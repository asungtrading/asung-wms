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

-- ═══ mrg-1 — 합치기(so_merge)가 시스템 줄을 「손으로」 로 바꾸는 결함 고치기 (2026-10-20 · 판정 548 · ln-1 보고 발견 1) ═══
--   원본 = so_merge 마지막 정의 20261020123910_ln_1_paste_price_lines_clear_price_set_by.sql 바이트 + 바뀐 줄(묶기 열쇠에 discount_source · deal_line_id · 계획 jsonb 의 출처 · 딜 · differs_in 둘 · insert 의 deal_line_id)
--   판정 548(Caleb 「A」): 합친 줄은 원본의 출처 · 딜을 그대로 싣는다 → 시스템 줄로 돌아가 오더 할인을 받고(od-1 so_line_manual false) · 합친 뒤 so_reprice 는 시스템 줄을 다시 매긴다(합친 수량 · 그날 · 그때 딜)
--   · 손 줄(price_override · manual) · shopify 줄(판정 433)은 계속 kept. 정본 §21 「합친 줄은 전부 manual 이라 … 건드리지 않는다」는 이 판정으로 바뀐다
--   옛 식(so-merge-1 · 2026-09-25): 'discount_source' = price_override → null · discount_pct not null → 'manual' · else null — 할인 % 가 있는 모든 시스템 줄(customer · deal · set · shopify)이 manual 이 되고 deal_line_id 는 글자 null 로 들어갔다
--   같은 식을 가진 할인 출처 함수는 so_merge 하나(나머지 'manual' 은 세금 규칙 · 쿠폰 사유 · 원가 출처) · 테스트 DB 의 옛 manual 줄 34(합친 오더 3)는 고치지 않는다(원래 출처를 모른다)

-- ═══ so_merge 재발행 ═══
create or replace function public.so_merge(p_so_ids uuid[], p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_head_fields constant text[] := array['ship_to_company','ship_to_contact','ship_to_phone','ship_to_line1','ship_to_line2','ship_to_city','ship_to_state_province','ship_to_postal_code','ship_to_country',
                                         'bill_to_customer_id','bill_to_name','bill_to_line1','bill_to_line2','bill_to_city','bill_to_state_province','bill_to_postal_code','bill_to_country',
                                         'payment_term_id','payment_term_name','price_tier','price_tier_id','tax_rule','tax_rule_id','tax_rule_manual','discount_pct',
                                         'order_discount_pct','order_discount_source','order_discount_deal_id','required_by','ref','comments','intake',
                                         'carrier','tracking_number','shipping_notes','ar_account_code','sale_account_code'];
  v_staff   uuid;
  v_ids     uuid[];
  v_n       int;
  v_today   date := public.ims_today();
  v_old     public.so%rowtype;                       -- 가장 오래된 원본 = 머리(⬜2)
  v_head    public.so%rowtype;                       -- 미리 보기용 가상 머리(order_date = 오늘)
  v_new     public.so%rowtype;
  v_cust    public.customer%rowtype;
  v_numbers text;
  v_any_confirmed boolean;
  v_diffs   jsonb; v_plan jsonb; v_calc_in jsonb; v_hint jsonb; v_pay jsonb; v_sib jsonb; v_sup jsonb; v_charges jsonb;
  v_warn    text[] := '{}';
  v_note    text;
  v_id      uuid;
  v_line_id uuid;
  v_cnt     int;
  v_bo      int := 0; v_reopened int := 0; v_released int := 0; v_moved int := 0; v_lines_n int := 0;
  v_combos  jsonb := '[]'::jsonb;  v_comp_n int := 0;                 -- asm-2b2(묶음 2 · 3): 콤보 줄끼리 합친다(열쇠 + 구성품 모양) · 합친 콤보 줄 아래 구성품을 다시 매단다(합친 콤보 수 × combo_qty · 저장된 combo_qty 로 · 정의가 바뀐 콤보는 열쇠가 갈라 따로 둔다)
  r record;
  e jsonb;
  v_cps jsonb := '[]'::jsonb;  v_best_cp uuid;  v_best_pct numeric := -1;  v_cp_pct numeric;   -- dsc-3b 판정 324 — 원본 쿠폰 가운데 큰 쪽
  od record;
  v_bo_msg  text;                                    -- bo-1d 판정 484: 열린 백오더 오더 거부 문장
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — sales 묶음
  v_staff := public.so_current_staff();

  -- ── 대상 검사 ──
  select array_agg(distinct x) into v_ids from unnest(p_so_ids) x where x is not null;
  if coalesce(array_length(p_so_ids, 1), 0) <> coalesce(array_length(v_ids, 1), 0) then raise exception 'The same order is listed twice — nothing was saved'; end if;
  if coalesce(array_length(v_ids, 1), 0) < 2 then raise exception 'A merge needs at least two orders — nothing was saved'; end if;
  perform 1 from public.so s where s.id = any(v_ids) order by s.id for update;
  get diagnostics v_n = row_count;
  if v_n <> array_length(v_ids, 1) then raise exception 'Order not found — nothing was saved'; end if;
  for r in select s.* from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number loop
    if r.status not in ('draft', 'confirmed') then
      raise exception 'Order % is % — only draft or confirmed orders still in IMS can be merged — nothing was saved', r.so_number,
        r.status || case when r.status = 'cancelled' and r.closed_reason = 'merged' then ' (already merged into ' || coalesce((select m.so_number from public.so m where m.id = r.merged_into_id), '?') || ')'
                         when r.status in ('at_wms', 'picking', 'packed') then ' (it is with the warehouse — merge is only possible before release)'
                         else '' end;
    end if;
    if r.channel <> 'warehouse' then raise exception 'Order % is a % order — only warehouse orders can be merged — nothing was saved', r.so_number, r.channel; end if;
  end loop;
  if (select count(distinct s.customer_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders belong to different customers — nothing was saved'; end if;
  if (select count(distinct coalesce(s.location_id::text, '(none)')) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are for different warehouses — change the warehouse first — nothing was saved'; end if;
  if (select count(distinct s.currency_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are in different currencies — nothing was saved'; end if;
  -- bo-1d 판정 484: 열린 백오더 예약이 있는 오더는 합치지 않는다(합치면 같은 제품 줄 수량이 더해져 확정 때의 이어받기를 건너뛴다 · 백오더의 길은 진행 · 이어받기 · 만료 · 취소) · 콤보 줄이면 구성품 줄의 예약(was_backorder 와 같은 모양) · 미리 보기도 같은 거부 · 프리오더 · 보류 · 할당은 막지 않는다
  select format('Order %s has open backorder lines (%s) — a backorder is not merged: proceed it when stock arrives, or confirm the new order so it takes the backorder over — nothing was saved',
                b.so_number, b.skus || case when b.n > 5 then ' and ' || (b.n - 5)::text || ' more' else '' end)
    into v_bo_msg
  from (select s.so_number, s.order_date, count(*) as n, string_agg(d.sku, ', ' order by d.line_no) filter (where d.rn <= 5) as skus
        from public.so s
        join (select l.so_id, l.line_no, l.sku, row_number() over (partition by l.so_id order by l.line_no) as rn
              from public.so_line l
              where l.combo_line_id is null
                and exists (select 1 from public.so_reserve rs join public.so_line cp on cp.id = rs.so_line_id
                            where (cp.id = l.id or cp.combo_line_id = l.id) and rs.released_at is null and rs.kind = 'backorder')) d on d.so_id = s.id
        where s.id = any(v_ids)
        group by s.id, s.so_number, s.order_date
        order by s.order_date, s.so_number limit 1) b;
  if v_bo_msg is not null then raise exception '%', v_bo_msg; end if;
  select c.* into v_cust from public.customer c where c.id = (select s.customer_id from public.so s where s.id = v_ids[1]);
  if not v_cust.is_active then raise exception 'Customer % is inactive — nothing was saved', v_cust.name; end if;
  v_any_confirmed := exists (select 1 from public.so s where s.id = any(v_ids) and s.status = 'confirmed');
  if v_any_confirmed then perform public.so_require_role('manager', 'saved'); end if;   -- 판정 5 · R5: 확정 오더의 재고를 푸는 순간 선을 넘는다

  select s.* into v_old from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number limit 1;
  select string_agg(s.so_number, ', ' order by s.order_date, s.so_number) into v_numbers from public.so s where s.id = any(v_ids);

  -- ── 머리 차이(판정 2·7 · 막지 않는다) ──
  select coalesce(jsonb_agg(jsonb_build_object('field', d.f, 'values', d.vals) order by d.f), '[]'::jsonb) into v_diffs
  from (select f, jsonb_agg(jsonb_build_object('so_number', s.so_number, 'value', to_jsonb(s)->f) order by s.order_date, s.so_number) as vals
        from public.so s cross join unnest(c_head_fields) f
        where s.id = any(v_ids)
        group by f having count(distinct coalesce(to_jsonb(s)->f, 'null'::jsonb)) > 1) d;

  -- ── 줄 계획(판정 4 · 고침 ①: 열쇠 = 제품 · 단가 · 정가 · 할인 % · 무상 사유 · override · 부가 셋 — tax_rule 은 열쇠 밖 · 전부 합친 오더 규칙) ──
  with src as (
    select l.*, s.so_number, dense_rank() over (order by s.order_date, s.so_number) as ord,
           exists (select 1 from public.so_reserve rs join public.so_line cp on cp.id = rs.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and rs.released_at is null and rs.kind = 'preorder')  as was_preorder,    -- asm-2b2: 콤보 줄의 예약은 구성품에
           exists (select 1 from public.so_reserve rs join public.so_line cp on cp.id = rs.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and rs.released_at is null and rs.kind = 'backorder') as was_backorder,
           (l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, v_today)) as deal_ended,
           (select string_agg(cp.sku || ':' || trim_scale(cp.combo_qty)::text, ',' order by cp.sku) from public.so_line cp where cp.combo_line_id = l.id) as combo_sig   -- asm-2b2: 콤보 줄의 구성품 모양(열쇠에 든다 · 보통 줄은 null)
    from public.so_line l join public.so s on s.id = l.so_id
    where s.id = any(v_ids) and l.combo_line_id is null                                                                                  -- asm-2b2: 구성품 줄은 계획에 들지 않는다(콤보 줄을 따라 다시 선다)
  ), grp as (
    select product_id, unit_price, list_price, discount_pct, free_reason, price_override, surcharge_pct, surcharge_amount, surcharge_label, combo_sig, discount_source, deal_line_id,   -- mrg-1 판정 548: 출처 · 딜도 열쇠(다르면 따로 줄)
           min(ord * 100000 + line_no) as first_pos, sum(qty_ordered) as qty, count(*) as n, (array_agg(id order by ord, line_no))[1] as first_line_id,
           (array_agg(sku order by ord, line_no))[1] as sku, (array_agg(product_name order by ord, line_no))[1] as product_name,
           (array_agg(unit order by ord, line_no))[1] as unit, (array_agg(pack_factor order by ord, line_no))[1] as pack_factor,
           (array_agg(comments order by ord, line_no) filter (where comments is not null))[1] as comments,
           (array_agg(price_set_by order by ord, line_no) filter (where price_set_by is not null))[1] as price_set_by,   -- ln-1 판정 546: 첫 원본의 setter(값이 있는 것 가운데 첫째)
           (array_agg(price_set_at order by ord, line_no) filter (where price_set_by is not null))[1] as price_set_at,
           bool_or(was_preorder) as was_preorder, bool_or(was_backorder) as was_backorder, bool_or(deal_ended) as deal_ended,
           jsonb_agg(jsonb_build_object('so_number', so_number, 'line_no', line_no, 'line_id', id, 'qty', qty_ordered, 'discount_source', discount_source, 'deal_line_id', deal_line_id,
                                        'was_preorder', was_preorder, 'was_backorder', was_backorder) order by ord, line_no) as sources
    from src
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
  ), numbered as (
    select g.*, row_number() over (order by g.first_pos) as line_no,
           count(*) over (partition by g.product_id) as n_same_product,
           first_value(g.unit_price)     over (partition by g.product_id order by g.first_pos) as p_unit_price,
           first_value(g.list_price)     over (partition by g.product_id order by g.first_pos) as p_list_price,
           first_value(g.discount_pct)   over (partition by g.product_id order by g.first_pos) as p_discount_pct,
           first_value(g.free_reason)    over (partition by g.product_id order by g.first_pos) as p_free_reason,
           first_value(g.price_override) over (partition by g.product_id order by g.first_pos) as p_override,
           first_value(g.surcharge_label) over (partition by g.product_id order by g.first_pos) as p_surcharge_label,
           first_value(g.combo_sig)      over (partition by g.product_id order by g.first_pos) as p_combo_sig,
           first_value(g.discount_source) over (partition by g.product_id order by g.first_pos) as p_discount_source,   -- mrg-1
           first_value(g.deal_line_id)   over (partition by g.product_id order by g.first_pos) as p_deal_line_id
    from grp g
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'line_no', x.line_no, 'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name, 'unit', x.unit, 'pack_factor', x.pack_factor,
           'qty', x.qty, 'list_price', x.list_price, 'discount_pct', x.discount_pct, 'unit_price', x.unit_price, 'price_override', x.price_override, 'free_reason', x.free_reason,
           'discount_source', x.discount_source, 'deal_line_id', x.deal_line_id,                                                                                    -- mrg-1 판정 548: 원본의 「왜 이 할인」 그대로(customer · deal · set · shopify · manual · 덮어쓴 줄은 null) — 옛 식은 할인 % 가 있는 시스템 줄을 manual 로 바꿨다
           'surcharge_pct', x.surcharge_pct, 'surcharge_amount', x.surcharge_amount, 'surcharge_label', x.surcharge_label, 'comments', x.comments,
           'price_set_by', x.price_set_by, 'price_set_at', x.price_set_at,                                                                                      -- ln-1
           'source_lines', x.n, 'sources', x.sources, 'was_preorder', x.was_preorder, 'was_backorder', x.was_backorder, 'deal_ended', x.deal_ended,
           'is_combo', x.combo_sig is not null, 'combo_sig', x.combo_sig, 'first_line_id', x.first_line_id,                                              -- asm-2b2
           'kept_apart', (x.n_same_product > 1),
           'differs_in', case when x.n_same_product > 1 then
              (select coalesce(jsonb_agg(k), '[]'::jsonb) from unnest(array[
                 case when x.unit_price is distinct from x.p_unit_price then 'unit_price' end,
                 case when x.list_price is distinct from x.p_list_price then 'list_price' end,
                 case when x.discount_pct is distinct from x.p_discount_pct then 'discount_pct' end,
                 case when x.free_reason is distinct from x.p_free_reason then 'free_reason' end,
                 case when x.price_override is distinct from x.p_override then 'price_override' end,
                 case when x.surcharge_label is distinct from x.p_surcharge_label then 'surcharge' end,
                 case when x.combo_sig is distinct from x.p_combo_sig then 'combo_definition' end,
                 case when x.discount_source is distinct from x.p_discount_source then 'discount_source' end,                                                   -- mrg-1
                 case when x.deal_line_id is distinct from x.p_deal_line_id then 'deal' end]) k where k is not null)
              else '[]'::jsonb end) order by x.line_no), '[]'::jsonb)
    into v_plan
  from numbered x;
  v_lines_n := coalesce(jsonb_array_length(v_plan), 0);

  -- ── 판정 4 보완 ①: 가상 머리(가장 오래된 원본 + 오늘) 로 다시 견적 ──
  v_head := v_old;
  v_head.order_date := v_today;
  select coalesce(jsonb_agg(jsonb_build_object('line_no', p->'line_no', 'product_id', p->'product_id', 'sku', p->'sku', 'qty', p->'qty', 'unit_price', p->'unit_price', 'discount_pct', p->'discount_pct',
                                               'discount_source', p->'discount_source', 'free_reason', p->'free_reason', 'price_override', p->'price_override')), '[]'::jsonb)
    into v_calc_in from jsonb_array_elements(v_plan) p;
  v_hint := public.so_merge_requote_calc(v_head, v_calc_in);

  -- ── 선결제 대상(옮긴다 · 조사 ③ unique (payment_id, so_id)) ──
  select coalesce(jsonb_agg(jsonb_build_object('payment_id', x.id, 'amount', x.amount, 'method', x.method, 'paid_on', x.paid_on, 'targets', x.targets) order by x.paid_on, x.id), '[]'::jsonb) into v_pay
  from (select p.id, p.amount, p.method, p.paid_on, jsonb_agg(s.so_number order by s.so_number) as targets
        from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active' join public.so s on s.id = o.so_id
        where o.so_id = any(v_ids) group by p.id, p.amount, p.method, p.paid_on) x;

  -- ── 판정 1 로 이어받기에서 빠질 형제(원본의 split 자손 중 열린 백오더가 있는 confirmed 오더) ──
  with recursive d as (
    select s.id, 0 as depth, array[s.id] as path from public.so s where s.id = any(v_ids)
    union all
    select c.id, d.depth + 1, d.path || c.id from d join public.so c on c.split_from_id = d.id where d.depth < 50 and not (c.id = any(d.path))
  )
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'status', s.status, 'split_reason', s.split_reason,
           'open_backorder_lines', (select count(*) from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null)) order by s.so_number), '[]'::jsonb)
    into v_sib
  from d join public.so s on s.id = d.id
  where d.depth > 0 and not (s.id = any(v_ids)) and s.status = 'confirmed'
    and exists (select 1 from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null);

  -- ── 원본이 확정 때 이어받은 남의 백오더 줄(⬜4 · 0-7: confirmed 이고 열린 예약이 없는 줄만 다시 연다 · 나머지는 닫힌 채 + 경고) ──
  select coalesce(jsonb_agg(jsonb_build_object('close_id', c.id, 'so_number', s.so_number, 'line_no', l.line_no, 'sku', l.sku, 'qty_open', c.qty_open, 'qty_taken', c.qty_taken, 'qty_unwanted', c.qty_unwanted,
           'taken_by', t.so_number, 'target_status', s.status,
           'reopenable', (s.status = 'confirmed' and not exists (select 1 from public.so_reserve rs where rs.so_line_id = l.id and rs.released_at is null))) order by s.so_number, l.line_no), '[]'::jsonb)
    into v_sup
  from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id join public.so s on s.id = l.so_id join public.so t on t.id = c.taken_by_so_id
  where c.taken_by_so_id = any(v_ids) and c.reopened_at is null and c.end_kind = 'superseded';

  -- ── 운임(판정 8: 옮기지 않는다 · 다시 계산한다) ──
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'line_no', c.line_no, 'name', c.name, 'amount', c.amount) order by s.so_number, c.line_no), '[]'::jsonb) into v_charges
  from public.so_charge c join public.so s on s.id = c.so_id where c.so_id = any(v_ids);

  -- ── 경고(막지 않는다) ──
  if jsonb_array_length(v_diffs) > 0 then v_warn := array_append(v_warn, 'head_differs'); end if;
  if jsonb_array_length(v_charges) > 0 then v_warn := array_append(v_warn, 'charges_not_merged'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'was_preorder')::boolean) then v_warn := array_append(v_warn, 'preorder_lines_need_reflag'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'deal_ended')::boolean) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if exists (select 1 from jsonb_array_elements(v_sup) x where not (x->>'reopenable')::boolean) then v_warn := array_append(v_warn, 'superseded_not_reopenable'); end if;
  if v_old.order_date <> v_today and v_lines_n > 0 then v_warn := array_append(v_warn, 'reprice_suggested'); end if;   -- §13 판정 3: 주문일이 바뀌면 줄은 그대로 + 표시 + 경고
  if jsonb_array_length(v_sib) > 0 then v_warn := array_append(v_warn, 'backorder_siblings_stay_open'); end if;      -- 판정 1 · 0-1 대가

  if not p_commit then
    return jsonb_build_object('committed', false, 'orders', to_jsonb(string_to_array(v_numbers, ', ')), 'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today,
                              'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'charges', v_charges,
                              'needs_manager', v_any_confirmed, 'warnings', to_jsonb(v_warn));
  end if;

  -- ── 실행 ① 새 오더(머리 통째 복사 · 위 주석의 칸 표) ──
  v_id := gen_random_uuid();
  v_note := 'Merged from ' || v_numbers;
  insert into public.so
  select * from jsonb_populate_record(null::public.so,
    to_jsonb(v_old) || jsonb_build_object(
      'id', v_id, 'so_number', public.so_next_number(), 'status', 'draft', 'order_date', v_today, 'ref', null,
      'comments', case when v_old.comments is null then v_note else v_old.comments || E'\n' || v_note end,
      'split_from_id', null, 'split_reason', null,
      'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
      'confirmed_at', null, 'confirmed_by', null, 'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null,
      'unconfirmed_at', null, 'unconfirmed_by', null, 'carrier', null, 'carrier_id', null, 'tracking_number', null,   -- ful-1c: carrier_id 도 비운다(합친 뒤 Ship & invoice 에서 고른다)
      'reprice_suggested_at', null, 'order_discount_locked_at', null,
      'created_at', now(), 'created_by', v_staff, 'updated_at', now(), 'updated_by', v_staff));
  select * into v_new from public.so where id = v_id;
  perform public.so_order_discount_apply(v_id, v_staff);                             -- 판정 7 · dsc-3a 판정 308 · 312: 새 머리는 잠기지 않는다 · manual 은 helper 가 그대로 · 줄이 들어오며 so_line 트리거가 금액 단계로 다시 고른다

  -- ── 실행 ② 줄(계획 그대로 · tax_rule = 합친 오더 규칙 · 짝 표) ──
  for e in select p from jsonb_array_elements(v_plan) p order by (p->>'line_no')::int loop
    insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                                list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, updated_by, price_set_by, price_set_at)
    values (v_id, (e->>'line_no')::int, (e->>'product_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
            (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, (e->>'unit_price')::numeric, (e->>'price_override')::boolean, e->>'discount_source', (e->>'deal_line_id')::uuid, e->>'free_reason',   -- mrg-1: 딜 연결도 그대로(짝 CHECK so_line_deal_line_pair_ck)
            (e->>'surcharge_pct')::numeric, (e->>'surcharge_amount')::numeric, e->>'surcharge_label', v_new.tax_rule, e->>'comments', v_staff, (e->>'price_set_by')::uuid, (e->>'price_set_at')::timestamptz)   -- ln-1
    returning id into v_line_id;
    insert into public.so_line_merge_source (line_id, from_line_id, created_by)
    select v_line_id, (x->>'line_id')::uuid, v_staff from jsonb_array_elements(e->'sources') x;
    if (e->>'is_combo')::boolean then v_combos := v_combos || jsonb_build_object('line_id', v_line_id, 'first_line_id', e->'first_line_id', 'qty', e->'qty', 'sources', e->'sources'); end if;
  end loop;
  -- asm-2b2(묶음 2): 합친 콤보 줄마다 구성품을 다시 매단다 — 첫 원본 콤보 줄의 구성품(저장된 combo_qty · 정의를 다시 읽지 않는다) · 수량 = 합친 콤보 수 × combo_qty · 값 0 · 줄 번호는 끝에(so_line_add 와 같은 자리) · 짝 표에 원본 구성품 줄도
  for e in select p from jsonb_array_elements(v_combos) p loop
    insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, updated_by, combo_line_id, combo_qty)
    select v_id, (select coalesce(max(n.line_no), 0) from public.so_line n where n.so_id = v_id) + row_number() over (order by cp.line_no), cp.product_id, cp.sku, cp.product_name, cp.unit, cp.pack_factor, (e->>'qty')::numeric * cp.combo_qty,
           null, null, 0, false, null, null, null, null, null, null, v_new.tax_rule, null, v_staff, (e->>'line_id')::uuid, cp.combo_qty
    from public.so_line cp where cp.combo_line_id = (e->>'first_line_id')::uuid;
    get diagnostics v_cnt = row_count;  v_comp_n := v_comp_n + v_cnt;
    insert into public.so_line_merge_source (line_id, from_line_id, created_by)
    select n.id, sc.id, v_staff
    from public.so_line n join jsonb_array_elements(e->'sources') sx on true join public.so_line sc on sc.combo_line_id = (sx->>'line_id')::uuid and sc.product_id = n.product_id
    where n.so_id = v_id and n.combo_line_id = (e->>'line_id')::uuid;
  end loop;
  if v_old.order_date <> v_today and v_lines_n > 0 then
    update public.so set reprice_suggested_at = now(), updated_by = v_staff where id = v_id;
  end if;
  -- dsc-3b 판정 324: 원본들의 쿠폰 가운데 helper 로 골라 본 % 가 큰 쪽만 새 머리에(같으면 오래된 원본 것) · 나머지는 뗀 채 남는다(원본은 merged 라 가족 판정에 안 걸린다)
  for r in select s.coupon_id, s.so_number, s.created_at from public.so s where s.id = any(v_ids) and s.coupon_id is not null order by s.created_at, s.so_number loop
    update public.so set coupon_id = r.coupon_id where id = v_id;
    perform public.so_order_discount_apply(v_id, v_staff, true);
    select case when s.order_discount_source = 'coupon' then s.order_discount_pct else -1 end into v_cp_pct from public.so s where s.id = v_id;
    v_cps := v_cps || jsonb_build_object('so_number', r.so_number, 'code', (select c.code from public.so_coupon c where c.id = r.coupon_id),
                                         'pct', (select public.so_coupon_pct(c, s) from public.so_coupon c, public.so s where c.id = r.coupon_id and s.id = v_id), 'won_pct', nullif(v_cp_pct, -1));
    if v_cp_pct > v_best_pct then v_best_pct := v_cp_pct; v_best_cp := r.coupon_id; end if;
  end loop;
  if v_cps <> '[]'::jsonb then
    update public.so set coupon_id = case when v_best_pct > -1 then v_best_cp else null end where id = v_id;
    perform public.so_order_discount_apply(v_id, v_staff, true);
    select coalesce(jsonb_agg(c || jsonb_build_object('kept', (select s.coupon_id from public.so s where s.id = v_id) = (select x.id from public.so_coupon x where x.code = c->>'code'))), '[]'::jsonb) into v_cps from jsonb_array_elements(v_cps) c;
  end if;

  -- ── 실행 ③ 원본의 열린 백오더 줄 → 장부 merged + 예약 closed(0-4) · asm-2b2: 수요 줄 단위(콤보 줄은 구성품 예약을 콤보 수로 · 장부는 콤보 줄에 · 구성품 예약 함께 닫힘) ──
  for r in
    select x.id as so_line_id, q.qty_open, q.ids as reserve_ids
    from public.so_line x
    cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, array_agg(res.id) as ids
                        from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                        where (cp.id = x.id or cp.combo_line_id = x.id) and res.released_at is null and res.kind = 'backorder') q
    where x.so_id = any(v_ids) and x.combo_line_id is null and q.qty_open is not null
  loop
    perform public.so_backorder_record(r.so_line_id, 'merged', r.qty_open, 0, 0, null, null, v_staff, 'Merged into ' || v_new.so_number);
    update public.so_reserve set released_at = now(), released_by = v_staff, released_reason = 'closed', updated_by = v_staff where id = any(r.reserve_ids);
    v_bo := v_bo + 1;
  end loop;

  -- ── 실행 ④ 원본이 이어받은 남의 줄 다시 열기(⬜4 · confirmed 이고 열린 예약 없는 줄만 · so_backorder_reopen 과 같은 모양) ──
  for r in select (x->>'close_id')::uuid as close_id, (x->>'reopenable')::boolean as ok from jsonb_array_elements(v_sup) x loop
    if r.ok then
      update public.so_backorder_close set reopened_at = now(), reopened_by = v_staff, updated_by = v_staff where id = r.close_id and reopened_at is null;
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
      select c.so_line_id, c.qty_open, 'backorder', null from public.so_backorder_close c where c.id = r.close_id;
      v_reopened := v_reopened + 1;
    end if;
  end loop;

  -- ── 실행 ⑤ 원본의 남은 열린 예약(allocated · preorder · hold) 풀기 → released(트리거가 reason 을 넣는다 · ⬜5) ──
  update public.so_reserve res set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x where x.id = res.so_line_id and res.released_at is null and x.so_id = any(v_ids);
  get diagnostics v_released = row_count;

  -- ── 실행 ⑥ 원본 닫기(한 문장 · so_merge_reason_ck 양방향 · so_closed_at_ck) ──
  update public.so set status = 'cancelled', closed_reason = 'merged', merged_into_id = v_id, closed_at = now(), closed_note = 'Merged into ' || v_new.so_number, cancelled_by = v_staff, updated_by = v_staff
  where id = any(v_ids) and status in ('draft', 'confirmed');
  get diagnostics v_cnt = row_count;
  if v_cnt <> array_length(v_ids, 1) then
    raise exception 'Not every order could be merged — one may have been changed by someone else just now — nothing was saved';
  end if;

  -- ── 실행 ⑦ 선결제 대상 옮기기(원본 행은 기록으로 · 합친 오더 행 하나) ──
  insert into public.so_payment_order (payment_id, so_id, created_by)
  select distinct o.payment_id, v_id, v_staff
  from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active'
  where o.so_id = any(v_ids)
  on conflict on constraint so_payment_order_uq do nothing;
  get diagnostics v_moved = row_count;

  return jsonb_build_object('committed', true, 'so_id', v_id, 'so_number', v_new.so_number, 'status', 'draft', 'orders', to_jsonb(string_to_array(v_numbers, ', ')),
                            'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today, 'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint,
                            'payments_moved', v_moved, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'superseded_reopened', v_reopened,
                            'backorder_lines_recorded', v_bo, 'reserves_released', v_released, 'charges', v_charges, 'component_lines', v_comp_n, 'coupons', v_cps, 'warnings', to_jsonb(v_warn));   -- asm-2b2: 다시 매단 구성품 줄 수
end;
$$;
comment on function public.so_merge(uuid[], boolean) is
  'SO 합치기(④b so-merge-1 · asm-2b2 · dsc-3a · dsc-3b · ful-1c · bo-1d · ln-1 · mrg-1 재발행 · 판정 1 ~ 8 · 484 · 548) — definer · sales · draft/confirmed · 창고 오더 · 같은 손님 · 창고 · 통화 · 열린 백오더 거부(484) · 줄 묶기 열쇠 = 제품 · 단가 · 정가 · 할인 % · 무상 · override · surcharge 셋 · combo_sig · 출처 · 딜(548 · 다르면 따로 줄 kept_apart · differs_in) · 합친 줄은 원본의 discount_source · deal_line_id · price_set_by/at(첫 원본) 그대로 · p_commit false = 미리 보기(계획 = 저장)';

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_src text := (select prosrc from pg_proc where oid = 'public.so_merge(uuid[], boolean)'::regprocedure); v_bad text := '';
begin
  if v_src ~ 'when x\.discount_pct is not null then ''manual''' then v_bad := v_bad || ' old-manual-expr'; end if;
  if v_src !~ '''discount_source'', x\.discount_source, ''deal_line_id'', x\.deal_line_id' then v_bad := v_bad || ' plan-source'; end if;
  if v_src !~ 'group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12' then v_bad := v_bad || ' group-key'; end if;
  if v_src !~ '\(e->>''deal_line_id''\)::uuid, e->>''free_reason''' then v_bad := v_bad || ' insert-deal'; end if;
  if v_src !~ 'then ''deal'' end\]\) k where k is not null' then v_bad := v_bad || ' differs-in'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname <> 'so_merge' and prosrc ~ 'when x\.discount_pct is not null then ''manual''') <> 0 then v_bad := v_bad || ' other-fn'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM511', message = format('STOP - mrg-1 did not land as designed:%s - nothing was changed', v_bad); end if;
end $$;
