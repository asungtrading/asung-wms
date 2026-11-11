// deno test --allow-read supabase/functions/freightcom/finance_test.ts — fc-track-3 action finance_sweep · finance_poll · Freightcom · DB · 네트워크 무접촉(가짜 fetch · 가짜 deps)
//   fixtures/finance-*.json = 지시서 📌 의 실물 꼴(11-10 inspect · TOR)을 다시 적은 것 — 바이트 원문이 아니다(문서 id · 줄 id · shipment id · 묶음 인보이스의 줄 금액은 지어낸 값 · 합 73924 · 줄 17 · 쉽먼트 넷은 실물과 같다)
//   DB 시험(supabase/tests/fc_track_3_check.sql)과 같은 파일
import { docHeadsOf, FINANCE_BATCH_DEFAULT, FINANCE_POLL_BATCH, FINANCE_SWEEP_BUDGET_MS, FINANCE_TIMEOUT_MS, FINANCE_WINDOW_DAYS, financeAccount, financeGet, type FinanceLog, financeLimitOf, financeLogError, financePaths, type FinancePollDeps, type FinanceSweepDeps, financeSweepSummary, HEAD_KEYS, LINE_KEYS, runFinancePoll, runFinanceSweep, slimBalance, slimDocument, slimHead, windowOf } from "./finance.ts";
import { FC_ACTIONS, FC_BOOK_ACTIONS, FC_CRON_ACTIONS } from "../_shared/freightcom.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const here = new URL("./fixtures/", import.meta.url);
const fx = (n: string) => JSON.parse(Deno.readTextFileSync(new URL(n, here)));
const DOCS = fx("finance-documents.json"), SOD = fx("finance-document-sod.json"), INV = fx("finance-document-invoice.json"), PM = fx("finance-payment-methods.json"), BAL = fx("finance-balance.json");
const BASE = "https://fc.example";
const NOW = Date.UTC(2026, 10, 11, 3, 0, 0);                       // 2026-11-11 03:00 UTC
const LIST = "/finance/documents?start_date=2026-10-07&end_date=2026-11-11";
type Call = { url: string; method: string; auth: string | null; hasSignal: boolean };
type Route = { status: number; body: unknown } | "hang" | "throw";
function fakeFetch(routes: Record<string, Route>, calls: Call[]): typeof fetch {
  return ((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, method: String(init?.method ?? "GET"), auth: (init?.headers as Record<string, string>)?.Authorization ?? null, hasSignal: !!init?.signal });
    const r = routes[url.slice(BASE.length)];
    if (r === "hang") return new Promise((_res, rej) => init?.signal?.addEventListener("abort", () => rej(init!.signal!.reason)));
    if (r === "throw" || r === undefined) return Promise.reject(new TypeError("connection refused"));
    return Promise.resolve(new Response(typeof r.body === "string" ? r.body : JSON.stringify(r.body), { status: r.status }));
  }) as typeof fetch;
}
type Saved = { docs: { account: string; docs: Record<string, unknown>[]; limit: number }[]; lines: { account: string; doc: Record<string, unknown> }[]; balances: { account: string; type: string; balance: Record<string, unknown>[] }[] };
const newSaved = (): Saved => ({ docs: [], lines: [], balances: [] });
// 가짜 저장 — DB 창구 셋이 돌려주는 꼴을 흉내낸다(need_lines 는 시험이 정한다 · 고르는 규칙은 DB 시험이 본다)
function deps(routes: Record<string, Route>, calls: Call[], logs: FinanceLog[], saved: Saved, need: Record<string, string[]> = {}, over: Partial<FinanceSweepDeps & FinancePollDeps> = {}): FinanceSweepDeps & FinancePollDeps {
  return {
    fetchFn: fakeFetch(routes, calls), base: BASE,
    apiKey: (a) => { if (!/^[A-Z0-9]{2,10}$/.test(a)) throw new Error("bad account"); return a === "TOR" || a === "EDM" ? "key-" + a : ""; },
    log: (row) => { logs.push(row); return Promise.resolve(); },
    docsSave: (account, docs, limit) => { saved.docs.push({ account, docs, limit }); const all = need[account] ?? []; return Promise.resolve({ account, received: docs.length, saved: docs.length, added: docs.length, skipped: 0, other_account: 0, need_lines: all.slice(0, limit), need_total: all.length }); },
    linesSave: (account, doc) => {
      if (doc.id === "fxDocBadSave") return Promise.reject(new Error("Document fxDocBadSave is not in the list yet"));
      saved.lines.push({ account, doc });
      return Promise.resolve({ document_id: doc.id, lines_received: (doc.line_items as unknown[]).length, lines_saved: (doc.line_items as unknown[]).length, lines_skipped: 0, shipments: 1, linked_bookings: 1, sum_matches: true, warnings: [] });
    },
    balanceSave: (account, type, balance) => { saved.balances.push({ account, type, balance }); return Promise.resolve(balance.length === 1 ? { account, saved: true, checked_at: "2026-11-11T03:00:00+00:00" } : { account, saved: false, warning: "balance_count — the answer has " + balance.length + " balances (expected exactly 1) · nothing was saved" }); },
    noAccountSentence: (a) => "No Freightcom connection for account " + a,
    enabled: () => Promise.resolve(true),
    accounts: () => Promise.resolve(["TOR"]),
    gate: (account) => Promise.resolve({ ok: true, row: { account } }),
    now: () => NOW,
    ...over,
  };
}
const OK_ROUTES: Record<string, Route> = {
  [LIST]: { status: 200, body: DOCS },
  "/finance/payment-methods": { status: 200, body: PM },
  "/finance/payment-method/fxPmNetTerms/available-balances": { status: 200, body: BAL },
  "/finance/document/fxDocSodB2": { status: 200, body: SOD },
  "/finance/document/fxDocInv1": { status: 200, body: INV },
};
const NEED = { TOR: ["fxDocSodB2", "fxDocInv1"] };
// 금액처럼 보이는 것이 새지 않았는가 — fixture 의 금액 글자(센트)와 http 를 찾는다
const MONEY = ["25675", "17439", "73924", "75678", "7288", "1228", "104500"];
const leaks = (v: unknown) => { const s = JSON.stringify(v); return [...MONEY.filter((m) => s.includes(m)), ...(/https?:\/\//.test(s) ? ["http"] : []), ...(/credit_card|mastercard|payment_account_id/.test(s) ? ["card"] : [])]; };

Deno.test("① 창 · 상한 · 경로 — 오늘 − 35 일 ~ 오늘(UTC) · limit 1 ~ 100(밖이면 기본) · 경로는 넷뿐이고 인코딩 · 결제 · reload 경로 없음(1165)", () => {
  eq(windowOf(new Date(NOW)), { start_date: "2026-10-07", end_date: "2026-11-11" }, "35-day window");
  eq(FINANCE_WINDOW_DAYS, 35, "window days");
  eq([financeLimitOf({ limit: 7 }), financeLimitOf({ limit: "40" }), financeLimitOf({ limit: 0 }), financeLimitOf({ limit: 101 }), financeLimitOf({}), financeLimitOf(null), financeLimitOf({ limit: 2.5 }), financeLimitOf({}, FINANCE_POLL_BATCH)], [7, 40, FINANCE_BATCH_DEFAULT, FINANCE_BATCH_DEFAULT, 25, 25, 25, 5], "limit");
  eq(Object.keys(financePaths).sort(), ["balance", "document", "documents", "paymentMethods"], "the only four paths");
  eq([financePaths.documents("2026-10-07", "2026-11-11"), financePaths.document("a/b c"), financePaths.paymentMethods(), financePaths.balance("p/m")],
    [LIST, "/finance/document/a%2Fb%20c", "/finance/payment-methods", "/finance/payment-method/p%2Fm/available-balances"], "paths encode their input");
  const all = [financePaths.documents("a", "b"), financePaths.document("x"), financePaths.paymentMethods(), financePaths.balance("x")].join(" ");
  eq(/pay(?!ment-method)|reload|charge|invoice/i.test(all.replace(/payment-method/g, "")), false, "no pay · reload · charge path exists");
  eq(Deno.readTextFileSync(new URL("./finance.ts", import.meta.url)).match(/method:\s*"(\w+)"/g), ['method: "GET"'], "finance.ts sends GET only");
});

Deno.test("② 머리 — 배열 맨몸 · {documents} · 그 밖 null · 일곱 칸만 · 값은 고치지 않는다", () => {
  const heads = docHeadsOf(DOCS)!;
  eq(heads.length, 9, "nine heads");
  eq(heads[4], { id: "fxDocSodB2", type: "shipment-order-details", number: "49250480", date: { year: 2026, month: 11, day: 10 }, due_date: { year: 2026, month: 11, day: 10 }, amount: { value: "25675", currency: "CAD" }, owing: { value: "0", currency: "CAD" } }, "head as received");
  eq(docHeadsOf({ documents: DOCS })?.length, 9, "{documents:[…]}");
  eq([docHeadsOf({ documents: "x" }), docHeadsOf(null), docHeadsOf("text"), docHeadsOf({})], [null, null, null, null], "anything else = not read");
  eq(docHeadsOf([]), [], "an empty list is a read");
  eq(docHeadsOf([{ id: "a", urls: { default: "https://x" }, extra: 1 }, "junk", null])!, [{ id: "a", type: null, number: null, date: null, due_date: null, amount: null, owing: null }], "non-objects dropped · unknown keys dropped · missing stays null (the database skips it)");
  eq(Object.keys(slimHead(DOCS[0])), [...HEAD_KEYS], "exactly HEAD_KEYS");
});

Deno.test("③ 문서 — urls · payments.data(카드 칸) · 모르는 칸을 버린다 · 줄은 일곱 칸 · message 끝 공백은 그대로(btrim 은 DB) · id · line_items 없으면 문서가 아니다", () => {
  const sod = slimDocument(SOD)!;
  eq(Object.keys(sod), [...HEAD_KEYS, "payments", "line_items"], "head + payments + line_items only");
  eq(sod.payments, [{ type: "net-terms", amount: { value: "25675", currency: "CAD" } }], "payments keep type and amount only");
  eq((sod.line_items as Record<string, unknown>[])[0], { id: "fxLnB2a", type: "surcharge", sub_type: "other-charge-1", payment_id: "fxPayLine1", shipment_id: "fcShipFinB", amount: { value: "7288", currency: "CAD" }, message: "Additional charge " }, "line as received");
  eq((sod.line_items as Record<string, unknown>[]).every((l) => JSON.stringify(Object.keys(l)) === JSON.stringify([...LINE_KEYS])), true, "exactly LINE_KEYS");
  const inv = slimDocument({ document: INV })!;
  eq([(inv.line_items as unknown[]).length, new Set((inv.line_items as Record<string, unknown>[]).map((l) => l.shipment_id)).size, inv.payments], [17, 4, [{ type: "credit-card", amount: { value: "73924", currency: "CAD" } }]], "wrapped {document} · 17 lines · four shipments · card data gone");
  eq(leaks([sod, inv]).filter((x) => x === "http" || x === "card"), [], "no url · no card field leaves the function");
  eq([slimDocument({ id: "x" }), slimDocument({ line_items: [] }), slimDocument({ id: " ", line_items: [] }), slimDocument(null), slimDocument([SOD])], [null, null, null, null, null], "not a document");
});

Deno.test("④ 잔액 — {available_balances} · 배열 → [{value, currency}] · 원소 수는 그대로 넘긴다(1 개가 아니면 DB 가 저장하지 않는다)", () => {
  eq(slimBalance(BAL), [{ value: "75678", currency: "" }], "one balance · blank currency as received");
  eq(slimBalance([{ value: "1", currency: "CAD", id: "x" }, { value: "2" }, "junk"]), [{ value: "1", currency: "CAD" }, { value: "2", currency: null }, { value: null, currency: null }], "bare list · extra keys dropped · count preserved");
  eq([slimBalance({}), slimBalance(null), slimBalance({ available_balances: {} })], [null, null, null], "not a balance answer");
});

Deno.test("⑤ 계정 한 번 — 머리 → 잔액 → 줄 순서 · 열쇠 · 시간 한도 신호 · 저장 셋 · 로그는 메타 줄뿐 · 반환 · 로그에 금액 · http · 카드 없음", async () => {
  const calls: Call[] = [], logs: FinanceLog[] = [], saved = newSaved();
  const it = await financeAccount("tor", 25, deps(OK_ROUTES, calls, logs, saved, NEED));
  eq(calls.map((c) => c.url.slice(BASE.length)), [LIST, "/finance/payment-methods", "/finance/payment-method/fxPmNetTerms/available-balances", "/finance/document/fxDocSodB2", "/finance/document/fxDocInv1"], "list → methods → balance → documents");
  eq(calls.every((c) => c.method === "GET" && c.auth === "key-TOR" && c.hasSignal), true, "GET · the account key · a timeout signal on every call");
  eq([saved.docs.length, saved.docs[0].account, saved.docs[0].docs.length, saved.docs[0].limit], [1, "TOR", 9, 25], "heads saved once with the limit");
  eq(saved.balances, [{ account: "TOR", type: "net-terms", balance: [{ value: "75678", currency: "" }] }], "balance saved with the method type");
  eq(saved.lines.map((l) => [l.account, l.doc.id, (l.doc.line_items as unknown[]).length]), [["TOR", "fxDocSodB2", 5], ["TOR", "fxDocInv1", 17]], "one save per document");
  eq(it, { account: "TOR", ok: true, docs_read: true, received: 9, saved: 9, added: 9, skipped: 0, need_total: 2, lines_read: 2, lines_failed: 0, lines_left: 0, balance_saved: true, stopped_early: false, errors: [], warnings: [] }, "the item is counts only");
  eq(logs.map((l) => [l.action, l.account, l.ok, l.http_status, l.error, l.shipment_id, "detail" in l]), [["finance_documents", "TOR", true, 200, null, null, false], ["finance_methods", "TOR", true, 200, null, null, false], ["finance_balance", "TOR", true, 200, null, null, false], ["finance_document", "TOR", true, 200, null, null, false], ["finance_document", "TOR", true, 200, null, null, false]], "one meta row per call");
  eq(leaks([it, logs]), [], "no amount · url · card in the item or the log");
});

Deno.test("⑥ 실패 갈래 — 목록 실패여도 잔액은 읽는다 · 꼴 다른 목록 · 문서 실패 · 다른 id · 저장 실패는 그 문서만 · 잔액 원소 둘은 저장 0 + 경고 · 결제수단 없음", async () => {
  let calls: Call[] = [], logs: FinanceLog[] = [], saved = newSaved();
  let it = await financeAccount("TOR", 25, deps({ ...OK_ROUTES, [LIST]: { status: 500, body: { message: "boom https://x/secret" } } }, calls, logs, saved, NEED));
  eq([it.ok, it.docs_read, it.balance_saved, it.lines_read, it.errors, saved.docs.length, calls.length], [false, false, true, 0, ["Freightcom finance_documents failed (HTTP 500)"], 0, 3], "list failed → nothing saved for documents · balance still read");
  eq(leaks(logs), [], "the failed body is not logged");
  calls = []; logs = []; saved = newSaved();
  it = await financeAccount("TOR", 25, deps({ ...OK_ROUTES, [LIST]: { status: 200, body: { message: "ok" } } }, calls, logs, saved, NEED));
  eq([it.docs_read, it.errors], [false, ["Freightcom finance_documents 200: the answer is not a list of documents"]], "a 200 that is not a list");
  calls = []; logs = []; saved = newSaved();
  const routes: Record<string, Route> = { ...OK_ROUTES, "/finance/document/fxDocGone": { status: 404, body: {} }, "/finance/document/fxDocOther": { status: 200, body: SOD }, "/finance/document/fxDocBadSave": { status: 200, body: { ...SOD, id: "fxDocBadSave" } }, "/finance/document/fxDocNoLines": { status: 200, body: { id: "fxDocNoLines" } },
    "/finance/payment-method/fxPmNetTerms/available-balances": { status: 200, body: { available_balances: [{ value: "1", currency: "CAD" }, { value: "2", currency: "USD" }] } } };
  it = await financeAccount("TOR", 25, deps(routes, calls, logs, saved, { TOR: ["fxDocGone", "fxDocOther", "fxDocBadSave", "fxDocNoLines", "fxDocSodB2"] }));
  eq([it.ok, it.lines_read, it.lines_failed, it.lines_left, it.balance_saved, saved.lines.map((l) => l.doc.id)], [false, 1, 4, 4, false, ["fxDocSodB2"]], "four bad documents do not stop the fifth · two balances are not saved");
  eq(it.warnings, ["balance_count — the answer has 2 balances (expected exactly 1) · nothing was saved", "document_id_differs — Freightcom answered with another document id · not saved"], "warnings name the reason");
  eq(it.errors, ["4 document reads failed — see the finance_document rows"], "one error line");
  calls = []; logs = []; saved = newSaved();
  it = await financeAccount("TOR", 25, deps({ ...OK_ROUTES, "/finance/payment-methods": { status: 200, body: [{ id: "c1", type: "credit-card" }] } }, calls, logs, saved, {}));
  eq([it.ok, it.balance_saved, it.warnings, calls.length], [true, false, ["no_balance_method — this Freightcom account has no net-terms or prepaid payment method · no balance to read"], 2], "no net-terms or prepaid method → no balance call");
});

Deno.test("⑦ 시간 한도 · 망 실패 · 계정 — hang 은 timeoutMs 뒤 끊는다 · 열쇠 없음 · 계정 꼴 틀림은 호출 0 · 로그 글은 정해진 꼴", async () => {
  const calls: Call[] = [], logs: FinanceLog[] = [];
  const r = await financeGet(fakeFetch({ "/finance/payment-methods": "hang" }, calls), BASE, "k", "finance_methods", "TOR", "/finance/payment-methods", (row) => { logs.push(row); return Promise.resolve(); }, 30);
  eq([r.ok, r.http_status, r.body, r.error, logs[0].error], [false, null, null, "Freightcom finance_methods failed (HTTP timeout)", "Freightcom finance_methods failed (HTTP timeout)"], "timeout");
  const n = await financeGet(fakeFetch({}, calls), BASE, "k", "finance_balance", "TOR", "/x", () => Promise.resolve(), 30);
  eq(n.error, "Freightcom finance_balance failed (HTTP network)", "network");
  eq([financeLogError("finance_document", 404, false), FINANCE_TIMEOUT_MS, FINANCE_SWEEP_BUDGET_MS], ["Freightcom finance_document failed (HTTP 404)", 20_000, 90_000], "constants");
  for (const a of ["VAN", "to r", ""]) {
    const c: Call[] = [], saved = newSaved();
    const it = await financeAccount(a, 25, deps(OK_ROUTES, c, [], saved));
    eq([it.ok, c.length, it.errors.length, saved.docs.length], [false, 0, 1, 0], "no key / bad account '" + a + "' → no call");
  }
});

Deno.test("⑧ finance_sweep — 스위치 off 면 호출 0 · 계정도 안 읽는다 · 요약 한 줄", async () => {
  const calls: Call[] = [], logs: FinanceLog[] = [], saved = newSaved();
  let asked = false;
  const r = await runFinanceSweep({ limit: 25 }, deps(OK_ROUTES, calls, logs, saved, NEED, { enabled: () => Promise.resolve(false), accounts: () => { asked = true; return Promise.resolve(["TOR"]); } }));
  eq([r.status, r.payload.ok, r.payload.enabled, r.payload.items, calls.length, asked, saved.docs.length], [200, true, false, [], 0, false, 0], "switch off → nothing read");
  eq([logs.length, logs[0].action, logs[0].ok, (logs[0].detail as Record<string, unknown>).skipped], [1, "finance_sweep", true, "switch off — inv_config fc_finance_poll_enabled is not 'on' (nothing read)"], "one summary row");
});

Deno.test("⑨ finance_sweep — 계정 둘 · batch 는 둘 합쳐서 · EDM 이 실패해도 TOR 는 끝난다 · 요약은 개수만(금액 없음)", async () => {
  const calls: Call[] = [], logs: FinanceLog[] = [], saved = newSaved();
  const r = await runFinanceSweep({ limit: 3 }, deps(OK_ROUTES, calls, logs, saved, { EDM: [], TOR: ["fxDocSodB2", "fxDocInv1"] }, { accounts: () => Promise.resolve(["EDM", "TOR"]) }));
  const items = r.payload.items as Record<string, unknown>[];
  eq(items.map((i) => [i.account, i.ok, i.docs_read, i.lines_read]), [["EDM", true, true, 0], ["TOR", true, true, 2]], "both accounts (same fake answers) read");
  eq(calls.filter((c) => c.auth === "key-EDM").length, 3, "EDM used its own key");
  // EDM 의 목록이 실패 · 잔액 꼴이 다름 — 그 계정만 failed
  const calls2: Call[] = [], logs2: FinanceLog[] = [], saved2 = newSaved();
  const d2 = deps({}, calls2, logs2, saved2, NEED, { accounts: () => Promise.resolve(["EDM", "TOR"]) });
  d2.fetchFn = ((input: string | URL | Request, init?: RequestInit) => {
    const edm = (init?.headers as Record<string, string>)?.Authorization === "key-EDM";
    return edm ? fakeFetch({ "/finance/payment-methods": { status: 200, body: { unexpected: true } } }, calls2)(input, init) : fakeFetch(OK_ROUTES, calls2)(input, init);
  }) as typeof fetch;
  const r2 = await runFinanceSweep({ limit: 1 }, d2);
  const it2 = r2.payload.items as Record<string, unknown>[];
  eq(it2.map((i) => [i.account, i.ok, i.docs_read, i.balance_saved, i.lines_read, i.lines_left]), [["EDM", false, false, false, 0, 0], ["TOR", true, true, true, 1, 1]], "EDM failed alone · TOR read one document (batch 1) and left one");
  eq([r2.status, r2.payload.ok, r2.payload.accounts, r2.payload.accounts_failed, r2.payload.lines_read, r2.payload.lines_left, r2.payload.balances_saved, r2.payload.stopped_early], [200, true, 2, 1, 1, 1, 1, false], "summary");
  const sum = logs2[logs2.length - 1];
  eq([sum.action, sum.ok, sum.error, sum.account, sum.shipment_id], ["finance_sweep", false, "1 of 2 accounts had a failed read — see the finance_… rows just before this one", null, null], "summary row");
  eq(leaks([logs, logs2, r.payload, r2.payload]), [], "no amount · url · card in any log row or reply");
  eq(financeSweepSummary([]), { accounts: 0, accounts_failed: 0, docs_received: 0, docs_added: 0, lines_read: 0, lines_failed: 0, lines_left: 0, balances_saved: 0 }, "empty summary");
});

Deno.test("⑩ finance_sweep 상한 — batch 를 다 쓰면 다음 계정은 머리 · 잔액만 · 90 s 가 지나면 새 문서 · 새 계정을 시작하지 않는다 · 스위치 · 계정 읽기 실패 502 · base 없음 500", async () => {
  let calls: Call[] = [], logs: FinanceLog[] = [], saved = newSaved();
  const r = await runFinanceSweep({ limit: 1 }, deps(OK_ROUTES, calls, logs, saved, { EDM: ["fxDocSodB2"], TOR: ["fxDocInv1"] }, { accounts: () => Promise.resolve(["EDM", "TOR"]) }));
  eq((r.payload.items as Record<string, unknown>[]).map((i) => [i.account, i.lines_read, i.lines_left, i.balance_saved]), [["EDM", 1, 0, true], ["TOR", 0, 1, true]], "the batch is shared — the second account reads heads and balance only");
  calls = []; logs = []; saved = newSaved();
  let t = NOW;
  const d = deps(OK_ROUTES, calls, logs, saved, NEED, { accounts: () => Promise.resolve(["TOR", "EDM"]), now: () => t });
  d.linesSave = (_a, doc) => { t += 95_000; saved.lines.push({ account: "TOR", doc }); return Promise.resolve({ document_id: doc.id, warnings: [] }); };
  const r2 = await runFinanceSweep({ limit: 25 }, d);
  eq([(r2.payload.items as unknown[]).length, r2.payload.stopped_early, r2.payload.accounts_left, saved.lines.length, r2.payload.lines_left], [1, true, 1, 1, 1], "after 90 s no new document and no new account");
  const e1 = await runFinanceSweep({}, deps(OK_ROUTES, [], [], newSaved(), {}, { enabled: () => Promise.reject(new Error("db down")) }));
  const e2 = await runFinanceSweep({}, deps(OK_ROUTES, [], [], newSaved(), {}, { accounts: () => Promise.reject(new Error("db down")) }));
  const e3 = await runFinanceSweep({}, deps(OK_ROUTES, [], [], newSaved(), {}, { base: "" }));
  eq([e1.status, e2.status, e3.status], [502, 502, 500], "fail closed");
});

Deno.test("⑪ finance_poll — JWT 없음 401 · 계정 꼴 400 · 문 거부는 까닭대로(세션 401 · 권한 · 창고 403 · 그 밖 422) · 문 앞에서는 호출 0 · 통과하면 줄 읽기 5 · 반환에 금액 없음", async () => {
  const calls: Call[] = [], logs: FinanceLog[] = [], saved = newSaved();
  const d = deps(OK_ROUTES, calls, logs, saved, NEED);
  eq([(await runFinancePoll("", { account: "TOR" }, d)).status, (await runFinancePoll("jwt", { account: "t o r" }, d)).status, (await runFinancePoll("jwt", {}, d)).status, calls.length], [401, 400, 400, 0], "401 · 400 · 400 before any call");
  const refuse = async (status: number, error: string) => { const c: Call[] = []; const r = await runFinancePoll("jwt", { account: "TOR" }, deps(OK_ROUTES, c, [], newSaved(), NEED, { gate: () => Promise.resolve({ ok: false, status, error }) })); return [r.status, r.payload.error, c.length]; };
  eq(await refuse(401, "JWT expired"), [401, "Invalid session — sign in again", 0], "session");
  eq(await refuse(400, "You cannot refresh Freightcom billing — ask an admin for the 'freight_booking' or 'purchasing' permission — nothing was read"), [403, "You cannot refresh Freightcom billing — ask an admin for the 'freight_booking' or 'purchasing' permission — nothing was read", 0], "permission");
  eq((await refuse(400, "This Freightcom account belongs to another warehouse — nothing was read"))[0], 403, "warehouse");
  eq((await refuse(400, "No warehouse uses the Freightcom account VAN — nothing was read"))[0], 422, "unknown account");
  const r = await runFinancePoll("jwt", { account: "tor" }, d);
  eq([r.status, r.payload.ok, r.payload.checked, r.payload.account, saved.docs[0].limit, (r.payload.finance as Record<string, unknown>).lines_read], [200, true, true, "TOR", FINANCE_POLL_BATCH, 2], "passed the gate → same steps · small batch");
  eq(leaks(r.payload), [], "the reply has no amount");
  const bad = await runFinancePoll("jwt", { account: "TOR" }, deps({}, [], [], newSaved(), NEED));
  eq([bad.status, bad.payload.ok, bad.payload.checked], [502, false, false], "nothing read → 502");
});

Deno.test("⑫ 길 가르기 — finance_sweep 은 cron 길에만 · finance_poll 은 FC_*_ACTIONS 밖(문이 DB fc_finance_gate) · 앞의 cron 갈래는 그대로", () => {
  eq([...FC_CRON_ACTIONS], ["pickup_sweep", "track_sweep", "finance_sweep"], "cron actions");
  const person = [...FC_ACTIONS, ...FC_BOOK_ACTIONS] as readonly string[];
  eq([person.includes("finance_sweep"), person.includes("finance_poll"), (FC_CRON_ACTIONS as readonly string[]).includes("finance_poll")], [false, false, false], "finance_sweep is not a person action · finance_poll is routed before the action list");
  const idx = Deno.readTextFileSync(new URL("./index.ts", import.meta.url));
  eq([idx.includes('if (action === "finance_poll") return await financePollAction(req, body);'), idx.includes('action === "finance_sweep" ? await financeSweepAction(body)'), /fc_finance_(docs|lines|balance)_save/.test(idx), /"(POST|PUT|DELETE|PATCH)", "\/finance/.test(idx)], [true, true, true, false], "index.ts routes both and writes nothing to /finance");
});
