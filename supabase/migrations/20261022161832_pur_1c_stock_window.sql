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

-- ═══ pur-1c — 발주앱 재고 읽기 창구 pur_stock() (2026-10-22 · 판정 604 · 608 · 615 · pur-1 뒤) ═══
--   발주앱(purchasing.html)은 시작할 때 stk_availability 를 500 행씩 16 쪽 불러 창고별로 접는다 — 실측 17 s(쪽마다 전체를 다시 센다 · count(*) over () · limit 은 맨 끝) · 8 쪽 동시면 statement timeout.
--   pur_stock() = 같은 집합을 한 번에: 재고 키(낱개 · 콤보 아님) × 활성 창고 · 다섯 수(on_hand · sales_allocated · transfer_reserved · on_order · in_transit)를 stk_availability 와 같은 출처에서 ·
--   가용 식은 inv_available_base 한 곳(창고마다 한 번 · 전부) · on_order · in_transit 은 stk_availability 의 onord · intr 블록을 그대로 옮겼다(⚠️ 한쪽을 고치면 다른 쪽도 — 공통 함수로 빼는 일은 stk_availability 재발행이라 다음 차수) ·
--   행 집합 = stk_availability(include_zero false) 와 같다(다섯 수의 창고 합이 모두 0 인 줄만 뺀다 · 판정 266) · 접기 = 화면 규칙 그대로(창고 이름에 edmonton → edm · 그 밖 → tor) · alloc = sales_allocated + transfer_reserved.
--   문 = purchasing 보기(pur_staff(false) · pur-1 과 같은 꼴) · definer · stable · authenticated 만(service_role 은 부르는 곳이 없어 주지 않는다 · 판정 615 규칙 「EF · GAS 가 REST 로 칠 때만」) · 표 · 뷰 · 시퀀스는 만들지 않는다.
create function public.pur_stock() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_whs uuid[];  v_rows jsonb;  v_n int;  v_wh jsonb;
begin
  perform public.pur_staff(false);
  select coalesce(array_agg(w.id order by w.name), '{}'::uuid[]) into v_whs from public.ref_warehouse w where w.is_active;
  if cardinality(v_whs) = 0 then raise exception 'No active warehouse — nothing was read'; end if;
  with whs as (
    select w.id, w.name, case when lower(w.name) like '%edmonton%' then 'edm' else 'tor' end as key from public.ref_warehouse w where w.id = any(v_whs)
  ),
  av as (                                                                                  -- 장부 · 판매 예약 · 트랜스퍼 예약 — 식 한 곳(inv_available_base) · 창고마다 한 번 · 전부
    select x.id as wh, b.stock_pid, b.qty_ea, b.sales_alloc_ea, b.transfer_alloc_ea from whs x cross join lateral public.inv_available_base(x.id, null) b
  ),
  onord as (                                                                               -- = stk_availability onord(판정 260): 확정 발주 줄 − 확정 입고 줄 · 줄마다 0 아래는 0 · 발주의 배송 창고
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
  intr as (                                                                                -- = stk_availability intr: 출발했고 아직 도착 창고에 다 들어오지 않은 트랜스퍼 줄 · 도착 창고
    select t.to_warehouse_id as wh, coalesce(pr.parent_product_id, pr.id) as stock_pid,
           sum(greatest(coalesce(l.qty_sent, 0) - coalesce(l.qty_received, 0) - coalesce(l.qty_lost, 0) - coalesce(l.qty_returned, 0), 0) * l.pack_factor) as ea
    from public.inv_transfer t
    join public.inv_transfer_line l on l.transfer_id = t.id
    join public.product pr on pr.id = l.product_id
    where t.status in ('in_transit', 'receiving') and t.to_warehouse_id = any(v_whs)
    group by 1, 2
  ),
  pw as (                                                                                  -- 재고 키(낱개 · 콤보 아님 · 판정 261) × 창고 — 창고별 다섯 수
    select p.id as pid, p.sku, x.key,
           coalesce(av.qty_ea, 0) as on_hand, coalesce(av.sales_alloc_ea, 0) as sales_allocated, coalesce(av.transfer_alloc_ea, 0) as transfer_reserved,
           coalesce(onord.ea, 0) as on_order, coalesce(intr.ea, 0) as in_transit
    from public.product p
    cross join whs x
    left join av    on av.wh = x.id    and av.stock_pid = p.id
    left join onord on onord.wh = x.id and onord.stock_pid = p.id
    left join intr  on intr.wh = x.id  and intr.stock_pid = p.id
    where p.parent_product_id is null
      and not exists (select 1 from public.product_bom bm where bm.parent_product_id = p.id and bm.is_active)
  ),
  br as (                                                                                  -- 브랜치로 접기(화면 규칙) — 같은 열쇠의 창고가 둘이면 합
    select pw.pid, pw.sku, pw.key, sum(pw.on_hand) as qoh, sum(pw.sales_allocated + pw.transfer_reserved) as alloc, sum(pw.on_order) as oo, sum(pw.in_transit) as it,
           sum(pw.on_hand - pw.sales_allocated - pw.transfer_reserved) as avail
    from pw group by 1, 2, 3
  ),
  fin as (                                                                                 -- 키마다 한 줄(tor · edm 을 조건 집계로 — 상관 서브쿼리는 7,992 × 36k 훑기라 45 s 였다) · 판정 266: 다섯 수의 창고 합이 모두 0 인 줄만 뺀다(available 은 안 본다)
    select br.pid, br.sku,
           coalesce(sum(br.qoh)   filter (where br.key = 'tor'), 0) as tq, coalesce(sum(br.alloc) filter (where br.key = 'tor'), 0) as ta, coalesce(sum(br.oo) filter (where br.key = 'tor'), 0) as to_, coalesce(sum(br.it) filter (where br.key = 'tor'), 0) as ti, coalesce(sum(br.avail) filter (where br.key = 'tor'), 0) as tv,
           coalesce(sum(br.qoh)   filter (where br.key = 'edm'), 0) as eq, coalesce(sum(br.alloc) filter (where br.key = 'edm'), 0) as ea, coalesce(sum(br.oo) filter (where br.key = 'edm'), 0) as eo, coalesce(sum(br.it) filter (where br.key = 'edm'), 0) as ei, coalesce(sum(br.avail) filter (where br.key = 'edm'), 0) as ev
    from br group by 1, 2
    having sum(br.qoh) <> 0 or sum(br.alloc) <> 0 or sum(br.oo) <> 0 or sum(br.it) <> 0
  )
  select coalesce(jsonb_agg(jsonb_build_object('sku', f.sku, 'product_id', f.pid,
           'tor', jsonb_build_object('qoh', f.tq, 'alloc', f.ta, 'oo', f.to_, 'it', f.ti, 'avail', f.tv),
           'edm', jsonb_build_object('qoh', f.eq, 'alloc', f.ea, 'oo', f.eo, 'it', f.ei, 'avail', f.ev)) order by f.sku, f.pid), '[]'::jsonb), count(*)
    into v_rows, v_n from fin f;
  select jsonb_agg(jsonb_build_object('warehouse_id', w.id, 'warehouse', w.name, 'key', case when lower(w.name) like '%edmonton%' then 'edm' else 'tor' end) order by w.name) into v_wh from public.ref_warehouse w where w.id = any(v_whs);
  return jsonb_build_object('row_count', v_n, 'warehouses', v_wh, 'rows', v_rows);
end $$;
revoke all on function public.pur_stock() from public, anon, service_role;                      -- 함수 기본 권한(f)이 anon · authenticated · service_role 에 X 를 준다 — 셋 다 거두고 authenticated 만 다시 준다
grant execute on function public.pur_stock() to authenticated;
comment on function public.pur_stock() is 'pur-1c 판정 604 · 608 — 발주앱 재고 한 번에: 재고 키마다 tor · edm 의 qoh · alloc(판매 + 트랜스퍼 예약) · oo · it · avail · 행 집합 · 수는 stk_availability(include_zero false)를 화면 규칙으로 접은 것과 같다 · 문 = purchasing 보기';

-- ═══ 착지 — 함수 하나 · definer · stable · ACL(authenticated 만) · stk_availability · inv_available_base 무변(md5) · 새 표 · 뷰 · 시퀀스 0 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_stock') <> 1 then v_bad := v_bad || ' pur_stock_count'; end if;
  if not (select p.prosecdef and p.provolatile = 's' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_stock') then v_bad := v_bad || ' not_definer_stable'; end if;
  if not has_function_privilege('authenticated', 'public.pur_stock()', 'execute') or has_function_privilege('anon', 'public.pur_stock()', 'execute') or has_function_privilege('service_role', 'public.pur_stock()', 'execute') then v_bad := v_bad || ' acl'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'stk_availability') <> '97a3160d2f7a1aaadecbbc9924c65b86' then v_bad := v_bad || ' stk_availability_changed'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_available_base') <> 'fd141ec16a8b98aad23eb1b17dadc0ab' then v_bad := v_bad || ' inv_available_base_changed'; end if;
  if (select p.proacl::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_stock') ~ 'anon=' then v_bad := v_bad || ' anon_in_acl'; end if;
  if v_bad <> '' then raise exception 'pur-1c landing check failed:%', v_bad; end if;
end $$;
