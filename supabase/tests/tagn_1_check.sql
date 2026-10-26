-- supabase/tests/tagn_1_check.sql — tagn-1 product_tag_names() 검증 (2026-10-26 · 판정 772 · deferred 340)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞 · 잠금 없음: 화면 셈 = 두 표 distinct 합집합 · ICU 순서 md5 · 행 수) → begin → (-v mig 면 \i) → 함수 꼴 · 권한 · 가짜 직원(열쇠 0) 호출 · 같은 수 · 같은 집합 · 순서 · 걸린 시간 → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261026193518_tagn_1_product_tag_names.sql -f supabase/tests/tagn_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험 = 확인 = 아래 EXPECT_OK · 적용 전 마른 실행(-v mig 없음)은 OK 4(C3 · C4 · S2 · T1) · 나머지 MISMATCH(아직 창구 없음 — 정상)
--   쓰기 0 — 창구는 stable · 가짜 직원 행은 rollback · product_tag · so_deal_target · ims_staff 행 수 전후 대조
\set ON_ERROR_STOP on
\set EXPECT_OK 19
\pset pager off
-- 기준(begin 앞 · 잠금 없음): 화면이 지금 셈하는 집합(discount-rules 1218 · products 742 — 두 표 distinct 합집합 · 빈 값 제외) · 기대 순서(ICU) · "C" 순서 · 행 수
create temp table t_screen as
  select u.tag from (select t.tag from public.product_tag t union select d.tag from public.so_deal_target d where d.target = 'tag') u
  where u.tag is not null and u.tag <> '';
select count(*) as n_screen, count(distinct tag) as n_screen_d from t_screen \gset
select md5(string_agg(tag, ',' order by tag collate "en-x-icu")) as exp_md5 from t_screen \gset
select md5(string_agg(tag, ',' order by tag collate "C")) as c_md5 from t_screen \gset
select (select count(*) from public.product_tag) as n_pt, (select count(*) from public.so_deal_target) as n_dt, (select count(*) from public.ims_staff) as n_staff,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_tag_names') as n_fn0 \gset
\echo '── 기준: screen set' :n_screen '(distinct' :n_screen_d ') · product_tag' :n_pt '· so_deal_target' :n_dt '· ims_staff' :n_staff '· product_tag_names in pg_proc' :n_fn0
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

-- ── F 함수 꼴: 하나 · stable · invoker · search_path · returns jsonb · comment ──
select count(*)::text as n_fn, coalesce(max(p.provolatile::text), '-') as vol, coalesce(max(p.prosecdef::text), '-') as def,
       coalesce(max(array_to_string(p.proconfig, ',')), '-') as cfg, coalesce(max(p.prorettype::regtype::text), '-') as rtype,
       coalesce(max(left(obj_description(p.oid, 'pg_proc'), 13)), '-') as cmt
from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_tag_names' \gset
select pg_temp.chk('F1 one product_tag_names', :'n_fn', '1');
select pg_temp.chk('F2 stable', :'vol', 's');
select pg_temp.chk('F3 security invoker', :'def', 'false');
select pg_temp.chk('F4 search_path', :'cfg', 'search_path=public, pg_temp');
select pg_temp.chk('F5 returns jsonb', :'rtype', 'jsonb');
select pg_temp.chk('F6 comment starts tagn-1', :'cmt', 'tagn-1 판정 772');
select pg_temp.chk('F7 no args', pg_temp.run('select pronargs::text from pg_proc where pronamespace = ''public''::regnamespace and proname = ''product_tag_names'''), '0');

-- ── P 권한: authenticated 만 · anon · public · service_role 없음 · 가짜 직원(열쇠 0) 이 부른다 ──
select pg_temp.chk('P1 authenticated can execute', pg_temp.run('select has_function_privilege(''authenticated'', ''public.product_tag_names()'', ''execute'')::text'), 'true');
select pg_temp.chk('P2 anon cannot',               pg_temp.run('select has_function_privilege(''anon'', ''public.product_tag_names()'', ''execute'')::text'), 'false');
select pg_temp.chk('P3 service_role cannot',       pg_temp.run('select has_function_privilege(''service_role'', ''public.product_tag_names()'', ''execute'')::text'), 'false');
select pg_temp.chk('P4 public (any role) no default grant', pg_temp.run('select (p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0))::text from pg_proc p where p.pronamespace = ''public''::regnamespace and p.proname = ''product_tag_names'''), 'true');
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values
  (gen_random_uuid(), 'tagn1-min@test.invalid', 'tagn1 no keys', 'worker', '[]', true);
select auth_user_id::text as u_min from public.ims_staff where email = 'tagn1-min@test.invalid' \gset
select set_config('request.jwt.claims', json_build_object('sub', :'u_min', 'role', 'authenticated')::text, true);
set local role authenticated;
select clock_timestamp() as t0 \gset
select pg_temp.run('select set_config(''app.out'', public.product_tag_names()::text, true)') as r_call \gset
select clock_timestamp() as t1 \gset
reset role;
select pg_temp.chk('P5 fake staff with no keys: call ok', case when :'r_call' like 'ERR%' then :'r_call' else 'OK' end, 'OK');
create temp table t_fn as
  select x.v, x.ord from jsonb_array_elements_text(pg_temp.j(current_setting('app.out', true))) with ordinality x(v, ord);

-- ── C 같은 수 · 같은 집합 · 빈 값 0 · 겹침 0 ──
select pg_temp.chk('C1 count = screen set', (select count(*)::text from t_fn), :'n_screen');
select pg_temp.chk('C2 set = screen set (except both ways = 0)',
  (select count(*)::text from ((select v from t_fn except select tag from t_screen) union all (select tag from t_screen except select v from t_fn)) x), '0');
select pg_temp.chk('C3 null · empty = 0', (select count(*)::text from t_fn where v is null or v = ''), '0');
select pg_temp.chk('C4 duplicates = 0', (select (count(*) - count(distinct v))::text from t_fn), '0');

-- ── S 순서 = ICU(en-x-icu = 화면 localeCompare) · "C"(바이트) 순서가 아니다 ──
select coalesce(md5(string_agg(v, ',' order by ord)), '(none)') as got_md5 from t_fn \gset
select pg_temp.chk('S1 order = en-x-icu order of screen set', :'got_md5', :'exp_md5');
select pg_temp.chk('S2 order is not byte ("C") order', (:'got_md5' <> :'c_md5')::text, 'true');

-- ── T 걸린 시간(가짜 직원 · 한 호출 · REST statement_timeout 8 s 안) ──
select round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000)::int as call_ms \gset
select pg_temp.chk(format('T1 one call < 8000 ms (measured %s ms)', :call_ms), (:call_ms < 8000)::text, 'true');

-- ── 화면 재료: 반환 꼴 앞 8 개 ──
\echo '── product_tag_names() → jsonb (앞 8 개 · 마지막 2 개)'
select (select jsonb_agg(v order by ord) from (select v, ord from t_fn order by ord limit 8) a) as first8,
       (select jsonb_agg(v order by ord) from (select v, ord from t_fn order by ord desc limit 2) b) as last2;

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.product_tag) = :n_pt as product_tag_same,
       (select count(*) from public.so_deal_target) = :n_dt as so_deal_target_same,
       (select count(*) from public.ims_staff) = :n_staff as staff_same,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_tag_names') = :n_fn0 as fn_count_same_as_before,
       (select md5(string_agg(tag, ',' order by tag collate "en-x-icu")) from (select u.tag from (select t.tag from public.product_tag t union select d.tag from public.so_deal_target d where d.target = 'tag') u where u.tag is not null and u.tag <> '') s) = :'exp_md5' as screen_set_same;
