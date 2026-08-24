-- wms_auto_hold 로컬 기능 테스트 (2026-08-24 · 자동 Hold — 마이그레이션 20260824202539)
--
-- 실행 (로컬 supabase — 프로덕션 금지):
--   supabase db reset
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/wms_auto_hold_test.sql
--
-- 전체가 한 트랜잭션 + 마지막 ROLLBACK — 로컬 DB 에 무흔적.
-- 전부 통과하면 마지막 NOTICE 가 "ALL 7 TESTS PASSED".
-- ⚠️ cron 실행 주체(postgres)와 같은 권한으로 돈다 — authenticated revoke 는 별개 확인(ⓖ).

begin;

do $test$
declare
  o1 bigint; t1 bigint; t2 bigint; t3 bigint; k1 bigint; w1 bigint; w2 bigint;
  tw1 bigint; tw2 bigint; tw3 bigint;
  la bigint; pa bigint; kla bigint; kpa bigint;
  n int; t text;
  ts_last timestamptz;
begin
  -- ── 셋업 ────────────────────────────────────────────────────────────
  insert into wms_orders (cin7_sale_id, order_number, status)
  values ('TEST-AH-1', 'SO-TEST-AH-1', 'picking') returning id into o1;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-A','SKU-A',1,10,10) returning id into la;

  -- ⓐ 대상: 마지막 스캔 25분 전 · started_at 40분 전 (보존 검증용)
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, started_at, heartbeat_at, work_started, created_at)
  values (o1,'AH-1','Worker A','in_progress', now()-interval '40 min', now()-interval '40 min', true, now()-interval '40 min')
  returning id into t1;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base, picked_base, picked_at, picked_by)
  values (t1, la, 10, 4, now()-interval '25 min', 'Worker A') returning id into pa;

  -- ⓑ 비대상: 마지막 스캔 3분 전 (started_at 은 40분 전 — 라인 시각이 판정을 미룬다)
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, started_at, heartbeat_at, work_started, created_at)
  values (o1,'AH-2','Worker B','in_progress', now()-interval '40 min', now()-interval '40 min', true, now()-interval '40 min')
  returning id into t2;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base, picked_base, picked_at, picked_by)
  values (t2, la, 10, 2, now()-interval '3 min', 'Worker B');

  -- ⓒ 라인 시각 없음(클레임만 하고 무스캔 — 옛 reaper 대상): 클레임 12분 전
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, heartbeat_at, created_at)
  values (o1,'AH-3','Worker C','in_progress', now()-interval '12 min', now()-interval '12 min')
  returning id into t3;

  -- ⓓ wave: 멤버 2 · 마지막 스캔 30분 전
  insert into wms_waves (label, warehouse, status, assigned_to, started_at, heartbeat_at, created_at)
  values ('W-AH-1','toronto','in_progress','Worker D', now()-interval '50 min', now()-interval '50 min', now()-interval '50 min')
  returning id into w1;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no, started_at, created_at)
  values (o1,'AH-W1','Worker D','in_progress', w1, 1, now()-interval '50 min', now()-interval '50 min') returning id into tw1;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no, started_at, created_at)
  values (o1,'AH-W2','Worker D','in_progress', w1, 2, now()-interval '50 min', now()-interval '50 min') returning id into tw2;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base, picked_base, picked_at, picked_by)
  values (tw1, la, 5, 1, now()-interval '30 min', 'Worker D');

  -- ⓕ 어긋난 wave: 멤버 하나가 남의 소유 (선검사 skip 대상)
  insert into wms_waves (label, warehouse, status, assigned_to, heartbeat_at, created_at)
  values ('W-AH-2','toronto','in_progress','Worker E', now()-interval '30 min', now()-interval '30 min')
  returning id into w2;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no, heartbeat_at, created_at)
  values (o1,'AH-W3','Worker E','in_progress', w2, 1, now()-interval '30 min', now()-interval '30 min');
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no, heartbeat_at, created_at)
  values (o1,'AH-W4','Somebody Else','in_progress', w2, 2, now()-interval '30 min', now()-interval '30 min') returning id into tw3;

  -- ⓔ pack: 마지막 검수 스캔 15분 전
  insert into wms_pack_tasks (order_id, pick_task_id, batch_label, assigned_to, status, started_at, heartbeat_at, work_started, created_at)
  values (o1, t2, 'AH-PK1', 'Worker F', 'in_progress', now()-interval '60 min', now()-interval '60 min', true, now()-interval '60 min')
  returning id into k1;
  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base, verified_base, status, verified_at, verified_by)
  values (k1, la, 10, 3, 'in_progress', now()-interval '15 min', 'Worker F') returning id into kpa;

  -- ── 실행 ────────────────────────────────────────────────────────────
  perform wms_auto_hold();

  -- ── ⓐ 단일 픽: 플립 + started_at 보존 + 이력(held_at = 마지막 스캔 + 10분 · source auto) ──
  select status||'/'||coalesce(assigned_to,'-')||'/'||coalesce(held_by,'-')||'/'||(started_at is not null)::text
    into t from wms_pick_tasks where id=t1;
  if t <> 'pending/-/Worker A/true' then raise exception 'FAIL a1: task=%', t; end if;
  select max(picked_at) into ts_last from wms_pick_task_lines where pick_task_id=t1;
  select count(*) into n from wms_task_holds
   where task_kind='pick' and task_id=t1 and worker='Worker A' and source='auto'
     and resumed_at is null and held_at = ts_last + interval '10 minutes';
  if n <> 1 then raise exception 'FAIL a2: history rows=%', n; end if;
  -- 라인 무접촉 (자동 Hold 는 플립+insert 뿐)
  select picked_base::text into t from wms_pick_task_lines where id=pa;
  if t <> '4' then raise exception 'FAIL a3: line touched (%)', t; end if;
  raise notice 'PASS a — 단일 픽 자동 Hold (플립·started_at 보존·held_at=마지막 활동+10분·라인 무접촉)';

  -- ── ⓑ 최근 스캔 배치 무접촉 ──────────────────────────────────────────
  select status||'/'||assigned_to into t from wms_pick_tasks where id=t2;
  if t <> 'in_progress/Worker B' then raise exception 'FAIL b1: %', t; end if;
  select count(*) into n from wms_task_holds where task_kind='pick' and task_id=t2;
  if n <> 0 then raise exception 'FAIL b2: history for active task'; end if;
  raise notice 'PASS b — 10분 미경과 무접촉 (라인 시각이 판정을 미룬다)';

  -- ── ⓒ 라인 시각 없음 → 클레임 시각(heartbeat) 폴백 ───────────────────
  select status||'/'||coalesce(held_by,'-') into t from wms_pick_tasks where id=t3;
  if t <> 'pending/Worker C' then raise exception 'FAIL c1: %', t; end if;
  select count(*) into n from wms_task_holds
   where task_kind='pick' and task_id=t3 and source='auto';
  if n <> 1 then raise exception 'FAIL c2: history rows=%', n; end if;
  raise notice 'PASS c — 무스캔 클레임 폴백 (옛 reaper 대상 흡수 · started_at 은 안 지운다)';

  -- ── ⓓ wave: 행+멤버 전부 플립 · 이력은 wave 행 1건(멤버 행 0 — A 단계 계약) ──
  select status||'/'||coalesce(assigned_to,'-')||'/'||coalesce(held_by,'-') into t from wms_waves where id=w1;
  if t <> 'pending/-/Worker D' then raise exception 'FAIL d1: wave=%', t; end if;
  select count(*) into n from wms_pick_tasks
   where wave_id=w1 and status='pending' and assigned_to is null and held_by='Worker D';
  if n <> 2 then raise exception 'FAIL d2: members=%', n; end if;
  select count(*) into n from wms_task_holds where task_kind='wave' and task_id=w1 and source='auto';
  if n <> 1 then raise exception 'FAIL d3: wave history rows=%', n; end if;
  select count(*) into n from wms_task_holds where task_kind='pick' and task_id in (tw1, tw2);
  if n <> 0 then raise exception 'FAIL d4: member rows must be 0, got %', n; end if;
  raise notice 'PASS d — wave 자동 Hold (행+멤버 원자 플립 · 이력 wave 1건)';

  -- ── ⓔ pack ───────────────────────────────────────────────────────────
  select status||'/'||coalesce(held_by,'-')||'/'||(started_at is not null)::text into t from wms_pack_tasks where id=k1;
  if t <> 'pending/Worker F/true' then raise exception 'FAIL e1: %', t; end if;
  select max(verified_at) into ts_last from wms_pack_task_lines where pack_task_id=k1;
  select count(*) into n from wms_task_holds
   where task_kind='pack' and task_id=k1 and source='auto' and held_at = ts_last + interval '10 minutes';
  if n <> 1 then raise exception 'FAIL e2: history rows=%', n; end if;
  raise notice 'PASS e — pack 자동 Hold (verified_at 기준 · started_at 보존)';

  -- ── ⓕ 어긋난 wave skip (멤버 소유자 불일치 — 선검사) ─────────────────
  select status||'/'||assigned_to into t from wms_waves where id=w2;
  if t <> 'in_progress/Worker E' then raise exception 'FAIL f1: mismatched wave was flipped (%)', t; end if;
  select count(*) into n from wms_task_holds where task_kind='wave' and task_id=w2;
  if n <> 0 then raise exception 'FAIL f2: history for skipped wave'; end if;
  raise notice 'PASS f — 어긋난 wave skip (무접촉 — health 가 잡는다)';

  -- ── ⓖ 상한 + 오름차순: 25건 대상 중 20건만 · 가장 최근 5건이 남는다 ──
  -- (별도 트랜잭션 상태가 아니므로 위 결과에 더해 진행 — 이미 물린 pick 2 + wave 1 = 예산 소진분
  --  고려해, 셋업을 초기화한 새 오더로 세지 않고 이력 행 수로 검증한다)
  delete from wms_task_holds;      -- 이 테스트 트랜잭션 안에서만 — 상한 검증을 깨끗한 판에서
  update wms_pick_tasks set status='completed' where id in (t1, t3);   -- 재물림 방지
  update wms_pack_tasks set status='completed' where id=k1;
  update wms_waves set status='completed' where id=w1;
  update wms_pick_tasks set status='completed' where wave_id=w1;
  for n in 1..25 loop
    insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, heartbeat_at, created_at)
    values (o1, 'AH-CAP-'||n, 'Worker G', 'in_progress', now() - interval '11 minutes' - (n || ' minutes')::interval, now() - interval '11 minutes' - (n || ' minutes')::interval);
  end loop;
  perform wms_auto_hold();
  select count(*) into n from wms_task_holds where source='auto';
  if n <> 20 then raise exception 'FAIL g1: cap — history rows=% (expected 20)', n; end if;
  -- 오름차순 = 가장 오래된 20건 처리 → 남은 in_progress 5건은 가장 최근(heartbeat 큰) 것들
  select count(*) into n from wms_pick_tasks
   where batch_label like 'AH-CAP-%' and status='in_progress'
     and heartbeat_at < (select min(heartbeat_at) from wms_pick_tasks where batch_label like 'AH-CAP-%' and status='pending');
  if n <> 0 then raise exception 'FAIL g2: an older task was skipped while a newer one was held (order broken)';
  end if;
  raise notice 'PASS g — 회차 상한 20 · last_activity 오름차순 (오래된 것 먼저)';

  raise notice '════ ALL 7 TESTS PASSED ════';
end
$test$;

rollback;
