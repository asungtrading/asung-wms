-- supabase/tests/qbo_1b_check.sql — qbo-1b 끊김 메일(869) · last_error 창구 검증 (2026-10-29 · 판정 869 · 870)
-- [테스트 · Asung-IMS] 시험 적용 장치 — begin → (-v mig 면 \i) → A ~ C 갈래 → rollback → 실제 행 무변(Z1) · 되돌림(Z2 시험 갈래만)
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261029190000_qbo_1b_reconnect_mail.sql -f supabase/tests/qbo_1b_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK = EXPECT_OK 20(연결 행이 없을 때) · ⚠️ 실제 QuickBooks 연결 행이 있으면 A7 · B 갈래(가짜 연결)는 건너뛰고 OK 8(「B skipped」 한 줄)
--   재료: 가짜 직원 하나(QBX admin · replica 로 넣고 rollback) · 가짜 토큰 글자 · realm = 고정된 샌드박스 회사(inv_config.qbo_realm_sandbox) 없으면 9341458557490536 · 메일은 mail_outbox 에 줄만(보내지 않는다 · rollback)
--   ⚠️ B5 는 inv_config.qbo_alert_to 를 savepoint 안에서 비웠다 되돌린다(이 마이그레이션이 만든 키 · rollback to savepoint)
\set ON_ERROR_STOP on
\set EXPECT_OK 20
\pset pager off
select (select count(*) from public.ims_staff) as w_staff, (select count(*) from public.inv_config) as w_cfg, (select count(*) from public.mail_outbox) as w_mail,
       (select count(*) from public.qbo_connection) as w_conn, (select count(*) from public.qbo_oauth_state) as w_state, (select count(*) from vault.secrets) as w_vault,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_mark_needs_reconnect') as mark_md5_0,
       (select coalesce(c.value, '9341458557490536') from (select 1) x left join public.inv_config c on c.key = 'qbo_realm_sandbox') as realm \gset
\echo '── 기준: staff' :w_staff '· inv_config' :w_cfg '· mail_outbox' :w_mail '· qbo_connection' :w_conn '· state' :w_state '· vault' :w_vault '· mark md5' :mark_md5_0 '· realm' :realm
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
create function pg_temp.as_role(p_role text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute format('set local role %I', p_role);
  execute p_sql into v;
  raise exception using errcode = 'P7777', message = coalesce(v, '(null)');
exception when sqlstate 'P7777' then return sqlerrm;
          when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
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
create function pg_temp.conn(p_col text) returns text language plpgsql as $$ declare v text; begin execute format('select %s::text from public.qbo_connection', p_col) into v; return coalesce(v, '(null)'); exception when others then return 'ERR ' || sqlstate; end $$;
create function pg_temp.mails() returns int language sql as $$ select count(*)::int from public.mail_outbox where kind = 'qbo_reconnect' $$;

-- ── A 착지 ──
select pg_temp.chk('A1 mail_outbox_kind_ck lists qbo_reconnect · kind_category_ck too',
  ((select pg_get_constraintdef(oid) from pg_constraint where conname = 'mail_outbox_kind_ck' and conrelid = 'public.mail_outbox'::regclass) ~ 'qbo_reconnect')::text || '/' || ((select pg_get_constraintdef(oid) from pg_constraint where conname = 'mail_outbox_kind_category_ck' and conrelid = 'public.mail_outbox'::regclass) ~ 'qbo_reconnect')::text, 'true/true');
select pg_temp.chk('A2 inv_config.qbo_alert_to = caleb@asung.ca', (select c.value from public.inv_config c where c.key = 'qbo_alert_to'), 'caleb@asung.ca');
select pg_temp.chk('A3 qbo_mark_needs_reconnect re-issued (md5 ≠ qbo-1a 8ca12316…) · body mentions qbo_reconnect · acl service_role only',
  ((select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_mark_needs_reconnect') <> '8ca12316bb32367f4a3d536e2260cdf8')::text || '/' || ((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_mark_needs_reconnect') ~ 'qbo_reconnect')::text || '/' || (select proacl::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_mark_needs_reconnect'),
  'true/true/{postgres=X/postgres,service_role=X/postgres}');
select pg_temp.chk('A4 qbo_last_error_set exists · acl service_role only', (select proacl::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_last_error_set'), '{postgres=X/postgres,service_role=X/postgres}');
select pg_temp.chk('A5 authenticated · anon cannot execute the two (42501)',
  (select count(*) from (values (pg_temp.as_role('authenticated', 'select public.qbo_mark_needs_reconnect(''x'')::text')), (pg_temp.as_role('authenticated', 'select public.qbo_last_error_set(''x'')::text')), (pg_temp.as_role('anon', 'select public.qbo_last_error_set(''x'')::text'))) v(r) where r like 'ERR 42501: permission denied for function qbo_%')::text, '3');
select pg_temp.as_user('00000000-0000-4000-8000-000000000000', 'authenticated');
select pg_temp.chk('A6 service_role with staff claims (authenticated) → "for the QuickBooks service only"',
  pg_temp.as_role('service_role', 'select public.qbo_last_error_set(''x'')::text'), 'ERR P0001: qbo_last_error_set is for the QuickBooks service only — nothing was changed');
select (:w_conn = 0) as no_conn \gset
\if :no_conn
select pg_temp.as_user('', 'service_role');
select pg_temp.chk('A7 no connection: last_error_set → not connected', pg_temp.as_role('service_role', 'select public.qbo_last_error_set(''x'')::text'), 'ERR P0001: QuickBooks is not connected — nothing was changed');
\endif

-- ── B 가짜 연결 → 표시 → 메일(연결 행이 없을 때만) ──
\if :no_conn
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'qbx-admin@test.invalid', 'QBX Admin', 'admin', '["ims"]', '{}') returning auth_user_id::text as u_adm, id::text as st_adm \gset
set local session_replication_role = origin;
select pg_temp.as_user('', 'service_role');
select pg_temp.do_as('service_role', format('select public.qbo_connection_save(''sandbox'', %L, ''RT-1'', ''AT-1'', now() + interval ''1 hour'', now() + interval ''100 days'', %L)::text', :'realm', :'st_adm')) as b0 \gset
select pg_temp.do_as('service_role', 'select public.qbo_company_name_set(''Sandbox Company CA 9bca'')::text') as b0n \gset
select pg_temp.chk('B0 fake connection saved (connected · version 1) · name set', coalesce(pg_temp.j(:'b0')->>'status', :'b0') || '/' || coalesce(pg_temp.j(:'b0')->>'token_version', '?') || '/' || coalesce(pg_temp.j(:'b0n')->>'company_name', :'b0n'), 'connected/1/Sandbox Company CA 9bca');
select pg_temp.do_as('service_role', 'select public.qbo_mark_needs_reconnect(''HTTP 400 invalid_grant: Token invalid'')::text') as b1 \gset
select pg_temp.chk('B1 mark on connected → needs_reconnect · was connected · mailed true · mail_to caleb · one qbo_reconnect row',
  coalesce(pg_temp.j(:'b1')->>'status', :'b1') || '/' || coalesce(pg_temp.j(:'b1')->>'was', '?') || '/' || coalesce(pg_temp.j(:'b1')->>'mailed', '?') || '/' || coalesce(pg_temp.j(:'b1')->>'mail_to', '?') || '/' || coalesce(pg_temp.j(:'b1')->>'mail_skipped', '(null)') || '/' || pg_temp.mails(),
  'needs_reconnect/connected/true/caleb@asung.ca/(null)/1');
select pg_temp.chk('B2 outbox row: kind · category · status queued · from = mail_doc_from · to · subject(env) · body has Reconnect + reason · payload keys · dedupe prefix · attachments []',
  (select o.kind || '/' || o.category || '/' || o.status || '/' || (o.from_address = (select c.value from public.inv_config c where c.key = 'mail_doc_from'))::text || '/' || o.to_address || '/' || o.subject || '/' || (o.body_text ~ 'Reconnect' and o.body_text ~ 'invalid_grant' and o.body_text ~ 'Sandbox Company CA 9bca')::text || '/' || (select string_agg(k, ',' order by k) from jsonb_object_keys(o.payload) k) || '/' || (o.dedupe_key like 'qbo:reconnect:sandbox:%')::text || '/' || o.attachments::text
     from public.mail_outbox o where o.kind = 'qbo_reconnect' order by o.created_at desc limit 1),
  'qbo_reconnect/transactional/queued/true/caleb@asung.ca/[IMS] QuickBooks connection needs attention (sandbox)/true/at,body_text,company_name,env,error,realm_id,subject/true/[]');
select pg_temp.do_as('service_role', 'select public.qbo_mark_needs_reconnect(''again'')::text') as b3 \gset
select pg_temp.chk('B3 mark again (already needs_reconnect) → was needs_reconnect · mailed false · still one row · last_error updated',
  coalesce(pg_temp.j(:'b3')->>'was', :'b3') || '/' || coalesce(pg_temp.j(:'b3')->>'mailed', '?') || '/' || pg_temp.mails() || '/' || pg_temp.conn('last_error'), 'needs_reconnect/false/1/again');
select pg_temp.do_as('service_role', format('select public.qbo_connection_save(''sandbox'', %L, ''RT-2'', ''AT-2'', now() + interval ''1 hour'', null, %L)::text', :'realm', :'st_adm')) as b4a \gset
select pg_temp.do_as('service_role', 'select public.qbo_mark_needs_reconnect(''second time'')::text') as b4 \gset
select pg_temp.chk('B4 reconnect → connected · mark → mailed again (transition) · two rows · distinct dedupe keys',
  coalesce(pg_temp.j(:'b4a')->>'status', :'b4a') || '/' || coalesce(pg_temp.j(:'b4')->>'mailed', :'b4') || '/' || pg_temp.mails() || '/' || (select count(distinct dedupe_key) from public.mail_outbox where kind = 'qbo_reconnect'), 'connected/true/2/2');
savepoint b5;
update public.inv_config set value = '' where key = 'qbo_alert_to';
select pg_temp.do_as('service_role', format('select public.qbo_connection_save(''sandbox'', %L, ''RT-3'', ''AT-3'', now() + interval ''1 hour'', null, %L)::text', :'realm', :'st_adm')) as b5a \gset
select pg_temp.do_as('service_role', 'select public.qbo_mark_needs_reconnect(''no recipient'')::text') as b5 \gset
select pg_temp.mails() as b5m \gset
rollback to savepoint b5;
-- ⚠️ chk 는 savepoint 를 되돌린 뒤(t_res 도 트랜잭션 표 — 안에서 넣으면 함께 사라진다 · 1차 시험 적용에서 13 번 줄이 빠졌다) · 값은 psql 변수로 건너온다
select pg_temp.chk('B5 qbo_alert_to empty → mark still marks (needs_reconnect) · mailed false · mail_skipped names the key · no new row',
  coalesce(pg_temp.j(:'b5')->>'status', :'b5') || '/' || coalesce(pg_temp.j(:'b5')->>'mailed', '?') || '/' || coalesce(pg_temp.j(:'b5')->>'mail_skipped', '?') || '/' || :b5m,
  'needs_reconnect/false/inv_config.qbo_alert_to is empty or not an email address/2');
select pg_temp.chk('B5b savepoint restored: qbo_alert_to back · connection as after B4 (needs_reconnect · version 2)', (select c.value from public.inv_config c where c.key = 'qbo_alert_to') || '/' || pg_temp.conn('status') || '/' || pg_temp.conn('token_version'), 'caleb@asung.ca/needs_reconnect/2');
select pg_temp.do_as('service_role', format('select public.qbo_connection_save(''sandbox'', %L, ''RT-4'', ''AT-4'', now() + interval ''1 hour'', null, %L)::text', :'realm', :'st_adm')) as b6a \gset
select pg_temp.do_as('service_role', 'select public.qbo_last_error_set(''Two refreshes raced: another one saved first'')::text') as b6 \gset
select pg_temp.chk('B6 last_error_set on connected → status unchanged · last_error · last_error_at set · no mail',
  coalesce(pg_temp.j(:'b6')->>'status', :'b6') || '/' || coalesce(pg_temp.j(:'b6')->>'last_error', '?') || '/' || (pg_temp.conn('last_error_at') <> '(null)')::text || '/' || pg_temp.mails(), 'connected/Two refreshes raced: another one saved first/true/2');
select pg_temp.chk('B7 last_error_set with empty text → default sentence · 400 chars cap', coalesce(pg_temp.j(pg_temp.do_as('service_role', 'select public.qbo_last_error_set(''  '')::text'))->>'last_error', '?') || '/' || length(coalesce(pg_temp.j(pg_temp.do_as('service_role', format('select public.qbo_last_error_set(%L)::text', repeat('x', 500))))->>'last_error', '')), 'QuickBooks call failed/400');
select pg_temp.conn('token_version') as v8 \gset
select pg_temp.do_as('service_role', format('select public.qbo_refresh_save(%s, ''RT-5'', ''AT-5'', now() + interval ''1 hour'', null)::text', :'v8')) as b8 \gset
-- ⚠️ 판 번호는 postgres 로 먼저 읽어 글자로 넘긴다 — service_role 은 qbo_connection 을 읽을 수 없다(1a:107 revoke · grant 0 · 1차 시험 적용의 B8 은 그 서브쿼리가 42501 로 죽은 것)
select pg_temp.chk('B8 refresh_save clears last_error (qbo-1a behaviour kept)', coalesce(pg_temp.j(:'b8')->>'token_version', :'b8') || '/' || pg_temp.conn('last_error'), '4/(null)');
select pg_temp.do_as('service_role', 'select public.qbo_connection_delete()::text') as b9 \gset
select pg_temp.chk('B9 delete → mail rows stay (they are the record) · connection 0', pg_temp.mails() || '/' || pg_temp.try('select count(*)::text from public.qbo_connection'), '2/0');
\else
\echo '── B skipped: a real QuickBooks connection is on file (qbo_connection rows =' :w_conn ') — fake-connection branch not run'
\endif

-- ── C 메일 표 제약 ──
select pg_temp.chk('C1 kind qbo_reconnect with category marketing is refused (kind_category_ck)',
  pg_temp.try($q$insert into public.mail_outbox (kind, category, status, from_address, to_address, subject, body_text, dedupe_key) values ('qbo_reconnect', 'marketing', 'queued', 'info@asung.ca', 'caleb@asung.ca', 's', 'b', 'qbo:test:marketing') returning status$q$),
  'ERR 23514: new row for relation "mail_outbox" violates check constraint "mail_outbox_kind_category_ck"');
select pg_temp.chk('C2 unknown kind still refused (kind_ck)',
  pg_temp.try($q$insert into public.mail_outbox (kind, category, status, from_address, to_address, subject, body_text, dedupe_key) values ('qbo_other', 'transactional', 'queued', 'info@asung.ca', 'caleb@asung.ca', 's', 'b', 'qbo:test:other') returning status$q$),
  'ERR 23514: new row for relation "mail_outbox" violates check constraint "mail_outbox_kind_ck"');

-- ── 결과 ──
select clock_timestamp() - :'t_begin0'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.ims_staff) = :w_staff and (select count(*) from public.inv_config) = :w_cfg and (select count(*) from public.mail_outbox) = :w_mail
            and (select count(*) from public.qbo_connection) = :w_conn and (select count(*) from public.qbo_oauth_state) = :w_state and (select count(*) from vault.secrets) = :w_vault
            and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_mark_needs_reconnect') = :'mark_md5_0'
       then 'Z1 OK real rows unchanged (staff · inv_config · mail_outbox · qbo_connection · state · vault · mark md5)' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when to_regprocedure('public.qbo_last_error_set(text)') is null and not exists (select 1 from public.inv_config where key = 'qbo_alert_to')
            and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'mail_outbox_kind_ck' and conrelid = 'public.mail_outbox'::regclass) !~ 'qbo_reconnect'
       then 'Z2 OK rollback restored · no qbo_last_error_set · no qbo_alert_to · kind_ck without qbo_reconnect' else 'Z2 MISMATCH' end as z2;
\endif
