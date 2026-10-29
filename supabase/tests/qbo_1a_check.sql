-- supabase/tests/qbo_1a_check.sql — qbo-1a QuickBooks 연결 DB 검증 (2026-10-29 · 판정 617 · 867 ~ 872)
-- [테스트 · Asung-IMS] 시험 적용 장치 — begin → (-v mig 면 \i) → A ~ I 갈래 → rollback → 실제 행 무변(Z1) · 표 없음 복귀(Z2 시험 갈래만)
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261029160000_qbo_1a_connection_db.sql -f supabase/tests/qbo_1a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK = EXPECT_OK · Z1 둘 다 · Z2 시험 갈래만
--   재료: 가짜 직원 둘(QBX admin · QBX manager · replica 로 넣고 rollback) · 가짜 토큰 글자 · realm 9341458557490536(샌드박스) · 9999000011112222(다른 회사)
--   ⚠️ 역할 바꿔 보기: pg_temp.as_role 이 set local role 을 한 뒤 늘 예외로 끝내 서브트랜잭션과 함께 역할이 되돌아온다(B8 이 확인) · claims 는 pg_temp.as_user(set_config local)
\set ON_ERROR_STOP on
\set EXPECT_OK 43
\pset pager off
\! grep -E '^\\set k11 ' supabase/ops/cutover-delete.sql | grep -c "qbo_connection qbo_oauth_state qbo_call_log" > /tmp/qbo_1a_cut1.txt
\! grep -E '^\\set kall ' supabase/ops/cutover-delete.sql | grep -c ":k11" > /tmp/qbo_1a_cut2.txt
select (select count(*) from public.ims_staff) as w_staff, (select count(*) from public.inv_config) as w_cfg, (select count(*) from vault.secrets) as w_vault,
       (select count(*) from vault.secrets where name like 'qbo/%') as w_vault_qbo, (select count(*) from public.inv_config where key like 'qbo_%') as w_cfg_qbo,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_is_admin') as adm_md5_0 \gset
\echo '── 기준: staff' :w_staff '· inv_config' :w_cfg '· vault.secrets' :w_vault '(qbo/' :w_vault_qbo ') · inv_config qbo_' :w_cfg_qbo
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin0 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create temp table t_cut (n int);
\copy t_cut from '/tmp/qbo_1a_cut1.txt'
\copy t_cut from '/tmp/qbo_1a_cut2.txt'
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
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
-- 역할을 바꿔 한 문장 — set local role 뒤 늘 예외로 끝내 역할이 서브트랜잭션과 함께 되돌아온다
create function pg_temp.as_role(p_role text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute format('set local role %I', p_role);
  execute p_sql into v;
  raise exception using errcode = 'P7777', message = coalesce(v, '(null)');
exception when sqlstate 'P7777' then return sqlerrm;
          when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 역할을 바꿔 쓰기 한 문장 — 성공하면 reset role 로 돌아오고 쓰기는 남는다(as_role 은 늘 되돌린다 — 읽기 · 거부 확인용)
create function pg_temp.do_as(p_role text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute format('set local role %I', p_role);
  execute p_sql into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.vault_n(p_like text) returns int language plpgsql as $$ declare v int; begin select count(*) into v from vault.secrets where name like p_like; return v; end $$;
create function pg_temp.conn(p_col text) returns text language plpgsql as $$ declare v text; begin execute format('select %s::text from public.qbo_connection', p_col) into v; return coalesce(v, '(null)'); exception when others then return 'ERR ' || sqlstate; end $$;
select (to_regclass('public.qbo_connection') is not null) as landed \gset
select encode(sha256('qbo-1a-state-1'::bytea), 'hex') as h1, encode(sha256('qbo-1a-state-2'::bytea), 'hex') as h2, encode(sha256('qbo-1a-state-old'::bytea), 'hex') as h3, encode(sha256('qbo-1a-state-4'::bytea), 'hex') as h4 \gset

-- ── 재료: 가짜 직원 둘 ──
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'qbx-admin@test.invalid', 'QBX Admin', 'admin', '["ims"]', '{}') returning auth_user_id::text as u_adm, id::text as st_adm \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'qbx-mgr@test.invalid', 'QBX Manager', 'manager', '["ims","master","sales"]', '{}') returning auth_user_id::text as u_mgr, id::text as st_mgr \gset

-- ── A 모양 ──
select pg_temp.chk('A1 tables 3 · windows 12 + inner 4 · no text token/secret column on qbo_connection · RLS 3 · policies 1 (call_log select)',
  (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r' and relname in ('qbo_connection', 'qbo_oauth_state', 'qbo_call_log')) || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_status', 'qbo_admin_gate', 'qbo_state_new', 'qbo_realm_clear', 'qbo_state_consume', 'qbo_connection_save', 'qbo_company_name_set', 'qbo_token_get', 'qbo_refresh_claim', 'qbo_refresh_save', 'qbo_mark_needs_reconnect', 'qbo_connection_delete')) || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_env_check', 'qbo_vault_put', 'qbo_vault_get', 'qbo_vault_drop')) || '/' ||
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'qbo_connection' and data_type = 'text' and column_name ~ '(token|secret)') || '/' ||
  (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname in ('qbo_connection', 'qbo_oauth_state', 'qbo_call_log') and relrowsecurity) || '/' ||
  (select count(*) from pg_policies where schemaname = 'public' and tablename in ('qbo_connection', 'qbo_oauth_state', 'qbo_call_log')),
  '3/12/4/0/3/1');
select pg_temp.chk('A2 acl: connection · state = postgres only · call_log = fc_call_log shape · sequence service_role only',
  coalesce((select relacl::text from pg_class where oid = to_regclass('public.qbo_connection')), '(none)') || ' | ' || coalesce((select relacl::text from pg_class where oid = to_regclass('public.qbo_oauth_state')), '(none)') || ' | ' ||
  coalesce((select relacl::text from pg_class where oid = to_regclass('public.qbo_call_log')), '(none)') || ' | ' || coalesce((select relacl::text from pg_class where oid = to_regclass('public.qbo_call_log_id_seq')), '(none)'),
  '{postgres=arwdDxtm/postgres} | {postgres=arwdDxtm/postgres} | {postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=ard/postgres} | {postgres=rwU/postgres,service_role=U/postgres}');
select pg_temp.chk('A3 function acl: staff windows (4) = authenticated only · service windows (8) = service_role only · inner (4) = nobody · all definer',
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_status', 'qbo_admin_gate', 'qbo_state_new', 'qbo_realm_clear') and proacl::text = '{postgres=X/postgres,authenticated=X/postgres}' and prosecdef) || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_state_consume', 'qbo_connection_save', 'qbo_company_name_set', 'qbo_token_get', 'qbo_refresh_claim', 'qbo_refresh_save', 'qbo_mark_needs_reconnect', 'qbo_connection_delete') and proacl::text = '{postgres=X/postgres,service_role=X/postgres}' and prosecdef) || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_env_check', 'qbo_vault_put', 'qbo_vault_get', 'qbo_vault_drop') and proacl::text = '{postgres=X/postgres}' and not prosecdef),
  '4/8/4');
select pg_temp.chk('A4 vault 0.3.1 present · create_secret · update_secret · decrypted_secrets · ims_is_admin untouched · FK only to ims_staff',
  (select extversion from pg_extension where extname = 'supabase_vault') || '/' || (to_regprocedure('vault.create_secret(text, text, text, uuid)') is not null)::text || '/' || (to_regprocedure('vault.update_secret(uuid, text, text, text, uuid)') is not null)::text || '/' || (to_regclass('vault.decrypted_secrets') is not null)::text || '/' ||
  ((select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_is_admin') = :'adm_md5_0')::text || '/' ||
  (select count(*) from pg_constraint con join pg_class c on c.oid = con.conrelid where con.contype = 'f' and c.relname in ('qbo_connection', 'qbo_oauth_state', 'qbo_call_log') and con.confrelid <> 'public.ims_staff'::regclass),
  '0.3.1/true/true/true/true/0');

-- ── B 직원(manager) · role authenticated ──
select pg_temp.as_user(:'u_mgr');
select pg_temp.chk('B1 manager: select qbo_connection · qbo_oauth_state → permission denied (grant 0)',
  pg_temp.as_role('authenticated', 'select count(*)::text from public.qbo_connection') || ' | ' || pg_temp.as_role('authenticated', 'select count(*)::text from public.qbo_oauth_state'),
  'ERR 42501: permission denied for table qbo_connection | ERR 42501: permission denied for table qbo_oauth_state');
select pg_temp.chk('B2 manager: vault.decrypted_secrets · vault.secrets → permission denied for schema vault',
  pg_temp.as_role('authenticated', 'select count(*)::text from vault.decrypted_secrets') || ' | ' || pg_temp.as_role('authenticated', 'select count(*)::text from vault.secrets'),
  'ERR 42501: permission denied for schema vault | ERR 42501: permission denied for schema vault');
select pg_temp.as_role('authenticated', 'select public.qbo_status()::text') as b3 \gset
select pg_temp.chk('B3 manager: qbo_status() works · status none · caller_is_admin false · no key named like token/secret',
  coalesce(pg_temp.j(:'b3')->>'status', :'b3') || '/' || coalesce(pg_temp.j(:'b3')->>'caller_is_admin', '?') || '/' || coalesce((select count(*)::text from jsonb_object_keys(pg_temp.j(:'b3')) k where k ~ '(token|secret)' and k <> 'token_version'), '?'),
  'none/false/0');
select pg_temp.chk('B4 manager: qbo_admin_gate · qbo_state_new · qbo_realm_clear → refused (870)',
  pg_temp.as_role('authenticated', 'select public.qbo_admin_gate()::text') || ' | ' || pg_temp.as_role('authenticated', format('select public.qbo_state_new(''sandbox'', %L)::text', :'h1')) || ' | ' || pg_temp.as_role('authenticated', 'select public.qbo_realm_clear(''sandbox'')::text'),
  'ERR P0001: Only an admin can connect, disconnect or reconnect QuickBooks — nothing was changed | ERR P0001: Only an admin can connect, disconnect or reconnect QuickBooks — nothing was changed | ERR P0001: Only an admin can connect, disconnect or reconnect QuickBooks — nothing was changed');
select pg_temp.chk('B5 manager: service windows → permission denied for function (grant service_role only) · 8 of 8',
  (select count(*) from (values
    (pg_temp.as_role('authenticated', 'select public.qbo_token_get()::text')),
    (pg_temp.as_role('authenticated', format('select public.qbo_state_consume(%L)::text', :'h1'))),
    (pg_temp.as_role('authenticated', 'select public.qbo_connection_save(''sandbox'', ''9341458557490536'', ''r'', ''a'', now(), now(), null)::text')),
    (pg_temp.as_role('authenticated', 'select public.qbo_company_name_set(''x'')::text')),
    (pg_temp.as_role('authenticated', 'select public.qbo_refresh_claim(gen_random_uuid())::text')),
    (pg_temp.as_role('authenticated', 'select public.qbo_refresh_save(1, ''r'', ''a'', now(), null)::text')),
    (pg_temp.as_role('authenticated', 'select public.qbo_mark_needs_reconnect(''x'')::text')),
    (pg_temp.as_role('authenticated', 'select public.qbo_connection_delete()::text'))) v(r) where r like 'ERR 42501: permission denied for function qbo_%')::text,
  '8');
select pg_temp.chk('B6 service role with a staff JWT (claims role authenticated) → "for the QuickBooks service only" (doc_is_service) · status() denied to service_role',
  pg_temp.as_role('service_role', 'select public.qbo_token_get()::text') || ' | ' || pg_temp.as_role('service_role', 'select public.qbo_status()::text'),
  'ERR P0001: qbo_token_get is for the QuickBooks service only — nothing was read | ERR 42501: permission denied for function qbo_status');
select pg_temp.chk('B7 anon: qbo_status → permission denied', pg_temp.as_role('anon', 'select public.qbo_status()::text'), 'ERR 42501: permission denied for function qbo_status');
select pg_temp.chk('B8 role restored after as_role (postgres)', current_user::text, 'postgres');

-- ── C admin ──
select pg_temp.as_user(:'u_adm');
select pg_temp.as_role('authenticated', 'select public.qbo_admin_gate()::text') as c1 \gset
select pg_temp.chk('C1 admin: gate passes → staff_id · name', coalesce(pg_temp.j(:'c1')->>'staff_id', :'c1') || '/' || coalesce(pg_temp.j(:'c1')->>'name', '?'), :'st_adm' || '/QBX Admin');
select pg_temp.do_as('authenticated', format('select public.qbo_state_new(''sandbox'', %L)::text', :'h1')) as c2 \gset
select pg_temp.chk('C2 admin: state_new → row (staff · env · not used) · expires_at = now + 10 min',
  coalesce(pg_temp.j(:'c2')->>'env', :'c2') || '/' || coalesce(((pg_temp.j(:'c2')->>'expires_at')::timestamptz - now())::text, '?') || '/' || coalesce(pg_temp.try(format('select (s.staff_id::text || ''/'' || s.env || ''/'' || (s.used_at is null)::text) from public.qbo_oauth_state s where s.state_hash = %L', :'h1')), '?'),
  'sandbox/00:10:00/' || :'st_adm' || '/sandbox/true');
select pg_temp.chk('C3 admin: bad env · bad hash → refused',
  pg_temp.as_role('authenticated', format('select public.qbo_state_new(''prod'', %L)::text', :'h2')) || ' | ' || pg_temp.as_role('authenticated', 'select public.qbo_state_new(''sandbox'', ''abc'')::text'),
  'ERR P0001: QuickBooks environment must be sandbox or production (got prod) — nothing was saved | ERR P0001: State hash must be 64 hex characters (sha256) — nothing was saved');
-- 지난 state 하나를 직접 심고(11 분 전) state_new 가 치우는지
\if :landed
insert into public.qbo_oauth_state (state_hash, staff_id, env, created_at) values (:'h3', :'st_adm'::uuid, 'sandbox', now() - interval '11 minutes');
\endif
select pg_temp.do_as('authenticated', format('select public.qbo_state_new(''sandbox'', %L)::text', :'h2')) as c4 \gset
select pg_temp.chk('C4 second state_new → ok · 11-minute-old state purged · live states 2',
  (pg_temp.j(:'c4') is not null)::text || '/' || pg_temp.try(format('select count(*)::text from public.qbo_oauth_state s where s.state_hash = %L', :'h3')) || '/' || pg_temp.try('select count(*)::text from public.qbo_oauth_state'),
  'true/0/2');

-- ── D consume (service) ──
select pg_temp.as_user('', 'service_role');
select pg_temp.do_as('service_role', format('select public.qbo_state_consume(%L)::text', :'h1')) as d1 \gset
select pg_temp.chk('D1 consume once → staff_id · env', coalesce(pg_temp.j(:'d1')->>'staff_id', :'d1') || '/' || coalesce(pg_temp.j(:'d1')->>'env', '?'), :'st_adm' || '/sandbox');
select pg_temp.chk('D2 consume again → already used · unknown hash → not found',
  pg_temp.as_role('service_role', format('select public.qbo_state_consume(%L)::text', :'h1')) || ' | ' || pg_temp.as_role('service_role', format('select public.qbo_state_consume(%L)::text', :'h4')),
  'ERR P0001: Sign-in state was already used — start the connection again from Settings — nothing was changed | ERR P0001: Sign-in state not found — start the connection again from Settings — nothing was changed');
\if :landed
insert into public.qbo_oauth_state (state_hash, staff_id, env, created_at) values (:'h3', :'st_adm'::uuid, 'sandbox', now() - interval '11 minutes');
\endif
select pg_temp.chk('D3 expired state (11 min) → refused · still unused', pg_temp.as_role('service_role', format('select public.qbo_state_consume(%L)::text', :'h3')) || ' | ' || pg_temp.try(format('select (s.used_at is null)::text from public.qbo_oauth_state s where s.state_hash = %L', :'h3')),
  'ERR P0001: Sign-in state expired (10 minutes) — start the connection again from Settings — nothing was changed | true');

-- ── E save (service) ──
select pg_temp.chk('E0 before connect: token_get · claim · company_name_set · mark → not connected · save with bad realm / no staff → refused',
  pg_temp.as_role('service_role', 'select public.qbo_token_get()::text') || ' | ' || pg_temp.as_role('service_role', 'select public.qbo_refresh_claim(gen_random_uuid())::text') || ' | ' || pg_temp.as_role('service_role', 'select public.qbo_company_name_set(''X'')::text') || ' | ' || pg_temp.as_role('service_role', 'select public.qbo_mark_needs_reconnect(''x'')::text') || ' | ' ||
  pg_temp.as_role('service_role', format('select public.qbo_connection_save(''sandbox'', ''abc'', ''r'', ''a'', now(), null, %L)::text', :'st_adm')) || ' | ' || pg_temp.as_role('service_role', 'select public.qbo_connection_save(''sandbox'', ''9341458557490536'', ''r'', ''a'', now(), null, null)::text'),
  'ERR P0001: QuickBooks is not connected — nothing to read | ERR P0001: QuickBooks is not connected — nothing to refresh | ERR P0001: QuickBooks is not connected — nothing was saved | ERR P0001: QuickBooks is not connected — nothing was changed | ERR P0001: QuickBooks company id (realmId) "abc" is not a number — nothing was saved | ERR P0001: Connecting staff null is not on file — nothing was saved');
select pg_temp.do_as('service_role', format('select public.qbo_connection_save(''sandbox'', ''9341458557490536'', ''RT-1'', ''AT-1'', now() + interval ''1 hour'', now() + interval ''100 days'', %L)::text', :'st_adm')) as e1 \gset
select pg_temp.chk('E1 first connect → connected · version 1 · realm pinned in inv_config · vault 2 rows named qbo/sandbox/* · ids on the row match vault',
  coalesce(pg_temp.j(:'e1')->>'status', :'e1') || '/' || coalesce(pg_temp.j(:'e1')->>'token_version', '?') || '/' || pg_temp.try('select c.value from public.inv_config c where c.key = ''qbo_realm_sandbox''') || '/' || pg_temp.vault_n('qbo/sandbox/%') || '/' ||
  pg_temp.try('select count(*)::text from public.qbo_connection c join vault.secrets r on r.id = c.refresh_secret_id and r.name = ''qbo/sandbox/refresh'' join vault.secrets a on a.id = c.access_secret_id and a.name = ''qbo/sandbox/access'''),
  'connected/1/9341458557490536/2/1');
select pg_temp.chk('E1b inv_config pin row: updated_by = connecting staff · note mentions qbo-1a', pg_temp.try('select (c.updated_by::text || ''/'' || (c.note like ''qbo-1a:%'')::text) from public.inv_config c where c.key = ''qbo_realm_sandbox'''), :'st_adm' || '/true');
select pg_temp.as_role('service_role', 'select public.qbo_token_get()::text') as e2 \gset
select pg_temp.chk('E2 token_get → both tokens as given · version 1 · env · realm', coalesce(pg_temp.j(:'e2')->>'refresh_token', :'e2') || '/' || coalesce(pg_temp.j(:'e2')->>'access_token', '?') || '/' || coalesce(pg_temp.j(:'e2')->>'token_version', '?') || '/' || coalesce(pg_temp.j(:'e2')->>'env', '?') || '/' || coalesce(pg_temp.j(:'e2')->>'realm_id', '?'), 'RT-1/AT-1/1/sandbox/9341458557490536');
select pg_temp.as_user(:'u_adm');
select pg_temp.as_role('authenticated', 'select public.qbo_status()::text') as e3 \gset
select pg_temp.chk('E3 admin status(): connected · connected_by name · caller_is_admin true · pinned_realm.sandbox · company_name null · no token keys (token_version is a number · allowed)',
  coalesce(pg_temp.j(:'e3')->>'status', :'e3') || '/' || coalesce(pg_temp.j(:'e3')->>'connected_by', '?') || '/' || coalesce(pg_temp.j(:'e3')->>'caller_is_admin', '?') || '/' || coalesce(pg_temp.j(:'e3')#>>'{pinned_realm,sandbox}', '?') || '/' || coalesce(pg_temp.j(:'e3')->>'company_name', '(null)') || '/' || coalesce((select count(*)::text from jsonb_object_keys(pg_temp.j(:'e3')) k where k ~ '(token|secret)' and k <> 'token_version'), '?'),
  'connected/QBX Admin/true/9341458557490536/(null)/0');
select pg_temp.chk('E4 while connected: state_new → refused (disconnect first) · realm_clear → refused',
  pg_temp.as_role('authenticated', format('select public.qbo_state_new(''sandbox'', %L)::text', :'h4')) || ' | ' || pg_temp.as_role('authenticated', 'select public.qbo_realm_clear(''sandbox'')::text'),
  'ERR P0001: QuickBooks is already connected to company 9341458557490536 (sandbox) — disconnect first to connect again — nothing was saved | ERR P0001: Disconnect QuickBooks before clearing the pinned company — nothing was changed');
select pg_temp.as_user('', 'service_role');
select pg_temp.chk('E5 save another realm → refused (pinned) · save production while sandbox on file → refused · vault still 2',
  pg_temp.as_role('service_role', format('select public.qbo_connection_save(''sandbox'', ''9999000011112222'', ''r'', ''a'', now(), null, %L)::text', :'st_adm')) || ' | ' || pg_temp.as_role('service_role', format('select public.qbo_connection_save(''production'', ''9341458557490536'', ''r'', ''a'', now(), null, %L)::text', :'st_adm')) || ' | ' || pg_temp.vault_n('qbo/%'),
  'ERR P0001: QuickBooks company 9999000011112222 is not the company this IMS was first connected to (9341458557490536) — connect the same company, or ask an admin to clear the pinned company first — nothing was saved | ERR P0001: A sandbox connection is still on file — disconnect it before connecting to production — nothing was saved | 2');
select pg_temp.chk('E6 company_name_set → stored · blank → refused',
  pg_temp.do_as('service_role', 'select public.qbo_company_name_set(''  Sandbox Company CA 9bca '')::text') || ' | ' || pg_temp.as_role('service_role', 'select public.qbo_company_name_set(''  '')::text') || ' | ' || pg_temp.conn('company_name'),
  '{"company_name": "Sandbox Company CA 9bca"} | ERR P0001: Company name is empty — nothing was saved | Sandbox Company CA 9bca');

-- ── F 갱신: 임대 + 판 번호 ──
select pg_temp.do_as('service_role', 'select public.qbo_refresh_claim(''11111111-1111-1111-1111-111111111111'')::text') as f1 \gset
select pg_temp.chk('F1 claim → tokens · version 1 · lease 30 s · refreshing_by', coalesce(pg_temp.j(:'f1')->>'refresh_token', :'f1') || '/' || coalesce(pg_temp.j(:'f1')->>'token_version', '?') || '/' || coalesce(((pg_temp.j(:'f1')->>'refreshing_until')::timestamptz - now())::text, '?') || '/' || pg_temp.conn('refreshing_by'), 'RT-1/1/00:00:30/11111111-1111-1111-1111-111111111111');
select pg_temp.as_role('service_role', 'select public.qbo_refresh_claim(''22222222-2222-2222-2222-222222222222'')::text') as f2 \gset
select pg_temp.as_user(:'u_adm');
select pg_temp.as_role('authenticated', 'select public.qbo_status()::text') as f2s \gset
select pg_temp.chk('F2 claim again (lease alive) → refused · status().refreshing true',
  (:'f2' like 'ERR P0001: Another refresh is running (lease until %Z) — wait and read the token again')::text || '/' || coalesce(pg_temp.j(:'f2s')->>'refreshing', :'f2s'),
  'true/true');
select pg_temp.as_user('', 'service_role');
select pg_temp.chk('F3 save with stale version 0 · null → refused · tokens untouched',
  pg_temp.as_role('service_role', 'select public.qbo_refresh_save(0, ''RT-x'', ''AT-x'', now(), null)::text') || ' | ' || pg_temp.as_role('service_role', 'select public.qbo_refresh_save(null, ''RT-x'', ''AT-x'', now(), null)::text') || ' | ' || coalesce(pg_temp.j(pg_temp.as_role('service_role', 'select public.qbo_token_get()::text'))->>'refresh_token', '?'),
  'ERR P0001: Token version 0 is stale — the connection is now at version 1 (another refresh saved first) — nothing was saved | ERR P0001: Token version null is stale — the connection is now at version 1 (another refresh saved first) — nothing was saved | RT-1');
select pg_temp.do_as('service_role', 'select public.qbo_refresh_save(1, ''RT-2'', ''AT-2'', now() + interval ''1 hour'', null)::text') as f4 \gset
select pg_temp.chk('F4 save version 1 → version 2 · lease cleared · last_refresh_at set · refresh_expires_at kept (null given) · vault rows still 2 (updated)',
  coalesce(pg_temp.j(:'f4')->>'token_version', :'f4') || '/' || pg_temp.conn('refreshing_until') || '/' || pg_temp.conn('refreshing_by') || '/' || pg_temp.conn('(last_refresh_at is not null)') || '/' || pg_temp.conn('(refresh_expires_at is not null)') || '/' || pg_temp.vault_n('qbo/sandbox/%'),
  '2/(null)/(null)/true/true/2');
select pg_temp.chk('F5 token_get → new tokens · version 2 · old version save → refused', coalesce(pg_temp.j(pg_temp.as_role('service_role', 'select public.qbo_token_get()::text'))->>'refresh_token', '?') || '/' || coalesce(pg_temp.j(pg_temp.as_role('service_role', 'select public.qbo_token_get()::text'))->>'access_token', '?') || '/' || coalesce(pg_temp.j(pg_temp.as_role('service_role', 'select public.qbo_token_get()::text'))->>'token_version', '?') || ' | ' || pg_temp.as_role('service_role', 'select public.qbo_refresh_save(1, ''RT-x'', ''AT-x'', now(), null)::text'),
  'RT-2/AT-2/2 | ERR P0001: Token version 1 is stale — the connection is now at version 2 (another refresh saved first) — nothing was saved');
-- 지난 임대: 직접 과거로 돌려 놓고 claim
select pg_temp.do_as('service_role', 'select public.qbo_refresh_claim(''33333333-3333-3333-3333-333333333333'')::text') as f6a \gset
\if :landed
update public.qbo_connection set refreshing_until = now() - interval '1 second';
\endif
select pg_temp.do_as('service_role', 'select public.qbo_refresh_claim(''44444444-4444-4444-4444-444444444444'')::text') as f6 \gset
select pg_temp.chk('F6 expired lease → claim passes · version 2 · new owner', coalesce(pg_temp.j(:'f6a')->>'token_version', :'f6a') || '/' || coalesce(pg_temp.j(:'f6')->>'token_version', :'f6') || '/' || pg_temp.conn('refreshing_by'), '2/2/44444444-4444-4444-4444-444444444444');
select pg_temp.chk('F7 save version 2 with empty refresh token → refused · then with tokens → version 3',
  pg_temp.as_role('service_role', 'select public.qbo_refresh_save(2, ''  '', ''AT-3'', now(), null)::text') || ' | ' || coalesce(pg_temp.j(pg_temp.do_as('service_role', 'select public.qbo_refresh_save(2, ''RT-3'', ''AT-3'', now() + interval ''1 hour'', now() + interval ''101 days'')::text'))->>'token_version', '?'),
  'ERR P0001: Token for qbo/sandbox/refresh is empty — nothing was saved | 3');

-- ── G needs_reconnect ──
select pg_temp.do_as('service_role', 'select public.qbo_mark_needs_reconnect(''invalid_grant: Incorrect Token type or clientID'')::text') as g1 \gset
select pg_temp.chk('G1 mark → needs_reconnect · last_error · claim refused · token_get still works (tokens kept until disconnect)',
  coalesce(pg_temp.j(:'g1')->>'status', :'g1') || '/' || coalesce(pg_temp.j(:'g1')->>'last_error', '?') || ' | ' || pg_temp.as_role('service_role', 'select public.qbo_refresh_claim(gen_random_uuid())::text') || ' | ' || coalesce(pg_temp.j(pg_temp.as_role('service_role', 'select public.qbo_token_get()::text'))->>'status', '?'),
  'needs_reconnect/invalid_grant: Incorrect Token type or clientID | ERR P0001: QuickBooks needs to be reconnected (invalid_grant: Incorrect Token type or clientID) — refresh is not attempted — ask an admin to reconnect in Settings | needs_reconnect');
select pg_temp.as_user(:'u_adm');
select pg_temp.as_role('authenticated', 'select public.qbo_status()::text') as g2 \gset
select pg_temp.chk('G2 status(): needs_reconnect · last_error · last_error_at · company_name kept', coalesce(pg_temp.j(:'g2')->>'status', :'g2') || '/' || coalesce(pg_temp.j(:'g2')->>'last_error', '?') || '/' || coalesce((pg_temp.j(:'g2')->>'last_error_at' is not null)::text, '?') || '/' || coalesce(pg_temp.j(:'g2')->>'company_name', '?'),
  'needs_reconnect/invalid_grant: Incorrect Token type or clientID/true/Sandbox Company CA 9bca');
select pg_temp.chk('G3 admin: state_new allowed again (needs_reconnect) · production env while sandbox row on file → refused',
  (pg_temp.j(pg_temp.do_as('authenticated', format('select public.qbo_state_new(''sandbox'', %L)::text', :'h4'))) is not null)::text || ' | ' || pg_temp.as_role('authenticated', format('select public.qbo_state_new(''production'', %L)::text', :'h2')),
  'true | ERR P0001: The connection on file is sandbox — disconnect it before connecting to production — nothing was saved');
select pg_temp.as_user('', 'service_role');
select pg_temp.do_as('service_role', format('select public.qbo_connection_save(''sandbox'', ''9341458557490536'', ''RT-4'', ''AT-4'', now() + interval ''1 hour'', null, %L)::text', :'st_adm')) as g4 \gset
select pg_temp.chk('G4 reconnect (same realm) → connected · version 4 · last_error cleared · company_name kept · vault still 2 rows · same vault ids reused',
  coalesce(pg_temp.j(:'g4')->>'status', :'g4') || '/' || coalesce(pg_temp.j(:'g4')->>'token_version', '?') || '/' || pg_temp.conn('last_error') || '/' || coalesce(pg_temp.j(:'g4')->>'company_name', '(null)') || '/' || pg_temp.vault_n('qbo/%') || '/' || coalesce(pg_temp.j(pg_temp.as_role('service_role', 'select public.qbo_token_get()::text'))->>'refresh_token', '?'),
  'connected/4/(null)/Sandbox Company CA 9bca/2/RT-4');

-- ── H 끊기 · realm 비우기 ──
select pg_temp.do_as('service_role', 'select public.qbo_connection_delete()::text') as h1 \gset
select pg_temp.chk('H1 delete → row 0 · vault qbo/* 0 · states 0 · deleted true · removed counts (vault 2 · states 3 = h1 used · h2 · h4)',
  coalesce(pg_temp.j(:'h1')->>'deleted', :'h1') || '/' || coalesce(pg_temp.j(:'h1')->>'vault_rows_removed', '?') || '/' || coalesce(pg_temp.j(:'h1')->>'states_removed', '?') || '/' || pg_temp.try('select count(*)::text from public.qbo_connection') || '/' || pg_temp.vault_n('qbo/%') || '/' || pg_temp.try('select count(*)::text from public.qbo_oauth_state'),
  'true/2/3/0/0/0');
select pg_temp.chk('H2 delete again → no error · deleted false · pin still on file', coalesce(pg_temp.j(pg_temp.do_as('service_role', 'select public.qbo_connection_delete()::text'))->>'deleted', '?') || '/' || pg_temp.try('select c.value from public.inv_config c where c.key = ''qbo_realm_sandbox'''), 'false/9341458557490536');
select pg_temp.as_user(:'u_adm');
select pg_temp.as_role('authenticated', 'select public.qbo_status()::text') as h3 \gset
select pg_temp.chk('H3 status(): none · pinned_realm.sandbox still shown · realm_clear → cleared true · again → false · pin gone',
  coalesce(pg_temp.j(:'h3')->>'status', :'h3') || '/' || coalesce(pg_temp.j(:'h3')#>>'{pinned_realm,sandbox}', '?') || ' | ' || pg_temp.do_as('authenticated', 'select public.qbo_realm_clear(''sandbox'')::text') || ' | ' || pg_temp.do_as('authenticated', 'select public.qbo_realm_clear(''sandbox'')::text') || ' | ' || pg_temp.try('select count(*)::text from public.inv_config c where c.key like ''qbo_realm_%'''),
  'none/9341458557490536 | {"env": "sandbox", "cleared": true} | {"env": "sandbox", "cleared": false} | 0');
select pg_temp.as_user('', 'service_role');
select pg_temp.do_as('service_role', format('select public.qbo_connection_save(''sandbox'', ''9999000011112222'', ''RT-9'', ''AT-9'', now() + interval ''1 hour'', null, %L)::text', :'st_adm')) as h4 \gset
select pg_temp.chk('H4 after clear: connect to another company → ok · new pin · version 1 · then delete (clean)',
  coalesce(pg_temp.j(:'h4')->>'realm_id', :'h4') || '/' || coalesce(pg_temp.j(:'h4')->>'token_version', '?') || '/' || pg_temp.try('select c.value from public.inv_config c where c.key = ''qbo_realm_sandbox''') || '/' || coalesce(pg_temp.j(pg_temp.do_as('service_role', 'select public.qbo_connection_delete()::text'))->>'vault_rows_removed', '?'),
  '9999000011112222/1/9999000011112222/2');

-- ── I 컷오버 ③ ──
select pg_temp.chk('I1 cutover-delete.sql: k11 line has the three tables · kall includes :k11', (select string_agg(n::text, '/' order by n) from t_cut), '1/1');

-- ── 결과 ──
select clock_timestamp() - :'t_begin0'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.ims_staff) = :w_staff and (select count(*) from public.inv_config) = :w_cfg and (select count(*) from vault.secrets) = :w_vault
            and (select count(*) from vault.secrets where name like 'qbo/%') = :w_vault_qbo and (select count(*) from public.inv_config where key like 'qbo_%') = :w_cfg_qbo
       then 'Z1 OK real rows unchanged (staff · inv_config · vault.secrets)' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when to_regclass('public.qbo_connection') is null and to_regclass('public.qbo_oauth_state') is null and to_regclass('public.qbo_call_log') is null and to_regprocedure('public.qbo_status()') is null then 'Z2 OK rollback restored · no tables · no function' else 'Z2 MISMATCH' end as z2;
\endif
