-- pg_cron 스케줄 기록 (2026-07-26)
--
-- ⚠️ 이 파일은 마이그레이션이 아니다. db push 로 적용되지 않는다.
--    로컬 테스트 DB에도 pg_cron 이 있어서, 마이그레이션에 넣으면
--    로컬에서 db reset 할 때마다 실서버 Edge Function 을 호출한다.
--
-- 실서버에는 이미 등록되어 돌고 있다. 이 파일은 재해복구용 기록.
-- 적용이 필요하면 실서버 대시보드 SQL Editor 에서 수동 실행.
--
-- 확인: select jobname, schedule, active from cron.job order by jobid;

-- 1) Cin7 주문 폴링 (5분마다) → Edge Function 'hello'
--    참고: Authorization 에 'Bearer ' 접두어가 없다. hello 가
--    verify_jwt=false 라 현재는 동작한다. 나중에 verify_jwt 를
--    켜면 'Bearer ' 를 붙여야 한다.
select cron.schedule(
  'wms-poll-orders',
  '*/5 * * * *',
  $job$
    select net.http_post(
      url     := 'https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/hello?commit=1',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdmdHBjbmt4YmRqenpmdnp3Y2ZsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQzOTA1MjYsImV4cCI6MjA5OTk2NjUyNn0.eaTHZbcvv2NhefRcYjMNKF-3BrNJ9qFt1Yyn-mNSyKk'
      )
    );
  $job$
);

-- 2) 유령 claim 정리 (2분마다)
select cron.schedule(
  'wms-reap-stale-claims',
  '*/2 * * * *',
  $job$ select wms_reap_stale_claims() $job$
);

-- 3) Health 스냅샷 (1시간마다 — 사용자 결정 2026-08-14)
--    wms_health_check() 12검사를 돌려 wms_health_runs 에 1행 append.
--    보존 정리(90일)는 함수 안에서 함께 수행 — 별도 정리 잡 없음.
--    admin 배지는 이 테이블의 최신 1행을 읽고, 3시간+ 공백이면 회색 "?" 로
--    "검사가 안 돌고 있다"를 표시한다 — 이 잡이 죽으면 배지가 그걸 알린다.
--    선행 조건: 20260814000000_health_snapshot.sql 마이그레이션이 push 되어 있을 것.
select cron.schedule(
  'wms-health-snapshot',
  '0 * * * *',
  $job$ select wms_health_snapshot() $job$
);
