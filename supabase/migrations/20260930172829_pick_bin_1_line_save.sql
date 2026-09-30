-- pick-bin-2(판정 121 ~ 124 · 2026-09-30) — ⑫ 「피커가 다른 칸에서 뽑아도 계획 칸이 적힌다」 DB 차수: 줄 저장마다 실제 칸 · 칸 목록 · 보고 칸 셋
--   판정 121: 실제로 뽑은 칸은 줄을 저장할 때마다 DB 에 적는다 — 새 창구 wms_pick_line_save(줄 저장 + 실제 칸 행 교체) · 보류 · 이어받기 · 다른 기기에도 칸이 남는다 · 판정 62 셈(inv_move_open_plans · unwritten = picked − Σactual)이 실시간
--   판정 122: 다른 칸을 알리는 방법 = 「Different bin」 → 그 SKU 가 있는 칸 목록(계획 칸 먼저 · 장부 재고 있는 칸 · 목록에 없는 칸은 타자) — wms_pick_lines 에 줄마다 stock_bins
--   판정 123: 장부 재고가 없거나 모자라도 · 비활성 칸도 받고 경고만(반환 bins[].ledger_qty · is_active · warnings) · 창고 검사는 그대로 · 칸 장부 음수는 보이게(Health bin_negative)
--   판정 124: 칸을 바꾸는 창의 체크 「Planned bin was empty」 때만 wrong_location 보고를 자동으로 — wms_reports 칸 셋 planned_bin · found_bin · bin_qty(wrong_location 에만 · CHECK)
--   ① wms_pick_line_bins_write(속 함수 · 판정 31 revoke) — 실제 칸 행의 유일한 쓰기 식: 완료 창구 ③′ 의 bins 경로 · 계획 채우기(20260928234815:606~639)를 옮겨 왔다 + kept 갈래(줄 저장이 적은 행 · 합 = picked 면 그대로)
--   ② wms_pick_line_save(새 창구 · authenticated) — 권한 문(ims_require_write picking) · 창고 · 과제 상태(in_progress 만 · completed · held 거부 문구) · CAS = 줄 행 갱신을 과제 조건 아래에서만(0행 = saved:false + reason) · 그 뒤 ① · 웨이브 멤버 줄 · 트랜스퍼 과제 줄 같은 길
--   ③ wms_complete_pick 재발행(마지막 정의 20260928234815:486..677 · md5 f5a4079b…) — ③′ 만 ① 호출로(옛 화면: bins 없음 · 줄 저장 없음 → planned 갈래 = 지금 규칙 그대로) · 반환 bins_kept 추가 · 나머지 줄 무변
--   ④ wms_pick_lines 재발행(마지막 정의 20260928234815:377..483 · md5 93c9260f…) — CTE sbal · sb 와 반환 키 stock_bins 만 추가 · 부르는 화면(피커 · 팩커 · 풀필먼트)은 키로 읽어 무영향
--   ⑤ wms_reports 칸 셋 + CHECK 둘
--   부딪히지 않는 증명: 두 창구 모두 「줄 행 UPDATE(행 잠금) → 실제 칸 행 교체」 순서 · 같은 줄의 저장 둘 · 저장과 완료는 줄 행 잠금에서 직렬 · 완료가 먼저면 과제 completed 라 저장이 거부 · 저장이 먼저면 완료(bins 없음)가 kept 로 그 행을 둔다
--   검증: ~/asung/prompts/pick-bin-2-verify.sql(시험 적용 · 확인 · 마른 실행 세 갈래 · 전부 rollback)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음(psql 트랜잭션 · db push 가 감싼다)

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


-- ═══ 1) wms_pick_line_bins_write — 실제 칸 행의 유일한 쓰기 자리(속 함수 · 판정 31 revoke) — 완료 창구 ③′ 와 줄 저장 창구가 같은 식을 부른다 ═══
create function public.wms_pick_line_bins_write(p_line_id bigint, p_picked numeric, p_bins jsonb, p_wh uuid, p_worker uuid, p_now timestamptz) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare
  v_b jsonb;  v_pl record;
  v_sum numeric := 0;  v_n int := 0;  v_rem numeric;  v_qty numeric;
  v_bin uuid;  v_bin_name text;  v_first uuid;  v_first_name text;
  v_mode text;  v_pid uuid;  v_out jsonb;  v_warn text[] := '{}';
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
  -- ② 반환 — 칸마다 장부(ims_inv_balance · 낱개 EA · 이 픽은 출고 전이라 아직 안 빠진 값) · is_active · 경고(판정 123 — 막지 않는다)
  select coalesce(pr.parent_product_id, pr.id) into v_pid
    from public.wms_pick_task_lines pl join public.wms_order_doc_line l on l.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
    join public.product pr on pr.id = l.product_id where pl.id = p_line_id;
  select coalesce(jsonb_agg(jsonb_build_object('bin_id', x.bin_id, 'bin', x.bin, 'qty_base', x.qty_base, 'ledger_qty', coalesce(v.qty, 0), 'is_active', rb.is_active,
                                               'planned', exists (select 1 from public.wms_pick_line_bins q where q.pick_task_line_id = p_line_id and q.planned and q.bin_id = x.bin_id))
                            order by x.id), '[]'::jsonb),
         coalesce(array_agg(format('ledger_short:%s:%s<%s', x.bin, coalesce(v.qty, 0), x.qty_base) order by x.id) filter (where coalesce(v.qty, 0) < x.qty_base), '{}')
         || coalesce(array_agg(format('inactive_bin:%s', x.bin) order by x.id) filter (where not rb.is_active), '{}')
    into v_out, v_warn
    from public.wms_pick_line_bins x
    join public.ref_bin rb on rb.id = x.bin_id
    left join public.ims_inv_balance v on v.bin_id = x.bin_id and v.warehouse_id = p_wh and v.product_id = v_pid
   where x.pick_task_line_id = p_line_id and not x.planned and x.pack_task_id is null;
  return jsonb_build_object('mode', v_mode, 'rows', v_n, 'bins', v_out, 'warnings', to_jsonb(v_warn));
end
$$;
comment on function public.wms_pick_line_bins_write(bigint, numeric, jsonb, uuid, uuid, timestamptz) is
  'pick-bin-2(판정 121 · 123) 실제 칸 행(wms_pick_line_bins planned=false · pack_task_id null)의 유일한 쓰기 식 — 완료 창구 wms_complete_pick ③′ 와 줄 저장 창구 wms_pick_line_save 가 부른다. bins 가 오면 교체(검사 셋: qty_base > 0 · 그 창고 칸 · 합 = picked) · 안 오면 이미 적힌 행의 합 = picked 면 그대로(kept) · 없거나 다르면 계획 칸 순서(planned · 옛 화면 그대로). 장부 재고 · is_active 는 막지 않고 반환 bins[].ledger_qty · is_active 와 warnings 로 알린다(판정 123). 팩 회복 행은 손대지 않는다. 속 함수 — 판정 31 revoke · 부르는 창구가 권한 · 창고 · CAS 를 지킨다.';
revoke all on function public.wms_pick_line_bins_write(bigint, numeric, jsonb, uuid, uuid, timestamptz) from public, anon, authenticated;   -- ⭐ 판정 31 — 속 함수(definer 창구 둘이 소유자로 부른다)

-- ═══ 2) wms_pick_line_save — 줄 저장 창구(판정 121) · 화면의 saveLine(줄 직접 UPDATE)을 대신한다 · 줄 하나 = picked_base + 실제 칸 배열 ═══
create function public.wms_pick_line_save(p_line_id bigint, p_picked_base numeric, p_bins jsonb default null, p_status text default null, p_verification_method text default null, p_session_id text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_worker uuid;
  v_now    timestamptz := now();
  v_t      record;
  v_st     text;
  v_upd    bigint;
  v_bw     jsonb;
begin
  perform public.ims_require_write('picking', 'saved');               -- ⭐ 첫 줄(판정 39 · fail-closed)
  v_worker := public.so_current_staff();
  if p_line_id is null or p_picked_base is null or p_picked_base < 0 then
    raise exception 'A pick line id and a picked quantity (0 or more) are needed — nothing was saved';
  end if;
  select t.id, t.status, t.assigned_to, t.session_id, t.wave_id, t.batch_label, d.warehouse_id, l.assigned_base
    into v_t
    from public.wms_pick_task_lines l
    join public.wms_pick_tasks t on t.id = l.pick_task_id
    join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)         -- 공용 목록(판정 71) · 판매 · 트랜스퍼 같은 길(판정 84 는 마무리에서)
   where l.id = p_line_id;
  if v_t.id is null then raise exception 'Pick line % not found — nothing was saved', p_line_id; end if;
  if not public.ims_can_warehouse(v_t.warehouse_id) then                          -- ⭐ 둘째
    raise exception 'This task is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  if v_t.status = 'completed' then
    raise exception 'Batch % is already completed — its lines can no longer be saved — nothing was saved', v_t.batch_label;
  end if;
  if v_t.status <> 'in_progress' then
    raise exception 'Batch % is on hold or not started — open it again before saving — nothing was saved', v_t.batch_label;
  end if;
  if p_status is not null and p_status not in ('pending', 'in_progress', 'picked', 'short') then
    raise exception 'Line status % is not one of pending · in_progress · picked · short — nothing was saved', p_status;
  end if;
  v_st := coalesce(p_status, case when p_picked_base >= v_t.assigned_base then 'picked' when p_picked_base > 0 then 'in_progress' else 'pending' end);
  -- CAS — 줄 행 갱신은 과제 조건(assigned_to = 나 · in_progress · session) 아래에서만 · 0행 = 아무것도 안 썼다(규칙 28) · 줄 행 잠금이 뒤의 칸 행 교체를 완료 창구 ③ → ③′ 와 같은 순서로 세운다
  update public.wms_pick_task_lines l
     set picked_base = p_picked_base, status = v_st, verification_method = nullif(p_verification_method, ''), picked_at = v_now, picked_by = v_worker
    from public.wms_pick_tasks t
   where l.id = p_line_id and t.id = l.pick_task_id
     and t.assigned_to = v_worker and t.status = 'in_progress'
     and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
  returning l.id into v_upd;
  if v_upd is null then
    return jsonb_build_object('saved', false, 'worker', v_worker,
      'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                              and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id then 'other_device'
                             when x.assigned_to is distinct from v_worker then 'not_yours' end
                   from public.wms_pick_tasks x where x.id = v_t.id));
  end if;
  v_bw := public.wms_pick_line_bins_write(p_line_id, p_picked_base, p_bins, v_t.warehouse_id, v_worker, v_now);
  return jsonb_build_object('saved', true, 'worker', v_worker, 'line_id', p_line_id, 'task_id', v_t.id, 'wave_id', v_t.wave_id,
                            'picked_base', p_picked_base, 'status', v_st) || v_bw;
end
$$;
comment on function public.wms_pick_line_save(bigint, numeric, jsonb, text, text, text) is
  'pick-bin-2 줄 저장 창구(판정 121 · 122 · 123) — 픽 줄 하나의 picked_base · status · verification_method 와 실제 칸 배열 [{bin_id 또는 bin, qty_base}] 을 받아 그 줄의 실제 칸 행(planned=false · pack_task_id null)을 통째로 바꾼다(속 함수 wms_pick_line_bins_write · 합 = picked_base · 0 이면 행 없음 · bins 없으면 계획 칸 순서). 첫 줄 ims_require_write(picking) · ims_can_warehouse · 과제 completed/held 는 거부 문구 · CAS = 줄 행 갱신을 과제 조건(assigned_to = 나 · in_progress · session) 아래에서만 · 0행 = {saved:false, worker, reason other_device|not_yours}. 웨이브 멤버 줄 · 트랜스퍼 과제 줄 같은 길. 장부 재고 · 비활성 칸은 막지 않고 bins[].ledger_qty · is_active · warnings 로(판정 123). 스캔마다 불러도 멱등(같은 입력 = 같은 행).';
revoke all on function public.wms_pick_line_save(bigint, numeric, jsonb, text, text, text) from public, anon;
grant execute on function public.wms_pick_line_save(bigint, numeric, jsonb, text, text, text) to authenticated;   -- 화면(wms-picker.html saveLine)이 부른다

-- ═══ 3) wms_complete_pick 재발행 — 마지막 정의 20260928234815_transfer_1b2.sql:486..677 · ③′ 만 속 함수 호출로 · 반환 bins_kept ═══
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
    v_bw := public.wms_pick_line_bins_write(v_line_id, v_pb, v_e->'bins', v_wh, v_worker, v_now);
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
$$;
comment on function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb, text) is
  '⑤-2a2 픽 완료(원본 wms_legacy.wms_complete_pick) — 첫 줄 ims_require_write(picking) · ims_can_warehouse · CAS(assigned_to = 나 · in_progress · session) 첫 쓰기 · 0행 = {completed:false, worker, reason other_device} · 웨이브는 wave 행 CAS + 멤버 일괄 · 줄 저장(행 수 검사) · ⊕ 실제 칸 행 wms_pick_line_bins planned=false = 속 함수 wms_pick_line_bins_write(pick-bin-2 판정 121: bins 오면 교체 · 안 오면 줄 저장이 적은 행(합 = picked_base)은 그대로 kept · 없거나 다르면 계획 칸 순서) · 반환 bins_inserted · bins_kept · short_pick → wms_worker_mistakes(p_mistakes) · stock_short 선언 → wms_reports refresh/delete(판정 20) · SO 상태는 안 바꾼다';
revoke all on function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb, text) from public, anon;
grant execute on function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb, text) to authenticated;

-- ═══ 4) wms_pick_lines 재발행 — 마지막 정의 20260928234815_transfer_1b2.sql:377..483 · stock_bins 만 추가(판정 122) ═══
create or replace function public.wms_pick_lines(p_task_ids bigint[] default null, p_pack_task_id bigint default null) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_task_ids bigint[];
  v_pack_id  bigint := p_pack_task_id;
  v_out      jsonb;
begin
  if (p_task_ids is null or cardinality(p_task_ids) = 0) = (p_pack_task_id is null) then
    raise exception 'Pass exactly one of p_task_ids / p_pack_task_id';
  end if;
  if p_pack_task_id is not null then
    select array[k.pick_task_id] into v_task_ids from public.wms_pack_tasks k where k.id = p_pack_task_id;
    if v_task_ids is null or v_task_ids[1] is null then return '[]'::jsonb; end if;     -- 팩 과제 없음 · 픽 과제 없는 팩 과제 = 빈 배열(깨끗한 빈손)
  else
    v_task_ids := p_task_ids;
  end if;

  with t as (
    select t.id, t.batch_label, coalesce(t.order_id, t.transfer_id) as order_id, t.wave_id, t.tote_no,
           d.doc_number as so_number, d.warehouse_id as location_id, w.name as wh_name, d.party_name as customer_name
    from public.wms_pick_tasks t
    join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
    left join public.ref_warehouse w on w.id = d.warehouse_id
    where t.id = any(v_task_ids)
  ), pl as (
    select l.id as line_id, l.pick_task_id, l.order_line_id, l.transfer_line_id, l.assigned_base, l.picked_base, l.status, l.verification_method, l.picked_by, l.picked_at,
           t.order_id, t.so_number, t.customer_name, t.location_id, t.wh_name, t.batch_label, t.wave_id, t.tote_no,
           x.sku, x.product_name, x.pack_factor,
           coalesce(p.parent_product_id, p.id) as stock_pid, (p.parent_product_id is not null) as is_set
    from public.wms_pick_task_lines l
    join t on t.id = l.pick_task_id
    join public.wms_order_doc_line x on x.line_id = coalesce(l.order_line_id, l.transfer_line_id)
    join public.product p on p.id = x.product_id
  ), pids as (
    select distinct pl.stock_pid from pl
  ), whs as (
    select distinct t.location_id from t where t.location_id is not null
  ), bal as (                                                             -- 창고 전체 잔고 · 한 문장 · 한 번(속도 함정)
    select v.warehouse_id, v.product_id, sum(v.qty) as qty
    from public.ims_inv_balance v
    where v.product_id = any(array(select pids.stock_pid from pids))
      and v.warehouse_id = any(array(select whs.location_id from whs))
    group by v.warehouse_id, v.product_id
  ), bc as (                                                              -- 낱개(factor 1) + 그 낱개를 parent 로 둔 세트들(factor = pack_factor)
    select coalesce(p.parent_product_id, p.id) as stock_pid,
           jsonb_agg(jsonb_build_object('barcode', b.barcode,
                                        'factor', case when p.parent_product_id is null then 1 else coalesce(p.pack_factor, 1) end,
                                        'sku', p.sku)
                     order by case when p.parent_product_id is null then 1 else coalesce(p.pack_factor, 1) end, b.is_primary desc, b.barcode) as arr
    from public.product_barcode b
    join public.product p on p.id = b.product_id
    where b.is_active
      and (p.id = any(array(select pids.stock_pid from pids)) or p.parent_product_id = any(array(select pids.stock_pid from pids)))
    group by coalesce(p.parent_product_id, p.id)
  ), bins as (                                                            -- 계획 칸(planned) · 실제 칸(actual) · 존은 여기 한 곳에서
    select x.pick_task_line_id, x.planned,
           jsonb_agg(jsonb_build_object('bin', x.bin, 'bin_id', x.bin_id, 'qty_base', x.qty_base,
                                        'zone', coalesce(rb.zone,
                                                         case when coalesce(x.bin, '') = '' then ''
                                                              when pl2.wh_name ilike '%edmonton%' and upper(left(x.bin, 1)) = 'E' then upper(substr(x.bin, 2, 1))
                                                              else upper(left(x.bin, 1)) end),
                                        'picked_by', x.picked_by, 'picked_at', x.picked_at)
                     order by x.id) as arr
    from public.wms_pick_line_bins x
    join pl pl2 on pl2.line_id = x.pick_task_line_id
    left join public.ref_bin rb on rb.id = x.bin_id
    group by x.pick_task_line_id, x.planned
  ), sbal as (                                                            -- pick-bin-2(판정 122) 칸 잔고 한 번 · bal 과 같은 술어 · bin 있는 행만(속도 함정)
    select v.warehouse_id, v.product_id, v.bin_id, v.qty, v.bin_is_active
    from public.ims_inv_balance v
    where v.product_id = any(array(select pids.stock_pid from pids))
      and v.warehouse_id = any(array(select whs.location_id from whs))
      and v.bin_id is not null
  ), sb as (                                                              -- 칸 목록 — 계획 칸 전부 + 장부 qty > 0 인 활성 칸 · 계획 먼저(계획 행 순) · 장부 내림 · 이름 · qty 는 낱개(EA)
    select z.line_id,
           jsonb_agg(jsonb_build_object('bin_id', z.bin_id, 'bin', z.bin, 'zone', z.zone, 'qty', z.qty, 'is_active', z.is_active, 'planned', z.planned)
                     order by z.planned desc, z.plan_ord nulls last, z.qty desc, z.bin) as arr
    from (
      select pl3.line_id, rb.id as bin_id, rb.name as bin,
             coalesce(rb.zone, case when coalesce(rb.name, '') = '' then ''
                                    when pl3.wh_name ilike '%edmonton%' and upper(left(rb.name, 1)) = 'E' then upper(substr(rb.name, 2, 1))
                                    else upper(left(rb.name, 1)) end) as zone,
             coalesce(s.qty, 0) as qty, rb.is_active, (pb.min_id is not null) as planned, pb.min_id as plan_ord
      from pl pl3
      join lateral (select s0.bin_id from sbal s0 where s0.product_id = pl3.stock_pid and s0.warehouse_id = pl3.location_id and s0.qty > 0 and s0.bin_is_active
                    union
                    select x.bin_id from public.wms_pick_line_bins x where x.pick_task_line_id = pl3.line_id and x.planned) c on true
      join public.ref_bin rb on rb.id = c.bin_id
      left join sbal s on s.bin_id = c.bin_id and s.product_id = pl3.stock_pid and s.warehouse_id = pl3.location_id
      left join (select x.pick_task_line_id, x.bin_id, min(x.id) as min_id from public.wms_pick_line_bins x where x.planned group by 1, 2) pb
             on pb.pick_task_line_id = pl3.line_id and pb.bin_id = c.bin_id
    ) z
    group by z.line_id
  ), pk as (                                                              -- 팩 갈래 — 팩 줄(order_line_id 로 짝)
    select k.id as pack_line_id, k.order_line_id, k.transfer_line_id, k.expected_base, k.verified_base, k.status as pack_status,
           k.verification_method as pack_verification_method, k.verified_by, k.verified_at
    from public.wms_pack_task_lines k
    where v_pack_id is not null and k.pack_task_id = v_pack_id
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'line_id', case when v_pack_id is null then pl.line_id else pk.pack_line_id end,
             'pick_line_id', pl.line_id,
             'pick_task_id', pl.pick_task_id, 'batch_label', pl.batch_label, 'wave_id', pl.wave_id, 'tote_no', pl.tote_no,
             'order_line_id', coalesce(pl.order_line_id, pl.transfer_line_id), 'so_id', pl.order_id, 'so_number', pl.so_number, 'customer_name', pl.customer_name, 'warehouse_id', pl.location_id,
             'sku', pl.sku, 'base_sku', sp.sku, 'product_name', pl.product_name, 'pack_factor', pl.pack_factor, 'is_set', pl.is_set,
             'assigned_base', pl.assigned_base, 'picked_base', pl.picked_base,
             'status', case when v_pack_id is null then pl.status else pk.pack_status end,
             'verification_method', case when v_pack_id is null then pl.verification_method else pk.pack_verification_method end,
             'picked_by', pl.picked_by, 'picked_at', pl.picked_at,
             'planned_bins', coalesce(bp.arr, '[]'::jsonb), 'actual_bins', coalesce(ba.arr, '[]'::jsonb),
             'stock_bins', coalesce(sb.arr, '[]'::jsonb),
             'barcodes', coalesce(bc.arr, '[]'::jsonb),
             'available_ea', coalesce(bal.qty, 0))
           || case when v_pack_id is null then '{}'::jsonb
                   else jsonb_build_object('pack_line_id', pk.pack_line_id, 'expected_base', pk.expected_base, 'verified_base', pk.verified_base,
                                           'pack_status', pk.pack_status, 'pack_verification_method', pk.pack_verification_method,
                                           'verified_by', pk.verified_by, 'verified_at', pk.verified_at) end
           order by pl.tote_no nulls first, pl.pick_task_id, pl.line_id), '[]'::jsonb)
    into v_out
  from pl
  join public.product sp on sp.id = pl.stock_pid
  left join bal  on bal.warehouse_id = pl.location_id and bal.product_id = pl.stock_pid
  left join bc   on bc.stock_pid = pl.stock_pid
  left join bins bp on bp.pick_task_line_id = pl.line_id and bp.planned
  left join bins ba on ba.pick_task_line_id = pl.line_id and not ba.planned
  left join sb   on sb.line_id = pl.line_id
  left join pk   on coalesce(pk.order_line_id, pk.transfer_line_id) = coalesce(pl.order_line_id, pl.transfer_line_id)
  where v_pack_id is null or pk.pack_line_id is not null;

  return v_out;
end
$$;
comment on function public.wms_pick_lines(bigint[], bigint) is
  '⑤-4b 읽기 창구 — 픽 줄(과제 여럿 · 웨이브 멤버 전부) 또는 팩 줄(팩 과제 하나) + 제품 · 바코드(낱개 + 세트 factor) · 계획 칸 · 실제 칸 · 존(ref_bin.zone 우선 · 없으면 칸 이름 규칙) · 창고 가용(ims_inv_balance 합 · 한 문장) · ⊕ stock_bins(pick-bin-2 판정 122: 이 낱개 제품의 그 창고 칸 목록 — 계획 칸 전부 + 장부 qty > 0 인 활성 칸 · 계획 먼저 · 장부 내림 · 이름 · qty 는 낱개 EA · [{bin_id, bin, zone, qty, is_active, planned}]). 읽기 · stable · invoker · 창고 검사 없음(쓰기 창구가 지킨다). 사진 칸 없음(판정 33).';
revoke all on function public.wms_pick_lines(bigint[], bigint) from public, anon;
grant execute on function public.wms_pick_lines(bigint[], bigint) to authenticated;

-- ═══ 5) wms_reports 칸 셋(판정 124) — wrong_location 에만 · 이름으로(원장 · 화면 · note 와 같은 그레인 · 자유 타자 허용 판정 122) · 기존 행 무접촉(전부 null) · 부분 유니크 없음 ═══
alter table public.wms_reports
  add column planned_bin text,
  add column found_bin   text,
  add column bin_qty     numeric;
alter table public.wms_reports
  add constraint wms_reports_bins_kind_ck check (kind = 'wrong_location' or (planned_bin is null and found_bin is null and bin_qty is null)),
  add constraint wms_reports_bin_qty_ck  check (bin_qty is null or bin_qty > 0);
comment on column public.wms_reports.planned_bin is 'pick-bin-2(판정 124) — wrong_location 에만: 계획 칸 이름(비어 있던 칸) · 화면이 「Planned bin was empty」 체크 때 자동으로 적는다';
comment on column public.wms_reports.found_bin   is 'pick-bin-2(판정 124) — wrong_location 에만: 실제로 뽑은 칸 이름(목록에 없는 칸도 타자 허용 · 판정 122)';
comment on column public.wms_reports.bin_qty     is 'pick-bin-2(판정 124) — wrong_location 에만: 그 칸에서 뽑은 낱개 수량(> 0) · ⑪ 뒤 절반(보고 → 칸 옮기기)은 뒤 화면 차수';
