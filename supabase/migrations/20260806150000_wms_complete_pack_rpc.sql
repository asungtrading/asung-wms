-- 팩 완료 RPC — 이 코드베이스의 첫 트랜잭션 함수 (8단계 · 재고 원장의 예습).
--
-- 완료의 쓰기 전부를 한 트랜잭션으로: 라인 최종 저장(진짜 UPDATE — upsert 아님)
-- → discrepancy 생성 → stock_short 정리 → CAS 플립 → ready 판정(비치명).
-- 전부 성공하거나 전부 취소된다. 계산은 프론트(packer.html)가, 쓰기는 이 함수가.
--
-- 설계 결정 (2026-08-06 사용자 승인):
--  · thin 함수 — 수량·판정은 JS 가 보낸다. required 의 출처가 경로마다 달라
--    (재개=reqMap / 시작=assigned_base, 분할 오더 배치 몫) 서버 재유도는 위험.
--  · CAS 플립이 첫 쓰기 — 0행이면 아무것도 쓴 게 없으므로 예외 없이
--    {completed:false, worker} 반환. 재호출(응답 유실 뒤)도 여기서 멈추므로
--    discrepancy 중복이 원천 불가(멱등). 1행이면 행 잠금이 트랜잭션 끝까지
--    유지되어 이어받기 UPDATE 가 커밋까지 블로킹 — 확인-쓰기 창 소멸.
--  · 작업자는 파라미터가 아니라 auth.email() → wms_staff.name 서버 유도.
--    wms-auth.js:170 이 같은 행(eq email)에서 me.name 을 얻으므로 같은 문자열.
--    매니저가 이름을 고친 드리프트는 반환된 worker ≠ me.name 으로 프론트가 감지.
--  · SECURITY INVOKER — 쓰는 테이블 전부 RLS auth_all(authenticated 전체 허용)이라
--    우회할 것이 없다. DEFINER 는 권한 재구현만 늘린다.
--  · ready 판정(checkOrderReady 상당)은 예외 격리 서브블록 — 오더 상태 유지 실패가
--    완료를 되돌리면 안 된다. 실패는 ready_error 로 보고.
--
-- ⚠️ GRANT: Postgres 는 함수 EXECUTE 를 PUBLIC 에 기본 부여한다
-- (wms_order_pack_progress 뷰에서 실측한 헐거운 기본 권한과 같은 계열) — 명시 회수.

create or replace function public.wms_complete_pack(
  p_task_id       bigint,
  p_lines         jsonb,                  -- [{id, verified_base, status('verified'|'mismatch'), verification_method|null}]
  p_disc          jsonb default '[]',     -- [{sku, reason('short_after_pack'|'over_pick'|'pack_scan_mistake'), ordered_base, actual_base}]
  p_short_refresh jsonb default '[]',     -- [{sku, ordered_base, actual_base}] — 선언 라인의 열린 stock_short 수량 갱신
  p_short_resolve jsonb default '[]',     -- ["sku"] — 선언했지만 채워진 라인 → stock_short 해소
  p_recovered     jsonb default '[]'      -- ["sku"] — 팩에서 회복 → short_pick 을 resolved_pack_recovery 로
) returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_worker  text;
  v_now     timestamptz := now();
  v_order_id       bigint;
  v_pick_task_id   bigint;
  v_order_number   text;
  v_picker         text;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
  v_disc_inserted  int := 0;
  v_short_refreshed    int := 0;
  v_short_resolved     int := 0;
  v_recovered_resolved int := 0;
  v_ready       boolean := false;
  v_ready_error text := null;
  v_total int;
  v_done  int;
  v_bad   text;
begin
  -- 작업자 = 서버 유도. 정확 일치(eq) — wms-auth.js 의 조회와 같은 의미
  -- (로그인이 성립했다면 auth 이메일과 wms_staff.email 은 정확히 같다).
  select s.name into v_worker from wms_staff s where s.email = auth.email();
  if v_worker is null then
    raise exception 'No staff record for this login (%) — nothing was saved', coalesce(auth.email(), 'no email');
  end if;

  -- 페이로드 검증: 이 함수가 만들 수 있는 reason 3종만 (플립 전 — 실패 시 아무것도 안 씀)
  select d->>'reason' into v_bad
    from jsonb_array_elements(coalesce(p_disc, '[]'::jsonb)) d
   where d->>'reason' not in ('short_after_pack', 'over_pick', 'pack_scan_mistake')
   limit 1;
  if v_bad is not null then
    raise exception 'Reason "%" is not allowed in pack completion — nothing was saved', v_bad;
  end if;

  -- ① CAS 플립 먼저 (2026-08-06 배포 조건 그대로: assigned_to + in_progress).
  --    0행 = 아무것도 쓴 것이 없다 → 예외가 아니라 조용한 반환. worker 를 실어
  --    프론트가 me.name 과 대조해 "직원 이름 변경" 드리프트를 구분한다.
  update wms_pack_tasks t
     set status = 'completed', completed_at = v_now, completed_by = v_worker
   where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
  returning t.order_id, t.pick_task_id into v_order_id, v_pick_task_id;

  if v_order_id is null then
    return jsonb_build_object('completed', false, 'worker', v_worker);
  end if;

  select o.order_number into v_order_number from wms_orders o where o.id = v_order_id;
  select pt.assigned_to into v_picker from wms_pick_tasks pt where pt.id = v_pick_task_id;

  -- ② 라인 최종 저장 — 진짜 UPDATE (7단계 upsert 의 23502 문제 없음).
  --    pack_task_id 조건 = 다른 태스크 라인 오염 차단.
  update wms_pack_task_lines l
     set verified_base = r.vb, status = r.st, verification_method = r.vm, verified_at = v_now
    from (
      select (e->>'id')::bigint                     as id,
             (e->>'verified_base')::numeric         as vb,
             e->>'status'                           as st,
             nullif(e->>'verification_method', '')  as vm
        from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) e
    ) r
   where l.id = r.id and l.pack_task_id = p_task_id;
  get diagnostics v_lines_updated = row_count;
  if v_lines_updated <> v_lines_expected then
    -- 예외 = 전체 롤백(플립 포함). 원인 없는 메시지는 작업자가 계속 다시 누르게 만든다.
    raise exception 'Line save failed: found % of % lines — lines may have been removed by a rollback. Nothing was saved. Ask a manager before retrying',
      v_lines_updated, v_lines_expected;
  end if;

  -- ③ discrepancy 생성 — 현행 코드와 같은 컬럼 모양 (reason 별 템플릿).
  --    responsible(=픽커)은 서버 유도: wms_pick_tasks.assigned_to (packer.html 의
  --    best-effort enrich 와 같은 출처, 더 신뢰).
  insert into wms_discrepancies
        (order_id, pack_task_id, order_number, sku, ordered_base, actual_base, reason,
         source, responsible, declared_by, resolved_by, resolved_at, cin7_corrected)
  select v_order_id, p_task_id, v_order_number, d->>'sku',
         (d->>'ordered_base')::numeric, (d->>'actual_base')::numeric, d->>'reason',
         case when d->>'reason' = 'pack_scan_mistake' then 'packing' end,
         case when d->>'reason' in ('short_after_pack', 'over_pick') then v_picker end,
         case when d->>'reason' = 'pack_scan_mistake' then v_worker end,
         case when d->>'reason' = 'pack_scan_mistake' then v_worker end,
         case when d->>'reason' = 'pack_scan_mistake' then v_now end,
         false
    from jsonb_array_elements(coalesce(p_disc, '[]'::jsonb)) d;
  get diagnostics v_disc_inserted = row_count;

  -- ④ 선언(stock_short) 정리 — UPDATE 0행 = 자연스러운 no-op (기존 best-effort 의미 그대로)
  update wms_discrepancies d
     set ordered_base = (r->>'ordered_base')::numeric, actual_base = (r->>'actual_base')::numeric
    from jsonb_array_elements(coalesce(p_short_refresh, '[]'::jsonb)) r
   where d.order_id = v_order_id and d.sku = r->>'sku'
     and d.reason = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_refreshed = row_count;

  update wms_discrepancies d
     set resolved_by = v_worker, resolved_at = v_now
    from jsonb_array_elements_text(coalesce(p_short_resolve, '[]'::jsonb)) as s(sku)
   where d.order_id = v_order_id and d.sku = s.sku
     and d.reason = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_resolved = row_count;

  -- ⑤ 팩에서 회복된 부족 → short_pick 해소. voided 행은 되살리지 않는다(2026-08-06 롤백 무효화).
  update wms_discrepancies d
     set resolved_by = v_worker, resolved_at = v_now, reason = 'resolved_pack_recovery'
    from jsonb_array_elements_text(coalesce(p_recovered, '[]'::jsonb)) as s(sku)
   where d.order_id = v_order_id and d.sku = s.sku
     and d.reason = 'short_pick' and d.resolved_at is null and d.voided_at is null;
  get diagnostics v_recovered_resolved = row_count;

  -- ⑥ ready 판정 (checkOrderReady 상당) — 비치명 서브블록: 실패해도 완료는 커밋.
  begin
    select count(*) into v_total from wms_pick_tasks where order_id = v_order_id;
    select count(distinct pick_task_id) into v_done
      from wms_pack_tasks where order_id = v_order_id and status = 'completed';
    if v_total > 0 and v_done >= v_total then
      update wms_orders
         set status = 'ready_to_close', notified_at = v_now
       where id = v_order_id
         and status in ('pending', 'picking', 'packing', 'ready_to_close');  -- 멱등 가드 — 0행 정상
      v_ready := true;
    end if;
  exception when others then
    v_ready := false;
    v_ready_error := sqlerrm;
  end;

  return jsonb_build_object(
    'completed', true,
    'worker', v_worker,
    'ready', v_ready,
    'ready_error', v_ready_error,
    'lines_updated', v_lines_updated,
    'disc_inserted', v_disc_inserted,
    'short_refreshed', v_short_refreshed,
    'short_resolved', v_short_resolved,
    'recovered_resolved', v_recovered_resolved);
end
$$;

-- ⚠️ 함수 EXECUTE 는 PUBLIC 기본 부여 — 명시 회수 후 필요한 것만 재부여
revoke all on function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb) from public;
revoke all on function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb) from anon;
grant execute on function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb) to authenticated, service_role;
