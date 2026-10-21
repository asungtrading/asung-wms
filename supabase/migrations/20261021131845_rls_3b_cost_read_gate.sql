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

-- ═══ rls-3b — 원가 읽기 가리기(장부 원가 · 공급처 단가) + 장부 원가를 읽는 invoker 함수 여섯 → definer (2026-10-21 · 판정 576 · 580 · 582 · rls-3 조사 이견 1 ~ 4 · 10 · rls-3b 이견 · 정본 so-module §68 뒤) ═══
--   결함(판정 576): 레이어 표 셋(inv_layer · inv_layer_cost_add · inv_layer_consume · rls-1) · inv_cost · inv_doc_cost(rls-3a)의 select 정책이 using (true) 라 로그인한 직원 누구나 PostgREST 로 장부 원가를 읽었다 ·
--     뷰 inv_layer_open(security_invoker 없음 · authenticated SELECT) · inv_layer_value(definer · 문 없음 · authenticated EXECUTE)로 layer id 만 알면 원가가 나왔다 · product_supplier(공급처 단가 · 공식)도 select true.
--   판정 580(울타리): 장부 원가 = 원가 열쇠(ims_can_view_cost) · product_supplier = purchasing · master · cost 중 하나라도 보기 열쇠 · PO · 인보이스 단가 · po_receipt_cost · inv_cost_adjust · inv_ledger(수량 표 — 행을 가리면 재고가 사라진다) · inv_snapshot.value 는 그대로.
--   순서(파일 · 한 트랜잭션): ⓪ 도우미 ims_require_ok → ③ ④ 함수 여섯 definer(정책을 가리기 전에 — invoker 가 가려진 표를 읽어 「조용히 0 행」이 되는 틈이 없게) → ① ② 정책 → ⑤ inv_layer_open 회수 → ⑥ inv_layer_value 회수(inv_adjust_eval 이 definer 가 된 뒤) → 착지.
--   ③ 새 첫 줄 문(판정 582 · 부르는 화면의 열쇠): so_stock_short_list → sales 보기 · so_credit_detail → sales 보기 · po_fx_cost_lines → purchasing 보기 · inv_adjust_eval → ims_can_adjust_read() · 원가 값 칸만 case when ims_can_view_cost() — 목록 · 개수 · 판정(cost_source · unknown · cost_branch)은 열쇠와 무관.
--   ④ 문 그대로 · 값만 열쇠로: po_charge_confirm(ims_require_write('purchasing') · 되돌리기 판정 「landed 가 이미 얹혔으면 거부」는 postgres 로 세어 열쇠와 무관 — 576 의 장부 결함이 안 생긴다 · 반환 'cost' 의 금액 칸만 뺀다) · inv_transfer_detail(ims_can_view('transfer') · carried 넷 · posted_cad 둘만 null · layers 수 · 비용 문서의 돈(total_cad · total_amount)은 그대로).
--   ⚠️ inv_layer_value 의 몸에는 문을 넣지 않는다(rls-3 조사 이견 2): definer 7(inv_layer_post_sale · post_credit · post_adjust · fifo_take · apply_adjust · apply_credit · so_credit_cancel)이 부르고 definer 안에서도 auth.uid() 는 부른 직원이라 원가 열쇠 없는 직원의 Ship · 크레딧 · 조정이 막힌다 ⇒ EXECUTE 회수만 · 몸 md5 2d4a569c… 그대로.
--   ⚠️ po_fx_cost_lines 는 레이어에서 수량 · 개수만 쓰고 돌려주는 돈은 po_receipt_cost · inv_cost_adjust 의 것(판정 580 그대로) — case 없음 · 문만. po_invoice_detail 은 inv_cost_adjust 만 읽어 이 차수 밖. so_backorder_* 셋(invoker · product_supplier 를 기본 공급처 이름에 씀 · sales 화면)은 이견 0 — 이 차수에서 재발행하지 않는다(474 행).
--   무접촉: 여섯 표의 grant · WMS 18 · inv_ledger · inv_config · rls-3a 의 16 표 · rls-3a 가 회수한 함수 11 의 ACL · 운영(가드).

-- ═══ 무접촉 증거 — 정책(wms · inv_ledger · inv_config · rls-3a 16) · grant(wms · inv_* 표 전부 + product_supplier · 뷰 inv_layer_open 은 이 차수가 회수하므로 뺀다) · 함수 ACL(rls-3a 11) 을 글 하나로 ═══
create temp table rls3b_before as
select md5(string_agg(k, ',' order by k)) as untouched
from (
  select 'pol:' || tablename || ':' || policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-') as k
    from pg_policies where schemaname = 'public' and (tablename like 'wms\_%' or tablename in ('inv_ledger', 'inv_config', 'inv_snapshot', 'inv_sync_state', 'inv_sku_types', 'inv_doc_state', 'inv_voided_docs', 'inv_missing_docs', 'inv_missing_lines', 'inv_conflicts', 'inv_collect_runs', 'inv_snapshot_runs', 'inv_compare', 'inv_compare_runs', 'inv_balance_diffs', 'inv_bin_notes'))
  union all
  select 'grant:' || table_name || ':' || grantee || ':' || privilege_type
    from information_schema.role_table_grants where table_schema = 'public' and (table_name like 'wms\_%' or table_name like 'inv\_%' or table_name = 'product_supplier') and table_name <> 'inv_layer_open'
  union all
  select 'fn:' || p.proname || ':' || coalesce(p.proacl::text, '-')
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_carry', 'inv_layer_cost_add_settle', 'inv_snap_balance_diffs', 'inv_compare_run', 'inv_ack_diff', 'tf_charge_confirm', 'tf_charge_update', 'tf_charge_delete', 'tf_charge_alloc_add', 'tf_charge_alloc_update', 'tf_charge_alloc_delete')
) s;

-- ═══ ⓪ 도우미 — sql 함수의 첫 문장 문(sql 은 raise 를 못 한다 · plpgsql 도우미가 대신) ═══
create function public.ims_require_ok(p_ok boolean, p_message text) returns boolean
  language plpgsql stable
  set search_path = public, pg_temp
as $$
begin
  if coalesce(p_ok, false) then return true; end if;
  raise exception '%', p_message;
end $$;
revoke all on function public.ims_require_ok(boolean, text) from public, anon;
grant execute on function public.ims_require_ok(boolean, text) to authenticated;
comment on function public.ims_require_ok(boolean, text) is 'rls-3b(2026-10-21) — p_ok 가 아니면 p_message 로 raise · sql 언어 definer 함수(inv_adjust_eval · po_fx_cost_lines)의 첫 문장 문에 쓴다(sql 은 raise 가 없다)';

-- ═══ so_stock_short_list 재발행 — 원본 20260925144959_so_pos_a3_lists.sql:88 바이트 + 머리 줄 하나(security invoker → definer) + 첫 줄 문 + unit_cost case · rls-3b ═══
CREATE OR REPLACE FUNCTION public.so_stock_short_list(p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER   -- rls-3b
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  f          jsonb := coalesce(p_filters, '{}'::jsonb);
  v_wh       text;
  v_unc_only boolean := coalesce((f->>'unchecked_only')::boolean, false);
  v_to       date := coalesce(nullif(f->>'to', '')::date, public.ims_today());
  v_from     date := coalesce(nullif(f->>'from', '')::date, public.ims_today() - 30);
  v_limit    int  := least(greatest(coalesce((f->>'limit')::int, 200), 1), 500);
  v_offset   int  := greatest(coalesce((f->>'offset')::int, 0), 0);
  v_open     jsonb;  v_open_n int;
  v_done     jsonb;  v_done_n int;
  v_unknown  int;
begin
  if not public.ims_can_view('sales') then raise exception 'You cannot view sales data — ask an admin to add the ''sales'' permission — nothing was read'; end if;   -- rls-3b(판정 582): 첫 줄 문 = Action Centre 의 열쇠(sales 보기) · definer 라 표 정책을 지나므로 여기서 거른다
  if nullif(f->>'warehouse_id', '') is not null then
    select w.name into v_wh from public.ref_warehouse w where w.id = (f->>'warehouse_id')::uuid;
    if v_wh is null then raise exception 'Warehouse not found'; end if;
  elsif nullif(f->>'warehouse', '') is not null then
    v_wh := f->>'warehouse';
  end if;
  if v_from > v_to then raise exception 'from % is after to %', v_from, v_to; end if;

  with rows as (
    select y.id as layer_id, y.doc_number, y.sku, y.warehouse, y.qty, y.received_on, y.cost_source, case when (select public.ims_can_view_cost()) then y.unit_cost end as unit_cost, (y.cost_source = 'unknown') as unknown,   -- rls-3b(판정 580): 원가 값만 열쇠로 · 목록 · 개수 · cost_source 는 그대로
           s.id as so_id, s.channel, s.status as so_status, s.customer_id, c.name as customer_name,
           k.id as check_id, k.checked_at, k.checked_by, ks.name as checked_by_name, k.note
    from public.inv_layer y
    left join public.so s on s.so_number = y.doc_number
    left join public.customer c on c.id = s.customer_id
    left join public.so_stock_short_check k on k.doc_number = y.doc_number and k.sku = y.sku and k.warehouse = y.warehouse
    left join public.ims_staff ks on ks.id = k.checked_by
    where y.origin_type = 'sale_shortfall' and (v_wh is null or y.warehouse = v_wh)
  )
  select coalesce((select jsonb_agg(to_jsonb(r) order by r.received_on desc, r.doc_number, r.sku) from rows r where r.check_id is null), '[]'::jsonb),
         (select count(*) from rows r where r.check_id is null),
         (select count(*) from rows r where r.check_id is null and r.unknown),
         case when v_unc_only then '[]'::jsonb else
           coalesce((select jsonb_agg(to_jsonb(r) order by r.checked_at desc, r.doc_number, r.sku)
                     from (select * from rows r where r.check_id is not null and (r.checked_at at time zone 'America/Toronto')::date between v_from and v_to
                           order by r.checked_at desc, r.doc_number, r.sku limit v_limit offset v_offset) r), '[]'::jsonb) end,
         case when v_unc_only then 0 else (select count(*) from rows r where r.check_id is not null and (r.checked_at at time zone 'America/Toronto')::date between v_from and v_to) end
    into v_open, v_open_n, v_unknown, v_done, v_done_n;

  return jsonb_build_object(
    'warehouse', v_wh, 'from', v_from, 'to', v_to, 'limit', v_limit, 'offset', v_offset,
    'unchecked_count', v_open_n, 'unchecked_unknown_cost', v_unknown, 'checked_in_range', v_done_n,
    'unchecked', v_open, 'checked', v_done);
end;

$function$;

-- ═══ so_credit_detail 재발행 — 원본 20260925205011_so_credit_read.sql:69 바이트 + 머리 줄 하나(security invoker → definer) + 첫 줄 문 + layers unit_cost case · rls-3b ═══
CREATE OR REPLACE FUNCTION public.so_credit_detail(p_credit_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER   -- rls-3b
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cr public.so_credit%rowtype;
begin
  if not public.ims_can_view('sales') then raise exception 'You cannot view sales data — ask an admin to add the ''sales'' permission — nothing was read'; end if;   -- rls-3b(판정 582): 첫 줄 문 = Credit Notes 의 열쇠(sales 보기) · definer 라 표 정책을 지나므로 여기서 거른다
  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  if not found then raise exception 'Credit note not found'; end if;
  return jsonb_build_object(
    'credit', to_jsonb(v_cr),
    'customer_name', (select c.name from public.customer c where c.id = v_cr.customer_id),
    'invoice_number', (select i.invoice_number from public.so_invoice i where i.id = v_cr.invoice_id),
    'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.line_no), '[]'::jsonb) from public.so_credit_line l where l.credit_id = v_cr.id),
    'allocations', (select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at), '[]'::jsonb) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null),
    'applied', (select coalesce(sum(a.amount), 0) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null),
    'remaining', public.so_credit_remaining(v_cr.id),                                                                                   -- so-credit-read-1 C1: 식의 한 곳(옛 식은 C0 정의 그대로였다)
    -- so-credit-read-1 R2(2026-09-25) — 더한 키 넷(옛 키 아홉은 그대로 · 부르는 곳 0 이지만 규칙대로 더하기만)
    'credit_row', (select to_jsonb(v) from public.so_credit_list v where v.id = v_cr.id),
    'allocations_all', (select coalesce(jsonb_agg(jsonb_build_object('alloc_id', a.id, 'invoice_id', a.invoice_id, 'invoice_number', i.invoice_number, 'invoice_status', i.status,
                                                                     'refund_payment_id', a.refund_payment_id, 'refund_paid_on', p.paid_on, 'refund_method', p.method, 'refund_reference', p.reference, 'refund_status', p.status,
                                                                     'amount', a.amount, 'source', a.source, 'voided_at', a.voided_at, 'void_note', a.void_note, 'created_at', a.created_at) order by a.created_at), '[]'::jsonb)
                        from public.so_credit_alloc a left join public.so_invoice i on i.id = a.invoice_id left join public.so_payment p on p.id = a.refund_payment_id
                        where a.credit_id = v_cr.id),
    'open_invoices', (select coalesce(jsonb_agg(jsonb_build_object('invoice_id', l.id, 'invoice_number', l.invoice_number, 'issued_on', l.issued_on, 'due_on', l.due_on, 'due_unknown', l.due_unknown,
                                                                   'total', l.total, 'remaining', l.remaining, 'days_overdue', l.days_overdue, 'so_numbers', l.so_numbers,
                                                                   'attached_from_this_credit', coalesce((select sum(a.amount) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.invoice_id = l.id and a.voided_at is null), 0)) order by l.issued_on, l.invoice_number), '[]'::jsonb)
                      from public.so_invoice_list l
                      where l.is_open and l.bill_to_customer_id = v_cr.customer_id and l.currency_id = v_cr.currency_id),
    'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_cr.customer_id) b where b.currency_id = v_cr.currency_id),
    'ledger', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'occurred_on', g.occurred_on, 'sku', g.sku, 'warehouse', g.warehouse, 'bin', g.bin, 'qty_delta', g.qty_delta, 'line_ref', g.line_ref, 'cost', g.raw -> 'cost') order by g.id), '[]'::jsonb)
                 from public.inv_ledger g where g.doc_type = 'creditnote' and g.doc_number = v_cr.credit_number and g.source = 'ims'),
    'layers', (select coalesce(jsonb_agg(jsonb_build_object('id', y.id, 'sku', y.sku, 'warehouse', y.warehouse, 'qty', y.qty, 'unit_cost', case when (select public.ims_can_view_cost()) then y.unit_cost end /* rls-3b(판정 580): 원가 값만 열쇠로 */, 'cost_source', y.cost_source, 'parent_layer_id', y.parent_layer_id,
                                                            'consumed', (select coalesce(sum(k.qty), 0) from public.inv_layer_consume k where k.layer_id = y.id)) order by y.id), '[]'::jsonb)
               from public.inv_layer y where y.origin_type = 'creditnote' and y.doc_number = v_cr.credit_number));
end;

$function$;

-- ═══ inv_adjust_eval 재발행 — 원본 20260930144905_cogs_2_cost_split.sql:1463 바이트 + 머리 줄 하나(security invoker → definer) + 첫 문장 문 + avg_cost case · rls-3b ═══
CREATE OR REPLACE FUNCTION public.inv_adjust_eval(p_adjust_id uuid)
 RETURNS TABLE(line_id uuid, line_no integer, product_id uuid, sku text, bin_id uuid, bin text, mode text, qty_input numeric, reason text, reason_note text, unit_cost numeric, seen_ledger numeric, seen_picked numeric, ledger numeric, picked numeric, basis numeric, delta numeric, result numeric, cost_branch text, avg_unit_cost numeric, rejects text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER   -- rls-3b
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.ims_require_ok(public.ims_can_adjust_read(), 'You cannot view stock adjustments — this needs the stock_adjust key — nothing was read');   -- rls-3b(판정 582): 첫 줄 문 = inv_adjust 의 select 정책과 같은 열쇠 · definer 라 표 정책을 지나므로 여기서 거른다(sql 함수 — 도우미가 raise)
  with h as (select a.warehouse, a.warehouse_id from public.inv_adjust a where a.id = p_adjust_id),
  x as materialized (                                                                     -- adj-a2(판정 54 B): 줄마다 장부 · P · avg · 칸을 한 번만 — 인라인된 식이 참조 자리마다 다시 돌던 것(≈13회/줄)을 막는다
    select l.*, public.inv_adjust_ledger(h.warehouse, l.bin, l.sku) as ledger, public.inv_adjust_picked(h.warehouse_id, l.bin_id, l.product_id) as picked,
           (select coalesce(sum(v.remaining_value) / nullif(sum(v.remaining_qty), 0), null)                   -- cogs-2(판정 111): 남은 가치 ÷ 남은 수량 · 식은 inv_layer_value 하나
              from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = l.sku and y.warehouse = h.warehouse and v.remaining_qty > 0) as avg_cost,
           (select b.is_active and b.warehouse_id = h.warehouse_id from public.ref_bin b where b.id = l.bin_id) as bin_ok
      from public.inv_adjust_line l, h where l.adjust_id = p_adjust_id
  ),
  y as (select x.*, x.ledger - x.picked as basis, case when x.mode = 'set' then x.qty_input - (x.ledger - x.picked) else x.qty_input end as d from x)
  select y.id, y.line_no, y.product_id, y.sku, y.bin_id, y.bin, y.mode, y.qty_input, y.reason, y.reason_note, y.unit_cost,
         y.seen_ledger, y.seen_picked, y.ledger, y.picked, y.basis, y.d, y.ledger + y.d,
         case when y.d > 0 and y.unit_cost is not null then 'manual' when y.d > 0 and y.avg_cost is not null then 'layer_avg'
              when y.d > 0 then 'unknown' when y.d < 0 then 'fifo' else 'none' end,
         case when (select public.ims_can_view_cost()) then round(y.avg_cost, 6) end,   -- rls-3b(판정 580): avg_unit_cost 값만 열쇠로 · 방법 칸(layer_avg · unknown)은 위에서 실제 avg 로 정한다 · 확정(inv_layer_post_adjust)은 레이어에서 다시 센다
         array_remove(array[
           case when y.ledger + y.d < 0 then format('line %s %s %s: result would be %s (below zero)', y.line_no, y.sku, y.bin, y.ledger + y.d) end,
           case when y.ledger <> y.seen_ledger then format('line %s %s %s: ledger changed (you saw %s, it is now %s)', y.line_no, y.sku, y.bin, y.seen_ledger, y.ledger) end,
           case when y.picked <> y.seen_picked then format('line %s %s %s: picked-not-shipped changed (you saw %s, it is now %s)', y.line_no, y.sku, y.bin, y.seen_picked, y.picked) end,
           case when not coalesce(y.bin_ok, false) then format('line %s: bin %s is inactive or not in this warehouse', y.line_no, y.bin) end
         ], null)
    from y order by y.line_no;

$function$;

-- ═══ po_fx_cost_lines 재발행 — 원본 20261020143921_rcv_1a_receipt_line_ref_suffix.sql:1352 바이트 + 머리 줄 하나(security invoker → definer) + 첫 문장 문 · rls-3b ═══
CREATE OR REPLACE FUNCTION public.po_fx_cost_lines(p_po_id uuid)
 RETURNS TABLE(po_line_id uuid, line_no integer, sku text, layers integer, layer_qty numeric, pin_source text, pin_fx numeric, unit_price_net numeric, target_cad numeric, layer_cad numeric, fx_fix_cad numeric, already_cad numeric, remaining_cad numeric, excluded_invoice_layers integer, unpinned_layers integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER   -- rls-3b
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.ims_require_ok(public.ims_can_view('purchasing'), 'You cannot view purchasing data — ask an admin to add the ''purchasing'' permission — nothing was read');   -- rls-3b(판정 582): 첫 줄 문 = Purchase Orders 의 열쇠(purchasing 보기) · definer 라 표 정책을 지나므로 여기서 거른다 · 돌려주는 돈은 po_receipt_cost · inv_cost_adjust 의 것(판정 580 그대로) — 레이어는 수량 · 개수만 쓴다
  with p as (
    select x.id, x.exchange_rate, (c.code is not distinct from b.code) as is_base
      from public.po x join public.ref_currency c on c.id = x.currency_id
      left join (select k.value as code from public.inv_config k where k.key = 'base_currency') b on true
     where x.id = p_po_id
  ), ly as (
    select pl.id as po_line_id, pl.line_no, pr.sku, y.id as layer_id, y.qty, y.unit_cost,
           k.exchange_rate_source as pin_source, k.exchange_rate as pin_fx, k.unit_price_net, k.unit_cost_cad
      from public.po_line pl join public.product pr on pr.id = pl.product_id
      join public.inv_layer y on public.inv_po_line_of(y.line_ref) = pl.id::text and y.origin_type = 'purchase' and y.cost_source = 'po_line'   -- rcv-1a
      left join public.po_receipt r on r.receipt_number = y.doc_number
      left join public.po_receipt_cost k on k.receipt_id = r.id and k.po_line_id = pl.id
     where pl.po_id = p_po_id
  ), fx as (
    select j.po_line_id, coalesce(sum(j.amount_cad), 0) as fx_fix_cad
      from public.inv_cost_adjust j
     where j.source_type = 'fx_fix' or (j.source_type = 'reversal' and exists (select 1 from public.inv_cost_adjust o where o.id = j.reverses_id and o.source_type = 'fx_fix'))   -- 이견 10: fx_fix 와 그 되돌림만
     group by j.po_line_id
  ), g as (
    select ly.po_line_id, ly.line_no, ly.sku,
           count(*)::int as layers,
           coalesce(sum(ly.qty) filter (where ly.pin_source = 'po'), 0) as layer_qty,
           min(ly.pin_source) filter (where ly.pin_source = 'po') as pin_source,
           max(ly.pin_fx) filter (where ly.pin_source = 'po') as pin_fx,
           max(ly.unit_price_net) filter (where ly.pin_source = 'po') as unit_price_net,
           coalesce(sum(ly.qty * ly.unit_price_net * (select coalesce(p.exchange_rate, 0) from p)) filter (where ly.pin_source = 'po'), 0) as target_cad,
           coalesce(sum(ly.qty * ly.unit_cost_cad) filter (where ly.pin_source = 'po'), 0) as layer_cad,
           count(*) filter (where ly.pin_source = 'invoice')::int as excluded_invoice_layers,
           count(*) filter (where ly.unit_cost_cad is null)::int as unpinned_layers
      from ly group by ly.po_line_id, ly.line_no, ly.sku
  )
  select g.po_line_id, g.line_no, g.sku, g.layers, g.layer_qty, g.pin_source, g.pin_fx, g.unit_price_net,
         case when (select p.is_base from p) or (select p.exchange_rate from p) is null then 0 else g.target_cad end as target_cad,
         g.layer_cad, coalesce(fx.fx_fix_cad, 0) as fx_fix_cad,
         g.layer_cad + coalesce(fx.fx_fix_cad, 0) as already_cad,
         case when (select p.is_base from p) or (select p.exchange_rate from p) is null or g.layer_qty = 0 then 0
              else round(g.target_cad - g.layer_cad - coalesce(fx.fx_fix_cad, 0), 2) end as remaining_cad,   -- 기준통화 · 환율 없음 · po 핀 없음 → 0
         g.excluded_invoice_layers, g.unpinned_layers
    from g left join fx on fx.po_line_id = g.po_line_id
   order by g.line_no

$function$;

-- ═══ po_charge_confirm 재발행 — 원본 20261020153535_rcv_1b_post_now.sql:857 바이트 + 머리 줄 하나(security invoker → definer) + 반환 'cost' 의 금액 칸 case(첫 줄 문 ims_require_write('purchasing') 그대로 · 되돌리기 판정 줄 그대로) · rls-3b ═══
CREATE OR REPLACE FUNCTION public.po_charge_confirm(p_charge_id uuid, p_confirm boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER   -- rls-3b
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_doc   text;                                                 -- ②-b: 0행 문장용(returning 이 v_chg 를 null 로 덮는다)
  v_staff uuid;
  v_chg   public.po_charge%rowtype;
  v_m     record;
  v_n     int;
  v_txt   text;
  v_warn  text[] := '{}';
  v_cost  jsonb;                                                -- 원가 창구의 반환(원가 이식 2차 · 2026-09-19)
  v_cur   text;                                                 -- ⑥ 환율 게이트 — 청구 통화 코드
  v_base_cur text;                                              -- ⑥ 기준통화 코드(inv_config.base_currency) · ⚠️ 원문에 같은 이름 없음 확인(2026-09-19 v_base 실사고)
  v_rate  numeric;                                              -- po-tax-2 · 제안 규칙 세율(경고용)
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_chg from public.po_charge where id = p_charge_id;
  if not found then raise exception 'Charge % not found — nothing was saved', p_charge_id; end if;
  v_doc := 'Charge ' || v_chg.charge_number;
  select * into v_m from public.po_charge_money where id = p_charge_id;

  if p_confirm then
    if v_chg.status = 'confirmed' then raise exception 'Charge % is already confirmed — nothing was saved', v_chg.charge_number; end if;
    if v_chg.status = 'cancelled' then raise exception 'Charge % is cancelled — a cancelled document cannot be confirmed — nothing was saved', v_chg.charge_number; end if;
    select count(*) into v_n from public.po_charge_alloc where po_charge_id = p_charge_id;
    if v_n = 0 then raise exception 'Charge % has no allocation lines — nothing to put on cost — nothing was saved', v_chg.charge_number; end if;
    -- ⭐⭐ 거부(경고 아님) — 양쪽 다 우리가 넣는 숫자라 안 맞으면 덜 입력한 것(⑤)
    if v_m.unallocated <> 0 then
      raise exception 'Charge % is not fully allocated — total % · allocated % · unallocated % — fix the allocations (or press Spread) first — nothing was saved',
        v_chg.charge_number, v_m.total_amount, v_m.alloc_sum, v_m.unallocated;
    end if;
    if v_chg.total_amount = 0 then v_warn := array_append(v_warn, 'total_amount_zero'); end if;
    select r.rate_pct into v_rate from public.ref_tax_rule r where r.id = v_chg.tax_rule_id;                 -- po-tax-2
    if coalesce(v_rate, 0) > 0 and v_chg.tax_amount = 0 then v_warn := array_append(v_warn, 'tax_amount_zero_with_rate'); end if;   -- po-tax-2 · 막지 않는다(세금은 낼 돈만 · 원가 무관)
    if exists (select 1 from public.po_charge_alloc a join public.po x on x.id = a.po_id where a.po_charge_id = p_charge_id and x.status = 'cancelled') then
      v_warn := array_append(v_warn, 'alloc_on_cancelled_po');
    end if;
    -- ⑥ ⭐⭐ 환율 — 기준통화가 아닌 비용인데 환율이 없거나 0 이면 확정 거부(입고와 같은 이유 · 원가가 조용히 틀리는 것보다 낫다 · 원가 이식 2차 2026-09-19)
    --   ⚠️ po_charge.exchange_rate 는 CAD per USD 다 — amount × exchange_rate = CAD. 곱한다 · 나누지 않는다(계산은 inv_layer_post_charge 에서).
    select c.code into v_cur from public.ref_currency c where c.id = v_chg.currency_id;
    select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
    if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which charges need an exchange rate — nothing was saved'; end if;
    if v_cur is distinct from v_base_cur and (v_chg.exchange_rate is null or v_chg.exchange_rate <= 0) then
      raise exception 'Charge % is in % but has no % per % exchange rate — the cost cannot be put on stock without it. Enter the rate on the charge ("Exchange rate") and confirm again — nothing was saved',
        v_chg.charge_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
    end if;
    update public.po_charge set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now() where id = p_charge_id returning * into v_chg;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    -- ⭐ 원가 — 같은 트랜잭션으로 레이어에 얹는다(원장 이식 2차의 ⓔ 와 같은 판단 · 원칙 2 「안에 있는 것끼리는 창구를 부른다」 · 하나가 실패하면 확정도 실패)
    v_cost := public.inv_layer_post_charge(p_charge_id);
    if coalesce((v_cost->>'no_layers_allocs')::int, 0) > 0 then v_warn := array_append(v_warn, 'cost_not_on_stock_no_receipt_yet'); end if;   -- 입고가 없는 발주 — 나중에 백필(inv_layer_post_charge 재호출)
    if coalesce((v_cost->>'no_basis_allocs')::int, 0) > 0 then v_warn := array_append(v_warn, 'cost_dropped_no_basis'); end if;                 -- 정본 D — 기준 0 은 버린다
    if coalesce((v_cost->>'deferred_allocs')::int, 0) > 0 then v_warn := array_append(v_warn, 'cost_deferred_post_now'); end if;                -- rcv-1b(판정 553) — 먼저 반영 묶음이 있는 draft 입고 · 마지막 확정 때 얹힌다
  else
    if v_chg.status <> 'confirmed' then raise exception 'Charge % is % — only a confirmed document can be reopened — nothing was saved', v_chg.charge_number, v_chg.status; end if;
    -- ⭐ po_invoice_confirm Reopen · po_doc_cancel 과 같은 선 — 결제 참조번호·금액을 이름으로
    if v_m.paid > 0 then
      select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
      from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
      where pa.po_charge_id = p_charge_id;
      raise exception 'Charge % has payments applied (%) — cannot reopen while paid; remove the payment allocation first — nothing was saved', v_chg.charge_number, v_txt;
    end if;
    -- ⭐ [원가 이식 2차] landed 가 이미 레이어에 얹혔으면 되돌리지 않는다 — 원가는 append-only. 되돌려 배분을 고치고 다시 확정해도 멱등이 건너뛰어 옛 금액이 남는다.
    select count(*) into v_n from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = v_chg.charge_number;
    if v_n > 0 then
      raise exception 'Charge % has already been added to stock cost (% layer row(s)) — it cannot be reopened; to correct it, enter an offsetting charge — nothing was saved', v_chg.charge_number, v_n;
    end if;
    update public.po_charge set status = 'draft', confirmed_by = null, confirmed_at = null where id = p_charge_id returning * into v_chg;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
  end if;

  return jsonb_build_object(
    'id', v_chg.id, 'charge_number', v_chg.charge_number, 'status', v_chg.status, 'confirmed_at', v_chg.confirmed_at,
    'money', jsonb_build_object('total_amount', v_m.total_amount, 'paid', v_m.paid, 'unpaid', v_m.unpaid, 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated,
                                'tax_amount', v_m.tax_amount, 'total_with_tax', v_m.total_with_tax),         -- po-tax-2
    'cost', case when public.ims_can_view_cost() then v_cost else v_cost - 'amount_posted_cad' - 'late_sold_cad' - 'late_moved_cad' - 'no_layers_amount_cad' - 'deferred_amount_cad' - 'allocs' end,   -- rls-3b(판정 580): 원가 금액 칸만 열쇠로 · layers_touched · status · warnings 는 그대로                                                                              -- ⭐ 원가 결과(layers_touched · amount_posted_cad · no_layers · no_basis · allocs[]) · 되돌리기면 null
    'warnings', to_jsonb(v_warn));
end;

$function$;

-- ═══ inv_transfer_detail 재발행 — 원본 20261008174126_po_tax_2.sql:1013 바이트 + 머리 줄 하나(security invoker → definer) + carried 넷 · posted_cad 둘 case(첫 줄 문 ims_can_view('transfer') 그대로 · layers 수 그대로) · rls-3b ═══
CREATE OR REPLACE FUNCTION public.inv_transfer_detail(p_transfer_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER   -- rls-3b
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when not public.ims_can_view('transfer') then null::jsonb else (
    select jsonb_build_object(
      'header', to_jsonb(x) || jsonb_build_object('from_warehouse', fw.name, 'to_warehouse', tw.name, 'created_by_name', cb.name, 'confirmed_by_name', fb.name),
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', p.name, 'qty', l.qty, 'qty_sent', l.qty_sent, 'short_sent', case when l.qty_sent is not null and l.qty_sent < l.qty then l.qty - l.qty_sent end, 'qty_received', l.qty_received, 'qty_lost', l.qty_lost, 'qty_returned', l.qty_returned, 'qty_extra', l.qty_extra, 'pack_factor', l.pack_factor,
                                                              'qty_ea', l.qty * l.pack_factor, 'stock_product_id', coalesce(p.parent_product_id, p.id),
                                                              -- tr-4b(판정 79 · 화면 ⑥ 재료): 이 줄의 자식 레이어(line_ref = 줄 id 또는 줄 id:…)로 따라온 얹힌 원가(kind carried) — 운송 중 · 도착 창고 · 되돌린(출발 창고)
                                                              'carried', (select jsonb_build_object('in_transit', case when (select public.ims_can_view_cost()) then coalesce(sum(ca.amount) filter (where y.warehouse = 'IN_TRANSIT'), 0) end, 'arrived', case when (select public.ims_can_view_cost()) then coalesce(sum(ca.amount) filter (where y.warehouse = tw.name), 0) end,   /* rls-3b(판정 580): 얹힌 원가 금액은 열쇠로 */
                                                                                                    'returned', case when (select public.ims_can_view_cost()) then coalesce(sum(ca.amount) filter (where y.warehouse = fw.name), 0) end, 'total', case when (select public.ims_can_view_cost()) then coalesce(sum(ca.amount), 0) end)
                                                                            from public.inv_layer y join public.inv_layer_cost_add ca on ca.layer_id = y.id and ca.kind = 'carried'
                                                                           where y.origin_type = 'transfer' and y.doc_number = x.transfer_number and (y.line_ref = l.id::text or y.line_ref like l.id::text || ':%'))) order by l.line_no), '[]'::jsonb)
                  from public.inv_transfer_line l join public.product p on p.id = l.product_id where l.transfer_id = x.id),
      'shortage', case when x.status = 'draft' then public.inv_transfer_shortage(x.id) else '[]'::jsonb end,
      -- tr-4(판정 67 · 묶음 일곱 · 화면 ⑥ 재료): 이 트랜스퍼에 배분된 비용 문서 — 문서별 금액(자기 통화) · CAD(기준통화면 ×1 · 아니면 × exchange_rate · 취소 제외) · 레이어에 얹힌 금액(cost_add landed · 배분 줄 단위)
      'freight', (select jsonb_build_object(
                    'total_cad', coalesce(sum(case when c.status <> 'cancelled' then a.amount * case when cu.code is not distinct from k.value then 1 else coalesce(c.exchange_rate, 0) end end), 0),
                    'posted_cad', case when (select public.ims_can_view_cost()) then coalesce(sum(pc.posted), 0) end,   /* rls-3b(판정 580): 레이어에 얹힌 금액은 열쇠로 · total_cad(비용 문서의 돈)는 그대로 */
                    'charges', coalesce(jsonb_agg(jsonb_build_object('charge_id', c.id, 'charge_number', c.charge_number, 'supplier_id', c.supplier_id, 'supplier_name', s.name, 'kind', c.kind, 'status', c.status, 'charge_date', c.charge_date, 'due_date', c.due_date,
                                                                'currency_code', cu.code, 'exchange_rate', c.exchange_rate, 'total_amount', c.total_amount, 'tax_amount', c.tax_amount, 'total_with_tax', c.total_amount + c.tax_amount /* po-tax-2 · 세금 전 · 찍힌 세금 · 낼 돈 */, 'alloc_id', a.id, 'amount', a.amount, 'posted_cad', case when (select public.ims_can_view_cost()) then coalesce(pc.posted, 0) end, 'layers', coalesce(pc.n, 0), 'description', c.description) order by c.charge_date, c.charge_number), '[]'::jsonb))
                  from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id join public.supplier s on s.id = c.supplier_id join public.ref_currency cu on cu.id = c.currency_id
                  left join public.inv_config k on k.key = 'base_currency'
                  left join lateral (select sum(ca.amount) as posted, count(*) as n from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = c.charge_number and ca.line_ref = a.id::text) pc on true
                  where a.transfer_id = x.id))
      from public.inv_transfer x
      join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = x.to_warehouse_id
      left join public.ims_staff cb on cb.id = x.created_by left join public.ims_staff fb on fb.id = x.confirmed_by
     where x.id = p_transfer_id) end;

$function$;

-- ═══ ① 장부 원가 표 다섯 — select 정책을 원가 열쇠로(쓰기는 rls-1 · rls-3a 가 이미 닫았다 · grant 무접촉) ═══
do $$ declare t text; begin
  foreach t in array array['inv_layer', 'inv_layer_cost_add', 'inv_layer_consume', 'inv_cost', 'inv_doc_cost'] loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.ims_can_view_cost()))', t || '_select', t);
    execute format('comment on policy %I on public.%I is %L', t || '_select', t,
      'rls-3b(판정 576 · 580 · 2026-10-21) — 장부 원가는 원가 열쇠(ims_can_view_cost · admin · supervisor 역할로 · 그 외 perms cost 또는 cost:read)가 있는 직원만 읽는다 · 창구(definer)는 정책을 지난다 · 쓰기는 service_role · postgres 만(rls-1 · rls-3a)');
  end loop;
end $$;

-- ═══ ② product_supplier — purchasing · master · cost 중 하나라도 보기 열쇠(행 정책 · 칸 작업 없음 · 쓰기 정책은 원래 없다 — 쓰기는 definer 창구) ═══
drop policy if exists product_supplier_select on public.product_supplier;
create policy product_supplier_select on public.product_supplier for select to authenticated
  using ((select public.ims_can_view('purchasing') or public.ims_can_view('master') or public.ims_can_view_cost()));
comment on policy product_supplier_select on public.product_supplier is 'rls-3b(판정 580 · 2026-10-21) — 공급처 단가 · 공식은 purchasing · master · cost 중 하나라도 보기 열쇠(x 또는 x:read · admin · supervisor 역할로)가 있는 직원만 · 괄호 select 하나(행마다 다시 부르지 않게) · 쓰기는 definer 창구(product_update …)';

-- ═══ ⑤ 뷰 inv_layer_open — 읽는 쪽 0(함수 · IMS 화면 · 옛 WMS 화면 · EF) · security_invoker 없는 뷰라 정책을 지나므로 권한 자체를 회수 ═══
revoke all on public.inv_layer_open from public, anon, authenticated;

-- ═══ ⑥ inv_layer_value — EXECUTE 회수(부르는 쪽은 전부 definer · inv_adjust_eval 은 위 ③ 에서 definer 가 됐다) · 몸 무접촉 ═══
revoke execute on function public.inv_layer_value(bigint) from public, anon, authenticated;

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare
  v_bad  text := '';
  v_n    int;
  v_t    text;
  v_q    text;
  v_tabs text[] := array['inv_layer', 'inv_layer_cost_add', 'inv_layer_consume', 'inv_cost', 'inv_doc_cost'];
begin
  foreach v_t in array v_tabs loop
    select count(*) into v_n from pg_policies where schemaname = 'public' and tablename = v_t and cmd <> 'SELECT';
    if v_n <> 0 then v_bad := v_bad || format(' %s_write_policies_%s', v_t, v_n); end if;
    select count(*), min(qual) into v_n, v_q from pg_policies where schemaname = 'public' and tablename = v_t and cmd = 'SELECT' and roles::text ~ 'authenticated';
    if v_n <> 1 or v_q !~ 'ims_can_view_cost\(\)' then v_bad := v_bad || format(' %s_select_policy_%s(%s)', v_t, v_n, coalesce(v_q, '-')); end if;
    select count(*) into v_n from information_schema.role_table_grants where table_schema = 'public' and table_name = v_t and grantee in ('authenticated', 'anon') and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
    if v_n <> 0 then v_bad := v_bad || format(' %s_auth_write_grants_%s', v_t, v_n); end if;
    select count(*) into v_n from information_schema.role_table_grants where table_schema = 'public' and table_name = v_t and grantee = 'authenticated' and privilege_type = 'SELECT';
    if v_n <> 1 then v_bad := v_bad || format(' %s_auth_select_%s', v_t, v_n); end if;
  end loop;
  select count(*), min(qual) into v_n, v_q from pg_policies where schemaname = 'public' and tablename = 'product_supplier';
  if v_n <> 1 or v_q !~ 'ims_can_view\(''purchasing''' or v_q !~ 'ims_can_view\(''master''' or v_q !~ 'ims_can_view_cost\(\)' then v_bad := v_bad || format(' product_supplier_policies_%s(%s)', v_n, coalesce(v_q, '-')); end if;
  select count(*) into v_n from information_schema.role_table_grants where table_schema = 'public' and table_name = 'product_supplier' and grantee in ('authenticated', 'anon') and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  if v_n <> 0 then v_bad := v_bad || format(' product_supplier_auth_write_grants_%s', v_n); end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.proconfig::text ~ 'search_path=public, pg_temp'
     and p.proname in ('so_stock_short_list', 'so_credit_detail', 'po_fx_cost_lines', 'inv_adjust_eval', 'po_charge_confirm', 'inv_transfer_detail');
  if v_n <> 6 then v_bad := v_bad || format(' definer_%s_of_6', v_n); end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and (
       (p.proname = 'so_stock_short_list' and p.prosrc ~ 'ims_can_view\(''sales''\)' and p.prosrc ~ 'ims_can_view_cost\(\)\) then y\.unit_cost')
    or (p.proname = 'so_credit_detail'    and p.prosrc ~ 'ims_can_view\(''sales''\)' and p.prosrc ~ 'ims_can_view_cost\(\)\) then y\.unit_cost')
    or (p.proname = 'po_fx_cost_lines'    and p.prosrc ~ 'ims_require_ok\(public\.ims_can_view\(''purchasing''\)')
    or (p.proname = 'inv_adjust_eval'     and p.prosrc ~ 'ims_require_ok\(public\.ims_can_adjust_read\(\)' and p.prosrc ~ 'ims_can_view_cost\(\)\) then round\(y\.avg_cost, 6\)')
    or (p.proname = 'po_charge_confirm'   and p.prosrc ~ 'ims_require_write\(''purchasing'', ''saved''\)' and p.prosrc ~ 'landed'' and ca\.doc_number = v_chg\.charge_number' and p.prosrc ~ 'v_cost - ''amount_posted_cad''')
    or (p.proname = 'inv_transfer_detail' and p.prosrc ~ 'ims_can_view\(''transfer''\)' and (length(p.prosrc) - length(replace(p.prosrc, 'ims_can_view_cost()) then coalesce(', ''))) / length('ims_can_view_cost()) then coalesce(') = 6));
  if v_n <> 6 then v_bad := v_bad || format(' gates_and_cases_%s_of_6', v_n); end if;
  if has_table_privilege('authenticated', 'public.inv_layer_open', 'select') or has_table_privilege('anon', 'public.inv_layer_open', 'select') or not has_table_privilege('service_role', 'public.inv_layer_open', 'select') then v_bad := v_bad || ' inv_layer_open_acl'; end if;
  if has_function_privilege('authenticated', 'public.inv_layer_value(bigint)', 'execute') or has_function_privilege('anon', 'public.inv_layer_value(bigint)', 'execute')
     or not has_function_privilege('postgres', 'public.inv_layer_value(bigint)', 'execute') or not has_function_privilege('service_role', 'public.inv_layer_value(bigint)', 'execute') then v_bad := v_bad || ' inv_layer_value_acl'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_layer_value' and p.prosecdef and md5(p.prosrc) = '2d4a569c9caaa4f9cecb5187625cf447';
  if v_n <> 1 then v_bad := v_bad || ' inv_layer_value_body_changed'; end if;
  if has_function_privilege('anon', 'public.ims_require_ok(boolean, text)', 'execute') then v_bad := v_bad || ' ims_require_ok_anon'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and not p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute')
     and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ '\m(inv_layer_open|inv_layer_value|inv_layer_cost_add|inv_layer_consume|inv_layer|inv_cost|inv_doc_cost)\M';
  if v_n <> 0 then v_bad := v_bad || format(' invoker_cost_readers_callable_%s', v_n); end if;
  select count(*) into v_n from (
    select md5(string_agg(k, ',' order by k)) as untouched from (
      select 'pol:' || tablename || ':' || policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-') as k
        from pg_policies where schemaname = 'public' and (tablename like 'wms\_%' or tablename in ('inv_ledger', 'inv_config', 'inv_snapshot', 'inv_sync_state', 'inv_sku_types', 'inv_doc_state', 'inv_voided_docs', 'inv_missing_docs', 'inv_missing_lines', 'inv_conflicts', 'inv_collect_runs', 'inv_snapshot_runs', 'inv_compare', 'inv_compare_runs', 'inv_balance_diffs', 'inv_bin_notes'))
      union all
      select 'grant:' || table_name || ':' || grantee || ':' || privilege_type
        from information_schema.role_table_grants where table_schema = 'public' and (table_name like 'wms\_%' or table_name like 'inv\_%' or table_name = 'product_supplier') and table_name <> 'inv_layer_open'
      union all
      select 'fn:' || p.proname || ':' || coalesce(p.proacl::text, '-')
        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_carry', 'inv_layer_cost_add_settle', 'inv_snap_balance_diffs', 'inv_compare_run', 'inv_ack_diff', 'tf_charge_confirm', 'tf_charge_update', 'tf_charge_delete', 'tf_charge_alloc_add', 'tf_charge_alloc_update', 'tf_charge_alloc_delete')
    ) s) a join rls3b_before b on b.untouched = a.untouched;
  if v_n <> 1 then v_bad := v_bad || ' untouched_set_changed(wms_18 · inv_ledger · inv_config · rls_3a_16 · grants · rls_3a_fn_acls)'; end if;
  if v_bad <> '' then raise exception 'rls-3b landing check failed:%', v_bad; end if;
end $$;
drop table rls3b_before;
