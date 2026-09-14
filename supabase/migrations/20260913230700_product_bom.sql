-- ─────────────────────────────────────────────────────────────
-- product_bom — IMS ③ 제품 · 콤보 구성 (테스트 DB Asung-IMS)
--
-- 정본: docs/design/po-module.md §3-d · 상위 ims-principles.md
-- 실측: 2026-09-13 · BOMType=Assembly 6,422 를 전수 갈라 냈다 · 2차(ProbeProductBom.gs · IncludeBOM=true 전량 18,829):
--       구성품 1개 6,406 · 구성품 2개 이상 15 · BOM 없음 12,408 · ComponentProductID 가 덤프에 없음 0
--
-- ⭐ 무엇을 담는가 — **다른 물건들을 묶은 것**만 담는다. 15건 · 구성품 60여 줄.
--      JAL99890~93CB   빗자루 + 쓰레받기 콤보 (색상 4종 · ⚠️ family 에도 속한다)
--      AS-DSPLY        진열대 ×1 + 젤 6종 ×12씩
--      UNF·CVT·ELO…    디스플레이 (립오일·향수 4~8종 ×4~6)
--      ⚠️ ELO82320 은 구성품마다 수량이 다르다(×2 ×3 ×4) — 「몇 개들이」 하나로 못 담는다
--
-- ⚠️⚠️ BOMType 으로 가르지 마라 — 사람이 고르는 값이고(화면 No BOM / Assembly BOM),
--    UOM 을 만들면 Cin7 이 자동으로 Assembly 로 바꾸고 구성품을 채운다.
--    실측 6,422 = 세트 6,343 + 대체바코드 61 + 진짜 조립 15 + 기타 3
--      ABC59139-12  → ABC59139 ×12   UOM 세트 (구성품 1개 · 수량 N)   → product.parent_product_id + pack_factor
--      ADA96563-…   → ADA96563 ×1    대체 바코드 (구성품 1개 · 수량 1) → product_barcode
--      JAL99891CB   → 둘 ×1 ×1        ⭐ 진짜 조립                      → 이 표
--    ⇒ 가르는 기준은 **구성품이 2개 이상인가**다.
--    ⭐ 구성품 1개인 BOM 은 이 표에 넣지 않는다 — 그 관계는 product.parent_product_id(ComponentProductID) 와 pack_factor(Quantity) 가 갖는다.
--
--    📌 [실사고 2026-09-13] 처음에 표본 20개를 SKU 순 앞에서부터 집었더니 전부 …-12 꼴이라
--       「조립 = 세트의 구현」으로 판정하고 BOM 축을 통째로 뺄 뻔했다. 실물이 있었다.
--       ⇒ 정렬된 목록의 앞쪽만 보면 특정 부류에 몰린다. 표본은 흩어 뽑아라.
--
-- ⭐ 중첩 없음 — 구성품 중 BOMType=Assembly 인 것이 0건이다. 펼치면 한 단계로 끝난다.
-- ⭐ 구성품이 덤프에 없는 것 0건 — FK 가 전부 이어진다(2차 실측으로 재확인).
-- ⚠️ 15건 전부 AutoAssembly=true · AutoDisassembly=false — 묶이되 풀리지 않는다
--    (UOM 세트는 둘 다 true 라 정반대다).
-- ⬜ 구성품 0인 채 Assembly 로 둔 것 1건 — Cin7 에서 확인 필요.
--
-- ⚠️ Production BOM · Make-to-order BOM 은 화면 드롭다운에 있으나 전량 실측 0건이다.
--    우리는 안 쓴다. 나중에 생기면 이 표가 못 받는다는 뜻이기도 하다.
--
-- ⚠️ cin7_id 는 항상 null 이다 — Cin7 BOM 원소(BillOfMaterialsProducts[])에는 자기 ID 가 없다(ComponentProductID 만).
--    그래도 공통 규약대로 둔다(supplier_discount 「항상 null 이지만 규약대로」 · §5 관계 표 예외). 재적재 키는 (parent_product_id, component_product_id).
-- ─────────────────────────────────────────────────────────────

create table if not exists public.product_bom (
  -- 공통 칸 (po-module §5 · 관계 표 — name 없음 · cin7_id·is_active 는 축소하지 않는다)
  id           uuid primary key default gen_random_uuid(),
  cin7_id      uuid unique,                         -- ⚠️ 항상 null — Cin7 BOM 원소에 ID 가 없다
  is_active    boolean not null default true,
  source       text not null default 'cin7',
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  -- ⭐ 콤보 하나에 구성품 여럿 · 같은 구성품이 여러 콤보에 들어갈 수 있다
  parent_product_id    uuid not null references public.product (id) on delete no action,
  component_product_id uuid not null references public.product (id) on delete no action,
  quantity             numeric not null,

  -- Cin7 값 (원소의 칸: ComponentProductID · ProductCode · Name · Quantity ·
  --          WastagePercent · WastageQuantity · CostPercentage)
  wastage_percent  numeric,
  wastage_quantity numeric,
  cost_percentage  numeric,   -- ⬜ 실측 0 과 100 둘뿐. 쓰임은 ⑤ 이후에 정한다

  constraint product_bom_source_ck    check (source in ('cin7', 'manual')),
  constraint product_bom_quantity_ck  check (quantity > 0),
  constraint product_bom_natural_key  unique (parent_product_id, component_product_id),
  constraint product_bom_not_self     check (parent_product_id <> component_product_id)
);

comment on table  public.product_bom is 'IMS ③ 콤보 구성. 다른 물건들을 묶은 것만(구성품 2개 이상). 실측 15건(2026-09-13). 구성품 1개인 BOM(세트·대체 UPC)은 여기 없다 — product.parent_product_id·product_barcode. 정본 po-module §3-d';
comment on column public.product_bom.quantity  is '구성품마다 다를 수 있다(ELO82320: ×2 ×3 ×4) · > 0 CHECK';
comment on column public.product_bom.cin7_id   is '⚠️ 항상 null — Cin7 BOM 원소에 자기 ID 가 없다. 공통 규약대로 둔다. 재적재 키는 (parent_product_id, component_product_id)';
comment on column public.product_bom.note      is '우리가 적는 메모. 재적재가 덮지 않는다';

-- FK 인덱스 — Postgres 는 자동 생성하지 않는다 (§5)
create index if not exists product_bom_parent_product_id_idx    on public.product_bom (parent_product_id);
create index if not exists product_bom_component_product_id_idx on public.product_bom (component_product_id);

-- 트리거 — ⚠️ set_updated_at() 은 20260911144606 에 하나뿐. 다시 만들지 마라
create trigger product_bom_set_updated_at
  before update on public.product_bom
  for each row execute function public.set_updated_at();

-- RLS
alter table public.product_bom enable row level security;

create policy auth_all on public.product_bom
  for all to authenticated using (true) with check (true);

revoke all on public.product_bom from anon;

-- ⚠️ 마스터가 아니라 관계다 — DELETE 를 막지 않는다(supplier_address 선례). TRUNCATE 는 막는다
revoke truncate on public.product_bom from authenticated;
