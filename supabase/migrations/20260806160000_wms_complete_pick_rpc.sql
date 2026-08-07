-- 픽 완료 RPC — 팩(wms_complete_pack, 20260806150000)과 같은 패턴 + wave.
--
-- 한 트랜잭션: CAS 플립(첫 쓰기) → 귀속 가드 → 라인 최종 저장(UPDATE)
-- → short_pick 생성 → stock_short 정리(갱신/stale delete). 전부 성공하거나 전부 취소.
--
-- 팩과 다른 점 (2026-08-06 사용자 승인):
--  · 단일/wave 한 함수 — 몸통(라인·discrepancy·stock_short)이 동일해 나누면 복제·드리프트.
--    p_task_id / p_wave_id 중 정확히 하나.
--  · wave 모드 CAS = wms_waves 행(소유권 단위 — 규칙 18/28). 0행 = 무기록 반환 → 재호출
--    멱등이 팩과 동일하게 성립: 이 함수가 만든 completed wave 는 멤버도 반드시 completed
--    (원자). "wave completed + 멤버 미완" 잔재는 과거 2단 쓰기에서만 가능 — 배포 전
--    감사 SQL 로 확인(테스트 ⓚ 가 그 상태의 동작을 문서화: completed:false·무변).
--  · 멤버 task 는 클라이언트가 보내지 않고 wave_id 로 서버 유도(wave 행 잠금 아래).
--    플립 행 수 ≠ 멤버 수면 예외 = wave 플립 포함 전체 롤백 — 낡은 화면이 시끄럽게 실패.
--  · ⚠️ 귀속 가드 (이번 설계 최대 위험 — 사용자 조건): wave 는 discrepancy 의
--    order_id·pick_task_id 를 클라이언트가 실어 보낸다(라인별 귀속 — 규칙 18. 팩은 태스크에서
--    유도 가능했지만 wave 는 불가). 잘못 실리면 부족이 엉뚱한 오더에 붙고 그건 조용히
--    틀어진다 → 세 배열(p_disc·p_short_refresh·p_short_delete) 전부 완료 범위의
--    order/task 인지 검사, 벗어나면 예외 = 전체 롤백. order_number 는 아예 받지 않고
--    order_id 로 서버에서 유도(오귀속 벡터 하나 제거).
--  · reason 은 파라미터로 받지 않는다 — 픽 완료가 만들 수 있는 것은 'short_pick' 뿐(고정).
--    responsible 미설정(규칙 41 — short_pick 은 픽커 실수 단정이 아님).
--  · stale stock_short 는 현행대로 DELETE (⚠️ 팩은 resolve — 비대칭. 원장 원칙 1번
--    "고치지 않고 추가"와 어긋남 → 백로그: 원장 착수 전 통일 판단).
--
-- 공통: 작업자 auth.email()→wms_staff.name 서버 유도 · SECURITY INVOKER ·
-- EXECUTE 는 PUBLIC 기본 부여라 명시 revoke.

create or replace function public.wms_complete_pick(
  p_lines         jsonb,                  -- [{id, picked_base, status('picked'|'short'), verification_method|null}]
  p_task_id       bigint default null,    -- 단일 모드
  p_wave_id       bigint default null,    -- wave 모드 (둘 중 정확히 하나)
  p_disc          jsonb default '[]',     -- [{order_id, pick_task_id|null, sku, ordered_base, actual_base}] → short_pick
  p_short_refresh jsonb default '[]',     -- [{order_id, sku, ordered_base, actual_base}] — 선언·여전히 부족
  p_short_delete  jsonb default '[]'      -- [{order_id, sku}] — 선언했지만 채움 (stale delete)
) returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_worker  text;
  v_now     timestamptz := now();
  v_flipped bigint;
  v_task_ids  bigint[];
  v_order_ids bigint[];
  v_member_total     int := 0;
  v_members_completed int := 0;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
  v_disc_inserted  int := 0;
  v_short_refreshed int := 0;
  v_short_deleted   int := 0;
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
    -- ① CAS = wave 행 (소유권 단위). 첫 쓰기 — 0행이면 아무것도 안 썼다.
    update wms_waves w
       set status = 'completed', completed_at = v_now
     where w.id = p_wave_id and w.assigned_to = v_worker and w.status = 'in_progress'
    returning w.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('completed', false, 'worker', v_worker);
    end if;

    -- ② 멤버 = 서버 유도 (wave 행 잠금 아래) → 일괄 플립. 행 수 ≠ 멤버 수 = 전체 롤백.
    select coalesce(array_agg(id), '{}') into v_task_ids
      from wms_pick_tasks where wave_id = p_wave_id;
    v_member_total := coalesce(array_length(v_task_ids, 1), 0);
    if v_member_total = 0 then
      raise exception 'Wave % has no member batches — nothing was saved. Ask a manager', p_wave_id;
    end if;
    update wms_pick_tasks t
       set status = 'completed', completed_at = v_now, completed_by = v_worker
     where t.wave_id = p_wave_id and t.assigned_to = v_worker;
    get diagnostics v_members_completed = row_count;
    if v_members_completed <> v_member_total then
      raise exception 'Wave completion failed: % of % member batches matched (a member may have been taken over or released) — nothing was saved. Ask a manager before retrying',
        v_members_completed, v_member_total;
    end if;
  else
    -- ① 단일 모드 CAS — 팩과 동형
    update wms_pick_tasks t
       set status = 'completed', completed_at = v_now, completed_by = v_worker
     where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
    returning t.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('completed', false, 'worker', v_worker);
    end if;
    v_task_ids := array[p_task_id];
  end if;

  select coalesce(array_agg(distinct order_id), '{}') into v_order_ids
    from wms_pick_tasks where id = any(v_task_ids);

  -- ⚠️ 귀속 가드 — 완료 범위 밖 order/task 가 실려 오면 예외 = 전체 롤백(플립 포함).
  perform 1 from jsonb_array_elements(coalesce(p_disc, '[]'::jsonb)) d
   where not ((d->>'order_id')::bigint = any(v_order_ids))
      or (d->>'pick_task_id' is not null and not ((d->>'pick_task_id')::bigint = any(v_task_ids)))
   limit 1;
  if found then
    raise exception 'Discrepancy row outside this pick scope (wrong order or batch) — nothing was saved';
  end if;
  perform 1 from jsonb_array_elements(coalesce(p_short_refresh, '[]'::jsonb)) r
   where not ((r->>'order_id')::bigint = any(v_order_ids)) limit 1;
  if found then
    raise exception 'Stock-short refresh outside this pick scope — nothing was saved';
  end if;
  perform 1 from jsonb_array_elements(coalesce(p_short_delete, '[]'::jsonb)) r
   where not ((r->>'order_id')::bigint = any(v_order_ids)) limit 1;
  if found then
    raise exception 'Stock-short cleanup outside this pick scope — nothing was saved';
  end if;

  -- ③ 라인 최종 저장 — pick_task_id 조건 = 타 배치 오염 차단
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
    raise exception 'Line save failed: found % of % lines — lines may have been removed by a rollback. Nothing was saved. Ask a manager before retrying',
      v_lines_updated, v_lines_expected;
  end if;

  -- ④ short_pick 생성 — reason 고정 · order_number 는 서버 유도
  insert into wms_discrepancies
        (order_id, pick_task_id, order_number, sku, ordered_base, actual_base, reason, cin7_corrected)
  select (d->>'order_id')::bigint, (d->>'pick_task_id')::bigint, o.order_number, d->>'sku',
         (d->>'ordered_base')::numeric, (d->>'actual_base')::numeric, 'short_pick', false
    from jsonb_array_elements(coalesce(p_disc, '[]'::jsonb)) d
    join wms_orders o on o.id = (d->>'order_id')::bigint;
  get diagnostics v_disc_inserted = row_count;

  -- ⑤ 선언(stock_short) 정리 — UPDATE/DELETE 0행 = 자연 no-op (기존 best-effort 의미)
  update wms_discrepancies d
     set ordered_base = (r->>'ordered_base')::numeric, actual_base = (r->>'actual_base')::numeric
    from jsonb_array_elements(coalesce(p_short_refresh, '[]'::jsonb)) r
   where d.order_id = (r->>'order_id')::bigint and d.sku = r->>'sku'
     and d.reason = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_refreshed = row_count;

  delete from wms_discrepancies d
   using jsonb_array_elements(coalesce(p_short_delete, '[]'::jsonb)) r
   where d.order_id = (r->>'order_id')::bigint and d.sku = r->>'sku'
     and d.reason = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_deleted = row_count;

  return jsonb_build_object(
    'completed', true,
    'worker', v_worker,
    'mode', case when p_wave_id is not null then 'wave' else 'single' end,
    'members_completed', v_members_completed,
    'lines_updated', v_lines_updated,
    'disc_inserted', v_disc_inserted,
    'short_refreshed', v_short_refreshed,
    'short_deleted', v_short_deleted);
end
$$;

-- ⚠️ 함수 EXECUTE 는 PUBLIC 기본 부여 — 명시 회수 후 필요한 것만 재부여
revoke all on function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb) from public;
revoke all on function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb) from anon;
grant execute on function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb) to authenticated, service_role;
