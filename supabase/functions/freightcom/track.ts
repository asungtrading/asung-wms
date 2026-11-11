// ============================================================
// ASUNG IMS — EF freightcom · action "track_sweep"(cron) · "track_poll"(사람) (fc-track-2 · 2026-11-10 · 판정 1158 ~ 1160 · DB 20261111020326)
//   왜: fc_booking.state 는 예약 순간 값 그대로다 — IMS 가 스스로 GET /shipment/{id} + GET /shipment/{id}/tracking-events 를 다시 읽어 상태 · 추적 이벤트를 적는다
//   ⭐ GET 둘뿐 · 경로는 코드에 박음 · 저장은 DB 창구 하나(fc_track_save · service_role) · 대상은 DB 한 곳(fc_track_due) · 사람 길의 문은 DB(fc_track_gate · 사용자 JWT)
//   파서는 DB 한 곳이다(fc_track_save — when 나노초 → 마이크로초 · 빈 where → null · message btrim · bolnumber / bol_number) — 여기서는 꼴만 본다(shipment id 가 있는가 · 이벤트가 목록인가)
//   DB 로 보내는 것: 쉽먼트는 여섯 칸만 추린 것(slimShipment — 주소 · 라벨 주소 · 요금은 보내지 않는다) · 이벤트는 받은 원소 그대로(type · when · where{city, region, country} · message — fc_track_event.raw)
//   로그(1156 과 같은 선): 호출 한 번 = fc_call_log 메타 한 줄(action track_shipment | track_events) · error 는 「Freightcom track_… failed (HTTP n)」 뿐 — 응답 몸은 로그 · 응답 어디에도 넣지 않는다
//   시간 한도(1157 과 같은 선): 이 파일의 호출에만 TRACK_TIMEOUT_MS(20 s · AbortSignal) — index.ts 의 fcCall(예약 · 견적 · 취소 · 픽업)은 무접촉
//   회차 상한(이견 6): TRACK_SWEEP_BUDGET_MS(90 s)가 지나면 새 건을 시작하지 않는다(stopped_early · 남은 건은 다음 회차 — cron timeout 120 s 안)
//   이벤트 GET 만 실패한 건: state 는 저장(p_events null) — DB 가 끝 표지(track_done_at)를 찍지 않으므로 다음 회차가 다시 읽는다(이견 2)
//   index.ts 는 잇는 줄만(deps 를 만들어 runTrackSweep · runTrackPoll 을 부른다) · 시험 = track_test.ts(가짜 fetch · 가짜 deps · fixtures/track-*.json)
// ============================================================
import { sweepLimitOf } from "../_shared/freightcom.ts";

export const TRACK_TIMEOUT_MS = 20_000;
export const TRACK_SWEEP_BUDGET_MS = 90_000;
const e = encodeURIComponent;
export const trackPaths = {
  shipment: (fcId: string) => "/shipment/" + e(fcId),
  events: (fcId: string) => "/shipment/" + e(fcId) + "/tracking-events",
};
export type TrackAction = "track_shipment" | "track_events";

// ── 꼴만 보는 순수 함수 ──
// {shipment:{…}} 감쌈 · 맨몸 둘 다 · id 가 글자여야 쉽먼트다
export function shipmentBodyOf(body: unknown): Record<string, unknown> | null {
  const b = body as Record<string, unknown> | null;
  if (!b || typeof b !== "object" || Array.isArray(b)) return null;
  const s = b.shipment && typeof b.shipment === "object" && !Array.isArray(b.shipment) ? (b.shipment as Record<string, unknown>) : b;
  return typeof s.id === "string" && s.id.trim() !== "" ? s : null;
}
// DB 로 보내는 여섯 칸 — 값은 손대지 않는다(lower · trim 은 DB) · 없는 칸은 싣지 않는다 · 주소(details) · labels · rate · tracking_url 은 버린다
export const SLIM_KEYS = ["id", "state", "pickup_confirmation_number", "bolnumber", "bol_number", "primary_tracking_number"] as const;
export function slimShipment(s: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const k of SLIM_KEYS) if (typeof s[k] === "string") out[k] = s[k];
  return out;
}
// {events:[…]} · 배열 맨몸 → 목록 · 그 밖은 null(못 읽음 — state 만 저장한다)
export function eventsOf(body: unknown): unknown[] | null {
  if (Array.isArray(body)) return body;
  const ev = (body as { events?: unknown } | null)?.events;
  return Array.isArray(ev) ? ev : null;
}
export function trackLogError(action: TrackAction, status: number | null, timedOut: boolean): string {
  return `Freightcom ${action} failed (HTTP ${status ? status : timedOut ? "timeout" : "network"})`;
}
// 사람 길의 문이 거부한 까닭 → HTTP: 세션 401 · 권한 · 창고 403 · 그 밖(없는 예약 · booked 아님) 422
export function gateStatusOf(rpcStatus: number, message: string): number {
  if (rpcStatus === 401) return 401;
  return /^You cannot |belongs to another warehouse/.test(message) ? 403 : 422;
}

// ── GET 하나 — 시간 한도 · 로그 줄은 메타만 ──
export type TrackLog = { shipment_id: string | null; account: string | null; action: string; ok: boolean; http_status: number | null; error: string | null; ms: number; detail?: unknown };
export type TrackGet = { ok: boolean; http_status: number | null; body: unknown; error: string | null; ms: number };
export async function trackGet(fetchFn: typeof fetch, base: string, apiKey: string, action: TrackAction, account: string, path: string, shipmentId: string | null,
                               log: (row: TrackLog) => Promise<void>, timeoutMs = TRACK_TIMEOUT_MS): Promise<TrackGet> {
  const t0 = Date.now();
  let status: number | null = null, body: unknown = null, error: string | null = null, timedOut = false;
  try {
    const r = await fetchFn(base + path, { method: "GET", headers: { Authorization: apiKey, Accept: "application/json" }, signal: AbortSignal.timeout(timeoutMs) });
    status = r.status;
    const text = await r.text();
    try { body = text ? JSON.parse(text) : null; } catch { body = null; }
    if (!r.ok) error = trackLogError(action, status, false);
  } catch (x) {
    const name = (x as Error)?.name ?? "";
    timedOut = name === "TimeoutError" || name === "AbortError";
    error = trackLogError(action, null, timedOut);
  }
  const ms = Date.now() - t0;
  await log({ shipment_id: shipmentId, account, action, ok: error === null, http_status: status, error, ms });
  return { ok: error === null, http_status: status, body: error === null ? body : null, error, ms };
}

// ── 한 건 — GET 둘 → 저장 · 던지지 않는다(한 건 실패가 회차를 멈추지 않는다) ──
export type TrackTarget = { booking_id: string; shipment_id: string; attempt?: number | null; account: string | null; freightcom_shipment_id: string | null; tier?: string | null };
export type TrackDeps = {
  fetchFn: typeof fetch;
  base: string;
  apiKey: (account: string) => string;                       // 없으면 "" · 계정 꼴이 틀리면 던질 수 있다(여기서 받는다)
  log: (row: TrackLog) => Promise<void>;                     // by_staff 는 index.ts 가 끼운다(cron 은 null)
  save: (bookingId: string, shipment: Record<string, unknown>, events: unknown[] | null) => Promise<Record<string, unknown>>;   // rpc/fc_track_save(service_role)
  noAccountSentence: (account: string) => string;
  timeoutMs?: number;
  now?: () => number;
};
export type TrackItem = Record<string, unknown> & { booking_id: string; read: boolean };
const SAVED_KEYS = ["state", "state_before", "state_changed", "state_kind", "state_checked_at", "delivered_at", "track_done_at", "track_last", "events_read", "events_received", "events_added", "events_skipped", "events_total", "pickup_confirmation", "confirmation_mismatch", "warnings"] as const;
export async function trackOne(t: TrackTarget, d: TrackDeps): Promise<TrackItem> {
  const base = { booking_id: t.booking_id, attempt: t.attempt ?? null, account: t.account ?? null, tier: t.tier ?? null };
  const account = String(t.account ?? "").trim(), fcId = String(t.freightcom_shipment_id ?? "").trim();
  let key = "";
  try { key = account ? d.apiKey(account) : ""; } catch { key = ""; }
  if (!account || !key) return { ...base, read: false, error: d.noAccountSentence(account || "??") };
  if (!fcId) return { ...base, read: false, error: "This booking has no Freightcom shipment id — nothing to read" };
  const timeout = d.timeoutMs ?? TRACK_TIMEOUT_MS;
  const s = await trackGet(d.fetchFn, d.base, key, "track_shipment", account, trackPaths.shipment(fcId), t.shipment_id, d.log, timeout);
  if (!s.ok) return { ...base, read: false, http_status: s.http_status, error: s.error };
  const ship = shipmentBodyOf(s.body);
  if (!ship) return { ...base, read: false, http_status: s.http_status, error: "Freightcom track_shipment 200: the answer has no shipment id" };
  const ev = await trackGet(d.fetchFn, d.base, key, "track_events", account, trackPaths.events(fcId), t.shipment_id, d.log, timeout);
  const events = ev.ok ? eventsOf(ev.body) : null;
  const events_error = ev.ok ? (events === null ? "Freightcom track_events 200: the answer is not a list of events" : null) : ev.error;
  try {
    const saved = await d.save(t.booking_id, slimShipment(ship), events);
    const out: TrackItem = { ...base, read: true, events_error };
    for (const k of SAVED_KEYS) out[k] = saved?.[k] ?? null;
    return out;
  } catch (x) {
    return { ...base, read: false, events_error, error: "Tracking was read but not saved — " + String((x as Error)?.message ?? x).slice(0, 300) };
  }
}

// ── cron 회차 — 스위치 → 대상 → 건마다 trackOne → 요약 한 줄(action track_sweep · detail) ──
export type SweepDeps = TrackDeps & { enabled: () => Promise<boolean>; due: (limit: number) => Promise<TrackTarget[]>; budgetMs?: number };
export type TrackReply = { status: number; payload: Record<string, unknown> };
export function trackSweepSummary(items: TrackItem[]): { read: number; changed: number; finished: number; failed: number; events_added: number; events_failed: number } {
  const s = { read: 0, changed: 0, finished: 0, failed: 0, events_added: 0, events_failed: 0 };
  for (const i of items) {
    if (!i.read) { s.failed++; continue; }
    s.read++;
    if (i.state_changed === true) s.changed++;
    if (i.track_done_at) s.finished++;
    if (i.events_error) s.events_failed++;
    s.events_added += typeof i.events_added === "number" ? i.events_added : 0;
  }
  return s;
}
export async function runTrackSweep(body: Record<string, unknown>, d: SweepDeps): Promise<TrackReply> {
  const now = d.now ?? Date.now, t0 = now();
  const limit = sweepLimitOf(body), budget = d.budgetMs ?? TRACK_SWEEP_BUDGET_MS;
  const summaryRow = async (ok: boolean, error: string | null, detail: Record<string, unknown>) =>
    await d.log({ shipment_id: null, account: null, action: "track_sweep", ok, http_status: null, error, ms: now() - t0, detail: { ...detail, ms: now() - t0 } });
  if (!d.base) return { status: 500, payload: { ok: false, error: "FREIGHTCOM_BASE_URL not configured on this project - refusing (fail-closed)" } };
  let enabled = false;
  try { enabled = await d.enabled(); }
  catch (x) { const error = "inv_config read failed: " + String((x as Error)?.message ?? x).slice(0, 200); await summaryRow(false, error, { enabled: null, limit, candidates: 0 }); return { status: 502, payload: { ok: false, error } }; }
  if (!enabled) {
    const skipped = "switch off — inv_config fc_track_poll_enabled is not 'on' (nothing read)";
    const zero = { enabled: false, limit, candidates: 0, read: 0, changed: 0, finished: 0, failed: 0, events_added: 0, events_failed: 0, stopped_early: false, left: 0, skipped };
    await summaryRow(true, null, zero);
    return { status: 200, payload: { ok: true, ...zero, items: [] } };
  }
  let due: TrackTarget[];
  try { due = (await d.due(limit)) ?? []; }
  catch (x) { const error = "fc_track_due failed: " + String((x as Error)?.message ?? x).slice(0, 200); await summaryRow(false, error, { enabled: true, limit, candidates: null }); return { status: 502, payload: { ok: false, error } }; }
  const items: TrackItem[] = [];
  let stopped_early = false;
  for (const t of due) {
    if (now() - t0 >= budget) { stopped_early = true; break; }
    items.push(await trackOne(t, d));
  }
  const s = trackSweepSummary(items);
  const detail = { enabled: true, limit, candidates: due.length, ...s, stopped_early, left: due.length - items.length };
  await summaryRow(s.failed === 0, s.failed === 0 ? null : s.failed + " of " + items.length + " tracking reads failed — see the track_shipment rows just before this one", detail);
  return { status: 200, payload: { ok: true, ...detail, ms: now() - t0, items } };
}

// ── 사람 길 — 문(DB · 사용자 JWT) → trackOne → 화면용 요약(주소 없음) ──
export type GateResult = { ok: true; row: Record<string, unknown> } | { ok: false; status: number; error: string };
export type PollDeps = TrackDeps & { gate: (bookingId: string) => Promise<GateResult>; detail?: (shipmentId: string) => Promise<unknown> };
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function runTrackPoll(jwt: string, body: Record<string, unknown>, d: PollDeps): Promise<TrackReply> {
  if (!jwt) return { status: 401, payload: { ok: false, error: "Missing Authorization" } };
  const bookingId = String(body.booking_id ?? "").trim();
  if (!UUID_RE.test(bookingId)) return { status: 400, payload: { ok: false, error: "booking_id is required (the booking's full id)" } };
  if (!d.base) return { status: 500, payload: { ok: false, error: "FREIGHTCOM_BASE_URL not configured on this project - refusing (fail-closed)" } };
  const g = await d.gate(bookingId);
  if (!g.ok) return { status: gateStatusOf(g.status, g.error), payload: { ok: false, error: g.status === 401 ? "Invalid session — sign in again" : g.error } };
  const shipmentId = String(g.row.shipment_id ?? "");
  const item = await trackOne({ booking_id: bookingId, shipment_id: shipmentId, attempt: Number(g.row.attempt ?? 0) || null, account: String(g.row.account ?? ""), freightcom_shipment_id: String(g.row.freightcom_shipment_id ?? "") }, d);
  let detail: unknown = null;
  if (d.detail && shipmentId) { try { detail = await d.detail(shipmentId); } catch { detail = null; } }
  if (!item.read) return { status: 502, payload: { ok: false, checked: false, booking_id: bookingId, error: String(item.error ?? "Couldn't read the tracking from Freightcom"), message: "Couldn't refresh the tracking from Freightcom — try again in a minute", track: item, detail } };
  return { status: 200, payload: { ok: true, checked: true, booking_id: bookingId, track: item, detail } };
}
