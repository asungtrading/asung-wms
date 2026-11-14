-- supabase/migrations/20261114125023_docsvc_1_service_lines_apart.sql — docsvc-1: 서비스 줄을 문서에서 운임과 따로 · 문서 재료(판정 1221 ~ 1228 · 2026-11-14 · 지시서 ~/asung/prompts/docsvc-1.md · 근거 ~/asung/scratch/docsvc-0.md)
-- 왜: 서비스 줄(FINAL-SALE 떨이 · Amazon FBA Prep …)이 인보이스 꼴 문서의 「Freight & surcharges」 표와 화면의 「Charges」 · 「Freight and charges」 에 운임과 한 묶음으로 찍힌다(SO-21445 인보이스 60513 · 서비스 오더 인보이스 11 장)
-- 판정 1221 안 (나) + ⓑ — charges[] · totals.charges_* 는 글자 그대로(옛 판이 바르게 찍힘) · services[] 와 운임만 담은 freight_lines[] 를 얹는다 · 1222 칸 제목은 내용에 따라(doc_data 가 정함) · 1223 순수 서비스 문서는 본표 자리 · 섞일 때만 제목 달린 칸
--      1224 수량 합계는 제품 줄만 · 서비스 칸은 자기 줄 수 · 수량 · 1225 surcharge 는 운임 쪽 · 1226 이번 판 = final_invoice · internal_receipt · ship_ready(credit_note · sales_order 는 deferred · 자료 무변)
--      1227 「이름 — 메모」 + 메모 두 번 찍힘 → 새 배열 둘에서만 comment 를 비운다(charges[] 무변 · 운임 줄 108 개도 새 배열에서 함께) · 1228 화면이 서비스 줄을 가려낼 칸
-- 이견 답(Caleb 2026-11-14): 문서 단위 + orders[].has_lines · has_services · totals.services_* · freight_* · services_line_count · services_qty_total · 할인 줄은 부모를 따라감 · 번호 각자 1 부터 · so_detail 무변 · mcp_order deferred
-- 재발행 여섯(몸 = DB prosrc 원본 2026-11-14 + 더한 줄 · 시그니처 · invoker · volatility · search_path · acl 그대로 · create or replace · drop 없음):
--   doc_data_invoice(charges 적재에 is_service · final_sale) · so_invoice_preview(같은 표지 + 서비스 줄 qty · unit_price — ⚠️ ship_ready charges[] 의 서비스 줄도 수량 · 단가가 찍힌다 · 지금 0 건) · doc_data_invoice_fmt(새 열쇠 얹기) · doc_field_catalog(세 kind)
--   so_invoice_detail(invoice · orders[] 의 services_amount · lines[] 의 is_service · final_sale) · so_credit_prepare(lines[] 의 is_service — crtax-1 판 위에)
-- 무접촉: so_detail(charges[] 가 이미 service_id · final_sale 을 준다) · doc_data_so · doc_data_credit · so_tax_preview · so_invoice_issue · qbo_* · mcp_* · 표 · 권한 · 판(doc_template) · 화면 · EF · 금액 · 세금 · 총액 · 재고 · 원가
-- 검증 supabase/tests/docsvc_1_check.sql(begin → rollback) · 적용은 사람: psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f <이 파일> && supabase migration repair --status applied 20261114125023 · supabase db push 금지
-- ⚠️ 잠금: 함수 여섯의 create or replace 뿐(표 잠금 없음) · 새 판은 이 파일 적용 뒤에만 Check 를 지난다(카탈로그 밖 이름 거부)

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

-- ═══ 앞 검사 — 재발행 원본이 2026-11-14 에 읽은 DB prosrc 그대로인가(so_credit_prepare 는 crtax-1 20261114111500 적용 뒤의 몸) · 새 열쇠가 아직 없는가 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure)      <> 'cc658f428dda04b61798e69b0bf75a90' then v_bad := v_bad || ' doc_data_invoice'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) <> 'f95805a3888849929132cccf5c443e91' then v_bad := v_bad || ' doc_data_invoice_fmt'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure)          <> '92d56249b202b261eab513f3896f8e3f' then v_bad := v_bad || ' so_invoice_preview'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.doc_field_catalog(text)'::regprocedure)                  <> 'f9b9aaedea19c4cf9ea3a5ebd621b75d' then v_bad := v_bad || ' doc_field_catalog'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_invoice_detail(uuid)'::regprocedure)                  <> 'accd8deedc3eb1a8bb6bcb2ef549418a' then v_bad := v_bad || ' so_invoice_detail'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_credit_prepare(uuid)'::regprocedure)                  <> '2286b74a8403a048dd5d151fb1392aa2' then v_bad := v_bad || ' so_credit_prepare(crtax-1 applied?)'; end if;
  if (public.doc_field_catalog('final_invoice')->'allowed') ? 'services_title' then v_bad := v_bad || ' catalog_keys_exist'; end if;
  if v_bad <> '' then raise exception 'docsvc-1 pre-check failed (functions changed since the migration was written — rebuild it from the current prosrc · or it is already applied):%', v_bad; end if;
end $$;

-- ═══ ① doc_data_invoice — charges 적재에 서비스 표지 둘(출력 charges[] 무변) ═══
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
                 'lines', (select coalesce(jsonb_agg(jsonb_build_object('product_id', sl.product_id, 'sku', l.sku, 'description', l.description, 'comment', (select sn.note from public.so_line_note sn where sn.so_line_id = sl.id), 'unit', l.unit, 'qty', l.qty, 'pack_factor', l.pack_factor, 'list_price', l.list_price, 'discount_pct', l.discount_pct,
                                                                        'unit_price', l.unit_price, 'amount', l.amount, 'tax_amount', l.tax_amount, 'is_free', sl.free_reason is not null, 'no_price', l.unit_price is null, 'manual', coalesce(public.so_line_manual(sl), false), 'final_sale', coalesce(sl.bgrade_bin_id is not null, false)) order by l.line_no), '[]'::jsonb)
                           from public.so_invoice_line l left join public.so_line sl on sl.id = l.so_line_id where l.invoice_order_id = o.id and l.kind = 'product')) order by o.so_number), '[]'::jsonb)
               from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id),
    'charges', (select coalesce(jsonb_agg(jsonb_build_object('so_number', o.so_number, 'kind', l.kind, 'account_code', l.account_code, 'description', l.description, 'comment', case when l.kind = 'charge' then c.description end,
                                                             'qty', l.qty, 'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'amount', l.amount, 'tax_amount', l.tax_amount,
                                                             'is_service', c.service_id is not null, 'final_sale', coalesce(rs.final_sale, false)) order by o.so_number, l.line_no), '[]'::jsonb)   -- docsvc-1 판정 1221: 서비스 줄 표지(so_charge.service_id · charge_discount 줄은 부모 so_charge 를 따라간다 · surcharge 는 so_charge 없음 → false) · fmt 가 services[] · freight_lines[] 로 가른다 · charges[] 출력 무변
                from public.so_invoice_line l join public.so_invoice_order o on o.id = l.invoice_order_id left join public.so_charge c on c.id = l.so_charge_id left join public.ref_service rs on rs.id = c.service_id
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

-- ═══ ② so_invoice_preview — ship_ready 의 운임 줄에 같은 표지 + 서비스 줄 수량 · 단가 ═══
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
  v_svc boolean;  v_fs boolean;  v_cq numeric;  v_cup numeric;                          -- docsvc-1: 운임 줄의 서비스 표지 · 서비스 줄의 수량 · 단가
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
      select coalesce(jsonb_agg(jsonb_build_object('product_id', l->'product_id', 'sku', l->>'sku', 'description', l->>'product_name', 'comment', (select sn.note from public.so_line_note sn where sn.so_line_id = sl.id), 'unit', l->>'unit', 'qty', (l->>'qty')::numeric, 'pack_factor', (l->>'pack_factor')::numeric,
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
        -- docsvc-1 판정 1221(이견 7): 서비스 줄 표지(is_service · final_sale) + 서비스 줄의 수량 · 단가 — so_invoice_issue :158 ~ 159 와 같은 식(금액이 수량 × 단가와 다르면 금액만) · 운임 줄(service_id null)은 지금처럼 빈칸 · 새로 더한 운임(charge_id 없음)은 false
        v_svc := null;  v_fs := null;  v_cq := null;  v_cup := null;
        select sc.service_id is not null, coalesce(rs.final_sale, false), case when sc.service_id is not null then sc.qty end, case when sc.service_id is not null then sc.unit_price end
          into v_svc, v_fs, v_cq, v_cup
        from public.so_charge sc left join public.ref_service rs on rs.id = sc.service_id where sc.id = nullif(e->>'charge_id', '')::uuid;
        v_svc := coalesce(v_svc, false);  v_fs := coalesce(v_fs, false);
        if v_cq is null or v_cup is null or (e->>'amount')::numeric <> round(v_cq * v_cup, 2) then v_cq := null;  v_cup := null; end if;
        v_charges := v_charges || jsonb_build_object('so_number', v_so.so_number, 'kind', 'charge', 'account_code', e->>'account_code', 'description', (e->>'name') || coalesce(' — ' || (e->>'description'), ''), 'comment', coalesce(e->>'description', ''),
                                                     'qty', v_cq, 'unit_price', v_cup, 'discount_pct', null, 'amount', (e->>'amount')::numeric, 'tax_amount', (e->>'tax')::numeric, 'is_service', v_svc, 'final_sale', v_fs);   -- docsvc-1
        if coalesce((e->>'discount')::numeric, 0) > 0 then
          v_charges := v_charges || jsonb_build_object('so_number', v_so.so_number, 'kind', 'charge_discount', 'account_code', v_fd_code, 'comment', '',
                                                       'description', (e->>'name') || ' discount' || case when nullif(e->>'discount_pct', '') is not null then format(' %s%%', trim_scale((e->>'discount_pct')::numeric)) else '' end,
                                                       'qty', null, 'unit_price', null, 'discount_pct', nullif(e->>'discount_pct', '')::numeric, 'amount', -(e->>'discount')::numeric, 'tax_amount', -coalesce((e->>'discount_tax')::numeric, 0), 'is_service', v_svc, 'final_sale', v_fs);   -- docsvc-1: 할인 줄은 부모 줄을 따라간다
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

-- ═══ ③ doc_data_invoice_fmt — services[] · freight_lines[] · 표지 · 합계를 얹는다 ═══
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
  v_services jsonb;  v_freight jsonb;  v_svc_amt numeric;  v_svc_tax numeric;  v_frt_amt numeric;  v_frt_tax numeric;  v_svc_n bigint;  v_svc_qty numeric;  v_svc_fs bigint;  v_svc_plain bigint;  v_prod_n bigint;   -- docsvc-1 판정 1221 ~ 1227
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
  -- ═══ docsvc-1 판정 1221 ~ 1227 — 서비스 줄을 운임과 따로(안 (나) + ⓑ) · 위의 옛 열쇠(charges[] · totals.charges_*)는 글자 그대로 · 아래는 얹기만 ═══
  --   가름: is_service(적재가 실음 · so_charge.service_id · 할인 줄은 부모를 따라감) → services[] / 나머지(운임 · 운임 할인 · 오더 할인 · surcharge — 판정 1225) → freight_lines[] · 번호는 각자 1 부터(charges[] 의 no 무변)
  --   1227: 설명이 「 — 메모」 로 끝나면(so_invoice_issue · so_invoice_preview 가 「이름 — 설명」 으로 굳힌 줄) comment 를 비운다 — 새 배열 둘에서만 · 운임 줄도 같음
  with s as (
    select x.ord, x.c, coalesce((x.c->>'is_service')::boolean, false) as svc, coalesce((x.c->>'final_sale')::boolean, false) as fs, coalesce(x.c->>'kind', '') <> 'charge_discount' as main,
           case when nullif(x.c->>'comment', '') is not null and right(coalesce(x.c->>'description', ''), char_length(' — ' || (x.c->>'comment'))) = ' — ' || (x.c->>'comment') then '' else coalesce(x.c->>'comment', '') end as cm
    from jsonb_array_elements(p_n->'charges') with ordinality x(c, ord)),
  n as (select s.*, row_number() over (partition by s.svc order by s.ord) as no from s),
  o as (select n.*, jsonb_build_object('no', n.no::text, 'so_number', coalesce(n.c->>'so_number', ''), 'code', coalesce(n.c->>'account_code', ''), 'description', coalesce(n.c->>'description', ''), 'comment', n.cm,
                                       'qty', public.doc_fmt_qty((n.c->>'qty')::numeric), 'unit_price', public.doc_fmt_money((n.c->>'unit_price')::numeric), 'discount_pct', public.doc_fmt_pct((n.c->>'discount_pct')::numeric),
                                       'amount', public.doc_fmt_money((n.c->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((n.c->>'tax_amount')::numeric)) as j from n)
  select coalesce(jsonb_agg(o.j || jsonb_build_object('final_sale', o.fs) order by o.ord) filter (where o.svc), '[]'::jsonb),                       -- services[].final_sale = 진짜 JSON 불리언(문자열 "false" 는 Mustache 가 「있음」 으로 읽는다 · bgr-1d)
         coalesce(jsonb_agg(o.j order by o.ord) filter (where not o.svc), '[]'::jsonb),
         coalesce(sum((o.c->>'amount')::numeric) filter (where o.svc), 0), coalesce(sum((o.c->>'tax_amount')::numeric) filter (where o.svc), 0),
         coalesce(sum((o.c->>'amount')::numeric) filter (where not o.svc), 0), coalesce(sum((o.c->>'tax_amount')::numeric) filter (where not o.svc), 0),
         count(*) filter (where o.svc and o.main), coalesce(sum((o.c->>'qty')::numeric) filter (where o.svc and o.main), 0),                         -- 1224: 서비스 칸의 줄 수 · 수량(할인 줄은 세지 않는다 · 제품 합계 totals.line_count · qty_total 은 무변)
         count(*) filter (where o.svc and o.main and o.fs), count(*) filter (where o.svc and o.main and not o.fs)
    into v_services, v_freight, v_svc_amt, v_svc_tax, v_frt_amt, v_frt_tax, v_svc_n, v_svc_qty, v_svc_fs, v_svc_plain
  from o;
  select count(*) into v_prod_n from jsonb_array_elements(p_n->'orders') q(o) cross join lateral jsonb_array_elements(q.o->'lines') l(l);
  v_out := v_out || jsonb_build_object(
    'services', v_services, 'freight_lines', v_freight,
    'services_title', case when v_svc_fs > 0 and v_svc_plain > 0 then 'Services & final sale' when v_svc_fs > 0 then 'Final sale items' when jsonb_array_length(v_services) > 0 then 'Services' else '' end,   -- 1222: 제목 글은 doc_data 가 정한다(판은 {{services_title}} · 엔진이 & 를 &amp; 로)
    'has_services', jsonb_array_length(v_services) > 0, 'has_freight_lines', jsonb_array_length(v_freight) > 0, 'has_product_lines', v_prod_n > 0,
    'services_separate', jsonb_array_length(v_services) > 0 and v_prod_n > 0,                                                                         -- 1223: 제품과 섞였을 때만 제목 달린 칸
    'services_as_main',  jsonb_array_length(v_services) > 0 and v_prod_n = 0);                                                                         -- 1223: 순수 서비스 문서 — 제목 없이 본표 자리
  v_out := jsonb_set(v_out, '{totals}', (v_out->'totals') || jsonb_build_object(
    'services_before_tax', public.doc_fmt_money(v_svc_amt), 'services_tax', public.doc_fmt_money(v_svc_tax), 'services_total', public.doc_fmt_money(v_svc_amt + v_svc_tax),
    'freight_before_tax',  public.doc_fmt_money(v_frt_amt), 'freight_tax',  public.doc_fmt_money(v_frt_tax), 'freight_total',  public.doc_fmt_money(v_frt_amt + v_frt_tax),   -- services + freight = charges(같은 줄을 둘로 가른 합)
    'services_line_count', v_svc_n::text, 'services_qty_total', public.doc_fmt_qty(v_svc_qty)));
  v_out := jsonb_set(v_out, '{orders}', (select coalesce(jsonb_agg(f.o || jsonb_build_object('has_lines', jsonb_array_length(coalesce(r.o->'lines', '[]'::jsonb)) > 0) order by f.ord), '[]'::jsonb)   -- 이견 2: 오더마다 제품 줄이 있나(오더 여럿 인보이스에서 빈 제품 표를 그리지 않게)
                                         from jsonb_array_elements(v_out->'orders') with ordinality f(o, ord) join jsonb_array_elements(p_n->'orders') with ordinality r(o, ord) on r.ord = f.ord));
  return v_out;
end;
$function$;

-- ═══ ④ doc_field_catalog — 새 열쇠 · 구획(인보이스 꼴 셋) ═══
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
    -- docsvc-1 판정 1221 ~ 1226: 서비스 줄 · 운임만 담은 줄(charges 와 같은 줄 모양) + 표지 · 합계 — 인보이스 꼴 셋에만(credit_note · sales_order 출력 무변) · v_charge(다섯 kind 공용) · required 무접촉
    foreach v_x in array v_charge loop v_allowed := v_allowed || ('services.' || v_x); end loop;
    foreach v_x in array v_charge loop v_allowed := v_allowed || ('freight_lines.' || v_x); end loop;
    v_allowed := v_allowed || array['services.final_sale', 'services_title', 'has_services', 'services_separate', 'services_as_main', 'has_product_lines', 'has_freight_lines', 'orders.has_lines',
                                    'totals.services_before_tax', 'totals.services_tax', 'totals.services_total', 'totals.freight_before_tax', 'totals.freight_tax', 'totals.freight_total',
                                    'totals.services_line_count', 'totals.services_qty_total'];
    v_sections := v_sections || array['services', 'freight_lines'];
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

-- ═══ ⑤ so_invoice_detail — 화면(so-invoices.html)이 서비스 줄을 가려낼 칸 ═══
CREATE OR REPLACE FUNCTION public.so_invoice_detail(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'invoice', to_jsonb(v) || jsonb_build_object('services_amount', (select coalesce(sum(xl.amount), 0) from public.so_invoice_line xl join public.so_charge xc on xc.id = xl.so_charge_id where xl.invoice_id = v.id and xl.kind = 'charge' and xc.service_id is not null)),   -- docsvc-1 판정 1228: 서비스 줄 정가 합(charges_amount 와 같은 뜻 — 그중 서비스 몫 · 할인 줄 · 세금 제외)
    'orders', (select coalesce(jsonb_agg(to_jsonb(o) || jsonb_build_object('services_amount', (select coalesce(sum(xl.amount), 0) from public.so_invoice_line xl join public.so_charge xc on xc.id = xl.so_charge_id where xl.invoice_order_id = o.id and xl.kind = 'charge' and xc.service_id is not null), 'so_status', s.status, 'ref', s.ref, 'channel', s.channel, 'intake', s.intake, 'store_name', c2.name)
                                          order by o.so_number), '[]'::jsonb)
               from public.so_invoice_order o
               join public.so s on s.id = o.so_id
               left join public.customer c2 on c2.id = o.customer_id
               where o.invoice_id = v.id),
    'lines', (select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('is_service', sc.service_id is not null, 'final_sale', (sl.bgrade_bin_id is not null) or coalesce(rs.final_sale, false)) order by l.line_no), '[]'::jsonb)   -- docsvc-1 판정 1228: 줄 표지 — is_service(so_charge.service_id · 할인 줄은 부모를 따라감) · final_sale(B급으로 판 줄 또는 FINAL-SALE 서비스 — so_credit_prepare 와 같은 뜻)
              from public.so_invoice_line l left join public.so_charge sc on sc.id = l.so_charge_id left join public.ref_service rs on rs.id = sc.service_id left join public.so_line sl on sl.id = l.so_line_id where l.invoice_id = v.id),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object(
                   'alloc_id', a.id, 'payment_id', p.id, 'paid_on', p.paid_on, 'method', p.method, 'reference', p.reference, 'account_code', p.account_code, 'warehouse_name', p.warehouse_name,
                   'amount', a.amount, 'payment_amount', p.amount,
                   -- 결제의 남은 금액(0-8) — ✅ so-pay-read-1(2026-09-25) 이 so_payment_remaining 으로 뗐다(식의 한 곳 · 옛 복사 식은 20260925014413_so_credit_c2.sql:146 에서 왔었다)
                   'payment_remaining', public.so_payment_remaining(p.id),
                   'source', a.source, 'voided_at', a.voided_at, 'void_note', a.void_note, 'payment_status', p.status, 'created_at', a.created_at)
                   order by p.paid_on, p.created_at, a.created_at), '[]'::jsonb)
                 from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
                 where a.invoice_id = v.id),
    'credits_applied', (select coalesce(jsonb_agg(jsonb_build_object(
                          'alloc_id', a.id, 'credit_id', c.id, 'credit_number', c.credit_number, 'credit_status', c.status, 'issued_on', c.issued_on, 'credit_total', c.total,
                          'amount', a.amount, 'source', a.source, 'voided_at', a.voided_at, 'void_note', a.void_note, 'created_at', a.created_at)
                          order by c.issued_on, c.credit_number, a.created_at), '[]'::jsonb)
                        from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id
                        where a.invoice_id = v.id),
    'credits_against', (select coalesce(jsonb_agg(jsonb_build_object(
                          'credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'reason', c.reason,
                          'lines_amount', c.lines_amount, 'fee_amount', c.fee_amount, 'tax_amount', c.tax_amount, 'total', c.total, 'cancelled_at', c.cancelled_at,
                          'applied_here', coalesce((select sum(a.amount) from public.so_credit_alloc a where a.credit_id = c.id and a.invoice_id = v.id and a.voided_at is null), 0))
                          order by c.issued_on, c.credit_number), '[]'::jsonb)
                        from public.so_credit c where c.invoice_id = v.id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', h.id, 'invoice_number', h.invoice_number, 'status', h.status, 'issued_on', h.issued_on, 'total', h.total, 'cancelled_at', h.cancelled_at, 'cancel_note', h.cancel_note,
                  'so_numbers', (select string_agg(ho.so_number, ', ' order by ho.so_number) from public.so_invoice_order ho where ho.invoice_id = h.id))
                  order by h.invoice_number), '[]'::jsonb)
                from public.so_invoice h
                where h.id <> v.id
                  and exists (select 1 from public.so_invoice_order a1 join public.so_invoice_order a2 on a2.so_id = a1.so_id
                              where a1.invoice_id = v.id and a2.invoice_id = h.id)),
    'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v.bill_to_customer_id) b where b.currency_id = v.currency_id)
  )
  from public.so_invoice_list v
  where v.id = p_invoice_id;
$function$;

-- ═══ ⑥ so_credit_prepare — 화면(so-credits.html)의 줄 표지 is_service ═══
CREATE OR REPLACE FUNCTION public.so_credit_prepare(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with inv as (
    select i.*, cu.name as customer_name, public.ims_today() as today,
           public.so_invoice_no_order(i.id) as no_order,                                                -- crtax-1(판정 1217): 오더 없는 인보이스(이월) — 발행이 세금 규칙을 받는다
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
                                  'currency_id', inv.currency_id, 'currency_code', inv.currency_code, 'total', inv.total, 'remaining', public.so_invoice_remaining(inv.id), 'needs_tax_rule', inv.no_order),
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
                'is_service', (l.kind = 'charge' and exists (select 1 from public.so_charge xc where xc.id = l.so_charge_id and xc.service_id is not null)),   -- docsvc-1 판정 1228: 서비스 줄 표지(운임 줄 false)
                'final_sale', sl.bgrade_bin_id is not null or (l.kind = 'charge' and exists (select 1 from public.so_charge fc join public.ref_service fs on fs.id = fc.service_id where fc.id = l.so_charge_id and fs.final_sale)), 'restock_bgrade_bin_gone', sl.bgrade_bin_id is not null and bgb.j is null,   -- bgr-1d 판정 640 · 649: B급으로 판 줄 · 그 B급 칸이 꺼졌거나 비활성이면 정상 기본으로
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
    'tax_rule_suggested', case when inv.no_order then public.so_credit_tax_rule_suggest(coalesce(public.so_invoice_store(inv.id), inv.bill_to_customer_id), inv.today) end,   -- crtax-1(판정 1218): 제안만(매장 기본 배송지) · 발행 commit 은 고른 규칙을 받아야 한다
    'tax_rule_options', case when inv.no_order then public.so_credit_tax_rule_options(false) else '[]'::jsonb end,                                                            -- crtax-1(판정 1219): 활성 sale 규칙 모두 · QBO 코드 유무
    'vocab', jsonb_build_object('reasons', '["customer_return","damaged","billing_error","other","price_adjustment"]'::jsonb,                                                      -- crn-2 판정 612
                                'not_restocked_reasons', '["damaged","not_returned","other"]'::jsonb,                                                   -- bgr-1e 판정 651: b_grade 는 새로 못 고른다
                                'not_restocked_reasons_retired', '["b_grade"]'::jsonb,                                                                    -- bgr-1e: 옛 줄 표시용(라벨만)
                                'line_kinds', '["product","freight","tax","other","restocking_fee","price_adjustment"]'::jsonb)                                                   -- crn-2 판정 603
  )
  from inv, cfg;
$function$;

-- ═══ 뒤 검사 — 카탈로그에 새 열쇠 · 구획이 세 kind 에만 ═══
do $$
declare v_k text;  v_bad text := '';
begin
  foreach v_k in array array['final_invoice', 'internal_receipt', 'ship_ready'] loop
    if not ((public.doc_field_catalog(v_k)->'allowed') ?& array['services.no', 'services.final_sale', 'freight_lines.amount', 'services_title', 'has_services', 'services_separate', 'services_as_main', 'has_product_lines', 'has_freight_lines', 'orders.has_lines', 'totals.services_before_tax', 'totals.freight_total', 'totals.services_line_count', 'totals.services_qty_total']
            and (public.doc_field_catalog(v_k)->'sections') ?& array['services', 'freight_lines']) then v_bad := v_bad || ' ' || v_k; end if;
  end loop;
  foreach v_k in array array['credit_note', 'sales_order'] loop
    if (public.doc_field_catalog(v_k)->'allowed') ? 'services_title' or (public.doc_field_catalog(v_k)->'sections') ? 'services' then v_bad := v_bad || ' ' || v_k || '_leaked'; end if;
  end loop;
  if v_bad <> '' then raise exception 'docsvc-1 post-check failed:%', v_bad; end if;
end $$;
