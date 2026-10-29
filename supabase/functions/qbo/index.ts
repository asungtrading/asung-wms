// ============================================================
// ASUNG IMS — Edge Function: qbo (qbo-1b · 2026-10-29 · 판정 617 · 867 ~ 872 · DB qbo-1a 20261029160000 · qbo-1b 20261029190000 · 흐름 · 순수 함수 ../_shared/qbo.ts)
//   QuickBooks Online 연결 — 연결(start) · callback · 상태 · 갱신 · 핑(CompanyInfo) · 끊기(revoke) · cron 갱신. 싱크는 뒤 차수.
//   ⚠️ 이 프로젝트(Asung-IMS · fazgmyvzzhqybtvtktyg)가 11-01 부터 그대로 운영(617) — db_role 가드는 쓰지 않는다 · 환경은 비밀값 QBO_ENV(sandbox | production · 없으면 500) 와 연결 행의 env 가 같아야 한다
//   문(config.toml verify_jwt = false — Intuit 이 브라우저를 JWT 없이 GET 으로 보낸다 · freightcom 과 같은 까닭):
//     GET  /functions/v1/qbo/callback?code&state&realmId | ?error=…  → 언제나 302 · 본문 없음 · Location = https://ims.asung.ca/settings.html?t=qbo&qbo=connected | &qbo=error&why=<denied|state|exchange|realm|save|env>(코드 고정 · 요청 값 안 섞음)
//        순서: error= 면 denied → state 의 sha256 으로 qbo_state_consume(service · 10 분 · 한 번) → env 대조 → code 교환(Basic · urlencoded · redirect_uri 같은 값) → realmId 숫자 → qbo_connection_save(realm 고정 · 다른 회사면 받은 토큰 revoke · why=realm) → CompanyInfo → qbo_company_name_set → 302
//     POST JSON {action} + Authorization: Bearer <직원 세션 JWT> — status(로그인한 직원 누구나 · qbo_status()) · start · disconnect · refresh · ping(admin · qbo_admin_gate() 가 DB 에서 본다 · 870)
//     POST JSON {action:"refresh"} + x-ims-cron-key == secret IMS_CRON_SECRET(미설정 500 fail-closed · drive 꼴) — cron ims-qbo-refresh(하루 한 번 · 강제 갱신)
//   갱신: 부를 때 접근 토큰이 5 분 안에 끝나면 먼저 · qbo_refresh_claim(임대 30 s) → Intuit refresh → qbo_refresh_save(판 번호 · 응답의 새 refresh_token 을 매번 저장) · 임대 못 받으면 1.5 s 씩 최대 15 s 기다렸다 새 판 읽기
//          invalid_grant → qbo_mark_needs_reconnect(다시 시도 안 함 · DB 가 끊김 메일 869 를 바뀌는 순간 한 번) · 네트워크 · 5xx 만 1 회 재시도 · API 401 은 강제 갱신 한 번 뒤 다시(그래도 401 이면 needs_reconnect)
//   끊기: revoke(refresh_token · Basic) → 실패해도 qbo_connection_delete() → call_log(action disconnect · by_staff) · 실패했으면 응답 글에 QuickBooks → Apps 에서도 끊어 달라
//   기록: Intuit 호출 한 번 = qbo_call_log 한 줄(action · env · realm_id · ok · http_status · intuit_tid · error 400 자 · by_staff · ms) · 90 일 지난 줄은 호출 끝에 지운다 · 토큰 끝점 · revoke 의 요청 몸은 기록하지 않는다
//   ⚠️ 비밀: QBO_ENV · QBO_CLIENT_ID_<SANDBOX|PRODUCTION> · QBO_CLIENT_SECRET_<…> · IMS_CRON_SECRET(기존) — 값은 응답 · 기록 · 오류 · console 어디에도 안 남는다(scrub)
//   배포: supabase functions deploy qbo --project-ref fazgmyvzzhqybtvtktyg
// ============================================================
import { CALL_LOG_KEEP_DAYS, DiscoveryCache, handle, RpcError, scrub, type Deps, type LogRow } from "../_shared/qbo.ts";

const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON = () => Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const INTUIT_TIMEOUT_MS = 20_000;
const discovery = new DiscoveryCache();                                                            // 함수 인스턴스 메모리 · 24 h
const envSecrets = (): string[] => ["QBO_CLIENT_SECRET_SANDBOX", "QBO_CLIENT_SECRET_PRODUCTION", "SUPABASE_SERVICE_ROLE_KEY"].map((k) => Deno.env.get(k) ?? "").filter((v) => v.length >= 8);

async function rpc(fn: string, args: Record<string, unknown>, jwt: string | null): Promise<unknown> {
  const headers: Record<string, string> = jwt ? { apikey: ANON(), Authorization: "Bearer " + jwt, "Content-Type": "application/json" } : { apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/json" };
  const r = await fetch(SB_URL() + "/rest/v1/rpc/" + fn, { method: "POST", headers, body: JSON.stringify(args) });
  const text = await r.text();
  if (!r.ok) {
    let msg = text.slice(0, 400);
    try { const j = JSON.parse(text); msg = String(j.message ?? j.error ?? msg); } catch { /* 글자 그대로 */ }
    throw new RpcError(r.status, scrub(msg, envSecrets()));
  }
  return text ? JSON.parse(text) : null;
}
async function sbWrite(method: string, path: string, body?: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { method, headers: { apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/json", Prefer: "return=minimal" }, body: body === undefined ? undefined : JSON.stringify(body) });
  if (!r.ok) throw new Error("sb " + method + " " + path.split("?")[0] + " " + r.status + ": " + (await r.text()).slice(0, 300));
}
async function recordCall(row: LogRow): Promise<void> {                                            // fc_call_log 꼴 · 던지지 않는다
  try {
    await sbWrite("POST", "qbo_call_log", { ...row, error: row.error ? scrub(row.error, envSecrets()).slice(0, 400) : null });
    try { await sbWrite("DELETE", "qbo_call_log?called_at=lt." + encodeURIComponent(new Date(Date.now() - CALL_LOG_KEEP_DAYS * 86_400_000).toISOString())); } catch (e) { console.warn("qbo_call_log purge failed:", scrub(String(e), envSecrets()).slice(0, 200)); }
  } catch (e) { console.warn("qbo recordCall failed:", scrub(String(e), envSecrets()).slice(0, 300)); }
}

const deps: Deps = {
  env: (name) => Deno.env.get(name),
  fetch: (url, init) => fetch(url, { ...init, signal: AbortSignal.timeout(INTUIT_TIMEOUT_MS) }),
  rpcUser: (fn, args, jwt) => rpc(fn, args, jwt),
  rpcService: (fn, args) => rpc(fn, args, null),
  log: recordCall,
  now: () => Date.now(),
  sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
  randomBytes: (n) => crypto.getRandomValues(new Uint8Array(n)),
  uuid: () => crypto.randomUUID(),
  warn: (msg) => console.warn(scrub(msg, envSecrets()).slice(0, 500)),
  discovery,
};
Deno.serve((req) => handle(req, deps));
