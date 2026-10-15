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
-- 20261015005345_bo_1c_demand_amount_overview.sql — bo-1c (2026-10-14 밤 · 집 PC · Fable · bo-1a dee6d70 위에)
--   판정 485(Backorders 탭 목적 넷 가운데 ① 비중 ② 잃은 세일 규모 ③ 반복해서 못 대는 SKU — 읽기)
--   ① so_backorder_demand 재발행 = 20261014234811 본문 바이트 복사 + 더한 줄 29(금액 칸 · 통화 · ordered · transferred · amount_sums · 거르기 currency) · 바뀐 줄 3(create or replace · c_keys 상수 · rows 닫는 줄) · 열쇠는 더하기만
--      금액 = 그 몫의 수량 × 그 줄의 so_line.unit_price(정의 주석 20260923182231:72 「⭐ 할인 뒤 단가(판매 단위) … null = 가격 없음 · 0 = 무상」 · 실물 349 줄: list_price × (1 − discount_pct/100) = unit_price 어긋남 0) · 세금 · 운임 · 오더 할인 · 쿠폰 제외
--      몫이 온 줄의 단가 그대로(다시 주문 줄은 그 줄의 단가 · 티어) · 단가 null 줄은 금액 null(합에서 빠진다) + price_missing · 통화는 오더 currency_code(덩어리에 currency · currency_n · 거르기 currency) — 실물 so 92 건 전부 CAD
--   ② 새 읽기 so_backorder_overview(p_filters) — ① 비중 ② 잃은 세일 규모 ③ SKU 순위 · 수요 숫자는 so_backorder_demand 를 불러 얻는다(셈은 하나가 정본)
--   판정 486(Caleb 2026-10-14 밤 · v3): ② 비율 = 기간 안에 잃은 것 ÷ 기간 안 확정된 주문 금액 · 반환에 basis 표지 · 분자는 「잃은 몫마다 그 몫이 끝난 날」로 거른다 — 장부 행 ended_at(superseded.qty_unwanted · expired.qty_open · cancelled.qty_open) · 뺀 몫 so_line.removed_at(475 · so_finalize 20260924202425 ①) ·
--      취소 오더의 남은 몫 so.closed_at(476 · CHECK so_closed_at_ck · 483 웹 자동 취소도 이것 — 옛 줄의 superseded 행은 unwanted 0 이라 잃은 몫이 아니다) · 전부 토론토 날짜 · 표식 줄의 몫은 뺀다 · backordered · demand 의 축 = 첫 백오더 예약의 allocated_at(토론토)
--      기간 열쇠(order_from/to 또는 ended_from/to)를 「기간」 하나로 읽는다 · 분자 재료는 기간 열쇠를 뺀 so_backorder_demand 호출(v_d2 · 덩어리 전부) · share · ③ 은 준 거르기 그대로(so_backorder_demand 의 order_from/to 는 첫 주문일 · ended_from/to 는 마지막 끝난 날에 걸린다 · 20261014234811 filtered CTE)
--   판정 487(Caleb 2026-10-14 밤): backordered = 덩어리마다 한 번 · 처음에 바로 못 보낸 몫만 — 줄의 첫 백오더 예약 수량(allocated_at 최소) · 다시 주문 오더(활성 superseded 장부의 taken_by_so_id · 병합 merged_into_id 와 그 split 자손)의 줄과 백오더가 있던 줄에서 갈라진 자손 줄(split_from_line_id 사슬)은 세지 않는다
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 ~/asung/prompts/bo-1c-verify.sql

-- ═══ ① so_backorder_demand 재발행(바이트 복사 + 더한 줄 · 줄 끝 -- bo-1c) ═══
create or replace function public.so_backorder_demand(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['customer_id','supplier_id','brand_id','sku','product_id','location_id','order_from','order_to','ended_from','ended_to','open','flagged','limit','offset','currency'];   -- bo-1c: + currency
  v_bad    text;
  v_limit  int := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_out    jsonb;
begin
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;

  with recursive
  seed as (                                                                                        -- 백오더가 한 번이라도 있었던 수요 줄
    select l.id
    from public.so_line l join public.so s on s.id = l.so_id
    where l.combo_line_id is null and l.free_reason is null and s.channel = 'warehouse' and not public.so_demand_so_excluded(s.id)
      and (exists (select 1 from public.so_reserve r join public.so_line cp on cp.id = r.so_line_id
                   where (cp.id = l.id or cp.combo_line_id = l.id) and r.kind = 'backorder')
           or exists (select 1 from public.so_backorder_close c where c.so_line_id = l.id))
  ),
  edge as (                                                                                        -- 연결 셋(양방향)
    select e.a, e.b from (
      select l.split_from_line_id as a, l.id as b from public.so_line l where l.split_from_line_id is not null
      union all select c.so_line_id, c.taken_by_line_id from public.so_backorder_close c where c.taken_by_line_id is not null and c.reopened_at is null
      union all select m.from_line_id, m.line_id from public.so_line_merge_source m
    ) e
    union
    select e.b, e.a from (
      select l.split_from_line_id as a, l.id as b from public.so_line l where l.split_from_line_id is not null
      union all select c.so_line_id, c.taken_by_line_id from public.so_backorder_close c where c.taken_by_line_id is not null and c.reopened_at is null
      union all select m.from_line_id, m.line_id from public.so_line_merge_source m
    ) e
  ),
  reach (seed_id, id) as (
    select s.id, s.id from seed s
    union
    select r.seed_id, e.b from reach r join edge e on e.a = r.id
  ),
  comp_of_seed as (select r.seed_id, min(r.id::text)::uuid as comp_id from reach r group by r.seed_id),   -- min(uuid) 집계가 없다 → text 로
  node as (select distinct r.id, cs.comp_id from reach r join comp_of_seed cs on cs.seed_id = r.seed_id),
  line as (                                                                                        -- 덩어리의 수요 줄 + 줄 셈 + 활성 표식
    select n.comp_id, l.id as line_id, l.so_id, s.so_number, s.channel, s.customer_id, s.location_id, s.location_name, s.order_date,
           l.line_no, l.product_id, l.sku, l.product_name, l.pack_factor,
           coalesce(p.parent_product_id, p.id) as stock_pid,
           d.*,
           fl.id as flag_id, fl.reason as flag_reason, fl.note as flag_note, fl.flagged_at, fl.flagged_by,
           case when fl.id is not null then d.lost else 0 end as flagged_qty,
           l.unit_price, s.currency_code,                                                                                                    -- bo-1c: 할인 뒤 단가(so_line.unit_price 주석 「할인 뒤 단가」 · null = 가격 없음) · 오더 통화
           d.demand * l.unit_price as demand_amount, d.sold * l.unit_price as sold_amount, d.lost * l.unit_price as lost_amount,            -- bo-1c: 금액 = 그 몫 × 그 줄의 단가(세금 · 운임 · 오더 할인 · 쿠폰 제외) · 단가 null 이면 null
           d.lost_unwanted * l.unit_price as lost_unwanted_amount, d.lost_expired * l.unit_price as lost_expired_amount,
           d.lost_cancelled * l.unit_price as lost_cancelled_amount, d.lost_removed * l.unit_price as lost_removed_amount,
           d.in_progress * l.unit_price as in_progress_amount, d.open_backorder * l.unit_price as open_backorder_amount,
           case when fl.id is not null then d.lost else 0 end * l.unit_price as flagged_amount,
           (select max(c.ended_at) from public.so_backorder_close c where c.so_line_id = l.id and c.reopened_at is null) as last_ended_at
    from node n
    join public.so_line l on l.id = n.id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    cross join lateral public.so_demand_line(l.id) d
    left join public.so_demand_flag fl on fl.active_line_id = l.id
    where l.combo_line_id is null and l.free_reason is null and s.channel = 'warehouse' and not public.so_demand_so_excluded(s.id)
  ),
  grp as (
    select x.comp_id,
           (array_agg(x.customer_id order by x.order_date, x.so_number, x.line_no))[1] as customer_id,
           (array_agg(x.stock_pid   order by x.order_date, x.so_number, x.line_no))[1] as stock_pid,
           (array_agg(x.location_id order by x.order_date, x.so_number, x.line_no))[1] as location_id,
           (array_agg(x.location_name order by x.order_date, x.so_number, x.line_no))[1] as location_name,
           count(distinct x.customer_id) as customer_n, count(distinct x.stock_pid) as product_n,
           min(x.order_date) as first_order_date, max(x.last_ended_at) as last_ended_at,
           count(*) as line_n,
           sum(x.demand) as demand_raw, sum(x.sold) as sold, sum(x.lost) as lost_raw, sum(x.in_progress) as in_progress, sum(x.open_backorder) as open_backorder,
           sum(x.flagged_qty) as flagged,
           sum(x.lost_unwanted) as lost_unwanted, sum(x.lost_expired) as lost_expired, sum(x.lost_cancelled) as lost_cancelled, sum(x.lost_removed) as lost_removed,
           sum(x.in_progress) filter (where x.so_status = 'draft') as ip_draft,
           sum(x.in_progress) filter (where x.so_status = 'confirmed') as ip_confirmed,
           sum(x.in_progress) filter (where x.so_status in ('at_wms', 'picking', 'packed')) as ip_warehouse,
           sum(x.in_progress) filter (where x.so_status not in ('draft', 'confirmed', 'at_wms', 'picking', 'packed')) as ip_other,
           count(*) filter (where x.flag_id is not null) as flagged_lines,
           sum(x.ordered) as ordered, sum(x.transferred) as transferred,                                                                     -- bo-1c: demand_raw = ordered − transferred
           sum(x.demand_amount) as demand_amount_raw, sum(x.sold_amount) as sold_amount, sum(x.lost_amount) as lost_amount_raw,              -- bo-1c: 금액 합(단가 있는 줄만 · sum 은 null 을 건너뛴다)
           sum(x.lost_unwanted_amount) as lost_unwanted_amount, sum(x.lost_expired_amount) as lost_expired_amount,
           sum(x.lost_cancelled_amount) as lost_cancelled_amount, sum(x.lost_removed_amount) as lost_removed_amount,
           sum(x.in_progress_amount) as in_progress_amount, sum(x.open_backorder_amount) as open_backorder_amount, sum(x.flagged_amount) as flagged_amount,
           count(*) filter (where x.unit_price is null) as price_missing,                                                                    -- bo-1c: 가격 없는 줄 수(그 줄의 금액은 합에 없다)
           count(distinct x.currency_code) as currency_n, min(x.currency_code) as currency,                                                 -- bo-1c: 통화가 섞이면 currency_n > 1(합치지 않는다 — 화면이 가른다)
           jsonb_agg(jsonb_build_object(
             'line_id', x.line_id, 'so_id', x.so_id, 'so_number', x.so_number, 'so_status', x.so_status, 'order_date', x.order_date, 'line_no', x.line_no,
             'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name, 'pack_factor', x.pack_factor, 'location_name', x.location_name,
             'ordered', x.ordered, 'sold', x.sold, 'removed', x.removed, 'transferred', x.transferred, 'demand', x.demand,
             'lost', x.lost, 'lost_by', jsonb_build_object('unwanted', x.lost_unwanted, 'expired', x.lost_expired, 'cancelled', x.lost_cancelled, 'removed', x.lost_removed),
             'in_progress', x.in_progress, 'open_backorder', x.open_backorder, 'end_kinds', x.end_kinds, 'last_ended_at', x.last_ended_at,
             'unit_price', x.unit_price, 'currency', x.currency_code,                                                                      -- bo-1c
             'amount', jsonb_build_object('demand', x.demand_amount, 'sold', x.sold_amount, 'lost', x.lost_amount, 'in_progress', x.in_progress_amount, 'open_backorder', x.open_backorder_amount, 'flagged', x.flagged_amount),
             'flag', case when x.flag_id is null then null else jsonb_build_object('id', x.flag_id, 'reason', x.flag_reason, 'note', x.flag_note, 'flagged_at', x.flagged_at, 'flagged_by', x.flagged_by, 'qty', x.flagged_qty) end
           ) order by x.order_date, x.so_number, x.line_no) as lines,
           array_agg(distinct x.so_number) as so_numbers
    from line x
    group by x.comp_id
  ),
  base as (
    select g.*, cu.name as customer_name, sp.id as product_id, sp.sku as stock_sku, sp.name as stock_name, sp.brand_id, sp.brand_name,
           ps.supplier_id, su.name as supplier_name,
           g.demand_raw - g.flagged as demand_then, g.lost_raw - g.flagged as lost
           , g.demand_amount_raw - coalesce(g.flagged_amount, 0) as demand_amount, g.lost_amount_raw - coalesce(g.flagged_amount, 0) as lost_amount   -- bo-1c: 표식 몫은 금액에서도 함께 뺀다
    from grp g
    join public.customer cu on cu.id = g.customer_id
    join public.product sp on sp.id = g.stock_pid
    left join public.product_supplier ps on ps.product_id = sp.id and ps.is_default and ps.is_active
    left join public.supplier su on su.id = ps.supplier_id
  ),
  filtered as (
    select * from base b
    where (f->>'customer_id' is null or b.customer_id = (f->>'customer_id')::uuid)
      and (f->>'supplier_id' is null or (f->>'supplier_id' = 'none' and b.supplier_id is null) or (f->>'supplier_id' <> 'none' and b.supplier_id = (f->>'supplier_id')::uuid))
      and (f->>'brand_id'    is null or b.brand_id = (f->>'brand_id')::uuid)
      and (f->>'sku'         is null or b.stock_sku ilike (f->>'sku') || '%' or exists (select 1 from jsonb_array_elements(b.lines) j where j->>'sku' ilike (f->>'sku') || '%'))
      and (f->>'product_id'  is null or b.product_id = (f->>'product_id')::uuid or exists (select 1 from jsonb_array_elements(b.lines) j where (j->>'product_id')::uuid = (f->>'product_id')::uuid))
      and (f->>'location_id' is null or b.location_id = (f->>'location_id')::uuid)
      and (f->>'order_from'  is null or b.first_order_date >= (f->>'order_from')::date)
      and (f->>'order_to'    is null or b.first_order_date <= (f->>'order_to')::date)
      and (f->>'ended_from'  is null or (b.last_ended_at at time zone 'America/Toronto')::date >= (f->>'ended_from')::date)
      and (f->>'ended_to'    is null or (b.last_ended_at at time zone 'America/Toronto')::date <= (f->>'ended_to')::date)
      and (f->>'open'        is null or (b.open_backorder > 0) = (f->>'open')::boolean)
      and (f->>'flagged'     is null or (b.flagged_lines > 0) = (f->>'flagged')::boolean)
      and (f->>'currency'    is null or b.currency = f->>'currency')                                                                         -- bo-1c
  )
  select jsonb_build_object(
    'total', count(*), 'limit', v_limit, 'offset', v_offset, 'filters', f,
    'sums', jsonb_build_object('demand_then', coalesce(sum(demand_then), 0), 'sold', coalesce(sum(sold), 0), 'lost', coalesce(sum(lost), 0),
                               'in_progress', coalesce(sum(in_progress), 0), 'open_backorder', coalesce(sum(open_backorder), 0), 'flagged', coalesce(sum(flagged), 0)),
    'identity', 'demand_then = sold + lost + in_progress + open_backorder (after flags) · demand_then = Σ(ordered − transferred) − flagged · lost = unwanted + expired + cancelled(ledger + cancelled-order remainder) + removed − flagged',
    'amount_sums', jsonb_build_object('demand_amount', coalesce(sum(demand_amount), 0), 'sold_amount', coalesce(sum(sold_amount), 0), 'lost_amount', coalesce(sum(lost_amount), 0),                          -- bo-1c
                                      'in_progress_amount', coalesce(sum(in_progress_amount), 0), 'open_backorder_amount', coalesce(sum(open_backorder_amount), 0), 'flagged_amount', coalesce(sum(flagged_amount), 0),
                                      'price_missing', coalesce(sum(price_missing), 0), 'currencies', (select coalesce(jsonb_agg(distinct currency), '[]'::jsonb) from filtered)),
    'amount_rule', 'amount = qty × so_line.unit_price (discounted unit price; tax, freight, order discount and coupon excluded) · unit_price null = price missing (counted in price_missing, left out of the sums) · a cluster with currency_n > 1 mixes currencies',
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'comp_id', x.comp_id, 'customer_id', x.customer_id, 'customer_name', x.customer_name,
        'product_id', x.product_id, 'sku', x.stock_sku, 'product_name', x.stock_name, 'brand_id', x.brand_id, 'brand_name', x.brand_name,
        'supplier_id', x.supplier_id, 'supplier_name', x.supplier_name, 'location_id', x.location_id, 'location_name', x.location_name,
        'first_order_date', x.first_order_date, 'last_ended_at', x.last_ended_at, 'so_numbers', to_jsonb(x.so_numbers), 'line_n', x.line_n,
        'demand_then', x.demand_then, 'sold', x.sold, 'lost', x.lost, 'in_progress', x.in_progress, 'open_backorder', x.open_backorder, 'flagged', x.flagged,
        'demand_raw', x.demand_raw, 'lost_raw', x.lost_raw,
        'lost_by', jsonb_build_object('unwanted', x.lost_unwanted, 'expired', x.lost_expired, 'cancelled', x.lost_cancelled, 'removed', x.lost_removed),
        'in_progress_by', jsonb_build_object('draft', coalesce(x.ip_draft, 0), 'confirmed', coalesce(x.ip_confirmed, 0), 'warehouse', coalesce(x.ip_warehouse, 0), 'other', coalesce(x.ip_other, 0)),
        'flagged_lines', x.flagged_lines, 'customer_n', x.customer_n, 'product_n', x.product_n, 'lines', x.lines,
        'ordered', x.ordered, 'transferred', x.transferred,                                                                                   -- bo-1c: demand_raw = ordered − transferred · demand_then = demand_raw − flagged
        'demand_amount', x.demand_amount, 'sold_amount', x.sold_amount, 'lost_amount', x.lost_amount, 'in_progress_amount', x.in_progress_amount, 'open_backorder_amount', x.open_backorder_amount,
        'flagged_amount', coalesce(x.flagged_amount, 0), 'demand_amount_raw', x.demand_amount_raw, 'lost_amount_raw', x.lost_amount_raw,
        'lost_amount_by', jsonb_build_object('unwanted', x.lost_unwanted_amount, 'expired', x.lost_expired_amount, 'cancelled', x.lost_cancelled_amount, 'removed', x.lost_removed_amount),
        'price_missing', x.price_missing, 'currency', x.currency, 'currency_n', x.currency_n)
      order by x.customer_name, x.customer_id, x.stock_sku, x.first_order_date, x.comp_id)
      from (select * from filtered order by customer_name, customer_id, stock_sku, first_order_date, comp_id limit v_limit offset v_offset) x), '[]'::jsonb))
  into v_out
  from filtered;
  return v_out;
end;
$$;
comment on function public.so_backorder_demand(jsonb) is
  '⭐ 백오더 수요 읽기(bo-1a · 판정 464 · 475 ~ 478 · 483 · bo-1c 금액) — 단위 = 손님 × 재고 제품의 연결 덩어리(씨앗 = 백오더가 한 번이라도 있었던 수요 줄 · 변 셋 split_from_line_id · 활성 장부 taken_by_line_id · so_line_merge_source · 양방향 재귀 · 병합 겹셈 없음) · 덩어리마다 demand_then · sold · lost(lost_by) · in_progress(in_progress_by) · open_backorder · flagged · ordered · transferred(demand_raw = ordered − transferred · demand_then = demand_raw − flagged) · lines[] · 항등식 demand_then = sold + lost + in_progress + open_backorder · bo-1c 금액 = 몫 × 그 줄의 unit_price(할인 뒤 단가 · 세금 · 운임 · 오더 할인 · 쿠폰 제외 · null 은 price_missing) demand_amount · sold_amount · lost_amount(lost_amount_by) · in_progress_amount · open_backorder_amount · flagged_amount · currency · currency_n · amount_sums · 뺀다 = 무상 줄 · pos·counter · 콤보 구성품 · 되돌려진 장부 행 · 되돌린 오더 · 필터 15(+ currency) · invoker · stable · 임시 표 없음';

-- ═══ ② so_backorder_overview — 판정 485 ① ② ③ (수요 숫자는 so_backorder_demand 의 rows 에서) ═══
--   ① 비중(지금): stock_sku_active = 활성 재고 제품(product.is_active ∧ parent_product_id null — bo-1a 의 「재고 제품」 단위 · 세트는 부모로 접힌다 · 콤보는 제 제품) · stock_sku_open_backorder = 거른 덩어리 가운데 열린 백오더가 있는 재고 제품 수 · stock_sku_backordered_in_period = 거른 덩어리의 재고 제품 수
--   ② 잃은 세일 규모: ordered_amount(분모) = warehouse 채널 · 확정된 오더(confirmed_at 있음 · 되돌린 오더 제외) · 확정일(토론토) 이 기간 안 · 수요 줄(무상 · 콤보 구성품 제외) qty_ordered × unit_price · 기간 = order_from/to 가 있으면 그것 · 없으면 ended_from/to · 둘 다 없으면 전부 · customer_id · location_id · currency 거르기도 따른다
--      분자 = 기간 열쇠를 뺀 so_backorder_demand 호출(v_d2 · 기간이 없으면 ③ 과 같은 호출)의 줄에서 잃은 몫마다 제 날짜로(판정 486 v3 · 위) · backordered · demand(덩어리) = 첫 백오더 예약 allocated_at 이 기간 안 · share · ③ 은 준 거르기 그대로
--      backordered_qty/amount(판정 487) = 분자 덩어리의 줄마다 「첫 백오더 예약 수량」(allocated_at 최소 · 콤보 줄은 구성품 예약 ÷ combo_qty 의 최소) × 단가 · 다시 주문 오더의 줄(활성 superseded taken_by_so_id · merged_into_id 와 split 자손)과 백오더가 있던 줄의 split 자손 줄은 0 · lost_amount · lost_amount_by · pct_of_ordered · basis 표지(판정 486)
--   ③ SKU 순위(재고 제품 하나 = 한 행): customers_waiting(열린 덩어리의 손님 수) · customers_in_period(거른 덩어리의 손님 수) · repeat_asks(그 제품 줄을 이어받은 새 오더 수 = 활성 superseded 장부의 distinct taken_by_so_id · 「백오더가 열린 동안 다시 주문」의 실물 기록) · repeat_customers(이어받기가 한 번이라도 있는 손님 수) ·
--      days_waiting_max/avg(열린 덩어리 · ims_today − 첫 주문일) · demand_then · sold · lost · lost_amount · open_backorder · open_backorder_amount · price_missing · last_receipt_on(원장 po_in · 다른 창고발 transfer_in — so_backorder_list 의 arrived 규칙 · location_id 를 주면 그 창고만) · no_receipt_since_first_ask(첫 주문일 뒤 그런 입고 0)
--   정렬 sort = lost_amount(기본) | lost | demand_then | open_backorder | customers_waiting | repeat_asks | days_waiting_max · 내림 · limit/offset 은 ③ 행에 · 수요 읽기는 limit 1000(덩어리 1000 넘으면 truncated true)
create function public.so_backorder_overview(p_filters jsonb default '{}'::jsonb) returns jsonb
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
      select max(g.occurred_on) as last_receipt_on
      from public.inv_ledger g
      where g.sku = p.sku and g.qty_delta > 0 and (v_wh is null or g.warehouse = v_wh)
        and (g.event_type = 'po_in'
             or (g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT'
                 and exists (select 1 from public.inv_ledger o
                             where o.doc_number = g.doc_number and o.sku = g.sku and o.event_type = 'transfer_out'
                               and o.warehouse <> 'IN_TRANSIT' and o.warehouse <> g.warehouse)))
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
comment on function public.so_backorder_overview(jsonb) is
  '⭐ Backorders 탭 머리 + SKU 순위(bo-1c · 판정 485 ① 비중 ② 잃은 세일 규모 ③ 반복해서 못 대는 SKU) — 수요 숫자는 so_backorder_demand(limit 1000)에서(셈은 하나가 정본) · share{stock_sku_active · stock_sku_open_backorder · stock_sku_backordered_in_period · pct_open · pct_in_period} · lost_sales{period · basis(판정 486: 기간 안에 잃은 것(몫마다 제 날짜 — 장부 ended_at · removed_at · so.closed_at) ÷ 기간 안 확정된 주문 금액) · lost_by · lost_price_missing · ordered_qty/amount(warehouse 확정 오더 · 확정일 토론토 · 되돌린 오더 제외 · 무상 · 구성품 제외) · backordered_qty/amount(판정 487: 덩어리마다 한 번 · 줄의 첫 백오더 예약 · 다시 주문 오더와 split 자손은 0) · demand · lost · lost_amount_by · pct_of_ordered · clusters_in_period} · rows[](재고 제품 하나 = 한 행: customers_waiting · customers_in_period · repeat_asks(활성 superseded 장부의 distinct taken_by_so_id) · repeat_customers · days_waiting_max/avg · demand_then · sold · lost · lost_amount · open_backorder(_amount) · last_receipt_on(원장 po_in · 다른 창고발 transfer_in · location_id 면 그 창고) · no_receipt_since_first_ask · rank) · 필터 = so_backorder_demand 의 15 + sort · invoker · stable';
revoke all on function public.so_backorder_overview(jsonb) from public, anon;
grant execute on function public.so_backorder_overview(jsonb) to authenticated;

-- ═══ ③ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text;
begin
  select prosrc into v_src from pg_proc where oid = 'public.so_backorder_demand(jsonb)'::regprocedure;
  if v_src !~ '''demand_amount'', x\.demand_amount' or v_src !~ '''currency''' or v_src !~ 'amount_sums' or v_src !~ '''transferred'', x\.transferred' then v_bad := v_bad || ' demand-body'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_backorder_demand', 'so_backorder_overview')) <> 2 then v_bad := v_bad || ' functions'; end if;
  if has_function_privilege('anon', 'public.so_backorder_overview(jsonb)', 'execute') or has_function_privilege('anon', 'public.so_backorder_demand(jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.so_backorder_overview(jsonb)', 'execute') or not has_function_privilege('authenticated', 'public.so_backorder_demand(jsonb)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if (select prosecdef or provolatile <> 's' from pg_proc where oid = 'public.so_backorder_overview(jsonb)'::regprocedure)
     or (select prosecdef or provolatile <> 's' from pg_proc where oid = 'public.so_backorder_demand(jsonb)'::regprocedure) then v_bad := v_bad || ' invoker/stable'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM485', message = format('STOP - bo-1c did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
