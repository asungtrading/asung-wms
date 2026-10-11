-- ord-1b-verify.sql — 받은 일 표 shop_order_inbox · shop_order_inbox_add · shop_store.orders_polled_at (Asung-IMS · 테스트)
--   기대: 시험 갈래(-v mig) OK 5 · 확인 갈래 OK 4(= 5 − 시험 전용 1: G0a) · MISMATCH 0 · 확인 갈래 전용 줄(\else)은 없다
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261011013000_ord_1b_inbox.sql -f supabase/tests/ord-1b-verify.sql > /tmp/ord-1b.out 2>&1; echo exit=$?
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료: 시험 스토어 test(읽기만) · 받은 일 줄은 전부 rollback · ⚠️ shop_order_inbox_id_seq 는 시험 적용이 만들어 rollback 으로 사라진다(시험 갈래) · 확인 갈래는 끝에서 greatest(max, 머리)로 되돌린다
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select coalesce((select last_value::text from pg_sequences where schemaname = 'public' and sequencename = 'shop_order_inbox_id_seq'), '0') as ib_seq_head \gset
begin;
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql security definer as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create function pg_temp.err_inv(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'no-error'; exception when others then return sqlstate || ' ' || sqlerrm; end $$;
\if :{?mig}
select pg_temp.chk('G0a trial marker: shop_order_inbox exists only after the trial apply', (to_regclass('public.shop_order_inbox') is not null)::text, 'true');
\endif
select id::text as store from public.shop_store where code = 'test' \gset
select pg_temp.chk('T1a table (rls on · select policy · webhook_id unique · gid check) · orders_polled_at column · inbox_add definer · authenticated: select only · no execute',
  (select relrowsecurity::text from pg_class where oid = 'public.shop_order_inbox'::regclass) || '/' || (select count(*)::text from pg_policies where tablename = 'shop_order_inbox' and cmd = 'SELECT') || '/' ||
  (select count(*)::text from pg_constraint where conrelid = 'public.shop_order_inbox'::regclass and conname in ('shop_order_inbox_webhook_uk', 'shop_order_inbox_gid_ck', 'shop_order_inbox_done_ck')) || '/' ||
  (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'shop_store' and column_name = 'orders_polled_at') || '/' ||
  (select prosecdef::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_inbox_add') || '/' ||
  has_table_privilege('authenticated', 'public.shop_order_inbox', 'select')::text || '/' || has_table_privilege('authenticated', 'public.shop_order_inbox', 'insert')::text || '/' || has_function_privilege('authenticated', 'public.shop_order_inbox_add(uuid, text, text, text, text)', 'execute')::text,
  'true/1/3/1/true/true/false/false');
select public.shop_order_inbox_add(:'store'::uuid, 'gid://shopify/Order/900000000001', 'orders/create', 'wh-1', 'ev-1') as i1 \gset
select coalesce(public.shop_order_inbox_add(:'store'::uuid, 'gid://shopify/Order/900000000001', 'orders/create', 'wh-1', 'ev-1')::text, 'null') as i2 \gset
select coalesce(public.shop_order_inbox_add(:'store'::uuid, 'gid://shopify/Order/900000000001', 'orders/updated', 'wh-2', 'ev-2')::text, 'null') as i3 \gset
select coalesce(public.shop_order_inbox_add(:'store'::uuid, 'gid://shopify/Order/900000000002', 'poll', null, null)::text, 'null') as i4 \gset
select coalesce(public.shop_order_inbox_add(:'store'::uuid, 'gid://shopify/Order/900000000002', 'poll', null, null)::text, 'null') as i5 \gset
update public.shop_order_inbox set started_at = now(), done_at = now(), result = 'created' where id = :i1;
select coalesce(public.shop_order_inbox_add(:'store'::uuid, 'gid://shopify/Order/900000000001', 'orders/updated', 'wh-2', 'ev-2')::text, 'null') as i6 \gset
select pg_temp.chk('T2a add: new row · same webhook again → null · another delivery for the same open order → null · poll row · poll again → null · after the first row is done, the new delivery → new row (open rows per order: one)',
  (:i1 > 0)::text || '/' || :'i2' || '/' || :'i3' || '/' || (:'i4' <> 'null')::text || '/' || :'i5' || '/' || (:'i6' <> 'null' and :'i6' <> :'i1'::text)::text || '/' || (select count(*)::text || ':' || count(*) filter (where done_at is null) from public.shop_order_inbox),
  'true/null/null/true/null/true/3:2');
select pg_temp.chk('T2b shape: bad gid → 23514 · done without result → 23514',
  left(pg_temp.err_inv(format('select public.shop_order_inbox_add(%L, %L, %L)', :'store', 'gid://shopify/Product/1', 'poll')), 5) || '/' ||
  left(pg_temp.err_inv(format('update public.shop_order_inbox set done_at = now() where id = %s', :i4)), 5),
  '23514/23514');
set local role authenticated;
select pg_temp.err_inv(format('select public.shop_order_inbox_add(%L, %L, %L)', :'store', 'gid://shopify/Order/1', 'poll')) as t2_auth \gset
select count(*)::text as t2_read from public.shop_order_inbox \gset
reset role;
select pg_temp.chk('T2c authenticated: inbox_add 42501 · reads the table (3 rows)', left(:'t2_auth', 5) || '/' || :'t2_read', '42501/3');
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select (to_regclass('public.shop_order_inbox') is not null)::text as has_ib \gset
\if :has_ib
select 'after rollback: inbox rows ' || (select count(*) from public.shop_order_inbox) || ' (applied DB — the trial leaves 0 new)';
select setval('public.shop_order_inbox_id_seq', greatest(coalesce((select max(id) from public.shop_order_inbox), 0), :ib_seq_head::bigint, 1), (select count(*) > 0 from public.shop_order_inbox));
select 'seq tail inbox ' || last_value || ' ' || is_called from public.shop_order_inbox_id_seq;
\else
select 'after rollback: shop_order_inbox does not exist (trial run — rolled back)';
\endif
