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
-- 20261019172034_doc_1c_zero_blank_due_now.sql — doc-1c (2026-10-19 · 회사 PC · Fable · 문서 값: 0 이면 빈칸 · Due = 지금 남은 금액 · net 단가가 같으면 빈칸)
--   판정 526(Notes = so_invoice.note — 이미 그렇다 · 바꿀 것 없음) · 527(Unit price = list_price — 판이 찍는다 · 창구 무접촉) · 528 ① ~ ④(Caleb 2026-10-19 · 화면 시험 60009 Clore)
--   ① doc_fmt_money_nz — 0 · null 이면 "" (Total · Tax · 줄 금액에는 안 쓴다 — 0 이어도 찍는다)
--   ② doc_unit_prices 재발행(원본 20261019152102:199 + 한 줄) — both 에서 오더 할인 0 · 없음이면 net_unit_price ""(④)
--   ③ doc_data_invoice 재발행(원본 20261019155731:628 + 한 줄) — 중립 totals 에 remaining(so_invoice_remaining · 찍는 순간)
--   ④ doc_data_invoice_fmt 재발행(원본 20261019155731:574 + 바뀐 줄 넷) — due = remaining(없으면 amount_due · ship_ready) · 0 이면 due_amount · due_label 둘 다 "" · 음수 Credit · 양수 Due · deposit · credit · balance_forward · paid 0 이면 ""(③)
--   ⑤ doc_data_so 재발행(원본 20261019152102:344 + 한 줄) — prepaid 0 이면 "" · due_amount 는 늘 · 크레딧(doc_data_credit)은 그대로(이견)
--   자리표 목록(doc_field_catalog) 무접촉 — 열쇠 그대로 · 값만 "" · 검증 ~/asung/prompts/doc-1c-verify.sql + doc-1b1 · doc-1b2 검증 다시(바뀐 기대만)

-- ═══ ① 0 이면 빈칸 ═══
create function public.doc_fmt_money_nz(p numeric) returns text
  language sql immutable parallel safe
  set search_path = public, pg_temp
as $$ select case when p is null or round(p, 2) = 0 then '' else public.doc_fmt_money(p) end; $$;
comment on function public.doc_fmt_money_nz(numeric) is 'doc-1c 판정 528 ② ③ — 돈 글자인데 0 · null 이면 ""(판이 {{#x}} 로 그 줄을 숨긴다) · 쓰는 자리 = due_amount · deposit_applied · credit_applied · balance_forward · paid · SO prepaid 만 · Total · Tax · 줄 금액은 doc_fmt_money(0 도 찍는다)';
revoke all on function public.doc_fmt_money_nz(numeric) from public, anon;
grant execute on function public.doc_fmt_money_nz(numeric) to authenticated, service_role;

-- ═══ ② doc_unit_prices 재발행 — 원본 20261019152102_doc_1b1_data.sql:199 바이트 + 한 줄 ═══
create or replace function public.doc_unit_prices(p_unit numeric, p_od_pct numeric, p_display text) returns jsonb
  language sql immutable parallel safe
  set search_path = public, pg_temp
as $$
  select case when p_unit is null then '{"unit_price": "", "net_unit_price": ""}'::jsonb
              when p_display = 'net' then jsonb_build_object('unit_price', public.doc_fmt_money(p_unit * (1 - coalesce(p_od_pct, 0) / 100)), 'net_unit_price', '')
              when p_display = 'discounted' then jsonb_build_object('unit_price', public.doc_fmt_money(p_unit), 'net_unit_price', '')
              else jsonb_build_object('unit_price', public.doc_fmt_money(p_unit), 'net_unit_price', case when coalesce(p_od_pct, 0) = 0 then '' else public.doc_fmt_money(p_unit * (1 - p_od_pct / 100)) end) end;   -- doc-1c 판정 528 ④: 오더 할인이 없으면 net 은 단가와 같다 → 빈칸(판이 칸을 숨긴다)
$$;

-- ═══ ③ doc_data_invoice 재발행 — 원본 20261019155731_doc_1b2_ship_ready.sql:628 바이트 + remaining 한 줄 ═══
create or replace function public.doc_data_invoice(p_kind text, p_invoice_id uuid, p_cfg jsonb) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_inv public.so_invoice%rowtype;
  v_n   jsonb;
begin
  select * into v_inv from public.so_invoice i where i.id = p_invoice_id;
  if v_inv.id is null then raise exception 'Invoice not found'; end if;
  v_n := jsonb_build_object(
    'header', jsonb_build_object('number', v_inv.invoice_number, 'issued_on', v_inv.issued_on, 'due_on', v_inv.due_on, 'payment_term_name', v_inv.payment_term_name, 'currency_code', v_inv.currency_code, 'memo', v_inv.note,
                                 'bill_to_customer_id', v_inv.bill_to_customer_id,
                                 'bill_to', jsonb_build_object('name', v_inv.bill_to_name, 'line1', v_inv.bill_to_line1, 'line2', v_inv.bill_to_line2, 'city', v_inv.bill_to_city, 'state_province', v_inv.bill_to_state_province, 'postal_code', v_inv.bill_to_postal_code, 'country', v_inv.bill_to_country)),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object(
                 'so_number', o.so_number, 'reference', s.ref, 'carrier', s.carrier, 'tracking', s.tracking_number, 'tax_rule', o.tax_rule, 'order_discount_pct', o.order_discount_pct,
                 'ship_to', jsonb_build_object('company', o.ship_to_company, 'contact', o.ship_to_contact, 'phone', o.ship_to_phone, 'line1', o.ship_to_line1, 'line2', o.ship_to_line2, 'city', o.ship_to_city, 'state_province', o.ship_to_state_province, 'postal_code', o.ship_to_postal_code, 'country', o.ship_to_country),
                 'lines', (select coalesce(jsonb_agg(jsonb_build_object('product_id', sl.product_id, 'sku', l.sku, 'description', l.description, 'comment', sl.comments, 'unit', l.unit, 'qty', l.qty, 'list_price', l.list_price, 'discount_pct', l.discount_pct,
                                                                        'unit_price', l.unit_price, 'amount', l.amount, 'tax_amount', l.tax_amount, 'is_free', sl.free_reason is not null, 'no_price', l.unit_price is null) order by l.line_no), '[]'::jsonb)
                           from public.so_invoice_line l left join public.so_line sl on sl.id = l.so_line_id where l.invoice_order_id = o.id and l.kind = 'product')) order by o.so_number), '[]'::jsonb)
               from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id),
    'charges', (select coalesce(jsonb_agg(jsonb_build_object('so_number', o.so_number, 'kind', l.kind, 'account_code', l.account_code, 'description', l.description, 'comment', case when l.kind = 'charge' then c.description end,
                                                             'qty', l.qty, 'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'amount', l.amount, 'tax_amount', l.tax_amount) order by o.so_number, l.line_no), '[]'::jsonb)
                from public.so_invoice_line l join public.so_invoice_order o on o.id = l.invoice_order_id left join public.so_charge c on c.id = l.so_charge_id
                where l.invoice_id = v_inv.id and l.kind <> 'product'),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('reference', p.reference, 'paid_on', p.paid_on, 'method', p.method, 'amount', a.amount) order by p.paid_on, p.created_at, a.created_at), '[]'::jsonb)
                 from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
                 where a.invoice_id = v_inv.id and a.voided_at is null and p.status = 'active' and p.kind = 'payment'),
    'totals', jsonb_build_object('order_discount', v_inv.order_discount_amount, 'surcharge', v_inv.surcharge_amount, 'taxable', v_inv.taxable_amount, 'tax', v_inv.tax_amount, 'total', v_inv.total,
                                 'deposit_applied', v_inv.deposit_applied, 'credit_applied', v_inv.credit_applied, 'balance_forward', v_inv.balance_forward,
                                 'paid', (select coalesce(sum(a.amount), 0) from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id where a.invoice_id = v_inv.id and a.voided_at is null and p.status = 'active' and p.kind = 'payment'),
                                 'amount_due', v_inv.amount_due,
                                 'remaining', public.so_invoice_remaining(v_inv.id)));                                                                                     -- doc-1c 판정 528 ①: 찍는 순간 지금 남은 금액(발행 때 종이 값 amount_due 는 doc-2 의 남긴 PDF 가 지킨다)
  return public.doc_data_invoice_fmt(p_kind, p_cfg, v_n);
end;
$$;

-- ═══ ④ doc_data_invoice_fmt 재발행 — 원본 20261019155731_doc_1b2_ship_ready.sql:574 바이트 + 바뀐 줄 넷 ═══
create or replace function public.doc_data_invoice_fmt(p_kind text, p_cfg jsonb, p_n jsonb) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_fmt  text := p_cfg->>'date_format';
  v_disp text := coalesce(p_cfg->>'unit_display', 'both');
  v_h    jsonb := p_n->'header';  v_t jsonb := p_n->'totals';
  v_orders jsonb;  v_charges jsonb;  v_payments jsonb;  v_inv jsonb;
  v_lines_amt numeric;  v_lines_tax numeric;  v_qty numeric;  v_chg_amt numeric;  v_chg_tax numeric;  v_chd numeric;
  v_due  numeric := coalesce((v_t->>'remaining')::numeric, (v_t->>'amount_due')::numeric);                                      -- doc-1c 판정 528 ①: 표에서 온 문서는 지금 남은 금액 · ship_ready(미리 보기)는 셈한 남을 몫
begin
  -- 제품 줄 — 오더 순(orders 배열 순 = so_number 순) · 줄 번호는 문서 안에서 1, 2, 3 … 이어서
  with ln as (
    select o.ord as o_ord, l.ord as l_ord, o.o->>'order_discount_pct' as od_pct, l.l, row_number() over (order by o.ord, l.ord) as no
    from jsonb_array_elements(p_n->'orders') with ordinality o(o, ord) cross join lateral jsonb_array_elements(o.o->'lines') with ordinality l(l, ord))
  select coalesce(jsonb_agg(jsonb_build_object(
           'so_number', coalesce(o.o->>'so_number', ''), 'reference', coalesce(o.o->>'reference', ''), 'carrier', coalesce(o.o->>'carrier', ''), 'tracking', coalesce(o.o->>'tracking', ''), 'tax_rule', coalesce(o.o->>'tax_rule', ''),
           'ship_to', (select jsonb_object_agg(k, coalesce(o.o->'ship_to'->>k, '')) from unnest(array['company', 'contact', 'phone', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country']) k),
           'lines', (select coalesce(jsonb_agg((jsonb_build_object('no', ln.no::text, 'upc', public.doc_upc(nullif(ln.l->>'product_id', '')::uuid), 'sku', coalesce(ln.l->>'sku', ''), 'description', coalesce(ln.l->>'description', ''), 'comment', coalesce(ln.l->>'comment', ''),
                                                                    'unit', coalesce(ln.l->>'unit', ''), 'qty', public.doc_fmt_qty((ln.l->>'qty')::numeric), 'list_price', public.doc_fmt_money((ln.l->>'list_price')::numeric), 'discount_pct', public.doc_fmt_pct((ln.l->>'discount_pct')::numeric),
                                                                    'amount', public.doc_fmt_money((ln.l->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((ln.l->>'tax_amount')::numeric), 'is_free', coalesce((ln.l->>'is_free')::boolean, false), 'no_price', coalesce((ln.l->>'no_price')::boolean, false))
                                                || public.doc_unit_prices((ln.l->>'unit_price')::numeric, (ln.od_pct)::numeric, v_disp)) order by ln.no), '[]'::jsonb)
                     from ln where ln.o_ord = o.ord)) order by o.ord), '[]'::jsonb),
         coalesce((select sum((ln.l->>'amount')::numeric) from ln), 0), coalesce((select sum((ln.l->>'tax_amount')::numeric) from ln), 0), coalesce((select sum((ln.l->>'qty')::numeric) from ln), 0)
    into v_orders, v_lines_amt, v_lines_tax, v_qty
  from jsonb_array_elements(p_n->'orders') with ordinality o(o, ord);
  select coalesce(jsonb_agg(jsonb_build_object('no', c.ord::text, 'so_number', coalesce(c.c->>'so_number', ''), 'code', coalesce(c.c->>'account_code', ''), 'description', coalesce(c.c->>'description', ''), 'comment', coalesce(c.c->>'comment', ''),
                                               'qty', public.doc_fmt_qty((c.c->>'qty')::numeric), 'unit_price', public.doc_fmt_money((c.c->>'unit_price')::numeric), 'discount_pct', public.doc_fmt_pct((c.c->>'discount_pct')::numeric),
                                               'amount', public.doc_fmt_money((c.c->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((c.c->>'tax_amount')::numeric)) order by c.ord), '[]'::jsonb),
         coalesce(sum((c.c->>'amount')::numeric), 0), coalesce(sum((c.c->>'tax_amount')::numeric), 0), coalesce(sum((c.c->>'amount')::numeric) filter (where c.c->>'kind' = 'charge_discount'), 0)
    into v_charges, v_chg_amt, v_chg_tax, v_chd
  from jsonb_array_elements(p_n->'charges') with ordinality c(c, ord);
  select coalesce(jsonb_agg(jsonb_build_object('no', p.ord::text, 'reference', coalesce(p.p->>'reference', ''), 'date', public.doc_fmt_date((p.p->>'paid_on')::date, v_fmt), 'method', public.doc_method_label(p.p->>'method'), 'amount', public.doc_fmt_money((p.p->>'amount')::numeric)) order by p.ord), '[]'::jsonb)
    into v_payments from jsonb_array_elements(p_n->'payments') with ordinality p(p, ord);
  v_inv := jsonb_build_object('number', coalesce(v_h->>'number', ''), 'date', public.doc_fmt_date((v_h->>'issued_on')::date, v_fmt), 'due_date', public.doc_fmt_date((v_h->>'due_on')::date, v_fmt), 'terms', coalesce(v_h->>'payment_term_name', ''),
                              'currency', coalesce(v_h->>'currency_code', ''), 'memo', coalesce(v_h->>'memo', ''), 'total_qty', public.doc_fmt_qty(v_qty));
  if p_kind = 'ship_ready' then
    v_inv := (v_inv - 'number') || jsonb_build_object('calc_at', public.doc_fmt_date(public.ims_today(), v_fmt) || ' ' || to_char(coalesce((p_n->>'calc_at')::timestamptz, now()) at time zone 'America/Toronto', 'HH24:MI'));
  end if;
  return jsonb_build_object(
    'invoice', v_inv, 'orders', v_orders, 'charges', v_charges, 'payments', v_payments,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money(v_lines_amt), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money(v_lines_amt + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'order_discount', public.doc_fmt_money((v_t->>'order_discount')::numeric), 'surcharge', public.doc_fmt_money((v_t->>'surcharge')::numeric), 'charges_discount', public.doc_fmt_money(v_chd),
                                 'before_tax', public.doc_fmt_money((v_t->>'taxable')::numeric), 'tax', public.doc_fmt_money((v_t->>'tax')::numeric), 'total', public.doc_fmt_money((v_t->>'total')::numeric),
                                 'deposit_applied', public.doc_fmt_money_nz((v_t->>'deposit_applied')::numeric), 'credit_applied', public.doc_fmt_money_nz((v_t->>'credit_applied')::numeric), 'balance_forward', public.doc_fmt_money_nz((v_t->>'balance_forward')::numeric),   -- doc-1c 판정 528 ③: 0 이면 빈칸
                                 'paid', public.doc_fmt_money_nz((v_t->>'paid')::numeric), 'due_label', case when v_due > 0 then 'Due' when v_due < 0 then 'Credit' else '' end, 'due_amount', public.doc_fmt_money_nz(v_due)))   -- doc-1c 판정 528 ②: 남은 돈 0 이면 둘 다 빈칸(판이 {{#totals.due_amount}} 로 숨긴다)
    || public.doc_data_common(p_kind, p_cfg, (v_h->'bill_to') || public.doc_contact(nullif(v_h->>'bill_to_customer_id', '')::uuid));
end;
$$;

-- ═══ ⑤ doc_data_so 재발행 — 원본 20261019152102_doc_1b1_data.sql:344 바이트 + 한 줄 ═══
create or replace function public.doc_data_so(p_so_id uuid, p_cfg jsonb) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_so   public.so%rowtype;
  v_pf   jsonb;  v_o jsonb;  v_t jsonb;
  v_fmt  text := p_cfg->>'date_format';
  v_disp text := coalesce(p_cfg->>'unit_display', 'both');
  v_lines jsonb;  v_charges jsonb := '[]'::jsonb;  v_prepay jsonb;
  v_lines_tax numeric;  v_n int := 0;  v_x jsonb;  v_sc_code text := (select c.value from public.inv_config c where c.key = 'so_surcharge_account_code');
  v_chg_amt numeric;  v_chg_tax numeric;
begin
  select * into v_so from public.so s where s.id = p_so_id;
  if v_so.id is null then raise exception 'Order not found'; end if;
  v_pf := public.so_proforma(array[p_so_id]);
  v_o := v_pf->'orders'->0;  v_t := v_pf->'totals';
  select coalesce(jsonb_agg((jsonb_build_object('no', x.no::text, 'upc', public.doc_upc(sl.product_id), 'sku', coalesce(x.l->>'sku', ''), 'description', coalesce(x.l->>'product_name', ''), 'comment', coalesce(sl.comments, ''),
                                                'unit', coalesce(x.l->>'unit', ''), 'qty', public.doc_fmt_qty((x.l->>'qty')::numeric), 'list_price', public.doc_fmt_money((x.l->>'list_price')::numeric), 'discount_pct', public.doc_fmt_pct((x.l->>'discount_pct')::numeric),
                                                'amount', public.doc_fmt_money((x.l->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((x.l->>'tax')::numeric), 'is_free', sl.free_reason is not null, 'no_price', sl.unit_price is null)
                             || public.doc_unit_prices(sl.unit_price, v_so.order_discount_pct, v_disp)) order by x.no), '[]'::jsonb),
         coalesce(sum((x.l->>'tax')::numeric), 0)
    into v_lines, v_lines_tax
  from (select l, row_number() over (order by (l->>'line_no')::int) as no from jsonb_array_elements(coalesce(v_o->'lines', '[]'::jsonb)) l) x
  left join public.so_line sl on sl.id = (x.l->>'line_id')::uuid;
  -- charges = 운임(정가) · 운임 할인(음수) · 오더 할인(음수) · 줄 부가 요금 — so_tax_preview 가 센 값 그대로 · 순서 운임 → 할인 → 오더 할인 → 부가 요금
  for v_x in select c from jsonb_array_elements(coalesce(v_o->'charges', '[]'::jsonb)) c loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_x->>'account_code', ''), 'description', coalesce(v_x->>'name', ''), 'comment', coalesce(v_x->>'description', ''),
                                                 'qty', '', 'unit_price', '', 'discount_pct', public.doc_fmt_pct((v_x->>'discount_pct')::numeric), 'amount', public.doc_fmt_money((v_x->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'tax')::numeric));
  end loop;
  for v_x in select c from jsonb_array_elements(coalesce(v_o->'charge_discounts', '[]'::jsonb)) c loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce((select c.value from public.inv_config c where c.key = 'so_freight_discount_account_code'), ''), 'description', coalesce(v_x->>'name', ''), 'comment', '',
                                                 'qty', '', 'unit_price', '', 'discount_pct', public.doc_fmt_pct((v_x->>'discount_pct')::numeric), 'amount', public.doc_fmt_money((v_x->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'tax')::numeric));
  end loop;
  if coalesce((v_o->'order_discount'->>'amount')::numeric, 0) <> 0 then
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_so.sale_account_code, ''), 'description', format('Order discount %s%%', public.doc_fmt_qty((v_o->'order_discount'->>'pct')::numeric)), 'comment', '',
                                                 'qty', '', 'unit_price', '', 'discount_pct', '', 'amount', public.doc_fmt_money((v_o->'order_discount'->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_o->'order_discount'->>'tax')::numeric));
  end if;
  for v_x in select l from jsonb_array_elements(coalesce(v_o->'lines', '[]'::jsonb)) l where coalesce((l->>'surcharge_total')::numeric, 0) > 0 order by (l->>'line_no')::int loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_sc_code, ''), 'description', coalesce(nullif(v_x->>'surcharge_label', ''), 'Surcharge') || ' (' || (v_x->>'sku') || ')', 'comment', '',
                                                 'qty', public.doc_fmt_qty((v_x->>'qty')::numeric), 'unit_price', public.doc_fmt_money((v_x->>'surcharge_unit')::numeric), 'discount_pct', '',
                                                 'amount', public.doc_fmt_money((v_x->>'surcharge_total')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'surcharge_tax')::numeric));
  end loop;
  v_chg_amt := coalesce((v_t->>'charges_amount')::numeric, 0) - coalesce((v_t->>'charges_discount_amount')::numeric, 0) + coalesce((v_t->>'order_discount_amount')::numeric, 0) + coalesce((v_t->>'surcharge_amount')::numeric, 0);
  v_chg_tax := case when v_t->>'tax' is null then null else (v_t->>'tax')::numeric - v_lines_tax end;
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'reference', coalesce(x.d->>'reference', ''), 'date', public.doc_fmt_date((x.d->>'paid_on')::date, v_fmt), 'method', public.doc_method_label(x.d->>'method'), 'amount', public.doc_fmt_money((x.d->>'remaining')::numeric)) order by x.no), '[]'::jsonb)
    into v_prepay
  from (select d, row_number() over () as no from jsonb_array_elements(coalesce(v_pf->'deposits', '[]'::jsonb)) d) x;
  return jsonb_build_object(
    'so', jsonb_build_object('number', v_so.so_number, 'date', public.doc_fmt_date(v_so.order_date, v_fmt), 'status', v_so.status, 'required_by', public.doc_fmt_date(v_so.required_by, v_fmt), 'terms', coalesce(v_so.payment_term_name, ''),
                             'reference', coalesce(v_so.ref, ''), 'currency', coalesce(v_so.currency_code, ''), 'memo', coalesce(v_so.comments, '')),
    'ship_to', jsonb_build_object('company', coalesce(v_so.ship_to_company, ''), 'contact', coalesce(v_so.ship_to_contact, ''), 'phone', coalesce(v_so.ship_to_phone, ''), 'line1', coalesce(v_so.ship_to_line1, ''), 'line2', coalesce(v_so.ship_to_line2, ''),
                                  'city', coalesce(v_so.ship_to_city, ''), 'state_province', coalesce(v_so.ship_to_state_province, ''), 'postal_code', coalesce(v_so.ship_to_postal_code, ''), 'country', coalesce(v_so.ship_to_country, '')),
    'lines', v_lines, 'charges', v_charges, 'prepayments', v_prepay,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money((v_t->>'lines_amount')::numeric), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money((v_t->>'lines_amount')::numeric + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'order_discount', public.doc_fmt_money((v_t->>'order_discount_amount')::numeric), 'surcharge', public.doc_fmt_money((v_t->>'surcharge_amount')::numeric), 'charges_discount', public.doc_fmt_money(-(v_t->>'charges_discount_amount')::numeric),
                                 'before_tax', public.doc_fmt_money((v_t->>'taxable_amount')::numeric), 'tax', public.doc_fmt_money((v_t->>'tax')::numeric), 'total', public.doc_fmt_money((v_t->>'total')::numeric),
                                 'prepaid', public.doc_fmt_money_nz((v_t->>'received')::numeric), 'due_amount', public.doc_fmt_money((v_t->>'balance_due')::numeric)))   -- doc-1c 판정 528 ③ 의 결: 선결제 없으면 빈칸 · due 는 늘(아직 안 낸 오더)
    || public.doc_data_common('sales_order', p_cfg, jsonb_build_object('name', v_so.bill_to_name, 'line1', v_so.bill_to_line1, 'line2', v_so.bill_to_line2, 'city', v_so.bill_to_city, 'state_province', v_so.bill_to_state_province,
                                                                        'postal_code', v_so.bill_to_postal_code, 'country', v_so.bill_to_country) || public.doc_contact(coalesce(v_so.bill_to_customer_id, v_so.customer_id)));
end;
$$;

-- ═══ ⑥ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if public.doc_fmt_money_nz(0) <> '' or public.doc_fmt_money_nz(null) <> '' or public.doc_fmt_money_nz(0.004) <> '' or public.doc_fmt_money_nz(-6.1) <> '-6.10' or public.doc_fmt_money(0) <> '0.00' then v_bad := v_bad || ' nz'; end if;
  if (public.doc_unit_prices(10, 0, 'both')->>'net_unit_price') <> '' or (public.doc_unit_prices(10, null, 'both')->>'net_unit_price') <> '' or (public.doc_unit_prices(10, 10, 'both')->>'net_unit_price') <> '9.00' or (public.doc_unit_prices(10, 10, 'net')->>'unit_price') <> '9.00' then v_bad := v_bad || ' unit_prices'; end if;
  if (select prosrc from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) !~ 'so_invoice_remaining' then v_bad := v_bad || ' invoice-remaining'; end if;
  if (select prosrc from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) !~ 'doc_fmt_money_nz\(v_due\)' then v_bad := v_bad || ' fmt-due'; end if;
  if (select prosrc from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure) !~ 'doc_fmt_money_nz' then v_bad := v_bad || ' so-prepaid'; end if;
  if (select count(*) from pg_proc where proname in ('doc_data_invoice_fmt', 'doc_data_invoice', 'doc_unit_prices', 'doc_data_so')) <> 4 then v_bad := v_bad || ' dup'; end if;
  if has_function_privilege('anon', 'public.doc_fmt_money_nz(numeric)', 'execute') or has_function_privilege('authenticated', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM511', message = format('STOP - doc-1c did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
