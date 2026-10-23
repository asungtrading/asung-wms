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

-- ═══ bgr-1d — B급 칸 ④ 인쇄 Final sale · 반품 경고 · 반품 칸 · surcharge 없음 (2026-10-23 · 판정 640 · 648 · 649 · 650) ═══
--   ① doc_data_invoice · doc_data_invoice_fmt · doc_field_catalog — final_invoice 줄 열쇠 final_sale(불리언 · 정상 줄 false = Mustache 「없음」) · 판은 손대지 않는다
--   ② so_credit_prepare 줄 final_sale · so_credit_issue 경고 final_sale:<sku>(반품 · 가격 조정 둘 다 · 막지 않는다)
--   ③ 반품 칸 — prepare · issue 의 칸 기본 = B급 줄이면 팔려 나간 그 B급 칸(꺼졌거나 비활성이면 정상 기본 + bgrade_bin_gone) · 이른 거부가 크레딧 창고의 활성 B급 칸을 연다 ·
--      원장 가드가 credit_in(+ · 그 크레딧 줄의 칸) 과 크레딧 취소의 반대 사건을 통과 · 빈 B급 칸에 들어오면 죽은 값을 지운다(값 없음)
--   ④ surcharge 없음 — so_line_bgrade_set 이 비우고 · so_line_bgrade_clear 가 그룹 기본을 다시 · 줄 트리거가 B급 줄의 surcharge 칸 patch 를 막는다(그룹 저장은 줄을 고치지 않는다 — 원문)
--   새 표 · 시퀀스 · 창구 0 · 재발행 열(서명 무변 · create or replace)

-- ═══ doc_data_invoice 재발행 — 원본 DB 바이트(md5 3a1a5a4b7653664836766b909f6ef471) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1d」) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.doc_data_invoice(p_kind text, p_invoice_id uuid, p_cfg jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
                                                                        'unit_price', l.unit_price, 'amount', l.amount, 'tax_amount', l.tax_amount, 'is_free', sl.free_reason is not null, 'no_price', l.unit_price is null, 'manual', coalesce(public.so_line_manual(sl), false), 'final_sale', coalesce(sl.bgrade_bin_id is not null, false)) order by l.line_no), '[]'::jsonb)
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
$function$;

-- ═══ doc_data_invoice_fmt 재발행 — 원본 DB 바이트(md5 1c7ae5b03ab807089df60ac3861a74a5) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1d」) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.doc_data_invoice_fmt(p_kind text, p_cfg jsonb, p_n jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
                                                                    'amount', public.doc_fmt_money((ln.l->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((ln.l->>'tax_amount')::numeric), 'is_free', coalesce((ln.l->>'is_free')::boolean, false), 'no_price', coalesce((ln.l->>'no_price')::boolean, false), 'final_sale', coalesce((ln.l->>'final_sale')::boolean, false))
                                                || public.doc_unit_prices((ln.l->>'unit_price')::numeric, case when coalesce((ln.l->>'manual')::boolean, false) then null else (ln.od_pct)::numeric end, v_disp)) order by ln.no), '[]'::jsonb)
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
$function$;

-- ═══ doc_field_catalog 재발행 — 원본 DB 바이트(md5 099cebdd1b6275f5dc9dc32f818e815e) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1d」) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.doc_field_catalog(p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_common   text[] := array['company.name', 'company.hst', 'company.website', 'company.logo_url', 'company.terms',
                             'branches.code', 'branches.label', 'branches.line1', 'branches.line2', 'branches.phone', 'branches.email',
                             'doc.kind', 'doc.title', 'doc.printed_at', 'show.upc', 'show.comment', 'show.charge_code',
                             'bill_to.name', 'bill_to.line1', 'bill_to.line2', 'bill_to.city', 'bill_to.state_province', 'bill_to.postal_code', 'bill_to.country', 'bill_to.email', 'bill_to.phone'];
  v_ship     text[] := array['company', 'contact', 'phone', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country'];
  v_line     text[] := array['no', 'upc', 'sku', 'description', 'comment', 'unit', 'qty', 'list_price', 'discount_pct', 'unit_price', 'net_unit_price', 'amount', 'tax_amount', 'is_free', 'no_price'];
  v_charge   text[] := array['no', 'so_number', 'code', 'description', 'comment', 'qty', 'unit_price', 'discount_pct', 'amount', 'tax_amount'];
  v_money    text[] := array['no', 'reference', 'date', 'method', 'amount'];
  v_tot_inv  text[] := array['lines_before_tax', 'lines_tax', 'lines_total', 'charges_before_tax', 'charges_tax', 'charges_total', 'order_discount', 'surcharge', 'charges_discount',
                             'before_tax', 'tax', 'total', 'deposit_applied', 'credit_applied', 'balance_forward', 'paid', 'due_label', 'due_amount'];
  v_tot_cr   text[] := array['lines_before_tax', 'lines_tax', 'lines_total', 'charges_before_tax', 'charges_tax', 'charges_total', 'restocking_fee', 'before_tax', 'tax', 'total', 'applied', 'remaining'];
  v_tot_so   text[] := array['lines_before_tax', 'lines_tax', 'lines_total', 'charges_before_tax', 'charges_tax', 'charges_total', 'order_discount', 'surcharge', 'charges_discount',
                             'before_tax', 'tax', 'total', 'prepaid', 'due_amount'];
  v_allowed  text[];
  v_sections text[] := array['branches'];
  v_required text[];
  v_x text;
begin
  if p_kind not in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready', 'internal_receipt') then
    raise exception 'Unknown document kind % — final_invoice, credit_note, sales_order, ship_ready or internal_receipt', coalesce(p_kind, '(null)');
  end if;
  v_allowed := v_common;
  if p_kind in ('final_invoice', 'ship_ready', 'internal_receipt') then
    v_allowed := v_allowed || array['invoice.date', 'invoice.due_date', 'invoice.terms', 'invoice.currency', 'invoice.memo', 'invoice.total_qty'];
    v_allowed := v_allowed || case when p_kind = 'ship_ready' then array['invoice.calc_at'] else array['invoice.number'] end;
    v_allowed := v_allowed || array['orders.so_number', 'orders.reference', 'orders.carrier', 'orders.tracking', 'orders.tax_rule'];
    foreach v_x in array v_ship   loop v_allowed := v_allowed || ('orders.ship_to.' || v_x); end loop;
    foreach v_x in array v_line   loop v_allowed := v_allowed || ('orders.lines.' || v_x); end loop;
    foreach v_x in array v_charge loop v_allowed := v_allowed || ('charges.' || v_x); end loop;
    foreach v_x in array v_money  loop v_allowed := v_allowed || ('payments.' || v_x); end loop;
    foreach v_x in array v_tot_inv loop v_allowed := v_allowed || ('totals.' || v_x); end loop;
    v_sections := v_sections || array['orders', 'orders.lines', 'charges', 'payments'];
    if p_kind = 'final_invoice' then v_allowed := v_allowed || 'orders.lines.final_sale'::text; end if;   -- bgr-1d 판정 640: B급으로 판 줄에 「Final sale」(손님 인보이스 · POS 영수증만 · 불리언)
    v_required := case p_kind when 'final_invoice'    then array['invoice.number', 'orders.lines', 'totals.tax', 'totals.total', 'totals.due_amount']
                              when 'ship_ready'       then array['invoice.calc_at', 'orders.lines', 'totals.tax', 'totals.total', 'totals.due_amount']
                              else                         array['invoice.number', 'invoice.total_qty', 'totals.total', 'totals.due_amount'] end;
  elsif p_kind = 'credit_note' then
    v_allowed := v_allowed || array['credit.number', 'credit.date', 'credit.invoice_number', 'credit.reference', 'credit.reason', 'credit.currency', 'credit.memo'];
    foreach v_x in array v_ship   loop v_allowed := v_allowed || ('ship_to.' || v_x); end loop;
    foreach v_x in array v_line   loop v_allowed := v_allowed || ('lines.' || v_x); end loop;
    foreach v_x in array v_charge loop v_allowed := v_allowed || ('charges.' || v_x); end loop;
    foreach v_x in array v_money  loop v_allowed := v_allowed || ('refunds.' || v_x); end loop;
    foreach v_x in array v_tot_cr loop v_allowed := v_allowed || ('totals.' || v_x); end loop;
    v_sections := v_sections || array['lines', 'charges', 'refunds'];
    v_required := array['credit.number', 'lines', 'totals.tax', 'totals.total'];
  else
    v_allowed := v_allowed || array['so.number', 'so.date', 'so.status', 'so.required_by', 'so.terms', 'so.reference', 'so.currency', 'so.memo'];
    foreach v_x in array v_ship   loop v_allowed := v_allowed || ('ship_to.' || v_x); end loop;
    foreach v_x in array v_line   loop v_allowed := v_allowed || ('lines.' || v_x); end loop;
    foreach v_x in array v_charge loop v_allowed := v_allowed || ('charges.' || v_x); end loop;
    foreach v_x in array v_money  loop v_allowed := v_allowed || ('prepayments.' || v_x); end loop;
    foreach v_x in array v_tot_so loop v_allowed := v_allowed || ('totals.' || v_x); end loop;
    v_sections := v_sections || array['lines', 'charges', 'prepayments'];
    v_required := array['so.number', 'lines', 'totals.tax', 'totals.total'];
  end if;
  return jsonb_build_object('kind', p_kind, 'allowed', to_jsonb(v_allowed), 'sections', to_jsonb(v_sections), 'required', to_jsonb(v_required));
end;
$function$;

-- ═══ so_credit_prepare 재발행 — 원본 DB 바이트(md5 3fcd62ab735eeb311ba2d9e67a5acbff) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1d」) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.so_credit_prepare(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with inv as (
    select i.*, cu.name as customer_name, public.ims_today() as today,
           (select s.location_id from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = i.id order by o.so_number limit 1) as wh_id   -- 발행 창구 :996 과 같은 줄(원판매 첫 오더의 창고)
    from public.so_invoice i left join public.customer cu on cu.id = i.bill_to_customer_id
    where i.id = p_invoice_id
  ),
  cfg as (
    select (select nullif(k.value, '')::int     from public.inv_config k where k.key = 'so_credit_restock_fee_days')         as fee_days,
           (select nullif(k.value, '')::numeric from public.inv_config k where k.key = 'so_credit_restock_fee_pct')          as fee_pct,
           (select nullif(k.value, '')          from public.inv_config k where k.key = 'so_credit_restock_fee_account_code') as fee_account_code
  )
  select jsonb_build_object(
    'invoice', jsonb_build_object('id', inv.id, 'invoice_number', inv.invoice_number, 'status', inv.status, 'creditable', (inv.status = 'issued'), 'issued_on', inv.issued_on,
                                  'days_since_invoice', inv.today - inv.issued_on, 'customer_id', inv.bill_to_customer_id, 'customer_name', inv.customer_name, 'bill_to_name', inv.bill_to_name,
                                  'currency_id', inv.currency_id, 'currency_code', inv.currency_code, 'total', inv.total, 'remaining', public.so_invoice_remaining(inv.id)),
    'warehouse', (select jsonb_build_object('warehouse_id', w.id, 'warehouse_name', w.name, 'is_active', w.is_active) from public.ref_warehouse w where w.id = inv.wh_id),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                'so_invoice_line_id', l.id, 'line_no', l.line_no, 'kind', l.kind, 'sku', l.sku, 'description', l.description, 'unit', l.unit, 'pack_factor', l.pack_factor,
                'qty_sold', l.qty,
                -- ⚠️ 복사 식(0-5): so_credit_issue 20260925012354:1055~1056 의 「이미 반품」과 글자까지 같아야 창구가 거부하지 않는다 · ⬜ so_credit_line_returned(so_invoice_line_id) 류 함수로 떼고 발행 창구와 함께 부른다(다음 차수)
                'qty_credited', case when l.kind = 'product' then (public.so_credit_line_state(l.id)->>'qty_returned')::numeric end,                                                            -- crn-2: 식은 so_credit_line_state 한 곳(§22-f ⬜ 닫힘)
                'qty_returnable', case when l.kind = 'product' then (public.so_credit_line_state(l.id)->>'qty_returnable')::numeric end,
                -- crn-2 판정 603 · 611 · 613: 가격 조정 재료 — 낸 단가(오더 할인 뒤) · 층(tiers) · 조정할 수 있는 수량(낸 단가 층) · 열린 조정 몫 · 앞선 조정 목록(콤보 줄은 null)
                'adjust', case when l.kind = 'product' and l.combo_components is null then public.so_credit_line_state(l.id) - 'so_invoice_line_id' - 'tiers_raw' end,
                'amount', l.amount,
                -- charge 줄의 「이미 반품」은 금액(발행 창구 :1099~1103 의 v_already 와 같은 뜻)
                'amount_credited', case when l.kind in ('charge', 'surcharge') then (select coalesce(sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') end,   -- surcharge-2b: surcharge 줄은 보이기만(자동 · 손으로 못 보낸다)
                'discount_line_id', fd.fd_id, 'discount_amount', fd.fd_amount, 'net_amount', case when l.kind = 'charge' then l.amount - coalesce(fd.fd_amount, 0) end,                     -- fr-3 판정 355: 운임 줄의 할인(인보이스 charge_discount 줄 · 양수) · 순액
                'discount_credited', fd.fd_credited, 'net_credited', case when l.kind = 'charge' then fd.gross_credited - coalesce(fd.fd_credited, 0) end,                   -- 이미 돌려준 할인(양수) · 이미 돌려준 순액
                'net_remaining', case when l.kind = 'charge' then (l.amount - coalesce(fd.fd_amount, 0)) - (fd.gross_credited - coalesce(fd.fd_credited, 0)) end,              -- 남은 순액 한도(so_credit_issue 의 순액 검사와 같은 식)
                'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'rate_pct', io.rate_pct, 'tax_rule', io.tax_rule, 'tax_amount', l.tax_amount, 'account_code', l.account_code,
                'product_id', sl.product_id, 'stock_product_id', coalesce(pr.parent_product_id, pr.id), 'stock_sku', coalesce(pp.sku, pr.sku),
                'final_sale', sl.bgrade_bin_id is not null, 'restock_bgrade_bin_gone', sl.bgrade_bin_id is not null and bgb.j is null,   -- bgr-1d 판정 640 · 649: B급으로 판 줄 · 그 B급 칸이 꺼졌거나 비활성이면 정상 기본으로
                -- 되돌려 놓을 칸 기본값 — 발행 창구 :1077 과 같은 길(ims_last_bin(낱개 제품, 창고) · ④a1 뒤로 보관용 아님 먼저 · 없으면 null → 사람이 고르거나 안 돌아옴으로)
                'restock_bin_default', case when l.kind = 'product' and l.combo_components is null and inv.wh_id is not null and pr.id is not null
                                            then coalesce(bgb.j, public.ims_last_bin(array[coalesce(pr.parent_product_id, pr.id)], inv.wh_id) -> coalesce(pr.parent_product_id, pr.id)::text) end,   -- bgr-1d 판정 649: B급 줄은 팔려 나간 그 B급 칸 먼저
                -- asm-2b2(묶음 7 · 판정 245): 콤보 인보이스 줄 = 반품 단위(qty 는 콤보 수) · 구성품마다 돌아가는 칸 기본(ims_last_bin · 낱개 제품 · 그 창고) — 보통 줄은 null
                'combo_components', (select jsonb_agg(cj || jsonb_build_object('restock_bin_default', case when inv.wh_id is not null and cpr.id is not null then public.ims_last_bin(array[coalesce(cpr.parent_product_id, cpr.id)], inv.wh_id) -> coalesce(cpr.parent_product_id, cpr.id)::text end) order by cj->>'sku')
                                       from jsonb_array_elements(l.combo_components) cj left join public.product cpr on cpr.id = nullif(cj->>'product_id', '')::uuid))
              order by l.line_no), '[]'::jsonb)
              from public.so_invoice_line l
              join public.so_invoice_order io on io.id = l.invoice_order_id
              left join public.so_line sl on sl.id = l.so_line_id
              left join public.product pr on pr.id = sl.product_id
              left join public.product pp on pp.id = pr.parent_product_id
              left join lateral (select jsonb_build_object('bin_id', rb.id, 'bin', rb.name, 'zone', rb.zone, 'received_on', null, 'is_bgrade', true) as j                       -- bgr-1d: ims_last_bin 칸 꼴 + is_bgrade
                                   from public.ref_bin rb where rb.id = sl.bgrade_bin_id and rb.is_bgrade and rb.is_active and rb.warehouse_id = inv.wh_id) bgb on true
              left join lateral (select d.id as fd_id, -d.amount as fd_amount,                                                                                       -- fr-3: 운임 줄의 할인 줄(없으면 null)
                                        (select coalesce(-sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = d.id and c.status = 'issued') as fd_credited,
                                        (select coalesce(sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') as gross_credited
                                   from public.so_invoice_line d where l.kind = 'charge' and d.invoice_id = l.invoice_id and d.kind = 'charge_discount' and d.so_charge_id = l.so_charge_id) fd on true
              where l.invoice_id = inv.id and l.kind in ('product', 'charge', 'surcharge')),
    'restock_fee', jsonb_build_object('days', cfg.fee_days, 'pct', cfg.fee_pct, 'account_code', cfg.fee_account_code,
                                      'days_since_invoice', inv.today - inv.issued_on,
                                      'applies', (cfg.fee_days is not null and inv.today - inv.issued_on > cfg.fee_days),
                                      'note', 'notice only — the preview so_credit_issue(p, false) proposes the amount (fee_suggested); the account must be picked when account_code is null'),
    'already_credited', (select coalesce(jsonb_agg(jsonb_build_object('credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'reason', c.reason, 'total', c.total, 'remaining', public.so_credit_remaining(c.id)) order by c.credit_number), '[]'::jsonb)
                         from public.so_credit c where c.invoice_id = inv.id),
    'vocab', jsonb_build_object('reasons', '["customer_return","damaged","billing_error","other","price_adjustment"]'::jsonb,                                                      -- crn-2 판정 612
                                'not_restocked_reasons', '["damaged","b_grade","not_returned","other"]'::jsonb,
                                'line_kinds', '["product","freight","tax","other","restocking_fee","price_adjustment"]'::jsonb)                                                   -- crn-2 판정 603
  )
  from inv, cfg;
$function$;

-- ═══ so_credit_issue 재발행 — 원본 DB 바이트(md5 4175a0e0c3e8abd7b4bf0f7cff106803) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1d」) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.so_credit_issue(p jsonb, p_commit boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_reasons   constant text[] := array['customer_return','damaged','billing_error','other','price_adjustment'];   -- crn-2 판정 612
  c_nr        constant text[] := array['damaged','b_grade','not_returned','other'];
  v_staff     uuid;
  v_on        date;
  v_reason    text;
  v_inv       public.so_invoice%rowtype;
  v_c         public.customer%rowtype;
  v_cur       public.ref_currency%rowtype;
  v_w         public.ref_warehouse%rowtype;
  v_rule      public.ref_tax_rule%rowtype;
  v_cr        public.so_credit%rowtype;
  v_il        public.so_invoice_line%rowtype;
  v_io        public.so_invoice_order%rowtype;
  v_pr        public.product%rowtype;
  v_bin       public.ref_bin%rowtype;
  v_acct      public.ref_account%rowtype;
  v_ref       boolean := false;                                                                        -- crn-1 판정 602 · 609: 참조 크레딧(인보이스 없음 · 옛 이름 cin7)
  v_ref_inv   text;  v_ref_ord text;  v_ref_date date;
  v_tax_src   text;  v_sa public.customer_address%rowtype;  v_tr jsonb;  v_seen text;                  -- crn-1 판정 610: 세금 기본 = 손님 기본 배송지의 규칙 · 경고 reference_seen
  v_cust      uuid;
  v_origin_on date;
  v_wh        uuid;
  v_bgb       uuid;                                                                   -- bgr-1d: 반품하는 인보이스 줄의 B급 칸(정상 줄 · 참조 크레딧은 null)
  v_first_io  public.so_invoice_order%rowtype;
  v_fee_days  int;  v_fee_pct numeric;  v_fee_acct_code text;
  v_lines     jsonb := '[]'::jsonb;
  v_ln        int := 0;
  v_kind      text;
  v_qty       numeric;  v_already numeric;  v_unit numeric;  v_amount numeric;  v_rate numeric;  v_tax numeric;
  v_bin_name  text;  v_bin_id uuid;  v_nr text;  v_nr_note text;  v_desc text;  v_acct_id uuid;  v_acct_code text;
  v_product_id uuid;  v_so_line_id uuid;  v_sku text;  v_il_id uuid;
  v_lines_amt numeric := 0;  v_fee_amt numeric := 0;  v_tax_amt numeric := 0;  v_product_amt numeric := 0;
  v_od_amt    numeric := 0;  v_od record;  v_od_il public.so_invoice_line%rowtype;                                      -- dsc-3b 판정 325 — 오더 할인 몫(인보이스-오더마다 음수 줄 하나)
  v_sc        public.so_invoice_line%rowtype;  v_sc_amt numeric := 0;  v_sc_line numeric;  v_sc_tax numeric;  v_sc_already numeric;   -- surcharge-2b(묶음 7)
  v_fd        public.so_invoice_line%rowtype;  v_fd_amt numeric := 0;  v_fd_line numeric := 0;  v_fd_tax numeric;  v_fd_already numeric;  v_fd_inv numeric;   -- fr-3 판정 355: 운임 할인 되돌림(인보이스 charge_discount 줄 · 같은 비율 · 끝수는 마지막에)
  v_rates     numeric[] := '{}';  v_first_rate numeric;
  v_fee_lines int := 0;  v_restock_n int := 0;
  v_fee_sugg  jsonb;
  v_warn      text[] := '{}';
  v_ledger    jsonb;
  v_est       numeric;  v_est_qty numeric;
  v_ask       numeric;
  x           jsonb;
  e           jsonb;
  -- asm-2b2(묶음 7 · 판정 245): 콤보 인보이스 줄의 반품 — 콤보 크레딧 줄(금액 · qty = 콤보 수 · 칸 · 사유 없음 · combo_components) + 구성품 크레딧 줄(금액 0 · qty = n × combo_qty · 제 칸 또는 사유 · combo_credit_line_id) · 구성품 하나만의 상품 줄은 거부
  v_combo     jsonb;  cj jsonb;  v_cov jsonb;  v_def_bin text;  v_def_nr text;  v_def_note text;  v_cpr public.product%rowtype;  v_cq numeric;  v_idmap jsonb := '{}'::jsonb;  v_parent_ln int;
  -- crn-2(판정 603 · 611 · 613 · 614): 인보이스 줄마다 가격 층(tiers · so_credit_line_state) — 이 호출 안의 반품 · 조정이 차례로 깎는다 · v_odb = 줄 번호 → 오더 할인 거울의 기준 금액(조정된 몫은 뺀다)
  v_tiers     jsonb := '{}'::jsonb;  v_take jsonb;  v_tier jsonb;  v_odb jsonb := '{}'::jsonb;  v_od_base numeric;  v_before numeric;  v_after numeric;  v_adj_n int := 0;  v_ret_n int := 0;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — 발행은 manager 이상(판정 3)
  v_staff := public.so_current_staff();
  v_on := coalesce(nullif(p->>'issued_on', '')::date, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Credit date % is in the future — nothing was saved', v_on; end if;
  v_reason := nullif(trim(p->>'reason'), '');
  if v_reason is null or v_reason <> all (c_reasons) then raise exception 'reason must be one of customer_return, damaged, billing_error, other — nothing was saved'; end if;
  if v_reason = 'other' and nullif(trim(p->>'note'), '') is null then raise exception 'reason other needs a note — nothing was saved'; end if;
  if p->'lines' is null or jsonb_typeof(p->'lines') <> 'array' or jsonb_array_length(p->'lines') = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  -- 설정(판정 5·7)
  select nullif(k.value, '')::int into v_fee_days from public.inv_config k where k.key = 'so_credit_restock_fee_days';
  select nullif(k.value, '')::numeric into v_fee_pct from public.inv_config k where k.key = 'so_credit_restock_fee_pct';
  select nullif(k.value, '') into v_fee_acct_code from public.inv_config k where k.key = 'so_credit_restock_fee_account_code';

  -- 원본 — IMS 인보이스 또는 참조 번호(옛 인보이스 종이 번호 · 판정 602 · 609 — 옛 열쇠 cin7 은 거부)
  if nullif(p->>'invoice_id', '') is not null then
    select * into v_inv from public.so_invoice i where i.id = (p->>'invoice_id')::uuid for update;
    if not found then raise exception 'Invoice not found — nothing was saved'; end if;
    if v_inv.status <> 'issued' then raise exception 'Invoice % is % — credit the live invoice, not a cancelled one — nothing was saved', v_inv.invoice_number, v_inv.status; end if;
    v_cust := v_inv.bill_to_customer_id;  v_origin_on := v_inv.issued_on;
    select * into v_cur from public.ref_currency c where c.id = v_inv.currency_id;
    select o.* into v_first_io from public.so_invoice_order o where o.invoice_id = v_inv.id order by o.so_number limit 1;
    select s.location_id into v_wh from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id order by o.so_number limit 1;
  elsif p ? 'cin7' then
    raise exception 'The cin7 key is gone — send ref {invoice_number, order_number, invoice_date} for a credit without an IMS invoice — nothing was saved';   -- crn-1 판정 609
  elsif p->'ref' is not null and jsonb_typeof(p->'ref') = 'object' then
    v_ref := true;
    v_ref_inv := nullif(trim(p->'ref'->>'invoice_number'), '');  v_ref_ord := nullif(trim(p->'ref'->>'order_number'), '');  v_ref_date := nullif(p->'ref'->>'invoice_date', '')::date;
    if v_ref_inv is null then raise exception 'A reference credit needs ref.invoice_number (the number on the paper invoice) — nothing was saved'; end if;
    if nullif(p->>'customer_id', '') is null then raise exception 'A reference credit needs customer_id — nothing was saved'; end if;
    v_cust := (p->>'customer_id')::uuid;  v_origin_on := v_ref_date;
    if not exists (select 1 from public.customer c where c.id = v_cust) then raise exception 'Customer not found — nothing was saved'; end if;
    select * into v_cur from public.ref_currency c
     where c.id = coalesce(nullif(p->>'currency_id', '')::uuid, (select c2.id from public.ref_currency c2 where c2.code = upper(nullif(trim(p->>'currency_code'), ''))), (select c3.currency_id from public.customer c3 where c3.id = v_cust));
    if v_cur.id is null then raise exception 'Currency is required — the customer has no default currency — nothing was saved'; end if;
    if nullif(trim(p->>'tax_rule'), '') is not null then                                                  -- 보낸 규칙 그대로(활성 판매 규칙 검사 그대로)
      select * into v_rule from public.ref_tax_rule r where r.name = trim(p->>'tax_rule') and r.direction = 'sale' and r.is_active;
      if v_rule.id is null then raise exception 'Tax rule % is not an active sale rule — nothing was saved', trim(p->>'tax_rule'); end if;
      v_tax_src := 'given';
    else                                                                                                  -- crn-1 판정 610: 손님 기본 배송지의 주 → so_tax_rule_for(IMS 인보이스와 같은 식) · 없으면 거부(직원이 고른다)
      select * into v_sa from public.customer_address a where a.customer_id = v_cust and a.type = 'Shipping' and a.is_active and a.is_default_for_type limit 1;
      if v_sa.id is null then raise exception 'Pick a tax rule — the customer has no default ship-to address to suggest one from — nothing was saved'; end if;
      v_tr := public.so_tax_rule_for(v_sa.country, v_sa.state_province, v_on, 'sale');
      if nullif(v_tr->>'rule_id', '') is null then raise exception 'Pick a tax rule — no sale tax rule is linked to the customer''s default ship-to (% / %) — nothing was saved', coalesce(v_sa.country, '?'), coalesce(v_sa.state_province, '?'); end if;
      select * into v_rule from public.ref_tax_rule r where r.id = (v_tr->>'rule_id')::uuid;
      v_tax_src := 'ship_to';
    end if;
    select c.default_location_id into v_wh from public.customer c where c.id = v_cust;
  else
    raise exception 'Give invoice_id (an IMS invoice) or ref {invoice_number, order_number, invoice_date} (a credit without an IMS invoice) — nothing was saved';
  end if;
  select * into v_c from public.customer c where c.id = v_cust for update;         -- 청구처 손님 행 잠금(잔액 직렬화 · ⓑ 와 같은 자물쇠)
  if not found then raise exception 'Customer not found — nothing was saved'; end if;

  -- 창고(반품을 받은 창고 · ⬜4) — 지정 → 원 판매 창고 → 손님 기본 창고 → 거부
  v_wh := coalesce(nullif(p->>'warehouse_id', '')::uuid, v_wh);
  if v_wh is null then raise exception 'warehouse_id is required — where were the goods returned to? — nothing was saved'; end if;
  select * into v_w from public.ref_warehouse w where w.id = v_wh;
  if not found then raise exception 'Warehouse not found — nothing was saved'; end if;
  if not v_w.is_active then raise exception 'Warehouse % is inactive — nothing was saved', v_w.name; end if;

  -- 줄 — 첫 바퀴: product · freight · tax · other(수수료는 둘째 바퀴 · 제품 합이 먼저 필요하다)
  for x in select t from jsonb_array_elements(p->'lines') t loop
    v_kind := nullif(trim(x->>'kind'), '');
    if v_kind = 'surcharge' then raise exception 'Surcharge lines are added automatically from the returned product lines — do not send them — nothing was saved'; end if;   -- surcharge-2b(D-3 · 자동만)
    if v_kind = 'freight_discount' then raise exception 'Freight discount lines are added automatically from the returned freight line — do not send them — nothing was saved'; end if;   -- fr-3 판정 355(자동만)
    if v_kind is null or v_kind not in ('product','freight','tax','other','restocking_fee','price_adjustment') then raise exception 'Line kind must be one of product, freight, tax, other, restocking_fee, price_adjustment — nothing was saved'; end if;
    if v_kind = 'restocking_fee' then v_fee_lines := v_fee_lines + 1; continue; end if;
    if v_kind = 'price_adjustment' then v_adj_n := v_adj_n + 1; continue; end if;                       -- crn-2: 가격 조정은 둘째 바퀴(반품이 먼저 낮은 층을 가져간다 · §2-2)
    v_il := null;  v_io := null;  v_pr := null;  v_bin := null;  v_acct := null;  v_fd := null;  v_fd_line := 0;                                                           -- fr-3
    v_qty := null;  v_unit := null;  v_rate := null;  v_bin_id := null;  v_bin_name := null;  v_nr := null;  v_nr_note := null;  v_product_id := null;  v_so_line_id := null;  v_sku := null;  v_il_id := null;  v_desc := null;  v_est := null;
    v_bgb := null;                                                                                                                                                         -- bgr-1d
    v_take := null;  v_od_base := null;                                                                                                                                                -- crn-2
    v_acct_id := nullif(x->>'account_id', '')::uuid;
    if v_acct_id is not null then
      select * into v_acct from public.ref_account a where a.id = v_acct_id;
      if v_acct.id is null then raise exception 'Account % not found — nothing was saved', v_acct_id; end if;
    end if;

    if v_kind = 'product' then
      v_qty := nullif(x->>'qty_returned', '')::numeric;
      if v_qty is null or v_qty <= 0 then raise exception 'A product line needs qty_returned > 0 — nothing was saved'; end if;
      if v_ref then
        v_sku := nullif(trim(x->>'sku'), '');
        if v_sku is null then raise exception 'A reference credit product line needs sku — nothing was saved'; end if;
        select * into v_pr from public.product pr where pr.sku = v_sku;
        if v_pr.id is null then raise exception 'Product % not found — nothing was saved', v_sku; end if;
        v_unit := nullif(x->>'unit_price', '')::numeric;
        if v_unit is null or v_unit < 0 then raise exception 'A reference credit product line needs unit_price (the price on the paper invoice) — nothing was saved'; end if;
        v_rate := v_rule.rate_pct;  v_product_id := v_pr.id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_pr.name);
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_98_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then
          if exists (select 1 from public.so_line cl2 join public.so_invoice_order io2 on io2.so_id = cl2.so_id                                  -- asm-2b2(판정 245): 구성품은 인보이스 줄이 없다 — 하나만 돌려받는 길은 「other」 금액 줄
                      where io2.invoice_id = v_inv.id and cl2.combo_line_id is not null and (cl2.id = nullif(x->>'so_line_id', '')::uuid or cl2.sku = nullif(trim(x->>'sku'), ''))) then
            raise exception 'Line % is a component of a combo on invoice % — a combo is credited whole (credit the combo line); for one component use an other line (amount only, no stock) — nothing was saved', coalesce(nullif(trim(x->>'sku'), ''), x->>'so_line_id'), v_inv.invoice_number;
          end if;
          raise exception 'An IMS product line needs so_invoice_line_id (the invoice line being returned) — nothing was saved';
        end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'product';
        if v_il.id is null then raise exception 'Invoice line % is not a product line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        v_already := (public.so_credit_line_state(v_il.id)->>'qty_returned')::numeric;                   -- crn-2: 「이미 반품」 식은 so_credit_line_state 한 곳(§22-f ⬜ 복사 식 닫힘 · 값은 같다)
        select coalesce(sum((t->>'qty_returned')::numeric), 0) into v_ask from jsonb_array_elements(p->'lines') t where t->>'kind' = 'product' and nullif(t->>'so_invoice_line_id', '')::uuid = v_il.id;
        if v_already + v_ask > v_il.qty then
          raise exception 'Invoice % line % (%): % of % already credited and % asked now — only % can still be returned — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, v_already, v_il.qty, v_ask, v_il.qty - v_already;
        end if;
        v_unit := v_il.unit_price;  v_rate := v_io.rate_pct;  v_sku := v_il.sku;  v_so_line_id := v_il.so_line_id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        -- crn-2 판정 611: 반품은 조정된 몫(낮은 층)부터 — 이 줄의 층을 가져와(이 호출의 앞선 줄이 깎은 것 포함) 낮은 값부터 v_qty 만큼 뗀다
        if not (v_tiers ? v_il.id::text) then v_tiers := v_tiers || jsonb_build_object(v_il.id::text, public.so_credit_line_state(v_il.id)->'tiers'); end if;
        v_take := public.so_credit_tiers_take(v_tiers->(v_il.id::text), v_qty, null);
        v_tiers := v_tiers || jsonb_build_object(v_il.id::text, v_take->'tiers');
        select sl.product_id into v_product_id from public.so_line sl where sl.id = v_il.so_line_id;
        select sl.bgrade_bin_id into v_bgb from public.so_line sl where sl.id = v_il.so_line_id;                                  -- bgr-1d 판정 640
        if v_bgb is not null then v_warn := array_append(v_warn, 'final_sale:' || v_sku); end if;                                -- bgr-1d: 경고만(노 리턴 · 발행은 막지 않는다)
        select * into v_pr from public.product pr where pr.id = v_product_id;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      if v_take is null then
        v_amount := round(v_qty * coalesce(v_unit, 0), 2);  v_od_base := v_amount;
      else                                                                                                      -- crn-2 판정 611: 낸 단가 층은 인보이스 단가(오더 할인 거울이 따로 뺀다) · 조정 층은 새 단가 그대로(거울 기준에서 뺀다)
        select coalesce(sum(case when (pt->>'paid')::boolean then round((pt->>'qty')::numeric * coalesce(v_unit, 0), 2) else round((pt->>'qty')::numeric * (pt->>'unit_price')::numeric, 2) end), 0),
               coalesce(sum(case when (pt->>'paid')::boolean then round((pt->>'qty')::numeric * coalesce(v_unit, 0), 2) else 0 end), 0)
          into v_amount, v_od_base from jsonb_array_elements(v_take->'parts') pt;
        if exists (select 1 from jsonb_array_elements(v_take->'parts') pt where not (pt->>'paid')::boolean) then
          v_unit := round(v_amount / v_qty, 6);
          v_desc := v_desc || ' (' || (select string_agg(trim_scale((pt->>'qty')::numeric) || ' × ' || trim_scale(case when (pt->>'paid')::boolean then coalesce(v_il.unit_price, 0) else (pt->>'unit_price')::numeric end), ' + ' order by ord) from jsonb_array_elements(v_take->'parts') with ordinality t(pt, ord)) || ')';
        end if;
      end if;
      v_tax := public.so_tax_amount(v_amount, v_rate);
      v_product_amt := v_product_amt + v_amount;  v_rates := array_append(v_rates, v_rate);
      -- 돌아오나(판정 1) — not_restocked_reason 이 있으면 안 돌아옴 · 아니면 칸(지정 → ims_last_bin → 거부 · '' 불허 · ⬜4)
      v_combo := case when v_ref then null else nullif(v_il.combo_components, 'null'::jsonb) end;
      v_nr := nullif(trim(x->>'not_restocked_reason'), '');
      if v_combo is not null then                                                                                 -- asm-2b2: 콤보 줄 자체는 칸 · 사유가 없다 — 줄에 적은 칸 · 사유는 구성품 전부의 기본값(components[] 가 덮는다)
        v_def_nr := v_nr;  v_def_note := nullif(trim(x->>'not_restocked_note'), '');  v_def_bin := nullif(trim(x->>'restock_bin'), '');  v_nr := null;
        if v_def_nr is not null and v_def_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
        if v_def_nr = 'other' and v_def_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
        if exists (select 1 from jsonb_array_elements(coalesce(nullif(x->'components', 'null'::jsonb), '[]'::jsonb)) cx where not exists (select 1 from jsonb_array_elements(v_combo) cy where cy->>'sku' = nullif(trim(cx->>'sku'), ''))) then
          raise exception 'components[] of combo % names a sku that is not part of that combo on invoice % — nothing was saved', v_sku, v_inv.invoice_number;
        end if;
      elsif v_nr is not null then
        if v_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
        v_nr_note := nullif(trim(x->>'not_restocked_note'), '');
        if v_nr = 'other' and v_nr_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
      else
        v_bin_name := nullif(trim(x->>'restock_bin'), '');
        if v_bin_name is null and v_bgb is not null then                                                                         -- bgr-1d 판정 649: B급 줄의 반품 = 팔려 나간 그 B급 칸
          select rb.name into v_bin_name from public.ref_bin rb where rb.id = v_bgb and rb.is_bgrade and rb.is_active and rb.warehouse_id = v_w.id;
          if v_bin_name is null then v_warn := array_append(v_warn, 'bgrade_bin_gone:' || v_sku); end if;                     -- 꺼졌거나 · 비활성 · 다른 창고 → 정상 기본(ims_last_bin)
        end if;
        if v_bin_name is null then
          v_bin_name := public.ims_last_bin(array[coalesce(v_pr.parent_product_id, v_pr.id)], v_w.id) -> coalesce(v_pr.parent_product_id, v_pr.id)::text ->> 'bin';
          if v_bin_name is null then raise exception 'No bin known for % in % — pick a restock bin (or mark the line not restocked) — nothing was saved', v_sku, v_w.name; end if;
        end if;
        select * into v_bin from public.ref_bin rb where rb.warehouse_id = v_w.id and rb.name = v_bin_name;
        if v_bin.id is null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bin_name, v_w.name; end if;
        if not v_bin.is_active then v_warn := array_append(v_warn, 'inactive_bin:' || v_bin_name); end if;
        v_bin_id := v_bin.id;  v_restock_n := v_restock_n + 1;
        -- 원가 복원 예상(미리 보기 · 원 판매의 소비 기록 평균 × EA · 없으면 null)
        select sum(cs.qty * cs.unit_cost) / nullif(sum(cs.qty), 0), sum(cs.qty) into v_est, v_est_qty
          from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
         where cs.doc_type = 'sale' and cs.reason = 'sale' and l.sku = coalesce((select pp.sku from public.product pp where pp.id = v_pr.parent_product_id), v_pr.sku)
           and cs.doc_number = case when v_ref then null else (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id)) end;   -- crn-1 판정 602: 참조 크레딧은 되짚지 않는다(예상 null · 실제 원가는 inv_layer_post_credit ② 가중평균부터)
      end if;
    elsif v_kind = 'freight' then
      if v_ref then
        v_amount := nullif(x->>'amount', '')::numeric;  v_rate := v_rule.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Freight');
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_99_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then raise exception 'An IMS freight line needs so_invoice_line_id (the charge line) — nothing was saved'; end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'charge';
        if v_il.id is null then raise exception 'Invoice line % is not a charge line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        v_amount := coalesce(nullif(x->>'amount', '')::numeric, v_il.amount);  v_rate := v_io.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        select coalesce(sum(cl.amount), 0) into v_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_il.id and c.status = 'issued';
        if v_already + v_amount > v_il.amount then raise exception 'Invoice % charge % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_already, v_il.amount, v_il.amount - v_already; end if;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      if v_amount is null or v_amount < 0 then raise exception 'A freight line needs amount ≥ 0 — nothing was saved'; end if;
      v_tax := public.so_tax_amount(v_amount, v_rate);
      if not v_ref then                                                                                             -- fr-3 판정 355: 그 운임 줄에 할인 줄(charge_discount · 같은 so_charge_id)이 있으면 같은 비율로 되돌린다
        select * into v_fd from public.so_invoice_line d where d.invoice_id = v_inv.id and d.kind = 'charge_discount' and d.so_charge_id = v_il.so_charge_id;
        if v_fd.id is not null then
          v_fd_inv := -v_fd.amount;                                                                                    -- 인보이스 할인(양수)
          select coalesce(-sum(cl.amount), 0) into v_fd_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_fd.id and c.status = 'issued';   -- 이미 돌려준 할인(양수)
          v_fd_line := case when v_already + v_amount = v_il.amount then v_fd_inv - v_fd_already                             -- 끝수 규칙: 정가를 다 돌려주는 마지막 줄은 남은 할인 전부(합 = 인보이스 할인 · 정확히)
                            else least(round(v_amount * v_fd_inv / v_il.amount, 2), v_fd_inv - v_fd_already) end;                 -- 그 밖은 round(x × 비율, 2) · 남은 할인을 넘지 않는다
          if (v_already - v_fd_already) + (v_amount - v_fd_line) > v_il.amount - v_fd_inv or v_fd_line > v_amount then         -- 순액 한도: 돌려준 순액 합 ≤ 손님이 낸 순액 · 남은 할인이 이번 운임보다 크면(앞 크레딧이 할인 없이 정가를 가져간 옛 모양) 음수 순액이 되므로 거부(정가 한도 검사는 위에 그대로)
            raise exception 'Invoice % charge % : the customer paid % net (% less % discount) — % net already credited and % asked now — only % left — nothing was saved',
              v_inv.invoice_number, v_il.line_no, v_il.amount - v_fd_inv, v_il.amount, v_fd_inv, v_already - v_fd_already, v_amount - v_fd_line, (v_il.amount - v_fd_inv) - (v_already - v_fd_already);
          end if;
        end if;
      end if;
    elsif v_kind = 'tax' then
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null or v_amount < 0 then raise exception 'A tax line needs amount ≥ 0 (the tax being returned) — nothing was saved'; end if;
      v_rate := null;  v_tax := 0;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Tax');
      if v_acct.id is null then
        select * into v_acct from public.ref_account a where a.id = (case when v_ref then v_rule.account_id else (select r.account_id from public.ref_tax_rule r where r.id = v_first_io.tax_rule_id) end);
      end if;
    else   -- other
      v_amount := nullif(x->>'amount', '')::numeric;  v_desc := nullif(trim(x->>'description'), '');
      if v_amount is null or v_amount < 0 then raise exception 'An other line needs amount ≥ 0 — nothing was saved'; end if;
      if v_desc is null then raise exception 'An other line needs a description — nothing was saved'; end if;
      if v_acct.id is null then raise exception 'An other line needs account_id (no default) — nothing was saved'; end if;
      v_rate := case when v_ref then v_rule.rate_pct else v_first_io.rate_pct end;  v_tax := public.so_tax_amount(v_amount, v_rate);
    end if;
    v_ln := v_ln + 1;  v_lines_amt := v_lines_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);  v_parent_ln := v_ln;
    if v_kind = 'product' then v_odb := v_odb || jsonb_build_object(v_ln::text, v_od_base); v_ret_n := v_ret_n + 1; end if;                                      -- crn-2: 거울 기준(조정된 몫 제외)
    v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', v_kind, 'so_invoice_line_id', v_il_id, 'so_line_id', v_so_line_id, 'product_id', v_product_id, 'sku', v_sku, 'description', v_desc,
                                             'qty_returned', v_qty, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                             'unit_price', v_unit, 'amount', v_amount, 'rate_pct', v_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code,
                                             'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_qty * coalesce(v_pr.pack_factor, 1), 6) end,
                                             'combo_components', case when v_kind = 'product' then v_combo end);                                           -- asm-2b2: 콤보 크레딧 줄에 includes(인보이스 줄 사본)
    if v_kind = 'freight' and not v_ref and v_fd.id is not null and v_fd_line > 0 then                                   -- fr-3 판정 355 · 352 · 354 · 358: 운임 줄 바로 뒤 할인 되돌림 줄 · 음수 · 세금 따로(줄마다) · 계정 = 인보이스 할인 줄 것
      v_fd_tax := public.so_tax_amount(-v_fd_line, v_io.rate_pct);
      v_ln := v_ln + 1;  v_fd_amt := v_fd_amt - v_fd_line;  v_tax_amt := v_tax_amt + coalesce(v_fd_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'freight_discount', 'so_invoice_line_id', v_fd.id, 'description', v_fd.description,
                                               'amount', -v_fd_line, 'rate_pct', v_io.rate_pct, 'tax_amount', coalesce(v_fd_tax, 0), 'account_id', v_fd.account_id, 'account_code', v_fd.account_code);
    end if;
    if v_kind = 'product' and not v_ref then                                                                  -- surcharge-2b(묶음 7): 그 상품의 인보이스 surcharge 줄이 있으면 크레딧 surcharge 줄을 자동으로 · 개당은 인보이스 줄의 것(문서는 문서에서) · 세금은 그 줄 세율로 따로 · 계정 복사 · 물건값(v_lines_amt) · 리스탁킹 피 바탕(v_product_amt) 밖
      select * into v_sc from public.so_invoice_line il where il.invoice_id = v_inv.id and il.kind = 'surcharge' and il.so_line_id = v_il.so_line_id;
      if v_sc.id is not null then
        v_sc_line := public.so_line_surcharge_total(v_sc.unit_price, v_qty);
        select coalesce(sum(cl.amount), 0) into v_sc_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_sc.id and c.status = 'issued';
        if v_sc_already + v_sc_line > v_sc.amount then raise exception 'Invoice % surcharge of line % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_sc_already, v_sc.amount, v_sc.amount - v_sc_already; end if;
        v_sc_tax := public.so_tax_amount(v_sc_line, v_io.rate_pct);
        v_ln := v_ln + 1;  v_sc_amt := v_sc_amt + v_sc_line;  v_tax_amt := v_tax_amt + coalesce(v_sc_tax, 0);
        v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'surcharge', 'so_invoice_line_id', v_sc.id, 'so_line_id', v_sc.so_line_id, 'product_id', v_product_id, 'sku', v_sc.sku, 'description', v_sc.description,
                                                 'qty_returned', v_qty, 'unit_price', v_sc.unit_price, 'amount', v_sc_line, 'rate_pct', v_io.rate_pct, 'tax_amount', coalesce(v_sc_tax, 0), 'account_id', v_sc.account_id, 'account_code', v_sc.account_code);
      end if;
    end if;
    if v_kind = 'product' and v_combo is not null then                                                             -- asm-2b2(묶음 7 · 판정 245): 구성품 크레딧 줄 — 콤보 n 개 ⇒ 구성품마다 n × combo_qty 가 재고로(제 칸 · 또는 안 돌아온 사유) · 금액 0 · 원장(credit_in)은 이 줄들만 · 원가 갈래 ① 은 구성품 SKU 의 소비 기록으로
      for cj in select c2.v from jsonb_array_elements(v_combo) with ordinality c2(v, ord) order by c2.ord loop
        select * into v_cpr from public.product pr where pr.id = nullif(cj->>'product_id', '')::uuid;
        if v_cpr.id is null then select * into v_cpr from public.product pr where pr.sku = cj->>'sku'; end if;
        if v_cpr.id is null then raise exception 'Component % of combo % is not a product any more — nothing was saved', cj->>'sku', v_sku; end if;
        select cx into v_cov from jsonb_array_elements(coalesce(nullif(x->'components', 'null'::jsonb), '[]'::jsonb)) cx where nullif(trim(cx->>'sku'), '') = cj->>'sku' limit 1;
        v_cq := v_qty * (cj->>'qty_per_combo')::numeric;
        v_bin := null;  v_bin_id := null;  v_bin_name := null;  v_est := null;  v_nr_note := null;
        v_nr := coalesce(nullif(trim(v_cov->>'not_restocked_reason'), ''), v_def_nr);
        if v_nr is not null then
          if v_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
          v_nr_note := coalesce(nullif(trim(v_cov->>'not_restocked_note'), ''), v_def_note);
          if v_nr = 'other' and v_nr_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
        else
          v_bin_name := coalesce(nullif(trim(v_cov->>'restock_bin'), ''), v_def_bin);
          if v_bin_name is null then
            v_bin_name := public.ims_last_bin(array[coalesce(v_cpr.parent_product_id, v_cpr.id)], v_w.id) -> coalesce(v_cpr.parent_product_id, v_cpr.id)::text ->> 'bin';
            if v_bin_name is null then raise exception 'No bin known for % (component of combo %) in % — pick a restock bin for it in components[] (or mark it not restocked) — nothing was saved', v_cpr.sku, v_sku, v_w.name; end if;
          end if;
          select * into v_bin from public.ref_bin rb where rb.warehouse_id = v_w.id and rb.name = v_bin_name;
          if v_bin.id is null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bin_name, v_w.name; end if;
          if not v_bin.is_active then v_warn := array_append(v_warn, 'inactive_bin:' || v_bin_name); end if;
          v_bin_id := v_bin.id;  v_restock_n := v_restock_n + 1;
          select sum(cs.qty * cs.unit_cost) / nullif(sum(cs.qty), 0) into v_est
            from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
           where cs.doc_type = 'sale' and cs.reason = 'sale' and l.sku = coalesce((select pp.sku from public.product pp where pp.id = v_cpr.parent_product_id), v_cpr.sku)
             and cs.doc_number = (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id));
        end if;
        v_ln := v_ln + 1;
        v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'product', 'so_invoice_line_id', null, 'so_line_id', nullif(cj->>'so_line_id', '')::uuid, 'product_id', v_cpr.id, 'sku', v_cpr.sku, 'description', coalesce(cj->>'description', v_cpr.name),
                                                 'qty_returned', v_cq, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                                 'unit_price', 0, 'amount', 0, 'rate_pct', v_rate, 'tax_amount', 0, 'account_id', v_acct.id, 'account_code', v_acct.code,
                                                 'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_cq * coalesce(v_cpr.pack_factor, 1), 6) end,
                                                 'combo_parent_line_no', v_parent_ln, 'combo_qty', (cj->>'qty_per_combo')::numeric, 'combo_sku', v_sku);
      end loop;
    end if;
  end loop;

  -- ═══ crn-2 판정 603 · 611 · 613 · 614: 가격 조정 줄(둘째 바퀴) — 인보이스 줄: 층(낸 단가 = 오더 할인 뒤 · 앞선 조정이 있으면 그 단가)에서 새 단가보다 비싼 가장 낮은 층 하나 · 수량은 그 층 안에서만(넘치면 나눠 보내라) ·
  --     참조 크레딧: 낸 단가 · 새 단가 · 수량을 손으로 · 금액 = (낸 − 새) × 수량 · 세율 = 그 줄(또는 규칙) · 계정 = 그 인보이스 줄(614 · 참조는 _98_) · 재고 0 · 거울 · surcharge · 운임 할인 · 피 기준에 안 들어간다 ═══
  for x in select t from jsonb_array_elements(p->'lines') t where t->>'kind' = 'price_adjustment' loop
    v_il := null;  v_io := null;  v_pr := null;  v_acct := null;  v_tier := null;  v_il_id := null;  v_so_line_id := null;  v_product_id := null;  v_sku := null;  v_desc := null;
    v_qty := nullif(x->>'qty', '')::numeric;  v_after := nullif(x->>'new_unit_price', '')::numeric;  v_acct_id := nullif(x->>'account_id', '')::uuid;
    if v_qty is null or v_qty <= 0 then raise exception 'A price adjustment line needs qty > 0 — nothing was saved'; end if;
    if v_after is null or v_after <= 0 then raise exception 'A price adjustment line needs new_unit_price above 0 — to write the goods off entirely use a product line marked not returned, or an other line — nothing was saved'; end if;
    if v_acct_id is not null then
      select * into v_acct from public.ref_account a where a.id = v_acct_id;
      if v_acct.id is null then raise exception 'Account % not found — nothing was saved', v_acct_id; end if;
    end if;
    if v_ref then
      v_sku := nullif(trim(x->>'sku'), '');
      if v_sku is null then raise exception 'A reference credit price adjustment line needs sku — nothing was saved'; end if;
      select * into v_pr from public.product pr where pr.sku = v_sku;
      if v_pr.id is null then raise exception 'Product % not found — nothing was saved', v_sku; end if;
      v_before := nullif(x->>'paid_unit_price', '')::numeric;
      if v_before is null or v_before < 0 then raise exception 'A reference credit price adjustment line needs paid_unit_price (the price on the paper invoice) — nothing was saved'; end if;
      if v_after >= v_before then raise exception 'New unit price % is not below the paid unit price % — nothing was saved', trim_scale(v_after), trim_scale(v_before); end if;
      v_rate := v_rule.rate_pct;  v_product_id := v_pr.id;  v_desc := v_pr.name;
      if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_98_'; end if;
    else
      v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
      if v_il_id is null then raise exception 'A price adjustment line needs so_invoice_line_id (the invoice line being adjusted) — nothing was saved'; end if;
      select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'product';
      if v_il.id is null then raise exception 'Invoice line % is not a product line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
      if v_il.combo_components is not null then raise exception 'Invoice % line % (%) is a combo — a price adjustment on a combo is not supported; use an other line — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku; end if;
      if exists (select 1 from public.so_line sl where sl.id = v_il.so_line_id and sl.bgrade_bin_id is not null) then v_warn := array_append(v_warn, 'final_sale:' || v_il.sku); end if;   -- bgr-1d: 가격 조정도 같은 경고
      select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
      if not (v_tiers ? v_il.id::text) then v_tiers := v_tiers || jsonb_build_object(v_il.id::text, public.so_credit_line_state(v_il.id)->'tiers'); end if;
      if not exists (select 1 from jsonb_array_elements(v_tiers->(v_il.id::text)) t where (t->>'qty')::numeric > 0) then
        raise exception 'Invoice % line % (%): nothing left to adjust — all % were returned — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, trim_scale(v_il.qty);
      end if;
      select t into v_tier from jsonb_array_elements(v_tiers->(v_il.id::text)) t where (t->>'qty')::numeric > 0 and (t->>'unit_price')::numeric > v_after order by (t->>'unit_price')::numeric limit 1;
      if v_tier is null then
        raise exception 'Invoice % line % (%): new unit price % is not below the current unit price % — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, trim_scale(v_after),
          trim_scale((select min((t->>'unit_price')::numeric) from jsonb_array_elements(v_tiers->(v_il.id::text)) t where (t->>'qty')::numeric > 0));
      end if;
      v_before := (v_tier->>'unit_price')::numeric;
      if v_qty > (v_tier->>'qty')::numeric then
        raise exception 'Invoice % line % (%): only % can be adjusted at % — split the adjustment (% at %%s%, the rest at the next price level) — nothing was saved',
          v_inv.invoice_number, v_il.line_no, v_il.sku, trim_scale((v_tier->>'qty')::numeric), trim_scale(v_before), trim_scale((v_tier->>'qty')::numeric), trim_scale(v_before);
      end if;
      v_take := public.so_credit_tiers_take(v_tiers->(v_il.id::text), v_qty, v_after);
      v_tiers := v_tiers || jsonb_build_object(v_il.id::text, public.so_credit_tiers_add(v_take->'tiers', v_qty, v_after));
      v_rate := v_io.rate_pct;  v_sku := v_il.sku;  v_so_line_id := v_il.so_line_id;  v_desc := v_il.description;
      select sl.product_id into v_product_id from public.so_line sl where sl.id = v_il.so_line_id;
      if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;   -- 판정 614: 그 판매 줄의 매출 계정
    end if;
    v_amount := round((v_before - v_after) * v_qty, 2);  v_tax := public.so_tax_amount(v_amount, v_rate);
    v_ln := v_ln + 1;  v_lines_amt := v_lines_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
    v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'price_adjustment', 'so_invoice_line_id', v_il_id, 'so_line_id', v_so_line_id, 'product_id', v_product_id, 'sku', v_sku,
                                             'description', format('Price adjustment %s → %s', trim_scale(v_before), trim_scale(v_after)) || coalesce(' — ' || v_desc, ''),
                                             'qty_adjusted', v_qty, 'unit_price_before', v_before, 'unit_price_after', v_after, 'unit_price', v_before - v_after,
                                             'amount', v_amount, 'rate_pct', v_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code);
  end loop;
  if v_adj_n > 0 and v_ret_n = 0 and v_reason <> 'price_adjustment' then v_warn := array_append(v_warn, 'reason_not_price_adjustment'); end if;          -- crn-2 §2-4: 경고만
  if v_reason = 'price_adjustment' and v_ret_n > 0 then v_warn := array_append(v_warn, 'reason_price_adjustment_with_returns'); end if;

  -- crn-1 판정 602 · crn-0 §2-5: 참조 크레딧 경고 — 늘 manual_unit_price(인보이스 없이 넣은 단가 · 화면이 크게) · 같은 손님 · 같은 참조 번호(대소문자 · 앞뒤 공백 무시) · 같은 SKU 의 앞선 발행 크레딧이 있으면 reference_seen:<CR 번호들>(막지 않는다)
  if v_ref then
    v_warn := array_append(v_warn, 'manual_unit_price');
    select string_agg(distinct c2.credit_number, ', ') into v_seen
      from public.so_credit c2 join public.so_credit_line l2 on l2.credit_id = c2.id
     where c2.customer_id = v_cust and c2.status = 'issued' and lower(trim(c2.ref_invoice_number)) = lower(v_ref_inv)
       and l2.kind = 'product' and l2.sku in (select le->>'sku' from jsonb_array_elements(v_lines) le where le->>'kind' = 'product');
    if v_seen is not null then v_warn := array_append(v_warn, 'reference_seen:' || v_seen); end if;
  end if;

  -- dsc-3b 판정 325 · 316: 인보이스 거울 — 인보이스-오더마다 오더 할인 % 가 있으면 그 오더의 제품 환불액에 음수 줄 하나(세금 따로 · 계정 = 그 인보이스의 order_discount 줄) · surcharge 는 기준 밖(인보이스와 같다) · Cin7 크레딧은 해당 없음
  if not v_ref then
    for v_od in
      select io.id as io_id, io.so_number, io.order_discount_pct as pct, io.rate_pct, sum(coalesce((v_odb->>(le->>'line_no'))::numeric, (le->>'amount')::numeric)) as amt   -- crn-2 판정 611 · 613: 조정된 몫은 거울 기준에서 뺀다(그 몫은 새 단가 그대로)
      from jsonb_array_elements(v_lines) le join public.so_invoice_line il on il.id = nullif(le->>'so_invoice_line_id', '')::uuid join public.so_invoice_order io on io.id = il.invoice_order_id join public.so_line sl on sl.id = il.so_line_id   -- od-1
      where le->>'kind' = 'product' and coalesce(io.order_discount_pct, 0) > 0 and not public.so_line_manual(sl)   -- od-1 판정 542 · 544: 손으로 정한 줄은 오더 할인을 받지 않았으니 되돌릴 몫도 없다
      group by io.id, io.so_number, io.order_discount_pct, io.rate_pct order by io.so_number
    loop
      v_amount := -round(v_od.amt * v_od.pct / 100, 2);  v_tax := public.so_tax_amount(v_amount, v_od.rate_pct);
      select * into v_od_il from public.so_invoice_line il where il.invoice_order_id = v_od.io_id and il.kind = 'order_discount' limit 1;
      v_ln := v_ln + 1;  v_od_amt := v_od_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'order_discount', 'so_invoice_line_id', v_od_il.id, 'description', format('Order discount %s%% (%s)', v_od.pct, v_od.so_number),
                                               'amount', v_amount, 'rate_pct', v_od.rate_pct, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_od_il.account_id, 'account_code', v_od_il.account_code);
    end loop;
  end if;

  -- 둘째 바퀴 — Restocking fee(판정 4·5·7 · 0-8): 기본 −round(Σ제품 × pct/100, 2) · 계정 = 지정 → 설정 → 거부 · 세율 = 첫 제품 줄(섞이면 경고) · 세금도 음수 · dsc-3b 판정 325: 기준 = 제품 환불액 − 오더 할인 몫(손님이 실제 낸 값)
  v_first_rate := case when v_ref then v_rule.rate_pct else v_rates[1] end;
  if v_fee_lines > 0 then
    if v_fee_lines > 1 then raise exception 'Only one restocking_fee line per credit note — nothing was saved'; end if;
    if (select count(distinct r) from unnest(v_rates) r) > 1 then v_warn := array_append(v_warn, 'fee_rate_mixed'); end if;
    for x in select t from jsonb_array_elements(p->'lines') t where t->>'kind' = 'restocking_fee' loop
      v_acct := null;  v_acct_id := nullif(x->>'account_id', '')::uuid;
      if v_acct_id is not null then select * into v_acct from public.ref_account a where a.id = v_acct_id;
      elsif v_fee_acct_code is not null then select * into v_acct from public.ref_account a where a.code = v_fee_acct_code; end if;
      if v_acct.id is null then raise exception 'A restocking fee line needs account_id — no default account is set (inv_config so_credit_restock_fee_account_code) — nothing was saved'; end if;
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null then v_amount := -round((v_product_amt + v_od_amt) * coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct, 0) / 100, 2); end if;   -- dsc-3b 판정 325: v_od_amt 는 음수
      if v_amount > 0 then raise exception 'A restocking fee reduces the credit — amount must be ≤ 0 (got %) — nothing was saved', v_amount; end if;
      v_tax := public.so_tax_amount(v_amount, v_first_rate);
      v_ln := v_ln + 1;  v_fee_amt := v_fee_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'restocking_fee', 'description', coalesce(nullif(trim(x->>'description'), ''), format('Restocking fee %s%%', coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct))),
                                               'amount', v_amount, 'rate_pct', v_first_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code);
    end loop;
  end if;
  -- 알림(판정 5) — 원 인보이스 발행일 + N일이 지났고 수수료 줄이 없으면 「대상」만 알린다(자동으로 붙이지 않는다)
  if v_origin_on is null then v_warn := array_append(v_warn, 'fee_window_unknown');
  elsif v_fee_days is not null and v_on - v_origin_on > v_fee_days and v_fee_lines = 0 and v_product_amt > 0 then
    v_warn := array_append(v_warn, 'restock_fee_window:' || (v_on - v_origin_on)::text);
    v_fee_sugg := jsonb_build_object('days_since_invoice', v_on - v_origin_on, 'pct', v_fee_pct, 'amount', -round((v_product_amt + v_od_amt) * coalesce(v_fee_pct, 0) / 100, 2), 'account_code', v_fee_acct_code);   -- dsc-3b 판정 325
  end if;
  if v_ln = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  if not p_commit then
    return jsonb_build_object('committed', false, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code, 'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                              'origin', case when v_ref then jsonb_build_object('ref_invoice_number', v_ref_inv, 'ref_order_number', v_ref_ord, 'ref_invoice_date', v_ref_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct, 'tax_rule_source', v_tax_src)
                                             else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                              'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_lines_amt, 'order_discount_amount', v_od_amt, 'freight_discount_amount', v_fd_amt, 'fee_amount', v_fee_amt, 'surcharge_amount', v_sc_amt, 'tax_amount', v_tax_amt, 'total', v_lines_amt + v_od_amt + v_fd_amt + v_fee_amt + v_sc_amt + v_tax_amt, 'restock_lines', v_restock_n),
                              'fee_suggested', v_fee_sugg, 'ledger', null, 'warnings', to_jsonb(v_warn));
  end if;

  insert into public.so_credit (customer_id, currency_id, currency_code, invoice_id, ref_invoice_number, ref_order_number, ref_invoice_date, origin_invoice_on, reason, note,
                                warehouse_id, warehouse_name, tax_rule_id, tax_rule, rate_pct, issued_on, issued_by, lines_amount, order_discount_amount, freight_discount_amount, fee_amount, surcharge_amount, tax_amount, total, created_by, updated_by)   -- fr-3
  values (v_cust, v_cur.id, v_cur.code, v_inv.id, v_ref_inv, v_ref_ord, v_ref_date, v_origin_on, v_reason, nullif(trim(p->>'note'), ''),
          v_w.id, v_w.name, v_rule.id, v_rule.name, v_rule.rate_pct, v_on, v_staff, v_lines_amt, v_od_amt, v_fd_amt, v_fee_amt, v_sc_amt, v_tax_amt, v_lines_amt + v_od_amt + v_fd_amt + v_fee_amt + v_sc_amt + v_tax_amt, v_staff, v_staff)   -- fr-3
  returning * into v_cr;
  for e in select t from jsonb_array_elements(v_lines) t loop
    insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, so_line_id, product_id, sku, description, qty_returned, restock_bin_id, restock_bin, not_restocked_reason, not_restocked_note,
                                       unit_price, amount, rate_pct, tax_amount, account_id, account_code, updated_by, combo_credit_line_id, combo_qty, combo_components,
                                       qty_adjusted, unit_price_before, unit_price_after)                                                                                                -- crn-2
    values (v_cr.id, (e->>'line_no')::int, e->>'kind', nullif(e->>'so_invoice_line_id', '')::uuid, nullif(e->>'so_line_id', '')::uuid, nullif(e->>'product_id', '')::uuid, e->>'sku', e->>'description',
            nullif(e->>'qty_returned', '')::numeric, nullif(e->>'restock_bin_id', '')::uuid, e->>'restock_bin', e->>'not_restocked_reason', e->>'not_restocked_note',
            nullif(e->>'unit_price', '')::numeric, (e->>'amount')::numeric, nullif(e->>'rate_pct', '')::numeric, (e->>'tax_amount')::numeric, nullif(e->>'account_id', '')::uuid, e->>'account_code', v_staff,
            (v_idmap->>(e->>'combo_parent_line_no'))::uuid, nullif(e->>'combo_qty', '')::numeric, nullif(e->'combo_components', 'null'::jsonb),                   -- asm-2b2: 구성품 줄은 앞서 넣은 콤보 줄(line_no → id)에 매단다 · 콤보 줄은 includes 를 든다
            nullif(e->>'qty_adjusted', '')::numeric, nullif(e->>'unit_price_before', '')::numeric, nullif(e->>'unit_price_after', '')::numeric)                                              -- crn-2
    returning id into v_il_id;
    v_idmap := v_idmap || jsonb_build_object((e->>'line_no'), v_il_id);
  end loop;
  if v_restock_n > 0 then
    v_ledger := public.inv_post_credit(v_cr.id, v_on);
    v_warn := v_warn || coalesce((select array_agg(t.w) from jsonb_array_elements_text(coalesce(v_ledger->'warnings', '[]'::jsonb)) as t(w)), '{}');
  end if;

  return jsonb_build_object('committed', true, 'credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', v_cr.status, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code,
                            'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                            'origin', case when v_ref then jsonb_build_object('ref_invoice_number', v_ref_inv, 'ref_order_number', v_ref_ord, 'ref_invoice_date', v_ref_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct, 'tax_rule_source', v_tax_src)
                                           else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                            'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_cr.lines_amount, 'order_discount_amount', v_cr.order_discount_amount, 'freight_discount_amount', v_cr.freight_discount_amount, 'fee_amount', v_cr.fee_amount, 'surcharge_amount', v_cr.surcharge_amount, 'tax_amount', v_cr.tax_amount, 'total', v_cr.total, 'restock_lines', v_restock_n),
                            'fee_suggested', v_fee_sugg, 'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ ims_bin_bgrade_refuse 재발행 — 원본 DB 바이트(md5 f4acbd8dcaf73f6c8988ac11cde0acf7) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1d」) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.ims_bin_bgrade_refuse()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- bgr-1b: tg_argv = (칸 이름, 사람 말 길 이름, 'move' 면 B급 셸 표지가 켜졌을 때 통과) · 바뀌지 않은 update 는 보지 않는다
declare v_id uuid;  v_name text;
begin
  v_id := nullif(to_jsonb(new) ->> tg_argv[0], '')::uuid;
  if v_id is null then return new; end if;
  if tg_op = 'UPDATE' and nullif(to_jsonb(old) ->> tg_argv[0], '')::uuid is not distinct from v_id then return new; end if;
  if tg_argv[2] = 'move' and coalesce(current_setting('ims.bgrade_move', true), '') = 'on' then return new; end if;
  select rb.name into v_name from public.ref_bin rb where rb.id = v_id and rb.is_bgrade;
  if v_name is null then return new; end if;
  if tg_table_name = 'so_credit_line' then                                                     -- bgr-1d 판정 649 · 650: 반품은 받은 창고의 활성 B급 칸으로 받을 수 있다
    if exists (select 1 from public.ref_bin rb join public.so_credit c on c.warehouse_id = rb.warehouse_id where rb.id = v_id and rb.is_active and c.id = nullif(to_jsonb(new) ->> 'credit_id', '')::uuid) then return new; end if;
    raise exception using errcode = 'IM637', message = format('Credit restock: B-grade bin %s is switched off or belongs to another store — pick an active B-grade bin of the store taking the return, or a regular bin — nothing was saved', v_name);
  end if;
  raise exception using errcode = 'IM637', message = format('%s: bin %s is a B-grade bin — %s — nothing was saved', tg_argv[1], v_name,
    case when tg_argv[2] = 'move' then 'use Move to B-grade / Move back for B-grade bins' else 'pick a regular bin; B-grade stock comes in only with Move to B-grade or a stock adjustment' end);
end $function$;

-- ═══ inv_ledger_bgrade_guard 재발행 — 원본 DB 바이트(md5 d7c0960a1f5cccee8a0b4fd4ad3fa39d) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1d」) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.inv_ledger_bgrade_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- bgr-1b 판정 635 · 638 · 639: IMS 사건(source ims)이 B급 칸을 건드리면 셋만 통과 — 조정(adjust_existing · adjust_new) · 판매 출고(sale_out 음수 · POS 1c) · 표지 켠 칸 옮기기(bin_move · B급 셸)
--   Cin7 적재(source cin7 · manual)는 보지 않는다 · 조정이 잔고 0 이하에서 B급 칸에 넣으면 그 칸 · SKU 의 옛 B급 값을 지운다(판정 644 — 「값 없음」으로 들어온다)
declare v_bin uuid;
        v_lbin uuid;                                                                                -- bgr-1c: 판매 출고 줄의 B급 칸(정상 줄이면 null)
begin
  if new.source is distinct from 'ims' then return new; end if;                                       -- bgr-1c: 칸 없는 판매 출고도 아래 B급 줄 검사를 거친다(옛 줄은 칸 '' 도 여기서 돌려보냈다)
  if new.event_type = 'sale_out' and new.raw ? 'so_line_id' then
    select l.bgrade_bin_id into v_lbin from public.so_line l where l.id = (new.raw->>'so_line_id')::uuid;   -- bgr-1c 판정 635 · 647
  end if;
  if coalesce(new.bin, '') = '' and v_lbin is null then return new; end if;                          -- bgr-1c
  select rb.id into v_bin from public.ref_bin rb join public.ref_warehouse w on w.id = rb.warehouse_id where w.name = new.warehouse and rb.name = new.bin and rb.is_bgrade;
  if v_lbin is not null and v_bin is distinct from v_lbin then                                       -- bgr-1c: B급 줄은 그 B급 칸에서만 나간다(정상 칸 · 다른 B급 칸 · 칸 없음 거부)
    raise exception using errcode = 'IM637', message = format('B-grade line (%s %s) ships only from its B-grade bin %s, not from %s — nothing was saved',
      new.sku, new.qty_delta, (select rb.name from public.ref_bin rb where rb.id = v_lbin), coalesce(nullif(new.bin, ''), '(no bin)'));
  end if;
  if v_bin is null then return new; end if;
  if new.event_type = 'credit_in' then                                                                -- bgr-1d 판정 649 · 650
    if new.qty_delta > 0 and exists (select 1 from public.so_credit_line cl where cl.id = nullif(new.raw->>'credit_line_id', '')::uuid and cl.restock_bin_id = v_bin) then
      if public.inv_adjust_ledger(new.warehouse, new.bin, new.sku) <= 0 then                         -- 빈 칸에 반품이 들어오면 옛 값은 죽은 값 — 지운다(「값 없음」 · 조정 갈래와 같다)
        delete from public.bgrade_price bp using public.product p where bp.bin_id = v_bin and bp.product_id = p.id and p.sku = new.sku;
      end if;
      return new;
    end if;
    if new.qty_delta < 0 and new.raw->>'kind' = 'credit_in_reversal'
       and exists (select 1 from public.inv_ledger g where g.id = nullif(new.raw->>'reversal_of', '')::bigint and g.event_type = 'credit_in' and g.warehouse = new.warehouse and g.bin = new.bin) then
      return new;                                                                                     -- 크레딧 취소 — 그 사이 팔렸으면 칸이 음수가 된다(정상 칸과 같다)
    end if;
  end if;
  if new.event_type in ('adjust_existing', 'adjust_new') then
    if new.qty_delta > 0 and public.inv_adjust_ledger(new.warehouse, new.bin, new.sku) <= 0 then
      delete from public.bgrade_price bp using public.product p where bp.bin_id = v_bin and bp.product_id = p.id and p.sku = new.sku;
    end if;
    return new;
  end if;
  if new.event_type = 'sale_out' and new.qty_delta < 0 and v_lbin = v_bin then return new; end if;   -- bgr-1c 판정 635: B급 칸의 판매 출고는 그 칸의 B급 줄만(1b 는 어떤 판매든)
  if new.raw->>'kind' = 'bin_move' and coalesce(current_setting('ims.bgrade_move', true), '') = 'on' then return new; end if;
  raise exception using errcode = 'IM637', message = format('Bin %s in %s is a B-grade bin — stock goes in or out of it only with Move to B-grade / Move back, a stock adjustment or a POS sale (%s %s %s) — nothing was saved',
    new.bin, new.warehouse, new.event_type, new.sku, new.qty_delta);
end $function$;

-- ═══ so_line_bgrade_set 재발행 — 원본 DB 바이트(md5 4ade7f51c85189949e18d604cb44e40b) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1d」) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.so_line_bgrade_set(p_line_id uuid, p_bin_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- bgr-1c 판정 634 ② · 642 · 644: POS 줄의 「B-grade」 — 값 = 그 칸의 B급 값(살아 있는 값만) · 칸 생략: 잔고 있는 B급 칸이 하나면 그 칸 · 여럿이면 action choose(저장 없음) · 없으면 거부
--   같은 오더에 같은 칸 · 같은 SKU 의 B급 줄이 있으면 그 줄에 수량을 더하고 이 줄을 지운다 · 정상 줄과는 합치지 않는다
declare v_staff uuid;  v_line public.so_line%rowtype;  v_so public.so%rowtype;  v_p public.product%rowtype;  v_b public.ref_bin%rowtype;  v_wh text;
        v_c jsonb;  v_bal numeric;  v_price numeric;  v_other public.so_line%rowtype;  v_out public.so_line%rowtype;  v_action text;  v_merge boolean;
begin
  perform public.ims_require_write('sales', 'saved');
  v_staff := public.so_current_staff();
  select * into v_line from public.so_line where id = p_line_id for update;
  if not found then raise exception 'Order line not found — nothing was saved'; end if;
  v_so := public.so_require_draft(v_line.so_id, 'saved');
  if v_so.channel <> 'pos' then raise exception 'B-grade is sold at the POS only — order % is a % order — nothing was saved', v_so.so_number, v_so.channel; end if;
  if v_line.combo_line_id is not null or exists (select 1 from public.so_line c where c.combo_line_id = v_line.id) then
    raise exception 'Line % is part of a combo — B-grade is for single items — nothing was saved', v_line.line_no;
  end if;
  select * into v_p from public.product p where p.id = v_line.product_id;
  if v_p.parent_product_id is not null then raise exception 'Line % (%) is a set or pack — B-grade is sold by the single unit — nothing was saved', v_line.line_no, v_line.sku; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_so.location_id;
  if p_bin_id is null then
    select coalesce(jsonb_agg(jsonb_build_object('bin_id', x.id, 'bin', x.name, 'price', x.price, 'has_price', x.price is not null, 'qty', x.bal) order by x.price nulls last, x.name), '[]'::jsonb) into v_c
      from (select rb.id, rb.name, bp.price, public.inv_adjust_ledger(v_wh, rb.name, v_p.sku) as bal
              from public.ref_bin rb left join public.bgrade_price bp on bp.bin_id = rb.id and bp.product_id = v_p.id
             where rb.is_bgrade and rb.is_active and rb.warehouse_id = v_so.location_id) x
     where x.bal > 0;
    if jsonb_array_length(v_c) = 0 then raise exception 'No B-grade stock of % at % — nothing was saved', v_p.sku, v_wh; end if;
    if jsonb_array_length(v_c) > 1 then
      return jsonb_build_object('action', 'choose', 'so_number', v_so.so_number, 'line_id', v_line.id, 'sku', v_p.sku, 'candidates', v_c,
                                'message', 'This item is in more than one B-grade bin — pick the bin (its price) — nothing was saved');
    end if;
    p_bin_id := (v_c->0->>'bin_id')::uuid;
  end if;
  select * into v_b from public.ref_bin rb where rb.id = p_bin_id;
  if not found then raise exception 'Bin not found (%) — nothing was saved', p_bin_id; end if;
  if not v_b.is_bgrade then raise exception 'Bin % is not a B-grade bin — nothing was saved', v_b.name; end if;
  if v_b.warehouse_id is distinct from v_so.location_id then raise exception 'Bin % is at another store — nothing was saved', v_b.name; end if;
  v_bal := public.inv_adjust_ledger(v_wh, v_b.name, v_p.sku);
  if v_bal <= 0 then raise exception 'No B-grade stock of % in bin % — its B-grade price is no longer live; put found stock in with an adjustment and set a price first — nothing was saved', v_p.sku, v_b.name; end if;
  select bp.price into v_price from public.bgrade_price bp where bp.bin_id = v_b.id and bp.product_id = v_p.id;
  if v_price is null then raise exception 'No B-grade price for % in bin % — ask a manager to set it (B-grade stock without a price cannot be sold) — nothing was saved', v_p.sku, v_b.name; end if;
  if v_line.bgrade_bin_id = v_b.id then
    return jsonb_build_object('action', 'unchanged', 'so_number', v_so.so_number, 'line', to_jsonb(v_line), 'removed_line_id', null, 'bin_id', v_b.id, 'bin', v_b.name,
                              'price', v_line.unit_price, 'bin_qty', v_bal, 'total', public.so_line_total(v_line), 'warnings', '[]'::jsonb);
  end if;
  select * into v_other from public.so_line l where l.so_id = v_so.id and l.id <> v_line.id and l.bgrade_bin_id = v_b.id and l.product_id = v_p.id order by l.line_no limit 1 for update;
  v_merge := found;                                                                       -- perform 이 FOUND 를 덮기 전에 담는다
  perform set_config('ims.bgrade_line', 'on', true);
  if v_merge then
    update public.so_line set qty_ordered = qty_ordered + v_line.qty_ordered, updated_by = v_staff where id = v_other.id returning * into v_out;
    delete from public.so_line where id = v_line.id;
    v_action := 'merged';
  else
    update public.so_line set bgrade_bin_id = v_b.id, unit_price = v_price, discount_pct = null, discount_source = null, deal_line_id = null, free_reason = null,
                              surcharge_pct = null, surcharge_amount = null, surcharge_label = null,                    -- bgr-1d 판정 648: B급 값이 모든 값(세금만 더한다)
                              price_override = true, price_set_by = v_staff, price_set_at = now(), updated_by = v_staff
     where id = v_line.id returning * into v_out;
    v_action := 'set';
  end if;
  perform set_config('ims.bgrade_line', '', true);
  return jsonb_build_object('action', v_action, 'so_number', v_so.so_number, 'line', to_jsonb(v_out), 'removed_line_id', case when v_action = 'merged' then v_line.id end,
                            'bin_id', v_b.id, 'bin', v_b.name, 'price', v_price, 'bin_qty', v_bal, 'total', public.so_line_total(v_out),
                            'warnings', case when v_out.qty_ordered > v_bal then '["over_bgrade_stock"]'::jsonb else '[]'::jsonb end);
end $function$;

-- ═══ so_line_bgrade_clear 재발행 — 원본 DB 바이트(md5 101713c2ff23f2116da6a77704cb142f) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1d」) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.so_line_bgrade_clear(p_line_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- bgr-1c: B급 줄을 정상 줄로 되돌린다(sales 문 · draft) — 칸 · price_override 를 비우고 시스템 값으로 다시 견적
declare v_staff uuid;  v_line public.so_line%rowtype;  v_so public.so%rowtype;  v_out public.so_line%rowtype;
begin
  perform public.ims_require_write('sales', 'saved');
  v_staff := public.so_current_staff();
  select * into v_line from public.so_line where id = p_line_id for update;
  if not found then raise exception 'Order line not found — nothing was saved'; end if;
  v_so := public.so_require_draft(v_line.so_id, 'saved');
  if v_line.bgrade_bin_id is null then raise exception 'Line % is not a B-grade line — nothing was saved', v_line.line_no; end if;
  perform set_config('ims.bgrade_line', 'on', true);
  update public.so_line set bgrade_bin_id = null, price_override = false, price_set_by = null, price_set_at = null, updated_by = v_staff where id = v_line.id;
  update public.so_line l set surcharge_pct = d.surcharge_pct, surcharge_amount = d.surcharge_amount, surcharge_label = d.surcharge_label   -- bgr-1d 판정 648: 정상 줄로 돌아가면 so_line_add 와 같은 그룹 기본
    from public.so_line_surcharge_defaults(v_line.product_id, v_line.free_reason is not null) d where l.id = v_line.id;
  perform set_config('ims.bgrade_line', '', true);
  v_out := public.so_line_requote(v_line.id, v_line.qty_ordered, true);
  return jsonb_build_object('action', 'cleared', 'so_number', v_so.so_number, 'line', to_jsonb(v_out), 'total', public.so_line_total(v_out), 'warnings', '[]'::jsonb);
end $function$;

-- ═══ so_line_bgrade_guard 재발행 — 원본 DB 바이트(md5 180c0558c246c445bb613d660078aa43) + 더한 줄 · 바꾼 줄(줄 끝 「bgr-1d」) · 서명 · 권한 · comment 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.so_line_bgrade_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- bgr-1c 판정 635: B급 줄(bgrade_bin_id)은 so_line_bgrade_set · clear(표지 ims.bgrade_line)만 세우고 지운다 · 세울 때 POS · draft · 그 오더 창고의 B급 칸
declare v_flag boolean := coalesce(current_setting('ims.bgrade_line', true), '') = 'on';  v_s record;  v_ok boolean;
begin
  if tg_op = 'INSERT' then
    if new.bgrade_bin_id is not null and not v_flag then
      raise exception using errcode = 'IM638', message = format('B-grade lines are made only with the B-grade button on a POS line (%s) — nothing was saved', new.sku);
    end if;
    if new.split_from_line_id is not null and exists (select 1 from public.so_line l where l.id = new.split_from_line_id and l.bgrade_bin_id is not null) then
      raise exception using errcode = 'IM638', message = format('A B-grade line (%s) is not split or copied to another order — nothing was saved', new.sku);
    end if;
  else
    if new.bgrade_bin_id is distinct from old.bgrade_bin_id and not v_flag then
      raise exception using errcode = 'IM638', message = format('Line %s: B-grade is set or cleared only with the B-grade button on the POS — nothing was saved', old.line_no);
    end if;
    if old.bgrade_bin_id is not null and new.bgrade_bin_id is not null then
      if new.so_id is distinct from old.so_id then
        raise exception using errcode = 'IM638', message = format('Line %s is a B-grade line — it stays on its POS order — nothing was saved', old.line_no);
      end if;
      if not v_flag and (new.unit_price, new.discount_pct, new.discount_source, new.price_override, new.free_reason, new.deal_line_id, new.surcharge_pct, new.surcharge_amount, new.surcharge_label)   -- bgr-1d 판정 648: surcharge 칸도
                        is distinct from (old.unit_price, old.discount_pct, old.discount_source, old.price_override, old.free_reason, old.deal_line_id, old.surcharge_pct, old.surcharge_amount, old.surcharge_label) then
        raise exception using errcode = 'IM638', message = format('Line %s is a B-grade line — its price comes from the B-grade bin; change the bin price (reprice) or clear B-grade — nothing was saved', old.line_no);
      end if;
    end if;
  end if;
  if new.bgrade_bin_id is not null and (tg_op = 'INSERT' or new.bgrade_bin_id is distinct from old.bgrade_bin_id) then
    select s.channel, s.status, s.so_number, s.location_id into v_s from public.so s where s.id = new.so_id;
    if v_s.channel is distinct from 'pos' or v_s.status is distinct from 'draft' then
      raise exception using errcode = 'IM638', message = format('B-grade lines are POS only, on a draft order (%s is %s · %s) — nothing was saved', v_s.so_number, v_s.channel, v_s.status);
    end if;
    select exists (select 1 from public.ref_bin rb where rb.id = new.bgrade_bin_id and rb.is_bgrade and rb.warehouse_id = v_s.location_id) into v_ok;
    if not v_ok then
      raise exception using errcode = 'IM638', message = format('Bin for line %s is not a B-grade bin of this order''s store — nothing was saved', new.line_no);
    end if;
  end if;
  return new;
end $function$;
-- ═══ 착지 ═══
do $$
begin
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('doc_data_invoice', 'doc_data_invoice_fmt', 'doc_field_catalog', 'ims_bin_bgrade_refuse', 'inv_ledger_bgrade_guard', 'so_credit_issue', 'so_credit_prepare', 'so_line_bgrade_clear', 'so_line_bgrade_guard', 'so_line_bgrade_set'))
     <> 'doc_data_invoice=1ba3b5148de65436aae947af78b15736 doc_data_invoice_fmt=a0c3f58dbd760a01615ee7996556e7fb doc_field_catalog=7a9edf38a1903ddc3398a9df700882e8 ims_bin_bgrade_refuse=6fcfa6cb78bb7ffa074440d86f0d2534 inv_ledger_bgrade_guard=1bef648eb17180e5c89dfcae8db9b8b5 so_credit_issue=b226c668340b37531bd22361d00f6e04 so_credit_prepare=2f040018d15dabf5f18e90648aee5ce7 so_line_bgrade_clear=85c7ad7db90cb0a24a00a655127c7978 so_line_bgrade_guard=596a3bb53d35373961fcd06fa6f2857f so_line_bgrade_set=47c6b9f4329c4535e7ffd018e206c6d2' then raise exception 'bgr-1d landing check failed: bodies'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('doc_data_invoice', 'doc_data_invoice_fmt', 'doc_field_catalog', 'ims_bin_bgrade_refuse', 'inv_ledger_bgrade_guard', 'so_credit_issue', 'so_credit_prepare', 'so_line_bgrade_clear', 'so_line_bgrade_guard', 'so_line_bgrade_set')) <> 10 then raise exception 'bgr-1d landing check failed: overloads'; end if;
  if not ((public.doc_field_catalog('final_invoice')->'allowed') ? 'orders.lines.final_sale') or ((public.doc_field_catalog('ship_ready')->'allowed') ? 'orders.lines.final_sale') then
    raise exception 'bgr-1d landing check failed: catalog';
  end if;
end $$;
