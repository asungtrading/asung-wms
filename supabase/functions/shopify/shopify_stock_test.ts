// deno test supabase/functions/shopify/shopify_stock_test.ts — Shopify · DB 무접촉 (stock-1b ① ~ ⑥ · _shared/shopify-stock.ts 의 순수 함수)
import { activateKeyParts, activeLevels, chunk, countsToward, drainShouldStop, idemKey, needActivation, planRows, setInput, setKeyParts, sortedForSet, splitUserErrors, STOCK_BATCH, STOCK_REF, type QueueRow, type SendItem, type SentRow, type StockPayloadRow } from "../_shared/shopify-stock.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const S = "s0000000-0000-0000-0000-000000000000";
const P = (i: number) => "p000000" + i + "-0000-0000-0000-000000000000";
const W_TO = "w0000000-0000-0000-0000-00000000000a", W_ED = "w0000000-0000-0000-0000-00000000000b";
const L_TO = "gid://shopify/Location/86890414263", L_ED = "gid://shopify/Location/86891397303";
const ITEM = (i: number) => "gid://shopify/InventoryItem/5144225" + i;
const row = (i: number, wh: string, loc: string, q: number | string, extra: Partial<StockPayloadRow> = {}): StockPayloadRow =>
  ({ store_id: S, product_id: P(i), sku: "SKU" + i, inventory_item_gid: ITEM(i), warehouse_id: wh, location_gid: loc, quantity: q, is_off: false, blocks: [], ...extra });
const q = (id: number, i: number, force = false, reason = "inv_ledger"): QueueRow => ({ id, store_id: S, product_id: P(i), reason, force });

Deno.test("① planRows — 변형 없음 skipped_off · blocks error · 같으면 skipped_same · 다른 위치만 보냄 · force 면 둘 다 · 꺼진 구성원 0 · 음수 · 소수 · 문자열 수량", () => {
  const payload: StockPayloadRow[] = [
    row(1, W_TO, L_TO, 32), row(1, W_ED, L_ED, 8),                          // ANN01001 꼴
    row(2, W_TO, L_TO, "43"), row(2, W_ED, L_ED, 1),                        // 문자열 수량(PostgREST numeric)
    row(3, W_TO, L_TO, 0, { is_off: true }), row(3, W_ED, L_ED, 0, { is_off: true }),   // 꺼진 구성원 — 0
    row(4, W_TO, L_TO, 12, { inventory_item_gid: null, blocks: ["no_inventory_item"] }), row(4, W_ED, L_ED, 2, { inventory_item_gid: null, blocks: ["no_inventory_item"] }),
    row(5, W_TO, L_TO, -3), row(5, W_ED, L_ED, 2.7),
  ];
  const sent: SentRow[] = [
    { product_id: P(1), warehouse_id: W_TO, quantity: 32, last_status: "ok" }, { product_id: P(1), warehouse_id: W_ED, quantity: 7, last_status: "ok" },   // Edmonton 만 다르다
    { product_id: P(2), warehouse_id: W_TO, quantity: "43", last_status: "ok" }, { product_id: P(2), warehouse_id: W_ED, quantity: 1, last_status: "ok" },   // 둘 다 같다
    { product_id: P(3), warehouse_id: W_TO, quantity: 0, last_status: "error" },                                                                   // error 는 다름으로
  ];
  const plans = planRows([q(10, 1), q(11, 2), q(12, 3), q(13, 4), q(14, 5), q(15, 9), q(16, 2, true)], payload, sent);
  eq(plans.map((p) => p.queue_id + ":" + p.result + ":" + p.items.length), ["10:send:1", "11:skipped_same:0", "12:send:2", "13:error:0", "14:send:2", "15:skipped_off:0", "16:send:2"], "row results");
  eq(plans[0].items[0], { queue_id: 10, product_id: P(1), sku: "SKU1", warehouse_id: W_ED, inventory_item_gid: ITEM(1), location_gid: L_ED, quantity: 8 }, "only the differing location is sent");
  eq(plans[2].items.map((i) => i.quantity), [0, 0], "member off → 0 at both (error sent row counts as different)");
  eq(plans[3].error, "cannot send stock: no_inventory_item (send the product first)", "blocks message");
  eq(plans[4].items.map((i) => i.quantity), [0, 2], "negative → 0 · 2.7 → 2 (floor)");
  eq(plans[6].items.map((i) => i.location_gid), [L_TO, L_ED], "force sends both locations (sorted by location gid · Toronto 86890… < Edmonton 86891…)");
});

Deno.test("② chunk · setInput — 100 개씩 · quantities 는 (item · location) 정렬 · changeFromQuantity null · name available · reason correction · referenceDocumentUri", () => {
  const items: SendItem[] = Array.from({ length: 230 }, (_, i) => ({ queue_id: i, product_id: P(i % 9), sku: "S", warehouse_id: i % 2 ? W_ED : W_TO, inventory_item_gid: ITEM(9 - (i % 10)), location_gid: i % 2 ? L_ED : L_TO, quantity: i }));
  const parts = chunk(items);
  eq(parts.map((c) => c.length), [100, 100, 30], "chunks of " + STOCK_BATCH);
  const inp = setInput(parts[0].slice(0, 3), 17) as { name: string; reason: string; referenceDocumentUri: string; quantities: Array<Record<string, unknown>> };
  eq([inp.name, inp.reason, inp.referenceDocumentUri], ["available", "correction", STOCK_REF(17)], "header");
  eq(inp.quantities.map((x) => x.inventoryItemId + "|" + x.locationId), [ITEM(7) + "|" + L_TO, ITEM(8) + "|" + L_ED, ITEM(9) + "|" + L_TO], "sorted by item then location");
  eq(inp.quantities[0], { inventoryItemId: ITEM(7), locationId: L_TO, quantity: 2, changeFromQuantity: null }, "no compare (421)");
});

Deno.test("③ idemKey — 같은 입력(순서 달라도) → 같은 키 · 수량 하나 바뀌면 다른 키 · 큐 줄 id 가 다르면(새벽 force 되풀이) 다른 키 · 참조가 다르면 다른 키 · UUID 모양 · activate 키는 (item · location)", async () => {
  const a: SendItem[] = [{ queue_id: 1, product_id: P(1), sku: "A", warehouse_id: W_TO, inventory_item_gid: ITEM(1), location_gid: L_TO, quantity: 32 }, { queue_id: 1, product_id: P(1), sku: "A", warehouse_id: W_ED, inventory_item_gid: ITEM(1), location_gid: L_ED, quantity: 8 }];
  const k1 = await idemKey(setKeyParts(a, 17)), k2 = await idemKey(setKeyParts(a.slice().reverse(), 17));
  const k3 = await idemKey(setKeyParts([a[0], { ...a[1], quantity: 9 }], 17));
  const k4 = await idemKey(setKeyParts(a.map((i) => ({ ...i, queue_id: 99 })), 99));
  const k5 = await idemKey(setKeyParts(a, "push-1"));
  eq(k1 === k2, true, "order independent"); eq(k1 === k3, false, "quantity change → new key"); eq(k1 === k4, false, "new queue rows (same quantities) → new key"); eq(k1 === k5, false, "different ref → new key");
  eq(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(k1), true, "uuid shape " + k1);
  eq(await idemKey(activateKeyParts(ITEM(1), L_ED)) === await idemKey(activateKeyParts(ITEM(1), L_TO)), false, "activate keys differ per location");
  eq(await idemKey(activateKeyParts(ITEM(1), L_ED)) === k1, false, "activate key ≠ set key");
});

Deno.test("④ activeLevels · needActivation — Toronto 만 붙은 아이템은 Edmonton 만 activate · 둘 다 붙으면 0 · 같은 짝 두 번은 한 번", () => {
  const nodes = [
    { id: ITEM(1), tracked: true, inventoryLevels: { nodes: [{ location: { id: L_TO } }] } },
    { id: ITEM(2), tracked: true, inventoryLevels: { nodes: [{ location: { id: L_TO } }, { location: { id: L_ED } }] } },
    null,
  ];
  const active = activeLevels(nodes);
  eq([...active].sort(), [ITEM(1) + "|" + L_TO, ITEM(2) + "|" + L_ED, ITEM(2) + "|" + L_TO].sort(), "active pairs");
  const items: SendItem[] = [
    { queue_id: 1, product_id: P(1), sku: "A", warehouse_id: W_TO, inventory_item_gid: ITEM(1), location_gid: L_TO, quantity: 1 },
    { queue_id: 1, product_id: P(1), sku: "A", warehouse_id: W_ED, inventory_item_gid: ITEM(1), location_gid: L_ED, quantity: 1 },
    { queue_id: 2, product_id: P(2), sku: "B", warehouse_id: W_ED, inventory_item_gid: ITEM(2), location_gid: L_ED, quantity: 1 },
    { queue_id: 3, product_id: P(1), sku: "A", warehouse_id: W_ED, inventory_item_gid: ITEM(1), location_gid: L_ED, quantity: 1 },
  ];
  eq(needActivation(items, active), [{ inventory_item_gid: ITEM(1), location_gid: L_ED }], "only item1@Edmonton · once");
});

Deno.test("⑤ splitUserErrors — field 경로의 자리로 그 아이템만 · 경로 없으면 묶음 전체 · 두 오류 한 자리면 이어 붙임", () => {
  const items: SendItem[] = sortedForSet([
    { queue_id: 1, product_id: P(1), sku: "A", warehouse_id: W_TO, inventory_item_gid: ITEM(2), location_gid: L_TO, quantity: 1 },
    { queue_id: 1, product_id: P(1), sku: "A", warehouse_id: W_ED, inventory_item_gid: ITEM(1), location_gid: L_ED, quantity: 1 },
  ]);
  eq(items.map((i) => i.inventory_item_gid), [ITEM(1), ITEM(2)], "sorted");
  const s = splitUserErrors([
    { field: ["input", "quantities", "1", "quantity"], message: "too high", code: "INVALID_QUANTITY_TOO_HIGH" },
    { field: ["input", "quantities", "1"], message: "not stocked", code: "ITEM_NOT_STOCKED_AT_LOCATION" },
  ], items);
  eq([...s.perItem.entries()], [[1, "INVALID_QUANTITY_TOO_HIGH: too high · ITEM_NOT_STOCKED_AT_LOCATION: not stocked"]], "per item (index 1 = item2@Toronto)");
  eq(s.whole, null, "no whole error");
  const w = splitUserErrors([{ field: null, message: "The same idempotency key cannot be used with different operation parameters.", code: "IDEMPOTENCY_KEY_PARAMETER_MISMATCH" }, { field: ["input", "reason"], message: "bad reason" }], items);
  eq(w.perItem.size, 0, "none per item"); eq(w.whole, "IDEMPOTENCY_KEY_PARAMETER_MISMATCH: The same idempotency key cannot be used with different operation parameters. · bad reason", "whole");
});

Deno.test("⑥ 상품 drain 칸 셈(판정 424 ②) — skipped_same_hash 는 안 센다 · 20 건 보내면 멈춤 · 시간 한도로 멈춤", () => {
  eq(["ok", "error", "skipped_same_hash"].map(countsToward), [true, true, false], "countsToward");
  eq(drainShouldStop(19, 20, 1000), null, "19 sent · go on");
  eq(drainShouldStop(20, 20, 1000), "batch full (20)", "20 sent · stop");
  eq(drainShouldStop(3, 20, 40_000), "time limit (40 s)", "time");
  eq(drainShouldStop(0, 20, 39_999), null, "just under the limit");
});
