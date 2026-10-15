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
-- 20261015015435_bo_2_arrivals_waiting.sql — bo-2 (2026-10-14 밤 · 집 PC · Fable · bo-1d 089d94b 위에)
--   판정 485 ④(입고 → 소통 · 전환) · 482(공급처: IMS 입고는 raw.po_id → po.supplier_id · 그 앞(Cin7 모양)은 제품의 기본 공급처) · 488(다른 창고 손님도 아래에 함께 · 표지) · 484(합치지 않는다 · 각각 진행)
--   ① inv_receipt_events(sku · warehouse · from · to) — 「입고」 정의 하나(원장 po_in · 다른 창고에서 온 transfer_in · qty_delta > 0 · so_backorder_list 의 arrived 규칙과 같다) · so_backorder_overview 와 so_backorder_arrivals 가 같이 쓴다
--   ② so_backorder_overview 재발행 = 20261015005345 본문 바이트 복사 · last_receipt_on 의 lateral 9 줄 → 헬퍼 호출 2 줄(바뀐 줄 · diff 보고) · 그 밖 동일
--   ③ so_backorder_waiting(p_product_id · p_location_id) — 오른쪽: 그 재고 제품을 기다리는 열린 백오더 · 프리오더 줄(콤보 줄은 구성품으로) · 같은 창고 먼저 · can_fill(미리 보기 셈 · 오래 기다린 줄부터 · 다른 창고 null) · 손님 연락(customer_contact 기본 연락처: name · email · phone · mobile_phone) · order_other_skus · proceed_moves_other_skus
--   ④ so_backorder_arrivals(p_filters) — 왼쪽: 기간 안 입고된 재고 제품 × 창고(기본 최근 30 일) · 공급처(판정 482 · 마지막 입고 기준 · 거르기는 어느 입고든) · 기다리는 손님 0 인 입고는 뺀다(include_no_waiting 로 켠다) · available_now · can_fill_now
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 ~/asung/prompts/bo-2-verify.sql

-- ═══ ① inv_receipt_events — 입고 정의 하나 ═══
create function public.inv_receipt_events(p_sku text default null, p_warehouse text default null, p_from date default null, p_to date default null)
  returns table (ledger_id bigint, sku text, warehouse text, occurred_on date, kind text, doc_number text, qty_delta numeric, raw jsonb)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select g.id, g.sku, g.warehouse, g.occurred_on, g.event_type, g.doc_number, g.qty_delta, g.raw
  from public.inv_ledger g
  where (p_sku is null or g.sku = p_sku) and (p_warehouse is null or g.warehouse = p_warehouse)
    and (p_from is null or g.occurred_on >= p_from) and (p_to is null or g.occurred_on <= p_to)
    and g.qty_delta > 0
    and (g.event_type = 'po_in'
         or (g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT'
             and exists (select 1 from public.inv_ledger o
                         where o.doc_number = g.doc_number and o.sku = g.sku and o.event_type = 'transfer_out'
                           and o.warehouse <> 'IN_TRANSIT' and o.warehouse <> g.warehouse)))
$$;
comment on function public.inv_receipt_events(text, text, date, date) is
  'bo-2 속 읽기 — 「입고」 정의 하나(판정 6 · 7 · so_backorder_list 의 arrived 규칙): 원장 po_in · 다른 창고에서 온 transfer_in(같은 doc 의 transfer_out 창고가 다르고 IN_TRANSIT 아님) · qty_delta > 0 · 조정 · 반품 · 조립 · 출발 줄 없는 도착은 입고가 아니다 · sku · warehouse(이름) · 기간(occurred_on)으로 거른다 · so_backorder_overview(last_receipt_on) · so_backorder_arrivals 가 쓴다';
revoke all on function public.inv_receipt_events(text, text, date, date) from public, anon;
grant execute on function public.inv_receipt_events(text, text, date, date) to authenticated;

-- ═══ ② so_backorder_overview 재발행(바이트 복사 · last_receipt_on 만 헬퍼로) ═══
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
    select n.comp_id, n.unit_price, case when ro.is_reorder or an.had_bo then 0 else coalesce(fr.qty, 0) end as bo_qty, fr.on_date
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
    where s.channel = 'warehouse' and s.confirmed_at is not null and not public.so_demand_so_excluded(s.id)
      and l.combo_line_id is null and l.free_reason is null
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
       'rule', 'ordered = warehouse orders with confirmed_at (unconfirmed-then-cancelled excluded), confirmed date (Toronto) in the period = order_from/to else ended_from/to else all · lost = every lost piece whose own date is in the period (ruling 486) · backordered = per cluster once, the first backorder reservation of each line, by its allocated_at; lines of re-orders (take-over or merge targets and their splits) and splits of a line that already had a backorder count 0 (ruling 487) · demand = clusters whose first backorder reservation is in the period'),
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

-- ═══ ③ so_backorder_waiting — 그 재고 제품(세트는 부모로 접힌다 · 콤보는 제 제품)을 기다리는 열린 백오더 · 프리오더 줄 ═══
--   줄 = 수요 줄(combo_line_id null)에 열린 backorder · preorder 예약(그 줄 또는 구성품 줄) · 제품이 그 줄의 제품이거나 구성품 가운데 하나(콤보 줄은 구성품으로 기다린다) · 상태는 안 거른다(진행은 confirmed 만 — can_proceed)
--   단위: qty_open = 판매 단위(so_backorder_list 와 같은 식) · qty_base = 그 제품의 낱개 EA(보통 줄 qty × pack_factor · 콤보 줄 qty × combo_qty × 구성품 pack_factor) · available_now_base = inv_available_base(창고 · 그 제품)의 가용 EA
--   can_fill(판정 488): 같은 창고 줄만 · 오래 기다린 줄부터(days_waiting desc · order_date · so_number · line_no) 가용 EA 를 차례로 나눈 몫 — 미리 보기 셈 · 실제 진행(so_backorder_proceed)은 오더 한 장 단위로 엔진이 다시 계산한다 · 다른 창고 줄은 null
--   days_waiting = 그 줄의 첫 backorder · preorder 예약(allocated_at 최소 · 토론토 날짜)부터 — bo-1c 487 의 「첫 예약」과 같은 정의
create function public.so_backorder_waiting(p_product_id uuid, p_location_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_pid   uuid;
  v_prod  record;
  v_loc   record;
  v_avail numeric;
  v_out   jsonb;
begin
  select coalesce(p.parent_product_id, p.id) into v_pid from public.product p where p.id = p_product_id;
  if v_pid is null then raise exception 'Product not found'; end if;
  select p.id, p.sku, p.name into v_prod from public.product p where p.id = v_pid;
  select w.id, w.name into v_loc from public.ref_warehouse w where w.id = p_location_id;
  if v_loc.id is null then raise exception 'Warehouse not found'; end if;
  select coalesce(b.qty_ea, 0) - coalesce(b.sales_alloc_ea, 0) - coalesce(b.transfer_alloc_ea, 0) into v_avail
  from public.inv_available_base(p_location_id, array[v_pid]) b where b.stock_pid = v_pid;
  v_avail := coalesce(v_avail, 0);

  with ln as (
    select l.id as line_id, l.so_id, l.line_no, l.sku, l.product_name, l.pack_factor, l.unit_price, l.free_reason, l.qty_ordered,
           s.so_number, s.status, s.order_date, s.customer_id, s.location_id, s.location_name,
           q.qty_open, q.kind, q.first_at,
           (coalesce(p.parent_product_id, p.id) <> v_pid) as via_combo,
           case when coalesce(p.parent_product_id, p.id) = v_pid then l.pack_factor
                else (select cp.combo_qty * cp.pack_factor from public.so_line cp join public.product pp on pp.id = cp.product_id
                      where cp.combo_line_id = l.id and coalesce(pp.parent_product_id, pp.id) = v_pid order by cp.line_no limit 1) end as base_per_unit
    from public.so_line l
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, min(res.kind) as kind, min(res.allocated_at) as first_at
                        from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                        where (cp.id = l.id or cp.combo_line_id = l.id) and res.kind in ('backorder', 'preorder') and res.released_at is null) q
    where l.combo_line_id is null and q.qty_open is not null
      and (coalesce(p.parent_product_id, p.id) = v_pid
           or exists (select 1 from public.so_line cp join public.product pp on pp.id = cp.product_id where cp.combo_line_id = l.id and coalesce(pp.parent_product_id, pp.id) = v_pid))
  ),
  x as (
    select ln.*, (ln.location_id = p_location_id) as same_location,
           ln.qty_open * ln.base_per_unit as qty_base,
           (public.ims_today() - (ln.first_at at time zone 'America/Toronto')::date) as days_waiting,
           cu.name as customer_name, cc.name as contact_name, cc.email as contact_email, cc.phone as contact_phone, cc.mobile_phone as contact_mobile,
           (select count(*) from public.so_line o
             where o.so_id = ln.so_id and o.combo_line_id is null and o.id <> ln.line_id
               and exists (select 1 from public.so_reserve r2 join public.so_line cp2 on cp2.id = r2.so_line_id
                           where (cp2.id = o.id or cp2.combo_line_id = o.id) and r2.kind in ('backorder', 'preorder') and r2.released_at is null)) as order_other_skus
    from ln
    join public.customer cu on cu.id = ln.customer_id
    left join public.customer_contact cc on cc.customer_id = cu.id and cc.is_default and cc.is_active
  ),
  ranked as (
    select x.*,
           case when x.same_location then coalesce(sum(x.qty_base) over (partition by x.same_location order by x.days_waiting desc, x.order_date, x.so_number, x.line_no
                                                                        rows between unbounded preceding and 1 preceding), 0) end as before_base
    from x
  ),
  fill as (
    select r.*, case when r.same_location then least(r.qty_base, greatest(v_avail - r.before_base, 0)) end as can_fill_base from ranked r
  )
  select jsonb_build_object(
    'product_id', v_pid, 'sku', v_prod.sku, 'product_name', v_prod.name, 'location_id', v_loc.id, 'location_name', v_loc.name,
    'available_now_base', v_avail,
    'waiting_same', jsonb_build_object('customers', count(distinct customer_id) filter (where same_location), 'lines', count(*) filter (where same_location), 'qty_base', coalesce(sum(qty_base) filter (where same_location), 0)),
    'waiting_other', jsonb_build_object('customers', count(distinct customer_id) filter (where not same_location), 'lines', count(*) filter (where not same_location), 'qty_base', coalesce(sum(qty_base) filter (where not same_location), 0)),
    'can_fill_now_base', coalesce(sum(can_fill_base), 0),
    'can_fill_basis', 'preview only — same-warehouse lines, longest wait first, sharing available_now_base (EA); so_backorder_proceed re-computes per order (all its open backorder and pre-order lines) at the moment it runs',
    'proceed_note', 'so_backorder_proceed takes the whole order: every open backorder and pre-order line of that order is sent to the engine, not only this SKU (proceed_moves_other_skus) · only a confirmed order can proceed (can_proceed) · a line at another warehouse needs a transfer or a warehouse change first (ruling 488)',
    'rows', coalesce(jsonb_agg(jsonb_build_object(
        'kind', f.kind, 'so_id', f.so_id, 'so_number', f.so_number, 'so_status', f.status, 'can_proceed', f.status = 'confirmed', 'order_date', f.order_date,
        'customer_id', f.customer_id, 'customer_name', f.customer_name, 'contact_name', f.contact_name, 'contact_email', f.contact_email, 'contact_phone', f.contact_phone, 'contact_mobile', f.contact_mobile,
        'line_id', f.line_id, 'line_no', f.line_no, 'sku', f.sku, 'product_name', f.product_name, 'via_combo', f.via_combo, 'pack_factor', f.pack_factor, 'base_per_unit', f.base_per_unit,
        'qty_ordered', f.qty_ordered, 'qty_open', f.qty_open, 'qty_base', f.qty_base, 'unit_price', f.unit_price, 'amount', f.qty_open * f.unit_price, 'free_reason', f.free_reason, 'owed', f.free_reason is not null,
        'first_reserved_at', f.first_at, 'days_waiting', f.days_waiting,
        'same_location', f.same_location, 'location_id', f.location_id, 'location_name', f.location_name,
        'order_other_skus', f.order_other_skus, 'proceed_moves_other_skus', f.order_other_skus > 0,
        'can_fill_base', f.can_fill_base, 'can_fill_units', case when f.can_fill_base is null then null else floor(f.can_fill_base / f.base_per_unit) end)
      order by f.same_location desc, f.days_waiting desc, f.order_date, f.so_number, f.line_no), '[]'::jsonb))
  into v_out
  from fill f;
  return v_out;
end;
$$;
comment on function public.so_backorder_waiting(uuid, uuid) is
  '⭐ Backorders 탭 오른쪽(bo-2 · 판정 485 ④ · 488) — 그 재고 제품(세트는 부모로 · 콤보는 제 제품)을 기다리는 열린 백오더 · 프리오더 줄(콤보 줄은 구성품으로) · 같은 창고 줄 먼저(same_location) · days_waiting(첫 예약 allocated_at) · 손님 기본 연락처(customer_contact is_default: name · email · phone · mobile_phone) · qty_open(판매 단위) · qty_base(그 제품 EA) · can_fill_base/units(미리 보기 셈 · 오래 기다린 줄부터 · 다른 창고 null · can_fill_basis) · order_other_skus · proceed_moves_other_skus(진행은 오더 한 장 전부) · can_proceed(confirmed) · 머리 waiting_same · waiting_other · available_now_base · can_fill_now_base · invoker · stable';
revoke all on function public.so_backorder_waiting(uuid, uuid) from public, anon;
grant execute on function public.so_backorder_waiting(uuid, uuid) to authenticated;

-- ═══ ④ so_backorder_arrivals — 기간 안 입고된 재고 제품 × 창고(기다리는 손님이 있는 것만 · include_no_waiting 로 전부) ═══
--   p_filters: location_id · supplier_id(none = 공급처 모름) · brand_id · sku(앞글자) · product_id · received_from · received_to(기본 = 열쇠 둘 다 없으면 최근 30 일) · include_no_waiting · limit(≤ 1000) · offset
--   공급처(판정 482): 입고마다 raw.po_id → po.supplier_id(basis po) · 없으면 제품의 기본 공급처(basis product_default) · 행의 supplier = 마지막 입고의 것 · 거르기는 어느 입고의 공급처든 맞으면
create function public.so_backorder_arrivals(p_filters jsonb default '{}'::jsonb) returns jsonb
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
    select y.stock_pid, s.location_id, s.customer_id, y.so_id, y.qty_base
    from (
      select l.id, l.so_id, coalesce(p.parent_product_id, p.id) as stock_pid, q.qty_open * l.pack_factor as qty_base
      from public.so_line l join public.product p on p.id = l.product_id
      cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open
                          from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                          where (cp.id = l.id or cp.combo_line_id = l.id) and res.kind in ('backorder', 'preorder') and res.released_at is null) q
      where l.combo_line_id is null and q.qty_open is not null
      union all
      select l.id, l.so_id, coalesce(pp.parent_product_id, pp.id), q.qty_open * cp.combo_qty * cp.pack_factor
      from public.so_line l join public.so_line cp on cp.combo_line_id = l.id join public.product pp on pp.id = cp.product_id
      cross join lateral (select min(floor(res.qty_allocated / coalesce(c2.combo_qty, 1))) as qty_open
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
        'available_now_base', coalesce((select b.qty_ea - b.sales_alloc_ea - b.transfer_alloc_ea from public.inv_available_base(p.location_id, array[p.stock_pid]) b where b.stock_pid = p.stock_pid), 0),
        'waiting_same_location', jsonb_build_object('customers', p.same_customers, 'lines', p.same_lines, 'qty_base', p.same_qty_base),
        'waiting_other_locations', jsonb_build_object('customers', p.other_customers, 'lines', p.other_lines, 'qty_base', p.other_qty_base),
        'can_fill_now_base', (public.so_backorder_waiting(p.stock_pid, p.location_id)->>'can_fill_now_base')::numeric)
      order by p.same_qty_base desc, p.last_received_on desc, p.psku) from page p), '[]'::jsonb),
    'elapsed_ms', round(extract(epoch from (clock_timestamp() - v_t0)) * 1000))
  into v_out;
  return v_out;
end;
$$;
comment on function public.so_backorder_arrivals(jsonb) is
  '⭐ Backorders 탭 왼쪽(bo-2 · 판정 485 ④ · 482 · 488) — 기간 안(기본 최근 30 일 · received_from/to) 입고된 재고 제품 × 창고 한 행 · 입고 = inv_receipt_events(po_in · 다른 창고발 transfer_in) · 공급처 = 입고마다 raw.po_id → po.supplier_id(basis po) 아니면 제품 기본 공급처(basis product_default · 판정 482) · 기다리는 손님(열린 백오더 · 프리오더 · 콤보는 구성품으로) 같은 창고 / 다른 창고(판정 488) · 기다리는 줄 0 인 입고는 뺀다(include_no_waiting) · available_now_base · can_fill_now_base(= so_backorder_waiting 의 같은 창고 합) · receipts[] ≤ 20(receipts_truncated) · 필터 location_id · supplier_id(none) · brand_id · sku · product_id · limit ≤ 1000 · offset · 정렬 같은 창고 기다리는 EA 내림 · invoker · stable';
revoke all on function public.so_backorder_arrivals(jsonb) from public, anon;
grant execute on function public.so_backorder_arrivals(jsonb) to authenticated;

-- ═══ ⑤ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text;
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('inv_receipt_events', 'so_backorder_waiting', 'so_backorder_arrivals', 'so_backorder_overview')) <> 4 then v_bad := v_bad || ' functions'; end if;
  select prosrc into v_src from pg_proc where oid = 'public.so_backorder_overview(jsonb)'::regprocedure;
  if v_src !~ 'inv_receipt_events\(p\.sku, v_wh, null, null\)' or v_src ~ 'o\.warehouse <> g\.warehouse' or v_src !~ 'reorder_so' then v_bad := v_bad || ' overview-body'; end if;
  if has_function_privilege('anon', 'public.inv_receipt_events(text, text, date, date)', 'execute') or has_function_privilege('anon', 'public.so_backorder_waiting(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public.so_backorder_arrivals(jsonb)', 'execute') or has_function_privilege('anon', 'public.so_backorder_overview(jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.so_backorder_waiting(uuid, uuid)', 'execute') or not has_function_privilege('authenticated', 'public.so_backorder_arrivals(jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.inv_receipt_events(text, text, date, date)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if (select bool_or(prosecdef or provolatile <> 's') from pg_proc where pronamespace = 'public'::regnamespace and proname in ('inv_receipt_events', 'so_backorder_waiting', 'so_backorder_arrivals', 'so_backorder_overview')) then v_bad := v_bad || ' invoker/stable'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM488', message = format('STOP - bo-2 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
