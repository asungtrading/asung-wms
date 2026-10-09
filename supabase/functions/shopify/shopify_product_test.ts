// deno test supabase/functions/shopify/shopify_product_test.ts — Shopify · DB 무접촉 (shop-2b ① ~ ④ · _shared/shopify-product.ts · shopify-clean.ts 의 순수 함수)
import { assertNoForbiddenKeys, buildProductSetInput, hsDigits, imageUrl, matchMedia, mediaNodes, PRODUCT_MEDIA_QUERY, unknownMedia, userErrorsSentence, type MediaNode, type Payload } from "../_shared/shopify-product.ts";
import { CLEAN_CONFIG, cleanHtml, FORBIDDEN_AFTER_CLEAN, forbiddenAfterClean, iframeHost, rulesClean } from "../_shared/shopify-clean.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const BASE = "https://fazgmyvzzhqybtvtktyg.supabase.co";
const P = (i: number) => "p000000" + i + "-0000-0000-0000-000000000000";
const I = (i: number) => "i000000" + i + "-0000-0000-0000-000000000000";
const sizes = ['Small (1/2" Diameter)', 'Medium (3/4" Diameter)', 'Large (7/8" Diameter)', 'X-Large (1 1/8" Diameter)', 'Jumbo (1 1/2" Diameter)'];
const colors = ["Blue", "Yellow", "Green", "Pink", "Orange", "Black", "Black", "Black", "Black", "Black"];
const fam: Payload = {
  kind: "family", store_code: "test", family_id: "f0000000-0000-0000-0000-000000000000", product_id: null, title: "ANNIE Snap-On Rollers", description_html: "<p>x</p>", vendor: "Annie", product_type: "Beauty Tools & Salon Supplies",
  tags: ["Roller"], send_tags: false, status: "ACTIVE", active_variants: 9, options: [{ name: "Color", values: ["Blue", "Yellow", "Green", "Pink", "Orange", "Black"] }, { name: "Size", values: sizes }],
  variants: Array.from({ length: 10 }, (_, i) => ({ product_id: P(i), sku: "ANN010" + String(i + 1).padStart(2, "0"), name: "v" + i, barcode: "70537201001" + i, price: 1.49, compare_at_price: 1.49,
    option_values: [{ name: "Color", value: colors[i] }, { name: "Size", value: sizes[i % 5] }], inventory_policy: i === 3 ? "DENY" : "CONTINUE", is_active: i !== 3, sellable: true, image_id: I(i), weight: { value: 0.039, unit: "KILOGRAMS" }, hs_code: null, country_code: null })),
  files: Array.from({ length: 10 }, (_, i) => ({ product_image_id: I(i), image_path: P(i) + "/" + I(i) + ".jpg", url: null, alt: "v" + i, product_id: P(i) })),
  listing_on: true, blocks: [], hash: "h1",
};
const single: Payload = {
  kind: "product", store_code: "test", family_id: null, product_id: P(7), title: "ANNIE PrimeX Premium Barber Cape - Chain", description_html: null, vendor: "Annie", product_type: "Capes", tags: [], send_tags: true, status: "ACTIVE", active_variants: 1, options: [],
  variants: [{ product_id: P(7), sku: "ANN03907", name: "cape", barcode: "705372039077", price: "12.4900000", compare_at_price: null, option_values: [], inventory_policy: "CONTINUE", is_active: true, sellable: true, image_id: I(7), weight: { value: 323, unit: "GRAMS" }, hs_code: "9615.11", country_code: "CN" }],
  files: [{ product_image_id: I(7), image_path: P(7) + "/" + I(7) + ".png", url: null, alt: "cape", product_id: P(7) }], listing_on: true, blocks: [], hash: "h2",
};

Deno.test("① family input — 10 variants · 2 options · Compare-at same value sent · DENY kept · tags omitted (send_tags false) · weight KILOGRAMS · files 10 with REPLACE · variant file = files entry · new product → identifier null", () => {
  const b = buildProductSetInput(fam, { baseUrl: BASE, productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "<p>clean</p>" });
  const inp = b.input as any;
  eq(b.identifier, null, "identifier");
  eq(inp.variants.length, 10, "variants");
  eq(inp.productOptions, [{ name: "Color", values: ["Blue", "Yellow", "Green", "Pink", "Orange", "Black"].map((n) => ({ name: n })) }, { name: "Size", values: sizes.map((n) => ({ name: n })) }], "options");
  eq(inp.variants[0].price, "1.49", "price"); eq(inp.variants[0].compareAtPrice, "1.49", "compare same value sent (408)");
  eq(inp.variants[3].inventoryPolicy, "DENY", "member off → DENY (406)"); eq(inp.variants[0].inventoryPolicy, "CONTINUE", "407");
  eq("tags" in inp, false, "tags omitted (410)"); eq(inp.status, "ACTIVE", "status"); eq(inp.descriptionHtml, "<p>clean</p>", "cleaned html used"); eq(inp.vendor, "Annie", "vendor"); eq(inp.productType, "Beauty Tools & Salon Supplies", "type");
  eq(inp.variants[0].inventoryItem, { tracked: true, measurement: { weight: { value: 0.039, unit: "KILOGRAMS" } } }, "inventoryItem");
  eq(inp.variants[0].optionValues, [{ optionName: "Color", name: "Blue" }, { optionName: "Size", name: sizes[0] }], "optionValues");
  eq(inp.files.length, 10, "files"); eq(inp.files[0], { originalSource: imageUrl(BASE, fam.files[0].image_path), filename: I(0) + ".jpg", contentType: "IMAGE", alt: "v0", duplicateResolutionMode: "REPLACE" }, "file ref by URL · REPLACE");
  eq(inp.variants[0].file, inp.files[0], "variant file is the same ref as in files");
  eq("id" in inp.variants[0], false, "no variant id on first push"); eq("inventoryQuantities" in inp.variants[0], false, "no quantities (③)");
});
Deno.test("② single — Title / Default Title · tags sent when send_tags · compare null omitted · GRAMS · hs digits · country · existing gids → identifier + variant id + media id", () => {
  const b = buildProductSetInput(single, { baseUrl: BASE, productGid: "gid://shopify/Product/9", variantGidBySku: { ANN03907: "gid://shopify/ProductVariant/77" }, mediaGidByImage: { [I(7)]: "gid://shopify/MediaImage/55" }, cleanedHtml: "" });
  const inp = b.input as any;
  eq(b.identifier, { id: "gid://shopify/Product/9" }, "identifier");
  eq(inp.productOptions, [{ name: "Title", values: [{ name: "Default Title" }] }], "single variant option");
  eq(inp.variants[0].optionValues, [{ optionName: "Title", name: "Default Title" }], "single optionValues");
  eq(inp.tags, [], "tags sent (empty) when send_tags"); eq("compareAtPrice" in inp.variants[0], false, "compare null omitted"); eq(inp.variants[0].price, "12.49", "price rounded");
  eq(inp.variants[0].inventoryItem, { tracked: true, measurement: { weight: { value: 323, unit: "GRAMS" } }, harmonizedSystemCode: "961511", countryCodeOfOrigin: "CN" }, "inventoryItem with hs · country");
  eq(inp.variants[0].id, "gid://shopify/ProductVariant/77", "variant id"); eq(inp.files, [{ id: "gid://shopify/MediaImage/55" }], "media by id"); eq(inp.variants[0].file, { id: "gid://shopify/MediaImage/55" }, "variant file by id");
  eq(hsDigits("9615.11"), "961511", "hs"); eq(hsDigits("12"), null, "hs too short"); eq(hsDigits(null), null, "hs null");
});
Deno.test("③ forbidden keys — none in both inputs · detector finds a planted one · matchMedia by filename stem · userErrors sentence", () => {
  eq(assertNoForbiddenKeys(buildProductSetInput(fam, { baseUrl: BASE, productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "" }).input), [], "family clean");
  eq(assertNoForbiddenKeys(buildProductSetInput(single, { baseUrl: BASE, productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "" }).input), [], "single clean");
  eq(assertNoForbiddenKeys({ title: "x", variants: [{ metafields: [] }], seo: {} }), ["input.variants[0].metafields", "input.seo"], "planted");
  eq(matchMedia([{ gid: "gid://shopify/MediaImage/1", url: "https://cdn.shopify.com/s/files/1/x/" + I(0) + "_abc.jpg" }, { gid: "gid://shopify/MediaImage/2", url: null }], fam.files.slice(0, 2)), { [I(0)]: "gid://shopify/MediaImage/1" }, "match one · unmatched left out");
  eq(userErrorsSentence([{ field: ["input", "variants", "0", "sku"], message: "SKU taken", code: "TAKEN" }, { message: "x" }]), "input.variants.0.sku: SKU taken (TAKEN) · x", "sentence");
});
Deno.test("④ rules clean — POWR iframe gone · YouTube kept · script · object gone · onclick · javascript: gone · style= kept · config strings match ims-desc.js", () => {
  const hosts = new Set(["www.youtube.com", "youtube.com", "www.youtube-nocookie.com", "www.facebook.com", "facebook.com"]);
  const r = rulesClean('<p style="color:red"><b>Hi</b></p><iframe src="https://www.youtube.com/embed/a" allowfullscreen></iframe><iframe src="https://www.powr.io/chat/u/x#platform=bigcommerce"></iframe><script>x()</script><a href="javascript:void(0)" onclick="y()">a</a><img src="https://i.ibb.co/a.jpg"><object data="x"><param name="a"></object><IFRAME SRC=//Youtube.com/embed/b></IFRAME>', hosts);
  eq(r.html, '<p style="color:red"><b>Hi</b></p><iframe src="https://www.youtube.com/embed/a" allowfullscreen></iframe><a>a</a><img src="https://i.ibb.co/a.jpg"><IFRAME SRC=//Youtube.com/embed/b></IFRAME>', "html");
  eq(r.removed.sort(), ["<object>", "<script>", "iframe (www.powr.io)", "javascript: link", "onclick="].sort(), "removed"); eq(r.engine, "rules", "engine");
  eq(iframeHost("https://WWW.Powr.io/x"), "www.powr.io", "host lower"); eq(iframeHost("not a url"), "", "no host"); eq(iframeHost("//youtube.com/e"), "youtube.com", "protocol-relative");
  eq(CLEAN_CONFIG.FORBID_TAGS, ["script", "style", "object", "embed", "form", "meta", "link", "base"], "FORBID_TAGS = ims-desc.js");
  eq(CLEAN_CONFIG.ADD_ATTR, ["allow", "allowfullscreen", "frameborder", "scrolling", "target"], "ADD_ATTR = ims-desc.js");
});
Deno.test("⑤ 안전장치(판정 412) — 규칙이 못 지우는 모양(링크 속성이 아닌 칸의 javascript:)은 판별이 잡는다 · 가짜 판별 → 문장 · 빈 배열 → null · cleanHtml 은 늘 rules", () => {
  const hosts = new Set(["www.youtube.com"]);
  const tricky = '<p>ok</p><a data-go="javascript:alert(1)">x</a>';
  const r = cleanHtml(tricky, hosts);
  eq(r.engine, "rules", "engine"); eq(r.html, tricky, "rules leave the non-link attribute (the DB detector catches it — ims_html_forbidden javascript_link)");
  const fakeDetector = (html: string) => (/=\s*["']?\s*javascript\s*:/i.test(html) ? ["javascript_link"] : []);
  eq(forbiddenAfterClean(fakeDetector(r.html)), FORBIDDEN_AFTER_CLEAN + ":javascript_link", "gate sentence");
  eq(forbiddenAfterClean(fakeDetector(cleanHtml('<p>ok</p><a href="javascript:alert(1)">x</a>', hosts).html)), null, "link javascript: is removed by the rules → gate passes");
  eq(forbiddenAfterClean([]), null, "empty"); eq(forbiddenAfterClean(null), null, "null"); eq(forbiddenAfterClean(["script", "iframe_host:www.powr.io"]), FORBIDDEN_AFTER_CLEAN + ":script,iframe_host:www.powr.io", "many");
});
Deno.test("⑥ 사진 짝(fix2) — 응답 media 가 처리 중(url 없음) → 0 · 직전 읽기 READY 10 → 10 · 그걸로 만든 input 의 files · 변형 file 이 전부 {id} · 사람이 올린 사진(줄기 없음) → unknown 1 · 처리 중 하나 → 그 사진만 originalSource", () => {
  const cdn = (stem: string) => "https://cdn.shopify.com/s/files/1/0770/0194/9367/files/" + stem + ".jpg?v=1760000000";
  const processing: MediaNode[] = fam.files.map((f, i) => ({ gid: "gid://shopify/MediaImage/" + (100 + i), status: "PROCESSING", url: null, alt: null }));
  eq(Object.keys(matchMedia(processing, fam.files, true)).length, 0, "processing → nothing (the real first push)");
  const ready: MediaNode[] = fam.files.map((f, i) => ({ gid: "gid://shopify/MediaImage/" + (100 + i), status: "READY", url: cdn(f.product_image_id), alt: "x" }));
  const matched = matchMedia(ready, fam.files, true);
  eq(Object.keys(matched).length, 10, "pre-read READY 10 → 10");
  const b = buildProductSetInput(fam, { baseUrl: BASE, productGid: "gid://shopify/Product/8836280582327", variantGidBySku: {}, mediaGidByImage: matched, cleanedHtml: "" });
  const inp = b.input as any;
  eq(inp.files.every((x: any) => typeof x.id === "string" && Object.keys(x).length === 1), true, "all files by id");
  eq(inp.variants.every((v: any) => typeof v.file?.id === "string"), true, "all variant files by id");
  const human: MediaNode[] = [...ready, { gid: "gid://shopify/MediaImage/999", status: "READY", url: cdn("photo-from-admin"), alt: null }];
  eq(unknownMedia(human, fam.files), 1, "one unknown (human-uploaded) → dropped by the files list (409)");
  eq(unknownMedia(processing, fam.files), 10, "processing nodes have no url → counted unknown only for reporting");
  const partial: MediaNode[] = ready.map((n, i) => (i === 4 ? { ...n, status: "PROCESSING", url: null } : n));
  const m2 = matchMedia(partial, fam.files, true);
  eq(Object.keys(m2).length, 9, "one still processing → 9");
  const b2 = buildProductSetInput(fam, { baseUrl: BASE, productGid: "gid://shopify/Product/1", variantGidBySku: {}, mediaGidByImage: m2, cleanedHtml: "" });
  const files2 = (b2.input as any).files;
  eq(files2.filter((x: any) => x.id).length, 9, "9 by id"); eq(files2[4].originalSource !== undefined && files2[4].duplicateResolutionMode === "REPLACE", true, "the processing one goes by URL + REPLACE");
  eq(mediaNodes({ id: "g", handle: null, status: "ACTIVE", media: { nodes: [{ id: "gid://shopify/MediaImage/1", status: "READY", image: { url: "u" } }] } }), [{ gid: "gid://shopify/MediaImage/1", alt: null, status: "READY", url: "u" }], "mediaNodes shape");
  eq(PRODUCT_MEDIA_QUERY.includes("media(first: 250)") && PRODUCT_MEDIA_QUERY.includes("status image { url }"), true, "query asks status + url");
});
