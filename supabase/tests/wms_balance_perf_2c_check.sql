-- supabase/tests/wms_balance_perf_2c_check.sql — wms-balance-perf-2c ②-c(deferred 450) so_sale_now p_with_deals · stk_availability sale CTE false — 검증 (2026-11-02)
-- [메인 IMS · Asung-IMS] 시험 적용 장치 틀 — 기준(begin 앞: 지문 · 무접촉 md5 · 속성 · 호출자 전수 count)
--   → (-v mig 면: O 옛 창구를 begin 앞 자동 커밋 읽기로 — so_sale_now(null, null) · (세일 제품 20 · 조건부 포함) · (null, 날짜) · stk_availability Both 100 · 토론토 100 · 세일만 · q UNF)
--   → begin → (-v mig 면 \i) → N 새 창구(기본 3 + false 1 + stk 4) · C 옛 = 새(기본 호출 jsonb 같음 · false 의 product_id · best_pct · conditional = 옛 같은 칸 · deals '[]' · stk 줄 · 순서 · sale_pct · sale_conditional)
--   → E 꼴(서명 하나 · default 3 · 속성 · acl · 태그 줄 뺀 본문 · 다른 호출자 무변 · comment) → rollback → Z
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261103060000_wms_balance_perf_2c.sql -f supabase/tests/wms_balance_perf_2c_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 24 · 확인(적용 뒤) 14 — C0 ~ C9 는 시험 갈래만 · Z 는 t_res 밖 한 줄
--   직원 문: stk_availability 는 request.jwt.claims 에 활성 admin sub · so_sale_now 는 문 없음(invoker · 읽기) · 쓰기 0
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 24
\else
\set EXPECT_OK 14
\endif
\pset pager off
select (select max(id) from public.inv_ledger) as fp_led_max, (select count(*) from public.inv_ledger) as fp_led_n,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('so_deal_products_all', 'so_deal_products', 'product_list', 'product_export', 'stk_value_total', 'stk_availability_export', 'inv_available_base', 'ims_inv_balance_of')) as un_md5_0,
       (select p.proname || ':' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner) || '/' || pg_get_function_result(p.oid) || '/' || pg_get_function_identity_arguments(p.oid)
          from pg_proc p where p.oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure) as attr_stk_0,
       (select coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner) || '/' || pg_get_function_result(p.oid) || '/' || (p.prosrc ~ '#variable_conflict use_column')::text
          from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_sale_now' limit 1) as attr_sale_0,
       (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc ~ '\mso_sale_now\M') as callers_0,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as wh1,
       (select s.auth_user_id::text from public.ims_staff s where s.is_active and s.auth_user_id is not null and s.role = 'admin' order by s.created_at limit 1) as staff_uid \gset
\echo '── 기준: ledger max' :fp_led_max '· so_sale_now 를 읽는 함수' :callers_0 '· so_sale_now 속성(전)' :attr_sale_0
select set_config('request.jwt.claim.sub', :'staff_uid', false), set_config('request.jwt.claims', json_build_object('sub', :'staff_uid', 'role', 'authenticated')::text, false);
-- 입력: 세일 제품 20(조건부 딜 제품을 앞에) · 날짜 하나
select (select array_agg(x.product_id)::text from (select z.product_id from public.so_sale_now(null, null) z order by z.conditional desc, z.best_pct desc, z.product_id limit 20) x) as pids_sale,
       (select (coalesce(max(x.date_from), public.ims_today()))::text from public.so_deal x where x.is_active and x.kind = 'pct') as on_date \gset
\echo '── 입력: 세일 제품 20' :pids_sale '· 날짜' :on_date
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create temp table t_run (phase text, name text, res jsonb, ms numeric);
create function pg_temp.run(p_phase text, p_name text, p_sql text) returns void language plpgsql as $$
declare v jsonb; t0 timestamptz := clock_timestamp();
begin
  execute p_sql into v;
  insert into t_run values (p_phase, p_name, v, round(extract(epoch from clock_timestamp() - t0) * 1000, 1));
exception when others then
  insert into t_run values (p_phase, p_name, jsonb_build_object('err', sqlerrm), round(extract(epoch from clock_timestamp() - t0) * 1000, 1));
end $$;
create temp table t_calls (ord serial, name text, sql text, new_only boolean default false);
insert into t_calls (name, sql) values
  ('so_sale_now (null, null)',           'select coalesce(jsonb_agg(to_jsonb(z) order by z.product_id), ''[]'') from public.so_sale_now(null, null) z'),
  ('so_sale_now (20 sale products, null)', format('select coalesce(jsonb_agg(to_jsonb(z) order by z.product_id), ''[]'') from public.so_sale_now(%L::uuid[], null) z', :'pids_sale')),
  ('so_sale_now (null, date)',           format('select coalesce(jsonb_agg(to_jsonb(z) order by z.product_id), ''[]'') from public.so_sale_now(null, %L::date) z', :'on_date')),
  ('stk_availability Both · zero off · 100',   'select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(null, null, null, null, false, 100, 0, false, null) with ordinality r'),
  ('stk_availability Toronto · zero off · 100', format('select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(%L::uuid, null, null, null, false, 100, 0, false, null) with ordinality r', :'wh1')),
  ('stk_availability Both · sale only · zero on · 100', 'select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(null, null, null, null, true, 100, 0, true, null) with ordinality r'),
  ('stk_availability Both · q UNF · zero on · 500', 'select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(null, ''UNF'', null, null, true, 500, 0, false, null) with ordinality r');
insert into t_calls (name, sql, new_only) values
  ('so_sale_now (null, null, false)', 'select coalesce(jsonb_agg(to_jsonb(z) order by z.product_id), ''[]'') from public.so_sale_now(null, null, false) z', true),
  ('so_sale_now (20 sale products, null, false)', format('select coalesce(jsonb_agg(to_jsonb(z) order by z.product_id), ''[]'') from public.so_sale_now(%L::uuid[], null, false) z', :'pids_sale'), true);
\if :{?mig}
select format('select pg_temp.run(%L, %L, %L)', 'old', c.name, c.sql) from t_calls c where not c.new_only order by c.ord \gexec
select (select max(id) from public.inv_ledger)::text || '/' || (select count(*) from public.so_deal) || '/' || (select count(*) from public.so_deal_line) || '/' || (select count(*) from public.so_deal_target) || '/' || (select count(*) from public.so_reserve where released_at is null) as fp_old \gset
\echo '── 옛 결과 담음 · 지문' :fp_old
\endif

begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select clock_timestamp() as t_mig \gset
select format('select pg_temp.run(%L, %L, %L)', 'new', c.name, c.sql) from t_calls c order by c.ord \gexec
select (select max(id) from public.inv_ledger)::text || '/' || (select count(*) from public.so_deal) || '/' || (select count(*) from public.so_deal_line) || '/' || (select count(*) from public.so_deal_target) || '/' || (select count(*) from public.so_reserve where released_at is null) as fp_new \gset
select pg_temp.chk('N1 new calls all succeeded (no err)', (select count(*)::text from t_run where phase = 'new' and res ? 'err'), '0');
select pg_temp.chk('N2 new so_sale_now (null, null) rows > 0 · a conditional product exists · deals non-empty', (select ((jsonb_array_length(res) > 0) and exists (select 1 from jsonb_array_elements(res) e where (e ->> 'conditional')::boolean) and (select bool_and(jsonb_array_length(e -> 'deals') > 0) from jsonb_array_elements(res) e))::text from t_run where phase = 'new' and name = 'so_sale_now (null, null)'), 'true');
select pg_temp.chk('N3 new so_sale_now (null, null, false): same row count as default · every deals = [] · deal_count kept', (select (jsonb_array_length(f.res) = jsonb_array_length(d.res) and (select bool_and(e -> 'deals' = '[]'::jsonb and (e ->> 'deal_count')::int > 0) from jsonb_array_elements(f.res) e))::text from t_run f join t_run d on d.phase = 'new' and d.name = 'so_sale_now (null, null)' where f.phase = 'new' and f.name = 'so_sale_now (null, null, false)'), 'true');
select pg_temp.chk('N4 new false: product_id · best_pct · conditional · deal_count = default call same columns (except both ways 0)',
  (select (select count(*) from (select e -> 'product_id', e -> 'best_pct', e -> 'conditional', e -> 'deal_count' from jsonb_array_elements(f.res) e except all select e -> 'product_id', e -> 'best_pct', e -> 'conditional', e -> 'deal_count' from jsonb_array_elements(d.res) e) x)::text || '/' ||
          (select count(*) from (select e -> 'product_id', e -> 'best_pct', e -> 'conditional', e -> 'deal_count' from jsonb_array_elements(d.res) e except all select e -> 'product_id', e -> 'best_pct', e -> 'conditional', e -> 'deal_count' from jsonb_array_elements(f.res) e) x)::text
     from t_run f join t_run d on d.phase = 'new' and d.name = 'so_sale_now (null, null)' where f.phase = 'new' and f.name = 'so_sale_now (null, null, false)'), '0/0');
select pg_temp.chk('N5 new false (20 products): same three columns as default (20 products)',
  (select (select count(*) from (select e -> 'product_id', e -> 'best_pct', e -> 'conditional' from jsonb_array_elements(f.res) e except all select e -> 'product_id', e -> 'best_pct', e -> 'conditional' from jsonb_array_elements(d.res) e) x)::text || '/' || (select count(*) from (select e -> 'product_id', e -> 'best_pct', e -> 'conditional' from jsonb_array_elements(d.res) e except all select e -> 'product_id', e -> 'best_pct', e -> 'conditional' from jsonb_array_elements(f.res) e) x)::text || '/' || jsonb_array_length(f.res)::text
     from t_run f join t_run d on d.phase = 'new' and d.name = 'so_sale_now (20 sale products, null)' where f.phase = 'new' and f.name = 'so_sale_now (20 sale products, null, false)'), '0/0/20');
\if :{?mig}
select pg_temp.chk('C0 fingerprint stable between old and new (' || :'fp_old' || ' → ' || :'fp_new' || ')', :'fp_new', :'fp_old');
select pg_temp.chk('C' || c.ord || ' new = old: ' || c.name || case when :'fp_new' <> :'fp_old' then ' (skipped: data moved)' else '' end || ' · ms old ' || o.ms || ' → new ' || n.ms,
                   case when :'fp_new' <> :'fp_old' then 'skipped' else (n.res = o.res)::text end, case when :'fp_new' <> :'fp_old' then 'skipped' else 'true' end)
from t_calls c join t_run o on o.phase = 'old' and o.name = c.name join t_run n on n.phase = 'new' and n.name = c.name where not c.new_only order by c.ord;
select pg_temp.chk('C8 false call: product_id · best_pct · conditional = OLD default call same columns (except both ways 0)',
  (select (select count(*) from (select e -> 'product_id', e -> 'best_pct', e -> 'conditional' from jsonb_array_elements(f.res) e except all select e -> 'product_id', e -> 'best_pct', e -> 'conditional' from jsonb_array_elements(o.res) e) x)::text || '/' || (select count(*) from (select e -> 'product_id', e -> 'best_pct', e -> 'conditional' from jsonb_array_elements(o.res) e except all select e -> 'product_id', e -> 'best_pct', e -> 'conditional' from jsonb_array_elements(f.res) e) x)::text
     from t_run f join t_run o on o.phase = 'old' and o.name = 'so_sale_now (null, null)' where f.phase = 'new' and f.name = 'so_sale_now (null, null, false)'), '0/0');
select pg_temp.chk('C9 false call ms vs old default: ' || (select o.ms from t_run o where o.phase = 'old' and o.name = 'so_sale_now (null, null)') || ' → ' || (select f.ms from t_run f where f.phase = 'new' and f.name = 'so_sale_now (null, null, false)'),
  (select (f.ms < o.ms)::text from t_run f join t_run o on o.phase = 'old' and o.name = 'so_sale_now (null, null)' where f.phase = 'new' and f.name = 'so_sale_now (null, null, false)'), 'true');
\endif
select pg_temp.chk('E1 so_sale_now: one function · 3 args · 3 defaults · result unchanged', (select count(*)::text || '/' || max(pg_get_function_identity_arguments(oid)) || '/' || max(pronargdefaults)::text || '/' || max(pg_get_function_result(oid)) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_sale_now'),
  '1/p_product_ids uuid[], p_on date, p_with_deals boolean/3/TABLE(product_id uuid, best_pct numeric, deal_count integer, conditional boolean, deals jsonb)');
select pg_temp.chk('E2 so_sale_now attributes (acl · invoker · stable · search_path · owner · variable_conflict) unchanged',
  (select coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner) || '/' || pg_get_function_result(p.oid) || '/' || (p.prosrc ~ '#variable_conflict use_column')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_sale_now' limit 1), :'attr_sale_0');
select pg_temp.chk('E3 so_sale_now body = original 7391d9d3 minus deals lines + tagged (3)',
  (select md5(regexp_replace(prosrc, '[^\n]*wms-balance-perf-2c[^\n]*\n', '', 'g')) || '/' || (select count(*) from regexp_matches(prosrc, 'wms-balance-perf-2c', 'g')) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_sale_now'), '93599e5201075393a8d07c6f4ad9c47a/3');
select pg_temp.chk('E4 stk_availability body = ②-b 6437737 minus sale line + tagged (1) · calls (null, null, false)',
  (select md5(regexp_replace(prosrc, '[^\n]*wms-balance-perf-2c[^\n]*\n', '', 'g')) || '/' || (select count(*) from regexp_matches(prosrc, 'wms-balance-perf-2c', 'g')) || '/' || (prosrc ~ 'public\.so_sale_now\(null, null, false\)')::text from pg_proc where oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure), 'ece94fa8f71c55a2f956443599a3d74a/1/true');
select pg_temp.chk('E5 stk_availability attributes · result · args unchanged',
  (select p.proname || ':' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner) || '/' || pg_get_function_result(p.oid) || '/' || pg_get_function_identity_arguments(p.oid) from pg_proc p where p.oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure), :'attr_stk_0');
select pg_temp.chk('E6 other callers untouched and still (null, null) · caller count unchanged', (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('so_deal_products_all', 'so_deal_products', 'product_list', 'product_export', 'stk_value_total', 'stk_availability_export', 'inv_available_base', 'ims_inv_balance_of')) || '/' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc ~ '\mso_sale_now\M')::text || '/' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_list', 'product_export', 'stk_value_total') and p.prosrc ~ 'public\.so_sale_now\(null, null\)')::text,
  :'un_md5_0' || '/' || :'callers_0' || '/3');
select pg_temp.chk('E7 comments carry wms-balance-perf-2c × 2', (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_sale_now', 'stk_availability') and obj_description(p.oid, 'pg_proc') like '%wms-balance-perf-2c%'), '2');
select pg_temp.chk('E8 no view · trigger depends on so_sale_now', (select count(*)::text from pg_class c where c.relkind in ('v', 'm') and c.relnamespace = 'public'::regnamespace and pg_get_viewdef(c.oid) ~ '\mso_sale_now\M') || '/' || (select count(*)::text from pg_trigger t join pg_proc p on p.oid = t.tgfoid where not t.tgisinternal and p.prosrc ~ '\mso_sale_now\M'), '0/0');
select pg_temp.chk('E9 named-argument call shape of the screens still resolves (p_product_ids · p_on)', (select jsonb_typeof(coalesce(jsonb_agg(to_jsonb(z)), '[]'))::text from public.so_sale_now(p_product_ids => :'pids_sale'::uuid[], p_on => null) z), 'array');
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || left(coalesce(got, '(null)'), 300) || ' | want=' || left(coalesce(want, '(null)'), 300) end as detail from t_res order by n;
select count(*) filter (where ok) as n_ok, count(*) filter (where not ok) as n_bad, count(*) as n_all from t_res \gset
select phase, name, ms, jsonb_array_length(case when jsonb_typeof(res) = 'array' then res else '[]'::jsonb end) as rows, case when res ? 'err' then left(res ->> 'err', 80) else '' end as err from t_run order by name, phase;
select clock_timestamp() as t_end \gset
rollback;
select (select max(id) from public.inv_ledger) = :fp_led_max and (select count(*) from public.inv_ledger) = :fp_led_n as z_fingerprint_same_as_start,
       (select string_agg(pg_get_function_identity_arguments(oid), ' ; ') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_sale_now') as z_sale_args_after,
       round(extract(epoch from (:'t_end'::timestamptz - :'t_begin'::timestamptz))::numeric, 2) as begin_to_rollback_s,
       round(extract(epoch from (:'t_end'::timestamptz - :'t_mig'::timestamptz))::numeric, 2) as mig_to_rollback_s;
\echo '── 결과: OK' :n_ok '· MISMATCH' :n_bad '· 전체' :n_all '· 기대 OK' :EXPECT_OK
\if :{?mig}
\echo '   (시험 갈래 · 적용은 rollback 됨 · z_sale_args_after 는 옛 2 인자여야 한다)'
\else
\echo '   (확인 갈래 · z_sale_args_after 는 3 인자)'
\endif
