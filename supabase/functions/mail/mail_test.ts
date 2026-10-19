// deno test supabase/functions/mail/mail_test.ts — Google · DB 무접촉(가짜) · mail-2b ① ~ ⑩ · mail-4c ⑪ · doc-3b ⑫ ~ ⑯(문서 메일 · MIME 무변 황금 · PDF 단계)
import { addressFor, base64url, buildMime, chatText, classify, drain, encodeWord, errorChatText, isDocKind, mailbox, pdfStep, projectRef, PROD_REF, render, safety, sha256Hex, TEST_REF, type Attachment, type AttachmentRead, type ClaimedMail, type Deps, type DocBody, type Line, type MailConfig, type Mark, type Outcome, type PdfDeps, type PdfJob } from "../_shared/mail.ts";

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
const CFG = (o: Partial<MailConfig> = {}): MailConfig => ({ enabled: true, redirect_to: "ops@asung.ca", db_role: "test", ...o });
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
