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

-- ═══ stk-av-1 — Stock Availability 넓히기 DB: 예약 목록 · 공급처 · 두 브랜치 · 재고 금액 · 원가 열쇠 (2026-10-20 · 판정 566 · 567 · 570 · 571 · 575 · 576 · 578 · stk-av-1 이견 1 ~ 12 · 정본 so-module §46 뒤) ═══
--   ① 원가 열쇠 cost — ims_perm_catalog screens.cost(ims 방 · admin · supervisor 는 역할로 · 나머지는 Staff 에서 켠다 · cost 와 cost:read 둘 다 「보임」) · 확인 함수 ims_can_view_cost() = ims_can_view('cost')(판정 578 「A」)
--   ② stk_reserved(p_product_id, p_warehouse_id) — 판매 예약(SO) · 트랜스퍼 예약(TRF) 목록 · definer · 문 = 로그인 + 활성 직원(stk_* 와 같은 문) · ⭐ inv_available_base 의 alloc · talloc 과 서로 같은 조건(판정 566 「B」 · inv_available_base 는 무접촉) · 손님 이름은 ims_can_view('sales') 없으면 null · TRF 번호 · 상태 · 수량은 열쇠 없이(짐작 확인 11)
--   ③ stk_availability 재발행(옛 서명 drop · 이견 6) — p_supplier_id(판정 570 「A」 · 활성 공급처 줄이 있는 제품 전부 · 기본 아니어도 · 세트 줄은 낱개로) · p_warehouse_id null = Both(판정 571 「B」 · 활성 창고 전부 · 평평한 열은 합 · by_warehouse jsonb 에 창고별) · 바코드 정확 일치(⑥ · 세트 바코드 → 낱개 줄 + 세트 표시 · 여러 제품이면 전부) · 옛 인자 · 옛 열 그대로 · ⭐ 원가 열 없음(판정 262 그대로 · 575 「A」)
--   ④ stk_value_many(p_product_ids[], p_warehouse_id) · stk_value_total(p_warehouse_id, …같은 거르기) — 레이어 남은 금액(inv_layer_value 와 서로 같은 식 · 집합형 · 이견 9) · ⭐ 원가 열쇠 필수(판정 567 · 575 · 둘만 원가를 낸다) · layer_qty_ea 함께(레이어 수량 ≠ 장부 수량 · Toronto +228 · IN_TRANSIT +2,559)
--   이 차수 밖(판정 576 「A」): 레이어 표 읽기 가리기 ⑤ 는 rls-3 — invoker 읽기 함수 6(po_charge_confirm · so_stock_short_list · so_credit_detail · inv_adjust_eval · inv_transfer_detail · po_fx_cost_lines) · inv_layer_open · inv_layer_value · 원가 울타리(577) · inv_cost · inv_doc_cost · inv_snapshot 의 auth_all

-- ═══ ① 원가 열쇠 — ims_perm_catalog 에 screens.cost · ims_can_view_cost() ═══
create or replace function public.ims_perm_catalog() returns jsonb
  language sql immutable
  set search_path = public, pg_temp
as $$
  select '{
    "modes": ["wms", "ims"],
    "screens": {
      "shopify":    {"room": "ims", "min_role": "manager", "label": "Shopify stores, product push, stock sync (manager and above · shop-1a)"},
      "purchasing": {"room": "ims", "label": "Purchase orders, invoices, charges, payments"},
      "master":     {"room": "ims", "label": "Settings, suppliers, products, families, supplier products, prices, product tags, deals"},
      "receiving":  {"room": "ims", "label": "Receiving and putaway"},
      "staff":      {"room": "ims", "label": "Adding and editing people (below your own rank)"},
      "sales":      {"room": "ims", "label": "Sales orders, customer addresses and contacts"},
      "picking":     {"room": "wms", "label": "Picking — pick tasks, waves, holds"},
      "packing":     {"room": "wms", "label": "Packing — pack tasks, pallets, boxes"},
      "fulfillment": {"room": "wms", "label": "Fulfillment — finalize, shipping, manager review"},
      "wms_manage":  {"room": "wms", "min_role": "manager", "label": "Warehouse management — batches, waves, rollbacks (manager and above)"},
      "wms_receiving":         {"room": "wms", "label": "Warehouse receiving — count, put away, hold, off-PO"},
      "wms_receiving_confirm": {"room": "wms", "min_role": "manager", "label": "Warehouse receiving — confirm a receipt (manager and above · off until switched on)"},
      "stock_adjust":          {"room": "ims", "min_role": "manager", "label": "Stock adjustments — draft and confirm (manager and above · off until switched on)"},
      "stock_move":            {"room": "wms", "label": "Bin moves — move stock between bins in one warehouse (person by person · off until switched on)"},
      "transfer":              {"room": "ims", "label": "Transfers — warehouse to warehouse (person by person · off until switched on)"},
      "doc_template":          {"room": "ims", "min_role": "supervisor", "label": "Document templates — publish a layout version (admin always · supervisor only when switched on · off until switched on)"},
      "cost":                  {"room": "ims", "label": "Inventory cost — stock value, layer values, unit costs (admin and supervisor always · person by person · read and write both show it · off until switched on)"}
    }
  }'::jsonb;
$$;
do $$ begin
  execute format('comment on function public.ims_perm_catalog() is %L',
    obj_description(to_regprocedure('public.ims_perm_catalog()'), 'pg_proc')
    || ' · ⭐ [2026-10-20 stk-av-1] screens.cost(ims 방 · 원가 보기 — 재고 금액 · 레이어 가치 · 단가 · admin · supervisor 는 역할로 · 나머지는 Staff 에서 · cost 와 cost:read 둘 다 보임(write 는 뒷날 원가 조정 열쇠 자리) — 문은 ims_can_view_cost() 하나 · 판정 567 · 575 · 578)');
end $$;

create function public.ims_can_view_cost() returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$ select public.ims_can_view('cost') $$;   -- stk-av-1 판정 578 「A」: admin · supervisor 는 역할로 · 나머지는 perms 의 cost 또는 cost:read(ims_can_view 와 같은 contract · ims_can_adjust_read 선례)
revoke all on function public.ims_can_view_cost() from public, anon;
grant execute on function public.ims_can_view_cost() to authenticated;
comment on function public.ims_can_view_cost() is '원가를 볼 수 있는가(stk-av-1 · 판정 567 · 575 · 578 · 2026-10-20) = ims_can_view(''cost'') — admin · supervisor 역할로 · 그 외는 perms cost 또는 cost:read · 모르는 값 · 비활성 · 행 없음 = false · 이 문을 보는 창구: stk_value_many · stk_value_total(원가를 내는 창구는 이 둘뿐 · 판정 262) · rls-3 이 레이어 표 정책에도 쓴다(판정 576)';

-- ═══ ② stk_reserved — 예약 목록(판정 566 「B」) ═══
create function public.stk_reserved(p_product_id uuid, p_warehouse_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_pid       uuid;
  v_sku       text;
  v_wh        text;
  v_sales     boolean;
  v_so        jsonb;
  v_trf       jsonb;
  v_so_total  numeric;
  v_trf_total numeric;
begin
  -- 문(판정 268) — 로그인 + 활성 직원 · 열쇠는 보지 않는다(stk_* 와 같은 문)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active;
  if v_wh is null then raise exception 'Warehouse not found or inactive — pick an active branch'; end if;
  select coalesce(p.parent_product_id, p.id) into v_pid from public.product p where p.id = p_product_id;   -- 재고 키 = 낱개(세트 id 를 받으면 그 낱개 · inv_available_base 와 같은 키)
  if v_pid is null then raise exception 'Product not found — nothing was read'; end if;
  select p.sku into v_sku from public.product p where p.id = v_pid;
  v_sales := public.ims_can_view('sales');   -- 손님 이름은 sales(:read 포함) 열쇠가 있는 사람에게만 · 창고 직원에게는 SO 번호 · 상태 · 수량만
  -- ⭐ 판매 예약 — inv_available_base 의 alloc 과 서로 같은 조건(판정 566) — 한쪽을 고치면 다른 쪽도:
  --   released_at null · kind allocated(hold · backorder · preorder 는 안 셈) · 오더 창고 s.location_id · 재고 키 coalesce(parent_product_id, id) · qty_allocated × 줄 pack_factor · 콤보는 구성품 줄이 그대로 걸린다
  select coalesce(jsonb_agg(jsonb_build_object(
           'so_id', s.id, 'so_number', s.so_number, 'status', s.status,
           'customer_name', case when v_sales then c.name end,
           'line_sku', l.sku, 'qty', r.qty_allocated, 'pack_factor', l.pack_factor, 'qty_ea', r.qty_allocated * l.pack_factor,
           'allocated_at', r.allocated_at) order by r.allocated_at, s.so_number, l.line_no), '[]'::jsonb),
         coalesce(sum(r.qty_allocated * l.pack_factor), 0)
    into v_so, v_so_total
  from public.so_reserve r
  join public.so_line l on l.id = r.so_line_id
  join public.so s on s.id = l.so_id
  join public.product p on p.id = l.product_id
  left join public.customer c on c.id = s.customer_id
  where r.released_at is null and r.kind = 'allocated'
    and s.location_id = p_warehouse_id
    and coalesce(p.parent_product_id, p.id) = v_pid;
  -- ⭐ 트랜스퍼 예약 — inv_available_base 의 talloc 과 서로 같은 조건(판정 566): status confirmed · at_wms · picking(출발 전) · 출발 창고 · qty × 줄 pack_factor
  select coalesce(jsonb_agg(jsonb_build_object(
           'transfer_id', t.id, 'transfer_number', t.transfer_number, 'status', t.status,
           'from_warehouse', wf.name, 'to_warehouse', wt.name,
           'line_sku', l.sku, 'qty', l.qty, 'pack_factor', l.pack_factor, 'qty_ea', l.qty * l.pack_factor,
           'confirmed_at', t.confirmed_at) order by t.transfer_number, l.line_no), '[]'::jsonb),
         coalesce(sum(l.qty * l.pack_factor), 0)
    into v_trf, v_trf_total
  from public.inv_transfer_line l
  join public.inv_transfer t on t.id = l.transfer_id
  join public.product p on p.id = l.product_id
  left join public.ref_warehouse wf on wf.id = t.from_warehouse_id
  left join public.ref_warehouse wt on wt.id = t.to_warehouse_id
  where t.status in ('confirmed', 'at_wms', 'picking')
    and t.from_warehouse_id = p_warehouse_id
    and coalesce(p.parent_product_id, p.id) = v_pid;
  return jsonb_build_object('product_id', v_pid, 'sku', v_sku, 'warehouse_id', p_warehouse_id, 'warehouse', v_wh, 'customer_name_visible', v_sales,
                            'so', v_so, 'so_total', v_so_total, 'trf', v_trf, 'trf_total', v_trf_total);
end;
$$;
revoke all on function public.stk_reserved(uuid, uuid) from public, anon;
grant execute on function public.stk_reserved(uuid, uuid) to authenticated;
comment on function public.stk_reserved(uuid, uuid) is
  '⭐ 제품 하나 × 창고 하나의 예약 목록(stk-av-1 · 판정 566 「B」 · 2026-10-20) — so[] {so_id · so_number · status · customer_name(sales 열쇠 없으면 null) · line_sku · qty · pack_factor · qty_ea · allocated_at} · trf[] {transfer_id · transfer_number · status · from_warehouse · to_warehouse · line_sku · qty · pack_factor · qty_ea · confirmed_at} · so_total · trf_total(EA) · ⭐ inv_available_base 의 alloc · talloc 과 서로 같은 조건 — 한쪽을 고치면 다른 쪽도 · 시험 「모든 제품 × 창고에서 so_total = sales_alloc_ea · trf_total = transfer_alloc_ea」 · 세트 id 를 받으면 그 낱개 · 문 = 로그인 + 활성 직원(판정 268) · definer(TRF 번호 · 상태 · 수량은 열쇠 없이 보인다 · 판정 264 의 연장) · 원가 없음(판정 262)';
do $$ begin
  execute format('comment on function public.inv_available_base(uuid, uuid[]) is %L',
    obj_description(to_regprocedure('public.inv_available_base(uuid, uuid[])'), 'pg_proc')
    || ' · ⭐ [2026-10-20 stk-av-1 판정 566] alloc · talloc 의 조건은 stk_reserved(목록)와 서로 같은 조건 — 한쪽을 고치면 다른 쪽도(시험: 모든 키 × 창고에서 목록 합 = 타일)');
end $$;

-- ═══ ③ stk_availability 재발행 — 공급처 · Both · 바코드 · by_warehouse (판정 570 · 571 · ⑥ · 262 그대로) ═══
drop function public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean);   -- 이견 6: create or replace 로는 옛 서명이 남아 PostgREST 가 후보를 못 고른다 — 옛 서명을 지우고 새로 · grant 다시
create function public.stk_availability(
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
  v_limit  int  := least(greatest(coalesce(p_limit, 100), 1), 500);
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
revoke all on function public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean, uuid) from public, anon;
grant execute on function public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean, uuid) to authenticated;
comment on function public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean, uuid) is
  '⭐ 브랜치별 재고 가용표 한 쪽(stk-1 · 판정 257 ~ 262 · 266 ~ 268 · sale-1 판정 361 · ⭐ stk-av-1 재발행 판정 570 · 571 · 575 · 2026-10-20) — 줄 = 재고 키(낱개 · 세트 · 콤보 줄 없음) × 고른 창고(활성만 · ⭐ p_warehouse_id null = Both = 활성 창고 전부 · 평평한 열은 합 · by_warehouse jsonb [{warehouse_id · warehouse · on_hand · sales_allocated · transfer_reserved · available · on_order · in_transit · last_event_on}] 창고 이름 순 · 한 창고면 원소 하나) · on_hand · sales_allocated · transfer_reserved · available · on_order · in_transit · last_event_on · 세트 sku 검색 → 낱개 줄(matched_set_*) · ⭐ p_q 가 활성 바코드와 정확히 같으면 그 제품(세트 바코드 → 낱개 줄 + 세트 표시 · 여러 제품이면 전부) · ⭐ p_supplier_id = 그 공급처의 활성 줄이 있는 제품 전부(기본 아니어도 · 세트 줄은 낱개로) · p_include_zero 거짓이면 다섯 숫자(Both 는 합) 모두 0 인 줄만 뺀다 · sale_pct · sale_conditional(so_sale_now) · p_sale_only · total = 거른 뒤 전체 수 · 문 = 로그인 + 활성 직원(열쇠 안 봄 · 판정 268) · definer · limit ≤ 500 · ⭐ 원가 열 없음(판정 262 · 575 — 금액은 stk_value_many · stk_value_total · 원가 열쇠) · rows_all 의 where 는 stk_value_total 의 keys 와 서로 같은 조건';

-- ═══ ④ stk_value_many · stk_value_total — 레이어 남은 금액 · 원가 열쇠 필수 (판정 567 · 575) ═══
create function public.stk_value_many(p_product_ids uuid[], p_warehouse_id uuid default null)
returns table(product_id uuid, warehouse_id uuid, warehouse text, layer_qty_ea numeric, remaining_value numeric)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_whs   uuid[];
  v_pids  uuid[];
begin
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  if not public.ims_can_view_cost() then raise exception 'You do not have the Inventory cost permission — an admin switches it on in Staff — nothing was read'; end if;   -- 판정 567 · 575: 원가는 열쇠가 있는 사람에게만 · DB 가 거부
  if p_warehouse_id is null then
    select coalesce(array_agg(w.id order by w.name), '{}'::uuid[]) into v_whs from public.ref_warehouse w where w.is_active;
    if cardinality(v_whs) = 0 then raise exception 'No active warehouse — nothing was read'; end if;
  else
    if not exists (select 1 from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active) then raise exception 'Warehouse not found or inactive — pick an active branch'; end if;
    v_whs := array[p_warehouse_id];
  end if;
  -- 판정 275 와 같은 규칙 — null · 중복 제거 → 500 초과 거부 · 0 이면 빈 결과 · 모르는 id 는 줄 없음 · 세트 id 는 그 낱개(재고 키)
  select coalesce(array_agg(distinct coalesce(p.parent_product_id, p.id)), '{}'::uuid[]) into v_pids
    from unnest(coalesce(p_product_ids, '{}'::uuid[])) as u(pid) join public.product p on p.id = u.pid;
  if cardinality((select array_agg(distinct u.pid) from unnest(coalesce(p_product_ids, '{}'::uuid[])) as u(pid) where u.pid is not null)) > 500 then
    raise exception 'Too many products (the limit is 500) — ask for one page at a time';
  end if;
  if cardinality(v_pids) = 0 then return; end if;
  return query
  with whs as (select w.id, w.name from public.ref_warehouse w where w.id = any(v_whs)),
  keys as (select p.id, p.sku from public.product p where p.id = any(v_pids)),
  -- ⭐ inv_layer_value 와 서로 같은 식(집합형 · 이견 9): 남은 수량 = qty − Σ소진 qty · 남은 가치 = unit_cost × qty + Σ얹음 − Σ소진 amount · 열린 레이어 = 남은 수량 > 0(inv_layer_open 과 같은 문) · 레이어마다 6 자리 반올림 뒤 합(inv_layer_open.remaining_cost 의 합과 같다)
  lay as (select l.id, l.sku, l.warehouse, l.qty, l.unit_cost from public.inv_layer l join keys k on k.sku = l.sku join whs x on x.name = l.warehouse),
  a as (select ca.layer_id, sum(ca.amount) as s from public.inv_layer_cost_add ca join lay on lay.id = ca.layer_id group by 1),
  c as (select k.layer_id, sum(k.qty) as q, sum(k.amount) as m from public.inv_layer_consume k join lay on lay.id = k.layer_id group by 1),
  v as (select lay.sku, lay.warehouse, lay.qty - coalesce(c.q, 0) as rem_qty, round(lay.unit_cost * lay.qty + coalesce(a.s, 0) - coalesce(c.m, 0), 6) as rem_val
        from lay left join a on a.layer_id = lay.id left join c on c.layer_id = lay.id)
  select k.id, x.id, x.name,
         coalesce(sum(v.rem_qty) filter (where v.rem_qty > 0), 0),
         coalesce(sum(v.rem_val) filter (where v.rem_qty > 0), 0)
  from keys k cross join whs x
  left join v on v.sku = k.sku and v.warehouse = x.name
  group by k.id, x.id, x.name
  order by k.id, x.name;
end;
$$;
revoke all on function public.stk_value_many(uuid[], uuid) from public, anon;
grant execute on function public.stk_value_many(uuid[], uuid) to authenticated;
comment on function public.stk_value_many(uuid[], uuid) is
  '⭐ 제품 여럿 × 창고의 레이어 남은 금액(stk-av-1 · 판정 567 · 575 · 2026-10-20 · 「레이어 남은 금액」 — 레이어 수량 ≠ 장부 수량이라 layer_qty_ea 를 함께 낸다) — 줄 = 재고 키 × 창고(p_warehouse_id null = 활성 창고 전부) · remaining_value = Σ 열린 레이어의 (unit_cost × qty + Σ얹음 − Σ소진 amount)(inv_layer_value 와 서로 같은 식 · 집합형 · 레이어마다 6 자리) · layer_qty_ea = Σ 남은 수량 · 레이어 없는 키는 0 · 배열 규칙은 판정 275 와 같다(500 상한 · 세트 id 는 그 낱개) · ⭐ 문 = 로그인 + 활성 직원 + 원가 열쇠(ims_can_view_cost · 없으면 거부) · definer · 쪽마다 한 번(stk_bins_many 선례)';

create function public.stk_value_total(p_warehouse_id uuid, p_q text default null, p_brand_id uuid default null, p_category_id uuid default null, p_supplier_id uuid default null, p_sale_only boolean default false)
returns table(warehouse_id uuid, warehouse text, products int, layer_qty_ea numeric, remaining_value numeric)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_q     text := nullif(btrim(p_q), '');
  v_whs   uuid[];
begin
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  if not public.ims_can_view_cost() then raise exception 'You do not have the Inventory cost permission — an admin switches it on in Staff — nothing was read'; end if;   -- 판정 567 · 575
  if p_warehouse_id is null then
    select coalesce(array_agg(w.id order by w.name), '{}'::uuid[]) into v_whs from public.ref_warehouse w where w.is_active;
    if cardinality(v_whs) = 0 then raise exception 'No active warehouse — nothing was read'; end if;
  else
    if not exists (select 1 from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active) then raise exception 'Warehouse not found or inactive — pick an active branch'; end if;
    v_whs := array[p_warehouse_id];
  end if;
  return query
  with whs as (select w.id, w.name from public.ref_warehouse w where w.id = any(v_whs)),
  sale as (select z.product_id from public.so_sale_now(null, null) z),
  bc as (select coalesce(s.parent_product_id, s.id) as stock_pid from public.product_barcode b join public.product s on s.id = b.product_id where v_q is not null and b.is_active and b.barcode = v_q group by 1),
  setm as (select s.parent_product_id as stock_pid from public.product s
           where v_q is not null and s.parent_product_id is not null
             and (s.sku ilike '%' || v_q || '%' or exists (select 1 from public.product_barcode b where b.product_id = s.id and b.is_active and b.barcode = v_q)) group by 1),
  sup as (select distinct coalesce(sp.parent_product_id, sp.id) as stock_pid from public.product_supplier ps join public.product sp on sp.id = ps.product_id
          where p_supplier_id is not null and ps.supplier_id = p_supplier_id and ps.is_active),
  keys as (                                                                                -- ⭐ stk_availability rows_all 의 where 와 서로 같은 조건 — 한쪽을 고치면 다른 쪽도 · 0 줄 숨김은 여기 없다(창고의 레이어 가치 전부)
    select p.id, p.sku
    from public.product p
    left join setm on setm.stock_pid = p.id
    left join sale on sale.product_id = p.id
    left join bc   on bc.stock_pid = p.id
    left join sup  on sup.stock_pid = p.id
    where p.parent_product_id is null
      and (not p_sale_only or sale.product_id is not null)
      and not exists (select 1 from public.product_bom bm where bm.parent_product_id = p.id and bm.is_active)
      and (p_brand_id is null or p.brand_id = p_brand_id)
      and (p_category_id is null or p.category_id = p_category_id)
      and (p_supplier_id is null or sup.stock_pid is not null)
      and (v_q is null or p.sku ilike '%' || v_q || '%' or p.name ilike '%' || v_q || '%' or p.brand_name ilike '%' || v_q || '%' or setm.stock_pid is not null or bc.stock_pid is not null)
  ),
  -- ⭐ inv_layer_value 와 서로 같은 식(stk_value_many 와 같은 네 CTE)
  lay as (select l.id, l.sku, l.warehouse, l.qty, l.unit_cost from public.inv_layer l join keys k on k.sku = l.sku join whs x on x.name = l.warehouse),
  a as (select ca.layer_id, sum(ca.amount) as s from public.inv_layer_cost_add ca join lay on lay.id = ca.layer_id group by 1),
  c as (select k.layer_id, sum(k.qty) as q, sum(k.amount) as m from public.inv_layer_consume k join lay on lay.id = k.layer_id group by 1),
  v as (select lay.sku, lay.warehouse, lay.qty - coalesce(c.q, 0) as rem_qty, round(lay.unit_cost * lay.qty + coalesce(a.s, 0) - coalesce(c.m, 0), 6) as rem_val
        from lay left join a on a.layer_id = lay.id left join c on c.layer_id = lay.id)
  select x.id, x.name,
         count(distinct v.sku) filter (where v.rem_qty > 0)::int,
         coalesce(sum(v.rem_qty) filter (where v.rem_qty > 0), 0),
         coalesce(sum(v.rem_val) filter (where v.rem_qty > 0), 0)
  from whs x
  left join v on v.warehouse = x.name
  group by x.id, x.name
  order by x.name;
end;
$$;
revoke all on function public.stk_value_total(uuid, text, uuid, uuid, uuid, boolean) from public, anon;
grant execute on function public.stk_value_total(uuid, text, uuid, uuid, uuid, boolean) to authenticated;
comment on function public.stk_value_total(uuid, text, uuid, uuid, uuid, boolean) is
  '⭐ 창고의 레이어 남은 금액 합계(stk-av-1 · 판정 567 · 575 · 2026-10-20) — 줄 = 창고(p_warehouse_id null = 활성 창고 전부) · products = 열린 레이어가 있는 재고 키 수 · layer_qty_ea · remaining_value(inv_layer_value 와 서로 같은 식 · 집합형 · ≈ 1 초 · 화면은 단추로 부른다) · 거르기(p_q · 브랜드 · 분류 · 공급처 · 세일)는 stk_availability rows_all 의 where 와 서로 같은 조건 — 한쪽을 고치면 다른 쪽도 · 0 줄 숨김은 없다(거른 재고 키 전부) · ⭐ 문 = 로그인 + 활성 직원 + 원가 열쇠(ims_can_view_cost · 없으면 거부) · definer';

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text; v_base text;
begin
  if to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean)') is not null then v_bad := v_bad || ' old_stk_availability_left'; end if;
  if to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean, uuid)') is null or to_regprocedure('public.stk_reserved(uuid, uuid)') is null
     or to_regprocedure('public.stk_value_many(uuid[], uuid)') is null or to_regprocedure('public.stk_value_total(uuid, text, uuid, uuid, uuid, boolean)') is null
     or to_regprocedure('public.ims_can_view_cost()') is null then v_bad := v_bad || ' functions'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('stk_availability', 'stk_reserved', 'stk_value_many', 'stk_value_total', 'ims_can_view_cost') and p.prosecdef) <> 5 then v_bad := v_bad || ' definer'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('stk_availability', 'stk_reserved', 'stk_value_many', 'stk_value_total', 'ims_can_view_cost')
        and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')) <> 5 then v_bad := v_bad || ' grants'; end if;
  if not (public.ims_perm_catalog()->'screens' ? 'cost') then v_bad := v_bad || ' catalog_cost'; end if;
  if (select count(*) from jsonb_object_keys(public.ims_perm_catalog()->'screens')) <> 17 then v_bad := v_bad || ' catalog_count'; end if;
  if exists (select 1 from pg_proc p where p.oid in (to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean, uuid)'), to_regprocedure('public.stk_reserved(uuid, uuid)'), to_regprocedure('public.inv_available_base(uuid, uuid[])'))
               and pg_get_function_result(p.oid) ~* '(amount|unit_price|cost|value)') then v_bad := v_bad || ' cost_column(262)'; end if;
  if pg_get_function_result(to_regprocedure('public.stk_availability(uuid, text, uuid, uuid, boolean, int, int, boolean, uuid)')) !~ 'by_warehouse jsonb\)$' then v_bad := v_bad || ' by_warehouse_last'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.stk_reserved(uuid, uuid)');
  select p.prosrc into v_base from pg_proc p where p.oid = to_regprocedure('public.inv_available_base(uuid, uuid[])');
  if v_src !~ 'r\.kind = ''allocated''' or v_base !~ 'r\.kind = ''allocated''' or v_src !~ '\(''confirmed'', ''at_wms'', ''picking''\)' or v_base !~ '\(''confirmed'', ''at_wms'', ''picking''\)' then v_bad := v_bad || ' same_conditions(566)'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('stk_value_many', 'stk_value_total') and p.prosrc ~ 'ims_can_view_cost\(\)') <> 2 then v_bad := v_bad || ' cost_gate'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM575', message = format('STOP - stk-av-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
