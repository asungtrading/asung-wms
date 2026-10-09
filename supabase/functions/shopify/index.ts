// ============================================================
// ASUNG IMS — Edge Function: shopify (shop-1b · 2026-10-09 · 판정 362 · 403 · shop-0 ⬜4 · ⬜6 · ⬜7)
//   ⚠️ 테스트 프로젝트(Asung-IMS · fazgmyvzzhqybtvtktyg) 전용 — 시작 때 inv_config.db_role = 'test' 가 아니면 멈춘다(ims-product-images 와 같은 뜻).
//   POST JSON {action, store, …} · action 은 ping 하나(②③④⑤ 가 더한다) · 응답은 json(status) · CORS.
//   문(action 마다 · verify_jwt=false 라 함수 안에서):
//     직원 길  Authorization: Bearer <세션 JWT> → caller JWT 로 rpc/ims_can_write('shopify')(ims-staff-create 모양 · 401 세션 · 403 권한) → /auth/v1/user 로 by_staff(ims_staff.id)
//     cron 길  x-ims-cron-key == secret IMS_CRON_SECRET(미설정이면 500 fail-closed) · by_staff null — ping 은 두 길 다 허락(건강 점검)
//   표 읽기 · shop_location 갱신 · shop_call_log 쓰기는 service_role(ims-product-images 선례) — 세 표는 authenticated 직접 쓰기가 닫혀 있다(shop-1a).
//   호출 한 번 = shop_call_log 한 줄(성공 · 실패 모두 · error 는 앞 400 자 · 한도 원문도 여기) · 90 일 지난 줄은 호출 끝에 지운다.
//   Shopify 부르기 · 토큰 · 대조 판단은 ../_shared/shopify.ts(순수 함수는 deno test) — 이 파일은 문 · 받아 오고 · 쓰고 · 기록한다.
//   배포: supabase functions deploy shopify --project-ref fazgmyvzzhqybtvtktyg (config.toml [functions.shopify] verify_jwt=false)
// ============================================================
import { API_VERSION, compareLocations, getToken, missingScopes, shopifyGql, type PairRow, type ShopLocation, type StoreRow, type Warning } from "../_shared/shopify.ts";

const CALL_LOG_KEEP_DAYS = 90;
const CORS: HeadersInit = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-ims-cron-key", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const ACTIONS = ["ping"];

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
type LogRow = { store_id: string | null; action: string; ok: boolean; http_status: number | null; query_cost: number | null; throttle_available: number | null; error: string | null; by_staff: string | null; ms: number };
async function recordCall(row: LogRow): Promise<void> {
  try {
    await sbWrite("POST", "shop_call_log", { ...row, error: row.error ? row.error.slice(0, 400) : null });
    try { await sbWrite("DELETE", "shop_call_log?called_at=lt." + encodeURIComponent(new Date(Date.now() - CALL_LOG_KEEP_DAYS * 86_400_000).toISOString())); } catch (e) { console.warn("call_log purge failed:", String(e).slice(0, 200)); }
  } catch (e) { console.warn("recordCall failed:", String(e).slice(0, 300)); }
}

// ── 문 — cron 길(x-ims-cron-key) 또는 직원 길(Bearer JWT → ims_can_write('shopify')) ──
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
  let staffId: string | null = null;                                                               // by_staff — 누가 눌렀나(실패해도 막지 않는다)
  try {
    const u = await fetch(SB_URL() + "/auth/v1/user", { headers: { apikey: ANON(), Authorization: "Bearer " + jwt } });
    const uid = u.ok ? String((await u.json())?.id ?? "") : "";
    if (uid) staffId = (await sbGet("ims_staff?select=id&auth_user_id=eq." + uid + "&limit=1"))[0]?.id ?? null;
  } catch (e) { console.warn("by_staff lookup failed:", String(e).slice(0, 200)); }
  return { kind: "staff", staffId };
}

// ── ping — 토큰(scope 대조) → shop · locations → 짝 대조(GID) → shopify_name · checked_at → 기록 → 응답 ──
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
  for (const u of cmp.updates) {                                                                   // 짝 행의 표시 칸만(service_role · 표는 직접 쓰기 닫힘) · 실패는 경고로
    try { await sbWrite("PATCH", "shop_location?id=eq." + u.id, { shopify_name: u.name, checked_at: now }); }
    catch (e) { warnings.push({ code: "pair_update_failed", gid: u.gid, detail: String(e).slice(0, 200) }); }
  }
  await recordCall({ store_id: store.id, action: "ping", ok: true, http_status: g.status, query_cost: g.cost.actual, throttle_available: g.cost.available, error: warnings.length ? "warnings: " + warnings.map((w) => w.code).join(",") : null, by_staff: caller.staffId, ms: Date.now() - t0 });
  return json(200, {
    ok: true, store: store.code, api_version: API_VERSION, caller: caller.kind,
    shop: { name: shop.name ?? null, myshopifyDomain: shop.myshopifyDomain ?? null, currencyCode: shop.currencyCode ?? null },
    locations: locs.map((l) => ({ ...l, paired_warehouse: pairs.find((p) => p.is_active && p.shopify_location_gid === l.id)?.warehouse_id ?? null })),
    pairs: pairs.map((p: any) => ({ gid: p.shopify_location_gid, warehouse: p.ref_warehouse?.name ?? null, is_active: p.is_active })),
    scopes: tok.scope.split(",").filter(Boolean), missing_scopes: missing, warnings,
    cost: g.cost, attempts: g.attempts, ms: Date.now() - t0,
  });
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
    return json(400, { ok: false, error: "unhandled action " + action });
  } catch (e) {
    return json(500, { ok: false, error: String((e as Error)?.message ?? e).slice(0, 400) });
  }
});
