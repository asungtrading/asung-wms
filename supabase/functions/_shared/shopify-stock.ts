// ============================================================
// ASUNG IMS — 재고 보내기 순수 함수 (_shared · stock-1b · 2026-10-10 · 판정 421 ~ 425 · stock-1a 20261010194732)
//   DB 의 shop_stock_payload 줄(변형 × 위치)과 shop_stock_sent(마지막으로 보낸 숫자)를 받아 「무엇을 보낼지」를 가른다 — 네트워크 · DB 없음(deno test)
//   · 줄 판정 planRows: payload 에 그 변형이 없음 → skipped_off(판정 425) · blocks(no_inventory_item) → error · force 아님 + 위치 전부 sent 와 같음(ok) → skipped_same(판정 422) · 나머지 → 보낼 (아이템 · 위치 · 수량)
//     ⚠️ force 가 아니면 다른 위치만 보낸다(같은 위치는 호출에서 뺀다) · force 면 위치 둘 다
//   · 묶기 chunk: inventorySetQuantities 한 번에 STOCK_BATCH 개(한 번 최대 개수는 문서에 없다 — 첫 호출 cost 로 조정 · 상수 하나)
//   · @idempotent 키 idemKey: 묶음의 (큐 줄 id · item · location · quantity) + 참조(첫 줄 id | push-<시각>) 를 정렬해 SHA-256 → UUID 모양 · 같은 입력 → 같은 키(재시도에 안전) · 입력이 바뀌면 다른 키(IDEMPOTENCY_KEY_PARAMETER_MISMATCH 를 피한다)
//     ⚠️ 큐 줄 id 를 넣는 까닭: 같은 수량을 나중에 다시(새벽 force) 보낼 때 옛 키가 되풀이되면 Shopify 가 「이미 처리됨」으로 되돌려 덮기가 안 된다 — 줄 id 는 매번 새로 생기므로 키가 달라진다
//     📌 문서(2026-10-10 MCP · shopify.dev/docs/apps/build/apis/graphql-admin/implementing-idempotency): 성공하면 새 키 · 실패 재시도는 같은 키 · 같은 키 + 다른 인자 = IDEMPOTENCY_KEY_PARAMETER_MISMATCH · 결정적 키(UUID v5 결)는 저장 없이 재생성 가능
//   · userErrors 나누기 splitUserErrors: field 경로 ["input","quantities",<i>,…] 의 i 로 그 아이템만 error · 경로가 없으면 묶음 전체 error
//   · 상품 drain 칸 셈 countsToward(판정 424 ②): skipped_same_hash 는 DRAIN_MAX 에 세지 않는다 — 시간 한도(DRAIN_TIME_MS)로만 멈춘다
// ============================================================

export const STOCK_BATCH = 100;                                           // inventorySetQuantities 한 번의 quantities 수(짐작 · 첫 호출 cost 로 조정)
export const STOCK_DRAIN_MS = 40_000;                                     // 재고 drain 한 회차 시간 한도(cron 1 분 안에 끝나게)
export const STOCK_FETCH = 500;                                           // 한 회차에 읽는 열린 줄 수(오래된 것부터)
export const SENT_CHUNK = 100;                                            // stock-drain-fix-1: shop_stock_sent 읽기 product_id=in.() 한 번의 id 수 — uuid 36 자 × 500 ≈ 18 KB URL 은 보내기 실패(2026-10-30 Go live · 매분 500) · 100 ≈ 3.7 KB(이미 통과하는 정수 id 500 개 PATCH 와 같은 크기) · 줄 수 ≤ 100 × 위치 수로 1,000 행 캡 안
export const STOCK_REASON = "correction";
export const STOCK_REF = (firstQueueId: number | string) => "gid://asung-ims/StockQueue/" + String(firstQueueId);

export const INVENTORY_LEVELS_QUERY = `query ImsInventoryLevels($ids: [ID!]!) { nodes(ids: $ids) { ... on InventoryItem { id tracked inventoryLevels(first: 20) { nodes { location { id } } } } } }`;
export const INVENTORY_SET_MUTATION = `mutation ImsInventorySet($input: InventorySetQuantitiesInput!, $key: String!) { inventorySetQuantities(input: $input) @idempotent(key: $key) { inventoryAdjustmentGroup { id reason changes { name delta quantityAfterChange item { id } location { id } } } userErrors { field message code } } }`;
export const INVENTORY_ACTIVATE_MUTATION = `mutation ImsInventoryActivate($item: ID!, $loc: ID!, $key: String!) { inventoryActivate(inventoryItemId: $item, locationId: $loc) @idempotent(key: $key) { inventoryLevel { id location { id } } userErrors { field message } } }`;

export type StockPayloadRow = { store_id: string; product_id: string; sku: string; inventory_item_gid: string | null; warehouse_id: string; location_gid: string; quantity: number | string; is_off: boolean; blocks: string[] };
export type SentRow = { product_id: string; warehouse_id: string; quantity: number | string; last_status: "ok" | "error" };
export type QueueRow = { id: number; store_id: string; product_id: string; reason: string; force: boolean };
export type SendItem = { queue_id: number; product_id: string; sku: string; warehouse_id: string; inventory_item_gid: string; location_gid: string; quantity: number };
export type RowPlan = { queue_id: number; product_id: string; sku: string | null; result: "send" | "skipped_same" | "skipped_off" | "error"; error: string | null; items: SendItem[] };
export type UserErr = { field?: string[] | null; message?: string; code?: string | null };

const qty = (v: number | string | null | undefined): number => { const n = Math.floor(Number(v)); return Number.isFinite(n) && n > 0 ? n : 0; };

// ── 줄 판정 — 큐 줄(변형)마다 payload 줄(위치 N) · sent 를 보고 무엇을 보낼지 ──
export function planRows(queue: QueueRow[], payload: StockPayloadRow[], sent: SentRow[]): RowPlan[] {
  const byProduct = new Map<string, StockPayloadRow[]>();
  for (const r of payload) { const a = byProduct.get(r.product_id) ?? []; a.push(r); byProduct.set(r.product_id, a); }
  const sentKey = new Map(sent.map((s) => [s.product_id + "|" + s.warehouse_id, s]));
  const out: RowPlan[] = [];
  for (const q of queue) {
    const rows = (byProduct.get(q.product_id) ?? []).slice().sort((a, b) => a.location_gid.localeCompare(b.location_gid));
    if (!rows.length) { out.push({ queue_id: q.id, product_id: q.product_id, sku: null, result: "skipped_off", error: null, items: [] }); continue; }
    const sku = rows[0].sku;
    const blocked = rows.find((r) => r.blocks && r.blocks.length);
    if (blocked) { out.push({ queue_id: q.id, product_id: q.product_id, sku, result: "error", error: "cannot send stock: " + blocked.blocks.join(", ") + " (send the product first)", items: [] }); continue; }
    const items: SendItem[] = [];
    for (const r of rows) {
      const want = qty(r.quantity);
      const s = sentKey.get(r.product_id + "|" + r.warehouse_id);
      const same = !!s && s.last_status === "ok" && qty(s.quantity) === want;
      if (!q.force && same) continue;                                                             // 판정 422: 마지막으로 보낸 숫자와 같으면 그 위치는 안 보낸다
      items.push({ queue_id: q.id, product_id: r.product_id, sku, warehouse_id: r.warehouse_id, inventory_item_gid: r.inventory_item_gid as string, location_gid: r.location_gid, quantity: want });
    }
    if (!items.length) { out.push({ queue_id: q.id, product_id: q.product_id, sku, result: "skipped_same", error: null, items: [] }); continue; }
    out.push({ queue_id: q.id, product_id: q.product_id, sku, result: "send", error: null, items });
  }
  return out;
}

// ── 묶기 — 보낼 아이템을 STOCK_BATCH 개씩(순서는 큐 id · 위치) ──
export function chunk<T>(items: T[], size = STOCK_BATCH): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

// ── inventorySetQuantities 입력 — quantities 는 (item · location) 순으로 정렬(지문이 순서를 본다 · 문서) ──
export function setInput(items: SendItem[], firstQueueId: number | string): Record<string, unknown> {
  const sorted = items.slice().sort((a, b) => (a.inventory_item_gid + "|" + a.location_gid).localeCompare(b.inventory_item_gid + "|" + b.location_gid));
  return {
    name: "available", reason: STOCK_REASON, referenceDocumentUri: STOCK_REF(firstQueueId),
    quantities: sorted.map((i) => ({ inventoryItemId: i.inventory_item_gid, locationId: i.location_gid, quantity: i.quantity, changeFromQuantity: null })),   // 비교 없이 IMS 값(판정 421)
  };
}

// ── @idempotent 키 — 결정적(같은 입력 → 같은 키) · UUID 모양 ──
export async function idemKey(parts: string[]): Promise<string> {
  const text = parts.slice().sort().join("\n");
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  const hex = Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return hex.slice(0, 8) + "-" + hex.slice(8, 12) + "-" + hex.slice(12, 16) + "-" + hex.slice(16, 20) + "-" + hex.slice(20, 32);
}
export const setKeyParts = (items: SendItem[], refId: number | string) => ["ref|" + String(refId), ...items.map((i) => i.queue_id + "|" + i.inventory_item_gid + "|" + i.location_gid + "|" + i.quantity)];
export const activateKeyParts = (itemGid: string, locGid: string) => ["activate", itemGid, locGid];

// ── 위치 붙이기 — nodes(ids) 응답에서 (item · location) 활성 짝을 모은다 · 보낼 것 중 없는 짝 = activate 대상 ──
export type LevelsNode = { id?: string; tracked?: boolean; inventoryLevels?: { nodes?: Array<{ location?: { id?: string } }> } } | null;
export function activeLevels(nodes: LevelsNode[]): Set<string> {
  const s = new Set<string>();
  for (const n of nodes) { if (!n?.id) continue; for (const l of n.inventoryLevels?.nodes ?? []) if (l?.location?.id) s.add(n.id + "|" + l.location.id); }
  return s;
}
export function needActivation(items: SendItem[], active: Set<string>): Array<{ inventory_item_gid: string; location_gid: string }> {
  const seen = new Set<string>(); const out: Array<{ inventory_item_gid: string; location_gid: string }> = [];
  for (const i of items) { const k = i.inventory_item_gid + "|" + i.location_gid; if (active.has(k) || seen.has(k)) continue; seen.add(k); out.push({ inventory_item_gid: i.inventory_item_gid, location_gid: i.location_gid }); }
  return out;
}

// ── userErrors 나누기 — field ["input","quantities","3","quantity"] 의 숫자 = 정렬된 quantities 의 자리 · 없으면 묶음 전체 ──
export function splitUserErrors(errs: UserErr[], sortedItems: SendItem[]): { perItem: Map<number, string>; whole: string | null } {
  const perItem = new Map<number, string>();
  const whole: string[] = [];
  for (const e of errs) {
    const path = e.field ?? [];
    const at = path.indexOf("quantities");
    const idx = at >= 0 && at + 1 < path.length ? Number(path[at + 1]) : NaN;
    const msg = (e.code ? e.code + ": " : "") + String(e.message ?? "");
    if (Number.isInteger(idx) && idx >= 0 && idx < sortedItems.length) perItem.set(idx, (perItem.get(idx) ? perItem.get(idx) + " · " : "") + msg);
    else whole.push(msg);
  }
  return { perItem, whole: whole.length ? whole.join(" · ") : null };
}
export const sortedForSet = (items: SendItem[]) => items.slice().sort((a, b) => (a.inventory_item_gid + "|" + a.location_gid).localeCompare(b.inventory_item_gid + "|" + b.location_gid));

// ── 상품 drain 칸 셈(판정 424 ②) — skipped_same_hash 는 20 칸에 세지 않는다 · 시간 한도로 멈춘다 ──
export const DRAIN_TIME_MS = 40_000;
export const countsToward = (result: string): boolean => result !== "skipped_same_hash";
export function drainShouldStop(sentSoFar: number, max: number, elapsedMs: number, timeMs = DRAIN_TIME_MS): string | null {
  if (sentSoFar >= max) return "batch full (" + max + ")";
  if (elapsedMs >= timeMs) return "time limit (" + Math.round(timeMs / 1000) + " s)";
  return null;
}
