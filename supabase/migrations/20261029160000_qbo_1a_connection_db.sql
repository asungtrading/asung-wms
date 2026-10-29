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
-- qbo-1a — QuickBooks 연결: DB 바탕 (표 셋 · Vault · 창구 열둘 · 문) (2026-10-29 · 판정 617 · 867 ~ 872 · 조사 qbo-0 · 지시서 ~/asung/prompts/qbo-1a.md)
--   왜: 싱크는 컷오버 뒤라도 연결은 먼저(Caleb) — Intuit 설문(868)은 샌드박스에서 연결 → 끊기 → 다시 연결을 실제로 해 본 뒤 채운다. 이 차수 = DB · qbo-1b = EF `qbo`(start · callback · refresh · revoke · companyinfo · cron) · 화면 = Settings ?t=qbo(대화 Claude)
--   토큰은 Vault(supabase_vault 0.3.1 · vault.create_secret / update_secret / decrypted_secrets) — 표에는 토큰 칸이 없다 · 화면은 qbo_status() 로 상태만(처리방침 §4 「not shown on staff screens」 · deferred 362 교훈 「화면이 안 그리는 것에 기대지 않는다」)
--   연결 행은 하나(singleton) · 환경은 명시 값(env sandbox | production · EF 비밀값 QBO_ENV 와 다르면 EF 가 거부 — freightcom 의 db_role = 'test' 가드는 쓰지 않는다 · 컷오버 뒤에도 test 로 남는다 cutover-delete.sql:16) · 이 프로젝트(Asung-IMS)가 11-01 부터 그대로 운영(617)
--   문(870): 연결 · 끊기 · 다시 연결 · 고정 회사 비우기 = IMS admin 역할만 — DB 가 ims_is_admin()(20260915141105 · 하나뿐 · 다시 만들지 않는다) 으로 본다 · 새 열쇠 없음 · 상태 읽기는 로그인한 직원 누구나
--   service_role 창구(EF 전용)는 doc_is_service()(20261019181014 · claims.role = service_role) 로 가른다 — grant 도 service_role 에만
--   CSRF state: 32 바이트 무작위는 EF 가 만들고 DB 에는 sha256 hex 만 · 10 분 · 한 번(조건부 update 1 행)
--   갱신이 겹치지 않게 = 임대 + 판 번호(PostgREST 한 호출 = 한 트랜잭션이라 잠금을 쥐고 Intuit 을 부를 수 없다): claim(임대 30 s · 토큰 + 판 번호) → save(판 번호가 같을 때만 쓰고 +1 · 임대 풀기) · 옛 판으로 저장은 거부(Intuit 은 갱신마다 refresh_token 을 바꾼다 — 옛 값을 다시 쓰면 invalid_grant)
--   realm 고정: 처음 연결한 회사 id 를 env 별로 inv_config(qbo_realm_sandbox · qbo_realm_production)에 · 다른 회사는 저장 거부(싱크가 시작되면 IMS 행이 QBO id 를 가리킨다 — 회사가 바뀌면 짝이 전부 틀어진다) · 비우기는 admin 이 연결 없을 때만
--   끊기 = Vault 두 행 + 연결 행 + state 전부 지움(처리방침 약속) · Intuit revoke 호출은 EF(1b) · revoke 가 실패해도 지운다 · 누가 끊었나는 EF 의 qbo_call_log(action disconnect · by_staff)
--   호출 기록 qbo_call_log = fc_call_log 꼴(20261028162209:166) + env · realm_id · intuit_tid(Intuit 응답 머리 · 지원 문의 열쇠) · 90 일 지우기는 EF 몫 · grant 는 fc 와 같다
--   컷오버 날 지우기(cutover-delete.sql ③ 분류 · 같은 커밋에서 고침): K(남김) = qbo_connection qbo_oauth_state qbo_call_log(설정 · 10 분짜리 · 기록 — 거래가 아니다) · 거래 표를 가리키는 FK 0 · 샌드박스 → 운영은 컷오버 날이 아니라 운영 키를 받은 날 「끊기 → QBO_ENV=production + 운영 키 → 연결」(문서 차수)
--   ⚠️ 적용은 Caleb: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261029160000_qbo_1a_connection_db.sql · 그 뒤 supabase migration repair --status applied 20261029160000
--   시험: supabase/tests/qbo_1a_check.sql(begin → \i → 검증 → rollback)

-- ═══ 1) 표 셋 ═══
create table public.qbo_connection (
  singleton           boolean primary key default true check (singleton),
  env                 text not null check (env in ('sandbox', 'production')),
  realm_id            text not null check (realm_id ~ '^[0-9]{4,32}$'),
  company_name        text,
  status              text not null default 'connected' check (status in ('connected', 'needs_reconnect')),
  connected_by        uuid references public.ims_staff (id),
  connected_at        timestamptz not null default now(),
  refresh_secret_id   uuid not null,
  access_secret_id    uuid not null,
  access_expires_at   timestamptz not null,
  refresh_expires_at  timestamptz,
  token_version       int not null default 1,
  refreshing_until    timestamptz,
  refreshing_by       uuid,
  last_refresh_at     timestamptz,
  last_error          text,
  last_error_at       timestamptz,
  updated_at          timestamptz not null default now()
);
comment on table  public.qbo_connection is 'qbo-1a: QuickBooks 연결 한 줄(singleton) — 토큰은 여기 없다(Vault · refresh_secret_id · access_secret_id 가 가리킨다) · 화면은 qbo_status() 로만 · 쓰기는 창구만(grant 0) · 컷오버 K';
comment on column public.qbo_connection.env                is 'sandbox | production — EF 비밀값 QBO_ENV 와 다르면 EF 가 거부(명시 값 · db_role 가드 안 씀) · 바꾸기는 끊기 → 연결';
comment on column public.qbo_connection.realm_id           is 'Intuit realmId(QBO 회사 id · 숫자 글자) — inv_config.qbo_realm_<env> 에 고정된 값과 같아야 저장된다';
comment on column public.qbo_connection.company_name       is 'CompanyInfo 로 읽은 회사 이름(qbo_company_name_set · EF ping) · Settings 칸에 보인다';
comment on column public.qbo_connection.status             is 'connected | needs_reconnect(invalid_grant · 갱신 토큰 만료 · QBO 쪽에서 끊김 — EF 가 qbo_mark_needs_reconnect · 다시 시도하지 않는다 · Caleb 메일 869 는 EF)';
comment on column public.qbo_connection.refresh_secret_id  is 'vault.secrets.id — 이름 qbo/<env>/refresh · 갱신마다 update_secret(값이 바뀐다 · 옛 값으로 다시 쓰면 Intuit 이 invalid_grant)';
comment on column public.qbo_connection.access_secret_id   is 'vault.secrets.id — 이름 qbo/<env>/access · 1 시간짜리';
comment on column public.qbo_connection.access_expires_at  is '접근 토큰 만료(expires_in 으로 EF 가 센다) — 5 분 안이면 EF 가 먼저 갱신';
comment on column public.qbo_connection.refresh_expires_at is '갱신 토큰 만료(x_refresh_token_expires_in · Intuit 최대 5 년 — 짐작 · 1b 실호출로 확인) · null = 모름';
comment on column public.qbo_connection.token_version      is '판 번호(CAS) — claim 이 준 번호와 같을 때만 save 가 쓰고 +1 · 옛 판 저장은 거부';
comment on column public.qbo_connection.refreshing_until   is '갱신 임대(30 s) — 비었거나 지났을 때만 claim 이 준다 · save · mark_needs_reconnect 가 푼다';
comment on column public.qbo_connection.refreshing_by      is '임대를 쥔 EF 호출의 표식(p_owner · 진단용) · save 는 판 번호만 본다';
comment on column public.qbo_connection.last_error         is '마지막 오류 한 줄(EF 가 토큰 · 비밀을 거르고 넘긴다 · 400 자)';

create table public.qbo_oauth_state (
  state_hash  text primary key check (state_hash ~ '^[0-9a-f]{64}$'),
  staff_id    uuid not null references public.ims_staff (id),
  env         text not null check (env in ('sandbox', 'production')),
  created_at  timestamptz not null default now(),
  used_at     timestamptz
);
comment on table public.qbo_oauth_state is 'qbo-1a: OAuth CSRF state — EF 가 만든 32 바이트 무작위의 sha256 hex 만(원문은 Intuit 허락 주소에만) · 10 분 · 한 번(qbo_state_consume 조건부 update 1 행) · 지난 것은 state_new 가 지운다 · grant 0 · 컷오버 K';

create table public.qbo_call_log (
  id           bigint generated always as identity primary key,
  called_at    timestamptz not null default now(),
  env          text,
  realm_id     text,
  action       text not null,
  ok           boolean not null,
  http_status  int,
  intuit_tid   text,
  error        text,
  by_staff     uuid references public.ims_staff (id),
  ms           int
);
create index qbo_call_log_called_idx on public.qbo_call_log (called_at);
comment on table  public.qbo_call_log is 'qbo-1a: EF qbo 의 호출 기록(fc_call_log 꼴 · 90 일 · EF 가 service_role 로 쓰고 지운다 · 토큰 · 비밀은 EF 가 거른 뒤) · 컷오버 K';
comment on column public.qbo_call_log.intuit_tid is 'Intuit 응답 머리 intuit_tid — Intuit 지원 문의 때 이 값으로 찾는다(설문 Error Handling 2)';

-- RLS · grant — 연결 · state 는 정책 0 · grant 0(창구만) · call_log 는 fc_call_log 와 같다(authenticated 읽기 · service_role 쓰기 · 지우기)
alter table public.qbo_connection  enable row level security;
alter table public.qbo_oauth_state enable row level security;
alter table public.qbo_call_log    enable row level security;
revoke all on public.qbo_connection, public.qbo_oauth_state, public.qbo_call_log from public, anon, authenticated, service_role;
create policy qbo_call_log_select on public.qbo_call_log for select to authenticated using (true);
grant select on public.qbo_call_log to authenticated, service_role;
grant insert, delete on public.qbo_call_log to service_role;
revoke all on sequence public.qbo_call_log_id_seq from public, anon, authenticated, service_role;
grant usage on sequence public.qbo_call_log_id_seq to service_role;

-- ═══ 2) 속 함수 — env 검사 · Vault 넣기 · 읽기 · 지우기 (실행 권한 0 · definer 창구 안에서만) ═══
create function public.qbo_env_check(p_env text) returns text
  language plpgsql immutable
  set search_path = public, pg_temp
as $$
begin
  if p_env is null or p_env not in ('sandbox', 'production') then
    raise exception 'QuickBooks environment must be sandbox or production (got %) — nothing was saved', coalesce(p_env, 'null');
  end if;
  return p_env;
end;
$$;
revoke all on function public.qbo_env_check(text) from public, anon, authenticated, service_role;

create function public.qbo_vault_put(p_name text, p_value text, p_id uuid) returns uuid
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if p_value is null or btrim(p_value) = '' then raise exception 'Token for % is empty — nothing was saved', p_name; end if;
  if p_id is not null and exists (select 1 from vault.secrets s where s.id = p_id) then
    perform vault.update_secret(p_id, new_secret => p_value);
    return p_id;
  end if;
  delete from vault.secrets s where s.name = p_name;                                             -- 짝 잃은 옛 행(이름 유니크)
  v_id := vault.create_secret(p_value, p_name, 'qbo-1a: QuickBooks OAuth token — read by qbo_token_get only');
  return v_id;
end;
$$;
revoke all on function public.qbo_vault_put(text, text, uuid) from public, anon, authenticated, service_role;

create function public.qbo_vault_get(p_id uuid) returns text
  language sql stable
  set search_path = public, pg_temp
as $$ select d.decrypted_secret from vault.decrypted_secrets d where d.id = p_id; $$;
revoke all on function public.qbo_vault_get(uuid) from public, anon, authenticated, service_role;

create function public.qbo_vault_drop(p_env text, p_ids uuid[]) returns int
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_n int;
begin
  delete from vault.secrets s where s.id = any (coalesce(p_ids, '{}')) or s.name in ('qbo/' || p_env || '/refresh', 'qbo/' || p_env || '/access');
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.qbo_vault_drop(text, uuid[]) from public, anon, authenticated, service_role;

-- ═══ 3) 직원 창구 — qbo_status(누구나) · qbo_admin_gate · qbo_state_new · qbo_realm_clear(admin · 870) ═══
create function public.qbo_status() returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v      public.qbo_connection%rowtype;
  v_by   text;
  v_adm  boolean := public.ims_is_admin();
  v_pins jsonb;
begin
  select coalesce(jsonb_object_agg(replace(c.key, 'qbo_realm_', ''), c.value), '{}'::jsonb) into v_pins from public.inv_config c where c.key in ('qbo_realm_sandbox', 'qbo_realm_production');
  select * into v from public.qbo_connection;
  if not found then
    return jsonb_build_object('status', 'none', 'caller_is_admin', v_adm, 'pinned_realm', v_pins);
  end if;
  select s.name into v_by from public.ims_staff s where s.id = v.connected_by;
  return jsonb_build_object(
    'status', v.status, 'env', v.env, 'realm_id', v.realm_id, 'company_name', v.company_name,
    'connected_by', v_by, 'connected_at', v.connected_at,
    'access_expires_at', v.access_expires_at, 'refresh_expires_at', v.refresh_expires_at,
    'token_version', v.token_version, 'refreshing', (v.refreshing_until is not null and v.refreshing_until > now()),
    'last_refresh_at', v.last_refresh_at, 'last_error', v.last_error, 'last_error_at', v.last_error_at,
    'caller_is_admin', v_adm, 'pinned_realm', v_pins);
end;
$$;
revoke all on function public.qbo_status() from public, anon, authenticated, service_role;
grant execute on function public.qbo_status() to authenticated;
comment on function public.qbo_status() is 'qbo-1a: Settings ?t=qbo 가 읽는 연결 상태 한 줄 — 토큰 칸 없음(Vault id 도 없음) · 연결 없으면 status none · caller_is_admin(870 · 단추를 보일지) · pinned_realm(env 별 고정 회사)';

create function public.qbo_admin_gate() returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare v_s public.ims_staff%rowtype;
begin
  if not public.ims_is_admin() then
    raise exception 'Only an admin can connect, disconnect or reconnect QuickBooks — nothing was changed';
  end if;
  select * into v_s from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  return jsonb_build_object('staff_id', v_s.id, 'name', v_s.name);
end;
$$;
revoke all on function public.qbo_admin_gate() from public, anon, authenticated, service_role;
grant execute on function public.qbo_admin_gate() to authenticated;
comment on function public.qbo_admin_gate() is 'qbo-1a 판정 870: EF qbo 가 사용자 JWT 로 부른다 — 활성 admin 이 아니면 거부 · 통과하면 staff_id · name(by_staff 용)';

create function public.qbo_state_new(p_env text, p_state_hash text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_gate jsonb := public.qbo_admin_gate();
  v_c    public.qbo_connection%rowtype;
  v_at   timestamptz := now();
begin
  perform public.qbo_env_check(p_env);
  if p_state_hash is null or p_state_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'State hash must be 64 hex characters (sha256) — nothing was saved';
  end if;
  delete from public.qbo_oauth_state s where s.created_at < v_at - interval '10 minutes';
  select * into v_c from public.qbo_connection;
  if found and v_c.status = 'connected' then
    raise exception 'QuickBooks is already connected to company % (%) — disconnect first to connect again — nothing was saved', coalesce(v_c.company_name, v_c.realm_id), v_c.env;
  end if;
  if found and v_c.env <> p_env then
    raise exception 'The connection on file is % — disconnect it before connecting to % — nothing was saved', v_c.env, p_env;
  end if;
  insert into public.qbo_oauth_state (state_hash, staff_id, env, created_at) values (p_state_hash, (v_gate->>'staff_id')::uuid, p_env, v_at);
  return jsonb_build_object('state_hash', p_state_hash, 'env', p_env, 'expires_at', v_at + interval '10 minutes');
end;
$$;
revoke all on function public.qbo_state_new(text, text) from public, anon, authenticated, service_role;
grant execute on function public.qbo_state_new(text, text) to authenticated;
comment on function public.qbo_state_new(text, text) is 'qbo-1a: 연결 시작(EF start · admin 870) — 10 분 지난 state 지우기 → 이미 connected 면 거부(다시 연결은 needs_reconnect 이거나 연결 없음일 때만) → sha256 hex 한 줄';

create function public.qbo_realm_clear(p_env text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_n int;
begin
  perform public.qbo_admin_gate();
  perform public.qbo_env_check(p_env);
  if exists (select 1 from public.qbo_connection) then
    raise exception 'Disconnect QuickBooks before clearing the pinned company — nothing was changed';
  end if;
  delete from public.inv_config c where c.key = 'qbo_realm_' || p_env;
  get diagnostics v_n = row_count;
  return jsonb_build_object('env', p_env, 'cleared', v_n > 0);
end;
$$;
revoke all on function public.qbo_realm_clear(text) from public, anon, authenticated, service_role;
grant execute on function public.qbo_realm_clear(text) to authenticated;
comment on function public.qbo_realm_clear(text) is 'qbo-1a: env 의 고정 회사(inv_config.qbo_realm_<env>) 비우기 — admin(870) · 연결이 없을 때만 · 다음 연결이 새 회사를 고정한다(회사를 바꾸는 별도 동작)';

-- ═══ 4) 서비스 창구 — EF qbo 전용(doc_is_service · grant service_role) ═══
create function public.qbo_state_consume(p_state_hash text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_s public.qbo_oauth_state%rowtype;
begin
  if not public.doc_is_service() then raise exception 'qbo_state_consume is for the QuickBooks service only — nothing was changed'; end if;
  update public.qbo_oauth_state s set used_at = now()
    where s.state_hash = p_state_hash and s.used_at is null and s.created_at >= now() - interval '10 minutes'
    returning * into v_s;
  if found then return jsonb_build_object('staff_id', v_s.staff_id, 'env', v_s.env, 'created_at', v_s.created_at); end if;
  select * into v_s from public.qbo_oauth_state s where s.state_hash = p_state_hash;
  if not found then raise exception 'Sign-in state not found — start the connection again from Settings — nothing was changed'; end if;
  if v_s.used_at is not null then raise exception 'Sign-in state was already used — start the connection again from Settings — nothing was changed'; end if;
  raise exception 'Sign-in state expired (10 minutes) — start the connection again from Settings — nothing was changed';
end;
$$;
revoke all on function public.qbo_state_consume(text) from public, anon, authenticated, service_role;
grant execute on function public.qbo_state_consume(text) to service_role;
comment on function public.qbo_state_consume(text) is 'qbo-1a: EF callback — 있고 · 10 분 안 · 안 쓴 state 만 used_at 을 채운다(조건부 update 1 행 = CSRF 한 번) · 아니면 사람 말로 가른다(없음 · 이미 씀 · 지남)';

create function public.qbo_connection_save(p_env text, p_realm text, p_refresh text, p_access text, p_access_exp timestamptz, p_refresh_exp timestamptz, p_staff uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_c     public.qbo_connection%rowtype;
  v_key   text;
  v_pin   text;
  v_rid   uuid;
  v_aid   uuid;
  v_realm text := btrim(coalesce(p_realm, ''));
begin
  if not public.doc_is_service() then raise exception 'qbo_connection_save is for the QuickBooks service only — nothing was saved'; end if;
  perform public.qbo_env_check(p_env);
  if v_realm !~ '^[0-9]{4,32}$' then raise exception 'QuickBooks company id (realmId) "%" is not a number — nothing was saved', v_realm; end if;
  if p_access_exp is null then raise exception 'Access token expiry is required — nothing was saved'; end if;
  if p_staff is null or not exists (select 1 from public.ims_staff s where s.id = p_staff) then raise exception 'Connecting staff % is not on file — nothing was saved', coalesce(p_staff::text, 'null'); end if;
  -- realm 고정(env 별) — 첫 연결이 고정 · 다른 회사는 거부
  v_key := 'qbo_realm_' || p_env;
  select c.value into v_pin from public.inv_config c where c.key = v_key;
  if v_pin is null then
    insert into public.inv_config (key, value, note, updated_by) values (v_key, v_realm, 'qbo-1a: 처음 연결한 QuickBooks 회사 id(' || p_env || ') — 다른 회사는 저장 거부 · 비우기는 qbo_realm_clear(admin · 연결 없을 때)', p_staff);
  elsif v_pin <> v_realm then
    raise exception 'QuickBooks company % is not the company this IMS was first connected to (%) — connect the same company, or ask an admin to clear the pinned company first — nothing was saved', v_realm, v_pin;
  end if;
  select * into v_c from public.qbo_connection for update;
  if found and v_c.env <> p_env then
    raise exception 'A % connection is still on file — disconnect it before connecting to % — nothing was saved', v_c.env, p_env;
  end if;
  v_rid := public.qbo_vault_put('qbo/' || p_env || '/refresh', p_refresh, v_c.refresh_secret_id);
  v_aid := public.qbo_vault_put('qbo/' || p_env || '/access',  p_access,  v_c.access_secret_id);
  insert into public.qbo_connection (env, realm_id, connected_by, connected_at, refresh_secret_id, access_secret_id, access_expires_at, refresh_expires_at)
    values (p_env, v_realm, p_staff, now(), v_rid, v_aid, p_access_exp, p_refresh_exp)
  on conflict (singleton) do update set
    env = excluded.env, realm_id = excluded.realm_id, status = 'connected',
    company_name = case when public.qbo_connection.realm_id = excluded.realm_id then public.qbo_connection.company_name else null end,
    connected_by = excluded.connected_by, connected_at = excluded.connected_at,
    refresh_secret_id = excluded.refresh_secret_id, access_secret_id = excluded.access_secret_id,
    access_expires_at = excluded.access_expires_at, refresh_expires_at = excluded.refresh_expires_at,
    token_version = public.qbo_connection.token_version + 1,
    refreshing_until = null, refreshing_by = null, last_error = null, last_error_at = null, updated_at = now()
  returning * into v_c;
  return jsonb_build_object('env', v_c.env, 'realm_id', v_c.realm_id, 'status', v_c.status, 'token_version', v_c.token_version, 'company_name', v_c.company_name);
end;
$$;
revoke all on function public.qbo_connection_save(text, text, text, text, timestamptz, timestamptz, uuid) from public, anon, authenticated, service_role;
grant execute on function public.qbo_connection_save(text, text, text, text, timestamptz, timestamptz, uuid) to service_role;
comment on function public.qbo_connection_save(text, text, text, text, timestamptz, timestamptz, uuid) is 'qbo-1a: EF callback 이 토큰 교환 뒤 — realm 고정 검사(첫 연결이면 inv_config 에 고정) → Vault 두 행 넣기 · 바꾸기 → 연결 행 connected · token_version + 1 · 오류 비움 · 다른 env 행이 있으면 거부 · 돌려주는 것에 토큰 없음';

create function public.qbo_company_name_set(p_name text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_name text := left(btrim(coalesce(p_name, '')), 200);
begin
  if not public.doc_is_service() then raise exception 'qbo_company_name_set is for the QuickBooks service only — nothing was saved'; end if;
  if v_name = '' then raise exception 'Company name is empty — nothing was saved'; end if;
  update public.qbo_connection set company_name = v_name, updated_at = now();
  if not found then raise exception 'QuickBooks is not connected — nothing was saved'; end if;
  return jsonb_build_object('company_name', v_name);
end;
$$;
revoke all on function public.qbo_company_name_set(text) from public, anon, authenticated, service_role;
grant execute on function public.qbo_company_name_set(text) to service_role;
comment on function public.qbo_company_name_set(text) is 'qbo-1a: EF ping(CompanyInfo) 의 CompanyName 을 연결 행에';

create function public.qbo_token_get() returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare v_c public.qbo_connection%rowtype;
begin
  if not public.doc_is_service() then raise exception 'qbo_token_get is for the QuickBooks service only — nothing was read'; end if;
  select * into v_c from public.qbo_connection;
  if not found then raise exception 'QuickBooks is not connected — nothing to read'; end if;
  return jsonb_build_object('env', v_c.env, 'realm_id', v_c.realm_id, 'status', v_c.status, 'token_version', v_c.token_version,
    'access_expires_at', v_c.access_expires_at, 'refresh_expires_at', v_c.refresh_expires_at,
    'refresh_token', public.qbo_vault_get(v_c.refresh_secret_id), 'access_token', public.qbo_vault_get(v_c.access_secret_id));
end;
$$;
revoke all on function public.qbo_token_get() from public, anon, authenticated, service_role;
grant execute on function public.qbo_token_get() to service_role;
comment on function public.qbo_token_get() is 'qbo-1a: EF 전용 — Vault 에서 두 토큰을 풀어 준다(화면 · 직원은 실행 권한 없음 · 시험 B 가 보인다)';

create function public.qbo_refresh_claim(p_owner uuid) returns jsonb
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
  update public.qbo_connection set refreshing_until = now() + interval '30 seconds', refreshing_by = p_owner, updated_at = now() returning * into v_c;
  return jsonb_build_object('env', v_c.env, 'realm_id', v_c.realm_id, 'token_version', v_c.token_version, 'refreshing_until', v_c.refreshing_until,
    'refresh_token', public.qbo_vault_get(v_c.refresh_secret_id), 'access_token', public.qbo_vault_get(v_c.access_secret_id));
end;
$$;
revoke all on function public.qbo_refresh_claim(uuid) from public, anon, authenticated, service_role;
grant execute on function public.qbo_refresh_claim(uuid) to service_role;
comment on function public.qbo_refresh_claim(uuid) is 'qbo-1a: 갱신 임대 — 비었거나 지난 임대만 30 s 로 쥐고 토큰 + 판 번호를 준다 · 쥔 임대가 살아 있으면 「다른 갱신 중」 · needs_reconnect 면 거부(다시 시도하지 않는다)';

create function public.qbo_refresh_save(p_version int, p_refresh text, p_access text, p_access_exp timestamptz, p_refresh_exp timestamptz) returns jsonb
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
    returning * into v_c;
  return jsonb_build_object('token_version', v_c.token_version, 'access_expires_at', v_c.access_expires_at, 'refresh_expires_at', v_c.refresh_expires_at);
end;
$$;
revoke all on function public.qbo_refresh_save(int, text, text, timestamptz, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.qbo_refresh_save(int, text, text, timestamptz, timestamptz) to service_role;
comment on function public.qbo_refresh_save(int, text, text, timestamptz, timestamptz) is 'qbo-1a: 갱신 결과 저장 — claim 이 준 판 번호와 같을 때만 Vault 를 바꾸고 +1 · 임대 풀기 · last_refresh_at · 다르면 거부(사람 말 — 옛 토큰으로 덮지 않는다)';

create function public.qbo_mark_needs_reconnect(p_error text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_c public.qbo_connection%rowtype;
begin
  if not public.doc_is_service() then raise exception 'qbo_mark_needs_reconnect is for the QuickBooks service only — nothing was changed'; end if;
  update public.qbo_connection set status = 'needs_reconnect', last_error = left(coalesce(nullif(btrim(p_error), ''), 'QuickBooks refused the token'), 400), last_error_at = now(),
    refreshing_until = null, refreshing_by = null, updated_at = now() returning * into v_c;
  if not found then raise exception 'QuickBooks is not connected — nothing was changed'; end if;
  return jsonb_build_object('status', v_c.status, 'last_error', v_c.last_error, 'last_error_at', v_c.last_error_at);
end;
$$;
revoke all on function public.qbo_mark_needs_reconnect(text) from public, anon, authenticated, service_role;
grant execute on function public.qbo_mark_needs_reconnect(text) to service_role;
comment on function public.qbo_mark_needs_reconnect(text) is 'qbo-1a: invalid_grant · 갱신 토큰 만료 · QBO 쪽에서 끊김 → needs_reconnect · last_error(EF 가 거른 글) · 임대 풀기 · 토큰은 남긴다(끊기는 admin 의 동작)';

create function public.qbo_connection_delete() returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_c public.qbo_connection%rowtype; v_v int := 0; v_s int;
begin
  if not public.doc_is_service() then raise exception 'qbo_connection_delete is for the QuickBooks service only — nothing was deleted'; end if;
  select * into v_c from public.qbo_connection for update;
  if found then
    v_v := public.qbo_vault_drop(v_c.env, array[v_c.refresh_secret_id, v_c.access_secret_id]);
    delete from public.qbo_connection;
  else
    v_v := public.qbo_vault_drop('sandbox', null) + public.qbo_vault_drop('production', null);      -- 짝 잃은 Vault 행도 치운다
  end if;
  delete from public.qbo_oauth_state;
  get diagnostics v_s = row_count;
  return jsonb_build_object('deleted', v_c.singleton is not null, 'env', v_c.env, 'vault_rows_removed', v_v, 'states_removed', v_s);
end;
$$;
revoke all on function public.qbo_connection_delete() from public, anon, authenticated, service_role;
grant execute on function public.qbo_connection_delete() to service_role;
comment on function public.qbo_connection_delete() is 'qbo-1a: 끊기(EF disconnect · admin 870 은 EF 가 qbo_admin_gate 로 먼저) — Vault 두 행 + 연결 행 + state 전부 지움(처리방침 §4 약속) · 없는 것을 지워도 오류 아님 · 누가 끊었나는 EF 의 qbo_call_log';

-- ═══ 5) 착지 확인 ═══
do $$
declare v_n int; v_acl text; v_bad text := '';
begin
  if (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r' and relname in ('qbo_connection', 'qbo_oauth_state', 'qbo_call_log')) <> 3 then v_bad := v_bad || ' tables'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_status', 'qbo_admin_gate', 'qbo_state_new', 'qbo_realm_clear', 'qbo_state_consume', 'qbo_connection_save', 'qbo_company_name_set', 'qbo_token_get', 'qbo_refresh_claim', 'qbo_refresh_save', 'qbo_mark_needs_reconnect', 'qbo_connection_delete', 'qbo_env_check', 'qbo_vault_put', 'qbo_vault_get', 'qbo_vault_drop')) <> 16 then v_bad := v_bad || ' functions'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'qbo_connection' and data_type = 'text' and column_name ~ '(token|secret)') <> 0 then v_bad := v_bad || ' (token column on qbo_connection)'; end if;
  select relacl::text into v_acl from pg_class where oid = 'public.qbo_connection'::regclass;
  if v_acl <> '{postgres=arwdDxtm/postgres}' then v_bad := v_bad || ' qbo_connection acl ' || v_acl; end if;
  select relacl::text into v_acl from pg_class where oid = 'public.qbo_oauth_state'::regclass;
  if v_acl <> '{postgres=arwdDxtm/postgres}' then v_bad := v_bad || ' qbo_oauth_state acl ' || v_acl; end if;
  select relacl::text into v_acl from pg_class where oid = 'public.qbo_call_log'::regclass;
  if v_acl <> '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=ard/postgres}' then v_bad := v_bad || ' qbo_call_log acl ' || v_acl; end if;
  if (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname in ('qbo_connection', 'qbo_oauth_state', 'qbo_call_log') and relrowsecurity) <> 3 then v_bad := v_bad || ' rls'; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('qbo_connection', 'qbo_oauth_state', 'qbo_call_log')) <> 1 then v_bad := v_bad || ' policies'; end if;
  if to_regprocedure('vault.create_secret(text, text, text, uuid)') is null or to_regprocedure('vault.update_secret(uuid, text, text, text, uuid)') is null or to_regclass('vault.decrypted_secrets') is null then v_bad := v_bad || ' (vault functions missing)'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_is_admin') is distinct from 'f436952852c42e41a06885659c07207a' then v_bad := v_bad || ' ims_is_admin'; end if;
  if to_regprocedure('public.doc_is_service()') is null then v_bad := v_bad || ' doc_is_service'; end if;
  if (select count(*) from pg_constraint con join pg_class c on c.oid = con.conrelid where con.contype = 'f' and c.relname in ('qbo_connection', 'qbo_oauth_state', 'qbo_call_log') and con.confrelid <> 'public.ims_staff'::regclass) <> 0 then v_bad := v_bad || ' (FK outside ims_staff)'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM870', message = format('STOP - qbo-1a landing check failed:%s', v_bad); end if;
end $$;
