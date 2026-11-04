-- supabase/tests/qbo_sync_2e2_1_check.sql — qbo-sync-2e-2-1 검증: 표 · 붙임 몸(짝 · Line 둘 · 수단 · 입금 계좌 없음 · wait 셋 · failed 글 · 매장 다름 · 환불 조용히) · void 몸 · 트리거(auto · Attach · detach · 인보이스 취소) · claim(blocked · failed · wait_reason) · done(qbo_txn credit_alloc · 0 대조 · void · reconcile) · retry 규칙 · list · doc · preview · 백필(실물 1) · requeue · 권한 · nowhere (2026-11-03)
-- [테스트 · Asung-IMS = IMS 메인] 시험 적용 장치 틀 — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback · ⚠️ 10 초 안 · ⚠️ 붙임 트리거는 DEFERRED — `set constraints all immediate` 로 당겨 쏜다
--   Claude Code(시험): MIG=supabase/migrations/20261103200000_qbo_sync_2e2_1_credit_apply_jobs.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2e2_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 차이는 G0 · B1(시험 = 파일 안 백필 1 · 확인 = 이미 적용된 수) · 기대 OK 수는 EXPECT_OK(시험 30 · 확인은 B2 가 없어 29)
--   쓰기: 가짜 직원 1(manager · qbo · sales) · 손님 3(A 짝 · 부모 P 짝 없음 · 자식 K 짝) · 제품 1 · 인보이스 7 · 크레딧 5(CR-999xx · 시퀀스 무접촉) · 결제 2(환불 1 직접) · 붙임 ≈ 10 · 전부 rollback · QBO 호출 0
--   실물: B1 백필이 CR-01008 → 60026 붙임의 credit_apply 일감 1 행을 만들고(새 행) B2 가 그 일감만 claim 한다(for update skip locked = 새 행만 · 기존 실물 행은 읽기만) → rollback
--   「발행 auto」 길은 so_invoice_issue 대신 그 발행이 부르는 so_credit_alloc_add(source auto) 로 흉내 낸다(트리거는 표에 달려 길과 무관 · A-2)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 30
\else
\set EXPECT_OK 29
\endif
\pset pager off
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'qbo\_%' or p.proname like 'so\_%' or p.proname like 'shop\_%');
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0, (select count(*) from public.product) as n_prod0,
       (select count(*) from public.so) as n_so0, (select count(*) from public.so_invoice) as n_inv0, (select count(*) from public.so_credit) as n_cr0, (select count(*) from public.so_credit_alloc) as n_calloc0, (select count(*) from public.so_payment) as n_pay0,
       (select count(*) from public.qbo_job) as n_job0, (select count(*) from public.qbo_txn) as n_txn0, (select count(*) from public.qbo_link) as n_link0,
       (select realm_id from public.qbo_connection where singleton) as realm,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as tor_id, (select id::text from public.ref_currency where code = 'CAD') as cad_id, (select id::text from public.ref_account where code = '_105_') as acct105,
       (select count(*) from public.so_credit_alloc a join public.so_invoice i on i.id = a.invoice_id where a.voided_at is null and i.kind = 'sale' and public.qbo_send_since_ok(i.issued_on) and public.qbo_send_since_ok((a.created_at at time zone 'America/Toronto')::date)
           and not exists (select 1 from public.qbo_job j where j.ims_kind = 'credit_alloc' and j.ims_id = a.id::text) and not exists (select 1 from public.qbo_txn t where t.ims_kind = 'credit_alloc' and t.ims_id = a.id::text)) as n_scope,
       (select a.id::text from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id where c.credit_number = 'CR-01008' and a.voided_at is null limit 1) as real_alloc,
       (select j.id::text from public.qbo_job j join public.so_credit c on c.id::text = j.ims_id where j.kind = 'credit' and c.credit_number = 'CR-01008' and j.state not in ('sent', 'skipped') limit 1) as real_crjob,
       (select count(*) from public.qbo_job where ims_kind = 'credit_alloc') as n_cajob0, public.ims_today()::text as today \gset
\echo '── 기준: 함수' :n_fn '· job' :n_job0 '· credit_alloc jobs' :n_cajob0 '· txn' :n_txn0 '· 백필 범위' :n_scope '· 실물 붙임' :real_alloc '· CR-01008 일감' :real_crjob '· realm' :realm
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
create function pg_temp.job(p_kind text, p_ims text) returns uuid language sql as $$ select j.id from public.qbo_job j where j.kind = p_kind and j.ims_id = p_ims and j.state not in ('sent', 'skipped') order by j.created_at desc limit 1 $$;
create function pg_temp.jobs(p_ims text) returns text language sql as $$ select coalesce(string_agg(j.kind || ':' || j.state, ',' order by j.created_at, j.kind), '(none)') from public.qbo_job j where j.ims_id = p_ims $$;
-- 가짜 직원 · 손님 셋(A 짝 · P 부모 짝 없음 · K 자식 · 청구처 P · 짝 있음) · 제품 · 인보이스 일곱
insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values
  ('e3e3e3e3-0000-4000-8000-00000000000a', 'e3e3e3e3-0000-4000-8000-000000000001', 'qbo-sync-2e2-bk@asung.invalid', 'QBO 2e2 Bookkeeper', 'manager', '["qbo", "sales"]');
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
create function pg_temp.fulfill(p_inv uuid) returns int language plpgsql as $$
declare v_so uuid; v_n int := 0;
begin
  for v_so in select o.so_id from public.so_invoice_order o where o.invoice_id = p_inv loop
    update public.so set status = 'confirmed', confirmed_at = now() where id = v_so;
    update public.so set status = 'shipped' where id = v_so;
    update public.so set status = 'fulfilled', closed_at = now(), invoiced_at = now() where id = v_so;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
create function pg_temp.mk_cr(p_id uuid, p_num text, p_inv uuid, p_ref text, p_cust uuid, p_store uuid, p_total numeric) returns void language plpgsql as $$
begin
  insert into public.so_credit (id, credit_number, status, customer_id, store_customer_id, currency_id, currency_code, invoice_id, ref_invoice_number, ref_order_number, reason, warehouse_id, warehouse_name, issued_on, issued_by, lines_amount, fee_amount, tax_amount, total, order_discount_amount, freight_discount_amount, surcharge_amount)
  values (p_id, p_num, 'issued', p_cust, p_store, (select id from public.ref_currency where code = 'CAD'), 'CAD', p_inv, p_ref, case when p_ref is not null then 'SO-OLD-1' end, 'customer_return',
          (select id from public.ref_warehouse where name = 'Asung Trading Inc.'), 'Asung Trading Inc.', public.ims_today(), 'e3e3e3e3-0000-4000-8000-00000000000a', p_total, 0, 0, p_total, 0, 0, 0);
end $$;
-- INV1 A sale(일감 queued) · INV2 A sale(txn) · INV3 K 매장 · 청구처 P(txn) · INV4 A opening · INV5 A sale since 전(10-31) · INV6 A sale(txn · 취소용) · INV7 A sale(txn · 1013 용)
select pg_temp.mk_inv('13e00000-0000-4000-8000-000000000001', '9970001', 'sale', 'c3e00000-0000-4000-8000-00000000000a', 'QBO2E Store A', :'today'::date, array['c3e00000-0000-4000-8000-00000000000a'::uuid]);
select pg_temp.mk_inv('13e00000-0000-4000-8000-000000000002', '9970002', 'sale', 'c3e00000-0000-4000-8000-00000000000a', 'QBO2E Store A', :'today'::date, array['c3e00000-0000-4000-8000-00000000000a'::uuid]);
select pg_temp.mk_inv('13e00000-0000-4000-8000-000000000003', '9970003', 'sale', 'c3e00000-0000-4000-8000-000000000010', 'QBO2E Parent', :'today'::date, array['c3e00000-0000-4000-8000-000000000011'::uuid]);
select pg_temp.mk_inv('13e00000-0000-4000-8000-000000000004', '9970004', 'opening', 'c3e00000-0000-4000-8000-00000000000a', 'QBO2E Store A', '2026-10-01', '{}'::uuid[]);
select pg_temp.mk_inv('13e00000-0000-4000-8000-000000000005', '9970005', 'sale', 'c3e00000-0000-4000-8000-00000000000a', 'QBO2E Store A', '2026-10-31', array['c3e00000-0000-4000-8000-00000000000a'::uuid]);
select pg_temp.mk_inv('13e00000-0000-4000-8000-000000000006', '9970006', 'sale', 'c3e00000-0000-4000-8000-00000000000a', 'QBO2E Store A', :'today'::date, array['c3e00000-0000-4000-8000-00000000000a'::uuid]);
select pg_temp.mk_inv('13e00000-0000-4000-8000-000000000007', '9970007', 'sale', 'c3e00000-0000-4000-8000-00000000000a', 'QBO2E Store A', :'today'::date, array['c3e00000-0000-4000-8000-00000000000a'::uuid]);
-- 크레딧: CR1 A(INV2 의 크레딧 · txn) · CR2 A(참조 · 일감 queued) · CR3 K 매장 · 청구처 P(txn) · CR4 A(txn) · CR5 A(txn)
select pg_temp.mk_cr('33e00000-0000-4000-8000-000000000001', 'CR-99901', '13e00000-0000-4000-8000-000000000002', null, 'c3e00000-0000-4000-8000-00000000000a', 'c3e00000-0000-4000-8000-00000000000a', 20);
select pg_temp.mk_cr('33e00000-0000-4000-8000-000000000002', 'CR-99902', null, 'OLD-2', 'c3e00000-0000-4000-8000-00000000000a', 'c3e00000-0000-4000-8000-00000000000a', 5);
select pg_temp.mk_cr('33e00000-0000-4000-8000-000000000003', 'CR-99903', null, 'OLD-3', 'c3e00000-0000-4000-8000-000000000010', 'c3e00000-0000-4000-8000-000000000011', 5);
select pg_temp.mk_cr('33e00000-0000-4000-8000-000000000004', 'CR-99904', null, 'OLD-4', 'c3e00000-0000-4000-8000-00000000000a', 'c3e00000-0000-4000-8000-00000000000a', 5);
select pg_temp.mk_cr('33e00000-0000-4000-8000-000000000005', 'CR-99905', null, 'OLD-5', 'c3e00000-0000-4000-8000-00000000000a', 'c3e00000-0000-4000-8000-00000000000a', 10);
set constraints all immediate;
update public.qbo_job set state = 'sent', qbo_id = 'INV-2E-' || right(ims_id, 1), qbo_name = '997000' || right(ims_id, 1), sent_at = now() where kind = 'invoice' and ims_id in ('13e00000-0000-4000-8000-000000000002', '13e00000-0000-4000-8000-000000000003', '13e00000-0000-4000-8000-000000000006', '13e00000-0000-4000-8000-000000000007');
update public.qbo_job set state = 'sent', qbo_id = 'CM-2E-' || right(ims_id, 1), qbo_name = 'CR-9990' || right(ims_id, 1), sent_at = now() where kind = 'credit' and ims_id in ('33e00000-0000-4000-8000-000000000001', '33e00000-0000-4000-8000-000000000003', '33e00000-0000-4000-8000-000000000004', '33e00000-0000-4000-8000-000000000005');
insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, sent_at)
  select :'realm', 'invoice', x, 'Invoice', 'INV-2E-' || right(x, 1), '997000' || right(x, 1), '0', 10, 0, now() from unnest(array['13e00000-0000-4000-8000-000000000002', '13e00000-0000-4000-8000-000000000003', '13e00000-0000-4000-8000-000000000006', '13e00000-0000-4000-8000-000000000007']) x
  union all select :'realm', 'credit', x, 'CreditMemo', 'CM-2E-' || right(x, 1), 'CR-9990' || right(x, 1), '0', case right(x, 1) when '1' then 20 when '5' then 10 else 5 end, 0, now() from unnest(array['33e00000-0000-4000-8000-000000000001', '33e00000-0000-4000-8000-000000000003', '33e00000-0000-4000-8000-000000000004', '33e00000-0000-4000-8000-000000000005']) x;
select pg_temp.job('invoice', '13e00000-0000-4000-8000-000000000001')::text as jinv1, pg_temp.job('credit', '33e00000-0000-4000-8000-000000000002')::text as jcr2 \gset

-- ── A) 착지 ──
select pg_temp.chk('A1 CHECK — qbo_job kind 10 · ims_kind credit_alloc · pair · qbo_txn kind credit_alloc · pair ELSE Payment 그대로', (select string_agg((pg_get_constraintdef(oid) ~* 'credit_alloc|credit_apply')::text, ',' order by conname) from pg_constraint where conname in ('qbo_job_kind_ck', 'qbo_job_ims_kind_ck', 'qbo_job_pair_ck', 'qbo_txn_kind_ck'))
  || ' | ' || (select pg_get_constraintdef(oid) ~ 'ELSE ''Payment''' from pg_constraint where conname = 'qbo_txn_pair_ck')::text, 'true,true,true,true | true');
select pg_temp.chk('A2 트리거 so_credit_alloc_qbo — deferrable · AFTER INSERT OR UPDATE OF voided_at · 결제 트리거 둘 그대로', (select string_agg(t.tgname || ':' || c.relname || ':' || case when t.tgdeferrable and t.tginitdeferred then 'deferred' else 'immediate' end, ',' order by t.tgname) from pg_trigger t join pg_class c on c.oid = t.tgrelid where t.tgname in ('so_credit_alloc_qbo', 'so_payment_alloc_qbo', 'so_payment_qbo_status'))
  || ' | ' || (select pg_get_triggerdef(oid) ~ 'AFTER INSERT OR UPDATE OF voided_at' from pg_trigger where tgname = 'so_credit_alloc_qbo')::text, 'so_credit_alloc_qbo:so_credit_alloc:deferred,so_payment_alloc_qbo:so_payment_alloc:deferred,so_payment_qbo_status:so_payment:immediate | true');
select pg_temp.chk('A3 nowhere — 새 함수 · 재발행 일곱의 깊이 0 WHERE 없는 update · delete = 0', (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_credit_alloc_sync', 'qbo_credit_apply_backfill', 'qbo_job_on_credit_alloc', 'qbo_payment_requeue', 'qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc')),
  'qbo_credit_alloc_sync=0 qbo_credit_apply_backfill=0 qbo_job_claim=0 qbo_job_doc=0 qbo_job_done=0 qbo_job_list=0 qbo_job_on_credit_alloc=0 qbo_job_preview=0 qbo_job_retry=0 qbo_payment_requeue=0');
select pg_temp.chk('A4 ACL — 새 함수 grant 0 · done · claim service_role · retry authenticated · requeue grant 0', (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_credit_apply_body', 'qbo_credit_apply_void_body', 'qbo_credit_alloc_sync', 'qbo_job_on_credit_alloc', 'qbo_credit_apply_backfill', 'qbo_payment_requeue', 'qbo_job_done', 'qbo_job_claim', 'qbo_job_retry')),
  'qbo_credit_alloc_sync={postgres=X/postgres} qbo_credit_apply_backfill={postgres=X/postgres} qbo_credit_apply_body={postgres=X/postgres} qbo_credit_apply_void_body={postgres=X/postgres} qbo_job_claim={postgres=X/postgres,service_role=X/postgres} qbo_job_done={postgres=X/postgres,service_role=X/postgres} qbo_job_on_credit_alloc={postgres=X/postgres} qbo_job_retry={postgres=X/postgres,authenticated=X/postgres} qbo_payment_requeue={postgres=X/postgres}');
select pg_temp.chk('A5 결제 넷 무변(2e-1b md5) — 몸 · void 몸 · sync · 지문', (select string_agg(left(md5(p.prosrc), 8), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_payment_body', 'qbo_payment_fingerprint', 'qbo_payment_sync', 'qbo_payment_void_body')), 'e1aea518 d6da0342 9efb5d9f 4ddb45cd');

-- ── B) 백필(실물 · 파일 안에서 돌았다) · 실물 claim ──
\if :{?mig}
select pg_temp.chk('B1 백필 — credit_apply 일감 수 = 백필 범위(실물 1 = CR-01008 → 60026) · queued · 가짜 제외', (select count(*)::text || ' ' || string_agg(j.state || ':' || (j.ims_id = :'real_alloc')::text, ',') from public.qbo_job j where j.ims_kind = 'credit_alloc' and j.ims_id not like '%-0000-4000-8000-%'), :n_scope || ' queued:true');
select pg_temp.svc(format($q$ select public.qbo_job_claim(50, array['credit_apply', 'credit_apply_void'], array[%L]::uuid[])::text $q$, pg_temp.job('credit_apply', :'real_alloc'))) as clr \gset
select pg_temp.chk('B2 실물 claim — blocked_for_invoice 1 · blocked_by = CR-01008 credit 일감(queued) · 글 「waiting for credit note CR-01008 …」(rollback 됨)', (:'clr'::jsonb->>'claimed') || ' ' || (:'clr'::jsonb->>'blocked_for_invoice') || ' | ' || (select j.state || ' ' || (j.blocked_by::text = :'real_crjob')::text || ' ' || j.warning from public.qbo_job j where j.id = pg_temp.job('credit_apply', :'real_alloc')), '1 1 | blocked true waiting for credit note CR-01008 to reach QuickBooks first');
\else
select pg_temp.chk('B1 (적용 뒤) 실물 붙임 CR-01008 → 60026 의 credit_apply 일감이 있다', (select count(*)::text from public.qbo_job j where j.ims_kind = 'credit_alloc' and j.ims_id = :'real_alloc'), '1');
\endif

-- ── C) 붙임 넣기(창구 · 트리거) · 몸 ──
select public.so_credit_alloc_add('33e00000-0000-4000-8000-000000000001', '13e00000-0000-4000-8000-000000000002', 3, 'auto', 'e3e3e3e3-0000-4000-8000-00000000000a', null) as a1 \gset
select (:'a1'::public.so_credit_alloc).id::text as al1 \gset
select pg_temp.bk(format($q$ select (public.so_credit_attach(%L, %L::jsonb))->'allocations'->0->>'alloc_id' $q$, '33e00000-0000-4000-8000-000000000002', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000002', 'amount', 2))::text)) as al2 \gset
select pg_temp.bk(format($q$ select (public.so_credit_attach(%L, %L::jsonb))->'allocations'->0->>'alloc_id' $q$, '33e00000-0000-4000-8000-000000000001', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000001', 'amount', 1))::text)) as al3 \gset
select pg_temp.bk(format($q$ select (public.so_credit_attach(%L, %L::jsonb))->'allocations'->0->>'alloc_id' $q$, '33e00000-0000-4000-8000-000000000001', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000004', 'amount', 1))::text)) as al4 \gset
select pg_temp.bk(format($q$ select (public.so_credit_attach(%L, %L::jsonb))->'allocations'->0->>'alloc_id' $q$, '33e00000-0000-4000-8000-000000000001', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000005', 'amount', 1))::text)) as al5 \gset
-- 환불 대상(2e-3): 환불 결제 직접 + 붙임 직접 · 매장 다름: CR3(K) → INV2(A) 직접(창구는 막는다 · 몸의 울타리를 본다)
insert into public.so_payment (id, kind, amount, paid_on, method, customer_id, currency_id, account_id, warehouse_id, status, created_by) values ('43e00000-0000-4000-8000-000000000001', 'refund', 2, public.ims_today(), 'cash', 'c3e00000-0000-4000-8000-00000000000a', :'cad_id', :'acct105', :'tor_id', 'active', 'e3e3e3e3-0000-4000-8000-00000000000a');
insert into public.so_credit_alloc (id, credit_id, refund_payment_id, amount, source, created_by) values ('53e00000-0000-4000-8000-000000000006', '33e00000-0000-4000-8000-000000000001', '43e00000-0000-4000-8000-000000000001', 2, 'manual', 'e3e3e3e3-0000-4000-8000-00000000000a');
insert into public.so_credit_alloc (id, credit_id, invoice_id, amount, source, created_by) values ('53e00000-0000-4000-8000-000000000007', '33e00000-0000-4000-8000-000000000003', '13e00000-0000-4000-8000-000000000002', 1, 'manual', 'e3e3e3e3-0000-4000-8000-00000000000a');
select pg_temp.chk('C1 넣기 — auto(al1) · Attach(al2 ~ al5) · 매장 다름(al7) 은 트리거가 credit_apply queued · 환불 대상(al6)은 일감 없음', (select count(*)::text || ' ' || string_agg(j.state, ',') from public.qbo_job j where j.kind = 'credit_apply' and j.ims_id in (:'al1', :'al2', :'al3', :'al4', :'al5', '53e00000-0000-4000-8000-000000000007')) || ' | ' || (select count(*)::text from public.qbo_job j where j.ims_id = '53e00000-0000-4000-8000-000000000006'), '6 queued,queued,queued,queued,queued,queued | 0');
select public.qbo_credit_apply_body(:'al1'::uuid)::text as b1 \gset
select pg_temp.chk('C2 al1 몸(CR1 → INV2 · 둘 다 QBO) — CustomerRef C-2E-A · TxnDate 오늘 · TotalAmt 0 · CurrencyRef CAD · 수단 · 입금 계좌 · PaymentRefNum 없음 · PrivateNote · Line 둘(Invoice INV-2E-2 · CreditMemo CM-2E-1 · 3) · check_lines 둘(txn_type) · lookup · wait null · needs 0 · fingerprint null',
  (:'b1'::jsonb->'body'->'CustomerRef'->>'value') || ' ' || (:'b1'::jsonb->'body'->>'TxnDate') || ' ' || (:'b1'::jsonb->'body'->>'TotalAmt') || ' ' || (:'b1'::jsonb->'body'->'CurrencyRef'->>'value') || ' ' || (:'b1'::jsonb->'body' ?| array['PaymentMethodRef', 'DepositToAccountRef', 'PaymentRefNum'])::text || ' ' || (:'b1'::jsonb->'body'->>'PrivateNote' = 'IMS credit applied ' || :'al1')::text
  || ' | ' || (:'b1'::jsonb->'body'->'Line'->0->'LinkedTxn'->0->>'TxnId') || ' ' || (:'b1'::jsonb->'body'->'Line'->0->'LinkedTxn'->0->>'TxnType') || ' ' || (:'b1'::jsonb->'body'->'Line'->0->>'Amount') || ' ' || (:'b1'::jsonb->'body'->'Line'->1->'LinkedTxn'->0->>'TxnId') || ' ' || (:'b1'::jsonb->'body'->'Line'->1->'LinkedTxn'->0->>'TxnType') || ' ' || (:'b1'::jsonb->'body'->'Line'->1->>'Amount')
  || ' | ' || (:'b1'::jsonb->'check_lines'->0->>'txn_type') || ' ' || (:'b1'::jsonb->'check_lines'->0->>'invoice_number') || ' ' || (:'b1'::jsonb->'check_lines'->0->>'qbo_invoice_id') || ' ' || (:'b1'::jsonb->'check_lines'->1->>'txn_type') || ' ' || (:'b1'::jsonb->'check_lines'->1->>'credit_number') || ' ' || (:'b1'::jsonb->'check_lines'->1->>'qbo_creditmemo_id') || ' ' || (:'b1'::jsonb->'check_lines'->1->>'amount')
  || ' | ' || (:'b1'::jsonb->'lookup'->>'private_note' = 'IMS credit applied ' || :'al1')::text || ' ' || (:'b1'::jsonb->'lookup'->>'total_amt') || ' ' || (:'b1'::jsonb->'lookup'->>'customer_ref') || ' | ' || coalesce(:'b1'::jsonb->>'wait_job', 'null') || ' ' || jsonb_array_length(:'b1'::jsonb->'needs')::text || ' ' || (:'b1'::jsonb->'fingerprint')::text || ' ' || (:'b1'::jsonb->>'name'),
  'C-2E-A ' || :'today' || ' 0 CAD false true | INV-2E-2 Invoice 3 CM-2E-1 CreditMemo 3 | Invoice 9970002 INV-2E-2 CreditMemo CR-99901 CM-2E-1 3 | true 0 C-2E-A | null 0 null CR-99901 → 9970002');
select public.qbo_credit_apply_body(:'al2'::uuid)::text as b2 \gset
select pg_temp.chk('C3 al2 몸(CR2 안 보냄) — wait_job = CR2 credit 일감 · wait_reason 「credit note CR-99902」 · Line 0', coalesce(:'b2'::jsonb->>'wait_job', 'null') || ' | ' || (:'b2'::jsonb->>'wait_reason') || ' | ' || (:'b2'::jsonb->>'line_count'), :'jcr2' || ' | waiting for credit note CR-99902 to reach QuickBooks first | 0');
select public.qbo_credit_apply_body(:'al3'::uuid)::text as b3 \gset
select pg_temp.chk('C4 al3 몸(CR1 → INV1 · 인보이스 안 보냄) — wait_job = INV1 일감 · wait_reason 「invoice 9970001」', coalesce(:'b3'::jsonb->>'wait_job', 'null') || ' | ' || (:'b3'::jsonb->>'wait_reason'), :'jinv1' || ' | waiting for invoice 9970001 to reach QuickBooks first');
select pg_temp.chk('C5 몸 거부 글 — al4 이월 · al5 since 전 · al7 매장 다름 · al6 환불 대상', pg_temp.try(format('select public.qbo_credit_apply_body(%L)::text', :'al4')) || ' | ' || pg_temp.try(format('select public.qbo_credit_apply_body(%L)::text', :'al5')) || ' | ' || pg_temp.try('select public.qbo_credit_apply_body(''53e00000-0000-4000-8000-000000000007'')::text') || ' | ' || pg_temp.try('select public.qbo_credit_apply_body(''53e00000-0000-4000-8000-000000000006'')::text'),
  'ERR P0001: Invoice 9970004 was carried over from the previous system and has no QuickBooks match yet — match it under Settings → QuickBooks → Opening invoices; this credit application then goes by itself — nothing was sent | ERR P0001: Invoice 9970005 was issued before the QuickBooks start date and has no QuickBooks match — match it under Settings → QuickBooks → Opening invoices — nothing was sent | ERR P0001: Credit note CR-99903 belongs to store QBO2E Kid Store but invoice 9970002 is for store QBO2E Store A — detach it (a credit note applies only to invoices of its own store) — nothing was sent | ERR P0001: Credit note CR-99901 pays a refund — refunds go to QuickBooks in a later step (2e-3) — nothing was sent');
select pg_temp.chk('C6 void 몸 — 보낸 적 없음 → 거부', pg_temp.try(format('select public.qbo_credit_apply_void_body(%L)::text', :'al1')), 'ERR P0001: Credit application CR-99901 → 9970002 was never sent to QuickBooks — nothing to void');
-- 1013: INV7 에 결제 P1(sent) → 떼기 → payment_void queued → CR4 → INV7 붙이면 그 void 뒤
select pg_temp.bk(format($q$ select (public.so_payment_add(%L::jsonb))->>'payment_id' $q$, jsonb_build_object('customer_id', 'c3e00000-0000-4000-8000-00000000000a', 'amount', 4, 'method', 'cash', 'reference', '2E2-P1', 'currency_code', 'CAD', 'warehouse_id', :'tor_id', 'allocations', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000007', 'amount', 4)))::text)) as p1 \gset
select pg_temp.svc(format($q$ select (public.qbo_job_claim(50, array['payment'], array[%L]::uuid[]))->>'claimed' $q$, pg_temp.job('payment', :'p1'))) as clp \gset
select pg_temp.svc(format('select (public.qbo_job_done(%L, ''PAY-2E2-P1'', ''2E2-P1'', ''0'', ''tid-p1'', null, null, 4, null, 0))->>''state''', pg_temp.job('payment', :'p1'))) as dp \gset
select pg_temp.bk(format($q$ select (public.so_payment_detach(%L, 'test detach'))->>'payment_id' $q$, (select a.id from public.so_payment_alloc a where a.payment_id = :'p1'::uuid and a.voided_at is null))) as dtp \gset
select pg_temp.bk(format($q$ select (public.so_credit_attach(%L, %L::jsonb))->'allocations'->0->>'alloc_id' $q$, '33e00000-0000-4000-8000-000000000004', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000007', 'amount', 1))::text)) as al8 \gset
select public.qbo_credit_apply_body(:'al8'::uuid)::text as b8 \gset
select pg_temp.chk('C7 1013 — P1 sent(' || :'clp' || ' ' || :'dp' || ') → 떼기 → payment_void queued · al8(CR4 → INV7) 몸은 그 void 뒤(wait_job · 글 「void of payment 2E2-P1 on invoice 9970007 … queued」)', (select pg_temp.jobs(:'p1')) || ' | ' || (:'b8'::jsonb->>'wait_job' = pg_temp.job('payment_void', :'p1')::text)::text || ' ' || (:'b8'::jsonb->>'wait_reason'),
  'payment:sent,payment_void:queued | true waiting for the void of payment 2E2-P1 on invoice 9970007 to reach QuickBooks first (that job is queued)');
update public.qbo_job set state = 'failed', last_error = 'test: QuickBooks refused' where id = pg_temp.job('payment_void', :'p1');
select public.qbo_credit_apply_body(:'al8'::uuid)::text as b8b \gset
update public.qbo_job set state = 'sent', qbo_id = 'PAY-2E2-P1', sent_at = now(), last_error = null where id = pg_temp.job('payment_void', :'p1');
update public.qbo_txn set voided_at = now() where ims_kind = 'payment' and ims_id = :'p1';
select public.qbo_credit_apply_body(:'al8'::uuid)::text as b8c \gset
select pg_temp.chk('C8 1013 — void 가 failed 면 글에 「retry or skip it first」 · void 가 sent 되면 wait 없음 · Line 둘', (:'b8b'::jsonb->>'wait_reason') || ' | ' || coalesce(:'b8c'::jsonb->>'wait_job', 'null') || ' ' || (:'b8c'::jsonb->>'line_count'),
  'waiting for the void of payment 2E2-P1 on invoice 9970007 to reach QuickBooks first (that job is failed — retry or skip it first) | null 2');

-- ── D) claim · done · reconcile · 떼기 · 취소 ──
select pg_temp.svc(format($q$ select public.qbo_job_claim(50, array['credit_apply', 'credit_apply_void'], array[%L, %L, %L, %L, %L, %L]::uuid[])::text $q$, pg_temp.job('credit_apply', :'al1'), pg_temp.job('credit_apply', :'al2'), pg_temp.job('credit_apply', :'al3'), pg_temp.job('credit_apply', :'al4'), pg_temp.job('credit_apply', :'al5'), pg_temp.job('credit_apply', '53e00000-0000-4000-8000-000000000007'))) as cl \gset
select pg_temp.chk('D1 claim 여섯 — al1 claimed(jobs 1 · kind · body TotalAmt 0 · check_lines 2 · lookup · fingerprint null) · al2 · al3 blocked_for_invoice(wait_reason 이 warning 에) · al4 · al5 · al7 failed',
  (:'cl'::jsonb->>'claimed') || ' ' || (:'cl'::jsonb->>'blocked_for_invoice') || ' ' || (:'cl'::jsonb->>'blocked_for_needs') || ' ' || (:'cl'::jsonb->>'body_failed') || ' | ' || jsonb_array_length(:'cl'::jsonb->'jobs')::text || ' ' || (:'cl'::jsonb->'jobs'->0->>'kind') || ' ' || (:'cl'::jsonb->'jobs'->0->'body'->>'TotalAmt') || ' ' || jsonb_array_length(:'cl'::jsonb->'jobs'->0->'check_lines')::text || ' ' || (:'cl'::jsonb->'jobs'->0->'lookup'->>'customer_ref') || ' ' || coalesce(:'cl'::jsonb->'jobs'->0->>'fingerprint', 'null')
  || ' | ' || (select j.state || ':' || (j.blocked_by::text = :'jcr2')::text || ':' || j.warning from public.qbo_job j where j.id = pg_temp.job('credit_apply', :'al2')) || ' | ' || (select j.state || ':' || (j.blocked_by::text = :'jinv1')::text from public.qbo_job j where j.id = pg_temp.job('credit_apply', :'al3')),
  '6 2 0 3 | 1 credit_apply 0 2 C-2E-A null | blocked:true:waiting for credit note CR-99902 to reach QuickBooks first | blocked:true');
select pg_temp.bk(format('select public.qbo_job_preview(%L)::text', pg_temp.job('credit_apply', :'al2'))) as pv \gset
select pg_temp.chk('D2 preview al2 — wait(reason · job = CR2 일감) · blocked_by kind credit · sendable false · doc(CR-99902 → 9970002 · 매장 · 2 · active) · check_lines 0',
  (:'pv'::jsonb->'wait'->>'reason') || ' ' || (:'pv'::jsonb->'wait'->>'job_id' = :'jcr2')::text || ' | ' || (:'pv'::jsonb->'blocked_by'->>'kind') || ' ' || (:'pv'::jsonb->>'sendable') || ' | ' || (:'pv'::jsonb->'doc'->>'doc_number') || ' ' || (:'pv'::jsonb->'doc'->>'name') || ' ' || (:'pv'::jsonb->'doc'->>'total') || ' ' || (:'pv'::jsonb->'doc'->>'doc_status') || ' | ' || jsonb_array_length(:'pv'::jsonb->'check_lines')::text,
  'waiting for credit note CR-99902 to reach QuickBooks first true | credit false | CR-99902 → 9970002 QBO2E Store A 2 active | 0');
select pg_temp.svc(format('select public.qbo_job_done(%L, ''PAY-2E2-1'', ''CR-99901 → 9970002'', ''0'', ''tid-1'', null, null, 0, null, 0)::text', pg_temp.job('credit_apply', :'al1'))) as d1 \gset
select pg_temp.chk('D3 done al1 — sent · qbo_txn(credit_alloc · Payment · PAY-2E2-1 · doc_number · total 0 · fingerprint null · source sent) · mismatch null · reconcile same',
  (:'d1'::jsonb->>'state') || ' ' || coalesce(:'d1'::jsonb->>'mismatch', 'null') || ' ' || (:'d1'::jsonb->'reconcile'->>'action') || ' | ' || (select t.ims_kind || ' ' || t.qbo_type || ' ' || t.qbo_id || ' ' || t.doc_number || ' ' || t.total_amt::text || ' ' || coalesce(t.fingerprint, 'null') || ' ' || t.source from public.qbo_txn t where t.ims_kind = 'credit_alloc' and t.ims_id = :'al1'),
  'sent null same | credit_alloc Payment PAY-2E2-1 CR-99901 → 9970002 0 null sent');
-- 대조: CR5 → INV2 1 · done 에 TotalAmt 1 → mismatch + warning · sent
select pg_temp.bk(format($q$ select (public.so_credit_attach(%L, %L::jsonb))->'allocations'->0->>'alloc_id' $q$, '33e00000-0000-4000-8000-000000000005', jsonb_build_array(jsonb_build_object('invoice_id', '13e00000-0000-4000-8000-000000000002', 'amount', 1))::text)) as al9 \gset
select pg_temp.svc(format($q$ select (public.qbo_job_claim(50, array['credit_apply'], array[%L]::uuid[]))->>'claimed' $q$, pg_temp.job('credit_apply', :'al9'))) as cl9 \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''PAY-2E2-9'', ''CR-99905 → 9970002'', ''0'', ''tid-9'', null, null, 1, null, 1)::text', pg_temp.job('credit_apply', :'al9'))) as d9 \gset
select pg_temp.chk('D4 done al9 with TotalAmt 1 — sent · mismatch 「is not 0」 · warning · txn mismatch', (:'d9'::jsonb->>'state') || ' | ' || (:'d9'::jsonb->>'mismatch') || ' | ' || (select (j.warning = t.mismatch)::text from public.qbo_job j join public.qbo_txn t on t.ims_kind = 'credit_alloc' and t.ims_id = j.ims_id where j.ims_id = :'al9' and j.kind = 'credit_apply'),
  'sent | QuickBooks total 1 is not 0 — check credit application CR-99905 → 9970002 in QuickBooks (942) | true');
-- 떼기(sent 뒤) → void 일감 · void 몸 · claim · done
select pg_temp.bk(format($q$ select (public.so_credit_detach(%L, 'test detach'))->>'alloc_id' $q$, :'al1')) as dt1 \gset
select public.qbo_credit_apply_void_body(:'al1'::uuid)::text as vb \gset
select pg_temp.chk('D5 al1 떼기 — credit_apply_void queued(note) · void 몸 Id PAY-2E2-1 · SyncToken 0 · sparse · lookup private_note', (select pg_temp.jobs(:'al1')) || ' | ' || (select (j.note like '%detached — void the zero payment%')::text from public.qbo_job j where j.id = pg_temp.job('credit_apply_void', :'al1')) || ' | ' || (:'vb'::jsonb->'body'->>'Id') || ' ' || (:'vb'::jsonb->'body'->>'SyncToken') || ' ' || (:'vb'::jsonb->'body'->>'sparse') || ' ' || (:'vb'::jsonb->'lookup'->>'private_note' = 'IMS credit applied ' || :'al1')::text,
  'credit_apply:sent,credit_apply_void:queued | true | PAY-2E2-1 0 true true');
select pg_temp.svc(format($q$ select (public.qbo_job_claim(50, array['credit_apply', 'credit_apply_void'], array[%L]::uuid[]))->>'claimed' $q$, pg_temp.job('credit_apply_void', :'al1'))) as clv \gset
select pg_temp.svc(format('select public.qbo_job_done(%L, ''PAY-2E2-1'', ''CR-99901 → 9970002'', ''1'', ''tid-v1'', null, null)::text', pg_temp.job('credit_apply_void', :'al1'))) as dv \gset
select pg_temp.chk('D6 void claim · done — sent · qbo_txn voided_at · reconcile none(7 인자 호출 그대로 됨)', :'clv' || ' ' || (:'dv'::jsonb->>'state') || ' ' || (:'dv'::jsonb->'reconcile'->>'action') || ' | ' || (select (t.voided_at is not null)::text from public.qbo_txn t where t.ims_kind = 'credit_alloc' and t.ims_id = :'al1'), '1 sent none | true');
-- 안 보낸 붙임 떼기 → skipped · 보내는 중 떼기 → void blocked_by 그 일감 → done 이 푼다
select pg_temp.bk(format($q$ select (public.so_credit_detach(%L, 'test detach 2'))->>'alloc_id' $q$, :'al2')) as dt2 \gset
select pg_temp.svc(format($q$ select (public.qbo_job_claim(50, array['credit_apply'], array[%L]::uuid[]))->>'claimed' $q$, pg_temp.job('credit_apply', :'al8'))) as cl8 \gset
select pg_temp.bk(format($q$ select (public.so_credit_detach(%L, 'test detach 3'))->>'alloc_id' $q$, :'al8')) as dt8 \gset
select pg_temp.chk('D7 al2(blocked) 떼기 → skipped 「detached before sending」 · al8 sending 중 떼기 → credit_apply_void blocked_by 그 일감', (select pg_temp.jobs(:'al2')) || ' ' || (select (j.note like '%detached before sending%')::text from public.qbo_job j where j.ims_id = :'al2' and j.kind = 'credit_apply') || ' | ' || :'cl8' || ' ' || (select j.state || ' ' || (j.blocked_by = pg_temp.job('credit_apply', :'al8'))::text || ' ' || j.note from public.qbo_job j where j.id = pg_temp.job('credit_apply_void', :'al8')),
  'credit_apply:skipped true | 1 blocked true detached while sending — void after the send settles');
select pg_temp.svc(format('select public.qbo_job_done(%L, ''PAY-2E2-8'', ''CR-99904 → 9970007'', ''0'', ''tid-8'', null, null, 0, null, 0)::text', pg_temp.job('credit_apply', :'al8'))) as d8 \gset
select pg_temp.chk('D8 al8 done — sent · unblocked 1(void → queued) · reconcile void', (:'d8'::jsonb->>'state') || ' ' || (:'d8'::jsonb->>'unblocked') || ' ' || (:'d8'::jsonb->'reconcile'->>'action') || ' | ' || (select pg_temp.jobs(:'al8')), 'sent 1 void | credit_apply:sent,credit_apply_void:queued');
-- 인보이스 취소: INV6 에 auto 붙임(CR5) sent → 취소 → 붙임 void → credit_apply_void queued · invoice_void 일감도
select pg_temp.fulfill('13e00000-0000-4000-8000-000000000006') as ff \gset
select public.so_credit_alloc_add('33e00000-0000-4000-8000-000000000005', '13e00000-0000-4000-8000-000000000006', 2, 'auto', 'e3e3e3e3-0000-4000-8000-00000000000a', null) as a6 \gset
select (:'a6'::public.so_credit_alloc).id::text as al6b \gset
select pg_temp.svc(format($q$ select (public.qbo_job_claim(50, array['credit_apply'], array[%L]::uuid[]))->>'claimed' $q$, pg_temp.job('credit_apply', :'al6b'))) as cl6 \gset
select pg_temp.svc(format('select (public.qbo_job_done(%L, ''PAY-2E2-6'', ''CR-99905 → 9970006'', ''0'', ''tid-6'', null, null, 0, null, 0))->>''state''', pg_temp.job('credit_apply', :'al6b'))) as d6 \gset
select pg_temp.bk($q$ select (public.so_invoice_cancel('13e00000-0000-4000-8000-000000000006', 'test cancel'))->>'invoice_id' $q$) as cx \gset
select pg_temp.chk('D9 인보이스 취소(' || :'cl6' || ' ' || :'d6' || ') — 붙임 void → credit_apply_void queued · invoice_void 일감 queued · 인보이스 cancelled', :'cx' || ' | ' || (select pg_temp.jobs(:'al6b')) || ' | ' || (select pg_temp.jobs('13e00000-0000-4000-8000-000000000006')) || ' | ' || (select i.status from public.so_invoice i where i.id = '13e00000-0000-4000-8000-000000000006'),
  '13e00000-0000-4000-8000-000000000006 | credit_apply:sent,credit_apply_void:queued | invoice:sent,invoice_void:queued | cancelled');

-- ── E) requeue · retry 규칙 · list · doc ──
select public.qbo_payment_requeue('13e00000-0000-4000-8000-000000000005'::uuid)::text as rq5 \gset
select pg_temp.chk('E1 requeue(INV5 since 전) — 수 1(결제 0 + 붙임 1) · al5 failed → queued(note)', :'rq5' || ' ' || (select j.state || ' ' || (j.note like 'sent again: invoice 9970005 is now matched%')::text from public.qbo_job j where j.id = pg_temp.job('credit_apply', :'al5')), '1 queued true');
select pg_temp.chk('E2 retry — al4(failed · 이월 · 활성) OK queued · al2 skipped(떼임) 는 거부 · al8 의 void(queued) 는 상태로 거부',
  pg_temp.bk(format('select (public.qbo_job_retry(%L, ''match later''))->>''state''', pg_temp.job('credit_apply', :'al4'))) || ' | ' || pg_temp.bk(format('select (public.qbo_job_retry(%L, ''why''))->>''state''', (select j.id from public.qbo_job j where j.ims_id = :'al2' and j.kind = 'credit_apply'))) || ' | ' || pg_temp.bk(format('select (public.qbo_job_retry(%L, ''why''))->>''state''', pg_temp.job('credit_apply_void', :'al8'))),
  'queued | ERR P0001: Credit application CR-99902 → 9970002 was detached (or pays a refund) — nothing to send (a void job takes care of QuickBooks) — nothing was saved | ERR P0001: Only a failed or skipped job, or one whose result is unknown, can be sent again (this one is queued) — nothing was saved');
select pg_temp.bk($q$ select public.qbo_job_list(null, array['credit_apply', 'credit_apply_void'], null, null, 'CR-999', 50, 0)::text $q$) as ls \gset
select pg_temp.chk('E3 list(kinds credit_apply · q CR-999) — 가짜 줄 수 = DB 일감 수 · al1 void 줄의 doc(번호 · 매장 · CAD · 3 · 오늘 · voided) · txn(PAY-2E2-1 · voided) · ims_name',
  (select count(*)::text from jsonb_array_elements(:'ls'::jsonb->'rows') r where r->>'ims_id' like '%-0000-4000-8000-%' or r->>'ims_id' in (:'al1', :'al2', :'al3', :'al4', :'al5', :'al8', :'al9', :'al6b')) || '=' || (select count(*)::text from public.qbo_job j where j.ims_kind = 'credit_alloc' and j.ims_id <> :'real_alloc')
  || ' | ' || (select (r->>'doc_number') || ' ' || (r->>'name') || ' ' || (r->>'currency') || ' ' || (r->>'total') || ' ' || (r->>'doc_date') || ' ' || (r->>'doc_status') || ' ' || (r->>'txn_qbo_id') || ' ' || (r->>'txn_voided_at' is not null)::text || ' | ' || (r->>'ims_name') from jsonb_array_elements(:'ls'::jsonb->'rows') r where r->>'ims_id' = :'al1' and r->>'kind' = 'credit_apply_void'),
  (select count(*)::text from public.qbo_job j where j.ims_kind = 'credit_alloc' and j.ims_id <> :'real_alloc') || '=' || (select count(*)::text from public.qbo_job j where j.ims_kind = 'credit_alloc' and j.ims_id <> :'real_alloc') || ' | CR-99901 → 9970002 QBO2E Store A CAD 3 ' || :'today' || ' voided PAY-2E2-1 true | CR-99901 → 9970002 · QBO2E Store A · CAD 3');
select pg_temp.chk('E4 qbo_job_doc(credit_alloc) — 환불 대상은 「CR → refund」 · 모르는 id 는 null · list 의 kinds 검사 10', (public.qbo_job_doc('credit_alloc', '53e00000-0000-4000-8000-000000000006')->>'doc_number') || ' | ' || coalesce(public.qbo_job_doc('credit_alloc', gen_random_uuid()::text)::text, 'null') || ' | ' || pg_temp.bk($q$ select (public.qbo_job_list(null, array['bogus']))->>'kinds' $q$),
  'CR-99901 → refund | null | ERR P0001: kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void (got {bogus})');
select pg_temp.chk('E5 claim kinds 검사 — 옛 EF 꼴(기본)은 붙임을 안 잡는다 · 결제 일감 · 지문 무변(P1 fingerprint 는 claim 때 적힌 값)', pg_temp.svc($q$ select (public.qbo_job_claim(5))->>'kinds' $q$) || ' | ' || (select (j.fingerprint is not null)::text from public.qbo_job j where j.kind = 'payment' and j.ims_id = :'p1'), '["customer", "item"] | true');
select pg_temp.chk('F1 바뀐 함수 = 재발행 일곱(claim · doc · done · list · preview · retry · payment_requeue) + 새 함수(t_pre 에 없음) · 그 밖 무변', (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5), case when :{?mig} then 'qbo_job_claim,qbo_job_doc,qbo_job_done,qbo_job_list,qbo_job_preview,qbo_job_retry,qbo_payment_requeue' else '(none)' end);

\echo '── 결과'
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.customer) = :n_cust0 as customer_same, (select count(*) from public.product) = :n_prod0 as product_same,
       (select count(*) from public.so) = :n_so0 as so_same, (select count(*) from public.so_invoice) = :n_inv0 as invoice_same, (select count(*) from public.so_credit) = :n_cr0 as credit_same, (select count(*) from public.so_credit_alloc) = :n_calloc0 as calloc_same, (select count(*) from public.so_payment) = :n_pay0 as payment_same,
       (select count(*) from public.qbo_job) = :n_job0 as job_same, (select count(*) from public.qbo_txn) = :n_txn0 as txn_same, (select count(*) from public.qbo_link) = :n_link0 as link_same,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same;
