// ============================================================
// ASUNG IMS — 발송 보내기 순수 함수 · 쿼리 (_shared · ful-2 · 2026-10-13 · 판정 436 ~ 453 · DB ful-1a 20261013170000 · ful-2a 20261013193000 · ful-1b 20261013210000 · ful-2c)
//   fulfill_drain 이 쓴다 — 네트워크 · DB 없음(deno test). 흐름(index.ts fulfillDrain):
//   · 큐 ship 줄 → 그 SO 의 결과 표 머리(shop_fulfillment · pending | error)마다 ① Shopify 오더의 fulfillmentOrders(줄 · remainingQuantity · 위치 · 배송 방식) + fulfillments 를 읽고
//     ② planLines: 결과 표 줄(line_gid · 수량)을 열린 FO 줄에 짝 맞춤 · 보낼 수량은 Shopify 남은 수량으로 자른다(미룬 201 b · 자르면 quantity_sent < quantity · 경고 fulfill_cut)
//     ③ movesNeeded: FO 위치 ≠ SO 창고의 Shopify 위치면 fulfillmentOrderMove(보낼 줄 · 수량만 · 판정 445) → remapAfterMove: 옮겨진 FO 의 줄 id 로 다시 짝(원래 FO 에 발송된 줄이 있으면 새 FO 가 된다 — 스키마 설명) ·
//        move 실패 → 원래 FO 로 그대로 보내고 경고 fulfill_location_mismatch(판정 453 · 손님 메일을 늦추지 않는다)
//     ④ pickupPath: kind pickup + 쓰는 FO 전부 PICK_UP → fulfillmentOrderLineItemsPreparedForPickup(손님 「Ready for pickup」 메일 · 판정 379 · ready_at) · 그 밖(carrier · delivery · pickup + SHIPPING · delivery + PICK_UP)은 fulfillmentCreate(판정 378)
//     ⑤ buildFulfillmentInput: carrier = trackingInfo{company(Shopify 이름 · 없으면 뺌) · numbers · urls(url 틀이 있으면)} · notifyCustomer true / pickup · delivery = trackingInfo 없음 · notifyCustomer false
//     ⑥ 보낼 것이 0 이면 adoptExisting: 우리 송장과 같은 발송(carrier) · 큐에 넣은 뒤 만든 송장 없는 발송(pickup · delivery)이 있으면 그 GID 를 받아 적는다(「보냈는데 못 적은」 구멍 · fulfillmentCreate 에 @idempotent 없음) · 없으면 skipped + fulfill_nothing_left
//   📌 스키마(2026-10-13 MCP graphql_schema): FulfillmentOrderMovePayload.movedFulfillmentOrder — 「원래 FO 에 일부라도 발송된 줄이 없으면 원래 FO 가 옮겨진다 · 있으면 옮겨진 FO 는 원래 것과 다르다」 · remainingFulfillmentOrder 는 deprecated
//   📌 문서: move 실패 = FO closed · 진행 보고됨 · 새 위치가 그 품목을 stock 하지 않음 · 권한 · requestStatus SUBMITTED 등 · 발송된 줄은 못 옮긴다(FulfillmentOrderMovePayload)
//   ful-1b(판정 438 · 443 · 447): 큐 kind 셋 — ship(위) · picked_up(창구 so_picked_up(ful-1c · 옛 shop_fulfill_picked_up) → 픽업 FO 에 fulfillmentCreate notify false → GID · 짐작: 「Picked up」 전용 mutation 은 문서에 없다) ·
//     tracking_fix(창구 so_tracking_fix → GID 있는 carrier 머리마다 fulfillmentTrackingInfoUpdate notify false) · 쓸 때마다 last_push_at(ingest 의 메아리 ⓑ 2 분 창)
//   ful-2c(실물 #1008): 직원이 Shopify 에서 먼저 「Mark as ready for pickup」 을 누른 FO 에 PreparedForPickup 을 보내면 userErrors 코드 NO_LINE_ITEMS_TO_PREPARE_FOR_FULFILLMENT_ORDER 로 돌아온다(enum 셋 중 하나 · 문서 설명 「준비할 줄이 없다」)
//     → 우리가 보내는 조건(열린 PICK_UP FO · 남은 수량 > 0)이 발송됨 · 닫힘 · 보류를 먼저 걸러내므로 이 코드 = 「이미 Ready」 — 보낸 FO 전부가 그 코드면 받아 적는다(sent · ready_at = FO updatedAt(없으면 지금) · last_push_at 없음 · 경고 없음) · 일부만이면 error
//     FO 상태 IN_PROGRESS 로 미리 가르지 않는다(「준비됨」의 표시가 아니다 · 짐작이 틀리면 Ready 메일이 한 번도 안 간다 · Caleb) — Shopify 가 판정한다
// ============================================================

export const FULFILL_FETCH = 20;                                          // 한 회차에 집는 큐 줄
export const FULFILL_DRAIN_MS = 40_000;                                   // 한 회차 시간 한도(cron 1 분 안에)
export const FULFILL_MAX_ATTEMPTS = 5;                                    // 넘으면 큐 done error + 경고 fulfill_failed(다시 여는 길은 ful-1b/3)
export const OPEN_FO_STATUS = ["OPEN", "IN_PROGRESS"] as const;          // 보낼 수 있는 FO(짐작 · SCHEDULED · ON_HOLD 는 안 보낸다)
export const WARN_CODES = ["fulfill_failed", "fulfill_cut", "fulfill_location_mismatch", "fulfill_nothing_left", "pickup_failed", "tracking_fix_failed"] as const;
export const FULFILL_KINDS = ["ship", "picked_up", "tracking_fix"] as const;   // ful-1b: drain 이 집는 큐 종류(queued_at 순)
export type FulfillKind = typeof FULFILL_KINDS[number];

// ── GraphQL(2026-10 · MCP validate ✅ VALID · 필요 권한은 지금 앱(v1scopes)으로 된다 — read_orders · read/write_merchant_managed_fulfillment_orders · read_locations · read_inventory) ──
export const FULFILL_ORDERS_QUERY = `query ImsFulfillmentOrders($id: ID!) { order(id: $id) { id name displayFulfillmentStatus
  fulfillmentOrders(first: 20) { nodes { id status requestStatus updatedAt assignedLocation { location { id name } } deliveryMethod { methodType } lineItems(first: 100) { nodes { id totalQuantity remainingQuantity lineItem { id sku } } } } }
  fulfillments(first: 20) { id status createdAt trackingInfo(first: 10) { number } } } }`;
export const FULFILLMENT_CREATE_MUTATION = `mutation ImsFulfillmentCreate($fulfillment: FulfillmentInput!) { fulfillmentCreate(fulfillment: $fulfillment) { fulfillment { id status createdAt trackingInfo(first: 10) { company number url } } userErrors { field message } } }`;
export const FULFILLMENT_ORDER_MOVE_MUTATION = `mutation ImsFulfillmentOrderMove($id: ID!, $newLocationId: ID!, $items: [FulfillmentOrderLineItemInput!]) { fulfillmentOrderMove(id: $id, newLocationId: $newLocationId, fulfillmentOrderLineItems: $items) { movedFulfillmentOrder { id status assignedLocation { location { id name } } lineItems(first: 100) { nodes { id remainingQuantity lineItem { id } } } } originalFulfillmentOrder { id status } userErrors { field message } } }`;
export const TRACKING_UPDATE_MUTATION = `mutation ImsFulfillmentTrackingUpdate($fulfillmentId: ID!, $trackingInfoInput: FulfillmentTrackingInput!, $notifyCustomer: Boolean) { fulfillmentTrackingInfoUpdate(fulfillmentId: $fulfillmentId, trackingInfoInput: $trackingInfoInput, notifyCustomer: $notifyCustomer) { fulfillment { id status trackingInfo(first: 10) { company number url } } userErrors { field message } } }`;   // ful-1b 판정 438 · ✅ VALID
export const PREPARED_FOR_PICKUP_MUTATION = `mutation ImsFulfillmentReadyForPickup($input: FulfillmentOrderLineItemsPreparedForPickupInput!) { fulfillmentOrderLineItemsPreparedForPickup(input: $input) { userErrors { field message code } } }`;

// ── 모양 ──
export type FoLine = { id: string; totalQuantity?: number | null; remainingQuantity: number | null; lineItem: { id: string; sku?: string | null } | null };
export type FoNode = { id: string; status: string; requestStatus?: string | null; updatedAt?: string | null; assignedLocation?: { location?: { id: string; name?: string | null } | null } | null; deliveryMethod?: { methodType?: string | null } | null; lineItems?: { nodes?: FoLine[] } | null };
export type FulfillmentNode = { id: string; status?: string | null; createdAt?: string | null; trackingInfo?: Array<{ number?: string | null }> | null };
export type FulRow = { id: string; so_id: string; shop_order_id: string; store_id: string; carrier_id: string | null; carrier_name: string | null; carrier_kind: "carrier" | "pickup" | "delivery" | null; shopify_company: string | null; tracking_numbers: string[]; notify_customer: boolean; status: string; attempts: number; created_at: string;
  shopify_fulfillment_gid?: string | null; fulfillment_order_gid?: string | null; ready_at?: string | null; picked_up_at?: string | null };   // ful-1b: picked_up · tracking_fix 가 읽는 칸
export type FulLine = { id: string; line_gid: string; so_line_id: string; quantity: number | string; quantity_sent?: number | string | null };
export type PlanItem = { line_id: string; line_gid: string; fo_id: string; fo_line_id: string; qty: number };
export type Plan = { items: PlanItem[]; sent_by_line: Record<string, number>; cut: Array<{ line_id: string; line_gid: string; wanted: number; sent: number }>; nothing: string[] };
export type MoveReq = { fo_id: string; from_location: string | null; items: Array<{ id: string; quantity: number }> };
export type UserErr = { field?: string[] | null; message?: string; code?: string | null };

const n = (v: unknown): number => { const x = Math.floor(Number(v)); return Number.isFinite(x) && x > 0 ? x : 0; };
export const isOpenFo = (fo: FoNode): boolean => (OPEN_FO_STATUS as readonly string[]).includes(String(fo.status ?? "").toUpperCase());
export const foLocation = (fo: FoNode): string | null => fo.assignedLocation?.location?.id ?? null;
export const foMethod = (fo: FoNode): string => String(fo.deliveryMethod?.methodType ?? "").toUpperCase();

// ── ② 줄 짝 맞추기 — 결과 표 줄마다 열린 FO 의 같은 LineItem 줄(remaining > 0)에 FO id 순으로 채운다 · 모자라면 자른다(cut) · 하나도 없으면 nothing ──
export function planLines(lines: FulLine[], fos: FoNode[]): Plan {
  const open = fos.filter(isOpenFo).slice().sort((a, b) => a.id.localeCompare(b.id));
  const remaining = new Map<string, number>();                                            // FO 줄 id → 남은 수량(이 계획 안에서 줄어든다)
  for (const fo of open) for (const l of fo.lineItems?.nodes ?? []) remaining.set(l.id, n(l.remainingQuantity));
  const plan: Plan = { items: [], sent_by_line: {}, cut: [], nothing: [] };
  for (const line of lines) {
    const wanted = n(line.quantity);
    let left = wanted, sent = 0;
    for (const fo of open) {
      if (left <= 0) break;
      for (const fl of fo.lineItems?.nodes ?? []) {
        if (left <= 0) break;
        if (fl.lineItem?.id !== line.line_gid) continue;
        const avail = remaining.get(fl.id) ?? 0;
        if (avail <= 0) continue;
        const take = Math.min(avail, left);
        plan.items.push({ line_id: line.id, line_gid: line.line_gid, fo_id: fo.id, fo_line_id: fl.id, qty: take });
        remaining.set(fl.id, avail - take); left -= take; sent += take;
      }
    }
    plan.sent_by_line[line.id] = sent;
    if (sent === 0) plan.nothing.push(line.id);
    else if (sent < wanted) plan.cut.push({ line_id: line.id, line_gid: line.line_gid, wanted, sent });
  }
  return plan;
}

// ── ③ 위치 — 쓰는 FO 마다 assignedLocation ≠ 목표면 move(보낼 줄 · 수량만) ──
export function movesNeeded(items: PlanItem[], fos: FoNode[], targetLocationGid: string | null): MoveReq[] {
  if (!targetLocationGid) return [];
  const byFo = new Map(fos.map((f) => [f.id, f]));
  const out = new Map<string, MoveReq>();
  for (const it of items) {
    const fo = byFo.get(it.fo_id);
    const loc = fo ? foLocation(fo) : null;
    if (!fo || loc === targetLocationGid) continue;
    const m = out.get(it.fo_id) ?? { fo_id: it.fo_id, from_location: loc, items: [] };
    const ex = m.items.find((x) => x.id === it.fo_line_id);
    if (ex) ex.quantity += it.qty; else m.items.push({ id: it.fo_line_id, quantity: it.qty });
    out.set(it.fo_id, m);
  }
  return [...out.values()];
}
// 옮긴 뒤 — 옮겨진 FO(원래 것일 수도 · 새것일 수도)의 줄 id 로 다시 짝(lineItem.id 로) · 못 찾은 줄은 원래 id 그대로(응답이 줄을 안 줬다 · fulfillmentCreate 가 거절하면 그때 error)
export function remapAfterMove(items: PlanItem[], fromFoId: string, moved: FoNode | null): { items: PlanItem[]; unmatched: number } {
  if (!moved) return { items, unmatched: 0 };
  const byGid = new Map((moved.lineItems?.nodes ?? []).map((l) => [l.lineItem?.id ?? "", l.id]));
  let unmatched = 0;
  const out = items.map((it) => {
    if (it.fo_id !== fromFoId) return it;
    const nid = byGid.get(it.line_gid);
    if (!nid) { unmatched++; return { ...it, fo_id: moved.id }; }
    return { ...it, fo_id: moved.id, fo_line_id: nid };
  });
  return { items: out, unmatched };
}

// ── ④ 길 — kind pickup 이고 쓰는 FO 전부 PICK_UP 이면 「Ready for pickup」 · 그 밖은 fulfillmentCreate(378) ──
export function pickupPath(kind: FulRow["carrier_kind"], items: PlanItem[], fos: FoNode[]): "ready_pickup" | "create" {
  if (kind !== "pickup") return "create";
  const used = new Set(items.map((i) => i.fo_id));
  if (!used.size) return "create";
  const byFo = new Map(fos.map((f) => [f.id, f]));
  for (const id of used) { const fo = byFo.get(id); if (!fo || foMethod(fo) !== "PICK_UP") return "create"; }
  return "ready_pickup";
}

// ── ⑤ 입력 ──
export function trackingUrls(template: string | null | undefined, numbers: string[]): string[] {
  const t = String(template ?? "").trim();
  if (!t || !t.includes("{number}")) return [];
  return numbers.map((x) => t.split("{number}").join(encodeURIComponent(x)));
}
export function buildFulfillmentInput(row: FulRow, items: PlanItem[], urlTemplate: string | null | undefined): Record<string, unknown> {
  const byFo = new Map<string, Array<{ id: string; quantity: number }>>();
  for (const it of items) {
    const a = byFo.get(it.fo_id) ?? [];
    const ex = a.find((x) => x.id === it.fo_line_id);
    if (ex) ex.quantity += it.qty; else a.push({ id: it.fo_line_id, quantity: it.qty });
    byFo.set(it.fo_id, a);
  }
  const input: Record<string, unknown> = {
    lineItemsByFulfillmentOrder: [...byFo.entries()].map(([fulfillmentOrderId, fulfillmentOrderLineItems]) => ({ fulfillmentOrderId, fulfillmentOrderLineItems })),
    notifyCustomer: row.carrier_kind === "carrier",
  };
  if (row.carrier_kind === "carrier") {
    const numbers = (row.tracking_numbers ?? []).map((x) => String(x).trim()).filter(Boolean);
    const tracking: Record<string, unknown> = { numbers };
    if (row.shopify_company) tracking.company = row.shopify_company;                     // 목록에 없는 운송사 = company 를 빼고 번호만(+ url 틀이 있으면 링크)
    const urls = trackingUrls(urlTemplate, numbers);
    if (urls.length) tracking.urls = urls;
    input.trackingInfo = tracking;
  }
  return input;
}
// ful-1b 판정 438: 송장 고침 입력 — company(목록 이름 · 없으면 뺌) · numbers · urls(틀) · notifyCustomer 는 부르는 쪽이 false 로
export function buildTrackingInput(row: FulRow, urlTemplate: string | null | undefined): Record<string, unknown> {
  const numbers = (row.tracking_numbers ?? []).map((x) => String(x).trim()).filter(Boolean);
  const tracking: Record<string, unknown> = { numbers };
  if (row.shopify_company) tracking.company = row.shopify_company;
  const urls = trackingUrls(urlTemplate, numbers);
  if (urls.length) tracking.urls = urls;
  return tracking;
}
// ful-1b 판정 443: Picked up — 창구가 적은 픽업 머리(ready_at · picked_up_at 있고 GID 없음)만 · 그 머리의 픽업 FO(fulfillment_order_gid)를 찾는다 · 없거나 닫혔으면 null(받아 적기 adoptExisting 으로)
export const needsPickedUp = (row: FulRow): boolean => row.carrier_kind === "pickup" && !!row.ready_at && !!row.picked_up_at && !row.shopify_fulfillment_gid;
export const needsTrackingFix = (row: FulRow): boolean => row.carrier_kind === "carrier" && !!row.shopify_fulfillment_gid;
export function pickupFo(row: FulRow, fos: FoNode[]): FoNode | null {
  const fo = fos.find((f) => f.id === row.fulfillment_order_gid) ?? null;
  return fo && isOpenFo(fo) ? fo : null;
}
// ful-2c: 「이미 Ready」 판정 — userErrors 가 하나 이상이고 전부 NO_LINE_ITEMS_TO_PREPARE_FOR_FULFILLMENT_ORDER 일 때만(일부만 그 코드 · 다른 코드 · 코드 없음 → false = error 재시도)
export const READY_ALREADY_CODE = "NO_LINE_ITEMS_TO_PREPARE_FOR_FULFILLMENT_ORDER";
export function adoptReadyError(errs: UserErr[] | null | undefined): boolean {
  const e = errs ?? [];
  return e.length > 0 && e.every((x) => String(x.code ?? "").toUpperCase() === READY_ALREADY_CODE);
}
// ful-2c: 받아 적는 ready_at — 보낸 FO 들의 updatedAt 중 가장 늦은 것(Mark as ready 가 FO 를 바꾼 시각 · 짐작) · 없거나 못 읽으면 fallback(지금)
export function readyAtFromFos(fos: FoNode[], foIds: string[], fallback: string): string {
  const used = new Set(foIds);
  let best: string | null = null;
  for (const fo of fos) {
    if (!used.has(fo.id)) continue;
    const u = String(fo.updatedAt ?? "");
    if (u && Number.isFinite(Date.parse(u)) && (!best || u > best)) best = u;
  }
  return best ? new Date(best).toISOString() : fallback;
}
export const preparedForPickupInput = (foIds: string[]) => ({ lineItemsByFulfillmentOrder: [...new Set(foIds)].map((fulfillmentOrderId) => ({ fulfillmentOrderId })) });

// ── ⑥ 보낼 것이 0 일 때 — 우리가 이미 보낸 발송이면 받아 적는다 ──
//   carrier: 송장 번호가 하나라도 겹치는 발송(취소 아님) · pickup · delivery: 송장 없는 발송 중 큐에 넣은 뒤(결과 표 created_at 이후)에 만든 것 · 여럿이면 가장 최근
export function adoptExisting(row: FulRow, fulfillments: FulfillmentNode[]): string | null {
  const live = fulfillments.filter((f) => String(f.status ?? "").toUpperCase() !== "CANCELLED");
  if (row.carrier_kind === "carrier") {
    const mine = new Set((row.tracking_numbers ?? []).map((x) => String(x).trim()).filter(Boolean));
    if (!mine.size) return null;
    const hit = live.find((f) => (f.trackingInfo ?? []).some((t) => mine.has(String(t.number ?? "").trim())));
    return hit?.id ?? null;
  }
  const since = Date.parse(row.created_at);
  const cands = live.filter((f) => !(f.trackingInfo ?? []).some((t) => String(t.number ?? "").trim()) && (!Number.isFinite(since) || Date.parse(String(f.createdAt ?? "")) >= since - 60_000))
    .sort((a, b) => String(b.createdAt ?? "").localeCompare(String(a.createdAt ?? "")));
  return cands[0]?.id ?? null;
}

// ── 재시도 셈 — 머리 하나라도 error 면 큐를 열어 둔다 · 시도 수가 한도면 닫고 경고 ──
export function queueOutcome(fulStatuses: string[], attemptsSoFar: number, max = FULFILL_MAX_ATTEMPTS): { done: boolean; result: "ok" | "error" | null; attempts: number; warn: boolean } {
  const bad = fulStatuses.some((s) => s === "error" || s === "pending");
  if (!bad) return { done: true, result: "ok", attempts: attemptsSoFar, warn: false };
  const attempts = attemptsSoFar + 1;
  if (attempts >= max) return { done: true, result: "error", attempts, warn: true };
  return { done: false, result: null, attempts, warn: false };
}
export function userErrorsText(errs: UserErr[] | null | undefined): string {
  return (errs ?? []).map((e) => (e.field?.length ? e.field.join(".") + ": " : "") + (e.message ?? "") + (e.code ? " (" + e.code + ")" : "")).join(" · ");
}
