-- Cin7 이미지 직결 동기화 — 실행 기록 + Health 검사 (2026-08-14)
--
-- 배경 (2026-08-14 실사고): WMS 상품 사진이 7주 묵어 있었다(GHO57212 미표시 보고).
-- BQ asung_product_images 가 Cin7 수동 export CSV 기반이라 사람이 3단계를 안 돌리면
-- 조용히 늙는다 — 뿌리는 "묵은 것을 아무도 몰랐다"이다. 새 EF `product-images` 가
-- Cin7 에서 대표 이미지를 받아 wms_sku_snapshot.image_url 을 매일 덮어쓴다
-- (BQ 경로는 이중 안전으로 유지 — EF 헤더 주석 참조).
--
-- 이 마이그레이션 2가지:
--  ① wms_image_sync_runs — EF 실행 기록. 테이블 하나가 세 역할을 한다:
--     관측(진단 jsonb) · Health 알림(아래 image_sync_stale) · EF 쿨다운 가드
--     (마지막 성공 20시간 이내면 재실행 거부 — 시크릿이 새도 증폭 차단).
--  ② wms_health_check() 에 검사 1개 추가 — image_sync_stale (warn · sort 120):
--     마지막 성공 실행이 48시간 초과 **또는 한 번도 없음**이면 fail.
--     ⚠️ "한 번도 없음"도 잡는 것이 의도다: push 후 첫 성공 실행까지 warn 1 이
--     떠 있게 된다. 조용히 두면 "cron 등록을 잊어도 영원히 조용" = CSV 7주 사고의
--     재판이라 이쪽을 택했다(2026-08-14 설계 승인). 배포를 끝내면(첫 성공) 사라진다.

-- ─────────────────────────────────────────────────────────
-- ① 실행 기록 테이블 (wms_health_runs 와 같은 컨벤션 — 20260814000000)
-- ─────────────────────────────────────────────────────────
create table wms_image_sync_runs (
  id          bigint generated always as identity primary key,
  started_at  timestamptz not null default now(),   -- EF 요청 시작(t0)
  finished_at timestamptz,
  ok          boolean not null,
  updated     int not null default 0,               -- 실제로 image_url 이 바뀐 행수 (diff 산출)
  error_note  text,                                 -- 실패 사유 (aborted:"time"/rate_limited/page_error/incomplete 등)
  -- EF 진단 응답 전문 (pages_scanned·list_total·matched·missing_in_snapshot 샘플 등).
  -- EF 로그는 휘발하므로 사후 조사는 이 컬럼으로만 가능 — wms_health_runs.failures 와 같은 판단.
  diag        jsonb
);

create index wms_image_sync_runs_started_at_idx on wms_image_sync_runs (started_at desc);

-- 기존 wms_ 테이블 컨벤션: RLS ON + auth_all (anon 거부 · authenticated 전체 허용).
-- 쓰기는 EF(service_role — RLS 우회, 서버사이드 정상 경로)만 한다.
alter table wms_image_sync_runs enable row level security;
create policy auth_all on wms_image_sync_runs
  for all to authenticated using (true) with check (true);

-- 보존 정리(90일)는 EF 가 run 기록 직후 best-effort DELETE 로 수행한다 —
-- wms_health_snapshot() 의 "쓰기 지점에서 정리, 별도 정리 잡 없음" 패턴과 동일.
-- (health 쪽은 쓰기 지점이 SQL 함수라 함수 안에서 했고, 여기는 쓰기 지점이 EF 다.)

-- ─────────────────────────────────────────────────────────
-- ② wms_health_check() 재작성 — 기존 12검사는 baseline 원문 그대로,
--    image_sync CTE + sort 120 행만 추가 (warn 마지막 110 뒤 · info 200 앞)
-- ─────────────────────────────────────────────────────────
-- ⚠️ create or replace 는 기존 ACL 을 보존한다 — 20260814010000 이 회수한
--    PUBLIC/anon EXECUTE 가 이 마이그레이션으로 되살아나지 않는다(그 파일 말미 주석의
--    "drop 후 재생성" 케이스가 아님). authenticated·service_role 실행 권한도 그대로.
CREATE OR REPLACE FUNCTION "public"."wms_health_check"() RETURNS TABLE("sort" integer, "check_key" "text", "category" "text", "title" "text", "hint" "text", "fail_count" bigint, "sample" "jsonb")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
with
bad_math as (
  select id, order_id, order_sku, ordered_qty, factor, required_base
  from wms_order_lines
  where required_base is distinct from ordered_qty * factor
),
factor_drift as (
  select ol.id, ol.order_sku, ol.factor as line_factor, s.factor as snapshot_factor
  from wms_order_lines ol
  join wms_sku_snapshot s on s.sku = ol.order_sku
  where ol.factor is distinct from s.factor
),
split_bad as (
  select ol.id, ol.order_id, o.order_number, ol.order_sku, ol.required_base,
         coalesce((select sum(ptl.assigned_base)
                     from wms_pick_task_lines ptl
                    where ptl.order_line_id = ol.id), 0) as assigned_sum
  from wms_order_lines ol
  join wms_orders o on o.id = ol.order_id
  where o.status in ('picking','packing','ready_to_close','closed')
    and exists (select 1 from wms_pick_tasks pt where pt.order_id = ol.order_id)
    and coalesce((select sum(ptl.assigned_base)
                    from wms_pick_task_lines ptl
                   where ptl.order_line_id = ol.id), 0)
        is distinct from ol.required_base
),
short_no_disc as (
  select ptl.id, ol.order_id, o.order_number, ol.order_sku,
         ptl.assigned_base, ptl.picked_base
  from wms_pick_task_lines ptl
  join wms_order_lines ol on ol.id = ptl.order_line_id
  join wms_orders o on o.id = ol.order_id
  where ptl.status = 'short'
    and not exists (
      select 1 from wms_discrepancies d
      where d.order_id = ol.order_id and d.sku = ol.order_sku
    )
),
pick_over as (
  select ptl.id, ptl.pick_task_id, ol.order_sku,
         ptl.assigned_base, ptl.picked_base
  from wms_pick_task_lines ptl
  join wms_order_lines ol on ol.id = ptl.order_line_id
  where ptl.picked_base > ptl.assigned_base
),
progress_leak as (
  select id, order_number, order_progress, status
  from wms_orders
  where order_progress is distinct from '2.Release to WMS'
    and status not in ('closed','voided')
),
dup_sale as (
  select cin7_sale_id, count(*) as cnt
  from wms_orders
  where cin7_sale_id is not null
  group by cin7_sale_id
  having count(*) > 1
),
finalize_recon as (
  select o.order_number, ol.order_sku, ol.required_base,
         coalesce(sum(ptl.picked_base), 0) as picked_base
  from wms_orders o
  join wms_order_lines ol on ol.order_id = o.id
  join wms_pick_task_lines ptl on ptl.order_line_id = ol.id
  where o.status = 'closed' and o.completion_type = 'clean'
  group by o.id, o.order_number, ol.order_sku, ol.required_base
  having coalesce(sum(ptl.picked_base), 0) is distinct from ol.required_base
),
orphan_pick as (
  select o.id, o.order_number, o.status, count(pt.id) as pick_tasks
  from wms_orders o
  join wms_pick_tasks pt on pt.order_id = o.id
  where o.status = 'pending'
  group by o.id, o.order_number, o.status
),
orphan_pack as (
  select pk.id as pack_task_id, pk.batch_label, o.order_number,
         pk.status as pack_status, pt.status as pick_status
  from wms_pack_tasks pk
  join wms_orders o on o.id = pk.order_id
  left join wms_pick_tasks pt on pt.id = pk.pick_task_id
  where pt.id is null                    -- pack with no paired pick batch at all
     or pt.status is distinct from 'completed'   -- or pick batch not finished yet
),
wave_state as (
  select w.id, w.label, w.status,
         count(pt.id) as member_batches,
         count(pt.id) filter (where pt.status = 'completed') as completed_batches
  from wms_waves w
  left join wms_pick_tasks pt on pt.wave_id = w.id
  group by w.id, w.label, w.status
  having count(pt.id) = 0
      or (w.status = 'completed'
          and count(pt.id) <> count(pt.id) filter (where pt.status = 'completed'))
      or (w.status <> 'completed'
          and count(pt.id) > 0
          and count(pt.id) = count(pt.id) filter (where pt.status = 'completed'))
),
image_sync as (
  -- product-images EF 의 마지막 성공 실행. max over 빈 테이블 = null 1행 —
  -- "한 번도 안 돌았다"도 아래 판정이 fail 로 잡는다(의도 — 파일 상단 주석).
  select max(started_at) as last_ok_at,
         round(extract(epoch from (now() - max(started_at))) / 3600)::int as hours_ago
  from wms_image_sync_runs
  where ok
),
last_import as (
  select max(imported_at) as last_at,
         round(extract(epoch from (now() - max(imported_at))) / 60)::int as minutes_ago
  from wms_orders
)
select 10, 'factor_math', 'critical', 'Factor arithmetic',
  'required_base must equal ordered_qty x factor. A row here means the base conversion was miscomputed at import.',
  (select count(*) from bad_math),
  (select jsonb_agg(t) from (select * from bad_math limit 8) t)
union all
select 20, 'factor_drift', 'warn', 'Line factor vs snapshot',
  'Order-line factor differs from the current product snapshot. Often just a snapshot updated after import, but verify it is not a bad lookup.',
  (select count(*) from factor_drift),
  (select jsonb_agg(t) from (select * from factor_drift limit 8) t)
union all
select 30, 'split_sum', 'critical', 'Split assignment sum',
  'For split orders the assigned base across all batches must equal the line required_base. A gap means a concurrent split lost or double-counted units.',
  (select count(*) from split_bad),
  (select jsonb_agg(t) from (select * from split_bad limit 8) t)
union all
select 40, 'short_no_disc', 'critical', 'Short pick without discrepancy',
  'A pick line marked short with no matching discrepancy row - the shortfall vanished silently. Match key: order_id + order_sku; verify if unsure.',
  (select count(*) from short_no_disc),
  (select jsonb_agg(t) from (select * from short_no_disc limit 8) t)
union all
select 50, 'pick_over', 'warn', 'Picked exceeds assigned',
  'Picked base is greater than assigned at the pick level. Over-quantity should surface at pack, not pick.',
  (select count(*) from pick_over),
  (select jsonb_agg(t) from (select * from pick_over limit 8) t)
union all
select 60, 'progress_leak', 'warn', 'Order progress leak',
  'Active orders whose order_progress is not "2.Release to WMS". Watch for "Backordered" (shared field in Cin7). May also mean the order changed in Cin7 after import (case C).',
  (select count(*) from progress_leak),
  (select jsonb_agg(t) from (select * from progress_leak limit 8) t)
union all
select 70, 'dup_sale', 'critical', 'Duplicate Cin7 sale id',
  'Same cin7_sale_id imported more than once. The unique constraint should make this impossible - a row here means dedup or the constraint failed.',
  (select count(*) from dup_sale),
  (select jsonb_agg(t) from (select * from dup_sale limit 8) t)
union all
select 80, 'finalize_recon', 'critical', 'Finalize reconciliation',
  'Clean-finalized orders where total picked base does not equal required_base. End-to-end check: a row means a factor/pick error slipped through as clean.',
  (select count(*) from finalize_recon),
  (select jsonb_agg(t) from (select * from finalize_recon limit 8) t)
union all
select 90, 'orphan_pick', 'warn', 'Orphaned pick tasks',
  'Orders back at pending (pre-split) that still have pick tasks - an Undo Split rollback that did not clean up.',
  (select count(*) from orphan_pick),
  (select jsonb_agg(t) from (select * from orphan_pick limit 8) t)
union all
select 100, 'orphan_pack', 'warn', 'Orphaned pack tasks',
  'A pack batch whose paired pick batch is missing or not completed. (An order can be picking overall while some of its batches pack - that is normal and no longer flagged.)',
  (select count(*) from orphan_pack),
  (select jsonb_agg(t) from (select * from orphan_pack limit 8) t)
union all
select 110, 'wave_state', 'warn', 'Wave consistency',
  'A wave with no member batches, a completed wave with unfinished batches, or a wave whose batches are all done but the wave never closed (an interrupted finish).',
  (select count(*) from wave_state),
  (select jsonb_agg(t) from (select * from wave_state limit 8) t)
union all
select 120, 'image_sync_stale', 'warn', 'Cin7 image sync stale',
  'Last successful product-images run is older than 48h, or it has never run. Product pictures on screens may be stale (this is how the 7-week CSV went unnoticed). Check pg_cron job wms-image-sync, the WMS_CRON_SECRET secret, and wms_image_sync_runs for the failing run''s error_note/diag.',
  (select (case when last_ok_at is null or last_ok_at < now() - interval '48 hours' then 1 else 0 end)::bigint from image_sync),
  (select jsonb_build_object('last_ok_at', last_ok_at, 'hours_ago', hours_ago) from image_sync)
union all
select 200, 'last_import', 'info', 'Last order imported',
  'Newest imported_at - the true signal that polling saved an order. A long gap is normal if no new orders qualified.',
  0::bigint,
  (select jsonb_build_object('last_at', last_at, 'minutes_ago', minutes_ago) from last_import)
order by 1;
$$;
