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
// 서버측 권한 게이트 (2026-08-13) — receiving 과 공용. ⚠️ 바꾸면 receiving 도 재배포.
// ⚠️⚠️ hold_recheck 액션에만 쓴다 — 폴링 경로(?commit=1)는 pg_cron 이 Bearer 접두어 없는
//    anon 키로 부르므로(verify_jwt=false 전제) 전역 게이트를 넣으면 오더 유입이 전면 중단된다.
import { hasApply, verifyCaller } from "../_shared/authgate.ts";

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

// ── 유입 오더 변경 감지 → 보류 (2026-08-12 · 규칙 43 — "실수로 오더가 진행되는 것을 막는" 안전장치) ──
// 유입된(already_exists) 오더는 상세를 다시 안 읽어 Cin7 On Hold 를 영원히 몰랐다(종전 갭).
// wms_orders.cin7_updated(유입 시점의 saleList.Updated)와 현재 목록의 Updated 를 비교(0콜) —
// 다르면 상세 재조회로 AdditionalAttribute1 판정. Updated 는 신호가 아니라 **트리거**다(판정은 상세만).
// ⚠️ wms_polled_sales 기억(미유입 전용)과 별개 — 유입 오더는 wms_orders.cin7_updated 가 기억 역할.
// ⚠️ 보류 트리거는 'On Hold' 하나뿐 — "2.Release 가 아닌 전부"로 잡으면 정상 완료 오더가 전부 보류가 된다.
//    예상 밖 값은 hold_state='unexpected' 로 admin 알림만(숨김·차단 없음 — 매니저 판단).
// ⚠️ 캡 굶주림 없음(self-draining): 판정 후 cin7_updated 를 갱신하므로 처리된 오더는 다음 회차 후보에서
//    자동 이탈 — 잘린 것은 다음 회차에 반드시 앞으로 온다(SO-14106 의 "영구 잔류" 구조와 반대).
//    정렬은 오더번호 내림차순(최신 우선 — 픽 임박 가능성이 높은 쪽 먼저). 잘린 수는 hold_check_deferred.
const HOLD_CHECK_MAX = 10;                  // 회차당 재조회 상한 (평시 후보 0~2건 — 초과 자체가 이상 신호)
const HOLD_RELEASE = "2.Release to WMS";    // 정상 값 — 이것으로 복귀하면 on_hold 는 재개 가능 표시(수동), unexpected 는 자동 해소
const HOLD_TRIGGER = "On Hold";             // 보류 트리거 — 이 값 하나뿐

// ── Cin7 void 감지 (2026-08-14 — 백로그 「Cin7 void 감지」 · 실사고 SO-14015 9일 방치) ──
// void 된 sale 은 OrderStatus 가 VOIDED 로 바뀌어 AUTHORISED 목록에서 **빠진다**(2026-08-14 GAS 실측)
// — hold 의 Updated 트리거는 "목록에 있는 행"만 보므로 구조적으로 못 본다. 반대 방향을 대조한다:
// WMS 활성 오더(closed/voided 제외 — hold 와 동일) 중 이번 회차 목록에 없는 것 = 사라짐 후보.
// ⚠️ 연속 2회차 완충(사용자 결정): 1회차 부재는 cin7_gone_missing_since 기록만, 2회차 부재만 확정
//    조회, 재등장하면 자동 해제. "없다"가 진짜 void 인지 목록 누락인지 구분할 방법이 없고,
//    오판의 대가(작업자가 멀쩡한 오더를 멈춤)가 크다. 5분 지연은 무관(SO-14015 는 9일 걸렸다).
// ⚠️ truncated/rate_limited 회차는 전면 스킵(후보 기록도 없음) — 목록이 불완전하면 "없다"가 오판이
//    된다(wms_polled_sales purge 가 "목록에 없는 id 삭제"를 기각한 것과 정확히 같은 함정).
// 판정은 확정 조회(saleList?Search=<order_number>)의 **Status='VOIDED'** 로만 —
// CombinedPickingStatus 는 케이스마다 갈린다(실측: SO-14613 NOT PICKED / SO-14015 PICKING).
// 확정에 상세 /sale 이 아니라 saleList Search 를 쓰는 이유: 필요한 것은 Status 하나뿐이고
// 목록 응답에 있다(AdditionalAttribute1 은 없지만 여기선 불필요).
// ⚠️ 감지만 자동 — status='voided' 전환은 매니저의 ⊘ Void 수동 실행만(마이그레이션 주석 참조).
const VOID_CHECK_MAX = 10;    // 회차당 확정 조회 상한 (HOLD_CHECK_MAX 와 같은 형태 — 평시 후보 0건, 08-14 실측 활성 27 중 0)
const VOID_ACTIVE_STATUSES = "pending,picking,packing,ready_to_close";

// ── bin 백필 스위프 (2026-08-31 — 유입 시점 sticky 미인지로 bin_location 이 빈 라인을 재해석) ──
// 왜: 유입(assembleLine)은 그 순간의 wms_sku_bins(전일 05:00 Cin7 → 06:30 재적재)만 본다.
//   저녁 유입 오더는 sticky 가 다음날 아침에야 배우는 자리를 영영 못 받는다([실측 2026-08]
//   한 달 52오더·~180줄 · SO-15071 세 줄 line_flag='no_bin' 으로 규명). 소비처(픽 화면·동선
//   정렬·픽리스트 Zones·packer·manager·원장 트랜스퍼 출발 bin)가 전부 이 컬럼을 읽으므로
//   화면 재조회 대신 여기(서버 — wms_order_lines 의 단일 쓰기 주체 유지)서 채운다.
// ⚠️ VOID_ACTIVE_STATUSES 재사용 금지 — packing 이후는 픽이 끝난 뒤라, 그때 채우는 값에는
//   「실제로 집은 자리」 보증이 없다(원장 다리가 이 컬럼을 트랜스퍼 출발 bin 으로 쓴다).
const BACKFILL_STATUSES = "pending,picking";
const BACKFILL_MAX_LINES = 40;   // 회차 캡 — 초과분은 자연 이월(채워진 라인이 is.null 필터에서 이탈 = self-draining)

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
async function sbPatch(path: string, body: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, {
    method: "PATCH", headers: sbHeaders({ Prefer: "return=minimal" }), body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error("sbPatch " + r.status + ": " + (await r.text()).slice(0, 300));
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
      // cin7_updated·hold_* 는 유입 오더 변경 감지용 (2026-08-12 규칙 43 — 같은 조회에 필드 추가라 0콜)
      "wms_orders?cin7_sale_id=in.(" + encodeURIComponent(inList) + ")&select=id,cin7_sale_id,order_number,status,cin7_updated,hold_state,hold_detected_at"
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

// ── bin 판정의 단일 출처 — 유입(assembleLine)과 백필 스위프가 같은 규칙을 쓴다 (2026-08-31) ──
// 규칙: 같은 warehouse + is_current=true 만, available 내림차순 — 첫 행이 primary.
// ⚠️ 조건을 한쪽만 바꾸면 유입과 백필이 같은 SKU 에 다른 bin 을 고른다 — 반드시 이 빌더를 거칠 것.
function skuBinsQuery(skuFilter: string, warehouse: string): string {
  return "wms_sku_bins?" + skuFilter + "&warehouse=eq." + warehouse + "&is_current=eq.true&order=available.desc";
}
// 정렬된(available desc) 행에서 SKU 별 첫 등장 행 = assembleLine 의 bins[0] 과 같은 선택 규칙의 배치판.
function primaryBinsBySku(rows: any[]): Map<string, any> {
  const m = new Map<string, any>();
  for (const r of rows ?? []) { const k = String(r?.sku ?? ""); if (k && !m.has(k)) m.set(k, r); }
  return m;
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
  const bins = await sbGet(skuBinsQuery("sku=eq." + encodeURIComponent(baseSku), warehouse));
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

// ── ?action=hold_recheck&order_id=N — admin 재개 버튼 (2026-08-12 · 규칙 43) ──
// Cin7 을 재확인한 뒤에만 해제한다: 매니저가 WMS 에서 재개했는데 Cin7 이 아직 On Hold 면 다음 폴링이
// 다시 보류로 되돌려 두 시스템이 싸운다 — "Cin7 을 먼저 풀고, 그걸 인지한 매니저가 재개를 허가한다".
// ⚠️⚠️ 이 분기는 이 레포 **첫 서버측 사용자 권한 게이트**였다(staff-create 의 /auth/v1/user 검증 패턴 이식).
//    ~~다른 EF 확대는 별건 백로그~~ → 2026-08-13 확대 완료: 게이트는 _shared/authgate.ts 로 추출됐고
//    receiving 도 같은 게이트를 쓴다(read=active 직원 / apply=admin·'apply'). 보류 해제가 매니저
//    권한이어야 하는 이유(재개는 신중해야 한다)는 불변.
async function holdRecheck(req: Request, url: URL): Promise<Response> {
  // ①② 호출자 검증 + 권한 — _shared/authgate.ts 로 추출 (2026-08-13, receiving 게이트와 공용).
  //    ⚠️ 종전엔 select 에 active 가 없어 비활성화된 admin 의 살아 있는 세션이 통과했다 — 이제 401.
  //    (staff-create 는 active 를 검사한다 — 두 게이트가 갈라져 있던 것을 이번에 통일.
  //     [실측 2026-08-13] 현재 wms_staff 전원 active=true 라 이 변경이 지금 막는 사람은 없다.)
  //    권한은 admin 역할 또는 perms 'apply' (기존 "신중한 조작" 권한 키 재사용 — 2026-08-12 사용자 결정).
  const s = await verifyCaller(req);
  if (!s) return json({ ok: false, error: "not signed in" }, 401);
  if (!s.active) return json({ ok: false, error: "account is inactive" }, 401);
  if (!hasApply(s)) {
    return json({ ok: false, error: "no permission - admin role or 'apply' permission required" }, 403);
  }
  // ③ Cin7 재확인 → 판정
  const oid = Number(url.searchParams.get("order_id"));
  if (!oid) return json({ ok: false, error: "order_id required" }, 400);
  const rows = await sbGet("wms_orders?id=eq." + oid + "&select=id,cin7_sale_id,order_number,hold_state");
  const o = rows[0];
  if (!o) return json({ ok: false, error: "order not found" }, 404);
  if (!o.hold_state) return json({ ok: true, released: true, note: "not held" });
  const dr = await fetch(CIN7_BASE + "/sale?ID=" + o.cin7_sale_id, { headers: cin7Headers() });
  if (!dr.ok) return json({ ok: false, error: "Cin7 read failed (" + dr.status + ") - try again" }, 502);
  const progress = String((await dr.json())?.AdditionalAttributes?.AdditionalAttribute1 ?? "");
  if (progress === HOLD_RELEASE) {
    // cin7_updated 는 여기서 갱신하지 않는다(목록 Updated 가 비교 기준 — 다음 폴링이 1회 재확인 후 스스로 갱신).
    await sbPatch("wms_orders?id=eq." + oid,
      { hold_state: null, hold_progress: null, hold_detected_at: null, hold_releasable_at: null, order_progress: progress });
    return json({ ok: true, released: true, progress, by: s.name });
  }
  // 여전히 보류/이상 값 — 차단 + 최신 값으로 갱신(admin 이 이유를 그대로 본다)
  const still = progress === HOLD_TRIGGER ? "on_hold" : "unexpected";
  await sbPatch("wms_orders?id=eq." + oid, { hold_state: still, hold_progress: progress });
  return json({ ok: true, released: false, progress, state: still });
}

Deno.serve(async (req) => {
  try {
    const url0 = new URL(req.url);
    // 재개 재확인 액션 — 폴링 본문과 독립 (규칙 43. OPTIONS 는 브라우저 preflight)
    if (req.method === "OPTIONS") return new Response("ok", { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" } });
    if (url0.searchParams.get("action") === "hold_recheck") return await holdRecheck(req, url0);
    const commit = url0.searchParams.get("commit") === "1";

    // 1) 폴링: AUTHORISED 여러 페이지 수집
    //    ⚠️ 429 처리 (2026-08-04 실사고 — SO-14100·SO-14106 미유입): 예전엔 !ok 즉시 throw 라
    //    1페이지 성공 후 2·3페이지에서 429 를 맞으면 회차 전체가 500 으로 죽고, pg_cron 5분 주기 +
    //    같은 Cin7 계정을 쓰는 GAS 들 때문에 429 가 일상이라 뒤 페이지 오더가 영구히 유입되지 않았다.
    //    지금은 공용 cin7()(2026-08-19 부터 Retry-After 기반 최대 60초 1회)로 재시도하고, 소진되면 throw 없이 그 회차를
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
    const holdCandidates: { c: any; ex: any }[] = [];   // 유입 오더 중 Updated 가 바뀐 것 (규칙 43 — 상수 주석)
    for (const c of notPicked) {
      const ex = idset.get(String(c.SaleID));
      if (ex) {
        skipped.push({ order: c.OrderNumber, reason: "already_exists", status: ex.status });
        // active 만 — WMS 종착(closed)·voided 는 어떤 값이 와도 무시(정상 종착이 3.Finalized 다).
        // cin7_updated null 도 후보(비교 불가 행이 영원히 감지에서 빠지지 않게 — 2026-08-12 사용자 지시).
        if (ex.status !== "closed" && ex.status !== "voided" &&
            (ex.cin7_updated == null || String(c.Updated ?? "") !== String(ex.cin7_updated))) {
          holdCandidates.push({ c, ex });
        }
      } else freshPre.push(c);
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
      // 배송 주소·결제 조건 → 픽리스트 표시용 (2026-08-30 · 필드 실측 GAS 프로브 SO-15505).
      // ⚠️ 유입 시점 값 — 이후 Cin7 에서 고쳐도 반영 안 됨(A안 확정 2026-08-30: 「주소 수정이 목록
      //   Updated 를 올리는지」 미확인이라, hold 재조회 patch 에 얹는 최신화는 다음 단계로 남겼다).
      const shipAddress = d.ShippingAddress ?? null;   // 객체 통째(jsonb) — 인쇄는 DisplayAddressLine1/2 두 줄, 원문 보존은 라벨 인쇄 대비
      const terms = String(d.Terms ?? "").trim() || null;

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
          terms: terms,          // dry-run 에서 Terms 유입 확인 (배포 직후 오더 유입을 안 기다리고 확인)
          ship_to: shipAddress ? [shipAddress.DisplayAddressLine1, shipAddress.DisplayAddressLine2].filter(Boolean).join(" / ") : null,  // 주소 요약 1줄 — 위와 동일 목적
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
          ship_address: shipAddress,   // ⚠️ 컬럼 추가 마이그레이션(20260830182524)이 이 EF 배포보다 먼저 (규칙 23)
          terms: terms,
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

    // ── 유입 오더 변경 감지 → 보류 판정 (2026-08-12 · 규칙 43 — 상단 상수 주석이 설계 정본) ──
    //    읽기(재조회·판정)는 dry-run·commit 공통(dry-run 이 프로덕션 동작을 반영), 쓰기는 commit 만.
    //    429 는 이번 회차 중단 — 후보는 cin7_updated 미갱신이라 다음 회차에 자연 재시도된다.
    let holdChecked = 0, holdDetected = 0, holdReleasableSeen = 0, holdUnexpected = 0;
    holdCandidates.sort((a, b) => orderNum(b.c) - orderNum(a.c));   // 최신 우선 — 기존 상세조회 원칙과 동일
    const holdDeferred = Math.max(0, holdCandidates.length - HOLD_CHECK_MAX);
    for (const { c, ex } of holdCandidates.slice(0, HOLD_CHECK_MAX)) {
      await sleep(DETAIL_DELAY_MS);
      const dr = await fetch(CIN7_BASE + "/sale?ID=" + c.SaleID, { headers: cin7Headers() });
      if (dr.status === 429) { detailRateLimited++; break; }   // 이번 회차 중단 — sleep(60000) 은 안 쓴다(후보는 자연 이월)
      if (!dr.ok) { errors.push({ order: c.OrderNumber, err: "hold check detail " + dr.status }); continue; }
      holdChecked++;
      const d = await dr.json();
      const progress = String(d.AdditionalAttributes?.AdditionalAttribute1 ?? "");
      const patch: Record<string, unknown> = { cin7_updated: String(c.Updated ?? ""), order_progress: progress };
      if (progress === HOLD_RELEASE) {
        if (ex.hold_state === "on_hold") {
          // 재개 가능 표시만 — 자동 복귀 금지(막는 건 자동·푸는 건 수동, 의도적 비대칭 — 규칙 43)
          patch.hold_releasable_at = new Date().toISOString(); holdReleasableSeen++;
        } else if (ex.hold_state === "unexpected") {
          // unexpected 는 아무것도 안 멈췄으므로 정상 복귀 확인 = 알림 자동 소멸 (on_hold 와 비대칭 — 의도)
          patch.hold_state = null; patch.hold_progress = null; patch.hold_detected_at = null; patch.hold_releasable_at = null;
        }
      } else if (progress === HOLD_TRIGGER) {
        patch.hold_state = "on_hold"; patch.hold_progress = progress; patch.hold_releasable_at = null;
        if (!ex.hold_detected_at) patch.hold_detected_at = new Date().toISOString();   // 최초 감지 시각 유지
        holdDetected++;
      } else {
        // 예상 밖 값 — 보류로 처리하지도, 무시하지도 않는다: admin 에 원문 그대로(숨김·차단 없음)
        patch.hold_state = "unexpected"; patch.hold_progress = progress; patch.hold_releasable_at = null;
        if (!ex.hold_detected_at) patch.hold_detected_at = new Date().toISOString();
        holdUnexpected++;
      }
      if (commit) {
        try { await sbPatch("wms_orders?id=eq." + ex.id, patch); }
        catch (e) { errors.push({ order: c.OrderNumber, err: "hold patch: " + String(e).slice(0, 200) }); }
      }
    }

    // ── Cin7 void 감지 (2026-08-14 — 상단 상수 주석이 설계 정본. 읽기 공통·쓰기 commit 만 — hold 와 동일) ──
    let voidActive = 0, voidCandidatesNew = 0, voidChecked = 0, voidDetected = 0,
        voidGoneOther = 0, voidCleared = 0, voidDeferred = 0;
    // 목록 완전성 가드 — Total 미보고도 불완전으로 취급(fail-safe: 판정 못 할 뿐 다음 회차에 본다)
    const voidSkippedUnsafe = rateLimited || listTotal == null || candidates.length < listTotal;
    if (!voidSkippedUnsafe) {
      // 활성 오더 조회 — 기존 dedup(existingSaleIds)은 목록의 SaleID 로 in.() 하므로 "목록에 없는
      // 오더"가 구조적으로 안 나온다 → Supabase REST 1콜 추가(활성 ~27행 · Cin7 콜 아님 — 08-11 예산 무접촉).
      const active = await sbGet(
        "wms_orders?status=in.(" + VOID_ACTIVE_STATUSES + ")" +
        "&select=id,order_number,cin7_sale_id,cin7_void_state,cin7_gone_missing_since");
      voidActive = active.length;
      // ⚠️ 대조 기준은 skip_picked **이전**의 전체 candidates — PICKED 오더도 목록엔 있다
      //    (notPicked 로 대조하면 Cin7 이 먼저 픽한 오더가 전부 "사라짐" 오탐).
      const presentIds = new Set(candidates.map((c: any) => String(c.SaleID)));
      const confirmQueue: any[] = [];
      for (const o of active) {
        if (!o.cin7_sale_id) continue;
        if (presentIds.has(String(o.cin7_sale_id))) {
          // 재등장 = 후보 해제. 확정(voided/gone_other) 뒤의 재등장도 자동 해제 — Cin7 에서
          // un-void 로 복귀한 것(unexpected 자동 해소와 같은 논리: 정상 복귀 확인 = 알림 소멸).
          if (o.cin7_gone_missing_since || o.cin7_void_state) {
            voidCleared++;
            if (commit) {
              try {
                await sbPatch("wms_orders?id=eq." + o.id,
                  { cin7_void_state: null, cin7_void_detected_at: null, cin7_gone_status: null, cin7_gone_missing_since: null });
              } catch (e) { errors.push({ order: o.order_number, err: "void clear: " + String(e).slice(0, 200) }); }
            }
          }
          continue;
        }
        if (o.cin7_void_state) continue;   // 이미 확정 — 매니저 처리 대기(⊘ Void 로 status 가 바뀌면 활성에서 이탈)
        if (!o.cin7_gone_missing_since) {  // 1회차 부재 — 기록만, 판정 안 함(완충 — 상수 주석)
          voidCandidatesNew++;
          if (commit) {
            try { await sbPatch("wms_orders?id=eq." + o.id, { cin7_gone_missing_since: new Date().toISOString() }); }
            catch (e) { errors.push({ order: o.order_number, err: "void mark: " + String(e).slice(0, 200) }); }
          }
          continue;
        }
        confirmQueue.push(o);              // 2회차 이상 부재 — 확정 조회 대상
      }
      // 확정 조회 — 최신 오더번호 우선 + 캡 + 429 는 회차 중단(후보는 자연 이월 — hold 와 동일)
      const voidOrderNum = (o: any) => Number(String(o?.order_number ?? "").replace(/\D/g, "")) || 0;
      confirmQueue.sort((a, b) => voidOrderNum(b) - voidOrderNum(a));
      voidDeferred = Math.max(0, confirmQueue.length - VOID_CHECK_MAX);
      for (const o of confirmQueue.slice(0, VOID_CHECK_MAX)) {
        await sleep(DETAIL_DELAY_MS);
        let sj: any;
        try {
          sj = await cin7Get("/saleList?Limit=10&Search=" + encodeURIComponent(String(o.order_number ?? "")));
        } catch (e: any) {
          if (Number(e?.status) === 429) { detailRateLimited++; break; }
          errors.push({ order: o.order_number, err: "void check: " + String(e).slice(0, 200) });
          continue;
        }
        voidChecked++;
        // Search 는 부분 일치 — OrderNumber 정확 일치 행만 인정
        const row = (sj?.SaleList ?? []).find((r: any) => String(r?.OrderNumber ?? "") === String(o.order_number ?? ""));
        const patch: Record<string, unknown> = {};
        if (!row) {
          // Search 에도 없음 = 문서가 통째로 사라짐(void 보다 이상한 상태) → NOT_IN_CIN7 로 확정
          // (사용자 결정 2026-08-14: 후보 유지 재시도는 매 회차 1콜이 영원히 나가고 아무도 모른다.
          //  값의 언더스코어 = "Cin7 원문이 아니라 우리가 붙인 값" 표식 — 다른 값은 Cin7 원문 대문자).
          patch.cin7_void_state = "gone_other"; patch.cin7_gone_status = "NOT_IN_CIN7";
          patch.cin7_void_detected_at = new Date().toISOString();
          voidGoneOther++;
        } else if (String(row.Status ?? "") === "VOIDED") {
          patch.cin7_void_state = "voided"; patch.cin7_gone_status = String(row.Status);
          patch.cin7_void_detected_at = new Date().toISOString();
          voidDetected++;
        } else if (String(row.OrderStatus ?? "") === "AUTHORISED") {
          // 여전히 AUTHORISED = 폴링 목록 누락 글리치였다 — 후보 해제 ("여전히 목록에 있음"의 판별식:
          // 무필터 Search 엔 FULFILLED 도 "있으므로" OrderStatus 로 가른다)
          patch.cin7_gone_missing_since = null;
          voidCleared++;
        } else {
          // AUTHORISED 필터에서 빠진 다른 종착(FULFILLED/CLOSED 등) — 표시만(숨김·차단 없음)
          patch.cin7_void_state = "gone_other"; patch.cin7_gone_status = String(row.Status ?? "");
          patch.cin7_void_detected_at = new Date().toISOString();
          voidGoneOther++;
        }
        if (commit) {
          try { await sbPatch("wms_orders?id=eq." + o.id, patch); }
          catch (e) { errors.push({ order: o.order_number, err: "void patch: " + String(e).slice(0, 200) }); }
        }
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

    // ── bin 백필 스위프 (2026-08-31 — 상단 BACKFILL_* 상수 주석이 설계 정본) ──
    // 회차 맨 끝 + 블록 전체 try/catch: 여기서 무엇이 죽어도 유입·hold·void 는 이미 끝나 있다.
    // Cin7 콜 0 (Supabase REST 만 — DETAIL_DELAY_MS·429 무관). dry-run 은 계획 카운트만(쓰기 0).
    // 관측: cron 은 응답을 안 읽으므로(pg_net 5초 타임아웃 — 규칙 12) 영구 창구는 결과물이다 —
    //   line_flag 에 no_bin 이 있는데 bin_location 이 채워진 라인 = 이 스위프의 서명.
    // ⚠️ line_flag('no_bin')·needs_review 는 무접촉 — flag 는 「유입 땐 몰랐다」는 기록이고,
    //   manager 분할 미리보기의 no_bin 칩과 채워진 bin 이 공존하는 것이 의도다(오해 아님).
    //   needs_review 잔존이 매니저 화면에서 거슬리는지는 배포 후 관찰로 판단(Caleb 확정 — 판단 대기).
    // 못 잡는 것: 당일 유입·당일 픽(sticky 가 아직 모르는 구간)·sticky 가 끝내 모르는 SKU —
    //   근본 해결은 WMS 픽 라인 bin 기록(별건).
    let backfillCandidates = 0, backfillFilled = 0, backfillUnresolved = 0,
        backfillSkippedPicked = 0, backfillCapHit = false;
    try {
      // ⚠️ !inner 필수 — 빠지면 부모 행이 남고 임베드만 null 이라 status 필터가 조용히 무력화된다
      //   ([실측 2026-08-14 packer] !inner 누락 = 조용히 틀림 / 임베드 자체가 빠지면 400 = 시끄럽게 죽음).
      const cand = await sbGet(
        "wms_order_lines?bin_location=is.null" +
        "&select=id,base_sku,order_id,wms_orders!inner(status,warehouse)" +
        "&wms_orders.status=in.(" + BACKFILL_STATUSES + ")" +
        "&order=id.asc&limit=" + BACKFILL_MAX_LINES);
      backfillCandidates = cand.length;
      backfillCapHit = cand.length === BACKFILL_MAX_LINES;   // 가득 = 더 있을 수 있음(다음 회차 자연 이월)
      if (cand.length) {
        // ⚠️ 이미 픽된 라인 제외 — 안내 없이 집은 자리를 모른 채 sticky 자리를 쓰면 원장 다리
        //   (wms_order_lines.bin_location → 트랜스퍼 출발 bin)에 보증 없는 값이 흐른다.
        //   pending 오더 라인은 픽 행 자체가 없어 자동 통과. 같은 order_line_id 의 분할 배치
        //   다중 행은 Set 이 흡수한다.
        const picked = new Set<number>();
        try {
          const pkRows = await sbGet(
            "wms_pick_task_lines?order_line_id=in.(" + cand.map((c: any) => c.id).join(",") + ")" +
            "&picked_base=gt.0&select=order_line_id");
          for (const r of pkRows) picked.add(Number(r.order_line_id));
        } catch (e) {
          // 픽 대조 실패 = 이번 회차 전체 skip (덜 채우는 쪽이 안전 — 픽 여부 모른 채 채우지 않는다)
          throw new Error("pick-check failed, sweep skipped this run: " + String(e).slice(0, 150));
        }
        const fillable = cand.filter((c: any) => !picked.has(Number(c.id)));
        backfillSkippedPicked = cand.length - fillable.length;
        // 창고별 배치 조회 — 유입과 같은 규칙(skuBinsQuery)·같은 선택(primaryBinsBySku = bins[0])
        const byWh: Record<string, any[]> = {};
        for (const c of fillable) {
          const wh = String(c.wms_orders?.warehouse ?? "");
          if (!wh) { backfillUnresolved++; continue; }
          (byWh[wh] = byWh[wh] || []).push(c);
        }
        for (const wh of Object.keys(byWh)) {
          const group = byWh[wh];
          const inList = [...new Set(group.map((c: any) => String(c.base_sku)))]
            .map((s) => '"' + s + '"').join(",");
          const rows = await sbGet(
            skuBinsQuery("sku=in.(" + encodeURIComponent(inList) + ")", wh) + "&select=sku,bin,zone,available");
          const primary = primaryBinsBySku(rows);
          for (const c of group) {
            const p = primary.get(String(c.base_sku));
            if (!p || !p.bin) { backfillUnresolved++; continue; }   // sticky 가 여전히 모름 — 비워둔다
            if (!commit) { backfillFilled++; continue; }             // dry-run: 채울 것 카운트만
            try {
              // ⚠️ null 가드는 서버측 URL 필터 — 경합 시 0행 매치(204)로 무해하게 진다
              await sbPatch("wms_order_lines?id=eq." + c.id + "&bin_location=is.null",
                { bin_location: p.bin, zone: p.zone ?? null });
              backfillFilled++;
            } catch (e) {
              errors.push({ order: "(backfill line " + c.id + ")", err: String(e).slice(0, 200) });
            }
          }
        }
      }
    } catch (e) {
      errors.push({ order: "(bin backfill sweep)", err: String(e).slice(0, 200) });
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
      // ── 유입 오더 변경 감지 진단 (2026-08-12 · 규칙 43) ──
      hold_checked: holdChecked,             // Updated 변경으로 재조회한 건수 (평시 0~2 — 계속 높으면 이상)
      hold_detected: holdDetected,           // 이번 회차 On Hold 판정
      hold_releasable_seen: holdReleasableSeen, // 보류 중인데 Cin7 이 2.Release 로 복귀한 것을 본 건수
      hold_unexpected: holdUnexpected,       // 예상 밖 값 (admin 알림 대상)
      hold_check_deferred: holdDeferred,     // 캡(HOLD_CHECK_MAX)에 밀린 건수 — 여러 회차 연속 >0 이면 캡 재검토
      // ── Cin7 void 감지 진단 (2026-08-14) ──
      void_skipped_unsafe: voidSkippedUnsafe, // truncated/rate_limited/Total 미보고 회차 — 감지 전면 스킵(오판 방어)
      void_active: voidActive,               // 대조한 WMS 활성 오더 수 (평시 ~27)
      void_candidates_new: voidCandidatesNew, // 이번 회차 1회차 부재로 기록만 한 건수
      void_checked: voidChecked,             // 2회차 부재로 확정 조회한 건수 (평시 0 — 계속 높으면 이상)
      void_detected: voidDetected,           // 이번 회차 VOIDED 확정
      void_gone_other: voidGoneOther,        // 다른 종착/NOT_IN_CIN7 로 확정 (표시만)
      void_cleared: voidCleared,             // 재등장으로 후보·확정 해제한 건수
      void_check_deferred: voidDeferred,     // 캡(VOID_CHECK_MAX)에 밀린 건수
      // ── bin 백필 스위프 진단 (2026-08-31) — 평시 전부 0 이 정상 (아침 6:30 재적재 후 첫 회차에 몰린다) ──
      backfill_candidates: backfillCandidates,        // 활성(pending·picking) 오더의 빈 bin 라인 수
      backfill_filled: backfillFilled,                // 채운 수 (dry-run 에선 "채울 것" 수)
      backfill_unresolved: backfillUnresolved,        // sticky 가 여전히 모름 — 비워둠 (당일 유입·이력 밖 부류)
      backfill_skipped_picked: backfillSkippedPicked, // 이미 픽된 라인 — 원장 보증이 없어 안 채움
      backfill_cap_hit: backfillCapHit,               // 캡(BACKFILL_MAX_LINES) 가득 — 잔여는 다음 회차 자연 이월
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
  // CORS 는 hold_recheck(브라우저의 admin 이 호출 — 2026-08-12)용. 폴링 응답(pg_cron)엔 무해.
  return new Response(JSON.stringify(obj, null, 2), {
    status, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}
