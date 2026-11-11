# Freightcom 연동 — 설계 정본

작성: 2026-10-28 · 집 PC · docs-1028h · 판정 677(시작) · 835 ~ 862(원문 표는 `so-module.md` §84-a · §85-a) · 선례 `shopify-integration.md`(날짜 절은 하루의 이야기 · 이 문서가 「지금 규칙」)
⚠️ 말하는 틀 — IMS 는 Cin7 없이 돈다(ims-principles 원칙 1). 이 설계의 주어는 IMS 와 Freightcom 둘뿐이다.
⭐ 상태 [2026-10-28] **테스트 환경 견적 · 예약 · 라벨 · 취소 끝**(테스트 DB `Asung-IMS` · Freightcom 테스트 토큰 · 실호출 넷 모두 취소함 · so-module §84-c · §85-c) · **운영 = 토큰 대기**(deferred 326 · 364) → ⭐ [2026-11-03 · Caleb · so-module §99-c 8] **토론토는 운영** — FREIGHTCOM_BASE_URL = `https://external-api.freightcom.com` · FREIGHTCOM_API_KEY_TOR = 운영 토큰 · FREIGHTCOM_API_KEY_EDM **지움**(시험 토큰은 운영 주소에서 안 통하고 남기면 가짜 예약 위험 · status EDM has_key false) · 코드 무변(키는 계정별 848 · 주소는 하나) · **에드먼턴은 운영 토큰 올 때까지 Freightcom 사이트에서 손 예약**(deferred 462 · 키 없을 때 IMS 화면이 무엇을 보이는지는 안 봤다)
⚠️ 운영에서는 아직 **손으로** 한다 — EF `freightcom` 은 `inv_config.db_role = 'test'` 가 아니면 멈춘다(`supabase/functions/freightcom/index.ts:3`) · ~~운영 토큰 · 비밀값 · 이 가드를 푸는 날이 운영 시작이다~~ → [2026-10-29 · 판정 617 확인 · so-module §87] 이 프로젝트(Asung-IMS)가 11-01 부터 **그대로 운영**이고 db_role 은 컷오버 뒤에도 'test'(`cutover-delete.sql:16`) — 이 가드는 asung-WMS 만 막을 뿐 운영을 가르지 못한다 ⇒ **운영 시작 = 비밀값을 운영 토큰 · 운영 BASE_URL 로 바꾸는 날**(그 전까지 이 프로젝트의 예약은 테스트 토큰 · 청구 없음)
⚠️ 예약은 운영에서 **실제 청구**(Net Terms) — 운영 토큰을 받기 전까지 실호출은 테스트 환경만 → [2026-11-03] 토론토는 운영 토큰이라 **IMS 의 토론토 예약 = 실제 청구** · 시험 때 예약을 IMS 에서 Cancel 하지 말 것 · ~~에드먼턴은 키 없음(손 예약)~~ → [2026-11-05] 에드먼턴도 운영 토큰(462 닫힘) — **IMS 의 에드먼턴 예약 = 실제 청구**
⚠️ [2026-11-04 · so-module §100-c 7 · **deferred 464**] **토론토 예약에 픽업이 안 잡힌 실물** — SO-20846(Purolator · regular_pickup f · 요청 날짜 · 시각을 보냄) → Freightcom state `waiting-for-scheduling` · pickup_confirmation 빈칸 · 직원이 사이트에서 손 요청 · 단서 = fc-2b 주석 「pickup_details 날짜 · 시각 꼴은 짐작」(실호출로 확인한 것은 pre_scheduled 꼴뿐) · 조사 fc-pickup-0 안 씀 · 그때까지 토론토 Book 뒤 Freightcom 사이트에서 픽업 확인 · 없으면 손 요청
⭐ [2026-11-05 ~ 06 · so-module §101 · **deferred 464 닫힘** · 462 닫힘] **픽업이 잡히게** — 원인은 **H2(픽업 몸에 연락처 없음)**: 11-06 비정기 상자 9 건 schedule error(UPS 「Missing or invalid ContactName」 7 · Purolator 「Sender Name is a mandatory field」 2) → fc-pickup-3 이 contact_name · contact_phone_number 를 싣는다(1049) · 예약 뒤 IMS 가 픽업 상태를 **다시 읽고**(fc-pickup-1) **5 분마다 스스로 읽는다**(fc-pickup-2 · cron 64 · 1041) · 출고 뒤에도 Action Centre 「Pickups not scheduled」(fc-pickup-4 · 1050) · reference_codes · 주말 → 월요일(1040 · 1048) — 아래 §7 · §8-b · ⚠️ 「fc-2b 꼴 짐작」 단서는 **낡았다**(FedEx · Canpar 가 같은 꼴을 받는다) · **에드먼턴 운영 토큰** `FREIGHTCOM_API_KEY_EDM` 넣음(11-05 · Caleb · `ref_warehouse.freightcom_account` TOR · EDM) ⇒ 에드먼턴 예약도 IMS 에서 = 실제 청구
⭐ [2026-11-11 · so-module §112 · 판정 1154 ~ 1168] **예약 뒤를 IMS 가 본다** — 상태 · 추적을 스스로 읽고(cron 68 `ims-fc-track-poll` · 1160) · Freightcom 에서 취소된 예약을 알아보고 인정하고(1158 · 1159) · 청구 문서 · 남은 한도를 읽고(cron 69 `ims-fc-finance-poll` · 1163 ~ 1166 · 결제는 사람이 Freightcom 사이트에서) · 보드 **Integrations › Freightcom**(fcb v1 · 1167) · **fc_ 표 11 개 모두 닫힘 — 화면은 창구로만**(1168 · deferred 362 · 564 닫힘) · §8-c ~ 8-e

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
| `fc_track_event` | 추적 이벤트(상태 · 이벤트뿐 — 주소 · 돈 없음 · at not null · 유니크(booking_id, at, type, md5(message)) · message = btrim 값 · 원문 raw · 칸 이름 `place`) — fc-track-2 · 처음부터 닫음 | D |
| `fc_document` | Freightcom 청구 문서 머리(열쇠 = Freightcom document id · raw 없음 · payments 는 [{type, amount_cents}] 만) — fc-track-3 · 처음부터 닫음(1166) | D |
| `fc_document_line` | 청구 문서 줄(PK document_id + line_id · 줄의 shipment_id = fc_booking.freightcom_shipment_id) — 1166 | D |
| `fc_balance` | 계정 잔액 이력(90 일) — 1166 | D |

칸: `ref_warehouse` + phone · email · contact_name(출발지) · `freightcom_account`(848) · `timezone`(857) · `closes_at`(852) · `customer_address` + residential · tailgate_required · threshold_delivery(839 · 840) · `inv_config.fc_markup_pct` = 5(836)
칸 [2026-11-11 · fc-track-2] `fc_booking` + state_checked_at · delivered_at · track_last · track_done_at(끝 상태 + 이벤트 함께 저장 때만) · cancel_source(ims | freightcom) · cancel_note(500 자) · `inv_config` + fc_track_poll_enabled · fc_track_poll_batch(10) · fc_finance_poll_enabled · fc_finance_doc_batch(25) · fc_credit_limit_TOR(5000) · fc_credit_limit_EDM(2000) · ⚠️ [2026-11-11 · 1168] **표 11 개 모두 닫힘**(RLS 정책 0 · anon · authenticated 권한 0 · service_role 은 그대로)

상태:
- 발송 `draft → quoted → selected → booked` · `cancelled`(다른 SO 묶음으로 갈아 끼울 때 superseded_by) · 예약 취소 = `booked → selected`(856)
- 예약 시도 `pending → booked | failed` · `booked → cancelled` · 10 분 넘은 pending 은 다음 prepare 가 failed 로 비켜 둔다(abandoned)
- [2026-11-11 · fc-track-2] Freightcom 쪽 상태 = `fc_booking.state`(lower 원문 · CHECK 없음) · 뜻은 `fc_state_kind(state)` 한 곳 → cancelled | delivered | open · Freightcom 에서 취소된 예약 = `booked` 그대로 + fc_state_kind cancelled → 사람이 「Mark cancelled in IMS」(1159) → `booked → cancelled` · 발송 selected · cancel_source freightcom
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
| `fc_track_due` · `fc_track_save` | EF(service_role) | [2026-11-11 · 1160] 읽을 예약(한 곳) · 상태 · 이벤트 저장(§8-c) |
| `fc_track_gate` | sales ∨ fulfillment ∨ freight_booking(쓰기) + 그 창고 | 사람 길 track_poll 의 문(Check status) |
| `fc_book_mark_cancelled` | freight_booking + 그 창고(`fc_book_gate`) | [1159] Freightcom 취소 인정 — 호출 없음 |
| `fc_finance_docs_save` · `fc_finance_lines_save` · `fc_finance_balance_save` · `fc_finance_lines_due` | EF(service_role) | [1163 ~ 1166] 청구 문서 · 줄 · 잔액(§8-d) |
| `fc_finance_gate` | freight_booking ∨ purchasing + 그 계정을 쓰는 창고 | 사람 길 finance_poll 의 문 |
| `fc_board` · `fc_board_detail` | 상태 문 · 돈 문(1167) | [1168] 보드 — 화면이 fc_ 를 읽는 유일한 길(§8-e) |

속 함수: `fc_gate`(견적 문) · `fc_book_gate`(예약 문) · `fc_hm` · `fc_ymd` · `fc_cutoff_parse` · `fc_past_cutoff` · `fc_cutoff_eval` · [2026-11-11] `fc_state_kind` · `fc_ts`(나노초 → 마이크로초) · `fc_booking_rate`(견적 정본 = 예약 응답 rate · 없으면 고른 견적 줄) · `fc_charge_check` · `fc_finance_account_summary` · `fc_doc_cents`
마이그레이션: `20261028162209` fc-1a ~ `20261028233000` fc-2b2(아홉) · EF `supabase/functions/freightcom/index.ts` + `../_shared/freightcom.ts` · [2026-11-11] `20261111020326` fc-track-2 · `20261111034018` fc-track-3 · `20261111042906` fc-track-4 · EF 새 파일 track.ts(inspect 꼴) · inspect · finance(fc-track-1 · 3)

## 4. 문(권한) — 853 · 854 · 859

- 견적 · 고르기 = `sales` 또는 `fulfillment` + 그 창고(창고 직원에게 sales 는 주지 않는다 · 판정 7)
- 예약 · 취소 · 다시 예약 = **`freight_booking`** 를 켠 사람만 + 그 창고 · admin · supervisor 는 늘(854)
- `freight_booking` 은 Staff 화면 두 방(WMS · IMS) 모두에(859 · `ims_perm_catalog` 의 `rooms ["wms","ims"]` · staff.html st v3b 가 둘 중 하나만 체크해도 남긴다)
- `freight_booking` 의 read 는 아무것도 주지 않는다(EF · DB 문은 write 만 본다) — deferred 366
- 운송사 × 창고 픽업 표는 화면에서 **Settings 에만**(Carrier pickups · master · 860) — DB 창구는 fulfillment + 그 창고도 받는다
- [2026-11-11 · 1154 · 1167] inspect = admin 만 · 보드 상태 문 = sales 보기 ∨ fulfillment 보기 ∨ freight_booking 쓰기 ∨ 돈 문 · **돈 문 = freight_booking ∨ purchasing 쓰기**(purchasing:read 는 돈 못 봄) · Check status = sales ∨ fulfillment ∨ freight_booking(쓰기) + 그 창고 · Mark cancelled = freight_booking + 그 창고(§8-c ~ 8-e)

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
- **aone(손님이 Shopify 에서 운임을 결제한 웹 오더 · `freight_locked`)만 운임 줄을 덮지 않는다**(836 · 844) — 견적 · 예약 · 기록만 · charge_amount = null · → [2026-10-29 · fc-lock-1 · 판정 882 · so-module §89] **갈린 형제 포함** — 발송에 든 SO 의 `split_from_id` 사슬을 위로(깊이 50 · 순환 가드) 거슬러 어느 SO 든 aone 스토어(`shop_store.kind = 'aone'` · 지금은 aonebeauty.com 하나) shop_order 에 이어지면 잠근다 · 판정 함수 `so_chain_shop_orders(so_id)`(invoker · public · anon · authenticated 회수 · 두 창구 안에서만) · asung.ca 는 판정 473 그대로(Shopify 운임 = 견적 · Freightcom 이 덮는다)
- [2026-10-29 · fc-lock-1 · 판정 882] 판정 549(`so_charge_gate` — packed 오더의 비용 줄: aone 스토어 오더 거부 · 스토어를 모르는 Shopify 오더 거부)도 **사슬로** 본다 — 형제는 `intake` shopify 를 물려받지만 shop_order 는 **원래 SO 에만** 있다 · 사슬을 안 보던 때는 형제가 aone · asung 가릴 것 없이 「Shopify order but its store is unknown」 으로 막혔다 → 이제 aone 형제는 「came from aonebeauty」 로 막히고 asung 형제는 보통 오더처럼 통과(fc-lock-1 이견 1 — 덤) · 오류 글 그대로 · ⚠️ 잠금(`freight_locked`)은 전에는 형제에 안 걸려 Freightcom 운임이 aone 형제에 붙었다(실측 SO-25259b)

## 7. 예약 · 픽업 규칙 — 852 · 857

- 예약 전 검사(`fc_book_prepare`): 발송 selected · 고른 줄 · 운송사 짝 · 계정 · 견적 valid_until · 견적 뒤 유닛 무변 · SO 출고 전
- **창고 시간대**(857): 「지금」 · 마감은 창고 시간대로 · Toronto = America/Toronto · **Edmonton = America/Regina**(Alberta 가 2026-11-01 부터 상시 UTC-6 · DB 의 tz 자료는 이 변경을 모른다 · 실측 2026-12-15 18:00 UTC → America/Edmonton 11:00 · Regina 12:00 · Toronto 13:00)
- **정기 픽업**(852 · `ref_carrier_pickup.regular_pickup`) 이 있는 상자 발송 = `pre_scheduled_pickup: true`(시각 없음)
- 그 밖 상자 = `pickup_details {pre_scheduled_pickup:false, date:{year,month,day}, ready_at:{hour,minute}, ready_until:{hour,minute}}`(회사 실호출 FedEx 로 확인) · 팔렛(LTL) = `dispatch_details` 같은 꼴(집 실호출 Maritime 으로 확인)
- 기본 창: 오늘이면 지금 + 1 분 ~ `closes_at` · 다음 날이면 **09:00 ~ `closes_at`** · 화면이 날짜 · Ready from · until 을 넣으면 그 값(비우면 DB 규칙)
- ⭐ [2026-11-06 · fc-pickup-3 `5d6cec3` · `20261107012000` · 판정 1049] 비정기 상자의 pickup_details 에 **`contact_name`** = `ref_warehouse.contact_name`(btrim) · **`contact_phone_number: {number}`** = fc_phone(창고 phone · 특수문자 없이 10 자리) — origin 과 같은 출처 · 비거나 10 자리가 아니면 **예약 거부**(Settings → Warehouses → Edit 의 Contact · Phone) · `pickup_location` 은 보내지 않는다(출처 칸 없음 · 문서 설명 없음) · 정기 픽업(`{pre_scheduled_pickup:true}`) · 팔렛(dispatch_details)은 바이트 그대로 · 문서 근거: Customer API 2.11.0 PickupDetails
- ⭐ [판정 1048 · Caleb 11-06] **토론토 · 에드먼턴 모두 토 · 일 출고 안 함** — 자동 픽업 날(ship_date · 오늘 · 마감 지남 · 문 닫힘의 +1)이 토 · 일이면 다음 **월요일** + 경고 `weekend:<날>` · 직원이 적은 날(p_pickup.date)이 주말이면 거부 · 공휴일은 아직 안 본다 ⇒ 금요일 늦은 Book → 월요일 픽업
- ⭐ [판정 1040] **`details.reference_codes`** = [운임 SO(charge_so_id · fc_charge_so_set 으로 옮긴 것 포함), 같은 발송의 나머지 SO(created_at · so_number 순)] · 원소당 SO 번호 하나 · 견적 details 의 값은 덮는다 · 운임 SO 가 발송의 live SO 에 없으면 created_at 순 + 경고 `charge_so_missing` · 개수 · 길이 한도는 문서에 없다(라벨 Reference 에 어떻게 찍히나는 첫 실물 · deferred 485)
- **마감**: Freightcom `carrier_cut_off_time` 이 진짜면 그것 먼저(cutoff_source freightcom) · 아니면 `ref_carrier_pickup.cutoff`(ims) · 없으면 모른다 — ⚠️ 테스트 환경은 전부 가짜 `31-12-0000 06:42PM`(연도 0000 → null) · 운영에서 다시(364)
- 마감 지남 → 다음 날 + 경고 `past_cutoff:` · 창고 문 닫힘(지금 ≥ closes_at) → 다음 날 + 경고 `closed:` — 경고는 응답의 `prepare_warnings` 에만(DB 칸 없음 · 화면이 「— 」 뒤 글을 칸에 남긴다 · 새로 고치면 사라짐)
- 지난 운송사는 「마감 지남」 · 미리 고르기에서 뺀다(고를 수는 있다)
- 운송사 마감은 창고 `closes_at` 보다 늦을 수 없다(`ref_carrier_pickup_set` 거부)
- 값(closes_at · 정기 픽업 · 마감)은 **창고 담당자가 말하면 오피스(master)가 Settings 에 넣는다**(860) · 테스트 DB 지금 값: closes_at Toronto 17:00 · Edmonton 16:00(Caleb 화면 2026-10-28) — 실제 값 아님 · 담당자에게 받아야 한다(~~deferred 367~~ → [2026-10-29] 617 확인으로 **컷오버 전 필수 deferred 369** · reload-procedure §P-2 0c)

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

## 8-b. 픽업 다시 읽기 · 자동 · Action Centre — 1041 · 1050 (2026-11-05 ~ 06 · fc-pickup-1 · 2 · 4 · so-module §101)

- **왜**: 예약 순간 Freightcom 은 픽업을 따로 잡는다 — IMS 가 그 순간 상태만 적으면 「안 잡힘」 을 아무도 모른다(464 · SO-20846)
- **1041 ① 다시 읽기 · 알리기**(fc-pickup-1 `9971dbf` · `20261105183506`): fc_booking 칸 넷 — `schedule_status`(원문 lower · 40 자 · CHECK 없음) · `schedule_error` · `schedule_checked_at`(마지막 성공 읽기) · `schedule_response` / 파서 `fc_schedule_parse` 하나 / 저장 `fc_book_schedule_save`(service_role · booked 만 · 확인번호는 비었을 때만 채움 · 다르면 경고) / 판정 `fc_pickup_check(b)` — needed = booked ∧ 비정기 상자(pre_scheduled_pickup false) · **not_scheduled** = needed ∧ 번호 없음 ∧ (error · timed-out ∨ 모르는 값 ∨ 읽은 적 없음 ∨ 예약 뒤 **15 분** ∨ done 인데 번호 없음) · pending = 15 분 안 pending · 영어 한 줄은 DB 한 곳 / `fc_booking_for_shipment.current.pickup_check` · EF `pickup_poll {booking_id}`(GET `/shipment/{id}/schedule` 만 · 청구 없음 · GET 실패면 DB 무변)
- **schedule 응답 꼴** = `{error, pickup_confirmation_number, status}` **맨몸**(실물 11-06)
- **1041 ② 자동**(fc-pickup-2 `7447121` · `20261107000000`): 스위치 `inv_config.fc_pickup_poll_enabled`(**on** · 11-06 Caleb) · `fc_pickup_poll_batch` 10 / `fc_booking.schedule_done_at`(done 을 처음 본 시각 · 덮지 않음) / `fc_call_log.detail`(회차 요약 · action pickup_sweep) / 대상 한 곳 `fc_pickup_poll_due(p_limit)` — needed ∧ 번호 없음 ∧ Freightcom id 있음 · **창** = now() < greatest(booked_at + 48 h, 픽업 날 + 2 일 00:00 America/Toronto) · **2 단** = 예약 뒤 2 시간 안은 회차마다 · 그 뒤 마지막 성공 읽기에서 30 분 / cron **jobid 64** `ims-fc-pickup-poll` `*/5` → EF `pickup_sweep`(`supabase/ops/cron.sql`)
  - 첫 자동 회차(11-06 20:40) read 9 · done 8
  - ⚠️ 창의 「토론토 00:00」 은 에드먼턴(America/Regina · §7) 예약에도 같다(1 시간 차 · deferred 477)
  - ⚠️ 15 분 빨강은 그대로 — done_at 이 20 건 쌓이면 걸린 시간을 보고 다시(deferred 474)
- **화면 상태 줄**(asung-ims `ad8e85c` · so pk v1 · fu v1.10): 예약됨 칸에 ✓ Pickup scheduled — confirmation … / ⚠ Pickup NOT scheduled — <DB 글> · 「Schedule the pickup on the Freightcom site, then press Check pickup」 / ⏳ 잡는 중 · Check pickup = `pickup_poll` · ⚠️ 예약됨 칸은 Ship & invoice · WMS Finalize 단계에만 — **출고 뒤 사라진다**
- **1050 Action Centre**(fc-pickup-4 `fda40c7` · `20261107020808` · ml v1.5 `d20c047`): `fc_pickup_attention_list(p_warehouse_id)` — 대상 = booked ∧ 현재 시도 ∧ fc_pickup_check.not_scheduled(판정은 그 함수 하나) · 창 = poll_due 와 **같은 식**(⚠️ 둘을 같이 고친다 · 「목록에 있다 = cron 이 아직 읽는다」) · 창고 두 겹(p_warehouse_id ∧ ims_can_warehouse) · 정렬 픽업 날 → booked_at · 탭 「**Pickups not scheduled**」(여섯째) · 「확인함」 칸 없음(deferred 473) · 배지 = `ims_action_counts.pickups`(1051) · 실물 2 건
- ⚠️ `fc_book_cancel_save` 가 예약 응답(response)을 취소 응답으로 덮는다 — 그대로(deferred 475)
- ⚠️ 11-05 의 「10 건 done」 으로 fc-pickup-1 · 2 가 「원인 H1(Freightcom 이 늦게 스케줄)」 이라 적었으나 다음 날 error 9 건이 **H2** 를 보였다 — 그 10 건은 직원 손 요청이었을 공산(짐작 · so §101-c 5)

## 8-c. 예약 뒤 상태 · 추적 — 1154 ~ 1160 (2026-11-10 밤 ~ 11-11 · fc-track-0 · 1 · 2 · asung-wms `586ca9f` · so-module §112)

- **왜**(Caleb 11-10 · 원문 전문 = so-module §112-c 5): 「쉽먼트들이 픽업됐는지, 인트렌짓중인지, 딜리버리가 되었는지, 추가적으로 발생한 상황은 없는지도 말이야.」 — `fc_booking.state` 는 예약 순간 값 그대로였다(booked 53 중 40 · cron 64 는 schedule 만 읽는다)
- **스펙 사실**(fc-track-0 · OpenAPI 2.11.0 · md5 `afdb4a5dd8f843ba4339eaec62e42bb4`): state enum draft · waiting-for-transit · in-transit · delivered · exception · missing · cancelled · **웹훅 없음** · rate limit 글 없음 · 돈은 최소 단위 문자열
- **스펙 밖 실물**(11-10 inspect): state `waiting-for-scheduling`(booked 53 중 11) · 응답 키 `bolnumber` · 청구 줄마다 **`shipment_id`** · 추적 이벤트에서 「Out For Delivery」 · 지연은 type 이 아니라 **in-transit + message** · when 나노초 9 자리 · message 끝 공백 · `invoices-for-transaction-number` · `invoices-for-shipment-id` 는 **빈 배열**(쓰지 마라)
- **inspect**(fc-track-1 · EF 배포 · 저장 0 · GET 6): **1154** admin 만(`ims_is_admin()`) · **1155** 응답에서 http 로 시작하는 문자열 값 전부 · 카드 칸 셋(credit_card_number · credit_card_auth · credit_card_reference) 지움 · **1156** 로그는 메타만(몸 0 · 오류 「Freightcom inspect_<what> failed (HTTP n)」) · **1157** timeout 20 s 는 새 길에만(예약 · 견적 · 취소 · 픽업 길은 바이트 그대로) · balance 는 net-terms → prepaid → 422
- **1160 자동 읽기**(fc-track-2 · `20261111020326` · 확인 OK 40): cron **68** `ims-fc-track-poll` `7,22,37,52 * * * *` · 스위치 `fc_track_poll_enabled` **on** · batch 10 · EF track_sweep(회차 90 s 상한) · 사람 길 track_poll(Check status · 문 `fc_track_gate`)
  - 대상 한 곳 `fc_track_due`: booked ∧ Freightcom id ∧ track_done_at null ∧ 예약 뒤 30 일 안 ∧ (읽은 적 없음 ∨ 마지막 성공 읽기에서 3 시간 · out for delivery 면 1 시간) — 처음 먼저
  - `fc_track_save`: 응답 id ≠ 예약의 Freightcom id 면 거부 · 이벤트 중복 무시 · track_done_at 은 **끝 상태 + 이벤트를 함께 저장할 때만** · pickup_confirmation · bol_number 는 비었을 때만 · 추적번호 · SO 칸 무변(다르면 경고만)
  - 뜻은 `fc_state_kind` 한 곳(cancelled | delivered | open) — 실물로 본 값은 cancelled · delivered 뿐 · canceled · cancel% 는 **짐작** · 모르는 값은 open(계속 읽는다)
  - 첫 자동 회차(03:07 UTC 11-11) read 10 · changed 10 · failed 0
- **1158** Freightcom 에서 취소된 예약은 픽업 경고 · cron 64 · Action Centre 밖 / **1159** 「Freightcom 취소 인정」 `fc_book_mark_cancelled`(§10)
- 이견 아홉 받음(fc-track-2): cancel_source · cancel_note · track_done_at · at not null · message btrim · fc_track_gate · 새 파일 track.ts(inspect 꼴) · 90 s 상한 · fc_state_kind 한 곳 · 추적번호 · SO 칸 무변 · 칸 이름 `place`
- ⚠️ 읽은 적 없는 예약이 계속 실패하면 줄 앞을 차지한다(굶음 · deferred 572)
- ⭐ 실물로 풀린 것: Action Centre 「Pickups not scheduled」(11-10) Purolator SO-21022/21094(FC 취소) · UPS SO-21245/21249(픽업 거절 「closing time less than minimum window」) → 1158 · 1159

## 8-d. 청구 · 남은 한도 — 1163 ~ 1166 (2026-11-11 · fc-track-3 · asung-wms `d3e7e51` · `20261111034018` · 확인 OK 33)

- **Caleb 사실**: 「인보이스는 여러 쉽먼트를 묶어서 오는 걸로 알고 있어.」 · 「수시로 freightcom에 들어가서 결제해야 할 인보이스를 선택하고 등록해놓은 크레딧 카드로 결제하고 있어.」 · 한도 **TOR 5,000 · EDM 2,000**(「에드몬튼은 리밋이 2000불이야」)
- **청구 문서 실물**: `shipment-order-details`(번호 = transaction_number · **예약하는 순간 생긴다** · 같은 번호가 날짜를 달리해 여러 번 · 금액이 바뀌는 것 있음 — 49250480 11-06 174.39 → 11-10 256.75 · `other-charge-1` 72.88 추가) · `net-terms-invoice`(묶음 · 줄마다 shipment_id · due = date + 30 · 카드 결제로 owing 0)
- **1163** 쉽먼트별 견적 대비 청구 · 추가 요금(이름은 Freightcom 원문) — `fc_charge_check` state none | unread | billed | extra | less | cancelled_billed | unknown · **세전 합계 · 오차 100 ¢** · extra_lines 는 설명용 · 견적 정본 = 예약 응답 response.rate(없으면 고른 견적 줄 · 475) · 판 = 그 쉽먼트 줄이 든 shipment-order-details 중 날짜가 가장 늦은 것(「최근 판 = 전체 재진술」 은 **짐작**)
- **1164** 계정별 남은 한도(Freightcom 값이 정본) · 한도(설정 `fc_credit_limit_TOR` 5000 · `fc_credit_limit_EDM` 2000 · 달러) · 사용 = 한도 − 남은 한도 · 결제할 인보이스(owing > 0 — 실물은 전부 0 이라 꼴은 짐작) · 청구 전 합계
- **1165** 결제는 사람이 Freightcom 사이트에서 · IMS 는 보여 주기만 · 결제 API 안 부름 / **1166** 돈 표(fc_document · fc_document_line · fc_balance)는 처음부터 닫음
- 잇는 열쇠 = 줄의 shipment_id = `fc_booking.freightcom_shipment_id`(deferred 562 묶음 쪼개기는 이것으로 풀림) · 창은 오늘 − 35 일
- cron **69** `ims-fc-finance-poll` `43 11,15,19,23 * * *` · 스위치 `fc_finance_poll_enabled` **on** · EF finance_sweep · 사람 길 finance_poll(GET 만 · 결제 없음 · 문 `fc_finance_gate`)
- **실물**(11-11 04:07 UTC): **billed 53 · cancelled_billed 2 · extra 0** · TOR 남은 756.78(사용 4,243.22) · **EDM 남은 82.90(사용 1,917.10)** · unbilled 늘 0(청구 문서는 예약 순간 생긴다) · cancelled_billed = TOR **49195614**(SO-20945 · 33.83 · IMS 취소 11-05) · TOR **49250480**(SO-21106 · 256.75 · 취소 11-06 · 같은 발송을 49253023 으로 다시 예약 · 둘 다 청구) → Caleb 이 Freightcom 에 문의(other-charge-1 뜻도)
- ⚠️ IMS 취소(DELETE)가 Freightcom 청구를 지우지 않는 것으로 보임(**짐작** · Freightcom 답 대기 · deferred 573)

## 8-e. 보드 — Integrations › Freightcom · 1167 · 1168 (2026-11-11 · fc-track-4 · asung-wms `06e597c` · `20261111042906` · 확인 OK 27 · 화면 fcb v1 `6e4690c`)

- **1167 문**: 보드 = Integrations › Freightcom · **상태 문** = sales 보기 ∨ fulfillment 보기 ∨ freight_booking 쓰기 ∨ 돈 문 · **돈 문 = freight_booking ∨ purchasing 쓰기**(purchasing:read 는 돈 못 봄) · 창고 경계(ims_can_warehouse) · 메뉴 열쇠 null(창구가 거부)
- **1168 창구로만**: 열린 fc_ 표 7 개(fc_booking · fc_call_log · fc_label · fc_quote · fc_quote_rate · fc_shipment · fc_shipment_so) select 정책 drop + anon · authenticated 권한 0 → **fc_ 표 11 개 모두 닫힘**(조사 11-10: 화면 · ims-*.js · ims-mcp · GAS 의 직접 읽기 0) · deferred **362 · 564 닫힘**
- `fc_board(p_from, p_to, p_warehouse_id, p_view, p_q, p_limit, p_offset)` — 창 = 예약일(토론토) from ~ to(기본 오늘 − 30 일 ~ 오늘) ∨ 배송이 안 끝난 것 · booked · cancelled 만 · q = SO 번호 · 손님 이름 · 운송장 · 거래 번호 · view = all | moving | problems | delivered | cancelled · 돈 칸은 돈 문 통과자에게만 · ⚠️ request · response · labels · schedule_response 는 싣지 않는다
- `fc_board_detail(p_booking_id)` — 행 · 이벤트(최신 먼저) · money(돈 문만: charge · documents · lines)
- **늦음** = 픽업일(없으면 예약일) + transit 영업일 · 주말 건너뜀 · 공휴일 안 셈 · 오늘 > expected + 1 일(**짐작**) · **exception** = fc_state_kind 가 모르는 state(**짐작** · 실물 0)
- 넣지 않은 것: 「묶음에 안 묶인 합」(사용액과 안 맞음 — TOR 59 % · EDM 20 %) · 「다음 결제로 풀릴 금액」(모든 shipment-order-details 줄을 읽어야 · deferred **569**) · IMS 밖 예약(deferred **565**)
- 화면 freightcom.html `fcb v1`: 계정 칸(남은 한도 · 사용 막대 · 결제할 인보이스 · 「Pay on the Freightcom site.」) · 탭 All · On the way · Needs a look · Delivered · Cancelled · 목록(상태 · 예상 · 운임 · 표지 Late · Exception · Cancelled on Freightcom · Pickup not scheduled · Extra charge · Billed after cancel) · 상세(추적 이벤트 · 견적 대비 청구 · Check status · Mark cancelled in IMS)

## 9. 라벨 — 851 · 858

- 상자 = **4 × 6(A6 PDF)** 기본 · Letter 고름 · 팔렛 = Letter(BOL 포함 짐작) · **팔렛 라벨을 IMS 가 따로 만들지 않는다**(Caleb · 팔렛마다 라벨 불필요)
- EF 가 Freightcom 의 labels[] 에서 a6 pdf(padded 아님) + letter pdf(세로)만 받아 `%PDF` 확인 → 비공개 버킷 `documents/fc_label/<발송>-<시도>-<size>.pdf` → `fc_label_add` · zpl 은 받지 않는다
- 화면은 EF `label {label_id}` → `fc_label_get`(문) → **서명 URL 120 초**로만 연다
- ⚠️⚠️ **Freightcom 라벨 원본 주소를 화면에 보이지 마라** — 테스트의 S3 주소에 서명이 없다(주소만 알면 열리는 꼴 · 라벨에 손님 주소) · 운영에서 서명 여부를 다시 본다(364)
  - ⚠️ 지금 원본 주소가 닿는 곳(docs-1028h 조사 · 레포 근거 · 실호출 확인 없음): `fc_booking_for_shipment` 의 current(`to_jsonb(b) - 'request' - 'response'` → labels 남음) · `fc_label_get` 반환(`to_jsonb(v_l)` → source_url) · **표 직접 읽기** — `fc_booking` · `fc_label` 은 RLS select `using (true)` + authenticated select(response · labels · source_url) ⇒ 화면이 안 그리는 것에 기대는 꼴 · deferred 362 → [2026-11-11 · fc-track-4 · 1168] ③ 표 직접 읽기는 닫힘(fc_ 표 11 개 · 362 닫힘) · 보드 창구는 labels 를 싣지 않는다
- 실측: 상자 3 개 → 추적 3 · 라벨 꼴마다 3 페이지 / 팔렛 3 개 → 추적 1 · Letter 1 페이지(회사 프로브)

## 10. 취소 — 855 · 856

- `fc_book_cancel_prepare`(freight_booking + 창고 · booked 만 · SO 가 shipped 면 거부) → `DELETE /shipment/{id}` → `fc_book_cancel_save`
- 발송은 **selected 로**(고른 줄 그대로) — 견적이 유효하면 바로 다시 예약(856)
- SO 칸은 예약 때 쓴 값과 **아직 같을 때만** 그 전 값으로(그 사이 사람이 바꾼 칸은 둔다 · orders_kept)
- [2026-11-11 · 1158 · 1159] **Freightcom 쪽에서 취소된 예약**(사이트 손 취소 등)은 IMS 가 상태를 읽어 「Cancelled on Freightcom」 으로 보이고 픽업 경고 · cron 64 · Action Centre 에서 뺀다 · 사람이 Mark cancelled in IMS(`fc_book_mark_cancelled` · Freightcom 호출 없음 · SO 칸 856 되돌림 · response 안 덮음) · ⚠️ IMS 취소(DELETE)가 Freightcom 청구를 지우지 않는 것으로 보임(**짐작** · Freightcom 답 대기 · deferred 573 · §8-d)

## 11. 화면 (asung-ims · 대화 Claude)

- WMS `wms-fulfillment.html`(fu v1.4 ~ v1.5b): Freight 칸 — 견적 · 조건 · 기억 · 줄 고르기 · Book(픽업 날짜 · 시각 · 실제 청구 확인 창) · 진행 칸 · Check again · 예약됨 칸(운송사 · 추적 링크 · BOL · 픽업 확인번호 · 픽업 · 라벨) · Cancel booking · Finalize 확인 글 「BOOKED …」 / 「— not booked yet」 · ⚠️ 예약은 Finalize 전(뒤에는 작업대에서 사라진다)
- **잠금**: 예약됨 ∨ 진행 중(pending) ∨ 기다리는 중이면 다시 견적 · Use this rate · 조건을 잠근다(상태가 둘 — 발송 · 예약 — 이라 곱으로 센다)
- 오피스 `so.html`(so v5x ~ v5y1): Ship & invoice 창 Freight 칸 — 같은 엔진 · 같은 모양 + 누가 · 언제 예약했나
  - ⚠️⚠️ **`so_finalize` 는 창의 운송사 · 송장 칸을 그대로 보낸다** — DB 가 예약 때 SO 에 쓴 송장을 창의 빈 칸이 덮을 수 있다 ⇒ so v5y: 오피스가 예약하면 발송의 모든 SO 블록에 채움 · 창고가 예약한 뒤 창을 열면 **빈** 칸만 채움 · 취소하면 예약 송장과 **같은** 칸만 비움 · Fill carrier · tracking 단추
- Settings(set v10 ~ v11a): Warehouse Edit(연락처 · Freightcom 계정 · 시간대 · Closes at) · Carriers(Freightcom names) · Shipping quotes(markup % · 창고 연결) · **Carrier pickups**(`?t=pickup`)
- 손님(cs v7 · v7a): 주소 배송 조건 · 기본 운송사 · 피할 운송사
- Staff(st v3b): 열쇠의 방 = `rooms`
- [2026-11-11] so.html `so fct v1` · wms-fulfillment.html `fu v1.11`(`af9c53d`): 예약 칸 배송 상태 한 줄(🚚 · ✓ Delivered · 예외 노랑) · Check status · 「Cancelled on Freightcom」 띠 · Mark cancelled in IMS · SO 상세 Carrier 아래 한 줄(출고된 오더 포함) / **freightcom.html `fcb v1` · ims-auth.js `nav v19`**(`6e4690c`): 보드(§8-e)
- ⬜ 매뉴얼에 아직 없다(deferred 368) → [2026-11-11 · docs-1111a] 보드 · 예약 칸 배송 상태 · Check status · Mark cancelled 는 매뉴얼 01-sales `sales-freightcom` 에 들어감 · 예약 장 자체는 아직(368 부분)

## 12. 운영으로 가는 조건 (deferred 326 · 364)

- ~~Freightcom 운영 토큰(TOR · EDM — Edmonton 은 API 를 따로 신청)~~ → [2026-11-03] TOR · [2026-11-05] EDM 운영 토큰(deferred 462 닫힘 · so §101-b)
- ~~EF 비밀값을 운영 프로젝트에 · EF 의 테스트 전용 가드(`db_role = 'test'`) 풀기~~ → [2026-10-29 · 617 확인] 같은 프로젝트(Asung-IMS)의 비밀값 `FREIGHTCOM_API_KEY_TOR` · `_EDM` · `FREIGHTCOM_BASE_URL` 을 운영 값으로 바꾼다 · 가드는 그대로(운영을 가르지 않는다 — 머리 줄) · 운영 토큰 요청 메일 2026-10-29(보냈는지 못 봤다 · deferred 326 · 364)
- 다시 볼 것: 운송사 진짜 마감 · 라벨 원본 주소의 서명 여부 · 운송사별 pickup_confirmation(FedEx 비정기 픽업은 옴 · Maritime 팔렛은 null — 짐작) → [2026-11-06] 비정기 상자 픽업은 연락처가 있어야 잡힌다(H2 · 1049) · 확인번호는 예약 뒤 다시 읽어 받는다(§8-b) · 처리 시간 · Purolator Freight 400 · Edmonton 출발 견적 · Apex Freightcom 이름(실제 쓰는 날)
- closes_at · 정기 픽업 · 마감 실제 값(창고 담당자) — **컷오버 전 필수**(deferred 369 · 남김 표라 컷오버 지우기에 안 지워진다)
- ~~원본 라벨 주소가 닿는 곳 닫기(362)~~ → [2026-11-11 · fc-track-4 `06e597c` · 1168] 닫힘(§8-e)
