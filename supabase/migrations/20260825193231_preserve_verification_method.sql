-- pack verification_method 보존 (2026-08-25) — 완료·Hold RPC 의 방법 덮어쓰기 결함
--
-- 배경 [실측 2026-08-25]: wms_pack_task_lines(verified_base>0) 분포 — scanned_base 18,364 ·
-- **null 3,702** · manual 3,449 · scanned_variant 2,687. null 이 manual 보다 많고 오늘까지
-- 계속 생긴다 — 옛 데이터가 아니다.
-- 원인: packer 가 재개(resumePack)에서 verified_base 는 복원하면서 vmethod 만 null 로 버렸고
-- (조회 select 에도 없었다 — 같은 커밋의 프론트 수정이 근본 해결), 완료·Hold RPC 가 전 라인의
-- verification_method 를 r.vm 그대로 다시 쓴다 → 스캔으로 저장된 라인이 Hold·재개·새로고침 뒤
-- 완료되면 null 로 덮인다. ⚠️ Hold 를 성실히 쓴 사람일수록 기록이 더 지워졌다.
-- 왜 중요한가: verification_method 는 「실물 스캔 없이 눌러 넘긴 작업」을 찾는 직접 증거다 —
-- 수량은 다시 세면 되지만 "스캔했는지"는 지나가면 끝(비가역).
--
-- 이 파일 = 심층 방어: 두 함수 재정의 — **변경은 각각 verification_method 한 줄뿐**
-- (r.vm → coalesce(r.vm, l.verification_method)). verified_at = coalesce(l.verified_at, v_now)
-- 전례(20260821201104)와 같은 수법. 원문 기반(전수 grep 으로 최신 확인 — 자르지 않음):
--   wms_complete_pack = 20260821201104 · wms_hold_pack = 20260824192416.
-- 프론트 복원(같은 커밋 packer.html)이 근본이고 이것은 미래의 「상태를 잃는 경로」
-- (in-place Resume 버튼 등) 대비 마지막 벽이다. coalesce 는 새 값이 항상 이기므로 정당한
-- 변경(스캔→수동)은 안 막힌다 — 막히는 것은 「값→null 지우기」뿐인데 packer 에 그런 UI
-- 경로가 없다(세팅 지점 전수 확인: 스캔 1247/1254 · 수동 1140/1286 · null 은 배열 초기화뿐).
--
-- ⚠️ 과거 오염분은 백필 금지 — 「이 배포 이후만 신뢰」. 신뢰 시점은 배포 후 실측으로
-- asung-wms 스킬 규칙 37 계열에 기입한다(HOLD_TRACKING_SINCE 와 같은 방식 — 추정 금지).
-- ⚠️ create or replace 는 기존 ACL 을 보존한다(20260814030000 전례 주석) — revoke/grant 재조정 불필요.
-- ⚠️ picker 는 이 구조 결함이 없다(두 로드 경로 모두 복원 — picker.html:758·770/:992·1004 확인).

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
     set verified_base = r.vb, status = r.st,
         -- 방법 보존 (2026-08-25): null 이 오면 기존값 유지 — 새 값이 오면 항상 새 값(정당한 변경 통과)
         verification_method = coalesce(r.vm, l.verification_method),
         -- 스캔 시점 verified_at 보존 (2026-08-21 — 라인 시각 편승 1단계): packer saveLine 이 스캔마다
         -- 찍은 값이 있으면 유지, 스캔 0 라인(최종 flush 만 탄 것)은 종전대로 완료 시각.
         -- 소비처는 값이 항상 채워진다는 기대 유지 — coalesce 라 null 로 남는 라인 없음.
         verified_at = coalesce(l.verified_at, v_now)
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
     set verified_base = r.vb, status = r.st,
         -- 방법 보존 (2026-08-25 — 완료 RPC 와 같은 한 줄 · 파일 헤더)
         verification_method = coalesce(r.vm, l.verification_method)
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
