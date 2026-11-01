-- supabase/tests/mcp_2_check.sql — mcp-2 검증: 표 mcp_call_log · 창구 mcp_log_add · mcp_log_purge · 권한(ims_connector · authenticated · anon · service_role) · staff_id 채움 · 1 년 지우기 (2026-11-01 UTC · 판정 924)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4 · 잠금 규칙) — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i) → 가짜 재료 → 검증 → rollback → 실제 행 무변
--   Claude Code(시험): MIG=supabase/migrations/20261101000546_mcp_2_call_log.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/mcp_2_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 두 갈래의 차이는 G0(시험만 · echo 줄 · t_res 밖) · Z 의 표 유무(시험 없음 · 확인 있음) · 기대 OK 수는 같다
--   쓰기: 가짜 직원 2(mcp79002 · admin · manager) · mcp_call_log 가짜 줄(client_id mcp-test-79002 · 전부 rollback) · 시퀀스 무접촉(mcp_call_log identity 는 새 표 · 실물 번호 아님) · 실제 행 0 변경
--   REST 두 겹: ① 아래 L1 nowhere 정적 셈(purge 의 delete 는 WHERE 있음 · add 는 insert 뿐) ② 실호출은 배포 뒤 Caleb 의 curl 묶음 ④(mcp_call_log 한 줄 refused)
\set ON_ERROR_STOP on
\set EXPECT_OK 29
\pset pager off
select (select count(*) from public.ims_staff) as n_staff \gset
\if :{?mig}
\set n_log0 -1
\else
select count(*) as n_log0 from public.mcp_call_log \gset
\endif
\echo '── 기준: staff' :n_staff '· mcp_call_log 줄(확인 갈래만 · 시험은 -1)' :n_log0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
-- 역할 · claims 를 바꿔 한 문장을 돌린다(끝나면 되돌린다 · 오류는 'ERR sqlstate: msg' 글로) — mcp_1a_check 의 as_conn 그대로
create function pg_temp.as_conn(p_role text, p_claims jsonb, p_sql text) returns text language plpgsql as $$
declare v text; v_old text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', coalesce(p_claims::text, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into v;
  exception when others then
    v := 'ERR ' || sqlstate || ': ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
  return coalesce(v, '(null)');
end $$;
create function pg_temp.st(v text, p text) returns text language sql as $$ select case when v like p || '%' then p else left(v, 120) end $$;
-- safeupdate 정적 셈(ar_2b_check.sql 의 nowhere 그대로): 깊이 0 WHERE 없는 update · delete 수
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

-- ── A) 착지 ──
select pg_temp.chk('A1 칸 12 · 꼴', (select string_agg(column_name || ':' || data_type, ' ' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'mcp_call_log'),
  'id:bigint called_at:timestamp with time zone auth_user_id:uuid staff_id:uuid client_id:text tool:text args:jsonb ms:integer outcome:text error_code:text error_message:text result_bytes:integer');
select pg_temp.chk('A2 제약 — PK · outcome CHECK · error_message 200 CHECK · FK 0', (select string_agg(conname || ':' || contype::text, ' ' order by conname) from pg_constraint where conrelid = 'public.mcp_call_log'::regclass),
  'mcp_call_log_error_message_ck:c mcp_call_log_outcome_ck:c mcp_call_log_pkey:p');
select pg_temp.chk('A3 색인 둘(called_at · staff_id+called_at)', (select string_agg(indexname, ' ' order by indexname) from pg_indexes where schemaname = 'public' and tablename = 'mcp_call_log' and indexname <> 'mcp_call_log_pkey'), 'mcp_call_log_called_idx mcp_call_log_staff_called_idx');
select pg_temp.chk('A4 표 acl(authenticated r 만 · service_role · anon · ims_connector 0) + RLS', (select c.relacl::text || ' rls=' || c.relrowsecurity::text from pg_class c where c.oid = 'public.mcp_call_log'::regclass), '{postgres=arwdDxtm/postgres,authenticated=r/postgres} rls=true');
select pg_temp.chk('A5 정책 하나 — select · authenticated · ims_is_admin()', (select string_agg(policyname || ':' || cmd || ':' || roles::text || ':' || (qual like '%ims_is_admin()%')::text, ' ') from pg_policies where schemaname = 'public' and tablename = 'mcp_call_log'), 'mcp_call_log_select_admin:SELECT:{authenticated}:true');
select pg_temp.chk('A6 창구 acl — service_role 만(PUBLIC · anon · authenticated · ims_connector 0)', (select string_agg(p.proname || '=' || p.proacl::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_log_add', 'mcp_log_purge')),
  'mcp_log_add={postgres=X/postgres,service_role=X/postgres} mcp_log_purge={postgres=X/postgres,service_role=X/postgres}');
select pg_temp.chk('A7 창구 둘 definer · volatile · search_path 고정', (select string_agg(p.proname || ':' || p.prosecdef::text || p.provolatile::text || (p.proconfig::text = '{"search_path=public, pg_temp"}')::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_log_add', 'mcp_log_purge')), 'mcp_log_add:truevtrue mcp_log_purge:truevtrue');

-- ── B) 가짜 직원 둘(admin · manager) ──
create temp table t_f as select gen_random_uuid() as adm_id, gen_random_uuid() as adm_uid, gen_random_uuid() as mgr_id, gen_random_uuid() as mgr_uid, gen_random_uuid() as ghost_uid, 'mcp-test-79002'::text as cid;
insert into public.ims_staff (id, auth_user_id, email, name, role, perms, is_active)
select adm_id, adm_uid, 'mcp79002adm@test.invalid', 'MCP Fake Admin', 'admin', '["ims"]'::jsonb, true from t_f union all
select mgr_id, mgr_uid, 'mcp79002mgr@test.invalid', 'MCP Fake Manager', 'manager', '["ims","claude","sales"]'::jsonb, true from t_f;
select adm_id, adm_uid, mgr_id, mgr_uid, ghost_uid, cid from t_f \gset
select set_config('mcp.adm_uid', :'adm_uid', true), set_config('mcp.mgr_uid', :'mgr_uid', true), set_config('mcp.ghost_uid', :'ghost_uid', true), set_config('mcp.cid', :'cid', true);
create function pg_temp.cl(p_uid text, p_role text) returns jsonb language sql as $$ select jsonb_build_object('sub', p_uid, 'role', p_role, 'aud', 'authenticated') $$;

-- ── C) 권한 — 표 직접 쓰기 · 읽기 · 창구 EXECUTE ──
select pg_temp.chk('C1 ims_connector 표 insert → 42501', left(pg_temp.as_conn('ims_connector', pg_temp.cl(:'mgr_uid', 'ims_connector') || '{"client_id":"x"}', $q$insert into public.mcp_call_log (tool, outcome) values ('x', 'ok') returning id::text$q$), 9), 'ERR 42501');
select pg_temp.chk('C2 authenticated 표 insert → 42501', left(pg_temp.as_conn('authenticated', pg_temp.cl(:'adm_uid', 'authenticated'), $q$insert into public.mcp_call_log (tool, outcome) values ('x', 'ok') returning id::text$q$), 9), 'ERR 42501');
select pg_temp.chk('C3 service_role 표 insert → 42501(창구로만)', left(pg_temp.as_conn('service_role', '{"role":"service_role"}', $q$insert into public.mcp_call_log (tool, outcome) values ('x', 'ok') returning id::text$q$), 9), 'ERR 42501');
select pg_temp.chk('C4 anon 표 select → 42501', left(pg_temp.as_conn('anon', '{"role":"anon"}', $q$select count(*)::text from public.mcp_call_log$q$), 9), 'ERR 42501');
select pg_temp.chk('C5 service_role 표 select → 42501(읽기도 없다)', left(pg_temp.as_conn('service_role', '{"role":"service_role"}', $q$select count(*)::text from public.mcp_call_log$q$), 9), 'ERR 42501');
select pg_temp.chk('C6 ims_connector · authenticated · anon mcp_log_add → 42501 셋', left(pg_temp.as_conn('ims_connector', pg_temp.cl(:'mgr_uid', 'ims_connector'), $q$select public.mcp_log_add(null, 'c', 'find_order', '{}', 1, 'ok')::text$q$), 9) || ' ' ||
  left(pg_temp.as_conn('authenticated', pg_temp.cl(:'adm_uid', 'authenticated'), $q$select public.mcp_log_add(null, 'c', 'find_order', '{}', 1, 'ok')::text$q$), 9) || ' ' ||
  left(pg_temp.as_conn('anon', '{"role":"anon"}', $q$select public.mcp_log_add(null, 'c', 'find_order', '{}', 1, 'ok')::text$q$), 9), 'ERR 42501 ERR 42501 ERR 42501');
select pg_temp.chk('C7 ims_connector · authenticated mcp_log_purge → 42501 둘', left(pg_temp.as_conn('ims_connector', pg_temp.cl(:'mgr_uid', 'ims_connector'), $q$select public.mcp_log_purge()::text$q$), 9) || ' ' ||
  left(pg_temp.as_conn('authenticated', pg_temp.cl(:'adm_uid', 'authenticated'), $q$select public.mcp_log_purge()::text$q$), 9), 'ERR 42501 ERR 42501');

-- ── D) service_role 이 창구로 쓴다 — staff_id 채움 · 200 자 · 3 KB args 그대로 · CHECK ──
select pg_temp.as_conn('service_role', '{"role":"service_role"}', format($q$select public.mcp_log_add(%L, %L, 'find_order', '{"so_number":"SO-25001"}', 123, 'ok', null, null, 2048)::text$q$, :'mgr_uid', :'cid')) as id1 \gset
select pg_temp.as_conn('service_role', '{"role":"service_role"}', format($q$select public.mcp_log_add(%L, %L, 'stock', '{"query":"LAC"}', 45, 'refused', '42501', repeat('x', 300), null)::text$q$, :'ghost_uid', :'cid')) as id2 \gset
select pg_temp.as_conn('service_role', '{"role":"service_role"}', format($q$select public.mcp_log_add(%L, %L, 'backorders', jsonb_build_object('head', repeat('y', 3000)), 9000, 'error', '57014', 'timeout', null)::text$q$, :'adm_uid', :'cid')) as id3 \gset
select pg_temp.chk('D1 service_role mcp_log_add 셋 → id 셋(숫자)', (:'id1' ~ '^[0-9]+$')::text || (:'id2' ~ '^[0-9]+$')::text || (:'id3' ~ '^[0-9]+$')::text, 'truetruetrue');
select pg_temp.chk('D2 줄 1 — staff_id = manager 의 ims_staff.id · client_id · outcome ok · result_bytes', (select (staff_id = :'mgr_id'::uuid)::text || ' ' || client_id || ' ' || outcome || ' ' || result_bytes::text || ' ' || coalesce(error_code, '-') from public.mcp_call_log where id = :'id1'::bigint), 'true mcp-test-79002 ok 2048 -');
select pg_temp.chk('D3 줄 2 — 모르는 auth_user_id → staff_id null(auth_user_id 는 남음) · error_message 200 자로 잘림 · refused 42501', (select (staff_id is null)::text || ' ' || (auth_user_id = :'ghost_uid'::uuid)::text || ' ' || length(error_message)::text || ' ' || outcome || ' ' || error_code from public.mcp_call_log where id = :'id2'::bigint), 'true true 200 refused 42501');
select pg_temp.chk('D4 줄 3 — args 3 KB 그대로(창구는 받는 대로 · 자르기는 EF 몫) · ms 9000 · error 57014', (select length(args->>'head')::text || ' ' || ms::text || ' ' || outcome || ' ' || error_code || ' ' || (staff_id = :'adm_id'::uuid)::text from public.mcp_call_log where id = :'id3'::bigint), '3000 9000 error 57014 true');
select pg_temp.chk('D5 outcome 밖 값 → CHECK mcp_call_log_outcome_ck', pg_temp.st(pg_temp.as_conn('service_role', '{"role":"service_role"}', $q$select public.mcp_log_add(null, 'c', 'stock', '{}', 1, 'maybe')::text$q$), 'ERR 23514'), 'ERR 23514');
select pg_temp.chk('D6 tool null → 23502', pg_temp.st(pg_temp.as_conn('service_role', '{"role":"service_role"}', $q$select public.mcp_log_add(null, 'c', null, '{}', 1, 'ok')::text$q$), 'ERR 23502'), 'ERR 23502');
select pg_temp.chk('D7 called_at 기본 now() · 이 트랜잭션의 셋 모두', (select count(*)::text from public.mcp_call_log where client_id = :'cid' and called_at = now()), '3');

-- ── E) 읽기 — admin 만(RLS) ──
select pg_temp.chk('E1 authenticated admin → 이 시험의 줄 3 보인다', pg_temp.as_conn('authenticated', pg_temp.cl(:'adm_uid', 'authenticated'), format($q$select count(*)::text from public.mcp_call_log where client_id = %L$q$, :'cid')), '3');
select pg_temp.chk('E2 authenticated manager(claude 있어도) → 0 줄(RLS · 오류 아님)', pg_temp.as_conn('authenticated', pg_temp.cl(:'mgr_uid', 'authenticated'), format($q$select count(*)::text from public.mcp_call_log where client_id = %L$q$, :'cid')), '0');
select pg_temp.chk('E3 authenticated admin 이 표에 update · delete → 42501(select 만)', left(pg_temp.as_conn('authenticated', pg_temp.cl(:'adm_uid', 'authenticated'), format($q$delete from public.mcp_call_log where client_id = %L returning id::text$q$, :'cid')), 9) || ' ' ||
  left(pg_temp.as_conn('authenticated', pg_temp.cl(:'adm_uid', 'authenticated'), format($q$update public.mcp_call_log set ms = 1 where client_id = %L returning id::text$q$, :'cid')), 9), 'ERR 42501 ERR 42501');

-- ── F) 지우기 — 1 년 지난 줄만(가짜 시각은 소유자가 직접 insert · 트리거 없는 표) ──
insert into public.mcp_call_log (called_at, client_id, tool, outcome) values (now() - interval '400 days', :'cid', 'old400', 'ok'), (now() - interval '364 days', :'cid', 'old364', 'ok'), (now() - interval '10 days', :'cid', 'old10', 'ok');
select count(*) as n_expired from public.mcp_call_log where called_at < now() - interval '1 year' \gset
select pg_temp.as_conn('service_role', '{"role":"service_role"}', $q$select public.mcp_log_purge()::text$q$) as purged \gset
select pg_temp.chk('F1 service_role purge → 지운 수 = 1 년 넘은 줄 수(이 시험의 old400 포함 · ≥ 1)', :'purged' || ' ' || (:n_expired >= 1)::text, :'n_expired'::text || ' true');
select pg_temp.chk('F2 purge 뒤 — old400 없음 · old364 · old10 · 이 시험의 셋 남음', (select string_agg(tool, ' ' order by tool) from public.mcp_call_log where client_id = :'cid'), 'backorders find_order old10 old364 stock');
select pg_temp.chk('F3 purge 두 번째(postgres 직접) → 0', public.mcp_log_purge()::text, '0');

-- ── L) REST 두 겹 ① 정적 ──
select pg_temp.chk('L1 창구 둘 — 깊이 0 WHERE 없는 update · delete 0(purge 의 delete 는 WHERE)', (select sum(pg_temp.nowhere(p.prosrc))::text || ' ' || count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_log_add', 'mcp_log_purge')), '0 2');
select pg_temp.chk('L2 mcp-1a 무접촉 — 도구 5 · 훅 · 도우미 acl 그대로', (select string_agg(p.proname || '=' || p.proacl::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_order', 'mcp_gate', 'ims_access_token_hook')),
  'ims_access_token_hook={postgres=X/postgres,supabase_auth_admin=X/postgres} mcp_gate={postgres=X/postgres} mcp_order={postgres=X/postgres,ims_connector=X/postgres}');
select p.proname, md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_log_add', 'mcp_log_purge') order by 1;

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
\if :{?mig}
select (select count(*) from public.ims_staff) = :n_staff as staff_same, to_regclass('public.mcp_call_log') is null as table_gone_as_expected;
\else
select (select count(*) from public.ims_staff) = :n_staff as staff_same, (select count(*) from public.mcp_call_log) = :n_log0 as log_rows_same;
\endif
