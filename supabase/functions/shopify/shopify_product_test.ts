// deno test supabase/functions/shopify/shopify_product_test.ts — Shopify · DB 무접촉 (shop-2b ① ~ ④ · shop-img-off-1 ⑧ · _shared/shopify-product.ts · shopify-clean.ts 의 순수 함수)
import { assertNoForbiddenKeys, buildProductSetInput, countryAlpha2, hsDigits, ISO_ALPHA3_TO_2, SHOPIFY_COUNTRY_CODES, imageStems, imageUrl, livePairs, matchMedia, pairBeforePush, skuStem, stemMatches, urlStem, mediaNodes, NEW_SHOP_PRODUCT_COLUMNS, newShopProductColumns, PRODUCT_MEDIA_QUERY, unknownMedia, userErrorsSentence, type MediaNode, type Payload } from "../_shared/shopify-product.ts";
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

Deno.test("① family input — 10 variants · 2 options · Compare-at same value sent · DENY kept · tags omitted (send_tags false) · weight KILOGRAMS · files 10 named by member SKU with APPEND_UUID · variant file = files entry · new product → identifier null", () => {
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
  eq(inp.files.length, 10, "files"); eq(inp.files[0], { originalSource: imageUrl(BASE, fam.files[0].image_path), filename: "ANN01001.jpg", contentType: "IMAGE", alt: "v0", duplicateResolutionMode: "APPEND_UUID" }, "file ref by URL · member SKU · APPEND_UUID");
  eq(inp.variants[0].file, inp.files[0], "variant file is the same ref as in files");
  eq("id" in inp.variants[0], false, "no variant id on first push"); eq("inventoryQuantities" in inp.variants[0], false, "no quantities (③)");
});
Deno.test("② single — Title / Default Title · tags omitted when send_tags but IMS tags 0(판정 1043) · compare null omitted · GRAMS · hs digits · country · existing gids → identifier + variant id + media id", () => {
  const b = buildProductSetInput(single, { baseUrl: BASE, productGid: "gid://shopify/Product/9", variantGidBySku: { ANN03907: "gid://shopify/ProductVariant/77" }, mediaGidByImage: { [I(7)]: "gid://shopify/MediaImage/55" }, cleanedHtml: "" });
  const inp = b.input as any;
  eq(b.identifier, { id: "gid://shopify/Product/9" }, "identifier");
  eq(inp.productOptions, [{ name: "Title", values: [{ name: "Default Title" }] }], "single variant option");
  eq(inp.variants[0].optionValues, [{ optionName: "Title", name: "Default Title" }], "single optionValues");
  eq("tags" in inp, false, "tags omitted when send_tags but IMS tags 0 (1043 · shop-new-1 — was: tags [] sent, which wiped Shopify tags)"); eq("compareAtPrice" in inp.variants[0], false, "compare null omitted"); eq(inp.variants[0].price, "12.49", "price rounded");
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
  eq(files2.filter((x: any) => x.id).length, 9, "9 by id"); eq(files2[4].originalSource !== undefined && files2[4].duplicateResolutionMode === "APPEND_UUID" && files2[4].filename === "ANN01005.jpg", true, "the processing one goes by URL + APPEND_UUID · SKU name");
  eq(mediaNodes({ id: "g", handle: null, status: "ACTIVE", media: { nodes: [{ id: "gid://shopify/MediaImage/1", status: "READY", image: { url: "u" } }] } }), [{ gid: "gid://shopify/MediaImage/1", alt: null, status: "READY", url: "u" }], "mediaNodes shape");
  eq(PRODUCT_MEDIA_QUERY.includes("media(first: 250)") && PRODUCT_MEDIA_QUERY.includes("status image { url }"), true, "query asks status + url");
});
Deno.test("⑦ 원산지(판정 884 · shop-coo-1) — 세 글자 → 두 글자 · Shopify enum 밖이면 칸 빼기 + cooDropped · 실측 11 코드 전부", () => {
  eq(countryAlpha2("USA"), "US", "USA"); eq(countryAlpha2("CHN"), "CN", "CHN"); eq(countryAlpha2("cn"), "CN", "lower"); eq(countryAlpha2(" CN "), "CN", "trim"); eq(countryAlpha2("CN"), "CN", "CN");
  eq(countryAlpha2("XYZ"), null, "unknown 3"); eq(countryAlpha2(""), null, "empty"); eq(countryAlpha2(null), null, "null"); eq(countryAlpha2("China"), null, "name not mapped (이견 ③)");
  eq(countryAlpha2("PRI"), null, "PRI → PR not in Shopify enum"); eq(countryAlpha2("PR"), null, "PR not in Shopify enum"); eq(countryAlpha2("XKX"), "XK", "Kosovo"); eq(countryAlpha2("ZZ"), null, "ZZ excluded"); eq(countryAlpha2("QQ"), null, "unknown 2");
  const real: Record<string, string> = { CHN: "CN", USA: "US", MEX: "MX", CZE: "CZ", THA: "TH", KOR: "KR", IDN: "ID", GHA: "GH", LUX: "LU", DOM: "DO", BRA: "BR" };   // 실측 2026-10-29 · 996 제품
  for (const [a3, a2] of Object.entries(real)) eq(countryAlpha2(a3), a2, "measured " + a3);
  eq(Object.keys(ISO_ALPHA3_TO_2).length, 249, "ISO 249"); eq(new Set(Object.values(ISO_ALPHA3_TO_2)).size, 249, "alpha-2 unique");
  eq(Object.values(ISO_ALPHA3_TO_2).filter((c) => !SHOPIFY_COUNTRY_CODES.has(c)).sort(), ["AQ", "AS", "FM", "GU", "MH", "MP", "PR", "PW", "VI"], "ISO not in Shopify");
  eq([...SHOPIFY_COUNTRY_CODES].filter((c) => !Object.values(ISO_ALPHA3_TO_2).includes(c)).sort(), ["AC", "AN", "TA", "XK"], "Shopify only (ZZ excluded)");
  const mk = (sku: string, cc: string | null) => ({ ...single.variants[0], sku, country_code: cc });
  const b = buildProductSetInput({ ...single, kind: "family", options: [], variants: [mk("A1", "USA"), mk("A2", "XYZ"), mk("A3", ""), mk("A4", null), mk("A5", "PRI")] }, { baseUrl: BASE, productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "" });
  const vs = (b.input as any).variants;
  eq(vs[0].inventoryItem.countryCodeOfOrigin, "US", "USA sent as US"); eq("countryCodeOfOrigin" in vs[1].inventoryItem, false, "XYZ omitted"); eq("countryCodeOfOrigin" in vs[2].inventoryItem, false, "empty omitted");
  eq("countryCodeOfOrigin" in vs[3].inventoryItem, false, "null omitted"); eq("countryCodeOfOrigin" in vs[4].inventoryItem, false, "PRI omitted"); eq(vs[1].inventoryItem.harmonizedSystemCode, "961511", "other fields kept");
  eq(b.cooDropped, [{ sku: "A2", code: "XYZ" }, { sku: "A5", code: "PRI" }], "cooDropped — empty · null are not drops");
  eq(buildProductSetInput(single, { baseUrl: BASE, productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "" }).cooDropped, [], "single CN — none dropped");
});

Deno.test("⑧ 판정 890(shop-img-off-1) — 꺼진 스토어 payload(DB 가 주는 꼴: files [] · image_id null · send_images false) → files 키 없음 · 변형 file 없음 · fileCount 0 · 나머지(title · variants · tags · status)는 그대로 · 안전띠: send_images false 인데 files 10 이 와도 안 보낸다 · send_images true · 없음(옛 payload)은 지금처럼", () => {
  const ctx = { baseUrl: BASE, productGid: "gid://shopify/Product/9", variantGidBySku: {}, mediaGidByImage: { [I(0)]: "gid://shopify/MediaImage/1" }, cleanedHtml: "<p>x</p>" };
  const off: Payload = { ...fam, send_images: false, files: [], variants: fam.variants.map((v) => ({ ...v, image_id: null })) };
  const b = buildProductSetInput(off, ctx); const inp = b.input as Record<string, unknown>;
  eq("files" in inp, false, "no files key (559 shape)"); eq((inp.variants as Array<Record<string, unknown>>).some((v) => "file" in v), false, "no variant file");
  eq(b.fileCount, 0, "fileCount 0"); eq(assertNoForbiddenKeys(inp), [], "forbidden none");
  eq([inp.title, (inp.variants as unknown[]).length, inp.status, inp.vendor, "tags" in inp], ["ANNIE Snap-On Rollers", 10, "ACTIVE", "Annie", false], "everything else as before");
  const belt: Payload = { ...fam, send_images: false };                                           // DB 가 사진을 줬어도(있을 수 없는 꼴) 안전띠가 뺀다
  const b2 = buildProductSetInput(belt, ctx); const inp2 = b2.input as Record<string, unknown>;
  eq("files" in inp2, false, "belt: no files key"); eq((inp2.variants as Array<Record<string, unknown>>).some((v) => "file" in v), false, "belt: no variant file"); eq(b2.fileCount, 0, "belt: fileCount 0");
  const on: Payload = { ...fam, send_images: true };
  const b3 = buildProductSetInput(on, ctx); eq((b3.input as any).files.length, 10, "on: files 10"); eq((b3.input as any).files[0], { id: "gid://shopify/MediaImage/1" }, "on: media by id kept"); eq(b3.fileCount, 10, "on: fileCount 10");
  const legacy = buildProductSetInput(fam, ctx); eq((legacy.input as any).files.length, 10, "no send_images key (old payload) → as before");
});

Deno.test("⑨ shop-new-1(판정 1042 · 1043) — IMS 가 만드는 상품(행 없음 · DB 가 send_images · send_tags true 로 줌 · identifier null): files · tags 가 나간다 / IMS 사진 0 → files 키 없음 / IMS 태그 0 → tags 키 없음(두 번째 안전띠) / 두 번째 보내기(identifier 있음 · 표식 true)에도 나간다 / 기존 link 상품(false · false)은 둘 다 안 나간다 / 덧씌운 기존 상품(사진만 · 태그만)은 그것만 나간다 / 새 행 세 칸", () => {
  const ctxNew = { baseUrl: BASE, productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "<p>x</p>" };
  const ctxOld = { ...ctxNew, productGid: "gid://shopify/Product/9", variantGidBySku: { ANN03907: "gid://shopify/ProductVariant/77" } };
  const made: Payload = { ...single, send_images: true, send_tags: true, tags: ["AOS", "ASS", "Conditioner"] };
  const b1 = buildProductSetInput(made, ctxNew); const i1 = b1.input as any;
  eq(b1.identifier, null, "made: identifier null (productSet creates)"); eq(i1.files.length, 1, "made: files 1"); eq(i1.variants[0].file, i1.files[0], "made: variant file"); eq(i1.tags, ["AOS", "ASS", "Conditioner"], "made: tags out (내부 표식 태그도 · 판정 426)");
  const noPhoto: Payload = { ...made, files: [], variants: made.variants.map((v) => ({ ...v, image_id: null })) };
  const b2 = buildProductSetInput(noPhoto, ctxNew); const i2 = b2.input as any;
  eq("files" in i2, false, "no photo: files key absent (559)"); eq("file" in i2.variants[0], false, "no photo: no variant file"); eq(i2.tags, ["AOS", "ASS", "Conditioner"], "no photo: tags still out");
  const noTag: Payload = { ...made, tags: [] };                                                  // DB 는 send_tags false 를 주지만(1043) true 로 와도 여기서 막는다
  const b3 = buildProductSetInput(noTag, ctxNew); const i3 = b3.input as any;
  eq("tags" in i3, false, "no tag: tags key absent even with send_tags true (belt)"); eq(i3.files.length, 1, "no tag: files still out");
  const second = buildProductSetInput(made, ctxOld); const i4 = second.input as any;
  eq(second.identifier, { id: "gid://shopify/Product/9" }, "second send: identifier"); eq(i4.files.length, 1, "second send: files out"); eq(i4.tags.length, 3, "second send: tags out"); eq(i4.variants[0].id, "gid://shopify/ProductVariant/77", "second send: variant id kept");
  const linked: Payload = { ...made, send_images: false, send_tags: false, files: [], variants: made.variants.map((v) => ({ ...v, image_id: null })) };   // 기존(잇기) 상품 · 스토어 스위치 꺼짐 · DB 가 주는 꼴
  const b5 = buildProductSetInput(linked, ctxOld); const i5 = b5.input as any;
  eq(["files" in i5, "tags" in i5, "file" in i5.variants[0]], [false, false, false], "linked: no files · no tags · no variant file");
  const ovrImg: Payload = { ...made, send_images: true, send_tags: false };                      // 사진만 덧씌움(asung ABE10612 꼴)
  const b6 = buildProductSetInput(ovrImg, ctxOld); const i6 = b6.input as any;
  eq([i6.files.length, "tags" in i6], [1, false], "override images only: files out · tags not");
  const ovrTag: Payload = { ...made, send_images: false, send_tags: true, files: [], variants: made.variants.map((v) => ({ ...v, image_id: null })) };   // 태그만 덧씌움
  const b7 = buildProductSetInput(ovrTag, ctxOld); const i7 = b7.input as any;
  eq(["files" in i7, i7.tags.length], [false, 3], "override tags only: tags out · files not");
  for (const b of [b1, b2, b3, second, b5, b6, b7]) eq(assertNoForbiddenKeys(b.input), [], "forbidden none");
  eq(newShopProductColumns(false), { origin: "ims", send_images: true, send_tags: true }, "no shop_product row → three columns on the first upsert");
  eq(newShopProductColumns(true), {}, "row exists → nothing (PATCH leaves the three columns alone)");
  eq(NEW_SHOP_PRODUCT_COLUMNS, { origin: "ims", send_images: true, send_tags: true }, "constant");
});

Deno.test("⑩ shop-img-name-1 — 파일 이름 = SKU · SKU_2 · SKU_3(payload 순서) · 패밀리는 구성원 SKU · png · webp 유지 · 못 쓰는 글자 → - · 비면 uuid · APPEND_UUID", () => {
  const files3 = ["a.jpg", "b.jpg", "c.jpg"].map((x, i) => ({ product_image_id: I(i), image_path: P(7) + "/" + I(i) + ".jpg", url: null, alt: "cape", product_id: P(7) }));
  const s3 = { ...single, files: files3, variants: single.variants.map((v) => ({ ...v, image_id: I(0) })) };
  const b3 = buildProductSetInput(s3, { baseUrl: BASE, productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "" }); const i3 = b3.input as any;
  eq(i3.files.map((f: any) => f.filename), ["ANN03907.jpg", "ANN03907_2.jpg", "ANN03907_3.jpg"], "single product 3 photos");
  eq(i3.files.every((f: any) => f.duplicateResolutionMode === "APPEND_UUID"), true, "never REPLACE");
  eq(i3.variants[0].file.filename, "ANN03907.jpg", "variant file = same name as its files entry");
  const fam4: Payload = { ...fam, variants: fam.variants.slice(0, 4), files: fam.files.slice(0, 4) };
  eq((buildProductSetInput(fam4, { baseUrl: BASE, productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "" }).input as any).files.map((f: any) => f.filename), ["ANN01001.jpg", "ANN01002.jpg", "ANN01003.jpg", "ANN01004.jpg"], "family 4 members 1 each → member SKU");
  const famMix: Payload = { ...fam, variants: fam.variants.slice(0, 2), files: [fam.files[1], { ...fam.files[0] }, { ...fam.files[0], product_image_id: I(8), image_path: P(0) + "/" + I(8) + ".jpg" }] };
  eq(Object.values(imageStems(famMix)), ["ANN01002", "ANN01001", "ANN01001_2"], "family: cover of another member first · numbering per SKU in payload order");
  eq(buildProductSetInput(single, { baseUrl: BASE, productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "" }).input.files, [{ originalSource: imageUrl(BASE, single.files[0].image_path), filename: "ANN03907.png", contentType: "IMAGE", alt: "cape", duplicateResolutionMode: "APPEND_UUID" }], "png kept");
  const webp = { ...single, files: [{ ...single.files[0], image_path: P(7) + "/" + I(7) + ".WEBP" }] };
  eq((buildProductSetInput(webp, { baseUrl: BASE, productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "" }).input as any).files[0].filename, "ANN03907.webp", "webp kept (lower-case ext)");
  eq(skuStem("ADA83721FAM - 004"), "ADA83721FAM-004", "space run → one -"); eq(skuStem("AB/CD\\EF"), "AB-CD-EF", "slashes"); eq(skuStem("  /X#Y/ "), "X-Y", "edges trimmed");
  eq(skuStem("ONO00140"), "ONO00140", "plain"); eq(skuStem("AB--CD"), "AB--CD", "clean SKU dashes untouched"); eq(skuStem("AB -/ CD"), "AB-CD", "dashes inside a bad run fold in"); eq(skuStem("A.B_c-1"), "A.B_c-1", "allowed kept"); eq(skuStem(" / # "), null, "empty → null"); eq(skuStem(null), null, "null");
  const bad = { ...single, variants: single.variants.map((v) => ({ ...v, sku: " / " })) };
  eq((buildProductSetInput(bad, { baseUrl: BASE, productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "" }).input as any).files[0].filename, I(7) + ".png", "unusable SKU → old uuid name");
  const orphan = { ...single, files: [{ ...single.files[0], product_id: P(9) }] };
  eq(Object.values(imageStems(orphan)), [I(7)], "image whose product is not among variants → uuid name");
  const spaced = { ...single, variants: single.variants.map((v) => ({ ...v, sku: "ADA83721FAM - 004" })) };
  eq((buildProductSetInput(spaced, { baseUrl: BASE, productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "" }).input as any).files[0].filename, "ADA83721FAM-004.png", "real odd SKU");
});
Deno.test("⑪ shop-img-name-1 짝 기준 — 정확히 SKU · SKU_n · 뒤 _<uuid> 허용 · 옛 uuid 줄기 계속 · 「포함」 금지 · 한 사진은 한 번만 · unknown", () => {
  const cdn = (stem: string, e = "jpg") => "https://cdn.shopify.com/s/files/1/0770/0194/9367/files/" + stem + "." + e + "?v=1762460000";
  const U = "1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d";
  const f0 = fam.files[0], st = { [f0.product_image_id]: "ANN01001" };
  eq(urlStem(cdn("ANN01001_2")), "ann01001_2", "urlStem: last segment · no query · no ext · lower");
  eq(urlStem(cdn("ADA83721FAM-004%20x", "png")), "ada83721fam-004 x", "decoded");
  eq(stemMatches(urlStem(cdn("ANN01001")), f0, "ANN01001"), true, "(b) exact");
  eq(stemMatches(urlStem(cdn("ann01001")), f0, "ANN01001"), true, "(b) case-insensitive");
  eq(stemMatches(urlStem(cdn("ANN01001_" + U)), f0, "ANN01001"), true, "(b) + _<uuid> (APPEND_UUID)");
  eq(stemMatches(urlStem(cdn("ANN01001_" + U.replace(/-/g, ""))), f0, "ANN01001"), true, "(b) + _<32 hex>");
  eq(stemMatches(urlStem(cdn("ANN01001_2")), f0, "ANN01001"), false, "ANN01001 must not match ANN01001_2 (no 'contains')");
  eq(stemMatches(urlStem(cdn("ANN01001_2_" + U)), f0, "ANN01001"), false, "nor ANN01001_2_<uuid>");
  eq(stemMatches(urlStem(cdn("ANN010011")), f0, "ANN01001"), false, "nor a longer SKU");
  eq(stemMatches(urlStem(cdn("x_ANN01001")), f0, "ANN01001"), false, "nor a prefix");
  eq(stemMatches(urlStem(cdn("ANN01001_abc")), f0, "ANN01001"), false, "nor a non-uuid tail");
  eq(stemMatches(urlStem(cdn("ANN01001_2")), f0, "ANN01001_2"), true, "(b) second photo");
  eq(stemMatches(urlStem(cdn(f0.product_image_id)), f0, "ANN01001"), true, "(c) old uuid stem still matches");
  eq(stemMatches(urlStem(cdn(f0.product_image_id + "_abc")), f0, "ANN01001"), true, "(c) old uuid stem with Shopify tail");
  eq(stemMatches(null, f0, "ANN01001"), false, "no url");
  const media: MediaNode[] = [
    { gid: "g/1", status: "READY", url: cdn("ANN01001_2") },
    { gid: "g/2", status: "READY", url: cdn("ANN01001_" + U) },
    { gid: "g/3", status: "READY", url: cdn(fam.files[1].product_image_id) },
    { gid: "g/4", status: "READY", url: cdn("photo-from-admin") },
    { gid: "g/5", status: "PROCESSING", url: null },
  ];
  const files2 = fam.files.slice(0, 2), stems2 = { [I(0)]: "ANN01001", [I(1)]: "ANN01002" };
  eq(matchMedia(media, files2, true, stems2), { [I(0)]: "g/2", [I(1)]: "g/3" }, "SKU+uuid one · old uuid one · ANN01001_2 not taken by ANN01001");
  eq(unknownMedia(media, files2, stems2), 3, "ANN01001_2 (not ours here) · admin photo · processing → unknown 3");
  const dup: Payload = { ...fam, variants: fam.variants.slice(0, 1), files: [fam.files[0], { ...fam.files[0], product_image_id: I(8) }] };
  const ds = imageStems(dup);
  eq(Object.values(ds), ["ANN01001", "ANN01001_2"], "two photos of one SKU");
  eq(matchMedia([{ gid: "g/9", status: "READY", url: cdn("ANN01001") }], dup.files, true, ds), { [I(0)]: "g/9" }, "one Shopify photo → only the first IMS photo");
  eq(matchMedia([{ gid: "g/9", status: "READY", url: cdn("ANN01001") }], [f0], true), {}, "no stems given → only old uuid rule (callers pass stems)");
  eq(Object.keys(st).length, 1, "fixture");
});

Deno.test("⑫ shop-photo-imp-1(판정 1179) — 패밀리 사진 줄기 = 패밀리 SKU · _2 …(구성원 SKU 와 따로 센다) · 구성원 줄기 무변 · 옛 uuid 줄기 짝 무변 · 짝이 있으면 {id}", () => {
  const F = "f0000000-0000-0000-0000-000000000000", ctx = { baseUrl: BASE, productGid: null, variantGidBySku: {}, mediaGidByImage: {}, cleanedHtml: "" };
  const ff = (i: number) => ({ product_image_id: I(i), image_path: F + "/" + I(i) + (i === 21 ? ".png" : ".jpg"), url: null, alt: "ANNIE Snap-On Rollers", product_id: null, family_id: F, sku: "ANN01000FAM" });
  const mem: Payload = { ...fam, variants: fam.variants.slice(0, 3), files: [...fam.files.slice(0, 3), { ...fam.files[0], product_image_id: I(8), image_path: P(0) + "/" + I(8) + ".jpg" }] };
  const withFam: Payload = { ...mem, files: [ff(20), ...mem.files, ff(21), ff(22)] };                    // DB 순서: 표지(패밀리 사진) → 변형 대표 → 구성원 나머지 → 패밀리 사진
  const st = imageStems(withFam), before = imageStems(mem);
  eq([st[I(20)], st[I(21)], st[I(22)]], ["ANN01000FAM", "ANN01000FAM_2", "ANN01000FAM_3"], "family photos → family SKU stem, numbered in payload order");
  eq(mem.files.map((f) => st[f.product_image_id]), mem.files.map((f) => before[f.product_image_id]), "member stems are the same with and without family photos");
  eq(mem.files.map((f) => before[f.product_image_id]), ["ANN01001", "ANN01002", "ANN01003", "ANN01001_2"], "member stems as before");
  const inp = buildProductSetInput(withFam, ctx).input as any;
  eq(inp.files.map((f: any) => f.filename), ["ANN01000FAM.jpg", "ANN01001.jpg", "ANN01002.jpg", "ANN01003.jpg", "ANN01001_2.jpg", "ANN01000FAM_2.png", "ANN01000FAM_3.jpg"], "productSet files keep the payload order · names");
  eq(inp.files[0].originalSource, imageUrl(BASE, F + "/" + I(20) + ".jpg"), "family photo source = family folder path");
  eq(inp.variants.map((v: any) => v.file?.filename), ["ANN01001.jpg", "ANN01002.jpg", "ANN01003.jpg"], "variant files untouched by family photos");
  eq(JSON.stringify(buildProductSetInput(mem, ctx).input), JSON.stringify(buildProductSetInput({ ...mem, files: mem.files.map((f) => ({ ...f })) }, ctx).input), "member-only payload builds the same input as before");
  eq(Object.values(imageStems({ ...withFam, files: [{ ...ff(20), sku: " / " }] })), [I(20)], "unusable family SKU → old uuid name");
  eq(Object.values(imageStems({ ...withFam, files: [{ ...ff(20), sku: undefined }] })), [I(20)], "family photo without sku (old DB) → old uuid name, no crash");
  const media: MediaNode[] = [
    { gid: "gid://shopify/MediaImage/1", url: "https://cdn.shopify.com/s/files/1/0/files/ANN01000FAM.jpg?v=1", status: "READY" },
    { gid: "gid://shopify/MediaImage/2", url: "https://cdn.shopify.com/s/files/1/0/files/ANN01000FAM_2_0a1b2c3d-0000-4000-8000-000000000000.png?v=1", status: "READY" },
    { gid: "gid://shopify/MediaImage/3", url: "https://cdn.shopify.com/s/files/1/0/files/" + I(22) + ".jpg?v=1", status: "READY" },
    { gid: "gid://shopify/MediaImage/4", url: "https://cdn.shopify.com/s/files/1/0/files/ANN01001.jpg?v=1", status: "READY" },
    { gid: "gid://shopify/MediaImage/5", url: "https://cdn.shopify.com/s/files/1/0/files/" + I(1) + ".jpg?v=1", status: "READY" },
  ];
  const m = matchMedia(media, withFam.files, true, st);
  eq([m[I(20)], m[I(21)], m[I(22)], m[I(0)], m[I(1)]], ["gid://shopify/MediaImage/1", "gid://shopify/MediaImage/2", "gid://shopify/MediaImage/3", "gid://shopify/MediaImage/4", "gid://shopify/MediaImage/5"], "pairing: exact family stem · _<uuid> · old uuid stem (family + member)");
  eq(unknownMedia(media, withFam.files, st), 0, "nothing unknown");
  const reuse = buildProductSetInput(withFam, { ...ctx, mediaGidByImage: m }).input as any;
  eq(reuse.files[0], { id: "gid://shopify/MediaImage/1" }, "paired family photo is sent by id only");
});

Deno.test("⑬ shop-photo-imp-2b-1 — 짝 가드: 짝 있는 사진 · 그 gid 는 줄기 맞추기에서 빠진다 · payload 밖 사진의 gid 도 · 사라진 짝은 풀린다 · 짝으로 남는 사진은 unknown 이 아니다 · 짝이 없으면 예전과 같다", () => {
  const cdn = (stem: string) => "https://cdn.shopify.com/s/files/1/0/files/" + stem + ".jpg?v=1";
  const f0 = fam.files[0], f8 = { ...fam.files[0], product_image_id: I(8) };                           // 같은 SKU 의 사진 둘 — 줄기 ANN01001 · ANN01001_2
  const p2: Payload = { ...fam, variants: fam.variants.slice(0, 1), files: [f0, f8] }, st = imageStems(p2);
  eq([st[I(0)], st[I(8)]], ["ANN01001", "ANN01001_2"], "fixture stems");
  // Shopify 쪽 이름은 IMS 순서와 엇갈려 있다(직원이 올린 이름 · 판정 1052): f0 의 그림 = ANN01001_2.jpg(g/A · 심은 짝) · ANN01001.jpg(g/B)는 짝 없는 다른 그림
  const media: MediaNode[] = [{ gid: "g/A", status: "READY", url: cdn("ANN01001_2") }, { gid: "g/B", status: "READY", url: cdn("ANN01001") }, { gid: "g/C", status: "READY", url: cdn("IMG_4471") }];
  eq(matchMedia(media, p2.files, true, st), { [I(0)]: "g/B", [I(8)]: "g/A" }, "without the guard both photos cross over by file name (the defect)");
  eq(matchMedia(media, p2.files, true, st, { [I(0)]: "g/A" }), {}, "guard: the paired photo is left alone and its gid is not given to ANN01001_2");
  eq(matchMedia(media, p2.files, true, st, {}, ["g/B"]), { [I(8)]: "g/A" }, "takenGids: a gid paired to a photo outside this payload is not taken");
  eq(unknownMedia(media, p2.files, st), 1, "old count: only the admin photo");
  eq(unknownMedia([{ gid: "g/K", status: "READY", url: cdn("IMG_9") }, ...media], p2.files, st, ["g/K"]), 1, "keptGids: a seeded pair with a Shopify-only file name is not counted as going away");
  // 풀기
  eq(livePairs({ [I(0)]: "g/A", [I(8)]: "g/gone" }, media), { live: { [I(0)]: "g/A" }, stale: [I(8)] }, "a pair whose gid is not on the product any more is stale");
  eq(livePairs({}, media), { live: {}, stale: [] }, "no pairs");
  // 한 몸: f0 은 심은 짝(g/S · 이름 IMG_1) · f8 의 짝은 사라졌다(g/gone) · g/T 는 꺼진 IMS 사진(payload 밖 I(5))의 짝인데 이름이 ANN01001_2 · g/N 은 새로 올라온 ANN01001_2_<uuid>
  const U = "0a1b2c3d-0000-4000-8000-000000000000";
  const m2: MediaNode[] = [{ gid: "g/S", status: "READY", url: cdn("IMG_1") }, { gid: "g/T", status: "READY", url: cdn("ANN01001_2") }, { gid: "g/N", status: "READY", url: cdn("ANN01001_2_" + U) }, { gid: "g/X", status: "READY", url: cdn("IMG_2") }];
  const foreign = [{ product_image_id: I(0), shopify_file_gid: "g/S" }, { product_image_id: I(5), shopify_file_gid: "g/T" }];
  const pb = pairBeforePush(m2, p2.files, st, { [I(0)]: "g/S", [I(8)]: "g/gone" }, foreign);
  eq(pb.stale, [I(8)], "stale pair released for this push");
  eq(pb.takenGids, ["g/T"], "only the row of a photo outside the payload is foreign");
  eq(pb.matched, { [I(8)]: "g/N" }, "the released photo is re-paired by stem — not with the foreign g/T");
  eq(pb.paired, { [I(0)]: "g/S", [I(8)]: "g/N" }, "pairs to send by id");
  eq(pb.removedUnknown, 2, "going away: g/T (the switched-off photo) and g/X — not the seeded g/S");
  const noNew = pairBeforePush(m2.filter((x) => x.gid !== "g/N"), p2.files, st, { [I(0)]: "g/S", [I(8)]: "g/gone" }, foreign);
  eq([noNew.matched, noNew.paired], [{}, { [I(0)]: "g/S" }], "released and nothing to pair → sent by URL again (no {id: gone gid})");
  const ctx = { baseUrl: BASE, productGid: "gid://shopify/Product/1", variantGidBySku: {}, cleanedHtml: "" };
  const inp = buildProductSetInput(p2, { ...ctx, mediaGidByImage: noNew.paired }).input as any;
  eq([inp.files[0], inp.files[1].filename, "id" in inp.files[1]], [{ id: "g/S" }, "ANN01001_2.jpg", false], "productSet: seeded pair by id · released photo by URL");
  // 짝이 하나도 없는 listing 은 예전과 같다
  const old = matchMedia(m2, p2.files, true, st), same = pairBeforePush(m2, p2.files, st, {}, []);
  eq([same.matched, same.stale, same.takenGids, same.removedUnknown], [old, [], [], unknownMedia(m2, p2.files, st)], "no pairs → same result as before the guard");
});
