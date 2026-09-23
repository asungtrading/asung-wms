-- SO 할인 규칙 ②-0a — 제품 태그 · 딜 표 넷 · 계산 함수 둘 · so/so_line 새 칸 · set_discount_pct 뜻 좁힘 (2026-09-23 · 파일 시각 UTC)
-- 지시서 ~/asung/prompts/so-deal-1.md · 판정 Caleb 2026-09-23(D1~D9 · 회신 이견 1~14 · 판정 2·3 · ⬜1~⬜8) · 정본 docs/design/so-module.md §13(신설 · 말만)
-- 바탕: 20260913230500(product · brand_id · parent_product_id · pack_factor) · 20260922201223(customer) · 20260923133042(so · so_line) ·
--       20260923154749(product_price · set_discount_pct · 마스터/관계 표 정책 선례) · 20260923182231(ims_perm_catalog 마지막 정의 :19 · so_price_for) · 20260918133858(ims_touch)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음)
--
-- ⭐ 무엇을 만드나(⬜7 — 둘로 나눈 앞쪽 · 창구 끼우기·다시 매기기 창구·검증 창구는 ②-0b)
--    ① product_tag                 제품 태그(D4 · 1,245종 전부 옮긴다 · IMS 에서 붙이고 뗀다) — 관계 표 규약(product_barcode 결)
--    ② so_deal                     딜 머리(D1·D2 · 두 층을 한 층으로 — 할인 「틀」 표 없음 · % 는 줄에) · 오더 전체 딜은 order_pct(이견 6) — 마스터 규약
--    ③ so_deal_customer            고른 손님(customer_scope='selected')
--    ④ so_deal_line                딜 줄 — % · 몇 개 이상(none | qty N | case = 그 낱개의 켜진 세트 중 가장 작은 계수 · D3)
--    ⑤ so_deal_target              걸기(include: tag | brand | product) · 빼기(exclude: tag | product — 브랜드 빼기 없음 · D2)
--    ⑥ 문지기 둘                    오더 전체 딜은 줄이 없다(so_deal_line BEFORE INSERT/UPDATE · so_deal BEFORE UPDATE)
--    ⑦ so_deal_best(product, customer, qty, on)  줄 딜 계산 창구 하나 → (pct, deal_id, line_id) · 걸기 ∧ ¬빼기 ∧ 수량 기준 → 가장 큰 % 하나(D5)
--    ⑧ so_order_discount(so_id)                  오더 전체 딜 → (pct, deal_id) · 제품 줄 합계에 한 번(D6 · 운임 제외)
--    ⑨ so.order_discount_pct · order_discount_deal_id · order_discount_source(⬜4) · so_line.discount_source · deal_line_id(판정 2)
--    ⑩ product.set_discount_pct 주석 — 뜻을 좁힌다(D8 · 11-c 판정 ② 뒤집음 · 칸은 그대로 · so_price_for 의 set_calc 식도 그대로)
--    ⑪ ims_perm_catalog master 라벨에 product tags · deals(재발행 · 마지막 정의 20260923182231:19 · 바뀐 줄 1)
--
-- ⭐ 쓰기 방식(⬜5 · Caleb 판정) — 딜·태그 쓰기 = master · RLS 쓰기 정책(product_price 20260923154749:159~166 선례) · 창구는 화면 차수
--    ⚠️ 거래 표 넷(so · so_line · so_charge · so_reserve)의 「창구만」(12-b 판정 5)과 다른 이유: 딜·태그는 마스터(설정)다 — 화면 사고가 난 자리는 거래 상태 전이였고,
--       표 사이 규칙은 이견 6(order_pct)으로 트리거 하나에 들어갔다 · 적재는 service_role 이라 창구를 타지 않는다 · 900행 한도(⬜7)
-- ⭐ 할인 계산 규칙(D5 · SO-10842 실물 · RON01624 21% 가 손님 기본 7% 를 대신했다 — 28 이 아니다)
--    줄 할인 = greatest(손님 기본, so_deal_best(…).pct) — 더하지 않는다 · 그 식은 so_line_quote(②-0b) · 이 파일은 so_deal_best 까지
--    오더 전체 할인 = round(제품 줄 합계 × pct/100, 2) — SO-10842: 9,249.51 × 5% = −462.4755 → −462.48 · Freight 174.26 은 기준에 없다(D6)
--    기간은 오더 날짜(so.order_date)로 판정한다(D7) · 같은 SKU 두 줄(p_force_new)은 줄마다 따로 판정(이견 8 · mix & match 없음)
-- ⚠️ 다시 만들지 않은 것: ims_touch() 20260918133858:41 · ims_can_write() 20260918020000:99 · so_price_for 20260923182231:135 · so_line_quote(②-0b 에서 drop 뒤 새 시그니처)
-- ⚠️ 시퀀스 무접촉 · seed 없음(딜·태그 적재는 적재 차수 · ⬜8) · 검증 heredoc 은 회신에(시험 딜·태그·가짜 직원은 트랜잭션 안에서만)

-- ═══ ① product_tag — 제품 태그 (D4 · 관계 표 규약: 공통 7칸 · cin7_id 늘 null · DELETE 열림 · TRUNCATE 막음) ═══
-- 태그는 글자 그대로(이견 13 · 대소문자만 다른 짝은 적재가 멈추고 보고한다) · 앞뒤 공백 없음 · 빈 문자열 없음
create table if not exists public.product_tag (
  id           uuid primary key default gen_random_uuid(),
  cin7_id      uuid unique,
  source       text not null default 'cin7',
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references public.ims_staff (id) on delete no action,
  product_id   uuid not null references public.product (id) on delete no action,
  tag          text not null,
  constraint product_tag_source_ck       check (source in ('cin7','manual')),
  constraint product_tag_tag_ck          check (tag = btrim(tag) and tag <> ''),
  constraint product_tag_product_tag_key unique (product_id, tag)
);
create index if not exists product_tag_product_idx    on public.product_tag (product_id);
create index if not exists product_tag_tag_idx        on public.product_tag (tag);
create index if not exists product_tag_updated_by_idx on public.product_tag (updated_by);

comment on table  public.product_tag is '제품 태그(SO 할인 규칙 ②-0a · D4) — Cin7 Tags 1,245종 전부 옮긴다(케이스 태그 GM|HS<%>UOM<수량> 1,217 제품 · DISC_YesSale 645 · Clearance 473 · ASS·AOS·EDM_NoSale … · Shopify 쪽 쓰임도 있다) · IMS 에서 붙이고 뗀다(source manual) · 딜 줄이 태그로 건다(so_deal_target target=tag · 글자 그대로 일치) · 관계 표 규약(DELETE 열림 — 태그를 떼면 줄을 지운다 · TRUNCATE 막음) · 정본 docs/design/so-module.md §13 · 2026-09-23 신설';
comment on column public.product_tag.cin7_id    is '규약 칸 · 늘 null — Cin7 은 태그에 GUID 를 주지 않는다(제품 Tags 는 콤마 문자열) · 적재 열쇠는 (product_id, tag)';
comment on column public.product_tag.source     is 'cin7 = Cin7 제품 Tags 에서 옮긴 줄(재적재가 덮는다 · Cin7 에서 떼면 지운다) · manual = IMS 에서 붙인 태그(재적재 무접촉) · CHECK product_tag_source_ck';
comment on column public.product_tag.product_id is 'FK → product(id) · NOT NULL · on delete no action · 인덱스 product_tag_product_idx · unique (product_id, tag) 가 적재 열쇠';
comment on column public.product_tag.tag        is '⭐ 태그 글자 그대로(대소문자 포함 · 이견 13 · 대소문자만 다른 짝은 적재가 멈추고 보고) · CHECK 앞뒤 공백 없음·빈 문자열 없음 · 인덱스 product_tag_tag_idx(딜 미리 보기 「이 태그의 제품」) · 케이스 태그 GM20UOM12 = General Merchandise · 20% · 12개 이상(Caleb 2026-09-23 「GM과 HS는 우리가 약속하고 쓰는 약어야」)';
comment on column public.product_tag.updated_by is '마지막으로 고친 사람 → ims_staff(id) · product_tag_touch(ims_touch) · 인덱스 product_tag_updated_by_idx';

-- ═══ ② so_deal — 딜 머리 (D1·D2·D6·D7 · 이견 1·6 · 마스터 규약: name · is_active · DELETE 없음 · TRUNCATE 막음) ═══
-- 두 층(Product Discounts 48 · Deals 26)을 한 층으로 — % 는 줄(so_deal_line.pct)에 · 오더 전체 딜은 줄이 없고 order_pct 하나(이견 6)
-- 기간 date_from · date_to 둘 다 선택(null = 열림) · 판정은 오더 날짜(D7) · 기한이 지나도 is_active 는 그대로일 수 있다(Cin7 실물 — 날짜가 정한다)
-- coupon_code 는 원문 칸 — 계산에 쓰지 않는다(이견 1 · Caleb 「지금은 가야. 그런데 나중에는 손님이 쿠폰 코드를 넣으면 되게 하고 싶어」 · 코드 방식은 Shopify 연동 차수)
create table if not exists public.so_deal (
  id              uuid primary key default gen_random_uuid(),
  cin7_id         uuid unique,
  name            text not null,
  is_active       boolean not null default true,
  source          text not null default 'cin7',
  note            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  updated_by      uuid references public.ims_staff (id) on delete no action,
  date_from       date,
  date_to         date,
  customer_scope  text not null default 'all',
  is_order_level  boolean not null default false,
  order_pct       numeric,
  coupon_code     text,
  constraint so_deal_source_ck         check (source in ('cin7','manual')),
  constraint so_deal_name_ck           check (name = btrim(name) and name <> ''),
  constraint so_deal_dates_ck          check (date_from is null or date_to is null or date_from <= date_to),
  constraint so_deal_customer_scope_ck check (customer_scope in ('all','selected')),
  constraint so_deal_order_pct_ck      check (order_pct is null or (order_pct > 0 and order_pct <= 100)),
  constraint so_deal_order_pct_pair_ck check (is_order_level = (order_pct is not null)),
  constraint so_deal_coupon_code_ck    check (coupon_code is null or (coupon_code = btrim(coupon_code) and coupon_code <> ''))
);
create index if not exists so_deal_updated_by_idx on public.so_deal (updated_by);

comment on table  public.so_deal is '⭐ SO 딜(할인 규칙 ②-0a · D1·D2) — Cin7 의 두 층(Product Discounts 「얼마나」 · Deals 「누구에게·언제·무엇에」)을 한 층으로: 딜 = 이름 · 기간 · 켜짐 · 대상 손님(all | selected → so_deal_customer) · 줄(so_deal_line · % · 걸기·빼기 · 몇 개 이상). 오더 전체 딜(D6 · Extra 5%·10% Google Review Promo)은 is_order_level + order_pct 하나 · 줄이 없다(문지기 so_deal_line_order_level_guard) · 제품 줄 합계 × pct 한 번 · 세금 전 · 운임(so_charge) 제외. 기간 판정은 so.order_date(D7). SO 모듈 소유 마스터(9-b · 컷오버 때 지우지 않는다) · 쓰기 = master RLS(⬜5 · 거래 표 넷의 「창구만」과 다른 이유는 정본 §13) · 정본 docs/design/so-module.md §13 · 2026-09-23 신설';
comment on column public.so_deal.cin7_id        is 'Cin7 Deals Export 의 TaskID(GUID) — 적재 열쇠(upsert) · manual 딜은 null';
comment on column public.so_deal.name           is '딜 이름 원문(Cin7 DealName · 예 Sale: Monthly_September_2026 · UOM Discount) · 유니크 아님(Cin7 이 보장하지 않는다) · CHECK 앞뒤 공백 없음';
comment on column public.so_deal.is_active      is '켜짐 — ⚠️ Cin7 실물: 기한이 지난 딜도 IsActive True 로 남는다(4·5월 세일) — 실제로 거는지는 날짜(date_from·date_to)가 정한다 · so_deal_best·so_order_discount 는 둘 다 본다';
comment on column public.so_deal.source         is 'cin7 = Deals Export 에서 옮긴 딜 · manual = IMS 에서 만든 딜 · CHECK so_deal_source_ck';
comment on column public.so_deal.date_from      is '시작(포함) · null = 처음부터 · ⭐ 판정 기준은 오더 날짜 so.order_date(D7 · Caleb 「오더 날짜로 해야지」) — 줄을 넣은 날이 아니다 · CHECK date_from <= date_to(둘 다 있을 때)';
comment on column public.so_deal.date_to        is '끝(포함) · null = 끝없음 · 세일이 끝난 뒤 넣은 줄은 경고 deal_ended_before_line_added(②-0b so_line_quote 쪽)';
comment on column public.so_deal.customer_scope is 'all = 모든 손님(Export 90줄) · selected = so_deal_customer 목록의 손님만(7줄 · Hera Beauty 18곳 · PZ Wholesale · Google Review 23곳·10곳) · CHECK 둘 · ⚠️ selected 인데 목록이 비면 아무에게도 걸리지 않는다(막지 않는다 — 안전한 쪽) · 손님 태그 범위는 옮기지 않는다(D9 · 실물 0)';
comment on column public.so_deal.is_order_level is '⭐ true = 오더 전체 딜(D6 · Cin7 EntireOrder) — 줄 할인이 끝난 제품 줄 합계에 한 번 더 · 세금 전 · 운임 제외 · 줄(so_deal_line)이 없다(문지기) · order_pct 와 짝(so_deal_order_pct_pair_ck) · 계산은 so_order_discount(so_id)';
comment on column public.so_deal.order_pct      is '오더 전체 할인 %(is_order_level 일 때만 · 짝 CHECK · 0 < pct <= 100) · SO-10842 실물: 제품 줄 합계 9,249.51 × 5% = −462.4755 → 합계 −462.48 = round(합계 × pct/100, 2) · Freight 174.26 은 기준에 없다';
comment on column public.so_deal.coupon_code    is '원문 칸(Cin7 CouponCodes · EXTRA10 · EXTRA5) — ⚠️ 계산에 쓰지 않는다: 지금은 대상 손님 목록이면 자동(Caleb 2026-09-23 「지금은 가야」) · 손님이 코드를 넣는 방식은 Shopify 연동 차수 · SO-10842 화면 「Coupon EXTRA5 (…)」는 자동인지 입력인지 화면만으로 모른다';
comment on column public.so_deal.updated_by     is '마지막으로 고친 사람 → ims_staff(id) · so_deal_touch(ims_touch) · 인덱스 so_deal_updated_by_idx';

-- ═══ ③ so_deal_customer — 고른 손님 (D2 · 관계 표 규약) ═══
create table if not exists public.so_deal_customer (
  id           uuid primary key default gen_random_uuid(),
  cin7_id      uuid unique,
  source       text not null default 'cin7',
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references public.ims_staff (id) on delete no action,
  deal_id      uuid not null references public.so_deal  (id) on delete no action,
  customer_id  uuid not null references public.customer (id) on delete no action,
  constraint so_deal_customer_source_ck         check (source in ('cin7','manual')),
  constraint so_deal_customer_deal_customer_key unique (deal_id, customer_id)
);
create index if not exists so_deal_customer_deal_idx       on public.so_deal_customer (deal_id);
create index if not exists so_deal_customer_customer_idx   on public.so_deal_customer (customer_id);
create index if not exists so_deal_customer_updated_by_idx on public.so_deal_customer (updated_by);

comment on table  public.so_deal_customer is '딜의 고른 손님(customer_scope=selected 일 때 · D2) · unique (deal_id, customer_id) · 적재는 Cin7 CustomerName 콤마 목록을 customer.name 글자 그대로로 맞춘다(⚠️ customer.name 은 유니크가 아니다 — 겹치면 멈춤 · ⬜8) · 관계 표 규약(DELETE 열림 · TRUNCATE 막음) · 2026-09-23 신설';
comment on column public.so_deal_customer.cin7_id     is '규약 칸 · 늘 null — Cin7 은 딜-손님 짝에 ID 를 주지 않는다';
comment on column public.so_deal_customer.deal_id     is 'FK → so_deal(id) · NOT NULL · on delete no action · 인덱스 so_deal_customer_deal_idx · ⚠️ 부모가 customer_scope=all 이면 줄은 뜻이 없다(막지 않는다)';
comment on column public.so_deal_customer.customer_id is 'FK → customer(id) · NOT NULL · on delete no action · 인덱스 so_deal_customer_customer_idx(so_deal_best·so_order_discount 가 손님으로 찾는다)';
comment on column public.so_deal_customer.updated_by  is '마지막으로 고친 사람 → ims_staff(id) · so_deal_customer_touch(ims_touch)';

-- ═══ ④ so_deal_line — 딜 줄 (D2·D3 · 관계 표 규약) ═══
-- 몇 개 이상: none(수량 무관) · qty(min_qty 이상) · case(그 낱개의 켜진 세트 중 가장 작은 pack_factor 이상 · 세트가 없으면 걸리지 않는다)
-- ⚠️ D3: case 줄은 미리 보기 화면(걸리는 제품 N · 지금 할인 없는 M · 다른 % 태그 K · 뺀 제품)이 서기 전에는 만들지 않는다 — 표만 둔다 · Cin7 UOM Discount 25줄은 qty 모드(이견 11 · 단계 할인 SPR07301 12→10% · 144→15%)
create table if not exists public.so_deal_line (
  id            uuid primary key default gen_random_uuid(),
  cin7_id       uuid unique,
  source        text not null default 'cin7',
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.ims_staff (id) on delete no action,
  deal_id       uuid not null references public.so_deal (id) on delete no action,
  line_no       integer not null,
  pct           numeric not null,
  min_qty_mode  text not null default 'none',
  min_qty       numeric,
  constraint so_deal_line_source_ck        check (source in ('cin7','manual')),
  constraint so_deal_line_line_no_ck       check (line_no >= 1),
  constraint so_deal_line_pct_ck           check (pct > 0 and pct <= 100),
  constraint so_deal_line_min_qty_mode_ck  check (min_qty_mode in ('none','qty','case')),
  constraint so_deal_line_min_qty_ck       check (min_qty is null or min_qty > 0),
  constraint so_deal_line_min_qty_pair_ck  check ((min_qty_mode = 'qty') = (min_qty is not null)),
  constraint so_deal_line_deal_line_no_key unique (deal_id, line_no)
);
create index if not exists so_deal_line_deal_idx       on public.so_deal_line (deal_id);
create index if not exists so_deal_line_updated_by_idx on public.so_deal_line (updated_by);

comment on table  public.so_deal_line is '⭐ 딜 줄(D2·D3) — % 하나 · 몇 개 이상(none | qty N | case) · 범위는 so_deal_target(걸기·빼기). 판정 = 「걸기에 들고 · 빼기에 없고 · 그 줄(같은 SKU 한 줄)의 수량이 기준 이상」(D5 · mix & match 없음 · 같은 SKU 두 줄은 줄마다 따로 · 이견 8) · 한 제품에 여러 줄이 걸리면 가장 큰 % 하나(so_deal_best · 더하지 않는다) · ⚠️ 오더 전체 딜(is_order_level)에는 줄을 넣을 수 없다(so_deal_line_order_level_guard) · Cin7 Product Discount 「틀」은 표로 두지 않는다(D1 · 쓰이는 틀이 사실상 「몇 %」뿐 · 금액·가산·덮어쓰기는 옮기지 않는다 D9) · 2026-09-23 신설';
comment on column public.so_deal_line.cin7_id      is '규약 칸 · 늘 null — Cin7 Export 는 딜 줄에 ID 를 주지 않는다(TaskID 는 딜 머리)';
comment on column public.so_deal_line.deal_id      is 'FK → so_deal(id) · NOT NULL · on delete no action · 인덱스 so_deal_line_deal_idx · unique (deal_id, line_no)';
comment on column public.so_deal_line.line_no      is '딜 안 차례(1부터 · CHECK) · unique (deal_id, line_no)';
comment on column public.so_deal_line.pct          is '⭐ 할인 % · NOT NULL · CHECK 0 < pct <= 100 · 실물 전부 %(5·10·12·15·20·21·25·30·40·50) · 줄 할인 = greatest(손님 기본 so.discount_pct, 이 값) — 더하지 않는다(12-b 판정 4 · SO-10842 RON01624 21% ≠ 28%)';
comment on column public.so_deal_line.min_qty_mode is '몇 개 이상 — none = 수량 무관(Discount N% 딜 전부) · qty = min_qty 이상(UOM Discount 25줄 · GM20UOM12 → 12) · case = 그 낱개의 켜진 세트 중 가장 작은 pack_factor 이상(세트 없으면 걸리지 않는다) · ⚠️ case 줄은 미리 보기 화면 뒤에(D3) · CHECK 셋';
comment on column public.so_deal_line.min_qty      is 'qty 모드의 기준 수량(판매 단위 · 그 줄 qty_ordered 와 비교) · 짝 CHECK so_deal_line_min_qty_pair_ck: (mode = qty) = (min_qty 있음) — none·case 에는 없다 · CHECK > 0';
comment on column public.so_deal_line.updated_by   is '마지막으로 고친 사람 → ims_staff(id) · so_deal_line_touch(ims_touch)';

-- ═══ ⑤ so_deal_target — 걸기 · 빼기 (D2 · 관계 표 규약) ═══
-- include: tag | brand | product(섞어도) · exclude: tag | product(브랜드 빼기 없음 · CHECK) · 값 칸 셋 중 target 과 맞는 하나만(CHECK) · 중복은 전체 유니크 하나(nulls not distinct · ⚠️ 부분 유니크 금지 — asung-wms 규칙 29 · PostgREST on_conflict 가 WHERE 붙은 유니크를 못 쓴다 · 2026-07-29 실사고 · PostgreSQL 15 부터)
create table if not exists public.so_deal_target (
  id          uuid primary key default gen_random_uuid(),
  cin7_id     uuid unique,
  source      text not null default 'cin7',
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.ims_staff (id) on delete no action,
  line_id     uuid not null references public.so_deal_line (id) on delete no action,
  kind        text not null,
  target      text not null,
  tag         text,
  brand_id    uuid references public.ref_brand (id) on delete no action,
  product_id  uuid references public.product   (id) on delete no action,
  constraint so_deal_target_source_ck  check (source in ('cin7','manual')),
  constraint so_deal_target_kind_ck    check (kind in ('include','exclude')),
  constraint so_deal_target_target_ck  check (target in ('tag','brand','product')),
  constraint so_deal_target_value_ck   check (
       (target = 'tag'     and tag is not null and brand_id is null     and product_id is null)
    or (target = 'brand'   and tag is null     and brand_id is not null and product_id is null)
    or (target = 'product' and tag is null     and brand_id is null     and product_id is not null)),
  constraint so_deal_target_tag_ck     check (tag is null or (tag = btrim(tag) and tag <> '')),
  constraint so_deal_target_exclude_ck check (kind = 'include' or target <> 'brand'),
  constraint so_deal_target_uq         unique nulls not distinct (line_id, kind, target, tag, brand_id, product_id)
);
create index if not exists so_deal_target_line_idx       on public.so_deal_target (line_id);
create index if not exists so_deal_target_tag_idx        on public.so_deal_target (tag);
create index if not exists so_deal_target_brand_idx      on public.so_deal_target (brand_id);
create index if not exists so_deal_target_product_idx    on public.so_deal_target (product_id);
create index if not exists so_deal_target_updated_by_idx on public.so_deal_target (updated_by);

comment on table  public.so_deal_target is '⭐ 딜 줄의 범위(D2) — kind include(걸기: tag | brand | product · 섞어도) · exclude(빼기: tag | product · ⚠️ 브랜드 빼기 없음 so_deal_target_exclude_ck) · 값 칸 셋(tag · brand_id · product_id) 중 target 과 맞는 하나만(so_deal_target_value_ck) · 같은 줄·같은 kind 에 같은 값은 한 번(so_deal_target_uq · unique nulls not distinct 여섯 칸 — 값 칸 셋 중 둘은 늘 null 이라 nulls not distinct 가 필요하다 · 부분 유니크 금지 규칙 29) · 브랜드는 product.brand_id(FK) 로 맞춘다(⬜2 · brand_name 원문 아님 — 빈 76곳은 브랜드 딜에 걸리지 않는다 · 대가) · 카테고리·손님 태그 범위는 옮기지 않는다(D9 · 실물 0) · 2026-09-23 신설';
comment on column public.so_deal_target.cin7_id    is '규약 칸 · 늘 null';
comment on column public.so_deal_target.line_id    is 'FK → so_deal_line(id) · NOT NULL · on delete no action · 인덱스 so_deal_target_line_idx';
comment on column public.so_deal_target.kind       is 'include = 걸기 · exclude = 빼기 · CHECK 둘 · 판정 = 걸기에 든다 ∧ 빼기에 없다(so_deal_best)';
comment on column public.so_deal_target.target     is 'tag | brand | product · CHECK 셋 · exclude 는 tag·product 만(so_deal_target_exclude_ck)';
comment on column public.so_deal_target.tag        is 'target=tag 의 태그 글자 그대로(product_tag.tag 와 = 비교 · 대소문자 포함) · CHECK 앞뒤 공백 없음 · 인덱스 so_deal_target_tag_idx';
comment on column public.so_deal_target.brand_id   is 'target=brand 의 브랜드 → ref_brand(id) · product.brand_id 와 비교(⬜2) · 인덱스 so_deal_target_brand_idx · 적재는 Cin7 BrandName → ref_brand.name(unique) 글자 그대로 · 못 맞추면 멈춤';
comment on column public.so_deal_target.product_id is 'target=product 의 제품 → product(id) · 인덱스 so_deal_target_product_idx · 적재는 Cin7 ProductSKU → product.sku · 못 맞추면 멈춤 · 실물 참조 2,757(서로 다른 1,918 · 세트 SKU 124 는 2025-11·12 세일에만)';
comment on column public.so_deal_target.updated_by is '마지막으로 고친 사람 → ims_staff(id) · so_deal_target_touch(ims_touch)';

-- ═══ ⑥ 문지기 둘 — 오더 전체 딜은 줄이 없다 (이견 6 · 표 사이 규칙 하나를 트리거로 · 6-g′ 「관례만으로는 막히지 않는다」) ═══
-- 6-a so_deal_line_order_level_guard — 줄을 넣거나 다른 딜로 옮길 때 부모가 is_order_level 이면 거부
create function public.so_deal_line_order_level_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare
  d public.so_deal%rowtype;
begin
  select * into d from public.so_deal where id = new.deal_id;
  if found and d.is_order_level then
    raise exception 'Deal % is an order-level deal — it has no lines (order_pct is the whole discount) — nothing was saved', d.name;
  end if;
  return new;
end;
$$;
comment on function public.so_deal_line_order_level_guard() is 'so_deal_line BEFORE INSERT OR UPDATE OF deal_id — 부모 딜이 is_order_level 이면 거부(이견 6 · 오더 전체 딜은 order_pct 하나 · 줄 없음). FK 가 없는 deal_id 는 여기서 안 막는다(FK 가 막는다)';
revoke all on function public.so_deal_line_order_level_guard() from public, anon;

-- 6-b so_deal_order_level_guard — 줄이 있는 딜을 오더 전체 딜로 바꾸는 update 거부
create function public.so_deal_order_level_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  if new.is_order_level and not old.is_order_level
     and exists (select 1 from public.so_deal_line l where l.deal_id = new.id) then
    raise exception 'Deal % has lines — remove them before making it an order-level deal — nothing was saved', new.name;
  end if;
  return new;
end;
$$;
comment on function public.so_deal_order_level_guard() is 'so_deal BEFORE UPDATE — 줄이 있는 딜에 is_order_level 을 켜면 거부(이견 6 의 반대쪽 문). insert 는 줄이 있을 수 없어 보지 않는다';
revoke all on function public.so_deal_order_level_guard() from public, anon;

create trigger so_deal_line_order_level_guard before insert or update of deal_id on public.so_deal_line
  for each row execute function public.so_deal_line_order_level_guard();
create trigger so_deal_order_level_guard before update on public.so_deal
  for each row execute function public.so_deal_order_level_guard();
-- 트리거 순서(이름 알파벳 · 둘 다 BEFORE): so_deal_line_order_level_guard < so_deal_line_touch · so_deal_order_level_guard < so_deal_touch — 칸이 겹치지 않아 순서에 기대지 않는다

-- ═══ ⑦ so_deal_best — 줄 딜 계산 창구 하나 (⬜3 · D2·D3·D5·D7) ═══
--   (p_product_id, p_customer_id, p_qty, p_on) → (pct, deal_id, line_id) · 늘 한 행(없으면 (null, null, null) · so_price_for 와 같은 결)
--   후보 딜 = 켜짐 ∧ 줄 딜(is_order_level=false) ∧ 기간 안(null 은 열림 · p_on = 오더 날짜 · null 이면 오늘) ∧ (all ∨ so_deal_customer 에 손님)
--   줄 판정 = include 하나 이상에 든다(product = · brand = product.brand_id · tag ∈ product_tag) ∧ exclude 어디에도 없다(product · tag) ∧ 수량 기준(none · qty ≥ min_qty · case ≥ min(켜진 세트 pack_factor) · 세트 없으면 불통)
--   가장 큰 % 하나 · 같으면 deal_id · line_no 순(결정적) · 더하지 않는다(D5) · 손님 기본과의 greatest 는 so_line_quote(②-0b)의 일
--   p_customer_id null → all 딜만 · p_qty null → 0 으로 본다(none 줄만 걸린다) · 제품이 없으면 (null, null, null)
create function public.so_deal_best(p_product_id uuid, p_customer_id uuid, p_qty numeric, p_on date)
  returns table (pct numeric, deal_id uuid, line_id uuid)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with p as (
    select pr.id, pr.brand_id,
           (select min(s.pack_factor) from public.product s
             where s.parent_product_id = pr.id and s.is_active and s.pack_factor is not null) as case_qty
    from public.product pr where pr.id = p_product_id
  ),
  d as (
    select x.id
    from public.so_deal x
    where x.is_active and not x.is_order_level
      and (x.date_from is null or x.date_from <= coalesce(p_on, current_date))
      and (x.date_to   is null or x.date_to   >= coalesce(p_on, current_date))
      and (x.customer_scope = 'all'
           or (p_customer_id is not null
               and exists (select 1 from public.so_deal_customer dc where dc.deal_id = x.id and dc.customer_id = p_customer_id)))
  ),
  best as (
    select l.pct, l.deal_id, l.id as line_id
    from public.so_deal_line l
    join d on d.id = l.deal_id
    cross join p
    where exists (select 1 from public.so_deal_target t
                   where t.line_id = l.id and t.kind = 'include'
                     and (   (t.target = 'product' and t.product_id = p.id)
                          or (t.target = 'brand'   and t.brand_id   = p.brand_id)
                          or (t.target = 'tag'     and exists (select 1 from public.product_tag pt where pt.product_id = p.id and pt.tag = t.tag))))
      and not exists (select 1 from public.so_deal_target t
                       where t.line_id = l.id and t.kind = 'exclude'
                         and (   (t.target = 'product' and t.product_id = p.id)
                              or (t.target = 'tag'     and exists (select 1 from public.product_tag pt where pt.product_id = p.id and pt.tag = t.tag))))
      and case l.min_qty_mode
            when 'none' then true
            when 'qty'  then coalesce(p_qty, 0) >= l.min_qty
            when 'case' then p.case_qty is not null and coalesce(p_qty, 0) >= p.case_qty
            else false
          end
    order by l.pct desc, l.deal_id, l.line_no
    limit 1
  )
  select b.pct, b.deal_id, b.line_id
  from (select 1) one
  left join best b on true;
$$;
comment on function public.so_deal_best(uuid, uuid, numeric, date) is
  '⭐ 줄 딜 계산 창구 하나(할인 규칙 ②-0a · ⬜3) — (pct, deal_id, line_id) · 늘 한 행((null,null,null) = 걸리는 딜 없음). 후보 = 켜짐 ∧ 줄 딜 ∧ 기간 안(오더 날짜 p_on · null 은 열림) ∧ 손님(all | selected 목록) · 줄 = include 에 든다(product · brand=product.brand_id · tag∈product_tag 글자 그대로) ∧ exclude 에 없다(product · tag) ∧ 수량 기준(none · qty ≥ min_qty · case ≥ 켜진 세트 중 가장 작은 pack_factor · 세트 없으면 불통) · 가장 큰 % 하나(pct desc, deal_id, line_no · 더하지 않는다 D5) · 손님 기본과의 greatest 는 so_line_quote(②-0b) · 그 줄(같은 SKU 한 줄)의 수량만 본다(mix & match 없음 · p_force_new 두 줄은 따로 · 이견 8)';
revoke all on function public.so_deal_best(uuid, uuid, numeric, date) from public, anon;
grant execute on function public.so_deal_best(uuid, uuid, numeric, date) to authenticated;   -- 읽기 창구 — 화면 미리보기(표 select 와 같은 층 · so_line_quote 선례)

-- ═══ ⑧ so_order_discount — 오더 전체 딜 (⬜3·⬜4 · D6) ═══
--   (p_so_id) → (pct, deal_id) · 늘 한 행 · 오더의 손님·오더 날짜로 · 켜짐 ∧ is_order_level ∧ 기간 안 ∧ 손님 → 가장 큰 order_pct 하나
--   금액은 부르는 쪽(so_detail ②-0b)이 round(제품 줄 합계 × pct/100, 2) · 운임 제외 · 굳히는 자리는 so.order_discount_pct(⬜4 · source deal)
create function public.so_order_discount(p_so_id uuid)
  returns table (pct numeric, deal_id uuid)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with s as (select o.customer_id, o.order_date from public.so o where o.id = p_so_id),
  best as (
    select x.order_pct, x.id
    from public.so_deal x cross join s
    where x.is_active and x.is_order_level
      and (x.date_from is null or x.date_from <= s.order_date)
      and (x.date_to   is null or x.date_to   >= s.order_date)
      and (x.customer_scope = 'all'
           or exists (select 1 from public.so_deal_customer dc where dc.deal_id = x.id and dc.customer_id = s.customer_id))
    order by x.order_pct desc, x.id
    limit 1
  )
  select b.order_pct, b.id
  from (select 1) one
  left join best b on true;
$$;
comment on function public.so_order_discount(uuid) is
  '⭐ 오더 전체 딜 계산 창구(할인 규칙 ②-0a · D6·⬜4) — (pct, deal_id) · 늘 한 행((null,null) = 없음 · 오더가 없어도 같다). 오더의 customer_id·order_date 로 켜진 오더 전체 딜(is_order_level) 중 기간 안 · 손님 맞는 것의 가장 큰 order_pct 하나. 금액 = round(제품 줄 합계 × pct/100, 2)(SO-10842 실물 9,249.51 × 5% → −462.48) · 세금 전 · 운임(so_charge) 제외 · 굳히는 자리 so.order_discount_pct(source deal · so_create·손님·오더 날짜 바꾸기 ②-0b)';
revoke all on function public.so_order_discount(uuid) from public, anon;
grant execute on function public.so_order_discount(uuid) to authenticated;                  -- 읽기 창구(so 는 RLS select · 로그인만)

-- ═══ ⑨ so · so_line 새 칸 (⬜4 · 판정 2 · 이견 5) ═══
-- 9-a so — 오더 전체 할인을 굳힌다(source deal = so_order_discount 가 찾음 · manual = 사람이 정함 · 자동 재계산은 deal 만 덮는다)
alter table public.so
  add column if not exists order_discount_pct     numeric,
  add column if not exists order_discount_deal_id uuid references public.so_deal (id) on delete no action,
  add column if not exists order_discount_source  text;
alter table public.so
  add constraint so_order_discount_pct_ck     check (order_discount_pct is null or (order_discount_pct >= 0 and order_discount_pct <= 100)),
  add constraint so_order_discount_source_ck  check (order_discount_source is null or order_discount_source in ('deal','manual')),
  add constraint so_order_discount_pair_ck    check ((order_discount_pct is not null) = (order_discount_source is not null)),
  add constraint so_order_discount_deal_ck    check ((order_discount_deal_id is not null) = (order_discount_source is not distinct from 'deal'));
create index if not exists so_order_discount_deal_idx on public.so (order_discount_deal_id);
comment on column public.so.order_discount_pct     is '⭐ 오더 전체 할인 %(D6·⬜4) — 줄 할인이 끝난 제품 줄 합계에 한 번 더 · 세금 전 · 운임 제외 · 금액 = round(합계 × pct/100, 2) · null = 없음 · 짝 so_order_discount_pair_ck(값이 있다 = source 가 있다) · CHECK 0~100(manual 0 = 사람이 껐다) · 다시 찾는 곳: so_create · 손님 바꾸기 · 오더 날짜 바꾸기(source deal 일 때만 · ②-0b) · 사람이 고칠 수 있다(so_header_update 열쇠 · ②-0b)';
comment on column public.so.order_discount_deal_id is '어느 오더 전체 딜인가 → so_deal(id) · source deal 일 때만(so_order_discount_deal_ck) · 인덱스 so_order_discount_deal_idx · 「왜 이 할인」이 남는다';
comment on column public.so.order_discount_source  is 'deal = so_order_discount 가 찾았다(자동 재계산이 덮는다) · manual = 사람이 정했다(자동이 건드리지 않는다) · CHECK 둘 · 짝 CHECK 둘(pct · deal_id)';
comment on constraint so_order_discount_pair_ck on public.so is '⬜4 — (order_discount_pct is not null) = (order_discount_source is not null) · 둘 다 null(없음) 통과 · 한쪽만 위반 · 양쪽이 null 을 내지 않는다(§10 머리)';
comment on constraint so_order_discount_deal_ck on public.so is '⬜4 — (deal_id 있음) = (source = deal) · manual·없음이면 deal_id 없어야 한다 · is not distinct from 이라 null 을 내지 않는다';

-- 9-b so_line — 「왜 이 할인」(이견 5 · 판정 2): customer = 손님 기본 · deal = 딜 줄(deal_line_id 짝) · manual = 사람이 준 할인(p_discount_pct · 다시 매기기가 건드리지 않는다)
--    덮어쓴 줄(price_override)은 discount_pct·discount_source 둘 다 null(①b 회신 5 「discount_pct 는 뜻이 없다」와 같은 결) · 짝 CHECK (discount_pct 있음) = (source 있음)
--    ⚠️ 기존 줄: 테스트 DB 의 so_line 은 비어 있다(12-f ✅ so_delete cascade · 12-g) — 채움 update 없음 · 운영에는 SO 표가 아직 없다
alter table public.so_line
  add column if not exists discount_source text,
  add column if not exists deal_line_id    uuid references public.so_deal_line (id) on delete no action;
alter table public.so_line
  add constraint so_line_discount_source_ck   check (discount_source is null or discount_source in ('customer','deal','manual')),
  add constraint so_line_discount_pair_ck     check ((discount_pct is not null) = (discount_source is not null)),
  add constraint so_line_deal_line_pair_ck    check ((deal_line_id is not null) = (discount_source is not distinct from 'deal'));
create index if not exists so_line_deal_line_idx on public.so_line (deal_line_id);
comment on column public.so_line.discount_source is '⭐ 왜 이 할인인가(이견 5 · 판정 2) — customer = 손님 기본(so.discount_pct) · deal = 딜 줄(deal_line_id 짝 · so_deal_best) · manual = 사람이 준 할인(so_line_add p_discount_pct · so_line_update discount_pct) · null = 할인 칸이 없다(덮어쓴 줄 price_override) · 짝 so_line_discount_pair_ck(discount_pct 있음 = source 있음) · ⭐ 다시 매기기(넣기·합치기·수량 · ②-0b)는 price_override=false 이고 manual 이 아닌 줄만 건드린다 · 합치기 짝도 이 칸으로 가른다(판정 2 · 시스템이 매긴 줄은 제품만으로 늘 합친다 · 5-e 「단가가 같으면」 뒤집음)';
comment on column public.so_line.deal_line_id    is '걸린 딜 줄 → so_deal_line(id) · source deal 일 때만(so_line_deal_line_pair_ck) · 인덱스 so_line_deal_line_idx · 「받았을 금액」(list_price)처럼 「왜 이 할인」이 남는다 · 딜 줄은 지우지 않는다(마스터 · on delete no action)';
comment on constraint so_line_discount_pair_ck  on public.so_line is '이견 5 — (discount_pct is not null) = (discount_source is not null) · 덮어쓴 줄은 둘 다 null 로 통과 · 양쪽이 null 을 내지 않는다';
comment on constraint so_line_deal_line_pair_ck on public.so_line is '이견 5 — (deal_line_id 있음) = (source = deal) · customer·manual·null 이면 deal_line_id 없어야 한다';

-- ═══ ⑩ product.set_discount_pct — 뜻을 좁힌다 (D8 · 11-c 판정 ② 「세트마다 할인 하나 = 케이스 할인」을 뒤집는다 · 칸·CHECK·so_price_for 식은 그대로) ═══
comment on column public.product.set_discount_pct is
  '세트 SKU 자체를 팔 때 그 세트 가격의 할인 %(D8 · 2026-09-23 뜻 좁힘 — 11-c 판정 ② 「세트마다 할인 하나 = 케이스 할인」을 뒤집었다) · ⚠️ 케이스 할인(낱개 12개 이상이면 몇 %)은 여기가 아니라 전부 딜이다(so_deal_line min_qty_mode qty|case · 태그 GM20UOM12 류 · Caleb 「세일즈 오더에는 세트는 전혀 나오지 않아」) · 지금은 비워 둔다(null = 할인 없음) · 세트 가격 = 낱개의 그 티어 가격 × pack_factor × (1 − set_discount_pct/100) round 2(so_price_for set_calc · product_price 줄이 있으면 고정가가 이긴다 판정 ③·④) · CHECK 0~100 · 낱개(parent_product_id null)에는 값이 들어갈 수 없다(product_set_discount_set_only_ck) · 손님 기본 할인(customer.discount_pct)·딜과 다른 자리';

-- ═══ ⑪ ims_perm_catalog — master 라벨에 product tags · deals (재발행 · 마지막 정의 20260923182231:19 · 바뀐 줄 1 · 나머지 그대로) ═══
create or replace function public.ims_perm_catalog() returns jsonb
  language sql immutable
  set search_path = public, pg_temp
as $$
  select '{
    "modes": ["wms", "ims"],
    "screens": {
      "purchasing": {"room": "ims", "label": "Purchase orders, invoices, charges, payments"},
      "master":     {"room": "ims", "label": "Settings, suppliers, products, families, supplier products, prices, product tags, deals"},
      "receiving":  {"room": "ims", "label": "Receiving and putaway"},
      "staff":      {"room": "ims", "label": "Adding and editing people (below your own rank)"},
      "sales":      {"room": "ims", "label": "Sales orders, customer addresses and contacts"}
    }
  }'::jsonb;
$$;

-- ═══ 트리거 — <표>_touch → ims_touch()(다시 만들지 않는다) ═══
create trigger product_tag_touch      before update on public.product_tag      for each row execute function public.ims_touch();
create trigger so_deal_touch          before update on public.so_deal          for each row execute function public.ims_touch();
create trigger so_deal_customer_touch before update on public.so_deal_customer for each row execute function public.ims_touch();
create trigger so_deal_line_touch     before update on public.so_deal_line     for each row execute function public.ims_touch();
create trigger so_deal_target_touch   before update on public.so_deal_target   for each row execute function public.ims_touch();

-- ═══ RLS · 권한 — 20260923154749:157~170 모양 · 묶음 master(⬜5) ═══
alter table public.product_tag      enable row level security;
alter table public.so_deal          enable row level security;
alter table public.so_deal_customer enable row level security;
alter table public.so_deal_line     enable row level security;
alter table public.so_deal_target   enable row level security;
-- 마스터 — 정책 셋(DELETE 없음 · is_active 로 물러난다)
create policy so_deal_select on public.so_deal for select to authenticated using (true);
create policy so_deal_insert on public.so_deal for insert to authenticated with check ((select public.ims_can_write('master')));
create policy so_deal_update on public.so_deal for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
-- 관계 표 넷 — 정책 넷(DELETE 열림 — 태그를 떼고 · 손님·줄·범위를 지운다)
create policy product_tag_select      on public.product_tag      for select to authenticated using (true);
create policy product_tag_insert      on public.product_tag      for insert to authenticated with check ((select public.ims_can_write('master')));
create policy product_tag_update      on public.product_tag      for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy product_tag_delete      on public.product_tag      for delete to authenticated using ((select public.ims_can_write('master')));
create policy so_deal_customer_select on public.so_deal_customer for select to authenticated using (true);
create policy so_deal_customer_insert on public.so_deal_customer for insert to authenticated with check ((select public.ims_can_write('master')));
create policy so_deal_customer_update on public.so_deal_customer for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy so_deal_customer_delete on public.so_deal_customer for delete to authenticated using ((select public.ims_can_write('master')));
create policy so_deal_line_select     on public.so_deal_line     for select to authenticated using (true);
create policy so_deal_line_insert     on public.so_deal_line     for insert to authenticated with check ((select public.ims_can_write('master')));
create policy so_deal_line_update     on public.so_deal_line     for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy so_deal_line_delete     on public.so_deal_line     for delete to authenticated using ((select public.ims_can_write('master')));
create policy so_deal_target_select   on public.so_deal_target   for select to authenticated using (true);
create policy so_deal_target_insert   on public.so_deal_target   for insert to authenticated with check ((select public.ims_can_write('master')));
create policy so_deal_target_update   on public.so_deal_target   for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy so_deal_target_delete   on public.so_deal_target   for delete to authenticated using ((select public.ims_can_write('master')));

revoke all on public.product_tag      from anon;
revoke all on public.so_deal          from anon;
revoke all on public.so_deal_customer from anon;
revoke all on public.so_deal_line     from anon;
revoke all on public.so_deal_target   from anon;
revoke delete, truncate on public.so_deal          from authenticated;   -- 마스터
revoke truncate         on public.product_tag      from authenticated;   -- 관계 표 — delete 는 연다
revoke truncate         on public.so_deal_customer from authenticated;
revoke truncate         on public.so_deal_line     from authenticated;
revoke truncate         on public.so_deal_target   from authenticated;

-- ═══ 검증(회신 · psql heredoc · begin…rollback · 시퀀스 무접촉 · 시험 딜·태그·가짜 직원은 트랜잭션 안에서만) ═══
--   표 5 · 정책 3+16 · 트리거 5 touch + 2 guard · 함수 4(guard 2 · so_deal_best · so_order_discount) · so 칸 3 + CHECK 4 · so_line 칸 2 + CHECK 3 · 전체 유니크 so_deal_target_uq(부분 인덱스 0) · master 라벨
--   so_deal_best: 태그 12 이상(6 → null · 12 → 20) · 단계(12 → 10 · 144 → 15) · 케이스(11 → null · 12 → % · 세트 없는 낱개 → null) · 빼기(브랜드 걸기 + 태그 빼기 + SKU 빼기 → 뺀 둘 null) ·
--                큰 쪽 하나(20 과 30 → 30) · 기간(order_date 밖 → null) · 고른 손님(목록 밖 → null · 손님 null → null) · 없는 제품 → 한 행 (null,null,null)
--   so_order_discount: 5% · 기간 · 손님 · 없는 오더 → (null,null) · 금액 round(9249.51 × 5/100, 2) = 462.48
--   거부(시험마다 하나 · get stacked diagnostics constraint_name): so_deal_order_pct_pair_ck · so_deal_line_min_qty_pair_ck · so_deal_target_value_ck · so_deal_target_exclude_ck · product_tag_tag_ck ·
--                so_deal_target_uq(23505) · product_tag_product_tag_key(23505) · so_order_discount_deal_ck · so_line_deal_line_pair_ck · 문지기 둘(P0001)
--   권한: 가짜 직원 A(manager · perms ["master"]) so_deal insert 통과 · B(perms ["sales"]) 42501 · 둘 다 select 통과 · explain analyze so_deal_best 한 줄
