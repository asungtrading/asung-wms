// deno test supabase/functions/shopify/shopify_paid_test.ts — Shopify · DB 무접촉 (pay-2b ① ~ ⑧ · _shared/shopify-paid.ts 의 순수 함수 · deps 주입 다리)
import { isPermissionError, MARK_PAID_MAX_ATTEMPTS, MARK_PAID_MUTATION, markPaidFailedMessage, markPaidFinal, processMarkPaid, skipBeforeSend, skipByState, type MarkPaidDeps, type PayOrder } from "../_shared/shopify-paid.ts";
import type { GqlLike } from "../_shared/shopify-edit.ts";
type GqlResp = Awaited<ReturnType<GqlLike>>;

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const GID = "gid://shopify/Order/9800000000001";
const order = (status: string | null, cancelledAt: string | null = null, outstanding = "1.68"): PayOrder => ({ cancelledAt, displayFinancialStatus: status, updatedAt: "2026-10-14T12:00:00Z", totalOutstandingSet: { shopMoney: { amount: outstanding, currencyCode: "CAD" } } });
const gqlOk = (data: unknown, raw = "{}"): GqlResp => ({ ok: true, status: 200, data, errors: null, raw, cost: { actual: 10 } });
const paidResp = (status = "PAID", ue: Array<{ field?: string[]; message: string }> = []) => gqlOk({ orderMarkAsPaid: { order: { id: GID, name: "#1", displayFinancialStatus: status, updatedAt: "2026-10-14T12:00:05Z", totalOutstandingSet: { shopMoney: { amount: status === "PAID" ? "0.0" : "1.68", currencyCode: "CAD" } } }, userErrors: ue } });
// deps 가짜 — 부른 순서를 steps 로 남긴다
function deps(o: PayOrder | null, ready: boolean, resp: GqlResp, log: string[] = []): MarkPaidDeps & { log: string[]; stamped: string[] } {
  const stamped: string[] = [];
  return {
    log, stamped,
    readOrder: async () => { log.push("readOrder"); return { order: o, cost: 5, error: null }; },
    paidState: async () => { log.push("paidState"); return { ready, open_sos: ready ? [] : ["SO-1a"], remaining_total: ready ? 0 : 1.68, invoices: [] }; },
    stampPaidPush: async (iso) => { log.push("stamp"); stamped.push(iso); },
    gql: async (q, v) => { log.push("gql:" + (q === MARK_PAID_MUTATION ? "markAsPaid" : "?") + ":" + JSON.stringify(v)); return resp; },
    now: () => "2026-10-14T12:00:01.000Z",
  };
}

Deno.test("① skipBeforeSend — 취소됨 · PAID · AUTHORIZED · REFUNDED · PARTIALLY_REFUNDED · VOIDED 는 건너뜀 · PENDING · PARTIALLY_PAID · EXPIRED · null 은 보낸다", () => {
  eq(skipBeforeSend(order("PENDING", "2026-10-14T00:00:00Z"))?.skip, "cancelled_in_shopify", "① cancelled");
  eq(skipBeforeSend(order("PAID"))?.skip, "already_paid", "① paid");
  eq(skipBeforeSend(order("paid"))?.skip, "already_paid", "① 소문자도");
  eq(skipBeforeSend(order("AUTHORIZED"))?.skip, "authorized_not_captured", "① authorized");
  eq(skipBeforeSend(order("REFUNDED"))?.skip, "refunded_in_shopify", "① refunded");
  eq(skipBeforeSend(order("PARTIALLY_REFUNDED"))?.skip, "refunded_in_shopify", "① partially refunded");
  eq(skipBeforeSend(order("VOIDED"))?.skip, "voided", "① voided");
  eq(skipBeforeSend(order("PENDING")), null, "① pending → 보낸다");
  eq(skipBeforeSend(order("PARTIALLY_PAID")), null, "① partially paid → 보낸다(남은 금액 전부)");
  eq(skipBeforeSend(order("EXPIRED")), null, "① expired → 보낸다");
  eq(skipBeforeSend(order(null)), null, "① 없음 → 보낸다");
});
Deno.test("② skipByState — ready 아님 · null · ready true", () => {
  eq(skipByState({ ready: false, open_sos: ["SO-1a"], remaining_total: 1.68 })?.skip, "not_ready_anymore", "② not ready");
  eq(skipByState({ ready: false, open_sos: ["SO-1a"], remaining_total: 1.68 })?.reason.includes("open orders 1 · remaining 1.68"), true, "② 까닭에 수");
  eq(skipByState(null)?.skip, "not_ready_anymore", "② null");
  eq(skipByState({ ready: true, open_sos: [], remaining_total: 0 }), null, "② ready");
});
Deno.test("③ isPermissionError — HTTP 401 · 403 · extensions.code ACCESS_DENIED · 문구(access denied · permission · not authorized · forbidden · scope) · userErrors 문구 · 그 밖은 아님", () => {
  eq(isPermissionError({ status: 403, errors: null }), true, "③ 403");
  eq(isPermissionError({ status: 401, errors: null }), true, "③ 401");
  eq(isPermissionError({ status: 200, errors: [{ message: "x", extensions: { code: "ACCESS_DENIED" } }] }), true, "③ ACCESS_DENIED");
  eq(isPermissionError({ status: 200, errors: [{ message: "Access denied for orderMarkAsPaid field. Required access: `write_orders` access scope. Also: The user must have mark_orders_as_paid permission." }] }), true, "③ 문구(문서 모양 짐작)");
  eq(isPermissionError({ status: 200, errors: null }, [{ field: ["id"], message: "You don't have permission to mark orders as paid" }]), true, "③ userErrors 문구");
  eq(isPermissionError({ status: 200, errors: null }, [{ field: ["id"], message: "Order cannot be marked as paid." }]), false, "③ 일반 거절은 아님");
  eq(isPermissionError({ status: 500, errors: [{ message: "Internal error" }] }), false, "③ 500 은 아님(retry)");
});
Deno.test("④ processMarkPaid 성공 — 순서 readOrder → paidState → stamp(보내기 전) → gql · 응답 PAID → ok · reason 에 outstanding · cost 합", async () => {
  const d = deps(order("PENDING"), true, paidResp());
  const r = await processMarkPaid(d, GID);
  eq(r.status, "ok", "④ ok");
  eq(d.log, ["readOrder", "paidState", "stamp", "gql:markAsPaid:" + JSON.stringify({ input: { id: GID } })], "④ 순서 — stamp 가 mutation 앞");
  eq(d.stamped, ["2026-10-14T12:00:01.000Z"], "④ paid_push_at 값 = now()");
  eq(r.steps, ["read", "state", "stamp", "mutation"], "④ steps");
  eq([r.shopify_status, r.outstanding, r.cost, r.final], ["PAID", "0.0", 15, false], "④ 상태 · 남은 금액 · cost");
  eq(r.reason, "PAID · outstanding 0.0 · updatedAt 2026-10-14T12:00:05Z", "④ reason");
});
Deno.test("⑤ processMarkPaid 건너뜀 — Shopify 쪽(PAID · 취소)은 paidState · stamp · gql 없이 · IMS 쪽(ready 아님)은 stamp · gql 없이", async () => {
  const a = deps(order("PAID"), true, paidResp());
  const ra = await processMarkPaid(a, GID);
  eq([ra.status, ra.reason?.split(" — ")[0], a.log], ["skipped", "already_paid", ["readOrder"]], "⑤ PAID → 읽기만");
  const b = deps(order("PENDING", "2026-10-14T00:00:00Z"), true, paidResp());
  eq([(await processMarkPaid(b, GID)).reason?.split(" — ")[0], b.log], ["cancelled_in_shopify", ["readOrder"]], "⑤ 취소 → 읽기만");
  const c = deps(order("PENDING"), false, paidResp());
  const rc = await processMarkPaid(c, GID);
  eq([rc.status, rc.reason?.split(" — ")[0], c.log, c.stamped], ["skipped", "not_ready_anymore", ["readOrder", "paidState"], []], "⑤ ready 아님 → stamp 없음");
  const n = deps(null, true, paidResp());
  const rn = await processMarkPaid(n, GID);
  eq([rn.status, rn.error, n.log], ["error", "order not in Shopify (or older than 60 days)", ["readOrder"]], "⑤ Shopify 에 없음 → error(retry)");
});
Deno.test("⑥ processMarkPaid 실패 — userErrors(일반) → error · final false · stamp 는 이미 적혔다(지우지 않는다) · 권한 문구 userErrors → final true · HTTP 403 → final true · 응답이 PAID 아님 → error", async () => {
  const a = deps(order("PENDING"), true, paidResp("PENDING", [{ field: ["id"], message: "Order cannot be marked as paid." }]));
  const ra = await processMarkPaid(a, GID);
  eq([ra.status, ra.final, ra.error, a.stamped.length], ["error", false, "orderMarkAsPaid: id: Order cannot be marked as paid.", 1], "⑥ 일반 userErrors");
  const b = deps(order("PENDING"), true, paidResp("PENDING", [{ message: "Access denied: the user must have mark_orders_as_paid permission" }]));
  const rb = await processMarkPaid(b, GID);
  eq([rb.status, rb.final], ["error", true], "⑥ 권한 userErrors → 한 번에");
  const c = deps(order("PENDING"), true, { ok: false, status: 403, data: null, errors: [{ message: "forbidden" }], raw: "{\"errors\":\"forbidden\"}", cost: { actual: null } });
  const rc = await processMarkPaid(c, GID);
  eq([rc.status, rc.final, rc.raw, rc.error?.startsWith("orderMarkAsPaid: graphql HTTP 403")], ["error", true, "{\"errors\":\"forbidden\"}", true], "⑥ 403 → final · raw 남김");
  const d = deps(order("PENDING"), true, paidResp("PARTIALLY_PAID"));
  const rd = await processMarkPaid(d, GID);
  eq([rd.status, rd.final, rd.error, rd.shopify_status], ["error", false, "orderMarkAsPaid answered PARTIALLY_PAID — expected PAID", "PARTIALLY_PAID"], "⑥ PAID 아님");
  const e = deps(order("PENDING"), true, { ok: false, status: 500, data: null, errors: null, raw: "boom", cost: { actual: null } });
  const re = await processMarkPaid(e, GID);
  eq([re.status, re.final, re.error], ["error", false, "orderMarkAsPaid: graphql HTTP 500 · boom"], "⑥ 500 → retry");
});
Deno.test("⑦ markPaidFinal · 메시지 — 5 회 · 권한은 1 회 · 문구", () => {
  eq([markPaidFinal(1, false), markPaidFinal(4, false), markPaidFinal(MARK_PAID_MAX_ATTEMPTS, false), markPaidFinal(1, true)], [false, false, true, true], "⑦ final");
  eq(markPaidFailedMessage("#1005", 5, "Order cannot be marked as paid."), "IMS could not mark Shopify order #1005 as paid after 5 tries — mark it paid in Shopify by hand only if IMS shows it fully paid (last error: Order cannot be marked as paid.)", "⑦ 5 회");
  eq(markPaidFailedMessage("#1005", 1, "graphql HTTP 403"), "IMS could not mark Shopify order #1005 as paid after 1 try — mark it paid in Shopify by hand only if IMS shows it fully paid (last error: graphql HTTP 403)", "⑦ 1 회(권한)");
});
Deno.test("⑧ MARK_PAID_MUTATION — 이름 · input 변수 · 응답 선택(displayFinancialStatus · totalOutstandingSet · userErrors)", () => {
  eq(MARK_PAID_MUTATION.includes("orderMarkAsPaid(input: $input)") && MARK_PAID_MUTATION.includes("$input: OrderMarkAsPaidInput!"), true, "⑧ 모양");
  eq(["displayFinancialStatus", "totalOutstandingSet", "userErrors { field message }", "updatedAt"].every((k) => MARK_PAID_MUTATION.includes(k)), true, "⑧ 선택 집합");
});
