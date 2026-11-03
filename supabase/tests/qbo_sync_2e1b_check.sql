-- supabase/tests/qbo_sync_2e1b_check.sql — qbo-sync-2e-1b 검증: 표 · 지문 · 결제 몸(짝 · 줄 · wait · failed 글 · 일부 붙음) · void 몸 · 트리거(넣기 · 떼기 · 다시 붙이기 · 취소) · claim(blocked_for_invoice · needs · failed · 지문) · done(qbo_txn Payment · 지문 · 대조 · reconcile) · retry 규칙 · list · doc · preview · 백필(실물 61 · 이월 3 제외) · requeue · 권한 · nowhere (2026-11-02 밤)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback · ⚠️ 10 초 안 · ⚠️ 붙임 트리거는 DEFERRED — `set constraints all immediate` 로 당겨 쏜다
--   Claude Code(시험): MIG=supabase/migrations/20261103050000_qbo_sync_2e1b_payment_jobs.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2e1b_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 차이는 G0 · 백필 수(시험 = 파일 안 백필 61 · 확인 = 이미 적용된 수) · 기대 OK 수는 EXPECT_OK
--   쓰기: 가짜 직원 1(manager · qbo · sales) · 손님 3(A 짝 · 부모 P 짝 없음 · 자식 K 짝) · 제품 1 · 인보이스 5 · 결제 6 · 전부 rollback · QBO 호출 0
\set ON_ERROR_STOP on
\set EXPECT_OK 33
\pset pager off
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'qbo\_%' or p.proname like 'so\_%' or p.proname like 'shop\_%');
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0, (select count(*) from public.product) as n_prod0,
       (select count(*) from public.so) as n_so0, (select count(*) from public.so_invoice) as n_inv0, (select count(*) from public.so_payment) as n_pay0, (select count(*) from public.so_payment_alloc) as n_alloc0,
       (select count(*) from public.qbo_job) as n_job0, (select count(*) from public.qbo_txn) as n_txn0, (select count(*) from public.qbo_link) as n_link0,
       (select realm_id from public.qbo_connection where singleton) as realm,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as tor_id, (select id::text from public.ref_currency where code = 'CAD') as cad_id,
       (select l.qbo_id from public.ref_account a join public.qbo_link l on l.ims_kind = 'account' and l.ims_id = a.id::text where a.code = '_105_') as q105,
       (select count(*) from public.so_payment p where p.status = 'active' and p.kind = 'payment' and p.method <> 'opening' and exists (select 1 from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null)
           and not exists (select 1 from public.so_payment_alloc a join public.so_invoice i on i.id = a.invoice_id where a.payment_id = p.id and a.voided_at is null and (i.kind = 'opening' or not public.qbo_send_since_ok(i.issued_on)))) as n_scope,
       (select count(distinct a.payment_id) from public.so_payment_alloc a join public.so_invoice i on i.id = a.invoice_id join public.so_payment p on p.id = a.payment_id where a.voided_at is null and i.kind = 'opening' and p.method <> 'opening') as n_open_linked,
       (select i.id::text from public.so_invoice i where i.invoice_number = '50761') as inv50761,
       (select count(*) from public.qbo_job where ims_kind = 'payment') as n_payjob0, public.ims_today()::text as today \gset
\echo '── 기준: 함수' :n_fn '· job' :n_job0 '· payment jobs' :n_payjob0 '· txn' :n_txn0 '· 백필 범위' :n_scope '· 이월에 붙은 결제' :n_open_linked '· realm' :realm
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$ insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want); $$;
create function pg_temp.as_conn(p_role text, p_claims jsonb, p_sql text) returns text language plpgsql as $$
declare v text; v_old text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', coalesce(p_claims::text, ''), true);
  execute format('set local role %I', p_role);
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  execute 'reset role';
  perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
  return coalesce(v, '(null)');
end $$;
create function pg_temp.bk(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"e3e3e3e3-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
create function pg_temp.svc(p_sql text) returns text language sql as $$ select pg_temp.as_conn('service_role', '{"role":"service_role"}'::jsonb, p_sql) $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  return coalesce(v, '(null)');
end $$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g'); exit when v_chunk = v_prev; end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
-- 가짜 직원 · 손님 셋(A 짝 · P 부모 짝 없음 · K 자식 · 청구처 P · 짝 있음) · 제품 · 인보이스 다섯
insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values
  ('e3e3e3e3-0000-4000-8000-00000000000a', 'e3e3e3e3-0000-4000-8000-000000000001', 'qbo-sync-2e1b-bk@asung.invalid', 'QBO 2e1b Bookkeeper', 'manager', '["qbo", "sales"]');
insert into public.customer (id, name, is_active, source, currency_code) values
  ('c3e00000-0000-4000-8000-00000000000a', 'QBO2E Store A', true, 'manual', 'CAD'), ('c3e00000-0000-4000-8000-000000000010', 'QBO2E Parent', true, 'manual', 'CAD');
insert into public.customer (id, name, is_active, source, currency_code, parent_id, parent_source, default_bill_to_customer_id) values
  ('c3e00000-0000-4000-8000-000000000011', 'QBO2E Kid Store', true, 'manual', 'CAD', 'c3e00000-0000-4000-8000-000000000010', 'ims', 'c3e00000-0000-4000-8000-000000000010');
insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match) values
  (:'realm', 'customer', 'c3e00000-0000-4000-8000-00000000000a', 'Customer', 'C-2E-A', 'manual', 'QBO2E Store A'), (:'realm', 'customer', 'c3e00000-0000-4000-8000-000000000011', 'Customer', 'C-2E-K', 'manual', 'QBO2E Kid Store');
insert into public.product (id, name, sku, is_active, source, sellable, revenue_account_code) values ('d3e00000-0000-4000-8000-000000000001', 'QBO2E Widget', 'QBO2E-001', true, 'manual', true, '_98_');
create temp sequence s_so start 99940;
create function pg_temp.mk_inv(p_id uuid, p_num text, p_kind text, p_bill uuid, p_bill_name text, p_on date, p_cust uuid[]) returns void language plpgsql as $$
declare i int; v_oid uuid; v_so uuid; v_sl uuid; v_num text; v_n int := coalesce(array_length(p_cust, 1), 0); v_prod uuid := 'd3e00000-0000-4000-8000-000000000001';
begin
  insert into public.so_invoice (id, invoice_number, kind, status, bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country, issued_on, issued_by, store_customer_id, legacy_sale_id, legacy_invoice_id, currency_id, currency_code, lines_amount, taxable_amount, tax_amount, total, amount_due)
  values (p_id, p_num, p_kind, 'issued', p_bill, p_bill_name, '1 Any St', 'Toronto', 'ON', 'M1M 1M1', 'CA', p_on, case when p_kind = 'sale' then 'e3e3e3e3-0000-4000-8000-00000000000a'::uuid end, coalesce(p_cust[1], p_bill), case when p_kind = 'opening' then 'test-sale-' || p_num end, case when p_kind = 'opening' then 'test-inv-' || p_num end, (select id from public.ref_currency where code = 'CAD'), 'CAD', 10 * greatest(v_n, 1), 10 * greatest(v_n, 1), 0, 10 * greatest(v_n, 1), 10 * greatest(v_n, 1));
  for i in 1 .. v_n loop
    v_so := gen_random_uuid(); v_sl := gen_random_uuid(); v_oid := gen_random_uuid(); v_num := 'SO-' || nextval('s_so')::text;
    insert into public.so (id, so_number, customer_id, bill_to_customer_id, channel, intake, currency_id, currency_code, order_date, ref, shipped_at, ship_to_company, ship_to_line1, ship_to_city, ship_to_country)
    values (v_so, v_num, p_cust[i], p_bill, 'pos', 'manual', (select id from public.ref_currency where code = 'CAD'), 'CAD', p_on, 'PO-' || v_num, now(), 'Ship', '5 St', 'Toronto', 'CA');
    insert into public.so_line (id, so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, unit_price) values (v_sl, v_so, 1, v_prod, 'QBO2E-001', 'QBO2E Widget', 1, 1, 1, 10);
    insert into public.so_invoice_order (id, invoice_id, so_id, so_number, customer_id, ship_to_company, ship_to_line1, ship_to_city, ship_to_country, tax_rule_id, tax_rule, rate_pct, tax_source, lines_amount, taxable_amount, tax_amount, total)
    values (v_oid, p_id, v_so, v_num, p_cust[i], 'Ship', '5 St', 'Toronto', 'CA', (select id from public.ref_tax_rule where name = 'HST ON (Sale)'), 'HST ON (Sale)', 0, 'ship_to', 10, 10, 0, 10);
    insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, qty, unit_price, amount, tax_amount, account_code) values (p_id, v_oid, i, 'product', v_sl, 'QBO2E-001', 'QBO2E Widget', 1, 10, 10, 0, '_98_');
  end loop;
end $$;
-- INV1 A sale(일감 queued · 결제가 기다림) · INV2 A sale(보내진 셈 · txn) · INV3 K 매장 · 청구처 P sale(txn · 980) · INV4 A opening(이월 · 짝 없음) · INV5 A sale since 전(10-31)
select pg_temp.mk_inv('13e00000-0000-4000-8000-000000000001', '9970001', 'sale', 'c3e00000-0000-4000-8000-00000000000a', 'QBO2E Store A', :'today'::date, array['c3e00000-0000-4000-8000-00000000000a'::uuid]);
select pg_temp.mk_inv('13e00000-0000-4000-8000-000000000002', '9970002', 'sale', 'c3e00000-0000-4000-8000-00000000000a', 'QBO2E Store A', :'today'::date, array['c3e00000-0000-4000-8000-00000000000a'::uuid]);
select pg_temp.mk_inv('13e00000-0000-4000-8000-000000000003', '9970003', 'sale', 'c3e00000-0000-4000-8000-000000000010', 'QBO2E Parent', :'today'::date, array['c3e00000-0000-4000-8000-000000000011'::uuid]);
select pg_temp.mk_inv('13e00000-0000-4000-8000-000000000004', '9970004', 'opening', 'c3e00000-0000-4000-8000-00000000000a', 'QBO2E Store A', '2026-10-01', '{}'::uuid[]);
select pg_temp.mk_inv('13e00000-0000-4000-8000-000000000005', '9970005', 'sale', 'c3e00000-0000-4000-8000-00000000000a', 'QBO2E Store A', '2026-10-31', array['c3e00000-0000-4000-8000-00000000000a'::uuid]);
set constraints all immediate;
update public.qbo_job set state = 'sent', qbo_id = 'INV-2E-2', qbo_name = '9970002', sent_at = now() where ims_id = '13e00000-0000-4000-8000-000000000002' and kind = 'invoice';
update public.qbo_job set state = 'sent', qbo_id = 'INV-2E-3', qbo_name = '9970003', sent_at = now() where ims_id = '13e00000-0000-4000-8000-000000000003' and kind = 'invoice';
insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, sent_at) values
  (:'realm', 'invoice', '13e00000-0000-4000-8000-000000000002', 'Invoice', 'INV-2E-2', '9970002', '0', 10, 0, now()), (:'realm', 'invoice', '13e00000-0000-4000-8000-000000000003', 'Invoice', 'INV-2E-3', '9970003', '0', 10, 0, now());
select (select id from public.qbo_job where ims_id = '13e00000-0000-4000-8000-000000000001' and kind = 'invoice') as jinv1, (select count(*) from public.qbo_job) as n_job1 \gset

-- ── A) 착지 ──
select pg_temp.chk('A1 CHECK — qbo_job kind 8 · ims_kind payment · qbo_txn kind · type · pair · source · 칸 fingerprint 둘', (select string_agg((pg_get_constraintdef(oid) ~* 'payment')::text, ',' order by conname) from pg_constraint where conname in ('qbo_job_kind_ck', 'qbo_job_ims_kind_ck', 'qbo_job_pair_ck', 'qbo_txn_kind_ck', 'qbo_txn_pair_ck', 'qbo_txn_type_ck'))
  || ' | ' || (select count(*)::text from information_schema.columns where (table_name, column_name) in (('qbo_job', 'fingerprint'), ('qbo_txn', 'fingerprint'), ('qbo_txn', 'source'))) || ' | ' || (select pg_get_constraintdef(oid) ~ 'matched' from pg_constraint where conname = 'qbo_txn_source_ck')::text, 'true,true,true,true,true,true | 3 | true');
select pg_temp.chk('A2 inv_config qbo_send_payments_enabled = off · done 서명 하나(10 인자) · 트리거 둘', (select value from public.inv_config where key = 'qbo_send_payments_enabled') || ' | ' || (select string_agg(pg_get_function_identity_arguments(p.oid), ' ; ') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_job_done')
  || ' | ' || (select string_agg(t.tgname || ':' || c.relname || ':' || case when t.tgdeferrable then 'deferrable' else 'immediate' end, ',' order by t.tgname) from pg_trigger t join pg_class c on c.oid = t.tgrelid where t.tgname in ('so_payment_alloc_qbo', 'so_payment_qbo_status')),
  'off | p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text, p_intuit_tid text, p_note text, p_sku text, p_total_amt numeric, p_total_tax numeric, p_unapplied_amt numeric | so_payment_alloc_qbo:so_payment_alloc:deferrable,so_payment_qbo_status:so_payment:immediate');
select pg_temp.chk('A3 nowhere — 새 함수 · 재발행 여섯의 깊이 0 WHERE 없는 update · delete = 0', (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_payment_sync', 'qbo_payment_requeue', 'qbo_payment_backfill', 'qbo_job_on_payment_alloc', 'qbo_job_on_payment_status', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview')),
  'qbo_job_claim=0 qbo_job_done=0 qbo_job_list=0 qbo_job_on_payment_alloc=0 qbo_job_on_payment_status=0 qbo_job_preview=0 qbo_job_retry=0 qbo_payment_backfill=0 qbo_payment_requeue=0 qbo_payment_sync=0');
select pg_temp.chk('A4 ACL — 새 함수 grant 0 · done service_role · claim service_role · preview · list · retry authenticated', (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_payment_body', 'qbo_payment_void_body', 'qbo_payment_fingerprint', 'qbo_payment_sync', 'qbo_payment_requeue', 'qbo_payment_backfill', 'qbo_job_done', 'qbo_job_claim', 'qbo_job_retry')),
  'qbo_job_claim={postgres=X/postgres,service_role=X/postgres} qbo_job_done={postgres=X/postgres,service_role=X/postgres} qbo_job_retry={postgres=X/postgres,authenticated=X/postgres} qbo_payment_backfill={postgres=X/postgres} qbo_payment_body={postgres=X/postgres} qbo_payment_fingerprint={postgres=X/postgres} qbo_payment_requeue={postgres=X/postgres} qbo_payment_sync={postgres=X/postgres} qbo_payment_void_body={postgres=X/postgres}');

-- ── B) 백필(실물 · 파일 안에서 돌았다) — 시험이면 범위 수 · 이월에 붙은 결제는 일감 없음 ──
\if :{?mig}
select pg_temp.chk('B1 백필 — payment 일감 수 = 백필 범위(실물 61) · 전부 queued · 이월 인보이스에 붙은 결제(3)는 일감 없음', (select count(*)::text || ' ' || count(*) filter (where state = 'queued')::text from public.qbo_job where ims_kind = 'payment' and ims_id not like '%-0000-4000-8000-%')
  || ' | ' || (select count(*)::text from public.qbo_job j where j.ims_kind = 'payment' and j.ims_id in (select a.payment_id::text from public.so_payment_alloc a join public.so_invoice i on i.id = a.invoice_id where a.voided_at is null and i.kind = 'opening')),
  :n_scope || ' ' || :n_scope || ' | 0');
\else
select pg_temp.chk('B1 (적용 뒤) 이월 인보이스에 붙은 결제는 1d 전까지 일감 없음', (select count(*)::text from public.qbo_job j where j.ims_kind = 'payment' and j.ims_id in (select a.payment_id::text from public.so_payment_alloc a join public.so_invoice i on i.id = a.invoice_id where a.voided_at is null and i.kind = 'opening')), '0');
\endif

-- ── C) 결제 넣기(창구 · 트리거) · 몸 ──
select pg_temp.bk(format($q$ select (public.so_payment_add(%L::jsonb))->>'payment_id' $q$, jsonb_build_object('customer_id', 'c3e00000-0000-4000-8000-00000000000a', 'amount', 10, 'method', 'cheque', 'reference', 'CHQ 2E-P1', 'currency_code', 'CAD', 'warehouse_id', :'tor_id', 'paid_on', (:'today'::date + 7)::text, 'allocations', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000002', 'amount', 10)))::text)) as p1 \gset
select pg_temp.bk(format($q$ select (public.so_payment_add(%L::jsonb))->>'payment_id' $q$, jsonb_build_object('customer_id', 'c3e00000-0000-4000-8000-00000000000a', 'amount', 4, 'method', 'cash', 'reference', '2E-P2', 'currency_code', 'CAD', 'warehouse_id', :'tor_id', 'allocations', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000001', 'amount', 4)))::text)) as p2 \gset
select pg_temp.bk(format($q$ select (public.so_payment_add(%L::jsonb))->>'payment_id' $q$, jsonb_build_object('customer_id', 'c3e00000-0000-4000-8000-000000000010', 'amount', 10, 'method', 'e_transfer', 'reference', 'ET-2E-P3-REFERENCE-TOO-LONG-123', 'currency_code', 'CAD', 'warehouse_id', :'tor_id', 'allocations', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000003', 'amount', 10)))::text)) as p3 \gset
select pg_temp.bk(format($q$ select (public.so_payment_add(%L::jsonb))->>'payment_id' $q$, jsonb_build_object('customer_id', 'c3e00000-0000-4000-8000-00000000000a', 'amount', 3, 'method', 'credit_card', 'reference', '2E-P4', 'currency_code', 'CAD', 'warehouse_id', :'tor_id', 'allocations', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000001', 'amount', 3)))::text)) as p4 \gset
select pg_temp.bk(format($q$ select (public.so_payment_add(%L::jsonb))->>'payment_id' $q$, jsonb_build_object('customer_id', 'c3e00000-0000-4000-8000-00000000000a', 'amount', 2, 'method', 'cash', 'reference', '2E-P5', 'currency_code', 'CAD', 'warehouse_id', :'tor_id', 'allocations', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000004', 'amount', 2)))::text)) as p5 \gset
select pg_temp.bk(format($q$ select (public.so_payment_add(%L::jsonb))->>'payment_id' $q$, jsonb_build_object('customer_id', 'c3e00000-0000-4000-8000-00000000000a', 'amount', 25, 'method', 'cash', 'reference', '2E-P6', 'currency_code', 'CAD', 'warehouse_id', :'tor_id')::text)) as p6 \gset
select pg_temp.chk('C1 넣기 여섯 — P1 ~ P5 는 붙임이 있어 트리거가 payment 일감 queued · P6(받아 둔 돈만)은 일감 없음', (select count(*)::text || ' ' || string_agg(j.state, ',' order by j.ims_id) from public.qbo_job j where j.ims_kind = 'payment' and j.ims_id in (:'p1', :'p2', :'p3', :'p4', :'p5')) || ' | ' || (select count(*)::text from public.qbo_job j where j.ims_kind = 'payment' and j.ims_id = :'p6'), '5 queued,queued,queued,queued,queued | 0');
select public.qbo_payment_body(:'p1'::uuid)::text as b1 \gset
select pg_temp.chk('C2 P1 몸 — CustomerRef C-2E-A · TxnDate 미래(+7 · 991 경고) · TotalAmt 10 · Method 2 · DepositTo _105_ 짝 · PaymentRefNum · PrivateNote · Line 1 → INV-2E-2 · check_lines 1 · unapplied 0 · needs 0 · wait null',
  (:'b1'::jsonb->'body'->'CustomerRef'->>'value') || ' ' || (:'b1'::jsonb->'body'->>'TxnDate') || ' ' || (:'b1'::jsonb->'body'->>'TotalAmt') || ' ' || (:'b1'::jsonb->'body'->'PaymentMethodRef'->>'value') || ' ' || (:'b1'::jsonb->'body'->'DepositToAccountRef'->>'value') || ' ' || (:'b1'::jsonb->'body'->>'PaymentRefNum') || ' | ' || (:'b1'::jsonb->'body'->>'PrivateNote' = 'IMS payment ' || :'p1')::text
  || ' | ' || (:'b1'::jsonb->'body'->'Line'->0->'LinkedTxn'->0->>'TxnId') || ' ' || (:'b1'::jsonb->'body'->'Line'->0->>'Amount') || ' | ' || jsonb_array_length(:'b1'::jsonb->'check_lines')::text || ' ' || (:'b1'::jsonb->'check_lines'->0->>'invoice_number') || ' | ' || (:'b1'::jsonb->'totals'->>'unapplied') || ' ' || jsonb_array_length(:'b1'::jsonb->'needs')::text || ' ' || coalesce(:'b1'::jsonb->>'wait_job', 'null') || ' | ' || (:'b1'::jsonb->'warnings'->>0),
  'C-2E-A ' || (:'today'::date + 7)::text || ' 10 2 ' || :'q105' || ' CHQ 2E-P1 | true | INV-2E-2 10 | 1 9970002 | 0 0 null | post-dated: QuickBooks payment dated ' || (:'today'::date + 7)::text || ' (991)');
select public.qbo_payment_body(:'p2'::uuid)::text as b2 \gset
select pg_temp.chk('C3 P2 몸 — INV1 의 일감이 queued → wait_job = 그 일감 · wait_invoice 9970001 · Line 0', coalesce(:'b2'::jsonb->>'wait_job', 'null') || ' ' || (:'b2'::jsonb->>'wait_invoice') || ' ' || (:'b2'::jsonb->>'line_count'), :'jinv1' || ' 9970001 0');
select public.qbo_payment_body(:'p3'::uuid)::text as b3 \gset
select pg_temp.chk('C4 P3 몸(980 (나)) — 청구처 P 짝 없음 → needs customer P · Line 은 자식 K 의 인보이스 INV-2E-3 · reference 21 자로 잘림 + 경고',
  jsonb_array_length(:'b3'::jsonb->'needs')::text || ' ' || (:'b3'::jsonb->'needs'->0->>'name') || ' | ' || (:'b3'::jsonb->'body' ? 'CustomerRef')::text || ' ' || (:'b3'::jsonb->'body'->'Line'->0->'LinkedTxn'->0->>'TxnId') || ' | ' || (:'b3'::jsonb->'body'->>'PaymentRefNum') || ' ' || length(:'b3'::jsonb->'body'->>'PaymentRefNum')::text || ' | ' || (select count(*)::text from jsonb_array_elements_text(:'b3'::jsonb->'warnings') w where w like 'reference %cut to 21%'),
  '1 QBO2E Parent | false INV-2E-3 | ET-2E-P3-REFERENCE-TO 21 | 1');
select pg_temp.chk('C5 P4 몸 — credit_card 짝 없음 → 거부 글(983)', (select pg_temp.try(format('select public.qbo_payment_body(%L)::text', :'p4'))), 'ERR P0001: Payment method "credit_card" has no QuickBooks match — link it under Settings → QuickBooks matching → Payment methods — nothing was sent');
select pg_temp.chk('C6 P5 몸 — 이월 인보이스 짝 없음 → 거부 글(Opening invoices)', (select pg_temp.try(format('select public.qbo_payment_body(%L)::text', :'p5'))), 'ERR P0001: Invoice 9970004 was carried over from the previous system and has no QuickBooks match yet — match it under Settings → QuickBooks → Opening invoices; this payment then goes by itself — nothing was sent');
select pg_temp.chk('C7 P6 몸 — 붙임 0 → 거부 글(2e-3) · void 몸 — 보낸 적 없음 → 거부', (select pg_temp.try(format('select public.qbo_payment_body(%L)::text', :'p6'))) || ' | ' || (select pg_temp.try(format('select public.qbo_payment_void_body(%L)::text', :'p1'))),
  'ERR P0001: Payment 2E-P6 has no invoice applied — money on account goes to QuickBooks in a later step (2e-3) — nothing was sent | ERR P0001: Payment CHQ 2E-P1 was never sent to QuickBooks — nothing to void');
select pg_temp.chk('C8 P6 에 INV5(since 전 · 짝 없음) 붙이면 → 몸 거부 글(start date)', (select pg_temp.bk(format($q$ select (public.so_payment_attach(%L, %L::jsonb))->>'payment_id' $q$, :'p6', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000005', 'amount', 5))::text))) || ' | ' || (select pg_temp.try(format('select public.qbo_payment_body(%L)::text', :'p6'))),
  :'p6' || ' | ERR P0001: Invoice 9970005 was issued before the QuickBooks start date and has no QuickBooks match — match it under Settings → QuickBooks → Opening invoices — nothing was sent');

-- ── D) claim · done · reconcile ──
select pg_temp.svc(format($q$ select public.qbo_job_claim(50, array['payment', 'payment_void'], array[%L, %L, %L, %L, %L]::uuid[])::text $q$,
  (select id from public.qbo_job where ims_id = :'p1' and kind = 'payment'), (select id from public.qbo_job where ims_id = :'p2' and kind = 'payment'), (select id from public.qbo_job where ims_id = :'p3' and kind = 'payment'),
  (select id from public.qbo_job where ims_id = :'p4' and kind = 'payment'), (select id from public.qbo_job where ims_id = :'p5' and kind = 'payment'))) as cl \gset
select pg_temp.chk('D1 claim 다섯 — P1 claimed(jobs 1 · fingerprint · check_lines · lookup 실림) · P2 blocked_for_invoice · P3 blocked_for_needs(need_jobs 손님 P) · P4 · P5 failed',
  (:'cl'::jsonb->>'claimed') || ' ' || (:'cl'::jsonb->>'blocked_for_invoice') || ' ' || (:'cl'::jsonb->>'blocked_for_needs') || ' ' || (:'cl'::jsonb->>'body_failed') || ' | ' || jsonb_array_length(:'cl'::jsonb->'jobs')::text || ' ' || (:'cl'::jsonb->'jobs'->0->>'fingerprint' = public.qbo_payment_fingerprint(:'p1'::uuid))::text || ' ' || jsonb_array_length(:'cl'::jsonb->'jobs'->0->'check_lines')::text || ' ' || (:'cl'::jsonb->'jobs'->0->'lookup'->>'customer_ref')
  || ' | ' || (:'cl'::jsonb->'need_jobs'->0->>'kind') || ' ' || (:'cl'::jsonb->'need_jobs'->0->>'ims_id') || ' | ' || (select string_agg(j.state || ':' || coalesce(left(j.warning, 40), left(j.last_error, 40)), ' ; ' order by j.ims_id) from public.qbo_job j where j.kind = 'payment' and j.ims_id in (:'p2', :'p3')),
  '5 1 1 2 | 1 true 1 C-2E-A | customer c3e00000-0000-4000-8000-000000000010 | ' || (select string_agg(x, ' ; ') from (select j.state || ':' || coalesce(left(j.warning, 40), left(j.last_error, 40)) as x from public.qbo_job j where j.kind = 'payment' and j.ims_id in (:'p2', :'p3') order by j.ims_id) y));
select pg_temp.chk('D2 P2 blocked_by = INV1 일감 · P3 blocked_by = 손님 P 일감(새로 생김)', (select (j.blocked_by = :'jinv1'::uuid)::text from public.qbo_job j where j.kind = 'payment' and j.ims_id = :'p2') || ' ' || (select (p.kind || ':' || p.ims_id) from public.qbo_job j join public.qbo_job p on p.id = j.blocked_by where j.kind = 'payment' and j.ims_id = :'p3'), 'true customer:c3e00000-0000-4000-8000-000000000010');
select pg_temp.chk('D3 P1 일감 fingerprint 가 claim 때 적혔다', (select (j.fingerprint = public.qbo_payment_fingerprint(:'p1'::uuid))::text from public.qbo_job j where j.kind = 'payment' and j.ims_id = :'p1'), 'true');
select pg_temp.svc(format('select public.qbo_job_done(%L, ''PAY-2E-1'', ''CHQ 2E-P1'', ''0'', ''tid-p1'', null, null, 10, null, 0)::text', (select id from public.qbo_job where ims_id = :'p1' and kind = 'payment'))) as d1 \gset
select pg_temp.chk('D4 done P1 — sent · qbo_txn Payment(PAY-2E-1 · fingerprint 옮김 · source sent · doc_number) · mismatch null · reconcile same',
  (:'d1'::jsonb->>'state') || ' ' || coalesce(:'d1'::jsonb->>'mismatch', 'null') || ' ' || (:'d1'::jsonb->'reconcile'->>'action') || ' | ' || (select t.qbo_type || ' ' || t.qbo_id || ' ' || t.doc_number || ' ' || t.source || ' ' || (t.fingerprint = public.qbo_payment_fingerprint(:'p1'::uuid))::text || ' ' || coalesce(t.total_tax::text, 'null') from public.qbo_txn t where t.ims_kind = 'payment' and t.ims_id = :'p1'),
  'sent null same | Payment PAY-2E-1 CHQ 2E-P1 sent true null');
-- 떼기 → 지문 null → void 일감 queued · 다시 붙이기 → payment 일감 blocked_by void
select pg_temp.bk(format($q$ select (public.so_payment_detach(%L, 'test detach'))->>'payment_id' $q$, (select a.id from public.so_payment_alloc a where a.payment_id = :'p1'::uuid and a.voided_at is null))) as dt \gset
select pg_temp.chk('D5 P1 떼기 — void 일감 queued(note) · payment 일감 없음(지문 null = 다시 보내지 않음)', (select string_agg(j.kind || ':' || j.state, ',' order by j.kind) from public.qbo_job j where j.ims_id = :'p1' and j.state not in ('sent', 'skipped')) || ' | ' || (select (j.note like '%void in QuickBooks%')::text from public.qbo_job j where j.ims_id = :'p1' and j.kind = 'payment_void'), 'payment_void:queued | true');
select pg_temp.bk(format($q$ select (public.so_payment_attach(%L, %L::jsonb))->>'payment_id' $q$, :'p1', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000002', 'amount', 10))::text)) as at \gset
select pg_temp.chk('D6a P1 똑같이 다시 붙이기(10 → INV2 = QBO 그대로) — 안 나간 void 일감은 skipped(「restored」) · 열린 일감 0', (select coalesce(string_agg(j.kind || ':' || j.state, ','), '(none)') from public.qbo_job j where j.ims_id = :'p1' and j.state not in ('sent', 'skipped')) || ' | ' || (select (j.note like '%restored to what QuickBooks has%')::text from public.qbo_job j where j.ims_id = :'p1' and j.kind = 'payment_void' and j.state = 'skipped'), '(none) | true');
select pg_temp.bk(format($q$ select (public.so_payment_detach(%L, 'test detach b'))->>'payment_id' $q$, (select a.id from public.so_payment_alloc a where a.payment_id = :'p1'::uuid and a.voided_at is null))) as dtb \gset
select pg_temp.bk(format($q$ select (public.so_payment_attach(%L, %L::jsonb))->>'payment_id' $q$, :'p1', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000002', 'amount', 9))::text)) as atb \gset
select pg_temp.chk('D6b P1 다르게 다시 붙이기(9 → INV2) — 새 void 일감 queued · payment 일감 blocked_by = 그 void(다시 보내기)', (select j.state || ' ' || (j.blocked_by = (select v.id from public.qbo_job v where v.ims_id = :'p1' and v.kind = 'payment_void' and v.state = 'queued'))::text from public.qbo_job j where j.ims_id = :'p1' and j.kind = 'payment' and j.state not in ('sent', 'skipped')), 'blocked true');
select public.qbo_payment_void_body(:'p1'::uuid)::text as vb \gset
select pg_temp.chk('D7 void 몸 — Id PAY-2E-1 · SyncToken 0 · sparse true', (:'vb'::jsonb->'body'->>'Id') || ' ' || (:'vb'::jsonb->'body'->>'SyncToken') || ' ' || (:'vb'::jsonb->'body'->>'sparse'), 'PAY-2E-1 0 true');
select pg_temp.svc(format($q$ select public.qbo_job_claim(50, array['payment', 'payment_void'], array[%L]::uuid[])::text $q$, (select id from public.qbo_job where ims_id = :'p1' and kind = 'payment_void' and state = 'queued'))) as cl2 \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''PAY-2E-1'', ''CHQ 2E-P1'', ''1'', ''tid-v1'', null, null)::text', (select id from public.qbo_job where ims_id = :'p1' and kind = 'payment_void' and state = 'sending'))) as dv \gset
select pg_temp.chk('D8 void done — qbo_txn voided_at · payment 일감 풀림(queued · 9 인자 호출 그대로 됨) · reconcile', (:'dv'::jsonb->>'state') || ' ' || (:'dv'::jsonb->>'unblocked') || ' ' || (:'dv'::jsonb->'reconcile'->>'action') || ' | ' || (select (t.voided_at is not null)::text from public.qbo_txn t where t.ims_kind = 'payment' and t.ims_id = :'p1') || ' ' || (select j.state from public.qbo_job j where j.ims_id = :'p1' and j.kind = 'payment' and j.state not in ('sent', 'skipped')), 'sent 1 none | true queued');
-- P1 취소: 떼고(void 일감이 이미 있으니 지문 같음 → 조용) → so_payment_void → status 트리거
select pg_temp.bk(format($q$ select (public.so_payment_detach(%L, 'test detach 2'))->>'payment_id' $q$, (select a.id from public.so_payment_alloc a where a.payment_id = :'p1'::uuid and a.voided_at is null))) as dt2 \gset
select pg_temp.bk(format($q$ select (public.so_payment_void(%L, 'test void'))->>'payment_id' $q$, :'p1')) as vd \gset
select pg_temp.chk('D9 P1 떼고 취소 — queued payment 일감은 skipped(「voided or fully detached」) · 새 void 일감 없음(QBO 쪽은 이미 void) · 결제 voided', (select string_agg(j.kind || ':' || j.state, ',' order by j.kind, j.created_at) from public.qbo_job j where j.ims_id = :'p1') || ' | ' || (select p.status from public.so_payment p where p.id = :'p1'::uuid), 'payment:sent,payment:skipped,payment_void:skipped,payment_void:sent | voided');
-- 일부만 붙은 결제(P6 · 25 중 5 · INV5 는 since 전이라 거부 → INV2 로 바꿔 본다)
select pg_temp.bk(format($q$ select (public.so_payment_detach(%L, 'move'))->>'payment_id' $q$, (select a.id from public.so_payment_alloc a where a.payment_id = :'p6'::uuid and a.voided_at is null))) as dt3 \gset
select pg_temp.bk(format($q$ select (public.so_payment_attach(%L, %L::jsonb))->>'payment_id' $q$, :'p6', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000002', 'amount', 5))::text)) as at2 \gset
select public.qbo_payment_body(:'p6'::uuid)::text as b6 \gset
select pg_temp.chk('D10 P6 일부만 붙음(25 중 5) — TotalAmt 25 · Line 1 (5) · unapplied 20 + 경고', (:'b6'::jsonb->'body'->>'TotalAmt') || ' ' || jsonb_array_length(:'b6'::jsonb->'body'->'Line')::text || ' ' || (:'b6'::jsonb->'body'->'Line'->0->>'Amount') || ' ' || (:'b6'::jsonb->'totals'->>'unapplied') || ' ' || (select count(*)::text from jsonb_array_elements_text(:'b6'::jsonb->'warnings') w where w like 'CAD 20 not applied%'), '25 1 5 20 1');

-- ── E) retry 규칙 · list · doc · preview · requeue ──
select pg_temp.chk('E1 retry — P4(failed · 붙임 있음) 되살림 OK · P1 skipped 는 지문 null 이라 거부 · P1 의 skipped void(QBO 쪽 이미 void) 는 「not standing」 거부',
  (select pg_temp.bk(format('select (public.qbo_job_retry(%L, ''link later''))->>''state''', (select id from public.qbo_job where ims_id = :'p4' and kind = 'payment')))) || ' | ' || (select pg_temp.bk(format('select (public.qbo_job_retry(%L, ''why''))->>''state''', (select id from public.qbo_job where ims_id = :'p1' and kind = 'payment' and state = 'skipped'))))
  || ' | ' || (select pg_temp.bk(format('select (public.qbo_job_retry(%L, ''why''))->>''state''', (select id from public.qbo_job where ims_id = :'p1' and kind = 'payment_void' and state = 'skipped')))),
  'queued | ERR P0001: Payment CHQ 2E-P1 is voided or has no invoice applied — nothing to send (a void job takes care of QuickBooks) — nothing was saved | ERR P0001: Payment CHQ 2E-P1 is not standing in QuickBooks — nothing to void — nothing was saved');
select pg_temp.bk($q$ select public.qbo_job_list(null, array['payment', 'payment_void'], null, null, '2E-P', 50, 0)::text $q$) as ls \gset
select pg_temp.chk('E2 list(kinds payment · q 2E-P) — 가짜 결제 줄 수 = DB 의 일감 수 · doc 칸(reference · 청구처 · 통화 · 금액 · 받은 날 · 상태) · txn 칸(P1 PAY-2E-1 voided)',
  (select count(*)::text from jsonb_array_elements(:'ls'::jsonb->'rows') r where r->>'ims_id' in (:'p1', :'p2', :'p3', :'p4', :'p5', :'p6')) || '=' || (select count(*)::text from public.qbo_job j where j.ims_kind = 'payment' and j.ims_id in (:'p1', :'p2', :'p3', :'p4', :'p5', :'p6')) || ' | ' || (select r->>'doc_number' || ' ' || (r->>'name') || ' ' || (r->>'currency') || ' ' || (r->>'total') || ' ' || (r->>'doc_date') || ' ' || (r->>'doc_status') || ' ' || (r->>'txn_qbo_id') || ' ' || (r->>'txn_voided_at' is not null)::text from jsonb_array_elements(:'ls'::jsonb->'rows') r where r->>'ims_id' = :'p1' and r->>'kind' = 'payment_void' and r->>'state' = 'sent'),
  (select count(*)::text from public.qbo_job j where j.ims_kind = 'payment' and j.ims_id in (:'p1', :'p2', :'p3', :'p4', :'p5', :'p6')) || '=' || (select count(*)::text from public.qbo_job j where j.ims_kind = 'payment' and j.ims_id in (:'p1', :'p2', :'p3', :'p4', :'p5', :'p6')) || ' | CHQ 2E-P1 QBO2E Store A CAD 10 ' || (:'today'::date + 7)::text || ' voided PAY-2E-1 true');
select pg_temp.bk(format('select public.qbo_job_preview(%L)::text', (select id from public.qbo_job where ims_id = :'p2' and kind = 'payment'))) as pv \gset
select pg_temp.chk('E3 preview P2 — wait(인보이스 9970001 · 일감) · sendable false · doc · check_lines 0 · fingerprint', (:'pv'::jsonb->'wait'->>'invoice') || ' ' || (:'pv'::jsonb->'wait'->>'job_id' = :'jinv1')::text || ' ' || (:'pv'::jsonb->>'sendable') || ' | ' || (:'pv'::jsonb->'doc'->>'doc_number') || ' ' || (:'pv'::jsonb->'doc'->>'total') || ' | ' || jsonb_array_length(:'pv'::jsonb->'check_lines')::text || ' ' || (:'pv'::jsonb->>'fingerprint' = public.qbo_payment_fingerprint(:'p2'::uuid))::text, '9970001 true false | 2E-P2 4 | 0 true');
select pg_temp.chk('E4 qbo_job_doc(payment) · 모르는 ims_id 는 null', (select public.qbo_job_doc('payment', :'p2')->>'name') || ' | ' || coalesce(public.qbo_job_doc('payment', gen_random_uuid()::text)::text, 'null'), 'QBO2E Store A | null');
select public.qbo_payment_requeue('13e00000-0000-4000-8000-000000000004'::uuid)::text as rq4 \gset
select pg_temp.chk('E5a requeue(INV4 이월) — 수 1 · P5 failed 일감이 queued 로', :'rq4' || ' ' || coalesce((select j.state from public.qbo_job j where j.ims_id = :'p5' and j.kind = 'payment'), 'none'), '1 queued');
select public.qbo_payment_requeue(:'inv50761'::uuid)::text as rq5 \gset
select pg_temp.chk('E5b 실물 50761 requeue — 수 1 · 그 결제 일감 생김(queued)', :'rq5' || ' ' || coalesce((select string_agg(j.state, ',') from public.qbo_job j where j.ims_kind = 'payment' and j.ims_id in (select a.payment_id::text from public.so_payment_alloc a where a.invoice_id = :'inv50761'::uuid and a.voided_at is null)), 'none'), '1 queued');
select pg_temp.chk('E6 실물 50761 결제 일감 claim → failed 「Opening invoices」 글(1d 전)', pg_temp.svc(format($q$ select (public.qbo_job_claim(50, array['payment'], array[%L]::uuid[]))->'requested'->0->>'reason' $q$, (select j.id from public.qbo_job j where j.ims_kind = 'payment' and j.ims_id in (select a.payment_id::text from public.so_payment_alloc a where a.invoice_id = :'inv50761'::uuid and a.voided_at is null) limit 1))), 'Invoice 50761 was carried over from the previous system and has no QuickBooks match yet — match it under Settings → QuickBooks → Opening invoices; this payment then goes by itself — nothing was sent');
select pg_temp.chk('E7 claim kinds 검사 — 옛 EF 꼴(기본 customer · item)은 결제를 안 잡는다 · bogus kind 거부', pg_temp.svc($q$ select (public.qbo_job_claim(5))->>'kinds' $q$) || ' | ' || (select pg_temp.svc($q$ select (public.qbo_job_claim(5, array['bogus']))->>'kinds' $q$)), '["customer", "item"] | ERR P0001: kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void (got {bogus})');
select pg_temp.chk('F1 바뀐 함수 = 재발행 여섯 + 새 함수(t_pre 에 없음) · 그 밖 무변', (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5), case when :{?mig} then 'qbo_job_claim,qbo_job_doc,qbo_job_done,qbo_job_list,qbo_job_preview,qbo_job_retry' else '(none)' end);

\echo '── 결과'
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.customer) = :n_cust0 as customer_same, (select count(*) from public.product) = :n_prod0 as product_same,
       (select count(*) from public.so) = :n_so0 as so_same, (select count(*) from public.so_invoice) = :n_inv0 as invoice_same, (select count(*) from public.so_payment) = :n_pay0 as payment_same, (select count(*) from public.so_payment_alloc) = :n_alloc0 as alloc_same,
       (select count(*) from public.qbo_job) = :n_job0 as job_same, (select count(*) from public.qbo_txn) = :n_txn0 as txn_same, (select count(*) from public.qbo_link) = :n_link0 as link_same,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same;
