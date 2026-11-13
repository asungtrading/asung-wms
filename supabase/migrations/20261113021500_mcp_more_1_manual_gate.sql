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
-- mcp-more-1 — Claude 커넥터 매뉴얼 도구 둘(manual_search · manual_read)의 문 mcp_manual_gate() (2026-11-13 UTC · 지시서 ~/asung/prompts/mcp-more-1.md · 판정 1211 · 조사 mcp-more-0)
--   무엇: 매뉴얼 도구는 DB 를 읽지 않는다(EF ims-mcp 가 GitHub main 의 docs/manual 원고를 읽는다 · help.html 과 같은 곳) — 그래도 「Claude 열쇠를 끄면 다음 질문부터 거절(921)」 이 지켜지도록
--         EF 가 원고를 읽기 **전에** 사용자 토큰으로 이 함수를 부른다 · 몸 = perform mcp_gate(null) 하나(활성 직원 + perms ? claude | claude:read · client_id = mcp_config) · 화면 열쇠는 보지 않는다(매뉴얼 화면 help.html 이 열쇠 null — 로그인한 누구나)
--   꼴: 인자 없음 · returns boolean(늘 true — mcp_gate 의 staff id 를 커넥터에 돌려주지 않는다) · definer(mcp_gate 는 아무에게도 EXECUTE 가 없다) · stable · search_path 고정
--       도구 둘이 이 함수 하나를 같이 쓴다(창구를 둘로 나누면 몸이 같은 함수가 둘) · 거절은 mcp_gate 의 P0001 문장 그대로(EF 가 isError 로)
--   권한: ims_connector 만 EXECUTE(PUBLIC · anon · authenticated · service_role 0) · 표 · 뷰 0 그대로
--   무변: mcp_gate(본문 md5 e50d34c953bd66513458353207680e6f) · 도구 창구 여섯 · 훅 · mcp_config · mcp_call_log · 다른 표 · 창구 전부
--   적용(Caleb · IMS 메인 fazgmyvzzhqybtvtktyg): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f <이 파일> && supabase migration repair --status applied 20261113021500 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): MIG=<이 파일> psql "$(cat ~/.asung-testdb-url)" -X -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/mcp_more_1_check.sql   (확인 갈래 · 적용 뒤 · Caleb: -v mig 없이)
--   ⚠️ 순서: DB 먼저 · EF 나중 — 새 EF 가 옛 DB 를 만나면 매뉴얼 도구만 「could not run this tool (PGRST202)」 · 다른 도구 여섯은 그대로

-- ═══ 0) 바탕 확인 — mcp_gate 가 mcp-1a 판 한 벌인지 · 아니면 멈춘다 ═══
do $$
declare v_n int; v_md5 text;
begin
  select count(*), min(md5(p.prosrc)) into v_n, v_md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_gate';
  if v_n <> 1 or v_md5 <> 'e50d34c953bd66513458353207680e6f' then
    raise exception 'mcp-more-1: mcp_gate is not the single mcp-1a version (count %, md5 %) — stop, nothing was changed', v_n, coalesce(v_md5, '(none)');
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_manual_gate') then
    raise exception 'mcp-more-1: mcp_manual_gate already exists — stop, nothing was changed';
  end if;
end $$;

-- ═══ A) 문 ═══
create function public.mcp_manual_gate() returns boolean
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public.mcp_gate(null);
  return true;
end;
$$;
comment on function public.mcp_manual_gate() is 'mcp-more-1 판정 1211: Claude 커넥터 매뉴얼 도구(manual_search · manual_read)의 문 — EF ims-mcp 가 GitHub 원고를 읽기 전에 사용자 토큰으로 부른다 · 몸 = mcp_gate(null) 하나(활성 직원 + claude 열쇠 · 호출마다 · 921) · 늘 true(직원 id 를 돌려주지 않는다) · DB 는 아무것도 읽어 주지 않는다 · ims_connector 만 EXECUTE';

-- ═══ 권한 — ims_connector 만 ═══
revoke all on function public.mcp_manual_gate() from public, anon, authenticated, service_role, ims_connector;
grant execute on function public.mcp_manual_gate() to ims_connector;

-- ═══ 착지 검사 ═══
do $$
declare v text; v_n int;
begin
  select p.proacl::text || ' ' || p.prosecdef::text || p.provolatile::text || ' ' || p.proconfig::text || ' ' || pg_get_function_result(p.oid) into v from pg_proc p where p.oid = 'public.mcp_manual_gate()'::regprocedure;
  if v <> '{postgres=X/postgres,ims_connector=X/postgres} trues {"search_path=public, pg_temp"} boolean' then raise exception 'mcp-more-1 landing: gate %', v; end if;
  select p.proacl::text || ' ' || md5(p.prosrc) into v from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_gate';
  if v <> '{postgres=X/postgres} e50d34c953bd66513458353207680e6f' then raise exception 'mcp-more-1 landing: mcp_gate changed %', v; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'mcp\_%' and (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'));   -- mcp_ 만 본다 · 아래 ims_connector 목록도 그 역할에게 직접 준 것만(PUBLIC 으로 열린 다른 모듈 함수는 이 차수 밖)
  if v_n <> 0 then raise exception 'mcp-more-1 landing: PUBLIC EXECUTE on % mcp functions', v_n; end if;
  select string_agg(p.proname, ' ' order by p.proname) into v from pg_proc p where p.pronamespace = 'public'::regnamespace and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 'ims_connector'::regrole and a.privilege_type = 'EXECUTE');
  if v <> 'mcp_backorders mcp_customer mcp_manual_gate mcp_order mcp_po mcp_sales mcp_stock' then raise exception 'mcp-more-1 landing: ims_connector functions %', v; end if;
  select count(*) into v_n from information_schema.role_table_grants where grantee = 'ims_connector';
  if v_n <> 0 then raise exception 'mcp-more-1 landing: ims_connector table grants %', v_n; end if;
  raise notice 'mcp-more-1 landing OK — gate acl · definer · stable · boolean · mcp_gate same · mcp_ PUBLIC EXECUTE 0 · ims_connector functions 7 · tables 0';
end $$;
