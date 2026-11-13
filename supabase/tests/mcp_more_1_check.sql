-- supabase/tests/mcp_more_1_check.sql — mcp-more-1 검증: 매뉴얼 도구의 문 mcp_manual_gate() — 꼴 · 권한(ims_connector 만) · 열쇠 있는 직원 OK · Claude 열쇠 끈 직원 · 비활성 직원 · 다른 client 거절 · 끄면 다음 호출부터 거절(921) · 읽기 전용 트랜잭션 (2026-11-13 UTC · 판정 1211)
-- [IMS 메인 · Asung-IMS · fazgmyvzzhqybtvtktyg] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i) → 가짜 재료 → 검증 → rollback → 실제 행 무변
--   Claude Code(시험): export MIG=supabase/migrations/20261113021500_mcp_more_1_manual_gate.sql; psql "$(cat ~/.asung-testdb-url)" -X -v ON_ERROR_STOP=1 -v mig="$MIG" -f supabase/tests/mcp_more_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 MIG= 와 -v mig 만 뺀다 — 차이는 G0(시험만 · echo 줄 · t_res 밖) · 끝 줄의 함수 유무 · 기대 OK 수는 같다
--   변이(Claude Code): 문 한 줄(perform public.mcp_gate(null);)을 뺀 사본을 MIG 로 → MISMATCH 가 나와야 한다(exit 3)
--   쓰기: 가짜 직원 넷(mcp79011 · 전부 rollback) · 실제 행 0 변경 · mcp_config 는 읽기만(client id 는 출력하지 않는다)
--   끝: MISMATCH 가 있거나 OK 수가 EXPECT_OK 와 다르면 exit 3
\set ON_ERROR_STOP on
\set EXPECT_OK 27
\pset pager off
select (select count(*) from public.ims_staff) as n_staff, (select count(*) from public.mcp_call_log) as n_log \gset
\echo '── 기준: staff' :n_staff '· mcp_call_log' :n_log
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
grant insert, select on t_res to public; grant usage on sequence t_res_n_seq to public;
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
\set Q 'select public.mcp_manual_gate()::text'

-- ── A) 착지 — 꼴 · 권한 · 무접촉 ──
select pg_temp.chk('A1 함수 하나 · 인자 0 · boolean · definer · stable · search_path 고정 · plpgsql', (select count(*)::text || ' ' || min(pg_get_function_identity_arguments(p.oid)) || '|' || min(pg_get_function_result(p.oid)) || ' ' || bool_and(p.prosecdef)::text || min(p.provolatile::text) || ' ' || min(p.proconfig::text) || ' ' || min(l.lanname)
  from pg_proc p join pg_language l on l.oid = p.prolang where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_manual_gate'), '1 |boolean trues {"search_path=public, pg_temp"} plpgsql');
select pg_temp.chk('A2 acl — ims_connector 만(PUBLIC · anon · authenticated · service_role 0)', (select p.proacl::text from pg_proc p where p.oid = 'public.mcp_manual_gate()'::regprocedure), '{postgres=X/postgres,ims_connector=X/postgres}');
select pg_temp.chk('A3 몸 — 주석 빼고 문장 둘: perform public.mcp_gate(null) · return true', (select regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\s+', ' ', 'g') from pg_proc p where p.oid = 'public.mcp_manual_gate()'::regprocedure), ' begin perform public.mcp_gate(null); return true; end; ');
select pg_temp.chk('A4 EXECUTE 가 있는 역할 = ims_connector · postgres 계열뿐(anon · authenticated · service_role · authenticator f)', (select string_agg(r || ':' || has_function_privilege(r, 'public.mcp_manual_gate()', 'EXECUTE')::text, ' ' order by r) from unnest(array['anon', 'authenticated', 'service_role', 'authenticator', 'ims_connector']) r),
  'anon:false authenticated:false authenticator:false ims_connector:true service_role:false');
select pg_temp.chk('A5 ims_connector 에게 EXECUTE 를 준 public 함수 = 도구 여섯 + 문 하나(PUBLIC 으로 열린 다른 모듈 함수는 이 차수 밖 — 보고에) · 표 · 뷰 권한 0', (select string_agg(p.proname, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 'ims_connector'::regrole and a.privilege_type = 'EXECUTE')) || ' | ' || (select count(*)::text from information_schema.role_table_grants where grantee = 'ims_connector'),
  'mcp_backorders mcp_customer mcp_manual_gate mcp_order mcp_po mcp_sales mcp_stock | 0');
select pg_temp.chk('A6 mcp_gate 무접촉 — acl(아무에게도) · 본문 md5', (select p.proacl::text || ' ' || md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_gate'), '{postgres=X/postgres} e50d34c953bd66513458353207680e6f');
select pg_temp.chk('A7 PUBLIC EXECUTE 가 붙은(또는 acl 이 빈) mcp_ 함수 0', (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mcp\_%' and (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'))), '0');
select pg_temp.chk('A8 comment 있음(판정 1211)', (select (obj_description('public.mcp_manual_gate()'::regprocedure, 'pg_proc') like '%1211%')::text), 'true');

-- ── B) 가짜 직원 넷 — on(claude) · ro(claude:read · 화면 열쇠 없음) · off(admin 인데 claude 없음) · gone(claude 있지만 비활성) ──
create temp table t_f as select gen_random_uuid() as on_uid, gen_random_uuid() as ro_uid, gen_random_uuid() as off_uid, gen_random_uuid() as gone_uid, gen_random_uuid() as ghost_uid, (select c.claude_client_id from public.mcp_config c where c.singleton) as cid;
insert into public.ims_staff (id, auth_user_id, email, name, role, perms, is_active)
select gen_random_uuid(), on_uid,   'mcp79011on@test.invalid',   'MCP Fake On',   'manager', '["ims","claude","sales"]'::jsonb, true  from t_f union all
select gen_random_uuid(), ro_uid,   'mcp79011ro@test.invalid',   'MCP Fake Read', 'worker',  '["claude:read"]'::jsonb,          true  from t_f union all
select gen_random_uuid(), off_uid,  'mcp79011off@test.invalid',  'MCP Fake Off',  'admin',   '["ims","sales","purchasing"]'::jsonb, true from t_f union all
select gen_random_uuid(), gone_uid, 'mcp79011gone@test.invalid', 'MCP Fake Gone', 'manager', '["ims","claude"]'::jsonb,         false from t_f;
select on_uid, ro_uid, off_uid, gone_uid, ghost_uid from t_f \gset
select pg_temp.chk('B0 mcp_config 에 등록된 client 가 있다(없으면 아래 OK 길을 시험할 수 없다)', (select (cid is not null and cid <> '')::text from t_f), 'true');
create function pg_temp.cl(p_uid text, p_cid text) returns jsonb language sql as $$ select jsonb_build_object('sub', p_uid, 'role', 'ims_connector', 'aud', 'authenticated') || case when p_cid is null then '{}'::jsonb else jsonb_build_object('client_id', p_cid) end $$;
create function pg_temp.cid() returns text language sql as $$ select cid from t_f $$;

-- ── C) 문 — 누가 지나가나 ──
select pg_temp.chk('C1 claude 열쇠 있는 직원 → true(직원 id 가 아니다)', pg_temp.as_conn('ims_connector', pg_temp.cl(:'on_uid', pg_temp.cid()), :'Q'), 'true');
select pg_temp.chk('C2 claude:read 만 있고 화면 열쇠가 없는 직원 → true(매뉴얼은 화면 열쇠를 보지 않는다 — help.html 열쇠 null)', pg_temp.as_conn('ims_connector', pg_temp.cl(:'ro_uid', pg_temp.cid()), :'Q'), 'true');
select pg_temp.chk('C3 Claude 열쇠 끈 직원(admin 이어도) → P0001 거절', pg_temp.as_conn('ims_connector', pg_temp.cl(:'off_uid', pg_temp.cid()), :'Q'), 'ERR P0001: Your account does not have the ''claude'' permission — ask an admin to switch it on in Staff — nothing was read');
select pg_temp.chk('C4 비활성 직원(claude 있어도) → P0001 거절', pg_temp.as_conn('ims_connector', pg_temp.cl(:'gone_uid', pg_temp.cid()), :'Q'), 'ERR P0001: No active staff record for this login — nothing was read');
select pg_temp.chk('C5 직원 표에 없는 로그인 → P0001 거절', pg_temp.as_conn('ims_connector', pg_temp.cl(:'ghost_uid', pg_temp.cid()), :'Q'), 'ERR P0001: No active staff record for this login — nothing was read');
select pg_temp.chk('C6 토큰에 client_id 없음 → P0001 거절', pg_temp.as_conn('ims_connector', pg_temp.cl(:'on_uid', null), :'Q'), 'ERR P0001: This tool can only be used through the Claude connector (no OAuth client in the token) — nothing was read');
select pg_temp.chk('C7 등록되지 않은 client_id → P0001 거절', pg_temp.as_conn('ims_connector', pg_temp.cl(:'on_uid', 'mcp-test-79011-not-registered'), :'Q'), 'ERR P0001: This OAuth client is not the registered Claude connector — nothing was read');
select pg_temp.chk('C8 claims 없음(빈 토큰) → P0001 거절', pg_temp.as_conn('ims_connector', null, :'Q'), 'ERR P0001: This tool can only be used through the Claude connector (no OAuth client in the token) — nothing was read');

-- ── D) 다른 역할은 부르지 못한다(42501) — 열쇠가 있는 직원의 화면 세션(authenticated)도 ──
select pg_temp.chk('D1 authenticated(claude 있는 직원의 화면 세션) → 42501', left(pg_temp.as_conn('authenticated', pg_temp.cl(:'on_uid', pg_temp.cid()) || '{"role":"authenticated"}', :'Q'), 9), 'ERR 42501');
select pg_temp.chk('D2 anon → 42501', left(pg_temp.as_conn('anon', '{"role":"anon"}', :'Q'), 9), 'ERR 42501');
select pg_temp.chk('D3 service_role → 42501', left(pg_temp.as_conn('service_role', '{"role":"service_role"}', :'Q'), 9), 'ERR 42501');
select pg_temp.chk('D4 ims_connector 가 mcp_gate 를 직접 → 42501(문 함수로만)', left(pg_temp.as_conn('ims_connector', pg_temp.cl(:'on_uid', pg_temp.cid()), $q$select public.mcp_gate(null)::text$q$), 9), 'ERR 42501');

-- ── E) 호출마다 본다(921) — 끄면 다음 호출부터 거절 · 다시 켜면 통과 · 비활성으로 바꿔도 ──
update public.ims_staff set perms = perms - 'claude' where auth_user_id = :'on_uid';
select pg_temp.chk('E1 열쇠를 끈 뒤 같은 토큰 → 거절', left(pg_temp.as_conn('ims_connector', pg_temp.cl(:'on_uid', pg_temp.cid()), :'Q'), 61), 'ERR P0001: Your account does not have the ''claude'' permission');
update public.ims_staff set perms = perms || '["claude:read"]'::jsonb where auth_user_id = :'on_uid';
select pg_temp.chk('E2 claude:read 로 다시 켜면 → true', pg_temp.as_conn('ims_connector', pg_temp.cl(:'on_uid', pg_temp.cid()), :'Q'), 'true');
update public.ims_staff set is_active = false where auth_user_id = :'on_uid';
select pg_temp.chk('E3 비활성으로 바꾸면 → 거절', left(pg_temp.as_conn('ims_connector', pg_temp.cl(:'on_uid', pg_temp.cid()), :'Q'), 48), 'ERR P0001: No active staff record for this login');

-- ── F) 아무것도 쓰지 않는다 — 읽기 전용 트랜잭션에서도 돈다(PostgREST 는 stable 함수를 읽기 전용으로 부른다) · 기록 표 무접촉 ──
select pg_temp.chk('F1 호출이 mcp_call_log 를 쓰지 않는다(기록은 EF 가 mcp_log_add 로)', (select count(*)::text from public.mcp_call_log), :'n_log');
set transaction read only;
select pg_temp.chk('F2 읽기 전용 트랜잭션 — 통과 길(ro 직원) true', pg_temp.as_conn('ims_connector', pg_temp.cl(:'ro_uid', pg_temp.cid()), :'Q'), 'true');
select pg_temp.chk('F3 읽기 전용 트랜잭션 — 거절 길도 P0001 그대로(25006 아님)', left(pg_temp.as_conn('ims_connector', pg_temp.cl(:'off_uid', pg_temp.cid()), :'Q'), 10), 'ERR P0001:');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select (count(*) filter (where not ok) = 0 and count(*) filter (where ok) = :EXPECT_OK) as all_ok from t_res \gset
select md5(p.prosrc) as mcp_manual_gate_md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_manual_gate';
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
\if :{?mig}
select (select count(*) from public.ims_staff) = :n_staff as staff_same, (select count(*) from public.mcp_call_log) >= :n_log as log_not_shrunk, to_regprocedure('public.mcp_manual_gate()') is null as function_gone_as_expected, (select count(*) from public.ims_staff where email like 'mcp79011%') = 0 as fakes_gone;
\else
select (select count(*) from public.ims_staff) = :n_staff as staff_same, (select count(*) from public.mcp_call_log) >= :n_log as log_not_shrunk, to_regprocedure('public.mcp_manual_gate()') is not null as function_present, (select count(*) from public.ims_staff where email like 'mcp79011%') = 0 as fakes_gone;
\endif
\if :all_ok
\echo 'RESULT OK'
\else
\echo 'RESULT FAIL'
do $$ begin raise exception 'mcp_more_1_check FAILED - see MISMATCH lines above'; end $$;
\endif
