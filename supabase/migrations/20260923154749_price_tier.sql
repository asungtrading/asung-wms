-- SO 가격표 ① — ref_price_tier · product_price · product.set_discount_pct (2026-09-23 · 파일 시각 UTC)
--
-- 목표: 마이그레이션 1개 · 표 2(ref_price_tier 마스터 · product_price 관계) · 칸 1(product.set_discount_pct + CHECK 둘) · 함수 1(product_price_set_touch 값 변경 감지 트리거) ·
--       ⭐ 티어 여덟 행 seed(on conflict (code) do nothing · source='cin7' · 검토 이견 8) · 가격 줄 적재 0(적재 스크립트 차수). 읽기 함수 없음(⬜5 · 세트 가격 식은 주석으로).
-- 선행: 20260911164513(ref_currency · CAD·USD seed) · 20260913230500(product · parent_product_id · pack_factor · sellable) · 20260917230000·20260918020000(ims_can_write) · 20260918133858(ims_touch · updated_by 규약) ·
--       20260922201223(customer.price_tier 원문 칸) · 20260923133042(so.price_tier 원문 칸). ⚠️ ims_touch() · ims_can_write(text) 는 다시 만들지 않는다(마지막 정의 확인 — ims_can_write 는 20260918020000:99 · 앞 회신의 20260917230000 은 틀린 위치였다).
-- 정본: docs/design/so-module.md §1-j(가격 청취) · 9-c ⬜2(price_tier 원문만 · ref_price_tier 는 가격 계산 전에) · §11(이번 차수 — 만든 뒤 신설) · docs/design/po-module.md §5(공통·관계 표 규약) · 594~606행(sellable 「원문 보존용」).
--       이 파일과 정본이 어긋나면 정본이 이긴다. 지시서 ~/asung/prompts/so-price-1-tables.md · 검토 이견 1~10 · ⬜1~7 은 Caleb 판정(2026-09-23)대로.
--
-- ═══ 실측 (PriceTierProbe.gs · 2026-09-23 토론토 오전 · Caleb 실행 · 제품 18,963 전량 · IncludeBOM=true) ═══
--   티어 목록 GET ref/priceTier → {PriceTiers:[{Code,Name}]} 열 · Code N ↔ PriceTierN ↔ PriceTiers[Name] 100% 일치 · 1 Wholesale · 2 Franchise · 3 AONE · 4 Regular CAD · 5 ComparedPrice CAD · 6 wholesalespecia CAD ·
--     7 USWholesale USD · 8 REFERENCECOST USD · 9 Tier 9 · 10 Tier 10(둘은 전부 0 → 옮기지 않는다).
--   채움(Active Stock 낱개 8,609 · 양수) Wholesale 8,594 · Franchise 8,513 · AONE 8,431 · Regular 8,561 · ComparedPrice 8,423 · wholesalespecia 7,541 · USWholesale 7,492 · REFERENCECOST 168 · 소수 최대 4자리 · ⚠️ 음수 1(Wholesale −0.4 · Active Stock 밖).
--   Sellable  Active Stock 세트 5,832 중 true 1(BEL43475-12 · Wholesale·Franchise·wholesalespecia 16.99 = 낱개 1.39×12=16.68 보다 1.9% 비쌈) · Sellable No 세트의 값은 뜻이 없다(「낱개 한 개 값과 같다」 4,890).
--   손님 원문 price_tier 넷(9-g): Wholesale 7,421 · AONE 2,044 · Regular CAD 2 · USWholesale USD 1 — 티어 이름과 글자 그대로 일치.
--
-- ═══ 청취 (Caleb 2026-09-23 · 정본 §11 에 말 그대로) ═══
--   「지금 cin7에서 가격을 정하는 것은 수동으로 하고 있어. markup %나 average cost가 기능으로 있지만 사용하지 않아.」 ⇒ 숫자가 정본이다 — 제품 차수(20260913230500)가 PriceTier 를 미룬 이유(「계산 규칙이 API 에 없다」)가 풀렸다.
--   「-6, 12등등으로 uom으로 묶여진 세트들은 가격을 안가져와도 돼 … yes로 되어 있는 제품은 실제로 UOM으로 판매를 하고 있는거라 그것은 가격을 가져와야 해」 · 「베이스 가격이 1불이면, -6가 붙은 세트는 6불이야」 · 「uom으로 판매하는 것들은 좀 더 싸게」
--   「comparedPrice CAD와 Wholesalespecia CAD는 샤피파이에 있는 두 스토어때문에 … comparedPrice는 Aone과, wholesalespecia는 Wholesale과 짝」 · Cin7 Shopify 화면: Sale price tier = Wholesale · Compare price tier = wholesalespecia CAD ⇒ wholesalespecia 는 특가가 아니라 비교가.
--
-- ═══ 판정 ①~④ (✅ Caleb 2026-09-23) ═══
--   ① 티어 여덟 · purpose 셋 — sale(Wholesale · Franchise(짐작 · 손님 0) · AONE · Regular CAD · USWholesale USD) · compare(ComparedPrice CAD · wholesalespecia CAD — Shopify 비교가 · 결제에 쓰지 않는다) · reference(REFERENCECOST USD — 참고값).
--      비교가 티어를 손님에게 붙이면 줄 그은 값으로 청구한다 · 안 쓰는 티어도 손으로 넣은 값이라 버리면 되살릴 수 없다. ⭐ Shopify 짝은 티어 표에 두지 않는다 — 스토어 설정이 정한다(연동 차수).
--   ② 세트 할인은 세트마다 하나 — product.set_discount_pct · 모든 티어에 같이. 세트 가격 = 낱개의 그 티어 가격 × pack_factor × (1 − set_discount_pct/100). 손님 기본 할인(§1-k)과 다른 자리(오더 줄에서는 세트 가격 → 손님 할인 순 · 짐작 · 오더 가격 차수).
--   ③ 가격표 = 제품 × 티어 → 가격 한 표 product_price — 낱개: 줄 = 정본 · 세트: 보통 줄 없음 = 계산 · 줄이 있으면 고정가(계산값보다 줄이 이긴다). ⭐ 줄마다 출처(source cin7·formula·manual · 검토 이견 3) · 언제(price_set_at) · 누가(price_set_by).
--   ④ BEL43475-12 는 16.99 고정가 — 세트 줄 셋(Wholesale · Franchise · wholesalespecia CAD) · 나머지 티어는 계산 · 낱개가 바뀌어도 셋은 따라가지 않는다(가격 화면이 「고정가 세트」를 따로 보여야 한다 · 화면 차수).
--   📌 product.sellable 의 첫 사용 — po-module 603행 「원문 보존용 · 우리 논리가 읽지 않는다」는 세트 판정에 쓰지 말라는 뜻이었다. 이번에는 「그 세트를 실제로 파는가 → Cin7 세트 가격을 가져오나」에 적재 스크립트가 읽는다. 표·제약은 이 칸을 참조하지 않는다(정본 §11 뒤집은 것).
--
-- ═══ 검토 이견·⬜ 판정 ═══
--   이견 2  ref_price_tier.currency_id NOT NULL → ref_currency · FK 하나(원문 칸 없음 — Cin7 은 티어 통화를 모른다 · 이름 속 글자일 뿐 · supplier.currency_id 와 같은 자리) · 7·8 = USD · 나머지 여섯 = CAD(IMS 판정 값).
--   이견 3  product_price 는 source 하나 · CHECK 셋(cin7 · formula · manual) · price_source 없음 — 가격 줄은 값이 곧 행이라 「행의 출처」와 「값의 출처」가 갈리지 않는다. 재적재는 source='cin7' 줄만 덮는다 · formula·manual 은 무접촉(판정 ③ 「사람이 고친 값은 덮지 않는다」가 이 칸 하나에 선다). ⚠️ source 어휘가 이 표만 셋이다.
--   이견 4  값 변경 감지 트리거 product_price_set_touch() — 자기 행만 본다 · insert: price_set_at 기본 now() · price_set_by = auth.uid()→ims_staff.id(없으면 null · 적재) · update: price is distinct from old.price 일 때만 둘을 갱신 · 같은 값이면 보낸 대로(둘 다 그대로).
--   이견 5  product.set_discount_pct CHECK 둘 — 0~100 · 낱개 금지 (set_discount_pct is null or parent_product_id is not null) — 양쪽이 is null·is not null 이라 null 을 내지 않는다(§10 머리 규칙) · 세트 판정은 parent_product_id(po-module · sellable·UOM 이름을 안 본다).
--   이견 6  price > 0 — Cin7 의 0 은 「가격 없음」 · 줄을 만들지 않는다 · 0 줄이 「고정가 0」으로 읽혀 세트 계산을 덮는 것을 막는다 · 음수 1건도 막힌다(적재가 건너뛰고 센다) · 샘플 0 단가는 so_line.unit_price 의 일.
--   이견 7  product_price.cin7_id 는 규약대로 두되 늘 null(Cin7 이 가격 칸에 ID 를 주지 않는다 · supplier_discount 선례) · 적재 열쇠는 (product_id, tier_id) plain 유니크.
--   이견 8  티어 여덟 seed 는 이 파일이 넣는다(purpose·currency 는 우리 판정 값 — 스크립트가 Cin7 에서 읽어 낼 수 없다 · ref_currency 선례 20260911164513 60행) · currency_id 는 (select id from ref_currency where code=…) — uuid 를 박지 않는다.
--            ⭐ 가격 적재 스크립트는 티어를 이름이 아니라 code 로 맞춘다 · IMS 에 없는 code 가 오거나 같은 code 의 이름이 다르면 멈춘다(적재 차수 규칙).
--   이견 9  code smallint · 이견 10 Franchise = sale 은 짐작(주석) · ⬜1~7 회신 답 그대로(마스터/관계 규약 · 읽기 함수 없음 · 권한 master · Deprecated 낱개도 옮긴다 — 적재 차수).
--
-- ═══ 공통 규약 확인 (po-module §5 · 20260922201223 · 20260918133858 과 동일한 모양) ═══
--   id uuid PK · cin7_id uuid unique plain · source check <표>_source_ck · FK on delete no action(마스터·관계 표 — cascade 금지) · FK 칸마다 인덱스 <표>_<칸>_idx · updated_by → ims_staff(id) + <표>_updated_by_idx ·
--   트리거 <표>_touch → ims_touch() · RLS select 열림 + insert/update/(delete) = (select ims_can_write('master')) · 정책 이름 <표>_<동사> · revoke all from anon ·
--   마스터(ref_price_tier)는 revoke delete, truncate(정책 셋) · 관계(product_price)는 revoke truncate 만(정책 넷 — 지우면 「계산으로 돌아간다」가 뜻이 된다).
-- ⚠️ begin/commit 없음 — 적용은 psql -v ON_ERROR_STOP=1 -1 -f(한 트랜잭션) + supabase migration repair --status applied <이 파일 시각> (po-module §13-f) — 실행은 Caleb · [테스트 · Asung-IMS].

-- ═══ ① ref_price_tier — 가격 티어 마스터 (판정 ① · 이견 2·9) ═══
create table if not exists public.ref_price_tier (
  id           uuid primary key default gen_random_uuid(),
  cin7_id      uuid unique,
  code         smallint not null unique,
  name         text not null unique,
  purpose      text not null,
  currency_id  uuid not null references public.ref_currency (id) on delete no action,
  is_active    boolean not null default true,
  source       text not null default 'cin7',
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references public.ims_staff (id) on delete no action,
  constraint ref_price_tier_code_ck    check (code between 1 and 10),
  constraint ref_price_tier_purpose_ck check (purpose in ('sale','compare','reference')),
  constraint ref_price_tier_source_ck  check (source in ('cin7','manual'))
);
create index if not exists ref_price_tier_currency_idx   on public.ref_price_tier (currency_id);
create index if not exists ref_price_tier_updated_by_idx on public.ref_price_tier (updated_by);

comment on table  public.ref_price_tier is 'SO 가격 티어 마스터(Cin7 GET ref/priceTier 대응 · Code 1~10 ↔ 제품의 PriceTier1~10 칸 · 실측 2026-09-23 100% 일치) · 여덟 행(Tier 9·10 은 전부 0 → 옮기지 않는다) · purpose 셋(sale · compare · reference) · currency_id 는 IMS 판정 값(Cin7 은 티어 통화를 모른다) · ⭐ Shopify 짝(판매 티어·비교 티어)은 여기 두지 않는다 — 스토어 설정이 정한다(연동 차수) · 마스터 규약(DELETE·TRUNCATE 막음 · is_active 로 물러난다) · 정본 docs/design/so-module.md §1-j · §11 · 2026-09-23 신설';
comment on column public.ref_price_tier.cin7_id     is '규약 칸 · 늘 null — Cin7 은 티어에 GUID 를 주지 않는다(Code 정수만) · 열쇠는 code';
comment on column public.ref_price_tier.code        is '⭐ Cin7 ref/priceTier Code(1~10 · CHECK) · unique · 적재 열쇠 — 가격 적재 스크립트는 티어를 이름이 아니라 code 로 맞춘다 · IMS 에 없는 code 가 오거나 같은 code 의 이름이 다르면 멈춘다(적재 차수 규칙) · 제품 칸 PriceTier<code> 가 이 티어의 값';
comment on column public.ref_price_tier.name        is 'Cin7 티어 이름 원문(unique) · ⚠️ 이름 속 CAD·USD 는 글자일 뿐(§1-j) — 통화는 currency_id · customer.price_tier · so.price_tier 원문이 이 이름과 글자 그대로 맞는다(9-g 넷 실측)';
comment on column public.ref_price_tier.purpose     is '⭐ 쓰임 CHECK 셋 — sale(손님·스토어의 판매 티어가 될 수 있다) · compare(Shopify 비교가 · 결제에 쓰지 않는다 · 손님에게 붙이면 줄 그은 값으로 청구한다) · reference(참고값 · 파는 가격이 아니다) · 판정 ① · Franchise = sale 은 짐작(손님 0 · 이름·값으로 · 첫 손님이 붙을 때 확인)';
comment on column public.ref_price_tier.currency_id is '⭐ FK → ref_currency(id) · NOT NULL · 원문 칸 없음(supplier.currency_id 와 같은 자리) · 인덱스 ref_price_tier_currency_idx · Cin7 은 티어 통화를 모른다(이름 속 글자일 뿐 · §1-j) — IMS 판정 값(Caleb 2026-09-23 · 7 USWholesale USD · 8 REFERENCECOST USD = USD · 나머지 여섯 = CAD) · ⚠️ 손님 통화 ≠ 티어 통화는 막지 않고 알린다 — 오더 가격 차수에서(USD 손님 셋 중 USWholesale 은 하나 · 9-g)';
comment on column public.ref_price_tier.is_active   is '규약 칸 · Cin7 에서 티어가 사라지거나 쓰지 않게 되면 false 로 물러난다(지우지 않는다 — product_price 가 가리킨다)';
comment on column public.ref_price_tier.source      is 'cin7 = Cin7 ref/priceTier 에 있는 티어(seed 여덟 전부) · manual = IMS 가 만든 티어 · CHECK ref_price_tier_source_ck';
comment on column public.ref_price_tier.updated_by  is '마지막으로 고친 사람 → ims_staff(id) · ref_price_tier_touch(ims_touch) · 인덱스 ref_price_tier_updated_by_idx';

-- ═══ ② product_price — 제품 × 티어 → 가격 (판정 ③ · 이견 3·4·6·7) ═══
create table if not exists public.product_price (
  id            uuid primary key default gen_random_uuid(),
  cin7_id       uuid unique,
  is_active     boolean not null default true,
  source        text not null default 'cin7',
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.ims_staff (id) on delete no action,
  product_id    uuid not null references public.product        (id) on delete no action,
  tier_id       uuid not null references public.ref_price_tier (id) on delete no action,
  price         numeric(18,7) not null,
  price_set_at  timestamptz not null default now(),
  price_set_by  uuid references public.ims_staff (id) on delete no action,
  constraint product_price_source_ck        check (source in ('cin7','formula','manual')),
  constraint product_price_price_ck         check (price > 0),
  constraint product_price_product_tier_key unique (product_id, tier_id)
);
create index if not exists product_price_product_idx      on public.product_price (product_id);
create index if not exists product_price_tier_idx         on public.product_price (tier_id);
create index if not exists product_price_price_set_by_idx on public.product_price (price_set_by);
create index if not exists product_price_updated_by_idx   on public.product_price (updated_by);

comment on table  public.product_price is 'SO 가격표 — 제품 × 티어 → 가격 한 표(판정 ③) · 낱개: 줄이 있다 = 정본 가격 · 세트: 보통 줄이 없다 = 계산(낱개의 그 티어 가격 × pack_factor × (1 − product.set_discount_pct/100)) · 줄이 있으면 고정가 — 계산값보다 줄이 이긴다(BEL43475-12 16.99 셋 · 판정 ④) · Cin7 의 0 은 「가격 없음」이라 줄을 만들지 않는다(price > 0) · 관계 표 규약(DELETE 열림 — 지우면 「계산으로 돌아간다」 · TRUNCATE 막음) · ⚠️ 읽기 함수(계산 창구)는 SO 쓰기 차수(⬜5 · 한 창구 원칙 5-f) · 정본 docs/design/so-module.md §11 · 2026-09-23 신설';
comment on column public.product_price.cin7_id      is '규약 칸 · 늘 null — Cin7 은 가격 칸(PriceTier1~10)에 ID 를 주지 않는다(supplier_discount 선례) · 적재 열쇠는 (product_id, tier_id)';
comment on column public.product_price.source       is '⭐ 값을 무엇이 정했나 — CHECK 셋 cin7(Cin7 적재) · formula(가격식 · 다음 차수) · manual(사람) · ⚠️ 이 표만 셋이다(다른 표는 cin7·manual 둘) — 가격 줄은 값이 곧 행이라 「행의 출처」와 「값의 출처」가 갈리지 않는다(검토 이견 3 · price_source 칸을 따로 두지 않았다) · ⭐ 재적재는 source=cin7 줄만 덮는다 · formula·manual 은 무접촉(판정 ③ 「사람이 고친 값은 덮지 않는다」 · 가격식 차수의 「한 번 정해지면 안 바꾼다」·「일괄 재적용 때 사람이 고친 값은 덮지 않는다」가 이 칸에 선다)';
comment on column public.product_price.product_id   is 'FK → product(id) · NOT NULL · on delete no action · 인덱스 product_price_product_idx · 낱개·세트 어느 쪽이든 가리킬 수 있다(세트 줄 = 고정가)';
comment on column public.product_price.tier_id      is 'FK → ref_price_tier(id) · NOT NULL · on delete no action · 인덱스 product_price_tier_idx · unique (product_id, tier_id) 가 적재 열쇠(plain · on_conflict)';
comment on column public.product_price.price        is '가격 · numeric(18,7)(실측 소수 최대 4자리 · po_line.unit_price 와 한 관례) · NOT NULL · CHECK > 0 — Cin7 의 0 은 「가격 없음」이라 줄을 만들지 않는다(0 줄이 「고정가 0」으로 읽혀 세트 계산을 덮는 것을 막는다) · 음수(실물 Wholesale −0.4 1건)도 막힌다 — 적재가 건너뛰고 센다 · 샘플·무상 0 단가는 so_line.unit_price 의 일(5-e) · 통화는 tier 의 currency_id';
comment on column public.product_price.price_set_at is '⭐ 이 가격 값이 정해진 시각(updated_at 과 다르다 — updated 는 행이 아무 이유로든 바뀐 때) · NOT NULL default now() · product_price_set_touch 가 price 가 실제로 바뀔 때만 now() 로 · 같은 값을 다시 써도(재적재) 그대로 · 가격식 차수의 「한 번 정해지면 안 바꾼다」 판정의 근거';
comment on column public.product_price.price_set_by is '이 가격 값을 정한 사람 → ims_staff(id) · nullable · product_price_set_touch 가 auth.uid() → ims_staff.id 로 채운다(화면이 주지 않는다 · anon key 공개) · null = 적재·식(system) · 인덱스 product_price_price_set_by_idx';
comment on column public.product_price.updated_by   is '마지막으로 고친 사람 → ims_staff(id) · product_price_touch(ims_touch) · 인덱스 product_price_updated_by_idx';

-- ═══ ③ product_price_set_touch() — 값 변경 감지 트리거 (이견 4 · 자기 행만 본다 · ⚠️ ims_touch 는 그대로) ═══
-- insert: price_set_at 은 기본값 now() · price_set_by = auth.uid() → ims_staff.id(없으면 null = 적재·system)
-- update: price is distinct from old.price 일 때만 price_set_at = now() · price_set_by = 위와 같이 · 같은 값이면 보낸 대로(둘 다 그대로 — 재적재가 같은 값을 다시 써도 안 바뀐다)
-- 이름 규칙 9-b(<표>_<동작>) · security definer(ims_staff 를 읽는다 · ims_touch 와 같은 이유) · 서브쿼리 별칭 s.(20260918133858 ⚠️ 별칭 규칙)
-- 트리거 이름 순서: product_price_set_touch < product_price_touch — 값 감지가 먼저, updated_at/by 가 뒤(칸이 겹치지 않아 순서에 기대지 않는다)
create function public.product_price_set_touch()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
begin
  if tg_op = 'INSERT' then
    v_staff := (select s.id from public.ims_staff s where s.auth_user_id = auth.uid());
    new.price_set_by := v_staff;                                   -- auth.uid() 가 null(service_role 적재)이면 null = system
    if new.price_set_at is null then new.price_set_at := now(); end if;
    return new;
  end if;
  if new.price is distinct from old.price then
    v_staff := (select s.id from public.ims_staff s where s.auth_user_id = auth.uid());
    new.price_set_at := now();
    new.price_set_by := v_staff;
  end if;
  return new;
end;
$$;
comment on function public.product_price_set_touch() is 'product_price BEFORE INSERT OR UPDATE — 가격 값이 정해진 시각·사람(price_set_at · price_set_by)을 자기 행만 보고 채운다. insert: set_by = auth.uid()→ims_staff.id(없으면 null) · update: price 가 실제로 바뀔 때만 둘을 갱신 · 같은 값이면 보낸 대로. ⚠️ updated_at/by 는 ims_touch 의 일(이 함수가 건드리지 않는다) · 재적재가 같은 값을 다시 써도 price_set_at 이 안 움직인다(검토 이견 4 · 2026-09-23)';
revoke all on function public.product_price_set_touch() from public, anon;

-- ═══ ④ product.set_discount_pct — 세트 할인 하나 (판정 ② · 이견 5) · 선례 20260923012022 의 add column 모양 ═══
alter table public.product add column if not exists set_discount_pct numeric;
alter table public.product
  add constraint product_set_discount_pct_ck      check (set_discount_pct is null or (set_discount_pct >= 0 and set_discount_pct <= 100)),
  add constraint product_set_discount_set_only_ck check (set_discount_pct is null or parent_product_id is not null);
comment on column public.product.set_discount_pct is '⭐ 세트 할인 % · 세트마다 하나 · 모든 티어에 같이 걸린다(판정 ② · Caleb 2026-09-23 「uom으로 판매하는 것들은 좀 더 싸게」) · null = 할인 없음 · 세트 가격 = 낱개의 그 티어 가격 × pack_factor × (1 − set_discount_pct/100) — 계산은 SO 쓰기 차수의 창구(⬜5) · product_price 에 그 세트·티어 줄이 있으면 고정가가 이긴다(판정 ③·④) · CHECK 0~100 · ⚠️ 낱개(parent_product_id null)에는 값이 들어갈 수 없다(product_set_discount_set_only_ck — 양쪽이 null 을 내지 않는 식 · §10 머리) · 손님 기본 할인(customer.discount_pct · §1-k)과 다른 자리 — 오더 줄에서는 세트 가격 → 손님 할인 순(짐작 · 오더 가격 차수)';

-- ═══ 트리거 — <표>_touch → ims_touch()(다시 만들지 않는다) + product_price_set_touch ═══
create trigger ref_price_tier_touch     before update           on public.ref_price_tier for each row execute function public.ims_touch();
create trigger product_price_touch      before update           on public.product_price  for each row execute function public.ims_touch();
create trigger product_price_set_touch  before insert or update on public.product_price  for each row execute function public.product_price_set_touch();

-- ═══ RLS · 권한 — 20260917235000 모양 · 묶음 master(⬜6 · pricing 묶음은 가격식 차수) ═══
alter table public.ref_price_tier enable row level security;
alter table public.product_price  enable row level security;
-- 마스터 — 정책 셋
create policy ref_price_tier_select on public.ref_price_tier for select to authenticated using (true);
create policy ref_price_tier_insert on public.ref_price_tier for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_price_tier_update on public.ref_price_tier for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
-- 관계 표 — 정책 넷(DELETE 열림 — 지우면 「계산으로 돌아간다」)
create policy product_price_select on public.product_price for select to authenticated using (true);
create policy product_price_insert on public.product_price for insert to authenticated with check ((select public.ims_can_write('master')));
create policy product_price_update on public.product_price for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy product_price_delete on public.product_price for delete to authenticated using ((select public.ims_can_write('master')));

revoke all on public.ref_price_tier from anon;
revoke all on public.product_price  from anon;
revoke delete, truncate on public.ref_price_tier from authenticated;   -- 마스터
revoke truncate         on public.product_price  from authenticated;   -- 관계 표 — delete 는 연다

-- ═══ ⑤ 티어 여덟 seed (이견 8 · Cin7 ref/priceTier 실측 2026-09-23 · purpose·currency 는 IMS 판정 값 · 재실행 안전) ═══
-- ⚠️ currency_id 는 조회로 — uuid 를 박지 않는다(테스트·운영이 다르다) · ref_currency 에 CAD·USD 가 없으면 NOT NULL 로 여기서 멈춘다(그것이 맞다)
insert into public.ref_price_tier (code, name, purpose, currency_id, source, note) values
  (1, 'Wholesale',           'sale',      (select id from public.ref_currency where code = 'CAD'), 'cin7', null),
  (2, 'Franchise',           'sale',      (select id from public.ref_currency where code = 'CAD'), 'cin7', 'purpose sale 은 짐작 — 손님 0 · 이름·값으로(Wholesale 과 같다 8,486) · 첫 손님이 붙을 때 확인'),
  (3, 'AONE',                'sale',      (select id from public.ref_currency where code = 'CAD'), 'cin7', null),
  (4, 'Regular CAD',         'sale',      (select id from public.ref_currency where code = 'CAD'), 'cin7', null),
  (5, 'ComparedPrice CAD',   'compare',   (select id from public.ref_currency where code = 'CAD'), 'cin7', 'Shopify 비교가 · AONE 스토어 짝(Caleb) — 짝은 스토어 설정에'),
  (6, 'wholesalespecia CAD', 'compare',   (select id from public.ref_currency where code = 'CAD'), 'cin7', 'Shopify 비교가 · Wholesale 스토어 짝(Cin7 연동 화면 Compare price tier) — 이름과 달리 특가가 아니다'),
  (7, 'USWholesale USD',     'sale',      (select id from public.ref_currency where code = 'USD'), 'cin7', null),
  (8, 'REFERENCECOST USD',   'reference', (select id from public.ref_currency where code = 'USD'), 'cin7', '참고값 · 파는 가격이 아니다 · 값 168/8,609 · 소수 4자리 35개')
on conflict (code) do nothing;

-- 검증(회신 · psql heredoc · begin…rollback · 시퀀스 없음 · 시험마다 어기는 CHECK 하나만): 표 2 · seed 8(Tier 9·10 없음) · 정책 3+4 · 트리거 3 · 함수 1 ·
--   23514(purpose · code 11 · price 0 · set_discount 101 · 낱개에 set_discount) · 23505((product_id, tier_id)) · 트리거(2020 남는가 · 같은 값 그대로 · 다른 값 오늘) · customer.price_tier ⊆ name(기대 0) · anon 0 · 42501(worker 계정 없으면 없다고).
