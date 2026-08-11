// ============================================================
// ASUNG WMS - Edge Function (3단계: 폴링 + dedup + 저장)
//   ▸ 폴링 범위 확대판: 여러 페이지 순회 + detail 조회 전 batch dedup
// ------------------------------------------------------------
// 흐름:
//   1) saleList(OrderStatus=AUTHORISED) 여러 페이지 순회로 후보 수집
//      — 429 는 공용 cin7() 백오프로 재시도, 소진 시 throw 없이 회차 조기 종료(rate_limited 노출)
//   2) 이미 PICKED 된 것 스킵(우리 단계는 픽 이전) — 제외 내역은 skipped_detail 에 기록
//   3) detail 조회 "전에" batch dedup — 이미 wms_orders 에 있는 건 상세조회 자체를 생략
//      (→ Cin7 API 호출을 크게 줄여 rate limit 안전, 밀린 오더까지 스캔 가능)
//   3b) "확인했으나 비대상" 기억 스킵 (2026-08-11, wms_polled_sales) — Updated 정확 일치 + TTL(1시간)
//      이내면 상세조회 생략. 회차당 상세 50→~6건. 판정은 언제나 상세조회가 한다(상수 주석 참조).
//   4) 남은 후보만 "최신 오더번호부터" /sale 상세 → AdditionalAttribute1='2.Release to WMS' 만 통과
//      (비대상 오더는 저장되지 않아 매 회차 fresh 에 남는다 — 최신 우선이 아니면
//       MAX_DETAIL 캡을 그것들이 선점해 최신 오더가 굶는다. 2026-08-04 실사고 SO-14106)
//   5) assembleLine() 정규화 → needs_review 계산
//   6) ?commit=1 이면 wms_orders + wms_order_lines 저장, 아니면 dry-run(보고만)
// ============================================================
// Cin7 HTTP 레이어는 receiving 과 공용 (2026-08-04 공용화 — 429 정책이 갈라지지 않게).
// ⚠️ _shared/cin7.ts 를 바꾸면 receiving 도 함께 재배포할 것 (파일 상단 주석 참조).
import { CIN7_BASE, cin7Get, cin7Headers, sleep } from "../_shared/cin7.ts";

const POLL_LIMIT = 100;       // saleList 페이지 크기 (실측 2026-08-04: AUTHORISED Total 140 — 100×3 이면 전량)
const POLL_MAX_PAGES = 3;     // 최대 순회 페이지 (총량이 300 을 넘으면 재검토 — 응답 truncated:true 가 그 신호)
const MAX_DETAIL = 60;        // 한 실행당 /sale 상세조회 상한 (rate limit 보호)
const SKIP_PICKED = true;     // 이미 PICKED 된 오더는 상세조회 생략(우리 단계는 픽 이전)
const DETAIL_DELAY_MS = 250;  // Cin7 rate limit 완화 (상세조회 간 간격)
const DEDUP_CHUNK = 50;       // dedup 조회 시 SaleID 묶음 크기 (URL 길이 보호)

// ── "확인했으나 비대상" 기억 (2026-08-11 — 회차당 상세조회 50→~6건 목표, wms_polled_sales) ──
// saleList 의 `Updated` 를 변경 트리거로 쓴다: 기억에 있고 + Updated 가 저장값과 **정확히 같고**
// (문자열 비교 — 파싱하면 .29Z/.290Z 형식 차이가 흡수돼 "다른데 같다" 오판) + 마지막 확인이 TTL 이내면
// 상세조회를 생략한다. ⚠️ Updated 는 신호가 아니라 트리거다 — "릴리즈됐다"가 아니라 "뭔가 바뀌었으니
// 읽어봐라"일 뿐, 판정(AdditionalAttribute1)은 언제나 상세조회가 한다. 무관한 수정(코멘트·주소·수량)으로
// 바뀌어도 헛읽기 1회뿐 = 낭비만, 누락 없음.
// ⚠️ TTL 은 순수 보험 — Updated 신호가 어떤 이유로든 실패해도 최대 1시간 안에는 반드시 다시 읽힌다
//    (조용한 영구 누락을 구조적으로 차단). 정상 작동하는 한 거의 발동하지 않는다(memory_ttl_expired 로 관측).
// ⚠️ 킬 스위치: 0 으로 두면 기억 조회·스킵·기록·정리 전부 비활성 = 현행 동작 복귀(상수 1줄 + 재배포).
const POLL_MEMORY_TTL_MS = 3600_000;
// 목록에서 빠진 오더(PICKED·CLOSED 등)의 기억 행 정리 기준. 활성 비대상 오더는 TTL 재확인 upsert 로
// checked_at 이 매시간 갱신되므로, 30일 미갱신 = 목록에서 빠진 지 오래 = 삭제 안전.
// ("목록에 없는 id 삭제" 방식은 truncated 회차에 대량 오삭제 위험이 있어 기각 — 시간 기준이 안전.)
const POLL_MEMORY_PURGE_MS = 30 * 86400_000;

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

// Cin7 sale 상세의 Reference 추출 (화면 "Reference" 필드 = API CustomerReference — 위 실측 주석 참고).
// 픽리스트 상단에 인쇄해 현장에서 고객 발주번호를 대조한다. 값 없으면 null → 인쇄에서 그 줄 생략.
function extractReference(d: any): string | null {
  const cands = [d?.CustomerReference, d?.Reference];
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
// upsert — ⚠️ 페이로드에 NOT NULL 전 컬럼을 실을 것 (NOT NULL 검사가 ON CONFLICT 해소보다 먼저 돈다
// — 2026-08-06 배치 upsert 프로덕션 실패). on_conflict 대상은 평범한 PK 만(부분 유니크는 깨진다 — 규칙 29).
async function sbUpsert(table: string, conflictCol: string, rows: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + table + "?on_conflict=" + conflictCol, {
    method: "POST",
    headers: sbHeaders({ Prefer: "resolution=merge-duplicates,return=minimal" }),
    body: JSON.stringify(rows),
  });
  if (!r.ok) throw new Error("sbUpsert " + table + " " + r.status + ": " + (await r.text()).slice(0, 400));
}
// 행 수 (HEAD + count=exact — 본문 없이 Content-Range 헤더로). 실패해도 회차를 깨지 않는다(null).
async function sbCount(table: string): Promise<number | null> {
  try {
    const r = await fetch(SB_URL() + "/rest/v1/" + table + "?select=*", {
      method: "HEAD", headers: sbHeaders({ Prefer: "count=exact" }),
    });
    const total = (r.headers.get("content-range") || "").split("/")[1];
    return total && total !== "*" ? Number(total) : null;
  } catch { return null; }
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

// "확인했으나 비대상" 기억 조회 — ⚠️ already_exists 를 통과한 후보만 대상(2026-08-11 사용자 조건:
// 조회량 110→51 — already_exists 는 앞에서 어차피 걸러진다). existingSaleIds 와 같은 청크 in.() 패턴.
async function polledMemory(saleIds: string[]): Promise<Map<string, any>> {
  const found = new Map<string, any>();
  for (let i = 0; i < saleIds.length; i += DEDUP_CHUNK) {
    const chunk = saleIds.slice(i, i + DEDUP_CHUNK);
    const inList = chunk.map((id) => '"' + id + '"').join(",");
    const rows = await sbGet(
      "wms_polled_sales?cin7_sale_id=in.(" + encodeURIComponent(inList) + ")&select=cin7_sale_id,cin7_updated,checked_at"
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

    // 1) 폴링: AUTHORISED 여러 페이지 수집
    //    ⚠️ 429 처리 (2026-08-04 실사고 — SO-14100·SO-14106 미유입): 예전엔 !ok 즉시 throw 라
    //    1페이지 성공 후 2·3페이지에서 429 를 맞으면 회차 전체가 500 으로 죽고, pg_cron 5분 주기 +
    //    같은 Cin7 계정을 쓰는 GAS 들 때문에 429 가 일상이라 뒤 페이지 오더가 영구히 유입되지 않았다.
    //    지금은 공용 cin7()(백오프 1.5s→3s, 상한 2회)로 재시도하고, 소진되면 throw 없이 그 회차를
    //    조기 종료해 앞 페이지 분량은 정상 처리한다. 429 외 4xx/5xx 는 기존대로 throw.
    //    ⚠️ 조용한 부분 스캔이 가장 위험 — rate_limited / rate_limited_at_page 로 반드시 노출한다.
    let candidates: any[] = [];
    let pagesScanned = 0;
    let listTotal: number | null = null;          // saleList 가 보고한 Total (잘림 감지용)
    let rateLimited = false;                       // 429 백오프 소진으로 조기 종료했으면 true
    let rateLimitedAtPage: number | null = null;   // 어느 페이지에서 끊겼는지
    for (let page = 1; page <= POLL_MAX_PAGES; page++) {
      let j: any;
      try {
        j = await cin7Get("/saleList?Limit=" + POLL_LIMIT + "&Page=" + page + "&OrderStatus=AUTHORISED");
      } catch (e: any) {
        if (Number(e?.status) === 429) { rateLimited = true; rateLimitedAtPage = page; break; }
        throw e;
      }
      if (j?.Total != null) listTotal = Number(j.Total);
      const batch = j?.SaleList ?? [];
      pagesScanned++;
      candidates = candidates.concat(batch);
      if (batch.length < POLL_LIMIT) break; // 마지막 페이지
    }

    // 스캔 범위 진단 — "안 들어온다" 를 dry-run 응답만으로 판정하기 위한 필드 (규칙 12).
    // saleList 는 오더번호 오름차순이라(실측 2026-08-04, 1페이지 = SO-11739~SO-14061)
    // newest_scanned 가 실제 최신 오더에 못 미치면 스캔 범위가 최신에 도달하지 못한 것.
    let oldestScanned: string | null = null;
    let newestScanned: string | null = null;
    for (const c of candidates) {
      const n = String(c?.OrderNumber ?? "").trim();
      if (!n) continue;
      if (oldestScanned === null || n < oldestScanned) oldestScanned = n;
      if (newestScanned === null || n > newestScanned) newestScanned = n;
    }

    // 2) PICKED 스킵 (우리 단계는 픽 이전)
    //    ⚠️ 제외 내역을 skipped_detail 에 남긴다 (2026-08-04: 제외 45건이 응답에 안 보여
    //    "안 들어온다" 진단을 GAS 로 손수 해야 했다. SKIP_PICKED 는 병행운영 케이스 (B),
    //    규칙 12 — "안 들어온다" 의 최빈 원인이라 노출 가치가 가장 크다.)
    const skipped: any[] = [];
    const notPicked: any[] = [];
    for (const c of candidates) {
      if (SKIP_PICKED && c.CombinedPickingStatus === "PICKED") {
        skipped.push({ order: c.OrderNumber, reason: "skip_picked", picking_status: c.CombinedPickingStatus });
      } else {
        notPicked.push(c);
      }
    }

    // 3) detail 조회 전 batch dedup — 이미 있는 건 상세조회 생략
    const idset = await existingSaleIds(notPicked.map((c) => String(c.SaleID)));
    const freshPre: any[] = [];
    for (const c of notPicked) {
      const ex = idset.get(String(c.SaleID));
      if (ex) skipped.push({ order: c.OrderNumber, reason: "already_exists", status: ex.status });
      else freshPre.push(c);
    }

    // 3b) "확인했으나 비대상" 기억 스킵 (2026-08-11 — 상수 주석·edge-function.md 폴링 절 참조)
    //     스킵 = 기억에 있고 AND Updated 정확 일치(문자열) AND 확인 TTL 이내. Updated 가 비면 항상 읽는다.
    //     ⚠️ 읽기(스킵 판정)는 dry-run·commit 공통 — dry-run 이 프로덕션 동작을 반영해야 한다.
    //     ⚠️ 개별 스킵 행은 skipped_detail 에 싣지 않는다(정상 스킵 40여 건이 매 회차 응답에 실릴 이유가
    //        없다 — 사용자 결정 2026-08-11). 카운트는 skipped_unchanged.
    //     ⚠️ 경합(설계상 허용): saleList 조회와 상세조회 사이에 릴리즈되면 목록의 Updated 가 옛값이라
    //        그 회차를 건너뛴다 — 다음 회차(≤5분)에 들어오므로 누락이 아니라 지연이다(edge-function.md).
    let skippedUnchanged = 0;
    let memoryTtlExpired = 0;
    let memset = new Map<string, any>();
    if (POLL_MEMORY_TTL_MS > 0 && freshPre.length) {
      memset = await polledMemory(freshPre.map((c) => String(c.SaleID)));
    }
    const fresh: any[] = [];
    const nowMs = Date.now();
    for (const c of freshPre) {
      const mem = memset.get(String(c.SaleID));
      const upd = String(c.Updated ?? "");
      if (mem && upd && String(mem.cin7_updated) === upd) {
        if (nowMs - Date.parse(mem.checked_at) < POLL_MEMORY_TTL_MS) { skippedUnchanged++; continue; }
        memoryTtlExpired++;   // 보험 발동 — Updated 는 같지만 TTL 만료라 읽는다 (0 에 가까워야 정상)
      }
      fresh.push(c);
    }

    // ⚠️ 상세조회는 최신 오더번호부터 (내림차순 — 2026-08-04 실사고 SO-14106).
    //    saleList 는 오더번호 오름차순인데, '2.Release to WMS' 가 아닌 오더는 저장되지 않아
    //    다음 회차에도 fresh 에 계속 남는다 → 오래된 비대상 오더들이 매 회차 MAX_DETAIL 예산을
    //    선점하면 뒤쪽(최신) 오더는 영구히 순번이 오지 않는다(굶주림). 우리가 필요한 것은
    //    방금 릴리즈된 최신 오더다. 규칙 20 purchaseList 오름차순 함정의 두 번째 사례.
    const orderNum = (c: any) => Number(String(c?.OrderNumber ?? "").replace(/\D/g, "")) || 0;
    fresh.sort((a, b) => orderNum(b) - orderNum(a));

    const inserted: any[] = [];
    const wouldInsert: any[] = [];
    const errors: any[] = [];
    let detailFetched = 0;
    let detailCapped = false;
    let detailCappedOrders: string[] = [];
    let detailRateLimited = 0;      // 상세조회 429 로 이번 회차 건너뛴 건수 (2026-08-11 — 종전엔 어디에도 안 남았다)
    const memoryUpserts: any[] = []; // "확인했으나 비대상" 기록 후보 — 회차 끝에 한 번에 upsert (commit 만)

    // 4) 남은 후보만 상세조회 (최신 우선)
    for (let fi = 0; fi < fresh.length; fi++) {
      const c = fresh[fi];
      if (detailFetched >= MAX_DETAIL) {
        detailCapped = true;
        // 캡에 잘린 오더를 응답에 노출 — 최신 우선 정렬이라 잘리는 건 가장 오래된 fresh 후보들.
        // ("확인했으나 비대상" 기억은 2026-08-11 도입 완료 — fresh 자체가 줄어 평시엔 캡이 안 걸려야 정상.
        //  이 목록이 다시 자라면 기억 스킵이 안 먹는다는 신호: skipped_unchanged·memory_ttl_expired 를 볼 것.)
        detailCappedOrders = fresh.slice(fi).map((x) => String(x?.OrderNumber ?? ""));
        break;
      }
      await sleep(DETAIL_DELAY_MS);
      const detResp = await fetch(CIN7_BASE + "/sale?ID=" + c.SaleID, { headers: cin7Headers() });
      // ⚠️ 429 스킵 오더는 **기억에 기록하면 안 된다**(안 읽은 것을 "확인했음"으로 기억하면 Updated 가
      //    다시 바뀔 때까지 영영 안 읽힌다) — 기록 지점이 상세 판정 뒤라 구조적으로 보장된다.
      //    60초 sleep 구조 자체는 이번 범위 밖(백로그 — detail_rate_limited 로 빈도를 먼저 관측).
      if (detResp.status === 429) { detailRateLimited++; await sleep(60000); continue; } // rate limit
      if (!detResp.ok) { errors.push({ order: c.OrderNumber, err: "detail " + detResp.status }); continue; }
      detailFetched++;
      const d = await detResp.json();

      const progress = d.AdditionalAttributes?.AdditionalAttribute1 ?? "";
      if (progress !== "2.Release to WMS") {
        // ⚠️⚠️ 기억 기록의 급소: **상세조회에 성공했고 + 판정 결과 비대상**일 때만 기록한다.
        //    조회 실패·429 스킵은 위에서 continue 로 빠져 여기 도달하지 못한다(구조적 보장).
        //    쓰기는 commit 만(dry-run 은 판정만) · cin7_updated 는 NOT NULL 이라 항상 싣는다(빈 값이면
        //    스킵 판정의 upd 검사가 어차피 항상 "읽기"로 떨어진다) · last_progress 는 진단 전용.
        if (commit && POLL_MEMORY_TTL_MS > 0) {
          memoryUpserts.push({
            cin7_sale_id: String(c.SaleID),
            order_number: String(c.OrderNumber ?? ""),
            last_progress: String(progress || "") || null,
            cin7_updated: String(c.Updated ?? ""),
            checked_at: new Date().toISOString(),
          });
        }
        continue; // 우리 큐만
      }

      const comments = extractComments(d);  // Cin7 sale 코멘트 → 픽리스트 표시용
      const priceTier = (d.PriceTier ?? "").trim() || null;  // 실측 확정(SO-13560): 최상위 PriceTier
      const reference = extractReference(d);  // 화면 Reference(=CustomerReference) → 픽리스트 표시용

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
          reference: reference,  // dry-run 에서 Reference 유입 확인
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
          order_date: (d.OrderDate || c.OrderDate || "").slice(0, 10) || null,
          order_progress: progress,
          cin7_status: d.Status ?? null,
          comments: comments,
          price_tier: priceTier,
          reference: reference,
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
        // 과거 비대상으로 기억됐던 오더가 릴리즈됐다 — 기억 행 정리 (best-effort: 실패해도 무해,
        // 다음 회차엔 already_exists 가 기억보다 먼저 거른다. 목적은 memory_rows 감시를 깨끗하게).
        if (POLL_MEMORY_TTL_MS > 0) {
          try { await sbDelete("wms_polled_sales?cin7_sale_id=eq." + encodeURIComponent(String(c.SaleID))); }
          catch { /* 무해 — 위 주석 */ }
        }
      } catch (e) {
        errors.push({ order: c.OrderNumber, err: String(e) });
      }
    }

    // ── "확인했으나 비대상" 기억 쓰기 + 정리 (commit 만 — dry-run 은 wms_orders 처럼 아무것도 안 쓴다) ──
    let memoryRows: number | null = null;
    if (POLL_MEMORY_TTL_MS > 0) {
      if (commit && memoryUpserts.length) {
        try { await sbUpsert("wms_polled_sales", "cin7_sale_id", memoryUpserts); }
        catch (e) { errors.push({ order: "(poll memory upsert)", err: String(e) }); } // 기록 실패 = 다음 회차에 다시 읽을 뿐
      }
      if (commit) {
        // purge: 30일 미갱신 = 목록에서 빠진 지 오래(활성 행은 TTL 재확인 upsert 가 매시간 checked_at 갱신).
        try { await sbDelete("wms_polled_sales?checked_at=lt." + encodeURIComponent(new Date(Date.now() - POLL_MEMORY_PURGE_MS).toISOString())); }
        catch (e) { errors.push({ order: "(poll memory purge)", err: String(e) }); }
      }
      memoryRows = await sbCount("wms_polled_sales");   // 무한 증식 감시 (실패 시 null — 회차는 계속)
    }

    return json({
      mode: commit ? "COMMIT" : "DRY-RUN (저장 안 함, ?commit=1 붙이면 저장)",
      pages_scanned: pagesScanned,
      // ── 스캔 범위 진단 (2026-08-04) — 이 여섯 개로 "안 들어온다" 즉시 판정 ──
      list_total: listTotal,                    // saleList 가 보고한 Total
      list_fetched: candidates.length,          // 실제로 받은 행 수
      truncated: listTotal == null ? null : candidates.length < listTotal, // 전량을 못 읽었으면 true
      oldest_scanned: oldestScanned,            // 스캔한 오더번호 범위
      newest_scanned: newestScanned,
      rate_limited: rateLimited,                // 429 백오프 소진으로 회차 조기 종료
      rate_limited_at_page: rateLimitedAtPage,  // 끊긴 페이지 (정상이면 null)
      candidates: candidates.length,
      after_skip_picked: notPicked.length,
      // skipped 배열에 skip_picked 도 들어가므로(2026-08-04) 기존 카운트 의미를 지키려면 reason 필터 필요
      already_exists: skipped.filter((s) => s.reason === "already_exists").length,
      fresh_candidates: fresh.length,
      // ── 기억 스킵 진단 (2026-08-11) — 기존 필드는 이름·의미 무변, 아래는 추가만 ──
      skipped_unchanged: skippedUnchanged,   // 기억(Updated 정확 일치 + TTL 내)으로 상세조회 생략한 건수
      memory_ttl_expired: memoryTtlExpired,  // Updated 는 같은데 TTL 만료로 읽은 건수 — 보험 발동 횟수(0 근처가 정상)
      memory_rows: memoryRows,               // 기억 테이블 행 수 (무한 증식 감시 · 조회 실패 시 null)
      detail_fetched: detailFetched,
      detail_rate_limited: detailRateLimited, // 상세조회 429 로 이번 회차 조용히 건너뛴 건수 (2026-08-11 — 종전엔 미노출)
      detail_capped: detailCapped, // true 면 이번 실행 상한 도달 (최신 우선이라 잘린 건 가장 오래된 fresh)
      detail_capped_orders: detailCappedOrders, // 캡에 잘린 오더 목록 — 굶주림 감시용 (2026-08-04)
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
