// ============================================================
// ASUNG WMS — Edge Function: product-images
//   Cin7 → wms_sku_snapshot.image_url 직결 (2026-08-14)
//   v2: EdgeRuntime.waitUntil 백그라운드 (같은 날 — 아래 "150초 실측 실패" 참조)
// ------------------------------------------------------------
// 배경 (2026-08-14 실사고): WMS 상품 사진이 7주 묵어 있었다(GHO57212 미표시 보고).
// BQ asung_product_images 가 Cin7 수동 export CSV 기반이라 사람이 3단계(Cin7 export →
// Drive 업로드 → GAS 실행)를 안 돌리면 조용히 늙는다 — 뿌리는 "묵은 것을 아무도
// 몰랐다"이다. 이 EF 는 Cin7 /product?IncludeAttachments=true 에서 대표 이미지
// (IsDefault=true)를 받아 wms_sku_snapshot.image_url 을 직접 덮어쓴다.
//
// ⚠️⚠️ 왜 백그라운드인가 — 150초 idle timeout 실측 (2026-08-14 첫 수동 실행):
//    동기 v1 은 148페이지(3~4분)를 다 돈 뒤에야 응답했고, 게이트웨이가
//    504 {"code":"IDLE_TIMEOUT","message":"Request idle timeout limit (150s) reached"}
//    로 끊었다. 이 150초는 "응답 바이트가 안 나온다" 제한이라 wall-clock 400초와 **별개**다.
//    [실측] 그 실패에서 wms_image_sync_runs 0행 · 스냅샷 무변 — all-or-nothing 이 작동했다.
//    → 대응 = 인증·쿨다운까지 동기로 검사(401/403/SKIPPED 는 즉시 응답) 후
//    **202 Accepted 를 즉시 반환**하고 수집~기록은 EdgeRuntime.waitUntil 백그라운드로.
//    백그라운드 수명은 Supabase 문서(background-tasks, 2026-08-14 열람) 기준
//    wall-clock·CPU·메모리 한도까지("The maximum duration is capped based on the
//    wall-clock, CPU, and memory limits") = 유료 400초 — 수집 ~210초가 넉넉히 들어가므로
//    페이싱(1100ms)·시간 가드(330초)는 v1 그대로다. cron 의 net.http_post 는 응답을
//    기다리지 않으므로 이 방식과 맞는다. **결과는 응답이 아니라 wms_image_sync_runs 로
//    확인한다**(성공·실패 모두 row 가 남는다 — 백그라운드는 클라이언트가 결과를 못 본다).
//    ⚠️ 로컬 serve 로 백그라운드를 테스트하려면 config.toml [edge_runtime]
//    policy = "per_worker" 가 필요하다(문서) — 전역 설정이라 바꾸지 않았고, 검증은 실서버에서.
//
// ⚠️ BQ 경로는 유지된다 (사용자 결정 2026-08-14 — 이중 안전):
//    WmsSync(GAS)가 매일 6:30(America/Toronto) 스냅샷을 truncate+재적재하며 BQ 이미지
//    (옛 값일 수 있음)를 다시 채운다 → 이 EF 는 그 **이후** 매일 재실행이 필수다.
//    "덮어쓴 값이 다음날 아침 BQ 값으로 되돌아갔다가 이 EF 가 다시 덮는다"가 정상
//    동작이고, EF 가 실패해도 옛 사진이 남는 것이 이중 안전의 취지다.
//    pg_cron 등록: supabase/ops/cron.sql 'wms-image-sync'(12:30 UTC) + 재시도(13:30 UTC).
//
// 원칙 3개 (어기면 이중 안전이 무너진다):
//  · all-or-nothing — 수집이 완전할 때만 쓴다(수신 == Total · 429 조기 종료 없음 ·
//    non-200 페이지 없음). 하나라도 어긋나면 **한 행도 쓰지 않고** 진단만 기록.
//    분할 실행(이어받기)은 만들지 않는다 — 중간 상태를 저장하는 순간 그게 곧
//    부분 갱신 경로가 된다. 백그라운드 400초 예산 안에 넉넉히 끝난다.
//  · 빈 값을 쓰는 경로가 없다 — Cin7 에 대표 이미지가 없는 SKU 는 행을 건드리지
//    않는다(BQ 유래 값 보존). 갱신 대상은 "대표 이미지가 있고 + URL 이 다른" 행만.
//  · 존재 필터 — 스냅샷에 있는 sku 만 upsert 한다. merge-duplicates 는 없는 행을
//    insert 하므로 필터 없이는 유령 행(base_sku null·factor 1)이 생긴다. 페이로드의
//    sku 는 **스냅샷 행의 원문**을 쓴다 — Cin7 쪽 대소문자가 달라도 INSERT 로 새는
//    경로가 원천 차단된다(이중 방어).
//
// 실측 (2026-08-14 GAS 프로브):
//  · 파라미터명 정확히 **IncludeAttachments** — IncludeAttachment/IncludeAll 은 빈 배열.
//    응답 키 Products(cin7-api product-master.md — ProductList 아님) · Attachments[] 에
//    {ID, ContentType, FileName, IsDefault, DownloadUrl}.
//  · Total 14,718 → 148페이지 · 페이지당 325ms·328KB.
//  · URL 은 DownloadUrl 이 아니라 **ID 로 조립**:
//    https://inventory.dearsystems.com/Product/Download?id=<Attachment ID>
//    (DownloadUrl 은 timeStamp 서명이 붙어 만료 위험 · 조립 URL 은 CSV 형태와 GUID
//     동일 실측 · <img> 표시 확인 2048x2048).
//  · ModifiedSince 는 증분 필터로 못 쓴다 — 재고 변동이 LastModifiedOn 을 올려
//    하루 4,010건 → 매번 전량 148콜. 대신 diff 로 변경 행만 쓴다.
//
// 인증 (hello 의 "폴링 무인증 + hold_recheck 게이트" 공존 구조와 동형 — 단 폴링식
// 무인증은 복제하지 않는다: 이 EF 는 호출 1번 = Cin7 ~150콜이라 hello 보다 429
// 증폭이 크다. 백로그 「보안」이 hello 를 이미 "429 남용 벡터"로 지적했다):
//  · cron 경로: x-wms-cron-key 헤더 == secret WMS_CRON_SECRET (verify_jwt=false —
//    config.toml). secret 미설정이면 500 fail-closed. ⚠️ 시크릿 실제 값은 레포에
//    절대 넣지 말 것 — supabase secrets set + 대시보드 cron 등록에만. 레포 공개
//    여부와 무관한 금지다: git 히스토리는 영구 · 발행 Pages 사이트는 private
//    레포여도 공개 · private = "접근 권한자가 본다". 2026-08-19 private 전환
//    시도·복귀 후에도 그대로 — 근거 정본은 asung-wms 스킬 「상품 이미지 파이프라인」 절.
//  · 수동 경로: ?force=1 + 로그인 JWT → verifyCaller/hasApply(쿨다운 우회).
//  · 쿨다운 20시간: 마지막 성공(ok=true)이 20시간 이내면 즉시 SKIPPED — 시크릿이
//    새도 증폭이 하루 1회로 갇히고, 재시도 cron(13:30)은 첫 실행 성공 시 자동 no-op.
//  · 인플라이트 가드(v2): 백그라운드가 3~4분 돌므로 같은 인스턴스에 두 번째 트리거가
//    오면 SKIPPED(in_flight). 모듈 스코프 플래그라 **다른 인스턴스 간 중복은 못 막는
//    best-effort** — 중복이 나도 쓰기는 멱등(같은 값 upsert)이고 Cin7 은 429 로
//    자기제한되므로 피해가 없다. 흔한 케이스(force 연타)를 값싸게 잡는 것이 목적.
//
// Cin7 HTTP 레이어는 hello·receiving 과 공용 (_shared/cin7.ts).
// ⚠️ _shared 를 바꾸면 세 함수(hello·receiving·product-images) 모두 재배포 — 파일 상단 주석 참조.
import { cin7Get, sleep } from "../_shared/cin7.ts";
import { hasApply, verifyCaller } from "../_shared/authgate.ts";

const PAGE_LIMIT = 100;          // /product 페이지 크기 (실측 148페이지 · Total 14,718)
const PAGE_SLEEP_MS = 1100;      // 선제 페이싱 — 분당 ~52콜 < 한도 60/60. ⚠️ cin7() 백오프는 2026-08-19 부터
                                 //   Retry-After 기반(최대 60초 1회 — 백로그 20번 해소)이나 여전히 최후 방어로만 —
                                 //   선제 페이싱이 주 수단이다(200 응답엔 x-ratelimit-* 이 없어 사전 제어 불가).
                                 //   백그라운드 예산 400초에 수집 ~210초가 들어가므로 줄일 이유가 없다(v2 조사).
const MAX_PAGES = 200;           // 폭주 방지 하드캡 (Total 이 20,000 을 넘으면 재검토 — truncated 가 신호)
const TIME_BUDGET_MS = 330_000;  // t0 기준. 초과 시 **쓰기 없이** 중단(aborted:"time") —
                                 //   receiving APPLY_TIME_BUDGET_MS 의 "쓰기 앞에서만 끊는다" 원칙과 동일.
                                 //   백그라운드도 wall-clock 400초(문서)에 종료된다 — 그 앞에서 우리가 먼저
                                 //   끊고 run row 를 남긴다(강제 종료는 row 를 못 남긴다). ⚠️ 문서의 400초가
                                 //   워커 수명 기준이면 t0 가드가 못 잡는 종료가 이론상 남는다 — 그 경우
                                 //   row 부재 → Health image_sync_stale(48h) 이 최후 신호(수용된 백스톱).
const SNAPSHOT_PAGE = 1000;      // 스냅샷 전량 읽기 페이지 (PostgREST 1000행 캡 — limit/offset 로 무관화)
const UPSERT_BATCH = 500;        // GAS WmsSync INSERT_BATCH 와 동일 스케일
const COOLDOWN_MS = 20 * 3_600_000; // 마지막 성공 후 20시간 내 cron 재실행 거부 (force=1 은 우회)
const RUNS_KEEP_DAYS = 90;       // wms_image_sync_runs 보존 — wms_health_runs(90일)와 동일
const DOWNLOAD_BASE = "https://inventory.dearsystems.com/Product/Download?id=";

const CORS: HeadersInit = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-wms-cron-key",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

// 인플라이트 가드 — 위 인증 절 주석 참조 (같은 인스턴스 한정 best-effort).
let running = false;

// 종료 통지 — 기록 fetch 는 종료 창에서 전달 보장이 없어 **로그만** 남긴다(채택 근거:
// 기록 보장은 330초 시간 가드의 몫이고, 여기서 쓰다 만 run row 가 더 헷갈린다).
addEventListener("beforeunload", (ev: any) => {
  if (running) console.warn("product-images: shutdown mid-run, reason=", ev?.detail?.reason ?? "?");
});

// ── Supabase REST 헬퍼 (hello 와 같은 형태 — service_role 자동주입) ──
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
async function sbPost(table: string, body: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + table, {
    method: "POST", headers: sbHeaders({ Prefer: "return=minimal" }), body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error("sbPost " + table + " " + r.status + ": " + (await r.text()).slice(0, 400));
}
async function sbDelete(path: string): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { method: "DELETE", headers: sbHeaders() });
  if (!r.ok) throw new Error("sbDelete " + r.status + ": " + (await r.text()).slice(0, 300));
}
// upsert — 스냅샷 존재 필터를 거친 행만 오므로 실질은 전부 UPDATE 다(유령 insert 없음).
// 페이로드는 {sku, image_url} 만 — synced_at 은 싣지 않는다("GAS 가 마지막으로 적재한
// 시각" 의미 보존). on_conflict 대상 sku 는 전체 PK (부분 유니크 아님 — 규칙 29 무관).
async function sbUpsert(table: string, conflictCol: string, rows: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + table + "?on_conflict=" + conflictCol, {
    method: "POST",
    headers: sbHeaders({ Prefer: "resolution=merge-duplicates,return=minimal" }),
    body: JSON.stringify(rows),
  });
  if (!r.ok) throw new Error("sbUpsert " + table + " " + r.status + ": " + (await r.text()).slice(0, 400));
}

// 실행 기록 1행 + 보존 정리(90일) — 둘 다 best-effort: 기록 실패가 실행을 막지 않는다.
// ⚠️ v2 부터 이 row 가 **결과를 보는 유일한 창구**다(백그라운드 응답은 아무도 못 본다).
// 기록이 계속 실패하면 Health image_sync_stale 이 48시간 뒤 warn 으로 드러낸다(조용히 안 죽는다).
async function recordRun(startedAtIso: string, ok: boolean, updated: number, errorNote: string | null, diag: unknown): Promise<boolean> {
  try {
    await sbPost("wms_image_sync_runs", {
      started_at: startedAtIso,
      finished_at: new Date().toISOString(),
      ok,
      updated,
      error_note: errorNote,
      diag,
    });
    // 보존 정리 — wms_health_snapshot() 의 "쓰기 지점에서 정리, 별도 정리 잡 없음" 패턴.
    try {
      await sbDelete("wms_image_sync_runs?started_at=lt." +
        encodeURIComponent(new Date(Date.now() - RUNS_KEEP_DAYS * 86_400_000).toISOString()));
    } catch (e) { console.warn("runs purge failed (무해):", String(e).slice(0, 200)); }
    return true;
  } catch (e) {
    console.warn("recordRun failed:", String(e).slice(0, 300));
    return false;
  }
}

// ── 백그라운드 본체: 수집 → all-or-nothing 관문 → 스냅샷 diff → upsert → run 기록 ──
// 어떤 사유로 죽든 run row 가 남아야 사후에 알 수 있다(백그라운드는 클라이언트가 결과를
// 못 본다) — 최상위 try/catch 가 ok=false + error_note 를 기록하고, finally 가 인플라이트를 푼다.
async function runSync(t0: number, startedAtIso: string, diag: Record<string, unknown>): Promise<void> {
  let updated = 0;   // 배치 도중 예외 시 catch 가 "여기까지 썼다"를 기록한다
  try {
    // ── 1) 수집: /product 전 페이지 (선제 페이싱 · 원문 비누적) ──
    let listTotal: number | null = null;
    let pagesScanned = 0;
    let productsSeen = 0;
    let withDefaultImage = 0;
    let noImage = 0;
    let noDefaultButHasAttachments = 0;   // 대표 미지정 — ⚠️ 경고 아님(2026-08-14 조사: 427건 중 426건이
                                          //   담당자 지정 누락(수정 완료), 1건은 사진이 필요 없는 변형 — 정상일 수 있는 상태)
    let defaultNotImage = 0;              // 대표가 image/* 아님(PDF 등) 또는 ID 없음 — 쓰면 멀쩡한 BQ 이미지를 깨진 URL 로 덮는다
    let duplicateCin7Sku = 0;             // Cin7 에 같은 SKU 가 둘 — 첫 것만 쓴다(한 upsert 배치에 같은 PK 2회는 PostgREST 에러)
    let rateLimited = false;
    let rateLimitedAtPage: number | null = null;
    let aborted: string | null = null;
    let abortNote: string | null = null;
    const cinImages: { sku: string; url: string }[] = [];
    const seenSku = new Set<string>();

    for (let page = 1; page <= MAX_PAGES; page++) {
      // 시간 가드는 반드시 페이지 fetch **앞** — 어차피 완주 못 할 수집에 콜을 더 쓰지 않는다.
      if (Date.now() - t0 > TIME_BUDGET_MS) {
        aborted = "time";
        abortNote = "time budget " + TIME_BUDGET_MS + "ms exceeded at page " + page;
        break;
      }
      let j: any;
      try {
        j = await cin7Get("/product?Page=" + page + "&Limit=" + PAGE_LIMIT + "&IncludeAttachments=true");
      } catch (e: any) {
        if (Number(e?.status) === 429) {
          // 백오프(Retry-After 기반 최대 60초 1회 — 2026-08-19 개정) 소진 — 회차 포기. 부분 수집으로는 쓰지 않는다(all-or-nothing).
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
      const batch = (j?.Products ?? []) as any[];
      for (const p of batch) {
        productsSeen++;
        const sku = String(p?.SKU ?? "").trim();
        if (!sku) continue;
        const atts = (p?.Attachments ?? []) as any[];
        if (!atts.length) { noImage++; continue; }
        const def = atts.find((a) => a?.IsDefault === true);
        if (!def) { noDefaultButHasAttachments++; continue; }
        // 대표가 이미지 파일이 아니거나 ID 가 없으면 조립 URL 이 <img> 에서 깨진다 — 건드리지 않는 쪽이 안전.
        if (!def.ID || !String(def.ContentType ?? "").toLowerCase().startsWith("image/")) { defaultNotImage++; continue; }
        const key = sku.toUpperCase();
        if (seenSku.has(key)) { duplicateCin7Sku++; continue; }
        seenSku.add(key);
        withDefaultImage++;
        // ⚠️ DownloadUrl 은 저장하지 않는다(timeStamp 서명 만료 위험) — ID 로 조립(실측 확인).
        cinImages.push({ sku, url: DOWNLOAD_BASE + String(def.ID) });
      }
      // batch/j 는 여기서 버려진다 — 148페이지 원문(~48MB)을 누적하면 256MB 한도 위험권(설계 조건).
      if (batch.length < PAGE_LIMIT) break;   // 마지막 페이지
      await sleep(PAGE_SLEEP_MS);
    }

    // 하드캡까지 돌았는데 안 끝났으면 수신 부족으로 아래 incomplete 판정에 걸린다.
    if (!aborted && (listTotal == null || productsSeen !== listTotal)) {
      aborted = "incomplete";
      abortNote = "received " + productsSeen + " of Total " + (listTotal ?? "?");
    }

    Object.assign(diag, {
      pages_scanned: pagesScanned,
      list_total: listTotal,
      truncated: listTotal == null ? null : productsSeen < listTotal,
      rate_limited: rateLimited,
      rate_limited_at_page: rateLimitedAtPage,
      products_seen: productsSeen,
      with_default_image: withDefaultImage,
      no_image: noImage,
      no_default_but_has_attachments: noDefaultButHasAttachments,
      default_not_image: defaultNotImage,
      duplicate_cin7_sku: duplicateCin7Sku,
    });

    // ── all-or-nothing 관문: 여기서 걸리면 Supabase 에 한 행도 쓰지 않는다 ──
    if (aborted) {
      const errorNote = aborted + (abortNote ? " - " + abortNote : "");
      diag.aborted = aborted;
      diag.abort_note = abortNote;
      diag.duration_ms = Date.now() - t0;
      // 실패도 기록한다(ok=false) — 쿨다운은 ok=true 만 보므로 재시도를 막지 않고,
      // 연속 실패는 Health image_sync_stale(48h) 이 warn 으로 끌어올린다.
      await recordRun(startedAtIso, false, 0, errorNote, diag);
      return;
    }

    // ── 2) 스냅샷 전량 읽기 (limit/offset · order=sku.asc — 1000행 캡 무관화) ──
    const snapBySku = new Map<string, { sku: string; image_url: string }>();
    let snapshotRows = 0;
    for (let offset = 0; ; offset += SNAPSHOT_PAGE) {
      const rows = await sbGet(
        "wms_sku_snapshot?select=sku,image_url&order=sku.asc&limit=" + SNAPSHOT_PAGE + "&offset=" + offset
      );
      snapshotRows += rows.length;
      for (const r of rows) {
        snapBySku.set(String(r.sku ?? "").trim().toUpperCase(), {
          sku: String(r.sku),                       // 원문 — upsert 페이로드에 이걸 쓴다(UPDATE 보장)
          image_url: String(r.image_url ?? ""),     // GAS 는 "사진 없음"을 '' 로 넣는다(null 아님)
        });
      }
      if (rows.length < SNAPSHOT_PAGE) break;
    }

    // ── 3) diff: 존재하고 + URL 이 다른 행만 ──
    let matched = 0;
    let unchanged = 0;
    let missingInSnapshot = 0;
    const missingSample: string[] = [];
    const changed: { sku: string; image_url: string }[] = [];
    for (const ci of cinImages) {
      const snap = snapBySku.get(ci.sku.toUpperCase());
      if (!snap) {
        // Cin7 에는 있는데 스냅샷에 없는 SKU — BQ 마스터와의 시차(신제품 등). 쓰지 않는다(존재 필터).
        missingInSnapshot++;
        if (missingSample.length < 8) missingSample.push(ci.sku);
        continue;
      }
      matched++;
      if (snap.image_url === ci.url) { unchanged++; continue; }
      changed.push({ sku: snap.sku, image_url: ci.url });
    }

    Object.assign(diag, {
      snapshot_rows: snapshotRows,
      matched,
      unchanged,
      missing_in_snapshot: missingInSnapshot,
      missing_sample: missingSample,
      to_update: changed.length,
    });

    // ── 4) 변경분만 배치 upsert (전부 기존 행 → 실질 UPDATE) ──
    for (let i = 0; i < changed.length; i += UPSERT_BATCH) {
      const batch = changed.slice(i, i + UPSERT_BATCH);
      await sbUpsert("wms_sku_snapshot", "sku", batch);   // 실패는 throw → catch 가 부분 진행(updated)을 기록
      updated += batch.length;
    }
    diag.updated = updated;
    diag.duration_ms = Date.now() - t0;

    // ── 5) 실행 기록 (쿨다운·Health·사후 조사가 전부 이 행을 본다) ──
    await recordRun(startedAtIso, true, updated, null, diag);
  } catch (e) {
    // 배치 도중 예외 = 부분 갱신 가능 상태 — 각 행은 올바른 값이고 재실행이 수렴한다(멱등).
    // "이미지가 사라지는" 방향의 실패는 없다(빈 값을 쓰는 경로 자체가 없음).
    diag.updated = updated;
    diag.duration_ms = Date.now() - t0;
    await recordRun(startedAtIso, false, updated, String(e).slice(0, 400), diag);
  } finally {
    running = false;
  }
}

Deno.serve(async (req) => {
  const t0 = Date.now();
  const startedAtIso = new Date().toISOString();
  const diag: Record<string, unknown> = {};
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    const url = new URL(req.url);
    const force = url.searchParams.get("force") === "1";

    // ── 동기 구간: 인증·쿨다운·인플라이트 — 거부는 즉시 응답으로 알린다(백그라운드로 넘기지 않는다) ──
    if (force) {
      // 수동 재실행 — hold_recheck 와 같은 게이트(authgate 공용). 쿨다운을 우회한다.
      const caller = await verifyCaller(req);
      if (!caller) return json({ ok: false, error: "not signed in" }, 401);
      if (!caller.active) return json({ ok: false, error: "account is inactive" }, 401);
      if (!hasApply(caller)) {
        return json({ ok: false, error: "no permission - admin role or 'apply' permission required" }, 403);
      }
      diag.by = caller.name;
    } else {
      const secret = Deno.env.get("WMS_CRON_SECRET") ?? "";
      // fail-closed: secret 미설정 상태로 무인증 개방이 되면 hello 폴링의 "429 남용 벡터"를 복제한다.
      if (!secret) return json({ ok: false, error: "WMS_CRON_SECRET not configured - refusing (fail-closed)" }, 500);
      if ((req.headers.get("x-wms-cron-key") ?? "") !== secret) {
        return json({ ok: false, error: "unauthorized" }, 401);
      }
      // 쿨다운 — 시크릿이 새도 증폭을 하루 1회로 가둔다. 재시도 cron(13:30)의 no-op 도 여기서 성립.
      // ok=true 만 보므로 실패한 실행은 재시도를 막지 않는다.
      const last = await sbGet("wms_image_sync_runs?ok=is.true&order=started_at.desc&limit=1&select=started_at");
      if (last[0] && Date.now() - Date.parse(last[0].started_at) < COOLDOWN_MS) {
        return json({ mode: "SKIPPED", skipped: "cooldown", last_ok_at: last[0].started_at });
      }
    }
    if (running) return json({ mode: "SKIPPED", skipped: "in_flight" });   // force 도 겹치기 실행은 무의미
    diag.mode = force ? "FORCE" : "CRON";

    // ── 백그라운드 발사 + 202 즉시 응답 (150초 idle timeout 회피 — 상단 v2 주석) ──
    const edgeRuntime = (globalThis as unknown as {
      EdgeRuntime?: { waitUntil(p: Promise<unknown>): void };
    }).EdgeRuntime;
    if (!edgeRuntime?.waitUntil) {
      // 조용한 동기 폴백 금지 — 폴백하면 504 IDLE_TIMEOUT 이 이유 없이 재발한다(fail-visible).
      return json({ ok: false, error: "EdgeRuntime.waitUntil unavailable - cannot run in background" }, 500);
    }
    running = true;
    edgeRuntime.waitUntil(runSync(t0, startedAtIso, diag));
    return json({
      accepted: true,
      started_at: startedAtIso,
      mode: diag.mode,
      by: diag.by,
      hint: "running in background - result lands in wms_image_sync_runs (ok/error_note/diag)",
    }, 202);
  } catch (e) {
    // 동기 구간(인증·쿨다운) 실패 — 수집을 시작하지 않았으므로 run row 는 안 남긴다.
    // (401 시도마다 row 를 남기면 그 자체가 쓰기 남용 벡터가 된다. 반복 실패는 stale warn 이 잡는다.)
    return json({ ok: false, error: String(e) }, 500);
  }
});

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj, null, 2), {
    status, headers: { "Content-Type": "application/json", ...CORS },
  });
}
