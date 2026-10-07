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
-- 20261007202707_sale_1_sale_now.sql — sale-1 (2026-10-07 · 회사 PC)
--   Caleb 「inventory 모듈에서 현재 세일하는 제품들에 해당 세일 라벨도 붙일 수 있나?」 · 「products화면에도 보이면 좋겠어. 그리고, 세일하는 제품들만 필터링이 되면 좋겠어.」
--   판정 361 세일 = 오늘(ims_today) 기간 안 · 딜과 줄이 켜짐 · 쿠폰이 필요 없는 줄 할인 딜(is_order_level false · coupon_required false) · 조건(최소 수량 · 손님 조건)이 있어도 세일(라벨 * · 설명에) · 딜이 여럿이면 가장 큰 % 하나 · 붙일 곳 Stock availability · Products(둘 다 「세일 제품만」 거르기)
--   식 한 곳: 대상 판정(브랜드 · 카테고리 · 제품 · 태그 · 빼기 · 세트 = 낱개가 걸리면 같이 · 판정 302)은 so_deal_products_all(딜 여럿) 하나 — so_deal_products 는 그 껍데기로 재발행(결과 같음은 검증 E1) · so_sale_now 가 부른다 · so_deal_candidates 는 무접촉(판정 337 그대로)
--   읽기 창구 so_sale_now(p_product_ids · p_on) · stk_availability(+ p_sale_only · 열 sale_pct · sale_conditional · 반환 모양이 바뀌어 drop + create) · product_list(products.html 의 목록 질의를 서버로 · 거르기 일곱 그대로 + p_sale_only) — 세일 제품이 수천이라 id 목록 거르기는 안 된다
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 supabase/tests/sale-1-verify.sql

-- ═══ 1) so_deal_products_all — 식 한 곳(so_deal_products 20261007003838:1600~1627 바이트 복사 · 바뀐 줄 셋: 이름 · 인자 · deal_id) · invoker · authenticated 허용(so_sale_now 가 invoker 라 회수된 속을 못 부른다 · 읽는 표 전부 authenticated select) ═══
create function public.so_deal_products_all(p_deal_ids uuid[] default null)
  returns table (deal_id uuid, product_id uuid, line_id uuid, line_no int, matched_by text[])
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  return query
  with l as (select x.id as line_id, x.line_no, x.deal_id from public.so_deal_line x where (p_deal_ids is null or x.deal_id = any (p_deal_ids)) and x.is_active),   -- sale-1: 딜 여럿(null = 전부) · deal_id 를 들고 간다
  t as (select x.line_id, x.kind, x.target, x.tag, x.brand_id, x.product_id, x.category_id from public.so_deal_target x join l on l.line_id = x.line_id),
  base as (                                                                                  -- 제품 자신이 대상에 맞는다(종류마다 인덱스 길)
    select t.line_id, t.kind, t.target, t.product_id                                  from t                                                                  where t.target = 'product'
    union all select t.line_id, t.kind, t.target, pr.id from t join public.product pr on pr.brand_id    = t.brand_id    where t.target = 'brand'
    union all select t.line_id, t.kind, t.target, pr.id from t join public.product pr on pr.category_id = t.category_id where t.target = 'category'
    union all select t.line_id, t.kind, t.target, pt.product_id from t join public.product_tag pt on pt.tag = t.tag      where t.target = 'tag'
  ),
  m as (                                                                                     -- 세트는 낱개가 걸리면 같이 걸린다(판정 302 · candidates 의 p 둘째 가지)
    select b.line_id, b.kind, b.target || '' as via, b.product_id from base b
    union all
    select b.line_id, b.kind, b.target || ':base', s.id from base b join public.product s on s.parent_product_id = b.product_id
  ),
  inc as (select m.line_id, m.product_id, array_agg(distinct m.via) as matched_by from m where m.kind = 'include' group by m.line_id, m.product_id),
  exc as (select distinct m.line_id, m.product_id from m where m.kind = 'exclude')
  select l.deal_id, i.product_id, i.line_id, l.line_no, i.matched_by
    from inc i join l on l.line_id = i.line_id
    left join exc e on e.line_id = i.line_id and e.product_id = i.product_id
   where e.product_id is null;
end $$;
revoke all on function public.so_deal_products_all(uuid[]) from public, anon;
grant execute on function public.so_deal_products_all(uuid[]) to authenticated;
comment on function public.so_deal_products_all(uuid[]) is '⭐ 딜 대상 제품 식 한 곳(sale-1 · 판정 337 의 so_deal_products 를 딜 여럿으로) — (deal_id · product_id · line_id · line_no · matched_by) · 켜진 줄마다 걸기 ∧ ¬빼기(그 줄 안에서) · 제품 · 브랜드 · 카테고리 · 태그 · 세트는 낱개가 걸리면 같이(:base · 판정 302) · 딜 켜짐 · 기간 · 손님 · 수량 · 제품 켜짐은 보지 않는다 · null = 모든 딜 · so_deal_products(껍데기) · so_sale_now 가 부른다 · invoker(읽는 표 전부 authenticated select)';

-- ═══ 2) so_deal_products 재발행 — 마지막 정의 20261007003838:1600~1627 · 껍데기(결과 · 시그니처 · 권한 그대로 · 검증 E1 이 옛 함수와 대조) ═══
create or replace function public.so_deal_products(p_deal_id uuid)
  returns table (product_id uuid, line_id uuid, line_no int, matched_by text[])
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
begin
  return query select a.product_id, a.line_id, a.line_no, a.matched_by from public.so_deal_products_all(array[p_deal_id]) a;   -- sale-1: 식은 so_deal_products_all 한 곳(검증 E1 이 옛 함수와 모든 딜에서 같음을 본다)
end $$;
comment on function public.so_deal_products(uuid) is '딜이 손댈 수 있는 제품 집합(dsc-4b · 판정 337 · ⭐ sale-1 재발행: 식은 so_deal_products_all 한 곳 · 결과 같음) — 켜진 줄마다 (제품 · 줄 · 걸린 까닭[product|brand|category|tag(:base = 낱개를 거쳐)]) · 뜻은 so_deal_candidates 의 hit 과 같다(검증 dsc-4b T4) · 오더 딜은 줄이 없어 빈 집합 · 속 함수(so_deal_list · so_deal_detail · so_deal_save 가 부른다) · definer';

-- ═══ 3) so_sale_now — 오늘 세일하는 제품(판정 361) ═══
create function public.so_sale_now(p_product_ids uuid[] default null, p_on date default null)
  returns table (product_id uuid, best_pct numeric, deal_count int, conditional boolean, deals jsonb)
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare v_on date := coalesce(p_on, public.ims_today());
begin
  return query
  with d as (                                                                                  -- 판정 361: 켜진 줄 할인 딜 · 쿠폰 아님 · 오늘 기간 안
    select x.id, x.name, x.date_from, x.date_to,
           exists (select 1 from public.so_deal_customer_rule r where r.deal_id = x.id) as customer_limited
    from public.so_deal x
    where x.is_active and not x.is_order_level and not x.coupon_required and x.kind = 'pct'
      and (x.date_from is null or x.date_from <= v_on) and (x.date_to is null or x.date_to >= v_on)
  ),
  j as (
    select a.product_id, a.deal_id, d.name, l.pct, l.line_no, l.min_qty_mode, l.min_qty, d.date_from, d.date_to, d.customer_limited, a.matched_by
    from public.so_deal_products_all((select array_agg(d2.id) from d d2)) a                                    -- 식 한 곳 · 켜진 줄만(세트는 낱개를 거쳐 · 판정 302)
    join d on d.id = a.deal_id
    join public.so_deal_line l on l.id = a.line_id
    where p_product_ids is null or a.product_id = any (p_product_ids)
  )
  select j.product_id,
         max(j.pct)                                                     as best_pct,
         count(distinct j.deal_id)::int                                 as deal_count,
         bool_or(j.min_qty_mode <> 'none' or j.customer_limited)        as conditional,
         jsonb_agg(jsonb_build_object('deal_id', j.deal_id, 'name', j.name, 'pct', j.pct, 'line_no', j.line_no, 'date_from', j.date_from, 'date_to', j.date_to,
                                      'min_qty_mode', j.min_qty_mode, 'min_qty', j.min_qty, 'customer_limited', j.customer_limited, 'matched_by', j.matched_by)
                   order by j.pct desc, j.name, j.line_no)               as deals
  from j
  where (select count(*) from d) > 0
  group by j.product_id;
end $$;
revoke all on function public.so_sale_now(uuid[], date) from public, anon;
grant execute on function public.so_sale_now(uuid[], date) to authenticated;
comment on function public.so_sale_now(uuid[], date) is '⭐ 지금 세일하는 제품(sale-1 · 판정 361 · 2026-10-07) — 세일 = p_on(null = ims_today · 토론토) 기간 안 · 켜진 딜의 켜진 줄 · 쿠폰이 필요 없는 줄 할인 딜(오더 딜 · 쿠폰 딜은 뺀다) · 대상 판정은 so_deal_products_all 한 곳(세트는 낱개를 거쳐) · 행 = 제품마다 best_pct(가장 큰 %) · deal_count(딜 수) · conditional(최소 수량 또는 손님 조건이 있는 줄이 하나라도) · deals[{deal_id · name · pct · line_no · date_from · date_to · min_qty_mode · min_qty · customer_limited · matched_by}](% 큰 순 · 줄마다 한 항목) · p_product_ids null = 세일 제품 전부 · 제품 켜짐은 보지 않는다(화면이 거른다) · invoker · stable · Stock availability · Products 화면이 라벨 · 거르기에 쓴다(stk_availability · product_list 가 안에서 부른다)';

-- ═══ 4) stk_availability 재발행 — 마지막 정의 20261006143300:118~217 · 인자 p_sale_only(끝에) · 열 sale_pct · sale_conditional(total 앞) · 반환 모양이 바뀌어 drop + create + 권한 ═══
drop function public.stk_availability(uuid, text, uuid, uuid, boolean, int, int);
create function public.stk_availability(
  p_warehouse_id uuid,
  p_q            text    default null,
  p_brand_id     uuid    default null,
  p_category_id  uuid    default null,
  p_include_zero boolean default false,
  p_limit        int     default 100,
  p_offset       int     default 0,
  p_sale_only    boolean default false                                                   -- sale-1 판정 361: 참이면 오늘 세일하는 낱개만
) returns table (
  product_id uuid, sku text, name text, brand_id uuid, brand_name text, category_id uuid, category_name text, is_active boolean,
  on_hand numeric, sales_allocated numeric, transfer_reserved numeric, available numeric, on_order numeric, in_transit numeric, last_event_on date,
  matched_set_sku text, matched_set_pack_factor numeric, matched_set_count int,
  sale_pct numeric, sale_conditional boolean,                                             -- sale-1 판정 361: 세일 라벨(가장 큰 % · 조건 있음) · 세일이 아니면 null
  total bigint
)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_q      text := nullif(btrim(p_q), '');
  v_limit  int  := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_offset int  := greatest(coalesce(p_offset, 0), 0);
begin
  -- 문(판정 268) — 로그인 + 활성 직원 · 열쇠는 보지 않는다(판정 258)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  if not exists (select 1 from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active) then
    raise exception 'Warehouse not found or inactive — pick an active branch';
  end if;
  return query
  with av as (                                                                           -- 장부 · 판매 예약 · 트랜스퍼 예약 — 식 한 곳(inv_available_base)
    select b.stock_pid, b.qty_ea, b.sales_alloc_ea, b.transfer_alloc_ea from public.inv_available_base(p_warehouse_id, null) b
  ),
  lastev as (
    select b.product_id, max(b.last_event_on) as last_event_on from public.ims_inv_balance b where b.warehouse = (select w.name from public.ref_warehouse w where w.id = p_warehouse_id) and b.product_id is not null group by 1
  ),
  onord as (                                                                             -- 판정 260 — 확정 발주 줄 − 확정 입고 줄 · 줄마다 0 아래는 0 · 발주의 배송 창고
    select coalesce(pr.parent_product_id, pr.id) as stock_pid, sum(greatest(l.qty_ea - coalesce(rc.recv, 0), 0)) as ea
    from public.po po
    join public.po_line l on l.po_id = po.id
    join public.product pr on pr.id = l.product_id
    left join (select rl.po_line_id, sum(rl.qty_ea) as recv
                 from public.po_receipt_line rl join public.po_receipt r on r.id = rl.receipt_id
                where r.status = 'confirmed' group by 1) rc on rc.po_line_id = l.id
    where po.status = 'confirmed' and po.ship_to_warehouse_id = p_warehouse_id
    group by 1
  ),
  intr as (                                                                              -- 운송 중 — 출발했고 아직 도착 창고에 다 들어오지 않은 트랜스퍼 줄 · 도착 창고
    select coalesce(pr.parent_product_id, pr.id) as stock_pid,
           sum(greatest(coalesce(l.qty_sent, 0) - coalesce(l.qty_received, 0) - coalesce(l.qty_lost, 0) - coalesce(l.qty_returned, 0), 0) * l.pack_factor) as ea
    from public.inv_transfer t
    join public.inv_transfer_line l on l.transfer_id = t.id
    join public.product pr on pr.id = l.product_id
    where t.status in ('in_transit', 'receiving') and t.to_warehouse_id = p_warehouse_id
    group by 1
  ),
  sale as (                                                                              -- sale-1 판정 361: 오늘 세일(so_sale_now · 식 한 곳) — 낱개 줄에 붙인다
    select z.product_id, z.best_pct, z.conditional from public.so_sale_now(null, null) z
  ),
  setm as (                                                                              -- 판정 261 · 267 — 세트 sku 검색 → 낱개 줄 · 첫 세트(sku 순) + 개수
    select s.parent_product_id as stock_pid,
           (array_agg(s.sku order by s.sku))[1]         as matched_set_sku,
           (array_agg(s.pack_factor order by s.sku))[1] as matched_set_pack_factor,
           count(*)::int                                as matched_set_count
    from public.product s
    where v_q is not null and s.parent_product_id is not null and s.sku ilike '%' || v_q || '%'
    group by 1
  ),
  rows_all as (
    select p.id, p.sku, p.name, p.brand_id, p.brand_name, p.category_id, p.category_name, p.is_active,
           coalesce(av.qty_ea, 0)            as on_hand,
           coalesce(av.sales_alloc_ea, 0)    as sales_allocated,
           coalesce(av.transfer_alloc_ea, 0) as transfer_reserved,
           coalesce(av.qty_ea, 0) - coalesce(av.sales_alloc_ea, 0) - coalesce(av.transfer_alloc_ea, 0) as available,
           coalesce(onord.ea, 0)             as on_order,
           coalesce(intr.ea, 0)              as in_transit,
           lastev.last_event_on,
           setm.matched_set_sku, setm.matched_set_pack_factor, setm.matched_set_count,
           sale.best_pct as sale_pct, sale.conditional as sale_conditional                                              -- sale-1
    from public.product p                                                                -- 줄 = 재고 키 = 낱개(세트 · 콤보 줄 없음 · 판정 261)
    left join av     on av.stock_pid     = p.id
    left join lastev on lastev.product_id = p.id
    left join onord  on onord.stock_pid  = p.id
    left join intr   on intr.stock_pid   = p.id
    left join setm   on setm.stock_pid   = p.id
    left join sale   on sale.product_id  = p.id                                                                        -- sale-1
    where p.parent_product_id is null
      and (not p_sale_only or sale.product_id is not null)                                                             -- sale-1 판정 361: 세일 제품만
      and not exists (select 1 from public.product_bom bm where bm.parent_product_id = p.id and bm.is_active)
      and (p_brand_id is null or p.brand_id = p_brand_id)
      and (p_category_id is null or p.category_id = p_category_id)
      and (v_q is null or p.sku ilike '%' || v_q || '%' or p.name ilike '%' || v_q || '%' or p.brand_name ilike '%' || v_q || '%' or setm.stock_pid is not null)
  ),
  rows_kept as (
    select r.* from rows_all r
    where p_include_zero
       or r.on_hand <> 0 or r.sales_allocated <> 0 or r.transfer_reserved <> 0 or r.on_order <> 0 or r.in_transit <> 0   -- 판정 266 — 다섯 숫자 모두 0 인 줄만 뺀다
  )
  select r.id, r.sku, r.name, r.brand_id, r.brand_name, r.category_id, r.category_name, r.is_active,
         r.on_hand, r.sales_allocated, r.transfer_reserved, r.available, r.on_order, r.in_transit, r.last_event_on,
         r.matched_set_sku, r.matched_set_pack_factor, r.matched_set_count,
         r.sale_pct, r.sale_conditional,                                                                                   -- sale-1
         count(*) over () as total
  from rows_kept r
  order by r.sku, r.id
  limit v_limit offset v_offset;
end;
$$;
revoke all on function public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean) from public, anon;
grant execute on function public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean) to authenticated;
comment on function public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean) is
  '⭐ 브랜치별 재고 가용표 한 쪽(stk-1 · 판정 257 ~ 262 · 266 ~ 268 · ⭐ sale-1 재발행 판정 361) — 줄 = 재고 키(낱개 · 세트 · 콤보 줄 없음) × 고른 창고(활성만) · on_hand · sales_allocated · transfer_reserved · available · on_order · in_transit · last_event_on · 세트 sku 검색 → 낱개 줄(matched_set_*) · p_include_zero 거짓이면 다섯 숫자 모두 0 인 줄만 뺀다 · ⭐ sale_pct · sale_conditional = 오늘 세일 라벨(so_sale_now · 낱개 기준 — 세트만 대상인 딜은 낱개 줄에 안 보인다) · p_sale_only 참이면 세일 낱개만 · total = 거른 뒤 전체 수 · 문 = 로그인 + 활성 직원(열쇠 안 봄 · 판정 268) · definer · limit ≤ 500';

-- ═══ 5) product_list — products.html 목록 질의(sb.from("product") · listQuery)를 서버로 · 거르기 일곱 그대로 + p_sale_only · 세일 열쇠 둘 · total ═══
create function public.product_list(
  p_q           text    default null,                                                    -- sku 또는 name ilike %q%(화면 .or(sku.ilike,name.ilike))
  p_brand_name  text    default null,                                                    -- 화면 .eq("brand_name")
  p_category_name text  default null,                                                    -- 화면 .eq("category_name")
  p_supplier_id uuid    default null,                                                    -- 화면 product_supplier!inner(supplier_id · is_active) — 판정 151
  p_kind        text    default null,                                                    -- 'single' = 낱개(parent null) · 'set' = 세트 · null · 'all' = 전부
  p_only_active boolean default false,                                                   -- 화면 .eq("is_active", true)
  p_sale_only   boolean default false,                                                   -- sale-1 판정 361: 오늘 세일하는 제품만
  p_limit       int     default 100,
  p_offset      int     default 0
) returns table (
  id uuid, sku text, name text, is_active boolean, parent_product_id uuid, pack_factor numeric, brand_name text, category_name text,   -- 화면 cols 그대로
  sale_pct numeric, sale_conditional boolean,                                                                                        -- sale-1
  total bigint
)
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_q      text := nullif(btrim(p_q), '');
  v_limit  int  := least(greatest(coalesce(p_limit, 100), 1), 1000);
  v_offset int  := greatest(coalesce(p_offset, 0), 0);
begin
  if p_kind is not null and p_kind not in ('single', 'set', 'all') then raise exception 'p_kind must be single, set or all'; end if;
  return query
  with sale as (select z.product_id, z.best_pct, z.conditional from public.so_sale_now(null, null) z)
  select p.id, p.sku, p.name, p.is_active, p.parent_product_id, p.pack_factor, p.brand_name, p.category_name,
         sale.best_pct, sale.conditional,
         count(*) over () as total
  from public.product p
  left join sale on sale.product_id = p.id
  where (not p_only_active or p.is_active)
    and (p_kind is null or p_kind = 'all' or (p_kind = 'single' and p.parent_product_id is null) or (p_kind = 'set' and p.parent_product_id is not null))
    and (p_brand_name is null or p.brand_name = p_brand_name)
    and (p_category_name is null or p.category_name = p_category_name)
    and (v_q is null or p.sku ilike '%' || v_q || '%' or p.name ilike '%' || v_q || '%')
    and (p_supplier_id is null or exists (select 1 from public.product_supplier ps where ps.product_id = p.id and ps.supplier_id = p_supplier_id and ps.is_active))
    and (not p_sale_only or sale.product_id is not null)
  order by p.sku, p.id
  limit v_limit offset v_offset;
end $$;
revoke all on function public.product_list(text, text, text, uuid, text, boolean, boolean, int, int) from public, anon;
grant execute on function public.product_list(text, text, text, uuid, text, boolean, boolean, int, int) to authenticated;
comment on function public.product_list(text, text, text, uuid, text, boolean, boolean, int, int) is '⭐ 제품 목록 한 쪽(sale-1 · 판정 361 · 2026-10-07) — products.html listQuery(sb.from("product") · 칸 여덟 · 거르기: q(sku · name ilike) · brand_name · category_name · 공급처(product_supplier 켜진 줄 · 판정 151) · kind single|set|all · only_active · 순서 sku) 를 서버로 옮긴 것 + p_sale_only(오늘 세일하는 제품만 · so_sale_now) + sale_pct · sale_conditional(라벨) + total(거른 뒤 전체 수 · PostgREST count exact 자리) · 세일 제품이 수천이라 id 목록 거르기(in.(…))는 주소 길이에 걸린다 — 서버가 거른다 · invoker(product RLS select 그대로) · limit ≤ 1000';

-- ═══ 6) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text;
begin
  foreach v_t in array array['public.so_deal_products_all(uuid[])', 'public.so_deal_products(uuid)', 'public.so_sale_now(uuid[], date)', 'public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean)', 'public.product_list(text, text, text, uuid, text, boolean, boolean, int, int)'] loop
    if to_regprocedure(v_t) is null then v_bad := v_bad || format(' %s(missing)', v_t); end if;
    if has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(anon)', v_t); end if;
  end loop;
  foreach v_t in array array['public.so_deal_products_all(uuid[])', 'public.so_sale_now(uuid[], date)', 'public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean)', 'public.product_list(text, text, text, uuid, text, boolean, boolean, int, int)'] loop
    if not has_function_privilege('authenticated', v_t, 'execute') then v_bad := v_bad || format(' %s(no-authenticated)', v_t); end if;
  end loop;
  if has_function_privilege('authenticated', 'public.so_deal_products(uuid)', 'execute') then v_bad := v_bad || ' so_deal_products(authenticated-open)'; end if;
  if to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int)') is not null then v_bad := v_bad || ' old_stk_signature'; end if;
  if (select count(*) from pg_proc where proname in ('stk_availability', 'so_deal_products', 'so_sale_now', 'product_list', 'so_deal_products_all')) <> 5 then v_bad := v_bad || ' count'; end if;
  if pg_get_function_result('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean)'::regprocedure) not like '%sale_pct numeric, sale_conditional boolean, total bigint%' then v_bad := v_bad || ' stk(result)'; end if;
  if (select p.prosrc from pg_proc p where p.proname = 'so_deal_products') not like '%so_deal_products_all(array[p_deal_id])%' then v_bad := v_bad || ' so_deal_products(body)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_deal_candidates', 'so_deal_best', 'so_deal_customer_ok', 'so_deal_list', 'so_deal_detail', 'so_deal_save') and p.prosrc like '%sale-1%') <> 0 then v_bad := v_bad || ' untouched(touched)'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM361', message = format('STOP - sale-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
