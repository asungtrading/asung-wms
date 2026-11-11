// ============================================================
// ASUNG IMS — EF freightcom · action "inspect" (fc-track-1 · 2026-11-10 · Freightcom 쉽먼트 보드 1 차 · 판정 1154 ~ 대기)
//   왜: 묶음 인보이스의 줄이 어느 쉽먼트 것인지 가려낼 수 있는지(line_items 의 id · sub_type · message) · 추적 · 잔액의 실물 꼴을 본다
//   ⭐ GET 만 · 경로는 코드에 박음(입력은 encodeURIComponent · 날짜 YYYY-MM-DD) · DB 저장 0 · 원문은 부른 사람에게만
//   문 = 활성 admin 만(rpc/ims_is_admin · 사용자 JWT · Caleb 11-10 ⬜1) — 응답에 손님 주소 · 연락처가 그대로 있다
//   지우는 칸(Caleb 11-10 ⛔1 · ⛔3): 문자열 값이 http:// · https:// 로 시작하면 키와 상관없이 전부(중첩 · 배열 안까지) "[removed]"
//                                    · credit_card_number · credit_card_auth · credit_card_reference 는 어디에 있든 "[removed]"(금액 · type · id 는 남김)
//   로그(⛔2): 호출 한 번 = fc_call_log 메타 한 줄(action inspect_<what> · account · ok · http_status · ms · by_staff) · error 는
//              「Freightcom inspect_<what> failed (HTTP n)」 뿐 — 응답 몸 · 금액은 로그에 넣지 않는다(fc_call_log 는 로그인한 누구나 읽는다)
//   시간 한도: 이 파일의 호출에만 INSPECT_TIMEOUT_MS(20 s · AbortSignal) — index.ts 의 fcCall(예약 · 견적 · 취소 · 픽업)은 무접촉
//   Freightcom 이 2xx 가 아니어도 EF 는 200 + ok:false + http_status + 몸(지운 뒤) — supabase-js invoke 가 2xx 아닌 응답의 몸을 버리기 때문
//   index.ts 는 잇는 줄만(deps 를 만들어 runInspect 를 부른다) · 시험 = inspect_test.ts(가짜 fetch · 가짜 deps)
// ============================================================

export const INSPECT_WHATS = ["shipment", "tracking", "invoices", "documents", "document", "balance"] as const;
export type InspectWhat = typeof INSPECT_WHATS[number];
export const INSPECT_TIMEOUT_MS = 20_000;
export const REMOVED = "[removed]";
export const INSPECT_DEFAULT_DAYS = 30;
const CARD_KEYS = new Set(["credit_card_number", "credit_card_auth", "credit_card_reference"]);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ACCOUNT_RE = /^[A-Z0-9]{2,10}$/;   // _shared/freightcom.ts ACCOUNT_RE 와 같은 규칙(판정 848) — _shared 를 고치지 않으려 여기 둔다
const YMD_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const BOOKING_WHATS: readonly InspectWhat[] = ["shipment", "tracking", "invoices"];

// ── 지우기 — 중첩 · 배열 안까지 · 원본은 건드리지 않는다 ──
export function redact(v: unknown): unknown {
  if (typeof v === "string") return /^https?:\/\//i.test(v.trim()) ? REMOVED : v;
  if (Array.isArray(v)) return v.map(redact);
  if (v && typeof v === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, x] of Object.entries(v as Record<string, unknown>)) out[k] = CARD_KEYS.has(k) && x !== null && x !== undefined && x !== "" ? REMOVED : redact(x);
    return out;
  }
  return v;
}

// ── 날짜 ──
export function isYmd(s: unknown): s is string {
  if (typeof s !== "string") return false;
  const m = YMD_RE.exec(s);
  if (!m) return false;
  const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  return d.getUTCFullYear() === +m[1] && d.getUTCMonth() === +m[2] - 1 && d.getUTCDate() === +m[3];
}
const ymd = (d: Date) => d.toISOString().slice(0, 10);
export function defaultRange(now: Date): { start_date: string; end_date: string } {
  return { start_date: ymd(new Date(now.getTime() - INSPECT_DEFAULT_DAYS * 86_400_000)), end_date: ymd(now) };
}

// ── 결제수단 고르기 — net-terms → prepaid → 없음(credit-card 는 잔액이 없다) ──
export function pickBalanceMethod(body: unknown): { id: string; type: string; label: string } | null {
  const b = body as Record<string, unknown> | unknown[] | null;
  const arr = Array.isArray(b) ? b : Array.isArray((b as Record<string, unknown>)?.payment_methods) ? (b as Record<string, unknown>).payment_methods as unknown[] : [];
  const rows = arr.filter((r) => r && typeof r === "object") as Record<string, unknown>[];
  for (const t of ["net-terms", "prepaid"]) {
    const r = rows.find((x) => String(x.type ?? "").toLowerCase() === t && String(x.id ?? "").trim() !== "");
    if (r) return { id: String(r.id).trim(), type: t, label: String(r.label ?? "") };
  }
  return null;
}

// ── 몸 읽기 — 틀리면 { error } (400) ──
export type InspectInput = { what: InspectWhat; booking_id: string | null; account: string | null; document_id: string | null; start_date: string | null; end_date: string | null };
export function parseInspect(body: Record<string, unknown>, now: Date = new Date()): InspectInput | { error: string } {
  const what = String(body.what ?? "");
  if (!(INSPECT_WHATS as readonly string[]).includes(what)) return { error: "what must be one of: " + INSPECT_WHATS.join(", ") };
  const w = what as InspectWhat;
  const s = (k: string) => { const v = body[k]; return v === undefined || v === null ? "" : String(v).trim(); };
  const out: InspectInput = { what: w, booking_id: null, account: null, document_id: null, start_date: null, end_date: null };
  if (BOOKING_WHATS.includes(w)) {
    if (!UUID_RE.test(s("booking_id"))) return { error: "booking_id (full uuid) is required for what=" + w };
    out.booking_id = s("booking_id").toLowerCase();
    return out;
  }
  const account = s("account").toUpperCase();
  if (!ACCOUNT_RE.test(account)) return { error: "account (2–10 upper-case letters or digits, e.g. TOR · EDM) is required for what=" + w };
  out.account = account;
  if (w === "document") {
    const id = s("document_id");
    if (!id || id.length > 128 || /[\s/?#]/.test(id)) return { error: "document_id is required (no spaces, slashes, ? or #, at most 128 characters)" };
    out.document_id = id;
  }
  if (w === "documents") {
    const d = defaultRange(now);
    const st = s("start_date") || d.start_date, en = s("end_date") || d.end_date;
    if (!isYmd(st) || !isYmd(en)) return { error: "start_date and end_date must be YYYY-MM-DD (UTC)" };
    if (st > en) return { error: "start_date must not be after end_date" };
    out.start_date = st; out.end_date = en;
  }
  return out;
}

// ── 경로 — 코드에 박음 · 입력은 encodeURIComponent ──
const e = encodeURIComponent;
export const inspectPaths = {
  shipment: (fcId: string) => "/shipment/" + e(fcId),
  tracking: (fcId: string) => "/shipment/" + e(fcId) + "/tracking-events",
  invoicesByTn: (tn: string) => "/finance/invoices-for-transaction-number/" + e(tn),
  invoicesByShipment: (fcId: string) => "/finance/invoices-for-shipment-id/" + e(fcId),
  documents: (st: string, en: string) => "/finance/documents?start_date=" + e(st) + "&end_date=" + e(en),
  document: (id: string) => "/finance/document/" + e(id),
  paymentMethods: () => "/finance/payment-methods",
  balance: (pmId: string) => "/finance/payment-method/" + e(pmId) + "/available-balances",
};

// ── GET 하나 — 시간 한도 · 2xx 아니어도 몸 · 로그 줄은 메타만 ──
export type LogMeta = { shipment_id: string | null; account: string; action: string; ok: boolean; http_status: number | null; error: string | null; ms: number };
export type GetResult = { http_status: number | null; ok: boolean; ms: number; body: unknown; error: string | null };
export function inspectLogError(what: InspectWhat, status: number | null, timedOut: boolean): string {
  return `Freightcom inspect_${what} failed (HTTP ${status ? status : timedOut ? "timeout" : "network"})`;
}
export async function inspectGet(fetchFn: typeof fetch, base: string, apiKey: string, what: InspectWhat, account: string, path: string, shipmentId: string | null,
                                 log: (row: LogMeta) => Promise<void>, timeoutMs = INSPECT_TIMEOUT_MS): Promise<GetResult> {
  const t0 = Date.now();
  let status: number | null = null, body: unknown = null, error: string | null = null, timedOut = false;
  try {
    const r = await fetchFn(base + path, { method: "GET", headers: { Authorization: apiKey, Accept: "application/json" }, signal: AbortSignal.timeout(timeoutMs) });
    status = r.status;
    const text = await r.text();
    try { body = text ? JSON.parse(text) : null; } catch { body = text; }
    if (!r.ok) error = "Freightcom answered HTTP " + status;
  } catch (x) {
    const name = (x as Error)?.name ?? "";
    timedOut = name === "TimeoutError" || name === "AbortError";
    error = timedOut ? `Freightcom did not answer within ${timeoutMs} ms` : "Freightcom unreachable: " + String((x as Error)?.message ?? x).slice(0, 200);
  }
  const ms = Date.now() - t0;
  await log({ shipment_id: shipmentId, account, action: "inspect_" + what, ok: error === null, http_status: status, error: error === null ? null : inspectLogError(what, status, timedOut), ms });
  return { http_status: status, ok: error === null, ms, body: redact(body), error };
}

// ── 처리 몸 — index.ts 가 deps 를 만들어 부른다 ──
export type InspectBooking = { id: string; shipment_id: string; status: string; account: string | null; freightcom_shipment_id: string | null; transaction_number: string | null; shipment_account: string | null };
export type InspectDeps = {
  isAdmin: () => Promise<boolean | "invalid">;              // rpc/ims_is_admin(사용자 JWT) · 401 이면 "invalid"
  loadBooking: (id: string) => Promise<InspectBooking | null>;
  apiKey: (account: string) => string;                       // 없으면 ""
  base: string;
  fetchFn: typeof fetch;
  log: (row: LogMeta) => Promise<void>;                     // by_staff 는 index.ts 가 끼운다
  noAccountSentence: (account: string) => string;
  now?: Date;
  timeoutMs?: number;
};
export type InspectReply = { status: number; payload: Record<string, unknown> };

export async function runInspect(jwt: string, body: Record<string, unknown>, d: InspectDeps): Promise<InspectReply> {
  const t0 = Date.now();
  if (!jwt) return { status: 401, payload: { ok: false, error: "Missing Authorization" } };
  const admin = await d.isAdmin();
  if (admin === "invalid") return { status: 401, payload: { ok: false, error: "Invalid session — sign in again" } };
  if (!admin) return { status: 403, payload: { ok: false, error: "Not allowed — Freightcom inspect is for an active admin only (it shows raw Freightcom answers with customer addresses)" } };
  const p = parseInspect(body, d.now ?? new Date());
  if ("error" in p) return { status: 400, payload: { ok: false, error: p.error } };
  if (!d.base) return { status: 500, payload: { ok: false, error: "FREIGHTCOM_BASE_URL not configured on this project - refusing (fail-closed)" } };

  let account = p.account ?? "", shipmentId: string | null = null, fcId = "", tn = "";
  const warnings: string[] = [];
  let booking: Record<string, unknown> | null = null;
  if (p.booking_id) {
    const b = await d.loadBooking(p.booking_id);
    if (!b) return { status: 404, payload: { ok: false, error: "booking not found" } };
    fcId = String(b.freightcom_shipment_id ?? "").trim();
    if (!fcId) return { status: 400, payload: { ok: false, error: `Booking ${b.id} has no Freightcom shipment id (status ${b.status}) — nothing to inspect` } };
    account = String(b.shipment_account ?? b.account ?? "").trim();
    if (b.shipment_account && b.account && b.shipment_account !== b.account) warnings.push(`account_differs — shipment ${b.shipment_account} · booking ${b.account} · used the shipment's`);
    tn = String(b.transaction_number ?? "").trim();
    shipmentId = b.shipment_id;
    booking = { booking_id: b.id, status: b.status, freightcom_shipment_id: fcId, transaction_number: tn || null };
  }
  const key = account ? d.apiKey(account) : "";
  if (!account || !key) return { status: 422, payload: { ok: false, error: d.noAccountSentence(account || "??") } };
  const get = (path: string) => inspectGet(d.fetchFn, d.base, key, p.what, account, path, shipmentId, d.log, d.timeoutMs ?? INSPECT_TIMEOUT_MS);
  const part = (r: GetResult) => ({ http_status: r.http_status, ok: r.ok, ms: r.ms, error: r.error, body: r.body });
  const reply = (results: GetResult[], b: unknown, extra: Record<string, unknown> = {}): InspectReply => {
    const bad = results.find((r) => !r.ok);
    return { status: 200, payload: { ok: !bad, what: p.what, account, http_status: (bad ?? results[results.length - 1])?.http_status ?? null, ms: Date.now() - t0, ...(booking ? { booking } : {}), ...extra, ...(warnings.length ? { warnings } : {}), body: b } };
  };

  if (p.what === "shipment") { const r = await get(inspectPaths.shipment(fcId)); return reply([r], r.body, r.error ? { error: r.error } : {}); }
  if (p.what === "tracking") { const r = await get(inspectPaths.tracking(fcId)); return reply([r], r.body, r.error ? { error: r.error } : {}); }
  if (p.what === "invoices") {
    const byShip = await get(inspectPaths.invoicesByShipment(fcId));
    const byTn = tn ? await get(inspectPaths.invoicesByTn(tn)) : null;
    if (!tn) warnings.push("no transaction_number on this booking — only the shipment-id path was read");
    const same = byTn && byTn.ok && byShip.ok ? JSON.stringify(byTn.body) === JSON.stringify(byShip.body) : null;
    return reply(byTn ? [byTn, byShip] : [byShip], { by_transaction_number: byTn ? part(byTn) : null, by_shipment_id: part(byShip) }, { same_answer: same });
  }
  if (p.what === "documents") { const r = await get(inspectPaths.documents(p.start_date!, p.end_date!)); return reply([r], r.body, { start_date: p.start_date, end_date: p.end_date, ...(r.error ? { error: r.error } : {}) }); }
  if (p.what === "document") { const r = await get(inspectPaths.document(p.document_id!)); return reply([r], r.body, { document_id: p.document_id, ...(r.error ? { error: r.error } : {}) }); }
  // balance
  const pm = await get(inspectPaths.paymentMethods());
  if (!pm.ok) return reply([pm], { payment_methods: part(pm), available_balances: null }, { error: pm.error });
  const picked = pickBalanceMethod(pm.body);
  if (!picked) return { status: 422, payload: { ok: false, what: p.what, account, error: "This Freightcom account has no net-terms or prepaid payment method — no balance to read", body: { payment_methods: part(pm) } } };
  const bal = await get(inspectPaths.balance(picked.id));
  return reply([pm, bal], { payment_methods: part(pm), picked, available_balances: part(bal) }, bal.error ? { error: bal.error } : {});
}
