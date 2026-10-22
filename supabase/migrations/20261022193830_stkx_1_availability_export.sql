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

-- ═══ stkx-1 — Stock Availability 내보내기(CSV) · stk_availability 한 번에 전부 (2026-10-22 · 판정 628 · 동료 피드백 「export 할 수 있으면」) ═══
--   안 A: stk_availability 재발행 — 서명 · 권한 · 바이트 그대로 + 한도 한 줄(500 → 20000) · 화면 보통 목록(PAGE 100)은 무영향 · 쪽마다 전체를 다시 세는 함수라 16 쪽(55 ~ 134 s)보다 한 번(≈ 1.4 s)이 싸다.
--   + 내보내기 창구 stk_availability_export(같은 거르기 인자 · limit · offset 없음) returns jsonb — 식은 두 벌이 아니다(안의 stk_availability 를 20000 으로 한 번 불러 jsonb 로 감싼다) ·
--     ⚠️ PostgREST 의 Max rows(1000)는 집합을 돌려주는 RPC 에도 걸린다(PostgREST 문서 db-max-rows 「applies to all requests including RPC」) — 그래서 내보내기는 한 행(jsonb)으로 돌려준다 · 화면은 rows 를 CSV 로.
--   원가 칸은 없다(판정 262 · 575 — 금액은 stk_value_many · stk_value_total · 원가 열쇠가 있을 때만 화면이 따로) · 원본 20261020232704_stk_av_1_reserved_value_cost_key.sql:150(DB md5 97a3160d2f7a1aaadecbbc9924c65b86 · 137 줄) · 새 md5 fd12bcc1280c2bc952490d240cd58f05
create or replace function public.stk_availability(
  p_warehouse_id uuid, p_q text default null, p_brand_id uuid default null, p_category_id uuid default null,
  p_include_zero boolean default false, p_limit int default 100, p_offset int default 0, p_sale_only boolean default false,
  p_supplier_id uuid default null)
returns table(product_id uuid, sku text, name text, brand_id uuid, brand_name text, category_id uuid, category_name text, is_active boolean,
              on_hand numeric, sales_allocated numeric, transfer_reserved numeric, available numeric, on_order numeric, in_transit numeric, last_event_on date,
              matched_set_sku text, matched_set_pack_factor numeric, matched_set_count int, sale_pct numeric, sale_conditional boolean, total bigint,
              by_warehouse jsonb)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_q      text := nullif(btrim(p_q), '');
  v_limit  int  := least(greatest(coalesce(p_limit, 100), 1), 20000);                                 -- stkx-1 판정 628: 내보내기가 한 번에 전부(500 → 20000 · 재고 키 ≈ 12,400 · 화면 목록은 100 그대로)
  v_offset int  := greatest(coalesce(p_offset, 0), 0);
  v_whs    uuid[];
begin
  -- 문(판정 268) — 로그인 + 활성 직원 · 열쇠는 보지 않는다(판정 258)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  if p_warehouse_id is null then                                                           -- 판정 571 「B」 Both = 활성 창고 전부 · 평평한 열은 합 · by_warehouse 에 창고별
    select coalesce(array_agg(w.id order by w.name), '{}'::uuid[]) into v_whs from public.ref_warehouse w where w.is_active;
    if cardinality(v_whs) = 0 then raise exception 'No active warehouse — nothing was read'; end if;
  else
    if not exists (select 1 from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active) then
      raise exception 'Warehouse not found or inactive — pick an active branch';
    end if;
    v_whs := array[p_warehouse_id];
  end if;
  return query
  with whs as (select w.id, w.name from public.ref_warehouse w where w.id = any(v_whs)),
  av as (                                                                                  -- 장부 · 판매 예약 · 트랜스퍼 예약 — 식 한 곳(inv_available_base) · 창고마다 한 번(lateral)
    select x.id as wh, b.stock_pid, b.qty_ea, b.sales_alloc_ea, b.transfer_alloc_ea from whs x cross join lateral public.inv_available_base(x.id, null) b
  ),
  lastev as (                                                                              -- 뷰는 warehouse(이름)로 걸러야 인덱스로 내려간다 — lateral 의 x.name 은 파라미터라 밀어넣어진다(stk-1 교훈)
    select x.id as wh, le.product_id, le.last_event_on
    from whs x cross join lateral (select b.product_id, max(b.last_event_on) as last_event_on from public.ims_inv_balance b where b.warehouse = x.name and b.product_id is not null group by 1) le
  ),
  onord as (                                                                               -- 판정 260 — 확정 발주 줄 − 확정 입고 줄 · 줄마다 0 아래는 0 · 발주의 배송 창고
    select po.ship_to_warehouse_id as wh, coalesce(pr.parent_product_id, pr.id) as stock_pid, sum(greatest(l.qty_ea - coalesce(rc.recv, 0), 0)) as ea
    from public.po po
    join public.po_line l on l.po_id = po.id
    join public.product pr on pr.id = l.product_id
    left join (select rl.po_line_id, sum(rl.qty_ea) as recv
                 from public.po_receipt_line rl join public.po_receipt r on r.id = rl.receipt_id
                where r.status = 'confirmed' group by 1) rc on rc.po_line_id = l.id
    where po.status = 'confirmed' and po.ship_to_warehouse_id = any(v_whs)
    group by 1, 2
  ),
  intr as (                                                                                -- 운송 중 — 출발했고 아직 도착 창고에 다 들어오지 않은 트랜스퍼 줄 · 도착 창고
    select t.to_warehouse_id as wh, coalesce(pr.parent_product_id, pr.id) as stock_pid,
           sum(greatest(coalesce(l.qty_sent, 0) - coalesce(l.qty_received, 0) - coalesce(l.qty_lost, 0) - coalesce(l.qty_returned, 0), 0) * l.pack_factor) as ea
    from public.inv_transfer t
    join public.inv_transfer_line l on l.transfer_id = t.id
    join public.product pr on pr.id = l.product_id
    where t.status in ('in_transit', 'receiving') and t.to_warehouse_id = any(v_whs)
    group by 1, 2
  ),
  pw as (                                                                                  -- 재고 키 × 고른 창고 — 창고별 한 줄
    select p.id as pid, x.id as wh, x.name as whname,
           coalesce(av.qty_ea, 0) as on_hand, coalesce(av.sales_alloc_ea, 0) as sales_allocated, coalesce(av.transfer_alloc_ea, 0) as transfer_reserved,
           coalesce(onord.ea, 0) as on_order, coalesce(intr.ea, 0) as in_transit, lastev.last_event_on
    from public.product p
    cross join whs x
    left join av     on av.wh = x.id     and av.stock_pid = p.id
    left join lastev on lastev.wh = x.id and lastev.product_id = p.id
    left join onord  on onord.wh = x.id  and onord.stock_pid = p.id
    left join intr   on intr.wh = x.id   and intr.stock_pid = p.id
    where p.parent_product_id is null
  ),
  agg as (                                                                                 -- 평평한 열 = 고른 창고들의 합 · by_warehouse = 창고별(이름 순 · 한 창고면 원소 하나)
    select pw.pid,
           sum(pw.on_hand) as on_hand, sum(pw.sales_allocated) as sales_allocated, sum(pw.transfer_reserved) as transfer_reserved,
           sum(pw.on_order) as on_order, sum(pw.in_transit) as in_transit, max(pw.last_event_on) as last_event_on,
           jsonb_agg(jsonb_build_object('warehouse_id', pw.wh, 'warehouse', pw.whname,
                                        'on_hand', pw.on_hand, 'sales_allocated', pw.sales_allocated, 'transfer_reserved', pw.transfer_reserved,
                                        'available', pw.on_hand - pw.sales_allocated - pw.transfer_reserved,
                                        'on_order', pw.on_order, 'in_transit', pw.in_transit, 'last_event_on', pw.last_event_on) order by pw.whname) as by_warehouse
    from pw group by pw.pid
  ),
  sale as (                                                                                -- sale-1 판정 361: 오늘 세일(so_sale_now · 식 한 곳) — 낱개 줄에 붙인다
    select z.product_id, z.best_pct, z.conditional from public.so_sale_now(null, null) z
  ),
  bc as (                                                                                  -- ⑥ 바코드 정확 일치(product_barcode · 활성) → 그 제품의 재고 키 · 여러 제품이면 전부 · 세트 바코드는 setm 에서 세트 표시
    select coalesce(s.parent_product_id, s.id) as stock_pid
    from public.product_barcode b join public.product s on s.id = b.product_id
    where v_q is not null and b.is_active and b.barcode = v_q
    group by 1
  ),
  setm as (                                                                                -- 판정 261 · 267 — 세트 sku 검색(또는 세트 바코드 정확 일치) → 낱개 줄 · 첫 세트(sku 순) + 개수
    select s.parent_product_id as stock_pid,
           (array_agg(s.sku order by s.sku))[1]         as matched_set_sku,
           (array_agg(s.pack_factor order by s.sku))[1] as matched_set_pack_factor,
           count(*)::int                                as matched_set_count
    from public.product s
    where v_q is not null and s.parent_product_id is not null
      and (s.sku ilike '%' || v_q || '%' or exists (select 1 from public.product_barcode b where b.product_id = s.id and b.is_active and b.barcode = v_q))
    group by 1
  ),
  sup as (                                                                                 -- 판정 570 「A」 — 그 공급처의 활성 줄이 있는 제품 전부(기본 아니어도) · 세트 줄은 낱개로(짐작 확인 8) · 비활성 줄 제외
    select distinct coalesce(sp.parent_product_id, sp.id) as stock_pid
    from public.product_supplier ps join public.product sp on sp.id = ps.product_id
    where p_supplier_id is not null and ps.supplier_id = p_supplier_id and ps.is_active
  ),
  rows_all as (                                                                            -- ⭐ 이 where 는 stk_value_total 의 keys 와 서로 같은 조건 — 한쪽을 고치면 다른 쪽도
    select p.id, p.sku, p.name, p.brand_id, p.brand_name, p.category_id, p.category_name, p.is_active,
           coalesce(agg.on_hand, 0)            as on_hand,
           coalesce(agg.sales_allocated, 0)    as sales_allocated,
           coalesce(agg.transfer_reserved, 0)  as transfer_reserved,
           coalesce(agg.on_hand, 0) - coalesce(agg.sales_allocated, 0) - coalesce(agg.transfer_reserved, 0) as available,
           coalesce(agg.on_order, 0)           as on_order,
           coalesce(agg.in_transit, 0)         as in_transit,
           agg.last_event_on,
           setm.matched_set_sku, setm.matched_set_pack_factor, setm.matched_set_count,
           sale.best_pct as sale_pct, sale.conditional as sale_conditional,
           agg.by_warehouse
    from public.product p                                                                -- 줄 = 재고 키 = 낱개(세트 · 콤보 줄 없음 · 판정 261)
    left join agg    on agg.pid          = p.id
    left join setm   on setm.stock_pid   = p.id
    left join sale   on sale.product_id  = p.id
    left join bc     on bc.stock_pid     = p.id
    left join sup    on sup.stock_pid    = p.id
    where p.parent_product_id is null
      and (not p_sale_only or sale.product_id is not null)                                                             -- sale-1 판정 361: 세일 제품만
      and not exists (select 1 from public.product_bom bm where bm.parent_product_id = p.id and bm.is_active)
      and (p_brand_id is null or p.brand_id = p_brand_id)
      and (p_category_id is null or p.category_id = p_category_id)
      and (p_supplier_id is null or sup.stock_pid is not null)
      and (v_q is null or p.sku ilike '%' || v_q || '%' or p.name ilike '%' || v_q || '%' or p.brand_name ilike '%' || v_q || '%' or setm.stock_pid is not null or bc.stock_pid is not null)
  ),
  rows_kept as (
    select r.* from rows_all r
    where p_include_zero
       or r.on_hand <> 0 or r.sales_allocated <> 0 or r.transfer_reserved <> 0 or r.on_order <> 0 or r.in_transit <> 0   -- 판정 266 — 다섯 숫자(Both 는 합) 모두 0 인 줄만 뺀다
  )
  select r.id, r.sku, r.name, r.brand_id, r.brand_name, r.category_id, r.category_name, r.is_active,
         r.on_hand, r.sales_allocated, r.transfer_reserved, r.available, r.on_order, r.in_transit, r.last_event_on,
         r.matched_set_sku, r.matched_set_pack_factor, r.matched_set_count,
         r.sale_pct, r.sale_conditional,
         count(*) over () as total,
         r.by_warehouse
  from rows_kept r
  order by r.sku, r.id
  limit v_limit offset v_offset;
end;
$$;

create function public.stk_availability_export(p_warehouse_id uuid, p_q text default null, p_brand_id uuid default null, p_category_id uuid default null,
                                               p_include_zero boolean default false, p_sale_only boolean default false, p_supplier_id uuid default null) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  -- stkx-1 판정 628: 화면 그대로 CSV — 같은 거르기 · 모든 쪽 · 같은 칸 · 한 행(jsonb)이라 PostgREST Max rows(1000)에 안 잘린다 · 문 · 열쇠는 stk_availability 의 것(로그인 + 활성 직원)
  select jsonb_build_object('total', coalesce(max(r.total), 0), 'row_count', count(*), 'truncated', coalesce(max(r.total), 0) > 20000,
                            'rows', coalesce(jsonb_agg(to_jsonb(r) - 'total' order by r.sku, r.product_id), '[]'::jsonb))
  from public.stk_availability(p_warehouse_id, p_q, p_brand_id, p_category_id, p_include_zero, 20000, 0, p_sale_only, p_supplier_id) r
$$;
revoke all on function public.stk_availability_export(uuid, text, uuid, uuid, boolean, boolean, uuid) from public, anon, service_role;
grant execute on function public.stk_availability_export(uuid, text, uuid, uuid, boolean, boolean, uuid) to authenticated;
comment on function public.stk_availability_export(uuid, text, uuid, uuid, boolean, boolean, uuid) is 'stkx-1 판정 628 — Stock Availability 내보내기: stk_availability(같은 거르기 · 20000 · 0)를 한 번 불러 {total, row_count, truncated, rows[]} 한 행으로 · 원가 칸 없음 · 문 = 로그인 + 활성 직원(안의 창구가 본다)';

-- ═══ 착지 — 몸 md5 · 서명 하나 · ACL 무변 · 내보내기 창구 ACL · 다른 stk_ 무변 · 새 표 0 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'stk_availability') <> 1 then v_bad := v_bad || ' overloads'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'stk_availability') <> 'fd12bcc1280c2bc952490d240cd58f05' then v_bad := v_bad || ' body'; end if;
  if (select p.proacl::text || ':' || p.prosecdef::text || ':' || p.provolatile::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'stk_availability') <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}:true:s' then v_bad := v_bad || ' acl'; end if;
  if (select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'stk_availability') !~ '20000' then v_bad := v_bad || ' limit_text'; end if;
  if not has_function_privilege('authenticated', 'public.stk_availability_export(uuid, text, uuid, uuid, boolean, boolean, uuid)', 'execute') or has_function_privilege('anon', 'public.stk_availability_export(uuid, text, uuid, uuid, boolean, boolean, uuid)', 'execute') or has_function_privilege('service_role', 'public.stk_availability_export(uuid, text, uuid, uuid, boolean, boolean, uuid)', 'execute') then v_bad := v_bad || ' export_acl'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('stk_bins', 'stk_bins_many', 'stk_movements', 'stk_reserved', 'stk_value_many', 'stk_value_total', 'inv_available_base', 'so_sale_now', 'pur_stock'))
     <> 'inv_available_base=fd141ec16a8b98aad23eb1b17dadc0ab pur_stock=d217ac939873ef36e8ae1e2677eb4996 so_sale_now=7391d9d3436ad22edda0a75a99fc904a stk_bins=2b4d86b893608a999cc86dc2eeba3cec stk_bins_many=6e618902010d900ea3286b565feaef7b stk_movements=4b4ff9f9565024d1649d014300520f3e stk_reserved=bf0e12bb8140f1e5b8ae19a3beca3cb5 stk_value_many=ec34616819df603b297e7c87bcb7e93b stk_value_total=49c1828b00299c002a70cb7e176cd569' then v_bad := v_bad || ' others_changed'; end if;
  if v_bad <> '' then raise exception 'stkx-1 landing check failed:%', v_bad; end if;
end $$;
