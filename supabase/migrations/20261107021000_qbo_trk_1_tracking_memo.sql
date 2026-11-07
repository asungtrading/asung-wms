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
-- qbo-trk-1 — QBO 인보이스 TrackingNum 31 자 한도: 첫 송장번호만 칸에 · 전체 목록은 CustomerMemo 둘째 줄 (2026-11-06 · Caleb 판정 A · 지시서 ~/asung/prompts/qbo-trk-1.md)
-- 실물: qbo-send.html Invoices failed 6 장 — HTTP 400 ValidationFault 2050 「String length … Min:0 Max:31 supported. Supplied length:218」(다른 장 68 · 38) · 다상자 Freightcom 예약이 so.tracking_number 를 「a, b, c」 로 잇는다(ful_1a · ful_1b · fc_2b 모두 ', ')
-- 확인: 실패 칸 = TrackingNum(failed 6 장 모두 Supplied length = length(body->>'TrackingNum')) · 몸은 일감에 저장되지 않고 claim · preview 가 qbo_invoice_body 를 매번 다시 부른다 → 적용 뒤 Retry 한 번이면 새 몸으로 나간다
-- 하는 것: qbo_invoice_body(2b1 20261102040000) 재발행 하나 —
--   ① TrackingNum = 첫 오더(so_number 순)의 첫 조각(쉼표 · 공백 · 줄바꿈 `[,\s]+` 로 나눔) · 31 자 넘으면 left(31) + warnings
--   ② CustomerMemo = 「Customer Reference: <refs>, <매장>」 + 줄바꿈 + 「Tracking: <전체>」 — 오더 하나면 「Tracking: a, b」 · 여럿이면 「Tracking: SO-1 a, b / SO-2 c」(송장 있는 오더만) — 이견 5(Caleb: 오더별 전부)
--   ③ 메모 줄은 조각 둘 이상 · 잘림 · 첫 오더 밖 송장이 있을 때만 → 송장 하나 · 31 자 이하 · 첫 오더에만인 인보이스는 몸이 전과 바이트 동일(시나리오 6)
--   ④ CustomerMemo 1,000 자(Intuit Invoice 레퍼런스 · 짐작 표시) 넘으면 Tracking 줄을 쉼표 · 오더 경계에서 뒤부터 떼고 ' …' + warnings
--   ⑤ PrivateNote 무변 — 인보이스 unknown 풀기는 DocNumber(EF entityKeyOf) · PrivateNote 완전 일치는 payment · credit_apply 뿐(이견 1 · grep 확인)
-- 안 하는 것: EF(몸을 그대로 보낸다 · 배포 없음) · 크레딧 노트 몸(TrackingNum · ShipDate 를 싣지 않는다) · BillEmail 100 자 가드(안 쟀다 · 이견 6) · 정본 · 스킬(말만)
-- 시험: supabase/tests/qbo_trk_1_check.sql(begin → \i → 검증 → rollback · 시나리오 T1 ~ T10 · 재발행 전후 바이트 비교 · L1 nowhere)
-- 적용(Caleb · 운영 메인 Asung-IMS): supabase db push --db-url "$(cat ~/.asung-testdb-url)" → migration repair → 확인 검사(-v mig 없이) → qbo-send.html 실패 인보이스 Preview → Retry

create or replace function public.qbo_invoice_body(p_invoice_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_realm text := public.qbo_realm_of();
  v_i public.so_invoice%rowtype; v_o public.so_invoice_order%rowtype; v_store public.customer%rowtype; v_so public.so%rowtype;
  v_n_orders int; v_n_stores int; v_cust_ref text; v_term_ref text; v_tax_ref text; v_rate_ref text; v_item text; v_cur text;
  v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_lines jsonb := '[]'::jsonb; v_tax_lines jsonb := '[]'::jsonb;
  v_refs text; v_email text; v_bill jsonb; v_ship jsonb; v_detail jsonb; v_desc text; v_qty numeric; v_up numeric; v_need jsonb;
  v_l record; v_t record;
  v_r record; v_trk text; v_trk_line text; v_parts text[] := '{}'; v_n_trk int := 0; v_n_first int := 0; v_trk_cut boolean := false; v_memo text; v_budget int;   -- qbo-trk-1 송장 · 메모
begin
  select * into v_i from public.so_invoice i where i.id = p_invoice_id;
  if v_i.id is null then raise exception 'No IMS invoice % — nothing was sent', p_invoice_id; end if;
  if v_i.kind = 'opening' then raise exception 'Invoice % was carried forward from the previous system — it is already in QuickBooks (786) — nothing was sent', v_i.invoice_number; end if;
  if v_i.status <> 'issued' then raise exception 'Invoice % is % — only an issued invoice is sent to QuickBooks — nothing was sent', v_i.invoice_number, v_i.status; end if;
  select count(*), count(distinct o.customer_id) into v_n_orders, v_n_stores from public.so_invoice_order o where o.invoice_id = v_i.id and o.cancelled_at is null;
  if v_n_orders = 0 then raise exception 'Invoice % has no orders — nothing was sent', v_i.invoice_number; end if;
  if v_n_stores > 1 then raise exception 'Invoice % covers % stores — cancel and reissue per store (one QuickBooks customer per invoice) — nothing was sent', v_i.invoice_number, v_n_stores; end if;
  select * into v_o from public.so_invoice_order o where o.invoice_id = v_i.id and o.cancelled_at is null order by o.so_number limit 1;
  select * into v_so from public.so s where s.id = v_o.so_id;
  select * into v_store from public.customer c where c.id = v_o.customer_id;
  if v_store.id is null then raise exception 'Invoice % — the store (order customer) is missing — nothing was sent', v_i.invoice_number; end if;
  -- 935 CustomerRef = 매장 · 짝 없으면 need(손님 일감 · 부모는 open_or_add 가)
  select l.qbo_id into v_cust_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_store.id::text;
  if v_cust_ref is null then v_needs := v_needs || jsonb_build_object('kind', 'customer', 'ims_id', v_store.id::text, 'name', v_store.name); end if;
  -- 결제조건 · 기한
  if v_i.payment_term_id is not null then
    select l.qbo_id into v_term_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'payment_term' and l.ims_id = v_i.payment_term_id::text;
    if v_term_ref is null then raise exception 'Payment term "%" has no QuickBooks match — link it under Settings → QuickBooks matching — nothing was sent', v_i.payment_term_name; end if;
  else
    v_warn := array_append(v_warn, 'no payment term on the invoice — QuickBooks default terms');
  end if;
  if v_i.due_on is null then v_warn := array_append(v_warn, 'no due date on the invoice'); end if;
  v_cur := coalesce(nullif(btrim(coalesce(v_i.currency_code, '')), ''), (select c.code from public.ref_currency c where c.id = v_i.currency_id));
  if v_cur is null then raise exception 'Invoice % has no currency code — nothing was sent', v_i.invoice_number; end if;
  -- 936 · 946 주소 · 이메일(값은 문서에 찍힌 그대로)
  v_bill := jsonb_strip_nulls(jsonb_build_object('Line1', nullif(btrim(coalesce(v_i.bill_to_name, '')), ''), 'Line2', nullif(btrim(coalesce(v_i.bill_to_line1, '')), ''), 'Line3', nullif(btrim(coalesce(v_i.bill_to_line2, '')), ''),
                                                 'City', nullif(btrim(coalesce(v_i.bill_to_city, '')), ''), 'CountrySubDivisionCode', nullif(btrim(coalesce(v_i.bill_to_state_province, '')), ''), 'PostalCode', nullif(btrim(coalesce(v_i.bill_to_postal_code, '')), ''),
                                                 'Country', public.qbo_country_name(v_i.bill_to_country)));
  if nullif(btrim(coalesce(v_i.bill_to_line1, '')), '') is null then v_warn := array_append(v_warn, 'no billing address on the invoice'); end if;
  if public.qbo_country_name(v_i.bill_to_country) is not null and public.qbo_country_name(v_i.bill_to_country) not in ('Canada', 'USA') then v_warn := array_append(v_warn, format('billing country "%s" sent as is', public.qbo_country_name(v_i.bill_to_country))); end if;
  v_ship := jsonb_strip_nulls(jsonb_build_object('Line1', nullif(btrim(coalesce(v_o.ship_to_company, '')), ''), 'Line2', nullif(btrim(coalesce(v_o.ship_to_line1, '')), ''), 'Line3', nullif(btrim(coalesce(v_o.ship_to_line2, '')), ''),
                                                 'City', nullif(btrim(coalesce(v_o.ship_to_city, '')), ''), 'CountrySubDivisionCode', nullif(btrim(coalesce(v_o.ship_to_state_province, '')), ''), 'PostalCode', nullif(btrim(coalesce(v_o.ship_to_postal_code, '')), ''),
                                                 'Country', public.qbo_country_name(v_o.ship_to_country)));
  if v_ship = '{}'::jsonb then v_ship := null; v_warn := array_append(v_warn, 'no ship-to address on the first order'); end if;
  if v_n_orders > 1 and exists (select 1 from public.so_invoice_order o where o.invoice_id = v_i.id and o.cancelled_at is null and o.id <> v_o.id
                                  and (o.ship_to_company, o.ship_to_line1, o.ship_to_line2, o.ship_to_city, o.ship_to_state_province, o.ship_to_postal_code, o.ship_to_country)
                                      is distinct from (v_o.ship_to_company, v_o.ship_to_line1, v_o.ship_to_line2, v_o.ship_to_city, v_o.ship_to_state_province, v_o.ship_to_postal_code, v_o.ship_to_country)) then
    v_warn := array_append(v_warn, 'ship-to differs between orders — first order (' || v_o.so_number || ') used');
  end if;
  v_email := public.doc_mail_recipient(v_i.bill_to_customer_id)->>'to';
  if v_email is null then v_warn := array_append(v_warn, 'no email on file for the bill-to customer'); end if;
  -- 939 메모 — ref 없는 오더는 so_number
  select string_agg(coalesce(nullif(btrim(s.ref), ''), o.so_number), ', ' order by o.so_number) into v_refs
    from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_i.id and o.cancelled_at is null;
  -- qbo-trk-1(2026-11-06 · Caleb 판정 A) 송장 — QBO TrackingNum 은 31 자(ValidationFault 2050 실물 · 다상자 Freightcom 예약은 「a, b, c」 218 자까지)
  --   TrackingNum = 첫 오더(so_number 순)의 첫 조각(쉼표 · 공백 · 줄바꿈으로 나눔 · 31 자 넘으면 자르고 경고) · 전체 목록 = CustomerMemo 둘째 줄 「Tracking: …」(오더 여럿이면 「SO-1 a, b / SO-2 c」)
  --   메모 줄은 조각이 둘 이상 · 잘렸을 때 · 첫 오더 밖의 송장이 있을 때만 — 송장 하나 · 31 자 이하 · 첫 오더에만이면 몸은 전과 바이트 동일
  for v_r in select o.so_id, o.so_number, array_remove(regexp_split_to_array(btrim(coalesce(s.tracking_number, '')), '[,\s]+'), '') as pcs
               from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_i.id and o.cancelled_at is null order by o.so_number loop
    if v_r.so_id = v_o.so_id then
      v_n_first := coalesce(array_length(v_r.pcs, 1), 0);
      v_trk := v_r.pcs[1];
      if length(v_trk) > 31 then
        v_trk_cut := true; v_warn := array_append(v_warn, format('tracking number "%s" cut to 31 characters for QuickBooks — the full number is in the memo', v_trk)); v_trk := left(v_trk, 31);
      end if;
    end if;
    if coalesce(array_length(v_r.pcs, 1), 0) > 0 then
      v_n_trk := v_n_trk + array_length(v_r.pcs, 1);
      v_parts := array_append(v_parts, case when v_n_orders = 1 then array_to_string(v_r.pcs, ', ') else v_r.so_number || ' ' || array_to_string(v_r.pcs, ', ') end);
    end if;
  end loop;
  v_memo := 'Customer Reference: ' || v_refs || ', ' || v_store.name;
  if v_n_trk > 1 or v_trk_cut or v_n_trk <> v_n_first then
    v_trk_line := array_to_string(v_parts, ' / ');
    v_budget := 1000 - length(v_memo) - length(E'\nTracking: ');                                        -- CustomerMemo 1,000 자(Intuit Invoice 레퍼런스)
    if length(v_trk_line) > v_budget then
      v_budget := v_budget - 2;                                                                         -- 끝의 ' …'
      while length(v_trk_line) > v_budget and v_trk_line ~ '[,/]' loop
        v_trk_line := rtrim(regexp_replace(v_trk_line, '\s*[,/][^,/]*$', ''));                        -- 쉼표 · 오더 경계에서 뒤부터 뗀다
      end loop;
      if length(v_trk_line) > v_budget then v_trk_line := left(v_trk_line, v_budget); end if;
      v_trk_line := v_trk_line || ' …';
      v_warn := array_append(v_warn, 'tracking list in the memo cut to fit 1,000 characters');
    end if;
    v_memo := v_memo || E'\nTracking: ' || v_trk_line;
  end if;
  -- 942 세금 — 규칙마다 TaxLine(TaxRateRef 는 거울 detail)
  for v_t in select o.tax_rule_id, o.tax_rule, max(o.rate_pct) as rate, sum(o.taxable_amount) as taxable, sum(o.tax_amount) as tax
               from public.so_invoice_order o where o.invoice_id = v_i.id and o.cancelled_at is null group by o.tax_rule_id, o.tax_rule order by o.tax_rule loop
    select l.qbo_id into v_tax_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'tax_rule' and l.ims_id = v_t.tax_rule_id::text;
    if v_tax_ref is null then raise exception 'Tax rule "%" has no QuickBooks tax code — link it under Settings → QuickBooks matching — nothing was sent', v_t.tax_rule; end if;
    select e.detail into v_detail from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'TaxCode' and e.qbo_id = v_tax_ref;
    v_rate_ref := nullif(btrim(coalesce(v_detail->'TaxRateDetail'->0->'TaxRateRef'->>'value', '')), '');
    if v_rate_ref is null then raise exception 'QuickBooks tax code #% ("%") has no tax rate on file — Settings → QuickBooks matching → Refresh list (tax codes), then retry — nothing was sent', v_tax_ref, v_t.tax_rule; end if;
    if jsonb_array_length(coalesce(v_detail->'TaxRateDetail', '[]'::jsonb)) > 1 then v_warn := array_append(v_warn, format('tax code #%s has %s rates — first rate #%s used', v_tax_ref, jsonb_array_length(v_detail->'TaxRateDetail'), v_rate_ref)); end if;
    v_tax_lines := v_tax_lines || jsonb_build_object('DetailType', 'TaxLineDetail', 'Amount', v_t.tax,
                     'TaxLineDetail', jsonb_build_object('TaxRateRef', jsonb_build_object('value', v_rate_ref), 'PercentBased', true, 'TaxPercent', trim_scale(v_t.rate), 'NetAmountTaxable', v_t.taxable));
  end loop;
  -- 줄 — so_invoice_line 순서 그대로
  for v_l in select l.*, o.tax_rule_id, sl.product_id, c.service_id, c.account_code as charge_acct, c.name as charge_name
               from public.so_invoice_line l join public.so_invoice_order o on o.id = l.invoice_order_id
               left join public.so_line sl on sl.id = l.so_line_id left join public.so_charge c on c.id = l.so_charge_id
              where l.invoice_id = v_i.id and o.cancelled_at is null order by l.line_no loop
    select l.qbo_id into v_tax_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'tax_rule' and l.ims_id = v_l.tax_rule_id::text;
    v_item := null; v_need := null; v_desc := v_l.description; v_qty := 1; v_up := v_l.amount;
    if v_l.kind = 'product' then
      if v_l.product_id is null then raise exception 'Invoice % line % has no product — nothing was sent', v_i.invoice_number, v_l.line_no; end if;
      select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'product' and l.ims_id = v_l.product_id::text;
      if v_item is null then v_need := jsonb_build_object('kind', 'item', 'ims_id', v_l.product_id::text, 'name', v_l.sku); end if;
      if coalesce(v_l.discount_pct, 0) <> 0 and v_l.list_price is not null then v_desc := coalesce(v_desc, v_l.sku) || format(' (list %s, %s%% off)', trim_scale(v_l.list_price), trim_scale(v_l.discount_pct)); end if;
      v_qty := v_l.qty; v_up := coalesce(v_l.unit_price, 0);
    elsif v_l.kind = 'surcharge' then
      select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'surcharge';
      if v_item is null then v_need := jsonb_build_object('kind', 'item', 'ims_id', 'surcharge', 'name', 'Tariff Surcharge'); end if;
      v_qty := v_l.qty; v_up := coalesce(v_l.unit_price, 0);
    elsif v_l.kind = 'order_discount' then
      select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'discount';
      if v_item is null then raise exception 'IMS order discount has no QuickBooks item — link "discount" to the Discount item under Settings → QuickBooks matching — nothing was sent'; end if;
    elsif v_l.kind in ('charge', 'charge_discount') then
      if v_l.service_id is not null then
        select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'service' and l.ims_id = v_l.service_id::text;
        if v_item is null then raise exception 'Service "%" has no QuickBooks item — link it under Settings → QuickBooks matching — nothing was sent', v_l.charge_name; end if;
      elsif nullif(btrim(coalesce(v_l.charge_acct, '')), '') is null then
        raise exception 'Charge "%" has no account — nothing was sent', v_l.charge_name;
      elsif v_l.charge_acct = '_99_' then
        select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'freight';
        if v_item is null then raise exception 'IMS freight has no QuickBooks item — link "freight" to the Freight item under Settings → QuickBooks matching — nothing was sent'; end if;
      else
        select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'acct:' || v_l.charge_acct;
        if v_item is null then raise exception 'Charge "%" on account % has no QuickBooks item — link account item "acct:%" to a QuickBooks item under Settings → QuickBooks matching (951) — nothing was sent', v_l.charge_name, v_l.charge_acct, v_l.charge_acct; end if;
      end if;
      if v_l.kind = 'charge' and v_l.qty is not null then v_qty := v_l.qty; v_up := v_l.unit_price; end if;
    else
      raise exception 'Invoice % line % has unknown kind % — nothing was sent', v_i.invoice_number, v_l.line_no, v_l.kind;
    end if;
    if v_need is not null and not (v_needs @> jsonb_build_array(v_need)) then v_needs := v_needs || v_need; end if;
    v_lines := v_lines || jsonb_build_object('DetailType', 'SalesItemLineDetail', 'LineNum', v_l.line_no, 'Amount', v_l.amount, 'Description', left(coalesce(v_desc, ''), 4000),
                 'SalesItemLineDetail', jsonb_strip_nulls(jsonb_build_object('ItemRef', case when v_item is not null then jsonb_build_object('value', v_item) end, 'Qty', trim_scale(v_qty), 'UnitPrice', trim_scale(v_up),
                                                                             'TaxCodeRef', case when v_tax_ref is not null then jsonb_build_object('value', v_tax_ref) end)));
  end loop;
  if jsonb_array_length(v_lines) = 0 then raise exception 'Invoice % has no lines — nothing was sent', v_i.invoice_number; end if;
  return jsonb_build_object('kind', 'invoice', 'ims_kind', 'invoice', 'ims_id', p_invoice_id::text, 'name', v_i.invoice_number, 'doc_number', v_i.invoice_number, 'store_customer_id', v_store.id,
    'body', jsonb_strip_nulls(jsonb_build_object(
      'DocNumber', v_i.invoice_number, 'TxnDate', to_char(v_i.issued_on, 'YYYY-MM-DD'), 'DueDate', to_char(v_i.due_on, 'YYYY-MM-DD'),
      'CustomerRef', case when v_cust_ref is not null then jsonb_build_object('value', v_cust_ref) end,
      'SalesTermRef', case when v_term_ref is not null then jsonb_build_object('value', v_term_ref) end,
      'CurrencyRef', jsonb_build_object('value', v_cur),
      'BillAddr', case when v_bill <> '{}'::jsonb then v_bill end, 'ShipAddr', v_ship, 'BillEmail', case when v_email is not null then jsonb_build_object('Address', v_email) end,
      'PrivateNote', 'Customer Reference: ' || v_refs, 'CustomerMemo', jsonb_build_object('value', v_memo),                                                  -- qbo-trk-1 메모 둘째 줄 Tracking
      'ShipDate', to_char((v_so.shipped_at at time zone 'America/Toronto')::date, 'YYYY-MM-DD'), 'TrackingNum', v_trk,                                     -- qbo-trk-1 첫 오더의 첫 번호 · ≤ 31
      'GlobalTaxCalculation', 'TaxExcluded', 'Line', v_lines,
      'TxnTaxDetail', jsonb_build_object('TotalTax', v_i.tax_amount, 'TaxLine', v_tax_lines))),
    'needs', v_needs, 'warnings', to_jsonb(v_warn), 'line_count', jsonb_array_length(v_lines),
    'totals', jsonb_build_object('taxable', v_i.taxable_amount, 'tax', v_i.tax_amount, 'total', v_i.total));
end;
$$;
comment on function public.qbo_invoice_body(uuid) is 'qbo-sync-2b1 판정 935 ~ 946 · 951 · [qbo-trk-1 2026-11-06 TrackingNum 31 자: 첫 오더의 첫 송장번호만(넘으면 31 자 + 경고) · 전체 목록은 CustomerMemo 둘째 줄 「Tracking: …」(오더 여럿이면 「SO-1 a, b / SO-2 c」 · 1,000 자 넘으면 경계에서 자르고 「 …」 + 경고) · 송장 하나 · 31 자 이하면 몸 무변]: IMS 인보이스 → QBO Invoice 만들기 몸 — CustomerRef = 매장(so_invoice_order.customer_id · 둘 이상이면 실패) · SalesTermRef · CurrencyRef · BillAddr · ShipAddr(첫 오더) · BillEmail(doc_mail_recipient) · 메모 둘(939) · 줄 = so_invoice_line 그대로(ItemRef 는 qbo_link product · charge(surcharge · discount · freight · acct:<code>) · service · TaxCodeRef = 오더 규칙) · TxnTaxDetail(TotalTax + TaxLine · TaxRateRef 는 qbo_entity.detail) · 돌려주는 것 = { body · needs[{kind customer|item · ims_id}] · warnings · totals · line_count } · 짝이 없어 만들어야 하면 needs(claim 이 일감으로) · 사람 짝이 필요하면 예외(failed)';
