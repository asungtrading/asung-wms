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
//         ⚠️⚠️ 완료 PUT 의 TransferQuantity 변경은 **무시된다** (2026-07-28 TR-03267 실측 — 아래 applyCommit 주석).
//         → 완료 수량 = 보낸 수량 확정 / 실물 차이는 discrepancy 큐 / bin 이동은 min(received, expected) 캡.
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
    if (!resp.ok) throw new Error("Cin7 " + method + " " + path.split("?")[0] + " -> " + resp.status + ": " + text.slice(0, 400) +
      (method !== "GET" && body !== undefined ? " | SENT: " + JSON.stringify(body).slice(0, 600) : ""));
    return text ? JSON.parse(text) : {};
  }
  throw new Error("Cin7 429 rate limit (retries exhausted)");
}
const cin7Get = (path: string) => cin7("GET", path);

async function sb(method: string, path: string, body?: unknown, prefer?: string): Promise<any> {
  const url = (Deno.env.get("SUPABASE_URL") ?? "") + "/rest/v1/" + path;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const resp = await fetch(url, {
    method,
    headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json", Prefer: prefer || "return=representation" },
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

const WH_NAME: Record<string, string> = { toronto: "Asung Trading Inc.", edmonton: "Asung - Edmonton" };

// ── bin 이름 → GUID (실측 검증: Cin7 쓰기 API 는 이름 거부, GUID 만 받음) ─────────
// ⚠️⚠️ 실사고 2026-07-28 (TR-02935, 첫 에드먼튼 Apply): `/ref/location` 은 **Total 2678 인데 Limit 500 에서 잘린다.**
//   반환된 500행의 내용 = 최상위 창고 2행 + **토론토 child-location 498행뿐, 에드먼튼 child 는 0행**(전부 뒤 페이지).
//   그래서 에드먼튼 bin GUID 조회가 **첫 호출부터 throw** → Apply 의 bin 이동이 한 건도 실행되지 않고
//   전 품목이 집결 bin EZ010101 에 남았다(수량이 정확히 맞는 라인까지 남은 것이 "첫 호출부터 throw" 의 증거).
//   ⚠️ 토론토도 안전하지 않았다: Bins[] 가 2047 개인데 child 는 498행만 들어오므로 앞쪽 밖의 토론토 bin 도 같은 실패를 낸다.
//   PO-01066·PO-00965 가 성공한 것은 그 bin 들이 우연히 앞 페이지에 있었기 때문일 뿐이다.
//
// ✅ 해결 (실측 확정): **최상위 창고 행(ParentID 없음)의 `Bins[]` 에 GUID 가 이미 전부 들어있다** — 페이지네이션 불필요.
//   · Asung - Edmonton   (623edcaa-5f18-4682-aae1-b9016d977c11) Bins[] = 628개
//   · Asung Trading Inc. (f1ca3946-5a4e-4da7-b68a-ce7d3500f0be) Bins[] = 2047개
//   · 원소 형태: {"ID":"5fb51e98-…","Name":"EA010101","IsDeprecated":false,"IsStaging":false}
//   · 실측 확인: EZ010101 → b997fb39-03ee-48fd-8979-18940e082490 · EG030102 → 07f87571-fccc-400f-857f-ab31096b8fe6
//   최상위 2행은 응답 앞머리에 오므로 Limit=500 한 번으로 충분하다(잘림은 child 행에서만 발생).
//
// ❌ **child-location 이름 매칭 경로는 제거했다.** 실측상 child 의 `Name` 은 bin 이름이 아니다
//   (예 "071164313169" — 바코드류). 즉 이 경로는 처음부터 매칭될 수 없었고, 남겨두면 "폴백이 있으니 괜찮다" 는
//   오해를 남긴다. bin GUID 의 유일한 출처는 최상위 창고 행의 Bins[] 다.
let _locCache: any[] | null = null;
async function locations(): Promise<any[]> {
  if (!_locCache) _locCache = (await cin7Get("/ref/location?Limit=500")).LocationList || [];
  return _locCache as any[];
}

// 창고별 bin 이름(대문자) → {id, name} 맵. 요청 내 1회만 만든다(_locCache 재사용).
// key 는 대문자 비교용이고 name 은 Cin7 원본 표기를 그대로 보존한다 — "EZ01Pallet05" 처럼 대소문자가 섞인 bin 이 있고,
// 이 이름이 putaway_bin·to_location_raw 비교(이미 제자리 스킵)·프린트에 그대로 쓰이므로 대문자로 바꿔 내보내면 안 된다.
const _binMaps: Record<string, Map<string, { id: string; name: string }>> = {};
async function binMap(warehouse: string): Promise<Map<string, { id: string; name: string }>> {
  const key = normWarehouse(warehouse);   // 'edmonton'/'toronto' 도, 'Asung - Edmonton' 같은 Cin7 이름도 받는다
  const hit = _binMaps[key];
  if (hit) return hit;
  const list = await locations();
  const tops = list.filter((l: any) => !l.ParentID);
  const wh = tops.find((l: any) => (l.Name || "").trim() === (WH_NAME[key] || "").trim())
    || tops.find((l: any) => normWarehouse(l.Name || "") === key);
  if (!wh) throw new Error("warehouse not found in /ref/location: " + warehouse);
  const m = new Map<string, { id: string; name: string }>();
  for (const b of (wh.Bins || []) as any[]) {
    if (b.IsDeprecated) continue;                       // 폐기된 bin 은 매칭 대상 아님
    const name = String(b.Name || "").trim();
    const k = name.toUpperCase();
    if (k && b.ID && !m.has(k)) m.set(k, { id: String(b.ID), name });
  }
  _binMaps[key] = m;
  return m;
}
async function binGuid(warehouse: string, binName: string): Promise<string> {
  const g = (await binMap(warehouse)).get(String(binName || "").trim().toUpperCase());
  if (!g) throw new Error("bin not found: " + binName + " @ " + warehouse);
  return g.id;
}
// GUID 를 못 찾아도 throw 하지 않는 버전 — Apply 는 그 라인만 스킵하고 나머지를 계속 쓴다.
// ⚠️ TR-02935 의 피해가 커진 직접 원인이 "bin 한 건 실패 → 전체 throw → receipt PATCH·discrepancy 까지 유실" 이었다.
async function tryBinGuid(warehouse: string, binName: string): Promise<{ guid: string | null; reason: string }> {
  try {
    return { guid: await binGuid(warehouse, binName), reason: "" };
  } catch (e) {
    return { guid: null, reason: String((e as Error).message || e).slice(0, 200) };
  }
}

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

// ── PO 목록: 인보이스 AUTHORISED + PAID (Invoice First) ──────
// PAID 를 포함하는 이유: Invoice First 는 "인보이스가 승인됐는가"의 문제이고 PAID 는 그 승인 이후 단계(지불 완료)라 리시빙 자격을 잃지 않는다.
// (실측 2026-07-28 PO-01081: Status=INVOICED / InvoiceStatus=PAID → AUTHORISED 단일 조회에서 Total 0 으로 통째로 누락됐다.)
// 서버 파라미터는 유지한다 — 제거하면 DRAFT/NOT AVAILABLE/VOIDED 까지 긁어와 스캔량이 커지고 Invoice First 게이트가 느슨해진다.
const PO_INVOICE_STATUSES = ["AUTHORISED", "PAID"];

// ⚠️ 페이지 크기 — 조기 종료 조건(`items.length < PO_PAGE_LIMIT`)과 **반드시 같은 상수**를 써야 한다.
// 둘이 어긋나면(예: Limit=1000 인데 종료 조건이 100) 첫 페이지에서 무조건 루프가 끊긴다.
// ⚠️ 실측 2026-07-28 (purchaseList, InvoiceStatus=PAID, Total 825):
//  · **정렬은 PO 번호 오름차순.** page1 = PO-00004~ 이고 최신 PO 는 마지막 페이지(Page=9 에서 PO-01081 확인).
//    → 기존 `Limit=100` + `page <= 3`(=상태별 300건) 상한이 최신 PO 를 통째로 못 읽던 진짜 원인.
//  · **Limit=1000 이 동작한다**: page1 에 825건 전부(PO-00004~PO-01081), page2 는 0건. 상태당 호출 1번으로 끝난다.
//  · **UpdatedSince 는 쓰지 않는다** — 동작은 하지만(30일 124건/60일 249건/90일 331건) 60일 창의 page1 도
//    PO-00004 부터 시작한다. 지불 처리로 옛 PO 가 계속 갱신되므로 날짜 창이 PO 번호의 최신성을 보장하지 못한다.
//  · **RestockReceivedStatus 는 무시된다** — NOT AVAILABLE·DRAFT 모두 Total 825(무필터와 동일). 서버 필터로 못 좁히니
//    StockReceivedStatus 제외는 아래 루프에서 클라이언트 측으로 계속 처리한다.
// ⚠️ PO 총건수가 2000건을 넘기 시작하면 이 상한(PO_PAGE_LIMIT × PO_MAX_PAGES)을 다시 봐야 한다.
const PO_PAGE_LIMIT = 1000;
const PO_MAX_PAGES = 3;

async function listOpenPOs(search: string): Promise<{ pos: any[]; scanned: Record<string, number>; truncated: boolean }> {
  const byId = new Map<string, any>(); // dedup — PurchaseList 의 ID 기준 (두 조회에 같은 PO 가 들어올 수 있음)
  const scanned: Record<string, number> = {}; // 진단 — 상태별로 실제 가져온 행 수 (필터 전)
  let truncated = false;                      // 진단 — 페이지 상한에 걸려 더 있는데 못 읽은 상태가 있으면 true
  for (let si = 0; si < PO_INVOICE_STATUSES.length; si++) {
    if (si > 0) await sleep(250); // 조회 사이 간격 (Cin7 rate limit)
    const st0 = PO_INVOICE_STATUSES[si];
    scanned[st0] = 0;
    let page = 1;
    while (page <= PO_MAX_PAGES) {
      const q = "/purchaseList?Page=" + page + "&Limit=" + PO_PAGE_LIMIT + "&InvoiceStatus=" + st0 +
        (search ? "&Search=" + encodeURIComponent(search) : "");
      const data = await cin7Get(q);
      const items = data.PurchaseList || [];
      scanned[st0] += items.length;
      for (const p of items) {
        const st = String(p.Status || "").toUpperCase();
        if (st.includes("VOID") || st.includes("COMPLETED") || st.includes("CREDITED")) continue; // 끝난/취소 PO (복합상태 포함)
        if (st.includes("RECEIVED") && !st.includes("RECEIVING")) continue;                       // 이미 받은 PO (RECEIVING=부분입고 진행중은 유지)
        if (/service/i.test(String(p.Type || ""))) continue;                                     // Service 주문(운송·관세 등) 제외 — 물건 없음
        if (String(p.StockReceivedStatus || "").toUpperCase() === "AUTHORISED") continue;
        const key = String(p.ID || "");
        if (byId.has(key)) continue;
        byId.set(key, {
          id: p.ID, po_number: p.OrderNumber || "", supplier: p.Supplier || "",
          status: p.Status || "", invoice_status: p.InvoiceStatus || "",
          type: p.Type || "Simple Purchase", order_date: p.OrderDate || null, source: "po",
        });
      }
      if (items.length < PO_PAGE_LIMIT) break;              // 마지막 페이지 (실측: PAID 는 page1 825건 → 여기서 끝)
      if (page === PO_MAX_PAGES) { truncated = true; break; } // 꽉 찬 페이지인데 상한 도달 → 아직 더 남았다
      page++; await sleep(300);
    }
  }
  const out = [...byId.values()];
  out.sort((a, b) => String(b.order_date || "").localeCompare(String(a.order_date || "")));
  return { pos: out, scanned, truncated };
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
  // 같은 (SKU + bin) 은 Cin7 stock received 에서 중복 불가 → 미리 수량 합산해 하나로 병합
  const merged: Record<string, any> = {};
  for (const l of target) {
    const key = String(l.order_sku).toUpperCase() + "|" + String(l.putaway_bin).toUpperCase();
    // parts = 이 병합 그룹을 구성한 실제 receipt 라인들. exported_base 체크포인트(트랜스퍼)를 쓰려면 id 가 필요하다.
    const part = { id: l.id, received_base: Number(l.received_base || 0), exported_base: Number(l.exported_base || 0) };
    if (merged[key]) { merged[key].received_base += Number(l.received_base); merged[key].parts.push(part); }
    else merged[key] = { order_sku: l.order_sku, base_sku: l.base_sku, putaway_bin: l.putaway_bin, received_base: Number(l.received_base), parts: [part] };
  }
  const mergedLines = Object.values(merged);
  const planLines = mergedLines.map((l: any) => {
    const s = sm[String(l.order_sku).toUpperCase()];
    const factor = (s && Number(s.factor) > 0) ? Number(s.factor) : 1;
    const units = Number(l.received_base) / factor;
    if (!Number.isInteger(units)) throw new Error(l.order_sku + ": received " + l.received_base + " base units not divisible by factor " + factor);
    return {
      order_sku: l.order_sku, base_sku: l.base_sku, qty_units: units, qty_base: Number(l.received_base), bin: l.putaway_bin,
      parts: l.parts, exported_already: l.parts.reduce((n: number, p: any) => n + Number(p.exported_base || 0), 0),
    };
  });

  // ── 리시빙 차이(초과/부족/오프-PO) 를 SKU 단위로 집계 → discrepancy 큐용 ──
  // 정책: Cin7 엔 received 그대로 쓰고, 기대치(expected)와의 차이는 매니저가 Cin7 에서 수동 adjustment.
  const bySku: Record<string, any> = {};
  for (const l of lines) {
    const rb = Number(l.received_base || 0);
    if (rb <= 0 && !l.is_off_po) continue;
    const k = String(l.order_sku).toUpperCase();
    if (!bySku[k]) bySku[k] = { order_sku: l.order_sku, received: 0, expected: 0, off_po: !!l.is_off_po, needs_approval: !!l.needs_approval };
    bySku[k].received += rb;
    bySku[k].expected += Number(l.expected_base || 0);
    if (l.is_off_po) bySku[k].off_po = true;
  }
  const discrepancies: any[] = [];
  for (const k in bySku) {
    const r = bySku[k];
    if (r.off_po) {
      if (r.received > 0 && !r.needs_approval) discrepancies.push({ sku: r.order_sku, ordered_base: 0, actual_base: r.received, reason: "recv_off_po" });
    } else if (r.received > r.expected) {
      discrepancies.push({ sku: r.order_sku, ordered_base: r.expected, actual_base: r.received, reason: "recv_over" });
    } else if (r.received < r.expected) {
      discrepancies.push({ sku: r.order_sku, ordered_base: r.expected, actual_base: r.received, reason: "recv_short" });
    }
  }

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
        lines: planLines, skipped, discrepancies,
      },
    };
  }
  const det = await transferDetail(rcpt.cin7_purchase_id);
  const trStatus = String(det.status || "").toUpperCase();
  // ⚠️ 재개 경로 (2026-07-28, TR-02935): 예전 검증은 "IN TRANSIT 이어야 함" 뿐이라, 원 TR 은 COMPLETED 됐는데
  //   bin 이동이 중간에 throw 한 receipt 이 **영구히 큐에 갇혔다**(applied_at 도 null 이라 Applied 배지도 없음).
  //   → COMPLETED 도 받아들이고 ①PUT 을 건너뛰어 ②bin 이동부터 재개한다. 어느 쪽인지는 plan.mode 로 노출.
  if (trStatus !== "IN TRANSIT" && trStatus !== "COMPLETED") {
    throw new Error("transfer is " + det.status + " (expected IN TRANSIT for a new apply, or COMPLETED to resume bin moves)");
  }
  const mode = trStatus === "COMPLETED" ? "resume" : "new";

  // ⚠️ 실측(2026-07-25): 완료 시 재고 착지 지점은 트랜스퍼 헤더 To 에 따라 두 가지.
  //   (a) To = 창고 GUID        → bin 없이 창고에 떠 있음 (TR-03259 형, Cin7 재고화면 BIN 칸 공백)
  //   (b) To = 특정 bin GUID    → 그 bin 에 전량 (예 EZ010101 임시 집결 — 실제 보관자리 아님)
  //   두 경우 모두 From = det.to_guid 로 꺼내면 Cin7 이 알아서 처리(실측 200).
  //   landingBin 은 (b)에서 "이미 제자리" 스킵 판단용. to_location_raw 예: "Asung - Edmonton: EZ010101"
  // ⚠️⚠️ trim + undefined 방어 필수: (a) 는 콜론이 없어 split(":")[1] 이 undefined 이고,
  //   앞 공백(": EZ010101" → " EZ010101")이 남으면 "이미 제자리" 판정이 어긋나 From==To 이동을 쏴서 400 이 난다.
  const landingRaw = String(det.to_location_raw || "").trim();
  const ci = landingRaw.indexOf(":");
  const landingBin = ci >= 0 ? landingRaw.slice(ci + 1).trim() : "";   // (a) 창고만이면 ""
  // ⚠️ 잔량의 **위치 표현이 (a)/(b) 로 다르다.** 매니저가 Cin7 에서 찾아 제거하는 지점이라 틀리면 못 찾는다.
  //   (b) → 집결 bin 이름 / (a) → 창고명 + " (no bin)". to_location_raw 원문을 쓰는 게 가장 안전.
  const landingLabel = landingBin || ((landingRaw || WH_NAME[rcpt.warehouse] || "the warehouse") + " (no bin)");

  // ── ⚠️⚠️ bin 이동 수량 = min(received_base, expected_base) 캡 (2026-07-28 — 안 하면 400) ──
  // 완료 후 착지 지점에 실제로 앉는 건 **보낸 수량(expected)** 이다 (Cin7 이 완료 PUT 의 수량 변경을 무시하므로).
  //   · 초과 라인 → expected 만큼만 옮긴다. 초과분은 Cin7 에 **존재하지 않으므로** 옮기려 하면 400.
  //   · 부족 라인 → received 만큼 옮기고 `expected - received` 는 착지 지점에 남는다. **의도된 동작**
  //     (남은 수량 = 매니저가 Cin7 에서 제거해야 할 양이고, 남아 있다는 것 자체가 "미정리" 신호).
  //   · off-transfer(트랜스퍼에 없던 SKU) → expected 0 이라 자동으로 캡 0 → bin 이동 제외, discrepancy(recv_off_po) 로만 남긴다.
  const expBySku: Record<string, number> = {};
  const skuLabel: Record<string, string> = {};
  for (const l of lines) {
    const k = String(l.order_sku).toUpperCase();
    expBySku[k] = (expBySku[k] || 0) + Number(l.expected_base || 0);
    if (!skuLabel[k]) skuLabel[k] = l.order_sku;
  }
  const budget: Record<string, number> = {};
  for (const k in expBySku) budget[k] = expBySku[k];
  const excludedFromMove: any[] = [];
  const movedBySku: Record<string, number> = {};
  for (const p of planLines as any[]) {
    const k = String(p.order_sku).toUpperCase();
    const left = Math.max(0, Number(budget[k] || 0));
    const move = Math.min(Number(p.qty_base), left);
    budget[k] = left - move;
    p.move_base = move;                                            // Cin7 에 실제로 쏘는 수량 (캡됨)
    p.pending_base = Math.max(0, move - Number(p.exported_already || 0));  // 재개 시 남은 몫
    movedBySku[k] = (movedBySku[k] || 0) + move;
    if (move < Number(p.qty_base)) {
      excludedFromMove.push({
        sku: p.order_sku, bin: p.bin, received: Number(p.qty_base), moved: move, not_moved: Number(p.qty_base) - move,
        reason: expBySku[k] > 0 ? "over-received — the excess does not exist in Cin7" : "off-transfer SKU — Cin7 holds none of it",
      });
    }
  }
  // 착지 지점에 남는 잔량 = 보낸 수량 − 실제로 옮긴 수량 (부족 라인 + bin 없어 스킵된 라인 + 아예 못 받은 라인)
  const leftoverAtLanding: any[] = [];
  for (const k in expBySku) {
    const left = Number(expBySku[k]) - Number(movedBySku[k] || 0);
    if (left > 0) leftoverAtLanding.push({ sku: skuLabel[k], qty: left, where: landingLabel });
  }

  // pending_base 가 남은 라인만 이동 대상 (exported_base 가 이미 찬 라인은 재Apply 때 건너뛴다)
  const groups: Record<string, any[]> = {};
  (planLines as any[]).filter((p) => Number(p.pending_base) > 0).forEach((p) => { (groups[p.bin] = groups[p.bin] || []).push(p); });
  const moves = Object.keys(groups).filter((b) => !landingBin || b.toUpperCase() !== landingBin.toUpperCase());
  const alreadyExported = (planLines as any[]).filter((p) => Number(p.move_base) > 0 && Number(p.pending_base) <= 0).length;

  return {
    receipt: rcpt, source: "transfer",
    plan: {
      action: "Transfer completion + bin placement" + (mode === "resume" ? " (RESUME — transfer already COMPLETED)" : ""),
      mode,
      steps: [
        mode === "resume"
          ? "1) SKIP — " + det.po_number + " is already COMPLETED in Cin7 (resuming bin moves only)"
          : "1) PUT " + det.po_number + " -> COMPLETED with the ORIGINAL sent quantities (Cin7 ignores quantity edits) — stock lands in " + landingLabel,
        "2) " + moves.length + " bin move(s), quantity capped at the sent qty (" + (moves.join(", ") || "none") + ")" +
          (landingBin && moves.length < Object.keys(groups).length ? " · already-in-place groups skipped" : "") +
          (alreadyExported ? " · " + alreadyExported + " line(s) already exported, skipped" : ""),
        "3) " + leftoverAtLanding.length + " leftover line(s) stay in " + landingLabel +
          " — remove them in Cin7 with a manual stock adjustment (see the discrepancy queue)",
      ],
      transfer: {
        number: det.po_number, status: det.status, landing_bin: landingBin || null,
        landing_label: landingLabel, to_location_raw: landingRaw, to_guid: det.to_guid,
      },
      lines: planLines, groups: Object.keys(groups).map((b) => ({ bin: b, lines: groups[b] })),
      leftover_at_landing: leftoverAtLanding, excluded_from_move: excludedFromMove,
      skipped, discrepancies,
    },
  };
}

// ── Apply to Cin7 — 실행 (commit) ───────────────────────────
async function applyCommit(planWrap: any, appliedBy: string) {
  const rcpt = planWrap.receipt, source = planWrap.source, plan = planWrap.plan;
  const whName = WH_NAME[rcpt.warehouse] || WH_NAME.toronto;
  const log: string[] = [];
  // bin GUID 를 못 찾은 라인 — 전체를 중단시키지 않고 여기 모아 응답·apply_note 로 노출한다 (TR-02935 교훈).
  const skippedBins: { sku: string; bin: string; reason: string }[] = [];

  // ── ⓪ 리시빙 차이 → discrepancy 큐 (⚠️⚠️ Cin7 을 건드리기 **전에** 기록한다) ──
  // ⚠️ 2026-07-28 순서 역전: 예전엔 applyCommit **맨 마지막**이라 bin 이동이 throw 하면 차이 기록이 통째로 유실됐다
  //   (TR-02935 실사고 — 원 TR 은 COMPLETED 됐는데 discrepancy 도 applied_at 도 안 남아 보정 근거가 사라졌다).
  // ⚠️ 새 정책에서 이 큐는 **유일한 보정 지시서**다. 특히 트랜스퍼는 Cin7 이 완료 수량 변경을 무시하므로
  //   (아래 실측 주석) 매니저의 수동 stock adjustment 가 유일한 정정 경로다.
  // ⚠️ 그래서 여기서만 기존 방침("실패해도 Apply 성공 = WARN")을 **의도적으로 뒤집는다**:
  //   기록 실패 = Apply 중단. 기록 없이 재고를 옮기면 차이를 되찾을 방법이 없다.
  // on_conflict=receipt_id,sku + ignore-duplicates 라 재실행은 안전(중복 안 쌓임).
  const disc = (plan.discrepancies || []) as any[];
  if (disc.length) {
    const rows = disc.map((d) => ({
      order_id: null, order_number: rcpt.po_number, po_number: rcpt.po_number,
      receipt_id: rcpt.id, source: "receiving",
      sku: d.sku, ordered_base: d.ordered_base, actual_base: d.actual_base,
      reason: d.reason, responsible: rcpt.received_by || null, cin7_corrected: false,
    }));
    try {
      await sb("POST", "wms_discrepancies?on_conflict=receipt_id,sku", rows, "resolution=ignore-duplicates,return=minimal");
    } catch (e) {
      throw new Error("discrepancy log failed - NOTHING was written to Cin7 (the queue is the only correction record, " +
        "so we stop instead of moving stock without it). Detail: " + String((e as Error).message).slice(0, 200));
    }
    log.push(disc.length + " discrepancy(ies) logged for manager review (before any Cin7 write)");
  }

  if (source === "po") {
    try {
      const inv = await cin7Get("/purchase/invoice?TaskID=" + encodeURIComponent(rcpt.cin7_purchase_id));
      const st = String((inv.Invoices && inv.Invoices[0] && inv.Invoices[0].Status) || inv.Status || "").toUpperCase();
      if (st && st !== "AUTHORISED" && st !== "PAID") throw new Error("invoice status is " + st);
      log.push("invoice check: " + (st || "ok"));
    } catch (e) {
      throw new Error("Invoice not authorised - authorize the invoice in Cin7 first (Invoice First). Detail: " + String((e as Error).message));
    }
    const now = new Date().toISOString().slice(0, 10) + "T00:00:00Z";  // 실측 성공 형식
    // ⚠️ Cin7 stock received 는 한 문서(POST)에 bin(location) 1개만 허용 (실측: 다른 bin 섞으면 400 'Lines is invalid').
    //    → putaway_bin 으로 그룹핑해 bin 마다 별도 POST /purchase/stock (DRAFT). 전부 성공 후 한 번 authorize.
    const byBin: Record<string, any[]> = {};
    for (const p of plan.lines) {
      const b = String(p.bin);
      (byBin[b] = byBin[b] || []).push(p);
    }
    // bin GUID 는 **쓰기 전에 전부 해석**한다 — 못 찾은 bin 은 그 라인만 스킵하고 나머지는 계속 쓴다.
    // PO 경로는 아직 아무것도 안 쓴 상태이므로, 하나도 해석되지 않으면 throw 해서 receipt 을 큐에 남기는 게 맞다
    // (그래야 bin 을 고쳐 다시 Apply 할 수 있다). 트랜스퍼 경로는 이미 PUT COMPLETED 가 나갔으므로 절대 throw 하지 않는다.
    const resolved: { bin: string; guid: string; lines: any[] }[] = [];
    for (const bin of Object.keys(byBin)) {
      const r = await tryBinGuid(whName, bin);
      if (!r.guid) {
        byBin[bin].forEach((p) => skippedBins.push({ sku: p.order_sku, bin, reason: r.reason }));
        log.push("WARN bin " + bin + " skipped (" + byBin[bin].length + " line(s)): " + r.reason);
        continue;
      }
      resolved.push({ bin, guid: r.guid, lines: byBin[bin] });
    }
    if (!resolved.length) {
      throw new Error("no bin GUID could be resolved - nothing was written to Cin7. " +
        skippedBins.map((s) => s.bin + ": " + s.reason).join(" | "));
    }
    for (let bi = 0; bi < resolved.length; bi++) {
      const { bin, guid, lines: binLines } = resolved[bi];
      const bodyLines = binLines.map((p) => ({
        Date: now, SKU: p.order_sku, Quantity: Math.round(Number(p.qty_units)),
        LocationID: guid, Received: false,
      }));
      await cin7("POST", "/purchase/stock", { TaskID: rcpt.cin7_purchase_id, Status: "DRAFT", Lines: bodyLines });
      log.push("stock received DRAFT — bin " + bin + ": " + bodyLines.length + " line(s)");
      if (bi < resolved.length - 1) await sleep(400);
    }
    log.push("total " + resolved.reduce((n, r) => n + r.lines.length, 0) + " line(s) across " + resolved.length + " bin(s)" +
      (skippedBins.length ? " · " + skippedBins.length + " line(s) skipped (no bin GUID)" : ""));
    if (skippedBins.length) {
      // 스킵된 라인이 있으면 **자동 authorize 하지 않는다** — authorize 는 되돌릴 수 없고 Simple PO 는 한 번만 가능하므로,
      // DRAFT 로 남겨 매니저가 Cin7 화면에서 빠진 라인을 채운 뒤 직접 authorize 할 수 있게 한다.
      log.push("WARN auto-authorize SKIPPED because " + skippedBins.length + " line(s) had no bin GUID - " +
        "DRAFT is saved; add the missing line(s) in Cin7 and authorize there. Skipped: " +
        skippedBins.map((s) => s.sku + "@" + s.bin).join(", "));
    } else {
      try {
        await cin7("POST", "/purchase/stock", { TaskID: rcpt.cin7_purchase_id, Status: "AUTHORISED", Lines: [] });
        log.push("stock received AUTHORISED");
      } catch (e) {
        log.push("WARN auto-authorize failed - DRAFT is saved; authorize in Cin7 UI. (" + String((e as Error).message).slice(0, 200) + ")");
      }
    }
  } else {
    const det = await cin7Get("/stockTransfer?TaskID=" + encodeURIComponent(rcpt.cin7_purchase_id));
    const now = new Date().toISOString().slice(0, 10) + "T00:00:00Z";
    const landing = plan.transfer.landing_bin;
    const landingLabel = plan.transfer.landing_label || landing || "the warehouse";

    // ── 1) 원 TR 을 **원본(보낸) 수량 그대로** COMPLETED ──
    // ⚠️⚠️ 실물 수량 덮어쓰기(recvBySku → TransferQuantity 교체)는 **제거했다** (2026-07-28 실측, TR-03267 신규 IN TRANSIT):
    //   Cin7 은 완료 PUT 의 `TransferQuantity` 변경을 **조용히 무시한다.** SENT 에 변경값이 정확히 실려 나가고
    //   PUT 200 이 떨어지지만 되읽으면 원본 그대로다:
    //     · AS93113  원본 2 → 요청 4 → 저장 2  ❌
    //     · AS92700  원본 4 → 요청 2 → 저장 4  ❌
    //   **증가·감소 양방향 모두 무시.** 코드 버그가 아니라 API 제약이다(추정 이유: 창고간 트랜스퍼는 발송 시점에
    //   재고가 in-transit 계정으로 넘어가므로, 거기 없는 수량을 완료로 받을 수 없다).
    // ⚠️ 스킬의 "트랜스퍼 수량 초과 완료 허용(2026-07-25)" 은 **틀린 기록**이었다 — HTTP 200 만 보고 저장값을
    //   되읽지 않았고, PO stock received 의 초과 허용(이쪽은 사실)과 혼동됐다. PO 경로는 그대로 둔다.
    // → 정책(사용자 결정 2026-07-28): 완료 수량 = 보낸 수량 확정 · 실물 차이는 위 ⓪ discrepancy 에 명시(필수)
    //   · 매니저가 Cin7 에서 수동 stock adjustment 로 정리.
    if (plan.mode === "resume") {
      log.push("transfer " + (plan.transfer.number || det.Number || "") +
        " is already COMPLETED in Cin7 - PUT skipped, resuming bin moves (checkpoint resume)");
    } else {
      await cin7("PUT", "/stockTransfer", {
        TaskID: det.TaskID, Status: "COMPLETED",
        From: det.From, To: det.To,
        CostDistributionType: det.CostDistributionType || "Cost",
        InTransitAccount: det.InTransitAccount || undefined,
        DepartureDate: det.DepartureDate || now, CompletionDate: now,
        Reference: det.Reference || "", Lines: det.Lines || [],   // ⚠️ 원본 그대로 — 수량 변경은 무시된다(위 주석)
        SkipOrder: true,
      });
      log.push("transfer " + det.Number + " COMPLETED with the SENT quantities (Cin7 ignores quantity edits) - landed in " + landingLabel);
    }

    // ── 2) 착지 지점 → 실제 bin 으로 이동 (수량은 min(received, expected) 로 캡됨 — buildApplyPlan 참조) ──
    // From = det.To (창고 GUID 면 bin 없는 재고, 집결 bin GUID 면 그 bin) — 두 경우 다 실측 200.
    const fromGuid = det.To;
    // ⚠️ 여기서는 **절대 throw 하지 않는다** — 위 PUT 으로 Cin7 TR 이 이미 COMPLETED(되돌릴 수 없음)다.
    //    GUID 못 찾은 bin 은 스킵하고 남은 bin 은 계속 옮긴 뒤, 아래 receipt PATCH 까지 반드시 도달한다.
    //    (TR-02935: 첫 bin 에서 throw → TR 만 COMPLETED 되고 applied_at 은 null, discrepancy 도 유실됐다.)
    for (const g of plan.groups) {
      if (landing && String(g.bin).toUpperCase() === String(landing).toUpperCase()) {
        log.push("bin " + g.bin + ": already in place (landing bin) - skip"); continue;
      }
      const rg = await tryBinGuid(whName, g.bin);
      if (!rg.guid) {
        g.lines.forEach((p: any) => skippedBins.push({ sku: p.base_sku || p.order_sku, bin: g.bin, reason: rg.reason }));
        log.push("WARN bin move -> " + g.bin + " SKIPPED (" + g.lines.length + " line(s)): " + rg.reason +
          " - stock stays in " + landingLabel);
        continue;
      }
      const moveLines = g.lines.filter((p: any) => Number(p.pending_base) > 0);
      if (!moveLines.length) { log.push("bin " + g.bin + ": already exported - skip"); continue; }
      const mini = {
        Status: "COMPLETED", From: fromGuid, To: rg.guid,
        CostDistributionType: "Cost",
        DepartureDate: now, CompletionDate: now,
        Reference: "WMS putaway " + rcpt.po_number,
        Lines: moveLines.map((p: any) => ({ SKU: p.base_sku, TransferQuantity: Math.round(Number(p.pending_base)) })),
        SkipOrder: true,
      };
      const res = await cin7("POST", "/stockTransfer", mini);
      log.push("bin move -> " + g.bin + ": " + (res.Number || "ok") + " (" +
        moveLines.map((p: any) => p.base_sku + " x" + Math.round(Number(p.pending_base)) +
          (Number(p.pending_base) < Number(p.qty_base) ? " capped from " + Number(p.qty_base) : "")).join(", ") + ")");
      // ── exported_base 체크포인트 (규칙 27 R10 완화) ──
      // 이 bin 은 Cin7 에서 이미 옮겨졌다 → 재Apply 때 다시 쏘지 않도록 라인에 기록한다.
      // ⚠️ 되돌릴 수 없는 Cin7 쓰기 **뒤**라 PATCH 실패에도 throw 하지 않는다(규칙 21). 대신 WARN 으로 크게 남긴다 —
      //    체크포인트가 빠지면 재Apply 시 같은 bin 을 한 번 더 옮겨 재고가 이중으로 움직인다.
      for (const p of moveLines) await markExported(p, log);
      await sleep(300);
    }

    // 잔량(부족분·bin 없음·off-transfer)이 착지 지점에 남는다 — 의도된 동작이고, 매니저가 제거할 지점이다.
    // ⚠️ 어디에 남는지가 (a)창고(no bin) / (b)집결 bin 으로 다르므로 landingLabel 을 그대로 실어 보낸다.
    const lo = (plan.leftover_at_landing || []) as any[];
    if (lo.length) {
      log.push("LEFTOVER stays in " + landingLabel + " (remove in Cin7 with a manual stock adjustment): " +
        lo.map((x) => x.sku + " x" + x.qty).join(", "));
    }
    const ex = (plan.excluded_from_move || []) as any[];
    if (ex.length) {
      log.push("not moved (Cin7 holds none of it): " +
        ex.map((x) => x.sku + " " + x.not_moved + " of " + x.received + " - " + x.reason).join(" | "));
    }
  }

  // 스킵된 라인은 apply_note 에도 구조화해 남긴다 — Review/History 에서 나중에 추적 가능해야 한다.
  if (skippedBins.length) log.push("skipped_bins: " + JSON.stringify(skippedBins).slice(0, 800));

  await sb("PATCH", "wms_receipts?id=eq." + rcpt.id, {
    status: "completed", applied_at: new Date().toISOString(), applied_by: appliedBy || null, apply_note: log.join(" | "),
  });

  return { log, skipped_bins: skippedBins };
}

// ── exported_base 체크포인트: 이 planLine 이 Cin7 으로 옮겨진 수량을 구성 receipt 라인에 기록 ──
// planLine 은 (order_sku + putaway_bin) 병합체라 여러 라인으로 쪼개질 수 있다 → move_base 를 parts 순서대로
// 각 라인의 received_base 한도까지 채운다. PATCH 는 절대값이라 재실행해도 같은 상태로 수렴(idempotent).
async function markExported(p: any, log: string[]) {
  let rem = Number(p.move_base || 0);
  for (const part of (p.parts || []) as any[]) {
    const take = Math.min(Number(part.received_base || 0), Math.max(0, rem));
    rem -= take;
    try {
      await sb("PATCH", "wms_receipt_lines?id=eq." + part.id, { exported_base: take }, "return=minimal");
      part.exported_base = take;
    } catch (e) {
      log.push("WARN exported_base checkpoint failed for line " + part.id + " (" + p.order_sku + " x" + take +
        ") - a re-apply could move this bin twice: " + String((e as Error).message).slice(0, 120));
    }
  }
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
      // pos 배열은 그대로, scanned/truncated 는 최상위 진단 필드로만 추가 (receiver.html 은 pos 만 읽는다)
      return json({ ok: true, ...(await listOpenPOs((url.searchParams.get("search") || "").trim())) });
    }
    if (action === "po") {
      const id = url.searchParams.get("id") || "";
      if (!id) return json({ ok: false, error: "id required" }, 400);
      return json({ ok: true, po: await poDetail(id, url.searchParams.get("type") || "Simple Purchase") });
    }
    if (action === "bins") {
      // ⚠️ binGuid 와 **같은 소스(최상위 창고 행의 Bins[])** 를 쓴다 — 예전 child-location 수집 경로는
      //    /ref/location Limit 잘림에 똑같이 걸려 에드먼튼 bin 이 통째로 빠졌다(실측 2026-07-28, 위 binMap 주석 참조).
      const wh = normWarehouse(url.searchParams.get("warehouse") || "toronto");
      const m = await binMap(wh);
      const bins = [...m.values()].map((v) => ({ bin: v.name, id: v.id }));  // 정렬은 receiver.html 의 sortBins 가 한다
      return json({ ok: true, warehouse: wh, bins });
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
      const res = await applyCommit(planWrap, appliedBy);
      // skipped_bins = bin GUID 를 못 찾아 Cin7 에 못 쓴 라인. 사유는 log 의 WARN 줄에도 있다(admin 이 alert 로 띄움).
      return json({ ok: true, dry_run: false, log: res.log, skipped_bins: res.skipped_bins });
    }
    return json({ ok: false, error: "unknown action" }, 400);
  } catch (e) {
    return json({ ok: false, error: String((e as Error).message || e) }, 500);
  }
});
