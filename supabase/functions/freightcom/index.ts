// ============================================================
// ASUNG IMS — Edge Function: freightcom (fc-1b · 2026-10-28 · 판정 835 ~ 845 · DB fc-1a 20261028162209 · fc-1b 20261028170402 · 순수 함수 ../_shared/freightcom.ts)
//   ⚠️ 테스트 프로젝트(Asung-IMS · fazgmyvzzhqybtvtktyg) 전용 — 시작 때 inv_config.db_role = 'test' 가 아니면 멈춘다. 비밀값 FREIGHTCOM_API_KEY · FREIGHTCOM_BASE_URL(없으면 500 fail-closed) — 토큰은 응답 · 기록 · 오류 문장 어디에도 안 남는다.
//   POST JSON {action, …} · 응답 json(status) · CORS · cron 길 없음(직원 길만 · verify_jwt=false 라 문은 함수 안):
//     문  Authorization: Bearer <세션 JWT> → rpc/ims_can_write('sales') 또는 ('fulfillment')(둘 다 false → 403) · /auth/v1/user → ims_staff.id(by_staff) — 실제 검사(창고 · 상태 · 치수 · 835 두 문)는 DB 창구 fc_shipment_prepare 가 사용자 JWT 로 다시 한다
//     quote {so_ids[], options{residential · tailgate_required · threshold_delivery · remember · ship_date}}
//        ① rpc/fc_shipment_prepare(사용자 JWT · p_commit true) — 거부면 그 문장 그대로 422
//        ② 팔렛이면 팔렛마다 POST /freight-class/calculate {box: measurements} → freight_class 끼움
//        ③ services: 상자 = GET /services(10 분 캐시)를 prepare.carriers(ref_carrier_fc_name 의 이름 전부 · fc-1b3)로 거른 id 만(하나도 없으면 422 — Settings 에서 운송사의 Freightcom 이름) · 팔렛 = services 없이
//        ④ POST /rate → 202 {request_id} → service_role rpc/fc_quote_pending(발송 · request_id · 실제 보낸 몸) → GET /rate/{id} 를 1.5 초마다 · 최대 25 초
//        ⑤ done → service_role rpc/fc_quote_save(…, p_request = 보낸 몸) → {ok, pending:false, prepare, quote, detail: rpc/fc_shipment_for_so(사용자 JWT · charge SO)} · 아니면 {ok, pending:true, shipment_id, request_id, complete, total}
//     quote_poll {shipment_id, request_id} — ④ 의 다시 묻기부터(화면의 Check again · pending 줄이 done 으로)
//     services — 운송사 이름 고유 목록 + 서비스 전부(Settings 에서 운송사의 Freightcom 이름(ref_carrier_fc_names_set)을 고를 때)
//     status — 비밀값 유무 · base url(토큰 값 없음) · Freightcom 호출 없음
//   Freightcom 호출 한 번 = fc_call_log 한 줄(service_role REST · action · ok · http_status · error · by_staff · shipment_id · ms) · 90 일 지난 줄은 호출 끝에 지운다
//   배포: supabase functions deploy freightcom --project-ref fazgmyvzzhqybtvtktyg (config.toml [functions.freightcom] verify_jwt=false)
// ============================================================
import { attachFreightClass, distinctCarriers, FC_ACTIONS, fcErrorSentence, freightClassOf, palletBoxes, parseServices, pickServices, POLL_INTERVAL_MS, QUOTE_WAIT_MS, rateBody, rateStatus, requestIdOf, SERVICES_CACHE_MS, shouldKeepPolling, type FcService, type RateRequest } from "../_shared/freightcom.ts";
import { sleep } from "../_shared/shopify.ts";

const CALL_LOG_KEEP_DAYS = 90;
const CORS: HeadersInit = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON = () => Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const FC_KEY = () => (Deno.env.get("FREIGHTCOM_API_KEY") ?? "").trim();
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
// rpc 두 길 — service_role(fc_quote_pending · fc_quote_save) · 사용자 JWT(fc_shipment_prepare · fc_shipment_for_so — DB 의 문이 그 사람을 본다) · PostgREST 오류는 사람 말(message)로
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
type LogRow = { shipment_id: string | null; action: string; ok: boolean; http_status: number | null; error: string | null; by_staff: string | null; ms: number };
async function recordCall(row: LogRow): Promise<void> {
  try {
    await sbWrite("POST", "fc_call_log", { ...row, error: row.error ? row.error.slice(0, 400) : null });
    try { await sbWrite("DELETE", "fc_call_log?called_at=lt." + encodeURIComponent(new Date(Date.now() - CALL_LOG_KEEP_DAYS * 86_400_000).toISOString())); } catch (e) { console.warn("call_log purge failed:", String(e).slice(0, 200)); }
  } catch (e) { console.warn("recordCall failed:", String(e).slice(0, 300)); }
}

// ── 문 ──
type Caller = { jwt: string; staffId: string | null; mode: "office" | "wms" };
async function gate(req: Request): Promise<Caller | Response> {
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json(401, { ok: false, error: "Missing Authorization" });
  const can = async (screen: string): Promise<boolean | Response> => {
    const r = await fetch(SB_URL() + "/rest/v1/rpc/ims_can_write", { method: "POST", headers: { apikey: ANON(), Authorization: "Bearer " + jwt, "Content-Type": "application/json" }, body: JSON.stringify({ p_screen: screen }) });
    if (r.status === 401) return json(401, { ok: false, error: "Invalid session — sign in again" });
    if (!r.ok) return json(502, { ok: false, error: "Permission check failed (ims_can_write): " + (await r.text()).slice(0, 200) });
    return (await r.json()) === true;
  };
  const sales = await can("sales"); if (sales instanceof Response) return sales;
  let mode: Caller["mode"] = "office";
  if (!sales) {
    const ful = await can("fulfillment"); if (ful instanceof Response) return ful;
    if (!ful) return json(403, { ok: false, error: "Not allowed — freight quotes need the 'sales' (office) or 'fulfillment' (warehouse) permission" });
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

// ── Freightcom 호출 하나 = 기록 한 줄 ──
type FcResult = { status: number; body: unknown };
async function fcCall(action: string, method: "GET" | "POST", path: string, body: unknown, caller: Caller, shipmentId: string | null): Promise<FcResult> {
  const t0 = Date.now();
  let status = 0, parsed: unknown = null, err: string | null = null;
  try {
    const r = await fetch(FC_BASE() + path, { method, headers: { Authorization: FC_KEY(), Accept: "application/json", "Content-Type": "application/json" }, body: body === undefined ? undefined : JSON.stringify(body) });
    status = r.status;
    const text = await r.text();
    try { parsed = text ? JSON.parse(text) : null; } catch { parsed = text; }
    if (!r.ok) err = fcErrorSentence(action, status, parsed);
  } catch (e) {
    err = "Freightcom " + action + " unreachable: " + String((e as Error)?.message ?? e).slice(0, 200);
  }
  await recordCall({ shipment_id: shipmentId, action, ok: err === null, http_status: status || null, error: err, by_staff: caller.staffId, ms: Date.now() - t0 });
  if (err) throw new RpcError(502, err);
  return { status, body: parsed };
}

// /services 10 분 캐시(함수 인스턴스 메모리)
let servicesCache: { at: number; list: FcService[] } | null = null;
async function loadServices(caller: Caller): Promise<FcService[]> {
  if (servicesCache && Date.now() - servicesCache.at < SERVICES_CACHE_MS) return servicesCache.list;
  const r = await fcCall("services", "GET", "/services", undefined, caller, null);
  const list = parseServices(r.body);
  servicesCache = { at: Date.now(), list };
  return list;
}

// GET /rate/{id} 를 시한 안에서 되묻는다 → done 이면 응답 원문 · 아니면 상태만
async function pollRates(requestId: string, caller: Caller, shipmentId: string): Promise<{ done: true; body: unknown } | { done: false; complete: number; total: number }> {
  const started = Date.now();
  let st = { done: false, complete: 0, total: 0 };
  while (true) {
    const r = await fcCall("rate_poll", "GET", "/rate/" + encodeURIComponent(requestId), undefined, caller, shipmentId);
    st = rateStatus(r.body);
    if (st.done) return { done: true, body: r.body };
    if (!shouldKeepPolling(st, started, Date.now(), QUOTE_WAIT_MS)) return { done: false, complete: st.complete, total: st.total };
    await sleep(POLL_INTERVAL_MS);
  }
}

async function finishQuote(shipmentId: string, requestId: string, sent: Record<string, unknown> | null, chargeSoId: string | null, caller: Caller): Promise<Response> {
  const p = await pollRates(requestId, caller, shipmentId);
  if (!p.done) return json(202, { ok: true, pending: true, shipment_id: shipmentId, request_id: requestId, complete: p.complete, total: p.total, wait_ms: QUOTE_WAIT_MS });
  const saved = await rpc("fc_quote_save", { p_shipment_id: shipmentId, p_request_id: requestId, p_response: p.body, p_error: null, p_request: sent }, null);
  const detail = chargeSoId ? await rpc("fc_shipment_for_so", { p_so_id: chargeSoId }, caller.jwt) : null;
  return json(200, { ok: true, pending: false, shipment_id: shipmentId, request_id: requestId, quote: saved, detail });
}

async function quote(body: Record<string, unknown>, caller: Caller): Promise<Response> {
  const soIds = Array.isArray(body.so_ids) ? body.so_ids.map(String) : [];
  if (soIds.length === 0) return json(400, { ok: false, error: "so_ids must be a list of order ids" });
  const prepare = await rpc("fc_shipment_prepare", { p_so_ids: soIds, p_options: body.options ?? {}, p_commit: true }, caller.jwt) as Record<string, unknown>;
  const shipmentId = String(prepare.shipment_id), chargeSoId = String(prepare.charge_so_id ?? "") || null;
  let req = prepare.request as RateRequest;
  let serviceIds: string[] | null = null, services: { matched: string[]; unmatched: string[] } | null = null;
  if (req.details.packaging_type === "pallet") {
    const classes: string[] = [];
    for (const box of palletBoxes(req)) classes.push(freightClassOf((await fcCall("freight_class", "POST", "/freight-class/calculate", { box }, caller, shipmentId)).body));
    req = attachFreightClass(req, classes);
  } else {
    const names = Array.isArray(prepare.carriers) ? prepare.carriers.map(String) : [];
    const picked = pickServices(await loadServices(caller), names);
    services = { matched: picked.matched, unmatched: picked.unmatched };
    if (picked.ids.length === 0) return json(422, { ok: false, error: "No carrier on the IMS carrier list has a Freightcom name that Freightcom knows — set 'Freightcom carrier' under Settings → Carriers (e.g. UPS · Purolator · Canada Post)", shipment_id: shipmentId, carriers: names, services });
    serviceIds = picked.ids;
  }
  const sent = rateBody(req, serviceIds);
  const r = await fcCall("rate", "POST", "/rate", sent, caller, shipmentId);
  const requestId = requestIdOf(r.body);
  await rpc("fc_quote_pending", { p_shipment_id: shipmentId, p_request_id: requestId, p_request: sent }, null);
  const res = await finishQuote(shipmentId, requestId, sent, chargeSoId, caller);
  const out = await res.json();
  return json(res.status, { ...out, prepare: { action: prepare.action, mode: prepare.mode, packaging_type: prepare.packaging_type, charge_so_number: prepare.charge_so_number, so_numbers: prepare.so_numbers, options: prepare.options, address_id: prepare.address_id, address_review: prepare.address_review, freight_locked: prepare.freight_locked, warnings: prepare.warnings, services } });
}

Deno.serve(async (req) => {
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") return json(405, { ok: false, error: "POST only" });
    let dbRole: string | null = null;
    try { dbRole = String((await sbGet("inv_config?select=value&key=eq.db_role"))[0]?.value ?? ""); } catch { dbRole = null; }
    if (dbRole !== "test") return json(500, { ok: false, error: "inv_config.db_role is " + String(dbRole ?? "missing") + " - this function runs on the test project only (Asung-IMS) - refusing" });
    const caller = await gate(req);
    if (caller instanceof Response) return caller;
    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const action = String(body?.action ?? "");
    if (!(FC_ACTIONS as readonly string[]).includes(action)) return json(400, { ok: false, error: "action must be one of: " + FC_ACTIONS.join(", ") });
    if (action === "status") return json(200, { ok: true, secrets: { FREIGHTCOM_API_KEY: FC_KEY() !== "", FREIGHTCOM_BASE_URL: FC_BASE() !== "" }, base_url: FC_BASE() || null, mode: caller.mode, wait_ms: QUOTE_WAIT_MS });
    if (!FC_KEY() || !FC_BASE()) return json(500, { ok: false, error: "FREIGHTCOM_API_KEY / FREIGHTCOM_BASE_URL not configured on this project - refusing (fail-closed)" });
    if (action === "services") { const list = await loadServices(caller); return json(200, { ok: true, carriers: distinctCarriers(list), services: list, count: list.length }); }
    if (action === "quote") return await quote(body, caller);
    if (action === "quote_poll") {
      const shipmentId = String(body.shipment_id ?? ""), requestId = String(body.request_id ?? "");
      if (!shipmentId || !requestId) return json(400, { ok: false, error: "shipment_id and request_id are required" });
      const f = (await sbGet("fc_shipment?select=id,charge_so_id,status&id=eq." + encodeURIComponent(shipmentId) + "&limit=1"))[0];
      if (!f) return json(404, { ok: false, error: "shipment not found" });
      return await finishQuote(shipmentId, requestId, null, f.charge_so_id ?? null, caller);
    }
    return json(400, { ok: false, error: "unknown action" });
  } catch (e) {
    if (e instanceof RpcError) return json(e.status === 502 ? 502 : 422, { ok: false, error: e.message });
    return json(500, { ok: false, error: String((e as Error)?.message ?? e).slice(0, 400) });
  }
});
