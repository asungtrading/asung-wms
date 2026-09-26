-- ⑤-2a2 WMS 창구 둘째 — 픽 완료 · 팩 완료 · 보류 둘 · 재개 · 자동 보류 (2026-09-26 UTC · 토론토 2026-09-26 저녁)
-- 정본 so-module §24 · 지시서 ~/asung/prompts/wms-5-2.md · 판정 회신 wms-5-2-rulings.md(§1 「WMS 창구」 중 a1 이 안 한 것 · 판정 20 · 22 · 24 · 25) · a1 = 20260926192314(468b897)
-- 대상: [테스트 · Asung-IMS] 만 — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 시험 적용 + 검증 ~/asung/prompts/wms-5-2a2-verify.sql(-v mig)
-- ⛔⛔ 절대 조건(Caleb 2026-09-26): 운영 WMS(asung-WMS · wms.asung.ca)는 어떤 경우에도 멈추면 안 된다.
--     첫 문장 = 운영 가드(원본 supabase/ops/guard-test-only.sql 의 글자를 그대로 복사 · 검증 G0 이 임시 파일 diff 로 같음을 잰다).
--     흔적 셋 중 하나라도 있으면 WM501 로 멈춘다(OR · fail-closed): cron.job 에 wms-poll-orders/wms-auto-hold · inv_config.db_role <> 'test' · wms_health_runs 행 > 0
--     ⚠️ 자동 보류 잡은 테스트 전용 이름 ims-wms-auto-hold 로 등록한다(가드 흔적 a 와 안 부딪히게 · supabase/ops/cron.sql 블록 · 등록은 Caleb)
-- 원본 = wms_legacy 의 같은 이름 함수 여섯(마지막 정의: complete_pick·hold_pick·complete_pack·hold_pack 20260910230704 · auto_hold 20260824202539 · resume_hold 20260825183827) → 새 표 · uuid · ims_staff
--   · 작업자 = so_current_staff()(auth.uid → ims_staff.id · 운영은 auth.email → wms_staff.name) · CAS(assigned_to = 사람 id · status in_progress · session_id) 그대로 · 0행 = {completed/held:false, worker, reason other_device}
--   · 창구마다 첫 줄 ims_require_write(화면 값: 픽·보류 픽·재개 픽/웨이브 = picking · 팩·보류 팩·재개 팩 = packing) · 다음 ims_can_warehouse(과제 오더의 창고 · 웨이브는 wms_waves.warehouse_id)
--   · definer(a1 창구 wms_batch_create 와 같은 모양 · 문은 첫 줄의 ims_require_write 하나) · 자동 보류는 cron(postgres)만 · authenticated 에서 뺐다
-- 운영의 p_disc 가 담던 것을 나눈다(판정 20):
--   · 작업자 실수(short_pick · short_after_pack · over_pick · pack_scan_mistake · resolved_pack_recovery) → wms_worker_mistakes (p_mistakes · 칸은 운영 wms_discrepancies 와 같다)
--   · 픽커의 「Not enough stock」 선언 → wms_reports kind stock_short(화면이 직접 insert · 이 파일은 qty_expected · qty_found 칸을 더한다 · 완료 창구가 refresh/delete/resolve 한다)
-- 픽 완료의 실제 칸(첫 회신 안): p_lines[].bins [{bin_id | bin, qty_base}] → wms_pick_line_bins planned=false(picked_by/at) · 합 = picked_base(아니면 거부) ·
--   bins 를 안 보내면 계획 칸(planned=true) 순서로 picked_base 를 채운다(첫 계획 칸이 나머지를 받는다) · 계획 칸도 없으면 거부(계획 칸이 없던 줄은 warnings 로 이미 알렸다)
-- ⭐ 판정 24 — 운영 창구가 찍던 시각·사람 칸을 빠짐없이(검증 T 절이 함수 원문과 자료 둘 다로 대조):
--   픽 완료 wms_pick_tasks status·completed_at·completed_by / wms_waves status·completed_at / 줄 picked_base·status·verification_method(picked_at/by 는 화면이 스캔마다)
--   팩 완료 wms_pack_tasks status·completed_at·completed_by / 줄 verified_base·status·verification_method(coalesce)·verified_at(coalesce)·⊕verified_by(coalesce · 새 표 칸)
--   보류 status·assigned_to·heartbeat_at·held_by + wms_task_holds task_kind·task_id·worker(·held_at·source auto) / 재개 resumed_at·resumed_by(서버 시계)
--   ⊖ 운영 팩 완료의 wms_orders.status ready_to_close·notified_at 은 없다 — SO 의 packed 는 Finalize(⑤-2b · 판정 18) · ready 는 뷰 wms_order_pack_progress.all_packed 로 돌려준다
-- 정합: a1 이 so.packed_at/by 와 so_status_guard 의 comment 에 「팩 완료」라고 적은 것을 「Finalize(⑤-2b)」로 바로잡는다(판정 18 · 코드는 그대로)
-- ⚠️ ⑤-2b 로 넘긴 것: 치수 칸(판정 19) · Finalize(picking→packed) · wms_so_handoff · so_finalize 재발행 · 되돌리기 다섯 · 검토함(판정 22 · wms_order_review)
-- ⚠️ 번호 시퀀스(so · 인보이스 · 크레딧)는 이 파일이 건드리지 않는다 · so_ship · so_finalize 를 부르지 않는다 · WMS 일련번호(과제 · 웨이브 · 보류 · 실수 · 리포트)는 문서 번호가 아니다

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

-- ═══ 1) wms_reports — stock_short 의 수량 칸 둘(판정 20 · 운영 wms_discrepancies 의 ordered_base·actual_base 자리 · 뒤의 재고 조정 연결이 쓴다) ═══
alter table public.wms_reports
  add column qty_expected numeric,
  add column qty_found    numeric;
comment on column public.wms_reports.qty_expected is '⑤-2a2 kind stock_short 만 — 그 줄이 필요했던 EA(assigned_base) · 픽/팩 완료 창구가 p_short_refresh 로 갱신한다';
comment on column public.wms_reports.qty_found    is '⑤-2a2 kind stock_short 만 — 선반에서 찾은 EA(picked/verified_base) · 재고 사건 차수의 조정 연결이 기대 − 찾음 을 쓴다(판정 20 ⬜)';

-- ═══ 2) 정합 — a1 의 comment 둘을 판정 18 대로(packed 는 Finalize · ⑤-2b · 코드 무접촉) ═══
comment on column public.so.packed_at  is '⑤-2a1(판정 23) 출하 준비가 끝난 때 — so_wms_status(packed) 가 찍는다(Finalize · ⑤-2b · 판정 18 「packed = Finalized」) · 팩 완료(⑤-2a2)는 찍지 않는다 · packed→picking 으로 되돌리면 지운다';
comment on function public.so_status_guard() is
  '⭐ SO 상태 문지기(6-g′ · 12-b 판정 6 · ②a ⬜3 · ③a ⬜5 · ⓑ2 · ④a2 · ⑤-2a1) — insert 는 draft 만 · status 가 바뀌는 update 는 허락 짝에 없으면 거부(소유자·definer 창구도 지난다) · 같은 상태의 update 는 통과. 짝 일곱 + WMS 여섯 + 길별 하나: draft→confirmed · confirmed→draft · confirmed→cancelled · draft→cancelled · packed→shipped(so_ship · warehouse) · shipped→fulfilled(so_invoice_issue) · fulfilled→shipped(so_invoice_cancel) · ⑤ confirmed→at_wms(Release) · at_wms→confirmed(거둬들이기) · at_wms→picking(배치·웨이브) · picking→at_wms(창고가 되돌림) · picking→packed(Finalize · ⑤-2b) · packed→picking(Undo Finalize) — 전부 so_wms_status 가 낸다 · at_wms→cancelled · picking→cancelled 없음(판정 21 한 단계씩) · ⭐ confirmed→shipped 는 channel pos·counter 만(so_ship · 7-c)';

-- ═══ 3) wms_complete_pick — 원본 wms_legacy.wms_complete_pick(20260910230704) · 새 표 · uuid · ims_staff · 실제 칸 행 · p_disc → p_mistakes(short_pick) · stock_short 는 wms_reports ═══
--   p_lines [{id, picked_base, status, verification_method, bins?:[{bin_id|bin, qty_base}]}] · p_mistakes [{order_id, pick_task_id?, sku, ordered_base, actual_base}]
--   p_short_refresh [{order_id, sku, ordered_base, actual_base}] · p_short_delete [{order_id, sku}]
create function public.wms_complete_pick(p_lines jsonb, p_task_id bigint default null, p_wave_id bigint default null, p_mistakes jsonb default '[]'::jsonb, p_short_refresh jsonb default '[]'::jsonb, p_short_delete jsonb default '[]'::jsonb, p_session_id text default null) returns jsonb
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
        (order_id, pick_task_id, order_number, sku, ordered_base, actual_base, reason, cin7_corrected)
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
comment on function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb, text) is
  '⑤-2a2 픽 완료(원본 wms_legacy.wms_complete_pick) — 첫 줄 ims_require_write(picking) · ims_can_warehouse · CAS(assigned_to = 나 · in_progress · session) 첫 쓰기 · 0행 = {completed:false, worker, reason other_device} · 웨이브는 wave 행 CAS + 멤버 일괄 · 줄 저장(행 수 검사) · ⊕ 실제 칸 행 wms_pick_line_bins planned=false(합 = picked_base · bins 없으면 계획 칸 순서) · short_pick → wms_worker_mistakes(p_mistakes) · stock_short 선언 → wms_reports refresh/delete(판정 20) · SO 상태는 안 바꾼다';
revoke all on function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb, text) from public, anon;
grant execute on function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb, text) to authenticated;

-- ═══ 4) wms_hold_pick — 원본 wms_legacy.wms_hold_pick(20260910230704) · 새 표 · uuid · ims_staff ═══
create function public.wms_hold_pick(p_lines jsonb, p_task_id bigint default null, p_wave_id bigint default null, p_session_id text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_worker  uuid;
  v_wh      uuid;
  v_flipped bigint;
  v_task_ids bigint[];
  v_member_total int := 0;
  v_members_held int := 0;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
begin
  perform public.ims_require_write('picking', 'saved');               -- ⭐ 첫 줄
  v_worker := public.so_current_staff();
  if (p_task_id is null) = (p_wave_id is null) then
    raise exception 'Pass exactly one of p_task_id / p_wave_id — nothing was saved';
  end if;
  select case when p_wave_id is not null then (select w.warehouse_id from public.wms_waves w where w.id = p_wave_id)
              else (select s.location_id from public.wms_pick_tasks t join public.so s on s.id = t.order_id where t.id = p_task_id) end into v_wh;
  if v_wh is null then raise exception 'Task not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_wh) then                          -- ⭐ 둘째
    raise exception 'This task is at another warehouse — you are not set up for it — nothing was saved';
  end if;

  if p_wave_id is not null then
    -- ① CAS = wave 행 (소유권 단위 — 규칙 18/28). 첫 쓰기 — 0행이면 아무것도 안 썼다.
    update public.wms_waves w
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = v_worker
     where w.id = p_wave_id and w.assigned_to = v_worker and w.status = 'in_progress'
       and (p_session_id is null or w.session_id is null or w.session_id = p_session_id)
    returning w.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('held', false, 'worker', v_worker,
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
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = v_worker
     where t.wave_id = p_wave_id and t.assigned_to = v_worker;
    get diagnostics v_members_held = row_count;
    if v_members_held <> v_member_total then
      raise exception 'Hold failed: % of % member batches matched (a member may have been taken over or released) — nothing was saved. Ask a manager before retrying',
        v_members_held, v_member_total;
    end if;
  else
    -- ① 단일 모드 CAS — 완료와 동형(방향만 반대)
    update public.wms_pick_tasks t
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = v_worker
     where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
       and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
    returning t.id into v_flipped;
    if v_flipped is null then
      return jsonb_build_object('held', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from public.wms_pick_tasks x where x.id = p_task_id));
    end if;
    v_task_ids := array[p_task_id];
  end if;

  -- ③ 라인 최종 저장 — pick_task_id 스코프 = 타 배치 오염 차단. 행 수 ≠ 배열 길이 = 예외 = 플립 포함 전체 롤백.
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
    raise exception 'Line save failed: found % of % lines — lines may have been removed by a rollback. Nothing was held. Ask a manager before retrying',
      v_lines_updated, v_lines_expected;
  end if;

  -- ④ Hold 구간 이력 — wave 는 wave 행 1건(멤버별 N행 금지). resumed_at 은 wms_resume_hold 가 닫는다.
  insert into public.wms_task_holds (task_kind, task_id, worker)
  values (case when p_wave_id is not null then 'wave' else 'pick' end, coalesce(p_wave_id, p_task_id), v_worker);

  return jsonb_build_object(
    'held', true,
    'worker', v_worker,
    'mode', case when p_wave_id is not null then 'wave' else 'single' end,
    'members_held', v_members_held,
    'lines_updated', v_lines_updated);
end
$$;
comment on function public.wms_hold_pick(jsonb, bigint, bigint, text) is
  '⑤-2a2 픽 보류(원본 wms_legacy.wms_hold_pick) — 첫 줄 ims_require_write(picking) · ims_can_warehouse · CAS 첫 쓰기(status pending · assigned_to null · heartbeat_at null · held_by 나) · 0행 = {held:false, worker, reason} · 웨이브는 wave 행 + 멤버 일괄 · 줄 저장(행 수 검사) · wms_task_holds 한 행(manual) · started_at 은 남긴다(최초 시작 · 규칙 37)';
revoke all on function public.wms_hold_pick(jsonb, bigint, bigint, text) from public, anon;
grant execute on function public.wms_hold_pick(jsonb, bigint, bigint, text) to authenticated;

-- ═══ 5) wms_complete_pack — 원본 wms_legacy.wms_complete_pack(20260910230704) · 새 표 · uuid · ims_staff · p_disc → p_mistakes(세 reason) · stock_short 는 wms_reports · ready 는 뷰(SO 상태 무변 · 판정 18) ═══
--   p_lines [{id, verified_base, status, verification_method}] · p_mistakes [{sku, reason short_after_pack|over_pick|pack_scan_mistake, ordered_base, actual_base}]
--   p_short_refresh [{sku, ordered_base, actual_base}] · p_short_resolve [sku …] · p_recovered [sku …]
create function public.wms_complete_pack(p_task_id bigint, p_lines jsonb, p_mistakes jsonb default '[]'::jsonb, p_short_refresh jsonb default '[]'::jsonb, p_short_resolve jsonb default '[]'::jsonb, p_recovered jsonb default '[]'::jsonb, p_session_id text default null) returns jsonb
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
         source, responsible, declared_by, resolved_by, resolved_at, cin7_corrected)
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
comment on function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb, text) is
  '⑤-2a2 팩 완료(원본 wms_legacy.wms_complete_pack) — 첫 줄 ims_require_write(packing) · ims_can_warehouse · reason 셋만 · CAS 첫 쓰기 · 0행 = {completed:false, worker, reason} · 줄 저장(verified_at/by·방법 coalesce 보존 · 행 수 검사) · 실수 → wms_worker_mistakes(responsible = 픽 과제 assigned_to · pack_scan_mistake 는 선해소) · stock_short → wms_reports refresh/resolve · 팩 회복 → short_pick resolved_pack_recovery · ready = 뷰 all_packed(SO 상태 무변 · packed 는 Finalize ⑤-2b)';
revoke all on function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb, text) from public, anon;
grant execute on function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb, text) to authenticated;

-- ═══ 6) wms_hold_pack — 원본 wms_legacy.wms_hold_pack(20260910230704) ═══
create function public.wms_hold_pack(p_task_id bigint, p_lines jsonb, p_session_id text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_worker  uuid;
  v_wh      uuid;
  v_flipped bigint;
  v_lines_expected int := coalesce(jsonb_array_length(p_lines), 0);
  v_lines_updated  int := 0;
begin
  perform public.ims_require_write('packing', 'saved');               -- ⭐ 첫 줄
  v_worker := public.so_current_staff();
  select s.location_id into v_wh from public.wms_pack_tasks t join public.so s on s.id = t.order_id where t.id = p_task_id;
  if v_wh is null then raise exception 'Task not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_wh) then                          -- ⭐ 둘째
    raise exception 'This task is at another warehouse — you are not set up for it — nothing was saved';
  end if;

  -- ① CAS 플립 먼저 — 0행 = 무기록 {held:false, worker} (재호출 멱등)
  update public.wms_pack_tasks t
     set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = v_worker
   where t.id = p_task_id and t.assigned_to = v_worker and t.status = 'in_progress'
     and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
  returning t.id into v_flipped;
  if v_flipped is null then
    return jsonb_build_object('held', false, 'worker', v_worker,
        'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
                                and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
                               then 'other_device' end
                     from public.wms_pack_tasks x where x.id = p_task_id));
  end if;

  -- ② 라인 최종 저장 — pack_task_id 스코프 + 행 수 검사 = 전체 롤백 · 방법 보존
  update public.wms_pack_task_lines l
     set verified_base = r.vb, status = r.st,
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

  -- ③ Hold 구간 이력
  insert into public.wms_task_holds (task_kind, task_id, worker)
  values ('pack', p_task_id, v_worker);

  return jsonb_build_object(
    'held', true,
    'worker', v_worker,
    'lines_updated', v_lines_updated);
end
$$;
comment on function public.wms_hold_pack(bigint, jsonb, text) is
  '⑤-2a2 팩 보류(원본 wms_legacy.wms_hold_pack) — 첫 줄 ims_require_write(packing) · ims_can_warehouse · CAS 첫 쓰기(pending · assigned_to null · heartbeat_at null · held_by 나) · 0행 = {held:false, worker, reason} · 줄 저장(행 수 검사) · wms_task_holds 한 행(manual)';
revoke all on function public.wms_hold_pack(bigint, jsonb, text) from public, anon;
grant execute on function public.wms_hold_pack(bigint, jsonb, text) to authenticated;

-- ═══ 7) wms_resume_hold — 원본 wms_legacy.wms_resume_hold(20260825183827) · 재개자 uuid · 화면 값은 kind 로(pick·wave = picking · pack = packing) ═══
create function public.wms_resume_hold(p_task_kind text, p_task_id bigint) returns integer
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_worker uuid;
  v_n int;
begin
  if p_task_kind not in ('pick', 'wave', 'pack') then
    raise exception 'Unknown task kind % — nothing was closed', p_task_kind;
  end if;
  perform public.ims_require_write(case when p_task_kind = 'pack' then 'packing' else 'picking' end, 'closed');   -- ⭐ 첫 줄
  v_worker := public.so_current_staff();                              -- 재개자 = 서버 유도

  update public.wms_task_holds
     set resumed_at = now(),        -- ⚠️ 서버 시계 — 이 함수의 존재 이유
         resumed_by = v_worker
   where task_kind = p_task_kind and task_id = p_task_id and resumed_at is null;
  get diagnostics v_n = row_count;
  return v_n;
end
$$;
comment on function public.wms_resume_hold(text, bigint) is
  '⑤-2a2 보류 닫기(원본 wms_legacy.wms_resume_hold) — 재개(클레임)는 화면이 표에 직접 쓰고(운영 그대로 · auth_all) 이 창구가 열린 wms_task_holds 를 서버 시계로 닫는다(resumed_at · resumed_by = 나) · 첫 줄 ims_require_write(kind 로 picking/packing) · 0행 = 신규 시작(no-op)';
revoke all on function public.wms_resume_hold(text, bigint) from public, anon;
grant execute on function public.wms_resume_hold(text, bigint) to authenticated;

-- ═══ 8) wms_auto_hold — 원본 wms_legacy.wms_auto_hold(20260824202539) · held_by/worker uuid · cron(postgres)만 · 잡 이름은 ims-wms-auto-hold(테스트 전용 · cron.sql) ═══
create function public.wms_auto_hold() returns void
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare
  c_after constant interval := interval '10 minutes';  -- ⚠️ 판정 상수 — 유일한 자리
  c_cap   constant int := 20;                          -- 회차 전체 상한
  v_budget int := c_cap;                               -- 남은 예산 (c_cap 에서 차감)
  v_n int;
  w record;
  v_members int;
  v_flipped int;
begin
  -- ── 1) 단일 픽 (wave 멤버 제외 — wave 는 3)에서 wave 단위로) ──
  with stale as (
    select t.id, t.assigned_to,
           greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz),
                    coalesce(t.started_at,     'epoch'::timestamptz),
                    coalesce(t.heartbeat_at,   'epoch'::timestamptz),
                    t.created_at) as last_activity
      from public.wms_pick_tasks t
      left join public.wms_pick_task_lines l on l.pick_task_id = t.id
     where t.status = 'in_progress' and t.wave_id is null and t.assigned_to is not null
     group by t.id
    having greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz),
                    coalesce(t.started_at,     'epoch'::timestamptz),
                    coalesce(t.heartbeat_at,   'epoch'::timestamptz),
                    t.created_at) < now() - c_after
     order by 3 asc                                    -- 오래된 것 먼저
     limit v_budget
  ),
  flipped as (
    update public.wms_pick_tasks t
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = s.assigned_to
      from stale s
     where t.id = s.id and t.status = 'in_progress' and t.assigned_to = s.assigned_to  -- CAS 재확인
    returning t.id, s.assigned_to as worker, s.last_activity
  )
  insert into public.wms_task_holds (task_kind, task_id, worker, held_at, source)
  select 'pick', f.id, f.worker, f.last_activity + c_after, 'auto' from flipped f;
  get diagnostics v_n = row_count;
  v_budget := v_budget - v_n;
  if v_budget <= 0 then return; end if;

  -- ── 2) 팩 ──
  with stale as (
    select t.id, t.assigned_to,
           greatest(coalesce(max(l.verified_at), 'epoch'::timestamptz),
                    coalesce(t.started_at,       'epoch'::timestamptz),
                    coalesce(t.heartbeat_at,     'epoch'::timestamptz),
                    t.created_at) as last_activity
      from public.wms_pack_tasks t
      left join public.wms_pack_task_lines l on l.pack_task_id = t.id
     where t.status = 'in_progress' and t.assigned_to is not null
     group by t.id
    having greatest(coalesce(max(l.verified_at), 'epoch'::timestamptz),
                    coalesce(t.started_at,       'epoch'::timestamptz),
                    coalesce(t.heartbeat_at,     'epoch'::timestamptz),
                    t.created_at) < now() - c_after
     order by 3 asc
     limit v_budget
  ),
  flipped as (
    update public.wms_pack_tasks t
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = s.assigned_to
      from stale s
     where t.id = s.id and t.status = 'in_progress' and t.assigned_to = s.assigned_to
    returning t.id, s.assigned_to as worker, s.last_activity
  )
  insert into public.wms_task_holds (task_kind, task_id, worker, held_at, source)
  select 'pack', f.id, f.worker, f.last_activity + c_after, 'auto' from flipped f;
  get diagnostics v_n = row_count;
  v_budget := v_budget - v_n;
  if v_budget <= 0 then return; end if;

  -- ── 3) wave — wave 행 단위 판정·이력, 플립은 행+멤버 전부 · 어긋난 wave 는 skip(다음 회차) ──
  for w in
    select wv.id, wv.assigned_to,
           greatest(coalesce(max(l.picked_at),  'epoch'::timestamptz),
                    coalesce(wv.started_at,     'epoch'::timestamptz),
                    coalesce(wv.heartbeat_at,   'epoch'::timestamptz),
                    wv.created_at) as last_activity
      from public.wms_waves wv
      left join public.wms_pick_tasks t on t.wave_id = wv.id
      left join public.wms_pick_task_lines l on l.pick_task_id = t.id
     where wv.status = 'in_progress' and wv.assigned_to is not null
     group by wv.id
    having greatest(coalesce(max(l.picked_at),  'epoch'::timestamptz),
                    coalesce(wv.started_at,     'epoch'::timestamptz),
                    coalesce(wv.heartbeat_at,   'epoch'::timestamptz),
                    wv.created_at) < now() - c_after
     order by 3 asc
     limit v_budget
  loop
    exit when v_budget <= 0;
    select count(*), count(*) filter (where status = 'in_progress' and assigned_to = w.assigned_to)
      into v_members, v_flipped
      from public.wms_pick_tasks where wave_id = w.id;
    if v_members = 0 or v_flipped <> v_members then
      continue;
    end if;
    update public.wms_waves
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = w.assigned_to
     where id = w.id and status = 'in_progress' and assigned_to = w.assigned_to;
    if not found then continue; end if;
    update public.wms_pick_tasks
       set status = 'pending', assigned_to = null, heartbeat_at = null, held_by = w.assigned_to
     where wave_id = w.id and status = 'in_progress' and assigned_to = w.assigned_to;
    insert into public.wms_task_holds (task_kind, task_id, worker, held_at, source)
    values ('wave', w.id, w.assigned_to, w.last_activity + c_after, 'auto');
    v_budget := v_budget - 1;
  end loop;
end
$$;
comment on function public.wms_auto_hold() is
  '⑤-2a2 자동 보류(원본 wms_legacy.wms_auto_hold · 판정 10분 · 상한 20 · 오래된 것 먼저) — 마지막 활동(줄 picked/verified_at · started_at · heartbeat_at · created_at) + 10분이 지난 in_progress 과제를 pending 으로(held_by = 그 사람 · wms_task_holds source auto · held_at = 마지막 활동 + 10분) · 웨이브는 행 + 멤버 · cron 잡 ims-wms-auto-hold(테스트 전용 이름 · 운영 가드 흔적 a 와 다르다 · supabase/ops/cron.sql) · authenticated 에서 뺐다';
revoke all on function public.wms_auto_hold() from public, anon, authenticated;
