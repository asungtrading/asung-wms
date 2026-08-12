// ============================================================
// PO 초과 클램프 합성 라인 테스트 (2026-08-10 · 규칙 20 개정)
// ------------------------------------------------------------
// 실행:  deno test supabase/functions/receiving/po_clamp_test.ts
// Cin7·DB 무접촉 — buildApplyPlan 의 PO 분기가 쓰는 순수 함수(po_clamp.ts)만 검증한다.
// ⚠️ 2026-08-10 실측: 초과 PO 실물이 아직 없다(invoice 기준 receipt PO-01121 은 61라인 전부 일치)
//    — 이 스위트가 유일한 사전 검증 수단이다. 케이스 ①~⑧은 사용자 지정 최소 목록.
// ⚠️ index.ts 를 import 하지 말 것 — 최상위 Deno.serve 라 테스트가 서버를 띄운다(분리 이유).
// ============================================================

import { applyPoInvoiceClamp, type PoPlanLine } from "./po_clamp.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}

// buildApplyPlan 의 planLines 원소를 흉내낸 합성 라인. qty_units = received/factor (호출 전 보증과 동일).
function line(sku: string, bin: string, receivedBase: number, factor = 1, exported = 0): PoPlanLine {
  return {
    order_sku: sku, qty_base: receivedBase, qty_units: receivedBase / factor,
    bin, exported_already: exported,
  };
}

Deno.test("① 초과: 인보이스 10 · received 12 → move 10 · qty_units 10 · pending 10", () => {
  const ls = [line("SKU-A", "B01", 12)];
  const capped = applyPoInvoiceClamp(ls, { "SKU-A": 10 }, true);
  eq(ls[0].move_base, 10, "move_base");
  eq(ls[0].qty_units, 10, "qty_units");
  eq(ls[0].pending_base, 10, "pending_base");
  eq(ls[0].qty_base, 12, "qty_base 는 received 그대로 (admin capped 대비 표시용)");
  eq(capped, [{ sku: "SKU-A", bin: "B01", received: 12, writes: 10, cut: 2 }], "capped");
});

Deno.test("① 보강 — factor 4: 인보이스 40(=10units) · received 48 → move 40 · qty_units 10", () => {
  const ls = [line("SKU-F", "B01", 48, 4)];
  applyPoInvoiceClamp(ls, { "SKU-F": 40 }, true);
  eq(ls[0].move_base, 40, "move_base");
  eq(ls[0].qty_units, 10, "qty_units (base/factor)");
  eq(ls[0].pending_base, 40, "pending_base");
});

Deno.test("② 부족: 인보이스 10 · received 8 → move 8 (무변경)", () => {
  const ls = [line("SKU-A", "B01", 8)];
  const capped = applyPoInvoiceClamp(ls, { "SKU-A": 10 }, true);
  eq(ls[0].move_base, 8, "move_base");
  eq(ls[0].qty_units, 8, "qty_units");
  eq(ls[0].pending_base, 8, "pending_base");
  eq(capped, [], "capped 없음");
});

Deno.test("③ 일치: 10/10 → move 10", () => {
  const ls = [line("SKU-A", "B01", 10)];
  const capped = applyPoInvoiceClamp(ls, { "SKU-A": 10 }, true);
  eq(ls[0].move_base, 10, "move_base");
  eq(capped, [], "capped 없음");
});

Deno.test("④ expected 0 (인보이스에 없는 SKU): received 5 → move 0 전량 컷 — 2026-08-12 정책 반전(PO-01027)", () => {
  // ⚠️ 2026-08-12 에 ④ 를 정반대로 뒤집었다(종전: "공장 백오더 — move 5 통과"). 전제가 틀렸었다 —
  // 공장 백오더는 물건만 따로 오지 않는다(사용자 확인). 인보이스에 없는 SKU 를 쏘면 Cin7 이
  // 400 "doesn't exist in purchase invoice" 로 거부한다(실사고 PO-01027 — 2 bin 전멸·DRAFT 잔류).
  // 이 테스트를 다시 "통과"로 되돌리려는 사람은 규칙 20 정정 기록을 먼저 읽을 것.
  // 맵에 0 으로 있든 키가 아예 없든 동일해야 한다.
  for (const expMap of [{ "SKU-B": 0 }, {}]) {
    const ls = [line("SKU-B", "B02", 5)];
    const capped = applyPoInvoiceClamp(ls, expMap as Record<string, number>, true);
    eq(ls[0].move_base, 0, "move_base 0 (expMap=" + JSON.stringify(expMap) + ")");
    eq(ls[0].pending_base, 0, "pending_base 0 — POST 그룹에서 빠져 Cin7 무접촉");
    eq(capped, [{ sku: "SKU-B", bin: "B02", received: 5, writes: 0, cut: 5 }], "전량이 capped 로 기록");
  }
});

Deno.test("⑤ 멀티 bin: 같은 SKU 라인 2개(binA 6 · binB 6) · 인보이스 10 → A 6 · B 4 (뒤 라인부터 잘림)", () => {
  const ls = [line("SKU-A", "BIN-A", 6), line("SKU-A", "BIN-B", 6)];
  const capped = applyPoInvoiceClamp(ls, { "SKU-A": 10 }, true);
  eq(ls[0].move_base, 6, "binA move (앞 라인 온전)");
  eq(ls[1].move_base, 4, "binB move (budget 잔량만)");
  eq(ls[1].pending_base, 4, "binB pending");
  eq(capped, [{ sku: "SKU-A", bin: "BIN-B", received: 6, writes: 4, cut: 2 }], "capped 는 잘린 뒤 라인만");
});

Deno.test("⑥ expected_source='order' (clamp=false): 초과여도 클램프 없음 — 구형 receipt 회귀", () => {
  const ls = [line("SKU-A", "B01", 12)];
  const capped = applyPoInvoiceClamp(ls, { "SKU-A": 10 }, false);
  eq(ls[0].move_base, 12, "move_base = received (종전 동작)");
  eq(ls[0].qty_units, 12, "qty_units 무변");
  eq(ls[0].pending_base, 12, "pending_base = received");
  eq(capped, [], "capped 없음");
});

Deno.test("⑦ 재개: pending 은 클램프 기준 — exported=클램프값이면 0, 미만이면 전량(all-or-nothing)", () => {
  // 직전 회차가 클램프값 10 을 다 실었다 → pending 0 (재전송 없음)
  const done = [line("SKU-A", "B01", 12, 1, 10)];
  applyPoInvoiceClamp(done, { "SKU-A": 10 }, true);
  eq(done[0].pending_base, 0, "exported 10 >= move 10 → pending 0");
  // 체크포인트 일부만 남은 잔재(exported 4 < move 10) → 전량 pending (라인 all-or-nothing 유지)
  const part = [line("SKU-A", "B01", 12, 1, 4)];
  applyPoInvoiceClamp(part, { "SKU-A": 10 }, true);
  eq(part[0].pending_base, 10, "exported 4 < move 10 → pending 10 (전량)");
});

Deno.test("⑧ capped_to_invoice 내용이 실제 잘린 라인과 일치 (혼합 시나리오)", () => {
  const ls = [
    line("OVER-1", "B01", 12),          // 인보이스 10 → cut 2
    line("SHORT", "B02", 8),            // 인보이스 10 → 무변
    line("EXACT", "B03", 10),           // 인보이스 10 → 무변
    line("BACKORDER", "B04", 5),        // expected 0 → 전량 컷 (2026-08-12 정책 반전 — ④ 참조)
    line("MULTI", "B05", 6),            // 인보이스 10, 라인 2개 —
    line("MULTI", "B06", 6),            //   앞 6 + 뒤 4 → 뒤만 cut 2
  ];
  const capped = applyPoInvoiceClamp(ls, { "OVER-1": 10, "SHORT": 10, "EXACT": 10, "MULTI": 10 }, true);
  eq(capped, [
    { sku: "OVER-1", bin: "B01", received: 12, writes: 10, cut: 2 },
    { sku: "BACKORDER", bin: "B04", received: 5, writes: 0, cut: 5 },
    { sku: "MULTI", bin: "B06", received: 6, writes: 4, cut: 2 },
  ], "잘린 라인만, planLines 순서대로");
  eq(ls.map((l) => l.move_base), [10, 8, 10, 0, 6, 4], "각 라인 move_base");
});
