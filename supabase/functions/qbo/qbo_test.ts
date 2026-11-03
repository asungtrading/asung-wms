// deno test supabase/functions/qbo/qbo_test.ts — Intuit · DB · 네트워크 무접촉(가짜 fetch · 가짜 DB 창구 열둘 + qbo_last_error_set) · qbo-1b ① ~ ⑩ + ⓪ 순수 함수 · ⑪ 회사 이름 저장 거부의 흔적(qbo-1c 뒤 · 판단 4)
//   qbo-read-1(2026-11-01 · 판정 933): ⑫ query · ⑬ read + 읽기 전용 요청 검사 — 가짜 Intuit 에 /query · /<entity>/<id> · /preferences 길(QueryResponse 꼴 · SyncToken · Customer 연락처 칸 포함)
//   가짜 DB 는 20261029160000(qbo-1a) 창구의 거부 글 · 반환 키를 그대로 흉내 낸다(state 10 분 · 한 번 · realm 고정 · 임대 · 판 번호 · needs_reconnect 거부 · mark 의 mailed = connected 에서 바뀔 때만)
//   qbo-sync-1b(2026-11-01 · 판정 934): ⑭ pull — 가짜 DB 에 qbo_pull_begin · qbo_entity_upsert · qbo_pull_finish(20261101210000 의 거부 글 · 반환 키 그대로) · 쪽 1000 은 override 로 · 기존 ⓪ ~ ⑬ 무변
//   ⚠️ 모든 비밀 · 토큰 가짜 값에 ZZSECRET 표식 — 응답 · 기록 · warn 어디에도 그 표식이 없어야 한다(⑨ + 모든 시험 끝)
import { kindsOf, paymentKeyOf, parsePaymentKey, PAYMENT_KINDS, UPDATE_VOID_ENTITIES, isVoidedPayment, paymentsByDateQueryText, ACCESS_EXPIRES_DEFAULT_S, ACTIONS, ADMIN_ACTIONS, assertReadOnlyRequest, assertWriteAllowed, authorizeUrl, classifyWrite, CRON_ACTIONS, DUPLICATE_DOCNUMBER_CODES, DUPLICATE_NAME_CODE, faultCode, invoiceTotals, SEND_KINDS, STALE_OBJECT_CODE, KEY_ACTIONS, PII_ENTITIES, REQUESTID_MAX, SEND_LIMIT_MAX, SEND_PICK_MAX, SEND_PICK_ROUNDS, SEND_PICK_BUDGET_MS, SEND_PICK_PARALLEL, sqlQuote, WRITE_ENTITIES, MAXRESULTS_MAX, parseQuery, QboError, queryForLog, QUERY_ENTITIES, RESPONSE_MAX_BYTES, stripPii, callbackLocation, PII_FIELDS, PULL_ENTITIES, PULL_FIELDS, PULL_NO_ACTIVE_FILTER, PULL_PAGE, pullQueryText, type CallbackWhy, DISCOVERY_TTL_MS, DiscoveryCache, handle, intuitErrorText, isCallbackPath, isRetryable, needsReconnect, newStateRaw, parseDiscovery, parseTokenResponse, redirectUriOf, RpcError, scrub, SETTINGS_URL, sha256Hex, type Deps, type LogRow } from "../_shared/qbo.ts";

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
type Inv = { Id: string; DocNumber: string; SyncToken: number; TotalAmt: number; TotalTax: number; voided: boolean; CustomerRef: unknown; ent?: "Invoice" | "CreditMemo"; Balance?: number };   // 2e-1c: Balance(없으면 TotalAmt) — 결제가 줄인다
type Pay = { Id: string; SyncToken: number; TotalAmt: number; UnappliedAmt: number; CustomerRef: unknown; TxnDate: string; PaymentRefNum: string | null; PrivateNote: string; Line: Record<string, unknown>[]; voided: boolean; DepositToAccountRef: unknown; PaymentMethodRef: unknown };   // 2e-1c 가짜 Payment(A-1 실물 꼴)   // 2c1: ent 없으면 Invoice · 가짜 장부 하나에 둘 다
type Intuit = { hits: Hit[]; tokenN: number; override: ((h: Hit) => Response | Error | null)[]; dupNames: Set<string>; createdN: number; created: Created[]; invoices: Map<string, Inv>; dupDoc: Set<string>; voidRefuse: Set<string>; taxOverride: Map<string, number>; payments: Map<string, Pay> };   // [2e-1c payments]   // 2b2: invoices = 가짜 장부(Id → 인보이스) · dupDoc 는 6140 · voidRefuse 는 void 400 · taxOverride 는 QBO 가 세금을 다르게 셈한 꼴(mismatch)   // 2a′: 가짜 쓰기 — dupNames 에 있으면 6240 · created 에 쌓인다(이름 조회가 찾는다)
const jres = (status: number, body: unknown, tid = "tid-" + status) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", intuit_tid: tid } });
function intuitFake(): { it: Intuit; fetch: Deps["fetch"] } {
  const it: Intuit = { hits: [], tokenN: 0, override: [], dupNames: new Set(), createdN: 0, created: [], invoices: new Map(), dupDoc: new Set(), voidRefuse: new Set(), taxOverride: new Map(), payments: new Map() };
  const invRow = (v: Inv) => ({ Id: v.Id, DocNumber: v.DocNumber, SyncToken: String(v.SyncToken), TotalAmt: v.TotalAmt, TxnTaxDetail: { TotalTax: v.TotalTax }, CustomerRef: v.CustomerRef, Balance: v.Balance ?? v.TotalAmt, BillAddr: { Line1: "ZZPII" }, BillEmail: { Address: "ZZPII@example.invalid" }, PrivateNote: v.voided ? "Voided" : "Customer Reference: x", domain: "QBO", sparse: false });
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
        for (const l of v.Line) { const inv = it.invoices.get(String(((((l.LinkedTxn ?? []) as Record<string, unknown>[])[0] ?? {}) as Record<string, unknown>).TxnId ?? "")); if (inv) inv.Balance = Math.round(((inv.Balance ?? inv.TotalAmt) + Number(l.Amount ?? 0)) * 100) / 100; }
        v.SyncToken++; v.TotalAmt = 0; v.UnappliedAmt = 0; v.Line = []; v.voided = true; v.PrivateNote = "Voided - " + v.PrivateNote;
        return jres(200, { Payment: payRow(v), time: "2026-11-02T12:00:00Z" }, "tid-pvoid-" + v.Id);
      }
      if (op !== null) return jres(400, { Fault: { Error: [{ Message: "Unsupported Operation", code: "500" }], type: "ValidationFault" } }, "tid-op");
      const lines = Array.isArray(b.Line) ? b.Line as Record<string, unknown>[] : [], outLines: Record<string, unknown>[] = [];
      for (const l of lines) {
        const lt = (((l.LinkedTxn ?? []) as Record<string, unknown>[])[0] ?? {}) as Record<string, unknown>, inv = it.invoices.get(String(lt.TxnId ?? ""));
        if (!inv || (inv.ent ?? "Invoice") !== "Invoice") return jres(400, { Fault: { Error: [{ Message: "Invalid Reference Id", Detail: "Invalid Reference Id : Invoice " + String(lt.TxnId) + " not found", code: "6240" }], type: "ValidationFault" } }, "tid-badref");
        const bal = inv.Balance ?? inv.TotalAmt;
        if (Number(l.Amount ?? 0) > bal + 0.004) return jres(400, { Fault: { Error: [{ Message: "Business Validation Error", Detail: "Amount applied exceeds the invoice balance", code: "6000" }], type: "ValidationFault" } }, "tid-6000");
        inv.Balance = Math.round((bal - Number(l.Amount ?? 0)) * 100) / 100;
        outLines.push({ Amount: Number(l.Amount ?? 0), LinkedTxn: l.LinkedTxn, LineEx: { any: [{ name: "{http://schema.intuit.com/finance/v3}NameValue", value: { Name: "txnId", Value: inv.Id } }, { value: { Name: "txnOpenBalance", Value: String(inv.Balance) } }, { value: { Name: "txnReferenceNumber", Value: inv.DocNumber } }] } });
      }
      const id = String(7000 + (++it.createdN)), total = Number(b.TotalAmt ?? 0), applied = outLines.reduce((a, l) => a + Number(l.Amount ?? 0), 0);
      const v: Pay = { Id: id, SyncToken: 0, TotalAmt: total, UnappliedAmt: Math.round((total - applied) * 100) / 100, CustomerRef: b.CustomerRef, TxnDate: String(b.TxnDate ?? ""), PaymentRefNum: typeof b.PaymentRefNum === "string" ? b.PaymentRefNum : null, PrivateNote: String(b.PrivateNote ?? ""), Line: outLines, voided: false, DepositToAccountRef: b.DepositToAccountRef ?? { value: "26" }, PaymentMethodRef: b.PaymentMethodRef };
      it.payments.set(id, v);
      return jres(200, { Payment: payRow(v), time: "2026-11-02T12:00:00Z" }, "tid-ppost-" + id);
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
      const byDate = /\bfrom\s+Payment\s+where\s+TxnDate\s*=\s*'(\d{4}-\d{2}-\d{2})'/i.exec(q);                      // 2e-1c 결제 unknown 풀기 — 그 날의 Payment 전부(가짜 장부)
      if (byDate) { const rows = [...it.payments.values()].filter((v) => v.TxnDate === byDate[1]).map((v) => ({ Id: v.Id, TotalAmt: v.TotalAmt, UnappliedAmt: v.UnappliedAmt, SyncToken: String(v.SyncToken), PrivateNote: v.PrivateNote, PaymentRefNum: v.PaymentRefNum, CustomerRef: v.CustomerRef, TxnDate: v.TxnDate })); return jres(200, { QueryResponse: rows.length ? { Payment: rows, startPosition: 1, maxResults: rows.length } : {}, time: "2026-11-02T12:00:00Z" }, "tid-qpay"); }
      const byDoc = /\bwhere\s+DocNumber\s*=\s*'((?:[^']|'')*)'/i.exec(q);                                      // 2b2 DocNumber 조회 — 가짜 장부에서
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
    if (/\/journalentry\/\d+\?/.test(url)) return jres(404, { Fault: { Error: [{ Message: "Object Not Found", Detail: "Object Not Found : Something you're trying to use has been made inactive.", code: "610" }], type: "ValidationFault" } }, "tid-404");
    return jres(404, { Fault: { Error: [{ Message: "no route", code: "404" }], type: "SystemFault" } });
  };
  return { it, fetch };
}

// ── 가짜 DB(창구 열둘 + last_error_set · 20261029160000 의 글 그대로) ──
type Conn = { env: string; realm_id: string; status: string; company_name: string | null; token_version: number; access_exp: number; refresh_exp: number | null; refresh: string; access: string; lease_until: number | null; last_error: string | null; connected_by: string };
type Pull = { started_at: number; next_start: number; received: number; pages: number; finished_at: number | null };
type Ent = { name: string; sku: string | null; fetched_at: number; gone_at: number | null };
type Db = { conn: Conn | null; states: Map<string, { staff_id: string; env: string; created_at: number; used_at: number | null }>; pin: Record<string, string | null>; calls: string[]; mails: number; saveFails: boolean; staleOnSave: boolean; lastErrors: string[]; versionBumpOnSleep: boolean; pulls: Map<string, Pull>; ents: Map<string, Map<string, Ent>>; keys: Record<string, string | null>; jobs: Map<string, Job>; links: { ims_kind: string; ims_id: string; qbo_id: string; qbo_name: string; matched_by: string }[]; txns: Map<string, Txn>; claimKinds: string[][] };   // keys = JWT → perms 열쇠('qbo' · 'qbo:read' · null) · qbo-sync-2a 945 · jobs · links = 2a′ 일감 상태기(20261102003000 · 20261102030000 의 규칙 · 거부 글 그대로)
type Job = { id: string; kind: string; ims_kind: string; ims_id: string; state: string; attempts: number; request_id: string; name: string; name_alt: string | null; sku: string | null; body: Record<string, unknown>; qbo_id: string | null; qbo_name: string | null; last_error: string | null; claimed_at: number | null; sent_at: number | null; doc_number?: string | null; totals?: { total: number; tax: number } | null; warning?: string | null; needs?: { kind: string; ims_id: string; name: string; parent?: { ims_id: string; name: string } }[]; wait_job?: string | null; blocked_by?: string | null; fingerprint?: string | null; check_lines?: { invoice_number: string; qbo_invoice_id: string; amount: number }[] | null; lookup?: Record<string, unknown> | null; pay_totals?: { amount: number; unapplied: number } | null };   // 2d1: needs · wait_job · blocked_by · [2e-1c fingerprint · check_lines · lookup · pay_totals]
type Txn = { qbo_id: string; doc_number: string; sync_token: string | null; total_amt: number | null; total_tax: number | null; mismatch: string | null; voided_at: number | null; fingerprint?: string | null; unapplied?: number | null };   // [2e-1c fingerprint · unapplied]   // 2b2 qbo_txn 거울(20261102040000 의 942 규칙 · 글 그대로)
const STAFF = "11111111-1111-4111-8111-111111111111";
const STAFF_MGR = "22222222-2222-4222-8222-222222222222";
const staffOf = (jwt: string) => jwt === "JWT-ADMIN" ? STAFF : STAFF_MGR;
function dbFake(clock: () => number): { db: Db; rpcUser: Deps["rpcUser"]; rpcService: Deps["rpcService"] } {
  const db: Db = { conn: null, states: new Map(), pin: { sandbox: null, production: null }, calls: [], mails: 0, saveFails: false, staleOnSave: false, lastErrors: [], versionBumpOnSleep: false, pulls: new Map(), ents: new Map(), keys: { "JWT-ADMIN": "qbo", "JWT-MGR": null }, jobs: new Map(), links: [], txns: new Map(), claimKinds: [] };   // 2a: admin 도 열쇠를 켜야 한다 — 기본 가짜 admin 은 켜 둔다
  const refuse = (msg: string) => { throw new RpcError(400, msg); };
  const keyOf = (jwt: string) => db.keys[jwt] === "qbo" ? "write" : db.keys[jwt] === "qbo:read" ? "read" : null;
  const rpcUser: Deps["rpcUser"] = async (fn, args, jwt) => {
    db.calls.push("user:" + fn);
    if (jwt !== "JWT-ADMIN" && jwt !== "JWT-MGR") throw new RpcError(401, "JWT expired");
    if (fn === "qbo_status") return db.conn ? { status: db.conn.status, env: db.conn.env, realm_id: db.conn.realm_id, company_name: db.conn.company_name, token_version: db.conn.token_version, last_error: db.conn.last_error, caller_is_admin: jwt === "JWT-ADMIN", caller_qbo: keyOf(jwt), pinned_realm: db.pin } : { status: "none", caller_is_admin: jwt === "JWT-ADMIN", caller_qbo: keyOf(jwt), pinned_realm: db.pin };
    // qbo-sync-2a 945 — 열쇠 문(20261102003000 의 거부 글 그대로): qbo_key_gate · 1a 짝 · 받기 창구(qbo_sync_gate = qbo_key_gate(true)) · 그 밖은 admin 만
    const KEY_FNS = ["qbo_key_gate", "qbo_pull_begin", "qbo_entity_upsert", "qbo_pull_finish"];
    if (fn === "qbo_key_gate") { const write = args.p_write !== false; if (db.keys[jwt] === "qbo" || (!write && db.keys[jwt] === "qbo:read")) return staffOf(jwt); refuse(`Your account does not have the 'qbo'${write ? " (write)" : ""} permission — ask an admin to switch it on in Staff — nothing was changed`); }
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
  w.db.jobs.set(j.id, j);
  return j;
}
const postHits = (w: World) => apiHits(w).filter((h) => h.method === "POST" && !h.url.includes("/query"));
function writesAllowedOnly(w: World, where: string) {
  for (const h of apiHits(w)) {
    if (h.method === "GET") continue;
    const u = new URL(h.url);
    const ent = (/\/v3\/company\/[^/]+\/(customer|item|invoice|creditmemo|payment)\/?$/.exec(u.pathname) ?? [])[1] ?? null, op = u.searchParams.get("operation"), inc = u.searchParams.get("include");
    ok(h.method === "POST" && ent !== null && !!u.searchParams.get("requestid") && ((op === null && inc === null) || (op === "void" && (ent === "invoice" || ent === "creditmemo")) || (op === "update" && inc === "void" && ent === "payment")), where + ": unexpected write to Intuit: " + h.method + " " + h.url);   // [2e-1c payment · update&include=void]   // 2b2: invoice · invoice?operation=void 도 허용 꼴 · [2c1 creditmemo]
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
  eq([...SEND_KINDS], ["customer", "item", "invoice", "invoice_void", "credit", "credit_void", "payment", "payment_void"], "SEND_KINDS (2c1: + credit · credit_void · [2e-1c + payment · payment_void])");
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
  eq([b1.claimed, b1.sent, b1.failed, b1.unknown, b1.mismatch, (b1.kinds as string[]).length, w.db.claimKinds.at(-1)], [1, 1, 0, 0, 0, 8, ["customer", "item", "invoice", "invoice_void", "credit", "credit_void", "payment", "payment_void"]], "claim with six kinds · one invoice sent: " + JSON.stringify(b1.jobs));
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
  eq([b1.claimed, b1.sent, b1.failed, b1.unknown, b1.mismatch, (b1.kinds as string[]).length], [1, 1, 0, 0, 0, 8], "one credit memo sent: " + JSON.stringify(b1.jobs));
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
  eq([...SEND_KINDS], ["customer", "item", "invoice", "invoice_void", "credit", "credit_void", "payment", "payment_void"], "SEND_KINDS 8");
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
  eq([kindsOf(undefined), kindsOf(null), kindsOf(["payment", "payment", "payment_void"])], [[...SEND_KINDS], [...SEND_KINDS], ["payment", "payment_void"]], "kindsOf: all · dedupe");
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
  eq(bk2.kinds, [...SEND_KINDS], "no kinds → all 8 (old callers unchanged)");
  const p10 = addPay(w, "CHQ 10", [{ inv: "5105", doc: "60205", amt: 1 }], 1);
  const pid10 = "0e0e0e0e-0000-4000-8000-" + String(Number(p10.id.replace("job-", ""))).padStart(12, "0"); w.db.jobs.delete(p10.id); p10.id = pid10; w.db.jobs.set(pid10, p10);   // job_ids 길은 uuid 만 받는다
  const bk3 = await body(await postBody(w, { action: "send", job_ids: [pid10], kinds: ["customer"] }, "JWT-MGR"));
  eq([bk3.mode, bk3.kinds, bk3.sent, p10.state], ["selected", [...SEND_KINDS], 1, "sent"], "job_ids path ignores kinds (bookkeeper picks a payment job)");
  ok(w.db.claimKinds.length > kinds0, "claims happened");
  writesAllowedOnly(w, "㉒"); noLeak(w, "㉒");
  ok(!JSON.stringify({ logs: w.logs, warns: w.warns }).includes("ZZPII"), "no PII in logs");
});
