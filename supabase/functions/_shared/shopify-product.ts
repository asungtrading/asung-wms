// ============================================================
// ASUNG IMS — payload → productSet (_shared · shop-2b · 2026-10-09 · 판정 405 ~ 410 · shop-2-0 ⬜3 · 이견 2 · 4 · 6)
//   순수 함수(deno test): buildProductSetInput · assertNoForbiddenKeys · matchMedia · userErrorsSentence · mapResponse
//   ⚠️ 넣지 않는 칸(설계 §3-a Shopify 사람 칸 · 목록 칸은 보낸 대로 맞춰져 사람이 넣은 것이 지워진다): FORBIDDEN_INPUT_KEYS — 시험이 input 에 하나도 없음을 증명한다
//   문서(2026-10-09 MCP): 변형 file 은 상품 files 에도 있어야 한다 · 단일 변형 상품은 옵션 Title / Default Title 자리표시(Product 문서 「implicit Title option」) · media 는 비동기(status UPLOADED → READY)
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
export type Payload = { kind: "family" | "product"; store_code: string; family_id: string | null; product_id: string | null; title: string; description_html: string | null; vendor: string | null; product_type: string | null; tags: string[]; send_tags: boolean; status: "ACTIVE" | "ARCHIVED"; active_variants: number; options: Array<{ name: string; values: string[] }>; variants: PayloadVariant[]; files: PayloadFile[]; listing_on: boolean; blocks: string[]; hash: string };
export type MapCtx = { baseUrl: string; productGid: string | null; variantGidBySku: Record<string, string>; mediaGidByImage: Record<string, string>; cleanedHtml: string };
export type FileRef = { id?: string; originalSource?: string; filename?: string; contentType?: "IMAGE"; alt?: string; duplicateResolutionMode?: "REPLACE" };

const money = (v: number | string | null | undefined): string | null => (v === null || v === undefined || v === "" ? null : Number(v).toFixed(2));
const ext = (path: string) => { const m = path.match(/\.([a-z0-9]+)$/i); return m ? m[1].toLowerCase() : "jpg"; };
export const imageUrl = (baseUrl: string, imagePath: string) => baseUrl.replace(/\/+$/, "") + "/storage/v1/object/public/product-images/" + imagePath.split("/").map(encodeURIComponent).join("/");
export const hsDigits = (hs: string | null | undefined): string | null => { const d = String(hs ?? "").replace(/\D/g, ""); return d.length >= 6 && d.length <= 13 ? d : null; };

export function fileRef(f: PayloadFile, ctx: MapCtx): FileRef {
  const gid = ctx.mediaGidByImage[f.product_image_id];
  if (gid) return { id: gid };
  return { originalSource: f.url ?? imageUrl(ctx.baseUrl, f.image_path), filename: f.product_image_id + "." + ext(f.image_path), contentType: "IMAGE", alt: f.alt ?? "", duplicateResolutionMode: "REPLACE" };
}

export function buildProductSetInput(p: Payload, ctx: MapCtx): { identifier: { id: string } | null; input: Record<string, unknown>; fileCount: number } {
  const fileByImage = new Map(p.files.map((f) => [f.product_image_id, f]));
  const productOptions = p.kind === "family" && p.options.length
    ? p.options.map((o) => ({ name: o.name, values: o.values.map((v) => ({ name: v })) }))
    : [{ name: "Title", values: [{ name: "Default Title" }] }];                                   // 단일 변형 관례(Product 문서 「implicit Title option」)
  const variants = p.variants.map((v) => {
    const out: Record<string, unknown> = {
      sku: v.sku,
      optionValues: p.kind === "family" && v.option_values.length ? v.option_values.map((ov) => ({ optionName: ov.name, name: ov.value ?? "" })) : [{ optionName: "Title", name: "Default Title" }],
      price: money(v.price) ?? "0.00",
      inventoryPolicy: v.inventory_policy,                                                        // 판정 406 · 407
      inventoryItem: { tracked: true, ...(v.weight && v.weight.value > 0 ? { measurement: { weight: { value: Number(v.weight.value), unit: v.weight.unit } } } : {}),
                       ...(hsDigits(v.hs_code) ? { harmonizedSystemCode: hsDigits(v.hs_code) } : {}), ...(v.country_code ? { countryCodeOfOrigin: v.country_code } : {}) },
    };
    if (v.barcode) out.barcode = v.barcode;
    const cmp = money(v.compare_at_price); if (cmp !== null) out.compareAtPrice = cmp;              // null = 안 보냄 · 같은 값이어도 보냄(판정 408)
    const gid = ctx.variantGidBySku[v.sku]; if (gid) out.id = gid;
    const f = v.image_id ? fileByImage.get(v.image_id) : undefined; if (f) out.file = fileRef(f, ctx);   // 변형 file 은 files 에도 있다(문서)
    return out;
  });
  const input: Record<string, unknown> = {
    title: p.title, descriptionHtml: ctx.cleanedHtml, status: p.status,                            // 판정 405
    productOptions, variants, files: p.files.map((f) => fileRef(f, ctx)),                           // 판정 409: IMS 목록대로
  };
  if (p.vendor) input.vendor = p.vendor;
  if (p.product_type) input.productType = p.product_type;
  if (p.send_tags) input.tags = p.tags;                                                            // 판정 410: false 면 칸 자체를 안 보낸다
  return { identifier: ctx.productGid ? { id: ctx.productGid } : null, input, fileCount: p.files.length };
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
