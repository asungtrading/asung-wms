-- ─────────────────────────────────────────────────────────────
-- product_barcode — IMS ③ 제품 · 바코드 (테스트 DB Asung-IMS)
--
-- 정본: docs/design/po-module.md §3-d · 상위 ims-principles.md
-- 실측: 2026-09-13 · GET /product 전량 18,829 + IncludeMovements 표본 62건 + 2차 IncludeBOM=true 전량(ProbeProductBom.gs)
--
-- ⭐ 왜 표인가 — Cin7 은 제품당 바코드 칸이 **하나뿐**이다. 공급사가 UPC 를 바꾸면
--    새 바코드를 담을 데가 없어서 `…-EA-ALT-UPC` 라는 **SKU 를 파서 우회**해 왔다(62건).
--    우리 표는 그 한계가 없다 — 줄을 하나 더하면 된다.
--    (Caleb 2026-09-13: 앞으로도 화면에서 바코드가 바뀌면 추가할 수 있어야 한다)
--    📌 WMS 는 이미 ALT-UPC 를 「base 에 붙는 별칭 · factor 1」로 조립해 쓴다(WmsSync.js scannable_barcodes) — 그 관행을 데이터로 옮긴다.
--
-- ⭐ 62건을 product 에 담지 않는 근거 — 전수 실측
--      거래(Movements)가 있는 것        0 / 62      ⇐ 합쳐도 과거가 끊기지 않는다
--      부모와 바코드가 다르다           50          ⇐ 우회의 증거
--      부모와 바코드가 같다             12          ⇐ 만들 이유가 없었던 행
--      바코드가 아예 없다                7          ⇐ 바코드용 SKU 인데 바코드가 없다
--    ⚠️ 대조군(AAL19019)은 Movements 1건을 돌려줬다 — 파라미터는 먹었다.
--       「거래 없음」과 「파라미터 안 먹음」을 갈라 놓고 판정했다.
--    ⚠️ CON00134 하나는 부모가 없다(접미사도 없이 UOM 만 EA-ALT-UPC). 비활성 · 손으로 처리.
--
-- ⚠️⚠️ 흡수 대상은 62 가 아니라 59 다 (2차 실측 2026-09-13) — UOM=EA-ALT-UPC 인 61건의 BOM Quantity 가 1 → 59 · 6 → 1 · 12 → 1.
--    BOM 이 1 이 아닌 둘(SIS00522-6 ×6 활성 · ×12 1건)은 「대체 UPC 가 아니라 진짜 세트인데 UOM 이름만 잘못 잡힌 것」일 수 있다.
--    흡수하면 세트가 사라진다. ⇒ 흡수 조건은 「UOM=EA-ALT-UPC **그리고** BOM Quantity=1」. 둘 + CON00134 는 ⬜ Caleb 확인 뒤 판정.
--
-- ⭐ cin7_id 는 여기서 null 이 아니다 — 흡수한 대체 UPC 행은 Cin7 ProductID 를 가진 실물 행이다.
--    재적재의 멱등 키이자 「이 줄이 어느 SKU 에서 왔나」의 추적선. 부모 자신의 Barcode 로 만든 줄은 cin7_id null(제품 행의 cin7_id 는 product 에 있다).
--    사람이 화면에서 더한 줄도 null(source='manual').
--
-- ⭐ valid_from 을 두는 이유 — 공급사가 UPC 를 바꿔도 **옛 바코드를 단 재고가 창고에 남는다.**
--    지우면 그 물건이 스캔되지 않는다. 바코드는 꺼지는 게 아니라 겹쳐 쌓인다.
--    ⇒ 「이때부터 들어온 건 이 바코드」를 날짜로 남긴다. is_active 는 공통 규약대로 두되(§5 관계 표 예외) 「스캔에서 빼고 싶다」는 뜻으로만 쓴다.
--
-- ⚠️ is_primary 에 부분 유니크 인덱스를 걸지 마라 — PostgREST on_conflict 가 깨진다(WMS 규칙 29).
--    대신 「제품당 primary 가 둘 이상인 건수」를 세는 카운터를 화면에 둔다(평상시 0).
--
-- ⚠️ 재적재는 source='cin7' 인 줄만 갱신한다. 사람이 넣은 줄(source='manual')은 건드리지 마라.
--    (공급처에서 cin7_comments 와 note 를 나눠 사람이 쓴 메모를 지킨 것과 같은 방식)
-- ⬜ Barcode 빈값 수 · 중복 48종의 성격(세트·낱개 쌍 / 대체 UPC / 무관)은 미측정 — 무관이면 스캔 화면이 갈라 물어야 한다.
-- ─────────────────────────────────────────────────────────────

create table if not exists public.product_barcode (
  -- 공통 칸 (po-module §5 · 관계 표 — name 없음 · cin7_id·is_active 는 축소하지 않는다)
  id          uuid primary key default gen_random_uuid(),
  cin7_id     uuid unique,                          -- ⭐ 흡수한 대체 UPC 행의 Cin7 ProductID · 그 외 null
  is_active   boolean not null default true,
  source      text not null default 'cin7',
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  product_id  uuid not null references public.product (id) on delete no action,
  barcode     text not null,
  is_primary  boolean not null default false,
  valid_from  date,

  constraint product_barcode_source_ck   check (source in ('cin7', 'manual')),
  constraint product_barcode_natural_key unique (product_id, barcode)
);

comment on table  public.product_barcode is 'IMS ③ 제품 바코드. Cin7 은 제품당 하나라 SKU 로 우회했다(62건 · 흡수는 BOM=1 인 59) — 여기서 줄로 푼다. 정본 po-module §3-d';
comment on column public.product_barcode.cin7_id    is '흡수한 대체 UPC 행(…-EA-ALT-UPC)의 Cin7 ProductID — 재적재 멱등 키 · 추적선. 부모 자신의 바코드 줄·사람이 넣은 줄은 null';
comment on column public.product_barcode.is_primary is '인쇄·표시용 대표. 스캔은 어느 줄이든 맞는다. ⚠️ 부분 유니크 금지 — 제품당 둘 이상은 카운터로(평상시 0)';
comment on column public.product_barcode.valid_from is 'UPC 가 바뀌어도 옛 바코드를 단 재고가 남는다 — 지우지 않고 쌓는다';
comment on column public.product_barcode.note       is '우리가 적는 메모. 재적재가 덮지 않는다';

-- FK 인덱스 — Postgres 는 자동 생성하지 않는다 (§5) · 찾기용 barcode 인덱스(스캔 → 제품)
create index if not exists product_barcode_product_id_idx on public.product_barcode (product_id);
create index if not exists product_barcode_barcode_idx    on public.product_barcode (barcode);

-- 트리거 — ⚠️ set_updated_at() 은 20260911144606 에 하나뿐. 다시 만들지 마라
create trigger product_barcode_set_updated_at
  before update on public.product_barcode
  for each row execute function public.set_updated_at();

-- RLS
alter table public.product_barcode enable row level security;

create policy auth_all on public.product_barcode
  for all to authenticated using (true) with check (true);

revoke all on public.product_barcode from anon;

-- ⚠️ 마스터가 아니라 관계다 — DELETE 를 막지 않는다(잘못 넣은 바코드는 지운다 · supplier_address 선례). TRUNCATE 는 막는다
revoke truncate on public.product_barcode from authenticated;
