-- SO 모듈 마이그레이션 ① — 손님 표 셋 신설: customer · customer_address · customer_contact (2026-09-22)
--
-- 목표: 마이그레이션 1개 · 표 3개 · ⭐ 행 적재 0건 · 뼈대만. 적재 GAS 는 다음 차수(supplier 20260912202952 와 같은 순서).
-- 선행: 20260911161647(ref_payment_term) · 162906(ref_account) · 164513(ref_currency) · 165946(ref_warehouse) · 20260917230000(ims_can_write · ims_staff) ·
--       20260918133858(ims_touch · updated_by 규약). ⚠️ ims_touch() · ims_can_write(text) · set_updated_at() 은 여기서 다시 만들지 않는다(마지막 정의 확인 · 이름·시그니처만 씀).
-- 정본: docs/design/so-module.md §5-a~5-c(칸·근거) · §9(이번 차수의 판정 · 뒤집은 것 표) · docs/design/po-module.md §5(공통 규약) · §7-b(supplier 선례).
--       이 파일과 정본이 어긋나면 정본이 이긴다. 지시서 ~/asung/prompts/so-mig-1-customer.md · 검토 이견 1~8 · ⬜1~6 은 Caleb 판정(2026-09-22 저녁)대로.
--
-- ═══ 이름 — 앞머리 없음 (so-module §9-b · 판정 ⑤) ═══
--   customer · customer_address · customer_contact — supplier · product 처럼 모듈 공용 마스터라 so_ 를 붙이지 않는다(거래 표 so · so_line … 와 갈린다).
--   ⚠️ 파일 이름도 supplier 와 같이 <시각>_customer.sql (검토 이견 1).
--
-- ═══ 실측 근거 (2026-09-21 GAS 프로브 GET /customer?Page=1&Limit=1 · so-module §1-s · 손님 하나) ═══
--   Total 9,452 — PostgREST 1,000행 한도를 넘는다 · 적재는 페이지네이션(ref_bin 2,675 선례).
--   우리가 손님에 붙기로 정한 여섯이 전부 실재: Currency · PaymentTerm · Discount · TaxRule · PriceTier · Location.
--   Addresses[]: Type(Shipping·Billing) · DefaultForType · Line1/2 · City · State · Postcode · Country · Contacts[]: Default · IncludeInEmail · MarketingConsent · Phone · Mobile · Email · Website.
--   ⚠️ 프로브가 손님 하나라 값의 분포(Status 어휘 · Type 어휘 · DefaultForType 체크율 · 하위 ID 유무)는 모른다 — 적재 첫 회에 센다(§9-e).
--   Cin7 손님 화면 실측(Caleb 2026-09-22): 주소 TYPE 선택지는 Billing · Business · Shipping 셋(그 밖은 고를 수 없다) · 연락처 화면에 JOB TITLE · FAX · COMMENT 칸.
--   공급처 API 키(cin7-api references/supplier.md 101행): Address 키에 ID · Contact 키에 Fax · Comment · ID 있음 · JobTitle 없음 ⇒ 손님도 같은 응답 가족으로 본다(짐작 · 적재 첫 페이지에서 키 목록을 그대로 센다).
--
-- ═══ 설계 판단 (Caleb 확정 2026-09-22 · so-module §9-a) ═══
--   ① customer 는 PO 마스터 규약 그대로 — 공통 8칸 · Cin7 Status → is_active(so.status 와 한 모듈에서 두 뜻이 되는 것을 피한다 · released→at_wms 와 같은 종류) ·
--      Cin7 Comments → cin7_comments(우리 note 와 섞지 않는다 · 재적재가 우리가 적은 말을 덮는다 · supplier 선례) · 재적재는 po-module §3-f 한 규칙(upsert + 이번에 안 들어온 source='cin7' 은 is_active=false).
--   ② customer_address · customer_contact 는 관계 표 규약 — 공통 7칸(name 없음) · cin7_id unique nullable(늘 null 이어도 둔다 · supplier_discount 「규약대로」) · DELETE 연다 · TRUNCATE 막는다.
--   ③ is_default_for_type 은 받되 빈 곳은 규칙으로 메운다(체크된 것은 믿는다 · 없고 그 type 이 하나면 그것 · 여럿이면 비워 두고 사람이) — 확정은 적재 첫 회에 센 뒤. ⚠️ supplier 는 DefaultForType 을 버렸다(체크율이 실태와 달랐다) — 손님은 표 모양을 5-b 그대로 두고 첫 회 분포로 판정한다.
--      ⭐ Business 는 배송지·청구지 기본값 찾기에 쓰지 않는다.
--   ④ 연락처 is_default · include_in_email · marketing_consent 는 받아 두고 메일 기능 전까지 아무것도 기대지 않는다 — 어느 칸이 수신처인지는 메일 절에서 실물로.
--      ⭐ marketing_consent 는 nullable · 기본값 없음(true 동의 · false 안 함 · null 모름 — IMS 에서 새로 만든 연락처) · 보낼 때 null 은 false 와 똑같이 다룬다(CASL · 확인된 동의에만).
--   ⬜1 쓰기 묶음 master(ims_perm_catalog 가 JSON 리터럴이라 새 묶음은 마이그레이션 — sales 묶음은 SO 거래 표 차수에서) · ⬜2 tax_rule · price_tier 는 원문만(ref_tax_rule 미결 · ref_price_tier 없음 · 생기면 FK 칸을 옆에) ·
--   ⬜3 default_location 은 FK+원문(ref_warehouse · Cin7 은 이름으로 준다) · ⬜4 주소 칸 이름은 ref_warehouse·supplier_address·po 머리와 같은 낱말 state_province · postal_code ·
--   ⬜5 fax · cin7_comment 는 만든다 · job_title 은 만들지 않는다(API 에 없다) · 이견 3 currency 는 FK+원문(currency_id + currency_code · PO·SO 가 ref_currency 를 공용 · 원문은 첫 회 검산용 — FK 가 비는 손님 수가 기대값 0).
--   ⚠️ NOT NULL 은 name · is_active · source · 시각 · FK NOT NULL(customer_id) · bool 기본값 칸에만 — Cin7 화면 필수 축이라도 원문 칸에 NOT NULL 을 걸지 않는다(supplier 와 다르다: 그쪽은 226/226 실측이 있었고 여기는 손님 하나) · 적재가 도중에 멈추지 않게.
--   ⚠️ customer.name 에 유니크를 걸지 않는다(5-a · product 576종 중복 선례 · 손님은 GUID cin7_id 가 열쇠라 이름이 열쇠 노릇을 할 필요가 없다 — supplier 와 다른 자리).
--   ⚠️ 부분 유니크 인덱스 금지(asung-wms 규칙 29 · PostgREST on_conflict) — 「하나뿐」은 생성 칸 + 전체 유니크로(5-b · 5-c · 5-f 와 같은 장치).
--
-- ═══ 공통 규약 확인 (po-module §5 · 20260917235000 · 20260918133858 과 동일한 모양) ═══
--   id uuid PK · cin7_id uuid unique plain · source check <표>_source_ck · FK on delete no action(cascade 금지) · FK 칸마다 인덱스 <표>_<칸>_idx · updated_by → ims_staff(id) + <표>_updated_by_idx ·
--   트리거 <표>_touch before update → ims_touch()(다시 만들지 않는다) · RLS select 열림 + insert/update/(delete) = (select ims_can_write('master')) · 정책 이름 <표>_<동사> ·
--   revoke all from anon · 마스터는 revoke delete, truncate(정책 셋) · 관계 표는 revoke truncate 만(정책 넷).

-- ═══ ① customer — 손님 마스터 ═══
create table if not exists public.customer (
  id                           uuid primary key default gen_random_uuid(),
  cin7_id                      uuid unique,
  name                         text not null,
  display_name                 text,
  is_active                    boolean not null default true,
  source                       text not null default 'cin7',
  note                         text,
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now(),
  updated_by                   uuid references public.ims_staff (id) on delete no action,
  -- 오더로 따라가는 설정(5-a) — FK + 원문 · 원문에도 NOT NULL 없음(적재가 멈추지 않게)
  currency_id                  uuid references public.ref_currency (id) on delete no action,
  currency_code                text,
  payment_term_id              uuid references public.ref_payment_term (id) on delete no action,
  payment_term_name            text,
  discount_pct                 numeric,
  tax_rule                     text,
  price_tier                   text,
  default_location_id          uuid references public.ref_warehouse (id) on delete no action,
  default_location_name        text,
  -- 계정(5-a) — FK + 원문(code)
  ar_account_id                uuid references public.ref_account (id) on delete no action,
  ar_account_code              text,
  sale_account_id              uuid references public.ref_account (id) on delete no action,
  sale_account_code            text,
  -- 계층(5-a · §2-m 정정) — 연결 축만 · 상속 없음
  parent_id                    uuid references public.customer (id) on delete no action,
  is_bill_parent               boolean not null default false,
  is_legal_entity              boolean not null default false,
  default_ship_to_customer_id  uuid references public.customer (id) on delete no action,
  default_bill_to_customer_id  uuid references public.customer (id) on delete no action,
  -- 그 밖(5-a)
  default_carrier              text,
  tax_number                   text,
  tags                         text,
  cin7_comments                text,
  constraint customer_source_ck check (source in ('cin7','manual'))
);
create index if not exists customer_updated_by_idx               on public.customer (updated_by);
create index if not exists customer_currency_idx                 on public.customer (currency_id);
create index if not exists customer_payment_term_idx             on public.customer (payment_term_id);
create index if not exists customer_default_location_idx         on public.customer (default_location_id);
create index if not exists customer_ar_account_idx               on public.customer (ar_account_id);
create index if not exists customer_sale_account_idx             on public.customer (sale_account_id);
create index if not exists customer_parent_idx                   on public.customer (parent_id);
create index if not exists customer_default_ship_to_customer_idx on public.customer (default_ship_to_customer_id);
create index if not exists customer_default_bill_to_customer_idx on public.customer (default_bill_to_customer_id);

comment on table  public.customer is 'SO 모듈 손님 마스터(Cin7 GET /customer 대응 · 9,452명 · 우리 키 id · cin7_id 는 매핑·적재 열쇠) · ⚠️ 앞머리 없음 — supplier·product 처럼 모듈 공용 마스터 · Cin7 Status 는 is_active 로 · Comments 는 cin7_comments 로 · 재적재는 po-module §3-f 한 규칙(upsert + 안 들어온 cin7 행은 is_active=false) · DELETE·TRUNCATE 막음(오더·인보이스·원장이 가리키는 마스터) · 정본 docs/design/so-module.md §5-a · §9 · 2026-09-22 신설';
comment on column public.customer.cin7_id                     is 'Cin7 customer.ID(GUID) · unique plain(nullable — manual 손님) · ⭐ 적재 열쇠(upsert on_conflict=cin7_id) · Cin7 은 손님을 GUID 로 참조하므로 이름 정규화가 필요 없다';
comment on column public.customer.name                        is 'Cin7 Name 원문 · NOT NULL(부분 객체를 첫 요청에서 세우는 제약 · po-module §5) · ⚠️ 유니크 없음 — product 576종 중복 선례 · 손님 이름 중복은 미측정 · 열쇠는 cin7_id';
comment on column public.customer.display_name                is 'Cin7 DisplayName 원문';
comment on column public.customer.is_active                   is '⭐ Cin7 Status 를 여기로 받는다(판정 ① · so.status 와 한 모듈에서 두 뜻이 되는 것을 피한다). ⬜ Cin7 Status 어휘가 둘뿐인지 모른다 — 적재 첫 회에 distinct 를 세고 셋 이상이면 그때 원문 칸을 옆에 더한다(지금 만들지 않는다). 재적재에 안 들어온 cin7 행은 false 로 물러난다';
comment on column public.customer.source                      is 'cin7 = 적재가 덮어도 되는 행 · manual = 우리가 만든 행(재적재 무접촉) · CHECK customer_source_ck';
comment on column public.customer.note                        is '우리가 적는 메모. ⚠️ Cin7 재적재가 덮지 않는다 — Cin7 원문은 cin7_comments';
comment on column public.customer.updated_by                  is '마지막으로 고친 사람 → ims_staff(id) · customer_touch(ims_touch) 가 auth.uid() 로 채운다(화면이 주지 않는다 · anon key 공개) · null = 아직 안 고쳤거나 service_role 적재(system) · 인덱스 customer_updated_by_idx';
comment on column public.customer.currency_id                 is 'FK → ref_currency(id) · nullable · on delete no action · 인덱스 customer_currency_idx. PO·SO 가 ref_currency(CAD·USD)를 공용한다(Caleb: 판매도 CAD·USD) · 원문(currency_code)을 code 로 매칭해 채운다. ⚠️ FK 가 비는 손님 수 = ref_currency 에 없는 통화 — 첫 회 기대값 0(검토 이견 3 채택 · 5-a 「원문 하나」를 뒤집었다 · §9-d)';
comment on column public.customer.currency_code               is 'Cin7 Currency 원문(예 CAD) · 첫 회 검산용 · FK 가 못 붙어도 원래 값이 남는다';
comment on column public.customer.payment_term_id             is 'FK → ref_payment_term(id) · nullable · 인덱스 customer_payment_term_idx · 원문(payment_term_name)을 이름으로 매칭(supplier 와 같은 자리 · ref_payment_term 은 PO 와 공용 · §4)';
comment on column public.customer.payment_term_name           is 'Cin7 PaymentTerm 원문(예 C.B.S (Cash Before Shipment)) · FK 가 못 붙어도 여기는 남는다 · ⚠️ NOT NULL 없음(손님 하나 프로브 — 226/226 실측이 있던 supplier 와 다르다)';
comment on column public.customer.discount_pct                is 'Cin7 Discount 원문(%) · 손님 할인 하나(§1-k · PO 의 체인 할인과 다르다 · §4) · 오더 머리로 복사된다(5-d)';
comment on column public.customer.tax_rule                    is 'Cin7 TaxRule 원문(예 GST (Sale)) · ⚠️ 원문만 — ref_tax_rule 은 미결(po-module §7 갈림길) · 생기면 FK 칸을 옆에 붙인다(⬜2) · ⚠️ 인보이스(§8) 전에 서야 한다 · 5-a 「FK+원문 다섯」 중 하나를 원문만으로 시작(§9-d)';
comment on column public.customer.price_tier                  is 'Cin7 PriceTier 원문(예 AONE) · ⚠️ 원문만 — ref_price_tier 는 어디에도 없다(grep 0) · 생기면 FK 칸을 옆에(⬜2) · 오더 가격 계산(§1-j · 5-e list_price) 전에 서야 한다';
comment on column public.customer.default_location_id         is 'FK → ref_warehouse(id) · nullable · 인덱스 customer_default_location_idx · Cin7 Location(이름 · 예 Asung Trading Inc.)을 ref_warehouse.name 으로 매칭(⬜3) · 창고 제안값일 뿐 — ⚠️ 라우팅을 자동으로 하지 않는다(§1-i · 5-a) · so.location 도 같은 짝(FK+원문)이어야 한다(§9-d · so 표는 다음 차수)';
comment on column public.customer.default_location_name       is 'Cin7 Location 원문 · FK 가 못 붙어도 남는다';
comment on column public.customer.ar_account_id               is 'FK → ref_account(id) · nullable · 인덱스 customer_ar_account_idx · Cin7 AccountReceivable(code · 예 _61_)을 ref_account.code 로 매칭(자연키 code · po-module)';
comment on column public.customer.ar_account_code             is 'Cin7 AccountReceivable 원문 Code · FK 가 못 붙어도 남는다';
comment on column public.customer.sale_account_id             is 'FK → ref_account(id) · nullable · 인덱스 customer_sale_account_idx · Cin7 RevenueAccount(code · 예 _98_ · 화면의 Sale account)을 ref_account.code 로 매칭';
comment on column public.customer.sale_account_code           is 'Cin7 RevenueAccount 원문 Code · FK 가 못 붙어도 남는다';
comment on column public.customer.parent_id                   is 'Cin7 CustomerParentID → customer(id) · 자기 참조 · nullable · on delete no action · 인덱스 customer_parent_idx · ⭐ 연결 축만 — 상속 없음(§2-m 정정 · 자식 설정은 각자) · ⚠️ 적재는 부모를 먼저 넣어야 이어진다(적재 차수의 일)';
comment on column public.customer.is_bill_parent              is 'Cin7 IsBillParent 그대로 받아만 둔다 · IMS 규칙은 걸지 않는다(그 일은 default_bill_to_customer_id 가 한다 · 5-a)';
comment on column public.customer.is_legal_entity             is 'Cin7 IsLegalEntity 그대로 받아만 둔다';
comment on column public.customer.default_ship_to_customer_id is '⭐ Cin7 에 없는 우리 칸 · 「이 손님의 오더에 배송지를 채울 때 어느 손님의 주소록을 먼저 보나」 → customer(id) · 비어 있으면 자기 자신 · 가리키는 손님이 부모일 필요 없음(자유 연결) · 기본값일 뿐 — 오더에서 세 길 중 어느 것으로도 채운다(5-d 드롭십) · ⚠️ 재적재가 덮지 않는다 · 인덱스 customer_default_ship_to_customer_idx';
comment on column public.customer.default_bill_to_customer_id is '⭐ Cin7 에 없는 우리 칸 · 청구처 주소록의 주인 → customer(id) · 비어 있으면 자기 자신 · 주소를 복제하지 않고 주소록의 주인을 가리킨다(부모 주소가 바뀌면 자식 수만큼 고치는 일을 피한다 · 5-a) · ⚠️ 재적재가 덮지 않는다 · 인덱스 customer_default_bill_to_customer_idx';
comment on column public.customer.default_carrier             is 'Cin7 Carrier 원문 · 오더 carrier 의 기본값(5-d)';
comment on column public.customer.tax_number                  is '손님 세금 등록번호 · ⬜ §1-s 프로브 목록에 없던 칸(화면에만 보였다) — 필드명·유무는 적재 때 실물로(5-a ⬜)';
comment on column public.customer.tags                        is 'Cin7 Tags 원문 · ⚠️ 형식 미확인(문자열인지 배열인지 안 봤다) — text 로 받고 적재 때 본다(검토 이견 5)';
comment on column public.customer.cin7_comments               is 'Cin7 Comments 원문 · ⚠️ 우리 note 와 섞지 마라 — 재적재는 이 칸만 덮는다(supplier.cin7_comments 와 같은 이유 · 판정 ①)';

-- ═══ ② customer_address — 주소록 (관계 표 규약 · 판정 ②·③) ═══
create table if not exists public.customer_address (
  id                   uuid primary key default gen_random_uuid(),
  cin7_id              uuid unique,
  is_active            boolean not null default true,
  source               text not null default 'cin7',
  note                 text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  updated_by           uuid references public.ims_staff (id) on delete no action,
  customer_id          uuid not null references public.customer (id) on delete no action,
  type                 text,
  is_default_for_type  boolean not null default false,
  default_customer_id  uuid generated always as (case when is_default_for_type then customer_id end) stored,
  label                text,
  line1                text,
  line2                text,
  city                 text,
  state_province       text,
  postal_code          text,
  country              text,
  constraint customer_address_source_ck  check (source in ('cin7','manual')),
  constraint customer_address_type_ck    check (type is null or type in ('Billing','Business','Shipping')),
  constraint customer_address_default_uq unique (default_customer_id, type)
);
create index if not exists customer_address_customer_idx   on public.customer_address (customer_id);
create index if not exists customer_address_updated_by_idx on public.customer_address (updated_by);

comment on table  public.customer_address is 'SO 모듈 손님 주소록(Cin7 customer.Addresses[] 대응 · 우리 키 id · 열쇠 cin7_id — ⬜ Cin7 하위 ID 유무는 적재 첫 회에 · 없으면 손님 단위로 지우고 다시 넣는다 · 그래서 DELETE 가 열려 있다) · 관계 표 규약 7칸(name 없음) · TRUNCATE 막음 · 오더의 bill_to_*·ship_to_* 는 여기서 칸칸이 복사된다(5-d · 주소록을 FK 로 가리키지 않는다) · 정본 docs/design/so-module.md §5-b · §9 · 2026-09-22 신설';
comment on column public.customer_address.customer_id         is 'FK → customer(id) · NOT NULL · on delete no action(cascade 금지) · 인덱스 customer_address_customer_idx';
comment on column public.customer_address.type                is 'Cin7 Type 원문 · ⭐ CHECK customer_address_type_ck 셋(Billing · Business · Shipping · Cin7 손님 주소 화면 선택지 실측 — 그 밖은 고를 수 없다 · Caleb 2026-09-22 · 검토 이견 2) · null 허용(선택지가 빈 채로 시작한다) · ⚠️ 빈 문자열은 적재 때 null 로(ims_blank_ 전례) · ⭐ Business 는 배송지·청구지 기본값 찾기에 쓰지 않는다 · 📌 주소 type 을 제약하는 첫 표(supplier_address 는 CHECK 없음) · 적재 첫 회에 셀 것: type 빈 줄 수 · 「Business 만 있고 Shipping 없는 손님」 수';
comment on column public.customer_address.is_default_for_type is '⭐ Cin7 DefaultForType 을 받되 빈 곳은 규칙으로 메운다(판정 ③): 체크된 것은 그대로 믿는다 · 체크가 없고 그 type 이 하나면 그것을 기본으로 · 여럿이면 비워 두고 그 손님 수를 세어 사람이 정한다 · ⚠️ 확정은 적재 첫 회에 체크율을 센 뒤(거의 다 체크면 메울 필요 없음 · 거의 비었으면 supplier 처럼 Cin7 값을 버리는 쪽) · ⬜ 규칙으로 메운 것과 Cin7 값을 가를 표시가 필요한지는 적재 차수 · 「손님·type 당 하나」는 default_customer_id + customer_address_default_uq 가 지킨다';
comment on column public.customer_address.default_customer_id is '생성 칸 — is_default_for_type 이면 customer_id · 아니면 null · 전체 유니크 (default_customer_id, type) 가 「손님·type 당 기본 하나」를 막는다(기본이 아닌 줄은 null 이라 안 부딪힌다 · WHERE 없는 전체 유니크라 규칙 29 에 걸리지 않는다 · PostgREST on_conflict 도 받는다 · 5-b · 5-f 와 같은 장치) · ⚠️ type 이 null 인 기본 줄은 (customer, null) 이라 서로 안 부딪힌다 — 기본 줄에는 type 을 채우는 것이 적재·화면의 일';
comment on column public.customer_address.label               is '⭐ Cin7 에 없는 우리 칸 · 사람이 붙이는 이름(본사 · 2호점 · DDS 창고) — 드롭십 주소를 고를 때 두 줄만 보고 고르기 어렵다 · 적재 때 비워 두고 쓰면서 채운다 · ⚠️ 재적재가 덮지 않는다';
comment on column public.customer_address.line1               is 'Cin7 Line1 원문 · NOT NULL 없음 · 칸 이름은 supplier_address·ref_warehouse 와 같은 낱말(주소 전용 표라 address_ 접두어 없음)';
comment on column public.customer_address.line2               is 'Cin7 Line2 원문 · ⚠️ 빈 문자열("")은 적재에서 null 로 통일(ref_bin · supplier_address 전례)';
comment on column public.customer_address.state_province      is 'Cin7 State 원문 · ⭐ 이름을 state_province 로(5-b 의 state 를 뒤집었다 · ⬜4 — ref_warehouse · supplier_address · po 머리와 한 낱말 · 코드 0줄이라 지금이 가장 싸다) · §1-i 창고 라우팅의 근거 칸(BC·AB·MB → 에드먼튼) — ⚠️⚠️ 자동 라우팅 금지 · 제안까지만';
comment on column public.customer_address.postal_code         is 'Cin7 Postcode 원문 · ⭐ 이름을 postal_code 로(5-b 의 postcode 를 뒤집었다 · ⬜4)';
comment on column public.customer_address.note                is '우리가 적는 메모 · ⚠️ 재적재가 덮지 않는다';

-- ═══ ③ customer_contact — 연락처 (관계 표 규약 · 판정 ②·④) ═══
create table if not exists public.customer_contact (
  id                   uuid primary key default gen_random_uuid(),
  cin7_id              uuid unique,
  is_active            boolean not null default true,
  source               text not null default 'cin7',
  note                 text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  updated_by           uuid references public.ims_staff (id) on delete no action,
  customer_id          uuid not null references public.customer (id) on delete no action,
  name                 text,
  phone                text,
  mobile_phone         text,
  fax                  text,
  email                text,
  website              text,
  is_default           boolean not null default false,
  default_customer_id  uuid generated always as (case when is_default then customer_id end) stored,
  include_in_email     boolean not null default false,
  marketing_consent    boolean,
  cin7_comment         text,
  constraint customer_contact_source_ck  check (source in ('cin7','manual')),
  constraint customer_contact_default_uq unique (default_customer_id)
);
create index if not exists customer_contact_customer_idx   on public.customer_contact (customer_id);
create index if not exists customer_contact_updated_by_idx on public.customer_contact (updated_by);

comment on table  public.customer_contact is 'SO 모듈 손님 연락처(Cin7 customer.Contacts[] 대응 · 우리 키 id · 열쇠 cin7_id — ⬜ 하위 ID 유무는 적재 첫 회에) · 관계 표 규약 7칸 · DELETE 열림 · TRUNCATE 막음 · ⚠️ is_default · include_in_email · marketing_consent 는 받아 두기만 — 어느 칸이 메일 수신처를 정하는지는 메일 절에서 실물로(판정 ④ · 5-c ⬜) · 적재 첫 페이지에서 Contacts 키 목록을 그대로 센다(JobTitle 이 오면 그때 더한다) · 정본 docs/design/so-module.md §5-c · §9 · 2026-09-22 신설';
comment on column public.customer_contact.customer_id         is 'FK → customer(id) · NOT NULL · on delete no action(cascade 금지) · 인덱스 customer_contact_customer_idx';
comment on column public.customer_contact.name                is 'Cin7 Name 원문 · ⚠️ NOT NULL 금지(supplier_contact 는 32/261 이 빈 이름이었다) · 열쇠는 cin7_id';
comment on column public.customer_contact.fax                 is 'Cin7 Fax 원문 · ⬜5 수정 채택 — 손님 연락처 화면에 FAX 칸이 있고 공급처 API Contact 키에 Fax 가 있다(cin7-api references/supplier.md 101행) · 5-c 목록에 없던 칸(§9-d)';
comment on column public.customer_contact.is_default          is 'Cin7 Default 그대로 · 「손님당 하나」는 default_customer_id + customer_contact_default_uq 가 지킨다(5-c · 부분 유니크 금지) · ⚠️ 메일 수신처를 정하는 칸인지는 확인 전(5-c 관찰 「default contact 의 email 로 보내는 것 같다」 · 메일 절에서 실물로)';
comment on column public.customer_contact.default_customer_id is '생성 칸 — is_default 이면 customer_id · 아니면 null · 전체 유니크 customer_contact_default_uq 가 「손님당 기본 연락처 하나」를 막는다(5-c · 규칙 29 회피 장치)';
comment on column public.customer_contact.include_in_email    is 'Cin7 IncludeInEmail 그대로 · ⭐ 손님은 담는다(supplier 는 true 2/261 라 버렸다) — 손님 쪽에만 메일 실무(최종 인보이스 일부 자동 발송 · §1-r · §2-n)가 있고 버렸다가 필요해지면 9,452명을 다시 받아야 한다 · 뜻은 메일 절에서 · 적재 때 켜진 수만 센다';
comment on column public.customer_contact.marketing_consent   is '⭐ Cin7 MarketingConsent · nullable · 기본값 없음 — true 동의 · false 동의 안 함 · null 모름(IMS 에서 새로 만든 연락처) · CASL — 동의 기록은 나중에 만들 수 없는 종류라 Cin7 값을 그대로 받아 둔다 · ⚠️⚠️ 보낼 때는 null 을 false 와 똑같이 다룬다 — 확인된 동의(true)에만 마케팅 메일(검토 이견 4 채택)';
comment on column public.customer_contact.cin7_comment        is 'Cin7 Contact.Comment 원문 · ⚠️ 우리 note 와 섞지 마라 — 재적재는 이 칸만 덮는다(supplier_contact 와 같은 이유) · ⭐ 공급처 때 이 메모에 cc 수신처가 문장으로 적혀 있었다(E.T Browne) — 손님 메일 수신처를 정할 때(5-c ⬜) 근거가 될 수 있다 · 5-c 목록에 없던 칸(⬜5 · §9-d)';
comment on column public.customer_contact.note                is '우리가 적는 메모 · ⚠️ 재적재가 덮지 않는다 — Cin7 원문은 cin7_comment';

-- ═══ 트리거 — <표>_touch → 공용 ims_touch() (20260918133858 · updated_at 지금 · updated_by = auth.uid() → ims_staff.id · ⚠️ 다시 만들지 않는다) ═══
create trigger customer_touch         before update on public.customer         for each row execute function public.ims_touch();
create trigger customer_address_touch before update on public.customer_address for each row execute function public.ims_touch();
create trigger customer_contact_touch before update on public.customer_contact for each row execute function public.ims_touch();

-- ═══ RLS · 권한 — 20260917235000 모양(select 열림 · 쓰기 = ims_can_write('master') · (select …) 로 감싼다) · 묶음 master(⬜1 · sales 묶음은 SO 거래 표 차수에서) ═══
alter table public.customer         enable row level security;
alter table public.customer_address enable row level security;
alter table public.customer_contact enable row level security;

-- 마스터 — 정책 셋(delete 권한 자체가 없어 delete 정책을 만들지 않는다)
create policy customer_select on public.customer for select to authenticated using (true);
create policy customer_insert on public.customer for insert to authenticated with check ((select public.ims_can_write('master')));
create policy customer_update on public.customer for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
-- 관계 표 — 정책 넷(DELETE 열림 · 「손님 단위로 지우고 다시 넣는다」·「걸러서 지운다」가 이것을 전제한다)
create policy customer_address_select on public.customer_address for select to authenticated using (true);
create policy customer_address_insert on public.customer_address for insert to authenticated with check ((select public.ims_can_write('master')));
create policy customer_address_update on public.customer_address for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy customer_address_delete on public.customer_address for delete to authenticated using ((select public.ims_can_write('master')));
create policy customer_contact_select on public.customer_contact for select to authenticated using (true);
create policy customer_contact_insert on public.customer_contact for insert to authenticated with check ((select public.ims_can_write('master')));
create policy customer_contact_update on public.customer_contact for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy customer_contact_delete on public.customer_contact for delete to authenticated using ((select public.ims_can_write('master')));

revoke all on public.customer         from anon;
revoke all on public.customer_address from anon;
revoke all on public.customer_contact from anon;
revoke delete, truncate on public.customer         from authenticated;   -- 마스터는 is_active 로 물러나게 한다
revoke truncate         on public.customer_address from authenticated;   -- 관계 표 — delete 는 연다
revoke truncate         on public.customer_contact from authenticated;

-- 검증(회신에 따로 · psql heredoc): 표 셋 행 0 · 정책 11(3+4+4) · 트리거 _touch 셋 · _set_updated_at 0 · 유니크 5(cin7_id 셋 · customer_address_default_uq · customer_contact_default_uq) ·
--   FK 인덱스 13 · anon 권한 0 · authenticated 가 customer 에 DELETE·TRUNCATE 없음 · address/contact 에 TRUNCATE 없음 · 권한 실동작(42501) · 생성 칸 유니크(23505) · type CHECK(23514 · Business 통과 · 'business' 거부 · null 통과).
-- 적용은 psql -f + supabase migration repair --status applied 20260922201223 (po-module §13-f · 이력 표가 안 쌓인다) — 실행은 Caleb.
