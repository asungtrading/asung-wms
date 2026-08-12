// ============================================================
// PO 초과 클램프 — received > expected 면 인보이스 수량까지만 Cin7 에 쓴다
// (2026-08-10 사용자 결정 · 규칙 20 차이 처리 정책 개정)
// ------------------------------------------------------------
// 정책:
//   · 부족(received < expected) = 그대로 received 를 쓴다 (무변경)
//   · 초과(received > expected) = expected(인보이스 수량)까지만. 초과분은 Cin7 에 안 쓰고
//     recv_over discrepancy 로만 남는다 → 매니저가 Cin7 에서 수동 조정 (자동 조정 없음)
//   · ⚠️⚠️ SKU 합계 expected 0 = **전량 초과로 다룬다 — move 0 (2026-08-12 정책 반전, 규칙 20 정정 기록 참조).**
//     종전(2026-08-10~11) "공장 백오더 — 통과" 는 전제가 틀렸다: 공장 백오더는 물건만 따로 오지 않는다
//     (2026-08-12 사용자 확인). 인보이스에 없는데 온 물건 = 인보이스에 안 잡힌 초과분이고, Cin7 도 거부한다 —
//     실사고 PO-01027: expected 0 SKU 를 stock received 로 쏘자 400 "doesn't exist in purchase invoice",
//     2 bin 전부 실패·문서 DRAFT 잔류. move 0 이면 그 라인은 pending 0 → POST 그룹에서 빠져 400 원인이 소멸한다.
//     물건은 창고에만 있고 Cin7 반영은 매니저 수동 조정이 유일한 경로다(전량 recv_over 로 기록됨).
//   · ⚠️ expected_source='order'(구형 receipt · 인보이스 폴백)는 호출측이 clamp=false 로 부른다 —
//     오더 기준으로 자르면 정상 수량이 잘린다.
//
// ⚠️ 수식은 buildApplyPlan 트랜스퍼 절의 bin 이동 캡(Math.min budget 소진)과 쌍둥이고, 2026-08-12 부터
//    **expected 0 처리도 같아졌다**(둘 다 전량 제외 — 트랜스퍼는 물리적 강제, PO 는 정책 + PO-01027 실측:
//    Cin7 이 인보이스 밖 SKU 를 400 으로 거부하므로 사실상 물리적 강제이기도 하다). 종전 "정반대" 주석의
//    경위는 규칙 20 정정 기록에. 공용 헬퍼 통합은 트랜스퍼 경로가 다음에 열릴 때 별건(2026-08-10 결정).
//
// budget 소진 순서 = planLines 순서(= wms_receipt_lines id 순 = PO/인보이스 라인 순서) →
// 초과분은 **마지막 PO 라인부터** 잘린다. ⚠️ "마지막 bin 부터"로 읽지 말 것 — 작업자가 bin 을
// 채운 시각은 어느 컬럼에도 기록되지 않는다(2026-08-10 실측. updated_at 은 bin 변경·승인에도
// 갱신되는 **최종 수정 시각**이라 채움 순서 대용으로 부적격). id 순이 결정론적 대용물이고
// 트랜스퍼 캡과 같은 순서다. 진짜 시간 순서가 필요해지면 first_received_at 컬럼 신설이
// 선행돼야 한다(2026-08-10 판단 — 범위 증가라 지금은 만들지 않는다).
//
// 이 파일이 index.ts 에서 분리된 이유: index.ts 는 최상위 Deno.serve 라 import 만 해도 서버가 뜬다 —
// 합성 라인 테스트(po_clamp_test.ts, deno test — Cin7·DB 무접촉)가 순수 함수만 가져오기 위한 분리다.
// ⚠️ 실측 2026-08-10: 초과 PO 실물이 아직 없다(PO-01121 61라인 전부 일치) — 이 스위트가 유일한 사전 검증이다.
// ============================================================

// buildApplyPlan 의 planLines 원소 중 이 함수가 읽고/쓰는 필드만 명시한다.
export type PoPlanLine = {
  order_sku: string;
  qty_base: number;        // received (병합 합계) — 클램프해도 이 값은 안 바꾼다 (admin "capped" 대비 표시용)
  qty_units: number;       // in: received/factor (buildApplyPlan 이 정수 보증) → out: move_base/factor
  bin: string;
  exported_already?: number;
  move_base?: number;      // out: Cin7 에 실제로 쓰는 수량 (클램프됨) — markExported·POST 가 이 값을 쓴다
  pending_base?: number;   // out: 라인 all-or-nothing (exported_already >= move_base ? 0 : move_base)
};

export type PoCappedLine = { sku: string; bin: string; received: number; writes: number; cut: number };

// planLines 를 제자리에서 갱신(move_base·qty_units·pending_base)하고 잘린 라인 목록을 반환한다.
// expectedBySku = SKU(대문자) → expected_base 합. ⚠️ received 0 라인의 expected 도 포함한 전체 인보이스 합이어야
// 한다(트랜스퍼 expBySku 와 동일 집계 — discrepancy 의 bySku 는 rb>0 필터가 있어 다르다. 빠뜨리면 과잉 클램프).
// clamp=false 면 종전 PO 동작 그대로(move=received)다 — expected_source='order' 회귀 경로.
export function applyPoInvoiceClamp(
  planLines: PoPlanLine[],
  expectedBySku: Record<string, number>,
  clamp: boolean,
): PoCappedLine[] {
  const budget: Record<string, number> = {};
  for (const k in expectedBySku) budget[k] = Number(expectedBySku[k] || 0);
  const capped: PoCappedLine[] = [];
  for (const p of planLines) {
    const received = Number(p.qty_base);
    let move = received;
    if (clamp) {
      // expected 0 예외 없음(2026-08-12 정책 반전 — 위 헤더 주석): 인보이스에 없는 SKU 는 budget 0 → move 0.
      const k = String(p.order_sku).toUpperCase();
      const left = Math.max(0, Number(budget[k] || 0));
      move = Math.min(received, left);
      budget[k] = left - move;
      if (move < received) {
        capped.push({ sku: p.order_sku, bin: p.bin, received, writes: move, cut: received - move });
      }
    }
    // factor = received/units — buildApplyPlan 이 units 정수를 이미 보증했다. expected(인보이스 units×factor)와
    // received 가 모두 factor 배수라 move 도 배수가 보장되지만, 반올림 수량을 Cin7 에 쓰는 사고는 fail-loud 로 막는다.
    const factor = received / Number(p.qty_units);
    const units = move / factor;
    if (!Number.isInteger(units)) {
      throw new Error(p.order_sku + ": capped quantity " + move + " base units is not divisible by factor " + factor +
        " - refusing to write a rounded quantity to Cin7");
    }
    p.move_base = move;
    p.qty_units = units;
    // 라인 all-or-nothing (종전 PO 의미 유지): 부분 수량 재전송은 factor 로 안 나눠떨어질 수 있고,
    // 중복 재전송은 Cin7 이 400 "Cannot add duplicate value" 로 시끄럽게 거부한다.
    p.pending_base = Number(p.exported_already || 0) >= move ? 0 : move;
  }
  return capped;
}
