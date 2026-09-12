-- PO 모듈 ② 공급처 — 주소·연락처 표 신설: supplier_address · supplier_contact (2026-09-12) · ⚠️ supplier_discount 는 다음 단계 · 적재 GAS 도 별도
--
-- 목표: 마이그레이션 1개 · 표 2개 · 행 적재 0건. 뼈대만.
-- 선행: 20260912202952(supplier 본체 · 테스트 DB 에 226행 적재 완료) — 둘 다 supplier(id) 를 FK 로 참조한다.
-- 정본: docs/design/po-module.md §7-b 의 B(주소)·C(연락처) · §5(공통 규약). 이 파일과 정본이 어긋나면 정본이 이긴다.
--
-- ═══ 실측 근거 (2026-09-12 GAS 프로브 · GET /supplier 활성 226) ═══
--   주소 87건: Type Billing 77 · Business 8 · Shipping 2 · 개수 0건 143곳 · 1건 79곳 · 2건 4곳(최대 2 · §8 과 일치)
--     2건인 4곳의 조합 Billing+Billing 1 · Billing+Business 1 · Billing+Shipping 1 · Business+Shipping 1 — 같은 타입 둘은 House of Cheatham, Inc. 1곳뿐
--     칸별 채움/87 Line1 87 · Line2 9 · City 85 · State 81 · Postcode 83 · Country 83 · Type 87
--   연락처 261건: Name 229(빈 32) · Phone 112 · MobilePhone 38 · Fax 17 · Email 139 · Website 53 · Comment 45 · Default true 169/false 92(둘 이상인 공급처 0곳) · IncludeInEmail true 2
--     ⚠️ 연락수단이 하나도 없는 행 117 — 회사 이름이 그대로 든 행(Alamo · DHL Express …) · 상태를 적은 행("Acquired by J&D Brush" · "INACTIVE") · 거래 중단 표시 24
--     한 공급처 안 이름 중복 0 — 그러나 빈 이름 32 라 이름을 열쇠로 쓸 수 없다
--
-- ═══ 설계 판단 (Caleb 확정 2026-09-12 · §7-b) ═══
--   · 열쇠는 둘 다 cin7_id(unique). ⚠️ (supplier_id, type) 은 자연키가 아니다 — House of Cheatham 이 Billing 둘 · (supplier_id, name) 도 아니다 — 빈 이름 32.
--   · ⚠️⚠️ DefaultForType 은 만들지 않는다 — 실측 true 15 / false 72 인데 주소가 1건뿐인 공급처가 79곳 ⇒ 유일한 주소인데 「기본이 아니다」로 찍힌 행이 60곳 안팎.
--     화면 체크박스라 아무도 안 누르면 false 로 남는다(실물 Beauty Treats: 주소 1건 BILLING · 체크 없음). 담으면 「기본 청구지를 가져와라」가 60곳에서 조용히 빈다 — 에러는 안 난다(§6-a 계열).
--     ⇒ 기본 주소는 규칙으로 정한다: 1건이면 그것 · 2건이면 타입으로(3곳) · Billing 둘인 House of Cheatham 1곳만 사람이 정한다. 늦게 파도 채워지는 부류(ims-principles §4-d).
--   · 연락처 is_default 는 담는다 — 주소의 DefaultForType 과 달리 실제로 구별한다(둘 이상인 공급처 0곳). Cin7 목록 화면의 CONTACT 칸이 이 값을 보여 준다(그래서 실무가 여기에 상태를 적었다).
--   · ⚠️ IncludeInEmail 은 만들지 않는다 — true 2/261. 실무는 그 대신 Comments 에 문장으로 적었다(E.T Browne: cc 넷). 발주서 발송을 실제로 만들 때 우리 칸으로 새로 만든다.
--   · ⚠️ JOB TITLE 은 화면에만 있고 GET /supplier 응답에 없다 — 담을 수 없다.
--   · Cin7 Contact.Comment 는 공통 note 가 아니라 별도 칸 cin7_comment 로 — 본체의 cin7_comments/note 분리와 같은 이유(재적재가 우리가 적은 말을 덮는다).
--   · ⭐ 적재 방침: 연락처 261건을 그대로 옮기고 나중에 걸러서 지운다. 다만 거래 중단 표시 24건은 연락처가 아니다 — supplier.is_discontinued 로 승격하고 행은 남기지 않는다.
--   · 주소 칸 이름은 ref_warehouse 의 주소 여섯과 같은 낱말(line1·line2·city·state_province·postal_code·country) — 두 표를 나란히 읽을 일이 생긴다. 주소 전용 표라 address_ 접두어는 붙이지 않는다.
--   · NOT NULL 은 supplier_id 와 is_default 에만 — line1 87/87 은 오늘의 사실이지 규칙이 아니다 · name 은 빈 값 32.
--
-- ═══ ⭐ 권한 — 본체와 다르다 (Caleb 확정 2026-09-12) ═══
--   본체 supplier 는 DELETE 를 막았다(행이 지워지면 매달린 과거 발주가 갈 곳을 잃는다 · is_active 로 물러난다).
--   주소·연락처는 ⭐ DELETE 를 연다 — 어느 문서도 이 행들을 가리키지 않고 지워져도 남는 것이 없다. Cin7 에서 지워진 연락처를 우리 표에서 치워야 하고,
--   「그대로 옮기고 나중에 걸러서 지운다」가 DELETE 를 전제한다. ⚠️ TRUNCATE 는 막는다 — 표를 통째로 비우는 것은 실수 한 줄이면 된다.
--
-- ═══ 공통 규약 확인 (§5 · 20260912202952 와 동일한 모양) ═══
--   공통 칸(id·cin7_id·is_active·source·note·created_at·updated_at · ⚠️ name 은 공통이 아니다 — 주소에 없고 연락처는 nullable) · source check ('cin7','manual')
--   · FK on delete no action(cascade 금지) · 인덱스 <표>_supplier_idx · 트리거 <표>_set_updated_at(공용 함수 재사용 · ⚠️ 다시 만들지 않는다)
--   · RLS auth_all + revoke anon · revoke truncate from authenticated(delete 는 revoke 하지 않는다) · 부분 유니크 인덱스 없음(PostgREST on_conflict).

-- ── supplier_address ──
create table if not exists supplier_address (
  id             uuid primary key default gen_random_uuid(),
  cin7_id        uuid unique,
  is_active      boolean not null default true,
  source         text not null default 'cin7',
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  supplier_id    uuid not null references supplier(id) on delete no action,
  line1          text,
  line2          text,
  city           text,
  state_province text,
  postal_code    text,
  country        text,
  type           text,
  constraint supplier_address_source_ck check (source in ('cin7','manual'))
);
create index supplier_address_supplier_idx on supplier_address (supplier_id);

comment on table supplier_address is 'PO 모듈 ② 공급처 주소(Cin7 supplier.Addresses[] 대응 · 우리 키 id · 열쇠 cin7_id) · 실측 활성 226 중 주소 0건 143곳 · 1건 79곳 · 2건 4곳(최대 2) — ⚠️ 「최소 1건」류 제약을 걸지 마라(§8-D) · ⚠️ 주소 유무를 발주처/경비처 판정의 근거로 쓰지 마라(상관이 보였으나 인과가 아니다) · ⚠️⚠️ DefaultForType 은 없다 — true 15/false 72 인데 주소 1건뿐인 곳이 79 라 값이 실태를 반영하지 않는다(체크박스 미클릭 = false). 기본 주소는 규칙으로: 1건이면 그것 · 2건이면 타입 · Billing 둘인 House of Cheatham 1곳만 사람이 · ⭐ DELETE 열림(어느 문서도 가리키지 않는다) · TRUNCATE 막음 · 정본 docs/design/po-module.md §7-b-B · 2026-09-12 신설';
comment on column supplier_address.supplier_id is 'FK → supplier(id) · NOT NULL · on delete no action(cascade 금지) · 인덱스 supplier_address_supplier_idx';
comment on column supplier_address.type        is 'Cin7 Type 원문 · 실측 Billing 77 · Business 8 · Shipping 2. ⚠️ (supplier_id, type) 은 자연키가 아니다 — House of Cheatham, Inc. 이 Billing 을 둘 갖는다 ⇒ 열쇠는 cin7_id';
comment on column supplier_address.line1       is 'Cin7 Line1 · 실측 87/87 채움이지만 NOT NULL 을 걸지 않는다 — 오늘의 사실이지 규칙이 아니다. 칸 이름은 ref_warehouse.address_line1 과 같은 낱말(주소 전용 표라 접두어 없음)';
comment on column supplier_address.line2       is 'Cin7 Line2 · 실측 9/87 만 채움. ⚠️ 빈 문자열("")로 오는 값은 적재에서 null 로 통일한다(ref_bin 전례 · ims_blank_)';

-- ── supplier_contact ──
create table if not exists supplier_contact (
  id           uuid primary key default gen_random_uuid(),
  cin7_id      uuid unique,
  is_active    boolean not null default true,
  source       text not null default 'cin7',
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  supplier_id  uuid not null references supplier(id) on delete no action,
  name         text,
  phone        text,
  mobile_phone text,
  fax          text,
  email        text,
  website      text,
  is_default   boolean not null default false,
  cin7_comment text,
  constraint supplier_contact_source_ck check (source in ('cin7','manual'))
);
create index supplier_contact_supplier_idx on supplier_contact (supplier_id);

comment on table supplier_contact is 'PO 모듈 ② 공급처 연락처(Cin7 supplier.Contacts[] 대응 · 우리 키 id · 열쇠 cin7_id) · 실측 261건 · ⚠️ 연락수단(전화·모바일·팩스·메일·웹)이 하나도 없는 행 117 — 회사 이름이 그대로 든 행 · 상태를 적은 행("Acquired by J&D Brush" · "INACTIVE") ⇒ 그대로 옮기고 나중에 걸러서 지운다(⭐ DELETE 가 열려 있는 이유 · TRUNCATE 는 막음) · ⚠️ 거래 중단 표시("No longer purchase" 계열 24건)는 연락처가 아니다 — supplier.is_discontinued 로 승격하고 행은 남기지 않는다 · 칸별 채움/261 Phone 112 · MobilePhone 38 · Fax 17 · Email 139 · Website 53 · Comment 45 · ⚠️ IncludeInEmail(true 2/261) 과 JOB TITLE(API 응답에 없다)은 담지 않는다 · 정본 docs/design/po-module.md §7-b-C · 2026-09-12 신설';
comment on column supplier_contact.supplier_id  is 'FK → supplier(id) · NOT NULL · on delete no action(cascade 금지) · 인덱스 supplier_contact_supplier_idx';
comment on column supplier_contact.name         is 'Cin7 Name 원문 · ⚠️ NOT NULL 금지 — 실측 32/261 이 빈 이름. 한 공급처 안 이름 중복은 0 이지만 빈 이름 때문에 자연키로 쓸 수 없다 ⇒ 열쇠는 cin7_id';
comment on column supplier_contact.is_default   is 'Cin7 Default 그대로 · 실측 true 169 · ⚠️ 둘 이상인 공급처 0곳 — 주소의 DefaultForType 과 달리 실제로 구별한다. 📌 Cin7 공급처 목록 화면의 CONTACT 칸이 이 값을 보여 준다(그래서 실무가 여기에 상태를 적었다). 둘이 true 되는 것을 제약으로 막지 않는다(부분 유니크 금지)';
comment on column supplier_contact.cin7_comment is 'Cin7 Contact.Comment 원문(45/261). ⚠️ 우리 note 와 섞지 마라 — 재적재는 이 칸만 덮는다(본체 cin7_comments/note 분리와 같은 이유). IncludeInEmail 대신 실무가 cc 대상을 여기 문장으로 적었다(E.T Browne)';
comment on column supplier_contact.note         is '우리가 적는 메모. ⚠️ Cin7 재적재가 덮지 않는다 — Cin7 원문은 cin7_comment';

-- ── updated_at 트리거 — 공용 함수 set_updated_at() 재사용(다시 만들지 않는다) ──
create trigger supplier_address_set_updated_at before update on supplier_address for each row execute function set_updated_at();
create trigger supplier_contact_set_updated_at before update on supplier_contact for each row execute function set_updated_at();

-- ── RLS · 권한 — auth_all + revoke anon · ⭐ DELETE 는 연다(본체와 다르다 · 위 「권한」 절) · ⚠️ TRUNCATE 만 막는다 ──
alter table supplier_address enable row level security;
alter table supplier_contact enable row level security;
create policy auth_all on supplier_address for all to authenticated using (true) with check (true);
create policy auth_all on supplier_contact for all to authenticated using (true) with check (true);
revoke all on supplier_address from anon;
revoke all on supplier_contact from anon;
revoke truncate on supplier_address from authenticated;
revoke truncate on supplier_contact from authenticated;
