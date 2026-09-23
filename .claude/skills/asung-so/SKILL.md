---
name: asung-so
description: >
  Asung Trading IMS 의 SO(판매) 모듈 — Cin7 Core 판매 오더·손님을 대체하는 네 번째 모듈. 손님 표 셋을
  읽거나 적재하거나 SO 거래 표를 설계·만들 때 먼저 읽으세요.
  "SO 모듈", "판매 오더", "세일즈 오더", "customer", "customer_address", "customer_contact", "손님 표", "손님 적재",
  "ImsLoadCustomer", "CustomerProbe", "MarketingConsent", "마케팅 동의", "CASL", "DefaultForType", "기본 주소", "기본 배송지",
  "청구지", "Shipping", "Billing", "Business", "parent_id", "부모 손님", "IsBillParent", "job_title", "so.status", "so.intake",
  "Release to WMS", "at_wms", "so_out", "credit_in", "so_invoice", "so_payment_alloc", "so_credit_alloc", "재적재", "내리기",
  "deferrable", "so-module.md"
  가 나오면 추측하지 말고 이 스킬과 정본 docs/design/so-module.md 를 확인하세요.
  ⚠️MarketingConsent 는 숫자다(2 Opt in · 3 Opt out · 0·1 둘 다 Unknown) — 순서·소거 추론으로 옮기지 마라,
  ⚠️재적재는 내리기 → upsert 순서(upsert 먼저면 Cin7 에서 지워진 옛 기본이 새 기본을 23505 로 막는다),
  ⚠️적재는 id·parent_id·note·default_*·label 을 보내지 않는다(null 로 보내는 것과 다르다),
  ⚠️「기본 하나」 유니크는 deferrable — 한 손님의 주소·연락처는 한 요청에 모아 보낸다,
  ⚠️SO 거래 표(so·so_line·so_charge·so_reserve)는 읽기만 — 쓰기 RPC·전이 트리거는 아직 없다 · 함수 이름은 9-b 규칙만.
---

# Asung SO(판매) 모듈 스킬

⭐ **설계 정본 `docs/design/so-module.md`** — 여기는 「모르면 사고가 나는 것」과 포인터만. 이 스킬과 정본이 어긋나면 **정본이 맞다**(정본 §9 = 9-a~9-j).
관련 스킬: `asung-po`(마스터·관계 표 규약 — 손님 셋이 그대로 따른다) · `asung-inv-ledger`(출고 사건 `so_out`) · `asung-wms`(Release to WMS 이후) · `cin7-api`(`references/customer.md`) · `asung-apps-script`(적재 스크립트 규칙 6).

## 0. 어디까지 왔나

```
손님 표 셋      ✅ 2026-09-22 — 마이그레이션 ① customer · customer_address · customer_contact(9-a~9-f) · ② job_title(9-g·9-h) · ③ 기본 하나 유니크 deferrable(9-i)
손님 첫 적재    ✅ 2026-09-22 — docs/probes/ImsLoadCustomer.gs · ⚠️ 테스트 DB(Asung-IMS)만 · 실측은 9-j
가격표          ✅ 2026-09-23 — 20260923154749(ref_price_tier 8행 · product_price · product.set_discount_pct) · 첫 적재 76,872줄 · docs/probes/ImsLoadPrice.gs · 테스트 DB(11-e · 11-g)
SO 거래 표      ✅ 2026-09-23 — 마이그레이션 ④ 20260923133042(so · so_line · so_charge · so_reserve · 시퀀스 SO-25000~) · ⑤ 20260923134840(so_merge_reason_ck 양방향) · ⚠️ 읽기만 · 테스트 DB · 전이·RPC 는 다음(§10)
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
     주소·연락처는 관계 표(DELETE 열림 · 그래도 적재는 지우지 않고 내린다) · 쓰기 묶음 ims_can_write('master') · 트리거 <t>_touch → ims_touch()   (9-a ①②)
⭐  「하나뿐」은 생성 칸 + 전체 유니크(default_customer_id) — 부분 유니크 인덱스 금지(asung-wms 규칙 29 · PostgREST on_conflict)          (5-b · 5-c · 9-i ⑪)
⭐  주소 칸 낱말 state_province · postal_code(ref_warehouse · supplier_address 와 같다 · 5-b 본문의 state·postcode 는 뒤집힘 — 9-d 표가 이력)
⭐  낱말 충돌 — so.status(오더 상태 · 6-a) ≠ customer 의 Cin7 Status(→ is_active) · so.intake(유입 넷 · 6-b · 처음 이름 source) ≠ source(cin7|manual · 어느 시스템이 만들었나) ·
     released → at_wms(6-a)                                                                                              (9-a ① · 6-a · 6-b)
⭐  이름 규칙(판정 ⑤) — 표 so_invoice · so_invoice_order · so_payment · so_payment_alloc · so_credit · so_credit_line · so_credit_alloc ·
     함수 so_<동작> · so_invoice_<동작> · so_payment_<동작> · so_credit_<동작> · 읽기 _detail/_list · 손님 셋은 앞머리 없음(supplier·product 처럼) ·
     ⚠️ 실제 이름은 각 차수의 지시서가 이 규칙으로 붙인다 — 지금 목록을 만들지 마라                                          (9-b)
⭐  FK+원문 짝 — currency_id+currency_code · payment_term_id+_name · default_location_id+_name(ref_warehouse.name 매칭) · ar/sale_account_id+_code ·
     tax_rule 은 원문만(ref_tax_rule 미결 — 인보이스 전에 서야 한다) · price_tier 원문 옆에 FK 붙이기는 다음(⭐ ref_price_tier 는 섰다 · §11 · 2026-09-23)        (9-c ⬜2·⬜3 · 9-d · 11-f)
⭐  가격표(§11) — ref_price_tier 여덟 행(code 1~8 · purpose sale·compare·reference · currency_id FK 하나 · 7·8 = USD) · product_price(제품×티어 → 가격 · 낱개 줄 = 정본 · 세트 줄 = 고정가 · 없으면 계산) · product.set_discount_pct(세트만)
     ⚠️ product_price.source 는 셋(cin7 · formula · manual) — 이 표만 · 재적재는 cin7 줄만 덮는다 · formula·manual 은 무접촉                                          (11-c 이견 3)
     ⚠️ Cin7 의 0 은 「가격 없음」 — 줄을 만들지 않는다(price > 0) · 세트는 Sellable=Yes 만 · 티어는 이름이 아니라 code 로 맞춘다 · 없는 code·다른 이름이면 멈춘다             (11-c 이견 6·8 · 11-f)
📌  직원 계정도 손님 표에 있다(Asung Employee - …) — 마케팅·매출에서 가르는 표시 ⬜(9-e)
📌  마이그레이션 파일 시각은 UTC — 앞 파일 셋 20260922201223 · 20260923012022 · 20260923014604(asung-workflow §4)
```

## 4. SO 거래 표 — 표 있음 · 쓰기 없음 (포인터 + 함정 넷)

```
⭐⭐ at_wms_at ≠ so_reserve.released_at — 앞은 Release to WMS(소유권이 창고로 · 6-e) · 뒤는 「할당을 풀었다」(5-f). 같은 낱말을 쓰지 않은 이유가 6-a(released→at_wms)   (10-b ⬜1)
⭐⭐ so_reserve 는 풀고(released_at) → 걸기(insert) 순서 — open_line_id 는 plain unique(deferrable 아님 · customer_*_default_uq 와 다르다) · 거꾸로 짜면 23505 · 그것이 맞다    (10-b 이견 4)
⭐⭐ 검증 insert 는 번호를 직접(SO-99999t 등) — 시퀀스는 롤백되지 않는다 · 기본값은 pg_get_expr 로 읽는다 · so_number_seq.last_value 가 null 인지 본다                   (10-d)
⭐⭐ CHECK 는 null 을 통과시킨다 — 짝 CHECK 는 = 양쪽이 null 이 될 수 없게(is null · is not null · is not distinct from) · 검증 시험은 한 번에 CHECK 하나만 어기게      (⑤ · 10-b)
⚠️  so_line·so_charge → so 는 CASCADE(거래 표 「문서 → 소유 줄」) · so_reserve → so_line 은 NO ACTION(이력) — 마스터 규약의 「cascade 금지」를 거래 표에 씌우지 마라       (10-b ⬜8)
⚠️  status 는 아홉(6-a 제목의 「열」은 세면 아홉 · 정정 후보) · closed_reason 은 cancelled 에만 · merged 이면 merged_into_id 가 있어야 하고 그 반대도(⑤)                    (10-c)
```

- 표 구조 §5(so · so_line · so_charge · so_reserve · 손님 셋 5-a~5-c) · 상태와 전이 §6(6-a 상태 열 · 6-b `channel` 길 셋 warehouse·pos·counter + `intake` 유입 넷 · 6-e 소유권의 선 `Release to WMS` · 6-g′ CHECK+RPC+트리거) · 원장 접점 §7(7-b 출고 사건 `so_out` · 7-c 쓰기 경로 RPC 하나) · 인보이스·결제·크레딧 §8(8-c 묶음 · 8-e 잔액 · 8-g 크레딧 노트).
- ⚠️ `counter` ≠ WMS 의 `direct` — 이름을 바꾼 이유는 6-b(1026행) · 손님 잔액 식의 빼는 두 항(결제 배분 · 크레딧 배분 = `so_payment_alloc` · `so_credit_alloc`)은 8-e · 인보이스 묶음의 열쇠 「함께 나갔다」 AND 「같은 청구처」는 8-c(1489행 · Caleb 판정 2026-09-22).
- ⚠️ 여기 세부를 옮겨 적지 않는다 — 표가 서는 차수에서 그 절이 정본이다.

## 5. 이 스킬을 갱신할 때

- 새 사실은 **정본 §9 에 먼저**, 여기에는 「모르면 사고가 나는 것」만 한 줄 · 실측 숫자·행 수·역사는 두지 않는다(정본 9-g · 9-j 가 갖고 있다).
- `description` 은 1024자(pre-commit `scripts/check-skill-desc.sh`). 줄일 때 표 이름·함정 키워드보다 일반어를 먼저 뺀다 · `asung-po` 와 겹치는 키워드(supplier · ims_touch · 마스터 데이터)는 넣지 않는다.
- 옛 문장은 `~~취소선~~ + [정정 날짜]` — 경위가 정본에 있으면 포인터로 대신한다.
