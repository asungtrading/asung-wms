-- supabase/tests/qbo_sync_2e1a2_check.sql — qbo-sync-2e-1a2 검증: Shopify 결제 Deposit To = Clearing - Shopify _1150040029_(판정 993) — 기본값 2 행 · USD 행 없음 · 계좌 · QBO 짝 · add 길 · 그 밖 무변 (2026-11-02 밤)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback · ⚠️ 10 초 안
--   Claude Code(시험): MIG=supabase/migrations/20261103040000_qbo_sync_2e1a2_shopify_clearing.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2e1a2_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK 수는 EXPECT_OK
\set ON_ERROR_STOP on
\set EXPECT_OK 10
\pset pager off
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'qbo\_%' or p.proname like 'so\_%' or p.proname like 'shop\_%');
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.so_payment) as n_pay0, (select count(*) from public.so_payment_account_default) as n_def0,
       (select realm_id from public.qbo_connection where singleton) as realm,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as tor_id, (select id::text from public.ref_warehouse where name = 'Asung - Edmonton') as edm_id,
       (select id::text from public.ref_currency where code = 'CAD') as cad_id, (select id::text from public.ref_account where code = '_1150040029_') as a029_id,
       (select c.id::text from public.customer c where c.is_active order by c.created_at limit 1) as cust_id \gset
\echo '── 기준: 함수' :n_fn '· staff' :n_staff0 '· payments' :n_pay0 '· defaults' :n_def0 '· realm' :realm
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
create function pg_temp.mgr(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"e2e2e2e2-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values
  ('e2e2e2e2-0000-4000-8000-00000000000a', 'e2e2e2e2-0000-4000-8000-000000000001', 'qbo-sync-2e1a2-mgr@asung.invalid', 'QBO 2e1a2 Manager', 'manager', '["sales"]');

select pg_temp.chk('B1 shopify CAD TOR · EDM → _1150040029_', (select string_agg(d.account_code, ',' order by w.name) from public.so_payment_account_default d join public.ref_warehouse w on w.id = d.warehouse_id where d.method = 'shopify' and d.currency_code = 'CAD'), '_1150040029_,_1150040029_');
select pg_temp.chk('B2 shopify USD rows (none — 판정 2 「USD 없음」 그대로)', (select count(*)::text from public.so_payment_account_default d where d.method = 'shopify' and d.currency_code <> 'CAD'), '0');
select pg_temp.chk('B3 account_id matches account_code on every row', (select count(*)::text from public.so_payment_account_default d join public.ref_account a on a.id = d.account_id where a.code <> d.account_code), '0');
select pg_temp.chk('B4 rows still 24', (select count(*)::text from public.so_payment_account_default), '24');
select pg_temp.chk('B5 paypal _124_ · cheque CAD _105_ untouched (TOR)', (select string_agg(d.method || ':' || d.account_code, ',' order by d.method) from public.so_payment_account_default d join public.ref_warehouse w on w.id = d.warehouse_id where w.name = 'Asung Trading Inc.' and d.currency_code = 'CAD' and d.method in ('paypal', 'cheque')), 'cheque:_105_,paypal:_124_');
select pg_temp.chk('B6 _1150040029_ Clearing - Shopify · active BANK · QBO 짝 1150040029', (select a.name || ' · ' || a.account_type || ' · ' || a.is_active::text || ' · ' || coalesce((select l.qbo_id from public.qbo_link l where l.realm_id = :'realm' and l.ims_kind = 'account' and l.ims_id = a.id::text), 'none') from public.ref_account a where a.code = '_1150040029_'), 'Clearing - Shopify · BANK · true · 1150040029');
select pg_temp.chk('B7 so_payment_default_account(shopify, EDM, CAD) = _1150040029_', (select public.so_payment_default_account('shopify', :'edm_id'::uuid, :'cad_id'::uuid)::text), :'a029_id');
select pg_temp.chk('D1 add method shopify · TOR · CAD → account _1150040029_ (default)', pg_temp.mgr(format($q$ select (public.so_payment_add(%L::jsonb))->>'account_code' $q$,
       jsonb_build_object('customer_id', :'cust_id', 'amount', 9.99, 'method', 'shopify', 'reference', '2e1a2-D1', 'currency_code', 'CAD', 'warehouse_id', :'tor_id')::text)), '_1150040029_');
select pg_temp.chk('D2 add method shopify with an explicit account still allowed (_104_)', pg_temp.mgr(format($q$ select (public.so_payment_add(%L::jsonb))->>'account_code' $q$,
       jsonb_build_object('customer_id', :'cust_id', 'amount', 1, 'method', 'shopify', 'reference', '2e1a2-D2', 'currency_code', 'CAD', 'warehouse_id', :'tor_id', 'account_id', (select id from public.ref_account where code = '_104_'))::text)), '_104_');
select pg_temp.chk('F1 no function body changed', (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5), '(none)');

\echo '── 결과'
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.so_payment) = :n_pay0 as payment_same, (select count(*) from public.so_payment where reference like '2e1a2-D%') = 0 as test_payments_gone,
       (select count(*) from public.so_payment_account_default) = :n_def0 as defaults_same,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same;
