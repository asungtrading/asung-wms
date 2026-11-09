// deno test supabase/functions/qbo/qbo_test.ts — Intuit · DB · 네트워크 무접촉(가짜 fetch · 가짜 DB 창구 열둘 + qbo_last_error_set) · qbo-1b ① ~ ⑩ + ⓪ 순수 함수 · ⑪ 회사 이름 저장 거부의 흔적(qbo-1c 뒤 · 판단 4)
//   qbo-read-1(2026-11-01 · 판정 933): ⑫ query · ⑬ read + 읽기 전용 요청 검사 — 가짜 Intuit 에 /query · /<entity>/<id> · /preferences 길(QueryResponse 꼴 · SyncToken · Customer 연락처 칸 포함)
//   가짜 DB 는 20261029160000(qbo-1a) 창구의 거부 글 · 반환 키를 그대로 흉내 낸다(state 10 분 · 한 번 · realm 고정 · 임대 · 판 번호 · needs_reconnect 거부 · mark 의 mailed = connected 에서 바뀔 때만)
//   qbo-sync-1b(2026-11-01 · 판정 934): ⑭ pull — 가짜 DB 에 qbo_pull_begin · qbo_entity_upsert · qbo_pull_finish(20261101210000 의 거부 글 · 반환 키 그대로) · 쪽 1000 은 override 로 · 기존 ⓪ ~ ⑬ 무변
//   ⚠️ 모든 비밀 · 토큰 가짜 값에 ZZSECRET 표식 — 응답 · 기록 · warn 어디에도 그 표식이 없어야 한다(⑨ + 모든 시험 끝)
//   qbo-sync-2e-2-1b(2026-11-04 · 판정 1009 · 1011 ~ 1016 · sandbox C-5″ · C-6): ㉓ 크레딧 붙임(0 원 Payment) · void — 가짜 Intuit: CreditMemo 읽기에 Balance 와 RemainingCredit 둘 다 · POST payment 가 CreditMemo LinkedTxn 을 받아 RemainingCredit 를 줄인다(void 는 되돌림) · TotalAmt 0 응답엔 DepositToAccountRef 없음 · 가짜 DB done 에 credit_apply · credit_apply_void(20261103200000 의 글 그대로) · SEND_KINDS 단언 셋 8 → 10(⑱ · ⑳ · ㉒ — 2c1 · 2e-1c 때와 같은 갱신 · 결제 시험 본문 무변)
//   qbo-sync-2e-3-1b(2026-11-07 · 판정 998′ · 1009 · 1011 ~ 1013 · DB 2e-3-1 20261107044131): ㉕ 이월 받아 둔 돈의 붙임 = 「쓰기」 CreditMemo(OC-<인보이스>-<n>) + 0 원 Payment · void 둘 — 가짜 DB done 에 opening_credit · opening_credit_void · opening_apply · opening_apply_void(20261107044131 의 글 그대로) · addJob ims_kind opening_alloc · SEND_KINDS 단언 넷 10 → 14(⑱ · ⑳ · ㉒ · ㉓ — 앞 차수와 같은 갱신 · 본문 무변) · 새 갈래 없음(이견 1)이라 기존 ⑳ · ㉓ 길을 opening 넷으로 다시 돈다
//   qbo-sync-2e-1d-2(2026-11-06 · deferred 452 · DB 1d-1 20261105184613): ㉔ 이월 인보이스 짝 — opening_candidates · opening_read(peek) · opening_search — 가짜 DB 에 qbo_opening_list · qbo_opening_candidates · qbo_opening_match(20261105184613 의 거부 글 · 반환 키 꼴 · 일곱 칸 밖 칸이 오면 거부해 EF 의 줄이기를 증명) · 가짜 Intuit query 에 DocNumber in (…) · like · 기존 ⓪ ~ ㉓ 무변
//   qbo-sync-2e-3-2-1b2(2026-11-08 · 이견 1 ~ 8): 가짜 Intuit 의 txnOpenBalance 는 차감 **직전** 값(sandbox P3 · 걸음 25 → 26 실측 · Expense · CreditMemo · Invoice 줄 셋) · openBalanceNote(after = before − Amount · Expense |after| > 0.004 · CreditMemo after < −0.004) 순수 단언 셋 · ㉖ ①(note 글) · ③(경고 글 「6.04 left」) 두 단언만 바뀜 · 그 밖의 옛 시험 무변
//   qbo-sync-2e-3-2-1b(2026-11-08 · 판정 1056 ~ 1058 · ⓖ-1 ~ ⓖ-8 · DB 2e-3-2-1 20261108075221 · 이견 1 ~ 11): ㉖ 환불 = Purchase(Expense) 만들기 · 0 원 Payment(Expense 줄 + CreditMemo 줄) · void 둘(Payment update&include=void → Purchase Full update void 꼴) — 가짜 Intuit: Purchase 장부(POST 만들기 · Id 있으면 Full update = SyncToken 대조 · 5010 · 금액 0 ∧ 「Voided - 」 면 status Voided · GET purchase/<id> · 조회 TxnDate = · >= … <= 범위 · STARTPOSITION 쪽 · JournalEntry · RefundReceipt 는 심은 행만) · Payment 의 LinkedTxn TxnType "Expense"(열린 금액 · txnOpenBalance · Purchase LinkedTxn Payment · SyncToken 오름 · void 되돌림) · 가짜 DB done 에 refund · refund_void · refund_apply · refund_apply_void(20261108075221 의 글 그대로) · addJob ims_kind refund · SEND_KINDS 단언 넷 14 → 18(⑱ · ㉒ · ㉓ · ㉕ · ㉕ ⑥ 의 「모르는 kind」 는 refund → bogus) · writesAllowedOnly 에 purchase(Id 가 있으면 void 꼴)
import { REFUND_KINDS, REFUND_APPLY_KINDS, REFUND_GUARD_DAYS, REFUND_GUARD_PAGES_MAX, REFUND_GUARD_ENTITIES, VOIDED_NOTE_PREFIX, purchaseVoidBodyProblem, isVoidedPurchase, purchasesByDateQueryText, refundGuardQueryText, shiftDate, purchaseCustomerRefs, journalCustomerAmounts, refundHandHit, txnOpenBalances, openBalanceNote, OPENING_CREDIT_KINDS, OPENING_APPLY_KINDS, TXN_KINDS, OPENING_BATCH_DEFAULT, OPENING_BATCH_MAX, OPENING_BUDGET_MS, OPENING_SEARCH_MAX, OPENING_REASONS, openingSlim, openingQueryText, openingSearchQueryText, kindsOf, paymentKeyOf, parsePaymentKey, PAYMENT_KINDS, CREDIT_APPLY_KINDS, UPDATE_VOID_ENTITIES, isVoidedPayment, paymentsByDateQueryText, ACCESS_EXPIRES_DEFAULT_S, ACTIONS, ADMIN_ACTIONS, assertReadOnlyRequest, assertWriteAllowed, authorizeUrl, classifyWrite, CRON_ACTIONS, DUPLICATE_DOCNUMBER_CODES, DUPLICATE_NAME_CODE, faultCode, invoiceTotals, SEND_KINDS, STALE_OBJECT_CODE, KEY_ACTIONS, PII_ENTITIES, REQUESTID_MAX, SEND_LIMIT_MAX, SEND_PICK_MAX, SEND_PICK_ROUNDS, SEND_PICK_BUDGET_MS, SEND_PICK_PARALLEL, sqlQuote, WRITE_ENTITIES, MAXRESULTS_MAX, parseQuery, QboError, queryForLog, QUERY_ENTITIES, RESPONSE_MAX_BYTES, stripPii, callbackLocation, PII_FIELDS, PULL_ENTITIES, PULL_FIELDS, PULL_NO_ACTIVE_FILTER, PULL_PAGE, pullQueryText, type CallbackWhy, DISCOVERY_TTL_MS, DiscoveryCache, handle, intuitErrorText, isCallbackPath, isRetryable, needsReconnect, newStateRaw, parseDiscovery, parseTokenResponse, redirectUriOf, RpcError, scrub, SETTINGS_URL, sha256Hex, type Deps, type LogRow } from "../_shared/qbo.ts";
import { DEFAULT_SEND_KINDS, COST_DAY_KINDS, COST_DAY_DOC_RE, journalDebitCents, fingerprintDebitCents, costDayKeyOf, parseCostDayKey, costDayDocOfImsId } from "../_shared/qbo.ts";   // 3-3

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
function ok(c: boolean, msg: string) { if (!c) throw new Error(msg); }

// ── 가짜 Intuit ──
const SB = "https://fazgmyvzzhqybtvtktyg.supabase.co";
const DISC = { issuer: "https://oauth.platform.intuit.com/op/v1", authorization_endpoint: "https://appcenter.intuit.com/connect/oauth2", token_endpoint: "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer", revocation_endpoint: "https://developer.api.intuit.com/v2/oauth2/tokens/revoke" };
type Hit = { url: string; method: string; body: string; auth: string | null };
type Created = { ent: string; id: string; name: string; sku: string | null; requestid: string | null };
type Inv = { Id: string; DocNumber: string; SyncToken: number; TotalAmt: number; TotalTax: number; voided: boolean; CustomerRef: unknown; ent?: "Invoice" | "CreditMemo"; Balance?: number; RemainingCredit?: number };   // [2e-2-1b RemainingCredit — CreditMemo 만(실물 C-5″: Balance 와 둘 다 온다)]   // 2e-1c: Balance(없으면 TotalAmt) — 결제가 줄인다
type Pay = { Id: string; SyncToken: number; TotalAmt: number; UnappliedAmt: number; CustomerRef: unknown; TxnDate: string; PaymentRefNum: string | null; PrivateNote: string; Line: Record<string, unknown>[]; voided: boolean; DepositToAccountRef: unknown; PaymentMethodRef: unknown };   // 2e-1c 가짜 Payment(A-1 실물 꼴)   // 2c1: ent 없으면 Invoice · 가짜 장부 하나에 둘 다
type Pur = { Id: string; SyncToken: number; TxnDate: string; TotalAmt: number; PaymentType: unknown; EntityRef: unknown; PrivateNote: string; DocNumber: string | null; Line: Record<string, unknown>[]; LinkedTxn: Record<string, unknown>[]; AccountRef: unknown; voided: boolean; open: number; status?: string };   // 2e-3-2-1b 가짜 Purchase(sandbox 2-a · 2-d 꼴 · open = A/R 줄의 열린 금액 — 0 원 Payment 가 줄인다 · status 는 void 꼴일 때만 Voided)
type Intuit = { hits: Hit[]; tokenN: number; override: ((h: Hit) => Response | Error | null)[]; dupNames: Set<string>; createdN: number; created: Created[]; invoices: Map<string, Inv>; dupDoc: Set<string>; voidRefuse: Set<string>; taxOverride: Map<string, number>; payments: Map<string, Pay>; purchases: Map<string, Pur>; journals: Record<string, unknown>[]; refundReceipts: Record<string, unknown>[]; purchaseStatus: Map<string, string | null> };   // [2e-3-2-1b purchases · journals · refundReceipts(손 기록 가드의 심은 행) · purchaseStatus(Full update 응답의 status 를 꾸민다 — null = 칸 없음)]   // [2e-1c payments]   // 2b2: invoices = 가짜 장부(Id → 인보이스) · dupDoc 는 6140 · voidRefuse 는 void 400 · taxOverride 는 QBO 가 세금을 다르게 셈한 꼴(mismatch)   // 2a′: 가짜 쓰기 — dupNames 에 있으면 6240 · created 에 쌓인다(이름 조회가 찾는다)
const jres = (status: number, body: unknown, tid = "tid-" + status) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", intuit_tid: tid } });
function intuitFake(): { it: Intuit; fetch: Deps["fetch"] } {
  const it: Intuit = { hits: [], tokenN: 0, override: [], dupNames: new Set(), createdN: 0, created: [], invoices: new Map(), dupDoc: new Set(), voidRefuse: new Set(), taxOverride: new Map(), payments: new Map(), purchases: new Map(), journals: [], refundReceipts: [], purchaseStatus: new Map() };
  const invRow = (v: Inv) => ({ Id: v.Id, DocNumber: v.DocNumber, SyncToken: String(v.SyncToken), TotalAmt: v.TotalAmt, TxnTaxDetail: { TotalTax: v.TotalTax }, CustomerRef: v.CustomerRef, Balance: v.Balance ?? v.TotalAmt, ...(v.ent === "CreditMemo" ? { RemainingCredit: v.RemainingCredit ?? v.Balance ?? v.TotalAmt } : {}), BillAddr: { Line1: "ZZPII" }, BillEmail: { Address: "ZZPII@example.invalid" }, PrivateNote: v.voided ? "Voided" : "Customer Reference: x", domain: "QBO", sparse: false });
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
    if (h.method === "POST" && /\/v3\/company\/[^/]+\/payment\/?\?/.test(url)) {                      // 2e-1c 가짜 Payment — 만들기(Line 의 Invoice Balance 를 줄인다 · LineEx) · void(operation=update&include=void · SyncToken 대조)
      const b = JSON.parse(h.body || "{}") as Record<string, unknown>, sp = new URL(url).searchParams, op = sp.get("operation");
      const payRow = (p: Pay) => ({ Id: p.Id, SyncToken: String(p.SyncToken), TxnDate: p.TxnDate, TotalAmt: p.TotalAmt, UnappliedAmt: p.UnappliedAmt, CustomerRef: p.CustomerRef, PaymentRefNum: p.PaymentRefNum, PrivateNote: p.PrivateNote, DepositToAccountRef: p.DepositToAccountRef, PaymentMethodRef: p.PaymentMethodRef, CurrencyRef: { value: "CAD" }, Line: p.Line, domain: "QBO", sparse: false });
      if (op === "update" && sp.get("include") === "void") {
        const v = it.payments.get(String(b.Id ?? ""));
        if (!v) return jres(400, { Fault: { Error: [{ Message: "Object Not Found", Detail: "Object Not Found : Something you're trying to use has been made inactive.", code: "610" }], type: "ValidationFault" } }, "tid-610");
        if (it.voidRefuse.has(v.Id)) return jres(400, { Fault: { Error: [{ Message: "Business Validation Error", Detail: "You cannot void a payment that has been deposited", code: "6000" }], type: "ValidationFault" } }, "tid-6000");
        if (String(b.SyncToken) !== String(v.SyncToken)) return jres(400, { Fault: { Error: [{ Message: "Stale Object Error", Detail: "Stale Object Error : You and someone else were working on this at the same time.", code: "5010" }], type: "ValidationFault" } }, "tid-5010");
        for (const l of v.Line) { const lt0 = ((((l.LinkedTxn ?? []) as Record<string, unknown>[])[0] ?? {}) as Record<string, unknown>); if (lt0.TxnType === "Expense") { const pur = it.purchases.get(String(lt0.TxnId ?? "")); if (pur) { pur.open = Math.round((pur.open + Number(l.Amount ?? 0)) * 100) / 100; pur.SyncToken++; pur.LinkedTxn = pur.LinkedTxn.filter((t) => String(t.TxnId) !== v.Id); } continue; }   // [2e-3-2-1b Expense 줄 — 열린 금액 되돌림 · Purchase SyncToken 오름 · LinkedTxn 풀림]
          const inv = it.invoices.get(String(lt0.TxnId ?? "")); if (inv) { inv.Balance = Math.round(((inv.Balance ?? inv.TotalAmt) + Number(l.Amount ?? 0)) * 100) / 100; if (inv.ent === "CreditMemo") inv.RemainingCredit = inv.Balance; } }   // [2e-2-1b C-6: CreditMemo RemainingCredit 되돌림]
        v.SyncToken++; v.TotalAmt = 0; v.UnappliedAmt = 0; v.Line = []; v.voided = true; v.PrivateNote = "Voided - " + v.PrivateNote;
        return jres(200, { Payment: payRow(v), time: "2026-11-02T12:00:00Z" }, "tid-pvoid-" + v.Id);
      }
      if (op !== null) return jres(400, { Fault: { Error: [{ Message: "Unsupported Operation", code: "500" }], type: "ValidationFault" } }, "tid-op");
      const lines = Array.isArray(b.Line) ? b.Line as Record<string, unknown>[] : [], outLines: Record<string, unknown>[] = [], linkedPur: Pur[] = [];   // [2e-3-2-1b linkedPur — Expense 줄의 Purchase 에 Payment LinkedTxn 을 단다]
      for (const l of lines) {
        const lt = (((l.LinkedTxn ?? []) as Record<string, unknown>[])[0] ?? {}) as Record<string, unknown>, inv = it.invoices.get(String(lt.TxnId ?? ""));
        if (lt.TxnType === "Expense") {                                                              // 2e-3-2-1b sandbox 2-a · 걸음 25 — Expense 줄: Purchase 의 열린 금액(A/R 줄)을 줄인다 · 모자라면 6000 · Purchase SyncToken 오름 · txnOpenBalance
          const pur = it.purchases.get(String(lt.TxnId ?? ""));
          if (!pur || pur.voided) return jres(400, { Fault: { Error: [{ Message: "Invalid Reference Id", Detail: "Invalid Reference Id : Expense " + String(lt.TxnId) + " not found", code: "6240" }], type: "ValidationFault" } }, "tid-badref");
          if (Number(l.Amount ?? 0) > pur.open + 0.004) return jres(400, { Fault: { Error: [{ Message: "Business Validation Error", Detail: "Amount applied exceeds the expense open balance", code: "6000" }], type: "ValidationFault" } }, "tid-6000");
          const purBefore = pur.open; pur.open = Math.round((pur.open - Number(l.Amount ?? 0)) * 100) / 100; pur.SyncToken++; linkedPur.push(pur);   // [1b2] txnOpenBalance = 차감 직전 값(sandbox P3 · 걸음 25)
          outLines.push({ Amount: Number(l.Amount ?? 0), LinkedTxn: l.LinkedTxn, LineEx: { any: [{ name: "{http://schema.intuit.com/finance/v3}NameValue", value: { Name: "txnId", Value: pur.Id } }, { value: { Name: "txnOpenBalance", Value: String(purBefore) } }, { value: { Name: "txnReferenceNumber", Value: pur.DocNumber ?? "" } }] } });
          continue;
        }
        if (lt.TxnType === "CreditMemo") {                                                           // 2e-2-1b C-5″ — CreditMemo 줄: RemainingCredit 를 줄인다(Balance 도 같이) · 모자라면 6000
          if (!inv || inv.ent !== "CreditMemo") return jres(400, { Fault: { Error: [{ Message: "Invalid Reference Id", Detail: "Invalid Reference Id : CreditMemo " + String(lt.TxnId) + " not found", code: "6240" }], type: "ValidationFault" } }, "tid-badref");
          const rem = inv.RemainingCredit ?? inv.Balance ?? inv.TotalAmt;
          if (Number(l.Amount ?? 0) > rem + 0.004) return jres(400, { Fault: { Error: [{ Message: "Business Validation Error", Detail: "Amount applied exceeds the credit memo balance", code: "6000" }], type: "ValidationFault" } }, "tid-6000");
          inv.RemainingCredit = Math.round((rem - Number(l.Amount ?? 0)) * 100) / 100; inv.Balance = inv.RemainingCredit;
          outLines.push({ Amount: Number(l.Amount ?? 0), LinkedTxn: l.LinkedTxn, LineEx: { any: [{ name: "{http://schema.intuit.com/finance/v3}NameValue", value: { Name: "txnId", Value: inv.Id } }, { value: { Name: "txnOpenBalance", Value: String(rem) } }, { value: { Name: "txnReferenceNumber", Value: inv.DocNumber } }] } });
          continue;
        }
        if (!inv || (inv.ent ?? "Invoice") !== "Invoice") return jres(400, { Fault: { Error: [{ Message: "Invalid Reference Id", Detail: "Invalid Reference Id : Invoice " + String(lt.TxnId) + " not found", code: "6240" }], type: "ValidationFault" } }, "tid-badref");
        const bal = inv.Balance ?? inv.TotalAmt;
        if (Number(l.Amount ?? 0) > bal + 0.004) return jres(400, { Fault: { Error: [{ Message: "Business Validation Error", Detail: "Amount applied exceeds the invoice balance", code: "6000" }], type: "ValidationFault" } }, "tid-6000");
        inv.Balance = Math.round((bal - Number(l.Amount ?? 0)) * 100) / 100;
        outLines.push({ Amount: Number(l.Amount ?? 0), LinkedTxn: l.LinkedTxn, LineEx: { any: [{ name: "{http://schema.intuit.com/finance/v3}NameValue", value: { Name: "txnId", Value: inv.Id } }, { value: { Name: "txnOpenBalance", Value: String(bal) } }, { value: { Name: "txnReferenceNumber", Value: inv.DocNumber } }] } });
      }
      const id = String(7000 + (++it.createdN)); for (const pur of linkedPur) pur.LinkedTxn.push({ TxnId: id, TxnType: "Payment" });   // [2e-3-2-1b]
      const total = Number(b.TotalAmt ?? 0), applied = outLines.reduce((a, l) => a + (((((l.LinkedTxn ?? []) as Record<string, unknown>[])[0] ?? {}) as Record<string, unknown>).TxnType === "CreditMemo" ? -1 : 1) * Number(l.Amount ?? 0), 0);   // [2e-2-1b C-5″: CreditMemo 줄은 붙임을 되돌리는 쪽 — 0 원 Payment 의 UnappliedAmt 는 0]
      const v: Pay = { Id: id, SyncToken: 0, TotalAmt: total, UnappliedAmt: Math.round((total - applied) * 100) / 100, CustomerRef: b.CustomerRef, TxnDate: String(b.TxnDate ?? ""), PaymentRefNum: typeof b.PaymentRefNum === "string" ? b.PaymentRefNum : null, PrivateNote: String(b.PrivateNote ?? ""), Line: outLines, voided: false, DepositToAccountRef: b.DepositToAccountRef ?? (total === 0 ? undefined : { value: "26" }), PaymentMethodRef: b.PaymentMethodRef };   // [2e-2-1b C-5″: 0 원 Payment 응답엔 DepositToAccountRef 가 없다]
      it.payments.set(id, v);
      return jres(200, { Payment: payRow(v), time: "2026-11-02T12:00:00Z" }, "tid-ppost-" + id);
    }
    const purRow = (p: Pur, withStatus = true) => ({ Id: p.Id, SyncToken: String(p.SyncToken), TxnDate: p.TxnDate, TotalAmt: p.TotalAmt, PaymentType: p.PaymentType, AccountRef: p.AccountRef, EntityRef: p.EntityRef, PrivateNote: p.PrivateNote, DocNumber: p.DocNumber, CurrencyRef: { value: "CAD" }, GlobalTaxCalculation: "NotApplicable", Line: p.Line, ...(p.LinkedTxn.length ? { LinkedTxn: p.LinkedTxn } : {}), ...(withStatus && p.status ? { status: p.status } : {}), domain: "QBO", sparse: false });   // 2e-3-2-1b 가짜 Purchase 꼴(sandbox P1 · 조회 select 에는 status 칸이 안 나온다)
    if (h.method === "POST" && /\/v3\/company\/[^/]+\/purchase\/?\?/.test(url)) {                      // 2e-3-2-1b 가짜 Purchase — 만들기(Id 없음) · Full update(Id · SyncToken 대조 · 5010 · 줄 Amount · PrivateNote 그대로 받음 · 금액 0 ∧ 「Voided - 」 = status Voided) · operation 은 어느 것도 없다
      const b = JSON.parse(h.body || "{}") as Record<string, unknown>, op = new URL(url).searchParams.get("operation");
      if (op !== null) return jres(400, { Fault: { Error: [{ Message: "Unsupported Operation", code: "500" }], type: "ValidationFault" } }, "tid-op");
      const mkLines = (ls: unknown, keepIds: boolean) => (Array.isArray(ls) ? ls as Record<string, unknown>[] : []).map((l, i) => ({ ...l, Id: keepIds && l.Id != null ? String(l.Id) : String(i + 1), LineNum: keepIds && l.LineNum != null ? l.LineNum : i + 1, Amount: Number(l.Amount ?? 0) }));
      if (b.Id != null) {
        const v = it.purchases.get(String(b.Id));
        if (!v) return jres(400, { Fault: { Error: [{ Message: "Object Not Found", Detail: "Object Not Found : Something you're trying to use has been made inactive.", code: "610" }], type: "ValidationFault" } }, "tid-610");
        if (it.voidRefuse.has(v.Id)) return jres(400, { Fault: { Error: [{ Message: "Business Validation Error", Detail: "You cannot change a transaction in a closed period", code: "6000" }], type: "ValidationFault" } }, "tid-6000");
        if (String(b.SyncToken) !== String(v.SyncToken)) return jres(400, { Fault: { Error: [{ Message: "Stale Object Error", Detail: "Stale Object Error : You and someone else were working on this at the same time.", code: "5010" }], type: "ValidationFault" } }, "tid-5010");
        v.Line = mkLines(b.Line, true); v.TotalAmt = Math.round(v.Line.reduce((a, l) => a + Number(l.Amount ?? 0), 0) * 100) / 100; v.PrivateNote = String(b.PrivateNote ?? ""); v.TxnDate = String(b.TxnDate ?? v.TxnDate); v.SyncToken++;
        v.voided = v.TotalAmt === 0 && v.PrivateNote.startsWith("Voided - "); v.status = v.voided ? "Voided" : undefined; if (v.voided) v.open = 0;
        const row = purRow(v), st = it.purchaseStatus.get(v.Id); if (st === null) delete (row as Record<string, unknown>).status; else if (st !== undefined) (row as Record<string, unknown>).status = st;
        return jres(200, { Purchase: row, time: "2026-11-08T12:00:00Z" }, "tid-pfu-" + v.Id);
      }
      const id = String(8000 + (++it.createdN)), ln = mkLines(b.Line, false), total = Math.round(ln.reduce((a, l) => a + Number(l.Amount ?? 0), 0) * 100) / 100;
      const v: Pur = { Id: id, SyncToken: 0, TxnDate: String(b.TxnDate ?? ""), TotalAmt: total, PaymentType: b.PaymentType, EntityRef: b.EntityRef, PrivateNote: String(b.PrivateNote ?? ""), DocNumber: typeof b.DocNumber === "string" ? b.DocNumber : null, Line: ln, LinkedTxn: [], AccountRef: b.AccountRef, voided: false, open: total };
      it.purchases.set(id, v);
      return jres(200, { Purchase: purRow(v), time: "2026-11-08T12:00:00Z" }, "tid-ppur-" + id);
    }
    // 3-3 가짜 JournalEntry — 만들기(sandbox ② S1 그대로: Id · SyncToken "0" · DocNumber 그대로 · Entity 에 name 붙음 · TxnTaxDetail {} · CurrencyRef CAD · ExchangeRate 1 · Line[].Id · CustomExtensions [] · ⚠️ TotalAmt 0 · HomeTotalAmt 0) · 같은 DocNumber 둘째도 성공(S2 · 중복을 막지 않는다) · Id 가 있으면 400(만들기만 — EF 가 먼저 거부하므로 닿지 않는다) · 장부 = it.journals(환불 가드의 심은 행과 같은 배열)
    const jeRow = (v: Record<string, unknown>) => !Array.isArray(v.Line) ? v : ({ ...v, Line: (v.Line as Record<string, unknown>[]).map((l) => ({ ...l, JournalEntryLineDetail: { ...(l.JournalEntryLineDetail as Record<string, unknown>), ...((l.JournalEntryLineDetail as Record<string, unknown>)?.Entity ? { Entity: { ...((l.JournalEntryLineDetail as Record<string, unknown>).Entity as Record<string, unknown>), EntityRef: { ...(((l.JournalEntryLineDetail as Record<string, unknown>).Entity as Record<string, unknown>).EntityRef as Record<string, unknown>), name: "ZZPII Customer Name" } } } : {}) } })) });   // S3: 조회 · 읽기 응답의 Entity.EntityRef.name = 손님 이름 글자
    if (h.method === "POST" && /\/v3\/company\/[^/]+\/journalentry\/?\?/.test(url)) {
      const b = JSON.parse(h.body || "{}") as Record<string, unknown>, op = new URL(url).searchParams.get("operation");
      if (op !== null || b.Id != null) return jres(400, { Fault: { Error: [{ Message: "Unsupported Operation", code: "500" }], type: "ValidationFault" } }, "tid-op");
      const id = String(10000 + (++it.createdN)), lines = (Array.isArray(b.Line) ? b.Line as Record<string, unknown>[] : []).map((l, i) => ({ ...l, Id: String(i), LineNum: i + 1, Amount: Number(l.Amount ?? 0), CustomExtensions: [] }));
      const v: Record<string, unknown> = { Id: id, SyncToken: "0", DocNumber: typeof b.DocNumber === "string" ? b.DocNumber : null, TxnDate: String(b.TxnDate ?? ""), PrivateNote: String(b.PrivateNote ?? ""), Line: lines, TxnTaxDetail: {}, CurrencyRef: { value: "CAD", name: "Canadian Dollar" }, ExchangeRate: 1, TotalAmt: 0, HomeTotalAmt: 0, Adjustment: false, domain: "QBO", sparse: false, MetaData: { CreateTime: "2026-11-09T00:00:00-08:00" } };
      it.journals.push(v);
      return jres(200, { JournalEntry: jeRow(v), time: "2026-11-09T12:00:00Z" }, "tid-je-" + id);
    }
    if (h.method === "GET" && /\/v3\/company\/[^/]+\/journalentry\/[^/?]+\?/.test(url)) {               // 3-3 가짜 JournalEntry 읽기(Line 포함)
      const id = (/\/journalentry\/([^/?]+)\?/.exec(url) ?? [])[1] ?? "", v = it.journals.find((x) => String(x.Id) === id);
      return v ? jres(200, { JournalEntry: jeRow(v), time: "2026-11-09T12:00:00Z" }, "tid-jer-" + id) : jres(404, { Fault: { Error: [{ Message: "Object Not Found", Detail: "Object Not Found : Something you're trying to use has been made inactive.", code: "610" }], type: "ValidationFault" } }, "tid-404");
    }
    if (h.method === "GET" && /\/v3\/company\/[^/]+\/purchase\/[^/?]+\?/.test(url)) {                   // 2e-3-2-1b 가짜 Purchase 읽기
      const id = (/\/purchase\/([^/?]+)\?/.exec(url) ?? [])[1] ?? "", v = it.purchases.get(id);
      return v ? jres(200, { Purchase: purRow(v), time: "2026-11-08T12:00:00Z" }, "tid-pur-" + id) : jres(404, { Fault: { Error: [{ Message: "Object Not Found", code: "610" }], type: "ValidationFault" } }, "tid-404");
    }
    if (h.method === "GET" && /\/v3\/company\/[^/]+\/payment\/[^/?]+\?/.test(url)) {                    // 2e-1c 가짜 Payment 읽기
      const id = (/\/payment\/([^/?]+)\?/.exec(url) ?? [])[1] ?? "", v = it.payments.get(id);
      return v ? jres(200, { Payment: { Id: v.Id, SyncToken: String(v.SyncToken), TxnDate: v.TxnDate, TotalAmt: v.TotalAmt, UnappliedAmt: v.UnappliedAmt, CustomerRef: v.CustomerRef, PaymentRefNum: v.PaymentRefNum, PrivateNote: v.PrivateNote, Line: v.Line }, time: "2026-11-02T12:00:00Z" }, "tid-pay-" + id) : jres(404, { Fault: { Error: [{ Message: "Object Not Found", code: "610" }], type: "ValidationFault" } }, "tid-404");
    }
    if (h.method === "POST" && /\/v3\/company\/[^/]+\/(invoice|creditmemo)\/?\?/.test(url)) {           // 2b2 가짜 인보이스 · [2c1 creditmemo] — 만들기 · void(operation=void · SyncToken 대조 · 거부)
      const key: "Invoice" | "CreditMemo" = /\/creditmemo\/?\?/.test(url) ? "CreditMemo" : "Invoice";
      const b = JSON.parse(h.body || "{}") as Record<string, unknown>, op = new URL(url).searchParams.get("operation");
      if (op === "void") {
        const v = it.invoices.get(String(b.Id ?? ""));
        if (!v || (v.ent ?? "Invoice") !== key) return jres(400, { Fault: { Error: [{ Message: "Object Not Found", Detail: "Object Not Found : Something you're trying to use has been made inactive.", code: "610" }], type: "ValidationFault" } }, "tid-610");
        if (it.voidRefuse.has(v.Id)) return jres(400, { Fault: { Error: [{ Message: "Business Validation Error", Detail: "You cannot void an invoice that has payments applied", code: "6000" }], type: "ValidationFault" } }, "tid-6000");
        if (String(b.SyncToken) !== String(v.SyncToken)) return jres(400, { Fault: { Error: [{ Message: "Stale Object Error", Detail: "Stale Object Error : You and someone else were working on this at the same time.", code: "5010" }], type: "ValidationFault" } }, "tid-5010");
        v.SyncToken++; v.TotalAmt = 0; v.TotalTax = 0; v.voided = true;
        return jres(200, { [key]: invRow(v), time: "2026-11-02T12:00:00Z" }, "tid-void-" + v.Id);
      }
      const doc = String(b.DocNumber ?? "");
      if (it.dupDoc.has(doc) || [...it.invoices.values()].some((v) => v.DocNumber === doc && (v.ent ?? "Invoice") === key)) return jres(400, { Fault: { Error: [{ Message: "Duplicate Document Number Error", Detail: "Duplicate Document Number Error : You must specify a different number. This number has already been used.", code: "6140", element: "" }], type: "ValidationFault" } }, "tid-6140");
      const lines = Array.isArray(b.Line) ? b.Line as Record<string, unknown>[] : [], sub = lines.reduce((a, l) => a + Number(l.Amount ?? 0), 0);
      const tax = it.taxOverride.get(doc) ?? Number(((b.TxnTaxDetail ?? {}) as Record<string, unknown>).TotalTax ?? 0);
      const id = String(5000 + (++it.createdN));
      const v: Inv = { Id: id, DocNumber: doc, SyncToken: 0, TotalAmt: Math.round((sub + tax) * 100) / 100, TotalTax: tax, voided: false, CustomerRef: b.CustomerRef, ent: key };
      it.invoices.set(id, v);
      return jres(200, { [key]: invRow(v), time: "2026-11-02T12:00:00Z" }, "tid-post-" + id);
    }
    if (h.method === "GET" && /\/v3\/company\/[^/]+\/(invoice|creditmemo)\/[^/?]+\?/.test(url)) {        // 2b2 인보이스 읽기 · [2c1 creditmemo]
      const key: "Invoice" | "CreditMemo" = /\/creditmemo\//.test(url) ? "CreditMemo" : "Invoice";
      const id = (/\/(?:invoice|creditmemo)\/([^/?]+)\?/.exec(url) ?? [])[1] ?? "", v = it.invoices.get(id);
      return v && (v.ent ?? "Invoice") === key ? jres(200, { [key]: invRow(v), time: "2026-11-02T12:00:00Z" }, "tid-inv-" + id) : jres(404, { Fault: { Error: [{ Message: "Object Not Found", code: "610" }], type: "ValidationFault" } }, "tid-404");
    }
    if (h.method === "POST" && /\/v3\/company\/[^/]+\/(customer|item)\/?\?/.test(url)) {                 // 2a′ 가짜 쓰기 — Intuit 실물 꼴: 2xx 몸 = { Customer | Item: {...Id, SyncToken} } · 중복 이름 400 Fault 6240
      const ent = (/\/(customer|item)\/?\?/.exec(url) ?? [])[1] ?? "", b = JSON.parse(h.body || "{}") as Record<string, unknown>, name = String(ent === "customer" ? b.DisplayName : b.Name);
      if (it.dupNames.has(name)) return jres(400, { Fault: { Error: [{ Message: "Duplicate Name Exists Error", Detail: "The name supplied already exists. : " + name, code: "6240", element: "" }], type: "ValidationFault" }, time: "2026-11-01T12:00:00Z" }, "tid-6240");
      const id = String(1000 + (++it.createdN)), requestid = new URL(url).searchParams.get("requestid");
      it.created.push({ ent, id, name, sku: typeof b.Sku === "string" ? b.Sku : null, requestid });
      const row = ent === "customer" ? { Id: id, DisplayName: name, CompanyName: b.CompanyName, SyncToken: "0", PrimaryEmailAddr: b.PrimaryEmailAddr, BillAddr: b.BillAddr, Taxable: b.Taxable, domain: "QBO", sparse: false }
        : { Id: id, Name: name, Sku: b.Sku ?? null, Type: b.Type, SyncToken: "0", IncomeAccountRef: b.IncomeAccountRef, domain: "QBO", sparse: false };
      return jres(200, { [ent === "customer" ? "Customer" : "Item"]: row, time: "2026-11-01T12:00:00Z" }, "tid-post-" + id);
    }
    if (url.includes("/query?")) {                                                                   // QueryResponse 꼴 — 엔터티 이름 키 · startPosition · maxResults · count(*) 는 totalCount 만
      const q = new URL(url).searchParams.get("query") ?? "";
      const ent = (/\bfrom\s+([A-Za-z]+)/i.exec(q) ?? [])[1] ?? "";
      const entity = QUERY_ENTITIES.find((e) => e.toLowerCase() === ent.toLowerCase()) ?? ent;
      if (/^select\s+count\s*\(\s*\*\s*\)/i.test(q)) return jres(200, { QueryResponse: { totalCount: 1234 }, time: "2026-11-01T12:00:00Z" }, "tid-count");
      const byRange = /\bfrom\s+(Purchase|JournalEntry|RefundReceipt)\s+where\s+TxnDate\s*>=\s*'(\d{4}-\d{2}-\d{2})'\s+and\s+TxnDate\s*<=\s*'(\d{4}-\d{2}-\d{2})'/i.exec(q);   // 2e-3-2-1b 손 기록 가드 — 서버는 TxnDate 만 거른다(sandbox 2-e) · STARTPOSITION · MAXRESULTS 로 쪽
      if (byRange) {
        const ent = byRange[1], from = byRange[2], to = byRange[3], mx = Number((/\bmaxresults\s+(\d+)/i.exec(q) ?? [])[1] ?? 100), st = Number((/\bstartposition\s+(\d+)/i.exec(q) ?? [])[1] ?? 1);
        const all = (ent === "Purchase" ? [...it.purchases.values()].map((v) => purRow(v, false)) : ent === "JournalEntry" ? it.journals : it.refundReceipts).filter((r) => { const d = String((r as Record<string, unknown>).TxnDate ?? ""); return d >= from && d <= to; });
        const rows = all.slice(st - 1, st - 1 + mx);
        return jres(200, { QueryResponse: rows.length ? { [ent]: rows, startPosition: st, maxResults: rows.length } : {}, time: "2026-11-08T12:00:00Z" }, "tid-qrange");
      }
      const byPurDate = /\bfrom\s+Purchase\s+where\s+TxnDate\s*=\s*'(\d{4}-\d{2}-\d{2})'/i.exec(q);                 // 2e-3-2-1b 환불 unknown 풀기 — 그 날의 Purchase 전부
      if (byPurDate) { const rows = [...it.purchases.values()].filter((v) => v.TxnDate === byPurDate[1]).map((v) => purRow(v, false)); return jres(200, { QueryResponse: rows.length ? { Purchase: rows, startPosition: 1, maxResults: rows.length } : {}, time: "2026-11-08T12:00:00Z" }, "tid-qpur"); }
      const byDate = /\bfrom\s+Payment\s+where\s+TxnDate\s*=\s*'(\d{4}-\d{2}-\d{2})'/i.exec(q);                      // 2e-1c 결제 unknown 풀기 — 그 날의 Payment 전부(가짜 장부)
      if (byDate) { const rows = [...it.payments.values()].filter((v) => v.TxnDate === byDate[1]).map((v) => ({ Id: v.Id, TotalAmt: v.TotalAmt, UnappliedAmt: v.UnappliedAmt, SyncToken: String(v.SyncToken), PrivateNote: v.PrivateNote, PaymentRefNum: v.PaymentRefNum, CustomerRef: v.CustomerRef, TxnDate: v.TxnDate })); return jres(200, { QueryResponse: rows.length ? { Payment: rows, startPosition: 1, maxResults: rows.length } : {}, time: "2026-11-02T12:00:00Z" }, "tid-qpay"); }
      const openRow = (v: Inv) => ({ Id: v.Id, SyncToken: String(v.SyncToken), DocNumber: v.DocNumber, TxnDate: "2026-10-15", TotalAmt: v.TotalAmt, Balance: v.Balance ?? v.TotalAmt, CustomerRef: v.CustomerRef ?? { value: "7190", name: "ZZPII Customer" } });   // 2e-1d-2 ② 실물 꼴(CustomerRef 에 name 이 온다)
      const byIn = /\bfrom\s+Invoice\s+where\s+DocNumber\s+in\s*\(([^)]*)\)/i.exec(q);                                   // 2e-1d-2 opening_candidates — 가짜 장부의 Invoice 중 번호 집합 안
      if (byIn) { const set = new Set([...byIn[1].matchAll(/'((?:[^']|'')*)'/g)].map((m) => m[1].replace(/''/g, "'"))); const rows = [...it.invoices.values()].filter((v) => (v.ent ?? "Invoice") === "Invoice" && set.has(v.DocNumber)).map(openRow); return jres(200, { QueryResponse: rows.length ? { Invoice: rows, startPosition: 1, maxResults: rows.length, totalCount: rows.length } : {}, time: "2026-11-06T12:00:00Z" }, "tid-qin"); }
      const byLike = /\bfrom\s+Invoice\s+where\s+DocNumber\s+like\s+'((?:[^']|'')*)'/i.exec(q);                             // 2e-1d-2 opening_search
      if (byLike) { const pat = byLike[1].replace(/''/g, "'").replace(/^%/, "").replace(/%$/, ""); const rows = [...it.invoices.values()].filter((v) => (v.ent ?? "Invoice") === "Invoice" && v.DocNumber.includes(pat)).map(openRow); return jres(200, { QueryResponse: rows.length ? { Invoice: rows, startPosition: 1, maxResults: rows.length } : {}, time: "2026-11-06T12:00:00Z" }, "tid-qlike"); }
      const byDoc = /\bwhere\s+DocNumber\s*=\s*'((?:[^']|'')*)'/i.exec(q);                                      // 2b2 DocNumber 조회 — 가짜 장부에서
      if (byDoc && entity === "JournalEntry") { const dn = byDoc[1].replace(/''/g, "'"); const rows = it.journals.filter((v) => String(v.DocNumber ?? "") === dn).reverse().map((v) => ({ Id: v.Id, DocNumber: v.DocNumber, TxnDate: v.TxnDate, PrivateNote: v.PrivateNote, SyncToken: v.SyncToken, Line: (jeRow(v) as Record<string, unknown>).Line })); return jres(200, { QueryResponse: rows.length ? { JournalEntry: rows, startPosition: 1, maxResults: rows.length, totalCount: rows.length } : {}, time: "2026-11-09T12:00:00Z" }, "tid-jedoc"); }   // 3-3 sandbox S3: 고른 칸에 Line 을 안 넣었는데 Line 이 함께 온다(손님 이름 글자 포함) · 최신 먼저(198 · 197)
      if (byDoc) { const dn = byDoc[1].replace(/''/g, "'"); const rows = [...it.invoices.values()].filter((v) => v.DocNumber === dn && (v.ent ?? "Invoice") === entity).map((v) => ({ Id: v.Id, DocNumber: v.DocNumber, SyncToken: String(v.SyncToken), TotalAmt: v.TotalAmt })); return jres(200, { QueryResponse: rows.length ? { [entity]: rows, startPosition: 1, maxResults: rows.length } : {}, time: "2026-11-02T12:00:00Z" }, "tid-bydoc"); }   // 2c1: from Invoice | CreditMemo 로 가른다
      const byName = /\bwhere\s+(DisplayName|Name)\s*=\s*'((?:[^']|'')*)'/i.exec(q);                      // 2a′ unknown 풀기 — 가짜 쓰기가 하나라도 있었으면 created 에서 그 이름(따옴표 둘 → 하나) · 없으면 옛 시험의 기본 3 행
      if (byName && it.created.length > 0) { const nm = byName[2].replace(/''/g, "'"); const rows = it.created.filter((c) => c.ent === (entity === "Customer" ? "customer" : "item") && c.name === nm).map((c) => entity === "Customer" ? { Id: c.id, DisplayName: c.name, SyncToken: "0" } : { Id: c.id, Name: c.name, Sku: c.sku, SyncToken: "0" }); return jres(200, { QueryResponse: rows.length ? { [entity]: rows, startPosition: 1, maxResults: rows.length } : {}, time: "2026-11-01T12:00:00Z" }, "tid-byname"); }
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
    return jres(404, { Fault: { Error: [{ Message: "no route", code: "404" }], type: "SystemFault" } });
  };
  return { it, fetch };
}

// ── 가짜 DB(창구 열둘 + last_error_set · 20261029160000 의 글 그대로) ──
type Conn = { env: string; realm_id: string; status: string; company_name: string | null; token_version: number; access_exp: number; refresh_exp: number | null; refresh: string; access: string; lease_until: number | null; last_error: string | null; connected_by: string };
type Pull = { started_at: number; next_start: number; received: number; pages: number; finished_at: number | null };
type Ent = { name: string; sku: string | null; fetched_at: number; gone_at: number | null };
type Db = { conn: Conn | null; states: Map<string, { staff_id: string; env: string; created_at: number; used_at: number | null }>; pin: Record<string, string | null>; calls: string[]; mails: number; saveFails: boolean; staleOnSave: boolean; lastErrors: string[]; versionBumpOnSleep: boolean; pulls: Map<string, Pull>; ents: Map<string, Map<string, Ent>>; keys: Record<string, string | null>; jobs: Map<string, Job>; links: { ims_kind: string; ims_id: string; qbo_id: string; qbo_name: string; matched_by: string }[]; txns: Map<string, Txn>; claimKinds: string[][]; opening: Opening };   // keys = JWT → perms 열쇠('qbo' · 'qbo:read' · null) · qbo-sync-2a 945 · jobs · links = 2a′ 일감 상태기(20261102003000 · 20261102030000 의 규칙 · 거부 글 그대로)
type Job = { id: string; kind: string; ims_kind: string; ims_id: string; state: string; attempts: number; request_id: string; name: string; name_alt: string | null; sku: string | null; body: Record<string, unknown>; qbo_id: string | null; qbo_name: string | null; last_error: string | null; claimed_at: number | null; sent_at: number | null; doc_number?: string | null; totals?: { total: number; tax: number } | null; warning?: string | null; needs?: { kind: string; ims_id: string; name: string; parent?: { ims_id: string; name: string } }[]; wait_job?: string | null; blocked_by?: string | null; fingerprint?: string | null; check_lines?: { txn_type?: string; invoice_number?: string; qbo_invoice_id?: string; credit_number?: string; qbo_creditmemo_id?: string; refund?: string; qbo_purchase_id?: string; amount: number }[] | null; lookup?: Record<string, unknown> | null; pay_totals?: { amount: number; unapplied: number } | null };   // [2e-3-2-1b txn_type Expense · refund · qbo_purchase_id]   // 2d1: needs · wait_job · blocked_by · [2e-1c fingerprint · check_lines · lookup · pay_totals] · [2e-2-1b check_lines 에 txn_type · credit_number · qbo_creditmemo_id]
type OpeningInv = { invoice_id: string; invoice_number: string; match: "none" | "auto" | "manual"; reason: string | null; warning: string | null; warn: string | null };   // 2e-1d-2 가짜 이월 인보이스(warn = 사람 짝 때 DB 검사가 낼 경고 글)
type Opening = { list: OpeningInv[]; held: Map<string, string>; cands: { numbers: string[]; rows: Record<string, unknown>[] }[]; matches: { invoice_id: string; qbo_id: string; row: Record<string, unknown>; ack: boolean }[]; failCall: number | null };
type Txn = { qbo_id: string; doc_number: string; sync_token: string | null; total_amt: number | null; total_tax: number | null; mismatch: string | null; voided_at: number | null; fingerprint?: string | null; unapplied?: number | null };   // [2e-1c fingerprint · unapplied]   // 2b2 qbo_txn 거울(20261102040000 의 942 규칙 · 글 그대로)
const STAFF = "11111111-1111-4111-8111-111111111111";
const STAFF_MGR = "22222222-2222-4222-8222-222222222222";
const staffOf = (jwt: string) => jwt === "JWT-ADMIN" ? STAFF : STAFF_MGR;
function dbFake(clock: () => number): { db: Db; rpcUser: Deps["rpcUser"]; rpcService: Deps["rpcService"] } {
  const db: Db = { conn: null, states: new Map(), pin: { sandbox: null, production: null }, calls: [], mails: 0, saveFails: false, staleOnSave: false, lastErrors: [], versionBumpOnSleep: false, pulls: new Map(), ents: new Map(), keys: { "JWT-ADMIN": "qbo", "JWT-MGR": null }, jobs: new Map(), links: [], txns: new Map(), claimKinds: [], opening: { list: [], held: new Map(), cands: [], matches: [], failCall: null } };   // 2a: admin 도 열쇠를 켜야 한다 — 기본 가짜 admin 은 켜 둔다
  const refuse = (msg: string) => { throw new RpcError(400, msg); };
  const keyOf = (jwt: string) => db.keys[jwt] === "qbo" ? "write" : db.keys[jwt] === "qbo:read" ? "read" : null;
  const rpcUser: Deps["rpcUser"] = async (fn, args, jwt) => {
    db.calls.push("user:" + fn);
    if (jwt !== "JWT-ADMIN" && jwt !== "JWT-MGR") throw new RpcError(401, "JWT expired");
    if (fn === "qbo_status") return db.conn ? { status: db.conn.status, env: db.conn.env, realm_id: db.conn.realm_id, company_name: db.conn.company_name, token_version: db.conn.token_version, last_error: db.conn.last_error, caller_is_admin: jwt === "JWT-ADMIN", caller_qbo: keyOf(jwt), pinned_realm: db.pin } : { status: "none", caller_is_admin: jwt === "JWT-ADMIN", caller_qbo: keyOf(jwt), pinned_realm: db.pin };
    // qbo-sync-2a 945 — 열쇠 문(20261102003000 의 거부 글 그대로): qbo_key_gate · 1a 짝 · 받기 창구(qbo_sync_gate = qbo_key_gate(true)) · 그 밖은 admin 만
    const KEY_FNS = ["qbo_key_gate", "qbo_pull_begin", "qbo_entity_upsert", "qbo_pull_finish"];
    if (fn === "qbo_key_gate") { const write = args.p_write !== false; if (db.keys[jwt] === "qbo" || (!write && db.keys[jwt] === "qbo:read")) return staffOf(jwt); refuse(`Your account does not have the 'qbo'${write ? " (write)" : ""} permission — ask an admin to switch it on in Staff — nothing was changed`); }
    // 2e-1d-2 창구 셋(20261105184613 의 거부 글 · 반환 키 꼴) — list 는 qbo_key_gate(false) · candidates · match 는 qbo_key_gate(true)
    if (fn === "qbo_opening_list") {
      if (db.keys[jwt] !== "qbo" && db.keys[jwt] !== "qbo:read") refuse("Your account does not have the 'qbo' permission — ask an admin to switch it on in Staff — nothing was changed");
      const rows = db.opening.list.map((x) => ({ invoice_id: x.invoice_id, invoice_number: x.invoice_number, match: x.match, store_name: "ZZPII Store " + x.invoice_number, bill_to_name: "ZZPII Bill-to", reason: x.reason, warning: x.warning, candidates: [] }));
      return { realm_id: db.conn?.realm_id ?? null, summary: { invoices: rows.length, unmatched: rows.filter((r) => r.match === "none").length }, rows };
    }
    if (fn === "qbo_opening_candidates" || fn === "qbo_opening_match") {
      if (db.keys[jwt] !== "qbo") refuse("Your account does not have the 'qbo' (write) permission — ask an admin to switch it on in Staff — nothing was changed");
      const SEVEN = ["Id", "SyncToken", "DocNumber", "TxnDate", "TotalAmt", "Balance", "CustomerRef"];
      const checkRow = (r: Record<string, unknown>) => {                                           // EF 의 줄이기 증명 — 일곱 칸 밖 · CustomerRef 가 {value} 객체가 아니면 거부
        const extra = Object.keys(r).filter((k) => !SEVEN.includes(k));
        if (extra.length) refuse("test fake: row carries fields beyond the seven: " + extra.join(","));
        const cr = r.CustomerRef as Record<string, unknown> | null;
        if (!cr || typeof cr !== "object" || Object.keys(cr).some((k) => k !== "value")) refuse("test fake: CustomerRef must be an object with value only");
      };
      if (fn === "qbo_opening_candidates") {
        const nums = (args.p_doc_numbers ?? []) as string[], rows = (args.p_rows ?? []) as Record<string, unknown>[];
        if (!Array.isArray(rows)) refuse("rows must be a JSON array of QuickBooks Invoice rows");
        for (const r of rows) checkRow(r);
        db.opening.cands.push({ numbers: nums, rows });
        if (db.opening.failCall === db.opening.cands.length) refuse("canceling statement due to statement timeout");
        if (nums.length === 0) return { checked: 0, matched: 0, taken: 0, already: 0, review_changed: 0, review_same: 0, unknown_numbers: 0, rows: [] };
        const out: Record<string, unknown>[] = []; let matched = 0, taken = 0, already = 0, changed = 0, same = 0, unknown = 0;
        for (const n of [...nums].sort()) {
          const inv = db.opening.list.find((x) => x.invoice_number === n);
          if (!inv) { unknown++; continue; }
          if (inv.match !== "none") { already++; out.push({ invoice_number: n, result: "already", qbo_id: db.opening.held.get(n) ?? null, match_how: inv.match }); continue; }
          const hits = rows.filter((r) => String(r.DocNumber ?? "").trim() === n);
          if (hits.length === 1 && ![...db.opening.held.values()].includes(String(hits[0].Id))) { inv.match = "auto"; inv.reason = null; db.opening.held.set(n, String(hits[0].Id)); matched++; out.push({ result: "matched", invoice_id: inv.invoice_id, invoice_number: n, qbo_id: String(hits[0].Id), txn_id: "txn-" + n, match_how: "auto", requeue_touched: 0 }); continue; }
          let reason: string, warning: string;
          if (hits.length === 1) { reason = "taken"; warning = `QuickBooks invoice #${hits[0].Id} is already matched to IMS invoice ${[...db.opening.held.entries()].find((e) => e[1] === String(hits[0].Id))?.[0]} — unmatch that one first`; taken++; }
          else if (hits.length === 0) { reason = "not_found"; warning = `no QuickBooks invoice is numbered ${n}`; }
          else { reason = "many"; warning = `QuickBooks has ${hits.length} invoices numbered ${n} — pick one by hand`; }
          if (reason === "taken") { inv.reason = reason; inv.warning = warning; out.push({ result: "taken", invoice_id: inv.invoice_id, invoice_number: n, qbo_id: String(hits[0].Id), holder: "x" }); continue; }
          if (inv.reason === reason && inv.warning === warning) same++; else { inv.reason = reason; inv.warning = warning; changed++; }
          out.push({ invoice_number: n, invoice_id: inv.invoice_id, result: "review", reason, warning, candidates: hits.length });
        }
        return { checked: matched + taken + already + changed + same, matched, taken, already, review_changed: changed, review_same: same, unknown_numbers: unknown, rows: out };
      }
      const qid = String(args.p_qbo_id ?? "").trim(), row = args.p_row as Record<string, unknown> | null, ack = args.p_ack === true;
      if (!qid) refuse("Pick the QuickBooks invoice to match — nothing was saved");
      if (!row || typeof row !== "object") refuse("row must be the QuickBooks Invoice row read by id — nothing was saved");
      checkRow(row!);
      if (String(row!.Id ?? "").trim() !== qid) refuse(`The row given is QuickBooks Invoice #${row!.Id ?? "?"} — not #${qid} — read it again`);
      const inv = db.opening.list.find((x) => x.invoice_id === String(args.p_invoice_id));
      if (!inv) refuse(`No IMS invoice ${args.p_invoice_id} — nothing was matched`);
      if (inv!.match !== "none") refuse(`Invoice ${inv!.invoice_number} is already matched to QuickBooks Invoice #${db.opening.held.get(inv!.invoice_number)} — unmatch it first — nothing was saved`);
      const holder = [...db.opening.held.entries()].find((e) => e[1] === qid);
      if (holder) refuse(`QuickBooks Invoice #${qid} is already matched to IMS invoice ${holder[0]} — unmatch that one first — nothing was saved`);
      const warns: string[] = [];
      if (String(row!.DocNumber ?? "") !== inv!.invoice_number) warns.push(`QuickBooks invoice #${qid} is numbered "${row!.DocNumber ?? ""}", not ${inv!.invoice_number}`);
      if (inv!.warn) warns.push(inv!.warn);
      const warning = warns.length ? warns.join(" · ") : null;
      if (warning && !ack) refuse(`QuickBooks Invoice #${qid} does not look like IMS invoice ${inv!.invoice_number}: ${warning} — confirm to match it anyway — nothing was saved`);
      db.opening.matches.push({ invoice_id: inv!.invoice_id, qbo_id: qid, row: row!, ack });
      inv!.match = "manual"; inv!.reason = null; inv!.warning = warning; db.opening.held.set(inv!.invoice_number, qid);
      return { result: "matched", invoice_id: inv!.invoice_id, invoice_number: inv!.invoice_number, qbo_id: qid, txn_id: "txn-" + inv!.invoice_number, match_how: "manual", requeue_touched: 0, acked: warning !== null, warning };
    }
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
      // ── 2a′ 일감 창구(service) — 20261102003000 · 20261102030000 의 상태 규칙 · 거부 글 그대로 ──
      case "qbo_job_unknown_list": return [...db.jobs.values()].filter((j) => j.state === "unknown").map((j) => ({ job_id: j.id, kind: j.kind, ims_kind: j.ims_kind, ims_id: j.ims_id, qbo_name: j.qbo_name, sku: j.ims_kind === "product" ? j.sku : null, request_id: j.request_id, attempts: j.attempts, last_error: j.last_error }));
      case "qbo_job_claim": {                                                                          // 2d1: p_job_ids(고른 id 만) · ② 부모 sent → queued · ④ needs → need 일감 + blocked(손님 우선) · wait_job → blocked · need_jobs · requested — 20261102150000 의 규칙 · 글 그대로
        let stale = 0; for (const j of db.jobs.values()) if (j.state === "sending" && j.claimed_at !== null && j.claimed_at < clock() - 600_000) { j.state = "unknown"; j.claimed_at = null; j.last_error = (j.last_error ? j.last_error + " · " : "") + "stale: still sending"; stale++; }
        const kinds = Array.isArray(args.p_kinds) ? args.p_kinds as string[] : ["customer", "item"]; db.claimKinds.push(kinds);                 // 2b1: p_kinds 기본 customer · item
        const pick = Array.isArray(args.p_job_ids) ? [...new Set((args.p_job_ids as string[]).map(String))] : null;
        if (pick !== null && pick.length === 0) refuse("job_ids must name at least one job — nothing was read");
        if (pick !== null && pick.length > 200) refuse(`job_ids may name at most 200 jobs in one call (got ${pick.length}) — nothing was read`);
        let unblocked = 0; for (const j of db.jobs.values()) if (j.state === "blocked" && j.blocked_by && db.jobs.get(j.blocked_by)?.state === "sent") { j.state = "queued"; j.blocked_by = j.blocked_by; unblocked++; }
        const cand = [...db.jobs.values()].filter((j) => j.state === "queued" && kinds.includes(j.kind) && (pick === null || pick.includes(j.id)));
        const picked = pick === null ? cand.slice(0, Math.max(1, Math.min(Number(args.p_limit ?? 15), 50))) : cand;
        for (const j of picked) { j.state = "sending"; j.claimed_at = clock(); j.attempts++; }
        const needJobs: Record<string, unknown>[] = [], rows: Record<string, unknown>[] = []; let blockedNeeds = 0, blockedInv = 0;
        const openOf = (kind: string, imsId: string) => [...db.jobs.values()].find((x) => x.kind === kind && x.ims_id === imsId && !["sent", "skipped"].includes(x.state));
        const mk = (kind: string, imsId: string, name: string): Job => { const n = ++jobN; const j: Job = { id: "job-" + n, kind, ims_kind: kind === "customer" ? "customer" : "product", ims_id: imsId, state: "queued", attempts: 0, request_id: "11111111-2222-4333-8444-" + String(n).padStart(12, "0"), name, name_alt: null, sku: kind === "item" ? "SKU-" + n : null, body: kind === "customer" ? { DisplayName: name } : { Name: name, Type: "Service" }, qbo_id: null, qbo_name: null, last_error: null, claimed_at: null, sent_at: null, warning: null, blocked_by: null }; db.jobs.set(j.id, j); return j; };
        for (const j of picked) {
          const pending = (j.needs ?? []).filter((n) => !db.links.some((l) => l.ims_id === n.ims_id));
          if (pending.length > 0) {
            let last: string | null = null, cust: string | null = null;
            for (const n of pending) {
              let nj = openOf(n.kind, n.ims_id); const existing = !!nj; let parentId: string | null = null;
              if (!nj) { nj = mk(n.kind, n.ims_id, n.name); if (n.parent && !db.links.some((l) => l.ims_id === n.parent!.ims_id)) { let pj = openOf("customer", n.parent.ims_id); const pex = !!pj; if (!pj) pj = mk("customer", n.parent.ims_id, n.parent.name); nj.state = "blocked"; nj.blocked_by = pj.id; parentId = pj.id; needJobs.push({ job_id: pj.id, kind: "customer", ims_kind: "customer", ims_id: pj.ims_id, state: pj.state, name: null, existing: pex, for_job: nj.id, parent_job: null }); } }
              needJobs.push({ job_id: nj.id, kind: n.kind, ims_kind: nj.ims_kind, ims_id: n.ims_id, state: nj.state, name: n.name, existing, for_job: j.id, parent_job: parentId });
              last = nj.id; if (n.kind === "customer") cust = nj.id;
            }
            j.state = "blocked"; j.blocked_by = cust ?? last; j.claimed_at = null; j.warning = `waiting for ${pending.length} QuickBooks record(s) to be created first`; blockedNeeds++; continue;
          }
          if (j.wait_job && db.jobs.get(j.wait_job)?.state !== "sent") { j.state = "blocked"; j.blocked_by = j.wait_job; j.claimed_at = null; j.warning = `waiting for invoice ${db.jobs.get(j.wait_job)?.doc_number ?? "?"} to reach QuickBooks first`; blockedInv++; continue; }
          rows.push({ job_id: j.id, kind: j.kind, ims_kind: j.ims_kind, ims_id: j.ims_id, attempt: j.attempts, request_id: j.request_id, name: j.name, name_alt: j.name_alt, sku: j.sku, doc_number: j.doc_number ?? null, qbo_id: j.kind === "invoice_void" ? (j.body.Id != null ? String(j.body.Id) : null) : null, body: j.body, warnings: [], totals: j.totals ? { taxable: null, tax: j.totals.tax, total: j.totals.total } : null,
            fingerprint: j.fingerprint ?? null, check_lines: j.check_lines ?? null, lookup: j.lookup ?? null });   // 2e-1c
        }
        for (const id of pick ?? []) { const j = db.jobs.get(id); if (!j || j.state !== "blocked" || picked.some((x) => x.id === id)) continue;   // 2d1 ⑤ 되살리기 — blocked 로 남은 일감의 열린 need(부모 blocked_by + needs) 를 need_jobs 로
          const bb = j.blocked_by ? db.jobs.get(j.blocked_by) : null; if (bb && !["sent", "skipped"].includes(bb.state)) needJobs.push({ job_id: bb.id, kind: bb.kind, ims_kind: bb.ims_kind, ims_id: bb.ims_id, state: bb.state, name: null, existing: true, for_job: j.id, parent_job: null });
          for (const n of (j.needs ?? []).filter((n) => !db.links.some((l) => l.ims_id === n.ims_id))) { const oj = openOf(n.kind, n.ims_id); if (oj && oj.id !== j.blocked_by) needJobs.push({ job_id: oj.id, kind: n.kind, ims_kind: oj.ims_kind, ims_id: n.ims_id, state: oj.state, name: n.name, existing: true, for_job: j.id, parent_job: null }); } }
        const requested = (pick ?? []).map((id) => { const j = db.jobs.get(id); const was = picked.some((x) => x.id === id);
          const result = !j ? "not_found" : was ? (j.state === "sending" ? "claimed" : j.state) : j.state !== "queued" ? "not_queued" : !kinds.includes(j.kind) ? "wrong_kind" : "locked";
          const reason = !j ? "no such job" : was ? (j.state === "blocked" ? j.warning ?? null : j.state === "failed" ? j.last_error : null) : j.state !== "queued" ? `the job is ${j.state} — not sent` + (j.state === "blocked" ? ` (${j.warning ?? "waiting for another job"})` : j.state === "failed" || j.state === "skipped" ? " — retry it first" : j.state === "unknown" ? " — retry it with a note after checking QuickBooks" : j.state === "sending" ? " (another send is working on it)" : "") : !kinds.includes(j.kind) ? `kind ${j.kind} is not sent by this worker` : "another send holds the job — try again in a moment";
          return { job_id: id, kind: j?.kind ?? null, state: j?.state ?? null, result, reason }; });
        return { recovered_unknown: stale, unblocked, claimed: picked.length, body_failed: 0, blocked_for_needs: blockedNeeds, blocked_for_invoice: blockedInv, picked: pick, need_jobs: needJobs, requested, jobs: rows };
      }
      case "qbo_job_done": {
        const j = db.jobs.get(String(args.p_job)); if (!j) refuse(`Job ${args.p_job} not found — nothing was saved`);
        if (!["sending", "unknown"].includes(j!.state)) refuse(`Only a job being sent, or one whose result is unknown, can be finished (this one is ${j!.state}) — nothing was saved`);
        if (!args.p_qbo_id || !args.p_qbo_name) refuse("qbo_id and qbo_name are required — nothing was saved");
        j!.state = "sent"; j!.sent_at = clock(); j!.claimed_at = null; j!.qbo_id = String(args.p_qbo_id); j!.qbo_name = String(args.p_qbo_name); if (args.p_note) { j!.attempts++; j!.last_error = (j!.last_error ? j!.last_error + " · " : "") + String(args.p_note); }
        if (j!.kind === "invoice" || j!.kind === "credit") {                                         // 2b1 invoice → qbo_txn + 942 대조(mismatch · 상태는 sent) · [2c1 credit 도]
          const ta = typeof args.p_total_amt === "number" ? args.p_total_amt : null, tx = typeof args.p_total_tax === "number" ? args.p_total_tax : null, t = j!.totals ?? { total: 0, tax: 0 };
          const word = j!.kind === "credit" ? "credit note" : "invoice", qtype = j!.kind === "credit" ? "CreditMemo" : "Invoice";
          const mismatch = ta === null || tx === null ? `QuickBooks did not return TotalAmt / TotalTax — check ${word} ${j!.doc_number} in QuickBooks` : (ta !== t.total || tx !== t.tax) ? `QuickBooks total ${ta} / tax ${tx} differs from IMS ${t.total} / ${t.tax} — check ${word} ${j!.doc_number} in QuickBooks (942)` : null;
          if ([...db.txns.entries()].some(([k, v]) => v.qbo_id === j!.qbo_id && k !== j!.ims_id)) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: `QuickBooks ${qtype} #${j!.qbo_id} is already recorded for another IMS invoice — check both in QuickBooks and fix by hand`, unblocked: 0, mismatch }; }
          db.txns.set(j!.ims_id, { qbo_id: j!.qbo_id, doc_number: j!.qbo_name, sync_token: typeof args.p_sync_token === "string" ? args.p_sync_token : null, total_amt: ta, total_tax: tx, mismatch, voided_at: null });
          if (mismatch) j!.warning = (j!.warning ? j!.warning + " · " : "") + mismatch;
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked: 0, mismatch };
        }
        if (j!.kind === "credit_apply") {                                                            // 2e-2-1b credit_apply → qbo_txn credit_alloc ↔ Payment(지문 없음) + TotalAmt 0 · UnappliedAmt 0 대조(20261103200000 의 글 그대로)
          const ta = typeof args.p_total_amt === "number" ? args.p_total_amt : null, ua = typeof args.p_unapplied_amt === "number" ? args.p_unapplied_amt : null, label = j!.name;
          const mismatch = ta === null ? `QuickBooks did not return TotalAmt — check credit application ${label} in QuickBooks` : ta !== 0 ? `QuickBooks total ${ta} is not 0 — check credit application ${label} in QuickBooks (942)` : (ua !== null && ua !== 0) ? `QuickBooks unapplied ${ua} is not 0 — check credit application ${label} in QuickBooks (942)` : null;
          if ([...db.txns.entries()].some(([k, v]) => v.qbo_id === j!.qbo_id && k !== j!.ims_id)) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: `QuickBooks Payment #${j!.qbo_id} is already recorded for another IMS record — check both in QuickBooks and fix by hand`, unblocked: 0, mismatch }; }
          db.txns.set(j!.ims_id, { qbo_id: j!.qbo_id, doc_number: j!.qbo_name, sync_token: typeof args.p_sync_token === "string" ? args.p_sync_token : null, total_amt: ta, total_tax: null, mismatch, voided_at: null, fingerprint: null, unapplied: ua });
          if (mismatch) j!.warning = (j!.warning ? j!.warning + " · " : "") + mismatch;
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked: 0, mismatch, reconcile: { action: "same" } };
        }
        if (j!.kind === "opening_credit") {                                                          // 2e-3-1b opening_credit → qbo_txn opening_credit ↔ 「쓰기」 CreditMemo + 대조(TotalAmt = 붙임 금액 ∧ TotalTax 0 · 20261107044131 의 글 그대로)
          const ta = typeof args.p_total_amt === "number" ? args.p_total_amt : null, tx = typeof args.p_total_tax === "number" ? args.p_total_tax : null, amt = j!.totals?.total ?? 0, label = j!.name;
          const mismatch = ta === null || tx === null ? `QuickBooks did not return TotalAmt / TotalTax — check opening credit ${label} in QuickBooks` : (ta !== amt || tx !== 0) ? `QuickBooks total ${ta} / tax ${tx} differs from IMS ${amt} / 0 — check opening credit ${label} in QuickBooks (942)` : null;
          if ([...db.txns.entries()].some(([k, v]) => v.qbo_id === j!.qbo_id && k !== j!.ims_id)) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: `QuickBooks CreditMemo #${j!.qbo_id} is already recorded for another IMS record — check both in QuickBooks and fix by hand`, unblocked: 0, mismatch }; }
          db.txns.set(j!.ims_id, { qbo_id: j!.qbo_id, doc_number: j!.qbo_name, sync_token: typeof args.p_sync_token === "string" ? args.p_sync_token : null, total_amt: ta, total_tax: tx, mismatch, voided_at: null });
          if (mismatch) j!.warning = (j!.warning ? j!.warning + " · " : "") + mismatch;
          let unblocked = 0; for (const x of db.jobs.values()) if (x.state === "blocked" && x.blocked_by === j!.id) { x.state = "queued"; unblocked++; }   // DB done 끝의 「부모 sent → blocked 를 queued」 — opening_apply 가 여기서 풀린다
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked, mismatch, reconcile: { action: "same" } };
        }
        if (j!.kind === "opening_credit_void") {                                                     // 2e-3-1b opening_credit_void → voided_at
          const t = db.txns.get(j!.ims_id);
          if (!t) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: "voided in QuickBooks but IMS has no sent opening credit memo on file to mark — check qbo_txn by hand", unblocked: 0, mismatch: null }; }
          t.voided_at = clock(); if (typeof args.p_sync_token === "string") t.sync_token = args.p_sync_token;
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked: 0, mismatch: null, reconcile: { action: "none" } };
        }
        if (j!.kind === "opening_apply") {                                                           // 2e-3-1b opening_apply → qbo_txn opening_alloc ↔ Payment(지문 없음) + TotalAmt 0 · UnappliedAmt 0 대조(가짜 장부는 ims_id 하나에 한 줄 — 붙임의 Payment 짝은 ims_id + ":apply" 로 둔다)
          const ta = typeof args.p_total_amt === "number" ? args.p_total_amt : null, ua = typeof args.p_unapplied_amt === "number" ? args.p_unapplied_amt : null, label = j!.name;
          const mismatch = ta === null ? `QuickBooks did not return TotalAmt — check opening credit application ${label} in QuickBooks` : ta !== 0 ? `QuickBooks total ${ta} is not 0 — check opening credit application ${label} in QuickBooks (942)` : (ua !== null && ua !== 0) ? `QuickBooks unapplied ${ua} is not 0 — check opening credit application ${label} in QuickBooks (942)` : null;
          if ([...db.txns.entries()].some(([k, v]) => v.qbo_id === j!.qbo_id && k !== j!.ims_id + ":apply")) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: `QuickBooks Payment #${j!.qbo_id} is already recorded for another IMS record — check both in QuickBooks and fix by hand`, unblocked: 0, mismatch }; }
          db.txns.set(j!.ims_id + ":apply", { qbo_id: j!.qbo_id, doc_number: j!.qbo_name, sync_token: typeof args.p_sync_token === "string" ? args.p_sync_token : null, total_amt: ta, total_tax: null, mismatch, voided_at: null, fingerprint: null, unapplied: ua });
          if (mismatch) j!.warning = (j!.warning ? j!.warning + " · " : "") + mismatch;
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked: 0, mismatch, reconcile: { action: "same" } };
        }
        if (j!.kind === "opening_apply_void") {                                                      // 2e-3-1b opening_apply_void → voided_at(Payment 짝)
          const t = db.txns.get(j!.ims_id + ":apply");
          if (!t) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: "voided in QuickBooks but IMS has no sent opening credit application on file to mark — check qbo_txn by hand", unblocked: 0, mismatch: null }; }
          t.voided_at = clock(); if (typeof args.p_sync_token === "string") t.sync_token = args.p_sync_token;
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked: 0, mismatch: null, reconcile: { action: "none" } };
        }
        if (j!.kind === "refund") {                                                                 // 2e-3-2-1b refund → qbo_txn refund ↔ Purchase + 대조(TotalAmt = 크레딧 몫 합 · TotalTax 0 또는 없음 · 20261108075221 의 글 그대로) · 끝의 「부모 sent → blocked 를 queued」 로 refund_apply 가 풀린다
          const ta = typeof args.p_total_amt === "number" ? args.p_total_amt : null, tx = typeof args.p_total_tax === "number" ? args.p_total_tax : null, amt = j!.totals?.total ?? 0, label = j!.name;
          const mismatch = ta === null ? `QuickBooks did not return TotalAmt — check refund ${label} in QuickBooks` : ta !== amt ? `QuickBooks total ${ta} differs from IMS ${amt} (credit-note part of refund ${label}) — check it in QuickBooks (942)` : (tx !== null && tx !== 0) ? `QuickBooks tax ${tx} is not 0 — check refund ${label} in QuickBooks (942)` : null;
          if ([...db.txns.entries()].some(([k, v]) => v.qbo_id === j!.qbo_id && k !== j!.ims_id)) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: `QuickBooks Purchase #${j!.qbo_id} is already recorded for another IMS record — check both in QuickBooks and fix by hand`, unblocked: 0, mismatch }; }
          db.txns.set(j!.ims_id, { qbo_id: j!.qbo_id, doc_number: j!.qbo_name, sync_token: typeof args.p_sync_token === "string" ? args.p_sync_token : null, total_amt: ta, total_tax: tx, mismatch, voided_at: null });
          if (mismatch) j!.warning = (j!.warning ? j!.warning + " · " : "") + mismatch;
          let unblocked = 0; for (const x of db.jobs.values()) if (x.state === "blocked" && x.blocked_by === j!.id) { x.state = "queued"; unblocked++; }
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked, mismatch, reconcile: { action: "same" } };
        }
        if (j!.kind === "refund_void") {                                                            // 2e-3-2-1b refund_void → voided_at(Purchase 짝)
          const t = db.txns.get(j!.ims_id);
          if (!t) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: "voided in QuickBooks but IMS has no sent refund expense on file to mark — check qbo_txn by hand", unblocked: 0, mismatch: null }; }
          t.voided_at = clock(); if (typeof args.p_sync_token === "string") t.sync_token = args.p_sync_token;
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked: 0, mismatch: null, reconcile: { action: "none" } };
        }
        if (j!.kind === "refund_apply") {                                                           // 2e-3-2-1b refund_apply → qbo_txn refund_apply ↔ 0 원 Payment(ims_id + ":apply") + TotalAmt 0 · UnappliedAmt 0 대조
          const ta = typeof args.p_total_amt === "number" ? args.p_total_amt : null, ua = typeof args.p_unapplied_amt === "number" ? args.p_unapplied_amt : null, label = j!.name;
          const mismatch = ta === null ? `QuickBooks did not return TotalAmt — check the zero payment of refund ${label} in QuickBooks` : ta !== 0 ? `QuickBooks total ${ta} is not 0 — check the zero payment of refund ${label} in QuickBooks (942)` : (ua !== null && ua !== 0) ? `QuickBooks unapplied ${ua} is not 0 — check the zero payment of refund ${label} in QuickBooks (942)` : null;
          if ([...db.txns.entries()].some(([k, v]) => v.qbo_id === j!.qbo_id && k !== j!.ims_id + ":apply")) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: `QuickBooks Payment #${j!.qbo_id} is already recorded for another IMS record — check both in QuickBooks and fix by hand`, unblocked: 0, mismatch }; }
          db.txns.set(j!.ims_id + ":apply", { qbo_id: j!.qbo_id, doc_number: j!.qbo_name, sync_token: typeof args.p_sync_token === "string" ? args.p_sync_token : null, total_amt: ta, total_tax: null, mismatch, voided_at: null, fingerprint: null, unapplied: ua });
          if (mismatch) j!.warning = (j!.warning ? j!.warning + " · " : "") + mismatch;
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked: 0, mismatch, reconcile: { action: "same" } };
        }
        if (j!.kind === "refund_apply_void") {                                                      // 2e-3-2-1b refund_apply_void → voided_at(Payment 짝)
          const t = db.txns.get(j!.ims_id + ":apply");
          if (!t) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: "voided in QuickBooks but IMS has no sent refund zero payment on file to mark — check qbo_txn by hand", unblocked: 0, mismatch: null }; }
          t.voided_at = clock(); if (typeof args.p_sync_token === "string") t.sync_token = args.p_sync_token;
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked: 0, mismatch: null, reconcile: { action: "none" } };
        }
        if (j!.kind === "cost_day") {                                                               // 3-3 가짜 done cost_day(20261108224000 의 글 그대로): qbo_txn cost_sheet ↔ JournalEntry · round(p_total_amt*100) ↔ 지문 앞 칸(claim 때 고정) · 다르면 mismatch(sent 그대로) · qbo_name 은 DocNumber 로 돌아온다
          const ta = typeof args.p_total_amt === "number" ? args.p_total_amt : null, label = j!.doc_number ?? j!.ims_id, fp = Number((/^(\d+)\|/.exec(j!.fingerprint ?? "") ?? [])[1] ?? -1);
          const mismatch = ta === null ? `QuickBooks did not return TotalAmt — check journal entry ${label} in QuickBooks` : Math.round(ta * 100) !== fp ? `QuickBooks total ${ta} differs from IMS ${(fp / 100).toFixed(2)} — check journal entry ${label} in QuickBooks (942)` : null;
          if ([...db.txns.entries()].some(([k, v]) => v.qbo_id === j!.qbo_id && k !== j!.ims_id)) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: `QuickBooks JournalEntry #${j!.qbo_id} is already recorded for another IMS record — check both in QuickBooks and fix by hand`, unblocked: 0, mismatch }; }
          db.txns.set(j!.ims_id, { qbo_id: j!.qbo_id, doc_number: j!.qbo_name, sync_token: typeof args.p_sync_token === "string" ? args.p_sync_token : null, total_amt: ta, total_tax: null, mismatch, voided_at: null, fingerprint: j!.fingerprint ?? null });
          if (mismatch) j!.warning = (j!.warning ? j!.warning + " · " : "") + mismatch;
          let unblocked = 0; for (const x of db.jobs.values()) if (x.state === "blocked" && x.blocked_by === j!.id) { x.state = "queued"; unblocked++; }   // 뒤 장(wait_job)이 풀린다
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked, mismatch, reconcile: { action: "same" } };
        }
        if (j!.kind === "credit_apply_void") {                                                       // 2e-2-1b credit_apply_void → voided_at
          const t = db.txns.get(j!.ims_id);
          if (!t) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: "voided in QuickBooks but IMS has no sent credit application on file to mark — check qbo_txn by hand", unblocked: 0, mismatch: null }; }
          t.voided_at = clock(); if (typeof args.p_sync_token === "string") t.sync_token = args.p_sync_token;
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked: 0, mismatch: null, reconcile: { action: "none" } };
        }
        if (j!.kind === "payment") {                                                                 // 2e-1c payment → qbo_txn Payment + 지문 + TotalAmt · UnappliedAmt 대조(20261103050000 의 글 그대로)
          const ta = typeof args.p_total_amt === "number" ? args.p_total_amt : null, ua = typeof args.p_unapplied_amt === "number" ? args.p_unapplied_amt : null, t = j!.pay_totals ?? { amount: 0, unapplied: 0 }, ref = j!.name;
          const mismatch = ta === null ? `QuickBooks did not return TotalAmt — check payment ${ref} in QuickBooks` : ta !== t.amount ? `QuickBooks total ${ta} differs from IMS ${t.amount} — check payment ${ref} in QuickBooks (942)` : (ua !== null && ua !== t.unapplied) ? `QuickBooks unapplied ${ua} differs from IMS ${t.unapplied} — check payment ${ref} in QuickBooks (942)` : null;
          if ([...db.txns.entries()].some(([k, v]) => v.qbo_id === j!.qbo_id && k !== j!.ims_id)) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: `QuickBooks Payment #${j!.qbo_id} is already recorded for another IMS payment — check both in QuickBooks and fix by hand`, unblocked: 0, mismatch }; }
          db.txns.set(j!.ims_id, { qbo_id: j!.qbo_id, doc_number: j!.qbo_name, sync_token: typeof args.p_sync_token === "string" ? args.p_sync_token : null, total_amt: ta, total_tax: null, mismatch, voided_at: null, fingerprint: j!.fingerprint ?? null, unapplied: ua });
          if (mismatch) j!.warning = (j!.warning ? j!.warning + " · " : "") + mismatch;
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked: 0, mismatch, reconcile: { action: "same" } };
        }
        if (j!.kind === "payment_void") {                                                            // 2e-1c payment_void → voided_at
          const t = db.txns.get(j!.ims_id);
          if (!t) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: "voided in QuickBooks but IMS has no sent payment on file to mark — check qbo_txn by hand", unblocked: 0, mismatch: null }; }
          t.voided_at = clock(); if (typeof args.p_sync_token === "string") t.sync_token = args.p_sync_token;
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked: 0, mismatch: null, reconcile: { action: "none" } };
        }
        if (j!.kind === "invoice_void" || j!.kind === "credit_void") {                               // 2b1 void → qbo_txn.voided_at · [2c1 credit_void 도]
          const t = db.txns.get(j!.ims_id);
          if (!t) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: "voided in QuickBooks but IMS has no sent invoice on file to mark — check qbo_txn by hand", unblocked: 0, mismatch: null }; }
          t.voided_at = clock(); if (typeof args.p_sync_token === "string") t.sync_token = args.p_sync_token;
          return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked: 0, mismatch: null };
        }
        const type = j!.ims_kind === "customer" ? "Customer" : "Item"; const m = db.ents.get(type) ?? new Map<string, Ent>(); db.ents.set(type, m); m.set(j!.qbo_id, { name: j!.qbo_name, sku: typeof args.p_sku === "string" ? args.p_sku : null, fetched_at: clock(), gone_at: null });
        if (db.links.some((l) => l.qbo_id === j!.qbo_id && !(l.ims_kind === j!.ims_kind && l.ims_id === j!.ims_id))) { j!.state = "failed"; j!.sent_at = null; return { job_id: j!.id, kind: j!.kind, state: "failed", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: false, link_error: `QuickBooks ${type} #${j!.qbo_id} was created but is already linked to another IMS row — fix the link by hand under Settings → QuickBooks matching`, unblocked: 0 }; }
        db.links.push({ ims_kind: j!.ims_kind, ims_id: j!.ims_id, qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, matched_by: "created" });
        return { job_id: j!.id, kind: j!.kind, state: "sent", qbo_id: j!.qbo_id, qbo_name: j!.qbo_name, linked: true, link_error: null, unblocked: 0 };
      }
      case "qbo_job_fail": {
        const j = db.jobs.get(String(args.p_job)); if (!j) refuse(`Job ${args.p_job} not found — nothing was saved`);
        if (!["sending", "unknown"].includes(j!.state)) refuse(`Only a job being sent, or one whose result is unknown, can fail (this one is ${j!.state}) — nothing was saved`);
        j!.state = "failed"; j!.claimed_at = null; j!.last_error = String(args.p_error ?? "send failed"); return { job_id: j!.id, state: "failed", attempts: j!.attempts };
      }
      case "qbo_job_unknown": {
        const j = db.jobs.get(String(args.p_job)); if (!j) refuse(`Job ${args.p_job} not found — nothing was saved`);
        if (j!.state !== "sending") refuse(`Only a job being sent can become unknown (this one is ${j!.state}) — nothing was saved`);
        j!.state = "unknown"; j!.claimed_at = null; j!.last_error = String(args.p_error ?? "no answer from QuickBooks"); if (typeof args.p_name === "string" && args.p_name) j!.qbo_name = args.p_name; return { job_id: j!.id, state: "unknown", attempts: j!.attempts, qbo_name: j!.qbo_name };
      }
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
  eq([rc.status, String((await body(rc)).error)], [400, "cron may only call: refresh, send"], "cron key → 400 (query is not a cron action)");
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
  eq(pullQueryText("TaxCode", 1), "select Id, Name, Active, SyncToken, SalesTaxRateList from TaxCode STARTPOSITION 1 MAXRESULTS 1000", "taxcode query has no where · 2b2 SalesTaxRateList");
  eq(pullQueryText("Item", 1), "select * from Item where Active in (true, false) STARTPOSITION 1 MAXRESULTS 1000", "item query is select * (1c — field-selected queries drop Sku)");
  eq(PULL_FIELDS.Customer.includes("*") || PULL_FIELDS.Vendor.includes("*"), false, "customer · vendor keep the field list (933)");
  eq(PULL_PAGE, 1000, "page size");
  // 문
  const w = world(); connect(w);
  eq((await postBody(w, { action: "pull", entity: "Item" }, "JWT-MGR")).status, 403, "manager → 403");
  eq((await postBody(w, { action: "pull", entity: "Item" }, null)).status, 401, "no session → 401");
  const rc = await postBody(w, { action: "pull", entity: "Item" }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" });
  eq([rc.status, String((await body(rc)).error)], [400, "cron may only call: refresh, send"], "cron key → 400 (pull is not a cron action)");
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
  eq([rc.status, String((await body(rc)).error)], [400, "cron may only call: refresh, send"], "cron path: pull still refused");
  eq((await postBody(w, { action: "pull", entity: "TaxCode" }, "JWT-BAD")).status, 401, "unknown session → 401");
  readOnlyOnly(w, "⑮"); noLeak(w, "⑮");
});

// ── qbo-sync-2a′ — 쓰기 시험 장치: 일감 넣기 · API 호스트로 나간 쓰기가 전부 허용 꼴(POST customer · item · requestid)인지 ──
let jobN = 0;
function addJob(w: World, o: Partial<Job> & { kind: string }): Job {
  const n = ++jobN;
  const j: Job = { id: "job-" + n, kind: o.kind, ims_kind: o.ims_kind ?? (o.kind === "customer" ? "customer" : "product"), ims_id: o.ims_id ?? "ims-" + n, state: "queued", attempts: 0, request_id: "11111111-2222-4333-8444-" + String(n).padStart(12, "0"),
    name: o.name ?? (o.kind === "customer" ? "Customer " + n : "Item " + n), name_alt: o.name_alt ?? null, sku: o.sku ?? (o.kind === "item" ? "SKU-" + n : null),
    body: o.body ?? (o.kind === "customer" ? { DisplayName: o.name ?? "Customer " + n, CompanyName: o.name ?? "Customer " + n, Taxable: true, CurrencyRef: { value: "CAD" }, BillAddr: { Line1: "35 ZZPII Rd", City: "Toronto", Country: "Canada" }, PrimaryEmailAddr: { Address: "shop-ZZPII@example.invalid" } }
      : { Name: o.name ?? "Item " + n, Sku: o.sku ?? "SKU-" + n, Type: "Service", Taxable: true, IncomeAccountRef: { value: "98" }, ExpenseAccountRef: { value: "58" } }),
    qbo_id: null, qbo_name: null, last_error: null, claimed_at: null, sent_at: null, doc_number: o.doc_number ?? null, totals: o.totals ?? null, warning: null, needs: o.needs, wait_job: o.wait_job ?? null, blocked_by: null };   // 2d1 needs · wait_job
  if (o.kind === "invoice" || o.kind === "invoice_void") { j.ims_kind = "invoice"; }
  if (o.kind === "credit" || o.kind === "credit_void") { j.ims_kind = "credit"; }                       // 2c1
  if (o.kind === "payment" || o.kind === "payment_void") { j.ims_kind = "payment"; j.fingerprint = o.fingerprint ?? null; j.check_lines = o.check_lines ?? null; j.lookup = o.lookup ?? null; j.pay_totals = o.pay_totals ?? null; }   // 2e-1c
  if (o.kind === "credit_apply" || o.kind === "credit_apply_void") { j.ims_kind = "credit_alloc"; j.fingerprint = null; j.check_lines = o.check_lines ?? null; j.lookup = o.lookup ?? null; j.pay_totals = o.pay_totals ?? null; }   // 2e-2-1b
  if (o.kind === "refund" || o.kind === "refund_void" || o.kind === "refund_apply" || o.kind === "refund_apply_void") { j.ims_kind = "refund"; j.fingerprint = null; j.check_lines = o.check_lines ?? null; j.lookup = o.lookup ?? null; j.pay_totals = o.pay_totals ?? null; }   // 2e-3-2-1b 한 환불에 일감 넷 · ims_id = so_payment.id
  if (o.kind === "opening_credit" || o.kind === "opening_credit_void" || o.kind === "opening_apply" || o.kind === "opening_apply_void") { j.ims_kind = "opening_alloc"; j.fingerprint = null; j.check_lines = o.check_lines ?? null; j.lookup = o.lookup ?? null; j.pay_totals = o.pay_totals ?? null; }   // 2e-3-1b 한 붙임에 일감 넷 · ims_id = so_payment_alloc.id
  if (o.kind === "cost_day") { j.ims_kind = "cost_sheet"; j.fingerprint = o.fingerprint ?? null; j.check_lines = null; j.lookup = o.lookup ?? null; j.needs = o.needs; }   // 3-3 하루 원가 장 · ims_id 「YYYY-MM-DD|TOR」 · 지문 「<차변 센트>|<줄 md5>」(claim 때 고정)
  w.db.jobs.set(j.id, j);
  return j;
}
const postHits = (w: World) => apiHits(w).filter((h) => h.method === "POST" && !h.url.includes("/query"));
function writesAllowedOnly(w: World, where: string) {
  for (const h of apiHits(w)) {
    if (h.method === "GET") continue;
    const u = new URL(h.url);
    const ent = (/\/v3\/company\/[^/]+\/(customer|item|invoice|creditmemo|payment|purchase|journalentry)\/?$/.exec(u.pathname) ?? [])[1] ?? null, op = u.searchParams.get("operation"), inc = u.searchParams.get("include");
    ok(h.method === "POST" && ent !== null && !!u.searchParams.get("requestid") && ((op === null && inc === null) || (op === "void" && (ent === "invoice" || ent === "creditmemo")) || (op === "update" && inc === "void" && ent === "payment")), where + ": unexpected write to Intuit: " + h.method + " " + h.url);
    if (ent === "purchase") { const b = JSON.parse(h.body || "{}") as Record<string, unknown>; ok(op === null && (b.Id == null || purchaseVoidBodyProblem(b) === null), where + ": a purchase update that is not the void shape: " + h.body.slice(0, 200)); }   // [2e-3-2-1b purchase — 만들기 · void 꼴만]   // [2e-1c payment · update&include=void]   // 2b2: invoice · invoice?operation=void 도 허용 꼴 · [2c1 creditmemo]
    if (ent === "journalentry") { const b = JSON.parse(h.body || "{}") as Record<string, unknown>; ok(op === null && inc === null && b.Id == null, where + ": a journal entry write that is not a create: " + h.body.slice(0, 200)); }   // [3-3 journalentry — 만들기만(몸에 Id 없음)]
  }
}
const send = (w: World, jwt: string | null = "JWT-ADMIN", extra: Record<string, unknown> = {}) => postBody(w, { action: "send", ...extra }, jwt);

Deno.test("⑯ 쓰기 순수(qbo-sync-2a′) — assertWriteAllowed(POST customer · item · invoice · creditmemo + requestid · operation=void 는 invoice · creditmemo 만 · delete · PUT · DELETE · vendor · requestid 없음 · 51 자 거부) · classifyWrite · faultCode · sqlQuote · PII 가드 확장(Invoice · CreditMemo · Payment · SalesReceipt · RefundReceipt: select * 400 · BillEmail · ShipFromAddr 400 · read 는 벗김 · DocNumber 등은 그대로)", () => {
  const base = "https://quickbooks.api.intuit.com/v3/company/123";
  for (const e of WRITE_ENTITIES) assertWriteAllowed("POST", `${base}/${e}?requestid=r1&minorversion=75`);
  assertWriteAllowed("POST", `${base}/invoice?operation=void&requestid=r1`); assertWriteAllowed("POST", `${base}/creditmemo?operation=void&requestid=r1`);
  const refused = (m: string, u: string, why: string) => { let msg = ""; try { assertWriteAllowed(m, u); } catch (e) { msg = (e as Error).message; } ok(msg.startsWith("refusing"), why + " should be refused: " + (msg || "(allowed)")); return msg; };
  ok(refused("POST", `${base}/customer?operation=void&requestid=r1`, "void customer").includes("only operation=void on invoice, creditmemo"), "void only on invoice · creditmemo");
  ok(refused("POST", `${base}/invoice?operation=delete&requestid=r1`, "delete").includes("operation=delete is never sent"), "delete never");
  refused("PUT", `${base}/customer?requestid=r1`, "PUT"); refused("DELETE", `${base}/customer?requestid=r1`, "DELETE"); refused("GET", `${base}/customer?requestid=r1`, "GET via write path");
  refused("POST", `${base}/vendor?requestid=r1`, "vendor"); refused("POST", `${base}/customer/5?requestid=r1`, "customer/5 (not a create path)"); refused("POST", `${base}/query?requestid=r1`, "query via write path");
  ok(refused("POST", `${base}/customer`, "no requestid").includes("without a requestid"), "requestid required"); refused("POST", `${base}/customer?requestid=${"x".repeat(REQUESTID_MAX + 1)}`, "requestid 51");
  eq([classifyWrite(200, null), classifyWrite(201, null), classifyWrite(400, null), classifyWrite(429, null), classifyWrite(500, null), classifyWrite(503, null), classifyWrite(0, "boom"), classifyWrite(200, "boom")], ["ok", "ok", "fail", "fail", "unknown", "unknown", "unknown", "unknown"], "classifyWrite");
  eq([faultCode({ Fault: { Error: [{ code: "6240" }] } }), faultCode({ Fault: { Error: [{ code: 610 }] } }), faultCode({}), faultCode("x"), faultCode(null)], ["6240", "610", null, null, null], "faultCode");
  eq([sqlQuote("O'Neil & Co"), sqlQuote("")], ["'O''Neil & Co'", "''"], "sqlQuote doubles quotes");
  eq([...PII_ENTITIES], ["Customer", "Vendor", "Invoice", "CreditMemo", "Payment", "SalesReceipt", "RefundReceipt"], "PII entities now seven");
  for (const e of ["Invoice", "CreditMemo", "Payment", "SalesReceipt", "RefundReceipt"]) {
    let m = ""; try { parseQuery(`select * from ${e}`); } catch (x) { m = (x as Error).message; } ok(m.includes("select * is not allowed on " + e), e + " select * refused: " + m);
    m = ""; try { parseQuery(`select Id, BillEmail from ${e}`); } catch (x) { m = (x as Error).message; } ok(m.includes("BillEmail is not readable"), e + " BillEmail refused: " + m);
    eq(parseQuery(`select Id, DocNumber, TotalAmt, TxnDate, CustomerRef, SyncToken from ${e} MAXRESULTS 5`).entity, e, e + " plain fields pass");
  }
  let m2 = ""; try { parseQuery("select Id, ShipFromAddr from Invoice"); } catch (x) { m2 = (x as Error).message; } ok(m2.includes("ShipFromAddr"), "ShipFromAddr refused");
  eq(parseQuery("select count(*) from Invoice").isCount, true, "count(*) on Invoice still fine");
  const inv = stripPii("Invoice", { Id: "1", DocNumber: "48160", TotalAmt: 93.3, BillAddr: { Line1: "x" }, ShipAddr: { Line1: "x" }, BillEmail: { Address: "x" }, BillEmailCc: { Address: "x" }, ShipFromAddr: { Line1: "x" }, CustomerRef: { value: "9" } });
  eq(Object.keys(inv).sort(), ["CustomerRef", "DocNumber", "Id", "TotalAmt"], "read Invoice strips address · email fields");
  eq(Object.keys(stripPii("Item", { Id: "1", BillAddr: { Line1: "x" } })).length, 2, "Item untouched");
});

Deno.test("⑰ send(qbo-sync-2a′) — 문(열쇠 qbo 만 · qbo:read 403 · cron 400 · limit 밖 400 · 연결 없음 409 · 일감 무접촉) · 손님 + Item 보내기(POST 둘 · requestid = request_id · 몸 그대로 · 2xx → done · 짝 created · 거울 · 기록 detail 에 job id 만 · 주소 · 이메일 0) · 6240 Item 은 ` [SKU]` 로 requestid -2 한 번 더(note · attempts +1) · 6240 손님은 failed · 5xx · 끊김 → unknown(1 번만 · 보낸 이름) · 2xx 몸 없음 → unknown · 401 한 번 → 갱신 뒤 같은 requestid 다시 · 다음 send 가 unknown 을 이름으로 풀기(하나 found → sent · 0 not_found · 둘 ambiguous) · 쓰기는 허용 꼴만", async () => {
  // 문
  const w = world(); connect(w);
  w.db.keys["JWT-MGR"] = "qbo:read";
  eq((await send(w, "JWT-MGR")).status, 403, "qbo:read cannot send");
  w.db.keys["JWT-MGR"] = "qbo";
  const rc = await postBody(w, { action: "send" }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" });
  eq([rc.status, (await body(rc)).ok, (await body(await postBody(w, { action: "send" }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" }))).claimed], [200, true, 0], "2b2: cron may send (ims-qbo-send) · nothing queued → claimed 0");
  eq([(await send(w, "JWT-MGR", { limit: 0 })).status, (await send(w, "JWT-MGR", { limit: SEND_LIMIT_MAX + 1 })).status, (await send(w, "JWT-MGR", { limit: "x" })).status], [400, 400, 400], "limit outside 1 … 50 → 400");
  const w0 = world();                                                                                 // 연결 없음
  addJob(w0, { kind: "customer" });
  const r0 = await send(w0);
  eq([r0.status, w0.db.jobs.get("job-1")!.state, apiHits(w0).length], [409, "queued", 0], "not connected → 409 · job untouched · no Intuit call");
  // 보내기 — 손님 + Item
  const jc = addJob(w, { kind: "customer", name: "Some Shop Inc", ims_id: "cust-1" }), ji = addJob(w, { kind: "item", name: "Widget- Blue", name_alt: "Widget- Blue [SKU-W]", sku: "SKU-W", ims_id: "prod-1" });
  const r1 = await send(w, "JWT-MGR");
  const t1 = await r1.text(); ok(!t1.includes("\n"), "compact JSON");
  const b1 = JSON.parse(t1) as Record<string, unknown>;
  eq([r1.status, b1.ok, b1.claimed, b1.sent, b1.failed, b1.unknown, (b1.resolved as unknown[]).length], [200, true, 2, 2, 0, 0, 0], "two jobs sent: " + t1);
  const posts = postHits(w);
  eq(posts.length, 2, "two POSTs");
  eq([new URL(posts[0].url).pathname.endsWith("/customer"), new URL(posts[0].url).searchParams.get("requestid"), new URL(posts[0].url).searchParams.get("minorversion")], [true, jc.request_id, "75"], "customer POST carries the job request_id");
  eq(JSON.parse(posts[0].body), jc.body, "body sent as the DB built it");
  eq([new URL(posts[1].url).pathname.endsWith("/item"), new URL(posts[1].url).searchParams.get("requestid")], [true, ji.request_id], "item POST");
  eq([jc.state, jc.qbo_id, jc.qbo_name, ji.state, ji.qbo_id], ["sent", "1001", "Some Shop Inc", "sent", "1002"], "jobs sent with the QuickBooks ids");
  eq(w.db.links.map((l) => l.ims_kind + ":" + l.ims_id + ":" + l.qbo_id + ":" + l.matched_by), ["customer:cust-1:1001:created", "product:prod-1:1002:created"], "links created");
  eq([w.db.ents.get("Customer")!.get("1001")!.name, w.db.ents.get("Item")!.get("1002")!.sku], ["Some Shop Inc", "SKU-W"], "mirror rows upserted");
  const sendLogs = w.logs.filter((l) => l.action === "send");
  eq(sendLogs.length, 2, "two call_log rows for the writes");
  eq([sendLogs[0].ok, sendLogs[0].http_status, sendLogs[0].by_staff, sendLogs[0].detail?.job_id, sendLogs[0].detail?.qbo_id, sendLogs[0].detail?.request_id], [true, 200, STAFF_MGR, "job-2", "1001", jc.request_id], "detail = job id · qbo id · request id: " + JSON.stringify(sendLogs[0]));
  const logText = JSON.stringify(w.logs);
  ok(!logText.includes("ZZPII") && !logText.includes("Some Shop Inc") && !logText.includes("Line1"), "no address · email · name in call_log");
  eq(JSON.stringify(b1).includes("ZZPII"), false, "response carries no address · email");
  // 6240 — Item 은 [SKU] 로 한 번 더(requestid -2) · 손님은 failed
  const jd = addJob(w, { kind: "item", name: "Dup Name", name_alt: "Dup Name [SKU-D]", sku: "SKU-D" }), jcd = addJob(w, { kind: "customer", name: "Dup Customer" });
  w.it.dupNames.add("Dup Name"); w.it.dupNames.add("Dup Customer");
  const n0 = postHits(w).length;
  const b2 = await body(await send(w, "JWT-MGR"));
  const p2 = postHits(w).slice(n0);
  eq([b2.claimed, b2.sent, b2.failed, p2.length], [2, 1, 1, 3], "item retried once with [SKU] · customer failed: " + JSON.stringify(b2.jobs));
  eq([JSON.parse(p2[0].body).Name, new URL(p2[0].url).searchParams.get("requestid"), JSON.parse(p2[1].body).Name, new URL(p2[1].url).searchParams.get("requestid")], ["Dup Name", jd.request_id, "Dup Name [SKU-D]", jd.request_id + "-2"], "second request = other name · other requestid");
  eq([jd.state, jd.qbo_name, jd.attempts, (jd.last_error ?? "").startsWith("Duplicate Name (6240) on \"Dup Name\" — sent again as \"Dup Name [SKU-D]\"")], ["sent", "Dup Name [SKU-D]", 2, true], "item sent under the alt name · note · attempts 2");
  eq([jcd.state, (jcd.last_error ?? "").includes("code 6240")], ["failed", true], "customer duplicate → failed (no automatic rename): " + jcd.last_error);
  eq(JSON.parse(p2[2].body).DisplayName, "Dup Customer", "customer tried once");
  // 5xx · 끊김 → unknown(1 번만 · 보낸 이름) · 2xx 몸 없음 → unknown
  const j5 = addJob(w, { kind: "customer", name: "Five Hundred" }), jn = addJob(w, { kind: "item", name: "Net Down", sku: "SKU-N" }), je = addJob(w, { kind: "customer", name: "Empty Body" });
  w.it.override.push((h) => h.method === "POST" && h.body.includes("Five Hundred") ? jres(503, { Fault: { Error: [{ Message: "Service Unavailable", code: "3001" }], type: "SystemFault" } }, "tid-503") : null);
  w.it.override.push((h) => h.method === "POST" && h.body.includes("Net Down") ? new Error("connection reset by peer") : null);
  w.it.override.push((h) => h.method === "POST" && h.body.includes("Empty Body") ? jres(200, { time: "2026-11-01T12:00:00Z" }, "tid-empty") : null);
  const n1 = postHits(w).length, sleeps0 = w.sleeps.length;
  const b3 = await body(await send(w, "JWT-MGR"));
  eq([b3.claimed, b3.unknown, b3.sent, b3.failed, postHits(w).length - n1, w.sleeps.length - sleeps0], [3, 3, 0, 0, 3, 0], "all three unknown · exactly one POST each · no retry sleep: " + JSON.stringify(b3.jobs));
  eq([j5.state, j5.qbo_name, (j5.last_error ?? "").includes("HTTP 503"), jn.state, jn.qbo_name, (jn.last_error ?? "").includes("unreachable"), je.state, (je.last_error ?? "").includes("without the created Customer")], ["unknown", "Five Hundred", true, "unknown", "Net Down", true, "unknown", true], "unknown rows keep the name that was sent");
  w.it.override.length = 0;
  // 다음 send — unknown 풀기: Net Down 은 QBO 에 생겼다(created 에 심는다) → found · Five Hundred 는 없다 → not_found · Empty Body 는 둘 → ambiguous
  w.it.created.push({ ent: "item", id: "7777", name: "Net Down", sku: "SKU-N", requestid: null });
  w.it.created.push({ ent: "customer", id: "8881", name: "Empty Body", sku: null, requestid: null }, { ent: "customer", id: "8882", name: "Empty Body", sku: null, requestid: null });
  const n2 = postHits(w).length, q0 = queryHits(w).length;
  const b4 = await body(await send(w, "JWT-MGR"));
  const res = b4.resolved as Record<string, unknown>[];
  eq([res.length, postHits(w).length - n2, queryHits(w).length - q0, b4.claimed], [3, 0, 3, 0], "three name checks (GET query) · no write · nothing queued: " + JSON.stringify(res));
  eq(res.map((x) => x.result).sort(), ["ambiguous", "found", "not_found"], "one found · one not found · one ambiguous");
  eq([jn.state, jn.qbo_id, (jn.last_error ?? "").includes("found in QuickBooks by name"), j5.state, je.state], ["sent", "7777", true, "unknown", "unknown"], "found → sent + note · others stay unknown");
  eq(w.db.links.some((l) => l.ims_id === jn.ims_id && l.qbo_id === "7777"), true, "found one is linked (created)");
  const chk = w.logs.filter((l) => l.action === "send_check");
  eq([chk.length, String(chk[0].detail?.q).includes("?"), String(chk[0].detail?.q).includes("Net Down") || String(chk[0].detail?.q).includes("Five Hundred")], [3, true, false], "name check logged with the literal masked");
  const sq = sentQuery(queryHits(w).at(-1)!) ?? "";
  ok(/^select Id, (DisplayName|Name)(, Sku)?, SyncToken from (Customer|Item) where (DisplayName|Name) = '.+' MAXRESULTS 100$/.test(sq), "name check query shape: " + sq);
  // 401 한 번 → 갱신 → 같은 requestid 로 다시
  const j4 = addJob(w, { kind: "customer", name: "Auth Once" });
  let deny = 1; w.it.override.push((h) => h.method === "POST" && deny-- > 0 ? jres(401, { Fault: { Error: [{ Message: "AuthenticationFailed", code: "3200" }], type: "AUTHENTICATION" } }, "tid-401") : null);
  const v0 = w.db.conn!.token_version, n3 = postHits(w).length;
  const b5 = await body(await send(w, "JWT-MGR"));
  const p5 = postHits(w).slice(n3);
  eq([b5.sent, p5.length, new URL(p5[0].url).searchParams.get("requestid") === new URL(p5[1].url).searchParams.get("requestid"), w.db.conn!.token_version, j4.state], [1, 2, true, v0 + 1, "sent"], "401 → refresh once → same request again");
  w.it.override.length = 0;
  // 이름에 따옴표 — 조회 리터럴 따옴표 둘
  const jq = addJob(w, { kind: "customer", name: "O'Neil & Co" });
  w.it.override.push((h) => h.method === "POST" && h.body.includes("O'Neil") ? jres(502, {}, "tid-502") : null);
  await send(w, "JWT-MGR"); w.it.override.length = 0;
  w.it.created.push({ ent: "customer", id: "9009", name: "O'Neil & Co", sku: null, requestid: null });
  const b6 = await body(await send(w, "JWT-MGR"));
  eq([(b6.resolved as Record<string, unknown>[]).find((x) => x.job_id === jq.id)?.result, jq.state, jq.qbo_id, (sentQuery(queryHits(w).at(-1)!) ?? "").includes("'O''Neil & Co'")], ["found", "sent", "9009", true], "quote in the name is doubled in the check query");
  // 잠긴 일감 · 꺼진 길 — 큐가 비면 claimed 0 · unknown 둘(Five Hundred · Empty Body)은 매번 다시 본다(check_failed 면 다음에)
  const b7 = await body(await send(w, "JWT-MGR", { limit: 1 }));
  eq([b7.claimed, (b7.resolved as unknown[]).length, b7.limit], [0, 2, 1], "nothing queued · two unknown still checked each send");
  writesAllowedOnly(w, "⑰"); noLeak(w, "⑰");
  const allText = JSON.stringify({ logs: w.logs, warns: w.warns });
  ok(!allText.includes("ZZPII"), "addresses · emails never reach call_log or warn");
});

// ── qbo-sync-2b2 — 인보이스 · void 시험 장치: 인보이스 일감(몸은 DB qbo_invoice_body 꼴) · void 일감 · 가짜 장부 ──
const invBody = (doc: string, cust = "7190"): Record<string, unknown> => ({ DocNumber: doc, TxnDate: "2026-11-02", DueDate: "2027-01-01", CustomerRef: { value: cust }, SalesTermRef: { value: "4" }, CurrencyRef: { value: "CAD" },
  BillAddr: { Line1: "Regina ZZPII", Line2: "1 ZZPII St", City: "Toronto", CountrySubDivisionCode: "ON", PostalCode: "M1M 1M1", Country: "Canada" }, ShipAddr: { Line1: "ZZPII", Country: "Canada" }, BillEmail: { Address: "ap-ZZPII@example.invalid" },
  PrivateNote: "Customer Reference: PO-1", CustomerMemo: { value: "Customer Reference: PO-1, Regina ZZPII" }, GlobalTaxCalculation: "TaxExcluded",
  Line: [{ DetailType: "SalesItemLineDetail", LineNum: 1, Amount: 36, Description: "Widget (list 2, 10% off)", SalesItemLineDetail: { ItemRef: { value: "12829" }, Qty: 20, UnitPrice: 1.8, TaxCodeRef: { value: "6" } } },
         { DetailType: "SalesItemLineDetail", LineNum: 2, Amount: 0, Description: "Standard", SalesItemLineDetail: { ItemRef: { value: "4" }, Qty: 1, UnitPrice: 0, TaxCodeRef: { value: "6" } } }],
  TxnTaxDetail: { TotalTax: 4.68, TaxLine: [{ DetailType: "TaxLineDetail", Amount: 4.68, TaxLineDetail: { TaxRateRef: { value: "12" }, PercentBased: true, TaxPercent: 13, NetAmountTaxable: 36 } }] } });
const addInv = (w: World, doc: string, extra: Partial<Job> = {}) => addJob(w, { kind: "invoice", ims_id: "inv-" + doc, name: doc, doc_number: doc, totals: { total: 40.68, tax: 4.68 }, body: invBody(doc), ...extra });
const addVoid = (w: World, doc: string, id: string | null, syncToken: string | null) => addJob(w, { kind: "invoice_void", ims_id: "inv-" + doc, name: doc, doc_number: doc, body: id ? (syncToken !== null ? { Id: id, SyncToken: syncToken } : { Id: id }) : {} });
const invoicePosts = (w: World) => postHits(w).filter((h) => /\/invoice\/?\?/.test(h.url));
const voidPosts = (w: World) => invoicePosts(w).filter((h) => new URL(h.url).searchParams.get("operation") === "void");
const docQueries = (w: World) => queryHits(w).filter((h) => /DocNumber\s*=/.test(sentQuery(h) ?? ""));
const invReads = (w: World) => apiHits(w).filter((h) => h.method === "GET" && /\/invoice\/\d+\?/.test(h.url));

Deno.test("⑱ invoice send(qbo-sync-2b2) — 순수(SEND_KINDS 6(2c1) · CRON_ACTIONS refresh · send · 6140 · 6210 · 5010 · invoiceTotals · PULL_FIELDS.TaxCode 에 SalesTaxRateList · assertWriteAllowed invoice?operation=void) · claim 에 p_kinds 6 · DocNumber 멱등 조회 → POST invoice(몸 그대로 · requestid · TxnTaxDetail) → done(TotalAmt · TotalTax · DocNumber) · 합계 다르면 sent + mismatch · 이미 있으면 안 만들고 읽어서 done + note · 6140 → 다시 찾아서 done · 6140 인데 못 찾으면 failed · 다른 4xx failed · 5xx · 끊김 → unknown(DocNumber) → 다음 send 가 DocNumber 로 풀기(found → 읽어서 합계 · not_found) · 기록에 주소 · 이메일 0 · 쓰기는 허용 꼴만", async () => {
  eq([...SEND_KINDS], ["customer", "item", "invoice", "invoice_void", "credit", "credit_void", "payment", "payment_void", "credit_apply", "credit_apply_void", "opening_credit", "opening_credit_void", "opening_apply", "opening_apply_void", "refund", "refund_void", "refund_apply", "refund_apply_void", "cost_day"], "SEND_KINDS (2c1: + credit · credit_void · [2e-1c + payment · payment_void] · [2e-2-1b + credit_apply · credit_apply_void] · [2e-3-2-1b + refund 넷] · [3-3 + cost_day])");
  eq([...CRON_ACTIONS], ["refresh", "send"], "cron may send");
  eq([[...DUPLICATE_DOCNUMBER_CODES], STALE_OBJECT_CODE], [["6140", "6210"], "5010"], "fault codes");
  eq(invoiceTotals({ TotalAmt: 93.3, TxnTaxDetail: { TotalTax: 10.74 } }), { total_amt: 93.3, total_tax: 10.74 }, "totals from the Intuit row");
  eq(invoiceTotals({ TotalAmt: "93.30" }), { total_amt: 93.3, total_tax: null }, "string number · missing tax → null");
  ok(PULL_FIELDS.TaxCode.includes("SalesTaxRateList"), "TaxCode pull carries SalesTaxRateList");
  assertWriteAllowed("POST", "https://quickbooks.api.intuit.com/v3/company/1/invoice?operation=void&requestid=r1&minorversion=75");
  const w = world(); connect(w); w.db.keys["JWT-MGR"] = "qbo";
  // 1) 보통 한 장 — 멱등 조회 1(0 행) → POST 1 → done(합계 같음 · mismatch null)
  const j1 = addInv(w, "60001");
  const b1 = await body(await send(w, "JWT-MGR"));
  eq([b1.claimed, b1.sent, b1.failed, b1.unknown, b1.mismatch, (b1.kinds as string[]).length, w.db.claimKinds.at(-1)], [1, 1, 0, 0, 0, 18, ["customer", "item", "invoice", "invoice_void", "credit", "credit_void", "payment", "payment_void", "credit_apply", "credit_apply_void", "opening_credit", "opening_credit_void", "opening_apply", "opening_apply_void", "refund", "refund_void", "refund_apply", "refund_apply_void"]], "claim with six kinds · one invoice sent: " + JSON.stringify(b1.jobs));
  eq([docQueries(w).length, invoicePosts(w).length, invReads(w).length], [1, 1, 0], "one DocNumber check · one POST · no read");
  const p1 = invoicePosts(w)[0], u1 = new URL(p1.url);
  eq([u1.pathname.endsWith("/invoice"), u1.searchParams.get("requestid"), u1.searchParams.get("operation"), u1.searchParams.get("minorversion")], [true, j1.request_id, null, "75"], "POST invoice with the job request_id · no operation");
  eq(JSON.parse(p1.body), invBody("60001"), "body sent as the DB built it (TxnTaxDetail included)");
  const t1 = w.db.txns.get("inv-60001")!;
  eq([j1.state, j1.qbo_id, j1.qbo_name, t1.qbo_id, t1.doc_number, t1.sync_token, t1.total_amt, t1.total_tax, t1.mismatch, j1.warning], ["sent", "5001", "60001", "5001", "60001", "0", 40.68, 4.68, null, null], "done with DocNumber · totals · no mismatch");
  const q1 = sentQuery(docQueries(w)[0]) ?? "";
  eq(q1, "select Id, DocNumber, SyncToken, TotalAmt from Invoice where DocNumber = '60001' MAXRESULTS 100", "DocNumber check query shape (no PII fields)");
  const sl = w.logs.filter((l) => l.action === "send");
  eq([sl.length, sl[0].detail?.job_id, sl[0].detail?.qbo_id, sl[0].detail?.request_id, sl[0].detail?.fault, "doc_number" in (sl[0].detail ?? {})], [1, j1.id, "5001", j1.request_id, null, false], "write log detail = job · qbo id · request id only");
  const chk1 = w.logs.filter((l) => l.action === "send_check");
  eq([chk1.length, String(chk1[0].detail?.q).includes("'"), chk1[0].detail?.rows], [1, false, 0], "check logged with the literal masked");
  // 2) QBO 가 세금을 다르게 셈 → sent 그대로 + mismatch(DB 글) · 응답 mismatch 1
  const j2 = addInv(w, "60002"); w.it.taxOverride.set("60002", 4.67);
  const b2 = await body(await send(w, "JWT-MGR"));
  const t2 = w.db.txns.get("inv-60002")!;
  eq([b2.sent, b2.mismatch, j2.state, t2.total_amt, t2.total_tax, (t2.mismatch ?? "").startsWith("QuickBooks total 40.67 / tax 4.67 differs from IMS 40.68 / 4.68"), (j2.warning ?? "").includes("(942)"), (b2.jobs as Record<string, unknown>[])[0].mismatch === t2.mismatch], [1, 1, "sent", 40.67, 4.67, true, true, true], "mismatch recorded · state stays sent: " + t2.mismatch);
  // 3) 이미 QBO 에 있는 번호(Cin7 이 보냈다) → 만들지 않고 읽어서 done + note
  w.it.invoices.set("4999", { Id: "4999", DocNumber: "60003", SyncToken: 2, TotalAmt: 40.68, TotalTax: 4.68, voided: false, CustomerRef: { value: "7190" } });
  const j3 = addInv(w, "60003"); const n3 = invoicePosts(w).length;
  const b3 = await body(await send(w, "JWT-MGR"));
  eq([b3.sent, invoicePosts(w).length - n3, invReads(w).length, j3.state, j3.qbo_id, w.db.txns.get("inv-60003")!.sync_token, (j3.last_error ?? "").includes("already in QuickBooks (DocNumber found before sending)")], [1, 0, 1, "sent", "4999", "2", true], "found before sending → no POST · read once · note");
  // 4) 6140 — 우리 조회 뒤에 생겼다(조회 때는 0 · POST 가 6140) → 다시 찾아서 done · 못 찾으면 failed
  const j4 = addInv(w, "60004");
  let planted = false; w.it.override.push((h) => { if (h.method === "POST" && h.body.includes("\"60004\"") && !planted) { planted = true; w.it.invoices.set("4998", { Id: "4998", DocNumber: "60004", SyncToken: 0, TotalAmt: 40.68, TotalTax: 4.68, voided: false, CustomerRef: null }); return jres(400, { Fault: { Error: [{ Message: "Duplicate Document Number Error", code: "6140" }], type: "ValidationFault" } }, "tid-6140"); } return null; });
  const b4 = await body(await send(w, "JWT-MGR")); w.it.override.length = 0;
  eq([b4.sent, j4.state, j4.qbo_id, (j4.last_error ?? "").includes("duplicate DocNumber (6140)"), docQueries(w).filter((h) => (sentQuery(h) ?? "").includes("60004")).length], [1, "sent", "4998", true, 2], "6140 → second DocNumber check → recorded: " + j4.last_error);
  const j4b = addInv(w, "60005"); w.it.dupDoc.add("60005");
  const b4b = await body(await send(w, "JWT-MGR"));
  eq([b4b.failed, j4b.state, (j4b.last_error ?? "").includes("code 6140"), (j4b.last_error ?? "").includes("could not be found by number afterwards")], [1, "failed", true, true], "6140 but nothing found → failed with both facts: " + j4b.last_error);
  // 5) 다른 4xx → failed · 5xx → unknown(DocNumber) · 끊김 → unknown · 2xx 몸 없음 → unknown
  const j5 = addInv(w, "60006"), j6 = addInv(w, "60007"), j7 = addInv(w, "60008"), j8 = addInv(w, "60009");
  w.it.override.push((h) => h.method === "POST" && h.body.includes("\"60006\"") ? jres(400, { Fault: { Error: [{ Message: "Business Validation Error", Detail: "Customer is inactive", code: "6000" }], type: "ValidationFault" } }, "tid-6000") : null);
  w.it.override.push((h) => h.method === "POST" && h.body.includes("\"60007\"") ? jres(503, { Fault: { Error: [{ Message: "Service Unavailable", code: "3001" }], type: "SystemFault" } }, "tid-503") : null);
  w.it.override.push((h) => h.method === "POST" && h.body.includes("\"60008\"") ? new Error("connection reset by peer") : null);
  w.it.override.push((h) => h.method === "POST" && h.body.includes("\"60009\"") ? jres(200, { time: "x" }, "tid-empty") : null);
  const s0 = w.sleeps.length;
  const b5 = await body(await send(w, "JWT-MGR")); w.it.override.length = 0;
  eq([b5.claimed, b5.failed, b5.unknown, w.sleeps.length - s0], [4, 1, 3, 0], "one failed · three unknown · no retry sleep: " + JSON.stringify(b5.jobs));
  eq([j5.state, (j5.last_error ?? "").includes("code 6000"), j6.state, j6.qbo_name, j7.state, j7.qbo_name, (j7.last_error ?? "").includes("unreachable"), j8.state, (j8.last_error ?? "").includes("without the created Invoice")], ["failed", true, "unknown", "60007", "unknown", "60008", true, "unknown", true], "unknown rows keep the DocNumber");
  // 6) 다음 send — unknown 풀기: 60007 은 QBO 에 생겼다 → found(읽어서 합계 · 세금이 다르면 mismatch) · 60008 · 60009 는 없다 → not_found
  w.it.invoices.set("4990", { Id: "4990", DocNumber: "60007", SyncToken: 1, TotalAmt: 40.68, TotalTax: 4.68, voided: false, CustomerRef: null });
  const b6 = await body(await send(w, "JWT-MGR"));
  const res6 = b6.resolved as Record<string, unknown>[];
  eq([res6.length, res6.map((x) => x.result).sort().join(","), j6.state, j6.qbo_id, w.db.txns.get("inv-60007")!.total_amt, (j6.last_error ?? "").includes("found in QuickBooks by DocNumber"), j7.state, j8.state, b6.claimed], [3, "found,not_found,not_found", "sent", "4990", 40.68, true, "unknown", "unknown", 0], "DocNumber resolution: " + JSON.stringify(res6));
  // 7) 401 한 번 → 갱신 → 같은 requestid 로 다시(인보이스도)
  const j9 = addInv(w, "60010"); let deny = 1; w.it.override.push((h) => h.method === "POST" && deny-- > 0 ? jres(401, { Fault: { Error: [{ Message: "AuthenticationFailed", code: "3200" }], type: "AUTHENTICATION" } }, "tid-401") : null);
  const v0 = w.db.conn!.token_version, n9 = invoicePosts(w).length;
  const b9 = await body(await send(w, "JWT-MGR")); w.it.override.length = 0;
  const p9 = invoicePosts(w).slice(n9);
  eq([b9.sent, p9.length, new URL(p9[0].url).searchParams.get("requestid") === new URL(p9[1].url).searchParams.get("requestid"), w.db.conn!.token_version, j9.state], [1, 2, true, v0 + 1, "sent"], "401 → refresh → same request again");
  // 8) 멱등 조회가 실패(5xx)하면 보내지 않는다 → failed 「not sent」 · POST 0
  const j10 = addInv(w, "60011"); w.it.override.push((h) => h.url.includes("/query?") && (sentQuery(h) ?? "").includes("60011") ? jres(503, {}, "tid-503") : null);
  const n10 = invoicePosts(w).length;
  const b10 = await body(await send(w, "JWT-MGR")); w.it.override.length = 0;
  eq([b10.failed, invoicePosts(w).length - n10, j10.state, (j10.last_error ?? "").startsWith("not sent — the DocNumber check failed")], [1, 0, "failed", true], "check failed → nothing written · failed");
  // 9) 번호가 둘 → failed(사람)
  w.it.invoices.set("4980", { Id: "4980", DocNumber: "60012", SyncToken: 0, TotalAmt: 1, TotalTax: 0, voided: false, CustomerRef: null }); w.it.invoices.set("4981", { Id: "4981", DocNumber: "60012", SyncToken: 0, TotalAmt: 1, TotalTax: 0, voided: false, CustomerRef: null });
  const j11 = addInv(w, "60012");
  await send(w, "JWT-MGR");
  eq([j11.state, (j11.last_error ?? "").includes("already has 2 invoices with number 60012")], ["failed", true], "ambiguous DocNumber → failed: " + j11.last_error);
  writesAllowedOnly(w, "⑱"); noLeak(w, "⑱");
  const allText = JSON.stringify({ logs: w.logs, warns: w.warns });
  ok(!allText.includes("ZZPII"), "addresses · emails never reach call_log or warn");
  ok(!JSON.stringify(w.logs).includes("Regina"), "customer name not in call_log");
});

Deno.test("⑲ void(qbo-sync-2b2) — POST invoice?operation=void {Id, SyncToken} · 2xx → done(voided_at) · SyncToken 없으면 읽어서(GET 한 번) · 5010 stale → 읽어서 requestid -2 로 한 번 더 · void 거부(4xx) → failed · 5xx → unknown → 다음 send 가 읽어서 TotalAmt 0 이면 done · 아니면 not_voided · 없는 Id → failed(610) · cron 길로도 send(열쇠 없음 · by_staff null · limit 은 몸에서) · 쓰기는 허용 꼴만", async () => {
  const w = world(); connect(w); w.db.keys["JWT-MGR"] = "qbo";
  // 바탕: 인보이스 넷을 먼저 보낸다(5001 ~ 5004)
  for (const d of ["60101", "60102", "60103", "60104"]) addInv(w, d);
  const b0 = await body(await send(w, "JWT-MGR"));
  eq([b0.sent, w.it.invoices.size], [4, 4], "four invoices in the fake ledger");
  // 1) 보통 void — Id · SyncToken 그대로 → POST operation=void · done · txn voided · 기록 detail 에 operation
  const v1 = addVoid(w, "60101", "5001", "0");
  const b1 = await body(await send(w, "JWT-MGR"));
  const vp = voidPosts(w);
  eq([b1.sent, vp.length, JSON.parse(vp[0].body), new URL(vp[0].url).searchParams.get("requestid"), v1.state, v1.qbo_id, w.db.txns.get("inv-60101")!.voided_at !== null, w.db.txns.get("inv-60101")!.sync_token, w.it.invoices.get("5001")!.voided], [1, 1, { Id: "5001", SyncToken: "0" }, v1.request_id, "sent", "5001", true, "1", true], "voided: " + JSON.stringify(b1.jobs));
  const vl = w.logs.filter((l) => l.action === "send" && l.detail?.operation === "void");
  eq([vl.length, vl[0].detail?.job_id, vl[0].detail?.qbo_id], [1, v1.id, "5001"], "void write logged with operation · job · qbo id");
  // 2) SyncToken 없음 → GET 으로 읽고 void · note
  const v2 = addVoid(w, "60102", "5002", null); const r0 = invReads(w).length;
  const b2 = await body(await send(w, "JWT-MGR"));
  eq([b2.sent, invReads(w).length - r0, v2.state, (v2.last_error ?? "").includes("SyncToken read from QuickBooks before voiding"), w.it.invoices.get("5002")!.voided], [1, 1, "sent", true, true], "read first, then void");
  // 3) 5010 stale → 읽어서 -2 로 다시
  w.it.invoices.get("5003")!.SyncToken = 3;
  const v3 = addVoid(w, "60103", "5003", "0"); const n3 = voidPosts(w).length;
  const b3 = await body(await send(w, "JWT-MGR"));
  const p3 = voidPosts(w).slice(n3);
  eq([b3.sent, p3.length, JSON.parse(p3[1].body).SyncToken, new URL(p3[1].url).searchParams.get("requestid"), v3.state, (v3.last_error ?? "").includes("stale SyncToken (5010)")], [1, 2, "3", v3.request_id + "-2", "sent", true], "stale → re-read → second try with -2");
  // 4) void 거부(결제 붙음 등 4xx) → failed · 장부 그대로
  w.it.voidRefuse.add("5004");
  const v4 = addVoid(w, "60104", "5004", "0");
  const b4 = await body(await send(w, "JWT-MGR"));
  eq([b4.failed, v4.state, (v4.last_error ?? "").includes("code 6000"), w.it.invoices.get("5004")!.voided], [1, "failed", true, false], "refused void → failed: " + v4.last_error);
  // 5) 없는 Id → 610 → failed · Id 없는 일감 → failed(not sent)
  const v5 = addVoid(w, "60199", "9999", "0"), v6 = addVoid(w, "60198", null, null);
  const b5 = await body(await send(w, "JWT-MGR"));
  eq([b5.failed, v5.state, (v5.last_error ?? "").includes("code 610"), v6.state, (v6.last_error ?? "").startsWith("not sent — no QuickBooks invoice id")], [2, "failed", true, "failed", true], "unknown id · no id");
  // 6) 5xx → unknown → 다음 send: 아직 void 안 됨 → not_voided(unknown 그대로) · 손으로 void 된 셈(장부 0) → found → done
  w.it.voidRefuse.delete("5004"); w.it.invoices.get("5004")!.SyncToken = 0;
  const v7 = addJob(w, { kind: "invoice_void", ims_id: "inv-60104", name: "60104", doc_number: "60104", body: { Id: "5004", SyncToken: "0" } });
  w.it.override.push((h) => h.method === "POST" && new URL(h.url).searchParams.get("operation") === "void" ? jres(502, {}, "tid-502") : null);
  const b7 = await body(await send(w, "JWT-MGR")); w.it.override.length = 0;
  eq([b7.unknown, v7.state, v7.qbo_name], [1, "unknown", "60104"], "void 5xx → unknown with DocNumber");
  const b8 = await body(await send(w, "JWT-MGR"));
  eq([(b8.resolved as Record<string, unknown>[])[0].result, v7.state], ["not_voided", "unknown"], "still carries an amount → not_voided");
  const inv = w.it.invoices.get("5004")!; inv.TotalAmt = 0; inv.TotalTax = 0; inv.voided = true; inv.SyncToken = 1;
  const b9 = await body(await send(w, "JWT-MGR"));
  eq([(b9.resolved as Record<string, unknown>[])[0].result, v7.state, w.db.txns.get("inv-60104")!.voided_at !== null, (v7.last_error ?? "").includes("voided (amount 0)")], ["found", "sent", true, true], "amount 0 → voided → done");
  // 7) cron 길 — 열쇠로 send(by_staff null · limit 몸에서 · 400 밖은 거부)
  const v8 = addVoid(w, "60102", "5002", "1"); w.it.invoices.get("5002")!.voided = false;
  const rc = await postBody(w, { action: "send", limit: 7 }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" });
  const bc = await body(rc);
  eq([rc.status, bc.ok, bc.limit, bc.claimed, bc.sent, v8.state, w.logs.filter((l) => l.action === "send").at(-1)?.by_staff], [200, true, 7, 1, 1, "sent", null], "cron send: " + JSON.stringify(bc.jobs));
  eq((await postBody(w, { action: "send", limit: 0 }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" })).status, 400, "cron limit 0 → 400");
  eq((await postBody(w, { action: "send" }, null, { "x-ims-cron-key": "wrong" })).status, 401, "wrong cron key → 401");
  writesAllowedOnly(w, "⑲"); noLeak(w, "⑲");
  ok(!JSON.stringify({ logs: w.logs, warns: w.warns }).includes("ZZPII"), "no PII in logs");
});

// ── qbo-sync-2c1 — 크레딧 노트 시험 장치: 크레딧 일감(몸은 DB qbo_credit_body 꼴 · DocNumber CR-…) · void 일감 · 같은 가짜 장부(ent CreditMemo) ──
const crBody = (doc: string, cust = "7190"): Record<string, unknown> => ({ DocNumber: doc, TxnDate: "2026-11-02", CustomerRef: { value: cust }, CurrencyRef: { value: "CAD" },
  BillAddr: { Line1: "Regina ZZPII", Line2: "1 ZZPII St", City: "Toronto", CountrySubDivisionCode: "ON", PostalCode: "M1M 1M1", Country: "Canada" }, ShipAddr: { Line1: "ZZPII", Line2: "8 Ship Rd", Country: "Canada" }, BillEmail: { Address: "ap-ZZPII@example.invalid" },
  PrivateNote: "Credit for invoice 60001 · Customer Reference: PO-1", CustomerMemo: { value: "Credit for invoice 60001 · Customer Reference: PO-1, Regina ZZPII" }, GlobalTaxCalculation: "TaxExcluded",
  Line: [{ DetailType: "SalesItemLineDetail", LineNum: 1, Amount: 5, Description: "Widget", SalesItemLineDetail: { ItemRef: { value: "12829" }, Qty: 1, UnitPrice: 5, TaxCodeRef: { value: "6" } } },
         { DetailType: "SalesItemLineDetail", LineNum: 2, Amount: 2, Description: "Freight", SalesItemLineDetail: { ItemRef: { value: "4" }, Qty: 1, UnitPrice: 2, TaxCodeRef: { value: "6" } } }],
  TxnTaxDetail: { TotalTax: 0.91, TaxLine: [{ DetailType: "TaxLineDetail", Amount: 0.91, TaxLineDetail: { TaxRateRef: { value: "12" }, PercentBased: true, TaxPercent: 13, NetAmountTaxable: 7 } }] } });
const addCr = (w: World, doc: string, extra: Partial<Job> = {}) => addJob(w, { kind: "credit", ims_id: "cr-" + doc, name: doc, doc_number: doc, totals: { total: 7.91, tax: 0.91 }, body: crBody(doc), ...extra });
const addCrVoid = (w: World, doc: string, id: string | null, syncToken: string | null) => addJob(w, { kind: "credit_void", ims_id: "cr-" + doc, name: doc, doc_number: doc, body: id ? (syncToken !== null ? { Id: id, SyncToken: syncToken } : { Id: id }) : {} });
const cmPosts = (w: World) => postHits(w).filter((h) => /\/creditmemo\/?\?/.test(h.url));
const cmVoidPosts = (w: World) => cmPosts(w).filter((h) => new URL(h.url).searchParams.get("operation") === "void");
const cmReads = (w: World) => apiHits(w).filter((h) => h.method === "GET" && /\/creditmemo\/\d+\?/.test(h.url));
const cmDocQueries = (w: World) => queryHits(w).filter((h) => /from\s+CreditMemo\s+where\s+DocNumber\s*=/i.test(sentQuery(h) ?? ""));

Deno.test("⑳ credit memo send · void(qbo-sync-2c1 · 판정 963) — POST creditmemo(몸은 DB qbo_credit_body 그대로 · DueDate 없음) · DocNumber 조회 from CreditMemo(같은 번호의 Invoice 는 세지 않는다) · 2xx done(TotalAmt · TotalTax → 942) · 이미 있으면 읽어서 done · 6140 → 다시 찾아 짝 · 5xx unknown → 다음 send 가 CreditMemo 로 풀기 · void: POST creditmemo?operation=void · SyncToken 없으면 GET creditmemo/<id> · 거부 → failed(장부 그대로) · 5xx → unknown → not_voided → 0 이면 done · writesAllowedOnly 에 creditmemo", async () => {
  const w = world(); connect(w); w.db.keys["JWT-MGR"] = "qbo";
  // 1) 보통 한 장 — CreditMemo DocNumber 조회 1(0 행) → POST creditmemo 1 → done(합계 같음)
  const c1 = addCr(w, "CR-01000");
  const b1 = await body(await send(w, "JWT-MGR"));
  eq([b1.claimed, b1.sent, b1.failed, b1.unknown, b1.mismatch, (b1.kinds as string[]).length], [1, 1, 0, 0, 0, 18], "one credit memo sent: " + JSON.stringify(b1.jobs));
  eq([cmDocQueries(w).length, cmPosts(w).length, cmReads(w).length, invoicePosts(w).length], [1, 1, 0, 0], "one CreditMemo DocNumber check · one POST creditmemo · no read · no invoice write");
  const p1 = cmPosts(w)[0], u1 = new URL(p1.url);
  eq([u1.pathname.endsWith("/creditmemo"), u1.searchParams.get("requestid"), u1.searchParams.get("operation")], [true, c1.request_id, null], "POST creditmemo with the job request_id · no operation");
  eq(JSON.parse(p1.body), crBody("CR-01000"), "body sent as the DB built it (no DueDate · SalesTermRef · ShipDate)");
  ok(!("DueDate" in JSON.parse(p1.body)) && !("SalesTermRef" in JSON.parse(p1.body)), "credit memo body carries no DueDate · SalesTermRef");
  eq(sentQuery(cmDocQueries(w)[0]) ?? "", "select Id, DocNumber, SyncToken, TotalAmt from CreditMemo where DocNumber = 'CR-01000' MAXRESULTS 100", "DocNumber check query shape (CreditMemo · no PII fields)");
  const t1 = w.db.txns.get("cr-CR-01000")!;
  eq([c1.state, c1.qbo_id, c1.qbo_name, t1.qbo_id, t1.doc_number, t1.sync_token, t1.total_amt, t1.total_tax, t1.mismatch, w.it.invoices.get("5001")!.ent], ["sent", "5001", "CR-01000", "5001", "CR-01000", "0", 7.91, 0.91, null, "CreditMemo"], "done with DocNumber · totals · ledger row is a CreditMemo");
  const sl = w.logs.filter((l) => l.action === "send");
  eq([sl.length, sl[0].detail?.job_id, sl[0].detail?.qbo_id, "doc_number" in (sl[0].detail ?? {}), JSON.stringify(sl[0].detail).includes("ZZPII")], [1, c1.id, "5001", false, false], "write log detail = job · qbo id only");
  // 2) 세금이 다르게 셈 → sent + mismatch(크레딧 글)
  const c2 = addCr(w, "CR-01001"); w.it.taxOverride.set("CR-01001", 0.9);
  const b2 = await body(await send(w, "JWT-MGR"));
  const t2 = w.db.txns.get("cr-CR-01001")!;
  eq([b2.sent, b2.mismatch, c2.state, t2.total_amt, t2.total_tax, (t2.mismatch ?? "").startsWith("QuickBooks total 7.9 / tax 0.9 differs from IMS 7.91 / 0.91 — check credit note CR-01001"), (c2.warning ?? "").includes("(942)")], [1, 1, "sent", 7.9, 0.9, true, true], "mismatch recorded · state sent: " + t2.mismatch);
  // 3) 이미 QBO 에 있는 번호(Cin7 이 보낸 CreditMemo) → 만들지 않고 읽어서 done + note · 같은 번호의 Invoice 는 세지 않는다(CR-01003 은 Invoice 로만 있다 → 그대로 만든다)
  w.it.invoices.set("4999", { Id: "4999", DocNumber: "CR-01002", SyncToken: 2, TotalAmt: 7.91, TotalTax: 0.91, voided: false, CustomerRef: { value: "7190" }, ent: "CreditMemo" });
  w.it.invoices.set("4998", { Id: "4998", DocNumber: "CR-01003", SyncToken: 0, TotalAmt: 7.91, TotalTax: 0.91, voided: false, CustomerRef: null });
  const c3 = addCr(w, "CR-01002"), c3b = addCr(w, "CR-01003"); const n3 = cmPosts(w).length;
  const b3 = await body(await send(w, "JWT-MGR"));
  eq([b3.sent, cmPosts(w).length - n3, cmReads(w).length, c3.state, c3.qbo_id, w.db.txns.get("cr-CR-01002")!.sync_token, (c3.last_error ?? "").includes("already in QuickBooks (DocNumber found before sending)"), c3b.state, c3b.qbo_id !== "4998"],
     [2, 1, 1, "sent", "4999", "2", true, "sent", true], "found by number → read · recorded · Invoice with the same number ignored: " + JSON.stringify(b3.jobs));
  // 4) 6140 — 우리 조회 뒤에 생겼다 → 다시 찾아서 done · 못 찾으면 failed(크레딧 낱말)
  const c4 = addCr(w, "CR-01004");
  let planted = false; w.it.override.push((h) => { if (h.method === "POST" && h.url.includes("/creditmemo") && h.body.includes("\"CR-01004\"") && !planted) { planted = true; w.it.invoices.set("4997", { Id: "4997", DocNumber: "CR-01004", SyncToken: 0, TotalAmt: 7.91, TotalTax: 0.91, voided: false, CustomerRef: null, ent: "CreditMemo" }); } return null; });
  const b4 = await body(await send(w, "JWT-MGR")); w.it.override.length = 0;
  eq([b4.sent, c4.state, c4.qbo_id, (c4.last_error ?? "").includes("duplicate DocNumber (6140) — the existing credit memo #4997")], [1, "sent", "4997", true], "6140 → second DocNumber check → recorded: " + c4.last_error);
  const c4b = addCr(w, "CR-01005"); w.it.dupDoc.add("CR-01005");
  const b4b = await body(await send(w, "JWT-MGR"));
  eq([b4b.failed, c4b.state, (c4b.last_error ?? "").includes("code 6140"), (c4b.last_error ?? "").includes("and the credit memo could not be found by number afterwards")], [1, "failed", true, true], "6140 but nothing found → failed: " + c4b.last_error);
  // 5) 5xx → unknown(DocNumber 를 남긴다) → 다음 send: CreditMemo 로 풀기(found · 합계) · 없으면 not_found(크레딧 글)
  const c5 = addCr(w, "CR-01006"), c6 = addCr(w, "CR-01007");
  w.it.override.push((h) => h.method === "POST" && h.url.includes("/creditmemo") && (h.body.includes("\"CR-01006\"") || h.body.includes("\"CR-01007\"")) ? jres(503, { Fault: { Error: [{ Message: "Service Unavailable", code: "3001" }], type: "SystemFault" } }, "tid-503") : null);
  const b5 = await body(await send(w, "JWT-MGR")); w.it.override.length = 0;
  eq([b5.unknown, c5.state, c5.qbo_name, c6.state], [2, "unknown", "CR-01006", "unknown"], "5xx → unknown with DocNumber");
  w.it.invoices.set("4990", { Id: "4990", DocNumber: "CR-01006", SyncToken: 1, TotalAmt: 7.91, TotalTax: 0.91, voided: false, CustomerRef: null, ent: "CreditMemo" });
  const b6 = await body(await send(w, "JWT-MGR"));
  const res6 = b6.resolved as Record<string, unknown>[];
  eq([res6.length, res6.map((x) => x.result).sort().join(","), c5.state, c5.qbo_id, w.db.txns.get("cr-CR-01006")!.total_amt, (c5.last_error ?? "").includes("found in QuickBooks by DocNumber"), c6.state, String(res6.find((x) => x.job_id === c6.id)?.message).includes("QuickBooks has no credit memo with that number")],
     [2, "found,not_found", "sent", "4990", 7.91, true, "unknown", true], "unknown resolved by CreditMemo DocNumber: " + JSON.stringify(res6));
  w.db.jobs.get(c6.id)!.state = "skipped";
  // 6) void — Id · SyncToken 그대로 → POST creditmemo?operation=void · done(voided_at) · SyncToken 없으면 GET creditmemo/<id> · 5010 → -2 · 거부 → failed · 장부 그대로
  const v1 = addCrVoid(w, "CR-01000", "5001", "0");
  const b7 = await body(await send(w, "JWT-MGR"));
  const vp = cmVoidPosts(w);
  eq([b7.sent, vp.length, JSON.parse(vp[0].body), new URL(vp[0].url).searchParams.get("requestid"), v1.state, w.db.txns.get("cr-CR-01000")!.voided_at !== null, w.it.invoices.get("5001")!.voided, voidPosts(w).length], [1, 1, { Id: "5001", SyncToken: "0" }, v1.request_id, "sent", true, true, 0], "void credit memo: " + JSON.stringify(b7.jobs));
  const v2 = addCrVoid(w, "CR-01001", "5002", null); const r0 = cmReads(w).length;
  const b8 = await body(await send(w, "JWT-MGR"));
  eq([b8.sent, cmReads(w).length - r0, v2.state, (v2.last_error ?? "").includes("SyncToken read from QuickBooks before voiding"), w.it.invoices.get("5002")!.voided], [1, 1, "sent", true, true], "read creditmemo first, then void");
  w.it.invoices.get("4997")!.SyncToken = 3;
  const v3 = addCrVoid(w, "CR-01004", "4997", "0"); const n9 = cmVoidPosts(w).length;
  const b9 = await body(await send(w, "JWT-MGR"));
  const p9 = cmVoidPosts(w).slice(n9);
  eq([b9.sent, p9.length, JSON.parse(p9[1].body).SyncToken, new URL(p9[1].url).searchParams.get("requestid"), v3.state], [1, 2, "3", v3.request_id + "-2", "sent"], "stale → re-read → second try with -2");
  w.it.voidRefuse.add("4999");
  const v4 = addCrVoid(w, "CR-01002", "4999", "2");
  const b10 = await body(await send(w, "JWT-MGR"));
  eq([b10.failed, v4.state, (v4.last_error ?? "").includes("code 6000"), w.it.invoices.get("4999")!.voided, w.db.txns.get("cr-CR-01002")!.voided_at], [1, "failed", true, false, null], "refused void → failed · nothing deleted · txn not voided: " + v4.last_error);
  // 7) void 5xx → unknown → 아직 금액 → not_voided · 0 이면 found → done
  w.it.voidRefuse.delete("4999");
  const v5 = addCrVoid(w, "CR-01002", "4999", "2"); w.db.jobs.get(v4.id)!.state = "skipped";
  w.it.override.push((h) => h.method === "POST" && new URL(h.url).searchParams.get("operation") === "void" ? jres(502, {}, "tid-502") : null);
  const b11 = await body(await send(w, "JWT-MGR")); w.it.override.length = 0;
  eq([b11.unknown, v5.state, v5.qbo_name], [1, "unknown", "CR-01002"], "void 5xx → unknown with DocNumber");
  const b12 = await body(await send(w, "JWT-MGR"));
  eq([(b12.resolved as Record<string, unknown>[])[0].result, v5.state, String((b12.resolved as Record<string, unknown>[])[0].message).includes("credit memo still carries an amount")], ["not_voided", "unknown", true], "still carries an amount → not_voided");
  const cm = w.it.invoices.get("4999")!; cm.TotalAmt = 0; cm.TotalTax = 0; cm.voided = true; cm.SyncToken = 3;
  const b13 = await body(await send(w, "JWT-MGR"));
  eq([(b13.resolved as Record<string, unknown>[])[0].result, v5.state, w.db.txns.get("cr-CR-01002")!.voided_at !== null, (v5.last_error ?? "").includes("credit memo is voided (amount 0)")], ["found", "sent", true, true], "amount 0 → voided → done");
  writesAllowedOnly(w, "⑳"); noLeak(w, "⑳");
  const allText = JSON.stringify({ logs: w.logs, warns: w.warns });
  ok(!allText.includes("ZZPII"), "addresses · emails never reach call_log or warn");
  ok(!allText.includes("Regina"), "customer name not in call_log");
});

// ── qbo-sync-2d1 — 골라 보내기 장치: needs(손님 · 부모 · Item) · 960 크레딧 · 동시 5 · 예산 ──
const pickSend = (w: World, jobIds: unknown, jwt: string | null = "JWT-ADMIN") => postBody(w, { action: "send", job_ids: jobIds }, jwt);
function meter(w: World): { max: () => number; calls: () => number } {                                 // fetch 를 감싸 동시 호출 수를 센다(한 틱 뒤에 끝나게)
  const orig = w.deps.fetch; let inflight = 0, max = 0, calls = 0;
  w.deps.fetch = async (url, init) => { inflight++; calls++; max = Math.max(max, inflight); await new Promise((r) => setTimeout(r, 2)); try { return await orig(url, init); } finally { inflight--; } };
  return { max: () => max, calls: () => calls };
}
Deno.test("㉑ 골라 보내기(qbo-sync-2d1 · 판정 971) — 순수(SEND_PICK_* · ACTIONS 그대로) · 거부(배열 아님 · 빈 · 11 개 · uuid 아님 → 400 · qbo:read 403) · 인보이스 하나 고르면 need(부모 · Item → 손님) 를 같은 호출에서 먼저(바퀴 4 · POST 순서) · requested 는 id 마다(sent · not_found · not_queued(sent · failed 까닭)) · 크레딧 홀로 고르면 인보이스를 대신 보내지 않고 blocked + 까닭 · 함께 고르면 인보이스 → 크레딧(바퀴 2) · 10 장 동시 5(한 장 503 · 한 장 6140 이어도 나머지 sent · 결과는 일감마다) · 30 s 예산(바퀴 앞) · 옛 send{limit} 그대로(mode oldest) · writesAllowedOnly · PII 0", async () => {
  eq([SEND_PICK_MAX, SEND_PICK_ROUNDS, SEND_PICK_BUDGET_MS, SEND_PICK_PARALLEL], [10, 5, 30_000, 5], "2d1 constants");
  eq([...ACTIONS].includes("send") && !([...ACTIONS] as string[]).includes("preview"), true, "preview is a DB rpc, not an EF action");
  const w = world(); connect(w);
  w.db.keys["JWT-MGR"] = "qbo:read";
  eq((await pickSend(w, ["11111111-2222-4333-8444-000000000001"], "JWT-MGR")).status, 403, "qbo:read cannot send");
  w.db.keys["JWT-MGR"] = "qbo";
  const u = (n: number) => "11111111-2222-4333-8444-" + String(n).padStart(12, "0");
  for (const [bad, why] of [["x", "not an array"], [[], "empty"], [Array.from({ length: 11 }, (_, i) => u(i + 1)), "11 ids"], [["job-1"], "not a uuid"]] as [unknown, string][]) {
    const r = await pickSend(w, bad, "JWT-MGR"); eq([r.status, String((await body(r)).error).length > 10], [400, true], why + " → 400");
  }
  // 가짜 일감의 id 는 "job-N" 꼴이라 uuid 검사를 지나지 못한다 → 이 시험 안에서만 id 를 uuid 로 바꿔 둔다(DB 는 uuid)
  const uid = (j: Job) => { const id = u(Number(j.id.replace("job-", ""))); w.db.jobs.delete(j.id); j.id = id; w.db.jobs.set(id, j); return id; };
  // A — 인보이스 하나 · needs: 손님 C(부모 P) · Item I → 바퀴 1 blocked(need 3 생김) · 2 P + I(동시) · 3 C · 4 A
  const a = addInv(w, "70001", { needs: [{ kind: "customer", ims_id: "cust-C", name: "Kid Store", parent: { ims_id: "cust-P", name: "Parent Co" } }, { kind: "item", ims_id: "prod-I", name: "Widget I" }] }); const aId = uid(a);
  const m = meter(w);
  const rA = await pickSend(w, [aId], "JWT-MGR"); const bA = await body(rA);
  const req = bA.requested as Record<string, unknown>[];
  eq([rA.status, bA.ok, bA.mode, bA.rounds, bA.stopped, bA.sent, bA.failed, bA.unknown, bA.blocked, bA.claimed, bA.parallel], [200, true, "selected", 4, null, 1, 0, 0, 0, 5, 5], "one invoice → 4 rounds · claimed 5(A twice) · sent 1: " + JSON.stringify(bA));
  eq([req.length, req[0].job_id, req[0].result, req[0].round, req[0].qbo_id !== null, a.state, a.qbo_id !== null], [1, aId, "sent", 4, true, "sent", true], "requested = the invoice · sent in round 4");
  const needs = bA.needs as Record<string, unknown>[];
  eq(needs.map((x) => (x.kind as string) + ":" + x.result + ":" + x.round).sort(), ["customer:sent:2", "customer:sent:3", "item:sent:2"], "needs: parent + item round 2 · customer round 3: " + JSON.stringify(needs));
  const order = postHits(w).map((h) => { const b = JSON.parse(h.body || "{}"); return new URL(h.url).pathname.split("/").pop() + ":" + (b.DisplayName ?? b.Name ?? b.DocNumber); });
  eq([order.length, order.slice(0, 2).sort(), order[2], order[3]], [4, ["customer:Parent Co", "item:Widget I"], "customer:Kid Store", "invoice:70001"], "POST order: parent + item · customer · invoice: " + order.join(" "));
  eq(w.db.links.map((l) => l.ims_id).sort(), ["cust-C", "cust-P", "prod-I"], "three links created");
  // B — not_found · 이미 sent · failed 는 requested 에 까닭만 · 일감 무접촉
  const f = addInv(w, "70002"); const fId = uid(f); f.state = "failed"; f.last_error = "body rejected";
  const n0 = postHits(w).length;
  const bB = await body(await pickSend(w, [u(999), aId, fId], "JWT-MGR"));
  const rb = bB.requested as Record<string, unknown>[];
  eq([bB.rounds, bB.stopped, bB.sent, bB.not_sent, postHits(w).length - n0, rb.map((x) => x.result), rb[1].state, String(rb[2].reason)], [1, null, 0, 3, 0, ["not_found", "not_queued", "not_queued"], "sent", "the job is failed — not sent — retry it first"], "nothing to do(all terminal → stopped null) · reasons per id: " + JSON.stringify(rb));
  eq(f.state, "failed", "failed job untouched (no implicit retry)");
  // C — 크레딧 홀로: 인보이스 B 가 queued 인데 고르지 않았다 → blocked + 까닭 · 인보이스 POST 0 · 함께 고르면 인보이스 → 크레딧 바퀴 2
  const bi = addInv(w, "70003"); const biId = uid(bi);
  const cr = addCr(w, "CR-70003", { wait_job: biId }); const crId = uid(cr);
  const n1 = postHits(w).length;
  const bC = await body(await pickSend(w, [crId], "JWT-MGR"));
  const rc = (bC.requested as Record<string, unknown>[])[0];
  eq([bC.rounds, bC.stopped, bC.blocked, rc.result, String(rc.reason), postHits(w).length - n1, cr.state, cr.blocked_by, bi.state], [1, "no_progress", 1, "blocked", "waiting for invoice 70003 to reach QuickBooks first", 0, "blocked", biId, "queued"], "credit alone → blocked · the invoice is not sent on its behalf: " + JSON.stringify(bC));
  const bC2 = await body(await pickSend(w, [crId, biId], "JWT-MGR"));
  const rc2 = bC2.requested as Record<string, unknown>[];
  eq([bC2.rounds, bC2.sent, rc2.map((x) => x.job_id + ":" + x.result + ":" + x.round), bi.state, cr.state, postHits(w).length - n1], [2, 2, [crId + ":sent:2", biId + ":sent:1"], "sent", "sent", 2], "together: invoice round 1 → credit round 2: " + JSON.stringify(rc2));
  // D — 10 장 동시 5 · 503 하나(unknown) · 6140 하나(dupDoc → 다시 찾아 짝) · 나머지 sent · 결과는 일감마다
  const ten = Array.from({ length: 10 }, (_, i) => uid(addInv(w, "71" + String(i).padStart(3, "0"))));
  w.it.override.push((h) => h.method === "POST" && h.body.includes('"DocNumber":"71003"') ? jres(503, { Fault: { Error: [{ Message: "Service Unavailable", code: "3001" }], type: "SystemFault" } }, "tid-503") : null);
  w.it.invoices.set("4999", { Id: "4999", DocNumber: "71007", SyncToken: 0, TotalAmt: 40.68, TotalTax: 4.68, voided: false, CustomerRef: { value: "7190" } });   // 이미 있는 번호 → 조회에서 잡혀 안 만들고 짝
  const c0 = m.calls();
  const bD = await body(await pickSend(w, ten, "JWT-MGR"));
  const rd = bD.requested as Record<string, unknown>[];
  eq([bD.rounds, bD.sent, bD.unknown, bD.failed, bD.blocked, rd.length, m.max()], [1, 9, 1, 0, 0, 10, 5], "10 invoices in one round · 5 in flight at most · one unknown: " + JSON.stringify({ rounds: bD.rounds, sent: bD.sent, unknown: bD.unknown, max: m.max() }));
  eq(rd.map((x) => x.result), ["sent", "sent", "sent", "unknown", "sent", "sent", "sent", "sent", "sent", "sent"], "result per job in the order asked: " + JSON.stringify(rd.map((x) => x.result)));
  eq([String(rd[7].note).startsWith("already in QuickBooks (DocNumber found before sending)"), rd[7].qbo_id, String(rd[3].error).includes("HTTP 503")], [true, "4999", true], "71007 recorded from the existing row · 71003 unknown with the error");
  eq(m.calls() - c0, 10 + 9 + 1, "10 DocNumber checks + 9 POSTs + 1 read(71007 was found → read instead of POST) = " + (m.calls() - c0) + " (read of 4999 counted too)");
  w.it.override.length = 0;
  // E — 예산: 첫 바퀴에서 시계가 31 s 가면 둘째 바퀴를 열지 않는다(stopped time) · 잡힌 것은 끝까지 · need 가 남은 인보이스는 blocked 그대로(다시 보내면 이어진다)
  const slow = addInv(w, "72001"); const slowId = uid(slow);
  const nd = addInv(w, "72002", { needs: [{ kind: "item", ims_id: "prod-Z", name: "Widget Z" }] }); const ndId = uid(nd);
  w.it.override.push((h) => { if (h.method === "POST" && h.body.includes('"DocNumber":"72001"')) w.clock.t += 31_000; return null; });
  const bE = await body(await pickSend(w, [slowId, ndId], "JWT-MGR"));
  const re = bE.requested as Record<string, unknown>[];
  eq([bE.rounds, bE.stopped, re[0].result, re[1].result, nd.state, slow.state, [...w.db.jobs.values()].some((j) => j.ims_id === "prod-Z" && j.state === "queued")], [1, "time", "sent", "blocked", "blocked", "sent", true], "budget: round 1 only · need job left queued for the next send: " + JSON.stringify(bE));
  w.it.override.length = 0;
  const bE2 = await body(await pickSend(w, [ndId], "JWT-MGR"));
  eq([bE2.rounds, (bE2.requested as Record<string, unknown>[])[0].result, nd.state, (bE2.needs as Record<string, unknown>[]).map((x) => x.result)], [3, "sent", "sent", ["sent"]], "next send resumes it (round 1 finds the waiting item job · 2 sends it · 3 the invoice): " + JSON.stringify(bE2));
  // F — 옛 길(limit) 그대로 · 동시 아님 · mode oldest
  const old = addInv(w, "73001"); uid(old);
  const bF = await body(await send(w, "JWT-MGR", { limit: 5 }));
  eq([bF.mode, bF.claimed, bF.sent, bF.limit, old.state], ["oldest", 1, 1, 5, "sent"], "send { limit } unchanged: " + JSON.stringify(bF));
  writesAllowedOnly(w, "㉑"); noLeak(w, "㉑");
  const allText = JSON.stringify({ logs: w.logs, warns: w.warns });
  ok(!allText.includes("ZZPII") && !allText.includes("Regina"), "addresses · emails · names never reach call_log or warn");
});


// ── qbo-sync-2e-1c — 결제 시험 장치: 결제 일감(몸은 DB qbo_payment_body 꼴 · check_lines · lookup · fingerprint) · void 일감 · 가짜 장부의 인보이스에 Balance ──
const payBody = (ref: string | null, lines: { inv: string; amt: number }[], total: number, cust = "7190", note = "IMS payment 0e0e0e0e-0000-4000-8000-000000000001", date = "2026-11-02"): Record<string, unknown> => ({
  CustomerRef: { value: cust }, TxnDate: date, TotalAmt: total, CurrencyRef: { value: "CAD" }, PaymentMethodRef: { value: "2" }, DepositToAccountRef: { value: "105" }, ...(ref ? { PaymentRefNum: ref } : {}), PrivateNote: note,
  Line: lines.map((l) => ({ Amount: l.amt, LinkedTxn: [{ TxnId: l.inv, TxnType: "Invoice" }] })) });
const addPay = (w: World, ref: string, lines: { inv: string; doc: string; amt: number }[], total: number, extra: Partial<Job> = {}) => {
  const n = jobN + 1, note = "IMS payment 0e0e0e0e-0000-4000-8000-" + String(n).padStart(12, "0");
  const applied = lines.reduce((a, l) => a + l.amt, 0);
  return addJob(w, { kind: "payment", ims_id: "pay-" + ref, name: ref, doc_number: ref, body: payBody(ref, lines.map((l) => ({ inv: l.inv, amt: l.amt })), total, "7190", note),
    check_lines: lines.map((l) => ({ invoice_number: l.doc, qbo_invoice_id: l.inv, amount: l.amt })), lookup: { customer_ref: "7190", txn_date: "2026-11-02", total_amt: total, private_note: note },
    fingerprint: "fp-" + ref, pay_totals: { amount: total, unapplied: Math.round((total - applied) * 100) / 100 }, ...extra });
};
const addPayVoid = (w: World, ref: string, id: string | null, syncToken: string | null) => addJob(w, { kind: "payment_void", ims_id: "pay-" + ref, name: ref, doc_number: ref, body: id ? (syncToken !== null ? { Id: id, SyncToken: syncToken, sparse: true } : { Id: id, sparse: true }) : {} });
const ledgerInv = (w: World, id: string, doc: string, total = 40.68, balance?: number) => { w.it.invoices.set(id, { Id: id, DocNumber: doc, SyncToken: 0, TotalAmt: total, TotalTax: 4.68, voided: false, CustomerRef: { value: "7190" }, Balance: balance ?? total }); };
const payPosts = (w: World) => postHits(w).filter((h) => /\/payment\/?\?/.test(h.url));
const payVoidPosts = (w: World) => payPosts(w).filter((h) => new URL(h.url).searchParams.get("operation") === "update" && new URL(h.url).searchParams.get("include") === "void");
const payReads = (w: World) => apiHits(w).filter((h) => h.method === "GET" && /\/payment\/\d+\?/.test(h.url));
const payQueries = (w: World) => queryHits(w).filter((h) => /from\s+Payment\s+where\s+TxnDate\s*=/i.test(sentQuery(h) ?? ""));
const doneArgs = (w: World) => w.db.calls;   // 창구 호출 순서만

Deno.test("㉒ 결제 보내기 · void · 자동 길(qbo-sync-2e-1c · 판정 978 ~ 991 · sandbox B-4 · B-6) — 순수(SEND_KINDS 8 · PAYMENT_KINDS · 가드 가지 넷 · 열쇠 접기/펴기 · kindsOf) · (가) Balance 가드(GET invoice → 모자라면 failed · 못 읽으면 failed · POST 0) · POST payment(몸 그대로 · requestid · done 10 인자 · txn · 장부 Balance 줄어듦) · 일부 붙음(UnappliedAmt · 대조 mismatch) · unknown(5xx → 열쇠 → TxnDate 조회 → 0 not_found · 하나 found → done · 둘 ambiguous) · void(update&include=void {Id, SyncToken, sparse} · 2xx → voided_at · Balance 되돌림 · SyncToken 없으면 GET · 5010 → -2 · 4xx failed · 5xx → unknown → 읽어서 Voided 면 done) · send {kinds}(직원 · cron · 400 셋 · job_ids 길은 무시) · 쓰기 꼴 · 누출 0", async () => {
  // ⓪ 순수
  eq([...SEND_KINDS], ["customer", "item", "invoice", "invoice_void", "credit", "credit_void", "payment", "payment_void", "credit_apply", "credit_apply_void", "opening_credit", "opening_credit_void", "opening_apply", "opening_apply_void", "refund", "refund_void", "refund_apply", "refund_apply_void", "cost_day"], "SEND_KINDS 8 → 10 (2e-2-1b) → 14 (2e-3-1b) → 18 (2e-3-2-1b) → 19 (3-3)");
  eq([[...PAYMENT_KINDS], [...UPDATE_VOID_ENTITIES]], [["payment", "payment_void"], ["payment"]], "PAYMENT_KINDS · UPDATE_VOID_ENTITIES");
  const base = "https://sandbox-quickbooks.api.intuit.com/v3/company/9341458557490536/";
  assertWriteAllowed("POST", base + "payment?requestid=r1&minorversion=75");
  assertWriteAllowed("POST", base + "payment?operation=update&include=void&requestid=r1&minorversion=75");
  for (const bad of ["payment?operation=update&requestid=r1", "payment?operation=void&requestid=r1", "payment?include=void&requestid=r1", "invoice?operation=update&include=void&requestid=r1", "payment?operation=delete&requestid=r1", "payment?minorversion=75"]) {
    let threw = false; try { assertWriteAllowed("POST", base + bad); } catch { threw = true; } ok(threw, "refused: " + bad);
  }
  const key = paymentKeyOf({ customer_ref: "7190", txn_date: "2026-11-02", total_amt: 10, private_note: "IMS payment 0e0e0e0e-0000-4000-8000-000000000009" }, {});
  eq([key, parsePaymentKey(key), parsePaymentKey("x|y|z"), parsePaymentKey("IMS payment a|7190|2026-13-99|1")], ["IMS payment 0e0e0e0e-0000-4000-8000-000000000009|7190|2026-11-02|10", { privateNote: "IMS payment 0e0e0e0e-0000-4000-8000-000000000009", customerRef: "7190", txnDate: "2026-11-02", totalAmt: 10 }, null, null], "payment key fold · unfold");
  eq(paymentKeyOf(null, payBody("R", [], 5)), "IMS payment 0e0e0e0e-0000-4000-8000-000000000001|7190|2026-11-02|5", "key from the body when lookup is missing (old DB)");
  eq(paymentsByDateQueryText("2026-11-02"), "select Id, TotalAmt, UnappliedAmt, SyncToken, PrivateNote, PaymentRefNum, CustomerRef, TxnDate from Payment where TxnDate = '2026-11-02' MAXRESULTS 100", "payments-by-date query (no PII fields)");
  eq([isVoidedPayment({ TotalAmt: 0, PrivateNote: "Voided - IMS payment x" }), isVoidedPayment({ TotalAmt: 0, PrivateNote: "IMS payment x" }), isVoidedPayment({ TotalAmt: 10, PrivateNote: "Voided - x" }), isVoidedPayment(null)], [true, false, false, false], "voided = TotalAmt 0 and Voided note");
  eq([kindsOf(undefined), kindsOf(null), kindsOf(["payment", "payment", "payment_void"])], [[...DEFAULT_SEND_KINDS], [...DEFAULT_SEND_KINDS], ["payment", "payment_void"]], "kindsOf: default 18 (3-3: cost_day only when named) · dedupe");
  for (const bad of [[], "payment", ["bogus"], [""], 5]) { let threw = false; try { kindsOf(bad); } catch (e) { threw = e instanceof QboError && e.status === 400; } ok(threw, "kindsOf refuses " + JSON.stringify(bad)); }

  const w = world(); connect(w); w.db.keys["JWT-MGR"] = "qbo";
  ledgerInv(w, "5101", "60201"); ledgerInv(w, "5102", "60202", 40.68, 5); ledgerInv(w, "5103", "60203"); ledgerInv(w, "5104", "60204"); ledgerInv(w, "5105", "60205"); ledgerInv(w, "5106", "60206");
  // ① 보통 결제 — GET invoice(Balance) 1 → POST payment 1 · 몸 그대로 · requestid · done(TotalAmt 10 · unapplied 0) · txn · 장부 Balance 30.68
  const p1 = addPay(w, "CHQ 1", [{ inv: "5101", doc: "60201", amt: 10 }], 10);
  const r0 = invReads(w).length;
  const b1 = await body(await send(w, "JWT-MGR", { kinds: ["payment", "payment_void"] }));
  const pp = payPosts(w);
  eq([b1.sent, b1.kinds, invReads(w).length - r0, pp.length, JSON.parse(pp[0].body), new URL(pp[0].url).searchParams.get("requestid"), new URL(pp[0].url).searchParams.get("operation")], [1, ["payment", "payment_void"], 1, 1, p1.body, p1.request_id, null], "one Balance read, one POST payment with the DB body: " + JSON.stringify(b1.jobs));
  const t1 = w.db.txns.get("pay-CHQ 1")!;
  eq([p1.state, p1.qbo_id, t1.qbo_id, t1.doc_number, t1.total_amt, t1.unapplied, t1.total_tax, t1.fingerprint, t1.mismatch, w.it.invoices.get("5101")!.Balance, (b1.jobs as Record<string, unknown>[])[0].mismatch], ["sent", "7001", "7001", "CHQ 1", 10, 0, null, "fp-CHQ 1", null, 30.68, null], "done 10 args → txn with fingerprint · invoice balance reduced");
  const l1 = w.logs.filter((l) => l.action === "send" && l.detail?.job_id === p1.id);
  eq([l1.length, l1[0].detail?.qbo_id, l1[0].detail?.request_id], [1, "7001", p1.request_id], "write logged with job · qbo id · requestid");
  // ② (가) Balance 가드 — 5102 는 Balance 5 < 15 → failed · POST 0 · 글
  const p2 = addPay(w, "CHQ 2", [{ inv: "5102", doc: "60202", amt: 15 }], 15); const n2 = payPosts(w).length;
  const b2 = await body(await send(w, "JWT-MGR", { kinds: ["payment"] }));
  eq([b2.failed, payPosts(w).length - n2, p2.state, (p2.last_error ?? "").startsWith("not sent — QuickBooks already shows 35.68 paid on invoice 60202 (balance 5 < 15)"), w.it.invoices.get("5102")!.Balance], [1, 0, "failed", true, 5], "balance guard → failed, nothing written: " + p2.last_error);
  // ③ 못 읽음(없는 인보이스 9999 · 404) → failed · POST 0
  const p3 = addPay(w, "CHQ 3", [{ inv: "9999", doc: "60299", amt: 1 }], 1); const n3 = payPosts(w).length;
  const b3 = await body(await send(w, "JWT-MGR", { kinds: ["payment"] }));
  eq([b3.failed, payPosts(w).length - n3, p3.state, (p3.last_error ?? "").startsWith("not sent — could not read invoice 60299 (QuickBooks #9999) before sending")], [1, 0, "failed", true], "unreadable invoice → failed: " + p3.last_error);
  // ④ 일부만 붙음 — 25 중 5 · UnappliedAmt 20 · IMS 가 20 이라 했으면 mismatch 없음 / IMS 가 0 이라 하면(검산 거짓) mismatch 경고 · 상태 sent
  const p4 = addPay(w, "CHQ 4", [{ inv: "5103", doc: "60203", amt: 5 }], 25);
  const p5 = addPay(w, "CHQ 5", [{ inv: "5104", doc: "60204", amt: 5 }], 25, { pay_totals: { amount: 25, unapplied: 0 } });
  const b4 = await body(await send(w, "JWT-MGR", { kinds: ["payment"] }));
  eq([b4.sent, b4.mismatch, w.db.txns.get("pay-CHQ 4")!.unapplied, w.db.txns.get("pay-CHQ 4")!.mismatch, p5.state, (w.db.txns.get("pay-CHQ 5")!.mismatch ?? "").includes("QuickBooks unapplied 20 differs from IMS 0"), (p5.warning ?? "").includes("(942)")], [2, 1, 20, null, "sent", true, true], "partial payment: UnappliedAmt 20 · mismatch only when IMS disagrees");
  // ⑤ unknown — 5xx → unknown(qbo_name = 열쇠) → 다음 send: 그 날 조회 → 없음 not_found → 손으로 만든 셈(가짜 장부에 넣음) → found → done · 둘이면 ambiguous
  const p6 = addPay(w, "CHQ 6", [{ inv: "5105", doc: "60205", amt: 7 }], 7);
  w.it.override.push((h) => h.method === "POST" && /\/payment\/?\?/.test(h.url) ? jres(502, {}, "tid-502") : null);
  const b6 = await body(await send(w, "JWT-MGR", { kinds: ["payment"] })); w.it.override.length = 0;
  const key6 = "IMS payment 0e0e0e0e-0000-4000-8000-" + String(Number(p6.id.slice(4))).padStart(12, "0") + "|7190|2026-11-02|7";
  eq([b6.unknown, p6.state, p6.qbo_name], [1, "unknown", key6], "5xx → unknown with the payment key: " + p6.qbo_name);
  const b7 = await body(await send(w, "JWT-MGR", { kinds: ["payment"] }));
  const rs7 = b7.resolved as Record<string, unknown>[];
  eq([rs7[0].result, p6.state, payQueries(w).length, /where TxnDate = '2026-11-02' MAXRESULTS 100/.test(sentQuery(payQueries(w)[0]) ?? "")], ["not_found", "unknown", 1, true], "not in QuickBooks yet → not_found (query by date)");
  w.it.payments.set("7777", { Id: "7777", SyncToken: 0, TotalAmt: 7, UnappliedAmt: 0, CustomerRef: { value: "7190" }, TxnDate: "2026-11-02", PaymentRefNum: "CHQ 6", PrivateNote: key6.split("|")[0] + " · entered by hand", Line: [], voided: false, DepositToAccountRef: { value: "105" }, PaymentMethodRef: { value: "2" } });
  w.it.payments.set("7778", { Id: "7778", SyncToken: 0, TotalAmt: 7, UnappliedAmt: 0, CustomerRef: { value: "7190" }, TxnDate: "2026-11-02", PaymentRefNum: "other", PrivateNote: "something else", Line: [], voided: false, DepositToAccountRef: { value: "105" }, PaymentMethodRef: { value: "2" } });
  const b8 = await body(await send(w, "JWT-MGR", { kinds: ["payment"] }));
  const rs8 = b8.resolved as Record<string, unknown>[];
  eq([rs8[0].result, rs8[0].qbo_id, p6.state, p6.qbo_id, w.db.txns.get("pay-CHQ 6")!.qbo_id, (p6.last_error ?? "").includes("found in QuickBooks by date, customer, amount and note")], ["found", "7777", "sent", "7777", "7777", true], "found by date · customer · amount · note → done (the other row on that day is ignored)");
  const p9 = addPay(w, "CHQ 9", [{ inv: "5106", doc: "60206", amt: 3 }], 3);
  w.it.override.push((h) => h.method === "POST" && /\/payment\/?\?/.test(h.url) ? jres(502, {}, "tid-502") : null);
  await body(await send(w, "JWT-MGR", { kinds: ["payment"] })); w.it.override.length = 0;
  const key9 = String(p9.qbo_name);
  for (const id of ["7781", "7782"]) w.it.payments.set(id, { Id: id, SyncToken: 0, TotalAmt: 3, UnappliedAmt: 0, CustomerRef: { value: "7190" }, TxnDate: "2026-11-02", PaymentRefNum: "CHQ 9", PrivateNote: key9.split("|")[0], Line: [], voided: false, DepositToAccountRef: { value: "105" }, PaymentMethodRef: { value: "2" } });
  const b9 = await body(await send(w, "JWT-MGR", { kinds: ["payment"] }));
  eq([(b9.resolved as Record<string, unknown>[])[0].result, (b9.resolved as Record<string, unknown>[])[0].rows, p9.state], ["ambiguous", 2, "unknown"], "two matching payments → ambiguous, job stays unknown");
  // ⑥ void — 7001 보통(Id · SyncToken · sparse → update&include=void · done · voided_at · Balance 되돌림) · SyncToken 없음 → GET 먼저 · 5010 → -2 · 4xx failed · 5xx → unknown → 읽어서 Voided → done
  const v1 = addPayVoid(w, "CHQ 1", "7001", "0");
  const bv1 = await body(await send(w, "JWT-MGR", { kinds: ["payment_void"] }));
  const vp = payVoidPosts(w);
  eq([bv1.sent, vp.length, JSON.parse(vp[0].body), new URL(vp[0].url).searchParams.get("requestid"), v1.state, w.db.txns.get("pay-CHQ 1")!.voided_at !== null, w.it.payments.get("7001")!.voided, w.it.payments.get("7001")!.TotalAmt, w.it.invoices.get("5101")!.Balance], [1, 1, { Id: "7001", SyncToken: "0", sparse: true }, v1.request_id, "sent", true, true, 0, 40.68], "void via operation=update&include=void · balance restored");
  const vl = w.logs.filter((l) => l.action === "send" && l.detail?.operation === "update");
  eq([vl.length, vl[0].detail?.include, vl[0].detail?.job_id], [1, "void", v1.id], "void write logged with operation · include");
  const v2 = addPayVoid(w, "CHQ 4", "7002", null); const pr0 = payReads(w).length;
  const bv2 = await body(await send(w, "JWT-MGR", { kinds: ["payment_void"] }));
  eq([bv2.sent, payReads(w).length - pr0, v2.state, (v2.last_error ?? "").includes("SyncToken read from QuickBooks before voiding"), w.it.payments.get("7002")!.voided], [1, 1, "sent", true, true], "no SyncToken → read first, then void");
  w.it.payments.get("7003")!.SyncToken = 3;
  const v3 = addPayVoid(w, "CHQ 5", "7003", "0"); const nv3 = payVoidPosts(w).length;
  const bv3 = await body(await send(w, "JWT-MGR", { kinds: ["payment_void"] }));
  const p3v = payVoidPosts(w).slice(nv3);
  eq([bv3.sent, p3v.length, JSON.parse(p3v[1].body).SyncToken, new URL(p3v[1].url).searchParams.get("requestid"), v3.state, (v3.last_error ?? "").includes("stale SyncToken (5010)")], [1, 2, "3", v3.request_id + "-2", "sent", true], "stale → re-read → second try with -2");
  w.it.voidRefuse.add("7777");
  const v4 = addPayVoid(w, "CHQ 6", "7777", "0");
  const bv4 = await body(await send(w, "JWT-MGR", { kinds: ["payment_void"] }));
  eq([bv4.failed, v4.state, (v4.last_error ?? "").includes("code 6000"), w.it.payments.get("7777")!.voided], [1, "failed", true, false], "refused void → failed: " + v4.last_error);
  w.it.voidRefuse.delete("7777");
  const v5 = addJob(w, { kind: "payment_void", ims_id: "pay-CHQ 6", name: "CHQ 6", doc_number: "CHQ 6", body: { Id: "7777", SyncToken: "0", sparse: true } });
  w.it.override.push((h) => h.method === "POST" && new URL(h.url).searchParams.get("include") === "void" ? jres(502, {}, "tid-502") : null);
  const bv5 = await body(await send(w, "JWT-MGR", { kinds: ["payment_void"] })); w.it.override.length = 0;
  eq([bv5.unknown, v5.state, v5.qbo_name], [1, "unknown", "7777"], "void 5xx → unknown with the payment id");
  const bv6 = await body(await send(w, "JWT-MGR", { kinds: ["payment_void"] }));
  const rv6 = (bv6.resolved as Record<string, unknown>[]).find((x) => x.job_id === v5.id)!;
  eq([rv6.result, v5.state], ["not_voided", "unknown"], "still carries an amount → not_voided");
  const pv = w.it.payments.get("7777")!; pv.TotalAmt = 0; pv.UnappliedAmt = 0; pv.Line = []; pv.voided = true; pv.PrivateNote = "Voided - " + pv.PrivateNote; pv.SyncToken = 1;
  const bv7 = await body(await send(w, "JWT-MGR", { kinds: ["payment_void"] }));
  const rv7 = (bv7.resolved as Record<string, unknown>[]).find((x) => x.job_id === v5.id)!;
  eq([rv7.result, v5.state, w.db.txns.get("pay-CHQ 6")!.voided_at !== null, (v5.last_error ?? "").includes("voided (amount 0)")], ["found", "sent", true, true], "Voided note + amount 0 → done");
  const v6 = addPayVoid(w, "CHQ 7", null, null);
  const bv8 = await body(await send(w, "JWT-MGR", { kinds: ["payment_void"] }));
  eq([bv8.failed, v6.state, (v6.last_error ?? "").startsWith("not sent — no QuickBooks payment id")], [1, "failed", true], "void job without id → failed");
  // ⑦ kinds — 직원 길 · cron 길 · 거부 셋 · job_ids 길은 kinds 를 안 본다 · 옛 꼴(kinds 없음)은 8 종류 전부
  const kinds0 = w.db.claimKinds.length;
  const bk1 = await body(await send(w, "JWT-MGR", { kinds: ["payment"] }));
  eq([bk1.kinds, w.db.claimKinds[w.db.claimKinds.length - 1]], [["payment"], ["payment"]], "staff send with kinds → claim p_kinds");
  const p11 = addPay(w, "CHQ 11", [{ inv: "5106", doc: "60206", amt: 2 }], 2);
  const rc = await postBody(w, { action: "send", kinds: ["payment", "payment_void"], limit: 7 }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" });
  const bc = await body(rc);
  eq([rc.status, bc.ok, bc.kinds, bc.limit, bc.sent, p11.state, w.db.claimKinds[w.db.claimKinds.length - 1], w.logs.filter((l) => l.action === "send").at(-1)?.by_staff ?? null], [200, true, ["payment", "payment_void"], 7, 1, "sent", ["payment", "payment_void"], null], "cron 62 shape: kinds + limit · one payment sent · by_staff null");
  for (const bad of [{ kinds: [] }, { kinds: ["bogus"] }, { kinds: "payment" }]) eq((await postBody(w, { action: "send", ...bad }, "JWT-MGR")).status, 400, "send kinds refused: " + JSON.stringify(bad));
  const bk2 = await body(await send(w, "JWT-MGR"));
  eq(bk2.kinds, [...DEFAULT_SEND_KINDS], "no kinds → default 18 (old callers unchanged · 3-3: cost_day only when named)");
  const p10 = addPay(w, "CHQ 10", [{ inv: "5105", doc: "60205", amt: 1 }], 1);
  const pid10 = "0e0e0e0e-0000-4000-8000-" + String(Number(p10.id.replace("job-", ""))).padStart(12, "0"); w.db.jobs.delete(p10.id); p10.id = pid10; w.db.jobs.set(pid10, p10);   // job_ids 길은 uuid 만 받는다
  const bk3 = await body(await postBody(w, { action: "send", job_ids: [pid10], kinds: ["customer"] }, "JWT-MGR"));
  eq([bk3.mode, bk3.kinds, bk3.sent, p10.state], ["selected", [...SEND_KINDS], 1, "sent"], "job_ids path ignores kinds (bookkeeper picks a payment job)");
  ok(w.db.claimKinds.length > kinds0, "claims happened");
  writesAllowedOnly(w, "㉒"); noLeak(w, "㉒");
  ok(!JSON.stringify({ logs: w.logs, warns: w.warns }).includes("ZZPII"), "no PII in logs");
});

// ── 2e-2-1b 크레딧 붙임(0 원 Payment) 장치 — 몸 · check_lines · lookup 은 DB qbo_credit_apply_body 꼴(11-04 CR-01008 → 60026 preview 실물 · CustomerRef 9242 · TxnDate 2026-11-02 · 계좌 · 수단 · 참조 없음) ──
const caBody = (inv: string, cm: string, amt: number, note: string, cust = "9242", date = "2026-11-02"): Record<string, unknown> => ({
  CustomerRef: { value: cust }, TxnDate: date, TotalAmt: 0, CurrencyRef: { value: "CAD" }, PrivateNote: note,
  Line: [{ Amount: amt, LinkedTxn: [{ TxnId: inv, TxnType: "Invoice" }] }, { Amount: amt, LinkedTxn: [{ TxnId: cm, TxnType: "CreditMemo" }] }] });
const caNoteOf = (n: number) => "IMS credit applied 2e2e2e2e-0000-4000-8000-" + String(n).padStart(12, "0");
const addCa = (w: World, label: string, inv: string, invDoc: string, cm: string, cmDoc: string, amt: number, extra: Partial<Job> = {}) => {
  const note = caNoteOf(jobN + 1);
  return addJob(w, { kind: "credit_apply", ims_id: "ca-" + label, name: label, doc_number: label, body: caBody(inv, cm, amt, note),
    check_lines: [{ txn_type: "Invoice", invoice_number: invDoc, qbo_invoice_id: inv, amount: amt }, { txn_type: "CreditMemo", credit_number: cmDoc, qbo_creditmemo_id: cm, amount: amt }],
    lookup: { customer_ref: "9242", txn_date: "2026-11-02", total_amt: 0, private_note: note }, pay_totals: { amount: 0, unapplied: 0 }, ...extra });
};
const addCaVoid = (w: World, label: string, id: string | null, syncToken: string | null) => addJob(w, { kind: "credit_apply_void", ims_id: "ca-" + label, name: label, doc_number: label, body: id ? (syncToken !== null ? { Id: id, SyncToken: syncToken, sparse: true } : { Id: id, sparse: true }) : {} });
const ledgerCm = (w: World, id: string, doc: string, total: number, remaining?: number, balance?: number) => { w.it.invoices.set(id, { Id: id, DocNumber: doc, SyncToken: 0, TotalAmt: total, TotalTax: 0, voided: false, CustomerRef: { value: "9242" }, ent: "CreditMemo", Balance: balance ?? remaining ?? total, RemainingCredit: remaining ?? total }); };
const caKeyOf = (j: Job) => String(((j.body.PrivateNote ?? "") as string)) + "|9242|2026-11-02|0";

Deno.test("㉓ 크레딧 붙임 = 0 원 Payment 보내기 · void(qbo-sync-2e-2-1b · 판정 1009 · 1011 ~ 1016 · sandbox C-5″ · C-6) — 순수(SEND_KINDS 10 · CREDIT_APPLY_KINDS · PAYMENT_KINDS 무변 · parsePaymentKey 접두 둘 · kindsOf 넷 · 모르는 값 400) · ① 가드 둘 통과 → POST payment(몸 그대로 · requestid · 계좌 없음) → done(TotalAmt 0 · UnappliedAmt 0 · txn 지문 없음 · 인보이스 Balance · 크레딧 RemainingCredit 줄어듦) · ② Invoice Balance 모자람 failed · ③ CreditMemo RemainingCredit 모자람(Balance 는 넉넉) failed · ④ 못 읽음 둘 failed · check_lines 결함 failed · ⑤ 4xx failed · ⑥ 5xx · 끊김 unknown(열쇠) · ⑦ 풀기 0 · 1 · 2(완전 일치 · Voided 제외) · ⑧ void(SyncToken 없음 · 5010 · 거부 · 5xx → not_voided → done) · ⑨ 골라 보내기는 void 를 대신 보내지 않는다(960 · 1013) · 쓰기 꼴 · 누출 0", async () => {
  // ⓪ 순수
  eq([[...SEND_KINDS].length, [...CREDIT_APPLY_KINDS], [...PAYMENT_KINDS]], [19, ["credit_apply", "credit_apply_void"], ["payment", "payment_void"]], "SEND_KINDS 10 → 14 (2e-3-1b) → 18 (2e-3-2-1b) → 19 (3-3) · CREDIT_APPLY_KINDS · PAYMENT_KINDS unchanged");
  const k0 = "IMS credit applied 2e2e2e2e-0000-4000-8000-000000000001|9242|2026-11-02|0";
  eq([parsePaymentKey(k0), parsePaymentKey("IMS credit 2e2e|9242|2026-11-02|0"), parsePaymentKey("IMS payment x|7190|2026-11-02|10")?.totalAmt], [{ privateNote: "IMS credit applied 2e2e2e2e-0000-4000-8000-000000000001", customerRef: "9242", txnDate: "2026-11-02", totalAmt: 0 }, null, 10], "payment key: both prefixes · others still refused");
  eq(kindsOf(["payment", "payment_void", "credit_apply", "credit_apply_void"]), ["payment", "payment_void", "credit_apply", "credit_apply_void"], "kindsOf: the four cron-62 kinds");
  for (const bad of [["credit_apply", "bogus"], ["credit_alloc"], ["Credit_Apply"]]) { let threw = false; try { kindsOf(bad); } catch (e) { threw = e instanceof QboError && e.status === 400; } ok(threw, "kindsOf refuses " + JSON.stringify(bad)); }

  const w = world(); connect(w); w.db.keys["JWT-MGR"] = "qbo";
  ledgerInv(w, "6101", "60301", 14.67); ledgerCm(w, "6201", "CR-01008", 13.52);
  // ① 성공 — GET invoice 1 · GET creditmemo 1 → POST payment 1(몸 그대로 · requestid · operation 없음 · 길은 /payment) → done 10 인자(TotalAmt 0 · UnappliedAmt 0) · txn(지문 없음 · mismatch 없음) · 장부: Balance 14.67 → 1.15 · RemainingCredit 13.52 → 0 · 응답에 DepositToAccountRef 없음
  const a1 = addCa(w, "CR-01008 → 60301", "6101", "60301", "6201", "CR-01008", 13.52);
  const ir0 = invReads(w).length, cr0 = cmReads(w).length, pr0 = payReads(w).length;
  const b1 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] }));
  const pp = payPosts(w);
  eq([b1.sent, b1.failed, b1.unknown, b1.kinds, invReads(w).length - ir0, cmReads(w).length - cr0, payReads(w).length - pr0, pp.length, JSON.parse(pp[0].body), new URL(pp[0].url).pathname.endsWith("/payment"), new URL(pp[0].url).searchParams.get("requestid"), new URL(pp[0].url).searchParams.get("operation")],
     [1, 0, 0, ["credit_apply"], 1, 1, 0, 1, a1.body, true, a1.request_id, null], "one invoice read, one credit memo read, one POST payment with the DB body: " + JSON.stringify(b1.jobs));
  const t1 = w.db.txns.get("ca-CR-01008 → 60301")!, q1 = w.it.payments.get(String(a1.qbo_id))!;
  eq([a1.state, a1.qbo_id, t1.qbo_id, t1.doc_number, t1.total_amt, t1.unapplied, t1.total_tax, t1.fingerprint, t1.mismatch, (b1.jobs as Record<string, unknown>[])[0].mismatch, w.it.invoices.get("6101")!.Balance, w.it.invoices.get("6201")!.RemainingCredit, q1.TotalAmt, q1.UnappliedAmt, q1.DepositToAccountRef, q1.Line.length],
     ["sent", "7001", "7001", "CR-01008 → 60301", 0, 0, null, null, null, null, 1.15, 0, 0, 0, undefined, 2], "done → txn credit_alloc (label as doc_number · no fingerprint) · ledger moved · 0.00 payment has no deposit account");
  const l1 = w.logs.filter((l) => l.action === "send" && l.detail?.job_id === a1.id);
  eq([l1.length, l1[0].detail?.qbo_id, l1[0].detail?.request_id, l1[0].detail?.kind], [1, "7001", a1.request_id, "credit_apply"], "write logged with job · qbo id · requestid");
  // ② Invoice Balance 모자람(5 < 10) → failed · POST 0 · 크레딧은 읽지 않는다(인보이스 먼저)
  ledgerInv(w, "6102", "60302", 40.68, 5); ledgerCm(w, "6202", "CR-01009", 20);
  const a2 = addCa(w, "CR-01009 → 60302", "6102", "60302", "6202", "CR-01009", 10); const n2 = payPosts(w).length, cr2 = cmReads(w).length;
  const b2 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] }));
  eq([b2.failed, payPosts(w).length - n2, cmReads(w).length - cr2, a2.state, a2.last_error, w.it.invoices.get("6102")!.Balance, w.it.invoices.get("6202")!.RemainingCredit], [1, 0, 0, "failed", "not sent — QuickBooks already shows 35.68 paid on invoice 60302 (balance 5 < 10) — a payment or credit entered before the switch-over or in QuickBooks? check before sending, then retry or skip", 5, 20], "invoice balance guard → failed, nothing written");
  // ③ CreditMemo RemainingCredit 모자람(3 < 10) — Balance 는 20 으로 넉넉: 둘을 가른다 → failed · POST 0
  ledgerInv(w, "6103", "60303"); ledgerCm(w, "6203", "CR-01010", 20, 3, 20);
  const a3 = addCa(w, "CR-01010 → 60303", "6103", "60303", "6203", "CR-01010", 10); const n3 = payPosts(w).length;
  const b3 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] }));
  eq([b3.failed, payPosts(w).length - n3, a3.state, a3.last_error, w.it.invoices.get("6103")!.Balance], [1, 0, "failed", "not sent — QuickBooks shows only 3 left on credit memo CR-01010 (less than 10) — applied in QuickBooks or before the switch-over? check before sending, then retry or skip", 40.68], "RemainingCredit guard (not Balance) → failed, nothing written");
  // ④ 못 읽음 — 인보이스 9999(404) · 크레딧 9998(404 · 인보이스는 멀쩡) → failed · POST 0 · check_lines 결함(줄 하나 · null) → failed · 읽기도 0
  ledgerInv(w, "6104", "60304"); ledgerCm(w, "6204", "CR-01011", 20);
  const a4 = addCa(w, "CR-01011 → 60399", "9999", "60399", "6204", "CR-01011", 1); const n4 = payPosts(w).length;
  const b4 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] }));
  eq([b4.failed, payPosts(w).length - n4, a4.state, (a4.last_error ?? "").startsWith("not sent — could not read invoice 60399 (QuickBooks #9999) before sending")], [1, 0, "failed", true], "unreadable invoice → failed: " + a4.last_error);
  const a5 = addCa(w, "CR-01099 → 60304", "6104", "60304", "9998", "CR-01099", 1);
  const b5 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] }));
  eq([b5.failed, payPosts(w).length - n4, a5.state, (a5.last_error ?? "").startsWith("not sent — could not read credit memo CR-01099 (QuickBooks #9998) before sending")], [1, 0, "failed", true], "unreadable credit memo → failed: " + a5.last_error);
  const a6 = addCa(w, "CR-01011 → 60304 (one line)", "6104", "60304", "6204", "CR-01011", 1, { check_lines: [{ txn_type: "Invoice", invoice_number: "60304", qbo_invoice_id: "6104", amount: 1 }] });
  const a7 = addCa(w, "CR-01011 → 60304 (no lines)", "6104", "60304", "6204", "CR-01011", 1, { check_lines: null });
  const ir6 = invReads(w).length, cr6 = cmReads(w).length;
  const b6 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] }));
  eq([b6.failed, payPosts(w).length - n4, invReads(w).length - ir6, cmReads(w).length - cr6, a6.state, a6.last_error, a7.state, (a7.last_error ?? "").startsWith("not sent — the job carries 0 check line(s)")], [2, 0, 0, 0, "failed", "not sent — the job carries 1 check line(s) instead of one invoice and one credit memo — nothing was written; retry it after checking the credit application", "failed", true], "check_lines must be one invoice + one credit memo (이견 3)");
  // ⑤ POST 4xx(6000) → failed · 장부 그대로
  ledgerInv(w, "6105", "60305"); ledgerCm(w, "6205", "CR-01012", 20);
  const a8 = addCa(w, "CR-01012 → 60305", "6105", "60305", "6205", "CR-01012", 4);
  w.it.override.push((h) => h.method === "POST" && /\/payment\/?\?/.test(h.url) ? jres(400, { Fault: { Error: [{ Message: "Business Validation Error", Detail: "ZZ validation", code: "6000" }], type: "ValidationFault" } }, "tid-6000") : null);
  const b8 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] })); w.it.override.length = 0;
  eq([b8.failed, a8.state, (a8.last_error ?? "").includes("6000"), w.db.txns.has("ca-CR-01012 → 60305")], [1, "failed", true, false], "4xx → failed: " + a8.last_error);
  // ⑥ 5xx → unknown(열쇠 = 결제 꼴 · 총액 0) · 끊김도 unknown
  ledgerInv(w, "6106", "60306"); ledgerCm(w, "6206", "CR-01013", 20);
  const a9 = addCa(w, "CR-01013 → 60306", "6106", "60306", "6206", "CR-01013", 6);
  w.it.override.push((h) => h.method === "POST" && /\/payment\/?\?/.test(h.url) ? jres(502, {}, "tid-502") : null);
  const b9 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] })); w.it.override.length = 0;
  eq([b9.unknown, a9.state, a9.qbo_name, parsePaymentKey(a9.qbo_name)?.totalAmt], [1, "unknown", caKeyOf(a9), 0], "5xx → unknown with the credit-applied key: " + a9.qbo_name);
  const a10 = addCa(w, "CR-01013 → 60306 (b)", "6106", "60306", "6206", "CR-01013", 1);
  w.it.override.push((h) => h.method === "POST" && /\/payment\/?\?/.test(h.url) ? new Error("connection reset") : null);
  const b10 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] })); w.it.override.length = 0;
  eq([b10.unknown, a10.state, a10.qbo_name], [1, "unknown", caKeyOf(a10)], "network error → unknown with the key");
  // ⑦ 풀기 — 그 날 조회 → 0 not_found(「Voided - 」 장 · 메모에 덧붙인 장 · 금액 0 아닌 장은 안 잡힌다 — 완전 일치 · Voided 제외) → 하나 found → done · 둘 ambiguous · DocNumber 조회 0
  const noteA = String(a9.body.PrivateNote), dq0 = (w.it.hits.filter((h) => /DocNumber/.test(h.url))).length;
  w.it.payments.set("7901", { Id: "7901", SyncToken: 0, TotalAmt: 0, UnappliedAmt: 0, CustomerRef: { value: "9242" }, TxnDate: "2026-11-02", PaymentRefNum: null, PrivateNote: "Voided - " + noteA, Line: [], voided: true, DepositToAccountRef: undefined, PaymentMethodRef: undefined });
  w.it.payments.set("7902", { Id: "7902", SyncToken: 0, TotalAmt: 0, UnappliedAmt: 0, CustomerRef: { value: "9242" }, TxnDate: "2026-11-02", PaymentRefNum: null, PrivateNote: noteA + " · entered by hand", Line: [], voided: false, DepositToAccountRef: undefined, PaymentMethodRef: undefined });
  w.it.payments.set("7903", { Id: "7903", SyncToken: 0, TotalAmt: 6, UnappliedAmt: 0, CustomerRef: { value: "9242" }, TxnDate: "2026-11-02", PaymentRefNum: "x", PrivateNote: noteA, Line: [], voided: false, DepositToAccountRef: { value: "105" }, PaymentMethodRef: { value: "2" } });
  const b11 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] }));
  const r11 = (b11.resolved as Record<string, unknown>[]).find((x) => x.job_id === a9.id)!;
  eq([r11.result, a9.state, /where TxnDate = '2026-11-02' MAXRESULTS 100/.test(sentQuery(payQueries(w).at(-1)!) ?? ""), w.it.hits.filter((h) => /DocNumber/.test(h.url)).length - dq0], ["not_found", "unknown", true, 0], "voided twin · note-with-suffix · non-zero amount are not it → not_found (no DocNumber query)");
  w.it.payments.set("7904", { Id: "7904", SyncToken: 0, TotalAmt: 0, UnappliedAmt: 0, CustomerRef: { value: "9242" }, TxnDate: "2026-11-02", PaymentRefNum: null, PrivateNote: noteA, Line: [{ Amount: 6, LinkedTxn: [{ TxnId: "6106", TxnType: "Invoice" }] }, { Amount: 6, LinkedTxn: [{ TxnId: "6206", TxnType: "CreditMemo" }] }], voided: false, DepositToAccountRef: undefined, PaymentMethodRef: undefined });
  const b12 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] }));
  const r12 = (b12.resolved as Record<string, unknown>[]).find((x) => x.job_id === a9.id)!;
  eq([r12.result, r12.qbo_id, a9.state, a9.qbo_id, w.db.txns.get("ca-CR-01013 → 60306")!.qbo_id, w.db.txns.get("ca-CR-01013 → 60306")!.total_amt, (a9.last_error ?? "").includes("found in QuickBooks by date, customer, amount 0 and note")], ["found", "7904", "sent", "7904", "7904", 0, true], "exact note + amount 0 + customer → done");
  const noteB = String(a10.body.PrivateNote);
  for (const id of ["7905", "7906"]) w.it.payments.set(id, { Id: id, SyncToken: 0, TotalAmt: 0, UnappliedAmt: 0, CustomerRef: { value: "9242" }, TxnDate: "2026-11-02", PaymentRefNum: null, PrivateNote: noteB, Line: [], voided: false, DepositToAccountRef: undefined, PaymentMethodRef: undefined });
  const b13 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] }));
  const r13 = (b13.resolved as Record<string, unknown>[]).find((x) => x.job_id === a10.id)!;
  eq([r13.result, r13.rows, a10.state], ["ambiguous", 2, "unknown"], "two matching 0.00 payments → ambiguous, job stays unknown");
  // ⑧ void — ① 의 7001(Id · SyncToken · sparse → update&include=void · 길은 /payment · done 7 인자 · voided_at · Balance · RemainingCredit 되돌림) · SyncToken 없음 → GET payment 먼저 · 5010 → -2 · 거부 → failed · 5xx → unknown → not_voided → Voided 면 done · Id 없음 failed
  const v1 = addCaVoid(w, "CR-01008 → 60301", "7001", "0"); const nv1 = payVoidPosts(w).length;
  const bv1 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply_void"] }));
  const vp = payVoidPosts(w).slice(nv1);
  eq([bv1.sent, vp.length, JSON.parse(vp[0].body), new URL(vp[0].url).pathname.endsWith("/payment"), new URL(vp[0].url).searchParams.get("requestid"), v1.state, w.db.txns.get("ca-CR-01008 → 60301")!.voided_at !== null, q1.voided, q1.TotalAmt, q1.Line.length, q1.PrivateNote.startsWith("Voided - "), w.it.invoices.get("6101")!.Balance, w.it.invoices.get("6201")!.RemainingCredit],
     [1, 1, { Id: "7001", SyncToken: "0", sparse: true }, true, v1.request_id, "sent", true, true, 0, 0, true, 14.67, 13.52], "void via payment?operation=update&include=void · invoice balance and credit memo RemainingCredit restored (C-6)");
  const v2 = addCaVoid(w, "CR-01013 → 60306", "7904", null); const pr2 = payReads(w).length;
  const bv2 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply_void"] }));
  eq([bv2.sent, payReads(w).length - pr2, v2.state, (v2.last_error ?? "").includes("SyncToken read from QuickBooks before voiding"), w.it.payments.get("7904")!.voided], [1, 1, "sent", true, true], "no SyncToken → GET payment first, then void");
  ledgerInv(w, "6107", "60307"); ledgerCm(w, "6207", "CR-01015", 20);
  const a14 = addCa(w, "CR-01015 → 60307", "6107", "60307", "6207", "CR-01015", 2);
  await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] }));
  const q14 = w.it.payments.get(String(a14.qbo_id))!; q14.SyncToken = 3;
  const v3 = addCaVoid(w, "CR-01015 → 60307", q14.Id, "0"); const nv3 = payVoidPosts(w).length;
  const bv3 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply_void"] }));
  const p3v = payVoidPosts(w).slice(nv3);
  eq([a14.state, bv3.sent, p3v.length, JSON.parse(p3v[1].body).SyncToken, new URL(p3v[1].url).searchParams.get("requestid"), v3.state, (v3.last_error ?? "").includes("stale SyncToken (5010)"), q14.voided], ["sent", 1, 2, "3", v3.request_id + "-2", "sent", true, true], "stale → re-read → second try with -2");
  ledgerInv(w, "6108", "60308"); ledgerCm(w, "6208", "CR-01016", 20);
  const a15 = addCa(w, "CR-01016 → 60308", "6108", "60308", "6208", "CR-01016", 2);
  await body(await send(w, "JWT-MGR", { kinds: ["credit_apply"] }));
  const q15 = w.it.payments.get(String(a15.qbo_id))!; w.it.voidRefuse.add(q15.Id);
  const v4 = addCaVoid(w, "CR-01016 → 60308", q15.Id, "0");
  const bv4 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply_void"] }));
  eq([bv4.failed, v4.state, (v4.last_error ?? "").includes("code 6000"), q15.voided, w.db.txns.get("ca-CR-01016 → 60308")!.voided_at], [1, "failed", true, false, null], "refused void → failed, ledger untouched: " + v4.last_error);
  w.it.voidRefuse.delete(q15.Id);
  const v5 = addCaVoid(w, "CR-01016 → 60308", q15.Id, "1");
  w.it.override.push((h) => h.method === "POST" && new URL(h.url).searchParams.get("include") === "void" ? jres(502, {}, "tid-502") : null);
  const bv5 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply_void"] })); w.it.override.length = 0;
  eq([bv5.unknown, v5.state, v5.qbo_name], [1, "unknown", q15.Id], "void 5xx → unknown with the payment id");
  const bv6 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply_void"] }));
  const rv6 = (bv6.resolved as Record<string, unknown>[]).find((x) => x.job_id === v5.id)!;
  eq([rv6.result, v5.state], ["not_voided", "unknown"], "0.00 payment that is not marked Voided → not_voided (amount alone does not prove the void)");
  q15.TotalAmt = 0; q15.UnappliedAmt = 0; q15.Line = []; q15.voided = true; q15.PrivateNote = "Voided - " + q15.PrivateNote; q15.SyncToken = 2;
  const bv7 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply_void"] }));
  const rv7 = (bv7.resolved as Record<string, unknown>[]).find((x) => x.job_id === v5.id)!;
  eq([rv7.result, v5.state, w.db.txns.get("ca-CR-01016 → 60308")!.voided_at !== null, (v5.last_error ?? "").includes("voided (amount 0)")], ["found", "sent", true, true], "Voided note + amount 0 → done");
  const v6 = addCaVoid(w, "CR-01017 → 60309", null, null);
  const bv8 = await body(await send(w, "JWT-MGR", { kinds: ["credit_apply_void"] }));
  eq([bv8.failed, v6.state, (v6.last_error ?? "").startsWith("not sent — no QuickBooks payment id")], [1, "failed", true], "void job without id → failed");
  // ⑨ cron 62 꼴 kinds 넷(결제 + 붙임 한 호출) · 골라 보내기(job_ids): void 일감에 blocked 된 붙임을 홀로 고르면 그 void 를 대신 보내지 않는다(960 · 1013 · 이견 5)
  ledgerInv(w, "6109", "60309"); ledgerCm(w, "6209", "CR-01018", 20);
  const a16 = addCa(w, "CR-01018 → 60309", "6109", "60309", "6209", "CR-01018", 3);
  const p16 = addPay(w, "CHQ 16", [{ inv: "6109", doc: "60309", amt: 1 }], 1);
  const rc = await postBody(w, { action: "send", kinds: ["payment", "payment_void", "credit_apply", "credit_apply_void"], limit: 9 }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" });
  const bc = await body(rc);
  eq([rc.status, bc.kinds, bc.sent, bc.failed, a16.state, p16.state, w.db.claimKinds.at(-1)], [200, ["payment", "payment_void", "credit_apply", "credit_apply_void"], 2, 0, "sent", "sent", ["payment", "payment_void", "credit_apply", "credit_apply_void"]], "cron 62 with four kinds: a payment and a credit application in one round");
  const vq = addCaVoid(w, "CR-01018 → 60309", String(a16.qbo_id), "0");                                    // 열린 void(queued) — 붙임 다음 장이 1013 으로 그 뒤에 선다
  const a17 = addCa(w, "CR-01019 → 60309", "6109", "60309", "6209", "CR-01018", 1, { wait_job: vq.id });
  const uid17 = "2e2e2e2e-0000-4000-8000-" + String(Number(a17.id.replace("job-", ""))).padStart(12, "0"); w.db.jobs.delete(a17.id); a17.id = uid17; w.db.jobs.set(uid17, a17);
  const nvq = payVoidPosts(w).length;
  const bp = await body(await postBody(w, { action: "send", job_ids: [uid17] }, "JWT-MGR"));
  const rq = (bp.requested as Record<string, unknown>[])[0];
  eq([bp.mode, rq.result, a17.state, a17.blocked_by, vq.state, payVoidPosts(w).length - nvq, (bp.needs as unknown[]).length, bp.stopped], ["selected", "blocked", "blocked", vq.id, "queued", 0, 0, "no_progress"], "picked credit application waits for the void; the void is not sent on its behalf: " + JSON.stringify(rq));
  writesAllowedOnly(w, "㉓"); noLeak(w, "㉓");
  ok(!JSON.stringify({ logs: w.logs, warns: w.warns }).includes("ZZPII"), "no PII in logs");
});

// ── qbo-sync-2e-1d-2(2026-11-06 · deferred 452 · DB 1d-1 20261105184613) — 이월 인보이스 짝 시험 장치: 가짜 QBO 장부에 이월 인보이스(CustomerRef 에 name · GET 은 BillAddr · BillEmail 이 그대로 온다) · 가짜 DB 의 이월 목록 ──
let openN = 0;
const ledgerOpen = (w: World, doc: string, extra: Partial<Inv> = {}): Inv => { const id = String(8000 + (++openN)); const v: Inv = { Id: id, DocNumber: doc, SyncToken: 2, TotalAmt: 113, TotalTax: 13, voided: false, CustomerRef: { value: "7190", name: "ZZPII Customer" }, Balance: 113, ...extra }; w.it.invoices.set(id, v); return v; };
const imsOpen = (w: World, doc: string, match: OpeningInv["match"] = "none", warn: string | null = null): OpeningInv => { const x: OpeningInv = { invoice_id: "1d1d1d1d-0000-4000-8000-" + doc.padStart(12, "0"), invoice_number: doc, match, reason: null, warning: null, warn }; w.db.opening.list.push(x); return x; };
const openQueries = (w: World) => queryHits(w).filter((h) => /DocNumber\s+in\s*\(/i.test(sentQuery(h) ?? ""));
const numsOf = (h: Hit): string[] => [...(sentQuery(h) ?? "").matchAll(/'((?:[^']|'')*)'/g)].map((m) => m[1]);
const openReads = (w: World) => apiHits(w).filter((h) => h.method === "GET" && /\/invoice\/\d+\?/.test(h.url));
const cands = (w: World, jwt: string | null = "JWT-MGR", extra: Record<string, unknown> = {}) => postBody(w, { action: "opening_candidates", ...extra }, jwt);
const SEVEN_KEYS = ["Id", "SyncToken", "DocNumber", "TxnDate", "TotalAmt", "Balance", "CustomerRef"];
function noPii(w: World, texts: string[], where: string) {
  const all = JSON.stringify({ logs: w.logs, warns: w.warns, texts });
  ok(!all.includes("ZZPII"), where + ": customer name · address · email leaked: " + all.slice(all.indexOf("ZZPII") - 120, all.indexOf("ZZPII") + 60));
}

Deno.test("㉔ 이월 인보이스 짝(qbo-sync-2e-1d-2 · deferred 452) — 순수(ACTIONS · KEY_ACTIONS 셋 · 묶음 상수 · 조회 글 parseQuery 통과 · openingSlim 일곱 칸 · CustomerRef {value}) · 문(열쇠 없음 403 · qbo:read 403 · 열쇠 없는 admin 403 · cron 400 · 세션 없음 401 · 거부 전 Intuit · 목록 0) · 번호 5 · QBO 행 5 → 조회 1 · RPC 1(p_doc_numbers 5 · p_rows 5 · 일곱 칸 · name 없음) · 짝 선 장은 안 묻는다 · invoice_numbers 교집합(꾸민 번호 ignored) · 250 → 묶음 수 · ∪ = 250 · batch 60 · 한도 밖 400 · QBO 503 한 묶음만 실패 · DB 실패 한 묶음만(기록 ok=false http_status null) · 쪽 가득 too_many_rows(RPC 0) · 예산 not_run · QBO 에 없는 번호(2329611 꼴) → p_rows 에 없음 · p_doc_numbers 에 있음 · not_found · opening_read(peek 쓰기 0 · 줄인 행 · 경고 + ack 없음 → DB 글 그대로 422 · ack → matched · 610 → 404 · 입력 400) · opening_search(입력 400 · like · 줄인 행) · 기록 detail(q 리터럴 → ? · 결과 행 없음) · API 호스트에 GET 만 · 이름 · 주소 · 이메일 · 토큰 0", async () => {
  // ⓪ 순수
  eq([...ACTIONS].sort(), ["status", ...ADMIN_ACTIONS, ...KEY_ACTIONS].sort(), "ACTIONS = status + ADMIN + KEY");
  ok((KEY_ACTIONS as readonly string[]).includes("opening_candidates") && (KEY_ACTIONS as readonly string[]).includes("opening_read") && (KEY_ACTIONS as readonly string[]).includes("opening_search") && !(ADMIN_ACTIONS as readonly string[]).some((a) => a.startsWith("opening_")), "opening_* are key actions, not admin");
  ok(OPENING_BATCH_DEFAULT >= 1 && OPENING_BATCH_DEFAULT <= OPENING_BATCH_MAX && OPENING_BATCH_MAX <= 150, "batch default within max ≤ 150");
  const worst = Array.from({ length: OPENING_BATCH_MAX }, (_, i) => String(2000000 + i));                 // 7 자리 150 개 — 2000 자 한도 안
  const pw = parseQuery(openingQueryText(worst));
  eq([pw.entity, pw.maxResults, openingQueryText(worst).length <= 2000], ["Invoice", MAXRESULTS_MAX, true], "worst-case batch query passes parseQuery: " + openingQueryText(worst).length + " chars");
  eq(openingQueryText(["50763", "O'1"]), "select Id, SyncToken, DocNumber, TxnDate, TotalAmt, Balance, CustomerRef from Invoice where DocNumber in ('50763', 'O''1') MAXRESULTS 1000", "query text · quotes doubled");
  eq(parseQuery(openingSearchQueryText("ITRA6260")).maxResults, OPENING_SEARCH_MAX, "search text passes parseQuery");
  eq(openingSlim({ Id: 7, SyncToken: 3, DocNumber: " 50763 ", TxnDate: "2026-10-15", TotalAmt: "113.00", Balance: 113, CustomerRef: { value: "7190", name: "ZZPII" }, BillAddr: { Line1: "ZZPII" }, Line: [{ Description: "ZZPII" }], CustomerMemo: { value: "ZZPII" } }),
    { Id: "7", SyncToken: "3", DocNumber: "50763", TxnDate: "2026-10-15", TotalAmt: 113, Balance: 113, CustomerRef: { value: "7190" } }, "openingSlim: seven fields · CustomerRef {value} only · numbers as numbers");
  eq([openingSlim(null), openingSlim({ DocNumber: "x" }), openingSlim({ Id: "1" })], [null, null, { Id: "1", SyncToken: null, DocNumber: null, TxnDate: null, TotalAmt: null, Balance: null, CustomerRef: { value: null } }], "openingSlim: no Id → null · missing fields → null");
  eq([...OPENING_REASONS], ["not_found", "many", "unlinked", "customer", "total", "balance", "docnumber", "taken"], "reason keys = DB review reasons");
  // ① 문 — 열쇠 없는 manager · qbo:read · 열쇠 없는 admin · cron · 세션 없음 · Intuit 0 · 목록 0
  const w = world(); connect(w);
  w.db.keys["JWT-MGR"] = null;
  for (const a of ["opening_candidates", "opening_read", "opening_search"]) {
    const r = await postBody(w, { action: a, qbo_id: "8001", invoice_id: "1d1d1d1d-0000-4000-8000-000000050763", doc_like: "50763" }, "JWT-MGR");
    eq([a, r.status, String((await body(r)).error)], [a, 403, "Your account does not have the 'qbo' (write) permission — ask an admin to switch it on in Staff — nothing was changed"], "no key → 403: " + a);
  }
  w.db.keys["JWT-MGR"] = "qbo:read";
  const rr = await cands(w);
  eq([rr.status, String((await body(rr)).error).includes("'qbo' (write)")], [403, true], "qbo:read → 403");
  w.db.keys["JWT-ADMIN"] = null;
  eq((await cands(w, "JWT-ADMIN")).status, 403, "admin without the key → 403 (945)");
  w.db.keys["JWT-ADMIN"] = "qbo";
  const rc = await cands(w, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" });
  eq((await postBody(w, { action: "opening_candidates" }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" })).status, 400, "cron path → 400"); void rc;
  eq((await cands(w, "JWT-BAD")).status, 401, "unknown session → 401");
  eq([apiHits(w).length, w.db.calls.filter((x) => x.startsWith("user:qbo_opening")).length], [0, 0], "refused: no Intuit call · no opening RPC");
  // ② 번호 5 · QBO 행 5 → 조회 1 · RPC 1 · 일곱 칸 · 짝 선 장(auto)은 안 묻는다
  w.db.keys["JWT-MGR"] = "qbo";
  for (const d of ["50763", "50764", "50765", "50766", "50767"]) { ledgerOpen(w, d); imsOpen(w, d); }
  imsOpen(w, "50700", "auto"); w.db.opening.held.set("50700", "7999");                                  // 이미 선 장
  const r2 = await cands(w);
  const t2 = await r2.text(), b2 = JSON.parse(t2) as Record<string, unknown>;
  const tot2 = b2.totals as Record<string, number>;
  eq([r2.status, b2.ok, b2.asked, b2.open, b2.ignored, b2.not_run, b2.batch, (b2.batches as unknown[]).length, tot2.batches_failed, tot2.matched, tot2.qbo_rows, tot2.qbo_missing, (b2.rows as unknown[]).length], [200, true, 5, 5, [], 0, OPENING_BATCH_DEFAULT, 1, 0, 5, 5, 0, 5], "five numbers · one batch · five matched: " + t2);
  eq(openQueries(w).length, 1, "one QuickBooks query");
  eq(numsOf(openQueries(w)[0]).sort(), ["50763", "50764", "50765", "50766", "50767"], "the matched invoice 50700 was not asked");
  ok((sentQuery(openQueries(w)[0]) ?? "").startsWith("select Id, SyncToken, DocNumber, TxnDate, TotalAmt, Balance, CustomerRef from Invoice where DocNumber in ('"), "query fields · in (…)");
  eq(w.db.opening.cands.length, 1, "one RPC");
  const c1 = w.db.opening.cands[0];
  eq([c1.numbers.length, c1.rows.length, c1.rows.every((r) => Object.keys(r).sort().join() === [...SEVEN_KEYS].sort().join()), c1.rows.every((r) => Object.keys(r.CustomerRef as object).join() === "value")], [5, 5, true, true], "p_doc_numbers 5 · p_rows 5 · seven fields · CustomerRef {value}");
  eq(w.db.opening.list.filter((x) => x.match === "auto").length, 6, "five newly matched + the earlier one");
  ok(!t2.includes("\n"), "compact JSON");
  const l2 = w.logs.filter((l) => l.action === "opening_candidates");
  eq([l2.length, l2[0].ok, l2[0].http_status, l2[0].by_staff, l2[0].detail?.batch, l2[0].detail?.numbers, l2[0].detail?.rows, l2[0].detail?.totalCount], [1, true, 200, STAFF_MGR, 1, 5, 5, 5], "log row per batch: " + JSON.stringify(l2[0]));
  eq(l2[0].detail?.q, "select Id, SyncToken, DocNumber, TxnDate, TotalAmt, Balance, CustomerRef from Invoice where DocNumber in (?, ?, ?, ?, ?) MAXRESULTS 1000", "log q: literals → ?");
  ok(!JSON.stringify(l2).includes("50763"), "log carries no invoice numbers · no rows");
  // 다시 돌리면 already · 변화 0
  const b2b = await body(await cands(w));
  eq([(b2b.totals as Record<string, number>).already, (b2b.totals as Record<string, number>).matched, b2b.asked], [0, 0, 0], "second run: nothing open → asked 0 · no query");
  eq(openQueries(w).length, 1, "no new QuickBooks query when nothing is open");
  // ③ invoice_numbers 교집합 — 꾸민 번호 · 이미 선 장은 ignored · 빈 배열 400
  ledgerOpen(w, "50768"); imsOpen(w, "50768"); imsOpen(w, "50769");
  const b3 = await body(await cands(w, "JWT-MGR", { invoice_numbers: ["50768", "99999999", "50700"] }));
  eq([b3.asked, b3.ignored, (b3.totals as Record<string, number>).matched, numsOf(openQueries(w).at(-1)!)], [1, ["99999999", "50700"], 1, ["50768"]], "only the open number is asked; fabricated · matched numbers are ignored");
  eq((await postBody(w, { action: "opening_candidates", invoice_numbers: [] }, "JWT-MGR")).status, 400, "empty invoice_numbers → 400");
  eq((await postBody(w, { action: "opening_candidates", invoice_numbers: [5] }, "JWT-MGR")).status, 400, "non-string invoice_numbers → 400");
  // ④ QBO 에 없는 번호(2329611 꼴: QBO DocNumber 가 「2329611 | ITRA6260-1」) → p_rows 에 없음 · p_doc_numbers 에 있음 · not_found · missing_numbers
  ledgerOpen(w, "2329611 | ITRA6260-1"); imsOpen(w, "2329611");
  const b4 = await body(await cands(w));
  const c4 = w.db.opening.cands.at(-1)!;
  eq([b4.asked, c4.numbers, c4.rows.length, (b4.totals as Record<string, number>).qbo_missing, b4.missing_numbers, (b4.reasons as Record<string, number>).not_found, (b4.totals as Record<string, number>).review_changed, ((b4.rows as Record<string, unknown>[])[0] ?? {}).reason], [2, ["50769", "2329611"], 0, 2, ["50769", "2329611"], 2, 2, "not_found"], "not in QuickBooks → asked but no row · review not_found: " + JSON.stringify(b4));
  const b4b = await body(await cands(w));
  eq([(b4b.totals as Record<string, number>).review_same, (b4b.totals as Record<string, number>).review_changed], [2, 0], "same result again → review_same (idempotent)");
  // ⑤ 250 번호 → 묶음 수 · ∪ = 250 · batch 60 → 5 묶음 · 한도 밖 400
  const w5 = world(); connect(w5); w5.db.keys["JWT-MGR"] = "qbo";
  const all250: string[] = [];
  for (let i = 0; i < 250; i++) { const d = String(40000 + i); all250.push(d); ledgerOpen(w5, d); imsOpen(w5, d); }
  const b5 = await body(await cands(w5));
  const nb = Math.ceil(250 / OPENING_BATCH_DEFAULT);
  const union = new Set(openQueries(w5).flatMap(numsOf));
  eq([b5.asked, (b5.batches as unknown[]).length, openQueries(w5).length, w5.db.opening.cands.length, union.size, (b5.totals as Record<string, number>).matched, (b5.totals as Record<string, number>).batches_failed], [250, nb, nb, nb, 250, 250, 0], "250 numbers → " + nb + " batches · union 250 · all matched");
  ok(openQueries(w5).every((h) => numsOf(h).length <= OPENING_BATCH_DEFAULT), "every batch ≤ default");
  eq(w5.db.opening.cands.map((c) => c.numbers.length).reduce((a, b) => a + b, 0), 250, "RPC numbers sum 250");
  for (const x of w5.db.opening.list) x.match = "none"; w5.db.opening.held.clear();
  const b5b = await body(await cands(w5, "JWT-MGR", { batch: 60 }));
  eq([b5b.batch, (b5b.batches as unknown[]).length, (b5b.batches as Record<string, number>[]).map((b) => b.numbers)], [60, 5, [60, 60, 60, 60, 10]], "batch 60 → 5 batches");
  for (const bad of [0, 151, 1.5, "x"]) eq((await postBody(w5, { action: "opening_candidates", batch: bad }, "JWT-MGR")).status, 400, "batch out of range → 400: " + bad);
  // ⑥ QBO 503 한 묶음(재시도 1 뒤 실패) → 그 묶음만 intuit_failed · 나머지 진행 · DB 실패 한 묶음 → db_failed + 기록 ok=false http_status null
  for (const x of w5.db.opening.list) x.match = "none"; w5.db.opening.held.clear(); w5.db.opening.cands = [];
  let hit = 0;
  w5.it.override.push((h) => /DocNumber\s+in/i.test(sentQuery(h) ?? "") && ++hit >= 2 && hit <= 3 ? jres(503, { Fault: { Error: [{ Message: "Service Unavailable", code: "503" }], type: "SystemFault" } }, "tid-503") : null);   // 2 번째 묶음의 두 시도(첫 + 재시도)
  w5.db.opening.failCall = 3;                                                                        // 3 번째 RPC(= 4 번째 묶음 · 2 번째 묶음은 RPC 를 안 부른다)
  const b6 = await body(await cands(w5, "JWT-MGR", { batch: 60 }));
  const bs6 = b6.batches as Record<string, unknown>[];
  eq([bs6.map((b) => b.status), (b6.totals as Record<string, number>).batches_failed, (b6.totals as Record<string, number>).numbers_failed, (b6.totals as Record<string, number>).matched, w5.db.opening.cands.length], [["ok", "intuit_failed", "ok", "db_failed", "ok"], 2, 120, 130, 4], "one Intuit failure · one DB failure · the rest matched: " + JSON.stringify(bs6));
  ok(String(bs6[1].error).startsWith("QuickBooks opening_candidates failed — HTTP 503"), "intuit error text: " + bs6[1].error);
  eq(String(bs6[3].error), "canceling statement due to statement timeout", "db error text as-is");
  const l6 = w5.logs.filter((l) => l.action === "opening_candidates" && !l.ok);
  eq([l6.length, l6[0].http_status, l6[1].http_status, l6[1].error, l6[1].by_staff, l6[1].detail?.db, l6[1].detail?.batch], [2, 503, null, "canceling statement due to statement timeout", STAFF_MGR, true, 4], "two failed log rows: Intuit 503 · DB (http_status null): " + JSON.stringify(l6));
  w5.it.override.pop(); w5.db.opening.failCall = null;
  // ⑦ 쪽 가득(행 ≥ 1000) → too_many_rows · RPC 0 · 예산 넘김 → not_run
  const w7 = world(); connect(w7); w7.db.keys["JWT-MGR"] = "qbo";
  for (let i = 0; i < 3; i++) { ledgerOpen(w7, String(41000 + i)); imsOpen(w7, String(41000 + i)); }
  w7.it.override.push((h) => /DocNumber\s+in/i.test(sentQuery(h) ?? "") ? jres(200, { QueryResponse: { Invoice: Array.from({ length: 1000 }, (_, i) => ({ Id: String(90000 + i), DocNumber: "41000", SyncToken: "0", TotalAmt: 1, Balance: 1, CustomerRef: { value: "1", name: "ZZPII" } })), startPosition: 1, maxResults: 1000 } }, "tid-full") : null);
  const b7 = await body(await cands(w7));
  eq([(b7.batches as Record<string, unknown>[])[0].status, w7.db.opening.cands.length, (b7.totals as Record<string, number>).batches_failed], ["too_many_rows", 0, 1], "full page → too_many_rows · RPC not called: " + JSON.stringify(b7.batches));
  w7.it.override.pop();
  w7.it.override.push((h) => { if (/DocNumber\s+in/i.test(sentQuery(h) ?? "")) w7.clock.t += OPENING_BUDGET_MS + 1000; return null; });
  const b7b = await body(await cands(w7, "JWT-MGR", { batch: 2 }));
  eq([(b7b.batches as unknown[]).length, b7b.not_run, (b7b.totals as Record<string, number>).matched], [1, 1, 2], "budget exceeded after batch 1 → the rest not_run");
  w7.it.override.pop();
  // ⑧ opening_read — 입력 400 · peek(쓰기 0 · 줄인 행 · BillAddr · name 없음) · 경고 + ack 없음 → DB 글 그대로 422 · ack → matched · 다른 장이 쥔 Id 거부 · 610 → 404
  const w8 = world(); connect(w8); w8.db.keys["JWT-MGR"] = "qbo";
  const q1 = ledgerOpen(w8, "2329611 | ITRA6260-1"); const i1 = imsOpen(w8, "2329611");
  const q2 = ledgerOpen(w8, "50780"); const i2 = imsOpen(w8, "50780", "none", "QuickBooks balance 0 differs from what IMS expects (113)");
  eq((await postBody(w8, { action: "opening_read", qbo_id: "abc", invoice_id: i1.invoice_id }, "JWT-MGR")).status, 400, "qbo_id not a number → 400");
  eq((await postBody(w8, { action: "opening_read", qbo_id: q1.Id, invoice_id: "nope" }, "JWT-MGR")).status, 400, "invoice_id not a uuid → 400");
  eq((await postBody(w8, { action: "opening_read", qbo_id: q1.Id, invoice_id: i1.invoice_id, ack: "yes" }, "JWT-MGR")).status, 400, "ack not boolean → 400");
  eq(openReads(w8).length, 0, "no Intuit call for refused input");
  const rp = await postBody(w8, { action: "opening_read", qbo_id: q1.Id, peek: true }, "JWT-MGR");
  const tp = await rp.text(), bp = JSON.parse(tp) as Record<string, unknown>;
  eq([rp.status, bp.ok, bp.peek, bp.qbo_id, Object.keys(bp.row as object).sort(), (bp.row as Record<string, unknown>).DocNumber, ((bp.row as Record<string, unknown>).CustomerRef as Record<string, unknown>), bp.intuit_tid, w8.db.opening.matches.length], [200, true, true, q1.Id, [...SEVEN_KEYS].sort(), "2329611 | ITRA6260-1", { value: "7190" }, "tid-inv-" + q1.Id, 0], "peek: slim row · no write: " + tp);
  ok(!tp.includes("ZZPII") && !tp.includes("BillAddr"), "peek response has no address · email · name");
  eq([w8.logs.at(-1)!.action, w8.logs.at(-1)!.detail?.entity, w8.logs.at(-1)!.detail?.id, w8.logs.at(-1)!.detail?.rows, w8.logs.at(-1)!.detail?.peek], ["opening_read", "Invoice", q1.Id, 1, true], "read log row");
  const rm = await postBody(w8, { action: "opening_read", qbo_id: q1.Id, invoice_id: i1.invoice_id }, "JWT-MGR");
  const bm = await body(rm);
  eq([rm.status, bm.ok, bm.error, w8.db.opening.matches.length], [422, false, `QuickBooks Invoice #${q1.Id} does not look like IMS invoice 2329611: QuickBooks invoice #${q1.Id} is numbered "2329611 | ITRA6260-1", not 2329611 — confirm to match it anyway — nothing was saved`, 0], "warning without ack → DB refusal text as-is (422)");
  const rm2 = await postBody(w8, { action: "opening_read", qbo_id: q1.Id, invoice_id: i1.invoice_id, ack: true }, "JWT-MGR");
  const tm2 = await rm2.text(), bm2 = JSON.parse(tm2) as Record<string, unknown>;
  eq([rm2.status, bm2.ok, bm2.result, bm2.match_how, bm2.acked, bm2.qbo_id, bm2.invoice_id, i1.match, w8.db.opening.matches.length, Object.keys(w8.db.opening.matches[0].row).sort()], [200, true, "matched", "manual", true, q1.Id, i1.invoice_id, "manual", 1, [...SEVEN_KEYS].sort()], "ack → matched manual · RPC got the slim row: " + tm2);
  ok(!tm2.includes("ZZPII"), "match response has no name");
  const rm3 = await postBody(w8, { action: "opening_read", qbo_id: q1.Id, invoice_id: i2.invoice_id, ack: true }, "JWT-MGR");
  eq([rm3.status, String((await body(rm3)).error)], [422, `QuickBooks Invoice #${q1.Id} is already matched to IMS invoice 2329611 — unmatch that one first — nothing was saved`], "Id held by another IMS invoice → refused as-is");
  const rm4 = await postBody(w8, { action: "opening_read", qbo_id: q2.Id, invoice_id: i2.invoice_id }, "JWT-MGR");
  eq([rm4.status, String((await body(rm4)).error).includes("QuickBooks balance 0 differs")], [422, true], "DB warning (balance) without ack → refused");
  const rm5 = await body(await postBody(w8, { action: "opening_read", qbo_id: q2.Id, invoice_id: i2.invoice_id, ack: true }, "JWT-MGR"));
  eq([rm5.result, rm5.acked, String(rm5.warning).includes("balance 0 differs")], ["matched", true, true], "ack → matched with the warning kept");
  const r404 = await postBody(w8, { action: "opening_read", qbo_id: "99999", peek: true }, "JWT-MGR");
  eq([r404.status, String((await body(r404)).error)], [404, "QuickBooks has no Invoice #99999 — check the Id"], "Fault 610 → 404");
  eq([w8.logs.at(-1)!.ok, w8.logs.at(-1)!.http_status, w8.logs.at(-1)!.detail?.rows], [false, 404, 0], "failed read logged");
  let deny8 = 1;
  w8.it.override.push((h) => /\/invoice\/\d+\?/.test(h.url) && deny8-- > 0 ? jres(401, { Fault: { Error: [{ Message: "AuthenticationFailed", code: "3200" }], type: "AUTHENTICATION" } }, "tid-401") : null);
  const v8 = w8.db.conn!.token_version;
  const r401 = await postBody(w8, { action: "opening_read", qbo_id: q2.Id, peek: true }, "JWT-MGR");
  eq([r401.status, w8.db.conn!.token_version], [200, v8 + 1], "401 once → refresh → again (withAuthRetry)");
  w8.it.override.pop();
  // ⑨ opening_search — 입력 400 · like · 줄인 행 · 기록 q
  for (const bad of ["ab", "x".repeat(31), "50%", "O'1", "a;b", "", undefined]) eq((await postBody(w8, { action: "opening_search", doc_like: bad }, "JWT-MGR")).status, 400, "doc_like refused: " + JSON.stringify(bad));
  const rs = await postBody(w8, { action: "opening_search", doc_like: "ITRA6260" }, "JWT-MGR");
  const ts = await rs.text(), bs = JSON.parse(ts) as Record<string, unknown>;
  eq([rs.status, bs.ok, bs.doc_like, bs.count, bs.more, ((bs.rows as Record<string, unknown>[])[0]).Id, ((bs.rows as Record<string, unknown>[])[0]).DocNumber, Object.keys((bs.rows as Record<string, unknown>[])[0]).sort()], [200, true, "ITRA6260", 1, false, q1.Id, "2329611 | ITRA6260-1", [...SEVEN_KEYS].sort()], "search by part of the number: " + ts);
  ok(!ts.includes("ZZPII"), "search response has no name");
  eq(sentQuery(w8.it.hits.at(-1)!), "select Id, SyncToken, DocNumber, TxnDate, TotalAmt, Balance, CustomerRef from Invoice where DocNumber like '%ITRA6260%' MAXRESULTS 20", "like query text");
  eq([w8.logs.at(-1)!.action, w8.logs.at(-1)!.detail?.q, w8.logs.at(-1)!.detail?.rows], ["opening_search", "select Id, SyncToken, DocNumber, TxnDate, TotalAmt, Balance, CustomerRef from Invoice where DocNumber like ? MAXRESULTS 20", 1], "search log: literal → ?");
  const bs0 = await body(await postBody(w8, { action: "opening_search", doc_like: "nothing here" }, "JWT-MGR"));
  eq([bs0.count, bs0.rows], [0, []], "no hit → empty rows");
  // ⑩ 읽기만 · 누출 0
  for (const x of [w, w5, w7, w8]) { readOnlyOnly(x, "㉔"); noLeak(x, "㉔"); noPii(x, [], "㉔"); }
  ok(apiHits(w8).every((h) => h.method === "GET") && apiHits(w5).every((h) => h.method === "GET"), "opening_* never POSTs to the API host (token refresh is the OAuth host)");
});

// ── 2e-3-1b 이월 받아 둔 돈 붙임 장치 — 몸 넷은 DB qbo_opening_credit_body · qbo_opening_apply_body 꼴(11-07 운영 60172 → OC-60172-1 · 28.24 · Item 5624 Customer Credit · TaxCodeRef Out of Scope(Sale) · TaxLine 0 · CustomerMemo) · 한 붙임(so_payment_alloc.id)에 일감 넷이 같은 ims_id ──
const ocNoteOf = (n: number) => "2e3e3e3e-0000-4000-8000-" + String(n).padStart(12, "0");
const ocBody = (doc: string, inv: string, amt: number, uuid: string, cust = "9242", date = "2026-11-07"): Record<string, unknown> => ({
  DocNumber: doc, TxnDate: date, CustomerRef: { value: cust }, CurrencyRef: { value: "CAD" }, PrivateNote: "IMS opening credit used " + uuid, CustomerMemo: { value: "Credit on account applied to invoice " + inv }, GlobalTaxCalculation: "TaxExcluded",
  Line: [{ DetailType: "SalesItemLineDetail", LineNum: 1, Amount: amt, Description: "Credit on account applied to invoice " + inv, SalesItemLineDetail: { ItemRef: { value: "5624" }, Qty: 1, UnitPrice: amt, TaxCodeRef: { value: "4" } } }],
  TxnTaxDetail: { TotalTax: 0, TaxLine: [{ DetailType: "TaxLineDetail", Amount: 0, TaxLineDetail: { TaxRateRef: { value: "8" }, PercentBased: true, TaxPercent: 0, NetAmountTaxable: amt } }] } });
const addOc = (w: World, inv: string, n: number, amt: number, extra: Partial<Job> = {}) => {
  const uuid = ocNoteOf(jobN + 1), doc = `OC-${inv}-${n}`;
  return addJob(w, { kind: "opening_credit", ims_id: "oa-" + uuid, name: `${doc} → ${inv}`, doc_number: doc, totals: { total: amt, tax: 0 }, body: ocBody(doc, inv, amt, uuid), ...extra });
};
const addOcVoid = (w: World, c: Job, id: string | null, syncToken: string | null) => addJob(w, { kind: "opening_credit_void", ims_id: c.ims_id, name: c.name, doc_number: c.doc_number, body: id ? (syncToken !== null ? { Id: id, SyncToken: syncToken } : { Id: id }) : {} });
const addOa = (w: World, c: Job, invId: string, invDoc: string, cmId: string, amt: number, extra: Partial<Job> = {}) => {
  const uuid = c.ims_id.slice(3), note = "IMS opening credit applied " + uuid, doc = String(c.doc_number);
  return addJob(w, { kind: "opening_apply", ims_id: c.ims_id, name: c.name, doc_number: c.name, body: caBody(invId, cmId, amt, note, "9242", "2026-11-07"),
    check_lines: [{ txn_type: "Invoice", invoice_number: invDoc, qbo_invoice_id: invId, amount: amt }, { txn_type: "CreditMemo", credit_number: doc, qbo_creditmemo_id: cmId, amount: amt }],
    lookup: { customer_ref: "9242", txn_date: "2026-11-07", total_amt: 0, private_note: note }, pay_totals: { amount: 0, unapplied: 0 }, ...extra });
};
const addOaVoid = (w: World, c: Job, id: string | null, syncToken: string | null) => addJob(w, { kind: "opening_apply_void", ims_id: c.ims_id, name: c.name, doc_number: c.name, body: id ? (syncToken !== null ? { Id: id, SyncToken: syncToken, sparse: true } : { Id: id, sparse: true }) : {} });
const oaKeyOf = (j: Job) => String(((j.body.PrivateNote ?? "") as string)) + "|9242|2026-11-07|0";
const ocDocQueries = (w: World) => cmDocQueries(w).filter((h) => /OC-/.test(sentQuery(h) ?? ""));

Deno.test("㉕ 이월 받아 둔 돈의 붙임 = 「쓰기」 CreditMemo + 0 원 Payment 보내기 · void 둘(qbo-sync-2e-3-1b · 판정 998′ · 1009 · 1011 ~ 1013 · 이견 1 ~ 10) — 순수(SEND_KINDS 14 · OPENING_CREDIT_KINDS · OPENING_APPLY_KINDS · TXN_KINDS · CREDIT_APPLY_KINDS 무변 · parsePaymentKey 접두 셋 · kindsOf 여덟 · 모르는 값 400) · ① opening_credit: DocNumber 조회 from CreditMemo → POST creditmemo(몸 그대로) → done(TotalAmt = 금액 · TotalTax 0) → blocked 였던 opening_apply 가 풀려 가드 둘 → POST payment 0 원 → done · ② 이미 있음 · 6140 · 5xx unknown → DocNumber 풀기 · ③ 세금 mismatch · TotalTax 없음(이견 7) · ④ apply 가드(Balance · RemainingCredit · 못 읽음 · check_lines) · 4xx · 5xx unknown → 풀기 0 · 1 · 2(완전 일치 · Voided 제외) · ⑤ void 둘(apply_void 먼저 → credit_void · SyncToken 없음 · 5010 · 거부 · 5xx → not_voided → done) · ⑥ cron 62 kinds 8 · ⑦ 골라 보내기 두 호출(첫 실물 꼴) · 쓰기 꼴 · 누출 0", async () => {
  // ⓪ 순수
  eq([[...SEND_KINDS].length, [...OPENING_CREDIT_KINDS], [...OPENING_APPLY_KINDS], [...TXN_KINDS], [...CREDIT_APPLY_KINDS], [...PAYMENT_KINDS]],
     [19, ["opening_credit", "opening_credit_void"], ["opening_apply", "opening_apply_void"], ["invoice", "invoice_void", "credit", "credit_void"], ["credit_apply", "credit_apply_void"], ["payment", "payment_void"]], "SEND_KINDS 14 → 18 (2e-3-2-1b) → 19 (3-3) · new pairs · old arrays unchanged");
  const k0 = "IMS opening credit applied 2e3e3e3e-0000-4000-8000-000000000001|9242|2026-11-07|0";
  eq([parsePaymentKey(k0), parsePaymentKey("IMS opening credit used 2e3e|9242|2026-11-07|0"), parsePaymentKey("IMS credit applied x|9242|2026-11-07|0")?.totalAmt, parsePaymentKey("IMS payment x|7190|2026-11-02|10")?.totalAmt],
     [{ privateNote: "IMS opening credit applied 2e3e3e3e-0000-4000-8000-000000000001", customerRef: "9242", txnDate: "2026-11-07", totalAmt: 0 }, null, 0, 10], "payment key: third prefix · the CreditMemo note (used) is not a payment key · old prefixes unchanged");
  const EIGHT = ["payment", "payment_void", "credit_apply", "credit_apply_void", "opening_credit", "opening_credit_void", "opening_apply", "opening_apply_void"];
  eq(kindsOf(EIGHT), EIGHT, "kindsOf: the eight cron-62 kinds");
  for (const bad of [["opening_credit", "bogus"], ["opening_alloc"], ["Opening_Credit"], ["opening"]]) { let threw = false; try { kindsOf(bad); } catch (e) { threw = e instanceof QboError && e.status === 400; } ok(threw, "kindsOf refuses " + JSON.stringify(bad)); }

  const w = world(); connect(w); w.db.keys["JWT-MGR"] = "qbo";
  // ① 성공 — 인보이스 60172(QBO #6301 · 28.24 남음) · opening_credit OC-60172-1 → CreditMemo DocNumber 조회 1(0 행) → POST creditmemo 1(몸 그대로 · requestid · operation 없음) → done(TotalAmt 28.24 · TotalTax 0 · mismatch 없음) · blocked 였던 opening_apply 가 풀려 → GET invoice 1 · GET creditmemo 1 → POST payment 1(0 원 · 계좌 없음) → done · 장부 Balance 28.24 → 0 · RemainingCredit 28.24 → 0
  ledgerInv(w, "6301", "60172", 128.24, 28.24);
  const c1 = addOc(w, "60172", 1, 28.24);
  const a1 = addOa(w, c1, "6301", "60172", "", 28.24); a1.state = "blocked"; a1.blocked_by = c1.id;   // DB sync 가 세운 꼴(이견 2 · opening_apply blocked_by opening_credit) · CreditMemo Id 는 아직 모른다
  const b1 = await body(await send(w, "JWT-MGR", { kinds: ["opening_credit"] }));
  const cp = cmPosts(w);
  eq([b1.claimed, b1.sent, b1.failed, b1.unknown, b1.mismatch, b1.kinds, ocDocQueries(w).length, cp.length, cmReads(w).length, invoicePosts(w).length, payPosts(w).length, JSON.parse(cp[0].body), new URL(cp[0].url).pathname.endsWith("/creditmemo"), new URL(cp[0].url).searchParams.get("requestid"), new URL(cp[0].url).searchParams.get("operation")],
     [1, 1, 0, 0, 0, ["opening_credit"], 1, 1, 0, 0, 0, c1.body, true, c1.request_id, null], "one CreditMemo DocNumber check · one POST creditmemo with the DB body · no invoice · payment write: " + JSON.stringify(b1.jobs));
  eq(sentQuery(ocDocQueries(w)[0]) ?? "", "select Id, DocNumber, SyncToken, TotalAmt from CreditMemo where DocNumber = 'OC-60172-1' MAXRESULTS 100", "DocNumber check from CreditMemo (not Invoice)");
  const t1 = w.db.txns.get(c1.ims_id)!, cm1 = w.it.invoices.get(String(c1.qbo_id))!;
  eq([c1.state, c1.qbo_id, c1.qbo_name, t1.qbo_id, t1.doc_number, t1.total_amt, t1.total_tax, t1.mismatch, cm1.ent, cm1.TotalAmt, cm1.TotalTax, cm1.RemainingCredit ?? cm1.TotalAmt, a1.state, a1.blocked_by], ["sent", "5001", "OC-60172-1", "5001", "OC-60172-1", 28.24, 0, null, "CreditMemo", 28.24, 0, 28.24, "queued", c1.id], "done → txn opening_credit ↔ CreditMemo · totals match · opening_apply released to queued");
  const l1 = w.logs.filter((l) => l.action === "send" && l.detail?.job_id === c1.id);
  eq([l1.length, l1[0].detail?.qbo_id, l1[0].detail?.request_id, l1[0].detail?.kind, JSON.stringify(l1[0].detail).includes("Credit on account")], [1, "5001", c1.request_id, "opening_credit", false], "write logged with job · qbo id · requestid · no body");
  a1.check_lines![1].qbo_creditmemo_id = "5001"; (a1.body.Line as Record<string, unknown>[])[1].LinkedTxn = [{ TxnId: "5001", TxnType: "CreditMemo" }];   // DB 몸은 claim 때 qbo_txn 의 CreditMemo Id 를 넣는다 — 가짜는 여기서 채운다
  const ir0 = invReads(w).length, cr0 = cmReads(w).length, pr0 = payReads(w).length;
  const b2 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply"] }));
  const pp = payPosts(w);
  eq([b2.sent, b2.failed, b2.unknown, b2.kinds, invReads(w).length - ir0, cmReads(w).length - cr0, payReads(w).length - pr0, pp.length, JSON.parse(pp[0].body), new URL(pp[0].url).pathname.endsWith("/payment"), new URL(pp[0].url).searchParams.get("requestid"), new URL(pp[0].url).searchParams.get("operation")],
     [1, 0, 0, ["opening_apply"], 1, 1, 0, 1, a1.body, true, a1.request_id, null], "one invoice read, one credit memo read, one POST payment with the DB body: " + JSON.stringify(b2.jobs));
  const ta1 = w.db.txns.get(a1.ims_id + ":apply")!, q1 = w.it.payments.get(String(a1.qbo_id))!;
  eq([a1.state, a1.qbo_id, ta1.qbo_id, ta1.doc_number, ta1.total_amt, ta1.unapplied, ta1.total_tax, ta1.fingerprint, ta1.mismatch, w.it.invoices.get("6301")!.Balance, cm1.RemainingCredit, q1.TotalAmt, q1.UnappliedAmt, q1.DepositToAccountRef, q1.Line.length, q1.PrivateNote.startsWith("IMS opening credit applied ")],
     ["sent", "7002", "7002", "OC-60172-1 → 60172", 0, 0, null, null, null, 0, 0, 0, 0, undefined, 2, true], "done → txn opening_alloc ↔ 0.00 Payment · invoice balance 0 · credit memo used up · no deposit account");
  // ② 이미 QBO 에 있는 번호 → 만들지 않고 읽어서 done + note · 6140(우리 조회 뒤 생김) → 다시 찾아 done · 5xx → unknown(DocNumber) → 다음 send 가 from CreditMemo 로 풀기(found · 합계) · 없으면 not_found(크레딧 글)
  w.it.invoices.set("4899", { Id: "4899", DocNumber: "OC-60173-1", SyncToken: 2, TotalAmt: 10, TotalTax: 0, voided: false, CustomerRef: { value: "9242" }, ent: "CreditMemo" });
  const c2 = addOc(w, "60173", 1, 10); const n2 = cmPosts(w).length;
  const b3 = await body(await send(w, "JWT-MGR", { kinds: ["opening_credit"] }));
  eq([b3.sent, cmPosts(w).length - n2, c2.state, c2.qbo_id, w.db.txns.get(c2.ims_id)!.sync_token, (c2.last_error ?? "").includes("already in QuickBooks (DocNumber found before sending)")], [1, 0, "sent", "4899", "2", true], "found by number → read · recorded · not created again");
  const c3 = addOc(w, "60174", 1, 5);
  let planted = false; w.it.override.push((h) => { if (h.method === "POST" && h.url.includes("/creditmemo") && h.body.includes("\"OC-60174-1\"") && !planted) { planted = true; w.it.invoices.set("4897", { Id: "4897", DocNumber: "OC-60174-1", SyncToken: 0, TotalAmt: 5, TotalTax: 0, voided: false, CustomerRef: { value: "9242" }, ent: "CreditMemo" }); } return null; });
  const b4 = await body(await send(w, "JWT-MGR", { kinds: ["opening_credit"] })); w.it.override.length = 0;
  eq([b4.sent, c3.state, c3.qbo_id, (c3.last_error ?? "").includes("duplicate DocNumber (6140) — the existing credit memo #4897")], [1, "sent", "4897", true], "6140 → second DocNumber check → recorded: " + c3.last_error);
  const c4 = addOc(w, "60175", 1, 7), c5 = addOc(w, "60176", 1, 8);
  w.it.override.push((h) => h.method === "POST" && h.url.includes("/creditmemo") && (h.body.includes("\"OC-60175-1\"") || h.body.includes("\"OC-60176-1\"")) ? jres(503, { Fault: { Error: [{ Message: "Service Unavailable", code: "3001" }], type: "SystemFault" } }, "tid-503") : null);
  const b5 = await body(await send(w, "JWT-MGR", { kinds: ["opening_credit"] })); w.it.override.length = 0;
  eq([b5.unknown, c4.state, c4.qbo_name, c5.state, c5.qbo_name], [2, "unknown", "OC-60175-1", "unknown", "OC-60176-1"], "5xx → unknown with DocNumber");
  w.it.invoices.set("4890", { Id: "4890", DocNumber: "OC-60175-1", SyncToken: 1, TotalAmt: 7, TotalTax: 0, voided: false, CustomerRef: { value: "9242" }, ent: "CreditMemo" });
  const b6 = await body(await send(w, "JWT-MGR", { kinds: ["opening_credit"] }));
  const res6 = b6.resolved as Record<string, unknown>[];
  eq([res6.length, res6.map((x) => x.result).sort().join(","), c4.state, c4.qbo_id, w.db.txns.get(c4.ims_id)!.total_amt, w.db.txns.get(c4.ims_id)!.total_tax, (c4.last_error ?? "").includes("found in QuickBooks by DocNumber"), c5.state, String(res6.find((x) => x.job_id === c5.id)?.message).includes("QuickBooks has no credit memo with that number")],
     [2, "found,not_found", "sent", "4890", 7, 0, true, "unknown", true], "unknown resolved by CreditMemo DocNumber: " + JSON.stringify(res6));
  w.db.jobs.get(c5.id)!.state = "skipped";
  // ③ QBO 가 세금을 다르게 셈(0.5) → sent + mismatch(「opening credit」 글 · 942) · TotalTax 칸이 안 오면(이견 7) → total_tax null · 「did not return」 mismatch · EF 는 0 으로 꾸미지 않는다
  const c6 = addOc(w, "60177", 1, 9); w.it.taxOverride.set("OC-60177-1", 0.5);
  const b7 = await body(await send(w, "JWT-MGR", { kinds: ["opening_credit"] }));
  const t6 = w.db.txns.get(c6.ims_id)!;
  eq([b7.sent, b7.mismatch, c6.state, t6.total_amt, t6.total_tax, t6.mismatch, (c6.warning ?? "").includes("(942)")], [1, 1, "sent", 9.5, 0.5, "QuickBooks total 9.5 / tax 0.5 differs from IMS 9 / 0 — check opening credit OC-60177-1 → 60177 in QuickBooks (942)", true], "tax mismatch recorded · state sent");
  const c7 = addOc(w, "60178", 1, 3);
  w.it.override.push((h) => h.method === "POST" && h.url.includes("/creditmemo") && h.body.includes("\"OC-60178-1\"") ? jres(200, { CreditMemo: { Id: "4880", DocNumber: "OC-60178-1", SyncToken: "0", TotalAmt: 3, CustomerRef: { value: "9242" } }, time: "2026-11-07T12:00:00Z" }, "tid-notax") : null);
  const b8 = await body(await send(w, "JWT-MGR", { kinds: ["opening_credit"] })); w.it.override.length = 0;
  const t7 = w.db.txns.get(c7.ims_id)!;
  eq([b8.sent, c7.state, c7.qbo_id, t7.total_amt, t7.total_tax, t7.mismatch], [1, "sent", "4880", 3, null, "QuickBooks did not return TotalAmt / TotalTax — check opening credit OC-60178-1 → 60178 in QuickBooks"], "no TxnTaxDetail in the answer → total_tax null · DB judges (not faked to 0)");
  // ④ opening_apply 가드 — Invoice Balance 모자람 · CreditMemo RemainingCredit 모자람(Balance 넉넉) · 못 읽음 둘 · check_lines 결함 → failed · POST 0 / 4xx failed / 5xx · 끊김 unknown(열쇠 접두 셋째) → 풀기 0(Voided 쌍둥이 · 덧붙인 메모 · 금액 있음) · 1 found → done · 2 ambiguous · DocNumber 조회 0
  ledgerInv(w, "6302", "60179", 40.68, 5); ledgerCm(w, "6402", "OC-60179-1", 20);
  const c8 = addOc(w, "60179", 1, 10); w.db.jobs.get(c8.id)!.state = "sent"; const a2 = addOa(w, c8, "6302", "60179", "6402", 10); const n4 = payPosts(w).length, cr4 = cmReads(w).length;
  const b9 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply"] }));
  eq([b9.failed, payPosts(w).length - n4, cmReads(w).length - cr4, a2.state, a2.last_error, w.it.invoices.get("6302")!.Balance, w.it.invoices.get("6402")!.RemainingCredit], [1, 0, 0, "failed", "not sent — QuickBooks already shows 35.68 paid on invoice 60179 (balance 5 < 10) — a payment or credit entered before the switch-over or in QuickBooks? check before sending, then retry or skip", 5, 20], "invoice balance guard → failed, nothing written");
  ledgerInv(w, "6303", "60180"); ledgerCm(w, "6403", "OC-60180-1", 20, 3, 20);
  const c9 = addOc(w, "60180", 1, 10); w.db.jobs.get(c9.id)!.state = "sent"; const a3 = addOa(w, c9, "6303", "60180", "6403", 10);
  const b10 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply"] }));
  eq([b10.failed, payPosts(w).length - n4, a3.state, a3.last_error, w.it.invoices.get("6303")!.Balance], [1, 0, "failed", "not sent — QuickBooks shows only 3 left on credit memo OC-60180-1 (less than 10) — applied in QuickBooks or before the switch-over? check before sending, then retry or skip", 40.68], "RemainingCredit guard (OC number in the message) → failed, nothing written");
  ledgerInv(w, "6304", "60181"); ledgerCm(w, "6404", "OC-60181-1", 20);
  const c10 = addOc(w, "60181", 1, 1); w.db.jobs.get(c10.id)!.state = "sent";
  const a4 = addOa(w, c10, "9999", "60199", "6404", 1);
  const b11 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply"] }));
  eq([b11.failed, payPosts(w).length - n4, a4.state, (a4.last_error ?? "").startsWith("not sent — could not read invoice 60199 (QuickBooks #9999) before sending")], [1, 0, "failed", true], "unreadable invoice → failed: " + a4.last_error);
  const c11 = addOc(w, "60181", 2, 1); w.db.jobs.get(c11.id)!.state = "sent";
  const a5 = addOa(w, c11, "6304", "60181", "9998", 1);
  const b12 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply"] }));
  eq([b12.failed, payPosts(w).length - n4, a5.state, (a5.last_error ?? "").startsWith("not sent — could not read credit memo OC-60181-2 (QuickBooks #9998) before sending")], [1, 0, "failed", true], "unreadable credit memo → failed: " + a5.last_error);
  const c12 = addOc(w, "60181", 3, 1); w.db.jobs.get(c12.id)!.state = "sent";
  const a6 = addOa(w, c12, "6304", "60181", "6404", 1, { check_lines: [{ txn_type: "Invoice", invoice_number: "60181", qbo_invoice_id: "6304", amount: 1 }] });
  const ir6 = invReads(w).length, cr6 = cmReads(w).length;
  const b13 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply"] }));
  eq([b13.failed, payPosts(w).length - n4, invReads(w).length - ir6, cmReads(w).length - cr6, a6.state, a6.last_error], [1, 0, 0, 0, "failed", "not sent — the job carries 1 check line(s) instead of one invoice and one credit memo — nothing was written; retry it after checking the credit application"], "check_lines must be one invoice + one credit memo");
  ledgerInv(w, "6305", "60182"); ledgerCm(w, "6405", "OC-60182-1", 20);
  const c13 = addOc(w, "60182", 1, 4); w.db.jobs.get(c13.id)!.state = "sent"; const a7 = addOa(w, c13, "6305", "60182", "6405", 4);
  w.it.override.push((h) => h.method === "POST" && /\/payment\/?\?/.test(h.url) ? jres(400, { Fault: { Error: [{ Message: "Business Validation Error", Detail: "ZZ validation", code: "6000" }], type: "ValidationFault" } }, "tid-6000") : null);
  const b14 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply"] })); w.it.override.length = 0;
  eq([b14.failed, a7.state, (a7.last_error ?? "").includes("6000"), w.db.txns.has(a7.ims_id + ":apply")], [1, "failed", true, false], "4xx → failed: " + a7.last_error);
  ledgerInv(w, "6306", "60183"); ledgerCm(w, "6406", "OC-60183-1", 20);
  const c14 = addOc(w, "60183", 1, 6); w.db.jobs.get(c14.id)!.state = "sent"; const a8 = addOa(w, c14, "6306", "60183", "6406", 6);
  w.it.override.push((h) => h.method === "POST" && /\/payment\/?\?/.test(h.url) ? jres(502, {}, "tid-502") : null);
  const b15 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply"] })); w.it.override.length = 0;
  eq([b15.unknown, a8.state, a8.qbo_name, parsePaymentKey(a8.qbo_name)?.privateNote.startsWith("IMS opening credit applied "), parsePaymentKey(a8.qbo_name)?.totalAmt], [1, "unknown", oaKeyOf(a8), true, 0], "5xx → unknown with the opening-credit-applied key: " + a8.qbo_name);
  const c15 = addOc(w, "60183", 2, 1); w.db.jobs.get(c15.id)!.state = "sent"; const a9 = addOa(w, c15, "6306", "60183", "6406", 1);
  w.it.override.push((h) => h.method === "POST" && /\/payment\/?\?/.test(h.url) ? new Error("connection reset") : null);
  const b16 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply"] })); w.it.override.length = 0;
  eq([b16.unknown, a9.state, a9.qbo_name], [1, "unknown", oaKeyOf(a9)], "network error → unknown with the key");
  const noteA = String(a8.body.PrivateNote), dq0 = w.it.hits.filter((h) => /DocNumber/.test(h.url)).length;
  w.it.payments.set("7901", { Id: "7901", SyncToken: 0, TotalAmt: 0, UnappliedAmt: 0, CustomerRef: { value: "9242" }, TxnDate: "2026-11-07", PaymentRefNum: null, PrivateNote: "Voided - " + noteA, Line: [], voided: true, DepositToAccountRef: undefined, PaymentMethodRef: undefined });
  w.it.payments.set("7902", { Id: "7902", SyncToken: 0, TotalAmt: 0, UnappliedAmt: 0, CustomerRef: { value: "9242" }, TxnDate: "2026-11-07", PaymentRefNum: null, PrivateNote: noteA + " · entered by hand", Line: [], voided: false, DepositToAccountRef: undefined, PaymentMethodRef: undefined });
  w.it.payments.set("7903", { Id: "7903", SyncToken: 0, TotalAmt: 6, UnappliedAmt: 0, CustomerRef: { value: "9242" }, TxnDate: "2026-11-07", PaymentRefNum: "x", PrivateNote: noteA, Line: [], voided: false, DepositToAccountRef: { value: "105" }, PaymentMethodRef: { value: "2" } });
  const b17 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply"] }));
  const r17 = (b17.resolved as Record<string, unknown>[]).find((x) => x.job_id === a8.id)!;
  eq([r17.result, a8.state, /where TxnDate = '2026-11-07' MAXRESULTS 100/.test(sentQuery(payQueries(w).at(-1)!) ?? ""), w.it.hits.filter((h) => /DocNumber/.test(h.url)).length - dq0], ["not_found", "unknown", true, 0], "voided twin · note-with-suffix · non-zero amount are not it → not_found (no DocNumber query)");
  w.it.payments.set("7904", { Id: "7904", SyncToken: 0, TotalAmt: 0, UnappliedAmt: 0, CustomerRef: { value: "9242" }, TxnDate: "2026-11-07", PaymentRefNum: null, PrivateNote: noteA, Line: [{ Amount: 6, LinkedTxn: [{ TxnId: "6306", TxnType: "Invoice" }] }, { Amount: 6, LinkedTxn: [{ TxnId: "6406", TxnType: "CreditMemo" }] }], voided: false, DepositToAccountRef: undefined, PaymentMethodRef: undefined });
  const b18 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply"] }));
  const r18 = (b18.resolved as Record<string, unknown>[]).find((x) => x.job_id === a8.id)!;
  eq([r18.result, r18.qbo_id, a8.state, a8.qbo_id, w.db.txns.get(a8.ims_id + ":apply")!.qbo_id, w.db.txns.get(a8.ims_id + ":apply")!.total_amt, (a8.last_error ?? "").includes("found in QuickBooks by date, customer, amount 0 and note")], ["found", "7904", "sent", "7904", "7904", 0, true], "exact note + amount 0 + customer → done");
  const noteB = String(a9.body.PrivateNote);
  for (const id of ["7905", "7906"]) w.it.payments.set(id, { Id: id, SyncToken: 0, TotalAmt: 0, UnappliedAmt: 0, CustomerRef: { value: "9242" }, TxnDate: "2026-11-07", PaymentRefNum: null, PrivateNote: noteB, Line: [], voided: false, DepositToAccountRef: undefined, PaymentMethodRef: undefined });
  const b19 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply"] }));
  const r19 = (b19.resolved as Record<string, unknown>[]).find((x) => x.job_id === a9.id)!;
  eq([r19.result, r19.rows, a9.state], ["ambiguous", 2, "unknown"], "two matching 0.00 payments → ambiguous, job stays unknown");
  w.db.jobs.get(a9.id)!.state = "skipped";
  // ⑤ void 둘 — 떼기 = opening_apply_void(payment?operation=update&include=void · 7001) 먼저 → opening_credit_void(creditmemo?operation=void · 5001) 는 blocked_by 로 그 뒤(한 호출에 둘을 주면 첫 호출은 apply_void 만 · 다음 호출이 credit_void) · 장부 Balance · RemainingCredit 되돌아온 뒤 CreditMemo 가 0 이 된다 · SyncToken 없음 → GET 먼저 · 5010 → -2 · 거부 → failed · 5xx → unknown → not_voided → done
  const v1 = addOaVoid(w, c1, "7002", "0"), cv1 = addOcVoid(w, c1, "5001", "0"); cv1.state = "blocked"; cv1.blocked_by = v1.id;
  const nv1 = payVoidPosts(w).length, ncv1 = cmVoidPosts(w).length;
  const bv1 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply_void", "opening_credit_void"] }));
  const vp = payVoidPosts(w).slice(nv1);
  eq([bv1.sent, bv1.claimed, vp.length, cmVoidPosts(w).length - ncv1, JSON.parse(vp[0].body), new URL(vp[0].url).pathname.endsWith("/payment"), new URL(vp[0].url).searchParams.get("requestid"), v1.state, cv1.state, w.db.txns.get(c1.ims_id + ":apply")!.voided_at !== null, w.db.txns.get(c1.ims_id)!.voided_at, q1.voided, q1.TotalAmt, q1.Line.length, w.it.invoices.get("6301")!.Balance, cm1.RemainingCredit, cm1.voided],
     [1, 1, 1, 0, { Id: "7002", SyncToken: "0", sparse: true }, true, v1.request_id, "sent", "blocked", true, null, true, 0, 0, 28.24, 28.24, false], "first call: only the 0.00 payment is voided (balance and RemainingCredit restored) · the credit memo void still waits");
  const bv2 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply_void", "opening_credit_void"] }));
  const cvp = cmVoidPosts(w).slice(ncv1);
  eq([bv2.unblocked, bv2.sent, cvp.length, JSON.parse(cvp[0].body), new URL(cvp[0].url).pathname.endsWith("/creditmemo"), new URL(cvp[0].url).searchParams.get("operation"), new URL(cvp[0].url).searchParams.get("requestid"), cv1.state, w.db.txns.get(c1.ims_id)!.voided_at !== null, cm1.voided, cm1.TotalAmt, voidPosts(w).length],
     [1, 1, 1, { Id: "5001", SyncToken: "0" }, true, "void", cv1.request_id, "sent", true, true, 0, 0], "second call: the credit memo is voided via creditmemo?operation=void · no invoice void");
  const cv2 = addOcVoid(w, c2, "4899", null); const r0 = cmReads(w).length;
  const bv3 = await body(await send(w, "JWT-MGR", { kinds: ["opening_credit_void"] }));
  eq([bv3.sent, cmReads(w).length - r0, cv2.state, (cv2.last_error ?? "").includes("SyncToken read from QuickBooks before voiding"), w.it.invoices.get("4899")!.voided], [1, 1, "sent", true, true], "no SyncToken → GET creditmemo first, then void");
  w.it.invoices.get("4897")!.SyncToken = 3;
  const cv3 = addOcVoid(w, c3, "4897", "0"); const n9 = cmVoidPosts(w).length;
  const bv4 = await body(await send(w, "JWT-MGR", { kinds: ["opening_credit_void"] }));
  const p9 = cmVoidPosts(w).slice(n9);
  eq([bv4.sent, p9.length, JSON.parse(p9[1].body).SyncToken, new URL(p9[1].url).searchParams.get("requestid"), cv3.state, (cv3.last_error ?? "").includes("stale SyncToken (5010)")], [1, 2, "3", cv3.request_id + "-2", "sent", true], "stale → re-read → second try with -2");
  w.it.voidRefuse.add("4890");
  const cv4 = addOcVoid(w, c4, "4890", "1");
  const bv5 = await body(await send(w, "JWT-MGR", { kinds: ["opening_credit_void"] }));
  eq([bv5.failed, cv4.state, (cv4.last_error ?? "").includes("code 6000"), w.it.invoices.get("4890")!.voided, w.db.txns.get(c4.ims_id)!.voided_at], [1, "failed", true, false, null], "refused credit memo void → failed · txn not voided: " + cv4.last_error);
  w.it.voidRefuse.delete("4890"); w.db.jobs.get(cv4.id)!.state = "skipped";
  const cv5 = addOcVoid(w, c4, "4890", "1");
  w.it.override.push((h) => h.method === "POST" && new URL(h.url).searchParams.get("operation") === "void" ? jres(502, {}, "tid-502") : null);
  const bv6 = await body(await send(w, "JWT-MGR", { kinds: ["opening_credit_void"] })); w.it.override.length = 0;
  eq([bv6.unknown, cv5.state, cv5.qbo_name], [1, "unknown", "OC-60175-1"], "credit memo void 5xx → unknown with DocNumber");
  const bv7 = await body(await send(w, "JWT-MGR", { kinds: ["opening_credit_void"] }));
  const rv7 = (bv7.resolved as Record<string, unknown>[]).find((x) => x.job_id === cv5.id)!;
  eq([rv7.result, cv5.state, String(rv7.message).includes("credit memo still carries an amount")], ["not_voided", "unknown", true], "still carries an amount → not_voided");
  const cm4 = w.it.invoices.get("4890")!; cm4.TotalAmt = 0; cm4.TotalTax = 0; cm4.voided = true; cm4.SyncToken = 2;
  const bv8 = await body(await send(w, "JWT-MGR", { kinds: ["opening_credit_void"] }));
  const rv8 = (bv8.resolved as Record<string, unknown>[]).find((x) => x.job_id === cv5.id)!;
  eq([rv8.result, cv5.state, w.db.txns.get(c4.ims_id)!.voided_at !== null, (cv5.last_error ?? "").includes("credit memo is voided (amount 0)")], ["found", "sent", true, true], "amount 0 → voided → done");
  const q8 = w.it.payments.get("7904")!; w.it.voidRefuse.add("7904");
  const v2 = addOaVoid(w, c14, "7904", "0");
  const bv9 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply_void"] }));
  eq([bv9.failed, v2.state, (v2.last_error ?? "").includes("code 6000"), q8.voided, w.db.txns.get(c14.ims_id + ":apply")!.voided_at], [1, "failed", true, false, null], "refused payment void → failed: " + v2.last_error);
  w.it.voidRefuse.delete("7904"); w.db.jobs.get(v2.id)!.state = "skipped";
  const v3 = addOaVoid(w, c14, "7904", null); const pr3 = payReads(w).length;
  w.it.override.push((h) => h.method === "POST" && new URL(h.url).searchParams.get("include") === "void" ? jres(502, {}, "tid-502") : null);
  const bv10 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply_void"] })); w.it.override.length = 0;
  eq([bv10.unknown, payReads(w).length - pr3, v3.state, v3.qbo_name], [1, 1, "unknown", "7904"], "no SyncToken → GET payment · void 5xx → unknown with the payment id");
  const bv11 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply_void"] }));
  eq([(bv11.resolved as Record<string, unknown>[]).find((x) => x.job_id === v3.id)!.result, v3.state], ["not_voided", "unknown"], "0.00 payment not marked Voided → not_voided");
  q8.TotalAmt = 0; q8.UnappliedAmt = 0; q8.Line = []; q8.voided = true; q8.PrivateNote = "Voided - " + q8.PrivateNote; q8.SyncToken = 2;
  const bv12 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply_void"] }));
  eq([(bv12.resolved as Record<string, unknown>[]).find((x) => x.job_id === v3.id)!.result, v3.state, w.db.txns.get(c14.ims_id + ":apply")!.voided_at !== null], ["found", "sent", true], "Voided note + amount 0 → done");
  const v4 = addOaVoid(w, c15, null, null), cv6 = addOcVoid(w, c15, null, null);
  const bv13 = await body(await send(w, "JWT-MGR", { kinds: ["opening_apply_void", "opening_credit_void"] }));
  eq([bv13.failed, v4.state, (v4.last_error ?? "").startsWith("not sent — no QuickBooks payment id"), cv6.state, (cv6.last_error ?? "").startsWith("not sent — no QuickBooks credit memo id")], [2, "failed", true, "failed", true], "void jobs without id → failed (both words)");
  // ⑥ cron 62 꼴 kinds 여덟(결제 · 크레딧 붙임 · 이월 둘 한 호출 · 열쇠 문 없음) → claim p_kinds 여덟 · 모르는 kind 는 400(배포 전 여덟 등록 = 1034 함정 — 지금 EF 는 받는다)
  ledgerInv(w, "6307", "60184", 40.68); const c16 = addOc(w, "60184", 1, 2);
  const rc = await postBody(w, { action: "send", kinds: EIGHT, limit: 9 }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" });
  const bc = await body(rc);
  eq([rc.status, bc.kinds, bc.sent, bc.failed, c16.state, w.db.claimKinds.at(-1), w.logs.filter((l) => l.action === "send").at(-1)?.by_staff ?? null], [200, EIGHT, 1, 0, "sent", EIGHT, null], "cron 62 with eight kinds: an opening credit memo in one round · by_staff null");
  const rbad = await postBody(w, { action: "send", kinds: [...EIGHT, "bogus"], limit: 9 }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" });
  eq([rbad.status, String((await body(rbad)).error).includes("kinds must be among")], [400, true], "an unknown kind in the cron body → 400 (nothing sent — 1034)");
  // ⑦ 골라 보내기 — 첫 실물 꼴 두 호출: ① opening_credit 하나(job_ids) → sent · 같은 붙임의 opening_apply 는 고르지 않았으니 풀리기만(queued · 보내지 않는다) ② opening_apply 하나 → sent / apply 를 홀로 고르면(credit 이 queued) blocked · credit 을 대신 보내지 않는다(960 · 이견 5)
  ledgerInv(w, "6308", "60185", 60, 12.5);
  const c17 = addOc(w, "60185", 1, 12.5); const a17 = addOa(w, c17, "6308", "60185", "", 12.5); a17.state = "blocked"; a17.blocked_by = c17.id;
  const uidC = "2e3e3e3e-0000-4000-8000-" + String(Number(c17.id.replace("job-", ""))).padStart(12, "0"), uidA = "2e3e3e3e-0000-4000-8000-" + String(Number(a17.id.replace("job-", ""))).padStart(12, "0");
  w.db.jobs.delete(c17.id); c17.id = uidC; w.db.jobs.set(uidC, c17); w.db.jobs.delete(a17.id); a17.id = uidA; a17.blocked_by = uidC; w.db.jobs.set(uidA, a17);
  const np0 = payPosts(w).length, ncp0 = cmPosts(w).length;
  const bpa = await body(await postBody(w, { action: "send", job_ids: [uidA] }, "JWT-MGR"));
  const rqa = (bpa.requested as Record<string, unknown>[])[0];
  eq([bpa.mode, rqa.result, a17.state, a17.blocked_by, c17.state, cmPosts(w).length - ncp0, payPosts(w).length - np0, (bpa.needs as unknown[]).length, bpa.stopped], ["selected", "not_queued", "blocked", uidC, "queued", 0, 0, 0, "no_progress"], "picked opening_apply (already blocked by the DB sync — not_queued · state blocked) waits for its credit memo; the credit memo is not sent on its behalf: " + JSON.stringify(rqa));
  const bp1 = await body(await postBody(w, { action: "send", job_ids: [uidC] }, "JWT-MGR"));
  const rq1 = (bp1.requested as Record<string, unknown>[])[0];
  eq([bp1.mode, rq1.result, c17.state, c17.qbo_id !== null, cmPosts(w).length - ncp0, payPosts(w).length - np0, a17.state], ["selected", "sent", "sent", true, 1, 0, "queued"], "first real ①: only the credit memo goes · the 0.00 payment is released but not sent: " + JSON.stringify(rq1));
  a17.check_lines![1].qbo_creditmemo_id = String(c17.qbo_id); (a17.body.Line as Record<string, unknown>[])[1].LinkedTxn = [{ TxnId: String(c17.qbo_id), TxnType: "CreditMemo" }];
  const bp2 = await body(await postBody(w, { action: "send", job_ids: [uidA] }, "JWT-MGR"));
  const rq2 = (bp2.requested as Record<string, unknown>[])[0];
  eq([bp2.mode, rq2.result, a17.state, payPosts(w).length - np0, w.it.invoices.get("6308")!.Balance, w.it.invoices.get(String(c17.qbo_id))!.RemainingCredit], ["selected", "sent", "sent", 1, 0, 0], "first real ②: the 0.00 payment goes · invoice balance 0 · credit memo used up: " + JSON.stringify(rq2));
  writesAllowedOnly(w, "㉕"); noLeak(w, "㉕");
  ok(!JSON.stringify({ logs: w.logs, warns: w.warns }).includes("ZZPII"), "no PII in logs");
});

// ── 2e-3-2-1b 환불 — 가짜 일감 넷(DB qbo_refund_body · qbo_refund_apply_body · qbo_refund_void_body · qbo_refund_apply_void_body 꼴) · 심은 Purchase · 히트 ──
const rfUuid = (n: number) => "2e3f2e3f-0000-4000-8000-" + String(n).padStart(12, "0");
const rfDetail = (cust = "9242") => ({ AccountRef: { value: "84" }, CustomerRef: { value: cust }, TaxCodeRef: { value: "4" } });
const rfHead = (cust = "9242", date = "2026-11-05", doc: string | null = null): Record<string, unknown> => ({ PaymentType: "Cash", AccountRef: { value: "105" }, EntityRef: { value: cust, type: "Customer" }, TxnDate: date, CurrencyRef: { value: "CAD" }, GlobalTaxCalculation: "NotApplicable", ...(doc ? { DocNumber: doc } : {}) });
type Cm = { id: string; doc: string; amt: number };
const cmSum = (cms: Cm[]) => Math.round(cms.reduce((a, c) => a + c.amt, 0) * 100) / 100;
const addRf = (w: World, label: string, uuid: string, cms: Cm[], cust = "9242", date = "2026-11-05", doc: string | null = null, extra: Partial<Job> = {}) =>
  addJob(w, { kind: "refund", ims_id: uuid, name: label, doc_number: doc, totals: { total: cmSum(cms), tax: 0 },
    body: { ...rfHead(cust, date, doc), PrivateNote: "IMS refund " + uuid, Line: [{ DetailType: "AccountBasedExpenseLineDetail", LineNum: 1, Amount: cmSum(cms), Description: "Refund of credit note" + (cms.length > 1 ? "s " : " ") + cms.map((c) => c.doc).join(", "), AccountBasedExpenseLineDetail: rfDetail(cust) }] },
    check_lines: cms.map((c) => ({ txn_type: "CreditMemo", credit_number: c.doc, qbo_creditmemo_id: c.id, amount: c.amt })),
    lookup: { customer_ref: cust, txn_date: date, total_amt: cmSum(cms), private_note: "IMS refund " + uuid }, ...extra });
const addRfa = (w: World, label: string, uuid: string, pid: string, cms: Cm[], cust = "9242", date = "2026-11-05", extra: Partial<Job> = {}) =>
  addJob(w, { kind: "refund_apply", ims_id: uuid, name: label, doc_number: label,
    body: { CustomerRef: { value: cust }, TxnDate: date, TotalAmt: 0, CurrencyRef: { value: "CAD" }, PrivateNote: "IMS refund applied " + uuid, Line: [{ Amount: cmSum(cms), LinkedTxn: [{ TxnId: pid, TxnType: "Expense" }] }, ...cms.map((c) => ({ Amount: c.amt, LinkedTxn: [{ TxnId: c.id, TxnType: "CreditMemo" }] }))] },
    check_lines: [{ txn_type: "Expense", refund: label, qbo_purchase_id: pid, amount: cmSum(cms) }, ...cms.map((c) => ({ txn_type: "CreditMemo", credit_number: c.doc, qbo_creditmemo_id: c.id, amount: c.amt }))],
    lookup: { customer_ref: cust, txn_date: date, total_amt: 0, private_note: "IMS refund applied " + uuid }, pay_totals: { amount: 0, unapplied: 0 }, ...extra });
const addRfv = (w: World, label: string, uuid: string, pid: string, syncToken: string | null, cust = "9242", date = "2026-11-05") =>
  addJob(w, { kind: "refund_void", ims_id: uuid, name: label, doc_number: null, body: { ...rfHead(cust, date), Id: pid, ...(syncToken !== null ? { SyncToken: syncToken } : {}), PrivateNote: "Voided - IMS refund " + uuid, Line: [{ DetailType: "AccountBasedExpenseLineDetail", LineNum: 1, Amount: 0, Description: "Voided", AccountBasedExpenseLineDetail: rfDetail(cust) }] } });
const addRfav = (w: World, label: string, uuid: string, payId: string, syncToken: string | null) => addJob(w, { kind: "refund_apply_void", ims_id: uuid, name: label, doc_number: label, body: syncToken !== null ? { Id: payId, SyncToken: syncToken, sparse: true } : { Id: payId, sparse: true } });
const plantPur = (w: World, id: string, date: string, amt: number, cust: string | null, note: string, lineCust?: string | null): Pur => {   // 북키퍼가 손으로 넣은 꼴(EntityRef 또는 줄 CustomerRef 만) · 금액 0 + 「Voided - 」 면 Voided
  const lc = lineCust === undefined ? cust : lineCust, voided = amt === 0 && note.startsWith("Voided - ");
  const v: Pur = { Id: id, SyncToken: 0, TxnDate: date, TotalAmt: amt, PaymentType: "Check", EntityRef: cust ? { value: cust, type: "Customer" } : undefined, PrivateNote: note, DocNumber: null, Line: [{ Id: "1", LineNum: 1, Amount: amt, DetailType: "AccountBasedExpenseLineDetail", AccountBasedExpenseLineDetail: { AccountRef: { value: "84" }, ...(lc ? { CustomerRef: { value: lc } } : {}), TaxCodeRef: { value: "4" } } }], LinkedTxn: [], AccountRef: { value: "105" }, voided, open: amt, ...(voided ? { status: "Voided" } : {}) };
  w.it.purchases.set(id, v); return v;
};
const purPosts = (w: World) => postHits(w).filter((h) => /\/purchase\/?\?/.test(h.url));
const purReads = (w: World) => apiHits(w).filter((h) => h.method === "GET" && /\/purchase\/\d+\?/.test(h.url));
const guardQueries = (w: World, ent: string) => queryHits(w).filter((h) => new RegExp("from\\s+" + ent + "\\s+where\\s+TxnDate\\s*>=", "i").test(sentQuery(h) ?? ""));
const purDateQueries = (w: World) => queryHits(w).filter((h) => /from\s+Purchase\s+where\s+TxnDate\s*=/i.test(sentQuery(h) ?? ""));
const nextPurId = (w: World) => String(8000 + w.it.createdN + 1);   // 가짜 장부의 다음 Purchase Id(DB 는 claim 때 qbo_txn 에서 넣는다 — 가짜 몸은 미리 셈한다)

Deno.test("㉖ 환불 = Purchase(Expense) 만들기 · 0 원 Payment(Expense + CreditMemo 줄) · void 둘(qbo-sync-2e-3-2-1b · 판정 1056 ~ 1058 · ⓖ-6 · ⓖ-7 · sandbox 2-a ~ 2-e · 걸음 25 · 이견 1 ~ 11) — 순수(SEND_KINDS 18 · REFUND_KINDS · REFUND_APPLY_KINDS · 옛 배열 무변 · parsePaymentKey 접두 넷 · kindsOf 열둘 · assertWriteAllowed purchase 만들기 · void 꼴만(몸 검사 · operation 전부 거부 · 다른 엔티티 무변) · isVoidedPurchase · 조회 글 parseQuery 통과 · shiftDate · 손님 · JE · 히트 · txnOpenBalance) · ① refund: CreditMemo RemainingCredit → 손 기록 셋(± 7 일 · 서버는 TxnDate 만) → POST purchase(몸 그대로) → done(TotalAmt · DocNumber = reference) → refund_apply 풀림 → GET purchase · creditmemo → POST payment(Expense + CreditMemo 줄) → done(TotalAmt 0 · UnappliedAmt 0 · txnOpenBalance note) · ② 가드: 크레딧 모자람 · 손 Purchase(EntityRef · 줄 CustomerRef) · 다른 손님 · Voided · IMS 환불 · 범위 밖 · 금액 다름은 통과 · JournalEntry · RefundReceipt · 쪽 넘김 · 쪽 넘침 · 조회 실패 · 4xx · 5xx unknown → 풀기 0 · 1 · 2(완전 일치 · Voided 제외) · 열쇠 결함 · ③ refund_apply 가드(check_lines · 못 읽음 · Voided · 메모 다름 · TotalAmt 모자람 · 크레딧 모자람 · 4xx · 5xx → 풀기) · 열린 금액 남음 note · ④ void: refund_apply_void 먼저(update&include=void · 되돌림) → refund_void(GET → Full update: 읽은 SyncToken · 읽은 Line Amount 0 · Voided 메모 · operation 없음 · status Voided → done) · LinkedTxn Payment 남음 failed · 5010 → -2 · status 다름 failed · status 없음 done + note · 이미 Voided done · 줄 0 failed · 거부 failed · 5xx → unknown → Id 로 풀기 · ⑤ cron 62 kinds 열둘 · ⑥ 골라 보내기(apply 홀로 = blocked · 둘 함께 = refund → apply) · 쓰기 꼴 · 누출 0", async () => {
  // ⓪ 순수
  eq([[...SEND_KINDS].length, [...SEND_KINDS].slice(14, 18), [...REFUND_KINDS], [...REFUND_APPLY_KINDS], [...TXN_KINDS], [...CREDIT_APPLY_KINDS], [...PAYMENT_KINDS], [...OPENING_CREDIT_KINDS], [...OPENING_APPLY_KINDS], [...WRITE_ENTITIES], [...REFUND_GUARD_ENTITIES], REFUND_GUARD_DAYS, REFUND_GUARD_PAGES_MAX, VOIDED_NOTE_PREFIX],
     [19, ["refund", "refund_void", "refund_apply", "refund_apply_void"], ["refund", "refund_void"], ["refund_apply", "refund_apply_void"], ["invoice", "invoice_void", "credit", "credit_void"], ["credit_apply", "credit_apply_void"], ["payment", "payment_void"], ["opening_credit", "opening_credit_void"], ["opening_apply", "opening_apply_void"], ["customer", "item", "invoice", "creditmemo", "payment", "purchase", "journalentry"], ["Purchase", "JournalEntry", "RefundReceipt"], 7, 5, "Voided - "], "SEND_KINDS 18 → 19 (3-3) · new pairs · old arrays unchanged · WRITE_ENTITIES + purchase + journalentry (3-3)");
  const u0 = rfUuid(1);
  eq([parsePaymentKey(`IMS refund ${u0}|9242|2026-11-05|43.96`), parsePaymentKey(`IMS refund applied ${u0}|9242|2026-11-05|0`)?.totalAmt, parsePaymentKey("IMS refunded x|9242|2026-11-05|1"), parsePaymentKey("IMS payment x|7190|2026-11-02|10")?.totalAmt, parsePaymentKey("IMS credit applied x|9242|2026-11-02|0")?.totalAmt],
     [{ privateNote: "IMS refund " + u0, customerRef: "9242", txnDate: "2026-11-05", totalAmt: 43.96 }, 0, null, 10, 0], "payment key: fourth prefix (expense · applied) · others refused · old prefixes unchanged");
  const TWELVE = ["payment", "payment_void", "credit_apply", "credit_apply_void", "opening_credit", "opening_credit_void", "opening_apply", "opening_apply_void", "refund", "refund_void", "refund_apply", "refund_apply_void"];
  eq(kindsOf(TWELVE), TWELVE, "kindsOf: the twelve cron-62 kinds");
  for (const bad of [["refund", "bogus"], ["purchase"], ["Refund"], ["refund_apply_void", ""]]) { let threw = false; try { kindsOf(bad); } catch (e) { threw = e instanceof QboError && e.status === 400; } ok(threw, "kindsOf refuses " + JSON.stringify(bad)); }
  const base = "https://quickbooks.api.intuit.com/v3/company/123", pu = `${base}/purchase?requestid=r1&minorversion=75`;
  const voidB: Record<string, unknown> = { Id: "188", SyncToken: "2", PaymentType: "Cash", PrivateNote: "Voided - IMS refund x", Line: [{ Amount: 0, DetailType: "AccountBasedExpenseLineDetail" }, { Amount: 0 }] };
  assertWriteAllowed("POST", pu, { PaymentType: "Cash", Line: [{ Amount: 5 }] }); assertWriteAllowed("POST", pu, voidB); assertWriteAllowed("POST", pu); assertWriteAllowed("POST", pu, null);
  const refusedB = (b: unknown, why: string) => { let msg = ""; try { assertWriteAllowed("POST", pu, b); } catch (e) { msg = (e as Error).message; } ok(msg.startsWith("refusing") && msg.includes("void shape"), why + " should be refused: " + (msg || "(allowed)")); return msg; };
  ok(refusedB({ ...voidB, SyncToken: undefined }, "no SyncToken").includes("no SyncToken"), "why: SyncToken");
  ok(refusedB({ ...voidB, Line: [{ Amount: 0 }, { Amount: 5 }] }, "amount 5").includes("line 2 Amount is not 0"), "why: amount");
  ok(refusedB({ ...voidB, Line: [{ Amount: "0" }] }, "string amount").includes("line 1 Amount is not 0"), "why: amount must be the number 0");
  ok(refusedB({ ...voidB, PrivateNote: "IMS refund x" }, "no Voided note").includes("PrivateNote does not start"), "why: note");
  ok(refusedB({ ...voidB, sparse: true }, "sparse").includes("sparse"), "why: sparse");
  ok(refusedB({ ...voidB, Line: [] }, "no lines").includes("no lines"), "why: lines");
  ok(refusedB({ Id: "188" }, "bare Id").includes("no SyncToken"), "bare Id refused");
  const refusedU = (u: string, why: string) => { let msg = ""; try { assertWriteAllowed("POST", u, voidB); } catch (e) { msg = (e as Error).message; } ok(msg.startsWith("refusing"), why + ": " + (msg || "(allowed)")); return msg; };
  ok(refusedU(`${base}/purchase?operation=void&requestid=r1`, "purchase?operation=void").includes("only operation=void on invoice, creditmemo"), "no operation=void on purchase");
  ok(refusedU(`${base}/purchase?operation=update&include=void&requestid=r1`, "purchase update&include=void").includes("operation=update&include=void on payment"), "no update&include=void on purchase");
  refusedU(`${base}/purchase?operation=delete&requestid=r1`, "purchase delete"); refusedU(`${base}/purchase/188?requestid=r1`, "purchase/188 (not a create path)");
  let m0 = ""; try { assertWriteAllowed("POST", `${base}/purchase?minorversion=75`, { PaymentType: "Cash" }); } catch (e) { m0 = (e as Error).message; } ok(m0.includes("without a requestid"), "purchase create still needs a requestid");
  assertWriteAllowed("POST", `${base}/invoice?requestid=r1`, { Id: "5", DocNumber: "x" });   // 덧(이견 7): 다른 엔티티의 몸은 이 차수에 보지 않는다 — 넓히는 안은 보고에
  eq([purchaseVoidBodyProblem(voidB), purchaseVoidBodyProblem({}), purchaseVoidBodyProblem(null)], [null, "no SyncToken", "no SyncToken"], "purchaseVoidBodyProblem");
  eq([isVoidedPurchase({ TotalAmt: 0, PrivateNote: "Voided - IMS refund x" }), isVoidedPurchase({ TotalAmt: 0, PrivateNote: "IMS refund x" }), isVoidedPurchase({ TotalAmt: 5, PrivateNote: "Voided - x" }), isVoidedPurchase({ TotalAmt: "0", PrivateNote: "Voided - x" }), isVoidedPurchase(null)], [true, false, false, true, false], "isVoidedPurchase: amount 0 AND the Voided note (sandbox P2 a · b)");
  for (const ent of REFUND_GUARD_ENTITIES) { const t = refundGuardQueryText(ent, "2026-10-29", "2026-11-12", 1001); const pq = parseQuery(t); eq([pq.entity, pq.maxResults, pq.startPosition, t.includes("STARTPOSITION 1001 MAXRESULTS 1000"), t.includes("TxnDate >= '2026-10-29' and TxnDate <= '2026-11-12'"), /^select \* /.test(t)], [ent, 1000, 1001, true, true, ent !== "RefundReceipt"], ent + " guard query passes parseQuery · RefundReceipt names its fields"); }
  eq(parseQuery(purchasesByDateQueryText("2026-11-05")).text, "select * from Purchase where TxnDate = '2026-11-05' MAXRESULTS 1000", "purchases by date");
  eq([shiftDate("2026-11-05", -7), shiftDate("2026-11-05", 7), shiftDate("2026-03-02", -7), shiftDate("2026-12-28", 7)], ["2026-10-29", "2026-11-12", "2026-02-23", "2027-01-04"], "shiftDate across months and years");
  eq([purchaseCustomerRefs({ EntityRef: { value: "9", type: "Customer" }, Line: [{ AccountBasedExpenseLineDetail: { CustomerRef: { value: "8" } } }, { ItemBasedExpenseLineDetail: { CustomerRef: { value: "7" } } }, {}] }), purchaseCustomerRefs({ EntityRef: { value: "9", type: "Vendor" } }), purchaseCustomerRefs({ EntityRef: { value: "9" } }), purchaseCustomerRefs({})], [["9", "8", "7"], [], ["9"], []], "purchaseCustomerRefs: EntityRef(Customer or untyped) + line CustomerRef");
  const je = { Id: "77", TxnDate: "2026-11-04", Line: [{ Amount: 12.5, JournalEntryLineDetail: { PostingType: "Debit", Entity: { Type: "Customer", EntityRef: { value: "9242" } } } }, { Amount: 12.5, JournalEntryLineDetail: { PostingType: "Credit", AccountRef: { value: "1" } } }, { Amount: 3, JournalEntryLineDetail: { PostingType: "Debit", Entity: { Type: "Vendor", EntityRef: { value: "9242" } } } }] };
  eq([journalCustomerAmounts(je, "9242"), journalCustomerAmounts(je, "1")], [{ any: [12.5], debit: 12.5 }, { any: [], debit: 0 }], "journalCustomerAmounts: customer entity lines only");
  const hp = (over: Record<string, unknown>) => ({ Id: "1", TxnDate: "2026-11-04", TotalAmt: 43.96, EntityRef: { value: "9242", type: "Customer" }, PrivateNote: "cheque", Line: [], ...over });
  eq([refundHandHit("Purchase", hp({}), "9242", 43.96), refundHandHit("Purchase", hp({ TotalAmt: 43.95 }), "9242", 43.96), refundHandHit("Purchase", hp({ EntityRef: { value: "7190" } }), "9242", 43.96), refundHandHit("Purchase", hp({ PrivateNote: "IMS refund " + rfUuid(9) }), "9242", 43.96), refundHandHit("Purchase", hp({ TotalAmt: 0, PrivateNote: "Voided - cheque" }), "9242", 43.96), refundHandHit("Purchase", hp({ EntityRef: undefined, Line: [{ AccountBasedExpenseLineDetail: { CustomerRef: { value: "9242" } } }] }), "9242", 43.96), refundHandHit("Purchase", hp({ PaymentType: "CreditCard" }), "9242", 43.96),
      refundHandHit("JournalEntry", je, "9242", 12.5), refundHandHit("JournalEntry", je, "9242", 3), refundHandHit("JournalEntry", je, "1", 12.5),
      refundHandHit("RefundReceipt", { CustomerRef: { value: "9242" }, TotalAmt: 43.96 }, "9242", 43.96), refundHandHit("RefundReceipt", { CustomerRef: { value: "9242" }, TotalAmt: 0 }, "9242", 0), refundHandHit("RefundReceipt", { CustomerRef: { value: "7190" }, TotalAmt: 43.96 }, "9242", 43.96), refundHandHit("Deposit", hp({}), "9242", 43.96)],
     [true, false, false, false, false, true, true, true, false, false, true, false, false, false], "refundHandHit: customer · amount · not Voided · not an IMS refund · any PaymentType · JE customer lines · RefundReceipt customer · other entities never");
  eq(txnOpenBalances({ Line: [{ Amount: 5, LinkedTxn: [{ TxnId: "195", TxnType: "Expense" }], LineEx: { any: [{ name: "x", value: { Name: "txnId", Value: "195" } }, { value: { Name: "txnOpenBalance", Value: "0" } }] } }, { Amount: 3, LinkedTxn: [{ TxnId: "193", TxnType: "CreditMemo" }] }] }), [{ type: "Expense", id: "195", open: "0" }, { type: "CreditMemo", id: "193", open: null }], "txnOpenBalances from LineEx");
  const obl = (type: string, id: string, before: string | null, amt: number) => ({ Amount: amt, LinkedTxn: [{ TxnId: id, TxnType: type }], ...(before === null ? {} : { LineEx: { any: [{ value: { Name: "txnId", Value: id } }, { value: { Name: "txnOpenBalance", Value: before } }] } }) });   // [1b2] openBalanceNote — 잇기 직전 값 · after = before − Amount
  eq(openBalanceNote({ Line: [obl("Expense", "195", "5.00", 5), obl("CreditMemo", "193", "3.00", 3)] }), { note: "QuickBooks open balance before linking: Expense #195 5.00 → 0 after · CreditMemo #193 3.00 → 0 after", warn: false }, "openBalanceNote: before = amount → no warning (the real sandbox answer 5.00 · 3.00)");
  eq(openBalanceNote({ Line: [obl("Expense", "195", "3.00", 5), obl("CreditMemo", "193", "2.00", 3)] }), { note: "QuickBooks open balance before linking: Expense #195 3.00 → -2 after · CreditMemo #193 2.00 → -1 after — Expense #195 2 short · CreditMemo #193 1 short, check the refund in QuickBooks", warn: true }, "openBalanceNote: before < amount → warning on both kinds");
  eq([openBalanceNote({ Line: [obl("Expense", "195", "10.00", 3), obl("CreditMemo", "193", "10.00", 3)] }), openBalanceNote({ Line: [obl("CreditMemo", "193", null, 3)] }), openBalanceNote({})], [{ note: "QuickBooks open balance before linking: Expense #195 10.00 → 7 after · CreditMemo #193 10.00 → 7 after — Expense #195 7 left, check the refund in QuickBooks", warn: true }, { note: "QuickBooks open balance before linking: CreditMemo #193 ? → ? after", warn: false }, { note: null, warn: false }], "openBalanceNote: left over → Expense warns · CreditMemo does not (partial use is normal) · no LineEx → ? · no lines → null");

  const w = world(); connect(w); w.db.keys["JWT-MGR"] = "qbo";
  const CM1: Cm[] = [{ id: "6401", doc: "CR-01011", amt: 43.96 }];
  // ① 성공 — refund: GET creditmemo 1 → 손 기록 조회 셋(Purchase · JournalEntry · RefundReceipt · paid_on ± 7 일 · STARTPOSITION 1) → POST purchase 1(몸 그대로 · requestid · operation 없음) → done(TotalAmt 43.96 · TotalTax 없음 → null · DocNumber = reference) → blocked 였던 refund_apply 가 풀린다
  ledgerCm(w, "6401", "CR-01011", 43.96);
  const u1 = rfUuid(1), r1 = addRf(w, "CR-01011 refund", u1, CM1, "9242", "2026-11-05", "REF-1");
  const pid1 = nextPurId(w);
  const a1 = addRfa(w, "CR-01011 refund", u1, pid1, CM1); a1.state = "blocked"; a1.blocked_by = r1.id;   // DB sync 가 세운 꼴(ⓖ-6: 0 원 Payment 는 만들 때부터 Purchase 일감 뒤)
  const b1 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  const pp1 = purPosts(w);
  eq([b1.claimed, b1.sent, b1.failed, b1.unknown, b1.kinds, cmReads(w).length, guardQueries(w, "Purchase").length, guardQueries(w, "JournalEntry").length, guardQueries(w, "RefundReceipt").length, pp1.length, JSON.parse(pp1[0].body), new URL(pp1[0].url).pathname.endsWith("/purchase"), new URL(pp1[0].url).searchParams.get("requestid"), new URL(pp1[0].url).searchParams.get("operation"), payPosts(w).length, invReads(w).length, purDateQueries(w).length],
     [1, 1, 0, 0, ["refund"], 1, 1, 1, 1, 1, r1.body, true, r1.request_id, null, 0, 0, 0], "credit memo read · three hand-record checks · one POST purchase with the DB body: " + JSON.stringify(b1.jobs));
  eq(sentQuery(guardQueries(w, "Purchase")[0]), "select * from Purchase where TxnDate >= '2026-10-29' and TxnDate <= '2026-11-12' STARTPOSITION 1 MAXRESULTS 1000", "paid_on ± 7 days · the server filters TxnDate only (sandbox 2-e)");
  eq(sentQuery(guardQueries(w, "RefundReceipt")[0]), "select Id, TxnDate, TotalAmt, CustomerRef, PrivateNote, DocNumber from RefundReceipt where TxnDate >= '2026-10-29' and TxnDate <= '2026-11-12' STARTPOSITION 1 MAXRESULTS 1000", "RefundReceipt names its fields (PII entity)");
  const t1 = w.db.txns.get(u1)!, q1 = w.it.purchases.get(pid1)!;
  eq([r1.state, r1.qbo_id, r1.qbo_name, t1.qbo_id, t1.doc_number, t1.total_amt, t1.total_tax, t1.mismatch, q1.TotalAmt, q1.open, q1.PrivateNote, q1.SyncToken, q1.status, a1.state, a1.blocked_by], ["sent", pid1, "REF-1", pid1, "REF-1", 43.96, null, null, 43.96, 43.96, "IMS refund " + u1, 0, undefined, "queued", r1.id], "done → txn refund ↔ Purchase(DocNumber = reference) · totals match · refund_apply released to queued");
  const l1 = w.logs.filter((l) => l.action === "send" && l.detail?.job_id === r1.id), lc1 = w.logs.filter((l) => l.action === "send_check" && l.detail?.job_id === r1.id);
  eq([l1.length, l1[0].detail?.qbo_id, l1[0].detail?.request_id, l1[0].detail?.kind, lc1.length, lc1.every((l) => String(l.detail?.q ?? "").includes("TxnDate >= ? and TxnDate <= ?")), lc1.map((l) => l.detail?.rows), lc1.map((l) => l.detail?.page)], [1, pid1, r1.request_id, "refund", 3, true, [0, 0, 0], [1, 1, 1]], "write logged with job · qbo id · requestid · checks logged with rows · page · q literals → ? · no rows");
  //    refund_apply: GET purchase 1(있음 · Voided 아님 · 이 환불의 메모 · TotalAmt ≥ 줄) · GET creditmemo 1 → POST payment 1(몸 그대로 · Expense 줄 + CreditMemo 줄 · 계좌 없음) → done(TotalAmt 0 · UnappliedAmt 0) · 장부: RemainingCredit 0 · Purchase 열린 금액 0 · LinkedTxn Payment · SyncToken 오름 · txnOpenBalance 는 note 에
  const cr1 = cmReads(w).length;
  const b2 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply"] }));
  const pp2 = payPosts(w), payId1 = String(a1.qbo_id);
  eq([b2.sent, b2.failed, b2.unknown, purReads(w).length, cmReads(w).length - cr1, pp2.length, JSON.parse(pp2[0].body), new URL(pp2[0].url).pathname.endsWith("/payment"), new URL(pp2[0].url).searchParams.get("requestid"), new URL(pp2[0].url).searchParams.get("operation")],
     [1, 0, 0, 1, 1, 1, a1.body, true, a1.request_id, null], "one purchase read · one credit memo read · one POST payment with the DB body: " + JSON.stringify(b2.jobs));
  const ta1 = w.db.txns.get(u1 + ":apply")!, pay1 = w.it.payments.get(payId1)!;
  eq([a1.state, ta1.qbo_id, ta1.doc_number, ta1.total_amt, ta1.unapplied, ta1.mismatch, pay1.TotalAmt, pay1.UnappliedAmt, pay1.DepositToAccountRef, pay1.Line.length, pay1.PrivateNote, w.it.invoices.get("6401")!.RemainingCredit, q1.open, q1.SyncToken, q1.LinkedTxn, (b2.jobs as Record<string, unknown>[])[0].note],
     ["sent", payId1, "CR-01011 refund", 0, 0, null, 0, 0, undefined, 2, "IMS refund applied " + u1, 0, 0, 1, [{ TxnId: payId1, TxnType: "Payment" }], `QuickBooks open balance before linking: Expense #${pid1} 43.96 → 0 after · CreditMemo #6401 43.96 → 0 after`], "done → txn refund_apply ↔ 0.00 Payment · credit memo used up · purchase open 0 and linked · open balances before linking in the note, no warning [1b2]");

  // ② refund 가드 — (a) RemainingCredit 모자람(크레딧 먼저 · 손 기록 조회 0 · POST 0)
  ledgerCm(w, "6402", "CR-01012", 175.83, 100);
  const CM2: Cm[] = [{ id: "6402", doc: "CR-01012", amt: 175.83 }];
  const u2 = rfUuid(2), r2 = addRf(w, "CR-01012 refund", u2, CM2);
  const g0 = guardQueries(w, "Purchase").length, pp0 = purPosts(w).length;
  const b3 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  eq([b3.failed, r2.state, (r2.last_error ?? "").includes("only 100 left on credit memo CR-01012 (less than the 175.83 this refund pays out)"), guardQueries(w, "Purchase").length - g0, purPosts(w).length - pp0], [1, "failed", true, 0, 0], "credit memo short → failed before any hand-record check or write: " + r2.last_error);
  // (b) 손 Purchase(같은 손님 · 같은 금액 · ± 7 일 안 · PaymentType Check) → failed 「delete it … then Retry」 · POST 0
  w.it.invoices.get("6402")!.RemainingCredit = 175.83;
  plantPur(w, "9901", "2026-11-03", 175.83, "9242", "Refund cheque #1");
  r2.state = "queued";
  const b4 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  eq([b4.failed, r2.state, (r2.last_error ?? "").includes("QuickBooks already shows an expense of 175.83 to this customer on 2026-11-03 (Purchase #9901)"), (r2.last_error ?? "").includes("delete it in QuickBooks, then Retry; if it is right, Skip this job"), guardQueries(w, "Purchase").length - g0, guardQueries(w, "JournalEntry").length, purPosts(w).length - pp0], [1, "failed", true, true, 1, 1, 0], "hand-entered expense found → failed · nothing written: " + r2.last_error);
  // (c) 통과하는 것들 — 다른 손님 · Voided · 다른 IMS 환불(「IMS refund 」 머리 · 이견 3) · 범위 밖(+ 15 일) · 금액 다름 → sent · Purchase 조회에 4 행이 왔다(범위 안 넷)
  w.it.purchases.delete("9901");
  plantPur(w, "9902", "2026-11-03", 175.83, "7190", "Refund cheque #2"); plantPur(w, "9903", "2026-11-03", 0, "9242", "Voided - Refund cheque #3"); plantPur(w, "9904", "2026-11-06", 175.83, "9242", "IMS refund " + rfUuid(99)); plantPur(w, "9905", "2026-11-20", 175.83, "9242", "Refund cheque #5"); plantPur(w, "9906", "2026-11-04", 175.84, "9242", "Refund cheque #6");
  r2.state = "queued";
  const b5 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  const lcP = w.logs.filter((l) => l.action === "send_check" && l.detail?.job_id === r2.id && String(l.detail?.q ?? "").startsWith("select * from Purchase where TxnDate >=")).at(-1);
  eq([b5.sent, r2.state, r2.qbo_id, lcP?.detail?.rows, w.db.txns.get(u2)!.total_amt, w.it.invoices.get("6402")!.RemainingCredit], [1, "sent", String(8000 + w.it.createdN), 5, 175.83, 175.83], "other customer · voided · another IMS refund · out of range · other amount do not block → sent (the credit memo is only consumed by the 0.00 payment)");
  // (d) 줄 CustomerRef 만 있는 손 Purchase(EntityRef 없음)도 잡는다
  ledgerCm(w, "6403", "CR-01013", 50); plantPur(w, "9907", "2026-11-10", 50, null, "cheque to customer", "9242");
  const u5 = rfUuid(5), r5 = addRf(w, "CR-01013 refund", u5, [{ id: "6403", doc: "CR-01013", amt: 50 }]);
  const b6 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  eq([b6.failed, r5.state, (r5.last_error ?? "").includes("(Purchase #9907)")], [1, "failed", true], "line CustomerRef only → still a hit: " + r5.last_error);
  // (e) JournalEntry(손님 Entity 줄 12.5) → failed · 다른 손님의 JE 는 통과
  ledgerCm(w, "6404", "CR-01014", 12.5); w.it.journals.push(je);
  const u6 = rfUuid(6), r6 = addRf(w, "CR-01014 refund", u6, [{ id: "6404", doc: "CR-01014", amt: 12.5 }]);
  const b7 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  eq([b7.failed, r6.state, (r6.last_error ?? "").includes("QuickBooks already shows a journal entry of 12.5 to this customer on 2026-11-04 (JournalEntry #77)")], [1, "failed", true], "hand journal entry → failed: " + r6.last_error);
  w.it.journals.length = 0; w.it.journals.push({ ...je, Id: "78", Line: [{ Amount: 12.5, JournalEntryLineDetail: { PostingType: "Debit", Entity: { Type: "Customer", EntityRef: { value: "1" } } } }] });
  r6.state = "queued";
  const b8 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  eq([b8.sent, r6.state], [1, "sent"], "a journal entry for another customer does not block");
  // (f) RefundReceipt(같은 손님 · 같은 금액) → failed
  ledgerCm(w, "6405", "CR-01015", 9.99); w.it.refundReceipts.push({ Id: "88", TxnDate: "2026-11-06", TotalAmt: 9.99, CustomerRef: { value: "9242" }, PrivateNote: "", DocNumber: "1055" });
  const u7 = rfUuid(7), r7 = addRf(w, "CR-01015 refund", u7, [{ id: "6405", doc: "CR-01015", amt: 9.99 }]);
  const b9 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  eq([b9.failed, r7.state, (r7.last_error ?? "").includes("QuickBooks already shows a refund receipt of 9.99 to this customer on 2026-11-06 (RefundReceipt #88)")], [1, "failed", true], "hand refund receipt → failed: " + r7.last_error);
  w.it.refundReceipts.length = 0;
  // (g) 쪽 넘김 — 첫 쪽 1000 행(다른 손님) → STARTPOSITION 1001 로 한 번 더 → sent · 다섯 쪽이 다 차면 failed 「too many to check」(POST 0)
  const DUMMY = Array.from({ length: 1000 }, (_, i) => ({ Id: "d" + i, TxnDate: "2026-11-01", TotalAmt: 1, EntityRef: { value: "7190", type: "Customer" }, PrivateNote: "", Line: [] }));
  const qOf = (h: Hit) => h.url.includes("/query?") ? (new URL(h.url).searchParams.get("query") ?? "") : "";
  w.it.override.push((h) => /from Purchase where TxnDate >=/i.test(qOf(h)) && /STARTPOSITION 1 /.test(qOf(h)) ? jres(200, { QueryResponse: { Purchase: DUMMY, startPosition: 1, maxResults: 1000 } }, "tid-page1") : null);
  r7.state = "queued"; const gp0 = guardQueries(w, "Purchase").length;
  const b10 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] })); w.it.override.length = 0;
  const gpq = guardQueries(w, "Purchase").slice(gp0);
  eq([b10.sent, r7.state, gpq.length, /STARTPOSITION 1001 MAXRESULTS 1000/.test(sentQuery(gpq[1]) ?? ""), w.logs.filter((l) => l.action === "send_check" && l.detail?.job_id === r7.id && l.detail?.page === 2).length], [1, "sent", 2, true, 1], "a full page → next page with STARTPOSITION 1001 → sent");
  ledgerCm(w, "6406", "CR-01016", 1.5); const u8 = rfUuid(8), r8 = addRf(w, "CR-01016 refund", u8, [{ id: "6406", doc: "CR-01016", amt: 1.5 }]);
  w.it.override.push((h) => /from Purchase where TxnDate >=/i.test(qOf(h)) ? jres(200, { QueryResponse: { Purchase: DUMMY, startPosition: Number((/STARTPOSITION (\d+)/.exec(qOf(h)) ?? [])[1] ?? 1), maxResults: 1000 } }, "tid-pagefull") : null);
  const gp1 = guardQueries(w, "Purchase").length, ppg = purPosts(w).length;
  const b11 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] })); w.it.override.length = 0;
  eq([b11.failed, r8.state, guardQueries(w, "Purchase").length - gp1, (r8.last_error ?? "").includes("more than 5000 Purchase records between 2026-10-29 and 2026-11-12, too many to check"), purPosts(w).length - ppg], [1, "failed", 5, true, 0], "five full pages → failed (narrow by hand) · nothing written: " + r8.last_error);
  // (h) 손 기록 조회 5xx → failed(보내지 않는다) · (i) POST 4xx → failed · POST 5xx → unknown(열쇠) → 다음 send 가 그날 Purchase 조회로 풀기 0 · 1 · 2(완전 일치 · Voided 제외)
  w.it.override.push((h) => /from JournalEntry where TxnDate >=/i.test(qOf(h)) ? jres(503, { Fault: { Error: [{ Message: "Service Unavailable", code: "3001" }], type: "SystemFault" } }, "tid-503") : null);
  r8.state = "queued";
  const b12 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] })); w.it.override.length = 0;
  eq([b12.failed, r8.state, (r8.last_error ?? "").includes("the QuickBooks check for hand-entered refunds (JournalEntry) failed before sending"), purPosts(w).length - ppg], [1, "failed", true, 0], "a failed check → failed · nothing written: " + r8.last_error);
  w.it.override.push((h) => h.method === "POST" && /\/purchase\/?\?/.test(h.url) && h.body.includes(u8) ? jres(400, { Fault: { Error: [{ Message: "Business Validation Error", Detail: "The account is not valid", code: "6000" }], type: "ValidationFault" } }, "tid-6000") : null);
  r8.state = "queued";
  const b13 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] })); w.it.override.length = 0;
  eq([b13.failed, r8.state, (r8.last_error ?? "").includes("6000")], [1, "failed", true], "4xx → failed: " + r8.last_error);
  w.it.override.push((h) => h.method === "POST" && /\/purchase\/?\?/.test(h.url) && h.body.includes(u8) ? jres(503, { Fault: { Error: [{ Message: "Service Unavailable", code: "3001" }], type: "SystemFault" } }, "tid-503") : null);
  r8.state = "queued";
  const b14 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] })); w.it.override.length = 0;
  eq([b14.unknown, r8.state, r8.qbo_name], [1, "unknown", `IMS refund ${u8}|9242|2026-11-05|1.5`], "5xx → unknown with the payment-shaped key");
  const pd0 = purDateQueries(w).length;
  const b15 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  eq([(b15.resolved as Record<string, unknown>[])[0].result, r8.state, purDateQueries(w).length - pd0, sentQuery(purDateQueries(w).at(-1)!)], ["not_found", "unknown", 1, "select * from Purchase where TxnDate = '2026-11-05' MAXRESULTS 1000"], "resolve: no purchase that day with the note → not_found (stays unknown)");
  plantPur(w, "9950", "2026-11-05", 0, "9242", "Voided - IMS refund " + u8); plantPur(w, "9951", "2026-11-05", 1.5, "7190", "IMS refund " + u8); plantPur(w, "9952", "2026-11-05", 1.5, "9242", "IMS refund " + u8 + " x");
  const b16 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  eq([(b16.resolved as Record<string, unknown>[])[0].result, r8.state], ["not_found", "unknown"], "resolve: voided · other customer · note not exact → still not_found");
  plantPur(w, "9953", "2026-11-05", 1.5, "9242", "IMS refund " + u8);
  const b17 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  eq([(b17.resolved as Record<string, unknown>[])[0].result, r8.state, r8.qbo_id, w.db.txns.get(u8)!.qbo_id, w.db.txns.get(u8)!.total_amt, (r8.last_error ?? "").includes("found in QuickBooks by date, customer and note")], ["found", "sent", "9953", "9953", 1.5, true], "resolve: exactly one → done with totals");
  ledgerCm(w, "6407", "CR-01017", 2); const u9 = rfUuid(9), r9 = addRf(w, "CR-01017 refund", u9, [{ id: "6407", doc: "CR-01017", amt: 2 }]); r9.state = "unknown"; r9.qbo_name = `IMS refund ${u9}|9242|2026-11-05|2`;
  plantPur(w, "9954", "2026-11-05", 2, "9242", "IMS refund " + u9); plantPur(w, "9955", "2026-11-05", 2, "9242", "IMS refund " + u9);
  const b18 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  eq([(b18.resolved as Record<string, unknown>[])[0].result, (b18.resolved as Record<string, unknown>[])[0].rows, r9.state], ["ambiguous", 2, "unknown"], "resolve: two → ambiguous (by hand)");
  w.it.purchases.delete("9954"); w.it.purchases.delete("9955"); r9.state = "skipped";
  // (j) 열쇠 결함(손님 없음) → failed · 보내지 않는다
  const u10 = rfUuid(10), r10 = addRf(w, "no customer", u10, [{ id: "6407", doc: "CR-01017", amt: 2 }], "9242", "2026-11-05", null, { lookup: { customer_ref: "", txn_date: "2026-11-05", total_amt: 2, private_note: "IMS refund " + u10 } }); delete r10.body.EntityRef;
  const ppj = purPosts(w).length;
  const b19 = await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  eq([b19.failed, r10.state, (r10.last_error ?? "").includes("carries no QuickBooks customer, date or amount"), purPosts(w).length - ppj], [1, "failed", true, 0], "no customer on the job → failed: " + r10.last_error);

  // ③ refund_apply 가드 — check_lines 결함 · Purchase 못 읽음 · Voided · 메모 다름 · TotalAmt 모자람 · 크레딧 모자람 · 4xx · 5xx → unknown → 풀기(0 · 1) · 열린 금액이 남으면 note 경고
  const pid2 = String(r2.qbo_id), ppa = payPosts(w).length;
  const bad1 = addRfa(w, "CR-01012 refund", u2, pid2, CM2, "9242", "2026-11-05", { check_lines: [{ txn_type: "CreditMemo", credit_number: "CR-01012", qbo_creditmemo_id: "6402", amount: 175.83 }] });
  const c1 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply"] }));
  eq([c1.failed, bad1.state, (bad1.last_error ?? "").includes("1 check line(s) instead of one expense and at least one credit memo"), payPosts(w).length - ppa], [1, "failed", true, 0], "check lines without the expense → failed: " + bad1.last_error);
  bad1.state = "skipped";
  const bad2 = addRfa(w, "CR-01012 refund", u2, "4242", CM2);
  const c2 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply"] }));
  eq([c2.failed, bad2.state, (bad2.last_error ?? "").includes("could not read the expense of refund CR-01012 refund (QuickBooks #4242)")], [1, "failed", true], "purchase not readable → failed: " + bad2.last_error);
  bad2.state = "skipped";
  plantPur(w, "9910", "2026-11-05", 0, "9242", "Voided - IMS refund " + u2);
  const bad3 = addRfa(w, "CR-01012 refund", u2, "9910", CM2);
  const c3 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply"] }));
  eq([c3.failed, bad3.state, (bad3.last_error ?? "").includes("(QuickBooks #9910) is voided in QuickBooks")], [1, "failed", true], "purchase voided → failed: " + bad3.last_error);
  bad3.state = "skipped";
  plantPur(w, "9911", "2026-11-05", 175.83, "9242", "IMS refund " + rfUuid(98));
  const bad4 = addRfa(w, "CR-01012 refund", u2, "9911", CM2);
  const c4 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply"] }));
  eq([c4.failed, bad4.state, (bad4.last_error ?? "").includes(`does not carry the note of refund CR-01012 refund ("IMS refund ${u2}")`)], [1, "failed", true], "purchase of another refund → failed: " + bad4.last_error);
  bad4.state = "skipped";
  plantPur(w, "9912", "2026-11-05", 100, "9242", "IMS refund " + u2);
  const bad5 = addRfa(w, "CR-01012 refund", u2, "9912", CM2);
  const c5 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply"] }));
  eq([c5.failed, bad5.state, (bad5.last_error ?? "").includes("totals 100 (less than 175.83)")], [1, "failed", true], "purchase total short → failed: " + bad5.last_error);
  bad5.state = "skipped";
  w.it.invoices.get("6402")!.RemainingCredit = 10;
  const bad6 = addRfa(w, "CR-01012 refund", u2, pid2, CM2);
  const c6 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply"] }));
  eq([c6.failed, bad6.state, (bad6.last_error ?? "").includes("only 10 left on credit memo CR-01012 (less than 175.83)"), payPosts(w).length - ppa], [1, "failed", true, 0], "credit memo short → failed · nothing written: " + bad6.last_error);
  w.it.invoices.get("6402")!.RemainingCredit = 175.83;
  w.it.override.push((h) => h.method === "POST" && /\/payment\/?\?/.test(h.url) && h.body.includes(u2) ? jres(400, { Fault: { Error: [{ Message: "Business Validation Error", Detail: "x", code: "6000" }], type: "ValidationFault" } }, "tid-6000") : null);
  bad6.state = "queued";
  const c7 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply"] })); w.it.override.length = 0;
  eq([c7.failed, bad6.state, (bad6.last_error ?? "").includes("6000")], [1, "failed", true], "4xx → failed: " + bad6.last_error);
  w.it.override.push((h) => h.method === "POST" && /\/payment\/?\?/.test(h.url) && h.body.includes(u2) ? jres(503, { Fault: { Error: [{ Message: "Service Unavailable", code: "3001" }], type: "SystemFault" } }, "tid-503") : null);
  bad6.state = "queued";
  const c8 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply"] })); w.it.override.length = 0;
  eq([c8.unknown, bad6.state, bad6.qbo_name], [1, "unknown", `IMS refund applied ${u2}|9242|2026-11-05|0`], "5xx → unknown with the payment key");
  const c9 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply"] }));
  eq([(c9.resolved as Record<string, unknown>[])[0].result, bad6.state], ["not_found", "unknown"], "resolve: no 0.00 payment that day with the note → not_found");
  w.it.payments.set("7777", { Id: "7777", SyncToken: 0, TotalAmt: 0, UnappliedAmt: 0, CustomerRef: { value: "9242" }, TxnDate: "2026-11-05", PaymentRefNum: null, PrivateNote: "IMS refund applied " + u2, Line: [], voided: false, DepositToAccountRef: undefined, PaymentMethodRef: undefined });
  const c10 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply"] }));
  eq([(c10.resolved as Record<string, unknown>[])[0].result, bad6.state, bad6.qbo_id, w.db.txns.get(u2 + ":apply")!.qbo_id], ["found", "sent", "7777", "7777"], "resolve: exactly one 0.00 payment with the note → done");
  //    열린 금액이 남는 꼴(Purchase 50 · 환불 43.96 — 이견 2: 보내기 전엔 TotalAmt ≥ 줄만 본다 · 보낸 뒤 txnOpenBalance 50(직전) − 43.96 = 6.04 left 가 note 경고로 · [1b2 이견 3 (나)])
  ledgerCm(w, "6408", "CR-01018", 43.96); const u11 = rfUuid(11); plantPur(w, "9913", "2026-11-05", 50, "9242", "IMS refund " + u11);
  const a11 = addRfa(w, "CR-01018 refund", u11, "9913", [{ id: "6408", doc: "CR-01018", amt: 43.96 }]);
  const c11 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply"] }));
  eq([c11.sent, a11.state, String((c11.jobs as Record<string, unknown>[])[0].note), w.it.purchases.get("9913")!.open], [1, "sent", "QuickBooks open balance before linking: Expense #9913 50 → 6.04 after · CreditMemo #6408 43.96 → 0 after — Expense #9913 6.04 left, check the refund in QuickBooks", 6.04], "open balance left → sent with a warning note (not failed — it stands in QuickBooks) [1b2: computed after = before − amount]");

  // ④ void 둘 — refund_apply_void 먼저(payment?operation=update&include=void · 되돌림: RemainingCredit · Purchase 열린 금액 · LinkedTxn 풀림 · SyncToken 오름) → refund_void(GET purchase → Full update: Id · 읽은 SyncToken · 읽은 Line Amount 0 · 「Voided - 」 · operation 없음 → status Voided → done)
  const av1 = addRfav(w, "CR-01011 refund", u1, payId1, "0");
  const pv0 = payVoidPosts(w).length;
  const d1 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply_void"] }));
  eq([d1.sent, av1.state, payVoidPosts(w).length - pv0, JSON.parse(payVoidPosts(w).at(-1)!.body), ta1.voided_at !== null, pay1.TotalAmt, pay1.voided, w.it.invoices.get("6401")!.RemainingCredit, q1.open, q1.LinkedTxn, q1.SyncToken], [1, "sent", 1, { Id: payId1, SyncToken: "0", sparse: true }, true, 0, true, 43.96, 43.96, [], 2], "zero payment voided → credit memo and purchase open again · purchase SyncToken moved (sandbox: linking and unlinking bump it)");
  const rv1 = addRfv(w, "CR-01011 refund", u1, pid1, "0");   // DB 몸의 SyncToken 0 은 낡았다(지금 2) — EF 는 늘 먼저 읽는다
  const pr0 = purReads(w).length, ppv0 = purPosts(w).length;
  const d2 = await body(await send(w, "JWT-MGR", { kinds: ["refund_void"] }));
  const vpost = purPosts(w).at(-1)!, vbody = JSON.parse(vpost.body) as Record<string, unknown>;
  eq([d2.sent, d2.failed, rv1.state, purReads(w).length - pr0, purPosts(w).length - ppv0, new URL(vpost.url).searchParams.get("operation"), new URL(vpost.url).searchParams.get("requestid"), vbody.Id, vbody.SyncToken, vbody.PrivateNote, vbody.PaymentType, vbody.DocNumber, vbody.sparse, (vbody.Line as Record<string, unknown>[]).map((l) => [l.Id, l.LineNum, l.Amount, l.Description, l.DetailType, JSON.stringify(l.AccountBasedExpenseLineDetail)])],
     [1, 0, "sent", 1, 1, null, rv1.request_id, pid1, "2", "Voided - IMS refund " + u1, "Cash", undefined, undefined, [["1", 1, 0, "Refund of credit note CR-01011", "AccountBasedExpenseLineDetail", JSON.stringify(rfDetail())]]], "Full update void: DB head + Id + SyncToken read (2, not the stale 0) + the lines as read with Amount 0 + Voided note · no operation: " + JSON.stringify(d2.jobs));
  eq([q1.TotalAmt, q1.status, q1.voided, q1.SyncToken, t1.voided_at !== null, t1.sync_token, (d2.jobs as Record<string, unknown>[])[0].note], [0, "Voided", true, 3, true, "3", "SyncToken and lines read from QuickBooks before voiding"], "QuickBooks: amount 0 · status Voided · IMS: txn voided_at · SyncToken 3");
  //    LinkedTxn 에 Payment 가 남아 있으면 failed(이견 4) — 새 환불 r12 · a12 를 보내 둔 뒤 refund_void 만
  ledgerCm(w, "6409", "CR-01019", 5); const CM12: Cm[] = [{ id: "6409", doc: "CR-01019", amt: 5 }]; const u12 = rfUuid(12), r12 = addRf(w, "CR-01019 refund", u12, CM12); const pid12 = nextPurId(w);
  await body(await send(w, "JWT-MGR", { kinds: ["refund"] })); const a12 = addRfa(w, "CR-01019 refund", u12, pid12, CM12); await body(await send(w, "JWT-MGR", { kinds: ["refund_apply"] }));
  eq([r12.state, r12.qbo_id, a12.state, w.it.purchases.get(pid12)!.LinkedTxn.length], ["sent", pid12, "sent", 1], "r12 · a12 standing in QuickBooks");
  const rv12 = addRfv(w, "CR-01019 refund", u12, pid12, null); const ppv1 = purPosts(w).length;
  const d3 = await body(await send(w, "JWT-MGR", { kinds: ["refund_void"] }));
  eq([d3.failed, rv12.state, (rv12.last_error ?? "").includes(`the zero payment #${a12.qbo_id} is still linked to expense #${pid12} — void it first`), purPosts(w).length - ppv1], [1, "failed", true, 0], "zero payment still linked → failed · nothing written: " + rv12.last_error);
  rv12.state = "skipped";
  //    5010(읽은 뒤 누가 또 바꿨다) → 다시 읽어 requestid -2 로 한 번 더 → done
  ledgerCm(w, "6410", "CR-01020", 3); const u13 = rfUuid(13), r13 = addRf(w, "CR-01020 refund", u13, [{ id: "6410", doc: "CR-01020", amt: 3 }]); const pid13 = nextPurId(w);
  await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  const rv13 = addRfv(w, "CR-01020 refund", u13, pid13, "0"); let stale = false;
  w.it.override.push((h) => { if (h.method === "POST" && /\/purchase\/?\?/.test(h.url) && h.body.includes(`"Id":"${pid13}"`) && !stale) { stale = true; w.it.purchases.get(pid13)!.SyncToken++; return jres(400, { Fault: { Error: [{ Message: "Stale Object Error", Detail: "Stale Object Error", code: "5010" }], type: "ValidationFault" } }, "tid-5010"); } return null; });
  const ppv2 = purPosts(w).length, pr2 = purReads(w).length;
  const d4 = await body(await send(w, "JWT-MGR", { kinds: ["refund_void"] })); w.it.override.length = 0;
  const vp2 = purPosts(w).slice(ppv2);
  eq([d4.sent, rv13.state, vp2.length, purReads(w).length - pr2, new URL(vp2[1].url).searchParams.get("requestid"), (JSON.parse(vp2[1].body) as Record<string, unknown>).SyncToken, w.it.purchases.get(pid13)!.status, (rv13.last_error ?? "").includes("stale SyncToken (5010) — re-read and voided again"), r13.state], [1, "sent", 2, 2, rv13.request_id + "-2", "1", "Voided", true, "sent"], "5010 → second read → POST with -2 and the new SyncToken → done: " + rv13.last_error);
  //    status 가 있고 Voided 가 아니면 failed(이견 1 — QBO 는 0 · Voided 메모인데 status 가 다르다) · 그 뒤 Retry 는 「이미 Voided」 로 done(POST 0) · status 없으면 done + note
  ledgerCm(w, "6411", "CR-01021", 4); const u14 = rfUuid(14); addRf(w, "CR-01021 refund", u14, [{ id: "6411", doc: "CR-01021", amt: 4 }]); const pid14 = nextPurId(w);
  await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  w.it.purchaseStatus.set(pid14, "Pending");
  const rv14 = addRfv(w, "CR-01021 refund", u14, pid14, null);
  const d5 = await body(await send(w, "JWT-MGR", { kinds: ["refund_void"] }));
  eq([d5.failed, rv14.state, (rv14.last_error ?? "").includes(`QuickBooks answered status "Pending" instead of Voided for expense #${pid14}`), w.it.purchases.get(pid14)!.TotalAmt, w.db.txns.get(u14)!.voided_at], [1, "failed", true, 0, null], "status other than Voided → failed (a person looks): " + rv14.last_error);
  w.it.purchaseStatus.delete(pid14); rv14.state = "queued"; const ppv3 = purPosts(w).length;
  const d6 = await body(await send(w, "JWT-MGR", { kinds: ["refund_void"] }));
  eq([d6.sent, rv14.state, purPosts(w).length - ppv3, (rv14.last_error ?? "").includes("already voided in QuickBooks (amount 0 · Voided note) — recorded, not sent again"), w.db.txns.get(u14)!.voided_at !== null], [1, "sent", 0, true, true], "retry finds it already voided → done without writing: " + rv14.last_error);
  ledgerCm(w, "6412", "CR-01022", 6); const u15 = rfUuid(15); addRf(w, "CR-01022 refund", u15, [{ id: "6412", doc: "CR-01022", amt: 6 }]); const pid15 = nextPurId(w);
  await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  w.it.purchaseStatus.set(pid15, null);
  const rv15 = addRfv(w, "CR-01022 refund", u15, pid15, null);
  const d7 = await body(await send(w, "JWT-MGR", { kinds: ["refund_void"] })); w.it.purchaseStatus.delete(pid15);
  eq([d7.sent, rv15.state, String((d7.jobs as Record<string, unknown>[])[0].note), w.db.txns.get(u15)!.voided_at !== null], [1, "sent", "SyncToken and lines read from QuickBooks before voiding · no status in the answer — amount 0 and the Voided note are on file", true], "no status in the answer → done + note");
  //    5xx → unknown(qbo_name = Purchase Id) → 다음 send 가 Id 로 읽어 not_voided(그대로) · QBO 쪽이 void 되면 found → done · 줄 0 → failed · 거부(4xx) → failed
  ledgerCm(w, "6413", "CR-01023", 7); const u16 = rfUuid(16); addRf(w, "CR-01023 refund", u16, [{ id: "6413", doc: "CR-01023", amt: 7 }]); const pid16 = nextPurId(w);
  await body(await send(w, "JWT-MGR", { kinds: ["refund"] }));
  const rv16 = addRfv(w, "CR-01023 refund", u16, pid16, null);
  w.it.override.push((h) => h.method === "POST" && /\/purchase\/?\?/.test(h.url) && h.body.includes(`"Id":"${pid16}"`) ? jres(503, { Fault: { Error: [{ Message: "Service Unavailable", code: "3001" }], type: "SystemFault" } }, "tid-503") : null);
  const d8 = await body(await send(w, "JWT-MGR", { kinds: ["refund_void"] })); w.it.override.length = 0;
  eq([d8.unknown, rv16.state, rv16.qbo_name], [1, "unknown", pid16], "5xx → unknown with the purchase id");
  const d9 = await body(await send(w, "JWT-MGR", { kinds: ["refund_void"] }));
  eq([(d9.resolved as Record<string, unknown>[])[0].result, rv16.state], ["not_voided", "unknown"], "resolve: still carries an amount → not_voided (retry by hand)");
  const q16 = w.it.purchases.get(pid16)!; q16.TotalAmt = 0; q16.PrivateNote = "Voided - IMS refund " + u16; q16.voided = true; q16.status = "Voided"; q16.SyncToken = 5;
  const d10 = await body(await send(w, "JWT-MGR", { kinds: ["refund_void"] }));
  eq([(d10.resolved as Record<string, unknown>[])[0].result, rv16.state, w.db.txns.get(u16)!.voided_at !== null, w.db.txns.get(u16)!.sync_token], ["found", "sent", true, "5"], "resolve: voided in QuickBooks → done");
  const u17 = rfUuid(17); plantPur(w, "9920", "2026-11-05", 8, "9242", "IMS refund " + u17).Line = []; w.db.txns.set(u17, { qbo_id: "9920", doc_number: "x", sync_token: "0", total_amt: 8, total_tax: null, mismatch: null, voided_at: null });
  const rv17 = addRfv(w, "no lines", u17, "9920", null); const ppv4 = purPosts(w).length;
  const d11 = await body(await send(w, "JWT-MGR", { kinds: ["refund_void"] }));
  eq([d11.failed, rv17.state, (rv17.last_error ?? "").includes("expense #9920 has no lines in QuickBooks"), purPosts(w).length - ppv4], [1, "failed", true, 0], "no lines read → failed · nothing written: " + rv17.last_error);
  ledgerCm(w, "6414", "CR-01024", 9); const u18 = rfUuid(18); addRf(w, "CR-01024 refund", u18, [{ id: "6414", doc: "CR-01024", amt: 9 }]); const pid18 = nextPurId(w);
  await body(await send(w, "JWT-MGR", { kinds: ["refund"] })); w.it.voidRefuse.add(pid18);
  const rv18 = addRfv(w, "CR-01024 refund", u18, pid18, null);
  const d12 = await body(await send(w, "JWT-MGR", { kinds: ["refund_void"] }));
  eq([d12.failed, rv18.state, (rv18.last_error ?? "").includes("6000"), w.it.purchases.get(pid18)!.TotalAmt, w.db.txns.get(u18)!.voided_at], [1, "failed", true, 9, null], "QuickBooks refuses the update → failed · ledger untouched: " + rv18.last_error);
  //    refund_apply_void 5xx → unknown → Id 로 읽어 not_voided → QBO 쪽 void 뒤 found(결제 void 풀기 길 그대로)
  const av12 = addRfav(w, "CR-01019 refund", u12, String(a12.qbo_id), null);
  w.it.override.push((h) => h.method === "POST" && /\/payment\/?\?/.test(h.url) && new URL(h.url).searchParams.get("include") === "void" && h.body.includes(`"Id":"${a12.qbo_id}"`) ? jres(503, { Fault: { Error: [{ Message: "Service Unavailable", code: "3001" }], type: "SystemFault" } }, "tid-503") : null);
  const d13 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply_void"] })); w.it.override.length = 0; const nameU = av12.qbo_name;
  const d14 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply_void"] }));
  const pay12 = w.it.payments.get(String(a12.qbo_id))!; pay12.TotalAmt = 0; pay12.voided = true; pay12.PrivateNote = "Voided - " + pay12.PrivateNote; pay12.SyncToken++;
  const d15 = await body(await send(w, "JWT-MGR", { kinds: ["refund_apply_void"] }));
  eq([d13.unknown, nameU, (d14.resolved as Record<string, unknown>[])[0].result, (d15.resolved as Record<string, unknown>[])[0].result, av12.state, w.db.txns.get(u12 + ":apply")!.voided_at !== null], [1, String(a12.qbo_id), "not_voided", "found", "sent", true], "refund_apply_void unknown → resolved by id like a payment void");

  // ⑤ cron 62 꼴 kinds 열둘(열쇠 문 없음) → claim p_kinds 열둘 · by_staff null · 모르는 kind 400
  ledgerCm(w, "6415", "CR-01025", 1); const r19 = addRf(w, "CR-01025 refund", rfUuid(19), [{ id: "6415", doc: "CR-01025", amt: 1 }]);
  const rc = await postBody(w, { action: "send", kinds: TWELVE, limit: 9 }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" });
  const bc = await body(rc);
  eq([rc.status, bc.kinds, bc.sent, bc.failed, r19.state, w.db.claimKinds.at(-1), w.logs.filter((l) => l.action === "send").at(-1)?.by_staff ?? null], [200, TWELVE, 1, 0, "sent", TWELVE, null], "cron 62 with twelve kinds: a refund expense in one round · by_staff null");
  const rbad = await postBody(w, { action: "send", kinds: [...TWELVE, "bogus"], limit: 9 }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" });
  eq([rbad.status, String((await body(rbad)).error).includes("kinds must be among")], [400, true], "an unknown kind in the cron body → 400 (nothing sent — 1034)");

  // ⑥ 골라 보내기(첫 실물 꼴) — refund_apply 만 고르면(refund 가 queued) blocked 그대로 · 대신 보내지 않는다(이견 11 · 화면은 둘을 함께 또는 refund 부터) · 둘을 함께 고르면 refund → refund_apply 두 바퀴
  ledgerCm(w, "6416", "CR-01026", 2.5); const CM20: Cm[] = [{ id: "6416", doc: "CR-01026", amt: 2.5 }]; const u20 = rfUuid(20);
  const r20 = addRf(w, "CR-01026 refund", u20, CM20); const pid20 = nextPurId(w); const a20 = addRfa(w, "CR-01026 refund", u20, pid20, CM20); a20.state = "blocked"; a20.blocked_by = r20.id;
  const uidR = "2e3f2e3f-1111-4000-8000-" + String(Number(r20.id.replace("job-", ""))).padStart(12, "0"), uidA = "2e3f2e3f-1111-4000-8000-" + String(Number(a20.id.replace("job-", ""))).padStart(12, "0");
  w.db.jobs.delete(r20.id); r20.id = uidR; w.db.jobs.set(uidR, r20); w.db.jobs.delete(a20.id); a20.id = uidA; a20.blocked_by = uidR; w.db.jobs.set(uidA, a20);
  const np6 = payPosts(w).length, npp6 = purPosts(w).length;
  const e1 = await body(await postBody(w, { action: "send", job_ids: [uidA] }, "JWT-MGR"));
  const rqa = (e1.requested as Record<string, unknown>[])[0];
  eq([e1.mode, rqa.result, a20.state, a20.blocked_by, r20.state, purPosts(w).length - npp6, payPosts(w).length - np6, (e1.needs as unknown[]).length, e1.stopped], ["selected", "not_queued", "blocked", uidR, "queued", 0, 0, 0, "no_progress"], "picked refund_apply alone: stays blocked · the refund expense is not sent on its behalf: " + JSON.stringify(rqa));
  const e2 = await body(await postBody(w, { action: "send", job_ids: [uidR, uidA] }, "JWT-MGR"));
  eq([e2.mode, e2.rounds, e2.sent, e2.failed, r20.state, r20.qbo_id, a20.state, purPosts(w).length - npp6, payPosts(w).length - np6, w.it.invoices.get("6416")!.RemainingCredit, w.it.purchases.get(pid20)!.open], ["selected", 2, 2, 0, "sent", pid20, "sent", 1, 1, 0, 0], "picked both: refund expense in round 1 · zero payment in round 2 · credit memo used up: " + JSON.stringify(e2.requested));

  writesAllowedOnly(w, "㉖"); noLeak(w, "㉖");
  ok(!JSON.stringify({ logs: w.logs, warns: w.warns }).includes("ZZPII"), "no PII in logs");
  ok(!w.logs.some((l) => JSON.stringify(l.detail ?? {}).includes("2026-10-29") || JSON.stringify(l.detail ?? {}).includes("Refund cheque")), "no query literals · no row contents in the call log");
});

// ── 3-3 하루 원가 장 — 가짜 일감(DB qbo_cost_day_body 꼴 · sandbox ② S1 몸) · 도우미 ──
const cdDoc = (date: string, wh = "TOR", rebuild = false) => `COGS-${date.replace(/-/g, "")}-${wh}${rebuild ? "-R" : ""}`;
const cdBody = (date: string, wh: string, debits: [string, number, string | null][], credit: number | null = null): Record<string, unknown> => ({   // debits = [설명, 금액, 손님 Id | null] · #59 Credit 한 줄(없으면 합)
  DocNumber: cdDoc(date, wh), TxnDate: date, PrivateNote: `IMS cost day ${date} ${wh}`,
  Line: [...debits.map(([d, a, cust]) => ({ Description: d, Amount: a, DetailType: "JournalEntryLineDetail", JournalEntryLineDetail: { PostingType: "Debit", AccountRef: { value: "84" }, ...(cust ? { Entity: { Type: "Customer", EntityRef: { value: cust } } } : {}) } })),
    { Description: `Inventory ${wh}`, Amount: credit ?? Math.round(debits.reduce((s, [, a]) => s + a, 0) * 100) / 100, DetailType: "JournalEntryLineDetail", JournalEntryLineDetail: { PostingType: "Credit", AccountRef: { value: "85" } } }] });
const cdCents = (b: Record<string, unknown>) => (b.Line as Record<string, unknown>[]).filter((l) => (l.JournalEntryLineDetail as Record<string, unknown>).PostingType === "Debit").reduce((s, l) => s + Math.round(Number(l.Amount) * 100), 0);
const addCd = (w: World, date: string, wh = "TOR", debits: [string, number, string | null][] = [["SO-20008", 12.34, "61"]], extra: Partial<Job> & { fp_cents?: number } = {}) => {
  const b = cdBody(date, wh, debits), cents = extra.fp_cents ?? cdCents(b), { fp_cents: _f, ...rest } = extra;
  return addJob(w, { kind: "cost_day", ims_id: `${date}|${wh}`, name: cdDoc(date, wh), doc_number: cdDoc(date, wh), body: b, fingerprint: `${cents}|d41d8cd98f00b204e9800998ecf8427e`, lookup: { doc_number: cdDoc(date, wh), txn_date: date, total_amt: cents / 100 }, ...rest });
};
const jePosts = (w: World) => postHits(w).filter((h) => /\/journalentry\/?\?/.test(h.url));
const jeReads = (w: World) => apiHits(w).filter((h) => h.method === "GET" && /\/journalentry\/\d+\?/.test(h.url));
const jeDocQueries = (w: World) => queryHits(w).filter((h) => /from\s+JournalEntry\s+where\s+DocNumber\s*=/i.test(sentQuery(h) ?? ""));
const plantJe = (w: World, doc: string, date: string, debits: [string, number, string | null][], id = String(900 + w.it.journals.length)) => { const b = cdBody(date, "TOR", debits); const v: Record<string, unknown> = { Id: id, SyncToken: "0", DocNumber: doc, TxnDate: date, PrivateNote: "hand", Line: (b.Line as Record<string, unknown>[]).map((l, i) => ({ ...l, Id: String(i) })), TotalAmt: 0, HomeTotalAmt: 0 }; w.it.journals.push(v); return v; };
const doneCalls = (w: World) => w.db.calls.filter((c) => c === "svc:qbo_job_done").length;

Deno.test("㉗ 하루 원가 장 = JournalEntry 보내기(qbo-sync-3-3 · 판정 1092 ~ 1103 · 1112 · sandbox ② S1 ~ S3 · 이견 1 ~ 10 · ⬜1 ~ ⬜8) — 순수(SEND_KINDS 19 · DEFAULT_SEND_KINDS 18 · COST_DAY_KINDS · WRITE_ENTITIES + journalentry · journalDebitCents · fingerprintDebitCents · 열쇠 접기/펴기 · ims_id → DocNumber · DocNumber 제약 꼴 · kindsOf · assertWriteAllowed journalentry 만들기만) · T1 claim → 가드 0 행 → POST journalentry(몸 그대로 · requestid) → 응답 TotalAmt 0 · Line 둘 → done 에 Debit 합 → sent · 지문 다르면 sent + mismatch(942) · T2 가드 1 행 → POST 0 · unknown(열쇠 「<doc>|<센트>」 · 글) → 다음 send 풀기: 금액 같음 done · 다름 unknown 그대로 + 1112 글 · 조회 실패 failed · T3 POST 끊김 · 5xx · 몸 없음 · 6140 → unknown → 풀기 0 not_found · 1 같음 done · 1 다름 unknown · qbo_name null + 1 행 unknown · 2 행 ambiguous · T4 kindsOf(undefined) 에 cost_day 없음 · cron 61 꼴 · cron 62 열둘은 집지 않음 · [cost_day, customer] 받음 · sendPicked 가 잡음 · T5 쓰기 꼴 · T6 needs 손님 → 같은 sendPicked 호출에서 손님 먼저 → 장 · cron 길 호출 셋 · 조회 행 · 손님 이름 기록 0", async () => {
  // T0 순수
  eq([[...SEND_KINDS].length, [...SEND_KINDS].slice(18), [...DEFAULT_SEND_KINDS].length, [...DEFAULT_SEND_KINDS].includes("cost_day"), [...DEFAULT_SEND_KINDS], [...COST_DAY_KINDS], [...WRITE_ENTITIES].slice(6)],
     [19, ["cost_day"], 18, false, [...SEND_KINDS].slice(0, 18), ["cost_day"], ["journalentry"]], "SEND_KINDS 19 · DEFAULT 18 = the old 18 in order · WRITE_ENTITIES + journalentry");
  const s1 = { Id: "197", SyncToken: "0", DocNumber: "COGS-20261102-TOR-R", TotalAmt: 0, HomeTotalAmt: 0, Line: [{ Id: "0", Amount: 12.34, JournalEntryLineDetail: { PostingType: "Debit", AccountRef: { value: "84" }, Entity: { Type: "Customer", EntityRef: { value: "61", name: "ZZPII" } } } }, { Id: "1", Amount: 12.34, JournalEntryLineDetail: { PostingType: "Credit", AccountRef: { value: "85" } } }] };   // ② S1 응답 꼴
  eq([journalDebitCents(s1), journalDebitCents({ ...s1, Line: [...s1.Line, { Amount: "0.01", JournalEntryLineDetail: { PostingType: "Debit" } }, { Amount: 5, JournalEntryLineDetail: {} }] }), journalDebitCents({ Id: "1", TotalAmt: 0 }), journalDebitCents(null), journalDebitCents({ Line: [] })], [1234, 1235, null, null, 0], "journalDebitCents: Debit lines only · cents · string amount · no Line → null · empty → 0");
  eq([fingerprintDebitCents("1234|d41d8cd98f00b204e9800998ecf8427e"), fingerprintDebitCents("0|x"), fingerprintDebitCents(null), fingerprintDebitCents("abc"), fingerprintDebitCents("12.5|x")], [1234, 0, null, null, null], "fingerprintDebitCents = the front field of the DB fingerprint");
  eq([costDayKeyOf("COGS-20261102-TOR", 1234), costDayKeyOf("COGS-20261102-TOR", null), parseCostDayKey("COGS-20261102-TOR|1234"), parseCostDayKey("COGS-20261102-EDM-R"), parseCostDayKey("COGS-20261102-TOR|12.5"), parseCostDayKey("COGS-2026110-TOR|1"), parseCostDayKey("a|b|c"), parseCostDayKey(null), parseCostDayKey("60007")],
     ["COGS-20261102-TOR|1234", "COGS-20261102-TOR", { doc: "COGS-20261102-TOR", cents: 1234 }, { doc: "COGS-20261102-EDM-R", cents: null }, null, null, null, null, null], "cost day key: <DocNumber>|<cents> · split is safe (DocNumber shape has no |)");
  eq([costDayDocOfImsId("2026-11-02|TOR"), costDayDocOfImsId("2026-10-31|EDM|rebuild"), costDayDocOfImsId("2026-11-02|YYZ"), costDayDocOfImsId("x"), costDayDocOfImsId(null), COST_DAY_DOC_RE.test("COGS-20261102-TOR"), COST_DAY_DOC_RE.test("COGS-20261102-EDM-R"), COST_DAY_DOC_RE.test("COGS-20261102-TOR|1")], ["COGS-20261102-TOR", "COGS-20261031-EDM-R", null, null, null, true, true, false], "ims_id → DocNumber · DocNumber shape 17 · 19 chars");
  eq([kindsOf(undefined).includes("cost_day"), kindsOf(null).includes("cost_day"), kindsOf(["cost_day", "customer", "cost_day"]), kindsOf(["cost_day"])], [false, false, ["cost_day", "customer"], ["cost_day"]], "kindsOf: default leaves cost_day out · named in → in");
  const base = "https://quickbooks.api.intuit.com/v3/company/123";
  assertWriteAllowed("POST", `${base}/journalentry?requestid=r1&minorversion=75`, { DocNumber: "COGS-20261102-TOR", Line: [] });
  const refusedJe = (u: string, b: unknown, why: string) => { let m = ""; try { assertWriteAllowed("POST", u, b); } catch (e) { m = (e as Error).message; } ok(m.startsWith("refusing"), why + " should be refused: " + (m || "(allowed)")); return m; };
  ok(refusedJe(`${base}/journalentry?requestid=r1`, { Id: "197", SyncToken: "0" }, "JE with Id").includes("only ever created, never updated, voided or deleted"), "journalentry create only (body Id refused)");
  refusedJe(`${base}/journalentry?operation=void&requestid=r1`, {}, "JE operation=void"); refusedJe(`${base}/journalentry?operation=update&include=void&requestid=r1`, {}, "JE update&include=void"); refusedJe(`${base}/journalentry?operation=delete&requestid=r1`, {}, "JE delete"); refusedJe(`${base}/journalentry?include=void&requestid=r1`, {}, "JE include"); refusedJe(`${base}/journalentry`, {}, "JE no requestid");
  assertWriteAllowed("POST", `${base}/purchase?requestid=r1`, { Id: "1", SyncToken: "0", PrivateNote: "Voided - x", Line: [{ Amount: 0 }] });   // 다른 엔티티의 몸 검사는 그대로(2e-3-2-1b)

  const w = world(); connect(w); w.db.keys["JWT-MGR"] = "qbo";
  const TWELVE = ["payment", "payment_void", "credit_apply", "credit_apply_void", "opening_credit", "opening_credit_void", "opening_apply", "opening_apply_void", "refund", "refund_void", "refund_apply", "refund_apply_void"];
  // T1 — claim(p_kinds [cost_day]) → 가드 조회 0 행 → POST journalentry(몸 = DB 몸 그대로 · requestid · operation 없음) → 응답 TotalAmt 0 · Line 둘 → done p_total_amt = Debit 합 12.34 → sent · mismatch null · qbo_name = DocNumber(열쇠 꼴 아님)
  const j1 = addCd(w, "2026-11-02");
  const b1 = await body(await send(w, "JWT-MGR", { kinds: ["cost_day"] }));
  eq([b1.claimed, b1.sent, b1.failed, b1.unknown, b1.mismatch, b1.kinds, w.db.claimKinds.at(-1), jeDocQueries(w).length, jePosts(w).length, jeReads(w).length], [1, 1, 0, 0, 0, ["cost_day"], ["cost_day"], 1, 1, 0], "T1 one cost day sent: " + JSON.stringify(b1.jobs));
  const p1 = jePosts(w)[0], u1 = new URL(p1.url);
  eq([u1.pathname.endsWith("/journalentry"), u1.searchParams.get("requestid"), u1.searchParams.get("operation"), u1.searchParams.get("include"), JSON.parse(p1.body)], [true, j1.request_id, null, null, cdBody("2026-11-02", "TOR", [["SO-20008", 12.34, "61"]])], "T1 POST journalentry with the job request_id · body as the DB built it");
  eq(sentQuery(jeDocQueries(w)[0]), "select Id, DocNumber, SyncToken, TotalAmt from JournalEntry where DocNumber = 'COGS-20261102-TOR' MAXRESULTS 100", "T1 guard query shape");
  const je1 = w.it.journals.at(-1)!, t1 = w.db.txns.get("2026-11-02|TOR")!;
  eq([je1.TotalAmt, je1.HomeTotalAmt, j1.state, j1.qbo_id, j1.qbo_name, t1.qbo_id, t1.doc_number, t1.sync_token, t1.total_amt, t1.total_tax, t1.mismatch, t1.fingerprint, j1.warning], [0, 0, "sent", String(je1.Id), "COGS-20261102-TOR", String(je1.Id), "COGS-20261102-TOR", "0", 12.34, null, null, "1234|d41d8cd98f00b204e9800998ecf8427e", null], "T1 QBO answers TotalAmt 0 · done carries the Debit sum 12.34 · no mismatch · qbo_name is the DocNumber");
  const sl1 = w.logs.filter((l) => l.action === "send").at(-1)!, ck1 = w.logs.filter((l) => l.action === "send_check").at(-1)!;
  eq([sl1.detail?.job_id, sl1.detail?.qbo_id, sl1.detail?.request_id, "operation" in (sl1.detail ?? {}), ck1.detail?.rows, String(ck1.detail?.q).includes("'")], [j1.id, String(je1.Id), j1.request_id, false, 0, false], "T1 logs: write detail = job · id · request · check detail = rows · masked q");
  // T1b — 지문(1300)과 Debit 합(1234)이 다르면 sent + mismatch(DB 942 글)
  const j1b = addCd(w, "2026-11-03", "TOR", [["SO-20009", 12.34, "61"]], { fp_cents: 1300 });
  const b1b = await body(await send(w, "JWT-MGR", { kinds: ["cost_day"] }));
  eq([b1b.sent, b1b.mismatch, j1b.state, (w.db.txns.get("2026-11-03|TOR")!.mismatch ?? "").startsWith("QuickBooks total 12.34 differs from IMS 13.00"), (j1b.warning ?? "").includes("(942)")], [1, 1, "sent", true, true], "T1b Debit sum ≠ fingerprint → sent + mismatch: " + j1b.warning);
  // T2 — 가드 1 행(QBO 에 같은 DocNumber 가 이미 있다 · S2: QBO 는 막지 않는다) → POST 0 · unknown(열쇠 「<doc>|<센트>」 · 글에 Id · resolve 둘 · 「then Retry」 없음) → 다음 send 풀기: 금액 같음 → GET 1 → done(sent · qbo_name 되돌림)
  plantJe(w, "COGS-20261104-TOR", "2026-11-04", [["SO-20010", 12.34, "61"]], "197");
  const j2 = addCd(w, "2026-11-04"); const np0 = jePosts(w).length;
  const b2 = await body(await send(w, "JWT-MGR", { kinds: ["cost_day"] }));
  eq([b2.claimed, b2.unknown, b2.sent, jePosts(w).length - np0, j2.state, j2.qbo_name, (j2.last_error ?? "").includes("not sent — QuickBooks already has journal entry #197 with DocNumber COGS-20261104-TOR"), (j2.last_error ?? "").includes("if it is this cost day, resolve it as in_qbo with that Id; if not, remove it in QuickBooks, then resolve not_in_qbo"), (j2.last_error ?? "").includes("Retry")], [1, 1, 0, 0, "unknown", "COGS-20261104-TOR|1234", true, true, false], "T2 guard hit → no POST · unknown with key and text: " + j2.last_error);
  const d0 = doneCalls(w), nr0 = jeReads(w).length;
  const b2r = await body(await send(w, "JWT-MGR", { kinds: ["cost_day"] }));
  const res2 = (b2r.resolved as Record<string, unknown>[]).find((x) => x.job_id === j2.id)!;
  eq([res2.result, res2.qbo_id, j2.state, j2.qbo_id, j2.qbo_name, doneCalls(w) - d0, jeReads(w).length - nr0, w.db.txns.get("2026-11-04|TOR")!.total_amt, w.db.txns.get("2026-11-04|TOR")!.mismatch, (j2.last_error ?? "").includes("found in QuickBooks by DocNumber with the same debits")], ["found", "197", "sent", "197", "COGS-20261104-TOR", 1, 1, 12.34, null, true], "T2 next send: 1 row · same debits → read once → done · qbo_name back to the DocNumber: " + JSON.stringify(res2));
  // T2b — 가드 1 행인데 금액이 다르다(QBO 12.34 · 이 장 15.00) → unknown → 다음 send 는 done 하지 않는다(1112 글 · done 0 · 상태 그대로)
  plantJe(w, "COGS-20261105-TOR", "2026-11-05", [["SO-20011", 12.34, "61"]], "198");
  const j2b = addCd(w, "2026-11-05", "TOR", [["SO-20011", 15, "61"]]);
  await send(w, "JWT-MGR", { kinds: ["cost_day"] });
  eq([j2b.state, j2b.qbo_name], ["unknown", "COGS-20261105-TOR|1500"], "T2b guard hit → unknown with the expected cents");
  const d1 = doneCalls(w);
  const b2b = await body(await send(w, "JWT-MGR", { kinds: ["cost_day"] }));
  const res2b = (b2b.resolved as Record<string, unknown>[]).find((x) => x.job_id === j2b.id)!;
  eq([res2b.result, res2b.qbo_id, res2b.qbo_debit, res2b.expected_debit, res2b.message, j2b.state, j2b.qbo_name, doneCalls(w) - d1, b2b.claimed],
     ["amount_differs", "198", 12.34, 15, "QuickBooks JournalEntry #198 with DocNumber COGS-20261105-TOR has debits 12.34 but this cost day expects 15.00 — not recorded. Check it in QuickBooks: if it is right, resolve in_qbo with that Id; if not, remove it there, then resolve not_in_qbo", "unknown", "COGS-20261105-TOR|1500", 0, 0], "T2b 1112: debits differ → not recorded · unknown stays · done 0");
  // T2c — 가드 조회 실패(5xx) → failed 「not sent」 · POST 0
  const j2c = addCd(w, "2026-11-06"); w.it.override.push((h) => h.url.includes("/query?") && (sentQuery(h) ?? "").includes("COGS-20261106-TOR") ? jres(503, {}, "tid-503") : null);
  const np1 = jePosts(w).length;
  const b2c = await body(await send(w, "JWT-MGR", { kinds: ["cost_day"] })); w.it.override.length = 0;
  eq([b2c.failed, jePosts(w).length - np1, j2c.state, (j2c.last_error ?? "").startsWith("not sent — the DocNumber check failed before sending")], [1, 0, "failed", true], "T2c check failed → failed · nothing written: " + j2c.last_error);
  // T3 — POST 끊김 · 503 · 2xx 몸 없음 · 6140 → unknown(열쇠) → 다음 send 풀기: 0 행 not_found · 1 행 같음 done · 1 행 다름 unknown(1112) · 2 행 ambiguous · qbo_name null + 1 행 → unknown(글)
  const j3a = addCd(w, "2026-11-07"), j3b = addCd(w, "2026-11-08"), j3c = addCd(w, "2026-11-09"), j3d = addCd(w, "2026-11-10"), j3e = addCd(w, "2026-11-11"), j3f = addCd(w, "2026-11-12");
  w.it.override.push((h) => h.method === "POST" && h.body.includes("COGS-20261107-TOR") ? new Error("connection reset by peer") : null);
  w.it.override.push((h) => h.method === "POST" && h.body.includes("COGS-20261108-TOR") ? jres(503, { Fault: { Error: [{ Message: "Service Unavailable", code: "3001" }], type: "SystemFault" } }, "tid-503") : null);
  w.it.override.push((h) => h.method === "POST" && h.body.includes("COGS-20261109-TOR") ? jres(200, { time: "x" }, "tid-empty") : null);
  w.it.override.push((h) => h.method === "POST" && h.body.includes("COGS-20261110-TOR") ? jres(400, { Fault: { Error: [{ Message: "Duplicate Document Number Error", code: "6140" }], type: "ValidationFault" } }, "tid-6140") : null);
  w.it.override.push((h) => h.method === "POST" && (h.body.includes("COGS-20261111-TOR") || h.body.includes("COGS-20261112-TOR")) ? jres(503, {}, "tid-503") : null);
  const s0 = w.sleeps.length;
  const b3 = await body(await send(w, "JWT-MGR", { kinds: ["cost_day"], limit: 10 })); w.it.override.length = 0;
  eq([b3.claimed, b3.unknown, b3.failed, b3.sent, w.sleeps.length - s0, [j3a, j3b, j3c, j3d, j3e, j3f].map((j) => j.state + ":" + j.qbo_name), (j3a.last_error ?? "").includes("unreachable"), (j3c.last_error ?? "").includes("without the created JournalEntry"), (j3d.last_error ?? "").includes("duplicate DocNumber (6140)")],
     [6, 6, 0, 0, 0, ["unknown:COGS-20261107-TOR|1234", "unknown:COGS-20261108-TOR|1234", "unknown:COGS-20261109-TOR|1234", "unknown:COGS-20261110-TOR|1234", "unknown:COGS-20261111-TOR|1234", "unknown:COGS-20261112-TOR|1234"], true, true, true], "T3 six unknown with keys · no retry sleep: " + JSON.stringify(b3.jobs));
  plantJe(w, "COGS-20261108-TOR", "2026-11-08", [["SO-20012", 12.34, "61"]], "301");                               // (b) 1 행 같음 → done
  plantJe(w, "COGS-20261109-TOR", "2026-11-09", [["SO-20013", 12.33, "61"]], "302");                               // (c) 1 행 다름 → 1112
  plantJe(w, "COGS-20261110-TOR", "2026-11-10", [["SO-20014", 12.34, "61"]], "303"); plantJe(w, "COGS-20261110-TOR", "2026-11-10", [["SO-20014", 12.34, "61"]], "304");   // (d) 2 행 → ambiguous
  j3e.qbo_name = null;                                                                                            // (e) stale sending → unknown 꼴(claim 이 열쇠 없이 unknown 으로) · ims_id 로 DocNumber 만
  plantJe(w, "COGS-20261111-TOR", "2026-11-11", [["SO-20015", 12.34, "61"]], "305");
  w.it.journals.push({ Id: "306", SyncToken: "0", DocNumber: "COGS-20261112-TOR", TxnDate: "2026-11-12", PrivateNote: "no lines", TotalAmt: 0 });   // (f) 1 행 · Line 칸 없음(짐작 밖) → needs_hand(빈 Line [] 은 Debit 0 = 금액 다름으로 간다)
  const d2 = doneCalls(w);
  const b3r = await body(await send(w, "JWT-MGR", { kinds: ["cost_day"] }));
  const r3 = (id: string) => (b3r.resolved as Record<string, unknown>[]).find((x) => x.job_id === id)!;
  eq([r3(j3a.id).result, j3a.state, String(r3(j3a.id).message).includes("no journal entry with number COGS-20261107-TOR") && String(r3(j3a.id).message).includes("resolve the cost day as not_in_qbo")], ["not_found", "unknown", true], "T3(a) 0 rows → not_found · stays unknown");
  eq([r3(j3b.id).result, j3b.state, j3b.qbo_id, j3b.qbo_name, w.db.txns.get("2026-11-08|TOR")!.total_amt], ["found", "sent", "301", "COGS-20261108-TOR", 12.34], "T3(b) 1 row · same debits → done");
  eq([r3(j3c.id).result, r3(j3c.id).qbo_debit, r3(j3c.id).expected_debit, j3c.state, j3c.qbo_name, String(r3(j3c.id).message).startsWith("QuickBooks JournalEntry #302 with DocNumber COGS-20261109-TOR has debits 12.33 but this cost day expects 12.34 — not recorded.")], ["amount_differs", 12.33, 12.34, "unknown", "COGS-20261109-TOR|1234", true], "T3(c) 1 row · different debits → unknown stays (1112)");
  eq([r3(j3d.id).result, r3(j3d.id).count, j3d.state, String(r3(j3d.id).message)], ["ambiguous", 2, "unknown", "QuickBooks has 2 journal entrys with number COGS-20261110-TOR (#304, #303) — remove the extra in QuickBooks, then resolve the cost day as in_qbo with the one left"], "T3(d) 2 rows → ambiguous · stays unknown");
  eq([r3(j3e.id).result, r3(j3e.id).qbo_id, j3e.state, String(r3(j3e.id).message)], ["needs_hand", "305", "unknown", "QuickBooks has journal entry #305 with number COGS-20261111-TOR but the expected debit is not on the job — check it in QuickBooks, then resolve the cost day as in_qbo (with #305) or not_in_qbo by hand"], "T3(e) no key (stale sending) → DocNumber from ims_id · 1 row → by hand · no done (1112)");
  eq([r3(j3f.id).result, j3f.state, String(r3(j3f.id).message).includes("came back without lines")], ["needs_hand", "unknown", true], "T3(f) 1 row without lines → by hand");
  eq([doneCalls(w) - d2, b3r.claimed], [1, 0], "T3 exactly one done across six unknowns");
  // T4 — kinds: cron 61 꼴(kinds 없음 · cron 열쇠)은 DEFAULT 18 로 claim → cost_day 는 queued 그대로 · cron 62 열둘도 · sendPicked(job_ids)는 19 로 잡아 보낸다
  const j4 = addCd(w, "2026-11-13");
  const c61 = await body(await postBody(w, { action: "send", limit: 15 }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" }));
  eq([c61.ok, c61.kinds, w.db.claimKinds.at(-1), c61.claimed, j4.state], [true, [...DEFAULT_SEND_KINDS], [...DEFAULT_SEND_KINDS], 0, "queued"], "T4 cron 61 shape (no kinds) → default 18 → the cost day is not taken");
  const c62 = await body(await postBody(w, { action: "send", kinds: TWELVE, limit: 15 }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" }));
  eq([c62.kinds, w.db.claimKinds.at(-1), c62.claimed, j4.state], [TWELVE, TWELVE, 0, "queued"], "T4 cron 62 twelve → not taken");
  eq((await send(w, "JWT-MGR", { kinds: ["cost_day", "bogus"] })).status, 400, "T4 unknown kind → 400");
  const uid = (j: Job) => { const id = "33333333-3333-4333-8333-" + j.id.replace("job-", "").padStart(12, "0"); w.db.jobs.delete(j.id); j.id = id; w.db.jobs.set(id, j); return id; };
  const j4Id = uid(j4);
  const bp = await body(await pickSend(w, [j4Id], "JWT-MGR"));
  const rq = (bp.requested as Record<string, unknown>[])[0];
  eq([bp.mode, (bp.kinds as string[]).length, w.db.claimKinds.at(-1)!.includes("cost_day"), bp.sent, rq.result, rq.round, j4.state, j4.qbo_name], ["selected", 19, true, 1, "sent", 1, "sent", "COGS-20261113-TOR"], "T4 sendPicked takes the cost day (19 kinds): " + JSON.stringify(rq));
  // T6 — needs 손님(DB 몸이 Entity 짝 없는 손님을 needs 로) → sendPicked: 바퀴 1 blocked + need customer · 바퀴 2 손님 POST · 바퀴 3 장 POST → sent
  const j6 = addCd(w, "2026-11-14", "TOR", [["SO-20020", 7.5, null]], { needs: [{ kind: "customer", ims_id: "cust-N", name: "customer of SO-20020" }] }); const j6Id = uid(j6);
  const nc0 = postHits(w).filter((h) => /\/customer\/?\?/.test(h.url)).length, nj0 = jePosts(w).length;
  const b6 = await body(await pickSend(w, [j6Id], "JWT-MGR"));
  const rq6 = (b6.requested as Record<string, unknown>[])[0], nd6 = b6.needs as Record<string, unknown>[];
  eq([b6.rounds, b6.sent, b6.blocked, rq6.result, rq6.round, nd6.map((x) => x.kind + ":" + x.result + ":" + x.round), postHits(w).filter((h) => /\/customer\/?\?/.test(h.url)).length - nc0, jePosts(w).length - nj0, j6.state, w.db.links.some((l) => l.ims_id === "cust-N")], [3, 1, 0, "sent", 3, ["customer:sent:2"], 1, 1, "sent", true], "T6 picked: customer first (round 2) → cost day (round 3): " + JSON.stringify({ rq6, nd6 }));
  const custPost = postHits(w).filter((h) => /\/customer\/?\?/.test(h.url)).at(-1)!, jePost = jePosts(w).at(-1)!;
  ok(w.it.hits.indexOf(custPost) < w.it.hits.indexOf(jePost), "T6 customer POST precedes the journal entry POST");
  // T6b — cron 길 {kinds:[cost_day, customer]} 호출 셋: ① blocked + need 손님 세움 ② 손님 ③ 풀린 장
  const j6b = addCd(w, "2026-11-15", "TOR", [["SO-20021", 7.5, null]], { needs: [{ kind: "customer", ims_id: "cust-M", name: "customer of SO-20021" }] });
  const cron = async () => body(await postBody(w, { action: "send", kinds: ["cost_day", "customer"], limit: 15 }, null, { "x-ims-cron-key": "cron-ZZSECRET-0123456789abcdef" }));
  const k1 = await cron(); const needJob = [...w.db.jobs.values()].find((x) => x.kind === "customer" && x.ims_id === "cust-M")!;
  eq([k1.kinds, k1.claimed, k1.blocked_for_needs, k1.sent, j6b.state, j6b.blocked_by, needJob?.state], [["cost_day", "customer"], 1, 1, 0, "blocked", needJob?.id, "queued"], "T6b call 1: cost day blocked · customer job queued");
  const k2 = await cron();
  eq([k2.claimed, k2.sent, needJob.state, j6b.state], [1, 1, "sent", "blocked"], "T6b call 2: the customer goes");
  const k3 = await cron();
  eq([k3.unblocked, k3.claimed, k3.sent, j6b.state, j6b.qbo_name], [1, 1, 1, "sent", "COGS-20261115-TOR"], "T6b call 3: the cost day is unblocked and goes: " + JSON.stringify({ err: j6b.last_error, jobs: k3.jobs }));
  // T5 · 누출 — 쓰기 꼴(journalentry 만들기만) · 조회 행 · 손님 이름(S3 Entity name) · 토큰 0
  writesAllowedOnly(w, "㉗"); noLeak(w, "㉗");
  ok(!JSON.stringify({ logs: w.logs, warns: w.warns }).includes("ZZPII"), "㉗ customer names from JournalEntry rows never reach call_log or warn");
  ok(w.logs.filter((l) => l.action === "send_check").every((l) => !("Line" in (l.detail ?? {})) && !JSON.stringify(l.detail ?? {}).includes("Amount")), "㉗ check logs carry rows · q only (no JournalEntry rows)");
});
