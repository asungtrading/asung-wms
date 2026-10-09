// ============================================================
// ASUNG IMS — Edge Function: shopify (shop-1b ping · shop-2b push · drain · clean_check · 2026-10-09 · 판정 362 · 403 ~ 411)
//   ⚠️ 테스트 프로젝트(Asung-IMS · fazgmyvzzhqybtvtktyg) 전용 — 시작 때 inv_config.db_role = 'test' 가 아니면 멈춘다.
//   POST JSON {action, store, …} · 응답은 json(status) · CORS.
//   문(action 마다 · verify_jwt=false 라 함수 안에서):
//     직원 길  Authorization: Bearer <세션 JWT> → rpc/ims_can_write('shopify')(ims-staff-create 모양 · 401 세션 · 403 권한) → /auth/v1/user 로 by_staff
//     cron 길  x-ims-cron-key == secret IMS_CRON_SECRET(미설정 500 fail-closed) · by_staff null
//     ping      직원 · cron / push · clean_check 직원만 / drain cron 만(직원도 허락 — 손으로 비울 때)
//   표 읽기 · 대응 표 갱신 · 큐 · call_log 는 service_role(세 표는 authenticated 직접 쓰기가 닫혀 있다) · payload 는 rpc/shop_product_payload(2a1) · 거르기는 ../_shared/shopify-clean.ts(규칙 기반 · 판정 412) · 조립은 ../_shared/shopify-product.ts
//   ⭐ 사진 짝(fix2 · 실물 media_matched 0): 보내기 직전 product.media 를 읽어 READY + url 인 사진만 줄기(= product_image id)로 shop_media 에 짝 → 그 사진은 {id} 로 · 처리 중은 URL + REPLACE(쌓이지 않음) · 줄기가 IMS 에 없는 사진은 지워진다(판정 409 · media_removed_unknown) · 직원 push 는 응답이 처리 중이면 2 초 × 2 회 다시 읽는다 · hash 가 같으면 직전 읽기도 안 한다
//   ⭐ 안전장치(판정 412): 거른 html 을 rpc/ims_html_forbidden 에 넣어 하나라도 걸리면 productSet 을 부르지 않는다(result error · description_forbidden_after_clean:<코드> · 직원 길 push 는 422 · drain 은 다음 건 계속) — IMS 에서 그 설명을 한 번 고쳐 저장하면 풀린다
//   호출 한 번 = shop_call_log 한 줄(drain 은 건마다) · 90 일 지난 줄은 호출 끝에 지운다.
//   배포: supabase functions deploy shopify --project-ref fazgmyvzzhqybtvtktyg (config.toml [functions.shopify] verify_jwt=false)
// ============================================================
import { API_VERSION, compareLocations, getToken, missingScopes, shopifyGql, type PairRow, type ShopLocation, type StoreRow, type Warning } from "../_shared/shopify.ts";
import { cleanHtml, forbiddenAfterClean, FORBIDDEN_AFTER_CLEAN } from "../_shared/shopify-clean.ts";
import { assertNoForbiddenKeys, buildProductSetInput, mapResponse, matchMedia, mediaNodes, PRODUCT_MEDIA_QUERY, PRODUCT_SET_MUTATION, unknownMedia, userErrorsSentence, type MediaNode, type Payload, type RespProduct } from "../_shared/shopify-product.ts";
import { sleep } from "../_shared/shopify.ts";

const CALL_LOG_KEEP_DAYS = 90;
const DRAIN_MAX = 20;
const DRAIN_MIN_AVAILABLE = 500;
const MEDIA_REREAD_MAX = 2;                                                                        // 직원 push 만 · 응답 사진이 처리 중이면 2 초 뒤 다시 읽기(최대 2 회) · drain 은 안 한다(회차 시간 · 다음 push 의 직전 읽기가 잡는다)
const MEDIA_REREAD_WAIT_MS = 2000;                                                                   // 한도 남은 점수가 이 아래면 이번 회차를 멈춘다(다음 분에 이어서)
const CORS: HeadersInit = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-ims-cron-key", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const ACTIONS = ["ping", "push", "drain", "clean_check"];

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

Deno.serve(async (req) => {
  const t0 = Date.now();
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") return json(405, { ok: false, error: "POST only" });
    let dbRole: string | null = null;
    try { dbRole = String((await sbGet("inv_config?select=value&key=eq.db_role"))[0]?.value ?? ""); } catch { dbRole = null; }
    if (dbRole !== "test") return json(500, { ok: false, error: "inv_config.db_role is " + String(dbRole ?? "missing") + " - this function runs on the test project only (Asung-IMS) - refusing" });
    const caller = await gate(req);
    if (caller instanceof Response) return caller;
    const body = await req.json().catch(() => ({}));
    const action = String(body?.action ?? "");
    if (!ACTIONS.includes(action)) return json(400, { ok: false, error: "action must be one of: " + ACTIONS.join(", ") });
    if ((action === "push" || action === "clean_check") && caller.kind !== "staff") return json(403, { ok: false, error: action + " is a staff action (sign in) — cron may only ping and drain" });

    if (action === "clean_check") {                                                                 // 규칙 거르기 샘플 + DB 판별(안전장치) 결과
      const hosts = await loadHosts();
      const sample = String(body?.html ?? '<p style="color:red"><b>Hi</b></p><iframe src="https://www.youtube.com/embed/a"></iframe><iframe src="https://www.powr.io/chat/u/x#platform=bigcommerce"></iframe><script>x()</script><a href="javascript:void(0)" onclick="y()">a</a><img src="https://i.ibb.co/a.jpg"><object data="x"></object>');
      const r = cleanHtml(sample, hosts);
      const codes = (await sbRpc("ims_html_forbidden", { p_html: r.html })) as string[];
      return json(200, { ok: true, engine: r.engine, hosts: [...hosts], removed: r.removed, forbidden_after_clean: codes, html: r.html, ms: Date.now() - t0 });
    }

    if (action === "drain") {                                                                       // 열린 큐 ≤ 20 건 · 오래된 것부터 · 실패해도 다음 건 · 한도가 적으면 멈춤
      const rows = await sbGet("shop_push_queue?select=id,store_id,family_id,product_id,reason&done_at=is.null&order=queued_at.asc,id.asc&limit=" + DRAIN_MAX);
      const hosts = rows.length ? await loadHosts() : new Set<string>();
      const stores: Record<string, StoreRow> = {};
      const out: Array<{ id: number; result: string; error: string | null; product_gid: string | null }> = [];
      let stopped: string | null = null;
      for (const q of rows) {
        if (!stores[q.store_id]) stores[q.store_id] = (await sbGet("shop_store?select=id,code,shop_domain,secret_prefix,is_active,label,kind&id=eq." + q.store_id + "&limit=1"))[0];
        const store = stores[q.store_id];
        await sbWrite("PATCH", "shop_push_queue?id=eq." + q.id, { started_at: new Date().toISOString() });
        let r: PushResult;
        if (!store || !store.is_active) r = { ok: false, result: "error", error: "store missing or switched off", product_gid: null, handle: null, status: null, variants: 0, media: 0, media_matched_before: 0, media_reused_ids: 0, media_removed_unknown: 0, media_matched: 0, media_rereads: 0, clean: null, hash: null, cost: null, query_cost_total: 0, ms: 0, blocks: [] };
        else r = await pushOne(store, { family_id: q.family_id, product_id: q.product_id }, caller, false, hosts, "drain");
        await sbWrite("PATCH", "shop_push_queue?id=eq." + q.id, { done_at: new Date().toISOString(), result: r.result, error: r.error });
        out.push({ id: q.id, result: r.result, error: r.error, product_gid: r.product_gid });
        const avail = (r.cost as { available?: number | null } | null)?.available;
        if (typeof avail === "number" && avail < DRAIN_MIN_AVAILABLE) { stopped = "throttle budget low (" + avail + ")"; break; }
      }
      const open = (await sbGet("shop_push_queue?select=id&done_at=is.null&limit=1")).length > 0;
      return json(200, { ok: true, drained: out.length, results: out, stopped, more_open: open, ms: Date.now() - t0 });
    }

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

    // push {store, family_sku | sku, force?} — 켜진 listing 만 · 큐를 거치지 않고 바로
    const fsku = String(body?.family_sku ?? "").trim(), psku = String(body?.sku ?? "").trim();
    if ((fsku === "") === (psku === "")) return json(400, { ok: false, error: "give exactly one of family_sku, sku" });
    const l = (await sbGet("shop_listing_list?select=family_id,product_id,is_on,sku,kind&store_id=eq." + store.id + "&sku=eq." + encodeURIComponent(fsku || psku) + "&kind=eq." + (fsku ? "family" : "product") + "&limit=1"))[0];
    if (!l) return json(404, { ok: false, error: `${fsku || psku} is not listed on store ${code} — switch it on first (Send to Shopify)` });
    if (!l.is_on) return json(409, { ok: false, error: `${fsku || psku} is switched off on store ${code} — it stays ARCHIVED until switched on` });
    const hosts = await loadHosts();
    const r = await pushOne(store, { family_id: l.family_id, product_id: l.product_id }, caller, !!body?.force, hosts, "push");
    return json(r.ok ? 200 : (r.error?.startsWith(FORBIDDEN_AFTER_CLEAN) ? 422 : 502), { ...r, store: code, target: fsku || psku, api_version: API_VERSION });
  } catch (e) {
    return json(500, { ok: false, error: String((e as Error)?.message ?? e).slice(0, 400) });
  }
});
