---
name: asung-so
description: >
  Asung Trading IMS 의 SO(판매) 모듈 — Cin7 Core 판매 오더·손님을 대체하는 네 번째 모듈. 손님·가격·딜·SO 거래 표를 다룰 때 먼저 읽으세요.
  "SO 모듈", "판매 오더", "세일즈 오더", "customer", "customer_address", "customer_contact", "손님 표", "손님 적재",
  "ImsLoadCustomer", "MarketingConsent", "마케팅 동의", "CASL", "기본 주소", "기본 배송지",
  "청구지", "parent_id", "부모 손님", "so.status", "so.intake",
  "Release to WMS", "at_wms", "재적재", "내리기",
  "deferrable", "딜", "so_deal", "product_tag", "케이스 할인", "GM20UOM12", "오더 전체 할인", "so_reprice", "discount_source", "so_confirm", "가용 재고"
  가 나오면 추측하지 말고 이 스킬과 정본 docs/design/so-module.md 를 확인하세요.
  ⚠️MarketingConsent 는 숫자다(2 Opt in · 3 Opt out · 0·1 둘 다 Unknown) — 순서·소거 추론으로 옮기지 마라,
  ⚠️재적재는 내리기 → upsert 순서(upsert 먼저면 Cin7 에서 지워진 옛 기본이 새 기본을 23505 로 막는다),
  ⚠️적재는 id·parent_id·note·default_*·label 을 보내지 않는다(null 로 보내는 것과 다르다),
  ⚠️「기본 하나」 유니크는 deferrable — 한 손님의 주소·연락처는 한 요청에 모아 보낸다,
  ⚠️SO 거래 표(so·so_line·so_charge·so_reserve)는 창구(so_create…)로만 쓴다 · unit_price null=가격 없음·0=무상,
  ⚠️줄 할인은 더하지 않는다 · 시스템 줄은 제품만으로 합치고 다시 견적 · 다시 매기기는 할인만 · 오늘은 ims_today(토론토).
---

# Asung SO(판매) 모듈 스킬

⭐ **설계 정본 `docs/design/so-module.md`** — 여기는 「모르면 사고가 나는 것」과 포인터만. 이 스킬과 정본이 어긋나면 **정본이 맞다**(정본 §9 = 9-a~9-j).
관련 스킬: `asung-po`(마스터·관계 표 규약 — 손님 셋이 그대로 따른다) · `asung-inv-ledger`(출고 사건 `so_out`) · `asung-wms`(Release to WMS 이후) · `cin7-api`(`references/customer.md`) · `asung-apps-script`(적재 스크립트 규칙 6).

## 0. 어디까지 왔나

```
손님 표 셋      ✅ 2026-09-22 — 마이그레이션 ① customer · customer_address · customer_contact(9-a~9-f) · ② job_title(9-g·9-h) · ③ 기본 하나 유니크 deferrable(9-i)
손님 첫 적재    ✅ 2026-09-22 — docs/probes/ImsLoadCustomer.gs · ⚠️ 테스트 DB(Asung-IMS)만 · 실측은 9-j
가격표          ✅ 2026-09-23 — 20260923154749(ref_price_tier 8행 · product_price · product.set_discount_pct) · 첫 적재 76,872줄 · docs/probes/ImsLoadPrice.gs · 테스트 DB(11-e · 11-g)
SO 거래 표      ✅ 2026-09-23 — 마이그레이션 ④ 20260923133042(so · so_line · so_charge · so_reserve · 시퀀스 SO-25000~) · ⑤ 20260923134840(so_merge_reason_ck 양방향) · 테스트 DB(§10)
SO 쓰기 ① 초안  ✅ 2026-09-23 — ①a 20260923182231(sales 권한 · 표 보정 · so_status_guard · so_price_for · so_copy_customer) · ①b 20260923191030(창구 열 개 so_create…so_detail · inv_config so_direct_order_tier_code) · ①c 20260923192101(운임 음수 금지) · 테스트 DB(§12)
할인 규칙 ②-0   ✅ 2026-09-23 — ②-0a 20260923224900(product_tag · so_deal 넷 · so_deal_best · so_order_discount · so/so_line 출처 칸) · ②-0b 20260923232500(ims_today · so_line_quote 3인자 · 창구 여섯 재발행 · so_reprice) · 테스트 DB(§13) · ⚠️ 운영은 둘을 한 번에
쓰기 ② 확정·할당 ✅ 2026-09-23 — ②a 20260924014219(so_confirm · so_unconfirm · 엔진 so_allocate_run · so_split · so_available · so_family_*) · 015859(so_available_many 식 한 곳) · 020852(grant) · 021413·021759(so_unconfirm 고침 둘) · ②b 022449(so_hold · so_reallocate · so_cancel · so_change_location · so_backorder_proceed · so_divide · so_detail·so_delete 재발행) · 023740(되돌리기는 표시와 사슬로) · 테스트 DB(§14)
쓰기 ③ 출고·백오더 ✅ 2026-09-24 — ③a 20260924141140(so_ship · inv_post_sale/inv_layer_post_sale · pick_short) · ③a′ 143507 · ③b 145105(so_backorder_close · 이어받기 · 다시 열기) · ③b′ 151719 · ③c 151038(만료 스윕 · so_backorder_list · cron 테스트 jobid 1) · ③b″ 153856(무상 줄 제외 · 만료 기간 supervisor 잠금) · 정본 §15
세금 ①·②      ✅ 2026-09-24 — ① 20260924172351(ref_tax_rule 31 · ref_tax_region 14 · ref_region_alias 143 · ims_region_from_address · so_tax_rule_for · so_tax_amount · so_tax_preview · 세율 불변) · ② 175014(so.tax_rule_id · tax_rule_manual · so_tax_refresh · so_tax_set_manual · 창구 여덟 재발행) · 정본 §16
인보이스 ⓐ      ✅ 2026-09-24 — ⓐ1 20260924200029(결제조건 34 · so_invoice 셋 · 60000 · so_invoice_issue/cancel/reissue · 문지기 짝 둘 · so.bill_to_customer_id · customer.invoice_split_by_store) · ⓐ2 202425(so_line.qty_removed 다섯 · so_finalize · so_ship·so_line_requote·so_detail·so_family_* 재발행) · 정본 §17 · ⓑ 결제·ⓒ 크레딧은 다음
결제 ⓑ          ✅ 2026-09-24 — ⓑ1 20260924234250(so_payment · alloc · order · 계좌 기본값 22 · so_customer_balance · so_invoice_remaining · 창구 다섯) · ⓑ2 20260925001733(발행 때 auto_deposit·auto_balance · deposit_applied · balance_forward · fulfilled 곧장 · 취소 가드 · so_proforma) · 검증 1a OK 100 · 1b OK 54 · 정본 §18
크레딧 ⓒ        ✅ 2026-09-25 — ⓒ1 20260925012354(so_credit 셋 · CR-01000 · 리스탁킹 피 설정 · 원장 credit_in 두 층 · inv_layer_apply 재발행 · 발행·취소·읽기) · ⓒ2 20260925014413(진 빚 · 발행 ② 크레딧 · 취소 가드 · 환불 크레딧부터 · 붙이기·떼기) · 검증 1a OK 53 · 1b OK 34 · 정본 §19 · ⭐ 새 일하는 방식 첫 실물
POS · counter ④a ✅ 2026-09-25 — a1 20260925133147(product_bin_overflow · 창구 둘 · ims_last_bin 재발행 · so_pick_plan) · a2 142307(so_create·so_status_guard·so_ship·so_confirm·so_allocate_run·so_tier_warnings·so_hold·so_divide 재발행 + so_confirm_precheck·so_allocate_all·so_pos_confirm·so_pos_reopen·so_pos_complete·so_pos_finish·so_counter_ship) · a3 144959(so_stock_short_check·_confirm·_list · so_pos_open_list) · 검증 OK 28·36·20 · 정본 §20
오더 병합 ④b    ✅ 2026-09-25 — 20260925151823(end_kind merged · so_line_merge_source · so_merge_chain_reaches · so_backorder_supersede 재발행 · so_merge_requote_calc·_hint · so_merge) · 검증 OK 22 · 정본 §21
읽기 창구 넷    ✅ 2026-09-25 — 인보이스 20260925191843(685c766 · so_invoice_list · so_invoice_detail · so_invoice_ar_summary) · 결제 195701(5507e0c · so_payment_remaining · so_payment_list · so_payment_detail) · 결제 식 일곱 201614(c8cabf5 · 복사 식 0) · 크레딧 205011(8f37651 · so_credit_remaining · so_credit_list · so_credit_prepare) · 검증 OK 17·14·9·17 · 정본 §22
오피스 화면     ✅ 2026-09-25 — asung-ims so.html v2.3 · so-invoices v1.2 · so-payments v1 · so-credits v1.1 · so-backorders v1.3 · pos v1 · manager-list v1 · 탭 묶음 Purchasing | Sales · CHECKLIST 7-f~7-l · 정본 §23
⑤ WMS 이관     ⬜ 2026-09-26 — 판정 아홉(옮겨 고친다 · 안의 모듈 · 창구 · uuid · ims_staff · asung-ims WMS 모드) · 조사 실측 · 차수 계획 → 정본 §24 · ⓪ 문서만 섰다
⑤ WMS 창구 ⑤-2a ✅ 2026-09-26 — 상태 짝 WMS 여섯 · so_wms_status(authenticated 불가) · Release/거둬들이기(sales) · packed = Finalize(창고 출하 준비 완료) · 재고 · 인보이스는 so_finalize(§24-h · i · j)
```
- ⭐ 전부 **테스트 DB(Asung-IMS)** 에만 있다 — `--db-url …testdb-url` 이 보이면 테스트 · 없으면 운영(CLAUDE.md 1절).

## 1. ⭐⭐ 손님 적재 — 모르면 사고

```
⭐⭐ MarketingConsent 는 숫자다 — 2→true(Opt in) · 3→false(Opt out) · 0·1→null(둘 다 Unknown) · 그 밖 → 적재 멈춤(추정해 넣지 않는다)
     ⚠️ 선택 목록 순서(Unknown·Opt in·Opt out)와 다르고 Unknown 이 둘 — 「셋 중 남은 하나」 추론이 틀렸다(0 을 Opt out 으로 짐작 → 화면은 Unknown)
        네 값 모두 Cin7 화면 대조로 확정 · 화면 대조 없이 옮기지 마라
     ⚠️ 보낼 때 null = false — 확인된 동의(true)에만 마케팅 메일(CASL)                                   (9-h ⑥ · 9-a ④)
⭐⭐ 재적재 순서 — 1) 전량 수집 2) 내리기(is_active=false + 기본 표시 풀기) 3) upsert(on_conflict=cin7_id · is_active:true) 4) 내린 수·되살린 수 보고
     ⚠️ upsert 먼저면 「Cin7 에서 지워진 옛 기본」이 문장에 없어 새 기본이 23505 — deferrable 은 한 문장 안 교대만 구한다
     지우지 않는다(PO 「한 규칙」 po-module §3-f) · source='manual' 은 어디에도 안 걸린다                  (9-i ⑩ · 시험 5)
⭐⭐ 「기본 하나」 유니크(customer_address_default_uq · customer_contact_default_uq)는 DEFERRABLE INITIALLY IMMEDIATE — 문장 끝에 한 번 검사
     ⇒ 한 손님의 주소·연락처는 **한 요청**(PostgREST 요청 하나 = 한 문장)에 모아 보낸다 · 묶음을 손님 중간에서 가르지 않는다
     ⚠️ initially deferred 가 아니다 · on_conflict 기준 cin7_id 는 plain 유니크 그대로(deferrable 은 arbiter 가 못 된다)   (9-i ⑪)
⭐⭐ 적재가 절대 보내지 않는 칸 — id · updated_at · updated_by · created_at · note · default_customer_id(생성 칸 — 보내면 거부) ·
     customer.parent_id(1단계) · default_ship_to_customer_id · default_bill_to_customer_id · customer_address.label
     ⚠️ 「보내지 않는다」 ≠ 「null 로 보낸다」 — PostgREST upsert 는 보낸 칸을 덮는다(null 을 실으면 재적재마다 지운다)
     보내도 되는 것: source='cin7' · is_active:true · is_default_for_type · is_default(규칙으로 메운 값 포함)
     customer_id 는 Cin7 손님 GUID 가 아니라 우리 customer.id — 1단계 뒤 cin7_id → id 조회해 바꿔 보낸다      (9-i ⑫)
⭐⭐ 부모는 두 단계 — 1단계 손님 전부(parent_id 없이) · 2단계 부모 있는 손님만 PATCH(CustomerParentID → customer.id) · 없어진 부모는 비움
     자기 참조 FK 는 줄마다 즉시 검사 — 자식이 먼저 들어가면 거부                                          (9-i ⑫)
⭐⭐ 적재 안전장치 둘 — 받은 행 ≠ API Total 이면 멈춤 · 한 번에 내리는 줄 > max(20, 1%) 면 멈춤(ILC_ALLOW_BIG_DOWN=1 로 한 번만 통과)
     계기: 가짜 데이터 시험에서 수집이 짧게 끝나자 151명을 내렸다 · ⚠️ 끝 판단은 Total 이 아니라 받은 행 수     (9-j)
⭐  멈춤 조건(추정해 넣지 않는다 · 로그에 적고 throw) — Status 가 Active·Deprecated 밖 · MarketingConsent 0~3 밖 · Type 이 Billing·Business·Shipping·빈 값 밖 ·
     한 손님에 Default 연락처 둘 이상 · 같은 cin7_id 두 번                                                 (ImsLoadCustomer.gs 머리)
```

## 1-b. ⭐⭐ 가격 적재 — 모르면 사고 (ImsLoadPrice.gs · ilp 접두 · 11-g)

```
⭐⭐ 세트는 Sellable=Yes 만 가져온다 — No 세트의 가격 칸 값은 낱개 한 개 값이 남은 것(4,890/5,464) · 가져오면 세트 하나가 낱개 값이 되어 틀린 가격 · 콤보는 낱개처럼 자기 가격(11-g ①)
⭐⭐ source='cin7' 줄만 다룬다 — formula·manual 줄은 읽지도 덮지도 내리지도 않는다(11-c 이견 3) · 사라진 가격은 is_active=false(지우지 않는다 · 11-g ②)
⭐⭐ price_set_at · price_set_by 는 보내지 않는다 — 트리거 product_price_set_touch 가 값이 바뀔 때만 채운다 · 같은 값을 다시 보내도 안 움직인다(11-c 이견 4)
⭐⭐ 티어는 이름이 아니라 code 로 맞춘다 — IMS 에 없는 code 가 오거나 같은 code 의 이름이 다르면 멈춘다(11-c 이견 8) · Cin7 의 0 은 「가격 없음」 = 줄 없음 · 음수는 건너뛰고 센다
```

## 2. ⭐ 기본 주소 · 배송지 기본값

```
⭐  기본 주소 규칙(is_default_for_type · 손님·type 마다) — 체크 1 그대로 · 없고 하나 → 메움 · 없고 여럿 / 둘 이상 → 비움(사람이 고른다 · 적재 보고에 이름)
     ⚠️ 둘 이상일 때 하나를 고르지 않는다(먼저·최근 모두 추정) — Cin7 이 기본 체크 둘을 막지 않는다               (9-h ⑦ · 9-a ③)
⭐  배송지 기본값은 **오더를 만들 때만** — ① 기본 Shipping → ② Shipping 이 0개일 때만 기본 Billing(「청구지에서 가져옴」 표시) → ③ 비움(사람이 고른다)
     ⚠️ 주소록에 Billing 을 Shipping 으로 복사해 넣지 않는다 · ⚠️ Business 는 기본값 찾기에 안 쓴다 · 구현은 SO 오더 화면 차수   (9-h ⑧)
⚠️  주소 type CHECK 셋 Billing · Business · Shipping(대소문자 그대로 · null 허용 · "" 는 적재 때 null)                          (검토 이견 2 · 마이그레이션 ①)
```

## 3. ⭐ 표 규약 · 낱말 · 이름 규칙

```
⭐  손님 셋 = PO 마스터·관계 표 규약(po-module §5) — customer 는 마스터(DELETE·TRUNCATE 막음 · Cin7 Status → is_active 로 물러남 · Comments → cin7_comments) ·
     주소·연락처는 관계 표(DELETE 열림 · 그래도 적재는 지우지 않고 내린다) · 쓰기 묶음 customer 는 master · 주소·연락처는 sales OR master(①a · 12-b 판정 1) · 트리거 <t>_touch → ims_touch()   (9-a ①② · §12)
⭐  「하나뿐」은 생성 칸 + 전체 유니크(default_customer_id) — 부분 유니크 인덱스 금지(asung-wms 규칙 29 · PostgREST on_conflict)          (5-b · 5-c · 9-i ⑪)
⭐  주소 칸 낱말 state_province · postal_code(ref_warehouse · supplier_address 와 같다 · 5-b 본문의 state·postcode 는 뒤집힘 — 9-d 표가 이력)
⭐  낱말 충돌 — so.status(오더 상태 · 6-a) ≠ customer 의 Cin7 Status(→ is_active) · so.intake(유입 넷 · 6-b · 처음 이름 source) ≠ source(cin7|manual · 어느 시스템이 만들었나) ·
     released → at_wms(6-a)                                                                                              (9-a ① · 6-a · 6-b)
⭐  이름 규칙(판정 ⑤) — 표 so_invoice · so_invoice_order · so_payment · so_payment_alloc · so_credit · so_credit_line · so_credit_alloc ·
     함수 so_<동작> · so_invoice_<동작> · so_payment_<동작> · so_credit_<동작> · 읽기 _detail/_list · 손님 셋은 앞머리 없음(supplier·product 처럼) ·
     ⚠️ 실제 이름은 각 차수의 지시서가 이 규칙으로 붙인다 — 지금 목록을 만들지 마라                                          (9-b)
⭐  FK+원문 짝 — currency_id+currency_code · payment_term_id+_name · default_location_id+_name(ref_warehouse.name 매칭) · ar/sale_account_id+_code ·
     ~~tax_rule 은 원문만(ref_tax_rule 미결)~~ → [2026-09-24 §16] so.tax_rule_id + tax_rule 짝 CHECK 섰다(customer 쪽 FK 는 안 만든다 · 계산에 안 쓴다) · price_tier 원문 옆 FK — so.price_tier_id 는 섰다(①a) · customer 쪽은 다음(재적재 함께 · 11-f)        (9-c ⬜2·⬜3 · 9-d · 11-f · 12-c ⬜3)
⭐  가격표(§11) — ref_price_tier 여덟 행(code 1~8 · purpose sale·compare·reference · currency_id FK 하나 · 7·8 = USD) · product_price(제품×티어 → 가격 · 낱개 줄 = 정본 · 세트 줄 = 고정가 · 없으면 계산) · product.set_discount_pct(세트만)
     ⚠️ product_price.source 는 셋(cin7 · formula · manual) — 이 표만 · 재적재는 cin7 줄만 덮는다 · formula·manual 은 무접촉                                          (11-c 이견 3)
     ⚠️ Cin7 의 0 은 「가격 없음」 — 줄을 만들지 않는다(price > 0) · 세트는 Sellable=Yes 만 · 티어는 이름이 아니라 code 로 맞춘다 · 없는 code·다른 이름이면 멈춘다             (11-c 이견 6·8 · 11-f)
📌  직원 계정도 손님 표에 있다(Asung Employee - …) — 마케팅·매출에서 가르는 표시 ⬜(9-e)
📌  마이그레이션 파일 시각은 UTC — 손님 셋 20260922201223 · 20260923012022 · 20260923014604 · 거래 표 둘 · 가격표 · 쓰기 ① 셋(§0 · asung-workflow §4)
```

## 4. SO 거래 표 — 쓰기는 창구만 (포인터 + 함정 넷)

```
⭐⭐ at_wms_at ≠ so_reserve.released_at — 앞은 Release to WMS(소유권이 창고로 · 6-e) · 뒤는 「할당을 풀었다」(5-f). 같은 낱말을 쓰지 않은 이유가 6-a(released→at_wms)   (10-b ⬜1)
⭐⭐ so_reserve 는 풀고(released_at) → 걸기(insert) 순서 — open_line_id 는 plain unique(deferrable 아님 · customer_*_default_uq 와 다르다) · 거꾸로 짜면 23505 · 그것이 맞다    (10-b 이견 4)
⭐⭐ 검증 insert 는 번호를 직접(SO-99999t 등) — 시퀀스는 롤백되지 않는다 · 기본값은 pg_get_expr 로 읽는다 · so_number_seq.last_value 가 null 인지 본다                   (10-d)
⭐⭐ CHECK 는 null 을 통과시킨다 — 짝 CHECK 는 = 양쪽이 null 이 될 수 없게(is null · is not null · is not distinct from) · 검증 시험은 한 번에 CHECK 하나만 어기게      (⑤ · 10-b)
⚠️  so_line·so_charge → so 는 CASCADE(거래 표 「문서 → 소유 줄」) · so_reserve → so_line 은 NO ACTION(이력) — 마스터 규약의 「cascade 금지」를 거래 표에 씌우지 마라       (10-b ⬜8)
⚠️  status 는 아홉(6-a 제목의 「열」은 세면 아홉 · 정정 후보) · closed_reason 은 cancelled 에만 · merged 이면 merged_into_id 가 있어야 하고 그 반대도(⑤)                    (10-c)
```

## 4-b. ⭐⭐ SO 쓰기(①a·①b·①c) — 모르면 사고

```
⭐⭐ 표 넷은 화면이 직접 쓰지 않는다(select grant 만) — 쓰기는 security definer 창구 열 개만 · 창구 첫 줄 ims_require_write('sales') 가 유일한 문 · 하나라도 빠지면 누구나 쓴다 ⇒ 새 창구는 첫 줄 권한 + set search_path + so_require_draft   (12-b 판정 5)
     ⚠️ PO 와 다르다(PO 는 invoker + 쓰기 정책) — PO 관례를 SO 에 옮기지 마라 · 표에 insert/update grant 를 열지 마라(이중 방어가 무너진다)
⭐⭐ so_status_guard — insert 는 draft 만 · status 가 바뀌는 update 는 허락 짝(v_ok)에 없으면 전부 거부 · 지금 짝 0개 · 소유자·definer 창구도 지난다 ⇒ 전이 길을 만들 때 v_ok 에 짝을 더하는 마이그레이션이 먼저   (12-b 판정 6)
⭐⭐ unit_price null = 가격 없음(줄은 선다 · 확정 ② 가 막는다) · 0 = 무상(사람 값 · price_override true · free_reason 필수 · other 는 comments) — CHECK so_line_free_pair_ck (free_reason is not null) = (unit_price is not distinct from 0)   (12-b 판정 2)
⭐⭐ 가격은 so_price_for(티어 sale·활성 · 가격 줄 활성 · 세트 = 낱개 × pack_factor × (1 − set_discount_pct/100) round 2) → so_line_quote(so, product, qty)(할인 = greatest(손님 기본, so_deal_best 의 딜 %) · 더하지 않는다 · 큰 쪽의 출처 customer|deal) · 단가는 자르지 않고 줄 합계만 round(qty × unit_price, 2) = so_line_total 하나   (12-b 판정 3·4 · §13-g)
⭐⭐ 같은 SKU — ~~unit_price 가 같으면 합친다~~ [2026-09-23 정정 · §13 판정 2] 시스템 줄(price_override=false · discount_source <> manual)은 제품만으로 합치고 합친 수량으로 다시 견적 · 사람이 정한 줄(덮어쓴 단가 · 수동 할인)만 단가 비교(다르면 ask · p_force_new) · 붙여넣기는 첫 줄에 수량을 모은다(duplicate) · 비활성 제품은 거부 — po_lines_paste 와 다르다   (§13-g · 12-c ⬜5)
⭐⭐ 티어는 손님이 아니라 「들어온 곳」이 정한다 — 직접 오더는 손님 기본이 초깃값 · inv_config so_direct_order_tier_code(=1 Wholesale · auth_all — 누구나 바꿀 수 있다 · 경고만) ≠ 이면 direct_order_tier_unexpected · 손님 원문과 다르면 tier_differs_from_customer · 막지 않는다   (12-b 판정 B)
⭐  배송지 회사/사람 규칙 넷(so_customer_is_company) — legal_entity → 회사 · AONE → 사람 · 기본 연락처 이름이 다르고 서로 포함 안 하면 → 회사 · 그 밖 사람 · 합의된 오차(1001132194 ONTARIO INC) · 틀리면 초안에서 고친다   (12-d)
⭐  시험은 SO-25000 을 소비한다 — rollback 밖에서 so 가 비어 있을 때만 setval(25000, false) · 전환 전 점검 25000 · is_called f · 가짜 직원은 트랜잭션 안에서만(ims_staff.auth_user_id FK 없음)   (12-g)
⚠️  운임 amount 는 0 이상(①c · 돌려줄 돈은 크레딧 노트 8-g) · 비활성 손님은 거부(판정 A) · 한 트랜잭션 안 now() 는 같다 — 시각 비교로 검증하지 마라 · 제약 이름은 get stacked diagnostics constraint_name 으로   (12-b · 12-f)
```

- 표 구조 §5(so · so_line · so_charge · so_reserve · 손님 셋 5-a~5-c) · 상태와 전이 §6(6-a 상태 열 · 6-b `channel` 길 셋 warehouse·pos·counter + `intake` 유입 넷 · 6-e 소유권의 선 `Release to WMS` · 6-g′ CHECK+RPC+트리거) · 원장 접점 §7(7-b 출고 사건 `so_out` · 7-c 쓰기 경로 RPC 하나) · 인보이스·결제·크레딧 §8(8-c 묶음 · 8-e 잔액 · 8-g 크레딧 노트).
- ⚠️ `counter` ≠ WMS 의 `direct` — 이름을 바꾼 이유는 6-b(1026행) · 손님 잔액 식의 빼는 두 항(결제 배분 · 크레딧 배분 = `so_payment_alloc` · `so_credit_alloc`)은 8-e · 인보이스 묶음의 열쇠 「함께 나갔다」 AND 「같은 청구처」는 8-c(1489행 · Caleb 판정 2026-09-22).
- ⚠️ 여기 세부를 옮겨 적지 않는다 — 표가 서는 차수에서 그 절이 정본이다.

## 4-c. ⭐⭐ 할인 규칙(②-0a·②-0b) — 모르면 사고 (정본 §13)

```
⭐⭐ 줄 할인 = greatest(손님 기본 so.discount_pct, 딜 %) — 더하지 않는다(SO-10842: Red One 21% 가 7% 를 대신 · 28 아님) · 딜 판정 = 걸기 ∧ ¬빼기 ∧ 수량 기준 · ⭐ 빼기는 그 딜 줄에서만(다른 딜이 걸면 산다) · 한 줄(같은 SKU 한 줄)의 수량만(mix & match 없음)   (D2 · D5)
⭐⭐ 「왜 이 할인」은 so_line.discount_source(customer|deal|manual) + deal_line_id — 덮어쓴 줄(price_override)은 둘 다 null(짝 CHECK so_line_discount_pair_ck) · 창구를 새로 쓸 때 이 둘을 빠뜨리면 23514   (이견 5)
⭐⭐ 다시 매기기는 할인만 — 들어간 줄의 list_price 는 그대로(가격표가 바뀌어도 따라가지 않는다) · 자동 = 넣기·합치기·수량 · 수동 = so_reprice · 사람이 정한 줄(manual · override)은 어느 쪽도 건드리지 않는다 ·
     바깥 조건(order_date · price_tier · discount_pct)이 바뀌면 줄은 그대로 + so.reprice_suggested_at + 경고 reprice_suggested   (판정 3)
⭐⭐ 기간은 so.order_date 로 판정(D7) · 「오늘」= ims_today()(토론토 · current_date 는 UTC 라 저녁 8시 뒤 내일) · 세일 끝난 뒤 넣은 줄은 경고 deal_ended_before_line_added   (13-h)
⭐⭐ 오더 전체 할인(D6) — 줄 할인 뒤 제품 줄 합계에 한 번 · round(합계 × pct/100, 2) · 운임(so_charge) 제외 · so.order_discount_pct/deal_id/source 에 굳는다(deal|manual) · manual 은 자동 재계산이 덮지 않는다 · 0 = 사람이 껐다 · 지금은 손님 목록이면 자동(쿠폰 코드는 원문만)
⭐⭐ 오더 전체 딜은 so_deal.order_pct 하나 · 줄이 없다(문지기 둘) · so_deal_target 유니크는 전체 하나(nulls not distinct · 부분 유니크 금지 규칙 29) · 딜·태그 쓰기 = master RLS(거래 표 넷의 「창구만」과 다르다 — 이유 §13-e ⬜5)
⭐  케이스(case) 모드 줄은 미리 보기 화면 뒤에(D3) — Cin7 UOM Discount 25줄은 qty 모드로 옮긴다(태그 이름 GM20UOM12 = 20% · 12 이상 · 단계 할인 8개) · set_discount_pct 는 「세트 SKU 자체」 할인만(D8 · 11-c ② 뒤집힘)
⚠️  Deals Export CSV 에는 % 칸·수량 칸이 없다 — DiscountName 글자에서만(Case Discount 7줄은 못 옮긴다) · 쿠폰 코드 EXTRA10·EXTRA5 는 실재(「비어 있음」이 틀렸다) · 100% 딜 줄은 so_line_free_pair_ck 에 걸린다(⬜)   (13-b · 13-k)
```

## 4-d. ⭐⭐ 확정·할당(②a·②b) — 모르면 사고 (정본 §14)

```
⭐⭐ 확정할 때 모자란 몫은 늘 나눈다(묻지 않는다 · R1) — 원래 오더는 늘 전부 할당된 줄만(또는 통째로 hold·백오더·프리오더 — 빈 원본 없음) · 백오더 a(stock_short) · 프리오더 b(preorder) 형제는 할당 없음 · 물건이 들어와도 자동으로 잡지 않는다 · 엔진은 so_allocate_run 하나(확정·재할당·창고 바꾸기·백오더 진행이 부른다)   (14-a·14-b)
⭐⭐ 보류는 늘 오더 전체(Caleb 「보류는 특정 제품에만 한한 경우는 없어」) — so_hold 는 열린 allocated 전부를 풀고 kind hold · 줄 단위 보류 없음 · 처음부터 보류는 so_confirm(p_hold) · 풀기는 so_reallocate(모자라면 그때 나뉜다) · 「특정 제품만 나중에」는 so_divide 로 떼어 so_hold   (R3 · 이견 2)
⭐⭐ 역할 선 — 오더 담당(sales) = 초안까지 · manager 이상 = 확정부터(확정·보류·풀기·취소·창고 바꾸기·백오더 진행·나누기) · ⭐ 확정 되돌리기(so_unconfirm)는 supervisor 이상 · 창구는 ims_require_write('sales') + so_require_role 둘 다(sales 열쇠 없는 manager 는 막힌다)   (R5 · R9 · ⬜2)
⭐⭐ 되돌리기는 표시와 사슬로 먼저 거른다 — manual 형제 있으면 거부 · 대상은 stock_short·preorder ∧ 같은 시각 · 형제가 또 나뉘었으면(손자) 거부 · 그 뒤 「손대지 않았다」(열린 예약만 · 풀린 이력 무시) · ⚠️ 「같은 시각」은 다른 트랜잭션일 때만 뜻이 있다 · 돌아온 줄은 옛 예약 이력을 달고 다닌다   (14-f)
⭐  가용은 EA(so_available_many 식 한 곳 · 뷰 한 번 ~150ms) — 줄마다 so_available 을 부르지 마라(100줄 = 15초) · 세트 줄은 낱개 재고 × pack_factor(floor) · 취소는 열린 자손 전부 함께(p_keep 으로 살린다 · 그 아래도) · 미리 보기는 p_commit false(풀어야 계산되는 것은 하위 블록에서 되돌린다)   (14-c · 14-e)
⚠️  invoker 창구가 revoke 된 속 함수를 부르면 직원에게만 42501(postgres 로 재면 안 보인다) · 시험 자료를 뷰 전체에서 고르지 마라(후보 300 → 한 문장) · psql 백슬래시 줄 끝 주석 금지   (14-e · asung-workflow §4)
```

## 4-e. ⭐⭐ 출고 · 백오더 장부 · 만료(③) — 모르면 사고 (정본 §15)

```
⭐⭐ 출고는 so_ship 한 곳(속 함수 · ④⑤ 의 definer 창구가 부른다) — CAS 플립(packed→shipped)이 첫 쓰기 · 할당 닫기(shipped/released) · qty_shipped · 덜 나간 몫은 pick_short 형제(backorder) · 원장은 inv_post_sale → inv_layer_post_sale 만(SO 가 원장에 직접 쓰지 않는다)   (판정 1 · 7-c)
⭐⭐ 원장 SKU 는 낱개 — 세트 줄은 parent_product.sku · qty × pack_factor · 같은 낱개 SKU 줄은 접어 한 번 소진(재생성과 행 단위까지 같다) · 부족분은 최근 원가 레이어(sale_shortfall · hint 는 값이 근거 · id 아님)   (17번 · 15-b)
⭐⭐ bin 은 그 창고 ref_bin 에 있어야(없으면 거부) · '' 는 받는다(WMS 칸별 수량 전까지) · 비활성 칸은 받고 경고   (판정 12)
⭐⭐ 장부(so_backorder_close)는 끝난 방식만 — superseded · expired · proceeded · cancelled · 「열려 있다」는 so_reserve backorder 열린 줄 · 다시 열면 reopened_at(줄당 활성 한 줄 active_line_id)   (판정 2 · 5-g)
⭐⭐ 이어받기는 새 오더를 「확정할 때」(출하 때 아님) — 같은 손님·같은 제품 · 가족 밖 · 브랜치 무관 · 가장 오래된 줄부터 · 나머지는 더 원하지 않음 · 유상 줄만 센다 · 무상 줄 백오더는 대상에서도 뺀다   (판정 3·4·5·8·13·15)
⭐⭐ 오더는 만료로만 닫힌다(뒤처리로는 안 닫는다) — 90일(inv_config so_backorder_expire_days) · 유상 줄만 expired · 무상 줄(우리가 줄 것)은 만료도 이어받기도 안 되고 proceed·cancel 로만 끝난다 · 무상 줄이 남으면 오더도 안 닫힌다   (판정 11·16)
⭐⭐ 다시 열기(so_unconfirm · so_cancel p_reopen_superseded true)는 대상 백오더 오더가 confirmed 일 때만 — 만료·취소 뒤엔 거부(그 되돌리기·취소도 함께 거부) · so_cancel 은 이어받은 줄이 있으면 p_reopen_superseded 를 사람이 고른다(null 이면 거부)   (판정 10·11)
⭐⭐ sweep 은 cron(postgres)만 부른다(authenticated 42501) · 만료 기간은 supervisor 이상만(inv_config_guard · 잠긴 키 목록 ims_config_locked_keys · 값은 양의 정수)   (판정 14)
⭐  「입고됨」 = 백오더 뒤 그 창고에 po_in 또는 다른 창고에서 온 transfer_in(출발 줄 있고 출발 ≠ 도착 · IN_TRANSIT 제외) · 조정·반품·조립·출발 줄 없는 도착은 아니다 · notified_state unknown_pre_ims 는 「안 보냄」이 아니다(GAS 가 Cin7 에서 보낸다)   (판정 6·7 · 이견 8)
⚠️  CHECK 를 넓히면 함수 본문의 같은 값 목록도 훑어라(so_split 실사고 ③a′) · 쓰기 창구를 FROM 의 lateral 에서 부르지 마라(③a 검증 v1) · 시험은 order_date 를 과거로(시간은 못 바꾼다) · cron.sql 의 이 잡은 테스트 DB jobid 1(운영엔 함수 없음)
```

## 4-f. ⭐⭐ 세금(세금 ①·②) — 모르면 사고 (정본 §16)

```
⭐⭐ 오더의 세금은 배송지 주가 정한다(판정 2) — customer.tax_rule 은 계산에 쓰지 않는다(91% 틀림 · HST NB 2016 (Sale) 이 온타리오 손님에게) · so_copy_customer 가 복사하지 않는다 · 1-m 의 「손님에 저장한대로」는 뒤집혔다   (16-a ② · 16-b)
⭐⭐ 오더 하나에 규칙 하나(판정 8·9) — so.tax_rule_id + tax_rule(짝 CHECK so_tax_rule_pair_ck) · 제품 줄·운임 줄·오더 전체 할인 줄 전부 그 규칙 · so_line.tax_rule·so_charge.tax_rule 은 기록만(따라간다) · 줄·운임만 따로 바꾸는 길 없음(so_line_update tax_rule 열쇠 거부 · so_charge_set p_tax_rule 은 오더 규칙과 다르면 거부)
⭐⭐ 줄마다 반올림해 더한다(판정 3 · so_tax_amount = round(금액 × rate_pct/100, 2)) — 10.05 × 3줄 13% = 3.93(한 번에 3.92 아님) · 오더 전체 할인 줄도 따로(SO-10842 462.48 − 23.12 = 439.36) · rate_pct 는 퍼센트 값(13 · 5 · 0)   (16-a ③ 98.5%)
⭐⭐ 세율은 안 고친다(판정 4 · 트리거 ref_tax_rule_rate_lock · admin 도) — 세율이 바뀌면 새 규칙 + ref_tax_region 연결에 effective_from(종료일 없음 · 「그 날짜 이하 중 가장 늦은 시작일」이 답) · 인보이스가 발행일(ims_today)로 다시 골라 이름·세율·세액을 굳힌다(판정 5 · 인보이스 차수)
⭐⭐ 사람이 정한 규칙(so_header_update tax_rule 열쇠 → tax_rule_manual) — 배송지의 나라·주가 바뀌면 배송지 규칙으로 되돌리고 경고 tax_rule_reset_by_ship_to(판정 7 · 거리·도시·우편번호만 바뀌면 그대로) · tax_rule null 이면 배송지로 · 활성 sale 규칙 이름만(없는 이름·purchase·비활성 거부)
⭐⭐ 규칙이 없으면 확정 거부(so_confirm R6 · 「Order … has no tax rule」) — 초안은 경고 tax_region_unknown · so_detail warnings tax_rule_missing · 세금을 모르면 인보이스를 낼 수 없다(가격 없는 줄과 같은 이유)
⭐⭐ 캐나다인데 주를 모르면 규칙 없음 — 해외 폴백('*','*' Zero-rated)을 타지 않는다(0% 로 떨어뜨리지 않는다) · 'CA' 는 country 로 가른다(Canada 면 나라 전체 · US 면 캘리포니아 · 비면 null) · 주 표기는 표(ref_region_alias · upper(trim) · 새 실물은 행 추가 · 마이그레이션 아님)   (⬜3)
⭐  세금 규칙을 쓰는 자리는 속 함수 둘만(so_tax_refresh · so_tax_set_manual · authenticated 실행 없음) — 새 창구가 so.tax_rule 을 직접 쓰면 짝 CHECK·줄·운임이 어긋난다 · so_split 은 머리 통째 복사라 형제가 물려받는다   (16-d · 16-e)
⚠️  옛 세율 규칙 셋(HST NB 13 · NL 13 · PE 14)은 표에 기록만 · 연결 없음 · 옛 연결(NS 15)도 안 실었다(2025-03-31 로 물으면 「연결 없음」) · 매입(purchase) 연결은 없다(PO 세금 계산 없음) · 회계사 확인 거리 여섯은 16-c
```

## 4-g. ⭐⭐ 오피스 마무리 · 인보이스(ⓐ) — 모르면 사고 (정본 §17)

```
⭐⭐ 출고 + 발행은 so_finalize 한 트랜잭션(판정 1 · 사람이 누른다 — 출하 사건이 자동 발행하지 않는다) · sales(오더 담당)부터(판정 8 · R5 의 예외) · packed 만 · 하나라도 막히면 전체 거부(막힌 오더를 빼고 다시) · so_ship 은 so_finalize 가 부른다(직접 부르는 창구 없음 · 속 함수)
⭐⭐ 묶음 = 청구처(so.bill_to_customer_id · 그날 값) · 청구처의 invoice_split_by_store 가 켜졌으면 오더의 손님(매장)별 · invoice_group 으로 직원이 바꾼다(청구처 안에서만) · 한 인보이스 = 한 청구처 · 한 통화 · 오더는 살아 있는 인보이스 하나에만(active_so_id)
⭐⭐ 「손님이 뺐다」(so_line.qty_removed)는 백오더가 아니다(판정 5) — 원장 무접촉 · 할당은 so_ship 이 released · qty_ordered 는 그대로(주문 12 · 뺐다 12) · 보낼 목표 = 주문 − 뺀 것 · 그 아래 덜 나간 몫만 pick_short(형제 · 백오더)
⭐⭐ 손님이 뺀 줄만 자동 다시 견적(판정 6 · so_line_requote(…, false) · 할인만 · 시스템 줄만 · 사람이 정한 줄 무접촉) · pick_short 는 다시 견적 없음(판정 7 · 할인 그대로) · 모든 줄을 뺀 오더는 거부 + 길(WMS 되돌리기 → 취소 · 판정 9)
⭐⭐ 인보이스 금액은 보낸 수량 — round(qty_shipped × unit_price, 2)(so_line_total 은 주문 수량 · 초안까지만) · so_tax_preview(…, 'shipped') 식 한 곳 · 줄마다 반올림(§16 판정 3 · 예시는 줄 수를 함께: 3×10.05 한 줄 3.92 · 10.05 세 줄 3.93) · 오더별 세금 규칙은 so_invoice_order 에 굳는다(발행일 규칙 · manual 이면 오더 규칙)
⭐⭐ 번호 60000~(접두어 없음 · 재사용 금지 · 취소해도 남는다) · 취소·재발행은 manager(so_invoice_cancel · so_invoice_reissue) · 취소 = 문서 전체가 틀렸을 때(부분 문제는 크레딧) · 담긴 오더 invoiced→shipped · ⚠️ 결제·크레딧이 붙었으면 거부는 ⓑ·ⓒ 가 재발행해 더한다
⭐⭐ balance_forward 는 ⓑ 전에 null(0 을 넣지 마라 — 「잔액 0 을 확인했다」로 읽힌다) → ⓑ2 부터 발행이 채운다(0 이하 · 봤는데 없으면 0 · 4-h) · 기한 = 발행일 + net_days(판정 10 · 34 값 · null 이면 경고 due_date_unknown · split 이면 split_terms) · 조기결제 할인 기한은 안 찍는다
⚠️  so_detail 은 shipped·fulfilled 에서 basis shipped(보낸 수량 · 인보이스가 정본 · ⓑ2 부터 invoiced 상태 값 없음) · so_family_* 남은 수량 = 주문 − 뺀 것 − 보낸 것 · fulfilled 로 옮기는 때·발행 시점 잔액·취소 가드는 ⓑ → 4-h
```

## 4-h. ⭐⭐ 결제 · 손님 잔액 · 선결제(ⓑ) — 모르면 사고 (정본 §18)

```
⭐⭐ 권한: 넣기·붙이기·대상 오더 = ims_require_write('sales') · 떼기·취소·환불 = 거기에 so_require_role('manager') — ⚠️ 「sales」는 역할이 아니라 쓰기 열쇠(ims_role_rank 는 worker<manager<supervisor<admin · so_require_role('sales') 는 전원 거부)
⭐⭐ 잔액 계산은 so_customer_balance 하나(통화별 · received = Σpayment 남은 금액 − Σrefund · reserved_deposit = 대상 오더가 아직 열린 선결제(so_payment_is_reserved) · owed_credit 0(ⓒ) · available = received + owed − reserved) — 화면·다른 함수가 식을 다시 짜지 않는다 · 별도 잔액 표 없음 → ✅ ⓒ2 가 채웠다(4-i)
⭐⭐ 인보이스 남은 금액 = so_invoice_remaining = total − Σ활성 alloc — amount_due(= total − deposit_applied + balance_forward)는 종이에 찍힌 값일 뿐(발행 때 자동으로 붙은 것이 둘 다에 있어 amount_due − Σ 로 세면 두 번 뺀다)
⭐⭐ 붙이기 한도 셋 = 인보이스 남은 금액 · 결제 남은 금액 · 그 통화의 받아 둔 돈(환불은 집계라 특정 결제에 안 매인다) · 같은 통화끼리만 · 같은 청구처 · 활성 짝(payment, invoice)은 하나 · 붙이는 것은 so_payment_alloc_add(속) 하나
⭐⭐ 떼기 = void(행 유지 · voided_at/by/note · 생성 칸 active_invoice_id 가 비어 다시 붙일 수 있다) · 결제 취소 = status voided(활성 alloc 있으면 「먼저 떼라」 · payment 는 취소 뒤 received < 0 이면 거부) · 환불 = kind refund 한 줄(한도 received · 계좌 필수 · 기본값 없음) — 삭제 없음
⭐⭐ 발행(so_invoice_issue) 순간 자동 둘: ① 담긴 오더를 대상으로 적어 둔 선결제(so_payment_order · auto_deposit · 받은 날 순 · 남는 돈은 잔액) ② 손님 일반 잔액(auto_balance · available 한도 · 다른 오더 예약분 제외 · 인보이스만큼만) → deposit_applied · balance_forward = −②(0 이하 · 봤는데 없으면 0 · null 은 ⓑ 전) · 사람이 보낸 결제는 제안(so_payment_propose)만 하고 사람이 붙인다
⭐⭐ 취소(so_invoice_cancel): alloc 에 source manual 이 하나라도 있으면 거부(먼저 떼라 · 또는 크레딧) · auto_deposit·auto_balance 는 함께 void(void_note 「Invoice N cancelled: 사유」) → 돈은 잔액으로 · 대상 표시가 남아 재발행 때 다시 붙는다 · 떼고 취소한 결제도 일반 잔액이 되어 다음 발행 때 자동으로 쓰인다(판정 5·7)
⭐⭐ invoiced 상태 값은 없다(so_status_ck 여덟) — 발행 순간 shipped → fulfilled 곧장(closed_at 짝) · 취소 → shipped(closed_at·invoiced_at null) · 돈은 오더 끝의 조건이 아니다(Net 30 미수 정상) · invoiced_at 은 시각 칸으로 남는다
⭐  결제 계좌 후보 = is_active and (account_type = 'BANK' or code = '_5_') — ⚠️ for_payments 를 믿지 마라(_5_ 만 true · BANK 전부 false) · 기본값은 so_payment_account_default (method, warehouse_id, currency_code) 22행(판정 2 · 없는 조합 = 계좌를 요구 · admin 이 고친다) · 브랜치 = warehouse_id FK(ref_warehouse 에 code 없음)
⚠️  선수금 = 붙지 않은 결제 + 대상 오더 표시(금액 없음) · 손님에게 주는 종이는 견적서 so_proforma(읽기 · 저장 안 함 · basis ordered · received = 대상 선결제 남은 금액 · 여러 오더 대상 결제는 남은 금액 전부 — 짐작) · AONE 오더는 method shopify 로 결제된 채 들어온다(유입 차수)
⚠️  검증 시험 자료: 인보이스는 postgres 직접 insert(CHECK 여덟 만족) · 오더는 창구로 만들고 shipped/packed 만 replica 로 · 같은 트랜잭션의 같은 날 결제는 순서가 id 로 갈린다 — 예상은 집합·합으로 · 앞 절이 남긴 상태(떼고 푼 결제)를 따라가라
```

## 4-i. ⭐⭐ 크레딧 노트 · 반품 재고 · 리스탁킹 피(ⓒ) — 모르면 사고 (정본 §19)

```
⭐⭐ 권한: 발행·취소 = manager(so_credit_issue · so_credit_cancel · 판정 3) · 붙이기 = sales(so_credit_attach) · 떼기 = manager(so_credit_detach) · 환불에 쓰인 몫은 떼지 못한다(환불을 취소 so_payment_void)
⭐⭐ 원본은 둘 중 하나(짝 CHECK) — IMS invoice_id(issued 만) 또는 Cin7 cin7_invoice_number(종이) + cin7_order_number(되짚기 열쇠 · SO-…) · Cin7 크레딧은 tax_rule 명시 · 줄은 sku·수량·단가 손으로(판정 6)
⭐⭐ IMS 크레딧 줄은 so_invoice_line 을 가리킨다 — 단가·계정은 그 줄 · 세율은 그 줄의 인보이스 오더 rate_pct 를 줄에 굳힌다(0-11) · Σ반품(활성 크레딧) + 이번 ≤ 인보이스 줄 qty 아니면 거부(과다 반품)
⭐⭐ 갈리는 것은 「재고가 움직이냐」 — 줄에 restock_bin_id 가 있으면 원장 credit_in(그 칸 · EA · 낱개 SKU) · 없으면 not_restocked_reason(damaged · b_grade · not_returned · other) · 칸 기본 ims_last_bin(그 창고) → 없으면 사람이 · '' 불허 · B급 칸이 서면 칸 표시만 더한다
⭐⭐ 원가 = 원 판매 소비 기록 복원(return_restore · 열쇠 = 오더 번호 · IMS 는 so_line → so.so_number · Cin7 은 cin7_order_number) → 남은 레이어 가중평균 → 최근 원가(17-e) → unknown · 실시간·재생성이 inv_layer_post_credit 하나를 부른다(17-f) · raw.cost.remainder 가 hint
⭐⭐ 리스탁킹 피는 알림만(판정 5 · 자동 금지) — 원 인보이스 발행일 + 60일이 지나면 restock_fee_window:N + fee_suggested · 넣으면 kind restocking_fee 한 줄(≤ 0 · 20% 미리 채움 · % 바꿈 · 세금도 음수) · 계정은 지정 → 설정(so_credit_restock_fee_account_code · 지금 빈 값) → 거부(판정 7) · 60·20 은 잠금 키
⭐⭐ 취소는 돌아온 재고가 안 팔렸을 때만 — 활성 so_credit_alloc 없음 ∧ 그 크레딧 레이어 소진 0 → 반대 credit_in(:reversal) + reason reversal 전량 소진 · 팔렸으면 거부(재고 조정 + 새 크레딧) · 번호 남음
⭐⭐ 발행 순서 = ① 대상 선결제 → ② 크레딧(발행일 순 · auto) → ③ 받아 둔 돈(received − reserved) · balance_forward = −(② + ③) 한 줄 · so_invoice.credit_applied 는 ② 몫 · 취소는 auto 크레딧을 풀고 manual 이면 거부(판정 7 규칙)
⭐⭐ 환불은 크레딧부터 — 한도 received + owed_credit · so_credit_alloc.refund_payment_id · received 는 크레딧이 갚은 몫만큼 안 준다 · 환불 취소가 그 몫을 함께 void
⭐  남은 금액(so_invoice_remaining) = total − 결제 붙임 − 크레딧 붙임 · 잔액 owed_credit = Σissued total − Σ활성 alloc(인보이스·환불) · 식은 so_customer_balance 하나
⚠️  inv_layer_apply_done 은 inv_layer_apply 가 만드는 임시 표 — 보조 함수에서 스키마 접두를 붙이지 마라(2026-09-25 실사고 · 1차 실행 실패) · 한 크레딧에 같은 SKU 가 다른 원 판매에서 오면 첫 줄의 판매로 되짚고 경고 mixed_origin_sales
```

## 4-j. ⭐⭐ POS · counter · 오더 병합(④) — 모르면 사고 (정본 §20 · §21)

```
⭐⭐ 보관용은 칸이 아니라 **SKU × 칸 짝**(product_bin_overflow) — ⚠️ 이름에 reserve 를 쓰지 마라(so_reserve 가 「할당」이다) · 켜기·끄기는 receiving 열쇠(매니저로 좁히지 않는다) · 순서만 바꾸고 막지 않는다 · 칸이 비어도 표시는 남는다   (§20 판정 2·3)
⭐⭐ 칸 계획 so_pick_plan — 재고 있는 평소 칸 → 재고 있는 보관용 칸 → 모자란 몫은 첫 후보 칸(재고 0 이어도 · 없으면 '') · 세트 줄은 **정수 세트 단위**로만 나눈다 · short_ea = **창고 전체 부족분**(원장 부족분 레이어와 같은 몫 · 칸 하나가 모자란 것이 아니다)   (판정 1·4 · 고침 ①)
⭐⭐ POS·counter 는 **재고를 보지 않고 전 줄 allocated** — 백오더·이어받기·나누기·보류가 없다(so_allocate_run·so_hold·so_divide 에 길 가드 · ⚠️ 가드가 없던 판이 pos 오더를 갈랐다) · 픽은 목표와 같아야 한다(pick_short 없음) · POS 의 Confirm·다시 열기·Finish = sales(R5 의 두 번째 예외) · counter = manager   (판정 6·12·13 · 20-c)
⭐⭐ Finish 는 **막지 않는다** — 받은 금액·미수를 보이고 남은 몫은 그 인보이스의 미수 · 미리 보기 식은 발행 ①②③ 과 **같아야 한다**(검증이 「미리 보기 = 발행 뒤 값」으로 묶는다)   (판정 5 · 0-8)
⭐⭐ 「재고 없이 나갔다」는 새 표가 아니다 — 원장의 sale_shortfall 레이어를 so_stock_short_list 가 읽고, 매니저 확인만 so_stock_short_check 에 적는다 · ⚠️⚠️ **열쇠는 (doc_number, sku, warehouse)** — 레이어 id 는 inv_layer_apply 재생성이 바꾼다(실측 494928 → 504446) · 확인 권한 = manager + (sales ∨ receiving) · 되돌리기 없음   (판정 7 · 0-10·0-11)
⭐⭐ 병합 — 원본이 전부 초안이면 sales · 하나라도 확정이면 manager · 같은 손님·창고·통화 · **channel warehouse 만** · 주문일은 **합친 날**(ims_today) · 줄은 전부 manual(deal_line_id null) · tax_rule 은 합친 오더의 규칙 · 운임은 **안 옮긴다**(charges_not_merged) · 선결제 대상은 옮긴다 · 되돌리기 없음(떼어 낸다)   (§21 판정 3·4·5·6·8)
⭐⭐ **병합 오더의 확정은 원본의 백오더 형제를 이어받지 않는다**(so_merge_chain_reaches — split 조상 전부에서 merged_into_id 사슬) ⇒ ⚠️ 한 손님·한 제품의 열린 백오더가 **두 줄**인 것이 정상인 경우가 있다(§15 판정 5 의 병합 예외 · 다음 오더가 오래된 줄부터 닫아 수요는 한 번만 센다)   (§21 판정 1 · 0-1·0-2)
⭐  병합 줄 모으기 열쇠 아홉(제품·단가·정가·할인%·무상 사유·override·부가 셋)이 **전부 같을 때만** 한 줄 — tax_rule 은 열쇠 밖 · 합친 오더 머리는 so_split 식 통째 복사(so_create 를 거치면 티어·오더 전체 할인이 손님 기본으로 되돌아간다)   (고침 ① · ⬜2)
⚠️  백오더 오더를 합치면 장부 end_kind **'merged'**(cancelled 로 적으면 백오더 화면이 취소로 센다) · 원본이 이어받은 남의 줄은 다시 열되 대상이 confirmed 일 때만(아니면 경고 superseded_not_reopenable) · 프리오더였던 줄은 표시가 없다(경고 preorder_lines_need_reflag)   (0-4·0-5·0-7)
```

## 4-k. ⭐⭐ 읽기 창구 · 오피스 화면 — 모르면 사고 (정본 §22 · §23)

```
⭐⭐ 남은 금액은 세 함수뿐 — so_invoice_remaining · so_payment_remaining · so_credit_remaining · DB 에 복사 식 0(남은 하나 so_credit_prepare.qty_credited = so_credit_issue 와 같은 식 ⬜ · 다르면 화면은 된다는데 창구가 거부)
⭐⭐ 환불은 붙일 돈이 아니다 — so_payment_remaining 이 null · 환불 줄은 두 칸(refund_credit_covered · refund_from_account) · held_for_orders 는 boolean(금액은 손님 잔액 reserved_deposit)
⭐  목록은 뷰(so_invoice_list · so_payment_list · so_credit_list · security_invoker · select 만 — Supabase 기본 ALL 을 걷었다) · 한 장은 RPC jsonb · so_credit_detail 은 키를 더하기만(옛 키 아홉 그대로) · issue_contract(크레딧 발행 입력 모양)는 정본 §22-c
⭐⭐ 화면은 DB 값을 그리기만 · 세트는 기본 숨김(케이스도 낱개 × 수량 · Include sets 는 manager) · Proceed 는 기다려 주지 않는다(잡힐 것 없으면 막힘) · POS 매장은 기기 localStorage(CLAUDE.md §5 예외)
⚠️  Manager List 의 즉시 결제 = ref_payment_term.net_days 0 — 손님 결제조건 자료만큼만 정확(Net30 6,305 정리 전) · Unpaid 탭은 브랜치로 못 거른다(뷰에 창고 칸 ⬜)
```

## 5. 이 스킬을 갱신할 때

- 새 사실은 **정본(§9~§12)에 먼저**, 여기에는 「모르면 사고가 나는 것」만 한 줄 · 실측 숫자·행 수·역사는 두지 않는다(정본 9-g · 9-j 가 갖고 있다).
- `description` 은 1024자(pre-commit `scripts/check-skill-desc.sh`). 줄일 때 표 이름·함정 키워드보다 일반어를 먼저 뺀다 · `asung-po` 와 겹치는 키워드(supplier · ims_touch · 마스터 데이터)는 넣지 않는다.
- 옛 문장은 `~~취소선~~ + [정정 날짜]` — 경위가 정본에 있으면 포인터로 대신한다.
