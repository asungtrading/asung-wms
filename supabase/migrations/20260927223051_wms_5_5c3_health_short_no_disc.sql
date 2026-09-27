-- ⑤-5c3 wms_health_check 재발행 — short_no_disc 가 재고 부족 신고(wms_reports stock_short)도 본다 (2026-09-27 UTC · 토론토 2026-09-27 저녁)
-- 정본 so-module §24(24-b 표 갈래 · 24-h 판정 20 · 24-g 판정 13) · 지시서 ~/asung/prompts/wms-5-5c3.md · 시험 적용 + 검증 ~/asung/prompts/wms-5-5c3-verify.sql(-v mig)
-- 대상: [테스트 · Asung-IMS] 만 — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음)
-- ⛔⛔ 절대 조건(Caleb 2026-09-26): 운영 WMS(asung-WMS · wms.asung.ca)는 어떤 경우에도 멈추면 안 된다.
--     첫 문장 = 운영 가드(원본 supabase/ops/guard-test-only.sql 의 글자를 그대로 복사 · 검증 G0 이 임시 파일 diff 로 같음을 잰다).
--     흔적 셋 중 하나라도 있으면 WM501 로 멈춘다(OR · fail-closed): cron.job 에 wms-poll-orders/wms-auto-hold · inv_config.db_role <> 'test' · wms_health_runs 행 > 0
-- 하는 일: public.wms_health_check() 를 마지막 정의(20260927214447:487~684)에서 create or replace — 바뀌는 것은 short_no_disc 한 검사뿐
--   왜: 운영에서는 stock_short 신고가 같은 wms_discrepancies 표에 있어 「모자란 줄 ↔ 설명 행」 짝이 한 표 안이었다 · IMS 는 24-b 로 둘로 갈렸다(실수 = wms_worker_mistakes · 신고 = wms_reports stock_short)
--       ⑤-5c1 은 실수 표만 봐서 SO-25003(11/12 픽 · 「Not enough stock」 선언 · 실수 행 없음 — 규칙 41 · 판정 20 「선언한 줄은 실수에서 제외」)이 걸렸다(검사 버그 · 2026-09-27 Caleb 화면 시험)
--   뜻: 모자란 줄은 「같은 오더 · 같은 SKU 에 (voided 아닌) short_pick/resolved_pack_recovery 실수 행」 또는 「같은 오더 · 같은 SKU 의 wms_reports kind stock_short(resolved 무관)」 가 있으면 걸지 않는다 · 짝 열쇠 = 원본 그대로 order + SKU(wms_reports.order_id uuid · sku text)
--   무변: 시그니처 · stable · security definer · search_path · 첫 줄 문 ims_can_view(wms_manage) · grant · comment · 다른 열둘 검사(⑤-5c3 지시서 B 훑기 — 둘로 갈린 표 빠짐은 이 검사 하나)
-- ⚠️ 번호(SO · PO · RCV · 인보이스 · 크레딧)를 이 파일이 당기지 않는다 · 표를 만들거나 고치지 않는다

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

-- ═══ wms_health_check 재발행 — 원본 20260927214447:487~684 그대로 · 바뀐 줄 = create or replace · short_nd 의 not exists 한 줄 · hint 한 줄 ═══
create or replace function public.wms_health_check() returns table(sort integer, check_key text, category text, title text, hint text, fail_count bigint, sample jsonb)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  c_stale constant interval := interval '24 hours';   -- packed_not_finalized · long_hold
  c_claim constant interval := interval '8 hours';    -- stale_claim(근무 하루)
begin
  if not public.ims_can_view('wms_manage') then                        -- ⭐ 첫 줄 문
    raise exception 'You cannot view WMS health — this needs the wms_manage screen — ask an admin';
  end if;
  return query
  with
  line_split as (
    select s.so_number, l.line_no, l.sku,
           (l.qty_ordered - l.qty_removed) * l.pack_factor as need_ea,
           sum(pl.assigned_base) as assigned_ea
      from public.so s
      join public.so_line l on l.so_id = s.id
      join public.wms_pick_task_lines pl on pl.order_line_id = l.id
      join public.wms_pick_tasks t on t.id = pl.pick_task_id and t.order_id = s.id
     where s.status in ('picking', 'packed')
     group by s.so_number, l.line_no, l.sku, l.qty_ordered, l.qty_removed, l.pack_factor
    having sum(pl.assigned_base) is distinct from (l.qty_ordered - l.qty_removed) * l.pack_factor
  ),
  short_nd as (
    select s.so_number, t.batch_label, l.sku, pl.assigned_base, pl.picked_base
      from public.wms_pick_task_lines pl
      join public.wms_pick_tasks t on t.id = pl.pick_task_id
      join public.so s on s.id = t.order_id
      join public.so_line l on l.id = pl.order_line_id
     where pl.status = 'short'
       and not exists (select 1 from public.wms_worker_mistakes m
                        where m.order_id = s.id and m.sku = l.sku and m.reason in ('short_pick', 'resolved_pack_recovery') and m.voided_at is null)
       and not exists (select 1 from public.wms_reports r                 -- ⑤-5c3: 「Not enough stock」 신고(판정 20 · 24-b 로 갈린 쪽)도 모자람을 설명한다 · resolved 무관
                        where r.order_id = s.id and r.sku = l.sku and r.kind = 'stock_short')
  ),
  pick_over as (
    select s.so_number, t.batch_label, l.sku, pl.assigned_base, pl.picked_base
      from public.wms_pick_task_lines pl
      join public.wms_pick_tasks t on t.id = pl.pick_task_id
      join public.so s on s.id = t.order_id
      join public.so_line l on l.id = pl.order_line_id
     where pl.picked_base > pl.assigned_base
  ),
  fin_pair as (
    select s.so_number, s.status, (f.order_id is not null) as has_finalize_row, f.finalized_at
      from public.so s
      left join public.wms_order_finalize f on f.order_id = s.id
     where (s.status = 'packed' and f.order_id is null)
        or (f.order_id is not null and s.status in ('draft', 'confirmed', 'at_wms', 'picking', 'cancelled'))
  ),
  orphan_task as (
    select s.so_number, s.status, count(t.id) as pick_tasks, string_agg(t.batch_label, ', ' order by t.batch_label) as batches
      from public.so s
      join public.wms_pick_tasks t on t.order_id = s.id
     where s.status in ('draft', 'confirmed', 'at_wms', 'cancelled')
     group by s.id, s.so_number, s.status
  ),
  orphan_pack as (
    select k.id as pack_task_id, k.batch_label, s.so_number, k.status as pack_status, t.status as pick_status
      from public.wms_pack_tasks k
      join public.so s on s.id = k.order_id
      left join public.wms_pick_tasks t on t.id = k.pick_task_id
     where t.id is null or t.status is distinct from 'completed'
  ),
  wave_state as (
    select w.id, w.label, w.status,
           count(t.id) as member_batches,
           count(t.id) filter (where t.status = 'completed') as completed_batches
      from public.wms_waves w
      left join public.wms_pick_tasks t on t.wave_id = w.id
     group by w.id, w.label, w.status
    having count(t.id) = 0
        or (w.status = 'completed' and count(t.id) <> count(t.id) filter (where t.status = 'completed'))
        or (w.status <> 'completed' and count(t.id) > 0 and count(t.id) = count(t.id) filter (where t.status = 'completed'))
  ),
  hold_leak as (
    select h.id as hold_id, h.task_kind, h.task_id, h.worker, h.held_at,
           coalesce(p.status, k.status, w.status) as task_status,
           (coalesce(p.held_by, k.held_by, w.held_by) is not null) as task_held,
           h.rn as open_rank
      from (select th.*, row_number() over (partition by th.task_kind, th.task_id order by th.held_at desc) as rn
              from public.wms_task_holds th
             where th.resumed_at is null and th.task_kind in ('pick', 'pack', 'wave')) h
      left join public.wms_pick_tasks p on h.task_kind = 'pick' and p.id = h.task_id
      left join public.wms_pack_tasks k on h.task_kind = 'pack' and k.id = h.task_id
      left join public.wms_waves      w on h.task_kind = 'wave' and w.id = h.task_id
     where h.rn > 1                                                     -- 같은 과제에 열린 보류가 둘 = 닫기가 유실된 지문
        or (coalesce(p.id, k.id, w.id) is not null                      -- 지워진 과제(되돌리기)는 의도 · 표시 안 함
            and not (coalesce(p.status, k.status, w.status) = 'pending' and coalesce(p.held_by, k.held_by, w.held_by) is not null))
  ),
  picking_nt as (
    select s.so_number, s.picking_at, s.picking_by
      from public.so s
     where s.status = 'picking' and not exists (select 1 from public.wms_pick_tasks t where t.order_id = s.id)
  ),
  packed_nf as (
    select s.so_number, v.pick_batches, v.packs_done, max(k.completed_at) as last_pack_at
      from public.so s
      join public.wms_order_pack_progress v on v.order_id = s.id
      join public.wms_pack_tasks k on k.order_id = s.id and k.status = 'completed'
     where s.status = 'picking' and v.all_packed
     group by s.id, s.so_number, v.pick_batches, v.packs_done
    having max(k.completed_at) < now() - c_stale
  ),
  stale_claim as (
    select 'pick' as kind, t.id as task_id, t.batch_label as label, t.assigned_to,
           greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz), coalesce(t.started_at, 'epoch'::timestamptz), coalesce(t.heartbeat_at, 'epoch'::timestamptz), t.created_at) as last_activity
      from public.wms_pick_tasks t
      left join public.wms_pick_task_lines l on l.pick_task_id = t.id
     where t.status = 'in_progress' and t.wave_id is null
     group by t.id
    having greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz), coalesce(t.started_at, 'epoch'::timestamptz), coalesce(t.heartbeat_at, 'epoch'::timestamptz), t.created_at) < now() - c_claim
    union all
    select 'pack', t.id, t.batch_label, t.assigned_to,
           greatest(coalesce(max(l.verified_at), 'epoch'::timestamptz), coalesce(t.started_at, 'epoch'::timestamptz), coalesce(t.heartbeat_at, 'epoch'::timestamptz), t.created_at)
      from public.wms_pack_tasks t
      left join public.wms_pack_task_lines l on l.pack_task_id = t.id
     where t.status = 'in_progress'
     group by t.id
    having greatest(coalesce(max(l.verified_at), 'epoch'::timestamptz), coalesce(t.started_at, 'epoch'::timestamptz), coalesce(t.heartbeat_at, 'epoch'::timestamptz), t.created_at) < now() - c_claim
    union all
    select 'wave', w.id, w.label, w.assigned_to,
           greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz), coalesce(w.started_at, 'epoch'::timestamptz), coalesce(w.heartbeat_at, 'epoch'::timestamptz), w.created_at)
      from public.wms_waves w
      left join public.wms_pick_tasks t on t.wave_id = w.id
      left join public.wms_pick_task_lines l on l.pick_task_id = t.id
     where w.status = 'in_progress'
     group by w.id
    having greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz), coalesce(w.started_at, 'epoch'::timestamptz), coalesce(w.heartbeat_at, 'epoch'::timestamptz), w.created_at) < now() - c_claim
  ),
  long_hold as (
    select h.id as hold_id, h.task_kind, h.task_id, h.worker, h.held_at, h.source
      from public.wms_task_holds h
     where h.resumed_at is null and h.task_kind in ('pick', 'pack', 'wave') and h.held_at < now() - c_stale
       and ((h.task_kind = 'pick' and exists (select 1 from public.wms_pick_tasks p where p.id = h.task_id))
         or (h.task_kind = 'pack' and exists (select 1 from public.wms_pack_tasks k where k.id = h.task_id))
         or (h.task_kind = 'wave' and exists (select 1 from public.wms_waves w where w.id = h.task_id)))
  ),
  last_rel as (
    select max(s.at_wms_at) as last_at,
           to_char(max(s.at_wms_at) at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI') as last_at_toronto,
           round(extract(epoch from (now() - max(s.at_wms_at))) / 60)::int as minutes_ago
      from public.so s
  )
  select 10, 'line_split_sum', 'critical', 'Line split sum',
    'For every line of an order in warehouse work (Working / Finalized) the batch assignments in base units must add up to (ordered - removed) x pack factor. A row here means a split lost or double-counted units. Lines that have no batch line at all are not listed here (see Working order without batches).',
    (select count(*) from line_split), (select jsonb_agg(t) from (select * from line_split limit 8) t)
  union all
  select 20, 'short_no_disc', 'warn', 'Short pick without a mistake row',
    'A pick line marked short with neither a short-pick mistake row nor a Not enough stock report for the same order and SKU (voided mistake rows do not count; a report explains the shortfall whether or not it is resolved) - the shortfall vanished silently. Match key: order + SKU; verify if unsure.',
    (select count(*) from short_nd), (select jsonb_agg(t) from (select * from short_nd limit 8) t)
  union all
  select 30, 'pick_over', 'warn', 'Picked exceeds assigned',
    'Picked base is greater than assigned at the pick level. Over-quantity should surface at pack (over-pick), not pick.',
    (select count(*) from pick_over), (select jsonb_agg(t) from (select * from pick_over limit 8) t)
  union all
  select 40, 'finalize_pair', 'critical', 'Finalized order without a finalize record (or the reverse)',
    'An order in Finalized (packed) must have exactly one finalize record, and a finalize record must not exist on an order that has not been finalized yet. A row means Finalize or Undo Finalize was interrupted - the office cannot fulfil it until the pair is repaired.',
    (select count(*) from fin_pair), (select jsonb_agg(t) from (select * from fin_pair limit 8) t)
  union all
  select 50, 'orphan_task', 'critical', 'Batches on an order that left warehouse work',
    'Pick batches exist for an order whose status is not Working or Finalized (the office recalled or cancelled it, or a rollback did not clean up). Pickers will see a red banner on these batches - undo the batches (Rollback tab).',
    (select count(*) from orphan_task), (select jsonb_agg(t) from (select * from orphan_task limit 8) t)
  union all
  select 60, 'orphan_pack', 'warn', 'Orphaned pack tasks',
    'A pack batch whose paired pick batch is missing or not completed. (An order can be Working overall while some of its batches pack - that is normal and not flagged.)',
    (select count(*) from orphan_pack), (select jsonb_agg(t) from (select * from orphan_pack limit 8) t)
  union all
  select 70, 'wave_state', 'warn', 'Wave consistency',
    'A wave with no member batches, a completed wave with unfinished batches, or a wave whose batches are all done but the wave never closed (an interrupted finish).',
    (select count(*) from wave_state), (select jsonb_agg(t) from (select * from wave_state limit 8) t)
  union all
  select 80, 'hold_leak', 'warn', 'Open hold vs batch state',
    'An open hold row (not resumed) whose batch is not pending-and-held, or two open rows on one batch - the resume close was lost, so its hold time will silently not be subtracted in Stats. Deleted batches (rollback) are intentionally not flagged. Receipt holds are checked on the Receiving side.',
    (select count(*) from hold_leak), (select jsonb_agg(t) from (select * from hold_leak limit 8) t)
  union all
  select 90, 'picking_no_tasks', 'critical', 'Working order without batches',
    'An order in Working (picking) with no pick batches at all. Split & Waves always creates the batches in the same transaction, and Undo Split returns the order to Released to WMS - a row here means an interrupted rollback. Roll it back or re-release it.',
    (select count(*) from picking_nt), (select jsonb_agg(t) from (select * from picking_nt limit 8) t)
  union all
  select 100, 'packed_not_finalized', 'warn', 'All batches packed but not finalized for 24h',
    'Every batch of the order is packed (it is on the Fulfillment board) but nobody finalized it for more than 24 hours after the last pack. The goods are sitting on the floor - finish the pallets and press Finalize.',
    (select count(*) from packed_nf), (select jsonb_agg(t) from (select * from packed_nf limit 8) t)
  union all
  select 110, 'stale_claim', 'warn', 'Batch claimed but silent for 8h',
    'A pick/pack batch or wave still in progress with no scan, start or heartbeat for more than 8 hours (last activity = latest of line scan time, started_at, heartbeat_at, created_at - the same rule as auto-hold). Auto-hold should have returned it to the pool after 10 minutes - a row here usually means the auto-hold job is not running. Release it from the Status tab.',
    (select count(*) from stale_claim), (select jsonb_agg(t) from (select * from stale_claim limit 8) t)
  union all
  select 120, 'long_hold', 'warn', 'Batch on hold for more than 24h',
    'A pick/pack batch or wave has been on hold (not resumed) for more than 24 hours. Someone started it and nobody finished it - resume it or roll the order back.',
    (select count(*) from long_hold), (select jsonb_agg(t) from (select * from long_hold limit 8) t)
  union all
  select 200, 'last_release', 'info', 'Last release to WMS',
    'Newest Release to WMS from the office (Toronto time) - the signal that orders are still flowing into the warehouse. A long gap is normal when the office has nothing to release.',
    0::bigint, (select jsonb_build_object('last_at', last_at, 'last_at_toronto', last_at_toronto, 'minutes_ago', minutes_ago) from last_rel)
  order by 1;
end
$$;
