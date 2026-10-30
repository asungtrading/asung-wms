// ============================================================
// ASUNG IMS — payload → productSet (_shared · shop-2b · 2026-10-09 · 판정 405 ~ 410 · shop-2-0 ⬜3 · 이견 2 · 4 · 6)
//   순수 함수(deno test): buildProductSetInput · countryAlpha2(판정 884) · assertNoForbiddenKeys · matchMedia · userErrorsSentence · mapResponse
//   ⚠️ 넣지 않는 칸(설계 §3-a Shopify 사람 칸 · 목록 칸은 보낸 대로 맞춰져 사람이 넣은 것이 지워진다): FORBIDDEN_INPUT_KEYS — 시험이 input 에 하나도 없음을 증명한다
//   문서(2026-10-09 MCP): 변형 file 은 상품 files 에도 있어야 한다 · 단일 변형 상품은 옵션 Title / Default Title 자리표시(Product 문서 「implicit Title option」) · media 는 비동기(status UPLOADED → READY)
//   판정 559(link-1b · 2026-10-20): IMS 사진 0 장이면 files 키 · 변형 file 을 넣지 않는다(Shopify 사진 무접촉 · 409 의 예외) · 사진이 생기면 409 대로
//   판정 890(shop-img-off-1 · 2026-10-30): 스토어 send_images false 면 DB 가 사진 0 장 꼴(files [] · image_id null)로 준다 → 559 갈래 · 여기서는 payload.send_images === false 를 두 번째 안전띠로 봐 files 가 와도 안 보낸다(asung · aone 의 Shopify 전용 사진 3,264 장 보호)
//   사진 쌓임 막기: shop_media 에 MediaImage id 가 있으면 {id} · 없으면 {originalSource, filename = <product_image_id>.<ext>, duplicateResolutionMode REPLACE}(같은 이름이면 바꿔치기 — 두 겹 안전띠)
//   shop-2b-fix2(실물 media_matched 0): productSet 응답 시점에는 사진이 처리 중이라 image.url 이 비어 있다 → 보내기 직전에 product(id).media 를 읽어 READY + url 인 것만 줄기(= product_image id · 실물로 확인)로 짝 → shop_media → 그 뒤 input 을 만든다(PRODUCT_MEDIA_QUERY · matchMedia readyOnly) · 처리 중인 사진은 REPLACE 로 다시(쌓이지 않음 · 실물) · 줄기가 IMS 에 없는 Shopify 사진은 files 에서 빠져 지워진다(판정 409 · media_removed_unknown)
// ============================================================

export const FORBIDDEN_INPUT_KEYS = ["collections", "metafields", "seo", "category", "templateSuffix", "giftCard", "giftCardTemplateSuffix", "requiresSellingPlan", "redirectNewHandle", "handle", "claimOwnership", "combinedListingRole"];
export const PRODUCT_MEDIA_QUERY = `query ImsProductMedia($id: ID!) { product(id: $id) { id media(first: 250) { nodes { id alt ... on MediaImage { status image { url } } } } } }`;
export const PRODUCT_SET_MUTATION = `mutation ImsProductSet($identifier: ProductSetIdentifiers, $input: ProductSetInput!) {
  productSet(identifier: $identifier, input: $input, synchronous: true) {
    product { id handle status
      variants(first: 250) { nodes { id sku inventoryItem { id } } }
      media(first: 250) { nodes { id alt ... on MediaImage { status image { url } } } } }
    userErrors { field message code } } }`;

export type PayloadVariant = { product_id: string; sku: string; name: string; barcode: string | null; price: number | string | null; compare_at_price: number | string | null; option_values: Array<{ name: string; value: string | null }>; inventory_policy: "CONTINUE" | "DENY"; is_active: boolean; sellable: boolean; image_id: string | null; weight: { value: number; unit: string } | null; hs_code: string | null; country_code: string | null };
export type PayloadFile = { product_image_id: string; image_path: string; url: string | null; alt: string | null; product_id: string };
export type Payload = { kind: "family" | "product"; store_code: string; family_id: string | null; product_id: string | null; title: string; description_html: string | null; vendor: string | null; product_type: string | null; tags: string[]; send_tags: boolean; status: "ACTIVE" | "ARCHIVED"; active_variants: number; options: Array<{ name: string; values: string[] }>; variants: PayloadVariant[]; files: PayloadFile[]; listing_on: boolean; blocks: string[]; hash: string; send_images?: boolean };   // send_images: shop-img-off-1(판정 890) · hash 밖 · false 면 DB 가 files [] · image_id null 을 준다 — 여기서는 두 번째 안전띠
export type MapCtx = { baseUrl: string; productGid: string | null; variantGidBySku: Record<string, string>; mediaGidByImage: Record<string, string>; cleanedHtml: string };
export type FileRef = { id?: string; originalSource?: string; filename?: string; contentType?: "IMAGE"; alt?: string; duplicateResolutionMode?: "REPLACE" };

const money = (v: number | string | null | undefined): string | null => (v === null || v === undefined || v === "" ? null : Number(v).toFixed(2));
const ext = (path: string) => { const m = path.match(/\.([a-z0-9]+)$/i); return m ? m[1].toLowerCase() : "jpg"; };
export const imageUrl = (baseUrl: string, imagePath: string) => baseUrl.replace(/\/+$/, "") + "/storage/v1/object/public/product-images/" + imagePath.split("/").map(encodeURIComponent).join("/");
export const hsDigits = (hs: string | null | undefined): string | null => { const d = String(hs ?? "").replace(/\D/g, ""); return d.length >= 6 && d.length <= 13 ? d : null; };
// 판정 884(shop-coo-1 · 2026-10-29): 원산지 코드 → Shopify CountryCode(두 글자) — IMS 의 product.country_of_origin_code(Cin7 원문 세 글자)는 그대로 · 바꿀 수 없으면 그 칸만 뺀다(cooDropped → 성공 note)
//   ISO 3166-1 alpha-3 → alpha-2 249 + XKX→XK(코소보 · ISO 밖 관용 코드) · 결과가 Shopify enum 에 있을 때만 — Shopify enum(Admin schema 실측 2026-10-29)은 ISO 와 다르다:
//   ISO 인데 Shopify 에 없음 AQ AS FM GU MH MP PR PW VI(보내면 같은 invalid value 오류) · Shopify 에만 AC AN TA XK ZZ — ZZ(Unknown Region)는 자리표시라 뺐다
export const ISO_ALPHA3_TO_2: Record<string, string> = Object.fromEntries([
  "AD:AND AE:ARE AF:AFG AG:ATG AI:AIA AL:ALB AM:ARM AO:AGO AQ:ATA AR:ARG AS:ASM AT:AUT AU:AUS AW:ABW AX:ALA AZ:AZE",
  "BA:BIH BB:BRB BD:BGD BE:BEL BF:BFA BG:BGR BH:BHR BI:BDI BJ:BEN BL:BLM BM:BMU BN:BRN BO:BOL BQ:BES BR:BRA BS:BHS",
  "BT:BTN BV:BVT BW:BWA BY:BLR BZ:BLZ CA:CAN CC:CCK CD:COD CF:CAF CG:COG CH:CHE CI:CIV CK:COK CL:CHL CM:CMR CN:CHN",
  "CO:COL CR:CRI CU:CUB CV:CPV CW:CUW CX:CXR CY:CYP CZ:CZE DE:DEU DJ:DJI DK:DNK DM:DMA DO:DOM DZ:DZA EC:ECU EE:EST",
  "EG:EGY EH:ESH ER:ERI ES:ESP ET:ETH FI:FIN FJ:FJI FK:FLK FM:FSM FO:FRO FR:FRA GA:GAB GB:GBR GD:GRD GE:GEO GF:GUF",
  "GG:GGY GH:GHA GI:GIB GL:GRL GM:GMB GN:GIN GP:GLP GQ:GNQ GR:GRC GS:SGS GT:GTM GU:GUM GW:GNB GY:GUY HK:HKG HM:HMD",
  "HN:HND HR:HRV HT:HTI HU:HUN ID:IDN IE:IRL IL:ISR IM:IMN IN:IND IO:IOT IQ:IRQ IR:IRN IS:ISL IT:ITA JE:JEY JM:JAM",
  "JO:JOR JP:JPN KE:KEN KG:KGZ KH:KHM KI:KIR KM:COM KN:KNA KP:PRK KR:KOR KW:KWT KY:CYM KZ:KAZ LA:LAO LB:LBN LC:LCA",
  "LI:LIE LK:LKA LR:LBR LS:LSO LT:LTU LU:LUX LV:LVA LY:LBY MA:MAR MC:MCO MD:MDA ME:MNE MF:MAF MG:MDG MH:MHL MK:MKD",
  "ML:MLI MM:MMR MN:MNG MO:MAC MP:MNP MQ:MTQ MR:MRT MS:MSR MT:MLT MU:MUS MV:MDV MW:MWI MX:MEX MY:MYS MZ:MOZ NA:NAM",
  "NC:NCL NE:NER NF:NFK NG:NGA NI:NIC NL:NLD NO:NOR NP:NPL NR:NRU NU:NIU NZ:NZL OM:OMN PA:PAN PE:PER PF:PYF PG:PNG",
  "PH:PHL PK:PAK PL:POL PM:SPM PN:PCN PR:PRI PS:PSE PT:PRT PW:PLW PY:PRY QA:QAT RE:REU RO:ROU RS:SRB RU:RUS RW:RWA",
  "SA:SAU SB:SLB SC:SYC SD:SDN SE:SWE SG:SGP SH:SHN SI:SVN SJ:SJM SK:SVK SL:SLE SM:SMR SN:SEN SO:SOM SR:SUR SS:SSD",
  "ST:STP SV:SLV SX:SXM SY:SYR SZ:SWZ TC:TCA TD:TCD TF:ATF TG:TGO TH:THA TJ:TJK TK:TKL TL:TLS TM:TKM TN:TUN TO:TON",
  "TR:TUR TT:TTO TV:TUV TW:TWN TZ:TZA UA:UKR UG:UGA UM:UMI US:USA UY:URY UZ:UZB VA:VAT VC:VCT VE:VEN VG:VGB VI:VIR",
  "VN:VNM VU:VUT WF:WLF WS:WSM YE:YEM YT:MYT ZA:ZAF ZM:ZMB ZW:ZWE",
].join(" ").split(" ").map((x) => [x.slice(3), x.slice(0, 2)]));
export const SHOPIFY_COUNTRY_CODES = new Set([
  "AC AD AE AF AG AI AL AM AN AO AR AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD",
  "CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FO FR GA GB GD GE GF GG",
  "GH GI GL GM GN GP GQ GR GS GT GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR",
  "KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MK ML MM MN MO MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG",
  "NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PS PT PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO",
  "SR SS ST SV SX SY SZ TA TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VN VU WF WS XK YE",
  "YT ZA ZM ZW",
].join(" ").split(" "));
export const countryAlpha2 = (code: string | null | undefined): string | null => {
  const c = String(code ?? "").trim().toUpperCase();
  const a2 = c.length === 2 ? c : c.length === 3 ? (c === "XKX" ? "XK" : ISO_ALPHA3_TO_2[c]) : undefined;
  return a2 && SHOPIFY_COUNTRY_CODES.has(a2) ? a2 : null;
};

export function fileRef(f: PayloadFile, ctx: MapCtx): FileRef {
  const gid = ctx.mediaGidByImage[f.product_image_id];
  if (gid) return { id: gid };
  return { originalSource: f.url ?? imageUrl(ctx.baseUrl, f.image_path), filename: f.product_image_id + "." + ext(f.image_path), contentType: "IMAGE", alt: f.alt ?? "", duplicateResolutionMode: "REPLACE" };
}

export function buildProductSetInput(p: Payload, ctx: MapCtx): { identifier: { id: string } | null; input: Record<string, unknown>; fileCount: number; cooDropped: Array<{ sku: string; code: string }> } {
  const cooDropped: Array<{ sku: string; code: string }> = [];                                   // 판정 884: 바꿀 수 없어 뺀 원산지 — index.ts 성공 note 에
  const files = p.send_images === false ? [] : p.files;                                           // 판정 890: 스토어가 사진을 안 보내면 두 번째 안전띠(DB 가 이미 [] 를 준다)
  const fileByImage = new Map(files.map((f) => [f.product_image_id, f]));
  const productOptions = p.kind === "family" && p.options.length
    ? p.options.map((o) => ({ name: o.name, values: o.values.map((v) => ({ name: v })) }))
    : [{ name: "Title", values: [{ name: "Default Title" }] }];                                   // 단일 변형 관례(Product 문서 「implicit Title option」)
  const variants = p.variants.map((v) => {
    const coo = countryAlpha2(v.country_code); if (!coo && v.country_code && v.country_code.trim()) cooDropped.push({ sku: v.sku, code: v.country_code });
    const out: Record<string, unknown> = {
      sku: v.sku,
      optionValues: p.kind === "family" && v.option_values.length ? v.option_values.map((ov) => ({ optionName: ov.name, name: ov.value ?? "" })) : [{ optionName: "Title", name: "Default Title" }],
      price: money(v.price) ?? "0.00",
      inventoryPolicy: v.inventory_policy,                                                        // 판정 406 · 407
      inventoryItem: { tracked: true, ...(v.weight && v.weight.value > 0 ? { measurement: { weight: { value: Number(v.weight.value), unit: v.weight.unit } } } : {}),
                       ...(hsDigits(v.hs_code) ? { harmonizedSystemCode: hsDigits(v.hs_code) } : {}), ...(coo ? { countryCodeOfOrigin: coo } : {}) },                 // 판정 884
    };
    if (v.barcode) out.barcode = v.barcode;
    const cmp = money(v.compare_at_price); if (cmp !== null) out.compareAtPrice = cmp;              // null = 안 보냄 · 같은 값이어도 보냄(판정 408)
    const gid = ctx.variantGidBySku[v.sku]; if (gid) out.id = gid;
    const f = files.length && v.image_id ? fileByImage.get(v.image_id) : undefined; if (f) out.file = fileRef(f, ctx);   // 변형 file 은 files 에도 있다(문서) · 판정 559: 사진 0 장이면 변형 file 도 없다
    return out;
  });
  const input: Record<string, unknown> = {
    title: p.title, descriptionHtml: ctx.cleanedHtml, status: p.status,                            // 판정 405
    productOptions, variants,
  };
  if (files.length) input.files = files.map((f) => fileRef(f, ctx));                           // 판정 409: IMS 목록대로 · 판정 559(link-1b): IMS 사진 0 장이면 files 키를 보내지 않는다(목록 칸이라 [] 는 Shopify 사진을 전부 지운다) — 사진이 생기면 409 대로
  if (p.vendor) input.vendor = p.vendor;
  if (p.product_type) input.productType = p.product_type;
  if (p.send_tags) input.tags = p.tags;                                                            // 판정 410: false 면 칸 자체를 안 보낸다
  return { identifier: ctx.productGid ? { id: ctx.productGid } : null, input, fileCount: files.length, cooDropped };
}

export function assertNoForbiddenKeys(input: Record<string, unknown>): string[] {
  const hit: string[] = [];
  const walk = (o: unknown, path: string) => {
    if (Array.isArray(o)) { o.forEach((x, i) => walk(x, path + "[" + i + "]")); return; }
    if (o && typeof o === "object") for (const k of Object.keys(o as Record<string, unknown>)) { if (FORBIDDEN_INPUT_KEYS.includes(k)) hit.push(path + "." + k); walk((o as Record<string, unknown>)[k], path + "." + k); }
  };
  walk(input, "input");
  return hit;
}

export type RespProduct = { id: string; handle: string | null; status: string; variants?: { nodes?: Array<{ id: string; sku: string | null; inventoryItem?: { id: string } | null }> }; media?: { nodes?: Array<{ id: string; alt?: string | null; status?: string | null; image?: { url?: string | null } | null }> } };
export function mapResponse(prod: RespProduct) {
  return {
    productGid: prod.id, handle: prod.handle ?? null, status: prod.status,
    variants: (prod.variants?.nodes ?? []).map((v) => ({ gid: v.id, sku: v.sku ?? "", inventoryItemGid: v.inventoryItem?.id ?? null })),
    media: (prod.media?.nodes ?? []).map((m) => ({ gid: m.id, alt: m.alt ?? null, status: m.status ?? null, url: m.image?.url ?? null })),
  };
}
// 사진 id ↔ product_image: CDN url 의 파일 이름 줄기 = product_image_id(우리가 filename 을 그렇게 보냈다 · 실물 확인 2026-10-09) · readyOnly 면 status READY + url 있는 것만 · 못 맞추면 비워 둔다(REPLACE 로 다시 보낸다)
export type MediaNode = { gid: string; url: string | null; status?: string | null; alt?: string | null };
export function matchMedia(media: MediaNode[], files: PayloadFile[], readyOnly = false): Record<string, string> {
  const out: Record<string, string> = {};
  for (const f of files) {
    const m = media.find((x) => (!readyOnly || (x.status === "READY" && !!x.url)) && (x.url ?? "").toLowerCase().includes(f.product_image_id.toLowerCase()));
    if (m) out[f.product_image_id] = m.gid;
  }
  return out;
}
// Shopify 에 있는데 IMS 사진 목록에 줄기가 없는 것(사람이 올린 사진 · 옛 파일) — files 목록에 안 들어가 지워진다(판정 409) · 수만 돌려준다
export function unknownMedia(media: MediaNode[], files: PayloadFile[]): number {
  const stems = files.map((f) => f.product_image_id.toLowerCase());
  return media.filter((x) => !stems.some((s) => (x.url ?? "").toLowerCase().includes(s))).length;
}
export const mediaNodes = (prod: RespProduct | null | undefined): MediaNode[] => (prod?.media?.nodes ?? []).map((m) => ({ gid: m.id, alt: m.alt ?? null, status: m.status ?? null, url: m.image?.url ?? null }));
export function userErrorsSentence(errs: Array<{ field?: string[] | null; message?: string; code?: string | null }>): string {
  return errs.map((e) => (e.field?.length ? e.field.join(".") + ": " : "") + (e.message ?? "") + (e.code ? " (" + e.code + ")" : "")).join(" · ").slice(0, 400);
}
