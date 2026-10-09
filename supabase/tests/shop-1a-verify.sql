-- shop-1a-verify.sql — Shopify 연동 ① 바탕 DB: shop_store · shop_location · shop_call_log · 권한 키 shopify · shop_store_save · shop_store_list · 시작값 (Asung-IMS · 테스트)
--   기대: 시험 갈래(-v mig) OK 20 · 확인 갈래 OK 19(= 20 − 시험 전용 1: G0a) · MISMATCH 0 · 확인 갈래 전용 줄(\else)은 없다 · 3회차 통과(1회차 7: T1c 기본 권한 references·trigger — 마이그레이션 고침 · T2b 뷰는 55000 · T3a·T4a 검사 순서 · T3d old_missing · T4b 열쇠 모양 + 1008 already_mapped · T6a jsonb 열쇠 순서 / 2회차 1: T4b 정렬 순서 — 기대 쪽)
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261009170919_shop_1a_store.sql -f supabase/tests/shop-1a-verify.sql > /tmp/shop-1a.out 2>&1; echo exit=$?
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료는 가짜만(스토어 shop1a_* · 직원 둘) · 실제 행은 읽기만(티어 · 창고 · 시작값 test 행) · 끝은 rollback · 시퀀스: shop_call_log identity 는 rollback 뒤 greatest(max, head)로 되돌린다
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select md5((public.ims_perm_catalog() #- '{screens,shopify}')::text) as cat_head \gset
do $$ declare v_last text; begin
  if to_regclass('public.shop_call_log_id_seq') is not null then execute 'select last_value::text from public.shop_call_log_id_seq' into v_last; else v_last := '0'; end if;
  perform set_config('shop1a.log_seq_head', v_last, false);
end $$;
select current_setting('shop1a.log_seq_head') as log_seq_head \gset
\echo '== head catalog(without shopify)' :cat_head 'call_log seq' :log_seq_head

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
create function pg_temp.err(p_sql text) returns text language plpgsql security definer as $$
begin
  execute p_sql; return 'no-error';
exception when others then return sqlstate || ' ' || sqlerrm;
end $$;

\if :{?mig}
select pg_temp.chk('G0a trial marker (catalog reissued · md5 ≠ 40dac628…)', (select (md5(prosrc) <> '40dac6284fe9bdc73879971ed16ac3c9')::text from pg_proc where proname = 'ims_perm_catalog' and pronamespace = 'public'::regnamespace), 'true');
\endif

-- ═══ T1 — 표 · CHECK · 유니크 · FK · 권한 · 뷰 ═══
select pg_temp.chk('T1a tables 3 · touch triggers 2 · constraints (store 6 · location 3 · log 1) · view · window',
  (select count(*) from pg_tables where schemaname = 'public' and tablename in ('shop_store', 'shop_location', 'shop_call_log'))::text || '/' ||
  (select count(*) from pg_trigger where not tgisinternal and tgname in ('shop_store_touch', 'shop_location_touch'))::text || '/' ||
  (select count(*) from pg_constraint where conrelid = 'public.shop_store'::regclass and conname in ('shop_store_code_uk', 'shop_store_domain_uk', 'shop_store_code_ck', 'shop_store_domain_ck', 'shop_store_kind_ck', 'shop_store_prefix_ck'))::text || '/' ||
  (select count(*) from pg_constraint where conrelid = 'public.shop_location'::regclass and conname in ('shop_location_store_gid_uk', 'shop_location_store_wh_uk', 'shop_location_gid_ck'))::text || '/' ||
  (select count(*) from pg_constraint where conrelid = 'public.shop_call_log'::regclass and conname = 'shop_call_log_error_ck')::text || '/' ||
  (select count(*) from pg_views where schemaname = 'public' and viewname = 'shop_store_list')::text || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_store_save' and prosecdef)::text, '3/2/6/3/1/1/1');
select pg_temp.chk('T1b FK count: store 3 (sale · compare · updated_by) · location 3 (store · warehouse · updated_by) · log 2',
  (select count(*) from pg_constraint where conrelid = 'public.shop_store'::regclass and contype = 'f')::text || '/' || (select count(*) from pg_constraint where conrelid = 'public.shop_location'::regclass and contype = 'f')::text || '/' || (select count(*) from pg_constraint where conrelid = 'public.shop_call_log'::regclass and contype = 'f')::text, '3/3/2');
select pg_temp.chk('T1c privileges: authenticated select only on 3 tables + view · anon nothing · guard: window executable by authenticated',
  (select string_agg(t || ':' || coalesce(p, '-'), ',' order by t) from (select t, (select string_agg(privilege_type, '+' order by privilege_type) from information_schema.role_table_grants g where g.table_schema = 'public' and g.table_name = t and g.grantee = 'authenticated') p from unnest(array['shop_store', 'shop_location', 'shop_call_log', 'shop_store_list']) t) x) || '/' ||
  (select count(*) from information_schema.role_table_grants g where g.table_schema = 'public' and g.table_name like 'shop\_%' and g.grantee = 'anon')::text || '/' ||
  has_function_privilege('authenticated', 'public.shop_store_save(jsonb, boolean, text[])', 'execute')::text,
  'shop_call_log:SELECT,shop_location:SELECT,shop_store:SELECT,shop_store_list:SELECT/0/true');
select pg_temp.chk('T1d CHECKs refuse (23514): code upper · domain not myshopify · kind · prefix lower · gid shape · error 401 chars',
  left(pg_temp.err($q$insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id) values ('BAD', 'x.myshopify.com', 'x', 'asung', (select id from public.ref_price_tier where name = 'Wholesale'))$q$), 5) || '/' ||
  left(pg_temp.err($q$insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id) values ('shop1a_x', 'x.example.com', 'x', 'asung', (select id from public.ref_price_tier where name = 'Wholesale'))$q$), 5) || '/' ||
  left(pg_temp.err($q$insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id) values ('shop1a_x', 'x.myshopify.com', 'x', 'ebay', (select id from public.ref_price_tier where name = 'Wholesale'))$q$), 5) || '/' ||
  left(pg_temp.err($q$insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, secret_prefix) values ('shop1a_x', 'x.myshopify.com', 'x', 'asung', (select id from public.ref_price_tier where name = 'Wholesale'), 'shopify_ims')$q$), 5) || '/' ||
  left(pg_temp.err($q$insert into public.shop_location (store_id, shopify_location_gid, warehouse_id) values ((select id from public.shop_store where code = 'test'), 'Location/1', (select id from public.ref_warehouse where name = 'Asung - Edmonton'))$q$), 5) || '/' ||
  left(pg_temp.err($q$insert into public.shop_call_log (store_id, action, ok, error) values (null, 'ping', false, repeat('x', 401))$q$), 5), '23514/23514/23514/23514/23514/23514');

-- ═══ T2 — 권한 키 shopify · 기존 키 회귀 없음 ═══
select pg_temp.chk('T2a catalog: shopify present (ims · manager) · everything else byte-identical to head (md5 of catalog minus screens.shopify)',
  (public.ims_perm_catalog()->'screens'->'shopify'->>'room') || '/' || (public.ims_perm_catalog()->'screens'->'shopify'->>'min_role') || '/' || (md5((public.ims_perm_catalog() #- '{screens,shopify}')::text) = :'cat_head')::text || '/' || (select count(*) from jsonb_object_keys(public.ims_perm_catalog()->'screens'))::text, 'ims/manager/true/15');

-- ═══ 재료(postgres · 가짜 직원 둘) ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'shop1a-admin@test.invalid', 'SHOP1A Admin', 'admin', '[]'::jsonb) returning auth_user_id::text as a_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'shop1a-mgr@test.invalid', 'SHOP1A Manager', 'manager', '["shopify","master"]'::jsonb) returning auth_user_id::text as m_uid \gset
select s.id::text as a_sid from public.ims_staff s where s.email = 'shop1a-admin@test.invalid' \gset
\set a_claims '{"sub":"' :a_uid '","role":"authenticated"}'
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
select id::text as wh_tor from public.ref_warehouse where name = 'Asung Trading Inc.' \gset
select id::text as wh_edm from public.ref_warehouse where name = 'Asung - Edmonton' \gset
select id::text as wh_off from public.ref_warehouse where name = 'Production Facility' \gset

set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.ims_can_write('shopify')::text as m_can_shopify \gset
select pg_temp.err($q$select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'shop1a_m', 'shop_domain', 'shop1a-m.myshopify.com', 'label', 'x', 'kind', 'asung', 'sale_tier', 'Wholesale', 'old', null)), true)$q$) as m_save \gset
do $$ begin insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id) values ('shop1a_d', 'shop1a-d.myshopify.com', 'x', 'asung', (select id from public.ref_price_tier where name = 'Wholesale')); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as m_direct \gset
do $$ begin insert into public.shop_call_log (action, ok) values ('ping', true); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as m_log \gset
do $$ begin update public.shop_store_list set label = 'x' where code = 'test'; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as m_view \gset
select count(*)::text as m_read from public.shop_store_list where code = 'test' \gset
reset role;
select pg_temp.chk('T2b manager with perm shopify: ims_can_write true · window refused (admin only) · direct insert 42501 · call_log insert 42501 · view update 55000 (lateral join view · not updatable · no write path) · view readable',
  :'m_can_shopify' || '/' || (:'m_save' like 'P0001 Only an admin can change Shopify stores%')::text || '/' || :'m_direct' || '/' || :'m_log' || '/' || :'m_view' || '/' || :'m_read', 'true/true/42501/42501/55000/1');

-- ═══ T3 — 창구 store_set · store_off(admin) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'a_claims', true);
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'shop1a_a', 'shop_domain', 'shop1a-a.myshopify.com', 'label', 'Fake A', 'kind', 'asung', 'sale_tier', 'Wholesale', 'compare_tier', 'wholesalespecia CAD', 'old', null)), false)::text as t3_pre \gset
select count(*)::text as t3_pre_n from public.shop_store where code = 'shop1a_a' \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'shop1a_a', 'shop_domain', 'shop1a-a.myshopify.com', 'label', 'Fake A', 'kind', 'asung', 'sale_tier', 'Wholesale', 'compare_tier', 'wholesalespecia CAD', 'old', null)), true)::text as t3_unack \gset
select count(*)::text as t3_unack_n from public.shop_store where code = 'shop1a_a' \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'shop1a_a', 'shop_domain', 'shop1a-a.myshopify.com', 'label', 'Fake A', 'kind', 'asung', 'sale_tier', 'Wholesale', 'compare_tier', 'wholesalespecia CAD', 'old', null)), true, array['shop1a_a:kind_active_dup'])::text as t3_set \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'shop1a_a', 'shop_domain', 'shop1a-a.myshopify.com', 'label', 'Fake A2', 'kind', 'asung', 'sale_tier', 'Wholesale', 'compare_tier', 'wholesalespecia CAD', 'old', jsonb_build_object('shop_domain', 'shop1a-a.myshopify.com', 'label', 'STALE', 'kind', 'asung', 'sale_tier', 'Wholesale', 'compare_tier', 'wholesalespecia CAD', 'secret_prefix', 'SHOPIFY_IMS'))), true, array['shop1a_a:kind_active_dup'])::text as t3_stale \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'shop1a_a', 'shop_domain', 'shop1a-a.myshopify.com', 'label', 'Fake A2', 'kind', 'asung', 'sale_tier', 'Wholesale', 'compare_tier', 'wholesalespecia CAD', 'old', jsonb_build_object('shop_domain', 'shop1a-a.myshopify.com', 'label', 'Fake A', 'kind', 'asung', 'sale_tier', 'Wholesale', 'compare_tier', 'wholesalespecia CAD', 'secret_prefix', 'SHOPIFY_IMS'))), true, array['shop1a_a:kind_active_dup'])::text as t3_upd \gset
select public.shop_store_save(jsonb_build_array(
  jsonb_build_object('op', 'store_set', 'code', 'shop1a_b', 'shop_domain', 'shop1a-b.myshopify.com', 'label', 'B', 'kind', 'aone', 'sale_tier', 'AONE', 'compare_tier', 'REFERENCECOST USD', 'old', null),
  jsonb_build_object('op', 'store_set', 'code', 'shop1a_c', 'shop_domain', 'shop1a-c.myshopify.com', 'label', 'C', 'kind', 'aone', 'sale_tier', 'ComparedPrice CAD', 'compare_tier', 'AONE', 'old', null),
  jsonb_build_object('op', 'store_set', 'code', 'shop1a_d', 'shop_domain', 'shop1a-d.myshopify.com', 'label', 'D', 'kind', 'aone', 'sale_tier', 'Nope Tier', 'old', null),
  jsonb_build_object('op', 'store_set', 'code', 'shop1a_e', 'shop_domain', 'shop1a-e.example.com', 'label', 'E', 'kind', 'aone', 'sale_tier', 'AONE', 'old', null),
  jsonb_build_object('op', 'store_set', 'code', 'shop1a_f', 'shop_domain', 'shop1a-a.myshopify.com', 'label', '', 'kind', 'ebay', 'sale_tier', 'AONE', 'secret_prefix', 'bad', 'old', null),
  jsonb_build_object('op', 'store_set', 'code', 'shop1a_g', 'shop_domain', 'shop1a-g.myshopify.com', 'label', 'G', 'kind', 'aone', 'sale_tier', 'AONE', 'old', jsonb_build_object('label', 'x')),
  jsonb_build_object('op', 'store_set', 'code', 'shop1a_a', 'shop_domain', 'shop1a-a.myshopify.com', 'label', 'A3', 'kind', 'asung', 'sale_tier', 'Wholesale', 'old', null),
  jsonb_build_object('op', 'store_set', 'code', 'shop1a_a', 'shop_domain', 'shop1a-a.myshopify.com', 'label', 'A4', 'kind', 'asung', 'sale_tier', 'Wholesale', 'old', null)
), true)::text as t3_bad \gset
select public.shop_store_save(jsonb_build_array(
  jsonb_build_object('op', 'store_set', 'code', 'shop1a_same', 'shop_domain', 'shop1a-same.myshopify.com', 'label', 'Same', 'kind', 'aone', 'sale_tier', 'AONE', 'compare_tier', 'AONE', 'old', null),
  jsonb_build_object('op', 'store_set', 'code', 'shop1a_none', 'shop_domain', 'shop1a-none.myshopify.com', 'label', 'None', 'kind', 'aone', 'sale_tier', 'AONE', 'compare_tier', '', 'secret_prefix', 'SHOPIFY_AONE', 'old', null)
), true, array['shop1a_none:kind_active_dup'])::text as t3_ok2 \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_off', 'code', 'shop1a_same', 'old', 'wrong.myshopify.com')), true)::text as t3_off_stale \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_off', 'code', 'shop1a_same', 'old', 'shop1a-same.myshopify.com')), true)::text as t3_off \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_off', 'code', 'shop1a_same', 'old', 'shop1a-same.myshopify.com')), true)::text as t3_off2 \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'store_set', 'code', 'shop1a_same', 'shop_domain', 'shop1a-same.myshopify.com', 'label', 'Same', 'kind', 'aone', 'sale_tier', 'AONE', 'compare_tier', 'AONE', 'old', jsonb_build_object('shop_domain', 'shop1a-same.myshopify.com', 'label', 'Same', 'kind', 'aone', 'sale_tier', 'AONE', 'compare_tier', 'AONE', 'secret_prefix', 'SHOPIFY_IMS'))), false)::text as t3_react \gset
reset role;
select pg_temp.chk('T3a preview: committed false · no row · warnings kind_active_dup (test store is asung) · commit without ack: unacked lists it · no row',
  (:'t3_pre'::jsonb->>'committed') || '/' || :'t3_pre_n' || '/' || (:'t3_pre'::jsonb->'warnings'->0->>'code') || '/' || (:'t3_unack'::jsonb->>'committed') || '/' || (:'t3_unack'::jsonb->'unacked')::text || '/' || :'t3_unack_n', 'false/0/kind_active_dup/false/["shop1a_a:kind_active_dup"]/0');
select pg_temp.chk('T3b commit with ack: row · tiers by name · prefix default · updated_by admin · active', (:'t3_set'::jsonb->>'committed') || '/' ||
  (select s.code || '|' || (select name from public.ref_price_tier where id = s.sale_tier_id) || '|' || (select name from public.ref_price_tier where id = s.compare_tier_id) || '|' || s.secret_prefix || '|' || (s.updated_by = :'a_sid'::uuid)::text || '|' || s.is_active::text from public.shop_store s where s.code = 'shop1a_a'), 'true/shop1a_a|Wholesale|wholesalespecia CAD|SHOPIFY_IMS|true|true');
select pg_temp.chk('T3c stale old → changed_elsewhere · right old → updated label', (:'t3_stale'::jsonb->'blocks'->0->>'code') || '/' || (:'t3_upd'::jsonb->>'committed') || '/' || (select label from public.shop_store where code = 'shop1a_a'), 'changed_elsewhere/true/Fake A2');
select pg_temp.chk('T3d blocks: compare reference · Price not sale · unknown tier · domain shape · domain taken + label + kind + prefix · old null on an existing store → old_missing · old object on a new store → store_unknown · duplicate in call · nothing saved',
  (select string_agg(b->>'key', ',' order by b->>'key') from jsonb_array_elements(:'t3_bad'::jsonb->'blocks') b) || '/' || (select count(*)::text from public.shop_store where code in ('shop1a_b', 'shop1a_c', 'shop1a_d', 'shop1a_e', 'shop1a_f', 'shop1a_g')),
  'shop1a_a:field_duplicate_in_call,shop1a_a:old_missing,shop1a_b:compare_tier_reference,shop1a_c:sale_tier_not_sale,shop1a_d:sale_tier_unknown,shop1a_e:domain_invalid,shop1a_f:domain_taken,shop1a_f:kind_invalid,shop1a_f:label_missing,shop1a_f:prefix_invalid,shop1a_g:store_unknown/0');
select pg_temp.chk('T3e Compare-at = Price (AONE · AONE) passes with no block or warning · Compare-at empty → null · prefix SHOPIFY_AONE', (:'t3_ok2'::jsonb->>'committed') || '/' || (select count(*) from jsonb_array_elements(:'t3_ok2'::jsonb->'warnings') w where w->>'code' <> 'kind_active_dup')::text || '/' ||
  (select (sale_tier_id = compare_tier_id)::text from public.shop_store where code = 'shop1a_same') || '/' || (select coalesce(compare_tier_id::text, 'null') || '|' || secret_prefix from public.shop_store where code = 'shop1a_none'), 'true/0/true/null|SHOPIFY_AONE');
select pg_temp.chk('T3f store_off: wrong old → changed_elsewhere · off → inactive · again → already_off · store_set on an off store previews store_reactivated', (:'t3_off_stale'::jsonb->'blocks'->0->>'code') || '/' || (:'t3_off'::jsonb->>'committed') || '/' || (select is_active::text from public.shop_store where code = 'shop1a_same') || '/' || (:'t3_off2'::jsonb->'blocks'->0->>'code') || '/' || (select string_agg(w->>'code', ',' order by w->>'code') from jsonb_array_elements(:'t3_react'::jsonb->'warnings') w), 'changed_elsewhere/true/false/already_off/kind_active_dup,store_reactivated');

-- ═══ T4 — location_set · location_off ═══
set local role authenticated;
select set_config('request.jwt.claims', :'a_claims', true);
select public.shop_store_save(jsonb_build_array(
  jsonb_build_object('op', 'location_set', 'store_code', 'shop1a_a', 'shopify_location_gid', 'gid://shopify/Location/1001', 'warehouse_id', :'wh_tor', 'old', null),
  jsonb_build_object('op', 'location_set', 'store_code', 'shop1a_a', 'shopify_location_gid', 'gid://shopify/Location/1002', 'warehouse_id', :'wh_edm', 'old', null)), true)::text as t4_set \gset
select string_agg(l.shopify_location_gid || '=' || w.name, ',' order by l.shopify_location_gid) || '/' || bool_and(l.is_active and l.updated_by = :'a_sid'::uuid)::text as t4_set_rows from public.shop_location l join public.ref_warehouse w on w.id = l.warehouse_id join public.shop_store s on s.id = l.store_id where s.code = 'shop1a_a' \gset
select public.shop_store_save(jsonb_build_array(
  jsonb_build_object('op', 'location_set', 'store_code', 'shop1a_a', 'shopify_location_gid', 'gid://shopify/Location/1003', 'warehouse_id', :'wh_tor', 'old', null),
  jsonb_build_object('op', 'location_set', 'store_code', 'shop1a_a', 'shopify_location_gid', 'gid://shopify/Location/1004', 'warehouse_id', :'wh_off', 'old', null),
  jsonb_build_object('op', 'location_set', 'store_code', 'shop1a_a', 'shopify_location_gid', 'gid://shopify/Location/1005', 'warehouse_id', 'not-a-uuid', 'old', null),
  jsonb_build_object('op', 'location_set', 'store_code', 'shop1a_a', 'shopify_location_gid', 'Location/1006', 'warehouse_id', :'wh_tor', 'old', null),
  jsonb_build_object('op', 'location_set', 'store_code', 'shop1a_a', 'shopify_location_gid', 'gid://shopify/Location/1001', 'warehouse_id', :'wh_edm', 'old', null),
  jsonb_build_object('op', 'location_set', 'store_code', 'shop1a_a', 'shopify_location_gid', 'gid://shopify/Location/1001', 'warehouse_id', :'wh_edm', 'old', :'wh_tor'),
  jsonb_build_object('op', 'location_set', 'store_code', 'shop1a_zz', 'shopify_location_gid', 'gid://shopify/Location/1007', 'warehouse_id', :'wh_tor', 'old', null),
  jsonb_build_object('op', 'location_set', 'store_code', 'shop1a_a', 'shopify_location_gid', 'gid://shopify/Location/1008', 'warehouse_id', :'wh_edm', 'old', null),
  jsonb_build_object('op', 'location_set', 'store_code', 'shop1a_a', 'shopify_location_gid', 'gid://shopify/Location/1009', 'warehouse_id', :'wh_edm', 'old', null),
  jsonb_build_object('op', 'location_off', 'store_code', 'shop1a_a', 'shopify_location_gid', 'gid://shopify/Location/1999', 'old', null)), true)::text as t4_bad \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'location_off', 'store_code', 'shop1a_a', 'shopify_location_gid', 'gid://shopify/Location/1002', 'old', :'wh_edm')), true)::text as t4_off \gset
select public.shop_store_save(jsonb_build_array(jsonb_build_object('op', 'location_set', 'store_code', 'shop1a_a', 'shopify_location_gid', 'gid://shopify/Location/2002', 'warehouse_id', :'wh_edm', 'old', null)), true)::text as t4_revive \gset
reset role;
select pg_temp.chk('T4a two pairs saved · gid · warehouse · active · updated_by admin', (:'t4_set'::jsonb->>'committed') || '/' || :'t4_set_rows', 'true/gid://shopify/Location/1001=Asung Trading Inc.,gid://shopify/Location/1002=Asung - Edmonton/true');
select pg_temp.chk('T4b blocks: warehouse already mapped · inactive warehouse · bad uuid · gid shape · old missing-vs-changed · unknown store · 1008 Edmonton already on 1002 · 1009 same warehouse twice in call · location_unknown · nothing saved',
  (select string_agg(b->>'key' || '=' || (b->>'code'), ',' order by b->>'key') from jsonb_array_elements(:'t4_bad'::jsonb->'blocks') b) || '/' || (select count(*)::text from public.shop_location l join public.shop_store s on s.id = l.store_id where s.code = 'shop1a_a'),
  'shop1a_a:gid://shopify/Location/1001:changed_elsewhere=changed_elsewhere,shop1a_a:gid://shopify/Location/1001:field_duplicate_in_call=field_duplicate_in_call,shop1a_a:gid://shopify/Location/1003:warehouse_already_mapped=warehouse_already_mapped,shop1a_a:gid://shopify/Location/1004:warehouse_unknown=warehouse_unknown,shop1a_a:gid://shopify/Location/1005:warehouse_unknown=warehouse_unknown,shop1a_a:gid://shopify/Location/1008:warehouse_already_mapped=warehouse_already_mapped,shop1a_a:gid://shopify/Location/1009:warehouse_duplicate_in_call=warehouse_duplicate_in_call,shop1a_a:gid://shopify/Location/1999:location_unknown=location_unknown,shop1a_a:Location/1006:gid_invalid=gid_invalid,shop1a_zz:store_unknown=store_unknown/2');
select pg_temp.chk('T4c location_off → inactive · re-pairing the same warehouse to a new GID revives that row (unique kept · 2 rows · 1002 gone · 2002 active · checked_at null)',
  (:'t4_off'::jsonb->>'committed') || '/' || (:'t4_revive'::jsonb->>'committed') || '/' || (select count(*)::text || '/' || string_agg(l.shopify_location_gid || ':' || l.is_active::text, ',' order by l.shopify_location_gid) from public.shop_location l join public.shop_store s on s.id = l.store_id where s.code = 'shop1a_a'), 'true/true/2/gid://shopify/Location/1001:true,gid://shopify/Location/2002:true');

-- ═══ T5 — 시작값 test 행(판정 403) ═══
select pg_temp.chk('T5a seed test store: domain · kind asung · Price Wholesale · Compare-at wholesalespecia CAD · prefix SHOPIFY_IMS · active · no location pairs',
  (select shop_domain || '|' || kind || '|' || (select name from public.ref_price_tier where id = s.sale_tier_id) || '|' || (select name from public.ref_price_tier where id = s.compare_tier_id) || '|' || secret_prefix || '|' || is_active::text || '|' || (select count(*) from public.shop_location l where l.store_id = s.id)::text from public.shop_store s where s.code = 'test'),
  'asung-ims-test.myshopify.com|asung|Wholesale|wholesalespecia CAD|SHOPIFY_IMS|true|0');

-- ═══ T6 — 뷰 shop_store_list ═══
insert into public.shop_call_log (store_id, action, ok, http_status, query_cost, throttle_available, error, by_staff, ms) values ((select id from public.shop_store where code = 'shop1a_a'), 'ping', false, 200, 4, 3996, 'fake: locations missing', :'a_sid'::uuid, 123);
insert into public.shop_call_log (store_id, action, ok, http_status, query_cost, throttle_available, ms) values ((select id from public.shop_store where code = 'shop1a_a'), 'ping', true, 200, 4, 3996, 98);
insert into public.shop_call_log (store_id, action, ok, http_status, ms) values ((select id from public.shop_store where code = 'shop1a_a'), 'other', false, 500, 10);
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select (row_to_json(v)::jsonb - 'id' - 'updated_at' - 'updated_by' - 'sale_tier_id' - 'compare_tier_id' - 'last_ping_at' - 'locations')::text as t6_row from public.shop_store_list v where v.code = 'shop1a_a' \gset
select (select jsonb_agg(x - 'id' - 'warehouse_id' order by x->>'shopify_location_gid') from jsonb_array_elements(v.locations) x)::text as t6_loc, (last_ping_at is not null)::text as t6_at from public.shop_store_list v where v.code = 'shop1a_a' \gset
select (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'shop_store_list') as t6_cols \gset
reset role;
select pg_temp.chk('T6a view row: tier names · last ping = latest ping row (ok true · error null) · other action ignored · locations_active 2', :'t6_row',
  '{"code": "shop1a_a", "kind": "asung", "note": null, "label": "Fake A2", "is_active": true, "shop_domain": "shop1a-a.myshopify.com", "last_ping_ok": true, "secret_prefix": "SHOPIFY_IMS", "sale_tier_name": "Wholesale", "last_ping_error": null, "locations_active": 2, "compare_tier_name": "wholesalespecia CAD"}');
select pg_temp.chk('T6b view locations jsonb (warehouse names · active · checked_at) · last_ping_at set · columns', :'t6_loc' || '/' || :'t6_at' || '/' || :'t6_cols',
  '[{"is_active": true, "checked_at": null, "shopify_name": null, "warehouse_name": "Asung Trading Inc.", "shopify_location_gid": "gid://shopify/Location/1001"}, {"is_active": true, "checked_at": null, "shopify_name": null, "warehouse_name": "Asung - Edmonton", "shopify_location_gid": "gid://shopify/Location/2002"}]/true/id,code,shop_domain,label,kind,is_active,secret_prefix,note,updated_at,updated_by,sale_tier_id,sale_tier_name,compare_tier_id,compare_tier_name,locations,locations_active,last_ping_ok,last_ping_at,last_ping_error');
select pg_temp.chk('T6c real rows: only the seed store exists outside fakes · touch moved updated_at on the updated fake store', (select count(*)::text from public.shop_store where code not like 'shop1a%') || '/' || (select (updated_at >= created_at)::text from public.shop_store where code = 'shop1a_a'), '1/true');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
do $$ begin
  if to_regclass('public.shop_call_log_id_seq') is not null then                                   -- 시험 갈래: 표가 rollback 으로 사라져 있다 → 건너뜀 · 확인 갈래: greatest(max, head)
    execute format('select setval(''public.shop_call_log_id_seq'', greatest(coalesce((select max(id) from public.shop_call_log), 0), %s, 1), (select count(*) > 0 from public.shop_call_log))', current_setting('shop1a.log_seq_head', true));
    raise notice 'seq tail call_log %', (select last_value::text || ' ' || is_called::text from public.shop_call_log_id_seq);
  else
    raise notice 'seq tail call_log: no table (trial · nothing to restore)';
  end if;
end $$;
