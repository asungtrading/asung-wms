// ============================================================
// ASUNG IMS — 나가지 않을 몫 · Shopify 오더 고치기: 순수 함수 · 쿼리 · Shopify 다리(gql 주입) (_shared · ful-4b ~ 4b3 · 2026-10-13 · 판정 439 · 441 · 457 ~ 462 · DB ful-4a 20261014000000)
//   order_drain(index.ts editShopOrder) · order_edit_preview 가 쓴다 — 네트워크는 gql 주입 · DB 없음(deno test). 흐름:
//   · 큐 shop_order_queue(kind order_edit · 열린 줄 · queued_at 순 · ≤ 20 · 40 s) → 오더마다 ① Shopify 오더 줄(currentQuantity · unfulfilledQuantity · 취소 · 결제 상태)을 실시간으로 읽고
//     ② can_ship 은 DB 에서 그 순간 다시 센다(rpc shop_order_can_ship · 장부 값은 스캔 때 것) ③ 취소된 오더 · 돈 받은 오더(PAID · PARTIALLY_PAID · PARTIALLY_REFUNDED · 판정 457)는 skipped(다음 스캔이 refund_due 길로)
//     ④ planOrderEdit: 줄마다 to_remove = max(unfulfilled − can_ship, 0) · new_quantity = current − to_remove — ⚠️ new_quantity 는 commit 뒤 currentQuantity 의 기대값(장부 쪽)이지 setQuantity 에 보내는 값이 아니다 · 전부 0 이면 받아 적기(removed_qty 만 맞추고 done ok)
//     ⑤ runOrderEdit: orderEditBegin → planEditSteps(줄 짝 matchCalcLine · 보낼 값 setQuantityFor) → orderEditSetQuantity(restock true · 판정 459) → 응답 확인 verifySetResponse(commit 전) → 하나라도 어긋나면 commit 없이 NoChangeError → orderEditCommit(notifyCustomer false · 판정 441)
//     ⑥ removed_qty = shop_order_line.quantity − currentQuantity(commit 뒤) · shop_order.last_push_at(메아리 ⓑ) · 큐 done · 5 회 실패면 경고 order_edit_failed(NoChangeError 는 한 번에 · retry 아님)
//   📌 문서(2026-10-13 MCP): orderEditCommit 「If notifyCustomer is set to true, then an email invoice … is sent」 · 「You can only edit unfulfilled line items」 · 세션은 「until you commit or abandon them」(버리는 mutation 없음 · orderEdit* 11 개 확인 · 안 commit 하면 끝)
//   📌 짐작(Caleb 시험에서 확인): unfulfilledQuantity = currentQuantity − 보낸 수량 · CalculatedLineItem 숫자 id = LineItem 숫자 id · 안 commit 한 세션은 오더에 영향 없음
//   ⭐ 확정(실물 · 2026-10-13 try-set · #1011 · 세션 CalculatedOrder/97462157495): orderEditSetQuantity 의 quantity 는 「고칠 수 있는 몫(editableQuantity) 중 남길 수」이지 전체 수량이 아니다 —
//     calc {quantity 2 · editableQuantity 1}(1 개 발송) 에 0 을 보내니 editableQuantity 0 · DecrementItem delta 1 · 잔액 2.98 → 1.49 / 1 을 보내니(ful-4b · 4b1 의 값) userErrors 없이 조용히 지나가고 staged 0 → commit 이 「There must be at least one change to be made.」
//     → setQuantityFor = max(editableQuantity − to_remove, 0) · 바뀌지 않는 값을 Shopify 는 거절하지 않으므로 응답(줄 단위 stagedChanges)을 commit 전에 우리가 읽는다
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
// ful-4b2 · 4b3: 선택 집합(validate ✅ 2026-10-13) — 오더 단위 stagedChanges(first 20) · 세션의 줄 전부(preview · try_set 용) · ⭐ 줄 단위 calculatedLineItem.stagedChanges(리스트 · 페이지 없음 · commit 전 확인이 읽는 것)
export const ORDER_EDIT_SET_QTY_MUTATION = `mutation ImsOrderEditSetQuantity($id: ID!, $lineItemId: ID!, $quantity: Int!, $restock: Boolean) { orderEditSetQuantity(id: $id, lineItemId: $lineItemId, quantity: $quantity, restock: $restock) { calculatedOrder { id totalOutstandingSet { shopMoney { amount currencyCode } } subtotalLineItemsQuantity stagedChanges(first: 20) { nodes { __typename ... on OrderStagedChangeDecrementItem { delta restock lineItem { id } } } } lineItems(first: 250) { nodes { id sku quantity editableQuantity editableQuantityBeforeChanges restockable restocking } } } calculatedLineItem { id quantity editableQuantity editableQuantityBeforeChanges restocking stagedChanges { __typename ... on OrderStagedChangeDecrementItem { delta restock lineItem { id } } } } userErrors { field message } } }`;
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
// ⑤ setQuantity 에 보낼 값 — 고칠 수 있는 몫 기준(머리 ⭐ 실물 확정 · ful-4b3): quantity = max(editableQuantity − to_remove, 0) · change = editableQuantity − quantity(실제로 줄어드는 양 · 0 이면 그 줄은 안 보낸다) · to_remove > editableQuantity 면 clamped(이미 나간 몫은 못 지운다 · 「only unfulfilled」)
export type SetQty = { quantity: number; change: number; clamped: boolean };
export function setQuantityFor(calc: CalcLine, toRemove: number): SetQty {
  const ed = Math.max(Math.floor(n(calc.editableQuantity)), 0), tr = Math.max(Math.floor(toRemove), 0);
  const quantity = Math.max(ed - tr, 0);
  return { quantity, change: ed - quantity, clamped: tr > ed };
}
export class NoChangeError extends Error { constructor(msg: string) { super(msg); this.name = "NoChangeError"; } }
// ⑤ 줄마다 짝 + 보낼 값 — preview(would_set) 와 runOrderEdit 가 같은 함수 하나를 쓴다(두 식이 갈라지지 않게)
export type EditStep = { line_gid: string; sku: string | null; to_remove: number; calc: CalcLine | null; set: SetQty | null };
export function planEditSteps(calc: CalcLine[], plan: Plan, live: LiveLine[]): EditStep[] {
  return plan.edits.filter((e) => e.to_remove > 0).map((e) => {
    const lv = live.find((l) => l.id === e.line_gid)!;                                              // plan.edits 는 live 에 있는 줄만(없는 줄은 plan.missing)
    const c = matchCalcLine(lv, calc);
    return { line_gid: e.line_gid, sku: lv.sku ?? null, to_remove: e.to_remove, calc: c, set: c ? setQuantityFor(c, e.to_remove) : null };
  });
}
// ⑤ 응답 확인(commit 전) — editableQuantity === 보낸 quantity 그리고 그 줄(lineItem.id === line_gid)의 DecrementItem delta === change · restock 은 막지 않고 돌려준다(false 면 notes 로)
export type StagedChange = { __typename?: string; delta?: number; restock?: boolean; lineItem?: { id: string } | null };
export type SetQtyLine = { id?: string; quantity?: number; editableQuantity?: number; editableQuantityBeforeChanges?: number; restocking?: boolean; stagedChanges?: StagedChange[] | null };
export function verifySetResponse(step: { line_gid: string; quantity: number; change: number }, line: SetQtyLine | null | undefined): { ok: boolean; why: string | null; restock: boolean | null } {
  if (!line) return { ok: false, why: "no calculatedLineItem in the response", restock: null };
  const staged = line.stagedChanges ?? [];
  const dec = staged.find((s) => s.__typename === "OrderStagedChangeDecrementItem" && s.lineItem?.id === step.line_gid) ?? null;
  const got = "editableQuantity " + (line.editableQuantity ?? "?") + " · quantity " + (line.quantity ?? "?") + " · staged " + (dec ? "DecrementItem delta " + dec.delta + " restock " + dec.restock : staged.length ? staged.length + " other" : "none");
  if (line.editableQuantity !== step.quantity) return { ok: false, why: "editableQuantity is not the sent " + step.quantity + " (" + got + ")", restock: dec?.restock ?? null };
  if (!dec) return { ok: false, why: "no DecrementItem for this line (" + got + ")", restock: null };
  if (dec.delta !== step.change) return { ok: false, why: "delta is not the expected " + step.change + " (" + got + ")", restock: dec.restock ?? null };
  return { ok: true, why: null, restock: dec.restock ?? null };
}
// ⑥ removed_qty = 원래 수량(shop_order_line.quantity) − 지금 수량(currentQuantity) — 우리가 지운 것 · Shopify 에서 지워진 것이 같이 잡힌다(§0 이견 3)
export const removedQty = (dbQuantity: number | string, currentQuantity: number | string): number => Math.max(n(dbQuantity) - n(currentQuantity), 0);
export const userErrorsText = (errs: Array<{ field?: string[] | null; message?: string }> | null | undefined): string =>
  (errs ?? []).map((e) => (e.field?.length ? e.field.join(".") + ": " : "") + (e.message ?? "")).join(" · ");


// ── Shopify 다리(gql 주입 · ful-4b3) — begin → 짝 · 보낼 값 → set → 응답 확인 → commit. DB 는 모른다(index.ts editShopOrder 가 앞뒤를 맡는다) ──
type UserErr = { field?: string[] | null; message?: string };
const gqlErrText = (g: { status: number; errors: unknown; raw: string | null }): string => "graphql HTTP " + g.status + (g.errors ? " · " + JSON.stringify(g.errors).slice(0, 300) : "") + (g.raw ? " · " + g.raw.slice(0, 100) : "");
type BeginData = { orderEditBegin?: { calculatedOrder?: { id: string; stagedChanges?: { nodes?: Array<{ __typename?: string }> }; lineItems?: { nodes?: CalcLine[] } } | null; userErrors?: unknown } };
type SetData = { orderEditSetQuantity?: { calculatedOrder?: { stagedChanges?: { nodes?: unknown[] } } | null; calculatedLineItem?: unknown; userErrors?: unknown } };
type CommitData = { orderEditCommit?: { order?: { lineItems?: { nodes?: Array<{ id: string; quantity: number; currentQuantity: number }> } } | null; userErrors?: unknown } };
export async function beginOrderEdit(gql: GqlLike, orderGid: string): Promise<{ calcId: string; calc: CalcLine[]; cost: number }> {
  const gb = await gql(ORDER_EDIT_BEGIN_MUTATION, { id: orderGid });
  const db = (gb.data as BeginData | null)?.orderEditBegin;
  const errs = db?.userErrors as UserErr[] | null | undefined;
  if (!gb.ok || errs?.length || !db?.calculatedOrder?.id) throw new Error("orderEditBegin: " + (errs?.length ? userErrorsText(errs) : gqlErrText(gb)));
  return { calcId: db.calculatedOrder.id, calc: db.calculatedOrder.lineItems?.nodes ?? [], cost: gb.cost.actual ?? 0 };
}
export type OrderEditRun = { calc_id: string; after: LiveLine[]; changed: number; notes: string[]; no_restock: string[]; cost: number };
export async function runOrderEdit(gql: GqlLike, orderGid: string, plan: Plan, live: LiveLine[]): Promise<OrderEditRun> {
  const b = await beginOrderEdit(gql, orderGid);
  let cost = b.cost, changed = 0;
  const steps = planEditSteps(b.calc, plan, live);
  const notes: string[] = [], no_restock: string[] = [];
  for (const st of steps) {
    const short = st.line_gid.split("/").pop();
    if (!st.calc || !st.set) throw new Error("line " + short + " (" + (st.sku ?? "?") + "): cannot tell which calculated line it is (same product twice?) — edit the order in Shopify by hand");
    if (st.set.clamped) notes.push(short + ": wanted −" + st.to_remove + " · only " + st.calc.editableQuantity + " editable (" + Math.max(n(st.calc.quantity) - n(st.calc.editableQuantity), 0) + " already fulfilled) → sent " + st.set.quantity);
    if (st.set.change <= 0) { notes.push(short + ": no change (calc " + st.calc.quantity + " · editable " + st.calc.editableQuantity + " · to_remove " + st.to_remove + ")"); continue; }
    const gs = await gql(ORDER_EDIT_SET_QTY_MUTATION, { id: b.calcId, lineItemId: st.calc.id, quantity: st.set.quantity, restock: true });   // 판정 459
    cost += gs.cost.actual ?? 0;
    const ds = (gs.data as SetData | null)?.orderEditSetQuantity;
    const errs = ds?.userErrors as UserErr[] | null | undefined;
    if (!gs.ok || errs?.length) throw new Error("orderEditSetQuantity " + short + " → " + st.set.quantity + ": " + (errs?.length ? userErrorsText(errs) : gqlErrText(gs)));
    const v = verifySetResponse({ line_gid: st.line_gid, quantity: st.set.quantity, change: st.set.change }, ds?.calculatedLineItem as SetQtyLine | null | undefined);
    if (!v.ok) throw new NoChangeError("Shopify did not stage the change for line " + short + " (" + (st.sku ?? "?") + "): sent quantity " + st.set.quantity + " expecting −" + st.set.change + " (calc " + st.calc.quantity + " · editable " + st.calc.editableQuantity + " · to_remove " + st.to_remove + ") but the response shows " + v.why + " — NOT committed; check the order in Shopify by hand");
    if (v.restock === false) { const t = short + " (" + (st.sku ?? "?") + "): Shopify will NOT restock " + st.set.change + " — check inventory by hand"; no_restock.push(t); notes.push(t); }
    changed += st.set.change;
  }
  if (changed <= 0) {                                                                                // 바꿀 줄이 0 — commit 을 보내지 않는다(세션은 버림) · 다시 시도하지 않는 error
    const detail = steps.map((st) => st.line_gid.split("/").pop() + " live current " + (live.find((l) => l.id === st.line_gid)?.currentQuantity ?? "?") + " unfulfilled " + (live.find((l) => l.id === st.line_gid)?.unfulfilledQuantity ?? "?") + " · calc " + (st.calc?.quantity ?? "?") + "/" + (st.calc?.editableQuantity ?? "?") + " · to_remove " + st.to_remove).join("; ");
    throw new NoChangeError("nothing would change in Shopify (" + detail + ") — every line is already at that quantity or fully fulfilled; check the order in Shopify by hand");
  }
  const gc = await gql(ORDER_EDIT_COMMIT_MUTATION, { id: b.calcId, notify: false, note: ORDER_EDIT_STAFF_NOTE });   // 판정 441 · 메일 없음
  cost += gc.cost.actual ?? 0;
  const dc = (gc.data as CommitData | null)?.orderEditCommit;
  const cerrs = dc?.userErrors as UserErr[] | null | undefined;
  if (!gc.ok || cerrs?.length || !dc?.order) throw new Error("orderEditCommit: " + (cerrs?.length ? userErrorsText(cerrs) : gqlErrText(gc)));
  const after: LiveLine[] = (dc.order.lineItems?.nodes ?? []).map((l) => ({ id: l.id, quantity: l.quantity, currentQuantity: l.currentQuantity, unfulfilledQuantity: 0 }));   // commit 응답엔 unfulfilledQuantity 가 없다(removedQty 는 안 쓴다)
  return { calc_id: b.calcId, after, changed, notes, no_restock, cost };
}

// ── ful-4b2 · try-set(원인 확인만 · commit 없음 · 세션은 버린다) — ful-4b3 뒤로는 진단용 ──────────────────────────────
//   실물(머리 ⭐): ⓐ(editable − to_remove = 0) 가 DecrementItem delta 1 · ⓑ(calc − to_remove = 1 · 확정 전 식) 는 staged 0. 세션 id 셋 모두 달랐다(preview 97462124727 · ⓐ 97462157495 · ⓑ 97462190263 · contaminated 없음)
//   세션을 버리는 뮤테이션은 없다(orderEdit* 11 개 확인) — begin 이 같은 세션을 돌려주면(id 가 앞과 같거나 staged 가 0 이 아니면) 그대로 돌리되 contaminated: true(숨기지 않는다 · 그것도 실물)
export type TrySetKey = "a" | "b";
export const TRY_SET_RULE: Record<TrySetKey, string> = { a: "editableQuantity - to_remove", b: "calc.quantity - to_remove" };
export function trySetCandidates(calc: CalcLine, toRemove: number): Record<TrySetKey, { quantity: number; clamped: boolean }> {
  const a = setQuantityFor(calc, toRemove);                                                        // ⓐ = 확정 식(setQuantityFor · ful-4b3)
  const cq = Math.max(Math.floor(n(calc.quantity)), 0), tr = Math.max(Math.floor(toRemove), 0);   // ⓑ = 확정 전 식(ful-4b1: calc.quantity − to_remove · 바닥 = 이미 나간 몫) · 진단용 · 실물에서 변화 0
  const floor = Math.max(cq - Math.floor(n(calc.editableQuantity)), 0), want = Math.max(cq - tr, 0), bq = Math.max(want, floor);
  return { a: { quantity: a.quantity, clamped: a.clamped }, b: { quantity: bq, clamped: bq !== want } };
}
export type GqlLike = (query: string, variables: Record<string, unknown>) => Promise<{ ok: boolean; status: number; data: unknown; errors: unknown; raw: string | null; cost: { actual: number | null } }>;
export type TrySetSend = { line_gid: string; sku: string | null; to_remove: number; calc_line_id: string | null; calc_at_begin: CalcLine | null; quantity_sent: number | null; clamped: boolean; skipped: string | null;
  response: { ok: boolean; status: number; user_errors: unknown; calculated_line_item: unknown; calculated_order: unknown; staged_count: number | null; errors: unknown } | null };
export type TrySetResult = { key: TrySetKey; rule: string; same_as_a?: true; calculated_order_id: string | null; staged_at_begin: number | null; contaminated: boolean; contaminated_reason: string | null;
  calc_lines_at_begin: CalcLine[]; begin_user_errors: unknown; sends: TrySetSend[]; cost: number };
// 후보마다 begin 을 따로 → 줄마다 setQuantity(restock true · 판정 459) → 응답을 그대로 모은다. commit 은 절대 부르지 않는다(테스트가 호출 목록으로 확인). ful-4b3 뒤로는 진단용(ⓐ 가 확정 식)
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
