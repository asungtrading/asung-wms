-- 라인 시각 편승 1단계 (2026-08-21) — "실제 작업 시간" 기록 시작 (Stats 계산은 2단계 별건)
--
-- 배경 [실사고 SO-15028-1]: completed_at−started_at 벽시계는 hold·점심이 들어가고(과대),
-- reaper 의 started_at=null 리셋 뒤 재클레임이 "최초 시작"을 새로 찍으면 229라인이 4.1분으로
-- 기록된다(과소). 점 하나(started_at)로 구간을 표현하는 구조가 목표("실제로 몇 분 들였나")와
-- 맞지 않는다 → 리시빙 last_received_by/at(2026-08-17 검증 완료)과 동형으로, 라인별
-- "마지막으로 만진 시각/사람"을 스캔 저장에 편승해 기록한다.
--   · picked_at 은 baseline 부터 있었으나 채우는 코드가 0곳이던 죽은 컬럼 — 이번에 살린다.
--   · 왕복 증가 0 — picker/packer saveLine 이 이미 스캔·스테퍼·수동입력마다 UPDATE 1개를
--     보낸다(필드 편승). 백로그 「picked_at 살리기」의 비용 ②("왕복 급증")는 오판이었다.
--   · 시각은 클라이언트(태블릿) — 리시빙과 동일(사용자 결정 2026-08-21). 시계 오차는 백로그.
--   · 갭 컷·Stats 계산은 2단계(며칠 쌓인 실제 스캔 간격 분포를 보고 N 확정 — 15분은 추측값).
--
-- 이 파일: ① 컬럼 2개 추가 ② 팩 완료 RPC 재정의 — 변경은 verified_at = v_now →
-- coalesce(l.verified_at, v_now) **한 곳뿐**(스캔 시각 보존). 나머지 함수 몸통은
-- 20260806150000 원문 그대로다(diff 로 검증할 것 — 검증된 경로).
-- ⚠️ 픽 완료 RPC(wms_complete_pick)는 무접촉 — 라인 UPDATE 가 picked_at 을 원래 안 덮는다.
-- ⚠️ 배포 순서: 이 SQL(db push — Caleb 직접) 먼저 → picker/packer 프론트(규칙 23).

alter table public.wms_pick_task_lines add column if not exists picked_by text;
alter table public.wms_pack_task_lines add column if not exists verified_by text;

-- 의미(리시빙 last_received_by/at 과 동형): "이 라인을 마지막으로 만진 시각/사람".
-- 한 라인을 둘이 나누면 앞사람이 덮이지만 태스크 전체로는 각자 만진 라인이 남는다.

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
     set verified_base = r.vb, status = r.st, verification_method = r.vm,
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

-- ⚠️ 함수 EXECUTE 는 PUBLIC 기본 부여 — 명시 회수 후 필요한 것만 재부여
revoke all on function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb) from public;
revoke all on function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb) from anon;
grant execute on function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb) to authenticated, service_role;
