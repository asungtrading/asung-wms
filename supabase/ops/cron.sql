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
--    wms_health_check() 검사 전부(2026-08-24 현재 13검사+info — schema.md 「wms_health_check()」이
--    정본, 여기 수를 고정 표기하지 않는다)를 돌려 wms_health_runs 에 1행 append.
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
--    ⚠️⚠️ x-wms-cron-key 실제 값을 이 파일에 넣지 말 것 — 레포 공개 여부와 무관한 금지다.
--       (anon 키는 원래 공개라 커밋 OK 였지만 이 시크릿은 다르다.)
--       ⚠️ 레포는 2026-08-19 부터 private 이지만 금지는 그대로다: git 히스토리는 영구 ·
--       발행 Pages 사이트는 private 레포여도 공개 · private = "접근 권한자가 본다".
--       근거 정본은 asung-wms 스킬 「상품 이미지 파이프라인」 절의 시크릿 위치 규칙.
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

-- ============================================================
-- ⑤ 재고 원장 수집 (2026-08-21 등록 · jobid 6~11) → Edge Function 'inv-collect'
--   설계 정본: docs/design/ledger-design.md 4부 「⑤ 쓰기 가동」
--   경위 기록: docs/sessions/2026-08-20-ledger-go-live.md
--
-- ⚠️⚠️ **소스별로 6잡으로 나눴다** — TIME_BUDGET_MS=120초 안에 6종을 다 돌 수 없다.
--    [실측 2026-08-19] 첫 소스(adjustment, 5,009행)가 예산을 거의 소진 → transfer 0행
--    capped:"time" → 나머지 4종 aborted: "time budget exhausted before this source".
--    ⇒ 한 회차에 전 소스를 돌린다는 전제 자체를 버렸다. only= 로 하나씩 돈다.
--
-- ⚠️⚠️ **분(minute)을 어긋나게 배치했다** — 위 1) 'wms-poll-orders'(*/5)와 **같은 WMS 키를
--    공유**하므로 Cin7 한도(60콜/60초 · 애플리케이션 키 단위)를 나눠 쓴다. 같은 분에 겹치면
--    양쪽이 429 를 맞는다. hello 는 0·5·10…, 원장은 2·4·8·11·13·16 로 흩어 놨다.
--    ⚠️ 여기에 잡을 더 붙일 때도 **분이 겹치지 않는지 먼저 볼 것 — hello 와만이 아니라
--      원장 잡끼리도.** 아래 「purchase 스케줄 정정」이 정확히 그것을 놓쳐서 생긴 일이다.
--
-- ⚠️ **[2026-08-21 정정] purchase 스케줄 — 최초 등록 '7-52/15' → '8-53/15'.**
--    최초 등록값 7·22·37·52 는 **transfer('2-57/5' = 2·7·12·…·57)의 부분집합**이라 4회 실행이
--    전부 동시였다. 둘 다 inv-collect 이고 같은 WMS 키라 각각 최대 40콜×1,200ms 면
--    합산 분당 ~100콜 = 한도 60의 1.7배(드러나는 신호는 rate_limited 하나다).
--    실서버에서 cron.alter_job 으로 변경 완료(jobid 8 확인) — 아래 8) 은 그 값 그대로다.
--    📌 **교훈: hello 와의 겹침만 보고 원장 잡끼리를 안 봤다** — 분 집합을 전수 계산할 것.
--       잡이 늘면 확인해야 하는 쌍은 제곱으로 는다. 눈으로 세지 말 것.
--    현재 겹침 0 (전수 계산 확인):
--      hello 0·5·10…55 / transfer 2·7·12…57 / sale 4·9·14…59 /
--      purchase 8·23·38·53 / adjustment 11 / assembly 13 / creditnote 16
--
-- ⚠️⚠️ **URL 의 since=2026-08-20 은 빠지면 안 된다** — 이벤트 날짜 필터이고, 기초 스냅샷
--    (snapshot_key 2026-08-20-initial · taken_at 2026-08-20T23:42:47.855Z)의 경계 방어다.
--    빠지면 스냅샷에 이미 녹아 있는 과거 사건이 원장에 또 더해져 **조용히 부푼다.**
--    코드는 occurred_on > since (엄격히 큼)이라 8/20 전체가 제외된다 — 그날 낮 사건은
--    스냅샷에 포함돼 있고 19:42 이후에는 창고가 멈춰 사건이 없다. since=2026-08-19 로 하면
--    8/20 낮이 이중 계상된다.
--    📌 **스냅샷을 다시 찍으면 아래 6줄의 since 를 손으로 갱신할 것** (설계 4부 「쓰기를 켜기
--    전에 결정해야 하는 것」 2번 — 테이블 영속화 대신 cron URL 을 고른 대가다).
--    ⚠️ since 와 from_since 는 다른 것이다 — from_since 는 갱신 커서의 씨앗이고, 커서가
--    inv_sync_state 에 이미 seed 돼 있으므로 여기에는 넣지 않는다(넣어도 state 가 우선).
--
-- ⚠️⚠️ x-wms-cron-key 실제 값을 이 파일에 넣지 말 것 — 위 4)·5)와 같은 관례.
--    (git 히스토리는 영구 · 발행 Pages 사이트는 private 레포여도 공개 · private =
--     "접근 권한자가 본다". 근거 정본은 asung-wms 스킬의 시크릿 위치 규칙.)
--    inv-collect 는 product-images·inv-snapshot 과 **같은 WMS_CRON_SECRET** 을 쓴다.
--    아래는 placeholder — 대시보드 SQL Editor 에서 등록할 때만 채운다.
--
-- 선행 조건: 20260816000000_inv_ledger_tables.sql + 20260819000000_inv_conflicts.sql push ·
--   inv-collect 배포(@2026-08-19.1 이상) · WMS_CRON_SECRET secret 등록 ·
--   ⚠️ **inv_sync_state 커서 seed 완료**(전량 축 3종: transfer=TR-01327 · adjustment=ST-00646 ·
--   assembly=FG-00128 / 증분 축 3종은 스냅샷 taken_at). seed 없이 돌면 매 회차 TR-00001 부터
--   재처리한다(warnings: "NO FLOOR - scanning from the very first document").
--
-- 📌 **검증은 결과물로만 한다** — cron.job_run_details 의 succeeded 는 아무것도 보장하지 않는다
--    (2026-08-19 실측 — HTTP 요청을 띄운 것까지만 본다). 유일한 증거:
--      select source_key, last_cursor, last_run_at, note from inv_sync_state order by source_key;
--    → last_run_at 갱신 + last_cursor 전진. 그리고 select count(*) from inv_ledger;
-- 📌 placeholder·since 잔존 확인 (값을 노출하지 않는 방식):
--      select jobname,
--             command like '%SECRET%'           as still_placeholder,
--             command like '%since=2026-08-20%' as has_since
--      from cron.job where jobname like 'inv-collect%';
-- ============================================================

-- 6) 창고이동 (5분 주기 · 2·7·12…분)
--    ⚠️ 가장 무거운 소스 — DepartureDate·CompletionDate 두 날짜를 봐야 해서 목록만으로
--    판정이 안 되고 상세 캡 40에 걸린다(가동 첫 회차 detail_capped_remaining 1,787).
--    seed 직후에는 밀린 것을 소화하는 구간이 있다 — 5분 주기가 그 때문이다.
select cron.schedule(
  'inv-collect-transfer',
  '2-57/5 * * * *',
  $job$
    select net.http_post(
      url     := 'https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/inv-collect?only=transfer&since=2026-08-20&commit=1',
      headers := jsonb_build_object(
        'Content-Type',   'application/json',
        'x-wms-cron-key', '<WMS_CRON_SECRET 실제 값으로 교체 — 이 파일에 커밋 금지>'
      )
    );
  $job$
);

-- 7) 판매 출고 (5분 주기 · 4·9·14…분)
--    ⚠️ 후보가 캡 40의 3.6배(하루치 145 — 2026-08-19 실측)라 자주 도는 것이 답이다.
--    해결은 캡 상향이 아니다: 1,200ms × 40 = 48초로 이미 60초 창의 80% 를 쓴다.
select cron.schedule(
  'inv-collect-sale',
  '4-59/5 * * * *',
  $job$
    select net.http_post(
      url     := 'https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/inv-collect?only=sale&since=2026-08-20&commit=1',
      headers := jsonb_build_object(
        'Content-Type',   'application/json',
        'x-wms-cron-key', '<WMS_CRON_SECRET 실제 값으로 교체 — 이 파일에 커밋 금지>'
      )
    );
  $job$
);

-- 8) 발주 입고 (15분 주기 · 8·23·38·53분)
--    ⚠️ 최초 등록은 '7-52/15'(7·22·37·52) 였고 transfer 와 매 회 겹쳤다 —
--    2026-08-21 alter_job 으로 정정. 경위는 위 헤더 「purchase 스케줄」 절.
select cron.schedule(
  'inv-collect-purchase',
  '8-53/15 * * * *',
  $job$
    select net.http_post(
      url     := 'https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/inv-collect?only=purchase&since=2026-08-20&commit=1',
      headers := jsonb_build_object(
        'Content-Type',   'application/json',
        'x-wms-cron-key', '<WMS_CRON_SECRET 실제 값으로 교체 — 이 파일에 커밋 금지>'
      )
    );
  $job$
);

-- 9) 재고 조정 (매시 11분)
--    📌 무겁지 않다 — skip_since 판정이 목록 레벨에서 되므로 상세를 한 번도 안 부른다
--    (가동 첫 회차: 후보 586건이 detail_fetched 0 으로 한 회차에 끝났다).
select cron.schedule(
  'inv-collect-adjustment',
  '11 * * * *',
  $job$
    select net.http_post(
      url     := 'https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/inv-collect?only=adjustment&since=2026-08-20&commit=1',
      headers := jsonb_build_object(
        'Content-Type',   'application/json',
        'x-wms-cron-key', '<WMS_CRON_SECRET 실제 값으로 교체 — 이 파일에 커밋 금지>'
      )
    );
  $job$
);

-- 10) 조립 (매시 13분) — 전체 120건 · 대부분 VOIDED
select cron.schedule(
  'inv-collect-assembly',
  '13 * * * *',
  $job$
    select net.http_post(
      url     := 'https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/inv-collect?only=assembly&since=2026-08-20&commit=1',
      headers := jsonb_build_object(
        'Content-Type',   'application/json',
        'x-wms-cron-key', '<WMS_CRON_SECRET 실제 값으로 교체 — 이 파일에 커밋 금지>'
      )
    );
  $job$
);

-- 11) 반품 입고 (매시 16분) — [실측] 하루 4건. 드물어서 자주 돌 이유가 없다.
select cron.schedule(
  'inv-collect-creditnote',
  '16 * * * *',
  $job$
    select net.http_post(
      url     := 'https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/inv-collect?only=creditnote&since=2026-08-20&commit=1',
      headers := jsonb_build_object(
        'Content-Type',   'application/json',
        'x-wms-cron-key', '<WMS_CRON_SECRET 실제 값으로 교체 — 이 파일에 커밋 금지>'
      )
    );
  $job$
);

-- ══════════════════════════════════════════════════════════════════════════════
-- ⑥ shadow 대조 + 비재고 캐시 (2026-08-24 · jobid 12·13·14)
--
-- ⚠️ 분 집합 전수 (2026-08-24 · Cin7 콜을 쓰는 잡 전부 — 겹침 0):
--     hello(wms-poll-orders)   0·5·10·15·20·25·30·35·40·45·50·55   (*/5)
--     transfer                 2·7·12·17·22·27·32·37·42·47·52·57   (2-57/5)
--     sale                     4·9·14·19·24·29·34·39·44·49·54·59   (4-59/5)
--     purchase                 8·23·38·53                          (8-53/15)
--     adjustment               11        assembly 13       creditnote 16
--     snapshot(잡12) 21        sku-types(잡14) 26        compare(잡13) 36 ← DB 전용
--   ⇒ 사용 중 = mod5∈{0,2,4} 전체 + {8,11,13,16,21,23,26,36,38,53}
--     남은 빈 분 = {1,3,6,18,28,31,33,41,43,46,48,51,56,58}  ← 다음 잡은 여기서 고른다
--   ⚠️ 잡이 늘 때마다 **눈으로 세지 말고 다시 전수 계산할 것**(2026-08-21 purchase 겹침 교훈:
--     7·22·37·52 가 transfer 의 부분집합이라 4회가 전부 동시 실행 = 분당 ~100콜).
--   📌 DB 전용 잡(reaper */2 · health 0분 · compare 36분)은 Cin7 한도와 무관해 이 집합 밖이다.
--
-- ⚠️ **등록 실물은 화면이 아니라 cron.job 으로 확인한다** — 아래 시각(03:xx UTC)은 이 파일의
--   설계값이다. 실제 등록값 확인: select jobid, jobname, schedule, active from cron.job order by jobid;
-- ══════════════════════════════════════════════════════════════════════════════

-- 12) ⑥ shadow 대조 — Cin7 현재고 스냅샷 (매일 03:21 UTC) → Edge Function 'inv-snapshot'
--     ⚠️ 등록 전에 첫 실행을 손으로 확인할 것(⑤ 가동과 같은 순서):
--       curl -s "https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/inv-snapshot?key=auto-compare" \
--         -H "x-wms-cron-key: $S" | jq .    # → wrote ≈ 13,800 · aborted null
--       그 뒤 psql: select inv_compare_run(to_char(now(),'YYYY-MM-DD')||'-compare');
--     시각 근거: 03:21 UTC = 토론토 23:21 EDT / 에드먼튼 21:21 MDT — 두 창고 마감 후 ·
--       GAS BinStock(05:00 GAS 시간)·WmsSync(6:30) 전. 겨울(EST/MST)도 마감 후라 DST 무해.
--     ⚠️ 분 21 = 빈 분(2026-08-24 전수 계산 — mod5∈{1,3} 중 8·11·13·16·23·38·53 제외:
--       {1,3,6,18,21,26,28,31,33,36,41,43,46,48,51,56,58}). 실행 43초라 그 분 안에서 끝난다.
--       잡이 늘면 이 집합을 다시 전수 계산할 것(2026-08-21 purchase 겹침 교훈 — 눈으로 세지 말 것).
--     key=auto-compare → EF 가 'YYYY-MM-DD-compare' 생성(-initial 은 여전히 수동 명시만).
select cron.schedule(
  'inv-snapshot-compare',
  '21 3 * * *',
  $job$
    select net.http_get(
      url     := 'https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/inv-snapshot?key=auto-compare',
      headers := jsonb_build_object(
        'x-wms-cron-key', '<WMS_CRON_SECRET 실제 값으로 교체 — 이 파일에 커밋 금지>'
      )
    );
  $job$
);

-- 13) ⑥ shadow 대조 — 대조 RPC (매일 03:36 UTC · 잡 12 의 15분 뒤 — 스냅샷 43초 대비 여유)
--     DB 전용(Cin7 콜 0) — 분 충돌 무관하나 빈 분 36 으로 관례 유지.
--     스냅샷이 실패한 날은 RPC 가드가 "no snapshot rows" 기록만 남긴다(오탐 0 — all-or-nothing 의 짝).
--     결과 확인: select * from inv_compare_runs order by id desc limit 3;
--                select * from inv_compare where checked_on = current_date order by abs(diff) desc;
select cron.schedule(
  'inv-compare-run',
  '36 3 * * *',
  $job$
    select inv_compare_run(to_char(now(), 'YYYY-MM-DD') || '-compare');
  $job$
);

-- 14) 비재고 SKU 캐시 갱신 (매일 03:26 UTC) → Edge Function 'inv-sku-types'
--     배경 [FINAL-SALE 실사고 2026-08-24]: Type=Non-inventory 판매를 수집이 재고 사건으로 잡음.
--     /product 전량(15~30콜)에서 Type≠Stock SKU 를 inv_sku_types 로 — inv-collect 게이트가 읽는다.
--     ⚠️ 분 26 = 빈 분(2026-08-24 전수 재계산 — 빈 분 집합에서 21(잡12)·36(잡13)을 추가 제외:
--       {1,3,6,18,26,28,31,33,41,43,46,48,51,56,58}). 30콜 × 400ms ≈ 22초 — 그 분 안에서 끝난다.
--       03:26 은 잡 12(03:21 — 43초 종료) 뒤·잡 13(03:36) 앞 — 새벽 원장 작업 몰아두기.
--     ⚠️ 등록 전에 첫 실행을 손으로(dry → 실행 → 테이블 5행 확인):
--       curl -s ".../functions/v1/inv-sku-types?dry=1" -H "x-wms-cron-key: $S" | jq '.non_stock'
select cron.schedule(
  'inv-sku-types',
  '26 3 * * *',
  $job$
    select net.http_get(
      url     := 'https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1/inv-sku-types',
      headers := jsonb_build_object(
        'x-wms-cron-key', '<WMS_CRON_SECRET 실제 값으로 교체 — 이 파일에 커밋 금지>'
      )
    );
  $job$
);
