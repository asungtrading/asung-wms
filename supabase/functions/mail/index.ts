// mail — IMS 메일 일꾼(mail-2b · 2026-10-16 · 판정 493 · 502 · 510 · 511 · 514) — ⚠️ 테스트 프로젝트(fazgmyvzzhqybtvtktyg)에 먼저 · 운영은 컷오버 때
//   문: x-ims-cron-key == secret IMS_CRON_SECRET(미설정 500 fail-closed · shopify · ims-product-images 와 같은 꼴) · config.toml [functions.mail] verify_jwt = false
//   POST {"action": "drain"}  mail_claim → 안전(프로젝트 ref ↔ db_role · 시험 DB 는 mail_redirect_to 로 돌려 보내기) → 그리기 → Gmail users.messages.send → mail_mark(id, attempt, …)
//        {"action": "chat"}   mail_run_chat_due → 회차마다 요약 글 → Chat 웹훅 → mail_run_chat_mark
//        {"action": "render", "id": "<mail id>"}  보내지 않고 그린 결과만(같은 안전 검사의 받는 이 · 제목)
//   비밀: GMAIL_OAUTH_CLIENT_ID · GMAIL_OAUTH_CLIENT_SECRET · GMAIL_REFRESH_TOKEN_IMS(tools/gmail-oauth-ims.sh 가 넣는다) · IMS_CHAT_WEBHOOK_BACKORDER · IMS_CRON_SECRET
//   ⚠️ 비밀 값은 로그 · 응답 · DB 어디에도 남기지 않는다(오류는 Google 의 error 코드 · 설명만)
import { chatText, drain, projectRef, render, safety, addressFor, type ChatMail, type ChatRun, type ClaimedMail, type MailConfig, type Outcome } from "../_shared/mail.ts";

const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const sbHeaders = { get value(): HeadersInit { return { apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/json" }; } };
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const BATCH = 5, BUDGET_MS = 40_000, SEND_TIMEOUT_MS = 20_000, CHAT_GAP_MS = 1_100;   // Chat 웹훅은 스페이스마다 초당 1 건(문서)

async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { headers: sbHeaders.value });
  if (!r.ok) throw new Error(`GET ${path.split("?")[0]} ${r.status}: ${(await r.text()).slice(0, 200)}`);
  return await r.json();
}
async function sbRpc(fn: string, args: Record<string, unknown>): Promise<any> {
  const r = await fetch(SB_URL() + "/rest/v1/rpc/" + fn, { method: "POST", headers: sbHeaders.value, body: JSON.stringify(args) });
  if (!r.ok) throw new Error(`rpc/${fn} ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return await r.json();
}
async function readConfig(): Promise<MailConfig> {
  const rows = await sbGet("inv_config?select=key,value&key=in.(db_role,mail_enabled,mail_redirect_to)");
  const v = (k: string) => rows.find((r) => r.key === k)?.value ?? null;
  return { enabled: v("mail_enabled") === "on", redirect_to: (v("mail_redirect_to") ?? "") || null, db_role: v("db_role") };
}

// ── 열쇠 — 계정마다 함수 하나(판정 380 의 직원 본인 주소가 올 자리 · mail-0 E3) · 한 번 부르는 동안 재사용 ──
const tokenCache = new Map<string, { token: string; until: number }>();
export async function gmailToken(account: "ims"): Promise<string> {
  const c = tokenCache.get(account);
  if (c && c.until > Date.now() + 60_000) return c.token;
  const id = Deno.env.get("GMAIL_OAUTH_CLIENT_ID") ?? "", secret = Deno.env.get("GMAIL_OAUTH_CLIENT_SECRET") ?? "";
  const refresh = Deno.env.get(account === "ims" ? "GMAIL_REFRESH_TOKEN_IMS" : "") ?? "";
  if (!id || !secret || !refresh) throw new Error("Gmail OAuth secrets are not set (GMAIL_OAUTH_CLIENT_ID · GMAIL_OAUTH_CLIENT_SECRET · GMAIL_REFRESH_TOKEN_IMS)");
  const r = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: id, client_secret: secret, refresh_token: refresh, grant_type: "refresh_token" }), signal: AbortSignal.timeout(15_000) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) throw new Error(`token endpoint ${r.status} ${j.error ?? ""}${j.error_description ? ": " + j.error_description : ""}${j.error === "invalid_grant" ? " — run tools/gmail-oauth-ims.sh again" : ""}`);
  tokenCache.set(account, { token: j.access_token, until: Date.now() + Number(j.expires_in ?? 3600) * 1000 });
  return j.access_token;
}
async function gmailSend(token: string, raw: string): Promise<Outcome> {
  try {
    const r = await fetch("https://gmail.googleapis.com/gmail/v1/users/me/messages/send", { method: "POST", headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ raw }), signal: AbortSignal.timeout(SEND_TIMEOUT_MS) });
    return { kind: "http", status: r.status, body: await r.text() };
  } catch (e) {
    const name = (e as Error)?.name ?? "";
    return name === "TimeoutError" || name === "AbortError" ? { kind: "timeout" } : { kind: "network", message: String((e as Error)?.message ?? e).slice(0, 200) };
  }
}

async function doDrain(): Promise<Response> {
  const out = await drain({
    ref: projectRef(SB_URL()),
    readConfig,
    claim: async (n) => { const c = await sbRpc("mail_claim", { p_limit: n }); return { enabled: !!c.enabled, redirect_to: c.redirect_to ?? null, db_role: c.db_role ?? null, mails: (c.mails ?? []) as ClaimedMail[] }; },
    mark: async (id, attempt, m, rendered) => { await sbRpc("mail_mark", { p_id: id, p_attempt: attempt, p_result: m.result, p_provider_message_id: m.provider_message_id, p_error: m.error, p_rendered: rendered }); },
    token: () => gmailToken("ims"),
    send: gmailSend,
    now: () => Date.now(),
    log: (msg) => console.error(msg),
  }, { batch: BATCH, budgetMs: BUDGET_MS, boundary: () => "ims-" + crypto.randomUUID() });
  return json(out.ok ? 200 : 500, out);
}

async function doChat(): Promise<Response> {
  const hook = Deno.env.get("IMS_CHAT_WEBHOOK_BACKORDER") ?? "";
  if (!hook) return json(500, { ok: false, error: "IMS_CHAT_WEBHOOK_BACKORDER not configured - nothing posted (runs stay due)" });
  const cfg = await readConfig();
  const test = projectRef(SB_URL()) !== "gftpcnkxbdjzzfvzwcfl" || cfg.db_role === "test";
  const due = (await sbRpc("mail_run_chat_due", {})) as (ChatRun & { run_id: string })[];
  const results: unknown[] = [];
  for (const run of due) {
    const rows = await sbGet(`mail_outbox?select=status,payload&run_id=eq.${run.run_id}&order=created_at`);
    const mails: ChatMail[] = rows.map((r) => ({ status: r.status, customer_name: r.payload?.customer_name ?? null, lines: (r.payload?.lines ?? []).map((l: any) => ({ so_number: l.so_number, sku: l.sku })) }));
    const runRow = (await sbGet(`mail_run?select=no_email&id=eq.${run.run_id}`))[0];
    const skippedIds: { customer_id: string; reason: string }[] = runRow?.no_email ?? [];
    const names = skippedIds.length ? await sbGet(`customer?select=id,name&id=in.(${skippedIds.map((s) => s.customer_id).join(",")})`) : [];
    const skippedNames = skippedIds.map((s) => ({ name: names.find((n) => n.id === s.customer_id)?.name ?? "", reason: s.reason }));
    const text = chatText(run, mails, skippedNames, test);
    let ok = false, err: string | null = null;
    try {
      const r = await fetch(hook, { method: "POST", headers: { "Content-Type": "application/json; charset=UTF-8" }, body: JSON.stringify({ text }), signal: AbortSignal.timeout(15_000) });
      ok = r.ok; if (!ok) err = `chat webhook ${r.status}`;                                                // 웹훅 주소(비밀)는 적지 않는다
    } catch (e) { err = `chat webhook ${(e as Error)?.name ?? "error"}`; }
    results.push(await sbRpc("mail_run_chat_mark", { p_run_id: run.run_id, p_ok: ok, p_error: err }));
    await new Promise((res) => setTimeout(res, CHAT_GAP_MS));
  }
  return json(200, { ok: true, posted: results });
}

async function doRender(id: string): Promise<Response> {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return json(400, { ok: false, error: "id must be a mail id" });
  const row = (await sbGet(`mail_outbox?select=id,kind,status,from_address,from_name,reply_to,to_address,payload,attempts&id=eq.${id}`))[0];
  if (!row) return json(404, { ok: false, error: "mail not found" });
  const s = safety(await readConfig(), projectRef(SB_URL()));
  const r = render(row.kind, row.payload);
  const mail = { ...row, attempt: row.attempts } as ClaimedMail;
  const a = s.ok ? addressFor(mail, s, r.subject) : { to: row.to_address, original_to: null, subject: r.subject };
  return json(200, { ok: true, status: row.status, would_send: s.ok, safety: s.ok ? (s.test ? "test-redirect" : (s.redirect ? "redirect" : "live")) : s.reason,
    from: { name: row.from_name, address: row.from_address }, reply_to: row.reply_to, to: a.to, original_to: a.original_to, subject: a.subject, body_text: r.body_text, body_html: r.body_html });
}

function sameSecret(a: string, b: string): boolean {                                              // 길이 말고는 시간이 같다(Edge Runtime 의 crypto.subtle.timingSafeEqual 유무에 기대지 않는다)
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return json(405, { ok: false, error: "POST only" });
    const key = req.headers.get("x-ims-cron-key");
    const secret = Deno.env.get("IMS_CRON_SECRET") ?? "";
    if (!secret) return json(500, { ok: false, error: "IMS_CRON_SECRET not configured - refusing (fail-closed)" });
    if (key === null || !sameSecret(key, secret)) return json(401, { ok: false, error: "unauthorized" });
    const body = await req.json().catch(() => ({}));
    if (body.action === "drain") return await doDrain();
    if (body.action === "chat") return await doChat();
    if (body.action === "render") return await doRender(String(body.id ?? ""));
    return json(400, { ok: false, error: "action must be drain, chat or render" });
  } catch (e) {
    console.error("mail failed:", String((e as Error)?.message ?? e).slice(0, 500));
    return json(500, { ok: false, error: String((e as Error)?.message ?? e).slice(0, 300) });
  }
});
