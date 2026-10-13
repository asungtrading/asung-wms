// deno test supabase/functions/shopify/shopify_fulfill_test.ts — Shopify · DB 무접촉 (ful-2 ① ~ ⑧ · _shared/shopify-fulfill.ts 의 순수 함수)
import { adoptExisting, buildFulfillmentInput, FULFILL_MAX_ATTEMPTS, movesNeeded, pickupPath, planLines, preparedForPickupInput, queueOutcome, remapAfterMove, trackingUrls, userErrorsText, type FoNode, type FulfillmentNode, type FulLine, type FulRow } from "../_shared/shopify-fulfill.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const L_TO = "gid://shopify/Location/86890414263", L_ED = "gid://shopify/Location/86891397303";
const LI = (i: number) => "gid://shopify/LineItem/1637894078482" + i;
const FOL = (fo: number, i: number) => "gid://shopify/FulfillmentOrderLineItem/" + fo + "0" + i;
const fo = (id: number, loc: string, lines: Array<[number, number]>, extra: Partial<FoNode> = {}): FoNode =>
  ({ id: "gid://shopify/FulfillmentOrder/" + id, status: "OPEN", requestStatus: "UNSUBMITTED", assignedLocation: { location: { id: loc, name: loc === L_TO ? "Toronto" : "Edmonton" } }, deliveryMethod: { methodType: "SHIPPING" },
     lineItems: { nodes: lines.map(([i, rem]) => ({ id: FOL(id, i), totalQuantity: rem, remainingQuantity: rem, lineItem: { id: LI(i), sku: "SKU" + i } })) }, ...extra });
const line = (i: number, qty: number): FulLine => ({ id: "fl-" + i, line_gid: LI(i), so_line_id: "sl-" + i, quantity: qty });
const row = (kind: FulRow["carrier_kind"], numbers: string[] = [], company: string | null = "Canada Post"): FulRow =>
  ({ id: "f-1", so_id: "so-1", shop_order_id: "o-1", store_id: "s-1", carrier_id: "c-1", carrier_name: kind === "carrier" ? "Canada Post" : kind === "pickup" ? "Pickup" : "Delivery", carrier_kind: kind, shopify_company: kind === "carrier" ? company : null,
     tracking_numbers: numbers, notify_customer: kind === "carrier", status: "pending", attempts: 0, created_at: "2026-10-13T15:00:00Z" });

Deno.test("① planLines — 같은 위치 · 수량 그대로 · 두 줄 · FO 하나", () => {
  const p = planLines([line(1, 2), line(2, 3)], [fo(1, L_TO, [[1, 2], [2, 3]])]);
  eq(p.items.map((i) => [i.fo_line_id, i.qty]), [[FOL(1, 1), 2], [FOL(1, 2), 3]], "items");
  eq(p.cut, [], "no cut"); eq(p.nothing, [], "nothing"); eq(p.sent_by_line, { "fl-1": 2, "fl-2": 3 }, "sent_by_line");
});
Deno.test("② planLines — 수량 자르기(Shopify 남은 1 · 보낼 3) · 닫힌 FO 는 안 쓴다 · 남은 0 줄은 nothing · 문자열 수량", () => {
  const p = planLines([line(1, 3), line(2, 2), { ...line(3, 1), quantity: "1" }], [fo(1, L_TO, [[1, 1], [2, 0], [3, 5]]), fo(2, L_TO, [[2, 9]], { status: "CLOSED" })]);
  eq(p.items.map((i) => [i.line_id, i.qty]), [["fl-1", 1], ["fl-3", 1]], "items");
  eq(p.cut, [{ line_id: "fl-1", line_gid: LI(1), wanted: 3, sent: 1 }], "cut");
  eq(p.nothing, ["fl-2"], "nothing — closed FO 의 9 는 안 센다");
});
Deno.test("③ planLines — 한 줄이 FO 둘에 걸쳐 있으면 FO id 순으로 채운다(2 + 1) · 같은 FO 줄을 두 결과 줄이 나눠 쓰지 않는다", () => {
  const p = planLines([line(1, 3)], [fo(2, L_ED, [[1, 1]]), fo(1, L_TO, [[1, 2]])]);
  eq(p.items.map((i) => [i.fo_id.split("/").pop(), i.qty]), [["1", 2], ["2", 1]], "two FOs");
  const p2 = planLines([line(1, 2), { ...line(1, 2), id: "fl-1b" }], [fo(1, L_TO, [[1, 3]])]);
  eq(p2.items.map((i) => [i.line_id, i.qty]), [["fl-1", 2], ["fl-1b", 1]], "shared remaining 3 → 2 + 1");
  eq(p2.cut.map((c) => c.line_id), ["fl-1b"], "second is cut");
});
Deno.test("④ movesNeeded · remapAfterMove — Toronto FO · SO Edmonton → move 보낼 줄 · 수량만 · 옮긴 뒤 새 FO 의 줄 id 로 · 못 찾은 줄 unmatched · 같은 위치면 move 0", () => {
  const fos = [fo(1, L_TO, [[1, 5], [2, 5]])];
  const p = planLines([line(1, 2), line(2, 5)], fos);
  eq(movesNeeded(p.items, fos, L_ED), [{ fo_id: "gid://shopify/FulfillmentOrder/1", from_location: L_TO, items: [{ id: FOL(1, 1), quantity: 2 }, { id: FOL(1, 2), quantity: 5 }] }], "move with items only");
  eq(movesNeeded(p.items, fos, L_TO), [], "same location");
  eq(movesNeeded(p.items, fos, null), [], "no pair → no move");
  const moved = fo(9, L_ED, [[1, 2], [2, 5]]);                                               // 새 FO(원래 FO 에 발송된 줄이 있던 경우)
  const r = remapAfterMove(p.items, "gid://shopify/FulfillmentOrder/1", moved);
  eq(r.items.map((i) => [i.fo_id.split("/").pop(), i.fo_line_id, i.qty]), [["9", FOL(9, 1), 2], ["9", FOL(9, 2), 5]], "remapped");
  eq(r.unmatched, 0, "all matched");
  const r2 = remapAfterMove(p.items, "gid://shopify/FulfillmentOrder/1", fo(9, L_ED, [[1, 2]]));
  eq([r2.unmatched, r2.items[1].fo_line_id], [1, FOL(1, 2)], "unmatched keeps the old line id");
  eq(remapAfterMove(p.items, "gid://shopify/FulfillmentOrder/1", null).items, p.items, "null moved → unchanged");
});
Deno.test("⑤ buildFulfillmentInput — carrier: company · numbers · urls(틀) · notify true / delivery: trackingInfo 없음 · notify false / 목록에 없는 운송사: company 없이 번호만 / FO 둘 묶기", () => {
  const fos = [fo(1, L_TO, [[1, 2]]), fo(2, L_TO, [[2, 3]])];
  const p = planLines([line(1, 2), line(2, 3)], fos);
  const a = buildFulfillmentInput(row("carrier", ["A1", "B2"]), p.items, "https://t.example/{number}");
  eq(a, { lineItemsByFulfillmentOrder: [{ fulfillmentOrderId: "gid://shopify/FulfillmentOrder/1", fulfillmentOrderLineItems: [{ id: FOL(1, 1), quantity: 2 }] }, { fulfillmentOrderId: "gid://shopify/FulfillmentOrder/2", fulfillmentOrderLineItems: [{ id: FOL(2, 2), quantity: 3 }] }],
         notifyCustomer: true, trackingInfo: { numbers: ["A1", "B2"], company: "Canada Post", urls: ["https://t.example/A1", "https://t.example/B2"] } }, "carrier input");
  const d = buildFulfillmentInput(row("delivery"), p.items, null);
  eq(Object.keys(d).sort(), ["lineItemsByFulfillmentOrder", "notifyCustomer"], "delivery — no trackingInfo");
  eq(d.notifyCustomer, false, "delivery — no mail");
  const u = buildFulfillmentInput(row("carrier", ["X 1"], null), p.items, null);
  eq(u.trackingInfo, { numbers: ["X 1"] }, "unknown carrier — numbers only");
  eq(trackingUrls("https://t/{number}/x", ["a b"]), ["https://t/a%20b/x"], "url encode");
  eq(trackingUrls("https://t/no-placeholder", ["a"]), [], "template without {number} → none");
  eq(preparedForPickupInput(["fo-1", "fo-1", "fo-2"]), { lineItemsByFulfillmentOrder: [{ fulfillmentOrderId: "fo-1" }, { fulfillmentOrderId: "fo-2" }] }, "prepared input · dedup");
});
Deno.test("⑥ pickupPath — pickup + PICK_UP → ready_pickup · pickup + SHIPPING → create · delivery + PICK_UP → create · carrier → create · FO 섞이면 create", () => {
  const pick = fo(1, L_TO, [[1, 1]], { deliveryMethod: { methodType: "PICK_UP" } });
  const ship = fo(2, L_TO, [[2, 1]]);
  const p1 = planLines([line(1, 1)], [pick]);
  eq(pickupPath("pickup", p1.items, [pick]), "ready_pickup", "pickup + PICK_UP");
  eq(pickupPath("delivery", p1.items, [pick]), "create", "delivery + PICK_UP → 378");
  eq(pickupPath("carrier", p1.items, [pick]), "create", "carrier");
  const p2 = planLines([line(2, 1)], [ship]);
  eq(pickupPath("pickup", p2.items, [ship]), "create", "pickup + SHIPPING → 378");
  const p3 = planLines([line(1, 1), line(2, 1)], [pick, ship]);
  eq(pickupPath("pickup", p3.items, [pick, ship]), "create", "mixed FOs → create");
  eq(pickupPath("pickup", [], [pick]), "create", "no items");
});
Deno.test("⑦ adoptExisting — Shopify 발송 뒤 기록 실패 → 다음 회차: carrier 는 송장이 겹치는 발송 · pickup/delivery 는 큐 뒤의 송장 없는 발송(가장 최근) · 취소된 것 · 큐 전 것 · 번호 없음은 안 받는다", () => {
  const fs: FulfillmentNode[] = [
    { id: "gid://shopify/Fulfillment/1", status: "SUCCESS", createdAt: "2026-10-13T15:01:00Z", trackingInfo: [{ number: "A1" }, { number: "B2" }] },
    { id: "gid://shopify/Fulfillment/2", status: "CANCELLED", createdAt: "2026-10-13T15:02:00Z", trackingInfo: [{ number: "C3" }] },
    { id: "gid://shopify/Fulfillment/3", status: "SUCCESS", createdAt: "2026-10-13T14:00:00Z", trackingInfo: [] },           // 큐 전(15:00) 에 만든 것
    { id: "gid://shopify/Fulfillment/4", status: "SUCCESS", createdAt: "2026-10-13T15:03:00Z", trackingInfo: [] },
    { id: "gid://shopify/Fulfillment/5", status: "SUCCESS", createdAt: "2026-10-13T15:05:00Z", trackingInfo: [{ number: "" }] },
  ];
  eq(adoptExisting(row("carrier", ["B2", "ZZ"]), fs), "gid://shopify/Fulfillment/1", "carrier — overlapping number");
  eq(adoptExisting(row("carrier", ["C3"]), fs), null, "carrier — only the cancelled one matches");
  eq(adoptExisting(row("carrier", []), fs), null, "carrier — no numbers");
  eq(adoptExisting(row("delivery"), fs), "gid://shopify/Fulfillment/5", "delivery — latest no-tracking after queue time (empty number counts as none)");
  eq(adoptExisting(row("pickup"), fs.slice(0, 3)), null, "pickup — only the pre-queue one → none");
  // planLines 로 「보낼 것 0」 이 먼저 서야 adopt 를 본다(index.ts 흐름) — remaining 0 인 FO 하나
  eq(planLines([line(1, 2)], [fo(1, L_TO, [[1, 0]])]).items, [], "nothing left → adopt path");
});
Deno.test("⑧ queueOutcome · userErrorsText — 전부 sent/skipped → done ok · error 있으면 열어 둠 · 5 회째 → done error + 경고", () => {
  eq(queueOutcome(["sent", "skipped"], 0), { done: true, result: "ok", attempts: 0, warn: false }, "ok");
  eq(queueOutcome(["sent", "error"], 0), { done: false, result: null, attempts: 1, warn: false }, "retry 1");
  eq(queueOutcome(["error"], FULFILL_MAX_ATTEMPTS - 2), { done: false, result: null, attempts: FULFILL_MAX_ATTEMPTS - 1, warn: false }, "retry 4");
  eq(queueOutcome(["error"], FULFILL_MAX_ATTEMPTS - 1), { done: true, result: "error", attempts: FULFILL_MAX_ATTEMPTS, warn: true }, "5th → closed + warn");
  eq(queueOutcome(["pending"], 0), { done: false, result: null, attempts: 1, warn: false }, "pending (not reached) counts as not done");
  eq(userErrorsText([{ field: ["fulfillment", "trackingInfo"], message: "bad", code: "INVALID" }, { message: "x" }]), "fulfillment.trackingInfo: bad (INVALID) · x", "text");
  eq(userErrorsText(null), "", "null");
});
