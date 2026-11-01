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
-- qbo-read-1 — qbo_call_log 에 detail jsonb 칸 하나 (2026-11-01 · 판정 933 · 지시서 ~/asung/prompts/qbo-read-1.md · 이견 1 「B」 · 선례 mcp_call_log.args 20261101000546:44)
--   무엇: EF qbo 의 새 읽기 전용 액션 query · read 가 호출 한 줄에 담는 것 — entity · rows(받은 행 수) · totalCount(count(*) 일 때) · startPosition · maxResults · 다듬은 조회 문장(따옴표 리터럴 → ?)
--   ⚠️ 결과 행은 담지 않는다(손님 데이터의 두 번째 사본 금지 · 924 와 같은 까닭) · 손님 이름 같은 값은 EF 가 ? 로 바꾼 뒤 — call_log 는 로그인한 직원 누구나 읽는다(20261029160000:108)
--   기존 액션(status · start · callback · refresh · ping · disconnect · company_name)은 detail null 그대로(무변) · 칸 하나 추가뿐 — 창구 · 정책 · grant · 색인 · FK 무접촉
--   FK: qbo_call_log 의 FK 는 by_staff → ims_staff 하나뿐 · 거래 표 FK 0 — 컷오버 지우는 순서(cutover-delete.sql k11 K) 영향 없음
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사(검증 G0)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261101190000_qbo_read_1_call_log_detail.sql && supabase migration repair --status applied 20261101190000 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): MIG=supabase/migrations/20261101190000_qbo_read_1_call_log_detail.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_read_1_check.sql

alter table public.qbo_call_log add column detail jsonb;
comment on column public.qbo_call_log.detail is 'qbo-read-1: query · read 액션의 조회 요약(entity · rows · totalCount · startPosition · maxResults · q = 리터럴을 ? 로 바꾼 조회 문장) — 결과 행은 담지 않는다 · 다른 액션은 null';
