-- supabase/migrations/20261108140000_doc_qty_1_totals.sql — doc-qty-1: 문서(SO · PROFORMA · INVOICE · Internal Receipt)에 수량 합계 열쇠 (2026-11-08 · 지시서 ~/asung/prompts/doc-qty-1.md · 이견 답 열셋)
-- 요청(직원 · 11-08): 「Sales Order, Proforma, Invoice 등 Document 에도 Product Total Quantity 가 보여지도록」 — 이 차수는 DB 열쇠만 · 판(template)은 뒤 차수에 대화 Claude 가 통째로 쓰고 Caleb 이 Settings → Documents 에서 올린다
-- 열쇠(kind 넷 sales_order · ship_ready · final_invoice · internal_receipt · credit_note 는 아님 · 이견 6): totals.line_count(제품 줄 수) · totals.qty_total(Σ 줄 수량 = 문서 줄의 수량 칸과 같은 값) · totals.qty_total_ea(Σ 수량 × pack_factor · qty_total 과 같으면 "" · Caleb 「다」)
--   + 인보이스 꼴 세 kind 는 오더마다 orders[].line_count · qty_total · qty_total_ea(이견 5 · 오더 여럿 인보이스 22 장 실재) · invoice.total_qty 는 무변(같은 값 · internal_receipt required · 이견 1)
-- 식 한 곳 = 새 함수 doc_qty_totals(원천 줄 배열 → 셋) · 부르는 곳 둘(fmt 세 kind · doc_data_so) — 이견 4 · 콤보 구성품 줄은 원천(so_proforma · so_invoice_preview · so_invoice_line)에 없어 「보이는 줄 = 센 줄」(이견 2) · 무상 줄은 센다 · charges 는 다른 배열
-- pack_factor 가 문서 줄 재료에 없어 적재 둘에 열쇠 하나씩(이견 3): doc_data_invoice(so_invoice_line.pack_factor) · so_invoice_preview(so_tax_preview 의 pack_factor) — so_invoice_issue 는 so_invoice_preview 를 부르지 않는다(호출 0 · 주석 2 · grep) · 돈 · 세금 무변 · sales_order 는 so_proforma 줄에 이미 있다
-- 몸 = DB prosrc 원본(2026-11-08 · fmt e2e64dfe · so 9b669a0e · catalog 7b8e242a · doc_data_invoice 5fcac178 · so_invoice_preview 6a36efcb) + 더한 줄: fmt 3 줄(문장 둘 · 옛 줄 무변) · catalog 2 줄 · doc_data_invoice · so_invoice_preview · so 는 그 줄 안에 열쇠 · 식 삽입(각 1 줄)
-- 시그니처 · invoker · volatility · search_path · acl 그대로(create or replace · drop 없음) · comment 는 끝에 [doc-qty-1] 덧 · doc_data(디스패처) · doc_data_credit · doc_data_ship_ready · so_invoice_issue · so_tax_preview · so_proforma 무접촉 · 판 · doc_template 무변
-- 검증 supabase/tests/doc_qty_1_check.sql(begin → rollback · 옛 = 새 · 값 · 카탈로그 ↔ 출력 · 옛 발행 = 새 발행 한 겹) · 적용은 Caleb(psql -1 · lock_timeout 5s · migration repair) · supabase db push 금지
-- ⚠️ jsonb_build_object 안에 「--」 줄 주석을 두지 마라(so-detail-keys-1) — 이 파일의 더한 주석은 문장 끝 · 제 줄에만
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

-- ═══ ① 식 한 곳 — doc_qty_totals ═══
create or replace function public.doc_qty_totals(p_lines jsonb)
 returns jsonb
 language sql
 immutable parallel safe
 set search_path to 'public', 'pg_temp'
as $function$
  select jsonb_build_object('line_count', count(*)::text,
                            'qty_total', public.doc_fmt_qty(coalesce(sum(x.q), 0)),
                            'qty_total_ea', case when coalesce(sum(x.q * x.pf), 0) = coalesce(sum(x.q), 0) then '' else public.doc_fmt_qty(coalesce(sum(x.q * x.pf), 0)) end)
  from (select (l->>'qty')::numeric as q, coalesce(nullif(l->>'pack_factor', '')::numeric, 1) as pf
        from jsonb_array_elements(case when jsonb_typeof(p_lines) = 'array' then p_lines else '[]'::jsonb end) l) x;
$function$;
revoke all on function public.doc_qty_totals(jsonb) from public, anon, authenticated;
comment on function public.doc_qty_totals(jsonb) is 'doc-qty-1 (2026-11-08) — 문서 제품 줄 배열(원천 jsonb · qty · pack_factor 숫자) → 합계 셋 글자: line_count = 줄 수 · qty_total = Σ qty(문서 줄의 수량 칸과 같은 값 · doc_fmt_qty) · qty_total_ea = Σ qty × coalesce(pack_factor, 1) — qty_total 과 같으면 ""(세트 줄이 있는 문서만 「Qty 2 (36 EA)」 · 「0 이면 빈칸」 과 같은 결 · 판에서 거르지 않는다) · 식 한 곳: doc_data_invoice_fmt(세 kind · 장 · 오더마다) · doc_data_so 가 같이 부른다 — 다른 길로 더하지 마라 · 콤보 줄은 세트 하나(구성품 줄은 원천 so_proforma · so_invoice_preview · so_invoice_line 에 없다) · 무상 줄은 센다 · charges 는 배열이 달라 안 센다';

-- ═══ ② 적재 — doc_data_invoice(so_invoice_line.pack_factor 한 열쇠) ═══
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
  if v_inv.kind = 'opening' then raise exception 'Invoice % was carried forward from the previous system — the original is in QuickBooks. It cannot be printed or mailed from IMS', v_inv.invoice_number; end if;   -- ar-2 판정 785: doc_data 한 곳(화면 인쇄 · 미리 보기 · 서버 PDF · 메일 자리표 전부)
  v_n := jsonb_build_object(
    'header', jsonb_build_object('number', v_inv.invoice_number, 'issued_on', v_inv.issued_on, 'due_on', v_inv.due_on, 'payment_term_name', v_inv.payment_term_name, 'currency_code', v_inv.currency_code, 'memo', v_inv.note,
                                 'bill_to_customer_id', v_inv.bill_to_customer_id,
                                 'bill_to', jsonb_build_object('name', v_inv.bill_to_name, 'line1', v_inv.bill_to_line1, 'line2', v_inv.bill_to_line2, 'city', v_inv.bill_to_city, 'state_province', v_inv.bill_to_state_province, 'postal_code', v_inv.bill_to_postal_code, 'country', v_inv.bill_to_country)),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object(
                 'so_number', o.so_number, 'reference', s.ref, 'carrier', s.carrier, 'tracking', s.tracking_number, 'tax_rule', o.tax_rule, 'order_discount_pct', o.order_discount_pct,
                 'ship_to', jsonb_build_object('company', o.ship_to_company, 'contact', o.ship_to_contact, 'phone', o.ship_to_phone, 'line1', o.ship_to_line1, 'line2', o.ship_to_line2, 'city', o.ship_to_city, 'state_province', o.ship_to_state_province, 'postal_code', o.ship_to_postal_code, 'country', o.ship_to_country),
                 'lines', (select coalesce(jsonb_agg(jsonb_build_object('product_id', sl.product_id, 'sku', l.sku, 'description', l.description, 'comment', sl.comments, 'unit', l.unit, 'qty', l.qty, 'pack_factor', l.pack_factor, 'list_price', l.list_price, 'discount_pct', l.discount_pct,
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
    'credits', (select coalesce(jsonb_agg(jsonb_build_object('credit_number', c.credit_number, 'issued_on', c.issued_on, 'amount', a.amount,
                                                             'reference', case when c.invoice_id = v_inv.id then null else coalesce((select oi.invoice_number from public.so_invoice oi where oi.id = c.invoice_id), c.ref_invoice_number) end)
                                          order by c.issued_on, c.credit_number, a.created_at), '[]'::jsonb)
                from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id
                where a.invoice_id = v_inv.id and a.voided_at is null and c.status = 'issued'),                                                                           -- doc-cr-1 판정 864: 이 인보이스에 걸린 살아 있는 크레딧(so_invoice_list cred · so_invoice_remaining 과 같은 조건) · reference = 원 인보이스 번호(IMS invoice_number → Cin7 ref_invoice_number) · 자기 자신이면 null
    'totals', jsonb_build_object('order_discount', v_inv.order_discount_amount, 'surcharge', v_inv.surcharge_amount, 'taxable', v_inv.taxable_amount, 'tax', v_inv.tax_amount, 'total', v_inv.total,
                                 'deposit_applied', v_inv.deposit_applied, 'credit_applied', v_inv.credit_applied, 'balance_forward', v_inv.balance_forward,
                                 'paid', (select coalesce(sum(a.amount), 0) from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id where a.invoice_id = v_inv.id and a.voided_at is null and p.status = 'active' and p.kind = 'payment'),
                                 'amount_due', v_inv.amount_due,
                                 'remaining', public.so_invoice_remaining(v_inv.id)));                                                                                     -- doc-1c 판정 528 ①: 찍는 순간 지금 남은 금액(발행 때 종이 값 amount_due 는 doc-2 의 남긴 PDF 가 지킨다)
  return public.doc_data_invoice_fmt(p_kind, p_cfg, v_n);
end;
$function$;

-- ═══ ③ 적재 — so_invoice_preview(미리 보기 제품 줄에 pack_factor 한 열쇠 · 돈 식 무변) ═══
CREATE OR REPLACE FUNCTION public.so_invoice_preview(p_orders jsonb, p_shipped_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pf      jsonb;
  v_on      date := public.ims_today();                                                  -- 발행일 = 마무리한 날(so_finalize → so_invoice_issue(…, null) · ⓐ1) · p_shipped_on 은 출고일일 뿐
  v_g       jsonb;  v_o jsonb;  e jsonb;  x jsonb;
  v_ids     uuid[];
  v_first   public.so%rowtype;  v_so public.so%rowtype;  v_pt public.ref_payment_term%rowtype;
  v_rule_id uuid;  v_prev jsonb;  v_over jsonb;
  v_sc_code text := (select nullif(k.value, '') from public.inv_config k where k.key = 'so_surcharge_account_code');
  v_fd_code text := (select nullif(k.value, '') from public.inv_config k where k.key = 'so_freight_discount_account_code');
  v_orders  jsonb;  v_lines jsonb;  v_charges jsonb;  v_pay jsonb;  v_plan jsonb;  v_docs jsonb := '[]'::jsonb;  v_warn text[];
  v_lines_amt numeric;  v_od_amt numeric;  v_chg_amt numeric;  v_chd_amt numeric;  v_sc_amt numeric;  v_tax numeric;  v_total numeric;
  v_o_od numeric;
begin
  v_pf := public.so_finalize(p_orders, false, p_shipped_on);                             -- 검사 · 묶음 · 수량 · 다시 매긴 단가 · 운임 · 부가 요금 — 쓰지 않는다(p_commit false) · 문은 so_finalize 의 것(sales)
  for v_g in select g from jsonb_array_elements(v_pf->'invoices') g loop
    select array_agg((o->>'so_id')::uuid) into v_ids from jsonb_array_elements(v_pf->'orders') o where o->>'invoice_group' = v_g->>'group';
    select * into v_first from public.so s where s.id = any(v_ids) order by s.so_number limit 1;
    v_pt := null;
    if v_first.payment_term_id is not null then select * into v_pt from public.ref_payment_term t where t.id = v_first.payment_term_id; end if;
    v_orders := '[]'::jsonb;  v_charges := '[]'::jsonb;  v_warn := '{}';
    v_lines_amt := 0;  v_od_amt := 0;  v_chg_amt := 0;  v_chd_amt := 0;  v_sc_amt := 0;  v_tax := 0;
    for v_so in select * from public.so s where s.id = any(v_ids) order by s.so_number loop
      select o into v_o from jsonb_array_elements(v_pf->'orders') o where (o->>'so_id')::uuid = v_so.id;
      -- p_over: 보낼 수량(ship.lines picked) · 다시 매긴 단가(repriced) · 부가 요금(surcharges new) · 운임(charges — 마무리 화면이 고친 · 더한 것)
      select coalesce(jsonb_object_agg(z.line_id, z.o), '{}'::jsonb) into v_over
      from (select l->>'line_id' as line_id,
                   jsonb_build_object('qty', (l->>'picked')::numeric)
                   || coalesce((select jsonb_build_object('unit_price', r->'new_unit_price', 'discount_pct', r->'new_discount_pct', 'discount_source', r->'new_discount_source')
                                from jsonb_array_elements(coalesce(v_o->'repriced', '[]'::jsonb)) r where r->>'line_id' = l->>'line_id'), '{}'::jsonb)
                   || coalesce((select s->'new' from jsonb_array_elements(coalesce(v_o->'surcharges', '[]'::jsonb)) s where s->>'line_id' = l->>'line_id'), '{}'::jsonb) as o
            from jsonb_array_elements(coalesce(v_o->'ship'->'lines', '[]'::jsonb)) l) z;
      select pe into x from jsonb_array_elements(p_orders) pe where pe->>'so_id' = v_so.id::text;                                                     -- 입력(마무리 화면이 보낸 그대로) — description 은 so_finalize 미리 보기 항목에 없어 입력에서 짝(같은 순서)으로 가져온다
      v_over := jsonb_build_object('lines', v_over,
                                   'charges', (select coalesce(jsonb_agg(jsonb_build_object('charge_id', cc.c->'charge_id', 'name', cc.c->>'name', 'description', nullif(trim(ii.i->>'description'), ''), 'amount', cc.c->'amount',
                                                                                             'discount_pct', cc.c->'discount_pct', 'discount_amount', cc.c->'discount_amount', 'account_code', cc.c->'account_code') order by cc.ord), '[]'::jsonb)
                                               from jsonb_array_elements(coalesce(v_o->'charges', '[]'::jsonb)) with ordinality cc(c, ord)
                                               left join jsonb_array_elements(coalesce(nullif(x->'charges', 'null'::jsonb), '[]'::jsonb)) with ordinality ii(i, ord) on ii.ord = cc.ord));
      v_rule_id := public.so_invoice_rule_pick(v_so, v_on);
      v_prev := public.so_tax_preview(v_so.id, v_on, v_rule_id, 'shipped', v_over);
      v_o_od := (v_prev->'totals'->>'order_discount_amount')::numeric;
      -- 제품 줄(보낸 수량 > 0 · 구성품 줄 제외) · 그 뒤 surcharge 줄 · 오더 할인 줄 · 운임 줄 + 할인 줄 — so_invoice_issue 148 ~ 180 과 같은 순서
      select coalesce(jsonb_agg(jsonb_build_object('product_id', l->'product_id', 'sku', l->>'sku', 'description', l->>'product_name', 'comment', sl.comments, 'unit', l->>'unit', 'qty', (l->>'qty')::numeric, 'pack_factor', (l->>'pack_factor')::numeric,
                                                   'list_price', (l->>'list_price')::numeric, 'discount_pct', (l->>'discount_pct')::numeric, 'unit_price', (l->>'unit_price')::numeric, 'amount', (l->>'amount')::numeric, 'tax_amount', (l->>'tax')::numeric,
                                                   'is_free', sl.free_reason is not null, 'no_price', (l->>'unit_price') is null, 'manual', coalesce((l->>'manual')::boolean, false)) order by (l->>'line_no')::int), '[]'::jsonb)
        into v_lines
      from jsonb_array_elements(v_prev->'lines') l left join public.so_line sl on sl.id = (l->>'line_id')::uuid
      where (l->>'qty')::numeric > 0 and nullif(l->>'combo_line_id', '') is null;
      v_charges := v_charges || coalesce((select jsonb_agg(jsonb_build_object('so_number', v_so.so_number, 'kind', 'surcharge', 'account_code', v_sc_code, 'description', l->>'surcharge_label', 'comment', '',
                                                                                'qty', (l->>'qty')::numeric, 'unit_price', (l->>'surcharge_unit')::numeric, 'discount_pct', null, 'amount', (l->>'surcharge_total')::numeric, 'tax_amount', (l->>'surcharge_tax')::numeric) order by (l->>'line_no')::int)
                                          from jsonb_array_elements(v_prev->'lines') l where (l->>'qty')::numeric > 0 and nullif(l->>'combo_line_id', '') is null and coalesce((l->>'surcharge_total')::numeric, 0) > 0), '[]'::jsonb);
      if v_o_od <> 0 then
        v_charges := v_charges || jsonb_build_object('so_number', v_so.so_number, 'kind', 'order_discount', 'account_code', v_so.sale_account_code, 'description', format('Order discount %s%%', v_so.order_discount_pct), 'comment', '',
                                                     'qty', null, 'unit_price', null, 'discount_pct', null, 'amount', v_o_od, 'tax_amount', (v_prev->'order_discount'->>'tax')::numeric);
      end if;
      for e in select c from jsonb_array_elements(v_prev->'charges') c loop
        v_charges := v_charges || jsonb_build_object('so_number', v_so.so_number, 'kind', 'charge', 'account_code', e->>'account_code', 'description', (e->>'name') || coalesce(' — ' || (e->>'description'), ''), 'comment', coalesce(e->>'description', ''),
                                                     'qty', null, 'unit_price', null, 'discount_pct', null, 'amount', (e->>'amount')::numeric, 'tax_amount', (e->>'tax')::numeric);
        if coalesce((e->>'discount')::numeric, 0) > 0 then
          v_charges := v_charges || jsonb_build_object('so_number', v_so.so_number, 'kind', 'charge_discount', 'account_code', v_fd_code, 'comment', '',
                                                       'description', (e->>'name') || ' discount' || case when nullif(e->>'discount_pct', '') is not null then format(' %s%%', trim_scale((e->>'discount_pct')::numeric)) else '' end,
                                                       'qty', null, 'unit_price', null, 'discount_pct', nullif(e->>'discount_pct', '')::numeric, 'amount', -(e->>'discount')::numeric, 'tax_amount', -coalesce((e->>'discount_tax')::numeric, 0));
        end if;
      end loop;
      v_orders := v_orders || jsonb_build_object('so_number', v_so.so_number, 'reference', v_so.ref, 'carrier', coalesce((select rc.name from public.ref_carrier rc where rc.id = nullif(v_o->>'_carrier_id', '')::uuid), case when (v_o->>'_carrier_touch')::boolean then null else v_so.carrier end),
                                                 'tracking', case when (v_o->>'_tracking_touch')::boolean then nullif(array_to_string(array(select jsonb_array_elements_text(v_o->'_tracking')), ', '), '') else v_so.tracking_number end,
                                                 'tax_rule', v_prev->'rule'->>'rule', 'order_discount_pct', v_so.order_discount_pct,
                                                 'ship_to', jsonb_build_object('company', v_so.ship_to_company, 'contact', v_so.ship_to_contact, 'phone', v_so.ship_to_phone, 'line1', v_so.ship_to_line1, 'line2', v_so.ship_to_line2,
                                                                               'city', v_so.ship_to_city, 'state_province', v_so.ship_to_state_province, 'postal_code', v_so.ship_to_postal_code, 'country', v_so.ship_to_country),
                                                 'lines', v_lines);
      v_lines_amt := v_lines_amt + (v_prev->'totals'->>'lines_amount')::numeric;  v_od_amt := v_od_amt + v_o_od;
      v_chg_amt := v_chg_amt + (v_prev->'totals'->>'charges_amount')::numeric;  v_chd_amt := v_chd_amt + coalesce((v_prev->'totals'->>'charges_discount_amount')::numeric, 0);
      v_sc_amt := v_sc_amt + coalesce((v_prev->'totals'->>'surcharge_amount')::numeric, 0);  v_tax := v_tax + (v_prev->'totals'->>'tax')::numeric;
      if v_rule_id is distinct from v_so.tax_rule_id then v_warn := array_append(v_warn, 'draft_rule_changed:' || v_so.so_number); end if;
    end loop;
    v_total := v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt + v_tax;
    v_plan := public.so_invoice_apply_plan(v_first.bill_to_customer_id, v_first.currency_id, v_ids, v_total);
    select coalesce(jsonb_agg(jsonb_build_object('reference', s->'reference', 'paid_on', s->'paid_on', 'method', s->>'method', 'amount', (s->>'amount')::numeric) order by (s->>'paid_on')::date, (s->>'created_at')::timestamptz, ord), '[]'::jsonb)
      into v_pay from jsonb_array_elements(v_plan->'steps') with ordinality t(s, ord) where s->>'step' in ('auto_deposit', 'auto_balance');
    v_docs := v_docs || jsonb_build_object(
      'group', v_g->>'group', 'so_ids', to_jsonb(v_ids),
      'header', jsonb_build_object('number', null, 'issued_on', v_on, 'due_on', case when v_pt.net_days is not null then v_on + v_pt.net_days end, 'payment_term_name', coalesce(v_pt.name, v_first.payment_term_name),
                                   'currency_code', v_first.currency_code, 'memo', '', 'bill_to_customer_id', v_first.bill_to_customer_id,
                                   'bill_to', jsonb_build_object('name', v_first.bill_to_name, 'line1', v_first.bill_to_line1, 'line2', v_first.bill_to_line2, 'city', v_first.bill_to_city, 'state_province', v_first.bill_to_state_province, 'postal_code', v_first.bill_to_postal_code, 'country', v_first.bill_to_country)),
      'orders', v_orders, 'charges', v_charges, 'payments', v_pay,
      'totals', jsonb_build_object('order_discount', v_od_amt, 'surcharge', v_sc_amt, 'taxable', v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt, 'tax', v_tax, 'total', v_total,
                                   'deposit_applied', (v_plan->>'deposit')::numeric, 'credit_applied', (v_plan->>'credit')::numeric, 'balance_forward', -((v_plan->>'credit')::numeric + (v_plan->>'balance')::numeric),
                                   'paid', (v_plan->>'deposit')::numeric + (v_plan->>'balance')::numeric, 'amount_due', v_total - (v_plan->>'deposit')::numeric - (v_plan->>'credit')::numeric - (v_plan->>'balance')::numeric),
      'plan', v_plan, 'warnings', to_jsonb(v_warn), 'calc_at', now());
  end loop;
  return jsonb_build_object('issued_on', v_on, 'shipped_on', v_pf->>'shipped_on', 'docs', v_docs, 'finalize_warnings', v_pf->'warnings', 'put_back', v_pf->'put_back');
end;
$function$;
comment on function public.so_invoice_preview(jsonb, date) is 'doc-1b2 — Ship Ready(PROFORMA)의 숫자: so_finalize(p_orders, false) 가 돌려준 묶음 · 보낼 수량(picked) · 다시 매긴 단가 · 부가 요금 · 운임 고침을 p_over 로 so_tax_preview(shipped) 에 넘겨 발행(so_invoice_issue)과 같은 식 · 같은 순서(제품 → surcharge → 오더 할인 → 운임 → 운임 할인)로 줄을 세우고 so_invoice_apply_plan 으로 붙을 돈을 셈한다 · 발행일 = 오늘(ims_today — so_finalize 가 so_invoice_issue 에 null 을 넘긴다) · 아무것도 쓰지 않는다 · 묶음마다 중립 jsonb 하나(docs) — doc_data_invoice_fmt 가 문서로 그린다 · ⚠️ 미리 보기와 실제 발행 사이에 바뀔 수 있는 것(doc-0 Q2 ⑥): 세율(날짜) · 결제 · 크레딧 · WMS 픽 · 묶음 — calc_at 을 종이에 찍는다 · [doc-qty-1 2026-11-08] docs[].orders[].lines[].pack_factor(so_tax_preview 의 값 · 숫자) — fmt 가 낱개 합(qty_total_ea)에 쓴다 · 돈 · 세금 · 줄 순서 · 다른 열쇠 무변 · so_invoice_issue 는 이 함수를 부르지 않는다(so_tax_preview 를 바로)';

-- ═══ ④ 그리기 — doc_data_invoice_fmt(세 kind · 장 · 오더마다) ═══
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
  v_credits jsonb := '[]'::jsonb;  v_cr_amt numeric := 0;  v_out jsonb;                                                                                                   -- doc-cr-1 판정 864
  v_cr_src  jsonb;                                                                                                                                                      -- doc-sr-1 판정 874: 크레딧 목록의 중립 원천(final_invoice · internal_receipt = 적재의 credits[] · ship_ready = apply_plan 의 auto_credit 걸음)
  v_lines_amt numeric;  v_lines_tax numeric;  v_qty numeric;  v_chg_amt numeric;  v_chg_tax numeric;  v_chd numeric;
  v_due  numeric := coalesce((v_t->>'remaining')::numeric, (v_t->>'amount_due')::numeric);                                      -- doc-1c 판정 528 ①: 표에서 온 문서는 지금 남은 금액 · ship_ready(미리 보기)는 셈한 남을 몫
begin
  -- 제품 줄 — 오더 순(orders 배열 순 = so_number 순) · 줄 번호는 문서 안에서 1, 2, 3 … 이어서
  with ln as (
    select o.ord as o_ord, l.ord as l_ord, o.o->>'order_discount_pct' as od_pct, l.l, row_number() over (order by o.ord, l.ord) as no
    from jsonb_array_elements(p_n->'orders') with ordinality o(o, ord) cross join lateral jsonb_array_elements(o.o->'lines') with ordinality l(l, ord))
  select coalesce(jsonb_agg(jsonb_build_object(
           'so_number', coalesce(o.o->>'so_number', ''), 'reference', coalesce(o.o->>'reference', ''), 'carrier', coalesce(o.o->>'carrier', ''), 'tracking', coalesce(o.o->>'tracking', ''), 'tax_rule', coalesce(o.o->>'tax_rule', ''),
           'ship_to_repeat', exists (select 1 from jsonb_array_elements(p_n->'orders') with ordinality q(q, qord) where q.qord < o.ord and (select string_agg(lower(btrim(coalesce(q.q->'ship_to'->>k, ''))), '|' order by k) from unnest(array['company', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country']) k) = (select string_agg(lower(btrim(coalesce(o.o->'ship_to'->>k, ''))), '|' order by k) from unnest(array['company', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country']) k)),   -- srs-1 판정 788: 앞 오더에 같은 배송지(이름 · 주소 줄 · 도시 · 주 · 우편번호 · 나라 · lower(btrim))가 있으면 true — 판이 {{^ship_to_repeat}} 로 한 번만 그린다 · 첫 오더는 false
           'ship_to', (select jsonb_object_agg(k, coalesce(o.o->'ship_to'->>k, '')) from unnest(array['company', 'contact', 'phone', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country']) k),
           'lines', (select coalesce(jsonb_agg((jsonb_build_object('no', ln.no::text, 'upc', public.doc_upc(nullif(ln.l->>'product_id', '')::uuid), 'sku', coalesce(ln.l->>'sku', ''), 'description', coalesce(ln.l->>'description', ''), 'comment', coalesce(ln.l->>'comment', ''),
                                                                    'unit', coalesce(ln.l->>'unit', ''), 'qty', public.doc_fmt_qty((ln.l->>'qty')::numeric),   -- doc-hand-price-1: list_price · discount_pct 는 아래 doc_price_cells 가 준다
                                                                    'amount', public.doc_fmt_money((ln.l->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((ln.l->>'tax_amount')::numeric), 'is_free', coalesce((ln.l->>'is_free')::boolean, false), 'no_price', coalesce((ln.l->>'no_price')::boolean, false), 'final_sale', coalesce((ln.l->>'final_sale')::boolean, false))
                                                || public.doc_unit_prices((ln.l->>'unit_price')::numeric, case when coalesce((ln.l->>'manual')::boolean, false) then null else (ln.od_pct)::numeric end, v_disp)
                                                || public.doc_price_cells((ln.l->>'list_price')::numeric, (ln.l->>'discount_pct')::numeric, (ln.l->>'unit_price')::numeric, coalesce((ln.l->>'manual')::boolean, false), coalesce((ln.l->>'is_free')::boolean, false))) order by ln.no), '[]'::jsonb)   -- doc-hand-price-1 판정 976: 손 가격 줄(manual ∧ discount_pct null ∧ 무상 아님)은 단가 칸에 손 가격 · 할인 빈칸 — 판별 · 꼴 한 곳 doc_price_cells
                     from ln where ln.o_ord = o.ord)) order by o.ord), '[]'::jsonb),
         coalesce((select sum((ln.l->>'amount')::numeric) from ln), 0), coalesce((select sum((ln.l->>'tax_amount')::numeric) from ln), 0), coalesce((select sum((ln.l->>'qty')::numeric) from ln), 0)
    into v_orders, v_lines_amt, v_lines_tax, v_qty
  from jsonb_array_elements(p_n->'orders') with ordinality o(o, ord);
  -- doc-qty-1: 오더마다 제품 줄 수 · 수량 합 · 낱개 합(orders[].line_count · qty_total · qty_total_ea) — 원천 줄(p_n orders[].lines · 그린 줄과 같은 순서 · 같은 배열)을 doc_qty_totals 한 곳에 · 그린 줄 무접촉
  select coalesce(jsonb_agg((f.o || public.doc_qty_totals(r.o->'lines')) order by f.ord), '[]'::jsonb) into v_orders
    from jsonb_array_elements(v_orders) with ordinality f(o, ord) join jsonb_array_elements(p_n->'orders') with ordinality r(o, ord) on r.ord = f.ord;
  select coalesce(jsonb_agg(jsonb_build_object('no', c.ord::text, 'so_number', coalesce(c.c->>'so_number', ''), 'code', coalesce(c.c->>'account_code', ''), 'description', coalesce(c.c->>'description', ''), 'comment', coalesce(c.c->>'comment', ''),
                                               'qty', public.doc_fmt_qty((c.c->>'qty')::numeric), 'unit_price', public.doc_fmt_money((c.c->>'unit_price')::numeric), 'discount_pct', public.doc_fmt_pct((c.c->>'discount_pct')::numeric),
                                               'amount', public.doc_fmt_money((c.c->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((c.c->>'tax_amount')::numeric)) order by c.ord), '[]'::jsonb),
         coalesce(sum((c.c->>'amount')::numeric), 0), coalesce(sum((c.c->>'tax_amount')::numeric), 0), coalesce(sum((c.c->>'amount')::numeric) filter (where c.c->>'kind' = 'charge_discount'), 0)
    into v_charges, v_chg_amt, v_chg_tax, v_chd
  from jsonb_array_elements(p_n->'charges') with ordinality c(c, ord);
  select coalesce(jsonb_agg(jsonb_build_object('no', p.ord::text, 'reference', coalesce(p.p->>'reference', ''), 'date', public.doc_fmt_date((p.p->>'paid_on')::date, v_fmt), 'method', public.doc_method_label(p.p->>'method'), 'amount', public.doc_fmt_money((p.p->>'amount')::numeric)) order by p.ord), '[]'::jsonb)
    into v_payments from jsonb_array_elements(p_n->'payments') with ordinality p(p, ord);
  if p_kind = 'ship_ready' then   -- doc-sr-1 판정 874: ship_ready 는 발행 전이라 붙임(so_credit_alloc)이 없다 — so_invoice_preview 가 실은 apply_plan 의 크레딧 계획(auto_credit 걸음 · credit_id · credit_number · issued_on · amount)을 같은 중립 꼴로 · reference(원 인보이스 번호)는 계획에 없어 so_credit → so_invoice.invoice_number(IMS) → ref_invoice_number(Cin7) 로 읽는다 · 순서는 계획 순(issued_on → created_at)
    select coalesce(jsonb_agg(jsonb_build_object('credit_number', s.s->>'credit_number', 'issued_on', s.s->'issued_on', 'amount', (s.s->>'amount')::numeric,
                                                 'reference', (select coalesce((select oi.invoice_number from public.so_invoice oi where oi.id = c.invoice_id), c.ref_invoice_number) from public.so_credit c where c.id = nullif(s.s->>'credit_id', '')::uuid)) order by s.ord), '[]'::jsonb)
      into v_cr_src from jsonb_array_elements(coalesce(p_n->'plan'->'steps', '[]'::jsonb)) with ordinality s(s, ord) where s.s->>'step' = 'auto_credit';
  else
    v_cr_src := coalesce(p_n->'credits', '[]'::jsonb);   -- doc-cr-1 판정 864: 적재(doc_data_invoice)가 실은 살아 있는 붙임 목록
  end if;
  -- doc-cr-1 판정 864 · doc-sr-1 판정 874: 크레딧 목록(번호 · 발행일 · 원 인보이스 번호 · 금액) + 합 — 세 kind 같은 꼴 · 순서는 원천 순
    select coalesce(jsonb_agg(jsonb_build_object('no', c.ord::text, 'number', coalesce(c.c->>'credit_number', ''), 'date', public.doc_fmt_date((c.c->>'issued_on')::date, v_fmt), 'reference', coalesce(c.c->>'reference', ''), 'amount', public.doc_fmt_money((c.c->>'amount')::numeric)) order by c.ord), '[]'::jsonb),
           coalesce(sum((c.c->>'amount')::numeric), 0)
      into v_credits, v_cr_amt from jsonb_array_elements(v_cr_src) with ordinality c(c, ord);
  v_inv := jsonb_build_object('number', coalesce(v_h->>'number', ''), 'date', public.doc_fmt_date((v_h->>'issued_on')::date, v_fmt), 'due_date', public.doc_fmt_date((v_h->>'due_on')::date, v_fmt), 'terms', coalesce(v_h->>'payment_term_name', ''),
                              'currency', coalesce(v_h->>'currency_code', ''), 'memo', coalesce(v_h->>'memo', ''), 'total_qty', public.doc_fmt_qty(v_qty));
  v_inv := v_inv || jsonb_build_object('so_numbers', coalesce((select string_agg(o.o->>'so_number', ', ' order by o.ord) from jsonb_array_elements(p_n->'orders') with ordinality o(o, ord) where nullif(btrim(o.o->>'so_number'), '') is not null), ''));   -- srs-1 판정 787: 문서의 오더 SO 번호를 orders 순서대로 「, 」 로 이은 글(빈 번호 건너뜀) — 메일 제목 {{invoice.so_numbers}} 재료 · 세 kind 공통
  if p_kind = 'ship_ready' then
    v_inv := (v_inv - 'number') || jsonb_build_object('calc_at', public.doc_fmt_date(public.ims_today(), v_fmt) || ' ' || to_char(coalesce((p_n->>'calc_at')::timestamptz, now()) at time zone 'America/Toronto', 'HH24:MI'));
  end if;
  v_out := jsonb_build_object(   -- doc-cr-1: return → v_out(아래에서 새 열쇠를 얹는다) · 옛 열쇠 전부 무접촉
    'invoice', v_inv, 'orders', v_orders, 'charges', v_charges, 'payments', v_payments,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money(v_lines_amt), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money(v_lines_amt + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'order_discount', public.doc_fmt_money((v_t->>'order_discount')::numeric), 'surcharge', public.doc_fmt_money((v_t->>'surcharge')::numeric), 'charges_discount', public.doc_fmt_money(v_chd),
                                 'before_tax', public.doc_fmt_money((v_t->>'taxable')::numeric), 'tax', public.doc_fmt_money((v_t->>'tax')::numeric), 'total', public.doc_fmt_money((v_t->>'total')::numeric),
                                 'deposit_applied', public.doc_fmt_money_nz((v_t->>'deposit_applied')::numeric), 'credit_applied', public.doc_fmt_money_nz((v_t->>'credit_applied')::numeric), 'balance_forward', public.doc_fmt_money_nz((v_t->>'balance_forward')::numeric),   -- doc-1c 판정 528 ③: 0 이면 빈칸
                                 'paid', public.doc_fmt_money_nz((v_t->>'paid')::numeric), 'due_label', case when v_due > 0 then 'Due' when v_due < 0 then 'Credit' else '' end, 'due_amount', public.doc_fmt_money_nz(v_due)))   -- doc-1c 판정 528 ②: 남은 돈 0 이면 둘 다 빈칸(판이 {{#totals.due_amount}} 로 숨긴다)
    || public.doc_data_common(p_kind, p_cfg, (v_h->'bill_to') || public.doc_contact(nullif(v_h->>'bill_to_customer_id', '')::uuid));
  v_out := jsonb_set(v_out, '{totals,balance_due}', to_jsonb(public.doc_fmt_money(v_due)));                                                                                -- doc-cr-1 판정 864: 늘 찍는 남은 금액 — 0 이면 "0.00"(528 의 「0 이면 줄 없음」 을 이 열쇠만 바꾼다 · due_amount 는 그대로) · 세 kind
  v_out := jsonb_set(v_out, '{totals,credits}', to_jsonb(public.doc_fmt_money_nz(v_cr_amt))) || jsonb_build_object('credits', v_credits);   -- doc-cr-1: Credits 합(0 이면 빈칸 → 판의 줄이 사라진다) · 목록 · [doc-sr-1 판정 874] 세 kind(ship_ready 도)
  v_out := jsonb_set(v_out, '{totals}', (v_out->'totals') || public.doc_qty_totals((select coalesce(jsonb_agg(l.l), '[]'::jsonb) from jsonb_array_elements(p_n->'orders') o(o) cross join lateral jsonb_array_elements(o.o->'lines') l(l))));   -- doc-qty-1: 장 합계 셋 totals.line_count · qty_total · qty_total_ea — 모든 오더의 제품 줄(fmt 가 그린 orders.lines 와 같은 원천 · 구성품 줄은 원천이 이미 뺐다) · 세 kind · invoice.total_qty 는 무변(같은 값)
  return v_out;
end;
$function$;
comment on function public.doc_data_invoice_fmt(text, jsonb, jsonb) is 'doc-1b2 — 인보이스 꼴 문서(final_invoice · internal_receipt · ship_ready)의 그리기 한 곳: 중립 jsonb(표에서 온 것 · 또는 so_invoice_preview 의 미리 보기) → doc_field_catalog 의 열쇠 · 꼴 · 줄 번호 · 판정 314 단가 칸 · ship_ready 는 invoice.number 대신 invoice.calc_at · [srs-1 판정 787] invoice.so_numbers = 오더 SO 번호를 orders 순서대로 「, 」 로 이은 글(빈 번호 건너뜀 · 메일 제목 자리표) · [판정 788] orders.ship_to_repeat = 앞 오더와 같은 배송지(company · 주소 줄 · city · state_province · postal_code · country · lower(btrim))면 true — 묶음 인보이스가 같은 Ship To 를 한 번만 · [doc-cr-1 판정 864] totals.balance_due = 늘 찍는 남은 금액(0 이면 "0.00" · 세 kind) · final_invoice · internal_receipt 에 credits[](no · number · date · reference · amount) · totals.credits(합 · 0 이면 "") — 옛 열쇠 무접촉 · [doc-sr-1 판정 874] ship_ready 에도 credits[] · totals.credits(같은 이름 · 뜻 · 꼴) — 원천은 so_invoice_preview 가 실은 plan(so_invoice_apply_plan)의 auto_credit 걸음 · reference 는 so_credit → so_invoice 로 읽음 · 불변식 total − Σpayments − Σcredits = balance_due(장마다) · [doc-hand-price-1 판정 976] orders.lines 의 list_price · discount_pct 는 doc_price_cells 가 — 손 가격 줄(manual ∧ discount_pct null ∧ 무상 아님)은 손 가격 · 빈칸 · 그 밖은 정가 · 할인 %(열쇠 이름 · 수 그대로 · 판 무변) · [doc-qty-1 2026-11-08] totals.line_count · qty_total · qty_total_ea(장) · orders[].line_count · qty_total · qty_total_ea(오더마다) — 식은 doc_qty_totals 한 곳 · 원천 줄(p_n orders[].lines · pack_factor 는 적재 doc_data_invoice · so_invoice_preview 가 싣는다) · 그린 줄 · 옛 열쇠 · invoice.total_qty 무변 · 세 kind';

-- ═══ ⑤ 그리기 — doc_data_so(sales_order · 장) ═══
CREATE OR REPLACE FUNCTION public.doc_data_so(p_so_id uuid, p_cfg jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
                                                'unit', coalesce(x.l->>'unit', ''), 'qty', public.doc_fmt_qty((x.l->>'qty')::numeric),   -- doc-hand-price-1: list_price · discount_pct 는 아래 doc_price_cells 가 준다
                                                'amount', public.doc_fmt_money((x.l->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((x.l->>'tax')::numeric), 'is_free', sl.free_reason is not null, 'no_price', sl.unit_price is null)
                             || public.doc_unit_prices(sl.unit_price, case when coalesce(public.so_line_manual(sl), false) then null else v_so.order_discount_pct end, v_disp)
                             || public.doc_price_cells((x.l->>'list_price')::numeric, (x.l->>'discount_pct')::numeric, sl.unit_price, coalesce(public.so_line_manual(sl), false), sl.free_reason is not null)) order by x.no), '[]'::jsonb),   -- doc-hand-price-1 판정 976: 손 가격 줄은 단가 칸에 손 가격 · 할인 빈칸(fmt 와 같은 식 · doc_price_cells)
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
                                 'prepaid', public.doc_fmt_money_nz((v_t->>'received')::numeric), 'due_amount', public.doc_fmt_money((v_t->>'balance_due')::numeric)) || public.doc_qty_totals(v_o->'lines'))   -- doc-qty-1: totals 에 line_count · qty_total · qty_total_ea(so_proforma 의 줄 = 위 lines 와 같은 원천 · 구성품 줄 이미 뺌 · pack_factor 는 so_tax_preview 가 싣는다) · doc-1c 판정 528 ③ 의 결: 선결제 없으면 빈칸 · due 는 늘(아직 안 낸 오더)
    || public.doc_data_common('sales_order', p_cfg, jsonb_build_object('name', v_so.bill_to_name, 'line1', v_so.bill_to_line1, 'line2', v_so.bill_to_line2, 'city', v_so.bill_to_city, 'state_province', v_so.bill_to_state_province,
                                                                        'postal_code', v_so.bill_to_postal_code, 'country', v_so.bill_to_country) || public.doc_contact(coalesce(v_so.bill_to_customer_id, v_so.customer_id)));
end;
$function$;
comment on function public.doc_data_so(uuid, jsonb) is 'doc-1b — sales_order 문서 자료(so_proforma 의 줄 · 운임 · 오더 할인 · 부가 요금 · 선결제 · doc_data_common) · [od-1 판정 544] 손 줄(so_line_manual)은 오더 할인 몫 0(doc_unit_prices od_pct null) · [doc-hand-price-1 판정 976] lines 의 list_price · discount_pct 는 doc_price_cells 가 — 손 가격 줄은 손 가격 · 빈칸 · 그 밖은 정가 · 할인 %(fmt · doc_data_credit 과 같은 식 · 판 sales_order v2 무변) · [doc-qty-1 2026-11-08] totals.line_count · qty_total · qty_total_ea — doc_qty_totals(so_proforma 의 lines · fmt 와 같은 식) · 줄 열쇠 무변';

-- ═══ ⑥ 카탈로그 — doc_field_catalog ═══
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
  v_credit   text[] := array['no', 'number', 'date', 'reference', 'amount'];   -- doc-cr-1 판정 864: 크레딧 목록 한 줄(번호 · 발행일 · 원 인보이스 번호 · 붙인 금액)
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
    v_allowed := v_allowed || array['invoice.so_numbers', 'orders.ship_to_repeat'];   -- srs-1 판정 787: 오더 SO 번호를 「, 」 로 이은 글(메일 제목 자리표) · 판정 788: 앞 오더와 같은 배송지면 true(불리언 · {{^ship_to_repeat}}) — final_invoice · ship_ready · internal_receipt
    v_allowed := v_allowed || array['orders.so_number', 'orders.reference', 'orders.carrier', 'orders.tracking', 'orders.tax_rule'];
    foreach v_x in array v_ship   loop v_allowed := v_allowed || ('orders.ship_to.' || v_x); end loop;
    foreach v_x in array v_line   loop v_allowed := v_allowed || ('orders.lines.' || v_x); end loop;
    foreach v_x in array v_charge loop v_allowed := v_allowed || ('charges.' || v_x); end loop;
    foreach v_x in array v_money  loop v_allowed := v_allowed || ('payments.' || v_x); end loop;
    foreach v_x in array v_tot_inv loop v_allowed := v_allowed || ('totals.' || v_x); end loop;
    v_sections := v_sections || array['orders', 'orders.lines', 'charges', 'payments'];
    v_allowed := v_allowed || 'totals.balance_due'::text;   -- doc-cr-1 판정 864: 늘 찍는 남은 금액(0 이면 "0.00") — 세 kind · required 는 무접촉(옛 판이 다시 Check 돼도 통과)
    foreach v_x in array v_credit loop v_allowed := v_allowed || ('credits.' || v_x); end loop;   -- doc-cr-1 판정 864 · [doc-sr-1 판정 874] 크레딧 목록 + 합 — 세 kind(ship_ready 는 apply_plan 의 크레딧 계획 · final_invoice · internal_receipt 는 붙임)
    v_allowed := v_allowed || 'totals.credits'::text;
    v_sections := v_sections || 'credits'::text;
    v_allowed := v_allowed || array['totals.line_count', 'totals.qty_total', 'totals.qty_total_ea', 'orders.line_count', 'orders.qty_total', 'orders.qty_total_ea'];   -- doc-qty-1: 제품 줄 수 · 수량 합 · 낱개 합(Σ qty × pack_factor · qty_total 과 같으면 "") — 장(totals) · 오더마다(orders) · 세 kind · required 무접촉 · invoice.total_qty 무변
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
    v_allowed := v_allowed || array['totals.line_count', 'totals.qty_total', 'totals.qty_total_ea'];   -- doc-qty-1: sales_order 도 장 합계 셋(lines 가 콤보 줄 = 세트 하나 · 구성품 줄 없음)
    v_sections := v_sections || array['lines', 'charges', 'prepayments'];
    v_required := array['so.number', 'lines', 'totals.tax', 'totals.total'];
  end if;
  return jsonb_build_object('kind', p_kind, 'allowed', to_jsonb(v_allowed), 'sections', to_jsonb(v_sections), 'required', to_jsonb(v_required));
end;
$function$;
comment on function public.doc_field_catalog(text) is 'doc-1a ⑥ — 문서 kind 마다 판이 쓸 수 있는 자리표(allowed · 경로 꼴 orders.lines.sku = {{#orders}}{{#lines}}{{sku}}) · 목록 섹션(sections · 스코프를 미는 것 — 그 밖의 자리표도 {{#x}}…{{/x}} 조건으로 쓸 수 있으나 스코프를 밀지 않는다) · 필수(required · 섹션 이름은 섹션으로 써야 한다) · ⭐ doc-1b 데이터 창구는 이 목록과 똑같은 열쇠를 내야 한다(doc-1b 검증이 대조) · doc-0 Q2 와 다른 곳: bill_to · ship_to 에 city · state_province · postal_code · country(IMS 칸이 따로다) · charges.so_number · *.method · 크레딧 · SO 의 totals 는 제 것(deposit · balance_forward 없음) · [srs-1 판정 787 · 788] 인보이스 꼴 세 kind 에 invoice.so_numbers · orders.ship_to_repeat(불리언 · {{^ship_to_repeat}} 조건) · [doc-cr-1 판정 864] 인보이스 꼴 세 kind 에 totals.balance_due · final_invoice · internal_receipt 에 credits 섹션(no · number · date · reference · amount) · totals.credits · required 무접촉 · [doc-sr-1 판정 874] credits 섹션 · totals.credits 가 ship_ready 에도(세 kind 같은 목록) · required 무접촉 · [doc-qty-1 2026-11-08] totals.line_count · qty_total · qty_total_ea(kind 넷 — credit_note 는 아님) · orders.line_count · qty_total · qty_total_ea(인보이스 꼴 세 kind) · required 무접촉';

-- ═══ 착지 ═══
do $$
declare v_bad text := ''; v_n int;
begin
  select count(*) into v_n from pg_proc where pronamespace = 'public'::regnamespace and proname in ('doc_qty_totals', 'doc_data_invoice', 'so_invoice_preview', 'doc_data_invoice_fmt', 'doc_data_so', 'doc_field_catalog');
  if v_n <> 6 then v_bad := v_bad || ' count=' || v_n; end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.doc_qty_totals(jsonb)'::regprocedure) <> '49e29e0b03162808c5962e8483e9c1be' then v_bad := v_bad || ' qty_md5'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) <> '2fc7e887f8dd4ea2a842b8a5a710c4d9' then v_bad := v_bad || ' inv_md5'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure) <> 'fe4974b74b20337919ff2ddc11c4f18e' then v_bad := v_bad || ' pv_md5'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) <> 'f95805a3888849929132cccf5c443e91' then v_bad := v_bad || ' fmt_md5'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure) <> 'fe40d90b4930b9e0dbde0666074fb90d' then v_bad := v_bad || ' so_md5'; end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) <> 'f9b9aaedea19c4cf9ea3a5ebd621b75d' then v_bad := v_bad || ' cat_md5'; end if;
  -- 권한 · 머리 그대로(acl 은 create or replace 가 지킨다 · 새 함수는 postgres · service_role 만)
  if coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), '-') <> '{postgres=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' fmt_acl'; end if;
  if coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure), '-') <> '{postgres=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' so_acl'; end if;
  if coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure), '-') <> '{postgres=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' inv_acl'; end if;
  if coalesce((select proacl::text from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure), '-') <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' cat_acl'; end if;
  if coalesce((select proacl::text from pg_proc where oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure), '-') <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' pv_acl'; end if;
  if coalesce((select proacl::text from pg_proc where oid = 'public.doc_qty_totals(jsonb)'::regprocedure), '-') <> '{postgres=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' qty_acl'; end if;
  if (select provolatile::text || prosecdef::text from pg_proc where oid = 'public.doc_qty_totals(jsonb)'::regprocedure) <> 'ifalse' then v_bad := v_bad || ' qty_head'; end if;
  -- 값 한 번: 세트 줄 둘 + 낱개 줄 → 3 · 37 · 같으면 ""
  if public.doc_qty_totals('[{"qty": 1, "pack_factor": 18}, {"qty": 1, "pack_factor": 18}, {"qty": 1, "pack_factor": 1}]'::jsonb) <> '{"line_count": "3", "qty_total": "3", "qty_total_ea": "37"}'::jsonb then v_bad := v_bad || ' qty_val1'; end if;
  if public.doc_qty_totals('[{"qty": 2}, {"qty": 0.5, "pack_factor": null}]'::jsonb) <> '{"line_count": "2", "qty_total": "2.5", "qty_total_ea": ""}'::jsonb then v_bad := v_bad || ' qty_val2'; end if;
  if public.doc_qty_totals('[]'::jsonb) <> '{"line_count": "0", "qty_total": "0", "qty_total_ea": ""}'::jsonb or public.doc_qty_totals(null) <> '{"line_count": "0", "qty_total": "0", "qty_total_ea": ""}'::jsonb then v_bad := v_bad || ' qty_val3'; end if;
  if not ((public.doc_field_catalog('sales_order')->'allowed') ? 'totals.qty_total_ea') or not ((public.doc_field_catalog('ship_ready')->'allowed') ? 'orders.qty_total_ea') or ((public.doc_field_catalog('credit_note')->'allowed') ? 'totals.qty_total') then v_bad := v_bad || ' cat_keys'; end if;
  if v_bad <> '' then raise exception 'doc-qty-1 landing check failed:%', v_bad; end if;
end $$;
