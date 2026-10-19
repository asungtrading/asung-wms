// _shared/mail.ts — IMS 메일 EF(mail)의 순수 함수 · 흐름(mail-2b · 2026-10-16) — DB · Google 은 deps 로 받는다(시험은 가짜)
//   판정 493(Gmail API) · 500(창고마다 글) · 501(그 손님 몫 + 창고 가용) · 502(Chat 요약) · 505(일부 몫) · 510(ims@asung.ca · OAuth) · 511(From 별칭 · Reply-To) · 514(응답 없음 = unknown)
//   doc-3b(2026-10-19 · 판정 529 · 530): 문서 메일(kind doc_*) — 제목 · 본문은 줄에 · PDF 는 attachments + Storage · MIME 은 첨부가 있을 때만 multipart/mixed(없으면 mail-2b 바이트 그대로 · 시험 ⑫) · PDF 단계 pdfStep
//   안전(mail-1a 이견 1 · 11): 프로젝트 ref 와 inv_config.db_role 이 같은 쪽을 가리켜야 하고 · 시험이면 mail_redirect_to(@asung.ca)로 돌려 보낸다 · 아니면 보내지 않는다

export const TEST_REF = "fazgmyvzzhqybtvtktyg";   // Asung-IMS(테스트)
export const PROD_REF = "gftpcnkxbdjzzfvzwcfl";   // asung-WMS(운영)

export type MailConfig = { enabled: boolean; redirect_to: string | null; db_role: string | null };
export type Line = { so_number: string; line_no: number; sku: string; product_name: string | null; qty_open: number; can_fill_units: number; available_units: number | null; basis?: string; is_combo?: boolean };
export type Payload = { customer_name?: string | null; location_name?: string | null; lines?: Line[] };
export type ClaimedMail = { id: string; kind: string; from_address: string; from_name: string | null; reply_to: string | null; to_address: string; payload: Payload; attempt: number; subject?: string | null };
export type Rendered = { subject: string; body_text: string; body_html: string };
// doc-3b(2026-10-19 · 3a 계약): 문서 메일(kind doc_*)은 제목 · 본문이 줄에 박혀 있고(doc_mail_send · doc_setting 글) 첨부는 mail_outbox.attachments — PDF 바이트는 Storage documents/<path>
export type Attachment = { doc_file_id: string; path: string; filename: string; bytes: number; sha256: string };
export type DocBody = { body_text: string | null; attachments: Attachment[] };
export type AttachmentRead = { ok: true; bytes: Uint8Array } | { ok: false; retry: boolean; error: string };
export const DOC_KINDS = ["doc_final_invoice", "doc_credit_note", "doc_sales_order", "doc_ship_ready"] as const;
export function isDocKind(kind: string): boolean { return (DOC_KINDS as readonly string[]).includes(kind); }
export type Safety = { ok: true; test: boolean; redirect: string | null } | { ok: false; reason: "disabled" | "unknown_project" | "mismatch" | "no_redirect"; detail: string };

// ── 안전 ──
export function projectRef(supabaseUrl: string): string | null {
  const m = /^https:\/\/([a-z0-9]{20})\.supabase\.co\/?$/.exec(supabaseUrl.trim());
  return m ? m[1] : null;
}
const ONE_ADDRESS = /^[^@\s,;]+@[^@\s,;]+\.[^@\s,;]+$/;   // ims_mail_address_ok 와 같은 모양
export function safety(cfg: MailConfig, ref: string | null): Safety {
  if (ref !== TEST_REF && ref !== PROD_REF) return { ok: false, reason: "unknown_project", detail: `project ref ${ref ?? "missing"} is neither the test nor the production project` };
  const refTest = ref === TEST_REF, dbTest = cfg.db_role === "test";
  if (refTest !== dbTest) return { ok: false, reason: "mismatch", detail: `project ref says ${refTest ? "test" : "production"} but inv_config.db_role is ${cfg.db_role ?? "missing"}` };
  if (!cfg.enabled) return { ok: false, reason: "disabled", detail: "mail_enabled is not on" };
  const r = (cfg.redirect_to ?? "").trim();
  if (refTest) {
    if (!ONE_ADDRESS.test(r) || !/@asung\.ca$/i.test(r)) return { ok: false, reason: "no_redirect", detail: "test database without an @asung.ca mail_redirect_to — nothing is sent" };
    return { ok: true, test: true, redirect: r };
  }
  if (r && !ONE_ADDRESS.test(r)) return { ok: false, reason: "no_redirect", detail: "mail_redirect_to is not one address" };
  return { ok: true, test: false, redirect: r || null };
}
// 돌려 보내기: 받는 이 · 제목 앞 표지 · original_to
export function addressFor(mail: ClaimedMail, s: Safety & { ok: true }, subject: string): { to: string; original_to: string | null; subject: string } {
  if (!s.redirect) return { to: mail.to_address, original_to: null, subject };
  return { to: s.redirect, original_to: mail.to_address, subject: `[${s.test ? "TEST" : "REDIRECT"} → ${mail.to_address}] ${subject}` };
}

// ── 그리기(backorder_ready) ──
const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
const num = (n: number | null | undefined) => (n === null || n === undefined || !Number.isFinite(Number(n))) ? "—" : String(Number(n));
export function isEdmonton(locationName: string | null | undefined): boolean { return /edmonton/i.test(locationName ?? ""); }   // CLAUDE.md 불변식(Location 에 Edmonton → edmonton)
function readyText(l: Line): string {
  const c = Number(l.can_fill_units), q = Number(l.qty_open);
  return c >= q ? `${num(c)} (all of it)` : `${num(c)} of your ${num(q)} on backorder`;   // 505: 일부 몫
}
function grouped(lines: Line[]): [string, Line[]][] {
  const m = new Map<string, Line[]>();
  for (const l of [...lines].sort((a, b) => a.so_number.localeCompare(b.so_number) || a.line_no - b.line_no)) m.set(l.so_number, [...(m.get(l.so_number) ?? []), l]);
  return [...m.entries()];
}
const FOOTER = `Best regards,

Customer Service Team

"With a Graceful Win, We become the Channel of Blessing"

Email: info@asung.ca  |  Web: www.asung.ca
Toronto HQ | 35 Suntract Rd. North York, ON M9N 2V8 | +1 (416) 792-2298
Edmonton   | 18418 105 Ave NW. Edmonton, AB T5S 0N7 | +1 (780) 752-7678

This email and any attachments are confidential and intended only for the designated recipient.
If you have received this email in error, please notify the sender and delete it from your system.
Unauthorized copying, disclosure, or distribution of this email is strictly prohibited.
If you have received content that does not belong to you, please contact us at info@asung.ca`;
const RULE = "─────────────────────────────────";
export function renderBackorderReady(p: Payload): Rendered {
  const ed = isEdmonton(p.location_name);
  const where = ed ? "Edmonton" : "Toronto";
  const name = (p.customer_name ?? "").trim() || "Customer";
  const lines = p.lines ?? [];
  if (!lines.length) throw new Error("render: payload has no lines");
  const subject = ed ? "[Asung Trading] Backordered Item(s) Now Available in Edmonton" : "[Asung Trading] Backordered Item(s) Now Back In Stock";
  const intro = `We are pleased to inform you that the following backordered item(s) ${ed ? "are now available at our Edmonton location" : "are now back in stock"}.`;
  const t: string[] = [`Dear ${name},`, "", intro, "Please see the details below:", ""];
  const h: string[] = [`<p>Dear ${esc(name)},</p>`, `<p>${esc(intro)}<br>Please see the details below:</p>`];
  for (const [so, ls] of grouped(lines)) {
    t.push(`Order No. : ${so}`, RULE);
    h.push(`<p style="margin:16px 0 4px"><b>Order No. : ${esc(so)}</b></p>`,
      `<table cellpadding="4" cellspacing="0" border="1" style="border-collapse:collapse;font-family:Arial,sans-serif;font-size:13px">`,
      `<tr style="background:#f2f2f2"><th align="left">Product</th><th align="left">SKU</th><th align="right">Backordered Qty</th><th align="left">Ready for you now</th><th align="right">In stock (${where})</th></tr>`);
    for (const l of ls) {
      const pn = (l.product_name ?? "").trim() || l.sku;
      const f = (label: string, v: string) => `${label.padEnd(19)} : ${v}`;                       // 칸 이름 너비 하나(가장 긴 In stock (Edmonton) = 19)
      t.push(f("Product", pn), f("SKU", l.sku), f("Backordered Qty", num(l.qty_open)), f("Ready for you now", readyText(l)), f(`In stock (${where})`, num(l.available_units)), RULE);
      h.push(`<tr><td>${esc(pn)}</td><td>${esc(l.sku)}</td><td align="right">${esc(num(l.qty_open))}</td><td>${esc(readyText(l))}</td><td align="right">${esc(num(l.available_units))}</td></tr>`);
    }
    t.push("");
    h.push(`</table>`);
  }
  const note1 = "This email is for notification purposes only. We will not be processing the backorder automatically.";
  const note2 = "If you wish to proceed with the item(s), please place a new order at www.asung.ca.";
  const note3 = "\"Ready for you now\" is how much of your backorder we have in stock today. Stock is not reserved for you and may sell out before your new order is placed.";   // 판정 515 고침 ① — 알림 뒤 재고를 잡아 두지 않는다(496 · 506)
  t.push(note1, note2, note3, "", FOOTER);
  h.push(`<p>${esc(note1)}<br>${esc(note2)}</p>`, `<p style="color:#555;font-size:12px">${esc(note3)}</p>`,
    `<pre style="font-family:Arial,sans-serif;font-size:12px;color:#333;white-space:pre-wrap">${esc(FOOTER)}</pre>`);
  return { subject, body_text: t.join("\n"), body_html: `<!doctype html><html><body style="font-family:Arial,sans-serif;font-size:14px">${h.join("\n")}</body></html>` };
}
// ── 그리기(doc_* · doc-3b) — 제목 · 본문은 줄에 박힌 것 그대로 · HTML 은 글을 이스케이프해 pre-wrap 으로(판정 530 의 보내는 이름 · 주소도 줄에 있다) ──
export function textToHtml(text: string): string {
  return `<!doctype html><html><body style="font-family:Arial,sans-serif;font-size:14px"><pre style="font-family:Arial,sans-serif;font-size:14px;white-space:pre-wrap">${esc(text)}</pre></body></html>`;
}
export function renderDoc(m: { subject?: string | null; body_text?: string | null }): Rendered {
  const subject = (m.subject ?? "").trim(), text = m.body_text ?? "";
  if (!subject || !text.trim()) throw new Error("render: document mail has no subject or body (doc_mail_send fills both)");
  return { subject, body_text: text, body_html: textToHtml(text) };
}
export function render(kind: string, p: Payload, mail?: { subject?: string | null; body_text?: string | null }): Rendered {
  if (kind === "backorder_ready") return renderBackorderReady(p);
  if (isDocKind(kind)) return renderDoc(mail ?? {});
  throw new Error(`render: unknown mail kind ${kind}`);
}

// ── MIME(RFC 5322 · 2047 · 2045) ──
const noCrLf = (s: string) => s.replace(/[\r\n]+/g, " ").trim();
const b64 = (bytes: Uint8Array) => { let s = ""; for (let i = 0; i < bytes.length; i += 32768) s += String.fromCharCode(...bytes.subarray(i, Math.min(i + 32768, bytes.length))); return btoa(s); };   // 덩이로(PDF 10 MB · 결과는 전과 같다 — 시험 ⑫)
const utf8 = (s: string) => new TextEncoder().encode(s);
export function encodeWord(s: string): string { return /^[\x20-\x7e]*$/.test(s) ? s : `=?UTF-8?B?${b64(utf8(s))}?=`; }
export function mailbox(name: string | null, address: string): string {
  const a = noCrLf(address), n = noCrLf(name ?? "");
  if (!n) return a;
  if (!/^[\x20-\x7e]*$/.test(n)) return `${encodeWord(n)} <${a}>`;
  return `"${n.replace(/(["\\])/g, "\\$1")}" <${a}>`;
}
const wrap76 = (s: string) => s.replace(/.{1,76}/g, (m) => m + "\r\n");
export type MimeFile = { filename: string; bytes: Uint8Array };
const fileName = (s: string) => (s.replace(/[^\x20-\x7e]/g, "_").replace(/["\\;]/g, "_").trim() || "document.pdf");   // 헤더에 그대로 들어간다 — ASCII · 따옴표 없이
export function buildMime(o: { from_name: string | null; from_address: string; to: string; reply_to: string | null; subject: string; text: string; html: string; boundary: string; attachments?: MimeFile[] }): string {
  const hs = [`From: ${mailbox(o.from_name, o.from_address)}`, `To: ${noCrLf(o.to)}`];
  if (o.reply_to) hs.push(`Reply-To: ${noCrLf(o.reply_to)}`);
  const files = o.attachments ?? [];
  if (!files.length) {                                                                                 // 첨부 없음 — mail-2b 모양 그대로(바이트 무변 · 시험 ⑫ 황금 문자열)
    hs.push(`Subject: ${encodeWord(noCrLf(o.subject))}`, "MIME-Version: 1.0", `Content-Type: multipart/alternative; boundary="${o.boundary}"`);
    const part = (type: string, body: string) => `--${o.boundary}\r\nContent-Type: ${type}; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n${wrap76(b64(utf8(body.replace(/\r?\n/g, "\r\n"))))}`;
    return hs.join("\r\n") + "\r\n\r\n" + part("text/plain", o.text) + part("text/html", o.html) + `--${o.boundary}--\r\n`;
  }
  // 첨부 있음(doc-3b) — 바깥 multipart/mixed · 안에 multipart/alternative(위와 같은 두 갈래) + application/pdf(base64 · Content-Disposition: attachment)
  const alt = o.boundary + "-alt";
  hs.push(`Subject: ${encodeWord(noCrLf(o.subject))}`, "MIME-Version: 1.0", `Content-Type: multipart/mixed; boundary="${o.boundary}"`);
  const part = (type: string, body: string) => `--${alt}\r\nContent-Type: ${type}; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n${wrap76(b64(utf8(body.replace(/\r?\n/g, "\r\n"))))}`;
  const inner = `--${o.boundary}\r\nContent-Type: multipart/alternative; boundary="${alt}"\r\n\r\n` + part("text/plain", o.text) + part("text/html", o.html) + `--${alt}--\r\n`;
  const pdfs = files.map((f) => { const n = fileName(f.filename); return `--${o.boundary}\r\nContent-Type: application/pdf; name="${n}"\r\nContent-Transfer-Encoding: base64\r\nContent-Disposition: attachment; filename="${n}"\r\n\r\n${wrap76(b64(f.bytes))}`; }).join("");
  return hs.join("\r\n") + "\r\n\r\n" + inner + pdfs + `--${o.boundary}--\r\n`;
}
export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const h = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes.slice()));
  return Array.from(h, (b) => b.toString(16).padStart(2, "0")).join("");
}
export function base64url(s: string): string { return b64(utf8(s)).replace(/\+/g, "-").replace(/\//g, "_"); }

// ── 결과 갈래(Gmail 문서 「Resolve errors」 2026-10-16 확인) ──
export type Outcome = { kind: "http"; status: number; body: string } | { kind: "timeout" } | { kind: "network"; message: string } | { kind: "token"; message: string };
export type Mark = { result: "sent" | "failed" | "retry" | "unknown"; provider_message_id: string | null; error: string | null };
const RETRY_403 = ["rateLimitExceeded", "userRateLimitExceeded", "dailyLimitExceeded"];
export function classify(o: Outcome): Mark {
  if (o.kind === "token") return { result: "retry", provider_message_id: null, error: `token: ${o.message}`.slice(0, 500) };              // Gmail 에 아무것도 안 갔다
  if (o.kind === "timeout") return { result: "unknown", provider_message_id: null, error: "timeout waiting for Gmail — the message may or may not have been sent" };   // 514
  if (o.kind === "network") return { result: "unknown", provider_message_id: null, error: `network: ${o.message}`.slice(0, 500) };
  let reason = "", message = "", id: string | null = null;
  try { const j = JSON.parse(o.body || "{}"); id = j?.id ?? null; reason = j?.error?.errors?.[0]?.reason ?? j?.error?.status ?? ""; message = j?.error?.message ?? ""; } catch { message = (o.body || "").slice(0, 200); }
  const err = `${o.status}${reason ? " " + reason : ""}${message ? ": " + message : ""}`.slice(0, 500);
  if (o.status >= 200 && o.status < 300) return id ? { result: "sent", provider_message_id: id, error: null } : { result: "unknown", provider_message_id: null, error: `${o.status} without a message id` };
  if (o.status === 401) return { result: "retry", provider_message_id: null, error: err };                    // 토큰 만료 · 철회 — 안 보내졌다
  if (o.status === 403 && RETRY_403.includes(reason)) return { result: "retry", provider_message_id: null, error: err };
  if (o.status === 429 || o.status >= 500) return { result: "retry", provider_message_id: null, error: err };
  return { result: "failed", provider_message_id: null, error: err };                                         // 400 · 403(권한 · 정책) · 404 …
}

// ── Chat 요약(판정 502 · 이메일 주소는 넣지 않는다) ──
export type ChatRun = { run_id: string; location_name: string; run_on: string; mails: number; by_status: Record<string, number>; skipped: Record<string, number> };
export type ChatMail = { status: string; customer_name: string | null; lines: { so_number: string; sku: string }[] };
const REASON_WORD: Record<string, string> = { no_email: "no email", bad_shape: "email not usable", paused: "alerts off", customer_inactive: "inactive customer" };
export function chatText(run: ChatRun, mails: ChatMail[], skippedNames: { name: string; reason: string }[], test: boolean, max = 3500): string {
  const head = `${test ? "[TEST] " : ""}Backorder mail — ${isEdmonton(run.location_name) ? "Edmonton" : "Toronto"} · ${run.run_on}`;
  const sk = Object.entries(run.skipped).filter(([, n]) => n > 0).map(([r, n]) => `${REASON_WORD[r] ?? r} ${n}`).join(" · ");
  if (!mails.length) return `${head} — nothing to send.${sk ? ` Not sent: ${sk}.` : ""}`;
  const st = (k: string) => run.by_status[k] ?? 0;
  const out = [head, `Sent ${st("sent")} · Failed ${st("failed")} · Unknown ${st("unknown")} · Cancelled ${st("cancelled")}${sk ? ` · Not sent: ${sk}` : ""}`];
  const rows = mails.map((m) => {
    const byOrder = new Map<string, string[]>();
    for (const l of m.lines) byOrder.set(l.so_number, [...(byOrder.get(l.so_number) ?? []), l.sku]);
    const tag = m.status === "sent" ? "" : ` [${m.status}]`;
    return `• ${(m.customer_name ?? "").trim() || "(no name)"}${tag} — ` + [...byOrder.entries()].map(([so, skus]) => `${so}: ${skus.join(", ")}`).join("; ");
  });
  if (skippedNames.length) rows.push(...skippedNames.map((s) => `• ${s.name || "(no name)"} — not sent (${REASON_WORD[s.reason] ?? s.reason})`));
  let text = out.join("\n");
  for (let i = 0; i < rows.length; i++) {
    if ((text + "\n" + rows[i]).length > max) { text += `\n… and ${rows.length - i} more`; break; }
    text += "\n" + rows[i];
  }
  return text;
}

// ── 회차 실패 Chat 한 줄(판정 518 · mail-4c) — 오류 요지만 · 이메일 · 열쇠 모양은 지운다 ──
export type ChatError = { error_id: number; location_name: string; run_on: string; message: string | null; attempts: number };
const EMAIL_LIKE = /[^\s@<>"'(),;:]+@[^\s@<>"'(),;:]+\.[^\s@<>"'(),;:]+/g;
const KEY_LIKE = /[A-Za-z0-9_\-]{32,}/g;
export function errorChatText(e: ChatError, test: boolean, gistMax = 200): string {
  const gist = (e.message ?? "").replace(EMAIL_LIKE, "<email>").replace(KEY_LIKE, "<…>").replace(/\s+/g, " ").trim();
  const short = gist.length > gistMax ? gist.slice(0, gistMax - 1) + "…" : gist;
  return `${test ? "[TEST] " : ""}⚠️ Backorder mail — ${isEdmonton(e.location_name) ? "Edmonton" : "Toronto"} · ${e.run_on} — run failed (${short || "no message"})`;
}

// ── 흐름(drain · chat) — deps 를 넣어 시험한다 ──
export type Deps = {
  ref: string | null;
  readConfig: () => Promise<MailConfig>;
  claim: (n: number) => Promise<MailConfig & { mails: ClaimedMail[] }>;
  mark: (id: string, attempt: number, m: Mark, rendered: (Rendered & { to_address: string; original_to: string | null }) | null) => Promise<void>;
  token: () => Promise<string>;
  send: (token: string, raw: string) => Promise<Outcome>;
  now: () => number;
  log: (msg: string) => void;
  loadDoc: (id: string) => Promise<DocBody>;                    // doc-3b: 문서 메일의 본문 · 첨부 목록(mail_claim 은 subject 까지만 준다 · 기계 무접촉)
  readAttachment: (a: Attachment) => Promise<AttachmentRead>;   // doc-3b: Storage documents/<path> 바이트
};
// 문서 메일 재료 — 본문 · 첨부(sha256 · 크기 대조 · 없거나 틀리면 failed · Storage 가 잠깐 안 되면 retry)
export async function docMaterial(d: Deps, m: ClaimedMail): Promise<{ ok: true; r: Rendered; files: MimeFile[] } | { ok: false; result: "failed" | "retry"; error: string }> {
  const doc = await d.loadDoc(m.id);
  let r: Rendered;
  try { r = renderDoc({ subject: m.subject, body_text: doc.body_text }); } catch (e) { return { ok: false, result: "failed", error: String((e as Error)?.message ?? e).slice(0, 500) }; }
  if (!doc.attachments.length) return { ok: false, result: "failed", error: "document mail has no attachment — the PDF step did not attach one (doc_mail_attach)" };
  const files: MimeFile[] = [];
  for (const a of doc.attachments) {
    const got = await d.readAttachment(a);
    if (!got.ok) return { ok: false, result: got.retry ? "retry" : "failed", error: `attachment ${a.filename}: ${got.error}`.slice(0, 500) };
    if (got.bytes.length !== Number(a.bytes)) return { ok: false, result: "failed", error: `attachment ${a.filename}: ${got.bytes.length} bytes in storage, ${a.bytes} expected` };
    const h = await sha256Hex(got.bytes);
    if (h !== a.sha256) return { ok: false, result: "failed", error: `attachment ${a.filename}: sha256 differs from doc_file` };
    files.push({ filename: a.filename, bytes: got.bytes });
  }
  return { ok: true, r, files };
}
export async function drain(d: Deps, o: { batch: number; budgetMs: number; boundary: () => string }): Promise<{ ok: boolean; status: string; detail?: string; counts: Record<string, number> }> {
  const t0 = d.now(), counts: Record<string, number> = { sent: 0, failed: 0, retry: 0, unknown: 0 };
  const pre = safety(await d.readConfig(), d.ref);
  if (!pre.ok && pre.reason !== "disabled") { d.log(`mail drain refused: ${pre.detail}`); return { ok: false, status: pre.reason, detail: pre.detail, counts }; }   // 어긋나면 집지도 않는다
  if (!pre.ok) { await d.claim(o.batch); return { ok: true, status: "disabled", counts }; }                                                                // 꺼짐 — claim 이 멈춘 sending 만 되살린다
  let tok: string | null = null, tokenBroken: string | null = null;
  while (d.now() - t0 < o.budgetMs && !tokenBroken) {
    const c = await d.claim(o.batch);
    if (!c.mails.length) break;
    const s = safety(c, d.ref);
    for (const m of c.mails) {
      if (!s.ok) { await d.mark(m.id, m.attempt, { result: "retry", provider_message_id: null, error: `safety: ${s.detail}` }, null); counts.retry++; continue; }   // 집은 뒤 설정이 바뀜 — 보내지 않는다
      if (tokenBroken) { await d.mark(m.id, m.attempt, { result: "retry", provider_message_id: null, error: tokenBroken }, null); counts.retry++; continue; }   // 열쇠가 없으면 이 묶음은 보내지 않고 다음에
      let r: Rendered, files: MimeFile[] | undefined;
      if (isDocKind(m.kind)) {                                                                                                                             // doc-3b: 문서 메일 — 줄의 글 + Storage 의 PDF
        const mat = await docMaterial(d, m);
        if (!mat.ok) { await d.mark(m.id, m.attempt, { result: mat.result, provider_message_id: null, error: mat.error }, null); counts[mat.result]++; continue; }
        r = mat.r; files = mat.files;
      } else {
        try { r = render(m.kind, m.payload); }
        catch (e) { await d.mark(m.id, m.attempt, { result: "failed", provider_message_id: null, error: String(e).slice(0, 500) }, null); counts.failed++; continue; }
      }
      const a = addressFor(m, s, r.subject);
      const rendered = { subject: a.subject, body_text: r.body_text, body_html: r.body_html, to_address: a.to, original_to: a.original_to };
      let outcome: Outcome;
      try { tok ??= await d.token(); outcome = await d.send(tok, base64url(buildMime({ from_name: m.from_name, from_address: m.from_address, to: a.to, reply_to: m.reply_to, subject: a.subject, text: r.body_text, html: r.body_html, boundary: o.boundary(), attachments: files }))); }
      catch (e) { outcome = { kind: "token", message: String((e as Error)?.message ?? e) }; }
      const mk = classify(outcome);
      if (outcome.kind === "token" || (outcome.kind === "http" && outcome.status === 401)) { tok = null; if (outcome.kind === "token") tokenBroken = mk.error; d.log(`mail token problem: ${mk.error}`); }
      await d.mark(m.id, m.attempt, mk, mk.result === "sent" ? rendered : null);
      counts[mk.result]++;
    }
  }
  return { ok: true, status: "drained", counts };
}

// ── PDF 단계(doc-3b · 3a 계약) — waiting_pdf 줄을 집어(doc_mail_pdf_claim) EF doc 으로 PDF 를 만들고(render · reason send · service 길) 붙인다(doc_mail_attach → queued) · 못 만들면 doc_mail_pdf_failed(세 번 뒤 failed) ──
//   보내지 않는다 — 그 뒤는 기존 drain 이 집는다(queued · next_attempt_at = now). mail_enabled 가 꺼져 있으면 집지 않는다(메일만 끄는 스위치가 PDF 도 멈춘다).
export type PdfJob = { outbox_id: string; doc_kind: string; ref: unknown; attempts: number };
export type PdfRender = { ok: true; doc_file_id: string } | { ok: false; error: string };
export type PdfDeps = {
  readConfig: () => Promise<MailConfig>;
  claim: (n: number) => Promise<PdfJob[]>;
  render: (kind: string, ref: unknown) => Promise<PdfRender>;
  attach: (outboxId: string, docFileId: string) => Promise<void>;
  failed: (outboxId: string, error: string) => Promise<void>;
  now: () => number;
  log: (msg: string) => void;
};
export async function pdfStep(d: PdfDeps, o: { batch: number; budgetMs: number }): Promise<{ ok: boolean; status: string; counts: Record<string, number> }> {
  const t0 = d.now(), counts: Record<string, number> = { attached: 0, failed: 0 };
  const cfg = await d.readConfig();
  if (!cfg.enabled) return { ok: true, status: "disabled", counts };
  while (d.now() - t0 < o.budgetMs) {
    const jobs = await d.claim(o.batch);
    if (!jobs.length) break;
    for (const j of jobs) {
      if (j.doc_kind === "ship_ready") { await d.failed(j.outbox_id, "a Ship Ready mail needs its PDF made by the staff who sends it (doc-1b2) — the worker cannot make it"); counts.failed++; continue; }   // 3a 는 ship_ready 를 waiting_pdf 로 넣지 않는다 — 방어
      const r = await d.render(j.doc_kind, j.ref);
      if (!r.ok) { await d.failed(j.outbox_id, r.error); counts.failed++; d.log(`mail pdf failed (${j.doc_kind} attempt ${j.attempts + 1}): ${r.error}`); continue; }
      try { await d.attach(j.outbox_id, r.doc_file_id); counts.attached++; }
      catch (e) { await d.failed(j.outbox_id, `attach: ${String((e as Error)?.message ?? e)}`.slice(0, 500)); counts.failed++; }   // PDF 는 남는다(doc_file · 버킷) · 줄은 다음에 다시
    }
  }
  return { ok: true, status: "done", counts };
}
