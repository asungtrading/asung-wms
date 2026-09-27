-- ⑤-5c1 Health 읽기 창구 · cin7_corrected → manager_resolved (2026-09-27 UTC · 토론토 2026-09-27 저녁)
-- 정본 so-module §24(24-g 판정 13 · 24-h 판정 24 · 24-k) · 조사 회신 ⬜3 · ⬜7 · 지시서 ~/asung/prompts/wms-5-5c1.md(판정 36 · 37 · 다섯 묶음 1) · 시험 적용 + 검증 ~/asung/prompts/wms-5-5c1-verify.sql(-v mig)
-- 대상: [테스트 · Asung-IMS] 만 — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음)
-- ⛔⛔ 절대 조건(Caleb 2026-09-26): 운영 WMS(asung-WMS · wms.asung.ca)는 어떤 경우에도 멈추면 안 된다.
--     첫 문장 = 운영 가드(원본 supabase/ops/guard-test-only.sql 의 글자를 그대로 복사 · 검증 G0 이 임시 파일 diff 로 같음을 잰다).
--     흔적 셋 중 하나라도 있으면 WM501 로 멈춘다(OR · fail-closed): cron.job 에 wms-poll-orders/wms-auto-hold · inv_config.db_role <> 'test' · wms_health_runs 행 > 0
-- 하는 일:
--   A. wms_worker_mistakes.cin7_corrected → manager_resolved(뜻 「매니저가 이 실수를 정리했다」 · 운영 「Cin7 Fixed」 의 자리 · 다섯 묶음 1) · 인덱스는 칸을 따라간다(이름 idx_mistakes_unresolved 무변) · comment
--      재발행 넷 — wms_complete_pick · wms_complete_pack(20260926200918) · wms_rb_void · wms_rollback(20260926204246): 마지막 정의 본문 그대로 + 그 낱말만 · create or replace(시그니처 · grant · comment 무변 · wms_rb_void 의 authenticated 회수도 남는다)
--   B. public.wms_health_check() — 옛 이름 · 옛 반환 표(sort · check_key · category · title · hint · fail_count · sample) 그대로(판정 15 · 화면 코드 무변) · 검사 열둘 + 정보 한 줄 = 13 행 · 통과한 검사도 fail_count 0 으로 행을 낸다
--      판정 37: 뺀 다섯(factor_drift · progress_leak · dup_sale · image_sync_stale · last_import) · 남긴 여덟(line_split_sum · short_no_disc · pick_over · finalize_pair · orphan_task · orphan_pack · wave_state · hold_leak) · 새 넷(picking_no_tasks · packed_not_finalized · stale_claim · long_hold) · 정보 last_release
--      stable · security definer · 첫 줄 문 = ims_can_view('wms_manage') · authenticated · 전 창고 · 기록 표 wms_health_runs · cron 은 세우지 않는다(판정 13 가드 흔적 c)
-- ⚠️ 번호(SO · PO · RCV · 인보이스 · 크레딧)를 이 파일이 당기지 않는다 · 표를 만들지 않는다 · 옛 표(wms_legacy)는 무접촉

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

-- ═══ A) 칸 이름 — cin7_corrected → manager_resolved (인덱스 idx_mistakes_unresolved 는 칸을 따라간다 · 이름 무변) ═══
alter table public.wms_worker_mistakes rename column cin7_corrected to manager_resolved;
comment on column public.wms_worker_mistakes.manager_resolved is
  '⑤-5c1 매니저가 이 실수를 정리했다(재고 조정까지 끝냄 · 운영 admin 「Cin7 Fixed」 단추의 자리 · 운영 칸 이름은 cin7_corrected) — true 면 열린 큐에서 빠진다 · 되돌리기(wms_rb_void)는 이 칸이 true 인 행을 무효화하지 않는다 · resolved_by/at 과 함께 찍힌다';
comment on table public.wms_worker_mistakes is
  '⑤-1 (so-module §24 판정 14) · 옛 wms_discrepancies 의 좁힌 판 — 작업자 실수 다섯만 · recv_* 는 po_receipt_diff · stock_short 는 wms_reports(판정 20) · manager_resolved 는 「매니저가 정리했다」 뜻(⑤-5c1 · 운영 칸 이름 cin7_corrected) · 옛 표는 wms_legacy';

-- ═══ A2) 재발행 넷 — 마지막 정의 본문 그대로 · 그 낱말만 · create or replace(시그니처 · grant · comment 무변) ═══
-- wms_complete_pick — 원본 20260926200918_wms_5_2a2_pick_pack_holds.sql · 바뀐 낱말 1
create or replace function public.wms_complete_pick(p_lines jsonb, p_task_id bigint default null, p_wave_id bigint default null, p_mistakes jsonb default '[]'::jsonb, p_short_refresh jsonb default '[]'::jsonb, p_short_delete jsonb default '[]'::jsonb, p_session_id text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_worker  uuid;
  v_now     timestamptz := now();
  v_wh      uuid;
  v_flipped bigint;
  v_task_ids  bigint[];
  v_order_ids uuid[];
  v_member_total     int := 0;
  v_members_completed int := 0;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
  v_disc_inserted  int := 0;
  v_short_refreshed int := 0;
  v_short_deleted   int := 0;
  v_bins_inserted   int := 0;
  v_e       jsonb;  v_b jsonb;                                       -- ⚠️ 별칭 e·b(줄 저장 서브쿼리)와 겹치지 않게 v_ 접두
  v_pl      record;
  v_line_id bigint;  v_pb numeric;  v_sum numeric;  v_rem numeric;  v_bin uuid;  v_bin_name text;  v_first uuid;  v_first_name text;
begin
  perform public.ims_require_write('picking', 'saved');               -- ⭐ 첫 줄
  v_worker := public.so_current_staff();
  if (p_task_id is null) = (p_wave_id is null) then
    raise exception 'Pass exactly one of p_task_id / p_wave_id — nothing was saved';
  end if;
  -- 창고 제한 — 과제 오더의 창고 · 웨이브는 웨이브 행의 창고
  select case when p_wave_id is not null then (select w.warehouse_id from public.wms_waves w where w.id = p_wave_id)
              else (select s.location_id from public.wms_pick_tasks t join public.so s on s.id = t.order_id where t.id = p_task_id) end into v_wh;
  if v_wh is null then raise exception 'Task not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_wh) then                          -- ⭐ 둘째
    raise exception 'This task is at another warehouse — you are not set up for it — nothing was saved';
  end if;

  if p_wave_id is not null then
    -- ① CAS = wave 행 (소유권 단위). 첫 쓰기 — 0행이면 아무것도 안 썼다.
    update public.wms_waves w
       set status = 'completed', completed_at = v_now
     where w.id = p_wave_id and w.assigned_to = v_worker and w.status = 'in_progress'
       and (p_session_id is null or w.session_id is null or w.session_id = p_session_id)
    returning w.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('completed', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from public.wms_waves x where x.id = p_wave_id));
    end if;
    -- ② 멤버 = 서버 유도 (wave 행 잠금 아래) → 일괄 플립. 행 수 ≠ 멤버 수 = 전체 롤백.
    select coalesce(array_agg(id), '{}') into v_task_ids from public.wms_pick_tasks where wave_id = p_wave_id;
    v_member_total := coalesce(array_length(v_task_ids, 1), 0);
    if v_member_total = 0 then
      raise exception 'Wave % has no member batches — nothing was saved. Ask a manager', p_wave_id;
    end if;
    update public.wms_pick_tasks t
       set status = 'completed', completed_at = v_now, completed_by = v_worker
     where t.wave_id = p_wave_id and t.assigned_to = v_worker;
    get diagnostics v_members_completed = row_count;
    if v_members_completed <> v_member_total then
      raise exception 'Wave completion failed: % of % member batches matched (a member may have been taken over or released) — nothing was saved. Ask a manager before retrying',
        v_members_completed, v_member_total;
    end if;
  else
    -- ① 단일 모드 CAS — 팩과 동형
    update public.wms_pick_tasks t
       set status = 'completed', completed_at = v_now, completed_by = v_worker
     where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
       and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
    returning t.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('completed', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from public.wms_pick_tasks x where x.id = p_task_id));
    end if;
    v_task_ids := array[p_task_id];
  end if;

  select coalesce(array_agg(distinct order_id), '{}') into v_order_ids from public.wms_pick_tasks where id = any(v_task_ids);

  -- ⚠️ 귀속 가드 — 완료 범위 밖 order/task 가 실려 오면 예외 = 전체 롤백(플립 포함).
  perform 1 from jsonb_array_elements(coalesce(p_mistakes, '[]'::jsonb)) d
   where not ((d->>'order_id')::uuid = any(v_order_ids))
      or (d->>'pick_task_id' is not null and not ((d->>'pick_task_id')::bigint = any(v_task_ids)))
   limit 1;
  if found then
    raise exception 'Mistake row outside this pick scope (wrong order or batch) — nothing was saved';
  end if;
  perform 1 from jsonb_array_elements(coalesce(p_short_refresh, '[]'::jsonb)) r
   where not ((r->>'order_id')::uuid = any(v_order_ids)) limit 1;
  if found then
    raise exception 'Stock-short refresh outside this pick scope — nothing was saved';
  end if;
  perform 1 from jsonb_array_elements(coalesce(p_short_delete, '[]'::jsonb)) r
   where not ((r->>'order_id')::uuid = any(v_order_ids)) limit 1;
  if found then
    raise exception 'Stock-short cleanup outside this pick scope — nothing was saved';
  end if;

  -- ③ 라인 최종 저장 — pick_task_id 조건 = 타 배치 오염 차단
  update public.wms_pick_task_lines l
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

  -- ③′ 실제 칸 행(⑤-2a2) — 줄마다 planned=false 행을 새로(있던 것은 지운다) · 합 = picked_base · bins 가 없으면 계획 칸 순서로
  for v_e in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    v_line_id := (v_e->>'id')::bigint;  v_pb := (v_e->>'picked_base')::numeric;
    delete from public.wms_pick_line_bins x where x.pick_task_line_id = v_line_id and not x.planned;
    if v_pb <= 0 then continue; end if;
    if jsonb_typeof(v_e->'bins') = 'array' and jsonb_array_length(v_e->'bins') > 0 then
      v_sum := 0;
      for v_b in select * from jsonb_array_elements(v_e->'bins') loop
        if (v_b->>'qty_base')::numeric <= 0 then raise exception 'Line %: a bin row has qty_base <= 0 — nothing was saved', v_line_id; end if;
        if v_b ? 'bin_id' then
          select rb.id, rb.name into v_bin, v_bin_name from public.ref_bin rb where rb.id = (v_b->>'bin_id')::uuid and rb.warehouse_id = v_wh;
        else
          select rb.id, rb.name into v_bin, v_bin_name from public.ref_bin rb where rb.name = v_b->>'bin' and rb.warehouse_id = v_wh;
        end if;
        if v_bin is null then raise exception 'Line %: bin % is not in this warehouse — nothing was saved', v_line_id, coalesce(v_b->>'bin', v_b->>'bin_id'); end if;
        insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at)
        values (v_line_id, v_bin, v_bin_name, (v_b->>'qty_base')::numeric, false, v_worker, v_now);
        v_bins_inserted := v_bins_inserted + 1;  v_sum := v_sum + (v_b->>'qty_base')::numeric;
      end loop;
      if v_sum <> v_pb then raise exception 'Line %: bin quantities (%) do not add up to picked (%) — nothing was saved', v_line_id, v_sum, v_pb; end if;
    else
      v_rem := v_pb;  v_first := null;
      for v_pl in select x.bin_id, x.bin, x.qty_base from public.wms_pick_line_bins x where x.pick_task_line_id = v_line_id and x.planned order by x.id loop
        if v_first is null then v_first := v_pl.bin_id; v_first_name := v_pl.bin; end if;
        exit when v_rem <= 0;
        insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at)
        values (v_line_id, v_pl.bin_id, v_pl.bin, least(v_rem, v_pl.qty_base), false, v_worker, v_now);
        v_bins_inserted := v_bins_inserted + 1;  v_rem := v_rem - least(v_rem, v_pl.qty_base);
      end loop;
      if v_rem > 0 and v_first is not null then                      -- 계획보다 많이 뽑았다 → 첫 계획 칸이 나머지를 받는다
        insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at)
        values (v_line_id, v_first, v_first_name, v_rem, false, v_worker, v_now);
        v_bins_inserted := v_bins_inserted + 1;  v_rem := 0;
      end if;
      if v_rem > 0 then raise exception 'Line %: no bins given and no planned bins to fall back on — nothing was saved', v_line_id; end if;
    end if;
  end loop;

  -- ④ short_pick 생성 — reason 고정 · order_number 는 서버 유도(so_number) → wms_worker_mistakes
  insert into public.wms_worker_mistakes
        (order_id, pick_task_id, order_number, sku, ordered_base, actual_base, reason, manager_resolved)
  select (d->>'order_id')::uuid, (d->>'pick_task_id')::bigint, o.so_number, d->>'sku',
         (d->>'ordered_base')::numeric, (d->>'actual_base')::numeric, 'short_pick', false
    from jsonb_array_elements(coalesce(p_mistakes, '[]'::jsonb)) d
    join public.so o on o.id = (d->>'order_id')::uuid;
  get diagnostics v_disc_inserted = row_count;

  -- ⑤ 선언(stock_short) 정리 — wms_reports kind stock_short · UPDATE/DELETE 0행 = 자연 no-op
  update public.wms_reports d
     set qty_expected = (r->>'ordered_base')::numeric, qty_found = (r->>'actual_base')::numeric
    from jsonb_array_elements(coalesce(p_short_refresh, '[]'::jsonb)) r
   where d.order_id = (r->>'order_id')::uuid and d.sku = r->>'sku'
     and d.kind = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_refreshed = row_count;

  delete from public.wms_reports d
   using jsonb_array_elements(coalesce(p_short_delete, '[]'::jsonb)) r
   where d.order_id = (r->>'order_id')::uuid and d.sku = r->>'sku'
     and d.kind = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_deleted = row_count;

  return jsonb_build_object(
    'completed', true,
    'worker', v_worker,
    'mode', case when p_wave_id is not null then 'wave' else 'single' end,
    'members_completed', v_members_completed,
    'lines_updated', v_lines_updated,
    'bins_inserted', v_bins_inserted,
    'disc_inserted', v_disc_inserted,
    'short_refreshed', v_short_refreshed,
    'short_deleted', v_short_deleted);
end
$$;
-- wms_complete_pack — 원본 20260926200918_wms_5_2a2_pick_pack_holds.sql · 바뀐 낱말 1
create or replace function public.wms_complete_pack(p_task_id bigint, p_lines jsonb, p_mistakes jsonb default '[]'::jsonb, p_short_refresh jsonb default '[]'::jsonb, p_short_resolve jsonb default '[]'::jsonb, p_recovered jsonb default '[]'::jsonb, p_session_id text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_worker  uuid;
  v_now     timestamptz := now();
  v_wh      uuid;
  v_order_id       uuid;
  v_pick_task_id   bigint;
  v_order_number   text;
  v_picker         uuid;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
  v_disc_inserted  int := 0;
  v_short_refreshed    int := 0;
  v_short_resolved     int := 0;
  v_recovered_resolved int := 0;
  v_ready       boolean := false;
  v_bad   text;
begin
  perform public.ims_require_write('packing', 'saved');               -- ⭐ 첫 줄
  v_worker := public.so_current_staff();
  select s.location_id into v_wh from public.wms_pack_tasks t join public.so s on s.id = t.order_id where t.id = p_task_id;
  if v_wh is null then raise exception 'Task not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_wh) then                          -- ⭐ 둘째
    raise exception 'This task is at another warehouse — you are not set up for it — nothing was saved';
  end if;

  -- 페이로드 검증: 이 함수가 만들 수 있는 reason 3종만 (플립 전 — 실패 시 아무것도 안 씀)
  select d->>'reason' into v_bad
    from jsonb_array_elements(coalesce(p_mistakes, '[]'::jsonb)) d
   where d->>'reason' not in ('short_after_pack', 'over_pick', 'pack_scan_mistake')
   limit 1;
  if v_bad is not null then
    raise exception 'Reason "%" is not allowed in pack completion — nothing was saved', v_bad;
  end if;

  -- ① CAS 플립 먼저 (assigned_to = 나 + in_progress + session). 0행 = 아무것도 쓴 것이 없다 → 조용한 반환.
  update public.wms_pack_tasks t
     set status = 'completed', completed_at = v_now, completed_by = v_worker
   where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
     and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
  returning t.order_id, t.pick_task_id into v_order_id, v_pick_task_id;

  if v_order_id is null then
    return jsonb_build_object('completed', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from public.wms_pack_tasks x where x.id = p_task_id));
  end if;

  select o.so_number into v_order_number from public.so o where o.id = v_order_id;
  select pt.assigned_to into v_picker from public.wms_pick_tasks pt where pt.id = v_pick_task_id;

  -- ② 라인 최종 저장 — pack_task_id 조건 = 다른 태스크 라인 오염 차단. 방법·스캔 시각·사람은 coalesce 로 보존.
  update public.wms_pack_task_lines l
     set verified_base = r.vb, status = r.st,
         verification_method = coalesce(r.vm, l.verification_method),
         verified_at = coalesce(l.verified_at, v_now),
         verified_by = coalesce(l.verified_by, v_worker)
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
    raise exception 'Line save failed: found % of % lines — lines may have been removed by a rollback. Nothing was saved. Ask a manager before retrying',
      v_lines_updated, v_lines_expected;
  end if;

  -- ③ 실수 생성 — reason 별 템플릿 · responsible(=픽커)은 서버 유도: wms_pick_tasks.assigned_to → wms_worker_mistakes
  insert into public.wms_worker_mistakes
        (order_id, pack_task_id, order_number, sku, ordered_base, actual_base, reason,
         source, responsible, declared_by, resolved_by, resolved_at, manager_resolved)
  select v_order_id, p_task_id, v_order_number, d->>'sku',
         (d->>'ordered_base')::numeric, (d->>'actual_base')::numeric, d->>'reason',
         case when d->>'reason' = 'pack_scan_mistake' then 'packing' end,
         case when d->>'reason' in ('short_after_pack', 'over_pick') then v_picker end,
         case when d->>'reason' = 'pack_scan_mistake' then v_worker end,
         case when d->>'reason' = 'pack_scan_mistake' then v_worker end,
         case when d->>'reason' = 'pack_scan_mistake' then v_now end,
         false
    from jsonb_array_elements(coalesce(p_mistakes, '[]'::jsonb)) d;
  get diagnostics v_disc_inserted = row_count;

  -- ④ 선언(stock_short) 정리 — wms_reports kind stock_short · UPDATE 0행 = 자연스러운 no-op
  update public.wms_reports d
     set qty_expected = (r->>'ordered_base')::numeric, qty_found = (r->>'actual_base')::numeric
    from jsonb_array_elements(coalesce(p_short_refresh, '[]'::jsonb)) r
   where d.order_id = v_order_id and d.sku = r->>'sku'
     and d.kind = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_refreshed = row_count;

  update public.wms_reports d
     set resolved_by = v_worker, resolved_at = v_now
    from jsonb_array_elements_text(coalesce(p_short_resolve, '[]'::jsonb)) as s(sku)
   where d.order_id = v_order_id and d.sku = s.sku
     and d.kind = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_resolved = row_count;

  -- ⑤ 팩에서 회복된 부족 → short_pick 해소. voided 행은 되살리지 않는다.
  update public.wms_worker_mistakes d
     set resolved_by = v_worker, resolved_at = v_now, reason = 'resolved_pack_recovery'
    from jsonb_array_elements_text(coalesce(p_recovered, '[]'::jsonb)) as s(sku)
   where d.order_id = v_order_id and d.sku = s.sku
     and d.reason = 'short_pick' and d.resolved_at is null and d.voided_at is null;
  get diagnostics v_recovered_resolved = row_count;

  -- ⑥ ready 판정 — 뷰 wms_order_pack_progress.all_packed 를 돌려줄 뿐 · SO 상태는 안 바꾼다(packed 는 Finalize · ⑤-2b · 판정 18)
  select coalesce(v.all_packed, false) into v_ready from public.wms_order_pack_progress v where v.order_id = v_order_id;

  return jsonb_build_object(
    'completed', true,
    'worker', v_worker,
    'ready', v_ready,
    'lines_updated', v_lines_updated,
    'disc_inserted', v_disc_inserted,
    'short_refreshed', v_short_refreshed,
    'short_resolved', v_short_resolved,
    'recovered_resolved', v_recovered_resolved);
end
$$;
-- wms_rb_void — 원본 20260926204246_wms_5_2b_finalize_handoff_rollback.sql · 바뀐 낱말 1
create or replace function public.wms_rb_void(p_staff uuid, p_link text, p_ids bigint[], p_reasons text[], p_why text) returns int
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_n int;
begin
  if p_link not in ('pick_task_id', 'pack_task_id') then raise exception 'wms_rb_void: bad link %', p_link; end if;
  execute format('update public.wms_worker_mistakes set voided_at = now(), voided_by = $1, voided_reason = $2 where %I = any($3) and reason = any($4) and voided_at is null and not manager_resolved', p_link)
  using p_staff, p_why, p_ids, p_reasons;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
-- wms_rollback — 원본 20260926204246_wms_5_2b_finalize_handoff_rollback.sql · 바뀐 낱말 1
create or replace function public.wms_rollback(p_so_id uuid, p_action text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_pack constant text[] := array['short_after_pack', 'over_pick', 'pack_scan_mistake'];
  v_staff uuid;  v_so public.so%rowtype;  v_fin public.wms_order_finalize%rowtype;
  v_ids bigint[];  v_wids bigint[];  v_wid bigint;
  v_arch int := 0;  v_void int := 0;  v_reopen int := 0;  v_status text;  v_from text;  v_to text;  v_orig uuid;  i int;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');
  v_staff := public.so_current_staff();
  if p_action not in ('finalize', 'fulfillment', 'pack', 'pick', 'split') then raise exception 'Unknown rollback action % — nothing was saved', p_action; end if;
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_so.location_id) then              -- ⭐ 둘째
    raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_so.so_number;
  end if;
  select * into v_fin from public.wms_order_finalize f where f.order_id = p_so_id;
  if p_action = 'finalize' then
    if v_so.status <> 'packed' or v_fin.order_id is null then raise exception 'Order % is not finalized (%) — nothing was saved', v_so.so_number, v_so.status; end if;
  else
    if v_so.status = 'packed' or v_fin.order_id is not null then       -- SO-13893 벨트: Finalize 뒤에는 팩 · 픽 · 배치를 되돌리지 않는다
      raise exception 'Order % is finalized — use Undo Finalize first — nothing was saved', v_so.so_number;
    end if;
    if v_so.status <> 'picking' then raise exception 'Order % is % — nothing to roll back here — nothing was saved', v_so.so_number, v_so.status; end if;
  end if;
  v_status := v_so.status;
  if p_action in ('finalize', 'fulfillment') then
    -- 팔렛 · 박스 · 담긴 것(운영 deleteFulfillmentRows) — 담긴 것 삭제 → 빈 유닛(담긴 것 0 · 자식 0) 삭제 · finalize 기록 삭제 · SO packed → picking
    v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_so.so_number, null, 'wms_pallet_items', format('order_id = %L', p_so_id));
    delete from public.wms_pallet_items where order_id = p_so_id;
    for i in 1 .. 2 loop                                               -- 두 단계: 빈 박스(자식) → 빈 팔렛(부모) · 담긴 것이 남은 유닛은 둔다(운영 deleteFulfillmentRows)
      v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_so.so_number, null, 'wms_pallets',
                  format('(order_id = %L or parent_id in (select id from public.wms_pallets where order_id = %L)) and not exists (select 1 from public.wms_pallet_items i where i.pallet_id = t.id) and not exists (select 1 from public.wms_pallets c where c.parent_id = t.id)', p_so_id, p_so_id));
      delete from public.wms_pallets u where (u.order_id = p_so_id or u.parent_id in (select id from public.wms_pallets where order_id = p_so_id))
        and not exists (select 1 from public.wms_pallet_items i where i.pallet_id = u.id) and not exists (select 1 from public.wms_pallets c where c.parent_id = u.id);
    end loop;
    if p_action = 'finalize' then
      v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_so.so_number, null, 'wms_order_finalize', format('order_id = %L', p_so_id));
      delete from public.wms_order_finalize where order_id = p_so_id;
      perform public.so_wms_status(p_so_id, 'picking', v_staff);
      v_status := 'picking';  v_orig := v_fin.finalized_by;
    end if;
    v_from := case p_action when 'finalize' then 'finalized' else 'fulfilled' end;  v_to := 'pack_complete';
  elsif p_action = 'pack' then
    if exists (select 1 from public.wms_pallet_items i where i.order_id = p_so_id) then raise exception 'Order % has items on pallets — Undo Fulfillment first — nothing was saved', v_so.so_number; end if;
    select coalesce(array_agg(id), '{}') into v_ids from public.wms_pack_tasks where order_id = p_so_id;
    select assigned_to into v_orig from public.wms_pack_tasks where order_id = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_so.so_number, null, 'wms_pack_tasks', format('order_id = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_so.so_number, null, 'wms_pack_task_lines', format('pack_task_id = any(%L::bigint[])', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pack_task_id', v_ids, c_pack, 'pack rollback (order ' || v_so.so_number || ')');
    update public.wms_worker_mistakes set reason = 'short_pick', resolved_by = null, resolved_at = null   -- 팩 회복을 다시 연다(오더 단위 · 규칙 14 양방향)
     where order_id = p_so_id and reason = 'resolved_pack_recovery' and voided_at is null and not manager_resolved;
    get diagnostics v_reopen = row_count;
    delete from public.wms_pack_tasks where order_id = p_so_id;        -- 줄은 cascade
    v_from := 'pack_complete';  v_to := 'pick_complete';
  elsif p_action = 'pick' then
    if exists (select 1 from public.wms_pack_tasks k where k.order_id = p_so_id) then raise exception 'Order % has packing — Undo Pack first — nothing was saved', v_so.so_number; end if;
    select coalesce(array_agg(id), '{}') into v_ids from public.wms_pick_tasks where order_id = p_so_id;
    select assigned_to into v_orig from public.wms_pick_tasks where order_id = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_so.so_number, null, 'wms_pick_tasks', format('order_id = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_so.so_number, null, 'wms_pick_task_lines', format('pick_task_id = any(%L::bigint[])', v_ids));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_so.so_number, null, 'wms_pick_line_bins', format('not planned and pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(%L::bigint[]))', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', v_ids, array['short_pick'], 'pick reset (order ' || v_so.so_number || ')');
    delete from public.wms_pick_line_bins b where not b.planned and b.pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(v_ids));
    update public.wms_pick_task_lines set picked_base = 0, status = 'pending', verification_method = null, picked_at = null, picked_by = null where pick_task_id = any(v_ids);
    update public.wms_pick_tasks set status = 'pending', assigned_to = null, started_at = null, completed_at = null, completed_by = null, heartbeat_at = null, work_started = false, held_by = null, session_id = null where order_id = p_so_id;
    v_from := 'pick_complete';  v_to := 'pick_reset';
  else   -- split
    if exists (select 1 from public.wms_pack_tasks k where k.order_id = p_so_id) then raise exception 'Order % has packing — Undo Pack first — nothing was saved', v_so.so_number; end if;
    select coalesce(array_agg(id), '{}'), coalesce(array_agg(distinct wave_id) filter (where wave_id is not null), '{}') into v_ids, v_wids from public.wms_pick_tasks where order_id = p_so_id;
    select assigned_to into v_orig from public.wms_pick_tasks where order_id = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_so.so_number, null, 'wms_pick_tasks', format('order_id = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_so.so_number, null, 'wms_pick_task_lines', format('pick_task_id = any(%L::bigint[])', v_ids));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_so.so_number, null, 'wms_pick_line_bins', format('pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(%L::bigint[]))', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', v_ids, array['short_pick'], 'split undo (order ' || v_so.so_number || ')');
    delete from public.wms_pick_tasks where order_id = p_so_id;        -- 줄 · 칸 행은 cascade
    foreach v_wid in array v_wids loop                                 -- 이 되돌리기로 빈 웨이브는 지운다(운영 doVoid 와 같다)
      if not exists (select 1 from public.wms_pick_tasks t where t.wave_id = v_wid) then
        v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_so.so_number, null, 'wms_waves', format('id = %L', v_wid));
        delete from public.wms_waves where id = v_wid;
      end if;
    end loop;
    perform public.so_wms_status(p_so_id, 'at_wms', v_staff);        -- 과제 0 → 판정 18
    v_status := 'at_wms';  v_from := 'split';  v_to := 'unsplit';
  end if;
  insert into public.wms_rollback_log (order_id, order_number, action, from_stage, to_stage, performed_by, original_worker)
  values (p_so_id, v_so.so_number, p_action, v_from, v_to, v_staff, v_orig);
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'action', p_action, 'status', v_status, 'archived', v_arch, 'voided', v_void, 'reopened', v_reopen);
end;
$$;
comment on function public.wms_rb_void(uuid, text, bigint[], text[], text) is '⑤-2b 속 함수 — 실수 무효화(삭제 아님 · 규칙 41 화이트리스트 · 링크 칸으로만 · manager_resolved 는 손대지 않는다 · ⑤-5c1 낱말) · 팩 = short_after_pack·over_pick·pack_scan_mistake · 픽 = short_pick · stock_short 는 리포트라 무관';

-- ═══ B) Health 읽기 창구 — public.wms_health_check() (판정 37 · 옛 wms_legacy.wms_health_check 의 자리 · 옛 반환 표 그대로) ═══
--   검사 열둘 + 정보 한 줄 = 13 행 · sort 순 · 통과한 검사도 fail_count 0 행 · sample = 걸린 것 8 개까지(사람이 읽는 칸 — SO 번호 · 배치 라벨 · SKU · 시각)
--   문턱은 상수 둘: c_stale 24h(packed_not_finalized · long_hold) · c_claim 8h(stale_claim · 근무 하루 — 셈은 wms_auto_hold 와 같은 「마지막 소식」 = 줄 스캔 시각 · started_at · heartbeat_at · created_at 의 최댓값)
--   ⬜a line_split_sum 은 배치에 든 줄만(wms_batch_create 가 보낼 줄 전부를 정확히 한 배치에 넣는다) · 배치 밖 줄은 picking_no_tasks 의 몫
--   ⬜c security definer(so 읽기 규칙과 무관하게 전 창고를 본다) · 첫 줄 문 ims_can_view('wms_manage') · 없으면 P0001 사람 문장
create function public.wms_health_check() returns table(sort integer, check_key text, category text, title text, hint text, fail_count bigint, sample jsonb)
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
    'A pick line marked short with no short-pick mistake row for that order and SKU (voided rows do not count) - the shortfall vanished silently. Match key: order + SKU; verify if unsure.',
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
comment on function public.wms_health_check() is
  '⑤-5c1 Health 읽기 창구(판정 37 · 옛 wms_legacy.wms_health_check 의 자리 · 반환 표 그대로) — stable · definer · 첫 줄 문 ims_can_view(wms_manage) · 검사 열둘 + 정보 last_release = 13 행 · 통과도 fail_count 0 행 · 문턱 상수 c_stale 24h · c_claim 8h · 전 창고 · 기록 표 · cron 없음(가드 흔적 c)';
revoke all on function public.wms_health_check() from public, anon;
grant execute on function public.wms_health_check() to authenticated;
