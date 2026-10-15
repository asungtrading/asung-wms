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
-- 20261015024520_bo_2b_ready_fixes.sql — bo-2b (2026-10-14 밤 · 집 PC · Fable · bo-2 a183aef · 화면 bo v4 2b10305 위에)
--   ① so_backorder_arrivals 재발행 — include_no_waiting true 의 statement timeout: 실측(테스트 DB · postgres · timeout 끔) 기본 30 일 · limit 200 = 16,775 ms · limit 20 = 2,335 ms · 기다리는 행만(2) = 312 ms · 행 하나 = inv_available_base 95 ms + so_backorder_waiting 183 ms
--      ⇒ 가용은 창고마다 한 번(쪽의 재고 제품 배열 · 창고 전체 7,670 행 251 ms) · can_fill_now_base 는 집합으로(wait CTE 에 first_on · order_date · so_number · line_no 를 더해 so_backorder_waiting 과 같은 순서) · 기다리는 같은 창고 줄이 없는 행은 0 · 반환 모양 · 거르기 · 정렬 그대로
--   ② so_backorder_ready(p_filters) — 판정 490: 입고와 상관없이 그 오더 창고에 지금 가용이 있어 can_fill > 0 인 열린 백오더 · 프리오더 줄(confirmed 만) · so_backorder_waiting 의 행 열쇠 그대로 + product_id · stock_sku · available_now_base · arrived_in_period · components(콤보)
--   ③ so_backorder_overview 재발행 — 판정 491(표식 줄은 backordered 에서도 0) · 492(분모 ordered 도 sku · brand · supplier · product 를 줄 단위로 거른다 · 거르기 없으면 그대로)
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 ~/asung/prompts/bo-2b-verify.sql

-- ═══ ① so_backorder_arrivals 재발행(20261015015435 본문 바이트 복사 + wait CTE 칸 넷 · avail · cf CTE · rows 두 줄) ═══
create or replace function public.so_backorder_arrivals(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['location_id','supplier_id','brand_id','sku','product_id','received_from','received_to','include_no_waiting','limit','offset'];
  v_bad    text;
  v_limit  int  := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int  := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_from   date := coalesce((f->>'received_from')::date, case when f->>'received_to' is null then public.ims_today() - 30 end);
  v_to     date := (f->>'received_to')::date;
  v_all    boolean := coalesce((f->>'include_no_waiting')::boolean, false);
  v_wh     text;
  v_t0     timestamptz := clock_timestamp();
  v_out    jsonb;
begin
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;
  if f->>'location_id' is not null then
    select w.name into v_wh from public.ref_warehouse w where w.id = (f->>'location_id')::uuid;
    if v_wh is null then raise exception 'Warehouse not found'; end if;
  end if;

  with ev as (                                                                                      -- 기간 안 입고 사건 → 재고 제품 · 창고 · 공급처
    select e.ledger_id, e.occurred_on, e.kind, e.doc_number, e.qty_delta,
           p.id as stock_pid, p.sku as psku, p.name as product_name, p.brand_id, p.brand_name,
           w.id as location_id, w.name as location_name,
           case when e.raw->>'po_id' is not null then (select po.supplier_id from public.po po where po.id = (e.raw->>'po_id')::uuid) end as po_supplier_id
    from public.inv_receipt_events(null, v_wh, v_from, v_to) e
    join public.product p on p.sku = e.sku and p.parent_product_id is null
    join public.ref_warehouse w on w.name = e.warehouse
  ),
  ev2 as (
    select ev.*, coalesce(ev.po_supplier_id, ps.supplier_id) as supplier_id,
           case when ev.po_supplier_id is not null then 'po' when ps.supplier_id is not null then 'product_default' end as supplier_basis
    from ev left join public.product_supplier ps on ps.product_id = ev.stock_pid and ps.is_default and ps.is_active
  ),
  grp as (
    select stock_pid, psku, product_name, brand_id, brand_name, location_id, location_name,
           sum(qty_delta) as received_base, count(*) as receipts_n, max(occurred_on) as last_received_on,
           (array_agg(supplier_id order by occurred_on desc, ledger_id desc))[1] as supplier_id,
           (array_agg(supplier_basis order by occurred_on desc, ledger_id desc))[1] as supplier_basis,
           array_agg(distinct supplier_id) filter (where supplier_id is not null) as supplier_ids,
           jsonb_agg(jsonb_build_object('occurred_on', occurred_on, 'kind', kind, 'doc_number', doc_number, 'qty_base', qty_delta, 'supplier_id', supplier_id, 'supplier_basis', supplier_basis) order by occurred_on desc, ledger_id desc) as receipts_all
    from ev2
    group by stock_pid, psku, product_name, brand_id, brand_name, location_id, location_name
  ),
  wait as (                                                                                        -- 열린 백오더 · 프리오더 수요 줄 → 기다리는 재고 제품(보통 줄 = 제 제품 · 콤보 줄 = 구성품마다)
    select y.stock_pid, s.location_id, s.customer_id, y.so_id, y.qty_base,
           (y.first_at at time zone 'America/Toronto')::date as first_on, s.order_date, s.so_number, y.line_no                                -- bo-2b: can_fill 순서(so_backorder_waiting 과 같다 — 오래 기다린 줄부터 · order_date · so_number · line_no)
    from (
      select l.id, l.so_id, l.line_no, coalesce(p.parent_product_id, p.id) as stock_pid, q.qty_open * l.pack_factor as qty_base, q.first_at
      from public.so_line l join public.product p on p.id = l.product_id
      cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, min(res.allocated_at) as first_at
                          from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                          where (cp.id = l.id or cp.combo_line_id = l.id) and res.kind in ('backorder', 'preorder') and res.released_at is null) q
      where l.combo_line_id is null and q.qty_open is not null
      union all
      select l.id, l.so_id, l.line_no, coalesce(pp.parent_product_id, pp.id), q.qty_open * cp.combo_qty * cp.pack_factor, q.first_at
      from public.so_line l join public.so_line cp on cp.combo_line_id = l.id join public.product pp on pp.id = cp.product_id
      cross join lateral (select min(floor(res.qty_allocated / coalesce(c2.combo_qty, 1))) as qty_open, min(res.allocated_at) as first_at
                          from public.so_reserve res join public.so_line c2 on c2.id = res.so_line_id
                          where (c2.id = l.id or c2.combo_line_id = l.id) and res.kind in ('backorder', 'preorder') and res.released_at is null) q
      where l.combo_line_id is null and q.qty_open is not null
    ) y join public.so s on s.id = y.so_id
  ),
  base as (
    select g.*,
           (select count(distinct w.customer_id) from wait w where w.stock_pid = g.stock_pid and w.location_id = g.location_id) as same_customers,
           (select count(*) from wait w where w.stock_pid = g.stock_pid and w.location_id = g.location_id) as same_lines,
           (select coalesce(sum(w.qty_base), 0) from wait w where w.stock_pid = g.stock_pid and w.location_id = g.location_id) as same_qty_base,
           (select count(distinct w.customer_id) from wait w where w.stock_pid = g.stock_pid and w.location_id is distinct from g.location_id) as other_customers,
           (select count(*) from wait w where w.stock_pid = g.stock_pid and w.location_id is distinct from g.location_id) as other_lines,
           (select coalesce(sum(w.qty_base), 0) from wait w where w.stock_pid = g.stock_pid and w.location_id is distinct from g.location_id) as other_qty_base
    from grp g
  ),
  filtered as (
    select * from base b
    where (v_all or b.same_lines + b.other_lines > 0)
      and (f->>'supplier_id' is null or (f->>'supplier_id' = 'none' and b.supplier_ids is null) or (f->>'supplier_id' <> 'none' and (f->>'supplier_id')::uuid = any(coalesce(b.supplier_ids, '{}'::uuid[]))))
      and (f->>'brand_id'   is null or b.brand_id = (f->>'brand_id')::uuid)
      and (f->>'sku'        is null or b.psku ilike (f->>'sku') || '%')
      and (f->>'product_id' is null or b.stock_pid = (f->>'product_id')::uuid)
  ),
  page as (
    select * from filtered order by same_qty_base desc, last_received_on desc, psku limit v_limit offset v_offset
  ),
  avail as (                                                                                       -- bo-2b: 가용은 창고마다 한 번(쪽의 재고 제품을 배열로) — 행마다 부르면 200 행에 16.8 초(실측)
    select lw.location_id, b.stock_pid, coalesce(b.qty_ea, 0) - coalesce(b.sales_alloc_ea, 0) - coalesce(b.transfer_alloc_ea, 0) as avail
    from (select pg.location_id, array_agg(distinct pg.stock_pid) as pids from page pg group by pg.location_id) lw
    cross join lateral public.inv_available_base(lw.location_id, lw.pids) b
  ),
  cf as (                                                                                          -- bo-2b: can_fill_now_base 를 집합으로(기다리는 같은 창고 줄이 있는 행만 · 규칙 = so_backorder_waiting · 오래 기다린 줄부터 가용을 나눈다)
    select z.stock_pid, z.location_id, sum(least(z.qty_base, greatest(z.avail - z.before_base, 0))) as can_fill_base
    from (select w.stock_pid, w.location_id, w.qty_base, coalesce(a.avail, 0) as avail,                                                     -- bo-2b: 잔고 행이 없는 제품은 inv_available_base 가 행을 안 낸다 → 가용 0
                 coalesce(sum(w.qty_base) over (partition by w.stock_pid, w.location_id order by w.first_on asc, w.order_date, w.so_number, w.line_no rows between unbounded preceding and 1 preceding), 0) as before_base
          from wait w left join avail a on a.stock_pid = w.stock_pid and a.location_id = w.location_id) z
    group by z.stock_pid, z.location_id
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered), 'limit', v_limit, 'offset', v_offset, 'filters', f,
    'period_from', v_from, 'period_to', v_to, 'include_no_waiting', v_all,
    'supplier_rule', 'per receipt: raw.po_id → po.supplier_id (basis po, IMS receipts) else the product''s default supplier (basis product_default, Cin7-era receipts) — ruling 482 · row supplier = the latest receipt''s · the supplier filter matches any receipt in the period',
    'waiting_rule', 'open backorder and pre-order demand lines waiting for this stock product (a combo line waits through its components) · same = order warehouse is the receipt warehouse · other = another warehouse (ruling 488: shown too, needs a transfer or a warehouse change before it can proceed) · rows with no waiting line are left out unless include_no_waiting',
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'product_id', p.stock_pid, 'sku', p.psku, 'product_name', p.product_name, 'brand_id', p.brand_id, 'brand_name', p.brand_name,
        'supplier_id', p.supplier_id, 'supplier_name', (select s.name from public.supplier s where s.id = p.supplier_id), 'supplier_basis', p.supplier_basis,
        'location_id', p.location_id, 'location_name', p.location_name,
        'received_base', p.received_base, 'receipts_n', p.receipts_n, 'last_received_on', p.last_received_on,
        'receipts', (select coalesce(jsonb_agg(r), '[]'::jsonb) from (select r from jsonb_array_elements(p.receipts_all) r limit 20) z), 'receipts_truncated', p.receipts_n > 20,
        'available_now_base', coalesce((select a.avail from avail a where a.stock_pid = p.stock_pid and a.location_id = p.location_id), 0),                        -- bo-2b
        'waiting_same_location', jsonb_build_object('customers', p.same_customers, 'lines', p.same_lines, 'qty_base', p.same_qty_base),
        'waiting_other_locations', jsonb_build_object('customers', p.other_customers, 'lines', p.other_lines, 'qty_base', p.other_qty_base),
        'can_fill_now_base', case when p.same_lines > 0 then coalesce((select c.can_fill_base from cf c where c.stock_pid = p.stock_pid and c.location_id = p.location_id), 0) else 0 end)   -- bo-2b
      order by p.same_qty_base desc, p.last_received_on desc, p.psku) from page p), '[]'::jsonb),
    'elapsed_ms', round(extract(epoch from (clock_timestamp() - v_t0)) * 1000))
  into v_out;
  return v_out;
end;
$$;

-- ═══ ② so_backorder_ready — 지금 보낼 수 있는 백오더(판정 490) ═══
--   줄 = so_backorder_waiting 과 같은 열린 백오더 · 프리오더 수요 줄 · 오더 confirmed(진행할 수 있는 것) · 기다리는 재고 제품 = 보통 줄의 제품 · 콤보 줄은 구성품마다
--   가용 = 오더 창고마다 inv_available_base 한 번(그 창고가 기다리는 재고 제품 배열) · 나눔 = 재고 제품 × 창고마다 오래 기다린 줄부터(first_on · order_date · so_number · line_no — so_backorder_waiting 과 같다) · 콤보 줄 = 구성품마다 나눈 몫 ÷ (combo_qty × pack_factor) 의 최소(통째 콤보 수 · so_backorder_list 의 available_here 와 같은 뜻) · 하나라도 0 이면 빠진다
create function public.so_backorder_ready(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['location_id','supplier_id','brand_id','sku','product_id','kind','limit','offset'];
  v_bad    text;
  v_kind   text := nullif(f->>'kind', '');
  v_limit  int  := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int  := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_t0     timestamptz := clock_timestamp();
  v_out    jsonb;
begin
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;
  if v_kind is not null and v_kind not in ('backorder', 'preorder') then raise exception 'kind must be backorder or preorder'; end if;

  with ln as (                                                                                      -- 열린 백오더 · 프리오더 수요 줄(confirmed)
    select l.id as line_id, l.so_id, l.line_no, l.sku, l.product_name, l.pack_factor, l.unit_price, l.free_reason, l.qty_ordered, l.product_id,
           coalesce(p.parent_product_id, p.id) as stock_pid, p.brand_id,
           s.so_number, s.status, s.order_date, s.customer_id, s.location_id, s.location_name,
           q.qty_open, q.kind, q.first_at, (q.first_at at time zone 'America/Toronto')::date as first_on,
           exists (select 1 from public.so_line cp where cp.combo_line_id = l.id) as is_combo
    from public.so_line l
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, min(res.kind) as kind, min(res.allocated_at) as first_at
                        from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                        where (cp.id = l.id or cp.combo_line_id = l.id) and res.kind in ('backorder', 'preorder') and res.released_at is null) q
    where l.combo_line_id is null and q.qty_open is not null and s.status = 'confirmed' and s.location_id is not null
  ),
  ent as (                                                                                          -- 기다리는 재고 제품 단위(보통 줄 = 제 제품 · 콤보 줄 = 구성품마다)
    select ln.line_id, ln.location_id, ln.stock_pid as need_pid, ln.pack_factor as per_unit, ln.qty_open * ln.pack_factor as qty_base, ln.first_on, ln.order_date, ln.so_number, ln.line_no,
           null::uuid as comp_line_id, ln.sku as need_sku
    from ln where not ln.is_combo
    union all
    select ln.line_id, ln.location_id, coalesce(pp.parent_product_id, pp.id), cp.combo_qty * cp.pack_factor, ln.qty_open * cp.combo_qty * cp.pack_factor, ln.first_on, ln.order_date, ln.so_number, ln.line_no,
           cp.id, coalesce(pps.sku, pp.sku)
    from ln join public.so_line cp on cp.combo_line_id = ln.line_id join public.product pp on pp.id = cp.product_id left join public.product pps on pps.id = pp.parent_product_id
    where ln.is_combo
  ),
  avail as (                                                                                        -- 창고마다 한 번
    select lw.location_id, b.stock_pid, coalesce(b.qty_ea, 0) - coalesce(b.sales_alloc_ea, 0) - coalesce(b.transfer_alloc_ea, 0) as avail
    from (select e.location_id, array_agg(distinct e.need_pid) as pids from ent e group by e.location_id) lw
    cross join lateral public.inv_available_base(lw.location_id, lw.pids) b
  ),
  share as (                                                                                        -- 재고 제품 × 창고마다 오래 기다린 줄부터 나눈다
    select e.*, coalesce(a.avail, 0) as avail,                                                                                             -- 잔고 행이 없는 제품은 inv_available_base 가 행을 안 낸다 → 가용 0(콤보 구성품이 빠지면 통째 수가 틀어진다)
           least(e.qty_base, greatest(coalesce(a.avail, 0) - coalesce(sum(e.qty_base) over (partition by e.need_pid, e.location_id order by e.first_on asc, e.order_date, e.so_number, e.line_no, e.comp_line_id
                                                                               rows between unbounded preceding and 1 preceding), 0), 0)) as fill_base
    from ent e left join avail a on a.stock_pid = e.need_pid and a.location_id = e.location_id
  ),
  per_line as (                                                                                     -- 줄마다: 보통 줄 = 그 몫 · 콤보 줄 = 구성품 가운데 최소 통째 수
    select sh.line_id,
           min(floor(sh.fill_base / sh.per_unit)) as can_fill_units,
           min(floor(sh.avail / sh.per_unit)) as avail_units,
           jsonb_agg(jsonb_build_object('sku', sh.need_sku, 'product_id', sh.need_pid, 'base_per_unit', sh.per_unit, 'available_now_base', sh.avail, 'can_fill_base', sh.fill_base, 'can_fill_units', floor(sh.fill_base / sh.per_unit)) order by sh.need_sku) filter (where sh.comp_line_id is not null) as components,
           bool_or(exists (select 1 from public.inv_receipt_events(sh.need_sku, (select w.name from public.ref_warehouse w where w.id = sh.location_id), public.ims_today() - 30, null))) as arrived_in_period
    from share sh group by sh.line_id
  ),
  rows_ as (
    select ln.*, pl.can_fill_units, pl.avail_units, pl.components, pl.arrived_in_period,
           sp.sku as stock_sku, sp.name as stock_name,
           (public.ims_today() - ln.first_on) as days_waiting,
           cu.name as customer_name, cc.name as contact_name, cc.email as contact_email, cc.phone as contact_phone, cc.mobile_phone as contact_mobile,
           ps.supplier_id,
           (select count(*) from public.so_line o
             where o.so_id = ln.so_id and o.combo_line_id is null and o.id <> ln.line_id
               and exists (select 1 from public.so_reserve r2 join public.so_line cp2 on cp2.id = r2.so_line_id
                           where (cp2.id = o.id or cp2.combo_line_id = o.id) and r2.kind in ('backorder', 'preorder') and r2.released_at is null)) as order_other_skus
    from ln
    join per_line pl on pl.line_id = ln.line_id
    join public.product sp on sp.id = ln.stock_pid
    join public.customer cu on cu.id = ln.customer_id
    left join public.customer_contact cc on cc.customer_id = cu.id and cc.is_default and cc.is_active
    left join public.product_supplier ps on ps.product_id = ln.stock_pid and ps.is_default and ps.is_active
    where pl.can_fill_units > 0
  ),
  filtered as (
    select * from rows_ r
    where (f->>'location_id' is null or r.location_id = (f->>'location_id')::uuid)
      and (f->>'supplier_id' is null or (f->>'supplier_id' = 'none' and r.supplier_id is null) or (f->>'supplier_id' <> 'none' and r.supplier_id = (f->>'supplier_id')::uuid))
      and (f->>'brand_id'    is null or r.brand_id = (f->>'brand_id')::uuid)
      and (f->>'sku'         is null or r.sku ilike (f->>'sku') || '%' or r.stock_sku ilike (f->>'sku') || '%'
           or exists (select 1 from jsonb_array_elements(coalesce(r.components, '[]'::jsonb)) j where j->>'sku' ilike (f->>'sku') || '%'))
      and (f->>'product_id'  is null or r.stock_pid = (f->>'product_id')::uuid or r.product_id = (f->>'product_id')::uuid)
      and (v_kind is null or r.kind = v_kind)
  )
  select jsonb_build_object(
    'as_of', public.ims_today(), 'filters', f, 'limit', v_limit, 'offset', v_offset,
    'total', count(*), 'orders', count(distinct so_id),
    'can_fill_basis', 'preview only — open backorder and pre-order lines of confirmed orders whose own warehouse has stock now: available_now_base (EA) shared longest wait first per stock product and warehouse (same rule as so_backorder_waiting); a combo line needs every component (whole combos); so_backorder_proceed re-computes per order at the moment it runs',
    'proceed_note', 'so_backorder_proceed takes the whole order: every open backorder and pre-order line of that order is sent to the engine, not only this line (proceed_moves_other_skus) · independent of receipts (ruling 490) — stock may come from adjustments, returns, cancelled orders or counts',
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'kind', r.kind, 'so_id', r.so_id, 'so_number', r.so_number, 'so_status', r.status, 'can_proceed', true, 'order_date', r.order_date,
        'customer_id', r.customer_id, 'customer_name', r.customer_name, 'contact_name', r.contact_name, 'contact_email', r.contact_email, 'contact_phone', r.contact_phone, 'contact_mobile', r.contact_mobile,
        'line_id', r.line_id, 'line_no', r.line_no, 'sku', r.sku, 'product_name', r.product_name, 'via_combo', false, 'is_combo', r.is_combo, 'pack_factor', r.pack_factor, 'base_per_unit', r.pack_factor,
        'qty_ordered', r.qty_ordered, 'qty_open', r.qty_open, 'qty_base', r.qty_open * r.pack_factor, 'unit_price', r.unit_price, 'amount', r.qty_open * r.unit_price, 'free_reason', r.free_reason, 'owed', r.free_reason is not null,
        'first_reserved_at', r.first_at, 'days_waiting', r.days_waiting,
        'same_location', true, 'location_id', r.location_id, 'location_name', r.location_name,
        'order_other_skus', r.order_other_skus, 'proceed_moves_other_skus', r.order_other_skus > 0,
        'can_fill_base', r.can_fill_units * r.pack_factor, 'can_fill_units', r.can_fill_units,
        'product_id', r.stock_pid, 'stock_sku', r.stock_sku, 'stock_name', r.stock_name, 'brand_id', r.brand_id, 'supplier_id', r.supplier_id,
        'available_now_base', r.avail_units * r.pack_factor, 'available_now_units', r.avail_units, 'arrived_in_period', r.arrived_in_period, 'components', r.components)
      order by r.days_waiting desc, r.order_date, r.so_number, r.line_no)
      from (select * from filtered order by days_waiting desc, order_date, so_number, line_no limit v_limit offset v_offset) r), '[]'::jsonb),
    'elapsed_ms', round(extract(epoch from (clock_timestamp() - v_t0)) * 1000))
  into v_out
  from filtered;
  return v_out;
end;
$$;
comment on function public.so_backorder_ready(jsonb) is
  '⭐ Arrivals 맨 위 「지금 보낼 수 있는 백오더」(bo-2b · 판정 490) — 입고와 상관없이 그 오더 창고에 지금 가용이 있어 can_fill > 0 인 열린 백오더 · 프리오더 수요 줄(confirmed 만 · 콤보 줄은 구성품 전부 — 통째 콤보 수) · 행 열쇠 = so_backorder_waiting 의 행 그대로(same_location true · can_proceed true · via_combo false) + product_id · stock_sku · stock_name · brand_id · supplier_id · is_combo · available_now_base/units · arrived_in_period(최근 30 일 입고) · components[] · 나눔 규칙 = 재고 제품 × 창고마다 오래 기다린 줄부터(can_fill_basis) · 거르기 location_id · supplier_id(none · 제품 기본 공급처) · brand_id · sku · product_id · kind · limit ≤ 1000 · offset · 정렬 days_waiting 내림 · 머리 total · orders · proceed_note · invoker · stable';
revoke all on function public.so_backorder_ready(jsonb) from public, anon;
grant execute on function public.so_backorder_ready(jsonb) to authenticated;

-- ═══ ③ so_backorder_overview 재발행(20261015015435 본문 바이트 복사 + 491 한 줄 · 492 줄 단위 거르기 · 표지 둘) ═══
create or replace function public.so_backorder_overview(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['customer_id','supplier_id','brand_id','sku','product_id','location_id','order_from','order_to','ended_from','ended_to','open','flagged','limit','offset','currency','sort'];
  c_sorts  constant text[] := array['lost_amount','lost','demand_then','open_backorder','customers_waiting','repeat_asks','days_waiting_max'];
  v_bad    text;
  v_sort   text := coalesce(nullif(f->>'sort', ''), 'lost_amount');
  v_limit  int  := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int  := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_d      jsonb;
  v_d2     jsonb;                                                                                   -- 판정 486: 분자 재료(기간 열쇠를 뺀 덩어리 전부 · 몫마다 제 날짜로 거른다)
  v_from   date := coalesce((f->>'order_from')::date, (f->>'ended_from')::date);
  v_to     date := coalesce((f->>'order_to')::date, (f->>'ended_to')::date);
  v_wh     text;
  v_t0     timestamptz := clock_timestamp();
  v_out    jsonb;
begin
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;
  if v_sort <> all (c_sorts) then raise exception 'sort must be one of %', array_to_string(c_sorts, ', '); end if;
  if f->>'location_id' is not null then select w.name into v_wh from public.ref_warehouse w where w.id = (f->>'location_id')::uuid; end if;
  v_d := public.so_backorder_demand((f - 'sort' - 'limit' - 'offset') || '{"limit": 1000, "offset": 0}'::jsonb);        -- 수요는 정본 하나에서(덩어리 전부 · 상한 1000)
  if v_from is null and v_to is null then v_d2 := v_d;
  else v_d2 := public.so_backorder_demand((f - 'sort' - 'limit' - 'offset' - 'order_from' - 'order_to' - 'ended_from' - 'ended_to') || '{"limit": 1000, "offset": 0}'::jsonb);   -- 판정 486: 분자 재료는 기간 없이 · 몫마다 거른다
  end if;

  with cl as (
    select r.value as r, (r.value->>'product_id')::uuid as product_id, (r.value->>'customer_id')::uuid as customer_id,
           (r.value->>'open_backorder')::numeric as open_bo, (r.value->>'first_order_date')::date as first_order_date
    from jsonb_array_elements(v_d->'rows') r
  ),
  ln as (                                                                                           -- ③ 덩어리의 줄(repeat_asks 의 재료)
    select c.product_id, (j->>'line_id')::uuid as line_id, (j->>'unit_price')::numeric as unit_price
    from cl c cross join lateral jsonb_array_elements(c.r->'lines') j
  ),
  cl2 as (                                                                                          -- 판정 486: 분자 재료 덩어리(기간 열쇠 없이)
    select r.value as r, (r.value->>'comp_id')::uuid as comp_id, (r.value->>'demand_then')::numeric as demand_then, (r.value->>'demand_amount')::numeric as demand_amount
    from jsonb_array_elements(v_d2->'rows') r
  ),
  ln2 as (
    select c.comp_id, (j->>'line_id')::uuid as line_id, (j->>'unit_price')::numeric as unit_price, (j->'flag') is not null and jsonb_typeof(j->'flag') <> 'null' as flagged,
           (j->'lost_by'->>'cancelled')::numeric as lost_cancelled
    from cl2 c cross join lateral jsonb_array_elements(c.r->'lines') j
  ),
  piece as (                                                                                        -- 판정 486 v3: 잃은 몫마다 제 날짜(토론토) · 표식 줄은 뺀다
    select n.line_id, n.unit_price, c.end_kind as kind,
           case c.end_kind when 'superseded' then c.qty_unwanted when 'expired' then c.qty_open when 'cancelled' then c.qty_open else 0 end as qty,
           (c.ended_at at time zone 'America/Toronto')::date as on_date
    from ln2 n join public.so_backorder_close c on c.so_line_id = n.line_id and c.reopened_at is null
    where not n.flagged and c.end_kind in ('superseded', 'expired', 'cancelled')
    union all
    select n.line_id, n.unit_price, 'removed', l.qty_removed, (l.removed_at at time zone 'America/Toronto')::date                      -- 475: 마무리(so_finalize)가 찍은 removed_at
    from ln2 n join public.so_line l on l.id = n.line_id where not n.flagged and l.qty_removed > 0
    union all
    select n.line_id, n.unit_price, 'cancelled',                                                                                        -- 476 · 483: 취소 오더의 남은 몫 = 줄의 lost_cancelled − 장부 cancelled 행 · 날짜 so.closed_at
           n.lost_cancelled - coalesce((select sum(c.qty_open) from public.so_backorder_close c where c.so_line_id = n.line_id and c.reopened_at is null and c.end_kind = 'cancelled'), 0),
           (s.closed_at at time zone 'America/Toronto')::date
    from ln2 n join public.so_line l on l.id = n.line_id join public.so s on s.id = l.so_id where not n.flagged and s.status = 'cancelled'
  ),
  piece_p as (
    select * from piece p where p.qty > 0 and (v_from is null or p.on_date >= v_from) and (v_to is null or p.on_date <= v_to)
  ),
  reorder_so as (                                                                                   -- 판정 487: 다시 주문 오더 = 이어받은 새 오더 · 병합의 새 오더
    select c.taken_by_so_id as so_id from public.so_backorder_close c where c.reopened_at is null and c.taken_by_so_id is not null
    union select s.merged_into_id from public.so s where s.merged_into_id is not null
  ),
  bo_line as (                                                                                      -- 판정 487: 줄의 첫 백오더 예약 · 다시 주문 오더(와 split 자손)의 줄 · 백오더가 있던 줄의 split 자손 줄은 0 · 축 = 첫 예약 allocated_at(토론토)
    select n.comp_id, n.unit_price, case when ro.is_reorder or an.had_bo or n.flagged then 0 else coalesce(fr.qty, 0) end as bo_qty, fr.on_date   -- bo-2b 판정 491: 표식 줄은 「백오더가 된 금액」에서도 0
    from ln2 n
    join public.so_line l on l.id = n.line_id
    cross join lateral (
      with recursive up as (select s.id, s.split_from_id from public.so s where s.id = l.so_id
                            union all select s.id, s.split_from_id from public.so s join up on s.id = up.split_from_id)
      select exists (select 1 from up u join reorder_so x on x.so_id = u.id) as is_reorder
    ) ro
    cross join lateral (
      with recursive anc as (select x.id, x.split_from_line_id from public.so_line x where x.id = l.split_from_line_id
                             union all select x.id, x.split_from_line_id from public.so_line x join anc on x.id = anc.split_from_line_id)
      select exists (select 1 from anc a join public.so_line cp on (cp.id = a.id or cp.combo_line_id = a.id) join public.so_reserve r on r.so_line_id = cp.id and r.kind = 'backorder') as had_bo
    ) an
    cross join lateral (
      select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty, (min(res.allocated_at) at time zone 'America/Toronto')::date as on_date
      from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
      where (cp.id = l.id or cp.combo_line_id = l.id) and res.kind = 'backorder'
        and res.allocated_at = (select min(r2.allocated_at) from public.so_reserve r2 join public.so_line c2 on c2.id = r2.so_line_id
                                 where (c2.id = l.id or c2.combo_line_id = l.id) and r2.kind = 'backorder')
    ) fr
  ),
  bo_p as (select * from bo_line b where b.bo_qty > 0 and (v_from is null or b.on_date >= v_from) and (v_to is null or b.on_date <= v_to)),
  cl_p as (                                                                                         -- 분자의 덩어리(demand): 첫 백오더 예약 날이 기간 안
    select c.* from cl2 c
    where exists (select 1 from bo_line b where b.comp_id = c.comp_id and b.bo_qty > 0 and (v_from is null or b.on_date >= v_from) and (v_to is null or b.on_date <= v_to))
  ),
  ordered as (                                                                                      -- ② 분모
    select coalesce(sum(l.qty_ordered), 0) as qty, sum(l.qty_ordered * l.unit_price) as amount, count(*) filter (where l.unit_price is null) as price_missing, count(distinct s.id) as orders
    from public.so s join public.so_line l on l.so_id = s.id
    join public.product lp on lp.id = l.product_id                                                                                          -- bo-2b 판정 492: 분모도 줄 단위로 거른다(재고 제품 = 부모로 접힘 · 콤보 줄은 제 제품)
    left join public.product sp on sp.id = coalesce(lp.parent_product_id, lp.id)
    left join public.product_supplier ps on ps.product_id = sp.id and ps.is_default and ps.is_active
    where s.channel = 'warehouse' and s.confirmed_at is not null and not public.so_demand_so_excluded(s.id)
      and l.combo_line_id is null and l.free_reason is null
      and (f->>'sku'         is null or sp.sku ilike (f->>'sku') || '%' or l.sku ilike (f->>'sku') || '%')                                    -- bo-2b 판정 492
      and (f->>'brand_id'    is null or sp.brand_id = (f->>'brand_id')::uuid)
      and (f->>'supplier_id' is null or (f->>'supplier_id' = 'none' and ps.supplier_id is null) or (f->>'supplier_id' <> 'none' and ps.supplier_id = (f->>'supplier_id')::uuid))
      and (f->>'product_id'  is null or sp.id = (f->>'product_id')::uuid or l.product_id = (f->>'product_id')::uuid)
      and (v_from is null or (s.confirmed_at at time zone 'America/Toronto')::date >= v_from)
      and (v_to   is null or (s.confirmed_at at time zone 'America/Toronto')::date <= v_to)
      and (f->>'customer_id' is null or s.customer_id = (f->>'customer_id')::uuid)
      and (f->>'location_id' is null or s.location_id = (f->>'location_id')::uuid)
      and (f->>'currency'    is null or s.currency_code = f->>'currency')
  ),
  sku as (                                                                                          -- ③ 재고 제품 하나 = 한 행
    select c.product_id,
           (array_agg(c.r->>'sku' order by c.first_order_date))[1] as sku, (array_agg(c.r->>'product_name' order by c.first_order_date))[1] as product_name,
           (array_agg(c.r->>'brand_id' order by c.first_order_date))[1] as brand_id, (array_agg(c.r->>'brand_name' order by c.first_order_date))[1] as brand_name,
           (array_agg(c.r->>'supplier_id' order by c.first_order_date))[1] as supplier_id, (array_agg(c.r->>'supplier_name' order by c.first_order_date))[1] as supplier_name,
           (array_agg(c.r->>'currency' order by c.first_order_date))[1] as currency, max((c.r->>'currency_n')::int) as currency_n_max,
           count(distinct c.customer_id) filter (where c.open_bo > 0) as customers_waiting,
           count(distinct c.customer_id) as customers_in_period,
           count(*) as clusters, count(*) filter (where c.open_bo > 0) as clusters_open,
           max(public.ims_today() - c.first_order_date) filter (where c.open_bo > 0) as days_waiting_max,
           round(avg(public.ims_today() - c.first_order_date) filter (where c.open_bo > 0), 1) as days_waiting_avg,
           min(c.first_order_date) as first_ask_on,
           sum((c.r->>'demand_then')::numeric) as demand_then, sum((c.r->>'sold')::numeric) as sold, sum((c.r->>'lost')::numeric) as lost,
           sum((c.r->>'lost_amount')::numeric) as lost_amount, sum((c.r->>'open_backorder')::numeric) as open_backorder, sum((c.r->>'open_backorder_amount')::numeric) as open_backorder_amount,
           sum((c.r->>'demand_amount')::numeric) as demand_amount, sum((c.r->>'sold_amount')::numeric) as sold_amount,
           sum((c.r->>'price_missing')::int) as price_missing, sum((c.r->>'flagged')::numeric) as flagged
    from cl c group by c.product_id
  ),
  sku2 as (
    select k.*, p.sku as base_sku,
           (select count(distinct c2.taken_by_so_id) from public.so_backorder_close c2
             where c2.end_kind = 'superseded' and c2.reopened_at is null
               and c2.so_line_id in (select n.line_id from ln n where n.product_id = k.product_id)) as repeat_asks,
           (select count(distinct s2.customer_id) from public.so_backorder_close c2 join public.so_line l2 on l2.id = c2.so_line_id join public.so s2 on s2.id = l2.so_id
             where c2.end_kind = 'superseded' and c2.reopened_at is null
               and c2.so_line_id in (select n.line_id from ln n where n.product_id = k.product_id)) as repeat_customers,
           rc.last_receipt_on
    from sku k
    join public.product p on p.id = k.product_id
    cross join lateral (
      select max(e.occurred_on) as last_receipt_on from public.inv_receipt_events(p.sku, v_wh, null, null) e                         -- bo-2: 입고 정의는 inv_receipt_events 하나(so_backorder_arrivals 와 같은 식)
    ) rc
  ),
  ranked as (
    select k.*, (k.last_receipt_on is null or k.last_receipt_on < k.first_ask_on) as no_receipt_since_first_ask,
           row_number() over (order by
             case v_sort when 'lost_amount' then k.lost_amount when 'lost' then k.lost when 'demand_then' then k.demand_then when 'open_backorder' then k.open_backorder
                         when 'customers_waiting' then k.customers_waiting when 'repeat_asks' then k.repeat_asks when 'days_waiting_max' then k.days_waiting_max end desc nulls last,
             k.lost desc, k.sku) as rn
    from sku2 k
  )
  select jsonb_build_object(
    'as_of', public.ims_today(), 'filters', f, 'sort', v_sort, 'limit', v_limit, 'offset', v_offset,
    'clusters', (v_d->>'total')::int, 'truncated', (v_d->>'total')::int >= 1000,
    'share', jsonb_build_object(
       'stock_sku_active', (select count(*) from public.product p where p.is_active and p.parent_product_id is null),
       'stock_sku_open_backorder', (select count(distinct c.product_id) from cl c where c.open_bo > 0),
       'stock_sku_backordered_in_period', (select count(distinct c.product_id) from cl c),
       'pct_open', round(100.0 * (select count(distinct c.product_id) from cl c where c.open_bo > 0) / nullif((select count(*) from public.product p where p.is_active and p.parent_product_id is null), 0), 2),
       'pct_in_period', round(100.0 * (select count(distinct c.product_id) from cl c) / nullif((select count(*) from public.product p where p.is_active and p.parent_product_id is null), 0), 2),
       'rule', 'stock product = product.is_active and parent_product_id is null (sets fold into their parent; a combo is its own product) · open = at least one open backorder cluster · in_period = clusters that pass the filters'),
    'lost_sales', jsonb_build_object(
       'period_from', v_from, 'period_to', v_to,
       'basis', 'lost_in_period_over_ordered_in_period',                                                                                     -- 판정 486
       'numerator_date', 'lost: each lost piece by its own date (Toronto) — ledger ended_at (unwanted · expired · cancelled rows) · so_line.removed_at (removed) · so.closed_at (cancelled-order remainder, incl. web auto-cancel) · backordered and demand: first backorder reservation allocated_at of the line / cluster · flagged lines excluded',
       'denominator_date', 'so.confirmed_at (Toronto)',
       'denominator_filters', 'line level: sku (stock sku or line sku prefix) · brand · supplier (product default) · product (stock or line) follow the same filter keys (ruling 492) · customer · location · currency at order level · no filter = whole company',
       'flag_rule', 'lines with an active not-real-demand flag count 0 in backordered as well as in lost (ruling 491)',
       'clusters_in_period', (select count(*) from cl_p),
       'ordered_qty', (select qty from ordered), 'ordered_amount', (select amount from ordered), 'ordered_orders', (select orders from ordered), 'ordered_price_missing', (select price_missing from ordered),
       'backordered_qty', (select coalesce(sum(bo_qty), 0) from bo_p), 'backordered_amount', (select coalesce(sum(bo_qty * unit_price), 0) from bo_p),   -- 판정 487 · 축 = 첫 예약 allocated_at
       'demand_then', (select coalesce(sum(demand_then), 0) from cl_p), 'demand_amount', (select coalesce(sum(demand_amount), 0) from cl_p),
       'lost', (select coalesce(sum(qty), 0) from piece_p), 'lost_amount', (select coalesce(sum(qty * unit_price), 0) from piece_p),                -- 빈 합은 0 · 단가 없는 몫은 lost_price_missing                       -- 판정 486 v3: 몫마다 제 날짜
       'lost_by', (select jsonb_build_object('unwanted', coalesce(sum(qty) filter (where kind = 'superseded'), 0), 'expired', coalesce(sum(qty) filter (where kind = 'expired'), 0),
                                             'cancelled', coalesce(sum(qty) filter (where kind = 'cancelled'), 0), 'removed', coalesce(sum(qty) filter (where kind = 'removed'), 0)) from piece_p),
       'lost_amount_by', (select jsonb_build_object('unwanted', coalesce(sum(qty * unit_price) filter (where kind = 'superseded'), 0), 'expired', coalesce(sum(qty * unit_price) filter (where kind = 'expired'), 0),
                                                    'cancelled', coalesce(sum(qty * unit_price) filter (where kind = 'cancelled'), 0), 'removed', coalesce(sum(qty * unit_price) filter (where kind = 'removed'), 0)) from piece_p),
       'lost_price_missing', (select count(*) from piece_p where unit_price is null),
       'pct_of_ordered', round(100.0 * (select coalesce(sum(qty * unit_price), 0) from piece_p) / nullif((select amount from ordered), 0), 2),
       'price_missing', (v_d2->'amount_sums'->>'price_missing')::int, 'currencies', v_d2->'amount_sums'->'currencies',
       'rule', 'ordered = warehouse orders with confirmed_at (unconfirmed-then-cancelled excluded), confirmed date (Toronto) in the period = order_from/to else ended_from/to else all · lost = every lost piece whose own date is in the period (ruling 486) · backordered = per cluster once, the first backorder reservation of each line, by its allocated_at; lines of re-orders (take-over or merge targets and their splits) and splits of a line that already had a backorder count 0 (ruling 487) · flagged lines count 0 (ruling 491) · demand = clusters whose first backorder reservation is in the period · ordered filters by sku · brand · supplier · product at line level (ruling 492)'),
    'total_skus', (select count(*) from ranked),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'product_id', k.product_id, 'sku', k.sku, 'base_sku', k.base_sku, 'product_name', k.product_name, 'brand_id', k.brand_id, 'brand_name', k.brand_name,
        'supplier_id', k.supplier_id, 'supplier_name', k.supplier_name, 'currency', k.currency, 'currency_mixed', k.currency_n_max > 1,
        'customers_waiting', k.customers_waiting, 'customers_in_period', k.customers_in_period, 'repeat_asks', k.repeat_asks, 'repeat_customers', k.repeat_customers,
        'clusters', k.clusters, 'clusters_open', k.clusters_open, 'days_waiting_max', k.days_waiting_max, 'days_waiting_avg', k.days_waiting_avg, 'first_ask_on', k.first_ask_on,
        'demand_then', k.demand_then, 'demand_amount', k.demand_amount, 'sold', k.sold, 'sold_amount', k.sold_amount, 'lost', k.lost, 'lost_amount', k.lost_amount,
        'open_backorder', k.open_backorder, 'open_backorder_amount', k.open_backorder_amount, 'flagged', k.flagged, 'price_missing', k.price_missing,
        'last_receipt_on', k.last_receipt_on, 'no_receipt_since_first_ask', k.no_receipt_since_first_ask, 'rank', k.rn)
      order by k.rn) from ranked k where k.rn > v_offset and k.rn <= v_offset + v_limit), '[]'::jsonb),
    'elapsed_ms', round(extract(epoch from (clock_timestamp() - v_t0)) * 1000))
  into v_out;
  return v_out;
end;
$$;

-- ═══ ④ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text;
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_backorder_ready', 'so_backorder_arrivals', 'so_backorder_overview', 'so_backorder_waiting')) <> 4 then v_bad := v_bad || ' functions'; end if;
  select prosrc into v_src from pg_proc where oid = 'public.so_backorder_arrivals(jsonb)'::regprocedure;
  if v_src !~ 'cf as \(' or v_src ~ 'so_backorder_waiting\(p\.stock_pid' or v_src !~ 'supplier_rule' then v_bad := v_bad || ' arrivals-body'; end if;
  select prosrc into v_src from pg_proc where oid = 'public.so_backorder_overview(jsonb)'::regprocedure;
  if v_src !~ 'or n\.flagged then 0' or v_src !~ 'denominator_filters' or v_src !~ 'inv_receipt_events\(p\.sku, v_wh, null, null\)' or v_src !~ 'reorder_so' then v_bad := v_bad || ' overview-body'; end if;
  if has_function_privilege('anon', 'public.so_backorder_ready(jsonb)', 'execute') or not has_function_privilege('authenticated', 'public.so_backorder_ready(jsonb)', 'execute')
     or has_function_privilege('anon', 'public.so_backorder_arrivals(jsonb)', 'execute') or has_function_privilege('anon', 'public.so_backorder_overview(jsonb)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if (select bool_or(prosecdef or provolatile <> 's') from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_backorder_ready', 'so_backorder_arrivals', 'so_backorder_overview')) then v_bad := v_bad || ' invoker/stable'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM490', message = format('STOP - bo-2b did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
