// ============================================================
// ASUNG IMS — Edge Function: shopify (shop-1b ping · shop-2b push · drain · clean_check · 2026-10-09 · 판정 362 · 403 ~ 411 · ⭐ stock-1b stock_drain · stock_push · 2026-10-10 · 판정 421 ~ 425)
//   ⚠️ 테스트 프로젝트(Asung-IMS · fazgmyvzzhqybtvtktyg) 전용 — 시작 때 inv_config.db_role = 'test' 가 아니면 멈춘다.
//   POST JSON {action, store, …} · 응답은 json(status) · CORS.
//   문(action 마다 · verify_jwt=false 라 함수 안에서):
//     직원 길  Authorization: Bearer <세션 JWT> → rpc/ims_can_write('shopify')(ims-staff-create 모양 · 401 세션 · 403 권한) → /auth/v1/user 로 by_staff
//     cron 길  x-ims-cron-key == secret IMS_CRON_SECRET(미설정 500 fail-closed) · by_staff null
//     ping      직원 · cron / push · clean_check · stock_push 직원만 / drain · stock_drain cron 길(직원도 허락 — 손으로 비울 때)
//   ⭐ 재고(stock-1b · 판정 421 ~ 425): stock_drain = shop_stock_queue 열린 줄(오래된 것부터 ≤ STOCK_FETCH)을 스토어마다 묶어 rpc/shop_stock_payload 한 번 → 줄 판정(../_shared/shopify-stock.ts planRows: 변형 없음 skipped_off · blocks error · 같으면 skipped_same · force 면 전부)
//      → (아이템 · 위치) 활성 여부를 nodes(ids) 로 한 번 읽어 없는 짝은 inventoryActivate → inventorySetQuantities(name available · reason correction · changeFromQuantity null · @idempotent 결정적 키 · STOCK_BATCH 개씩) → shop_stock_sent upsert · 줄 result · 한도 적으면 멈춤 · 시간 한도 STOCK_DRAIN_MS
//      stock_push = 직원 · 대상 하나(family_sku | sku)의 변형 전부를 force 로 바로(큐 없이 · 판정 415 결) · 위치별 결과를 돌려준다
//   ⭐ 상품 drain(판정 424 ②): skipped_same_hash 줄은 DRAIN_MAX 20 칸에 세지 않는다 — 보낸(또는 error) 건이 20 이거나 DRAIN_TIME_MS 를 넘으면 멈춘다 · 한 회차에 읽는 열린 줄은 DRAIN_FETCH
//   표 읽기 · 대응 표 갱신 · 큐 · call_log 는 service_role(세 표는 authenticated 직접 쓰기가 닫혀 있다) · payload 는 rpc/shop_product_payload(2a1) · 거르기는 ../_shared/shopify-clean.ts(규칙 기반 · 판정 412) · 조립은 ../_shared/shopify-product.ts
//   ⭐ 사진 짝(fix2 · 실물 media_matched 0): 보내기 직전 product.media 를 읽어 READY + url 인 사진만 줄기(= product_image id)로 shop_media 에 짝 → 그 사진은 {id} 로 · 처리 중은 URL + REPLACE(쌓이지 않음) · 줄기가 IMS 에 없는 사진은 지워진다(판정 409 · media_removed_unknown) · 직원 push 는 응답이 처리 중이면 2 초 × 2 회 다시 읽는다 · hash 가 같으면 직전 읽기도 안 한다
//   ⭐ 안전장치(판정 412): 거른 html 을 rpc/ims_html_forbidden 에 넣어 하나라도 걸리면 productSet 을 부르지 않는다(result error · description_forbidden_after_clean:<코드> · 직원 길 push 는 422 · drain 은 다음 건 계속) — IMS 에서 그 설명을 한 번 고쳐 저장하면 풀린다
//   ⭐ 오더 받기(ord-1b · 판정 363 ~ 372 · 430 ~ 434 · DB ord-1a1 · 1a2 · 받은 일 표 20261011013000 · 순수 함수 ../_shared/shopify-order.ts):
//      webhook   = 문 셋째(HMAC · 헤더 X-Shopify-Topic 이 있으면 이 길 · 문 앞에서 가른다) — 원문 바이트의 HMAC-SHA256(스토어의 client secret) 과 X-Shopify-Hmac-SHA256 상수 시간 비교 · 스토어는 X-Shopify-Shop-Domain · 몸(REST 모양)에서 오더 GID 만 → rpc/shop_order_inbox_add → 바로 200 · 검증 실패 401 · 모르는 스토어 200(기록만 · 재시도 폭주 막기)
//      orders_drain = cron · 직원 — 받은 일 열린 줄(오래된 것부터 ≤ INBOX_FETCH)을 GraphQL 로 다시 읽어 rpc/shop_order_ingest → received 면 rpc/shop_order_process → 줄 닫기(result = status) · 한 건 실패해도 다음 · 시간 한도 ORDERS_DRAIN_MS
//                     ⭐ ord-1b2: 그 뒤 받은 일 줄 없이 status = received 인 shop_order(직원이 resolve_customer · resolve_lines 로 푼 것 · 앞 회차가 시간 한도로 멈춘 것)를 ≤ INBOX_FETCH 줍는다 — Shopify 를 다시 읽지 않고 rpc/shop_order_process 만(다시 읽으면 줄을 다시 풀어 resolve_lines 가 사라진다) · 열린 받은 일 줄이 있는 오더는 그 길이 맡는다 · 응답 swept · cron 47 의 where 조건도 received 를 본다
//      orders_poll  = cron · 직원 — 스토어마다 orders(updated_at:> orders_polled_at − 5 분) 50 개씩 ≤ 5 쪽 → 받은 일(topic poll · 웹훅이 빠진 것 줍기) → orders_polled_at = 본 것 중 최댓값
//                     ⭐ ord-1b3: 바뀐 오더만 — 페이지마다 shop_order(같은 스토어 · GID)를 한 번 읽어 updatedAt 이 같거나 오래된 오더는 건너뛴다(skipped_same · pollPick) · 열린 받은 일 줄이 있으면 skipped_open(inbox_add null) — 겹침 5 분 때문에 새 활동이 없으면 마지막 오더들이 15 분마다 다시 보여 received · needs_review 의 줄(resolve_lines)을 지우던 결함(실물 2026-10-11 01:15 · 01:30)
//      order_read   = 직원 · 쓰기 0 — 오더 하나(GID · 숫자 · 이름 #1001)를 ① 쿼리로 읽어 원문 · errors · 가림 보고(customer · email · 주소 null · 「not approved」) — 보호된 손님 정보 확정용(ord-0 ⬜1)
//      webhooks_subscribe · webhooks_list = 직원 — 스토어의 shop-specific 구독(ORDERS_CREATE · UPDATED · CANCELLED → 이 함수 주소) · 있으면 그대로 · 목록
//      ⚠️ EF 는 shop_system_enter · leave 를 부르지 않는다(시스템 창구 안에서만) · ingest · process 는 service_role rpc
//   ⭐ 발송 보내기(ful-2 · 2026-10-13 · 판정 436 ~ 453 · DB ful-1a 20261013170000 · ful-2a 20261013193000 · 순수 함수 ../_shared/shopify-fulfill.ts):
//      fulfill_drain = cron · 직원 — shop_fulfill_queue 의 열린 ship 줄(오래된 것부터 ≤ FULFILL_FETCH)마다 그 SO 의 결과 표 머리(shop_fulfillment · pending | error)를 하나씩: Shopify 오더의 fulfillmentOrders + fulfillments 읽기 →
//                      줄 짝(planLines · 남은 수량으로 자름 → quantity_sent · 경고 fulfill_cut) → 위치 맞추기(SO 창고의 shop_location ≠ FO 위치면 fulfillmentOrderMove · 실패면 그대로 보내고 경고 fulfill_location_mismatch · 판정 445 · 453) →
//                      kind pickup + FO PICK_UP 이면 fulfillmentOrderLineItemsPreparedForPickup(ready_at · 판정 379) · 그 밖은 fulfillmentCreate(carrier = 송장 · 메일 / pickup · delivery = 송장 없음 · 메일 없음 · 판정 378) → 머리 sent(GID) · 줄 quantity_sent · fulfillment_order_line_item_gid
//                      ful-1b(DB 20261013210000 · 판정 438 · 443 · 447): 큐 kind picked_up(창구 so_picked_up(ful-1c · 옛 shop_fulfill_picked_up) → 픽업 FO 에 fulfillmentCreate notify false → GID) · tracking_fix(창구 so_tracking_fix → fulfillmentTrackingInfoUpdate notify false) · Shopify 에 쓸 때마다 last_push_at(ingest 메아리 ⓑ)
//                      ful-2c: Ready for pickup 을 보냈는데 Shopify 가 NO_LINE_ITEMS_TO_PREPARE_FOR_FULFILLMENT_ORDER 로 거절하면(직원이 Shopify 에서 먼저 Mark as ready · 실물 #1008) 받아 적는다 — sent · ready_at = FO updatedAt · last_error 「adopted: already ready in Shopify」 · last_push_at · 경고 없음
//   · order_drain(cron 5 분 · 직원 · ful-4b · DB ful-4a 20261014000000 · 판정 439 · 441 · 457 ~ 462): 오더 큐 shop_order_queue(kind order_edit · 15 분 스캔 shop_unshipped_scan 이 넣는다) ≤ 20 · 40 s —
//                      오더마다 Shopify 줄(currentQuantity · unfulfilledQuantity)을 실시간으로 · can_ship 은 rpc shop_order_can_ship 으로 그 순간 다시(장부 값은 스캔 때 것) · 취소 · 돈 받음(PAID · PARTIALLY_PAID · PARTIALLY_REFUNDED)은 skipped
//                      to_remove = max(unfulfilled − can_ship, 0) · 전부 0 이면 받아 적기(removed_qty 만) · 아니면 orderEditBegin → SetQuantity(restock true) → Commit(notifyCustomer false) → removed_qty = 원래 − 지금 · shop_order.last_push_at(메아리 ⓑ) · 5 회 실패면 경고 order_edit_failed
//                      보낼 것이 0 이면 우리 발송을 받아 적는다(adoptExisting · 송장 겹침 / 큐 뒤 송장 없는 발송) · 아니면 skipped + 경고 fulfill_nothing_left · 머리 하나라도 error 면 큐를 열어 두고 attempts + 1 · 5 회면 큐 done error + 경고 fulfill_failed
//                      쓰기 = 세 표(shop_fulfillment · line · 큐)는 service_role REST PATCH(stock_drain 의 patchQueue 와 같은 길) · shop_order 경고는 rpc/shop_order_warn(ful-2a · 한 문장 || 라 ingest 경고와 안 겹친다) · shop_system_enter 는 안 부른다
//   호출 한 번 = shop_call_log 한 줄(drain 은 건마다) · 90 일 지난 줄은 호출 끝에 지운다.
//   배포: supabase functions deploy shopify --project-ref fazgmyvzzhqybtvtktyg (config.toml [functions.shopify] verify_jwt=false)
// ============================================================
import { API_VERSION, compareLocations, getToken, missingScopes, shopifyGql, type PairRow, type ShopLocation, type StoreRow, type Warning } from "../_shared/shopify.ts";
import { cleanHtml, forbiddenAfterClean, FORBIDDEN_AFTER_CLEAN } from "../_shared/shopify-clean.ts";
import { assertNoForbiddenKeys, buildProductSetInput, mapResponse, matchMedia, mediaNodes, PRODUCT_MEDIA_QUERY, PRODUCT_SET_MUTATION, unknownMedia, userErrorsSentence, type MediaNode, type Payload, type RespProduct } from "../_shared/shopify-product.ts";
import { sleep } from "../_shared/shopify.ts";
import { drainNext, drainStop, findStoreByDomain, gidInFilter, INBOX_FETCH, isOrderTopic, maxUpdatedAt, missingSubscriptions, ORDER_BY_NAME_QUERY, ORDER_READ_QUERY, ORDER_TOPICS, orderGidFromWebhook, orderRef, ORDERS_DRAIN_MS, ORDERS_SINCE_QUERY, POLL_PAGES_MAX, pollPick, pollQuery, pollSince, redactionReport, sweepPick, verifyWebhookHmac, WEBHOOK_LIST_QUERY, WEBHOOK_SUBSCRIBE_MUTATION, webhookHead, webhookUri, type KnownOrder, type ReceivedRow, type SubNode } from "../_shared/shopify-order.ts";
import { secretNames } from "../_shared/shopify.ts";
import { adoptExisting, adoptReadyError, buildFulfillmentInput, buildTrackingInput, FULFILL_DRAIN_MS, FULFILL_FETCH, FULFILL_KINDS, FULFILL_ORDERS_QUERY, FULFILLMENT_CREATE_MUTATION, FULFILLMENT_ORDER_MOVE_MUTATION, movesNeeded, pickupFo, pickupPath, planLines, PREPARED_FOR_PICKUP_MUTATION, preparedForPickupInput, queueOutcome, readyAtFromFos, remapAfterMove, TRACKING_UPDATE_MUTATION, userErrorsText, type FoNode, type FulfillKind, type FulfillmentNode, type FulLine, type FulRow, type PlanItem, type UserErr } from "../_shared/shopify-fulfill.ts";
import { isPaid, matchCalcLine, NoChangeError, ORDER_EDIT_BEGIN_MUTATION, ORDER_EDIT_COMMIT_MUTATION, ORDER_EDIT_FETCH, ORDER_EDIT_MAX_ATTEMPTS, ORDER_EDIT_MS, ORDER_EDIT_SET_QTY_MUTATION, ORDER_EDIT_STAFF_NOTE, ORDER_LINES_QUERY, planOrderEdit, removedQty, runTrySet, setQuantityFor, userErrorsText as editErrorsText, type CalcLine, type DbLine, type LiveLine, type Plan, type TrySetResult } from "../_shared/shopify-edit.ts";
import { activateKeyParts, activeLevels, chunk, countsToward, DRAIN_TIME_MS, drainShouldStop, idemKey, INVENTORY_ACTIVATE_MUTATION, INVENTORY_LEVELS_QUERY, INVENTORY_SET_MUTATION, needActivation, planRows, setInput, setKeyParts, sortedForSet, splitUserErrors, STOCK_BATCH, STOCK_DRAIN_MS, STOCK_FETCH, type LevelsNode, type QueueRow, type RowPlan, type SendItem, type SentRow, type StockPayloadRow } from "../_shared/shopify-stock.ts";

const CALL_LOG_KEEP_DAYS = 90;
const DRAIN_MAX = 20;                                                                              // 보낸(ok · error) 건의 칸 — skipped_same_hash 는 세지 않는다(판정 424 ②)
const DRAIN_FETCH = 200;                                                                           // 한 회차에 읽는 열린 상품 줄(건너뛸 줄이 많아도 20 건은 보내게)
const DRAIN_MIN_AVAILABLE = 500;
const MEDIA_REREAD_MAX = 2;                                                                        // 직원 push 만 · 응답 사진이 처리 중이면 2 초 뒤 다시 읽기(최대 2 회) · drain 은 안 한다(회차 시간 · 다음 push 의 직전 읽기가 잡는다)
const MEDIA_REREAD_WAIT_MS = 2000;                                                                   // 한도 남은 점수가 이 아래면 이번 회차를 멈춘다(다음 분에 이어서)
const CORS: HeadersInit = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-ims-cron-key", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const ACTIONS = ["ping", "push", "drain", "clean_check", "stock_drain", "stock_push", "order_read", "webhooks_subscribe", "webhooks_list", "orders_poll", "orders_drain", "fulfill_drain", "order_drain", "order_edit_preview"];

const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON = () => Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const json = (status: number, obj: unknown): Response => new Response(JSON.stringify(obj, null, 2), { status, headers: { "Content-Type": "application/json", ...CORS } });
const sbHeaders = (extra: Record<string, string> = {}): HeadersInit => ({ apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/json", ...extra });
async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { headers: sbHeaders() });
  if (!r.ok) throw new Error("sbGet " + path.split("?")[0] + " " + r.status + ": " + (await r.text()).slice(0, 300));
  return await r.json();
}
async function sbWrite(method: string, path: string, body?: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { method, headers: sbHeaders({ Prefer: "return=minimal" }), body: body === undefined ? undefined : JSON.stringify(body) });
  if (!r.ok) throw new Error("sb " + method + " " + path.split("?")[0] + " " + r.status + ": " + (await r.text()).slice(0, 300));
}
async function sbRpc(fn: string, args: Record<string, unknown>): Promise<unknown> {
  const r = await fetch(SB_URL() + "/rest/v1/rpc/" + fn, { method: "POST", headers: sbHeaders(), body: JSON.stringify(args) });
  if (!r.ok) throw new Error("rpc " + fn + " " + r.status + ": " + (await r.text()).slice(0, 300));
  return await r.json();
}
async function sbUpsertByKey(table: string, filter: string, row: Record<string, unknown>): Promise<void> {   // 유니크 키로 찾아 PATCH · 없으면 POST(부분 유니크 · null 키라 on_conflict 를 안 쓴다)
  const ex = await sbGet(table + "?select=id&" + filter + "&limit=1");
  if (ex[0]) await sbWrite("PATCH", table + "?id=eq." + ex[0].id, row); else await sbWrite("POST", table, row);
}
type LogRow = { store_id: string | null; action: string; ok: boolean; http_status: number | null; query_cost: number | null; throttle_available: number | null; error: string | null; by_staff: string | null; ms: number };
async function recordCall(row: LogRow): Promise<void> {
  try {
    await sbWrite("POST", "shop_call_log", { ...row, error: row.error ? row.error.slice(0, 400) : null });
    try { await sbWrite("DELETE", "shop_call_log?called_at=lt." + encodeURIComponent(new Date(Date.now() - CALL_LOG_KEEP_DAYS * 86_400_000).toISOString())); } catch (e) { console.warn("call_log purge failed:", String(e).slice(0, 200)); }
  } catch (e) { console.warn("recordCall failed:", String(e).slice(0, 300)); }
}

// ── 문 ──
type Caller = { kind: "cron"; staffId: null } | { kind: "staff"; staffId: string | null };
async function gate(req: Request): Promise<Caller | Response> {
  const cronKey = req.headers.get("x-ims-cron-key");
  if (cronKey !== null) {
    const secret = Deno.env.get("IMS_CRON_SECRET") ?? "";
    if (!secret) return json(500, { ok: false, error: "IMS_CRON_SECRET not configured - refusing (fail-closed)" });
    if (cronKey !== secret) return json(401, { ok: false, error: "unauthorized" });
    return { kind: "cron", staffId: null };
  }
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json(401, { ok: false, error: "Missing Authorization" });
  const r = await fetch(SB_URL() + "/rest/v1/rpc/ims_can_write", { method: "POST", headers: { apikey: ANON(), Authorization: "Bearer " + jwt, "Content-Type": "application/json" }, body: JSON.stringify({ p_screen: "shopify" }) });
  if (r.status === 401) return json(401, { ok: false, error: "Invalid session — sign in again" });
  if (!r.ok) return json(502, { ok: false, error: "Permission check failed (ims_can_write): " + (await r.text()).slice(0, 200) });
  if ((await r.json()) !== true) return json(403, { ok: false, error: "Not allowed — you need the 'shopify' permission (manager and above) to use Shopify stores" });
  let staffId: string | null = null;
  try {
    const u = await fetch(SB_URL() + "/auth/v1/user", { headers: { apikey: ANON(), Authorization: "Bearer " + jwt } });
    const uid = u.ok ? String((await u.json())?.id ?? "") : "";
    if (uid) staffId = (await sbGet("ims_staff?select=id&auth_user_id=eq." + uid + "&limit=1"))[0]?.id ?? null;
  } catch (e) { console.warn("by_staff lookup failed:", String(e).slice(0, 200)); }
  return { kind: "staff", staffId };
}

// ── 허락 iframe host(ref_embed_host) — 호출마다 한 번 ──
async function loadHosts(): Promise<Set<string>> {
  const rows = await sbGet("ref_embed_host?select=host&kind=eq.iframe&is_active=eq.true");
  return new Set(rows.map((r: { host: string }) => String(r.host).toLowerCase()));
}

// ── ping(shop-1b) ──
const PING_QUERY = `query ImsPing { shop { name myshopifyDomain currencyCode } locations(first: 50) { nodes { id name isActive } } }`;
async function ping(store: StoreRow, caller: Caller, t0: number): Promise<Response> {
  const warnings: Warning[] = [];
  let tok;
  try { tok = await getToken(store); }
  catch (e) {
    const msg = String((e as Error)?.message ?? e);
    await recordCall({ store_id: store.id, action: "ping", ok: false, http_status: null, query_cost: null, throttle_available: null, error: "token: " + msg, by_staff: caller.staffId, ms: Date.now() - t0 });
    return json(502, { ok: false, error: msg, store: store.code });
  }
  const missing = missingScopes(tok.scope);
  if (missing.length) warnings.push({ code: "missing_scopes", detail: missing.join(",") });
  const g = await shopifyGql(store, PING_QUERY);
  if (!g.ok) {
    const err = "graphql HTTP " + g.status + (g.errors ? " · " + JSON.stringify(g.errors).slice(0, 300) : "") + (g.raw ? " · " + g.raw.slice(0, 100) : "");
    await recordCall({ store_id: store.id, action: "ping", ok: false, http_status: g.status, query_cost: g.cost.actual, throttle_available: g.cost.available, error: err, by_staff: caller.staffId, ms: Date.now() - t0 });
    return json(502, { ok: false, error: "Shopify did not answer the ping for " + store.shop_domain + " — " + err, store: store.code, attempts: g.attempts });
  }
  const data = g.data as { shop?: { name?: string; myshopifyDomain?: string; currencyCode?: string }; locations?: { nodes?: ShopLocation[] } };
  const shop = data?.shop ?? {};
  const locs: ShopLocation[] = (data?.locations?.nodes ?? []).map((l) => ({ id: String(l.id), name: String(l.name ?? ""), isActive: !!l.isActive }));
  if (shop.currencyCode && shop.currencyCode !== "CAD") warnings.push({ code: "currency_not_cad", detail: String(shop.currencyCode) });
  if (shop.myshopifyDomain && shop.myshopifyDomain.toLowerCase() !== store.shop_domain.toLowerCase()) warnings.push({ code: "domain_mismatch", detail: shop.myshopifyDomain + " ≠ " + store.shop_domain });
  const pairs: PairRow[] = await sbGet("shop_location?select=id,shopify_location_gid,shopify_name,warehouse_id,is_active,ref_warehouse(name)&store_id=eq." + store.id);
  const cmp = compareLocations(locs, pairs.map((p: any) => ({ ...p, warehouse_name: p.ref_warehouse?.name ?? null })));
  warnings.push(...cmp.warnings);
  const now = new Date().toISOString();
  for (const u of cmp.updates) {
    try { await sbWrite("PATCH", "shop_location?id=eq." + u.id, { shopify_name: u.name, checked_at: now }); }
    catch (e) { warnings.push({ code: "pair_update_failed", gid: u.gid, detail: String(e).slice(0, 200) }); }
  }
  await recordCall({ store_id: store.id, action: "ping", ok: true, http_status: g.status, query_cost: g.cost.actual, throttle_available: g.cost.available, error: warnings.length ? "warnings: " + warnings.map((w) => w.code).join(",") : null, by_staff: caller.staffId, ms: Date.now() - t0 });
  return json(200, {
    ok: true, store: store.code, api_version: API_VERSION, caller: caller.kind,
    shop: { name: shop.name ?? null, myshopifyDomain: shop.myshopifyDomain ?? null, currencyCode: shop.currencyCode ?? null },
    locations: locs.map((l) => ({ ...l, paired_warehouse: pairs.find((p) => p.is_active && p.shopify_location_gid === l.id)?.warehouse_id ?? null })),
    pairs: pairs.map((p: any) => ({ gid: p.shopify_location_gid, warehouse: p.ref_warehouse?.name ?? null, is_active: p.is_active })),
    scopes: tok.scope.split(",").filter(Boolean), missing_scopes: missing, warnings, cost: g.cost, attempts: g.attempts, ms: Date.now() - t0,
  });
}

// ── push 한 건 — payload → (hash 비교) → 거르기 → productSet → 대응 표 · 결과 ──
type Target = { family_id: string | null; product_id: string | null };
type PushResult = { ok: boolean; result: "ok" | "skipped_same_hash" | "error"; error: string | null; product_gid: string | null; handle: string | null; status: string | null; variants: number; media: number; media_matched_before: number; media_reused_ids: number; media_removed_unknown: number; media_matched: number; media_rereads: number; clean: { engine: string; removed: string[] } | null; hash: string | null; cost: unknown; query_cost_total: number; ms: number; blocks: string[] };
async function pushOne(store: StoreRow, target: Target, caller: Caller, force: boolean, hosts: Set<string>, action: string): Promise<PushResult> {
  const t0 = Date.now();
  const fail = (msg: string, extra: Partial<PushResult> = {}): PushResult => ({ ok: false, result: "error", error: msg.slice(0, 400), product_gid: null, handle: null, status: null, variants: 0, media: 0, media_matched_before: 0, media_reused_ids: 0, media_removed_unknown: 0, media_matched: 0, media_rereads: 0, clean: null, hash: null, cost: null, query_cost_total: 0, ms: Date.now() - t0, blocks: [], ...extra });
  const targetFilter = "store_id=eq." + store.id + "&family_id=" + (target.family_id ? "eq." + target.family_id : "is.null") + "&product_id=" + (target.product_id ? "eq." + target.product_id : "is.null");
  let p: Payload;
  try { p = (await sbRpc("shop_product_payload", { p_store_id: store.id, p_family_id: target.family_id, p_product_id: target.product_id })) as Payload; }
  catch (e) { const r = fail("payload: " + String((e as Error)?.message ?? e)); await recordCall({ store_id: store.id, action, ok: false, http_status: null, query_cost: null, throttle_available: null, error: r.error, by_staff: caller.staffId, ms: r.ms }); return r; }
  if (p.blocks.length) { const r = fail("cannot send: " + p.blocks.join(", "), { blocks: p.blocks, hash: p.hash }); await recordCall({ store_id: store.id, action, ok: false, http_status: null, query_cost: null, throttle_available: null, error: r.error, by_staff: caller.staffId, ms: r.ms }); return r; }
  const sp = (await sbGet("shop_product?select=id,shopify_product_gid,handle,last_hash,shopify_status&" + targetFilter + "&limit=1"))[0] ?? null;
  if (sp && sp.last_hash === p.hash && !force) {
    await recordCall({ store_id: store.id, action, ok: true, http_status: null, query_cost: 0, throttle_available: null, error: "skipped_same_hash", by_staff: caller.staffId, ms: Date.now() - t0 });
    return { ok: true, result: "skipped_same_hash", error: null, product_gid: sp.shopify_product_gid, handle: sp.handle, status: sp.shopify_status, variants: 0, media: 0, media_matched_before: 0, media_reused_ids: 0, media_removed_unknown: 0, media_matched: 0, media_rereads: 0, clean: null, hash: p.hash, cost: null, query_cost_total: 0, ms: Date.now() - t0, blocks: [] };   // hash 가 같으면 직전 읽기도 하지 않는다(Shopify 호출 0)
  }
  const clean = cleanHtml(p.description_html ?? "", hosts);
  let gate: string | null = null;                                                                   // 판정 412 안전장치 — DB 판별이 걸리면 보내지 않는다
  try { gate = forbiddenAfterClean((await sbRpc("ims_html_forbidden", { p_html: clean.html })) as string[]); }
  catch (e) { gate = FORBIDDEN_AFTER_CLEAN + ":check_failed(" + String((e as Error)?.message ?? e).slice(0, 120) + ")"; }
  if (gate) {
    await sbUpsertByKey("shop_product", targetFilter, { store_id: store.id, family_id: target.family_id, product_id: target.product_id, shopify_product_gid: sp?.shopify_product_gid ?? "gid://shopify/Product/0", last_status: "error", last_error: gate.slice(0, 400) }).catch((e) => console.warn("shop_product error mark failed:", String(e).slice(0, 200)));
    await recordCall({ store_id: store.id, action, ok: false, http_status: null, query_cost: null, throttle_available: null, error: gate, by_staff: caller.staffId, ms: Date.now() - t0 });
    return fail(gate, { clean: { engine: clean.engine, removed: clean.removed }, hash: p.hash });
  }
  const skus = p.variants.map((v) => v.sku);
  const vRows = skus.length ? await sbGet("shop_variant?select=product_id,shopify_variant_gid&store_id=eq." + store.id + "&product_id=in.(" + p.variants.map((v) => v.product_id).join(",") + ")") : [];
  const variantGidBySku: Record<string, string> = {};
  for (const v of p.variants) { const r = vRows.find((x: any) => x.product_id === v.product_id); if (r) variantGidBySku[v.sku] = r.shopify_variant_gid; }
  const mRows = p.files.length ? await sbGet("shop_media?select=product_image_id,shopify_file_gid&store_id=eq." + store.id + "&product_image_id=in.(" + p.files.map((f) => f.product_image_id).join(",") + ")") : [];
  const mediaGidByImage: Record<string, string> = {};
  for (const m of mRows) mediaGidByImage[m.product_image_id] = m.shopify_file_gid;
  let costTotal = 0, matchedBefore = 0, removedUnknown = 0;
  const upsertMedia = async (matched: Record<string, string>) => {
    for (const [imageId, gid] of Object.entries(matched)) {
      if (mediaGidByImage[imageId] === gid) continue;
      await sbUpsertByKey("shop_media", "store_id=eq." + store.id + "&product_image_id=eq." + imageId, { store_id: store.id, product_image_id: imageId, shopify_file_gid: gid, last_pushed_at: new Date().toISOString() });
      mediaGidByImage[imageId] = gid;
    }
  };
  if (sp?.shopify_product_gid && p.files.length) {                                                // 보내기 직전 짝 맞추기(fix2) — READY + url 인 사진만 줄기로
    const gm = await shopifyGql(store, PRODUCT_MEDIA_QUERY, { id: sp.shopify_product_gid });
    costTotal += gm.cost.actual ?? 0;
    if (gm.ok) {
      const nodes: MediaNode[] = mediaNodes((gm.data as { product?: RespProduct | null } | null)?.product);
      const matched = matchMedia(nodes, p.files, true);
      matchedBefore = Object.keys(matched).length;
      removedUnknown = unknownMedia(nodes, p.files);
      await upsertMedia(matched);
    } else console.warn("media pre-read failed:", gm.status, JSON.stringify(gm.errors ?? gm.raw ?? "").slice(0, 200));   // 못 읽으면 지금처럼 URL + REPLACE 로(쌓이지 않는다)
  }
  const built = buildProductSetInput(p, { baseUrl: SB_URL(), productGid: sp?.shopify_product_gid ?? null, variantGidBySku, mediaGidByImage, cleanedHtml: clean.html });
  const reusedIds = p.files.filter((f) => !!mediaGidByImage[f.product_image_id]).length;
  const forbidden = assertNoForbiddenKeys(built.input);
  if (forbidden.length) return fail("input carries forbidden keys: " + forbidden.join(","));
  const g = await shopifyGql(store, PRODUCT_SET_MUTATION, { identifier: built.identifier, input: built.input });
  costTotal += g.cost.actual ?? 0;
  const data = g.data as { productSet?: { product?: RespProduct | null; userErrors?: Array<{ field?: string[] | null; message?: string; code?: string | null }> } } | null;
  const ue = data?.productSet?.userErrors ?? [];
  if (!g.ok || ue.length || !data?.productSet?.product) {
    const msg = ue.length ? "Shopify refused: " + userErrorsSentence(ue) : "graphql HTTP " + g.status + (g.errors ? " · " + JSON.stringify(g.errors).slice(0, 300) : "") + (g.raw ? " · " + g.raw.slice(0, 100) : "");
    await sbUpsertByKey("shop_product", targetFilter, { store_id: store.id, family_id: target.family_id, product_id: target.product_id, shopify_product_gid: sp?.shopify_product_gid ?? "gid://shopify/Product/0", last_status: "error", last_error: msg.slice(0, 400) }).catch((e) => console.warn("shop_product error mark failed:", String(e).slice(0, 200)));
    await recordCall({ store_id: store.id, action, ok: false, http_status: g.status, query_cost: costTotal, throttle_available: g.cost.available, error: msg, by_staff: caller.staffId, ms: Date.now() - t0 });
    return fail(msg, { clean: { engine: clean.engine, removed: clean.removed }, hash: p.hash, cost: g.cost, query_cost_total: costTotal, media_matched_before: matchedBefore, media_reused_ids: reusedIds, media_removed_unknown: removedUnknown });
  }
  const m = mapResponse(data.productSet.product);
  let matched = matchMedia(m.media, p.files, true);
  let rereads = 0;
  if (caller.kind === "staff" && action === "push" && p.files.some((f) => !mediaGidByImage[f.product_image_id] && !matched[f.product_image_id])) {   // 처리 중이면 짧게 다시(직원 push 만)
    while (rereads < MEDIA_REREAD_MAX) {
      await sleep(MEDIA_REREAD_WAIT_MS); rereads++;
      const gm = await shopifyGql(store, PRODUCT_MEDIA_QUERY, { id: m.productGid });
      costTotal += gm.cost.actual ?? 0;
      if (!gm.ok) break;
      matched = { ...matched, ...matchMedia(mediaNodes((gm.data as { product?: RespProduct | null } | null)?.product), p.files, true) };
      if (!p.files.some((f) => !mediaGidByImage[f.product_image_id] && !matched[f.product_image_id])) break;
    }
  }
  const now = new Date().toISOString();
  await sbUpsertByKey("shop_product", targetFilter, { store_id: store.id, family_id: target.family_id, product_id: target.product_id, shopify_product_gid: m.productGid, handle: m.handle, shopify_status: m.status, last_hash: p.hash, last_pushed_at: now, last_status: "ok", last_error: null });
  for (const v of m.variants) {
    const pv = p.variants.find((x) => x.sku === v.sku); if (!pv) continue;
    await sbUpsertByKey("shop_variant", "store_id=eq." + store.id + "&product_id=eq." + pv.product_id, { store_id: store.id, product_id: pv.product_id, shopify_variant_gid: v.gid, inventory_item_gid: v.inventoryItemGid, last_hash: p.hash });
  }
  await upsertMedia(matched);
  const note = [clean.removed.length ? "clean removed: " + clean.removed.slice(0, 10).join(",") : "", "media before/after/reused/unknown " + matchedBefore + "/" + Object.keys(matched).length + "/" + reusedIds + "/" + removedUnknown + (rereads ? " rereads " + rereads : "")].filter(Boolean).join(" · ");
  await recordCall({ store_id: store.id, action, ok: true, http_status: g.status, query_cost: costTotal, throttle_available: g.cost.available, error: note || null, by_staff: caller.staffId, ms: Date.now() - t0 });
  return { ok: true, result: "ok", error: null, product_gid: m.productGid, handle: m.handle, status: m.status, variants: m.variants.length, media: m.media.length, media_matched_before: matchedBefore, media_reused_ids: reusedIds, media_removed_unknown: removedUnknown, media_matched: Object.keys(matched).length, media_rereads: rereads, clean: { engine: clean.engine, removed: clean.removed }, hash: p.hash, cost: g.cost, query_cost_total: costTotal, ms: Date.now() - t0, blocks: [] };
}

// ── 재고 보내기(stock-1b · 판정 421 ~ 425) — plans(줄 판정 결과)를 받아 Shopify 에 보내고 sent · 큐 줄을 적는다 ──
type ItemResult = { queue_id: number; sku: string | null; product_id: string; warehouse_id: string; location_gid: string; quantity: number; result: "ok" | "error"; error: string | null; activated: boolean };
type SendOut = { items: ItemResult[]; rowResult: Map<number, { result: "ok" | "error"; error: string | null }>; cost: number; calls: number; available: number | null; stopped: string | null };
async function sendStock(store: StoreRow, plans: RowPlan[], refId: number | string, t0: number, timeMs: number): Promise<SendOut> {
  const out: SendOut = { items: [], rowResult: new Map(), cost: 0, calls: 0, available: null, stopped: null };
  const all: SendItem[] = plans.filter((p) => p.result === "send").flatMap((p) => p.items);
  const itemErr = new Map<string, string>();                                                       // item|loc → error(activate 실패 · userErrors)
  const activated = new Set<string>();
  for (const batch of chunk(all, STOCK_BATCH)) {
    if (Date.now() - t0 > timeMs) { out.stopped = "time limit (" + Math.round(timeMs / 1000) + " s)"; break; }
    // 1) (아이템 · 위치) 활성 여부 — nodes(ids) 한 번 · 없는 짝은 inventoryActivate(결정적 키)
    const ids = [...new Set(batch.map((i) => i.inventory_item_gid))];
    const gl = await shopifyGql(store, INVENTORY_LEVELS_QUERY, { ids });
    out.calls++; out.cost += gl.cost.actual ?? 0; if (gl.cost.available !== null) out.available = gl.cost.available;
    if (!gl.ok) { out.stopped = "inventory levels read failed: HTTP " + gl.status + (gl.errors ? " · " + JSON.stringify(gl.errors).slice(0, 200) : ""); break; }
    const active = activeLevels(((gl.data as { nodes?: LevelsNode[] } | null)?.nodes ?? []) as LevelsNode[]);
    for (const a of needActivation(batch, active)) {
      const ga = await shopifyGql(store, INVENTORY_ACTIVATE_MUTATION, { item: a.inventory_item_gid, loc: a.location_gid, key: await idemKey(activateKeyParts(a.inventory_item_gid, a.location_gid)) });
      out.calls++; out.cost += ga.cost.actual ?? 0; if (ga.cost.available !== null) out.available = ga.cost.available;
      const ue = (ga.data as { inventoryActivate?: { userErrors?: Array<{ message?: string }> } } | null)?.inventoryActivate?.userErrors ?? [];
      if (!ga.ok || ue.length) itemErr.set(a.inventory_item_gid + "|" + a.location_gid, "activate failed: " + (ue.length ? ue.map((e) => e.message).join(" · ") : "HTTP " + ga.status + (ga.errors ? " · " + JSON.stringify(ga.errors).slice(0, 200) : "")));
      else activated.add(a.inventory_item_gid + "|" + a.location_gid);
    }
    // 2) inventorySetQuantities — activate 에 실패한 짝은 뺀다
    const sendable = batch.filter((i) => !itemErr.has(i.inventory_item_gid + "|" + i.location_gid));
    const sorted = sortedForSet(sendable);
    if (sorted.length) {
      const g = await shopifyGql(store, INVENTORY_SET_MUTATION, { input: setInput(sorted, refId), key: await idemKey(setKeyParts(sorted, refId)) });
      out.calls++; out.cost += g.cost.actual ?? 0; if (g.cost.available !== null) out.available = g.cost.available;
      const ue = (g.data as { inventorySetQuantities?: { userErrors?: Array<{ field?: string[] | null; message?: string; code?: string | null }> } } | null)?.inventorySetQuantities?.userErrors ?? [];
      const split = splitUserErrors(ue, sorted);
      const whole = !g.ok ? "graphql HTTP " + g.status + (g.errors ? " · " + JSON.stringify(g.errors).slice(0, 300) : "") + (g.raw ? " · " + g.raw.slice(0, 100) : "") : split.whole;
      sorted.forEach((i, idx) => { const e = whole ?? split.perItem.get(idx) ?? null; if (e) itemErr.set(i.inventory_item_gid + "|" + i.location_gid, "Shopify refused: " + e); });
    }
    for (const i of batch) {
      const k = i.inventory_item_gid + "|" + i.location_gid; const e = itemErr.get(k) ?? null;
      out.items.push({ queue_id: i.queue_id, sku: i.sku, product_id: i.product_id, warehouse_id: i.warehouse_id, location_gid: i.location_gid, quantity: i.quantity, result: e ? "error" : "ok", error: e ? e.slice(0, 400) : null, activated: activated.has(k) });
    }
    if (typeof out.available === "number" && out.available < DRAIN_MIN_AVAILABLE) { out.stopped = "throttle budget low (" + out.available + ")"; break; }
  }
  // 3) sent upsert(unique store × product × warehouse) · 줄 결과(한 줄의 위치가 하나라도 error 면 error)
  const now = new Date().toISOString();
  const sentRows = out.items.map((i) => ({ store_id: store.id, product_id: i.product_id, warehouse_id: i.warehouse_id, quantity: i.quantity, sent_at: now, last_status: i.result, last_error: i.error }));
  if (sentRows.length) {
    const r = await fetch(SB_URL() + "/rest/v1/shop_stock_sent?on_conflict=store_id,product_id,warehouse_id", { method: "POST", headers: sbHeaders({ Prefer: "resolution=merge-duplicates,return=minimal" }), body: JSON.stringify(sentRows) });
    if (!r.ok) throw new Error("shop_stock_sent upsert " + r.status + ": " + (await r.text()).slice(0, 300));
  }
  for (const p of plans) {
    if (p.result !== "send") continue;
    const mine = out.items.filter((i) => i.queue_id === p.queue_id);
    if (!mine.length) continue;                                                                    // 시간 한도 · 멈춤으로 못 보낸 줄 — 열어 둔다(다음 회차)
    const errs = mine.filter((i) => i.result === "error");
    out.rowResult.set(p.queue_id, errs.length ? { result: "error", error: errs.map((e) => e.sku + "@" + e.location_gid.split("/").pop() + ": " + e.error).join(" · ").slice(0, 400) } : { result: "ok", error: null });
  }
  return out;
}
async function patchQueue(ids: number[], body: Record<string, unknown>): Promise<void> { if (ids.length) await sbWrite("PATCH", "shop_stock_queue?id=in.(" + ids.join(",") + ")", body); }

async function stockDrain(caller: Caller, t0: number): Promise<Response> {
  const rows: QueueRow[] = await sbGet("shop_stock_queue?select=id,store_id,product_id,reason,force&done_at=is.null&order=queued_at.asc,id.asc&limit=" + STOCK_FETCH);
  const byStore = new Map<string, QueueRow[]>();
  for (const q of rows) { const a = byStore.get(q.store_id) ?? []; a.push(q); byStore.set(q.store_id, a); }
  const summary: Record<string, number> = { ok: 0, skipped_same: 0, skipped_off: 0, error: 0 };
  const stores: Array<Record<string, unknown>> = [];
  let stopped: string | null = null;
  for (const [storeId, qs] of byStore) {
    if (stopped) break;
    const store: StoreRow | undefined = (await sbGet("shop_store?select=id,code,shop_domain,secret_prefix,is_active,label,kind&id=eq." + storeId + "&limit=1"))[0];
    const now = new Date().toISOString();
    if (!store || !store.is_active) { await patchQueue(qs.map((q) => q.id), { started_at: now, done_at: now, result: "error", error: "store missing or switched off" }); summary.error += qs.length; continue; }
    await patchQueue(qs.map((q) => q.id), { started_at: now });
    const pids = [...new Set(qs.map((q) => q.product_id))];
    let payload: StockPayloadRow[];
    try { payload = (await sbRpc("shop_stock_payload", { p_store_id: store.id, p_product_ids: pids })) as StockPayloadRow[]; }
    catch (e) {
      const msg = "payload: " + String((e as Error)?.message ?? e).slice(0, 300);
      await patchQueue(qs.map((q) => q.id), { done_at: new Date().toISOString(), result: "error", error: msg }); summary.error += qs.length;
      await recordCall({ store_id: store.id, action: "stock_drain", ok: false, http_status: null, query_cost: null, throttle_available: null, error: msg, by_staff: caller.staffId, ms: Date.now() - t0 });
      continue;
    }
    const sent: SentRow[] = await sbGet("shop_stock_sent?select=product_id,warehouse_id,quantity,last_status&store_id=eq." + store.id + "&product_id=in.(" + pids.join(",") + ")");
    const plans = planRows(qs, payload, sent);
    const done = new Date().toISOString();
    for (const r of ["skipped_same", "skipped_off"] as const) { const ids = plans.filter((p) => p.result === r).map((p) => p.queue_id); await patchQueue(ids, { done_at: done, result: r, error: null }); summary[r] += ids.length; }
    for (const p of plans.filter((x) => x.result === "error")) { await patchQueue([p.queue_id], { done_at: done, result: "error", error: p.error }); summary.error++; }
    const toSend = plans.filter((p) => p.result === "send");
    let so: SendOut | null = null;
    if (toSend.length) {
      try { so = await sendStock(store, toSend, toSend[0].queue_id, t0, STOCK_DRAIN_MS); }
      catch (e) {
        const msg = String((e as Error)?.message ?? e).slice(0, 300);
        await patchQueue(toSend.map((p) => p.queue_id), { done_at: new Date().toISOString(), result: "error", error: msg }); summary.error += toSend.length;
        await recordCall({ store_id: store.id, action: "stock_drain", ok: false, http_status: null, query_cost: null, throttle_available: null, error: msg, by_staff: caller.staffId, ms: Date.now() - t0 });
        stores.push({ store: store.code, rows: qs.length, error: msg }); continue;
      }
      const fin = new Date().toISOString();
      for (const [qid, r] of so.rowResult) { await patchQueue([qid], { done_at: fin, result: r.result, error: r.error }); summary[r.result]++; }
      const left = toSend.filter((p) => !so!.rowResult.has(p.queue_id)).map((p) => p.queue_id);
      if (left.length) await patchQueue(left, { started_at: null });                                // 못 보낸 줄은 열어 둔다
      stopped = so.stopped;
    }
    const note = "rows " + qs.length + " · ok " + (so ? [...so.rowResult.values()].filter((r) => r.result === "ok").length : 0) + " · skipped_same " + plans.filter((p) => p.result === "skipped_same").length + " · skipped_off " + plans.filter((p) => p.result === "skipped_off").length + " · error " + (plans.filter((p) => p.result === "error").length + (so ? [...so.rowResult.values()].filter((r) => r.result === "error").length : 0)) + (so ? " · items " + so.items.length + " · activated " + so.items.filter((i) => i.activated).length + " · calls " + so.calls : "") + (stopped ? " · stopped: " + stopped : "");
    await recordCall({ store_id: store.id, action: "stock_drain", ok: !so || !so.items.some((i) => i.result === "error"), http_status: null, query_cost: so?.cost ?? 0, throttle_available: so?.available ?? null, error: note, by_staff: caller.staffId, ms: Date.now() - t0 });
    stores.push({ store: store.code, rows: qs.length, sent_items: so?.items.length ?? 0, activated: so?.items.filter((i) => i.activated).length ?? 0, calls: so?.calls ?? 0, cost: so?.cost ?? 0, errors: so?.items.filter((i) => i.result === "error").map((i) => ({ sku: i.sku, location: i.location_gid, error: i.error })) ?? [] });
  }
  const open = (await sbGet("shop_stock_queue?select=id&done_at=is.null&limit=1")).length > 0;
  return json(200, { ok: true, drained: rows.length, ...summary, stores, stopped, more_open: open, ms: Date.now() - t0 });
}

// stock_push — 직원 · 대상 하나의 변형 전부를 force 로 바로(큐 없이) · 위치별 결과
async function stockPush(store: StoreRow, target: Target, label: string, caller: Caller, t0: number): Promise<Response> {
  const pids: string[] = target.family_id
    ? (await sbGet("product?select=id&family_id=eq." + target.family_id + "&parent_product_id=is.null")).map((r: { id: string }) => r.id)
    : [target.product_id as string];
  const payload = (await sbRpc("shop_stock_payload", { p_store_id: store.id, p_product_ids: pids })) as StockPayloadRow[];
  const fake: QueueRow[] = pids.map((pid, i) => ({ id: -(i + 1), store_id: store.id, product_id: pid, reason: "push", force: true }));
  const plans = planRows(fake, payload, []);
  const so = await sendStock(store, plans, "push-" + Date.now(), t0, STOCK_DRAIN_MS);
  const blocked = plans.filter((p) => p.result !== "send").map((p) => ({ product_id: p.product_id, sku: p.sku, result: p.result, error: p.error }));
  const ok = !so.items.some((i) => i.result === "error") && !so.stopped;
  await recordCall({ store_id: store.id, action: "stock_push", ok, http_status: null, query_cost: so.cost, throttle_available: so.available, error: ok ? "items " + so.items.length + (blocked.length ? " · blocked " + blocked.length : "") : (so.stopped ?? so.items.filter((i) => i.result === "error").map((i) => i.sku + ": " + i.error).join(" · ")), by_staff: caller.staffId, ms: Date.now() - t0 });
  return json(ok ? 200 : 502, { ok, result: ok ? "ok" : "error", store: store.code, target: label, variants: pids.length, sent_items: so.items.length, activated: so.items.filter((i) => i.activated).length, calls: so.calls, cost: so.cost, stopped: so.stopped,
    items: so.items.map((i) => ({ sku: i.sku, location_gid: i.location_gid, warehouse_id: i.warehouse_id, quantity: i.quantity, result: i.result, error: i.error, activated: i.activated })), blocked, api_version: API_VERSION, ms: Date.now() - t0 });
}


// ── 오더 받기(ord-1b) ──────────────────────────────────────────────────────────────
const STORE_SELECT = "shop_store?select=id,code,shop_domain,secret_prefix,is_active,label,kind,orders_polled_at";
type StoreRowO = StoreRow & { orders_polled_at?: string | null };
function gqlErr(g: { status: number; errors: unknown; raw: string | null }): string { return "graphql HTTP " + g.status + (g.errors ? " · " + JSON.stringify(g.errors).slice(0, 300) : "") + (g.raw ? " · " + g.raw.slice(0, 100) : ""); }

// 웹훅 — 문 셋째 · 원문 바이트로 HMAC · 오더 GID 만 받은 일 표에 · 바로 200
async function webhook(req: Request, t0: number): Promise<Response> {
  const head = webhookHead(req.headers)!;
  const bytes = new Uint8Array(await req.arrayBuffer());
  const stores: StoreRowO[] = await sbGet(STORE_SELECT);
  const store = findStoreByDomain(stores, head.domain);
  if (!store) {                                                                                     // 모르는 스토어 — 기록만 · 200(재시도 폭주를 막는다 · 검증은 못 한다: 열쇠를 모른다)
    await recordCall({ store_id: null, action: "webhook", ok: false, http_status: 200, query_cost: null, throttle_available: null, error: "unknown shop domain " + head.domain + " · topic " + head.topic, by_staff: null, ms: Date.now() - t0 });
    return json(200, { ok: false, ignored: "unknown store" });
  }
  const secret = Deno.env.get(secretNames(store.secret_prefix).secret) ?? "";
  if (!(await verifyWebhookHmac(secret, bytes, req.headers.get("x-shopify-hmac-sha256")))) {
    await recordCall({ store_id: store.id, action: "webhook", ok: false, http_status: 401, query_cost: null, throttle_available: null, error: "hmac mismatch · topic " + head.topic + " · webhook " + (head.webhookId ?? "-"), by_staff: null, ms: Date.now() - t0 });
    return json(401, { ok: false, error: "unauthorized" });
  }
  if (!isOrderTopic(head.topic)) {
    await recordCall({ store_id: store.id, action: "webhook", ok: true, http_status: 200, query_cost: null, throttle_available: null, error: "ignored topic " + head.topic, by_staff: null, ms: Date.now() - t0 });
    return json(200, { ok: true, ignored: head.topic });
  }
  let body: unknown = null;
  try { body = JSON.parse(new TextDecoder().decode(bytes)); } catch { body = null; }
  const gid = orderGidFromWebhook(body);
  if (!gid) {
    await recordCall({ store_id: store.id, action: "webhook", ok: false, http_status: 200, query_cost: null, throttle_available: null, error: "no order id in body · topic " + head.topic, by_staff: null, ms: Date.now() - t0 });
    return json(200, { ok: false, ignored: "no order id" });
  }
  const inboxId = await sbRpc("shop_order_inbox_add", { p_store_id: store.id, p_order_gid: gid, p_topic: head.topic, p_webhook_id: head.webhookId, p_event_id: head.eventId });
  await recordCall({ store_id: store.id, action: "webhook", ok: true, http_status: 200, query_cost: null, throttle_available: null, error: head.topic + " " + gid.split("/").pop() + (inboxId === null ? " · duplicate (already open or same delivery)" : " · inbox " + inboxId), by_staff: null, ms: Date.now() - t0 });
  return json(200, { ok: true, inbox_id: inboxId, duplicate: inboxId === null, topic: head.topic, order_gid: gid, ms: Date.now() - t0 });
}

// 오더 하나 읽기 — GID · 숫자 · 이름(#1001) → ① 쿼리 원문 · errors 그대로
async function readOrder(store: StoreRow, ref: string): Promise<{ gid: string | null; order: Record<string, unknown> | null; errors: Array<{ message?: string }> | null; cost: number; status: number; raw: string | null; notFound: boolean }> {
  const r = orderRef(ref);
  if (!r) return { gid: null, order: null, errors: [{ message: "give an order GID, id or name" }], cost: 0, status: 400, raw: null, notFound: false };
  let gid: string | null = "gid" in r ? r.gid : null, cost = 0;
  if (!gid) {
    const gq = await shopifyGql(store, ORDER_BY_NAME_QUERY, { q: "query" in r ? r.query : "" });
    cost += gq.cost.actual ?? 0;
    if (!gq.ok) return { gid: null, order: null, errors: gq.errors ?? [{ message: gqlErr(gq) }], cost, status: gq.status, raw: gq.raw, notFound: false };
    gid = (gq.data as { orders?: { nodes?: Array<{ id: string }> } } | null)?.orders?.nodes?.[0]?.id ?? null;
    if (!gid) return { gid: null, order: null, errors: null, cost, status: gq.status, raw: null, notFound: true };
  }
  const g = await shopifyGql(store, ORDER_READ_QUERY, { id: gid });
  cost += g.cost.actual ?? 0;
  const order = ((g.data as { order?: Record<string, unknown> | null } | null)?.order ?? null);
  return { gid, order, errors: g.errors, cost, status: g.status, raw: g.raw, notFound: g.ok && !order };
}
async function orderRead(store: StoreRow, ref: string, caller: Caller, t0: number): Promise<Response> {
  const r = await readOrder(store, ref);
  const report = redactionReport(r.order, r.errors);
  const ok = !!r.order;
  await recordCall({ store_id: store.id, action: "order_read", ok, http_status: r.status, query_cost: r.cost, throttle_available: null, error: ok ? (report.not_approved ? "not approved for customer data" : null) : (r.notFound ? "not found: " + ref : JSON.stringify(r.errors ?? "").slice(0, 300)), by_staff: caller.staffId, ms: Date.now() - t0 });
  return json(ok ? 200 : (r.notFound ? 404 : 502), { ok, store: store.code, ref, gid: r.gid, redaction: report, order: r.order, errors: r.errors, cost: r.cost, api_version: API_VERSION, ms: Date.now() - t0 });
}

// 구독 — 목록 · 없는 주제만 만든다(shop-specific · 이 함수 주소)
async function webhooksList(store: StoreRow, caller: Caller, t0: number): Promise<Response> {
  const g = await shopifyGql(store, WEBHOOK_LIST_QUERY);
  const nodes = ((g.data as { webhookSubscriptions?: { nodes?: SubNode[] } } | null)?.webhookSubscriptions?.nodes ?? []) as SubNode[];
  await recordCall({ store_id: store.id, action: "webhooks_list", ok: g.ok, http_status: g.status, query_cost: g.cost.actual, throttle_available: g.cost.available, error: g.ok ? "subscriptions " + nodes.length : gqlErr(g), by_staff: caller.staffId, ms: Date.now() - t0 });
  if (!g.ok) return json(502, { ok: false, store: store.code, error: gqlErr(g) });
  const uri = webhookUri(SB_URL());
  return json(200, { ok: true, store: store.code, uri, subscriptions: nodes, missing: missingSubscriptions(nodes, uri), api_version: API_VERSION, ms: Date.now() - t0 });
}
async function webhooksSubscribe(store: StoreRow, caller: Caller, t0: number): Promise<Response> {
  const uri = webhookUri(SB_URL());
  const gl = await shopifyGql(store, WEBHOOK_LIST_QUERY);
  if (!gl.ok) { await recordCall({ store_id: store.id, action: "webhooks_subscribe", ok: false, http_status: gl.status, query_cost: gl.cost.actual, throttle_available: null, error: gqlErr(gl), by_staff: caller.staffId, ms: Date.now() - t0 }); return json(502, { ok: false, store: store.code, error: gqlErr(gl) }); }
  let nodes = ((gl.data as { webhookSubscriptions?: { nodes?: SubNode[] } } | null)?.webhookSubscriptions?.nodes ?? []) as SubNode[];
  const created: SubNode[] = [], failed: Array<{ topic: string; error: string }> = [];
  let cost = gl.cost.actual ?? 0;
  for (const topic of missingSubscriptions(nodes, uri)) {
    const g = await shopifyGql(store, WEBHOOK_SUBSCRIBE_MUTATION, { topic, uri });
    cost += g.cost.actual ?? 0;
    const d = (g.data as { webhookSubscriptionCreate?: { webhookSubscription?: SubNode | null; userErrors?: Array<{ message?: string }> } } | null)?.webhookSubscriptionCreate;
    if (!g.ok || !d?.webhookSubscription || (d.userErrors ?? []).length) failed.push({ topic, error: (d?.userErrors ?? []).map((e) => e.message).join(" · ") || gqlErr(g) });
    else { created.push(d.webhookSubscription); nodes = [...nodes, d.webhookSubscription]; }
  }
  await recordCall({ store_id: store.id, action: "webhooks_subscribe", ok: !failed.length, http_status: gl.status, query_cost: cost, throttle_available: null, error: "created " + created.map((c) => c.topic).join(",") + (failed.length ? " · failed " + failed.map((f) => f.topic + ": " + f.error).join(" · ") : ""), by_staff: caller.staffId, ms: Date.now() - t0 });
  return json(failed.length ? 502 : 200, { ok: !failed.length, store: store.code, uri, created, failed, subscriptions: nodes, missing: missingSubscriptions(nodes, uri), wanted: ORDER_TOPICS, api_version: API_VERSION, ms: Date.now() - t0 });
}

// 주기 확인 — 스토어마다 updated_at 뒤의 오더를 받은 일 표에(웹훅이 빠진 것 줍기)
async function ordersPoll(caller: Caller, t0: number): Promise<Response> {
  const stores: StoreRowO[] = (await sbGet(STORE_SELECT + "&is_active=eq.true")) as StoreRowO[];
  const out: Array<Record<string, unknown>> = [];
  for (const store of stores) {
    const since = pollSince(store.orders_polled_at ?? null);
    let after: string | null = null, pages = 0, seen = 0, added = 0, skippedSame = 0, skippedOpen = 0, cost = 0, err: string | null = null, maxSeen: string | null = store.orders_polled_at ?? null;
    for (;;) {
      const g = await shopifyGql(store, ORDERS_SINCE_QUERY, { q: pollQuery(since), after });
      cost += g.cost.actual ?? 0; pages++;
      if (!g.ok) { err = gqlErr(g); break; }
      const d = (g.data as { orders?: { pageInfo?: { hasNextPage?: boolean; endCursor?: string | null }; nodes?: Array<{ id: string; updatedAt?: string | null }> } } | null)?.orders;
      const nodes = d?.nodes ?? [];
      seen += nodes.length;
      // ord-1b3 — 바뀐 오더만: 이 페이지의 GID 들을 shop_order 에서 한 번 읽어 updatedAt 을 견준다 · 같으면 skipped_same · 열린 받은 일 줄이 있으면 inbox_add 가 null → skipped_open
      const known: KnownOrder[] = nodes.length ? (await sbGet("shop_order?select=shopify_order_gid,shopify_updated_at&store_id=eq." + store.id + "&shopify_order_gid=" + encodeURIComponent(gidInFilter(nodes.map((n) => n.id))))) as KnownOrder[] : [];
      const pick = pollPick(nodes, known);
      skippedSame += pick.same.length;
      for (const n of pick.add) { if ((await sbRpc("shop_order_inbox_add", { p_store_id: store.id, p_order_gid: n.id, p_topic: "poll", p_webhook_id: null, p_event_id: null })) !== null) added++; else skippedOpen++; }
      maxSeen = maxUpdatedAt(nodes, maxSeen);
      if (!d?.pageInfo?.hasNextPage || !d.pageInfo.endCursor || pages >= POLL_PAGES_MAX) break;
      after = d.pageInfo.endCursor;
    }
    if (!err) await sbWrite("PATCH", "shop_store?id=eq." + store.id, { orders_polled_at: maxSeen ?? new Date().toISOString() });
    await recordCall({ store_id: store.id, action: "orders_poll", ok: !err, http_status: null, query_cost: cost, throttle_available: null, error: err ?? ("since " + since + " · seen " + seen + " · added " + added + " · skipped_same " + skippedSame + " · skipped_open " + skippedOpen + " · pages " + pages), by_staff: caller.staffId, ms: Date.now() - t0 });
    out.push({ store: store.code, since, seen, added, skipped_same: skippedSame, skipped_open: skippedOpen, pages, cost, polled_at: err ? store.orders_polled_at ?? null : maxSeen, error: err });
  }
  return json(200, { ok: out.every((o) => !o.error), stores: out, ms: Date.now() - t0 });
}

// drain — 받은 일 열린 줄 → GraphQL 다시 읽기 → ingest → (received) process → 줄 닫기
type InboxRow = { id: number; store_id: string; order_gid: string; topic: string };
async function ordersDrain(caller: Caller, t0: number): Promise<Response> {
  const rows: InboxRow[] = await sbGet("shop_order_inbox?select=id,store_id,order_gid,topic&done_at=is.null&order=received_at.asc,id.asc&limit=" + INBOX_FETCH);
  const stores: Record<string, StoreRowO | undefined> = {};
  const out: Array<Record<string, unknown>> = [];
  const summary: Record<string, number> = {};
  const doneGids = new Set<string>();
  let stopped: string | null = null;
  for (const q of rows) {
    stopped = drainStop(Date.now() - t0, ORDERS_DRAIN_MS);
    if (stopped) break;
    const tq = Date.now();
    if (doneGids.has(q.order_gid)) {                                                                // 같은 오더의 다른 열린 줄 — 방금 읽었다
      await sbWrite("PATCH", "shop_order_inbox?id=eq." + q.id, { started_at: new Date().toISOString(), done_at: new Date().toISOString(), result: "dup", error: null });
      summary.dup = (summary.dup ?? 0) + 1; out.push({ id: q.id, order_gid: q.order_gid, result: "dup" }); continue;
    }
    await sbWrite("PATCH", "shop_order_inbox?id=eq." + q.id, { started_at: new Date().toISOString() });
    if (!stores[q.store_id]) stores[q.store_id] = ((await sbGet(STORE_SELECT + "&id=eq." + q.store_id + "&limit=1")) as StoreRowO[])[0];
    const store = stores[q.store_id];
    let result = "error", error: string | null = null, cost = 0, shopOrderId: string | null = null, soNumber: string | null = null;
    try {
      if (!store || !store.is_active) throw new Error("store missing or switched off");
      const r = await readOrder(store, q.order_gid);
      cost = r.cost;
      if (r.notFound) { result = "not_found"; error = "order not in Shopify (or older than 60 days)"; }
      else if (!r.order) throw new Error(JSON.stringify(r.errors ?? r.raw ?? "read failed").slice(0, 300));
      else {
        const ing = (await sbRpc("shop_order_ingest", { p_store_id: store.id, p_order: r.order })) as { shop_order_id?: string; status?: string; action?: string };
        shopOrderId = ing.shop_order_id ?? null; result = String(ing.status ?? "error");
        if (drainNext(ing) === "process") {
          const pr = (await sbRpc("shop_order_process", { p_shop_order_id: ing.shop_order_id })) as { status?: string; so_number?: string; error?: string; warnings?: unknown[] };
          result = String(pr.status ?? result); soNumber = pr.so_number ?? null; error = pr.error ?? null;
        }
      }
    } catch (e) { result = "error"; error = String((e as Error)?.message ?? e).slice(0, 400); }
    await sbWrite("PATCH", "shop_order_inbox?id=eq." + q.id, { done_at: new Date().toISOString(), result, error });
    doneGids.add(q.order_gid);
    summary[result] = (summary[result] ?? 0) + 1;
    await recordCall({ store_id: store?.id ?? null, action: "orders_drain", ok: result !== "error", http_status: null, query_cost: cost, throttle_available: null, error: q.topic + " " + q.order_gid.split("/").pop() + " → " + result + (soNumber ? " " + soNumber : "") + (error ? " · " + error : ""), by_staff: caller.staffId, ms: Date.now() - tq });
    out.push({ id: q.id, order_gid: q.order_gid, topic: q.topic, result, shop_order_id: shopOrderId, so_number: soNumber, error, cost, ms: Date.now() - tq });
  }
  // ord-1b2 — 받은 일 줄 없는 received(직원이 resolve 로 푼 것 · 앞 회차가 멈춘 것): 다시 읽지 않고 저장된 원문으로 process 만
  const swept: Array<Record<string, unknown>> = [];
  if (!stopped) {
    const received: Array<ReceivedRow & { store_id: string; name: string }> = await sbGet("shop_order?select=id,store_id,shopify_order_gid,name&status=eq.received&order=received_at.asc,id.asc&limit=" + INBOX_FETCH);
    const openGids = new Set<string>(received.length ? (await sbGet("shop_order_inbox?select=order_gid&done_at=is.null&limit=1000") as Array<{ order_gid: string }>).map((r) => r.order_gid) : []);
    for (const o of sweepPick(received, openGids, doneGids)) {
      stopped = drainStop(Date.now() - t0, ORDERS_DRAIN_MS);
      if (stopped) break;
      const tq = Date.now();
      let result = "error", error: string | null = null, soNumber: string | null = null;
      try {
        const pr = (await sbRpc("shop_order_process", { p_shop_order_id: o.id })) as { status?: string; so_number?: string; error?: string; skipped?: boolean };
        result = String(pr.status ?? "error"); soNumber = pr.so_number ?? null; error = pr.error ?? (pr.skipped ? "skipped (no longer received)" : null);
      } catch (e) { result = "error"; error = String((e as Error)?.message ?? e).slice(0, 400); }
      summary["swept_" + result] = (summary["swept_" + result] ?? 0) + 1;
      await recordCall({ store_id: o.store_id, action: "orders_drain", ok: result !== "error", http_status: null, query_cost: null, throttle_available: null, error: "sweep " + o.name + " → " + result + (soNumber ? " " + soNumber : "") + (error ? " · " + error : ""), by_staff: caller.staffId, ms: Date.now() - tq });
      swept.push({ shop_order_id: o.id, order_gid: o.shopify_order_gid, name: o.name, result, so_number: soNumber, error, ms: Date.now() - tq });
    }
  }
  const open = (await sbGet("shop_order_inbox?select=id&done_at=is.null&limit=1")).length > 0;
  const receivedLeft = (await sbGet("shop_order?select=id&status=eq.received&limit=1")).length > 0;
  return json(200, { ok: true, drained: out.length, ...summary, results: out, swept, stopped, more_open: open || receivedLeft, ms: Date.now() - t0 });
}

// ── 발송 보내기(ful-2) ──────────────────────────────────────────────────────────────
type FulQueueRow = { id: number; so_id: string; kind: string; attempts: number; queued_at: string };
type FulOut = { status: "sent" | "skipped" | "error"; gid: string | null; fo: string | null; path: string | null; cut: number; warns: string[]; cost: number; error: string | null };
const patchFulQueue = (id: number, body: Record<string, unknown>) => sbWrite("PATCH", "shop_fulfill_queue?id=eq." + id, body);
const nowIso = () => new Date().toISOString();
async function warnOrder(shopOrderId: string, code: string, message: string): Promise<void> {
  try { await sbRpc("shop_order_warn", { p_shop_order_id: shopOrderId, p_code: code, p_message: message.slice(0, 300) }); }
  catch (e) { console.warn("shop_order_warn failed:", String(e).slice(0, 200)); }
}
// 결과 표 머리 하나를 Shopify 로 — 읽기 → 짝 → 위치 → (Ready for pickup | fulfillmentCreate) → 표에 적기 · 실패는 예외로(부르는 쪽이 error 로 적는다)
async function sendFulfillment(store: StoreRow, f: FulRow): Promise<FulOut> {
  const out: FulOut = { status: "error", gid: null, fo: null, path: null, cut: 0, warns: [], cost: 0, error: null };
  const so: Array<{ id: string; shopify_order_gid: string; name: string }> = await sbGet("shop_order?select=id,shopify_order_gid,name&id=eq." + f.shop_order_id + "&limit=1");
  if (!so[0]) throw new Error("shop_order " + f.shop_order_id + " not found");
  const lines: FulLine[] = await sbGet("shop_fulfillment_line?select=id,line_gid,so_line_id,quantity,quantity_sent&fulfillment_id=eq." + f.id + "&order=line_gid.asc");
  if (!lines.length) throw new Error("fulfillment " + f.id + " has no lines");
  const template = f.carrier_id ? String((await sbGet("ref_carrier?select=tracking_url_template&id=eq." + f.carrier_id + "&limit=1"))[0]?.tracking_url_template ?? "") : "";
  const g = await shopifyGql(store, FULFILL_ORDERS_QUERY, { id: so[0].shopify_order_gid });
  out.cost += g.cost.actual ?? 0;
  if (!g.ok) throw new Error("read: " + gqlErr(g));
  const order = (g.data as { order?: { fulfillmentOrders?: { nodes?: FoNode[] }; fulfillments?: FulfillmentNode[] } | null } | null)?.order;
  if (!order) throw new Error("order " + so[0].name + " not in Shopify (or older than 60 days)");
  const fos = order.fulfillmentOrders?.nodes ?? [];
  const plan = planLines(lines, fos);
  const stamp = nowIso();
  if (!plan.items.length) {                                                                         // 보낼 것이 없다 — 우리 발송이면 받아 적는다 · 아니면 skipped + 경고
    const adopt = adoptExisting(f, order.fulfillments ?? []);
    for (const l of lines) await sbWrite("PATCH", "shop_fulfillment_line?id=eq." + l.id, { quantity_sent: adopt ? l.quantity : 0 });
    if (adopt) {
      await sbWrite("PATCH", "shop_fulfillment?id=eq." + f.id, { status: "sent", shopify_fulfillment_gid: adopt, sent_at: stamp, last_error: "adopted: fulfillment already in Shopify (recorded on retry)", attempts: f.attempts + 1 });
      return { ...out, status: "sent", gid: adopt, path: "adopt" };
    }
    await sbWrite("PATCH", "shop_fulfillment?id=eq." + f.id, { status: "skipped", last_error: "nothing left to fulfill in Shopify (" + lines.length + " lines · remaining 0)", attempts: f.attempts + 1 });
    await warnOrder(f.shop_order_id, "fulfill_nothing_left", "IMS " + f.carrier_name + " shipment: Shopify had nothing left to fulfill (fulfilled or cancelled in Shopify first?) — nothing was sent");
    return { ...out, status: "skipped", path: "skipped", warns: ["fulfill_nothing_left"] };
  }
  let items: PlanItem[] = plan.items;
  // 위치 — SO 창고의 Shopify 위치 짝 · 다르면 move(보낼 줄 · 수량만) · 실패면 그대로 보내고 경고(판정 453)
  const soRow: Array<{ location_id: string | null }> = await sbGet("so?select=location_id&id=eq." + f.so_id + "&limit=1");
  const pair: Array<{ shopify_location_gid: string }> = soRow[0]?.location_id ? await sbGet("shop_location?select=shopify_location_gid&store_id=eq." + f.store_id + "&warehouse_id=eq." + soRow[0].location_id + "&is_active=eq.true&limit=1") : [];
  const target = pair[0]?.shopify_location_gid ?? null;
  for (const mv of movesNeeded(items, fos, target)) {
    const gm = await shopifyGql(store, FULFILLMENT_ORDER_MOVE_MUTATION, { id: mv.fo_id, newLocationId: target, items: mv.items });
    out.cost += gm.cost.actual ?? 0;
    const d = (gm.data as { fulfillmentOrderMove?: { movedFulfillmentOrder?: FoNode | null; userErrors?: UserErr[] } } | null)?.fulfillmentOrderMove;
    const ue = d?.userErrors ?? [];
    if (!gm.ok || ue.length || !d?.movedFulfillmentOrder) {
      const why = ue.length ? userErrorsText(ue) : gqlErr(gm);
      out.warns.push("fulfill_location_mismatch");
      await warnOrder(f.shop_order_id, "fulfill_location_mismatch", "Shopify kept the fulfillment at " + (mv.from_location ?? "?") + " — move to the IMS warehouse location failed: " + why + " — shipment sent anyway");
      continue;
    }
    const r = remapAfterMove(items, mv.fo_id, d.movedFulfillmentOrder);
    items = r.items;
    if (d.movedFulfillmentOrder.id !== mv.fo_id) fos.push(d.movedFulfillmentOrder);              // 새 FO 면 pickupPath · 기록이 그것을 본다
  }
  const foIds = [...new Set(items.map((i) => i.fo_id))];
  out.fo = foIds[0] ?? null;
  const path = pickupPath(f.carrier_kind, items, fos);
  out.path = path;
  if (path === "ready_pickup") {
    const gp = await shopifyGql(store, PREPARED_FOR_PICKUP_MUTATION, { input: preparedForPickupInput(foIds) });
    out.cost += gp.cost.actual ?? 0;
    const ue = (gp.data as { fulfillmentOrderLineItemsPreparedForPickup?: { userErrors?: UserErr[] } } | null)?.fulfillmentOrderLineItemsPreparedForPickup?.userErrors ?? [];
    if (!gp.ok) throw new Error("ready for pickup: " + gqlErr(gp));
    if (ue.length && adoptReadyError(ue)) {                                                       // ful-2c: Shopify 가 「준비할 줄이 없다」 = 이미 Ready(직원이 Shopify 에서 먼저) → 받아 적는다(쓴 것 없음 · last_push_at 없음 · 경고 없음)
      const readyAt = readyAtFromFos(fos, foIds, stamp);
      await sbWrite("PATCH", "shop_fulfillment?id=eq." + f.id, { status: "sent", ready_at: readyAt, sent_at: stamp, fulfillment_order_gid: out.fo, last_error: "adopted: already ready in Shopify (Ready for pickup was done in Shopify before IMS) — " + userErrorsText(ue).slice(0, 200), attempts: f.attempts + 1 });
      out.path = "ready_adopt";
    } else {
      if (ue.length) throw new Error("ready for pickup: " + userErrorsText(ue));
      await sbWrite("PATCH", "shop_fulfillment?id=eq." + f.id, { status: "sent", ready_at: stamp, sent_at: stamp, fulfillment_order_gid: out.fo, last_error: null, attempts: f.attempts + 1, last_push_at: stamp });
    }
  } else {
    const gc = await shopifyGql(store, FULFILLMENT_CREATE_MUTATION, { fulfillment: buildFulfillmentInput(f, items, template) });
    out.cost += gc.cost.actual ?? 0;
    const d = (gc.data as { fulfillmentCreate?: { fulfillment?: { id: string; status?: string } | null; userErrors?: UserErr[] } } | null)?.fulfillmentCreate;
    const ue = d?.userErrors ?? [];
    if (!gc.ok || ue.length || !d?.fulfillment?.id) throw new Error("fulfillmentCreate: " + (ue.length ? userErrorsText(ue) : gqlErr(gc)));
    out.gid = d.fulfillment.id;
    await sbWrite("PATCH", "shop_fulfillment?id=eq." + f.id, { status: "sent", shopify_fulfillment_gid: out.gid, sent_at: stamp, fulfillment_order_gid: out.fo, last_error: null, attempts: f.attempts + 1, last_push_at: stamp });
  }
  for (const l of lines) {
    const foLine = items.find((i) => i.line_id === l.id)?.fo_line_id ?? null;
    await sbWrite("PATCH", "shop_fulfillment_line?id=eq." + l.id, { quantity_sent: plan.sent_by_line[l.id] ?? 0, fulfillment_order_line_item_gid: foLine });
  }
  if (plan.cut.length || plan.nothing.length) {                                                     // 자른 줄 · 남은 것이 없던 줄 — 경고 한 줄(판정 442 · 미룬 201 b)
    out.cut = plan.cut.length + plan.nothing.length;
    out.warns.push("fulfill_cut");
    const parts = [...plan.cut.map((c) => c.line_gid.split("/").pop() + ": wanted " + c.wanted + " · sent " + c.sent), ...plan.nothing.map((id) => (lines.find((l) => l.id === id)?.line_gid ?? id).split("/").pop() + ": nothing left in Shopify")];
    await warnOrder(f.shop_order_id, "fulfill_cut", "Shopify had less left to fulfill than IMS shipped — " + parts.join("; "));
  }
  out.status = "sent";
  return out;
}
// ful-1b 판정 443: Picked up — 창구가 적은 픽업 머리(ready_at · picked_up_at · GID 없음)의 픽업 FO 에 fulfillmentCreate(notify false · 송장 없음) → GID · FO 가 닫혔거나 없으면 받아 적기(adopt · Ready 이후의 송장 없는 발송)
async function sendPickedUp(store: StoreRow, f: FulRow): Promise<FulOut> {
  const out: FulOut = { status: "error", gid: null, fo: f.fulfillment_order_gid ?? null, path: "picked_up", cut: 0, warns: [], cost: 0, error: null };
  const so: Array<{ id: string; shopify_order_gid: string; name: string }> = await sbGet("shop_order?select=id,shopify_order_gid,name&id=eq." + f.shop_order_id + "&limit=1");
  if (!so[0]) throw new Error("shop_order " + f.shop_order_id + " not found");
  const lines: FulLine[] = await sbGet("shop_fulfillment_line?select=id,line_gid,so_line_id,quantity,quantity_sent&fulfillment_id=eq." + f.id + "&order=line_gid.asc");
  const g = await shopifyGql(store, FULFILL_ORDERS_QUERY, { id: so[0].shopify_order_gid });
  out.cost += g.cost.actual ?? 0;
  if (!g.ok) throw new Error("read: " + gqlErr(g));
  const order = (g.data as { order?: { fulfillmentOrders?: { nodes?: FoNode[] }; fulfillments?: FulfillmentNode[] } | null } | null)?.order;
  if (!order) throw new Error("order " + so[0].name + " not in Shopify (or older than 60 days)");
  const stamp = nowIso();
  const fo = pickupFo(f, order.fulfillmentOrders?.nodes ?? []);
  if (fo) {
    const plan = planLines(lines.map((l) => ({ ...l, quantity: l.quantity_sent ?? l.quantity })), [fo]);         // Ready 때 보낸 수량만(자른 뒤) · 남은 것이 없으면 아래 adopt
    if (plan.items.length) {
      const gc = await shopifyGql(store, FULFILLMENT_CREATE_MUTATION, { fulfillment: buildFulfillmentInput(f, plan.items, "") });   // kind pickup → trackingInfo 없음 · notifyCustomer false
      out.cost += gc.cost.actual ?? 0;
      const d = (gc.data as { fulfillmentCreate?: { fulfillment?: { id: string } | null; userErrors?: UserErr[] } } | null)?.fulfillmentCreate;
      const ue = d?.userErrors ?? [];
      if (!gc.ok || ue.length || !d?.fulfillment?.id) throw new Error("picked up (fulfillmentCreate): " + (ue.length ? userErrorsText(ue) : gqlErr(gc)));
      await sbWrite("PATCH", "shop_fulfillment?id=eq." + f.id, { shopify_fulfillment_gid: d.fulfillment.id, last_error: null, attempts: f.attempts + 1, last_push_at: stamp });
      return { ...out, status: "sent", gid: d.fulfillment.id };
    }
  }
  const adopt = adoptExisting({ ...f, created_at: f.ready_at ?? f.created_at }, order.fulfillments ?? []);
  if (adopt) {
    await sbWrite("PATCH", "shop_fulfillment?id=eq." + f.id, { shopify_fulfillment_gid: adopt, last_error: "adopted: pickup fulfillment already in Shopify (recorded on retry)", attempts: f.attempts + 1 });
    return { ...out, status: "sent", gid: adopt, path: "adopt" };
  }
  throw new Error("pickup fulfillment order " + (f.fulfillment_order_gid ?? "?") + " is not open in Shopify and no fulfillment to adopt — mark it picked up in Shopify by hand");
}
// ful-1b 판정 438: 송장 고침 — GID 있는 carrier 머리마다 fulfillmentTrackingInfoUpdate(company · numbers · urls · notifyCustomer false) · 값은 창구 so_tracking_fix 가 결과 표에 적어 둔 것
async function sendTrackingFix(store: StoreRow, f: FulRow): Promise<FulOut> {
  const out: FulOut = { status: "error", gid: f.shopify_fulfillment_gid ?? null, fo: f.fulfillment_order_gid ?? null, path: "tracking_fix", cut: 0, warns: [], cost: 0, error: null };
  if (!f.shopify_fulfillment_gid) throw new Error("fulfillment " + f.id + " has no Shopify fulfillment GID — nothing to update");
  const template = f.carrier_id ? String((await sbGet("ref_carrier?select=tracking_url_template&id=eq." + f.carrier_id + "&limit=1"))[0]?.tracking_url_template ?? "") : "";
  const stamp = nowIso();
  const gt = await shopifyGql(store, TRACKING_UPDATE_MUTATION, { fulfillmentId: f.shopify_fulfillment_gid, trackingInfoInput: buildTrackingInput(f, template), notifyCustomer: false });
  out.cost += gt.cost.actual ?? 0;
  const d = (gt.data as { fulfillmentTrackingInfoUpdate?: { fulfillment?: { id: string } | null; userErrors?: UserErr[] } } | null)?.fulfillmentTrackingInfoUpdate;
  const ue = d?.userErrors ?? [];
  if (!gt.ok || ue.length || !d?.fulfillment?.id) throw new Error("fulfillmentTrackingInfoUpdate: " + (ue.length ? userErrorsText(ue) : gqlErr(gt)));
  await sbWrite("PATCH", "shop_fulfillment?id=eq." + f.id, { last_error: null, last_push_at: stamp });
  return { ...out, status: "sent" };
}
// ── 나가지 않을 몫 · Shopify 오더 고치기(ful-4b) ───────────────────────────────────────────────────────
type OrderQueueRow = { id: number; shop_order_id: string; kind: string; attempts: number; queued_at: string; payload: Record<string, unknown> };
type EditOut = { status: "done" | "skipped" | "error"; removed: number; lines: number; reason: string | null; cost: number; error: string | null; final?: boolean };
const patchOrderQueue = (id: number, body: Record<string, unknown>) => sbWrite("PATCH", "shop_order_queue?id=eq." + id, body);
// 오더 하나의 재료 — DB 줄 · can_ship(rpc · 그 순간) · Shopify 실시간 줄 · 계획(begin 전까지 · 쓰기 0)
type EditCtx = { lines: DbLine[]; order: { cancelledAt?: string | null; displayFinancialStatus?: string | null; lineItems?: { nodes?: LiveLine[] } }; live: LiveLine[]; plan: Plan; cost: number };
async function readEditContext(store: StoreRow, o: { id: string; shopify_order_gid: string; name: string }): Promise<EditCtx> {
  const dbLines: Array<{ id: string; line_gid: string; quantity: number | string }> = await sbGet("shop_order_line?select=id,line_gid,quantity&shop_order_id=eq." + o.id + "&order=line_no.asc");
  const can = (await sbRpc("shop_order_can_ship", { p_shop_order_id: o.id })) as Array<{ shop_order_line_id: string; can_ship: number | string }>;   // §0 이견 2: 그 순간 다시 센다
  const canBy = new Map(can.map((c) => [c.shop_order_line_id, c.can_ship]));
  const lines: DbLine[] = dbLines.map((l) => ({ shop_order_line_id: l.id, line_gid: l.line_gid, quantity: l.quantity, can_ship: canBy.get(l.id) ?? 0 }));
  const g = await shopifyGql(store, ORDER_LINES_QUERY, { id: o.shopify_order_gid });
  if (!g.ok) throw new Error("read: " + gqlErr(g));
  const order = (g.data as { order?: EditCtx["order"] | null } | null)?.order;
  if (!order) throw new Error("order " + o.name + " not in Shopify (or older than 60 days)");
  const live = order.lineItems?.nodes ?? [];
  return { lines, order, live, plan: planOrderEdit(lines, live), cost: g.cost.actual ?? 0 };
}
// begin → calc 줄 · 짝 · setQuantity 값(calc 기준 · 실물 #1011) — 보내지는 않는다
type EditStep = { line_gid: string; sku: string | null; to_remove: number; calc: CalcLine | null; set: { quantity: number; change: number; clamped: boolean } | null };
async function beginEdit(store: StoreRow, gid: string, plan: Plan, live: LiveLine[]): Promise<{ calcId: string; calc: CalcLine[]; steps: EditStep[]; cost: number }> {
  const gb = await shopifyGql(store, ORDER_EDIT_BEGIN_MUTATION, { id: gid });
  const db = (gb.data as { orderEditBegin?: { calculatedOrder?: { id: string; lineItems?: { nodes?: CalcLine[] } } | null; userErrors?: Array<{ field?: string[] | null; message?: string }> } } | null)?.orderEditBegin;
  if (!gb.ok || db?.userErrors?.length || !db?.calculatedOrder?.id) throw new Error("orderEditBegin: " + (db?.userErrors?.length ? editErrorsText(db.userErrors) : gqlErr(gb)));
  const calc = db.calculatedOrder.lineItems?.nodes ?? [];
  const steps: EditStep[] = plan.edits.filter((e) => e.to_remove > 0).map((e) => {
    const lv = live.find((l) => l.id === e.line_gid)!;
    const c = matchCalcLine(lv, calc);
    return { line_gid: e.line_gid, sku: lv.sku ?? null, to_remove: e.to_remove, calc: c, set: c ? setQuantityFor(c, e.to_remove) : null };
  });
  return { calcId: db.calculatedOrder.id, calc, steps, cost: gb.cost.actual ?? 0 };
}
// 오더 하나 — 실시간 읽기 → 가르기(취소 · 돈 받음) → 계획 → (0 이면 받아 적기) → begin → setQuantity(바뀌는 줄만) → commit → 장부 · last_push_at · 실패는 예외로(부르는 쪽이 error 로 적는다)
async function editShopOrder(store: StoreRow, o: { id: string; shopify_order_gid: string; name: string }): Promise<EditOut> {
  const out: EditOut = { status: "error", removed: 0, lines: 0, reason: null, cost: 0, error: null };
  const ctx = await readEditContext(store, o);
  out.cost += ctx.cost;
  const { lines, order, live, plan } = ctx;
  const stamp = nowIso();
  const writeRemoved = async (after: LiveLine[]) => {                                              // ⑥ removed_qty = 원래 − 지금(우리가 지운 것 · Shopify 에서 지워진 것 같이)
    const byGid = new Map(after.map((l) => [l.id, l]));
    for (const l of lines) { const v = byGid.get(l.line_gid); if (v) await sbWrite("PATCH", "shop_order_line_unshipped?shop_order_line_id=eq." + l.shop_order_line_id, { removed_qty: removedQty(l.quantity, v.currentQuantity), computed_at: stamp }); }
  };
  if (order.cancelledAt) return { ...out, status: "skipped", reason: "cancelled in Shopify (" + order.cancelledAt + ") — nothing to edit" };   // 판정 456 · 434
  if (isPaid(order.displayFinancialStatus)) return { ...out, status: "skipped", reason: "paid now (" + order.displayFinancialStatus + ") — the next scan takes the refund_due path" };   // 판정 457
  out.lines = plan.edits.filter((e) => e.to_remove > 0).length;
  if (plan.total_remove <= 0) {                                                                     // 받아 적기 — 이미 지워졌거나(직원이 Shopify 에서) 그 사이 나가게 됐다
    await writeRemoved(live);
    return { ...out, status: "done", removed: 0, reason: "nothing to remove now" + (plan.missing.length ? " · " + plan.missing.length + " line(s) not in Shopify" : "") };
  }
  const b = await beginEdit(store, o.shopify_order_gid, plan, live);
  out.cost += b.cost;
  const notes: string[] = [];
  let changed = 0;
  for (const st of b.steps) {
    const short = st.line_gid.split("/").pop();
    if (!st.calc || !st.set) throw new Error("line " + short + " (" + (st.sku ?? "?") + "): cannot tell which calculated line it is (same product twice?) — edit the order in Shopify by hand");
    if (st.set.clamped) notes.push(short + ": wanted −" + st.to_remove + " · editable floor " + st.set.quantity);
    if (st.set.change <= 0) { notes.push(short + ": no change (calc " + st.calc.quantity + " · editable " + st.calc.editableQuantity + " · to_remove " + st.to_remove + ")"); continue; }
    const gs = await shopifyGql(store, ORDER_EDIT_SET_QTY_MUTATION, { id: b.calcId, lineItemId: st.calc.id, quantity: st.set.quantity, restock: true });   // 판정 459
    out.cost += gs.cost.actual ?? 0;
    const ds = (gs.data as { orderEditSetQuantity?: { userErrors?: Array<{ field?: string[] | null; message?: string }> } } | null)?.orderEditSetQuantity;
    if (!gs.ok || ds?.userErrors?.length) throw new Error("orderEditSetQuantity " + short + " → " + st.set.quantity + ": " + (ds?.userErrors?.length ? editErrorsText(ds.userErrors) : gqlErr(gs)));
    changed += st.set.change;
  }
  if (changed <= 0) {                                                                               // 바꿀 줄이 0 — commit 을 보내지 않는다(세션은 버림) · 다시 시도하지 않는 error
    const detail = b.steps.map((st) => st.line_gid.split("/").pop() + " live current " + (live.find((l) => l.id === st.line_gid)?.currentQuantity ?? "?") + " unfulfilled " + (live.find((l) => l.id === st.line_gid)?.unfulfilledQuantity ?? "?") + " · calc " + (st.calc?.quantity ?? "?") + "/" + (st.calc?.editableQuantity ?? "?") + " · to_remove " + st.to_remove).join("; ");
    throw new NoChangeError("nothing would change in Shopify (" + detail + ") — the calculated line already has that quantity; check the order in Shopify by hand");
  }
  const gc = await shopifyGql(store, ORDER_EDIT_COMMIT_MUTATION, { id: b.calcId, notify: false, note: ORDER_EDIT_STAFF_NOTE });   // 판정 441 · 메일 없음
  out.cost += gc.cost.actual ?? 0;
  const dc = (gc.data as { orderEditCommit?: { order?: { lineItems?: { nodes?: Array<{ id: string; quantity: number; currentQuantity: number }> } } | null; userErrors?: Array<{ field?: string[] | null; message?: string }> } } | null)?.orderEditCommit;
  if (!gc.ok || dc?.userErrors?.length || !dc?.order) throw new Error("orderEditCommit: " + (dc?.userErrors?.length ? editErrorsText(dc.userErrors) : gqlErr(gc)));
  const after = (dc.order.lineItems?.nodes ?? []).map((l) => ({ id: l.id, quantity: l.quantity, currentQuantity: l.currentQuantity, unfulfilledQuantity: 0 }));
  await writeRemoved(after);
  await sbWrite("PATCH", "shop_order?id=eq." + o.id, { last_push_at: stamp });                     // 메아리 ⓑ(ful-4a ingest)
  return { ...out, status: "done", removed: changed, reason: notes.length ? notes.join("; ") : null };
}
// 직원 · 쓰기 0(begin 까지 · commit 없음 · 세션은 버린다) — 실물을 그대로 돌려준다: DB 줄 · can_ship · live 줄 · 계획 · calc 줄 · 짝 · setQuantity 에 보낼 값
// ful-4b2 try_set: preview 가 begin 하는 조건과 같을 때 후보 ⓐ · ⓑ 를 세션 따로 열어 setQuantity 까지 보내고(commit 없음 · 큐 · 장부 · 경고 · shop_order* 무접촉) 응답을 그대로 try_set 에 싣는다 · try_set 없으면 응답은 전과 같다
async function orderEditPreview(ref: string, trySet: boolean, caller: Caller, t0: number): Promise<Response> {
  const key = ref.trim();
  if (!key) return json(400, { ok: false, error: "order is required — shop_order id (uuid) or Shopify name like #1011" });
  const filter = /^[0-9a-f-]{36}$/i.test(key) ? "id=eq." + key : "name=eq." + encodeURIComponent(key);
  const o: { id: string; store_id: string; shopify_order_gid: string; name: string; financial_status: string | null } | undefined = (await sbGet("shop_order?select=id,store_id,shopify_order_gid,name,financial_status&" + filter + "&limit=1"))[0];
  if (!o) return json(404, { ok: false, error: "shop_order " + key + " not found" });
  const store: StoreRow | undefined = (await sbGet("shop_store?select=id,code,shop_domain,secret_prefix,is_active,label,kind&id=eq." + o.store_id + "&limit=1"))[0];
  if (!store) return json(404, { ok: false, error: "store not found" });
  const ctx = await readEditContext(store, o);
  let begun: Record<string, unknown> | null = null;
  let tried: TrySetResult[] | null = null;
  if (ctx.plan.total_remove > 0 && !ctx.order.cancelledAt) {
    const b = await beginEdit(store, o.shopify_order_gid, ctx.plan, ctx.live);
    begun = { calculated_order_id: b.calcId, calc_lines: b.calc, steps: b.steps.map((st) => ({ line_gid: st.line_gid, sku: st.sku, to_remove: st.to_remove, matched_calc_id: st.calc?.id ?? null, would_set: st.set })), cost: b.cost };
    if (trySet) tried = await runTrySet((q, v) => shopifyGql(store, q, v), o.shopify_order_gid, ctx.plan, ctx.live, [b.calcId]);   // ful-4b2 · preview 의 세션 id 를 앞선 것으로 넘긴다(contaminated 판정)
  }
  const triedCost = (tried ?? []).reduce((a, r) => a + r.cost, 0);
  const triedText = tried ? " · try_set " + tried.map((r) => r.key + "=" + (r.same_as_a ? "same_as_a" : r.sends.map((x) => x.quantity_sent ?? "-").join("/") + (r.contaminated ? "!" : ""))).join(" ") + " (not committed)" : "";
  await recordCall({ store_id: store.id, action: "order_edit_preview", ok: true, http_status: null, query_cost: ctx.cost + Number((begun?.cost as number) ?? 0) + triedCost, throttle_available: null, error: o.name + " · to_remove " + ctx.plan.total_remove + (begun ? " · begun (not committed)" : " · no begin") + triedText, by_staff: caller.staffId, ms: Date.now() - t0 });
  return json(200, { ok: true, order: { id: o.id, name: o.name, gid: o.shopify_order_gid, financial_status_db: o.financial_status, financial_status_live: ctx.order.displayFinancialStatus ?? null, cancelled_at: ctx.order.cancelledAt ?? null, paid: isPaid(ctx.order.displayFinancialStatus) },
    db_lines: ctx.lines, live_lines: ctx.live, plan: ctx.plan, edit: begun, note: "preview only — orderEditBegin was " + (begun ? "called and NOT committed (session abandoned)" : "not called"), ms: Date.now() - t0,
    ...(trySet ? { try_set: tried, try_set_note: tried ? "a = editableQuantity - to_remove · b = calc.quantity - to_remove · each in its own orderEditBegin · setQuantity sent with restock true · NOTHING committed" : "try_set requested but preview did not begin (nothing to remove or cancelled)" } : {}) });
}
async function orderDrain(caller: Caller, t0: number): Promise<Response> {
  const rows: OrderQueueRow[] = await sbGet("shop_order_queue?select=id,shop_order_id,kind,attempts,queued_at,payload&done_at=is.null&kind=eq.order_edit&order=queued_at.asc,id.asc&limit=" + ORDER_EDIT_FETCH);
  const stores: Record<string, StoreRow | undefined> = {};
  const out: Array<Record<string, unknown>> = [];
  const summary: Record<string, number> = {};
  let stopped: string | null = null;
  for (const q of rows) {
    stopped = drainStop(Date.now() - t0, ORDER_EDIT_MS);
    if (stopped) break;
    const tq = Date.now();
    await patchOrderQueue(q.id, { started_at: nowIso() });
    const o: { id: string; store_id: string; shopify_order_gid: string; name: string } | undefined = (await sbGet("shop_order?select=id,store_id,shopify_order_gid,name&id=eq." + q.shop_order_id + "&limit=1"))[0];
    let r: EditOut;
    try {
      if (!o) throw new Error("shop_order " + q.shop_order_id + " not found");
      if (!stores[o.store_id]) stores[o.store_id] = (await sbGet("shop_store?select=id,code,shop_domain,secret_prefix,is_active,label,kind&id=eq." + o.store_id + "&limit=1"))[0];
      const store = stores[o.store_id];
      if (!store || !store.is_active) throw new Error("store missing or switched off");
      r = await editShopOrder(store, o);
    } catch (e) {
      r = { status: "error", removed: 0, lines: 0, reason: null, cost: 0, error: String((e as Error)?.message ?? e).slice(0, 400), final: e instanceof NoChangeError };
    }
    const attempts = q.attempts + 1;
    let resultKey: string;
    if (r.status === "error") {
      if (attempts >= ORDER_EDIT_MAX_ATTEMPTS || r.final) {                                     // 5 회 · 또는 다시 시도해도 같은 것(NoChangeError) → 한 번에 닫고 경고
        await patchOrderQueue(q.id, { done_at: nowIso(), result: "error", attempts, error: r.error });
        if (o) await warnOrder(o.id, "order_edit_failed", "IMS could not remove the unshipped quantity from Shopify order " + o.name + (r.final ? "" : " after " + attempts + " tries") + " — " + (r.error ?? "?") + " — edit the order in Shopify by hand or ask IT");
        resultKey = "error";
      } else { await patchOrderQueue(q.id, { started_at: null, attempts, error: r.error }); resultKey = "retry"; }
    } else {
      await patchOrderQueue(q.id, { done_at: nowIso(), result: r.status === "skipped" ? "skipped" : "ok", attempts, error: r.reason });
      resultKey = r.status === "skipped" ? "skipped" : "ok";
    }
    summary[resultKey] = (summary[resultKey] ?? 0) + 1;
    await recordCall({ store_id: o?.store_id ?? null, action: "order_drain", ok: resultKey !== "error", http_status: null, query_cost: r.cost, throttle_available: null,
      error: "queue " + q.id + " " + (o?.name ?? q.shop_order_id.slice(0, 8)) + " → " + resultKey + " · removed " + r.removed + " on " + r.lines + " line(s)" + (r.reason ? " · " + r.reason.slice(0, 160) : "") + (r.error ? " · " + r.error.slice(0, 160) : ""),
      by_staff: caller.staffId, ms: Date.now() - tq });
    out.push({ queue_id: q.id, shop_order_id: q.shop_order_id, name: o?.name ?? null, result: resultKey, attempts, removed: r.removed, lines: r.lines, reason: r.reason, error: r.error, cost: r.cost, ms: Date.now() - tq });
  }
  const open = (await sbGet("shop_order_queue?select=id&done_at=is.null&kind=eq.order_edit&limit=1")).length > 0;
  return json(200, { ok: true, drained: out.length, ...summary, results: out, stopped, more_open: open, ms: Date.now() - t0 });
}

const FUL_SELECT = "shop_fulfillment?select=id,so_id,shop_order_id,store_id,carrier_id,carrier_name,carrier_kind,shopify_company,tracking_numbers,notify_customer,status,attempts,created_at,shopify_fulfillment_gid,fulfillment_order_gid,ready_at,picked_up_at";
// 큐 종류마다 — 어느 머리를 집는가 · 실패하면 머리에 무엇을 적는가 · 5 회 뒤 경고 코드(ful-1b)
const FUL_KIND: Record<FulfillKind, { filter: string; send: (store: StoreRow, f: FulRow) => Promise<FulOut>; warn: string; failPatch: (msg: string, f: FulRow) => Record<string, unknown> }> = {
  ship:         { filter: "&status=in.(pending,error)", send: sendFulfillment, warn: "fulfill_failed", failPatch: (msg, f) => ({ status: "error", attempts: f.attempts + 1, last_error: msg }) },
  picked_up:    { filter: "&carrier_kind=eq.pickup&ready_at=not.is.null&picked_up_at=not.is.null&shopify_fulfillment_gid=is.null", send: sendPickedUp, warn: "pickup_failed", failPatch: (msg, f) => ({ attempts: f.attempts + 1, last_error: msg }) },   // 상태는 sent 그대로(Ready 가 됐다)
  tracking_fix: { filter: "&carrier_kind=eq.carrier&shopify_fulfillment_gid=not.is.null", send: sendTrackingFix, warn: "tracking_fix_failed", failPatch: (msg) => ({ last_error: msg }) },
};
async function fulfillDrain(caller: Caller, t0: number): Promise<Response> {
  const rows: FulQueueRow[] = await sbGet("shop_fulfill_queue?select=id,so_id,kind,attempts,queued_at&done_at=is.null&kind=in.(" + FULFILL_KINDS.join(",") + ")&order=queued_at.asc,id.asc&limit=" + FULFILL_FETCH);
  const stores: Record<string, StoreRow | undefined> = {};
  const out: Array<Record<string, unknown>> = [];
  const summary: Record<string, number> = {};
  let stopped: string | null = null;
  for (const q of rows) {
    stopped = drainStop(Date.now() - t0, FULFILL_DRAIN_MS);
    if (stopped) break;
    const tq = Date.now();
    const kind = (q.kind in FUL_KIND ? q.kind : "ship") as FulfillKind;
    const K = FUL_KIND[kind];
    await patchFulQueue(q.id, { started_at: nowIso() });
    const fuls: FulRow[] = await sbGet(FUL_SELECT + "&so_id=eq." + q.so_id + K.filter + "&order=created_at.asc");
    const results: Array<Record<string, unknown>> = [];
    let cost = 0;
    for (const f of fuls) {
      if (!stores[f.store_id]) stores[f.store_id] = (await sbGet("shop_store?select=id,code,shop_domain,secret_prefix,is_active,label,kind&id=eq." + f.store_id + "&limit=1"))[0];
      const store = stores[f.store_id];
      let r: FulOut;
      try {
        if (!store || !store.is_active) throw new Error("store missing or switched off");
        r = await K.send(store, f);
      } catch (e) {
        const msg = String((e as Error)?.message ?? e).slice(0, 400);
        r = { status: "error", gid: null, fo: null, path: null, cut: 0, warns: [], cost: 0, error: msg };
        await sbWrite("PATCH", "shop_fulfillment?id=eq." + f.id, K.failPatch(msg, f));
      }
      cost += r.cost;
      results.push({ fulfillment_id: f.id, shop_order_id: f.shop_order_id, kind: f.carrier_kind, status: r.status, gid: r.gid, fo: r.fo, path: r.path, cut: r.cut, warns: r.warns, error: r.error });
    }
    // 큐 셈 — ship 은 그 SO 의 머리 상태 전부(pending · error 가 남으면 다시) · picked_up · tracking_fix 는 이번 결과(집은 머리가 0 이면 할 일 없음 = ok)
    const statuses: string[] = kind === "ship" ? ((await sbGet("shop_fulfillment?select=status&so_id=eq." + q.so_id)) as Array<{ status: string }>).map((x) => x.status) : results.map((x) => String(x.status));
    const oc = queueOutcome(statuses, q.attempts);
    const firstErr = results.find((x) => x.error)?.error as string | undefined;
    if (oc.done) await patchFulQueue(q.id, { done_at: nowIso(), result: oc.result, attempts: oc.attempts, error: oc.result === "ok" ? (fuls.length ? null : "nothing to send for " + kind) : (firstErr ?? "fulfillment(s) still not sent") });
    else await patchFulQueue(q.id, { started_at: null, attempts: oc.attempts, error: firstErr ?? "fulfillment(s) still not sent" });
    if (oc.warn) for (const so of new Set(fuls.filter((f) => results.find((x) => x.fulfillment_id === f.id && x.status === "error")).map((f) => f.shop_order_id))) {
      await warnOrder(so, K.warn, "IMS could not " + (kind === "ship" ? "send the shipment to" : kind === "picked_up" ? "mark the pickup as picked up in" : "update the tracking in") + " Shopify after " + oc.attempts + " tries — last error: " + (firstErr ?? "?") + " — do it in Shopify by hand or ask IT");
    }
    const resultKey = oc.done ? (oc.result as string) : "retry";
    summary[resultKey] = (summary[resultKey] ?? 0) + 1;
    await recordCall({ store_id: fuls[0]?.store_id ?? null, action: "fulfill_drain", ok: resultKey !== "error", http_status: null, query_cost: cost, throttle_available: null,
      error: "queue " + q.id + " " + kind + " so " + q.so_id.slice(0, 8) + " → " + resultKey + " · " + results.map((x) => x.status + (x.path ? "/" + x.path : "") + (x.gid ? " " + String(x.gid).split("/").pop() : "") + (x.warns && (x.warns as string[]).length ? " ⚠" + (x.warns as string[]).join(",") : "")).join(" · ") + (firstErr ? " · " + firstErr.slice(0, 160) : ""),
      by_staff: caller.staffId, ms: Date.now() - tq });
    out.push({ queue_id: q.id, so_id: q.so_id, kind, result: resultKey, attempts: oc.attempts, fulfillments: results, cost, ms: Date.now() - tq });
  }
  const open = (await sbGet("shop_fulfill_queue?select=id&done_at=is.null&limit=1")).length > 0;
  return json(200, { ok: true, drained: out.length, ...summary, results: out, stopped, more_open: open, ms: Date.now() - t0 });
}

Deno.serve(async (req) => {
  const t0 = Date.now();
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") return json(405, { ok: false, error: "POST only" });
    let dbRole: string | null = null;
    try { dbRole = String((await sbGet("inv_config?select=value&key=eq.db_role"))[0]?.value ?? ""); } catch { dbRole = null; }
    if (dbRole !== "test") return json(500, { ok: false, error: "inv_config.db_role is " + String(dbRole ?? "missing") + " - this function runs on the test project only (Asung-IMS) - refusing" });
    if (webhookHead(req.headers)) return await webhook(req, t0);                                     // ord-1b: 문 셋째 — Shopify 웹훅(HMAC) · Bearer · cron 열쇠 앞에서
    const caller = await gate(req);
    if (caller instanceof Response) return caller;
    const body = await req.json().catch(() => ({}));
    const action = String(body?.action ?? "");
    if (!ACTIONS.includes(action)) return json(400, { ok: false, error: "action must be one of: " + ACTIONS.join(", ") });
    if (["push", "clean_check", "stock_push", "order_read", "webhooks_subscribe", "webhooks_list", "order_edit_preview"].includes(action) && caller.kind !== "staff") return json(403, { ok: false, error: action + " is a staff action (sign in) — cron may only ping, drain, stock_drain, orders_poll, orders_drain, fulfill_drain and order_drain" });

    if (action === "clean_check") {                                                                 // 규칙 거르기 샘플 + DB 판별(안전장치) 결과
      const hosts = await loadHosts();
      const sample = String(body?.html ?? '<p style="color:red"><b>Hi</b></p><iframe src="https://www.youtube.com/embed/a"></iframe><iframe src="https://www.powr.io/chat/u/x#platform=bigcommerce"></iframe><script>x()</script><a href="javascript:void(0)" onclick="y()">a</a><img src="https://i.ibb.co/a.jpg"><object data="x"></object>');
      const r = cleanHtml(sample, hosts);
      const codes = (await sbRpc("ims_html_forbidden", { p_html: r.html })) as string[];
      return json(200, { ok: true, engine: r.engine, hosts: [...hosts], removed: r.removed, forbidden_after_clean: codes, html: r.html, ms: Date.now() - t0 });
    }

    if (action === "drain") {                                                                       // 열린 큐 · 오래된 것부터 · 실패해도 다음 건 · 한도가 적으면 멈춤 · ⭐ 판정 424 ②: skipped_same_hash 는 20 칸에 안 센다 · 시간 한도
      const rows = await sbGet("shop_push_queue?select=id,store_id,family_id,product_id,reason&done_at=is.null&order=queued_at.asc,id.asc&limit=" + DRAIN_FETCH);
      const hosts = rows.length ? await loadHosts() : new Set<string>();
      const stores: Record<string, StoreRow> = {};
      const out: Array<{ id: number; result: string; error: string | null; product_gid: string | null }> = [];
      let stopped: string | null = null;
      let sent = 0;                                                                                  // 칸에 센 건(ok · error) · skipped_same_hash 는 안 센다
      for (const q of rows) {
        stopped = drainShouldStop(sent, DRAIN_MAX, Date.now() - t0, DRAIN_TIME_MS);
        if (stopped) break;
        if (!stores[q.store_id]) stores[q.store_id] = (await sbGet("shop_store?select=id,code,shop_domain,secret_prefix,is_active,label,kind&id=eq." + q.store_id + "&limit=1"))[0];
        const store = stores[q.store_id];
        await sbWrite("PATCH", "shop_push_queue?id=eq." + q.id, { started_at: new Date().toISOString() });
        let r: PushResult;
        if (!store || !store.is_active) r = { ok: false, result: "error", error: "store missing or switched off", product_gid: null, handle: null, status: null, variants: 0, media: 0, media_matched_before: 0, media_reused_ids: 0, media_removed_unknown: 0, media_matched: 0, media_rereads: 0, clean: null, hash: null, cost: null, query_cost_total: 0, ms: 0, blocks: [] };
        else r = await pushOne(store, { family_id: q.family_id, product_id: q.product_id }, caller, false, hosts, "drain");
        await sbWrite("PATCH", "shop_push_queue?id=eq." + q.id, { done_at: new Date().toISOString(), result: r.result, error: r.error });
        out.push({ id: q.id, result: r.result, error: r.error, product_gid: r.product_gid });
        if (countsToward(r.result)) sent++;
        const avail = (r.cost as { available?: number | null } | null)?.available;
        if (typeof avail === "number" && avail < DRAIN_MIN_AVAILABLE) { stopped = "throttle budget low (" + avail + ")"; break; }
      }
      const open = (await sbGet("shop_push_queue?select=id&done_at=is.null&limit=1")).length > 0;
      return json(200, { ok: true, drained: out.length, sent, skipped: out.length - sent, results: out, stopped, more_open: open, ms: Date.now() - t0 });
    }

    if (action === "stock_drain") return await stockDrain(caller, t0);
    if (action === "orders_drain") return await ordersDrain(caller, t0);
    if (action === "orders_poll") return await ordersPoll(caller, t0);
    if (action === "fulfill_drain") return await fulfillDrain(caller, t0);                       // ful-2
    if (action === "order_drain") return await orderDrain(caller, t0);                           // ful-4b
    if (action === "order_edit_preview") return await orderEditPreview(String(body.order ?? ""), body.try_set === true, caller, t0);   // ful-4b: begin 까지만 · commit 없음 · 원문 보기 · ful-4b2 try_set: 후보 ⓐ · ⓑ setQuantity 까지(commit 없음)

    // ping · push — 스토어 필요
    const code = String(body?.store ?? "").trim().toLowerCase();
    if (!/^[a-z0-9_]{1,20}$/.test(code)) return json(400, { ok: false, error: "store must be a store code (e.g. test)" });
    const rows: StoreRow[] = await sbGet("shop_store?select=id,code,shop_domain,secret_prefix,is_active,label,kind&code=eq." + code + "&limit=1");
    const store = rows[0];
    if (!store) {
      await recordCall({ store_id: null, action, ok: false, http_status: null, query_cost: null, throttle_available: null, error: "store not found: " + code, by_staff: caller.staffId, ms: Date.now() - t0 });
      return json(404, { ok: false, error: `Store "${code}" is not set up — add it under Settings → Shopify Stores` });
    }
    if (!store.is_active) return json(409, { ok: false, error: `Store "${code}" (${store.label ?? store.shop_domain}) is switched off — turn it on under Settings → Shopify Stores first` });
    if (action === "ping") return await ping(store, caller, t0);
    if (action === "order_read") return await orderRead(store, String(body?.order ?? ""), caller, t0);
    if (action === "webhooks_list") return await webhooksList(store, caller, t0);
    if (action === "webhooks_subscribe") return await webhooksSubscribe(store, caller, t0);

    // push · stock_push {store, family_sku | sku, force?} — 켜진 listing 만 · 큐를 거치지 않고 바로
    const fsku = String(body?.family_sku ?? "").trim(), psku = String(body?.sku ?? "").trim();
    if ((fsku === "") === (psku === "")) return json(400, { ok: false, error: "give exactly one of family_sku, sku" });
    const l = (await sbGet("shop_listing_list?select=family_id,product_id,is_on,sku,kind&store_id=eq." + store.id + "&sku=eq." + encodeURIComponent(fsku || psku) + "&kind=eq." + (fsku ? "family" : "product") + "&limit=1"))[0];
    if (!l) return json(404, { ok: false, error: `${fsku || psku} is not listed on store ${code} — switch it on first (Send to Shopify)` });
    if (!l.is_on) return json(409, { ok: false, error: `${fsku || psku} is switched off on store ${code} — it stays ARCHIVED until switched on` });
    if (action === "stock_push") return await stockPush(store, { family_id: l.family_id, product_id: l.product_id }, fsku || psku, caller, t0);
    const hosts = await loadHosts();
    const r = await pushOne(store, { family_id: l.family_id, product_id: l.product_id }, caller, !!body?.force, hosts, "push");
    return json(r.ok ? 200 : (r.error?.startsWith(FORBIDDEN_AFTER_CLEAN) ? 422 : 502), { ...r, store: code, target: fsku || psku, api_version: API_VERSION });
  } catch (e) {
    return json(500, { ok: false, error: String((e as Error)?.message ?? e).slice(0, 400) });
  }
});
