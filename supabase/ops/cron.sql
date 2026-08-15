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

-- 4) Cin7 상품 이미지 → 스냅샷 직결 (매일 1회) → Edge Function 'product-images'
--    (2026-08-14 — BQ CSV 이미지가 7주 묵었던 실사고의 재발 방지.
--     설계·원칙은 supabase/functions/product-images/index.ts 헤더 참조.)
--    ⚠️ 시각: pg_cron 은 UTC 기준이다(등록 후 `select * from cron.job;` 로 실측 확인 권장).
--       12:30 UTC = 토론토 여름(EDT) 8:30 / 겨울(EST) 7:30 — DST 로 계절마다 1시간 밀린다.
--       어느 계절에도 WmsSync(GAS, America/Toronto 6:30 ±15분 — 스냅샷 truncate+재적재)
--       **이후** · 창고 시작(9시) **전**이 되도록 고른 값. 재적재보다 먼저 돌면 그날
--       덮어쓴 이미지가 BQ 값으로 되돌아간 채 하루를 보낸다.
--    ⚠️⚠️ x-wms-cron-key 실제 값을 이 파일에 넣지 말 것 — 레포가 PUBLIC 이다.
--       (anon 키는 원래 공개라 커밋 OK 였지만 이 시크릿은 다르다.)
--       `supabase secrets set WMS_CRON_SECRET=...` 로 등록한 것과 같은 문자열을
--       실서버 대시보드 SQL Editor 에서 등록할 때만 채운다. 아래는 placeholder.
--    선행 조건: 20260814030000_image_sync_runs.sql push · product-images 배포 ·
--    WMS_CRON_SECRET secret 등록. (EF 는 secret 미설정이면 500 fail-closed.)
select cron.schedule(
  'wms-image-sync',
  '30 12 * * *',
  $job$
    select net.http_post(
      url     := 'https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/product-images',
      headers := jsonb_build_object(
        'Content-Type',   'application/json',
        'x-wms-cron-key', '<WMS_CRON_SECRET 실제 값으로 교체 — 이 파일에 커밋 금지>'
      )
    );
  $job$
);

-- 5) 위 4)의 재시도 슬롯 (1시간 뒤) — 첫 실행이 성공했으면 EF 쿨다운(20시간)이
--    자동으로 no-op(SKIPPED cooldown) 시키고, 실패(429 등)였으면 여기서 재시도된다.
--    등록 비용 0 으로 실패 모드만 줄이는 슬롯 (2026-08-14 설계 승인).
select cron.schedule(
  'wms-image-sync-retry',
  '30 13 * * *',
  $job$
    select net.http_post(
      url     := 'https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/product-images',
      headers := jsonb_build_object(
        'Content-Type',   'application/json',
        'x-wms-cron-key', '<WMS_CRON_SECRET 실제 값으로 교체 — 이 파일에 커밋 금지>'
      )
    );
  $job$
);
