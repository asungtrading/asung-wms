// _shared/mail.ts — IMS 메일 EF(mail)의 순수 함수 · 흐름(mail-2b · 2026-10-16) — DB · Google 은 deps 로 받는다(시험은 가짜)
//   판정 493(Gmail API) · 500(창고마다 글) · 501(그 손님 몫 + 창고 가용) · 502(Chat 요약) · 505(일부 몫) · 510(ims@asung.ca · OAuth) · 511(From 별칭 · Reply-To) · 514(응답 없음 = unknown)
//   안전(mail-1a 이견 1 · 11): 프로젝트 ref 와 inv_config.db_role 이 같은 쪽을 가리켜야 하고 · 시험이면 mail_redirect_to(@asung.ca)로 돌려 보낸다 · 아니면 보내지 않는다

export const TEST_REF = "fazgmyvzzhqybtvtktyg";   // Asung-IMS(테스트)
export const PROD_REF = "gftpcnkxbdjzzfvzwcfl";   // asung-WMS(운영)

export type MailConfig = { enabled: boolean; redirect_to: string | null; db_role: string | null };
export type Line = { so_number: string; line_no: number; sku: string; product_name: string | null; qty_open: number; can_fill_units: number; available_units: number | null; basis?: string; is_combo?: boolean };
export type Payload = { customer_name?: string | null; location_name?: string | null; lines?: Line[] };
export type ClaimedMail = { id: string; kind: string; from_address: string; from_name: string | null; reply_to: string | null; to_address: string; payload: Payload; attempt: number };
export type Rendered = { subject: string; body_text: string; body_html: string };
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
export function render(kind: string, p: Payload): Rendered {
  if (kind === "backorder_ready") return renderBackorderReady(p);
  throw new Error(`render: unknown mail kind ${kind}`);
}

// ── MIME(RFC 5322 · 2047 · 2045) ──
const noCrLf = (s: string) => s.replace(/[\r\n]+/g, " ").trim();
const b64 = (bytes: Uint8Array) => { let s = ""; for (const b of bytes) s += String.fromCharCode(b); return btoa(s); };
const utf8 = (s: string) => new TextEncoder().encode(s);
export function encodeWord(s: string): string { return /^[\x20-\x7e]*$/.test(s) ? s : `=?UTF-8?B?${b64(utf8(s))}?=`; }
export function mailbox(name: string | null, address: string): string {
  const a = noCrLf(address), n = noCrLf(name ?? "");
  if (!n) return a;
  if (!/^[\x20-\x7e]*$/.test(n)) return `${encodeWord(n)} <${a}>`;
  return `"${n.replace(/(["\\])/g, "\\$1")}" <${a}>`;
}
const wrap76 = (s: string) => s.replace(/.{1,76}/g, (m) => m + "\r\n");
export function buildMime(o: { from_name: string | null; from_address: string; to: string; reply_to: string | null; subject: string; text: string; html: string; boundary: string }): string {
  const hs = [`From: ${mailbox(o.from_name, o.from_address)}`, `To: ${noCrLf(o.to)}`];
  if (o.reply_to) hs.push(`Reply-To: ${noCrLf(o.reply_to)}`);
  hs.push(`Subject: ${encodeWord(noCrLf(o.subject))}`, "MIME-Version: 1.0", `Content-Type: multipart/alternative; boundary="${o.boundary}"`);
  const part = (type: string, body: string) => `--${o.boundary}\r\nContent-Type: ${type}; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n${wrap76(b64(utf8(body.replace(/\r?\n/g, "\r\n"))))}`;
  return hs.join("\r\n") + "\r\n\r\n" + part("text/plain", o.text) + part("text/html", o.html) + `--${o.boundary}--\r\n`;
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
};
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
      let r: Rendered;
      try { r = render(m.kind, m.payload); }
      catch (e) { await d.mark(m.id, m.attempt, { result: "failed", provider_message_id: null, error: String(e).slice(0, 500) }, null); counts.failed++; continue; }
      const a = addressFor(m, s, r.subject);
      const rendered = { subject: a.subject, body_text: r.body_text, body_html: r.body_html, to_address: a.to, original_to: a.original_to };
      let outcome: Outcome;
      try { tok ??= await d.token(); outcome = await d.send(tok, base64url(buildMime({ from_name: m.from_name, from_address: m.from_address, to: a.to, reply_to: m.reply_to, subject: a.subject, text: r.body_text, html: r.body_html, boundary: o.boundary() }))); }
      catch (e) { outcome = { kind: "token", message: String((e as Error)?.message ?? e) }; }
      const mk = classify(outcome);
      if (outcome.kind === "token" || (outcome.kind === "http" && outcome.status === 401)) { tok = null; if (outcome.kind === "token") tokenBroken = mk.error; d.log(`mail token problem: ${mk.error}`); }
      await d.mark(m.id, m.attempt, mk, mk.result === "sent" ? rendered : null);
      counts[mk.result]++;
    }
  }
  return { ok: true, status: "drained", counts };
}
