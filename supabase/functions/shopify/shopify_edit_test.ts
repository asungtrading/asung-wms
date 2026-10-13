// deno test supabase/functions/shopify/shopify_edit_test.ts — Shopify · DB 무접촉 (ful-4b ① ~ ⑤ · _shared/shopify-edit.ts 의 순수 함수)
import { clampEditable, isPaid, matchCalcLine, planOrderEdit, removedQty, type CalcLine, type DbLine, type LiveLine } from "../_shared/shopify-edit.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const LI = (i: number) => "gid://shopify/LineItem/940000000010" + i;
const CL = (i: number) => "gid://shopify/CalculatedLineItem/940000000010" + i;
const V = (i: number) => "gid://shopify/ProductVariant/5" + i;
const live = (i: number, qty: number, cur: number, unf: number, sku = "SKU" + i, v = i): LiveLine => ({ id: LI(i), sku, quantity: qty, currentQuantity: cur, unfulfilledQuantity: unf, variant: { id: V(v) } });
const db = (i: number, qty: number, can: number | string): DbLine => ({ shop_order_line_id: "sol-" + i, line_gid: LI(i), quantity: qty, can_ship: can });
const calc = (i: number, qty: number, editable: number, sku = "SKU" + i, v = i): CalcLine => ({ id: CL(i), sku, quantity: qty, editableQuantity: editable, restockable: true, variant: { id: V(v) } });

Deno.test("① planOrderEdit — 줄 하나: qty 5 · 보낸 1(current 5 · unfulfilled 4) · can_ship 2 → to_remove 2 · new 3 / can_ship 4 → 0 / can_ship 7 → 0(넘치면 0)", () => {
  eq(planOrderEdit([db(1, 5, 2)], [live(1, 5, 5, 4)]).edits[0], { line_gid: LI(1), shop_order_line_id: "sol-1", current: 5, unfulfilled: 4, can_ship: 2, to_remove: 2, new_quantity: 3 }, "① 2 지움");
  eq(planOrderEdit([db(1, 5, 4)], [live(1, 5, 5, 4)]).total_remove, 0, "① 전부 나갈 수 있다");
  eq(planOrderEdit([db(1, 5, "7")], [live(1, 5, 5, 4)]).total_remove, 0, "① can_ship 이 더 커도 0(문자열 수량)");
});
Deno.test("② planOrderEdit — 줄 둘 · 하나는 Shopify 에 없음(missing · 지우지 않음) · 이미 직원이 줄인 줄(current 3 · unfulfilled 3 · can_ship 3 → 0)", () => {
  const p = planOrderEdit([db(1, 5, 1), db(2, 2, 0), db(3, 1, 0)], [live(1, 5, 3, 3), live(2, 2, 2, 2)]);
  eq(p.edits.map((e) => [e.line_gid.split("/").pop(), e.to_remove, e.new_quantity]), [["9400000000101", 2, 1], ["9400000000102", 2, 0]], "② 줄 둘");
  eq(p.total_remove, 4, "② 합");
  eq(p.missing, [LI(3)], "② Shopify 에 없는 줄");
  eq(planOrderEdit([db(1, 5, 3)], [live(1, 5, 3, 3)]).total_remove, 0, "② 직원이 이미 줄였으면 0 → 받아 적기");
});
Deno.test("③ 일부 발송 줄 — clampEditable: quantity 5 · editable 2(3 은 이미 나감) → new 1 은 3 으로 올려 자른다(clamped) · new 4 는 그대로", () => {
  eq(clampEditable(1, calc(1, 5, 2)), { quantity: 3, clamped: true }, "③ 바닥");
  eq(clampEditable(4, calc(1, 5, 2)), { quantity: 4, clamped: false }, "③ 그대로");
  eq(clampEditable(0, calc(1, 5, 5)), { quantity: 0, clamped: false }, "③ 전부 안 나갔으면 0 까지");
});
Deno.test("④ matchCalcLine — variant + sku 하나 → 그것 · 같은 상품 둘 → 숫자 id 가 같은 것 · 둘 다 못 고르면 null · variant 없는 줄(custom)은 sku 만", () => {
  const cs = [calc(1, 5, 5), calc(2, 2, 2)];
  eq(matchCalcLine(live(1, 5, 5, 5), cs)?.id, CL(1), "④ 하나");
  const twice = [calc(1, 5, 5, "SKUX", 9), calc(2, 2, 2, "SKUX", 9)];
  eq(matchCalcLine(live(2, 2, 2, 2, "SKUX", 9), twice)?.id, CL(2), "④ 같은 상품 둘 → 숫자 id");
  eq(matchCalcLine({ ...live(7, 1, 1, 1, "SKUX", 9), id: "gid://shopify/LineItem/1" }, twice), null, "④ 숫자 id 도 안 맞으면 null");
  const custom: CalcLine = { id: CL(5), sku: "CUSTOM", quantity: 1, editableQuantity: 1, variant: null };
  eq(matchCalcLine({ id: LI(5), sku: "CUSTOM", quantity: 1, currentQuantity: 1, unfulfilledQuantity: 1, variant: null }, [custom, ...cs])?.id, CL(5), "④ custom 줄");
});
Deno.test("⑤ removedQty · isPaid — 원래 5 · 지금 3 → 2 · 지금이 더 크면 0 · PAID · PARTIALLY_PAID · PARTIALLY_REFUNDED 만 받음(소문자도) · PENDING · AUTHORIZED · REFUNDED · null 은 아니다", () => {
  eq(removedQty(5, 3), 2, "⑤ 2"); eq(removedQty("5", "5"), 0, "⑤ 0"); eq(removedQty(2, 3), 0, "⑤ 음수 없음");
  eq(["PAID", "PARTIALLY_PAID", "PARTIALLY_REFUNDED", "paid"].map(isPaid), [true, true, true, true], "⑤ 받음");
  eq(["PENDING", "AUTHORIZED", "REFUNDED", "VOIDED", "EXPIRED", null, undefined].map(isPaid), [false, false, false, false, false, false, false], "⑤ 안 받음");
});
