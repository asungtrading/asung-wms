// ============================================================
// ASUNG WMS - Edge Function (3단계: 폴링 + dedup + 저장)
//   ▸ 폴링 범위 확대판: 여러 페이지 순회 + detail 조회 전 batch dedup
// ------------------------------------------------------------
// 흐름:
//   1) saleList(OrderStatus=AUTHORISED) 여러 페이지 순회로 후보 수집
//   2) 이미 PICKED 된 것 스킵(우리 단계는 픽 이전)
//   3) detail 조회 "전에" batch dedup — 이미 wms_orders 에 있는 건 상세조회 자체를 생략
//      (→ Cin7 API 호출을 크게 줄여 rate limit 안전, 밀린 오더까지 스캔 가능)
//   4) 남은 후보만 /sale 상세 → AdditionalAttribute1='2.Release to WMS' 만 통과
//   5) assembleLine() 정규화 → needs_review 계산
//   6) ?commit=1 이면 wms_orders + wms_order_lines 저장, 아니면 dry-run(보고만)
// ============================================================

const CIN7_BASE = "https://inventory.dearsystems.com/ExternalApi/v2";
const POLL_LIMIT = 100;       // saleList 페이지 크기 (Cin7 최대 100)
const POLL_MAX_PAGES = 3;     // 최대 순회 페이지 (100 x 3 = 최근 AUTHORISED 300건 스캔)
const MAX_DETAIL = 60;        // 한 실행당 /sale 상세조회 상한 (rate limit 보호)
const SKIP_PICKED = true;     // 이미 PICKED 된 오더는 상세조회 생략(우리 단계는 픽 이전)
const DETAIL_DELAY_MS = 250;  // Cin7 rate limit 완화 (상세조회 간 간격)
const DEDUP_CHUNK = 50;       // dedup 조회 시 SaleID 묶음 크기 (URL 길이 보호)

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function cin7Headers(): HeadersInit {
  return {
    "api-auth-accountid": Deno.env.get("CIN7_ACCOUNT_ID") ?? "",
    "api-auth-applicationkey": Deno.env.get("CIN7_APPLICATION_KEY") ?? "",
    "Content-Type": "application/json",
  };
}
function normWarehouse(loc: string): string {
  return /edmonton/i.test(loc || "") ? "edmonton" : "toronto";
}
// Cin7 sale 상세의 사용자 코멘트 추출.
// ⚠️ 실측 확정(SO-13560, 2026-07-23): 화면의 "Comments" 필드 = API의 `Note`.
//    (화면 "Shipping notes"=ShippingNotes, "Reference"=CustomerReference 로 별개)
// Note 를 우선 쓰되, 만약을 위한 폴백 유지. 값 없으면 null → 픽리스트에 코멘트 박스 안 뜸.
function extractComments(d: any): string | null {
  const cands = [d?.Note, d?.Notes, d?.Comments, d?.Comment, d?.InternalNote, d?.InternalComments];
  for (const c of cands) {
    if (c != null && String(c).trim() !== "") return String(c).trim();
  }
  return null;
}

// ── Supabase REST 헬퍼 ──
const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SB_KEY = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
function sbHeaders(extra: Record<string, string> = {}): HeadersInit {
  return { apikey: SB_KEY(), Authorization: "Bearer " + SB_KEY(), "Content-Type": "application/json", ...extra };
}
async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { headers: sbHeaders() });
  if (!r.ok) throw new Error("sbGet " + r.status + ": " + (await r.text()).slice(0, 300));
  return await r.json();
}
async function sbPost(table: string, body: unknown, returnRep = false): Promise<any> {
  const r = await fetch(SB_URL() + "/rest/v1/" + table, {
    method: "POST",
    headers: sbHeaders(returnRep ? { Prefer: "return=representation" } : {}),
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error("sbPost " + table + " " + r.status + ": " + (await r.text()).slice(0, 400));
  return returnRep ? await r.json() : null;
}
async function sbDelete(path: string): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { method: "DELETE", headers: sbHeaders() });
  if (!r.ok) throw new Error("sbDelete " + r.status + ": " + (await r.text()).slice(0, 300));
}

// 이미 존재하는 cin7_sale_id 집합을 묶음 조회로 구성 (detail 호출 전 dedup)
async function existingSaleIds(saleIds: string[]): Promise<Map<string, any>> {
  const found = new Map<string, any>();
  for (let i = 0; i < saleIds.length; i += DEDUP_CHUNK) {
    const chunk = saleIds.slice(i, i + DEDUP_CHUNK);
    const inList = chunk.map((id) => '"' + id + '"').join(",");
    const rows = await sbGet(
      "wms_orders?cin7_sale_id=in.(" + encodeURIComponent(inList) + ")&select=cin7_sale_id,order_number,status"
    );
    for (const row of rows) found.set(String(row.cin7_sale_id), row);
  }
  return found;
}

// ── 라인 정규화 + 조립 (저장용 필드 포함) ──
async function assembleLine(ln: any, warehouse: string) {
  const orderSku = (ln.SKU ?? "").trim();
  const orderedQty = Number(ln.Quantity) || 0;
  const snap = await sbGet("wms_sku_snapshot?sku=eq." + encodeURIComponent(orderSku) + "&limit=1");
  const s = snap[0] ?? null;
  const baseSku = s?.base_sku ?? orderSku;
  const factor = s?.factor ?? 1;
  const requiredBase = orderedQty * factor;
  const bins = await sbGet(
    "wms_sku_bins?sku=eq." + encodeURIComponent(baseSku) +
    "&warehouse=eq." + warehouse + "&is_current=eq.true&order=available.desc"
  );
  const flags: string[] = [];
  if (!s) flags.push("no_snapshot");
  if (s && s.is_selling === false) flags.push("not_sellable");
  if (bins.length === 0) flags.push("no_bin");
  const totalAvail = bins.reduce((sum: number, b: any) => sum + (Number(b.available) || 0), 0);
  if (bins.length > 0 && totalAvail < requiredBase) flags.push("short_stock");
  const primary = bins[0] ?? null;
  return {
    order_sku: orderSku,
    base_sku: baseSku,
    is_variant: s?.is_variant ?? false,
    ordered_qty: orderedQty,
    factor,
    required_base: requiredBase,
    product_name: s?.product_name ?? ln.Name ?? "(스냅샷 없음)",
    image_url: s?.image_url ?? "",
    is_selling: s?.is_selling ?? null,
    scannable_barcodes: s?.scannable_barcodes ?? [],
    bin_location: primary?.bin ?? null,
    zone: primary?.zone ?? null,
    available_total: totalAvail,
    bins: bins.map((b: any) => ({ bin: b.bin, zone: b.zone, available: Number(b.available) || 0 })),
    flags,
  };
}

Deno.serve(async (req) => {
  try {
    const commit = new URL(req.url).searchParams.get("commit") === "1";

    // 1) 폴링: AUTHORISED 최근 여러 페이지 수집
    let candidates: any[] = [];
    let pagesScanned = 0;
    for (let page = 1; page <= POLL_MAX_PAGES; page++) {
      const listResp = await fetch(
        CIN7_BASE + "/saleList?Limit=" + POLL_LIMIT + "&Page=" + page + "&OrderStatus=AUTHORISED",
        { headers: cin7Headers() }
      );
      if (!listResp.ok) throw new Error("Cin7 saleList " + listResp.status);
      const batch = (await listResp.json()).SaleList ?? [];
      pagesScanned++;
      candidates = candidates.concat(batch);
      if (batch.length < POLL_LIMIT) break; // 마지막 페이지
    }

    // 2) PICKED 스킵 (우리 단계는 픽 이전)
    const notPicked = candidates.filter((c) => !(SKIP_PICKED && c.CombinedPickingStatus === "PICKED"));

    // 3) detail 조회 전 batch dedup — 이미 있는 건 상세조회 생략
    const idset = await existingSaleIds(notPicked.map((c) => String(c.SaleID)));
    const skipped: any[] = [];
    const fresh: any[] = [];
    for (const c of notPicked) {
      const ex = idset.get(String(c.SaleID));
      if (ex) skipped.push({ order: c.OrderNumber, reason: "already_exists", status: ex.status });
      else fresh.push(c);
    }

    const inserted: any[] = [];
    const wouldInsert: any[] = [];
    const errors: any[] = [];
    let detailFetched = 0;
    let detailCapped = false;

    // 4) 남은 후보만 상세조회
    for (const c of fresh) {
      if (detailFetched >= MAX_DETAIL) { detailCapped = true; break; }

      await sleep(DETAIL_DELAY_MS);
      const detResp = await fetch(CIN7_BASE + "/sale?ID=" + c.SaleID, { headers: cin7Headers() });
      if (detResp.status === 429) { await sleep(60000); continue; } // rate limit
      if (!detResp.ok) { errors.push({ order: c.OrderNumber, err: "detail " + detResp.status }); continue; }
      detailFetched++;
      const d = await detResp.json();

      const progress = d.AdditionalAttributes?.AdditionalAttribute1 ?? "";
      if (progress !== "2.Release to WMS") continue; // 우리 큐만

      const comments = extractComments(d);  // Cin7 sale 코멘트 → 픽리스트 표시용
      const priceTier = (d.PriceTier ?? "").trim() || null;  // 실측 확정(SO-13560): 최상위 PriceTier

      // 5) 라인 정규화
      const warehouse = normWarehouse(d.Location);
      const lines = d.Order?.Lines ?? [];
      const assembled = [];
      for (const ln of lines) {
        if (!(ln.SKU ?? "").trim()) continue;
        assembled.push(await assembleLine(ln, warehouse));
      }
      const needsReview = assembled.some((l) => l.flags.length > 0);
      const totalReq = assembled.reduce((s, l) => s + l.required_base, 0);

      if (!commit) {
        wouldInsert.push({
          order: c.OrderNumber, warehouse, line_count: assembled.length,
          total_required_base: totalReq, needs_review: needsReview,
          comments: comments,  // dry-run에서 어느 오더에 코멘트가 들어오는지 확인
          price_tier: priceTier,
          flagged: assembled.filter((l) => l.flags.length).map((l) => ({ sku: l.order_sku, flags: l.flags })),
        });
        continue;
      }

      // 6) 저장 — 헤더 먼저(id 회수) → 라인. 라인 실패시 헤더 롤백.
      try {
        const hdr = await sbPost("wms_orders", {
          cin7_sale_id: c.SaleID,
          order_number: c.OrderNumber,
          customer_name: d.Customer ?? c.Customer ?? null,
          warehouse,
          location: d.Location ?? null,
          ship_by: (d.ShipBy || c.ShipBy || "").slice(0, 10) || null,
          order_progress: progress,
          cin7_status: d.Status ?? null,
          comments: comments,
          price_tier: priceTier,
          status: "pending",
          needs_review: needsReview,
          total_lines: assembled.length,
          total_required_base: totalReq,
          cin7_updated: c.Updated ?? null,
          last_polled_at: new Date().toISOString(),
        }, true);
        const orderId = hdr[0].id;

        const lineRows = assembled.map((l) => ({
          order_id: orderId,
          order_sku: l.order_sku, base_sku: l.base_sku, factor: l.factor,
          ordered_qty: l.ordered_qty, required_base: l.required_base,
          product_name: l.product_name, image_url: l.image_url,
          bin_location: l.bin_location, zone: l.zone,
          is_selling: l.is_selling, scannable_barcodes: l.scannable_barcodes,
          line_flag: l.flags.length ? l.flags.join(",") : null,
        }));
        try {
          await sbPost("wms_order_lines", lineRows);
        } catch (le) {
          await sbDelete("wms_orders?id=eq." + orderId); // 롤백
          throw le;
        }
        inserted.push({ order: c.OrderNumber, warehouse, line_count: assembled.length, needs_review: needsReview });
      } catch (e) {
        errors.push({ order: c.OrderNumber, err: String(e) });
      }
    }

    return json({
      mode: commit ? "COMMIT" : "DRY-RUN (저장 안 함, ?commit=1 붙이면 저장)",
      pages_scanned: pagesScanned,
      candidates: candidates.length,
      after_skip_picked: notPicked.length,
      already_exists: skipped.length,
      fresh_candidates: fresh.length,
      detail_fetched: detailFetched,
      detail_capped: detailCapped, // true 면 이번 실행 상한 도달 → 다음 실행에서 나머지 유입
      inserted: inserted.length,
      errors: errors.length,
      would_insert: commit ? undefined : wouldInsert,
      inserted_detail: commit ? inserted : undefined,
      skipped_detail: skipped,
      error_detail: errors,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj, null, 2), { status, headers: { "Content-Type": "application/json" } });
}