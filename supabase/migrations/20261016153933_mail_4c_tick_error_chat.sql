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
-- 20261016153933_mail_4c_tick_error_chat.sql — mail-4c (2026-10-16 · 회사 PC · Fable · mail-4a 1e6ca6e 위에) · 판정 518(Caleb 「2」 — 창고 회차가 실패하면 백오더 Chat Space 에도 한 줄)
--   ① mail_run_error 에 Chat 칸 셋(chat_posted_at · chat_error · chat_attempts — 2a 회차 Chat 칸과 같은 꼴 · 다섯 번 실패하면 더 안 나온다)
--   ② 짝 창구 둘(새로 · 2a 의 mail_run_chat_due 는 재발행하지 않는다 — mail-4c 이견 1): mail_run_error_chat_due() · mail_run_error_chat_mark(p_id, p_ok, p_error) — service_role · postgres 만
--      「그 창고 · 그날 한 번만」: 오류 행은 창고 · 날마다 하나(4a) · 첫 게시 뒤 attempts 만 오르는 것은 다시 안 나온다 · 풀린(resolved) 행은 안 올린다(그날 회차 요약이 대신 간다 · 이견 2)
--   무접촉: tick · 2a 창구 · 표 셋 · 화면 창구 · EF 는 따로(supabase/functions/mail) · cron 56 은 고침 덩이(~/asung/prompts/mail-4c-cron.sql)
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 ~/asung/prompts/mail-4c-verify.sql

-- ═══ ① Chat 칸 ═══
alter table public.mail_run_error add column chat_posted_at timestamptz;
alter table public.mail_run_error add column chat_error text;
alter table public.mail_run_error add column chat_attempts int not null default 0;
alter table public.mail_run_error add constraint mail_run_error_chat_attempts_ck check (chat_attempts >= 0);
comment on column public.mail_run_error.chat_posted_at is 'mail-4c 판정 518 — 이 실패를 백오더 Chat Space 에 올린 때(창고 · 날마다 한 번 · 뒤에 attempts 가 올라도 다시 안 올린다)';
comment on column public.mail_run_error.chat_attempts is 'mail-4c — 실패 Chat 을 올리다 실패한 횟수 · 다섯 번이면 mail_run_error_chat_due 가 더 내지 않는다(chat_error 에 마지막 까닭)';

-- ═══ ② 짝 창구 ═══
create function public.mail_run_error_chat_due() returns jsonb
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'error_id', e.id, 'kind', e.kind, 'location_id', e.location_id, 'location_name', w.name, 'run_on', e.run_on, 'first_at', e.first_at, 'last_at', e.last_at,
           'attempts', e.attempts, 'message', e.message, 'chat_attempts', e.chat_attempts, 'chat_error', e.chat_error)
         order by e.first_at, e.id), '[]'::jsonb)
  from (select * from public.mail_run_error ee
        where ee.chat_posted_at is null and ee.chat_attempts < 5 and ee.resolved_at is null
        order by ee.first_at, ee.id limit 20) e
  join public.ref_warehouse w on w.id = e.location_id;
$$;
comment on function public.mail_run_error_chat_due() is 'mail-4c 판정 518 — Chat 에 「회차 실패」 한 줄을 올릴 오류 행(service_role 만): 아직 안 올렸고 · 다섯 번 미만 실패했고 · 풀리지 않은 것 · 오래된 것부터 20 · {error_id, kind, location_id, location_name, run_on, first_at, last_at, attempts, message, chat_attempts, chat_error}';
revoke all on function public.mail_run_error_chat_due() from public, anon, authenticated;
grant execute on function public.mail_run_error_chat_due() to service_role;

create function public.mail_run_error_chat_mark(p_id bigint, p_ok boolean, p_error text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_e public.mail_run_error%rowtype;
begin
  select * into v_e from public.mail_run_error e where e.id = p_id for update;
  if not found then
    raise exception 'Mail run error % not found — nothing was saved', p_id;
  end if;
  if v_e.chat_posted_at is not null then
    raise exception 'Mail run error % already has its Chat line (%) — nothing was saved', p_id, v_e.chat_posted_at;
  end if;
  if coalesce(p_ok, false) then
    update public.mail_run_error set chat_posted_at = now(), chat_error = null where id = p_id;
  else
    update public.mail_run_error set chat_attempts = chat_attempts + 1, chat_error = left(coalesce(p_error, 'chat post failed'), 2000) where id = p_id;
  end if;
  return (select jsonb_build_object('error_id', e.id, 'chat_posted_at', e.chat_posted_at, 'chat_attempts', e.chat_attempts, 'chat_error', e.chat_error) from public.mail_run_error e where e.id = p_id);
end;
$$;
comment on function public.mail_run_error_chat_mark(bigint, boolean, text) is 'mail-4c 판정 518 — EF 가 실패 Chat 결과를 적는다(service_role 만): 성공이면 chat_posted_at · 실패면 chat_attempts + 1 · chat_error · 이미 올린 행은 거부(mail_run_chat_mark 와 같은 꼴)';
revoke all on function public.mail_run_error_chat_mark(bigint, boolean, text) from public, anon, authenticated;
grant execute on function public.mail_run_error_chat_mark(bigint, boolean, text) to service_role;

-- ═══ ③ 실물 확인 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'mail_run_error' and column_name in ('chat_posted_at', 'chat_error', 'chat_attempts')) <> 3 then v_bad := v_bad || ' columns'; end if;
  if has_function_privilege('authenticated', 'public.mail_run_error_chat_due()', 'execute') or not has_function_privilege('service_role', 'public.mail_run_error_chat_due()', 'execute')
     or has_function_privilege('authenticated', 'public.mail_run_error_chat_mark(bigint, boolean, text)', 'execute') or not has_function_privilege('service_role', 'public.mail_run_error_chat_mark(bigint, boolean, text)', 'execute')
     or has_function_privilege('anon', 'public.mail_run_error_chat_due()', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM519', message = format('STOP - mail-4c did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
