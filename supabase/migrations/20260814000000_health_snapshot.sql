-- Health 자동 실행 이력 (2026-08-14)
--
-- wms_health_check() 실측 1,271ms · shared hit 70,550 (2026-08-14 explain analyze).
-- 종전에는 admin 부팅마다 refreshHealthBadge() 가 12검사 전체를 돌렸다 —
-- 부팅이 1.27초 느려지고, finalize_recon 이 closed 오더 전체를 스캔하므로
-- 오더가 쌓일수록 계속 느려진다.
-- 이제 pg_cron 이 1시간마다 wms_health_snapshot() 으로 결과를 이 테이블에 남기고,
-- 배지는 최신 1행만 읽는다 (Health 탭 loadHealth() 는 라이브 RPC 유지).
-- cron 등록은 마이그레이션이 아니라 supabase/ops/cron.sql 참조 (실서버 수동 등록).

create table wms_health_runs (
  id                  bigint generated always as identity primary key,
  ran_at              timestamptz not null default now(),
  crit_count          int not null,
  warn_count          int not null,
  -- fail_count > 0 인 critical/warn 검사만: [{check_key, category, fail_count, sample}]
  failures            jsonb not null,
  -- last_import 검사의 sample.minutes_ago (null = 오더 0건 — fail_count 는 리터럴 0이라 신호가 안 된다)
  last_import_minutes int
);

create index wms_health_runs_ran_at_idx on wms_health_runs (ran_at desc);

-- 기존 wms_ 테이블 컨벤션: RLS ON + auth_all (anon 거부 · authenticated 전체 허용)
alter table wms_health_runs enable row level security;
create policy auth_all on wms_health_runs
  for all to authenticated using (true) with check (true);

-- 스냅샷 1행 append + 자체 보존 정리.
-- 정리를 함수 안에서 하는 이유: 별도 정리 잡을 만들지 않는다 (wms_reap_stale_claims 패턴과 일관).
create or replace function wms_health_snapshot() returns void
language sql security definer
set search_path = public
as $$
  -- ⚠️ materialized 필수: 아래에서 r 을 집계(count filter)와 서브쿼리 양쪽에서 참조한다.
  -- CTE 가 inline 되면 wms_health_check()(실측 1,271ms)가 두 번 실행될 수 있다 — 2.5초.
  -- materialized 는 PG12+ 에서 1회 실행을 강제한다.
  with r as materialized (select * from wms_health_check())
  insert into wms_health_runs (crit_count, warn_count, failures, last_import_minutes)
  select
    count(*) filter (where category = 'critical' and fail_count > 0),
    count(*) filter (where category = 'warn'     and fail_count > 0),
    coalesce(jsonb_agg(jsonb_build_object(
        'check_key', check_key, 'category', category,
        'fail_count', fail_count, 'sample', sample))
      filter (where category <> 'info' and fail_count > 0), '[]'::jsonb),
    (select (sample->>'minutes_ago')::int from r where check_key = 'last_import')
  from r;

  delete from wms_health_runs where ran_at < now() - interval '90 days';
$$;

-- 호출자는 pg_cron(잡 소유자 postgres = 함수 소유자)뿐 — 프론트/anon 에 실행 권한을 주지 않는다.
-- ⚠️ PUBLIC 회수가 먼저다: Postgres 는 함수 EXECUTE 를 PUBLIC 에 기본 부여하므로
--    anon/authenticated 만 회수하면 PUBLIC 경유로 여전히 실행된다.
revoke execute on function public.wms_health_snapshot() from public;
revoke execute on function public.wms_health_snapshot() from anon;
revoke execute on function public.wms_health_snapshot() from authenticated;
