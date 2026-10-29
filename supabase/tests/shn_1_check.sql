-- supabase/tests/shn_1_check.sql — shn-1 Shipping notes 창구 so_shipping_notes_set 검증 (2026-10-29 · 판정 880)
-- [테스트 · Asung-IMS] 시험 적용 장치 — db_role = test 가드 → 기준(begin 앞: 함수 md5 · 예약 · 줄 · 원장 · WMS 표 md5 · 실물 packed 오더 하나) → begin → (-v mig 면 \i) → 가짜(직원 둘 · SO 여덟 — 전부 rollback) → T1~T6 · M → rollback → Z
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261029233000_shn_1_shipping_notes.sql -f supabase/tests/shn_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) · 확인(적용 뒤) 둘 다 23 — Z1 은 t_res 밖 한 줄
--   ⚠️ 시퀀스는 롤백되지 않는다(so_next_number comment) ⇒ SO 는 번호를 직접 넣는다(SO-79971~8) · 상태가 draft 가 아닌 가짜는 문지기(insert 는 draft 만)를 replica 로 비껴 넣는다 · 손님 · 통화는 실물 id 를 FK 로만 빌린다
--   ⚠️ T5 는 실물 packed 오더 하나(줄 · 예약 · 패킹 과제가 있는 것)를 rollback 안에서 고친다 — 그 행 잠금은 rollback 까지
--   잠금 규칙: 무거운 기준값(원장 md5)은 begin 앞 · lock_timeout 3s · begin ~ rollback 시간을 끝에 찍는다
\set ON_ERROR_STOP on
\pset pager off
select coalesce((select value from public.inv_config where key = 'db_role'), '(missing)') as db_role \gset
select (:'db_role' = 'test') as is_test \gset
\echo '── db_role' :db_role
\if :is_test
\else
\echo 'STOP — inv_config.db_role is not test — nothing was run'
\quit
\endif
-- ── 기준(begin 앞) ──
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_header_update', 'so_finalize', 'so_status_guard', 'so_shipping_notes_set');
select (select count(*) from t_pre where proname = 'so_shipping_notes_set') = 0 as fn_absent \gset
select (select count(*) from public.so) as w_so, (select count(*) from public.ims_staff) as w_staff, (select count(*) from public.so where so_number like 'SO-7997%') as w_fake \gset
-- 실물 packed 오더 하나 — 예약이 가장 많은 것(같으면 번호순)
select s.id::text as so_real, s.so_number as so_real_no, coalesce(s.shipping_notes, '') as real_old, md5((to_jsonb(s) - 'shipping_notes' - 'updated_at' - 'updated_by')::text) as real_rest0, md5(to_jsonb(s)::text) as real_full0
  from public.so s where s.status = 'packed' and exists (select 1 from public.wms_pack_tasks p where p.order_id = s.id)
  order by (select count(*) from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = s.id) desc, s.so_number limit 1 \gset
select (select coalesce(md5(string_agg(to_jsonb(t)::text, '|' order by t.id)), '(none)') from public.so_reserve t) as m_res0,
       (select coalesce(md5(string_agg(to_jsonb(t)::text, '|' order by t.id)), '(none)') from public.so_line t) as m_line0,
       (select coalesce(md5(string_agg(to_jsonb(t)::text, '|' order by t.id)), '(none)') from public.wms_pack_tasks t) as m_pack0,
       (select coalesce(md5(string_agg(to_jsonb(t)::text, '|' order by t.id)), '(none)') from public.wms_pick_tasks t) as m_pick0,
       (select count(*)::text || '/' || coalesce(md5(string_agg(to_jsonb(t)::text, '|' order by t.id)), '(none)') from public.inv_ledger t) as m_led0 \gset
\echo '── 기준: so' :w_so '· staff' :w_staff '· fake SO-7997x' :w_fake '· new fn absent' :fn_absent '· real packed' :so_real_no '(notes «' :real_old '»)'
\set EXPECT_OK 23
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin0 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
-- safeupdate 의 규칙을 정적으로 센다(cdc_1_check.sql 의 것 그대로)
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop
      v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g');
      exit when v_chunk = v_prev;
    end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
$$;
-- 창구를 화면처럼 부른다(authenticated 역할 · 가짜 직원 uid) · 결과는 jsonb 글자 · 예외는 'ERR <sqlstate>: <문장>'
create function pg_temp.shn(p_uid text, p_so text, p_text text, p_old text) returns text language plpgsql as $$
declare v text;
begin
  perform pg_temp.as_user(p_uid);
  execute 'set local role authenticated';
  execute format('select public.so_shipping_notes_set(%L, %L, %L)::text', p_so::uuid, p_text, p_old) into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then reset role; return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 행 보기: notes | status | updated_by | updated_at 이 움직였나(가짜는 하루 전 · touch 가 돌면 now())
create function pg_temp.srow(p_so text) returns text language sql as $$
  select coalesce(s.shipping_notes, '(null)') || '|' || s.status || '|' || coalesce(s.updated_by::text, '(null)') || '|' || (s.updated_at > now() - interval '1 hour')::text
  from public.so s where s.id = p_so::uuid;
$$;
create function pg_temp.rest(p_so text) returns text language sql as $$
  select md5((to_jsonb(s) - 'shipping_notes' - 'updated_at' - 'updated_by')::text) from public.so s where s.id = p_so::uuid;
$$;
create function pg_temp.fullrow(p_so text) returns text language sql as $$
  select md5(to_jsonb(s)::text) from public.so s where s.id = p_so::uuid;
$$;

-- ── 가짜: 직원 둘(sales · picking) · SO 여덟(상태마다 하나 · notes 'Old note' · updated_at 하루 전) ──
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'shn1-sales@test.invalid', 'SHN1 Sales', 'worker', '["sales"]', '{}') returning auth_user_id::text as u_sales, id::text as st_sales \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'shn1-picker@test.invalid', 'SHN1 Picker', 'worker', '["picking"]', '{}') returning auth_user_id::text as u_pick \gset
select c.id::text as cust, c.currency_id::text as cur from public.customer c where c.is_active order by c.created_at, c.id limit 1 \gset
create temp table t_so (id text, so_number text, status text, rest0 text, full0 text);
with ins as (
  insert into public.so (so_number, customer_id, channel, intake, currency_id, status, shipping_notes, closed_at, closed_reason, created_at, updated_at)
  select v.no, :'cust'::uuid, 'warehouse', 'manual', :'cur'::uuid, v.st, 'Old note',
         case when v.st in ('fulfilled', 'cancelled') then now() - interval '1 day' end, case when v.st = 'cancelled' then 'voided' end,
         now() - interval '2 day', now() - interval '1 day'
  from (values ('SO-79971', 'draft'), ('SO-79972', 'confirmed'), ('SO-79973', 'at_wms'), ('SO-79974', 'picking'), ('SO-79975', 'packed'),
               ('SO-79976', 'shipped'), ('SO-79977', 'fulfilled'), ('SO-79978', 'cancelled')) v(no, st)
  returning id, so_number, status)
insert into t_so (id, so_number, status) select i.id::text, i.so_number, i.status from ins i;
set local session_replication_role = origin;
update t_so t set rest0 = pg_temp.rest(t.id), full0 = pg_temp.fullrow(t.id) where true;
select max(id) filter (where status = 'draft') as s_dr, max(id) filter (where status = 'confirmed') as s_cf, max(id) filter (where status = 'at_wms') as s_aw,
       max(id) filter (where status = 'picking') as s_pk, max(id) filter (where status = 'packed') as s_pd, max(id) filter (where status = 'shipped') as s_sh,
       max(id) filter (where status = 'fulfilled') as s_fu, max(id) filter (where status = 'cancelled') as s_ca from t_so \gset

-- ── S0 스캐너 자기 시험 ──
select pg_temp.chk('S0 scanner self-test: no-where update 1 · where 0 · subquery-where-only 1 · with-update no-where 1 · delete no-where 1 · then-update 1 · string update 0 · where singleton 0',
  pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
  || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text
  || pg_temp.nowhere('update t set a = 1 where singleton returning * into v;')::text, '10111100');

-- ── T1 고칠 수 있는 다섯 상태: draft · confirmed · at_wms · picking · packed ──
select pg_temp.shn(:'u_sales', :'s_dr', '  New note  ', 'Old note') as r1a \gset
select pg_temp.shn(:'u_sales', :'s_cf', '  New note  ', 'Old note') as r1b \gset
select pg_temp.shn(:'u_sales', :'s_aw', '  New note  ', 'Old note') as r1c \gset
select pg_temp.shn(:'u_sales', :'s_pk', '  New note  ', 'Old note') as r1d \gset
select pg_temp.shn(:'u_sales', :'s_pd', '  New note  ', 'Old note') as r1e \gset
select pg_temp.chk('T1a draft → changed true · saved btrim(New note) · status same · updated_by = staff · updated_at moved · other columns same (md5 without notes · updated_*)',
  concat_ws('/', coalesce(pg_temp.j(:'r1a')->>'changed', :'r1a'), pg_temp.j(:'r1a')->>'shipping_notes', pg_temp.srow(:'s_dr'), (pg_temp.rest(:'s_dr') = (select rest0 from t_so where id = :'s_dr'))::text),
  'true/New note/New note|draft|' || :'st_sales' || '|true/true');
select pg_temp.chk('T1b confirmed → same',
  concat_ws('/', coalesce(pg_temp.j(:'r1b')->>'changed', :'r1b'), pg_temp.j(:'r1b')->>'shipping_notes', pg_temp.srow(:'s_cf'), (pg_temp.rest(:'s_cf') = (select rest0 from t_so where id = :'s_cf'))::text),
  'true/New note/New note|confirmed|' || :'st_sales' || '|true/true');
select pg_temp.chk('T1c at_wms → same',
  concat_ws('/', coalesce(pg_temp.j(:'r1c')->>'changed', :'r1c'), pg_temp.j(:'r1c')->>'shipping_notes', pg_temp.srow(:'s_aw'), (pg_temp.rest(:'s_aw') = (select rest0 from t_so where id = :'s_aw'))::text),
  'true/New note/New note|at_wms|' || :'st_sales' || '|true/true');
select pg_temp.chk('T1d picking → same',
  concat_ws('/', coalesce(pg_temp.j(:'r1d')->>'changed', :'r1d'), pg_temp.j(:'r1d')->>'shipping_notes', pg_temp.srow(:'s_pk'), (pg_temp.rest(:'s_pk') = (select rest0 from t_so where id = :'s_pk'))::text),
  'true/New note/New note|picking|' || :'st_sales' || '|true/true');
select pg_temp.chk('T1e packed (screen «Finalized») → same',
  concat_ws('/', coalesce(pg_temp.j(:'r1e')->>'changed', :'r1e'), pg_temp.j(:'r1e')->>'shipping_notes', pg_temp.srow(:'s_pd'), (pg_temp.rest(:'s_pd') = (select rest0 from t_so where id = :'s_pd'))::text),
  'true/New note/New note|packed|' || :'st_sales' || '|true/true');

-- ── T2 거부 셋: shipped · fulfilled · cancelled — 한 문장 · 행 무변(전 칸 md5) ──
select pg_temp.chk('T2a shipped → refused · row untouched',
  pg_temp.shn(:'u_sales', :'s_sh', 'New note', 'Old note') || ' / ' || (pg_temp.fullrow(:'s_sh') = (select full0 from t_so where id = :'s_sh'))::text,
  'ERR P0001: Order SO-79976 has already shipped — shipping notes can no longer be changed — nothing was saved / true');
select pg_temp.chk('T2b fulfilled → refused · row untouched',
  pg_temp.shn(:'u_sales', :'s_fu', 'New note', 'Old note') || ' / ' || (pg_temp.fullrow(:'s_fu') = (select full0 from t_so where id = :'s_fu'))::text,
  'ERR P0001: Order SO-79977 has already been shipped and invoiced — shipping notes can no longer be changed — nothing was saved / true');
select pg_temp.chk('T2c cancelled → refused · row untouched',
  pg_temp.shn(:'u_sales', :'s_ca', 'New note', 'Old note') || ' / ' || (pg_temp.fullrow(:'s_ca') = (select full0 from t_so where id = :'s_ca'))::text,
  'ERR P0001: Order SO-79978 is cancelled — shipping notes can no longer be changed — nothing was saved / true');

-- ── T3 비우기 · 같은 값 · 빈 글 = null ──
select pg_temp.shn(:'u_sales', :'s_dr', '   ', 'New note') as r3a \gset
select pg_temp.chk('T3a blank text (spaces) on draft → changed true · shipping_notes null in the result and on the row',
  concat_ws('/', coalesce(pg_temp.j(:'r3a')->>'changed', :'r3a'), (pg_temp.j(:'r3a') ? 'shipping_notes')::text, coalesce(pg_temp.j(:'r3a')->>'shipping_notes', '(null)'), pg_temp.srow(:'s_dr')),
  'true/true/(null)/(null)|draft|' || :'st_sales' || '|true');
select pg_temp.fullrow(:'s_cf') as cf_full1 \gset
select pg_temp.shn(:'u_sales', :'s_cf', 'New note   ', ' New note') as r3b \gset
select pg_temp.chk('T3b same value after btrim (text «New note   » · p_old « New note») on confirmed → changed false · echoes the value · row untouched (all columns md5)',
  concat_ws('/', coalesce(pg_temp.j(:'r3b')->>'changed', :'r3b'), pg_temp.j(:'r3b')->>'shipping_notes', (pg_temp.fullrow(:'s_cf') = :'cf_full1')::text), 'false/New note/true');
select pg_temp.fullrow(:'s_dr') as dr_full1 \gset
select pg_temp.shn(:'u_sales', :'s_dr', '', '') as r3c \gset
select pg_temp.chk('T3c already null · text «» · p_old «» → changed false · row untouched',
  concat_ws('/', coalesce(pg_temp.j(:'r3c')->>'changed', :'r3c'), coalesce(pg_temp.j(:'r3c')->>'shipping_notes', '(null)'), (pg_temp.fullrow(:'s_dr') = :'dr_full1')::text), 'false/(null)/true');
select pg_temp.shn(:'u_sales', :'s_dr', 'Back again', '  ') as r3d \gset
select pg_temp.chk('T3d row null · p_old «  » (blank = null) → accepted · changed true · Back again',
  concat_ws('/', coalesce(pg_temp.j(:'r3d')->>'changed', :'r3d'), pg_temp.srow(:'s_dr')), 'true/Back again|draft|' || :'st_sales' || '|true');

-- ── T4 거부 다섯 ──
select pg_temp.fullrow(:'s_aw') as aw_full1 \gset
select pg_temp.chk('T4a p_old differs (row = New note · screen saw Old note) → refused · one sentence · row untouched',
  pg_temp.shn(:'u_sales', :'s_aw', 'Other note', 'Old note') || ' / ' || (pg_temp.fullrow(:'s_aw') = :'aw_full1')::text,
  'ERR P0001: Someone changed the shipping notes on order SO-79973 just now — reload the order and try again — nothing was saved / true');
select pg_temp.chk('T4b unknown order → refused',
  pg_temp.shn(:'u_sales', '00000000-0000-4000-8000-00000000c0de', 'x', null), 'ERR P0001: Order 00000000-0000-4000-8000-00000000c0de not found — nothing was saved');
select pg_temp.fullrow(:'s_pd') as pd_full1 \gset
select pg_temp.chk('T4c staff without sales write (picking only) → refused by ims_require_write(sales) · row untouched',
  pg_temp.shn(:'u_pick', :'s_pd', 'Picker note', 'New note') || ' / ' || (pg_temp.fullrow(:'s_pd') = :'pd_full1')::text,
  'ERR P0001: You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved / true');
select pg_temp.chk('T4d function acl: authenticated execute · anon no · service_role no · public no · security definer · search_path pinned',
  has_function_privilege('authenticated', 'public.so_shipping_notes_set(uuid, text, text)', 'execute')::text || has_function_privilege('anon', 'public.so_shipping_notes_set(uuid, text, text)', 'execute')::text
  || has_function_privilege('service_role', 'public.so_shipping_notes_set(uuid, text, text)', 'execute')::text || (select (p.proacl::text ~ '=X/' and p.proacl::text !~ '^\{=')::text || '/' || p.prosecdef::text || '/' || (array_to_string(p.proconfig, ',') ~ 'search_path=public, pg_temp')::text from pg_proc p where p.oid = 'public.so_shipping_notes_set(uuid, text, text)'::regprocedure),
  'truefalsefalsetrue/true/true');
select pg_temp.fullrow(:'s_pk') as pk_full1 \gset
select pg_temp.chk('T4e 2001 characters after btrim → refused (limit 2000) · row untouched',
  pg_temp.shn(:'u_sales', :'s_pk', ' ' || repeat('a', 2001) || ' ', 'New note') || ' / ' || (pg_temp.fullrow(:'s_pk') = :'pk_full1')::text,
  'ERR P0001: Shipping notes are 2001 characters long — the limit is 2000 — nothing was saved / true');

-- ── T5 실물 packed 오더: 고친 뒤 이 칸 하나만 · 예약 · 줄 · 원장 · WMS 표 무변 ──
select pg_temp.shn(:'u_sales', :'so_real', 'SHN1 real packed note', nullif(:'real_old', '')) as r5 \gset
select pg_temp.chk('T5a real packed order (' || :'so_real_no' || ') → changed true · status packed · other columns same as begin 앞',
  concat_ws('/', coalesce(pg_temp.j(:'r5')->>'changed', :'r5'), pg_temp.srow(:'so_real'), (pg_temp.rest(:'so_real') = :'real_rest0')::text),
  'true/SHN1 real packed note|packed|' || :'st_sales' || '|true/true');
select pg_temp.chk('T5b so_reserve · so_line · wms_pack_tasks · wms_pick_tasks (all rows md5) · inv_ledger (count/md5) = begin 앞',
  concat_ws(' · ',
    (select coalesce(md5(string_agg(to_jsonb(t)::text, '|' order by t.id)), '(none)') from public.so_reserve t) = :'m_res0',
    (select coalesce(md5(string_agg(to_jsonb(t)::text, '|' order by t.id)), '(none)') from public.so_line t) = :'m_line0',
    (select coalesce(md5(string_agg(to_jsonb(t)::text, '|' order by t.id)), '(none)') from public.wms_pack_tasks t) = :'m_pack0',
    (select coalesce(md5(string_agg(to_jsonb(t)::text, '|' order by t.id)), '(none)') from public.wms_pick_tasks t) = :'m_pick0',
    (select count(*)::text || '/' || coalesce(md5(string_agg(to_jsonb(t)::text, '|' order by t.id)), '(none)') from public.inv_ledger t) = :'m_led0'),
  't · t · t · t · t');

-- ── T6 REST 첫 겹(정적): 새 함수의 update · delete 에 깊이 0 WHERE ──
select pg_temp.chk('T6 nowhere(prosrc) = 0 for so_shipping_notes_set',
  (select string_agg(proname || ' ' || pg_temp.nowhere(prosrc)::text, ' · ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_shipping_notes_set'),
  'so_shipping_notes_set 0');

-- ── M 무접촉 · comment · 상태 목록 ──
select pg_temp.chk('M1 comment carries 판정 880 · so_header_update · so_finalize · so_status_guard untouched (prosrc md5 = begin 앞)',
  (obj_description('public.so_shipping_notes_set(uuid, text, text)'::regprocedure, 'pg_proc') ~ '^shn-1 판정 880')::text || '/'
  || (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5 where t.proname in ('so_header_update', 'so_finalize', 'so_status_guard')),
  'true/3');
select pg_temp.chk('M2 so_status_ck still has exactly the eight statuses T1 (5 allowed) + T2 (3 refused) cover',
  (select string_agg(x, ',' order by x) from (select (regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g'))[1] as x from pg_constraint c where c.conrelid = 'public.so'::regclass and c.conname = 'so_status_ck') y),
  'at_wms,cancelled,confirmed,draft,fulfilled,packed,picking,shipped');

-- ── 결과 ──
select clock_timestamp() - :'t_begin0'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :w_so and (select count(*) from public.ims_staff) = :w_staff
            and (select count(*) from public.so where so_number like 'SO-7997%') = 0
            and (select md5(to_jsonb(s)::text) from public.so s where s.id = :'so_real'::uuid) = :'real_full0'
            and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_shipping_notes_set') = (case when :'fn_absent' = 't' then 0 else 1 end)
       then 'Z1 OK real rows unchanged (so · staff · no SO-7997x leftovers · real packed order row = begin 앞) · new fn presence = begin 앞' else 'Z1 MISMATCH real rows or functions changed' end as z1;
