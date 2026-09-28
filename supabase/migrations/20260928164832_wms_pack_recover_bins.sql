-- ─────────────────────────────────────────────────────────────
-- 팩에서 회복한 물건에 칸을 남긴다 — 판정 57 A (Asung-IMS · adj-rec-a · 2026-09-28)
--   왜: 팩 회복은 팩 줄 verified_base 만 남겨 wms_so_handoff(Σ칸 planned=false)가 회복분을 잘랐다 ⇒ so_finalize → so_ship → inv_post_sale 이 회복분을 안 빼고 pick_short 백오더 오탐 · 픽 0 전량 회복이면 마무리가 막혔다 · inv_adjust_picked(P)도 못 셌다
--   든 것: ① wms_pick_line_bins.pack_task_id(회복 행 표식 · FK wms_pack_tasks cascade) ② wms_complete_pack 재발행(20260927214447:244~371 · p_recovered 새 모양 [{sku, bin_id|bin, qty}] · 옛 모양 거부 · 회복 칸 행 · 줄 대조)
--         ③ wms_rollback(20260927214447:387~479 · pack 되돌리기가 회복 행을 archive → 삭제) ④ wms_rollback_batch(20260926204246:604~651 · 같은 뜻)
--   안 바꾼 것(뜻이 맞아서): wms_so_handoff · inv_adjust_picked · wms_pick_lines · wms_health_check · so_pick_plan — 회복 행은 planned=false 라 픽커 행과 같은 길로 읽힌다(보고 2 전수 표)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 시그니처 무변(create or replace · grant 그대로)
-- ─────────────────────────────────────────────────────────────
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

-- ═══ ① 회복 행 표식 ═══
alter table public.wms_pick_line_bins add column pack_task_id bigint references public.wms_pack_tasks (id) on delete cascade;
create index idx_pick_line_bins_pack_task on public.wms_pick_line_bins (pack_task_id) where pack_task_id is not null;
comment on column public.wms_pick_line_bins.pack_task_id is '판정 57 — 팩에서 회복한 낱개의 칸 행(planned=false · picked_by = 팩커)이면 그 팩 과제 · 픽커가 뽑은 행은 null · 팩 되돌리기(wms_rollback pack · wms_rollback_batch pack)가 archive 뒤 지운다(FK cascade 는 안전망) · 출고 · 원장 · P 는 픽커 행과 같은 길로 읽는다';

-- ═══ ② wms_complete_pack 재발행 — 20260927214447:244~371 바이트 그대로 · 더한 줄: 선언 2 · ②′ 회복 블록 · ⑤ 새 모양 · 반환 recovered_rows ═══
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
  -- 판정 57(adj-rec-a · 2026-09-28) — 팩 회복 칸 행
  v_r  jsonb;  v_pl_id bigint;  v_rq numeric;  v_bin uuid;  v_bin_name text;  v_recovered_rows int := 0;
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

  -- ②′ 팩 회복 칸 행(판정 57 · adj-rec-a 2026-09-28) — 픽을 넘겨 채운 낱개는 어느 칸에서 왔는지 남긴다 = 픽커가 뽑은 것과 같은 기록(wms_pick_line_bins planned=false · pack_task_id = 이 팩) ⇒ 출고(wms_so_handoff Σ칸) · 원장(so_ship) · P(inv_adjust_picked)가 저절로 맞는다
  --    p_recovered [{sku, bin_id | bin, qty}] · ⚠️ 옛 모양(['SKU'] · 캐시된 옛 화면)은 거부 — 칸 없이 조용히 완료되지 않게(fail-closed)
  if exists (select 1 from jsonb_array_elements(coalesce(p_recovered, '[]'::jsonb)) e where jsonb_typeof(e) <> 'object') then
    raise exception 'Reload the packing screen (Ctrl+F5) — this version cannot record where recovered stock came from — nothing was saved';
  end if;
  for v_r in select e from jsonb_array_elements(coalesce(p_recovered, '[]'::jsonb)) e loop
    select pl.id into v_pl_id from public.wms_pick_task_lines pl join public.so_line sl on sl.id = pl.order_line_id
     where pl.pick_task_id = v_pick_task_id and sl.sku = v_r->>'sku' order by pl.id limit 1;                      -- 줄마다 과제 하나(wms_batch_create) — 첫 줄
    if v_pl_id is null then raise exception 'Recovered % is not a line of this batch — nothing was saved', v_r->>'sku'; end if;
    if (v_r->>'qty') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' or (v_r->>'qty')::numeric <= 0 then raise exception 'Recovered % needs a positive qty — nothing was saved', v_r->>'sku'; end if;
    v_rq := (v_r->>'qty')::numeric;  v_bin := null;
    if nullif(v_r->>'bin_id', '') is not null then select rb.id, rb.name into v_bin, v_bin_name from public.ref_bin rb where rb.id = (v_r->>'bin_id')::uuid and rb.warehouse_id = v_wh and rb.is_active;
    else select rb.id, rb.name into v_bin, v_bin_name from public.ref_bin rb where rb.name = trim(v_r->>'bin') and rb.warehouse_id = v_wh and rb.is_active; end if;
    if v_bin is null then raise exception 'Recovered %: bin % is not an active bin at this warehouse — nothing was saved', v_r->>'sku', coalesce(v_r->>'bin', v_r->>'bin_id', '?'); end if;
    insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at, pack_task_id)
    values (v_pl_id, v_bin, v_bin_name, v_rq, false, v_worker, v_now, p_task_id);
    v_recovered_rows := v_recovered_rows + 1;
  end loop;
  -- 줄마다 대조 — 팩 verified = Σ실제 칸(픽커 + 이 팩의 회복)이어야 한다(넘치면 칸을 안 줬다 · 모자라면 회복을 너무 많이 줬다) · 회복 없이 verified ≤ 픽 칸 합은 정상(short_after_pack)
  select string_agg(format('%s packed %s, picked %s + recovered %s', t.sku, t.vb, t.pk, t.rc), '; ') into v_bad
    from (select sl.sku, kl.verified_base as vb,
                 coalesce((select sum(b.qty_base) from public.wms_pick_line_bins b join public.wms_pick_task_lines pl on pl.id = b.pick_task_line_id where pl.pick_task_id = v_pick_task_id and pl.order_line_id = kl.order_line_id and not b.planned and b.pack_task_id is null), 0) as pk,
                 coalesce((select sum(b.qty_base) from public.wms_pick_line_bins b where b.pack_task_id = p_task_id and b.pick_task_line_id in (select pl.id from public.wms_pick_task_lines pl where pl.pick_task_id = v_pick_task_id and pl.order_line_id = kl.order_line_id)), 0) as rc
            from public.wms_pack_task_lines kl join public.so_line sl on sl.id = kl.order_line_id where kl.pack_task_id = p_task_id) t
   where (t.rc = 0 and t.vb > t.pk) or (t.rc > 0 and t.vb <> t.pk + t.rc);
  if v_bad is not null then raise exception 'Recovered quantity does not match packed minus picked (%) — give the bin the extra came from — nothing was saved', v_bad; end if;

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
    from (select distinct e->>'sku' as sku from jsonb_array_elements(coalesce(p_recovered, '[]'::jsonb)) e) as s
   where d.order_id = v_order_id and d.sku = s.sku
     and d.reason = 'short_pick' and d.resolved_at is null and d.voided_at is null;                      -- 판정 57: 새 모양 [{sku, bin, qty}] 의 sku
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
    'recovered_resolved', v_recovered_resolved,
    'recovered_rows', v_recovered_rows);
end
$$;
comment on function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb, text) is
  '⑤-2a2 팩 완료(원본 wms_legacy.wms_complete_pack) + 판정 57(adj-rec-a 2026-09-28) — 첫 줄 ims_require_write(packing) · ims_can_warehouse · reason 셋만 · CAS 첫 쓰기 · 0행 = {completed:false, worker, reason} · 줄 저장 · ⭐ p_recovered [{sku, bin_id|bin, qty}] = 픽을 넘겨 채운 낱개의 칸 → wms_pick_line_bins planned=false · pack_task_id = 이 팩(픽커 행과 같은 기록 · 출고 · 원장 · P 가 맞는다) · 옛 모양([''SKU''])은 거부(캐시된 옛 화면 fail-closed) · 줄마다 verified = 픽 칸 합 + 회복 합 대조 · 실수 · 신고 정리 · short_pick → resolved_pack_recovery · ready = 뷰 all_packed';

-- ═══ ③ wms_rollback 재발행 — 20260927214447:387~479 바이트 그대로 · 더한 줄 2(pack: 회복 행 archive → 삭제) ═══
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
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_so.so_number, null, 'wms_pick_line_bins', format('pack_task_id = any(%L::bigint[])', v_ids));   -- 판정 57: 팩 회복 칸 행도 팩과 함께 간다(archive → 삭제 · FK cascade 는 안전망)
    delete from public.wms_pick_line_bins where pack_task_id = any(v_ids);
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

-- ═══ ④ wms_rollback_batch 재발행 — 20260926204246:604~651 바이트 그대로 · 더한 줄 2(pack: 이 팩의 회복 행 archive → 삭제) · create → create or replace ═══
create or replace function public.wms_rollback_batch(p_task_id bigint, p_kind text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_pack constant text[] := array['short_after_pack', 'over_pick', 'pack_scan_mistake'];
  v_staff uuid;  v_so public.so%rowtype;  v_label text;  v_orig uuid;  v_so_id uuid;
  v_arch int := 0;  v_void int := 0;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');
  v_staff := public.so_current_staff();
  if p_kind not in ('pack', 'pick') then raise exception 'Unknown batch rollback kind % — nothing was saved', p_kind; end if;
  if p_kind = 'pack' then select k.order_id, k.batch_label, k.assigned_to into v_so_id, v_label, v_orig from public.wms_pack_tasks k where k.id = p_task_id;
  else select t.order_id, t.batch_label, t.assigned_to into v_so_id, v_label, v_orig from public.wms_pick_tasks t where t.id = p_task_id; end if;
  if v_so_id is null then raise exception 'Task not found — nothing was saved'; end if;
  select * into v_so from public.so s where s.id = v_so_id for update;
  if not public.ims_can_warehouse(v_so.location_id) then              -- ⭐ 둘째
    raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_so.so_number;
  end if;
  if v_so.status = 'packed' or exists (select 1 from public.wms_order_finalize f where f.order_id = v_so_id) then
    raise exception 'Order % is finalized — use Undo Finalize first — nothing was saved', v_so.so_number;
  end if;
  if p_kind = 'pack' then
    if exists (select 1 from public.wms_pallet_items i where i.pack_task_id = p_task_id) then raise exception 'Batch % is on a pallet — Undo Fulfillment first — nothing was saved', v_label; end if;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', v_so_id, v_so.so_number, v_label, 'wms_pack_tasks', format('id = %L', p_task_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', v_so_id, v_so.so_number, v_label, 'wms_pack_task_lines', format('pack_task_id = %L', p_task_id));
    v_void := public.wms_rb_void(v_staff, 'pack_task_id', array[p_task_id], c_pack, 'pack rollback ' || v_label);
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', v_so_id, v_so.so_number, v_label, 'wms_pick_line_bins', format('pack_task_id = %L', p_task_id));   -- 판정 57: 이 팩의 회복 칸 행
    delete from public.wms_pick_line_bins where pack_task_id = p_task_id;
    delete from public.wms_pack_tasks where id = p_task_id;             -- 배치 단위는 회복을 재개하지 않는다(규칙 14 · 남은 팩이 있다)
  else
    if exists (select 1 from public.wms_pack_tasks k where k.pick_task_id = p_task_id) then raise exception 'Batch % already has packing — Undo Pack first — nothing was saved', v_label; end if;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', v_so_id, v_so.so_number, v_label, 'wms_pick_tasks', format('id = %L', p_task_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', v_so_id, v_so.so_number, v_label, 'wms_pick_task_lines', format('pick_task_id = %L', p_task_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', v_so_id, v_so.so_number, v_label, 'wms_pick_line_bins', format('not planned and pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = %L)', p_task_id));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', array[p_task_id], array['short_pick'], 'pick reset ' || v_label);
    delete from public.wms_pick_line_bins b where not b.planned and b.pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = p_task_id);
    update public.wms_pick_task_lines set picked_base = 0, status = 'pending', verification_method = null, picked_at = null, picked_by = null where pick_task_id = p_task_id;
    update public.wms_pick_tasks set status = 'pending', assigned_to = null, started_at = null, completed_at = null, completed_by = null, heartbeat_at = null, work_started = false, held_by = null, session_id = null where id = p_task_id;
  end if;
  insert into public.wms_rollback_log (order_id, order_number, action, from_stage, to_stage, performed_by, batch_label, original_worker)
  values (v_so_id, v_so.so_number, p_kind, case p_kind when 'pack' then 'pack_complete' else 'pick_complete' end, case p_kind when 'pack' then 'pick_complete' else 'pick_reset' end, v_staff, v_label, v_orig);
  return jsonb_build_object('so_id', v_so_id, 'so_number', v_so.so_number, 'batch_label', v_label, 'kind', p_kind, 'archived', v_arch, 'voided', v_void);
end;
$$;
comment on function public.wms_rollback_batch(bigint, text) is
  '⑤-2b 배치 단위 되돌리기(⬜9 · 운영 doBatchRollback) — wms_manage · manager 이상 · 창고 · pack: 그 팩 과제·줄 삭제 + 팩 실수 셋 무효화(회복 재개는 안 한다 · 규칙 14) · 팔렛에 담긴 배치는 거부 · pick: 그 픽 과제 줄 0 · pending · 실제 칸 행 삭제 + short_pick 무효화 · 팩이 있으면 거부 · Finalize 뒤는 거부 · SO 상태 무변(picking)';
revoke all on function public.wms_rollback_batch(bigint, text) from public, anon;
grant execute on function public.wms_rollback_batch(bigint, text) to authenticated;
