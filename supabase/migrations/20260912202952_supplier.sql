-- PO 모듈 ② 공급처 — 본체 표 신설: supplier (2026-09-12) · ⚠️ 이번 단계는 본체 하나뿐(주소·연락처·할인 표는 다음 단계 · 적재 GAS 도 별도)
--
-- 목표: 마이그레이션 1개 · 표 1개 · 행 적재 0건. 뼈대만.
-- 선행: 20260911144606(set_updated_at()) · 161647(ref_payment_term) · 162906(ref_account) · 164513(ref_currency) — 셋을 FK 로 참조한다.
-- 정본: docs/design/po-module.md §7-b(칸·근거) · §7-a(범위·FK 방식) · §5(공통 규약). 이 파일과 정본이 어긋나면 정본이 이긴다.
--
-- ═══ 이름 — ref_ 접두어를 붙이지 않는다 (§7-b) ═══
--   표 여덟의 ref_ 는 「다른 표가 값을 고르러 오는 목록」이었다. 공급처는 고르는 대상이 아니라 거래 상대이고 주소·연락처·할인을
--   거느리며 발주가 여기 매달린다 ⇒ supplier · supplier_address · supplier_contact · supplier_discount (뒤 셋은 다음 단계).
--   §5 가 공용 트리거 함수에 ref_ 를 안 붙인 판단(「②·③ 이 ref_ 가 아닐 수 있다」)이 여기서 맞았다.
--
-- ═══ 실측 근거 (2026-09-11~12 GAS 프로브 · GET /supplier 전량 688 · 활성 226) ═══
--   담는 범위 = 활성 226 전부. 비활성 462 는 담지 않는다(대부분 경비처 · §7-a · §8-A-1).
--   PaymentTerm 226/226 이 ref/paymentterm 의 Name 과 일치 · AccountPayable 226/226 이 ref/account 의 Code 와 일치(Name 일치 0) — Cin7 은 마스터를 이름 문자열로 참조한다(§8).
--   ⚠️ Net30(비활성) 21곳 · Net45(비활성) 2곳이 옛 표기를 쓴다 — 이름이 흔들리면 FK 가 못 붙는다 ⇒ 원문 칸을 함께 둔다.
--   Currency: 활성 226 안에 CAD·USD 만(KRW 는 비활성 1곳).
--   is_purchasable(우리 칸): Caleb 전수 판정 true 161 · false 56 · null 9(§8-B).
--   ⚠️ 거래 중단 표시가 연락처 이름 칸에 숨어 있다 — 'No longer purchase' 계열 24곳(대소문자 변형 6 포함 · Exod International 의 'No Longer Working' 은 제외 · Ashton Adams 는 'INACTIVE')
--     ⇒ supplier.is_discontinued 로 승격한다(§7-b-A). Cin7 에 날짜가 없어 discontinued_on 은 적재 시점에 전부 null.
--   Comments 75/226 에 값(주문 이메일·픽업 방식·결제 방식·처리 규칙) ⇒ cin7_comments 로 따로 받는다. 우리 note 에 붓지 않는다.
--
-- ═══ 설계 판단 (Caleb 확정 2026-09-12 · §7-b) ═══
--   · ⭐ name 유니크 — 중복 방지가 아니라 「이름을 열쇠로 쓸 수 있게 하는 장치」다: Cin7 이 이름으로 참조하고 upsert(on_conflict=name)가 유니크에 기댄다.
--     대가: 겹치면 그 배치 전체가 실패한다(전량 688 중복 0 은 오늘의 사실이지 규칙이 아니다). 'Ampro Industries' 와 'Ampro Industries, Inc.' 는 다른 글자 — 이것은 못 막는다.
--     이름이 바뀌면 행을 바꾼다(id 가 신원 · PO·제품↔공급처가 id 로 매달린다). 병행 운영 중엔 Cin7 을 먼저 바꾸고 우리가 따라간다 — 반대로 하면 다음 적재가 새 행을 만든다.
--   · FK + 원문 병행(§7-a) — payment_term_id/payment_term_name · account_payable_id/account_payable_code. 못 이은 것은 FK 가 null 이고 그 개수가 「아직 정리 안 된 곳」의 카운터.
--     ⚠️ Cin7 화면에서 필수인 축이라도 FK 에 NOT NULL 을 걸지 않는다 — NOT NULL 은 원문 칸에. 적재가 도중에 멈추지 않게 한다.
--   · currency_id 는 FK 하나(원문 없음) — CAD·USD 둘뿐이고 우리가 만든 표라 흔들리지 않는다.
--   · tax_rule 은 원문 문자열만 — ref_tax_rule 표는 아직 없다(§7 다음 갈림길 미결). 나중에 FK 칸만 옆에 붙인다.
--   · ⚠️⚠️ is_purchasable 은 nullable · 기본값 없음 — null = 「아직 판정 안 됨」의 카운터. DEFAULT false 를 넣으면 「경비처로 판정했다」와 구별되지 않는다.
--     Cin7 에 대응 개념이 없어 재동기화가 이 칸을 덮으면 안 된다(source 칸이 근거).
--   · ⭐ 거래 중단을 is_purchasable 과 섞지 않는다 — is_purchasable 「살 수 있는 곳인가」(발주처/경비처) · is_discontinued 「지금도 사는 곳인가」.
--     AIM DISTRIBUTOR 는 발주처가 맞고 지금 안 살 뿐이다. 중단이어도 is_purchasable 은 건드리지 않는다. 새 PO 후보는 두 칸을 같이 본다.
--   · ⚠️ 담지 않는 Cin7 칸 — AdditionalAttribute1(Supplier Type)·AttributeSet(§7-a · 정본은 is_purchasable) · Discount(⚠️ 「칸 하나」를 안 담는 것 — 할인은 다음 단계 supplier_discount 표) ·
--     TaxNumber(수집하지 않는다 · 전 곳 빈값) · LastModifiedOn(증분 적재가 필요해질 때 — 226곳엔 불필요 · §7-b 뒤집힌 판단) · Default carrier(§8-D · API 응답에 없다).
--
-- ═══ 공통 규약 확인 (§5 · 20260911165946 과 동일한 모양) ═══
--   공통 여덟 칸 · source check · FK on delete no action(cascade 금지) · FK 컬럼 인덱스 <표>_<컬럼>_idx · 트리거 <표>_set_updated_at(공용 함수 재사용 · ⚠️ 다시 만들지 않는다)
--   · RLS auth_all + revoke anon · revoke delete, truncate from authenticated(마스터는 is_active 로 물러나게 한다) · 부분 유니크 인덱스 없음(PostgREST on_conflict).

-- ── supplier ──
create table if not exists supplier (
  id                   uuid primary key default gen_random_uuid(),
  cin7_id              uuid unique,
  name                 text not null unique,
  is_active            boolean not null default true,
  source               text not null default 'cin7',
  note                 text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  payment_term_id      uuid references ref_payment_term(id) on delete no action,
  payment_term_name    text not null,
  account_payable_id   uuid references ref_account(id) on delete no action,
  account_payable_code text not null,
  currency_id          uuid references ref_currency(id) on delete no action,
  tax_rule             text,
  is_purchasable       boolean,
  is_discontinued      boolean not null default false,
  discontinued_on      date,
  cin7_comments        text,
  constraint supplier_source_ck check (source in ('cin7','manual'))
);
create index supplier_payment_term_idx    on supplier (payment_term_id);
create index supplier_account_payable_idx on supplier (account_payable_id);
create index supplier_currency_idx        on supplier (currency_id);

comment on table supplier is 'PO 모듈 ② 공급처 본체(Cin7 GET /supplier 대응 · 캐시 아님 · 우리 키 id · cin7_id 는 매핑) · 활성 226 만 담는다(비활성 462 는 경비처 · QBO 영역) · ⚠️ ref_ 접두어 없음 — 고르는 목록이 아니라 거래 상대(주소·연락처·할인 표가 여기 매달린다) · name 유니크 = 이름을 열쇠로 쓰는 장치(upsert on_conflict=name) · 정본 docs/design/po-module.md §7-b · 2026-09-12 신설';
comment on column supplier.name                 is '⭐ unique · Cin7 이 마스터를 이름 문자열로 참조하므로 열쇠 노릇을 해야 한다. 이름이 바뀌면 행을 바꾼다(새로 만들지 않는다 — 신원은 id). ⚠️ 병행 운영 중엔 Cin7 을 먼저 바꾸고 우리가 따라간다 · 유니크는 「같은 회사 두 번」을 막지 못한다(다른 글자)';
comment on column supplier.payment_term_id      is 'FK → ref_payment_term(id) · nullable · on delete no action · 인덱스 supplier_payment_term_idx. Cin7 원문(payment_term_name)을 이름으로 매칭해 채운다 — 못 이은 행은 null 이고 그 개수가 정리 대상의 카운터(Net30·Net45 옛 표기 23곳)';
comment on column supplier.payment_term_name    is 'Cin7 PaymentTerm 원문 문자열 · NOT NULL. FK 가 못 붙어도 여기는 남는다 — 적재가 도중에 멈추지 않게 하는 칸(§7-a)';
comment on column supplier.account_payable_id   is 'FK → ref_account(id) · nullable · on delete no action · 인덱스 supplier_account_payable_idx. Cin7 원문(account_payable_code)을 ref_account.code 로 매칭해 채운다(실측 226/226 일치 — 오늘의 사실이지 규칙이 아니다)';
comment on column supplier.account_payable_code is 'Cin7 AccountPayable 원문 Code(예: _109_) · NOT NULL. FK 가 못 붙어도 여기는 남는다';
comment on column supplier.currency_id          is 'FK → ref_currency(id) · nullable · on delete no action · 인덱스 supplier_currency_idx. 원문 칸 없음 — CAD·USD 둘뿐이고 우리가 만든 표라 흔들리지 않는다';
comment on column supplier.tax_rule             is 'Cin7 TaxRule 원문 문자열. ref_tax_rule 표는 아직 없다(§7 미결) — 생기면 FK 칸을 옆에 붙인다';
comment on column supplier.is_purchasable       is '⭐ Cin7 에 없는 우리 칸 · 「살 수 있는 곳인가」(발주처/경비처 판정 · Caleb 전수 161/56/9). ⚠️⚠️ null = 미판정. false 로 밀지 마라 — 「경비처로 판정했다」와 「아직 안 정했다」가 구별되지 않는다. Cin7 재동기화가 덮으면 안 된다';
comment on column supplier.is_discontinued      is '⭐ 우리 칸 · 「지금도 사는 곳인가」(거래 중단). is_purchasable(「살 수 있는 곳인가」)과 별개다 — 중단이어도 is_purchasable 은 건드리지 않는다. 적재 시 연락처 이름 칸의 No longer purchase 계열(소문자 비교 · 24곳)에서 승격 · 우리 화면 목록에 보여야 한다(안 보이면 실무가 또 다른 자리를 빌려 쓴다)';
comment on column supplier.discontinued_on      is '거래 중단 날짜 · nullable. ⚠️ 적재 시점엔 전부 null — Cin7 에 날짜가 없다(글자만 있다). 여부는 is_discontinued 가 갖고 날짜는 앞으로만 채워진다';
comment on column supplier.cin7_comments        is 'Cin7 Comments 원문(75/226 · 주문 이메일·픽업 방식·결제 방식·처리 규칙). ⚠️ 우리 note 와 섞지 마라 — 재적재는 이 칸만 덮는다. 칸으로 쪼개지 않는다(실태가 먼저고 칸이 나중) · 결제조건이 메모에도 적혀 있으나 ref_payment_term 이 정본';
comment on column supplier.note                 is '우리가 적는 메모(이름 변경 이력 등). ⚠️ Cin7 재적재가 덮지 않는다 — Cin7 원문은 cin7_comments';

-- ── updated_at 트리거 — 공용 함수 set_updated_at() 재사용(다시 만들지 않는다) ──
create trigger supplier_set_updated_at before update on supplier for each row execute function set_updated_at();

-- ── RLS · 권한 — ref_ 표와 동일: auth_all + revoke anon · ⚠️ DELETE·TRUNCATE 는 authenticated 에서 막는다(is_active 로 물러나게 한다) ──
alter table supplier enable row level security;
create policy auth_all on supplier for all to authenticated using (true) with check (true);
revoke all on supplier from anon;
revoke delete, truncate on supplier from authenticated;
