// deno test supabase/functions/mail/mail_test.ts — Google · DB 무접촉(가짜) · mail-2b ① ~ ⑩ · mail-4c ⑪ · doc-3b ⑫ ~ ⑯(문서 메일 · MIME 무변 황금 · PDF 단계) · qbo-1b ⑰(payload 알림 qbo_reconnect) · mail-live-1 ⑱ · aone-bo-1 ⑲ · mail-inc-1b ⑳(doc 갈래 황금) · ㉑(받는 이 여럿)
import { addressFor, base64url, buildMime, chatText, classify, drain, encodeWord, errorChatText, isDocKind, isPlainKind, renderPlain, mailbox, MAX_RECIPIENTS, pdfStep, projectRef, PROD_REF, recipients, render, safety, sha256Hex, TEST_REF, testMode, type Attachment, type AttachmentRead, type ClaimedMail, type Deps, type DocBody, type Line, type MailConfig, type Mark, type Outcome, type PdfDeps, type PdfJob } from "../_shared/mail.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
function ok(c: boolean, msg: string) { if (!c) throw new Error(msg); }
const L = (so: string, no: number, sku: string, name: string | null, q: number, c: number, av: number | null, combo = false): Line => ({ so_number: so, line_no: no, sku, product_name: name, qty_open: q, can_fill_units: c, available_units: av, basis: c >= q ? "full" : "receipt", is_combo: combo });
const PAYLOAD = { customer_name: "Maple <script>alert(1)</script> Café 가게", location_name: "Asung Trading Inc.",
  lines: [L("SO-90002", 1, "AAA-1", "Rice cooker", 48, 24, 30), L("SO-90001", 2, "BBB-2", "Pan & lid \"set\"", 5, 5, 12), L("SO-90001", 1, "CCC-3", "Combo box", 2, 2, 7, true)] };
const decodeB64 = (s: string) => new TextDecoder().decode(Uint8Array.from(atob(s.replace(/\r\n/g, "")), (ch) => ch.charCodeAt(0)));

Deno.test("① 그리기 — 오더 둘(번호 순) · 줄 셋(줄 번호 순) · 일부 몫 · 501 두 칸 · Toronto 제목", () => {
  const r = render("backorder_ready", PAYLOAD);
  eq(r.subject, "[Asung Trading] Backordered Item(s) Now Back In Stock", "toronto subject");
  const t = r.body_text;
  ok(t.indexOf("Order No. : SO-90001") < t.indexOf("Order No. : SO-90002"), "orders sorted");
  ok(t.indexOf("CCC-3") < t.indexOf("BBB-2"), "lines sorted by line_no inside SO-90001");
  ok(t.includes("Ready for you now   : 24 of your 48 on backorder"), "505 partial");
  ok(t.includes("Ready for you now   : 5 (all of it)"), "full");
  ok(t.includes("Backordered Qty     : 48") && t.includes("In stock (Toronto)  : 30"), "501 both numbers");
  ok(t.startsWith("Dear Maple <script>alert(1)</script> Café 가게,"), "text keeps the name as is");
  ok(t.includes("the following backordered item(s) are now back in stock.") && !t.includes(" is now ") && t.includes("We will not be processing the backorder automatically."), "GAS wording · 515 ② are now");
  const NOTE = '"Ready for you now" is how much of your backorder we have in stock today. Stock is not reserved for you and may sell out before your new order is placed.';
  ok(t.includes(NOTE) && !/hold/i.test(t), "515 ① note in text · no 'hold' promise");
  const h = render("backorder_ready", PAYLOAD).body_html;
  ok(h.includes(NOTE.replace(/"/g, "&quot;")) && !/hold/i.test(h) && h.includes("are now back in stock."), "515 ① ② in HTML");
});
Deno.test("② HTML 이스케이프 — 이름 · 상품명의 < > & \" · 외부 이미지 · 스크립트 없음", () => {
  const h = render("backorder_ready", PAYLOAD).body_html;
  ok(!h.includes("<script>") && h.includes("&lt;script&gt;alert(1)&lt;/script&gt;"), "escaped name");
  ok(h.includes("Pan &amp; lid &quot;set&quot;"), "escaped product");
  ok(!/<img|src=|https?:\/\//i.test(h.replace(/www\.asung\.ca/g, "")), "no images or links");
});
Deno.test("③ Edmonton 제목 · 문장 · 빈 이름 → Customer · 이름 없는 상품 → SKU · 빈 줄 → 오류 · 모르는 kind → 오류", () => {
  const r = render("backorder_ready", { customer_name: "  ", location_name: "Asung - Edmonton", lines: [L("SO-1", 1, "X-1", null, 3, 3, null)] });
  eq(r.subject, "[Asung Trading] Backordered Item(s) Now Available in Edmonton", "edmonton subject");
  ok(r.body_text.startsWith("Dear Customer,") && r.body_text.includes("the following backordered item(s) are now available at our Edmonton location.") && !r.body_text.includes(" is now ") && r.body_html.includes("are now available at our Edmonton location.") && r.body_text.includes("Product             : X-1") && r.body_text.includes("In stock (Edmonton) : —"), "edmonton text");
  let e1 = ""; try { render("backorder_ready", { lines: [] }); } catch (e) { e1 = String(e); }
  let e2 = ""; try { render("po_mail", PAYLOAD); } catch (e) { e2 = String(e); }
  ok(e1.includes("no lines") && e2.includes("unknown mail kind po_mail"), "errors");
});
Deno.test("④ MIME — From 별칭 · 이름 · Reply-To · 한글 · → 제목은 RFC 2047 · 두 갈래 base64 · 줄바꿈 CRLF · 헤더 주입 막음", () => {
  const raw = buildMime({ from_name: "Asung Trading", from_address: "notifications@asung.ca", to: "c@example.invalid\r\nBcc: x@evil", reply_to: "info@asung.ca",
    subject: "[TEST → c@example.invalid] 안녕 é", text: "줄1\n줄2", html: "<p>é</p>", boundary: "B1" });
  const head = raw.split("\r\n\r\n")[0].split("\r\n");
  eq(head[0], 'From: "Asung Trading" <notifications@asung.ca>', "from");
  eq(head[1], "To: c@example.invalid Bcc: x@evil", "CRLF folded away — no new header");
  eq(head[2], "Reply-To: info@asung.ca", "reply-to");
  ok(head[3].startsWith("Subject: =?UTF-8?B?") && head[3].endsWith("?="), "encoded subject");
  eq(decodeB64(head[3].slice("Subject: =?UTF-8?B?".length, -2)), "[TEST → c@example.invalid] 안녕 é", "subject round trip");
  ok(raw.includes('Content-Type: multipart/alternative; boundary="B1"') && raw.includes("Content-Type: text/plain; charset=UTF-8") && raw.includes("Content-Type: text/html; charset=UTF-8") && raw.endsWith("--B1--\r\n"), "parts");
  const textB64 = raw.split("Content-Transfer-Encoding: base64\r\n\r\n")[1].split("--B1")[0];
  eq(decodeB64(textB64), "줄1\r\n줄2", "text part");
  eq(encodeWord("plain ascii"), "plain ascii", "ascii untouched");
  eq(mailbox("아성", "a@b.c").startsWith("=?UTF-8?B?"), true, "non-ascii display name");
  ok(!/[+/]/.test(base64url(raw)), "base64url alphabet");
});
const CFG = (o: Partial<MailConfig> = {}): MailConfig => ({ enabled: true, redirect_to: "ops@asung.ca", db_role: "test", mail_live: false, ...o });
Deno.test("⑤ 안전 네 갈래 — 시험 + 돌려 보내기 · 시험인데 주소 없음 · ref 와 db_role 어긋남(두 쪽) · 운영 정상 · 모르는 ref · 꺼짐", () => {
  eq(projectRef(`https://${TEST_REF}.supabase.co`), TEST_REF, "ref parse");
  const s1 = safety(CFG(), TEST_REF);
  eq(s1, { ok: true, test: true, redirect: "ops@asung.ca" }, "test + redirect");
  const m: ClaimedMail = { id: "m", kind: "backorder_ready", from_address: "n@asung.ca", from_name: null, reply_to: null, to_address: "cust@example.invalid", payload: PAYLOAD, attempt: 1 };
  if (s1.ok) eq(addressFor(m, s1, "S"), { to: "ops@asung.ca", original_to: "cust@example.invalid", subject: "[TEST → cust@example.invalid] S" }, "redirected");
  eq(safety(CFG({ redirect_to: null }), TEST_REF).ok, false, "test without redirect");
  eq((safety(CFG({ redirect_to: "me@gmail.com" }), TEST_REF) as { reason: string }).reason, "no_redirect", "test redirect outside asung.ca");
  eq((safety(CFG({ db_role: null }), TEST_REF) as { reason: string }).reason, "mismatch", "test ref but db_role missing");
  eq((safety(CFG(), PROD_REF) as { reason: string }).reason, "mismatch", "prod ref but db_role test");
  const s5 = safety(CFG({ db_role: "prod", redirect_to: null }), PROD_REF);
  eq(s5, { ok: true, test: false, redirect: null }, "prod normal");
  if (s5.ok) eq(addressFor(m, s5, "S"), { to: "cust@example.invalid", original_to: null, subject: "S" }, "prod sends to the customer");
  eq((safety(CFG(), "abcdefghijabcdefghij") as { reason: string }).reason, "unknown_project", "unknown ref");
  eq((safety(CFG({ enabled: false }), TEST_REF) as { reason: string }).reason, "disabled", "disabled");
});
Deno.test("⑥ 결과 갈래 — 2xx · 400 · 403(권한) · 403(rateLimit) · 401 · 429 · 500 · 503 · 시간 초과 · 연결 끊김 · 토큰 · id 없는 200", () => {
  const h = (status: number, body: unknown = {}): Outcome => ({ kind: "http", status, body: JSON.stringify(body) });
  const ge = (code: number, reason: string, message = "m") => ({ error: { code, message, errors: [{ reason }] } });
  const r = (o: Outcome) => classify(o).result;
  eq(classify(h(200, { id: "gm-1" })), { result: "sent", provider_message_id: "gm-1", error: null }, "200");
  eq([r(h(400, ge(400, "badRequest"))), r(h(403, ge(403, "domainPolicy"))), r(h(403, ge(403, "userRateLimitExceeded"))), r(h(403, ge(403, "dailyLimitExceeded"))), r(h(401, ge(401, "authError"))),
      r(h(429, { error: { code: 429, message: "Too many requests: User-rate limit exceeded (Mail sending)" } })), r(h(500, ge(500, "backendError"))), r(h(503))],
     ["failed", "failed", "retry", "retry", "retry", "retry", "retry", "retry"], "http");
  eq([r({ kind: "timeout" }), r({ kind: "network", message: "connection reset" }), r({ kind: "token", message: "invalid_grant" }), r(h(200, {}))], ["unknown", "unknown", "retry", "unknown"], "non-http");
  eq(classify(h(400, ge(400, "badRequest", "Invalid To header"))).error, "400 badRequest: Invalid To header", "error text");
});
function fakeDeps(o: { cfg?: MailConfig; ref?: string; mails?: ClaimedMail[]; send?: (raw: string) => Outcome; tokenFails?: boolean }) {
  const marks: { id: string; attempt: number; m: Mark; rendered: unknown }[] = [], sent: string[] = [], logs: string[] = [];
  let queue = [...(o.mails ?? [])], claims = 0, tokens = 0;
  const cfg = o.cfg ?? CFG();
  const d: Deps = {
    ref: o.ref ?? TEST_REF,
    readConfig: () => Promise.resolve(cfg),
    claim: (n) => { claims++; const take = cfg.enabled ? queue.slice(0, n) : []; queue = cfg.enabled ? queue.slice(n) : queue; return Promise.resolve({ ...cfg, mails: take }); },
    mark: (id, attempt, m, rendered) => { marks.push({ id, attempt, m, rendered }); return Promise.resolve(); },
    token: () => { tokens++; return o.tokenFails ? Promise.reject(new Error("token endpoint 400 invalid_grant")) : Promise.resolve("tok"); },
    send: (_t, raw) => { sent.push(raw); return Promise.resolve(o.send ? o.send(raw) : { kind: "http", status: 200, body: JSON.stringify({ id: "gm-" + sent.length }) }); },
    now: () => 0,
    log: (s) => logs.push(s),
    loadDoc: (id) => Promise.reject(new Error("loadDoc called for " + id + " — a backorder test must not load a document")),
    readAttachment: (a) => Promise.reject(new Error("readAttachment called for " + a.path)),
  };
  return { d, marks, sent, logs, claims: () => claims, tokens: () => tokens };
}
const mail = (id: string, attempt = 1): ClaimedMail => ({ id, kind: "backorder_ready", from_address: "notifications@asung.ca", from_name: "Asung Trading", reply_to: "info@asung.ca", to_address: id + "@example.invalid", payload: PAYLOAD, attempt });
const opt = { batch: 2, budgetMs: 1000, boundary: () => "B" };
Deno.test("⑦ drain — 시험 DB: 셋 다 돌려 보냄 · mark(sent · rendered 의 to = ops · original_to = 손님 · 제목 [TEST →]) · 시도 번호 그대로 · 열쇠 한 번", async () => {
  const f = fakeDeps({ mails: [mail("a"), mail("b", 3), mail("c")] });
  const out = await drain(f.d, opt);
  eq(out.counts, { sent: 3, failed: 0, retry: 0, unknown: 0 }, "counts");
  eq(f.marks.map((x) => [x.id, x.attempt, x.m.result]), [["a", 1, "sent"], ["b", 3, "sent"], ["c", 1, "sent"]], "marks");
  const rd = f.marks[0].rendered as { to_address: string; original_to: string; subject: string };
  eq([rd.to_address, rd.original_to, rd.subject.startsWith("[TEST → a@example.invalid] ")], ["ops@asung.ca", "a@example.invalid", true], "redirect recorded");
  ok(f.sent.every((raw) => decodeB64(raw.replace(/-/g, "+").replace(/_/g, "/")).includes("To: ops@asung.ca")), "every raw goes to ops@asung.ca");
  eq(f.tokens(), 1, "token reused");
});
Deno.test("⑧ drain — 어긋남 · 주소 없음 · 모르는 ref 는 집지도 않는다 · 꺼짐은 claim 한 번(멈춤 되살리기만) · 보낸 것 0", async () => {
  for (const [cfg, ref, status] of [[CFG({ db_role: "prod" }), TEST_REF, "mismatch"], [CFG({ redirect_to: null }), TEST_REF, "no_redirect"], [CFG(), "abcdefghijabcdefghij", "unknown_project"]] as const) {
    const f = fakeDeps({ cfg, ref, mails: [mail("a")] });
    const out = await drain(f.d, opt);
    eq([out.ok, out.status, f.claims(), f.sent.length, f.marks.length], [false, status, 0, 0, 0], "refused " + status);
  }
  const off = fakeDeps({ cfg: CFG({ enabled: false }), mails: [mail("a")] });
  const o2 = await drain(off.d, opt);
  eq([o2.ok, o2.status, off.claims(), off.sent.length], [true, "disabled", 1, 0], "disabled");
});
Deno.test("⑨ drain — 결과마다 mark: 400 failed · 429 retry · 시간 초과 unknown · 토큰 실패면 보내지 않고 남은 것 전부 retry", async () => {
  const outs: Outcome[] = [{ kind: "http", status: 400, body: JSON.stringify({ error: { message: "Invalid To header", errors: [{ reason: "badRequest" }] } }) }, { kind: "http", status: 429, body: "{}" }, { kind: "timeout" }];
  let i = 0;
  const f = fakeDeps({ mails: [mail("a"), mail("b"), mail("c")], send: () => outs[i++] });
  await drain(f.d, opt);
  eq(f.marks.map((x) => [x.id, x.m.result, x.rendered === null]), [["a", "failed", true], ["b", "retry", true], ["c", "unknown", true]], "per result · rendered only on sent");
  const t = fakeDeps({ mails: [mail("a"), mail("b"), mail("c")], tokenFails: true });
  const o = await drain(t.d, opt);
  eq([t.sent.length, t.marks.map((x) => x.m.result), t.tokens(), t.claims()], [0, ["retry", "retry"], 1, 1], "token broken: no send · this batch retried · token asked once · no further claim");
  ok(t.marks[0].m.error!.startsWith("token: ") && t.logs.some((s) => s.includes("token problem")) && o.ok, "loud");
});
Deno.test("⑩ Chat 요약 — 보낸 날 · 0 통인 날 · reason 낱말 · 이메일 주소 없음 · 길면 자른다", () => {
  const run = { run_id: "r", location_name: "Asung Trading Inc.", run_on: "2026-10-19", mails: 2, by_status: { sent: 1, unknown: 1 }, skipped: { no_email: 1, paused: 1 } };
  const t = chatText(run, [{ status: "sent", customer_name: "Maple Store", lines: [{ so_number: "SO-1", sku: "A" }, { so_number: "SO-1", sku: "B" }, { so_number: "SO-2", sku: "C" }] },
    { status: "unknown", customer_name: "Oak Mart", lines: [{ so_number: "SO-3", sku: "D" }] }], [{ name: "Pine Co", reason: "no_email" }, { name: "Elm Ltd", reason: "paused" }], true);
  eq(t.split("\n"), ["[TEST] Backorder mail — Toronto · 2026-10-19", "Sent 1 · Failed 0 · Unknown 1 · Cancelled 0 · Not sent: no email 1 · alerts off 1",
    "• Maple Store — SO-1: A, B; SO-2: C", "• Oak Mart [unknown] — SO-3: D", "• Pine Co — not sent (no email)", "• Elm Ltd — not sent (alerts off)"], "sent day");
  ok(!t.includes("@"), "no email addresses");
  eq(chatText({ ...run, location_name: "Asung - Edmonton", mails: 0, by_status: {}, skipped: {} }, [], [], false), "Backorder mail — Edmonton · 2026-10-19 — nothing to send.", "zero day");
  const long = chatText(run, Array.from({ length: 200 }, (_, k) => ({ status: "sent", customer_name: "Customer " + k, lines: [{ so_number: "SO-" + k, sku: "SKU" }] })), [], false, 500);
  ok(long.length < 560 && /… and \d+ more$/.test(long), "cut");
});
Deno.test("⑪ 회차 실패 Chat 한 줄(판정 518) — 창고 · 날짜 · 요지 · [TEST] · 이메일 · 열쇠 모양 지움 · 길면 자름 · 빈 문장", () => {
  const e = { error_id: 1, location_name: "Asung - Edmonton", run_on: "2026-10-19", attempts: 1,
    message: "duplicate key value violates unique constraint \"mail_outbox_to_ck\" Key (to_address)=(" + ["someone", "example.invalid"].join("@") + ") token " + "abcdefghij".repeat(4) };   // 이메일 · 열쇠 모양은 돌 때 만든다(레포에 그 모양을 두지 않는다)
  const t1 = errorChatText(e, true);
  ok(t1.startsWith("[TEST] ⚠️ Backorder mail — Edmonton · 2026-10-19 — run failed (duplicate key value violates unique constraint"), "head");
  ok(!t1.includes("@") && t1.includes("<email>") && !/[A-Za-z0-9_-]{32,}/.test(t1) && t1.includes("<…>"), "no email · no key-like token");
  eq(errorChatText({ ...e, location_name: "Asung Trading Inc.", message: "abc ".repeat(150) }, false).length, "⚠️ Backorder mail — Toronto · 2026-10-19 — run failed ()".length + 200, "cut to 200");
  ok(errorChatText({ ...e, location_name: "Asung Trading Inc.", message: "abc ".repeat(150) }, false).endsWith("…)"), "ellipsis");
  eq(errorChatText({ ...e, location_name: "Asung Trading Inc.", message: null }, false), "⚠️ Backorder mail — Toronto · 2026-10-19 — run failed (no message)", "empty");
  eq(errorChatText({ ...e, location_name: "Asung Trading Inc.", message: "  line one\n   line two  " }, false), "⚠️ Backorder mail — Toronto · 2026-10-19 — run failed (line one line two)", "whitespace folded");
});

// ── doc-3b(2026-10-19) — 문서 메일: MIME 무변(황금 문자열) · 첨부 MIME · doc_* 그리기 · drain 의 doc 갈래 · PDF 단계 ──
const GOLDEN_IN = { from_name: "Asung Trading", from_address: "notifications@asung.ca", to: "ops@asung.ca", reply_to: "info@asung.ca", subject: "[TEST → c@example.invalid] 안녕 é", text: "줄1\n줄2 & <b>", html: "<p>é</p>", boundary: "B1" };
// mail-2b 코드(de276c8 시점 · 첨부 칸이 생기기 전)가 만든 바이트 — 2026-10-19 deno 2.9.6 실측 sha256 935c24c3…c87fe · 454 자. 바뀌면 백오더 메일 MIME 이 바뀐 것이다.
const GOLDEN_RAW = "From: \"Asung Trading\" <notifications@asung.ca>\r\nTo: ops@asung.ca\r\nReply-To: info@asung.ca\r\nSubject: =?UTF-8?B?W1RFU1Qg4oaSIGNAZXhhbXBsZS5pbnZhbGlkXSDslYjrhZUgw6k=?=\r\nMIME-Version: 1.0\r\nContent-Type: multipart/alternative; boundary=\"B1\"\r\n\r\n--B1\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n7KSEMQ0K7KSEMiAmIDxiPg==\r\n--B1\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\nPHA+w6k8L3A+\r\n--B1--\r\n";
const PDF_BYTES = new TextEncoder().encode("%PDF-1.4\n% doc-3b fake pdf é\n%%EOF\n");
Deno.test("⑫ MIME 무변 — 첨부 없음(undefined · []) 은 mail-2b 황금 문자열과 바이트가 같다 · sha256 같다 · 큰 본문(덩이 base64)도 같다", async () => {
  const raw = buildMime(GOLDEN_IN);
  eq(raw, GOLDEN_RAW, "golden bytes (no attachments)");
  eq(buildMime({ ...GOLDEN_IN, attachments: [] }), GOLDEN_RAW, "golden bytes (empty attachments)");
  eq(await sha256Hex(new TextEncoder().encode(raw)), "935c24c32d2a799841a02df0548eb0765d1dd354c3afcbb366915918a04c87fe", "golden sha256");
  const big = "x".repeat(100_000) + "é";                                                           // 32768 덩이 경계를 넘긴다
  const b = buildMime({ ...GOLDEN_IN, text: big, html: big }).split("Content-Transfer-Encoding: base64\r\n\r\n")[1].split("--B1")[0];
  eq(decodeB64(b), big, "chunked base64 round trip");
});
Deno.test("⑬ MIME 첨부 — 바깥 multipart/mixed · 안 alternative 는 황금의 두 갈래 그대로(경계 이름만) · application/pdf base64 · Content-Disposition attachment · 파일 이름 ASCII 로 · 바이트 왕복", () => {
  const raw = buildMime({ ...GOLDEN_IN, attachments: [{ filename: "60009-t1-20261019T181014Z.pdf", bytes: PDF_BYTES }, { filename: "크레딧 \"x\"; y.pdf", bytes: PDF_BYTES }] });
  const head = raw.split("\r\n\r\n")[0].split("\r\n");
  eq(head.slice(0, 5), GOLDEN_RAW.split("\r\n\r\n")[0].split("\r\n").slice(0, 5), "From · To · Reply-To · Subject · MIME-Version same as golden");
  eq(head[5], 'Content-Type: multipart/mixed; boundary="B1"', "outer mixed");
  const goldenBody = GOLDEN_RAW.split("\r\n\r\n").slice(1).join("\r\n\r\n");
  ok(raw.includes('--B1\r\nContent-Type: multipart/alternative; boundary="B1-alt"\r\n\r\n' + goldenBody.replace(/--B1/g, "--B1-alt")), "inner alternative = golden parts with the inner boundary");
  ok(raw.includes('Content-Type: application/pdf; name="60009-t1-20261019T181014Z.pdf"\r\nContent-Transfer-Encoding: base64\r\nContent-Disposition: attachment; filename="60009-t1-20261019T181014Z.pdf"\r\n\r\n'), "pdf part headers");
  ok(raw.includes('filename="___ _x__ y.pdf"'), "non-ascii · quotes · semicolon replaced");
  const pdfB64 = raw.split('filename="60009-t1-20261019T181014Z.pdf"\r\n\r\n')[1].split("\r\n--B1")[0];
  eq(Array.from(Uint8Array.from(atob(pdfB64.replace(/\r\n/g, "")), (ch) => ch.charCodeAt(0))), Array.from(PDF_BYTES), "pdf bytes round trip");
  ok(raw.endsWith("--B1--\r\n") && (raw.match(/\r\n--B1\r\n/g) ?? []).length === 3, "three outer parts · closed");
});
Deno.test("⑭ doc_* 그리기 — 줄의 제목 · 본문 그대로 · HTML 은 이스케이프 + pre-wrap · 제목 없음 → 오류 · backorder_ready 는 전과 같다 · 모르는 kind 오류", () => {
  const r = render("doc_final_invoice", {}, { subject: " FINAL INVOICE 60009 - Asung Trading Inc. ", body_text: "Dear A & B,\n\nPlease find <attached>." });
  eq(r.subject, "FINAL INVOICE 60009 - Asung Trading Inc.", "subject trimmed");
  eq(r.body_text, "Dear A & B,\n\nPlease find <attached>.", "text as is");
  ok(r.body_html.includes("Dear A &amp; B,\n\nPlease find &lt;attached&gt;.") && r.body_html.includes("white-space:pre-wrap") && !/<script|src=/i.test(r.body_html), "html escaped");
  let e1 = ""; try { render("doc_credit_note", {}, { subject: "", body_text: "x" }); } catch (e) { e1 = String(e); }
  let e2 = ""; try { render("doc_sales_order", {}); } catch (e) { e2 = String(e); }
  ok(e1.includes("no subject or body") && e2.includes("no subject or body"), "missing → error");
  eq(render("backorder_ready", PAYLOAD).subject, "[Asung Trading] Backordered Item(s) Now Back In Stock", "backorder untouched");
  eq(isDocKind("doc_ship_ready") && !isDocKind("backorder_ready") && !isDocKind("doc_internal_receipt"), true, "doc kinds");
});
const PDF_SHA = await sha256Hex(PDF_BYTES);
const ATT = (over: Partial<Attachment> = {}): Attachment => ({ doc_file_id: "f1", path: "final_invoice/60009-t1-20261019T181014Z.pdf", filename: "60009-t1-20261019T181014Z.pdf", bytes: PDF_BYTES.length, sha256: PDF_SHA, ...over });
const docMail = (id: string, subject = "FINAL INVOICE 60009 - Asung Trading Inc."): ClaimedMail => ({ id, kind: "doc_final_invoice", from_address: "info@asung.ca", from_name: "Asung Trading", reply_to: "info@asung.ca", to_address: id + "@example.invalid", payload: {}, attempt: 1, subject });
function docDeps(o: { docs: Record<string, DocBody>; read?: (a: Attachment) => AttachmentRead; mails: ClaimedMail[] }) {
  const f = fakeDeps({ mails: o.mails });
  const reads: string[] = [];
  f.d.loadDoc = (id) => Promise.resolve(o.docs[id] ?? { body_text: null, attachments: [] });
  f.d.readAttachment = (a) => { reads.push(a.path); return Promise.resolve(o.read ? o.read(a) : { ok: true, bytes: PDF_BYTES }); };
  return { ...f, reads };
}
Deno.test("⑮ drain 의 doc 갈래 — 문서 메일은 줄의 글 + Storage 의 PDF 로 mixed MIME · 돌려 보내기 그대로 · rendered 에 글 · 백오더 메일은 loadDoc 을 부르지 않는다 · 첨부 없음 failed · 본문 없음 failed · sha 틀림 failed · Storage 5xx retry · 404 failed", async () => {
  const body = "Dear Customer,\n\nPlease find attached your final invoice 60009.";
  const f = docDeps({ mails: [docMail("d1"), mail("b1")], docs: { d1: { body_text: body, attachments: [ATT()] } } });
  const out = await drain(f.d, opt);
  eq(out.counts, { sent: 2, failed: 0, retry: 0, unknown: 0 }, "both sent");
  const raw = decodeB64(f.sent[0].replace(/-/g, "+").replace(/_/g, "/"));
  ok(raw.includes("Content-Type: multipart/mixed;") && raw.includes('Content-Disposition: attachment; filename="60009-t1-20261019T181014Z.pdf"') && raw.includes("To: ops@asung.ca") && raw.includes('From: "Asung Trading" <info@asung.ca>'), "doc mail: mixed · attachment · redirected · from info@");
  ok(decodeB64(raw.split("Subject: =?UTF-8?B?")[1].split("?=")[0]).startsWith("[TEST → d1@example.invalid] FINAL INVOICE 60009"), "subject with redirect tag");
  const rd = f.marks[0].rendered as { body_text: string; to_address: string; original_to: string };
  eq([rd.body_text, rd.to_address, rd.original_to], [body, "ops@asung.ca", "d1@example.invalid"], "rendered on sent");
  const raw2 = decodeB64(f.sent[1].replace(/-/g, "+").replace(/_/g, "/"));
  ok(raw2.includes("Content-Type: multipart/alternative;") && !raw2.includes("multipart/mixed") && f.reads.length === 1, "backorder mail unchanged · one storage read in total");
  const bad = docDeps({ mails: [docMail("n1"), docMail("b2", ""), docMail("s1"), docMail("r1"), docMail("m1")],
    docs: { n1: { body_text: body, attachments: [] }, b2: { body_text: body, attachments: [ATT()] }, s1: { body_text: body, attachments: [ATT({ sha256: "00" })] }, r1: { body_text: body, attachments: [ATT({ path: "x/retry.pdf" })] }, m1: { body_text: body, attachments: [ATT({ path: "x/missing.pdf" })] } },
    read: (a) => a.path === "x/retry.pdf" ? { ok: false, retry: true, error: "storage 503" } : a.path === "x/missing.pdf" ? { ok: false, retry: false, error: "storage 404" } : { ok: true, bytes: PDF_BYTES } });
  const o2 = await drain(bad.d, { ...opt, batch: 5 });
  eq(bad.marks.map((x) => [x.id, x.m.result]), [["n1", "failed"], ["b2", "failed"], ["s1", "failed"], ["r1", "retry"], ["m1", "failed"]], "per fault");
  ok(bad.marks[0].m.error!.includes("no attachment") && bad.marks[1].m.error!.includes("no subject or body") && bad.marks[2].m.error!.includes("sha256") && bad.marks[3].m.error!.includes("storage 503") && bad.sent.length === 0, "errors named · nothing sent");
  eq(o2.counts, { sent: 0, failed: 4, retry: 1, unknown: 0 }, "counts");
});
Deno.test("⑯ PDF 단계 — 집기 → doc render → attach(queued) · render 실패 → pdf_failed · attach 실패 → pdf_failed · ship_ready 는 일꾼이 안 만든다 · 예산 안에서 다시 집는다 · 꺼짐이면 집지 않는다", async () => {
  const jobs: PdfJob[][] = [[{ outbox_id: "a", doc_kind: "final_invoice", ref: { invoice_id: "i1" }, attempts: 0 }, { outbox_id: "b", doc_kind: "credit_note", ref: { credit_id: "c1" }, attempts: 2 }, { outbox_id: "c", doc_kind: "ship_ready", ref: {}, attempts: 0 }], [{ outbox_id: "d", doc_kind: "sales_order", ref: { so_id: "s1" }, attempts: 0 }], []];
  const attached: [string, string][] = [], failed: [string, string][] = [], rendered: string[] = [];
  let claims = 0, t = 0;
  const d: PdfDeps = {
    readConfig: () => Promise.resolve(CFG()),
    claim: () => Promise.resolve(jobs[claims++] ?? []),
    render: (kind, ref) => { rendered.push(kind + ":" + JSON.stringify(ref)); return Promise.resolve(kind === "credit_note" ? { ok: false, error: "doc 500: Gotenberg 503" } : { ok: true, doc_file_id: "pdf-" + kind }); },
    attach: (id, f) => { if (id === "d") return Promise.reject(new Error("rpc/doc_mail_attach 400: this one is cancelled")); attached.push([id, f]); return Promise.resolve(); },
    failed: (id, e) => { failed.push([id, e]); return Promise.resolve(); },
    now: () => (t += 100),
    log: () => {},
  };
  const out = await pdfStep(d, { batch: 3, budgetMs: 10_000 });
  eq(out, { ok: true, status: "done", counts: { attached: 1, failed: 3 } }, "counts");
  eq(attached, [["a", "pdf-final_invoice"]], "attached");
  eq(failed.map(([id]) => id), ["b", "c", "d"], "failed ids");
  ok(failed[0][1].includes("Gotenberg 503") && failed[1][1].includes("Ship Ready") && failed[2][1].startsWith("attach: ") && failed[2][1].includes("cancelled"), "failure texts");
  eq([rendered, claims], [['final_invoice:{"invoice_id":"i1"}', 'credit_note:{"credit_id":"c1"}', 'sales_order:{"so_id":"s1"}'], 3], "ship_ready not rendered · claimed until empty");
  let c2 = 0;
  const off = await pdfStep({ ...d, readConfig: () => Promise.resolve(CFG({ enabled: false })), claim: () => { c2++; return Promise.resolve([]); } }, { batch: 3, budgetMs: 10_000 });
  eq([off.status, c2], ["disabled", 0], "disabled: no claim");
  let c3 = 0, t3 = 0;
  const tight = await pdfStep({ ...d, claim: () => { c3++; return Promise.resolve([{ outbox_id: "z" + c3, doc_kind: "final_invoice", ref: {}, attempts: 0 }]); }, attach: () => Promise.resolve(), now: () => (t3 += 6_000) }, { batch: 1, budgetMs: 10_000 });
  eq([tight.counts.attached, c3], [1, 1], "budget: one batch then stop");
});

Deno.test("⑰ qbo-1b 알림 그리기 — kind qbo_reconnect 는 payload 의 subject · body_text 그대로(HTML 은 이스케이프 + pre-wrap) · 둘 중 하나 없으면 오류 · doc · backorder 는 전과 같다 · 모르는 kind 는 여전히 오류", () => {
  const p = { subject: "[IMS] QuickBooks connection needs attention (sandbox)", body_text: "QuickBooks stopped accepting the IMS connection.\n\nReason:   HTTP 400 invalid_grant <token & more>\n\nOpen IMS -> Settings -> QuickBooks and click Reconnect (admin only)." };
  eq(isPlainKind("qbo_reconnect"), true, "plain kind");
  eq([isPlainKind("doc_final_invoice"), isPlainKind("backorder_ready"), isDocKind("qbo_reconnect")], [false, false, false], "not doc · not backorder");
  const r = render("qbo_reconnect", p);
  eq([r.subject, r.body_text === p.body_text, r.body_html.includes("&lt;token &amp; more&gt;"), r.body_html.includes("pre-wrap"), r.body_html.includes("<script")], [p.subject, true, true, true, false], "rendered from payload · escaped");
  eq(JSON.stringify(renderPlain(p)) === JSON.stringify(r), true, "renderPlain = render");
  let e1 = ""; try { render("qbo_reconnect", { subject: "x" }); } catch (e) { e1 = String(e); }
  let e2 = ""; try { render("qbo_reconnect", { body_text: "x" }); } catch (e) { e2 = String(e); }
  let e3 = ""; try { render("qbo_nope", p); } catch (e) { e3 = String(e); }
  eq([e1.includes("no subject or body_text"), e2.includes("no subject or body_text"), e3.includes("unknown mail kind")], [true, true, true], "errors");
});

Deno.test("⑱ mail-live-1(판정 617 · 947) — 시험 ref 라도 mail_live 면 운영 갈래: redirect 유지 → to redirect · 제목 [REDIRECT → 손님](TEST 아님) · redirect 없음 → 손님에게 · gmail 주소도 됨 · db_role 표지 없으면 여전히 mismatch · testMode · drain · Chat 표지 없음", async () => {
  const m: ClaimedMail = { id: "m", kind: "backorder_ready", from_address: "n@asung.ca", from_name: null, reply_to: null, to_address: "cust@example.invalid", payload: PAYLOAD, attempt: 1 };
  const live = safety(CFG({ mail_live: true }), TEST_REF);
  eq(live, { ok: true, test: false, redirect: "ops@asung.ca" }, "live + redirect kept → production branch with redirect");
  if (live.ok) eq(addressFor(m, live, "S"), { to: "ops@asung.ca", original_to: "cust@example.invalid", subject: "[REDIRECT → cust@example.invalid] S" }, "subject says REDIRECT, not TEST");
  const direct = safety(CFG({ mail_live: true, redirect_to: null }), TEST_REF);
  eq(direct, { ok: true, test: false, redirect: null }, "live without redirect");
  if (direct.ok) eq(addressFor(m, direct, "S"), { to: "cust@example.invalid", original_to: null, subject: "S" }, "goes to the customer");
  eq(safety(CFG({ mail_live: true, redirect_to: "me@gmail.com" }), TEST_REF), { ok: true, test: false, redirect: "me@gmail.com" }, "live: any one address");
  eq((safety(CFG({ mail_live: true, db_role: null }), TEST_REF) as { reason: string }).reason, "mismatch", "live but db_role marker missing → still mismatch");
  eq((safety(CFG({ mail_live: true, db_role: "prod" }), TEST_REF) as { reason: string }).reason, "mismatch", "live but db_role prod on test ref → mismatch");
  eq((safety(CFG({ mail_live: true, enabled: false }), TEST_REF) as { reason: string }).reason, "disabled", "live but off");
  eq((safety(CFG({ mail_live: true, redirect_to: "a@b.c, d@e.f" }), TEST_REF) as { reason: string }).reason, "no_redirect", "live: two addresses refused");
  eq(safety(CFG({ mail_live: false, redirect_to: null }), TEST_REF).ok, false, "not live: test rules unchanged");
  eq([testMode(CFG(), TEST_REF), testMode(CFG({ mail_live: true }), TEST_REF), testMode(CFG({ db_role: "prod", mail_live: false }), PROD_REF), testMode(CFG({ db_role: "prod", mail_live: true }), PROD_REF)], [true, false, false, false], "testMode");
  const f = fakeDeps({ cfg: CFG({ mail_live: true }), mails: [mail("a"), mail("b")] });
  const out = await drain(f.d, opt);
  eq(out.counts, { sent: 2, failed: 0, retry: 0, unknown: 0 }, "drain live + redirect: sent");
  const rd = f.marks[0].rendered as { to_address: string; original_to: string; subject: string };
  eq([rd.to_address, rd.original_to, rd.subject.startsWith("[REDIRECT → a@example.invalid] "), rd.subject.includes("[TEST")], ["ops@asung.ca", "a@example.invalid", true, false], "redirect recorded as REDIRECT");
  const g = fakeDeps({ cfg: CFG({ mail_live: true, redirect_to: null }), mails: [mail("a")] });
  await drain(g.d, opt);
  const rd2 = g.marks[0].rendered as { to_address: string; original_to: string | null; subject: string };
  eq([rd2.to_address, rd2.original_to, rd2.subject.includes("→")], ["a@example.invalid", null, false], "live without redirect: straight to the customer · no redirect marker in the subject");
  ok(g.sent.every((raw) => decodeB64(raw.replace(/-/g, "+").replace(/_/g, "/")).includes("To: a@example.invalid")), "raw To is the customer");
  const run = { run_id: "r", location_name: "Asung Trading Inc.", run_on: "2026-11-02", mails: 0, by_status: {}, skipped: {} };
  eq(chatText(run, [], [], testMode(CFG({ mail_live: true }), TEST_REF)), "Backorder mail — Toronto · 2026-11-02 — nothing to send.", "chat without [TEST]");
});

Deno.test("⑲ aone-bo-1(판정 948 ⑥) — Chat 요약에 aonebeauty.com 줄 수 한 줄: 0 · 없음이면 안 보임 · 보낸 날은 Sent 줄 뒤 · 0 통인 날은 nothing to send 뒤", () => {
  const run = { run_id: "r", location_name: "Asung Trading Inc.", run_on: "2026-11-02", mails: 1, by_status: { sent: 1 }, skipped: {} };
  const m = [{ status: "sent", customer_name: "Maple Store", lines: [{ so_number: "SO-1", sku: "A" }] }];
  eq(chatText({ ...run, aone_lines: 2 }, m, [], false).split("\n"), ["Backorder mail — Toronto · 2026-11-02", "Sent 1 · Failed 0 · Unknown 0 · Cancelled 0", "aonebeauty.com: 2 backorder line(s) left out of the automatic run — staff send those by hand", "• Maple Store — SO-1: A"], "sent day with aone line");
  eq(chatText({ ...run, aone_lines: 0 }, m, [], false).includes("aonebeauty"), false, "zero → no line");
  eq(chatText(run, m, [], false).includes("aonebeauty"), false, "absent → no line");
  eq(chatText({ ...run, mails: 0, by_status: {}, aone_lines: 3 }, [], [], false), "Backorder mail — Toronto · 2026-11-02 — nothing to send.\naonebeauty.com: 3 backorder line(s) left out of the automatic run — staff send those by hand", "nothing-to-send day with aone line");
});

// ── mail-inc-1b(2026-11-07 · 판정 1019 · 1027 · 1028 · 1029) — 받는 이 여럿: to_more 를 To 에 · 황금 둘(⑫ 백오더 · ⑳ 문서) 세 꼴(없음 · [] · null) 무변 ──
const rawOf = (b64url: string) => decodeB64(b64url.replace(/-/g, "+").replace(/_/g, "/"));
// 바꾸기 전 판(b9b14d6 시점 · to_more 가 생기기 전)의 drain doc 갈래가 만든 바이트 전체 — 2026-11-07 deno 2.9.8 실측 sha256 55b9fd7d…feb25 · 1182 자. 바뀌면 문서 메일 MIME 이 바뀐 것이다.
const GOLDEN20_RAW = "From: \"Asung Trading\" <info@asung.ca>\r\nTo: ops@asung.ca\r\nReply-To: info@asung.ca\r\nSubject: =?UTF-8?B?W1RFU1Qg4oaSIGQxQGV4YW1wbGUuaW52YWxpZF0gRklOQUwgSU5WT0lDRSA2MDAwOSAtIEFzdW5nIFRyYWRpbmcgSW5jLg==?=\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=\"B\"\r\n\r\n--B\r\nContent-Type: multipart/alternative; boundary=\"B-alt\"\r\n\r\n--B-alt\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\nRGVhciBDdXN0b21lciwNCg0KUGxlYXNlIGZpbmQgYXR0YWNoZWQgeW91ciBmaW5hbCBpbnZvaWNl\r\nIDYwMDA5Lg==\r\n--B-alt\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\nPCFkb2N0eXBlIGh0bWw+PGh0bWw+PGJvZHkgc3R5bGU9ImZvbnQtZmFtaWx5OkFyaWFsLHNhbnMt\r\nc2VyaWY7Zm9udC1zaXplOjE0cHgiPjxwcmUgc3R5bGU9ImZvbnQtZmFtaWx5OkFyaWFsLHNhbnMt\r\nc2VyaWY7Zm9udC1zaXplOjE0cHg7d2hpdGUtc3BhY2U6cHJlLXdyYXAiPkRlYXIgQ3VzdG9tZXIs\r\nDQoNClBsZWFzZSBmaW5kIGF0dGFjaGVkIHlvdXIgZmluYWwgaW52b2ljZSA2MDAwOS48L3ByZT48\r\nL2JvZHk+PC9odG1sPg==\r\n--B-alt--\r\n--B\r\nContent-Type: application/pdf; name=\"60009-t1-20261019T181014Z.pdf\"\r\nContent-Transfer-Encoding: base64\r\nContent-Disposition: attachment; filename=\"60009-t1-20261019T181014Z.pdf\"\r\n\r\nJVBERi0xLjQKJSBkb2MtM2IgZmFrZSBwZGYgw6kKJSVFT0YK\r\n--B--\r\n";
const GOLDEN20_SHA = "55b9fd7d273c76b79a6ef50f87e36befb53a6504736cdb5faf4c805b4a1feb25";
const GOLDEN_BO_SHA = "f38103f0e52fe0f70614dc9e25dba018f52c1af37bd6bf3a0343c2dd0ed77bad";   // 같은 시점 · drain 백오더 갈래(mail("a") · 시험 모드 · boundary B) 의 raw sha256 · 7166 자
const DOC_BODY = "Dear Customer,\n\nPlease find attached your final invoice 60009.";
Deno.test("⑳ MIME 무변(문서 메일) — drain doc 갈래의 raw 전체가 바꾸기 전 황금과 바이트가 같다 · to_more 없음 · [] · null 세 꼴 모두 · 백오더 갈래 raw 도 세 꼴 같고 sha 가 바꾸기 전과 같다", async () => {
  const docRaws: string[] = [], boRaws: string[] = [];
  for (const more of [undefined, [], null] as const) {
    const dm = { ...docMail("d1"), ...(more === undefined ? {} : { to_more: more }) } as ClaimedMail;
    const f = docDeps({ mails: [dm], docs: { d1: { body_text: DOC_BODY, attachments: [ATT()] } } });
    eq((await drain(f.d, opt)).counts, { sent: 1, failed: 0, retry: 0, unknown: 0 }, "doc sent (" + String(more) + ")");
    docRaws.push(rawOf(f.sent[0]));
    const bm = { ...mail("a"), ...(more === undefined ? {} : { to_more: more }) } as ClaimedMail;
    const g = fakeDeps({ mails: [bm] });
    eq((await drain(g.d, opt)).counts, { sent: 1, failed: 0, retry: 0, unknown: 0 }, "backorder sent (" + String(more) + ")");
    boRaws.push(rawOf(g.sent[0]));
  }
  eq(docRaws[0], GOLDEN20_RAW, "doc golden bytes (to_more absent)");
  eq(docRaws[1], GOLDEN20_RAW, "doc golden bytes (to_more [])");
  eq(docRaws[2], GOLDEN20_RAW, "doc golden bytes (to_more null)");
  eq(await sha256Hex(new TextEncoder().encode(docRaws[0])), GOLDEN20_SHA, "doc golden sha256");
  eq(docRaws[0].length, 1182, "doc golden length");
  ok(boRaws[0] === boRaws[1] && boRaws[1] === boRaws[2], "backorder raw identical across the three shapes");
  eq(await sha256Hex(new TextEncoder().encode(boRaws[0])), GOLDEN_BO_SHA, "backorder raw sha256 = before the change");
  eq(boRaws[0].length, 7166, "backorder raw length");
});
Deno.test("㉑ 받는 이 여럿 — recipients: 1 · 9(합 10) · 10(합 11 failed) · 겹침(대소문자) 한 번 · 주입 CR LF · 꼴 아님 · < > · 배열 아님 · to_address 도 검사 / drain: 운영 To 모두(`, `) · rendered.to_address 첫 주소 · redirect 한 통 · 제목 [TEST|REDIRECT → 모두] · redirect ∈ to_more 면 failed · 아무것도 안 보냄", async () => {
  const to = "a@example.invalid";
  const more = (n: number) => Array.from({ length: n }, (_, i) => `m${i + 1}@example.invalid`);
  eq(recipients({ to_address: to }), { ok: true, all: [to], more: [] }, "no to_more");
  eq(recipients({ to_address: to, to_more: null }), { ok: true, all: [to], more: [] }, "null");
  eq(recipients({ to_address: to, to_more: ["B@example.invalid"] }), { ok: true, all: [to, "B@example.invalid"], more: ["B@example.invalid"] }, "one more · case kept");
  eq(recipients({ to_address: to, to_more: more(9) }).ok, true, "9 more = 10 ok");
  eq(MAX_RECIPIENTS, 10, "cap 10");
  eq(recipients({ to_address: to, to_more: more(10) }), { ok: false, error: "11 recipients — the limit is 10 — the row was not sent" }, "10 more = 11 failed");
  eq(recipients({ to_address: to, to_more: ["A@EXAMPLE.invalid", "b@x.ca", " B@X.CA "] }), { ok: true, all: [to, "b@x.ca"], more: ["b@x.ca"] }, "duplicates (case · spaces) once · to_address dup dropped");
  eq(recipients({ to_address: to, to_more: ["b@x.ca", "z@y.ca\r\nBcc: evil@example.invalid"] }), { ok: false, error: "recipient 3 of 3 is not a usable address — the row was not sent" }, "header injection → failed · no address in the error");
  for (const bad of ["no-at", "a@b", "a b@x.ca", "a,b@x.ca", "a@x.ca;", "a<b@x.ca", "x>@y.ca", "\"q\"@x.ca", "a(b)@x.ca", "a:b@x.ca", "a\\b@x.ca", "", "   "]) {
    const r = recipients({ to_address: to, to_more: [bad] });
    eq(r.ok ? "ok" : r.error, "recipient 2 of 2 is not a usable address — the row was not sent", "bad shape: " + JSON.stringify(bad));
  }
  eq(recipients({ to_address: "a<b@x.ca", to_more: [] }).ok, false, "to_address checked too (1st)");
  eq((recipients({ to_address: "a<b@x.ca", to_more: ["b@x.ca"] }) as { error: string }).error, "recipient 1 of 2 is not a usable address — the row was not sent", "to_address is recipient 1");
  eq((recipients({ to_address: to, to_more: "b@x.ca" }) as { error: string }).error, "to_more is not a list — the row was not sent", "string instead of array");
  eq((recipients({ to_address: to, to_more: [42] }) as { error: string }).error, "recipient 2 of 2 is not a usable address — the row was not sent", "non-string element");
  // drain · 운영(live · redirect 없음): To 에 모두 · rendered.to_address 는 첫 주소(mail_mark 가 to_address 칸에 덮는다 · 쉼표 금지) · original_to null · 제목 표지 없음
  const live = fakeDeps({ cfg: CFG({ mail_live: true, redirect_to: null }), mails: [{ ...mail("a"), to_more: ["b@example.invalid", "C@example.invalid"] }] });
  eq((await drain(live.d, opt)).counts, { sent: 1, failed: 0, retry: 0, unknown: 0 }, "live sent");
  ok(rawOf(live.sent[0]).includes("\r\nTo: a@example.invalid, b@example.invalid, C@example.invalid\r\n"), "live To header = all three");
  const rdl = live.marks[0].rendered as { to_address: string; original_to: string | null; subject: string };
  eq([rdl.to_address, rdl.original_to, rdl.subject.includes("→")], ["a@example.invalid", null, false], "live rendered: first address only · no marker");
  // drain · 시험 모드(redirect ops@): 한 통 · To = ops · 제목 [TEST → a, b, c] · rendered to = ops · original_to = 첫 주소
  const test = fakeDeps({ mails: [{ ...mail("a"), to_more: ["b@example.invalid", "c@example.invalid"] }] });
  eq((await drain(test.d, opt)).counts, { sent: 1, failed: 0, retry: 0, unknown: 0 }, "test sent once");
  const rawT = rawOf(test.sent[0]);
  ok(rawT.includes("\r\nTo: ops@asung.ca\r\n") && !rawT.includes("b@example.invalid\r\n"), "test: one mail to redirect only");
  const rdt = test.marks[0].rendered as { to_address: string; original_to: string; subject: string };
  eq([rdt.to_address, rdt.original_to, rdt.subject.startsWith("[TEST → a@example.invalid, b@example.invalid, c@example.invalid] ")], ["ops@asung.ca", "a@example.invalid", true], "test: subject lists all · rendered to = redirect · original_to = first");
  // drain · 운영 + redirect: [REDIRECT → 모두]
  const red = fakeDeps({ cfg: CFG({ mail_live: true }), mails: [{ ...mail("a"), to_more: ["b@example.invalid"] }] });
  eq((await drain(red.d, opt)).counts, { sent: 1, failed: 0, retry: 0, unknown: 0 }, "live redirect sent once");
  const rdr = red.marks[0].rendered as { to_address: string; subject: string };
  eq([rdr.to_address, rdr.subject.startsWith("[REDIRECT → a@example.invalid, b@example.invalid] ")], ["ops@asung.ca", true], "REDIRECT lists all");
  // 제목(이견 4): 표지의 → 때문에 늘 encoded-word 한 덩이(접지 않는다 · 전과 같다) · 10 주소라도 그 줄이 998 자 아래 · 풀면 10 번째까지 다 있다
  const ten = fakeDeps({ cfg: CFG({ mail_live: true }), mails: [{ ...mail("a"), to_more: more(9) }] });
  eq((await drain(ten.d, opt)).counts.sent, 1, "ten recipients sent");
  const subjLine = rawOf(ten.sent[0]).split("\r\n").find((l) => l.startsWith("Subject: "))!;
  const decoded = decodeB64(subjLine.slice("Subject: =?UTF-8?B?".length, -2));
  ok(subjLine.length < 998 && subjLine.startsWith("Subject: =?UTF-8?B?") && subjLine.endsWith("?=") && !subjLine.includes("\r\n"), "subject = one encoded-word line under 998");
  ok(decoded.startsWith("[REDIRECT → a@example.invalid, m1@example.invalid, ") && decoded.includes(", m9@example.invalid] "), "decoded subject lists all ten");
  // drain · 틀린 줄은 failed · 아무것도 안 보냄 · loadDoc 도 안 부른다(검사가 그리기 · Storage 앞)
  const bad = fakeDeps({ cfg: CFG({ mail_live: true, redirect_to: null }), mails: [
    { ...mail("a"), to_more: more(10) }, { ...mail("b"), to_more: ["x@y.ca\r\nBcc: z@example.invalid"] }, { ...mail("c"), to_more: "d@example.invalid" }, { ...docMail("d"), to_more: ["<e@example.invalid>"] }] });
  eq((await drain(bad.d, { ...opt, batch: 4 })).counts, { sent: 0, failed: 4, retry: 0, unknown: 0 }, "all failed");
  eq(bad.marks.map((x) => [x.id, x.m.result, x.m.error]), [
    ["a", "failed", "11 recipients — the limit is 10 — the row was not sent"], ["b", "failed", "recipient 2 of 2 is not a usable address — the row was not sent"],
    ["c", "failed", "to_more is not a list — the row was not sent"], ["d", "failed", "recipient 2 of 2 is not a usable address — the row was not sent"]], "errors · no address in them");
  ok(bad.sent.length === 0 && !bad.marks.some((x) => JSON.stringify(x).includes("example.invalid\\r")), "nothing sent · injected text not recorded");
  // 이견 2: redirect ∈ to_more → failed(대소문자 무시) · redirect = to_address 는 전처럼 보낸다
  const clash = fakeDeps({ cfg: CFG({ mail_live: true }), mails: [{ ...mail("a"), to_more: ["OPS@asung.ca"] }, { ...mail("ops", 1), to_address: "ops@asung.ca", to_more: ["b@example.invalid"] }] });
  eq((await drain(clash.d, opt)).counts, { sent: 1, failed: 1, retry: 0, unknown: 0 }, "one failed one sent");
  eq(clash.marks.map((x) => [x.id, x.m.result, x.m.error]), [["a", "failed", "redirect address is also a recipient (to_more) — the row was not sent"], ["ops", "sent", null]], "clash named · to_address = redirect still fine");
  // addressFor 옛 꼴(all 없음)은 전과 같다
  const s1 = safety(CFG(), TEST_REF) as { ok: true; test: boolean; redirect: string | null };
  eq(addressFor(mail("a"), s1, "S"), { to: "ops@asung.ca", original_to: "a@example.invalid", subject: "[TEST → a@example.invalid] S" }, "addressFor default unchanged");
});
