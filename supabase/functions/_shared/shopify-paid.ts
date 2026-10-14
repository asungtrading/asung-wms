// ============================================================
// ASUNG IMS — 결제 표시 보내기(mark_paid): 순수 함수 · 쿼리 · Shopify 다리(gql 주입) (_shared · pay-2b · 2026-10-14 · 판정 449 · 469 · 468 · DB pay-2a 20261014162538 · pay-1a 20261014154103)
//   paid_drain(index.ts) 이 쓴다 — 네트워크 · DB 는 deps 주입(deno test). 흐름(한 행):
//   ① Shopify 오더 읽기(ORDER_LINES_QUERY 재사용 · cancelledAt · displayFinancialStatus · updatedAt · totalOutstandingSet)
//   ② Shopify 쪽 가르기(skipBeforeSend): 취소됨 → skipped cancelled_in_shopify · 이미 PAID → already_paid · AUTHORIZED → authorized_not_captured(orderMarkAsPaid 는 승인된 카드를 capture 한다 — 두 번 받는 길) · REFUNDED · PARTIALLY_REFUNDED → refunded_in_shopify · VOIDED → voided
//   ③ IMS 쪽 다시 판정(rpc shop_order_paid_state · ready 아니면 skipped not_ready_anymore — 스캔 뒤 결제가 취소됐을 수 있다)
//   ④ shop_order.paid_push_at = now() 를 보내기 전에 적는다(판정 468 의 −5 초 ~ +2 분 창 · 웹훅 받기가 EF 의 뒤쓰기보다 먼저 올 수 있다 · 실패해도 지우지 않는다 — 창이 2 분이라 해가 없다)
//      ⚠️ last_push_at 은 적지 않는다(오더 고치기 · 발송 메아리 447 ⓑ · 463 표지 — 같은 칸을 쓰면 그 창의 직원 고침 · 0 원 환불 판정이 섞인다 · pay-1a 이견 4)
//   ⑤ orderMarkAsPaid(input: {id}) · userErrors · 응답 order.displayFinancialStatus 가 PAID 인지
//   ⑥ 성공 → ok(응답 상태 · 남은 금액) · 실패 → error(final = 권한으로 보이는 오류 — 5 회를 기다리지 않는다) · 부르는 쪽(index.ts)이 큐 · 경고 mark_paid_failed 를 적는다
//   📌 pay-0(2026-10-14 · MCP 문서): orderMarkAsPaid 「Requires write_orders access scope. Also: The user must have mark_orders_as_paid permission」 · 「An order can be marked as paid only if it has a positive outstanding balance and its financial status isn't already PAID」
//      · 「will either create a new sale transaction for the full outstanding amount or capture an existing authorized transaction」 · 멱등 키 없음(보내기 전에 ①② 로 읽는다) · 되돌리기 없음
//   📌 짐작(첫 실물에서 확인): mark_orders_as_paid 사용자 권한이 client credentials 앱 토큰에 걸리는지 · 권한 거절의 문구 · 코드(아래 PERMISSION_RE 는 「access denied · permission · not authorized · forbidden · scope」 꼴을 권한 오류로 본다 — 첫 실물 응답 원문은 큐 error 와 shop_call_log 에 남는다)
// ============================================================

import type { GqlLike } from "./shopify-edit.ts";

export const MARK_PAID_FETCH = 20;
export const MARK_PAID_MS = 40_000;
export const MARK_PAID_MAX_ATTEMPTS = 5;

// ── GraphQL(2026-10 · 문서 예시의 선택 집합 그대로 — MCP validate 도구는 지금 no-op 이라 「VALID」 표기 없음 · 권한 write_orders + 사용자 mark_orders_as_paid) ──
export const MARK_PAID_MUTATION = `mutation ImsOrderMarkAsPaid($input: OrderMarkAsPaidInput!) { orderMarkAsPaid(input: $input) { order { id name displayFinancialStatus updatedAt totalOutstandingSet { shopMoney { amount currencyCode } } } userErrors { field message } } }`;

// ── 모양 ──
export type PayOrder = { cancelledAt?: string | null; displayFinancialStatus?: string | null; updatedAt?: string | null; totalOutstandingSet?: { shopMoney?: { amount?: string | null; currencyCode?: string | null } | null } | null };
export type PaidState = { ready?: boolean | null; open_sos?: unknown[] | null; remaining_total?: number | string | null; invoices?: unknown[] | null };
export type UserErr = { field?: string[] | null; message?: string | null };
export type GqlErr = { message?: string; extensions?: Record<string, unknown> };
export type Skip = { skip: string; reason: string } | null;
export type MarkPaidOut = { status: "ok" | "skipped" | "error"; reason: string | null; error: string | null; final: boolean; shopify_status: string | null; outstanding: string | null; cost: number; raw: string | null; steps: string[] };
export type MarkPaidDeps = {
  readOrder: () => Promise<{ order: PayOrder | null; cost: number; error: string | null }>;   // ① Shopify 읽기
  paidState: () => Promise<PaidState | null>;                                                   // ③ rpc shop_order_paid_state
  stampPaidPush: (iso: string) => Promise<void>;                                                // ④ shop_order.paid_push_at
  gql: GqlLike;                                                                                 // ⑤ 다리
  now?: () => string;
};

const up = (s: unknown): string => String(s ?? "").toUpperCase();
export const outstandingOf = (o: PayOrder | null | undefined): string | null => o?.totalOutstandingSet?.shopMoney?.amount ?? null;

// ── ② Shopify 쪽 가르기 — 보내지 않을 까닭(없으면 null) ──
export function skipBeforeSend(order: PayOrder): Skip {
  if (order.cancelledAt) return { skip: "cancelled_in_shopify", reason: "cancelled in Shopify (" + order.cancelledAt + ") — nothing to mark" };
  const st = up(order.displayFinancialStatus);
  if (st === "PAID") return { skip: "already_paid", reason: "already PAID in Shopify (outstanding " + (outstandingOf(order) ?? "?") + ")" };
  if (st === "AUTHORIZED") return { skip: "authorized_not_captured", reason: "AUTHORIZED in Shopify — orderMarkAsPaid would capture the customer's card; IMS does not capture cards" };
  if (st === "REFUNDED" || st === "PARTIALLY_REFUNDED") return { skip: "refunded_in_shopify", reason: st + " in Shopify — refunds are handled by the refund path, not marked paid" };
  if (st === "VOIDED") return { skip: "voided", reason: "VOIDED in Shopify — nothing to mark" };
  return null;
}
// ── ③ IMS 쪽 다시 판정 ──
export function skipByState(state: PaidState | null): Skip {
  if (!state || state.ready !== true) {
    const open = Array.isArray(state?.open_sos) ? state!.open_sos!.length : 0;
    return { skip: "not_ready_anymore", reason: "IMS is not fully paid any more (open orders " + open + " · remaining " + String(state?.remaining_total ?? "?") + ") — the next scan re-queues it when it is" };
  }
  return null;
}
// ── 권한으로 보이는 오류(짐작 · 첫 실물에서 문구 확인) — HTTP 401 · 403 · GraphQL errors.extensions.code ACCESS_DENIED · 문구 ──
export const PERMISSION_RE = /access denied|not (?:authorized|permitted|allowed)|permission|forbidden|required access|scope/i;
export function isPermissionError(g: { status: number; errors?: GqlErr[] | null }, userErrors: UserErr[] = []): boolean {
  if (g.status === 401 || g.status === 403) return true;
  for (const e of g.errors ?? []) {
    if (up(e.extensions?.code) === "ACCESS_DENIED") return true;
    if (PERMISSION_RE.test(String(e.message ?? ""))) return true;
  }
  return userErrors.some((u) => PERMISSION_RE.test(String(u.message ?? "")));
}
export const userErrorsSentence = (ue: UserErr[]): string => ue.map((u) => (u.field?.length ? u.field.join(".") + ": " : "") + (u.message ?? "?")).join("; ");
const gqlErrText = (g: { status: number; errors: unknown; raw: string | null }): string => "graphql HTTP " + g.status + (g.errors ? " · " + JSON.stringify(g.errors).slice(0, 300) : "") + (!g.errors && g.raw ? " · " + g.raw.slice(0, 200) : "");

// ── 한 행 — ① 읽기 → ② 가르기 → ③ 다시 판정 → ④ 표지 → ⑤ 보내기 → ⑥ 확인 · steps 는 시험이 순서를 본다 ──
export async function processMarkPaid(deps: MarkPaidDeps, orderGid: string): Promise<MarkPaidOut> {
  const out: MarkPaidOut = { status: "error", reason: null, error: null, final: false, shopify_status: null, outstanding: null, cost: 0, raw: null, steps: [] };
  const now = deps.now ?? (() => new Date().toISOString());
  const r = await deps.readOrder();
  out.steps.push("read");
  out.cost += r.cost;
  if (r.error) return { ...out, error: "read: " + r.error };
  if (!r.order) return { ...out, error: "order not in Shopify (or older than 60 days)" };
  out.shopify_status = r.order.displayFinancialStatus ?? null;
  out.outstanding = outstandingOf(r.order);
  const s1 = skipBeforeSend(r.order);
  if (s1) return { ...out, status: "skipped", reason: s1.skip + " — " + s1.reason };
  const state = await deps.paidState();
  out.steps.push("state");
  const s2 = skipByState(state);
  if (s2) return { ...out, status: "skipped", reason: s2.skip + " — " + s2.reason };
  await deps.stampPaidPush(now());                                                              // ④ 보내기 전에
  out.steps.push("stamp");
  const g = await deps.gql(MARK_PAID_MUTATION, { input: { id: orderGid } });
  out.steps.push("mutation");
  out.cost += g.cost.actual ?? 0;
  out.raw = g.raw ? g.raw.slice(0, 400) : null;
  if (!g.ok) return { ...out, error: "orderMarkAsPaid: " + gqlErrText(g), final: isPermissionError(g as { status: number; errors?: GqlErr[] | null }) };
  const d = (g.data as { orderMarkAsPaid?: { order?: PayOrder | null; userErrors?: UserErr[] } | null } | null)?.orderMarkAsPaid;
  const ue = d?.userErrors ?? [];
  if (ue.length) return { ...out, error: "orderMarkAsPaid: " + userErrorsSentence(ue), final: isPermissionError(g as { status: number; errors?: GqlErr[] | null }, ue) };
  const st = up(d?.order?.displayFinancialStatus);
  out.shopify_status = d?.order?.displayFinancialStatus ?? null;
  out.outstanding = outstandingOf(d?.order ?? null);
  if (st !== "PAID") return { ...out, error: "orderMarkAsPaid answered " + (st || "(no order)") + " — expected PAID" };
  return { ...out, status: "ok", reason: "PAID · outstanding " + (out.outstanding ?? "?") + (d?.order?.updatedAt ? " · updatedAt " + d.order.updatedAt : "") };
}
// 5 회 · 권한이면 한 번에 — 큐를 닫고 경고할지(index.ts 가 쓴다)
export function markPaidFinal(attempts: number, final: boolean): boolean { return final || attempts >= MARK_PAID_MAX_ATTEMPTS; }
export function markPaidFailedMessage(name: string, attempts: number, lastError: string | null): string {
  return "IMS could not mark Shopify order " + name + " as paid after " + attempts + (attempts === 1 ? " try" : " tries") + " — mark it paid in Shopify by hand only if IMS shows it fully paid (last error: " + (lastError ?? "?") + ")";
}
