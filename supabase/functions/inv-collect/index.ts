// ============================================================
// ASUNG 재고 원장 — Edge Function: inv-collect ②-a (2026-08-17)
//   수집 6종 — 전량 축 3종(조정·이동·조립, 문서번호 커서) + 증분 축 3종(판매·발주·반품,
//   날짜 커서 · ②-b 2026-08-17) — dry 기본
//   설계 정본: docs/design/ledger-design.md · 스키마: 20260816000000_inv_ledger_tables.sql
// ------------------------------------------------------------
// ⚠️ 이 단계는 쓰지 않는다. **기본이 dry** 이고 ?commit=1 없이는 어떤 쓰기(원장·커서)도
//   없다. 산출물은 "무엇이 몇 행 들어갈 것인가"를 보여주는 응답 — 원장이 쌓이기 전에
//   로직을 검증하기 위한 것이다(쓰기는 ⑤에서 켠다). 판매·발주·반품은 ②-b.
//
// ⚠️⚠️ 조정 두 배열의 규칙이 다르다 — 섞으면 원장 전체가 틀린다 (프로브 실측):
//   · ExistingStockLines → adjust_existing · qty_delta = Adjustment − QuantityOnHand
//     근거 ST-00755: OnHand=60 · Adjustment=110 → 화면 VARIANCE = +50.
//     즉 Adjustment 는 **조정 후 목표 수량**이지 증감분이 아니다.
//   · NewStockLines      → adjust_new      · qty_delta = Quantity (그대로 증가분)
//     QuantityOnHand 자체가 없고 UnitCost 가 있다.
//   ⚠️ 필드명 이중 형태 방어: cin7-api 레퍼런스(stock.md)는 같은 배열을
//   Quantity(당시)/AdjustedQuantity(목표)로 기록한다 — 프로브 실측(Adjustment/
//   QuantityOnHand)과 이름이 다르다. 실측을 1순위로 읽고 레퍼런스 형태를 폴백으로
//   두되, 폴백 발동은 field_fallbacks 로 **시끄럽게 보고**한다(dry-run 이 실제
//   형태를 드러낸다 — 조용한 폴백은 틀린 가정을 영구화한다).
//
// ⚠️⚠️ 창고이동은 한 라인 = 원장 4행 (실측 TR-00709 — Out 1/12=DepartureDate ·
//   In 1/22=CompletionDate, 9/9 일치):
//     1 transfer_out From창고/빈   −Q  DepartureDate
//     2 transfer_in  IN_TRANSIT    +Q  DepartureDate
//     3 transfer_out IN_TRANSIT    −Q  CompletionDate
//     4 transfer_in  To창고/빈     +Q  CompletionDate
//   CompletionDate 없으면(IN TRANSIT) 1·2만 — 3·4는 도착 후 회차에서 생긴다.
//   같은 창고 안 이동(97%)도 4행 그대로(분기 없음 — 코드 단순 + 자리 단위 승격 때 동형).
//   IN_TRANSIT 행의 bin='' · warehouse='IN_TRANSIT'(합성값 — 언더스코어 관례).
//
// ⚠️⚠️ 창고 판정은 문자열 파싱 금지 — ref/location 전량(2,676행·3페이지)으로 ID 맵:
//   ParentID 없는 행 = 창고(실측 3개·2단 트리) · 빈의 ParentID 는 항상 창고(예외 0건).
//   "Asung - Edmonton: EG020104" 콜론 파싱은 이름이 바뀌면 조용히 깨진다 — 안 한다.
//   맵에 없는 ID 는 버리지 않고 이름 문자열 폴백(없으면 UNMAPPED(<id>)) + 전역 경고.
//   ⚠️ commit 에서는 UNMAPPED 가 하나라도 있으면 그 소스 전체를 쓰지 않는다(사용자
//   조건 2026-08-17) — warehouse 에 UNMAPPED 가 들어가면 원장에 영구히 남고, 나중에
//   맵을 고쳐도 이미 쓴 행은 안 바뀐다.
//
// 커서 (inv_sync_state.last_cursor — 문서번호 **문자열 그대로** 저장, 비교만 숫자):
//   ⚠️ "마지막 처리 번호보다 큰 것만"을 그대로 구현하면 IN TRANSIT 이동의 3·4행이
//   영영 안 생긴다(커서가 지나가면 재방문 불가) — 커서는 **비종결 문서(IN TRANSIT·
//   DRAFT 등)를 만나면 그 앞에서 멈춘다**: "그 이하 문서가 전부 종결 상태인 최대 번호"
//   까지만 전진. 잡힌 구간의 종결 문서는 회차마다 재방문되지만 유니크 키 +
//   ignore-duplicates 가 중복을 막는다. 번호는 Cin7 자동 부여·수동 변경 불가(사용자
//   확인) — 변경은 새 번호가 되므로 놓치지 않는다. ⚠️ dry 는 커서를 옮기지 않는다.
//
// 커서 하한(floor · 2026-08-17 보완 — 첫 dry 실사고): DepartureDate 없는 초기 트랜스퍼
//   TR-00012~76 40건이 커서 앞에서 hold 되며 캡 40을 정확히 소진 — 뒤 ~3,000건이 한 건도
//   안 보였다(since 는 커서 정지를 못 푼다). → state 커서가 없을 때 ?from_cursor= 가 시야
//   하한이 된다: 그 이하 문서는 후보 제외(skip_before_floor). 원장은 스냅샷 이후만 쌓으므로
//   그 이전 문서는 볼 이유 자체가 없다. ⚠️ 하한은 옛 데이터를 안 보는 것이지 이상 감지를
//   끄는 것이 아니다 — 하한 이후의 날짜 결손·DRAFT 는 여전히 커서를 막는다(그게 맞다).
//   ⚠️ floor 는 커서 시작점이 되어 commit(⑤)에서 last_cursor 초기값으로 영속된다 — 그 이하
//   문서는 영영 안 본다(의도). 다시 보려면 inv_sync_state.last_cursor 를 손으로 되돌릴 것.
//
// 상세 조회 캡 (동기 EF 의 물리 제약): 커서·since 없는 첫 dry 는 후보 5,298건 =
//   상세 90분이라 불가능 → 목록 레벨(번호>커서·상태·since)로 후보를 좁히고
//   MAX_DETAIL_PER_SOURCE 캡 + **오름차순**(커서 무결성 — 건너뛰기 없음. 규칙 12 의
//   내림차순 교훈은 "비대상 잔류 굶주림"이 원인이었고 여기는 커서가 전진한다).
//   잘리면 detail_capped 를 **시끄럽게** 보고 — 조용하면 "적게 나온 게 정상"으로
//   오해한다. 검증 플로우(only=+since=)에선 후보가 작아 캡에 안 걸린다.
//
// 같은 문서 안 동일 유니크 키 라인은 **합산** + merged_lines 보고 (①스냅샷 합산과
//   같은 논리 — ignore-duplicates 의 조용한 소실 방지). ⚠️ merged_lines ≠ 0 은
//   line_ref=ProductID 가정("같은 SKU 두 줄 없음 — 실무 검증")이 깨졌다는 신호다.
//
// since 경계 아티팩트(알고 시작): 스냅샷 이전 출발·이후 도착 이동은 1·2행이 since 에
//   걸러져 IN_TRANSIT 이 음수로 남는다 — 스냅샷(productavailability)에 IN_TRANSIT
//   행이 없으므로 구조적으로 맞는 결과이고 ⑥ 대조의 설명 항목이다.
//
// 조립 날짜 미확정: FG-00110 의 실제 이동일은 2026-08-06(오더 생성 시점)인데 어느
//   필드인지 미확인 → occurred_on 은 잠정 CompletionDate, 응답 date_candidates 에
//   문서별 Date(목록)/CompletionDate/WIPDate 3종을 나란히 보고(Caleb 이 보고 확정).
//   [2026-08-17 dry 실측] 40건 전부 3값 동일 — 구별 불가·실질 위험 낮음. CompletionDate 유지.
//
// 조립 필드 실측 (2026-08-17 dry 실사고 2건 — 프로브 8·11차와 합치):
//   · 목록 배열 키 = FinishedGoods("FinishedGoodsList" 아님) · 문서번호 = AssemblyNumber
//     (Number/StocktakeNumber 폴백 체인이 전부 "" 를 내 커서 정지 + 유니크 키 붕괴 직전)
//   · PickLines 의 상품 코드 = ProductCode(SKU 필드 없음 — sku 가 전부 "" 로 들어갈 뻔)
//
// 빈 이동 날짜 대체 (2026-08-17 보완 2 — 구조적): Cin7 WMS 모바일 빈 이동은 DepartureDate
//   없는 트랜스퍼를 만든다(우리 WMS 에 빈 이동 기능이 없어 계속 발생 — 규칙 33 백로그).
//   같은 창고 + LastModifiedOn 있으면 대체 후 기록(창고 잔고 ±0 이라 무영향 · raw 에
//   date_substituted 표기), **창고간은 여전히 hold**(잔고가 움직이는데 시점 불명 = 진짜 이상).
//
// ══ ②-b 증분 축 3종 (판매·발주·반품 — 날짜 커서) ══
// 커서가 다르다: ②-a 는 문서번호(전량 수신 후 번호로 거름), ②-b 는 **시각** —
//   목록을 UpdatedSince 로 받는다. UpdatedSince = last_cursor − 1일(⚠️ 겹치게 받는다 —
//   경계 유실 방지, 중복은 유니크 키가 흡수). state 없으면 ?from_since=, 둘 다 없으면
//   전량 + since_alert. **문서 상태로 커서를 멈추지 않는다** — 미완료 문서는 갱신되면
//   UpdatedSince 에 다시 잡힌다(②-a 의 "비종결 정지"는 여기 해당 없음).
// ⚠️ 캡 회차 커서 보정(2026-08-17 채택 — 명세 결함 정정): 캡 회차에 커서를 회차 시작
//   시각으로 옮기면 캡 밖 후보가 **영영 유실**된다(다시 갱신되지 않는 한 재등장 안 함 —
//   판매는 하루 40~90 오더라 캡 40 초과가 일상). → 후보를 목록 Updated **오름차순**으로
//   처리하고, 캡 회차만 커서 = 마지막 처리 문서의 Updated(다음 회차가 이어받음 — ②-a 의
//   "커서가 캡 앞에서 멈춤"과 동형). Updated 필드는 소스별 명시: sale=Updated(hello 실측) ·
//   purchase=LastUpdatedDate(리시빙 관문 실측) · creditnote=Updated(추정 — 폴백 보고).
// · 판매: VOIDED·비 SHIPPED 제외(⚠️ 배송 전엔 재고가 안 빠진다 — 픽·팩은 Allocated 일 뿐).
//   fulfilment 단위 처리 — Ship.Lines 의 ShipmentDate(IsShipped true 만)가 원장 날짜
//   (실측 3/3 일치) · Pick.Lines 가 실제 나간 SKU·수량(−).
//   ⚠️ line_ref = <fulfilment TaskID>:<ProductID> — occurred_on 이 유니크 키에 없어 분할
//   출하에서 같은 SKU·같은 bin 이면 키가 완전히 겹쳐 두 번째 출고가 조용히 버려진다.
//   TaskID 는 재수집에도 안정(인덱스는 fulfilment void·재정렬에 흔들린다).
// · 발주: VOID·IsServiceOnly·StockReceivedStatus 없음/NOT AVAILABLE 제외. 상세가 갈린다 —
//   Type 에 Advanced 포함 → advanced-purchase?ID=(StockReceived **배열**) / 아니면
//   purchase?ID=(**객체 하나**). 블록 Status=DRAFT 제외(실측: PO-01083 DRAFT 194개 재고에
//   없음) · 빈 문자열 Status 는 처리(실측 PO-01128 — 재고 들어감, 건수만 보고).
//   날짜 = Lines[].Date(실측 4/4 — 라인 단위라 분할 입고도 정확). line_ref 는 다른 소스와
//   통일해 ProductID(CardID 라는 진짜 라인 식별자는 raw.line 원문에 남는다).
// · 반품: 목록 = saleCreditNoteList(배열 키 **SaleList** — 실측). CreditNoteStatus
//   VOIDED/NOT AVAILABLE·RestockStatus 비 AUTHORISED 제외. 상세 sale?ID= 의 CreditNotes[]
//   **전부 순회**(한 오더에 여러 개 — 실측 SO-00062). DRAFT CN 은 Restock 이 비어 있다
//   (금액만 — 재고 미복귀). ⚠️ doc_number = **CreditNoteNumber**(오더번호 아님 — 다중 CN 이
//   유니크 키를 깬다). 날짜 = CreditNoteDate.
//
// 하지 않는 것: /transactions(창고내 이동 94%가 회계 분개 없음 — 실측) ·
//   Movements(날짜 필터 없음·SKU 단위 — 검증 전용) · 콜론 파싱 · SKU 접미사 파싱
//   (AMP41108-12 의 실단위 6 실물 오류) · 판매/발주/반품(②-b) · cron·뷰·트리거 ·
//   wms_* 무접촉.
//
// 인증: inv-snapshot 과 동일 — x-wms-cron-key == WMS_CRON_SECRET · 미설정 500
//   fail-closed. ⚠️ product-images·inv-snapshot 과 시크릿 공유(분리하려면
//   INV_SNAPSHOT_SECRET 계열 — inv-snapshot 주석 참조).
//
// 실행 (Caleb 직접 — 배포 후):
//   curl -s "…/functions/v1/inv-collect?only=adjustment&since=2026-08-10" \
//     -H "x-wms-cron-key: $SECRET" | jq .
//   → &only=transfer → &only=assembly → 전체(only 없이) 순.
//   기대 감각: 조정 전체 1,201·최근 7일 31·하루 10건 안팎 / 이동 전체 3,977·97% 창고내 /
//   조립 전체 120·대부분 VOIDED.
//
// Cin7 HTTP 는 _shared/cin7.ts 공용 — ⚠️ _shared 를 바꾸면 소비 함수 전부 재배포.
import { cin7Get, sleep } from "../_shared/cin7.ts";

const COLLECTOR_VERSION = "inv-collect@2026-08-17.4";   // raw 에 박는다 — 규칙이 바뀌면 올릴 것 (.4 = ②-b 증분 축 3종)
const LIST_PAGE_LIMIT = 1000;
const MAX_LIST_PAGES = 12;             // 실측 2/4/1 페이지 — 성장 대비 하드캡(truncated 가 신호)
const LIST_SLEEP_MS = 400;
const DETAIL_SLEEP_MS = 700;           // 한도 60/60 공유(hello 폴링 회차 2~3콜) 고려
const MAX_DETAIL_PER_SOURCE = 40;      // 동기 EF 시간 제약 — 잘리면 detail_capped 로 시끄럽게 보고
const TIME_BUDGET_MS = 120_000;        // inv-snapshot 과 동일 — 150초 idle timeout 앞에서 먼저 끊는다
const INSERT_BATCH = 500;
const IN_TRANSIT = "IN_TRANSIT";       // 합성 창고 — 언더스코어 = "Cin7 원문 아님" 표기
const KNOWN_WAREHOUSES = new Set(["Asung Trading Inc.", "Asung - Edmonton"]);
// 유니크 키 = 마이그레이션 inv_ledger_event_uq 와 동일 순서 (on_conflict 대상)
const LEDGER_CONFLICT = "doc_type,doc_number,line_ref,event_type,warehouse,bin,sku";

type LedgerRow = {
  occurred_on: string; seq_hint: number; sku: string; warehouse: string; bin: string;
  qty_delta: number; event_type: string; doc_type: string; doc_number: string;
  doc_task_id: string | null; line_ref: string; amount: number | null; source: string;
  raw: Record<string, unknown>;
};

// 소스 3종 설정 — 목록 응답 배열 키는 실측: StockAdjustmentList·StockTransferList(cin7-api
// endpoint-index) · FinishedGoods(2026-08-17 dry 실측 — "FinishedGoodsList" 관례 추정이 틀렸었다.
// 폴백 스캔은 방어로 유지). ⚠️ 문서번호 필드는 소스별 명시(numberField) — 공용 폴백 체인은
// 새 소스가 붙을 때 조용히 틀린다(조립이 그랬다: Number 도 StocktakeNumber 도 없어 전부 ""
// → 커서 정지 + 유니크 키 붕괴 직전. 실측 프로브 8·11차: 조립 번호는 AssemblyNumber).
const SOURCES: Record<string, { listPath: string; listKey: string; numberField: string; detailPath: (id: string) => string; docType: string }> = {
  adjustment: {
    listPath: "/stockadjustmentList", listKey: "StockAdjustmentList", numberField: "StocktakeNumber",
    detailPath: (id) => "/stockadjustment?TaskID=" + encodeURIComponent(id), docType: "adjustment",
  },
  transfer: {
    listPath: "/stockTransferList", listKey: "StockTransferList", numberField: "Number",
    detailPath: (id) => "/stockTransfer?TaskID=" + encodeURIComponent(id), docType: "transfer",
  },
  assembly: {
    listPath: "/finishedGoodsList", listKey: "FinishedGoods", numberField: "AssemblyNumber",
    detailPath: (id) => "/finishedGoods?TaskID=" + encodeURIComponent(id), docType: "assembly",
  },
};

// ②-b 증분 축 3종 — 날짜 커서(UpdatedSince). updatedField 는 소스별 명시(공용 폴백 금지 —
// SOURCES numberField 와 같은 교훈): sale=Updated(hello 폴링 실측) · purchase=LastUpdatedDate
// (리시빙 관문 실측) · creditnote=Updated(SaleList 형태라 추정 — 비면 no_updated_field 로 드러난다).
const DATE_SOURCES: Record<string, { listPath: string; listKey: string; updatedField: string; docType: string }> = {
  sale:       { listPath: "/saleList",           listKey: "SaleList",     updatedField: "Updated",         docType: "sale" },
  purchase:   { listPath: "/purchaseList",       listKey: "PurchaseList", updatedField: "LastUpdatedDate", docType: "purchase" },
  creditnote: { listPath: "/saleCreditNoteList", listKey: "SaleList",     updatedField: "Updated",         docType: "creditnote" },
};

// ── Supabase REST 헬퍼 (inv-snapshot 과 같은 형태 — service_role 자동주입) ──
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
async function sbInsertIgnoreDup(table: string, conflictCols: string, rows: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + table + "?on_conflict=" + conflictCols, {
    method: "POST",
    headers: sbHeaders({ Prefer: "resolution=ignore-duplicates,return=minimal" }),
    body: JSON.stringify(rows),
  });
  if (!r.ok) throw new Error("sbInsert " + table + " " + r.status + ": " + (await r.text()).slice(0, 400));
}
async function sbUpsert(table: string, conflictCol: string, rows: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + table + "?on_conflict=" + conflictCol, {
    method: "POST",
    headers: sbHeaders({ Prefer: "resolution=merge-duplicates,return=minimal" }),
    body: JSON.stringify(rows),
  });
  if (!r.ok) throw new Error("sbUpsert " + table + " " + r.status + ": " + (await r.text()).slice(0, 400));
}

// 문서번호 → 비교용 숫자 (TR-03976 → 3976). ⚠️ 저장은 항상 문자열 원문 — 비교만 숫자
// (사람이 last_cursor 를 읽으면 "TR-03976 까지 봤다"가 보여야 한다 — 사용자 지시).
function docNum(n: string): number | null {
  const m = String(n ?? "").match(/(\d+)\s*$/);
  return m ? Number(m[1]) : null;
}
const dateOnly = (s: unknown): string | null => {
  const t = String(s ?? "").slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(t) ? t : null;
};
const norm = (s: unknown) => String(s ?? "").trim().toUpperCase();
// UpdatedSince = 커서 − 1일 (겹침 수신 — 경계 유실 방지, 중복은 유니크 키가 흡수)
function minusOneDay(d: string): string {
  const t = new Date(d + "T00:00:00Z");
  t.setUTCDate(t.getUTCDate() - 1);
  return t.toISOString().slice(0, 10);
}

// ── 공유 sink (2026-08-17 ②-b 에서 ②-a runSource 로부터 기계적 추출 — 동작 동일) ──
// 빈 sku 가드 · 문서 내 합산 · since 필터 · seq_hint 재판정을 문서번호 커서(runSource)와
// 날짜 커서(runDateSource)가 함께 쓴다 — 게이트 로직이 두 벌이면 다음 수정 때 갈라진다.
// ⚠️ 회귀 확인: ②-a dry 3종을 추출 전과 같은 파라미터로 재실행해 ledger_rows·samples·
//   date_histogram·cursor_after_would_be 동일성 대조(커밋 메시지에 절차 기재).
function makeSink(since: string | null) {
  const rows: LedgerRow[] = [];
  const dateHist: Record<string, number> = {};
  const stats = { merged_lines: 0, empty_sku_lines: 0, since_filtered_rows: 0 };
  // 문서 하나의 행들을 유니크 키로 합산해 push — merged_lines 는 line_ref 가정 붕괴 신호
  function push(docRows: LedgerRow[]): void {
    const byKey = new Map<string, LedgerRow>();
    for (const r of docRows) {
      // ⚠️ 빈 sku = 어느 상품인지 모르는 행 — 만들지 않는다. ≠0 이면 그 소스의 파싱이 틀렸다는
      //   뜻이라 나머지 행도 못 믿는다 → commit 게이트가 소스 전체를 막는다(UNMAPPED 와 같은 논리.
      //   실사고: 조립 PickLines 에 SKU 필드가 없어(정답은 ProductCode) sku 가 전부 "" 였는데
      //   나머지 필드는 멀쩡해 보였다 — 조용히 통과할 뻔했다).
      if (!r.sku) { stats.empty_sku_lines++; continue; }
      if (since && !(r.occurred_on > since)) { stats.since_filtered_rows++; continue; }   // "그 날짜보다 이후"만 — 경계일 제외
      const k = [r.doc_type, r.doc_number, r.line_ref, r.event_type, r.warehouse, r.bin, r.sku].join("\u0001");   // 구분자 없는 연결은 키 충돌("AB","C")/("A","BC")
      const cur = byKey.get(k);
      if (cur) {
        stats.merged_lines++;
        cur.qty_delta += r.qty_delta;
        if (r.amount != null) cur.amount = (cur.amount ?? 0) + r.amount;
        if (!Array.isArray(cur.raw.merged_lines_raw)) cur.raw.merged_lines_raw = [];
        (cur.raw.merged_lines_raw as unknown[]).push(r.raw.line);
      } else byKey.set(k, r);
    }
    for (const r of byKey.values()) {
      r.seq_hint = r.qty_delta > 0 ? 1 : 2;   // 합산 후 재판정 (유입 먼저)
      rows.push(r);
      dateHist[r.occurred_on] = (dateHist[r.occurred_on] ?? 0) + 1;
    }
  }
  return { rows, dateHist, stats, push };
}
const mkRaw = (line: unknown, header: Record<string, unknown>, rule: string): Record<string, unknown> =>
  ({ line, header, rule, collector: COLLECTOR_VERSION });   // ⚠️ 문서 전체 금지 — 라인 + 최소 헤더만. 고객명·주소 없음

Deno.serve(async (req) => {
  const t0 = Date.now();
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "x-wms-cron-key, content-type" } });
    }
    // ── 인증 (fail-closed — inv-snapshot 동일) ──
    const secret = Deno.env.get("WMS_CRON_SECRET") ?? "";
    if (!secret) return json({ ok: false, error: "WMS_CRON_SECRET not configured - refusing (fail-closed)" }, 500);
    if ((req.headers.get("x-wms-cron-key") ?? "") !== secret) return json({ ok: false, error: "unauthorized" }, 401);

    // ── 파라미터 ──
    const url = new URL(req.url);
    const commit = url.searchParams.get("commit") === "1";   // ⚠️ 기본 dry — ⑤에서 켠다
    const only = url.searchParams.get("only");
    if (only && !SOURCES[only] && !DATE_SOURCES[only]) {
      return json({ ok: false, error: "only must be adjustment|transfer|assembly|sale|purchase|creditnote" }, 400);
    }
    const since = (url.searchParams.get("since") ?? "").trim() || null;
    if (since && !/^\d{4}-\d{2}-\d{2}$/.test(since)) return json({ ok: false, error: "since must be YYYY-MM-DD" }, 400);

    // ── 커서 하한(floor) 파라미터 (2026-08-17 보완 — 실사고) ──
    // [실사고] 첫 dry(only=transfer&since=2026-08-10)가 원장 행 0개: DepartureDate 없는
    // 2025-11 초기 트랜스퍼 TR-00012~76 40건이 hold_missing_date 로 캡 40을 정확히 소진해
    // 뒤 ~3,000건을 한 건도 못 봤다. since 는 커서 정지를 못 푼다(정지가 필터보다 먼저다).
    // → 하한: 그 번호 이하 문서는 후보에서 아예 제외(스냅샷에 녹아 있으므로 볼 이유가 없다).
    // ⚠️ 하한은 "옛 데이터를 안 보는 것"이지 이상 감지를 끄는 것이 아니다 — 하한 이후
    //   문서의 날짜 결손·DRAFT 는 진짜 이상이므로 여전히 커서를 막는다(hold 로직 무변).
    // 형식: from_cursor=TR-03900 (전 소스 공통 — 비교는 숫자 접미사라 접두어 무관)
    //      또는 from_cursor=transfer:TR-03900,adjustment:ST-01150,assembly:FG-00110
    // ②-b 날짜 커서 시작점 — ②-a from_cursor 와 같은 역할(state 우선 · 없으면 이 값 · 둘 다 없으면 전량+alert)
    const fromSince = (url.searchParams.get("from_since") ?? "").trim() || null;
    if (fromSince && !/^\d{4}-\d{2}-\d{2}$/.test(fromSince)) return json({ ok: false, error: "from_since must be YYYY-MM-DD" }, 400);

    const fromCursorRaw = (url.searchParams.get("from_cursor") ?? "").trim() || null;
    const floorParam = new Map<string, string>();
    if (fromCursorRaw) {
      const tokens = fromCursorRaw.split(",").map((t) => t.trim()).filter(Boolean);
      if (tokens.some((t) => t.includes(":"))) {
        for (const t of tokens) {
          const [k, v] = t.split(":").map((x) => x.trim());
          // 잘못된 소스 키·번호를 조용히 무시하면 하한 없이 전량을 돌게 된다 — 400 으로 막는다
          if (!k || !v || !SOURCES[k]) return json({ ok: false, error: "from_cursor: unknown source '" + (k ?? "") + "' - use transfer:TR-…,adjustment:ST-…,assembly:FG-…" }, 400);
          if (docNum(v) == null) return json({ ok: false, error: "from_cursor: unparsable doc number '" + v + "'" }, 400);
          floorParam.set(k, v);
        }
      } else {
        if (tokens.length !== 1) return json({ ok: false, error: "from_cursor: multiple bare values - use source:VALUE form" }, 400);
        if (docNum(tokens[0]) == null) return json({ ok: false, error: "from_cursor: unparsable doc number '" + tokens[0] + "'" }, 400);
        for (const k of Object.keys(SOURCES)) floorParam.set(k, tokens[0]);
      }
    }

    const timeLeft = () => TIME_BUDGET_MS - (Date.now() - t0);

    // ── 창고 맵: ref/location 전량 (ParentID 없는 행 = 창고 · 2단 트리) ──
    const locMap = new Map<string, { name: string; parentId: string | null }>();
    let locPages = 0, locTotal: number | null = null, locReceived = 0;
    for (let page = 1; page <= MAX_LIST_PAGES; page++) {
      const j = await cin7Get("/ref/location?Page=" + page + "&Limit=" + LIST_PAGE_LIMIT);
      locPages++;
      if (j?.Total != null) locTotal = Number(j.Total);
      const batch = (j?.LocationList ?? []) as any[];
      locReceived += batch.length;
      for (const l of batch) {
        const id = String(l?.ID ?? "").trim();
        if (id) locMap.set(id, { name: String(l?.Name ?? "").trim(), parentId: l?.ParentID ? String(l.ParentID).trim() : null });
      }
      if (batch.length < LIST_PAGE_LIMIT) break;
      await sleep(LIST_SLEEP_MS);
    }
    if (locTotal != null && locReceived < locTotal) {
      // 맵이 잘리면 모든 판정이 UNMAPPED 오탐이 된다 — 여기서 중단이 맞다.
      return json({ ok: false, error: "location map truncated: " + locReceived + " of " + locTotal, duration_ms: Date.now() - t0 }, 500);
    }
    // LocationID → {warehouse, bin} — 창고면 bin='', 빈이면 부모 이름 + 빈 이름
    const unmapped = new Map<string, { id: string; name_fallback: string | null; sources: Set<string>; count: number }>();
    const unexpectedWarehouses = new Map<string, number>();   // 매핑은 됐지만 알려진 창고가 아닌 것 — 누가 실수로 재고를 넣으면 알아야 한다
    function markWh(name: string): void {
      if (!KNOWN_WAREHOUSES.has(name)) unexpectedWarehouses.set(name, (unexpectedWarehouses.get(name) ?? 0) + 1);
    }
    function resolveLoc(id: unknown, nameFallback: unknown, srcTag: string): { warehouse: string; bin: string; mapped: boolean } {
      const key = String(id ?? "").trim();
      const hit = key ? locMap.get(key) : undefined;
      if (hit) {
        if (!hit.parentId) { markWh(hit.name); return { warehouse: hit.name, bin: "", mapped: true }; }
        const parent = locMap.get(hit.parentId);
        if (parent) { markWh(parent.name); return { warehouse: parent.name, bin: hit.name, mapped: true }; }
      }
      const fb = String(nameFallback ?? "").trim() || null;
      const u = unmapped.get(key || "(no-id)") ?? { id: key || "(no-id)", name_fallback: fb, sources: new Set<string>(), count: 0 };
      u.sources.add(srcTag); u.count++;
      unmapped.set(u.id, u);
      return { warehouse: fb ?? "UNMAPPED(" + (key || "no-id") + ")", bin: "", mapped: false };
    }

    // ── 수집 상태 (커서) ──
    const runKeys = only ? [only] : [...Object.keys(SOURCES), ...Object.keys(DATE_SOURCES)];
    const stateRows = await sbGet("inv_sync_state?source_key=in.(" + runKeys.join(",") + ")&select=source_key,last_cursor");
    const cursorOf = (k: string) => stateRows.find((r) => r.source_key === k)?.last_cursor ?? null;

    const global = {
      mode: commit ? "commit" : "dry",
      since,
      collector_version: COLLECTOR_VERSION,
      location_map: { total: locTotal, received: locReceived, pages: locPages },
      rate_limited: false as boolean,
    };
    const results: Record<string, unknown> = {};

    // ══ 소스 하나 처리 ══
    async function runSource(key: string): Promise<void> {
      const cfg = SOURCES[key];
      const R: Record<string, unknown> = {};
      const warnings: string[] = [];
      const fieldFallbacks: Record<string, number> = {};
      const bump = (k: string) => { fieldFallbacks[k] = (fieldFallbacks[k] ?? 0) + 1; };

      // 1) 목록 전량 (날짜 축 없음 — 실측. 매번 전량 받아 우리 쪽에서 거른다)
      let listTotal: number | null = null, listReceived = 0, pages = 0;
      const listRows: any[] = [];
      let listAborted: string | null = null;
      for (let page = 1; page <= MAX_LIST_PAGES; page++) {
        if (timeLeft() < 0) { listAborted = "time"; break; }
        let j: any;
        try {
          j = await cin7Get(cfg.listPath + "?Page=" + page + "&Limit=" + LIST_PAGE_LIMIT);
        } catch (e: any) {
          if (Number(e?.status) === 429) { global.rate_limited = true; listAborted = "rate_limited"; }
          else listAborted = "page_error: " + String(e?.message ?? e).slice(0, 200);
          break;
        }
        pages++;
        if (j?.Total != null) listTotal = Number(j.Total);
        let batch = j?.[cfg.listKey] as any[] | undefined;
        if (!Array.isArray(batch)) {
          // 배열 키 폴백 스캔 (FinishedGoodsList 는 관례 추정) — 발동하면 보고
          const arrKey = Object.keys(j ?? {}).find((k) => Array.isArray(j[k]));
          batch = arrKey ? j[arrKey] : [];
          if (arrKey && arrKey !== cfg.listKey) { bump("list_key_fallback"); warnings.push("list array key was '" + arrKey + "' not '" + cfg.listKey + "'"); }
        }
        listReceived += batch!.length;
        listRows.push(...batch!);
        if (batch!.length < LIST_PAGE_LIMIT) break;
        await sleep(LIST_SLEEP_MS);
      }
      const truncated = listTotal == null ? null : listReceived < listTotal;

      // 2) 후보 선정 — 번호 오름차순 · 커서 초과 · 상태 · since(목록 레벨)
      const cursorBefore: string | null = cursorOf(key);
      // floor 해석 — state 커서가 있으면 그것(저장된 진행이 우선 — 파라미터로 실수 되돌림 방지),
      // 없으면 ?from_cursor=, 둘 다 없으면 없음 = 전량 스캔(시끄럽게 보고 — TR-00012 교착 재발 경로).
      let floorUsed: string | null = null;
      let floorSource: "state" | "param" | "none" = "none";
      if (cursorBefore) { floorUsed = cursorBefore; floorSource = "state"; }
      else if (floorParam.has(key)) { floorUsed = floorParam.get(key)!; floorSource = "param"; }
      const paramIgnored = floorSource === "state" && floorParam.has(key);
      const floorNum = floorUsed ? docNum(floorUsed) : null;
      if (floorSource === "none") warnings.push("NO FLOOR - scanning from the very first document (pass ?from_cursor= or seed inv_sync_state)");
      const numberOf = (row: any) => String(row?.[cfg.numberField] ?? "").trim();   // 소스별 명시 — SOURCES 주석 참조
      const statusCounts: Record<string, number> = {};
      for (const row of listRows) statusCounts[norm(row?.Status) || "(none)"] = (statusCounts[norm(row?.Status) || "(none)"] ?? 0) + 1;

      type Cand = { row: any; num: number; number: string; disposition: string };
      const cands: Cand[] = [];
      let skipBeforeFloor = 0;
      let unparsableNumbers = 0;                 // ⚠️ 행마다 경고를 쏟지 않는다 — 120줄 홍수에 진짜 경고가 묻힌다(실사고)
      let unparsableSample: string | null = null;
      for (const row of listRows) {
        const number = numberOf(row);
        const n = docNum(number);
        if (n == null) { unparsableNumbers++; if (unparsableSample == null) unparsableSample = number; }
        const num = n ?? Number.MAX_SAFE_INTEGER;
        // ⚠️ floor 적용은 disposition(hold 판정)보다 먼저 — 하한 이하 문서는 후보에 아예 안
        //   들어가므로 옛 문서의 날짜 결손·DRAFT 가 커서를 막을 기회 자체가 없다.
        if (floorNum != null && n != null && n <= floorNum) { skipBeforeFloor++; continue; }
        cands.push({ row, num, number, disposition: "" });
      }
      cands.sort((a, b) => a.num - b.num);
      if (unparsableNumbers > 0) warnings.push(unparsableNumbers + " doc(s) with unparsable/empty number (e.g. '" + unparsableSample + "') — cursor will hold at the first one");

      // 상태·since 로 disposition 1차 결정 (상세 없이 판정 가능한 것)
      //  terminal-skip = 커서가 지나가도 되는 건너뜀 / hold = 커서가 그 앞에서 멈춤
      for (const c of cands) {
        const st = norm(c.row?.Status);
        if (key === "transfer") {
          if (st === "VOIDED") { c.disposition = "skip_voided"; continue; }
          if (st === "COMPLETED") {
            const dep = dateOnly(c.row?.DepartureDate), comp = dateOnly(c.row?.CompletionDate);
            // 만들 수 있는 모든 날짜가 since 이하면 전부 걸러질 문서 — 종결이므로 커서 통과 가능
            if (since && dep && comp && dep <= since && comp <= since) { c.disposition = "skip_since"; continue; }
            c.disposition = "process";
          } else if (st === "IN TRANSIT") {
            const dep = dateOnly(c.row?.DepartureDate);
            // 1·2행마저 since 이하면 지금 만들 것이 없다 — 단 비종결이라 커서는 여기서 멈춘다(3·4 대기)
            c.disposition = (since && dep && dep <= since) ? "hold_intransit_before_since" : "process_nonterminal";
          } else { c.disposition = "hold_status:" + st; }
        } else {
          // adjustment · assembly — COMPLETED 만 처리 (VOIDED 제외 · 그 외는 비종결로 커서 hold)
          if (st === "VOIDED") { c.disposition = "skip_voided"; continue; }
          if (st !== "COMPLETED") { c.disposition = "hold_status:" + st; continue; }
          if (key === "adjustment") {
            const eff = dateOnly(c.row?.EffectiveDate);
            if (since && eff && eff <= since) { c.disposition = "skip_since"; continue; }
          }
          // 조립은 날짜 미확정(3후보)이라 목록 레벨 since 스킵을 하지 않는다 — 120건뿐이라 비용 없음
          c.disposition = "process";
        }
      }

      // 3) 상세 조회 (오름차순 · 캡 · 시간 가드) → 원장 행 생성
      const sink = makeSink(since);                 // 공유 sink — 파일 상단 makeSink(②-b 에서 추출, 동작 동일)
      const dateCandidates: { doc_number: string; list_date: string | null; completion_date: string | null; wip_date: string | null }[] = [];
      let detailFetched = 0, docsProcessed = 0, zeroQtyLines = 0, missingDateDocs = 0;
      const dateSubstitutedDocs: string[] = [];     // 빈 이동 날짜 대체 문서 (아래 transfer 분기)
      let detailCapped = false, detailCapReason: string | null = null;
      let unmappedInSource = 0;

      for (const c of cands) {
        if (!c.disposition.startsWith("process")) continue;
        if (detailFetched >= MAX_DETAIL_PER_SOURCE) { detailCapped = true; detailCapReason = "max_detail"; c.disposition = "hold_capped"; continue; }
        if (timeLeft() < 5_000) { detailCapped = true; detailCapReason = "time"; c.disposition = "hold_capped"; continue; }
        const taskId = String(c.row?.TaskID ?? "").trim();
        let det: any;
        try {
          det = await cin7Get(cfg.detailPath(taskId));
          detailFetched++;
          await sleep(DETAIL_SLEEP_MS);
        } catch (e: any) {
          if (Number(e?.status) === 429) { global.rate_limited = true; detailCapped = true; detailCapReason = "rate_limited"; c.disposition = "hold_rate_limited"; break; }
          warnings.push("detail error " + c.number + ": " + String(e?.message ?? e).slice(0, 200));
          c.disposition = "hold_detail_error";
          continue;
        }

        const rows: LedgerRow[] = [];
        const base = { doc_type: cfg.docType, doc_number: c.number, doc_task_id: taskId || null, source: "cin7" };

        if (key === "adjustment") {
          const eff = dateOnly(det?.EffectiveDate ?? c.row?.EffectiveDate);
          if (!eff) { missingDateDocs++; warnings.push("missing EffectiveDate: " + c.number); c.disposition = "hold_missing_date"; continue; }
          const header = { doc_number: c.number, task_id: taskId, status: det?.Status, effective_date: det?.EffectiveDate, header_location_id: det?.LocationID ?? null };
          for (const line of (det?.ExistingStockLines ?? []) as any[]) {
            // ⚠️ 목표수량 − 당시수량 (프로브 1순위 · 레퍼런스 형태 폴백은 카운트)
            let target = line?.Adjustment, onhand = line?.QuantityOnHand;
            if (target == null && line?.AdjustedQuantity != null) { target = line.AdjustedQuantity; bump("adjust_existing_target_fallback"); }
            if (onhand == null && line?.Quantity != null) { onhand = line.Quantity; bump("adjust_existing_onhand_fallback"); }
            if (target == null || onhand == null) { warnings.push("adjust_existing fields missing: " + c.number + " " + String(line?.SKU)); continue; }
            const delta = Number(target) - Number(onhand);
            if (delta === 0) { zeroQtyLines++; continue; }   // 변화 없는 조정 — 행 없이 카운트만
            const loc = pickLineLoc(line, header.header_location_id, det, c.number, key);
            rows.push({
              ...base, occurred_on: eff, seq_hint: delta > 0 ? 1 : 2,
              sku: String(line?.SKU ?? "").trim(), warehouse: loc.warehouse, bin: loc.bin,
              qty_delta: delta, event_type: "adjust_existing",
              line_ref: lineRef(line, warnings, c.number),
              amount: line?.UnitCost != null ? Number(line.UnitCost) * delta : null,
              raw: mkRaw(line, header, "adjust_existing: Adjustment(" + target + ") - QuantityOnHand(" + onhand + ") = " + (delta > 0 ? "+" : "") + delta),
            });
          }
          for (const line of (det?.NewStockLines ?? []) as any[]) {
            const q = Number(line?.Quantity ?? 0);   // ⚠️ 규칙이 다르다 — 그대로 증가분 (QuantityOnHand 없음)
            if (q === 0) { zeroQtyLines++; continue; }
            const loc = pickLineLoc(line, header.header_location_id, det, c.number, key);
            rows.push({
              ...base, occurred_on: eff, seq_hint: q > 0 ? 1 : 2,
              sku: String(line?.SKU ?? "").trim(), warehouse: loc.warehouse, bin: loc.bin,
              qty_delta: q, event_type: "adjust_new",
              line_ref: lineRef(line, warnings, c.number),
              amount: line?.UnitCost != null ? Number(line.UnitCost) * q : null,
              raw: mkRaw(line, header, "adjust_new: Quantity(" + q + ") as-is"),
            });
          }
        } else if (key === "transfer") {
          // From/To 해석을 날짜 검사보다 먼저 — 빈 이동(같은 창고) 판정에 필요 (2026-08-17 보완 2)
          const fromLoc = resolveLoc(det?.From ?? c.row?.From, det?.FromLocation ?? c.row?.FromLocation, key + ":" + c.number);
          const toLoc = resolveLoc(det?.To ?? c.row?.To, det?.ToLocation ?? c.row?.ToLocation, key + ":" + c.number);
          let dep = dateOnly(det?.DepartureDate ?? c.row?.DepartureDate);
          const comp = dateOnly(det?.CompletionDate ?? c.row?.CompletionDate);
          let dateSubstituted = false;
          if (!dep) {
            // [구조적 결손 — 사용자 확인 2026-08-17] Cin7 WMS 모바일로 빈 이동을 하면 DepartureDate
            // 없는 트랜스퍼가 생긴다. 우리 WMS 에 빈 이동 기능이 없어(규칙 33 백로그) 이 경로가
            // 계속 쓰이므로 매일 새로 생긴다 — 하한(floor)으로는 못 푼다(실측 TR-03971 외 14건/3일).
            // 같은 창고 안 이동은 창고 잔고 ±0 이라 날짜가 부정확해도 결과 무영향 → LastModifiedOn
            // 으로 대체하고 기록한다(버리면 나중에 빈 단위 승격 때 이력이 없다 — "지금 안 써도
            // 담는다" 원칙). ⚠️ **창고간은 여전히 hold** — 잔고가 움직이는데 시점을 모르는 것은
            // 진짜 이상이다. 대체 사실은 raw.header.date_substituted 에 남는다(이 날짜는 못 믿는다).
            const sameWh = fromLoc.mapped && toLoc.mapped && fromLoc.warehouse === toLoc.warehouse;
            const lm = dateOnly(det?.LastModifiedOn ?? c.row?.LastModifiedOn);
            if (sameWh && lm) {
              dep = lm;
              dateSubstituted = true;
              dateSubstitutedDocs.push(c.number);
            } else {
              missingDateDocs++;
              warnings.push("missing DepartureDate (cross-warehouse, unmapped, or no LastModifiedOn): " + c.number);
              c.disposition = "hold_missing_date";
              continue;
            }
          }
          if (!fromLoc.mapped) unmappedInSource++;
          if (!toLoc.mapped) unmappedInSource++;
          const header: Record<string, unknown> = { doc_number: c.number, task_id: taskId, status: det?.Status ?? c.row?.Status, departure_date: det?.DepartureDate, completion_date: det?.CompletionDate ?? null, from: det?.From ?? c.row?.From, to: det?.To ?? c.row?.To };
          if (dateSubstituted) header.date_substituted = "DepartureDate <- LastModifiedOn (bin move, same warehouse)";
          for (const line of (det?.Lines ?? []) as any[]) {
            const q = Number(line?.TransferQuantity ?? 0);
            if (q === 0) { zeroQtyLines++; continue; }
            const sku = String(line?.SKU ?? "").trim();
            const ref = lineRef(line, warnings, c.number);
            const lineRaw = { SKU: line?.SKU, ProductID: line?.ProductID, TransferQuantity: line?.TransferQuantity };
            const mk = (event: string, wh: string, bin: string, delta: number, day: string, leg: string): LedgerRow => ({
              ...base, occurred_on: day, seq_hint: delta > 0 ? 1 : 2, sku, warehouse: wh, bin,
              qty_delta: delta, event_type: event, line_ref: ref, amount: null,
              raw: mkRaw(lineRaw, header, "transfer 4-row leg " + leg + ": " + (delta > 0 ? "+" : "") + delta),
            });
            rows.push(mk("transfer_out", fromLoc.warehouse, fromLoc.bin, -q, dep, "1 from-warehouse departure"));
            rows.push(mk("transfer_in", IN_TRANSIT, "", q, dep, "2 into IN_TRANSIT departure"));
            if (comp) {   // 없으면(IN TRANSIT) 1·2만 — 3·4는 도착 후 회차 (커서가 이 문서 앞에서 멈춘다)
              rows.push(mk("transfer_out", IN_TRANSIT, "", -q, comp, "3 out of IN_TRANSIT completion"));
              rows.push(mk("transfer_in", toLoc.warehouse, toLoc.bin, q, comp, "4 to-warehouse completion"));
            }
          }
        } else {   // assembly
          const listDate = dateOnly(c.row?.Date);
          const comp = dateOnly(det?.CompletionDate);
          const wip = dateOnly(det?.WIPDate);
          dateCandidates.push({ doc_number: c.number, list_date: listDate, completion_date: comp, wip_date: wip });
          // ⚠️ 잠정 CompletionDate — 실제 이동일(FG-00110 = 오더 생성 시점 2026-08-06)이 어느
          //   필드인지 미확정. 폴백 발동은 카운트 — 응답의 date_candidates 로 Caleb 이 확정한다.
          let occurred = comp;
          if (!occurred && listDate) { occurred = listDate; bump("assembly_date_fallback_list"); }
          if (!occurred && wip) { occurred = wip; bump("assembly_date_fallback_wip"); }
          if (!occurred) { missingDateDocs++; warnings.push("no usable date: " + c.number); c.disposition = "hold_missing_date"; continue; }
          const header = { doc_number: c.number, task_id: taskId, status: det?.Status, completion_date: det?.CompletionDate ?? null, wip_date: det?.WIPDate ?? null, list_date: c.row?.Date ?? null };
          for (const line of (det?.PickLines ?? []) as any[]) {   // 구성품 차감
            const q = Number(line?.Quantity ?? 0);
            if (q === 0) { zeroQtyLines++; continue; }
            const loc = pickLineLoc(line, det?.LocationID ?? null, det, c.number, key);
            rows.push({
              ...base, occurred_on: occurred, seq_hint: 2,
              // ⚠️ PickLines 에는 SKU 필드가 없다 — ProductCode 가 상품 코드다 (2026-08-17 dry 실측:
              //   SKU 로 읽어 전부 "" 였다. 완제품(헤더)은 원래 ProductCode). SKU 폴백은 방어.
              sku: String(line?.ProductCode ?? line?.SKU ?? "").trim(), warehouse: loc.warehouse, bin: loc.bin,
              qty_delta: -q, event_type: "assemble_out", line_ref: lineRef(line, warnings, c.number),
              amount: null, raw: mkRaw(line, header, "assemble_out: -Quantity(" + q + ") component"),
            });
          }
          const hq = Number(det?.Quantity ?? 0);   // 헤더 = 완제품 유입
          if (hq === 0) zeroQtyLines++;
          else {
            const loc = pickLineLoc(det, det?.LocationID ?? null, det, c.number, key);   // 헤더의 BinID/LocationID
            rows.push({
              ...base, occurred_on: occurred, seq_hint: 1,
              sku: String(det?.ProductCode ?? "").trim(), warehouse: loc.warehouse, bin: loc.bin,
              qty_delta: hq, event_type: "assemble_in",
              line_ref: String(det?.ProductID ?? "").trim() || "header",
              amount: null,
              raw: mkRaw({ ProductCode: det?.ProductCode, ProductID: det?.ProductID, Quantity: det?.Quantity, BinID: det?.BinID ?? null, LocationID: det?.LocationID ?? null }, header, "assemble_in: +Quantity(" + hq + ") finished product (header)"),
            });
          }
        }

        sink.push(rows);
        docsProcessed++;
        if (c.disposition === "process") c.disposition = "processed";           // 종결 — 커서 통과 가능
        else if (c.disposition === "process_nonterminal") c.disposition = "processed_nonterminal";   // IN TRANSIT — 커서 hold
      }

      // 라인 위치 판정: 라인의 BinID → 라인의 LocationID → 헤더 LocationID. 둘 다 없으면 보고 + 폴백.
      function pickLineLoc(line: any, headerLocId: unknown, det: any, docNumber: string, srcKey: string): { warehouse: string; bin: string } {
        const id = line?.BinID ?? line?.LocationID ?? headerLocId;
        if (id == null) {
          warnings.push("no LocationID on line nor header: " + docNumber);
          const r = resolveLoc(null, line?.Location ?? det?.Location ?? null, srcKey + ":" + docNumber);
          unmappedInSource++;
          return { warehouse: r.warehouse, bin: r.bin };
        }
        const r = resolveLoc(id, line?.Location ?? det?.Location ?? null, srcKey + ":" + docNumber);
        if (!r.mapped) unmappedInSource++;
        return { warehouse: r.warehouse, bin: r.bin };
      }
      function lineRef(line: any, warn: string[], docNumber: string): string {
        const ref = String(line?.ProductID ?? "").trim();   // line_ref = ProductID (WMS cin7_po_line_id 와 같은 값 — 실무 검증)
        if (!ref) warn.push("line without ProductID: " + docNumber + " " + String(line?.SKU ?? "?"));
        return ref || "no-product-id:" + String(line?.SKU ?? "?");
      }

      // 4) 커서 전진 — 앞에서부터 연속으로 "종결"인 문서까지만. hold 를 만나면 그 앞에서 멈춘다.
      //    (hold 이후의 processed 문서 행도 응답·쓰기에는 포함된다 — 다음 회차 재방문은 유니크 키가 막는다)
      // ④ 커서 시작점 = floor — param floor 도 시작점이 되므로 commit 이 켜지면(⑤) floor 가
      //   그대로 last_cursor 초기값으로 영속된다(별도 주입 코드 불필요).
      //   ⚠️ floor 를 커서 시작점으로 삼으면 그 이하 문서는 영영 안 본다. 그것이 의도다
      //   (스냅샷에 녹아 있으므로). 다시 보려면 inv_sync_state.last_cursor 를 손으로 되돌려야 한다.
      let cursorAfter: string | null = floorUsed;
      let cursorHeldBy: { doc_number: string; reason: string } | null = null;
      for (const c of cands) {
        const d = c.disposition;
        // ⚠️ 파싱 불가 번호에는 커서를 올리지 않는다 — 저장되면 다음 회차 docNum(cursor)=null 이
        //   되어 커서 자체가 무효화된다(전량 재스캔). 그 문서 앞에서 멈추고 경고로 남긴다.
        if (docNum(c.number) == null) { cursorHeldBy = { doc_number: c.number, reason: "unparsable_number" }; break; }
        if (d === "processed" || d === "skip_voided" || d === "skip_since") { cursorAfter = c.number; continue; }
        cursorHeldBy = { doc_number: c.number, reason: d };
        break;
      }
      // 건너뜀·보류 내역 집계 (응답용 — "건너뛴 문서 수"를 사유별로)
      const dispositions: Record<string, number> = {};
      for (const c of cands) dispositions[c.disposition || "(untouched)"] = (dispositions[c.disposition || "(untouched)"] ?? 0) + 1;

      // 5) 샘플 5행 (전체 필드 — 숫자만 맞고 내용이 틀릴 수 있다: 눈으로 확인)
      const samples = sink.rows.slice(0, 5);

      Object.assign(R, {
        list_total: listTotal, list_received: listReceived, pages, truncated,
        list_aborted: listAborted,
        status_counts: statusCounts,
        cursor_before: cursorBefore,
        floor_used: floorUsed,
        floor_source: floorSource,
        from_cursor_param_ignored: paramIgnored || undefined,      // state 커서가 있어 파라미터를 무시했음
        // ⚠️ 하한 없음 = 목록 처음부터 전량 — 눈에 띄게 (TR-00012 교착의 재발 경로)
        floor_alert: floorSource === "none"
          ? "NO FLOOR - scanning from the very first document; old docs with missing dates will hold the cursor (TR-00012 incident)"
          : undefined,
        cursor_after: commit ? cursorAfter : cursorBefore,        // dry 는 커서 무변
        cursor_after_would_be: cursorAfter,
        cursor_held_by: cursorHeldBy,
        skip_before_floor: skipBeforeFloor,
        dispositions,
        detail_fetched: detailFetched,
        docs_processed: docsProcessed,
        // ⚠️ 시끄러운 캡 보고 — 조용하면 "적게 나온 게 정상"으로 오해한다
        detail_capped: detailCapped,
        detail_capped_reason: detailCapReason,
        detail_capped_remaining: detailCapped ? cands.filter((c) => c.disposition === "hold_capped").length : 0,
        ledger_rows: sink.rows.length,
        zero_qty_lines: zeroQtyLines,
        since_filtered_rows: sink.stats.since_filtered_rows,
        missing_date_docs: missingDateDocs,
        // ⚠️ merged_lines ≠ 0 = line_ref=ProductID 가정(같은 SKU 두 줄 없음)이 깨졌다는 신호
        merged_lines: sink.stats.merged_lines,
        merged_lines_alert: sink.stats.merged_lines > 0 ? "NOT ZERO - the line_ref=ProductID assumption is broken, inspect raw.merged_lines_raw" : null,
        // ⚠️ empty_sku_lines ≠ 0 = 이 소스의 파싱이 틀렸다 — commit 은 소스 전체 차단(사용자 조건)
        empty_sku_lines: sink.stats.empty_sku_lines,
        empty_sku_alert: sink.stats.empty_sku_lines > 0 ? "NOT ZERO - parsing is wrong for this source; commit is blocked until fixed" : undefined,
        // 빈 이동 날짜 대체 (같은 창고 + LastModifiedOn — 이 문서들의 occurred_on 은 근사값)
        date_substituted_docs: dateSubstitutedDocs.length,
        date_substituted_doc_numbers: dateSubstitutedDocs.slice(0, 20),
        field_fallbacks: fieldFallbacks,
        date_histogram: sink.dateHist,
        samples,
        warnings,
      });
      if (sink.stats.empty_sku_lines > 0) warnings.push(sink.stats.empty_sku_lines + " line(s) dropped for empty sku - parsing is wrong for this source");
      if (key === "assembly") R.date_candidates = dateCandidates;   // Date/CompletionDate/WIPDate 비교표 — Caleb 이 확정

      // 6) commit (⑤에서 켠다) — all-or-nothing per source:
      //    목록 불완전(429·truncated·페이지 오류) 또는 UNMAPPED(사용자 조건 ⑤) 또는 날짜 결손
      //    또는 빈 sku(2026-08-17 조건 — 상품을 모르는 행이 있다는 건 파싱이 틀렸다는 뜻이고
      //    나머지 행도 못 믿는다)면 그 소스는 한 행도 쓰지 않고 커서도 안 옮긴다.
      //    detail_capped 는 쓰기 가능 — 커서가 캡 앞에서 멈추므로 다음 회차가 이어간다.
      if (commit) {
        let blocked: string | null = null;
        if (listAborted) blocked = "list_aborted: " + listAborted;
        else if (truncated) blocked = "list truncated";
        else if (unmappedInSource > 0) blocked = "UNMAPPED location in " + unmappedInSource + " row(s) - fix map first (rows would be permanent)";
        else if (sink.stats.empty_sku_lines > 0) blocked = sink.stats.empty_sku_lines + " line(s) with empty sku - parsing is wrong, the rest of this source cannot be trusted";
        else if (missingDateDocs > 0) blocked = missingDateDocs + " doc(s) without usable date";
        if (blocked) {
          R.write_skipped = blocked;
        } else {
          for (let i = 0; i < sink.rows.length; i += INSERT_BATCH) {
            await sbInsertIgnoreDup("inv_ledger", LEDGER_CONFLICT, sink.rows.slice(i, i + INSERT_BATCH));
          }
          await sbUpsert("inv_sync_state", "source_key", [{
            source_key: key,
            last_cursor: cursorAfter,               // ⚠️ 문서번호 문자열 그대로 — 사람이 읽는 값
            last_run_at: new Date().toISOString(),
            last_ok_at: new Date().toISOString(),
            note: COLLECTOR_VERSION + " rows=" + sink.rows.length + (detailCapped ? " capped" : ""),
          }]);
          R.written = sink.rows.length;
        }
      }
      results[key] = R;
    }

    // ══ ②-b 증분 축 소스 하나 처리 (판매·발주·반품 — 날짜 커서) ══
    // 규칙·실측 근거는 파일 상단 「②-b 증분 축 3종」 절. 캡·시간·429·all-or-nothing 은 runSource 동형.
    async function runDateSource(key: string): Promise<void> {
      const cfg = DATE_SOURCES[key];
      const R: Record<string, unknown> = {};
      const warnings: string[] = [];
      const fieldFallbacks: Record<string, number> = {};
      const bump = (k: string) => { fieldFallbacks[k] = (fieldFallbacks[k] ?? 0) + 1; };
      const sink = makeSink(since);

      // since(날짜 커서) 해석 — floor 와 같은 우선순위: state → ?from_since= → 없음(전량·시끄럽게)
      const cursorBefore: string | null = cursorOf(key);
      let sinceUsed: string | null = null;
      let sinceSource: "state" | "param" | "none" = "none";
      if (cursorBefore) { sinceUsed = cursorBefore; sinceSource = "state"; }
      else if (fromSince) { sinceUsed = fromSince; sinceSource = "param"; }
      const paramIgnored = sinceSource === "state" && !!fromSince;
      if (sinceSource === "none") warnings.push("NO SINCE - pulling the full list (pass ?from_since= or seed inv_sync_state)");
      // ⚠️ UpdatedSince = 커서 − 1일 — 겹치게 받는다(경계 유실 방지 · 중복은 유니크 키가 흡수)
      const sinceDate = sinceUsed ? (dateOnly(sinceUsed) ?? sinceUsed.slice(0, 10)) : null;
      const updatedSinceReq = sinceDate ? minusOneDay(sinceDate) : null;

      // 1) 목록 — UpdatedSince 증분 (②-a 와 달리 전량이 아니다) · 페이징·키 폴백은 runSource 동형
      let listTotal: number | null = null, listReceived = 0, pages = 0;
      const listRows: any[] = [];
      let listAborted: string | null = null;
      for (let page = 1; page <= MAX_LIST_PAGES; page++) {
        if (timeLeft() < 0) { listAborted = "time"; break; }
        let j: any;
        try {
          j = await cin7Get(cfg.listPath + "?Page=" + page + "&Limit=" + LIST_PAGE_LIMIT +
            (updatedSinceReq ? "&UpdatedSince=" + encodeURIComponent(updatedSinceReq) : ""));
        } catch (e: any) {
          if (Number(e?.status) === 429) { global.rate_limited = true; listAborted = "rate_limited"; }
          else listAborted = "page_error: " + String(e?.message ?? e).slice(0, 200);
          break;
        }
        pages++;
        if (j?.Total != null) listTotal = Number(j.Total);
        let batch = j?.[cfg.listKey] as any[] | undefined;
        if (!Array.isArray(batch)) {
          const arrKey = Object.keys(j ?? {}).find((k) => Array.isArray(j[k]));
          batch = arrKey ? j[arrKey] : [];
          if (arrKey && arrKey !== cfg.listKey) { bump("list_key_fallback"); warnings.push("list array key was '" + arrKey + "' not '" + cfg.listKey + "'"); }
        }
        listReceived += batch!.length;
        listRows.push(...batch!);
        if (batch!.length < LIST_PAGE_LIMIT) break;
        await sleep(LIST_SLEEP_MS);
      }
      const truncated = listTotal == null ? null : listReceived < listTotal;

      // 2) 후보 좁히기 — 상세 조회를 줄이는 것이 관건 (소스별 제외는 파일 상단 절)
      const filterCounts: Record<string, number> = {};
      const tally = (k: string) => { filterCounts[k] = (filterCounts[k] ?? 0) + 1; };
      const srsCounts: Record<string, number> = {};   // purchase: 목록 StockReceivedStatus 분포
      const cands: { row: any; updated: string | null }[] = [];
      for (const row of listRows) {
        if (key === "sale") {
          if (norm(row?.Status) === "VOIDED") { tally("skip_voided"); continue; }
          // ⚠️ 배송 전에는 재고가 안 빠진다 — 픽·팩은 Allocated 일 뿐 (원장 스킬 함정 표)
          if (norm(row?.CombinedShippingStatus) !== "SHIPPED") { tally("skip_not_shipped"); continue; }
        } else if (key === "purchase") {
          if (norm(row?.Status).includes("VOID")) { tally("skip_voided"); continue; }
          if (row?.IsServiceOnly === true) { tally("skip_service_only"); continue; }
          const srs = norm(row?.StockReceivedStatus);
          srsCounts[srs || "(empty)"] = (srsCounts[srs || "(empty)"] ?? 0) + 1;
          // "입고 흔적 없음"의 해석 = 비었거나 NOT AVAILABLE — 분포(srsCounts)를 응답에 실어 dry 가 검증
          if (!srs || srs === "NOT AVAILABLE") { tally("skip_no_stock_received"); continue; }
        } else {   // creditnote
          const cst = norm(row?.CreditNoteStatus);
          if (cst === "VOIDED" || cst === "NOT AVAILABLE") { tally("skip_cn_status"); continue; }
          if (norm(row?.RestockStatus) !== "AUTHORISED") { tally("skip_restock_status"); continue; }
        }
        cands.push({ row, updated: String(row?.[cfg.updatedField] ?? "").trim() || null });
      }
      // ⚠️ Updated 오름차순 — 캡 회차의 커서를 "마지막 처리 문서의 Updated" 로 멈추기 위한 전제
      //   (파일 상단 캡 보정 절). Updated 없는 행은 맨 앞(먼저 처리 — 유실 방지) + 카운트.
      let noUpdatedField = 0;
      for (const cd of cands) if (!cd.updated) noUpdatedField++;
      cands.sort((a, b) => (a.updated ?? "").localeCompare(b.updated ?? ""));

      // 3) 상세 → 원장 행
      let detailFetched = 0, docsProcessed = 0, zeroQtyLines = 0, missingDateItems = 0;
      let detailCapped = false, detailCapReason: string | null = null, cappedRemaining = 0;
      let unmappedInSource = 0;
      let lastProcessedUpdated: string | null = null;
      // 소스별 부가 카운트 (응답 명세)
      let fulfilmentsSeen = 0, noShipFulfilments = 0, shipDateAmbiguous = 0, pickLineCount = 0;
      let advancedCount = 0, simpleCount = 0, draftBlocksSkipped = 0, emptyStatusBlocks = 0;
      const srBlockStatusCounts: Record<string, number> = {};
      let creditNotesSeen = 0, emptyRestock = 0, noCnNumber = 0;
      const restockStatusCounts: Record<string, number> = {};

      function locOf(line: any, docNo: string): { warehouse: string; bin: string } {
        const r = resolveLoc(line?.LocationID, line?.Location ?? null, key + ":" + docNo);
        if (!r.mapped) unmappedInSource++;
        return r;
      }
      function pidOf(line: any): string {
        const pid = String(line?.ProductID ?? "").trim();
        if (!pid) bump("missing_product_id");
        return pid || "no-product-id:" + String(line?.SKU ?? "?");
      }

      for (let i = 0; i < cands.length; i++) {
        if (detailFetched >= MAX_DETAIL_PER_SOURCE) { detailCapped = true; detailCapReason = "max_detail"; cappedRemaining = cands.length - i; break; }
        if (timeLeft() < 5_000) { detailCapped = true; detailCapReason = "time"; cappedRemaining = cands.length - i; break; }
        const cd = cands[i];
        const row = cd.row;
        let path: string;
        let id: string;
        if (key === "purchase") {
          id = String(row?.ID ?? "").trim();
          // ⚠️ 상세 엔드포인트가 갈린다 — Advanced 는 StockReceived 가 배열(파일 상단 절)
          const adv = norm(row?.Type).includes("ADVANCED");
          if (adv) advancedCount++; else simpleCount++;
          path = (adv ? "/advanced-purchase?ID=" : "/purchase?ID=") + encodeURIComponent(id);
        } else {
          id = String(row?.SaleID ?? row?.ID ?? "").trim();   // saleList 키는 SaleID (hello void 감지 실측)
          path = "/sale?ID=" + encodeURIComponent(id);
        }
        let det: any;
        try {
          det = await cin7Get(path);
          detailFetched++;
          await sleep(DETAIL_SLEEP_MS);
        } catch (e: any) {
          // ⚠️ 상세 오류도 캡과 같은 정지로 다룬다 — 날짜 커서는 문서 단위 재방문이 없어,
          //   오류 문서를 지나쳐 커서를 올리면 그 문서가 조용히 유실된다(다시 갱신되지 않는 한).
          if (Number(e?.status) === 429) { global.rate_limited = true; detailCapReason = "rate_limited"; }
          else { detailCapReason = "detail_error"; warnings.push("detail error " + String(row?.OrderNumber ?? id) + ": " + String(e?.message ?? e).slice(0, 200)); }
          detailCapped = true;
          cappedRemaining = cands.length - i;
          break;
        }

        const docNo = String(det?.OrderNumber ?? row?.OrderNumber ?? "").trim();
        const rows: LedgerRow[] = [];

        if (key === "sale") {
          const header = { order_number: docNo, sale_id: id, status: det?.Status ?? row?.Status ?? null };
          const fuls = (det?.Fulfilments ?? []) as any[];
          fulfilmentsSeen += fuls.length;
          for (let fi = 0; fi < fuls.length; fi++) {
            const f = fuls[fi];
            // ShipmentDate(실측 3/3 일치)가 원장 날짜 — IsShipped true 라인만. 비었으면 건너뛰고 카운트.
            const shipLines = ((f?.Ship?.Lines ?? []) as any[]).filter((l) => l?.IsShipped === true);
            if (!shipLines.length) { noShipFulfilments++; continue; }
            const dates = [...new Set(shipLines.map((l) => dateOnly(l?.ShipmentDate)).filter(Boolean))] as string[];
            if (!dates.length) { missingDateItems++; warnings.push("shipped fulfilment without usable ShipmentDate: " + docNo); continue; }
            if (dates.length > 1) shipDateAmbiguous++;   // 한 fulfilment 안 복수 날짜 — 첫 값 사용(실측 전 방어)
            const shipDate = dates[0];
            // ⚠️ line_ref = <fulfilment TaskID>:<ProductID> — occurred_on 이 유니크 키에 없어 분할
            //   출하(같은 SKU·같은 bin)에서 키가 완전히 겹쳐 두 번째 출고가 조용히 버려진다
            //   (2026-08-17 채택). TaskID 는 재수집에도 안정 — 배열 인덱스는 void·재정렬에 흔들린다.
            let fid = String(f?.TaskID ?? "").trim();
            if (!fid) { fid = "f" + (fi + 1); bump("fulfilment_taskid_fallback"); }
            const pickLines = (f?.Pick?.Lines ?? []) as any[];
            pickLineCount += pickLines.length;
            for (const line of pickLines) {
              const q = Number(line?.Quantity ?? 0);
              if (q === 0) { zeroQtyLines++; continue; }
              const loc = locOf(line, docNo);
              rows.push({
                doc_type: cfg.docType, doc_number: docNo, doc_task_id: id || null, source: "cin7",
                occurred_on: shipDate, seq_hint: 2,
                sku: String(line?.SKU ?? "").trim(), warehouse: loc.warehouse, bin: loc.bin,
                qty_delta: -q, event_type: "sale_out",
                line_ref: fid + ":" + pidOf(line),
                amount: null,
                raw: mkRaw(line, { ...header, fulfilment_task_id: fid, ship_date: shipDate }, "sale_out: -Quantity(" + q + ") shipped pick line"),
              });
            }
          }
        } else if (key === "purchase") {
          const header = { order_number: docNo, purchase_id: id, type: row?.Type ?? null };
          // ⚠️ Advanced=배열 · Simple=객체 (실측 — 원장 스킬 함정 표)
          const blocks = Array.isArray(det?.StockReceived) ? det.StockReceived
            : det?.StockReceived ? [det.StockReceived] : [];
          for (const b of blocks) {
            const bst = norm(b?.Status);
            srBlockStatusCounts[bst || "(empty)"] = (srBlockStatusCounts[bst || "(empty)"] ?? 0) + 1;
            // ⚠️ DRAFT 블록만 제외 — 승인 전이라 재고가 안 움직인다(실측 PO-01083 DRAFT 194개 재고에
            //   없음). 빈 문자열 Status 는 처리한다(실측 PO-01128 — 재고 들어감) — 건수만 보고.
            if (bst === "DRAFT") { draftBlocksSkipped++; continue; }
            if (bst === "") emptyStatusBlocks++;
            for (const line of (b?.Lines ?? []) as any[]) {
              const q = Number(line?.Quantity ?? 0);
              if (q === 0) { zeroQtyLines++; continue; }
              const d = dateOnly(line?.Date);   // ⚠️ 날짜는 라인 단위(실측 4/4) — 분할 입고도 정확
              if (!d) { missingDateItems++; continue; }
              const loc = locOf(line, docNo);
              rows.push({
                doc_type: cfg.docType, doc_number: docNo, doc_task_id: id || null, source: "cin7",
                occurred_on: d, seq_hint: 1,
                sku: String(line?.SKU ?? "").trim(), warehouse: loc.warehouse, bin: loc.bin,
                qty_delta: q, event_type: "po_in",
                // line_ref 는 다른 소스와 통일해 ProductID(WMS cin7_po_line_id 선례) —
                // 진짜 라인 식별자 CardID 는 raw.line 원문에 그대로 남는다.
                line_ref: pidOf(line),
                amount: null,
                raw: mkRaw(line, { ...header, block_status: b?.Status ?? null }, "po_in: +Quantity(" + q + ") stock received line"),
              });
            }
          }
        } else {   // creditnote
          const header = { order_number: docNo, sale_id: id };
          const cns = (det?.CreditNotes ?? []) as any[];   // ⚠️ 한 오더에 여러 개(실측 SO-00062) — 전부 순회
          creditNotesSeen += cns.length;
          for (const cn of cns) {
            const rst = norm(cn?.RestockStatus);
            restockStatusCounts[rst || "(empty)"] = (restockStatusCounts[rst || "(empty)"] ?? 0) + 1;
            if (rst !== "AUTHORISED") continue;   // DRAFT 는 Restock 이 비어 있다 — 금액만, 재고 미복귀
            const restock = (cn?.Restock ?? []) as any[];
            if (!restock.length) { emptyRestock++; continue; }
            const d = dateOnly(cn?.CreditNoteDate);
            if (!d) { missingDateItems++; warnings.push("credit note without usable CreditNoteDate: " + docNo); continue; }
            // ⚠️ doc_number = CreditNoteNumber — 오더번호가 아니다. 한 오더에 CN 이 여럿이라
            //   오더번호를 쓰면 유니크 키가 깨진다.
            const cnNo = String(cn?.CreditNoteNumber ?? "").trim();
            if (!cnNo) { noCnNumber++; warnings.push("credit note without CreditNoteNumber on " + docNo + " - rows skipped (unique key would collide)"); continue; }
            for (const line of restock) {
              const q = Number(line?.Quantity ?? 0);
              if (q === 0) { zeroQtyLines++; continue; }
              const loc = locOf(line, docNo);
              rows.push({
                doc_type: cfg.docType, doc_number: cnNo, doc_task_id: id || null, source: "cin7",
                occurred_on: d, seq_hint: 1,
                sku: String(line?.SKU ?? "").trim(), warehouse: loc.warehouse, bin: loc.bin,
                qty_delta: q, event_type: "credit_in",
                line_ref: pidOf(line),
                amount: null,
                raw: mkRaw(line, { ...header, credit_note_number: cnNo, credit_note_date: cn?.CreditNoteDate ?? null }, "credit_in: +Quantity(" + q + ") restock line"),
              });
            }
          }
        }

        sink.push(rows);
        docsProcessed++;
        if (cd.updated) lastProcessedUpdated = cd.updated;
      }

      // 4) 커서 (would-be) — 파일 상단 캡 보정 절:
      //    비캡 회차 = 회차 시작 시각(문서 상태로 멈추지 않는다 — 미완료 문서는 갱신되면 재등장)
      //    캡 회차   = 마지막 처리 문서의 Updated(오름차순 처리 전제 — 캡 밖 후보를 다음 회차가 이어받음)
      const runStartIso = new Date(t0).toISOString();
      const cursorWouldBe = detailCapped ? (lastProcessedUpdated ?? cursorBefore) : runStartIso;

      Object.assign(R, {
        list_total: listTotal, list_received: listReceived, pages, truncated,
        list_aborted: listAborted,
        since_used: sinceUsed,
        since_source: sinceSource,
        from_since_param_ignored: paramIgnored || undefined,
        // ⚠️ 하한 없음 = 전량 수신 — 눈에 띄게 (floor_alert 와 동형)
        since_alert: sinceSource === "none" ? "NO SINCE - pulling the FULL list; pass ?from_since= or seed inv_sync_state" : undefined,
        updated_since_requested: updatedSinceReq,   // 커서 − 1일 (겹침 수신)
        cursor_before: cursorBefore,
        cursor_after: commit ? cursorWouldBe : cursorBefore,   // dry 는 커서 무변
        cursor_after_would_be: cursorWouldBe,
        candidates: cands.length,
        filter_counts: filterCounts,
        no_updated_field: noUpdatedField,
        detail_fetched: detailFetched,
        docs_processed: docsProcessed,
        detail_capped: detailCapped,
        detail_capped_reason: detailCapReason,
        detail_capped_remaining: cappedRemaining,
        // ⚠️ 시끄러운 캡 보고 — 캡 회차의 커서 보정 덕에 유실은 없지만, "적게 나온 게 정상" 오해 방지
        detail_capped_alert: detailCapped
          ? "CAPPED - " + cappedRemaining + " candidate doc(s) NOT processed this round; cursor stops at the last processed doc's Updated so the next run continues"
          : undefined,
        ledger_rows: sink.rows.length,
        zero_qty_lines: zeroQtyLines,
        since_filtered_rows: sink.stats.since_filtered_rows,
        missing_date_items: missingDateItems,
        merged_lines: sink.stats.merged_lines,
        merged_lines_alert: sink.stats.merged_lines > 0 ? "NOT ZERO - the line_ref assumption is broken, inspect raw.merged_lines_raw" : null,
        empty_sku_lines: sink.stats.empty_sku_lines,
        empty_sku_alert: sink.stats.empty_sku_lines > 0 ? "NOT ZERO - parsing is wrong for this source; commit is blocked until fixed" : undefined,
        field_fallbacks: fieldFallbacks,
        date_histogram: sink.dateHist,
        samples: sink.rows.slice(0, 5),
        warnings,
      });
      if (sink.stats.empty_sku_lines > 0) warnings.push(sink.stats.empty_sku_lines + " line(s) dropped for empty sku - parsing is wrong for this source");
      if (key === "sale") {
        Object.assign(R, {
          fulfilments_seen: fulfilmentsSeen,
          no_ship_fulfilments: noShipFulfilments,
          ship_date_ambiguous: shipDateAmbiguous,
          avg_pick_lines_per_doc: docsProcessed ? Math.round((pickLineCount / docsProcessed) * 10) / 10 : null,
        });
      } else if (key === "purchase") {
        Object.assign(R, {
          advanced_docs: advancedCount,
          simple_docs: simpleCount,
          list_stock_received_status_counts: srsCounts,
          sr_block_status_counts: srBlockStatusCounts,
          draft_blocks_skipped: draftBlocksSkipped,
          empty_status_blocks: emptyStatusBlocks,
        });
      } else {
        Object.assign(R, {
          credit_notes_seen: creditNotesSeen,
          restock_status_counts: restockStatusCounts,
          empty_restock: emptyRestock,
          no_cn_number: noCnNumber,
        });
      }

      // 5) commit (⑤에서 켠다) — all-or-nothing per source (runSource 와 같은 조건).
      //    커서 저장값 = cursorWouldBe (캡 회차면 마지막 처리 문서 Updated · 아니면 회차 시작 시각).
      if (commit) {
        let blocked: string | null = null;
        if (listAborted) blocked = "list_aborted: " + listAborted;
        else if (truncated) blocked = "list truncated";
        else if (unmappedInSource > 0) blocked = "UNMAPPED location in " + unmappedInSource + " row(s) - fix map first (rows would be permanent)";
        else if (sink.stats.empty_sku_lines > 0) blocked = sink.stats.empty_sku_lines + " line(s) with empty sku - parsing is wrong, the rest of this source cannot be trusted";
        else if (missingDateItems > 0) blocked = missingDateItems + " item(s) without usable date";
        if (blocked) {
          R.write_skipped = blocked;
        } else {
          for (let i = 0; i < sink.rows.length; i += INSERT_BATCH) {
            await sbInsertIgnoreDup("inv_ledger", LEDGER_CONFLICT, sink.rows.slice(i, i + INSERT_BATCH));
          }
          await sbUpsert("inv_sync_state", "source_key", [{
            source_key: key,
            last_cursor: cursorWouldBe,
            last_run_at: new Date().toISOString(),
            last_ok_at: new Date().toISOString(),
            note: COLLECTOR_VERSION + " rows=" + sink.rows.length + (detailCapped ? " capped" : ""),
          }]);
          R.written = sink.rows.length;
        }
      }
      results[key] = R;
    }

    for (const key of runKeys) {
      if (timeLeft() < 3_000) { results[key] = { aborted: "time budget exhausted before this source" }; continue; }
      if (SOURCES[key]) await runSource(key);
      else await runDateSource(key);
    }

    const out = {
      ok: true,
      ...global,
      results,
      // 전역 경고 둘 — unmapped(맵에 없는 ID)와 unexpected(맵에는 있는데 알려진 창고가 아님)는 다른 등급
      unmapped_location_ids: [...unmapped.values()].map((u) => ({ id: u.id, name_fallback: u.name_fallback, count: u.count, sources: [...u.sources].slice(0, 5) })),
      unexpected_warehouses: [...unexpectedWarehouses].map(([name, hits]) => ({ name, resolve_hits: hits })),
      duration_ms: Date.now() - t0,
    };
    return json(out);
  } catch (e) {
    return json({ ok: false, error: String(e).slice(0, 500), duration_ms: Date.now() - t0 }, 500);
  }
});

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj, null, 2), {
    status, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}
