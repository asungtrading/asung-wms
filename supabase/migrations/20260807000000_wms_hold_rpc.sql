-- Hold RPC — 완료 RPC(wms_complete_pack 20260806150000 · wms_complete_pick 20260806160000)와
-- 같은 골격. 픽(단일+wave 한 함수)·팩 각 1개.
--
-- 한 트랜잭션: CAS 플립(첫 쓰기 — in_progress→pending·assigned_to null·held_by=작업자)
-- → 라인 최종 저장(UPDATE). 전부 성공하거나 전부 취소.
--
-- 완료와 다른 점 (2026-08-07 사용자 승인):
--  · 플립 방향이 반대(완료=completed / Hold=pending 복귀)이고 held_by 를 남긴다(규칙 23).
--    started_at·work_started 는 건드리지 않는다 — 현행 Hold 와 동일(진행 흔적 보존).
--  · discrepancy·stock_short 배열이 없다 — Hold 는 discrepancy 를 만들지 않는다(현행 확인).
--    따라서 wave 귀속 가드도 불필요: 라인 UPDATE 의 pick_task_id 스코프가 유일한 오염 방어.
--  · ⚠️ 전체 롤백 확정 (2026-08-07 사용자 결정): 라인 수 불일치도 플립 포함 전체 롤백.
--    "스캔한 것이 남아야 한다"는 요구는 saveLine 증분 저장(스캔당 1행)이 이미 충족하므로
--    Hold 시점 라인 저장은 최종 flush 일 뿐 — 부분 저장이 나은 실패 모드가 없다
--    (CAS 0행=스테일 쓰기 금지·규칙 28 / 라인 소멸=롤백된 태스크 오염 / 네트워크=재시도).
--  · 재호출 멱등: 이미 pending(내 Hold 커밋 후 응답 유실 → 재탭)이면 CAS 0행 =
--    무기록 {held:false, worker} 반환. 프론트 holdCasFailed 가 pending+held_by=나 로
--    "내 Hold" 를 판정(claim 이 held_by 를 null 로 정리하므로 이 조합은 내 Hold 뿐).
--  · 플립이 assigned_to 를 null 로 놓아도 행 잠금은 커밋까지 유지 — 남의 claim 이
--    커밋까지 블로킹되어 확인-쓰기 창은 완료와 동일하게 소멸.
--
-- 공통: 작업자 auth.email()→wms_staff.name 서버 유도 · 이름 드리프트는 worker 반환으로
-- 프론트 감지 · SECURITY INVOKER · EXECUTE 는 PUBLIC 기본 부여라 명시 revoke.

-- ── 픽 Hold: 단일 + wave 한 함수 (wms_complete_pick 과 같은 사유 — 몸통 동일) ──────
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

  return jsonb_build_object(
    'held', true,
    'worker', v_worker,
    'mode', case when p_wave_id is not null then 'wave' else 'single' end,
    'members_held', v_members_held,
    'lines_updated', v_lines_updated);
end
$$;

-- ── 팩 Hold — 픽 단일 모드와 동형 (verified_at 은 현행 Hold 와 동일하게 쓰지 않는다 —
--    완료(wms_complete_pack)만 verified_at 을 찍는다) ─────────────────────────────
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

  return jsonb_build_object(
    'held', true,
    'worker', v_worker,
    'lines_updated', v_lines_updated);
end
$$;

-- ⚠️ 함수 EXECUTE 는 PUBLIC 기본 부여 — 명시 회수 후 필요한 것만 재부여
revoke all on function public.wms_hold_pick(jsonb, bigint, bigint) from public;
revoke all on function public.wms_hold_pick(jsonb, bigint, bigint) from anon;
grant execute on function public.wms_hold_pick(jsonb, bigint, bigint) to authenticated, service_role;

revoke all on function public.wms_hold_pack(bigint, jsonb) from public;
revoke all on function public.wms_hold_pack(bigint, jsonb) from anon;
grant execute on function public.wms_hold_pack(bigint, jsonb) to authenticated, service_role;
