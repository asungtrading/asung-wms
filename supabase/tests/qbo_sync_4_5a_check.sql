-- supabase/tests/qbo_sync_4_5a_check.sql — qbo-sync-4-5a 검증 (2026-11-09 · 판정 1122 ~ 1125 · 1130 · 1132 ~ 1134 · §0 이견 1 ~ 20 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] begin → (-v mig 면 \i) → 가짜 재료(DO 하나) → S1 CAD Check · S2 USD CreditCard 둘 · S3 환율 빔 → 출구 · S4 1132 ①②③ · S5 1124 · S6 wait_job · S10 1133 셋 · S7 void · 지우기 둘 · S8 취소 순서 · S9 한 트랜잭션 셋 · S11 손님 결제 무변 · S12 백필 · W1 REST WHERE · G 구조 → rollback
--   Claude Code(시험 · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261109230000_qbo_sync_4_5a_supplier_payment_jobs.sql -f supabase/tests/qbo_sync_4_5a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(갈래마다)
--   ⚠️ 가짜 재료만(공급처 ZZ-QBO45-* · 계좌 ZZ45-* · PO-79451 · 79452 · 인보이스 ZZ45-* · 비용 ZZ45-CH-* · 거울 zz45*) — 실제 공급처 · 인보이스 · 결제 · 거울은 읽기만(S12 는 실제 결제 4 건의 몸을 try 로 읽는다 · 쓰기 0) · 백필이 실제 결제 4 건에 일감을 세우는 것은 마이그레이션의 몫(rollback)
--   ⚠️ po_payment · po_payment_alloc 트리거 생성 · qbo_job · qbo_txn CHECK 교체 — 토론토 17:00 뒤 또는 08:30 전 · 공개 레포 — 상호를 찍지 않는다
\set ON_ERROR_STOP on
\pset pager off
\if :{?mig}
\set EXPECT_OK 51
\else
\set EXPECT_OK 50
\endif
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
  select j.* from public.qbo_job j where j.kind = p_kind and j.ims_kind = p_ims_kind and j.ims_id = p_ims_id order by j.created_at desc, j.id desc limit 1
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
select (select count(*) from public.ims_staff) as pre_staff, (select count(*) from public.supplier) as pre_sup, (select count(*) from public.ref_account) as pre_acct, (select count(*) from public.po) as pre_po, (select count(*) from public.po_invoice) as pre_inv, (select count(*) from public.po_charge) as pre_chg,
       (select count(*) from public.po_payment) as pre_pay, (select count(*) from public.po_payment_alloc) as pre_alloc, (select count(*) from public.qbo_entity) as pre_ent, (select count(*) from public.qbo_link) as pre_link,
       (select count(*) from public.qbo_job) as pre_jobs, (select count(*) from public.qbo_txn) as pre_txn, (select count(*) from public.qbo_job where kind in ('payment', 'payment_void')) as pre_cust_pay_jobs,
       (select count(*) from public.po_payment p where exists (select 1 from public.po_payment_alloc a where a.po_payment_id = p.id) and public.qbo_po_since_ok(p.created_at)) as pre_real_pay_scope,
       (select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_retry', 'qbo_job_doc', 'qbo_job_list', 'qbo_job_on_po_doc_status', 'po_payment_alloc_guard', 'po_payment_create', 'po_payment_alloc_set', 'qbo_entity_upsert')) as pre_md5_11,
       (select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_payment_sync', 'qbo_payment_body', 'qbo_payment_void_body', 'qbo_payment_fingerprint', 'qbo_job_on_payment_alloc', 'qbo_job_on_payment_status', 'po_doc_delete', 'po_doc_cancel', 'po_payment_alloc_delete', 'po_payment_guard', 'qbo_job_skip', 'qbo_job_fail', 'qbo_job_unknown', 'qbo_job_unknown_list', 'qbo_bill_body')) as pre_md5_same,
       clock_timestamp() as t_begin \gset
\echo '── 기준: staff' :pre_staff '· suppliers' :pre_sup '· payments' :pre_pay '(scope' :pre_real_pay_scope ') · jobs' :pre_jobs '· txn' :pre_txn '· customer payment jobs' :pre_cust_pay_jobs '· realm' :realm

begin;
set local statement_timeout = '600s';
set local lock_timeout = '5s';
\if :{?mig}
\echo '── 시험 적용:' :mig
\i :mig
\endif
select clock_timestamp() as t_after_mig \gset

-- ── 가짜 재료(DO 하나) — 직원 · 공급처 셋 · 계좌 다섯(+ 거울 · 짝) · Vendor 거울 둘 · PO 둘 + 줄 · 인보이스 아홉 + 크레딧 · 비용 하나 · Bill 일감(sent 여덟 · queued 하나) · qbo_txn Bill 여덟 ──
do $$
declare v_usd uuid := (select id from public.ref_currency where code = 'USD'); v_cad uuid := (select id from public.ref_currency where code = 'CAD');
        v_ap_usd public.ref_account%rowtype; v_ap_cad public.ref_account%rowtype; v_term uuid := (select id from public.ref_payment_term where name = 'Due on receipt');
        v_zero uuid := (select id from public.ref_tax_rule where name = 'Zero-rated (Purchase)'); v_oos uuid := (select id from public.ref_tax_rule where name = 'Out of Scope (Purchase)');
        v_prod uuid := (select id from public.product where sku = 'AAL10850'); v_realm text := (select realm_id from public.qbo_connection where singleton);
        v_sa uuid := gen_random_uuid(); v_sb uuid := gen_random_uuid(); v_sc uuid := gen_random_uuid();
        v_acb uuid := gen_random_uuid(); v_acc uuid := gen_random_uuid(); v_acu uuid := gen_random_uuid(); v_acx uuid := gen_random_uuid(); v_ace uuid := gen_random_uuid();
        v_po1 uuid := gen_random_uuid(); v_po2 uuid := gen_random_uuid(); v_l1 uuid := gen_random_uuid(); v_l2 uuid := gen_random_uuid();
        v_i1 uuid := gen_random_uuid(); v_i2 uuid := gen_random_uuid(); v_i3 uuid := gen_random_uuid(); v_i4 uuid := gen_random_uuid(); v_i5 uuid := gen_random_uuid(); v_i6 uuid := gen_random_uuid(); v_i7 uuid := gen_random_uuid(); v_i8 uuid := gen_random_uuid(); v_i9 uuid := gen_random_uuid();
        v_c1 uuid := gen_random_uuid(); v_ch1 uuid := gen_random_uuid(); v_st uuid := gen_random_uuid(); v_staff uuid; v_j4 uuid; v_r record;
begin
  select * into v_ap_usd from public.ref_account where code = '_109_'; select * into v_ap_cad from public.ref_account where code = '_62_';
  if v_usd is null or v_cad is null or v_term is null or v_zero is null or v_oos is null or v_prod is null or v_realm is null or v_ap_usd.id is null or v_ap_cad.id is null then raise exception 'fixture: a reference row is missing (currency · term · tax rule · product AAL10850 · realm · A/P _109_ · _62_)'; end if;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (v_st, 'zz-qbo-sync-4-5a@test.invalid', 'ZZ qbo-sync-4-5a bookkeeper', 'manager', '["ims", "qbo", "purchasing"]', '{}') returning id into v_staff;
  insert into public.supplier (id, name, source, is_active, payment_term_id, payment_term_name, account_payable_id, account_payable_code, currency_id) values
    (v_sa, 'ZZ-QBO45 Supplier A', 'manual', true, v_term, 'Due on receipt', v_ap_usd.id, v_ap_usd.code, v_usd),
    (v_sb, 'ZZ-QBO45 Supplier B', 'manual', true, v_term, 'Due on receipt', v_ap_cad.id, v_ap_cad.code, v_cad),
    (v_sc, 'ZZ-QBO45 Supplier C', 'manual', true, v_term, 'Due on receipt', v_ap_cad.id, v_ap_cad.code, v_cad);
  insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, active) values (v_realm, 'Vendor', 'zz45va', 'ZZ-QBO45 Vendor A', true), (v_realm, 'Vendor', 'zz45vb', 'ZZ-QBO45 Vendor B', true), (v_realm, 'Vendor', 'zz45vc', 'ZZ-QBO45 Vendor C', true);
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by) values (v_realm, 'supplier', v_sa::text, 'Vendor', 'zz45va', 'manual'), (v_realm, 'supplier', v_sb::text, 'Vendor', 'zz45vb', 'manual'), (v_realm, 'supplier', v_sc::text, 'Vendor', 'zz45vc', 'manual');
  -- 계좌 다섯: acb BANK CAD(거울 Bank · CAD) · acc CREDITCARD USD(거울 Credit Card · USD) · acu BANK USD(거울 detail 없음 — 4-5b 전 운영 꼴) · acx BANK CAD(거울이 Credit Card — 1133 다름) · ace EXPENSE
  insert into public.ref_account (id, code, name, account_class, account_type, source, currency_code) values
    (v_acb, 'ZZ45-BANK-CAD', 'ZZ45 Bank CAD', 'ASSET', 'BANK', 'manual', null), (v_acc, 'ZZ45-CC-USD', 'ZZ45 Card USD', 'LIABILITY', 'CREDITCARD', 'manual', 'USD'),
    (v_acu, 'ZZ45-BANK-USD', 'ZZ45 Bank USD', 'ASSET', 'BANK', 'manual', 'USD'), (v_acx, 'ZZ45-BANK-CAD2', 'ZZ45 Bank CAD 2', 'ASSET', 'BANK', 'manual', null), (v_ace, 'ZZ45-EXP', 'ZZ45 Expense', 'EXPENSE', 'EXPENSE', 'manual', null);
  insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, active, detail) values
    (v_realm, 'Account', 'zz45acb', 'ZZ45 Bank CAD', true, '{"AccountType": "Bank", "CurrencyRef": {"value": "CAD"}}'::jsonb),
    (v_realm, 'Account', 'zz45acc', 'ZZ45 Card USD', true, '{"AccountType": "Credit Card", "CurrencyRef": {"value": "USD"}}'::jsonb),
    (v_realm, 'Account', 'zz45acu', 'ZZ45 Bank USD', true, null),
    (v_realm, 'Account', 'zz45acx', 'ZZ45 Bank CAD 2', true, '{"AccountType": "Credit Card", "CurrencyRef": {"value": "CAD"}}'::jsonb),
    (v_realm, 'Account', 'zz45ace', 'ZZ45 Expense', true, '{"AccountType": "Expense", "CurrencyRef": {"value": "CAD"}}'::jsonb);
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by) values
    (v_realm, 'account', v_acb::text, 'Account', 'zz45acb', 'manual'), (v_realm, 'account', v_acc::text, 'Account', 'zz45acc', 'manual'), (v_realm, 'account', v_acu::text, 'Account', 'zz45acu', 'manual'),
    (v_realm, 'account', v_acx::text, 'Account', 'zz45acx', 'manual'), (v_realm, 'account', v_ace::text, 'Account', 'zz45ace', 'manual');
  insert into public.po (id, po_number, status, supplier_id, currency_id) values (v_po1, 'PO-79451', 'confirmed', v_sa, v_usd), (v_po2, 'PO-79452', 'confirmed', v_sb, v_cad);
  insert into public.po_line (id, po_id, line_no, product_id, qty_ea, unit_price) values (v_l1, v_po1, 1, v_prod, 100, 2.5), (v_l2, v_po2, 1, v_prod, 100, 2.5);
  -- 인보이스(모두 confirmed · 세금 0): I1 A USD 20 · I2 A USD 10 · I3 B CAD 20 · I4 B CAD 10(bill queued) · I5 B CAD 10(since 전 · 10-15 생성) · I6 B CAD 10 + 크레딧 C1 2 · I7 C CAD 10 · I8 B CAD 10 · I9 B CAD 10
  insert into public.po_invoice (id, supplier_id, invoice_number, invoice_date, due_date, payment_term_id, payment_term_name, currency_id, exchange_rate, total_amount, status, doc_kind, tax_rule_id, confirmed_by, confirmed_at, created_at) values
    (v_i1, v_sa, 'ZZ45-INV-1', public.ims_today(), public.ims_today() + 30, v_term, 'Due on receipt', v_usd, 1.4, 20, 'confirmed', 'invoice', v_zero, v_staff, now(), now()),
    (v_i2, v_sa, 'ZZ45-INV-2', public.ims_today(), public.ims_today() + 30, v_term, 'Due on receipt', v_usd, 1.4, 10, 'confirmed', 'invoice', v_zero, v_staff, now(), now()),
    (v_i3, v_sb, 'ZZ45-INV-3', public.ims_today(), public.ims_today() + 30, v_term, 'Due on receipt', v_cad, null, 20, 'confirmed', 'invoice', v_zero, v_staff, now(), now()),
    (v_i4, v_sb, 'ZZ45-INV-4', public.ims_today(), public.ims_today() + 30, v_term, 'Due on receipt', v_cad, null, 10, 'confirmed', 'invoice', v_zero, v_staff, now(), now()),
    (v_i5, v_sb, 'ZZ45-INV-5', date '2026-10-15', date '2026-11-14', v_term, 'Due on receipt', v_cad, null, 10, 'confirmed', 'invoice', v_zero, v_staff, now(), timestamptz '2026-10-15 15:00:00-04'),
    (v_i6, v_sb, 'ZZ45-INV-6', public.ims_today(), public.ims_today() + 30, v_term, 'Due on receipt', v_cad, null, 10, 'confirmed', 'invoice', v_zero, v_staff, now(), now()),
    (v_i7, v_sc, 'ZZ45-INV-7', public.ims_today(), public.ims_today() + 30, v_term, 'Due on receipt', v_cad, null, 10, 'confirmed', 'invoice', v_zero, v_staff, now(), now()),
    (v_i8, v_sb, 'ZZ45-INV-8', public.ims_today(), public.ims_today() + 30, v_term, 'Due on receipt', v_cad, null, 10, 'confirmed', 'invoice', v_zero, v_staff, now(), now()),
    (v_i9, v_sb, 'ZZ45-INV-9', public.ims_today(), public.ims_today() + 30, v_term, 'Due on receipt', v_cad, null, 10, 'confirmed', 'invoice', v_zero, v_staff, now(), now()),
    (v_c1, v_sb, 'ZZ45-CR-1', public.ims_today(), null, null, null, v_cad, null, 2, 'confirmed', 'credit', v_zero, v_staff, now(), now());
  update public.po_invoice set credit_for_invoice_id = v_i6 where id = v_c1;
  insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price) values
    (v_i1, 1, 'goods', v_l1, 8, 2.5), (v_i2, 1, 'goods', v_l1, 4, 2.5), (v_i3, 1, 'goods', v_l2, 8, 2.5), (v_i4, 1, 'goods', v_l2, 4, 2.5), (v_i5, 1, 'goods', v_l2, 4, 2.5),
    (v_i6, 1, 'goods', v_l2, 4, 2.5), (v_i7, 1, 'goods', v_l2, 4, 2.5), (v_i8, 1, 'goods', v_l2, 4, 2.5), (v_i9, 1, 'goods', v_l2, 4, 2.5);
  insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, credit_reason) values (v_c1, 1, 'goods', v_l2, 1, 2, 'price_difference');
  -- 비용 CH1 A USD freight 7(세금 0)
  insert into public.po_charge (id, supplier_id, charge_number, charge_date, due_date, kind, currency_id, total_amount, tax_amount, status, tax_rule_id, confirmed_by, confirmed_at) values
    (v_ch1, v_sa, 'ZZ45-CH-1', public.ims_today(), public.ims_today() + 15, 'freight', v_usd, 7, 0, 'confirmed', v_oos, v_staff, now());
  insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (v_ch1, v_po1, 7);
  -- Bill 일감 sent + qbo_txn Bill(I1 · I2 · I3 · I6 · I7 · I8 · I9 · CH1) · I4 는 queued(txn 없음) · I5 는 since 전(일감 없음)
  for v_r in select * from (values (v_i1, 'po_invoice', 'ZZ45-INV-1', 'zz45b1', 20), (v_i2, 'po_invoice', 'ZZ45-INV-2', 'zz45b2', 10), (v_i3, 'po_invoice', 'ZZ45-INV-3', 'zz45b3', 20), (v_i6, 'po_invoice', 'ZZ45-INV-6', 'zz45b6', 10),
                                   (v_i7, 'po_invoice', 'ZZ45-INV-7', 'zz45b7', 10), (v_i8, 'po_invoice', 'ZZ45-INV-8', 'zz45b8', 10), (v_i9, 'po_invoice', 'ZZ45-INV-9', 'zz45b9', 10), (v_ch1, 'po_charge', 'ZZ45-CH-1', 'zz45c1', 7)) as x(id, ik, num, qid, amt) loop
    insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, sent_at, qbo_id, qbo_name, fingerprint, by_staff) values (v_realm, 'bill', v_r.ik, v_r.id::text, 'sent', now(), v_r.qid, v_r.num, (v_r.amt * 100)::text || '|X', v_staff);
    insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, fingerprint, source) values (v_realm, v_r.ik, v_r.id::text, 'Bill', v_r.qid, v_r.num, '0', v_r.amt, 0, (v_r.amt * 100)::text || '|X', 'sent');
  end loop;
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (v_realm, 'bill', 'po_invoice', v_i4::text, 'queued', v_staff) returning id into v_j4;
  perform pg_temp.put('staff', v_staff::text); perform pg_temp.put('st_uid', v_st::text); perform pg_temp.put('sa', v_sa::text); perform pg_temp.put('sb', v_sb::text); perform pg_temp.put('sc', v_sc::text);
  perform pg_temp.put('acb', v_acb::text); perform pg_temp.put('acc', v_acc::text); perform pg_temp.put('acu', v_acu::text); perform pg_temp.put('acx', v_acx::text); perform pg_temp.put('ace', v_ace::text);
  perform pg_temp.put('usd', v_usd::text); perform pg_temp.put('cad', v_cad::text); perform pg_temp.put('j4', v_j4::text);
  perform pg_temp.put('i1', v_i1::text); perform pg_temp.put('i2', v_i2::text); perform pg_temp.put('i3', v_i3::text); perform pg_temp.put('i4', v_i4::text); perform pg_temp.put('i5', v_i5::text); perform pg_temp.put('i6', v_i6::text);
  perform pg_temp.put('i7', v_i7::text); perform pg_temp.put('i8', v_i8::text); perform pg_temp.put('i9', v_i9::text); perform pg_temp.put('c1', v_c1::text); perform pg_temp.put('ch1', v_ch1::text);
end $$;
set constraints all immediate;
-- 결제 만들기 도우미 — 창구 po_payment_create(열쇠 직원 · commit) · 결과를 돌려주고 id 를 t_ids 에
create function pg_temp.mkpay(p_key text, p_sup text, p_cur text, p_amount numeric, p_acct text, p_ref text, p_targets jsonb, p_rate numeric default null, p_disc numeric default 0) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v := public.po_payment_create(nullif(p_sup, '')::uuid, public.ims_today(), p_amount, pg_temp.id(p_cur)::uuid, p_disc, nullif(p_acct, '')::uuid, p_ref, null, p_targets, true, p_rate);
  perform pg_temp.as_user(null);
  if p_key is not null then perform pg_temp.put(p_key, v->>'payment_id'); end if;
  return v;
end $$;

-- ── S1 CAD · BANK · 한 문서 전액 → 일감 1 · 몸(Check · PrintStatus NotSet · CurrencyRef CAD · 환율 없음 · PrivateNote 표지 · LinkedTxn = Bill Id) ──
do $$
declare v_r jsonb; v_b jsonb; v_j public.qbo_job;
begin
  v_r := pg_temp.mkpay('p1', pg_temp.id('sb'), 'cad', 10, pg_temp.id('acb'), 'ZZ45-P1', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i3'), 'amount', 10)));
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p1'));
  perform pg_temp.chk('S1a 저장(CAD · BANK · I3 10): 경고 0 · exchange_rate null · 일감 bill_payment/po_payment queued 하나 · by_staff = 직원', jsonb_array_length(v_r->'warnings')::text || ' ' || coalesce(v_r->>'exchange_rate', 'null') || ' ' || coalesce(v_j.state, '(none)') || ' ' || (select count(*) from public.qbo_job where ims_id = pg_temp.id('p1'))::text || ' ' || (v_j.by_staff = pg_temp.id('staff')::uuid)::text, '0 null queued 1 true');
  v_b := public.qbo_bill_payment_body(pg_temp.id('p1')::uuid);
  perform pg_temp.chk('S1b 몸 머리: kind bill_payment · ims_kind po_payment · DocNumber ZZ45-P1 · TxnDate 오늘 · TotalAmt 10 · VendorRef zz45vb · APAccountRef 62 · CurrencyRef CAD · ExchangeRate 없음 · PayType Check',
    (v_b->>'kind') || ' ' || (v_b->>'ims_kind') || ' ' || (v_b->'body'->>'DocNumber') || ' ' || ((v_b->'body'->>'TxnDate') = to_char(public.ims_today(), 'YYYY-MM-DD'))::text || ' ' || (v_b->'body'->>'TotalAmt') || ' ' || (v_b->'body'->'VendorRef'->>'value') || ' ' || (v_b->'body'->'APAccountRef'->>'value')
      || ' ' || (v_b->'body'->'CurrencyRef'->>'value') || ' ' || (v_b->'body' ? 'ExchangeRate')::text || ' ' || (v_b->'body'->>'PayType'), 'bill_payment po_payment ZZ45-P1 true 10 zz45vb 62 CAD false Check');
  perform pg_temp.chk('S1c CheckPayment.BankAccountRef zz45acb · PrintStatus NotSet · CreditCardPayment 없음 · PrivateNote 「IMS supplier payment <id>」 · 줄 1 Amount 10 · LinkedTxn zz45b3 Bill · check_lines 1(ZZ45-INV-3) · needs 0 · wait null · warnings 0',
    (v_b->'body'->'CheckPayment'->'BankAccountRef'->>'value') || ' ' || (v_b->'body'->'CheckPayment'->>'PrintStatus') || ' ' || (v_b->'body' ? 'CreditCardPayment')::text || ' ' || ((v_b->'body'->>'PrivateNote') = 'IMS supplier payment ' || pg_temp.id('p1'))::text
      || ' ' || (v_b->>'line_count') || ' ' || (v_b->'body'->'Line'->0->>'Amount') || ' ' || (v_b->'body'->'Line'->0->'LinkedTxn'->0->>'TxnId') || ' ' || (v_b->'body'->'Line'->0->'LinkedTxn'->0->>'TxnType')
      || ' ' || jsonb_array_length(v_b->'check_lines')::text || ' ' || (v_b->'check_lines'->0->>'doc_number') || ' ' || jsonb_array_length(v_b->'needs')::text || ' ' || coalesce(v_b->>'wait_job', 'null') || ' ' || jsonb_array_length(v_b->'warnings')::text,
    'zz45acb NotSet false true 1 10 zz45b3 Bill 1 ZZ45-INV-3 0 null 0');
  perform pg_temp.chk('S1d lookup(1134 열쇠 재료): entity BillPayment · vendor_ref zz45vb · total_cents 1000 · currency CAD · pay_type Check · private_note 표지 · 지문 = 함수 · 몸에 공급처 상호 없음 · totals.applied 10',
    (v_b->'lookup'->>'entity') || ' ' || (v_b->'lookup'->>'vendor_ref') || ' ' || (v_b->'lookup'->>'total_cents') || ' ' || (v_b->'lookup'->>'currency') || ' ' || (v_b->'lookup'->>'pay_type') || ' ' || ((v_b->'lookup'->>'private_note') = 'IMS supplier payment ' || pg_temp.id('p1'))::text
      || ' ' || ((v_b->>'fingerprint') = public.qbo_bill_payment_fingerprint(pg_temp.id('p1')::uuid))::text || ' ' || ((v_b->'body')::text ilike '%Supplier B%')::text || ' ' || (v_b->'totals'->>'applied'), 'BillPayment zz45vb 1000 CAD Check true true false 10');
end $$;

-- ── S2 USD · CREDITCARD · 두 문서(인보이스 + 청구서) 부분 → 줄 둘 · CurrencyRef USD · ExchangeRate · CCAccountRef ──
do $$
declare v_r jsonb; v_b jsonb;
begin
  v_r := pg_temp.mkpay('p2', pg_temp.id('sa'), 'usd', 12, pg_temp.id('acc'), 'ZZ45-P2', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i1'), 'amount', 5), jsonb_build_object('kind', 'charge', 'id', pg_temp.id('ch1'), 'amount', 7)), 1.35);
  v_b := public.qbo_bill_payment_body(pg_temp.id('p2')::uuid);
  perform pg_temp.chk('S2a 저장(USD · 환율 1.35 · I1 5 + CH1 7): 경고 0 · exchange_rate 1.35 · 저장된 환율 1.35 · 일감 queued', jsonb_array_length(v_r->'warnings')::text || ' ' || (v_r->>'exchange_rate') || ' ' || (select trim_scale(p.exchange_rate)::text from public.po_payment p where p.id = pg_temp.id('p2')::uuid) || ' ' || (pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p2'))).state, '0 1.35 1.35 queued');
  perform pg_temp.chk('S2b 몸: 줄 2 · CurrencyRef USD · ExchangeRate 1.35 · PayType CreditCard · CCAccountRef zz45acc · CheckPayment 없음 · APAccountRef 109 · VendorRef zz45va · 줄 금액 5 · 7 · LinkedTxn zz45b1 · zz45c1(청구서 Bill) · totals.exchange_rate 1.35',
    (v_b->>'line_count') || ' ' || (v_b->'body'->'CurrencyRef'->>'value') || ' ' || (v_b->'body'->>'ExchangeRate') || ' ' || (v_b->'body'->>'PayType') || ' ' || (v_b->'body'->'CreditCardPayment'->'CCAccountRef'->>'value') || ' ' || (v_b->'body' ? 'CheckPayment')::text
      || ' ' || (v_b->'body'->'APAccountRef'->>'value') || ' ' || (v_b->'body'->'VendorRef'->>'value') || ' ' || (select string_agg(x->>'Amount', ',' order by x->'LinkedTxn'->0->>'TxnId') from jsonb_array_elements(v_b->'body'->'Line') x) || ' ' || (select string_agg(x->'LinkedTxn'->0->>'TxnId', ',' order by x->'LinkedTxn'->0->>'TxnId') from jsonb_array_elements(v_b->'body'->'Line') x)
      || ' ' || (v_b->'totals'->>'exchange_rate'), '2 USD 1.35 CreditCard zz45acc false 109 zz45va 5,7 zz45b1,zz45c1 1.35');
end $$;

-- ── S3 USD 환율 빔 → 저장은 경고 · 몸은 raise · claim → failed · 환율 채우면 일감 다시 맞춤(requeued · 빠져나가는 길) ──
do $$
declare v_r jsonb; v_e text; v_j public.qbo_job; v_b jsonb; v_rid uuid;
begin
  v_r := pg_temp.mkpay('p3', pg_temp.id('sa'), 'usd', 10, pg_temp.id('acc'), 'ZZ45-P3', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i2'), 'amount', 10)));
  v_e := pg_temp.try(format($q$select public.qbo_bill_payment_body(%L::uuid)::text$q$, pg_temp.id('p3')));
  perform pg_temp.chk('S3a 환율 없는 USD 결제: 저장 경고 exchange_rate_missing · 몸 raise 「has no exchange rate … (1123) … (1118)」', ((v_r->'warnings')::text ~ 'exchange_rate_missing')::text || ' ' || (v_e ~ 'has no exchange rate')::text || ' ' || (v_e ~ '1123')::text || ' ' || (v_e ~ '1118')::text, 'true true true true');
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p3'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill_payment'], array[%L::uuid])$q$, v_j.id));
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p3'));
  perform pg_temp.chk('S3b claim: body_failed 1 · 일감 failed · 글 no exchange rate', (v_r->>'body_failed') || ' ' || v_j.state || ' ' || (v_j.last_error ~ 'has no exchange rate')::text, '1 failed true');
  v_rid := v_j.request_id;
  update public.po_payment set exchange_rate = 1.36 where id = pg_temp.id('p3')::uuid;                      -- 직접 update(문지기가 안 막는다 · 4-5c 화면 칸과 같은 길)
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p3'));
  v_b := public.qbo_bill_payment_body(pg_temp.id('p3')::uuid);
  perform pg_temp.chk('S3c 환율 채움(직접 update 1.36): 지문 바뀜 → failed 일감 queued(「sent again: the payment changed」) · request_id 새로 · 몸 ExchangeRate 1.36', v_j.state || ' ' || (v_j.note ~ 'sent again: the payment changed')::text || ' ' || (v_j.request_id <> v_rid)::text || ' ' || (v_b->'body'->>'ExchangeRate'), 'queued true true 1.36');
end $$;

-- ── S4 1132 — ① 할인 · ② 붙은 크레딧 · ③ gap ≠ 0 → 몸 raise · 글이 다르다 · 고치면 다시 보낼 수 있다(① requeue · ② Retry · ③ requeue) ──
do $$
declare v_r jsonb; v_e1 text; v_e2 text; v_e3 text; v_j public.qbo_job; v_al uuid; v_b jsonb; v_fp0 text;
begin
  -- ① P4 I9 10 → 할인 1(문지기 문 열고 직접 — 원가 사건 없이 할인만 심는다)
  v_r := pg_temp.mkpay('p4', pg_temp.id('sb'), 'cad', 10, pg_temp.id('acb'), 'ZZ45-P4', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i9'), 'amount', 10)));
  perform set_config('po.payment_door', '1', true);
  update public.po_payment_alloc set discount_amount = 1 where po_payment_id = pg_temp.id('p4')::uuid;
  perform set_config('po.payment_door', '', true);
  v_e1 := pg_temp.try(format($q$select public.qbo_bill_payment_body(%L::uuid)::text$q$, pg_temp.id('p4')));
  perform pg_temp.chk('S4a ① 할인 1(Σ 트리거 → discount_taken 1): 몸 raise 「Enter this payment in QuickBooks by hand … (1132 ①: … early-payment discount of 1 CAD)」', (select trim_scale(p.discount_taken)::text from public.po_payment p where p.id = pg_temp.id('p4')::uuid) || ' ' || (v_e1 ~ 'Enter this payment in QuickBooks by hand, then press Skip')::text || ' ' || (v_e1 ~ '1132 ①: supplier payment ZZ45-P4 takes an early-payment discount of 1 CAD')::text, '1 true true');
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p4'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill_payment'], array[%L::uuid])$q$, v_j.id));
  perform set_config('po.payment_door', '1', true);
  update public.po_payment_alloc set discount_amount = 0 where po_payment_id = pg_temp.id('p4')::uuid;
  perform set_config('po.payment_door', '', true);
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p4'));
  perform pg_temp.chk('S4b ① claim → failed · 할인 0 으로 되돌림 → queued(requeue) · 몸이 선다', (v_r->>'body_failed') || ' ' || v_j.state || ' ' || (pg_temp.try(format($q$select public.qbo_bill_payment_body(%L::uuid)->>'kind'$q$, pg_temp.id('p4')))), '1 queued bill_payment');
  -- ② P5 I6(크레딧 C1 2 가 붙어 unpaid 8 · 금액 생략 = 미지급 전액)
  v_r := pg_temp.mkpay('p5', pg_temp.id('sb'), 'cad', 8, pg_temp.id('acb'), 'ZZ45-P5', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i6'))));
  v_e2 := pg_temp.try(format($q$select public.qbo_bill_payment_body(%L::uuid)::text$q$, pg_temp.id('p5')));
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p5'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill_payment'], array[%L::uuid])$q$, v_j.id));
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p5'));
  perform pg_temp.chk('S4c ② 붙은 크레딧(I6 ← C1 confirmed): 충당 8 · 몸 raise 「… (1132 ②: invoice ZZ45-INV-6 has a supplier credit applied …) … press Retry」 · claim → failed', (select trim_scale(a.amount)::text from public.po_payment_alloc a where a.po_payment_id = pg_temp.id('p5')::uuid) || ' ' || (v_e2 ~ '1132 ②: invoice ZZ45-INV-6 has a supplier credit applied')::text || ' ' || (v_e2 ~ 'press Retry')::text || ' ' || v_j.state, '8 true true failed');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_r := public.qbo_job_retry(v_j.id, null);
  perform pg_temp.as_user(null);
  perform pg_temp.chk('S4d ② 출구 = Retry(failed · 지문 있음): queued', (v_r->>'state'), 'queued');
  -- ③ P2 의 청구서 줄을 떼면 gap 7 → raise · 다시 붙이면 몸이 선다 · 지문 같아 일감 queued 그대로
  v_fp0 := public.qbo_bill_payment_fingerprint(pg_temp.id('p2')::uuid);
  select a.id into v_al from public.po_payment_alloc a where a.po_payment_id = pg_temp.id('p2')::uuid and a.po_charge_id is not null;
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_r := public.po_payment_alloc_delete(v_al);
  v_e3 := pg_temp.try(format($q$select public.qbo_bill_payment_body(%L::uuid)::text$q$, pg_temp.id('p2')));
  v_r := public.po_payment_alloc_set(pg_temp.id('p2')::uuid, 'charge', pg_temp.id('ch1')::uuid, 7, null);
  perform pg_temp.as_user(null);
  v_b := public.qbo_bill_payment_body(pg_temp.id('p2')::uuid);
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p2'));
  perform pg_temp.chk('S4e ③ 청구서 줄 뗌(gap 7): raise 「(1132 ③: … add up to 5 but the payment is 12 USD, gap 7)」 · 다시 붙임 → 줄 2 · 지문 처음과 같다 · 일감 queued 하나', (v_e3 ~ '1132 ③: the amounts applied to documents add up to 5 but the payment is 12 USD, gap 7')::text || ' ' || (v_b->>'line_count') || ' ' || (public.qbo_bill_payment_fingerprint(pg_temp.id('p2')::uuid) = v_fp0)::text || ' ' || v_j.state || ' ' || (select count(*) from public.qbo_job where ims_id = pg_temp.id('p2'))::text, 'true 2 true queued 1');
end $$;

-- ── S5 1124 — 두 공급처 섞기: create 거부 · alloc_set 거부 · 직접 UPDATE 로 대상 바꾸기 거부 ──
do $$
declare v_e1 text; v_e2 text; v_e3 text; v_al uuid;
begin
  v_e1 := pg_temp.try(format($q$select pg_temp.mkpay(null, %L, 'cad', 10, %L, 'ZZ45-P6', %L::jsonb)::text$q$, pg_temp.id('sb'), pg_temp.id('acb'), jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i3'), 'amount', 5), jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i7'), 'amount', 5))::text));
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_e2 := pg_temp.try(format($q$select public.po_payment_alloc_set(%L::uuid, 'invoice', %L::uuid, 5, null)::text$q$, pg_temp.id('p1'), pg_temp.id('i7')));
  perform pg_temp.as_user(null);
  select a.id into v_al from public.po_payment_alloc a where a.po_payment_id = pg_temp.id('p1')::uuid;
  v_e3 := pg_temp.try(format($q$update public.po_payment_alloc set po_invoice_id = %L::uuid where id = %L::uuid returning id::text$q$, pg_temp.id('i7'), v_al));
  perform pg_temp.chk('S5 1124: create(B + C 문서) 거부 「documents of 2 suppliers … (1124)」 · alloc_set(P1 에 C 문서) 거부 「belongs to another supplier … (1124)」 · 직접 UPDATE 대상 바꾸기 거부 「remove the line and add the document again」 · P1 줄 그대로 I3',
    (v_e1 ~ 'documents of 2 suppliers')::text || ' ' || (v_e1 ~ '1124')::text || ' ' || (v_e2 ~ 'belongs to another supplier')::text || ' ' || (v_e2 ~ '1124')::text || ' ' || (v_e3 ~ 'remove the line and add the document again')::text || ' ' || (select (a.po_invoice_id = pg_temp.id('i3')::uuid)::text from public.po_payment_alloc a where a.id = v_al), 'true true true true true true');
end $$;

-- ── S6 Bill 일감 queued 인 문서(I4)에 붙인 결제 → wait_job → claim blocked · Bill sent 되면 claim ② 가 푼다 ──
do $$
declare v_r jsonb; v_b jsonb; v_j public.qbo_job; v_realm text := (select realm_id from public.qbo_connection where singleton);
begin
  v_r := pg_temp.mkpay('p7', pg_temp.id('sb'), 'cad', 10, pg_temp.id('acb'), 'ZZ45-P7', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i4'), 'amount', 10)));
  v_b := public.qbo_bill_payment_body(pg_temp.id('p7')::uuid);
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p7'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill_payment'], array[%L::uuid])$q$, v_j.id));
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p7'));
  perform pg_temp.chk('S6a Bill queued: 몸 wait_job = I4 의 bill 일감 · wait_reason 「waiting for bill ZZ45-INV-4」 · 줄 0 · claim → blocked_for_invoice 1 · blocked_by = 그 일감 · warning 글', ((v_b->>'wait_job') = pg_temp.id('j4'))::text || ' ' || (v_b->>'wait_reason') || ' ' || (v_b->>'line_count') || ' ' || (v_r->>'blocked_for_invoice') || ' ' || v_j.state || ' ' || (v_j.blocked_by = pg_temp.id('j4')::uuid)::text || ' ' || (v_j.warning ~ 'waiting for bill ZZ45-INV-4')::text,
    'true waiting for bill ZZ45-INV-4 to reach QuickBooks first — send it too 0 1 blocked true true');
  update public.qbo_job set state = 'sent', sent_at = now(), qbo_id = 'zz45b4', qbo_name = 'ZZ45-INV-4', fingerprint = '1000|CAD' where id = pg_temp.id('j4')::uuid;
  insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, fingerprint, source) values (v_realm, 'po_invoice', pg_temp.id('i4'), 'Bill', 'zz45b4', 'ZZ45-INV-4', '0', 10, 0, '1000|CAD', 'sent');
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill_payment'], array[%L::uuid])$q$, v_j.id));
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p7'));
  perform pg_temp.chk('S6b Bill sent 뒤 claim: unblocked ≥ 1 · claimed 1 · sending · jobs[0] LinkedTxn zz45b4 · 지문 적힘', ((v_r->>'unblocked')::int >= 1)::text || ' ' || (v_r->>'claimed') || ' ' || v_j.state || ' ' || (v_r->'jobs'->0->'body'->'Line'->0->'LinkedTxn'->0->>'TxnId') || ' ' || (v_j.fingerprint = public.qbo_bill_payment_fingerprint(pg_temp.id('p7')::uuid))::text, 'true 1 sending zz45b4 true');
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz45bp7', 'ZZ45-P7', '0', null, null, null, 10.00, null, null)$q$, v_j.id));
  perform pg_temp.chk('S6c done(10.00 = IMS 10): sent · linked · qbo_txn po_payment ↔ BillPayment zz45bp7 · doc_number ZZ45-P7 · 지문 옮김 · mismatch 없음 · reconcile same', (v_r->>'state') || ' ' || (v_r->>'linked') || ' ' || (select t.qbo_type || ' ' || t.qbo_id || ' ' || t.doc_number || ' ' || (t.fingerprint = public.qbo_bill_payment_fingerprint(pg_temp.id('p7')::uuid))::text || ' ' || coalesce(t.mismatch, '-') from public.qbo_txn t where t.ims_kind = 'po_payment' and t.ims_id = pg_temp.id('p7')) || ' ' || (v_r->'reconcile'->>'action'), 'sent true BillPayment zz45bp7 ZZ45-P7 true - same');
end $$;

-- ── S10 1133 대조 — 거울 값 없음 · 다름 · 같음(S1) · 계좌 종류 아님 · since 전 문서 ──
do $$
declare v_r jsonb; v_e text;
begin
  v_r := pg_temp.mkpay('p8', pg_temp.id('sa'), 'usd', 5, pg_temp.id('acu'), 'ZZ45-P8', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i1'), 'amount', 5)), 1.3);
  v_e := pg_temp.try(format($q$select public.qbo_bill_payment_body(%L::uuid)::text$q$, pg_temp.id('p8')));
  perform pg_temp.chk('S10a 거울 값 없음(BANK USD · detail null — 4-5b 전 운영 꼴): raise 「QuickBooks account #zz45acu … no account type or currency on file yet — … Refresh list (accounts) … (1133)」', (v_e ~ 'QuickBooks account #zz45acu')::text || ' ' || (v_e ~ 'no account type or currency on file yet')::text || ' ' || (v_e ~ 'Refresh list \(accounts\)')::text || ' ' || (v_e ~ '1133')::text, 'true true true true');
  v_r := pg_temp.mkpay('p9', pg_temp.id('sb'), 'cad', 5, pg_temp.id('acx'), 'ZZ45-P9', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i8'), 'amount', 5)));
  v_e := pg_temp.try(format($q$select public.qbo_bill_payment_body(%L::uuid)::text$q$, pg_temp.id('p9')));
  perform pg_temp.chk('S10b 거울 다름(IMS BANK · 거울 Credit Card): raise 「IMS account ZZ45-BANK-CAD2 is BANK but QuickBooks account #zz45acx is "Credit Card" — fix … (1133)」', (v_e ~ 'IMS account ZZ45-BANK-CAD2 is BANK but QuickBooks account #zz45acx is "Credit Card"')::text || ' ' || (v_e ~ '1133')::text, 'true true');
  v_r := pg_temp.mkpay('p12', pg_temp.id('sb'), 'cad', 5, pg_temp.id('ace'), 'ZZ45-P12', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i5'), 'amount', 5)));
  v_e := pg_temp.try(format($q$select public.qbo_bill_payment_body(%L::uuid)::text$q$, pg_temp.id('p12')));
  perform pg_temp.chk('S10c 계좌가 EXPENSE: raise 「… which is a EXPENSE account — a supplier payment goes out of a BANK or CREDITCARD account (1133)」(since 검사보다 먼저)', (v_e ~ 'which is a EXPENSE account')::text || ' ' || (v_e ~ 'BANK or CREDITCARD account \(1133\)')::text, 'true true');
  v_r := pg_temp.mkpay('p13', pg_temp.id('sb'), 'cad', 5, pg_temp.id('acb'), 'ZZ45-P13', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i5'), 'amount', 5)));
  v_e := pg_temp.try(format($q$select public.qbo_bill_payment_body(%L::uuid)::text$q$, pg_temp.id('p13')));
  perform pg_temp.chk('S10d since 전 문서(I5 · 10-15 생성 · Bill 일감 없음)에 붙은 결제: raise 「Enter … by hand … (Invoice ZZ45-INV-5 was created in IMS before the QuickBooks start date …)」(이견 15)', (v_e ~ 'Enter this payment in QuickBooks by hand')::text || ' ' || (v_e ~ 'Invoice ZZ45-INV-5 was created in IMS before the QuickBooks start date')::text, 'true true');
  perform pg_temp.chk('S10e 1122 는 저장에서 막힌다(4-3b 트리거): USD 결제를 CAD 계좌로 → 거부 글 「bank account ZZ45-BANK-CAD is in CAD but the payment currency is USD」', (pg_temp.try(format($q$select pg_temp.mkpay(null, %L, 'usd', 5, %L, 'ZZ45-PX', %L::jsonb, 1.3)::text$q$, pg_temp.id('sa'), pg_temp.id('acb'), jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i1'), 'amount', 5))::text)) ~ 'bank account ZZ45-BANK-CAD is in CAD but the payment currency is USD')::text, 'true');
end $$;

-- ── S7 보낸 뒤 바꿈 → void + 새 장 blocked · void 몸 · void done → 풀림 · 다시 보냄 · 지우기 둘(po_doc_delete · 직접 DELETE) → void 만 · 안 나간 일감은 skipped ──
do $$
declare v_r jsonb; v_j public.qbo_job; v_v public.qbo_job; v_b jsonb; v_t public.qbo_txn%rowtype;
begin
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p1'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill_payment'], array[%L::uuid])$q$, v_j.id));
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz45bp1', 'ZZ45-P1', '0', null, null, null, 10.00, null, null)$q$, v_j.id));
  update public.po_payment set paid_on = public.ims_today() + 1 where id = pg_temp.id('p1')::uuid;            -- 머리 칸 직접 update(화면 saveHead 와 같은 길) → 지문 바뀜
  v_v := pg_temp.job('bill_payment_void', 'po_payment', pg_temp.id('p1'));
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p1'));
  v_b := public.qbo_bill_payment_void_body(pg_temp.id('p1')::uuid);
  perform pg_temp.chk('S7a P1 sent 뒤 paid_on 바꿈: void 일감 queued(note 「changed — void, then send again」) · 새 bill_payment 일감 blocked · blocked_by = void · void 몸 {Id zz45bp1, SyncToken 0, sparse true} · lookup entity BillPayment',
    coalesce(v_v.state, '(none)') || ' ' || (v_v.note ~ 'supplier payment changed — void, then send again')::text || ' ' || v_j.state || ' ' || (v_j.blocked_by = v_v.id)::text || ' ' || (v_j.id <> v_v.id)::text || ' ' || (v_b->'body'->>'Id') || ' ' || (v_b->'body'->>'SyncToken') || ' ' || (v_b->'body'->>'sparse') || ' ' || (v_b->'lookup'->>'entity'),
    'queued true blocked true true zz45bp1 0 true BillPayment');
  update public.po_payment set paid_on = public.ims_today() where id = pg_temp.id('p1')::uuid;
  perform pg_temp.chk('S7b 똑같이 되돌림(지문 = QBO): 안 나간 void 는 skipped(「restored」) · 새 bill_payment 일감도 skipped · 열린 일감 0', (select coalesce(string_agg(j.kind || ':' || j.state, ',' order by j.kind), '(none)') from public.qbo_job j where j.ims_id = pg_temp.id('p1') and j.state not in ('sent', 'skipped')) || ' | ' || (select string_agg(j.kind || ':' || j.state, ',' order by j.kind, j.created_at) from public.qbo_job j where j.ims_id = pg_temp.id('p1') and j.state = 'skipped'), '(none) | bill_payment:skipped,bill_payment_void:skipped');
  update public.po_payment set reference = 'ZZ45-P1-REFERENCE-TOO-LONG-99' where id = pg_temp.id('p1')::uuid;
  v_v := pg_temp.job('bill_payment_void', 'po_payment', pg_temp.id('p1'));
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p1'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill_payment_void'], array[%L::uuid])$q$, v_v.id));
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz45bp1', 'ZZ45-P1', '1', null, null, null)$q$, v_v.id));
  select * into v_t from public.qbo_txn t where t.ims_kind = 'po_payment' and t.ims_id = pg_temp.id('p1');
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p1'));
  perform pg_temp.chk('S7c reference 바꿈 → 새 void queued + 새 장 blocked · void claim → done: qbo_txn voided_at · 새 장 unblocked(queued · done 의 ② 가 풀었다) · reconcile none', (v_r->>'state') || ' ' || (v_r->>'unblocked') || ' ' || (v_t.voided_at is not null)::text || ' ' || v_j.state || ' ' || (v_r->'reconcile'->>'action'), 'sent 1 true queued none');
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill_payment'], array[%L::uuid])$q$, v_j.id));
  perform pg_temp.chk('S7d 다시 보내기 몸(reference 29 자): DocNumber 21 자 「ZZ45-P1-REFERENCE-TOO」 · 경고 1130 · PrivateNote 에 full reference', (v_r->'jobs'->0->>'doc_number') || ' ' || length(v_r->'jobs'->0->>'doc_number')::text || ' ' || ((v_r->'jobs'->0->'warnings')::text ~ '1130')::text || ' ' || ((v_r->'jobs'->0->'body'->>'PrivateNote') like '%full reference: ZZ45-P1-REFERENCE-TOO-LONG-99')::text, 'ZZ45-P1-REFERENCE-TOO 21 true true');
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz45bp1b', 'ZZ45-P1-REFERENCE-TOO', '0', null, null, null, 10.00, null, null)$q$, v_j.id));
  select * into v_t from public.qbo_txn t where t.ims_kind = 'po_payment' and t.ims_id = pg_temp.id('p1');
  perform pg_temp.chk('S7e 다시 보낸 뒤: qbo_txn 한 행 · qbo_id zz45bp1b · voided_at null', (select count(*) from public.qbo_txn t where t.ims_kind = 'po_payment' and t.ims_id = pg_temp.id('p1'))::text || ' ' || v_t.qbo_id || ' ' || (v_t.voided_at is null)::text, '1 zz45bp1b true');
  -- 지우기 둘 — P10 sent → po_doc_delete('payment') · P11 sent → 직접 DELETE · P9(failed · 안 나감) → po_doc_delete → skipped · void 없음
  v_r := pg_temp.mkpay('p10', pg_temp.id('sb'), 'cad', 5, pg_temp.id('acb'), 'ZZ45-P10', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i8'), 'amount', 5)));
  v_r := pg_temp.mkpay('p11', pg_temp.id('sb'), 'cad', 10, pg_temp.id('acb'), 'ZZ45-P11', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i3'), 'amount', 10)));
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p10'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill_payment'], array[%L::uuid])$q$, v_j.id));
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz45bp10', 'ZZ45-P10', '0', null, null, null, 5.00, null, null)$q$, v_j.id));
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p11'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill_payment'], array[%L::uuid])$q$, v_j.id));
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz45bp11', 'ZZ45-P11', '0', null, null, null, 10.00, null, null)$q$, v_j.id));
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p9'));
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill_payment'], array[%L::uuid])$q$, v_j.id));
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_r := public.po_doc_delete('payment', pg_temp.id('p10')::uuid);
  v_r := public.po_doc_delete('payment', pg_temp.id('p9')::uuid);
  perform pg_temp.as_user(null);
  delete from public.po_payment where id = pg_temp.id('p11')::uuid;
  perform pg_temp.chk('S7f 지우기: P10(sent · po_doc_delete) → void queued 만(「deleted or fully detached」) · P11(sent · 직접 DELETE) → void queued 만 · P9(failed · 안 나감 · po_doc_delete) → skipped · void 0 · 결제 행 셋 없음',
    (select string_agg(j.kind || ':' || j.state, ',' order by j.kind) from public.qbo_job j where j.ims_id = pg_temp.id('p10') and j.state not in ('sent', 'skipped')) || ' ' || (select (j.note ~ 'deleted or fully detached')::text from public.qbo_job j where j.ims_id = pg_temp.id('p10') and j.kind = 'bill_payment_void')
      || ' | ' || (select string_agg(j.kind || ':' || j.state, ',' order by j.kind) from public.qbo_job j where j.ims_id = pg_temp.id('p11') and j.state not in ('sent', 'skipped'))
      || ' | ' || (select string_agg(j.kind || ':' || j.state, ',' order by j.kind) from public.qbo_job j where j.ims_id = pg_temp.id('p9')) || ' ' || (select count(*) from public.qbo_job j where j.ims_id = pg_temp.id('p9') and j.kind = 'bill_payment_void')::text
      || ' | ' || (select count(*) from public.po_payment p where p.id in (pg_temp.id('p9')::uuid, pg_temp.id('p10')::uuid, pg_temp.id('p11')::uuid))::text,
    'bill_payment_void:queued true | bill_payment_void:queued | bill_payment:skipped 0 | 0');
  v_b := public.qbo_bill_payment_void_body(pg_temp.id('p11')::uuid);
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  perform pg_temp.chk('S7g 지워진 결제의 void 몸(qbo_txn 만으로): Id zz45bp11 · name = doc_number ZZ45-P11 · retry(bill_payment · 지워짐) 거부 「deleted or has no document applied」', (v_b->'body'->>'Id') || ' ' || (v_b->>'name') || ' ' || (pg_temp.try(format($q$select public.qbo_job_retry(%L::uuid, 'zz')::text$q$, (select j.id from public.qbo_job j where j.ims_id = pg_temp.id('p9') and j.kind = 'bill_payment'))) ~ 'deleted or has no document applied')::text, 'zz45bp11 ZZ45-P11 true');
  perform pg_temp.as_user(null);
end $$;

-- ── S8 붙임 떼고 인보이스 취소 → bill_delete_manual 이 void 뒤에서 기다린다(이견 6 안 ㄱ) ──
do $$
declare v_r jsonb; v_v public.qbo_job; v_v11 public.qbo_job; v_d public.qbo_job; v_al uuid; v_st uuid := pg_temp.id('staff')::uuid;
begin
  select a.id into v_al from public.po_payment_alloc a where a.po_payment_id = pg_temp.id('p1')::uuid;
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_r := public.po_payment_alloc_delete(v_al);
  perform pg_temp.as_user(null);
  v_v := pg_temp.job('bill_payment_void', 'po_payment', pg_temp.id('p1'));
  perform pg_temp.chk('S8a P1(sent zz45bp1b) 붙임 뗌: void 일감 queued · note 「detached from po_invoice <I3>」 · 열린 bill_payment 0(지문 null)', coalesce(v_v.state, '(none)') || ' ' || (v_v.note ~ ('detached from po_invoice ' || pg_temp.id('i3')))::text || ' ' || (select count(*) from public.qbo_job j where j.ims_id = pg_temp.id('p1') and j.kind = 'bill_payment' and j.state not in ('sent', 'skipped'))::text, 'queued true 0');
  update public.po_invoice set status = 'cancelled', cancelled_by = v_st, cancelled_at = now() where id = pg_temp.id('i3')::uuid;
  v_d := pg_temp.job('bill_delete_manual', 'po_invoice', pg_temp.id('i3'));
  v_v11 := pg_temp.job('bill_payment_void', 'po_payment', pg_temp.id('p11'));
  perform pg_temp.chk('S8b I3 취소(Bill sent · 결제 붙임 0): bill_delete_manual blocked · blocked_by = I3 에서 뗀 결제의 가장 오래된 열린 void(P11 · 직접 DELETE 의 CASCADE 가 뗀 문서를 note 에 남겼다 · P1 의 void 도 note 에 I3) · note 「waits until the bill payment … is voided」 · Bill qbo_txn voided_at',
    coalesce(v_d.state, '(none)') || ' ' || (v_d.blocked_by = v_v11.id)::text || ' ' || (v_v11.note ~ ('detached from po_invoice ' || pg_temp.id('i3')))::text || ' ' || (v_d.note ~ 'waits until the bill payment that was applied to it is voided')::text || ' ' || (select (t.voided_at is not null)::text from public.qbo_txn t where t.ims_kind = 'po_invoice' and t.ims_id = pg_temp.id('i3')), 'blocked true true true true');
  v_r := pg_temp.svc(format($q$select public.qbo_job_claim(15, array['bill_payment_void'], array[%L::uuid])$q$, v_v11.id));
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz45bp11', 'ZZ45-P11', '1', null, null, null)$q$, v_v11.id));
  v_d := pg_temp.job('bill_delete_manual', 'po_invoice', pg_temp.id('i3'));
  perform pg_temp.chk('S8c P11 void done(결제 행은 이미 없다 · qbo_txn 만으로): sent · bill_delete_manual 풀림(queued · 사람이 QBO 에서 지우고 Skip) · unblocked 1 · P1 의 void 는 아직 queued(사람이 따로 보낸다)', (v_r->>'state') || ' ' || v_d.state || ' ' || (v_r->>'unblocked') || ' ' || (pg_temp.job('bill_payment_void', 'po_payment', pg_temp.id('p1'))).state, 'sent queued 1 queued');
end $$;

-- ── S9 한 트랜잭션(deferred)에서 붙임 셋 바꿈 → 끝에 한 번 · 일감 하나 ──
set constraints po_payment_qbo, po_payment_alloc_qbo deferred;
do $$
declare v_r jsonb; v_n0 int;
begin
  select count(*) into v_n0 from public.qbo_job where ims_id = pg_temp.id('p2');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_r := public.po_payment_alloc_set(pg_temp.id('p2')::uuid, 'charge', pg_temp.id('ch1')::uuid, 6, null);
  v_r := public.po_payment_alloc_set(pg_temp.id('p2')::uuid, 'charge', pg_temp.id('ch1')::uuid, 5, null);
  v_r := public.po_payment_alloc_set(pg_temp.id('p2')::uuid, 'charge', pg_temp.id('ch1')::uuid, 7, null);
  perform pg_temp.as_user(null);
  perform pg_temp.chk('S9a deferred 동안(트리거 아직 안 돎): 일감 수 그대로 · 열린 일감 queued 하나', (select count(*) from public.qbo_job where ims_id = pg_temp.id('p2'))::text || '=' || v_n0::text || ' ' || (select string_agg(j.state, ',') from public.qbo_job j where j.ims_id = pg_temp.id('p2') and j.state not in ('sent', 'skipped')), v_n0::text || '=' || v_n0::text || ' queued');
end $$;
set constraints all immediate;
select pg_temp.chk('S9b immediate(= 트랜잭션 끝): 트리거가 행마다 돌아도 일감 하나(queued · 지문 처음과 같다 · CH1 7)', (select count(*) from public.qbo_job where ims_id = pg_temp.id('p2'))::text || ' ' || (select string_agg(j.state, ',') from public.qbo_job j where j.ims_id = pg_temp.id('p2') and j.state not in ('sent', 'skipped')) || ' ' || (select trim_scale(a.amount)::text from public.po_payment_alloc a where a.po_payment_id = pg_temp.id('p2')::uuid and a.po_charge_id is not null), '1 queued 7');

-- ── S11 손님 결제 흐름 무변(회귀) · S13 list · preview · doc · G 구조 · W1 REST ──
do $$
declare v_l jsonb; v_p jsonb; v_j public.qbo_job;
begin
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_l := public.qbo_job_list(null, array['bill_payment', 'bill_payment_void'], null, null, 'ZZ45-P7', 50, 0);
  perform pg_temp.chk('S13a qbo_job_list(kinds 둘 · q ZZ45-P7): total 1 · ims_name 「ZZ45-P7 · <공급처> · CAD 10.00」 꼴 · txn_qbo_id zz45bp7', (v_l->>'total') || ' ' || ((v_l->'rows'->0->>'ims_name') like 'ZZ45-P7 · ZZ-QBO45 Supplier B · CAD 10%')::text || ' ' || (v_l->'rows'->0->>'txn_qbo_id'), '1 true zz45bp7');
  v_j := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p2'));
  v_p := public.qbo_job_preview(v_j.id);
  perform pg_temp.chk('S13b preview(P2 queued): sendable true · body.PayType CreditCard · doc.doc_number ZZ45-P2 · doc.name 공급처 A · doc.currency USD · fingerprint 있음 · check_lines 2', (v_p->>'sendable') || ' ' || (v_p->'body'->>'PayType') || ' ' || (v_p->'doc'->>'doc_number') || ' ' || (v_p->'doc'->>'name') || ' ' || (v_p->'doc'->>'currency') || ' ' || (v_p->>'fingerprint' is not null)::text || ' ' || jsonb_array_length(v_p->'check_lines')::text, 'true CreditCard ZZ45-P2 ZZ-QBO45 Supplier A USD true 2');
  perform pg_temp.chk('S13c qbo_job_doc(po_payment): 지워진 결제 null · 있는 결제 reference · doc_status active · total', coalesce(public.qbo_job_doc('po_payment', pg_temp.id('p11'))::text, 'null') || ' | ' || (public.qbo_job_doc('po_payment', pg_temp.id('p7'))->>'doc_number') || ' ' || (public.qbo_job_doc('po_payment', pg_temp.id('p7'))->>'doc_status') || ' ' || (public.qbo_job_doc('po_payment', pg_temp.id('p7'))->>'total'), 'null | ZZ45-P7 active 10');
  perform pg_temp.chk('S13d void 몸(QBO 쪽이 이미 void 된 P11): 거부 「already voided」 · retry(P11 의 sent void) 거부 「Only a failed or skipped job」', (pg_temp.try(format($q$select public.qbo_bill_payment_void_body(%L::uuid)::text$q$, pg_temp.id('p11'))) ~ 'is already voided')::text || ' ' || (pg_temp.try(format($q$select public.qbo_job_retry(%L::uuid, 'zz')::text$q$, (pg_temp.job('bill_payment_void', 'po_payment', pg_temp.id('p11'))).id)) ~ 'Only a failed or skipped job')::text, 'true true');
  perform pg_temp.as_user(null);
end $$;
select pg_temp.chk('S11 손님 결제 흐름 무변: payment · payment_void 일감 수 = 기준 · 무변 열다섯 md5 = begin 앞', ((select count(*) from public.qbo_job where kind in ('payment', 'payment_void')) = :pre_cust_pay_jobs)::text || ' ' || ((select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_payment_sync', 'qbo_payment_body', 'qbo_payment_void_body', 'qbo_payment_fingerprint', 'qbo_job_on_payment_alloc', 'qbo_job_on_payment_status', 'po_doc_delete', 'po_doc_cancel', 'po_payment_alloc_delete', 'po_payment_guard', 'qbo_job_skip', 'qbo_job_fail', 'qbo_job_unknown', 'qbo_job_unknown_list', 'qbo_bill_body')) = :'pre_md5_same')::text, 'true true');
select pg_temp.chk('S9c claim kinds: bill_payment · bill_payment_void 받는다 · EF SEND_KINDS 22 꼴로 고르면 wrong_kind(4-5b 전에는 안 나간다)',
  (pg_temp.svc(format($q$select to_jsonb(pg_temp.try($t$select (public.qbo_job_claim(1, array['bill_payment', 'bill_payment_void'], array[%L::uuid]))->'requested'->0->>'result'$t$))$q$, (select j.id from public.qbo_job j where j.ims_id = pg_temp.id('p2') and j.kind = 'bill_payment' and j.state = 'queued')))::text ~ 'claimed')::text || ' ' ||
  (pg_temp.svc(format($q$select to_jsonb(pg_temp.try($t$select (public.qbo_job_claim(15, array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void', 'cost_day', 'vendor', 'bill', 'vendor_credit'], array[%L::uuid]))->'requested'->0->>'result'$t$))$q$, (select j.id from public.qbo_job j where j.ims_id = pg_temp.id('p4') and j.kind = 'bill_payment')))::text ~ 'wrong_kind')::text, 'true true');
select pg_temp.chk('W1 WHERE 정적: 새 여섯 + 재발행 열하나 — 깊이 0 WHERE 없는 update · delete 0',
  (select string_agg(p.proname || ' ' || pg_temp.nowhere(p.prosrc)::text, ' · ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_bill_payment_fingerprint', 'qbo_bill_payment_body', 'qbo_bill_payment_void_body', 'qbo_bill_payment_sync', 'qbo_job_on_po_payment', 'qbo_bill_payment_backfill', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_retry', 'qbo_job_doc', 'qbo_job_list', 'qbo_job_on_po_doc_status', 'po_payment_alloc_guard', 'po_payment_create', 'po_payment_alloc_set', 'qbo_entity_upsert')),
  (select string_agg(p.proname || ' 0', ' · ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_bill_payment_fingerprint', 'qbo_bill_payment_body', 'qbo_bill_payment_void_body', 'qbo_bill_payment_sync', 'qbo_job_on_po_payment', 'qbo_bill_payment_backfill', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_retry', 'qbo_job_doc', 'qbo_job_list', 'qbo_job_on_po_doc_status', 'po_payment_alloc_guard', 'po_payment_create', 'po_payment_alloc_set', 'qbo_entity_upsert')));
select pg_temp.chk('G1 CHECK: qbo_job kind 25(bill_payment · bill_payment_void) · ims_kind 15(po_payment) · pair 명시 가지 둘 · qbo_txn kind po_payment · type BillPayment · pair po_payment→BillPayment · po_payment_exchange_rate_ck',
  (select (pg_get_constraintdef(oid) ~ 'bill_payment_void')::text from pg_constraint where conname = 'qbo_job_kind_ck') || ' ' || (select (pg_get_constraintdef(oid) ~ 'po_payment')::text from pg_constraint where conname = 'qbo_job_ims_kind_ck')
  || ' ' || (select (pg_get_constraintdef(oid) ~ $r$'bill_payment'::text THEN 'po_payment'$r$ and pg_get_constraintdef(oid) ~ $r$'bill_payment_void'::text THEN 'po_payment'$r$)::text from pg_constraint where conname = 'qbo_job_pair_ck')
  || ' ' || (select (pg_get_constraintdef(oid) ~ 'po_payment')::text from pg_constraint where conname = 'qbo_txn_kind_ck') || ' ' || (select (pg_get_constraintdef(oid) ~ 'BillPayment')::text from pg_constraint where conname = 'qbo_txn_type_ck')
  || ' ' || (select (pg_get_constraintdef(oid) ~ $r$'po_payment'::text THEN 'BillPayment'$r$)::text from pg_constraint where conname = 'qbo_txn_pair_ck') || ' ' || (select pg_get_constraintdef(oid) from pg_constraint where conname = 'po_payment_exchange_rate_ck'),
  'true true true true true true CHECK (((exchange_rate IS NULL) OR (exchange_rate > (0)::numeric)))');
select pg_temp.chk('G2 짝 제약 · CHECK 가 막는다: bill_payment + po_invoice 거부 · bill + po_payment 거부 · qbo_txn po_payment + Payment 거부 · exchange_rate 0 거부(P7 직접 update)',
  (pg_temp.try(format($q$insert into public.qbo_job (realm_id, kind, ims_kind, ims_id) values (%L, 'bill_payment', 'po_invoice', 'zz') returning id::text$q$, :'realm')) ~ 'qbo_job_pair_ck')::text
  || ' ' || (pg_temp.try(format($q$insert into public.qbo_job (realm_id, kind, ims_kind, ims_id) values (%L, 'bill', 'po_payment', 'zz') returning id::text$q$, :'realm')) ~ 'qbo_job_pair_ck')::text
  || ' ' || (pg_temp.try(format($q$insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id) values (%L, 'po_payment', 'zz', 'Payment', 'zz') returning id::text$q$, :'realm')) ~ 'qbo_txn_pair_ck')::text
  || ' ' || (pg_temp.try(format($q$update public.po_payment set exchange_rate = 0 where id = %L::uuid returning id::text$q$, pg_temp.id('p7'))) ~ 'po_payment_exchange_rate_ck')::text, 'true true true true');
select pg_temp.chk('G3 트리거 둘(po_payment_qbo · po_payment_alloc_qbo · deferrable initially deferred · 행마다) · 새 함수 여섯 grant 0 · po_payment_create ACL authenticated · service_role · 재발행 ACL 그대로',
  (select string_agg(t.tgname || ':' || c.relname || ':' || t.tgdeferrable::text || t.tginitdeferred::text, ',' order by t.tgname) from pg_trigger t join pg_class c on c.oid = t.tgrelid where t.tgname in ('po_payment_qbo', 'po_payment_alloc_qbo') and not t.tgisinternal) || ' | ' ||
  (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '(default)'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_bill_payment_fingerprint', 'qbo_bill_payment_body', 'qbo_bill_payment_void_body', 'qbo_bill_payment_sync', 'qbo_job_on_po_payment', 'qbo_bill_payment_backfill', 'po_payment_create', 'po_payment_alloc_set', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_doc', 'qbo_job_on_po_doc_status', 'po_payment_alloc_guard', 'qbo_entity_upsert')),
  'po_payment_alloc_qbo:po_payment_alloc:truetrue,po_payment_qbo:po_payment:truetrue | po_payment_alloc_guard:{postgres=X/postgres,service_role=X/postgres} po_payment_alloc_set:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} po_payment_create:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} qbo_bill_payment_backfill:{postgres=X/postgres} qbo_bill_payment_body:{postgres=X/postgres} qbo_bill_payment_fingerprint:{postgres=X/postgres} qbo_bill_payment_sync:{postgres=X/postgres} qbo_bill_payment_void_body:{postgres=X/postgres} qbo_entity_upsert:{postgres=X/postgres,authenticated=X/postgres} qbo_job_claim:{postgres=X/postgres,service_role=X/postgres} qbo_job_doc:{postgres=X/postgres} qbo_job_done:{postgres=X/postgres,service_role=X/postgres} qbo_job_list:{postgres=X/postgres,authenticated=X/postgres} qbo_job_on_po_doc_status:{postgres=X/postgres} qbo_job_on_po_payment:{postgres=X/postgres} qbo_job_preview:{postgres=X/postgres,authenticated=X/postgres} qbo_job_retry:{postgres=X/postgres,authenticated=X/postgres}');
select pg_temp.chk('G4 같은 이름 함수 수: po_payment_create 1(11 인자 · p_exchange_rate 맨 뒤) · po_payment_alloc_set 1 · 재발행 열하나 + 새 여섯 각 1 · 옛 10 인자 서명 없음',
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'po_payment_create')::text || ' ' || (select pg_get_function_identity_arguments(oid) ~ 'p_commit boolean, p_exchange_rate numeric$' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'po_payment_create')::text
  || ' ' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('po_payment_alloc_set', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_retry', 'qbo_job_doc', 'qbo_job_list', 'qbo_job_on_po_doc_status', 'po_payment_alloc_guard', 'qbo_entity_upsert', 'qbo_bill_payment_fingerprint', 'qbo_bill_payment_body', 'qbo_bill_payment_void_body', 'qbo_bill_payment_sync', 'qbo_job_on_po_payment', 'qbo_bill_payment_backfill'))::text
  || ' ' || (to_regprocedure('public.po_payment_create(uuid, date, numeric, uuid, numeric, uuid, text, text, jsonb, boolean)') is null)::text, '1 true 16 true');
select pg_temp.chk('G5 qbo_entity_upsert 몸에 Account AccountType · CurrencyRef(지시서 밖 재발행 — 4-5b pull 이 거울을 채우는 자리) · 거래 표 FK 0(qbo_job · qbo_txn → po_payment 없음)',
  (select (prosrc ~ $r$p_type = 'Account' and \(r \? 'AccountType' or r \? 'CurrencyRef'\)$r$)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_entity_upsert') || ' ' || (select count(*) from pg_constraint c where c.contype = 'f' and c.conrelid in ('public.qbo_job'::regclass, 'public.qbo_txn'::regclass) and c.confrelid = 'public.po_payment'::regclass)::text, 'true 0');
\if :{?mig}
select pg_temp.chk('S0b(시험 갈래) 재발행 열하나 md5 가 begin 앞과 다르다', ((select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_retry', 'qbo_job_doc', 'qbo_job_list', 'qbo_job_on_po_doc_status', 'po_payment_alloc_guard', 'po_payment_create', 'po_payment_alloc_set', 'qbo_entity_upsert')) <> :'pre_md5_11')::text, 'true');
select pg_temp.chk('S12(시험 갈래) 백필: 실제 결제 범위(since 뒤 · 붙임 ≥ 1) 4 건 모두 bill_payment 일감 queued · CAD 1 건 몸 = 거울 값 없음 글(Refresh list) · USD 3 건 몸 = 환율 없음 글(4-5b + Refresh · 환율 입력 뒤 풀린다)',
  (select count(*)::text || ' ' || count(*) filter (where j.state = 'queued')::text from public.qbo_job j join public.po_payment p on p.id::text = j.ims_id where j.kind = 'bill_payment' and p.reference not like 'ZZ45-%')
  || ' | ' || (select count(*) filter (where pg_temp.try(format($q$select public.qbo_bill_payment_body(%L::uuid)::text$q$, p.id)) ~ 'no account type or currency on file yet')::text || ' ' || count(*) filter (where pg_temp.try(format($q$select public.qbo_bill_payment_body(%L::uuid)::text$q$, p.id)) ~ 'has no exchange rate')::text
       from public.po_payment p join public.ref_currency c on c.id = p.currency_id where p.reference not like 'ZZ45-%' and public.qbo_po_since_ok(p.created_at) and exists (select 1 from public.po_payment_alloc a where a.po_payment_id = p.id) and c.code = 'CAD')
  || ' ' || (select count(*) filter (where pg_temp.try(format($q$select public.qbo_bill_payment_body(%L::uuid)::text$q$, p.id)) ~ 'has no exchange rate')::text
       from public.po_payment p join public.ref_currency c on c.id = p.currency_id where p.reference not like 'ZZ45-%' and public.qbo_po_since_ok(p.created_at) and exists (select 1 from public.po_payment_alloc a where a.po_payment_id = p.id) and c.code = 'USD'),
  :pre_real_pay_scope || ' ' || :pre_real_pay_scope || ' | 1 0 3');
select pg_temp.chk('S12b 백필 두 번째(멱등): queued 0 · seen 0', (select (public.qbo_bill_payment_backfill()->>'queued') || ' ' || (public.qbo_bill_payment_backfill()->>'seen')), '0 0');
\else
select pg_temp.chk('S0b(확인 갈래) 재발행 열하나 md5 = begin 앞(이미 적용)', ((select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_claim', 'qbo_job_done', 'qbo_job_preview', 'qbo_job_retry', 'qbo_job_doc', 'qbo_job_list', 'qbo_job_on_po_doc_status', 'po_payment_alloc_guard', 'po_payment_create', 'po_payment_alloc_set', 'qbo_entity_upsert')) = :'pre_md5_11')::text, 'true');
select pg_temp.chk('S12(확인 갈래) 백필(적용 때 돌았다): 실제 결제 범위마다 bill_payment 일감 또는 txn 이 있다 · 백필 다시 → queued 0',
  (select count(*) from public.po_payment p where p.reference not like 'ZZ45-%' and public.qbo_po_since_ok(p.created_at) and exists (select 1 from public.po_payment_alloc a where a.po_payment_id = p.id)
     and not exists (select 1 from public.qbo_job j where j.ims_kind = 'po_payment' and j.ims_id = p.id::text) and not exists (select 1 from public.qbo_txn t where t.ims_kind = 'po_payment' and t.ims_id = p.id::text))::text || ' ' || (public.qbo_bill_payment_backfill()->>'queued'), '0 0');
\endif
select pg_temp.chk('G6 실제 행 무변(트랜잭션 안): 공급처 +3 · 계좌 +5 · PO +2 · 인보이스 +10 · 비용 +1 · 결제 = 가짜 9(만든 12 − 지움 3) · 실제 qbo_txn 은 가짜만 늘었다(실제 ims_id 의 txn 수 = 기준)',
  ((select count(*) from public.supplier) - :pre_sup)::text || ' ' || ((select count(*) from public.ref_account) - :pre_acct)::text || ' ' || ((select count(*) from public.po) - :pre_po)::text || ' ' || ((select count(*) from public.po_invoice) - :pre_inv)::text || ' ' || ((select count(*) from public.po_charge) - :pre_chg)::text || ' ' || ((select count(*) from public.po_payment) - :pre_pay)::text
  || ' ' || ((select count(*) from public.qbo_txn t where t.qbo_id not like 'zz45%') = :pre_txn)::text, '3 5 2 10 1 9 true');

-- ── Z(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(상호 없음 · 가짜 행은 rollback) ──'
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, :EXPECT_OK as expect_ok from t_res;
select 'FAIL ' || label || format(' — got %s · want %s', coalesce(got, '(null)'), coalesce(want, '(null)')) as fail_line from t_res where not ok order by n;
select round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s;
rollback;
select (select count(*) from public.ims_staff) = :pre_staff and (select count(*) from public.supplier) = :pre_sup and (select count(*) from public.ref_account) = :pre_acct and (select count(*) from public.po) = :pre_po and (select count(*) from public.po_invoice) = :pre_inv and (select count(*) from public.po_charge) = :pre_chg
   and (select count(*) from public.po_payment) = :pre_pay and (select count(*) from public.po_payment_alloc) = :pre_alloc and (select count(*) from public.qbo_entity) = :pre_ent and (select count(*) from public.qbo_link) = :pre_link and (select count(*) from public.qbo_job) = :pre_jobs and (select count(*) from public.qbo_txn) = :pre_txn
   and not (:{?mig} and exists (select 1 from pg_constraint where conname = 'qbo_job_kind_ck' and pg_get_constraintdef(oid) like '%bill_payment%')) as rolled_back_clean;
