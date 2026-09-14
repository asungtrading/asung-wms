-- ─────────────────────────────────────────────────────────────
-- product_family — IMS ③ 제품 · 제품군 (테스트 DB Asung-IMS)
--
-- 정본: docs/design/po-module.md · 상위 ims-principles.md
-- 실측: 2026-09-13 GAS 프로브(ProbeProduct.gs) · GET /productFamily 전량 1,141
--
-- ⭐ 무엇인가 — 같은 물건의 색상·사이즈 변형을 묶는 단위.
--    제품군 자체는 팔리지 않는다(재고 없음 · SKU 는 …FAM). 목록 노릇만 한다.
--    ⇒ product.family_id 가 이 표를 가리킨다. 방향이 위→아래가 아니라 아래→위다.
--
-- ⚠️⚠️ 가격 10단계를 담지 않는다 — 실측에서 제품군 값과 변형 값이 950/4,884 어긋났다.
--    Category·Brand·계정·원산지는 4,884 전수 일치(제품군 쪽은 새 변형 만들 때의 기본값)이지만
--    가격만 변형이 따로 관리된다. 담으면 같은 값이 두 곳에 살고 950건이 어긋난 채 들어온다.
--    📌 화면의 가격에는 CALCULATED·TYPE(Markup %)·USE(Average cost) 가 붙어 있는데
--       GET /product 응답에는 그 계산 규칙이 없다 — 숫자만 베끼면 「왜 이 값인가」가 사라진다.
--       가격 축은 SO 모듈에서 ref/markupprices 까지 재고 나서 세운다.
--
-- ⚠️ HSCode 도 담지 않는다 — 제품군 쪽이 비어 있고(254건 전부 군=""), 변형에만 있다.
-- ⚠️ Attachments[] 는 담지 않는다 — 이미지 사슬이 따로 있다
--    (Cin7 → BQ asung_product_images → wms_sku_snapshot · product-images EF 가 매일 덮는다).
--    ③ 이 담으면 같은 사실의 셋째 사본이 된다.
-- ⚠️ Products[] 는 담지 않는다 — 그 관계는 product.family_id 로 표현된다.
--
-- ⭐ 옵션 축 셋 — 이름은 여기, 값은 product 에 (Option1Name / Products[].Option1)
--    실측: Option1Name 33종(Color 463 · Size 332 · Formula 69 · Type 52 · Style 46 · color 38 …)
--          Option2Name 13종 · Option3Name 1종(Quantity 하나뿐)
--    ⚠️ 33종이라 뜻 있는 칸으로 승격할 수 없다 — 이름을 값으로 담는다.
--       ims-principles §4-d 가 금한 것은 「이름 없는 칸에 뜻 있는 값을 숨기는 것」이고
--       여기는 이름이 값으로 같이 온다(supplier_discount.name 을 자유 문자열로 둔 것과 같은 판단).
--    ⚠️ Color/color · Size/size · Flavor/Flavour 가 따로 있다(Net 30/Net30 계열 흔들림).
--       정규화하지 않고 원문 그대로 받는다 — 사람이 전수 검사할 일이다.
--
-- ⭐ 자연키 sku — 실측 1,141/1,141 이 FAM 으로 끝난다(2026-09-13 Caleb 이 예외 둘을 고친 뒤).
--    ⚠️ name 에는 유니크를 걸지 않는다. 제품 쪽 이름 중복 576종의 뿌리가 이 변형들이고,
--       제품군 이름 중복은 측정하지 않았다(ref_account.name 9건 사고와 같은 자리).
-- ─────────────────────────────────────────────────────────────

create table if not exists public.product_family (
  -- 공통 8칸 (po-module §5)
  id            uuid primary key default gen_random_uuid(),
  cin7_id       uuid unique,
  name          text not null,
  is_active     boolean not null default true,
  source        text not null default 'cin7',
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- ⭐ 자연키
  sku           text not null unique,

  -- FK + 원문 병행 (공급처 §7-a 와 같은 규칙 — 못 이어도 적재가 멈추지 않는다)
  brand_id      uuid references public.ref_brand    (id) on delete no action,
  brand_name    text,
  category_id   uuid references public.ref_category (id) on delete no action,
  category_name text,
  unit_id       uuid references public.ref_unit     (id) on delete no action,
  uom_name      text,

  -- ⭐ 옵션 축 — 이름만. 값은 product 에.
  option1_name  text,
  option2_name  text,
  option3_name  text,

  -- Cin7 값
  costing_method   text,
  cin7_description text,
  cin7_modified_on timestamptz,

  constraint product_family_source_ck check (source in ('cin7', 'manual'))
);

comment on table  public.product_family        is 'IMS ③ 제품군 — 색상·사이즈 변형을 묶는 단위. 팔리지 않는다. 실측 1,141행(2026-09-13)';
comment on column public.product_family.sku    is '자연키. …FAM 으로 끝난다(1,141/1,141)';
comment on column public.product_family.option1_name is '옵션 축 이름. 값은 product.option1_value. 실측 33종 — 목록으로 만들지 않는다';
comment on column public.product_family.note   is '우리가 적는 메모. 재적재가 덮지 않는다';

-- FK 인덱스 — Postgres 는 자동 생성하지 않는다 (§5)
create index if not exists product_family_brand_idx    on public.product_family (brand_id);
create index if not exists product_family_category_idx on public.product_family (category_id);
create index if not exists product_family_unit_idx     on public.product_family (unit_id);

-- 트리거 — ⚠️ set_updated_at() 은 20260911144606 에 하나뿐. 다시 만들지 마라
create trigger product_family_set_updated_at
  before update on public.product_family
  for each row execute function public.set_updated_at();

-- RLS
alter table public.product_family enable row level security;

create policy auth_all on public.product_family
  for all to authenticated using (true) with check (true);

revoke all on public.product_family from anon;

-- ⚠️ 마스터는 지우지 않고 is_active 로 물러나게 한다 (§5)
revoke delete, truncate on public.product_family from authenticated;
