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
-- 20261007163823_bo_pre_1_preorder_list.sql — bo-pre-1 (2026-10-07 · 회사 PC)
--   판정 351(Caleb · 안 A) 「Pre order도 back order화면에 보이게 … 백오더처럼 입고 확인이 되면 좋겠어」 — 프리오더 줄을 Backorders 목록에 섞는다 · 줄마다 kind(backorder | preorder) · 거르기 kind · 머리 셈 open_backorder · open_preorder · arrived · available · owed · days_waiting 은 백오더와 같은 식(기준 시각 = 그 프리오더 예약이 생긴 때)
--   판정 9 지킴: 프리오더 = 「확정됐지만 재고가 없어 못 나가는 오더」 — 이어받기 · 만료 대상 아님 → 프리오더 행의 notified_at 은 null · 끝난 목록은 백오더만(프리오더는 기록 표 so_backorder_close 를 쓰지 않는다 · so_backorder_proceed 도 프리오더 줄에 장부를 안 적는다) · so_backorder_sweep · so_backorder_supersede · so_backorder_proceed 무접촉
--   재발행: so_backorder_list = 20261006000805:622~792 바이트 복사(DB md5 ceda1928 · 검증 G0 대조) + 더한 줄 · 바꾼 줄(이유는 줄 끝 -- bo-pre-1) · 백오더 행의 값은 하나도 안 바뀐다(검증 B1 ~ B5 가 옛 함수와 정규형 대조)
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 supabase/tests/bo-pre-1-verify.sql · 부르는 화면 so-backorders.html 하나(새 열쇠는 더한 것뿐 — 옛 열쇠 그대로)

-- ═══ 1) so_backorder_list 재발행 ═══
create or replace function public.so_backorder_list(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['customer_id','supplier_id','brand_id','sku','product_id','location_id','state','end_kind','order_from','order_to','ended_from','ended_to','arrived','notified','owed','limit','offset','kind'];   -- bo-pre-1 판정 351: 거르기 kind
  v_bad    text;
  v_state  text := coalesce(nullif(f->>'state', ''), 'all');
  v_kind   text := nullif(f->>'kind', '');                                                                           -- bo-pre-1 판정 351: backorder | preorder · 없으면 둘 다
  v_limit  int  := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int  := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_rows   jsonb;
  v_total  int;
  v_open   int;
  v_ended  int;
  v_open_owed int;                                 -- 열린 무상 백오더(우리가 줄 것) 수
  v_open_bo int;  v_open_pre int;                  -- bo-pre-1 판정 351: 열린 것 가운데 백오더 · 프리오더 수(화면이 거르기 옆에 보인다)
  v_avail  jsonb := '{}'::jsonb;                   -- "warehouse_id:stock_pid" → available_ea (창고마다 so_available_many 한 번)
  v_pids   uuid[];
  w        record;
begin
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;
  if v_state not in ('open', 'ended', 'all') then raise exception 'state must be open, ended or all'; end if;
  if v_kind is not null and v_kind not in ('backorder', 'preorder') then raise exception 'kind must be backorder or preorder'; end if;   -- bo-pre-1 판정 351

  -- 낱개 제품 묶음(가용 계산용) — stable 함수라 임시 표를 쓰지 않는다(INSERT 금지) · 같은 합집합을 아래 bo 가 다시 읽는다
  select array_agg(distinct x.stock_pid) into v_pids
  from (
    select coalesce(p.parent_product_id, p.id) as stock_pid
    from public.so_reserve r join public.so_line l on l.id = r.so_line_id join public.product p on p.id = l.product_id
    where r.kind in ('backorder', 'preorder') and r.released_at is null                                                 -- bo-pre-1 판정 351: 프리오더 줄도 같은 목록
    union
    select coalesce(p.parent_product_id, p.id)
    from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id join public.product p on p.id = l.product_id
    where c.reopened_at is null
    union                                                                                                       -- asm-2b2: 장부가 콤보 줄에 설 때 그 구성품의 재고 키(열린 콤보 백오더의 예약은 구성품 줄에 있어 첫 갈래가 이미 담는다)
    select coalesce(p.parent_product_id, p.id)
    from public.so_backorder_close c join public.so_line cp on cp.combo_line_id = c.so_line_id join public.product p on p.id = cp.product_id
    where c.reopened_at is null
  ) x;

  -- 가용 — 활성 창고마다 so_available_many 한 번(줄마다 부르지 않는다) · 이 목록의 낱개 제품 전부
  for w in select wh.id, wh.name from public.ref_warehouse wh where wh.is_active order by wh.name loop
    select coalesce(v_avail || jsonb_object_agg(w.id::text || ':' || m.stock_pid::text, m.available_ea), v_avail) into v_avail
    from public.so_available_many(v_pids, w.id) m;
  end loop;

  with bo as (
    select l.id as line_id, s.id as so_id, s.so_number, s.order_date, s.location_id, s.location_name, s.customer_id,
           l.product_id, coalesce(p.parent_product_id, p.id) as stock_pid, coalesce(pp.sku, p.sku) as base_sku, l.sku, l.product_name, l.pack_factor, l.qty_ordered,
           'open'::text as state, q.qty_open, q.since as backorder_since,
           null::text as end_kind, null::numeric as qty_taken, null::numeric as qty_unwanted, null::uuid as taken_by_so_id, null::timestamptz as ended_at,
           case when q.kind = 'preorder' then null else l.backorder_notified_at end as notified_at,                                   -- bo-pre-1 판정 9 · 351: 프리오더는 알림 추적 대상이 아니다
           q.kind,                                                                                                                  -- bo-pre-1 판정 351: 행마다 kind(backorder | preorder)
           l.free_reason                                                                                          -- 판정 15·16: 무상 줄 = owed(우리가 줄 것)
    from (select distinct coalesce(cp.combo_line_id, cp.id) as line_id                                           -- asm-2b2(묶음 4): 수요 줄 — 예약은 구성품 줄에 있지만 목록은 콤보 줄 하나로(수량 = 콤보 수 · 구성품은 아래 components)
            from public.so_reserve r join public.so_line cp on cp.id = r.so_line_id where r.kind in ('backorder', 'preorder') and r.released_at is null) d   -- bo-pre-1 판정 351
    join public.so_line l on l.id = d.line_id
    cross join lateral (select min(floor(r.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, min(r.allocated_at) as since, min(r.kind) as kind   -- bo-pre-1: 기준 시각 = 그 예약이 생긴 때(같은 식) · 한 수요 줄의 예약은 한 kind
                        from public.so_reserve r join public.so_line cp on cp.id = r.so_line_id
                        where (cp.id = l.id or cp.combo_line_id = l.id) and r.kind in ('backorder', 'preorder') and r.released_at is null) q   -- bo-pre-1 판정 351
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    left join public.product pp on pp.id = p.parent_product_id
    union all
    select l.id, s.id, s.so_number, s.order_date, s.location_id, s.location_name, s.customer_id,
           l.product_id, coalesce(p.parent_product_id, p.id), coalesce(pp.sku, p.sku), l.sku, l.product_name, l.pack_factor, l.qty_ordered,
           'ended', c.qty_open,
           (select max(r2.allocated_at) from public.so_reserve r2 join public.so_line cp on cp.id = r2.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and r2.kind = 'backorder'),   -- asm-2b2: 콤보 줄의 예약은 구성품에
           c.end_kind, c.qty_taken, c.qty_unwanted, c.taken_by_so_id, c.ended_at, l.backorder_notified_at,
           'backorder'::text,                                                                                                       -- bo-pre-1: 끝난 목록은 백오더만(프리오더는 기록 표가 없다 · 판정 9)
           l.free_reason
    from public.so_backorder_close c
    join public.so_line l on l.id = c.so_line_id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    left join public.product pp on pp.id = p.parent_product_id
    where c.reopened_at is null
  ),
  base as (
    select t.*,
           cu.name as customer_name,
           p.brand_id, p.brand_name,
           ps.supplier_id, su.name as supplier_name,
           ts.so_number as taken_by_so_number,
           (t.free_reason is not null) as owed,                                                                  -- 무상 줄 백오더 = 우리가 줄 것(판정 16 · 이어받기·만료 대상 아님)
           (public.ims_today() - t.order_date) as days_waiting,                                                  -- 기다린 날수(원래 주문일 기준 · 오래된 것을 매니저가 정리)
           cb.is_combo, cb.components,                                                                              -- asm-2b2: 콤보 줄 표시 · 구성품(sku · 이름 · combo_qty · base_sku)
           -- 입고됨(판정 6·7): 백오더가 생긴 뒤 그 창고에 po_in 또는 다른 창고에서 온 transfer_in(출발 줄이 있고 출발 창고 ≠ 도착 창고 · IN_TRANSIT 제외) · 조정·반품·조립 제외
           -- asm-2b2(⬜ 알림): 콤보는 「어느 구성품이든 자격 있는 입고가 있었다 ∧ 지금 통째 콤보가 1 개 이상 가용」 — 입고 사건이 있어야 하고(판정 6 · 반품 · 조정으로 생긴 가용은 세지 않는다) 반쪽 콤보로는 알리지 않는다(묶음 4)
           case when cb.is_combo then cb.arrived_any and coalesce(cb.avail_here, 0) >= 1 else exists (
             select 1 from public.inv_ledger g
             where g.sku = t.base_sku and g.warehouse = t.location_name and g.qty_delta > 0
               and g.occurred_on >= (t.backorder_since at time zone 'America/Toronto')::date
               and (g.event_type = 'po_in'
                    or (g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT'
                        and exists (select 1 from public.inv_ledger o
                                    where o.doc_number = g.doc_number and o.sku = g.sku and o.event_type = 'transfer_out'
                                      and o.warehouse <> 'IN_TRANSIT' and o.warehouse <> g.warehouse)))
           ) end as arrived,
           case when cb.is_combo then cb.avail_here else (v_avail->>(t.location_id::text || ':' || t.stock_pid::text))::numeric end as available_here,   -- asm-2b2: 콤보 가용 = min(구성품 가용 ÷ (combo_qty × pack_factor))
           case when cb.is_combo then cb.avail_other else (select jsonb_object_agg(wh.name, (v_avail->>(wh.id::text || ':' || t.stock_pid::text))::numeric)
              from public.ref_warehouse wh where wh.is_active and wh.id is distinct from t.location_id) end as available_other
    from bo t
    cross join lateral (                                                                                            -- asm-2b2: 콤보 줄의 구성품 · 콤보 단위 가용(이 창고 · 다른 창고) · 구성품 입고 사건
      select exists (select 1 from public.so_line cp where cp.combo_line_id = t.line_id) as is_combo,
             (select jsonb_agg(jsonb_build_object('sku', cp.sku, 'product_name', cp.product_name, 'combo_qty', cp.combo_qty, 'base_sku', coalesce(cpp.sku, cp2.sku)) order by cp.line_no)
                from public.so_line cp join public.product cp2 on cp2.id = cp.product_id left join public.product cpp on cpp.id = cp2.parent_product_id where cp.combo_line_id = t.line_id) as components,
             (select min(floor(coalesce((v_avail->>(t.location_id::text || ':' || coalesce(cp2.parent_product_id, cp2.id)::text))::numeric, 0) / (cp.combo_qty * cp.pack_factor)))
                from public.so_line cp join public.product cp2 on cp2.id = cp.product_id where cp.combo_line_id = t.line_id) as avail_here,
             (select jsonb_object_agg(wh.name, (select min(floor(coalesce((v_avail->>(wh.id::text || ':' || coalesce(cp2.parent_product_id, cp2.id)::text))::numeric, 0) / (cp.combo_qty * cp.pack_factor)))
                                                  from public.so_line cp join public.product cp2 on cp2.id = cp.product_id where cp.combo_line_id = t.line_id))
                from public.ref_warehouse wh where wh.is_active and wh.id is distinct from t.location_id) as avail_other,
             exists (select 1 from public.so_line cp join public.product cp2 on cp2.id = cp.product_id left join public.product cpp on cpp.id = cp2.parent_product_id
                       join public.inv_ledger g on g.sku = coalesce(cpp.sku, cp2.sku) and g.warehouse = t.location_name and g.qty_delta > 0
                                                 and g.occurred_on >= (t.backorder_since at time zone 'America/Toronto')::date
                                                 and (g.event_type = 'po_in'
                                                      or (g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT'
                                                          and exists (select 1 from public.inv_ledger o where o.doc_number = g.doc_number and o.sku = g.sku and o.event_type = 'transfer_out'
                                                                        and o.warehouse <> 'IN_TRANSIT' and o.warehouse <> g.warehouse)))
                      where cp.combo_line_id = t.line_id) as arrived_any
    ) cb
    join public.customer cu on cu.id = t.customer_id
    join public.product p on p.id = t.product_id
    left join public.product_supplier ps on ps.product_id = t.product_id and ps.is_default and ps.is_active
    left join public.supplier su on su.id = ps.supplier_id
    left join public.so ts on ts.id = t.taken_by_so_id
  ),
  filtered as (
    select * from base b
    where (f->>'customer_id' is null or b.customer_id = (f->>'customer_id')::uuid)
      and (f->>'supplier_id' is null or (f->>'supplier_id' = 'none' and b.supplier_id is null) or (f->>'supplier_id' <> 'none' and b.supplier_id = (f->>'supplier_id')::uuid))
      and (f->>'brand_id'    is null or b.brand_id = (f->>'brand_id')::uuid)
      and (f->>'sku'         is null or b.sku ilike (f->>'sku') || '%' or b.base_sku ilike (f->>'sku') || '%'
           or exists (select 1 from jsonb_array_elements(coalesce(b.components, '[]'::jsonb)) cj where cj->>'sku' ilike (f->>'sku') || '%' or cj->>'base_sku' ilike (f->>'sku') || '%'))   -- asm-2b2: 구성품 SKU 로도 콤보 백오더를 찾는다
      and (f->>'product_id'  is null or b.product_id = (f->>'product_id')::uuid)
      and (f->>'location_id' is null or b.location_id = (f->>'location_id')::uuid)
      and (v_state = 'all' or b.state = v_state)
      and (f->>'end_kind'    is null or b.end_kind = f->>'end_kind')
      and (f->>'order_from'  is null or b.order_date >= (f->>'order_from')::date)
      and (f->>'order_to'    is null or b.order_date <= (f->>'order_to')::date)
      and (f->>'ended_from'  is null or (b.ended_at at time zone 'America/Toronto')::date >= (f->>'ended_from')::date)
      and (f->>'ended_to'    is null or (b.ended_at at time zone 'America/Toronto')::date <= (f->>'ended_to')::date)
      and (f->>'arrived'     is null or b.arrived = (f->>'arrived')::boolean)
      and (f->>'notified'    is null or (b.notified_at is not null) = (f->>'notified')::boolean)
      and (f->>'owed'        is null or b.owed = (f->>'owed')::boolean)
      and (v_kind is null or b.kind = v_kind)                                                                                 -- bo-pre-1 판정 351
  )
  select count(*), count(*) filter (where state = 'open'), count(*) filter (where state = 'ended'),
         count(*) filter (where state = 'open' and owed) as open_owed_n,
         count(*) filter (where state = 'open' and kind = 'backorder'), count(*) filter (where state = 'open' and kind = 'preorder'),   -- bo-pre-1 판정 351
         coalesce((select jsonb_agg(jsonb_build_object(
             'so_id', x.so_id, 'so_number', x.so_number, 'order_date', x.order_date, 'line_id', x.line_id,
             'customer_id', x.customer_id, 'customer_name', x.customer_name,
             'product_id', x.product_id, 'sku', x.sku, 'base_sku', x.base_sku, 'product_name', x.product_name, 'pack_factor', x.pack_factor,
             'brand_id', x.brand_id, 'brand_name', x.brand_name, 'supplier_id', x.supplier_id, 'supplier_name', x.supplier_name,
             'location_id', x.location_id, 'location_name', x.location_name,
             'qty_ordered', x.qty_ordered, 'qty_open', x.qty_open, 'backorder_since', x.backorder_since,
             'state', x.state, 'kind', x.kind, 'end_kind', x.end_kind, 'qty_taken', x.qty_taken, 'qty_unwanted', x.qty_unwanted,                   -- bo-pre-1 판정 351: kind
             'taken_by_so_id', x.taken_by_so_id, 'taken_by_so_number', x.taken_by_so_number, 'ended_at', x.ended_at,
             'notified_at', x.notified_at, 'notified_state', case when x.notified_at is not null then 'sent' else 'unknown_pre_ims' end,
             'free_reason', x.free_reason, 'owed', x.owed, 'days_waiting', x.days_waiting,
             'arrived', x.arrived, 'available_here', x.available_here, 'available_other', x.available_other,
             'is_combo', x.is_combo, 'components', x.components)                                                   -- asm-2b2: 콤보 줄 하나로 선다(qty = 콤보 수) · 구성품은 여기에
           order by x.customer_name, x.customer_id, x.base_sku, x.order_date, x.so_number, x.line_id)
           from (select * from filtered order by customer_name, customer_id, base_sku, order_date, so_number, line_id limit v_limit offset v_offset) x), '[]'::jsonb)
    into v_total, v_open, v_ended, v_open_owed, v_open_bo, v_open_pre, v_rows
  from filtered;

  return jsonb_build_object(
    'total', v_total, 'open', v_open, 'ended', v_ended, 'open_owed', v_open_owed, 'open_backorder', v_open_bo, 'open_preorder', v_open_pre, 'limit', v_limit, 'offset', v_offset, 'filters', f,   -- bo-pre-1 판정 351
    'notify_tracking', 'pre_ims — backorder_notified_at is not written yet (GAS sends arrival mail from Cin7); notified_state unknown_pre_ims is not "not sent"; pre-order rows (kind preorder) are not notification-tracked: notified_at is always null (ruling 9)',
    'arrived_rule', 'po_in or transfer_in from another warehouse (same doc transfer_out at a different, non-IN_TRANSIT warehouse) at the order warehouse since the backorder was made; adjustments, credits, assemblies and arrivals without a departure leg do not count; a combo row is arrived when any component had such an arrival and at least one whole combo is available at the order warehouse; pre-order rows (kind preorder, ruling 351) use the same rule counted from the pre-order reservation, are never expired or taken over (ruling 9), and only open pre-orders are listed (no ended record)',
    'rows', v_rows);
end;
$$;

-- ═══ 2) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text;
begin
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_backorder_list';
  if v_src is null then v_bad := v_bad || ' missing'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_backorder_list') <> 1 then v_bad := v_bad || ' count'; end if;
  if v_src not like '%''open_preorder''%' or v_src not like '%kind must be backorder or preorder%' or v_src like '%r.kind = ''backorder'' and r.released_at is null%' then v_bad := v_bad || ' body'; end if;
  if (select p.prosecdef or p.provolatile <> 's' from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_backorder_list') then v_bad := v_bad || ' invoker/stable'; end if;
  if not has_function_privilege('authenticated', 'public.so_backorder_list(jsonb)', 'execute') or has_function_privilege('anon', 'public.so_backorder_list(jsonb)', 'execute') then v_bad := v_bad || ' acl'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_backorder_sweep', 'so_backorder_supersede', 'so_backorder_proceed') and p.prosrc like '%bo-pre-1%') <> 0 then v_bad := v_bad || ' untouched(touched)'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM351', message = format('STOP - bo-pre-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
