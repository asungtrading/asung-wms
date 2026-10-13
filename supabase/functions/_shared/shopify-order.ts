// ============================================================
// ASUNG IMS — 오더 받기 순수 함수 · 쿼리 (_shared · ord-1b · 2026-10-10 · 판정 363 ~ 372 · 430 ~ 434 · DB ord-1a1 · 1a2 · 받은 일 표 20261011013000)
//   · 웹훅 검증 verifyWebhookHmac: X-Shopify-Hmac-SHA256 = 원문 바이트의 HMAC-SHA256(앱 client secret · base64) · 상수 시간 비교(길이가 다르면 false)
//     📌 문서(2026-10-10 MCP · shopify.dev/docs/apps/build/webhooks/verify-deliveries): 원문 body · client secret · base64 · 시한 연결 1 s · 전체 5 s · 실패 4 시간 8 번 · 계속 실패하면 구독 삭제(…/webhooks/troubleshoot)
//   · 웹훅 몸은 REST 모양 오더(id 숫자 · admin_graphql_api_id · …/api/admin-rest/2026-10/resources/webhook) — ingest 가 받는 GraphQL 모양과 다르다 ⇒ 웹훅은 오더 GID 만 받은 일 표에 적고 drain 이 GraphQL 로 다시 읽는다
//   · 구독은 shop-specific(webhookSubscriptionCreate · topic + {uri, format JSON} · …/webhooks/subscribe — toml 길은 CLI 가 없어 안 쓴다) · 주제 ORDERS_CREATE · ORDERS_UPDATED · ORDERS_CANCELLED
//   · drain 순서(DB 가 정한 것): ingest → status received 면 process · 그 밖은 멈춤 · 같은 오더를 몇 번 읽어도 된다
//   · ord-1b2: 받은 일 줄 없이 status = received 인 shop_order(직원이 resolve 로 풀었거나 앞 회차가 시간 한도로 process 전에 멈춘 것)도 drain 이 줍는다 — Shopify 를 다시 읽지 않고 저장된 원문으로 process 만
//     (다시 읽어 ingest 하면 줄을 다시 풀어 resolve_lines 로 고른 SKU · 뺀 줄이 사라진다) · 열린 받은 일 줄이 있는 오더는 그 길이 맡는다(sweepPick)
//   · ord-1b3: 주기 확인은 바뀐 오더만 받은 일에 — 페이지마다 shop_order 를 한 번 읽어 updatedAt 을 견준다(pollPick · 같으면 skipped_same) · 받은 일 열린 줄이 이미 있으면 inbox_add 가 null(skipped_open)
// ============================================================
import { API_VERSION } from "./shopify.ts";

export const ORDER_TOPICS = ["ORDERS_CREATE", "ORDERS_UPDATED", "ORDERS_CANCELLED"] as const;
export const INBOX_FETCH = 50;                                                      // 한 회차에 읽는 열린 받은 일 줄
export const ORDERS_DRAIN_MS = 40_000;                                              // 한 회차 시간 한도(cron 1 분 안에)
export const POLL_OVERLAP_MS = 5 * 60_000;                                          // 주기 확인 겹침(웹훅이 늦게 온 것 · 시계 차이)
export const POLL_FIRST_WINDOW_MS = 24 * 3_600_000;                                 // orders_polled_at 이 없으면 하루 전부터
export const POLL_PAGES_MAX = 5;                                                    // 50 × 5 = 한 회차 250 오더까지

// ── GraphQL(2026-10 · MCP validate ✅ VALID · ord-0-shopify.graphql ① 과 같은 칸 + customAttributes · taxLines · transactions · fulfillmentOrders · ful-1b 판정 447 · 440: fulfillments(메아리 거르기 — ingest 가 GID 를 shop_fulfillment 와 견준다) · refunds(원문은 shop_order.raw 에 · 경고 refunded_in_shopify)) ──
export const ORDER_READ_QUERY = `query ImsOrderRead($id: ID!) { order(id: $id) {
  id name createdAt updatedAt processedAt cancelledAt cancelReason closed test
  displayFinancialStatus displayFulfillmentStatus sourceName tags note poNumber email phone
  customAttributes { key value }
  customer { id firstName lastName displayName tags defaultEmailAddress { emailAddress } defaultPhoneNumber { phoneNumber } defaultAddress { provinceCode countryCodeV2 } }
  shippingAddress { name company address1 address2 city province provinceCode zip country countryCodeV2 phone }
  billingAddress { name company address1 address2 city province provinceCode zip country countryCodeV2 phone }
  currencyCode taxesIncluded
  subtotalPriceSet { shopMoney { amount currencyCode } } totalDiscountsSet { shopMoney { amount } } totalShippingPriceSet { shopMoney { amount } } totalTaxSet { shopMoney { amount } } totalPriceSet { shopMoney { amount } }
  taxLines { title rate priceSet { shopMoney { amount } } }
  discountCodes
  discountApplications(first: 20) { nodes { __typename allocationMethod targetSelection targetType value { __typename ... on MoneyV2 { amount } ... on PricingPercentageValue { percentage } } ... on DiscountCodeApplication { code } ... on AutomaticDiscountApplication { title } ... on ManualDiscountApplication { title description } ... on ScriptDiscountApplication { title } } }
  lineItems(first: 250) { nodes { id sku name quantity currentQuantity variant { id sku } originalUnitPriceSet { shopMoney { amount } } discountedUnitPriceAfterAllDiscountsSet { shopMoney { amount } } totalDiscountSet { shopMoney { amount } } discountAllocations { allocatedAmountSet { shopMoney { amount } } discountApplication { index } } taxLines { title rate priceSet { shopMoney { amount } } } } }
  shippingLines(first: 5) { nodes { title code source carrierIdentifier originalPriceSet { shopMoney { amount } } discountedPriceSet { shopMoney { amount } } discountAllocations { allocatedAmountSet { shopMoney { amount } } } taxLines { title rate priceSet { shopMoney { amount } } } } }
  paymentGatewayNames
  transactions(first: 20) { id kind status gateway amountSet { shopMoney { amount currencyCode } } processedAt test }
  retailLocation { id name }
  fulfillmentOrders(first: 10) { nodes { id status assignedLocation { location { id name } } deliveryMethod { methodType } } }
  fulfillments(first: 20) { id status createdAt updatedAt trackingInfo(first: 10) { number } }
  refunds(first: 20) { id createdAt note totalRefundedSet { shopMoney { amount currencyCode } } refundLineItems(first: 50) { nodes { quantity restockType lineItem { id sku } } } }
} }`;
export const ORDER_BY_NAME_QUERY = `query ImsOrderByName($q: String!) { orders(first: 1, query: $q) { nodes { id name } } }`;
export const ORDERS_SINCE_QUERY = `query ImsOrdersSince($q: String!, $after: String) { orders(first: 50, after: $after, sortKey: UPDATED_AT, query: $q) { pageInfo { hasNextPage endCursor } nodes { id name updatedAt cancelledAt displayFinancialStatus test } } }`;
export const WEBHOOK_LIST_QUERY = `query ImsWebhookList { webhookSubscriptions(first: 50) { nodes { id topic uri format apiVersion { handle } createdAt } } }`;
export const WEBHOOK_SUBSCRIBE_MUTATION = `mutation ImsWebhookSubscribe($topic: WebhookSubscriptionTopic!, $uri: String!) { webhookSubscriptionCreate(topic: $topic, webhookSubscription: { uri: $uri, format: JSON }) { webhookSubscription { id topic uri format createdAt } userErrors { field message } } }`;
export const apiVersion = () => API_VERSION;

// ── 웹훅 검증 ──
const enc = new TextEncoder();
export async function hmacBase64(secret: string, bytes: Uint8Array): Promise<string> {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;   // Uint8Array<ArrayBufferLike> → ArrayBuffer(deno check)
  const sig = await crypto.subtle.sign("HMAC", key, buf);
  let s = ""; for (const b of new Uint8Array(sig)) s += String.fromCharCode(b);
  return btoa(s);
}
export function timingSafeEqual(a: string, b: string): boolean {                     // 길이가 다르면 false · 같으면 전부 비교(짧게 끝나지 않는다)
  if (a.length !== b.length) return false;
  let d = 0; for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}
export async function verifyWebhookHmac(secret: string, bytes: Uint8Array, header: string | null): Promise<boolean> {
  if (!secret || !header) return false;
  return timingSafeEqual(await hmacBase64(secret, bytes), header.trim());
}

// ── 웹훅 머리 · 몸 ──
export type WebhookHead = { topic: string; domain: string; webhookId: string | null; eventId: string | null; apiVersion: string | null };
export function webhookHead(h: Headers): WebhookHead | null {
  const topic = h.get("x-shopify-topic"), domain = h.get("x-shopify-shop-domain");
  if (!topic || !domain) return null;
  return { topic: topic.trim().toLowerCase(), domain: domain.trim().toLowerCase(), webhookId: h.get("x-shopify-webhook-id"), eventId: h.get("x-shopify-event-id"), apiVersion: h.get("x-shopify-api-version") };
}
export const isOrderTopic = (topic: string) => /^orders\/(create|updated|cancelled)$/.test(topic);
export function orderGidFromWebhook(body: unknown): string | null {                  // REST 몸: admin_graphql_api_id 가 있으면 그것 · 없으면 숫자 id 로
  const b = (body ?? {}) as { admin_graphql_api_id?: unknown; id?: unknown };
  const gid = typeof b.admin_graphql_api_id === "string" ? b.admin_graphql_api_id : "";
  if (/^gid:\/\/shopify\/Order\/[0-9]+$/.test(gid)) return gid;
  const id = typeof b.id === "number" || typeof b.id === "string" ? String(b.id) : "";
  return /^[0-9]+$/.test(id) ? "gid://shopify/Order/" + id : null;
}
export function findStoreByDomain<T extends { shop_domain: string; is_active: boolean }>(stores: T[], domain: string): T | null {
  const d = domain.trim().toLowerCase();
  return stores.find((s) => s.shop_domain.toLowerCase() === d) ?? null;
}

// ── 구독 ──
export type SubNode = { id: string; topic: string; uri?: string | null; format?: string | null };
export function missingSubscriptions(existing: SubNode[], uri: string, topics: readonly string[] = ORDER_TOPICS): string[] {
  const have = new Set(existing.filter((s) => (s.uri ?? "").replace(/\/+$/, "") === uri.replace(/\/+$/, "")).map((s) => s.topic));
  return topics.filter((t) => !have.has(t));
}
export const webhookUri = (supabaseUrl: string) => supabaseUrl.replace(/\/+$/, "") + "/functions/v1/shopify";

// ── 오더 찾기 — GID 또는 이름(#1001 · AS-6950) ──
export function orderRef(input: string): { gid: string } | { query: string } | null {
  const s = String(input ?? "").trim();
  if (!s) return null;
  if (/^gid:\/\/shopify\/Order\/[0-9]+$/.test(s)) return { gid: s };
  if (/^[0-9]+$/.test(s)) return { gid: "gid://shopify/Order/" + s };
  return { query: "name:" + JSON.stringify(s) };                                   // name:"#1001" — 따옴표로 묶어 # · - 를 그대로
}
export function redactionReport(order: Record<string, unknown> | null, errors: Array<{ message?: string }> | null): { customer_null: boolean; email_null: boolean; shipping_null: boolean; not_approved: boolean } {
  const o = (order ?? {}) as { customer?: unknown; email?: unknown; shippingAddress?: unknown };
  return { customer_null: o.customer == null, email_null: o.email == null, shipping_null: o.shippingAddress == null, not_approved: !!errors?.some((e) => /not approved/i.test(String(e?.message ?? ""))) };
}

// ── 주기 확인 — 기준 시각 · 쿼리 글 ──
export function pollSince(lastPolledAt: string | null, now = Date.now()): string {
  const base = lastPolledAt ? Date.parse(lastPolledAt) : NaN;
  const t = Number.isFinite(base) ? base - POLL_OVERLAP_MS : now - POLL_FIRST_WINDOW_MS;
  return new Date(t).toISOString();
}
export const pollQuery = (sinceIso: string) => "updated_at:>'" + sinceIso + "'";
export function maxUpdatedAt(nodes: Array<{ updatedAt?: string | null }>, current: string | null): string | null {
  let best = current;
  for (const n of nodes) { const u = n.updatedAt ?? null; if (u && (!best || u > best)) best = u; }
  return best;
}
// ord-1b3 — 바뀐 오더만: 페이지의 오더마다 updatedAt 을 shop_order.shopify_updated_at(같은 스토어 · 같은 GID)과 견줘 없거나(모르는 GID · 저장된 시각 없음) 더 새것만 받은 일에 · 같거나 오래된 것은 건너뜀(same)
//   since = orders_polled_at − 5 분 겹침이라 새 활동이 없으면 마지막 몇 오더가 15 분마다 계속 보인다(실물 2026-10-11 01:15 · 01:30 seen 2 · 3 added 2 · 3) — 다시 ingest 하면 received · needs_review 의 줄을 다시 풀어 resolve_lines 가 지워진다
//   시각은 Date.parse 로 견준다(Shopify 'Z' · PostgREST '+00:00') · 못 읽으면 줍는다(안전 쪽)
export type KnownOrder = { shopify_order_gid: string; shopify_updated_at: string | null };
export function pollPick<T extends { id: string; updatedAt?: string | null }>(nodes: T[], known: KnownOrder[]): { add: T[]; same: T[] } {
  const have = new Map<string, number>(known.map((o) => [o.shopify_order_gid, o.shopify_updated_at ? Date.parse(o.shopify_updated_at) : NaN]));
  const add: T[] = [], same: T[] = [];
  for (const n of nodes) {
    const h = have.get(n.id), u = n.updatedAt ? Date.parse(n.updatedAt) : NaN;
    if (h === undefined || !Number.isFinite(h) || !Number.isFinite(u) || u > h) add.push(n); else same.push(n);
  }
  return { add, same };
}
export const gidInFilter = (gids: string[]) => 'in.(' + gids.map((g) => '"' + g + '"').join(",") + ")";   // PostgREST in.("gid://…","gid://…") · 부르는 쪽이 encodeURIComponent

// ── drain 판정 — DB 가 돌려준 status 로 다음 걸음 ──
export type IngestOut = { shop_order_id?: string; status?: string; action?: string };
export function drainNext(ingest: IngestOut): "process" | "stop" {
  return ingest?.status === "received" ? "process" : "stop";
}
export function drainStop(elapsedMs: number, timeMs = ORDERS_DRAIN_MS): string | null {
  return elapsedMs >= timeMs ? "time limit (" + Math.round(timeMs / 1000) + " s)" : null;
}
// ord-1b2 — 받은 일 줄 없는 received 줍기: 열린 받은 일 줄이 있는 오더(그 길이 다시 읽는다) · 이번 회차에 방금 다룬 오더는 뺀다
export type ReceivedRow = { id: string; shopify_order_gid: string };
export function sweepPick<T extends ReceivedRow>(received: T[], openGids: Set<string>, doneGids: Set<string>): T[] {
  return received.filter((o) => !openGids.has(o.shopify_order_gid) && !doneGids.has(o.shopify_order_gid));
}
