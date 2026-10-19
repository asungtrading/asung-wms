// mail — IMS 메일 일꾼(mail-2b · 2026-10-16 · 판정 493 · 502 · 510 · 511 · 514) — ⚠️ 테스트 프로젝트(fazgmyvzzhqybtvtktyg)에 먼저 · 운영은 컷오버 때
//   문: x-ims-cron-key == secret IMS_CRON_SECRET(미설정 500 fail-closed · shopify · ims-product-images 와 같은 꼴) · config.toml [functions.mail] verify_jwt = false
//   POST {"action": "drain"}  mail_claim → 안전(프로젝트 ref ↔ db_role · 시험 DB 는 mail_redirect_to 로 돌려 보내기) → 그리기 → Gmail users.messages.send → mail_mark(id, attempt, …)
//                            doc-3b: kind doc_* 는 줄의 제목 · 본문 + attachments 의 PDF(Storage documents · sha256 대조) → multipart/mixed
//        {"action": "pdf"}    doc-3b: doc_mail_pdf_claim → EF doc(render · reason send · x-ims-cron-key) → doc_mail_attach(→ queued) · 실패는 doc_mail_pdf_failed — 보내지 않는다(그 뒤는 drain)
//        {"action": "chat"}   mail_run_error_chat_due → 회차 실패 한 줄(판정 518 · mail-4c) → mail_run_error_chat_mark · mail_run_chat_due → 회차마다 요약 글 → Chat 웹훅 → mail_run_chat_mark
//        {"action": "render", "id": "<mail id>"}  보내지 않고 그린 결과만(같은 안전 검사의 받는 이 · 제목 · doc_* 는 첨부 목록도)
//   비밀: GMAIL_OAUTH_CLIENT_ID · GMAIL_OAUTH_CLIENT_SECRET · GMAIL_REFRESH_TOKEN_IMS(tools/gmail-oauth-ims.sh 가 넣는다) · IMS_CHAT_WEBHOOK_BACKORDER · IMS_CRON_SECRET(EF doc 을 부를 때도 같은 열쇠)
//   ⚠️ 비밀 값은 로그 · 응답 · DB 어디에도 남기지 않는다(오류는 Google 의 error 코드 · 설명만)
import { chatText, drain, errorChatText, isDocKind, pdfStep, projectRef, render, safety, addressFor, type Attachment, type AttachmentRead, type ChatError, type ChatMail, type ChatRun, type ClaimedMail, type DocBody, type MailConfig, type Outcome, type PdfJob, type PdfRender } from "../_shared/mail.ts";

const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const sbHeaders = { get value(): HeadersInit { return { apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/json" }; } };
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const BATCH = 5, BUDGET_MS = 40_000, SEND_TIMEOUT_MS = 20_000, CHAT_GAP_MS = 1_100;   // Chat 웹훅은 스페이스마다 초당 1 건(문서)
const PDF_BATCH = 3, PDF_BUDGET_MS = 40_000, DOC_TIMEOUT_MS = 70_000, STORAGE_TIMEOUT_MS = 30_000;   // doc-3b: EF doc 은 장마다 Gotenberg 58 s 한도(첫 호출 4 s 실측) — 한 번에 셋 · 예산 40 s · 집은 줄은 10 분 잠김(doc_mail_pdf_claim)

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

// ── doc-3b: 문서 메일 재료 — 본문 · 첨부 목록은 줄에서(service_role 읽기 · mail_claim 무접촉) · PDF 바이트는 Storage documents/<path> ──
async function loadDoc(id: string): Promise<DocBody> {
  const row = (await sbGet(`mail_outbox?select=body_text,attachments&id=eq.${id}`))[0];
  return { body_text: row?.body_text ?? null, attachments: (Array.isArray(row?.attachments) ? row.attachments : []) as Attachment[] };
}
async function readAttachment(a: Attachment): Promise<AttachmentRead> {
  try {
    const r = await fetch(SB_URL() + "/storage/v1/object/documents/" + String(a.path).replace(/^\/+/, ""), { headers: { apikey: SERVICE(), Authorization: "Bearer " + SERVICE() }, signal: AbortSignal.timeout(STORAGE_TIMEOUT_MS) });
    if (r.ok) return { ok: true, bytes: new Uint8Array(await r.arrayBuffer()) };
    const text = (await r.text()).slice(0, 200);
    return { ok: false, retry: r.status >= 500 || r.status === 429, error: `storage ${r.status}: ${text}` };   // 404 · 400 = 파일이 없다(failed) · 5xx · 429 = 다음에
  } catch (e) {
    const name = (e as Error)?.name ?? "";
    return { ok: false, retry: true, error: name === "TimeoutError" || name === "AbortError" ? "storage timeout" : `storage: ${String((e as Error)?.message ?? e).slice(0, 200)}` };
  }
}
// EF doc 을 service 길로 부른다(같은 IMS_CRON_SECRET) — render · reason send · files[0].doc_file_id
async function docRender(kind: string, ref: unknown): Promise<PdfRender> {
  try {
    const r = await fetch(SB_URL() + "/functions/v1/doc", { method: "POST", headers: { "Content-Type": "application/json", "x-ims-cron-key": Deno.env.get("IMS_CRON_SECRET") ?? "" },
      body: JSON.stringify({ action: "render", kind, ref, reason: "send" }), signal: AbortSignal.timeout(DOC_TIMEOUT_MS) });
    const text = await r.text();
    let j: any = {}; try { j = JSON.parse(text); } catch { /* plain */ }
    if (!r.ok || !j?.ok) return { ok: false, error: `doc ${r.status}: ${String(j?.error ?? text).slice(0, 300)}` };
    const id = j?.files?.[0]?.doc_file_id;
    if (!id || j.files.length !== 1) return { ok: false, error: `doc answered with ${j?.files?.length ?? 0} files — one was expected` };
    return { ok: true, doc_file_id: String(id) };
  } catch (e) {
    const name = (e as Error)?.name ?? "";
    return { ok: false, error: name === "TimeoutError" || name === "AbortError" ? `doc did not answer in ${DOC_TIMEOUT_MS / 1000} s (Gotenberg may be waking up)` : `doc: ${String((e as Error)?.message ?? e).slice(0, 200)}` };
  }
}
async function doPdf(): Promise<Response> {
  const out = await pdfStep({
    readConfig,
    claim: async (n) => ((await sbRpc("doc_mail_pdf_claim", { p_limit: n })) ?? []) as PdfJob[],
    render: docRender,
    attach: async (id, docFileId) => { await sbRpc("doc_mail_attach", { p_outbox_id: id, p_doc_file_id: docFileId }); },
    failed: async (id, error) => { await sbRpc("doc_mail_pdf_failed", { p_outbox_id: id, p_error: error }); },
    now: () => Date.now(),
    log: (msg) => console.error(msg),
  }, { batch: PDF_BATCH, budgetMs: PDF_BUDGET_MS });
  return json(out.ok ? 200 : 500, out);
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
    loadDoc,
    readAttachment,
  }, { batch: BATCH, budgetMs: BUDGET_MS, boundary: () => "ims-" + crypto.randomUUID() });
  return json(out.ok ? 200 : 500, out);
}

async function postChat(hook: string, text: string): Promise<{ ok: boolean; err: string | null }> {
  try {
    const r = await fetch(hook, { method: "POST", headers: { "Content-Type": "application/json; charset=UTF-8" }, body: JSON.stringify({ text }), signal: AbortSignal.timeout(15_000) });
    return r.ok ? { ok: true, err: null } : { ok: false, err: `chat webhook ${r.status}` };                // 웹훅 주소(비밀)는 적지 않는다
  } catch (e) { return { ok: false, err: `chat webhook ${(e as Error)?.name ?? "error"}` }; }
}

async function doChat(): Promise<Response> {
  const hook = Deno.env.get("IMS_CHAT_WEBHOOK_BACKORDER") ?? "";
  if (!hook) return json(500, { ok: false, error: "IMS_CHAT_WEBHOOK_BACKORDER not configured - nothing posted (runs stay due)" });
  const cfg = await readConfig();
  const test = projectRef(SB_URL()) !== "gftpcnkxbdjzzfvzwcfl" || cfg.db_role === "test";
  const results: unknown[] = [];
  // 판정 518(mail-4c): 회차 실패 한 줄 먼저 — 창고 · 날마다 한 번(풀리지 않은 것만)
  const errs = (await sbRpc("mail_run_error_chat_due", {})) as ChatError[];
  for (const e of errs) {
    const r = await postChat(hook, errorChatText(e, test));
    results.push(await sbRpc("mail_run_error_chat_mark", { p_id: e.error_id, p_ok: r.ok, p_error: r.err }));
    await new Promise((res) => setTimeout(res, CHAT_GAP_MS));
  }
  const due = (await sbRpc("mail_run_chat_due", {})) as (ChatRun & { run_id: string })[];
  for (const run of due) {
    const rows = await sbGet(`mail_outbox?select=status,payload&run_id=eq.${run.run_id}&order=created_at`);
    const mails: ChatMail[] = rows.map((r) => ({ status: r.status, customer_name: r.payload?.customer_name ?? null, lines: (r.payload?.lines ?? []).map((l: any) => ({ so_number: l.so_number, sku: l.sku })) }));
    const runRow = (await sbGet(`mail_run?select=no_email&id=eq.${run.run_id}`))[0];
    const skippedIds: { customer_id: string; reason: string }[] = runRow?.no_email ?? [];
    const names = skippedIds.length ? await sbGet(`customer?select=id,name&id=in.(${skippedIds.map((s) => s.customer_id).join(",")})`) : [];
    const skippedNames = skippedIds.map((s) => ({ name: names.find((n) => n.id === s.customer_id)?.name ?? "", reason: s.reason }));
    const r = await postChat(hook, chatText(run, mails, skippedNames, test));
    results.push(await sbRpc("mail_run_chat_mark", { p_run_id: run.run_id, p_ok: r.ok, p_error: r.err }));
    await new Promise((res) => setTimeout(res, CHAT_GAP_MS));
  }
  return json(200, { ok: true, posted: results });
}

async function doRender(id: string): Promise<Response> {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return json(400, { ok: false, error: "id must be a mail id" });
  const row = (await sbGet(`mail_outbox?select=id,kind,status,from_address,from_name,reply_to,to_address,payload,attempts,subject,body_text,attachments&id=eq.${id}`))[0];
  if (!row) return json(404, { ok: false, error: "mail not found" });
  const s = safety(await readConfig(), projectRef(SB_URL()));
  const r = render(row.kind, row.payload, row);                                                      // doc_* 는 줄의 제목 · 본문
  const mail = { ...row, attempt: row.attempts } as ClaimedMail;
  const a = s.ok ? addressFor(mail, s, r.subject) : { to: row.to_address, original_to: null, subject: r.subject };
  return json(200, { ok: true, status: row.status, would_send: s.ok, safety: s.ok ? (s.test ? "test-redirect" : (s.redirect ? "redirect" : "live")) : s.reason,
    from: { name: row.from_name, address: row.from_address }, reply_to: row.reply_to, to: a.to, original_to: a.original_to, subject: a.subject, body_text: r.body_text, body_html: r.body_html,
    attachments: isDocKind(row.kind) ? (row.attachments ?? []) : undefined });
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
    if (body.action === "pdf") return await doPdf();
    if (body.action === "chat") return await doChat();
    if (body.action === "render") return await doRender(String(body.id ?? ""));
    return json(400, { ok: false, error: "action must be drain, pdf, chat or render" });
  } catch (e) {
    console.error("mail failed:", String((e as Error)?.message ?? e).slice(0, 500));
    return json(500, { ok: false, error: String((e as Error)?.message ?? e).slice(0, 300) });
  }
});
