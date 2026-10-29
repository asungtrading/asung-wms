do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;
-- qbo-1c — REST safeupdate 고침: qbo_* 창구의 WHERE 없는 update · delete 일곱에 열쇠 칸 WHERE (2026-10-29 · 샌드박스 실호출 결함 · asung-workflow §4 「REST 두 겹」 §79-e 1)
--   무엇이 났나: EF qbo 의 ping → rpc/qbo_company_name_set 이 PostgREST(authenticator 가 safeupdate 를 싣는다)에서 21000 「UPDATE requires a WHERE clause」 · callback 의 이름 쓰기도 같은 까닭으로 실패(company_name null) · psql 시험은 safeupdate 를 못 실어 통과했다
--   전수(마지막 정의 · 깊이 0 WHERE 없음): 1a:340 qbo_company_name_set update · 1a:380 qbo_refresh_claim update · 1a:404 qbo_refresh_save update · 1a:441 · 445 qbo_connection_delete delete 둘 · 1b:77 qbo_mark_needs_reconnect update · 1b:119 qbo_last_error_set update = 7
--   qbo_connection_save 가 실호출에서 통과한 까닭: insert … on conflict do update 는 명령 종류가 INSERT 라 safeupdate(UPDATE · DELETE 만 본다)의 대상이 아니다 · state_consume · state_new · realm_clear · vault 속 함수의 update · delete 는 WHERE 가 있다
--   고침: 행 하나 표의 열쇠 칸 `where singleton`(PK boolean · check (singleton)) · qbo_oauth_state 전부 지우기는 `where s.state_hash is not null`(PK · null 없음 = 전부) · 그 밖은 바이트 그대로(원문 20261029160000 · 20261029190000 에서 옮김 · 아래 md5 로 확인) · comment · ACL 은 create or replace 가 지킨다
--   데이터 무접촉 — 함수 여섯 재발행만 · 지금 있는 연결 행은 건드리지 않는다
--   ⚠️ 적용은 Caleb: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261029210000_qbo_1c_rest_safeupdate.sql && supabase migration repair --status applied 20261029210000
--   시험: supabase/tests/qbo_1c_check.sql(정적 nowhere 스캐너 · md5 · ACL · 연결 행 없을 때만 기능 갈래) + 둘째 겹 = 적용 뒤 REST 로 ping(Caleb)

-- ═══ 0) 마지막 정의 확인 — prosrc md5 여섯이 1a · 1b 의 것과 같을 때만 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_company_name_set')     is distinct from 'a8c0de1a9071563cf4f0772a969fdd8d' then v_bad := v_bad || ' qbo_company_name_set'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_refresh_claim')        is distinct from '9e02dd2d603ab20bcbc0e73d342c5ddb' then v_bad := v_bad || ' qbo_refresh_claim'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_refresh_save')         is distinct from '10ba0e1e5a43d522dbd53ae82e2f3f45' then v_bad := v_bad || ' qbo_refresh_save'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_connection_delete')    is distinct from '6bab46653e4111179bd5d844bd98f9ac' then v_bad := v_bad || ' qbo_connection_delete'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_mark_needs_reconnect') is distinct from '0df916d9bf8eba7d045028cc19f93825' then v_bad := v_bad || ' qbo_mark_needs_reconnect(1b)'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_last_error_set')       is distinct from '65d189d807579755e21ebc6f874af23c' then v_bad := v_bad || ' qbo_last_error_set(1b)'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM872', message = format('STOP - not the expected last definition (prosrc md5 differs):%s - re-read before re-issuing - nothing was changed', v_bad); end if;
end $$;

-- ═══ 1) 여섯 재발행 — 원문 + WHERE ═══
create or replace function public.qbo_company_name_set(p_name text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_name text := left(btrim(coalesce(p_name, '')), 200);
begin
  if not public.doc_is_service() then raise exception 'qbo_company_name_set is for the QuickBooks service only — nothing was saved'; end if;
  if v_name = '' then raise exception 'Company name is empty — nothing was saved'; end if;
  update public.qbo_connection set company_name = v_name, updated_at = now() where singleton;
  if not found then raise exception 'QuickBooks is not connected — nothing was saved'; end if;
  return jsonb_build_object('company_name', v_name);
end;
$$;
create or replace function public.qbo_refresh_claim(p_owner uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_c public.qbo_connection%rowtype;
begin
  if not public.doc_is_service() then raise exception 'qbo_refresh_claim is for the QuickBooks service only — nothing was changed'; end if;
  select * into v_c from public.qbo_connection for update;
  if not found then raise exception 'QuickBooks is not connected — nothing to refresh'; end if;
  if v_c.status = 'needs_reconnect' then raise exception 'QuickBooks needs to be reconnected (%) — refresh is not attempted — ask an admin to reconnect in Settings', coalesce(v_c.last_error, 'no error text'); end if;
  if v_c.refreshing_until is not null and v_c.refreshing_until > now() then
    raise exception 'Another refresh is running (lease until %) — wait and read the token again', to_char(v_c.refreshing_until at time zone 'UTC', 'HH24:MI:SS') || 'Z';
  end if;
  update public.qbo_connection set refreshing_until = now() + interval '30 seconds', refreshing_by = p_owner, updated_at = now() where singleton returning * into v_c;
  return jsonb_build_object('env', v_c.env, 'realm_id', v_c.realm_id, 'token_version', v_c.token_version, 'refreshing_until', v_c.refreshing_until,
    'refresh_token', public.qbo_vault_get(v_c.refresh_secret_id), 'access_token', public.qbo_vault_get(v_c.access_secret_id));
end;
$$;
create or replace function public.qbo_refresh_save(p_version int, p_refresh text, p_access text, p_access_exp timestamptz, p_refresh_exp timestamptz) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_c public.qbo_connection%rowtype;
begin
  if not public.doc_is_service() then raise exception 'qbo_refresh_save is for the QuickBooks service only — nothing was saved'; end if;
  if p_access_exp is null then raise exception 'Access token expiry is required — nothing was saved'; end if;
  select * into v_c from public.qbo_connection for update;
  if not found then raise exception 'QuickBooks is not connected — nothing was saved'; end if;
  if v_c.token_version <> coalesce(p_version, -1) then
    raise exception 'Token version % is stale — the connection is now at version % (another refresh saved first) — nothing was saved', coalesce(p_version::text, 'null'), v_c.token_version;
  end if;
  perform public.qbo_vault_put('qbo/' || v_c.env || '/refresh', p_refresh, v_c.refresh_secret_id);
  perform public.qbo_vault_put('qbo/' || v_c.env || '/access',  p_access,  v_c.access_secret_id);
  update public.qbo_connection set token_version = token_version + 1, access_expires_at = p_access_exp, refresh_expires_at = coalesce(p_refresh_exp, refresh_expires_at),
    refreshing_until = null, refreshing_by = null, last_refresh_at = now(), last_error = null, last_error_at = null, updated_at = now()
    where singleton returning * into v_c;
  return jsonb_build_object('token_version', v_c.token_version, 'access_expires_at', v_c.access_expires_at, 'refresh_expires_at', v_c.refresh_expires_at);
end;
$$;
create or replace function public.qbo_connection_delete() returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_c public.qbo_connection%rowtype; v_v int := 0; v_s int;
begin
  if not public.doc_is_service() then raise exception 'qbo_connection_delete is for the QuickBooks service only — nothing was deleted'; end if;
  select * into v_c from public.qbo_connection for update;
  if found then
    v_v := public.qbo_vault_drop(v_c.env, array[v_c.refresh_secret_id, v_c.access_secret_id]);
    delete from public.qbo_connection where singleton;
  else
    v_v := public.qbo_vault_drop('sandbox', null) + public.qbo_vault_drop('production', null);      -- 짝 잃은 Vault 행도 치운다
  end if;
  delete from public.qbo_oauth_state s where s.state_hash is not null;                                 -- 전부(PK · null 없음) · REST safeupdate 는 WHERE 의 있음만 본다
  get diagnostics v_s = row_count;
  return jsonb_build_object('deleted', v_c.singleton is not null, 'env', v_c.env, 'vault_rows_removed', v_v, 'states_removed', v_s);
end;
$$;
create or replace function public.qbo_mark_needs_reconnect(p_error text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_c      public.qbo_connection%rowtype;
  v_was    text;
  v_to     text := nullif(btrim(coalesce((select c.value from public.inv_config c where c.key = 'qbo_alert_to'), '')), '');
  v_from   text := nullif(btrim(coalesce((select c.value from public.inv_config c where c.key = 'mail_doc_from'), '')), '');
  v_name   text := nullif(btrim(coalesce((select c.value from public.inv_config c where c.key = 'mail_doc_from_name'), '')), '');
  v_mailed boolean := false;
  v_why    text;
  v_subject text;
  v_body   text;
begin
  if not public.doc_is_service() then raise exception 'qbo_mark_needs_reconnect is for the QuickBooks service only — nothing was changed'; end if;
  select * into v_c from public.qbo_connection for update;
  if not found then raise exception 'QuickBooks is not connected — nothing was changed'; end if;
  v_was := v_c.status;
  update public.qbo_connection set status = 'needs_reconnect', last_error = left(coalesce(nullif(btrim(p_error), ''), 'QuickBooks refused the token'), 400), last_error_at = now(),
    refreshing_until = null, refreshing_by = null, updated_at = now() where singleton returning * into v_c;
  if v_was = 'connected' then                                                                     -- 869: connected → needs_reconnect 로 바뀌는 순간 한 번만(이미 needs_reconnect 면 0)
    if v_to is null or not public.ims_mail_address_ok(v_to) then
      v_why := 'inv_config.qbo_alert_to is empty or not an email address';
    elsif v_from is null or not public.ims_mail_address_ok(v_from) then
      v_why := 'inv_config.mail_doc_from (the sender) is empty or not an email address';
    else
      v_subject := '[IMS] QuickBooks connection needs attention (' || v_c.env || ')';
      v_body := 'QuickBooks stopped accepting the IMS connection.' || E'\n\n'
             || 'Company:  ' || coalesce(v_c.company_name, '(name not read yet)') || ' (' || v_c.env || ', id ' || v_c.realm_id || ')' || E'\n'
             || 'When:     ' || to_char(now() at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI') || ' Toronto' || E'\n'
             || 'Reason:   ' || v_c.last_error || E'\n\n'
             || 'Nothing is sent to QuickBooks until it is reconnected.' || E'\n'
             || 'Open IMS -> Settings -> QuickBooks and click Reconnect (admin only).' || E'\n\n'
             || 'Asung IMS';
      begin
        insert into public.mail_outbox (kind, category, status, from_address, from_name, reply_to, to_address, subject, body_text, payload, dedupe_key)
        values ('qbo_reconnect', 'transactional', 'queued', v_from, v_name, null, v_to, v_subject, v_body,
                jsonb_build_object('env', v_c.env, 'realm_id', v_c.realm_id, 'company_name', v_c.company_name, 'error', v_c.last_error, 'at', now(), 'subject', v_subject, 'body_text', v_body),
                'qbo:reconnect:' || v_c.env || ':' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'));
        v_mailed := true;
      exception when others then
        v_why := 'mail_outbox insert failed: ' || sqlerrm;                                        -- 메일이 표시를 막지 않는다
      end;
    end if;
    if not v_mailed then raise warning 'qbo_mark_needs_reconnect: alert mail (869) not queued — %', v_why; end if;
  end if;
  return jsonb_build_object('status', v_c.status, 'last_error', v_c.last_error, 'last_error_at', v_c.last_error_at,
                            'was', v_was, 'mailed', v_mailed, 'mail_to', case when v_mailed then v_to end, 'mail_skipped', v_why);
end;
$$;
create or replace function public.qbo_last_error_set(p_error text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_c public.qbo_connection%rowtype;
begin
  if not public.doc_is_service() then raise exception 'qbo_last_error_set is for the QuickBooks service only — nothing was changed'; end if;
  update public.qbo_connection set last_error = left(coalesce(nullif(btrim(p_error), ''), 'QuickBooks call failed'), 400), last_error_at = now(), updated_at = now() where singleton returning * into v_c;
  if not found then raise exception 'QuickBooks is not connected — nothing was changed'; end if;
  return jsonb_build_object('status', v_c.status, 'last_error', v_c.last_error, 'last_error_at', v_c.last_error_at);
end;
$$;

-- ═══ 2) 착지 확인 — 여섯 모두 WHERE 가 들어갔고 md5 가 바뀌었다 · ACL 그대로 · 데이터 무접촉 ═══
do $$
declare v_bad text := ''; r record;
begin
  for r in select proname, prosrc, proacl::text as acl, prosecdef from pg_proc where pronamespace = 'public'::regnamespace
             and proname in ('qbo_company_name_set', 'qbo_refresh_claim', 'qbo_refresh_save', 'qbo_connection_delete', 'qbo_mark_needs_reconnect', 'qbo_last_error_set') loop
    if r.prosrc !~ 'where singleton' then v_bad := v_bad || ' ' || r.proname || ':no-where'; end if;
    if r.proname = 'qbo_connection_delete' and r.prosrc !~ 'where s\.state_hash is not null' then v_bad := v_bad || ' delete-state:no-where'; end if;
    if r.prosrc ~ 'update public\.qbo_connection set [^;]*(returning \* into v_c)?;' and r.prosrc !~ 'where singleton' then v_bad := v_bad || ' ' || r.proname || ':update-no-where'; end if;
    if r.acl <> '{postgres=X/postgres,service_role=X/postgres}' or not r.prosecdef then v_bad := v_bad || ' ' || r.proname || ':acl ' || coalesce(r.acl, 'null'); end if;
    if md5(r.prosrc) in ('a8c0de1a9071563cf4f0772a969fdd8d', '9e02dd2d603ab20bcbc0e73d342c5ddb', '10ba0e1e5a43d522dbd53ae82e2f3f45', '6bab46653e4111179bd5d844bd98f9ac', '0df916d9bf8eba7d045028cc19f93825', '65d189d807579755e21ebc6f874af23c') then v_bad := v_bad || ' ' || r.proname || ':unchanged'; end if;
  end loop;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_company_name_set', 'qbo_refresh_claim', 'qbo_refresh_save', 'qbo_connection_delete', 'qbo_mark_needs_reconnect', 'qbo_last_error_set')) <> 6 then v_bad := v_bad || ' count'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM872', message = format('STOP - qbo-1c landing check failed:%s', v_bad); end if;
end $$;
