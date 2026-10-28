// deno test --allow-read supabase/functions/freightcom/freightcom_test.ts — Freightcom · DB · 네트워크 무접촉 (fc-1b · _shared/freightcom.ts 의 순수 함수 · fixtures = 2026-10-28 Caleb PC 프로브 원문 · 토큰 없음)
import { attachFreightClass, cents, distinctCarriers, fcErrorSentence, freightClassOf, palletBoxes, parseServices, pickServices, QUOTE_WAIT_MS, rateBody, rateLines, rateStatus, requestIdOf, shouldKeepPolling, type RateRequest } from "../_shared/freightcom.ts";

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
