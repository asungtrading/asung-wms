// ============================================================
// ASUNG 재고 원장 — Edge Function: inv-snapshot (2026-08-17)
//   Cin7 ref/productavailability 전량 → inv_snapshot 기초 스냅샷 적재
//   설계 정본: docs/design/ledger-design.md · 스키마: 20260816000000_inv_ledger_tables.sql
// ------------------------------------------------------------
// 원장 계산의 출발점이다 — 현재 재고 = 스냅샷 + 그 이후 사건(inv_ledger).
// 한 번만 쓰는 것이 아니다: 원장이 틀어지면 새 snapshot_key 로 다시 찍고 처음부터
// 쌓는다. 그래서 snapshot_key 는 요청 파라미터 필수(자동 생성 금지 — 실수로 두 번
// 돌렸을 때 키가 달라지면 조용히 두 벌이 쌓인다. 같은 키 재실행은 아래 유니크 +
// ignore-duplicates 로 안전).
//
// ⚠️⚠️ 필드 의미 (프로브 18·19·20차 실측 — 틀리기 쉬움):
//   · OnHand      = 원장 기준 수량 → qty 에 넣는다
//   · StockOnHand = 수량이 아니라 **평가액** → value 에 넣는다
//     근거: KIMC-DSPLY01 OnHand=4 · StockOnHand=263.5228 = 4 × 65.88(BOM COST PER UNIT)
//   · Available   = OnHand − Allocated. 원장 대상 아님
//   · InTransit   = 창고이동과 무관 — OnOrder 와 같은 값(발주 잔량)
//
// ⚠️⚠️ 적재 대상 판정 (여기가 핵심):
//   · Bin 있음                     → 담는다
//   · Bin=null 이고 OnHand ≠ 0     → 담는다 (bin='' — ★ 빈 미지정 재고)
//   · Bin=null 이고 OnHand = 0     → 버린다
//   [실측] Bin≠null 만 담으면 11건이 통째로 누락된다(ASSH40608·KIMC-DSPLY01·PRO00124·
//   AIA0350x 계열 8건). Bin=null 행 8,296개 중 OnHand≠0 은 14개 — 그중 3건(SUN31504·
//   AS00879BLA·EBI03960)은 빈행도 함께 있다. **둘 다 담는다 — 합산이 맞다**: Bin=null
//   행은 집계행이 아니라 "빈 미지정 재고 자리"다(둘 다 있는 1,485개 중 1,482개(99.8%)가
//   null 행 0 = 재고가 전부 빈에 배치됨을 뜻한다).
//
// ⚠️ 같은 (sku, warehouse, bin) 원천 행은 insert 전에 **합산**한다 (2026-08-17 채택):
//   응답에 Batch·ExpiryDate 필드가 있어 배치 추적 상품이면 같은 SKU×빈이 여러 행으로
//   올 수 있다. 그대로 insert 하면 유니크 + ignore-duplicates 가 두 번째 행을 **조용히
//   버린다** — 원장이 경고하는 "조용한 누락" 그 부류다. merged_rows 가 0 이 아니면
//   그 자체가 새 사실(배치 그레인 실재)이니 응답에 반드시 남긴다.
//
// ⚠️ 창고는 Location 원문 그대로 담는다 — 하드코딩으로 거르지 않는다.
//   [실측] 실제로 나오는 것은 Asung Trading Inc.(13,016행) · Asung - Edmonton(9,117행)
//   둘뿐이고 Production Facility 는 행 자체가 없다(미사용 시스템 창고). 그래도 예상 밖
//   창고가 나오면 담되 응답에 경고로 보고한다(누가 실수로 재고를 넣으면 알아야 한다).
//   음수 재고도 같은 원칙(전수 0건이지만 거부하지 않고 담고 보고).
//
// all-or-nothing (product-images 원칙 이식): 수집이 불완전하면(429 조기 종료 ·
//   페이지 오류 · 수신≠Total) **한 행도 쓰지 않는다** — 부분 스냅샷은 원장의 출발점을
//   틀리게 만든다. 완전 수집 후 insert 도중 죽으면 같은 key 재실행이 수렴한다
//   (ignore-duplicates — 빠진 행만 채움). 사후 검증: existing_rows_before / db_rows_after.
//
// 동기 실행이다 (product-images 의 백그라운드와 다름 — 의도):
//   저쪽은 148페이지 3~4분 > 150초 idle timeout 이라 백그라운드가 필수였지만, 여기는
//   23페이지 · GAS 실측 61초 + insert ~28배치 ≈ 총 80초 안팎이라 동기로 안전하고,
//   **dry-run 요약을 응답으로 받는 것이 이 EF 의 검증 수단**이라 동기가 맞다.
//   시간 가드 120초 — 초과 시 쓰기 없이 중단 보고(aborted:"time").
//
// 인증: x-wms-cron-key == WMS_CRON_SECRET (hello 식 무인증 복제 금지 — 호출 1번 =
//   Cin7 23콜 증폭). 미설정이면 500 fail-closed.
//   ⚠️⚠️ product-images 와 WMS_CRON_SECRET 을 **공유한다**. 원장 쪽만 키를 돌려야
//   하면 INV_SNAPSHOT_SECRET 로 분리할 것 — 모르고 키를 바꾸면 이미지 동기화가
//   조용히 죽는다(cron 은 옛 키로 401 만 받는다).
//
// 하지 않는 것: Sku 파라미터(전량 조회다 — 참고: 그 파라미터는 전방 부분일치라 단건
//   조회 땐 정확일치 재필터가 필요하다. 여기선 무관) · UOM SKU 별도 필터(OnHand=0 이라
//   판정 규칙에서 자연히 빠진다. ⚠️ SKU 접미사 파싱 금지 — AMP41108-12 의 UOM 이
//   실제로 6인 실물 오류가 있다) · inv_ledger 무접촉 · cron 등록 없음(수동 실행 전용) ·
//   잔고 계산·뷰·트리거 없음 · wms_* 무접촉.
//
// 실행 (Caleb 직접 — 배포 후):
//   dry:  curl -s "…/functions/v1/inv-snapshot?dry=1&key=2026-08-22-initial" \
//           -H "x-wms-cron-key: $SECRET" | jq .
//   실적재: 같은 URL 에서 dry=1 제거.
//   기대값 대조(2026-08-16 실측): 담은 행 약 13,847 · Bin=null·OnHand≠0 목록 11~14건 ·
//   OnHand 합 토론토 1,812,735 · 에드먼턴 93,593.
//
// Cin7 HTTP 레이어는 _shared/cin7.ts 공용 — ⚠️ _shared 를 바꾸면 소비 함수
// (hello·receiving·product-images·inv-snapshot) 전부 재배포.
import { cin7Get, sleep } from "../_shared/cin7.ts";

const PAGE_LIMIT = 1000;         // [실측] 전량 22,133행 = 23페이지 · GAS 61초 · 페이지 상한 없음
const PAGE_SLEEP_MS = 400;       // 23콜은 한도 60/60 에 여유 — hello 폴링(회차 2~3콜)과 키를 공유해도 안전
const MAX_PAGES = 60;            // 폭주 방지 하드캡 (Total 이 60,000 을 넘으면 재검토 — truncated 가 신호)
const TIME_BUDGET_MS = 120_000;  // 동기 응답이라 150초 idle timeout 앞에서 우리가 먼저 끊는다(쓰기 없이)
const INSERT_BATCH = 500;        // GAS WmsSync INSERT_BATCH 와 동일 스케일
// [실측] 실제로 존재하는 창고 둘 — 이 목록은 "거르는" 데 쓰지 않는다. 벗어난 창고를
// unexpected_warehouses 로 **보고**하는 데만 쓴다(Production Facility 포함 — 나타나면 이상 신호).
const KNOWN_WAREHOUSES = new Set(["Asung Trading Inc.", "Asung - Edmonton"]);

const CORS: HeadersInit = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-wms-cron-key",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

// ── Supabase REST 헬퍼 (product-images 와 같은 형태 — service_role 자동주입) ──
const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SB_KEY = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
function sbHeaders(extra: Record<string, string> = {}): HeadersInit {
  return { apikey: SB_KEY(), Authorization: "Bearer " + SB_KEY(), "Content-Type": "application/json", ...extra };
}
// count-head — 행 0개, 개수만(PostgREST content-range). "넣었다는데 진짜 들어갔나"의 근거.
async function sbCount(table: string, filter: string): Promise<number> {
  const r = await fetch(SB_URL() + "/rest/v1/" + table + "?select=id&" + filter + "&limit=1", {
    method: "HEAD", headers: sbHeaders({ Prefer: "count=exact" }),
  });
  if (!r.ok) throw new Error("sbCount " + table + " " + r.status);
  const cr = r.headers.get("content-range") ?? "";      // 형태: "0-0/13847" 또는 "*/13847"
  const n = Number(cr.split("/")[1]);
  if (!Number.isFinite(n)) throw new Error("sbCount " + table + ": content-range 파싱 실패 '" + cr + "'");
  return n;
}
// insert — 유니크 (snapshot_key, sku, warehouse, bin) + ignore-duplicates = 같은 키 재실행 안전.
// ⚠️ 이 조합이 안전한 전제는 "insert 전 합산"이다(파일 상단 — 원천 중복은 여기 오기 전에 합쳐진다).
async function sbInsert(table: string, conflictCols: string, rows: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + table + "?on_conflict=" + conflictCols, {
    method: "POST",
    headers: sbHeaders({ Prefer: "resolution=ignore-duplicates,return=minimal" }),
    body: JSON.stringify(rows),
  });
  if (!r.ok) throw new Error("sbInsert " + table + " " + r.status + ": " + (await r.text()).slice(0, 400));
}

const round4 = (x: number) => Math.round(x * 10000) / 10000;

Deno.serve(async (req) => {
  const t0 = Date.now();
  const takenAtIso = new Date().toISOString();
  try {
    if (req.method === "OPTIONS") return json("ok" as unknown, 200, true);
    const url = new URL(req.url);

    // ── 인증 (fail-closed) ──
    const secret = Deno.env.get("WMS_CRON_SECRET") ?? "";
    if (!secret) return json({ ok: false, error: "WMS_CRON_SECRET not configured - refusing (fail-closed)" }, 500);
    if ((req.headers.get("x-wms-cron-key") ?? "") !== secret) {
      return json({ ok: false, error: "unauthorized" }, 401);
    }

    // ── 파라미터 ──
    const dry = url.searchParams.get("dry") === "1";
    let snapshotKey = (url.searchParams.get("key") ?? "").trim();
    if (!snapshotKey) {
      // dry 에도 요구한다 — 규칙 하나로 통일(자동 생성 금지의 연장).
      return json({ ok: false, error: "snapshot key required - pass ?key=2026-08-22-initial (no auto-generation)" }, 400);
    }
    // ── auto-compare (2026-08-24 · ⑥ 대조용 — 사용자 결정 Q-b(i)) ──
    // pg_cron URL 에 날짜를 박을 수 없어, 리터럴 'auto-compare' 일 때만 서버가 'YYYY-MM-DD-compare'
    // 를 생성한다. 「자동 생성 금지」의 원래 의도는 키가 실수로 겹치거나 의미 없는 값이 되는 것을
    // 막는 것 — 이것은 **명시적으로 요청한 자동화**라 취지에 어긋나지 않는다.
    // ⚠️ '-initial' 은 여전히 수동 명시만 — 기준선 재촬영은 사람이 키를 정해 실행한다.
    // ⚠️ 같은 날 재실행은 ignore-duplicates 라 **첫 실행 값이 남는다**(덮지 않음) — 대조 기준은
    //    "당일 첫 스냅샷"이고, 다시 찍고 싶으면 그 키의 행을 지우고 재실행.
    if (snapshotKey === "auto-compare") snapshotKey = takenAtIso.slice(0, 10) + "-compare";

    // ── 1) 수집: ref/productavailability 전량 페이징 ──
    let listTotal: number | null = null;
    let pagesScanned = 0;
    let receivedRows = 0;
    let rateLimited = false;
    let rateLimitedAtPage: number | null = null;
    let aborted: string | null = null;
    let abortNote: string | null = null;

    let keptSourceRows = 0;       // 판정 통과한 원천 행 수 (합산 전)
    let droppedZeroNoBin = 0;     // Bin=null & OnHand=0 — 버린 행
    let skippedNoSku = 0;         // SKU 빈 행 (방어 — 실측엔 없음)
    const nullBinNonzero: { sku: string; warehouse: string; onhand: number; value: number | null }[] = [];
    const negativeRows: { sku: string; warehouse: string; bin: string; onhand: number }[] = [];
    const unexpectedWh = new Map<string, number>();   // 창고명 → 행 수

    // 합산 그릇 — key = sku·warehouse·bin (구분자 \u0001)
    const agg = new Map<string, { sku: string; warehouse: string; bin: string; qty: number; value: number | null }>();

    for (let page = 1; page <= MAX_PAGES; page++) {
      // 시간 가드는 페이지 fetch 앞 — 어차피 완주 못 할 수집에 콜을 더 쓰지 않는다.
      if (Date.now() - t0 > TIME_BUDGET_MS) {
        aborted = "time";
        abortNote = "time budget " + TIME_BUDGET_MS + "ms exceeded at page " + page;
        break;
      }
      let j: any;
      try {
        j = await cin7Get("/ref/productavailability?Page=" + page + "&Limit=" + PAGE_LIMIT);
      } catch (e: any) {
        if (Number(e?.status) === 429) {
          // 백오프 소진 — throw 없이 조기 종료 + 보고 (조용한 부분 스캔이 가장 위험).
          rateLimited = true;
          rateLimitedAtPage = page;
          aborted = "rate_limited";
        } else {
          aborted = "page_error";
          abortNote = String(e?.message ?? e).slice(0, 300);
        }
        break;
      }
      pagesScanned++;
      if (j?.Total != null) listTotal = Number(j.Total);
      const batch = (j?.ProductAvailabilityList ?? []) as any[];
      receivedRows += batch.length;

      for (const row of batch) {
        const sku = String(row?.SKU ?? "").trim();
        if (!sku) { skippedNoSku++; continue; }
        const warehouse = String(row?.Location ?? "").trim();
        const bin = String(row?.Bin ?? "").trim();          // null → '' (스키마 NOT NULL DEFAULT '')
        const onHand = Number(row?.OnHand ?? 0);
        const value = row?.StockOnHand == null ? null : Number(row.StockOnHand);   // ⚠️ 평가액 — 수량 아님

        // 적재 대상 판정 (파일 상단 실측 규칙)
        if (bin === "") {
          if (onHand === 0) { droppedZeroNoBin++; continue; }
          // ★ 빈 미지정 재고 — 전체 목록으로 보고 (11~14건이라 짧다 — 눈으로 확인)
          nullBinNonzero.push({ sku, warehouse, onhand: onHand, value });
        }
        keptSourceRows++;

        if (onHand < 0) negativeRows.push({ sku, warehouse, bin, onhand: onHand });   // 담고 보고
        if (!KNOWN_WAREHOUSES.has(warehouse)) unexpectedWh.set(warehouse, (unexpectedWh.get(warehouse) ?? 0) + 1);

        // 합산 — 같은 (sku, warehouse, bin) 원천 행이 여럿이면(배치 그레인) qty·value 를 더한다.
        const k = sku + "\u0001" + warehouse + "\u0001" + bin;   // 구분자 없는 연결은 ("AB","C")/("A","BC") 충돌
        const cur = agg.get(k);
        if (cur) {
          cur.qty += onHand;
          if (value != null) cur.value = (cur.value ?? 0) + value;
        } else {
          agg.set(k, { sku, warehouse, bin, qty: onHand, value });
        }
      }

      if (batch.length < PAGE_LIMIT) break;   // 마지막 페이지
      await sleep(PAGE_SLEEP_MS);
    }

    // Total 대조 — 어긋나면 truncated (하드캡 도달·응답 잘림 어느 쪽이든).
    const truncated = listTotal == null ? null : receivedRows < listTotal;
    if (!aborted && (listTotal == null || truncated)) {
      aborted = "incomplete";
      abortNote = "received " + receivedRows + " of Total " + (listTotal ?? "?");
    }

    const mergedRows = keptSourceRows - agg.size;   // 0 이 아니면 그 자체가 새 사실(배치 그레인 실재)

    // ── 2) 요약 (창고별 — dry·실적재·중단 모두 이 요약을 낸다) ──
    const whAgg = new Map<string, { rows: number; skus: Set<string>; bins: Set<string>; onhand: number; value: number }>();
    for (const r of agg.values()) {
      let w = whAgg.get(r.warehouse);
      if (!w) { w = { rows: 0, skus: new Set(), bins: new Set(), onhand: 0, value: 0 }; whAgg.set(r.warehouse, w); }
      w.rows++;
      w.skus.add(r.sku);
      if (r.bin !== "") w.bins.add(r.bin);   // 빈 개수는 실제 빈만(빈 미지정 '' 제외)
      w.onhand += r.qty;
      w.value += r.value ?? 0;
    }
    const warehouses: Record<string, unknown> = {};
    for (const [name, w] of whAgg) {
      warehouses[name] = { rows: w.rows, skus: w.skus.size, bins: w.bins.size, onhand_sum: round4(w.onhand), value_sum: round4(w.value) };
    }

    const summary: Record<string, unknown> = {
      snapshot_key: snapshotKey,
      taken_at: takenAtIso,
      dry,
      pages_scanned: pagesScanned,
      list_total: listTotal,
      received_rows: receivedRows,
      truncated,
      rate_limited: rateLimited,
      rate_limited_at_page: rateLimitedAtPage,
      kept_source_rows: keptSourceRows,
      merged_rows: mergedRows,
      insert_rows: agg.size,
      dropped_zero_nobin: droppedZeroNoBin,
      skipped_no_sku: skippedNoSku,
      warehouses,
      null_bin_nonzero: nullBinNonzero,                       // 전체 목록 (11~14건 기대)
      negative_rows: negativeRows,                            // 있으면 이상 신호 (실측 0건)
      unexpected_warehouses: [...unexpectedWh].map(([name, rows]) => ({ name, rows })),   // 있으면 이상 신호
    };

    // ── all-or-nothing 관문: 수집 불완전이면 한 행도 쓰지 않는다 ──
    if (aborted) {
      summary.aborted = aborted;
      summary.abort_note = abortNote;
      summary.duration_ms = Date.now() - t0;
      return json({ ok: false, wrote: 0, ...summary }, 200);   // 부분 스냅샷은 원장의 출발점을 틀리게 만든다
    }

    if (dry) {
      summary.duration_ms = Date.now() - t0;
      return json({ ok: true, wrote: 0, ...summary });
    }

    // ── 3) 실적재: 사전 count → 500행 배치 insert → 사후 count ──
    // existing_rows_before > 0 = 같은 키 재실행(부분 insert 재개) 또는 키 재사용 실수 —
    // 어느 쪽인지 응답의 before/after 로 사람이 판정한다.
    const existingBefore = await sbCount("inv_snapshot", "snapshot_key=eq." + encodeURIComponent(snapshotKey));
    const rows = [...agg.values()].map((r) => ({
      snapshot_key: snapshotKey,
      taken_at: takenAtIso,
      sku: r.sku,
      warehouse: r.warehouse,
      bin: r.bin,
      qty: r.qty,
      value: r.value,
    }));
    let insertedBatches = 0;
    for (let i = 0; i < rows.length; i += INSERT_BATCH) {
      await sbInsert("inv_snapshot", "snapshot_key,sku,warehouse,bin", rows.slice(i, i + INSERT_BATCH));
      insertedBatches++;
    }
    const dbAfter = await sbCount("inv_snapshot", "snapshot_key=eq." + encodeURIComponent(snapshotKey));

    summary.existing_rows_before = existingBefore;
    summary.inserted_batches = insertedBatches;
    summary.db_rows_after = dbAfter;               // insert_rows 와 일치해야 정상 (재실행이면 수렴 확인)
    summary.duration_ms = Date.now() - t0;
    return json({ ok: true, wrote: dbAfter - existingBefore, ...summary });
  } catch (e) {
    // insert 도중 예외 = 부분 적재 가능 상태 — 같은 key 재실행이 수렴한다(ignore-duplicates).
    return json({ ok: false, error: String(e).slice(0, 500), duration_ms: Date.now() - t0 }, 500);
  }
});

function json(obj: unknown, status = 200, plain = false): Response {
  if (plain) return new Response(String(obj), { status, headers: CORS });
  return new Response(JSON.stringify(obj, null, 2), {
    status, headers: { "Content-Type": "application/json", ...CORS },
  });
}
