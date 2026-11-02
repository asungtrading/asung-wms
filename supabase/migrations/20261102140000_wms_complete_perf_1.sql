-- ─────────────────────────────────────────────────────────────
-- wms-complete-perf-1 — 픽 줄 저장 · 픽 Complete 가 느리다(Asung-IMS · 2026-11-02 오후 · 창고 직원 · 지시서 wms-complete-perf-0 §0 진단 → A 최소 수리)
--   증상: 16:37 UTC 리셋 뒤 pg_stat_statements — wms_pick_line_save 221 회 평균 219 ms(스캔마다) · wms_complete_pick 3 회 평균 5,107 ms(40 줄 TRF-00003-6 · 7 ≈ 7.5 s · 1 줄 ≈ 0.2 s).
--        화면은 창구를 한 번만 부른다(픽 Complete = ensureMine → waitSaves → wms_complete_pick 1 회) · 트리거는 wms_pick_* · wms_pack_* · wms_waves 에 0 개 — 범인은 창구 안이다.
--   범인: 속 함수 wms_pick_line_bins_write ② 가 칸마다 장부 수량(ledger_qty · 경고 ledger_short · 판정 123)을 ims_inv_balance 뷰에서 읽는다.
--        그 뷰는 inv_balance(inv_snapshot 13,844 + inv_ledger 96,712 행을 sku · warehouse · bin 으로 GROUP BY) 뒤에 product · ref_warehouse · ref_bin 을 이름으로 붙이므로
--        product_id · warehouse_id · bin_id 술어를 집계 안으로 못 밀어 넣는다 → 호출마다 110,556 행 HashAggregate(work_mem 3.5 MB · 디스크 5 batches) = 줄 하나 183 ~ 316 ms.
--        wms_complete_pick 은 줄마다 이 함수를 부른다 → 40 줄 × ~190 ms ≈ 7.5 s. 같은 키를 인덱스(inv_snapshot_uq · inv_ledger_sku_wh_on_idx)로 직접 세면 0.2 ms.
--        옛 WMS(wms_legacy.wms_complete_pick)는 장부를 읽지 않았다 — 차이는 전부 ② 다.
--   고침(결과 그대로 — 실제 칸 행 629 개 전부 뷰 값 = 직접 조회 값 · 차이 0):
--     ① wms_pick_line_bins_write ② — ims_inv_balance 조인 → 키 직접 조회(sku = product(v_pid).sku · warehouse = ref_warehouse(p_wh).name · bin = ref_bin.name ·
--        수량 = inv_snapshot(baseline_snapshot_key) 합 + inv_ledger qty_delta 합 = inv_balance 뷰의 정의 그대로) · v_pid 도 wms_order_doc_line 뷰(Append 1,848 행 · 8 ms) 대신 so_line / inv_transfer_line 직접.
--     ② 새 인자 p_with_ledger boolean default true — false 면 ② 전체를 건너뛰고 bins '[]' · warnings '[]' 를 돌려준다. 서명이 바뀌므로 6-인자 판은 drop(남기면 6-인자 호출이 모호).
--     ③ wms_complete_pick ③′ 는 false 로 부른다 — 완료는 v_bw 의 mode · rows 만 쓴다(bins · warnings 는 줄 저장 창구의 것). 본문 그 밖은 DB prosrc 바이트 그대로(md5 8927c009aca65c26170cd2f60a2ce8fe = 20260930172829:184).
--   마지막 정의: wms_pick_line_bins_write 20261023131028_bgr_1a_bgrade_bins.sql:543(DB md5 e14562afd1e68f524ea803e768c9ae55) · wms_complete_pick 20260930172829_pick_bin_1_line_save.sql:184.
--   권한 그대로: bins_write 는 속 함수(판정 31 revoke · postgres · service_role 만) · complete_pick 은 create or replace 라 acl · 소유자 그대로(authenticated execute).
--   무접촉: wms_pick_line_save(6-인자 호출 → default true 로 종전과 같은 반환) · ims_inv_balance 뷰 · 다른 호출자(wms_pick_lines · so_pick_plan · stk_* — B 안 · deferred 450) · 화면.
--   틀리면: 경고(ledger_short · ledger_qty)의 값만 틀린다 — 재고 · 픽 수량 쓰기에는 닿지 않는다.
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) wms_pick_line_bins_write — 서명 변경(p_with_ledger) → 6-인자 판 drop 후 새로 만든다 ═══
drop function if exists public.wms_pick_line_bins_write(bigint, numeric, jsonb, uuid, uuid, timestamptz);
create function public.wms_pick_line_bins_write(p_line_id bigint, p_picked numeric, p_bins jsonb, p_wh uuid, p_worker uuid, p_now timestamptz, p_with_ledger boolean default true)
 returns jsonb
 language plpgsql volatile
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_b jsonb;  v_pl record;
  v_sum numeric := 0;  v_n int := 0;  v_rem numeric;  v_qty numeric;
  v_bin uuid;  v_bin_name text;  v_first uuid;  v_first_name text;
  v_mode text;  v_pid uuid;  v_out jsonb;  v_warn text[] := '{}';
  v_sku text;  v_wh_name text;  v_bkey text;                                          -- perf-1 — 장부 키(sku · 창고 이름 · 기준 스냅샷 키)
begin
  if p_picked is null or p_picked < 0 then raise exception 'Line %: picked quantity must be 0 or more — nothing was saved', p_line_id; end if;
  -- ① 갈래: bins 가 왔으면 교체(given) · 안 왔으면 이미 적힌 실제 행(pack_task_id null)의 합 = picked 면 그대로(kept · 판정 121) · 없거나 다르면 계획 칸 순서(planned · 옛 화면 그대로)
  if jsonb_typeof(p_bins) = 'array' and jsonb_array_length(p_bins) > 0 then
    v_mode := 'given';
  else
    select coalesce(sum(x.qty_base), 0), count(*) into v_sum, v_n
      from public.wms_pick_line_bins x where x.pick_task_line_id = p_line_id and not x.planned and x.pack_task_id is null;
    v_mode := case when v_n > 0 and p_picked > 0 and v_sum = p_picked then 'kept' else 'planned' end;
  end if;
  if v_mode <> 'kept' then
    delete from public.wms_pick_line_bins x where x.pick_task_line_id = p_line_id and not x.planned and x.pack_task_id is null;   -- 팩 회복 행(pack_task_id)은 손대지 않는다
    v_sum := 0;  v_n := 0;
    if p_picked > 0 and v_mode = 'given' then
      for v_b in select * from jsonb_array_elements(p_bins) loop
        v_qty := coalesce((v_b->>'qty_base')::numeric, 0);
        if v_qty <= 0 then raise exception 'Line %: a bin row has qty_base <= 0 — nothing was saved', p_line_id; end if;
        v_bin := null;  v_bin_name := null;
        if v_b ? 'bin_id' then
          select rb.id, rb.name into v_bin, v_bin_name from public.ref_bin rb where rb.id = (v_b->>'bin_id')::uuid and rb.warehouse_id = p_wh;
        else
          select rb.id, rb.name into v_bin, v_bin_name from public.ref_bin rb where rb.name = trim(v_b->>'bin') and rb.warehouse_id = p_wh;
        end if;
        if v_bin is null then raise exception 'Line %: bin % is not in this warehouse — nothing was saved', p_line_id, coalesce(v_b->>'bin', v_b->>'bin_id'); end if;
        if (select rb.is_bgrade from public.ref_bin rb where rb.id = v_bin) then            -- bgr-1a 판정 635: 정상 오더 줄에 B급 칸 저장 거부(B급은 POS 에서만)
          raise exception 'Line %: bin % is a B-grade bin — B-grade stock is sold at POS only, pick from a regular bin — nothing was saved', p_line_id, v_bin_name;
        end if;
        insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at)
        values (p_line_id, v_bin, v_bin_name, v_qty, false, p_worker, p_now);
        v_n := v_n + 1;  v_sum := v_sum + v_qty;
      end loop;
      if v_sum <> p_picked then raise exception 'Line %: bin quantities (%) do not add up to picked (%) — nothing was saved', p_line_id, v_sum, p_picked; end if;
    elsif p_picked > 0 then
      v_rem := p_picked;  v_first := null;
      for v_pl in select x.bin_id, x.bin, x.qty_base from public.wms_pick_line_bins x where x.pick_task_line_id = p_line_id and x.planned order by x.id loop
        if v_first is null then v_first := v_pl.bin_id; v_first_name := v_pl.bin; end if;
        exit when v_rem <= 0;
        insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at)
        values (p_line_id, v_pl.bin_id, v_pl.bin, least(v_rem, v_pl.qty_base), false, p_worker, p_now);
        v_n := v_n + 1;  v_rem := v_rem - least(v_rem, v_pl.qty_base);
      end loop;
      if v_rem > 0 and v_first is not null then                      -- 계획보다 많이 뽑았다 → 첫 계획 칸이 나머지를 받는다
        insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at)
        values (p_line_id, v_first, v_first_name, v_rem, false, p_worker, p_now);
        v_n := v_n + 1;  v_rem := 0;
      end if;
      if v_rem > 0 then raise exception 'Line %: no bins given and no planned bins to fall back on — nothing was saved', p_line_id; end if;
    end if;
  end if;
  -- ② 반환 — 칸마다 장부(낱개 EA · 이 픽은 출고 전이라 아직 안 빠진 값) · is_active · 경고(판정 123 — 막지 않는다)
  --    perf-1: p_with_ledger=false(완료 창구 — mode · rows 만 쓴다)면 여기서 끝 · 장부 수량은 ims_inv_balance 뷰(호출마다 장부 전체 집계 · 180 ~ 320 ms) 대신
  --    inv_balance 의 정의 그대로 키로 직접 센다 — inv_snapshot(baseline_snapshot_key) 합 + inv_ledger qty_delta 합 · 키 = product(v_pid).sku · ref_warehouse(p_wh).name · ref_bin.name(빈 칸 이름은 없다)
  if not p_with_ledger then
    return jsonb_build_object('mode', v_mode, 'rows', v_n, 'bins', '[]'::jsonb, 'warnings', '[]'::jsonb);
  end if;
  select coalesce(pr.parent_product_id, pr.id) into v_pid                                   -- perf-1 — wms_order_doc_line 뷰(Append 전체) 대신 줄 표 직접 · 픽 줄은 콤보 부모를 가리키지 않는다
    from public.wms_pick_task_lines pl
    left join public.so_line sl on sl.id = pl.order_line_id
    left join public.inv_transfer_line tl on tl.id = pl.transfer_line_id
    join public.product pr on pr.id = coalesce(sl.product_id, tl.product_id)
   where pl.id = p_line_id;
  select p.sku into v_sku from public.product p where p.id = v_pid;
  select w.name into v_wh_name from public.ref_warehouse w where w.id = p_wh;
  select c.value into v_bkey from public.inv_config c where c.key = 'baseline_snapshot_key';
  select coalesce(jsonb_agg(jsonb_build_object('bin_id', x.bin_id, 'bin', x.bin, 'qty_base', x.qty_base, 'ledger_qty', v.qty, 'is_active', rb.is_active,
                                               'planned', exists (select 1 from public.wms_pick_line_bins q where q.pick_task_line_id = p_line_id and q.planned and q.bin_id = x.bin_id))
                            order by x.id), '[]'::jsonb),
         coalesce(array_agg(format('ledger_short:%s:%s<%s', x.bin, v.qty, x.qty_base) order by x.id) filter (where v.qty < x.qty_base), '{}')
         || coalesce(array_agg(format('inactive_bin:%s', x.bin) order by x.id) filter (where not rb.is_active), '{}')
    into v_out, v_warn
    from public.wms_pick_line_bins x
    join public.ref_bin rb on rb.id = x.bin_id
    cross join lateral (
      select coalesce((select sum(s.qty)       from public.inv_snapshot s where s.snapshot_key = v_bkey and s.sku = v_sku and s.warehouse = v_wh_name and coalesce(s.bin, '') = rb.name), 0)
           + coalesce((select sum(l.qty_delta) from public.inv_ledger   l where l.sku = v_sku and l.warehouse = v_wh_name and coalesce(l.bin, '') = rb.name), 0) as qty
    ) v
   where x.pick_task_line_id = p_line_id and not x.planned and x.pack_task_id is null;
  return jsonb_build_object('mode', v_mode, 'rows', v_n, 'bins', v_out, 'warnings', to_jsonb(v_warn));
end
$function$;
comment on function public.wms_pick_line_bins_write(bigint, numeric, jsonb, uuid, uuid, timestamptz, boolean) is
  'pick-bin-2(판정 121 · 123) 실제 칸 행(wms_pick_line_bins planned=false · pack_task_id null)의 유일한 쓰기 식 — 완료 창구 wms_complete_pick ③′ 와 줄 저장 창구 wms_pick_line_save 가 부른다. bins 가 오면 교체(검사 셋: qty_base > 0 · 그 창고 칸 · 합 = picked) · 안 오면 이미 적힌 행의 합 = picked 면 그대로(kept) · 없거나 다르면 계획 칸 순서(planned · 옛 화면 그대로). 장부 재고 · is_active 는 막지 않고 반환 bins[].ledger_qty · is_active 와 warnings 로 알린다(판정 123). perf-1(2026-11-02): 장부 수량은 키(sku · 창고 이름 · 칸 이름)로 inv_snapshot + inv_ledger 를 직접 센다(ims_inv_balance 뷰는 호출마다 장부 전체 집계) · p_with_ledger=false 면 장부 조회를 건너뛰고 bins · warnings 를 비운다(완료 창구). 팩 회복 행은 손대지 않는다. 속 함수 — 판정 31 revoke · 부르는 창구가 권한 · 창고 · CAS 를 지킨다.';
revoke all on function public.wms_pick_line_bins_write(bigint, numeric, jsonb, uuid, uuid, timestamptz, boolean) from public, anon, authenticated;   -- ⭐ 판정 31 — 속 함수(definer 창구 둘이 소유자로 부른다)

-- ═══ 2) wms_complete_pick — ③′ 호출에 false 한 곳만 · 그 밖은 DB prosrc 바이트 그대로(create or replace · acl · comment 유지) ═══
create or replace function public.wms_complete_pick(p_lines jsonb, p_task_id bigint default null, p_wave_id bigint default null, p_mistakes jsonb default '[]'::jsonb, p_short_refresh jsonb default '[]'::jsonb, p_short_delete jsonb default '[]'::jsonb, p_session_id text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $function$
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
  v_bins_kept       int := 0;
  v_e       jsonb;  v_bw jsonb;                                      -- ⚠️ 별칭 e·b(줄 저장 서브쿼리)와 겹치지 않게 v_ 접두
  v_line_id bigint;  v_pb numeric;
begin
  perform public.ims_require_write('picking', 'saved');               -- ⭐ 첫 줄
  v_worker := public.so_current_staff();
  if (p_task_id is null) = (p_wave_id is null) then
    raise exception 'Pass exactly one of p_task_id / p_wave_id — nothing was saved';
  end if;
  -- 창고 제한 — 과제 오더의 창고 · 웨이브는 웨이브 행의 창고
  select case when p_wave_id is not null then (select w.warehouse_id from public.wms_waves w where w.id = p_wave_id)
              else (select d.warehouse_id from public.wms_pick_tasks t join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id) where t.id = p_task_id) end into v_wh;
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

  select coalesce(array_agg(distinct coalesce(order_id, transfer_id)), '{}') into v_order_ids from public.wms_pick_tasks where id = any(v_task_ids);

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

  -- ③′ 실제 칸 행(⑤-2a2 · pick-bin-2 판정 121) — 줄마다 속 함수 wms_pick_line_bins_write: bins 가 오면 교체 · 안 오면 줄 저장이 적은 행(pack_task_id null · 합 = picked_base)은 그대로 · 없거나 합이 다르면 계획 칸 순서로
  for v_e in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    v_line_id := (v_e->>'id')::bigint;  v_pb := (v_e->>'picked_base')::numeric;
    v_bw := public.wms_pick_line_bins_write(v_line_id, v_pb, v_e->'bins', v_wh, v_worker, v_now, false);   -- perf-1 — 완료는 mode · rows 만 쓴다 → 장부 조회(②) 건너뜀
    if v_bw->>'mode' = 'kept' then v_bins_kept := v_bins_kept + 1; else v_bins_inserted := v_bins_inserted + (v_bw->>'rows')::int; end if;
  end loop;

  -- ④ short_pick 생성 — reason 고정 · order_number 는 서버 유도(so_number) → wms_worker_mistakes
  insert into public.wms_worker_mistakes
        (order_id, transfer_id, pick_task_id, order_number, sku, ordered_base, actual_base, reason, manager_resolved)
  select case when o.doc_kind = 'so' then o.doc_id end, case when o.doc_kind = 'transfer' then o.doc_id end, (d->>'pick_task_id')::bigint, o.doc_number, d->>'sku',
         (d->>'ordered_base')::numeric, (d->>'actual_base')::numeric, 'short_pick', false
    from jsonb_array_elements(coalesce(p_mistakes, '[]'::jsonb)) d
    join public.wms_order_doc o on o.doc_id = (d->>'order_id')::uuid;
  get diagnostics v_disc_inserted = row_count;

  -- ⑤ 선언(stock_short) 정리 — wms_reports kind stock_short · UPDATE/DELETE 0행 = 자연 no-op
  update public.wms_reports d
     set qty_expected = (r->>'ordered_base')::numeric, qty_found = (r->>'actual_base')::numeric
    from jsonb_array_elements(coalesce(p_short_refresh, '[]'::jsonb)) r
   where coalesce(d.order_id, d.transfer_id) = (r->>'order_id')::uuid and d.sku = r->>'sku'
     and d.kind = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_refreshed = row_count;

  delete from public.wms_reports d
   using jsonb_array_elements(coalesce(p_short_delete, '[]'::jsonb)) r
   where coalesce(d.order_id, d.transfer_id) = (r->>'order_id')::uuid and d.sku = r->>'sku'
     and d.kind = 'stock_short' and d.resolved_at is null;
  get diagnostics v_short_deleted = row_count;

  return jsonb_build_object(
    'completed', true,
    'worker', v_worker,
    'mode', case when p_wave_id is not null then 'wave' else 'single' end,
    'members_completed', v_members_completed,
    'lines_updated', v_lines_updated,
    'bins_inserted', v_bins_inserted,
    'bins_kept', v_bins_kept,
    'disc_inserted', v_disc_inserted,
    'short_refreshed', v_short_refreshed,
    'short_deleted', v_short_deleted);
end
$function$;
comment on function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb, text) is
  '⑤-2a2 픽 완료(원본 wms_legacy.wms_complete_pick) — 첫 줄 ims_require_write(picking) · ims_can_warehouse · CAS(assigned_to = 나 · in_progress · session) 첫 쓰기 · 0행 = {completed:false, worker, reason other_device} · 웨이브는 wave 행 CAS + 멤버 일괄 · 줄 저장(행 수 검사) · ⊕ 실제 칸 행 wms_pick_line_bins planned=false = 속 함수 wms_pick_line_bins_write(pick-bin-2 판정 121: bins 오면 교체 · 안 오면 줄 저장이 적은 행(합 = picked_base)은 그대로 kept · 없거나 다르면 계획 칸 순서 · perf-1: p_with_ledger=false — 완료는 mode · rows 만 쓴다) · 반환 bins_inserted · bins_kept · short_pick → wms_worker_mistakes(p_mistakes) · stock_short 선언 → wms_reports refresh/delete(판정 20) · SO 상태는 안 바꾼다';

-- ═══ 3) 자기 검사 — 서명 하나 · 권한 · 줄 저장 창구 무접촉 · 완료가 false 로 부른다 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_pick_line_bins_write') <> 1 then v_bad := v_bad || ' overloads'; end if;
  if (select pg_get_function_identity_arguments(oid) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_pick_line_bins_write')
     <> 'p_line_id bigint, p_picked numeric, p_bins jsonb, p_wh uuid, p_worker uuid, p_now timestamp with time zone, p_with_ledger boolean' then v_bad := v_bad || ' signature'; end if;
  if has_function_privilege('authenticated', 'public.wms_pick_line_bins_write(bigint, numeric, jsonb, uuid, uuid, timestamptz, boolean)', 'execute') then v_bad := v_bad || ' acl_bins_write'; end if;
  if not has_function_privilege('authenticated', 'public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb, text)', 'execute') then v_bad := v_bad || ' acl_complete_pick'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_pick_line_save') <> 'cf534f4be44edc83d32c1b95a0ca57d6' then v_bad := v_bad || ' line_save_changed'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_complete_pick') !~ 'v_wh, v_worker, v_now, false\)' then v_bad := v_bad || ' complete_pick_call'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_pick_line_bins_write') ~ 'public\.ims_inv_balance|public\.wms_order_doc_line' then v_bad := v_bad || ' view_still_used'; end if;
  if v_bad <> '' then raise exception 'wms-complete-perf-1 self-check failed:%', v_bad; end if;
end $$;
