// ============================================================
// ASUNG IMS — 기존 Shopify 상품 잇기(link-1b · 2026-10-20 · 판정 420 실행 · 555 ~ 563 · DB link-1a 20261020173401 · so-module §67)
//   순수 함수(deno test): parseBulkJsonl(JSONL → shop_link_item 원자료 칸) · errorMark(첫 보내기 실패 때 shop_product 에 무엇을 적나 — Product/0 자리표시 금지) · chunk
//   bulk: products → variants · media(connection 셋 · 중첩 2 · 문서 「connection 다섯 · 중첩 두 단계」) · inventoryItem · selectedOptions · options 는 connection 이 아니라 줄 안에 함께 온다
//   JSONL 규칙(문서 · 실물은 1d): 줄마다 JSON 하나 · 자식 줄은 `__parentId` 로 부모를 가리킨다 — 순서를 믿지 않는다(자식이 먼저 와도 끝에 붙인다 · 부모 없는 자식은 orphans)
//   퍼블리시는 읽지 않는다(판정 561) · 사진은 보고용(560 · 잇지 않는다)
// ============================================================

export const LINK_TIME_MS = 40_000;                                                                     // link_poll 한 회차 예산(다른 drain 과 같다) · 넘으면 more: true
export const LINK_CHUNK = 500;                                                                          // shop_link_item 덩이 POST 크기

export const BULK_PRODUCTS_QUERY = `{ products { edges { node { id handle title status vendor productType options { name values }
  variants { edges { node { id sku title position inventoryPolicy selectedOptions { name value } inventoryItem { id } } } }
  media { edges { node { id mediaContentType ... on MediaImage { alt image { url } } } } } } } } }`;
export const BULK_RUN_MUTATION = `mutation ImsLinkBulk($query: String!) { bulkOperationRunQuery(query: $query) { bulkOperation { id status } userErrors { field message } } }`;
export const BULK_STATUS_QUERY = `query ImsLinkBulkStatus($id: ID!) { node(id: $id) { ... on BulkOperation { id status errorCode objectCount rootObjectCount url partialDataUrl completedAt } } }`;

export type LinkVariant = { sku: string; variant_gid: string; inventory_item_gid: string | null; title: string | null; option_values: Array<{ name: string; value: string }>; inventory_policy: string | null; position: number | null };
export type LinkMedia = { gid: string; url: string | null; alt: string | null; kind: string | null };
export type LinkItem = { shopify_product_gid: string; handle: string | null; title: string | null; status: string | null; vendor: string | null; product_type: string | null;
  options: Array<{ name: string; values: string[] }>; variants: LinkVariant[]; media: LinkMedia[] };
export type ParseOut = { items: LinkItem[]; lines: number; blank: number; bad_json: number; orphans: number; unknown: number };

const kindOf = (id: unknown): "product" | "variant" | "media" | "other" => {
  const s = String(id ?? "");
  if (s.startsWith("gid://shopify/Product/")) return "product";
  if (s.startsWith("gid://shopify/ProductVariant/")) return "variant";
  if (/^gid:\/\/shopify\/(MediaImage|Video|ExternalVideo|Model3d|GenericFile)\//.test(s)) return "media";
  return "other";
};
const str = (v: unknown): string | null => (v === null || v === undefined ? null : String(v));

// JSONL → 상품 단위 원자료 · 줄 순서와 무관 · 변형은 position 순(없으면 온 순서) · SKU 는 trim(null → "")
export function parseBulkJsonl(text: string): ParseOut {
  const products = new Map<string, LinkItem>();
  const variants = new Map<string, Array<{ v: LinkVariant; seq: number }>>();
  const media = new Map<string, LinkMedia[]>();
  let lines = 0, blank = 0, bad = 0, orphans = 0, unknown = 0, seq = 0;
  for (const raw of text.split("\n")) {
    const line = raw.trim();
    lines++;
    if (!line) { blank++; continue; }
    let o: Record<string, unknown>;
    try { o = JSON.parse(line); } catch { bad++; continue; }
    const k = kindOf(o.id);
    if (k === "product") {
      const opts = Array.isArray(o.options) ? (o.options as Array<Record<string, unknown>>).map((x) => ({ name: String(x?.name ?? ""), values: Array.isArray(x?.values) ? (x.values as unknown[]).map((v) => String(v)) : [] })) : [];
      products.set(String(o.id), { shopify_product_gid: String(o.id), handle: str(o.handle), title: str(o.title), status: str(o.status), vendor: str(o.vendor), product_type: str(o.productType), options: opts, variants: [], media: [] });
    } else if (k === "variant") {
      const parent = str(o.__parentId);
      if (!parent) { orphans++; continue; }
      const so = Array.isArray(o.selectedOptions) ? (o.selectedOptions as Array<Record<string, unknown>>).map((x) => ({ name: String(x?.name ?? ""), value: String(x?.value ?? "") })) : [];
      const inv = (o.inventoryItem ?? null) as { id?: unknown } | null;
      const v: LinkVariant = { sku: String(o.sku ?? "").trim(), variant_gid: String(o.id), inventory_item_gid: inv?.id ? String(inv.id) : null, title: str(o.title), option_values: so,
        inventory_policy: str(o.inventoryPolicy), position: typeof o.position === "number" ? o.position : (o.position === undefined || o.position === null ? null : Number(o.position)) };
      if (!variants.has(parent)) variants.set(parent, []);
      variants.get(parent)!.push({ v, seq: seq++ });
    } else if (k === "media") {
      const parent = str(o.__parentId);
      if (!parent) { orphans++; continue; }
      const img = (o.image ?? null) as { url?: unknown } | null;
      if (!media.has(parent)) media.set(parent, []);
      media.get(parent)!.push({ gid: String(o.id), url: img?.url ? String(img.url) : null, alt: str(o.alt), kind: str(o.mediaContentType) });
    } else unknown++;
  }
  for (const [parent, vs] of variants) {
    const p = products.get(parent);
    if (!p) { orphans += vs.length; continue; }
    vs.sort((a, b) => ((a.v.position ?? Number.MAX_SAFE_INTEGER) - (b.v.position ?? Number.MAX_SAFE_INTEGER)) || (a.seq - b.seq));
    p.variants = vs.map((x) => x.v);
  }
  for (const [parent, ms] of media) {
    const p = products.get(parent);
    if (!p) { orphans += ms.length; continue; }
    p.media = ms;
  }
  return { items: [...products.values()], lines, blank, bad_json: bad, orphans, unknown };
}

// 첫 보내기 실패 때 shop_product 에 적을 것 — 아직 gid 가 없으면(새 상품) 아무것도 적지 않는다(null · Product/0 자리표시 금지 · 오류는 call_log 와 큐 result 에만) · 있으면 error 표시만(gid 는 안 건드린다)
export function errorMark(sp: { id: string; shopify_product_gid: string } | null | undefined, msg: string): { last_status: "error"; last_error: string } | null {
  if (!sp || !sp.shopify_product_gid || sp.shopify_product_gid === "gid://shopify/Product/0") return null;
  return { last_status: "error", last_error: msg.slice(0, 400) };
}

export function chunk<T>(arr: T[], n: number): T[][] { const out: T[][] = []; for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n)); return out; }

// shop_link_item 원자료 행(run_id 를 붙인다)
export const itemRow = (runId: string, it: LinkItem) => ({ run_id: runId, shopify_product_gid: it.shopify_product_gid, handle: it.handle, title: it.title, status: it.status, vendor: it.vendor, product_type: it.product_type, options: it.options, variants: it.variants, media: it.media });
