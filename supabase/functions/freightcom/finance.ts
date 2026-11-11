// ============================================================
// ASUNG IMS — EF freightcom · action "finance_sweep"(cron) · "finance_poll"(사람) (fc-track-3 · 2026-11-10 · 판정 1163 ~ 1166 · DB 20261111034018)
//   왜: Freightcom 이 예약 뒤에 요금을 더 붙이기도 하고(1163) · Net Terms 한도가 있어 중간중간 결제해야 한다(1164) — IMS 가 청구 문서 · 남은 한도를 스스로 읽어 둔다
//   ⭐ GET 넷뿐 · 경로는 코드에 박음(financePaths — 결제 · reload 경로는 없다 · 1165) · 저장은 DB 창구 셋(fc_finance_docs_save · fc_finance_lines_save · fc_finance_balance_save · service_role)
//      「줄을 읽을 문서」 를 고르는 규칙은 DB 한 곳(fc_finance_lines_due — docs_save 가 need_lines 로 돌려준다) · 사람 길의 문은 DB(fc_finance_gate · 사용자 JWT)
//   계정 한 번의 걸음: ① GET /finance/documents?start_date&end_date(창 = 오늘 − 35 일 ~ 오늘 · UTC · 매 회차 같은 식 ⬜4) → 머리 저장 → need_lines
//                     ② GET /finance/payment-methods → net-terms(없으면 prepaid) → GET …/available-balances → 잔액 저장(줄 읽기보다 먼저 — 회차 상한에 걸려도 잔액은 남는다)
//                     ③ need_lines 의 문서마다 GET /finance/document/{id} → 줄 저장(문서 하나씩 — 중간에 끊겨도 읽은 것은 남는다)
//   DB 로 보내는 것: 머리는 일곱 칸(slimHead) · 문서는 머리 + payments[{type, amount}] + line_items 일곱 칸(slimDocument — urls · payments.data(카드 칸) · 그 밖은 버린다) · 잔액은 [{value, currency}]
//   로그(1156 과 같은 선 + 이견 8): 호출 한 번 = fc_call_log 메타 한 줄(action finance_documents | finance_methods | finance_balance | finance_document) · 회차 요약(finance_sweep · detail)은 **개수만** — 금액은 로그 · 응답 어디에도 넣지 않는다
//   시간 한도(1157 과 같은 선): 이 파일의 호출에만 FINANCE_TIMEOUT_MS(20 s) · 회차 상한 FINANCE_SWEEP_BUDGET_MS(90 s)가 지나면 새 문서 · 새 계정을 시작하지 않는다(stopped_early)
//   한 계정 실패(열쇠 없음 · GET 실패 · 꼴 다름 — EDM 실물은 아직 없다)는 그 계정만 failed · 회차는 계속(이견 9)
//   index.ts 는 잇는 줄만(deps 를 만들어 runFinanceSweep · runFinancePoll 을 부른다) · 시험 = finance_test.ts(가짜 fetch · 가짜 deps · fixtures/finance-*.json)
// ============================================================
import { pickBalanceMethod } from "./inspect.ts";
import { gateStatusOf, type GateResult } from "./track.ts";

export const FINANCE_TIMEOUT_MS = 20_000;
export const FINANCE_SWEEP_BUDGET_MS = 90_000;
export const FINANCE_WINDOW_DAYS = 35;
export const FINANCE_BATCH_DEFAULT = 25;      // cron 몸이 inv_config fc_finance_doc_batch 를 읽어 limit 으로 넘긴다
export const FINANCE_BATCH_MAX = 100;
export const FINANCE_POLL_BATCH = 5;          // 사람 길 — 줄 읽기는 작게
const e = encodeURIComponent;
export const financePaths = {
  documents: (st: string, en: string) => "/finance/documents?start_date=" + e(st) + "&end_date=" + e(en),
  document: (id: string) => "/finance/document/" + e(id),
  paymentMethods: () => "/finance/payment-methods",
  balance: (pmId: string) => "/finance/payment-method/" + e(pmId) + "/available-balances",
};
export type FinanceAction = "finance_documents" | "finance_document" | "finance_methods" | "finance_balance";
const ACCOUNT_RE = /^[A-Z0-9]{2,10}$/;        // _shared/freightcom.ts ACCOUNT_RE 와 같은 규칙(판정 848)

// ── 꼴만 보는 순수 함수 ──
const ymd = (d: Date) => d.toISOString().slice(0, 10);
export function windowOf(now: Date, days = FINANCE_WINDOW_DAYS): { start_date: string; end_date: string } {
  return { start_date: ymd(new Date(now.getTime() - days * 86_400_000)), end_date: ymd(now) };
}
export function financeLimitOf(body: unknown, dflt = FINANCE_BATCH_DEFAULT): number {
  const v = (body as Record<string, unknown> | null)?.limit;
  const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN;
  return Number.isInteger(n) && n >= 1 && n <= FINANCE_BATCH_MAX ? n : dflt;
}
const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === "object" && !Array.isArray(v);
// 금액 · 날짜는 값을 고치지 않고 칸만 추린다(파서는 DB 한 곳)
const money = (v: unknown) => (isObj(v) ? { value: v.value ?? null, currency: v.currency ?? null } : null);
const dateOf = (v: unknown) => (isObj(v) ? { year: v.year ?? null, month: v.month ?? null, day: v.day ?? null } : null);
export const HEAD_KEYS = ["id", "type", "number", "date", "due_date", "amount", "owing"] as const;
export function slimHead(d: Record<string, unknown>): Record<string, unknown> {
  return { id: d.id ?? null, type: d.type ?? null, number: d.number ?? null, date: dateOf(d.date), due_date: dateOf(d.due_date), amount: money(d.amount), owing: money(d.owing) };
}
// 배열 맨몸 · {documents:[…]} → 추린 머리 목록 · 그 밖은 null(못 읽음)
export function docHeadsOf(body: unknown): Record<string, unknown>[] | null {
  const arr = Array.isArray(body) ? body : isObj(body) && Array.isArray(body.documents) ? body.documents : null;
  return arr ? (arr as unknown[]).filter(isObj).map(slimHead) : null;
}
export const LINE_KEYS = ["id", "type", "sub_type", "payment_id", "shipment_id", "amount", "message"] as const;
// 문서 하나 — 맨몸 · {document:{…}} · id 와 line_items 목록이 있어야 문서다 · urls · payments.data · 그 밖의 칸은 버린다
export function slimDocument(body: unknown): Record<string, unknown> | null {
  const b = isObj(body) && isObj(body.document) ? body.document : body;
  if (!isObj(b) || typeof b.id !== "string" || b.id.trim() === "" || !Array.isArray(b.line_items)) return null;
  const str = (v: unknown) => (typeof v === "string" ? v : null);
  return {
    ...slimHead(b),
    payments: (Array.isArray(b.payments) ? b.payments : []).filter(isObj).map((p) => ({ type: str(p.type), amount: money(p.amount) })),
    line_items: (b.line_items as unknown[]).filter(isObj).map((l) => ({ id: str(l.id), type: str(l.type), sub_type: str(l.sub_type), payment_id: str(l.payment_id), shipment_id: str(l.shipment_id), amount: money(l.amount), message: str(l.message) })),
  };
}
// {available_balances:[…]} · 배열 맨몸 → [{value, currency}] · 그 밖은 null — 원소 수 · 값 판정은 DB(1 개가 아니면 저장하지 않는다)
export function slimBalance(body: unknown): Record<string, unknown>[] | null {
  const arr = Array.isArray(body) ? body : isObj(body) && Array.isArray(body.available_balances) ? body.available_balances : null;
  return arr ? (arr as unknown[]).map((x) => (isObj(x) ? { value: x.value ?? null, currency: x.currency ?? null } : { value: null, currency: null })) : null;
}
export function financeLogError(action: FinanceAction, status: number | null, timedOut: boolean): string {
  return `Freightcom ${action} failed (HTTP ${status ? status : timedOut ? "timeout" : "network"})`;
}

// ── GET 하나 — 시간 한도 · 로그 줄은 메타만 ──
export type FinanceLog = { shipment_id: string | null; account: string | null; action: string; ok: boolean; http_status: number | null; error: string | null; ms: number; detail?: unknown };
export type FinanceGet = { ok: boolean; http_status: number | null; body: unknown; error: string | null; ms: number };
export async function financeGet(fetchFn: typeof fetch, base: string, apiKey: string, action: FinanceAction, account: string, path: string,
                                 log: (row: FinanceLog) => Promise<void>, timeoutMs = FINANCE_TIMEOUT_MS): Promise<FinanceGet> {
  const t0 = Date.now();
  let status: number | null = null, body: unknown = null, error: string | null = null, timedOut = false;
  try {
    const r = await fetchFn(base + path, { method: "GET", headers: { Authorization: apiKey, Accept: "application/json" }, signal: AbortSignal.timeout(timeoutMs) });
    status = r.status;
    const text = await r.text();
    try { body = text ? JSON.parse(text) : null; } catch { body = null; }
    if (!r.ok) error = financeLogError(action, status, false);
  } catch (x) {
    const name = (x as Error)?.name ?? "";
    timedOut = name === "TimeoutError" || name === "AbortError";
    error = financeLogError(action, null, timedOut);
  }
  const ms = Date.now() - t0;
  await log({ shipment_id: null, account, action, ok: error === null, http_status: status, error, ms });
  return { ok: error === null, http_status: status, body: error === null ? body : null, error, ms };
}

// ── 계정 한 번 — 던지지 않는다(한 계정 실패가 회차를 멈추지 않는다) · 반환에 금액 없음 ──
export type FinanceDeps = {
  fetchFn: typeof fetch;
  base: string;
  apiKey: (account: string) => string;                       // 없으면 "" · 계정 꼴이 틀리면 던질 수 있다(여기서 받는다)
  log: (row: FinanceLog) => Promise<void>;                   // by_staff 는 index.ts 가 끼운다(cron 은 null)
  docsSave: (account: string, docs: Record<string, unknown>[], limit: number) => Promise<Record<string, unknown>>;      // rpc/fc_finance_docs_save
  linesSave: (account: string, doc: Record<string, unknown>) => Promise<Record<string, unknown>>;                       // rpc/fc_finance_lines_save
  balanceSave: (account: string, methodType: string, balance: Record<string, unknown>[]) => Promise<Record<string, unknown>>;   // rpc/fc_finance_balance_save
  noAccountSentence: (account: string) => string;
  timeoutMs?: number;
  now?: () => number;
};
export type FinanceItem = {
  account: string; ok: boolean;
  docs_read: boolean; received: number; saved: number; added: number; skipped: number; need_total: number;
  lines_read: number; lines_failed: number; lines_left: number;
  balance_saved: boolean; stopped_early: boolean; errors: string[]; warnings: string[];
};
const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : 0);
const short = (x: unknown) => String((x as Error)?.message ?? x).slice(0, 300);
export async function financeAccount(accountIn: string, limit: number, d: FinanceDeps, deadline: number | null = null, cap: number = limit): Promise<FinanceItem> {
  const now = d.now ?? Date.now, timeout = d.timeoutMs ?? FINANCE_TIMEOUT_MS;
  const account = String(accountIn ?? "").trim().toUpperCase();
  const it: FinanceItem = { account, ok: false, docs_read: false, received: 0, saved: 0, added: 0, skipped: 0, need_total: 0, lines_read: 0, lines_failed: 0, lines_left: 0, balance_saved: false, stopped_early: false, errors: [], warnings: [] };
  let key = "";
  try { key = ACCOUNT_RE.test(account) ? d.apiKey(account) : ""; } catch { key = ""; }
  if (!key) { it.errors.push(d.noAccountSentence(account || "??")); return it; }
  const get = (action: FinanceAction, path: string) => financeGet(d.fetchFn, d.base, key, action, account, path, d.log, timeout);

  // ① 머리
  let need: string[] = [];
  const w = windowOf(new Date(now()));
  const list = await get("finance_documents", financePaths.documents(w.start_date, w.end_date));
  const heads = list.ok ? docHeadsOf(list.body) : null;
  if (!list.ok) it.errors.push(String(list.error));
  else if (heads === null) it.errors.push("Freightcom finance_documents 200: the answer is not a list of documents");
  else {
    try {
      const s = await d.docsSave(account, heads, limit);
      it.docs_read = true;
      it.received = num(s?.received); it.saved = num(s?.saved); it.added = num(s?.added); it.skipped = num(s?.skipped) + num(s?.other_account); it.need_total = num(s?.need_total);
      need = (Array.isArray(s?.need_lines) ? (s.need_lines as unknown[]).filter((x): x is string => typeof x === "string" && x.trim() !== "") : []).slice(0, Math.max(cap, 0));
      if (num(s?.other_account) > 0) it.warnings.push(`other_account — ${num(s?.other_account)} documents are already saved under another account and were left as they are`);
    } catch (x) { it.errors.push("The document list was read but not saved — " + short(x)); }
  }

  // ② 잔액(줄 읽기보다 먼저)
  const pm = await get("finance_methods", financePaths.paymentMethods());
  if (!pm.ok) it.errors.push(String(pm.error));
  else {
    const picked = pickBalanceMethod(pm.body);
    if (!picked) it.warnings.push("no_balance_method — this Freightcom account has no net-terms or prepaid payment method · no balance to read");
    else {
      const bal = await get("finance_balance", financePaths.balance(picked.id));
      const slim = bal.ok ? slimBalance(bal.body) : null;
      if (!bal.ok) it.errors.push(String(bal.error));
      else if (slim === null) it.warnings.push("balance_shape — the answer has no available_balances list · nothing was saved");
      else {
        try {
          const s = await d.balanceSave(account, picked.type, slim);
          it.balance_saved = s?.saved === true;
          if (!it.balance_saved) it.warnings.push(String(s?.warning ?? "balance not saved"));
        } catch (x) { it.errors.push("The balance was read but not saved — " + short(x)); }
      }
    }
  }

  // ③ 줄 — 문서 하나씩
  for (const id of need) {
    if (deadline !== null && now() >= deadline) { it.stopped_early = true; break; }
    const r = await get("finance_document", financePaths.document(id));
    const doc = r.ok ? slimDocument(r.body) : null;
    if (!r.ok || doc === null) { it.lines_failed++; continue; }
    if (doc.id !== id) { it.lines_failed++; it.warnings.push("document_id_differs — Freightcom answered with another document id · not saved"); continue; }
    try {
      const s = await d.linesSave(account, doc);
      it.lines_read++;
      for (const wn of Array.isArray(s?.warnings) ? (s.warnings as unknown[]) : []) it.warnings.push(String(s?.document_id ?? id) + ": " + String(wn));
    } catch { it.lines_failed++; }
  }
  it.lines_left = Math.max(0, it.need_total - it.lines_read);
  if (it.lines_failed > 0) it.errors.push(it.lines_failed + " document reads failed — see the finance_document rows");
  it.ok = it.errors.length === 0;
  return it;
}

// ── cron 회차 — 스위치 → 계정마다 financeAccount → 요약 한 줄(action finance_sweep · detail 은 개수만) ──
export type FinanceSweepDeps = FinanceDeps & { enabled: () => Promise<boolean>; accounts: () => Promise<string[]>; budgetMs?: number };
export type FinanceReply = { status: number; payload: Record<string, unknown> };
export function financeSweepSummary(items: FinanceItem[]) {
  const s = { accounts: items.length, accounts_failed: 0, docs_received: 0, docs_added: 0, lines_read: 0, lines_failed: 0, lines_left: 0, balances_saved: 0 };
  for (const i of items) {
    if (!i.ok) s.accounts_failed++;
    s.docs_received += i.received; s.docs_added += i.added; s.lines_read += i.lines_read; s.lines_failed += i.lines_failed; s.lines_left += i.lines_left;
    if (i.balance_saved) s.balances_saved++;
  }
  return s;
}
export async function runFinanceSweep(body: Record<string, unknown>, d: FinanceSweepDeps): Promise<FinanceReply> {
  const now = d.now ?? Date.now, t0 = now();
  const limit = financeLimitOf(body), budget = d.budgetMs ?? FINANCE_SWEEP_BUDGET_MS;
  const summaryRow = async (ok: boolean, error: string | null, detail: Record<string, unknown>) =>
    await d.log({ shipment_id: null, account: null, action: "finance_sweep", ok, http_status: null, error, ms: now() - t0, detail: { ...detail, ms: now() - t0 } });
  if (!d.base) return { status: 500, payload: { ok: false, error: "FREIGHTCOM_BASE_URL not configured on this project - refusing (fail-closed)" } };
  let enabled = false;
  try { enabled = await d.enabled(); }
  catch (x) { const error = "inv_config read failed: " + short(x).slice(0, 200); await summaryRow(false, error, { enabled: null, limit }); return { status: 502, payload: { ok: false, error } }; }
  if (!enabled) {
    const skipped = "switch off — inv_config fc_finance_poll_enabled is not 'on' (nothing read)";
    const zero = { enabled: false, limit, ...financeSweepSummary([]), stopped_early: false, skipped };
    await summaryRow(true, null, zero);
    return { status: 200, payload: { ok: true, ...zero, items: [] } };
  }
  let accounts: string[];
  try { accounts = (await d.accounts()) ?? []; }
  catch (x) { const error = "account list failed: " + short(x).slice(0, 200); await summaryRow(false, error, { enabled: true, limit }); return { status: 502, payload: { ok: false, error } }; }
  const items: FinanceItem[] = [];
  let left = limit, stopped_early = false;
  for (const a of accounts) {
    if (now() - t0 >= budget) { stopped_early = true; break; }
    const it = await financeAccount(a, Math.max(left, 1), d, t0 + budget, Math.max(left, 0));   // 상한은 계정 둘 합쳐서 — 다 쓰면 다음 계정은 머리 · 잔액만(줄 0)
    left -= it.lines_read + it.lines_failed;
    if (it.stopped_early) stopped_early = true;
    items.push(it);
  }
  const s = financeSweepSummary(items);
  const detail = { enabled: true, limit, ...s, stopped_early, accounts_left: accounts.length - items.length };
  await summaryRow(s.accounts_failed === 0, s.accounts_failed === 0 ? null : s.accounts_failed + " of " + items.length + " accounts had a failed read — see the finance_… rows just before this one", detail);
  return { status: 200, payload: { ok: true, ...detail, ms: now() - t0, items } };
}

// ── 사람 길 — 문(DB · 사용자 JWT) → financeAccount(줄 읽기는 작게) → 요약(금액 없음) ──
export type FinancePollDeps = FinanceDeps & { gate: (account: string) => Promise<GateResult> };
export async function runFinancePoll(jwt: string, body: Record<string, unknown>, d: FinancePollDeps): Promise<FinanceReply> {
  if (!jwt) return { status: 401, payload: { ok: false, error: "Missing Authorization" } };
  const account = String(body.account ?? "").trim().toUpperCase();
  if (!ACCOUNT_RE.test(account)) return { status: 400, payload: { ok: false, error: "account is required (2–10 upper-case letters or digits, e.g. TOR · EDM)" } };
  if (!d.base) return { status: 500, payload: { ok: false, error: "FREIGHTCOM_BASE_URL not configured on this project - refusing (fail-closed)" } };
  const g = await d.gate(account);
  if (!g.ok) return { status: gateStatusOf(g.status, g.error), payload: { ok: false, error: g.status === 401 ? "Invalid session — sign in again" : g.error } };
  const now = d.now ?? Date.now;
  const item = await financeAccount(String(g.row.account ?? account), financeLimitOf(body, FINANCE_POLL_BATCH), d, now() + FINANCE_SWEEP_BUDGET_MS);
  if (!item.docs_read && !item.balance_saved) return { status: 502, payload: { ok: false, checked: false, account, error: item.errors[0] ?? "Couldn't read the billing from Freightcom", message: "Couldn't refresh the Freightcom billing — try again in a minute", finance: item } };
  return { status: 200, payload: { ok: true, checked: true, account, finance: item } };
}
