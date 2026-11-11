// deno test --allow-read supabase/functions/freightcom/track_test.ts — fc-track-2 action track_sweep · track_poll · Freightcom · DB · 네트워크 무접촉(가짜 fetch · 가짜 deps)
//   fixtures/track-shipment.json · track-events.json = 지시서 📌 의 실물 꼴(11-10 inspect · UPS · delivered · 이벤트 8)을 다시 적은 것 — 바이트 원문이 아니다(id · 추적번호 · 시각 일부는 지어낸 값) · DB 시험(fc_track_2_check.sql)과 같은 파일
import { eventsOf, gateStatusOf, type PollDeps, runTrackPoll, runTrackSweep, shipmentBodyOf, SLIM_KEYS, slimShipment, type SweepDeps, TRACK_SWEEP_BUDGET_MS, TRACK_TIMEOUT_MS, trackGet, type TrackLog, trackLogError, trackOne, trackPaths, trackSweepSummary, type TrackTarget } from "./track.ts";
import { FC_ACTIONS, FC_BOOK_ACTIONS, FC_CRON_ACTIONS } from "../_shared/freightcom.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const here = new URL("./fixtures/", import.meta.url);
const SHIP = JSON.parse(Deno.readTextFileSync(new URL("track-shipment.json", here)));
const EVENTS = JSON.parse(Deno.readTextFileSync(new URL("track-events.json", here)));
const BASE = "https://fc.example";
const B1 = "11111111-1111-4111-8111-111111111111", B2 = "22222222-2222-4222-8222-222222222222", B3 = "33333333-3333-4333-8333-333333333333";
const target = (id: string, fcId = "fcShipTrack1", account = "TOR"): TrackTarget => ({ booking_id: id, shipment_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", attempt: 1, account, freightcom_shipment_id: fcId, tier: "first" });
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
type Saved = { id: string; shipment: Record<string, unknown>; events: unknown[] | null };
// 가짜 저장 — DB 의 fc_track_save 가 돌려주는 꼴을 흉내낸다(state 는 lower · trim · 끝 상태 ∧ 이벤트 읽음이면 끝 표지)
function fakeSave(saves: Saved[], fail: string[] = []) {
  return (id: string, shipment: Record<string, unknown>, events: unknown[] | null): Promise<Record<string, unknown>> => {
    if (fail.includes(id)) return Promise.reject(new Error("Booking #1 is cancelled — tracking is read for booked shipments only — nothing was saved"));
    saves.push({ id, shipment, events });
    const state = String(shipment.state ?? "").trim().toLowerCase();
    const ended = state === "delivered" || state.startsWith("cancel");
    return Promise.resolve({ booking_id: id, state, state_before: "in-transit", state_changed: state !== "in-transit", state_kind: state === "delivered" ? "delivered" : state.startsWith("cancel") ? "cancelled" : "open",
      state_checked_at: "2026-11-11T03:00:00+00:00", delivered_at: ended && events ? "2026-11-10T21:06:12.123456+00:00" : null, track_done_at: ended && events ? "2026-11-11T03:00:00+00:00" : null,
      track_last: events && events.length ? { type: "delivered", at: "2026-11-10T21:06:12.123456+00:00", city: "SAULT STE MARIE", region: "ON", message: "DELIVERED" } : null,
      events_read: events !== null, events_received: events?.length ?? 0, events_added: events?.length ?? 0, events_skipped: 0, events_total: events?.length ?? 0, pickup_confirmation: "29FBD3C23EA", confirmation_mismatch: false, warnings: [],
      pickup_check: { message: "should not be passed on" } });
  };
}
function deps(routes: Record<string, Route>, calls: Call[], logs: TrackLog[], saves: Saved[], over: Partial<SweepDeps & PollDeps> = {}): SweepDeps & PollDeps {
  return {
    fetchFn: fakeFetch(routes, calls), base: BASE,
    apiKey: (a) => { if (!/^[A-Z0-9]{2,10}$/.test(a)) throw new Error("bad account"); return a === "TOR" || a === "EDM" ? "key-" + a : ""; },
    log: (row) => { logs.push(row); return Promise.resolve(); },
    save: fakeSave(saves),
    noAccountSentence: (a) => "No Freightcom connection for account " + a,
    enabled: () => Promise.resolve(true),
    due: () => Promise.resolve([]),
    gate: (id) => Promise.resolve({ ok: true, row: { booking_id: id, shipment_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", attempt: 2, status: "booked", account: "TOR", freightcom_shipment_id: "fcShipTrack1" } }),
    ...over,
  };
}
const OK_ROUTES: Record<string, Route> = { "/shipment/fcShipTrack1": { status: 200, body: SHIP }, "/shipment/fcShipTrack1/tracking-events": { status: 200, body: EVENTS } };

Deno.test("① 꼴 — shipmentBodyOf(감쌈 · 맨몸 · id 없음) · eventsOf({events} · 배열 · 그 밖 null) · 경로는 인코딩", () => {
  eq(shipmentBodyOf(SHIP)?.id, "fcShipTrack1", "wrapped {shipment:{…}}");
  eq(shipmentBodyOf(SHIP.shipment)?.state, "delivered", "bare body");
  eq([shipmentBodyOf({ shipment: { state: "delivered" } }), shipmentBodyOf({ id: "  " }), shipmentBodyOf(null), shipmentBodyOf("text"), shipmentBodyOf([{ id: "x" }])], [null, null, null, null, null], "no id · blank id · null · text · list = not a shipment");
  eq(eventsOf(EVENTS)?.length, 8, "{events:[8]}");
  eq(eventsOf(EVENTS.events)?.length, 8, "bare list");
  eq([eventsOf({ events: "none" }), eventsOf({}), eventsOf(null), eventsOf("x")], [null, null, null, null], "anything else = not read");
  eq(eventsOf({ events: [] }), [], "an empty list is a read (zero events)");
  eq([trackPaths.shipment("a/b c"), trackPaths.events("a/b c")], ["/shipment/a%2Fb%20c", "/shipment/a%2Fb%20c/tracking-events"], "paths encode the id");
});

Deno.test("② slimShipment — DB 로는 여섯 칸만 · 주소 · 라벨 · 요금 · 주소 문자열은 버린다 · bolnumber · bol_number 둘 다 · 모르는 state 는 값 그대로", () => {
  const slim = slimShipment(SHIP.shipment);
  eq(slim, { id: "fcShipTrack1", state: "delivered", pickup_confirmation_number: "29FBD3C23EA", bolnumber: "", primary_tracking_number: "1ZFIXTURE0001" }, "only the keys the save window reads");
  eq(Object.keys(slim).every((k) => (SLIM_KEYS as readonly string[]).includes(k)), true, "nothing outside SLIM_KEYS");
  eq(JSON.stringify(slim).includes("http"), false, "no url leaves the function");
  eq(slimShipment({ id: "x", state: " Waiting-For-Scheduling ", bol_number: "B1", bolnumber: "B2", details: { destination: { name: "Shop" } }, labels: [{ url: "https://s3/x" }], rate: { total: { value: "4009" } } }),
    { id: "x", state: " Waiting-For-Scheduling ", bolnumber: "B2", bol_number: "B1" }, "both BOL spellings pass · unknown state untouched (the database lowers and trims)");
  eq(slimShipment({ id: "x", state: null, pickup_confirmation_number: 123 }), { id: "x" }, "non-strings are dropped, not coerced");
});

Deno.test("③ 이벤트는 받은 원소 그대로 DB 로 — 나노초 when · 빈 where · 끝 공백 message · 모르는 type 을 여기서 고치지 않는다(파서는 DB 한 곳)", async () => {
  const calls: Call[] = [], logs: TrackLog[] = [], saves: Saved[] = [];
  const odd = { events: [...EVENTS.events, { type: "Customs-Hold", when: "garbage", where: "", message: "  " }, "just text"] };
  const r = await trackOne(target(B1), deps({ ...OK_ROUTES, "/shipment/fcShipTrack1/tracking-events": { status: 200, body: odd } }, calls, logs, saves));
  eq(r.read, true, "read");
  eq(saves[0].events?.length, 10, "all ten elements passed on (the database counts the unreadable ones as skipped)");
  eq((saves[0].events as Record<string, unknown>[])[0], { type: "label-created", when: "2026-11-05T22:45:20.465569955Z", where: { city: "", region: "", country: "" }, message: "Shipper created a label, UPS has not received the package yet. " }, "nanoseconds · empty where · trailing space untouched");
  eq((saves[0].events as unknown[])[9], "just text", "even a non-object element is passed, not dropped here");
  eq((saves[0].events as Record<string, unknown>[])[7].message, "DELIVERED ", "trailing space kept for raw");
});

Deno.test("④ trackOne — GET 둘(shipment → events) · 열쇠 · 시간 한도 신호 · 로그는 메타 두 줄 · 반환에 주소 · pickup_check 없음", async () => {
  const calls: Call[] = [], logs: TrackLog[] = [], saves: Saved[] = [];
  const r = await trackOne(target(B1), deps(OK_ROUTES, calls, logs, saves));
  eq(calls.map((c) => c.method + " " + c.url.slice(BASE.length)), ["GET /shipment/fcShipTrack1", "GET /shipment/fcShipTrack1/tracking-events"], "two GETs in order");
  eq(calls.every((c) => c.auth === "key-TOR" && c.hasSignal), true, "account key · AbortSignal on both");
  eq(logs.map((l) => [l.action, l.ok, l.http_status, l.error, l.account, l.shipment_id]), [["track_shipment", true, 200, null, "TOR", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"], ["track_events", true, 200, null, "TOR", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"]], "two meta rows");
  eq(logs.every((l) => Object.keys(l).sort().join() === "account,action,error,http_status,ms,ok,shipment_id"), true, "log rows carry meta only (no body · no detail)");
  eq([r.read, r.state, r.state_kind, r.events_added, r.events_error, (r.track_last as Record<string, unknown>).message, r.track_done_at !== null], [true, "delivered", "delivered", 8, null, "DELIVERED", true], "summary from the save window");
  eq("pickup_check" in r || "details" in r || JSON.stringify(r).includes("http"), false, "no pickup_check · no address · no url in the item");
  eq(saves.length, 1, "one save");
});

Deno.test("⑤ trackOne 실패 갈래 — shipment GET 실패는 저장 0 · events 만 실패하면 state 는 저장(p_events null) · 로그 · 반환에 응답 몸 없음", async () => {
  const SECRET = "customer lives at 33 rue des Buses";
  let calls: Call[] = [], logs: TrackLog[] = [], saves: Saved[] = [];
  let r = await trackOne(target(B1), deps({ "/shipment/fcShipTrack1": { status: 404, body: { message: SECRET } } }, calls, logs, saves));
  eq([r.read, r.http_status, r.error, saves.length, calls.length], [false, 404, "Freightcom track_shipment failed (HTTP 404)", 0, 1], "404 → not read · nothing saved · events not even asked");
  eq(JSON.stringify([r, logs]).includes(SECRET), false, "the answer body is in neither the item nor the log");
  calls = []; logs = []; saves = [];
  r = await trackOne(target(B1), deps({ "/shipment/fcShipTrack1": { status: 200, body: SHIP }, "/shipment/fcShipTrack1/tracking-events": { status: 500, body: SECRET } }, calls, logs, saves));
  eq([r.read, r.state, r.events_read, r.events_error, r.track_done_at, saves[0].events], [true, "delivered", false, "Freightcom track_events failed (HTTP 500)", null, null], "events failed → state saved with p_events null → no end mark (next sweep reads again)");
  eq(logs.map((l) => [l.action, l.ok, l.error]), [["track_shipment", true, null], ["track_events", false, "Freightcom track_events failed (HTTP 500)"]], "log says which call failed");
  eq(JSON.stringify([r, logs]).includes(SECRET), false, "no body leaked");
  calls = []; logs = []; saves = [];
  r = await trackOne(target(B1), deps({ "/shipment/fcShipTrack1": { status: 200, body: SHIP }, "/shipment/fcShipTrack1/tracking-events": { status: 200, body: { events: "soon" } } }, calls, logs, saves));
  eq([r.read, r.events_error, saves[0].events], [true, "Freightcom track_events 200: the answer is not a list of events", null], "200 but not a list = events not read");
  calls = []; logs = []; saves = [];
  r = await trackOne(target(B1), deps({ "/shipment/fcShipTrack1": { status: 200, body: { shipment: { state: "delivered" } } } }, calls, logs, saves));
  eq([r.read, r.error, saves.length, calls.length], [false, "Freightcom track_shipment 200: the answer has no shipment id", 0, 1], "200 without an id is not a shipment");
  calls = []; logs = []; saves = [];
  r = await trackOne(target(B1), deps({ "/shipment/fcShipTrack1": { status: 200, body: "<html>" } }, calls, logs, saves));
  eq([r.read, saves.length], [false, 0], "non-JSON 200 → not read");
  r = await trackOne(target(B1), { ...deps(OK_ROUTES, [], [], []), save: fakeSave([], [B1]) });
  eq([r.read, String(r.error).startsWith("Tracking was read but not saved — Booking #1 is cancelled")], [false, true], "save refused by the database → failed with its sentence");
});

Deno.test("⑥ 시간 한도 · 망 실패 · 계정 — hang 은 timeoutMs 뒤 끊고 timeout 으로 · 열쇠 없음 · 계정 꼴 틀림 · Freightcom id 없음은 호출 0", async () => {
  let calls: Call[] = [], logs: TrackLog[] = [];
  const t0 = Date.now();
  let r = await trackOne(target(B1), { ...deps({ "/shipment/fcShipTrack1": "hang" }, calls, logs, []), timeoutMs: 40 });
  eq([r.read, r.error, logs[0].error, logs[0].http_status, Date.now() - t0 < 2_000], [false, "Freightcom track_shipment failed (HTTP timeout)", "Freightcom track_shipment failed (HTTP timeout)", null, true], "cut at timeoutMs");
  calls = []; logs = [];
  r = await trackOne(target(B1), deps({ "/shipment/fcShipTrack1": "throw" }, calls, logs, []));
  eq([r.read, r.error], [false, "Freightcom track_shipment failed (HTTP network)"], "network error (the exception text is not passed on)");
  calls = []; logs = [];
  r = await trackOne(target(B1, "fcShipTrack1", "VAN"), deps(OK_ROUTES, calls, logs, []));
  eq([r.read, r.error, calls.length, logs.length], [false, "No Freightcom connection for account VAN", 0, 0], "no key → no call");
  r = await trackOne(target(B1, "fcShipTrack1", "bad account!"), deps(OK_ROUTES, calls, logs, []));
  eq([r.read, calls.length], [false, 0], "apiKey throwing on a malformed account is caught");
  r = await trackOne(target(B1, "  "), deps(OK_ROUTES, calls, logs, []));
  eq([r.read, r.error, calls.length], [false, "This booking has no Freightcom shipment id — nothing to read", 0], "no Freightcom id → no call");
  eq([TRACK_TIMEOUT_MS, TRACK_SWEEP_BUDGET_MS], [20_000, 90_000], "20 s per call · 90 s per sweep");
  eq([trackLogError("track_events", 503, false), trackLogError("track_shipment", null, true), trackLogError("track_shipment", null, false)], ["Freightcom track_events failed (HTTP 503)", "Freightcom track_shipment failed (HTTP timeout)", "Freightcom track_shipment failed (HTTP network)"], "log error sentences");
  const g = await trackGet(fakeFetch({ "/x": { status: 200, body: { a: 1 } } }, []), BASE, "k", "track_shipment", "TOR", "/x", null, () => Promise.resolve());
  eq([g.ok, g.http_status, g.body, g.error], [true, 200, { a: 1 }, null], "trackGet ok");
});

Deno.test("⑦ track_sweep — 스위치 off 면 호출 0 · 대상도 안 읽는다 · 요약 한 줄", async () => {
  const calls: Call[] = [], logs: TrackLog[] = [], saves: Saved[] = [];
  let dueCalls = 0;
  const r = await runTrackSweep({ action: "track_sweep", limit: 10 }, deps(OK_ROUTES, calls, logs, saves, { enabled: () => Promise.resolve(false), due: () => { dueCalls++; return Promise.resolve([target(B1)]); } }));
  eq([r.status, r.payload.ok, r.payload.enabled, r.payload.candidates, r.payload.read, calls.length, dueCalls, saves.length], [200, true, false, 0, 0, 0, 0, 0], "off → no GET · no due read · no save");
  eq([logs.length, logs[0].action, logs[0].ok, (logs[0].detail as Record<string, unknown>).enabled, String((logs[0].detail as Record<string, unknown>).skipped).startsWith("switch off")], [1, "track_sweep", true, false, true], "one summary row");
});

Deno.test("⑧ track_sweep — batch(limit 은 DB 대상 함수로) · 한 건 실패가 회차를 멈추지 않는다 · 요약 셈 · 로그 메타만", async () => {
  const calls: Call[] = [], logs: TrackLog[] = [], saves: Saved[] = [];
  const limits: number[] = [];
  const routes: Record<string, Route> = { ...OK_ROUTES, "/shipment/fcB": { status: 502, body: "bad gateway" },
    "/shipment/fcC": { status: 200, body: { id: "fcC", state: "Waiting-For-Scheduling" } }, "/shipment/fcC/tracking-events": { status: 200, body: { events: [] } } };
  const d = deps(routes, calls, logs, saves, { due: (limit) => { limits.push(limit); return Promise.resolve([target(B1), target(B2, "fcB"), target(B3, "fcC")]); } });
  const r = await runTrackSweep({ limit: 3 }, d);
  const p = r.payload;
  eq(limits, [3], "limit passed to fc_track_due");
  eq([p.ok, p.enabled, p.limit, p.candidates, p.read, p.changed, p.finished, p.failed, p.events_added, p.events_failed, p.stopped_early, p.left], [true, true, 3, 3, 2, 2, 1, 1, 8, 0, false, 0], "summary");
  eq((p.items as Record<string, unknown>[]).map((i) => [i.booking_id, i.read, i.state ?? null]), [[B1, true, "delivered"], [B2, false, null], [B3, true, "waiting-for-scheduling"]], "the failed one in the middle does not stop the sweep · unknown state accepted");
  eq(calls.length, 5, "2 + 1 (failed at shipment) + 2 GETs");
  const sum = logs[logs.length - 1];
  eq([sum.action, sum.ok, sum.error, sum.shipment_id, sum.account], ["track_sweep", false, "1 of 3 tracking reads failed — see the track_shipment rows just before this one", null, null], "summary row last · not ok when something failed");
  eq(JSON.stringify(logs).includes("bad gateway") || JSON.stringify(logs).includes("SAULT"), false, "no answer body · no event text in any log row");
  eq(await sweepLimits([{ limit: 0 }, { limit: 51 }, {}, { limit: "7" }]), [10, 10, 10, 7], "limit outside 1 ~ 50 → 10 (what fc_track_due is asked for)");
  eq(trackSweepSummary([]), { read: 0, changed: 0, finished: 0, failed: 0, events_added: 0, events_failed: 0 }, "empty sweep");
});
async function sweepLimits(bodies: Record<string, unknown>[]): Promise<number[]> {
  const seen: number[] = [];
  for (const b of bodies) await runTrackSweep(b, deps({}, [], [], [], { due: (l) => { seen.push(l); return Promise.resolve([]); } }));
  return seen;
}

Deno.test("⑨ track_sweep 시간 상한 — 90 s 가 지나면 새 건을 시작하지 않는다(stopped_early · left) · 대상 읽기 실패 · 스위치 읽기 실패는 502 + 요약 줄 · BASE 없음 500", async () => {
  let calls: Call[] = [], logs: TrackLog[] = [], saves: Saved[] = [];
  let clock = 1_000_000;
  const d = deps(OK_ROUTES, calls, logs, saves, { due: () => Promise.resolve([target(B1), target(B2), target(B3)]), now: () => clock });
  d.save = (id, s, ev) => { clock += 50_000; return fakeSave(saves)(id, s, ev); };   // 한 건이 50 s 걸린 셈
  const r = await runTrackSweep({}, d);
  eq([r.payload.candidates, r.payload.read, r.payload.stopped_early, r.payload.left, saves.length, calls.length], [3, 2, true, 1, 2, 4], "after 100 s the third is left for the next sweep");
  eq((logs[logs.length - 1].detail as Record<string, unknown>).stopped_early, true, "summary row says so");
  calls = []; logs = []; saves = [];
  let r2 = await runTrackSweep({}, deps(OK_ROUTES, calls, logs, saves, { due: () => Promise.reject(new Error("permission denied for function fc_track_due")) }));
  eq([r2.status, r2.payload.ok, calls.length, logs.length, logs[0].ok], [502, false, 0, 1, false], "due failed → 502 · summary row · no GET");
  logs = [];
  r2 = await runTrackSweep({}, deps(OK_ROUTES, calls, logs, saves, { enabled: () => Promise.reject(new Error("sbGet inv_config 500")) }));
  eq([r2.status, logs.length, String(logs[0].error).startsWith("inv_config read failed")], [502, 1, true], "switch read failed → 502 (fail-closed)");
  r2 = await runTrackSweep({}, { ...deps(OK_ROUTES, calls, logs, saves), base: "" });
  eq([r2.status, calls.length], [500, 0], "no base url → 500");
});

Deno.test("⑩ track_poll 문 — JWT 없음 401 · booking_id 꼴 400 · 문 거부는 까닭대로(세션 401 · 권한 · 창고 403 · 그 밖 422) · 거부면 Freightcom 호출 0", async () => {
  const calls: Call[] = [], logs: TrackLog[] = [], saves: Saved[] = [];
  const refuse = (status: number, error: string) => deps(OK_ROUTES, calls, logs, saves, { gate: () => Promise.resolve({ ok: false, status, error }) });
  eq((await runTrackPoll("", { booking_id: B1 }, deps(OK_ROUTES, calls, logs, saves))).status, 401, "no JWT");
  eq([(await runTrackPoll("jwt", {}, deps(OK_ROUTES, calls, logs, saves))).status, (await runTrackPoll("jwt", { booking_id: "1474f64f" }, deps(OK_ROUTES, calls, logs, saves))).status], [400, 400], "booking_id missing · short id");
  let r = await runTrackPoll("jwt", { booking_id: B1 }, refuse(401, "JWT expired"));
  eq([r.status, r.payload.error], [401, "Invalid session — sign in again"], "expired session");
  r = await runTrackPoll("jwt", { booking_id: B1 }, refuse(400, "You cannot refresh freight tracking — ask an admin for the 'sales', 'fulfillment' or 'freight_booking' permission — nothing was read"));
  eq([r.status, String(r.payload.error).startsWith("You cannot refresh freight tracking")], [403, true], "no permission → 403 with the database sentence");
  eq((await runTrackPoll("jwt", { booking_id: B1 }, refuse(400, "This shipment belongs to another warehouse — nothing was read"))).status, 403, "other warehouse → 403");
  eq((await runTrackPoll("jwt", { booking_id: B1 }, refuse(400, "Booking #1 is cancelled — tracking is read for booked shipments only — nothing was read"))).status, 422, "not booked → 422");
  eq((await runTrackPoll("jwt", { booking_id: B1 }, refuse(400, "Booking " + B1 + " not found — nothing was read"))).status, 422, "not found → 422");
  eq([calls.length, saves.length, logs.length], [0, 0, 0], "refused → no Freightcom call · no save · no log row");
  eq([gateStatusOf(401, "x"), gateStatusOf(400, "You cannot refresh"), gateStatusOf(400, "x belongs to another warehouse x"), gateStatusOf(400, "other")], [401, 403, 403, 422], "gateStatusOf");
  eq((await runTrackPoll("jwt", { booking_id: B1 }, { ...deps(OK_ROUTES, calls, logs, saves), base: "" })).status, 500, "no base url → 500");
});

Deno.test("⑪ track_poll — 문이 준 계정 · Freightcom id 로 GET 둘 → 저장 → {ok, checked, track, detail} · 실패는 502 checked false · 주소 없음", async () => {
  let calls: Call[] = [], logs: TrackLog[] = [], saves: Saved[] = [];
  const details: string[] = [];
  let r = await runTrackPoll("jwt", { booking_id: B1.toUpperCase() }, deps(OK_ROUTES, calls, logs, saves, { detail: (sid) => { details.push(sid); return Promise.resolve({ shipment_id: sid, status: "booked" }); } }));
  const t = r.payload.track as Record<string, unknown>;
  eq([r.status, r.payload.ok, r.payload.checked, t.state, t.events_added, t.attempt, (t.track_last as Record<string, unknown>).city, t.delivered_at], [200, true, true, "delivered", 8, 2, "SAULT STE MARIE", "2026-11-10T21:06:12.123456+00:00"], "reply for the screen");
  eq([calls.length, calls[0].auth, saves[0].id, details], [2, "key-TOR", B1.toUpperCase(), ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"]], "gate's account and Freightcom id used · detail read with the shipment id");
  eq(JSON.stringify(r.payload).includes("http") || JSON.stringify(r.payload).includes("details\":{"), false, "no url · no address block in the reply");
  calls = []; logs = []; saves = [];
  r = await runTrackPoll("jwt", { booking_id: B1 }, deps({ "/shipment/fcShipTrack1": { status: 503, body: "down" } }, calls, logs, saves, { detail: () => Promise.reject(new Error("x")) }));
  eq([r.status, r.payload.ok, r.payload.checked, r.payload.error, r.payload.detail, saves.length], [502, false, false, "Freightcom track_shipment failed (HTTP 503)", null, 0], "Freightcom down → 502 · nothing saved · a failing detail read does not throw");
});

Deno.test("⑫ 길 가르기 — track_sweep 은 cron 길에만 · track_poll 은 FC_*_ACTIONS 밖(문이 DB fc_track_gate) · pickup_sweep 은 그대로", () => {
  eq([...FC_CRON_ACTIONS], ["pickup_sweep", "track_sweep"], "cron actions");
  const person = [...FC_ACTIONS, ...FC_BOOK_ACTIONS] as readonly string[];
  eq([person.includes("track_sweep"), person.includes("track_poll"), (FC_CRON_ACTIONS as readonly string[]).includes("track_poll")], [false, false, false], "track_sweep is not a person action · track_poll is routed before the FC_*_ACTIONS gate · not a cron action");
});
