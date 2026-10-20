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

-- ═══ po-cn-1 — 크레딧 노트 줄의 「크레딧 뒤 남은 차이」(판정 554 · 2026-10-20 · 동료 코멘트 CN-PO-02052 QTY DIFF −68) ═══
--   po_invoice_detail 재발행 — 원본 20261009023028_po_disc_5a.sql:745 바이트 + 3 줄: lines[] 에 열쇠 셋(크레딧 goods 줄에만 · 그 밖 null) · qty_diff 는 바이트 그대로(인보이스 「청구 − 받음」)
--     qty_diff_after_credits    = credit_billed_qty − received_qty − credited_not_received_qty   (0 아래로 안 깎는다 — 두 번째 크레딧이 −1 로 드러난다)
--     credit_billed_qty         = 그 PO 줄의 확정 인보이스 goods 수량 합
--     credited_not_received_qty = 그 PO 줄의 credit_reason = 'not_received' 크레딧 goods 수량 합(확정 + 이 문서(draft 여도) · 취소 제외 · 다른 draft 제외 · 이 줄 포함)
--   판정 554 의 뜻(이견 2 · Caleb 동의): 「확정 크레딧 goods 수량 합」은 not_received 줄만이다 — 값 차이(price_difference) 크레딧은 온 물건의 값이라 수량을 바꾸지 않고, reason 이 없는 줄은 세지 않는다(credit_reason_missing 경고가 가리킨다)
--   식은 po_credit_reason_suggest 한 집(po-disc-5a) — detail 이 p_exclude_line_id = null 로 한 번 더 부른다 · 받은 수량은 셋 다 po_receipt_line 합(rcv-1b 먼저 반영 묶음 줄도 입고 줄이라 저절로 든다)
--   무접촉: po_invoice_create(no_qty_difference 는 자기 식) · po_credit_reason_suggest · 뷰 0 · 화면 invoices.html(대화 Claude 가 새 열쇠를 그린다) · ACL(create or replace 는 ACL 을 지킨다)
create or replace function public.po_invoice_detail(p_invoice_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with i as (
  select * from public.po_invoice where id = p_invoice_id
),
m as (
  select * from public.po_invoice_money where id = p_invoice_id
),
lines as (
  select il.*,
         pl.po_id, x.po_number, pl.line_no as po_line_no, pl.qty_ea as po_qty_ea, pl.unit_price as po_unit_price,
         pr.sku, pr.name as product_name, up.sku as entered_unit_sku,
         sg.suggested as credit_reason_suggested, sg.not_received_left as credit_not_received_left, sg.spans_both as credit_spans_both,   -- po-disc-5a · 크레딧 goods 줄만(아니면 null)
         sa.billed_qty as credit_billed_qty, sa.credited_not_received_qty, sa.billed_qty - sa.received_qty - sa.credited_not_received_qty as qty_diff_after_credits,   -- po-cn-1(판정 554): 크레딧 뒤 남은 차이 = 확정 인보이스 goods − 입고 − not_received 크레딧(확정 + 이 문서 · 이 줄 포함) · 0 아래로 안 깎는다(과한 크레딧이 드러난다)
         round(il.qty_ea * il.unit_price, 2) as amount,
         tr.name as tax_rule_effective, tr.rate_pct,                                                     -- po-tax-1 · coalesce(줄, 머리)
         public.so_tax_amount(round(il.qty_ea * il.unit_price, 2), tr.rate_pct) as tax_amount,          -- po-tax-1 · 줄 세금(할인 줄은 묶음에서 뺀다 · money.tax_groups)
         case when il.po_line_id is not null
              then coalesce((select sum(rl.qty_ea) from public.po_receipt_line rl where rl.po_line_id = il.po_line_id), 0) end as received_qty,
         case when il.po_line_id is not null
              then coalesce((select sum(x2.qty_ea) from public.po_invoice_line x2 join public.po_invoice i2 on i2.id = x2.po_invoice_id
                              where x2.po_line_id = il.po_line_id and x2.line_kind = 'goods' and i2.doc_kind = 'invoice' and i2.status <> 'cancelled'
                                and i2.id <> p_invoice_id), 0) end as other_invoiced_qty
  from public.po_invoice_line il
  left join public.po_line pl on pl.id = il.po_line_id
  left join public.po x on x.id = pl.po_id
  left join public.product pr on pr.id = pl.product_id
  left join public.product up on up.id = il.entered_unit_product_id
  left join public.ref_tax_rule tr on tr.id = coalesce(il.tax_rule_id, (select tax_rule_id from i))
  left join lateral (select s.* from public.po_credit_reason_suggest(p_invoice_id, il.po_line_id, il.qty_ea, il.id) s where il.line_kind = 'goods' and (select doc_kind from i) = 'credit') sg on true   -- po-disc-5a
  left join lateral (select s.* from public.po_credit_reason_suggest(p_invoice_id, il.po_line_id, il.qty_ea, null) s where il.line_kind = 'goods' and il.po_line_id is not null and (select doc_kind from i) = 'credit') sa on true   -- po-cn-1: 같은 식 한 집 · 이 줄을 빼지 않는다(p_exclude_line_id null)
  where il.po_invoice_id = p_invoice_id
),
shares as (
  select l.po_id, l.po_number, x.status as po_status, count(*)::int as line_count,
         coalesce(sum(l.qty_ea) filter (where l.line_kind = 'goods'), 0) as qty_ea,
         coalesce(sum(l.amount), 0) as amount
  from lines l join public.po x on x.id = l.po_id
  where l.po_id is not null
  group by l.po_id, l.po_number, x.status
),
cred as (
  select c.id, c.invoice_number, c.invoice_date, c.status, c.total_amount, c.supplier_ref_number, cm.payable_net as credit_net, cm.alloc_total as used
  from public.po_invoice c join public.po_invoice_money cm on cm.id = c.id
  where c.credit_for_invoice_id = p_invoice_id
),
pay as (
  select pa.id as alloc_id, pa.amount as alloc_amount, pm.id as payment_id, pm.paid_on, pm.reference, pm.amount as payment_amount, pm.discount_taken,
         cur.code as currency_code, acc.code as account_code, acc.name as account_name, st.name as paid_by_name
  from public.po_payment_alloc pa
  join public.po_payment pm on pm.id = pa.po_payment_id
  join public.ref_currency cur on cur.id = pm.currency_id
  left join public.ref_account acc on acc.id = pm.account_id
  left join public.ims_staff st on st.id = pm.paid_by
  where pa.po_invoice_id = p_invoice_id
)
select case when not exists (select 1 from i) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', i.id, 'doc_kind', i.doc_kind, 'invoice_number', i.invoice_number, 'invoice_date', i.invoice_date, 'due_date', i.due_date, 'status', i.status,
      'supplier_ref_number', i.supplier_ref_number,                                          -- ⭐ 새 · 공급처가 보내온 크레딧 노트 번호(참조) · PostgREST 로 고친다
      'credit_po_id', i.credit_po_id, 'credit_po_number', cp.po_number,                     -- ⭐ 새 · 번호를 낸 발주
      'supplier_id', i.supplier_id, 'supplier_name', s.name,
      'currency_id', i.currency_id, 'currency_code', cur.code, 'exchange_rate', i.exchange_rate,
      'payment_term_id', i.payment_term_id, 'payment_term_name', coalesce(i.payment_term_name, pt.name),
      'total_amount', i.total_amount,
      'tax_rule_id', i.tax_rule_id, 'tax_rule', i.tax_rule, 'rate_pct', m.rate_pct,          -- po-tax-1 · 머리 규칙(초안에서 PostgREST 로 이름을 고친다)
      'credit_for_invoice_id', i.credit_for_invoice_id, 'credit_for_number', f.invoice_number, 'credit_for_status', f.status,
      'created_by_name', cb.name, 'confirmed_by_name', fb.name,
      'confirmed_at', i.confirmed_at, 'cancelled_at', i.cancelled_at, 'note', i.note, 'created_at', i.created_at, 'updated_at', i.updated_at)
    from i
    cross join m
    join public.supplier s on s.id = i.supplier_id
    join public.ref_currency cur on cur.id = i.currency_id
    left join public.ref_payment_term pt on pt.id = i.payment_term_id
    left join public.po_invoice f on f.id = i.credit_for_invoice_id
    left join public.po cp on cp.id = i.credit_po_id
    left join public.ims_staff cb on cb.id = i.created_by
    left join public.ims_staff fb on fb.id = i.confirmed_by
  ),
  'money', (
    select jsonb_build_object(
      'line_count', m.line_count, 'goods_sum', m.goods_sum, 'other_sum', m.other_sum, 'goods_payable', m.goods_payable, 'other_payable', m.other_payable,
      'discount_factor', round(m.factor, 6),
      'computed_total', m.computed_total, 'diff', m.diff,
      'payable_net', m.payable_net,
      'alloc_total', m.alloc_total,
      'credit_total', m.credit_total, 'unpaid', m.unpaid, 'remaining', m.remaining,
      -- ── po-tax-1 · 세금(문서 통화 · 규칙 모르면 null + 경고 tax_rule_missing) ──
      'taxable_amount', m.taxable_amount, 'tax_amount', m.tax_amount,
      'payable_taxable', m.payable_taxable, 'payable_tax', m.payable_tax,
      'tax_rule_groups', m.tax_rule_groups,
      'tax_groups', coalesce((select jsonb_agg(jsonb_build_object('tax_rule_id', g.tax_rule_id, 'tax_rule', g.tax_rule, 'rate_pct', g.rate_pct, 'line_count', g.line_count,
                                                                  'taxable_amount', g.taxable_amount, 'discount_amount', g.discount_amount, 'lines_tax', g.lines_tax,
                                                                  'discount_tax', g.discount_tax, 'tax_amount', g.tax_amount, 'payable_taxable', g.payable_taxable, 'payable_tax', g.payable_tax)
                                               order by g.tax_rule nulls last)
                               from public.po_tax_group g where g.doc_kind = 'invoice' and g.doc_id = p_invoice_id), '[]'::jsonb))
    from m
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'line_no', line_no, 'line_kind', line_kind, 'po_line_id', po_line_id, 'po_id', po_id, 'po_number', po_number, 'po_line_no', po_line_no,
      'sku', sku, 'product_name', product_name, 'description', description,
      'qty_ea', qty_ea, 'entered_unit_sku', entered_unit_sku, 'entered_unit_product_id', entered_unit_product_id, 'entered_qty', entered_qty, 'entered_pack_factor', entered_pack_factor,
      'unit_price', unit_price, 'amount', amount, 'is_payable', is_payable, 'note', note,
      'tax_rule_id', tax_rule_id, 'tax_rule', tax_rule, 'tax_rule_effective', tax_rule_effective, 'rate_pct', rate_pct, 'tax_amount', tax_amount,   -- po-tax-1 · 줄 규칙(null = 머리) · 적용 규칙 · 줄 세금
      'po_qty_ea', po_qty_ea, 'po_unit_price', po_unit_price,
      'received_qty', received_qty, 'other_invoiced_qty', other_invoiced_qty,
      'qty_diff', case when line_kind = 'goods' then qty_ea - received_qty end,
      'credit_reason', credit_reason, 'credit_reason_suggested', credit_reason_suggested, 'credit_not_received_left', credit_not_received_left, 'credit_spans_both', credit_spans_both,   -- po-disc-5a
      'qty_diff_after_credits', qty_diff_after_credits, 'credited_not_received_qty', credited_not_received_qty, 'credit_billed_qty', credit_billed_qty)   -- po-cn-1(판정 554) · 크레딧 goods 줄에만 · 그 밖 null · qty_diff 는 그대로(인보이스 뜻)
      order by line_no)
    from lines), '[]'::jsonb),
  'discounts', coalesce((
    select jsonb_agg(jsonb_build_object('id', d.id, 'seq', d.seq, 'name', d.name, 'percent', d.percent, 'supplier_discount_id', d.supplier_discount_id, 'note', d.note) order by d.seq)
    from public.po_invoice_discount d where d.po_invoice_id = p_invoice_id), '[]'::jsonb),
  'po_shares', coalesce((
    select jsonb_agg(jsonb_build_object('po_id', po_id, 'po_number', po_number, 'po_status', po_status, 'line_count', line_count, 'qty_ea', qty_ea, 'amount', amount) order by po_number)
    from shares), '[]'::jsonb),
  'credits', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'credit_number', invoice_number, 'credit_date', invoice_date, 'status', status, 'total_amount', total_amount,
                                        'supplier_ref_number', supplier_ref_number,                                   -- ⭐ 새
                                        'credit_net', credit_net, 'used', used)
      order by invoice_date, invoice_number)
    from cred), '[]'::jsonb),
  'payments', coalesce((
    select jsonb_agg(jsonb_build_object('alloc_id', alloc_id, 'payment_id', payment_id, 'paid_on', paid_on, 'reference', reference, 'alloc_amount', alloc_amount,
                                        'payment_amount', payment_amount, 'discount_taken', discount_taken, 'currency_code', currency_code,
                                        'account_code', account_code, 'account_name', account_name, 'paid_by_name', paid_by_name)
      order by paid_on, reference)
    from pay), '[]'::jsonb),
  'credit_cost_events', coalesce((                                                                                      -- po-disc-5a · 이 크레딧의 원가 사건(되돌림 포함)
    select jsonb_agg(jsonb_build_object('id', j.id, 'line_no', cl.line_no, 'po_line_id', j.po_line_id, 'amount_doc', j.amount_doc, 'amount_cad', j.amount_cad, 'status', j.status, 'posted_on', j.posted_on, 'reverses_id', j.reverses_id, 'source_type', j.source_type) order by cl.line_no, j.created_at)
    from public.inv_cost_adjust j join public.po_invoice_line cl on cl.id = coalesce((select o.source_id from public.inv_cost_adjust o where o.id = j.reverses_id), j.source_id)
    where cl.po_invoice_id = p_invoice_id and (j.source_type = 'po_credit' or exists (select 1 from public.inv_cost_adjust o where o.id = j.reverses_id and o.source_type = 'po_credit'))), '[]'::jsonb),
  'warnings', (
    select coalesce(jsonb_agg(w), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when i.doc_kind = 'credit' and i.credit_for_invoice_id is not null and m.alloc_total > 0 then 'attached_and_used' end,
        case when f.doc_kind = 'credit' then 'credit_for_is_credit' end,
        case when f.supplier_id is not null and f.supplier_id <> i.supplier_id then 'credit_for_other_supplier' end,
        case when i.total_amount = 0 then 'total_amount_zero' end,
        case when m.diff <> 0 then 'total_differs_from_lines' end,
        case when m.line_count = 0 then 'no_lines' end,
        case when m.tax_rule_missing then 'tax_rule_missing' end,                                -- po-tax-1 · 규칙 모르는 줄이 있다(세금 0 으로 더했다)
        case when i.doc_kind = 'credit' and i.status = 'draft' and exists (select 1 from lines l where l.line_kind = 'goods' and l.credit_reason is null) then 'credit_reason_missing' end,   -- po-disc-5a
        case when i.doc_kind = 'credit' and exists (select 1 from lines l where l.credit_spans_both) then 'credit_line_spans_both' end
      ], null)) as w
      from i cross join m left join public.po_invoice f on f.id = i.credit_for_invoice_id) t
  )
) end;
$$;
comment on function public.po_invoice_detail(uuid) is 'po-cn-1(판정 554 · 2026-10-20) — lines[] 에 크레딧 goods 줄의 「크레딧 뒤 남은 차이」 셋: qty_diff_after_credits = credit_billed_qty(확정 인보이스 goods 합) − received_qty(입고 줄 합) − credited_not_received_qty(credit_reason = not_received 크레딧 goods 합 · 확정 + 이 문서 · 취소 제외 · 이 줄 포함) · 0 아래로 안 깎음 · 판정 554 의 「확정 크레딧 goods 수량 합」은 not_received 줄만(값 차이 크레딧은 수량을 바꾸지 않는다 · reason 없는 줄은 안 센다) · 식은 po_credit_reason_suggest 한 집 · qty_diff(인보이스 「청구 − 받음」)는 그대로 · 인보이스 줄 · 그 밖의 줄은 셋 다 null';

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_src text; v_bad text := '';
begin
  select prosrc into v_src from pg_proc where oid = 'public.po_invoice_detail(uuid)'::regprocedure;
  if v_src !~ 'qty_diff_after_credits' or v_src !~ 'credited_not_received_qty' or v_src !~ 'credit_billed_qty' then v_bad := v_bad || ' keys_missing'; end if;
  if v_src !~ 'po_credit_reason_suggest\(p_invoice_id, il\.po_line_id, il\.qty_ea, null\)' then v_bad := v_bad || ' no_unexcluded_call'; end if;
  if v_src !~ '''qty_diff'', case when line_kind = ''goods'' then qty_ea - received_qty end' then v_bad := v_bad || ' qty_diff_changed'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'po_invoice_detail') <> 1 then v_bad := v_bad || ' overloads'; end if;
  if coalesce((select proacl::text from pg_proc where oid = 'public.po_invoice_detail(uuid)'::regprocedure), '') !~ 'authenticated' then v_bad := v_bad || ' acl'; end if;
  if v_bad <> '' then raise exception 'po-cn-1 landing check failed:%', v_bad; end if;
end $$;
