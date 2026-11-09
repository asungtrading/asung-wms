-- supabase/tests/qbo_sync_4_3a_check.sql — qbo-sync-4-3a 검증 (2026-11-09 · 판정 1115 ~ 1118 · 1121 · 1126 ~ 1130 · §0 이견 1 ~ 20 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] begin → (-v mig 면 \i) → 가짜 재료(DO 하나) → S1 Bill 몸 · S2 환율 없음 · S3 21 자 · S4 Vendor need · S5 취소 · 복원 · 다시 열기 · S6 VendorCredit · S7 비용 Bill · S8 백필 멱등 · S9 EF kinds(wrong_kind) · S10 list · preview · retry · W1 REST WHERE · G 구조 → rollback
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261109103000_qbo_sync_4_3a_supplier_bill_jobs.sql -f supabase/tests/qbo_sync_4_3a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(시험 · 확인 같다 · S0b 한 검사만 갈래마다 다르게 본다)
--   ⚠️ 가짜 재료만(공급처 ZZ-QBO43-* · PO-79431 · 인보이스 ZZ43-* · 비용 ZZ43-CH-* · 거울 zz43*) — 실제 공급처 · 인보이스 · 비용 · 결제 · 거울은 읽기만 · 백필이 실제 확정 인보이스 7 에 일감을 세우는 것은 마이그레이션의 몫(rollback)
--   ⚠️ po_invoice · po_charge 트리거 생성(SHARE ROW EXCLUSIVE) — 토론토 08:30 전 또는 17:00 뒤 · 공개 레포 — 상호를 찍지 않는다
\set ON_ERROR_STOP on
\pset pager off
\set EXPECT_OK 56
select (select value from public.inv_config where key = 'db_role') as db_role;
select (select realm_id from public.qbo_connection where singleton) as realm \gset

create temp table t_res (n serial, label text, got text, want text, ok boolean);
create temp table t_ids (k text primary key, v text);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns text language plpgsql as $$
begin
  insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want);
  return case when p_got is not distinct from p_want then 'OK   ' else 'FAIL ' end || p_label || case when p_got is not distinct from p_want then '' else format(' — got %s · want %s', coalesce(p_got, '(null)'), coalesce(p_want, '(null)')) end;
end $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
$$;
create function pg_temp.svc(p_sql text) returns jsonb language plpgsql as $$
declare v jsonb; v_claims text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute p_sql into v;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  return v;
end $$;
create function pg_temp.id(p_k text) returns text language sql as $$ select v from t_ids where k = p_k $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$ insert into t_ids values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.job(p_kind text, p_ims_kind text, p_ims_id text) returns public.qbo_job language sql as $$
  select j.* from public.qbo_job j where j.kind = p_kind and j.ims_kind = p_ims_kind and j.ims_id = p_ims_id order by j.created_at desc limit 1
$$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop
      v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g');
      exit when v_chunk = v_prev;
    end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;

-- ── 기준(begin 앞 · 잠금 없음) ──
select (select count(*) from public.ims_staff) as pre_staff, (select count(*) from public.supplier) as pre_sup, (select count(*) from public.po) as pre_po, (select count(*) from public.po_invoice) as pre_inv, (select count(*) from public.po_charge) as pre_chg,
       (select count(*) from public.po_payment) as pre_pay, (select count(*) from public.ref_tax_rule) as pre_tr, (select count(*) from public.qbo_entity) as pre_ent, (select count(*) from public.qbo_link) as pre_link,
       (select count(*) from public.qbo_job) as pre_jobs, (select count(*) from public.qbo_txn) as pre_txn, (select count(*) from public.po_invoice where status = 'confirmed' and doc_kind = 'invoice') as pre_conf_inv,
       (select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_open_or_add', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_list', 'qbo_job_retry', 'qbo_job_doc', 'qbo_entity_upsert')) as pre_md5_8,
       (select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_fail', 'qbo_job_skip', 'qbo_job_unknown', 'qbo_job_unknown_list', 'qbo_cost_expected')) as pre_md5_same,
       clock_timestamp() as t_begin \gset
\echo '── 기준: staff' :pre_staff '· suppliers' :pre_sup '· po' :pre_po '· invoices' :pre_inv '(confirmed' :pre_conf_inv ') · charges' :pre_chg '· jobs' :pre_jobs '· txn' :pre_txn '· realm' :realm

begin;
set local statement_timeout = '600s';
set local lock_timeout = '5s';
\if :{?mig}
\echo '── 시험 적용:' :mig
\i :mig
\endif
select clock_timestamp() as t_after_mig \gset

-- ── 가짜 재료(DO 하나) — 공급처 넷 · 거울 Vendor 둘 + Customer(이름 충돌) + TaxCode(매입 세율 있음) · 세금 규칙 하나 · PO 하나 + 줄 둘 · 인보이스 일곱 · 크레딧 하나 · 비용 셋 · 열쇠 직원 ──
do $$
declare v_usd uuid := (select id from public.ref_currency where code = 'USD'); v_cad uuid := (select id from public.ref_currency where code = 'CAD');
        v_ap_usd public.ref_account%rowtype; v_ap_cad public.ref_account%rowtype; v_term uuid := (select id from public.ref_payment_term where name = 'Due on receipt');
        v_zero uuid := (select id from public.ref_tax_rule where name = 'Zero-rated (Purchase)'); v_hst uuid := (select id from public.ref_tax_rule where name = 'HST ON (Purchase)'); v_oos uuid := (select id from public.ref_tax_rule where name = 'Out of Scope (Purchase)');
        v_prod uuid := (select id from public.product where sku = 'AAL10850'); v_realm text := (select realm_id from public.qbo_connection where singleton);
        v_sa uuid := gen_random_uuid(); v_sb uuid := gen_random_uuid(); v_sd uuid := gen_random_uuid(); v_se uuid := gen_random_uuid(); v_sf uuid := gen_random_uuid(); v_tr uuid := gen_random_uuid();
        v_po uuid := gen_random_uuid(); v_l1 uuid := gen_random_uuid(); v_l2 uuid := gen_random_uuid();
        v_i1 uuid := gen_random_uuid(); v_i2 uuid := gen_random_uuid(); v_i3 uuid := gen_random_uuid(); v_i4 uuid := gen_random_uuid(); v_i5 uuid := gen_random_uuid(); v_i6 uuid := gen_random_uuid(); v_i7 uuid := gen_random_uuid(); v_c1 uuid := gen_random_uuid();
        v_ch1 uuid := gen_random_uuid(); v_ch2 uuid := gen_random_uuid(); v_ch3 uuid := gen_random_uuid(); v_st uuid := gen_random_uuid(); v_staff uuid;
begin
  select * into v_ap_usd from public.ref_account where code = '_109_'; select * into v_ap_cad from public.ref_account where code = '_62_';
  if v_usd is null or v_cad is null or v_term is null or v_zero is null or v_hst is null or v_oos is null or v_prod is null or v_realm is null then raise exception 'fixture: a reference row is missing (currency · term · tax rule · product AAL10850 · realm)'; end if;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (v_st, 'zz-qbo-sync-4-3a@test.invalid', 'ZZ qbo-sync-4-3a bookkeeper', 'manager', '["ims", "qbo", "purchasing"]', '{}') returning id into v_staff;
  insert into public.supplier (id, name, source, is_active, payment_term_id, payment_term_name, account_payable_id, account_payable_code, currency_id) values
    (v_sa, 'ZZ-QBO43 Supplier A', 'manual', true, v_term, 'Due on receipt', v_ap_usd.id, v_ap_usd.code, v_usd),
    (v_sb, 'ZZ-QBO43 Supplier B', 'manual', true, v_term, 'Due on receipt', v_ap_cad.id, v_ap_cad.code, v_cad),
    (v_sd, 'ZZ-QBO43 Dup Name',   'manual', true, v_term, 'Due on receipt', v_ap_cad.id, v_ap_cad.code, v_cad),
    (v_se, 'ZZ-QBO43 Supplier E', 'manual', true, v_term, 'Due on receipt', v_ap_cad.id, v_ap_cad.code, v_cad),
    (v_sf, 'ZZ-QBO43 Supplier F', 'manual', true, v_term, 'Due on receipt', v_ap_cad.id, v_ap_cad.code, v_cad);
  insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, active) values (v_realm, 'Vendor', 'zz43va', 'ZZ-QBO43 Vendor A', true), (v_realm, 'Vendor', 'zz43ve', 'ZZ-QBO43 Vendor E', true), (v_realm, 'Customer', 'zz43dup', 'ZZ-QBO43 Dup Name', true);
  insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, active, detail) values (v_realm, 'TaxCode', 'zz43tc', 'ZZ-QBO43 Tax', true,
    '{"TaxRateDetail": [{"TaxRateRef": {"value": "zz43sr"}}], "PurchaseTaxRateList": {"TaxRateDetail": [{"TaxRateRef": {"value": "zz43pr"}}]}}'::jsonb);
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by) values (v_realm, 'supplier', v_sa::text, 'Vendor', 'zz43va', 'manual'), (v_realm, 'supplier', v_se::text, 'Vendor', 'zz43ve', 'manual');
  insert into public.ref_tax_rule (id, name, source, is_active, rate_pct, direction) values (v_tr, 'ZZ-QBO43 GST 5', 'manual', true, 5, 'purchase');
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by) values (v_realm, 'tax_rule', v_tr::text, 'TaxCode', 'zz43tc', 'manual');
  insert into public.po (id, po_number, status, supplier_id, currency_id) values (v_po, 'PO-79431', 'confirmed', v_sa, v_usd);
  insert into public.po_line (id, po_id, line_no, product_id, qty_ea, unit_price) values (v_l1, v_po, 1, v_prod, 100, 2.5), (v_l2, v_po, 2, v_prod, 100, 3.333);
  -- 인보이스 — I1 USD 1.4 두 줄 + 할인 5%(25.00 + 13.33 = 38.33 → 36.41 · 할인 1.92) · I2 환율 없음 · I3 번호 25 자 · I4 공급처 B(Vendor 짝 없음 · CAD) · I5 sent 꾸밈용 · I6 다시 열기용 · I7 이름 충돌 공급처 D
  insert into public.po_invoice (id, supplier_id, invoice_number, invoice_date, due_date, payment_term_id, payment_term_name, currency_id, exchange_rate, total_amount, status, doc_kind, tax_rule_id) values
    (v_i1, v_sa, 'ZZ43-INV-1', public.ims_today(), public.ims_today() + 30, v_term, 'Due on receipt', v_usd, 1.4, 36.41, 'draft', 'invoice', v_zero),
    (v_i2, v_sa, 'ZZ43-INV-2', public.ims_today(), null, v_term, 'Due on receipt', v_usd, null, 10, 'draft', 'invoice', v_zero),
    (v_i3, v_sa, 'ZZ43-INVOICE-NUMBER-25CHR', public.ims_today(), public.ims_today(), v_term, 'Due on receipt', v_usd, 1.3, 10, 'draft', 'invoice', v_zero),
    (v_i4, v_sb, 'ZZ43-INV-4', public.ims_today(), public.ims_today(), v_term, 'Due on receipt', v_cad, null, 10, 'draft', 'invoice', v_zero),
    (v_i5, v_sa, 'ZZ43-INV-5', public.ims_today(), public.ims_today(), v_term, 'Due on receipt', v_usd, 1.4, 10, 'draft', 'invoice', v_zero),
    (v_i6, v_sa, 'ZZ43-INV-6', public.ims_today(), public.ims_today(), v_term, 'Due on receipt', v_usd, 1.4, 10, 'draft', 'invoice', v_zero),
    (v_i7, v_sd, 'ZZ43-INV-7', public.ims_today(), public.ims_today(), v_term, 'Due on receipt', v_cad, null, 10, 'draft', 'invoice', v_zero),
    (v_c1, v_sa, 'ZZ43-CR-1', public.ims_today(), null, null, null, v_usd, 1.4, 5, 'draft', 'credit', v_zero);
  update public.po_invoice set credit_for_invoice_id = v_i1 where id = v_c1;
  insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price) values
    (v_i1, 1, 'goods', v_l1, 10, 2.5), (v_i1, 2, 'goods', v_l2, 4, 3.333),
    (v_i2, 1, 'goods', v_l1, 4, 2.5), (v_i3, 1, 'goods', v_l1, 4, 2.5), (v_i4, 1, 'goods', v_l1, 4, 2.5), (v_i5, 1, 'goods', v_l1, 4, 2.5), (v_i6, 1, 'goods', v_l1, 4, 2.5), (v_i7, 1, 'goods', v_l1, 4, 2.5);
  insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, credit_reason) values (v_c1, 1, 'goods', v_l1, 2, 2.5, 'price_difference');
  insert into public.po_invoice_discount (po_invoice_id, seq, name, percent) values (v_i1, 1, 'Early', 5);
  -- 비용 — CH1 duty 0 + 600.26(Out of Scope · M10 꼴) · CH2 freight 408.76 + 20.44(가짜 5% 규칙 · 매입 세율 있음) · CH3 brokerage 90 + 11.70(실제 HST ON · 매입 세율 없음 → 막힘)
  insert into public.po_charge (id, supplier_id, charge_number, charge_date, due_date, kind, currency_id, total_amount, tax_amount, status, tax_rule_id) values
    (v_ch1, v_se, 'ZZ43-CH-1', public.ims_today(), null, 'duty', v_cad, 0, 600.26, 'draft', v_oos),
    (v_ch2, v_se, 'ZZ43-CH-2', public.ims_today(), public.ims_today() + 15, 'freight', v_cad, 408.76, 20.44, 'draft', v_tr),
    (v_ch3, v_se, 'ZZ43-CH-3', public.ims_today(), null, 'brokerage', v_cad, 90, 11.70, 'draft', v_hst);
  insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (v_ch1, v_po, 0), (v_ch2, v_po, 408.76), (v_ch3, v_po, 90);
  perform pg_temp.put('staff', v_staff::text); perform pg_temp.put('st_uid', v_st::text); perform pg_temp.put('sa', v_sa::text); perform pg_temp.put('sb', v_sb::text); perform pg_temp.put('sd', v_sd::text); perform pg_temp.put('se', v_se::text); perform pg_temp.put('sf', v_sf::text);
  perform pg_temp.put('i1', v_i1::text); perform pg_temp.put('i2', v_i2::text); perform pg_temp.put('i3', v_i3::text); perform pg_temp.put('i4', v_i4::text); perform pg_temp.put('i5', v_i5::text); perform pg_temp.put('i6', v_i6::text); perform pg_temp.put('i7', v_i7::text); perform pg_temp.put('c1', v_c1::text);
  perform pg_temp.put('ch1', v_ch1::text); perform pg_temp.put('ch2', v_ch2::text); perform pg_temp.put('ch3', v_ch3::text);
end $$;

-- ── S1 USD 인보이스 확정 → bill 일감 1 · 몸(ExchangeRate · APAccountRef · DueDate · TxnTaxDetail · 줄 수 · 할인 음수 줄 · 계정 GINR · 상호 없음) ──
do $$
declare v_j public.qbo_job; v_b jsonb; v_m record; v_st uuid := pg_temp.id('staff')::uuid;
begin
  update public.po_invoice set status = 'confirmed', confirmed_by = v_st, confirmed_at = now() where id = pg_temp.id('i1')::uuid;
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i1'));
  perform pg_temp.chk('S1a 확정 트리거: bill · po_invoice 일감 queued 하나 · by_staff = confirmed_by', coalesce(v_j.state, '(none)') || ' ' || (v_j.by_staff = v_st)::text || ' ' || (select count(*) from public.qbo_job where ims_id = pg_temp.id('i1'))::text, 'queued true 1');
  select * into v_m from public.po_invoice_money where id = pg_temp.id('i1')::uuid;
  perform pg_temp.chk('S1b 돈 뷰: goods 38.33 · factor 0.95 · taxable 36.41 · tax 0 · computed 36.41 · diff 0', v_m.goods_sum::text || ' ' || trim_scale(v_m.factor)::text || ' ' || v_m.taxable_amount::text || ' ' || coalesce(v_m.tax_amount, 0)::text || ' ' || v_m.computed_total::text || ' ' || v_m.diff::text, '38.33 0.95 36.41 0.00 36.41 0.00');
  v_b := public.qbo_bill_body(pg_temp.id('i1')::uuid, 'bill');
  perform pg_temp.chk('S1c 몸 머리: kind bill · ims_kind po_invoice · DocNumber ZZ43-INV-1 · ExchangeRate 1.4 · CurrencyRef USD · APAccountRef 109(_109_ 짝) · VendorRef zz43va · DueDate 있음 · SalesTermRef 있음 · GlobalTaxCalculation TaxExcluded',
    (v_b->>'kind') || ' ' || (v_b->>'ims_kind') || ' ' || (v_b->'body'->>'DocNumber') || ' ' || (v_b->'body'->>'ExchangeRate') || ' ' || (v_b->'body'->'CurrencyRef'->>'value') || ' ' || (v_b->'body'->'APAccountRef'->>'value') || ' ' || (v_b->'body'->'VendorRef'->>'value')
      || ' ' || (v_b->'body' ? 'DueDate')::text || ' ' || (v_b->'body' ? 'SalesTermRef')::text || ' ' || (v_b->'body'->>'GlobalTaxCalculation'),
    'bill po_invoice ZZ43-INV-1 1.4 USD 109 zz43va true true TaxExcluded');
  perform pg_temp.chk('S1d 줄: 3(goods 2 + 할인 1) · 금액 25.00 · 13.33 · −1.92 · 계정 모두 GINR 1150040012 · 세금 코드 Zero-rated 2 · 첫 줄 설명 「AAL10850 × 10 @ 2.5 · PO PO-79431」 · 할인 설명 「Discount Early 5%」',
    (v_b->>'line_count') || ' ' || (select string_agg(x->>'Amount', ' ' order by (x->>'LineNum')::int) from jsonb_array_elements(v_b->'body'->'Line') x)
      || ' ' || (select string_agg(distinct x->'AccountBasedExpenseLineDetail'->'AccountRef'->>'value', ',') from jsonb_array_elements(v_b->'body'->'Line') x)
      || ' ' || (select string_agg(distinct x->'AccountBasedExpenseLineDetail'->'TaxCodeRef'->>'value', ',') from jsonb_array_elements(v_b->'body'->'Line') x)
      || ' | ' || (v_b->'body'->'Line'->0->>'Description') || ' | ' || (v_b->'body'->'Line'->2->>'Description'),
    '3 25.00 13.33 -1.92 1150040012 2 | AAL10850 × 10 @ 2.5 · PO PO-79431 | Discount Early 5%');
  perform pg_temp.chk('S1e 세금 · 합계 · 열쇠: TxnTaxDetail TotalTax 0 · TaxLine 없음(세금 0) · totals.total 36.41 · fingerprint 「3641|USD」 · lookup entity Bill · vendor_ref zz43va · total_cents 3641 · needs 0 · warnings 0',
    (v_b->'body'->'TxnTaxDetail'->>'TotalTax') || ' ' || (v_b->'body'->'TxnTaxDetail' ? 'TaxLine')::text || ' ' || (v_b->'totals'->>'total') || ' ' || (v_b->>'fingerprint') || ' ' || (v_b->'lookup'->>'entity') || ' ' || (v_b->'lookup'->>'vendor_ref') || ' ' || (v_b->'lookup'->>'total_cents')
      || ' ' || jsonb_array_length(v_b->'needs')::text || ' ' || jsonb_array_length(v_b->'warnings')::text,
    '0.00 false 36.41 3641|USD Bill zz43va 3641 0 0');
  perform pg_temp.chk('S1f 몸에 공급처 상호 없음 · PrivateNote 「IMS supplier invoice ZZ43-INV-1 · PO PO-79431」', ((v_b->'body')::text ilike '%Supplier A%')::text || ' | ' || (v_b->'body'->>'PrivateNote'), 'false | IMS supplier invoice ZZ43-INV-1 · PO PO-79431');
end $$;

-- ── S2 환율 없음 → claim 에서 failed(1118) · S3 번호 25 자 → DocNumber 21 · PrivateNote 전체 · S7 비용 셋 · S6 크레딧 ──
do $$
declare v_st uuid := pg_temp.id('staff')::uuid; v_r jsonb; v_j public.qbo_job; v_b jsonb; v_e text;
begin
  update public.po_invoice set status = 'confirmed', confirmed_by = v_st, confirmed_at = now() where id in (pg_temp.id('i2')::uuid, pg_temp.id('i3')::uuid, pg_temp.id('i4')::uuid, pg_temp.id('i5')::uuid, pg_temp.id('i6')::uuid, pg_temp.id('i7')::uuid, pg_temp.id('c1')::uuid);
  update public.po_charge set status = 'confirmed', confirmed_by = v_st, confirmed_at = now() where id in (pg_temp.id('ch1')::uuid, pg_temp.id('ch2')::uuid, pg_temp.id('ch3')::uuid);
  perform pg_temp.chk('S2a 확정 일곱 + 비용 셋: bill(po_invoice) 7 · vendor_credit(po_credit) 1 · bill(po_charge) 3 — 모두 queued', (select count(*) from public.qbo_job where kind = 'bill' and ims_kind = 'po_invoice' and ims_id like any (array[pg_temp.id('i1'), pg_temp.id('i2'), pg_temp.id('i3'), pg_temp.id('i4'), pg_temp.id('i5'), pg_temp.id('i6'), pg_temp.id('i7')]) and state = 'queued')::text
    || ' ' || (select count(*) from public.qbo_job where kind = 'vendor_credit' and ims_kind = 'po_credit' and ims_id = pg_temp.id('c1') and state = 'queued')::text
    || ' ' || (select count(*) from public.qbo_job where kind = 'bill' and ims_kind = 'po_charge' and ims_id in (pg_temp.id('ch1'), pg_temp.id('ch2'), pg_temp.id('ch3')) and state = 'queued')::text, '7 1 3');
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i2'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill'], array[%L::uuid])$q$, v_j.id));
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i2'));
  perform pg_temp.chk('S2b 환율 없는 USD 인보이스: claim → body_failed 1 · 일감 failed · 글 「has no exchange rate … (1118)」', (v_r->>'body_failed') || ' ' || v_j.state || ' ' || (v_j.last_error ~ 'has no exchange rate.*1118')::text, '1 failed true');
  v_b := public.qbo_bill_body(pg_temp.id('i3')::uuid);
  perform pg_temp.chk('S3 번호 25 자: DocNumber 21 자 「ZZ43-INVOICE-NUMBER-2」 · PrivateNote 에 전체 · 경고 1130 · name 은 IMS 번호 그대로', (v_b->'body'->>'DocNumber') || ' ' || length(v_b->'body'->>'DocNumber')::text || ' ' || ((v_b->'body'->>'PrivateNote') like '%full number: ZZ43-INVOICE-NUMBER-25CHR')::text || ' ' || ((v_b->'warnings')::text ~ '1130')::text || ' ' || (v_b->>'name'),
    'ZZ43-INVOICE-NUMBER-2 21 true true ZZ43-INVOICE-NUMBER-25CHR');
  -- S6 크레딧
  v_b := public.qbo_vendor_credit_body(pg_temp.id('c1')::uuid);
  perform pg_temp.chk('S6a VendorCredit 몸: kind vendor_credit · ims_kind po_credit · DocNumber ZZ43-CR-1 · DueDate · SalesTermRef 없음 · APAccountRef 109 · 줄 1 계정 GINR · 금액 5.00 · 설명 꼬리 「price difference」 · PrivateNote 「for invoice ZZ43-INV-1」 · lookup entity VendorCredit · ExchangeRate 1.4',
    (v_b->>'kind') || ' ' || (v_b->>'ims_kind') || ' ' || (v_b->'body'->>'DocNumber') || ' ' || (v_b->'body' ? 'DueDate')::text || ' ' || (v_b->'body' ? 'SalesTermRef')::text || ' ' || (v_b->'body'->'APAccountRef'->>'value') || ' ' || (v_b->>'line_count') || ' ' || (v_b->'body'->'Line'->0->'AccountBasedExpenseLineDetail'->'AccountRef'->>'value')
      || ' ' || (v_b->'body'->'Line'->0->>'Amount') || ' ' || ((v_b->'body'->'Line'->0->>'Description') like '%· price difference')::text || ' ' || ((v_b->'body'->>'PrivateNote') like '%for invoice ZZ43-INV-1%')::text || ' ' || (v_b->'lookup'->>'entity') || ' ' || (v_b->'body'->>'ExchangeRate'),
    'vendor_credit po_credit ZZ43-CR-1 false false 109 1 1150040012 5.00 true true VendorCredit 1.4');
  perform pg_temp.chk('S6b 몸 kind 검사: 크레딧을 bill 로 부르면 거부 · 인보이스를 vendor_credit 으로 부르면 거부', (pg_temp.try(format($q$select public.qbo_bill_body(%L::uuid, 'bill')::text$q$, pg_temp.id('c1'))) ~ 'is a supplier credit')::text || ' ' || (pg_temp.try(format($q$select public.qbo_vendor_credit_body(%L::uuid)::text$q$, pg_temp.id('i1'))) ~ 'is a supplier invoice')::text, 'true true');
  -- S7 비용 Bill
  v_b := public.qbo_charge_bill_body(pg_temp.id('ch1')::uuid);
  perform pg_temp.chk('S7a duty 「0 + 600.26」: 줄 1 = #125 줄(계정 125 · 금액 600.26 · 세금 코드 Out of Scope 4 · 설명 「GST on import · Duty ZZ43-CH-1 · PO-79431」) · TotalTax 0 · total 600.26 · fingerprint 「60026|CAD」 · DueDate = charge_date + 경고',
    (v_b->>'line_count') || ' ' || (v_b->'body'->'Line'->0->'AccountBasedExpenseLineDetail'->'AccountRef'->>'value') || ' ' || (v_b->'body'->'Line'->0->>'Amount') || ' ' || (v_b->'body'->'Line'->0->'AccountBasedExpenseLineDetail'->'TaxCodeRef'->>'value') || ' | ' || (v_b->'body'->'Line'->0->>'Description')
      || ' | ' || (v_b->'body'->'TxnTaxDetail'->>'TotalTax') || ' ' || (v_b->'totals'->>'total') || ' ' || (v_b->>'fingerprint') || ' ' || (v_b->'body' ? 'DueDate')::text || ' ' || ((v_b->'warnings')::text ~ 'no due date')::text,
    '1 125 600.26 4 | GST on import · Duty ZZ43-CH-1 · PO-79431 | 0 600.26 60026|CAD true true');
  v_b := public.qbo_charge_bill_body(pg_temp.id('ch2')::uuid);
  perform pg_temp.chk('S7b freight 408.76 + 20.44(가짜 5% 규칙 · 매입 세율 zz43pr): 줄 1 계정 136 · 세금 코드 zz43tc · TaxLine 1(TaxRateRef zz43pr · TaxPercent 5 · NetAmountTaxable 408.76 · Amount 20.44) · TotalTax 20.44 · total 429.20 · ims_kind po_charge · DueDate 있음 · 경고 0',
    (v_b->>'line_count') || ' ' || (v_b->'body'->'Line'->0->'AccountBasedExpenseLineDetail'->'AccountRef'->>'value') || ' ' || (v_b->'body'->'Line'->0->'AccountBasedExpenseLineDetail'->'TaxCodeRef'->>'value') || ' ' || jsonb_array_length(v_b->'body'->'TxnTaxDetail'->'TaxLine')::text
      || ' ' || (v_b->'body'->'TxnTaxDetail'->'TaxLine'->0->'TaxLineDetail'->'TaxRateRef'->>'value') || ' ' || (v_b->'body'->'TxnTaxDetail'->'TaxLine'->0->'TaxLineDetail'->>'TaxPercent') || ' ' || (v_b->'body'->'TxnTaxDetail'->'TaxLine'->0->'TaxLineDetail'->>'NetAmountTaxable') || ' ' || (v_b->'body'->'TxnTaxDetail'->'TaxLine'->0->>'Amount')
      || ' ' || (v_b->'body'->'TxnTaxDetail'->>'TotalTax') || ' ' || (v_b->'totals'->>'total') || ' ' || (v_b->>'ims_kind') || ' ' || (v_b->'body' ? 'DueDate')::text || ' ' || jsonb_array_length(v_b->'warnings')::text,
    '1 136 zz43tc 1 zz43pr 5 408.76 20.44 20.44 429.20 po_charge true 0');
  v_e := pg_temp.try(format($q$select public.qbo_charge_bill_body(%L::uuid)::text$q$, pg_temp.id('ch3')));
  perform pg_temp.chk('S7c brokerage + HST ON(실제 거울 = SalesTaxRateList 만): 몸이 막는다 「has no purchase tax rate on file … Refresh list」(§0 이견 7 · 4-4 뒤 풀림)', (v_e ~ 'has no purchase tax rate on file')::text || ' ' || (v_e ~ 'Refresh list')::text, 'true true');
  perform pg_temp.chk('S7d 실제 확정 인보이스 몸 7: USD Zero-rated 6 장은 몸이 선다(needs 0 · TotalTax 0) · CAD HST 1 장(Order #8884650)은 매입 세율 없음으로 막힌다',
    (select count(*) filter (where pg_temp.try(format($q$select public.qbo_bill_body(%L::uuid)::text$q$, i.id)) not like 'ERR %')::text || ' ' || count(*) filter (where pg_temp.try(format($q$select public.qbo_bill_body(%L::uuid)::text$q$, i.id)) ~ 'has no purchase tax rate')::text
       from public.po_invoice i where i.status = 'confirmed' and i.doc_kind = 'invoice' and i.invoice_number not like 'ZZ43-%'), '6 1');
end $$;

-- ── S4 Vendor 짝 없는 공급처 → claim: vendor need 일감 먼저 · 이 일감 blocked → done(vendor) → 풀림 · 이름 충돌 공급처 → failed(1128) ──
do $$
declare v_j public.qbo_job; v_v public.qbo_job; v_r jsonb; v_b jsonb; v_d jsonb;
begin
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i4'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill'], array[%L::uuid])$q$, v_j.id));
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i4'));
  v_v := pg_temp.job('vendor', 'supplier', pg_temp.id('sb'));
  perform pg_temp.chk('S4a claim: blocked_for_needs 1 · need_jobs 1(kind vendor · ims_kind supplier · state queued) · bill 일감 blocked · blocked_by = vendor 일감 · warning 「waiting for 1 QuickBooks record」',
    (v_r->>'blocked_for_needs') || ' ' || jsonb_array_length(v_r->'need_jobs')::text || ' ' || (v_r->'need_jobs'->0->>'kind') || ' ' || (v_r->'need_jobs'->0->>'ims_kind') || ' ' || (v_r->'need_jobs'->0->>'state') || ' ' || v_j.state || ' ' || (v_j.blocked_by = v_v.id)::text || ' ' || (v_j.warning ~ 'waiting for 1 QuickBooks record')::text,
    '1 1 vendor supplier queued blocked true true');
  v_b := public.qbo_vendor_body(pg_temp.id('sb')::uuid);
  perform pg_temp.chk('S4b Vendor 몸(1128): 키 둘뿐(DisplayName · CurrencyRef) · DisplayName = 공급처 이름 · CurrencyRef CAD · A/P 없음 · ims_kind supplier', (select string_agg(k, ',' order by k) from jsonb_object_keys(v_b->'body') k) || ' ' || (v_b->'body'->>'DisplayName') || ' ' || (v_b->'body'->'CurrencyRef'->>'value') || ' ' || (v_b->>'ims_kind'), 'CurrencyRef,DisplayName ZZ-QBO43 Supplier B CAD supplier');
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['vendor'], array[%L::uuid])$q$, v_v.id));
  perform pg_temp.chk('S4c claim(vendor): claimed 1 · jobs[0].name = DisplayName · body 키 둘', (v_r->>'claimed') || ' ' || (v_r->'jobs'->0->>'name') || ' ' || jsonb_array_length(coalesce((select jsonb_agg(k) from jsonb_object_keys(v_r->'jobs'->0->'body') k), '[]'::jsonb))::text, '1 ZZ-QBO43 Supplier B 2');
  v_d := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz43vb', 'ZZ-QBO43 Supplier B')$q$, v_v.id));
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i4'));
  perform pg_temp.chk('S4d done(vendor): sent · linked · qbo_link supplier created(zz43vb) · 거울 Vendor zz43vb · 자식 bill 일감 queued(unblocked 1)', (v_d->>'state') || ' ' || (v_d->>'linked') || ' ' || (select l.qbo_id || ' ' || l.matched_by from public.qbo_link l where l.ims_kind = 'supplier' and l.ims_id = pg_temp.id('sb')) || ' ' || (select count(*) from public.qbo_entity e where e.qbo_type = 'Vendor' and e.qbo_id = 'zz43vb')::text || ' ' || v_j.state || ' ' || (v_d->>'unblocked'), 'sent true zz43vb created 1 queued 1');
  v_b := public.qbo_bill_body(pg_temp.id('i4')::uuid);
  perform pg_temp.chk('S4e 짝이 생긴 뒤 몸: needs 0 · VendorRef zz43vb · APAccountRef 62(CAD A/P) · ExchangeRate 없음(CAD)', jsonb_array_length(v_b->'needs')::text || ' ' || (v_b->'body'->'VendorRef'->>'value') || ' ' || (v_b->'body'->'APAccountRef'->>'value') || ' ' || (v_b->'body' ? 'ExchangeRate')::text, '0 zz43vb 62 false');
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i7'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill'], array[%L::uuid])$q$, v_j.id));
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i7'));
  perform pg_temp.chk('S4f 이름 충돌 공급처(QBO Customer 와 같은 이름): need 몸이 거부 → bill 일감 failed · 글 「already has a customer or supplier named」 · vendor 일감 0(자동 개명 없음 · 사람 짝)', v_j.state || ' ' || (v_j.last_error ~ 'already has a customer or supplier named')::text || ' ' || (select count(*) from public.qbo_job where kind = 'vendor' and ims_id = pg_temp.id('sd'))::text, 'failed true 0');
  perform pg_temp.chk('S4g qbo_job_open_or_add(vendor): 새 공급처 F → 일감 새로(existing false) · 두 번째는 같은 열린 일감(existing true) · 이미 짝 있는 공급처 거부 · uuid 아님 거부', ((public.qbo_job_open_or_add('vendor', pg_temp.id('sf'), null))->>'existing') || ' ' || ((public.qbo_job_open_or_add('vendor', pg_temp.id('sf'), null))->>'existing') || ' ' || (pg_temp.try(format($q$select public.qbo_job_open_or_add('vendor', %L, null)::text$q$, pg_temp.id('sa'))) ~ 'already linked to a QuickBooks vendor')::text || ' ' || (pg_temp.try($q$select public.qbo_job_open_or_add('vendor', 'not-a-uuid', null)::text$q$) ~ 'must be a supplier id')::text, 'false true true true');
end $$;

-- ── S5 취소(안 나감 → skipped) · 취소(sent → bill_delete_manual queued + txn voided) · 복원(새 bill blocked 뒤 · skip 하면 풀림) · 다시 열기(skipped) · S9 EF kinds ──
do $$
declare v_st uuid := pg_temp.id('staff')::uuid; v_j public.qbo_job; v_d public.qbo_job; v_n public.qbo_job; v_r jsonb; v_t public.qbo_txn%rowtype; v_realm text := (select realm_id from public.qbo_connection where singleton);
begin
  -- (a) I6: queued → 다시 열기(confirmed → draft) → skipped
  update public.po_invoice set status = 'draft', confirmed_by = null, confirmed_at = null where id = pg_temp.id('i6')::uuid;
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i6'));
  perform pg_temp.chk('S5a 다시 열기(confirmed → draft · 안 나감): bill 일감 skipped · note 「reopened before sending」', v_j.state || ' ' || v_j.note, 'skipped reopened before sending');
  -- (b) I3: queued → 취소 → skipped
  update public.po_invoice set status = 'cancelled', cancelled_by = v_st, cancelled_at = now() where id = pg_temp.id('i3')::uuid;
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i3'));
  perform pg_temp.chk('S5b 취소(안 나감): skipped · note 「cancelled before sending」 · bill_delete_manual 0', v_j.state || ' ' || v_j.note || ' ' || (select count(*) from public.qbo_job where kind = 'bill_delete_manual' and ims_id = pg_temp.id('i3'))::text, 'skipped cancelled before sending 0');
  -- (c) I5: sent 로 꾸민다(일감 sent + qbo_txn Bill) → 취소 → bill_delete_manual queued · txn voided_at
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i5'));
  update public.qbo_job set state = 'sent', sent_at = now(), qbo_id = 'zz43bill5', qbo_name = 'ZZ43-INV-5', fingerprint = '1000|USD' where id = v_j.id;
  insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, total_amt, total_tax, job_id, fingerprint, source) values (v_realm, 'po_invoice', pg_temp.id('i5'), 'Bill', 'zz43bill5', 'ZZ43-INV-5', 10, 0, v_j.id, '1000|USD', 'sent');
  update public.po_invoice set status = 'cancelled', cancelled_by = v_st, cancelled_at = now() where id = pg_temp.id('i5')::uuid;
  v_d := pg_temp.job('bill_delete_manual', 'po_invoice', pg_temp.id('i5'));
  select * into v_t from public.qbo_txn t where t.ims_kind = 'po_invoice' and t.ims_id = pg_temp.id('i5');
  perform pg_temp.chk('S5c 취소(sent): bill_delete_manual queued · note 에 QBO Id zz43bill5 · 「delete … by hand, then press Skip」 · qbo_txn voided_at 찍힘 · sent 일감 그대로', coalesce(v_d.state, '(none)') || ' ' || (v_d.note ~ 'zz43bill5')::text || ' ' || (v_d.note ~ 'by hand, then press Skip')::text || ' ' || (v_t.voided_at is not null)::text || ' ' || (select state from public.qbo_job where id = v_j.id), 'queued true true true sent');
  -- 복원 → 새 bill 은 열린 bill_delete_manual 뒤(blocked)
  update public.po_invoice set status = 'confirmed', cancelled_by = null, cancelled_at = null where id = pg_temp.id('i5')::uuid;
  v_n := pg_temp.job('bill', 'po_invoice', pg_temp.id('i5'));
  perform pg_temp.chk('S5d 복원(cancelled → confirmed): 새 bill 일감 blocked · blocked_by = bill_delete_manual · warning 「deleted from QuickBooks by hand … skipped (1126)」 · 옛 sent 일감과 다른 행', v_n.state || ' ' || (v_n.blocked_by = v_d.id)::text || ' ' || (v_n.warning ~ 'deleted from QuickBooks by hand')::text || ' ' || (v_n.id <> v_j.id)::text, 'blocked true true true');
  -- 사람이 QBO 에서 지우고 Skip → claim ② 가 새 bill 을 푼다
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  perform pg_temp.chk('S5e retry 거부(queued bill_delete_manual): 상태 검사가 먼저 「Only a failed or skipped job」', (pg_temp.try(format($q$select public.qbo_job_retry(%L::uuid, 'zz')::text$q$, v_d.id)) ~ 'Only a failed or skipped job')::text, 'true');
  v_r := public.qbo_job_skip(v_d.id, 'ZZ43: deleted Bill zz43bill5 in QuickBooks');
  perform pg_temp.chk('S5e2 retry 거부(skipped bill_delete_manual): 「closed with Skip … never sent」 — 되살릴 수 없다(1126)', (pg_temp.try(format($q$select public.qbo_job_retry(%L::uuid, 'zz')::text$q$, v_d.id)) ~ 'closed with Skip')::text, 'true');
  perform pg_temp.as_user(null);
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill'], array[%L::uuid])$q$, v_n.id));
  v_n := pg_temp.job('bill', 'po_invoice', pg_temp.id('i5'));
  perform pg_temp.chk('S5f Skip 뒤 claim: unblocked ≥ 1 · 새 bill 일감 claimed → sending · request_id 는 옛 sent 일감과 다르다', ((v_r->>'unblocked')::int >= 1)::text || ' ' || (v_r->>'claimed') || ' ' || v_n.state || ' ' || (v_n.request_id <> v_j.request_id)::text, 'true 1 sending true');
  -- done(새 bill) → qbo_txn 이 새 Bill 로 바뀌고 voided_at 풀림
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz43bill5b', 'ZZ43-INV-5', '0', null, null, null, 10.00, 0)$q$, v_n.id));
  select * into v_t from public.qbo_txn t where t.ims_kind = 'po_invoice' and t.ims_id = pg_temp.id('i5');
  perform pg_temp.chk('S5g done(새 bill · TotalAmt 10.00 = 지문 1000): sent · mismatch 없음 · qbo_txn 한 행 · qbo_id zz43bill5b · voided_at null · qbo_type Bill', (v_r->>'state') || ' ' || (v_r->>'linked') || ' ' || (select count(*) from public.qbo_txn t where t.ims_kind = 'po_invoice' and t.ims_id = pg_temp.id('i5'))::text || ' ' || v_t.qbo_id || ' ' || (v_t.voided_at is null)::text || ' ' || v_t.qbo_type || ' ' || coalesce(v_t.mismatch, '-'), 'sent true 1 zz43bill5b true Bill -');
  -- (d) I1 claim → done 금액 다르게 → warning(942 꼴) · 지문
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i1'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill'], array[%L::uuid])$q$, v_j.id));
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i1'));
  perform pg_temp.chk('S5h claim(I1): sending · fingerprint 「3641|USD」 · jobs[0].lookup.total_cents 3641 · doc_number ZZ43-INV-1', v_j.state || ' ' || v_j.fingerprint || ' ' || (v_r->'jobs'->0->'lookup'->>'total_cents') || ' ' || (v_r->'jobs'->0->>'doc_number'), 'sending 3641|USD 3641 ZZ43-INV-1');
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz43bill1', 'ZZ43-INV-1', '0', null, null, null, 36.40, 0)$q$, v_j.id));
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i1'));
  perform pg_temp.chk('S5i done(I1 · TotalAmt 36.40 ≠ 36.41): sent 이지만 warning 「differs from IMS 36.41 … (942)」 · qbo_txn mismatch 글 · total_amt 36.40', v_j.state || ' ' || (v_j.warning ~ 'differs from IMS 36.41')::text || ' ' || (v_j.warning ~ '942')::text || ' ' || (select (t.mismatch is not null)::text || ' ' || t.total_amt::text from public.qbo_txn t where t.ims_kind = 'po_invoice' and t.ims_id = pg_temp.id('i1')), 'sent true true true 36.40');
  -- (e) 크레딧 claim → done → qbo_txn VendorCredit
  v_j := pg_temp.job('vendor_credit', 'po_credit', pg_temp.id('c1'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['vendor_credit'], array[%L::uuid])$q$, v_j.id));
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz43vc1', 'ZZ43-CR-1', '0', null, null, null, 5.00, 0)$q$, v_j.id));
  perform pg_temp.chk('S6c 크레딧 claim → done(5.00): sent · qbo_txn po_credit ↔ VendorCredit · mismatch 없음', (v_r->>'state') || ' ' || (select t.qbo_type || ' ' || coalesce(t.mismatch, '-') from public.qbo_txn t where t.ims_kind = 'po_credit' and t.ims_id = pg_temp.id('c1')), 'sent VendorCredit -');
  -- (f) 비용 Bill claim → done · 그 뒤 취소(sent) → bill_delete_manual(po_charge)
  v_j := pg_temp.job('bill', 'po_charge', pg_temp.id('ch1'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill'], array[%L::uuid])$q$, v_j.id));
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz43chg1', 'ZZ43-CH-1', '0', null, null, null, 600.26, 0)$q$, v_j.id));
  update public.po_charge set status = 'cancelled', cancelled_by = v_st, cancelled_at = now() where id = pg_temp.id('ch1')::uuid;
  v_d := pg_temp.job('bill_delete_manual', 'po_charge', pg_temp.id('ch1'));
  perform pg_temp.chk('S7e 비용 Bill done(600.26) → sent · qbo_txn po_charge ↔ Bill · 취소 → bill_delete_manual(po_charge) queued · note 「Bill ZZ43-CH-1 was cancelled」', (v_r->>'state') || ' ' || (select t.qbo_type || ' ' || coalesce(t.mismatch, '-') from public.qbo_txn t where t.ims_kind = 'po_charge' and t.ims_id = pg_temp.id('ch1')) || ' ' || coalesce(v_d.state, '(none)') || ' ' || (v_d.note ~ 'Bill ZZ43-CH-1 was cancelled')::text, 'sent Bill - queued true');
  -- (g) sending 중 취소 → bill_delete_manual blocked_by 그 일감
  v_j := pg_temp.job('bill', 'po_charge', pg_temp.id('ch2'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill'], array[%L::uuid])$q$, v_j.id));
  update public.po_charge set status = 'cancelled', cancelled_by = v_st, cancelled_at = now() where id = pg_temp.id('ch2')::uuid;
  v_d := pg_temp.job('bill_delete_manual', 'po_charge', pg_temp.id('ch2'));
  perform pg_temp.chk('S5j sending 중 취소: bill_delete_manual blocked · blocked_by = sending 일감 · note 「while it was being sent」', coalesce(v_d.state, '(none)') || ' ' || (v_d.blocked_by = v_j.id)::text || ' ' || (v_d.note ~ 'while it was being sent')::text, 'blocked true true');
  -- S9 EF kinds(SEND_KINDS 19 · 새 kind 없음) → 고른 bill 은 wrong_kind
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i4'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void', 'cost_day'], array[%L::uuid])$q$, v_j.id));
  perform pg_temp.chk('S9 EF SEND_KINDS 19 로 bill 을 고르면: claimed 0 · requested[0].result wrong_kind · reason 「kind bill is not sent by this worker」 · 일감은 queued 그대로(G 확인)', (v_r->>'claimed') || ' ' || (v_r->'requested'->0->>'result') || ' ' || (v_r->'requested'->0->>'reason') || ' ' || (select state from public.qbo_job where id = v_j.id), '0 wrong_kind kind bill is not sent by this worker queued');
  perform pg_temp.chk('S9b claim kinds 검사: bill_delete_manual 은 보내는 kind 가 아니다(거부) · vendor · bill · vendor_credit 은 받는다', (pg_temp.svc($q$select to_jsonb(pg_temp.try($t$select public.qbo_job_claim(1, array['bill_delete_manual'])::text$t$))$q$)::text ~ 'kinds must be among')::text || ' ' || (pg_temp.svc($q$select public.qbo_job_claim(1, array['vendor', 'bill', 'vendor_credit'], array['00000000-0000-0000-0000-000000000001'::uuid])$q$)->'requested'->0->>'result'), 'true not_found');
end $$;

-- ── S8 백필 멱등 · S10 list · preview · retry(열쇠 직원) ──
do $$
declare v_r jsonb; v_l jsonb; v_p jsonb; v_j public.qbo_job; v_e text;
begin
  v_r := public.qbo_po_backfill();
  perform pg_temp.chk('S8a 백필 두 번째: 더하는 일감 0(bills 0 · vendor_credits 0 · charge_bills 0) · 실제 확정 인보이스마다 bill 일감 하나(queued)', (v_r->>'bills') || ' ' || (v_r->>'vendor_credits') || ' ' || (v_r->>'charge_bills') || ' ' || (select count(*) from public.qbo_job j join public.po_invoice i on i.id::text = j.ims_id where j.kind = 'bill' and j.ims_kind = 'po_invoice' and i.invoice_number not like 'ZZ43-%' and j.state = 'queued')::text || '/' || (select count(*) from public.po_invoice where status = 'confirmed' and doc_kind = 'invoice' and invoice_number not like 'ZZ43-%')::text,
    '0 0 0 7/7');
  perform pg_temp.chk('S8b since 가드: created_at 토론토 날짜 기준 — 10-28 인보이스(AST261028 · 11-02 생성)도 들어왔다 · since 전 시각은 false · null 은 false', (select count(*) from public.qbo_job j join public.po_invoice i on i.id::text = j.ims_id where j.kind = 'bill' and i.invoice_date < date '2026-11-02')::text || ' ' || public.qbo_po_since_ok(timestamptz '2026-11-01 23:00-05')::text || ' ' || public.qbo_po_since_ok(null)::text, '1 false false');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_l := public.qbo_job_list('open', array['bill', 'vendor_credit', 'bill_delete_manual'], null, null, 'ZZ43-INV-4', 50, 0);
  perform pg_temp.chk('S10a qbo_job_list(open · kinds 셋 · q ZZ43-INV-4): total 1 · ims_name 「ZZ43-INV-4 · <공급처> · CAD 10.00」 · doc_status confirmed · currency CAD', (v_l->>'total') || ' ' || (v_l->'rows'->0->>'ims_name') || ' ' || (v_l->'rows'->0->>'doc_status') || ' ' || (v_l->'rows'->0->>'currency'), '1 ZZ43-INV-4 · ZZ-QBO43 Supplier B · CAD 10.00 confirmed CAD');
  v_l := public.qbo_job_list(null, array['bill_delete_manual'], null, null, null, 50, 0);
  perform pg_temp.chk('S10b list(kinds bill_delete_manual): 3(po_invoice skipped · po_charge queued · po_charge blocked) · 라벨은 문서 번호', (v_l->>'total') || ' ' || (select string_agg(x->>'state', ',' order by x->>'state') from jsonb_array_elements(v_l->'rows') x) || ' ' || (select count(*) from jsonb_array_elements(v_l->'rows') x where (x->>'ims_name') like 'ZZ43-%')::text, '3 blocked,queued,skipped 3');
  v_l := public.qbo_job_list('sent', array['bill'], null, null, 'ZZ43-INV-1', 50, 0);
  perform pg_temp.chk('S10c list(sent · bill · ZZ43-INV-1): txn 잇기 — txn_qbo_id zz43bill1 · txn_total_amt 36.40 · txn_mismatch 글', (v_l->'rows'->0->>'txn_qbo_id') || ' ' || (v_l->'rows'->0->>'txn_total_amt') || ' ' || ((v_l->'rows'->0->>'txn_mismatch') is not null)::text, 'zz43bill1 36.40 true');
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i4'));
  v_p := public.qbo_job_preview(v_j.id);
  perform pg_temp.chk('S10d preview(bill I4 · queued · 짝 있음): sendable true · needs 0 · body.APAccountRef 62 · doc.doc_number ZZ43-INV-4 · line_count 1 · fingerprint 「1000|CAD」', (v_p->>'sendable') || ' ' || jsonb_array_length(v_p->'needs')::text || ' ' || (v_p->'body'->'APAccountRef'->>'value') || ' ' || (v_p->'doc'->>'doc_number') || ' ' || (v_p->>'line_count') || ' ' || (v_p->>'fingerprint'), 'true 0 62 ZZ43-INV-4 1 1000|CAD');
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i7'));
  v_p := public.qbo_job_preview(v_j.id);
  perform pg_temp.chk('S10e preview(bill I7 · failed · 이름 충돌 공급처): error null(몸은 선다 · needs 1 vendor) · sendable false · needs[0].kind vendor', coalesce(v_p->>'error', '-') || ' ' || (v_p->>'sendable') || ' ' || jsonb_array_length(v_p->'needs')::text || ' ' || (v_p->'needs'->0->>'kind'), '- false 1 vendor');
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i6'));
  v_e := pg_temp.try(format($q$select public.qbo_job_retry(%L::uuid, 'zz')::text$q$, v_j.id));
  perform pg_temp.chk('S10f retry(skipped bill · 문서 draft): 거부 「while the supplier document is confirmed」', (v_e ~ 'while the supplier document is confirmed')::text, 'true');
  v_j := pg_temp.job('bill', 'po_invoice', pg_temp.id('i2'));
  v_r := public.qbo_job_retry(v_j.id, null);
  perform pg_temp.chk('S10g retry(failed bill I2): queued · request_id 새로', (v_r->>'state') || ' ' || ((select request_id from public.qbo_job where id = v_j.id) <> v_j.request_id)::text, 'queued true');
  perform pg_temp.chk('S10h qbo_job_doc 넷: po_invoice(번호 · 통화 · 줄 합 + 세금 · 상태) · po_credit · po_charge(금액 + 세금) · supplier(이름 · 통화 · active)',
    (public.qbo_job_doc('po_invoice', pg_temp.id('i1'))->>'doc_number') || ' ' || (public.qbo_job_doc('po_invoice', pg_temp.id('i1'))->>'currency') || ' ' || (public.qbo_job_doc('po_invoice', pg_temp.id('i1'))->>'total') || ' ' || (public.qbo_job_doc('po_invoice', pg_temp.id('i1'))->>'doc_status')
      || ' | ' || (public.qbo_job_doc('po_credit', pg_temp.id('c1'))->>'doc_number') || ' ' || (public.qbo_job_doc('po_credit', pg_temp.id('c1'))->>'total')
      || ' | ' || (public.qbo_job_doc('po_charge', pg_temp.id('ch2'))->>'doc_number') || ' ' || (public.qbo_job_doc('po_charge', pg_temp.id('ch2'))->>'total') || ' ' || (public.qbo_job_doc('po_charge', pg_temp.id('ch2'))->>'doc_status')
      || ' | ' || (public.qbo_job_doc('supplier', pg_temp.id('sb'))->>'name') || ' ' || (public.qbo_job_doc('supplier', pg_temp.id('sb'))->>'currency') || ' ' || (public.qbo_job_doc('supplier', pg_temp.id('sb'))->>'doc_status')
      || ' | ' || (public.qbo_job_doc('po_invoice', pg_temp.id('c1')) is null)::text,
    'ZZ43-INV-1 USD 36.41 confirmed | ZZ43-CR-1 5.00 | ZZ43-CH-2 429.20 cancelled | ZZ-QBO43 Supplier B CAD active | true');
  perform pg_temp.as_user(null);
  perform pg_temp.chk('S10i 열쇠 없는 호출: preview · list 거부(qbo 권한) · claim · done 은 service 전용', (pg_temp.try(format($q$select public.qbo_job_preview(%L::uuid)::text$q$, v_j.id)) ~ 'not registered as active staff')::text || ' ' || (pg_temp.try($q$select public.qbo_job_claim(15, array['bill'])::text$q$) ~ 'send worker only')::text || ' ' || (pg_temp.try(format($q$select public.qbo_job_done(%L::uuid, 'x', 'y')::text$q$, v_j.id)) ~ 'send worker only')::text, 'true true true');
end $$;

-- ── W1 REST 두 겹 ① · G 구조 ──
select pg_temp.chk('W1 WHERE 정적: 새 아홉 + 재발행 여덟 — 깊이 0 WHERE 없는 update · delete 0',
  (select string_agg(p.proname || ' ' || pg_temp.nowhere(p.prosrc)::text, ' · ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_po_since_ok', 'qbo_doc_number_21', 'qbo_purchase_tax', 'qbo_vendor_body', 'qbo_bill_body', 'qbo_vendor_credit_body', 'qbo_charge_bill_body', 'qbo_job_on_po_doc_status', 'qbo_po_backfill', 'qbo_job_open_or_add', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_list', 'qbo_job_retry', 'qbo_job_doc', 'qbo_entity_upsert')),
  (select string_agg(p.proname || ' 0', ' · ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_po_since_ok', 'qbo_doc_number_21', 'qbo_purchase_tax', 'qbo_vendor_body', 'qbo_bill_body', 'qbo_vendor_credit_body', 'qbo_charge_bill_body', 'qbo_job_on_po_doc_status', 'qbo_po_backfill', 'qbo_job_open_or_add', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_list', 'qbo_job_retry', 'qbo_job_doc', 'qbo_entity_upsert')));
select pg_temp.chk('G1 CHECK: qbo_job kind 23(vendor · bill · vendor_credit · bill_delete_manual) · ims_kind 14 · pair 에 vendor→supplier · vendor_credit→po_credit · bill · bill_delete_manual 가지 · qbo_txn Bill · VendorCredit',
  (select (pg_get_constraintdef(oid) ~ 'bill_delete_manual')::text from pg_constraint where conname = 'qbo_job_kind_ck') || ' ' || (select (pg_get_constraintdef(oid) ~ 'po_credit')::text from pg_constraint where conname = 'qbo_job_ims_kind_ck')
  || ' ' || (select (pg_get_constraintdef(oid) ~ $r$'vendor'::text THEN 'supplier'$r$ and pg_get_constraintdef(oid) ~ $r$'vendor_credit'::text THEN 'po_credit'$r$ and pg_get_constraintdef(oid) ~ $r$kind <> 'bill'::text$r$ and pg_get_constraintdef(oid) ~ $r$kind <> 'bill_delete_manual'::text$r$)::text from pg_constraint where conname = 'qbo_job_pair_ck')
  || ' ' || (select (pg_get_constraintdef(oid) ~ 'VendorCredit')::text from pg_constraint where conname = 'qbo_txn_type_ck') || ' ' || (select (pg_get_constraintdef(oid) ~ $r$'po_charge'::text THEN 'Bill'$r$ and pg_get_constraintdef(oid) ~ $r$'po_credit'::text THEN 'VendorCredit'$r$)::text from pg_constraint where conname = 'qbo_txn_pair_ck'),
  'true true true true true');
select pg_temp.chk('G2 짝 제약이 막는다: bill + po_credit 거부 · vendor + po_invoice 거부 · bill_delete_manual + supplier 거부 · qbo_txn po_invoice + VendorCredit 거부',
  (pg_temp.try(format($q$insert into public.qbo_job (realm_id, kind, ims_kind, ims_id) values (%L, 'bill', 'po_credit', 'zz') returning id::text$q$, :'realm')) ~ 'qbo_job_pair_ck')::text
  || ' ' || (pg_temp.try(format($q$insert into public.qbo_job (realm_id, kind, ims_kind, ims_id) values (%L, 'vendor', 'po_invoice', 'zz') returning id::text$q$, :'realm')) ~ 'qbo_job_pair_ck')::text
  || ' ' || (pg_temp.try(format($q$insert into public.qbo_job (realm_id, kind, ims_kind, ims_id) values (%L, 'bill_delete_manual', 'supplier', 'zz') returning id::text$q$, :'realm')) ~ 'qbo_job_pair_ck')::text
  || ' ' || (pg_temp.try(format($q$insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id) values (%L, 'po_invoice', 'zz', 'VendorCredit', 'zz') returning id::text$q$, :'realm')) ~ 'qbo_txn_pair_ck')::text, 'true true true true');
select pg_temp.chk('G3 트리거 둘(po_invoice_qbo_job · po_charge_qbo_job · AFTER UPDATE OF status) · 함수 아홉 grant 0 · 재발행 ACL 그대로(claim · done service · list · preview · retry authenticated · upsert authenticated(EF pull) · doc · open_or_add 0)',
  (select count(*) from pg_trigger where tgname in ('po_invoice_qbo_job', 'po_charge_qbo_job') and not tgisinternal)::text || ' ' ||
  (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '(default)'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_po_since_ok', 'qbo_doc_number_21', 'qbo_purchase_tax', 'qbo_vendor_body', 'qbo_bill_body', 'qbo_vendor_credit_body', 'qbo_charge_bill_body', 'qbo_job_on_po_doc_status', 'qbo_po_backfill', 'qbo_job_open_or_add', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_list', 'qbo_job_retry', 'qbo_job_doc', 'qbo_entity_upsert')),
  '2 qbo_bill_body:{postgres=X/postgres} qbo_charge_bill_body:{postgres=X/postgres} qbo_doc_number_21:{postgres=X/postgres} qbo_entity_upsert:{postgres=X/postgres,authenticated=X/postgres} qbo_job_claim:{postgres=X/postgres,service_role=X/postgres} qbo_job_doc:{postgres=X/postgres} qbo_job_done:{postgres=X/postgres,service_role=X/postgres} qbo_job_list:{postgres=X/postgres,authenticated=X/postgres} qbo_job_on_po_doc_status:{postgres=X/postgres} qbo_job_open_or_add:{postgres=X/postgres} qbo_job_preview:{postgres=X/postgres,authenticated=X/postgres} qbo_job_retry:{postgres=X/postgres,authenticated=X/postgres} qbo_po_backfill:{postgres=X/postgres} qbo_po_since_ok:{postgres=X/postgres} qbo_purchase_tax:{postgres=X/postgres} qbo_vendor_body:{postgres=X/postgres} qbo_vendor_credit_body:{postgres=X/postgres}');
select pg_temp.chk('G4 무변 다섯(fail · skip · unknown · unknown_list · qbo_cost_expected) md5 = begin 앞 · qbo_entity_upsert 몸에 PurchaseTaxRateList',
  ((select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_fail', 'qbo_job_skip', 'qbo_job_unknown', 'qbo_job_unknown_list', 'qbo_cost_expected')) = :'pre_md5_same')::text
  || ' ' || (select (prosrc ~ 'PurchaseTaxRateList')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_entity_upsert'), 'true true');
\if :{?mig}
select pg_temp.chk('S0b(시험 갈래) 재발행 여덟 md5 가 begin 앞과 다르다', ((select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_open_or_add', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_list', 'qbo_job_retry', 'qbo_job_doc', 'qbo_entity_upsert')) <> :'pre_md5_8')::text, 'true');
\else
select pg_temp.chk('S0b(확인 갈래) 재발행 여덟 md5 = begin 앞(이미 적용)', ((select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_open_or_add', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_list', 'qbo_job_retry', 'qbo_job_doc', 'qbo_entity_upsert')) = :'pre_md5_8')::text, 'true');
\endif
select pg_temp.chk('G5 거래 표 FK 0: qbo_job · qbo_txn 에서 po · po_invoice · po_charge · supplier 로 가는 FK 없음 · 이름마다 정의 하나', (select coalesce(string_agg(c.conrelid::regclass::text || '→' || c.confrelid::regclass::text, ','), '') from pg_constraint c where c.contype = 'f' and c.conrelid in ('public.qbo_job'::regclass, 'public.qbo_txn'::regclass) and c.confrelid in ('public.po'::regclass, 'public.po_invoice'::regclass, 'public.po_charge'::regclass, 'public.supplier'::regclass))
  || '|' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_open_or_add', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_list', 'qbo_job_retry', 'qbo_job_doc', 'qbo_entity_upsert', 'qbo_bill_body', 'qbo_charge_bill_body', 'qbo_vendor_body'))::text, '|11');
select pg_temp.chk('G6 실제 행 무변(트랜잭션 안): 실제 공급처 · 인보이스 · 비용 · 결제 수 = 기준 + 가짜(공급처 5 · 인보이스 8 · 비용 3 · 결제 0) · 실제 qbo_txn 은 가짜 넷만 늘었다',
  ((select count(*) from public.supplier) - :pre_sup)::text || ' ' || ((select count(*) from public.po_invoice) - :pre_inv)::text || ' ' || ((select count(*) from public.po_charge) - :pre_chg)::text || ' ' || ((select count(*) from public.po_payment) - :pre_pay)::text || ' ' || ((select count(*) from public.qbo_txn) - :pre_txn)::text, '5 8 3 0 4');

-- ── Z(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(상호 없음 · 가짜 행은 rollback) ──'
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, :EXPECT_OK as expect_ok from t_res;
select 'FAIL ' || label || format(' — got %s · want %s', coalesce(got, '(null)'), coalesce(want, '(null)')) as fail_line from t_res where not ok order by n;
select round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s;
rollback;
select (select count(*) from public.ims_staff) = :pre_staff and (select count(*) from public.supplier) = :pre_sup and (select count(*) from public.po) = :pre_po and (select count(*) from public.po_invoice) = :pre_inv and (select count(*) from public.po_charge) = :pre_chg
   and (select count(*) from public.ref_tax_rule) = :pre_tr and (select count(*) from public.qbo_entity) = :pre_ent and (select count(*) from public.qbo_link) = :pre_link and (select count(*) from public.qbo_job) = :pre_jobs and (select count(*) from public.qbo_txn) = :pre_txn
   and not (:{?mig} and exists (select 1 from pg_constraint where conname = 'qbo_job_kind_ck' and pg_get_constraintdef(oid) like '%vendor_credit%')) as rolled_back_clean;
