-- ─────────────────────────────────────────────────────────────
-- product — IMS ③ 제품 본체 (테스트 DB Asung-IMS)
--
-- 정본: docs/design/po-module.md · 상위 ims-principles.md
-- 실측: 2026-09-13 GAS 프로브(ProbeProduct.gs · ProbeProductChannels.gs)
--       GET /product?IncludeDeprecated=true 전량 18,829 · 83칸 전수
--
-- ⚠️⚠️ 모집단 정정: 정본 §8 의 「product (Total 14,677)」은 활성만 센 숫자였다.
--    전량은 18,829 이고 비활성이 4,152 다. 공급처를 226 으로 알았다가 688 이었던 자리와 같다.
--
-- ⭐ 담는 범위 — Type='Stock' 18,772 에서 대체 바코드를 뺀 것 + AS91437-BLK 1건
--    · 대체 바코드(UOM=EA-ALT-UPC) 62 중 ⭐ BOM Quantity=1 인 59 만 product_barcode 로 흡수한다(18,772 − 59 = 18,713).
--      ⚠️ 셋은 보류(⬜ Caleb 확인) — SIS00522-6(BOM ×6 · 활성) · BOM ×12 1건 · CON00134(부모 없음 · 비활성).
--      대체 UPC 인데 BOM 이 1 이 아니면 「진짜 세트인데 UOM 이름만 잘못 잡힌 것」일 수 있다 — 흡수하면 세트가 사라진다.
--    · 빠지는 57 은 전부 청구서 줄이다(아마존 프렙 12 · 드롭십 3 · 배송비 12 · 회계 조정 7 ·
--      시스템 항목 19 · CREDIT·FINAL-SALE 등). ⑤ PO 의 비용 라인에서 따로 다룬다.
--    · ⚠️ AS91437-BLK(Kim & C Hair Bobby Pin Bulk 50pack/Case)은 Type=Non Inventory 로
--      잘못 앉아 있다. 실물은 AS91437 을 만드는 벌크 자재다 — 기준을 흔들지 않고 손으로 넣는다.
--    · ⚠️ SKU 형식(_숫자_)으로 거르는 것은 전량에서 19건뿐이었다. 표본 30 이 앞쪽에 몰려
--      크게 보였을 뿐, 진짜 기준은 Type 이다.
--
-- ⭐ 조합 형태 넷 (2026-09-13 확정) — 한 행이 여럿에 동시에 걸린다. 「제품 종류」 칸을 만들지 마라.
--    관계 없음    홀로 선다 (family·BOM·구성품·세트의 부모 전부 아님)   4,161  ⚠️ 초안의 13,888 은 「family 아닌 Stock」이었다 — 틀린 수
--    family       색상·사이즈 변형              4,884 변형 / 1,141 군
--    UOM 세트     같은 물건의 다른 포장 단위     구성품 1개인 BOM 6,406 (대체 UPC 61 포함)
--    콤보         다른 물건들을 묶은 것          15  → product_bom
--    ⚠️ [2차 실측 2026-09-13 · Type=Stock 18,772 를 네 축으로 가름] 세 축(family + 구성품 + 세트의 부모)에 동시에 걸리는 것이
--       2,405건 · 두 축 이상 5,758건. 초안은 AS92080 계열 「6건」이라 적었으나 그건 AS-DSPLY 구성품만 센 수였다.
--       ⇒ 예외가 아니라 다수다. 종류 칸을 하나 두고 고르게 했다면 5,758행이 갈 곳을 잃었다
--          (Project Name 한 칸에 단종과 한정판이 같이 살던 그 모양이 된다).
--    ⇒ 종류는 관계가 있느냐 없느냐로 읽는다: family_id · parent_product_id · product_bom 소속
--
-- ⚠️⚠️ name 에 유니크를 걸지 마라 — 실측 576종 중복(ORLY GEL FX 60행 · WELLA 29행).
--    색상·사이즈가 이름에 안 들어가고 SKU 로만 갈린다. 걸면 배치 전체가 막힌다.
--    (ref_account.name 9건 사고와 같은 자리 · 이번엔 규모가 576종이다)
--    📌 화면에서 이름만 보여주면 60줄이 똑같이 보인다 — SKU 를 반드시 같이 띄운다.
--
-- ⚠️ Barcode 를 이 표에 두지 않는다 — 실측 48종 중복 · 대체 UPC 62건이 SKU 로 우회돼 있었다.
--    ⇒ product_barcode 표로 뺀다. Cin7 은 제품당 바코드 칸이 하나라 SKU 를 파야 했지만
--      우리는 줄을 더하면 된다(Caleb 2026-09-13: 앞으로도 화면에서 추가할 수 있어야 한다).
--
-- ⚠️ 계정 넷은 전부 nullable — 실측 채움이 5 · 3 · 1,103 · 870 곳뿐이다.
--    표본 30 에서 「제품이 계정을 넷 참조한다」고 본 것은 착시였다. NOT NULL 을 걸었으면 전부 막혔다.
--    값이 있는 것은 100% 이어진다(못 이은 값 0종).
--
-- 담지 않는 것 (전량 실측 근거)
--    Barcode          → product_barcode 로 뺐다
--    치수 넷          Carton*·Length·Width·Height 전량 0 (Weight 만 값이 있다)
--    PriceTier 1~10   ⬜ SO 모듈. 8단계가 실제로 돌고 이름에 통화가 박혀 있으며(Regular CAD ·
--                     USWholesale USD) 화면의 Markup %·Average cost 계산 규칙이 API 에 없다.
--                     숫자만 베끼면 「왜 이 값인가」가 사라진다.
--    BOM 플래그 다섯  BOMType·BillOfMaterial·AutoAssembly·AutoDisassembly·QuantityToProduce
--                     → 관계는 product_bom 이 갖는다. ⚠️ UOM 세트에도 Assembly 가 켜져 있어
--                       이 칸들로는 콤보를 못 가른다(구성품 2개 이상인가로 가른다).
--    Attachments      이미지 사슬이 따로 있다 (Cin7 → BQ asung_product_images →
--                     wms_sku_snapshot · product-images EF 가 매일 덮는다). 셋째 사본 금지.
--                     📌 2026-09-13 실측: IncludeAttachments=true 는 실제로 먹는다(끄면 빈 배열).
--                        「안 봐서 뺀다」가 아니라 「봤고 다른 데 있어서 뺀다」.
--    Channels         ⚠️ Cin7 이 API 로 주지 않는다. 파라미터 셋·엔드포인트 후보 일곱 모두 실패.
--                     ⚠️⚠️ Cin7 은 없는 경로에 404 가 아니라 200 + HTML 을 준다 —
--                        HTTP 코드로 엔드포인트 존재를 판정하지 마라(2026-09-13 실측).
--    Alternative products · Discounts · Additional descriptions   실무에서 안 쓴다(Caleb)
--    Image(슬롯10)    용도 미상 · 326곳 (Caleb: 작업자 참조용으로 보인다)
--    Bin 슬롯 1·2     ⚠️ 실제 자리이긴 하나 정본이 아니다 — 초반 참고용이고 현재 미사용(Caleb).
--                     8,509곳뿐이고 절반 넘게 비어 있다. 자리의 정본은 Cin7 재고이고
--                     조정 화면은 ref_bin + 원장을 읽는다. ⬜ 기본 자리는 ⑤ 리시빙·풋어웨이에서.
--    값이 하나뿐인 칸  AttributeSet · AlwaysShowQuantity · DropShipMode · DimensionsUnits ·
--                     DefaultLocation · AssemblyCostEstimationMethod (아무것도 구별하지 않는다)
--    전량 null        DiscountRule · WarrantyName · AdditionalAttribute5~9
--    StockLocator 3곳 · ShortDescription 15곳
--    ⬜ 미결: Tags(12,321) · PickZones(7,937) · 재주문점 둘 · CustomPrices · ReorderLevels
-- ─────────────────────────────────────────────────────────────

create table if not exists public.product (
  -- 공통 8칸 (po-module §5)
  id            uuid primary key default gen_random_uuid(),
  cin7_id       uuid unique,
  name          text not null,                      -- ⚠️ 유니크 없음 (576종 중복)
  is_active     boolean not null default true,      -- Cin7 Status='Active'
  source        text not null default 'cin7',
  note          text,                               -- 우리가 적는 메모. 재적재가 덮지 않는다
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- ⭐ 자연키 — 실측 18,829 전수에서 중복 0 · 빈값 0 · 앞뒤공백 0
  sku           text not null unique,

  -- ⭐ family — 변형이 위를 가리킨다. 홀로 선 것이 13,888 이므로 nullable.
  family_id     uuid references public.product_family (id) on delete no action,
  option1_value text,                               -- 옵션 이름은 product_family 에
  option2_value text,
  option3_value text,

  -- ⭐ UOM 세트 — 낱개가 위다. family 와 방향이 반대이고 축이 겹치지 않는다(실측 0건).
  -- ⭐ parent_product_id 의 출처는 BOM 의 ComponentProductID(GUID)다. 접미사로 찾지 마라.
  --    실측(2026-09-13 2차 · IncludeBOM=true 전량): 구성품 1개인 6,406건 전부 부모를 GUID 로 찾았고, 덤프에 없는 건수 0.
  -- ⭐ 카운터 — 평상시 0 이어야 신호가 산다
  --    ① 구성품이 1개인데 그 GUID 가 우리 표에 없음        0
  --    ② 세트의 uom_name(숫자) ≠ pack_factor(BOM)          0  ⚠️ 재고가 조용히 틀어지는 자리
  --    ③ 접미사로 찾은 부모 ≠ BOM 으로 찾은 부모            0
  --    2026-09-13 에 이 셋으로 오류 열 건을 찾았다(SKU 공백 셋 · 자리수 · 글자순서 · BOM 수량 둘 …).
  parent_product_id uuid references public.product (id) on delete no action,
  -- ⭐ pack_factor 의 정본은 BOM Quantity 다 (실측 2026-09-13)
  --    BOM 은 「이 세트 하나를 만들려면 낱개가 몇 개 드는가」이고 Cin7 이 재고를 빼는 것도 BOM 이다.
  --    UOM 이름은 화면 표시일 뿐 — 둘이 어긋나면 화면은 6개라 하고 재고는 1개가 빠진다(에러 없음).
  --    실측: 숫자UOM · BOM · 접미사 셋 일치 6,340 / 어긋남 3
  --      AIA00207-6 · ORS12208-6   UOM=6 인데 BOM=1  ⚠️ 재고가 실제로 어긋나던 자리 (Cin7 수정 완료)
  --      AMP41108-12               UOM·BOM 둘 다 6 · 접미사만 틀렸다
  --    ⚠️ UOM 이름과 접미사는 검산으로만 쓴다.
  pack_factor   numeric,

  -- FK + 원문 병행 — 못 이어도 적재가 멈추지 않는다 (§6)
  brand_id      uuid references public.ref_brand    (id) on delete no action,
  brand_name    text,                               -- ⚠️ 빈값 76곳
  category_id   uuid references public.ref_category (id) on delete no action,
  category_name text,
  unit_id       uuid references public.ref_unit     (id) on delete no action,
  uom_name      text,                               -- 원문 (EA / 6 / 12 / EA-ALT-UPC) · ⚠️ 검산용 — 세트 계수의 정본은 pack_factor(BOM)

  -- ⚠️ 계정 넷 — 전부 nullable (실측 5 · 3 · 1,103 · 870 곳)
  inventory_account_id   uuid references public.ref_account (id) on delete no action,
  inventory_account_code text,
  cogs_account_id        uuid references public.ref_account (id) on delete no action,
  cogs_account_code      text,
  revenue_account_id     uuid references public.ref_account (id) on delete no action,
  revenue_account_code   text,
  expense_account_id     uuid references public.ref_account (id) on delete no action,
  expense_account_code   text,

  -- 세금 규칙 — 원문만. ⬜ ref_tax_rule 미결 (제품 쪽은 각 6곳뿐이라 근거가 약하다)
  purchase_tax_rule text,
  sale_tax_rule     text,

  -- Cin7 값
  cin7_type         text,         -- ⭐ 원문 Stock / Service / Non Inventory. AS91437-BLK(Non Inventory · 실물은 자재)를 손으로 넣으면
                                  --    그 사실이 표에서 사라지면 안 된다. CHECK 없음(Cin7 이 늘릴 수 있다)
  sellable          boolean,      -- ⭐ 원문 보존용. 우리 논리가 이 칸을 읽지 않는다.
                                  --    사실상 「세트인가」의 그림자다 — false × Active 5,879 중 98.7% 가 숫자 UOM(세트)
                                  --    true × Active 의 UOM: EA 8,691 · JAR 62 · DP 41 · 나머지 78곳이 「진짜 안 파는 것」
                                  --    낱개/세트 판정은 pack_factor 와 관계(parent_product_id)로 한다
  costing_method    text,         -- ⚠️ FIFO 하나가 아니다 — Special - Serial Number 가 섞여 있다
  hs_code           text,
  country_of_origin text,
  country_of_origin_code text,
  weight            numeric,
  weight_unit       text,
  cin7_description  text,
  cin7_internal_note text,        -- ⚠️ 우리 note 와 섞지 마라
  cin7_created_on   timestamptz,
  cin7_modified_on  timestamptz,  -- ⭐ 18,829 전수 채움 — 증분 적재가 여기서 실제로 필요해진다

  -- ⭐ 우리 칸 — Cin7 의 이름 없는 슬롯을 뜻 있는 칸으로 갈라 담는다 (ims-principles §4-d)
  -- 슬롯3 'Project Name' 은 이름과 내용이 다르고 한 칸에 세 값이 산다 — 셋 다 「팔 수 있는가」를 말한다(Caleb 2026-09-13):
  --   Discontinued 4,662     더 이상 안 들여온다 · 제품의 성질        → is_discontinued
  --   Limited Edition 42     한정 물량이다 · 제품의 성질              → ⏸ 칸 없음 · cin7_project_name 원문에 남는다
  --   No Channel 74          아직 안 올렸다 · ⚠️ 지금 상태(재고 도착·보류 해제로 풀린다) → ❌ 칸으로 물려받지 않는다
  --   ⚠️ 한정판이면서 단종된 것을 적을 자리가 없다(실물 4건) — 그래서 갈랐다.
  --   ❌ 초안의 product_channel 은 뺐다 — No Channel 은 채널 정보가 아니라 판매 게이트이고 「없음」을 값으로 담는 칸이었다.
  --      진짜 채널 정보는 Cin7 Channels 탭에 살며 API 에 없다. 판매 게이트는 ⑤ 이후 사건으로 만든다(po-module §7).
  is_discontinued   boolean not null default false,
  cin7_project_name text,         -- ⭐ 원문 그대로(116곳) — 우리 해석과 Cin7 표기를 갈라 둔다

  -- 슬롯4 'Registered On' — 612곳
  -- ⚠️ CreatedDate 로 복원되지 않는다: 7할이 다르고 다를 때는 거의 항상 등록이 앞선다
  --    (1~7일 앞 382 · 같은 날 142/612). 프리세일·선등록 때문에 자동 시각과 안 맞는다.
  --    사람이 「이때부터로 치자」고 정해 주는 값인 것이 요점이다 — 사건으로 자동화하지 마라.
  registered_on     date,

  constraint product_source_ck check (source in ('cin7', 'manual'))
);

-- ⚠️ is_discontinued 와 is_active 를 합치지 마라 (실측 근거)
--    Discontinued × Active     1,141   단종 정했는데 재고가 남아 아직 판다
--    Discontinued × Deprecated 3,521   소진되어 내려갔다
--    (빈값) × Deprecated         617   단종 아닌 다른 이유로 내려갔다
--    ⇒ 셋(is_active · is_discontinued · sellable)이 서로를 설명하지 못한다. 각각 다른 사실이다.
--    📌 창고별로 재고가 남았는지는 칸을 더 파서 풀지 않는다 — 원장이 계산해 답한다.

comment on table  public.product is 'IMS ③ 제품 본체. Type=Stock 18,772 − 대체 UPC(BOM=1) 59 = 18,713 + 자재 1건(⬜ 보류 셋). 실측 2026-09-13 · 정본 docs/design/po-module.md §3-d';
comment on column public.product.sku is '자연키. 18,829 전수 중복 0';
comment on column public.product.pack_factor is '세트 계수. ⭐ 정본은 BOM Quantity(Cin7 이 재고를 빼는 수) — UOM 이름·접미사는 검산. 실측 셋 일치 6,340 / 어긋남 3 (2026-09-13)';
comment on column public.product.parent_product_id is '세트→낱개. ⭐ 출처는 BOM ComponentProductID(GUID) — 접미사로 찾지 마라. 대체바코드 흡수 후엔 세트만 남는다';
comment on column public.product.cin7_type is 'Cin7 Type 원문(Stock/Service/Non Inventory). 담는 범위는 Stock + AS91437-BLK(Non Inventory) — 후자가 자재임을 이 칸이 보존한다';
comment on column public.product.sellable is 'Cin7 Sellable 원문 보존용 — 우리 논리가 읽지 않는다. 세트 판정은 pack_factor·parent_product_id';
comment on column public.product.cin7_project_name is '슬롯3 Project Name 원문(Discontinued·Limited Edition·No Channel). is_discontinued 만 승격 · No Channel 은 판매 게이트라 칸으로 물려받지 않는다';
comment on column public.product.is_discontinued is '단종 결정. is_active(목록에서 내렸나)와 별개';
comment on column public.product.registered_on is '우리 목록에 들어온 날. CreatedDate 로 복원 안 된다';

-- FK 인덱스 — Postgres 는 자동 생성하지 않는다 (§5)
create index if not exists product_family_id_idx on public.product (family_id);
create index if not exists product_parent_idx    on public.product (parent_product_id);
create index if not exists product_brand_idx     on public.product (brand_id);
create index if not exists product_category_idx  on public.product (category_id);
create index if not exists product_unit_idx      on public.product (unit_id);
create index if not exists product_inv_acct_idx  on public.product (inventory_account_id);
create index if not exists product_cogs_acct_idx on public.product (cogs_account_id);
create index if not exists product_rev_acct_idx  on public.product (revenue_account_id);
create index if not exists product_exp_acct_idx  on public.product (expense_account_id);

-- 찾기용 — 이름으로 검색하는 화면이 온다(576종 중복이라 SKU 와 함께 쓴다)
create index if not exists product_name_idx on public.product (lower(name));

-- 트리거 — ⚠️ set_updated_at() 은 20260911144606 에 하나뿐. 다시 만들지 마라
create trigger product_set_updated_at
  before update on public.product
  for each row execute function public.set_updated_at();

-- RLS
alter table public.product enable row level security;

create policy auth_all on public.product
  for all to authenticated using (true) with check (true);

revoke all on public.product from anon;

-- ⚠️ 마스터는 지우지 않고 is_active 로 물러나게 한다 (§5)
revoke delete, truncate on public.product from authenticated;
