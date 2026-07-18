// ============================================================
// ASUNG WMS - Edge Function (2단계: base 정규화 추가)
// ------------------------------------------------------------
// 1단계 대비 변경:
//   - 오더 SKU를 스냅샷의 base_sku/factor 로 정규화
//   - required_base = ordered_qty * factor
//   - bin 조회를 base_sku 기준으로 (재고는 낱개=base 로 쌓임)
//   - is_selling=false 등 이상 라인에 flag 부여
// 여전히 저장은 안 함 (검증용). 대상=SO-13284 하나.
// ============================================================

const TARGET_ORDER = "SO-13284";
const CIN7_BASE = "https://inventory.dearsystems.com/ExternalApi/v2";

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

async function sbSelect(path: string): Promise<any[]> {
  const url = (Deno.env.get("SUPABASE_URL") ?? "") + "/rest/v1/" + path;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const resp = await fetch(url, {
    headers: { "apikey": key, "Authorization": "Bearer " + key },
  });
  if (!resp.ok) throw new Error("Supabase " + resp.status + ": " + (await resp.text()).slice(0, 300));
  return await resp.json();
}

// 오더 라인 하나를 정규화 + 스냅샷/bin 조립
async function assembleLine(ln: any, warehouse: string) {
  const orderSku = (ln.SKU ?? "").trim();
  const orderedQty = Number(ln.Quantity) || 0;

  // 1) 스냅샷 조회 (오더 SKU 기준)
  const snap = await sbSelect("wms_sku_snapshot?sku=eq." + encodeURIComponent(orderSku) + "&limit=1");
  const s = snap[0] ?? null;

  // 2) 정규화 — 스냅샷이 있으면 그 base_sku/factor 사용, 없으면 오더SKU 자체를 base 로 간주
  const baseSku = s?.base_sku ?? orderSku;
  const factor  = s?.factor ?? 1;
  const requiredBase = orderedQty * factor;

  // 3) bin 조회는 base_sku 기준 (재고는 낱개=base 로 쌓임)
  const bins = await sbSelect(
    "wms_sku_bins?sku=eq." + encodeURIComponent(baseSku) +
    "&warehouse=eq." + warehouse +
    "&is_current=eq.true&order=available.desc"
  );

  // 4) 이상 라인 플래그
  const flags: string[] = [];
  if (!s) flags.push("no_snapshot");
  if (s && s.is_selling === false) flags.push("not_sellable");
  if (bins.length === 0) flags.push("no_bin");

  const totalAvail = bins.reduce((sum: number, b: any) => sum + (Number(b.available) || 0), 0);
  if (bins.length > 0 && totalAvail < requiredBase) flags.push("short_stock");

  return {
    order_sku: orderSku,
    base_sku: baseSku,
    is_variant: s?.is_variant ?? false,
    ordered_qty: orderedQty,
    factor: factor,
    required_base: requiredBase,        // 실제 집어야 할 낱개
    product_name: s?.product_name ?? ln.Name ?? "(스냅샷 없음)",
    is_selling: s?.is_selling ?? null,
    available_total: totalAvail,
    bins: bins.map((b: any) => ({ bin: b.bin, zone: b.zone, available: Number(b.available) || 0 })),
    flags: flags,
  };
}

Deno.serve(async (_req) => {
  try {
    // 오더 검색 → SaleID
    const listResp = await fetch(
      CIN7_BASE + "/saleList?Limit=5&Page=1&Search=" + encodeURIComponent(TARGET_ORDER),
      { headers: cin7Headers() }
    );
    if (!listResp.ok) throw new Error("Cin7 saleList " + listResp.status);
    const listData = await listResp.json();
    const sales = listData.SaleList ?? [];
    const hit = sales.find((s: any) => s.OrderNumber === TARGET_ORDER) ?? sales[0];
    if (!hit) return json({ error: TARGET_ORDER + " 못 찾음" });

    // 상세 조회
    const detResp = await fetch(CIN7_BASE + "/sale?ID=" + hit.SaleID, { headers: cin7Headers() });
    if (!detResp.ok) throw new Error("Cin7 sale 상세 " + detResp.status);
    const d = await detResp.json();

    const progress = d.AdditionalAttributes?.AdditionalAttribute1 ?? "";
    const warehouse = normWarehouse(d.Location);
    const lines = d.Order?.Lines ?? [];

    // 각 라인 정규화 + 조립
    const assembled = [];
    for (const ln of lines) {
      if (!(ln.SKU ?? "").trim()) continue;
      assembled.push(await assembleLine(ln, warehouse));
    }

    // 요약
    const totalRequiredBase = assembled.reduce((s, l) => s + l.required_base, 0);
    const flaggedLines = assembled.filter(l => l.flags.length > 0).length;

    return json({
      order_number: hit.OrderNumber,
      sale_id: hit.SaleID,
      order_progress: progress,
      is_release_to_wms: progress === "2.Release to WMS",
      warehouse: warehouse,
      location_raw: d.Location,
      line_count: lines.length,
      total_required_base: totalRequiredBase,
      flagged_lines: flaggedLines,
      lines: assembled,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj, null, 2), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}