// deno test --allow-read supabase/functions/freightcom/inspect_test.ts — fc-track-1 action inspect · Freightcom · DB · 네트워크 무접촉(가짜 fetch · 가짜 deps)
import { defaultRange, INSPECT_WHATS, type InspectBooking, type InspectDeps, inspectGet, inspectPaths, isYmd, type LogMeta, parseInspect, pickBalanceMethod, redact, REMOVED, runInspect } from "./inspect.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const BASE = "https://fc.example";
const B1 = "cc649b92-72e1-4f2e-965d-15d3a11cec9d";
const BOOKING: InspectBooking = { id: B1, shipment_id: "11111111-1111-1111-1111-111111111111", status: "booked", account: "TOR", freightcom_shipment_id: "fcShip/1", transaction_number: "49137509", shipment_account: "TOR" };
type Call = { url: string; method: string; auth: string | null; hasSignal: boolean };
// 가짜 fetch — url 끝(경로)에 맞춰 답 · 안 끝나는 길(hang)은 signal 이 끊을 때까지 기다린다
function fakeFetch(routes: Record<string, { status: number; body: unknown } | "hang" | "throw">, calls: Call[]): typeof fetch {
  return ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, method: String(init?.method ?? "GET"), auth: (init?.headers as Record<string, string>)?.Authorization ?? null, hasSignal: !!init?.signal });
    const path = url.slice(BASE.length);
    const r = routes[path];
    if (r === "hang") return new Promise((_res, rej) => init?.signal?.addEventListener("abort", () => rej(init!.signal!.reason)));
    if (r === "throw" || r === undefined) return Promise.reject(new TypeError("connection refused " + path));
    return Promise.resolve(new Response(typeof r.body === "string" ? r.body : JSON.stringify(r.body), { status: r.status }));
  }) as typeof fetch;
}
function deps(over: Partial<InspectDeps>, routes: Record<string, { status: number; body: unknown } | "hang" | "throw">, calls: Call[], logs: LogMeta[]): InspectDeps {
  return {
    isAdmin: async () => true,
    loadBooking: async (id) => (id === B1 ? BOOKING : null),
    apiKey: (a) => (a === "TOR" || a === "EDM" ? "key-" + a : ""),
    base: BASE,
    fetchFn: fakeFetch(routes, calls),
    log: async (row) => { logs.push(row); },
    noAccountSentence: (a) => "No Freightcom connection for account " + a,
    now: new Date("2026-11-11T03:00:00Z"),
    ...over,
  };
}
const SHIP_BODY = { shipment: { id: "fcShip/1", state: "delivered", tracking_url: "https://track.carrier/x?n=1", labels: [{ size: "a6", format: "pdf", url: "https://s3.example/label.pdf?sig=abc" }], customs_invoice_url: "http://s3.example/ci.pdf", details: { destination: { name: "Shop", phone_number: { number: "4165550000" } } } } };
const INV_BODY = [{ id: "doc-1", number: "INV-77", amount: { currency: "CAD", value: "12345" }, owing: { currency: "CAD", value: "0" }, urls: { pdf: "https://s3.example/inv.pdf" },
  payments: [{ id: "p1", type: "credit-card", amount: { currency: "CAD", value: "12345" }, data: { credit_card_auth: "A1", credit_card_number: "****4242", credit_card_reference: "R9" } }],
  line_items: [{ id: "l1", type: "base", sub_type: "", amount: { currency: "CAD", value: "10000" }, message: "520863981582 Purolator" }, { id: "l2", type: "surcharge", sub_type: "inside-delivery", amount: { currency: "CAD", value: "2345" }, message: "see https://x.example" }] }];

Deno.test("① redact — http(s) 문자열은 키와 상관없이 · 중첩 · 배열 안까지 · 카드 칸 셋은 어디에 있든 · 금액 · type · id 는 남김 · 원본 무변", () => {
  const src = JSON.parse(JSON.stringify(INV_BODY));
  const r = redact(src) as typeof INV_BODY;
  eq(r[0].urls.pdf, REMOVED, "urls.pdf removed");
  eq(r[0].payments[0].data, { credit_card_auth: REMOVED, credit_card_number: REMOVED, credit_card_reference: REMOVED }, "card fields removed");
  eq([r[0].payments[0].id, r[0].payments[0].type, r[0].payments[0].amount.value], ["p1", "credit-card", "12345"], "payment id · type · amount kept");
  eq(r[0].line_items[0].message, "520863981582 Purolator", "message not starting with http kept");
  eq(r[0].line_items[1].message, "see https://x.example", "http inside text kept (only values that START with http)");
  eq(src[0].urls.pdf, "https://s3.example/inv.pdf", "source untouched");
  const s = redact(SHIP_BODY) as typeof SHIP_BODY;
  eq([s.shipment.tracking_url, s.shipment.labels[0].url, s.shipment.customs_invoice_url], [REMOVED, REMOVED, REMOVED], "tracking_url · labels[].url · customs_invoice_url removed (http and https · Caleb ⛔3)");
  eq(s.shipment.details.destination.phone_number.number, "4165550000", "PII is not this function's job (⬜4 · caller strips before sharing)");
  eq(redact({ a: [[" HTTPS://deep.example "]], n: 5, b: null, t: true }), { a: [[REMOVED]], n: 5, b: null, t: true }, "deep array · case · padding · non-strings kept");
  eq(redact({ data: { credit_card_number: null, credit_card_auth: "" } }), { data: { credit_card_number: null, credit_card_auth: "" } }, "empty card fields stay empty (no fake [removed])");
});

Deno.test("② parseInspect — what 여섯뿐 · booking_id 전체 uuid · account 꼴 · document_id · 날짜 YYYY-MM-DD · 기본 지난 30 일(UTC)", () => {
  const now = new Date("2026-11-11T03:00:00Z");
  eq(INSPECT_WHATS, ["shipment", "tracking", "invoices", "documents", "document", "balance"], "six whats");
  eq("error" in parseInspect({ what: "delete" }, now), true, "unknown what");
  eq("error" in parseInspect({}, now), true, "missing what");
  eq("error" in parseInspect({ what: "shipment", booking_id: "cc649b92" }, now), true, "8-char prefix refused");
  eq(parseInspect({ what: "tracking", booking_id: B1.toUpperCase() }, now), { what: "tracking", booking_id: B1, account: null, document_id: null, start_date: null, end_date: null }, "uuid lowercased");
  eq("error" in parseInspect({ what: "balance", account: "../x" }, now), true, "bad account");
  eq((parseInspect({ what: "balance", account: " edm " }, now) as { account: string }).account, "EDM", "account trimmed + upper");
  eq("error" in parseInspect({ what: "document", account: "TOR", document_id: "a/b" }, now), true, "slash in document_id");
  eq("error" in parseInspect({ what: "document", account: "TOR" }, now), true, "document_id required");
  eq(parseInspect({ what: "documents", account: "TOR" }, now), { what: "documents", booking_id: null, account: "TOR", document_id: null, start_date: "2026-10-12", end_date: "2026-11-11" }, "default 30 days UTC");
  eq(defaultRange(new Date("2026-03-01T00:30:00Z")), { start_date: "2026-01-30", end_date: "2026-03-01" }, "range across February");
  eq("error" in parseInspect({ what: "documents", account: "TOR", start_date: "2026-11-01", end_date: "2026-10-01" }, now), true, "start after end");
  eq("error" in parseInspect({ what: "documents", account: "TOR", start_date: "2026-02-30" }, now), true, "impossible date");
  eq([isYmd("2026-11-10"), isYmd("2026-11-10T00:00:00Z"), isYmd("20261110"), isYmd(20261110)], [true, false, false, false], "isYmd");
});

Deno.test("③ 경로 — 박아 둔 꼴 · 입력은 encodeURIComponent", () => {
  eq(inspectPaths.shipment("a/b?c"), "/shipment/a%2Fb%3Fc", "shipment");
  eq(inspectPaths.tracking("x"), "/shipment/x/tracking-events", "tracking");
  eq(inspectPaths.invoicesByTn("49137509"), "/finance/invoices-for-transaction-number/49137509", "by tn");
  eq(inspectPaths.invoicesByShipment("x y"), "/finance/invoices-for-shipment-id/x%20y", "by shipment");
  eq(inspectPaths.documents("2026-10-12", "2026-11-11"), "/finance/documents?start_date=2026-10-12&end_date=2026-11-11", "documents");
  eq(inspectPaths.document("d#1"), "/finance/document/d%231", "document");
  eq(inspectPaths.balance("pm 1"), "/finance/payment-method/pm%201/available-balances", "balance");
});

Deno.test("④ pickBalanceMethod — net-terms → prepaid → null(credit-card 만이면 없음)", () => {
  eq(pickBalanceMethod([{ id: "cc", type: "credit-card" }, { id: "pp", type: "prepaid" }, { id: "nt", type: "net-terms", label: "Net 30" }]), { id: "nt", type: "net-terms", label: "Net 30" }, "net-terms first");
  eq(pickBalanceMethod([{ id: "cc", type: "credit-card" }, { id: "pp", type: "Prepaid" }]), { id: "pp", type: "prepaid", label: "" }, "then prepaid");
  eq(pickBalanceMethod([{ id: "cc", type: "credit-card" }]), null, "card only → null");
  eq(pickBalanceMethod({ payment_methods: [{ id: "", type: "net-terms" }] }), null, "no id → null");
  eq(pickBalanceMethod(null), null, "null body");
});

Deno.test("⑤ 문 — JWT 없음 401 · 세션 틀림 401 · admin 아님 403 · what 모름 400 · Freightcom 호출 0", async () => {
  const calls: Call[] = [], logs: LogMeta[] = [];
  const d = deps({}, {}, calls, logs);
  eq((await runInspect("", { what: "shipment", booking_id: B1 }, d)).status, 401, "no jwt");
  eq((await runInspect("j", { what: "shipment", booking_id: B1 }, { ...d, isAdmin: async () => "invalid" })).status, 401, "invalid session");
  const r403 = await runInspect("j", { what: "shipment", booking_id: B1 }, { ...d, isAdmin: async () => false });
  eq([r403.status, String(r403.payload.error).includes("admin only")], [403, true], "not admin");
  eq((await runInspect("j", { what: "nope" }, d)).status, 400, "unknown what");
  eq((await runInspect("j", { what: "shipment" }, d)).status, 400, "booking_id missing");
  eq([calls.length, logs.length], [0, 0], "no Freightcom call · no log line");
});

Deno.test("⑥ 예약 · 계정 — 없는 예약 404 · Freightcom id 없음 400 · 계정 = 발송의 freightcom_account(다르면 경고) · 열쇠 없음 422", async () => {
  const calls: Call[] = [], logs: LogMeta[] = [];
  const d = deps({}, { "/shipment/fcShip%2F1": { status: 200, body: SHIP_BODY } }, calls, logs);
  eq((await runInspect("j", { what: "shipment", booking_id: "00000000-0000-0000-0000-000000000000" }, d)).status, 404, "booking not found");
  const noFc = await runInspect("j", { what: "tracking", booking_id: B1 }, { ...d, loadBooking: async () => ({ ...BOOKING, freightcom_shipment_id: null, status: "failed" }) });
  eq([noFc.status, String(noFc.payload.error).includes("no Freightcom shipment id")], [400, true], "no fc id");
  const diff = await runInspect("j", { what: "shipment", booking_id: B1 }, { ...d, loadBooking: async () => ({ ...BOOKING, account: "TOR", shipment_account: "EDM" }) });
  eq([diff.payload.account, (diff.payload.warnings as string[])[0].startsWith("account_differs"), calls[calls.length - 1].auth], ["EDM", true, "key-EDM"], "shipment account wins · warned · its key used");
  const noKey = await runInspect("j", { what: "balance", account: "XYZ" }, d);
  eq([noKey.status, noKey.payload.error], [422, "No Freightcom connection for account XYZ"], "no key");
  const noBase = await runInspect("j", { what: "balance", account: "TOR" }, { ...d, base: "" });
  eq(noBase.status, 500, "no base url fail-closed");
});

Deno.test("⑦ what 여섯 — GET 만 · 경로 · 계정 열쇠 · 지운 몸 · 로그는 메타만(inspect_<what>)", async () => {
  const routes = {
    "/shipment/fcShip%2F1": { status: 200, body: SHIP_BODY },
    "/shipment/fcShip%2F1/tracking-events": { status: 200, body: { events: [{ type: "delivered", when: "2026-11-05T15:00:00Z", where: { city: "Ottawa" }, message: "Delivered" }] } },
    "/finance/invoices-for-shipment-id/fcShip%2F1": { status: 200, body: INV_BODY },
    "/finance/invoices-for-transaction-number/49137509": { status: 200, body: INV_BODY },
    "/finance/documents?start_date=2026-10-12&end_date=2026-11-11": { status: 200, body: [{ id: "doc-1", number: "INV-77", amount: { currency: "CAD", value: "12345" } }] },
    "/finance/document/doc-1": { status: 200, body: INV_BODY[0] },
    "/finance/payment-methods": { status: 200, body: [{ id: "cc", type: "credit-card" }, { id: "nt-1", type: "net-terms", label: "Net terms" }] },
    "/finance/payment-method/nt-1/available-balances": { status: 200, body: { id: "nt-1", type: "net-terms", available_balances: [{ value: "500000" }] } },
  };
  const calls: Call[] = [], logs: LogMeta[] = [];
  const d = deps({}, routes, calls, logs);
  const sh = await runInspect("j", { what: "shipment", booking_id: B1 }, d);
  eq([sh.status, sh.payload.ok, sh.payload.http_status, sh.payload.account], [200, true, 200, "TOR"], "shipment ok");
  eq(((sh.payload.body as typeof SHIP_BODY).shipment.labels[0].url), REMOVED, "label url removed in reply");
  eq((sh.payload.booking as Record<string, unknown>).transaction_number, "49137509", "booking echo");
  const tr = await runInspect("j", { what: "tracking", booking_id: B1 }, d);
  eq((tr.payload.body as { events: unknown[] }).events.length, 1, "tracking events");
  const inv = await runInspect("j", { what: "invoices", booking_id: B1 }, d);
  const ib = inv.payload.body as { by_transaction_number: { body: typeof INV_BODY }; by_shipment_id: { body: typeof INV_BODY } };
  eq([inv.payload.ok, inv.payload.same_answer], [true, true], "both invoice paths · same answer");
  eq([ib.by_transaction_number.body[0].payments[0].data.credit_card_number, ib.by_shipment_id.body[0].urls.pdf], [REMOVED, REMOVED], "card + url removed in both parts");
  const docs = await runInspect("j", { what: "documents", account: "tor" }, d);
  eq([docs.payload.ok, docs.payload.start_date, docs.payload.end_date], [true, "2026-10-12", "2026-11-11"], "documents default range");
  const doc = await runInspect("j", { what: "document", account: "TOR", document_id: "doc-1" }, d);
  eq([doc.payload.ok, (doc.payload.body as typeof INV_BODY[0]).line_items.length], [true, 2], "document detail");
  const bal = await runInspect("j", { what: "balance", account: "TOR" }, d);
  const bb = bal.payload.body as { picked: { id: string }; available_balances: { body: { available_balances: { value: string }[] } } };
  eq([bal.payload.ok, bb.picked.id, bb.available_balances.body.available_balances[0].value], [true, "nt-1", "500000"], "balance via net-terms");
  eq(calls.every((c) => c.method === "GET" && c.hasSignal && c.url.startsWith(BASE + "/")), true, "every call GET · with timeout signal · base url");
  eq(calls.every((c) => c.auth === "key-TOR"), true, "TOR key for every call");
  eq(calls.map((c) => c.url.slice(BASE.length)), ["/shipment/fcShip%2F1", "/shipment/fcShip%2F1/tracking-events", "/finance/invoices-for-shipment-id/fcShip%2F1", "/finance/invoices-for-transaction-number/49137509",
    "/finance/documents?start_date=2026-10-12&end_date=2026-11-11", "/finance/document/doc-1", "/finance/payment-methods", "/finance/payment-method/nt-1/available-balances"], "exact paths in order");
  eq(logs.map((l) => l.action), ["inspect_shipment", "inspect_tracking", "inspect_invoices", "inspect_invoices", "inspect_documents", "inspect_document", "inspect_balance", "inspect_balance"], "one meta line per call");
  eq(logs.every((l) => l.ok && l.error === null && l.http_status === 200 && l.account === "TOR"), true, "meta only");
  eq(logs.filter((l) => l.action !== "inspect_documents" && l.action !== "inspect_document" && l.action !== "inspect_balance").every((l) => l.shipment_id === BOOKING.shipment_id), true, "booking whats log the shipment id");
  eq(Object.keys(logs[0]).sort(), ["account", "action", "error", "http_status", "ms", "ok", "shipment_id"], "no body field in the log row");
});

Deno.test("⑧ 2xx 아님 · 망 · 시간 초과 — EF 200 + ok:false + 몸(지운 뒤) · 로그 error 는 「failed (HTTP n)」 뿐(몸 없음)", async () => {
  const secret = { message: "bad data", data: { amount: "99999", url: "https://s3.example/x" } };
  const calls: Call[] = [], logs: LogMeta[] = [];
  const d = deps({ timeoutMs: 30 }, { "/shipment/fcShip%2F1": { status: 400, body: secret }, "/shipment/fcShip%2F1/tracking-events": "hang", "/finance/document/doc-9": "throw", "/finance/payment-methods": { status: 200, body: [{ id: "cc", type: "credit-card" }] } }, calls, logs);
  const bad = await runInspect("j", { what: "shipment", booking_id: B1 }, d);
  eq([bad.status, bad.payload.ok, bad.payload.http_status], [200, false, 400], "tolerated 400");
  eq((bad.payload.body as typeof secret).data, { amount: "99999", url: REMOVED }, "body returned to caller (url removed)");
  eq(logs[0].error, "Freightcom inspect_shipment failed (HTTP 400)", "log has no body");
  const t0 = Date.now();
  const hang = await runInspect("j", { what: "tracking", booking_id: B1 }, d);
  eq([hang.payload.ok, hang.payload.http_status, String(hang.payload.error).includes("did not answer within 30 ms"), Date.now() - t0 < 2000], [false, null, true, true], "aborted by timeout");
  eq(logs[1].error, "Freightcom inspect_tracking failed (HTTP timeout)", "timeout log line");
  const net = await runInspect("j", { what: "document", account: "TOR", document_id: "doc-9" }, d);
  eq([net.payload.ok, logs[2].error], [false, "Freightcom inspect_document failed (HTTP network)"], "network error");
  const card = await runInspect("j", { what: "balance", account: "TOR" }, d);
  eq([card.status, card.payload.ok, calls.filter((c) => c.url.includes("available-balances")).length], [422, false, 0], "card-only account → 422 · balance not called");
  eq(logs.every((l) => l.error === null || /^Freightcom inspect_\w+ failed \(HTTP [\w]+\)$/.test(l.error)), true, "every error line is the bare sentence");
});

Deno.test("⑨ inspectGet — 몸이 JSON 이 아니어도 글자 그대로(지운 뒤) · 빈 몸 null", async () => {
  const logs: LogMeta[] = [];
  const f = ((u: string) => Promise.resolve(new Response(u.endsWith("/a") ? "https://plain.example/x" : "", { status: u.endsWith("/a") ? 502 : 200 }))) as unknown as typeof fetch;
  const a = await inspectGet(f, BASE, "k", "document", "TOR", "/a", null, async (r) => { logs.push(r); });
  eq([a.ok, a.http_status, a.body], [false, 502, REMOVED], "text body redacted");
  const b = await inspectGet(f, BASE, "k", "document", "TOR", "/b", null, async (r) => { logs.push(r); });
  eq([b.ok, b.body], [true, null], "empty body null");
});
