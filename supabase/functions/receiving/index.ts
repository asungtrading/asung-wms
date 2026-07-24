// ============================================================
// ASUNG WMS — Edge Function: receiving (v2)
// ------------------------------------------------------------
// 액션:
//   ?action=pos                → 리시빙 준비된 PO (⚠️ InvoiceStatus=AUTHORISED 만 — Invoice First 워크플로)
//   ?action=pos&search=...     → PO 검색 (동일 필터)
//   ?action=po&id=&type=       → PO 상세 + 라인 정규화(스냅샷 조인)
//   ?action=transfers          → IN TRANSIT 트랜스퍼 (입고 대기)
//   ?action=transfer&id=       → 트랜스퍼 상세 + 라인 정규화
//   ?action=apply&receipt_id=N          → Apply 계획(dry-run) 반환 — 아무것도 안 씀
//   ?action=apply&receipt_id=N&commit=1 → 실제 Cin7 쓰기 실행
//
// 검증된 쓰기 (2026-07-23 실측):
//   [PO]  POST /purchase/stock — TaskID + Lines[{Date,SKU,Quantity,LocationID(bin GUID),Received}]
//         DRAFT 생성 확인. ⚠️ 선행조건: 인보이스 authorize (아니면 400 'Invoice First').
//         Authorize = 빈 Lines 재요청 (⚠️ 이 단계만 미실측 — 실패 시 DRAFT 는 남음, Cin7 화면 수동 Authorize 안내).
//   [TR]  POST /stockTransfer — From/To 는 bin GUID (이름은 400), 즉시 COMPLETED 가능,
//         같은 창고 bin↔bin 은 InTransitAccount 불필요. (TR-03236 실측)
//         트랜스퍼 완료 = PUT 원 TR COMPLETED (기본 To bin 착지) → bin 그룹별 미니 트랜스퍼로 재배치.
// ============================================================

const CIN7_BASE = "https://inventory.dearsystems.com/ExternalApi/v2";

const CORS: HeadersInit = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

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
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function cin7(method: string, path: string, body?: unknown): Promise<any> {
  for (let attempt = 0; attempt < 3; attempt++) {
    const resp = await fetch(CIN7_BASE + path, {
      method, headers: cin7Headers(),
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (resp.status === 429) { await sleep(1500); continue; }
    const text = await resp.text();
    if (!resp.ok) throw new Error("Cin7 " + method + " " + path.split("?")[0] + " -> " + resp.status + ": " + text.slice(0, 400));
    return text ? JSON.parse(text) : {};
  }
  throw new Error("Cin7 429 rate limit (retries exhausted)");
}
const cin7Get = (path: string) => cin7("GET", path);

async function sb(method: string, path: string, body?: unknown): Promise<any> {
  const url = (Deno.env.get("SUPABASE_URL") ?? "") + "/rest/v1/" + path;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const resp = await fetch(url, {
    method,
    headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json", Prefer: "return=representation" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!resp.ok) throw new Error("Supabase " + resp.status + ": " + (await resp.text()).slice(0, 300));
  const t = await resp.text();
  return t ? JSON.parse(t) : [];
}
const sbSelect = (path: string) => sb("GET", path);

function inList(vals: string[]): string {
  return vals.map((v) => '"' + String(v).replace(/"/g, '\\"') + '"').join(",");
}

// ── bin 이름 → GUID (실측 검증: API 는 GUID 만 받음) ─────────
let _locCache: any[] | null = null;
async function locations(): Promise<any[]> {
  if (!_locCache) _locCache = (await cin7Get("/ref/location?Limit=500")).LocationList || [];
  return _locCache as any[];
}
async function binGuid(warehouseName: string, binName: string): Promise<string> {
  const list = await locations();
  const wh = list.find((l) => (l.Name || "").trim() === warehouseName.trim());
  if (!wh) throw new Error("warehouse not found: " + warehouseName);
  const inBins = (wh.Bins || []).find((b: any) => (b.Name || "").trim() === binName.trim());
  if (inBins) return inBins.ID;
  const child = list.find((l) => l.ParentID === wh.ID &&
    ((l.Name || "") === warehouseName + ": " + binName || (l.Name || "").endsWith(": " + binName) || (l.Name || "") === binName));
  if (child) return child.ID;
  throw new Error("bin not found: " + binName + " @ " + warehouseName);
}
const WH_NAME: Record<string, string> = { toronto: "Asung Trading Inc.", edmonton: "Asung - Edmonton" };

// ── 스냅샷 배치 조인 (라인 정규화 공용) ─────────────────────
async function snapMap(skus: string[]): Promise<Record<string, any>> {
  const out: Record<string, any> = {};
  const uniq = [...new Set(skus.filter(Boolean))];
  for (let i = 0; i < uniq.length; i += 50) {
    const rows = await sbSelect(
      "wms_sku_snapshot?sku=in.(" + encodeURIComponent(inList(uniq.slice(i, i + 50))) + ")" +
      "&select=sku,base_sku,factor,is_variant,product_name,image_url,scannable_barcodes");
    rows.forEach((r: any) => { out[String(r.sku).toUpperCase()] = r; });
  }
  return out;
}
function normLine(l: any, s: any) {
  const orderSku = String(l.SKU || "").trim();
  const qty = Number(l.Quantity ?? l.TransferQuantity) || 0;
  const factor = (s && Number(s.factor) > 0) ? Number(s.factor) : 1;
  return {
    cin7_po_line_id: l.ProductID || null,
    order_sku: orderSku,
    base_sku: s ? s.base_sku : orderSku,
    factor,
    expected_base: qty * factor,
    ordered_qty: qty,
    product_name: (s && s.product_name) || l.Name || l.ProductName || "",
    image_url: (s && s.image_url) || "",
    scannable_barcodes: (s && s.scannable_barcodes) || [],
    no_snapshot: !s,
  };
}

// ── PO 목록: 인보이스 AUTHORISED 만 (Invoice First) ──────────
async function listOpenPOs(search: string): Promise<any[]> {
  const out: any[] = [];
  let page = 1;
  while (page <= 3) {
    const q = "/purchaseList?Page=" + page + "&Limit=100&InvoiceStatus=AUTHORISED" +
      (search ? "&Search=" + encodeURIComponent(search) : "");
    const data = await cin7Get(q);
    const items = data.PurchaseList || [];
    for (const p of items) {
      const st = String(p.Status || "").toUpperCase();
      if (st.includes("VOID") || st.includes("COMPLETED") || st.includes("CREDITED")) continue; // 끝난/취소 PO (복합상태 포함)
      if (st.includes("RECEIVED") && !st.includes("RECEIVING")) continue;                       // 이미 받은 PO (RECEIVING=부분입고 진행중은 유지)
      if (/service/i.test(String(p.Type || ""))) continue;                                     // Service 주문(운송·관세 등) 제외 — 물건 없음
      if (String(p.StockReceivedStatus || "").toUpperCase() === "AUTHORISED") continue;
      out.push({
        id: p.ID, po_number: p.OrderNumber || "", supplier: p.Supplier || "",
        status: p.Status || "", invoice_status: p.InvoiceStatus || "",
        type: p.Type || "Simple Purchase", order_date: p.OrderDate || null, source: "po",
      });
    }
    if (items.length < 100) break;
    page++; await sleep(300);
  }
  out.sort((a, b) => String(b.order_date || "").localeCompare(String(a.order_date || "")));
  return out;
}

// ── PO 상세 ─────────────────────────────────────────────────
async function poDetail(id: string, type: string): Promise<any> {
  const endpoint = /advanced/i.test(type || "") ? "/advanced-purchase" : "/purchase";
  const d = await cin7Get(endpoint + "?ID=" + encodeURIComponent(id));
  const rawLines: any[] = d.Lines || (d.Order && d.Order.Lines) || [];
  const location = d.Location || (d.Order && d.Order.Location) || "";
  const sm = await snapMap(rawLines.map((l) => String(l.SKU || "").trim()));
  const lines = rawLines.map((l) => normLine(l, sm[String(l.SKU || "").trim().toUpperCase()]));
  return {
    id: d.ID || id, po_number: d.OrderNumber || "", supplier: d.Supplier || "",
    status: d.Status || "", location, warehouse: normWarehouse(location), source: "po",
    line_count: lines.length, total_expected_base: lines.reduce((s2, l) => s2 + l.expected_base, 0), lines,
  };
}

// ── 트랜스퍼 목록: IN TRANSIT (입고 대기) ───────────────────
async function listTransfers(): Promise<any[]> {
  const data = await cin7Get("/stockTransferList?Page=1&Limit=100&Status=" + encodeURIComponent("IN TRANSIT"));
  return (data.StockTransferList || []).map((t: any) => ({
    id: t.TaskID, po_number: t.Number || "", supplier: (t.FromLocation || "") + " -> " + (t.ToLocation || ""),
    status: t.Status || "", warehouse: normWarehouse(t.ToLocation || ""), source: "transfer",
    order_date: t.DepartureDate || null,
  }));
}

// ── 트랜스퍼 상세 ───────────────────────────────────────────
async function transferDetail(id: string): Promise<any> {
  const d = await cin7Get("/stockTransfer?TaskID=" + encodeURIComponent(id));
  const rawLines: any[] = d.Lines || [];
  const sm = await snapMap(rawLines.map((l) => String(l.SKU || "").trim()));
  const lines = rawLines.map((l) => normLine(l, sm[String(l.SKU || "").trim().toUpperCase()]));
  return {
    id: d.TaskID || id, po_number: d.Number || "", supplier: (d.FromLocation || "") + " -> " + (d.ToLocation || ""),
    status: d.Status || "", location: d.ToLocation || "", warehouse: normWarehouse(d.ToLocation || ""),
    source: "transfer", to_location_raw: d.ToLocation || "", to_guid: d.To || null,
    line_count: lines.length, total_expected_base: lines.reduce((s2, l) => s2 + l.expected_base, 0), lines,
  };
}

// ── Apply to Cin7 — 계획 수립 (dry-run 공용) ─────────────────
async function buildApplyPlan(receiptId: number) {
  const rcpts = await sbSelect("wms_receipts?id=eq." + receiptId);
  if (!rcpts.length) throw new Error("receipt not found: " + receiptId);
  const rcpt = rcpts[0];
  if (rcpt.applied_at) throw new Error(rcpt.po_number + " already applied at " + rcpt.applied_at);
  if (rcpt.status !== "completed") throw new Error("receipt must be completed first (current: " + rcpt.status + ")");
  const lines = await sbSelect("wms_receipt_lines?receipt_id=eq." + receiptId + "&order=id");

  const src = rcpt.source_type || "po";

  const target: any[] = [], skipped: any[] = [];
  for (const l of lines) {
    const qty = Number(l.received_base || 0);
    if (qty <= 0) continue;
    if (l.needs_approval) { skipped.push({ sku: l.order_sku, qty, reason: "off-PO awaiting approval" }); continue; }
    if (src === "po" && l.is_off_po) { skipped.push({ sku: l.order_sku, qty, reason: "off-PO (not on this PO - handle separately)" }); continue; }
    if (!l.putaway_bin) { skipped.push({ sku: l.order_sku, qty, reason: "no bin assigned" }); continue; }
    target.push(l);
  }
  if (!target.length) throw new Error("nothing applicable (all lines skipped)");

  const sm = await snapMap(target.map((l) => l.order_sku));
  const planLines = target.map((l) => {
    const s = sm[String(l.order_sku).toUpperCase()];
    const factor = (s && Number(s.factor) > 0) ? Number(s.factor) : 1;
    const units = Number(l.received_base) / factor;
    if (!Number.isInteger(units)) throw new Error(l.order_sku + ": received " + l.received_base + " base units not divisible by factor " + factor);
    return { order_sku: l.order_sku, base_sku: l.base_sku, qty_units: units, qty_base: Number(l.received_base), bin: l.putaway_bin };
  });

  if (src === "po") {
    return {
      receipt: rcpt, source: "po",
      plan: {
        action: "PO stock received",
        steps: [
          "1) Check invoice is AUTHORISED (Invoice First)",
          "2) POST /purchase/stock - DRAFT with " + planLines.length + " line(s), each to its bin",
          "3) Authorize stock received (empty-lines request; if it fails, authorize in Cin7 UI)",
        ],
        lines: planLines, skipped,
      },
    };
  }
  const det = await transferDetail(rcpt.cin7_purchase_id);
  if (String(det.status).toUpperCase() !== "IN TRANSIT") throw new Error("transfer is " + det.status + " (expected IN TRANSIT)");
  const groups: Record<string, any[]> = {};
  planLines.forEach((p) => { (groups[p.bin] = groups[p.bin] || []).push(p); });
  const defaultBin = (det.to_location_raw.split(":")[1] || "").trim();
  const moves = Object.keys(groups).filter((b) => b !== defaultBin);
  return {
    receipt: rcpt, source: "transfer",
    plan: {
      action: "Transfer completion + bin placement",
      steps: [
        "1) PUT " + det.po_number + " -> COMPLETED (all stock lands in default bin " + (defaultBin || "?") + ")",
        "2) " + moves.length + " mini transfer(s) from " + defaultBin + " to actual bins (" + moves.join(", ") + ")",
      ],
      transfer: { number: det.po_number, to_default_bin: defaultBin, to_guid: det.to_guid },
      lines: planLines, groups: Object.keys(groups).map((b) => ({ bin: b, lines: groups[b] })), skipped,
    },
  };
}

// ── Apply to Cin7 — 실행 (commit) ───────────────────────────
async function applyCommit(planWrap: any, appliedBy: string) {
  const rcpt = planWrap.receipt, source = planWrap.source, plan = planWrap.plan;
  const whName = WH_NAME[rcpt.warehouse] || WH_NAME.toronto;
  const log: string[] = [];

  if (source === "po") {
    try {
      const inv = await cin7Get("/purchase/invoice?TaskID=" + encodeURIComponent(rcpt.cin7_purchase_id));
      const st = String((inv.Invoices && inv.Invoices[0] && inv.Invoices[0].Status) || inv.Status || "").toUpperCase();
      if (st && st !== "AUTHORISED" && st !== "PAID") throw new Error("invoice status is " + st);
      log.push("invoice check: " + (st || "ok"));
    } catch (e) {
      throw new Error("Invoice not authorised - authorize the invoice in Cin7 first (Invoice First). Detail: " + String((e as Error).message));
    }
    const now = new Date().toISOString();
    const bodyLines = [];
    for (const p of plan.lines) {
      bodyLines.push({
        Date: now, SKU: p.order_sku, Quantity: p.qty_units,
        LocationID: await binGuid(whName, p.bin), Received: false,
      });
    }
    await cin7("POST", "/purchase/stock", { TaskID: rcpt.cin7_purchase_id, Status: "DRAFT", Lines: bodyLines });
    log.push("stock received DRAFT created: " + plan.lines.length + " line(s)");
    try {
      await cin7("POST", "/purchase/stock", { TaskID: rcpt.cin7_purchase_id, Status: "AUTHORISED", Lines: [] });
      log.push("stock received AUTHORISED");
    } catch (e) {
      log.push("WARN auto-authorize failed - DRAFT is saved; authorize in Cin7 UI. (" + String((e as Error).message).slice(0, 200) + ")");
    }
  } else {
    const det = await cin7Get("/stockTransfer?TaskID=" + encodeURIComponent(rcpt.cin7_purchase_id));
    const now = new Date().toISOString();
    const putBody = {
      TaskID: det.TaskID, Status: "COMPLETED",
      From: det.From, To: det.To,
      CostDistributionType: det.CostDistributionType || "Cost",
      InTransitAccount: det.InTransitAccount || undefined,
      DepartureDate: det.DepartureDate || now, CompletionDate: now,
      Reference: det.Reference || "", Lines: det.Lines, SkipOrder: true,
    };
    await cin7("PUT", "/stockTransfer", putBody);
    log.push("transfer " + det.Number + " COMPLETED (landed in default bin)");
    const fromGuid = det.To;
    for (const g of plan.groups) {
      if (g.bin === plan.transfer.to_default_bin) { log.push("group " + g.bin + ": already default bin - skip"); continue; }
      const toGuid = await binGuid(whName, g.bin);
      const mini = {
        Status: "COMPLETED", From: fromGuid, To: toGuid,
        CostDistributionType: "Cost",
        DepartureDate: now, CompletionDate: now,
        Reference: "WMS putaway " + rcpt.po_number,
        Lines: g.lines.map((p: any) => ({ SKU: p.base_sku, TransferQuantity: p.qty_base })),
        SkipOrder: true,
      };
      const res = await cin7("POST", "/stockTransfer", mini);
      log.push("bin move -> " + g.bin + ": " + (res.Number || "ok") + " (" + g.lines.length + " line(s))");
      await sleep(300);
    }
  }

  await sb("PATCH", "wms_receipts?id=eq." + rcpt.id, {
    applied_at: new Date().toISOString(), applied_by: appliedBy || null, apply_note: log.join(" | "),
  });
  return log;
}

// ── 엔트리 ──────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
  try {
    const url = new URL(req.url);
    const action = url.searchParams.get("action") || "pos";
    if (action === "pos") {
      return json({ ok: true, pos: await listOpenPOs((url.searchParams.get("search") || "").trim()) });
    }
    if (action === "po") {
      const id = url.searchParams.get("id") || "";
      if (!id) return json({ ok: false, error: "id required" }, 400);
      return json({ ok: true, po: await poDetail(id, url.searchParams.get("type") || "Simple Purchase") });
    }
    if (action === "transfers") {
      return json({ ok: true, transfers: await listTransfers() });
    }
    if (action === "transfer") {
      const id = url.searchParams.get("id") || "";
      if (!id) return json({ ok: false, error: "id required" }, 400);
      return json({ ok: true, po: await transferDetail(id) });
    }
    if (action === "apply") {
      const rid = Number(url.searchParams.get("receipt_id") || 0);
      if (!rid) return json({ ok: false, error: "receipt_id required" }, 400);
      const planWrap = await buildApplyPlan(rid);
      if (url.searchParams.get("commit") !== "1") {
        return json({ ok: true, dry_run: true, source: planWrap.source, plan: planWrap.plan });
      }
      const appliedBy = url.searchParams.get("by") || "";
      const log = await applyCommit(planWrap, appliedBy);
      return json({ ok: true, dry_run: false, log });
    }
    return json({ ok: false, error: "unknown action" }, 400);
  } catch (e) {
    return json({ ok: false, error: String((e as Error).message || e) }, 500);
  }
});
