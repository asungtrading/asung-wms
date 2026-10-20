// deno test supabase/functions/shopify/shopify_link_test.ts — Shopify · DB 무접촉 (link-1b · _shared/shopify-link.ts 의 순수 함수 · 판정 559 · Product/0)
import { chunk, errorMark, itemRow, parseBulkJsonl } from "../_shared/shopify-link.ts";
import { assertNoForbiddenKeys, buildProductSetInput, type Payload } from "../_shared/shopify-product.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const P = (i: number) => "p000000" + i + "-0000-0000-0000-000000000000";
const I = (i: number) => "i000000" + i + "-0000-0000-0000-000000000000";

// 손으로 만든 JSONL — 자식이 부모보다 먼저 오는 줄 · 빈 줄 · 깨진 줄 · 고아 변형 · 모르는 종류 · 미디어 둘(이미지 · 비디오) · SKU 공백 · null SKU · position 뒤집힘
const JSONL = [
  `{"id":"gid://shopify/ProductVariant/21","sku":" LKF1-BLU ","title":"Blue","position":2,"inventoryPolicy":"CONTINUE","selectedOptions":[{"name":"Color","value":"Blue"}],"inventoryItem":{"id":"gid://shopify/InventoryItem/21"},"__parentId":"gid://shopify/Product/2"}`,
  ``,
  `{"id":"gid://shopify/Product/1","handle":"lk-s1","title":"LK single 1","status":"ACTIVE","vendor":"LK","productType":"Hair","options":[{"name":"Title","values":["Default Title"]}]}`,
  `{"id":"gid://shopify/ProductVariant/11","sku":"LK-S1","title":"Default Title","position":1,"inventoryPolicy":"DENY","selectedOptions":[{"name":"Title","value":"Default Title"}],"inventoryItem":{"id":"gid://shopify/InventoryItem/11"},"__parentId":"gid://shopify/Product/1"}`,
  `{"id":"gid://shopify/MediaImage/101","mediaContentType":"IMAGE","alt":"front","image":{"url":"https://cdn.shopify.com/x/front.jpg"},"__parentId":"gid://shopify/Product/1"}`,
  `{"id":"gid://shopify/Video/102","mediaContentType":"VIDEO","__parentId":"gid://shopify/Product/1"}`,
  `{"id":"gid://shopify/Product/2","handle":"lkf1","title":"LK Family 1","status":"DRAFT","vendor":null,"productType":"","options":[{"name":"Color","values":["Red","Blue"]}]}`,
  `{"id":"gid://shopify/ProductVariant/20","sku":"LKF1-RED","title":"Red","position":1,"inventoryPolicy":"CONTINUE","selectedOptions":[{"name":"Color","value":"Red"}],"inventoryItem":{"id":"gid://shopify/InventoryItem/20"},"__parentId":"gid://shopify/Product/2"}`,
  `{"id":"gid://shopify/ProductVariant/22","sku":null,"title":"Green","position":3,"inventoryPolicy":"CONTINUE","selectedOptions":[],"inventoryItem":null,"__parentId":"gid://shopify/Product/2"}`,
  `{"id":"gid://shopify/ProductVariant/99","sku":"ORPHAN","__parentId":"gid://shopify/Product/999"}`,
  `{not json`,
  `{"id":"gid://shopify/Collection/7","title":"x"}`,
  `{"id":"gid://shopify/ProductVariant/98","sku":"NOPARENT"}`,
].join("\n");

Deno.test("① parseBulkJsonl — 상품 2 · 변형은 __parentId 로 모이고 position 순 · 자식이 먼저 와도 붙는다 · SKU trim · null SKU → '' · inventoryItem null → null · 미디어 둘(이미지 url · 비디오 url null) · 고아 2 · 빈 1 · 깨진 1 · 모름 1", () => {
  const r = parseBulkJsonl(JSONL);
  eq(r.items.length, 2, "products");
  eq({ lines: r.lines, blank: r.blank, bad_json: r.bad_json, orphans: r.orphans, unknown: r.unknown }, { lines: 13, blank: 1, bad_json: 1, orphans: 2, unknown: 1 }, "counts");
  const s1 = r.items.find((i) => i.shopify_product_gid === "gid://shopify/Product/1")!;
  eq({ handle: s1.handle, title: s1.title, status: s1.status, vendor: s1.vendor, product_type: s1.product_type, options: s1.options }, { handle: "lk-s1", title: "LK single 1", status: "ACTIVE", vendor: "LK", product_type: "Hair", options: [{ name: "Title", values: ["Default Title"] }] }, "s1 head");
  eq(s1.variants, [{ sku: "LK-S1", variant_gid: "gid://shopify/ProductVariant/11", inventory_item_gid: "gid://shopify/InventoryItem/11", title: "Default Title", option_values: [{ name: "Title", value: "Default Title" }], inventory_policy: "DENY", position: 1 }], "s1 variants");
  eq(s1.media, [{ gid: "gid://shopify/MediaImage/101", url: "https://cdn.shopify.com/x/front.jpg", alt: "front", kind: "IMAGE" }, { gid: "gid://shopify/Video/102", url: null, alt: null, kind: "VIDEO" }], "s1 media");
  const f1 = r.items.find((i) => i.shopify_product_gid === "gid://shopify/Product/2")!;
  eq({ status: f1.status, vendor: f1.vendor, product_type: f1.product_type }, { status: "DRAFT", vendor: null, product_type: "" }, "f1 head");
  eq(f1.variants.map((v) => [v.sku, v.position, v.inventory_item_gid]), [["LKF1-RED", 1, "gid://shopify/InventoryItem/20"], ["LKF1-BLU", 2, "gid://shopify/InventoryItem/21"], ["", 3, null]], "f1 variants ordered by position · trimmed · null sku → '' · null inventoryItem");
  eq(f1.media, [], "f1 media none");
  const row = itemRow("r1", s1) as Record<string, unknown>;
  eq(Object.keys(row), ["run_id", "shopify_product_gid", "handle", "title", "status", "vendor", "product_type", "options", "variants", "media"], "row keys = shop_link_item 원자료 칸");
  eq(parseBulkJsonl("").items, [], "empty text");
  eq(chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]], "chunk");
});

Deno.test("② errorMark — sp 없음 → null(upsert 안 함 · Product/0 금지) · Product/0 자리표시 → null · 있으면 error 표시만(gid 없음)", () => {
  eq(errorMark(null, "boom"), null, "no sp");
  eq(errorMark(undefined, "boom"), null, "undefined sp");
  eq(errorMark({ id: "x", shopify_product_gid: "gid://shopify/Product/0" }, "boom"), null, "placeholder");
  const m = errorMark({ id: "x", shopify_product_gid: "gid://shopify/Product/9" }, "Shopify refused: " + "y".repeat(500));
  eq(m && Object.keys(m), ["last_status", "last_error"], "keys — no gid");
  eq(m!.last_status, "error", "status"); eq(m!.last_error.length, 400, "cut 400");
});

const single: Payload = {
  kind: "product", store_code: "test", family_id: null, product_id: P(7), title: "No image", description_html: null, vendor: "LK", product_type: null, tags: [], send_tags: false, status: "ACTIVE", active_variants: 1, options: [],
  variants: [{ product_id: P(7), sku: "LK-N1", name: "n1", barcode: null, price: 3, compare_at_price: null, option_values: [], inventory_policy: "CONTINUE", is_active: true, sellable: true, image_id: null, weight: null, hs_code: null, country_code: null }],
  files: [], listing_on: true, blocks: [], hash: "h0",
};
Deno.test("③ 판정 559 — IMS 사진 0 장이면 input 에 files 키가 없고 변형에도 file 이 없다 · forbidden 0 · fileCount 0 · 사진 1 장이면 지금처럼 files + 변형 file", () => {
  const b0 = buildProductSetInput(single, { baseUrl: "https://x.supabase.co", productGid: "gid://shopify/Product/5", variantGidBySku: { "LK-N1": "gid://shopify/ProductVariant/5" }, mediaGidByImage: {}, cleanedHtml: "" });
  const inp0 = b0.input as Record<string, unknown>;
  eq("files" in inp0, false, "no files key (559)");
  eq("file" in (inp0.variants as Array<Record<string, unknown>>)[0], false, "no variant file");
  eq(b0.fileCount, 0, "fileCount 0"); eq(assertNoForbiddenKeys(inp0), [], "forbidden none");
  eq(b0.identifier, { id: "gid://shopify/Product/5" }, "identifier kept");
  const withImg: Payload = { ...single, files: [{ product_image_id: I(7), image_path: P(7) + "/" + I(7) + ".jpg", url: null, alt: "n1", product_id: P(7) }], variants: [{ ...single.variants[0], image_id: I(7) }] };
  const b1 = buildProductSetInput(withImg, { baseUrl: "https://x.supabase.co", productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "" });
  const inp1 = b1.input as Record<string, unknown>;
  eq((inp1.files as unknown[]).length, 1, "files 1"); eq("file" in (inp1.variants as Array<Record<string, unknown>>)[0], true, "variant file"); eq(b1.fileCount, 1, "fileCount 1");
});
