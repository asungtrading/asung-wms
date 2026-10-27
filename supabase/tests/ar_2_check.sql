-- supabase/tests/ar_2_check.sql — ar-2 컷오버 미수 · 받아 둔 돈 이월 검증 (2026-10-26 · 판정 775 · 783 ~ 786)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞 · 잠금 없음: 시퀀스 · 행 수) → begin → lock_timeout 3s → (-v mig 면 \i) → 가짜 재료 → 검증 → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027014202_ar_2_opening_carry_forward.sql -f supabase/tests/ar_2_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK 는 시험 = 확인 = EXPECT_OK(모든 검사가 적용 뒤 상태만 본다 · 두 갈래 없음)
--   쓰기: 가짜 직원 1 · 가짜 손님 4 + 묶음 90 · 이월 인보이스 3 + 묶음 320 · 이월 결제 2 + 묶음 · 일반 인보이스 1 · 결제 2 · 크레딧 1 — 전부 rollback · 번호 시퀀스는 당기지 않는다(옛 번호 · 명시 번호)
\set ON_ERROR_STOP on
\set EXPECT_OK 66
\pset pager off
-- 기준(begin 앞 · 잠금 없음)
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
select (select count(*) from public.so_invoice) as n_inv, (select count(*) from public.so_payment) as n_pay, (select count(*) from public.so_payment_alloc) as n_alloc,
       (select count(*) from public.customer) as n_cust, (select count(*) from public.ims_staff) as n_staff, (select count(*) from public.so_credit) as n_cred,
       (select count(*) from public.mail_outbox) as n_mail, (select count(*) from public.doc_mail_skip) as n_skip, (select count(*) from public.drive_job) as n_drive,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_opening_load') as n_fn0 \gset
\echo '── 기준: so_invoice' :n_inv '· so_payment' :n_pay '· alloc' :n_alloc '· customer' :n_cust '· staff' :n_staff '· credit' :n_cred '· mail' :n_mail '· skip' :n_skip '· drive' :n_drive '· inv seq' :inv_seq_last :inv_seq_called '· so_opening_load in pg_proc' :n_fn0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.chkb(p_name text, p_ok boolean, p_note text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, coalesce(p_ok, false), coalesce(p_ok::text, 'null'), p_note);
$$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language plpgsql as $$
begin
  if p is null or left(p, 1) not in ('[', '{') then return null; end if;
  return p::jsonb;
end $$;
create temp table t_fx (k text primary key, v text);
create function pg_temp.fx(p text) returns text language sql stable as $$ select v from t_fx where k = p $$;
create function pg_temp.fxu(p text) returns uuid language sql stable as $$ select v::uuid from t_fx where k = p $$;
-- service_role 로 창구 부르기(REST 와 같은 역할 · 끝나면 되돌린다)
create function pg_temp.load(p jsonb, p_dry boolean) returns jsonb language plpgsql as $$
declare v jsonb; v_claims text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
  v := public.so_opening_load(p, p_dry);
  execute 'reset role';
  perform set_config('request.jwt.claims', v_claims, true);
  return v;
end $$;

-- ── F) 꼴: 칸 · CHECK · 색인 · 창구 · 뷰 ──
select pg_temp.chk('F1 so_invoice columns kind · prior_settled · store_customer_id · legacy_sale_id · legacy_invoice_id', (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'so_invoice' and column_name in ('kind', 'prior_settled', 'store_customer_id', 'legacy_sale_id', 'legacy_invoice_id')), '5');
select pg_temp.chk('F2 so_invoice CHECK kind · prior_settled · opening shape + old four kept', (select count(*)::text from pg_constraint where conrelid = 'public.so_invoice'::regclass and conname in ('so_invoice_kind_ck', 'so_invoice_prior_settled_ck', 'so_invoice_opening_ck', 'so_invoice_total_ck', 'so_invoice_taxable_ck', 'so_invoice_due_ck', 'so_invoice_number_ck')), '7');
select pg_temp.chk('F3 indexes legacy_invoice_uq · legacy_sale · store_customer · number_norm · payment_opening_uq', (select count(*)::text from pg_indexes where schemaname = 'public' and indexname in ('so_invoice_legacy_invoice_uq', 'so_invoice_legacy_sale_idx', 'so_invoice_store_customer_idx', 'so_invoice_number_norm_idx', 'so_payment_opening_uq')), '5');
select pg_temp.chkb('F4 so_payment_method_ck has opening · so_payment_add body does not', (select pg_get_constraintdef(oid) like '%''opening''%' from pg_constraint where conname = 'so_payment_method_ck') and (select prosrc not like '%''opening''%' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_add'), 'CHECK yes · human window no');
select pg_temp.chkb('F5 so_opening_load definer · service_role only', (select p.prosecdef from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_opening_load') and has_function_privilege('service_role', 'public.so_opening_load(jsonb, boolean)', 'execute') and not has_function_privilege('authenticated', 'public.so_opening_load(jsonb, boolean)', 'execute') and not has_function_privilege('anon', 'public.so_opening_load(jsonb, boolean)', 'execute'), 'definer · service_role yes · authenticated/anon no');
select pg_temp.chk('F6 so_invoice_list new columns six · security_invoker', (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'so_invoice_list' and column_name in ('kind', 'prior_settled', 'store_customer_id', 'store_name', 'legacy_sale_id', 'legacy_invoice_id')) || ' ' || (select (reloptions::text like '%security_invoker=true%')::text from pg_class where relname = 'so_invoice_list' and relnamespace = 'public'::regnamespace), '6 true');
select pg_temp.chkb('F7 so_invoice_remaining subtracts prior_settled · five re-issued bodies carry the added line', (select prosrc like '%i.total - i.prior_settled - coalesce(%' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_invoice_remaining')
  and (select prosrc like '%if new.kind = ''opening'' then return null; end if;%' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_auto_invoice')
  and (select prosrc like '%= ''opening'' then return null; end if;%' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'drive_archive_on_issue')
  and (select prosrc like '%cannot be cancelled%' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_invoice_cancel')
  and (select prosrc like '%it cannot be voided%' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_void')
  and (select prosrc like '%the original is in QuickBooks%' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_data_invoice'), 'six bodies');
select pg_temp.chk('F8 remaining formula census — functions/views with an inline total − alloc sum (must be only so_invoice_remaining)', (select string_agg(proname, ',' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and prosrc ~ 'total\s*-\s*(i\.prior_settled\s*-\s*)?coalesce\(\(select sum\(a\.amount\) from public\.so_payment_alloc'), 'so_invoice_remaining');
select pg_temp.chk('F10 old behaviour byte-identical: each re-issued body minus its ar-2 line(s) = original md5 (remaining · mail trigger · drive trigger · cancel · void · doc_data_invoice)',
  (select string_agg(ok::text, ' ' order by nm) from (values
    ('1remaining', md5(regexp_replace(replace((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_invoice_remaining'), 'i.total - i.prior_settled - coalesce(', 'i.total - coalesce('), ' · ar-2 판정 783[^\n]*', '')) = 'f9555d3c9f4b3b4745d5ceb67b5d92b5'),
    ('2mail', md5(regexp_replace((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_auto_invoice'), '[^\n]*ar-2 판정[^\n]*\n', '', 'g')) = '949df77673430c07974d9ab691fb7b16'),
    ('3drive', md5(regexp_replace((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'drive_archive_on_issue'), '[^\n]*ar-2 판정[^\n]*\n', '', 'g')) = '95086bef30c6c8e53c0186e6a5242414'),
    ('4cancel', md5(regexp_replace((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_invoice_cancel'), '[^\n]*ar-2 판정[^\n]*\n', '', 'g')) = '9107f7f408613ed6ac8d4c84217c25f7'),
    ('5void', md5(regexp_replace((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_payment_void'), '[^\n]*ar-2 판정[^\n]*\n', '', 'g')) = '82accf2f64856d5aabc798d818845ba6'),
    ('6docdata', md5(regexp_replace((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_data_invoice'), '[^\n]*ar-2 판정[^\n]*\n', '', 'g')) = '1ba3b5148de65436aae947af78b15736')
  ) v(nm, ok)), 'true true true true true true');
select pg_temp.chk('F9 account _1150040009_ active in ref_account (판정 786)', (select (count(*) = 1)::text from public.ref_account a where a.code = '_1150040009_' and a.is_active), 'true');

-- ── M0) 가짜 재료: 직원 S(manager · sales) · 손님 HQ(청구처 · 메일 켬 · 연락처) · STORE(청구처 = HQ) · USDC(USD · Edmonton) · NOBR(브랜치 없음) · 메일 트리거를 문장 끝에 ──
\echo '── M0 재료'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'ar2-s@test.invalid', 'AR2 S', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as s_uid, id::text as s_id \gset
\set s '{"sub":"' :s_uid '","role":"authenticated"}'
select set_config('request.jwt.claims', :'s', true) as staff_claims_set \gset
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as usd from public.ref_currency where code = 'USD' \gset
select id::text as tor, name as tor_name from public.ref_warehouse where is_active and name not ilike '%edmonton%' order by name limit 1 \gset
select id::text as edm, name as edm_name from public.ref_warehouse where is_active and name ilike '%edmonton%' order by name limit 1 \gset
select id::text as pt30, name as pt30_name, net_days as pt30_days from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
select public.ims_today() as today \gset
select id::text as bank from public.ref_account where is_active and account_type = 'BANK' order by code limit 1 \gset
set local session_replication_role = replica;
insert into public.customer (name, source, cin7_id, currency_id, currency_code, default_location_id, default_location_name, payment_term_id, payment_term_name, final_invoice_mail)
  values ('AR2 HQ (bill-to)', 'manual', gen_random_uuid(), :'cad'::uuid, 'CAD', :'tor'::uuid, :'tor_name', :'pt30'::uuid, :'pt30_name', true) returning id::text as hq, cin7_id::text as hq_c7 \gset
insert into public.customer (name, source, cin7_id, currency_id, currency_code, default_location_id, default_location_name, payment_term_id, payment_term_name, default_bill_to_customer_id)
  values ('AR2 Store (child)', 'manual', gen_random_uuid(), :'cad'::uuid, 'CAD', :'tor'::uuid, :'tor_name', :'pt30'::uuid, :'pt30_name', :'hq'::uuid) returning id::text as st, cin7_id::text as st_c7 \gset
insert into public.customer (name, source, cin7_id, currency_id, currency_code, default_location_id, default_location_name)
  values ('AR2 USD customer', 'manual', gen_random_uuid(), :'usd'::uuid, 'USD', :'edm'::uuid, :'edm_name') returning id::text as uc, cin7_id::text as uc_c7 \gset
insert into public.customer (name, source, cin7_id, currency_id, currency_code)
  values ('AR2 No-branch customer', 'manual', gen_random_uuid(), :'cad'::uuid, 'CAD') returning id::text as nb, cin7_id::text as nb_c7 \gset
insert into public.customer_contact (customer_id, source, is_active, is_default, include_in_email, name, email) values (:'hq'::uuid, 'manual', true, true, true, 'AR2 AP', 'ar2-hq@test.invalid');
set local session_replication_role = origin;
set constraints all immediate;
insert into t_fx values ('hq', :'hq'), ('hq_c7', :'hq_c7'), ('st', :'st'), ('st_c7', :'st_c7'), ('uc', :'uc'), ('uc_c7', :'uc_c7'), ('nb', :'nb'), ('nb_c7', :'nb_c7'), ('cad', :'cad'), ('usd', :'usd'), ('tor', :'tor'), ('pt30_name', :'pt30_name'), ('today', :'today'), ('ghost_c7', gen_random_uuid()::text);
select pg_temp.chkb('M0 staff · HQ(bill-to · mail on · contact) · STORE(bill-to HQ) · USDC · NOBR · terms ' || :'pt30_name', :'s_uid' <> '' and :'hq' <> '' and :'st' <> '' and :'uc' <> '' and :'nb' <> '' and :'pt30' <> '' and :'edm' <> '', 'see M0');

-- 입력 만들기 — variant: base · b_changed(B 합계 1001.00 · HQ 받아 둔 돈 35.00) · a_changed(A 합계 700.00 · HQ 40.00)
create function pg_temp.inp(p_variant text) returns jsonb language sql stable as $$
  select jsonb_build_object('as_of', pg_temp.fx('today'), 'complete', true,
    'invoices', jsonb_build_array(
      jsonb_build_object('legacy_sale_id', 'sale-A', 'legacy_invoice_id', 'task-A', 'invoice_number', '79901', 'cin7_customer_id', pg_temp.fx('st_c7'), 'issued_on', (pg_temp.fx('today')::date - 40)::text, 'payment_term_name', pg_temp.fx('pt30_name'), 'currency', 'CAD',
                         'total_before_tax', case when p_variant = 'a_changed' then 630.21 else 536.92 end, 'tax', 69.79, 'total', case when p_variant = 'a_changed' then 700.00 else 606.71 end, 'prior_settled', 5.44),
      jsonb_build_object('legacy_sale_id', 'sale-B', 'legacy_invoice_id', 'task-B', 'invoice_number', '79902', 'cin7_customer_id', pg_temp.fx('hq_c7'), 'issued_on', (pg_temp.fx('today')::date - 5)::text, 'due_on', (pg_temp.fx('today')::date + 25)::text, 'payment_term_name', pg_temp.fx('pt30_name'), 'currency', 'cad',
                         'total_before_tax', case when p_variant in ('b_changed', 'a_changed') then 885.96 else 884.95 end, 'tax', 115.04, 'total', case when p_variant in ('b_changed', 'a_changed') then 1001.00 else 1000.00 end),
      jsonb_build_object('legacy_sale_id', 'sale-C', 'legacy_invoice_id', 'task-C', 'invoice_number', '79903', 'cin7_customer_id', pg_temp.fx('uc_c7'), 'issued_on', (pg_temp.fx('today')::date - 3)::text, 'payment_term_name', 'AR2 unknown term', 'currency', 'USD',
                         'total_before_tax', 2925.53, 'tax', 0, 'total', 2925.53, 'prior_settled', 0),
      jsonb_build_object('legacy_sale_id', 'sale-D', 'legacy_invoice_id', 'task-D', 'invoice_number', '79904', 'cin7_customer_id', pg_temp.fx('ghost_c7'), 'issued_on', pg_temp.fx('today'), 'currency', 'CAD', 'total_before_tax', 10, 'tax', 0, 'total', 10)),
    'credits', jsonb_build_array(
      jsonb_build_object('cin7_customer_id', pg_temp.fx('st_c7'), 'currency', 'CAD', 'amount', 25.00, 'source', 'credit', 'reference', 'Credit for sale SO-00001'),
      jsonb_build_object('cin7_customer_id', pg_temp.fx('st_c7'), 'currency', 'CAD', 'amount', case when p_variant = 'b_changed' then 10.00 when p_variant = 'a_changed' then 15.00 else 5.00 end, 'source', 'overpay', 'reference', 'Overpaid from Invoice #40000'),
      jsonb_build_object('cin7_customer_id', pg_temp.fx('uc_c7'), 'currency', 'USD', 'amount', 72.29, 'source', 'credit', 'reference', 'Return to credit for CR-00688'),
      jsonb_build_object('cin7_customer_id', pg_temp.fx('nb_c7'), 'currency', 'CAD', 'amount', 10.00, 'source', 'credit', 'reference', 'no branch'),
      jsonb_build_object('cin7_customer_id', pg_temp.fx('ghost_c7'), 'currency', 'CAD', 'amount', 1.00, 'source', 'credit', 'reference', 'ghost')));
$$;

-- ── M1) Dry — 같은 판단 · 쓰기 0 ──
\echo '── M1 Dry'
select pg_temp.load(pg_temp.inp('base'), true) as dry1 \gset
select pg_temp.chk('M1a dry: invoices in 4 · inserted 3 · rejected 1(customer_unresolved) · credits groups 3 · inserted 2 · rejected 2', (:'dry1'::jsonb->>'dry') || ' ' || (:'dry1'::jsonb#>>'{invoices,in}') || ' ' || (:'dry1'::jsonb#>>'{invoices,inserted}') || ' ' || (:'dry1'::jsonb#>>'{invoices,rejected}') || ' ' || (:'dry1'::jsonb#>>'{invoices,rejects,0,reason}') || ' ' || (:'dry1'::jsonb#>>'{credits,groups}') || ' ' || (:'dry1'::jsonb#>>'{credits,inserted}') || ' ' || (:'dry1'::jsonb#>>'{credits,rejected}'), 'true 4 3 1 customer_unresolved 3 2 2');
select pg_temp.chk('M1b dry wrote nothing: so_invoice · so_payment counts unchanged', (select count(*) from public.so_invoice)::text || ' ' || (select count(*) from public.so_payment)::text, :'n_inv' || ' ' || :'n_pay');
select pg_temp.chk('M1c dry: existing_not_in_input (complete) = 0 · account _1150040009_', (:'dry1'::jsonb#>>'{invoices,existing_not_in_input,count}') || ' ' || (:'dry1'::jsonb#>>'{credits,existing_not_in_input,count}') || ' ' || (:'dry1'::jsonb#>>'{account,code}'), '0 0 _1150040009_');

-- ── M2) Apply ──
\echo '── M2 Apply'
select pg_temp.load(pg_temp.inp('base'), false) as ap1 \gset
select pg_temp.chk('M2a apply: inserted 3 · updated 0 · same 0 · rejected 1 · credits inserted 2 · same 0 · rejected 2(rows 1 customer_unresolved + group 1 branch_unresolved)',
  (:'ap1'::jsonb#>>'{invoices,inserted}') || ' ' || (:'ap1'::jsonb#>>'{invoices,updated}') || ' ' || (:'ap1'::jsonb#>>'{invoices,same}') || ' ' || (:'ap1'::jsonb#>>'{invoices,rejected}') || ' ' || (:'ap1'::jsonb#>>'{credits,inserted}') || ' ' || (:'ap1'::jsonb#>>'{credits,same}') || ' ' || (:'ap1'::jsonb#>>'{credits,rejected}') || ' ' || (:'ap1'::jsonb#>>'{credits,customer_unresolved}') || ' ' || (:'ap1'::jsonb#>>'{credits,branch_unresolved}'), '3 0 0 1 2 0 2 1 1');
select pg_temp.chk('M2b by_currency invoices CAD 2 · 1606.71 · prior 5.44 · remaining 1601.27 / USD 1 · 2925.53', (select string_agg(format('%s %s %s %s %s', e->>'currency_code', e->>'count', e->>'total', e->>'prior_settled', e->>'remaining'), ' / ' order by e->>'currency_code') from jsonb_array_elements(:'ap1'::jsonb#>'{invoices,by_currency}') e), 'CAD 2 1606.71 5.44 1601.27 / USD 1 2925.53 0 2925.53');
select pg_temp.chk('M2c by_currency credits CAD 1 group 30.00 / USD 1 group 72.29', (select string_agg(format('%s %s %s', e->>'currency_code', e->>'count', e->>'amount'), ' / ' order by e->>'currency_code') from jsonb_array_elements(:'ap1'::jsonb#>'{credits,by_currency}') e), 'CAD 1 30.00 / USD 1 72.29');
select pg_temp.chk('M2d before_tax_adjusted 1 (0.01) · term_unresolved 1 · due_unknown 1', (:'ap1'::jsonb#>>'{invoices,before_tax_adjusted,count}') || ' ' || (:'ap1'::jsonb#>>'{invoices,before_tax_adjusted,sum_abs}') || ' ' || (:'ap1'::jsonb#>>'{invoices,term_unresolved}') || ' ' || (:'ap1'::jsonb#>>'{invoices,due_unknown}'), '1 0.01 1 1');
select id::text as ia from public.so_invoice where invoice_number = '79901' \gset
select id::text as ib from public.so_invoice where invoice_number = '79902' \gset
select id::text as ic from public.so_invoice where invoice_number = '79903' \gset
select id::text as phq from public.so_payment where method = 'opening' and customer_id = :'hq'::uuid \gset
select id::text as pusd from public.so_payment where method = 'opening' and customer_id = :'uc'::uuid \gset
insert into t_fx values ('ia', :'ia'), ('ib', :'ib'), ('ic', :'ic'), ('phq', :'phq'), ('pusd', :'pusd');
select pg_temp.chk('M2e rows: A kind opening · store STORE · bill-to HQ · prior 5.44 · lines 536.92 · tax 69.79 · total 606.71 · amount_due 606.71 · bf null · issued_by null · due issued+30 · legacy keys',
  (select format('%s %s %s %s %s %s %s %s %s %s %s %s %s', i.kind, (i.store_customer_id = :'st'::uuid)::text, (i.bill_to_customer_id = :'hq'::uuid)::text, i.prior_settled, i.lines_amount, i.tax_amount, i.total, i.amount_due, (i.balance_forward is null)::text, (i.issued_by is null)::text, (i.due_on = i.issued_on + :pt30_days)::text, i.legacy_sale_id, i.legacy_invoice_id) from public.so_invoice i where i.id = :'ia'::uuid),
  format('opening true true 5.44 536.92 69.79 606.71 606.71 true true true sale-A task-A'));
select pg_temp.chk('M2f rows: B lines = total − tax (884.96 · not 884.95) · C due null · term name kept · USD · bill-to self', (select format('%s %s', i.lines_amount, (i.payment_term_id is not null)::text) from public.so_invoice i where i.id = :'ib'::uuid) || ' / ' || (select format('%s %s %s %s', (i.due_on is null)::text, i.payment_term_name, i.currency_code, (i.bill_to_customer_id = :'uc'::uuid)::text) from public.so_invoice i where i.id = :'ic'::uuid), '884.96 true / true AR2 unknown term USD true');
select pg_temp.chk('M2g opening payment HQ: kind payment · method opening · 30.00 · paid_on as_of · account _1150040009_ · branch from store · note carries both sources · created_by null', (select format('%s %s %s %s %s %s %s %s', p.kind, p.method, p.amount, (p.paid_on = :'today'::date)::text, p.account_code, (p.warehouse_id = :'tor'::uuid)::text, (p.note like '%credit 25.00 — Credit for sale SO-00001%' and p.note like '%overpay 5.00 — Overpaid from Invoice #40000%')::text, (p.created_by is null)::text) from public.so_payment p where p.id = :'phq'::uuid), 'payment opening 30.00 true _1150040009_ true true true');
select pg_temp.chk('M2h opening payment USDC: 72.29 USD · Edmonton branch', (select format('%s %s %s', p.amount, p.currency_code, (p.warehouse_id = :'edm'::uuid)::text) from public.so_payment p where p.id = :'pusd'::uuid), '72.29 USD true');
select pg_temp.chk('M2i no opening payment under STORE (money sits with the bill-to)', (select count(*)::text from public.so_payment p where p.customer_id = :'st'::uuid), '0');

-- ── M3) 식은 한 곳 — 남은 금액(함수 · 목록 · 잔액 · 연체 · 제안 · 미수 요약 · 상세)이 같은 숫자 ──
\echo '── M3 식은 한 곳'
select pg_temp.chk('M3a so_invoice_remaining A 601.27 · B 1000.00 · C 2925.53', public.so_invoice_remaining(:'ia'::uuid)::text || ' ' || public.so_invoice_remaining(:'ib'::uuid)::text || ' ' || public.so_invoice_remaining(:'ic'::uuid)::text, '601.27 1000.00 2925.53');
select pg_temp.chk('M3b so_invoice_list A: remaining 601.27 · overdue >0 · open · kind · prior · store_name · legacy', (select format('%s %s %s %s %s %s %s %s', l.remaining, (l.days_overdue > 0)::text, l.is_open::text, l.kind, l.prior_settled, l.store_name, l.legacy_sale_id, l.legacy_invoice_id) from public.so_invoice_list l where l.id = :'ia'::uuid), '601.27 true true opening 5.44 AR2 Store (child) sale-A task-A');
select pg_temp.chk('M3c so_invoice_list B not overdue · C due_unknown · paid 0 · credited 0', (select format('%s %s', l.days_overdue, l.paid) from public.so_invoice_list l where l.id = :'ib'::uuid) || ' / ' || (select format('%s %s %s', l.due_unknown::text, l.days_overdue, l.credited) from public.so_invoice_list l where l.id = :'ic'::uuid), '0 0 / true 0 0');
select pg_temp.chk('M3d so_customer_balance(HQ) CAD: received 30.00 · available 30.00 · open 2 · due 1601.27 · one currency row', (select format('%s %s %s %s %s', b.received, b.available, b.open_invoices, b.open_invoices_due, (select count(*) from public.so_customer_balance(:'hq'::uuid))) from public.so_customer_balance(:'hq'::uuid) b where b.currency_code = 'CAD'), '30.00 30.00 2 1601.27 1');
select pg_temp.chk('M3e so_customer_balance(USDC) USD: received 72.29 · open 1 · due 2925.53 / STORE: no rows', (select format('%s %s %s', b.received, b.open_invoices, b.open_invoices_due) from public.so_customer_balance(:'uc'::uuid) b where b.currency_code = 'USD') || ' / ' || (select count(*) from public.so_customer_balance(:'st'::uuid))::text, '72.29 1 2925.53 / 0');
select public.so_customer_overdue(:'st'::uuid) as ov_st \gset
select pg_temp.chk('M3f so_customer_overdue(STORE): bill-to HQ · differs · count 1 · 601.27 · invoice 79901 · available CAD 30.00', format('%s %s %s %s %s %s %s', ((:'ov_st'::jsonb->>'bill_to_customer_id') = :'hq')::text, :'ov_st'::jsonb->>'bill_to_differs', :'ov_st'::jsonb->>'count', :'ov_st'::jsonb#>>'{by_currency,0,amount}', :'ov_st'::jsonb#>>'{invoices,0,invoice_number}', :'ov_st'::jsonb#>>'{available,0,currency_code}', :'ov_st'::jsonb#>>'{available,0,available}'), 'true true 1 601.27 79901 CAD 30.00');
select pg_temp.chk('M3g so_customer_overdue(HQ) count 1 · (USDC) count 0 (due unknown is not overdue)', (public.so_customer_overdue(:'hq'::uuid)->>'count') || ' ' || (public.so_customer_overdue(:'uc'::uuid)->>'count'), '1 0');
select public.so_payment_propose(:'hq'::uuid, 2000, :'cad'::uuid) as prop \gset
select pg_temp.chk('M3h so_payment_propose(HQ 2000 CAD): A first(due earliest) 601.27 then B 1000.00 · allocated 1601.27 · leftover 398.73', format('%s %s %s %s %s %s', :'prop'::jsonb#>>'{proposed,0,invoice_number}', :'prop'::jsonb#>>'{proposed,0,suggested}', :'prop'::jsonb#>>'{proposed,1,invoice_number}', :'prop'::jsonb#>>'{proposed,1,suggested}', :'prop'::jsonb->>'allocated', :'prop'::jsonb->>'leftover'), '79901 601.27 79902 1000.00 1601.27 398.73');
select pg_temp.chk('M3i so_invoice_ar_summary(HQ) CAD: open 2 · remaining 1601.27 · overdue 1 · 601.27', (select format('%s %s %s %s', c->>'open_count', c->>'remaining_total', c->>'overdue_count', c->>'overdue_total') from jsonb_array_elements(public.so_invoice_ar_summary(:'hq'::uuid)->'currencies') c where c->>'currency_code' = 'CAD'), '2 1601.27 1 601.27');
select pg_temp.chk('M3j so_invoice_detail(A): invoice.kind opening · prior_settled · store_name · orders [] · lines [] · customer_balance.available 30.00', (select format('%s %s %s %s %s %s', d#>>'{invoice,kind}', d#>>'{invoice,prior_settled}', d#>>'{invoice,store_name}', jsonb_array_length(d->'orders'), jsonb_array_length(d->'lines'), d#>>'{customer_balance,available}') from public.so_invoice_detail(:'ia'::uuid) d), 'opening 5.44 AR2 Store (child) 0 0 30.00');
select pg_temp.chk('M3k next issue consumes the opening money — so_invoice_apply_plan(HQ CAD 500) balance 30.00 step auto_balance method opening / (USDC USD 50) 50 / (HQ USD 100) 0 (same currency only)',
  (select format('%s %s %s', j->>'balance', j#>>'{steps,0,step}', j#>>'{steps,0,method}') from public.so_invoice_apply_plan(:'hq'::uuid, :'cad'::uuid, '{}'::uuid[], 500) j) || ' / ' || (public.so_invoice_apply_plan(:'uc'::uuid, :'usd'::uuid, '{}'::uuid[], 50)->>'balance') || ' / ' || (public.so_invoice_apply_plan(:'hq'::uuid, :'usd'::uuid, '{}'::uuid[], 100)->>'balance'), '30.00 auto_balance opening / 50 / 0');

-- ── M4) 트리거 둘 — 이월 insert 뒤 메일 큐 · 드라이브 일 0 · 일반 인보이스는 그대로 생긴다 ──
\echo '── M4 트리거'
select (select count(*) from public.mail_outbox where created_at = now()) + (select count(*) from public.doc_mail_skip where created_at = now()) as m_after_open, (select count(*) from public.drive_job where created_at = now()) as d_after_open \gset
select pg_temp.chk('M4a after opening load: mail rows (outbox + skip) this txn 0 · drive_job 0', :'m_after_open' || ' ' || :'d_after_open', '0 0');
insert into public.so_invoice (invoice_number, bill_to_customer_id, bill_to_name, issued_on, issued_by, currency_id, currency_code, due_on)
  values ('79999', :'hq'::uuid, 'AR2 HQ (bill-to)', :'today'::date, :'s_id'::uuid, :'cad'::uuid, 'CAD', :'today'::date + 30) returning id::text as inrm \gset
select (select count(*) from public.mail_outbox where created_at = now()) + (select count(*) from public.doc_mail_skip where created_at = now()) as m_after_norm, (select count(*) from public.drive_job where created_at = now()) as d_after_norm \gset
select pg_temp.chkb('M4b a normal (sale) invoice insert still queues mail (' || :'m_after_norm' || ' row) — old behaviour unchanged · drive job ' || :'d_after_norm' || ' (drive_since_ok(today) = ' || public.drive_since_ok(:'today'::date)::text || ' — the Drive start date decides, not ar-2 · F10 proves the sale path byte-identical)', :'m_after_norm'::int >= 1 and (:'d_after_norm'::int >= 1 or not public.drive_since_ok(:'today'::date)), 'mail >= 1 · drive per start date');
select pg_temp.chk('M4c nothing in doc_mail_skip · drive_job refers to the three opening invoices', (select count(*) from public.doc_mail_skip k where k.ref->>'invoice_id' in (:'ia', :'ib', :'ic'))::text || ' ' || (select count(*) from public.drive_job d where d.doc_ref->>'invoice_id' in (:'ia', :'ib', :'ic'))::text, '0 0');
select pg_temp.chk('M4d the normal invoice is kind sale · prior 0 · HQ open stays 2 (its total is 0 so it is not open)', (select format('%s %s', i.kind, i.prior_settled) from public.so_invoice i where i.id = :'inrm'::uuid) || ' ' || (select b.open_invoices::text from public.so_customer_balance(:'hq'::uuid) b where b.currency_code = 'CAD'), 'sale 0 2');

-- ── M5) 다시 돌리기 — 같음 · Dry 바뀜은 쓰기 0 · Apply 바뀜 ──
\echo '── M5 다시 돌리기'
select pg_temp.load(pg_temp.inp('base'), false) as ap2 \gset
select pg_temp.chk('M5a same input again: invoices same 3 · inserted 0 · updated 0 · credits same 2 · inserted 0', format('%s %s %s %s %s', :'ap2'::jsonb#>>'{invoices,same}', :'ap2'::jsonb#>>'{invoices,inserted}', :'ap2'::jsonb#>>'{invoices,updated}', :'ap2'::jsonb#>>'{credits,same}', :'ap2'::jsonb#>>'{credits,inserted}'), '3 0 0 2 0');
select pg_temp.chk('M5b row counts after re-run unchanged (3 opening + 1 normal · 2 opening payments)', (select count(*) from public.so_invoice where kind = 'opening')::text || ' ' || (select count(*) from public.so_payment where method = 'opening')::text, '3 2');
select pg_temp.load(pg_temp.inp('b_changed'), true) as dry2 \gset
select pg_temp.chk('M5c dry with B 1001.00 · HQ 35.00: planned updated 1 + same 2 · credits updated 1 same 1 · DB still 1000.00 / 30.00', format('%s %s %s %s %s %s', :'dry2'::jsonb#>>'{invoices,updated}', :'dry2'::jsonb#>>'{invoices,same}', :'dry2'::jsonb#>>'{credits,updated}', :'dry2'::jsonb#>>'{credits,same}', public.so_invoice_remaining(:'ib'::uuid), (select p.amount from public.so_payment p where p.id = :'phq'::uuid)), '1 2 1 1 1000.00 30.00');
select pg_temp.load(pg_temp.inp('b_changed'), false) as ap3 \gset
select pg_temp.chk('M5d apply B 1001.00 · HQ 35.00: updated 1 · credits updated 1 · remaining(B) 1001.00 · lines 885.96 · available 35.00 · same payment id (no new row)', format('%s %s %s %s %s %s', :'ap3'::jsonb#>>'{invoices,updated}', :'ap3'::jsonb#>>'{credits,updated}', public.so_invoice_remaining(:'ib'::uuid), (select i.lines_amount from public.so_invoice i where i.id = :'ib'::uuid), (select b.available from public.so_customer_balance(:'hq'::uuid) b where b.currency_code = 'CAD'), (select count(*) from public.so_payment where method = 'opening' and customer_id = :'hq'::uuid)), '1 1 1001.00 885.96 35.00 1');

-- ── M6) IMS 붙임 — 결제 붙이기 → 남은 금액 감소 · 그 뒤 바뀐 적재는 거부 ──
\echo '── M6 IMS 붙임'
select public.so_payment_add(jsonb_build_object('customer_id', :'hq', 'amount', 100, 'method', 'cheque', 'currency_code', 'CAD', 'warehouse_id', :'tor', 'account_id', :'bank', 'reference', 'AR2 chq 1', 'allocations', jsonb_build_array(jsonb_build_object('invoice_id', :'ia', 'amount', 100)))) as pay1 \gset
select pg_temp.chk('M6a staff payment 100 on A: remaining(A) 501.27 · list.paid 100 · list.remaining same', format('%s %s %s', public.so_invoice_remaining(:'ia'::uuid), (select l.paid from public.so_invoice_list l where l.id = :'ia'::uuid), (select l.remaining from public.so_invoice_list l where l.id = :'ia'::uuid)), '501.27 100 501.27');
select public.so_payment_attach(:'phq'::uuid, jsonb_build_array(jsonb_build_object('invoice_id', :'ib', 'amount', 10))) as att1 \gset
select pg_temp.chk('M6b opening money attached by hand 10 on B: remaining(B) 991.00 · HQ available 25.00 · apply_plan balance 25.00', format('%s %s %s', public.so_invoice_remaining(:'ib'::uuid), (select b.available from public.so_customer_balance(:'hq'::uuid) b where b.currency_code = 'CAD'), public.so_invoice_apply_plan(:'hq'::uuid, :'cad'::uuid, '{}'::uuid[], 500)->>'balance'), '991.00 25.00 25.00');
select pg_temp.load(pg_temp.inp('a_changed'), false) as ap4 \gset
select pg_temp.chk('M6c re-run with A 700.00 · HQ 40.00 after IMS allocations: A rejected has_ims_allocations · B same · C same · HQ credit rejected has_ims_allocations · USD same · DB unchanged',
  format('%s %s %s %s %s %s %s', (select e->>'reason' from jsonb_array_elements(:'ap4'::jsonb#>'{invoices,rejects}') e where e->>'invoice_number' = '79901'), :'ap4'::jsonb#>>'{invoices,same}', :'ap4'::jsonb#>>'{invoices,rejected}',
         (select e->>'reason' from jsonb_array_elements(:'ap4'::jsonb#>'{credits,rejects}') e where e->>'currency_code' = 'CAD' and e->>'amount' = '40.00'), :'ap4'::jsonb#>>'{credits,same}', public.so_invoice_remaining(:'ia'::uuid), (select p.amount from public.so_payment p where p.id = :'phq'::uuid)), 'has_ims_allocations 2 2 has_ims_allocations 1 501.27 35.00');

-- ── M7) 거부 — 취소(784) · void · 인쇄 · 메일(785) · 일반 인보이스는 옛 동작 ──
\echo '── M7 거부'
select pg_temp.chkb('M7a so_invoice_cancel(A) refused: cannot be cancelled', pg_temp.run(format('select public.so_invoice_cancel(%L, %L)::text', :'ia', 'ar2 test')) like 'ERR P0001:%cannot be cancelled%', 'ERR cannot be cancelled');
select pg_temp.chkb('M7b so_payment_void(opening HQ) refused: it cannot be voided', pg_temp.run(format('select public.so_payment_void(%L, %L)::text', :'phq', 'ar2 test')) like 'ERR P0001:%it cannot be voided%', 'ERR cannot be voided');
select pg_temp.chkb('M7c doc_data(final_invoice A) refused: the original is in QuickBooks', pg_temp.run(format('select public.doc_data(%L, %L::jsonb)::text', 'final_invoice', jsonb_build_object('invoice_id', :'ia')::text)) like 'ERR P0001:%the original is in QuickBooks%', 'ERR QuickBooks');
select pg_temp.chkb('M7d doc_data(internal_receipt A) refused too', pg_temp.run(format('select public.doc_data(%L, %L::jsonb)::text', 'internal_receipt', jsonb_build_object('invoice_id', :'ia')::text)) like 'ERR P0001:%the original is in QuickBooks%', 'ERR QuickBooks');
select pg_temp.chkb('M7e doc_mail_send(final_invoice A · preview) refused with the same words', pg_temp.run(format('select public.doc_mail_send(%L, %L::jsonb, %L, %L, %L, false)::text', 'final_invoice', jsonb_build_object('invoice_id', :'ia')::text, 'ar2-hq@test.invalid', 'subj', 'body')) like 'ERR P0001:%the original is in QuickBooks%', 'ERR QuickBooks');
select pg_temp.run(format('select public.doc_data(%L, %L::jsonb)::text', 'final_invoice', jsonb_build_object('invoice_id', :'inrm')::text)) as dd_norm \gset
select pg_temp.chk('M7f normal invoice: doc_data works (docs[0].invoice.number 79999)', coalesce(pg_temp.j(:'dd_norm')#>>'{docs,0,invoice,number}', left(:'dd_norm', 200)), '79999');
select pg_temp.chk('M7g normal invoice: so_invoice_cancel works (status cancelled · remaining 0)', (public.so_invoice_cancel(:'inrm'::uuid, 'ar2 test')->>'status') || ' ' || public.so_invoice_remaining(:'inrm'::uuid)::text, 'cancelled 0');
select pg_temp.chkb('M7h so_payment_add refuses method opening for humans', pg_temp.run(format('select public.so_payment_add(%L::jsonb)::text', jsonb_build_object('customer_id', :'hq', 'amount', 1, 'method', 'opening', 'currency_code', 'CAD', 'warehouse_id', :'tor')::text)) like 'ERR P0001: Unknown payment method opening%', 'ERR Unknown payment method opening');

-- ── M8) 크레딧 붙이기(so_credit_attach) — 참조 크레딧 50 을 B 에 ──
\echo '── M8 크레딧'
set local session_replication_role = replica;
insert into public.so_credit (credit_number, status, customer_id, currency_id, currency_code, reason, warehouse_id, issued_on, lines_amount, total, ref_invoice_number, issued_by)
  values ('CR-79901', 'issued', :'hq'::uuid, :'cad'::uuid, 'CAD', 'other', :'tor'::uuid, :'today'::date, 50, 50, '79902', :'s_id'::uuid) returning id::text as cr1 \gset
set local session_replication_role = origin;
select public.so_credit_attach(:'cr1'::uuid, jsonb_build_array(jsonb_build_object('invoice_id', :'ib', 'amount', 50))) as catt \gset
select pg_temp.chk('M8a credit 50 attached to B: remaining(B) 941.00 · list.credited 50 · owed_credit 0 · available 25.00', format('%s %s %s %s', public.so_invoice_remaining(:'ib'::uuid), (select l.credited from public.so_invoice_list l where l.id = :'ib'::uuid), (select b.owed_credit from public.so_customer_balance(:'hq'::uuid) b where b.currency_code = 'CAD'), (select b.available from public.so_customer_balance(:'hq'::uuid) b where b.currency_code = 'CAD')), '941.00 50 0 25.00');

-- ── M9) 다 받으면 닫힘 ──
\echo '── M9 완납'
select public.so_payment_add(jsonb_build_object('customer_id', :'hq', 'amount', 501.27, 'method', 'e_transfer', 'currency_code', 'CAD', 'warehouse_id', :'tor', 'account_id', :'bank', 'reference', 'AR2 et 2', 'allocations', jsonb_build_array(jsonb_build_object('invoice_id', :'ia', 'amount', 501.27)))) as pay2 \gset
select pg_temp.chk('M9a A paid off: remaining 0 · is_open false · HQ open 1 (B) · overdue(STORE) count 0 · propose(HQ 5000) only B 941.00', format('%s %s %s %s %s %s', public.so_invoice_remaining(:'ia'::uuid), (select l.is_open::text from public.so_invoice_list l where l.id = :'ia'::uuid), (select b.open_invoices from public.so_customer_balance(:'hq'::uuid) b where b.currency_code = 'CAD'), public.so_customer_overdue(:'st'::uuid)->>'count', jsonb_array_length(public.so_payment_propose(:'hq'::uuid, 5000, :'cad'::uuid)->'proposed'), public.so_payment_propose(:'hq'::uuid, 5000, :'cad'::uuid)#>>'{proposed,0,remaining}'), '0.00 false 1 0 1 941.00');
select pg_temp.chkb('M9b over-allocation on A refused by the limit (remaining 0)', pg_temp.run(format('select public.so_payment_add(%L::jsonb)::text', jsonb_build_object('customer_id', :'hq', 'amount', 1, 'method', 'cash', 'currency_code', 'CAD', 'warehouse_id', :'tor', 'account_id', :'bank', 'allocations', jsonb_build_array(jsonb_build_object('invoice_id', :'ia', 'amount', 1)))::text)) like 'ERR P0001: Invoice 79901 has only 0.00 left to pay%', 'ERR has only 0.00 left');

-- ── M10) 권한 — authenticated 는 거부(42501) · service_role 은 통과(M1 ~ M6 이 service_role 로 돌았다) ──
\echo '── M10 권한'
do $$
begin
  execute 'set local role authenticated';
  perform public.so_opening_load('{}'::jsonb, true);
  perform set_config('app.ar2_perm', 'NO_ERROR', true);
exception when others then
  perform set_config('app.ar2_perm', sqlstate, true);
end $$;
reset role;
select pg_temp.chk('M10a authenticated calling so_opening_load → 42501', current_setting('app.ar2_perm', true), '42501');
select pg_temp.chk('M10b empty input as service_role → in 0 · nothing written', (pg_temp.load('{}'::jsonb, false)#>>'{invoices,in}') || ' ' || (select count(*) from public.so_invoice where kind = 'opening')::text, '0 3');
select pg_temp.chkb('M10c bad input refused: invoices not an array · > 500 rows · as_of in the future', pg_temp.run('select public.so_opening_load(''{"invoices": 1}''::jsonb, true)::text') like 'ERR P0001:%must be a JSON array%'
  and pg_temp.run('select public.so_opening_load(jsonb_build_object(''invoices'', (select jsonb_agg(jsonb_build_object(''x'', g)) from generate_series(1, 501) g)), true)::text') like 'ERR P0001:%Too many invoices%'
  and pg_temp.run(format('select public.so_opening_load(%L::jsonb, true)::text', jsonb_build_object('as_of', (:'today'::date + 1)::text)::text)) like 'ERR P0001:%in the future%', 'three refusals');
select pg_temp.chk('M10d row-level reasons: number_invalid · issued_on_future · total_mismatch · nothing_remaining · number_taken · duplicate_in_input',
  (select string_agg(e->>'reason', ' ' order by (e->>'seq')::int) from jsonb_array_elements(pg_temp.load(jsonb_build_object('as_of', :'today', 'invoices', jsonb_build_array(
     jsonb_build_object('legacy_sale_id', 's1', 'legacy_invoice_id', 't1', 'invoice_number', 'ABC', 'cin7_customer_id', :'hq_c7', 'issued_on', :'today', 'currency', 'CAD', 'total_before_tax', 10, 'tax', 0, 'total', 10),
     jsonb_build_object('legacy_sale_id', 's2', 'legacy_invoice_id', 't2', 'invoice_number', '79911', 'cin7_customer_id', :'hq_c7', 'issued_on', (:'today'::date + 1)::text, 'currency', 'CAD', 'total_before_tax', 10, 'tax', 0, 'total', 10),
     jsonb_build_object('legacy_sale_id', 's3', 'legacy_invoice_id', 't3', 'invoice_number', '79912', 'cin7_customer_id', :'hq_c7', 'issued_on', :'today', 'currency', 'CAD', 'total_before_tax', 10, 'tax', 1, 'total', 10),
     jsonb_build_object('legacy_sale_id', 's4', 'legacy_invoice_id', 't4', 'invoice_number', '79913', 'cin7_customer_id', :'hq_c7', 'issued_on', :'today', 'currency', 'CAD', 'total_before_tax', 10, 'tax', 0, 'total', 10, 'prior_settled', 10),
     jsonb_build_object('legacy_sale_id', 's5', 'legacy_invoice_id', 't5', 'invoice_number', '79901', 'cin7_customer_id', :'hq_c7', 'issued_on', :'today', 'currency', 'CAD', 'total_before_tax', 10, 'tax', 0, 'total', 10),
     jsonb_build_object('legacy_sale_id', 's6', 'legacy_invoice_id', 't6', 'invoice_number', '79914', 'cin7_customer_id', :'hq_c7', 'issued_on', :'today', 'currency', 'CAD', 'total_before_tax', 10, 'tax', 0, 'total', 10),
     jsonb_build_object('legacy_sale_id', 's6', 'legacy_invoice_id', 't6', 'invoice_number', '79915', 'cin7_customer_id', :'hq_c7', 'issued_on', :'today', 'currency', 'CAD', 'total_before_tax', 10, 'tax', 0, 'total', 10))), true)#>'{invoices,rejects}') e),
  'number_invalid issued_on_future total_mismatch nothing_remaining number_taken duplicate_in_input');

-- ── M11) 시퀀스 무변 · 옛 번호로 찾기(정규화 색인) ──
\echo '── M11 시퀀스'
select pg_temp.chk('M11a invoice · credit sequences untouched inside the transaction', (select last_value::text || ' ' || is_called::text from public.so_invoice_number_seq) || ' / ' || (select last_value::text || ' ' || is_called::text from public.so_credit_number_seq), :'inv_seq_last' || ' ' || (:'inv_seq_called'::boolean)::text || ' / ' || :'cr_seq_last' || ' ' || (:'cr_seq_called'::boolean)::text);
select pg_temp.chk('M11b find by old number through lower(btrim()) · the normalized index exists on that expression', (select count(*)::text from public.so_invoice i where lower(btrim(i.invoice_number)) = lower(btrim(' 79902 ')) and i.kind = 'opening') || ' ' || (select (indexdef like '%lower(btrim(invoice_number))%')::text from pg_indexes where indexname = 'so_invoice_number_norm_idx'), '1 true');

-- ── M12) 크기 실측 — 손님 90 · 이월 인보이스 320 · 받아 둔 돈 110 줄(90 묶음) 한 번에(REST 8 s 안인가) ──
\echo '── M12 크기 실측'
set local session_replication_role = replica;
insert into public.customer (name, source, cin7_id, currency_id, currency_code, default_location_id, default_location_name, payment_term_id, payment_term_name)
  select format('AR2 bulk %s', g), 'manual', gen_random_uuid(), :'cad'::uuid, 'CAD', :'tor'::uuid, :'tor_name', :'pt30'::uuid, :'pt30_name' from generate_series(1, 90) g;
set local session_replication_role = origin;
create temp table t_bulk as select c.id, c.cin7_id, row_number() over (order by c.name) as rn from public.customer c where c.name like 'AR2 bulk %';
select jsonb_build_object('as_of', :'today', 'complete', false,
  'invoices', (select jsonb_agg(jsonb_build_object('legacy_sale_id', 'bulk-sale-' || g, 'legacy_invoice_id', 'bulk-task-' || g, 'invoice_number', (80000 + g)::text, 'cin7_customer_id', b.cin7_id, 'issued_on', (:'today'::date - (g % 90))::text,
                                                    'payment_term_name', :'pt30_name', 'currency', 'CAD', 'total_before_tax', 100 + g, 'tax', round((100 + g) * 0.13, 2), 'total', round((100 + g) * 1.13, 2), 'prior_settled', case when g % 7 = 0 then 1.25 else 0 end))
                 from generate_series(1, 320) g join t_bulk b on b.rn = ((g - 1) % 90) + 1),
  'credits', (select jsonb_agg(jsonb_build_object('cin7_customer_id', b.cin7_id, 'currency', 'CAD', 'amount', 10 + g, 'source', case when g > 90 then 'overpay' else 'credit' end, 'reference', 'bulk ' || g))
                 from generate_series(1, 110) g join t_bulk b on b.rn = ((g - 1) % 90) + 1)) as bulk_in \gset
select clock_timestamp() as t_b0 \gset
select pg_temp.load(:'bulk_in'::jsonb, true) as bulk_dry \gset
select clock_timestamp() as t_b1 \gset
select pg_temp.load(:'bulk_in'::jsonb, false) as bulk_ap \gset
select clock_timestamp() as t_b2 \gset
select pg_temp.load(:'bulk_in'::jsonb, false) as bulk_re \gset
select clock_timestamp() as t_b3 \gset
select pg_temp.chk('M12a bulk apply: 320 inserted · 90 payment groups inserted · re-run 320 same · 90 same', format('%s %s %s %s', :'bulk_ap'::jsonb#>>'{invoices,inserted}', :'bulk_ap'::jsonb#>>'{credits,inserted}', :'bulk_re'::jsonb#>>'{invoices,same}', :'bulk_re'::jsonb#>>'{credits,same}'), '320 90 320 90');
select pg_temp.chkb('M12b bulk timing under 8 s each — dry ' || (:'bulk_dry'::jsonb->>'ms') || ' ms · apply ' || (:'bulk_ap'::jsonb->>'ms') || ' ms · re-run ' || (:'bulk_re'::jsonb->>'ms') || ' ms (wall ' || round(extract(epoch from :'t_b1'::timestamptz - :'t_b0'::timestamptz) * 1000)::text || ' / ' || round(extract(epoch from :'t_b2'::timestamptz - :'t_b1'::timestamptz) * 1000)::text || ' / ' || round(extract(epoch from :'t_b3'::timestamptz - :'t_b2'::timestamptz) * 1000)::text || ' ms)', (:'bulk_dry'::jsonb->>'ms')::numeric < 8000 and (:'bulk_ap'::jsonb->>'ms')::numeric < 8000 and (:'bulk_re'::jsonb->>'ms')::numeric < 8000, '< 8000 ms');
select pg_temp.chk('M12c bulk sums: CAD invoices 320 · remaining = Σtotal − Σprior · payment CAD 90 groups · Σ 110 rows', format('%s %s %s %s', :'bulk_ap'::jsonb#>>'{invoices,by_currency,0,count}', ((:'bulk_ap'::jsonb#>>'{invoices,by_currency,0,remaining}')::numeric = (:'bulk_ap'::jsonb#>>'{invoices,by_currency,0,total}')::numeric - (:'bulk_ap'::jsonb#>>'{invoices,by_currency,0,prior_settled}')::numeric)::text, :'bulk_ap'::jsonb#>>'{credits,by_currency,0,count}', ((select sum(10 + g) from generate_series(1, 110) g) = (:'bulk_ap'::jsonb#>>'{credits,by_currency,0,amount}')::numeric)::text), '320 true 90 true');
select pg_temp.chk('M12d bulk large (≥ 1000) list empty · so_invoice_list counts 323 opening rows · ar_summary(all) sees them', (jsonb_array_length(:'bulk_ap'::jsonb#>'{credits,large}'))::text || ' ' || (select count(*) from public.so_invoice_list l where l.kind = 'opening')::text, '0 323');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.so_invoice) = :n_inv as so_invoice_same, (select count(*) from public.so_payment) = :n_pay as so_payment_same, (select count(*) from public.so_payment_alloc) = :n_alloc as alloc_same,
       (select count(*) from public.customer) = :n_cust as customer_same, (select count(*) from public.ims_staff) = :n_staff as staff_same, (select count(*) from public.so_credit) = :n_cred as credit_same,
       (select count(*) from public.mail_outbox) = :n_mail as mail_same, (select count(*) from public.doc_mail_skip) = :n_skip as skip_same, (select count(*) from public.drive_job) = :n_drive as drive_same,
       (select last_value = :inv_seq_last and is_called = :'inv_seq_called'::boolean from public.so_invoice_number_seq) as inv_seq_same,
       (select last_value = :cr_seq_last and is_called = :'cr_seq_called'::boolean from public.so_credit_number_seq) as cr_seq_same,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_opening_load') = :n_fn0 as fn_count_same_as_before;
