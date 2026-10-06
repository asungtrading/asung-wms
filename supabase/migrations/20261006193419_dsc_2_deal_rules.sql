-- ─────────────────────────────────────────────────────────────
-- 할인 규칙 표 넓히기 · 손님 조건 표 · 후보 함수 · 줄 할인 겨루기(세트 · 낱개 EA) · 미리 보기 (Asung-IMS · dsc-2 · 2026-10-06)
--   정본(뒤에 적는다): so-module §47 — 판정 277(두 층) · 278(조건 · 종류마다 칸) · 279(낱개 EA · 콤보 개수) · 280(고정가 = 정가 · 세트 할인은 계산 판매 세트 후보) · 287(미리 보기 = 같은 식) · 288(kind · pct < 100) · 289(D9 정정) · 296 ~ 301 · dsc-2 이견 1 ~ 7 · 9 ~ 12
--   판정 296  so_order_discount 를 같은 뜻으로 최소 재발행(손님 조건을 새 표에서) + so_deal_customer 삭제(0행 · 옮기기 뒤) · customer_scope 칸은 남기되 읽지 않음(dsc-3 에서 지움) · coupon_code · is_order_level · 문지기 둘 무접촉
--   판정 297  so_deal_best(p_product_id, p_customer_id, p_qty, p_on, p_tier_id default null) · null = 손님 price_tier 로 찾은 sale 티어 · drop + create · grant · comment 다시 · 부르는 곳은 so_line_quote 하나(재발행)
--   판정 298  계산 판매 세트의 list_price = round(낱개 × pack_factor, 2) · 세트 할인이 이기면 unit = list × (1 − set_discount_pct/100) · so_price_for 무변 · set_calc 와의 센트 끝수 차 허용(지금 해당 세트 0) · discount_source 어휘에 set(짝 CHECK 무변)
--   판정 299  손님 조건 — 같은 종류 안 OR · 다른 종류끼리 AND · 빼기는 하나라도 맞으면 뺀다 · 걸기 줄 없음 = 전체 · 브랜치 = customer.default_location_id(오더 창고 아님) · 티어 = 오더에 굳은 so.price_tier_id
--   판정 300  후보 = 제품 쪽 걸기에 맞는 딜 줄만 · 진 이유 순서 inactive → kind_not_pct → period_before/period_after → excluded_product → customer_excluded → customer_not_matched → below_min_qty → lower_pct → won
--   ⭐ 세트 줄의 제품 쪽 판정은 세트 자신 **과 그 낱개(parent)** 둘 다 본다(세트 SKU 에 건 딜 · 낱개 SKU · 브랜드 · 태그에 건 딜이 모두 걸린다 · 판정 후보로 보고) · 콤보는 자기 자신만
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · so_price_for · 문지기 둘 · so_line_quote 를 부르는 9곳 무접촉 · 끝의 do 블록이 실물을 세어 어긋나면 전부 되돌린다
-- ─────────────────────────────────────────────────────────────
do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;

-- ═══ 1) so_deal.kind(판정 288) · so_deal_line.pct < 100 · customer_scope 는 읽지 않는다(판정 296) ═══
alter table public.so_deal add column if not exists kind text not null default 'pct';
alter table public.so_deal add constraint so_deal_kind_ck check (kind in ('pct'));
comment on column public.so_deal.kind is '규칙 종류(dsc-2 · 판정 288) — 첫 판은 pct(퍼센트 할인) 하나 · 덤(free_item 류)은 뒤에 어휘를 넓힌다 · 함수 so_deal_candidates 는 pct 가 아닌 줄을 kind_not_pct 로 진다';
do $$
begin
  if (select count(*) from public.so_deal_line where pct >= 100) <> 0 then
    raise exception using errcode = 'IM288', message = 'STOP - a deal line with pct >= 100 exists - lower it first (ruling 288: pct < 100)';
  end if;
end $$;
alter table public.so_deal_line drop constraint so_deal_line_pct_ck;
alter table public.so_deal_line add constraint so_deal_line_pct_ck check (pct > 0 and pct < 100);
comment on column public.so_deal_line.pct is '할인 %(0 < pct < 100 · 판정 288 — 100 은 무상 줄(free_reason)의 일 · 덤은 kind 로)';
comment on column public.so_deal.customer_scope is '⚠️ dsc-2(판정 296)부터 읽지 않는다 — 손님 조건은 so_deal_customer_rule(걸기 줄 없음 = 전체 · 판정 299) · 칸은 dsc-3 에서 지운다 · 옛 뜻: all = 모든 손님 · selected = so_deal_customer 목록(표는 dsc-2 가 지웠다)';

-- ═══ 2) so_deal_target — category(판정 278 · 289) · exclude 의 brand 허용 · 유니크 7칸 ═══
alter table public.so_deal_target add column if not exists category_id uuid references public.ref_category (id) on delete no action;
alter table public.so_deal_target drop constraint so_deal_target_target_ck;
alter table public.so_deal_target add constraint so_deal_target_target_ck check (target in ('tag', 'brand', 'product', 'category'));
alter table public.so_deal_target drop constraint so_deal_target_value_ck;
alter table public.so_deal_target add constraint so_deal_target_value_ck check (
     (target = 'tag'      and tag is not null and brand_id is null     and product_id is null     and category_id is null)
  or (target = 'brand'    and tag is null     and brand_id is not null and product_id is null     and category_id is null)
  or (target = 'product'  and tag is null     and brand_id is null     and product_id is not null and category_id is null)
  or (target = 'category' and tag is null     and brand_id is null     and product_id is null     and category_id is not null));
alter table public.so_deal_target drop constraint so_deal_target_exclude_ck;
alter table public.so_deal_target drop constraint so_deal_target_uq;
alter table public.so_deal_target add constraint so_deal_target_uq unique nulls not distinct (line_id, kind, target, tag, brand_id, product_id, category_id);
create index if not exists so_deal_target_category_idx on public.so_deal_target (category_id);
comment on column public.so_deal_target.target      is 'tag | brand | product | category(dsc-2 · 판정 278 · 289) · CHECK 넷 · exclude 도 넷 모두(브랜드 빼기 허용 · dsc-2 가 so_deal_target_exclude_ck 를 지웠다)';
comment on column public.so_deal_target.category_id is '카테고리 범위(dsc-2) → ref_category(id) · target = category 일 때만(so_deal_target_value_ck) · 제품 쪽 판정은 product.category_id(세트 줄은 세트와 낱개 둘 다)';

-- ═══ 3) so_deal_customer_rule — 손님 조건(판정 278 · 299) · so_deal_customer 옮기기 → 삭제(판정 296) ═══
create table if not exists public.so_deal_customer_rule (
  id           uuid primary key default gen_random_uuid(),
  cin7_id      uuid unique,
  source       text not null default 'manual',
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references public.ims_staff (id) on delete no action,
  deal_id      uuid not null references public.so_deal (id) on delete no action,
  kind         text not null,
  target       text not null,
  customer_id  uuid references public.customer       (id) on delete no action,
  warehouse_id uuid references public.ref_warehouse  (id) on delete no action,
  tier_id      uuid references public.ref_price_tier (id) on delete no action,
  constraint so_deal_customer_rule_source_ck check (source in ('cin7', 'manual')),
  constraint so_deal_customer_rule_kind_ck   check (kind in ('include', 'exclude')),
  constraint so_deal_customer_rule_target_ck check (target in ('customer', 'branch', 'tier')),
  constraint so_deal_customer_rule_value_ck  check (
       (target = 'customer' and customer_id is not null and warehouse_id is null     and tier_id is null)
    or (target = 'branch'   and customer_id is null     and warehouse_id is not null and tier_id is null)
    or (target = 'tier'     and customer_id is null     and warehouse_id is null     and tier_id is not null)),
  constraint so_deal_customer_rule_uq unique nulls not distinct (deal_id, kind, target, customer_id, warehouse_id, tier_id)
);
create index if not exists so_deal_customer_rule_deal_idx       on public.so_deal_customer_rule (deal_id);
create index if not exists so_deal_customer_rule_customer_idx   on public.so_deal_customer_rule (customer_id);
create index if not exists so_deal_customer_rule_warehouse_idx  on public.so_deal_customer_rule (warehouse_id);
create index if not exists so_deal_customer_rule_tier_idx       on public.so_deal_customer_rule (tier_id);
create index if not exists so_deal_customer_rule_updated_by_idx on public.so_deal_customer_rule (updated_by);
create trigger so_deal_customer_rule_touch before update on public.so_deal_customer_rule for each row execute function public.ims_touch();
alter table public.so_deal_customer_rule enable row level security;
create policy so_deal_customer_rule_select on public.so_deal_customer_rule for select to authenticated using (true);
create policy so_deal_customer_rule_insert on public.so_deal_customer_rule for insert to authenticated with check ((select public.ims_can_write('master')));
create policy so_deal_customer_rule_update on public.so_deal_customer_rule for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy so_deal_customer_rule_delete on public.so_deal_customer_rule for delete to authenticated using ((select public.ims_can_write('master')));
grant select, insert, update, delete on public.so_deal_customer_rule to authenticated;
comment on table  public.so_deal_customer_rule is '⭐ 딜의 손님 조건(dsc-2 · 판정 278 · 299) — 딜 단위(so_deal_target 은 줄 단위) · kind include(걸기) | exclude(빼기) · target customer | branch | tier · 값 칸은 종류마다 따로(FK 가 걸리게 · so_deal_target 선례) · 판정 = 빼기 하나라도 맞으면 뺀다 · 걸기는 같은 종류 안 OR · 다른 종류끼리 AND(「Edmonton 브랜치 + Wholesale 티어」= Edmonton 의 Wholesale 손님만) · 걸기 줄이 없으면 전체 · 식은 so_deal_customer_ok 한 곳(so_deal_candidates · so_order_discount 가 쓴다) · ⭐ 손님 그룹(지역 · 등급 — Caleb 2026-10-06 「나중에는 손님들의 그룹을 만들꺼야」)은 칸을 아직 두지 않는다 — 그룹 표가 생기면 target 어휘 + group_id 칸 + value CHECK 한 줄 · 쓰기는 지금 master RLS · dsc-4 에서 창구로';
comment on column public.so_deal_customer_rule.warehouse_id is '브랜치 조건 → ref_warehouse(id) · ⭐ 손님의 집 브랜치 customer.default_location_id 로 판정한다 — 오더 창고 so.location_id 가 아니다(판정 299 · 에드먼튼 손님 딜은 토론토 창고에서 출고해도 걸린다)';
comment on column public.so_deal_customer_rule.tier_id      is '가격 티어 조건 → ref_price_tier(id) · 오더에 굳은 so.price_tier_id 로 판정(판정 299) · 미리 보기 · so_deal_best(p_tier_id null)는 손님의 price_tier 이름으로 찾은 sale 티어';
do $$
declare v_moved int;
begin
  insert into public.so_deal_customer_rule (cin7_id, source, note, created_at, updated_at, updated_by, deal_id, kind, target, customer_id)
  select c.cin7_id, c.source, c.note, c.created_at, c.updated_at, c.updated_by, c.deal_id, 'include', 'customer', c.customer_id from public.so_deal_customer c;
  get diagnostics v_moved = row_count;
  raise notice 'dsc-2 — so_deal_customer rows moved into so_deal_customer_rule (include · customer): %', v_moved;
end $$;
drop table public.so_deal_customer;

-- ═══ 4) 손님 조건 판정 한 곳 so_deal_customer_ok(판정 299) ═══
create function public.so_deal_customer_ok(p_deal_id uuid, p_customer_id uuid, p_tier_id uuid)
  returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  with c as (select cu.default_location_id as branch_id from public.customer cu where cu.id = p_customer_id),
  r as (
    select x.kind, x.target,
           case x.target when 'customer' then x.customer_id = p_customer_id
                         when 'branch'   then x.warehouse_id = (select branch_id from c)
                         when 'tier'     then x.tier_id = p_tier_id end as hit
    from public.so_deal_customer_rule x where x.deal_id = p_deal_id
  )
  select not exists (select 1 from r where r.kind = 'exclude' and r.hit)                                        -- 빼기 하나라도 맞으면 뺀다
     and not exists (select 1 from (select distinct target from r where kind = 'include') k                       -- 걸기: 종류마다(AND) 그 종류 안에서 하나는 맞아야(OR) · 걸기 줄 없으면 전체
                      where not exists (select 1 from r i where i.kind = 'include' and i.target = k.target and i.hit));
$$;
revoke all on function public.so_deal_customer_ok(uuid, uuid, uuid) from public, anon;
grant execute on function public.so_deal_customer_ok(uuid, uuid, uuid) to authenticated;
comment on function public.so_deal_customer_ok(uuid, uuid, uuid) is '딜의 손님 조건 판정 한 곳(dsc-2 · 판정 299) — so_deal_customer_rule: 빼기 하나라도 맞으면 false · 걸기는 종류마다 AND · 같은 종류 안 OR · 걸기 줄 없으면 true · 브랜치 = customer.default_location_id · 티어 = 넘긴 p_tier_id(오더 so.price_tier_id) · so_deal_candidates · so_order_discount 가 부른다';

-- ═══ 5) 후보 함수 so_deal_candidates(판정 300) ═══
create function public.so_deal_candidates(p_product_id uuid, p_customer_id uuid, p_tier_id uuid, p_qty_ea numeric, p_on date)
  returns table (deal_id uuid, deal_name text, line_id uuid, line_no int, pct numeric, min_qty_mode text, min_qty numeric, status text, reason text)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  return query
  with p as (                                                                              -- 제품 쪽 판정 대상 = 줄의 제품 + (세트면) 그 낱개
    select pr.id, pr.brand_id, pr.category_id,
           (select min(s.pack_factor) from public.product s where s.parent_product_id = pr.id and s.is_active and s.pack_factor is not null) as case_qty
    from public.product pr where pr.id = p_product_id
    union all
    select b.id, b.brand_id, b.category_id,
           (select min(s.pack_factor) from public.product s where s.parent_product_id = b.id and s.is_active and s.pack_factor is not null)
    from public.product pr join public.product b on b.id = pr.parent_product_id where pr.id = p_product_id
  ),
  hit as (                                                                                 -- 대상 줄이 제품(또는 낱개)에 맞나
    select t.line_id, t.kind
    from public.so_deal_target t
    where exists (select 1 from p
                   where (t.target = 'product'  and t.product_id  = p.id)
                      or (t.target = 'brand'    and t.brand_id    = p.brand_id)
                      or (t.target = 'category' and t.category_id = p.category_id)
                      or (t.target = 'tag'      and exists (select 1 from public.product_tag pt where pt.product_id = p.id and pt.tag = t.tag)))
  ),
  cand as (                                                                                -- 후보 = 제품 쪽 걸기에 맞는 딜 줄만(판정 300)
    select l.id as line_id, l.deal_id, l.line_no, l.pct, l.min_qty_mode, l.min_qty, d.name as deal_name, d.is_active, d.kind, d.date_from, d.date_to,
           exists (select 1 from hit h where h.line_id = l.id and h.kind = 'exclude') as excluded_product,
           (select max(case_qty) from p) as case_qty                                                                         -- case 모드의 한 케이스 = 낱개의 켜진 세트 중 최소 계수(세트 줄이면 그 낱개 기준 · 낱개 EA 로 비교)
    from public.so_deal_line l
    join public.so_deal d on d.id = l.deal_id
    where not d.is_order_level and exists (select 1 from hit h where h.line_id = l.id and h.kind = 'include')
  ),
  cust as (                                                                                -- 손님 쪽 판정은 딜마다 한 번(줄마다가 아니라) · 빼기 맞음 / 전체 판정
    select d.deal_id,
           exists (select 1 from public.so_deal_customer_rule x where x.deal_id = d.deal_id and x.kind = 'exclude'
                    and case x.target when 'customer' then x.customer_id = p_customer_id
                                      when 'branch'   then x.warehouse_id = (select cu.default_location_id from public.customer cu where cu.id = p_customer_id)
                                      when 'tier'     then x.tier_id = p_tier_id end) as excluded,
           public.so_deal_customer_ok(d.deal_id, p_customer_id, p_tier_id) as ok
    from (select distinct c.deal_id from cand c) d
  ),
  judged as (
    select c.*,
           case
             when not c.is_active then 'inactive'
             when c.kind <> 'pct' then 'kind_not_pct'
             when c.date_from is not null and c.date_from > p_on then 'period_before'
             when c.date_to   is not null and c.date_to   < p_on then 'period_after'
             when c.excluded_product then 'excluded_product'
             when k.excluded then 'customer_excluded'
             when not k.ok then 'customer_not_matched'
             when c.min_qty_mode = 'qty'  and coalesce(p_qty_ea, 0) < c.min_qty then 'below_min_qty'
             when c.min_qty_mode = 'case' and (c.case_qty is null or coalesce(p_qty_ea, 0) < c.case_qty) then 'below_min_qty'
             else null
           end as fail
    from cand c join cust k on k.deal_id = c.deal_id
  ),
  ranked as (
    select j.*, row_number() over (partition by (j.fail is null) order by j.pct desc, j.deal_id, j.line_no) as rn from judged j
  )
  select r.deal_id, r.deal_name, r.line_id, r.line_no, r.pct, r.min_qty_mode, r.min_qty,
         case when r.fail is null and r.rn = 1 then 'won' else 'lost' end as status,
         case when r.fail is null and r.rn = 1 then 'won' when r.fail is null then 'lower_pct' else r.fail end as reason
  from ranked r
  order by (r.fail is null and r.rn = 1) desc, r.pct desc, r.deal_id, r.line_no;
end $$;
revoke all on function public.so_deal_candidates(uuid, uuid, uuid, numeric, date) from public, anon;
grant execute on function public.so_deal_candidates(uuid, uuid, uuid, numeric, date) to authenticated;
comment on function public.so_deal_candidates(uuid, uuid, uuid, numeric, date) is '⭐ 딜 후보 전부(dsc-2 · 판정 300 · 287) — 제품(세트면 그 낱개까지) 쪽 걸기에 맞는 딜 줄만 후보 · 줄마다 status won|lost · reason inactive → kind_not_pct → period_before/period_after → excluded_product → customer_excluded → customer_not_matched(판정 299 AND) → below_min_qty → lower_pct → won · 수량은 낱개 EA(판정 279 · 세트 줄은 qty × pack_factor 를 부르는 쪽이 곱한다 · case 모드 = 낱개의 켜진 세트 중 최소 계수) · 기간은 p_on(오더 날짜 · D7) · 티어 = 오더 so.price_tier_id · so_deal_best 는 이 결과의 won 한 줄 · so_quote_preview 가 목록을 그대로 보인다 · definer';

-- ═══ 6) so_deal_best 재발행 — 판정 297(p_tier_id default null) · 마지막 정의 20260923224900:250~297 → 같은 식의 껍데기 ═══
drop function public.so_deal_best(uuid, uuid, numeric, date);
create function public.so_deal_best(p_product_id uuid, p_customer_id uuid, p_qty numeric, p_on date, p_tier_id uuid default null)
  returns table (pct numeric, deal_id uuid, line_id uuid)
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  with t as (
    select coalesce(p_tier_id, (select rt.id from public.customer cu join public.ref_price_tier rt on rt.name = cu.price_tier and rt.purpose = 'sale' and rt.is_active where cu.id = p_customer_id limit 1)) as tier_id
  ),
  best as (
    select c.pct, c.deal_id, c.line_id
    from t, lateral public.so_deal_candidates(p_product_id, p_customer_id, t.tier_id, p_qty, coalesce(p_on, public.ims_today())) c
    where c.status = 'won' limit 1
  )
  select b.pct, b.deal_id, b.line_id from (select 1) one left join best b on true;
$$;
revoke all on function public.so_deal_best(uuid, uuid, numeric, date, uuid) from public, anon;
grant execute on function public.so_deal_best(uuid, uuid, numeric, date, uuid) to authenticated;
comment on function public.so_deal_best(uuid, uuid, numeric, date, uuid) is '가장 좋은 딜 줄 하나(②-0a · dsc-2 재발행 · 판정 297) — so_deal_candidates 의 won 한 줄(식 한 곳 · 정렬 pct desc · deal_id · line_no 그대로) · 늘 한 행(없으면 null) · p_qty 는 낱개 EA(판정 279 · 세트 줄은 so_line_quote 가 × pack_factor) · p_tier_id null = 손님 price_tier 이름으로 찾은 sale 티어 · p_on null = ims_today() · 부르는 곳 so_line_quote 하나 · definer';

-- ═══ 7) so_line_quote 재발행 — 마지막 정의 20260923232500:61~76 · 판정 279 · 280 · 298 ═══
create or replace function public.so_line_quote(p_so public.so, p_product_id uuid, p_qty numeric)
  returns table (list_price numeric, discount_pct numeric, unit_price numeric, price_source text, discount_source text, deal_line_id uuid)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with pr as (
    select p.id, p.parent_product_id, p.pack_factor, coalesce(p.set_discount_pct, 0) as set_pct from public.product p where p.id = p_product_id
  ),
  f as (select * from public.so_price_for(p_product_id, p_so.price_tier_id)),
  base as (                                                                               -- 판정 298: 계산 판매 세트는 list = round(낱개 × pack_factor, 2)(할인 전) · 세트 할인 % 가 후보 · 고정가(row)는 그대로 · 후보 없음
    select case when f.price_source = 'set_calc'
                then round((select pp.price from public.product_price pp where pp.product_id = pr.parent_product_id and pp.tier_id = p_so.price_tier_id and pp.is_active) * pr.pack_factor, 2)
                else f.list_price end as list_price,
           case when f.price_source = 'set_calc' then pr.set_pct else 0 end as set_pct,
           case when pr.parent_product_id is not null then p_qty * coalesce(pr.pack_factor, 1) else p_qty end as qty_ea     -- 판정 279: 세트 줄은 낱개 EA · 낱개 · 콤보는 그대로
    from pr, f
  ),
  b as (select * from base, lateral public.so_deal_best(p_product_id, p_so.customer_id, base.qty_ea, p_so.order_date, p_so.price_tier_id) d),
  x as (
    select greatest(coalesce(p_so.discount_pct, 0), coalesce(b.pct, 0), b.set_pct) as d,
           case when coalesce(b.pct, 0) > greatest(coalesce(p_so.discount_pct, 0), b.set_pct) then 'deal'            -- 딜이 가장 클 때만 deal · 세트 할인이 손님 기본 · 딜보다 클 때 set · 그 밖(같으면 포함) customer
                when b.set_pct > coalesce(p_so.discount_pct, 0) and b.set_pct >= coalesce(b.pct, 0) then 'set'
                else 'customer' end as src
    from b
  )
  select b.list_price,
         x.d,
         case when b.list_price is null then null else b.list_price * (1 - x.d / 100) end,
         (select price_source from f),
         x.src,
         case when x.src = 'deal' then b.line_id end
  from b, x;
$$;
comment on function public.so_line_quote(public.so, uuid, numeric) is '⭐ 줄 견적 — 식 한 곳(②-0b · dsc-2 재발행 2026-10-06 · 판정 277 줄 층 · 279 · 280 · 298) — list = so_price_for(제품 · 오더 티어) · 계산 판매 세트(set_calc)만 list 를 round(낱개 × pack_factor, 2) 할인 전으로 다시 세고 set_discount_pct 를 후보에 넣는다 · 고정가 세트(row)는 그 값이 정가 · 후보 없음 · 딜은 so_deal_best(낱개 EA = 세트 줄 qty × pack_factor · 오더 티어 · 오더 날짜) · d = greatest(손님 기본, 딜, 세트) · unit = list × (1 − d/100) 자르지 않음 · 출처 deal(딜이 가장 클 때) · set(세트 할인이 손님 기본 · 딜보다 클 때 · deal_line_id null) · customer(그 밖 · 같으면 customer) · 부르는 곳 9 무접촉(so_line_add · so_lines_paste · so_line_update · so_line_requote · so_reprice · so_merge_requote_calc · so_finalize · so_quote_preview …) · invoker';

-- ═══ 8) so_line.discount_source 어휘 + set(판정 298) ═══
alter table public.so_line drop constraint so_line_discount_source_ck;
alter table public.so_line add constraint so_line_discount_source_ck check (discount_source is null or discount_source in ('customer', 'deal', 'manual', 'set'));
comment on column public.so_line.discount_source is '왜 이 할인인가 — customer(손님 기본) · deal(딜 · deal_line_id 짝) · manual(사람이 준 할인 · 다시 매기기가 안 건드림) · set(dsc-2 · 판정 298 · 계산 판매 세트의 세트 할인이 이겼다 · deal_line_id null) · 덮어쓴 줄(price_override)은 null(짝 CHECK) · 화면 이름표는 so.html · pos.html(대화 Claude)';

-- ═══ 9) so_order_discount 재발행 — 판정 296 최소(손님 조건을 새 표에서 · 그 밖 그대로) · 마지막 정의 20260923224900:306~326 ═══
create or replace function public.so_order_discount(p_so_id uuid)
  returns table (pct numeric, deal_id uuid)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with s as (select o.customer_id, o.order_date, o.price_tier_id from public.so o where o.id = p_so_id),
  best as (
    select x.order_pct, x.id
    from public.so_deal x cross join s
    where x.is_active and x.is_order_level
      and (x.date_from is null or x.date_from <= s.order_date)
      and (x.date_to   is null or x.date_to   >= s.order_date)
      and public.so_deal_customer_ok(x.id, s.customer_id, s.price_tier_id)                                        -- dsc-2 판정 296: 손님 조건은 so_deal_customer_rule(없으면 전체) · 옛 scope 칸은 읽지 않는다
    order by x.order_pct desc, x.id
    limit 1
  )
  select b.order_pct, b.id
  from (select 1) one
  left join best b on true;
$$;
comment on function public.so_order_discount(uuid) is '오더 전체 할인 하나(D6 · dsc-2 최소 재발행 2026-10-06 · 판정 296) — 켜짐 ∧ is_order_level ∧ 기간(오더 날짜) ∧ 손님 조건(so_deal_customer_ok · 걸기 줄 없음 = 전체) → 가장 큰 order_pct · 늘 한 행(없으면 null) · 금액 기준 · 쿠폰 · manual 우선은 dsc-3 · customer_scope 는 더 읽지 않는다';

-- ═══ 10) 미리 보기 so_quote_preview(판정 287) ═══
create function public.so_quote_preview(p_customer_id uuid, p_product_id uuid, p_qty numeric, p_on date default null, p_tier_id uuid default null)
  returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_so    public.so%rowtype;
  v_cu    public.customer%rowtype;
  v_pr    public.product%rowtype;
  v_tier  uuid;
  q       record;
  v_ea    numeric;
  v_cands jsonb;
begin
  if not (public.ims_can_view('sales') or public.ims_can_write('master')) then
    raise exception 'You cannot view sales pricing — ask an admin to add the ''sales'' permission — nothing was read';
  end if;
  if p_qty is null or p_qty <= 0 then raise exception 'Quantity must be a positive number — nothing was read'; end if;
  select * into v_cu from public.customer where id = p_customer_id;
  if not found then raise exception 'Customer not found — nothing was read'; end if;
  select * into v_pr from public.product where id = p_product_id;
  if not found then raise exception 'Product not found — nothing was read'; end if;
  v_tier := coalesce(p_tier_id, (select rt.id from public.ref_price_tier rt where rt.name = v_cu.price_tier and rt.purpose = 'sale' and rt.is_active limit 1));
  -- 오더 없이 so 행을 흉내낸다 — so_line_quote 가 읽는 칸만(손님 · 티어 · 날짜 · 손님 기본 할인) · 같은 식(판정 287)
  v_so.customer_id := p_customer_id;  v_so.price_tier_id := v_tier;  v_so.order_date := coalesce(p_on, public.ims_today());  v_so.discount_pct := v_cu.discount_pct;
  select * into q from public.so_line_quote(v_so, p_product_id, p_qty);
  v_ea := case when v_pr.parent_product_id is not null then p_qty * coalesce(v_pr.pack_factor, 1) else p_qty end;
  -- 딜 가운데 이긴 줄도 손님 기본 · 세트 할인에 졌으면(quote 의 출처가 deal 이 아니면) lost · lower_pct 로 보인다 — 이긴 줄은 목록에 하나뿐
  select coalesce(jsonb_agg(jsonb_build_object('kind', 'deal', 'deal_id', c.deal_id, 'deal_name', c.deal_name, 'line_id', c.line_id, 'line_no', c.line_no, 'pct', c.pct,
                                               'min_qty_mode', c.min_qty_mode, 'min_qty', c.min_qty,
                                               'status', case when c.status = 'won' and q.discount_source <> 'deal' then 'lost' else c.status end,
                                               'reason', case when c.status = 'won' and q.discount_source <> 'deal' then 'lower_pct' else c.reason end)
                            order by (c.status = 'won' and q.discount_source = 'deal') desc, c.pct desc, c.deal_name, c.line_no), '[]'::jsonb)
    into v_cands from public.so_deal_candidates(p_product_id, p_customer_id, v_tier, v_ea, v_so.order_date) c;
  -- 손님 기본 · 세트 할인도 후보 줄로(딜 줄이 아니다 · 이긴 것은 quote 의 출처로 안다)
  v_cands := v_cands
    || jsonb_build_object('kind', 'customer', 'pct', coalesce(v_cu.discount_pct, 0), 'status', case when q.discount_source = 'customer' then 'won' else 'lost' end,
                          'reason', case when q.discount_source = 'customer' then 'won' else 'lower_pct' end)
    || case when q.price_source = 'set_calc'
            then jsonb_build_object('kind', 'set', 'pct', coalesce(v_pr.set_discount_pct, 0), 'status', case when q.discount_source = 'set' then 'won' else 'lost' end,
                                    'reason', case when q.discount_source = 'set' then 'won' else 'lower_pct' end)
            else '[]'::jsonb end;
  return jsonb_build_object(
    'customer_id', p_customer_id, 'customer_name', v_cu.name, 'product_id', p_product_id, 'sku', v_pr.sku, 'product_name', v_pr.name,
    'tier_id', v_tier, 'tier', (select rt.name from public.ref_price_tier rt where rt.id = v_tier), 'on', v_so.order_date,
    'qty', p_qty, 'qty_ea', v_ea, 'pack_factor', coalesce(v_pr.pack_factor, 1), 'is_set', v_pr.parent_product_id is not null,
    'list_price', q.list_price, 'discount_pct', q.discount_pct, 'discount_source', q.discount_source, 'deal_line_id', q.deal_line_id,
    'unit_price', q.unit_price, 'line_total', case when q.unit_price is null then null else round(p_qty * q.unit_price, 2) end, 'price_source', q.price_source,
    'candidates', v_cands);
end;
$$;
revoke all on function public.so_quote_preview(uuid, uuid, numeric, date, uuid) from public, anon;
grant execute on function public.so_quote_preview(uuid, uuid, numeric, date, uuid) to authenticated;
comment on function public.so_quote_preview(uuid, uuid, numeric, date, uuid) is '⭐ 할인 미리 보기(dsc-2 · 판정 287 · 2026-10-06) — 손님 · 제품 · 수량(줄 수량) · 날짜(기본 ims_today) · 티어(기본 손님의 sale 티어) → 오더 없이 so 행을 흉내내어 **같은 so_line_quote** 를 부른다(화면이 셈하지 않는다) · 반환 {list_price · discount_pct · discount_source · deal_line_id · unit_price · line_total · price_source · qty_ea · is_set · candidates[{kind deal|customer|set · deal_id · deal_name · line_id · line_no · pct · min_qty_mode · min_qty · status won|lost · reason}] · 이긴 줄은 하나(딜이 손님 기본 · 세트에 졌으면 그 딜 줄도 lost · lower_pct)} · 문 = sales 읽기 또는 master · definer · 원가 없음';

-- ═══ 11) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text;
begin
  if to_regclass('public.so_deal_customer') is not null then v_bad := v_bad || ' so_deal_customer(still there)'; end if;
  if to_regclass('public.so_deal_customer_rule') is null then v_bad := v_bad || ' so_deal_customer_rule'; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'so_deal_customer_rule') <> 4 then v_bad := v_bad || ' rule_policies'; end if;
  if to_regprocedure('public.so_deal_best(uuid, uuid, numeric, date)') is not null or to_regprocedure('public.so_deal_best(uuid, uuid, numeric, date, uuid)') is null then v_bad := v_bad || ' so_deal_best'; end if;
  if to_regprocedure('public.so_deal_candidates(uuid, uuid, uuid, numeric, date)') is null or to_regprocedure('public.so_deal_customer_ok(uuid, uuid, uuid)') is null or to_regprocedure('public.so_quote_preview(uuid, uuid, numeric, date, uuid)') is null then v_bad := v_bad || ' functions'; end if;
  if not exists (select 1 from pg_constraint where conname = 'so_deal_kind_ck') or not exists (select 1 from pg_constraint where conname = 'so_deal_line_pct_ck' and pg_get_constraintdef(oid) like '%< (100)%')
     or exists (select 1 from pg_constraint where conname = 'so_deal_target_exclude_ck') or not exists (select 1 from pg_constraint where conname = 'so_deal_target_uq' and pg_get_constraintdef(oid) like '%category_id%') then v_bad := v_bad || ' checks'; end if;
  if not exists (select 1 from pg_constraint where conname = 'so_line_discount_source_ck' and pg_get_constraintdef(oid) like '%''set''%') then v_bad := v_bad || ' so_line_source_ck'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.so_order_discount(uuid)');
  if v_src like '%so_deal_customer %' or v_src like '%customer_scope%' or v_src not like '%so_deal_customer_ok%' then v_bad := v_bad || ' so_order_discount'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.so_line_quote(public.so, uuid, numeric)');
  if v_src not like '%set_calc%' or v_src not like '%p_so.price_tier_id)%' then v_bad := v_bad || ' so_line_quote'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM296', message = format('STOP - dsc-2 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
