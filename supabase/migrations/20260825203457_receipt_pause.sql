-- 리시빙 Hold·partial 구간 기록 (2026-08-25) — 픽·팩과 같은 자의 리시빙 판
--
-- 배경 [실측 2026-08-25 · PO-01151]: Receiving 표의 시간 자는 workMinutes(created→completed)인데
-- Hold·선적 대기 공제가 없고, Throughput 쪽 라인 시각(last_received_at)은 저장 큐 flush 에 몰려
-- (20줄이 3.2초 — 실제 80분) 사실상 전송 시각이다. 새 자 = (completed_at − created_at) −
-- Hold·partial 구간 합 (⚠️ 순수 벽시계 — workMinutes 와 섞으면 주말·밤이 이중 공제된다).
--
-- 설계 (2026-08-25 Caleb 승인):
--  · wms_task_holds 재사용 — task_kind + 'receipt' · source + 'partial'.
--    partial(= 이 선적분 완료·나머지 선적 대기 — Apply 게이트가 completed 만 허용하고
--    cin7_purchase_id 유니크라 PO 당 receipt 1건: 다회 선적은 같은 receipt 에 누적 후 Apply 1회)
--    은 hold 와 원인이 다른 「멈춤」이라 source 로 가른다(화면 구분은 데이터가 쌓인 뒤 별건).
--  · 기록 = RPC wms_pause_receipt(플립+insert 한 트랜잭션 — 픽·팩 Hold RPC 와 동형).
--    CAS: in_progress 일 때만 플립(0행 = 무기록 — 이중 pause 차단 · completed/externally_applied 보호).
--  · 닫기 = 기존 wms_resume_hold('receipt', id) 재사용 — 재개(receiver openReceipt)와
--    ⚠️ admin Reopen(DB 직접 플립이라 receiver 분기 미발동 — 양쪽 호출) 그리고
--    ⚠️ 완료 시에도 호출(리시빙 고유: A 가 Hold 한 문서를 동시 작업자 B 가 그대로 완료할 수 있다
--    — finishReceipt 에 status 조건이 없다. hold 중 완료 = hold 종점이 완료 시각).
--  · ⚠️ 자동 Hold(wms_auto_hold)는 리시빙에 적용하지 않는다 — 점유 모델 부재(assigned_to 없음 ·
--    동시 다인 · held 는 잠금이 아님 — reaper 가 리시빙을 못 다뤘던 것과 같은 뿌리).
--    잔여 위험: Hold 를 안 누르고 열어둔 채 다음날 완료하면 그 receipt 의 새 자는 과대다 —
--    수동 Hold·partial 에 의존한다(픽·팩도 자동 Hold 이전엔 같았다).
--  · 문서 단위 지표다 — 여러 명이 같은 receipt 를 동시에 열므로 「사람의 시간」이 아니다
--    (화면 각주 "per receipt, not per worker").
--  · 과거는 계산 불가(hold 시각이 없었다) — 백필 금지. 신뢰 시점은 배포 후 첫 행 실측으로
--    스킬 규칙 37 계열에 기입(HOLD_TRACKING_SINCE 방식 — 추정 금지).
--
-- 이 파일: ① CHECK 확장 2건 ② wms_pause_receipt 신설 ③ wms_health_check 재정의 —
-- hold_leak 에 wms_receipts 조인 + receipt 분기(정상 열림 = held/partial · 삭제된 receipt 는
-- 픽·팩의 rollback/void 관례대로 안 잡음 · 이중 open 은 kind 무관 잡음). 함수 원문 기반 =
-- 20260824192416(재정의 전수 grep 으로 최신 확인 — 자르지 않음). 변경은 hold_leak CTE 의
-- select 1줄·조인 1줄·where 분기·hint 문구뿐.

-- ─────────────────────────────────────────────────────────
-- 1) CHECK 확장 — task_kind + 'receipt' · source + 'partial'
-- ─────────────────────────────────────────────────────────
alter table wms_task_holds drop constraint wms_task_holds_task_kind_check;
alter table wms_task_holds add constraint wms_task_holds_task_kind_check
  check (task_kind in ('pick','pack','wave','receipt'));
alter table wms_task_holds drop constraint wms_task_holds_source_check;
alter table wms_task_holds add constraint wms_task_holds_source_check
  check (source in ('manual','auto','partial'));   -- partial = 선적 대기 (receipt 전용)

-- ─────────────────────────────────────────────────────────
-- 2) wms_pause_receipt — 리시빙 Hold/partial (플립 + 이력, 한 트랜잭션)
-- ─────────────────────────────────────────────────────────
create or replace function public.wms_pause_receipt(
  p_receipt_id bigint,
  p_reason     text        -- 'held' | 'partial' (receipt.status 로 그대로 들어간다)
) returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_worker  text;
  v_flipped bigint;
begin
  if p_reason not in ('held', 'partial') then
    raise exception 'p_reason must be held or partial - nothing was saved';
  end if;
  select s.name into v_worker from wms_staff s where s.email = auth.email();
  if v_worker is null then
    raise exception 'No staff record for this login (%) - nothing was saved', coalesce(auth.email(), 'no email');
  end if;

  -- CAS: in_progress 일 때만 (0행 = 무기록 — 이중 pause·completed/externally_applied 보호.
  -- 리시빙은 소유자가 없어 assigned_to 조건이 없다 — 문서 전역 상태 플립)
  update wms_receipts
     set status = p_reason, updated_at = now()
   where id = p_receipt_id and status = 'in_progress'
  returning id into v_flipped;
  if v_flipped is null then
    return jsonb_build_object('paused', false, 'worker', v_worker);
  end if;

  -- 이력 — worker = 누른 사람(서버 유도). 구간의 의미는 「문서의 멈춤」이지 그 사람의 시간이 아니다.
  insert into wms_task_holds (task_kind, task_id, worker, source)
  values ('receipt', p_receipt_id, v_worker, case when p_reason = 'partial' then 'partial' else 'manual' end);

  return jsonb_build_object('paused', true, 'worker', v_worker, 'reason', p_reason);
end
$$;

revoke all on function public.wms_pause_receipt(bigint, text) from public;
revoke all on function public.wms_pause_receipt(bigint, text) from anon;
grant execute on function public.wms_pause_receipt(bigint, text) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────
-- 3) wms_health_check 재정의 — hold_leak 에 receipt 분기 (헤더 참조)
-- ─────────────────────────────────────────────────────────
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
  -- "한 번도 안 돌았다"도 아래 판정이 fail 로 잡는다(의도 — 20260814030000 상단 주석).
  select max(started_at) as last_ok_at,
         round(extract(epoch from (now() - max(started_at))) / 3600)::int as hours_ago
  from wms_image_sync_runs
  where ok
),
hold_leak as (
  select h.id, h.task_kind, h.task_id, h.worker, h.held_at,
         coalesce(p.status, k.status, w.status, rc.status) as task_status,
         coalesce(p.held_by, k.held_by, w.held_by) as task_held_by,
         h.rn as open_rank
  from (select th.*, row_number() over (partition by th.task_kind, th.task_id
                                        order by th.held_at desc) as rn
          from wms_task_holds th where th.resumed_at is null) h
  left join wms_pick_tasks p on h.task_kind = 'pick' and p.id = h.task_id
  left join wms_pack_tasks k on h.task_kind = 'pack' and k.id = h.task_id
  left join wms_waves      w on h.task_kind = 'wave' and w.id = h.task_id
  left join wms_receipts   rc on h.task_kind = 'receipt' and rc.id = h.task_id
  where h.rn > 1   -- same task holds two open rows - the fingerprint of a lost resume close
     -- receipt kind (2026-08-25 · 20260825203457): open row is normal only while the receipt is
     -- held/partial. Deleted receipts (admin delete path exists) = intended, not flagged - same
     -- convention as rollback/void for pick/pack/wave.
     or (h.task_kind = 'receipt' and rc.id is not null and rc.status not in ('held', 'partial'))
     or (h.task_kind <> 'receipt' and coalesce(p.id, k.id, w.id) is not null              -- deleted task (rollback/void) = intended, not flagged
         and not (coalesce(p.status, k.status, w.status) = 'pending'
                  and coalesce(p.held_by, k.held_by, w.held_by) is not null))
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
select 130, 'hold_leak', 'warn', 'Open hold vs task state',
  'An open hold row (resumed_at null) whose task is not pending+held (pick/pack/wave) or whose receipt is not held/partial - the resume close was lost, so its hold time will silently not be subtracted. Deleted tasks/receipts are intentionally not flagged; two open rows on one task always are.',
  (select count(*) from hold_leak),
  (select jsonb_agg(t) from (select * from hold_leak limit 8) t)
union all
select 200, 'last_import', 'info', 'Last order imported',
  'Newest imported_at - the true signal that polling saved an order. A long gap is normal if no new orders qualified.',
  0::bigint,
  (select jsonb_build_object('last_at', last_at, 'minutes_ago', minutes_ago) from last_import)
order by 1;
$$;
