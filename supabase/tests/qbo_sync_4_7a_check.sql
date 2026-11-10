-- supabase/tests/qbo_sync_4_7a_check.sql — qbo-sync-4-7a 검증 (2026-11-09 토론토 밤 · 판정 1143 ~ 1149 · §0 이견 1 ~ 23 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] begin → (-v mig 면 \i) → 가짜 재료(DO 하나) → S1 CAD 할인 결제 · S2 USD · S3 세금 몫 · 세금 있는 인보이스 · S4 붙은 크레딧 · S5 날짜만 고침 · S6 할인 바꿈 · 되돌림 · 없앰 · 새 할인 · S7 VC skipped · S8 원가 장 · S9 지급 기한 · S10 회귀 · W REST WHERE · G 구조 · Z 실제 행 무변 → rollback
--   Claude Code(시험 · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261110034500_qbo_sync_4_7a_discount_credit_due_date.sql -f supabase/tests/qbo_sync_4_7a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(두 갈래 같다 · 갈래 전용 검사 없음)
--   마른 실행(적용 전 · -v mig 없음 = 옛 함수): S1 · S5 · S6 · S8 이 FAIL 로 잡혀야 한다(시험이 결함을 잡는지)
--   ⚠️ 가짜 재료만(공급처 ZZ-QBO47-* · 계좌 ZZ47-* · PO-79471 · 79472 · 인보이스 ZZ47-* · 거울 zz47*) — 실제 행은 읽기만 · claim 은 일감 id 로만 · 공개 레포 — 상호를 찍지 않는다
--   ⚠️ qbo_job · qbo_txn CHECK 교체 · po_invoice 칸 · 트리거 — 토론토 17:00 뒤 또는 08:30 전
\set ON_ERROR_STOP on
\pset pager off
\set EXPECT_OK 41
select (select value from public.inv_config where key = 'db_role') as db_role;

create temp table t_res (n serial, label text, got text, want text, ok boolean);
create temp table t_ids (k text primary key, v text);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns text language plpgsql as $$
begin
  insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want);
  return case when p_got is not distinct from p_want then 'OK   ' else 'FAIL ' end || p_label;
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
  select j.* from public.qbo_job j where j.kind = p_kind and j.ims_kind = p_ims_kind and j.ims_id = p_ims_id order by j.created_at desc, j.id desc limit 1
$$;
create function pg_temp.openjob(p_kind text, p_ims_kind text, p_ims_id text) returns public.qbo_job language sql as $$
  select j.* from public.qbo_job j where j.kind = p_kind and j.ims_kind = p_ims_kind and j.ims_id = p_ims_id and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1
$$;
create function pg_temp.claim1(p_job uuid, p_kind text) returns jsonb language sql as $$
  select pg_temp.svc(format('select public.qbo_job_claim(1, array[%L], array[%L]::uuid[])', p_kind, p_job))
$$;
create function pg_temp.mkpay(p_key text, p_cur text, p_amount numeric, p_acct text, p_ref text, p_targets jsonb, p_rate numeric default null, p_disc numeric default 0) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v := public.po_payment_create(null, public.ims_today(), p_amount, pg_temp.id(p_cur)::uuid, p_disc, pg_temp.id(p_acct)::uuid, p_ref, null, p_targets, true, p_rate);
  perform pg_temp.as_user(null);
  perform pg_temp.put(p_key, v->>'payment_id');
  perform pg_temp.put(p_key || '_a', (select a.id::text from public.po_payment_alloc a where a.po_payment_id = (v->>'payment_id')::uuid order by a.created_at, a.id limit 1));
  return v;
end $$;
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
select (select count(*) from public.po_invoice) as pre_inv, (select count(*) from public.po_payment) as pre_pay, (select count(*) from public.po_payment_alloc) as pre_alloc, (select count(*) from public.qbo_job) as pre_jobs, (select count(*) from public.qbo_txn) as pre_txn,
       (select count(*) from public.supplier) as pre_sup, (select count(*) from public.inv_cost_adjust) as pre_adj,
       (select md5(coalesce(string_agg(md5((to_jsonb(i) - 'due_date_manual')::text), ',' order by i.id), '')) from public.po_invoice i) as pre_inv_md5,
       (select md5(coalesce(string_agg(md5(to_jsonb(p)::text), ',' order by p.id), '')) from public.po_payment p) as pre_pay_md5,
       (select md5(coalesce(string_agg(md5(to_jsonb(a)::text), ',' order by a.id), '')) from public.po_payment_alloc a) as pre_alloc_md5,
       (select md5(coalesce(string_agg(md5(to_jsonb(j)::text), ',' order by j.id), '')) from public.qbo_job j) as pre_job_md5,
       (select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_payment_sync', 'qbo_payment_body', 'qbo_bill_body', 'qbo_vendor_credit_body', 'qbo_charge_bill_body', 'qbo_bill_payment_sync', 'qbo_bill_payment_fingerprint', 'qbo_bill_payment_void_body', 'qbo_job_on_po_doc_status', 'qbo_job_skip', 'po_payment_create', 'po_payment_alloc_set', 'po_payment_alloc_discount_set', 'po_payment_alloc_cost_events', 'po_invoice_create', 'po_invoice_discount_parts')) as pre_md5_same,
       clock_timestamp() as t_begin \gset
\echo '── 기준: invoices' :pre_inv '· payments' :pre_pay '· allocs' :pre_alloc '· jobs' :pre_jobs '· txn' :pre_txn

begin;
set local statement_timeout = '600s';
set local lock_timeout = '5s';
\if :{?mig}
\echo '── 시험 적용:' :mig
\i :mig
\endif
select clock_timestamp() as t_after_mig \gset

-- ── 가짜 재료(DO 하나) — 직원 · 공급처 둘(A USD · B CAD) · 계좌 둘(+ 거울 · 짝) · Vendor 거울 둘 · PO 둘 + 줄 · 인보이스 열하나 + 크레딧 셋 · Bill 일감 sent + qbo_txn Bill ──
do $$
declare v_usd uuid := (select id from public.ref_currency where code = 'USD'); v_cad uuid := (select id from public.ref_currency where code = 'CAD');
        v_ap_usd public.ref_account%rowtype; v_ap_cad public.ref_account%rowtype; v_term uuid := (select id from public.ref_payment_term where name = 'Net 30' and net_days = 30); v_t15 uuid := (select id from public.ref_payment_term where name = 'Net 15' and net_days = 15);
        v_zero uuid := (select id from public.ref_tax_rule where name = 'Zero-rated (Purchase)'); v_hst uuid := (select id from public.ref_tax_rule where name = 'HST ON (Purchase)');
        v_prod uuid := (select id from public.product where sku = 'AAL10850'); v_realm text := (select realm_id from public.qbo_connection where singleton);
        v_sa uuid := gen_random_uuid(); v_sb uuid := gen_random_uuid(); v_acb uuid := gen_random_uuid(); v_acc uuid := gen_random_uuid();
        v_po1 uuid := gen_random_uuid(); v_po2 uuid := gen_random_uuid(); v_l1 uuid := gen_random_uuid(); v_l2 uuid := gen_random_uuid();
        v_st uuid := gen_random_uuid(); v_staff uuid; v_r record; v_id uuid; v_cr uuid;
begin
  select * into v_ap_usd from public.ref_account where code = '_109_'; select * into v_ap_cad from public.ref_account where code = '_62_';
  if v_usd is null or v_cad is null or v_term is null or v_t15 is null or v_zero is null or v_hst is null or v_prod is null or v_realm is null or v_ap_usd.id is null or v_ap_cad.id is null then raise exception 'fixture: a reference row is missing (currency · term Net 30 · Net 15 · tax rule · product AAL10850 · realm · A/P _109_ · _62_)'; end if;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (v_st, 'zz-qbo-sync-4-7a@test.invalid', 'ZZ qbo-sync-4-7a bookkeeper', 'manager', '["ims", "qbo", "purchasing"]', '{}') returning id into v_staff;
  insert into public.supplier (id, name, source, is_active, payment_term_id, payment_term_name, account_payable_id, account_payable_code, currency_id) values
    (v_sa, 'ZZ-QBO47 Supplier A', 'manual', true, v_term, 'Net 30', v_ap_usd.id, v_ap_usd.code, v_usd), (v_sb, 'ZZ-QBO47 Supplier B', 'manual', true, v_term, 'Net 30', v_ap_cad.id, v_ap_cad.code, v_cad);
  insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, active) values (v_realm, 'Vendor', 'zz47va', 'ZZ-QBO47 Vendor A', true), (v_realm, 'Vendor', 'zz47vb', 'ZZ-QBO47 Vendor B', true);
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by) values (v_realm, 'supplier', v_sa::text, 'Vendor', 'zz47va', 'manual'), (v_realm, 'supplier', v_sb::text, 'Vendor', 'zz47vb', 'manual');
  insert into public.ref_account (id, code, name, account_class, account_type, source, currency_code) values (v_acb, 'ZZ47-BANK-CAD', 'ZZ47 Bank CAD', 'ASSET', 'BANK', 'manual', null), (v_acc, 'ZZ47-CC-USD', 'ZZ47 Card USD', 'LIABILITY', 'CREDITCARD', 'manual', 'USD');
  insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, active, detail) values
    (v_realm, 'Account', 'zz47acb', 'ZZ47 Bank CAD', true, '{"AccountType": "Bank", "CurrencyRef": {"value": "CAD"}}'::jsonb), (v_realm, 'Account', 'zz47acc', 'ZZ47 Card USD', true, '{"AccountType": "Credit Card", "CurrencyRef": {"value": "USD"}}'::jsonb);
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by) values (v_realm, 'account', v_acb::text, 'Account', 'zz47acb', 'manual'), (v_realm, 'account', v_acc::text, 'Account', 'zz47acc', 'manual');
  insert into public.po (id, po_number, status, supplier_id, currency_id) values (v_po1, 'PO-79471', 'confirmed', v_sa, v_usd), (v_po2, 'PO-79472', 'confirmed', v_sb, v_cad);
  insert into public.po_line (id, po_id, line_no, product_id, qty_ea, unit_price) values (v_l1, v_po1, 1, v_prod, 100, 2.5), (v_l2, v_po2, 1, v_prod, 200, 2.5);
  -- 인보이스(모두 confirmed · 20.00 = 8 × 2.5): 1 A USD(환율 1.4) · 3 B CAD(S1 · S5 · S6 · S7) · 4 B CAD HST with_tax 2 % · 5 B CAD HST pre_tax · 6 초안 크레딧 · 7 확정 크레딧 · 8 취소 크레딧 · 9 할인 없음 · 10 초안(S9 지급 기한)
  for v_r in select * from (values ('1', v_sa, v_usd, 1.4::numeric, v_l1, v_zero, null::text, 'confirmed'), ('3', v_sb, v_cad, null, v_l2, v_zero, null, 'confirmed'), ('4', v_sb, v_cad, null, v_l2, v_hst, 'with_tax', 'confirmed'), ('5', v_sb, v_cad, null, v_l2, v_hst, 'pre_tax', 'confirmed'),
                                   ('6', v_sb, v_cad, null, v_l2, v_zero, null, 'confirmed'), ('7', v_sb, v_cad, null, v_l2, v_zero, null, 'confirmed'), ('8', v_sb, v_cad, null, v_l2, v_zero, null, 'confirmed'), ('9', v_sb, v_cad, null, v_l2, v_zero, null, 'confirmed'))
                           as x(k, sup, cur, rate, line, rule, basis, st) loop
    v_id := gen_random_uuid();
    insert into public.po_invoice (id, supplier_id, invoice_number, invoice_date, due_date, payment_term_id, payment_term_name, currency_id, exchange_rate, total_amount, status, doc_kind, tax_rule_id, confirmed_by, confirmed_at, created_at, early_discount_pct, early_discount_basis, early_discount_until)
    values (v_id, v_r.sup, 'ZZ47-INV-' || v_r.k, public.ims_today(), public.ims_today() + 30, v_term, 'Net 30', v_r.cur, v_r.rate, case when v_r.rule = v_hst then 22.6 else 20 end, v_r.st, 'invoice', v_r.rule, v_staff, now(), now(),
            case when v_r.basis is not null then 2 end, v_r.basis, case when v_r.basis is not null then public.ims_today() + 10 end);
    insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price) values (v_id, 1, 'goods', v_r.line, 8, 2.5);
    insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, sent_at, qbo_id, qbo_name, fingerprint, by_staff) values (v_realm, 'bill', 'po_invoice', v_id::text, 'sent', now(), 'zz47b' || v_r.k, 'ZZ47-INV-' || v_r.k, '2000|X', v_staff);
    insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, fingerprint, source) values (v_realm, 'po_invoice', v_id::text, 'Bill', 'zz47b' || v_r.k, 'ZZ47-INV-' || v_r.k, '0', 20, 0, '2000|X', 'sent');
    perform pg_temp.put('i' || v_r.k, v_id::text);
    if v_r.k in ('6', '7', '8') then                                                                      -- 붙은 크레딧 2.00(초안 · 확정 · 취소)
      v_cr := gen_random_uuid();
      insert into public.po_invoice (id, supplier_id, invoice_number, invoice_date, currency_id, total_amount, status, doc_kind, tax_rule_id, credit_for_invoice_id, confirmed_by, confirmed_at, cancelled_by, cancelled_at, created_at)
      values (v_cr, v_r.sup, 'ZZ47-CR-' || v_r.k, public.ims_today(), v_r.cur, 2, case v_r.k when '6' then 'draft' when '7' then 'confirmed' else 'cancelled' end, 'credit', v_r.rule, v_id,
              case when v_r.k = '7' then v_staff end, case when v_r.k = '7' then now() end, case when v_r.k = '8' then v_staff end, case when v_r.k = '8' then now() end, now());
      insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, credit_reason) values (v_cr, 1, 'goods', v_r.line, 1, 2, 'price_difference');
      perform pg_temp.put('c' || v_r.k, v_cr::text);
    end if;
  end loop;
  perform pg_temp.put('staff', v_staff::text); perform pg_temp.put('st_uid', v_st::text); perform pg_temp.put('sa', v_sa::text); perform pg_temp.put('sb', v_sb::text); perform pg_temp.put('acb', v_acb::text); perform pg_temp.put('acc', v_acc::text);
  perform pg_temp.put('usd', v_usd::text); perform pg_temp.put('cad', v_cad::text); perform pg_temp.put('term', v_term::text); perform pg_temp.put('t15', v_t15::text); perform pg_temp.put('zero', v_zero::text); perform pg_temp.put('realm', v_realm);
end $$;
set constraints all immediate;

-- ── S1 CAD pre_tax 할인 결제(2223170 꼴) — VC 일감 · 결제는 VC 뒤 · VC sent → 결제 queued · 몸 = Bill 줄 + VC 줄 · TotalAmt = 낸 돈 ──
do $$
declare v_r jsonb; v_c jsonb; v_b jsonb; v_vj public.qbo_job; v_pj public.qbo_job; v_a text; v_d text := 'D' || to_char(public.ims_today(), 'YYMMDD') || '-ZZ47-INV-3';
begin
  v_r := pg_temp.mkpay('p1', 'cad', 19.6, 'acb', 'ZZ47-P1', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i3'), 'amount', 20, 'discount', 0.4)), null, 0.4);
  v_a := pg_temp.id('p1_a');
  v_vj := pg_temp.openjob('vendor_credit', 'po_discount', v_a); v_pj := pg_temp.openjob('bill_payment', 'po_payment', pg_temp.id('p1'));
  perform pg_temp.chk('S1a 할인 결제 저장(I3 20 · 할인 0.4 · 낸 돈 19.6): 할인 VC 일감 vendor_credit/po_discount queued · 결제 일감 queued', coalesce(v_vj.state, '(none)') || ' ' || coalesce(v_pj.state, '(none)'), 'queued queued');
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment'); v_pj := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p1'));
  perform pg_temp.chk('S1b 결제 claim: blocked · blocked_by = 할인 VC 일감 · 글에 discount credit', v_pj.state || ' ' || (v_pj.blocked_by is not distinct from v_vj.id)::text || ' ' || (coalesce(v_pj.warning, '') like '%early-payment discount credit of invoice ZZ47-INV-3%')::text, 'blocked true true');
  v_c := pg_temp.claim1(v_vj.id, 'vendor_credit'); v_b := v_c->'jobs'->0;
  perform pg_temp.chk('S1c 할인 VC claim: claimed 1 · ims_kind po_discount · DocNumber D<yymmdd>-ZZ47-INV-3 · 줄 하나 0.4 → GINR · CurrencyRef CAD · 환율 없음 · TotalTax 0 · 지문 40|CAD · 표지',
    (v_c->>'claimed') || ' ' || coalesce(v_b->>'ims_kind', '?') || ' ' || ((v_b->'body'->>'DocNumber') = v_d)::text || ' ' || jsonb_array_length(coalesce(v_b->'body'->'Line', '[]'))::text || ' ' || coalesce(v_b->'body'->'Line'->0->>'Amount', '?')
      || ' ' || ((v_b->'body'->'Line'->0->'AccountBasedExpenseLineDetail'->'AccountRef'->>'value') = public.qbo_account_ref('_1150040012_', 'x'))::text || ' ' || coalesce(v_b->'body'->'CurrencyRef'->>'value', '?') || ' ' || (v_b->'body' ? 'ExchangeRate')::text
      || ' ' || coalesce(v_b->'body'->'TxnTaxDetail'->>'TotalTax', '?') || ' ' || coalesce(v_b->>'fingerprint', '?') || ' ' || ((v_b->'body'->>'PrivateNote') like 'IMS early-payment discount ' || v_a || '%')::text,
    '1 po_discount true 1 0.4 true CAD false 0 40|CAD true');
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz47vc1', %L, '0', null, null, null, 0.40, 0, null)$q$, v_vj.id, v_d));
  v_pj := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p1'));
  perform pg_temp.chk('S1d VC done: sent · linked · qbo_txn po_discount ↔ VendorCredit zz47vc1 · 결제 일감 queued', coalesce(v_r->>'state', '?') || ' ' || coalesce(v_r->>'linked', '?') || ' ' || coalesce((select t.qbo_type || ' ' || t.qbo_id || ' ' || t.fingerprint from public.qbo_txn t where t.ims_kind = 'po_discount' and t.ims_id = v_a), '(no txn)') || ' ' || v_pj.state, 'sent true VendorCredit zz47vc1 40|CAD queued');
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment'); v_b := v_c->'jobs'->0;
  perform pg_temp.chk('S1e 결제 claim: claimed 1 · TotalAmt 19.6 · 줄 둘 = Bill zz47b3 20 + VendorCredit zz47vc1 0.4 · check_lines 둘(txn_type · VC 줄에는 qbo_bill_id 없음)',
    (v_c->>'claimed') || ' ' || coalesce(v_b->'body'->>'TotalAmt', '?') || ' ' || jsonb_array_length(coalesce(v_b->'body'->'Line', '[]'))::text
      || ' ' || coalesce(v_b->'body'->'Line'->0->'LinkedTxn'->0->>'TxnType', '?') || ' ' || coalesce(v_b->'body'->'Line'->0->'LinkedTxn'->0->>'TxnId', '?') || ' ' || coalesce(v_b->'body'->'Line'->0->>'Amount', '?')
      || ' ' || coalesce(v_b->'body'->'Line'->1->'LinkedTxn'->0->>'TxnType', '?') || ' ' || coalesce(v_b->'body'->'Line'->1->'LinkedTxn'->0->>'TxnId', '?') || ' ' || coalesce(v_b->'body'->'Line'->1->>'Amount', '?')
      || ' | ' || coalesce(v_b->'check_lines'->0->>'txn_type', '?') || ' ' || coalesce(v_b->'check_lines'->0->>'qbo_bill_id', '?') || ' ' || coalesce(v_b->'check_lines'->1->>'txn_type', '?') || ' ' || coalesce(v_b->'check_lines'->1->>'qbo_txn_id', '?') || ' ' || (v_b->'check_lines'->1 ? 'qbo_bill_id')::text,
    '1 19.6 2 Bill zz47b3 20 VendorCredit zz47vc1 0.4 | Bill zz47b3 VendorCredit zz47vc1 false');
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz47bp1', 'ZZ47-P1', '0', null, null, null, 19.60, null, null)$q$, v_pj.id));
  perform pg_temp.chk('S1f 결제 done: sent · linked · 맞추기 same · 열린 일감 0', coalesce(v_r->>'state', '?') || ' ' || coalesce(v_r->>'linked', '?') || ' ' || coalesce(v_r->'reconcile'->>'action', '?') || ' ' || (select count(*) from public.qbo_job j where j.ims_id in (v_a, pg_temp.id('p1')) and j.state not in ('sent', 'skipped'))::text, 'sent true same 0');
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S1 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;

-- ── S2 USD 할인 — VC 환율 = 인보이스 환율(1148) · 결제 환율은 따로 ──
do $$
declare v_r jsonb; v_b text; v_j jsonb;
begin
  v_r := pg_temp.mkpay('p2', 'usd', 19.6, 'acc', 'ZZ47-P2', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i1'), 'amount', 20, 'discount', 0.4)), 1.41, 0.4);
  v_b := pg_temp.try(format('select public.qbo_discount_credit_body(%L::uuid)::text', pg_temp.id('p2_a')));
  if v_b like 'ERR %' then perform pg_temp.chk('S2a USD 할인 VC 몸', v_b, 'a body');
  else v_j := v_b::jsonb;
    perform pg_temp.chk('S2a USD 할인 VC 몸: CurrencyRef USD · ExchangeRate 1.4(인보이스 환율 · 결제 환율 1.41 아님) · 0.4 · 지문 40|USD · VendorRef zz47va · A/P = _109_ 짝',
      coalesce(v_j->'body'->'CurrencyRef'->>'value', '?') || ' ' || coalesce(v_j->'body'->>'ExchangeRate', '?') || ' ' || coalesce(v_j->'body'->'Line'->0->>'Amount', '?') || ' ' || coalesce(v_j->>'fingerprint', '?') || ' ' || coalesce(v_j->'body'->'VendorRef'->>'value', '?')
        || ' ' || ((v_j->'body'->'APAccountRef'->>'value') = public.qbo_account_ref('_109_', 'x'))::text, 'USD 1.4 0.4 40|USD zz47va true');
  end if;
  v_b := pg_temp.try(format('select public.qbo_bill_payment_body(%L::uuid)::text', pg_temp.id('p2')));
  perform pg_temp.chk('S2b USD 결제 몸: VC 일감(queued) 뒤에서 기다린다 · 결제 환율 1.41', case when v_b like 'ERR %' then v_b else ((v_b::jsonb->>'wait_job') = (pg_temp.openjob('vendor_credit', 'po_discount', pg_temp.id('p2_a'))).id::text)::text || ' ' || coalesce(v_b::jsonb->'body'->>'ExchangeRate', '?') end, 'true 1.41');
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S2 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;

-- ── S3 세금 몫(with_tax · 1145) · 세금 있는 인보이스(pre_tax · 이견 2) → 결제 몸 · VC 몸 둘 다 막는다(사람 글) ──
do $$
declare v_r jsonb; v_b text; v_v text;
begin
  v_r := pg_temp.mkpay('p3', 'cad', 22.15, 'acb', 'ZZ47-P3', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i4'), 'amount', 22.6, 'discount', 0.45)), null, 0.45);
  v_b := pg_temp.try(format('select public.qbo_bill_payment_body(%L::uuid)::text', pg_temp.id('p3'))); v_v := pg_temp.try(format('select public.qbo_discount_credit_body(%L::uuid)::text', pg_temp.id('p3_a')));
  perform pg_temp.chk('S3a with_tax 할인(세금 몫 > 0): 저장된 discount_tax_part > 0 · 결제 몸 raise 「…1145…tax share…」 · VC 몸 raise 「…1145…」 · 손 안내 머리',
    ((select a.discount_tax_part from public.po_payment_alloc a where a.id::text = pg_temp.id('p3_a')) > 0)::text || ' ' || (v_b like 'ERR %1145%tax share%nothing was sent')::text || ' ' || (v_v like 'ERR %1145%tax share%nothing was sent')::text || ' ' || (v_b like '%Enter this payment in QuickBooks by hand, then press Skip on this job%')::text, 'true true true true');
  v_r := pg_temp.mkpay('p3b', 'cad', 22.2, 'acb', 'ZZ47-P3B', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i5'), 'amount', 22.6, 'discount', 0.4)), null, 0.4);
  v_b := pg_temp.try(format('select public.qbo_bill_payment_body(%L::uuid)::text', pg_temp.id('p3b'))); v_v := pg_temp.try(format('select public.qbo_discount_credit_body(%L::uuid)::text', pg_temp.id('p3b_a')));
  perform pg_temp.chk('S3b pre_tax 할인 · 세금 있는 인보이스: 세금 몫 0 · 결제 몸 raise 「…carries tax…」 · VC 몸 raise 「…carries tax…」',
    ((select a.discount_tax_part from public.po_payment_alloc a where a.id::text = pg_temp.id('p3b_a')) = 0)::text || ' ' || (v_b like 'ERR %carries tax%nothing was sent')::text || ' ' || (v_v like 'ERR %carries tax%nothing was sent')::text, 'true true true');
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S3 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;

-- ── S4 붙은 크레딧(1147 · 초안 · 확정 = 막음 · 취소 = 지나감) ──
do $$
declare v_r jsonb; v_6 text; v_7 text; v_8 text;
begin
  v_r := pg_temp.mkpay('p46', 'cad', 5, 'acb', 'ZZ47-P46', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i6'), 'amount', 5)));
  v_r := pg_temp.mkpay('p47', 'cad', 5, 'acb', 'ZZ47-P47', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i7'), 'amount', 5)));
  v_r := pg_temp.mkpay('p48', 'cad', 5, 'acb', 'ZZ47-P48', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i8'), 'amount', 5)));
  v_6 := pg_temp.try(format('select public.qbo_bill_payment_body(%L::uuid)::text', pg_temp.id('p46'))); v_7 := pg_temp.try(format('select public.qbo_bill_payment_body(%L::uuid)::text', pg_temp.id('p47'))); v_8 := pg_temp.try(format('select public.qbo_bill_payment_body(%L::uuid)::text', pg_temp.id('p48')));
  perform pg_temp.chk('S4a 초안 크레딧이 붙은 인보이스의 결제: 몸 raise 「…1132 ②…」(unpaid 와 같은 조건)', (v_6 like 'ERR %1132 ②%ZZ47-INV-6%nothing was sent')::text, 'true');
  perform pg_temp.chk('S4b 확정 크레딧: 몸 raise 「…1132 ②…cancel that credit…」', (v_7 like 'ERR %1132 ②%ZZ47-INV-7%cancel that credit%nothing was sent')::text, 'true');
  perform pg_temp.chk('S4c 취소된 크레딧: 막지 않는다(몸이 선다 · 줄 하나)', case when v_8 like 'ERR %' then v_8 else (v_8::jsonb->>'line_count') end, '1');
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S4 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;

-- ── S5 결제 날짜만 고침(할인 같음) → 결제 void + 다시 · 새 몸이 같은 VC Id(1146) · bill_delete_manual 0 ──
do $$
declare v_a text := pg_temp.id('p1_a'); v_p text := pg_temp.id('p1'); v_b text; v_vj public.qbo_job; v_pj public.qbo_job;
begin
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  update public.po_payment set paid_on = paid_on - 1 where id = v_p::uuid;
  perform pg_temp.as_user(null);
  v_vj := pg_temp.openjob('bill_payment_void', 'po_payment', v_p); v_pj := pg_temp.openjob('bill_payment', 'po_payment', v_p);
  perform pg_temp.chk('S5a 날짜만 고침: 결제 void queued · 다시 보내기 blocked(void 뒤) · 할인 VC 짝은 서 있다(voided_at null) · bill_delete_manual 0 · 새 VC 일감 0',
    coalesce(v_vj.state, '(none)') || ' ' || coalesce(v_pj.state, '(none)') || ' ' || (v_pj.blocked_by is not distinct from v_vj.id)::text || ' ' || (select (t.voided_at is null)::text from public.qbo_txn t where t.ims_kind = 'po_discount' and t.ims_id = v_a)
      || ' ' || (select count(*) from public.qbo_job j where j.kind = 'bill_delete_manual' and j.ims_id = v_a)::text || ' ' || (select count(*) from public.qbo_job j where j.kind = 'vendor_credit' and j.ims_id = v_a and j.state <> 'sent')::text, 'queued blocked true true 0 0');
  v_b := pg_temp.try(format('select public.qbo_bill_payment_body(%L::uuid)::text', v_p));
  perform pg_temp.chk('S5b 새 결제 몸: 같은 VC Id zz47vc1 를 다시 싣는다 · TxnDate = 어제 · wait 없음', case when v_b like 'ERR %' then v_b else coalesce(v_b::jsonb->'body'->'Line'->1->'LinkedTxn'->0->>'TxnId', '?') || ' ' || ((v_b::jsonb->'body'->>'TxnDate') = to_char(public.ims_today() - 1, 'YYYY-MM-DD'))::text || ' ' || coalesce(v_b::jsonb->>'wait_job', 'null') end, 'zz47vc1 true null');
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S5 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;

-- ── S6 할인 금액 바꿈 → 손 삭제 일감(결제 void 뒤) + 새 VC 일감(그 뒤) · 되돌림 → 거둠 · 없앰 → 손 삭제만 · void sent → 손 삭제 queued · Skip 뒤 새 할인 → 새 VC 일감 ──
do $$
declare v_a text := pg_temp.id('p1_a'); v_p text := pg_temp.id('p1'); v_r jsonb; v_t text; v_void public.qbo_job; v_dj public.qbo_job; v_cj public.qbo_job;
begin
  v_void := pg_temp.openjob('bill_payment_void', 'po_payment', v_p);
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_t := pg_temp.try(format('select public.po_payment_alloc_discount_set(%L::uuid, 0.2, true, null)::text', v_a));
  perform pg_temp.as_user(null);
  v_dj := pg_temp.openjob('bill_delete_manual', 'po_discount', v_a); v_cj := pg_temp.openjob('vendor_credit', 'po_discount', v_a);
  perform pg_temp.chk('S6a 할인 0.4 → 0.2: VC 짝 voided_at 섬 · bill_delete_manual(po_discount) blocked · blocked_by = 결제 void · 글에 #zz47vc1 · 새 VC 일감 blocked(손 삭제 뒤)',
    case when v_t like 'ERR %' then v_t else (select (t.voided_at is not null)::text from public.qbo_txn t where t.ims_kind = 'po_discount' and t.ims_id = v_a) || ' ' || coalesce(v_dj.state, '(none)') || ' ' || (v_dj.blocked_by is not distinct from v_void.id)::text
      || ' ' || (coalesce(v_dj.note, '') like '%vendor credit #zz47vc1%by hand%Skip%')::text || ' ' || coalesce(v_cj.state, '(none)') || ' ' || (v_cj.blocked_by is not distinct from v_dj.id)::text end, 'true blocked true true blocked true');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_t := pg_temp.try(format('select public.po_payment_alloc_discount_set(%L::uuid, 0.4, true, null)::text', v_a));
  perform pg_temp.as_user(null);
  perform pg_temp.chk('S6b 되돌림 0.2 → 0.4(아무것도 나가기 전): 손 삭제 일감 skipped · 새 VC 일감 skipped · VC 짝 다시 인정(voided_at null) · 열린 po_discount 일감 0',
    case when v_t like 'ERR %' then v_t else (select j.state from public.qbo_job j where j.id = v_dj.id) || ' ' || (select j.state from public.qbo_job j where j.id = v_cj.id) || ' ' || (select (t.voided_at is null)::text from public.qbo_txn t where t.ims_kind = 'po_discount' and t.ims_id = v_a)
      || ' ' || (select count(*) from public.qbo_job j where j.ims_kind = 'po_discount' and j.ims_id = v_a and j.state not in ('sent', 'skipped'))::text end, 'skipped skipped true 0');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_t := pg_temp.try(format('select public.po_payment_alloc_discount_set(%L::uuid, 0, true, null)::text', v_a));
  perform pg_temp.as_user(null);
  v_dj := pg_temp.openjob('bill_delete_manual', 'po_discount', v_a); v_void := pg_temp.openjob('bill_payment_void', 'po_payment', v_p);
  perform pg_temp.chk('S6c 할인 없앰: VC 짝 voided_at · 손 삭제 일감 blocked(결제 void 뒤) · 글 removed · 열린 VC 일감 0',
    case when v_t like 'ERR %' then v_t else (select (t.voided_at is not null)::text from public.qbo_txn t where t.ims_kind = 'po_discount' and t.ims_id = v_a) || ' ' || coalesce(v_dj.state, '(none)') || ' ' || (v_dj.blocked_by is not distinct from v_void.id)::text || ' ' || (coalesce(v_dj.note, '') like '%was removed in IMS%')::text
      || ' ' || (select count(*) from public.qbo_job j where j.kind = 'vendor_credit' and j.ims_id = v_a and j.state not in ('sent', 'skipped'))::text end, 'true blocked true true 0');
  v_r := pg_temp.claim1(v_void.id, 'bill_payment_void');
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz47bp1', 'ZZ47-P1', '1', null, null, null)$q$, v_void.id));
  perform pg_temp.chk('S6d 결제 void sent → 손 삭제 일감 queued(사람 차례)', coalesce(v_r->>'state', '?') || ' ' || (select j.state from public.qbo_job j where j.id = v_dj.id), 'sent queued');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_t := pg_temp.try(format('select public.po_payment_alloc_discount_set(%L::uuid, 0.3, true, null)::text', v_a));
  v_cj := pg_temp.openjob('vendor_credit', 'po_discount', v_a);
  perform pg_temp.put('s6_cj_state', coalesce(v_cj.state, '(none)') || ' ' || (v_cj.blocked_by is not distinct from v_dj.id)::text);
  v_r := public.qbo_job_skip(v_dj.id, 'ZZ47 deleted vendor credit zz47vc1 in QuickBooks');
  perform pg_temp.as_user(null);
  v_r := pg_temp.claim1(v_cj.id, 'vendor_credit');
  perform pg_temp.chk('S6e 새 할인 0.3(손 삭제가 열린 동안): 새 VC 일감 blocked(손 삭제 뒤) → Skip 뒤 claim: claimed 1 · 몸 0.3 · 지문 30|CAD',
    case when v_t like 'ERR %' then v_t else pg_temp.id('s6_cj_state') || ' ' || (v_r->>'claimed') || ' ' || coalesce(v_r->'jobs'->0->'body'->'Line'->0->>'Amount', '?') || ' ' || coalesce(v_r->'jobs'->0->>'fingerprint', '?') end, 'blocked true 1 0.3 30|CAD');
  perform pg_temp.put('s6_cj', v_cj.id::text);
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S6 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;

-- ── S7 VC 일감 skipped → 결제 몸 raise(영구 blocked 방지) · Retry 가 VC 일감을 다시 세운다 ──
do $$
declare v_a text := pg_temp.id('p1_a'); v_p text := pg_temp.id('p1'); v_r jsonb; v_b text; v_pj public.qbo_job; v_c jsonb;
begin
  update public.qbo_job j set state = 'failed', claimed_at = null, last_error = 'ZZ47 simulated failure' where j.id = pg_temp.id('s6_cj')::uuid and j.state = 'sending';
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_r := public.qbo_job_skip(pg_temp.id('s6_cj')::uuid, 'ZZ47 skip the discount credit');
  perform pg_temp.as_user(null);
  v_b := pg_temp.try(format('select public.qbo_bill_payment_body(%L::uuid)::text', v_p));
  perform pg_temp.chk('S7a 할인 VC 일감 skipped: 결제 몸 raise 「…was skipped — retry that job first, or enter this payment … by hand…」', (v_b like 'ERR %early-payment discount of invoice ZZ47-INV-3 was skipped%retry that job first%by hand%nothing was sent')::text, 'true');
  v_pj := pg_temp.openjob('bill_payment', 'po_payment', v_p);
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment');
  perform pg_temp.chk('S7b 그 결제 일감 claim: failed(blocked 로 남지 않는다) · 글 was skipped', (select j.state || ' ' || (coalesce(j.last_error, '') like '%was skipped%')::text from public.qbo_job j where j.id = v_pj.id), 'failed true');
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S7 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;

-- ── S8 원가 장: settlement_discount CADJ 가 send(1149) — 본문 정적 검사(실제 원가 표를 건드리지 않는다) + 지금 settlement_discount 사건은 가짜뿐 ──
select pg_temp.chk('S8a qbo_cost_expected: settlement_discount 보류 글 없음 · CADJ 가지에 hold 없음(price_adjust · settlement_discount 모두 send)',
  (select (prosrc not like '%opens with the supplier payment round%')::text || ' ' || (prosrc not like $r$%when x.akd = 'price_adjust' then 'send' else 'hold'%$r$)::text || ' ' || (prosrc like $r$%when x.lcode is null then 'block' else 'send' end,   -- 4-7a%$r$)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_cost_expected'), 'true true true');
select pg_temp.chk('S8b 실제 settlement_discount 원가 사건 0(이 시험의 가짜 PO 것만 있다 · 레이어에 얹힌 것 0)',
  (select count(*) from public.inv_cost_adjust a where a.kind = 'settlement_discount' and a.created_at < :'t_begin'::timestamptz)::text || ' ' || (select count(*) from public.inv_layer_cost_add x where x.kind = 'settlement_discount')::text, '0 0');

-- ── S9 (B) 지급 기한 자동(1144) — 초안: 비면 채움 · 날짜 · 결제조건 바꾸면 다시 셈 · 사람 값 지킴 · 비우면 다시 셈 · 확정 · 크레딧은 무접촉 ──
do $$
declare v_id uuid := gen_random_uuid(); v_cr uuid := gen_random_uuid(); v_d date := public.ims_today(); v_s text := ''; v_r record;
begin
  insert into public.po_invoice (id, supplier_id, invoice_number, invoice_date, payment_term_id, payment_term_name, currency_id, total_amount, status, doc_kind, tax_rule_id)
  values (v_id, pg_temp.id('sb')::uuid, 'ZZ47-INV-10', v_d, pg_temp.id('term')::uuid, 'Net 30', pg_temp.id('cad')::uuid, 20, 'draft', 'invoice', pg_temp.id('zero')::uuid);
  select (i.due_date = v_d + 30)::text || ' ' || i.due_date_manual::text into v_s from public.po_invoice i where i.id = v_id;
  perform pg_temp.chk('S9a 초안 저장(기한 빔 · Net 30): 기한 = 날짜 + 30 · manual false', v_s, 'true false');
  update public.po_invoice set invoice_date = v_d + 1 where id = v_id;
  select (i.due_date = v_d + 31)::text || ' ' || i.due_date_manual::text into v_s from public.po_invoice i where i.id = v_id;
  perform pg_temp.chk('S9b 문서 날짜 +1: 기한도 다시 셈(+31)', v_s, 'true false');
  update public.po_invoice set payment_term_id = pg_temp.id('t15')::uuid, payment_term_name = 'Net 15' where id = v_id;
  select (i.due_date = v_d + 16)::text || ' ' || i.due_date_manual::text into v_s from public.po_invoice i where i.id = v_id;
  perform pg_temp.chk('S9c 결제조건 Net 15: 기한 = 날짜 + 15', v_s, 'true false');
  update public.po_invoice set due_date = v_d + 40 where id = v_id;
  update public.po_invoice set invoice_date = v_d where id = v_id;
  select (i.due_date = v_d + 40)::text || ' ' || i.due_date_manual::text into v_s from public.po_invoice i where i.id = v_id;
  perform pg_temp.chk('S9d 사람이 기한을 다르게 넣음 → manual true · 날짜를 바꿔도 그대로', v_s, 'true true');
  update public.po_invoice set due_date = null where id = v_id;
  select (i.due_date = v_d + 15)::text || ' ' || i.due_date_manual::text into v_s from public.po_invoice i where i.id = v_id;
  perform pg_temp.chk('S9e 기한을 비움 → 다시 셈(날짜 + 15) · manual false', v_s, 'true false');
  update public.po_invoice set payment_term_id = null, payment_term_name = null, due_date = null where id = v_id;
  select coalesce(i.due_date::text, 'null') || ' ' || i.due_date_manual::text into v_s from public.po_invoice i where i.id = v_id;
  perform pg_temp.chk('S9f 결제조건 없음 + 기한 비움: 빈 채로 둔다', v_s, 'null false');
  insert into public.po_invoice (id, supplier_id, invoice_number, invoice_date, payment_term_id, payment_term_name, currency_id, total_amount, status, doc_kind, tax_rule_id)
  values (v_cr, pg_temp.id('sb')::uuid, 'ZZ47-CR-10', v_d, pg_temp.id('term')::uuid, 'Net 30', pg_temp.id('cad')::uuid, 2, 'draft', 'credit', pg_temp.id('zero')::uuid);
  update public.po_invoice set note = 'ZZ47 touch' where id = pg_temp.id('i9')::uuid;
  select coalesce((select i.due_date::text from public.po_invoice i where i.id = v_cr), 'null') || ' ' || (select (i.due_date = v_d + 30)::text || ' ' || i.due_date_manual::text from public.po_invoice i where i.id = pg_temp.id('i9')::uuid) into v_s;
  perform pg_temp.chk('S9g 크레딧은 기한을 안 채운다 · 확정 인보이스를 건드려도 기한 · 표지 무변', v_s, 'null true false');
exception when others then perform pg_temp.chk('S9 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;
select pg_temp.chk('S9h po_invoice_confirm 본문: 경고 due_date_missing · due_date_differs_from_term(막지 않음 — raise 아님)',
  (select (prosrc like $r$%array_append(v_warn, 'due_date_missing')%$r$)::text || ' ' || (prosrc like $r$%array_append(v_warn, 'due_date_differs_from_term')%$r$)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'po_invoice_confirm'), 'true true');
select pg_temp.chk('S9i 기존 인보이스: manual 표지 = 「기한 ≠ 날짜 + net_days」 인 장만(어긋난 장 0) · 기한 값은 Z1 이 본다',
  pg_temp.try($q$select (count(*) filter (where i.due_date_manual is distinct from (i.due_date is not null and (t.net_days is null or i.due_date <> i.invoice_date + t.net_days))))::text from public.po_invoice i left join public.ref_payment_term t on t.id = i.payment_term_id
    where i.doc_kind = 'invoice' and i.invoice_number not like 'ZZ47-%'$q$), '0');

-- ── S10 회귀: 할인 없는 결제 몸(4-5a 꼴) · 가격 크레딧(po_credit) VC 는 옛 몸으로 · 손 안 댄 함수 md5 ──
do $$
declare v_r jsonb; v_b text; v_j jsonb; v_c jsonb; v_job uuid;
begin
  v_r := pg_temp.mkpay('p9', 'cad', 10, 'acb', 'ZZ47-P9', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i9'), 'amount', 10)));
  v_b := pg_temp.try(format('select public.qbo_bill_payment_body(%L::uuid)::text', pg_temp.id('p9')));
  if v_b like 'ERR %' then perform pg_temp.chk('S10a 할인 없는 결제 몸', v_b, 'a body');
  else v_j := v_b::jsonb;
    perform pg_temp.chk('S10a 할인 없는 결제 몸(4-5a 꼴): TotalAmt 10 · 줄 하나 Bill zz47b9 10 · check_lines 하나(qbo_bill_id 그대로) · wait 없음 · PayType Check · po_discount 일감 0',
      coalesce(v_j->'body'->>'TotalAmt', '?') || ' ' || jsonb_array_length(v_j->'body'->'Line')::text || ' ' || (v_j->'body'->'Line'->0->'LinkedTxn'->0->>'TxnType') || ' ' || (v_j->'body'->'Line'->0->'LinkedTxn'->0->>'TxnId') || ' ' || (v_j->'body'->'Line'->0->>'Amount')
        || ' ' || jsonb_array_length(v_j->'check_lines')::text || ' ' || (v_j->'check_lines'->0->>'qbo_bill_id') || ' ' || coalesce(v_j->>'wait_job', 'null') || ' ' || (v_j->'body'->>'PayType') || ' ' || (select count(*) from public.qbo_job j where j.ims_kind = 'po_discount' and j.ims_id = pg_temp.id('p9_a'))::text,
      '10 1 Bill zz47b9 10 1 zz47b9 null Check 0');
  end if;
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (pg_temp.id('realm'), 'vendor_credit', 'po_credit', pg_temp.id('c7'), 'queued', pg_temp.id('staff')::uuid) returning id into v_job;
  v_c := pg_temp.claim1(v_job, 'vendor_credit');
  perform pg_temp.chk('S10b 가격 크레딧(po_credit) VC claim: claimed 1 · ims_kind po_credit · DocNumber ZZ47-CR-7 · 지문 200|CAD(옛 몸 qbo_vendor_credit_body)', (v_c->>'claimed') || ' ' || coalesce(v_c->'jobs'->0->>'ims_kind', '?') || ' ' || coalesce(v_c->'jobs'->0->>'doc_number', '?') || ' ' || coalesce(v_c->'jobs'->0->>'fingerprint', '?'), '1 po_credit ZZ47-CR-7 200|CAD');
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S10 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;
select pg_temp.chk('S10c 손 안 댄 함수 열여섯 md5 = begin 앞(손님 결제 · Bill 몸 · 결제 sync · 지문 · po_doc_status · skip · 결제 · 할인 창구)',
  ((select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_payment_sync', 'qbo_payment_body', 'qbo_bill_body', 'qbo_vendor_credit_body', 'qbo_charge_bill_body', 'qbo_bill_payment_sync', 'qbo_bill_payment_fingerprint', 'qbo_bill_payment_void_body', 'qbo_job_on_po_doc_status', 'qbo_job_skip', 'po_payment_create', 'po_payment_alloc_set', 'po_payment_alloc_discount_set', 'po_payment_alloc_cost_events', 'po_invoice_create', 'po_invoice_discount_parts')) = :'pre_md5_same')::text, 'true');

-- ── W REST 두 겹 ① — 새 · 재발행 함수의 update · delete 깊이 0 WHERE ──
select pg_temp.chk('W1 새 · 재발행 함수 열셋: WHERE 없는 update · delete 0',
  (select coalesce(string_agg(p.proname || ':' || pg_temp.nowhere(p.prosrc)::text, ' ' order by p.proname) filter (where pg_temp.nowhere(p.prosrc) > 0), 'none') || ' ' || count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('qbo_discount_credit_body', 'qbo_discount_credit_sync', 'po_invoice_due_auto', 'qbo_job_claim', 'qbo_job_preview', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_doc', 'qbo_job_list', 'qbo_job_on_po_payment', 'qbo_bill_payment_body', 'qbo_cost_expected', 'po_invoice_confirm')), 'none 13');

-- ── G 구조 ──
select pg_temp.chk('G1 CHECK: qbo_job ims_kind · 짝(vendor_credit ↔ po_credit | po_discount · bill_delete_manual + po_discount) · qbo_txn kind · 짝(po_discount ↔ VendorCredit)',
  (select count(*) from pg_constraint where (conname = 'qbo_job_ims_kind_ck' and pg_get_constraintdef(oid) like '%po_discount%') or (conname = 'qbo_job_pair_ck' and pg_get_constraintdef(oid) like $r$%'po_credit'::text, 'po_discount'::text%$r$ and pg_get_constraintdef(oid) like $r$%'po_charge'::text, 'po_discount'::text%$r$)
     or (conname = 'qbo_txn_kind_ck' and pg_get_constraintdef(oid) like '%po_discount%') or (conname = 'qbo_txn_pair_ck' and pg_get_constraintdef(oid) like $r$%'po_discount'::text THEN 'VendorCredit'%$r$))::text, '4');
select pg_temp.chk('G2 짝 CHECK 가 막는다: vendor_credit + po_invoice · bill + po_discount 는 거부(23514)',
  left(pg_temp.try(format($q$insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state) values (%L, 'vendor_credit', 'po_invoice', 'zz47-x', 'queued') returning id::text$q$, pg_temp.id('realm'))), 9) || ' ' || left(pg_temp.try(format($q$insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state) values (%L, 'bill', 'po_discount', 'zz47-y', 'queued') returning id::text$q$, pg_temp.id('realm'))), 9), 'ERR 23514 ERR 23514');
select pg_temp.chk('G3 새 함수 셋 · 같은 이름 하나씩 · authenticated · anon · service_role 실행권 0 · 트리거 po_invoice_due_auto · 칸 due_date_manual',
  (select count(*)::text || ' ' || count(*) filter (where has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_discount_credit_body', 'qbo_discount_credit_sync', 'po_invoice_due_auto'))
    || ' ' || (select count(*) from pg_trigger t where t.tgname = 'po_invoice_due_auto' and t.tgrelid = 'public.po_invoice'::regclass and not t.tgisinternal)::text || ' ' || (select count(*) from pg_attribute where attrelid = 'public.po_invoice'::regclass and attname = 'due_date_manual' and attnotnull)::text, '3 0 1 1');

-- ── Z 실제 행 무변(트랜잭션 안 · begin 앞에 있던 행만) ──
select pg_temp.chk('Z1 실제 행 무변: 인보이스(due_date_manual 빼고) · 결제 · 붙임 · 일감 — begin 앞 지문 그대로 · 실제 qbo_txn 수 그대로',
  ((select md5(coalesce(string_agg(md5((to_jsonb(i) - 'due_date_manual')::text), ',' order by i.id), '')) from public.po_invoice i where i.invoice_number not like 'ZZ47-%') = :'pre_inv_md5')::text
    || ' ' || ((select md5(coalesce(string_agg(md5(to_jsonb(p)::text), ',' order by p.id), '')) from public.po_payment p where coalesce(p.reference, '') not like 'ZZ47-%') = :'pre_pay_md5')::text
    || ' ' || ((select md5(coalesce(string_agg(md5(to_jsonb(a)::text), ',' order by a.id), '')) from public.po_payment_alloc a join public.po_payment p on p.id = a.po_payment_id where coalesce(p.reference, '') not like 'ZZ47-%') = :'pre_alloc_md5')::text
    || ' ' || ((select md5(coalesce(string_agg(md5(to_jsonb(j)::text), ',' order by j.id), '')) from public.qbo_job j where j.created_at < :'t_begin'::timestamptz) = :'pre_job_md5')::text
    || ' ' || ((select count(*) from public.qbo_txn t where t.qbo_id not like 'zz47%') = :pre_txn)::text, 'true true true true true');

-- ── 결과(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(상호 없음 · 가짜 행은 rollback) ──'
select case when ok then 'OK   ' else 'FAIL ' end || label || case when ok then '' else format(' — got %s · want %s', coalesce(got, '(null)'), coalesce(want, '(null)')) end as line from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, :EXPECT_OK as expect_ok from t_res;
select round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s;
rollback;
select (select count(*) from public.po_invoice) = :pre_inv and (select count(*) from public.po_payment) = :pre_pay and (select count(*) from public.po_payment_alloc) = :pre_alloc and (select count(*) from public.qbo_job) = :pre_jobs and (select count(*) from public.qbo_txn) = :pre_txn
   and (select count(*) from public.supplier) = :pre_sup and (select count(*) from public.inv_cost_adjust) = :pre_adj as rolled_back_clean;
