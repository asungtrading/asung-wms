// ============================================================
// ASUNG IMS — Edge Function: freightcom (fc-1b 견적 · fc-2c 예약 · 2026-10-28 · 판정 835 ~ 858 · DB fc-1a ~ 1b5 · fc-2a ~ 2b2 · 순수 함수 ../_shared/freightcom.ts)
//   ⚠️ 테스트 프로젝트(Asung-IMS · fazgmyvzzhqybtvtktyg) 전용 — 시작 때 inv_config.db_role = 'test' 가 아니면 멈춘다. 비밀값 FREIGHTCOM_BASE_URL(공통 · 없으면 500) + 계정마다 FREIGHTCOM_API_KEY_<계정>(fc-1b4 판정 848 · 계정 = 출발 창고 ref_warehouse.freightcom_account · 발송에 스냅샷 · 없으면 422 「연결 없음」 · 옛 FREIGHTCOM_API_KEY 로 넘어가지 않는다) — 토큰은 응답 · 기록 · 오류 문장 어디에도 안 남는다.
//   POST JSON {action, …} · 응답 json(status) · CORS · cron 길 없음(직원 길만 · verify_jwt=false 라 문은 함수 안):
//     문  Authorization: Bearer <세션 JWT> → 견적 넷(quote · quote_poll · services · status) = rpc/ims_can_write('sales') 또는 ('fulfillment') · 예약 셋(book · book_poll · cancel) = ims_can_write('freight_booking')(853 · 854) · label = 셋 중 하나 — 실제 검사는 DB 창구가 사용자 JWT 로 다시 한다
//     quote {so_ids[], options} · quote_poll {shipment_id, request_id} · services {account?} · status — fc-1b 그대로(아래 주석 · 흐름 무접촉)
//     book {shipment_id, pickup?{date, ready_at, ready_until}}
//        ① rpc/fc_book_prepare(사용자 · p_commit false) → 계정 · 비밀값 없으면 422(쓰기 0) → 다시 p_commit true(pending 행 · booking_id · request)
//        ② 결제수단: GET /finance/payment-methods(계정마다 · 10 분 캐시 · net-terms 먼저) → request + payment_method_id(값은 코드에 없다)
//        ③ POST /shipment → 202 {id} → service_role rpc/fc_book_pending_set(booking_id · Freightcom id · 실제 보낸 몸) · 2xx 가 아니면 rpc/fc_book_save(p_error = 그 몸의 문장) → 422
//        ④ GET /shipment/{id} 를 1.5 초마다 · 최대 25 초 — 200 → rpc/fc_book_save(원문) → 라벨 받기 ⑤ → {ok, pending:false, booking, labels, detail} · 400(booking carrier 등) → fc_book_save(p_error · 몸) → 422 · 아직이면 202 {ok, pending:true, booking_id, freightcom_shipment_id}
//        ⑤ 라벨(851 · 858): labels[] 에서 a6 pdf(padded 아님) + letter pdf(세로 · 둘째 letter 는 landscape 로 짐작 → 받지 않음) 만 → Freightcom url 에서 받아(Authorization 없이 · S3) %PDF 확인 → documents/fc_label/<발송>-<시도>-<size>.pdf 올리기 → service_role rpc/fc_label_add · zpl 은 받지 않는다 · 라벨 실패는 예약을 되돌리지 않는다(warnings)
//     book_poll {booking_id} — ④ 부터(DB 의 freightcom_shipment_id 로) · 이미 booked 인데 라벨이 없으면 ⑤ 만 다시
//     cancel {shipment_id} → rpc/fc_book_cancel_prepare(사용자) → DELETE /shipment/{id} → service_role rpc/fc_book_cancel_save(cancelled_by · 몸 | p_error)
//     label {label_id} → rpc/fc_label_get(사용자 JWT · 문) → documents 서명 URL 120 초(EF doc 선례) → {signed_url, expires_in}
//   Freightcom 호출 한 번 = fc_call_log 한 줄(service_role REST · action · account · ok · http_status · error · by_staff · shipment_id · ms) · 라벨 받기도 한 줄(action label_fetch) · 90 일 지난 줄은 호출 끝에 지운다
//   배포: supabase functions deploy freightcom --project-ref fazgmyvzzhqybtvtktyg (config.toml [functions.freightcom] verify_jwt=false)
// ============================================================
import { ACCOUNT_RE, apiKeyFor, attachFreightClass, BOOK_WAIT_MS, bookBody, bookErrorSentence, bookOutcome, cancelOutcome, distinctCarriers, FC_ACTIONS, FC_BOOK_ACTIONS, fcErrorSentence, freightClassOf, freightcomIdOf, isPdf, labelPath, noAccountSentence, palletBoxes, parseServices, PAYMENT_CACHE_MS, paymentCacheKey, paymentMethodOf, pickLabels, pickServices, POLL_INTERVAL_MS, QUOTE_WAIT_MS, rateBody, rateStatus, requestIdOf, secretNameFor, SERVICES_CACHE_MS, servicesCacheKey, shouldKeepBookPolling, shouldKeepPolling, type FcLabel, type FcService, type RateRequest } from "../_shared/freightcom.ts";
import { pdfPages, sha256Hex } from "../_shared/doc.ts";
import { sleep } from "../_shared/shopify.ts";

const CALL_LOG_KEEP_DAYS = 90;
const SIGN_SECONDS = 120;
const STORAGE_TIMEOUT_MS = 20_000;
const LABEL_FETCH_TIMEOUT_MS = 20_000;
const CORS: HeadersInit = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON = () => Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const FC_KEY = (account: string) => apiKeyFor((k) => Deno.env.get(k), account);                            // fc-1b4 판정 848: 계정별 FREIGHTCOM_API_KEY_<계정> · 옛 FREIGHTCOM_API_KEY 는 안 읽는다
const FC_BASE = () => (Deno.env.get("FREIGHTCOM_BASE_URL") ?? "").trim().replace(/\/+$/, "");
const json = (status: number, obj: unknown): Response => new Response(JSON.stringify(obj, null, 2), { status, headers: { "Content-Type": "application/json", ...CORS } });
const sbHeaders = (extra: Record<string, string> = {}): HeadersInit => ({ apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/json", ...extra });
async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { headers: sbHeaders() });
  if (!r.ok) throw new Error("sbGet " + path.split("?")[0] + " " + r.status + ": " + (await r.text()).slice(0, 300));
  return await r.json();
}
async function sbWrite(method: string, path: string, body?: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { method, headers: sbHeaders({ Prefer: "return=minimal" }), body: body === undefined ? undefined : JSON.stringify(body) });
  if (!r.ok) throw new Error("sb " + method + " " + path.split("?")[0] + " " + r.status + ": " + (await r.text()).slice(0, 300));
}
// rpc 두 길 — service_role(fc_quote_pending · fc_quote_save · fc_book_pending_set · fc_book_save · fc_book_cancel_save · fc_label_add) · 사용자 JWT(prepare · for_so · book_prepare · cancel_prepare · label_get · for_shipment — DB 의 문이 그 사람을 본다) · PostgREST 오류는 사람 말(message)로
class RpcError extends Error { constructor(public status: number, message: string) { super(message); } }
async function rpc(fn: string, args: Record<string, unknown>, jwt: string | null): Promise<unknown> {
  const headers: Record<string, string> = jwt ? { apikey: ANON(), Authorization: "Bearer " + jwt, "Content-Type": "application/json" } : { apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/json" };
  const r = await fetch(SB_URL() + "/rest/v1/rpc/" + fn, { method: "POST", headers, body: JSON.stringify(args) });
  const text = await r.text();
  if (!r.ok) {
    let msg = text.slice(0, 400);
    try { const j = JSON.parse(text); msg = String(j.message ?? j.error ?? msg); } catch { /* 글자 그대로 */ }
    throw new RpcError(r.status, msg);
  }
  return text ? JSON.parse(text) : null;
}
type LogRow = { shipment_id: string | null; account: string | null; action: string; ok: boolean; http_status: number | null; error: string | null; by_staff: string | null; ms: number };
async function recordCall(row: LogRow): Promise<void> {
  try {
    await sbWrite("POST", "fc_call_log", { ...row, error: row.error ? row.error.slice(0, 400) : null });
    try { await sbWrite("DELETE", "fc_call_log?called_at=lt." + encodeURIComponent(new Date(Date.now() - CALL_LOG_KEEP_DAYS * 86_400_000).toISOString())); } catch (e) { console.warn("call_log purge failed:", String(e).slice(0, 200)); }
  } catch (e) { console.warn("recordCall failed:", String(e).slice(0, 300)); }
}

// ── 문 — 동작 묶음마다(fc-2c): quote = sales | fulfillment · book = freight_booking(853 · 854) · label = 셋 중 하나 ──
type Caller = { jwt: string; staffId: string | null; mode: "office" | "wms" };
async function gate(req: Request, need: "quote" | "book" | "label"): Promise<Caller | Response> {
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json(401, { ok: false, error: "Missing Authorization" });
  const can = async (screen: string): Promise<boolean | Response> => {
    const r = await fetch(SB_URL() + "/rest/v1/rpc/ims_can_write", { method: "POST", headers: { apikey: ANON(), Authorization: "Bearer " + jwt, "Content-Type": "application/json" }, body: JSON.stringify({ p_screen: screen }) });
    if (r.status === 401) return json(401, { ok: false, error: "Invalid session — sign in again" });
    if (!r.ok) return json(502, { ok: false, error: "Permission check failed (ims_can_write): " + (await r.text()).slice(0, 200) });
    return (await r.json()) === true;
  };
  const sales = await can("sales"); if (sales instanceof Response) return sales;
  let mode: Caller["mode"] = sales ? "office" : "wms";
  if (need === "book") {
    const fb = await can("freight_booking"); if (fb instanceof Response) return fb;
    if (!fb) return json(403, { ok: false, error: "Not allowed — booking or cancelling freight needs the 'freight_booking' permission (admin and supervisor always · others person by person)" });
  } else if (!sales) {
    const ful = await can("fulfillment"); if (ful instanceof Response) return ful;
    if (!ful) {
      const fb = need === "label" ? await can("freight_booking") : false; if (fb instanceof Response) return fb;
      if (!fb) return json(403, { ok: false, error: need === "label" ? "Not allowed — freight labels need the 'sales', 'fulfillment' or 'freight_booking' permission" : "Not allowed — freight quotes need the 'sales' (office) or 'fulfillment' (warehouse) permission" });
    }
    mode = "wms";
  }
  let staffId: string | null = null;
  try {
    const u = await fetch(SB_URL() + "/auth/v1/user", { headers: { apikey: ANON(), Authorization: "Bearer " + jwt } });
    const uid = u.ok ? String((await u.json())?.id ?? "") : "";
    if (uid) staffId = (await sbGet("ims_staff?select=id&auth_user_id=eq." + uid + "&limit=1"))[0]?.id ?? null;
  } catch (e) { console.warn("by_staff lookup failed:", String(e).slice(0, 200)); }
  return { jwt, staffId, mode };
}

// ── Freightcom 호출 하나 = 기록 한 줄 · tolerate = 2xx 가 아니어도 던지지 않고 몸을 돌려준다(예약 400 · 취소 403 을 읽어야 한다) ──
type FcResult = { status: number; body: unknown; error: string | null };
async function fcCall(account: string, action: string, method: "GET" | "POST" | "DELETE", path: string, body: unknown, caller: Caller, shipmentId: string | null, tolerate = false): Promise<FcResult> {
  const t0 = Date.now();
  let status = 0, parsed: unknown = null, err: string | null = null;
  try {
    const r = await fetch(FC_BASE() + path, { method, headers: { Authorization: FC_KEY(account), Accept: "application/json", "Content-Type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
    status = r.status;
    const text = await r.text();
    try { parsed = text ? JSON.parse(text) : null; } catch { parsed = text; }
    if (!r.ok) err = fcErrorSentence(action, status, parsed);
  } catch (e) {
    err = "Freightcom " + action + " unreachable: " + String((e as Error)?.message ?? e).slice(0, 200);
  }
  await recordCall({ shipment_id: shipmentId, account, action, ok: err === null, http_status: status || null, error: err, by_staff: caller.staffId, ms: Date.now() - t0 });
  if (err && !tolerate) throw new RpcError(502, err);
  return { status, body: parsed, error: err };
}

// /services 10 분 캐시(함수 인스턴스 메모리 · 계정마다 · fc-1b4) · 결제수단도 같은 꼴(fc-2c)
const servicesCache = new Map<string, { at: number; list: FcService[] }>();
async function loadServices(account: string, caller: Caller): Promise<FcService[]> {
  const k = servicesCacheKey(account), c = servicesCache.get(k);
  if (c && Date.now() - c.at < SERVICES_CACHE_MS) return c.list;
  const r = await fcCall(account, "services", "GET", "/services", undefined, caller, null);
  const list = parseServices(r.body);
  servicesCache.set(k, { at: Date.now(), list });
  return list;
}
const paymentCache = new Map<string, { at: number; pm: { id: string; type: string; label: string } }>();
async function loadPaymentMethod(account: string, caller: Caller, shipmentId: string): Promise<{ id: string; type: string; label: string }> {
  const k = paymentCacheKey(account), c = paymentCache.get(k);
  if (c && Date.now() - c.at < PAYMENT_CACHE_MS) return c.pm;
  const r = await fcCall(account, "payment_methods", "GET", "/finance/payment-methods", undefined, caller, shipmentId);
  const pm = paymentMethodOf(r.body);
  paymentCache.set(k, { at: Date.now(), pm });
  return pm;
}
// 계정이 있는 창고 목록(status · services 의 기본 계정) — 활성 창고 · 계정 있음
async function accountsInUse(): Promise<{ warehouse: string; account: string; has_key: boolean }[]> {
  const rows = await sbGet("ref_warehouse?select=name,freightcom_account&is_active=eq.true&freightcom_account=not.is.null&order=name");
  return rows.map((w: { name: string; freightcom_account: string }) => ({ warehouse: w.name, account: w.freightcom_account, has_key: FC_KEY(w.freightcom_account) !== "" }));
}

// ── 견적(fc-1b · 흐름 무접촉) ──
async function pollRates(account: string, requestId: string, caller: Caller, shipmentId: string): Promise<{ done: true; body: unknown } | { done: false; complete: number; total: number }> {
  const started = Date.now();
  let st = { done: false, complete: 0, total: 0 };
  while (true) {
    const r = await fcCall(account, "rate_poll", "GET", "/rate/" + encodeURIComponent(requestId), undefined, caller, shipmentId);
    st = rateStatus(r.body);
    if (st.done) return { done: true, body: r.body };
    if (!shouldKeepPolling(st, started, Date.now(), QUOTE_WAIT_MS)) return { done: false, complete: st.complete, total: st.total };
    await sleep(POLL_INTERVAL_MS);
  }
}
async function finishQuote(account: string, shipmentId: string, requestId: string, sent: Record<string, unknown> | null, chargeSoId: string | null, caller: Caller): Promise<Response> {
  const p = await pollRates(account, requestId, caller, shipmentId);
  if (!p.done) return json(202, { ok: true, pending: true, shipment_id: shipmentId, request_id: requestId, complete: p.complete, total: p.total, wait_ms: QUOTE_WAIT_MS });
  const saved = await rpc("fc_quote_save", { p_shipment_id: shipmentId, p_request_id: requestId, p_response: p.body, p_error: null, p_request: sent }, null);
  const detail = chargeSoId ? await rpc("fc_shipment_for_so", { p_so_id: chargeSoId }, caller.jwt) : null;
  return json(200, { ok: true, pending: false, shipment_id: shipmentId, request_id: requestId, quote: saved, detail });
}
async function quote(body: Record<string, unknown>, caller: Caller): Promise<Response> {
  const soIds = Array.isArray(body.so_ids) ? body.so_ids.map(String) : [];
  if (soIds.length === 0) return json(400, { ok: false, error: "so_ids must be a list of order ids" });
  // fc-1b4 판정 848: 미리 보기(쓰기 0)로 출발 창고의 계정을 먼저 보고 — 그 계정의 비밀값이 없으면 아무것도 저장하지 않고 422
  const peek = await rpc("fc_shipment_prepare", { p_so_ids: soIds, p_options: body.options ?? {}, p_commit: false }, caller.jwt) as Record<string, unknown>;
  const account = String(peek.freightcom_account ?? "").trim();
  if (!account || !FC_KEY(account)) return json(422, { ok: false, error: noAccountSentence(null, account || "??"), account: account || null, saved: false });
  const prepare = await rpc("fc_shipment_prepare", { p_so_ids: soIds, p_options: body.options ?? {}, p_commit: true }, caller.jwt) as Record<string, unknown>;
  const shipmentId = String(prepare.shipment_id), chargeSoId = String(prepare.charge_so_id ?? "") || null;
  let req = prepare.request as RateRequest;
  let serviceIds: string[] | null = null, services: { matched: string[]; unmatched: string[] } | null = null;
  if (req.details.packaging_type === "pallet") {
    const classes: string[] = [];
    for (const box of palletBoxes(req)) classes.push(freightClassOf((await fcCall(account, "freight_class", "POST", "/freight-class/calculate", { box }, caller, shipmentId)).body));
    req = attachFreightClass(req, classes);
  } else {
    const names = Array.isArray(prepare.carriers) ? prepare.carriers.map(String) : [];
    const picked = pickServices(await loadServices(account, caller), names);
    services = { matched: picked.matched, unmatched: picked.unmatched };
    if (picked.ids.length === 0) return json(422, { ok: false, error: "No carrier on the IMS carrier list has a Freightcom name that Freightcom knows — set 'Freightcom carrier' under Settings → Carriers (e.g. UPS · Purolator · Canada Post)", shipment_id: shipmentId, carriers: names, services });
    serviceIds = picked.ids;
  }
  const sent = rateBody(req, serviceIds);
  const r = await fcCall(account, "rate", "POST", "/rate", sent, caller, shipmentId);
  const requestId = requestIdOf(r.body);
  await rpc("fc_quote_pending", { p_shipment_id: shipmentId, p_request_id: requestId, p_request: sent }, null);
  const res = await finishQuote(account, shipmentId, requestId, sent, chargeSoId, caller);
  const out = await res.json();
  return json(res.status, { ...out, account, prepare: { action: prepare.action, mode: prepare.mode, packaging_type: prepare.packaging_type, charge_so_number: prepare.charge_so_number, so_numbers: prepare.so_numbers, options: prepare.options, address_id: prepare.address_id, address_review: prepare.address_review, freight_locked: prepare.freight_locked, warnings: prepare.warnings, services } });
}

// ── 예약(fc-2c) ──
// 저장소(documents 버킷 · EF doc 선례) — service_role 로 올리고 짧은 서명 URL
async function storageUpload(path: string, bytes: Uint8Array): Promise<void> {
  const r = await fetch(SB_URL() + "/storage/v1/object/documents/" + path, { method: "POST", headers: { apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/pdf", "x-upsert": "true" }, body: bytes.slice(), signal: AbortSignal.timeout(STORAGE_TIMEOUT_MS) });
  if (!r.ok) throw new Error(`storage upload ${r.status}: ${(await r.text()).slice(0, 200)}`);
}
async function storageSign(path: string): Promise<string> {
  const r = await fetch(SB_URL() + "/storage/v1/object/sign/documents/" + path, { method: "POST", headers: { apikey: SERVICE(), Authorization: "Bearer " + SERVICE(), "Content-Type": "application/json" }, body: JSON.stringify({ expiresIn: SIGN_SECONDS }), signal: AbortSignal.timeout(STORAGE_TIMEOUT_MS) });
  if (!r.ok) throw new Error(`storage sign ${r.status}: ${(await r.text()).slice(0, 200)}`);
  const s = String((await r.json())?.signedURL ?? "");
  if (!s) throw new Error("storage sign: no signedURL in the answer");
  return s.startsWith("http") ? s : SB_URL() + "/storage/v1" + (s.startsWith("/") ? "" : "/") + s;
}
type Booking = { id: string; shipment_id: string; attempt: number; status: string; account: string | null; freightcom_shipment_id: string | null; labels: unknown };
async function loadBooking(bookingId: string): Promise<Booking | null> {
  return (await sbGet("fc_booking?select=id,shipment_id,attempt,status,account,freightcom_shipment_id,labels&id=eq." + encodeURIComponent(bookingId) + "&limit=1"))[0] ?? null;
}
// ⑤ 라벨 받기 — a6 pdf + letter pdf(세로) · Freightcom url 은 S3(Authorization 없이) · %PDF 확인 · documents/fc_label/… · fc_label_add · 실패는 warnings(예약은 그대로)
async function fetchLabels(account: string, b: Booking, caller: Caller): Promise<{ saved: Record<string, unknown>[]; skipped: string[]; warnings: string[] }> {
  const picked = pickLabels(b.labels);
  const saved: Record<string, unknown>[] = [], warnings: string[] = [];
  for (const l of [picked.a6, picked.letter].filter((x): x is FcLabel => x !== null)) {
    const t0 = Date.now();
    let status = 0, err: string | null = null;
    try {
      const r = await fetch(l.url, { signal: AbortSignal.timeout(LABEL_FETCH_TIMEOUT_MS) });
      status = r.status;
      if (!r.ok) throw new Error(`label ${l.size} fetch HTTP ${r.status}`);
      const bytes = new Uint8Array(await r.arrayBuffer());
      if (!isPdf(bytes)) throw new Error(`label ${l.size} is not a PDF (${bytes.length} bytes)`);
      const path = labelPath(b.shipment_id, b.attempt, l.size, l.padded);
      await storageUpload(path, bytes);
      const row = await rpc("fc_label_add", { p: { booking_id: b.id, size: l.size, padded: l.padded, path, bytes: bytes.length, sha256: await sha256Hex(bytes), pages: pdfPages(bytes), source_url: l.url, fetched_by: caller.staffId } }, null) as Record<string, unknown>;
      saved.push({ label_id: row.id, size: l.size, padded: l.padded, path, bytes: bytes.length, pages: row.pages ?? null });
    } catch (e) {
      err = String((e as Error)?.message ?? e).slice(0, 300);
      warnings.push(`label_${l.size}: ${err}`);
    }
    await recordCall({ shipment_id: b.shipment_id, account, action: "label_fetch", ok: err === null, http_status: status || null, error: err, by_staff: caller.staffId, ms: Date.now() - t0 });
  }
  return { saved, skipped: picked.skipped, warnings };
}
// ④ GET /shipment/{id} 다시 묻기 → 저장 → 라벨
async function finishBook(account: string, b: Booking, fcId: string, caller: Caller): Promise<Response> {
  const started = Date.now();
  while (true) {
    const r = await fcCall(account, "book_poll", "GET", "/shipment/" + encodeURIComponent(fcId), undefined, caller, b.shipment_id, true);
    const o = bookOutcome(r.status, r.body);
    if (o.kind === "failed") {
      const failed = await rpc("fc_book_save", { p_booking_id: b.id, p_response: r.body, p_error: o.error }, null);
      return json(422, { ok: false, error: o.error, booking_id: b.id, attempt: b.attempt, status: "failed", booking: failed });
    }
    if (o.kind === "done") {
      const saved = await rpc("fc_book_save", { p_booking_id: b.id, p_response: r.body, p_error: null }, null) as Record<string, unknown>;
      const labels = await fetchLabels(account, { ...b, status: "booked", freightcom_shipment_id: fcId, labels: o.shipment.labels }, caller);
      const detail = await rpc("fc_booking_for_shipment", { p_shipment_id: b.shipment_id }, caller.jwt);
      return json(200, { ok: true, pending: false, booking_id: b.id, attempt: b.attempt, status: "booked", booking: saved, labels, detail });
    }
    if (!shouldKeepBookPolling(o, started, Date.now(), BOOK_WAIT_MS)) return json(202, { ok: true, pending: true, booking_id: b.id, attempt: b.attempt, shipment_id: b.shipment_id, freightcom_shipment_id: fcId, wait_ms: BOOK_WAIT_MS });
    await sleep(POLL_INTERVAL_MS);
  }
}
async function book(body: Record<string, unknown>, caller: Caller): Promise<Response> {
  const shipmentId = String(body.shipment_id ?? "");
  if (!shipmentId) return json(400, { ok: false, error: "shipment_id is required" });
  const pickup = body.pickup && typeof body.pickup === "object" ? body.pickup : {};
  const peek = await rpc("fc_book_prepare", { p_shipment_id: shipmentId, p_pickup: pickup, p_commit: false }, caller.jwt) as Record<string, unknown>;   // 쓰기 0 — 비밀값 없으면 여기서 끝
  const account = String(peek.account ?? "").trim();
  if (!account || !FC_KEY(account)) return json(422, { ok: false, error: noAccountSentence(null, account || "??"), account: account || null, saved: false });
  const prep = await rpc("fc_book_prepare", { p_shipment_id: shipmentId, p_pickup: pickup, p_commit: true }, caller.jwt) as Record<string, unknown>;        // pending 행
  const bookingId = String(prep.booking_id), attempt = Number(prep.attempt ?? 0);
  const b: Booking = { id: bookingId, shipment_id: shipmentId, attempt, status: "pending", account, freightcom_shipment_id: null, labels: null };
  const pm = await loadPaymentMethod(account, caller, shipmentId);
  const sent = bookBody(prep.request as Record<string, unknown>, pm.id);
  const r = await fcCall(account, "book", "POST", "/shipment", sent, caller, shipmentId, true);
  if (r.status < 200 || r.status >= 300) {
    const error = bookErrorSentence(r.status, r.body);
    const failed = await rpc("fc_book_save", { p_booking_id: bookingId, p_response: r.body, p_error: error }, null);
    return json(422, { ok: false, error, booking_id: bookingId, attempt, status: "failed", booking: failed, pickup: prep.pickup, warnings: prep.warnings });
  }
  const fcId = freightcomIdOf(r.body);
  await rpc("fc_book_pending_set", { p_booking_id: bookingId, p_freightcom_shipment_id: fcId, p_request: sent }, null);
  const res = await finishBook(account, b, fcId, caller);
  const out = await res.json();
  return json(res.status, { ...out, account, payment_method: { type: pm.type, label: pm.label }, pickup: prep.pickup, prepare_warnings: prep.warnings });   // 결제수단 id 는 돌려주지 않는다(request 에 남는다)
}
async function bookPoll(body: Record<string, unknown>, caller: Caller): Promise<Response> {
  const bookingId = String(body.booking_id ?? "");
  if (!bookingId) return json(400, { ok: false, error: "booking_id is required" });
  const b = await loadBooking(bookingId);
  if (!b) return json(404, { ok: false, error: "booking not found" });
  const account = String(b.account ?? "").trim();
  if (!account || !FC_KEY(account)) return json(422, { ok: false, error: noAccountSentence(null, account || "??") });
  if (b.status === "failed" || b.status === "cancelled") return json(422, { ok: false, error: `Booking #${b.attempt} is ${b.status}`, booking_id: b.id, status: b.status });
  if (b.status === "booked") {                                                                        // 이미 끝 — 라벨이 없으면 ⑤ 만 다시(Freightcom url 만료 전에)
    const have = await sbGet("fc_label?select=id&booking_id=eq." + encodeURIComponent(b.id));
    const labels = have.length === 0 ? await fetchLabels(account, b, caller) : null;
    return json(200, { ok: true, pending: false, booking_id: b.id, attempt: b.attempt, status: "booked", labels, detail: await rpc("fc_booking_for_shipment", { p_shipment_id: b.shipment_id }, caller.jwt) });
  }
  if (!b.freightcom_shipment_id) return json(409, { ok: false, error: `Booking #${b.attempt} has no Freightcom shipment id yet — the first call did not get past POST /shipment · after 10 minutes a new attempt sets it aside`, booking_id: b.id, status: b.status });
  return await finishBook(account, b, b.freightcom_shipment_id, caller);
}
async function cancel(body: Record<string, unknown>, caller: Caller): Promise<Response> {
  const shipmentId = String(body.shipment_id ?? "");
  if (!shipmentId) return json(400, { ok: false, error: "shipment_id is required" });
  const prep = await rpc("fc_book_cancel_prepare", { p_shipment_id: shipmentId }, caller.jwt) as Record<string, unknown>;   // 쓰기 0 · 문 · shipped 거부
  const account = String(prep.account ?? "").trim(), bookingId = String(prep.booking_id), fcId = String(prep.freightcom_shipment_id ?? "");
  if (!account || !FC_KEY(account)) return json(422, { ok: false, error: noAccountSentence(null, account || "??") });
  if (!fcId) return json(409, { ok: false, error: "The booking has no Freightcom shipment id — nothing to cancel there", booking_id: bookingId });
  const r = await fcCall(account, "cancel", "DELETE", "/shipment/" + encodeURIComponent(fcId), undefined, caller, shipmentId, true);
  const o = cancelOutcome(r.status, r.body);
  if (!o.ok) {
    const kept = await rpc("fc_book_cancel_save", { p_booking_id: bookingId, p_response: null, p_error: o.error }, null);
    return json(422, { ok: false, error: o.error, booking_id: bookingId, booking: kept });
  }
  const saved = await rpc("fc_book_cancel_save", { p_booking_id: bookingId, p_response: { cancelled_by: caller.staffId, http_status: r.status, body: r.body }, p_error: null }, null);
  return json(200, { ok: true, booking_id: bookingId, cancel: saved, detail: await rpc("fc_booking_for_shipment", { p_shipment_id: shipmentId }, caller.jwt) });
}
async function label(body: Record<string, unknown>, caller: Caller): Promise<Response> {
  const labelId = String(body.label_id ?? "");
  if (!labelId) return json(400, { ok: false, error: "label_id is required" });
  const l = await rpc("fc_label_get", { p_label_id: labelId }, caller.jwt) as Record<string, unknown>;   // 문은 DB(sales · fulfillment · freight_booking)
  return json(200, { ok: true, label_id: l.id, booking_id: l.booking_id, size: l.size, padded: l.padded, path: l.path, bytes: l.bytes, pages: l.pages, signed_url: await storageSign(String(l.path)), expires_in: SIGN_SECONDS });
}

Deno.serve(async (req) => {
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") return json(405, { ok: false, error: "POST only" });
    let dbRole: string | null = null;
    try { dbRole = String((await sbGet("inv_config?select=value&key=eq.db_role"))[0]?.value ?? ""); } catch { dbRole = null; }
    if (dbRole !== "test") return json(500, { ok: false, error: "inv_config.db_role is " + String(dbRole ?? "missing") + " - this function runs on the test project only (Asung-IMS) - refusing" });
    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const action = String(body?.action ?? "");
    const all = [...FC_ACTIONS, ...FC_BOOK_ACTIONS] as readonly string[];
    if (!all.includes(action)) return json(400, { ok: false, error: "action must be one of: " + all.join(", ") });
    const caller = await gate(req, action === "label" ? "label" : (FC_BOOK_ACTIONS as readonly string[]).includes(action) ? "book" : "quote");
    if (caller instanceof Response) return caller;
    if (action === "status") return json(200, { ok: true, base_url: FC_BASE() || null, accounts: (await accountsInUse()).map((a) => ({ ...a, secret: secretNameFor(a.account) })), legacy_key_still_set: (Deno.env.get("FREIGHTCOM_API_KEY") ?? "") !== "", mode: caller.mode, wait_ms: QUOTE_WAIT_MS, book_wait_ms: BOOK_WAIT_MS });   // 값 없음 · 계정마다 유무 · 옛 이름이 남아 있으면 알린다(지우라고)
    if (action === "label") return await label(body, caller);                                           // Freightcom 호출 없음 — 저장소만
    if (!FC_BASE()) return json(500, { ok: false, error: "FREIGHTCOM_BASE_URL not configured on this project - refusing (fail-closed)" });
    if (action === "services") {                                                                       // {account} — 없으면 계정 있는 창고가 하나뿐일 때 그것
      let account = String(body.account ?? "").trim().toUpperCase();
      if (!account) { const a = await accountsInUse(); if (a.length === 1) account = a[0].account; else return json(400, { ok: false, error: "account is required (one of: " + a.map((x) => x.account).join(", ") + ")" }); }
      if (!ACCOUNT_RE.test(account)) return json(400, { ok: false, error: "account must be 2–10 upper-case letters or digits" });
      if (!FC_KEY(account)) return json(422, { ok: false, error: noAccountSentence(null, account) });
      const list = await loadServices(account, caller);
      return json(200, { ok: true, account, carriers: distinctCarriers(list), services: list, count: list.length });
    }
    if (action === "quote") return await quote(body, caller);
    if (action === "quote_poll") {
      const shipmentId = String(body.shipment_id ?? ""), requestId = String(body.request_id ?? "");
      if (!shipmentId || !requestId) return json(400, { ok: false, error: "shipment_id and request_id are required" });
      const f = (await sbGet("fc_shipment?select=id,charge_so_id,status,freightcom_account&id=eq." + encodeURIComponent(shipmentId) + "&limit=1"))[0];
      if (!f) return json(404, { ok: false, error: "shipment not found" });
      const account = String(f.freightcom_account ?? "").trim();                                      // fc-1b4: 발송의 계정 스냅샷으로(창고를 다시 보지 않는다)
      if (!account || !FC_KEY(account)) return json(422, { ok: false, error: noAccountSentence(null, account || "??") });
      return await finishQuote(account, shipmentId, requestId, null, f.charge_so_id ?? null, caller);
    }
    if (action === "book") return await book(body, caller);
    if (action === "book_poll") return await bookPoll(body, caller);
    if (action === "cancel") return await cancel(body, caller);
    return json(400, { ok: false, error: "unknown action" });
  } catch (e) {
    if (e instanceof RpcError) return json(e.status === 502 ? 502 : 422, { ok: false, error: e.message });
    return json(500, { ok: false, error: String((e as Error)?.message ?? e).slice(0, 400) });
  }
});
