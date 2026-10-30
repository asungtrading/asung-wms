// deno test supabase/functions/shopify/shopify_order_test.ts — Shopify · DB 무접촉 (ord-1b ① ~ ⑥ · _shared/shopify-order.ts 의 순수 함수)
import { beforeCut, cutPick, hasImportTag, IMPORT_TAG, ORDERS_SINCE_QUERY, drainNext, drainStop, findStoreByDomain, gidInFilter, hmacBase64, isOrderTopic, maxUpdatedAt, missingSubscriptions, ORDER_TOPICS, orderGidFromWebhook, orderRef, ORDERS_DRAIN_MS, POLL_FIRST_WINDOW_MS, POLL_OVERLAP_MS, pollPick, pollQuery, pollSince, redactionReport, sweepPick, timingSafeEqual, verifyWebhookHmac, webhookHead, webhookUri } from "../_shared/shopify-order.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const enc = new TextEncoder();

Deno.test("① HMAC — 맞음 · 몸 한 글자 바뀜 · 헤더 바뀜 · 헤더 없음 · 비밀 없음 · 길이 다른 비교는 false · base64 모양", async () => {
  const secret = "shpss_test_secret_0123456789";
  const body = enc.encode('{"id":820982911946154508,"admin_graphql_api_id":"gid://shopify/Order/820982911946154508","name":"#1001"}');
  const mac = await hmacBase64(secret, body);
  eq(/^[A-Za-z0-9+/]{43}=$/.test(mac), true, "base64 of 32 bytes: " + mac);
  eq(await verifyWebhookHmac(secret, body, mac), true, "correct header passes");
  eq(await verifyWebhookHmac(secret, body, " " + mac + "\n"), true, "header whitespace is trimmed");
  const bytes2 = new Uint8Array(body); bytes2[10] = bytes2[10] === 48 ? 49 : 48;
  eq(await verifyWebhookHmac(secret, bytes2, mac), false, "one byte of the body changed");
  eq(await verifyWebhookHmac(secret, body, mac.slice(0, -2) + (mac.endsWith("A=") ? "B=" : "A=")), false, "header changed");
  eq(await verifyWebhookHmac(secret, body, null), false, "no header");
  eq(await verifyWebhookHmac("", body, mac), false, "no secret");
  eq(await verifyWebhookHmac("other-secret", body, mac), false, "other secret");
  eq(timingSafeEqual("abc", "abcd"), false, "length differs"); eq(timingSafeEqual("abc", "abc"), true, "same"); eq(timingSafeEqual("abc", "abd"), false, "differs");
});

Deno.test("② 웹훅 머리 · 몸 — 헤더 셋(topic · domain · webhook id) · 주제 거르기 · REST 몸에서 GID(admin_graphql_api_id 우선 · 숫자 id) · 스토어는 도메인으로(대소문자 무시)", () => {
  const h = new Headers({ "X-Shopify-Topic": "orders/create", "X-Shopify-Shop-Domain": "Asung-IMS-Test.myshopify.com", "X-Shopify-Webhook-Id": "wh-1", "X-Shopify-Event-Id": "ev-1", "X-Shopify-API-Version": "2026-10" });
  eq(webhookHead(h), { topic: "orders/create", domain: "asung-ims-test.myshopify.com", webhookId: "wh-1", eventId: "ev-1", apiVersion: "2026-10" }, "head");
  eq(webhookHead(new Headers({ "Authorization": "Bearer x" })), null, "no topic header → not a webhook");
  eq(["orders/create", "orders/updated", "orders/cancelled", "orders/paid", "products/update"].map(isOrderTopic), [true, true, true, false, false], "order topics");
  eq(orderGidFromWebhook({ id: 820982911946154508, admin_graphql_api_id: "gid://shopify/Order/820982911946154508" }), "gid://shopify/Order/820982911946154508", "gid from admin_graphql_api_id");
  eq(orderGidFromWebhook({ id: "123" }), "gid://shopify/Order/123", "numeric id");
  eq(orderGidFromWebhook({ admin_graphql_api_id: "gid://shopify/Product/1" }), null, "wrong gid kind and no id");
  eq(orderGidFromWebhook(null), null, "no body");
  const stores = [{ id: "a", shop_domain: "asung-ims-test.myshopify.com", is_active: true }, { id: "b", shop_domain: "other.myshopify.com", is_active: false }];
  eq(findStoreByDomain(stores, "ASUNG-IMS-TEST.myshopify.com ")?.id, "a", "store by domain"); eq(findStoreByDomain(stores, "nope.myshopify.com"), null, "unknown");
});

Deno.test("③ 구독 — 있는 주제는 빼고 · uri 가 다르면 없는 것으로 · 끝 슬래시 무시 · 주소 모양", () => {
  const uri = webhookUri("https://fazgmyvzzhqybtvtktyg.supabase.co/");
  eq(uri, "https://fazgmyvzzhqybtvtktyg.supabase.co/functions/v1/shopify", "uri");
  eq(missingSubscriptions([], uri), [...ORDER_TOPICS], "nothing yet → all three");
  eq(missingSubscriptions([{ id: "1", topic: "ORDERS_CREATE", uri: uri + "/" }, { id: "2", topic: "ORDERS_UPDATED", uri: "https://elsewhere.example/hook" }], uri), ["ORDERS_UPDATED", "ORDERS_CANCELLED"], "create present (trailing slash) · updated elsewhere");
});

Deno.test("④ 오더 찾기 · 가림 보고 — GID · 숫자 · 이름(#1001 · AS-6950) · 빈 글 · customer/email/주소 null · not approved 글", () => {
  eq(orderRef("gid://shopify/Order/5"), { gid: "gid://shopify/Order/5" }, "gid"); eq(orderRef(" 77 "), { gid: "gid://shopify/Order/77" }, "numeric");
  eq(orderRef("#1001"), { query: 'name:"#1001"' }, "name"); eq(orderRef("AS-6950"), { query: 'name:"AS-6950"' }, "name with dash"); eq(orderRef("  "), null, "blank");
  eq(redactionReport({ customer: null, email: null, shippingAddress: { city: "x" } }, [{ message: "This app is not approved to access the Customer object. See https://… for more details." }]), { customer_null: true, email_null: true, shipping_null: false, not_approved: true }, "redacted");
  eq(redactionReport({ customer: { id: "c" }, email: "a@b", shippingAddress: {} }, null), { customer_null: false, email_null: false, shipping_null: false, not_approved: false }, "full");
});

Deno.test("⑤ 주기 확인 — 기준 시각(마지막 − 5 분 · 없으면 하루 전) · 쿼리 글 · 본 것 중 최댓값", () => {
  const now = Date.parse("2026-10-10T20:00:00Z");
  eq(pollSince("2026-10-10T19:30:00.000Z", now), new Date(Date.parse("2026-10-10T19:30:00Z") - POLL_OVERLAP_MS).toISOString(), "last − overlap");
  eq(pollSince(null, now), new Date(now - POLL_FIRST_WINDOW_MS).toISOString(), "first run → a day back");
  eq(pollQuery("2026-10-10T19:25:00.000Z"), "updated_at:>'2026-10-10T19:25:00.000Z'", "query");
  eq(maxUpdatedAt([{ updatedAt: "2026-10-10T19:40:00Z" }, { updatedAt: "2026-10-10T19:50:00Z" }, { updatedAt: null }], "2026-10-10T19:45:00Z"), "2026-10-10T19:50:00Z", "max");
  eq(maxUpdatedAt([], null), null, "none");
});

Deno.test("⑥ drain — ingest status received 만 process · needs_review · created · cancelled · error 는 멈춤 · 시간 한도", () => {
  eq(["received", "needs_review", "created", "cancelled", "error", undefined].map((s) => drainNext({ status: s })), ["process", "stop", "stop", "stop", "stop", "stop"], "next step");
  eq(drainStop(ORDERS_DRAIN_MS - 1), null, "under"); eq(drainStop(ORDERS_DRAIN_MS), "time limit (40 s)", "at limit");
});

Deno.test("⑦ ord-1b2 sweep — 받은 일 줄 없는 received 만 줍는다 · 열린 받은 일 줄이 있는 오더 · 이번 회차에 다룬 오더는 뺀다 · 순서 그대로 · 비면 빈 것 · 시간 한도가 지났으면 줍지 않는다", () => {
  const recv = [{ id: "a", shopify_order_gid: "gid://shopify/Order/1" }, { id: "b", shopify_order_gid: "gid://shopify/Order/2" }, { id: "c", shopify_order_gid: "gid://shopify/Order/3" }, { id: "d", shopify_order_gid: "gid://shopify/Order/4" }];
  eq(sweepPick(recv, new Set(["gid://shopify/Order/2"]), new Set(["gid://shopify/Order/3"])).map((o) => o.id), ["a", "d"], "open inbox row (2) and just-handled (3) are skipped");
  eq(sweepPick(recv, new Set(), new Set()).map((o) => o.id), ["a", "b", "c", "d"], "nothing to skip → all, in order");
  eq(sweepPick([], new Set(["gid://shopify/Order/1"]), new Set()), [], "no received → none");
  const picked = sweepPick(recv, new Set(), new Set());
  let processed = 0, stopped: string | null = null;
  for (const _o of picked) { stopped = drainStop(ORDERS_DRAIN_MS + 5); if (stopped) break; processed++; }
  eq([processed, stopped], [0, "time limit (40 s)"], "time limit reached before the sweep → nothing processed");
});

Deno.test("⑧ ord-1b3 주기 확인 — 같은 updatedAt 건너뜀('Z' vs '+00:00' 같은 시각) · 더 새것 줍기 · 오래된 것 건너뜀 · 모르는 GID 줍기 · 저장된 시각 없음 줍기 · 못 읽는 시각 줍기 · 셈 · in 필터 모양", () => {
  const nodes = [
    { id: "gid://shopify/Order/1", updatedAt: "2026-10-11T00:58:43Z" },          // 같음(저장 +00:00)
    { id: "gid://shopify/Order/2", updatedAt: "2026-10-11T01:10:00Z" },          // 더 새것
    { id: "gid://shopify/Order/3", updatedAt: "2026-10-11T00:50:00Z" },          // 더 오래된 것(저장이 더 새것)
    { id: "gid://shopify/Order/4", updatedAt: "2026-10-11T01:00:00Z" },          // 모르는 GID
    { id: "gid://shopify/Order/5", updatedAt: "2026-10-11T01:00:00Z" },          // 저장된 시각 없음
    { id: "gid://shopify/Order/6", updatedAt: "not-a-date" },                     // 못 읽는 시각
  ];
  const known = [
    { shopify_order_gid: "gid://shopify/Order/1", shopify_updated_at: "2026-10-11T00:58:43+00:00" },
    { shopify_order_gid: "gid://shopify/Order/2", shopify_updated_at: "2026-10-11T00:56:31+00:00" },
    { shopify_order_gid: "gid://shopify/Order/3", shopify_updated_at: "2026-10-11T00:55:00+00:00" },
    { shopify_order_gid: "gid://shopify/Order/5", shopify_updated_at: null },
    { shopify_order_gid: "gid://shopify/Order/6", shopify_updated_at: "2026-10-11T00:55:00+00:00" },
  ];
  const p = pollPick(nodes, known);
  eq(p.add.map((n) => n.id.split("/").pop()), ["2", "4", "5", "6"], "newer · unknown · no stored time · unparseable are picked");
  eq(p.same.map((n) => n.id.split("/").pop()), ["1", "3"], "same and older are skipped");
  eq([p.add.length, p.same.length], [4, 2], "counts");
  eq(pollPick([], known), { add: [], same: [] }, "empty page");
  eq(pollPick(nodes.slice(0, 1), []), { add: nodes.slice(0, 1), same: [] }, "nothing known → pick");
  eq(gidInFilter(["gid://shopify/Order/1", "gid://shopify/Order/2"]), 'in.("gid://shopify/Order/1","gid://shopify/Order/2")', "PostgREST in filter");
  eq(decodeURIComponent(encodeURIComponent(gidInFilter(["gid://shopify/Order/1"]))), 'in.("gid://shopify/Order/1")', "round-trips through encodeURIComponent");
});

Deno.test("⑨ shop-cut-1 — 태그 낱말 하나 · 컷 앞 판정 · cutPick(모르는 · 컷 앞 · 태그 없음만 거른다 · 컷 없으면 전부 keep) · poll 쿼리에 createdAt tags", () => {
  eq(IMPORT_TAG, "ims-import", "tag name");
  eq([hasImportTag(["wholesale", "ims-import"]), hasImportTag([" IMS-Import "]), hasImportTag(["ims-importx"]), hasImportTag(["ims-import-x"]), hasImportTag("retail, IMS-IMPORT ,x"), hasImportTag("ims-importx,x"), hasImportTag([]), hasImportTag(null), hasImportTag(undefined), hasImportTag(5)],
     [true, true, false, false, true, false, false, false, false, false], "tag matching: whole word · trim · case · array or comma string");
  const cut = "2026-10-30T22:00:00Z";
  eq([beforeCut("2026-10-29T20:00:00Z", cut), beforeCut("2026-10-30T22:00:00Z", cut), beforeCut("2026-10-30T23:00:00Z", cut), beforeCut(null, cut), beforeCut("2026-10-29T20:00:00Z", null), beforeCut("garbage", cut), beforeCut("2026-10-29T20:00:00+00:00", "2026-10-30T22:00:00+00:00")],
     [true, false, false, false, false, false, true], "before cut: strict < · after → false · unparseable or missing → false (DB decides) · PostgREST +00:00 shape");
  const nodes = [
    { id: "gid://shopify/Order/1", name: "#1001", createdAt: "2026-10-29T20:00:00Z", tags: [] },                       // unknown · before · no tag → cut
    { id: "gid://shopify/Order/2", name: "#1002", createdAt: "2026-10-29T20:00:00Z", tags: ["IMS-Import"] },           // tagged → keep
    { id: "gid://shopify/Order/3", name: "#1003", createdAt: "2026-10-30T23:00:00Z", tags: [] },                       // after → keep
    { id: "gid://shopify/Order/4", name: "#1004", createdAt: "2026-10-29T20:00:00Z", tags: [] },                       // known (already in IMS) → keep
    { id: "gid://shopify/Order/5", name: "#1005", createdAt: null, tags: [] },                                         // no createdAt → keep
  ];
  const known = [{ shopify_order_gid: "gid://shopify/Order/4", shopify_updated_at: "2026-10-29T21:00:00+00:00" }];
  const p = cutPick(nodes, known, cut);
  eq(p.cut.map((n) => n.name), ["#1001"], "only the unknown · before-cut · untagged order is cut");
  eq(p.keep.map((n) => n.name), ["#1002", "#1003", "#1004", "#1005"], "the rest are kept in page order");
  eq(cutPick(nodes, known, null).cut.length, 0, "no cut time → gate off");
  eq(cutPick(nodes, known, "not a date").cut.length, 0, "unreadable cut time → gate off");
  eq(cutPick([], known, cut), { keep: [], cut: [] }, "empty page");
  eq(/nodes \{ id name createdAt updatedAt cancelledAt displayFinancialStatus test tags \}/.test(ORDERS_SINCE_QUERY), true, "poll query carries createdAt and tags");
});
