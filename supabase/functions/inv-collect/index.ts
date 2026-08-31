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
// 문서 상태 skip (2026-08-31 · 결함 D — inv_doc_state · 상세는 loadDocState/docStateSkip 절):
//   [실사고] 비종결 3건이 커서를 잡은 채 위 후보 159건 중 154건(COMPLETED — 이미 원장에 있고
//   안 바뀜)을 매 회차 다시 읽어 캡 40 을 소진 → TR-04330(−144)이 hold_capped 뒤에 갇혀 영영
//   누락(BMA15710 대조 차이 144). → 문서별 「마지막으로 본 목록 수정 시각」을 기록하고 값이
//   같으면 상세를 부르지 않는다. skip 문서도 커서 전진에 포함(처리한 것으로 취급).
//   ⚠️ 비종결(process_nonterminal)은 절대 skip 하지 않는다. ?recheck=1 = 그 회차만 판정 OFF
//   (전수 재확인 — 기록·커서는 평소대로 · 캡 때문에 여러 회차 분할 전제).
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
// ⚠️ 커서 tie-breaker (2026-08-30 결함 C — cursorKeyOf 절 주석이 정본): 정렬·필터·커서의
//   단위는 Updated 단독이 아니라 **<Updated>|<문서식별자>** 키다 — Updated 동률 그룹이 캡보다
//   크면(실측: 밀리초까지 같은 238건 = Cin7 플랫폼 일괄 갱신) Updated 단독 커서는 그룹 안에서
//   영원히 제자리였다(하루 반 동결·cron 은 매번 succeeded). 증상 가드 = decideCursor.cursorStalled.
// · 판매: VOIDED·비 SHIPPED 제외(⚠️ 배송 전엔 재고가 안 빠진다 — 픽·팩은 Allocated 일 뿐).
//   fulfilment 단위 처리 — Ship.Lines 의 ShipmentDate(IsShipped true 만)가 원장 날짜
//   (실측 3/3 일치) · Pick.Lines 가 실제 나간 SKU·수량(−).
//   ⚠️ line_ref = <fulfilment TaskID>:<ProductID> — occurred_on 이 유니크 키에 없어 분할
//   출하에서 같은 SKU·같은 bin 이면 키가 완전히 겹쳐 두 번째 출고가 조용히 버려진다.
//   TaskID 는 재수집에도 안정(인덱스는 fulfilment void·재정렬에 흔들린다).
// · 발주 (⚠️⚠️ 2026-08-18 재설계 — docs/sessions/2026-08-18-purchase-putaway-axis.md 가 근거.
//   옛 서술이 왜 틀렸는지를 남긴다 — 지우면 같은 오류를 또 저지른다):
//   목록 제외 = VOID·IsServiceOnly 만. ~~StockReceivedStatus 없음/NOT AVAILABLE 제외~~ 폐기 —
//   목록 값과 상세 블록 값은 양방향으로 어긋난다(표본 6건 중 Advanced 4건 = PO-00848·00931·
//   01048·01065, 12,552u 전부 실재 입고인데 문서째 지워졌다). 이제 분포만 센다.
//   축: **Advanced = PutAway**(bin 있음·확정 반영) / Simple = StockReceived(bin 있음 —
//   PO-00874). ~~"Advanced 는 StockReceived 배열을 읽는다"~~ 폐기 — SR 라인은 LocationID 가
//   null(창고 결손 = UNMAPPED)이고 SR Status 는 stock receiving 단계의 워크플로 상태다
//   (PO-00703 SR=DRAFT/PA=AUTHORISED 62줄 FULLY RECEIVED · PO-01131 SR=NOT AVAILABLE/
//   PA=AUTHORISED 3,570u). 그래서 ~~"블록 DRAFT 제외"~~(PO-01083 표본 하나의 일반화 — DRAFT 가
//   곧 미반영이라는 뜻이 아니었다)와 ~~"빈 문자열 통과"~~(PO-01128 의 빈 상태는 SR 블록이었고
//   PA 는 AUTHORISED 84줄 — PA 축에선 근거 소멸)이 둘 다 사라졌다. 블록 화이트리스트 =
//   두 축 모두 **AUTHORISED 만** + 미지값 경고. Advanced 인데 PA 없음 = 행 미기표 + 보고
//   (커서는 안 멈춘다 — 재등장 전제 미확인). 날짜 = Lines[].Date 유지(분할 입고는 블록이
//   아니라 라인 날짜로 갈린다 — PO-00703 블록 1개에 두 날짜).
//   ~~line_ref = ProductID(다른 소스와 통일)~~ 폐기 → **CardID**: PA 는 같은 SKU 를 빈 단위로
//   쪼개고 같은 빈·같은 SKU 가 날짜만 달라 두 줄인 사례 실재(PO-00944 KUZ77036 — 유니크 키에
//   occurred_on 이 없어 ProductID 면 뭉개진다. 유일성 실측 ProductID 94/97·109/110 vs
//   CardID 97/97·110/110. ⚠️ CardID 재수집 안정성 미확인 — 관찰 대상).
//   Type 은 가변(입고 후 Advanced 전환 관행 — simple_docs 0 은 정상. 전환이 LastUpdatedDate 를
//   올려 모든 PO 가 최소 두 번 UpdatedSince 에 잡힌다 = DO NOTHING 수정 미반영 문제가 일상).
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

const COLLECTOR_VERSION = "inv-collect@2026-08-31.4";   // raw 에 박는다 — 규칙이 바뀌면 올릴 것 (08-31.4 = ⚠️⚠️ 트랜스퍼 출발 bin — 헤더에서 bin 을 못 얻은 transfer_out(비 IN_TRANSIT)에 WMS 픽 bin 을 채운다(Reference 의 픽용 SO → wms_order_lines.bin_location · 실측 112/112 일치). **행 생성 규칙 변경** — 유니크 키의 bin 이 바뀌므로 기존 bin="" 행과 키가 갈린다: 재수집되는 문서는 새 bin 행이 추가되고 옛 "" 행은 scripts/fix-transfer-bins.mjs 로 상쇄한다. 소멸 감지에는 「bin 변경」 예외(partitionBinChanged)를 함께 넣어 옛 행이 매 회차 「사라짐」으로 검출돼 캡 500 을 소진하는 것을 막았다(missing_lines_bin_changed 로 카운트만). 이전 08-31.3 = 롤링 재확인 — skip 예정 중 seen_at 최고령 5건/회차 강제 재조회(inv_doc_state 검산 상시화 · 응답 rolling_* 추가). 원장 행 생성 규칙은 무변 · 이전 08-31.2 = 회차 로그 inv_collect_runs — commit 회차를 테이블에 남긴다(dry 미기록 · 응답 collect_run_logged/collect_run_error 추가). 원장 행 생성 규칙은 무변 · 이전 08-31.1 = 결함 D — inv_doc_state 문서 상태 skip: 변경 없는 종결 문서는 상세 미조회(skip_unchanged) + ?recheck=1 전수 재확인. 원장 행 생성 규칙은 무변 · 이전 08-30.1 = ②-b 커서 tie-breaker <Updated>|<식별자> + cursor_stalled 증상 가드 — 결함 C·판매 하루 반 동결 실사고. 원장 행 생성 규칙은 무변 · 이전 08-25.1 = 라인 소멸 감지(inv_missing_lines — TR-04175 실사고: 수집 후 Cin7 라인 138줄 삭제를 아무도 몰라 이중 차감·unknown 138 · 같은 날 검토 조정: 검출/기록 try/catch(진단은 수집을 안 막는다)·문서 캡 200→1500 — 규칙 변경 아님이라 버전 유지) · 08-24.1 = 비재고 SKU 게이트 · 08-19.1 = 페이싱·inv_conflicts)
const LIST_PAGE_LIMIT = 1000;
const MAX_LIST_PAGES = 12;             // 실측 2/4/1 페이지 — 성장 대비 하드캡(truncated 가 신호)
const LIST_SLEEP_MS = 400;
const DETAIL_SLEEP_MS = 1200;          // = 분당 50콜 (간격 ms = 60,000 ÷ 목표 분당 콜수) — 한도 60/60 의 여유분.
                                       //   ~~700ms~~ 는 분당 85.7콜 = **한도의 1.43배**였다(2026-08-18 밤 실측 확정 —
                                       //   429 본문 명문 "60 calls per 60 seconds" · 애플리케이션 키 단위 ·
                                       //   ⚠️ 200 응답엔 x-ratelimit-* 헤더가 없어 사전 제어 불가).
                                       //   같은 WMS 키를 hello(5분 폴링)·receiving·product-images·inv-snapshot 이
                                       //   공유하므로 한도를 통째로 쓸 수 없다.
const MAX_DETAIL_PER_SOURCE = 40;      // ⚠️ 40 의 근거(2026-08-19 확정): 사전 제어가 불가능하므로(위) 회차당
                                       //   호출 수를 미리 묶는 것이 유일한 예방책이고 **1,200ms × 40 = 48초 < 60초 창**.
                                       //   ⚠️ 캡을 올리려면 간격도 함께 봐야 한다 — 캡 55 × 1,200ms = 66초로 창을 넘는다.
                                       //   판매 하루 후보 145(캡의 3.6배)의 해결은 캡 상향이 아니라 **회차 주기**다
                                       //   (설계 정본 4부 1번 — ⑤에서 소스별 캡·주기 결정). 잘리면 detail_capped 로 시끄럽게 보고.
const ROLLING_RECHECK_PER_RUN = 5;     // 롤링 재확인(2026-08-31 · pickRollingRecheck 절): skip 예정 문서 중
                                       //   inv_doc_state.seen_at 최고령 N건을 매 회차 강제 재조회 — last_modified 를
                                       //   믿게 된 대가의 상시 검산. 처리되면 seen_at 이 갱신돼 자연히 회전한다
                                       //   ([계산] 트랜스퍼 156건 · 5분 주기 · N=5 = 약 2.6시간에 한 바퀴).
                                       //   캡 부담 거의 없음 — 현행 상세 5건 + 5건 = 10건 << 캡 40.
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
// ── 원장 쓰기 + 변경 감지 (2026-08-19 · ⑤ 게이트 4번 — 마이그레이션 20260819000000_inv_conflicts) ──
// ignore-duplicates 는 유니크 키가 겹치면 행을 조용히 버린다 — 재수집이 일상이라 그 자체는 의도.
// ⚠️ 문제는 「키는 같은데 값이 다른」 경우: [실측 2026-08-19] PO-01117 CAN01620 168→192 —
//   PO 를 닫으려고 인보이스 수량으로 채우는 **정상 실무**(정본 1부 「미달·초과 입고의 실무 흐름」).
//   그대로 두면 새 값이 아무 데도 안 남는다(pg_cron 자동 회차의 응답은 아무도 안 본다) →
//   inv_conflicts 에 기록해 ⑥ 대조에서 "왜 어긋났나"를 답하는 유일한 기록으로 남긴다.
// ⚠️ 쓰기를 차단하지 않는다(수량 정정은 흔한 정상 실무 — blocked 조건 아님, 경고·기록만) ·
//   원장 행은 안 고친다(append-only — 역분개는 자리 단위 과제, 정본 4부 3번) · 알림·화면 없음.
// 두 단계 — 전량 조회는 하지 않는다:
//   1) return=representation + select=키 7종만 으로 **실제 삽입된 행**을 돌려받아 버려진 행을
//      특정한다(응답은 raw 없이 키만이라 500행 배치 ≈ 수십 KB — EF 메모리에 무해).
//      ⚠️ 매칭은 배열 순서가 아니라 유니크 키 7종으로(PostgREST 가 순서를 보장한다는 근거 없음).
//   2) 버려진 행만 (doc_type, doc_number) 로 묶고 **line_ref 를 50개씩 in.() 청크**로 조회해 비교 —
//      doc_number 단독 조회는 대형 트랜스퍼(344라인×4행=1,376행/문서)에서 1000행 캡에 잘린다(규칙 20).
//      qty_delta·occurred_on 이 같으면 아무것도 안 한다(정상 재수집).
async function writeLedgerDetectingConflicts(rows: LedgerRow[], sourceKey: string): Promise<{
  inserted: number; insert_skipped: number; conflicts_detected: number; conflicts_sample: string[];
}> {
  const keyOf = (r: any) => [r.doc_type, r.doc_number, r.line_ref, r.event_type, r.warehouse, r.bin, r.sku].join("\u0001");
  const skipped: LedgerRow[] = [];
  let inserted = 0;
  for (let i = 0; i < rows.length; i += INSERT_BATCH) {
    const batch = rows.slice(i, i + INSERT_BATCH);
    const r = await fetch(SB_URL() + "/rest/v1/inv_ledger?on_conflict=" + LEDGER_CONFLICT + "&select=" + LEDGER_CONFLICT, {
      method: "POST",
      headers: sbHeaders({ Prefer: "resolution=ignore-duplicates,return=representation" }),
      body: JSON.stringify(batch),
    });
    if (!r.ok) throw new Error("sbInsert inv_ledger " + r.status + ": " + (await r.text()).slice(0, 400));
    const returned = (await r.json()) as any[];
    inserted += returned.length;
    const got = new Set(returned.map(keyOf));
    for (const row of batch) if (!got.has(keyOf(row))) skipped.push(row);
  }
  const conflicts: any[] = [];
  const sample: string[] = [];
  if (skipped.length) {
    const byDoc = new Map<string, LedgerRow[]>();
    for (const row of skipped) {
      const k = row.doc_type + "\u0001" + row.doc_number;
      let arr = byDoc.get(k); if (!arr) { arr = []; byDoc.set(k, arr); }
      arr.push(row);
    }
    for (const [dk, docRows] of byDoc) {
      const [docType, docNumber] = dk.split("\u0001");
      const refs = [...new Set(docRows.map((r) => r.line_ref))];
      const existing = new Map<string, any>();
      for (let i = 0; i < refs.length; i += 50) {
        const rows2 = await sbGet(
          "inv_ledger?select=" + LEDGER_CONFLICT + ",qty_delta,occurred_on" +
          "&doc_type=eq." + encodeURIComponent(docType) +
          "&doc_number=eq." + encodeURIComponent(docNumber) +
          "&line_ref=in.(" + encodeURIComponent(refs.slice(i, i + 50).map((v) => '"' + String(v).replace(/"/g, '\\"') + '"').join(",")) + ")"
        );
        for (const er of rows2) existing.set(keyOf(er), er);
      }
      for (const row of docRows) {
        const ex = existing.get(keyOf(row));
        if (!ex) continue;   // 이론상 없음(방금 충돌이 났으니 행이 있다) — 경합 등 엣지는 조용히 넘긴다
        const exQty = Number(ex.qty_delta), inQty = Number(row.qty_delta);
        const exOn = String(ex.occurred_on), inOn = String(row.occurred_on);
        if (exQty === inQty && exOn === inOn) continue;   // 정상 재수집 — 아무것도 하지 않는다
        conflicts.push({
          doc_type: row.doc_type, doc_number: row.doc_number, line_ref: row.line_ref,
          event_type: row.event_type, warehouse: row.warehouse, bin: row.bin, sku: row.sku,
          existing_qty: exQty, incoming_qty: inQty,
          existing_occurred_on: exOn, incoming_occurred_on: inOn,
          source: sourceKey, collector: COLLECTOR_VERSION,
          incoming_raw: (row.raw as any)?.line ?? null,   // 해당 라인만 — 원장 raw 관례(문서 전체 금지)
        });
        if (sample.length < 5) {
          sample.push(row.doc_number + "/" + row.sku + ": " +
            (exQty !== inQty ? exQty + "\u2192" + inQty : exOn + "\u2192" + inOn + " (date)"));
        }
      }
    }
    for (let i = 0; i < conflicts.length; i += INSERT_BATCH) {
      const r = await fetch(SB_URL() + "/rest/v1/inv_conflicts", {
        method: "POST",
        headers: sbHeaders({ Prefer: "return=minimal" }),
        body: JSON.stringify(conflicts.slice(i, i + INSERT_BATCH)),
      });
      if (!r.ok) throw new Error("sbInsert inv_conflicts " + r.status + ": " + (await r.text()).slice(0, 400));
    }
  }
  return { inserted, insert_skipped: skipped.length, conflicts_detected: conflicts.length, conflicts_sample: sample };
}
// ── 라인 소멸 감지 (2026-08-25 · 마이그레이션 20260825142042_inv_missing_lines) ──
// 배경 [실사고 TR-04175]: 원장은 append-only 라 Cin7 라인 삭제에 아무 신호가 없다 — 8/21 195줄
// 수집 → 8/24 Cin7 에서 138줄 삭제 → 원장 195행 잔존 = 토론토 138 SKU 이중 차감·대조 unknown 138.
// B(원장의 그 문서 행 · source='cin7' 만 — G2: manual 상쇄 행 제외) − A(이번 상세가 만든 행) =
// 사라진 라인. ⚠️ 기록·경보만 — 원장 무접촉·자동 정정 없음(유령 판정은 사람이 Cin7 화면으로).
// ⚠️ A 는 sink 필터 **전**의 rows 기준이다 — since 필터·비재고 게이트로 걸러진 라인은 Cin7 에
//   실재하므로 A 에 있어야 오탐이 없다(sink.rows 기준이면 그것들이 전부 "사라진 라인"이 된다).
// 판정 게이트(넷 다 필수 — 호출부):
//   G1 상세를 실제 조회하고 rows 를 만든 문서만(sink.push 도달 = processed/processed_nonterminal).
//      ⚠️ ②-b 는 문서 안 부분 스킵(미배송 fulfilment·비 AUTHORISED 블록·날짜 결손 라인 등)이
//      있으면 그 문서를 통째로 제외(docIncomplete) — 집합이 불완전하면 "삭제됨"으로 오판한다.
//   G2 source='cin7' 만 B 에 (아래 쿼리).
//   G3 회차 중단(list_aborted·truncated·detail cap·time)이면 소스 전체 skip (호출부).
//   G4 last_modified_on 없으면 그 문서 skip + 카운트 (키가 무너진다 — 호출부).
// ⚠️⚠️ 키 생성 규칙(bin·line_ref·warehouse)을 바꾸면 기존 원장 행이 전부 "사라진 라인"으로
//   검출된다(A 는 새 규칙·B 는 옛 규칙 — 집합이 통째로 어긋난다). 그런 변경을 배포할 때는
//   검출을 일시 정지하거나 기존 원장 행을 함께 마이그레이션할 것.
//   [발동 2026-08-31] 트랜스퍼 출발 bin 해결(loadTransferBinMap 절)이 정확히 이 변경이다 —
//   옛 bin="" 행의 키가 새 A 집합에 영원히 없어 매 회차 734행이 「사라짐」으로 검출되고,
//   inv_missing_lines 는 유니크 키가 막지만 **회차 캡 500 을 매번 소진해 진짜 소멸을 가린다**
//   (⚠️ 상쇄로도 안 없어진다 — 옛 cin7 행은 B 집합에 그대로 남는다).
//   ⇒ **처방 = 「bin 변경」 예외**(아래 partitionBinChanged): bin 만 다른 행이 A 에 있으면
//   소멸이 아니라 bin_changed 로 센다. **앞으로의 어떤 bin 규칙 변경에도 이 예외가 방어한다.**
//   line_ref·sku·warehouse 변경은 여전히 마이그레이션 동반이 필요하다.
//   · [전례] 발주 line_ref ProductID → CardID (2026-08-18).
const MISSING_MAX_PER_DOC = 1500;  // 문서당 상한 — 유니크 키는 DB 축적만 막고 EF 는 매 회차 계산하므로 별도 상한.
                                   //   ⚠️ 200 → 1500 (2026-08-25 검토): TR-04175 실물이 B−A=276(SKU 195×2 leg 중
                                   //   57×2 잔존)이라 첫 실사용부터 200 에 걸려 76건이 잘렸다. 대형 트랜스퍼는
                                   //   문서당 1,376행(344라인×4) — 전량 삭제까지 안 잘리게 1,500. 검출 목록은
                                   //   사람이 상쇄 SQL 을 만드는 재료라 잘리면 쓸모가 준다. 폭주는 회차 캡이 막는다.
const MISSING_MAX_PER_RUN = 500;   // 소스 회차당 상한
const MISSING_CONFLICT = LEDGER_CONFLICT + ",last_modified_on";   // = inv_missing_lines_uq 순서
type MissingDocCheck = { docNumber: string; lmo: string; docStatus: string | null; keys: Set<string> };
const ledgerKeyOf = (r: any) => [r.doc_type, r.doc_number, r.line_ref, r.event_type, r.warehouse, r.bin, r.sku].join("\u0001");
// ── 「bin 변경」 예외 (2026-08-31 — 스킬 「키 변경 시 소멸 감지가 원장 전체를 삭제됨으로
//    잡는다」 경고의 처방) ──
// B−A 후보 중, **bin 만 다른 행이 A 에 있으면** 소멸이 아니다 — 같은 라인이 새 bin 규칙으로
// 다시 기표된 것이다(트랜스퍼 출발 bin 해결 @2026-08-31.4 가 첫 사례: 옛 bin="" 행 734개가
// 매 회차 「사라짐」으로 검출돼 회차 캡 500 을 소진, 진짜 소멸을 가렸다. 상쇄로도 안 없어진다 —
// 옛 cin7 행은 B 에 그대로 남는다). **앞으로의 어떤 bin 규칙 변경에도 이 예외가 방어한다.**
// ⚠️ 예외는 bin 축에만 — 비교 키는 7키에서 bin 만 뺀 6키(doc_type·doc_number·line_ref·
//   event_type·warehouse·sku 전부 동일 = 정확히 「bin 만 다른」)다. line_ref·sku·warehouse 가
//   바뀌면 종전대로 소멸이다. 순수 함수 — 테스트 ⑪~⑬(scripts/test-invcollect-transferbin.mjs).
type BinChangedPartition = { kept: any[]; binChanged: number };
// ⚠️ 시그니처에 { 를 두지 않는다 — 테스트의 원문 추출(균형 중괄호) 관례
function partitionBinChanged(missing: any[], aKeys: Set<string>): BinChangedPartition {
  const aNoBin = new Set<string>();
  for (const k of aKeys) { const p = String(k).split("\u0001"); p.splice(5, 1); aNoBin.add(p.join("\u0001")); }
  let binChanged = 0;
  const kept = missing.filter((er) => {
    const noBin = [er.doc_type, er.doc_number, er.line_ref, er.event_type, er.warehouse, er.sku].join("\u0001");
    if (aNoBin.has(noBin)) { binChanged++; return false; }
    return true;
  });
  return { kept, binChanged };
}
async function detectMissingLines(docType: string, docs: MissingDocCheck[], warnings: string[]): Promise<{
  rows: any[]; detected: number; sample: string[]; capped: boolean; binChanged: number;
}> {
  const out: any[] = []; const sample: string[] = []; let capped = false; let binChanged = 0;
  for (const d of docs) {
    if (out.length >= MISSING_MAX_PER_RUN) { capped = true; warnings.push("missing-lines run cap " + MISSING_MAX_PER_RUN + " reached - remaining docs not checked this round"); break; }
    // B — 대형 문서(트랜스퍼 344라인×4행=1,376행/문서 실측)가 1000행 캡을 넘으므로 Range 페이지네이션
    const bRows: any[] = [];
    for (let off = 0; ; off += 1000) {
      const r = await fetch(SB_URL() + "/rest/v1/inv_ledger?select=" + LEDGER_CONFLICT + ",qty_delta,occurred_on,id" +
        "&doc_type=eq." + encodeURIComponent(docType) +
        "&doc_number=eq." + encodeURIComponent(d.docNumber) +
        "&source=eq.cin7&order=id.asc",
        { headers: sbHeaders({ Range: off + "-" + (off + 999) }) });   // caps-ok: Range 헤더 1000행 페이지네이션 — page<1000 까지 전량 수신 루프
      if (!r.ok) throw new Error("sbGet inv_ledger(missing) " + r.status + ": " + (await r.text()).slice(0, 300));
      const page = (await r.json()) as any[];
      bRows.push(...page);
      if (page.length < 1000) break;
    }
    let missing = bRows.filter((er) => !d.keys.has(ledgerKeyOf(er)));
    // 「bin 변경」 예외 — 캡 검사보다 앞: bin_changed 행이 문서·회차 캡을 소진하면 안 된다(그게 목적)
    const part = partitionBinChanged(missing, d.keys);
    missing = part.kept;
    binChanged += part.binChanged;
    if (missing.length > MISSING_MAX_PER_DOC) {
      warnings.push("missing-lines doc cap: " + d.docNumber + " has " + missing.length + " > " + MISSING_MAX_PER_DOC + " - truncated");
      missing = missing.slice(0, MISSING_MAX_PER_DOC);
      capped = true;
    }
    for (const er of missing) {
      if (out.length >= MISSING_MAX_PER_RUN) { capped = true; break; }
      out.push({
        doc_type: er.doc_type, doc_number: er.doc_number, line_ref: er.line_ref,
        event_type: er.event_type, warehouse: er.warehouse, bin: er.bin, sku: er.sku,
        last_modified_on: d.lmo,
        existing_qty: er.qty_delta, existing_occurred_on: er.occurred_on, existing_ledger_id: er.id,
        doc_status: d.docStatus, collector: COLLECTOR_VERSION,
      });
      if (sample.length < 5) sample.push(er.doc_number + "/" + er.sku + "/" + er.qty_delta);
    }
  }
  return { rows: out, detected: out.length, sample, capped, binChanged };
}
// 쓰기는 commit + write 성공 경로에서만 (dry=1 은 절대 안 쓴다 — 검출 수만 보고).
// ignore-duplicates: 같은 편집(같은 last_modified_on)의 재검출은 do-nothing — 중복 폭주 차단.
async function insertMissingLines(rows: any[]): Promise<number> {
  let inserted = 0;
  for (let i = 0; i < rows.length; i += INSERT_BATCH) {
    const r = await fetch(SB_URL() + "/rest/v1/inv_missing_lines?on_conflict=" + MISSING_CONFLICT + "&select=id", {
      method: "POST",
      headers: sbHeaders({ Prefer: "resolution=ignore-duplicates,return=representation" }),
      body: JSON.stringify(rows.slice(i, i + INSERT_BATCH)),
    });
    if (!r.ok) throw new Error("sbInsert inv_missing_lines " + r.status + ": " + (await r.text()).slice(0, 400));
    inserted += ((await r.json()) as any[]).length;
  }
  return inserted;
}
async function sbUpsert(table: string, conflictCol: string, rows: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + table + "?on_conflict=" + conflictCol, {
    method: "POST",
    headers: sbHeaders({ Prefer: "resolution=merge-duplicates,return=minimal" }),
    body: JSON.stringify(rows),
  });
  if (!r.ok) throw new Error("sbUpsert " + table + " " + r.status + ": " + (await r.text()).slice(0, 400));
}

// ── 문서 상태 skip (2026-08-31 · 결함 D — 마이그레이션 20260831140218_inv_doc_state) ──
// [실사고 2026-08-31] ②-a 는 비종결 문서(IN TRANSIT) 앞에서 커서가 멈추는데(설계대로), 그 위
//   문서가 상세 캡(40건/120초)을 넘으면 뒤쪽이 영영 안 들어온다: transfer 후보 159건 중 154건이
//   COMPLETED(이미 원장에 있고 안 바뀜)인데 매 회차 다시 읽어 캡을 소진 — TR-04330(8/28 · −144)
//   누락 = BMA15710 대조 차이 144. [08-27 은 capped_remaining 0 — 문서가 늘며 조용히 넘었다.]
// 처방: 문서별 「마지막으로 본 목록 수정 시각」을 inv_doc_state 에 기록하고, 다음 회차에 목록의
//   값이 같으면 상세를 부르지 않는다(skip_unchanged). [실측 2026-08-31 GAS 프로브] 그 값은 라인
//   편집에 반응한다: SO-15440 라인 삭제 3분 뒤 Updated 갱신 · TR-04175 138줄 삭제 시각 =
//   LastModifiedOn · PO-01117 수량 168→192 는 3주 뒤 LastUpdatedDate — 「값이 같으면 내용도
//   같다」. 반대 방향(내용 무변에 값만 갱신 — 08-28 플랫폼 일괄 갱신 238건)은 한 번 더 읽을 뿐
//   무해. ⚠️ 그래도 믿는 축에는 검산이 필요하다 — Cin7 이 내용을 바꾸면서 값을 안 올리는 경우가
//   있으면 「안 바뀌었다」고 판단해 영영 안 읽는다(놓치는 방향 — 이전(더 읽는 방향)보다 나쁘다).
//   ⇒ 검산 두 겹: ① **롤링 재확인**(상시 — 아래 pickRollingRecheck 절 · 회차마다 seen_at 최고령
//   N건 강제 재조회) ② ?recheck=1(수동 — 그 회차만 판정 OFF · 특정 구간 조사 도구).
// ⚠️ 판정은 종결 문서에만 — ②-a process_nonterminal 은 절대 skip 하지 않는다(도착이 목록 값을
//   바꾸는지 미확인 — 안 바꾸면 3·4행을 영영 못 만든다). ②-b 는 docIncomplete 문서를 기록하지
//   않는 것으로 같은 원칙을 지킨다(기록이 없으면 skip 도 없다).
// ⚠️ last_modified 는 문자열 완전 일치로만 비교 — 파싱 금지(sale/transfer 는 …Z · purchase 는
//   Z 없음 — 타임존 해석이 축마다 다르다. 같은 축의 저장값↔수신값 비교라 형식 차이는 무해).
// ⚠️ 진단·최적화는 수집을 막지 않는다(소멸 감지와 같은 원칙) — 읽기 실패 = 판정 OFF(전량 조회)
//   + doc_state_error · 쓰기 실패 = 경고만(다음 회차 재조회). 쓰기는 commit + 원장 쓰기 성공
//   뒤에만(dry 미기록).
// skip 문서는 missingDocs(A 집합)에 안 들어간다 — G1 동형(상세가 없으면 판정 불가).
//   손실 없음: 라인 삭제는 last_modified 를 바꿔 skip 되지 않는다(위 실측).
type DocStateRow = { source_key: string; doc_number: string; last_modified: string; doc_status: string | null; collector: string };
type DocStateRec = { lastModified: string; seenAt: string };   // seen_at — 롤링 재확인의 회전 축(2026-08-31)
const DOC_STATE_CHUNK = 200;   // in.() 청크 — (source_key, doc_number) PK 조회라 요청당 행수 ≤ 청크 = 1000행 캡에 구조적으로 안 닿는다
async function loadDocState(sourceKey: string, docNumbers: string[]): Promise<Map<string, DocStateRec>> {
  const map = new Map<string, DocStateRec>();
  const uniq = [...new Set(docNumbers.filter(Boolean))];
  for (let i = 0; i < uniq.length; i += DOC_STATE_CHUNK) {
    const chunk = uniq.slice(i, i + DOC_STATE_CHUNK);
    const rows = await sbGet("inv_doc_state?select=doc_number,last_modified,seen_at" +
      "&source_key=eq." + encodeURIComponent(sourceKey) +
      "&doc_number=in.(" + encodeURIComponent(chunk.map((v) => '"' + String(v).replace(/"/g, '\\"') + '"').join(",")) + ")");
    for (const r of rows) map.set(String(r.doc_number), { lastModified: String(r.last_modified), seenAt: String(r.seen_at ?? "") });
  }
  return map;
}
// skip 판정 — ②-a·②-b 공유 헬퍼(테스트 scripts/test-invcollect-docstate.mjs):
//   종결(terminal) ∧ ¬recheck ∧ 기록 존재 ∧ 문자열 완전 일치. 판정 불가(맵 없음 = 읽기 실패 ·
//   식별자/목록 값 결손)는 전부 false = 조회한다 — 틀려도 「한 번 더 읽는」 쪽으로만 틀린다.
function docStateSkip(terminal: boolean, recheck: boolean, state: Map<string, DocStateRec> | null, docNumber: string, listModified: string | null): boolean {
  if (!terminal || recheck) return false;
  if (!state || !docNumber || !listModified) return false;
  return state.get(docNumber)?.lastModified === listModified;
}
// ── 롤링 재확인 (2026-08-31 — last_modified 를 믿게 된 대가의 상시 검산) ──
// skip 예정 문서 중 seen_at 이 가장 오래된 N건은 skip 하지 않고 강제 재조회한다. 처리되면
// seen_at 이 갱신되므로 자연히 회전한다. 재조회 결과 내용이 저장분과 다르면(=값이 안 올라간
// 변경이 실재하면) 유니크 키·소멸 감지가 잡는다 — 놓친 것이 있어도 하루 안에 드러난다.
// ⚠️ 커버리지는 축마다 다르다:
//   · ②-a(transfer·adjustment·assembly) = ⭐ 완전 커버리지 — 매 회차 목록 전량을 받으므로
//     모든 문서가 언젠가 재조회된다. **롤링 재확인의 실질적 대상.**
//   · ②-b(sale·purchase·creditnote) = ⚠️ 최근 창만 — UpdatedSince 로 받으므로 커서보다 오래된
//     문서는 애초에 후보가 아니다. 📌 단 inv_doc_state 가 상황을 악화시키지는 않는다 — Cin7 이
//     변경 시 Updated 를 안 올리면 그 문서는 목록에 아예 안 나온다(이 위험은 inv_doc_state
//     이전부터 있던 것이고 롤링으로도 못 닿는다). 같은 코드를 적용하되(무해 · 최근 창 검산) 한계 명시.
// ⚠️ ?recheck=1 을 cron 으로 돌리는 방식은 버렸다 — recheck 는 skip 판정만 꺼서 후보 전체가
//   상세 대상이 되는데 캡은 40이라 매번 「커서 위 첫 40건」만 반복 = 나머지는 영영 안 본다
//   (「검산하고 있다」는 착각만 남는다 — 안 하는 것보다 나쁠 수 있다). recheck 는 수동 조사
//   도구로 유지 · ⬜ cron 등록하지 않는다.
// ⚠️ 강제 재조회분도 상세 조회라 캡에 포함된다 — 캡이 먼저 걸리면 그 회차는 못 하고 넘어간다
//   (seen_at 이 안 갱신되니 다음 회차에 다시 후보가 된다. 그대로 둔다).
// ⚠️ 진단이 수집을 막지 않는다 — 선정 실패는 롤링만 끄고(평소대로 skip) 경고만(호출부 try/catch).
type RollingEligible = { docNumber: string; seenAt: string };
type RollingPick = { set: Set<string>; oldestSeen: string | null };
// ⚠️ 시그니처에 { 를 두지 않는다 — 테스트의 원문 추출(균형 중괄호)이 본문 첫 { 를 찾는다(관례)
function pickRollingRecheck(eligible: RollingEligible[], n: number): RollingPick {
  // seen_at 오름차순(코드유닛 — timestamptz 문자열이라 성립) 앞 N건. 빈 seenAt 은 맨 앞 = 우선 재조회.
  if (!eligible.length || n <= 0) return { set: new Set(), oldestSeen: null };
  const sorted = [...eligible].sort((a, b) => (a.seenAt < b.seenAt ? -1 : a.seenAt > b.seenAt ? 1 : 0));
  return { set: new Set(sorted.slice(0, n).map((x) => x.docNumber)), oldestSeen: sorted[0].seenAt };
}

// ── 트랜스퍼 출발 bin 해결 (2026-08-31 — 창고 간 이동의 출발 bin 결손) ──
// [실측 2026-08-31 bin 단위 대조] 토론토 8,141칸 중 1,201칸 어긋남(격차 15,640) — 전부
//   창고 간 트랜스퍼 5문서(TR-04173·74·75·04330·04331 · IN TRANSIT) 734행의 출발 bin 결손.
//   유령 bin=''(−) 과 안 뺀 실제 bin(+) 이 거울상이라 **창고 합은 맞아 매일 대조에 안 걸린다.**
// ⚠️ API 다섯 갈래 전부 막다른 길이다 — 다시 파지 말 것:
//   stockTransfer Lines · Order.Lines · /order Lines · apib Line Model(Bin/Location 없음) ·
//   엔드포인트 102개 전수(재고 이동 조회 API 자체가 없다). 픽용 SO 에서 읽기도 불가 —
//   VOID 하면 Pick/Pack/Ship lines 가 0이 된다([실측] SO-15482).
// ⭐ 그런데 그 값이 우리 DB 에 있다: 업무 흐름이 「트랜스퍼 생성 → 같은 내용의 픽용 SO
//   (가상 손님 ASUNG EDM TRANSFER) → Release to WMS → 분할 픽·팩 → SO VOID → 트랜스퍼 확정」
//   이라, WMS 가 보여준 자리에서 작업자가 뺐고 Cin7 이 그 자리에서 차감했다.
//   [실측 TR-04331] Cin7 화면 Export CSV 112줄 vs wms_order_lines.bin_location — **112/112 완전 일치.**
//   연결 고리 = 트랜스퍼 Reference 의 SO 번호(예 "P2_(SO-15482-7,9 / SO-15834-1,2,3)").
//   ⚠️ Reference 는 사람이 손으로 넣는다 — 자동으로 붙지 않는다(없으면 비워두고 카운트).
//   ⚠️ 파트 번호(-1,2,3)는 무시한다 — bin 은 SO 라인당 하나라 어느 팔레트로 갔든 같다.
// ⚠️⚠️ 원칙: **틀린 bin 을 채우느니 비워둔다.** Reference 의 SO + WMS 에 그 SKU 가 있을 때만
//   채우고, 그 외 전부 bin='' 유지 + 카운트 + 경고. 「손님 이름 + 날짜」 같은 폴백 금지 —
//   잘못 이으면 틀린 bin 이 그럴듯하게 들어가고, 비어 있는 것보다 나쁘다(08-30 이중 차감의 교훈).
// ⚠️⚠️ 결합 명시: **원장이 WMS 테이블(wms_orders·wms_order_lines)을 읽는다** —
//   ims-principles 원칙 2(접점은 사건을 남긴다)와 어긋나는 **잠정 조치**다.
//   · 읽기 전용 · 같은 Supabase · WMS 스키마 변경에 취약하다
//   · ⭐ 목표는 WMS 픽이 원장에 **사건을 남기는** 것이다. 그때 이 조회는 사라진다
//   · 그리고 Reference 라는 다리 자체가 「트랜스퍼 → 가짜 SO → 픽 → VOID」 우회 때문에 있다.
//     WMS 가 트랜스퍼를 직접 픽하면 다리도 사라진다
// SKU 축: 원장 라인 sku = Cin7 원문(inv-collect 는 정규화하지 않는다) ↔ wms_order_lines 는
//   base_sku. 트랜스퍼는 재고(bin) 이동이고 bin 은 base_sku 기준(불변식)이라 실무상 같다
//   ([실측] 112/112). UOM SKU 가 오면 못 맞춰 비워둔다 — 안전 방향.
// ⚠️ 적용 범위: transfer_out · warehouse ≠ IN_TRANSIT · **헤더에서 bin 을 못 얻은 라인만**.
//   헤더에 bin 이 있으면(내부 bin 이동 — 이미 잘 된다 · 335행 실측) 종전 그대로.
//   도착 다리(4)·IN_TRANSIT 다리(2·3)는 무접촉.
// ⚠️ 과거 행은 안 고친다 — 보정은 scripts/fix-transfer-bins.mjs(같은 함수를 원문 추출해 쓴다).
// ⚠️ 조회 실패는 수집을 막지 않는다 — 해결만 끄고(전부 bin='') 경고(호출부 try/catch).
function parseTransferRefSOs(reference: unknown): string[] {
  // "P2_(SO-15482-7,9,10,11,12 / SO-15834-1,2,3)" → ["SO-15482","SO-15834"] (파트 번호 무시 · 중복 제거)
  return [...new Set(String(reference ?? "").match(/SO-\d+/g) ?? [])];
}
type TransferBinLine = { base_sku: unknown; bin_location: unknown };
type TransferBinBuild = { map: Map<string, string>; conflicts: string[] };
function buildTransferBinMap(lines: TransferBinLine[]): TransferBinBuild {
  // base_sku → bin_location. ⚠️ 여러 SO 에서 같은 SKU 의 bin 이 갈리면 그 SKU 는 뺀다
  //   (하나로 정할 근거가 없다 — 비워두고 conflict 로 보고). bin_location 빈 값도 뺀다.
  const map = new Map<string, string>();
  const conflicted = new Set<string>();
  for (const l of lines) {
    const sku = String(l?.base_sku ?? "").trim();
    const bin = String(l?.bin_location ?? "").trim();
    if (!sku || !bin) continue;
    const cur = map.get(sku);
    if (cur === undefined) map.set(sku, bin);
    else if (cur !== bin) conflicted.add(sku);
  }
  for (const sku of conflicted) map.delete(sku);
  return { map, conflicts: [...conflicted].sort() };
}
function resolveTransferBin(map: Map<string, string> | null, sku: string): string {
  // 판정 불가(맵 없음·미등재)는 전부 "" = 비워둔다 — 틀린 bin 보다 낫다
  if (!map || !sku) return "";
  return map.get(sku) ?? "";
}
type TransferBinLookup = { map: Map<string, string> | null; sos: string[]; soMissing: string[]; conflicts: string[]; truncated: boolean };
// sbGetFn 주입 — 테스트(test-invcollect-transferbin.mjs)와 보정 도구(fix-transfer-bins.mjs)가
// 같은 함수를 원문 추출해 쓴다(로직 두 벌 금지).
async function loadTransferBinMap(reference: unknown, sbGetFn: (path: string) => Promise<any[]>): Promise<TransferBinLookup> {
  const sos = parseTransferRefSOs(reference);
  if (!sos.length) return { map: null, sos, soMissing: [], conflicts: [], truncated: false };
  const orders = await sbGetFn("wms_orders?select=id,order_number&order_number=in.(" +
    encodeURIComponent(sos.map((v) => '"' + v + '"').join(",")) + ")");
  const found = new Set(orders.map((o: any) => String(o.order_number)));
  const soMissing = sos.filter((so) => !found.has(so));
  if (!orders.length) return { map: null, sos, soMissing, conflicts: [], truncated: false };
  const ids = orders.map((o: any) => String(o.id)).join(",");
  const lines = await sbGetFn("wms_order_lines?select=base_sku,bin_location&order_id=in.(" + ids + ")");   // caps-ok: 픽용 SO 라인 — 문서당 SO 1~2개 × ~110라인(실측 112). 1000행 도달 시 아래 truncated 가 해결을 끈다
  // ⚠️ PostgREST 1000행 캡 방어 — 잘린 맵으로 채우면 틀린 판정이 된다: 해결을 끈다(안전 방향)
  if (lines.length >= 1000) return { map: null, sos, soMissing, conflicts: [], truncated: true };
  const b = buildTransferBinMap(lines);
  return { map: b.map, sos, soMissing, conflicts: b.conflicts, truncated: false };
}

// ── 회차 로그 (2026-08-31 · 결함 C·D 후속 — 마이그레이션 20260831153314_inv_collect_runs) ──
// 결함 C(커서 동결)·D(캡 누락) 둘 다 **EF 응답에는 신호가 있었다**(cursor_after_would_be ==
//   cursor_before · hold_capped 120) — 그런데 응답은 수동 실행 때만 보이고, cron 은 응답을 안
//   읽으며 cron.job_run_details 는 늘 succeeded 다(결함 C 때 350회+). 각각 하루 반·사흘 늦게
//   알았고 그 지연이 데이터 유실 + 잘못된 응급조치를 낳았다. ⇒ commit 회차 결과를
//   inv_collect_runs 에 남겨 아침 점검이 SQL 한 줄이 되게 한다(inv_snapshot_runs 와 같은 틀 —
//   §4-c 급감 검사도 나중에 이 틀에 얹는다).
// ⚠️ dry 회차는 남기지 않는다 — 수동 조사가 기준선을 오염시킨다(inv_snapshot_runs 와 같은 판단).
// ⚠️ commit 이 차단된 회차(write_skipped)도 남긴다 — 차단된 회차가 남아야 원인이 보인다(ok=false).
// ⚠️ 진단은 수집을 막지 않는다 — 로그 실패는 경고 + collect_run_error 만(호출부 try/catch).
// 매핑은 R 의 기존 값 그대로 — 새로 계산하지 않는다. hold_capped 는 ②-a dispositions 에만 있다
//   (②-b 는 null). inserted ← R.written(응답 필드명이 written 이다 · blocked/미commit 이면 null).
// summary = R 전체 — 단 samples 는 제외(행이 커진다) · warnings 는 잘린 사본으로 대체(같은 이유).
function buildCollectRun(sourceKey: string, R: Record<string, unknown>, warnings: string[], durationMs: number): Record<string, unknown> {
  const num = (v: unknown) => (v == null ? null : Number(v));
  const warnCapped = warnings.slice(0, 50);   // ⚠️ 길면 앞 50개 — jsonb 행 폭주 방지
  const summary: Record<string, unknown> = {};
  for (const k of Object.keys(R)) if (k !== "samples") summary[k] = k === "warnings" ? warnCapped : R[k];
  const dispositions = (R.dispositions ?? null) as Record<string, number> | null;
  return {
    source_key: sourceKey,
    ok: R.write_skipped ? false : true,
    collector: COLLECTOR_VERSION,
    detail_capped: R.detail_capped === true,
    detail_capped_reason: R.detail_capped_reason ?? null,
    detail_capped_remaining: num(R.detail_capped_remaining) ?? 0,
    hold_capped: dispositions && dispositions["hold_capped"] != null ? Number(dispositions["hold_capped"]) : null,
    cursor_before: R.cursor_before ?? null,
    cursor_after: R.cursor_after ?? R.cursor_after_would_be ?? null,
    cursor_stalled_alert: R.cursor_stalled_alert ?? null,
    cursor_frozen_alert: R.cursor_frozen_alert ?? null,
    list_total: num(R.list_total),
    list_received: num(R.list_received),
    pages: num(R.pages),
    truncated: R.truncated ?? null,
    list_aborted: R.list_aborted ?? null,
    candidates: num(R.candidates),
    docs_processed: num(R.docs_processed),
    detail_fetched: num(R.detail_fetched),
    ledger_rows: num(R.ledger_rows),
    inserted: num(R.written),
    insert_skipped: num(R.insert_skipped),
    skipped_unchanged: num(R.skipped_unchanged),
    precision_skipped: num(R.precision_skipped),
    write_skipped: R.write_skipped ?? null,
    dispositions,
    warnings: warnCapped,
    summary,
    duration_ms: durationMs,
  };
}
async function writeCollectRun(row: Record<string, unknown>): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/inv_collect_runs", {
    method: "POST",
    headers: sbHeaders({ Prefer: "return=minimal" }),
    body: JSON.stringify([row]),
  });
  if (!r.ok) throw new Error("sbInsert inv_collect_runs " + r.status + ": " + (await r.text()).slice(0, 400));
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

// ── ②-b 커서 tie-breaker (2026-08-30 결함 C) ──
// [실사고] 밀리초까지 같은 Updated(2026-08-28T15:25:33.383Z)의 판매 238건(History 에 해당 시각
//   활동 없음 = Cin7 플랫폼 일괄 갱신 — 예고 없음·주기 미상·재발 전제)이 캡(40건/120초)보다
//   커서, 캡 회차 커서(=마지막 처리 문서의 Updated)가 동률 그룹 안에서 영원히 제자리 →
//   판매 수집이 하루 반 동결(cron 잡 7 은 350회+ 전부 succeeded — ⑥ 대조 unknown 861 이
//   하루 뒤에야 잡았다). 결함 A(후보 안 줄음)·B(Updated null) 가드는 「시각이 없다」만 봐서
//   「시각이 있는데 다 같다」(C)에 안 걸렸다 — 그래서 증상 가드(decideCursor)도 함께 둔다.
// 커서 형식: <Updated>|<문서식별자> (예 2026-08-28T15:25:33.383Z|SO-14030)
//   · Updated 는 항상 24자 ISO → 문자열 비교가 그대로 성립. 기존 맨 ISO 커서는 "그 시각 동률
//     그룹 맨 앞"으로 해석된다 — 동률 문서를 건너뛰지 않고 **재처리**한다(유니크 키가 흡수 —
//     안전 방향). ⚠️ 마이그레이션·일회성 변환 불필요 — 그대로 둔다.
//   · '|' 근거: [실측 2026-08-30] inv_ledger.doc_number 중 '|' 포함 0건 · ASCII 124 라
//     숫자·대문자보다 크다.
//   · updated_since_requested 는 커서 앞 10자를 잘라 쓴다 — '|' 가 붙어도 앞 10자는 날짜라 무변.
//   · ②-a(문서번호 커서)는 무접촉 — 동률 문제가 없다.
type CursorCand = { updated: string | null };
function cursorDocIdent(row: any): string {
  // 목록 행의 OrderNumber → 없으면 ID(SaleID/ID) 폴백 → 둘 다 없으면 "" (그 문서는 실질
  // tie-breaker 없이 동작 — 키 "<Updated>|" 는 그 시각 동률 그룹의 맨 앞에 선다 = 유실 방지)
  return String(row?.OrderNumber ?? "").trim() || String(row?.SaleID ?? row?.ID ?? "").trim();
}
function cursorKeyOf(updated: string | null, ident: string): string | null {
  // updated 없으면 key 도 null — 정렬 맨 앞·정밀도 필터 미적용(종전 동작 유지 = 유실 방지)
  return updated ? updated + "|" + ident : null;
}
function cursorKeyCompare(a: string | null, b: string | null): number {
  // ⚠️ 코드유닛 비교 — 정밀도 필터·커서 저장이 쓰는 < 와 같은 순서여야 한다
  //   (localeCompare 는 '|' 같은 문장부호 취급이 로케일·ICU 에 좌우된다). null(=Updated 없음)은 맨 앞.
  const ka = a ?? "", kb = b ?? "";
  return ka < kb ? -1 : ka > kb ? 1 : 0;
}
function countUpdatedTies(cands: CursorCand[]): number {
  // 이번 회차 후보 중 Updated 가 중복된 문서 수 — 동률 그룹의 존재를 평소에도 보이게(조기 신호)
  const freq = new Map<string, number>();
  for (const cd of cands) if (cd.updated) freq.set(cd.updated, (freq.get(cd.updated) ?? 0) + 1);
  let n = 0;
  for (const cd of cands) if (cd.updated && (freq.get(cd.updated) ?? 0) > 1) n++;
  return n;
}
// 커서 결정 + 동결 가드 — A·B·C 전부 「캡에 걸렸는데 커서가 안 나갔다」로 나타났다:
// 원인별 가드는 사촌을 놓치므로 **증상을 직접 본다**. stalled 면 commit 차단(호출부 5).
function decideCursor(detailCapped: boolean, lastProcessedKey: string | null, cursorBefore: string | null, runStartIso: string) {
  // 비캡 회차 = 회차 시작 시각(맨 ISO — 모든 이전 키보다 크므로 다음 회차의 키 비교가 정상 동작)
  const cursorWouldBe = detailCapped ? (lastProcessedKey ?? cursorBefore) : runStartIso;
  const cursorStalled = detailCapped && String(cursorWouldBe ?? "") <= String(cursorBefore ?? "");
  return { cursorWouldBe, cursorStalled };
}

// ── 공유 sink (2026-08-17 ②-b 에서 ②-a runSource 로부터 기계적 추출 — 동작 동일) ──
// 빈 sku 가드 · 문서 내 합산 · since 필터 · seq_hint 재판정을 문서번호 커서(runSource)와
// 날짜 커서(runDateSource)가 함께 쓴다 — 게이트 로직이 두 벌이면 다음 수정 때 갈라진다.
// ⚠️ 회귀 확인: ②-a dry 3종을 추출 전과 같은 파라미터로 재실행해 ledger_rows·samples·
//   date_histogram·cursor_after_would_be 동일성 대조(커밋 메시지에 절차 기재).
function makeSink(since: string | null, nonStockSkus?: Set<string>) {
  const rows: LedgerRow[] = [];
  const dateHist: Record<string, number> = {};
  const stats = { merged_lines: 0, empty_sku_lines: 0, since_filtered_rows: 0,
                  non_inventory_skipped: 0, non_inventory_sample: [] as { sku: string; doc: string }[] };
  // 문서 하나의 행들을 유니크 키로 합산해 push — merged_lines 는 line_ref 가정 붕괴 신호
  function push(docRows: LedgerRow[]): void {
    const byKey = new Map<string, LedgerRow>();
    for (const r of docRows) {
      // ⚠️ 빈 sku = 어느 상품인지 모르는 행 — 만들지 않는다. ≠0 이면 그 소스의 파싱이 틀렸다는
      //   뜻이라 나머지 행도 못 믿는다 → commit 게이트가 소스 전체를 막는다(UNMAPPED 와 같은 논리.
      //   실사고: 조립 PickLines 에 SKU 필드가 없어(정답은 ProductCode) sku 가 전부 "" 였는데
      //   나머지 필드는 멀쩡해 보였다 — 조용히 통과할 뻔했다).
      if (!r.sku) { stats.empty_sku_lines++; continue; }
      // 비재고 SKU 게이트 (2026-08-24 · FINAL-SALE) — Type≠Stock 은 Cin7 이 재고를 안 움직인다.
      //   makeSink 가 6소스 공통 유일 통로라 여기 한 곳이 판매·발주·조정·반품·이동·조립 전부를
      //   막는다(dry·commit 공통 — dry 응답에서도 skipped 가 보인다). 캐시가 비면 Set 이 비어
      //   자연히 무필터(fail-open — 로드부의 경고가 그 상태를 알린다).
      if (nonStockSkus && nonStockSkus.has(r.sku)) {
        stats.non_inventory_skipped++;
        if (stats.non_inventory_sample.length < 10) stats.non_inventory_sample.push({ sku: r.sku, doc: r.doc_number });
        continue;
      }
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
    // 전수 재확인 (2026-08-31 결함 D — docStateSkip 절): 그 회차만 문서 상태 skip 판정 OFF.
    // 기록(inv_doc_state 갱신)과 커서는 평소대로 — 캡 때문에 한 회차로 못 끝나 여러 회차 분할 전제.
    // ⚠️ cron 으로 돌리지 않는다(2026-08-31 결정 — pickRollingRecheck 절): 캡 40 + 커서 고정 탓에
    //   매번 커서 위 첫 40건만 반복해 커버리지가 안 나온다. 상시 검산은 롤링 재확인이 한다 —
    //   recheck 는 특정 구간을 강제로 다시 볼 때의 수동 조사 도구로 유지.
    const recheck = url.searchParams.get("recheck") === "1";

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

    // ── 비재고 SKU 게이트 로드 (2026-08-24 · FINAL-SALE 실사고 — 마이그레이션 20260824140345) ──
    // Type≠Stock 품목(Non-inventory·Service)은 팔려도 Cin7 이 재고를 안 움직인다 — 재고 사건이
    // 아니므로 원장에서 거른다. 목록은 inv_sku_types 캐시(별도 EF inv-sku-types 가 일 1회 갱신 —
    // 갱신 실패가 수집과 격리되도록 분리, 사용자 결정).
    // ⚠️ fail-open: 캐시가 비었거나 못 읽으면 **필터 없이 통과 + 경고** — 원장은 shadow 이고
    //   대조가 안전망이다(잘못 들어와도 unknown 으로 잡힌다 — FINAL-SALE 이 정확히 그 경로).
    //   차단이 수집을 멈추면 정상 재고까지 멈춘다. 조용한 폴백 금지 — global_warnings 에 실린다.
    let nonStockSkus = new Set<string>();
    const skuTypeWarnings: string[] = [];
    try {
      // ⚠️ 저장 범위 계약(마이그레이션 20260824140345 주석): 이 테이블엔 비-Stock 품목만 들어간다
      //   (EF inv-sku-types 가 Type!=='Stock' 만 upsert · [실측 2026-08-24] 49행) — 구조적 유계.
      //   Stock(1.4만+)을 넣으면 1,000행 캡에서 조용히 잘리고 잘린 비재고 SKU 가 게이트를 통과한다
      //   → 아래 800행 근접 경보가 캡 도달 **전에** 알린다(사후 감지는 이미 뚫린 뒤라 늦다).
      const st = await sbGet("inv_sku_types?select=sku,refreshed_at");   // caps-ok: 비-Stock 품목만 저장하는 계약 테이블(위 주석 · 49행) — 800행 근접 경보가 계약 붕괴를 선제 감지
      if (!st.length) skuTypeWarnings.push("inv_sku_types cache EMPTY - non-inventory gate INACTIVE (run inv-sku-types EF)");
      else {
        nonStockSkus = new Set(st.map((r: any) => String(r.sku)));
        if (st.length >= 800) {
          skuTypeWarnings.push("inv_sku_types has " + st.length + " rows - approaching the 1,000-row PostgREST cap. The table must hold ONLY non-Stock SKUs (contract in migration 20260824140345); if that changed, paginate this read BEFORE rows are silently dropped");
        }
        const newest = st.map((r: any) => String(r.refreshed_at ?? "")).sort().pop() ?? "";
        if (newest && Date.parse(newest) < Date.now() - 48 * 3600_000) {
          skuTypeWarnings.push("inv_sku_types cache STALE (refreshed " + newest + ") - gate still active with old list");
        }
      }
    } catch (e) {
      skuTypeWarnings.push("inv_sku_types cache UNREADABLE - non-inventory gate INACTIVE: " + String(e).slice(0, 120));
    }

    const global = {
      mode: commit ? "commit" : "dry",
      since,
      recheck: recheck || undefined,   // 전수 재확인 회차 — 문서 상태 skip 판정 OFF(기록·커서는 평소대로)
      collector_version: COLLECTOR_VERSION,
      location_map: { total: locTotal, received: locReceived, pages: locPages },
      // 비재고 게이트 상태 (2026-08-24) — 캐시 행 수 + 경고(비었음/낡음/못읽음 — 조용한 폴백 금지)
      non_stock_gate: { skus: nonStockSkus.size, warnings: skuTypeWarnings },
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

      // ── 문서 상태 skip 준비 (2026-08-31 결함 D — 파일 상단 docStateSkip 절) ──
      let docState: Map<string, DocStateRec> | null = null;
      let docStateError: string | null = null;
      let skippedUnchanged = 0;
      const docStateRows: DocStateRow[] = [];
      // ②-a 목록의 갱신 필드 = LastModifiedOn ([실측 2026-08-31] transfer 1000/1000 · 빈 값 0 ·
      // 동률 0. adjustment·assembly 는 미실측 — 값이 있으면 쓰고 없으면 판정 불가 = 늘 조회,
      // missingDocs 의 lmo 폴백과 같은 자세). ⚠️ 문자열 그대로 — 파싱 금지(축마다 형식이 다르다).
      const listLmOf = (row: any) => String(row?.LastModifiedOn ?? "").trim() || null;
      try {
        docState = await loadDocState(key, cands.filter((c) => c.disposition.startsWith("process")).map((c) => c.number));
      } catch (e: any) {
        // ⚠️ 진단·최적화는 수집을 막지 않는다 — 판정을 끄고(전량 조회) 경고만.
        docState = null;
        docStateError = String(e?.message ?? e).slice(0, 200);
        warnings.push("doc-state read failed - skip judging disabled, fetching all details: " + docStateError);
      }

      // ── 롤링 재확인 대상 선정 (2026-08-31 — 파일 상단 pickRollingRecheck 절) ──
      // ②-a 는 매 회차 목록 전량을 받으므로 ⭐ 완전 커버리지 — 롤링 재확인의 실질적 대상.
      // ⚠️ 비종결(process_nonterminal)은 원래 skip 대상이 아니라 선정과 무관하다(늘 조회).
      let rollingSet = new Set<string>();
      let rollingOldestSeen: string | null = null;
      let rollingRechecked = 0;
      const rollingSample: string[] = [];
      try {
        if (docState && !recheck) {   // recheck 회차는 전량 조회라 롤링이 무의미
          const eligible: RollingEligible[] = [];
          for (const c of cands) {
            if (c.disposition !== "process") continue;
            if (!docStateSkip(true, false, docState, c.number, listLmOf(c.row))) continue;
            eligible.push({ docNumber: c.number, seenAt: docState.get(c.number)!.seenAt });
          }
          const picked = pickRollingRecheck(eligible, ROLLING_RECHECK_PER_RUN);
          rollingSet = picked.set;
          rollingOldestSeen = picked.oldestSeen;   // ⭐ 커버리지 지표 — 2.6시간 이상 벌어지면 회전이 밀린 것
        }
      } catch (e: any) {
        // ⚠️ 진단이 수집을 막지 않는다 — 선정 실패는 롤링만 끄고(평소대로 skip) 경고만.
        rollingSet = new Set();
        warnings.push("rolling-recheck selection failed - disabled this round (docs skip as usual): " + String(e?.message ?? e).slice(0, 200));
      }

      // 3) 상세 조회 (오름차순 · 캡 · 시간 가드) → 원장 행 생성
      const sink = makeSink(since, nonStockSkus);   // 공유 sink — 파일 상단 makeSink(②-b 에서 추출) + 비재고 게이트
      const dateCandidates: { doc_number: string; list_date: string | null; completion_date: string | null; wip_date: string | null }[] = [];
      let detailFetched = 0, docsProcessed = 0, zeroQtyLines = 0, missingDateDocs = 0;
      const dateSubstitutedDocs: string[] = [];     // 빈 이동 날짜 대체 문서 (아래 transfer 분기)
      // 트랜스퍼 출발 bin 해결 카운터 (transfer 전용 — 파일 상단 loadTransferBinMap 절)
      let tbResolved = 0, tbUnresolved = 0;
      const tbNoReference: string[] = [], tbSoMissing: string[] = [], tbConflict: string[] = [];
      const tbPush = (arr: string[], v: string) => { if (v && !arr.includes(v) && arr.length < 10) arr.push(v); };
      let detailCapped = false, detailCapReason: string | null = null;
      let unmappedInSource = 0;
      // 라인 소멸 감지 — A 집합 축적 (파일 상단 detectMissingLines 절)
      const missingDocs: MissingDocCheck[] = [];
      let missingSkippedNoLmo = 0;

      for (const c of cands) {
        if (!c.disposition.startsWith("process")) continue;
        // 변경 없는 종결 문서는 상세를 부르지 않는다 (결함 D) — ⚠️ 종결(process)만.
        // process_nonterminal 은 절대 skip 하지 않는다: 도착(3·4행)을 만들려면 재방문이 필수인데,
        // 도착이 목록 값을 안 바꾸는 경우가 미확인이라 skip 하면 도착 다리를 영영 못 받는다.
        // skip 문서는 missingDocs(A 집합)에도 안 들어간다(상세가 없으니 판정 불가 — G1 동형).
        // 캡 검사보다 앞 — skip 은 호출 예산을 안 쓰므로 캡 도달 뒤에도 판정된다(집계 정확).
        if (docStateSkip(c.disposition === "process", recheck, docState, c.number, listLmOf(c.row))) {
          if (rollingSet.has(c.number)) {
            // 롤링 재확인 — skip 예정이지만 seen_at 최고령이라 강제 재조회(아래로 계속 → 상세).
            // skip_unchanged 로 세지 않는다(실제로 조회한다). 캡에 걸리면 hold_capped 로 넘어가고
            // seen_at 이 안 갱신되니 다음 회차에 다시 후보가 된다(그대로 둔다).
            rollingRechecked++;
            if (rollingSample.length < 5) rollingSample.push(c.number);
          } else {
            c.disposition = "skip_unchanged";
            skippedUnchanged++;
            continue;
          }
        }
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
          // ── 출발 bin 해결 (2026-08-31 — 파일 상단 loadTransferBinMap 절) ──
          // ⚠️ 헤더에서 bin 을 얻은 문서(fromLoc.bin ≠ "" — 내부 bin 이동)는 WMS 를 조회하지
          //   않는다(종전 그대로). 못 얻은 문서만 Reference 의 픽용 SO 로 WMS 픽 bin 을 찾는다.
          let transferBinMap: Map<string, string> | null = null;
          if (fromLoc.mapped && fromLoc.bin === "" && ((det?.Lines ?? []) as any[]).length) {
            try {
              const tb = await loadTransferBinMap(det?.Reference ?? c.row?.Reference, sbGet);
              if (!tb.sos.length) tbPush(tbNoReference, c.number);
              for (const so of tb.soMissing) tbPush(tbSoMissing, so);
              for (const sk of tb.conflicts) tbPush(tbConflict, sk);
              if (tb.truncated) {
                warnings.push("transfer-bin: wms_order_lines hit the 1000-row cap on " + c.number + " - resolution disabled for this doc (bins left empty)");
              } else if (tb.map && tb.map.size) {
                transferBinMap = tb.map;
                header.transfer_bin_source = "wms_order_lines via Reference " + tb.sos.join(",");   // 근거를 raw 에 남긴다
              }
            } catch (e: any) {
              // ⚠️ 진단·보강은 수집을 막지 않는다 — 해결만 끄고(전부 bin='') 경고만.
              transferBinMap = null;
              warnings.push("transfer-bin lookup failed (collection unaffected, bins left empty): " + String(e?.message ?? e).slice(0, 200));
            }
          }
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
            // 출발 bin: 헤더 값 우선 · 없으면 WMS 픽 bin (틀린 bin 을 채우느니 비워둔다 — 위 절)
            let depBin = fromLoc.bin;
            let binFromWms = false;
            if (depBin === "" && fromLoc.mapped) {
              depBin = resolveTransferBin(transferBinMap, sku);
              if (depBin) { tbResolved++; binFromWms = true; } else tbUnresolved++;
            }
            rows.push(mk("transfer_out", fromLoc.warehouse, depBin, -q, dep, "1 from-warehouse departure" + (binFromWms ? " - bin from WMS pick (Reference SO)" : "")));
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
        // 라인 소멸 감지 A 집합 — G1: push 도달 = 상세 실조회 + 문서 전체 파싱 성공(②-a 는 문서
        // 단위 hold 라 부분 스킵이 없다). ⚠️ rows=∅ 도 축적한다 — "모든 라인이 삭제된 문서"가
        // 정확히 실사고의 모양이다(TR-04175 는 부분이었지만 전량 삭제도 같은 경로).
        // ⚠️ A 는 sink 필터 전 rows — since·비재고로 걸러진 라인도 Cin7 에 실재하므로 A 에 포함.
        {
          const lmoRaw = String(det?.LastModifiedOn ?? c.row?.LastModifiedOn ?? "").trim();   // [실측 2026-08-25] stockTransferList 에 존재 — adjustment·assembly 는 값이 있으면 쓰고 없으면 G4
          if (!lmoRaw) missingSkippedNoLmo++;
          else missingDocs.push({
            docNumber: c.number, lmo: lmoRaw,
            docStatus: String(det?.Status ?? c.row?.Status ?? "").trim() || null,
            keys: new Set(rows.map(ledgerKeyOf)),
          });
        }
        // 문서 상태 기록 대상 (결함 D) — 종결(process) 문서만(비종결은 판정 대상이 아니라 기록도
        // 안 한다). 값은 **목록 행**의 것 — 다음 회차 skip 판정이 목록 값과 비교하므로 축을
        // 맞춘다(상세 값과 어긋나면 다음 회차에 한 번 더 읽을 뿐 — 안전 방향). 쓰기는 commit 블록.
        if (c.disposition === "process") {
          const lm = listLmOf(c.row);
          if (lm) docStateRows.push({ source_key: key, doc_number: c.number, last_modified: lm,
            doc_status: String(det?.Status ?? c.row?.Status ?? "").trim() || null, collector: COLLECTOR_VERSION });
        }
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
        if (d === "processed" || d === "skip_voided" || d === "skip_since" || d === "skip_unchanged") { cursorAfter = c.number; continue; }   // skip_unchanged 도 처리한 것으로 취급 — 커서가 정상 전진해야 한다(결함 D)
        cursorHeldBy = { doc_number: c.number, reason: d };
        break;
      }
      // 건너뜀·보류 내역 집계 (응답용 — "건너뛴 문서 수"를 사유별로)
      const dispositions: Record<string, number> = {};
      for (const c of cands) dispositions[c.disposition || "(untouched)"] = (dispositions[c.disposition || "(untouched)"] ?? 0) + 1;

      // 5) 샘플 5행 (전체 필드 — 숫자만 맞고 내용이 틀릴 수 있다: 눈으로 확인)
      const samples = sink.rows.slice(0, 5);

      // 라인 소멸 감지 — G3: 회차가 중단되면 집합이 불완전하다 → 소스 전체 skip.
      // 검출(계산)은 dry 에서도 돈다(보고용) — 쓰기는 commit 블록의 write 성공 경로에서만.
      let missingCheckSkipped: string | null = null;
      if (listAborted) missingCheckSkipped = "list_aborted: " + listAborted;
      else if (truncated) missingCheckSkipped = "list_truncated";
      else if (detailCapped) missingCheckSkipped = "detail_capped: " + detailCapReason;
      let missing: Awaited<ReturnType<typeof detectMissingLines>> | null = null;
      // ⚠️ 진단은 수집을 막지 않는다 — 검출 실패는 경고, 수집·커서는 정상 진행.
      //   (감싸지 않으면 REST 순단 한 번에 이 소스 회차 전체가 abort — 원장 쓰기·커서 전진이
      //    통째로 멈추는데 cron.job_run_details 는 succeeded = 조용한 정지)
      if (!missingCheckSkipped) {
        try {
          missing = await detectMissingLines(cfg.docType, missingDocs, warnings);
        } catch (e: any) {
          missing = null;
          missingCheckSkipped = "detect_failed: " + String(e?.message ?? e).slice(0, 200);
          warnings.push("missing-line detection failed (collection unaffected): " + missingCheckSkipped);
        }
      }

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
        // 문서 상태 skip (2026-08-31 결함 D) — skipped_unchanged 가 쌓이고 detail_capped 가
        // false 로 내려가는 것이 정상 궤적(1회차는 기록이 없어 0).
        skipped_unchanged: skippedUnchanged,
        doc_state_known: docState ? docState.size : 0,
        doc_state_error: docStateError ?? undefined,   // 있으면 이번 회차는 전량 조회로 동작했다
        // 롤링 재확인 (2026-08-31 — pickRollingRecheck 절)
        rolling_rechecked: rollingRechecked,
        rolling_recheck_sample: rollingSample,
        doc_state_oldest_seen: rollingOldestSeen ?? undefined,   // ⭐ 커버리지 지표 — 회전이 얼마나 뒤처졌는지
        ledger_rows: sink.rows.length,
        zero_qty_lines: zeroQtyLines,
        since_filtered_rows: sink.stats.since_filtered_rows,
        non_inventory_skipped: sink.stats.non_inventory_skipped,
        non_inventory_sample: sink.stats.non_inventory_sample,
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
        // 라인 소멸 감지 (2026-08-25 · TR-04175) — inserted 는 commit 블록에서 채운다
        missing_lines_detected: missing ? missing.detected : 0,
        missing_lines_bin_changed: missing ? missing.binChanged : 0,   // bin 만 바뀐 행 — 소멸 아님(키 규칙 변경의 흔적)
        missing_lines_inserted: 0,
        missing_lines_sample: missing ? missing.sample : [],
        missing_lines_capped: missing ? missing.capped : false,
        missing_lines_skipped_no_lmo: missingSkippedNoLmo,
        missing_check_skipped_reason: missingCheckSkipped ?? undefined,
        samples,
        warnings,
      });
      if (missing && missing.detected > 0) warnings.push(missing.detected + " ledger line(s) NO LONGER in the Cin7 doc (deleted lines?) - see inv_missing_lines; ledger rows kept (append-only), human review needed");
      if (sink.stats.empty_sku_lines > 0) warnings.push(sink.stats.empty_sku_lines + " line(s) dropped for empty sku - parsing is wrong for this source");
      if (key === "assembly") R.date_candidates = dateCandidates;   // Date/CompletionDate/WIPDate 비교표 — Caleb 이 확정
      if (key === "transfer") {
        // 출발 bin 해결 (2026-08-31 — loadTransferBinMap 절). unresolved > 0 이면 Reference
        // 누락·SO 미존재·SKU 불일치 중 하나 — 아래 목록이 어느 쪽인지 말한다.
        Object.assign(R, {
          transfer_bin_resolved: tbResolved,
          transfer_bin_unresolved: tbUnresolved,
          transfer_bin_no_reference: tbNoReference,
          transfer_bin_so_missing: tbSoMissing,
          transfer_bin_conflict: tbConflict,
        });
        if (tbUnresolved > 0) warnings.push(tbUnresolved + " transfer_out line(s) left with empty departure bin - fill Reference in Cin7 and run scripts/fix-transfer-bins.mjs");
      }

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
          const w = await writeLedgerDetectingConflicts(sink.rows, key);
          await sbUpsert("inv_sync_state", "source_key", [{
            source_key: key,
            last_cursor: cursorAfter,               // ⚠️ 문서번호 문자열 그대로 — 사람이 읽는 값
            last_run_at: new Date().toISOString(),
            last_ok_at: new Date().toISOString(),
            note: COLLECTOR_VERSION + " rows=" + sink.rows.length + " inserted=" + w.inserted + (detailCapped ? " capped" : ""),
          }]);
          // 문서 상태 기록 (결함 D) — 원장 쓰기 성공 뒤에만(dry 는 안 쓴다).
          // ⚠️ 진단·최적화는 수집을 막지 않는다 — 실패는 경고만(다음 회차가 그 문서를 다시 읽는다).
          if (docStateRows.length) {
            try {
              const seenAt = new Date().toISOString();
              await sbUpsert("inv_doc_state", "source_key,doc_number", docStateRows.map((r) => ({ ...r, seen_at: seenAt })));
            } catch (e: any) {
              warnings.push("doc-state upsert failed (collection unaffected): " + String(e?.message ?? e).slice(0, 200));
            }
          }
          R.written = w.inserted;                    // ⚠️ 2026-08-19 의미 변경: 시도 행수 → 실삽입 행수(재수집 중복 제외)
          R.insert_skipped = w.insert_skipped;       // 버려진 행 수 — 0 아님이 정상(재수집 포함)
          R.conflicts_detected = w.conflicts_detected;
          R.conflicts_sample = w.conflicts_sample;
          // 라인 소멸 기록 — 원장 쓰기 성공 뒤에만(dry 는 위에서 검출·보고만). 같은 편집의
          // 재검출은 유니크 키(7종+last_modified_on) + ignore-duplicates 가 do-nothing 으로 흡수.
          // ⚠️ 진단은 수집을 막지 않는다 — 원장 쓰기는 이미 성공했으므로 기록 실패가
          //   응답을 500 으로 만들면 안 된다. 실패 시 inserted 0 + 경고(다음 회차가 재검출).
          if (missing && missing.rows.length) {
            try {
              R.missing_lines_inserted = await insertMissingLines(missing.rows);
            } catch (e: any) {
              warnings.push("missing-line insert failed (collection unaffected, will re-detect next round): " + String(e?.message ?? e).slice(0, 200));
            }
          }
        }
      }
      // 회차 로그 (2026-08-31 · inv_collect_runs — dry 미기록 · 차단 회차도 기록 · 실패는 경고만)
      if (commit) {
        try {
          await writeCollectRun(buildCollectRun(key, R, warnings, Date.now() - t0));
          R.collect_run_logged = true;
        } catch (e: any) {
          R.collect_run_logged = false;
          R.collect_run_error = String(e?.message ?? e).slice(0, 200);
          warnings.push("collect-run log failed (collection unaffected): " + R.collect_run_error);
        }
      } else R.collect_run_logged = false;
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
      const sink = makeSink(since, nonStockSkus);

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
      const srsCounts: Record<string, number> = {};   // purchase: 목록 StockReceivedStatus 분포 — 관측 전용(2026-08-18 부터 거르지 않는다)
      const crsCounts: Record<string, number> = {};   // purchase: 목록 CombinedReceivingStatus 분포 — 관측 전용(신규)
      const listRestockStatusCounts: Record<string, number> = {};   // creditnote: 목록 RestockStatus 분포(세기만 — 거르지 않음)
      const cands: { row: any; updated: string | null; key: string | null }[] = [];
      for (const row of listRows) {
        if (key === "sale") {
          if (norm(row?.Status) === "VOIDED") { tally("skip_voided"); continue; }
          // ⚠️ 배송 전에는 재고가 안 빠진다 — 픽·팩은 Allocated 일 뿐 (원장 스킬 함정 표)
          if (norm(row?.CombinedShippingStatus) !== "SHIPPED") { tally("skip_not_shipped"); continue; }
        } else if (key === "purchase") {
          if (norm(row?.Status).includes("VOID")) { tally("skip_voided"); continue; }
          if (row?.IsServiceOnly === true) { tally("skip_service_only"); continue; }
          // ⚠️ 목록 StockReceivedStatus 게이트 제거 (2026-08-18) — 반품(.7)의 목록 RestockStatus
          //   필터 제거와 같은 계열: **상태 판정 권한은 상세 한 곳에만 둔다.** 목록 값과 상세 블록
          //   값은 양방향으로 어긋난다 = 상관이 없다([실측] 표본 6건 중 Advanced 4건 —
          //   PO-00848·00931·01048·01065, 12,552u — 전부 실재 입고인데 이 게이트가 문서째 지웠다).
          //   여기서는 분포만 센다(관측 전용 — 절대 거르지 않는다). 후보가 늘어 상세 호출이 느는
          //   것은 의도된 결과([실측] 241건 창에서 약 104 → 124).
          const srs = norm(row?.StockReceivedStatus);
          srsCounts[srs || "(empty)"] = (srsCounts[srs || "(empty)"] ?? 0) + 1;
          const crs = norm(row?.CombinedReceivingStatus);
          crsCounts[crs || "(empty)"] = (crsCounts[crs || "(empty)"] ?? 0) + 1;
        } else {   // creditnote
          const cst = norm(row?.CreditNoteStatus);
          // 문서 자체의 유효성 필터는 유지 (VOIDED/NOT AVAILABLE — 실측 477건 탈락, 옳은 탈락)
          if (cst === "VOIDED" || cst === "NOT AVAILABLE") { tally("skip_cn_status"); continue; }
          // ⚠️ 목록 단계 RestockStatus 필터 제거 (2026-08-17 .7): 목록 행은 sale 단위인데 한 sale 에
          //   CN 이 여럿이다([실측 dry] 상세 40건에서 credit_notes_seen 51). 단일값으로 오더를 통째로
          //   거르면 같은 오더 안의 AUTHORISED CN 이 함께 탈락해 조용히 유실된다 — 발주 게이트웨이
          //   사고("Status 문자열 필터가 PO 를 목록에서 지워버림")와 같은 계열. 상태 판정 권한은
          //   상세의 CreditNotes[] 순회 한 곳에만 둔다 — 여기서는 세기만 한다.
          //   후보 60→약 124 로 늘어 상세 호출이 배가 되는 것은 의도된 결과(캡 이어받기가 여러 회차).
          const rst = norm(row?.RestockStatus);
          listRestockStatusCounts[rst || "(empty)"] = (listRestockStatusCounts[rst || "(empty)"] ?? 0) + 1;
        }
        const updated = String(row?.[cfg.updatedField] ?? "").trim() || null;
        cands.push({ row, updated, key: cursorKeyOf(updated, cursorDocIdent(row)) });
      }
      // ⚠️ 키(<Updated>|<식별자>) 오름차순 — 캡 회차의 커서를 "마지막 처리 문서의 키" 로 멈추기
      //   위한 전제(파일 상단 캡 보정·tie-breaker 절). Updated 없는 행(key=null)은 종전대로
      //   맨 앞(먼저 처리 — 유실 방지) + 카운트.
      let noUpdatedField = 0;
      for (const cd of cands) if (!cd.updated) noUpdatedField++;
      cands.sort((a, b) => cursorKeyCompare(a.key, b.key));

      // ⚠️ 결함 A 차단 (2026-08-17 .6): 커서는 전체 정밀도 시각(캡 회차 = 마지막 처리 문서의
      //   Updated)인데 UpdatedSince 요청은 날짜(10자)로 잘라 −1일 — 요청 형태는 의도된 설계라
      //   그대로 두고(겹침 수신), **거르기를 우리 쪽에서 전체 정밀도로** 한다. 안 거르면 캡 회차
      //   다음 회차의 후보 집합이 직전과 동일해 같은 앞 40건만 반복 처리 — 41번째 이후가 영영
      //   안 들어온다(이미 원장에 있는 40건은 유니크 키가 흡수해 삽입 0행·ok:true·커서 동일값
      //   갱신 = 완전히 조용한 정체. ⚠️ dry 는 커서를 안 쓰므로 dry 로는 재현 불가 — 실측 전 수정).
      //   · cursorBefore 가 날짜(10자)보다 정밀할 때만 적용 — 날짜 하한(from_since 시드)은 현행 유지
      //   · < 만 제외, **같은 값(=)은 남긴다** — 경계에서 키가 동일한 문서(커서 경계 문서)가
      //     잘리지 않게(재처리분은 유니크 키가 흡수). <= 로 바꾸지 말 것
      //   · (2026-08-30 결함 C) 비교 단위는 updated 가 아니라 **키(<Updated>|<식별자>)** —
      //     맨 ISO 커서(구형 state·비캡 회차의 runStartIso)는 같은 시각의 키보다 작아(짧은 쪽이
      //     작다) 동률 문서가 걸러지지 않고 재처리된다(안전 방향 — tie-breaker 절 주석)
      //   · Updated 없는 후보(key=null)는 거르지 않는다(정렬이 맨 앞에 두는 것과 같은 이유 — 유실 방지)
      //   · dedup(아래)보다 먼저 — 뒤에 오면 dedup 이 남긴 "가장 이른 CN"이 정밀도 필터에 걸려
      //     그 오더가 통째로 탈락할 수 있다(살아남을 늦은 CN 이 있는데도)
      let precisionSkipped = 0;   // ⚠️ 캡 회차 "다음" 회차에만 0 이 아닌 것이 정상이다
      if (cursorBefore && cursorBefore.length > 10) {
        const kept: typeof cands = [];
        for (const cd of cands) {
          if (cd.key && cd.key < cursorBefore) { precisionSkipped++; continue; }
          kept.push(cd);
        }
        cands.length = 0;
        cands.push(...kept);
      }

      // ⚠️ creditnote 후보는 CN 단위 — 같은 오더의 CN 여럿이 각각 후보가 된다(실측 SO-00062).
      //   상세는 sale 단위이고 기표부가 det.CreditNotes[] 를 전부 순회하므로 오더당 1회만 부른다 —
      //   안 거르면 같은 /sale?ID= 를 중복 호출하고 같은 AUTHORISED CN 이 한 회차에 두 번 push 되어
      //   보고 숫자(ledger_rows·creditNotesSeen·restockStatusCounts)가 부풀고, 상세 캡이 중복분에
      //   잠식돼 캡 회차가 실제보다 적게 처리하며 커서도 덜 전진한다(DB 는 ignore-duplicates 가
      //   흡수하지만 보고·호출 예산은 안 막힌다).
      //   ⚠️ 정렬 뒤에 거르는 것이 전제: Updated 오름차순에서 "먼저 나온 것"을 남겨야 커서가
      //   그 오더의 더 늦은 CN 갱신 시각을 앞지르지 않는다(겹침 수신으로 자연 회수).
      //   sale·purchase 는 후보가 이미 오더/발주 단위 — 적용하지 않는다.
      let dupSaleDropped = 0;              // ⚠️ 0 이 아닌 것이 정상이다 — 한 오더 여러 CN 은 실측 사실
      let saleIdPresent = 0, saleIdFallback = 0;   // SaleID 부재 시 ID 폴백 추적 (CN ID 로 /sale?ID= 를 부르면 상세 오류 — 원인 추적용)
      if (key === "creditnote") {
        const seenSale = new Set<string>();
        const deduped: typeof cands = [];
        for (const cd of cands) {
          const sid = String(cd.row?.SaleID ?? "").trim();
          const fid = String(cd.row?.ID ?? "").trim();
          if (sid) saleIdPresent++; else if (fid) saleIdFallback++;
          const k = sid || fid;
          if (!k) { deduped.push(cd); continue; }   // 판정 불가(키 빈 값)는 조용히 탈락시키지 않는다
          if (seenSale.has(k)) { dupSaleDropped++; continue; }
          seenSale.add(k);
          deduped.push(cd);
        }
        cands.length = 0;
        cands.push(...deduped);
      }

      // 동률 관측 (결함 C 조기 신호 — 응답 updated_ties): 후보 확정(필터·dedup) 후에 센다
      const updatedTies = countUpdatedTies(cands);

      // ── 문서 상태 skip 준비 (2026-08-31 결함 D — ②-a 와 같은 판정 · 파일 상단 docStateSkip 절) ──
      // ②-b 는 문서에 커서가 멈추지 않으므로(갱신되면 UpdatedSince 재등장) 후보를 종결로 취급하되,
      // 「비종결 skip 금지」 원칙은 기록 쪽에서 지킨다: docIncomplete 문서는 기록하지 않는다
      // (기록이 없으면 skip 도 없다 — 아래 기록 지점). 문서 식별자 = cursorDocIdent(OrderNumber →
      // SaleID/ID) — creditnote 는 sale 단위(원장 doc_number 는 CN 번호지만 목록·상세 조회 단위가 sale).
      let docState: Map<string, DocStateRec> | null = null;
      let docStateError: string | null = null;
      let skippedUnchanged = 0;
      const docStateRows: DocStateRow[] = [];
      try {
        docState = await loadDocState(key, cands.map((cd) => cursorDocIdent(cd.row)).filter(Boolean));
      } catch (e: any) {
        // ⚠️ 진단·최적화는 수집을 막지 않는다 — 판정을 끄고(전량 조회) 경고만.
        docState = null;
        docStateError = String(e?.message ?? e).slice(0, 200);
        warnings.push("doc-state read failed - skip judging disabled, fetching all details: " + docStateError);
      }

      // ── 롤링 재확인 대상 선정 (2026-08-31 — 파일 상단 pickRollingRecheck 절) ──
      // ⚠️ ②-b 는 최근 창만 검산한다 — UpdatedSince 로 받으므로 커서보다 오래된 문서는 애초에
      //   후보가 아니다. 📌 단 inv_doc_state 가 상황을 악화시키지는 않는다: Cin7 이 변경 시
      //   Updated 를 안 올리면 그 문서는 목록에 아예 안 나온다(inv_doc_state 이전부터 있던 위험 ·
      //   롤링으로도 못 닿는다). 같은 코드를 무해하게 적용한다 — 실질적 대상은 ②-a.
      let rollingSet = new Set<string>();
      let rollingOldestSeen: string | null = null;
      let rollingRechecked = 0;
      const rollingSample: string[] = [];
      try {
        if (docState && !recheck) {   // recheck 회차는 전량 조회라 롤링이 무의미
          const eligible: RollingEligible[] = [];
          for (const cd of cands) {
            const ident = cursorDocIdent(cd.row);
            if (!docStateSkip(true, false, docState, ident, cd.updated)) continue;
            eligible.push({ docNumber: ident, seenAt: docState.get(ident)!.seenAt });
          }
          const picked = pickRollingRecheck(eligible, ROLLING_RECHECK_PER_RUN);
          rollingSet = picked.set;
          rollingOldestSeen = picked.oldestSeen;
        }
      } catch (e: any) {
        // ⚠️ 진단이 수집을 막지 않는다 — 선정 실패는 롤링만 끄고(평소대로 skip) 경고만.
        rollingSet = new Set();
        warnings.push("rolling-recheck selection failed - disabled this round (docs skip as usual): " + String(e?.message ?? e).slice(0, 200));
      }

      // 3) 상세 → 원장 행
      let detailFetched = 0, docsProcessed = 0, zeroQtyLines = 0, missingDateItems = 0;
      let detailCapped = false, detailCapReason: string | null = null, cappedRemaining = 0;
      let unmappedInSource = 0;
      let lastProcessedKey: string | null = null;
      // 소스별 부가 카운트 (응답 명세)
      let fulfilmentsSeen = 0, noShipFulfilments = 0, shipDateAmbiguous = 0, pickLineCount = 0;
      let advancedCount = 0, simpleCount = 0;
      let advNoPutaway = 0, advNoPutawaySrLines = 0, simpleWithPutaway = 0;
      let cardIdFallback = 0, nonInventoryLines = 0, receivedFalseLines = 0;
      const paBlockStatusCounts: Record<string, number> = {};
      const srBlockStatusCounts: Record<string, number> = {};
      const blocksSkipped: Record<string, number> = {};   // "축:상태" 키 (예 "putaway:VOIDED")
      const advNoPutawaySamples: string[] = [];
      let creditNotesSeen = 0, emptyRestock = 0, noCnNumber = 0;
      const restockStatusCounts: Record<string, number> = {};
      // 라인 소멸 감지 — A 집합 (파일 상단 detectMissingLines 절)
      const missingDocs: MissingDocCheck[] = [];
      let missingSkippedNoLmo = 0;

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
        const cd = cands[i];
        const docIdent = cursorDocIdent(cd.row);
        // 변경 없는 문서는 상세를 부르지 않는다 (결함 D) — 캡 검사보다 앞(호출 예산 무소모).
        // 비교 값 = cd.updated (sale 'Updated' · purchase 'LastUpdatedDate' — 목록 실측 필드 ·
        // [실측 2026-08-31] 빈 값 0건). 기록은 docIncomplete 문서를 제외하므로(아래) 여기 걸리는
        // 문서는 전부 「부분 스킵 없이 전량 기표된」 것 — 종결 취급이 안전하다.
        // ⚠️ skip 도 커서 전진에 포함(lastProcessedKey) — 처리한 것으로 취급해야 커서가 전진한다.
        if (docStateSkip(true, recheck, docState, docIdent, cd.updated)) {
          if (rollingSet.has(docIdent)) {
            // 롤링 재확인 — skip 예정이지만 seen_at 최고령이라 강제 재조회(아래로 계속 → 상세).
            rollingRechecked++;
            if (rollingSample.length < 5) rollingSample.push(docIdent);
          } else {
            skippedUnchanged++;
            if (cd.key) lastProcessedKey = cd.key;
            continue;
          }
        }
        if (detailFetched >= MAX_DETAIL_PER_SOURCE) { detailCapped = true; detailCapReason = "max_detail"; cappedRemaining = cands.length - i; break; }
        if (timeLeft() < 5_000) { detailCapped = true; detailCapReason = "time"; cappedRemaining = cands.length - i; break; }
        const row = cd.row;
        let path: string;
        let id: string;
        // 발주 축 결정 — 기표부가 재사용한다. ⚠️ 기표부에서 norm(Type) 을 재계산하지 말 것(두 곳이
        // 갈라질 여지). 판정 기준은 목록 Type 하나 — 엔드포인트 분기와 축 선택이 같은 값을 쓴다.
        let purchaseIsAdvanced = false;
        if (key === "purchase") {
          id = String(row?.ID ?? "").trim();
          // ⚠️ 엔드포인트 비대칭(실측): Advanced → purchase?ID= 는 400 deprecated(시끄러움) /
          //   Simple → advanced-purchase?ID= 는 200 + 빈 껍데기(조용함 — Status:"" · Lines:[]).
          purchaseIsAdvanced = norm(row?.Type).includes("ADVANCED");
          if (purchaseIsAdvanced) advancedCount++; else simpleCount++;
          path = (purchaseIsAdvanced ? "/advanced-purchase?ID=" : "/purchase?ID=") + encodeURIComponent(id);
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
        // 라인 소멸 감지 G1(②-b 판): 문서 안 부분 스킵이 하나라도 있으면 A 가 불완전 — 판정 제외.
        // (미배송 fulfilment·날짜 결손·비 AUTHORISED 블록/CN 등 — 그 라인들은 Cin7 에 실재하는데
        //  A 에 없으므로, 제외하지 않으면 전부 "사라진 라인"으로 오판한다)
        let docIncomplete = false;

        if (key === "sale") {
          const header = { order_number: docNo, sale_id: id, status: det?.Status ?? row?.Status ?? null };
          const fuls = (det?.Fulfilments ?? []) as any[];
          fulfilmentsSeen += fuls.length;
          for (let fi = 0; fi < fuls.length; fi++) {
            const f = fuls[fi];
            // ShipmentDate(실측 3/3 일치)가 원장 날짜 — IsShipped true 라인만. 비었으면 건너뛰고 카운트.
            const shipLines = ((f?.Ship?.Lines ?? []) as any[]).filter((l) => l?.IsShipped === true);
            if (!shipLines.length) { noShipFulfilments++; docIncomplete = true; continue; }
            const dates = [...new Set(shipLines.map((l) => dateOnly(l?.ShipmentDate)).filter(Boolean))] as string[];
            if (!dates.length) { missingDateItems++; docIncomplete = true; warnings.push("shipped fulfilment without usable ShipmentDate: " + docNo); continue; }
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
          // ── 축 결정 (2026-08-18 재설계 — docs/sessions/2026-08-18-purchase-putaway-axis.md) ──
          // Advanced 발주의 입고는 2단계(StockReceived=창고 도착 → PutAway=선반 배치)이고 **확정
          // 축은 PutAway 다**: SR 라인은 LocationID·Location 이 null(창고 GUID 이거나 아예 null —
          // resolveLoc 이 UNMAPPED(no-id)/bin 없음을 냈다. bin 이 구조적으로 안 얻어진다)이고,
          // SR 의 Status 는 stock receiving 단계의 워크플로 상태라 재고 반영 여부가 아니다
          // ([실측] PO-00703 SR=DRAFT/PA=AUTHORISED · 62줄 FULLY RECEIVED ·
          //  PO-01131 SR=NOT AVAILABLE/PA=AUTHORISED · 62줄 3,570u). SR·PA 는 같은 입고의 두 표현
          // (15건 표본 srLines==paLines)이라 **둘 다 읽으면 정확히 두 배**가 된다 — 하나만.
          // Simple 은 SR 에 LocationID 가 있다([실측] PO-00874) — SR 축 유지.
          // ⚠️ 축은 purchaseIsAdvanced(목록 Type — 엔드포인트 분기와 같은 기준)로만 가른다.
          //   **배열 존재 여부로 고르지 말 것** — "PA 가 비면 SR 폴백"은 지금 고치는 결함을 가장
          //   필요한 순간(선반 미배치 Advanced = 창고가 가짜로 들어가는 바로 그 경우)에 되살린다.
          const paBlocks = Array.isArray(det?.PutAway) ? det.PutAway : det?.PutAway ? [det.PutAway] : [];
          const srBlocks = Array.isArray(det?.StockReceived) ? det.StockReceived : det?.StockReceived ? [det.StockReceived] : [];
          const axis = purchaseIsAdvanced ? "putaway" : "stock_received";
          const blocks = purchaseIsAdvanced ? paBlocks : srBlocks;
          if (purchaseIsAdvanced && !paBlocks.length) {
            // Advanced 인데 PA 블록 없음 = 선반 미배치(실무상 PA 는 무조건 하나, 완료 문서 기준
            // 30/30 표본 — 진행 중 PO 는 이 상태일 수 있다). **행을 만들지 않고 넘어간다.**
            // ⚠️ 커서를 멈추지 않는다 — 증분 축(판매·발주·반품)에는 disposition/hold 기계가 없고,
            //   세우면 선반 배치를 영영 안 하는 PO 하나가 발주 축을 영구 동결시킨다(근거 사고:
            //   TR-00012~76 이 커서 앞에서 캡 40 을 소진해 뒤 ~3,000건 실명). put-away 가 문서를
            //   갱신해 다음 회차 UpdatedSince 에 재등장한다는 전제다 — ⚠️ **이 전제는 미확인**
            //   (관찰 대상 — adv_no_putaway 가 회차마다 같은 문서면 전제가 틀린 것).
            advNoPutaway++;
            docIncomplete = true;
            advNoPutawaySrLines += srBlocks.reduce((n: number, b: any) => n + (((b?.Lines ?? []) as any[]).length), 0);
            if (advNoPutawaySamples.length < 5) advNoPutawaySamples.push(docNo);
          } else {
            if (!purchaseIsAdvanced && paBlocks.length) {
              // Simple 인데 PA 블록 존재 — 축 모델의 반례 후보. 처리는 SR 축 그대로, 관측만.
              simpleWithPutaway++;
              if (simpleWithPutaway === 1) warnings.push("Simple purchase WITH PutAway block(s): " + docNo + " - processed on the SR axis, inspect");
            }
            for (const b of blocks) {
              const bst = norm(b?.Status);
              const axisStatusCounts = purchaseIsAdvanced ? paBlockStatusCounts : srBlockStatusCounts;
              axisStatusCounts[bst || "(empty)"] = (axisStatusCounts[bst || "(empty)"] ?? 0) + 1;
              // ── 블록 상태 화이트리스트: 두 축 모두 AUTHORISED 만 (2026-08-18) ──
              // ⚠️ 종전(.7)의 "빈 문자열 통과" 예외는 삭제 — 근거였던 PO-01128 은 Advanced 였고
              //   빈 상태는 SR 블록이었다(PA 는 AUTHORISED · 84줄 · bin 84/84). PA 축에선 근거 소멸.
              // ⚠️ 어제(f33260f)의 "SR NOT AVAILABLE/DRAFT 제외 = 유령 재고 차단" 판정은 무효 —
              //   SR 상태는 워크플로 중간 상태라 실재 입고를 지우고 있었다(PO-00703·PO-01131).
              //   화이트리스트 방향 자체는 옳다 — 틀린 것은 어느 배열의 상태를 보느냐였다.
              // 어휘 밖 값은 경고 — 표본으로 어휘를 확정하지 않는다(NOT AVAILABLE 로 그렇게 틀렸다).
              if (bst !== "AUTHORISED") {
                const skKey = axis + ":" + (bst || "(empty)");
                blocksSkipped[skKey] = (blocksSkipped[skKey] ?? 0) + 1;
                // [실측 2026-08-18] PO-01117 — Convert 직후 PA 블록이 DRAFT 로 생성된다.
                //   종전 어휘 실측 {AUTHORISED:37, VOIDED:1} 은 표본이 완료 문서라 진행 중 상태를 못 봤다.
                const known = purchaseIsAdvanced ? ["VOIDED", "DRAFT"] : ["VOIDED", "NOT AVAILABLE", "DRAFT", ""];
                if (!known.includes(bst)) warnings.push("unknown " + axis + " block Status: '" + bst + "' on " + docNo);
                docIncomplete = true;
                continue;
              }
              for (const line of (b?.Lines ?? []) as any[]) {
                // 관측 전용 2종 — ⚠️ 필터링 금지(dry 숫자를 보고 다음에 결정한다).
                //   NonInventory 는 SR 라인에만 있는 필드([실측]) — PA 축의 0 은 "없는 것"인지
                //   "안 보이는 것"인지 아직 모른다. 그대로 보고만 한다.
                if (line?.NonInventory === true) nonInventoryLines++;
                if (line?.Received === false) receivedFalseLines++;
                const q = Number(line?.Quantity ?? 0);
                if (q === 0) { zeroQtyLines++; continue; }
                const d = dateOnly(line?.Date);   // 분할 입고는 블록이 아니라 Lines[].Date 로 갈린다([실측] PO-00703 — 블록 1개에 두 날짜)
                if (!d) { missingDateItems++; docIncomplete = true; continue; }
                const loc = locOf(line, docNo);
                // line_ref = CardID (2026-08-18 — 종전 "다른 소스와 통일해 ProductID" 폐기):
                //   PA 는 같은 SKU 를 빈 단위로 쪼개 여러 줄로 담고, 같은 빈·같은 SKU 가 날짜만
                //   달라 두 줄인 사례가 실재한다([실측] PO-00944 KUZ77036: 7/15 894 · 7/16 6).
                //   유니크 키에 occurred_on 이 없어 ProductID 면 두 줄이 한 행으로 뭉개진다 —
                //   판매의 <fulfilment TaskID>:<ProductID> 와 같은 구조의 문제.
                //   유일성 실측: ProductID 94/97·109/110 vs CardID 97/97·110/110·62/62.
                //   ⚠️ CardID 의 재수집 안정성(Type 전환 시 재생성 여부)은 미확인 — 관찰 대상.
                let ref = String(line?.CardID ?? "").trim();
                if (!ref) {
                  ref = "nocard:" + pidOf(line);
                  cardIdFallback++;
                  warnings.push("purchase line without CardID: " + docNo + " " + String(line?.SKU ?? "?"));
                }
                rows.push({
                  doc_type: cfg.docType, doc_number: docNo, doc_task_id: id || null, source: "cin7",
                  occurred_on: d, seq_hint: 1,
                  sku: String(line?.SKU ?? "").trim(), warehouse: loc.warehouse, bin: loc.bin,
                  qty_delta: q, event_type: "po_in",
                  line_ref: ref,
                  amount: null,
                  raw: mkRaw(line, { ...header, axis, block_status: b?.Status ?? null, block_task_id: b?.TaskID ?? null, ir_number: b?.InvoicingAndReceivingNumber ?? null }, "po_in: +Quantity(" + q + ") " + axis + " line"),
                });
              }
            }
          }
        } else {   // creditnote
          const header = { order_number: docNo, sale_id: id };
          const cns = (det?.CreditNotes ?? []) as any[];   // ⚠️ 한 오더에 여러 개(실측 SO-00062) — 전부 순회
          creditNotesSeen += cns.length;
          for (const cn of cns) {
            const rst = norm(cn?.RestockStatus);
            restockStatusCounts[rst || "(empty)"] = (restockStatusCounts[rst || "(empty)"] ?? 0) + 1;
            if (rst !== "AUTHORISED") { docIncomplete = true; continue; }   // DRAFT 는 Restock 이 비어 있다 — 금액만, 재고 미복귀 (과거 AUTHORISED 수집분과의 비교가 불완전해지므로 판정도 제외)
            const restock = (cn?.Restock ?? []) as any[];
            if (!restock.length) { emptyRestock++; docIncomplete = true; continue; }
            const d = dateOnly(cn?.CreditNoteDate);
            if (!d) { missingDateItems++; docIncomplete = true; warnings.push("credit note without usable CreditNoteDate: " + docNo); continue; }
            // ⚠️ doc_number = CreditNoteNumber — 오더번호가 아니다. 한 오더에 CN 이 여럿이라
            //   오더번호를 쓰면 유니크 키가 깨진다.
            const cnNo = String(cn?.CreditNoteNumber ?? "").trim();
            if (!cnNo) { noCnNumber++; docIncomplete = true; warnings.push("credit note without CreditNoteNumber on " + docNo + " - rows skipped (unique key would collide)"); continue; }
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
        // 라인 소멸 감지 A 집합 — G1(②-b): 부분 스킵 없는 문서 + rows>0 만 (rows=∅ 는 미배송·
        // 미입고 등 정상 상태가 다양해 오탐원 — ②-a 와 달리 축적하지 않는다).
        // ⚠️ lmo = cd.updated — saleList 'Updated'(hello 폴링 실측)·purchaseList 'LastUpdatedDate'
        //   (리시빙 관문 실측). LastModifiedOn 이라는 필드는 ②-b 목록에서 미확인 — 실측된 갱신
        //   시각 필드를 쓴다(G4: 없으면 skip+카운트). creditnote 는 rows 의 doc_number 가 CN 번호
        //   (한 sale 에 여럿)라 doc_number 로 그룹핑 — 단 CN 이 문서에서 통째로 사라진 경우는
        //   rows 에 그 번호가 없어 못 잡는다(알려진 한계 — 주석으로만).
        if (!docIncomplete && rows.length) {
          if (!cd.updated) missingSkippedNoLmo++;
          else {
            const byDoc = new Map<string, Set<string>>();
            for (const rr of rows) {
              let ks = byDoc.get(rr.doc_number);
              if (!ks) { ks = new Set(); byDoc.set(rr.doc_number, ks); }
              ks.add(ledgerKeyOf(rr));
            }
            const st = String(det?.Status ?? row?.Status ?? "").trim() || null;
            for (const [dn, ks] of byDoc) missingDocs.push({ docNumber: dn, lmo: cd.updated, docStatus: st, keys: ks });
          }
        }
        // 문서 상태 기록 대상 (결함 D) — **부분 스킵 없는 문서만**(!docIncomplete — 소멸 감지
        // G1 과 같은 자세). docIncomplete(미배송 fulfilment·비 AUTHORISED 블록·DRAFT CN·
        // adv_no_putaway 등)는 ②-a 의 비종결에 해당한다 — 기록하면 「갱신 없이 완성되는」
        // 미확인 경로(예: put-away 가 LastUpdatedDate 를 안 올리는 경우)에서 영영 skip 된다.
        // 지금처럼 겹침 창(커서 −1일) 동안 늘 조회한다. 쓰기는 commit 블록.
        if (!docIncomplete) {
          const ident = cursorDocIdent(row);
          if (ident && cd.updated) docStateRows.push({ source_key: key, doc_number: ident, last_modified: cd.updated,
            doc_status: String(det?.Status ?? row?.Status ?? "").trim() || null, collector: COLLECTOR_VERSION });
        }
        if (cd.key) lastProcessedKey = cd.key;
      }

      // 4) 커서 (would-be) — 파일 상단 캡 보정·tie-breaker 절:
      //    비캡 회차 = 회차 시작 시각(문서 상태로 멈추지 않는다 — 미완료 문서는 갱신되면 재등장)
      //    캡 회차   = 마지막 처리 문서의 키 <Updated>|<식별자> (오름차순 처리 전제 — 캡 밖 후보를
      //               다음 회차가 이어받고, Updated 동률 그룹 안에서도 식별자로 전진한다 — 결함 C)
      const runStartIso = new Date(t0).toISOString();
      const { cursorWouldBe, cursorStalled } = decideCursor(detailCapped, lastProcessedKey, cursorBefore, runStartIso);
      // ⚠️ 결함 B 차단 (2026-08-17 .6): Updated 없는 문서(정렬상 맨 앞)가 캡을 채우면
      //   lastProcessedKey 가 null → 커서 무변 → 다음 회차도 같은 40건 = 동결.
      //   from_cursor 하한을 만들게 한 실사고(TR-00012~76 캡 소진)와 같은 모양 — commit 을 막고
      //   응답으로 드러낸다(dry 에서도 판별되게). 풀기: Cin7 쪽 Updated 를 채우거나,
      //   inv_sync_state.last_cursor 를 비우고 ?from_since= 로 재시드(②-a 하한 흐름과 동형).
      const cappedNoUpdated = detailCapped && lastProcessedKey == null;
      // ⚠️ 결함 C 증상 가드 (2026-08-30): 캡에 걸렸는데 커서가 전진하지 않으면 원인 불문 동결이다
      //   (decideCursor — cappedNoUpdated 는 「시각이 없다」만 보는 더 구체적인 진단이라 그대로 두고,
      //   이 가드가 A·B·C 와 미래의 사촌까지 증상으로 잡는다). commit 차단은 아래 5).
      if (cursorStalled) warnings.push("CURSOR STALLED - capped and cursor would not advance (cursorBefore=" + cursorBefore + ", wouldBe=" + cursorWouldBe + ") - collection is frozen; commit is blocked");

      // 라인 소멸 감지 — G3(②-a 와 동일): 회차 중단이면 소스 전체 skip. 검출은 dry 에서도(보고).
      let missingCheckSkipped: string | null = null;
      if (listAborted) missingCheckSkipped = "list_aborted: " + listAborted;
      else if (truncated) missingCheckSkipped = "list_truncated";
      else if (detailCapped) missingCheckSkipped = "detail_capped: " + detailCapReason;
      let missing: Awaited<ReturnType<typeof detectMissingLines>> | null = null;
      // ⚠️ 진단은 수집을 막지 않는다 — 검출 실패는 경고, 수집·커서는 정상 진행.
      //   (감싸지 않으면 REST 순단 한 번에 이 소스 회차 전체가 abort — 원장 쓰기·커서 전진이
      //    통째로 멈추는데 cron.job_run_details 는 succeeded = 조용한 정지)
      if (!missingCheckSkipped) {
        try {
          missing = await detectMissingLines(cfg.docType, missingDocs, warnings);
        } catch (e: any) {
          missing = null;
          missingCheckSkipped = "detect_failed: " + String(e?.message ?? e).slice(0, 200);
          warnings.push("missing-line detection failed (collection unaffected): " + missingCheckSkipped);
        }
      }

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
        updated_ties: updatedTies,   // ⚠️ 동률 그룹 조기 신호 — 캡보다 커지면 결함 C 상황(가드가 잡는다)
        detail_fetched: detailFetched,
        docs_processed: docsProcessed,
        detail_capped: detailCapped,
        detail_capped_reason: detailCapReason,
        detail_capped_remaining: cappedRemaining,
        // ⚠️ 시끄러운 캡 보고 — 캡 회차의 커서 보정 덕에 유실은 없지만, "적게 나온 게 정상" 오해 방지
        detail_capped_alert: detailCapped
          ? "CAPPED - " + cappedRemaining + " candidate doc(s) NOT processed this round; cursor stops at the last processed doc's cursor key so the next run continues"
          : undefined,
        // 문서 상태 skip (2026-08-31 결함 D) — 1회차는 기록이 없어 skipped_unchanged 0 이 정상.
        skipped_unchanged: skippedUnchanged,
        doc_state_known: docState ? docState.size : 0,
        doc_state_error: docStateError ?? undefined,   // 있으면 이번 회차는 전량 조회로 동작했다
        // 롤링 재확인 (2026-08-31 — pickRollingRecheck 절 · ⚠️ ②-b 는 최근 창만 검산)
        rolling_rechecked: rollingRechecked,
        rolling_recheck_sample: rollingSample,
        doc_state_oldest_seen: rollingOldestSeen ?? undefined,
        precision_skipped: precisionSkipped,   // ⚠️ 캡 회차 "다음" 회차에만 0 이 아닌 것이 정상
        cursor_frozen_alert: cappedNoUpdated
          ? "capped with no usable Updated - cursor would freeze; commit is blocked (clear inv_sync_state.last_cursor and re-seed with ?from_since= if stuck)"
          : undefined,
        cursor_stalled_alert: cursorStalled
          ? "capped and cursor would not advance (cursorBefore=" + cursorBefore + ", wouldBe=" + cursorWouldBe + ") - collection is frozen; commit is blocked"
          : undefined,
        ledger_rows: sink.rows.length,
        zero_qty_lines: zeroQtyLines,
        since_filtered_rows: sink.stats.since_filtered_rows,
        non_inventory_skipped: sink.stats.non_inventory_skipped,
        non_inventory_sample: sink.stats.non_inventory_sample,
        missing_date_items: missingDateItems,
        merged_lines: sink.stats.merged_lines,
        merged_lines_alert: sink.stats.merged_lines > 0 ? "NOT ZERO - the line_ref assumption is broken, inspect raw.merged_lines_raw" : null,
        empty_sku_lines: sink.stats.empty_sku_lines,
        empty_sku_alert: sink.stats.empty_sku_lines > 0 ? "NOT ZERO - parsing is wrong for this source; commit is blocked until fixed" : undefined,
        field_fallbacks: fieldFallbacks,
        date_histogram: sink.dateHist,
        // 라인 소멸 감지 (2026-08-25 · TR-04175) — inserted 는 commit 블록에서 채운다
        missing_lines_detected: missing ? missing.detected : 0,
        missing_lines_bin_changed: missing ? missing.binChanged : 0,   // bin 만 바뀐 행 — 소멸 아님(키 규칙 변경의 흔적)
        missing_lines_inserted: 0,
        missing_lines_sample: missing ? missing.sample : [],
        missing_lines_capped: missing ? missing.capped : false,
        missing_lines_skipped_no_lmo: missingSkippedNoLmo,
        missing_check_skipped_reason: missingCheckSkipped ?? undefined,
        samples: sink.rows.slice(0, 5),
        warnings,
      });
      if (missing && missing.detected > 0) warnings.push(missing.detected + " ledger line(s) NO LONGER in the Cin7 doc (deleted lines?) - see inv_missing_lines; ledger rows kept (append-only), human review needed");
      if (sink.stats.empty_sku_lines > 0) warnings.push(sink.stats.empty_sku_lines + " line(s) dropped for empty sku - parsing is wrong for this source");
      if (key === "sale") {
        Object.assign(R, {
          fulfilments_seen: fulfilmentsSeen,
          no_ship_fulfilments: noShipFulfilments,
          ship_date_ambiguous: shipDateAmbiguous,
          avg_pick_lines_per_doc: docsProcessed ? Math.round((pickLineCount / docsProcessed) * 10) / 10 : null,
        });
      } else if (key === "purchase") {
        if (advNoPutaway > 0) warnings.push(advNoPutaway + " Advanced doc(s) without PutAway - rows NOT made (shelf placement pending), e.g. " + advNoPutawaySamples.join(", "));
        Object.assign(R, {
          advanced_docs: advancedCount,
          // ⚠️ simple_docs 는 0 도 >0 도 정상 — Type 은 가변이지만 전환은 자동이 아니라 사람이
          //   Cin7 UI 에서 Convert 를 누르는 동작([실측 2026-08-18] PO-01117 Apply 후 31분 무변).
          //   Convert 가 보통 빨리 눌려 수집이 Simple 상태를 볼 확률이 낮을 뿐이다(세션 문서 §8).
          simple_docs: simpleCount,
          list_stock_received_status_counts: srsCounts,      // 관측 전용 — 이제 거르지 않는다
          list_combined_receiving_status_counts: crsCounts,  // 신규 관측
          putaway_block_status_counts: paBlockStatusCounts,
          sr_block_status_counts: srBlockStatusCounts,
          blocks_skipped: blocksSkipped,                     // 예: {"putaway:VOIDED": 3} — 축 접두어
          adv_no_putaway: advNoPutaway,                      // 선반 미배치 Advanced 문서 수 (행 미기표)
          adv_no_putaway_sr_lines: advNoPutawaySrLines,      // 그 문서들의 SR 라인 수 — "도착은 했는데 미배치"와 "아무것도 안 옴" 구분
          adv_no_putaway_samples: advNoPutawaySamples,       // 문서번호 최대 5
          adv_no_putaway_alert: advNoPutaway > 0
            ? advNoPutaway + " Advanced doc(s) had no PutAway block - NO rows were made for them; cursor NOT held (they re-enter when put-away updates the doc - that assumption is UNVERIFIED, watch for repeats)"
            : undefined,
          simple_with_putaway: simpleWithPutaway,
          card_id_fallback: cardIdFallback,
          non_inventory_lines: nonInventoryLines,            // 관측 전용 — 거르지 않음(SR 라인에만 있는 필드)
          received_false_lines: receivedFalseLines,          // 관측 전용 — 거르지 않음
        });
      } else {
        Object.assign(R, {
          credit_notes_seen: creditNotesSeen,
          restock_status_counts: restockStatusCounts,
          list_restock_status_counts: listRestockStatusCounts,   // 목록 단계는 세기만 — 판정은 상세 한 곳
          empty_restock: emptyRestock,
          no_cn_number: noCnNumber,
          // ⚠️ dup_sale_dropped 는 0 이 아닌 것이 정상 — 한 오더에 CN 여럿(SO-00062)이라 목록 행이 겹친다
          dup_sale_dropped: dupSaleDropped,
          sale_id_present: saleIdPresent,
          sale_id_fallback: saleIdFallback,
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
        else if (cappedNoUpdated) blocked = "capped with no usable Updated - cursor would freeze";
        else if (cursorStalled) blocked = "capped and cursor would not advance (cursorBefore=" + cursorBefore + ", wouldBe=" + cursorWouldBe + ") - collection is frozen";
        if (blocked) {
          R.write_skipped = blocked;
        } else {
          const w = await writeLedgerDetectingConflicts(sink.rows, key);
          await sbUpsert("inv_sync_state", "source_key", [{
            source_key: key,
            last_cursor: cursorWouldBe,
            last_run_at: new Date().toISOString(),
            last_ok_at: new Date().toISOString(),
            note: COLLECTOR_VERSION + " rows=" + sink.rows.length + " inserted=" + w.inserted + (detailCapped ? " capped" : ""),
          }]);
          // 문서 상태 기록 (결함 D) — ②-a 와 동일(원장 쓰기 성공 뒤에만 · dry 는 안 쓴다).
          // ⚠️ 진단·최적화는 수집을 막지 않는다 — 실패는 경고만(다음 회차가 그 문서를 다시 읽는다).
          if (docStateRows.length) {
            try {
              const seenAt = new Date().toISOString();
              await sbUpsert("inv_doc_state", "source_key,doc_number", docStateRows.map((r) => ({ ...r, seen_at: seenAt })));
            } catch (e: any) {
              warnings.push("doc-state upsert failed (collection unaffected): " + String(e?.message ?? e).slice(0, 200));
            }
          }
          R.written = w.inserted;                    // ⚠️ 2026-08-19 의미 변경: 시도 행수 → 실삽입 행수(재수집 중복 제외)
          R.insert_skipped = w.insert_skipped;       // 버려진 행 수 — 0 아님이 정상(재수집 포함)
          R.conflicts_detected = w.conflicts_detected;
          R.conflicts_sample = w.conflicts_sample;
          // 라인 소멸 기록 — ②-a 와 동일(원장 쓰기 성공 뒤에만 · dry 는 검출·보고만)
          // ⚠️ 진단은 수집을 막지 않는다 — 원장 쓰기는 이미 성공했으므로 기록 실패가
          //   응답을 500 으로 만들면 안 된다. 실패 시 inserted 0 + 경고(다음 회차가 재검출).
          if (missing && missing.rows.length) {
            try {
              R.missing_lines_inserted = await insertMissingLines(missing.rows);
            } catch (e: any) {
              warnings.push("missing-line insert failed (collection unaffected, will re-detect next round): " + String(e?.message ?? e).slice(0, 200));
            }
          }
        }
      }
      // 회차 로그 (2026-08-31 · inv_collect_runs — dry 미기록 · 차단 회차도 기록 · 실패는 경고만)
      if (commit) {
        try {
          await writeCollectRun(buildCollectRun(key, R, warnings, Date.now() - t0));
          R.collect_run_logged = true;
        } catch (e: any) {
          R.collect_run_logged = false;
          R.collect_run_error = String(e?.message ?? e).slice(0, 200);
          warnings.push("collect-run log failed (collection unaffected): " + R.collect_run_error);
        }
      } else R.collect_run_logged = false;
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
