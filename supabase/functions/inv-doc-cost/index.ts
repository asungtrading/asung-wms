// ============================================================
// ASUNG 재고 원장 — Edge Function: inv-doc-cost (2026-09-10)
//   Cin7 트랜스퍼 운송비(stockTransfer.ManualJournals · IsSystem=false · Debit='_59_') → inv_doc_cost
//   ⭐ 문서 단위 금액을 **읽어서 upsert 만** 한다. 배분하지 않는다(아래 「하지 않는 것」).
//   스키마: 20260910141553_inv_doc_cost_transfer_freight.sql · 설계: docs/design/ledger-design.md §원가 레이어
//   「트랜스퍼 운송비 — 배분까지 완료 · 수집기는 미착수」 소절 · 방향 정본: docs/design/ims-principles.md
// ------------------------------------------------------------
// ═══ 왜 별도 EF 인가 (Caleb 판정 2026-09-10) — inv-cost 확장이 아니다 ═══
//  1. 대상 표가 다르다 — inv-cost 는 inv_cost, 이 EF 는 inv_doc_cost. 같은 EF 에 두면 한 함수가 두 표를 관리한다.
//  2. ⚠️ 커서 시계가 다르다 — 발주와 트랜스퍼의 LastModifiedOn 이 독립적으로 움직인다. 하나로 묶으면 **어느 쪽 때문에
//     커서가 멈췄나**를 못 가린다. ⇒ inv_sync_state.source_key = 'cost_transfer' ('cost' 와 독립).
//  3. ⚠️ inv-cost 는 입력 축이 purchaseList 하나로 박혀 있다 — doc_type 이 buildCostRows 의 rows.push 에 "purchase"
//     리터럴이고 DocMode 타입이 두 값으로 좁아 분기 셋을 고쳐야 한다 [보고 2026-09-10 · /tmp/inv-cost-report.md].
//
// ═══ 무엇을 하나 ═══
//  ① stockTransferList 순회(Status=COMPLETED) → ② 후보 문서 상세(stockTransfer?TaskID=) → ③ ManualJournals 에서
//  IsSystem=false · Debit='_59_' 만 추출 → ④ inv_doc_cost upsert(on_conflict = inv_doc_cost_uq).
//
// ═══ ⚠️⚠️ 커서 축은 LastModifiedOn 이다 — CompletionDate 로 잡으면 놓친다 ═══
//  [실측 2026-09-10] TR-04175 는 Completion 09-02 인데 저널이 **09-10 에 붙었다**(LastModifiedOn = 2026-09-10T15:32:06.049Z).
//  완료일 커서는 이미 지나가 있다. 저널 날짜(도착 +1~2일)와 문서 갱신 시점은 다른 시계다.
//  [실측 2026-08-31 · inv-collect] stockTransferList 행 1000/1000 에 LastModifiedOn 존재 · 빈 값 0.
//  ⬜ 미확인: stockTransferList 에 UpdatedSince 계열 파라미터가 있는지 — cin7-api 스킬(references/stock.md)의 문서화된
//     파라미터는 Page·Limit·Status·Search 넷뿐이고 inv-collect 도 transfer 를 전량 순회(②-a)한다. ⇒ **전체 순회 후 코드에서
//     LastModifiedOn 으로 거른다**(미확인 파라미터를 보내지 않는다 — 조용히 무시되면 전량이고 400 이면 회차가 죽는다).
//     [실측 2026-09-09] Search 는 문서번호로 안 걸린다 · 목록은 최근순이 아니다(TR-03975 가 6페이지) ⇒ 정렬에 기대지 않는다.
//  커서 형식·판정은 inv-cost 관례 복제: <LastModifiedOn>|<Number> tie-breaker(동일 타임스탬프 다건 · 2026-08-31 결함 C) ·
//  비캡 회차 = 회차 시작 시각 · 캡 회차 = 마지막 처리 문서의 키 · cursorStalled 증상 가드가 commit 을 차단한다.
//  ⚠️ 전량 목록이라 「정밀도 필터」가 곧 증분 필터다 — 키 < 커서 인 문서를 코드에서 거른다(inv-cost 의 UpdatedSince −1일 +
//  정밀도 필터와 같은 결과 · 서버 창이 없을 뿐). ?from_since=YYYY-MM-DD 는 커서 없을 때의 첫 시딩 하한 · ?recheck_since 는
//  커서 아래를 다시 태운다(커서는 뒤로 가지 않는다 · 캡이면 제자리).
//
// ═══ ⚠️⚠️ 문서 필터 — From <> To (GUID) 로 건다 · 이름으로 걸면 안 된다 ═══
//  FromLocation/ToLocation 은 「창고: bin」 형태라 bin 트랜스퍼가 섞인다. [실측 2026-09-09] 이름 필터 784건 vs GUID 12건.
//  GUID 를 하드코딩하지 않는다 — From <> To 가 더 일반적이고 창고가 늘어도 돈다. 같으면 skip_same_location.
//  Status 는 COMPLETED 만 본다(목록 Status 파라미터 · 문서화됨) — 저널은 완료 뒤에 붙으므로 좁혀도 놓치지 않는다(실측 둘 다 COMPLETED).
//  서버 필터가 새는 경우를 위해 코드에서도 확인한다(skip_not_completed · 0 이 아니면 신호).
//
// ═══ ⚠️⚠️ ManualJournals 추출 — IsSystem 이 관건 · 배열 길이로 판단하면 틀린다 ═══
//  원소 키 여섯 [실측]: Debit · Credit · Reference · Date · Amount · IsSystem
//    TR-03975  ARRAY(2)  [0] Debit=_1150040007_ · Credit=_59_ · Ref=TR-03975 · 08-26 · 4878.11 · IsSystem=true
//                        [1] Debit=_59_ · Credit=_136_ · Ref=B6900109 · 08-27 · 398.75 · IsSystem=false
//    TR-04175  ARRAY(1)  [0] Debit=_59_ · Credit=_136_ · Ref=B6913286 · 09-04 · 249.33 · IsSystem=false
//  · IsSystem=true 는 운송중 계정 이동(_1150040007_ ↔ _59_)이고 금액이 **재고 자체**(4,878.11) — 담지 않는다.
//  · TR-04175 는 시스템 저널이 아예 없어 1행이고 그것이 운송비 · TR-03975 는 2행 중 [1] ⇒ 길이가 아니라 IsSystem 으로.
//  · 거르는 조건 둘(AND): IsSystem === false · Debit === '_59_'(재고 계정). ⭐ 화이트리스트 — 블랙리스트(_95_ 제외)는 처음 보는
//    계정을 조용히 통과시킨다. IsSystem=false 인데 Debit ≠ '_59_' 면 skip_non_inventory_debit + warning 에 계정 코드
//    (0 이 아니게 되는 것이 신호 · 새 계정이 나타났다는 뜻).
//
// ═══ ⚠️ inv_doc_cost 유니크와 null ═══
//  inv_doc_cost_uq = (doc_type, doc_number, kind, ref_number, occurred_on). ⚠️ ref_number 가 null 이면 유니크가 안 걸린다
//  (Postgres null 취급) ⇒ Reference 가 비면 skip_no_reference 로 세고 **넣지 않는다**(넣으면 매 회차 중복이 쌓인다).
//  Amount 0 은 skip_zero_amount(넣지 않는다). ⚠️ 음수는 넣는다 — 정정일 수 있고 배분 단계(inv_layer_apply) 가드가 차단한다
//  (inv_doc_cost 에 amount >= 0 CHECK 를 일부러 안 걸었다). 같은 upsert 페이로드 안에 같은 5키가 두 번이면 PostgREST 가
//  거부하므로("cannot affect row a second time") 합산 1행 + merged_rows 카운트 + 경고 — ⬜ 같은 인보이스가 같은 날 두 줄로
//  오는 경우는 미확인(두 실측 문서 모두 1행)이라 그때 실물로 판단한다.
//  raw = 그 문서의 ManualJournals 배열 **전체**(IsSystem=true 포함) + 최소 문서 헤더 — 「왜 이 금액만 골랐나」를 되짚을 수 있게.
//
// ═══ ⚠️⚠️ 하지 않는 것 ═══
//  · inv_layer 를 읽지 않는다 · 배분하지 않는다. 배분은 inv_layer_apply 가 한다(20260910141553). 이유: ① 수집기가 inv_layer 를
//    읽으면 의존 방향이 역전된다(ims-principles: 모듈은 레고처럼 · 접점은 사건 하나) ② 배분 결과가 굳으면 레이어 규칙이 바뀌어도
//    안 바뀐다 = 불변 조건(§3 · 레이어 = inv_ledger + inv_cost + inv_doc_cost + inv_snapshot 으로 전량 재생성) 이 깨진다.
//  · inv_cost 를 건드리지 않는다(inv-cost 의 표) · Cin7 에 쓰지 않는다(GET 만) · 배포·cron 등록은 사람이 한다.
//
// 인증(x-wms-cron-key · fail-closed)·페이싱(1,200ms = 분당 50콜 · 60/60 한도의 여유분 · 키 공유)·캡(회차 40건 · 120초)·
// dry 기본/?commit=1·회차 로그(inv_collect_runs · source_key='cost_transfer' · dry 미기록)는 inv-cost 관례 그대로.
// _shared/cin7.ts 무변(바꾸면 소비 함수 전부 재배포).
import { cin7Get, sleep } from "../_shared/cin7.ts";

const COLLECTOR_VERSION = "inv-doc-cost@2026-09-10.1";   // 10.1 = 최초 — 트랜스퍼 운송비 문서 단위 수집(배분 없음)
const LIST_PAGE_LIMIT = 1000;
const MAX_LIST_PAGES = 12;
const LIST_SLEEP_MS = 400;
const DETAIL_SLEEP_MS = 1200;    // 분당 50콜 — 60/60 한도의 여유분(hello·receiving·inv-collect·inv-cost 와 키 공유)
const MAX_DETAIL_PER_RUN = 40;   // 1,200ms × 40 = 48초 < 60초 창 — 회차 캡(문서당 상세 1콜)
const TIME_BUDGET_MS = 120_000;  // 150초 idle timeout 앞에서 먼저 끊는다
const INSERT_BATCH = 500;
const SOURCE_KEY = "cost_transfer";                       // ⚠️ 'cost'(inv-cost) 와 독립 — 커서 시계가 다르다(헤더)
const DOC_CONFLICT = "doc_type,doc_number,kind,ref_number,occurred_on";   // = inv_doc_cost_uq 순서
const INVENTORY_DEBIT = "_59_";                            // 재고 계정 — 화이트리스트(헤더)

// ── Supabase REST 헬퍼 (inv-cost 와 같은 형태 — service_role 자동주입) ──
const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SB_KEY = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
function sbHeaders(extra: Record<string, string> = {}): HeadersInit {
  return { apikey: SB_KEY(), Authorization: "Bearer " + SB_KEY(), "Content-Type": "application/json", ...extra };
}
async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { headers: sbHeaders() });
  if (!r.ok) throw new Error("sbGet " + r.status + ": " + (await r.text()).slice(0, 300));
  return await r.json();
}
async function sbUpsert(table: string, conflictCol: string, rows: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + table + "?on_conflict=" + conflictCol, {
    method: "POST",
    headers: sbHeaders({ Prefer: "resolution=merge-duplicates,return=minimal" }),
    body: JSON.stringify(rows),
  });
  if (!r.ok) throw new Error("sbUpsert " + table + " " + r.status + ": " + (await r.text()).slice(0, 400));
}
// inv_doc_cost 쓰기 — ⚠️ upsert(merge-duplicates)다. amount 는 키에 없어 정정이 덮어쓴다(마이그레이션 헤더 A).
//   refreshed_at 을 매 행 명시 — merge 는 payload 에 있는 컬럼만 갱신하므로 DB default 에 맡기면 기존 행이 낡은 채 남는다.
async function writeDocCostRows(rows: Record<string, unknown>[], runIso: string): Promise<number> {
  let written = 0;
  for (let i = 0; i < rows.length; i += INSERT_BATCH) {
    const batch = rows.slice(i, i + INSERT_BATCH).map((r) => ({ ...r, refreshed_at: runIso }));
    await sbUpsert("inv_doc_cost", DOC_CONFLICT, batch);
    written += batch.length;
  }
  return written;
}

// ── 계산 핵심 (pure — scripts/test-invdoccost.mjs 가 이 구간을 원문 추출해 검증한다) ──
const dateOnly = (s: unknown): string | null => {
  const t = String(s ?? "").slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(t) ? t : null;
};
const norm = (s: unknown) => String(s ?? "").trim().toUpperCase();
const round6 = (x: number) => Math.round(x * 1e6) / 1e6;

type DocCostRow = {
  doc_type: string; doc_number: string; kind: string; amount: number; occurred_on: string;
  ref_number: string; debit_account: string | null; credit_account: string | null;
  collector: string; raw: Record<string, unknown>;
};
// 저널 행 단위 집계 — 문서 disposition(문서 수)과 단위가 다르다. processed 문서 안에서도 skip 된 행이 보여야 신호가 산다.
type JournalTally = { kept: number; system: number; non_inventory_debit: number; no_reference: number; zero_amount: number; bad_amount: number; no_date: number };
const emptyTally = (): JournalTally => ({ kept: 0, system: 0, non_inventory_debit: 0, no_reference: 0, zero_amount: 0, bad_amount: 0, no_date: 0 });

// 목록 레벨 disposition — 상세 조회 전에 정한다. ⚠️ 이름(FromLocation/ToLocation)이 아니라 GUID(From/To)로(헤더).
function listDisposition(row: any): string {
  if (norm(row?.Status) !== "COMPLETED") return "skip_not_completed";   // 서버 Status 필터가 새면 여기서 잡힌다(0 이 아니면 신호)
  const from = String(row?.From ?? "").trim(), to = String(row?.To ?? "").trim();
  if (!from || !to || from === to) return "skip_same_location";          // bin 이동(같은 창고) · GUID 없음도 창고간 이동으로 볼 수 없다
  return "candidate";
}

// 문서 하나 → inv_doc_cost 행들. 실패는 문서 단위 격리(다른 문서는 계속).
function buildDocCostRows(input: { docNo: string; det: any; row: any }): {
  rows: DocCostRow[]; disposition: string; warnings: string[]; tally: JournalTally; mergedRows: number;
} {
  const { docNo, det, row } = input;
  const warnings: string[] = [];
  const tally = emptyTally();
  // ManualJournals 는 배열 [실측] — inv-cost 와 같이 {Lines:[…]} 형태도 받아준다(방어)
  const mjArr: any[] = Array.isArray(det?.ManualJournals) ? det.ManualJournals
    : Array.isArray(det?.ManualJournals?.Lines) ? det.ManualJournals.Lines : [];
  const done = (disposition: string, rows: DocCostRow[] = [], mergedRows = 0) => ({ rows, disposition, warnings, tally, mergedRows });
  if (mjArr.length === 0) return done("skip_no_journal");

  const userRows = mjArr.filter((j: any) => j?.IsSystem === false);   // ⚠️ === false — 값이 없는 행은 시스템 저널로도 운송비로도 안 본다
  tally.system = mjArr.length - userRows.length;
  if (userRows.length === 0) return done("skip_system_only");          // 아직 운송비 인보이스가 매칭되지 않았다

  const raw = {
    manual_journals: mjArr,                                            // ⭐ 배열 전체(IsSystem=true 포함) — 「왜 이 금액만 골랐나」
    doc: {
      task_id: det?.TaskID ?? row?.TaskID ?? null, status: det?.Status ?? row?.Status ?? null,
      from: row?.From ?? null, to: row?.To ?? null,
      departure_date: det?.DepartureDate ?? row?.DepartureDate ?? null, completion_date: det?.CompletionDate ?? row?.CompletionDate ?? null,
      last_modified_on: row?.LastModifiedOn ?? det?.LastModifiedOn ?? null, cost_distribution_type: row?.CostDistributionType ?? null,
    },
    collector: COLLECTOR_VERSION,
  };
  const rows: DocCostRow[] = [];
  let firstSkip: string | null = null;   // 행이 하나도 안 남았을 때의 문서 disposition — 처음 걸린 사유
  const skipRow = (k: keyof JournalTally, disposition: string) => { tally[k]++; firstSkip ??= disposition; };
  for (const j of userRows) {
    const debit = String(j?.Debit ?? "").trim();
    if (debit !== INVENTORY_DEBIT) {
      // 화이트리스트 밖 — 새 계정이 나타났다는 신호. 조용히 통과시키지 않는다(헤더)
      skipRow("non_inventory_debit", "skip_non_inventory_debit");
      warnings.push(docNo + ": user journal with Debit '" + (debit || "(empty)") + "' (Credit '" + String(j?.Credit ?? "") + "', Ref '" + String(j?.Reference ?? "")
        + "', Amount " + String(j?.Amount) + ") is not the inventory account " + INVENTORY_DEBIT + " - skipped (skip_non_inventory_debit)");
      continue;
    }
    const ref = String(j?.Reference ?? "").trim();
    if (!ref) {
      // ref_number 는 유니크 키 — null 이면 유니크가 안 걸려 매 회차 중복이 쌓인다(헤더)
      skipRow("no_reference", "skip_no_reference");
      warnings.push(docNo + ": freight journal without Reference (Amount " + String(j?.Amount) + " @ " + String(j?.Date) + ") - skipped (skip_no_reference)");
      continue;
    }
    const amount = Number(j?.Amount);
    if (!Number.isFinite(amount)) { skipRow("bad_amount", "skip_bad_amount"); warnings.push(docNo + ": freight journal Ref '" + ref + "' has non-numeric Amount " + String(j?.Amount) + " - skipped"); continue; }
    if (amount === 0) { skipRow("zero_amount", "skip_zero_amount"); continue; }
    const occurredOn = dateOnly(j?.Date);
    if (!occurredOn) { skipRow("no_date", "skip_no_date"); warnings.push(docNo + ": freight journal Ref '" + ref + "' without Date - skipped"); continue; }
    tally.kept++;
    rows.push({
      doc_type: "transfer", doc_number: docNo, kind: "transfer_freight",
      amount: round6(amount),                 // ⚠️ 음수도 넣는다 — 배분 단계 가드가 차단한다(헤더)
      occurred_on: occurredOn,                // ⚠️ 저널 Date(인보이스 날짜)
      ref_number: ref,                        // ⭐ Service Invoice 번호
      debit_account: debit, credit_account: String(j?.Credit ?? "").trim() || null,
      collector: COLLECTOR_VERSION, raw,
    });
  }
  // 페이로드 안 5키 중복 — PostgREST 가 거부하므로 합산. 0 이 아니면 「같은 인보이스가 같은 날 두 줄」 표본이 나온 것(⬜ 헤더)
  const byKey = new Map<string, DocCostRow>();
  let mergedRows = 0;
  for (const r of rows) {
    const k = [r.doc_type, r.doc_number, r.kind, r.ref_number, r.occurred_on].join("\u0001");
    const cur = byKey.get(k);
    if (cur) { mergedRows++; cur.amount = round6(cur.amount + r.amount); } else byKey.set(k, r);
  }
  if (mergedRows) warnings.push(docNo + ": " + mergedRows + " duplicate (ref, date) journal line(s) merged into one row - first real sample of same-invoice-same-day, inspect raw");
  if (byKey.size === 0) return done(firstSkip ?? "skip_system_only");
  return done("processed", [...byKey.values()], mergedRows);
}
// ── 계산 핵심 끝 ──

// ── 커서 tie-breaker (inv-cost 의 복제 — 원본 inv-collect 「②-b 커서 tie-breaker (2026-08-30 결함 C)」 절) ──
// 커서 = <LastModifiedOn>|<Number>. LastModifiedOn 은 목록 원문 문자열 그대로(절대 시각으로 파싱하지 않는다).
// 비캡 회차 = 회차 시작 시각(ISO Z) · 캡 회차 = 마지막 처리 문서의 키 — 동률 그룹 안에서도 식별자로 전진.
// ⚠️ 코드유닛 비교(localeCompare 금지) — 필터·저장이 같은 순서여야 문서가 유실되지 않는다. null(LMO 없음)은 맨 앞 = 거르지 않는다.
type CursorCand = { updated: string | null };
function cursorDocIdent(row: any): string {
  return String(row?.Number ?? "").trim() || String(row?.TaskID ?? "").trim();
}
function cursorKeyOf(updated: string | null, ident: string): string | null {
  return updated ? updated + "|" + ident : null;
}
function cursorKeyCompare(a: string | null, b: string | null): number {
  const ka = a ?? "", kb = b ?? "";
  return ka < kb ? -1 : ka > kb ? 1 : 0;
}
function countUpdatedTies(cands: CursorCand[]): number {
  const freq = new Map<string, number>();
  for (const cd of cands) if (cd.updated) freq.set(cd.updated, (freq.get(cd.updated) ?? 0) + 1);
  let n = 0;
  for (const cd of cands) if (cd.updated && (freq.get(cd.updated) ?? 0) > 1) n++;
  return n;
}
// 증상 가드 — 「캡에 걸렸는데 커서가 안 나갔다」를 직접 본다(결함 A·B·C 공통 증상). stalled 면 commit 차단.
function decideCursor(detailCapped: boolean, lastProcessedKey: string | null, cursorBefore: string | null, runStartIso: string) {
  const cursorWouldBe = detailCapped ? (lastProcessedKey ?? cursorBefore) : runStartIso;
  const cursorStalled = detailCapped && String(cursorWouldBe ?? "") <= String(cursorBefore ?? "");
  return { cursorWouldBe, cursorStalled };
}

// ── 회차 로그 (inv_collect_runs · source_key='cost_transfer' — inv-cost buildCostRun 의 복제 · 규칙 변경은 함께) ──
// dry 미기록 · 차단 회차도 기록(ok=false) · 로그 실패가 수집을 막지 않는다. inv-doc-cost 에 없는 개념은 null.
function buildDocCostRun(out: Record<string, unknown>, warnings: string[], durationMs: number): Record<string, unknown> {
  const num = (v: unknown) => (v == null ? null : Number(v));
  const warnCapped = warnings.slice(0, 50);
  const summary: Record<string, unknown> = {};
  for (const k of Object.keys(out)) if (k !== "samples") summary[k] = k === "warnings" ? warnCapped : out[k];
  return {
    source_key: SOURCE_KEY,
    ok: out.write_skipped ? false : true,
    collector: COLLECTOR_VERSION,
    detail_capped: out.detail_capped === true,
    detail_capped_reason: out.detail_capped_reason ?? null,
    detail_capped_remaining: num(out.detail_capped_remaining) ?? 0,
    hold_capped: null,
    cursor_before: out.cursor_before ?? null,
    cursor_after: out.cursor_after ?? out.cursor_after_would_be ?? null,
    cursor_stalled_alert: out.cursor_stalled_alert ?? null,
    cursor_frozen_alert: null,
    list_total: num(out.list_total),
    list_received: num(out.list_received),
    pages: num(out.pages),
    truncated: out.truncated ?? null,
    list_aborted: out.list_aborted ?? null,
    candidates: num(out.candidates),
    docs_processed: num(out.docs_processed),
    detail_fetched: num(out.detail_fetched),
    ledger_rows: null,
    inserted: null,
    insert_skipped: null,
    skipped_unchanged: null,
    precision_skipped: num(out.precision_skipped),
    write_skipped: out.write_skipped ?? null,
    dispositions: out.dispositions ?? null,
    warnings: warnCapped,
    summary,
    duration_ms: durationMs,
  };
}
async function writeCollectRun(row: Record<string, unknown>): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/inv_collect_runs", {
    method: "POST",
    headers: sbHeaders({ Prefer: "return=minimal" }),
    body: JSON.stringify([row]),
  });
  if (!r.ok) throw new Error("sbInsert inv_collect_runs " + r.status + ": " + (await r.text()).slice(0, 400));
}

Deno.serve(async (req) => {
  const t0 = Date.now();
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "x-wms-cron-key, content-type" } });
    }
    // ── 인증 (fail-closed — inv-collect·inv-cost 동일 · WMS_CRON_SECRET 공유) ──
    const secret = Deno.env.get("WMS_CRON_SECRET") ?? "";
    if (!secret) return json({ ok: false, error: "WMS_CRON_SECRET not configured - refusing (fail-closed)" }, 500);
    if ((req.headers.get("x-wms-cron-key") ?? "") !== secret) return json({ ok: false, error: "unauthorized" }, 401);

    // ── 파라미터 (관례: 기본 dry · ?commit=1 이 있어야 쓴다) ──
    const url = new URL(req.url);
    const commit = url.searchParams.get("commit") === "1";
    const fromSince = (url.searchParams.get("from_since") ?? "").trim() || null;   // 커서 없을 때의 첫 시딩 하한(LastModifiedOn 날짜)
    if (fromSince && !/^\d{4}-\d{2}-\d{2}$/.test(fromSince)) return json({ ok: false, error: "from_since must be YYYY-MM-DD" }, 400);
    // ?recheck_since=YYYY-MM-DD — 커서 아래 문서를 다시 태운다(이 날짜 이후 LastModifiedOn 전부 · 필터 끔). 커서는 손대지 않는다 —
    //   비캡 회차면 회차 시작 시각으로 전진(재조회 창 ⊇ 평시 창 · 중복은 upsert 흡수) · 캡 회차면 제자리(뒤로 가지 않는다).
    const recheckSince = (url.searchParams.get("recheck_since") ?? "").trim() || null;
    if (recheckSince && !/^\d{4}-\d{2}-\d{2}$/.test(recheckSince)) return json({ ok: false, error: "recheck_since must be YYYY-MM-DD" }, 400);
    const timeLeft = () => TIME_BUDGET_MS - (Date.now() - t0);
    const warnings: string[] = [];

    // ── 커서 (inv_sync_state · source_key='cost_transfer') ──
    const stateRows = await sbGet("inv_sync_state?source_key=eq." + SOURCE_KEY + "&select=source_key,last_cursor");
    const cursorBefore: string | null = stateRows[0]?.last_cursor ?? null;
    let sinceSource: "state" | "param" | "recheck" | "none" = "none";
    if (recheckSince) sinceSource = "recheck";
    else if (cursorBefore) sinceSource = "state";
    else if (fromSince) sinceSource = "param";
    if (sinceSource === "none") warnings.push("NO CURSOR - every COMPLETED transfer is a candidate (pass ?from_since=2026-08-20 or seed inv_sync_state '" + SOURCE_KEY + "'); the detail cap will page through them run by run");
    if (recheckSince) warnings.push("RECHECK_SINCE=" + recheckSince + " - candidates widened below cursor (" + cursorBefore + "), cursor filter off for this run; cursor is not moved backwards");
    // 코드 측 하한 — 전량 목록이라 서버 창이 없다(헤더). recheck > 커서 > from_since. 커서는 <LMO>|<Number> 키 비교 · 나머지는 날짜(앞 10자) 비교.
    const lmoFloorDate: string | null = recheckSince ?? (cursorBefore ? null : fromSince);

    // ── 1) 목록 — stockTransferList 전량(Status=COMPLETED) · 최근순이 아니므로 끝까지 받는다 ──
    let listTotal: number | null = null, listReceived = 0, pages = 0;
    const listRows: any[] = [];
    let listAborted: string | null = null;
    let rateLimited = false;
    for (let page = 1; page <= MAX_LIST_PAGES; page++) {
      if (timeLeft() < 0) { listAborted = "time"; break; }
      let j: any;
      try {
        j = await cin7Get("/stockTransferList?Page=" + page + "&Limit=" + LIST_PAGE_LIMIT + "&Status=" + encodeURIComponent("COMPLETED"));
      } catch (e: any) {
        if (Number(e?.status) === 429) { rateLimited = true; listAborted = "rate_limited"; }
        else listAborted = "page_error: " + String(e?.message ?? e).slice(0, 200);
        break;
      }
      pages++;
      if (j?.Total != null) listTotal = Number(j.Total);
      const batch = (j?.StockTransferList ?? []) as any[];
      listReceived += batch.length;
      listRows.push(...batch);
      if (batch.length < LIST_PAGE_LIMIT) break;
      await sleep(LIST_SLEEP_MS);
    }
    const truncated = listTotal == null ? null : listReceived < listTotal;

    // ── 2) 후보 — 하한(날짜) → 목록 disposition → 키 정렬 → 커서 필터 ──
    //   ⚠️ 목록 disposition 은 하한 안의 행만 센다 — 전량 목록에서 매 회차 「같은 창고 이동 772건」을 세면 기준선을 외우게 된다.
    const dispositions: Record<string, number> = {};
    const tally = (k: string) => { dispositions[k] = (dispositions[k] ?? 0) + 1; };
    const cands: { row: any; updated: string | null; key: string | null }[] = [];
    let belowFloor = 0, lmoMissing = 0;
    for (const row of listRows) {
      const updated = String(row?.LastModifiedOn ?? "").trim() || null;
      if (!updated) lmoMissing++;   // [실측 2026-08-31] 1000/1000 존재 — 0 이 아니면 신호(그 문서는 매 회차 후보가 된다 · 유실 방지 방향)
      if (lmoFloorDate && updated && updated.slice(0, 10) < lmoFloorDate) { belowFloor++; continue; }
      const d = listDisposition(row);
      if (d !== "candidate") { tally(d); continue; }
      cands.push({ row, updated, key: cursorKeyOf(updated, cursorDocIdent(row)) });
    }
    cands.sort((a, b) => cursorKeyCompare(a.key, b.key));
    // 커서 필터 = 증분 (inv-cost 의 정밀도 필터와 같은 비교 · 키 < 커서 는 이미 본 문서). recheck 회차는 끔.
    let precisionSkipped = 0;
    if (!recheckSince && cursorBefore) {
      const kept: typeof cands = [];
      for (const cd of cands) {
        if (cd.key && cd.key < cursorBefore) { precisionSkipped++; continue; }
        kept.push(cd);
      }
      cands.length = 0;
      cands.push(...kept);
    }
    const updatedTies = countUpdatedTies(cands);

    // ── 3) 상세 → 운송비 행 ──
    const allRows: DocCostRow[] = [];
    const journal = emptyTally();
    let detailFetched = 0, docsProcessed = 0, mergedRows = 0;
    let detailCapped = false, detailCapReason: string | null = null, cappedRemaining = 0;
    let lastProcessedKey: string | null = null;
    for (let i = 0; i < cands.length; i++) {
      if (detailFetched >= MAX_DETAIL_PER_RUN) { detailCapped = true; detailCapReason = "max_detail"; cappedRemaining = cands.length - i; break; }
      if (timeLeft() < 5_000) { detailCapped = true; detailCapReason = "time"; cappedRemaining = cands.length - i; break; }
      const cd = cands[i];
      const id = String(cd.row?.TaskID ?? "").trim();
      let det: any;
      try {
        det = await cin7Get("/stockTransfer?TaskID=" + encodeURIComponent(id));
        detailFetched++;
        await sleep(DETAIL_SLEEP_MS);
      } catch (e: any) {
        // 상세 오류 = 캡과 같은 정지 — 지나치면 그 문서가 조용히 유실된다(커서가 넘어간다)
        if (Number(e?.status) === 429) { rateLimited = true; detailCapReason = "rate_limited"; }
        else { detailCapReason = "detail_error"; warnings.push("detail error " + String(cd.row?.Number ?? id) + ": " + String(e?.message ?? e).slice(0, 200)); }
        detailCapped = true;
        cappedRemaining = cands.length - i;
        break;
      }
      const docNo = String(det?.Number ?? cd.row?.Number ?? "").trim();
      const r = buildDocCostRows({ docNo, det, row: cd.row });
      tally(r.disposition);
      warnings.push(...r.warnings);
      mergedRows += r.mergedRows;
      for (const k of Object.keys(journal) as (keyof JournalTally)[]) journal[k] += r.tally[k];
      if (r.disposition === "processed") { docsProcessed++; allRows.push(...r.rows); }
      if (cd.key) lastProcessedKey = cd.key;
    }

    // ── 커서 (inv-cost 동형): 비캡 = 회차 시작 시각 · 캡 = 마지막 처리 문서의 키 ──
    const runStartIso = new Date(t0).toISOString();
    let { cursorWouldBe, cursorStalled } = decideCursor(detailCapped, lastProcessedKey, cursorBefore, runStartIso);
    if (recheckSince && detailCapped) {
      cursorWouldBe = cursorBefore;
      cursorStalled = false;
      warnings.push("RECHECK capped - cursor held at " + cursorBefore + "; re-run with a later recheck_since to cover the remaining " + cappedRemaining + " doc(s)");
    }
    const cappedNoUpdated = detailCapped && lastProcessedKey == null;
    if (cursorStalled) warnings.push("CURSOR STALLED - capped and cursor would not advance (cursorBefore=" + cursorBefore + ", wouldBe=" + cursorWouldBe + ") - transfer freight collection is frozen; commit is blocked");
    if (journal.non_inventory_debit) warnings.push("SIGNAL: " + journal.non_inventory_debit + " user journal line(s) with a non-inventory Debit account were skipped - a new account appeared, inspect warnings above");
    if (journal.no_reference) warnings.push("SIGNAL: " + journal.no_reference + " freight journal line(s) without Reference were skipped (would break inv_doc_cost_uq)");

    // ── 4) commit — 쓰기 성공 뒤에만 커서 전진 ──
    let rowsWritten: number | null = null;
    let writeSkipped: string | null = null;
    if (commit) {
      if (listAborted) writeSkipped = "list_aborted: " + listAborted;
      else if (truncated) writeSkipped = "list truncated";
      else if (cappedNoUpdated) writeSkipped = "capped with no usable LastModifiedOn - cursor would freeze";
      else if (cursorStalled) writeSkipped = "capped and cursor would not advance (cursorBefore=" + cursorBefore + ", wouldBe=" + cursorWouldBe + ") - transfer freight collection is frozen";
      if (!writeSkipped) {
        rowsWritten = await writeDocCostRows(allRows as unknown as Record<string, unknown>[], new Date().toISOString());
        await sbUpsert("inv_sync_state", "source_key", [{
          source_key: SOURCE_KEY,
          last_cursor: cursorWouldBe,
          last_run_at: new Date().toISOString(),
          last_ok_at: new Date().toISOString(),
          note: COLLECTOR_VERSION + " rows=" + allRows.length + (detailCapped ? " capped" : ""),
        }]);
      }
    }
    // commit 블록 끝 — ⚠️ writeDocCostRows 호출은 위 블록 안 한 곳뿐이다(dry 는 절대 쓰지 않는다)

    const out: Record<string, unknown> = {
      ok: true,
      mode: commit ? "commit" : "dry",
      collector_version: COLLECTOR_VERSION,
      source_key: SOURCE_KEY,
      list_total: listTotal,
      list_received: listReceived,
      pages,
      truncated,
      list_aborted: listAborted,
      rate_limited: rateLimited,
      lmo_floor_date: lmoFloorDate,          // 코드 측 날짜 하한(recheck_since / from_since) · 커서 회차는 null(키 필터가 대신한다)
      below_floor: belowFloor,
      lmo_missing: lmoMissing,               // LastModifiedOn 없는 목록 행 — [실측] 0 · 0 이 아니면 신호
      dispositions,
      candidates: cands.length,
      precision_skipped: precisionSkipped,   // 키 < 커서 (이미 본 문서)
      updated_ties: updatedTies,             // 동률 그룹 조기 신호 — 캡보다 커지면 결함 C 상황(가드가 잡는다)
      detail_fetched: detailFetched,
      detail_capped: detailCapped,
      detail_capped_reason: detailCapReason,
      detail_capped_remaining: cappedRemaining,
      docs_processed: docsProcessed,
      rows_built: allRows.length,
      rows_written: rowsWritten,
      write_skipped: writeSkipped ?? undefined,
      journal_lines: journal,                // 저널 행 단위 집계(kept·system·non_inventory_debit·no_reference·zero_amount·bad_amount·no_date)
      merged_rows: mergedRows,               // 같은 (ref, date) 두 줄 합산 — ⬜ 표본 없음 · 0 이 아니면 첫 실물
      amount_built: round6(allRows.reduce((s, r) => s + r.amount, 0)),
      recheck_since: recheckSince,
      cursor_before: cursorBefore,
      cursor_after: commit && !writeSkipped ? cursorWouldBe : cursorBefore,
      cursor_after_would_be: cursorWouldBe,
      cursor_held_by: detailCapped ? "capped:" + detailCapReason + " - cursor held at last processed doc's cursor key" : null,
      cursor_stalled_alert: cursorStalled
        ? "capped and cursor would not advance (cursorBefore=" + cursorBefore + ", wouldBe=" + cursorWouldBe + ") - transfer freight collection is frozen; commit is blocked"
        : undefined,
      cursor_source: sinceSource,
      samples: allRows.slice(0, 5),
      warnings,
      duration_ms: Date.now() - t0,
    };

    // 회차 로그 (inv_collect_runs source_key='cost_transfer' — dry 미기록 · 차단 회차도 기록 · 실패는 경고만)
    if (commit) {
      try {
        await writeCollectRun(buildDocCostRun(out, warnings, Date.now() - t0));
        out.collect_run_logged = true;
      } catch (e: any) {
        out.collect_run_logged = false;
        out.collect_run_error = String(e?.message ?? e).slice(0, 200);
        warnings.push("collect-run log failed (freight collection unaffected): " + out.collect_run_error);
      }
    } else out.collect_run_logged = false;
    return json(out);
  } catch (e) {
    return json({ ok: false, error: String(e).slice(0, 500), duration_ms: Date.now() - t0 }, 500);
  }
});

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj, null, 2), {
    status, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}
