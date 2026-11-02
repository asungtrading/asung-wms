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
-- qbo-sync-2a′ — unknown 일감이 보낸 이름을 남긴다 · unknown 목록 창구 (2026-11-01 · 판정 945 · 지시서 ~/asung/prompts/qbo-sync-2a.md 2a′ · 2a 이견 12 「unknown → 다음 send 가 이름으로 조회해 푼다」 의 DB 바탕)
--   왜: EF send 가 결과를 모르면(네트워크 · 5xx · 응답 깨짐) qbo_job_unknown 으로 남기고, 다음 send 첫머리에 QBO 를 DisplayName · Name 으로 조회해 있으면 done · 없으면 사람이 retry 한다.
--       조회할 이름 = 그때 실제로 보낸 이름(` [SKU]` 가 붙었을 수도) — 몸을 다시 만들면 달라질 수 있어(그 사이 거울 · 이름이 바뀜) 보낸 이름을 qbo_job.qbo_name 에 남긴다.
--   무엇: qbo_job_unknown(p_job, p_error, p_intuit_tid, p_name) — 서명 바뀜(drop + create · 옛 서명 안 남음) · qbo_name = coalesce(p_name, qbo_name)
--         qbo_job_unknown_list() — service_role · state unknown 인 일감(id · kind · ims_kind · ims_id · qbo_name · sku · request_id · attempts · last_error · claimed_at 없음)
--   무접촉: 표 · 다른 창구 · 몸 함수 · 화면 · 첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사(G0)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261102030000_qbo_sync_2a2_unknown_name.sql && supabase migration repair --status applied 20261102030000 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): MIG=supabase/migrations/20261102030000_qbo_sync_2a2_unknown_name.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2a2_check.sql

drop function public.qbo_job_unknown(uuid, text, text);
create function public.qbo_job_unknown(p_job uuid, p_error text, p_intuit_tid text default null, p_name text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_j public.qbo_job%rowtype;
begin
  if not public.doc_is_service() then raise exception 'qbo_job_unknown is for the send worker only — nothing was saved'; end if;
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state <> 'sending' then raise exception 'Only a job being sent can become unknown (this one is %) — nothing was saved', v_j.state; end if;
  update public.qbo_job j set state = 'unknown', claimed_at = null, last_error = left(coalesce(nullif(btrim(coalesce(p_error, '')), ''), 'no answer from QuickBooks'), 2000), last_intuit_tid = coalesce(p_intuit_tid, j.last_intuit_tid),
         qbo_name = coalesce(nullif(btrim(coalesce(p_name, '')), ''), j.qbo_name)
   where j.id = v_j.id;
  return jsonb_build_object('job_id', v_j.id, 'state', 'unknown', 'attempts', v_j.attempts, 'qbo_name', coalesce(nullif(btrim(coalesce(p_name, '')), ''), v_j.qbo_name));
end;
$$;
comment on function public.qbo_job_unknown(uuid, text, text, text) is 'qbo-sync-2a′: 결과를 모른다(service_role · 네트워크 끊김 · 5xx · 응답 없음) — sending → unknown · p_name = 그때 보낸 이름(DisplayName · Name · ` [SKU]` 포함)을 qbo_name 에 남긴다 · 다음 send 가 qbo_job_unknown_list 로 읽어 QBO 를 그 이름으로 조회 → 있으면 done · 없으면 사람이 retry';

create function public.qbo_job_unknown_list() returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of();
begin
  if not public.doc_is_service() then raise exception 'qbo_job_unknown_list is for the send worker only — nothing was read'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('job_id', j.id, 'kind', j.kind, 'ims_kind', j.ims_kind, 'ims_id', j.ims_id, 'qbo_name', j.qbo_name,
                     'sku', case j.ims_kind when 'product' then (select btrim(p.sku) from public.product p where p.id::text = j.ims_id) end,
                     'request_id', j.request_id, 'attempts', j.attempts, 'last_error', j.last_error) order by j.created_at, j.id)
                   from public.qbo_job j where j.realm_id = v_realm and j.state = 'unknown'), '[]'::jsonb);
end;
$$;
comment on function public.qbo_job_unknown_list() is 'qbo-sync-2a′: unknown 일감 목록(service_role · EF send 첫머리) — job_id · kind · ims_kind · ims_id · qbo_name(보낸 이름) · sku(product) · request_id · attempts · last_error · created_at 순';

revoke all on function public.qbo_job_unknown(uuid, text, text, text), public.qbo_job_unknown_list() from public, anon, authenticated, service_role;
grant execute on function public.qbo_job_unknown(uuid, text, text, text), public.qbo_job_unknown_list() to service_role;

-- ═══ 착지 검사 ═══
do $$
declare v text;
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_job_unknown', 'qbo_job_unknown_list');
  if v <> 'qbo_job_unknown(p_job uuid, p_error text, p_intuit_tid text, p_name text)={postgres=X/postgres,service_role=X/postgres} qbo_job_unknown_list()={postgres=X/postgres,service_role=X/postgres}' then raise exception 'qbo-sync-2a′ landing: %', v; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_job_unknown') <> 1 then raise exception 'qbo-sync-2a′ landing: old qbo_job_unknown signature still there'; end if;
  raise notice 'qbo-sync-2a′ landing OK — qbo_job_unknown(4 인자) 하나 · qbo_job_unknown_list · service_role';
end $$;
