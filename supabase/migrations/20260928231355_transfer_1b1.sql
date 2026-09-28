-- ─────────────────────────────────────────────────────────────
-- 재고 사건 ② 트랜스퍼 · 둘째 몫 「창고 간」 ②-1 — 창고 창구 스무 개가 공용 목록(wms_order_doc · wms_order_doc_line)을 읽는다 · 판매 동작 무변 (Asung-IMS · tr-1b1 · 2026-09-28)
--   정본(뒤에 적는다): so-module §27(판정 64~72 · 묶음 10 의 6 · 10) · tr-1a(20260928201753) 가 세운 뷰 둘을 이 차수부터 창구가 읽는다
--   든 것: ① 뷰 wms_order_doc 재발행 — 끝에 19번째 칸 picking_by(판정 72 · 판매 so.picking_by · 트랜스퍼 inv_transfer.picking_by · Health picking_no_tasks 표본 무변)
--         ② 뷰 wms_order_pack_progress 재발행 — doc 키 coalesce(order_id, transfer_id) · 칸 이름 order_id · 모양 · acl 무변
--         ③ 창구 재발행 19 — 마지막 정의 바이트 그대로 + 조인 교체만(join so → wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id) · so_line → wms_order_doc_line) · 이름 · 인자 · 반환 모양 무변(묶음 10 의 6)
--            wms_batch_create(20260926192314) · wms_wave_create(〃) · wms_pick_task_build(〃) · so_pick_plan(20260925133147) · wms_pick_lines(20260927010322) · wms_complete_pick(20260927214447)
--            wms_complete_pack(20260928164832) · wms_hold_pick(20260926200918) · wms_hold_pack(〃) · wms_finalize(20260926204246) · wms_so_handoff(〃) · wms_rollback(20260928164832) · wms_rollback_batch(〃)
--            wms_unwave(20260926204246) · wms_review_set(〃) · wms_health_check(20260928182712) · inv_adjust_picked(20260928142722) · inv_move_open_plans(20260928182712) · inv_adjust_from_report(20260928142722 · 목록 밖 · 같은 조인)
--   ⭐ 판정 72(2026-09-28): (1) 상태 술어는 뷰의 원문 status(picking · packed …) — wms_stage 를 쓰지 않는다(done ⊃ fulfilled · P 에 출고된 픽이 든다) · inv_move_open_plans 의 wms_stage in (at_wms, picking) 만 판매와 같아 그대로
--                          (2) picking_by 는 뷰 끝 칸 (3) 판매 오더 행 잠금 `perform 1 from public.so … for update` 한 줄은 남긴다(판정 71 예외 · 트랜스퍼 잠금은 ②-2) (4) inv_adjust_from_report 포함
--   이 차수가 하지 않는 것(②-2 · tr-1b2): 트랜스퍼 입구(tf_release · tf_wms_recall · tf_wms_status) · wms_pick_task_build 의 transfer 칸 채우기 · wms_finalize 의 kind 갈래 · wms_doc_status — 쓰는 창구는 판매면 order_id 만 채운다(지금과 같게)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 판매 표 · 행 무접촉 · 판매 창구(so_finalize · so_ship · inv_post_sale · so_allocate_run · so_confirm · so_wms_status) 무접촉 · IMS 안에서만 선다(판정 51 · 60)
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

-- ═══ 1) 뷰 wms_order_doc 재발행 — tr-1a 20260928201753:399~412 바이트 그대로 + 끝 칸 picking_by(판정 72 · create or replace 는 끝 추가만 된다 · 옵션 security_invoker · grant · comment 는 남는다) ═══
create or replace view public.wms_order_doc with (security_invoker = true) as
  select 'so'::text as doc_kind, s.id as doc_id, s.so_number as doc_number, s.status, s.channel,
         case when s.status in ('draft', 'confirmed') then 'before_wms' when s.status = 'at_wms' then 'at_wms' when s.status = 'picking' then 'picking'
              when s.status = 'cancelled' then 'cancelled' else 'done' end as wms_stage,
         s.location_id as warehouse_id, s.location_name as warehouse_name, null::uuid as dest_warehouse_id, null::text as dest_warehouse_name,
         s.customer_id as party_id, c.name as party_name, s.at_wms_at, s.picking_at, s.packed_at as done_at, s.created_at, s.comments, s.ref,
         s.picking_by
    from public.so s left join public.customer c on c.id = s.customer_id
  union all
  select 'transfer', t.id, t.transfer_number, t.status, 'transfer',
         case when t.status in ('draft', 'confirmed') then 'before_wms' when t.status = 'at_wms' then 'at_wms' when t.status = 'picking' then 'picking'
              when t.status = 'cancelled' then 'cancelled' else 'done' end,
         t.from_warehouse_id, fw.name, t.to_warehouse_id, tw.name,
         t.to_warehouse_id, tw.name, t.at_wms_at, t.picking_at, t.departed_at, t.created_at, t.note, null::text,
         t.picking_by
    from public.inv_transfer t join public.ref_warehouse fw on fw.id = t.from_warehouse_id join public.ref_warehouse tw on tw.id = t.to_warehouse_id;
comment on column public.wms_order_doc.picking_by is 'tr-1b1(판정 72) — 창고 작업을 시작한 사람(판매 so.picking_by · 트랜스퍼 inv_transfer.picking_by) · Health picking_no_tasks 표본이 읽는다';

-- ═══ 2) 뷰 wms_order_pack_progress 재발행 — 20260926165113:379~390 바이트 그대로 · 묶는 키만 doc 키(coalesce(order_id, transfer_id)) · 칸 이름 order_id · 모양 · acl(anon·authenticated revoke 뒤 authenticated select) 무변 ═══
create or replace view public.wms_order_pack_progress
  with (security_invoker = true) as
select
  coalesce(pt.order_id, pt.transfer_id) as order_id,
  count(pt.id)::int as pick_batches,
  (count(distinct pk.pick_task_id) filter (where pk.status = 'completed'))::int as packs_done,
  count(pt.id) > 0
    and count(pt.id) = count(distinct pk.pick_task_id) filter (where pk.status = 'completed')
    as all_packed
from public.wms_pick_tasks pt
left join public.wms_pack_tasks pk on pk.pick_task_id = pt.id
group by coalesce(pt.order_id, pt.transfer_id);
comment on view public.wms_order_pack_progress is '⑤-1 (so-module §24 ⬜12) · 새 wms_pick_tasks·wms_pack_tasks 위에 같은 칸(order_id uuid) · fulfillment 보드의 관문 · 옛 뷰는 wms_legacy · tr-1b1: order_id = 문서 id(판매 오더 또는 트랜스퍼 · coalesce)';

-- ═══ 3) 창구 재발행 19 — 마지막 정의 바이트 그대로 + 조인 교체(diff 원문은 보고 · 바뀐 줄 227) · create or replace 라 grant · comment · security 가 남는다 ═══

-- ── wms_batch_create ──
create or replace function public.wms_batch_create(p_so_id uuid, p_batches jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_doc    public.wms_order_doc%rowtype;
  v_wh     text;
  v_plan   jsonb;
  v_ids    uuid[] := '{}';
  v_batch  uuid[];
  v_bad    text;
  v_n      int;
  i        int;
  b        jsonb;
  v_tasks  jsonb := '[]'::jsonb;
  v_t      jsonb;
  v_warn   jsonb := '[]'::jsonb;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄 — 카탈로그 wms_manage = manager 이상(min_role)
  v_staff := public.so_current_staff();
  perform 1 from public.so s where s.id = p_so_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_doc.warehouse_id;
  if not public.ims_can_warehouse(v_doc.warehouse_id) then              -- ⭐ 둘째 — 창고 제한 첫 실물
    raise exception 'Order % is at % — you are not set up for that warehouse — nothing was saved', v_doc.doc_number, coalesce(v_wh, '<none>');
  end if;
  if v_doc.status <> 'at_wms' then
    raise exception 'Order % is % — only orders released to the WMS can be batched — nothing was saved', v_doc.doc_number, v_doc.status;
  end if;
  if exists (select 1 from public.wms_pick_tasks t where t.order_id = p_so_id) then
    raise exception 'Order % already has pick tasks — nothing was saved', v_doc.doc_number;
  end if;
  if p_batches is null or jsonb_typeof(p_batches) <> 'array' or jsonb_array_length(p_batches) = 0 then
    raise exception 'Order % — no batches given — nothing was saved', v_doc.doc_number;
  end if;
  -- 줄 검사: 모르는 줄 · 두 번 든 줄 · 빠진 보낼 줄 · 다 뺀 줄
  for b in select * from jsonb_array_elements(p_batches) loop
    if jsonb_typeof(b->'line_ids') <> 'array' or jsonb_array_length(b->'line_ids') = 0 then
      raise exception 'Order % — a batch has no lines — nothing was saved', v_doc.doc_number;
    end if;
    select array_agg((e.v)::uuid) into v_batch from jsonb_array_elements_text(b->'line_ids') e(v);
    v_ids := v_ids || v_batch;
  end loop;
  select string_agg(u.id::text, ', ') into v_bad from unnest(v_ids) u(id) where not exists (select 1 from public.wms_order_doc_line l where l.line_id = u.id and l.doc_id = p_so_id);
  if v_bad is not null then raise exception 'Order % — lines not on this order (%) — nothing was saved', v_doc.doc_number, v_bad; end if;
  select string_agg(l.line_no::text, ', ') into v_bad from (select u.id from unnest(v_ids) u(id) group by u.id having count(*) > 1) d join public.wms_order_doc_line l on l.line_id = d.id;
  if v_bad is not null then raise exception 'Order % — lines in more than one batch (%) — nothing was saved', v_doc.doc_number, v_bad; end if;
  select string_agg(l.line_no::text, ', ' order by l.line_no) into v_bad from public.wms_order_doc_line l where l.doc_id = p_so_id and l.qty_target > 0 and not (l.line_id = any (v_ids));
  if v_bad is not null then raise exception 'Order % — lines left out of the batches (%) — nothing was saved', v_doc.doc_number, v_bad; end if;
  select string_agg(l.line_no::text, ', ' order by l.line_no) into v_bad from public.wms_order_doc_line l where l.doc_id = p_so_id and l.qty_target <= 0 and l.line_id = any (v_ids);
  if v_bad is not null then raise exception 'Order % — lines with nothing to ship (%) cannot be batched — nothing was saved', v_doc.doc_number, v_bad; end if;
  -- 계획 칸 · 과제
  v_plan := public.so_pick_plan(p_so_id);
  i := 0;
  for b in select * from jsonb_array_elements(p_batches) loop
    i := i + 1;
    select array_agg((e.v)::uuid) into v_batch from jsonb_array_elements_text(b->'line_ids') e(v);
    v_t := public.wms_pick_task_build(p_so_id, v_doc.doc_number || '-' || i, v_batch, null, null, v_staff, v_plan);
    v_tasks := v_tasks || v_t;
    v_warn := v_warn || (v_t->'warnings');
  end loop;
  perform public.so_wms_status(p_so_id, 'picking', v_staff);
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_doc.doc_number, 'status', 'picking', 'tasks', v_tasks,
                            'short_ea_total', v_plan->'short_ea_total', 'warnings', (v_plan->'warnings') || v_warn);
end;
$$;

-- ── wms_wave_create ──
create or replace function public.wms_wave_create(p_so_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_id     uuid;
  v_doc    public.wms_order_doc%rowtype;
  v_wh_id  uuid;
  v_wh     text;
  v_wave   bigint;
  v_label  text;
  v_md     text;
  v_n      int;
  v_plan   jsonb;
  v_ids    uuid[];
  i        int := 0;
  v_tasks  jsonb := '[]'::jsonb;
  v_t      jsonb;
  v_warn   jsonb := '[]'::jsonb;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  if p_so_ids is null or cardinality(p_so_ids) = 0 then raise exception 'No orders given — nothing was saved'; end if;
  if (select count(distinct u.id) from unnest(p_so_ids) u(id)) <> cardinality(p_so_ids) then raise exception 'An order is listed twice — nothing was saved'; end if;
  -- ① 검사 전부(잠근다)
  foreach v_id in array p_so_ids loop
    perform 1 from public.so s where s.id = v_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    if not found then raise exception 'Order not found (%) — nothing was saved', v_id; end if;
    select w.name into v_wh from public.ref_warehouse w where w.id = v_doc.warehouse_id;
    if not public.ims_can_warehouse(v_doc.warehouse_id) then            -- ⭐ 둘째
      raise exception 'Order % is at % — you are not set up for that warehouse — nothing was saved', v_doc.doc_number, coalesce(v_wh, '<none>');
    end if;
    if v_doc.status <> 'at_wms' then
      raise exception 'Order % is % — only orders released to the WMS can go in a wave — nothing was saved', v_doc.doc_number, v_doc.status;
    end if;
    if exists (select 1 from public.wms_pick_tasks t where t.order_id = v_id) then
      raise exception 'Order % already has pick tasks — nothing was saved', v_doc.doc_number;
    end if;
    if not exists (select 1 from public.wms_order_doc_line l where l.doc_id = v_id and l.qty_target > 0) then
      raise exception 'Order % has nothing left to ship — nothing was saved', v_doc.doc_number;
    end if;
    if v_wh_id is null then v_wh_id := v_doc.warehouse_id;
    elsif v_wh_id <> v_doc.warehouse_id then
      raise exception 'Order % is at % — a wave takes one warehouse only — nothing was saved', v_doc.doc_number, coalesce(v_wh, '<none>');
    end if;
  end loop;
  -- ② 웨이브 행
  v_md := to_char(public.ims_today(), 'MMDD');
  select coalesce(max(substring(w.label from '^W-' || v_md || '-([0-9]+)$')::int), 0) + 1 into v_n from public.wms_waves w where w.label like 'W-' || v_md || '-%';
  v_label := format('W-%s-%s', v_md, v_n);
  insert into public.wms_waves (label, warehouse_id, status, created_by, created_at)
  values (v_label, v_wh_id, 'pending', v_staff, now())
  returning id into v_wave;
  -- ③ 오더마다 과제 하나 → picking
  foreach v_id in array p_so_ids loop
    i := i + 1;
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    select array_agg(l.line_id) into v_ids from public.wms_order_doc_line l where l.doc_id = v_id and l.qty_target > 0;
    v_plan := public.so_pick_plan(v_id);
    v_t := public.wms_pick_task_build(v_id, v_doc.doc_number || '-1', v_ids, v_wave, i, v_staff, v_plan);
    v_tasks := v_tasks || (v_t || jsonb_build_object('so_id', v_id, 'so_number', v_doc.doc_number, 'short_ea_total', v_plan->'short_ea_total'));
    v_warn := v_warn || (v_plan->'warnings') || (v_t->'warnings');
    perform public.so_wms_status(v_id, 'picking', v_staff);
  end loop;
  return jsonb_build_object('wave_id', v_wave, 'label', v_label, 'warehouse_id', v_wh_id, 'orders', i, 'tasks', v_tasks, 'warnings', v_warn);
end;
$$;

-- ── wms_pick_task_build ──
create or replace function public.wms_pick_task_build(p_so_id uuid, p_label text, p_line_ids uuid[], p_wave_id bigint, p_tote_no int, p_staff uuid, p_plan jsonb) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare
  v_doc     public.wms_order_doc%rowtype;
  v_task    bigint;
  v_line    bigint;
  l         record;
  p         jsonb;
  v_bin     uuid;
  v_lines   int := 0;
  v_rows    int := 0;
  v_warn    text[] := '{}';
begin
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  insert into public.wms_pick_tasks (order_id, batch_label, status, created_by, created_at, wave_id, tote_no)
  values (p_so_id, p_label, 'pending', p_staff, now(), p_wave_id, p_tote_no)
  returning id into v_task;
  for l in
    select x.line_id as id, x.line_no, x.pack_factor, x.qty_target_ea as need_ea
    from public.wms_order_doc_line x where x.doc_id = p_so_id and x.line_id = any (p_line_ids) order by x.line_no
  loop
    insert into public.wms_pick_task_lines (pick_task_id, order_line_id, assigned_base, status, created_at)
    values (v_task, l.id, l.need_ea, 'pending', now())
    returning id into v_line;
    v_lines := v_lines + 1;
    for p in select * from jsonb_array_elements(coalesce(p_plan->'picks', '[]'::jsonb)) loop
      if (p->>'line_id')::uuid <> l.id then continue; end if;
      if coalesce(p->>'bin', '') = '' then
        v_warn := array_append(v_warn, format('no_bin:%s:%s', v_doc.doc_number, l.line_no));
        continue;
      end if;
      select b.id into v_bin from public.ref_bin b where b.warehouse_id = v_doc.warehouse_id and b.name = p->>'bin';
      if v_bin is null then
        v_warn := array_append(v_warn, format('bin_unknown:%s:%s:%s', v_doc.doc_number, l.line_no, p->>'bin'));
        continue;
      end if;
      insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned)
      values (v_line, v_bin, p->>'bin', (p->>'qty')::numeric * l.pack_factor, true);
      v_rows := v_rows + 1;
    end loop;
  end loop;
  return jsonb_build_object('task_id', v_task, 'batch_label', p_label, 'wave_id', p_wave_id, 'tote_no', p_tote_no, 'lines', v_lines, 'planned_rows', v_rows, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ── so_pick_plan ──
create or replace function public.so_pick_plan(p_so_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_doc      public.wms_order_doc%rowtype;
  v_wh       text;
  v_cands    jsonb := '{}'::jsonb;     -- 낱개 product_id → [{bin_id, bin, qty, ovf, rank}] (순서대로)
  v_tot      jsonb := '{}'::jsonb;     -- 낱개 product_id → 창고 전체 잔고(모든 칸 · '' · 비활성 포함)
  v_used     jsonb := '{}'::jsonb;     -- product_id → 앞 줄이 계획한 EA(창고 부족분 계산)
  v_taken    jsonb := '{}'::jsonb;     -- product_id|bin_id → 앞 줄이 계획한 EA(칸 남은 잔고)
  l          record;
  c          jsonb;
  v_arr      jsonb;
  v_key      text;
  v_need_u   numeric;  v_need_ea numeric;  v_rem numeric;  v_avail numeric;  v_take numeric;
  v_first    text;
  v_lines    jsonb := '[]'::jsonb;
  v_picks    jsonb := '[]'::jsonb;
  v_lp       jsonb;
  v_short    numeric;  v_short_tot numeric := 0;
  v_tot_p    numeric;  v_used_p numeric;
  v_warn     text[] := '{}';
  i          int;
begin
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not found then raise exception 'Order not found'; end if;
  if v_doc.warehouse_id is null then raise exception 'Order % has no warehouse — nothing to plan', v_doc.doc_number; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_doc.warehouse_id;

  -- 칸 잔고 한 문장(ims_inv_balance 를 한 번) — 후보(활성 칸 · bin 있음)는 순서를 붙여 · 창고 전체 잔고는 모든 행
  with pids as (
    select distinct x.stock_product_id as pid
    from public.wms_order_doc_line x where x.doc_id = p_so_id
  ), bal as (
    select v.product_id, v.bin_id, v.bin, v.qty, v.bin_is_active, v.last_seen_on
    from public.ims_inv_balance v join pids on pids.pid = v.product_id
    where v.warehouse_id = v_doc.warehouse_id
  ), cand as (
    select b.product_id, b.bin_id, b.bin, b.qty, (o.id is not null) as ovf, b.last_seen_on,
           case when b.qty > 0 and o.id is null then 1 when b.qty > 0 then 2 when o.id is null then 3 else 4 end as rank   -- 재고 있는 평소 → 재고 있는 보관용 → 빈 평소 → 빈 보관용
    from bal b left join public.product_bin_overflow o on o.product_id = b.product_id and o.bin_id = b.bin_id
    where b.bin_id is not null and b.bin_is_active
  )
  select coalesce((select jsonb_object_agg(x.product_id::text, x.arr)
                   from (select cd.product_id, jsonb_agg(jsonb_build_object('bin_id', cd.bin_id, 'bin', cd.bin, 'qty', cd.qty, 'ovf', cd.ovf, 'rank', cd.rank)
                                                          order by cd.rank, cd.last_seen_on desc, cd.qty desc, cd.bin) as arr
                         from cand cd group by cd.product_id) x), '{}'::jsonb),
         coalesce((select jsonb_object_agg(y.product_id::text, y.t) from (select b2.product_id, sum(b2.qty) as t from bal b2 group by b2.product_id) y), '{}'::jsonb)
    into v_cands, v_tot;

  for l in
    select x.line_id as id, x.line_no, x.sku, x.qty_target, x.pack_factor, x.stock_product_id as pid, (p.parent_product_id is not null) as is_set
    from public.wms_order_doc_line x join public.product p on p.id = x.product_id
    where x.doc_id = p_so_id order by x.line_no
  loop
    v_need_u  := l.qty_target;                    -- 보낼 목표(판매 단위 · 판정 5 §17)
    v_need_ea := v_need_u * l.pack_factor;
    v_lp := '[]'::jsonb;  v_rem := v_need_u;  v_first := null;
    v_arr := coalesce(v_cands->(l.pid::text), '[]'::jsonb);
    if jsonb_array_length(v_arr) > 0 then v_first := v_arr->0->>'bin'; end if;

    -- 재고 있는 칸(순서대로)에서 · 세트 줄은 칸마다 정수 세트만(floor(칸 EA ÷ pack)) · 앞 줄이 계획한 몫은 뺀다
    for i in 0 .. jsonb_array_length(v_arr) - 1 loop
      exit when v_rem <= 0;
      c := v_arr->i;
      if (c->>'rank')::int > 2 then exit; end if;               -- 재고 없는 칸은 채우는 자리가 아니다
      v_key := l.pid::text || '|' || (c->>'bin_id');
      v_avail := (c->>'qty')::numeric - coalesce((v_taken->>v_key)::numeric, 0);
      if v_avail <= 0 then continue; end if;
      v_take := least(v_rem, floor(v_avail / l.pack_factor));    -- 낱개는 pack 1 · 세트는 정수 세트
      if v_take <= 0 then continue; end if;
      v_lp := v_lp || jsonb_build_object('line_id', l.id, 'bin', c->>'bin', 'qty', v_take, 'from', case when (c->>'ovf')::boolean then 'overflow' else 'usual' end);
      v_taken := jsonb_set(v_taken, array[v_key], to_jsonb(coalesce((v_taken->>v_key)::numeric, 0) + v_take * l.pack_factor));
      v_rem := v_rem - v_take;
    end loop;
    -- 모자란 몫 — 첫 후보 칸에(재고 0 이어도 · 그 칸이 음수가 될 수 있다 · 판정 1) · 후보가 없으면 ''
    if v_rem > 0 then
      v_lp := v_lp || jsonb_build_object('line_id', l.id, 'bin', coalesce(v_first, ''), 'qty', v_rem, 'from', case when v_first is null then 'none' else 'fallback' end);
      if v_first is not null then
        v_key := l.pid::text || '|' || (v_arr->0->>'bin_id');
        v_taken := jsonb_set(v_taken, array[v_key], to_jsonb(coalesce((v_taken->>v_key)::numeric, 0) + v_rem * l.pack_factor));
      else
        v_warn := array_append(v_warn, 'no_bins:' || l.sku);
      end if;
    end if;
    -- 창고 전체 부족분(고침 ①) — 모든 칸 잔고 합에서 같은 제품의 앞 줄이 쓴 EA 를 뺀 것보다 필요 EA 가 많은 몫 · 원장 FIFO 가 세울 부족분 레이어와 같아야 한다
    v_tot_p  := coalesce((v_tot->>(l.pid::text))::numeric, 0);
    v_used_p := coalesce((v_used->>(l.pid::text))::numeric, 0);
    v_short  := greatest(0, v_need_ea - greatest(v_tot_p - v_used_p, 0));
    v_used   := jsonb_set(v_used, array[l.pid::text], to_jsonb(v_used_p + v_need_ea));
    v_short_tot := v_short_tot + v_short;
    if v_short > 0 then v_warn := array_append(v_warn, 'stock_short:' || l.sku); end if;

    v_picks := v_picks || v_lp;
    v_lines := v_lines || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'is_set', l.is_set, 'pack_factor', l.pack_factor,
                                             'to_ship', v_need_u, 'need_ea', v_need_ea, 'warehouse_qty_ea', v_tot_p, 'picks', v_lp, 'short_ea', v_short);
  end loop;

  return jsonb_build_object('so_id', v_doc.doc_id, 'so_number', v_doc.doc_number, 'warehouse_id', v_doc.warehouse_id, 'warehouse', v_wh,
                            'picks', v_picks, 'lines', v_lines, 'short_ea_total', v_short_tot, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ── wms_pick_lines ──
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
    select l.id as line_id, l.pick_task_id, l.order_line_id, l.assigned_base, l.picked_base, l.status, l.verification_method, l.picked_by, l.picked_at,
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
  ), pk as (                                                              -- 팩 갈래 — 팩 줄(order_line_id 로 짝)
    select k.id as pack_line_id, k.order_line_id, k.expected_base, k.verified_base, k.status as pack_status,
           k.verification_method as pack_verification_method, k.verified_by, k.verified_at
    from public.wms_pack_task_lines k
    where v_pack_id is not null and k.pack_task_id = v_pack_id
  )
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'line_id', case when v_pack_id is null then pl.line_id else pk.pack_line_id end,
             'pick_line_id', pl.line_id,
             'pick_task_id', pl.pick_task_id, 'batch_label', pl.batch_label, 'wave_id', pl.wave_id, 'tote_no', pl.tote_no,
             'order_line_id', pl.order_line_id, 'so_id', pl.order_id, 'so_number', pl.so_number, 'customer_name', pl.customer_name, 'warehouse_id', pl.location_id,
             'sku', pl.sku, 'base_sku', sp.sku, 'product_name', pl.product_name, 'pack_factor', pl.pack_factor, 'is_set', pl.is_set,
             'assigned_base', pl.assigned_base, 'picked_base', pl.picked_base,
             'status', case when v_pack_id is null then pl.status else pk.pack_status end,
             'verification_method', case when v_pack_id is null then pl.verification_method else pk.pack_verification_method end,
             'picked_by', pl.picked_by, 'picked_at', pl.picked_at,
             'planned_bins', coalesce(bp.arr, '[]'::jsonb), 'actual_bins', coalesce(ba.arr, '[]'::jsonb),
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
  left join pk   on pk.order_line_id = pl.order_line_id
  where v_pack_id is null or pk.pack_line_id is not null;

  return v_out;
end
$$;

-- ── wms_complete_pick ──
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
  select (d->>'order_id')::uuid, (d->>'pick_task_id')::bigint, o.doc_number, d->>'sku',
         (d->>'ordered_base')::numeric, (d->>'actual_base')::numeric, 'short_pick', false
    from jsonb_array_elements(coalesce(p_mistakes, '[]'::jsonb)) d
    join public.wms_order_doc o on o.doc_id = (d->>'order_id')::uuid;
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

-- ── wms_complete_pack ──
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
  select d.warehouse_id into v_wh from public.wms_pack_tasks t join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id) where t.id = p_task_id;
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

  select o.doc_number into v_order_number from public.wms_order_doc o where o.doc_id = v_order_id;
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
    select pl.id into v_pl_id from public.wms_pick_task_lines pl join public.wms_order_doc_line sl on sl.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
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
            from public.wms_pack_task_lines kl join public.wms_order_doc_line sl on sl.line_id = coalesce(kl.order_line_id, kl.transfer_line_id) where kl.pack_task_id = p_task_id) t
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

-- ── wms_hold_pick ──
create or replace function public.wms_hold_pick(p_lines jsonb, p_task_id bigint default null, p_wave_id bigint default null, p_session_id text default null) returns jsonb
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
              else (select d.warehouse_id from public.wms_pick_tasks t join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id) where t.id = p_task_id) end into v_wh;
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

-- ── wms_hold_pack ──
create or replace function public.wms_hold_pack(p_task_id bigint, p_lines jsonb, p_session_id text default null) returns jsonb
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
  select d.warehouse_id into v_wh from public.wms_pack_tasks t join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id) where t.id = p_task_id;
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

-- ── wms_finalize ──
create or replace function public.wms_finalize(p_so_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_id uuid;  v_doc public.wms_order_doc%rowtype;  v_all boolean;  v_bad text;
  v_placed boolean;  v_units int;  v_nodim int;  v_type text;
  v_out jsonb := '[]'::jsonb;  v_warn text[] := '{}';
begin
  perform public.ims_require_write('fulfillment', 'saved');            -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  if p_so_ids is null or cardinality(p_so_ids) = 0 then raise exception 'No orders given — nothing was saved'; end if;
  -- ① 검사 전부(잠금 · 하나라도 막히면 전체 거부)
  foreach v_id in array p_so_ids loop
    perform 1 from public.so s where s.id = v_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    if not found then raise exception 'Order not found (%) — nothing was saved', v_id; end if;
    if not public.ims_can_warehouse(v_doc.warehouse_id) then          -- ⭐ 둘째
      raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_doc.doc_number;
    end if;
    if v_doc.status <> 'picking' then
      raise exception 'Order % is % — only an order in warehouse work (picking) can be finalized — nothing was saved', v_doc.doc_number, v_doc.status;
    end if;
    select coalesce(v.all_packed, false) into v_all from public.wms_order_pack_progress v where v.order_id = v_id;
    if not coalesce(v_all, false) then
      raise exception 'Order % — not every batch is picked and packed yet (%) — nothing was saved', v_doc.doc_number,
        coalesce((select v.packs_done || '/' || v.pick_batches || ' packed' from public.wms_order_pack_progress v where v.order_id = v_id), 'no pick tasks');
    end if;
    select string_agg(format('line %s: %s on pallets but %s packed', sl.line_no, pi.q, coalesce(pk.q, 0)), '; ' order by sl.line_no) into v_bad
    from (select order_line_id, sum(qty_base) as q from public.wms_pallet_items where order_id = v_id group by 1) pi
    join public.wms_order_doc_line sl on sl.line_id = pi.order_line_id
    left join (select kl.order_line_id, sum(kl.verified_base) as q from public.wms_pack_task_lines kl join public.wms_pack_tasks k on k.id = kl.pack_task_id where k.order_id = v_id and k.status = 'completed' group by 1) pk on pk.order_line_id = pi.order_line_id
    where pi.q > coalesce(pk.q, 0);
    if v_bad is not null then raise exception 'Order % — more on pallets than was packed (%) — nothing was saved', v_doc.doc_number, v_bad; end if;
  end loop;
  -- ② 기록 + 전이
  foreach v_id in array p_so_ids loop
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    v_placed := exists (select 1 from public.wms_pallet_items pi where pi.order_id = v_id);
    select count(*), count(*) filter (where u.length_in is null or u.width_in is null or u.height_in is null or u.weight_lb is null) into v_units, v_nodim
    from public.wms_pallets u where u.order_id = v_id or u.parent_id in (select p2.id from public.wms_pallets p2 where p2.order_id = v_id);
    v_type := case when v_placed then 'packing_list' else 'direct' end;
    if v_nodim > 0 then v_warn := array_append(v_warn, format('units_without_dims:%s:%s', v_doc.doc_number, v_nodim)); end if;
    insert into public.wms_order_finalize (order_id, fulfillment_type, finalized_by, finalized_at, units, units_without_dims)
    values (v_id, v_type, v_staff, now(), v_units, v_nodim);
    perform public.so_wms_status(v_id, 'packed', v_staff);
    v_out := v_out || jsonb_build_object('so_id', v_id, 'so_number', v_doc.doc_number, 'fulfillment_type', v_type, 'units', v_units, 'units_without_dims', v_nodim,
                                         'shorts', (public.wms_so_handoff(v_id))->'shorts');
  end loop;
  return jsonb_build_object('finalized', v_out, 'count', jsonb_array_length(v_out), 'warnings', to_jsonb(v_warn));
end;
$$;

-- ── wms_so_handoff ──
create or replace function public.wms_so_handoff(p_so_id uuid) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_doc    public.wms_order_doc%rowtype;
  v_all    boolean;
  l        record;  b record;
  v_ship   numeric;  v_sum numeric;  v_cut numeric;
  v_bins   jsonb;  v_picks jsonb := '[]'::jsonb;  v_shorts jsonb := '[]'::jsonb;  v_units jsonb;
  v_nodim  int;
  i        int;
begin
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not found then raise exception 'Order not found'; end if;
  select coalesce(v.all_packed, false) into v_all from public.wms_order_pack_progress v where v.order_id = p_so_id;
  for l in
    select x.line_id as id, x.line_no, x.sku, x.pack_factor, x.qty_target as target,
           coalesce((select sum(kl.verified_base) from public.wms_pack_task_lines kl join public.wms_pack_tasks k on k.id = kl.pack_task_id
                     where kl.order_line_id = x.line_id and k.status = 'completed'), 0) as verified_ea,
           coalesce((select jsonb_agg(jsonb_build_object('bin', g.bin, 'units', g.units) order by g.first_id)
                     from (select pb.bin, min(pb.id) as first_id, floor(sum(pb.qty_base) / x.pack_factor) as units
                           from public.wms_pick_line_bins pb join public.wms_pick_task_lines pl on pl.id = pb.pick_task_line_id join public.wms_pick_tasks t on t.id = pl.pick_task_id
                           where pl.order_line_id = x.line_id and not pb.planned and t.status = 'completed' group by pb.bin) g), '[]'::jsonb) as bins
    from public.wms_order_doc_line x where x.doc_id = p_so_id order by x.line_no
  loop
    select coalesce(sum((e->>'units')::numeric), 0) into v_sum from jsonb_array_elements(l.bins) e;
    v_ship := least(v_sum, floor(l.verified_ea / l.pack_factor), l.target);
    if v_ship < 0 then v_ship := 0; end if;
    v_cut := v_sum - v_ship;  v_bins := l.bins;
    i := jsonb_array_length(v_bins) - 1;
    while v_cut > 0 and i >= 0 loop                              -- 마지막 칸부터 줄인다(⬜6)
      v_bins := jsonb_set(v_bins, array[i::text, 'units'], to_jsonb(greatest((v_bins->i->>'units')::numeric - v_cut, 0)));
      v_cut := v_cut - least(v_cut, (l.bins->i->>'units')::numeric);  i := i - 1;
    end loop;
    v_picks := v_picks || coalesce((select jsonb_agg(jsonb_build_object('line_id', l.id, 'bin', e->>'bin', 'qty', (e->>'units')::numeric)) from jsonb_array_elements(v_bins) e where (e->>'units')::numeric > 0), '[]'::jsonb);
    if v_ship < l.target then
      v_shorts := v_shorts || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'target', l.target, 'ship', v_ship);
    end if;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('unit_id', u.id, 'unit_type', u.unit_type, 'label', u.label, 'parent_unit_id', u.parent_id, 'status', u.status,
           'length_in', u.length_in, 'width_in', u.width_in, 'height_in', u.height_in, 'weight_lb', u.weight_lb, 'height_note', u.height_note, 'weight_note', u.weight_note,
           'items', coalesce((select jsonb_agg(jsonb_build_object('line_id', it.order_line_id, 'qty', round(it.qty / sl.pack_factor, 4), 'qty_base', it.qty) order by sl.line_no)
                              from (select pi.order_line_id, sum(pi.qty_base) as qty from public.wms_pallet_items pi where pi.pallet_id = u.id and pi.order_id = p_so_id group by pi.order_line_id) it
                              join public.wms_order_doc_line sl on sl.line_id = it.order_line_id), '[]'::jsonb)) order by u.parent_id nulls first, u.id), '[]'::jsonb),
         count(*) filter (where u.length_in is null or u.width_in is null or u.height_in is null or u.weight_lb is null)
    into v_units, v_nodim
  from public.wms_pallets u
  where u.order_id = p_so_id or u.parent_id in (select p2.id from public.wms_pallets p2 where p2.order_id = p_so_id);
  return jsonb_build_object('so_id', v_doc.doc_id, 'so_number', v_doc.doc_number, 'status', v_doc.status, 'all_packed', v_all,
                            'picks', v_picks, 'units', v_units, 'shorts', v_shorts, 'units_without_dims', coalesce(v_nodim, 0));
end;
$$;

-- ── wms_rollback ──
create or replace function public.wms_rollback(p_so_id uuid, p_action text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_pack constant text[] := array['short_after_pack', 'over_pick', 'pack_scan_mistake'];
  v_staff uuid;  v_doc public.wms_order_doc%rowtype;  v_fin public.wms_order_finalize%rowtype;
  v_ids bigint[];  v_wids bigint[];  v_wid bigint;
  v_arch int := 0;  v_void int := 0;  v_reopen int := 0;  v_status text;  v_from text;  v_to text;  v_orig uuid;  i int;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');
  v_staff := public.so_current_staff();
  if p_action not in ('finalize', 'fulfillment', 'pack', 'pick', 'split') then raise exception 'Unknown rollback action % — nothing was saved', p_action; end if;
  perform 1 from public.so s where s.id = p_so_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_doc.warehouse_id) then              -- ⭐ 둘째
    raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_doc.doc_number;
  end if;
  select * into v_fin from public.wms_order_finalize f where f.order_id = p_so_id;
  if p_action = 'finalize' then
    if v_doc.status <> 'packed' or v_fin.order_id is null then raise exception 'Order % is not finalized (%) — nothing was saved', v_doc.doc_number, v_doc.status; end if;
  else
    if v_doc.status = 'packed' or v_fin.order_id is not null then       -- SO-13893 벨트: Finalize 뒤에는 팩 · 픽 · 배치를 되돌리지 않는다
      raise exception 'Order % is finalized — use Undo Finalize first — nothing was saved', v_doc.doc_number;
    end if;
    if v_doc.status <> 'picking' then raise exception 'Order % is % — nothing to roll back here — nothing was saved', v_doc.doc_number, v_doc.status; end if;
  end if;
  v_status := v_doc.status;
  if p_action in ('finalize', 'fulfillment') then
    -- 팔렛 · 박스 · 담긴 것(운영 deleteFulfillmentRows) — 담긴 것 삭제 → 빈 유닛(담긴 것 0 · 자식 0) 삭제 · finalize 기록 삭제 · SO packed → picking
    v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_doc.doc_number, null, 'wms_pallet_items', format('order_id = %L', p_so_id));
    delete from public.wms_pallet_items where order_id = p_so_id;
    for i in 1 .. 2 loop                                               -- 두 단계: 빈 박스(자식) → 빈 팔렛(부모) · 담긴 것이 남은 유닛은 둔다(운영 deleteFulfillmentRows)
      v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_doc.doc_number, null, 'wms_pallets',
                  format('(order_id = %L or parent_id in (select id from public.wms_pallets where order_id = %L)) and not exists (select 1 from public.wms_pallet_items i where i.pallet_id = t.id) and not exists (select 1 from public.wms_pallets c where c.parent_id = t.id)', p_so_id, p_so_id));
      delete from public.wms_pallets u where (u.order_id = p_so_id or u.parent_id in (select id from public.wms_pallets where order_id = p_so_id))
        and not exists (select 1 from public.wms_pallet_items i where i.pallet_id = u.id) and not exists (select 1 from public.wms_pallets c where c.parent_id = u.id);
    end loop;
    if p_action = 'finalize' then
      v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_doc.doc_number, null, 'wms_order_finalize', format('order_id = %L', p_so_id));
      delete from public.wms_order_finalize where order_id = p_so_id;
      perform public.so_wms_status(p_so_id, 'picking', v_staff);
      v_status := 'picking';  v_orig := v_fin.finalized_by;
    end if;
    v_from := case p_action when 'finalize' then 'finalized' else 'fulfilled' end;  v_to := 'pack_complete';
  elsif p_action = 'pack' then
    if exists (select 1 from public.wms_pallet_items i where i.order_id = p_so_id) then raise exception 'Order % has items on pallets — Undo Fulfillment first — nothing was saved', v_doc.doc_number; end if;
    select coalesce(array_agg(id), '{}') into v_ids from public.wms_pack_tasks where order_id = p_so_id;
    select assigned_to into v_orig from public.wms_pack_tasks where order_id = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_doc.doc_number, null, 'wms_pack_tasks', format('order_id = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_doc.doc_number, null, 'wms_pack_task_lines', format('pack_task_id = any(%L::bigint[])', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pack_task_id', v_ids, c_pack, 'pack rollback (order ' || v_doc.doc_number || ')');
    update public.wms_worker_mistakes set reason = 'short_pick', resolved_by = null, resolved_at = null   -- 팩 회복을 다시 연다(오더 단위 · 규칙 14 양방향)
     where order_id = p_so_id and reason = 'resolved_pack_recovery' and voided_at is null and not manager_resolved;
    get diagnostics v_reopen = row_count;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_doc.doc_number, null, 'wms_pick_line_bins', format('pack_task_id = any(%L::bigint[])', v_ids));   -- 판정 57: 팩 회복 칸 행도 팩과 함께 간다(archive → 삭제 · FK cascade 는 안전망)
    delete from public.wms_pick_line_bins where pack_task_id = any(v_ids);
    delete from public.wms_pack_tasks where order_id = p_so_id;        -- 줄은 cascade
    v_from := 'pack_complete';  v_to := 'pick_complete';
  elsif p_action = 'pick' then
    if exists (select 1 from public.wms_pack_tasks k where k.order_id = p_so_id) then raise exception 'Order % has packing — Undo Pack first — nothing was saved', v_doc.doc_number; end if;
    select coalesce(array_agg(id), '{}') into v_ids from public.wms_pick_tasks where order_id = p_so_id;
    select assigned_to into v_orig from public.wms_pick_tasks where order_id = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_doc.doc_number, null, 'wms_pick_tasks', format('order_id = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_doc.doc_number, null, 'wms_pick_task_lines', format('pick_task_id = any(%L::bigint[])', v_ids));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_doc.doc_number, null, 'wms_pick_line_bins', format('not planned and pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(%L::bigint[]))', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', v_ids, array['short_pick'], 'pick reset (order ' || v_doc.doc_number || ')');
    delete from public.wms_pick_line_bins b where not b.planned and b.pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(v_ids));
    update public.wms_pick_task_lines set picked_base = 0, status = 'pending', verification_method = null, picked_at = null, picked_by = null where pick_task_id = any(v_ids);
    update public.wms_pick_tasks set status = 'pending', assigned_to = null, started_at = null, completed_at = null, completed_by = null, heartbeat_at = null, work_started = false, held_by = null, session_id = null where order_id = p_so_id;
    v_from := 'pick_complete';  v_to := 'pick_reset';
  else   -- split
    if exists (select 1 from public.wms_pack_tasks k where k.order_id = p_so_id) then raise exception 'Order % has packing — Undo Pack first — nothing was saved', v_doc.doc_number; end if;
    select coalesce(array_agg(id), '{}'), coalesce(array_agg(distinct wave_id) filter (where wave_id is not null), '{}') into v_ids, v_wids from public.wms_pick_tasks where order_id = p_so_id;
    select assigned_to into v_orig from public.wms_pick_tasks where order_id = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_doc.doc_number, null, 'wms_pick_tasks', format('order_id = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_doc.doc_number, null, 'wms_pick_task_lines', format('pick_task_id = any(%L::bigint[])', v_ids));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_doc.doc_number, null, 'wms_pick_line_bins', format('pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(%L::bigint[]))', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', v_ids, array['short_pick'], 'split undo (order ' || v_doc.doc_number || ')');
    delete from public.wms_pick_tasks where order_id = p_so_id;        -- 줄 · 칸 행은 cascade
    foreach v_wid in array v_wids loop                                 -- 이 되돌리기로 빈 웨이브는 지운다(운영 doVoid 와 같다)
      if not exists (select 1 from public.wms_pick_tasks t where t.wave_id = v_wid) then
        v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_doc.doc_number, null, 'wms_waves', format('id = %L', v_wid));
        delete from public.wms_waves where id = v_wid;
      end if;
    end loop;
    perform public.so_wms_status(p_so_id, 'at_wms', v_staff);        -- 과제 0 → 판정 18
    v_status := 'at_wms';  v_from := 'split';  v_to := 'unsplit';
  end if;
  insert into public.wms_rollback_log (order_id, order_number, action, from_stage, to_stage, performed_by, original_worker)
  values (p_so_id, v_doc.doc_number, p_action, v_from, v_to, v_staff, v_orig);
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_doc.doc_number, 'action', p_action, 'status', v_status, 'archived', v_arch, 'voided', v_void, 'reopened', v_reopen);
end;
$$;

-- ── wms_rollback_batch ──
create or replace function public.wms_rollback_batch(p_task_id bigint, p_kind text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_pack constant text[] := array['short_after_pack', 'over_pick', 'pack_scan_mistake'];
  v_staff uuid;  v_doc public.wms_order_doc%rowtype;  v_label text;  v_orig uuid;  v_so_id uuid;
  v_arch int := 0;  v_void int := 0;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');
  v_staff := public.so_current_staff();
  if p_kind not in ('pack', 'pick') then raise exception 'Unknown batch rollback kind % — nothing was saved', p_kind; end if;
  if p_kind = 'pack' then select k.order_id, k.batch_label, k.assigned_to into v_so_id, v_label, v_orig from public.wms_pack_tasks k where k.id = p_task_id;
  else select t.order_id, t.batch_label, t.assigned_to into v_so_id, v_label, v_orig from public.wms_pick_tasks t where t.id = p_task_id; end if;
  if v_so_id is null then raise exception 'Task not found — nothing was saved'; end if;
  perform 1 from public.so s where s.id = v_so_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
  select * into v_doc from public.wms_order_doc d where d.doc_id = v_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not public.ims_can_warehouse(v_doc.warehouse_id) then              -- ⭐ 둘째
    raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_doc.doc_number;
  end if;
  if v_doc.status = 'packed' or exists (select 1 from public.wms_order_finalize f where f.order_id = v_so_id) then
    raise exception 'Order % is finalized — use Undo Finalize first — nothing was saved', v_doc.doc_number;
  end if;
  if p_kind = 'pack' then
    if exists (select 1 from public.wms_pallet_items i where i.pack_task_id = p_task_id) then raise exception 'Batch % is on a pallet — Undo Fulfillment first — nothing was saved', v_label; end if;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', v_so_id, v_doc.doc_number, v_label, 'wms_pack_tasks', format('id = %L', p_task_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', v_so_id, v_doc.doc_number, v_label, 'wms_pack_task_lines', format('pack_task_id = %L', p_task_id));
    v_void := public.wms_rb_void(v_staff, 'pack_task_id', array[p_task_id], c_pack, 'pack rollback ' || v_label);
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', v_so_id, v_doc.doc_number, v_label, 'wms_pick_line_bins', format('pack_task_id = %L', p_task_id));   -- 판정 57: 이 팩의 회복 칸 행
    delete from public.wms_pick_line_bins where pack_task_id = p_task_id;
    delete from public.wms_pack_tasks where id = p_task_id;             -- 배치 단위는 회복을 재개하지 않는다(규칙 14 · 남은 팩이 있다)
  else
    if exists (select 1 from public.wms_pack_tasks k where k.pick_task_id = p_task_id) then raise exception 'Batch % already has packing — Undo Pack first — nothing was saved', v_label; end if;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', v_so_id, v_doc.doc_number, v_label, 'wms_pick_tasks', format('id = %L', p_task_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', v_so_id, v_doc.doc_number, v_label, 'wms_pick_task_lines', format('pick_task_id = %L', p_task_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', v_so_id, v_doc.doc_number, v_label, 'wms_pick_line_bins', format('not planned and pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = %L)', p_task_id));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', array[p_task_id], array['short_pick'], 'pick reset ' || v_label);
    delete from public.wms_pick_line_bins b where not b.planned and b.pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = p_task_id);
    update public.wms_pick_task_lines set picked_base = 0, status = 'pending', verification_method = null, picked_at = null, picked_by = null where pick_task_id = p_task_id;
    update public.wms_pick_tasks set status = 'pending', assigned_to = null, started_at = null, completed_at = null, completed_by = null, heartbeat_at = null, work_started = false, held_by = null, session_id = null where id = p_task_id;
  end if;
  insert into public.wms_rollback_log (order_id, order_number, action, from_stage, to_stage, performed_by, batch_label, original_worker)
  values (v_so_id, v_doc.doc_number, p_kind, case p_kind when 'pack' then 'pack_complete' else 'pick_complete' end, case p_kind when 'pack' then 'pick_complete' else 'pick_reset' end, v_staff, v_label, v_orig);
  return jsonb_build_object('so_id', v_so_id, 'so_number', v_doc.doc_number, 'batch_label', v_label, 'kind', p_kind, 'archived', v_arch, 'voided', v_void);
end;
$$;

-- ── wms_unwave ──
create or replace function public.wms_unwave(p_wave_id bigint) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_w public.wms_waves%rowtype;  v_ids bigint[];  v_oids uuid[];  v_id uuid;  v_doc public.wms_order_doc%rowtype;
  v_arch int := 0;  v_void int := 0;  v_back int := 0;
begin
  perform public.ims_require_write('wms_manage', 'saved');            -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');
  v_staff := public.so_current_staff();
  select * into v_w from public.wms_waves w where w.id = p_wave_id for update;
  if not found then raise exception 'Wave not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_w.warehouse_id) then              -- ⭐ 둘째
    raise exception 'Wave % is at another warehouse — you are not set up for it — nothing was saved', v_w.label;
  end if;
  select coalesce(array_agg(t.id), '{}'), coalesce(array_agg(distinct t.order_id), '{}') into v_ids, v_oids from public.wms_pick_tasks t where t.wave_id = p_wave_id;
  foreach v_id in array v_oids loop
    perform 1 from public.so s where s.id = v_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    if v_doc.status = 'packed' or exists (select 1 from public.wms_order_finalize f where f.order_id = v_id) then
      raise exception 'Order % in wave % is finalized — use Undo Finalize first — nothing was saved', v_doc.doc_number, v_w.label;
    end if;
    if exists (select 1 from public.wms_pack_tasks k where k.pick_task_id = any(v_ids) and k.order_id = v_id) then
      raise exception 'Order % in wave % already has packing — Undo Pack first — nothing was saved', v_doc.doc_number, v_w.label;
    end if;
  end loop;
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'unwave', null, null, v_w.label, 'wms_pick_tasks', format('wave_id = %L', p_wave_id));
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'unwave', null, null, v_w.label, 'wms_pick_task_lines', format('pick_task_id = any(%L::bigint[])', v_ids));
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'unwave', null, null, v_w.label, 'wms_pick_line_bins', format('pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(%L::bigint[]))', v_ids));
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'unwave', null, null, v_w.label, 'wms_waves', format('id = %L', p_wave_id));
  v_void := public.wms_rb_void(v_staff, 'pick_task_id', v_ids, array['short_pick'], 'wave undo ' || v_w.label);
  delete from public.wms_pick_tasks where wave_id = p_wave_id;         -- 줄 · 칸 행 cascade
  delete from public.wms_waves where id = p_wave_id;
  foreach v_id in array v_oids loop                                    -- 과제 0 이 된 오더만 at_wms(판정 18)
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    if v_doc.status = 'picking' and not exists (select 1 from public.wms_pick_tasks t where t.order_id = v_id) then
      perform public.so_wms_status(v_id, 'at_wms', v_staff);  v_back := v_back + 1;
    end if;
    insert into public.wms_rollback_log (order_id, order_number, action, from_stage, to_stage, performed_by, batch_label)
    values (v_id, v_doc.doc_number, 'unwave', 'wave', 'unsplit', v_staff, v_w.label);
  end loop;
  return jsonb_build_object('wave_id', p_wave_id, 'label', v_w.label, 'orders', cardinality(v_oids), 'tasks', cardinality(v_ids), 'back_to_at_wms', v_back, 'archived', v_arch, 'voided', v_void);
end;
$$;

-- ── wms_review_set ──
create or replace function public.wms_review_set(p_so_id uuid, p_reviewed boolean) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_doc public.wms_order_doc%rowtype;  v_r public.wms_order_review%rowtype;
begin
  perform public.ims_require_write('fulfillment', 'saved');            -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_doc.warehouse_id) then
    raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_doc.doc_number;
  end if;
  insert into public.wms_order_review as r (order_id, reviewed, reviewed_by, reviewed_at, cleared_by, cleared_at)
  values (p_so_id, p_reviewed, case when p_reviewed then v_staff end, case when p_reviewed then now() end, case when not p_reviewed then v_staff end, case when not p_reviewed then now() end)
  on conflict (order_id) do update
    set reviewed    = excluded.reviewed,
        reviewed_by = case when excluded.reviewed then v_staff else r.reviewed_by end,
        reviewed_at = case when excluded.reviewed then now()   else r.reviewed_at end,
        cleared_by  = case when excluded.reviewed then r.cleared_by else v_staff end,
        cleared_at  = case when excluded.reviewed then r.cleared_at else now()   end
  returning * into v_r;
  return to_jsonb(v_r) || jsonb_build_object('so_number', v_doc.doc_number);
end;
$$;

-- ── wms_health_check ──
create or replace function public.wms_health_check() returns table(sort integer, check_key text, category text, title text, hint text, fail_count bigint, sample jsonb)
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
    select d.doc_number as so_number, l.line_no, l.sku,
           l.qty_target_ea as need_ea,
           sum(pl.assigned_base) as assigned_ea
      from public.wms_order_doc d
      join public.wms_order_doc_line l on l.doc_id = d.doc_id
      join public.wms_pick_task_lines pl on coalesce(pl.order_line_id, pl.transfer_line_id) = l.line_id
      join public.wms_pick_tasks t on t.id = pl.pick_task_id and coalesce(t.order_id, t.transfer_id) = d.doc_id
     where d.status in ('picking', 'packed')
     group by d.doc_number, l.line_no, l.sku, l.qty_target_ea
    having sum(pl.assigned_base) is distinct from l.qty_target_ea
  ),
  short_nd as (
    select d.doc_number as so_number, t.batch_label, l.sku, pl.assigned_base, pl.picked_base
      from public.wms_pick_task_lines pl
      join public.wms_pick_tasks t on t.id = pl.pick_task_id
      join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
      join public.wms_order_doc_line l on l.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
     where pl.status = 'short'
       and not exists (select 1 from public.wms_worker_mistakes m
                        where coalesce(m.order_id, m.transfer_id) = d.doc_id and m.sku = l.sku and m.reason in ('short_pick', 'resolved_pack_recovery') and m.voided_at is null)
       and not exists (select 1 from public.wms_reports r                 -- ⑤-5c3: 「Not enough stock」 신고(판정 20 · 24-b 로 갈린 쪽)도 모자람을 설명한다 · resolved 무관
                        where coalesce(r.order_id, r.transfer_id) = d.doc_id and r.sku = l.sku and r.kind = 'stock_short')
  ),
  pick_over as (
    select d.doc_number as so_number, t.batch_label, l.sku, pl.assigned_base, pl.picked_base
      from public.wms_pick_task_lines pl
      join public.wms_pick_tasks t on t.id = pl.pick_task_id
      join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
      join public.wms_order_doc_line l on l.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
     where pl.picked_base > pl.assigned_base
  ),
  fin_pair as (
    select d.doc_number as so_number, d.status, (coalesce(f.order_id, f.transfer_id) is not null) as has_finalize_row, f.finalized_at
      from public.wms_order_doc d
      left join public.wms_order_finalize f on coalesce(f.order_id, f.transfer_id) = d.doc_id
     where (d.status = 'packed' and coalesce(f.order_id, f.transfer_id) is null)
        or (coalesce(f.order_id, f.transfer_id) is not null and d.status in ('draft', 'confirmed', 'at_wms', 'picking', 'cancelled'))
  ),
  orphan_task as (
    select d.doc_number as so_number, d.status, count(t.id) as pick_tasks, string_agg(t.batch_label, ', ' order by t.batch_label) as batches
      from public.wms_order_doc d
      join public.wms_pick_tasks t on coalesce(t.order_id, t.transfer_id) = d.doc_id
     where d.status in ('draft', 'confirmed', 'at_wms', 'cancelled')
     group by d.doc_id, d.doc_number, d.status
  ),
  orphan_pack as (
    select k.id as pack_task_id, k.batch_label, d.doc_number as so_number, k.status as pack_status, t.status as pick_status
      from public.wms_pack_tasks k
      join public.wms_order_doc d on d.doc_id = coalesce(k.order_id, k.transfer_id)
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
    union all                                                            -- ⑤-6b 입고 가지(판정 37 「receipt 는 ⑤-6」): 열린 보류가 draft 아닌 입고 · 창고 Complete 된 입고 · 한 입고에 둘
    select h.id, 'receipt'::text, null::bigint, h.worker, h.held_at,
           r.status, exists (select 1 from public.wms_receipt_complete c where c.receipt_id = r.id and c.completed), h.rn
      from (select th.*, row_number() over (partition by th.receipt_id order by th.held_at desc) as rn
              from public.wms_task_holds th
             where th.resumed_at is null and th.receipt_id is not null) h
      join public.po_receipt r on r.id = h.receipt_id
     where h.rn > 1
        or r.status <> 'draft'
        or exists (select 1 from public.wms_receipt_complete c where c.receipt_id = r.id and c.completed)
  ),
  recv_nc as (                                                           -- ⑤-6b 창고 Complete 뒤 24h 넘게 오피스 확정이 없다(여전히 draft)
    select r.receipt_number, p.po_number, c.completed_at, c.completed_by
      from public.wms_receipt_complete c
      join public.po_receipt r on r.id = c.receipt_id
      join public.po p on p.id = r.po_id
     where c.completed and r.status = 'draft' and c.completed_at < now() - c_stale
  ),
  recv_stale as (                                                        -- ⑤-6b 초안인데 작업 줄 0 · 만든 지 24h 넘음(열어 두고 아무것도 안 셈)
    select r.receipt_number, p.po_number, r.created_at, r.created_by
      from public.po_receipt r
      join public.po p on p.id = r.po_id
     where r.status = 'draft' and r.created_at < now() - c_stale
       and not exists (select 1 from public.po_receipt_work w where w.receipt_id = r.id)
  ),
  offpo_und as (                                                         -- ⑤-6c1 off-PO 가 정해지지 않은 채 24h(판정 43 대가 — 선반에는 있고 장부에는 없다)
    select r.receipt_number, pr.sku, d.received_qty, (d.placed_at is not null) as on_shelf, b.name as bin, d.created_at
      from public.po_receipt_diff d
      join public.po_receipt r on r.id = d.receipt_id
      join public.product pr on pr.id = d.product_id
      left join public.ref_bin b on b.id = d.bin_id
     where d.kind = 'off_po' and d.resolved_at is null and d.created_at < now() - c_stale
  ),
  offpo_rej as (                                                         -- ⑤-6c1 거절됐는데 선반에서 뺐다는 확인이 없다 24h
    select r.receipt_number, pr.sku, d.received_qty, b.name as bin, d.resolved_at, d.resolved_by
      from public.po_receipt_diff d
      join public.po_receipt r on r.id = d.receipt_id
      join public.product pr on pr.id = d.product_id
      left join public.ref_bin b on b.id = d.bin_id
     where d.kind = 'off_po' and d.resolution = 'rejected' and d.bin_id is not null and d.removed_at is null and d.resolved_at < now() - c_stale
  ),
  picking_nt as (
    select d.doc_number as so_number, d.picking_at, d.picking_by
      from public.wms_order_doc d
     where d.status = 'picking' and not exists (select 1 from public.wms_pick_tasks t where coalesce(t.order_id, t.transfer_id) = d.doc_id)
  ),
  packed_nf as (
    select d.doc_number as so_number, v.pick_batches, v.packs_done, max(k.completed_at) as last_pack_at
      from public.wms_order_doc d
      join public.wms_order_pack_progress v on v.order_id = d.doc_id
      join public.wms_pack_tasks k on coalesce(k.order_id, k.transfer_id) = d.doc_id and k.status = 'completed'
     where d.status = 'picking' and v.all_packed
     group by d.doc_id, d.doc_number, v.pick_batches, v.packs_done
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
  adj_nl as (                                                            -- adj-a 2026-09-28 확정된 조정인데 원장 행이 없다(delta 0 줄뿐인 문서는 제외)
    select a.adjust_number, a.confirmed_at, a.warehouse
      from public.inv_adjust a
     where a.status = 'confirmed'
       and exists (select 1 from public.inv_adjust_line l where l.adjust_id = a.id and l.delta <> 0)
       and not exists (select 1 from public.inv_ledger e where e.doc_type = 'adjustment' and e.doc_number = a.adjust_number and e.source = 'ims')
  ),
  mv_nl as (                                                             -- trf-a 2026-09-28 확정된 칸 옮기기인데 원장 행이 없다
    select m.move_number, m.confirmed_at, m.warehouse
      from public.inv_move m
     where m.status = 'confirmed'
       and exists (select 1 from public.inv_move_line l where l.move_id = m.id)
       and not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = m.move_number and e.source = 'ims')
  ),
  plan_short as (                                                        -- trf-a 열린 과제(pending · in_progress)의 계획 칸 합이 그 칸 장부보다 크다 — 피커가 빈 칸으로 간다(원인 무관 · 칸 옮기기 뒤 · 조정 뒤 · 낡은 계획)
    select s0.warehouse, s0.bin, s0.sku, s0.planned_ea, s0.ledger_ea, s0.batches
      from (select d.warehouse_name as warehouse, b.bin, coalesce(pp.sku, pr.sku) as sku, sum(b.qty_base) as planned_ea,
                   coalesce(max(v.qty), 0) as ledger_ea, string_agg(distinct t.batch_label, ', ') as batches
              from public.wms_pick_line_bins b
              join public.wms_pick_task_lines pl on pl.id = b.pick_task_line_id
              join public.wms_pick_tasks t on t.id = pl.pick_task_id
              join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
              join public.wms_order_doc_line l on l.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
              join public.product pr on pr.id = l.product_id
              left join public.product pp on pp.id = pr.parent_product_id
              left join public.inv_balance v on v.sku = coalesce(pp.sku, pr.sku) and v.warehouse = d.warehouse_name and v.bin = b.bin
             where b.planned and t.status in ('pending', 'in_progress')
             group by d.warehouse_name, b.bin, coalesce(pp.sku, pr.sku)) s0
     where s0.planned_ea > s0.ledger_ea
  ),
  bin_neg as (                                                           -- trf-a 칸 잔고가 음수 — 어디선가 실제와 다른 칸에서 뺐다(칸 없는 행 · 운송 중은 제외)
    select v.warehouse, v.bin, v.sku, v.qty
      from public.inv_balance v
     where v.qty < 0 and v.bin <> '' and v.warehouse in (select w.name from public.ref_warehouse w)
  ),
  last_rel as (
    select max(d.at_wms_at) as last_at,
           to_char(max(d.at_wms_at) at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI') as last_at_toronto,
           round(extract(epoch from (now() - max(d.at_wms_at))) / 60)::int as minutes_ago
      from public.wms_order_doc d
  )
  select 10, 'line_split_sum', 'critical', 'Line split sum',
    'For every line of an order in warehouse work (Working / Finalized) the batch assignments in base units must add up to (ordered - removed) x pack factor. A row here means a split lost or double-counted units. Lines that have no batch line at all are not listed here (see Working order without batches).',
    (select count(*) from line_split), (select jsonb_agg(t) from (select * from line_split limit 8) t)
  union all
  select 20, 'short_no_disc', 'warn', 'Short pick without a mistake row',
    'A pick line marked short with neither a short-pick mistake row nor a Not enough stock report for the same order and SKU (voided mistake rows do not count; a report explains the shortfall whether or not it is resolved) - the shortfall vanished silently. Match key: order + SKU; verify if unsure.',
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
    'An open hold row (not resumed) whose batch is not pending-and-held, or two open rows on one batch - the resume close was lost, so its hold time will silently not be subtracted in Stats. Deleted batches (rollback) are intentionally not flagged. Receipt rows: an open hold on a receipt that is no longer a draft, or already completed in the warehouse, or two open holds on one receipt.',
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
  select 130, 'receipt_completed_not_confirmed', 'warn', 'Receipt completed in the warehouse but not confirmed for 24h',
    'The warehouse pressed Complete more than 24 hours ago and the office has not confirmed the receipt (it is still a draft) - the goods are in their bins but not in the books. Confirm it in Purchase Receipts, or reopen it if the count was wrong.',
    (select count(*) from recv_nc), (select jsonb_agg(t) from (select * from recv_nc limit 8) t)
  union all
  select 140, 'stale_receipt_draft', 'warn', 'Receipt draft with nothing counted for 24h',
    'A receipt was started more than 24 hours ago and nothing has been counted on it. Usually someone pressed Start and walked away - delete the empty draft (Receiving tab) or count the goods.',
    (select count(*) from recv_stale), (select jsonb_agg(t) from (select * from recv_stale limit 8) t)
  union all
  select 150, 'off_po_undecided', 'warn', 'Off-PO item waiting for a decision for 24h',
    'An item scanned at the dock that is not on the PO has been waiting more than 24 hours for the office to accept (free or billed) or reject it. Until then it sits on the shelf but not in the books - decide it in Purchase Receipts (the WMS Admin Receiving tab links there).',
    (select count(*) from offpo_und), (select jsonb_agg(t) from (select * from offpo_und limit 8) t)
  union all
  select 160, 'off_po_rejected_on_shelf', 'warn', 'Rejected off-PO item still on the shelf for 24h',
    'The office rejected an off-PO item more than 24 hours ago and nobody confirmed taking it off the shelf. Pickers may find stock that is not in the books - take it off and press Removed in the receiving screen.',
    (select count(*) from offpo_rej), (select jsonb_agg(t) from (select * from offpo_rej limit 8) t)
  union all
  select 170, 'adjust_confirmed_no_ledger', 'critical', 'Confirmed stock adjustment without ledger rows',
    'A confirmed stock adjustment with a non-zero line has no ledger rows - the confirm transaction was interrupted between the document and the ledger. Stock is wrong until inv_post_adjust is run by the DB owner.',
    (select count(*) from adj_nl), (select jsonb_agg(t) from (select * from adj_nl limit 8) t)
  union all
  select 175, 'move_confirmed_no_ledger', 'critical', 'Confirmed bin move without ledger rows',
    'A confirmed bin move has no ledger rows - the confirm transaction was interrupted between the document and the ledger. Bin balances are wrong until inv_post_move is run by the DB owner.',
    (select count(*) from mv_nl), (select jsonb_agg(t) from (select * from mv_nl limit 8) t)
  union all
  select 180, 'planned_bin_short', 'warn', 'Pick plan points at a bin with less stock than planned',
    'Open pick tasks (waiting or in progress) plan more units from a bin than the ledger has there - the picker will find an empty or short bin. Usual causes: a bin move or an adjustment made after the batch was built, or a stale plan. Re-plan the batch or move the stock back.',
    (select count(*) from plan_short), (select jsonb_agg(t) from (select * from plan_short limit 8) t)
  union all
  select 185, 'bin_negative', 'warn', 'Bin balance below zero',
    'A bin reads a negative quantity in the ledger - units were deducted from a bin that did not have them (a pick recorded against the planned bin while the stock was elsewhere, or a move that was never recorded). Find the stock and fix it with a bin move or an adjustment.',
    (select count(*) from bin_neg), (select jsonb_agg(t) from (select * from bin_neg limit 8) t)
  union all
  select 200, 'last_release', 'info', 'Last release to WMS',
    'Newest Release to WMS from the office (Toronto time) - the signal that orders are still flowing into the warehouse. A long gap is normal when the office has nothing to release.',
    0::bigint, (select jsonb_build_object('last_at', last_at, 'last_at_toronto', last_at_toronto, 'minutes_ago', minutes_ago) from last_rel)
  order by 1;
end
$$;

-- ── inv_adjust_picked ──
create or replace function public.inv_adjust_picked(p_warehouse_id uuid, p_bin_id uuid, p_product_id uuid) returns numeric
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select coalesce(sum(pb.qty_base), 0)
    from public.wms_pick_line_bins pb
    join public.wms_pick_task_lines pl on pl.id = pb.pick_task_line_id
    join public.wms_pick_tasks t on t.id = pl.pick_task_id
    join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
    join public.wms_order_doc_line l on l.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
    join public.product pr on pr.id = l.product_id
   where not pb.planned and pb.bin_id = p_bin_id and d.warehouse_id = p_warehouse_id
     and d.status in ('picking', 'packed') and coalesce(pr.parent_product_id, pr.id) = p_product_id;
$$;

-- ── inv_move_open_plans ──
create or replace function public.inv_move_open_plans(p_warehouse_id uuid, p_bin_id uuid, p_product_id uuid)
  returns table(row_id bigint, task_id bigint, batch_label text, so_number text, task_status text, pick_task_line_id bigint,
                planned_qty numeric, covered_qty numeric, blocking_qty numeric, movable_qty numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with ln as (
    select pl.id as line_id, t.id as task_id, t.batch_label, d.doc_number as so_number, t.status as task_status,
           greatest(coalesce(pl.picked_base, 0) - coalesce((select sum(a.qty_base) from public.wms_pick_line_bins a where a.pick_task_line_id = pl.id and not a.planned), 0), 0) as unwritten,
           coalesce((select sum(a.qty_base) from public.wms_pick_line_bins a where a.pick_task_line_id = pl.id and not a.planned and a.bin_id = p_bin_id), 0) as actual_here
      from public.wms_pick_task_lines pl
      join public.wms_pick_tasks t on t.id = pl.pick_task_id
      join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
      join public.wms_order_doc_line l on l.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
      join public.product pr on pr.id = l.product_id
     where t.status in ('pending', 'in_progress') and d.warehouse_id = p_warehouse_id and d.wms_stage in ('at_wms', 'picking')
       and coalesce(pr.parent_product_id, pr.id) = p_product_id
  ), r as (
    select b.id as row_id, ln.line_id, ln.task_id, ln.batch_label, ln.so_number, ln.task_status, ln.unwritten, ln.actual_here, b.bin_id, b.qty_base,
           coalesce(sum(b.qty_base) over (partition by b.pick_task_line_id order by b.id rows between unbounded preceding and 1 preceding), 0) as before_qty
      from public.wms_pick_line_bins b join ln on ln.line_id = b.pick_task_line_id
     where b.planned
  ), c as (
    select r.*, least(r.qty_base, greatest(r.unwritten - r.before_qty, 0)) as covered from r where r.bin_id = p_bin_id
  )
  select c.row_id, c.task_id, c.batch_label, c.so_number, c.task_status, c.line_id, c.qty_base, c.covered,
         case when c.task_status = 'in_progress' then greatest(c.qty_base - c.actual_here, 0) else c.covered end,
         case when c.task_status = 'in_progress' then 0 else c.qty_base - c.covered end
    from c order by c.task_id, c.row_id;
$$;

-- ── inv_adjust_from_report ──
create or replace function public.inv_adjust_from_report(p_report_id bigint) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not public.ims_can_adjust_read() then null::jsonb else (
    select jsonb_build_object(
      'report', jsonb_build_object('id', r.id, 'kind', r.kind, 'order_number', r.order_number, 'sku', r.sku, 'qty_expected', r.qty_expected, 'qty_found', r.qty_found, 'note', r.note, 'resolved_at', r.resolved_at, 'created_at', r.created_at),
      'warehouse_id', s.warehouse_id, 'warehouse', s.warehouse_name, 'order_status', s.status,
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('product_id', b.pid, 'sku', b.base_sku, 'bin_id', b.bin_id, 'bin', b.bin, 'picked_this_order', b.qty,
                                                              'ledger', public.inv_adjust_ledger(s.warehouse_name, b.bin, b.base_sku), 'picked', public.inv_adjust_picked(s.warehouse_id, b.bin_id, b.pid),
                                                              'suggested_mode', 'set', 'suggested_qty', 0) order by b.bin), '[]'::jsonb)
                  from (select coalesce(pr.parent_product_id, pr.id) as pid, coalesce(pp.sku, pr.sku) as base_sku, pb.bin_id, pb.bin, sum(pb.qty_base) as qty
                          from public.wms_pick_tasks t join public.wms_pick_task_lines pl on pl.pick_task_id = t.id join public.wms_order_doc_line l on l.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
                          join public.product pr on pr.id = l.product_id left join public.product pp on pp.id = pr.parent_product_id
                          join public.wms_pick_line_bins pb on pb.pick_task_line_id = pl.id and not pb.planned
                         where coalesce(t.order_id, t.transfer_id) = coalesce(r.order_id, r.transfer_id) and l.sku = r.sku group by 1, 2, 3, 4) b))
      from public.wms_reports r join public.wms_order_doc s on s.doc_id = coalesce(r.order_id, r.transfer_id) where r.id = p_report_id and r.kind = 'stock_short') end;
$$;
