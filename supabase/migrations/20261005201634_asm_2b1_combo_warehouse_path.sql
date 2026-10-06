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

-- ─────────────────────────────────────────────────────────────
-- 콤보 오더가 창고를 지나 나가는 길 — 픽 계획 · 창고 문서 줄 · 출고 · POS 완료 · 수동 나누기 (Asung-IMS · asm-2b1 · 2026-10-05)
--   정본(뒤에 적는다): so-module §44 — 판정 244 · asm 묶음 2(재고 · 예약 · 픽 · 출고 · 원가는 구성품 줄) · 4(반쪽 콤보 없음) · 6(픽 화면은 구성품을 뽑는다 「for combo ○○」 · 팩 화면은 콤보 단위 · 창고 조립 없음)
--   앞 차수 asm-1(20261005192944) · asm-2a(20261005195104 · so_line.combo_line_id · combo_qty · 확정은 구성품만 예약) — 이 파일은 2b1(물건이 나가는 길) · 2b2(Finalize · 백오더 · 인보이스 · 세금 · 크레딧 · reprice · requote · merge)는 다음
--   ⭐ 한 자리로 거의 다 닫힌다: 공용 줄 뷰 wms_order_doc_line 이 창고 쪽 열넷(so_pick_plan · wms_pick_task_build · wms_batch_create · wms_wave_create · wms_pick_lines · wms_complete_pack · wms_so_handoff · wms_finalize · wms_pick_shelf
--      · inv_adjust_picked · inv_move_open_plans · inv_adjust_from_report · wms_pick_line_bins_write · wms_health_check)의 유일한 줄 출처다 ⇒ 뷰에서 콤보 줄(구성품이 달린 줄)을 빼고 콤보 매듭 칸 셋을 끝에 더하면 픽 계획 · 과제 · 팩 · 인계 · 마무리 · P · 칸 옮기기가 전부 구성품만 본다
--   든 것:
--     1) 뷰 wms_order_doc_line 재정의 — so 갈래에서 콤보 줄 제외 · 끝에 combo_line_id · combo_qty · combo_sku(트랜스퍼 갈래 null) · security_invoker · 권한 그대로(create or replace · 열 추가는 끝에만)
--     2) 재발행 여섯(마지막 정의 · DB prosrc md5 와 바이트 일치 확인 뒤 복사 · 바뀐 줄만 · 보고에 diff `<` 원문) —
--        wms_pick_lines(20260930172829 · 줄에 combo 셋) · so_ship(20260925142307 · 콤보 줄 픽 거부 · 줄 고리에서 제외 · 콤보 고리 = 나간 콤보 수 min(구성품 ÷ combo_qty) · 반쪽이면 거부 · 모자라면 콤보 단위 백오더 · ③′ 콤보 줄 qty_shipped · 형제 예약에서 콤보 줄 제외)
--        inv_post_sale(20260924141140 · 콤보 줄 픽 거부) · so_release_to_wms(20260926192314 · 할당 검사에서 콤보 줄 제외) · so_divide(20260925142307 · 콤보 줄 몫 × combo_qty 로 구성품 따라감 · 구성품 줄 거부) · so_merge(20260925151823 · 콤보 오더 합치기는 2b2 — 분명한 문장으로 거부)
--   ⚠️ 재발행 없음 — so_pick_plan · wms_pick_task_build · wms_batch_create · wms_wave_create · wms_complete_pick · wms_complete_pack · wms_so_handoff · wms_finalize(뷰가 가른다) · so_pos_complete(so_pick_plan 의 picks = 구성품만) · so_pos_finish · so_pos_reopen · so_cancel · so_delete · so_hold(줄 · 예약 단위 그대로 맞다)
--   ⚠️ 2b1 뒤에도 남는 것(2b2): Finalize 가 구성품 픽을 통째 콤보로 줄이기(지금은 so_ship 이 거부한다) · 백오더 넷 · 인보이스에 구성품 줄 숨기기 · 크레딧 · reprice · requote · merge
--   ⚠️ 부분 유니크 인덱스 없음 · 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 표 · 정책 · 권한 무접촉
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) 뷰 wms_order_doc_line 재정의 — 원문 20260928201753_transfer_1a.sql 413~ · 콤보 줄 제외 · 매듭 칸 셋을 끝에 ═══
create or replace view public.wms_order_doc_line with (security_invoker = true) as
  select 'so'::text as doc_kind,
         l.so_id as doc_id,
         l.id as line_id,
         l.line_no,
         l.product_id,
         l.sku,
         l.product_name,
         l.pack_factor,
         (l.qty_ordered - l.qty_removed) as qty_target,
         ((l.qty_ordered - l.qty_removed) * l.pack_factor) as qty_target_ea,
         coalesce(p.parent_product_id, p.id) as stock_product_id,
         l.combo_line_id,
         l.combo_qty,
         (select c.sku from public.so_line c where c.id = l.combo_line_id) as combo_sku
    from public.so_line l
    join public.product p on p.id = l.product_id
   where not exists (select 1 from public.so_line k where k.combo_line_id = l.id)                                                   -- asm-2b1(판정 244): 콤보 줄은 창고 문서 줄이 아니다 — 구성품 줄이 재고 · 픽 · 출고를 든다
  union all
  select 'transfer'::text as doc_kind,
         l.transfer_id as doc_id,
         l.id as line_id,
         l.line_no,
         l.product_id,
         l.sku,
         p.name as product_name,
         l.pack_factor,
         l.qty as qty_target,
         (l.qty * l.pack_factor) as qty_target_ea,
         coalesce(p.parent_product_id, p.id) as stock_product_id,
         null::uuid as combo_line_id,
         null::numeric as combo_qty,
         null::text as combo_sku
    from public.inv_transfer_line l
    join public.product p on p.id = l.product_id;
comment on view public.wms_order_doc_line is '공용 줄 목록 — so_line(qty_ordered − qty_removed) union all inv_transfer_line(qty) · pack_factor · qty_target_ea · stock_product_id(세트는 parent) · doc_id 로 읽는다 · asm-2b1(판정 244): 콤보 줄(구성품이 달린 줄)은 빠진다 — 구성품 줄이 combo_line_id · combo_qty · combo_sku 를 들고 온다(「for combo ○○」)';

-- ═══ 2) wms_pick_lines 재발행 — 20260930172829_pick_bin_1_line_save.sql 바이트 복사 · 줄에 combo_line_id · combo_qty · combo_sku ═══
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
           x.combo_line_id, x.combo_qty, x.combo_sku,                                                                       -- asm-2b1(판정 244 · 묶음 6): 구성품 줄이 어느 콤보 것인지
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
             'combo_line_id', pl.combo_line_id, 'combo_qty', pl.combo_qty, 'combo_sku', pl.combo_sku,                                              -- asm-2b1: 화면이 「for combo ○○」 를 그린다 · 보통 줄은 null
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

-- ═══ 3) so_ship 재발행 — 20260925142307_so_pos_a2_flow.sql 바이트 복사 · 콤보 줄 픽 거부 · 콤보 고리(나간 콤보 수 · 반쪽 거부 · 콤보 단위 백오더) · ③′ 콤보 줄 qty_shipped · 형제 예약 콤보 줄 제외 ═══
create or replace function public.so_ship(p_so_id uuid, p_picks jsonb, p_staff uuid, p_shipped_on date default null) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so       public.so%rowtype;
  v_wh       public.ref_warehouse%rowtype;
  v_on       date;
  v_bad      text;
  v_norm     jsonb;
  v_lines    jsonb := '[]'::jsonb;
  b_moves    jsonb := '[]'::jsonb;
  b_n        int := 0;
  v_shipped  int := 0;
  v_sib      public.so%rowtype;
  v_warn     text[] := '{}';
  v_ledger   jsonb;
  v_n        int;
  r          record;
  v_from     text;                                              -- ④a2: 「아직 안 나감」 상태 — pos·counter confirmed · warehouse packed(7-c)
  c          record;                                            -- asm-2b1(판정 244 · 묶음 2 · 4): 콤보 줄은 구성품이 나간 만큼 통째로 · 반쪽 콤보는 내보내지 않는다
begin
  if p_staff is null then raise exception 'so_ship needs the acting staff id — nothing was saved'; end if;

  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status = 'shipped' then                               -- 재호출 멱등 — 예외가 아니라 조용한 반환(7-c · wms_complete_pack)
    return jsonb_build_object('shipped', false, 'reason', 'already_shipped', 'so_number', v_so.so_number, 'shipped_at', v_so.shipped_at, 'shipped_by', v_so.shipped_by);
  end if;
  v_from := case when v_so.channel in ('pos', 'counter') then 'confirmed' else 'packed' end;
  if v_so.status <> v_from then
    raise exception 'Order % is % — only a % order can ship here — nothing was saved', v_so.so_number, v_so.status, v_from;
  end if;
  if v_so.location_id is null then raise exception 'Order % has no warehouse — nothing was saved', v_so.so_number; end if;
  select * into v_wh from public.ref_warehouse where id = v_so.location_id;
  if not found or not v_wh.is_active then
    raise exception 'Warehouse % of order % is inactive — nothing was saved', coalesce(v_wh.name, '?'), v_so.so_number;
  end if;
  v_on := coalesce(p_shipped_on, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Ship date % is in the future — nothing was saved', v_on; end if;

  -- 픽 다듬기 — 모양 · 줄 · 수량 · 칸
  if p_picks is null or jsonb_typeof(p_picks) <> 'array' or jsonb_array_length(p_picks) = 0 then
    raise exception 'p_picks must be a JSON array of {line_id, bin, qty} — nothing was saved';
  end if;
  if exists (select 1 from jsonb_array_elements(p_picks) e where nullif(e->>'line_id', '') is null or nullif(e->>'qty', '') is null) then
    raise exception 'Every pick needs a line_id and a qty — nothing was saved';
  end if;
  if exists (select 1 from jsonb_array_elements(p_picks) e where (e->>'qty') !~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' or (e->>'qty')::numeric <= 0) then
    raise exception 'Every pick needs a positive quantity — nothing was saved';
  end if;
  select string_agg(distinct e->>'line_id', ', ') into v_bad
  from jsonb_array_elements(p_picks) e
  where not exists (select 1 from public.so_line l where l.id = (e->>'line_id')::uuid and l.so_id = p_so_id);
  if v_bad is not null then raise exception 'Pick line % is not on order % — nothing was saved', v_bad, v_so.so_number; end if;
  select string_agg(distinct l.line_no::text, ', ') into v_bad                                                                          -- asm-2b1: 콤보 줄에는 픽이 없다 — 구성품 줄이 재고를 든다
  from jsonb_array_elements(p_picks) e join public.so_line l on l.id = (e->>'line_id')::uuid
  where exists (select 1 from public.so_line k where k.combo_line_id = l.id);
  if v_bad is not null then raise exception 'Pick line % of % is a combo line — pick its component lines instead — nothing was saved', v_bad, v_so.so_number; end if;
  select string_agg(distinct x.bin, ', ') into v_bad
  from (select coalesce(nullif(trim(e->>'bin'), ''), '') as bin from jsonb_array_elements(p_picks) e) x
  where x.bin <> '' and not exists (select 1 from public.ref_bin rb where rb.warehouse_id = v_so.location_id and rb.name = x.bin);
  if v_bad is not null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bad, v_wh.name; end if;
  select string_agg(distinct x.bin, ', ') into v_bad
  from (select coalesce(nullif(trim(e->>'bin'), ''), '') as bin from jsonb_array_elements(p_picks) e) x
  join public.ref_bin rb on rb.warehouse_id = v_so.location_id and rb.name = x.bin
  where not rb.is_active;
  if v_bad is not null then v_warn := array_append(v_warn, 'inactive_bin:' || v_bad); end if;   -- 받는다 — 실물이 그 칸에서 나왔다(판정 12 · 안)

  select coalesce(jsonb_agg(jsonb_build_object('line_id', g.line_id, 'bin', g.bin, 'qty', g.qty) order by g.line_id, g.bin), '[]'::jsonb) into v_norm
  from (select (e->>'line_id')::uuid as line_id, coalesce(nullif(trim(e->>'bin'), ''), '') as bin, sum((e->>'qty')::numeric) as qty
        from jsonb_array_elements(p_picks) e group by 1, 2) g;

  -- 줄마다 — 열린 allocated 예약이 있어야(packed 오더는 전부 할당 · R1) · 합 > 주문 거부 · 합 < 주문은 차이
  for r in
    select l.id, l.line_no, l.sku, l.qty_ordered, l.qty_removed, l.qty_ordered - l.qty_removed as target, coalesce(s.qty, 0) as shipped,   -- ⓐ2 판정 5: 목표 = 주문 − 손님이 뺀 것
           exists (select 1 from public.so_reserve x where x.so_line_id = l.id and x.released_at is null and x.kind = 'allocated') as has_alloc
    from public.so_line l
    left join (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s on s.line_id = l.id
    where l.so_id = p_so_id
      and not exists (select 1 from public.so_line k where k.combo_line_id = l.id)                                                   -- asm-2b1: 콤보 줄은 아래 콤보 고리에서(예약 · 픽이 없다)
    order by l.line_no
  loop
    if not r.has_alloc then
      raise exception 'Line % of % (%) has no open allocation — an order must be fully allocated to ship — nothing was saved', r.line_no, v_so.so_number, r.sku;
    end if;
    if r.shipped > r.target then
      raise exception 'Line % of % (%): picked % but % to ship (ordered % minus removed %) — over-pick goes back to its bin, it does not ship — nothing was saved', r.line_no, v_so.so_number, r.sku, r.shipped, r.target, r.qty_ordered, r.qty_removed;
    end if;
    if r.shipped < r.target and v_so.channel in ('pos', 'counter') then   -- ④a2 6-d: pos·counter 에는 백오더가 없다 — 목표 아래 픽은 거부(줄이려면 다시 열기)
      raise exception 'Line % of % (%): picked % of % to ship — a % order ships only what was scanned (no backorder) — reopen the order and fix the line — nothing was saved', r.line_no, v_so.so_number, r.sku, r.shipped, r.target, v_so.channel;
    end if;
    if r.shipped < r.target then                                -- ⓐ2 판정 5·7: 뺀 몫은 백오더가 아니다 · 목표 아래 차이만 pick_short(할인 그대로)
      b_moves := b_moves || jsonb_build_object('line_id', r.id, 'qty', r.target - r.shipped);  b_n := b_n + 1;
    end if;
    if r.shipped > 0 then v_shipped := v_shipped + 1; end if;
    v_lines := v_lines || jsonb_build_object('line_id', r.id, 'line_no', r.line_no, 'sku', r.sku, 'ordered', r.qty_ordered, 'removed', r.qty_removed, 'to_ship', r.target, 'shipped', r.shipped, 'short', r.target - r.shipped);
  end loop;
  -- asm-2b1(묶음 4): 콤보 줄 — 나간 콤보 수 = min(구성품 나간 수 ÷ 콤보 하나의 구성품 수) · 어느 구성품이 그보다 더 나가면 반쪽 콤보라 거부(Finalize 가 먼저 줄인다 · 2b2) · 모자란 콤보는 통째로 백오더(구성품 줄의 몫은 위 고리가 이미 비례로 넣었다)
  for c in
    select p.id, p.line_no, p.sku, p.qty_ordered, p.qty_removed, p.qty_ordered - p.qty_removed as target,
           (select min(floor(coalesce(s.qty, 0) / k.combo_qty)) from public.so_line k
              left join (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s on s.line_id = k.id
             where k.combo_line_id = p.id) as whole
    from public.so_line p where p.so_id = p_so_id and exists (select 1 from public.so_line k where k.combo_line_id = p.id) order by p.line_no
  loop
    select string_agg(format('%s picked %s, whole combos need %s', k.sku, trim_scale(coalesce(s.qty, 0)), trim_scale(c.whole * k.combo_qty)), '; ' order by k.line_no) into v_bad   -- trim_scale: 「2.000000」 이 아니라 「2」
      from public.so_line k left join (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s on s.line_id = k.id
     where k.combo_line_id = c.id and coalesce(s.qty, 0) > c.whole * k.combo_qty;
    if v_bad is not null then
      raise exception 'Combo % (line %) of %: components picked beyond whole combos (%) — a combo ships whole or not at all; put the extra back — nothing was saved', c.sku, c.line_no, v_so.so_number, v_bad;
    end if;
    if c.whole < c.target then
      b_moves := b_moves || jsonb_build_object('line_id', c.id, 'qty', c.target - c.whole);  b_n := b_n + 1;
    end if;
    v_lines := v_lines || jsonb_build_object('line_id', c.id, 'line_no', c.line_no, 'sku', c.sku, 'ordered', c.qty_ordered, 'removed', c.qty_removed, 'to_ship', c.target, 'shipped', c.whole, 'short', c.target - c.whole, 'combo', true);
  end loop;
  if v_shipped = 0 then
    raise exception 'Order % has no picked quantity at all — nothing ships (cancel or hold it with the order actions) — nothing was saved', v_so.so_number;
  end if;

  -- ① CAS 플립 — 첫 쓰기(문지기 packed→shipped) · 0행 = 그 사이 남이 바꿨다
  update public.so set status = 'shipped', shipped_at = now(), shipped_by = p_staff, updated_by = p_staff
  where id = p_so_id and status = v_from;                       -- ④a2: 문지기 짝 packed→shipped · confirmed→shipped(pos·counter)
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order % was not shipped — it may have been changed by someone else just now — nothing was saved', v_so.so_number;
  end if;

  -- ② 할당 닫기(5-f · ⬜4) — 나간 줄 shipped · 전량 못 나간 줄 released(실물이 없었다 · 형제에 backorder 가 선다)
  update public.so_reserve x set released_at = now(), released_by = p_staff, updated_by = p_staff,
         released_reason = case when coalesce(s.qty, 0) > 0 then 'shipped' else 'released' end
  from public.so_line l
  left join (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s on s.line_id = l.id
  where x.so_line_id = l.id and l.so_id = p_so_id and x.released_at is null and x.kind = 'allocated';

  -- ③ 줄 qty_shipped(판매 단위 · 나간 줄만 · 전량 못 나간 줄은 0 그대로 행째 형제로 간다)
  update public.so_line l set qty_shipped = s.qty, updated_by = p_staff
  from (select t.line_id, sum(t.qty) as qty from jsonb_to_recordset(v_norm) as t(line_id uuid, qty numeric) group by 1) s
  where s.line_id = l.id and l.so_id = p_so_id;
  update public.so_line p set qty_shipped = (select min(floor(k.qty_shipped / k.combo_qty)) from public.so_line k where k.combo_line_id = p.id), updated_by = p_staff   -- asm-2b1 ③′: 콤보 줄 「출고됨」 = 구성품이 다 나간 콤보 수(2b2 Finalize · 인보이스가 읽는다)
  where p.so_id = p_so_id and exists (select 1 from public.so_line k where k.combo_line_id = p.id);

  -- ④ 출하 차이 → 백오더 형제(2-f · 7-b · ⬜6 pick_short) — 할당 없이 · 물건이 들어와도 자동으로 잡지 않는다 · 재고 조정은 사람이(2-f)
  if b_n > 0 then
    v_sib := public.so_split(p_so_id, 'pick_short', b_moves, 'confirmed', p_staff);
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
    select x.id, x.qty_ordered, 'backorder', null from public.so_line x where x.so_id = v_sib.id and not exists (select 1 from public.so_line k where k.combo_line_id = x.id);   -- asm-2b1: 콤보 줄 제외
  end if;

  -- ⑤ 원장 — 창구 하나(원장 행 + FIFO + 부족분 · 한 트랜잭션 · 실패하면 출고도 실패)
  v_ledger := public.inv_post_sale(p_so_id, v_norm, v_on);

  return jsonb_build_object(
    'shipped', true, 'so_number', v_so.so_number, 'shipped_on', v_on, 'shipped_by', p_staff,
    'lines', v_lines,
    'backorder', case when b_n > 0 then jsonb_build_object('so_id', v_sib.id, 'so_number', v_sib.so_number, 'split_reason', 'pick_short', 'lines', b_n) else null end,
    'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 4) inv_post_sale 재발행 — 20260924141140_so_ship.sql 바이트 복사 · 콤보 줄 픽 거부(원장은 구성품만) ═══
create or replace function public.inv_post_sale(p_so_id uuid, p_picks jsonb, p_occurred_on date) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_post_sale@2026-09-24.1';
  v_so       public.so%rowtype;
  v_wh       text;
  v_existing int;
  v_baseline date;
  v_alloc    jsonb;
  v_bad      text;
  v_costs    jsonb := '{}'::jsonb;
  v_rows     int := 0;
  v_qty      numeric := 0;
  v_warn     text[] := '{}';
  k          record;
  b          record;
begin
  perform public.ims_require_write('sales', 'posted');        -- ⭐ 첫 줄 — 호출자(auth.uid())의 sales 쓰기

  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was posted to the ledger'; end if;
  if v_so.status <> 'shipped' or v_so.shipped_at is null then
    raise exception 'Order % is % — the ledger takes shipped orders only — nothing was posted to the ledger', v_so.so_number, v_so.status;
  end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_so.location_id;
  if v_wh is null then raise exception 'Order % has no warehouse — nothing was posted to the ledger', v_so.so_number; end if;

  -- 멱등 — 이미 기표된 출고는 다시 쓰지 않는다(말하는 0)
  select count(*) into v_existing from public.inv_ledger l
  where l.doc_type = 'sale' and l.doc_number = v_so.so_number and l.source = 'ims';
  if v_existing > 0 then
    return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'already_posted', true, 'existing_rows', v_existing,
                              'rows_posted', 0, 'qty_ea_posted', 0, 'keys', '{}'::jsonb, 'warnings', '["already_posted"]'::jsonb);
  end if;

  -- 날짜 경고 — 기초선보다 이르면 · 미래면(막지 않는다 · inv_post_receipt 와 같다)
  select (max(s.taken_at) at time zone 'America/Toronto')::date into v_baseline
  from public.inv_snapshot s where s.snapshot_key = (select c.value from public.inv_config c where c.key = 'baseline_snapshot_key');
  if v_baseline is not null and p_occurred_on < v_baseline then v_warn := array_append(v_warn, 'shipped_on_before_baseline'); end if;
  if p_occurred_on > public.ims_today() then v_warn := array_append(v_warn, 'shipped_on_in_future'); end if;

  -- 줄×칸 모으기 — 판매 단위 → EA(pack_factor) · 낱개 SKU(세트 줄은 parent) · 이 오더의 줄만
  select string_agg(distinct p.line_id::text, ', ') into v_bad
  from (select (e->>'line_id')::uuid as line_id from jsonb_array_elements(coalesce(p_picks, '[]'::jsonb)) e) p
  where not exists (select 1 from public.so_line l where l.id = p.line_id and l.so_id = p_so_id);
  if v_bad is not null then
    raise exception 'Pick line % is not on order % — nothing was posted to the ledger', v_bad, v_so.so_number;
  end if;
  select string_agg(distinct l.line_no::text, ', ') into v_bad                                                                          -- asm-2b1(판정 244): 콤보 줄은 원장에 닿지 않는다 — 구성품 줄만
  from jsonb_array_elements(coalesce(p_picks, '[]'::jsonb)) e join public.so_line l on l.id = (e->>'line_id')::uuid
  where exists (select 1 from public.so_line kk where kk.combo_line_id = l.id);                                                            -- 별칭 kk — 이 함수의 declare 에 k record 가 있다(「declare 변수 ≠ 조회 별칭」)
  if v_bad is not null then
    raise exception 'Pick line % of % is a combo line — components carry the stock — nothing was posted to the ledger', v_bad, v_so.so_number;
  end if;
  with p as (
    select (e->>'line_id')::uuid as line_id, coalesce(nullif(trim(e->>'bin'), ''), '') as bin, (e->>'qty')::numeric as qty
    from jsonb_array_elements(coalesce(p_picks, '[]'::jsonb)) e
  ),
  g as (select line_id, bin, sum(qty) as qty from p group by 1, 2),
  a as (
    select l.id as line_id, l.line_no, l.product_id, l.sku as sold_sku, l.pack_factor, l.unit_price,
           coalesce(pp.sku, pr.sku) as base_sku, g.bin, g.qty, g.qty * l.pack_factor as qty_ea
    from g
    join public.so_line l on l.id = g.line_id and l.so_id = p_so_id
    join public.product pr on pr.id = l.product_id
    left join public.product pp on pp.id = pr.parent_product_id
    where g.qty > 0
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no, a.bin), '[]'::jsonb) into v_alloc from a;
  if jsonb_array_length(v_alloc) = 0 then
    raise exception 'Order % has no picked quantity — nothing was posted to the ledger', v_so.so_number;
  end if;

  -- ⭐ 소진 먼저 — 낱개 SKU 키마다 한 번(창고 하나 · 줄 여럿은 접는다 · consume.line_ref = 첫 줄 · 재생성 키와 같다)
  for k in
    select t.base_sku, sum(t.qty_ea) as qty_ea, (array_agg(t.line_id::text order by t.line_no, t.bin))[1] as line_ref
    from jsonb_to_recordset(v_alloc) as t(base_sku text, qty_ea numeric, line_id uuid, line_no int, bin text)
    group by t.base_sku order by t.base_sku
  loop
    v_costs := v_costs || jsonb_build_object(k.base_sku,
                 public.inv_layer_post_sale(v_so.so_number, k.line_ref, k.base_sku, v_wh, k.qty_ea, p_occurred_on, null));
  end loop;

  -- 원장 행 — 줄×칸 · raw.cost 에 그 키의 소진·보충 결과(재생성이 raw.cost.shortfall 을 hint 로 읽는다 · 17-f (가))
  for b in
    select * from jsonb_to_recordset(v_alloc) as t(line_id uuid, line_no int, product_id uuid, sold_sku text, pack_factor numeric, unit_price numeric,
                                                   base_sku text, bin text, qty numeric, qty_ea numeric)
    order by line_no, bin
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (p_occurred_on, 2, b.base_sku, v_wh, b.bin, -b.qty_ea, 'sale_out', 'sale', v_so.so_number, v_so.id::text, b.line_id::text, null, 'ims',
      jsonb_build_object(
        'kind', 'sale_out', 'poster', c_version,
        'so_id', v_so.id, 'so_number', v_so.so_number, 'so_line_id', b.line_id, 'line_no', b.line_no,
        'product_id', b.product_id, 'sku', b.sold_sku, 'base_sku', b.base_sku, 'pack_factor', b.pack_factor,
        'qty', b.qty, 'qty_ea', b.qty_ea, 'unit_price', b.unit_price,
        'warehouse_id', v_so.location_id, 'warehouse', v_wh, 'bin', b.bin,
        'customer_id', v_so.customer_id, 'channel', v_so.channel, 'intake', v_so.intake,
        'shipped_on', p_occurred_on, 'shipped_at', v_so.shipped_at, 'shipped_by', v_so.shipped_by,
        'cost', v_costs->b.base_sku));
    v_rows := v_rows + 1;
    v_qty  := v_qty + b.qty_ea;
  end loop;

  return jsonb_build_object(
    'so_id', v_so.id, 'so_number', v_so.so_number, 'already_posted', false, 'existing_rows', 0,
    'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'keys', v_costs, 'poster', c_version, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Order % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_so.so_number, sqlerrm;
end;
$$;

-- ═══ 5) so_release_to_wms 재발행 — 20260926192314_wms_5_2a1_so_pairs_release_batch.sql 바이트 복사 · 할당 검사에서 콤보 줄 제외 ═══
create or replace function public.so_release_to_wms(p_so_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_id    uuid;
  v_so    public.so%rowtype;
  v_bad   text;
  v_out   jsonb := '[]'::jsonb;
begin
  perform public.ims_require_write('sales', 'saved');                 -- ⭐ 첫 줄 — Release 는 오더 담당(sales)
  v_staff := public.so_current_staff();
  if p_so_ids is null or cardinality(p_so_ids) = 0 then raise exception 'No orders given — nothing was saved'; end if;
  -- ① 검사 전부
  foreach v_id in array p_so_ids loop
    select * into v_so from public.so s where s.id = v_id;
    if not found then raise exception 'Order not found (%) — nothing was saved', v_id; end if;
    if v_so.channel <> 'warehouse' then
      raise exception 'Order % is a % order — only warehouse orders are released to the WMS — nothing was saved', v_so.so_number, v_so.channel;
    end if;
    if v_so.status <> 'confirmed' then
      raise exception 'Order % is % — only confirmed orders can be released — nothing was saved', v_so.so_number, v_so.status;
    end if;
    if v_so.location_id is null or not exists (select 1 from public.ref_warehouse w where w.id = v_so.location_id and w.is_active) then
      raise exception 'Order % has no active warehouse — nothing was saved', v_so.so_number;
    end if;
    select string_agg(distinct r.kind, ', ') into v_bad
    from public.so_reserve r join public.so_line l on l.id = r.so_line_id
    where l.so_id = v_id and r.released_at is null and r.kind <> 'allocated';
    if v_bad is not null then
      raise exception 'Order % has open % reservations — clear them first — nothing was saved', v_so.so_number, v_bad;
    end if;
    select string_agg(l.line_no::text, ', ' order by l.line_no) into v_bad
    from public.so_line l
    where l.so_id = v_id and (l.qty_ordered - l.qty_removed) > 0
      and not exists (select 1 from public.so_line k where k.combo_line_id = l.id)                                                   -- asm-2b1(판정 244): 콤보 줄은 예약이 없다 — 구성품 줄이 할당을 든다
      and coalesce((select sum(r.qty_allocated) from public.so_reserve r where r.so_line_id = l.id and r.kind = 'allocated' and r.released_at is null), 0) <> (l.qty_ordered - l.qty_removed);
    if v_bad is not null then
      raise exception 'Order % is not fully allocated (lines %) — allocate it first — nothing was saved', v_so.so_number, v_bad;
    end if;
    if not exists (select 1 from public.so_line l where l.so_id = v_id and (l.qty_ordered - l.qty_removed) > 0) then
      raise exception 'Order % has nothing left to ship — nothing was saved', v_so.so_number;
    end if;
  end loop;
  -- ② 전이 — 속 창구
  foreach v_id in array p_so_ids loop
    v_out := v_out || public.so_wms_status(v_id, 'at_wms', v_staff);
  end loop;
  return jsonb_build_object('released', v_out, 'count', jsonb_array_length(v_out));
end;
$$;

-- ═══ 6) so_divide 재발행 — 20260925142307_so_pos_a2_flow.sql 바이트 복사 · 콤보 줄 몫 × combo_qty 로 구성품 따라감 · 구성품 줄 거부 ═══
create or replace function public.so_divide(p_so_id uuid, p_moves jsonb, p_commit boolean default false) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_new public.so%rowtype;  m record;  l public.so_line%rowtype;  res public.so_reserve%rowtype;
  v_plan jsonb := '[]'::jsonb;  v_moves jsonb := '[]'::jsonb;  v_whole int := 0;  v_lines int;  v_nl public.so_line%rowtype;
  k public.so_line%rowtype;  v_kq numeric;                      -- asm-2b1(판정 244 · 묶음 4): 콤보 줄을 가르면 구성품 줄이 비례로 따라간다 · 구성품 줄은 따로 못 가른다
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.channel <> 'warehouse' then raise exception 'Order % is a % order — a pos/counter order is never split (6-f) — remove the line or make a second order — nothing was saved', v_so.so_number, v_so.channel; end if;   -- ④a2 훑기 ③(검증 6 실물: so_divide 가 pos 오더를 갈라 형제를 만들었다)
  if v_so.status not in ('draft', 'confirmed') then
    raise exception 'Order % is % — only a draft or confirmed order still in IMS can be divided — nothing was saved', v_so.so_number, v_so.status;
  end if;
  if p_moves is null or jsonb_typeof(p_moves) <> 'array' or jsonb_array_length(p_moves) = 0 then
    raise exception 'p_moves must be a non-empty array of {line_id, qty} — nothing was saved';
  end if;
  select count(*) into v_lines from public.so_line where so_id = p_so_id;

  for m in
    select (e->>'line_id')::uuid as line_id, nullif(e->>'qty', '')::numeric as qty from jsonb_array_elements(p_moves) e
  loop
    select * into l from public.so_line where id = m.line_id and so_id = p_so_id;
    if not found then raise exception 'Line % is not on order % — nothing was saved', m.line_id, v_so.so_number; end if;
    if m.qty is null or m.qty <= 0 then raise exception 'Quantity for line % must be positive — nothing was saved', l.line_no; end if;
    if m.qty > l.qty_ordered then raise exception 'Line % has only % — cannot split off % — nothing was saved', l.line_no, l.qty_ordered, m.qty; end if;
    if l.combo_line_id is not null then
      raise exception 'Line % is a component of combo % (line %) — divide the combo line instead — nothing was saved', l.line_no,
        (select c.sku from public.so_line c where c.id = l.combo_line_id), (select c.line_no from public.so_line c where c.id = l.combo_line_id);
    end if;
    if v_moves @> jsonb_build_array(jsonb_build_object('line_id', l.id)) then raise exception 'Line % is listed twice — nothing was saved', l.line_no; end if;
    select * into res from public.so_reserve where so_line_id = l.id and released_at is null;
    v_moves := v_moves || jsonb_build_object('line_id', l.id, 'qty', m.qty);
    if m.qty = l.qty_ordered then v_whole := v_whole + 1; end if;
    v_plan := v_plan || jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'qty_ordered', l.qty_ordered, 'qty_moved', m.qty, 'whole', m.qty = l.qty_ordered,
                                           'reserve_kind', res.kind, 'reserve_follows', case when res.id is null then 0 else m.qty end);
    for k in select * from public.so_line x where x.combo_line_id = l.id order by x.line_no loop                                        -- asm-2b1: 구성품 줄 = 콤보 몫 × combo_qty · 콤보 단위라 반쪽이 없다
      v_kq := m.qty * k.combo_qty;
      select * into res from public.so_reserve where so_line_id = k.id and released_at is null;
      v_moves := v_moves || jsonb_build_object('line_id', k.id, 'qty', v_kq);
      if v_kq = k.qty_ordered then v_whole := v_whole + 1; end if;
      v_plan := v_plan || jsonb_build_object('line_no', k.line_no, 'sku', k.sku, 'qty_ordered', k.qty_ordered, 'qty_moved', v_kq, 'whole', v_kq = k.qty_ordered,
                                             'reserve_kind', res.kind, 'reserve_follows', case when res.id is null then 0 else v_kq end, 'combo_sku', l.sku);
    end loop;
  end loop;
  if v_whole >= v_lines then
    raise exception 'Cannot split off every line of order % — leave at least one line (or one part of a line) — nothing was saved', v_so.so_number;
  end if;
  if not p_commit then
    return jsonb_build_object('so_number', v_so.so_number, 'committed', false, 'status', v_so.status, 'lines', v_plan);
  end if;

  perform pg_advisory_xact_lock(hashtext('so:' || regexp_replace(v_so.so_number, '[a-z]+$', '')));
  for m in select (e->>'line_id')::uuid as line_id from jsonb_array_elements(v_moves) e loop
    perform pg_advisory_xact_lock(hashtext('so_reserve:' || m.line_id::text));
  end loop;
  v_new := public.so_split(p_so_id, 'manual', v_moves, v_so.status, v_staff);

  -- 일부만 간 줄의 예약 — 풀고(이력) 원래 줄·형제 줄에 같은 kind 로(줄째 간 줄은 예약 행이 줄과 함께 갔다)
  if v_so.status = 'confirmed' then
    for v_nl in select * from public.so_line where so_id = v_new.id and split_from_line_id is not null loop
      select * into res from public.so_reserve where so_line_id = v_nl.split_from_line_id and released_at is null;
      if found then
        update public.so_reserve set released_at = now(), released_by = v_staff, updated_by = v_staff where id = res.id;                       -- 풀고 →
        insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
        select x.id, x.qty_ordered, res.kind, res.allocated_by from public.so_line x where x.id = v_nl.split_from_line_id;                        -- 원래 줄 · 남은 수량
        insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (v_nl.id, v_nl.qty_ordered, res.kind, res.allocated_by);   -- 형제 줄 · 옮긴 수량
      end if;
    end loop;
  end if;
  return jsonb_build_object('so_number', v_so.so_number, 'committed', true, 'status', v_so.status, 'lines', v_plan,
                            'sibling', jsonb_build_object('so_id', v_new.id, 'so_number', v_new.so_number, 'status', v_new.status, 'split_reason', 'manual'));
end;
$$;

-- ═══ 7) so_merge 재발행 — 20260925151823_so_merge_b.sql 바이트 복사 · 콤보 오더 합치기 거부(2b2) ═══
create or replace function public.so_merge(p_so_ids uuid[], p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_head_fields constant text[] := array['ship_to_company','ship_to_contact','ship_to_phone','ship_to_line1','ship_to_line2','ship_to_city','ship_to_state_province','ship_to_postal_code','ship_to_country',
                                         'bill_to_customer_id','bill_to_name','bill_to_line1','bill_to_line2','bill_to_city','bill_to_state_province','bill_to_postal_code','bill_to_country',
                                         'payment_term_id','payment_term_name','price_tier','price_tier_id','tax_rule','tax_rule_id','tax_rule_manual','discount_pct',
                                         'order_discount_pct','order_discount_source','order_discount_deal_id','required_by','ref','comments','intake',
                                         'carrier','tracking_number','shipping_notes','ar_account_code','sale_account_code'];
  v_staff   uuid;
  v_ids     uuid[];
  v_n       int;
  v_today   date := public.ims_today();
  v_old     public.so%rowtype;                       -- 가장 오래된 원본 = 머리(⬜2)
  v_head    public.so%rowtype;                       -- 미리 보기용 가상 머리(order_date = 오늘)
  v_new     public.so%rowtype;
  v_cust    public.customer%rowtype;
  v_numbers text;
  v_any_confirmed boolean;
  v_diffs   jsonb; v_plan jsonb; v_calc_in jsonb; v_hint jsonb; v_pay jsonb; v_sib jsonb; v_sup jsonb; v_charges jsonb;
  v_warn    text[] := '{}';
  v_note    text;
  v_id      uuid;
  v_line_id uuid;
  v_cnt     int;
  v_bo      int := 0; v_reopened int := 0; v_released int := 0; v_moved int := 0; v_lines_n int := 0;
  r record;
  e jsonb;
  od record;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — sales 묶음
  v_staff := public.so_current_staff();

  -- ── 대상 검사 ──
  select array_agg(distinct x) into v_ids from unnest(p_so_ids) x where x is not null;
  if coalesce(array_length(p_so_ids, 1), 0) <> coalesce(array_length(v_ids, 1), 0) then raise exception 'The same order is listed twice — nothing was saved'; end if;
  if coalesce(array_length(v_ids, 1), 0) < 2 then raise exception 'A merge needs at least two orders — nothing was saved'; end if;
  perform 1 from public.so s where s.id = any(v_ids) order by s.id for update;
  get diagnostics v_n = row_count;
  if v_n <> array_length(v_ids, 1) then raise exception 'Order not found — nothing was saved'; end if;
  for r in select s.* from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number loop
    if r.status not in ('draft', 'confirmed') then
      raise exception 'Order % is % — only draft or confirmed orders still in IMS can be merged — nothing was saved', r.so_number,
        r.status || case when r.status = 'cancelled' and r.closed_reason = 'merged' then ' (already merged into ' || coalesce((select m.so_number from public.so m where m.id = r.merged_into_id), '?') || ')'
                         when r.status in ('at_wms', 'picking', 'packed') then ' (it is with the warehouse — merge is only possible before release)'
                         else '' end;
    end if;
    if r.channel <> 'warehouse' then raise exception 'Order % is a % order — only warehouse orders can be merged — nothing was saved', r.so_number, r.channel; end if;
  end loop;
  if (select count(distinct s.customer_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders belong to different customers — nothing was saved'; end if;
  if exists (select 1 from public.so_line l where l.so_id = any(v_ids) and l.combo_line_id is not null) then                           -- asm-2b1(판정 244): 콤보 줄의 합치기(콤보 단위 · 구성품 다시 매달기)는 asm-2b2 — 그때까지 분명한 문장으로 막는다
    raise exception 'Order % has combo lines — merging orders with combos is not possible yet — nothing was saved',
      (select string_agg(distinct s.so_number, ', ') from public.so s join public.so_line l on l.so_id = s.id where s.id = any(v_ids) and l.combo_line_id is not null);
  end if;
  if (select count(distinct coalesce(s.location_id::text, '(none)')) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are for different warehouses — change the warehouse first — nothing was saved'; end if;
  if (select count(distinct s.currency_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are in different currencies — nothing was saved'; end if;
  select c.* into v_cust from public.customer c where c.id = (select s.customer_id from public.so s where s.id = v_ids[1]);
  if not v_cust.is_active then raise exception 'Customer % is inactive — nothing was saved', v_cust.name; end if;
  v_any_confirmed := exists (select 1 from public.so s where s.id = any(v_ids) and s.status = 'confirmed');
  if v_any_confirmed then perform public.so_require_role('manager', 'saved'); end if;   -- 판정 5 · R5: 확정 오더의 재고를 푸는 순간 선을 넘는다

  select s.* into v_old from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number limit 1;
  select string_agg(s.so_number, ', ' order by s.order_date, s.so_number) into v_numbers from public.so s where s.id = any(v_ids);

  -- ── 머리 차이(판정 2·7 · 막지 않는다) ──
  select coalesce(jsonb_agg(jsonb_build_object('field', d.f, 'values', d.vals) order by d.f), '[]'::jsonb) into v_diffs
  from (select f, jsonb_agg(jsonb_build_object('so_number', s.so_number, 'value', to_jsonb(s)->f) order by s.order_date, s.so_number) as vals
        from public.so s cross join unnest(c_head_fields) f
        where s.id = any(v_ids)
        group by f having count(distinct coalesce(to_jsonb(s)->f, 'null'::jsonb)) > 1) d;

  -- ── 줄 계획(판정 4 · 고침 ①: 열쇠 = 제품 · 단가 · 정가 · 할인 % · 무상 사유 · override · 부가 셋 — tax_rule 은 열쇠 밖 · 전부 합친 오더 규칙) ──
  with src as (
    select l.*, s.so_number, dense_rank() over (order by s.order_date, s.so_number) as ord,
           exists (select 1 from public.so_reserve rs where rs.so_line_id = l.id and rs.released_at is null and rs.kind = 'preorder')  as was_preorder,
           exists (select 1 from public.so_reserve rs where rs.so_line_id = l.id and rs.released_at is null and rs.kind = 'backorder') as was_backorder,
           (l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, v_today)) as deal_ended
    from public.so_line l join public.so s on s.id = l.so_id
    where s.id = any(v_ids)
  ), grp as (
    select product_id, unit_price, list_price, discount_pct, free_reason, price_override, surcharge_pct, surcharge_amount, surcharge_label,
           min(ord * 100000 + line_no) as first_pos, sum(qty_ordered) as qty, count(*) as n,
           (array_agg(sku order by ord, line_no))[1] as sku, (array_agg(product_name order by ord, line_no))[1] as product_name,
           (array_agg(unit order by ord, line_no))[1] as unit, (array_agg(pack_factor order by ord, line_no))[1] as pack_factor,
           (array_agg(comments order by ord, line_no) filter (where comments is not null))[1] as comments,
           bool_or(was_preorder) as was_preorder, bool_or(was_backorder) as was_backorder, bool_or(deal_ended) as deal_ended,
           jsonb_agg(jsonb_build_object('so_number', so_number, 'line_no', line_no, 'line_id', id, 'qty', qty_ordered, 'discount_source', discount_source, 'deal_line_id', deal_line_id,
                                        'was_preorder', was_preorder, 'was_backorder', was_backorder) order by ord, line_no) as sources
    from src
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9
  ), numbered as (
    select g.*, row_number() over (order by g.first_pos) as line_no,
           count(*) over (partition by g.product_id) as n_same_product,
           first_value(g.unit_price)     over (partition by g.product_id order by g.first_pos) as p_unit_price,
           first_value(g.list_price)     over (partition by g.product_id order by g.first_pos) as p_list_price,
           first_value(g.discount_pct)   over (partition by g.product_id order by g.first_pos) as p_discount_pct,
           first_value(g.free_reason)    over (partition by g.product_id order by g.first_pos) as p_free_reason,
           first_value(g.price_override) over (partition by g.product_id order by g.first_pos) as p_override,
           first_value(g.surcharge_label) over (partition by g.product_id order by g.first_pos) as p_surcharge_label
    from grp g
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'line_no', x.line_no, 'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name, 'unit', x.unit, 'pack_factor', x.pack_factor,
           'qty', x.qty, 'list_price', x.list_price, 'discount_pct', x.discount_pct, 'unit_price', x.unit_price, 'price_override', x.price_override, 'free_reason', x.free_reason,
           'discount_source', case when x.price_override then null when x.discount_pct is not null then 'manual' else null end,
           'surcharge_pct', x.surcharge_pct, 'surcharge_amount', x.surcharge_amount, 'surcharge_label', x.surcharge_label, 'comments', x.comments,
           'source_lines', x.n, 'sources', x.sources, 'was_preorder', x.was_preorder, 'was_backorder', x.was_backorder, 'deal_ended', x.deal_ended,
           'kept_apart', (x.n_same_product > 1),
           'differs_in', case when x.n_same_product > 1 then
              (select coalesce(jsonb_agg(k), '[]'::jsonb) from unnest(array[
                 case when x.unit_price is distinct from x.p_unit_price then 'unit_price' end,
                 case when x.list_price is distinct from x.p_list_price then 'list_price' end,
                 case when x.discount_pct is distinct from x.p_discount_pct then 'discount_pct' end,
                 case when x.free_reason is distinct from x.p_free_reason then 'free_reason' end,
                 case when x.price_override is distinct from x.p_override then 'price_override' end,
                 case when x.surcharge_label is distinct from x.p_surcharge_label then 'surcharge' end]) k where k is not null)
              else '[]'::jsonb end) order by x.line_no), '[]'::jsonb)
    into v_plan
  from numbered x;
  v_lines_n := coalesce(jsonb_array_length(v_plan), 0);

  -- ── 판정 4 보완 ①: 가상 머리(가장 오래된 원본 + 오늘) 로 다시 견적 ──
  v_head := v_old;
  v_head.order_date := v_today;
  select coalesce(jsonb_agg(jsonb_build_object('line_no', p->'line_no', 'product_id', p->'product_id', 'sku', p->'sku', 'qty', p->'qty', 'unit_price', p->'unit_price', 'discount_pct', p->'discount_pct',
                                               'discount_source', p->'discount_source', 'free_reason', p->'free_reason', 'price_override', p->'price_override')), '[]'::jsonb)
    into v_calc_in from jsonb_array_elements(v_plan) p;
  v_hint := public.so_merge_requote_calc(v_head, v_calc_in);

  -- ── 선결제 대상(옮긴다 · 조사 ③ unique (payment_id, so_id)) ──
  select coalesce(jsonb_agg(jsonb_build_object('payment_id', x.id, 'amount', x.amount, 'method', x.method, 'paid_on', x.paid_on, 'targets', x.targets) order by x.paid_on, x.id), '[]'::jsonb) into v_pay
  from (select p.id, p.amount, p.method, p.paid_on, jsonb_agg(s.so_number order by s.so_number) as targets
        from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active' join public.so s on s.id = o.so_id
        where o.so_id = any(v_ids) group by p.id, p.amount, p.method, p.paid_on) x;

  -- ── 판정 1 로 이어받기에서 빠질 형제(원본의 split 자손 중 열린 백오더가 있는 confirmed 오더) ──
  with recursive d as (
    select s.id, 0 as depth, array[s.id] as path from public.so s where s.id = any(v_ids)
    union all
    select c.id, d.depth + 1, d.path || c.id from d join public.so c on c.split_from_id = d.id where d.depth < 50 and not (c.id = any(d.path))
  )
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'status', s.status, 'split_reason', s.split_reason,
           'open_backorder_lines', (select count(*) from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null)) order by s.so_number), '[]'::jsonb)
    into v_sib
  from d join public.so s on s.id = d.id
  where d.depth > 0 and not (s.id = any(v_ids)) and s.status = 'confirmed'
    and exists (select 1 from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null);

  -- ── 원본이 확정 때 이어받은 남의 백오더 줄(⬜4 · 0-7: confirmed 이고 열린 예약이 없는 줄만 다시 연다 · 나머지는 닫힌 채 + 경고) ──
  select coalesce(jsonb_agg(jsonb_build_object('close_id', c.id, 'so_number', s.so_number, 'line_no', l.line_no, 'sku', l.sku, 'qty_open', c.qty_open, 'qty_taken', c.qty_taken, 'qty_unwanted', c.qty_unwanted,
           'taken_by', t.so_number, 'target_status', s.status,
           'reopenable', (s.status = 'confirmed' and not exists (select 1 from public.so_reserve rs where rs.so_line_id = l.id and rs.released_at is null))) order by s.so_number, l.line_no), '[]'::jsonb)
    into v_sup
  from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id join public.so s on s.id = l.so_id join public.so t on t.id = c.taken_by_so_id
  where c.taken_by_so_id = any(v_ids) and c.reopened_at is null and c.end_kind = 'superseded';

  -- ── 운임(판정 8: 옮기지 않는다 · 다시 계산한다) ──
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'line_no', c.line_no, 'name', c.name, 'amount', c.amount) order by s.so_number, c.line_no), '[]'::jsonb) into v_charges
  from public.so_charge c join public.so s on s.id = c.so_id where c.so_id = any(v_ids);

  -- ── 경고(막지 않는다) ──
  if jsonb_array_length(v_diffs) > 0 then v_warn := array_append(v_warn, 'head_differs'); end if;
  if jsonb_array_length(v_charges) > 0 then v_warn := array_append(v_warn, 'charges_not_merged'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'was_preorder')::boolean) then v_warn := array_append(v_warn, 'preorder_lines_need_reflag'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'deal_ended')::boolean) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if exists (select 1 from jsonb_array_elements(v_sup) x where not (x->>'reopenable')::boolean) then v_warn := array_append(v_warn, 'superseded_not_reopenable'); end if;
  if v_old.order_date <> v_today and v_lines_n > 0 then v_warn := array_append(v_warn, 'reprice_suggested'); end if;   -- §13 판정 3: 주문일이 바뀌면 줄은 그대로 + 표시 + 경고
  if jsonb_array_length(v_sib) > 0 then v_warn := array_append(v_warn, 'backorder_siblings_stay_open'); end if;      -- 판정 1 · 0-1 대가

  if not p_commit then
    return jsonb_build_object('committed', false, 'orders', to_jsonb(string_to_array(v_numbers, ', ')), 'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today,
                              'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'charges', v_charges,
                              'needs_manager', v_any_confirmed, 'warnings', to_jsonb(v_warn));
  end if;

  -- ── 실행 ① 새 오더(머리 통째 복사 · 위 주석의 칸 표) ──
  v_id := gen_random_uuid();
  v_note := 'Merged from ' || v_numbers;
  insert into public.so
  select * from jsonb_populate_record(null::public.so,
    to_jsonb(v_old) || jsonb_build_object(
      'id', v_id, 'so_number', public.so_next_number(), 'status', 'draft', 'order_date', v_today, 'ref', null,
      'comments', case when v_old.comments is null then v_note else v_old.comments || E'\n' || v_note end,
      'split_from_id', null, 'split_reason', null,
      'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
      'confirmed_at', null, 'confirmed_by', null, 'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null,
      'unconfirmed_at', null, 'unconfirmed_by', null, 'carrier', null, 'tracking_number', null, 'reprice_suggested_at', null,
      'created_at', now(), 'created_by', v_staff, 'updated_at', now(), 'updated_by', v_staff));
  select * into v_new from public.so where id = v_id;
  if v_old.order_discount_source = 'deal' then                                       -- 판정 7: source deal 이면 합친 날로 §13 자동 재계산 · manual 은 그대로
    select * into od from public.so_order_discount(v_id);
    update public.so set order_discount_pct = od.pct, order_discount_deal_id = od.deal_id, order_discount_source = case when od.pct is null then null else 'deal' end, updated_by = v_staff where id = v_id;
  end if;

  -- ── 실행 ② 줄(계획 그대로 · tax_rule = 합친 오더 규칙 · 짝 표) ──
  for e in select p from jsonb_array_elements(v_plan) p order by (p->>'line_no')::int loop
    insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                                list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, updated_by)
    values (v_id, (e->>'line_no')::int, (e->>'product_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
            (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, (e->>'unit_price')::numeric, (e->>'price_override')::boolean, e->>'discount_source', null, e->>'free_reason',
            (e->>'surcharge_pct')::numeric, (e->>'surcharge_amount')::numeric, e->>'surcharge_label', v_new.tax_rule, e->>'comments', v_staff)
    returning id into v_line_id;
    insert into public.so_line_merge_source (line_id, from_line_id, created_by)
    select v_line_id, (x->>'line_id')::uuid, v_staff from jsonb_array_elements(e->'sources') x;
  end loop;
  if v_old.order_date <> v_today and v_lines_n > 0 then
    update public.so set reprice_suggested_at = now(), updated_by = v_staff where id = v_id;
  end if;

  -- ── 실행 ③ 원본의 열린 백오더 줄 → 장부 merged + 예약 closed(0-4) ──
  for r in
    select res.id as reserve_id, res.so_line_id, res.qty_allocated
    from public.so_reserve res join public.so_line x on x.id = res.so_line_id
    where res.released_at is null and res.kind = 'backorder' and x.so_id = any(v_ids)
  loop
    perform public.so_backorder_record(r.so_line_id, 'merged', r.qty_allocated, 0, 0, null, null, v_staff, 'Merged into ' || v_new.so_number);
    update public.so_reserve set released_at = now(), released_by = v_staff, released_reason = 'closed', updated_by = v_staff where id = r.reserve_id;
    v_bo := v_bo + 1;
  end loop;

  -- ── 실행 ④ 원본이 이어받은 남의 줄 다시 열기(⬜4 · confirmed 이고 열린 예약 없는 줄만 · so_backorder_reopen 과 같은 모양) ──
  for r in select (x->>'close_id')::uuid as close_id, (x->>'reopenable')::boolean as ok from jsonb_array_elements(v_sup) x loop
    if r.ok then
      update public.so_backorder_close set reopened_at = now(), reopened_by = v_staff, updated_by = v_staff where id = r.close_id and reopened_at is null;
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
      select c.so_line_id, c.qty_open, 'backorder', null from public.so_backorder_close c where c.id = r.close_id;
      v_reopened := v_reopened + 1;
    end if;
  end loop;

  -- ── 실행 ⑤ 원본의 남은 열린 예약(allocated · preorder · hold) 풀기 → released(트리거가 reason 을 넣는다 · ⬜5) ──
  update public.so_reserve res set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x where x.id = res.so_line_id and res.released_at is null and x.so_id = any(v_ids);
  get diagnostics v_released = row_count;

  -- ── 실행 ⑥ 원본 닫기(한 문장 · so_merge_reason_ck 양방향 · so_closed_at_ck) ──
  update public.so set status = 'cancelled', closed_reason = 'merged', merged_into_id = v_id, closed_at = now(), closed_note = 'Merged into ' || v_new.so_number, cancelled_by = v_staff, updated_by = v_staff
  where id = any(v_ids) and status in ('draft', 'confirmed');
  get diagnostics v_cnt = row_count;
  if v_cnt <> array_length(v_ids, 1) then
    raise exception 'Not every order could be merged — one may have been changed by someone else just now — nothing was saved';
  end if;

  -- ── 실행 ⑦ 선결제 대상 옮기기(원본 행은 기록으로 · 합친 오더 행 하나) ──
  insert into public.so_payment_order (payment_id, so_id, created_by)
  select distinct o.payment_id, v_id, v_staff
  from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active'
  where o.so_id = any(v_ids)
  on conflict on constraint so_payment_order_uq do nothing;
  get diagnostics v_moved = row_count;

  return jsonb_build_object('committed', true, 'so_id', v_id, 'so_number', v_new.so_number, 'status', 'draft', 'orders', to_jsonb(string_to_array(v_numbers, ', ')),
                            'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today, 'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint,
                            'payments_moved', v_moved, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'superseded_reopened', v_reopened,
                            'backorder_lines_recorded', v_bo, 'reserves_released', v_released, 'charges', v_charges, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 8) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'wms_order_doc_line') <> 14
     or (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'wms_order_doc_line' and ordinal_position > 11) <> 'combo_line_id,combo_qty,combo_sku' then v_bad := v_bad || ' view-columns'; end if;
  if (select c.reloptions from pg_class c where c.oid = 'public.wms_order_doc_line'::regclass) is distinct from array['security_invoker=true'] then v_bad := v_bad || ' view-invoker'; end if;
  if not has_table_privilege('authenticated', 'public.wms_order_doc_line', 'select') then v_bad := v_bad || ' view-grant'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_pick_lines', 'so_ship', 'inv_post_sale', 'so_release_to_wms', 'so_divide', 'so_merge') and p.prosrc like '%asm-2b1%') <> 6 then v_bad := v_bad || ' reissues'; end if;
  if has_function_privilege('authenticated', 'public.so_ship(uuid, jsonb, uuid, date)', 'execute') or has_function_privilege('authenticated', 'public.inv_post_sale(uuid, jsonb, date)', 'execute') then v_bad := v_bad || ' inner-grants'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM244', message = format('STOP - asm-2b1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
