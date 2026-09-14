-- ─────────────────────────────────────────────────────────────
-- product_supplier — IMS ④ 제품↔공급처 (테스트 DB Asung-IMS)
--
-- 정본: docs/design/po-module.md §3-g · 상위 ims-principles.md(원칙 1 Cin7 독립 · 원칙 2 레고)
-- 실측: 2026-09-14 · GAS ProbeProductSupplier.gs · GET /product?IncludeSuppliers=true 전량 18,829 (Limit 1000 · 19페이지 · 107초)
--       Type=Stock 줄 12,728 (시트 전체 12,729 — Stock 아닌 제품의 줄 1 포함 · §3-g 경위) · 쌍 (ProductID, SupplierID) 중복 0 · ProductSupplierID 중복·빈값 0
--
-- ⭐ 왜 표인가 — Cin7 의 Suppliers[] 는 「이 제품을 어디서 얼마에 샀나」다. Cin7 이 사라지면 복원할 수 없다(원칙 1).
--    ⑤ PO 본체가 발주 후보·단가 폴백을 여기서 읽는다. Productmaster.js 가 BQ 에 매일 붓는 것과 다르다 — 그쪽은 캐시, 여기는 우리 표.
--
-- ⭐ 범위 — 비활성 공급처(688 중 462)에 붙은 줄도 담는다(787줄 · 31곳). 「예전에 어디서 샀나」도 사실이다.
--    발주 후보에서 빼는 일은 읽는 쪽이 supplier.is_active 를 걸어서 한다(§3-f 와 같은 모양).
--    ⚠️ 688 전부를 supplier 에 넣는 것은 아니다 — 제품에 붙어 등장한 GUID 만 적재가 스스로 데려온다(is_active=false · is_purchasable null).
--    ⚠️ 그때 Suppliers[] 에는 SupplierID·SupplierName 만 온다 — supplier 의 NOT NULL 칸(payment_term_name·account_payable_code)은
--       GET /supplier?IncludeDeprecated=true 전량 688 에서 채운다. ② 공급처 데려오기가 ③ 줄 넣기보다 먼저다(FK).
--
-- ⭐ 충돌 키는 cin7_id(ProductSupplierID) — ⑤ PUT /product-suppliers 가 필수로 요구하는 열쇠이기도 하다(없으면 단가를 Cin7 에 못 쓴다).
--    (product_id, supplier_id) 유니크는 「같은 쌍 두 줄 금지」라는 우리 규칙 — 12,728 줄 실측 중복 0 위에 건다.
--    ⚠️ 승격 — 사람이 먼저 적은 manual 줄(cin7_id null)과 같은 쌍이 Cin7 에 나타나면 새 행을 만들지 않고 그 행에 cin7_id·단가를 PATCH 로 채운다.
--       source 는 manual 유지(사람이 만든 줄이라는 사실은 남긴다). ⇒ 재적재 갱신 대상은 「source='cin7'」이 아니라 「cin7_id 가 있는 줄」.
--    ⚠️ 못 이은 줄(supplier_id·product_id 를 찾지 못함)은 넣지 않고 센다 — 오늘 0 이어도 장치는 둔다.
--
-- ⭐ is_default 는 우리 칸 — Cin7 응답에 기본 공급처 표시가 없다(Suppliers[] · ProductSupplierOptions[] 어디에도 Default·Primary 류 칸 없음).
--    계산: 후보 = supplier.is_active=true 인 줄만 · 하나면 그것 · 둘 이상이면 last_supplied 가 가장 최근인 것 · 가릴 수 없으면 비워 두고 센다.
--    ⚠️ 그 제품에 source='manual' 줄이 하나라도 있으면 재적재가 is_default 를 다시 계산하지 않는다(②의 is_purchasable 을 지킨 장치와 같다).
--    ⚠️⚠️ 부분 유니크 인덱스로 「제품당 하나」를 강제하지 마라 — PostgREST on_conflict 가 깨진다(WMS 규칙 29). 카운터로 센다(product_barcode.is_primary 선례).
--    ⚠️ product.default_supplier_id FK 대안은 채택하지 않았다 — product 를 ALTER 하면 ③ 이 ④ 의 사정을 알게 된다(원칙 2).
--
-- ⭐ 단가 — Cin7 은 소수 일곱 자리를 준다(Cost 1.3991666 · FixedCost 1.3991667) ⇒ numeric(18,7).
--    Cin7 줄의 「없음」은 0 으로 온다(둘 다 0 인 줄 1,232) — 0 은 0 으로 둔다(원문). manual 줄의 「없음」은 null.
--    읽는 쪽 폴백 fixed_cost>0 → cost>0 → 없음 이 둘을 같은 「없음」으로 읽는다.
--
-- 담지 않는 것(봤고 비어 있어서) — ProductSupplierOptions 전체(창고별 Lead·Safety·ReorderQuantity 전량 0 · 10,637줄×4 · 제품×공급처×창고 축은 지금 안 만든다) ·
--    SupplierProductName·URL(0) · DropShip(0) · IncludeInPricing(false 0) · PurchaseCost(FixedCost 와 같은 값) · Currency 원문 문자열(공급처 기본통화와 어긋난 줄 0 — 단 currency_id 는 둔다).
--
-- 카운터(적재 뒤 SQL · 평상시 0): ① is_default 둘 이상 ② is_default 못 정함(줄은 있는데) ③ 단가 둘 다 0(실측 1,232) ④ 활성 낱개인데 줄 0(세트·콤보·선주문 제외 뒤)
--    ⑤ 세트·콤보에 붙은 줄(실측 3 — AS92082-6·CRO71964-6·EBI68634-6 · 거르지 않고 넣는다 · Caleb 확인 목록) — 정본 §3-g
-- ─────────────────────────────────────────────────────────────

create table if not exists public.product_supplier (
  -- 공통 칸 (po-module §5 · 관계 표 — name 없음 · cin7_id·is_active 는 축소하지 않는다)
  id            uuid primary key default gen_random_uuid(),
  cin7_id       uuid unique,                           -- ⭐ ProductSupplierID · 충돌 키 · ⑤ PUT 의 필수 열쇠 · manual 줄은 null
  is_active     boolean not null default true,        -- §3-f: 이번 적재에 안 들어온 cin7 줄은 false 로 내린다(지우지 않는다)
  source        text not null default 'cin7',
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  product_id    uuid not null references public.product  (id) on delete no action,
  supplier_id   uuid not null references public.supplier (id) on delete no action,
  supplier_sku  text,                                  -- SupplierInventoryCode (6,981 채움)
  cost          numeric(18,7),                         -- Cost · 최근 매입가(화면 LATEST PRICE) · Cin7 의 없음은 0
  fixed_cost    numeric(18,7),                         -- FixedCost · 합의 고정가(화면 FIXED PRICE) · Cin7 의 없음은 0
  currency_id   uuid references public.ref_currency (id) on delete no action,   -- nullable · 오늘 CAD·USD 만이지만 규칙이 아니다
  last_supplied date,                                  -- LastSupplied · Cin7 이 T00:00:00 시간대 없이 준다 · 99줄 빈값
  is_default    boolean not null default false,        -- ⭐ 우리 칸 · 제품당 하나는 카운터로

  constraint product_supplier_source_ck   check (source in ('cin7', 'manual')),
  constraint product_supplier_natural_key unique (product_id, supplier_id)
);

comment on table  public.product_supplier is 'IMS ④ 제품↔공급처(Cin7 Suppliers[] 대응 · 캐시 아님 · 우리 키 id · cin7_id=ProductSupplierID 가 충돌 키). 낱개에 붙는다(세트는 부모의 것을 pack_factor 로 환산 · 콤보는 사지 않는다). 비활성 공급처 줄도 담는다 — 읽는 쪽이 supplier.is_active 를 건다. 정본 po-module §3-g · 2026-09-14 신설';
comment on column public.product_supplier.cin7_id       is '⭐ Cin7 ProductSupplierID · 충돌 키 · ⑤ PUT /product-suppliers 필수. manual 줄은 null — 같은 (product_id, supplier_id) 가 Cin7 에 나타나면 새 행 대신 이 칸을 채운다(승격 · source 는 manual 유지)';
comment on column public.product_supplier.source        is 'cin7 = 적재가 만든 줄 · manual = 사람이 적은 줄(선주문 등 · 단가 없이도 된다). ⚠️ 재적재 갱신 대상은 source 가 아니라 cin7_id 유무 · manual 줄이 하나라도 있는 제품은 is_default 를 재계산하지 않는다';
comment on column public.product_supplier.supplier_sku  is 'Cin7 SupplierInventoryCode 원문 — 공급처가 부르는 이 제품의 코드(6,981/12,728 채움)';
comment on column public.product_supplier.cost          is 'Cin7 Cost(LATEST PRICE · 최근 매입가) · numeric(18,7) — Cin7 이 소수 일곱 자리를 준다. ⚠️ Cin7 의 「없음」은 0 으로 온다 — 0 은 0 으로 둔다(원문) · 폴백 fixed_cost>0 → cost>0 → 없음';
comment on column public.product_supplier.fixed_cost    is 'Cin7 FixedCost(FIXED PRICE · 합의 고정가) · PurchaseCost 는 같은 값이라 담지 않는다 · ⑤ 발주 단가 폴백의 첫째';
comment on column public.product_supplier.currency_id   is 'FK → ref_currency(id) · nullable · 인덱스 product_supplier_currency_id_idx. 실측 CAD 1,584 · USD 11,144 · 공급처 기본통화와 어긋난 줄 0 — 오늘의 사실이지 규칙이 아니라 칸을 둔다. 못 이은 줄은 null 로 넣고 센다';
comment on column public.product_supplier.last_supplied is 'Cin7 LastSupplied · date — Cin7 이 T00:00:00 로 시간대 없이 준다(시간대 미판정 · registered_on 과 같다). is_default 계산의 기준(활성 공급처 줄 중 가장 최근)';
comment on column public.product_supplier.is_default    is '⭐ Cin7 에 없는 우리 칸 — 기본 공급처. 후보는 supplier.is_active=true 인 줄만 · 하나면 그것 · 둘 이상이면 last_supplied 최근 · 못 가리면 false 로 두고 센다(카운터 ②). ⚠️ 부분 유니크 금지 — 제품당 둘 이상은 카운터 ①(평상시 0)';
comment on column public.product_supplier.note          is '우리가 적는 메모. 재적재가 덮지 않는다';

-- FK 인덱스 — Postgres 는 자동 생성하지 않는다 (§5)
create index if not exists product_supplier_product_id_idx  on public.product_supplier (product_id);
create index if not exists product_supplier_supplier_id_idx on public.product_supplier (supplier_id);
create index if not exists product_supplier_currency_id_idx on public.product_supplier (currency_id);

-- 트리거 — ⚠️ set_updated_at() 은 20260911144606 에 하나뿐. 다시 만들지 마라
create trigger product_supplier_set_updated_at
  before update on public.product_supplier
  for each row execute function public.set_updated_at();

-- RLS
alter table public.product_supplier enable row level security;

create policy auth_all on public.product_supplier
  for all to authenticated using (true) with check (true);

revoke all on public.product_supplier from anon;

-- ⚠️ 마스터가 아니라 관계다 — DELETE 를 막지 않는다(잘못 넣은 연결은 지운다 · supplier_address·product_barcode 선례). TRUNCATE 는 막는다
revoke truncate on public.product_supplier from authenticated;
