-- supabase/tests/qbo_1c_check.sql — qbo-1c REST safeupdate 고침 검증 (2026-10-29 · asung-workflow §4 「REST 두 겹」 §79-e 1)
-- [테스트 · Asung-IMS] 시험 적용 장치 — 기준(begin 앞: qbo_* 함수 17 의 prosrc · md5 · comment · acl) → begin → (-v mig 면 \i) → S 정적(깊이 0 WHERE 스캐너 = safeupdate 규칙) · M md5 · P 권한 · F 기능(연결 행이 없을 때만) → rollback → Z
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261029210000_qbo_1c_rest_safeupdate.sql -f supabase/tests/qbo_1c_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) · 연결 행 있음 6 / 없음 13 · 확인(적용 뒤) · 연결 행 있음 5 / 없음 12 — M1(md5 바뀜 · 적용 전 기준)은 시험 갈래만 · F(가짜 연결 일곱)는 연결 행이 없을 때만(singleton)
--   ⚠️ psql 직결은 safeupdate 를 못 싣는다(ar-2b 실측) ⇒ 여기는 정적 겹 · 둘째 겹 = 적용 뒤 REST 로 ping(EF qbo · company_name 이 채워지면 통과)
--   쓰기 0 — 지금 있는 연결 행은 읽지도 바꾸지도 않는다(F 는 연결 행이 없을 때만 · 가짜 직원 · rollback)
\set ON_ERROR_STOP on
\pset pager off
create temp table t_pre as
  select p.proname, p.prosrc, md5(p.prosrc) as md5, p.proacl::text as acl, p.prosecdef, coalesce(obj_description(p.oid, 'pg_proc'), '') as cmt
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%';
select (select count(*) from t_pre) as n_fn, (select count(*) from public.qbo_connection) as w_conn, (select count(*) from public.qbo_oauth_state) as w_state,
       (select count(*) from public.ims_staff) as w_staff, (select count(*) from public.mail_outbox) as w_mail, (select count(*) from vault.secrets) as w_vault,
       (select coalesce(c.value, '9341458557490536') from (select 1) x left join public.inv_config c on c.key = 'qbo_realm_sandbox') as realm \gset
select (:w_conn = 0) as no_conn \gset
\echo '── 기준: qbo_* 함수' :n_fn '· qbo_connection' :w_conn '· state' :w_state '· staff' :w_staff '· mail_outbox' :w_mail '· vault' :w_vault '· realm' :realm
\if :{?mig}
\set pre_want 7
\if :no_conn
\set EXPECT_OK 13
\else
\set EXPECT_OK 6
\endif
\else
\set pre_want 0
\if :no_conn
\set EXPECT_OK 12
\else
\set EXPECT_OK 5
\endif
\endif
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
-- safeupdate 의 규칙을 정적으로 센다(ar_2b_check.sql 의 것 그대로): 문장마다 머리 동사가 update · delete(then · else · loop · begin 뒤 포함) 또는 with 뒤 최상위 update · delete 이고 깊이 0 에 where 가 없으면 하나
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
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  raise exception using errcode = 'P7777', message = coalesce(v, '(null)');
exception when sqlstate 'P7777' then return sqlerrm;
          when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
$$;
create function pg_temp.do_as(p_role text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute format('set local role %I', p_role);
  execute p_sql into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.conn(p_col text) returns text language plpgsql as $$ declare v text; begin execute format('select %s::text from public.qbo_connection', p_col) into v; return coalesce(v, '(null)'); exception when others then return 'ERR ' || sqlstate; end $$;

-- ── S 정적 ──
select pg_temp.chk('S0 scanner self-test: no-where update 1 · where 0 · subquery-where-only 1 · with-update no-where 1 · delete no-where 1 · then-update 1 · string update 0 · where singleton 0',
  pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
  || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text
  || pg_temp.nowhere('update t set a = 1 where singleton returning * into v;')::text, '10111100');
select pg_temp.chk('S1 재현(begin 앞 판): 여섯 함수의 WHERE 없는 update · delete — 시험 갈래 7(name_set 1 · claim 1 · save 1 · delete 2 · mark 1 · last_error 1) · 확인 갈래 0',
  (select sum(pg_temp.nowhere(prosrc))::text from t_pre where proname in ('qbo_company_name_set', 'qbo_refresh_claim', 'qbo_refresh_save', 'qbo_connection_delete', 'qbo_mark_needs_reconnect', 'qbo_last_error_set')), :'pre_want');
select pg_temp.chk('S2 통과(지금 판): qbo_* 함수 17 전부 0 (함수마다 「이름 0」)',
  (select string_agg(proname || ' ' || pg_temp.nowhere(prosrc)::text, ' · ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname like 'qbo\_%'),
  (select string_agg(proname || ' 0', ' · ' order by proname) from t_pre));

-- ── M md5 ──
\if :{?mig}
select pg_temp.chk('M1 (시험 갈래) 여섯의 prosrc md5 가 begin 앞과 다르다 · 여섯 모두 where singleton 포함 · delete 는 state_hash is not null',
  (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname where t.proname in ('qbo_company_name_set', 'qbo_refresh_claim', 'qbo_refresh_save', 'qbo_connection_delete', 'qbo_mark_needs_reconnect', 'qbo_last_error_set') and md5(p.prosrc) <> t.md5 and p.prosrc ~ 'where singleton')
  || '/' || (select (prosrc ~ 'delete from public\.qbo_oauth_state s where s\.state_hash is not null')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_connection_delete'), '6/true');
\endif
select pg_temp.chk('M2 다른 qbo_* 함수(열하나) 무접촉(prosrc md5 begin 앞 = 지금) · 함수 수 17 그대로',
  (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5 where t.proname not in ('qbo_company_name_set', 'qbo_refresh_claim', 'qbo_refresh_save', 'qbo_connection_delete', 'qbo_mark_needs_reconnect', 'qbo_last_error_set'))
  || '/' || (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname like 'qbo\_%'), '11/17');

-- ── P 권한 · comment ──
select pg_temp.chk('P1 여섯: acl service_role 만 · definer · comment 그대로(begin 앞과 같다)',
  (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname
    where t.proname in ('qbo_company_name_set', 'qbo_refresh_claim', 'qbo_refresh_save', 'qbo_connection_delete', 'qbo_mark_needs_reconnect', 'qbo_last_error_set') and p.proacl::text = '{postgres=X/postgres,service_role=X/postgres}' and p.prosecdef and coalesce(obj_description(p.oid, 'pg_proc'), '') = t.cmt and t.acl = p.proacl::text), '6');

-- ── F 기능(연결 행이 없을 때만 · 가짜 연결 → 여섯 창구가 전과 같이 돈다 · 각 update 가 행 하나에 닿는다) ──
\if :no_conn
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'qbx-admin@test.invalid', 'QBX Admin', 'admin', '["ims"]', '{}') returning id::text as st_adm \gset
set local session_replication_role = origin;
select pg_temp.as_user('', 'service_role');
select pg_temp.do_as('service_role', format('select public.qbo_connection_save(''sandbox'', %L, ''RT-1'', ''AT-1'', now() + interval ''1 hour'', now() + interval ''100 days'', %L)::text', :'realm', :'st_adm')) as f1 \gset
select pg_temp.chk('F1 save → connected · version 1', coalesce(pg_temp.j(:'f1')->>'status', :'f1') || '/' || coalesce(pg_temp.j(:'f1')->>'token_version', '?'), 'connected/1');
select pg_temp.do_as('service_role', 'select public.qbo_company_name_set(''Sandbox Company CA 9bca'')::text') as f2 \gset
select pg_temp.chk('F2 company_name_set → name on the row (the call that failed at REST)', coalesce(pg_temp.j(:'f2')->>'company_name', :'f2') || '/' || pg_temp.conn('company_name'), 'Sandbox Company CA 9bca/Sandbox Company CA 9bca');
select pg_temp.do_as('service_role', 'select public.qbo_refresh_claim(gen_random_uuid())::text') as f3 \gset
select pg_temp.chk('F3 refresh_claim → lease on the row · version 1 · refresh token RT-1', coalesce(pg_temp.j(:'f3')->>'token_version', :'f3') || '/' || coalesce(pg_temp.j(:'f3')->>'refresh_token', '?') || '/' || (pg_temp.conn('refreshing_until') <> '(null)')::text, '1/RT-1/true');
select pg_temp.do_as('service_role', 'select public.qbo_refresh_save(1, ''RT-2'', ''AT-2'', now() + interval ''1 hour'', null)::text') as f4 \gset
select pg_temp.chk('F4 refresh_save → version 2 · lease released · stale version refused', coalesce(pg_temp.j(:'f4')->>'token_version', :'f4') || '/' || pg_temp.conn('refreshing_until') || '/' || left(pg_temp.do_as('service_role', 'select public.qbo_refresh_save(1, ''RT-x'', ''AT-x'', now(), null)::text'), 35), '2/(null)/ERR P0001: Token version 1 is stale');
select pg_temp.do_as('service_role', 'select public.qbo_mark_needs_reconnect(''HTTP 400 invalid_grant'')::text') as f5 \gset
select pg_temp.chk('F5 mark → needs_reconnect · was connected · mailed true (1b kept)', coalesce(pg_temp.j(:'f5')->>'status', :'f5') || '/' || coalesce(pg_temp.j(:'f5')->>'was', '?') || '/' || coalesce(pg_temp.j(:'f5')->>'mailed', '?'), 'needs_reconnect/connected/true');
select pg_temp.do_as('service_role', 'select public.qbo_last_error_set(''raced'')::text') as f6 \gset
select pg_temp.chk('F6 last_error_set → status unchanged · last_error', coalesce(pg_temp.j(:'f6')->>'status', :'f6') || '/' || pg_temp.conn('last_error'), 'needs_reconnect/raced');
insert into public.qbo_oauth_state (state_hash, staff_id, env) values (encode(sha256('qbo-1c-state'::bytea), 'hex'), :'st_adm'::uuid, 'sandbox');
select pg_temp.do_as('service_role', 'select public.qbo_connection_delete()::text') as f7 \gset
select pg_temp.chk('F7 delete → deleted true · vault 2 · states 1 · row 0 · state 0 · delete again false', coalesce(pg_temp.j(:'f7')->>'deleted', :'f7') || '/' || coalesce(pg_temp.j(:'f7')->>'vault_rows_removed', '?') || '/' || coalesce(pg_temp.j(:'f7')->>'states_removed', '?') || '/' || pg_temp.try('select count(*)::text from public.qbo_connection') || '/' || pg_temp.try('select count(*)::text from public.qbo_oauth_state') || '/' || coalesce(pg_temp.j(pg_temp.do_as('service_role', 'select public.qbo_connection_delete()::text'))->>'deleted', '?'), 'true/2/1/0/0/false');
\else
\echo '── F skipped: a real QuickBooks connection is on file (qbo_connection rows =' :w_conn ') — the functional layer for this run is the REST ping after apply'
\endif

-- ── 결과 ──
select clock_timestamp() - :'t_begin0'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.qbo_connection) = :w_conn and (select count(*) from public.qbo_oauth_state) = :w_state and (select count(*) from public.ims_staff) = :w_staff
            and (select count(*) from public.mail_outbox) = :w_mail and (select count(*) from vault.secrets) = :w_vault
            and (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn
       then 'Z1 OK real rows unchanged (connection · state · staff · mail_outbox · vault) · 17 function md5 = begin 앞' else 'Z1 MISMATCH real rows or functions changed' end as z1;
