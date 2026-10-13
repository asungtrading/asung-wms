// ============================================================
// ASUNG IMS — 나가지 않을 몫 · Shopify 오더 고치기 순수 함수 · 쿼리 (_shared · ful-4b · 2026-10-13 · 판정 439 · 441 · 457 ~ 462 · DB ful-4a 20261014000000)
//   order_drain 이 쓴다 — 네트워크 · DB 없음(deno test). 흐름(index.ts orderDrain):
//   · 큐 shop_order_queue(kind order_edit · 열린 줄 · queued_at 순 · ≤ 20 · 40 s) → 오더마다 ① Shopify 오더 줄(currentQuantity · unfulfilledQuantity · 취소 · 결제 상태)을 실시간으로 읽고
//     ② can_ship 은 DB 에서 그 순간 다시 센다(rpc shop_order_can_ship · 장부 값은 스캔 때 것 — §0 이견 2) ③ 취소된 오더 · 돈 받은 오더(PAID · PARTIALLY_PAID · PARTIALLY_REFUNDED · 판정 457)는 skipped(다음 스캔이 refund_due 길로)
//     ④ planOrderEdit: 줄마다 to_remove = max(unfulfilled − can_ship, 0) · new_quantity = current − to_remove · 전부 0 이면 받아 적기(removed_qty 만 맞추고 done ok)
//     ⑤ orderEditBegin → 줄 짝(matchCalcLine: variant.id + sku 가 하나 · 아니면 숫자 id · 아니면 못 고른다 → error) → editableQuantity 로 한 번 더 자르고(clampEditable) orderEditSetQuantity(restock true · 판정 459) → orderEditCommit(notifyCustomer false · 판정 441)
//     ⑥ removed_qty = shop_order_line.quantity − currentQuantity(commit 뒤) · shop_order.last_push_at(메아리 ⓑ) · 큐 done · 5 회 실패면 경고 order_edit_failed
//   📌 문서(2026-10-13 MCP): orderEditCommit 「If notifyCustomer is set to true, then an email invoice … is sent」 · 「You can only edit unfulfilled line items」 · 세션은 「until you commit or abandon them」(버리는 mutation 없음 · 안 commit 하면 끝 · 짐작)
//   📌 짐작(Caleb 시험에서 확인): unfulfilledQuantity = currentQuantity − 보낸 수량 · CalculatedLineItem 숫자 id = LineItem 숫자 id · 안 commit 한 세션은 오더에 영향 없음
//   ⚠️ 실물 #1011(2026-10-13 · 일부 발송 줄 2 중 1 나감): currentQuantity − to_remove(= 1) 을 setQuantity 로 보냈더니 commit 이 「There must be at least one change」 — CalculatedLineItem.quantity 가 전체(2)가 아니라 1 이었다고 본다(짐작 · order_edit_preview 로 확인)
//     → setQuantity 값은 calc 기준(setQuantityFor: calc.quantity − to_remove · 바닥 = calc.quantity − editableQuantity) · 바뀌는 줄이 0 이면 commit 을 보내지 않고 NoChangeError(큐 done error 한 번 · 경고 order_edit_failed · retry 아님)
// ============================================================

export const ORDER_EDIT_FETCH = 20;
export const ORDER_EDIT_MS = 40_000;
export const ORDER_EDIT_MAX_ATTEMPTS = 5;
export const PAID_STATUSES = ["PAID", "PARTIALLY_PAID", "PARTIALLY_REFUNDED"] as const;    // 판정 457 — 돈 받음 = 고치지 않는다
export const ORDER_EDIT_STAFF_NOTE = "IMS: not shipping — backorder closed (quantity reduced by IMS)";

// ── GraphQL(2026-10 · MCP validate ✅ VALID · 권한 write_order_edits(앱 버전에 더한다) · read_orders) ──
export const ORDER_LINES_QUERY = `query ImsOrderLines($id: ID!) { order(id: $id) { id name cancelledAt closed displayFinancialStatus displayFulfillmentStatus updatedAt totalOutstandingSet { shopMoney { amount currencyCode } }
  lineItems(first: 250) { nodes { id sku quantity currentQuantity unfulfilledQuantity variant { id } } }
  fulfillmentOrders(first: 20) { nodes { id status deliveryMethod { methodType } lineItems(first: 100) { nodes { id remainingQuantity lineItem { id } } } } } } }`;
export const ORDER_EDIT_BEGIN_MUTATION = `mutation ImsOrderEditBegin($id: ID!) { orderEditBegin(id: $id) { calculatedOrder { id totalOutstandingSet { shopMoney { amount currencyCode } } stagedChanges(first: 20) { nodes { __typename } }
  lineItems(first: 250) { nodes { id sku quantity editableQuantity editableQuantityBeforeChanges restockable variant { id } } }
  originalOrder { id name cancelledAt displayFinancialStatus lineItems(first: 250) { nodes { id sku quantity currentQuantity variant { id } } } } } userErrors { field message } } }`;
// ful-4b2: 선택 집합을 넓혔다(validate ✅ 2026-10-13) — stagedChanges · 세션의 줄 전부 · editableQuantityBeforeChanges · restocking · subtotalLineItemsQuantity. order_drain 은 여기서 userErrors 만 읽는다(코드 무변)
export const ORDER_EDIT_SET_QTY_MUTATION = `mutation ImsOrderEditSetQuantity($id: ID!, $lineItemId: ID!, $quantity: Int!, $restock: Boolean) { orderEditSetQuantity(id: $id, lineItemId: $lineItemId, quantity: $quantity, restock: $restock) { calculatedOrder { id totalOutstandingSet { shopMoney { amount currencyCode } } subtotalLineItemsQuantity stagedChanges(first: 20) { nodes { __typename ... on OrderStagedChangeDecrementItem { delta restock lineItem { id } } } } lineItems(first: 250) { nodes { id sku quantity editableQuantity editableQuantityBeforeChanges restockable restocking } } } calculatedLineItem { id quantity editableQuantity editableQuantityBeforeChanges restocking } userErrors { field message } } }`;
export const ORDER_EDIT_COMMIT_MUTATION = `mutation ImsOrderEditCommit($id: ID!, $notify: Boolean, $note: String) { orderEditCommit(id: $id, notifyCustomer: $notify, staffNote: $note) { order { id updatedAt displayFinancialStatus displayFulfillmentStatus totalOutstandingSet { shopMoney { amount currencyCode } } lineItems(first: 250) { nodes { id quantity currentQuantity } } } userErrors { field message } } }`;

// ── 모양 ──
export type LiveLine = { id: string; sku?: string | null; quantity: number; currentQuantity: number; unfulfilledQuantity: number; variant?: { id: string } | null };
export type CalcLine = { id: string; sku?: string | null; quantity: number; editableQuantity: number; editableQuantityBeforeChanges?: number; restockable?: boolean; variant?: { id: string } | null };
export type DbLine = { shop_order_line_id: string; line_gid: string; quantity: number | string; can_ship: number | string };
export type EditPlan = { line_gid: string; shop_order_line_id: string; current: number; unfulfilled: number; can_ship: number; to_remove: number; new_quantity: number };
export type Plan = { edits: EditPlan[]; total_remove: number; missing: string[] };

const n = (v: unknown): number => { const x = Number(v); return Number.isFinite(x) ? x : 0; };
const num = (gid: string): string => String(gid ?? "").split("/").pop() ?? "";
export const isPaid = (status: string | null | undefined): boolean => (PAID_STATUSES as readonly string[]).includes(String(status ?? "").toUpperCase());

// ── ④ 줄마다 지울 몫 — to_remove = max(unfulfilled − can_ship, 0) · new = current − to_remove · DB 줄이 Shopify 에 없으면 missing(지우지 않는다) ──
export function planOrderEdit(dbLines: DbLine[], live: LiveLine[]): Plan {
  const byGid = new Map(live.map((l) => [l.id, l]));
  const plan: Plan = { edits: [], total_remove: 0, missing: [] };
  for (const d of dbLines) {
    const l = byGid.get(d.line_gid);
    if (!l) { plan.missing.push(d.line_gid); continue; }
    const current = Math.max(Math.floor(n(l.currentQuantity)), 0);
    const unfulfilled = Math.min(Math.max(Math.floor(n(l.unfulfilledQuantity)), 0), current);
    const can = Math.max(Math.floor(n(d.can_ship)), 0);
    const to_remove = Math.max(unfulfilled - can, 0);
    plan.edits.push({ line_gid: d.line_gid, shop_order_line_id: d.shop_order_line_id, current, unfulfilled, can_ship: can, to_remove, new_quantity: current - to_remove });
    plan.total_remove += to_remove;
  }
  return plan;
}

// ── ⑤ 줄 짝 — variant.id + sku 가 하나면 그것 · 둘 이상이면 숫자 id 가 같은 것 · 못 고르면 null(부르는 쪽이 error · 다시 시도 안 함) ──
export function matchCalcLine(live: LiveLine, calc: CalcLine[]): CalcLine | null {
  const vid = live.variant?.id ?? null, sku = String(live.sku ?? "").trim();
  const same = calc.filter((c) => (vid ? c.variant?.id === vid : !c.variant?.id) && String(c.sku ?? "").trim() === sku);
  if (same.length === 1) return same[0];
  const pool = same.length > 1 ? same : calc;
  const byId = pool.filter((c) => num(c.id) === num(live.id));
  return byId.length === 1 ? byId[0] : null;
}
// ⑤ setQuantity 에 보낼 값 — calc 기준: calc.quantity − to_remove · 바닥 = calc.quantity − editableQuantity(이미 나간 몫 · 문서 「only unfulfilled line items」) · change = 실제로 줄어드는 양(0 이면 그 줄은 안 보낸다)
export function setQuantityFor(calc: CalcLine, toRemove: number): { quantity: number; change: number; clamped: boolean } {
  const cq = Math.max(Math.floor(n(calc.quantity)), 0), floor = Math.max(cq - Math.floor(n(calc.editableQuantity)), 0);
  const want = Math.max(cq - Math.max(Math.floor(toRemove), 0), 0);
  const quantity = Math.max(want, floor);
  return { quantity, change: cq - quantity, clamped: quantity !== want };
}
export class NoChangeError extends Error { constructor(msg: string) { super(msg); this.name = "NoChangeError"; } }
// (ful-4b 첫 판 · 남겨 둠) editableQuantity 로 한 번 더 자른다 — 이미 발송된 몫(quantity − editable)보다 아래로는 못 줄인다
export function clampEditable(newQuantity: number, calc: CalcLine): { quantity: number; clamped: boolean } {
  const floor = Math.max(n(calc.quantity) - n(calc.editableQuantity), 0);
  return newQuantity < floor ? { quantity: floor, clamped: true } : { quantity: newQuantity, clamped: false };
}
// ⑥ removed_qty = 원래 수량(shop_order_line.quantity) − 지금 수량(currentQuantity) — 우리가 지운 것 · Shopify 에서 지워진 것이 같이 잡힌다(§0 이견 3)
export const removedQty = (dbQuantity: number | string, currentQuantity: number | string): number => Math.max(n(dbQuantity) - n(currentQuantity), 0);
export const userErrorsText = (errs: Array<{ field?: string[] | null; message?: string }> | null | undefined): string =>
  (errs ?? []).map((e) => (e.field?.length ? e.field.join(".") + ": " : "") + (e.message ?? "")).join(" · ");

// ── ful-4b2 · try-set(원인 확인만 · commit 없음 · 세션은 버린다) ──────────────────────────────────────────
//   실물 #1011: live {quantity 2 · currentQuantity 2 · unfulfilledQuantity 1} · calc {quantity 2 · editableQuantity 1} · to_remove 1 · 첫 판은 1 을 보내 commit 「There must be at least one change」
//   문서(2026-10-13 MCP 원문): setQuantity.quantity 「The new quantity to set for the line item. This value cannot be negative.」 · CalculatedLineItem.quantity 「The total number of items.」 ·
//   editableQuantity 「The total number of items that can be edited.」 · orderEditCommit 「You can only edit unfulfilled line items.」 — 전체 기준인지 고칠 수 있는 몫 기준인지는 어느 문장도 말하지 않는다 ⇒ 후보 둘을 세션 따로 열어 보낸다
//   ⓐ quantity = editableQuantity − to_remove(#1011 에서 0) · ⓑ quantity = calc.quantity − to_remove(setQuantityFor · #1011 에서 1) · 둘이 같으면(발송분 0) ⓑ 는 열지 않고 same_as_a
//   세션을 버리는 뮤테이션은 없다(orderEdit* 11 개 확인) — begin 이 같은 세션을 돌려주면(id 가 앞과 같거나 staged 가 0 이 아니면) 그대로 돌리되 contaminated: true(숨기지 않는다 · 그것도 실물)
export type TrySetKey = "a" | "b";
export const TRY_SET_RULE: Record<TrySetKey, string> = { a: "editableQuantity - to_remove", b: "calc.quantity - to_remove" };
export function trySetCandidates(calc: CalcLine, toRemove: number): Record<TrySetKey, { quantity: number; clamped: boolean }> {
  const ed = Math.max(Math.floor(n(calc.editableQuantity)), 0), tr = Math.max(Math.floor(toRemove), 0);
  const a = { quantity: Math.max(ed - tr, 0), clamped: ed - tr < 0 };
  const b = setQuantityFor(calc, tr);
  return { a, b: { quantity: b.quantity, clamped: b.clamped } };
}
export type GqlLike = (query: string, variables: Record<string, unknown>) => Promise<{ ok: boolean; status: number; data: unknown; errors: unknown; raw: string | null; cost: { actual: number | null } }>;
export type TrySetSend = { line_gid: string; sku: string | null; to_remove: number; calc_line_id: string | null; calc_at_begin: CalcLine | null; quantity_sent: number | null; clamped: boolean; skipped: string | null;
  response: { ok: boolean; status: number; user_errors: unknown; calculated_line_item: unknown; calculated_order: unknown; staged_count: number | null; errors: unknown } | null };
export type TrySetResult = { key: TrySetKey; rule: string; same_as_a?: true; calculated_order_id: string | null; staged_at_begin: number | null; contaminated: boolean; contaminated_reason: string | null;
  calc_lines_at_begin: CalcLine[]; begin_user_errors: unknown; sends: TrySetSend[]; cost: number };
type BeginData = { orderEditBegin?: { calculatedOrder?: { id: string; stagedChanges?: { nodes?: Array<{ __typename?: string }> }; lineItems?: { nodes?: CalcLine[] } } | null; userErrors?: unknown } };
type SetData = { orderEditSetQuantity?: { calculatedOrder?: { stagedChanges?: { nodes?: unknown[] } } | null; calculatedLineItem?: unknown; userErrors?: unknown } };
// 후보마다 begin 을 따로 → 줄마다 setQuantity(restock true · 판정 459) → 응답을 그대로 모은다. commit 은 절대 부르지 않는다(테스트가 호출 목록으로 확인).
// seenCalcIds: 앞서 연 세션 id(preview 의 begin 포함) — 같은 id 가 다시 오면 contaminated
export async function runTrySet(gql: GqlLike, orderGid: string, plan: Plan, live: LiveLine[], seenCalcIds: string[] = []): Promise<TrySetResult[]> {
  const edits = plan.edits.filter((e) => e.to_remove > 0);
  const seen = [...seenCalcIds];
  const results: TrySetResult[] = [];
  const begin = async (key: TrySetKey): Promise<TrySetResult> => {
    const gb = await gql(ORDER_EDIT_BEGIN_MUTATION, { id: orderGid });
    const co = (gb.data as BeginData | null)?.orderEditBegin?.calculatedOrder ?? null;
    const r: TrySetResult = { key, rule: TRY_SET_RULE[key], calculated_order_id: co?.id ?? null, staged_at_begin: co ? (co.stagedChanges?.nodes ?? []).length : null, contaminated: false, contaminated_reason: null,
      calc_lines_at_begin: co?.lineItems?.nodes ?? [], begin_user_errors: (gb.data as BeginData | null)?.orderEditBegin?.userErrors ?? (gb.ok ? null : gb.errors), sends: [], cost: gb.cost.actual ?? 0 };
    if (co?.id && seen.includes(co.id)) { r.contaminated = true; r.contaminated_reason = "orderEditBegin returned a calculated order already seen (" + co.id + ")"; }
    else if ((r.staged_at_begin ?? 0) > 0) { r.contaminated = true; r.contaminated_reason = "stagedChanges not empty right after begin (" + r.staged_at_begin + ")"; }
    if (co?.id) seen.push(co.id);
    return r;
  };
  const runOne = async (key: TrySetKey): Promise<TrySetResult> => {
    const r = await begin(key);
    if (!r.calculated_order_id) return r;                                                           // begin 이 실패 — 보낼 세션이 없다(begin_user_errors 에 원문)
    for (const e of edits) {
      const lv = live.find((l) => l.id === e.line_gid)!;
      const c = matchCalcLine(lv, r.calc_lines_at_begin);
      const send: TrySetSend = { line_gid: e.line_gid, sku: lv.sku ?? null, to_remove: e.to_remove, calc_line_id: c?.id ?? null, calc_at_begin: c, quantity_sent: null, clamped: false, skipped: null, response: null };
      if (!c) { send.skipped = "cannot tell which calculated line it is"; r.sends.push(send); continue; }
      const cand = trySetCandidates(c, e.to_remove)[key];
      send.quantity_sent = cand.quantity; send.clamped = cand.clamped;
      const gs = await gql(ORDER_EDIT_SET_QTY_MUTATION, { id: r.calculated_order_id, lineItemId: c.id, quantity: cand.quantity, restock: true });
      r.cost += gs.cost.actual ?? 0;
      const ds = (gs.data as SetData | null)?.orderEditSetQuantity ?? null;
      send.response = { ok: gs.ok, status: gs.status, user_errors: ds?.userErrors ?? null, calculated_line_item: ds?.calculatedLineItem ?? null, calculated_order: ds?.calculatedOrder ?? null,
        staged_count: ds?.calculatedOrder ? (ds.calculatedOrder.stagedChanges?.nodes ?? []).length : null, errors: gs.errors ?? null };
      r.sends.push(send);
    }
    return r;
  };
  if (!edits.length) return results;
  results.push(await runOne("a"));
  const ra = results[0];
  const sameAll = ra.sends.length > 0 && ra.sends.every((s) => s.calc_at_begin && trySetCandidates(s.calc_at_begin, s.to_remove).b.quantity === s.quantity_sent);
  if (sameAll) results.push({ key: "b", rule: TRY_SET_RULE.b, same_as_a: true, calculated_order_id: null, staged_at_begin: null, contaminated: false, contaminated_reason: null, calc_lines_at_begin: [], begin_user_errors: null, sends: [], cost: 0 });
  else results.push(await runOne("b"));
  return results;
}
