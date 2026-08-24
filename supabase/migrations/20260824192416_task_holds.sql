-- Hold 구간 기록 (2026-08-24) — wms_task_holds 신설 + Hold RPC 2종에 기록 + health 검사 1건
--
-- 왜: Stats 작업시간 = completed_at − started_at 벽시계라 Hold·점심·야간이 전부 들어간다.
--   목표 계산 「(completed_at − started_at) − Hold 구간 합」의 선행 작업 — 지금 스키마에는
--   Hold 시각이 어디에도 없다(2026-08-24 조사: held_by(text) 뿐, held_at 은 전 마이그레이션 0건).
-- ⚠️ 이번 범위는 「기록」뿐이다 — 자동 Hold(reaper)·Stats 계산 변경은 다음 단계. 화면 무변.
--
-- 설계 결정 (2026-08-24 사용자 확정):
--  · 이력 테이블(누계 컬럼 아님) — 요구가 「시간 빼기」 외에 「하루 평균 Hold 횟수」·「구간 길이
--    분포」·「일한 토막 길이」까지라 누계는 정보를 버리는 저장이다. 이력은 언제든 누계로 접힌다.
--  · wave 는 **wave 행 1건**(task_kind='wave', task_id=wave_id) — wave 의 Hold·재개는 항상
--    전원 동시 원자다(RPC 가 행 수 불일치 시 전체 롤백 · startWave 가 전원 일괄 플립 · 멤버
--    개별 Hold 경로는 프론트에 없음 — holdBtn 은 wave.id 를 넘기고 멤버는 개별 풀에서 숨김).
--    멤버별 N행은 순수 중복이고 「Hold 횟수」를 N배로 왜곡한다. 멤버 단위 시간이 필요하면
--    wms_pick_tasks.wave_id 조인으로 손실 없이 복원된다.
--  · held_at 기록 = Hold RPC 안(트랜잭션 — CAS 0행 조기 return 은 insert 미도달 · 어느 예외든
--    이력 포함 전체 롤백이라 기존 「전부 성공 또는 전부 취소」 계약이 자동 확장된다).
--  · resumed_at 기록 = 프론트 3곳 fire-and-forget UPDATE (picker startBatch · picker startWave ·
--    packer resumePack — 2026-08-24 재개 지점 전수 조사 확정). 재개 RPC 신설은 기각 — 검증된
--    클레임 CAS 경로 3곳(startBatch 는 신규 시작 겸용)을 통째로 이관하는 것이라 「기록만」 범위를
--    넘는다. 기록 실패가 작업을 막으면 안 된다(원장과 같은 원칙 · markWorkStarted 와 같은 결).
--  · resumed_by 신설 — 남의 held 재개가 허용되므로 재개자 ≠ Hold 자. 없으면 누가 풀었는지 영영 모른다.
--  · ⚠️ 열린 채 끝나는 4경로(배치 Rollback pick reset/pack undo · 오더 단위 rollback · void ·
--    unwave — 전부 admin, 2026-08-24 전수)는 **닫지 않는다**(검증된 파괴 경로 무접촉 — 아카이브
--    순서 불가침). 방어는 두 겹: ① 계산 규칙 — resumed_at null 을 「지금도 멈춰 있음」으로 취급하는
--    조건을 「태스크가 지금도 pending + held_by」일 때로 한정(그 외는 닫힘 유실/롤백 부산물로 제외.
--    Stats 단계에서 이 규칙이 정본) ② 아래 health 검사 hold_leak 가 유실을 즉시 드러낸다.
--  · FK 없음 — 3테이블 다형 참조 + rollback 이 태스크를 delete 해도 사실 기록은 남아야 한다.
--  · 부분 유니크 인덱스 금지(PostgREST on_conflict — 프로젝트 규칙). 중복 열린 행 방어는 RPC 흐름이
--    보장한다(held 상태에서 재 Hold 는 CAS 0행 → insert 미도달) — 인덱스는 조회용 일반형만.
--
-- 배포: supabase db reset 으로 로컬 검증 후 supabase db push (사람이 직접).

-- ─────────────────────────────────────────────────────────
-- 1) wms_task_holds — Hold 구간 이력
-- ─────────────────────────────────────────────────────────
create table wms_task_holds (
  id         bigint generated always as identity primary key,
  task_kind  text not null check (task_kind in ('pick','pack','wave')),
  task_id    bigint not null,          -- pick/pack 태스크 id 또는 wave id (task_kind 로 판별)
  worker     text not null,            -- Hold 누른 사람 (RPC v_worker — 서버 유도, 프론트 신뢰 안 함)
  held_at    timestamptz not null default now(),
  resumed_at timestamptz,              -- null = 열림. ⚠️ 계산 시 「태스크가 지금도 pending+held_by」일 때만 진행 중으로 취급
  resumed_by text,                     -- 재개자 (≠ worker 가능 — 남의 held 재개 허용)
  source     text not null default 'manual' check (source in ('manual','auto'))   -- 'auto' 는 자동 Hold(다음 단계)용 예약
);
create index idx_task_holds_task on wms_task_holds (task_kind, task_id);

alter table wms_task_holds enable row level security;
create policy auth_all on wms_task_holds for all to authenticated using (true) with check (true);
revoke all on wms_task_holds from anon;

-- ─────────────────────────────────────────────────────────
-- 2) wms_hold_pick — 20260807000000 전문 + return 직전 이력 insert 한 문장.
--    CAS·라인 저장·예외 동작 무변 (insert 가 마지막이라 모든 검사를 통과한 Hold 만 기록되고,
--    이후 예외가 없으므로 「이력만 남고 Hold 는 안 됨」 경로가 없다).
-- ─────────────────────────────────────────────────────────
create or replace function public.wms_hold_pick(
  p_lines   jsonb,                 -- [{id, picked_base, status('picked'|'in_progress'|'pending'), verification_method|null}]
  p_task_id bigint default null,   -- 단일 모드
  p_wave_id bigint default null    -- wave 모드 (둘 중 정확히 하나)
) returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_worker  text;
  v_flipped bigint;
  v_task_ids bigint[];
  v_member_total int := 0;
  v_members_held int := 0;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
begin
  if (p_task_id is null) = (p_wave_id is null) then
    raise exception 'Pass exactly one of p_task_id / p_wave_id — nothing was saved';
  end if;

  -- 작업자 = 서버 유도 (wms-auth.js:170 과 같은 행·같은 컬럼 → me.name 과 같은 문자열)
  select s.name into v_worker from wms_staff s where s.email = auth.email();
  if v_worker is null then
    raise exception 'No staff record for this login (%) — nothing was saved', coalesce(auth.email(), 'no email');
  end if;

  if p_wave_id is not null then
    -- ① CAS = wave 행 (소유권 단위 — 규칙 18/28). 첫 쓰기 — 0행이면 아무것도 안 썼다.
    update wms_waves w
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = v_worker
     where w.id = p_wave_id and w.assigned_to = v_worker and w.status = 'in_progress'
    returning w.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('held', false, 'worker', v_worker);
    end if;

    -- ② 멤버 = 서버 유도 (wave 행 잠금 아래) → 일괄 플립. 행 수 ≠ 멤버 수 = 전체 롤백.
    select coalesce(array_agg(id), '{}') into v_task_ids
      from wms_pick_tasks where wave_id = p_wave_id;
    v_member_total := coalesce(array_length(v_task_ids, 1), 0);
    if v_member_total = 0 then
      raise exception 'Wave % has no member batches — nothing was saved. Ask a manager', p_wave_id;
    end if;
    update wms_pick_tasks t
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = v_worker
     where t.wave_id = p_wave_id and t.assigned_to = v_worker;
    get diagnostics v_members_held = row_count;
    if v_members_held <> v_member_total then
      raise exception 'Hold failed: % of % member batches matched (a member may have been taken over or released) — nothing was saved. Ask a manager before retrying',
        v_members_held, v_member_total;
    end if;
  else
    -- ① 단일 모드 CAS — 완료와 동형(방향만 반대)
    update wms_pick_tasks t
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = v_worker
     where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
    returning t.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('held', false, 'worker', v_worker);
    end if;
    v_task_ids := array[p_task_id];
  end if;

  -- ③ 라인 최종 저장 — pick_task_id 스코프 = 타 배치 오염 차단.
  --    행 수 ≠ 배열 길이 = 예외 = 플립 포함 전체 롤백(위 헤더의 사용자 결정).
  update wms_pick_task_lines l
     set picked_base = r.pb, status = r.st, verification_method = r.vm
    from (
      select (e->>'id')::bigint                    as id,
             (e->>'picked_base')::numeric          as pb,
             e->>'status'                          as st,
             nullif(e->>'verification_method', '') as vm
        from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e
    ) r
   where l.id = r.id and l.pick_task_id = any(v_task_ids);
  get diagnostics v_lines_updated = row_count;
  if v_lines_updated <> v_lines_expected then
    raise exception 'Line save failed: found % of % lines — lines may have been removed by a rollback. Nothing was held. Ask a manager before retrying',
      v_lines_updated, v_lines_expected;
  end if;

  -- ④ Hold 구간 이력 (2026-08-24) — wave 는 wave 행 1건(멤버별 N행 금지 — 파일 헤더 근거).
  --    resumed_at 은 재개 프론트 3곳이 닫는다. 여기가 마지막 문장이라 실패 시 Hold 전체가 롤백.
  insert into wms_task_holds (task_kind, task_id, worker)
  values (case when p_wave_id is not null then 'wave' else 'pick' end,
          coalesce(p_wave_id, p_task_id), v_worker);

  return jsonb_build_object(
    'held', true,
    'worker', v_worker,
    'mode', case when p_wave_id is not null then 'wave' else 'single' end,
    'members_held', v_members_held,
    'lines_updated', v_lines_updated);
end
$$;

-- ─────────────────────────────────────────────────────────
-- 3) wms_hold_pack — 동일 원칙 (20260807000000 전문 + 이력 insert)
-- ─────────────────────────────────────────────────────────
create or replace function public.wms_hold_pack(
  p_task_id bigint,
  p_lines   jsonb                  -- [{id, verified_base, status('verified'|'in_progress'|'pending'), verification_method|null}]
) returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_worker  text;
  v_flipped bigint;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
begin
  select s.name into v_worker from wms_staff s where s.email = auth.email();
  if v_worker is null then
    raise exception 'No staff record for this login (%) — nothing was saved', coalesce(auth.email(), 'no email');
  end if;

  -- ① CAS 플립 먼저 — 0행 = 무기록 {held:false, worker} (재호출 멱등)
  update wms_pack_tasks t
     set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = v_worker
   where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
  returning t.id into v_flipped;
  if v_flipped is null then
    return jsonb_build_object('held', false, 'worker', v_worker);
  end if;

  -- ② 라인 최종 저장 — pack_task_id 스코프 + 행 수 검사 = 전체 롤백
  update wms_pack_task_lines l
     set verified_base = r.vb, status = r.st, verification_method = r.vm
    from (
      select (e->>'id')::bigint                    as id,
             (e->>'verified_base')::numeric        as vb,
             e->>'status'                          as st,
             nullif(e->>'verification_method', '') as vm
        from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e
    ) r
   where l.id = r.id and l.pack_task_id = p_task_id;
  get diagnostics v_lines_updated = row_count;
  if v_lines_updated <> v_lines_expected then
    raise exception 'Line save failed: found % of % lines — lines may have been removed by a rollback. Nothing was held. Ask a manager before retrying',
      v_lines_updated, v_lines_expected;
  end if;

  -- ③ Hold 구간 이력 (2026-08-24 — wms_hold_pick ④ 와 동일 원칙)
  insert into wms_task_holds (task_kind, task_id, worker)
  values ('pack', p_task_id, v_worker);

  return jsonb_build_object(
    'held', true,
    'worker', v_worker,
    'lines_updated', v_lines_updated);
end
$$;

-- ⚠️ 함수 EXECUTE 는 PUBLIC 기본 부여 — create or replace 는 기존 grant 를 보존하므로
--    (20260807000000 에서 revoke/grant 완료) 여기서 재조정 불필요. 시그니처 무변.

-- ─────────────────────────────────────────────────────────
-- 4) wms_health_check — 직전 정의(20260814030000 — baseline 12검사 + image_sync_stale 120) 전문
--    + hold_leak 검사 1건 (sort 130 · 기존 13검사 무접촉)
--    ⚠️ 기반은 baseline 이 아니라 20260814030000 이다 — 재정의 전수는 grep 을 자르지 말고 확인할 것
--    (이 파일 작성 중 head 로 자른 grep 을 전수로 취급해 image_sync_stale 을 지울 뻔했다).
--
--    「열린 hold 인데 태스크 상태 불일치」 — 닫기 UPDATE 유실의 지문. 유실되면 그 배치의
--    Hold 시간이 조용히 안 빠진다(에러 없음·정지 없음·신고 없음·데이터 틀림 — 조용한 결함 계열).
--    ⚠️ 오탐 설계:
--     · 정상 진행 Hold(태스크 pending + held_by)는 잡지 않는다.
--     · 태스크가 삭제된 열린 행(rollback pack undo·오더 rollback·void·unwave 의 의도된 부산물,
--       파일 헤더 4경로)은 잡지 않는다 — 잡으면 rollback 마다 경보가 쌓여 검사가 무시된다.
--       (pick reset 은 delete 가 아니라 pending 리셋 + held_by 잔존이라 「정상 Hold」 모양으로
--        남는다 — 실제로 held 풀에 다시 뜨므로 의미도 맞다.)
--     · 단 같은 태스크에 열린 행이 2개 이상이면(rn>1) 태스크 존재 여부와 무관하게 잡는다 —
--       「재개 닫기 유실 → 같은 사람이 다시 Hold」 의 유일한 지문이다.
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
         coalesce(p.status, k.status, w.status) as task_status,
         coalesce(p.held_by, k.held_by, w.held_by) as task_held_by,
         h.rn as open_rank
  from (select th.*, row_number() over (partition by th.task_kind, th.task_id
                                        order by th.held_at desc) as rn
          from wms_task_holds th where th.resumed_at is null) h
  left join wms_pick_tasks p on h.task_kind = 'pick' and p.id = h.task_id
  left join wms_pack_tasks k on h.task_kind = 'pack' and k.id = h.task_id
  left join wms_waves      w on h.task_kind = 'wave' and w.id = h.task_id
  where h.rn > 1   -- same task holds two open rows - the fingerprint of a lost resume close
     or (coalesce(p.id, k.id, w.id) is not null              -- deleted task (rollback/void) = intended, not flagged
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
  'An open hold row (resumed_at null) whose task is not pending+held - the resume close was lost, so its hold time will silently not be subtracted. Deleted tasks (rollback/void) are intentionally not flagged; two open rows on one task always are.',
  (select count(*) from hold_leak),
  (select jsonb_agg(t) from (select * from hold_leak limit 8) t)
union all
select 200, 'last_import', 'info', 'Last order imported',
  'Newest imported_at - the true signal that polling saved an order. A long gap is normal if no new orders qualified.',
  0::bigint,
  (select jsonb_build_object('last_at', last_at, 'minutes_ago', minutes_ago) from last_import)
order by 1;
$$;
