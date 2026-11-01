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
-- mcp-2 — IMS Claude 커넥터 호출 기록 표 mcp_call_log + 쓰기 창구 mcp_log_add + 지우기 창구 mcp_log_purge (2026-11-01 UTC · 판정 924 · 지시서 ~/asung/prompts/mcp-2.md · 이견 11 · 13 · 14 반영)
--   무엇: EF ims-mcp 가 tools/call 마다 한 줄(시각 · 직원 · client_id · 도구 · 입력값(EF 가 2 KB 로 자른 것) · ms · 갈래 ok | refused | error · 오류 코드 · 짧은 오류 글 · 결과 바이트) — ⚠️ 결과 내용은 적지 않는다(손님 데이터의 두 번째 사본 금지 · 924)
--   쓰기: EF 만 service_role 로 mcp_log_add(…) — 표 권한은 service_role · authenticated · anon · ims_connector 전부 0(창구만) · 읽기는 admin 만(RLS ims_is_admin · authenticated select grant — 나중 화면용)
--   지우기: mcp_log_purge() = called_at < now() - 1 year · cron 이 매일 부른다(등록은 마이그레이션 밖 · supabase/ops/cron.sql 「ims-mcp-log-purge」)
--   ⚠️ FK 없음(ims_staff · 거래 표 모두) — 기록은 사람이 지워져도 남는다 · 컷오버 날 지우기 대상 아님(거래 표 FK 0 · cutover-delete ③-c 「D 밖 → D FK 0」)
--   무접촉: mcp-1a 의 역할 · 훅 · 도구 · mcp_config · 화면 · 대시보드 · 첫 문장 = guard-test-only.sql 바이트 복사
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261101000546_mcp_2_call_log.sql && supabase migration repair --status applied 20261101000546 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): MIG=supabase/migrations/20261101000546_mcp_2_call_log.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/mcp_2_check.sql

-- ═══ A) 표 ═══
create table public.mcp_call_log (
  id            bigint generated always as identity primary key,
  called_at     timestamptz not null default now(),
  auth_user_id  uuid,
  staff_id      uuid,                                                                 -- FK 없음: 창구가 auth_user_id 로 찾아 넣는다 · 못 찾으면 null · 사람이 지워져도 줄은 남는다
  client_id     text,
  tool          text not null,
  args          jsonb,                                                                -- EF 가 2 KB 로 자른 것(넘으면 {"_truncated":true,"chars":N,"head":"…"} · 이견 11) · 창구는 받는 대로
  ms            int,
  outcome       text not null constraint mcp_call_log_outcome_ck check (outcome in ('ok', 'refused', 'error')),
  error_code    text,
  error_message text constraint mcp_call_log_error_message_ck check (error_message is null or length(error_message) <= 200),
  result_bytes  int
);
create index mcp_call_log_called_idx       on public.mcp_call_log (called_at);
create index mcp_call_log_staff_called_idx on public.mcp_call_log (staff_id, called_at);
comment on table public.mcp_call_log is 'mcp-2 판정 924: Claude 커넥터 도구 호출 기록 — tools/call 마다 한 줄(EF ims-mcp 가 service_role 로 mcp_log_add) · 결과 내용 없음(결과 바이트 수만) · 1 년 지난 줄은 mcp_log_purge(cron) · FK 없음 · 읽기는 admin 만(RLS) · 컷오버 지우기 대상 아님';
comment on column public.mcp_call_log.outcome is 'ok = 도구가 값을 냈다 · refused = 문이 거절(42501 · mcp_gate P0001 — 직원이 읽을 한 문장이 error_message) · error = 그 밖(timeout · DB 오류 · 인자 틀림)';
alter table public.mcp_call_log enable row level security;
create policy mcp_call_log_select_admin on public.mcp_call_log for select to authenticated using (public.ims_is_admin());
revoke all on table public.mcp_call_log from public, anon, authenticated, service_role, ims_connector;
grant select on table public.mcp_call_log to authenticated;                           -- 나중 화면용 · 행은 RLS(admin 만)

-- ═══ B) 쓰기 창구 — service_role 만(EF) · 직원 찾기는 auth_user_id → ims_staff.id(활성 여부 무관 · 없으면 null) ═══
create or replace function public.mcp_log_add(p_auth_user_id uuid, p_client_id text, p_tool text, p_args jsonb, p_ms int, p_outcome text,
                                              p_error_code text default null, p_error_message text default null, p_result_bytes int default null) returns bigint
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_id bigint;
begin
  insert into public.mcp_call_log (auth_user_id, staff_id, client_id, tool, args, ms, outcome, error_code, error_message, result_bytes)
  values (p_auth_user_id, (select s.id from public.ims_staff s where s.auth_user_id = p_auth_user_id limit 1), p_client_id, p_tool, p_args, p_ms, p_outcome,
          p_error_code, left(p_error_message, 200), p_result_bytes)
  returning id into v_id;
  return v_id;
end;
$$;
comment on function public.mcp_log_add(uuid, text, text, jsonb, int, text, text, text, int) is 'mcp-2 판정 924: EF ims-mcp 가 tools/call 끝에 service_role 로 부른다 — 한 줄 insert · staff_id 는 auth_user_id 로 찾아 넣는다(없으면 null) · error_message 는 200 자로 자른다 · 돌려주는 것 = id';

-- ═══ C) 지우기 창구 — 1 년 지난 줄 · cron(postgres) 또는 service_role ═══
create or replace function public.mcp_log_purge() returns int
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_n int;
begin
  delete from public.mcp_call_log where called_at < now() - interval '1 year';        -- REST safeupdate: WHERE 있음
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
comment on function public.mcp_log_purge() is 'mcp-2 판정 924: mcp_call_log 에서 called_at 이 1 년보다 오래된 줄을 지운다 — cron ims-mcp-log-purge(매일 · supabase/ops/cron.sql) · 돌려주는 것 = 지운 수';

revoke all on function public.mcp_log_add(uuid, text, text, jsonb, int, text, text, text, int), public.mcp_log_purge() from public, anon, authenticated, service_role, ims_connector;
grant execute on function public.mcp_log_add(uuid, text, text, jsonb, int, text, text, text, int) to service_role;
grant execute on function public.mcp_log_purge() to service_role;

-- ═══ 착지 검사 ═══
do $$
declare v text;
begin
  select c.relacl::text || ' rls=' || c.relrowsecurity::text into v from pg_class c where c.oid = 'public.mcp_call_log'::regclass;
  if v <> '{postgres=arwdDxtm/postgres,authenticated=r/postgres} rls=true' then raise exception 'mcp-2 landing: table acl %', v; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'mcp_call_log') <> 1 then raise exception 'mcp-2 landing: policy count'; end if;
  if (select count(*) from pg_constraint where conrelid = 'public.mcp_call_log'::regclass and contype = 'f') <> 0 then raise exception 'mcp-2 landing: FK must be 0'; end if;
  select string_agg(p.proname || '=' || p.proacl::text, ' ' order by p.proname) into v from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_log_add', 'mcp_log_purge');
  if v <> 'mcp_log_add={postgres=X/postgres,service_role=X/postgres} mcp_log_purge={postgres=X/postgres,service_role=X/postgres}' then raise exception 'mcp-2 landing: function acl %', v; end if;
  raise notice 'mcp-2 landing OK — mcp_call_log acl+rls · policy 1 · FK 0 · mcp_log_add · mcp_log_purge acl';
end $$;
