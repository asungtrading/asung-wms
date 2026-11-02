// deno test supabase/functions/qbo/qbo_test.ts — Intuit · DB · 네트워크 무접촉(가짜 fetch · 가짜 DB 창구 열둘 + qbo_last_error_set) · qbo-1b ① ~ ⑩ + ⓪ 순수 함수 · ⑪ 회사 이름 저장 거부의 흔적(qbo-1c 뒤 · 판단 4)
//   qbo-read-1(2026-11-01 · 판정 933): ⑫ query · ⑬ read + 읽기 전용 요청 검사 — 가짜 Intuit 에 /query · /<entity>/<id> · /preferences 길(QueryResponse 꼴 · SyncToken · Customer 연락처 칸 포함)
//   가짜 DB 는 20261029160000(qbo-1a) 창구의 거부 글 · 반환 키를 그대로 흉내 낸다(state 10 분 · 한 번 · realm 고정 · 임대 · 판 번호 · needs_reconnect 거부 · mark 의 mailed = connected 에서 바뀔 때만)
//   qbo-sync-1b(2026-11-01 · 판정 934): ⑭ pull — 가짜 DB 에 qbo_pull_begin · qbo_entity_upsert · qbo_pull_finish(20261101210000 의 거부 글 · 반환 키 그대로) · 쪽 1000 은 override 로 · 기존 ⓪ ~ ⑬ 무변
//   ⚠️ 모든 비밀 · 토큰 가짜 값에 ZZSECRET 표식 — 응답 · 기록 · warn 어디에도 그 표식이 없어야 한다(⑨ + 모든 시험 끝)
import { ACCESS_EXPIRES_DEFAULT_S, ACTIONS, ADMIN_ACTIONS, assertReadOnlyRequest, authorizeUrl, KEY_ACTIONS, MAXRESULTS_MAX, parseQuery, QboError, queryForLog, QUERY_ENTITIES, RESPONSE_MAX_BYTES, stripPii, callbackLocation, PII_FIELDS, PULL_ENTITIES, PULL_FIELDS, PULL_NO_ACTIVE_FILTER, PULL_PAGE, pullQueryText, type CallbackWhy, DISCOVERY_TTL_MS, DiscoveryCache, handle, intuitErrorText, isCallbackPath, isRetryable, needsReconnect, newStateRaw, parseDiscovery, parseTokenResponse, redirectUriOf, RpcError, scrub, SETTINGS_URL, sha256Hex, type Deps, type LogRow } from "../_shared/qbo.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
function ok(c: boolean, msg: string) { if (!c) throw new Error(msg); }

// ── 가짜 Intuit ──
const SB = "https://fazgmyvzzhqybtvtktyg.supabase.co";
const DISC = { issuer: "https://oauth.platform.intuit.com/op/v1", authorization_endpoint: "https://appcenter.intuit.com/connect/oauth2", token_endpoint: "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer", revocation_endpoint: "https://developer.api.intuit.com/v2/oauth2/tokens/revoke" };
type Hit = { url: string; method: string; body: string; auth: string | null };
type Intuit = { hits: Hit[]; tokenN: number; override: ((h: Hit) => Response | Error | null)[] };
const jres = (status: number, body: unknown, tid = "tid-" + status) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", intuit_tid: tid } });
function intuitFake(): { it: Intuit; fetch: Deps["fetch"] } {
  const it: Intuit = { hits: [], tokenN: 0, override: [] };
  const fetch: Deps["fetch"] = async (url, init) => {
    const h: Hit = { url, method: String(init.method ?? "GET"), body: typeof init.body === "string" ? init.body : "", auth: (init.headers as Record<string, string>)?.Authorization ?? null };
    it.hits.push(h);
    for (const o of it.override) { const r = o(h); if (r instanceof Error) throw r; if (r) return r; }
    if (url.includes("/.well-known/")) return jres(200, DISC, "tid-disc");
    if (url === DISC.token_endpoint) {
      const p = new URLSearchParams(h.body); it.tokenN++;
      if (p.get("grant_type") === "authorization_code") return jres(200, { access_token: `AT-x-ZZSECRET-${it.tokenN}`, refresh_token: `RT-x-ZZSECRET-${it.tokenN}`, expires_in: 3600, x_refresh_token_expires_in: 8726400, token_type: "bearer" }, "tid-tok");
      return jres(200, { access_token: `AT-r-ZZSECRET-${it.tokenN}`, refresh_token: `RT-r-ZZSECRET-${it.tokenN}`, expires_in: 3600, x_refresh_token_expires_in: 8726400, token_type: "bearer" }, "tid-ref");
    }
    if (url === DISC.revocation_endpoint) return jres(200, {}, "tid-rev");
    if (url.includes("/companyinfo/")) return jres(200, { CompanyInfo: { CompanyName: "Sandbox Company CA 9bca", Id: "1", SyncToken: "4", Email: { Address: "owner-ZZPII@example.invalid" } } }, "tid-ci");
    if (url.includes("/query?")) {                                                                   // QueryResponse 꼴 — 엔터티 이름 키 · startPosition · maxResults · count(*) 는 totalCount 만
      const q = new URL(url).searchParams.get("query") ?? "";
      const ent = (/\bfrom\s+([A-Za-z]+)/i.exec(q) ?? [])[1] ?? "";
      const entity = QUERY_ENTITIES.find((e) => e.toLowerCase() === ent.toLowerCase()) ?? ent;
      if (/^select\s+count\s*\(\s*\*\s*\)/i.test(q)) return jres(200, { QueryResponse: { totalCount: 1234 }, time: "2026-11-01T12:00:00Z" }, "tid-count");
      const max = Number((/\bmaxresults\s+(\d+)/i.exec(q) ?? [])[1] ?? 0), start = Number((/\bstartposition\s+(\d+)/i.exec(q) ?? [])[1] ?? 1);
      const n = Math.min(max, 3), star = /^select\s+\*/i.test(q);                                    // qbo-sync-1c 실물: 칸을 고른 조회는 Sku 를 안 돌려준다(sparse true) · select * 만 Sku
      const rows = Array.from({ length: n }, (_, i) => entity === "Customer"
        ? { Id: String(start + i), DisplayName: "Caribbean Island Food Market " + (start + i), SyncToken: "0", ParentRef: { value: "77" } }
        : star ? { Id: String(start + i), Name: entity + " " + (start + i), SyncToken: String(i), Sku: "SKU-" + (start + i), Active: true }
        : { Id: String(start + i), Name: entity + " " + (start + i), SyncToken: String(i), Active: true, sparse: true });
      return jres(200, { QueryResponse: { [entity]: rows, startPosition: start, maxResults: n }, time: "2026-11-01T12:00:00Z" }, "tid-q");
    }
    if (url.includes("/preferences?")) return jres(200, { Preferences: { Id: "1", SyncToken: "9", CurrencyPrefs: { MultiCurrencyEnabled: true, HomeCurrency: { value: "CAD" } } } }, "tid-pref");
    if (/\/customer\/\d+\?/.test(url)) return jres(200, { Customer: { Id: "123", DisplayName: "Caribbean Island Food Market", SyncToken: "7", ParentRef: { value: "77" }, PrimaryEmailAddr: { Address: "shop-ZZPII@example.invalid" }, PrimaryPhone: { FreeFormNumber: "416-ZZPII" }, Mobile: { FreeFormNumber: "ZZPII" }, Fax: { FreeFormNumber: "ZZPII" }, BillAddr: { Line1: "35 ZZPII Rd" }, ShipAddr: { Line1: "ZZPII" }, WebAddr: { URI: "ZZPII" }, Balance: 515.1 } }, "tid-cust");
    if (/\/vendor\/\d+\?/.test(url)) return jres(200, { Vendor: { Id: "5", DisplayName: "USD Supplier", SyncToken: "2", CurrencyRef: { value: "USD" }, PrimaryEmailAddr: { Address: "ZZPII" }, BillAddr: { Line1: "ZZPII" } } }, "tid-vend");
    if (/\/item\/\d+\?/.test(url)) return jres(200, { Item: { Id: "9", Name: "Freight", Type: "Service", SyncToken: "3", Sku: null } }, "tid-item");
    if (/\/journalentry\/\d+\?/.test(url)) return jres(404, { Fault: { Error: [{ Message: "Object Not Found", Detail: "Object Not Found : Something you're trying to use has been made inactive.", code: "610" }], type: "ValidationFault" } }, "tid-404");
    return jres(404, { Fault: { Error: [{ Message: "no route", code: "404" }], type: "SystemFault" } });
  };
  return { it, fetch };
}

// ── 가짜 DB(창구 열둘 + last_error_set · 20261029160000 의 글 그대로) ──
type Conn = { env: string; realm_id: string; status: string; company_name: string | null; token_version: number; access_exp: number; refresh_exp: number | null; refresh: string; access: string; lease_until: number | null; last_error: string | null; connected_by: string };
type Pull = { started_at: number; next_start: number; received: number; pages: number; finished_at: number | null };
type Ent = { name: string; sku: string | null; fetched_at: number; gone_at: number | null };
type Db = { conn: Conn | null; states: Map<string, { staff_id: string; env: string; created_at: number; used_at: number | null }>; pin: Record<string, string | null>; calls: string[]; mails: number; saveFails: boolean; staleOnSave: boolean; lastErrors: string[]; versionBumpOnSleep: boolean; pulls: Map<string, Pull>; ents: Map<string, Map<string, Ent>>; keys: Record<string, string | null> };   // keys = JWT → perms 열쇠('qbo' · 'qbo:read' · null) · qbo-sync-2a 945
const STAFF = "11111111-1111-4111-8111-111111111111";
const STAFF_MGR = "22222222-2222-4222-8222-222222222222";
const staffOf = (jwt: string) => jwt === "JWT-ADMIN" ? STAFF : STAFF_MGR;
function dbFake(clock: () => number): { db: Db; rpcUser: Deps["rpcUser"]; rpcService: Deps["rpcService"] } {
  const db: Db = { conn: null, states: new Map(), pin: { sandbox: null, production: null }, calls: [], mails: 0, saveFails: false, staleOnSave: false, lastErrors: [], versionBumpOnSleep: false, pulls: new Map(), ents: new Map(), keys: { "JWT-ADMIN": "qbo", "JWT-MGR": null } };   // 2a: admin 도 열쇠를 켜야 한다 — 기본 가짜 admin 은 켜 둔다
  const refuse = (msg: string) => { throw new RpcError(400, msg); };
  const keyOf = (jwt: string) => db.keys[jwt] === "qbo" ? "write" : db.keys[jwt] === "qbo:read" ? "read" : null;
  const rpcUser: Deps["rpcUser"] = async (fn, args, jwt) => {
    db.calls.push("user:" + fn);
    if (jwt !== "JWT-ADMIN" && jwt !== "JWT-MGR") throw new RpcError(401, "JWT expired");
    if (fn === "qbo_status") return db.conn ? { status: db.conn.status, env: db.conn.env, realm_id: db.conn.realm_id, company_name: db.conn.company_name, token_version: db.conn.token_version, last_error: db.conn.last_error, caller_is_admin: jwt === "JWT-ADMIN", caller_qbo: keyOf(jwt), pinned_realm: db.pin } : { status: "none", caller_is_admin: jwt === "JWT-ADMIN", caller_qbo: keyOf(jwt), pinned_realm: db.pin };
    // qbo-sync-2a 945 — 열쇠 문(20261102003000 의 거부 글 그대로): qbo_key_gate · 1a 짝 · 받기 창구(qbo_sync_gate = qbo_key_gate(true)) · 그 밖은 admin 만
    const KEY_FNS = ["qbo_key_gate", "qbo_pull_begin", "qbo_entity_upsert", "qbo_pull_finish"];
    if (fn === "qbo_key_gate") { const write = args.p_write !== false; if (db.keys[jwt] === "qbo" || (!write && db.keys[jwt] === "qbo:read")) return staffOf(jwt); refuse(`Your account does not have the 'qbo'${write ? " (write)" : ""} permission — ask an admin to switch it on in Staff — nothing was changed`); }
    if (KEY_FNS.includes(fn) && db.keys[jwt] !== "qbo") refuse("Your account does not have the 'qbo' (write) permission — ask an admin to switch it on in Staff — nothing was changed");
    if (!KEY_FNS.includes(fn) && jwt !== "JWT-ADMIN") refuse("Only an admin can connect, disconnect or reconnect QuickBooks — nothing was changed");
    if (fn === "qbo_admin_gate") return { staff_id: STAFF, name: "QBX Admin" };
    if (fn === "qbo_state_new") {
      const env = String(args.p_env), h = String(args.p_state_hash);
      if (!/^[0-9a-f]{64}$/.test(h)) refuse("State hash must be 64 hex characters (sha256) — nothing was saved");
      if (db.conn && db.conn.status === "connected") refuse(`QuickBooks is already connected to company ${db.conn.company_name ?? db.conn.realm_id} (${db.conn.env}) — disconnect first to connect again — nothing was saved`);
      if (db.conn && db.conn.env !== env) refuse(`The connection on file is ${db.conn.env} — disconnect it before connecting to ${env} — nothing was saved`);
      db.states.set(h, { staff_id: STAFF, env, created_at: clock(), used_at: null });
      return { state_hash: h, env, expires_at: new Date(clock() + 600_000).toISOString() };
    }
    // qbo-sync-1a 창구 셋(20261101210000 의 거부 글 · 반환 키 그대로) — realm 은 연결된 회사와 같아야 · begin 은 끝난 run 뒤거나 restart 면 새 run · upsert · finish 는 진행 중인 run 필수
    if (fn === "qbo_pull_begin" || fn === "qbo_entity_upsert" || fn === "qbo_pull_finish") {
      const t = String(args.p_type);
      if (!(PULL_ENTITIES as readonly string[]).includes(t)) refuse(`type must be one of Account, TaxCode, Term, PaymentMethod, Customer, Vendor, Item (got ${t})`);
      if (String(args.p_realm) !== db.conn?.realm_id) refuse(`QuickBooks company ${args.p_realm} is not the connected company — nothing was changed`);
      const s = db.pulls.get(t);
      if (fn === "qbo_pull_begin") {
        if (s && s.finished_at === null && args.p_restart !== true) return { realm_id: args.p_realm, qbo_type: t, started_at: new Date(s.started_at).toISOString(), next_start: s.next_start, received: s.received, pages: s.pages, resumed: true };
        const n: Pull = { started_at: clock(), next_start: 1, received: 0, pages: 0, finished_at: null }; db.pulls.set(t, n);
        return { realm_id: args.p_realm, qbo_type: t, started_at: new Date(n.started_at).toISOString(), next_start: 1, received: 0, pages: 0, resumed: false };
      }
      if (!s || s.finished_at !== null) refuse(`No pull in progress for ${t} — call qbo_pull_begin first`);
      if (fn === "qbo_entity_upsert") {
        const rows = args.p_rows as Record<string, unknown>[];
        if (!Array.isArray(rows)) refuse(`rows must be a JSON array of QuickBooks ${t} rows`);
        const m = db.ents.get(t) ?? new Map<string, Ent>(); db.ents.set(t, m);
        for (const r of rows) { const id = String(r.Id ?? "").trim(), name = String(r.Name ?? r.DisplayName ?? "").trim(); if (!id || !name) refuse(`Every ${t} row needs Id and Name (or DisplayName) — nothing was saved`); m.set(id, { name, sku: typeof r.Sku === "string" && r.Sku.trim() ? r.Sku.trim() : null, fetched_at: clock(), gone_at: null }); }
        s!.received += rows.length; s!.pages++; s!.next_start = Number(args.p_next_start ?? s!.next_start);
        return { qbo_type: t, received_now: rows.length, received: s!.received, pages: s!.pages, next_start: s!.next_start };
      }
      let gone = 0; for (const e of (db.ents.get(t) ?? new Map<string, Ent>()).values()) if (e.gone_at === null && e.fetched_at < s!.started_at) { e.gone_at = clock(); gone++; }
      s!.finished_at = clock();
      return { qbo_type: t, received: s!.received, pages: s!.pages, gone, finished_at: new Date(s!.finished_at).toISOString() };
    }
    throw new RpcError(404, "no such user rpc " + fn);
  };
  const rpcService: Deps["rpcService"] = async (fn, args) => {
    db.calls.push("svc:" + fn);
    const c = db.conn;
    switch (fn) {
      case "qbo_state_consume": {
        const s = db.states.get(String(args.p_state_hash));
        if (!s) refuse("Sign-in state not found — start the connection again from Settings — nothing was changed");
        if (s!.used_at !== null) refuse("Sign-in state was already used — start the connection again from Settings — nothing was changed");
        if (s!.created_at < clock() - 600_000) refuse("Sign-in state expired (10 minutes) — start the connection again from Settings — nothing was changed");
        s!.used_at = clock();
        return { staff_id: s!.staff_id, env: s!.env, created_at: new Date(s!.created_at).toISOString() };
      }
      case "qbo_connection_save": {
        const env = String(args.p_env), realm = String(args.p_realm ?? "").trim();
        if (!/^[0-9]{4,32}$/.test(realm)) refuse(`QuickBooks company id (realmId) "${realm}" is not a number — nothing was saved`);
        if (db.saveFails) refuse(`Connecting staff ${args.p_staff} is not on file — nothing was saved`);
        if (db.pin[env] === null) db.pin[env] = realm;
        else if (db.pin[env] !== realm) refuse(`QuickBooks company ${realm} is not the company this IMS was first connected to (${db.pin[env]}) — connect the same company, or ask an admin to clear the pinned company first — nothing was saved`);
        if (c && c.env !== env) refuse(`A ${c.env} connection is still on file — disconnect it before connecting to ${env} — nothing was saved`);
        const keepName = c && c.realm_id === realm ? c.company_name : null;
        db.conn = { env, realm_id: realm, status: "connected", company_name: keepName, token_version: (c?.token_version ?? 0) + 1, access_exp: Date.parse(String(args.p_access_exp)), refresh_exp: args.p_refresh_exp ? Date.parse(String(args.p_refresh_exp)) : null, refresh: String(args.p_refresh), access: String(args.p_access), lease_until: null, last_error: null, connected_by: String(args.p_staff) };
        return { env, realm_id: realm, status: "connected", token_version: db.conn.token_version, company_name: keepName };
      }
      case "qbo_company_name_set": { if (!c) refuse("QuickBooks is not connected — nothing was saved"); c!.company_name = String(args.p_name); return { company_name: c!.company_name }; }
      case "qbo_token_get": {
        if (!c) refuse("QuickBooks is not connected — nothing to read");
        return { env: c!.env, realm_id: c!.realm_id, status: c!.status, token_version: c!.token_version, access_expires_at: new Date(c!.access_exp).toISOString(), refresh_expires_at: c!.refresh_exp ? new Date(c!.refresh_exp).toISOString() : null, refresh_token: c!.refresh, access_token: c!.access };
      }
      case "qbo_refresh_claim": {
        if (!c) refuse("QuickBooks is not connected — nothing to refresh");
        if (c!.status === "needs_reconnect") refuse(`QuickBooks needs to be reconnected (${c!.last_error ?? "no error text"}) — refresh is not attempted — ask an admin to reconnect in Settings`);
        if (c!.lease_until !== null && c!.lease_until > clock()) refuse("Another refresh is running (lease until 12:00:30Z) — wait and read the token again");
        c!.lease_until = clock() + 30_000;
        return { env: c!.env, realm_id: c!.realm_id, token_version: c!.token_version, refreshing_until: new Date(c!.lease_until).toISOString(), refresh_token: c!.refresh, access_token: c!.access };
      }
      case "qbo_refresh_save": {
        if (!c) refuse("QuickBooks is not connected — nothing was saved");
        if (db.staleOnSave || c!.token_version !== Number(args.p_version)) refuse(`Token version ${args.p_version} is stale — the connection is now at version ${c!.token_version + (db.staleOnSave ? 1 : 0)} (another refresh saved first) — nothing was saved`);
        c!.token_version++; c!.refresh = String(args.p_refresh); c!.access = String(args.p_access); c!.access_exp = Date.parse(String(args.p_access_exp)); if (args.p_refresh_exp) c!.refresh_exp = Date.parse(String(args.p_refresh_exp)); c!.lease_until = null; c!.last_error = null;
        return { token_version: c!.token_version, access_expires_at: new Date(c!.access_exp).toISOString(), refresh_expires_at: c!.refresh_exp ? new Date(c!.refresh_exp).toISOString() : null };
      }
      case "qbo_mark_needs_reconnect": {
        if (!c) refuse("QuickBooks is not connected — nothing was changed");
        const was = c!.status; c!.status = "needs_reconnect"; c!.last_error = String(args.p_error).slice(0, 400); c!.lease_until = null;
        const mailed = was === "connected"; if (mailed) db.mails++;
        return { status: "needs_reconnect", last_error: c!.last_error, last_error_at: new Date(clock()).toISOString(), was, mailed, mail_to: mailed ? "caleb@asung.ca" : null };
      }
      case "qbo_last_error_set": { if (!c) refuse("QuickBooks is not connected — nothing was changed"); c!.last_error = String(args.p_error).slice(0, 400); db.lastErrors.push(c!.last_error); return { status: c!.status, last_error: c!.last_error }; }
      case "qbo_connection_delete": { const had = !!c; const n = db.states.size; db.conn = null; db.states.clear(); return { deleted: had, env: c?.env ?? null, vault_rows_removed: had ? 2 : 0, states_removed: n }; }
    }
    throw new RpcError(404, "no such service rpc " + fn);
  };
  return { db, rpcUser, rpcService };
}

// ── 장치 ──
type World = { deps: Deps; db: Db; it: Intuit; logs: LogRow[]; warns: string[]; env: Record<string, string | undefined>; clock: { t: number }; sleeps: number[] };
function world(env: Record<string, string | undefined> = {}): World {
  const clock = { t: Date.parse("2026-10-29T12:00:00Z") };
  const envs: Record<string, string | undefined> = { QBO_ENV: "sandbox", QBO_CLIENT_ID_SANDBOX: "client-id-sandbox", QBO_CLIENT_SECRET_SANDBOX: "cs-ZZSECRET-sandbox-0123456789", QBO_CLIENT_ID_PRODUCTION: "client-id-prod", QBO_CLIENT_SECRET_PRODUCTION: "cs-ZZSECRET-prod-0123456789", SUPABASE_URL: SB, IMS_CRON_SECRET: "cron-ZZSECRET-0123456789abcdef", ...env };
  const { it, fetch } = intuitFake();
  const { db, rpcUser, rpcService } = dbFake(() => clock.t);
  const logs: LogRow[] = [], warns: string[] = [], sleeps: number[] = [];
  let rnd = 0;
  const w: World = { db, it, logs, warns, env: envs, clock, sleeps, deps: {
    env: (k) => envs[k], fetch, rpcUser, rpcService,
    log: async (row) => { logs.push(row); },
    now: () => clock.t,
    sleep: async (ms) => { sleeps.push(ms); clock.t += ms; if (db.versionBumpOnSleep && db.conn) { db.conn.token_version++; db.conn.access = "AT-other-ZZSECRET"; db.conn.refresh = "RT-other-ZZSECRET"; db.conn.access_exp = clock.t + 3600_000; db.conn.lease_until = null; } },
    randomBytes: (n) => { const b = new Uint8Array(n); for (let i = 0; i < n; i++) b[i] = (rnd + i * 7) & 255; rnd++; return b; },
    uuid: () => "owner-" + (++rnd),
    warn: (m) => { warns.push(m); },
    discovery: new DiscoveryCache(),
  } };
  return w;
}
const post = (w: World, action: string, jwt: string | null = "JWT-ADMIN", headers: Record<string, string> = {}) =>
  handle(new Request(SB + "/functions/v1/qbo", { method: "POST", headers: { "Content-Type": "application/json", ...(jwt ? { Authorization: "Bearer " + jwt } : {}), ...headers }, body: JSON.stringify({ action }) }), w.deps);
const postBody = (w: World, bodyObj: Record<string, unknown>, jwt: string | null = "JWT-ADMIN", headers: Record<string, string> = {}) =>
  handle(new Request(SB + "/functions/v1/qbo", { method: "POST", headers: { "Content-Type": "application/json", ...(jwt ? { Authorization: "Bearer " + jwt } : {}), ...headers }, body: JSON.stringify(bodyObj) }), w.deps);
const get = (w: World, query: string) => handle(new Request(SB + "/functions/v1/qbo/callback" + query, { method: "GET" }), w.deps);
const body = async (r: Response) => await r.json() as Record<string, unknown>;
function connect(w: World, o: Partial<Conn> = {}) {
  w.db.conn = { env: "sandbox", realm_id: "9341458557490536", status: "connected", company_name: "Sandbox Company CA 9bca", token_version: 1, access_exp: w.clock.t + 3600_000, refresh_exp: w.clock.t + 100 * 86400_000, refresh: "RT-db-ZZSECRET-1", access: "AT-db-ZZSECRET-1", lease_until: null, last_error: null, connected_by: STAFF, ...o };
  w.db.pin.sandbox = w.db.conn.realm_id;
}
async function startAndCallback(w: World, extra = ""): Promise<{ raw: string; res: Response }> {
  const s = await body(await post(w, "start"));
  const raw = new URL(String(s.url)).searchParams.get("state") ?? "";
  const res = await get(w, `?code=CODE-ZZSECRET-abcdefgh&state=${encodeURIComponent(raw)}&realmId=9341458557490536${extra}`);
  return { raw, res };
}
function noLeak(w: World, where: string) {
  const all = JSON.stringify({ logs: w.logs, warns: w.warns });
  ok(!all.includes("ZZSECRET"), where + ": secret or token leaked into call_log/warn: " + all.slice(0, 300));
}
const tokenHits = (w: World) => w.it.hits.filter((h) => h.url === DISC.token_endpoint);
const revokeHits = (w: World) => w.it.hits.filter((h) => h.url === DISC.revocation_endpoint);
const ciHits = (w: World) => w.it.hits.filter((h) => h.url.includes("/companyinfo/"));

Deno.test("⓪ 순수 함수 — authorize URL 다섯 칸 · state 32 바이트 · sha256 · 302 주소 고정 · 토큰 응답(expires_in 없으면 3600 짐작 · x_refresh 없으면 null) · Fault/oauth 오류 글 · 재시도 · invalid_grant 판정 · discovery 파싱 · scrub", async () => {
  const u = new URL(authorizeUrl(DISC.authorization_endpoint, "cid", redirectUriOf(SB + "/"), "st"));
  eq([u.origin + u.pathname, u.searchParams.get("client_id"), u.searchParams.get("scope"), u.searchParams.get("response_type"), u.searchParams.get("redirect_uri"), u.searchParams.get("state")], ["https://appcenter.intuit.com/connect/oauth2", "cid", "com.intuit.quickbooks.accounting", "code", SB + "/functions/v1/qbo/callback", "st"], "authorize url");
  eq(newStateRaw(new Uint8Array(32)).length, 43, "32 bytes → 43 base64url chars");
  let threw = ""; try { newStateRaw(new Uint8Array(16)); } catch (e) { threw = (e as Error).message; } eq(threw.includes("32"), true, "16 bytes refused");
  eq(await sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256 abc");
  eq(callbackLocation(null), SETTINGS_URL + "&qbo=connected", "connected");
  eq(callbackLocation("realm"), SETTINGS_URL + "&qbo=error&why=realm", "why realm");
  threw = ""; try { callbackLocation("evil" as never); } catch (e) { threw = (e as Error).message; } eq(threw.includes("unknown"), true, "unknown why refused");
  eq([isCallbackPath("/qbo/callback"), isCallbackPath("/functions/v1/qbo/callback/"), isCallbackPath("/qbo"), isCallbackPath("/qbo/callbackx")], [true, true, false, false], "callback path");
  const t0 = 1_000_000_000_000;
  const tk = parseTokenResponse({ access_token: "a", refresh_token: "r", expires_in: 3600, x_refresh_token_expires_in: 8726400 }, t0);
  eq([tk.accessExp.getTime() - t0, (tk.refreshExp?.getTime() ?? 0) - t0, tk.assumedExpiresIn], [3600_000, 8726400_000, false], "expiries from response");
  const tk2 = parseTokenResponse({ access_token: "a", refresh_token: "r" }, t0);
  eq([tk2.accessExp.getTime() - t0, tk2.refreshExp, tk2.assumedExpiresIn], [ACCESS_EXPIRES_DEFAULT_S * 1000, null, true], "missing expires_in → 3600 assumed · x_refresh missing → null");
  threw = ""; try { parseTokenResponse({ access_token: "a" }, t0); } catch (e) { threw = (e as Error).message; } eq(threw.includes("refresh_token"), true, "no refresh_token → error");
  eq(intuitErrorText(400, { Fault: { Error: [{ Message: "Invalid Reference Id", Detail: "Something", code: "6240" }], type: "ValidationFault" } }), "HTTP 400 ValidationFault code 6240: Invalid Reference Id — Something", "Fault text");
  eq(intuitErrorText(400, { error: "invalid_grant", error_description: "Incorrect Token type or clientID" }), "HTTP 400 invalid_grant: Incorrect Token type or clientID", "oauth error text");
  eq(intuitErrorText(502, "<html>bad gateway</html>"), "HTTP 502 <html>bad gateway</html>", "plain text body");
  eq(intuitErrorText(500, { x: "y".repeat(900) }).length <= 400, true, "≤ 400");
  eq([isRetryable(503, false), isRetryable(500, false), isRetryable(0, true), isRetryable(400, false), isRetryable(401, false), isRetryable(429, false)], [true, true, true, false, false, false], "retry only network · 5xx");
  eq([needsReconnect(400, { error: "invalid_grant" }), needsReconnect(400, { error: "invalid_client" }), needsReconnect(401, { error: "invalid_grant" }), needsReconnect(500, {})], [true, false, false, false], "invalid_grant only");
  eq(parseDiscovery(DISC)?.token_endpoint, DISC.token_endpoint, "discovery parsed");
  eq(parseDiscovery({ ...DISC, token_endpoint: "http://insecure" }), null, "http endpoint refused");
  eq(parseDiscovery({}), null, "empty refused");
  const s = scrub("Bearer eyJabcdefghijklmnop.qrstuvwxyz.ABC refresh_token=RT1-ZZ&code=CODE-9 {\"access_token\":\"AT-ZZSECRET-1\",\"client_secret\":\"cs-ZZSECRET\"} token=AB11abcdefghijklmnopqrstuvwxyz my-exact-secret-value", ["my-exact-secret-value"]);
  ok(!/ZZSECRET|eyJ|RT1-ZZ|CODE-9|AB11|my-exact-secret-value/.test(s), "scrub removed all forms: " + s);
  eq(scrub("plain words stay", []), "plain words stay", "no-op");
});

Deno.test("① start — admin 아니면 DB 거부 글 그대로(403) · 세션 없음 401 · admin 이면 authorize URL(client_id · scope · response_type · redirect_uri · state) · DB 에는 sha256 만(원문 없음) · 이미 연결이면 DB 거부", async () => {
  const w = world();
  const r1 = await post(w, "start", "JWT-MGR");
  eq([r1.status, (await body(r1)).error], [403, "Only an admin can connect, disconnect or reconnect QuickBooks — nothing was changed"], "manager refused with DB text");
  eq((await post(w, "start", null)).status, 401, "no session");
  eq((await post(w, "start", "JWT-BAD")).status, 401, "bad session → 401");
  const r2 = await post(w, "start");
  const b2 = await body(r2);
  eq(r2.status, 200, "admin ok: " + JSON.stringify(b2));
  const u = new URL(String(b2.url));
  eq([u.origin + u.pathname, u.searchParams.get("client_id"), u.searchParams.get("scope"), u.searchParams.get("response_type"), u.searchParams.get("redirect_uri")], [DISC.authorization_endpoint, "client-id-sandbox", "com.intuit.quickbooks.accounting", "code", SB + "/functions/v1/qbo/callback"], "authorize params");
  const raw = u.searchParams.get("state") ?? "";
  eq(raw.length, 43, "state raw = 32 bytes base64url");
  eq([...w.db.states.keys()], [await sha256Hex(raw)], "DB holds sha256 hex only");
  ok(!JSON.stringify([...w.db.states.entries()]).includes(raw), "raw state not in DB");
  eq(b2.env, "sandbox", "env echoed");
  connect(w);
  const r3 = await post(w, "start");
  eq([r3.status, String((await body(r3)).error).startsWith("QuickBooks is already connected")], [422, true], "already connected → DB refusal");
  noLeak(w, "①");
});

Deno.test("② callback — 어느 갈래든 302 · 본문 없음 · Location 은 고정 주소 + why 낱말뿐: denied · state 없음/모름/지남/두 번 · 교환 실패 · env 다름 · realm 다름(→ revoke) · save 실패(→ revoke) · 성공(→ company name)", async () => {
  const w = world();
  const check = async (res: Response, why: CallbackWhy | null, label: string) => {
    eq([res.status, await res.text(), res.headers.get("Location")], [302, "", callbackLocation(why)], label);
  };
  await check(await get(w, "?error=access_denied&state=%22%3E%3Cscript%3E"), "denied", "denied (request value not in Location)");
  eq(w.it.hits.length, 0, "denied: no Intuit call");
  eq(w.logs.at(-1)?.action + "/" + w.logs.at(-1)?.ok, "callback/false", "denied logged");
  await check(await get(w, "?code=x"), "state", "no state");
  await check(await get(w, "?code=x&state=unknown-state"), "state", "unknown state");
  eq(w.logs.at(-1)?.error, "Sign-in state not found — start the connection again from Settings — nothing was changed", "DB text in log");
  // 지남: start 뒤 11 분
  const s1 = await body(await post(w, "start")); const raw1 = new URL(String(s1.url)).searchParams.get("state") ?? "";
  w.clock.t += 11 * 60_000;
  await check(await get(w, `?code=x&state=${raw1}&realmId=9341458557490536`), "state", "expired state");
  eq(tokenHits(w).length, 0, "expired: no exchange");
  // 교환 실패
  w.it.override.push((h) => h.url === DISC.token_endpoint && h.body.includes("grant_type=authorization_code") ? jres(400, { error: "invalid_grant", error_description: "Incorrect Token type or clientID" }, "tid-x1") : null);
  let r = await startAndCallback(w);
  await check(r.res, "exchange", "exchange 400");
  const lx = w.logs.find((l) => l.action === "token_exchange");
  eq([lx?.ok, lx?.http_status, lx?.intuit_tid, lx?.error], [false, 400, "tid-x1", "HTTP 400 invalid_grant: Incorrect Token type or clientID"], "exchange logged with tid · error");
  eq(tokenHits(w).length, 1, "400 is not retried");
  const th = tokenHits(w)[0];
  ok(th.auth?.startsWith("Basic ") === true && !th.body.includes("client_secret"), "Basic auth · no secret in body");
  eq(new URLSearchParams(th.body).get("redirect_uri"), SB + "/functions/v1/qbo/callback", "redirect_uri same as authorize");
  w.it.override.length = 0;
  // 두 번(같은 state 다시)
  r = await startAndCallback(w);
  await check(r.res, null, "success");
  eq(w.db.conn?.status + "/" + w.db.conn?.realm_id + "/" + w.db.conn?.token_version + "/" + w.db.conn?.company_name, "connected/9341458557490536/1/Sandbox Company CA 9bca", "saved · company name set");
  eq([w.db.conn?.refresh, w.db.conn?.access], ["RT-x-ZZSECRET-1", "AT-x-ZZSECRET-1"], "tokens from the exchange (the 400 above was an override — counter not advanced)");
  eq(w.logs.filter((l) => l.action === "callback" && l.ok).at(-1)?.by_staff, STAFF, "callback ok logged by state's staff");
  const before = tokenHits(w).length;
  await check(await get(w, `?code=CODE-ZZSECRET-again&state=${encodeURIComponent(r.raw)}&realmId=9341458557490536`), "state", "same state twice");
  eq(tokenHits(w).length, before, "replay: no exchange");
  // env 다름: state 는 sandbox 로 만들고 QBO_ENV 를 production 으로
  w.db.conn = null;
  const s2 = await body(await post(w, "start")); const raw2 = new URL(String(s2.url)).searchParams.get("state") ?? "";
  w.env.QBO_ENV = "production";
  await check(await get(w, `?code=x&state=${raw2}&realmId=9341458557490536`), "env", "env mismatch");
  w.env.QBO_ENV = "sandbox";
  // realm 다름 → 받은 토큰 revoke · why=realm
  const nRev = revokeHits(w).length;
  const s3 = await body(await post(w, "start")); const raw3 = new URL(String(s3.url)).searchParams.get("state") ?? "";
  await check(await get(w, `?code=CODE-ZZSECRET-r&state=${raw3}&realmId=9999000011112222`), "realm", "other company");
  eq(revokeHits(w).length, nRev + 1, "received token revoked");
  ok(revokeHits(w).at(-1)!.body.includes("RT-x-ZZSECRET"), "revoke sends the refresh token just received");
  eq(w.db.conn, null, "nothing saved");
  await check(await get(w, `?code=x&state=${(await startAndCallback(w, "&ignored=1")).raw}&realmId=abc`), "state", "(state consumed by the previous success — fresh start below)");
  w.db.conn = null;
  const s4 = await body(await post(w, "start")); const raw4 = new URL(String(s4.url)).searchParams.get("state") ?? "";
  await check(await get(w, `?code=CODE-ZZSECRET-n&state=${raw4}&realmId=abc`), "realm", "realmId not a number");
  // save 실패(다른 까닭) → revoke · why=save
  w.db.saveFails = true;
  const nRev2 = revokeHits(w).length;
  await check((await startAndCallback(w)).res, "save", "save failed");
  eq(revokeHits(w).length, nRev2 + 1, "save failure: token revoked");
  w.db.saveFails = false;
  // 성공인데 CompanyInfo 가 실패 → 그래도 connected(이름은 뒤에 ping)
  w.it.override.push((h) => h.url.includes("/companyinfo/") ? jres(503, {}, "tid-ci503") : null);
  await check((await startAndCallback(w)).res, null, "connected even when CompanyInfo fails");
  eq((w.db as Db).conn?.company_name ?? null, null, "name not set");
  ok(w.warns.some((x) => x.includes("company name not read")), "warned");
  ok(w.logs.every((l) => !l.error || !l.error.includes("ZZSECRET")), "no token in log");
  noLeak(w, "②");
});

Deno.test("③ 갱신 — 5 분 안 만료 → 먼저 갱신 뒤 핑(새 access 로) · 응답의 새 refresh_token 저장(옛 값 아님) · 두 갱신 겹침(임대 거부 → 기다렸다 새 판 읽기 · Intuit 0) · save 판 번호 거부 → last_error + 사람 말 · refresh 동작은 늘 강제", async () => {
  const w = world();
  connect(w, { access_exp: w.clock.t + 2 * 60_000 });
  const r1 = await body(await post(w, "ping"));
  eq([r1.ok, r1.company_name, r1.refreshed], [true, "Sandbox Company CA 9bca", true], "ping refreshed first: " + JSON.stringify(r1));
  eq(w.it.hits.filter((h) => !h.url.includes("well-known")).map((h) => h.url.includes("/companyinfo/") ? "companyinfo" : "token"), ["token", "companyinfo"], "token then companyinfo");
  eq(new URLSearchParams(tokenHits(w)[0].body).get("grant_type") + "/" + new URLSearchParams(tokenHits(w)[0].body).get("refresh_token"), "refresh_token/RT-db-ZZSECRET-1", "refresh with the stored refresh token");
  eq(ciHits(w)[0].auth, "Bearer AT-r-ZZSECRET-1", "companyinfo uses the NEW access token");
  eq([w.db.conn?.refresh, w.db.conn?.token_version, w.db.conn?.lease_until], ["RT-r-ZZSECRET-1", 2, null], "new refresh token saved · version 2 · lease released");
  eq(w.db.calls.filter((c) => c === "svc:qbo_refresh_claim").length, 1, "one claim");
  // 아직 신선 → 갱신 없이 핑
  const n = tokenHits(w).length;
  const r2 = await body(await post(w, "ping"));
  eq([r2.refreshed, tokenHits(w).length], [false, n], "fresh token: no refresh");
  // refresh 동작은 강제
  const r3 = await body(await post(w, "refresh"));
  eq([r3.refreshed, r3.token_version, tokenHits(w).length], [true, 3, n + 1], "refresh action forces");
  // 겹침: 임대가 살아 있다 → 기다렸다 새 판 읽기 · Intuit 호출 0
  w.db.conn!.lease_until = w.clock.t + 20_000; w.db.versionBumpOnSleep = true;
  const n2 = tokenHits(w).length;
  const r4 = await body(await post(w, "refresh"));
  eq([r4.ok, r4.refreshed, r4.token_version, tokenHits(w).length, w.sleeps.at(-1)], [true, true, 4, n2, 1500], "waited 1.5 s · read the other refresh's token · no Intuit call: " + JSON.stringify(r4));
  w.db.versionBumpOnSleep = false;
  // 겹침인데 15 s 안에 아무도 저장 안 함 → 503
  w.db.conn!.lease_until = w.clock.t + 60_000;
  const r5 = await post(w, "refresh");
  eq([r5.status, String((await body(r5)).error).includes("still running")], [503, true], "lease never released → 503");
  w.db.conn!.lease_until = null;
  // save 판 번호 거부 → last_error · 사람 말 · 상태는 connected 그대로
  w.db.staleOnSave = true;
  const r6 = await post(w, "refresh");
  const b6 = await body(r6);
  eq([r6.status, String(b6.error).startsWith("Two refreshes raced"), w.db.conn?.status, w.db.lastErrors.length], [409, true, "connected", 1], "stale save → 409 · last_error set · still connected: " + JSON.stringify(b6));
  w.db.staleOnSave = false;
  noLeak(w, "③");
});

Deno.test("④ invalid_grant — needs_reconnect · 재시도 0 · mark 한 번(DB 가 메일 한 번) · 다음 호출은 claim 거부(mark 0 · 메일 0) · 핑 401 은 강제 갱신 한 번 뒤 다시 · 그래도 401 이면 needs_reconnect", async () => {
  const w = world();
  connect(w);
  w.it.override.push((h) => h.url === DISC.token_endpoint ? jres(400, { error: "invalid_grant", error_description: "Token invalid" }, "tid-ig") : null);
  const r1 = await post(w, "refresh");
  const b1 = await body(r1);
  eq([r1.status, String(b1.error).includes("Reconnect"), String(b1.error).includes("alert mail queued")], [409, true, true], "invalid_grant → 409 human text: " + JSON.stringify(b1));
  eq([w.db.conn?.status, w.db.mails, tokenHits(w).length, w.db.calls.filter((c) => c === "svc:qbo_mark_needs_reconnect").length], ["needs_reconnect", 1, 1, 1], "marked · one mail · no retry");
  eq(w.logs.find((l) => l.action === "refresh")?.error, "HTTP 400 invalid_grant: Token invalid", "logged error");
  const r2 = await post(w, "refresh");
  eq([r2.status, w.db.mails, tokenHits(w).length, w.db.calls.filter((c) => c === "svc:qbo_mark_needs_reconnect").length], [409, 1, 1, 1], "already needs_reconnect: claim refuses · no Intuit · no second mark/mail");
  const r3 = await post(w, "ping");
  eq([r3.status, ciHits(w).length], [409, 0], "ping refuses too (no CompanyInfo call)");
  // invalid_client(설정 문제)는 표시하지 않는다
  const w2 = world(); connect(w2);
  w2.it.override.push((h) => h.url === DISC.token_endpoint ? jres(401, { error: "invalid_client" }, "tid-ic") : null);
  const r4 = await post(w2, "refresh");
  eq([r4.status, w2.db.conn?.status, w2.db.mails], [502, "connected", 0], "invalid_client → 502 · still connected · no mail");
  // 핑 401 → 강제 갱신 → 다시 → 그래도 401 → needs_reconnect
  const w3 = world(); connect(w3);
  w3.it.override.push((h) => h.url.includes("/companyinfo/") ? jres(401, { Fault: { Error: [{ Message: "message=AuthenticationFailed", code: "3200" }], type: "AuthenticationFault" } }, "tid-401") : null);
  const r5 = await post(w3, "ping");
  eq([r5.status, ciHits(w3).length, tokenHits(w3).length, w3.db.conn?.status, w3.db.mails], [409, 2, 1, "needs_reconnect", 1], "401 → refresh once → 401 again → needs_reconnect + mail");
  // 핑 401 → 갱신 뒤 200 이면 정상
  const w4 = world(); connect(w4);
  let first = true;
  w4.it.override.push((h) => { if (h.url.includes("/companyinfo/") && first) { first = false; return jres(401, {}, "tid-401a"); } return null; });
  const r6 = await body(await post(w4, "ping"));
  eq([r6.ok, r6.refreshed, ciHits(w4).length, w4.db.conn?.status], [true, true, 2, "connected"], "401 then ok after refresh");
  noLeak(w, "④"); noLeak(w3, "④-3");
});

Deno.test("⑤ 재시도 — 503 · 네트워크 끊김은 1 회만 다시(기록 한 줄 · 마지막 결과) · 400 Fault 는 다시 안 함 · Fault code · message · intuit_tid 가 기록에", async () => {
  const w = world();
  connect(w);
  let n = 0;
  w.it.override.push((h) => h.url.includes("/companyinfo/") && ++n === 1 ? jres(503, "<html>upstream</html>", "tid-503") : null);
  const r1 = await body(await post(w, "ping"));
  eq([r1.ok, ciHits(w).length, w.sleeps.at(-1)], [true, 2, 1000], "503 then ok: two fetches · one back-off");
  const l1 = w.logs.filter((l) => l.action === "companyinfo");
  eq([l1.length, l1[0].ok, l1[0].http_status, l1[0].intuit_tid], [1, true, 200, "tid-ci"], "one log row with the final result");
  w.it.override.length = 0; n = 0;
  w.it.override.push((h) => h.url.includes("/companyinfo/") && ++n === 1 ? new Error("connection reset") : null);
  const r2 = await body(await post(w, "ping"));
  eq([r2.ok, ciHits(w).length], [true, 4], "network error then ok");
  w.it.override.length = 0;
  w.it.override.push((h) => h.url.includes("/companyinfo/") ? jres(400, { Fault: { Error: [{ Message: "Invalid Reference Id", Detail: "Something went wrong", code: "6240" }], type: "ValidationFault" }, time: "2026-10-29" }, "tid-fault") : null);
  const r3 = await post(w, "ping");
  const b3 = await body(r3);
  eq([r3.status, ciHits(w).length, String(b3.error)], [502, 5, "QuickBooks CompanyInfo failed — HTTP 400 ValidationFault code 6240: Invalid Reference Id — Something went wrong"], "400 not retried · human text");
  const l3 = w.logs.at(-1)!;
  eq([l3.action, l3.ok, l3.http_status, l3.intuit_tid, l3.error, l3.by_staff, l3.env, l3.realm_id], ["companyinfo", false, 400, "tid-fault", "HTTP 400 ValidationFault code 6240: Invalid Reference Id — Something went wrong", STAFF, "sandbox", "9341458557490536"], "log row fields");
  w.it.override.length = 0;
  w.it.override.push((h) => h.url.includes("/companyinfo/") ? jres(503, {}, "tid-503b") : null);
  const r4 = await post(w, "ping");
  eq([r4.status, ciHits(w).length], [502, 7], "503 twice → 502 after one retry");
  noLeak(w, "⑤");
});

Deno.test("⑥ disconnect — revoke 성공 → delete · 기록(action disconnect · by_staff) · revoke 실패해도 delete + 「QuickBooks → Apps 에서도」 · admin 아니면 거부 · 연결 없어도 ok", async () => {
  const w = world();
  connect(w);
  const r1 = await body(await post(w, "disconnect"));
  eq([r1.ok, r1.revoked, r1.deleted, w.db.conn, revokeHits(w).length], [true, true, true, null, 1], "revoked + deleted: " + JSON.stringify(r1));
  const rv = revokeHits(w)[0];
  eq([rv.method, rv.auth?.startsWith("Basic "), JSON.parse(rv.body).token], ["POST", true, "RT-db-ZZSECRET-1"], "revoke: POST · Basic · {token: refresh}");
  const ld = w.logs.find((l) => l.action === "disconnect");
  eq([ld?.ok, ld?.by_staff, ld?.error], [true, STAFF, null], "disconnect logged");
  connect(w);
  w.it.override.push((h) => h.url === DISC.revocation_endpoint ? jres(500, { error: "server" }, "tid-r500") : null);
  const r2 = await body(await post(w, "disconnect"));
  eq([r2.ok, r2.revoked, r2.deleted, w.db.conn, String(r2.message).includes("QuickBooks → Apps")], [true, false, true, null, true], "revoke failed → still deleted · ask to remove in QuickBooks: " + JSON.stringify(r2));
  eq(w.logs.find((l) => l.action === "disconnect" && l.error)?.error?.startsWith("Intuit revoke failed"), true, "failure noted in log");
  w.it.override.length = 0;
  connect(w);
  eq((await post(w, "disconnect", "JWT-MGR")).status, 403, "manager refused");
  eq(w.db.conn?.status, "connected", "untouched");
  w.db.conn = null;
  const r3 = await body(await post(w, "disconnect"));
  eq([r3.ok, r3.revoked, r3.deleted, String(r3.message).startsWith("Nothing was connected")], [true, null, false, true], "no connection → ok");
  noLeak(w, "⑥");
});

Deno.test("⑦ env — QBO_ENV 없음 500(status 도) · 행 env ≠ QBO_ENV: refresh · ping 거부(409 사람 말) · status 는 env_mismatch true · disconnect 는 된다(행의 env 키로 revoke)", async () => {
  const w = world({ QBO_ENV: undefined });
  connect(w);
  for (const a of ["status", "refresh", "ping", "start", "disconnect"]) { const r = await post(w, a); eq([a, r.status, String((await body(r)).error).includes("QBO_ENV")], [a, 500, true], a + " → 500"); }
  eq((await post(w, "refresh", null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" })).status, 500, "cron path too");
  const w2 = world({ QBO_ENV: "production" });
  connect(w2);
  const r1 = await post(w2, "refresh");
  eq([r1.status, String((await body(r1)).error)], [409, "The QuickBooks connection on file is sandbox but this function runs as production (QBO_ENV) — disconnect it in Settings → QuickBooks, then connect again"], "refresh refused");
  eq((await post(w2, "ping")).status, 409, "ping refused");
  eq(tokenHits(w2).length + ciHits(w2).length, 0, "no Intuit call");
  const st = await body(await post(w2, "status"));
  eq([st.ok, st.env_mismatch, st.qbo_env, st.env], [true, true, "production", "sandbox"], "status shows the mismatch");
  const r2 = await body(await post(w2, "disconnect"));
  eq([r2.ok, r2.revoked, w2.db.conn, revokeHits(w2)[0].auth?.includes(btoa("client-id-sandbox:cs-ZZSECRET-sandbox-0123456789"))], [true, true, null, true], "disconnect works · revoke with the row's (sandbox) keys");
  const w3 = world({ QBO_CLIENT_SECRET_SANDBOX: undefined });
  const r3 = await post(w3, "start");
  eq([r3.status, String((await body(r3)).error).includes("QBO_CLIENT_SECRET_SANDBOX")], [500, true], "missing app secret → 500 naming the secret (value never)");
  noLeak(w, "⑦"); noLeak(w2, "⑦-2");
});

Deno.test("⑧ discovery — 24 h 캐시(두 start 에 fetch 한 번) · 지나면 다시 · 실패면 캐시(stale_served) · 캐시 없음 + 실패 → 500 · status 에 캐시 상태", async () => {
  const w = world();
  const disc = () => w.it.hits.filter((h) => h.url.includes("well-known")).length;
  await post(w, "start"); w.db.states.clear(); await post(w, "start");
  eq(disc(), 1, "one discovery fetch for two starts");
  const st1 = await body(await post(w, "status"));
  eq([(st1.discovery as Record<string, unknown>)?.fresh, (st1.discovery as Record<string, unknown>)?.stale_served, (st1.discovery as Record<string, unknown>)?.env], [true, false, "sandbox"], "status: cache fresh");
  w.clock.t += DISCOVERY_TTL_MS + 1;
  w.db.states.clear(); await post(w, "start");
  eq(disc(), 2, "expired → fetched again");
  w.clock.t += DISCOVERY_TTL_MS + 1;
  w.it.override.push((h) => h.url.includes("well-known") ? jres(503, {}, "tid-d503") : null);
  w.db.states.clear();
  const r = await body(await post(w, "start"));
  eq([r.ok, disc(), (await body(await post(w, "status"))).discovery], [true, 3, { env: "sandbox", cached_at: new Date(w.clock.t - DISCOVERY_TTL_MS - 1).toISOString(), fresh: false, stale_served: true }], "failure → stale cache served");
  const w2 = world();
  w2.it.override.push((h) => h.url.includes("well-known") ? jres(503, {}, "tid-d503") : null);
  const r2 = await post(w2, "start");
  eq([r2.status, String((await body(r2)).error).includes("discovery")], [500, true], "no cache + failure → 500");
  eq((await body(await post(w2, "status"))).discovery, null, "status: no cache");
  const w3 = world();
  w3.it.override.push((h) => h.url.includes("well-known") ? jres(200, { authorization_endpoint: "https://x", token_endpoint: "http://insecure" }) : null);
  eq((await post(w3, "start")).status, 500, "bad document → 500 (no hard-coded fallback)");
});

Deno.test("⑨ scrub — Intuit 오류 몸 · 네트워크 메시지 · DB 거부 글에 토큰 · secret · code 꼴이 있어도 응답 · 기록 · warn 에 0", async () => {
  const w = world();
  connect(w, { access_exp: w.clock.t + 60_000 });
  w.it.override.push((h) => h.url === DISC.token_endpoint ? jres(500, { error: "server_error", error_description: "echo access_token=AT-db-ZZSECRET-1 refresh_token=RT-db-ZZSECRET-1 code=CODE-ZZSECRET client_secret=cs-ZZSECRET-sandbox-0123456789 Bearer eyJaaaaaaaaaaaaaaaaa.bbbbbbbb.cccccccc" }, "tid-echo") : null);
  const r1 = await post(w, "refresh");
  const t1 = JSON.stringify(await body(r1));
  eq(r1.status, 502, "500 twice → 502");
  ok(!t1.includes("ZZSECRET") && !t1.includes("eyJ"), "response scrubbed: " + t1);
  ok(w.logs.every((l) => !(l.error ?? "").includes("ZZSECRET") && !(l.error ?? "").includes("eyJ")), "log scrubbed: " + JSON.stringify(w.logs));
  ok(w.logs.at(-1)!.error!.includes("[redacted]"), "redaction marker present");
  w.it.override.length = 0;
  w.it.override.push((h) => h.url === DISC.token_endpoint ? new Error("dial tcp: refresh_token=RT-db-ZZSECRET-1 leaked by a proxy") : null);
  w.clock.t += 31_000;                                                                              // 실패한 갱신의 임대(30 s)가 풀린 뒤
  const r2 = await post(w, "refresh");
  const t2 = JSON.stringify(await body(r2));
  eq([r2.status, t2.includes("unreachable"), t2.includes("ZZSECRET")], [502, true, false], "network message scrubbed: " + t2);
  w.it.override.length = 0;
  w.it.override.push((h) => h.url === DISC.token_endpoint ? jres(200, { access_token: "AT-new-ZZSECRET", refresh_token: "RT-new-ZZSECRET" }, "tid-noexp") : null);
  w.clock.t += 31_000;
  const r3 = await body(await post(w, "refresh"));
  eq([r3.ok, w.warns.at(-1)], [true, "qbo refresh: expires_in missing in the token response — assumed 3600 s"], "warn without values");
  const w2 = world(); connect(w2);
  const origSvc = w2.deps.rpcService;
  w2.deps.rpcService = async (fn, args) => { if (fn === "qbo_company_name_set") throw new RpcError(500, "boom refresh_token=RT-db-ZZSECRET-1 access_token=AT-db-ZZSECRET-1"); return await origSvc(fn, args); };
  const r4 = await post(w2, "ping");
  ok(!JSON.stringify(await body(r4)).includes("ZZSECRET"), "DB error text scrubbed in response");
  noLeak(w, "⑨"); noLeak(w2, "⑨-2");
});

Deno.test("⑩ cron 길 — 열쇠 없음(직원 길 401) · 틀림 401 · IMS_CRON_SECRET 미설정 500 · 맞으면 refresh(강제 · by_staff null) · cron 은 refresh 만 · OPTIONS · GET(아닌 길) 405", async () => {
  const w = world();
  connect(w);
  eq((await post(w, "refresh", null)).status, 401, "no key · no session → 401");
  eq((await post(w, "refresh", null, { "x-ims-cron-key": "wrong" })).status, 401, "wrong key → 401");
  eq((await post(w, "refresh", "JWT-MGR", { "x-ims-cron-key": "wrong" })).status, 401, "wrong key wins over a session (cron path chosen by the header)");
  const w0 = world({ IMS_CRON_SECRET: undefined }); connect(w0);
  const r0 = await post(w0, "refresh", null, { "x-ims-cron-key": "anything" });
  eq([r0.status, (await body(r0)).error], [500, "IMS_CRON_SECRET not configured - refusing (fail-closed)"], "unset → 500");
  const r1 = await body(await post(w, "refresh", null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" }));
  eq([r1.ok, r1.refreshed, r1.token_version, w.logs.at(-1)?.by_staff, w.logs.at(-1)?.action], [true, true, 2, null, "refresh"], "cron refresh forced · by_staff null");
  eq((await post(w, "ping", null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" })).status, 400, "cron may not ping");
  eq((await post(w, "disconnect", null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" })).status, 400, "cron may not disconnect");
  eq(w.db.conn?.status, "connected", "still connected");
  eq((await handle(new Request(SB + "/functions/v1/qbo", { method: "OPTIONS" }), w.deps)).status, 200, "OPTIONS");
  eq((await handle(new Request(SB + "/functions/v1/qbo", { method: "GET" }), w.deps)).status, 405, "GET without /callback → 405");
  eq((await post(w, "nope")).status, 400, "unknown action");
  noLeak(w, "⑩");
});

Deno.test("⑪ 회사 이름 저장 거부(qbo_company_name_set 이 던짐 · 1c 전의 REST 21000 꼴) — callback: 그래도 302 connected · call_log 에 company_name ok=false 줄(DB 글 · env · realm · by_staff) · last_error 무변 · ping: 422 사람 말 + 같은 꼴의 줄", async () => {
  const w = world();
  const orig = w.deps.rpcService;
  w.deps.rpcService = async (fn, args) => { if (fn === "qbo_company_name_set") throw new RpcError(400, "UPDATE requires a WHERE clause"); return await orig(fn, args); };
  const r = await startAndCallback(w);
  eq([r.res.status, await r.res.text(), r.res.headers.get("Location")], [302, "", callbackLocation(null)], "callback still connected");
  const row = w.logs.find((l) => l.action === "company_name");
  eq([row?.ok, row?.error, row?.env, row?.realm_id, row?.by_staff, row?.http_status, row?.intuit_tid], [false, "UPDATE requires a WHERE clause", "sandbox", "9341458557490536", STAFF, null, null], "company_name row: " + JSON.stringify(row));
  eq([w.db.conn?.status, w.db.conn?.company_name, w.db.conn?.last_error, w.db.lastErrors.length], ["connected", null, null, 0], "connection saved · name empty · last_error untouched");
  eq(w.logs.map((l) => l.action + ":" + l.ok).slice(-3), ["companyinfo:true", "company_name:false", "callback:true"], "order: Intuit ok → DB refused → callback ok");
  ok(w.warns.some((x) => x.includes("company name not saved") && x.includes("WHERE clause")), "warned too");
  const before = w.logs.length;
  const p = await post(w, "ping");
  const b = await body(p);
  eq([p.status, String(b.error)], [422, "QuickBooks answered, but the company name could not be saved — UPDATE requires a WHERE clause"], "ping 422 human text");
  const row2 = w.logs.slice(before).find((l) => l.action === "company_name");
  eq([row2?.ok, row2?.error, row2?.env, row2?.realm_id, row2?.by_staff], [false, "UPDATE requires a WHERE clause", "sandbox", "9341458557490536", STAFF], "ping leaves the same row shape");
  eq([w.db.conn?.last_error, w.db.lastErrors.length, w.db.conn?.status], [null, 0, "connected"], "ping: last_error untouched · still connected");
  w.deps.rpcService = orig;
  const p2 = await body(await post(w, "ping"));
  eq([p2.ok, p2.company_name, w.db.conn?.company_name], [true, "Sandbox Company CA 9bca", "Sandbox Company CA 9bca"], "ping retries and fills the name");
  noLeak(w, "⑪");
});

// ── qbo-read-1 — API 호스트로 나간 요청이 전부 GET(또는 POST …/query)인지 ──
const apiHits = (w: World) => w.it.hits.filter((h) => h.url.startsWith("https://sandbox-quickbooks.api.intuit.com/") || h.url.startsWith("https://quickbooks.api.intuit.com/"));
function readOnlyOnly(w: World, where: string) {
  for (const h of apiHits(w)) ok(h.method === "GET" || (h.method === "POST" && /\/query(\?|$)/.test(h.url)), where + ": non-read request reached the API host: " + h.method + " " + h.url);
}
const queryHits = (w: World) => w.it.hits.filter((h) => h.url.includes("/query?"));
const sentQuery = (h: Hit) => new URL(h.url).searchParams.get("query");

Deno.test("⑫ query — 순수 검사(select 만 · 세미콜론 · 허용 목록 · MAXRESULTS 기본 100 · 1000 초과 400 · Customer select * · 연락처 칸 · 리터럴 → ?) · 문(admin 만 · cron 400 · 세션 없음 401) · 응답 꼴(rows · count · totalCount · more · intuit_tid · SyncToken 그대로 · 들여쓰기 없음) · 기록 detail(손님 이름 없음 · 결과 행 없음) · 401 한 번 · needs_reconnect 409 · 429 재시도 0 · 5 MB 413 · API 호스트에 GET 만", async () => {
  // 순수
  const p1 = parseQuery("select * from Item");
  eq([p1.entity, p1.text, p1.maxResults, p1.startPosition, p1.isCount], ["Item", "select * from Item MAXRESULTS 100", 100, 1, false], "default MAXRESULTS appended");
  const p2 = parseQuery("SELECT Id, Name FROM item WHERE Type = 'Service' MAXRESULTS 1000 STARTPOSITION 1001");
  eq([p2.entity, p2.maxResults, p2.startPosition, p2.text.endsWith("STARTPOSITION 1001")], ["Item", 1000, 1001, true], "case-insensitive entity · explicit MAXRESULTS kept");
  const p3 = parseQuery("select count(*) from Customer");
  eq([p3.entity, p3.isCount, p3.text], ["Customer", true, "select count(*) from Customer"], "count(*) — no MAXRESULTS appended · allowed on Customer");
  const bad = (q: string, want: RegExp) => { try { parseQuery(q); throw new Error("accepted: " + q); } catch (e) { ok(e instanceof QboError && e.status === 400 && want.test(e.message), "expected 400 " + want + " for: " + q + " — got " + (e as Error).message); } };
  bad("update Item set Name = 'x'", /must start with select/);
  bad("select * from Item; delete", /semicolon/);
  bad("select * from Employee", /Employee is not readable/);
  bad("select * from Item MAXRESULTS 1001", /MAXRESULTS must be 1 … 1000/);
  bad("select * from Item MAXRESULTS 0", /MAXRESULTS must be/);
  bad("select * from Customer", /select \* is not allowed on Customer/);
  bad("select Id, DisplayName, PrimaryEmailAddr from Customer", /PrimaryEmailAddr is not readable on Customer/);
  bad("select Id, billaddr from Vendor", /BillAddr is not readable on Vendor/);
  bad("", /q is required/);
  bad("select * from Item STARTPOSITION 0", /STARTPOSITION must be 1 or more/);
  eq(MAXRESULTS_MAX, 1000, "cap");
  eq(queryForLog("select Id from Customer where DisplayName = 'Caribbean Island Food Market' and Email = 'a''b@x.ca' MAXRESULTS 100"), "select Id from Customer where DisplayName = ? and Email = ? MAXRESULTS 100", "literals → ? (doubled quote inside too)");
  // 문
  const w = world(); connect(w);
  eq((await postBody(w, { action: "query", q: "select * from Item" }, "JWT-MGR")).status, 403, "manager → 403");
  eq((await postBody(w, { action: "query", q: "select * from Item" }, null)).status, 401, "no session → 401");
  const rc = await postBody(w, { action: "query", q: "select * from Item" }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" });
  eq([rc.status, String((await body(rc)).error)], [400, "cron may only call: refresh"], "cron key → 400 (query is not a cron action)");
  eq(apiHits(w).length, 0, "no Intuit API call for refused requests");
  // 응답 꼴
  const r1 = await postBody(w, { action: "query", q: "select * from Item" });
  const t1 = await r1.text();
  ok(!t1.includes("\n"), "compact JSON (no indentation)");
  const b1 = JSON.parse(t1) as Record<string, unknown>;
  eq([r1.status, b1.ok, b1.entity, b1.count, b1.totalCount, b1.startPosition, b1.maxResults, b1.more, b1.intuit_tid], [200, true, "Item", 3, null, 1, 3, true, "tid-q"], "query response shape: " + t1);
  eq((b1.rows as Record<string, unknown>[])[1].SyncToken, "1", "SyncToken value untouched (rows are not scrubbed)");
  eq(sentQuery(queryHits(w)[0]!), "select * from Item MAXRESULTS 100", "MAXRESULTS 100 sent to Intuit");
  ok(queryHits(w)[0]!.url.includes("minorversion=75"), "minorversion on the query URL");
  const row1 = w.logs.at(-1)!;
  eq([row1.action, row1.ok, row1.http_status, row1.intuit_tid, row1.by_staff, row1.detail?.entity, row1.detail?.rows, row1.detail?.totalCount, row1.detail?.startPosition, row1.detail?.maxResults, row1.detail?.q], ["query", true, 200, "tid-q", STAFF, "Item", 3, null, 1, 3, "select * from Item MAXRESULTS 100"], "call_log row + detail: " + JSON.stringify(row1));
  ok(!JSON.stringify(row1).includes("SKU-"), "detail carries no result rows");
  // count(*) · 손님 이름
  const b2 = await body(await postBody(w, { action: "query", q: "select count(*) from Customer where DisplayName = 'Caribbean Island Food Market'" }));
  eq([b2.ok, b2.count, b2.totalCount, b2.more, (b2.rows as unknown[]).length], [true, 0, 1234, false, 0], "count(*) → totalCount only · more false");
  eq(w.logs.at(-1)!.detail?.q, "select count(*) from Customer where DisplayName = ?", "customer name replaced by ? in the log");
  ok(!JSON.stringify(w.logs).includes("Caribbean"), "customer name nowhere in call_log rows");
  const b3 = await body(await postBody(w, { action: "query", q: "select Id, DisplayName, ParentRef from Customer where DisplayName = 'Caribbean Island Food Market' MAXRESULTS 2 STARTPOSITION 3" }));
  eq([b3.ok, b3.count, b3.startPosition, b3.maxResults, b3.more, (b3.rows as Record<string, unknown>[])[0].Id], [true, 2, 3, 2, true, "3"], "paging values echoed from Intuit");
  ok(!JSON.stringify(w.logs).includes("Caribbean"), "still no customer name in the log after a row-returning query");
  // Intuit 400(QueryParserError) → 400 Fault 글
  w.it.override.push((h) => h.url.includes("/query?") && sentQuery(h)?.includes("Nope") ? jres(400, { Fault: { Error: [{ Message: "Error parsing query", Detail: "QueryParserError: Invalid content. Lexical error", code: "4000" }], type: "ValidationFault" } }, "tid-parse") : null);
  const r4 = await postBody(w, { action: "query", q: "select Nope from Item" });
  eq([r4.status, String((await body(r4)).error).startsWith("QuickBooks rejected the query — HTTP 400 ValidationFault code 4000")], [400, true], "Intuit 400 → 400 with the Fault text");
  // 401 한 번 → 강제 갱신 → 다시 · 그래도 401 → mark + 409
  let deny = 1;
  w.it.override.length = 0;
  w.it.override.push((h) => h.url.includes("/query?") && deny-- > 0 ? jres(401, { Fault: { Error: [{ Message: "message=AuthenticationFailed; errorCode=003200", code: "3200" }], type: "AUTHENTICATION" } }, "tid-401") : null);
  const v0 = w.db.conn!.token_version, tk0 = tokenHits(w).length;
  const b5 = await body(await postBody(w, { action: "query", q: "select * from Account" }));
  eq([b5.ok, b5.entity, w.db.conn!.token_version, tokenHits(w).length - tk0, w.logs.filter((l) => l.action === "query").slice(-2).map((l) => l.http_status)], [true, "Account", v0 + 1, 1, [401, 200]], "401 → one forced refresh → retried once");
  deny = 2;
  const r6 = await postBody(w, { action: "query", q: "select * from Account" });
  eq([r6.status, w.db.conn!.status, w.db.mails], [409, "needs_reconnect", 1], "401 twice → needs_reconnect (+ mail once)");
  eq((await postBody(w, { action: "query", q: "select * from Account" })).status, 409, "needs_reconnect → 409 without Intuit");
  // 429 · 5 MB
  const w2 = world(); connect(w2);
  w2.it.override.push((h) => h.url.includes("/query?") ? jres(429, { Fault: { Error: [{ Message: "ThrottleExceeded", code: "3001" }], type: "ValidationFault" } }, "tid-429") : null);
  const n0 = w2.it.hits.length;
  const r7 = await postBody(w2, { action: "query", q: "select * from Item" });
  eq([r7.status, w2.it.hits.length - n0, String((await body(r7)).error).includes("no automatic retry")], [429, 1, true], "429 → 429 · one hit · no retry");
  w2.it.override.length = 0;
  const big = "x".repeat(RESPONSE_MAX_BYTES + 10);
  w2.it.override.push((h) => h.url.includes("/query?") ? jres(200, { QueryResponse: { Item: [{ Id: "1", Name: big }] } }, "tid-big") : null);
  const r8 = await postBody(w2, { action: "query", q: "select * from Item" });
  const e8 = String((await body(r8)).error);
  eq([r8.status, e8.includes("lower MAXRESULTS")], [413, true], "over 5 MB → 413: " + e8.slice(0, 80));
  ok(w2.logs.at(-1)!.detail?.rows === 1 && Number(w2.logs.at(-1)!.detail?.bytes) > RESPONSE_MAX_BYTES, "log still records the oversized call");
  // 비밀 · 읽기 전용
  for (const x of [w, w2]) { readOnlyOnly(x, "⑫"); noLeak(x, "⑫"); }
  ok(!t1.includes("ZZSECRET") && !JSON.stringify(b3).includes("ZZSECRET"), "no secret in query responses");
  // 메서드 · 경로 검사 자체
  assertReadOnlyRequest("GET", "https://quickbooks.api.intuit.com/v3/company/1/item/9?minorversion=75");
  assertReadOnlyRequest("POST", "https://quickbooks.api.intuit.com/v3/company/1/query?minorversion=75");
  for (const [m, u] of [["POST", "https://quickbooks.api.intuit.com/v3/company/1/invoice?minorversion=75"], ["POST", "https://quickbooks.api.intuit.com/v3/company/1/invoice?operation=delete"], ["PUT", "https://quickbooks.api.intuit.com/v3/company/1/query"], ["DELETE", "https://quickbooks.api.intuit.com/v3/company/1/item/9"], ["PATCH", "https://quickbooks.api.intuit.com/v3/company/1/query"]]) {
    try { assertReadOnlyRequest(m, u); throw new Error("accepted " + m + " " + u); } catch (e) { ok(e instanceof QboError && e.status === 500 && /only reads/.test(e.message), "refused " + m + " " + u + ": " + (e as Error).message); }
  }
});

Deno.test("⑬ read — { entity, id } 단건 · Preferences · CompanyInfo 는 id 없이 · id 숫자만 400 · 허용 목록 밖 400 · Customer · Vendor 단건은 연락처 · 주소 칸 없이(이름 · ParentRef · SyncToken 은 그대로) · Item 은 전부 · Intuit 404 Fault → 502 · 기록 detail(entity · id · rows) · admin 만 · cron 400 · API 호스트에 GET 만 · 기존 ④ 의 ping 401 길은 withAuthRetry 로 같이 간다", async () => {
  const w = world(); connect(w);
  eq((await postBody(w, { action: "read", entity: "Customer", id: "123" }, "JWT-MGR")).status, 403, "manager → 403");
  eq((await postBody(w, { action: "read", entity: "Customer", id: "123" }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" })).status, 400, "cron → 400");
  const rb = await postBody(w, { action: "read", entity: "Employee", id: "1" });
  eq([rb.status, String((await body(rb)).error).startsWith("entity Employee is not readable here")], [400, true], "Employee → 400");
  const ri = await postBody(w, { action: "read", entity: "Customer", id: "abc" });
  eq([ri.status, String((await body(ri)).error)], [400, "id must be a number (the QuickBooks Id of the Customer)"], "non-numeric id → 400");
  eq((await postBody(w, { action: "read", entity: "Customer" })).status, 400, "missing id → 400");
  eq(apiHits(w).length, 0, "no Intuit call so far");
  // Customer — 연락처 · 주소 칸 없이
  const r1 = await postBody(w, { action: "read", entity: "customer", id: "123" });
  const t1 = await r1.text();
  const b1 = JSON.parse(t1) as Record<string, unknown>;
  const row = b1.row as Record<string, unknown>;
  eq([r1.status, b1.ok, b1.entity, b1.id, b1.intuit_tid, row.DisplayName, row.SyncToken, (row.ParentRef as Record<string, unknown>).value, row.Balance], [200, true, "Customer", "123", "tid-cust", "Caribbean Island Food Market", "7", "77", 515.1], "customer read: " + t1);
  eq(Object.keys(row).filter((k) => ["PrimaryEmailAddr", "PrimaryPhone", "Mobile", "Fax", "BillAddr", "ShipAddr", "WebAddr"].includes(k)), [], "contact · address fields removed");
  ok(!t1.includes("ZZPII") && !t1.includes("\n"), "no PII marker · compact JSON");
  ok(w.it.hits.at(-1)!.url.includes("/customer/123?") && w.it.hits.at(-1)!.url.includes("minorversion=75"), "path lower-case entity + id + minorversion");
  const l1 = w.logs.at(-1)!;
  eq([l1.action, l1.ok, l1.http_status, l1.intuit_tid, l1.by_staff, l1.detail?.entity, l1.detail?.id, l1.detail?.rows], ["read", true, 200, "tid-cust", STAFF, "Customer", "123", 1], "read log row: " + JSON.stringify(l1));
  ok(!JSON.stringify(l1).includes("Caribbean") && !JSON.stringify(l1).includes("ZZPII"), "log has no name · no PII");
  // Vendor — 같은 규칙 · Item — 전부 그대로
  const bv = await body(await postBody(w, { action: "read", entity: "Vendor", id: "5" }));
  eq([(bv.row as Record<string, unknown>).DisplayName, (bv.row as Record<string, unknown>).SyncToken, ((bv.row as Record<string, unknown>).CurrencyRef as Record<string, unknown>).value, "PrimaryEmailAddr" in (bv.row as object), "BillAddr" in (bv.row as object)], ["USD Supplier", "2", "USD", false, false], "vendor read stripped");
  const bi = await body(await postBody(w, { action: "read", entity: "Item", id: "9" }));
  eq([(bi.row as Record<string, unknown>).Name, (bi.row as Record<string, unknown>).Type, (bi.row as Record<string, unknown>).SyncToken, (bi.row as Record<string, unknown>).Sku], ["Freight", "Service", "3", null], "item read untouched");
  // Preferences · CompanyInfo — id 없이
  const bp = await body(await postBody(w, { action: "read", entity: "Preferences", id: "ignored-not-needed" }));
  eq([bp.ok, bp.entity, bp.id, ((bp.row as Record<string, unknown>).CurrencyPrefs as Record<string, unknown>).MultiCurrencyEnabled, bp.intuit_tid], [true, "Preferences", null, true, "tid-pref"], "preferences without id");
  ok(w.it.hits.at(-1)!.url.includes("/preferences?"), "preferences path");
  const bc = await body(await postBody(w, { action: "read", entity: "CompanyInfo" }));
  eq([bc.ok, bc.entity, (bc.row as Record<string, unknown>).CompanyName, (bc.row as Record<string, unknown>).SyncToken, w.db.conn!.company_name], [true, "CompanyInfo", "Sandbox Company CA 9bca", "4", "Sandbox Company CA 9bca"], "companyinfo read (name on the row untouched by read)");
  ok(w.it.hits.at(-1)!.url.includes("/companyinfo/9341458557490536?"), "companyinfo path = /companyinfo/<realm>");
  // Intuit 404 Fault → 502
  const r404 = await postBody(w, { action: "read", entity: "JournalEntry", id: "99999" });
  const e404 = String((await body(r404)).error);
  eq([r404.status, e404.startsWith("QuickBooks read failed — HTTP 404 ValidationFault code 610")], [502, true], "404 Fault → 502: " + e404);
  eq([w.logs.at(-1)!.ok, w.logs.at(-1)!.http_status, w.logs.at(-1)!.detail?.rows], [false, 404, 0], "failed read logged with rows 0");
  // stripPii 순수 · 다른 엔터티는 손대지 않는다
  eq(stripPii("Item", { Id: "1", BillAddr: { Line1: "kept" } }), { Id: "1", BillAddr: { Line1: "kept" } }, "stripPii only on Customer · Vendor");
  eq(stripPii("Vendor", { Id: "1", BillAddr: { Line1: "x" }, Mobile: {}, Name: "n" }), { Id: "1", Name: "n" }, "stripPii on Vendor");
  // ④ 의 길이 같은 함수를 지난다 — ping 401 한 번
  let deny = 1;
  w.it.override.push((h) => h.url.includes("/companyinfo/") && deny-- > 0 ? jres(401, { Fault: { Error: [{ Message: "AuthenticationFailed", code: "3200" }], type: "AUTHENTICATION" } }, "tid-401") : null);
  const v0 = w.db.conn!.token_version;
  const bp2 = await body(await post(w, "ping"));
  eq([bp2.ok, bp2.refreshed, w.db.conn!.token_version], [true, true, v0 + 1], "ping still refreshes once on 401 (shared withAuthRetry)");
  readOnlyOnly(w, "⑬"); noLeak(w, "⑬");
});

// ── qbo-sync-1b pull(2026-11-01 · 판정 934) — 가짜 DB 에 qbo_pull_begin · qbo_entity_upsert · qbo_pull_finish(20261101210000 의 글 그대로) ──
const pullHits = (w: World) => queryHits(w).filter((h) => /STARTPOSITION/.test(sentQuery(h) ?? ""));
Deno.test("⑭ pull — 순수(종류 7 · 칸에 연락처 없음 · TaxCode 만 where 없음 · Item 은 *(1c) · parseQuery 통과) · 문(admin 만 · cron 400 · 세션 없음 401 · 종류 밖 400 · start 0 400) · 쪽 둘(1000 → 다음 1001 · 2 → done · finish 한 번 · begin 한 번) · start 1 = 새 run · 끝난 뒤 start 2001 → 409 사람 말 · Customer 는 DisplayName · gone · 401 한 번 · 기록 detail(entity · rows · start · page · 행 없음) · API 호스트에 GET 만", async () => {
  // 순수
  eq(PULL_ENTITIES.length, 7, "seven pull entities");
  for (const e of PULL_ENTITIES) {
    const t = pullQueryText(e, 1);
    const p = parseQuery(t);
    eq([p.entity, p.maxResults, p.startPosition, t.endsWith("STARTPOSITION 1 MAXRESULTS 1000")], [e, 1000, 1, true], "pull query passes parseQuery: " + t);
    eq(/ where Active in \(true, false\)/.test(t), !PULL_NO_ACTIVE_FILTER.includes(e), "Active filter present except TaxCode: " + t);
    for (const f of PII_FIELDS) ok(!new RegExp("\\b" + f + "\\b", "i").test(PULL_FIELDS[e]), e + " fields carry no contact column " + f);
  }
  eq(pullQueryText("Customer", 2001), "select Id, DisplayName, FullyQualifiedName, ParentRef, Active, SyncToken from Customer where Active in (true, false) STARTPOSITION 2001 MAXRESULTS 1000", "customer query text");
  eq(pullQueryText("TaxCode", 1), "select Id, Name, Active, SyncToken from TaxCode STARTPOSITION 1 MAXRESULTS 1000", "taxcode query has no where");
  eq(pullQueryText("Item", 1), "select * from Item where Active in (true, false) STARTPOSITION 1 MAXRESULTS 1000", "item query is select * (1c — field-selected queries drop Sku)");
  eq(PULL_FIELDS.Customer.includes("*") || PULL_FIELDS.Vendor.includes("*"), false, "customer · vendor keep the field list (933)");
  eq(PULL_PAGE, 1000, "page size");
  // 문
  const w = world(); connect(w);
  eq((await postBody(w, { action: "pull", entity: "Item" }, "JWT-MGR")).status, 403, "manager → 403");
  eq((await postBody(w, { action: "pull", entity: "Item" }, null)).status, 401, "no session → 401");
  const rc = await postBody(w, { action: "pull", entity: "Item" }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" });
  eq([rc.status, String((await body(rc)).error)], [400, "cron may only call: refresh"], "cron key → 400 (pull is not a cron action)");
  const r400 = await postBody(w, { action: "pull", entity: "Invoice" });
  eq([r400.status, String((await body(r400)).error).startsWith("entity must be one of Account, TaxCode, Term, PaymentMethod, Customer, Vendor, Item (got Invoice)")], [400, true], "Invoice → 400");
  eq((await postBody(w, { action: "pull", entity: "TaxRate" })).status, 400, "TaxRate (readable by query, not pullable) → 400");
  eq((await postBody(w, { action: "pull", entity: "Item", start: 0 })).status, 400, "start 0 → 400");
  eq((await postBody(w, { action: "pull", entity: "Item", start: "abc" })).status, 400, "start abc → 400");
  eq([apiHits(w).length, w.db.pulls.size], [0, 0], "no Intuit call · no run for refused requests");
  // 쪽 둘 — 1 쪽 1000 행 · 2 쪽 2 행
  w.it.override.push((h) => {
    if (!h.url.includes("/query?")) return null;
    const q = sentQuery(h) ?? ""; if (!/from Item/.test(q)) return null;
    const start = Number((/STARTPOSITION (\d+)/.exec(q) ?? [])[1] ?? 1), n = start === 1 ? 1000 : 2;
    const rows = Array.from({ length: n }, (_, i) => ({ Id: String(start + i), Name: "Item " + (start + i), Sku: "SKU-" + (start + i), Active: i % 2 === 0, SyncToken: "0" }));
    return jres(200, { QueryResponse: { Item: rows, startPosition: start, maxResults: n }, time: "2026-11-01T12:00:00Z" }, "tid-pull");
  });
  const r1 = await postBody(w, { action: "pull", entity: "item" });
  const t1 = await r1.text(); ok(!t1.includes("\n"), "compact JSON");
  const b1 = JSON.parse(t1) as Record<string, unknown>;
  eq([r1.status, b1.ok, b1.entity, b1.start, b1.received_now, b1.received, b1.pages, b1.next_start, b1.done, b1.gone, b1.finished_at, b1.intuit_tid], [200, true, "Item", 1, 1000, 1000, 1, 1001, false, null, null, "tid-pull"], "page 1 response: " + t1);
  eq(sentQuery(pullHits(w)[0]!), "select * from Item where Active in (true, false) STARTPOSITION 1 MAXRESULTS 1000", "page 1 query sent to Intuit (select *)");
  eq(w.db.calls.filter((x) => x === "user:qbo_pull_begin").length, 1, "begin once (start 1)");
  eq([w.db.ents.get("Item")!.size, w.db.pulls.get("Item")!.finished_at, w.db.pulls.get("Item")!.next_start], [1000, null, 1001], "1000 rows upserted · run open · next_start 1001");
  const row1 = w.logs.at(-1)!;
  eq([row1.action, row1.ok, row1.http_status, row1.intuit_tid, row1.by_staff, row1.detail?.entity, row1.detail?.rows, row1.detail?.start, row1.detail?.page], ["pull", true, 200, "tid-pull", STAFF, "Item", 1000, 1, 1], "call_log row + detail: " + JSON.stringify(row1));
  ok(!JSON.stringify(row1).includes("SKU-") && !JSON.stringify(row1).includes("Item 1"), "detail carries no result rows");
  const b2 = await body(await postBody(w, { action: "pull", entity: "Item", start: 1001 }));
  eq([b2.ok, b2.start, b2.received_now, b2.received, b2.pages, b2.next_start, b2.done, b2.gone, typeof b2.finished_at], [true, 1001, 2, 1002, 2, null, true, 0, "string"], "page 2 → done · finish: " + JSON.stringify(b2));
  eq([w.db.calls.filter((x) => x === "user:qbo_pull_begin").length, w.db.calls.filter((x) => x === "user:qbo_pull_finish").length, w.db.ents.get("Item")!.size, w.db.pulls.get("Item")!.finished_at !== null], [1, 1, 1002, true], "begin still once · finish once · 1002 rows · run closed");
  eq(w.logs.at(-1)!.detail?.page, 2, "page number in the log");
  // 끝난 뒤 start 2001 → DB 거부 → 409 사람 말
  const r409 = await postBody(w, { action: "pull", entity: "Item", start: 2001 });
  eq([r409.status, String((await body(r409)).error)], [409, "No pull in progress for Item — call qbo_pull_begin first — start the pull again with start 1 (or omit start)"], "page after finish → 409");
  // start 1 다시 = 새 run · 전 run 의 행 중 안 온 것은 gone(시계를 밀어 fetched_at < started_at)
  w.clock.t += 1000;
  w.it.override.length = 0;                                                                        // 기본 가짜 = 3 행 → 한 쪽에 끝
  const b3 = await body(await postBody(w, { action: "pull", entity: "Item", start: 1 }));
  eq([b3.received_now, b3.received, b3.pages, b3.done, b3.gone], [3, 3, 1, true, 1002 - 3], "new run: 3 rows · 999 old rows gone (ids 1..3 refreshed)");
  eq(w.db.calls.filter((x) => x === "user:qbo_pull_begin").length, 2, "begin again on start 1");
  eq([w.db.ents.get("Item")!.get("1")!.sku, w.db.ents.get("Item")!.get("3")!.sku], ["SKU-1", "SKU-3"], "Sku stored from the select * rows (1c)");
  const bq = await body(await postBody(w, { action: "query", q: "select Id, Name, Sku from Item MAXRESULTS 3" }));
  ok((bq.rows as Record<string, unknown>[]).every((r) => r.Sku === undefined && r.sparse === true), "fake Intuit mirrors QuickBooks: a field-selected Item query returns no Sku (sparse) — the reason Item pulls select *");
  // Customer — DisplayName 이 이름 · 연락처 칸 없는 조회
  const bc = await body(await postBody(w, { action: "pull", entity: "Customer" }));
  const cq = sentQuery(pullHits(w).at(-1)!) ?? "";
  eq([bc.ok, bc.received, bc.done, cq.startsWith("select Id, DisplayName, FullyQualifiedName, ParentRef, Active, SyncToken from Customer where Active in (true, false)")], [true, 3, true, true], "customer pull: " + cq);
  for (const f of PII_FIELDS) ok(!cq.includes(f), "customer query names no contact column: " + f);
  eq([w.db.ents.get("Customer")!.get("1")!.name, w.db.ents.get("Customer")!.get("1")!.sku], ["Caribbean Island Food Market 1", null], "DisplayName stored as the name · no sku");
  ok(!JSON.stringify(w.logs).includes("Caribbean"), "customer names nowhere in call_log");
  // TaxCode — where 없이
  const bt = await body(await postBody(w, { action: "pull", entity: "TaxCode" }));
  eq([bt.ok, bt.done, / where /.test(sentQuery(pullHits(w).at(-1)!) ?? "")], [true, true, false], "taxcode pull without an Active filter");
  // 401 한 번 → 강제 갱신 → 다시(공용 withAuthRetry)
  let deny = 1;
  w.it.override.push((h) => h.url.includes("/query?") && deny-- > 0 ? jres(401, { Fault: { Error: [{ Message: "AuthenticationFailed", code: "3200" }], type: "AUTHENTICATION" } }, "tid-401") : null);
  const v0 = w.db.conn!.token_version;
  const bv = await body(await postBody(w, { action: "pull", entity: "Vendor" }));
  eq([bv.ok, bv.done, w.db.conn!.token_version], [true, true, v0 + 1], "pull refreshes once on 401 and retries");
  readOnlyOnly(w, "⑭"); noLeak(w, "⑭");
});

Deno.test("⑮ 문 둘(qbo-sync-2a 판정 945) — ACTIONS = status + ADMIN + KEY · pull 은 qbo_key_gate(열쇠 qbo 인 manager 통과 · by_staff 그 사람 · qbo_admin_gate 안 부름) · 열쇠 없는 admin 은 pull 403(admin 도 켜야 한다) · qbo:read 는 pull 403 · 열쇠 있는 manager 라도 ADMIN_ACTIONS 는 403 · status 의 caller_qbo · cron 은 그대로 refresh 만", async () => {
  eq([...ACTIONS].sort(), ["status", ...ADMIN_ACTIONS, ...KEY_ACTIONS].sort(), "every action is status, admin or key — none unassigned");
  const w = world(); connect(w);
  w.db.keys["JWT-MGR"] = "qbo";
  const r1 = await postBody(w, { action: "pull", entity: "TaxCode" }, "JWT-MGR");
  const n0 = w.db.calls.length;
  eq([r1.status, (await body(r1)).ok, w.logs.at(-1)!.by_staff], [200, true, STAFF_MGR], "manager with the qbo key pulls · call_log by_staff is that manager");
  ok(w.db.calls.includes("user:qbo_key_gate") && !w.db.calls.includes("user:qbo_admin_gate"), "pull went through qbo_key_gate only: " + w.db.calls.join(","));
  for (const a of ADMIN_ACTIONS) {
    const r = await postBody(w, { action: a, ...(a === "query" ? { q: "select * from Item" } : a === "read" ? { entity: "CompanyInfo" } : {}) }, "JWT-MGR");
    eq([a, r.status, String((await body(r)).error)], [a, 403, "Only an admin can connect, disconnect or reconnect QuickBooks — nothing was changed"], "key holder is not an admin: " + a);
  }
  eq(w.db.calls.slice(n0).filter((x) => x === "user:qbo_admin_gate").length, ADMIN_ACTIONS.length, "each admin action asked qbo_admin_gate once");
  eq([apiHits(w).filter((h) => !h.url.includes("/query?")).length], [0], "no Intuit call for the refused admin actions");
  w.db.keys["JWT-ADMIN"] = null;                                                                   // 945: admin 도 켜야 한다
  const r2 = await postBody(w, { action: "pull", entity: "TaxCode" });
  eq([r2.status, String((await body(r2)).error)], [403, "Your account does not have the 'qbo' (write) permission — ask an admin to switch it on in Staff — nothing was changed"], "admin without the key cannot pull");
  eq((await postBody(w, { action: "ping" })).status, 200, "…but still pings (admin action)");
  w.db.keys["JWT-MGR"] = "qbo:read";
  const r3 = await postBody(w, { action: "pull", entity: "TaxCode" }, "JWT-MGR");
  eq([r3.status, String((await body(r3)).error).includes("'qbo' (write)")], [403, true], "qbo:read cannot pull (write)");
  const st = await body(await post(w, "status", "JWT-MGR"));
  eq([st.caller_is_admin, st.caller_qbo], [false, "read"], "status carries caller_qbo from the DB row");
  w.db.keys["JWT-ADMIN"] = "qbo";
  eq((await body(await post(w, "status"))).caller_qbo, "write", "admin with the key → write");
  const rc = await postBody(w, { action: "pull", entity: "TaxCode" }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" });
  eq([rc.status, String((await body(rc)).error)], [400, "cron may only call: refresh"], "cron path unchanged");
  eq((await postBody(w, { action: "pull", entity: "TaxCode" }, "JWT-BAD")).status, 401, "unknown session → 401");
  readOnlyOnly(w, "⑮"); noLeak(w, "⑮");
});
