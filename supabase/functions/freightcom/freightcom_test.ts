// deno test --allow-read supabase/functions/freightcom/freightcom_test.ts — Freightcom · DB · 네트워크 무접촉 (fc-1b 견적 ① ~ ⑥ · fc-2c 예약 ⑦ ~ ⑩ · fc-pickup-1 스케줄 ⑪ · fc-pickup-2 cron 길 ⑫ · _shared/freightcom.ts 의 순수 함수 · fixtures = 2026-10-28 Caleb PC 프로브 원문 · 토큰 없음 · book-*.json 의 라벨 url 폴더는 MASKED)
import { ACCOUNT_RE, apiKeyFor, attachFreightClass, BOOK_WAIT_MS, bookBody, bookErrorSentence, bookOutcome, cancelOutcome, cents, distinctCarriers, FC_BOOK_ACTIONS, fcErrorSentence, freightClassOf, freightcomIdOf, isPdf, labelPath, noAccountSentence, palletBoxes, parseServices, paymentCacheKey, paymentMethodOf, pickLabels, pickServices, pickupCheckNeeded, QUOTE_WAIT_MS, rateBody, rateLines, rateStatus, requestIdOf, SCHEDULE_WAIT_MS, scheduleOf, scheduleOutcome, secretNameFor, servicesCacheKey, shipmentOf, shouldKeepBookPolling, shouldKeepPolling, shouldKeepSchedulePolling, sweepKindOf, sweepLimitOf, sweepSummary, FC_CRON_ACTIONS, sameSecret, SWEEP_LIMIT_DEFAULT, SWEEP_LIMIT_MAX, type RateRequest } from "../_shared/freightcom.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const here = new URL(".", import.meta.url).pathname;
const read = (f: string) => JSON.parse(Deno.readTextFileSync(here + "fixtures/" + f));

Deno.test("① /services 원문 = 배열 476 · 223 운송사(공백만 다른 이름 둘) · 문서 꼴 {services:[…]} 도 받는다 · 운송사 이름으로 서비스 고르기(대소문자 · 공백 무시 · Purolator ≠ Purolator Courier)", () => {
  const list = parseServices(read("services.json"));
  eq(list.length, 476, "476 services");
  eq(distinctCarriers(list).length, 223, "223 carriers after trim (raw 225 — two names differ only by trailing space, e.g. \"Purolator Freight \")");
  eq(parseServices({ services: list.slice(0, 3) }).length, 3, "documented shape accepted");
  const p = pickServices(list, [" ups ", "Canada Post", "Purolator", "Maritime Nowhere"]);
  eq(p.matched, [" ups ", "Canada Post", "Purolator"], "three matched (as given · sorted)");
  eq(p.unmatched, ["Maritime Nowhere"], "one unmatched");
  eq(p.ids.every((id) => ["UPS", "Canada Post", "Purolator"].includes(list.find((s) => s.id === id)?.carrier_name ?? "")), true, "ids only from those carriers: " + p.ids.join(","));
  eq(p.ids.includes("purolatorcourier.express") && !p.ids.includes("purolatorcourier-401.standard"), true, "id prefix is not the carrier key: Purolator = purolatorcourier.* · Purolator Courier = purolatorcourier-401.* (name match is right · fc-0 ④ B would be wrong)");
  eq(p.ids.includes("ups.standard") && p.ids.includes("canadapost-exclusive.expedited-parcel"), true, "known ids present");
  eq(pickServices(list, ["Purolator"]).ids.some((id) => list.find((s) => s.id === id)?.carrier_name === "Purolator Courier"), false, "Purolator does not pull Purolator Courier");
  eq(pickServices(list, []).ids, [], "no carriers → no ids");
  // fc-1b3 판정 847: 한 운송사의 이름 여럿 · /services 의 끝 공백 이름(「Purolator Freight 」 · 「Maritime 」)은 공백 없는 이름에 붙고 · 응답의 소문자(fastfrate)도 같은 열쇠
  const pf = pickServices(list, ["Purolator Freight", "Maritime", "Maritime-Ontario", "fastfrate", "Kindersley", "Kindersley Transport"]);
  eq(pf.unmatched, [], "all six names known (case · trailing-space insensitive)");
  eq(pf.ids.includes("purolatorfreight-151.standard") && pf.ids.includes("purolatorfreight.standard"), true, "trailing-space twin «Purolator Freight » joins Purolator Freight");
  eq(pf.ids.includes("mopallet.standard") && pf.ids.includes("maritime.dry") && pf.ids.includes("maritimeontario-267.standard"), true, "«Maritime » twin + Maritime-Ontario");
  eq(pf.ids.includes("fastfrate.standard") && !pf.ids.includes("LtViz90ze09z34gcXmBbnFhSSqvvO6h5.standard"), true, "fastfrate (lowercase) → Fastfrate · not FastfrateTest");
  eq(pf.ids.some((id) => id.startsWith("kindersley-ftl.")), false, "Kindersley Transport FTL stays out (name not given)");
});

const PKG: RateRequest = { details: { packaging_type: "package", packaging_properties: { packages: [{ measurements: { weight: { unit: "lb", value: 23 }, cuboid: { unit: "in", l: 12, w: 10, h: 8 } }, description: "B1" }] } } };
const PAL: RateRequest = { details: { packaging_type: "pallet", packaging_properties: { pallet_type: "ltl", has_stackable_pallets: false, pallets: [
  { measurements: { weight: { unit: "lb", value: 800 }, cuboid: { unit: "in", l: 48, w: 40, h: 48 } }, description: "P1", num_pieces: 2 },
  { measurements: { weight: { unit: "lb", value: 500 }, cuboid: { unit: "in", l: 48, w: 40, h: 36 } }, description: "P2", num_pieces: 1 } ], pallet_service_details: { threshold_delivery: true } } } };

Deno.test("② 팔렛 freight_class — measurements 둘 · 끼우면 pallets[i].freight_class · 원본 무변 · 수가 다르면 멈춤 · 상자는 빈 배열 · calculate 응답 읽기", () => {
  eq(palletBoxes(PAL).map((m) => m.weight.value), [800, 500], "two boxes");
  eq(palletBoxes(PKG), [], "package → none");
  const out = attachFreightClass(PAL, ["70", "85"]);
  eq((out.details.packaging_properties as { pallets: { freight_class: string }[] }).pallets.map((p) => p.freight_class), ["70", "85"], "classes attached");
  eq((PAL.details.packaging_properties as { pallets: Record<string, unknown>[] }).pallets[0].freight_class, undefined, "original untouched");
  let threw = ""; try { attachFreightClass(PAL, ["70"]); } catch (e) { threw = (e as Error).message; }
  eq(threw.startsWith("freight class count 1 does not match pallets 2"), true, "count mismatch stops");
  eq(freightClassOf({ freight_class: "70" }), "70", "string");
  eq(freightClassOf({ freight_class: 70 }), "70", "number → string");
  threw = ""; try { freightClassOf({}); } catch (e) { threw = (e as Error).message; }
  eq(threw.includes("no freight_class"), true, "missing → error");
});

Deno.test("③ /rate 몸 — 상자 = services 명시 · 팔렛 = services 없이 · request_id 읽기 · 상태 · 다시 묻기 끝 판정(done 또는 25 초)", () => {
  eq(Object.keys(rateBody(PKG, ["ups.standard", "ups.express"])), ["services", "details"], "package: services + details");
  eq(Object.keys(rateBody(PAL, null)), ["details"], "pallet: details only");
  eq(Object.keys(rateBody(PKG, [])), ["details"], "empty list → omitted (caller refuses earlier)");
  eq(requestIdOf({ request_id: " abc-1 " }), "abc-1", "request id trimmed");
  let threw = ""; try { requestIdOf({}); } catch (e) { threw = (e as Error).message; }
  eq(threw.includes("no request_id"), true, "missing id");
  eq(rateStatus({ status: { done: false, complete: 12, total: 38 } }), { done: false, complete: 12, total: 38 }, "status");
  eq(rateStatus({}), { done: false, complete: 0, total: 0 }, "no status → not done");
  const t0 = 1_000_000;
  eq(shouldKeepPolling({ done: false, complete: 1, total: 5 }, t0, t0 + 3_000), true, "3 s · not done → keep");
  eq(shouldKeepPolling({ done: true, complete: 5, total: 5 }, t0, t0 + 3_000), false, "done → stop");
  eq(shouldKeepPolling({ done: false, complete: 4, total: 5 }, t0, t0 + QUOTE_WAIT_MS), false, "deadline → stop (screen polls on)");
});

Deno.test("④ 응답 원문(fixtures) — 센트 정수 글자 · total = base + Σsurcharges + Σtaxes 가 상자 5 · 팔렛 15 + 15 전부 · carrier_name 이 든다(짐작 11 · 12 를 원문이 뒷받침)", () => {
  const pkg = rateLines(read("rate-package.json"));
  eq(pkg.length, 5, "5 UPS rates");
  eq(pkg.every((r) => r.consistent), true, "all consistent: " + JSON.stringify(pkg.map((r) => [r.service_id, r.base, r.surcharges, r.taxes, r.total])));
  eq(pkg.map((r) => r.carrier_name), ["UPS", "UPS", "UPS", "UPS", "UPS"], "carrier_name present");
  eq(cents({ value: "8524", currency: "CAD" }), 8524, "object");
  eq(cents("48671"), 48671, "string");
  eq(cents(null), null, "null");
  const pal = read("rate-pallet-tailgate-false-true.json");
  for (const k of ["False", "True"]) {
    const lines = rateLines(pal[k]);
    eq(lines.length, 15, k + ": 15 rates");
    eq(lines.every((r) => r.consistent), true, k + " all consistent");
    eq(lines.some((r) => r.surcharges > 0), true, k + ": some LTL rates carry surcharges (fuel · line-haul)");
  }
  const f = rateLines(pal.False), t = rateLines(pal.True);
  const byId = new Map(f.map((r) => [r.service_id, r]));
  const diffs = t.map((r) => (r.total ?? 0) - (byId.get(r.service_id)?.total ?? 0)).filter((d) => d !== 0);
  eq(diffs.length > 0 && diffs.every((d) => d > 0), true, "tailgate true costs more on the same services (" + diffs.join(",") + ")");
  eq(t.every((r) => r.base === byId.get(r.service_id)?.base), true, "base unchanged by tailgate — the difference is surcharge only");
});

Deno.test("⑤ 오류 문장 — 토큰 · 열쇠는 가린다 · 401 은 열쇠 안내 · 400 자", () => {
  const s = fcErrorSentence("rate", 401, { error: "unauthorized", api_key: "abcdef0123456789", token: "zzz" });
  eq(s.includes("abcdef0123456789") || s.includes("zzz"), false, "secrets masked: " + s);
  eq(s.includes("FREIGHTCOM_API_KEY"), true, "401 hint");
  eq(fcErrorSentence("rate", 500, "x".repeat(1000)).length < 480, true, "cut");
  eq(fcErrorSentence("rate_poll", 404, null).includes("request_id unknown"), true, "404 hint");
});

Deno.test("⑥ fc-1b4 판정 848 — 계정별 비밀값 FREIGHTCOM_API_KEY_<계정> · 없는 계정은 옛 FREIGHTCOM_API_KEY 로 넘어가지 않음 · 계정 열쇠 꼴 · 캐시 열쇠", () => {
  const env = (k: string) => ({ FREIGHTCOM_API_KEY: "old-shared-key", FREIGHTCOM_API_KEY_TOR: " tor-key " } as Record<string, string>)[k];
  eq(secretNameFor("TOR"), "FREIGHTCOM_API_KEY_TOR", "secret name");
  eq(apiKeyFor(env, "TOR"), "tor-key", "TOR key (trimmed)");
  eq(apiKeyFor(env, "EDM"), "", "EDM has no key — and the legacy FREIGHTCOM_API_KEY is NOT used");
  let threw = ""; try { secretNameFor("tor"); } catch (e) { threw = (e as Error).message; }
  eq(threw.includes('"tor" is not a valid key'), true, "lower-case refused (CHECK is upper-case 2–10)");
  eq([ACCOUNT_RE.test("A1"), ACCOUNT_RE.test("ABCDEFGHIJ"), ACCOUNT_RE.test("ABCDEFGHIJK"), ACCOUNT_RE.test("T"), ACCOUNT_RE.test("T-1")], [true, true, false, false, false], "2–10 upper alnum");
  eq(noAccountSentence("Asung - Edmonton", "EDM").startsWith("Warehouse Asung - Edmonton has no Freightcom connection — the secret FREIGHTCOM_API_KEY_EDM is not set"), true, "sentence names the secret");
  eq(servicesCacheKey(" tor ") === servicesCacheKey("TOR") && servicesCacheKey("TOR") !== servicesCacheKey("EDM"), true, "cache per account");
});

// ── fc-2c 예약 · 취소 · 라벨 (fixtures book-package.json · book-ltl-maritime.json = GET /shipment/{id} 200 원문 · {shipment:{…}} 로 감싸임) ──
Deno.test("⑦ 예약 응답 해석 — {shipment:{…}} · 맨몸 둘 다 · 상자: UPS · 추적 1 · 라벨 5 · bol 빈 글자 · 팔렛: maritime · F8093865 · bolnumber MO393895 · 라벨 1 · POST 202 {id} 읽기", () => {
  const pkg = read("book-package.json"), ltl = read("book-ltl-maritime.json");
  const s = shipmentOf(pkg);
  eq([s.id, s.state, s.primary_tracking_number, (s.tracking_numbers as unknown[]).length, (s.labels as unknown[]).length, s.bolnumber, (s.rate as { service_id: string }).service_id], ["CbeeOPfzfSDUI1ajuQCx8NwjElun7pm4", "waiting-for-transit", "1ZXXXXXXXXXXXXXXXX", 1, 5, "", "ups.standard"], "package shipment");
  eq(shipmentOf(s).id, s.id, "bare body is the same");
  const m = shipmentOf(ltl);
  eq([m.id, m.primary_tracking_number, m.bolnumber, (m.labels as unknown[]).length, (m.details as { packaging_type: string }).packaging_type, (m.rate as { carrier_name: string }).carrier_name], ["uv2bNzor8tvsd2fDt77sTW3VMV9J6H1u", "F8093865", "MO393895", 1, "pallet", "Maritime"], "ltl shipment (B said bol null — the file says MO393895)");
  eq(freightcomIdOf({ id: " abc " }), "abc", "POST /shipment 202 {id}");
  let threw = ""; try { freightcomIdOf({}); } catch (e) { threw = (e as Error).message; }
  eq(threw.includes("no id"), true, "missing id stops");
  eq(shipmentOf(null), {}, "null → empty object");
});

Deno.test("⑧ 다시 묻기 판정 — 202 아직 · 200 끝(fixture) · 400 booking carrier = 실패 문장 · 200 인데 id 없음 = 실패 · 시한 25 초 · 취소 200/204 ok · 403 = 서지 않은 예약", () => {
  eq(bookOutcome(202, null).kind, "pending", "202 → pending");
  const done = bookOutcome(200, read("book-package.json"));
  eq(done.kind === "done" && done.shipment.id, "CbeeOPfzfSDUI1ajuQCx8NwjElun7pm4", "200 fixture → done with shipment");
  const bad = bookOutcome(400, { message: "bad or missing data", data: { booking: "carrier" } });
  eq(bad.kind === "failed" && bad.error, "Freightcom book 400: bad or missing data (booking: carrier)", "400 booking carrier sentence (B · Purolator Freight on the test account)");
  eq(bookOutcome(200, { foo: 1 }).kind, "failed", "200 without id/state → failed");
  eq(bookErrorSentence(401, { error: "unauthorized", token: "zzz" }).includes("zzz"), false, "token masked");
  eq(bookErrorSentence(401, { error: "unauthorized" }).includes("FREIGHTCOM_API_KEY_<account>"), true, "401 hint");
  const t0 = 5_000_000;
  eq(shouldKeepBookPolling({ kind: "pending" }, t0, t0 + 6_000), true, "6 s pending → keep (box took 6 s · B)");
  eq(shouldKeepBookPolling({ kind: "pending" }, t0, t0 + BOOK_WAIT_MS), false, "deadline → stop (screen polls on with booking_id)");
  eq(shouldKeepBookPolling(bad, t0, t0 + 1_000), false, "failed → stop");
  eq(cancelOutcome(200, null), { ok: true, error: null }, "DELETE 200");
  eq(cancelOutcome(204, null).ok, true, "DELETE 204");
  const c403 = cancelOutcome(403, "permission denied");
  eq(c403.ok === false && c403.error!.startsWith("Freightcom cancel 403 — Freightcom refuses: the shipment is not booked there"), true, "403 = failed attempt · nothing to cancel: " + c403.error);
});

Deno.test("⑨ 라벨 고르기(851) — 상자 5 → a6 pdf(padded 아님) + letter pdf 세로(landscape 아님) · zpl · padded · landscape 는 건너뜀 · 팔렛 1 → letter 만 · 빈 목록 · 경로 꼴 · %PDF 판정", () => {
  const p = pickLabels(shipmentOf(read("book-package.json")).labels);
  eq([p.a6?.size, p.a6?.format, p.a6?.padded, /a6\.pdf$/.test(p.a6?.url ?? "")], ["a6", "pdf", false, true], "a6 pdf unpadded");
  eq([p.letter?.size, p.letter?.format, /letter\.pdf$/.test(p.letter?.url ?? ""), /landscape/.test(p.letter?.url ?? "")], ["letter", "pdf", true, false], "letter portrait");
  eq(p.skipped, ["a6:zpl", "letter:pdf", "a6:pdf:padded"], "skipped three (zpl · landscape letter · padded a6)");
  const l = pickLabels(shipmentOf(read("book-ltl-maritime.json")).labels);
  eq([l.a6, l.letter?.size, /BOL\.pdf$/.test(l.letter?.url ?? ""), l.skipped], [null, "letter", true, []], "pallet: one letter (BOL + label) · no a6");
  eq(pickLabels(null), { a6: null, letter: null, skipped: [] }, "no labels");
  eq(pickLabels([{ size: "a6", format: "pdf", padded: true, url: "u" }]).a6?.padded, true, "only padded a6 → take it");
  eq(labelPath("6815bff7-5527-4f8e-9f13-53e02dbe3b67", 3, "a6", false), "fc_label/6815bff7-5527-4f8e-9f13-53e02dbe3b67-3-a6.pdf", "path (matches fc_label_path_ck)");
  eq(labelPath("x", 1, "letter", true), "fc_label/x-1-letter-padded.pdf", "padded path");
  eq(isPdf(new TextEncoder().encode("%PDF-1.4 ...")), true, "pdf magic");
  eq(isPdf(new TextEncoder().encode("<html>")), false, "html is not a pdf (S3 error page)");
});

Deno.test("⑩ 결제수단 · 예약 몸 — 배열 / {payment_methods} · net-terms 먼저 · id 없으면 멈춤 · 캐시 열쇠 · payment_method_id 는 EF 가 끼운다(코드에 값 없음)", () => {
  eq(paymentMethodOf([{ id: "pm1", type: "credit-card", label: "Visa" }, { id: "pm2", type: "net-terms", label: "Net Terms" }]), { id: "pm2", type: "net-terms", label: "Net Terms" }, "net-terms preferred");
  eq(paymentMethodOf({ payment_methods: [{ id: "pm9", type: "credit-card", label: "Visa" }] }).id, "pm9", "wrapped · first when no net-terms");
  let threw = ""; try { paymentMethodOf([]); } catch (e) { threw = (e as Error).message; }
  eq(threw.includes("no payment method"), true, "empty → stop");
  threw = ""; try { paymentMethodOf([{ type: "net-terms" }]); } catch (e) { threw = (e as Error).message; }
  eq(threw.includes("no id"), true, "no id → stop");
  eq(paymentCacheKey(" tor ") === paymentCacheKey("TOR") && paymentCacheKey("TOR") !== servicesCacheKey("TOR"), true, "cache key per account · apart from services");
  const req = { unique_id: "u", service_id: "ups.standard", details: { packaging_type: "package" }, pickup_details: { pre_scheduled_pickup: true } };
  const sent = bookBody(req, "pm2");
  eq(Object.keys(sent).sort(), ["details", "payment_method_id", "pickup_details", "service_id", "unique_id"], "body keys");
  eq((req as Record<string, unknown>).payment_method_id, undefined, "original untouched");
});

// fc-pickup-1 — ⚠️ 아래 schedule 응답은 전부 문서 스키마 짐작(실물은 아무도 못 봤다 · fixtures 폴더는 프로브 원문이라 넣지 않는다) · 첫 실호출 뒤 pickup_check.keys 로 실물 열쇠를 본다
Deno.test("⑪ fc-pickup-1 스케줄 읽기 — status 네 값 · 감쌈 {schedule}/{pickup} · 맨몸 · 밖의 값 · 비문자열 → unknown · 확인번호 trim · 오류 글 열쇠 넷 · keys 정렬 · 시한 5 초 · 읽을 예약인가(상자 · 비정기 · 확인번호 없음) · pickup_poll 은 book 문", () => {
  const pkg = shipmentOf(read("book-package.json"));
  eq(scheduleOutcome({ status: "pending" }), { kind: "pending", status: "pending", confirmation: null, message: null, keys: ["status"] }, "pending bare");
  eq(scheduleOutcome({ schedule: { status: " Done ", pickup_confirmation_number: " 123 " } }), { kind: "done", status: "done", confirmation: "123", message: null, keys: ["schedule"] }, "wrapped {schedule} · trim · lower");
  eq(scheduleOutcome({ pickup: { status: "timed-out" } }).kind, "timed-out", "wrapped {pickup}");
  eq(scheduleOutcome({ status: "error", message: "Carrier rejected the window" }), { kind: "error", status: "error", confirmation: null, message: "Carrier rejected the window", keys: ["message", "status"] }, "error + message · keys sorted");
  eq(scheduleOutcome({ status: "error", errors: [{ message: "no window" }] }).message, "no window", "errors[0].message");
  eq(scheduleOutcome({ status: "error", errors: ["plain"] }).message, "plain", "errors[0] string");
  eq(scheduleOutcome({ status: "error", reason: "r", error_message: "e" }).message, "r", "reason before error_message");
  eq(scheduleOutcome({ status: "Scheduled-Maybe" }), { kind: "unknown", status: "scheduled-maybe", confirmation: null, message: null, keys: ["status"] }, "outside the four → unknown kind · raw kept");
  eq(scheduleOutcome({ status: { done: true } }).status, "unknown", "non-string status → unknown");
  eq(scheduleOutcome(null).status, "unknown", "null body");
  eq(scheduleOutcome([1]).keys, [], "array body → no keys");
  eq(scheduleOutcome({ status: "done", confirmation_number: "C9" }).confirmation, "C9", "confirmation_number fallback");
  eq(scheduleOf({ schedule: [1], status: "done" }).status, "done", "schedule that is an array is not a wrapper");
  eq(SCHEDULE_WAIT_MS, 5_000, "wait 5 s");
  const t0 = 1_000_000;
  eq(shouldKeepSchedulePolling(scheduleOutcome({ status: "pending" }), t0, t0 + 4_999), true, "pending inside 5 s → keep");
  eq(shouldKeepSchedulePolling(scheduleOutcome({ status: "pending" }), t0, t0 + 5_000), false, "pending at 5 s → stop");
  eq(shouldKeepSchedulePolling(scheduleOutcome({ status: "done" }), t0, t0), false, "done → stop");
  eq(shouldKeepSchedulePolling(scheduleOutcome({ status: "weird" }), t0, t0), false, "unknown → stop (save as is)");
  eq(pickupCheckNeeded({ pre_scheduled_pickup: false, date: { year: 2026, month: 11, day: 6 } }, pkg), true, "box · not pre-scheduled · fixture has empty confirmation → read");
  eq(pickupCheckNeeded({ pre_scheduled_pickup: true }, pkg), false, "regular pickup → no read");
  eq(pickupCheckNeeded(null, pkg), false, "pallet (no pickup_details) → no read");
  eq(pickupCheckNeeded(undefined, pkg), false, "missing → no read");
  eq(pickupCheckNeeded({ pre_scheduled_pickup: false }, { ...pkg, pickup_confirmation_number: "9516500" }), false, "confirmation already in the booking answer → no read");
  eq(pickupCheckNeeded({ pre_scheduled_pickup: "false" }, pkg), false, "string \"false\" is not false");
  eq((FC_BOOK_ACTIONS as readonly string[]).includes("pickup_poll"), true, "pickup_poll gated with the booking actions");
});

// fc-pickup-2 — cron 길의 순수 부분(index.ts 의 pickupSweep · serve 분기는 Deno.serve 라 여기서 못 돌린다) · 가짜 응답은 11-05 실물 꼴 {error, pickup_confirmation_number, status} 맨몸 그대로
Deno.test("⑫ fc-pickup-2 cron 길 — action 목록 갈라섬 · limit(1 ~ 50 · 밖 · 글자 · 없음 → 10) · sameSecret · 결과 분류(failed · done · pending · other) · 회차 요약 셈 · 실물 꼴 schedule 응답", () => {
  eq([...FC_CRON_ACTIONS], ["pickup_sweep", "track_sweep"], "cron may only call pickup_sweep and track_sweep (fc-track-2)");
  eq((FC_BOOK_ACTIONS as readonly string[]).includes("pickup_sweep"), false, "pickup_sweep is not a person action (JWT path → 400)");
  eq((FC_CRON_ACTIONS as readonly string[]).includes("pickup_poll"), false, "pickup_poll is not a cron action (key path → 400)");
  eq([SWEEP_LIMIT_DEFAULT, SWEEP_LIMIT_MAX], [10, 50], "limit bounds");
  eq([sweepLimitOf({ limit: 3 }), sweepLimitOf({ limit: "7" }), sweepLimitOf({ limit: 50 }), sweepLimitOf({ limit: 51 }), sweepLimitOf({ limit: 0 }), sweepLimitOf({ limit: 2.5 }), sweepLimitOf({ limit: "x" }), sweepLimitOf({}), sweepLimitOf(null)], [3, 7, 50, 10, 10, 10, 10, 10, 10], "limit parsing");
  eq([sameSecret("abc", "abc"), sameSecret("abc", "abd"), sameSecret("abc", "abcd"), sameSecret("", ""), sameSecret("", "a")], [true, false, false, true, false], "sameSecret");
  const real = { error: "", pickup_confirmation_number: "29FBD3C23EA", status: "done" };                 // 11-05 실물 꼴(맨몸 · 열쇠 셋)
  eq(scheduleOutcome(real), { kind: "done", status: "done", confirmation: "29FBD3C23EA", message: null, keys: ["error", "pickup_confirmation_number", "status"] }, "real shape → done · empty error is not a message");
  eq(scheduleOutcome({ error: "", pickup_confirmation_number: "", status: "pending" }).kind, "pending", "real shape pending");
  eq(sweepKindOf({ checked: false, error: "Couldn't check" }), "failed", "GET failed → failed");
  eq(sweepKindOf({ checked: true, schedule_status: "done" }), "done", "saved done");
  eq(sweepKindOf({ checked: true, schedule_status: "pending" }), "pending", "saved pending");
  eq(sweepKindOf({ checked: true, schedule_status: "timed-out" }), "other", "saved timed-out → other");
  eq(sweepKindOf({ checked: true, schedule_status: "unknown" }), "other", "saved unknown → other");
  eq(sweepKindOf({ checked: true }), "other", "saved without status → other (never silently done)");
  eq(sweepSummary([{ kind: "done" }, { kind: "pending" }, { kind: "failed" }, { kind: "done" }, { kind: "other" }]), { read: 4, done: 2, pending: 1, other: 1, failed: 1 }, "summary · read excludes failed");
  eq(sweepSummary([]), { read: 0, done: 0, pending: 0, other: 0, failed: 0 }, "empty run");
});
