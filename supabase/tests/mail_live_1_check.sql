-- supabase/tests/mail_live_1_check.sql — mail-live-1 mail_live 운영 선언 검증 (2026-11-01 밤 · 판정 617 · 947)
-- [테스트 · Asung-IMS] 시험 적용 장치 — begin → (-v mig 면 \i) → A ~ E 갈래 → rollback → 설정 md5 무변(Z1) · 10 초 안(Z2)
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261102013000_mail_live_1.sql -f supabase/tests/mail_live_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 MISMATCH 0 · ⚠️ 적용 뒤 mail_live 가 이미 on 이면 B · C 의 시작값이 다르다 — 갈래는 savepoint 안에서 off 로 맞추고 시작한다
--   재료: 가짜 직원 셋(mlv1-*@test.invalid · rollback) · 설정 값은 savepoint 안에서만 바뀐다 · 메일은 쌓지 않는다
\set ON_ERROR_STOP on
\pset pager off
select (select value from public.inv_config where key = 'db_role') as db_role0,
       (select count(*) from public.inv_config) as n_cfg0,
       (select md5(string_agg(c.key || '|' || c.value || '|' || coalesce(c.updated_at::text, '') || '|' || coalesce(c.updated_by::text, ''), ',' order by c.key)) from public.inv_config c) as md5_cfg0,
       (select count(*) from supabase_migrations.schema_migrations where version = '20261102013000') as n_mig0,
       (select count(*) from public.mail_outbox) as n_mail0 \gset
\echo '── 기준: db_role' :db_role0 '· inv_config' :n_cfg0 '· md5' :md5_cfg0 '· schema_migrations 20261102013000 =' :n_mig0 '· mail_outbox' :n_mail0
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
create function pg_temp.v(p_key text) returns text language sql as $$ select c.value from public.inv_config c where c.key = p_key $$;
create function pg_temp.upd(p_key text, p_value text) returns text language plpgsql as $$   -- postgres 직접(guard 의 값 검사만) · 예외 문장을 돌려준다
begin
  update public.inv_config set value = p_value where key = p_key;
  return 'ok ' || p_key || '=' || p_value;
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.del(p_key text) returns text language plpgsql as $$
begin
  delete from public.inv_config where key = p_key;
  return 'deleted ' || p_key;
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.set(p_key text, p_value text, p_old text) returns text language plpgsql as $$   -- 창구(REST 가 부르는 ims_config_set) · authenticated 로 부른다
begin
  return public.ims_config_set(p_key, p_value, p_old)::text;
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.as_role(p_role text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute format('set local role %I', p_role);
  execute p_sql into v;
  raise exception using errcode = 'P7777', message = coalesce(v, '(null)');
exception when sqlstate 'P7777' then return sqlerrm;
          when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;

-- ── A 착지 ──
select pg_temp.chk('A1 ims_mail_config_keys 11 · mail_live third', array_length(public.ims_mail_config_keys(), 1)::text || '/' || (public.ims_mail_config_keys())[3], '11/mail_live');
select pg_temp.chk('A2 inv_config.mail_live row (on|off) · note mentions 947', (select (c.value in ('on', 'off'))::text || '/' || (c.note ~ '947')::text from public.inv_config c where c.key = 'mail_live'), 'true/true');
select pg_temp.chk('A3 re-issued: problem md5 ≠ 9e534… · doc_mail_send md5 ≠ 98f93… · doc_mail_send no db_role · claim/settings/config_set mention mail_live',
  ((select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_mail_config_problem') <> '9e53418fd7ca5f3811e83a999eba451c')::text || '/'
  || ((select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_send') <> '98f93aaa243f111befdad7eeb9a0eb1e')::text || '/'
  || ((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_send') !~ 'db_role')::text || '/'
  || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('mail_claim', 'mail_settings', 'ims_config_set') and prosrc ~ 'mail_live')::text, 'true/true/true/3');
select pg_temp.chk('A4 acl unchanged: ims_config_set authenticated only · mail_claim service_role only · problem/settings/doc_mail_send/keys authenticated + service_role',
  (select proacl::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_config_set') || ' | ' || (select proacl::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_claim') || ' | '
  || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('ims_mail_config_problem', 'mail_settings', 'doc_mail_send', 'ims_mail_config_keys') and proacl::text = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}')::text,
  '{postgres=X/postgres,authenticated=X/postgres} | {postgres=X/postgres,service_role=X/postgres} | 4');
select pg_temp.chk('A5 guard trigger still one · guarded list reads keys() (rename of mail_live refused for authenticated is by keys())', (select count(*) from pg_trigger where tgrelid = 'public.inv_config'::regclass and tgname = 'inv_config_guard' and not tgisinternal)::text || '/' || ((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'inv_config_guard') ~ 'ims_mail_config_keys\(\)')::text, '1/true');

-- ── B 값 규칙(guard · postgres 직접 · savepoint 안 · 시작값 mail_enabled on · redirect @asung.ca · mail_live off) — 결과는 변수로 받아 savepoint 를 되돌린 뒤 t_res 에 적는다(되돌리면 temp 행도 사라진다) ──
savepoint b;
select pg_temp.upd('mail_enabled', 'on') as b0a, pg_temp.upd('mail_redirect_to', 'ops@asung.ca') as b0b, pg_temp.upd('mail_live', 'off') as b0c \gset
select pg_temp.upd('mail_live', 'maybe') as b1 \gset
select pg_temp.upd('mail_redirect_to', '') as b2 \gset
select pg_temp.upd('mail_redirect_to', 'me@gmail.com') as b3 \gset
select pg_temp.upd('mail_live', 'on') as b4a \gset
select pg_temp.upd('mail_redirect_to', '') as b4b \gset
select pg_temp.upd('mail_redirect_to', 'me@gmail.com') as b4c \gset
select pg_temp.upd('mail_redirect_to', '') as b4d \gset
select pg_temp.upd('mail_live', 'off') as b5a \gset
select pg_temp.del('mail_live') as b5b \gset
select pg_temp.upd('mail_redirect_to', 'a@asung.ca, b@asung.ca') as b5c \gset
select pg_temp.upd('mail_enabled', 'off') as b6a \gset
select pg_temp.upd('mail_enabled', 'on') as b6b \gset
select pg_temp.upd('mail_redirect_to', 'ops@asung.ca') as b7a \gset
select pg_temp.upd('mail_live', 'off') as b7b \gset
select pg_temp.upd('mail_redirect_to', '') as b7c \gset
select pg_temp.upd('mail_live', 'on') as b8a \gset
select pg_temp.upd('mail_enabled', 'off') as b8b \gset
select pg_temp.del('mail_live') as b8c \gset
select (select count(*) from public.inv_config where key = 'mail_live') as b8n \gset
rollback to savepoint b;
select pg_temp.chk('B0 start: enabled on · redirect ops@asung.ca · live off', :'b0a' || ' | ' || :'b0b' || ' | ' || :'b0c', 'ok mail_enabled=on | ok mail_redirect_to=ops@asung.ca | ok mail_live=off');
select pg_temp.chk('B1 mail_live maybe → refused', :'b1', 'ERR P0001: inv_config.mail_live must be on or off (got maybe) — nothing was saved');
select pg_temp.chk('B2 live off: redirect empty while enabled on → refused (old test rule intact)', :'b2', 'ERR P0001: inv_config.mail_redirect_to cannot be emptied while mail_enabled is on in the test database — turn mail_enabled off first — nothing was saved');
select pg_temp.chk('B3 live off: redirect outside asung.ca → refused (old test rule intact)', :'b3', 'ERR P0001: inv_config.mail_redirect_to must be an @asung.ca address in the test database (got me@gmail.com) — nothing was saved');
select pg_temp.chk('B4 live on → ok · redirect empty → ok · redirect me@gmail.com → ok (production branch: one address) · empty again → ok', :'b4a' || ' | ' || :'b4b' || ' | ' || :'b4c' || ' | ' || :'b4d', 'ok mail_live=on | ok mail_redirect_to= | ok mail_redirect_to=me@gmail.com | ok mail_redirect_to=');
select pg_temp.chk('B5 live on · redirect empty: mail_live off → refused · delete mail_live → refused · two addresses → refused (shape)', :'b5a' || ' | ' || :'b5b' || ' | ' || :'b5c',
  'ERR P0001: inv_config.mail_live cannot be off while mail_enabled is on and mail_redirect_to is not an @asung.ca address — set mail_redirect_to (an @asung.ca address) or turn mail_enabled off first — nothing was saved | ERR P0001: inv_config.mail_live cannot be removed while mail_enabled is on and mail_redirect_to is not an @asung.ca address — set mail_redirect_to or turn mail_enabled off first — nothing was saved | ERR P0001: inv_config.mail_redirect_to must be empty or one email address (got a@asung.ca, b@asung.ca) — nothing was saved');
select pg_temp.chk('B6 live on · redirect empty: mail_enabled off → on → ok both (rule ② relaxed)', :'b6a' || ' | ' || :'b6b', 'ok mail_enabled=off | ok mail_enabled=on');
select pg_temp.chk('B7 redirect ops@asung.ca → mail_live off → ok · then redirect empty → refused again', :'b7a' || ' | ' || :'b7b' || ' | ' || :'b7c', 'ok mail_redirect_to=ops@asung.ca | ok mail_live=off | ERR P0001: inv_config.mail_redirect_to cannot be emptied while mail_enabled is on in the test database — turn mail_enabled off first — nothing was saved');
select pg_temp.chk('B8 live on · enabled off: delete mail_live → allowed for postgres (no live rule when mail is off) · row gone', :'b8a' || ' | ' || :'b8b' || ' | ' || :'b8c' || ' | ' || :'b8n', 'ok mail_live=on | ok mail_enabled=off | deleted mail_live | 0');
select pg_temp.chk('B9 savepoint rolled back: mail_live row back', (select count(*) from public.inv_config where key = 'mail_live')::text, '1');

-- ── C REST 두 겹 — 창구 ims_config_set(authenticated · 가짜 직원 셋) → guard ──
savepoint c;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'mlv1-admin@test.invalid', 'MLV1 admin', 'admin', '["ims"]', '{}') returning auth_user_id::text as g_adm \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'mlv1-master@test.invalid', 'MLV1 master', 'manager', '["ims","master"]', '{}') returning auth_user_id::text as g_mas \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'mlv1-worker@test.invalid', 'MLV1 worker', 'worker', '["ims"]', '{}') returning auth_user_id::text as g_wrk \gset
\set c_adm '{"sub":"' :g_adm '","role":"authenticated"}'
\set c_mas '{"sub":"' :g_mas '","role":"authenticated"}'
\set c_wrk '{"sub":"' :g_wrk '","role":"authenticated"}'
select pg_temp.upd('mail_enabled', 'on') as c0a, pg_temp.upd('mail_redirect_to', 'ops@asung.ca') as c0b, pg_temp.upd('mail_live', 'off') as c0c \gset
set local role authenticated;
select set_config('request.jwt.claims', :'c_wrk', true) as claims;
select pg_temp.set('mail_live', 'on', null) as c1_wrk \gset
select set_config('request.jwt.claims', :'c_mas', true) as claims;
select pg_temp.set('mail_live', 'on', null) as c1_mas \gset
select set_config('request.jwt.claims', :'c_adm', true) as claims;
select pg_temp.set('mail_live', 'x', 'off') as c2_bad \gset
select pg_temp.set('mail_live', 'on', 'off') as c3_on \gset
select pg_temp.v('mail_live') as c3_v \gset
select pg_temp.set('mail_redirect_to', '', 'ops@asung.ca') as c4_empty \gset
select coalesce(pg_temp.v('mail_redirect_to'), '(null)') as c4_v \gset
select pg_temp.set('mail_live', 'off', 'on') as c5_off \gset
select pg_temp.set('mail_redirect_to', 'caleb@asung.ca', '') as c6_back \gset
select pg_temp.set('mail_live', 'off', 'on') as c7_off \gset
select pg_temp.v('mail_live') as c7_v \gset
select public.mail_settings()::text as c8_settings_adm \gset
select set_config('request.jwt.claims', :'c_mas', true) as claims;
select public.mail_settings()::text as c8_settings_mas \gset
reset role;
rollback to savepoint c;
select pg_temp.chk('C1 worker · master(manager) → needs an admin', (:'c1_wrk' like '%Changing mail_live needs an admin%')::text || '/' || (:'c1_mas' like '%Changing mail_live needs an admin%')::text, 'true/true');
select pg_temp.chk('C2 admin: value x → guard sentence through the gate', :'c2_bad', 'ERR P0001: inv_config.mail_live must be on or off (got x) — nothing was saved');
select pg_temp.chk('C3 admin: mail_live on → changed · edit_level admin · updated_by MLV1 admin · value on', (pg_temp.j(:'c3_on')->>'changed') || '/' || (pg_temp.j(:'c3_on')->>'edit_level') || '/' || (pg_temp.j(:'c3_on')->>'updated_by_name') || '/' || :'c3_v', 'true/admin/MLV1 admin/on');
select pg_temp.chk('C4 admin: redirect emptied while live on → changed (customers get mail)', (pg_temp.j(:'c4_empty')->>'changed') || '/' || :'c4_v', 'true/');
select pg_temp.chk('C5 admin: mail_live off while redirect empty → refused by guard through the gate', :'c5_off', 'ERR P0001: inv_config.mail_live cannot be off while mail_enabled is on and mail_redirect_to is not an @asung.ca address — set mail_redirect_to (an @asung.ca address) or turn mail_enabled off first — nothing was saved');
select pg_temp.chk('C6 admin: redirect caleb@asung.ca → mail_live off → both ok', (pg_temp.j(:'c6_back')->>'changed') || '/' || (pg_temp.j(:'c7_off')->>'changed') || '/' || :'c7_v', 'true/true/off');
select pg_temp.chk('C7 mail_settings: mail_live listed · edit_level admin · can_edit admin true · master false',
  (select (e->>'edit_level') || '/' || (e->>'can_edit') from jsonb_array_elements(pg_temp.j(:'c8_settings_adm')) e where e->>'key' = 'mail_live') || ' | ' || (select e->>'can_edit' from jsonb_array_elements(pg_temp.j(:'c8_settings_mas')) e where e->>'key' = 'mail_live'), 'admin/true | false');
select pg_temp.chk('C8 savepoint rolled back: fake staff gone · redirect back', (select count(*) from public.ims_staff where email like 'mlv1-%')::text || '/' || (pg_temp.v('mail_redirect_to') ~ '@asung\.ca$')::text, '0/true');

-- ── D mail_claim(service_role) 반환에 mail_live ──
savepoint d;
select pg_temp.upd('mail_enabled', 'on') as d0a, pg_temp.upd('mail_redirect_to', 'ops@asung.ca') as d0b, pg_temp.upd('mail_live', 'on') as d0c \gset
select pg_temp.as_role('service_role', 'select public.mail_claim(1)::text') as d1 \gset
reset role;
select pg_temp.upd('mail_live', 'off') as d2a \gset
select pg_temp.as_role('service_role', 'select public.mail_claim(1)::text') as d2 \gset
reset role;
rollback to savepoint d;
select pg_temp.chk('D1 mail_claim: mail_live true then false · enabled true · db_role test', (pg_temp.j(:'d1')->>'mail_live') || '/' || (pg_temp.j(:'d2')->>'mail_live') || '/' || (pg_temp.j(:'d1')->>'enabled') || '/' || (pg_temp.j(:'d1')->>'db_role'), 'true/false/true/test');

-- ── E doc_mail_send 미리 보기 — 본문 확인만(문서 · sales 문이 필요해 부르지 않는다) ──
select pg_temp.chk('E1 doc_mail_send preview returns redirect_to = v_redirect (no db_role branch)', ((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_send') ~ $q$'redirect_to', v_redirect,$q$)::text, 'true');

\echo '── 결과'
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when not ok then 'got=' || coalesce(got, '(null)') || ' · want=' || coalesce(want, '(null)') end as diff from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch from t_res;
select extract(epoch from clock_timestamp() - :'t_begin0'::timestamptz)::numeric(6,2) as seconds_in_txn \gset
rollback;
\echo '── Z1 rollback 뒤: 설정 md5 · 행 수 · schema_migrations · mail_outbox 그대로 · Z2 초'
select (select md5(string_agg(c.key || '|' || c.value || '|' || coalesce(c.updated_at::text, '') || '|' || coalesce(c.updated_by::text, ''), ',' order by c.key)) from public.inv_config c) = :'md5_cfg0' as z1_cfg_same,
       (select count(*) from public.inv_config) = :n_cfg0 as z1_rows_same,
       (select count(*) from supabase_migrations.schema_migrations where version = '20261102013000') = :n_mig0 as z1_mig_same,
       (select count(*) from public.mail_outbox) = :n_mail0 as z1_mail_same,
       (select count(*) from public.ims_staff where email like 'mlv1-%') = 0 as z1_no_fake_staff,
       :seconds_in_txn as z2_seconds;
