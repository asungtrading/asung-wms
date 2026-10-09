// deno test supabase/functions/shopify/shopify_test.ts — Shopify · DB 무접촉 (shop-1b ① ~ ④ · _shared/shopify.ts 의 순수 함수만)
import { compareLocations, costOf, isThrottled, missingScopes, REQUIRED_SCOPES, secretNames, throttleWaitMs, tokenErrorSentence, type PairRow, type ShopLocation } from "../_shared/shopify.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const GRANTED6 = "write_products,write_inventory,read_locations,write_orders,write_merchant_managed_fulfillment_orders,read_customers";   // 실측(shop-0 D · 토큰 응답 scope)

Deno.test("① scope 대조 — 실측 6 개 → missing 0 · read_locations 를 빼면 1 · write_orders 를 빼면 read_orders · write_orders 둘 · 빈 글자 → 10", () => {
  eq(REQUIRED_SCOPES.length, 10, "required 10");
  eq(missingScopes(GRANTED6), [], "measured six → nothing missing");
  eq(missingScopes(GRANTED6.replace("read_locations", "")), ["read_locations"], "one read scope gone");
  eq(missingScopes(GRANTED6.replace("write_orders", "")), ["read_orders", "write_orders"], "write gone → both");
  eq(missingScopes(" write_products , read_customers "), REQUIRED_SCOPES.filter((s) => !["read_products", "write_products", "read_customers"].includes(s)), "spaces trimmed");
  eq(missingScopes("").length, 10, "empty → all");
  eq(secretNames("SHOPIFY_IMS"), { id: "SHOPIFY_IMS_CLIENT_ID", secret: "SHOPIFY_IMS_CLIENT_SECRET" }, "secret names");
});

const TOR = "gid://shopify/Location/86890414263", EDM = "gid://shopify/Location/90000000001", OLD = "gid://shopify/Location/70000000000";
const pair = (id: string, gid: string, wh: string, is_active = true, name: string | null = null): PairRow => ({ id, shopify_location_gid: gid, shopify_name: name, warehouse_id: wh, warehouse_name: wh === "W1" ? "Asung Trading Inc." : "Asung - Edmonton", is_active });
const loc = (id: string, name: string, isActive = true): ShopLocation => ({ id, name, isActive });

Deno.test("② 위치 대조 — 짝 없음 location_unmapped · 짝만 있음 location_missing · Shopify 에서 꺼짐 · 이름 바뀜은 경고 아님(updates 에만) · 꺼진 짝은 안 센다", () => {
  const r0 = compareLocations([loc(TOR, "Shop location")], []);
  eq(r0.warnings, [{ code: "location_unmapped", gid: TOR, name: "Shop location" }], "first ping: one unmapped");
  eq(r0.updates, [], "nothing to update");
  const r1 = compareLocations([loc(TOR, "Toronto"), loc(EDM, "Edmonton")], [pair("p1", TOR, "W1", true, "Shop location")]);
  eq(r1.warnings, [{ code: "location_unmapped", gid: EDM, name: "Edmonton" }], "renamed Toronto is not a warning · Edmonton unmapped");
  eq(r1.updates, [{ id: "p1", gid: TOR, name: "Toronto" }], "name update for the paired one");
  const r2 = compareLocations([loc(TOR, "Toronto")], [pair("p1", TOR, "W1"), pair("p2", OLD, "W2")]);
  eq(r2.warnings, [{ code: "location_missing", gid: OLD, name: "Asung - Edmonton", detail: "not in Shopify" }], "pair whose gid is gone");
  const r3 = compareLocations([loc(TOR, "Toronto"), loc(EDM, "Edmonton", false)], [pair("p1", TOR, "W1"), pair("p2", EDM, "W2")]);
  eq(r3.warnings, [{ code: "location_missing", gid: EDM, name: "Edmonton", detail: "inactive in Shopify" }], "inactive in Shopify");
  eq(r3.updates.map((u) => u.id), ["p1", "p2"], "name still refreshed for the inactive one");
  const r4 = compareLocations([loc(TOR, "Toronto"), loc(EDM, "Edmonton", false)], [pair("p1", TOR, "W1"), pair("p9", EDM, "W2", false)]);
  eq(r4.warnings, [{ code: "location_unmapped", gid: EDM, name: "Edmonton (inactive)" }], "switched-off pair does not count · inactive Shopify location is told");
});

Deno.test("③ 한도 — 429 · extensions.code THROTTLED(짐작) · 기다림 = (요청 − 남은) / 회복률 · 상한 10 s · 정보 없으면 1 s × 2^회차", () => {
  eq(isThrottled(429, null), true, "429");
  eq(isThrottled(200, { errors: [{ extensions: { code: "THROTTLED" } }] }), true, "code throttled");
  eq(isThrottled(200, { errors: [{ extensions: { code: "MAX_COST_EXCEEDED" } }] }), false, "other code is not a throttle");
  eq(isThrottled(200, null), false, "ok");
  const ext = { cost: { requestedQueryCost: 1004, actualQueryCost: 0, throttleStatus: { maximumAvailable: 4000, currentlyAvailable: 4, restoreRate: 200 } } };
  eq(throttleWaitMs(ext, 1), 5250, "(1004 − 4) / 200 = 5 s + 250 ms");
  eq(throttleWaitMs({ cost: { requestedQueryCost: 50, throttleStatus: { currentlyAvailable: 4000, restoreRate: 200 } } }, 1), 250, "already enough → floor 250");
  eq(throttleWaitMs({ cost: { requestedQueryCost: 99999, throttleStatus: { currentlyAvailable: 0, restoreRate: 1 } } }, 1), 10000, "cap 10 s");
  eq([throttleWaitMs(null, 0), throttleWaitMs(null, 1), throttleWaitMs(undefined, 2), throttleWaitMs({}, 3)], [1000, 2000, 4000, 8000], "no info → backoff");
  eq(costOf({ cost: { requestedQueryCost: 4, actualQueryCost: 4, throttleStatus: { currentlyAvailable: 3996.5, restoreRate: 200 } } }), { requested: 4, actual: 4, available: 3997, restoreRate: 200 }, "cost rounded");
  eq(costOf(null), { requested: null, actual: null, available: null, restoreRate: null }, "no cost");
});

Deno.test("④ 토큰 오류 문장 — shop_not_permitted · invalid_client · 그 밖", () => {
  const s = { id: "x", code: "test", shop_domain: "asung-ims-test.myshopify.com", secret_prefix: "SHOPIFY_IMS", is_active: true };
  eq(tokenErrorSentence(403, { error: "shop_not_permitted" }, s).startsWith("Shopify refused the app for asung-ims-test.myshopify.com (shop_not_permitted) — the app and the store belong to different organizations"), true, "org sentence");
  eq(tokenErrorSentence(401, { error: "invalid_client" }, s).includes("SHOPIFY_IMS_CLIENT_ID / _CLIENT_SECRET"), true, "names the secrets");
  eq(tokenErrorSentence(500, { error: "x", error_description: "y" }, s), "Shopify token request for asung-ims-test.myshopify.com failed (HTTP 500 · x · y)", "generic");
});
