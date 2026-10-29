# Freightcom 연동 — 설계 정본

작성: 2026-10-28 · 집 PC · docs-1028h · 판정 677(시작) · 835 ~ 862(원문 표는 `so-module.md` §84-a · §85-a) · 선례 `shopify-integration.md`(날짜 절은 하루의 이야기 · 이 문서가 「지금 규칙」)
⚠️ 말하는 틀 — IMS 는 Cin7 없이 돈다(ims-principles 원칙 1). 이 설계의 주어는 IMS 와 Freightcom 둘뿐이다.
⭐ 상태 [2026-10-28] **테스트 환경 견적 · 예약 · 라벨 · 취소 끝**(테스트 DB `Asung-IMS` · Freightcom 테스트 토큰 · 실호출 넷 모두 취소함 · so-module §84-c · §85-c) · **운영 = 토큰 대기**(deferred 326 · 364)
⚠️ 운영에서는 아직 **손으로** 한다 — EF `freightcom` 은 `inv_config.db_role = 'test'` 가 아니면 멈춘다(`supabase/functions/freightcom/index.ts:3`) · 운영 토큰 · 비밀값 · 이 가드를 푸는 날이 운영 시작이다
⚠️ 예약은 운영에서 **실제 청구**(Net Terms) — 운영 토큰을 받기 전까지 실호출은 테스트 환경만

---

## 1. 무엇을 하나 — 엔진 하나 · 입구 둘 (판정 835)

- 옛 길: Freightcom 웹에 로그인 → 견적 → 운임 금액을 IMS 에 손으로 → 예약 → 운송사 · 추적번호를 IMS 에 손으로(so-module §1-p · 두 번 옮겨 적힌다)
- 새 길: **IMS 가 견적을 받고(운임 줄) · 예약하고(운송사 · 추적번호 · BOL · 라벨) · 취소한다** — 한 번에
- **엔진 하나** = DB 창구 + EF `freightcom` 하나 · **입구 둘**:
  - ① 기본 = **창고** — WMS Fulfillment 작업대(asung-ims `wms-fulfillment.html` · Finalize 전) — 치수 → 견적 → 운송사 고르기 → 예약 → 라벨 인쇄
  - ② 오피스 길 = **Ship & invoice 창**(asung-ims `so.html`) — 창고가 못 했거나 창고 견적이 틀렸을 때 같은 견적 · 예약을 다시
  - Caleb(835): 「그렇지만 wms가 못하면, 오피스에서도 할 수 있는 길도 열었으면 좋겠어.」 · 「wms에서 낸 견적이 잘못된 경우에 오피스에서 다시 낼 수 있는 길도 있었으면 좋겠어.」
- **한 발송에 살아 있는 예약은 하나**
- 범위 밖: 트랜스퍼(842)

## 2. 표 — 칸 · 상태

| 표 | 무엇 | 컷오버 |
|---|---|---|
| `fc_shipment` | 한 발송 = SO 하나 이상(같은 배송지 · 같은 창고 · 상자만 또는 팔렛만 838) · 견적 때 보낸 스냅샷(origin · destination · options · units · request) · `charge_so_id`(837) · `freight_locked`(836 · 844) · `freightcom_account`(848 스냅샷) · `address_review`(845) · `booking_id`(현재 · 마지막 시도) | D |
| `fc_shipment_so` | 발송에 든 SO · `live` · 부분 유니크 = 한 SO 는 살아 있는 발송 하나 | D |
| `fc_quote` | 견적 한 번(요청 · 응답 원문 · `seq` = 최신 열쇠 fc-1b2 · pending 줄) | D |
| `fc_quote_rate` | 견적 줄(센트 정수 · pretax · customer_charge · carrier_id · avoided · preselected · cutoff · cutoff_source) | D |
| `fc_booking` | 예약 시도 한 번 = 한 행(attempt · unique_id · request · response · labels 원문 · 추적 · BOL · 확인번호 · `so_written`) | D |
| `fc_label` | 받아 둔 라벨 PDF 한 장(a6 · letter · path · bytes · sha256 · source_url) | D |
| `fc_call_log` | EF 호출 기록(90 일 · action · account · ms) | K |
| `ref_carrier_fc_name` | 운송사 한 줄의 Freightcom 이름 여럿(847 · name_norm 유니크) | K |
| `ref_carrier_pickup` | 운송사 × 창고 정기 픽업 · 마감(852) | K |
| `customer_carrier_avoid` | 손님마다 피할 운송사(843) | K |

칸: `ref_warehouse` + phone · email · contact_name(출발지) · `freightcom_account`(848) · `timezone`(857) · `closes_at`(852) · `customer_address` + residential · tailgate_required · threshold_delivery(839 · 840) · `inv_config.fc_markup_pct` = 5(836)

상태:
- 발송 `draft → quoted → selected → booked` · `cancelled`(다른 SO 묶음으로 갈아 끼울 때 superseded_by) · 예약 취소 = `booked → selected`(856)
- 예약 시도 `pending → booked | failed` · `booked → cancelled` · 10 분 넘은 pending 은 다음 prepare 가 failed 로 비켜 둔다(abandoned)
- unique_id = 발송 id · 2 차부터 `<발송 id>-<attempt>`(같은 시도를 두 번 보내도 Freightcom 이 하나만 세운다)

## 3. 창구 — DB 가 검사 · 기록 · EF 는 나른다

| 창구 | 누가 | 무엇 |
|---|---|---|
| `fc_shipment_prepare` | sales 또는 fulfillment + 그 창고 | 검사(창고 · 배송지 · 상자/팔렛 · 치수 · 무게 · 전화 · 주소) → 발송 행 + /rate payload(DB 가 만든다) |
| `fc_quote_pending` · `fc_quote_save` | EF(service_role) · 직원 | 202 request_id 줄 · 결과 저장(836 셈 · 843 · 852 마감 · preselected) |
| `fc_quote_select` | 같은 문 | 줄 고르기(avoided · 짝 없는 운송사 거부) |
| `fc_charge_so_set` | sales | 운임 줄을 받을 SO 옮기기(837) |
| `fc_shipment_for_so` | 읽기 | 화면 둘이 같은 모양으로 읽는다(마감 · 시간대 · units_changed) |
| `wms_unit_dims_set` | sales 또는 fulfillment + 창고 | 치수 · 무게(841) |
| `customer_carrier_avoid_set` · `fc_address_review_close` | sales | 843 · 845 |
| `ref_carrier_fc_names_set` · `ref_carrier_pickup_set` | master(픽업은 + fulfillment + 그 창고) | 847 · 852 |
| `fc_book_prepare` | freight_booking + 그 창고 | 예약 전 검사 · 픽업(852) · p_commit = pending 행 |
| `fc_book_pending_set` · `fc_book_save` | EF(service_role) | 202 의 Freightcom id · 결과(855 SO 칸) |
| `fc_book_cancel_prepare` · `fc_book_cancel_save` | freight_booking · EF | 856 · 855 되돌림 |
| `fc_label_add` · `fc_label_get` | EF · 읽기 | 858 |
| `fc_booking_for_shipment` | 읽기 | 현재 시도 · 이력 · 라벨 행 · can_book |

속 함수: `fc_gate`(견적 문) · `fc_book_gate`(예약 문) · `fc_hm` · `fc_ymd` · `fc_cutoff_parse` · `fc_past_cutoff` · `fc_cutoff_eval`
마이그레이션: `20261028162209` fc-1a ~ `20261028233000` fc-2b2(아홉) · EF `supabase/functions/freightcom/index.ts` + `../_shared/freightcom.ts`

## 4. 문(권한) — 853 · 854 · 859

- 견적 · 고르기 = `sales` 또는 `fulfillment` + 그 창고(창고 직원에게 sales 는 주지 않는다 · 판정 7)
- 예약 · 취소 · 다시 예약 = **`freight_booking`** 를 켠 사람만 + 그 창고 · admin · supervisor 는 늘(854)
- `freight_booking` 은 Staff 화면 두 방(WMS · IMS) 모두에(859 · `ims_perm_catalog` 의 `rooms ["wms","ims"]` · staff.html st v3b 가 둘 중 하나만 체크해도 남긴다)
- `freight_booking` 의 read 는 아무것도 주지 않는다(EF · DB 문은 write 만 본다) — deferred 366
- 운송사 × 창고 픽업 표는 화면에서 **Settings 에만**(Carrier pickups · master · 860) — DB 창구는 fulfillment + 그 창고도 받는다

## 5. 견적 규칙

- **상자만 또는 팔렛만**(838) · 치수 · 무게는 견적 때만 필수(841 · 오피스도 넣는다)
- **주거지 기본**(839): 주소에 기억한 값이 먼저 → 없으면 SO 스냅샷의 배송지 회사 이름이 있으면 상업지 · 아니면 주거지
- **주소 조건 셋 기억**(840): 주거지 · 테일게이트 · 인사이드 — 견적 때 고치고 「기억」 하면 주소에 굳는다
  - 창고의 기억은 주소에 쓰지 않고 `address_review`(「주소 기억 필요 — 오피스 확인」)만 남긴다 → 오피스가 ① 주소 추가 ② 기본 배송 주소 바꾸기 ③ 이번만 으로 닫는다(845)
  - 주소 찾기 = 글자 맞추기 · 못 찾거나 둘 이상이면 같은 표시(845)
- **테일게이트 · 인사이드는 팔렛 발송에만**(850) — 상자 견적에는 열쇠를 싣지 않고 · 스냅샷의 두 값 = null(「해당 없음」) · 상자 기억은 주소의 두 값을 안 건드린다
- 배송 조건 칸은 Shipping · Business 주소에만(849 · Billing 은 화면이 숨김 · DB 그대로)
- **운송사 짝**(846 · 847): 견적 줄의 carrier_name 을 `ref_carrier_fc_name` 으로 IMS 운송사에 잇는다 · 짝 없는 줄은 고를 수 없다(오피스가 Settings → Carriers 에 더한다) · 한 운송사에 이름 여럿
- **피할 운송사**(843): 손님마다 · 흐림 · 고를 수 없음 · 미리 고르기에서 뺀다
- **미리 고르기**: 손님 기본 운송사 중 최저 → 없으면 전체 최저(피할 것 · 짝 없는 것 · 마감 지난 것 제외 852)
- **Freightcom 계정은 창고마다**(848): `ref_warehouse.freightcom_account`(TOR = Asung Trading Inc. · EDM = Asung - Edmonton) · EF 는 `FREIGHTCOM_API_KEY_<계정>` 만 읽는다 · 없으면 422 「연결 없음」 · 화면 꼬리표 TOR 파랑 · EDM 초록 · 그 밖 보라(fu v1.5b · so v5y1)

## 6. 손님 운임 — 836 · 837 · 844

- `customer_charge = round(pretax × (1 + fc_markup_pct / 100))` 센트 · `pretax = base + 할증 합`(세금 제외) · `fc_markup_pct` = 5(Settings → Shipping quotes · master)
- 고른 줄의 운임이 **운임 줄 하나**로 `charge_so_id` 의 SO 에 — 발송에 SO 가 여럿이어도 운임은 한 SO(837 · 기본 = 가장 먼저 만든 SO · `fc_charge_so_set` 로 옮긴다)
- **aone(손님이 Shopify 에서 운임을 결제한 웹 오더 · `freight_locked`)만 운임 줄을 덮지 않는다**(836 · 844) — 견적 · 예약 · 기록만 · charge_amount = null

## 7. 예약 · 픽업 규칙 — 852 · 857

- 예약 전 검사(`fc_book_prepare`): 발송 selected · 고른 줄 · 운송사 짝 · 계정 · 견적 valid_until · 견적 뒤 유닛 무변 · SO 출고 전
- **창고 시간대**(857): 「지금」 · 마감은 창고 시간대로 · Toronto = America/Toronto · **Edmonton = America/Regina**(Alberta 가 2026-11-01 부터 상시 UTC-6 · DB 의 tz 자료는 이 변경을 모른다 · 실측 2026-12-15 18:00 UTC → America/Edmonton 11:00 · Regina 12:00 · Toronto 13:00)
- **정기 픽업**(852 · `ref_carrier_pickup.regular_pickup`) 이 있는 상자 발송 = `pre_scheduled_pickup: true`(시각 없음)
- 그 밖 상자 = `pickup_details {pre_scheduled_pickup:false, date:{year,month,day}, ready_at:{hour,minute}, ready_until:{hour,minute}}`(회사 실호출 FedEx 로 확인) · 팔렛(LTL) = `dispatch_details` 같은 꼴(집 실호출 Maritime 으로 확인)
- 기본 창: 오늘이면 지금 + 1 분 ~ `closes_at` · 다음 날이면 **09:00 ~ `closes_at`** · 화면이 날짜 · Ready from · until 을 넣으면 그 값(비우면 DB 규칙)
- **마감**: Freightcom `carrier_cut_off_time` 이 진짜면 그것 먼저(cutoff_source freightcom) · 아니면 `ref_carrier_pickup.cutoff`(ims) · 없으면 모른다 — ⚠️ 테스트 환경은 전부 가짜 `31-12-0000 06:42PM`(연도 0000 → null) · 운영에서 다시(364)
- 마감 지남 → 다음 날 + 경고 `past_cutoff:` · 창고 문 닫힘(지금 ≥ closes_at) → 다음 날 + 경고 `closed:` — 경고는 응답의 `prepare_warnings` 에만(DB 칸 없음 · 화면이 「— 」 뒤 글을 칸에 남긴다 · 새로 고치면 사라짐)
- 지난 운송사는 「마감 지남」 · 미리 고르기에서 뺀다(고를 수는 있다)
- 운송사 마감은 창고 `closes_at` 보다 늦을 수 없다(`ref_carrier_pickup_set` 거부)
- 값(closes_at · 정기 픽업 · 마감)은 **창고 담당자가 말하면 오피스(master)가 Settings 에 넣는다**(860) · 테스트 DB 지금 값: closes_at Toronto 17:00 · Edmonton 16:00(Caleb 화면 2026-10-28) — 실제 값 아님 · 담당자에게 받아야 한다(deferred 367)

## 8. 예약 흐름 (EF `book`)

1. `fc_book_prepare`(사용자 JWT · p_commit false) → 계정 · 비밀값 확인(없으면 422 · 쓰기 0) → p_commit true(pending 행)
2. 결제수단 `GET /finance/payment-methods`(계정마다 · 10 분 캐시 · net-terms 먼저 · id 는 코드에 없다)
3. `POST /shipment` → 202 {id} → `fc_book_pending_set`(Freightcom id · 실제 보낸 몸) · 2xx 아니면 `fc_book_save(p_error)` → 422
4. `GET /shipment/{id}` 1.5 초마다 최대 25 초 → 200 이면 `fc_book_save` · 아직이면 202 `pending:true` → 화면 Check again = `book_poll {booking_id}`(DB 의 Freightcom id 로 이어 받는다)
5. 라벨 받기(9 절) · 라벨 실패는 예약을 되돌리지 않는다(warnings)

- **855**: 예약 순간 발송의 **모든 SO** 에 carrier_id · carrier · tracking_number(목록은 쉼표) 를 쓰고 그 전 값을 `so_written` 에 · shipped 가 된 SO 는 두고 경고
- 시간: 실측 12 ~ 17 s — IMS 몫 2 ~ 3 s · **Freightcom 이 운송사와 처리하는 몫 약 13 s**(book_poll 202 × 8 → 9 번째 200) · 줄이지 않고 진행 칸으로 보인다(861)
- **진행 칸**(861): 시계로 짐작하지 않고 2 초마다 `fc_booking_for_shipment` 로 DB 의 실제 흔적을 읽는다 — ① IMS 검사(pending 행 없음) ② Freightcom 에 보냄(pending · Freightcom id 없음) ③ Freightcom 이 받음 · 운송사 확정 기다림(id 있음) ④ booked · 라벨 저장 중
- 실패(예: 테스트의 Purolator Freight `400 booking carrier`)도 failed 행으로 남는다

## 9. 라벨 — 851 · 858

- 상자 = **4 × 6(A6 PDF)** 기본 · Letter 고름 · 팔렛 = Letter(BOL 포함 짐작) · **팔렛 라벨을 IMS 가 따로 만들지 않는다**(Caleb · 팔렛마다 라벨 불필요)
- EF 가 Freightcom 의 labels[] 에서 a6 pdf(padded 아님) + letter pdf(세로)만 받아 `%PDF` 확인 → 비공개 버킷 `documents/fc_label/<발송>-<시도>-<size>.pdf` → `fc_label_add` · zpl 은 받지 않는다
- 화면은 EF `label {label_id}` → `fc_label_get`(문) → **서명 URL 120 초**로만 연다
- ⚠️⚠️ **Freightcom 라벨 원본 주소를 화면에 보이지 마라** — 테스트의 S3 주소에 서명이 없다(주소만 알면 열리는 꼴 · 라벨에 손님 주소) · 운영에서 서명 여부를 다시 본다(364)
  - ⚠️ 지금 원본 주소가 닿는 곳(docs-1028h 조사 · 레포 근거 · 실호출 확인 없음): `fc_booking_for_shipment` 의 current(`to_jsonb(b) - 'request' - 'response'` → labels 남음) · `fc_label_get` 반환(`to_jsonb(v_l)` → source_url) · **표 직접 읽기** — `fc_booking` · `fc_label` 은 RLS select `using (true)` + authenticated select(response · labels · source_url) ⇒ 화면이 안 그리는 것에 기대는 꼴 · deferred 362
- 실측: 상자 3 개 → 추적 3 · 라벨 꼴마다 3 페이지 / 팔렛 3 개 → 추적 1 · Letter 1 페이지(회사 프로브)

## 10. 취소 — 855 · 856

- `fc_book_cancel_prepare`(freight_booking + 창고 · booked 만 · SO 가 shipped 면 거부) → `DELETE /shipment/{id}` → `fc_book_cancel_save`
- 발송은 **selected 로**(고른 줄 그대로) — 견적이 유효하면 바로 다시 예약(856)
- SO 칸은 예약 때 쓴 값과 **아직 같을 때만** 그 전 값으로(그 사이 사람이 바꾼 칸은 둔다 · orders_kept)

## 11. 화면 (asung-ims · 대화 Claude)

- WMS `wms-fulfillment.html`(fu v1.4 ~ v1.5b): Freight 칸 — 견적 · 조건 · 기억 · 줄 고르기 · Book(픽업 날짜 · 시각 · 실제 청구 확인 창) · 진행 칸 · Check again · 예약됨 칸(운송사 · 추적 링크 · BOL · 픽업 확인번호 · 픽업 · 라벨) · Cancel booking · Finalize 확인 글 「BOOKED …」 / 「— not booked yet」 · ⚠️ 예약은 Finalize 전(뒤에는 작업대에서 사라진다)
- **잠금**: 예약됨 ∨ 진행 중(pending) ∨ 기다리는 중이면 다시 견적 · Use this rate · 조건을 잠근다(상태가 둘 — 발송 · 예약 — 이라 곱으로 센다)
- 오피스 `so.html`(so v5x ~ v5y1): Ship & invoice 창 Freight 칸 — 같은 엔진 · 같은 모양 + 누가 · 언제 예약했나
  - ⚠️⚠️ **`so_finalize` 는 창의 운송사 · 송장 칸을 그대로 보낸다** — DB 가 예약 때 SO 에 쓴 송장을 창의 빈 칸이 덮을 수 있다 ⇒ so v5y: 오피스가 예약하면 발송의 모든 SO 블록에 채움 · 창고가 예약한 뒤 창을 열면 **빈** 칸만 채움 · 취소하면 예약 송장과 **같은** 칸만 비움 · Fill carrier · tracking 단추
- Settings(set v10 ~ v11a): Warehouse Edit(연락처 · Freightcom 계정 · 시간대 · Closes at) · Carriers(Freightcom names) · Shipping quotes(markup % · 창고 연결) · **Carrier pickups**(`?t=pickup`)
- 손님(cs v7 · v7a): 주소 배송 조건 · 기본 운송사 · 피할 운송사
- Staff(st v3b): 열쇠의 방 = `rooms`
- ⬜ 매뉴얼에 아직 없다(deferred 368)

## 12. 운영으로 가는 조건 (deferred 326 · 364)

- Freightcom 운영 토큰(TOR · EDM — Edmonton 은 API 를 따로 신청)
- EF 비밀값을 운영 프로젝트에 · EF 의 테스트 전용 가드(`db_role = 'test'`) 풀기
- 다시 볼 것: 운송사 진짜 마감 · 라벨 원본 주소의 서명 여부 · 운송사별 pickup_confirmation(FedEx 비정기 픽업은 옴 · Maritime 팔렛은 null — 짐작) · 처리 시간 · Purolator Freight 400 · Edmonton 출발 견적 · Apex Freightcom 이름(실제 쓰는 날)
- closes_at · 정기 픽업 · 마감 실제 값(창고 담당자)
- 원본 라벨 주소가 닿는 곳 닫기(362)
