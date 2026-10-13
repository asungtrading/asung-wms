// deno test supabase/functions/shopify/shopify_edit_test.ts — Shopify · DB 무접촉 (ful-4b ~ 4b3 ① ~ ⑨ · _shared/shopify-edit.ts 의 순수 함수 · gql 주입 다리)
import { isPaid, matchCalcLine, NoChangeError, ORDER_EDIT_BEGIN_MUTATION, ORDER_EDIT_COMMIT_MUTATION, ORDER_EDIT_SET_QTY_MUTATION, planEditSteps, planOrderEdit, removedQty, runOrderEdit, runTrySet, setQuantityFor, trySetCandidates, verifySetResponse, type CalcLine, type DbLine, type GqlLike, type LiveLine, type StagedChange } from "../_shared/shopify-edit.ts";

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
Deno.test("③ setQuantityFor 가장자리(ful-4b3 · 고칠 수 있는 몫 기준) — 발송분 0 인 줄(editable = quantity 5 · to_remove 2 → 3 · change 2 · 값이 전과 같다) · to_remove > editable(quantity 5 · editable 2 · to_remove 3 → 0 · change 2 · clamped) · editable 0 → 0 · change 0", () => {
  eq(setQuantityFor(calc(1, 5, 5), 2), { quantity: 3, change: 2, clamped: false }, "③ 안 나간 줄은 전과 같은 값");
  eq(setQuantityFor(calc(1, 5, 2), 3), { quantity: 0, change: 2, clamped: true }, "③ 이미 나간 3 은 못 지운다 → 0 · clamped");
  eq(setQuantityFor(calc(1, 5, 2), 1), { quantity: 1, change: 1, clamped: false }, "③ editable 2 에서 1 지움 → 1");
  eq(setQuantityFor(calc(1, 5, 0), 1), { quantity: 0, change: 0, clamped: true }, "③ 다 나간 줄 → change 0(보내지 않는다)");
  eq(setQuantityFor(calc(1, 5, 5), 0), { quantity: 5, change: 0, clamped: false }, "③ to_remove 0 → change 0");
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

Deno.test("⑥ 실물 #1011(2026-10-13 try-set 세션 97462157495) — 줄 2 · 1 나감(live current 2 · unfulfilled 1) · can_ship 0 → to_remove 1 · calc {quantity 2 · editable 1} → 보낼 값 0 · change 1(0 을 보내니 editable 0 · delta 1 · 잔액 2.98 → 1.49) · 1 을 보내면(ful-4b · 4b1) staged 0 → commit 거절 · planEditSteps · verifySetResponse 실물 응답", () => {
  const plan = planOrderEdit([db(1, 2, 0)], [live(1, 2, 2, 1, "ANN01015")]);
  eq(plan.edits[0].to_remove, 1, "⑥ to_remove 1"); eq(plan.total_remove, 1, "⑥ 합 1");
  const c = calc(1, 2, 1, "ANN01015");                                                             // 실물: CalculatedLineItem 은 전체 2 를 quantity 로 · 고칠 수 있는 몫 1 을 editableQuantity 로 보인다
  eq(setQuantityFor(c, 1), { quantity: 0, change: 1, clamped: false }, "⑥ 보낼 값 0(첫 판 · 4b1 은 1 을 보내 변화 0 → commit 거절)");
  eq(setQuantityFor(c, 0), { quantity: 1, change: 0, clamped: false }, "⑥ to_remove 0 → change 0 → 그 줄은 setQuantity 를 안 보낸다");
  const steps = planEditSteps([c], plan, [live(1, 2, 2, 1, "ANN01015")]);
  eq(steps.map((st) => [st.line_gid, st.sku, st.to_remove, st.calc?.id, st.set]), [[LI(1), "ANN01015", 1, CL(1), { quantity: 0, change: 1, clamped: false }]], "⑥ planEditSteps(preview would_set 와 drain 이 같은 것)");
  const dec: StagedChange = { __typename: "OrderStagedChangeDecrementItem", delta: 1, restock: true, lineItem: { id: LI(1) } };
  eq(verifySetResponse({ line_gid: LI(1), quantity: 0, change: 1 }, { id: CL(1), quantity: 1, editableQuantity: 0, restocking: true, stagedChanges: [dec] }), { ok: true, why: null, restock: true }, "⑥ 실물 ⓐ 응답 → 맞음");
  const v = verifySetResponse({ line_gid: LI(1), quantity: 1, change: 1 }, { id: CL(1), quantity: 2, editableQuantity: 1, restocking: false, stagedChanges: [] });
  eq([v.ok, v.restock, v.why?.startsWith("no DecrementItem for this line")], [false, null, true], "⑥ 실물 ⓑ 응답(1 을 보냄 · staged 없음) → 어긋남");
  eq(verifySetResponse({ line_gid: LI(1), quantity: 0, change: 1 }, { id: CL(1), quantity: 1, editableQuantity: 1, stagedChanges: [dec] }).why?.startsWith("editableQuantity is not the sent 0"), true, "⑥ editableQuantity 가 보낸 값과 다르면 어긋남");
  eq(verifySetResponse({ line_gid: LI(1), quantity: 0, change: 1 }, { id: CL(1), quantity: 1, editableQuantity: 0, stagedChanges: [{ ...dec, delta: 2 }] }).why?.startsWith("delta is not the expected 1"), true, "⑥ delta 가 다르면 어긋남");
  eq(verifySetResponse({ line_gid: LI(1), quantity: 0, change: 1 }, { id: CL(1), quantity: 1, editableQuantity: 0, stagedChanges: [{ ...dec, lineItem: { id: LI(2) } }] }).ok, false, "⑥ 다른 줄의 DecrementItem 은 안 친다");
  eq(verifySetResponse({ line_gid: LI(1), quantity: 0, change: 1 }, { id: CL(1), quantity: 1, editableQuantity: 0, stagedChanges: [{ ...dec, restock: false }] }), { ok: true, why: null, restock: false }, "⑥ restock false 는 막지 않고 돌려준다");
  eq(verifySetResponse({ line_gid: LI(1), quantity: 0, change: 1 }, null).ok, false, "⑥ 응답에 줄이 없으면 어긋남");
  const e = new NoChangeError("x"); eq(e instanceof NoChangeError && e.name === "NoChangeError", true, "⑥ NoChangeError = 다시 시도하지 않는 error");
  eq(matchCalcLine(live(1, 2, 2, 1, "ANN01015"), [c])?.id, c.id, "⑥ 줄 하나 짝");
});

// ── ful-4b2 try-set — 가짜 gql: 호출된 쿼리 · 변수를 모은다 · begin 마다 새 CalculatedOrder id(또는 같은 id · 시험 ⑧) ──
type Call = { query: string; vars: Record<string, unknown> };
function fakeGql(calcLines: CalcLine[], opt: { sameSession?: boolean; stagedAtBegin?: number } = {}): { gql: GqlLike; calls: Call[] } {
  const calls: Call[] = []; let begins = 0;
  const gql: GqlLike = (query, vars) => {
    calls.push({ query, vars });
    const cost = { actual: 10 };
    if (query.includes("orderEditBegin")) {
      begins++;
      const id = "gid://shopify/CalculatedOrder/" + (opt.sameSession ? 777 : 1000 + begins);
      return Promise.resolve({ ok: true, status: 200, errors: null, raw: null, cost, data: { orderEditBegin: { calculatedOrder: { id, stagedChanges: { nodes: Array.from({ length: opt.stagedAtBegin ?? 0 }, () => ({ __typename: "OrderStagedChangeDecrementItem" })) }, lineItems: { nodes: calcLines } }, userErrors: [] } } });
    }
    if (query.includes("orderEditSetQuantity")) {
      const q = Number(vars.quantity);
      return Promise.resolve({ ok: true, status: 200, errors: null, raw: null, cost, data: { orderEditSetQuantity: { calculatedLineItem: { id: vars.lineItemId, quantity: q, editableQuantity: q, editableQuantityBeforeChanges: 1, restocking: true },
        calculatedOrder: { id: vars.id, subtotalLineItemsQuantity: q, stagedChanges: { nodes: q === 0 ? [{ __typename: "OrderStagedChangeDecrementItem", delta: 1, restock: true, lineItem: { id: LI(1) } }] : [] }, lineItems: { nodes: calcLines } }, userErrors: [] } } });
    }
    throw new Error("unexpected query: " + query.slice(0, 40));
  };
  return { gql, calls };
}
Deno.test("⑦ try-set 실물 #1011 — 후보 ⓐ editable 1 − 1 = 0 · ⓑ calc 2 − 1 = 1 · begin 둘(세션 따로 · id 다름 · contaminated 아님) · setQuantity 둘(restock true) · commit 문자열은 호출 목록에 없다 · 음수는 0 으로 자른다", async () => {
  const c = calc(1, 2, 1, "ANN01015");
  eq(trySetCandidates(c, 1), { a: { quantity: 0, clamped: false }, b: { quantity: 1, clamped: false } }, "⑦ 후보 둘");
  eq(trySetCandidates(c, 5), { a: { quantity: 0, clamped: true }, b: { quantity: 1, clamped: true } }, "⑦ 넘치면 자른다(ⓐ 0 · ⓑ 바닥 1)");
  const plan = planOrderEdit([db(1, 2, 0)], [live(1, 2, 2, 1, "ANN01015")]);
  const { gql, calls } = fakeGql([c]);
  const rs = await runTrySet(gql, "gid://shopify/Order/1011", plan, [live(1, 2, 2, 1, "ANN01015")], ["gid://shopify/CalculatedOrder/999"]);
  eq(rs.map((r) => [r.key, r.calculated_order_id, r.staged_at_begin, r.contaminated, r.sends.map((s) => s.quantity_sent)]), [["a", "gid://shopify/CalculatedOrder/1001", 0, false, [0]], ["b", "gid://shopify/CalculatedOrder/1002", 0, false, [1]]], "⑦ ⓐ 0 · ⓑ 1 · 세션 둘");
  eq(calls.map((x) => x.query === ORDER_EDIT_BEGIN_MUTATION ? "begin" : x.query === ORDER_EDIT_SET_QTY_MUTATION ? "set" : "?"), ["begin", "set", "begin", "set"], "⑦ 호출 순서 begin → set → begin → set");
  eq(calls.filter((x) => x.query.includes("orderEditCommit") || x.query === ORDER_EDIT_COMMIT_MUTATION).length, 0, "⑦ commit 은 부르지 않는다");
  eq(calls.filter((x) => x.query === ORDER_EDIT_SET_QTY_MUTATION).map((x) => [x.vars.id, x.vars.lineItemId, x.vars.quantity, x.vars.restock]), [["gid://shopify/CalculatedOrder/1001", CL(1), 0, true], ["gid://shopify/CalculatedOrder/1002", CL(1), 1, true]], "⑦ 보낸 변수(restock true · 판정 459)");
  eq(rs[0].sends[0].response?.staged_count, 1, "⑦ ⓐ 응답의 staged 수를 그대로"); eq(rs[1].sends[0].response?.staged_count, 0, "⑦ ⓑ 응답 staged 0");
  eq(rs[0].sends[0].response?.calculated_line_item, { id: CL(1), quantity: 0, editableQuantity: 0, editableQuantityBeforeChanges: 1, restocking: true }, "⑦ calculatedLineItem 원문");
  eq(rs.reduce((a, r) => a + r.cost, 0), 40, "⑦ cost 합");
});
Deno.test("⑧ try-set — 같은 세션이 돌아오면 contaminated(그대로 돌린다 · 숨기지 않는다) · staged 가 0 이 아니어도 contaminated · 발송분 0 이면(ⓐ = ⓑ) ⓑ 는 열지 않고 same_as_a · to_remove 0 이면 빈 결과", async () => {
  const c = calc(1, 2, 1, "ANN01015"), lv = [live(1, 2, 2, 1, "ANN01015")], plan = planOrderEdit([db(1, 2, 0)], lv);
  const same = fakeGql([c], { sameSession: true });
  const rs = await runTrySet(same.gql, "gid://shopify/Order/1011", plan, lv, ["gid://shopify/CalculatedOrder/777"]);
  eq(rs.map((r) => [r.key, r.contaminated, r.sends.map((s) => s.quantity_sent)]), [["a", true, [0]], ["b", true, [1]]], "⑧ 같은 id → 둘 다 contaminated · 그래도 보낸다");
  eq(rs[0].contaminated_reason?.startsWith("orderEditBegin returned a calculated order already seen"), true, "⑧ 이유");
  const staged = fakeGql([c], { stagedAtBegin: 1 });
  const rs2 = await runTrySet(staged.gql, "gid://shopify/Order/1011", plan, lv, []);
  eq(rs2.map((r) => [r.contaminated, r.contaminated_reason]), [[true, "stagedChanges not empty right after begin (1)"], [true, "stagedChanges not empty right after begin (1)"]], "⑧ staged ≠ 0 → contaminated");
  const full = calc(1, 2, 2, "ANN01015"), lvFull = [live(1, 2, 2, 2, "ANN01015")], planFull = planOrderEdit([db(1, 2, 0)], lvFull);   // 안 나간 줄: ⓐ = 2 − 2 = 0 · ⓑ = 2 − 2 = 0
  const f = fakeGql([full]);
  const rs3 = await runTrySet(f.gql, "gid://shopify/Order/1012", planFull, lvFull);
  eq(rs3.map((r) => [r.key, r.same_as_a ?? false, r.sends.map((s) => s.quantity_sent)]), [["a", false, [0]], ["b", true, []]], "⑧ ⓐ = ⓑ → ⓑ 는 same_as_a");
  eq(f.calls.filter((x) => x.query === ORDER_EDIT_BEGIN_MUTATION).length, 1, "⑧ begin 은 하나만");
  eq(await runTrySet(f.gql, "gid://shopify/Order/1013", planOrderEdit([db(1, 2, 2)], lvFull), lvFull), [], "⑧ to_remove 0 → 빈 결과 · 호출 없음");
  eq(f.calls.length, 2, "⑧ 위 줄에서 호출이 늘지 않았다");
});

// ── ful-4b3 runOrderEdit — 가짜 gql: begin → set(줄마다 staged 를 줄지 말지 · restock) → commit · 호출 목록으로 commit 횟수를 본다 ──
function fakeEditGql(calcLines: CalcLine[], staged: Record<string, boolean>, restock = true): { gql: GqlLike; calls: Call[] } {
  const calls: Call[] = [];
  const lineGid = (calcId: string) => "gid://shopify/LineItem/" + calcId.split("/").pop();
  const gql: GqlLike = (query, vars) => {
    calls.push({ query, vars });
    const cost = { actual: 10 };
    if (query === ORDER_EDIT_BEGIN_MUTATION) return Promise.resolve({ ok: true, status: 200, errors: null, raw: null, cost, data: { orderEditBegin: { calculatedOrder: { id: "gid://shopify/CalculatedOrder/5000", stagedChanges: { nodes: [] }, lineItems: { nodes: calcLines } }, userErrors: [] } } });
    if (query === ORDER_EDIT_SET_QTY_MUTATION) {
      const c = calcLines.find((x) => x.id === vars.lineItemId)!, q = Number(vars.quantity), gid = lineGid(c.id), delta = c.editableQuantity - q;
      const st = staged[gid] ? [{ __typename: "OrderStagedChangeDecrementItem", delta, restock, lineItem: { id: gid } }] : [];
      return Promise.resolve({ ok: true, status: 200, errors: null, raw: null, cost, data: { orderEditSetQuantity: { calculatedLineItem: { id: c.id, quantity: c.quantity - (staged[gid] ? delta : 0), editableQuantity: q, restocking: restock, stagedChanges: st }, calculatedOrder: { id: vars.id, stagedChanges: { nodes: st } }, userErrors: [] } } });
    }
    if (query === ORDER_EDIT_COMMIT_MUTATION) return Promise.resolve({ ok: true, status: 200, errors: null, raw: null, cost, data: { orderEditCommit: { order: { id: "gid://shopify/Order/1011", lineItems: { nodes: calcLines.map((c) => ({ id: lineGid(c.id), quantity: c.quantity, currentQuantity: c.quantity - 1 })) } }, userErrors: [] } } });
    throw new Error("unexpected query: " + query.slice(0, 40));
  };
  return { gql, calls };
}
const kinds = (calls: Call[]) => calls.map((x) => x.query === ORDER_EDIT_BEGIN_MUTATION ? "begin" : x.query === ORDER_EDIT_SET_QTY_MUTATION ? "set" : x.query === ORDER_EDIT_COMMIT_MUTATION ? "commit" : "?");
Deno.test("⑨ runOrderEdit 세 갈래 — 어긋남(staged 없음) → commit 0 · NoChangeError(보낸 값 · 응답 값 원문) / 맞음 → commit 1 · 돌려준 줄(currentQuantity 1 → removed_qty 1) · changed 1 / 줄 둘 중 하나만 어긋남 → commit 0 · restock false 는 notes · no_restock 에만", async () => {
  const lv = [live(1, 2, 2, 1, "ANN01015")], plan = planOrderEdit([db(1, 2, 0)], lv), c = calc(1, 2, 1, "ANN01015");
  // ⓐ 어긋남 — Shopify 가 변화를 안 쌓았다(ful-4b 첫 판의 모양)
  const bad = fakeEditGql([c], { [LI(1)]: false });
  let err: unknown = null;
  try { await runOrderEdit(bad.gql, "gid://shopify/Order/1011", plan, lv); } catch (e) { err = e; }
  eq(err instanceof NoChangeError, true, "⑨ 어긋남 → NoChangeError");
  eq(String((err as Error).message).includes("sent quantity 0 expecting −1") && String((err as Error).message).includes("no DecrementItem for this line") && String((err as Error).message).includes("NOT committed"), true, "⑨ 문장에 보낸 값 · 응답 값");
  eq(kinds(bad.calls), ["begin", "set"], "⑨ commit 0");
  // ⓑ 맞음 — 실물 모양 → commit 한 번 · 돌려준 줄
  const good = fakeEditGql([c], { [LI(1)]: true });
  const r = await runOrderEdit(good.gql, "gid://shopify/Order/1011", plan, lv);
  eq(kinds(good.calls), ["begin", "set", "commit"], "⑨ commit 1");
  eq(good.calls[1].vars, { id: "gid://shopify/CalculatedOrder/5000", lineItemId: CL(1), quantity: 0, restock: true }, "⑨ 보낸 변수(0 · restock true)");
  eq(good.calls[2].vars, { id: "gid://shopify/CalculatedOrder/5000", notify: false, note: "IMS: not shipping — backorder closed (quantity reduced by IMS)" }, "⑨ commit 변수(메일 없음 · staffNote)");
  eq([r.calc_id, r.changed, r.notes, r.no_restock, r.cost, r.after], ["gid://shopify/CalculatedOrder/5000", 1, [], [], 30, [{ id: LI(1), quantity: 2, currentQuantity: 1, unfulfilledQuantity: 0 }]], "⑨ 돌려준 것");
  eq(removedQty(2, r.after[0].currentQuantity), 1, "⑨ #1011 → removed_qty 1(짐작 · 실물로 본다)");
  // ⓒ 줄 둘 중 하나만 어긋남 → commit 하지 않는다
  const lv2 = [live(1, 2, 2, 1, "ANN01015"), live(2, 3, 3, 3)], plan2 = planOrderEdit([db(1, 2, 0), db(2, 3, 1)], lv2), c2 = calc(2, 3, 3);
  const half = fakeEditGql([c, c2], { [LI(1)]: true, [LI(2)]: false });
  err = null;
  try { await runOrderEdit(half.gql, "gid://shopify/Order/1011", plan2, lv2); } catch (e) { err = e; }
  eq(err instanceof NoChangeError && String((err as Error).message).includes("line " + LI(2).split("/").pop()), true, "⑨ 둘째 줄이 어긋남");
  eq(kinds(half.calls), ["begin", "set", "set"], "⑨ 하나라도 어긋나면 commit 0");
  // ⓓ restock false → 막지 않는다 · notes · no_restock
  const nr = fakeEditGql([c], { [LI(1)]: true }, false);
  const r2 = await runOrderEdit(nr.gql, "gid://shopify/Order/1011", plan, lv);
  eq(kinds(nr.calls), ["begin", "set", "commit"], "⑨ restock false 도 commit");
  eq([r2.changed, r2.no_restock.length, r2.notes[0]?.includes("will NOT restock 1")], [1, 1, true], "⑨ notes · no_restock");
  // ⓔ 전부 change 0(다 나간 줄) → set 0 · commit 0 · NoChangeError
  const none = fakeEditGql([calc(1, 2, 0, "ANN01015")], {});
  err = null;
  try { await runOrderEdit(none.gql, "gid://shopify/Order/1011", plan, lv); } catch (e) { err = e; }
  eq(err instanceof NoChangeError && kinds(none.calls).join(",") === "begin", true, "⑨ 바꿀 줄 0 → begin 만 · NoChangeError");
});
