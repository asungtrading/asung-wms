// ============================================================
// ASUNG IMS — _shared/qbo.ts (qbo-1b · 2026-10-29 · 판정 617 · 867 ~ 872 · DB qbo-1a 20261029160000 · 지시서 ~/asung/prompts/qbo-1b.md)
//   QuickBooks Online OAuth 2.0 연결의 순수 함수 + 흐름(handle) — 바깥은 전부 Deps 로 주입(fetch · DB 창구 · 시계 · 난수) → qbo_test.ts 가 Intuit · DB 무접촉으로 돌린다
//   EF qbo/index.ts 는 Deps 의 실물(REST · Deno.env)만 댄다.
//   ⚠️ 토큰 · client secret · code 는 응답 · 기록 · 오류 · console 어디에도 남기지 않는다 — 모든 글은 scrub() 을 지난다(정확 값 치환이 주 · 꼴 치환은 보조)
//   출처(2026-10-29 직접 읽음):
//     · discovery 둘(https://developer.api.intuit.com/.well-known/openid_sandbox_configuration · …/openid_configuration) — authorize · token · revoke 가 양쪽 같다(userinfo 만 다름)
//     · API 기본 주소 · 토큰 끝점 몸(urlencoded · Basic) · revoke 몸(JSON {token} · Basic) · 응답 칸 이름 · intuit_tid 머리 = Intuit 공식 oauth-jsclient 소스
//       (github.com/intuit/oauth-jsclient src/OAuthClient.js · src/access-token/Token.js · src/response/AuthResponse.js)
//     · minorversion 75 = 2025-08-01 부터 1 ~ 74 는 무시되고 75 로 답한다(Intuit 공지 · codat 250219/250401 요약) — 75 를 명시해도 해가 없다
// ============================================================

export type Env = "sandbox" | "production";
export const ENVS: readonly Env[] = ["sandbox", "production"];
export const SCOPE = "com.intuit.quickbooks.accounting";
export const API_BASE: Record<Env, string> = { sandbox: "https://sandbox-quickbooks.api.intuit.com", production: "https://quickbooks.api.intuit.com" };
export const DISCOVERY_URL: Record<Env, string> = { sandbox: "https://developer.api.intuit.com/.well-known/openid_sandbox_configuration", production: "https://developer.api.intuit.com/.well-known/openid_configuration" };
export const MINOR_VERSION = "75";
export const SETTINGS_URL = "https://ims.asung.ca/settings.html?t=qbo";          // 302 가 보내는 곳 — 코드에 하나 고정 · 요청 값으로 만들지 않는다
export const CALLBACK_WHY = ["denied", "state", "exchange", "realm", "save", "env"] as const;
export type CallbackWhy = typeof CALLBACK_WHY[number];
export const DISCOVERY_TTL_MS = 24 * 3600_000;
export const REFRESH_AHEAD_MS = 5 * 60_000;                                       // 접근 토큰이 5 분 안에 끝나면 먼저 갱신
export const LEASE_WAIT_MS = 15_000, LEASE_POLL_MS = 1_500;                       // 임대 못 받으면 1.5 s 씩 최대 15 s 기다렸다 다시 읽기
export const RETRY_DELAY_MS = 1_000;                                              // 네트워크 · 5xx 만 1 회
export const CALL_LOG_KEEP_DAYS = 90;
export const ACCESS_EXPIRES_DEFAULT_S = 3600;                                     // expires_in 이 없을 때만(Intuit 문서값 · 이견 5) — 응답에 있으면 그 값
export const ACTIONS = ["status", "start", "disconnect", "refresh", "ping"] as const;
export const CRON_ACTIONS = ["refresh"] as const;
export const CORS: HeadersInit = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-region", "Access-Control-Allow-Methods": "POST, OPTIONS" };

export class RpcError extends Error { constructor(public status: number, message: string) { super(message); } }
export class QboError extends Error { constructor(public status: number, message: string) { super(message); } }

// ── 순수: 주소 · state · 해시 ──
export const base64url = (bytes: Uint8Array): string => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
export function newStateRaw(bytes: Uint8Array): string {
  if (bytes.length !== 32) throw new Error("state must be 32 random bytes");
  return base64url(bytes);
}
export async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
export function authorizeUrl(endpoint: string, clientId: string, redirectUri: string, state: string): string {
  const u = new URL(endpoint);
  u.search = new URLSearchParams({ client_id: clientId, scope: SCOPE, redirect_uri: redirectUri, response_type: "code", state }).toString();
  return u.toString();
}
export function callbackLocation(why: CallbackWhy | null): string {
  if (why === null) return SETTINGS_URL + "&qbo=connected";
  if (!(CALLBACK_WHY as readonly string[]).includes(why)) throw new Error("unknown callback why");
  return SETTINGS_URL + "&qbo=error&why=" + why;
}
export const redirect302 = (location: string): Response => new Response(null, { status: 302, headers: { Location: location, "Cache-Control": "no-store" } });
export const redirectUriOf = (supabaseUrl: string): string => supabaseUrl.replace(/\/+$/, "") + "/functions/v1/qbo/callback";
export const isCallbackPath = (pathname: string): boolean => /\/callback\/?$/.test(pathname);
export const envOf = (v: string | undefined | null): Env | null => (v === "sandbox" || v === "production" ? v : null);
export const secretNames = (env: Env) => ({ id: "QBO_CLIENT_ID_" + env.toUpperCase(), secret: "QBO_CLIENT_SECRET_" + env.toUpperCase() });
export const basicAuth = (id: string, secret: string): string => "Basic " + btoa(id + ":" + secret);

// ── 순수: discovery(24 h 캐시 · 실패면 캐시 · 캐시도 없으면 500 · 코드에 박은 폴백 없음) ──
export type Discovery = { authorization_endpoint: string; token_endpoint: string; revocation_endpoint: string };
export function parseDiscovery(j: unknown): Discovery | null {
  const o = (j ?? {}) as Record<string, unknown>;
  const pick = (k: string) => (typeof o[k] === "string" && /^https:\/\//.test(o[k] as string) ? (o[k] as string) : null);
  const a = pick("authorization_endpoint"), t = pick("token_endpoint"), r = pick("revocation_endpoint");
  return a && t && r ? { authorization_endpoint: a, token_endpoint: t, revocation_endpoint: r } : null;
}
export type DiscoveryState = { env: Env; cached_at: string; fresh: boolean; stale_served: boolean } | null;
export class DiscoveryCache {
  private c: { env: Env; at: number; d: Discovery } | null = null;
  private staleServed = false;
  constructor(private ttlMs = DISCOVERY_TTL_MS) {}
  async get(env: Env, fetchJson: (url: string) => Promise<unknown>, now: number): Promise<Discovery> {
    if (this.c && this.c.env === env && now - this.c.at < this.ttlMs) return this.c.d;
    try {
      const d = parseDiscovery(await fetchJson(DISCOVERY_URL[env]));
      if (!d) throw new Error("discovery document has no authorization/token/revocation endpoint");
      this.c = { env, at: now, d }; this.staleServed = false;
      return d;
    } catch (e) {
      if (this.c && this.c.env === env) { this.staleServed = true; return this.c.d; }                 // 실패면 캐시(지났어도)
      throw new QboError(500, "Intuit discovery document could not be read and nothing is cached — try again shortly: " + String((e as Error)?.message ?? e).slice(0, 200));
    }
  }
  state(now: number): DiscoveryState { return this.c ? { env: this.c.env, cached_at: new Date(this.c.at).toISOString(), fresh: now - this.c.at < this.ttlMs, stale_served: this.staleServed } : null; }
}

// ── 순수: 토큰 응답 · 오류 글 · 재시도 판정 · intuit_tid · scrub ──
export type Tokens = { access: string; refresh: string; accessExp: Date; refreshExp: Date | null; assumedExpiresIn: boolean };
export function parseTokenResponse(j: unknown, nowMs: number): Tokens {
  const o = (j ?? {}) as Record<string, unknown>;
  const access = typeof o.access_token === "string" ? o.access_token : "", refresh = typeof o.refresh_token === "string" ? o.refresh_token : "";
  if (!access || !refresh) throw new QboError(502, "Intuit token response has no access_token/refresh_token");
  const ein = Number(o.expires_in), rin = Number(o.x_refresh_token_expires_in);                        // 칸 이름 = oauth-jsclient Token.js(setToken) 그대로
  const assumed = !(ein > 0);
  return { access, refresh, accessExp: new Date(nowMs + (assumed ? ACCESS_EXPIRES_DEFAULT_S : ein) * 1000), refreshExp: rin > 0 ? new Date(nowMs + rin * 1000) : null, assumedExpiresIn: assumed };
}
export function intuitErrorText(status: number, body: unknown): string {
  let s = "HTTP " + status;
  const o = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const fault = o.Fault as Record<string, unknown> | undefined;
  if (fault && Array.isArray(fault.Error) && fault.Error.length) {
    const e = fault.Error[0] as Record<string, unknown>;
    s += " " + String(fault.type ?? "Fault") + " code " + String(e.code ?? "?") + ": " + String(e.Message ?? "") + (e.Detail ? " — " + String(e.Detail) : "");
  } else if (typeof o.error === "string") {
    s += " " + o.error + (o.error_description ? ": " + String(o.error_description) : "");
  } else if (typeof body === "string" && body.trim()) {
    s += " " + body.trim();
  }
  return s.slice(0, 400);
}
export const oauthErrorCode = (body: unknown): string | null => { const o = (body && typeof body === "object" ? body : {}) as Record<string, unknown>; return typeof o.error === "string" ? o.error : null; };
export const needsReconnect = (status: number, body: unknown): boolean => status === 400 && oauthErrorCode(body) === "invalid_grant";   // 갱신 토큰 만료 · 취소 · QBO 쪽 끊김 — 그 밖의 4xx(invalid_client 등)는 설정 문제라 표시하지 않는다
export const isRetryable = (status: number, networkError: boolean): boolean => networkError || status >= 500;
export const tidOf = (h: { get(name: string): string | null }): string | null => (h.get("intuit_tid") ?? "").trim() || null;
export const REDACTED = "[redacted]";
export function scrub(text: string, secrets: readonly string[] = []): string {
  let s = String(text ?? "");
  for (const v of secrets) if (v && v.length >= 8) s = s.split(v).join(REDACTED);
  return s
    .replace(/Bearer\s+[A-Za-z0-9\-._~+/]+=*/gi, "Bearer " + REDACTED)
    .replace(/("?(?:access|refresh|id)_token"?\s*[:=]\s*"?)[^"&\s,}]+/gi, "$1" + REDACTED)
    .replace(/("?client_secret"?\s*[:=]\s*"?)[^"&\s,}]+/gi, "$1" + REDACTED)
    .replace(/("?token"?\s*[:=]\s*"?)[^"&\s,}]+/gi, "$1" + REDACTED)
    .replace(/(\bcode=)[^&\s]+/gi, "$1" + REDACTED)
    .replace(/\beyJ[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+/g, REDACTED)                 // JWT 꼴(Intuit 접근 토큰 · 짐작 보강)
    .replace(/\bAB1[0-9][A-Za-z0-9\-_]{20,}/g, REDACTED);                                             // Intuit 갱신 토큰 꼴(AB11…· 짐작 보강 — 정확 값 치환이 주)
}
export const companyNameOf = (body: unknown): string | null => { const n = ((body as Record<string, unknown>)?.CompanyInfo as Record<string, unknown> | undefined)?.CompanyName; return typeof n === "string" && n.trim() ? n.trim() : null; };

// ── Deps — 바깥은 전부 여기로(시험은 가짜) ──
export type LogRow = { env: string | null; realm_id: string | null; action: string; ok: boolean; http_status: number | null; intuit_tid: string | null; error: string | null; by_staff: string | null; ms: number };
export type Deps = {
  env: (name: string) => string | undefined;
  fetch: (url: string, init: RequestInit) => Promise<Response>;                                      // Intuit 만(DB 는 rpc)
  rpcUser: (fn: string, args: Record<string, unknown>, jwt: string) => Promise<unknown>;            // 사용자 JWT 그대로(DB 의 문이 그 사람을 본다) · 실패 RpcError
  rpcService: (fn: string, args: Record<string, unknown>) => Promise<unknown>;                       // service_role 창구 · 실패 RpcError
  log: (row: LogRow) => Promise<void>;                                                               // qbo_call_log 한 줄 + 90 일 지우기 — 던지지 않는다
  now: () => number;
  sleep: (ms: number) => Promise<void>;
  randomBytes: (n: number) => Uint8Array;
  uuid: () => string;
  warn: (msg: string) => void;                                                                       // 이미 scrub 된 글만 온다
  discovery: DiscoveryCache;
};
type Ctx = { d: Deps; secrets: string[]; env: Env | null; byStaff: string | null };
const json = (status: number, obj: unknown): Response => new Response(JSON.stringify(obj, null, 2), { status, headers: { "Content-Type": "application/json", ...CORS } });
const cfgOf = (d: Deps): { qboEnv: Env | null; raw: string | undefined } => { const raw = d.env("QBO_ENV"); return { qboEnv: envOf(raw), raw }; };
function clientOf(c: Ctx, env: Env): { id: string; secret: string } {
  const n = secretNames(env), id = (c.d.env(n.id) ?? "").trim(), secret = (c.d.env(n.secret) ?? "").trim();
  if (!id || !secret) throw new QboError(500, `QuickBooks ${env} app keys are not set (${n.id} · ${n.secret}) — refusing (fail-closed)`);
  c.secrets.push(secret);
  return { id, secret };
}
const sc = (c: Ctx, s: string) => scrub(s, c.secrets);

// ── Intuit 호출 하나 = 기록 한 줄 · 네트워크 · 5xx 만 1 회 재시도 · 2xx 가 아니어도 던지지 않고 돌려준다(갈래는 부르는 쪽이) ──
type IntuitResult = { status: number; body: unknown; tid: string | null; networkError: string | null; error: string | null };
async function intuitCall(c: Ctx, action: string, url: string, init: RequestInit, realm: string | null, retry = true): Promise<IntuitResult> {
  const t0 = c.d.now();
  let r: IntuitResult = { status: 0, body: null, tid: null, networkError: null, error: null };
  for (let attempt = 0; attempt < 2; attempt++) {
    r = { status: 0, body: null, tid: null, networkError: null, error: null };
    try {
      const res = await c.d.fetch(url, init);
      r.status = res.status; r.tid = tidOf(res.headers);
      const text = await res.text();
      try { r.body = text ? JSON.parse(text) : null; } catch { r.body = text; }
      if (!res.ok) r.error = sc(c, intuitErrorText(r.status, r.body));
    } catch (e) {
      r.networkError = sc(c, String((e as Error)?.message ?? e).slice(0, 200));
      r.error = "Intuit " + action + " unreachable: " + r.networkError;
    }
    if (!(retry && attempt === 0 && isRetryable(r.status, r.networkError !== null))) break;
    await c.d.sleep(RETRY_DELAY_MS);
  }
  await c.d.log({ env: c.env, realm_id: realm, action, ok: r.error === null, http_status: r.status || null, intuit_tid: r.tid, error: r.error ? r.error.slice(0, 400) : null, by_staff: c.byStaff, ms: c.d.now() - t0 });
  return r;
}
const form = (o: Record<string, string>): string => new URLSearchParams(o).toString();
async function tokenCall(c: Ctx, action: "token_exchange" | "refresh", env: Env, endpoint: string, body: Record<string, string>, realm: string | null): Promise<IntuitResult> {
  const k = clientOf(c, env);
  return await intuitCall(c, action, endpoint, { method: "POST", headers: { Authorization: basicAuth(k.id, k.secret), Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" }, body: form(body) }, realm);
}
async function revokeCall(c: Ctx, env: Env, endpoint: string, refreshToken: string, realm: string | null): Promise<IntuitResult> {
  const k = clientOf(c, env);
  c.secrets.push(refreshToken);
  return await intuitCall(c, "revoke", endpoint, { method: "POST", headers: { Authorization: basicAuth(k.id, k.secret), Accept: "application/json", "Content-Type": "application/json" }, body: JSON.stringify({ token: refreshToken }) }, realm);
}
async function companyInfoCall(c: Ctx, env: Env, realm: string, access: string): Promise<IntuitResult> {
  c.secrets.push(access);
  const url = `${API_BASE[env]}/v3/company/${encodeURIComponent(realm)}/companyinfo/${encodeURIComponent(realm)}?minorversion=${MINOR_VERSION}`;
  return await intuitCall(c, "companyinfo", url, { method: "GET", headers: { Authorization: "Bearer " + access, Accept: "application/json" } }, realm);
}
const discoveryOf = (c: Ctx, env: Env) => c.d.discovery.get(env, async (url) => { const r = await c.d.fetch(url, { method: "GET", headers: { Accept: "application/json" } }); if (!r.ok) throw new Error("HTTP " + r.status); return await r.json(); }, c.d.now());

// ── 토큰 쥐기(갱신 포함) — qbo_token_get → 5 분 안이면 claim → Intuit refresh → save(판 번호) · 임대 못 받으면 기다렸다 다시 읽기 ──
type TokenRow = { env: Env; realm_id: string; status: string; token_version: number; access_expires_at: string; refresh_expires_at: string | null; refresh_token: string; access_token: string };
async function tokenGet(c: Ctx): Promise<TokenRow> {
  try {
    const t = await c.d.rpcService("qbo_token_get", {}) as TokenRow;
    c.secrets.push(t.access_token, t.refresh_token);
    return t;
  } catch (e) {
    if (e instanceof RpcError && /not connected/i.test(e.message)) throw new QboError(409, "QuickBooks is not connected — connect it in Settings → QuickBooks");
    throw e;
  }
}
function envGuard(c: Ctx, rowEnv: string): Env {
  const env = c.env;
  if (!env) throw new QboError(500, "QBO_ENV is not set (sandbox | production) — refusing (fail-closed)");
  if (rowEnv !== env) throw new QboError(409, `The QuickBooks connection on file is ${rowEnv} but this function runs as ${env} (QBO_ENV) — disconnect it in Settings → QuickBooks, then connect again`);
  return env;
}
export type Held = { access: string; env: Env; realm: string; token_version: number; access_expires_at: string; refresh_expires_at: string | null; refreshed: boolean };
async function ensureToken(c: Ctx, force: boolean): Promise<Held> {
  const t = await tokenGet(c);
  const env = envGuard(c, t.env);
  if (t.status === "needs_reconnect") throw new QboError(409, "QuickBooks needs to be reconnected — an admin can do it in Settings → QuickBooks → Reconnect");
  const held = (x: TokenRow, refreshed: boolean): Held => ({ access: x.access_token, env, realm: x.realm_id, token_version: x.token_version, access_expires_at: x.access_expires_at, refresh_expires_at: x.refresh_expires_at, refreshed });
  if (!force && new Date(t.access_expires_at).getTime() - c.d.now() > REFRESH_AHEAD_MS) return held(t, false);
  let claim: TokenRow & { refreshing_until: string };
  try {
    claim = await c.d.rpcService("qbo_refresh_claim", { p_owner: c.d.uuid() }) as TokenRow & { refreshing_until: string };
    c.secrets.push(claim.access_token, claim.refresh_token);
  } catch (e) {
    if (!(e instanceof RpcError)) throw e;
    if (/needs to be reconnected/i.test(e.message)) throw new QboError(409, "QuickBooks needs to be reconnected — an admin can do it in Settings → QuickBooks → Reconnect");
    if (!/Another refresh is running/i.test(e.message)) throw e;
    const t0 = c.d.now();                                                                           // 다른 갱신이 쥐고 있다 — 새 판이 저장될 때까지 기다렸다 읽는다
    while (c.d.now() - t0 < LEASE_WAIT_MS) {
      await c.d.sleep(LEASE_POLL_MS);
      const again = await tokenGet(c);
      if (again.status === "needs_reconnect") throw new QboError(409, "QuickBooks needs to be reconnected — an admin can do it in Settings → QuickBooks → Reconnect");
      if (again.token_version !== t.token_version) return held(again, true);
    }
    throw new QboError(503, "Another QuickBooks token refresh is still running — try again in a moment");
  }
  const disc = await discoveryOf(c, env);
  const r = await tokenCall(c, "refresh", env, disc.token_endpoint, { grant_type: "refresh_token", refresh_token: claim.refresh_token }, claim.realm_id);
  if (r.error) {
    if (needsReconnect(r.status, r.body)) {                                                         // invalid_grant — 다시 시도 안 함 · needs_reconnect(+ DB 가 메일 869 · 바뀌는 순간 한 번)
      const marked = await c.d.rpcService("qbo_mark_needs_reconnect", { p_error: r.error }) as { mailed?: boolean };
      throw new QboError(409, "QuickBooks refused the refresh token (invalid_grant) — the connection must be made again: Settings → QuickBooks → Reconnect" + (marked?.mailed ? " (alert mail queued)" : ""));
    }
    throw new QboError(502, "QuickBooks token refresh failed — " + r.error);                        // 임대는 30 s 뒤 풀린다 · 다음 호출이 다시 시도
  }
  const tk = parseTokenResponse(r.body, c.d.now());
  c.secrets.push(tk.access, tk.refresh);
  if (tk.assumedExpiresIn) c.d.warn("qbo refresh: expires_in missing in the token response — assumed " + ACCESS_EXPIRES_DEFAULT_S + " s");
  let saved: { token_version: number; access_expires_at: string; refresh_expires_at: string | null };
  try {
    saved = await c.d.rpcService("qbo_refresh_save", { p_version: claim.token_version, p_refresh: tk.refresh, p_access: tk.access, p_access_exp: tk.accessExp.toISOString(), p_refresh_exp: tk.refreshExp ? tk.refreshExp.toISOString() : null }) as typeof saved;
  } catch (e) {
    if (e instanceof RpcError && /stale/i.test(e.message)) {                                         // 판 번호 다름 = 새 토큰을 잃음 → last_error 와 사람 말(상태는 안 바꾼다)
      const msg = "Two refreshes raced: another one saved first and the token from this refresh was discarded. If QuickBooks answers invalid_grant at the next refresh, reconnect in Settings → QuickBooks";
      try { await c.d.rpcService("qbo_last_error_set", { p_error: msg }); } catch (e2) { c.d.warn("qbo_last_error_set failed: " + sc(c, String((e2 as Error)?.message ?? e2))); }
      throw new QboError(409, msg);
    }
    throw e;
  }
  return { access: tk.access, env, realm: claim.realm_id, token_version: saved.token_version, access_expires_at: saved.access_expires_at, refresh_expires_at: saved.refresh_expires_at, refreshed: true };
}

// ── 핑 — CompanyInfo → company_name · 401 이면 강제 갱신 한 번 뒤 다시 · 그래도 401 이면 needs_reconnect ──
async function ping(c: Ctx): Promise<{ company_name: string; realm_id: string; env: Env; refreshed: boolean }> {
  let h = await ensureToken(c, false);
  let r = await companyInfoCall(c, h.env, h.realm, h.access);
  if (r.status === 401) {
    h = await ensureToken(c, true);
    r = await companyInfoCall(c, h.env, h.realm, h.access);
    if (r.status === 401) {
      await c.d.rpcService("qbo_mark_needs_reconnect", { p_error: "QuickBooks rejected the access token right after a refresh (401) — the connection was probably revoked on the QuickBooks side" });
      throw new QboError(409, "QuickBooks rejected the token even after a refresh — the connection must be made again: Settings → QuickBooks → Reconnect");
    }
  }
  if (r.error) throw new QboError(502, "QuickBooks CompanyInfo failed — " + r.error);
  const name = companyNameOf(r.body);
  if (!name) throw new QboError(502, "QuickBooks CompanyInfo answered without CompanyName");
  await c.d.rpcService("qbo_company_name_set", { p_name: name });
  return { company_name: name, realm_id: h.realm, env: h.env, refreshed: h.refreshed };
}

// ── callback(GET · Intuit 이 브라우저를 보낸다) — 언제나 302 · 본문 비움 · Location 은 고정 주소 + 정해진 why 낱말뿐 ──
async function callback(url: URL, c: Ctx): Promise<Response> {
  const q = url.searchParams;
  const fail = async (why: CallbackWhy, error: string, realm: string | null = null): Promise<Response> => {
    await c.d.log({ env: c.env, realm_id: realm, action: "callback", ok: false, http_status: null, intuit_tid: null, error: sc(c, error).slice(0, 400), by_staff: c.byStaff, ms: 0 });
    return redirect302(callbackLocation(why));
  };
  if (q.get("error")) return await fail("denied", "denied: " + (q.get("error") ?? "").slice(0, 100));
  const state = q.get("state") ?? "", code = q.get("code") ?? "", realm = (q.get("realmId") ?? "").trim();
  if (code) c.secrets.push(code);
  if (!state) return await fail("state", "callback without state");
  let st: { staff_id: string; env: string };
  try { st = await c.d.rpcService("qbo_state_consume", { p_state_hash: await sha256Hex(state) }) as typeof st; }
  catch (e) { return await fail("state", e instanceof RpcError ? e.message : String((e as Error)?.message ?? e)); }
  c.byStaff = st.staff_id;
  if (!c.env) return await fail("env", "QBO_ENV is not set");
  if (st.env !== c.env) return await fail("env", `state was made for ${st.env} but QBO_ENV is ${c.env}`);
  const env = c.env;
  if (!code) return await fail("exchange", "callback without code");
  let disc: Discovery;
  try { clientOf(c, env); disc = await discoveryOf(c, env); } catch (e) { return await fail(e instanceof QboError && /app keys/.test(e.message) ? "env" : "exchange", String((e as Error)?.message ?? e)); }
  const redirectUri = redirectUriOf(c.d.env("SUPABASE_URL") ?? "");
  const r = await tokenCall(c, "token_exchange", env, disc.token_endpoint, { grant_type: "authorization_code", code, redirect_uri: redirectUri }, realm || null);
  if (r.error) return await fail("exchange", "token exchange: " + r.error, realm || null);
  let tk: Tokens;
  try { tk = parseTokenResponse(r.body, c.d.now()); } catch (e) { return await fail("exchange", String((e as Error)?.message ?? e), realm || null); }
  c.secrets.push(tk.access, tk.refresh);
  if (tk.assumedExpiresIn) c.d.warn("qbo callback: expires_in missing in the token response — assumed " + ACCESS_EXPIRES_DEFAULT_S + " s");
  const revokeReceived = async () => { await revokeCall(c, env, disc.revocation_endpoint, tk.refresh, realm || null); };   // 받은 토큰은 바로 되돌려 준다(저장하지 않았으니)
  if (!/^[0-9]{4,32}$/.test(realm)) { await revokeReceived(); return await fail("realm", "callback realmId missing or not a number", realm || null); }
  try {
    await c.d.rpcService("qbo_connection_save", { p_env: env, p_realm: realm, p_refresh: tk.refresh, p_access: tk.access, p_access_exp: tk.accessExp.toISOString(), p_refresh_exp: tk.refreshExp ? tk.refreshExp.toISOString() : null, p_staff: st.staff_id });
  } catch (e) {
    const msg = e instanceof RpcError ? e.message : String((e as Error)?.message ?? e);
    const realmRefused = /not the company this IMS was first connected to/i.test(msg);               // qbo_connection_save 의 거부 글(20261029160000)
    await revokeReceived();
    return await fail(realmRefused ? "realm" : "save", "save: " + msg, realm);
  }
  try {
    const ci = await companyInfoCall(c, env, realm, tk.access);
    const name = ci.error ? null : companyNameOf(ci.body);
    if (name) await c.d.rpcService("qbo_company_name_set", { p_name: name });
    else c.d.warn("qbo callback: company name not read — " + sc(c, ci.error ?? "no CompanyName") + " (connection saved; ping later)");
  } catch (e) { c.d.warn("qbo callback: company name step failed — " + sc(c, String((e as Error)?.message ?? e))); }
  await c.d.log({ env, realm_id: realm, action: "callback", ok: true, http_status: null, intuit_tid: null, error: null, by_staff: st.staff_id, ms: 0 });
  return redirect302(callbackLocation(null));
}

// ── 문 둘 — 직원(사용자 JWT → DB 창구가 본다) · cron(x-ims-cron-key == IMS_CRON_SECRET · refresh 만) ──
function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}
async function disconnect(c: Ctx): Promise<Response> {
  let revoked: boolean | null = null, note: string | null = null, env: Env | null = null, realm: string | null = null;
  try {
    const t = await tokenGet(c);
    env = envOf(t.env); realm = t.realm_id;
    if (env) {
      try {
        const disc = await discoveryOf(c, env);
        const r = await revokeCall(c, env, disc.revocation_endpoint, t.refresh_token, realm);
        revoked = r.error === null;
        if (!revoked) note = "Intuit revoke failed (" + r.error + ")";
      } catch (e) { revoked = false; note = "Intuit revoke was not possible (" + sc(c, String((e as Error)?.message ?? e)).slice(0, 200) + ")"; }
    }
  } catch (e) {
    if (!(e instanceof QboError && e.status === 409)) throw e;                                       // 연결 없음 — 그래도 delete 로 짝 잃은 Vault 행 · state 를 치운다
    note = "No connection was on file";
  }
  const del = await c.d.rpcService("qbo_connection_delete", {}) as Record<string, unknown>;        // revoke 가 실패해도 지운다(처리방침 약속)
  await c.d.log({ env: env ?? c.env, realm_id: realm, action: "disconnect", ok: true, http_status: null, intuit_tid: null, error: note ? note.slice(0, 400) : null, by_staff: c.byStaff, ms: 0 });
  const message = revoked === false ? "Disconnected in IMS, but QuickBooks could not be told — please also remove Asung IMS under QuickBooks → Apps → Connected apps. " + note
    : revoked === true ? "Disconnected — tokens revoked at Intuit and removed from IMS" : "Nothing was connected — leftover tokens and sign-in states (if any) were removed";
  return json(200, { ok: true, revoked, deleted: del?.deleted === true, vault_rows_removed: del?.vault_rows_removed ?? 0, states_removed: del?.states_removed ?? 0, message });
}
async function status(c: Ctx, jwt: string): Promise<Response> {
  const db = await c.d.rpcUser("qbo_status", {}, jwt) as Record<string, unknown>;
  const env = c.env, n = env ? secretNames(env) : null;
  const rowEnv = typeof db?.env === "string" ? db.env as string : null;
  return json(200, {
    ok: true, ...db,
    qbo_env: env, env_mismatch: rowEnv !== null && env !== null && rowEnv !== env,
    secrets: { client_id: n ? !!(c.d.env(n.id) ?? "").trim() : false, client_secret: n ? !!(c.d.env(n.secret) ?? "").trim() : false, cron_secret: !!(c.d.env("IMS_CRON_SECRET") ?? "").trim(), names: n },
    discovery: c.d.discovery.state(c.d.now()), redirect_uri: redirectUriOf(c.d.env("SUPABASE_URL") ?? ""), settings_url: SETTINGS_URL, minorversion: MINOR_VERSION,
  });
}
export async function handle(req: Request, d: Deps): Promise<Response> {
  const c: Ctx = { d, secrets: [], env: cfgOf(d).qboEnv, byStaff: null };
  for (const e of ENVS) { const n = secretNames(e); const s = (d.env(n.secret) ?? "").trim(); if (s) c.secrets.push(s); }
  try {
    const url = new URL(req.url);
    if (req.method === "GET" && isCallbackPath(url.pathname)) return await callback(url, c);
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") return json(405, { ok: false, error: "POST only (GET is only /callback)" });
    if (!c.env) return json(500, { ok: false, error: "QBO_ENV is not set (sandbox | production) — refusing (fail-closed)" + (cfgOf(d).raw ? " (got " + scrub(String(cfgOf(d).raw)) + ")" : "") });
    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const action = String(body?.action ?? "");
    const cronKey = req.headers.get("x-ims-cron-key");
    if (cronKey !== null) {                                                                          // cron 길 — 열쇠만 · refresh 만 · by_staff 없음
      const secret = d.env("IMS_CRON_SECRET") ?? "";
      if (!secret) return json(500, { ok: false, error: "IMS_CRON_SECRET not configured - refusing (fail-closed)" });
      if (!cronKey || !sameSecret(cronKey, secret)) return json(401, { ok: false, error: "unauthorized" });
      if (!(CRON_ACTIONS as readonly string[]).includes(action)) return json(400, { ok: false, error: "cron may only call: " + CRON_ACTIONS.join(", ") });
      const h = await ensureToken(c, true);
      return json(200, { ok: true, refreshed: h.refreshed, token_version: h.token_version, access_expires_at: h.access_expires_at, refresh_expires_at: h.refresh_expires_at, env: h.env, realm_id: h.realm });
    }
    if (!(ACTIONS as readonly string[]).includes(action)) return json(400, { ok: false, error: "action must be one of: " + ACTIONS.join(", ") });
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json(401, { ok: false, error: "Missing Authorization" });
    if (action === "status") return await status(c, jwt);
    let gate: { staff_id: string | null; name: string | null };
    try { gate = await d.rpcUser("qbo_admin_gate", {}, jwt) as typeof gate; }
    catch (e) { if (e instanceof RpcError) return json(e.status === 401 ? 401 : 403, { ok: false, error: e.status === 401 ? "Invalid session — sign in again" : e.message }); throw e; }
    c.byStaff = gate?.staff_id ?? null;
    if (action === "start") {
      const env = c.env;
      clientOf(c, env);
      const disc = await discoveryOf(c, env);
      const raw = newStateRaw(d.randomBytes(32));
      const st = await d.rpcUser("qbo_state_new", { p_env: env, p_state_hash: await sha256Hex(raw) }, jwt) as { expires_at: string };
      return json(200, { ok: true, url: authorizeUrl(disc.authorization_endpoint, clientOf(c, env).id, redirectUriOf(d.env("SUPABASE_URL") ?? ""), raw), env, expires_at: st?.expires_at ?? null, redirect_uri: redirectUriOf(d.env("SUPABASE_URL") ?? "") });
    }
    if (action === "disconnect") return await disconnect(c);
    if (action === "refresh") { const h = await ensureToken(c, true); return json(200, { ok: true, refreshed: h.refreshed, token_version: h.token_version, access_expires_at: h.access_expires_at, refresh_expires_at: h.refresh_expires_at, env: h.env, realm_id: h.realm }); }
    if (action === "ping") return json(200, { ok: true, ...(await ping(c)) });
    return json(400, { ok: false, error: "unknown action" });
  } catch (e) {
    if (e instanceof QboError) return json(e.status, { ok: false, error: sc(c, e.message) });
    if (e instanceof RpcError) return json(e.status === 401 ? 401 : 422, { ok: false, error: sc(c, e.status === 401 ? "Invalid session — sign in again" : e.message) });
    const msg = sc(c, String((e as Error)?.message ?? e)).slice(0, 400);
    d.warn("qbo failed: " + msg);
    return json(500, { ok: false, error: msg });
  }
}
