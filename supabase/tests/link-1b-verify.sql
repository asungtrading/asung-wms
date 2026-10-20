-- link-1b-verify.sql — shop_link_run 칸 넷 · 제약 shop_product_gid_real_ck(Product/0 거부) · link-1a 창구 넷 무접촉 · 실제 shop_product 행 무변
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261020180009_link_1b_bulk_cols_product0_ck.sql -f supabase/tests/link-1b-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 G0 는 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더

\echo '── db_role · schema_migrations'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261020180009' \gset
select :n_applied as schema_migrations_rows_for_20261020180009;

begin;
set local statement_timeout = '120s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return v;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;

\echo '── M0) 실제 shop_product 행 스냅샷(id 집합) · 가짜 스토어'
create temp table t_real_sp as select sp.id::text as id, sp.shopify_product_gid || '|' || coalesce(sp.last_hash, '') as v from public.shop_product sp;
select count(*) as n_real_sp, md5(coalesce(string_agg(id || v, '|' order by id), '')) as md5_real_sp from t_real_sp \gset
select id::text as tier from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
set local session_replication_role = replica;
insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, secret_prefix, oos_policy, is_active) values ('lk1b', 'ims-link1b-test.myshopify.com', 'LINK1B', 'asung', :'tier'::uuid, 'LINK1B', 'continue', true) returning id::text as store \gset
insert into public.product (sku, name, source, is_active, sellable) values ('LK1B-P0', 'LK1B product zero', 'manual', true, true) returning id::text as p0 \gset
set local session_replication_role = origin;
select pg_temp.chk(format('M0 %s real shop_product rows snapshotted · fake store · product', :n_real_sp), :'store' <> '' and :'p0' <> '', 'see M0');

\if :{?mig}
select pg_temp.run(format('insert into public.shop_product (store_id, product_id, shopify_product_gid, last_status, last_error) values (%L::uuid, %L::uuid, ''gid://shopify/Product/0'', ''error'', ''x'') returning id::text', :'store', :'p0')) as ins_old \gset
delete from public.shop_product where store_id = :'store'::uuid;
select pg_temp.chk('G0 before the trial: Product/0 placeholder is still accepted · no bulk_url column · not in schema_migrations',
  :'ins_old' not like 'ERR%' and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'shop_link_run' and column_name = 'bulk_url') and :n_applied = 0, format('ins_old %s · n_applied %s', left(:'ins_old', 80), :n_applied));
\echo '── \i 시험 적용'
\i :mig
\else
select pg_temp.chk('P0c confirm run: migration 20261020180009 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

\echo '── S1) 칸 넷 · 기본값 · 제약이 Product/0 을 거부 · 실제 gid 는 받는다 · link-1a 창구 넷 그대로'
select pg_temp.run(format('insert into public.shop_product (store_id, product_id, shopify_product_gid, last_status, last_error) values (%L::uuid, %L::uuid, ''gid://shopify/Product/0'', ''error'', ''x'') returning id::text', :'store', :'p0')) as ins_zero \gset
select pg_temp.run(format('insert into public.shop_product (store_id, product_id, shopify_product_gid, handle, shopify_status) values (%L::uuid, %L::uuid, ''gid://shopify/Product/555'', ''lk1b'', ''ACTIVE'') returning id::text', :'store', :'p0')) as ins_real \gset
select pg_temp.run(format('insert into public.shop_link_run (store_id, status) values (%L::uuid, ''reading'') returning coalesce(bulk_url, ''-'') || ''|'' || coalesce(bulk_status, ''-'') || ''|'' || coalesce(bulk_error, ''-'') || ''|'' || loaded_count', :'store')) as run_row \gset
select pg_temp.chk('S1 Product/0 insert refused by shop_product_gid_real_ck · real gid accepted · shop_link_run new columns default (null · null · null · 0) · four link-1a functions present',
  :'ins_zero' like 'ERR 23514%' and :'ins_zero' like '%shop_product_gid_real_ck%' and :'ins_real' not like 'ERR%'
  and :'run_row' = '-|-|-|0'
  and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_link_plan', 'shop_link_apply', 'shop_link_push_batch', 'shop_link_remaining')) = 4,
  format('zero %s | real %s | run %s', left(:'ins_zero', 160), left(:'ins_real', 80), :'run_row'));

\echo '── Z1) 실제 shop_product 행 무변'
select pg_temp.chk(format('Z1 %s real shop_product rows untouched', :n_real_sp),
  (select md5(coalesce(string_agg(t.id || t.v, '|' order by t.id), '')) from t_real_sp t join public.shop_product sp on sp.id::text = t.id and sp.shopify_product_gid || '|' || coalesce(sp.last_hash, '') = t.v) = :'md5_real_sp', 'see Z1');

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0'
select (select count(*) from public.shop_store where code = 'lk1b') + (select count(*) from public.product where sku like 'LK1B-%') as fake_traces_left;
