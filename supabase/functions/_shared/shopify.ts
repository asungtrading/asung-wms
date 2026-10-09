// ============================================================
// ASUNG IMS — 공용 Shopify 헬퍼 (_shared · shop-1b · 2026-10-09 · 판정 362 · shop-0 ⬜3 · ⬜5 · 이견 7)
//   토큰(client credentials · 24h · 인스턴스 메모리 캐시 · DB 에 두지 않는다) · GraphQL 한 곳(API 판 상수 하나 · 한도 재시도) · scope 대조 · 위치 대조(순수 · deno test)
//   ⚠️ 이 파일을 바꾸면 import 하는 함수를 모두 재배포한다 — 지금은 shopify 하나:
//      supabase functions deploy shopify --project-ref fazgmyvzzhqybtvtktyg
//   ⚠️ 비밀 이름 = <secret_prefix>_CLIENT_ID · <secret_prefix>_CLIENT_SECRET(shop_store.secret_prefix · 기본 SHOPIFY_IMS) · 값은 supabase secrets set 으로만
//   📌 Shopify 문서(2026-10-09 · MCP search_docs): 토큰 POST {shop}/admin/oauth/access_token {client_id, client_secret, grant_type: client_credentials} → {access_token, scope, expires_in: 86399}
//      · 「다시 받으려면 같은 요청을 다시」 · GraphQL 은 200 으로도 errors[] 를 준다(extensions.code · extensions.cost.throttleStatus{maximumAvailable, currentlyAvailable, restoreRate})
//      · ⚠️ 한도 초과 응답의 code 글자 'THROTTLED' 와 HTTP 429 는 문서 검색에서 못 봤다(짐작) — 둘 다 받아 주고, 실제로 만나면 원문을 shop_call_log.error 에 남긴다(index.ts)
// ============================================================

export const API_VERSION = "2026-10";                                    // 판 올리기는 여기 하나(분기마다)
export const TOKEN_REFRESH_BEFORE_MS = 3_600_000;                        // 남은 시간 1 시간 아래면 다시 받는다
export const THROTTLE_MAX_RETRY = 3;
export const THROTTLE_WAIT_CAP_MS = 10_000;
export const REQUIRED_SCOPES = [                                          // 앱 Asung IMS 버전 v1scopes 의 10 개(shop-0 B)
  "read_products", "write_products", "read_inventory", "write_inventory", "read_locations",
  "read_orders", "write_orders", "read_merchant_managed_fulfillment_orders", "write_merchant_managed_fulfillment_orders", "read_customers",
];

export type StoreRow = { id: string; code: string; shop_domain: string; secret_prefix: string; is_active: boolean; label?: string; kind?: string };
export type ShopLocation = { id: string; name: string; isActive: boolean };
export type PairRow = { id: string; shopify_location_gid: string; shopify_name: string | null; warehouse_id: string; warehouse_name?: string | null; is_active: boolean };
export type Warning = { code: string; gid?: string; name?: string; detail?: string };
export type Token = { token: string; scope: string; expiresAt: number };
export type GqlResult = {
  ok: boolean; status: number; data: unknown; errors: Array<{ message?: string; extensions?: Record<string, unknown> }> | null;
  cost: { requested: number | null; actual: number | null; available: number | null; restoreRate: number | null };
  attempts: number; tokenRefreshed: boolean; raw: string | null;
};

// ── 순수 함수(deno test) ──────────────────────────────────────────────────────────
export const secretNames = (prefix: string) => ({ id: prefix + "_CLIENT_ID", secret: prefix + "_CLIENT_SECRET" });

// scope 대조 — 토큰 응답은 write_X 가 있으면 read_X 를 생략한다(실측 6 개) ⇒ read_X 는 write_X 가 있으면 있는 것으로 친다
export function missingScopes(granted: string, required: string[] = REQUIRED_SCOPES): string[] {
  const have = new Set(granted.split(",").map((s) => s.trim()).filter(Boolean));
  const has = (s: string) => have.has(s) || (s.startsWith("read_") && have.has("write_" + s.slice(5)));
  return required.filter((s) => !has(s));
}

// 위치 대조 — GID 로만(이름이 바뀌는 것은 경고가 아니다 · shop-0 이견 6)
//   location_unmapped: Shopify 에 있는데 켜진 짝이 없다(비활성 위치도 알린다 — 이름에 (inactive))
//   location_missing : 켜진 짝의 GID 가 Shopify 에 없거나 Shopify 에서 꺼졌다
//   updates          : 켜진 짝 중 Shopify 에 있는 것 — shopify_name 을 그 이름으로(checked_at 은 index.ts 가 now)
export function compareLocations(shopLocs: ShopLocation[], pairs: PairRow[]): { warnings: Warning[]; updates: Array<{ id: string; gid: string; name: string }> } {
  const warnings: Warning[] = [];
  const updates: Array<{ id: string; gid: string; name: string }> = [];
  const activePairs = pairs.filter((p) => p.is_active);
  const byGid = new Map(activePairs.map((p) => [p.shopify_location_gid, p]));
  for (const l of shopLocs) {
    if (!byGid.has(l.id)) warnings.push({ code: "location_unmapped", gid: l.id, name: l.name + (l.isActive ? "" : " (inactive)") });
  }
  const shopById = new Map(shopLocs.map((l) => [l.id, l]));
  for (const p of activePairs) {
    const l = shopById.get(p.shopify_location_gid);
    if (!l) warnings.push({ code: "location_missing", gid: p.shopify_location_gid, name: p.warehouse_name ?? p.warehouse_id, detail: "not in Shopify" });
    else if (!l.isActive) { warnings.push({ code: "location_missing", gid: p.shopify_location_gid, name: l.name, detail: "inactive in Shopify" }); updates.push({ id: p.id, gid: l.id, name: l.name }); }
    else updates.push({ id: p.id, gid: l.id, name: l.name });
  }
  return { warnings, updates };
}

// 한도 — 429 또는 errors[].extensions.code === 'THROTTLED'(짐작) · 기다림 = (요청 비용 − 남은 점수) / 회복률 · 없으면 1 s × 2^회차 · 상한 10 s
export function isThrottled(status: number, body: { errors?: Array<{ extensions?: Record<string, unknown> }> | null } | null): boolean {
  if (status === 429) return true;
  return !!body?.errors?.some((e) => String(e?.extensions?.code ?? "").toUpperCase() === "THROTTLED");
}
export function throttleWaitMs(ext: Record<string, unknown> | null | undefined, attempt: number): number {
  const cost = (ext?.cost ?? null) as { requestedQueryCost?: number; throttleStatus?: { currentlyAvailable?: number; restoreRate?: number } } | null;
  const need = Number(cost?.requestedQueryCost ?? NaN) - Number(cost?.throttleStatus?.currentlyAvailable ?? NaN);
  const rate = Number(cost?.throttleStatus?.restoreRate ?? NaN);
  let ms: number;
  if (Number.isFinite(need) && Number.isFinite(rate) && rate > 0) ms = Math.ceil(Math.max(need, 0) / rate) * 1000 + 250;
  else ms = 1000 * Math.pow(2, Math.max(attempt, 0));
  return Math.min(Math.max(ms, 250), THROTTLE_WAIT_CAP_MS);
}
export function costOf(ext: Record<string, unknown> | null | undefined): GqlResult["cost"] {
  const c = (ext?.cost ?? null) as { requestedQueryCost?: number; actualQueryCost?: number; throttleStatus?: { currentlyAvailable?: number; restoreRate?: number } } | null;
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? Math.round(v) : null);
  return { requested: n(c?.requestedQueryCost), actual: n(c?.actualQueryCost), available: n(c?.throttleStatus?.currentlyAvailable), restoreRate: n(c?.throttleStatus?.restoreRate) };
}
// 토큰 끝점 오류를 사람 말로
export function tokenErrorSentence(status: number, body: unknown, store: StoreRow): string {
  const e = (body ?? {}) as { error?: string; error_description?: string };
  if (e.error === "shop_not_permitted") return `Shopify refused the app for ${store.shop_domain} (shop_not_permitted) — the app and the store belong to different organizations; create the app in that store's organization and point this store at that key prefix`;
  if (e.error === "invalid_client") return `Shopify did not accept the app key for ${store.shop_domain} (invalid_client) — check the ${store.secret_prefix}_CLIENT_ID / _CLIENT_SECRET secrets`;
  return `Shopify token request for ${store.shop_domain} failed (HTTP ${status}${e.error ? " · " + e.error : ""}${e.error_description ? " · " + e.error_description : ""})`;
}
export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ── 토큰 캐시(인스턴스 메모리 · 스토어별) ───────────────────────────────────────────
const tokens = new Map<string, Token>();
export function cachedToken(store: StoreRow, now = Date.now()): Token | null {
  const t = tokens.get(store.shop_domain);
  return t && t.expiresAt - now > TOKEN_REFRESH_BEFORE_MS ? t : null;
}
export function forgetToken(store: StoreRow): void { tokens.delete(store.shop_domain); }
export async function getToken(store: StoreRow, force = false): Promise<Token> {
  if (!force) { const c = cachedToken(store); if (c) return c; }
  const names = secretNames(store.secret_prefix);
  const id = Deno.env.get(names.id) ?? "", secret = Deno.env.get(names.secret) ?? "";
  if (!id || !secret) throw new Error(`Secrets ${names.id} / ${names.secret} are not set on this project — supabase secrets set … --project-ref <ref>`);
  const r = await fetch(`https://${store.shop_domain}/admin/oauth/access_token`, {
    method: "POST", headers: { "Content-Type": "application/json", "Accept": "application/json" },
    body: JSON.stringify({ client_id: id, client_secret: secret, grant_type: "client_credentials" }),
  });
  const text = await r.text();
  let j: { access_token?: string; scope?: string; expires_in?: number } = {};
  try { j = JSON.parse(text); } catch { /* 아래 문장 */ }
  if (!r.ok || !j.access_token) throw new Error(tokenErrorSentence(r.status, j, store) + (text && !j.access_token ? " · " + text.slice(0, 200) : ""));
  const t: Token = { token: j.access_token, scope: String(j.scope ?? ""), expiresAt: Date.now() + Number(j.expires_in ?? 86399) * 1000 };
  tokens.set(store.shop_domain, t);
  return t;
}

// ── GraphQL 한 곳 — 401/403 이면 토큰을 한 번 새로 받아 재시도 · 한도면 기다렸다 재시도(최대 3) · errors · userErrors 는 그대로 돌려준다 ──
export async function shopifyGql(store: StoreRow, query: string, variables: Record<string, unknown> = {}): Promise<GqlResult> {
  let tokenRefreshed = false, attempts = 0, throttled = 0;
  let tok = await getToken(store);
  for (;;) {
    attempts++;
    const r = await fetch(`https://${store.shop_domain}/admin/api/${API_VERSION}/graphql.json`, {
      method: "POST", headers: { "Content-Type": "application/json", "Accept": "application/json", "X-Shopify-Access-Token": tok.token },
      body: JSON.stringify({ query, variables }),
    });
    const text = await r.text();
    let body: { data?: unknown; errors?: GqlResult["errors"]; extensions?: Record<string, unknown> } | null = null;
    try { body = JSON.parse(text); } catch { body = null; }
    if ((r.status === 401 || r.status === 403) && !tokenRefreshed) {                       // 토큰이 죽었다 — 한 번만 새로
      tokenRefreshed = true; forgetToken(store); tok = await getToken(store, true); continue;
    }
    if (isThrottled(r.status, body) && throttled < THROTTLE_MAX_RETRY) {
      throttled++; await sleep(throttleWaitMs(body?.extensions, throttled)); continue;
    }
    const errors = (body?.errors && body.errors.length ? body.errors : null) as GqlResult["errors"];
    return { ok: r.ok && !errors, status: r.status, data: body?.data ?? null, errors, cost: costOf(body?.extensions), attempts, tokenRefreshed, raw: r.ok && !errors ? null : text.slice(0, 400) };
  }
}
