-- supabase/tests/wms_balance_perf_2b_check.sql — wms-balance-perf-2b ②-b(deferred 450) stk_availability by_warehouse 를 페이지 줄에만 — 검증 (2026-11-02)
-- [메인 IMS · Asung-IMS] 시험 적용 장치 틀(① · ②-a · ③ 과 같은 꼴) — 기준(begin 앞: 지문 · 무접촉 md5 · 속성 · 반환형)
--   → (-v mig 면: O 옛 창구를 begin 앞 자동 커밋 읽기로 — Both 100 · 토론토 100 · q UNF 500 · 세일만 · 2 쪽(offset 100) · 브랜드 거르기 · Zero stock 켬 100)
--   → begin → (-v mig 면 \i) → N 새 창구 · C 옛 = 새(jsonb 같음 · 순서 포함 — with ordinality) → E 꼴(태그 줄 뺀 본문 · 속성 · 반환형 · comment · 무접촉) → rollback → Z
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261103030000_wms_balance_perf_2b.sql -f supabase/tests/wms_balance_perf_2b_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 20 · 확인(적용 뒤) 11 — C0 ~ C8 은 시험 갈래만 · Z 는 t_res 밖 한 줄 · 내보내기 20,000 줄 · 에드먼턴은 캡처 파일이 덮는다(10 초 규칙)
--   직원 문: request.jwt.claims 에 활성 admin 직원 sub(definer · 읽기만) · 쓰기 0
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 20
\else
\set EXPECT_OK 11
\endif
\pset pager off
select (select max(id) from public.inv_ledger) as fp_led_max, (select count(*) from public.inv_ledger) as fp_led_n, (select count(*) from public.inv_snapshot) as fp_snap_n,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('ims_inv_balance_of', 'inv_available_base', 'so_sale_now', 'so_deal_products_all', 'stk_availability_export', 'stk_value_total', 'stk_reserved', 'wms_pick_lines', 'so_pick_plan')) as un_md5_0,
       (select p.proname || ':' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner) || '/' || pg_get_function_result(p.oid) || '/' || pg_get_function_identity_arguments(p.oid)
          from pg_proc p where p.oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure) as attr_0,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as wh1, (select id::text from public.ref_warehouse where name = 'Asung - Edmonton') as wh2,
       (select p.brand_id::text from public.product p where p.brand_id is not null and p.parent_product_id is null group by p.brand_id order by count(*) desc limit 1) as brand1,
       (select s.auth_user_id::text from public.ims_staff s where s.is_active and s.auth_user_id is not null and s.role = 'admin' order by s.created_at limit 1) as staff_uid \gset
\echo '── 기준: ledger max' :fp_led_max '· rows' :fp_led_n '· snapshot' :fp_snap_n '· 브랜드' :brand1
\echo '── 속성(전):' :attr_0
select set_config('request.jwt.claim.sub', :'staff_uid', false), set_config('request.jwt.claims', json_build_object('sub', :'staff_uid', 'role', 'authenticated')::text, false);
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
-- 호출문(옛 · 새 같은 문장 · 줄 순서까지 — with ordinality)
create temp table t_calls (ord serial, name text, sql text);
insert into t_calls (name, sql) values
  ('Both · zero off · 100',          'select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(null, null, null, null, false, 100, 0, false, null) with ordinality r'),
  ('Toronto · zero off · 100',       format('select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(%L::uuid, null, null, null, false, 100, 0, false, null) with ordinality r', :'wh1')),
  ('Both · q UNF · zero on · 500',   'select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(null, ''UNF'', null, null, true, 500, 0, false, null) with ordinality r'),
  ('Both · sale only · zero on · 100', 'select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(null, null, null, null, true, 100, 0, true, null) with ordinality r'),
  ('Both · zero off · page 2 (offset 100)', 'select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(null, null, null, null, false, 100, 100, false, null) with ordinality r'),
  ('Both · brand · zero on · 100',   format('select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(null, null, %L::uuid, null, true, 100, 0, false, null) with ordinality r', :'brand1')),
  ('Edmonton · zero on · 100',       format('select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(%L::uuid, null, null, null, true, 100, 0, false, null) with ordinality r', :'wh2')),
  ('Both · zero off · offset beyond end (99999)', 'select coalesce(jsonb_agg(to_jsonb(r) order by r.ordinality), ''[]'') from public.stk_availability(null, null, null, null, false, 100, 99999, false, null) with ordinality r');
\if :{?mig}
select format('select pg_temp.run(%L, %L, %L)', 'old', c.name, c.sql) from t_calls c order by c.ord \gexec
select (select max(id) from public.inv_ledger)::text || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.so_reserve where released_at is null) || '/' || (select count(*) from public.po_line) || '/' || (select count(*) from public.inv_transfer_line) as fp_old \gset
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
select (select max(id) from public.inv_ledger)::text || '/' || (select count(*) from public.inv_ledger) || '/' || (select count(*) from public.inv_snapshot) || '/' || (select count(*) from public.so_reserve where released_at is null) || '/' || (select count(*) from public.po_line) || '/' || (select count(*) from public.inv_transfer_line) as fp_new \gset
select pg_temp.chk('N1 new calls all succeeded (no err)', (select count(*)::text from t_run where phase = 'new' and res ? 'err'), '0');
select pg_temp.chk('N2 new Both zero off 100: 100 rows · total > 100 · every row has by_warehouse with 2 entries (Toronto · Edmonton by warehouse_id)',
  (select jsonb_array_length(res)::text || '/' || ((res -> 0 ->> 'total')::int > 100)::text || '/' || (select bool_and(jsonb_array_length(e -> 'by_warehouse') = 2 and (select count(distinct w ->> 'warehouse_id') from jsonb_array_elements(e -> 'by_warehouse') w) = 2) from jsonb_array_elements(res) e)::text
     from t_run where phase = 'new' and name = 'Both · zero off · 100'), '100/true/true');
select pg_temp.chk('N3 new Toronto zero off 100: by_warehouse has exactly one entry = Toronto', (select bool_and(jsonb_array_length(e -> 'by_warehouse') = 1 and e -> 'by_warehouse' -> 0 ->> 'warehouse_id' = :'wh1')::text from t_run, jsonb_array_elements(res) e where phase = 'new' and name = 'Toronto · zero off · 100'), 'true');
select pg_temp.chk('N4 new page 2: 100 rows · first sku > last sku of page 1 · same total', (select (jsonb_array_length(p2.res) = 100 and (p2.res -> 0 ->> 'sku') > (p1.res -> 99 ->> 'sku') and (p2.res -> 0 ->> 'total') = (p1.res -> 0 ->> 'total'))::text from t_run p1 join t_run p2 on p2.phase = 'new' and p2.name like 'Both · zero off · page 2%' where p1.phase = 'new' and p1.name = 'Both · zero off · 100'), 'true');
select pg_temp.chk('N5 new offset beyond end → 0 rows', (select jsonb_array_length(res)::text from t_run where phase = 'new' and name like 'Both · zero off · offset beyond%'), '0');
\if :{?mig}
select pg_temp.chk('C0 fingerprint stable between old and new (' || :'fp_old' || ' → ' || :'fp_new' || ')', :'fp_new', :'fp_old');
select pg_temp.chk('C' || c.ord || ' new = old (rows · order · by_warehouse): ' || c.name || case when :'fp_new' <> :'fp_old' then ' (skipped: data moved)' else '' end || ' · ms old ' || o.ms || ' → new ' || n.ms,
                   case when :'fp_new' <> :'fp_old' then 'skipped' else (n.res = o.res)::text end, case when :'fp_new' <> :'fp_old' then 'skipped' else 'true' end)
from t_calls c join t_run o on o.phase = 'old' and o.name = c.name join t_run n on n.phase = 'new' and n.name = c.name order by c.ord;
\endif
select pg_temp.chk('E1 body = original d5bc13a4 minus replaced lines + one closing paren + tagged (20)',
  (select md5(regexp_replace(prosrc, '[^\n]*wms-balance-perf-2b[^\n]*\n', '', 'g')) || '/' || (select count(*) from regexp_matches(prosrc, 'wms-balance-perf-2b', 'g')) from pg_proc where oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure), '3da1cb178caa2a7f187e34854807e768/20');
select pg_temp.chk('E2 attributes · return columns · arguments unchanged',
  (select p.proname || ':' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner) || '/' || pg_get_function_result(p.oid) || '/' || pg_get_function_identity_arguments(p.oid)
     from pg_proc p where p.oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure), :'attr_0');
select pg_temp.chk('E3 agg no longer builds jsonb · page and bw exist · one jsonb_agg', (select ((prosrc !~ 'agg\.by_warehouse') and prosrc ~ ', page as \(' and prosrc ~ '\), bw as \(' and (select count(*) from regexp_matches(prosrc, 'jsonb_agg\(jsonb_build_object\(''warehouse_id''', 'g')) = 1)::text from pg_proc where oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure), 'true');
select pg_temp.chk('E4 comment carries wms-balance-perf-2b', (select (obj_description(oid, 'pg_proc') like '%wms-balance-perf-2b%')::text from pg_proc where oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure), 'true');
select pg_temp.chk('E5 untouched md5 (inv_available_base · so_sale_now · so_deal_products_all · export · stk_value_total · stk_reserved · ① 둘 · ims_inv_balance_of)',
  (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('ims_inv_balance_of', 'inv_available_base', 'so_sale_now', 'so_deal_products_all', 'stk_availability_export', 'stk_value_total', 'stk_reserved', 'wms_pick_lines', 'so_pick_plan')), :'un_md5_0');
select pg_temp.chk('E6 export wrapper still calls stk_availability with 20000', (select (prosrc ~ 'public\.stk_availability\(p_warehouse_id, p_q, p_brand_id, p_category_id, p_include_zero, 20000, 0, p_sale_only, p_supplier_id\)')::text from pg_proc where oid = 'public.stk_availability_export(uuid, text, uuid, uuid, boolean, boolean, uuid)'::regprocedure), 'true');
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || left(coalesce(got, '(null)'), 300) || ' | want=' || left(coalesce(want, '(null)'), 300) end as detail from t_res order by n;
select count(*) filter (where ok) as n_ok, count(*) filter (where not ok) as n_bad, count(*) as n_all from t_res \gset
select phase, name, ms, jsonb_array_length(case when jsonb_typeof(res) = 'array' then res else '[]'::jsonb end) as rows, case when res ? 'err' then left(res ->> 'err', 80) else '' end as err from t_run order by name, phase;
select clock_timestamp() as t_end \gset
rollback;
select (select max(id) from public.inv_ledger) = :fp_led_max and (select count(*) from public.inv_ledger) = :fp_led_n and (select count(*) from public.inv_snapshot) = :fp_snap_n as z_fingerprint_same_as_start,
       (select md5(prosrc) from pg_proc where oid = 'public.stk_availability(uuid, text, uuid, uuid, boolean, integer, integer, boolean, uuid)'::regprocedure) as z_stk_md5_after,
       round(extract(epoch from (:'t_end'::timestamptz - :'t_begin'::timestamptz))::numeric, 2) as begin_to_rollback_s,
       round(extract(epoch from (:'t_end'::timestamptz - :'t_mig'::timestamptz))::numeric, 2) as mig_to_rollback_s;
\echo '── 결과: OK' :n_ok '· MISMATCH' :n_bad '· 전체' :n_all '· 기대 OK' :EXPECT_OK
\if :{?mig}
\echo '   (시험 갈래 · 적용은 rollback 됨 · z_stk_md5_after 는 옛 d5bc13a4… 이어야 한다)'
\else
\echo '   (확인 갈래 · z_stk_md5_after 는 새 값)'
\endif
