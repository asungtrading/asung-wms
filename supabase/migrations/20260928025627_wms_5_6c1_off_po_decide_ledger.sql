-- ⑤-6c1 (2026-09-27) — off-PO: 창고는 스캔하고 바로 놓는다 · 매니저(오피스 문)가 한 번에 받는다(무상 · 청구)/거절 · 원장 <diff_id>:offpo · 레이어 · 재생성 · Health
--   [테스트 · Asung-IMS] 전용 — 첫 문장은 supabase/ops/guard-test-only.sql 의 바이트 복사(앞에는 주석뿐). 판정 43 · 44 · 45 · 일곱 묶음(so-module 24-r 예정) · 설계 = ⑤-6c 설계 회신 D1 ~ D5′.
--   D1 po_receipt_diff 칸 여섯(off_po 만): bin_id · placed_by · placed_at(놓았다 · 판정 29) · unit_price(accepted_billed · PO 통화) · removed_by · removed_at(거절 뒤 선반에서 뺐다) + CHECK · 어휘 셋(accepted_free · accepted_billed · rejected) · inv_layer_source_ck 에 manual
--   D3 창고 창구 둘(definer · wms_receiving 문): wms_recv_off_po_putaway(diff · bin · done — wms_recv_gate · 결정 뒤 잠금) · wms_recv_off_po_removed(diff — rejected 뒤만 · 창고)
--   D2 결정 창구 하나(invoker · receiving 문 · 한 트랜잭션): po_receipt_diff_settle_off_po(diff · resolution · unit_price · note) → 받는다 = inv_post_receipt_off_po(원장 po_in · purchase · RCV · line_ref = diff_id::text||':offpo' · occurred_on = received_on · seq 1 · raw.kind po_off_po) → inv_layer_post_receipt_off_po(origin purchase · free → 0/free · billed → unit_price × factor/manual) · 거절 = 장부 없음 + remove_from_bin
--      ⚠️ 확정과 독립 — 두 창구는 입고의 확정을 요구하지 않는다(over 선례와 다른 점) · 확정(po_receipt_confirm_by · inv_post_receipt)은 po_line 기준이라 off_po 행을 읽지 않는다
--   재발행(마지막 정의 = DB prosrc md5 로 확인한 파일 · 바이트 그대로 + 바꾼 줄만): po_receipt_diff_settle_over · _resolve(거부 문장에 off_po 안내) · _reopen(accepted 거부 · rejected 허용) ·
--      inv_layer_apply(20260925012354 · IMS 가지 셋째 ims_offpo · raw.diff_id · 반환 offpo_* · ⭐ 같은 파일에 revoke — 판정 31) · po_receipt_detail(20260919175712 · diffs[] 에 칸 아홉 더함 · 기존 키 무변) ·
--      wms_health_check(20260928014844 · off_po_undecided 150 · off_po_rejected_on_shelf 160 · 15 → 17 행)
--   시험 적용 + 검증: ~/asung/prompts/wms-5-6c1-verify.sql (전부 rollback · 가짜 PO PO-79xxx · 가짜 입고 RCV-79xxx · 가짜 직원 · 실제 행 무접촉 · 번호 안 당김)

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

-- ═══ 1) po_receipt_diff — off-PO 의 자리(칸 여섯 · off_po 행에만) · 어휘 셋 · 레이어 cost_source manual ═══
alter table public.po_receipt_diff
  add column bin_id     uuid references public.ref_bin (id) on delete no action,          -- 놓은 칸(한 제품 한 칸 · 일곱 묶음 7)
  add column placed_by  uuid references public.ims_staff (id) on delete no action,        -- 놓았다를 누른 사람 · 그때(판정 29)
  add column placed_at  timestamptz,
  add column unit_price numeric,                                                          -- accepted_billed 의 입력 단가(PO 통화 · 일곱 묶음 2) · CAD = × po.exchange_rate
  add column removed_by uuid references public.ims_staff (id) on delete no action,        -- 거절 뒤 선반에서 뺐다(일곱 묶음 3 · Health 가 닫힌다)
  add column removed_at timestamptz;
alter table public.po_receipt_diff
  add constraint po_receipt_diff_off_po_cols_ck check (kind = 'off_po' or (bin_id is null and placed_by is null and placed_at is null and unit_price is null and removed_by is null and removed_at is null)),
  add constraint po_receipt_diff_placed_ck      check ((placed_at is null) = (placed_by is null) and (placed_at is null or bin_id is not null)),
  add constraint po_receipt_diff_removed_ck     check ((removed_at is null) = (removed_by is null) and (removed_at is null or (resolution = 'rejected' and bin_id is not null))),
  add constraint po_receipt_diff_unit_price_ck  check (unit_price is null or unit_price > 0),
  add constraint po_receipt_diff_billed_price_ck check (resolution is distinct from 'accepted_billed' or unit_price is not null);
alter table public.po_receipt_diff drop constraint if exists po_receipt_diff_resolution_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_resolution_ck
  check (resolution is null or resolution in ('split_shipment', 'out_of_stock', 'lost_damaged', 'miscount', 'other', 'free', 'billed', 'credited', 'accepted_free', 'accepted_billed', 'rejected'));
alter table public.po_receipt_diff drop constraint if exists po_receipt_diff_resolution_kind_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_resolution_kind_ck
  check (resolution is null
      or (kind = 'short'  and resolution in ('split_shipment', 'out_of_stock', 'lost_damaged', 'miscount', 'other'))
      or (kind = 'over'   and resolution in ('free', 'billed', 'credited'))
      or (kind = 'off_po' and resolution in ('accepted_free', 'accepted_billed', 'rejected')));
comment on column public.po_receipt_diff.bin_id     is '⑤-6c1 off_po 만 — 창고가 놓은 칸(wms_recv_off_po_putaway · 한 제품 한 칸) · 받는다 의 원장 bin';
comment on column public.po_receipt_diff.placed_by  is '⑤-6c1 off_po 만 — 놓았다를 누른 사람(판정 29 · placed_at 과 짝)';
comment on column public.po_receipt_diff.placed_at  is '⑤-6c1 off_po 만 — 놓은 때 · null = 아직 선반에 없다(accepted 거부)';
comment on column public.po_receipt_diff.unit_price is '⑤-6c1 off_po · accepted_billed 만 — 사람이 인보이스를 보고 PO 통화로 입력한 단가 · 레이어 unit_cost = × po.exchange_rate(기준통화면 ×1) · 재생성이 다시 읽는다';
comment on column public.po_receipt_diff.removed_by is '⑤-6c1 off_po · rejected 뒤 — 선반에서 뺐다를 누른 사람(wms_recv_off_po_removed)';
comment on column public.po_receipt_diff.removed_at is '⑤-6c1 off_po · rejected 뒤 — 뺀 때 · Health off_po_rejected_on_shelf 가 이것으로 닫힌다';
alter table public.inv_layer drop constraint if exists inv_layer_source_ck;
alter table public.inv_layer add constraint inv_layer_source_ck
  check (cost_source in ('inv_cost', 'snapshot_value', 'cin7_unitcost', 'layer_avg', 'assembly_sum', 'parent_layer', 'unknown', 'return_restore', 'po_line', 'free', 'layer_recent', 'layer_recent_other_wh', 'price_history', 'manual'));   -- ⑤-6c1 + manual(사람이 입력한 단가 · off-PO accepted_billed)

-- ═══ 2) 창고 창구 둘 — 놓기 · 뺐다 (definer · 첫 줄 wms_receiving 문) ═══
create function public.wms_recv_off_po_putaway(p_diff_id uuid, p_bin_id uuid, p_done boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_d public.po_receipt_diff%rowtype; v_r public.po_receipt%rowtype; v_b public.ref_bin%rowtype; v_sku text; v_now timestamptz := now();
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_d from public.po_receipt_diff d where d.id = p_diff_id for update;
  if not found then raise exception 'Off-PO item not found — nothing was saved'; end if;
  if v_d.kind <> 'off_po' then raise exception 'This difference is a "%" line, not an off-PO item — nothing was saved', v_d.kind; end if;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  if v_d.resolved_at is not null then
    raise exception 'Off-PO % was already decided as "%" by the office — its bin can no longer be changed here — nothing was saved', coalesce(v_sku, '?'), v_d.resolution;
  end if;
  v_r := public.wms_recv_gate(v_d.receipt_id);                 -- 창고 · 창고 Complete 잠금(작업 줄과 같은 규칙)
  v_b := public.po_receipt_bin_check(v_r.id, p_bin_id);        -- 그 입고의 창고 · 활성
  update public.po_receipt_diff
     set bin_id = p_bin_id,
         placed_by = case when coalesce(p_done, true) then v_staff else null end,
         placed_at = case when coalesce(p_done, true) then v_now else null end,
         updated_by = v_staff
   where id = p_diff_id;
  return jsonb_build_object('diff_id', p_diff_id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'qty', v_d.received_qty,
                            'bin_id', v_b.id, 'bin', v_b.name, 'zone', v_b.zone, 'placed', coalesce(p_done, true),
                            'placed_by', case when coalesce(p_done, true) then v_staff end, 'placed_at', case when coalesce(p_done, true) then v_now end);
end;
$$;
comment on function public.wms_recv_off_po_putaway(uuid, uuid, boolean) is '⑤-6c1 WMS off-PO 놓기(판정 43 — 승인 전 차단 없음 · 창고는 스캔하고 바로 놓는다) — 첫 줄 ims_require_write(wms_receiving) · wms_recv_gate(창고 · Complete 잠금) · po_receipt_bin_check(그 창고 · 활성) · 한 제품 한 칸(bin_id 덮어쓰기 · 나눠 놓기 없음) · done 이면 placed_by/at = 누른 사람 · 그때(판정 29) · false 면 placed 비움(칸은 남긴다) · 결정(resolved_at)된 뒤에는 거부 — 오피스가 정한 물건은 창고가 못 옮긴다';
revoke all on function public.wms_recv_off_po_putaway(uuid, uuid, boolean) from public, anon;
grant execute on function public.wms_recv_off_po_putaway(uuid, uuid, boolean) to authenticated;

create function public.wms_recv_off_po_removed(p_diff_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_d public.po_receipt_diff%rowtype; v_r public.po_receipt%rowtype; v_sku text; v_bin text; v_now timestamptz := now();
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_d from public.po_receipt_diff d where d.id = p_diff_id for update;
  if not found then raise exception 'Off-PO item not found — nothing was saved'; end if;
  if v_d.kind <> 'off_po' then raise exception 'This difference is a "%" line, not an off-PO item — nothing was saved', v_d.kind; end if;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  select * into v_r from public.po_receipt r where r.id = v_d.receipt_id;
  if not public.ims_can_warehouse(v_r.warehouse_id) then          -- Complete 잠금은 안 본다 — 거절된 물건은 입고가 닫힌 뒤에도 뺀다
    raise exception 'Receipt % is at another warehouse — you are not set up for it — nothing was saved', v_r.receipt_number;
  end if;
  if v_d.resolution is distinct from 'rejected' then
    raise exception 'Off-PO % is % — only a rejected item is taken off the shelf — nothing was saved', coalesce(v_sku, '?'), coalesce('decided as "' || v_d.resolution || '"', 'not decided yet');
  end if;
  if v_d.bin_id is null then raise exception 'Off-PO % was never put on a shelf — there is nothing to take off — nothing was saved', coalesce(v_sku, '?'); end if;
  if v_d.removed_at is not null then raise exception 'Off-PO % was already taken off the shelf on % — nothing was saved', coalesce(v_sku, '?'), to_char(v_d.removed_at at time zone 'America/Toronto', 'YYYY-MM-DD'); end if;
  select b.name into v_bin from public.ref_bin b where b.id = v_d.bin_id;
  update public.po_receipt_diff set removed_by = v_staff, removed_at = v_now, updated_by = v_staff where id = p_diff_id;
  return jsonb_build_object('diff_id', p_diff_id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'qty', v_d.received_qty, 'bin', v_bin, 'removed_by', v_staff, 'removed_at', v_now);
end;
$$;
comment on function public.wms_recv_off_po_removed(uuid) is '⑤-6c1 WMS 「선반에서 뺐다」(일곱 묶음 3) — 첫 줄 ims_require_write(wms_receiving) · 창고 · rejected 만 · 놓은 칸이 있어야 · 한 번만 · removed_by/at 을 남긴다(Health off_po_rejected_on_shelf 가 닫힌다) · Complete 잠금은 안 본다';
revoke all on function public.wms_recv_off_po_removed(uuid) from public, anon;
grant execute on function public.wms_recv_off_po_removed(uuid) to authenticated;

-- ═══ 3) 원장 · 레이어 창구(invoker · receiving 문 · 멱등 · 확정 요구 없음 — over 선례 inv_post_receipt_over · inv_layer_post_receipt_over 의 형제) ═══
create function public.inv_layer_post_receipt_off_po(p_diff_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_layer_post_receipt_off_po@2026-09-27.1';
  v_d        public.po_receipt_diff%rowtype;
  v_r        public.po_receipt%rowtype;
  v_po       public.po%rowtype;
  v_wh       text;
  v_sku      text;
  v_ref      text;
  v_qty      numeric;
  v_recv_on  date;
  v_rows     int;
  v_unit     numeric;
  v_src      text;
  v_cur      text;
  v_base     text;
  v_factor   numeric;
  v_layer_id bigint;
begin
  perform public.ims_require_write('receiving', 'posted');

  select * into v_d from public.po_receipt_diff where id = p_diff_id;
  if not found then raise exception 'Difference % not found — no cost layer was created', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  if not found then raise exception 'Receipt of difference % not found — no cost layer was created', p_diff_id; end if;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  if v_d.kind <> 'off_po' or v_d.resolved_at is null or v_d.resolution not in ('accepted_free', 'accepted_billed') then
    raise exception 'Off-PO % on % is not accepted (free or billed) — no cost layer was created', coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  v_ref := v_d.id::text || ':offpo';

  -- off-PO 원장 행을 접는다(한 차이 · 한 SKU · 한 창고 · 한 칸 ⇒ 레이어 하나)
  select sum(l.qty_delta), min(l.occurred_on), count(*)::int into v_qty, v_recv_on, v_rows
  from public.inv_ledger l
  where l.doc_type = 'purchase' and l.source = 'ims' and l.event_type = 'po_in'
    and l.doc_number = v_r.receipt_number and l.line_ref = v_ref and l.sku = v_sku and l.warehouse = v_wh and l.qty_delta > 0;
  if coalesce(v_rows, 0) = 0 then
    return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'resolution', v_d.resolution,
                              'ledger_rows', 0, 'layers_created', 0, 'layers_existing', 0, 'qty', 0, 'builder', c_version, 'warnings', '["no_ledger_rows_for_off_po"]'::jsonb);
  end if;

  -- 멱등 — 같은 4키(purchase · RCV · <diff>:offpo · sku · warehouse)의 레이어가 있으면 건너뛴다
  if exists (select 1 from public.inv_layer y
              where y.origin_type = 'purchase' and y.doc_number = v_r.receipt_number and y.line_ref = v_ref and y.sku = v_sku and y.warehouse = v_wh) then
    return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'resolution', v_d.resolution,
                              'ledger_rows', v_rows, 'layers_created', 0, 'layers_existing', 1, 'qty', v_qty, 'builder', c_version, 'warnings', '[]'::jsonb);
  end if;

  if v_d.resolution = 'accepted_free' then
    v_unit := 0; v_src := 'free';                                                                         -- ⭐ 낸 돈이 없다 — 진짜 0(unknown 아님 · over 선례)
  else
    -- ⭐ 사람이 입력한 단가(PO 통화) × 그 PO 의 환율(CAD per USD · 곱한다 · 기준통화면 ×1) — inv_layer_post_receipt 와 같은 식
    if v_d.unit_price is null or v_d.unit_price <= 0 then
      raise exception 'Off-PO % on % is billed but has no unit price — no cost layer was created', coalesce(v_sku, '?'), v_r.receipt_number;
    end if;
    select * into v_po from public.po where id = v_r.po_id;
    select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
    select k.value into v_base from public.inv_config k where k.key = 'base_currency';
    if v_base is null then raise exception 'inv_config.base_currency is not set — cannot tell which orders need an exchange rate — no cost layer was created'; end if;
    if v_cur is distinct from v_base then
      if v_po.exchange_rate is null or v_po.exchange_rate <= 0 then
        raise exception 'PO % is in % but has no % per % exchange rate — the off-PO cost cannot be worked out without it. Enter the rate in the order header and decide again — no cost layer was created',
          v_po.po_number, coalesce(v_cur, '?'), v_base, coalesce(v_cur, '?');
      end if;
      v_factor := v_po.exchange_rate;
    else
      v_factor := 1;
    end if;
    v_unit := v_d.unit_price * v_factor; v_src := 'manual';
  end if;

  insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
  values (v_sku, v_wh, 'purchase', v_r.receipt_number, v_ref, null, v_recv_on, true, v_qty, v_unit, v_src)
  returning id into v_layer_id;

  return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'warehouse', v_wh, 'resolution', v_d.resolution,
                            'ledger_rows', v_rows, 'layers_created', 1, 'layers_existing', 0, 'layer_id', v_layer_id,
                            'qty', v_qty, 'unit_price', v_d.unit_price, 'currency', v_cur, 'fx_rate', case when v_cur is distinct from v_base then v_factor end,
                            'unit_cost', v_unit, 'cost_source', v_src, 'cost_total_cad', v_qty * v_unit, 'received_on', v_recv_on,
                            'builder', c_version, 'warnings', '[]'::jsonb);
end;
$$;
comment on function public.inv_layer_post_receipt_off_po(uuid) is '⭐ 원가의 창구 · off-PO(⑤-6c1 · 2026-09-27) — 받아들인 off-PO 의 원장 행(RCV · line_ref <diff_id>:offpo · sku · warehouse)을 접어 inv_layer 한 행. accepted_free → unit_cost 0 · cost_source free. accepted_billed → po_receipt_diff.unit_price(PO 통화 · 사람 입력) × po.exchange_rate(CAD per USD · 곱한다 · 기준통화면 ×1) · cost_source manual. 멱등: 4키 레이어가 있으면 건너뛴다 · 원장 행이 없으면 경고만. inv_layer_apply() 재생성이 raw.diff_id 로 이 창구를 다시 부른다(ims_offpo). ⚠️ 입고의 확정을 요구하지 않는다(off-PO 결정은 확정과 독립 · 판정 43). ⚠️ inv_layer_post_charge 는 이 레이어(line_ref 접미어)에 landed 를 얹지 않는다. security invoker · append-only';
revoke all on function public.inv_layer_post_receipt_off_po(uuid) from public, anon;
grant execute on function public.inv_layer_post_receipt_off_po(uuid) to authenticated;

create function public.inv_post_receipt_off_po(p_diff_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_post_receipt_off_po@2026-09-27.1';
  v_d        public.po_receipt_diff%rowtype;
  v_r        public.po_receipt%rowtype;
  v_po       public.po%rowtype;
  v_wh       text;
  v_sku      text;
  v_bin      text;
  v_ref      text;
  v_existing int;
  v_layer    jsonb;
begin
  perform public.ims_require_write('receiving', 'posted');

  select * into v_d from public.po_receipt_diff where id = p_diff_id;
  if not found then raise exception 'Difference % not found — nothing was posted to the ledger', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  if not found then raise exception 'Receipt of difference % not found — nothing was posted to the ledger', p_diff_id; end if;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  if v_d.kind <> 'off_po' then
    raise exception 'Difference on % is a "%" line — only off-PO items are posted here (over → inv_post_receipt_over) — nothing was posted to the ledger', v_r.receipt_number, v_d.kind;
  end if;
  if v_d.resolved_at is null or v_d.resolution not in ('accepted_free', 'accepted_billed') then
    raise exception 'Off-PO % on % is not accepted (free or billed) — decide it first (po_receipt_diff_settle_off_po) — nothing was posted to the ledger', coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  if v_d.bin_id is null or v_d.placed_at is null then
    raise exception 'Off-PO % on % is not on a shelf yet — the warehouse puts it away first — nothing was posted to the ledger', coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  if v_d.received_qty <= 0 then raise exception 'Off-PO % on % has quantity % — nothing was posted to the ledger', coalesce(v_sku, '?'), v_r.receipt_number, v_d.received_qty; end if;
  select * into v_po from public.po where id = v_r.po_id;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  if v_wh is null then raise exception 'Warehouse of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;
  select b.name into v_bin from public.ref_bin b where b.id = v_d.bin_id;
  v_ref := v_d.id::text || ':offpo';                                                                  -- ⭐ 라인이 없다 — diff_id 가 열쇠 · 접미어로 유니크 7키 · 레이어 4키가 갈린다(:over 선례)

  -- 멱등 — 이미 행이 있으면 다시 쓰지 않는다 · 레이어만 다시(백필)
  select count(*) into v_existing from public.inv_ledger l
   where l.doc_type = 'purchase' and l.source = 'ims' and l.event_type = 'po_in' and l.doc_number = v_r.receipt_number and l.line_ref = v_ref;
  if v_existing > 0 then
    v_layer := public.inv_layer_post_receipt_off_po(p_diff_id);
    return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number, 'sku', v_sku,
                              'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0, 'qty_posted', 0, 'bin', v_bin, 'layer', v_layer, 'warnings', '["already_posted"]'::jsonb);
  end if;

  -- 한 행 — 한 제품 · 한 칸 · occurred_on = 문서의 received_on(같은 배로 왔다 · 결정한 날이 아니다 · 일곱 묶음 4) · seq 1(유입)
  insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
  values (
    v_r.received_on, 1, v_sku, v_wh, v_bin, v_d.received_qty, 'po_in', 'purchase', v_r.receipt_number, v_r.id::text, v_ref, null, 'ims',
    jsonb_build_object(
      'kind', 'po_off_po', 'poster', c_version,
      'diff_id', v_d.id, 'resolution', v_d.resolution, 'resolution_note', v_d.resolution_note, 'decided_by', v_d.resolved_by, 'decided_at', v_d.resolved_at,
      'unit_price', v_d.unit_price, 'currency_id', v_po.currency_id, 'exchange_rate', v_po.exchange_rate,
      'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'receipt_status', v_r.status, 'po_id', v_po.id, 'po_number', v_po.po_number,
      'product_id', v_d.product_id, 'sku', v_sku,
      'warehouse_id', v_r.warehouse_id, 'warehouse', v_wh, 'bin_id', v_d.bin_id, 'bin', v_bin, 'placed_by', v_d.placed_by, 'placed_at', v_d.placed_at,
      'received_on', v_r.received_on, 'qty', v_d.received_qty,
      'cost_rule', case v_d.resolution when 'accepted_free' then 'free — unit_cost 0 (nothing was paid)' else 'billed — unit_price typed from the invoice (PO currency) × po.exchange_rate' end));

  -- ⭐ 레이어 — 같은 트랜잭션(함께 서거나 함께 죽는다)
  v_layer := public.inv_layer_post_receipt_off_po(p_diff_id);

  return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number, 'sku', v_sku,
                            'already_posted', false, 'existing_rows', 0, 'rows_posted', 1, 'qty_posted', v_d.received_qty, 'bin', v_bin, 'occurred_on', v_r.received_on,
                            'layer', v_layer, 'warnings', '[]'::jsonb);
exception
  when unique_violation then
    raise exception 'Off-PO % on % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', p_diff_id, coalesce(v_r.receipt_number, '?'), sqlerrm;
end;
$$;
comment on function public.inv_post_receipt_off_po(uuid) is '⭐ 원장의 창구 · off-PO(⑤-6c1 · 2026-09-27 · 판정 43) — 받아들인 off-PO(accepted_free · accepted_billed · 놓은 칸 있음)를 inv_ledger 에 po_in 한 행으로 넣는다: doc_type purchase · doc_number RCV · doc_task_id receipt id · line_ref <diff_id>:offpo(라인이 없어 diff 가 열쇠) · bin = 놓은 칸 · qty = received_qty · occurred_on = po_receipt.received_on(같은 배 · 일곱 묶음 4) · seq_hint 1 · source ims · raw.kind po_off_po(raw.diff_id = 재생성 열쇠). 끝에 inv_layer_post_receipt_off_po 를 같은 트랜잭션으로. 멱등: 행이 있으면 already_posted · 레이어만 다시. ⚠️ 입고의 확정을 요구하지 않는다(확정과 독립 · 확정은 po_line 기준이라 이 행을 모른다). 거부(문장): 권한(receiving) · 없는 차이 · off_po 아님 · 안 받아들임 · 선반에 없음 · 수량 0. security invoker · append-only';
revoke all on function public.inv_post_receipt_off_po(uuid) from public, anon;
grant execute on function public.inv_post_receipt_off_po(uuid) to authenticated;

-- ═══ 4) 결정 창구 — po_receipt_diff_settle_off_po (판정 44 · Purchase Receipts 에서 · 오피스 문 receiving · 한 트랜잭션 · settle_over 의 형제) ═══
create function public.po_receipt_diff_settle_off_po(p_diff_id uuid, p_resolution text, p_unit_price numeric default null, p_note text default null) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_name    text;
  v_d       public.po_receipt_diff%rowtype;
  v_r       public.po_receipt%rowtype;
  v_po      public.po%rowtype;
  v_note    text;
  v_n       int;
  v_open    int;
  v_now     timestamptz := now();
  v_sku     text;
  v_bin     text;
  v_cur     text;
  v_base    text;
  v_post    jsonb;
begin
  perform public.ims_require_write('receiving', 'saved');
  select s.id, s.name into v_staff, v_name from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  -- 어휘 셋 — accepted_free(받는다 · 원가 0) · accepted_billed(받는다 · 인보이스 단가) · rejected(장부 없음 · 선반에서 뺀다)
  if p_resolution is null or p_resolution not in ('accepted_free', 'accepted_billed', 'rejected') then
    raise exception 'Decision "%" is not one of accepted_free, accepted_billed, rejected — nothing was saved', coalesce(p_resolution, '(empty)');
  end if;
  v_note := nullif(btrim(p_note), '');

  select * into v_d from public.po_receipt_diff where id = p_diff_id for update;                              -- 잠금 — 같은 물건을 두 사람이 동시에 정하지 않게(재고가 두 번 들어가면 안 된다)
  if not found then raise exception 'Difference % not found — nothing was saved', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  select b.name into v_bin from public.ref_bin b where b.id = v_d.bin_id;

  if v_d.kind <> 'off_po' then
    raise exception 'This difference on % is a "%" line — only off-PO items are decided here. A short difference is settled with po_receipt_diff_resolve, an over difference with po_receipt_diff_settle_over — nothing was saved',
      v_r.receipt_number, v_d.kind;
  end if;
  if v_d.resolved_at is not null then
    raise exception 'Off-PO % on % was already decided as "%" by % on %. % — nothing was saved',
      coalesce(v_sku, '?'), v_r.receipt_number, v_d.resolution,
      coalesce((select s.name from public.ims_staff s where s.id = v_d.resolved_by), '?'),
      to_char(v_d.resolved_at at time zone 'America/Toronto', 'YYYY-MM-DD'),
      case when v_d.resolution like 'accepted%' then 'The stock is already on the ledger so it cannot be decided twice' else 'Reopen it first if that was wrong' end;
  end if;
  if v_d.received_qty <= 0 then raise exception 'Off-PO % on % has quantity % — nothing was saved', coalesce(v_sku, '?'), v_r.receipt_number, v_d.received_qty; end if;
  if p_resolution like 'accepted%' and (v_d.bin_id is null or v_d.placed_at is null) then
    raise exception 'Off-PO % on % is not on a shelf yet — the warehouse puts it away first, then it can be accepted (the ledger needs the bin) — nothing was saved', coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  if p_resolution = 'accepted_billed' then
    if p_unit_price is null or p_unit_price <= 0 then
      raise exception 'Accepting off-PO % on % as billed needs the unit price from the invoice (in the order currency, more than 0) — nothing was saved', coalesce(v_sku, '?'), v_r.receipt_number;
    end if;
    select * into v_po from public.po where id = v_r.po_id;
    select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
    select k.value into v_base from public.inv_config k where k.key = 'base_currency';
    if v_cur is distinct from v_base and (v_po.exchange_rate is null or v_po.exchange_rate <= 0) then
      raise exception 'PO % is in % but has no % per % exchange rate — the off-PO cost cannot be worked out without it. Enter the rate in the order header and decide again — nothing was saved',
        v_po.po_number, coalesce(v_cur, '?'), coalesce(v_base, '?'), coalesce(v_cur, '?');
    end if;
  elsif p_unit_price is not null then
    raise exception 'A unit price goes only with accepted_billed — nothing was saved';
  end if;

  update public.po_receipt_diff
     set resolution = p_resolution, resolution_note = v_note, unit_price = case when p_resolution = 'accepted_billed' then p_unit_price end,
         resolved_by = v_staff, resolved_at = v_now, updated_by = v_staff
   where id = p_diff_id and resolved_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Off-PO % on % was not saved — it may have been decided by someone else just now — nothing was saved', coalesce(v_sku, '?'), v_r.receipt_number; end if;

  -- ⭐ 받는다 → 재고: 창구가 원장(한 행 · 놓은 칸)과 레이어(free 0 · billed 입력 단가 × 환율)를 넣는다 — 거부하면 결정도 함께 되돌아간다
  if p_resolution like 'accepted%' then
    v_post := public.inv_post_receipt_off_po(p_diff_id);
  end if;

  select count(*) into v_open from public.po_receipt_diff d where d.receipt_id = v_d.receipt_id and d.resolved_at is null;
  return jsonb_build_object(
    'diff_id', v_d.id, 'receipt_id', v_d.receipt_id, 'receipt_number', v_r.receipt_number, 'receipt_status', v_r.status,
    'kind', v_d.kind, 'sku', v_sku, 'product_id', v_d.product_id, 'qty', v_d.received_qty, 'bin_id', v_d.bin_id, 'bin', v_bin, 'placed_by', v_d.placed_by, 'placed_at', v_d.placed_at,
    'resolution', p_resolution, 'resolution_note', v_note, 'unit_price', case when p_resolution = 'accepted_billed' then p_unit_price end,
    'resolved_by', v_staff, 'resolved_by_name', v_name, 'resolved_at', v_now,
    'qty_added', coalesce(v_post->'qty_posted', '0'::jsonb), 'unit_cost', v_post->'layer'->'unit_cost', 'cost_source', v_post->'layer'->>'cost_source', 'layer_id', v_post->'layer'->'layer_id',
    'ledger', v_post,
    'remove_from_bin', case when p_resolution = 'rejected' and v_d.bin_id is not null then jsonb_build_object('bin', v_bin, 'qty', v_d.received_qty, 'placed_by', v_d.placed_by) end,
    'open_diffs_left', v_open);
end;
$$;
comment on function public.po_receipt_diff_settle_off_po(uuid, text, numeric, text) is '⑤-6c1 ⭐ off-PO 결정(판정 43 · 44 · Caleb 2026-09-27) — 오피스 Purchase Receipts 에서 한 번에: accepted_free(받는다 · 원가 0) · accepted_billed(받는다 · 인보이스 단가를 PO 통화로 입력 · CAD = × po.exchange_rate) · rejected(장부 없음 · 반환 remove_from_bin 으로 창고가 선반에서 뺀다). resolution · unit_price · resolved_by(서버 유도) · resolved_at 을 채운 뒤 accepted 면 같은 트랜잭션으로 inv_post_receipt_off_po(원장 한 행 · 놓은 칸) → inv_layer_post_receipt_off_po(레이어). 막는 것(문장): 권한(receiving) · 어휘 밖 · 없는 차이 · off_po 아님 · 이미 결정(accepted 는 두 번 못 정한다 · rejected 는 reopen 안내) · 수량 0 · accepted 인데 선반에 없음(placed_at) · billed 인데 단가 없음/≤0 · 기준통화 아닌 PO 에 환율 없음 · 단가를 accepted_billed 아닌 데 줌 · 남이 사이에 결정. ⚠️ 입고의 확정과 독립(순서 무관) · 받은 뒤 되돌리기 없음(일곱 묶음 6 · po_receipt_diff_reopen 이 거부). security invoker · 잠금 for update. 정본 so-module 24-r(예정)';
revoke all on function public.po_receipt_diff_settle_off_po(uuid, text, numeric, text) from public, anon;
grant execute on function public.po_receipt_diff_settle_off_po(uuid, text, numeric, text) to authenticated;

-- ═══ 5) 재발행 — 마지막 정의(DB prosrc md5 로 확인한 파일)에서 바이트 그대로 + 바꾼 줄만 ═══
-- 5a) po_receipt_diff_settle_over — 20260920171930:361 · 바뀐 것 2줄(주석 · 거부 문장에 off_po 안내)
create or replace function public.po_receipt_diff_settle_over(p_diff_id uuid, p_resolution text, p_note text default null) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_name    text;
  v_d       public.po_receipt_diff%rowtype;
  v_r       public.po_receipt%rowtype;
  v_note    text;
  v_n       int;
  v_open    int;
  v_now     timestamptz := now();
  v_sku     text;
  v_line_no int;
  v_fam     jsonb;
  v_post    jsonb;
begin
  perform public.ims_require_write('receiving', 'saved');
  select s.id, s.name into v_staff, v_name from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  -- 이유 셋 — free(공짜 · 원가 0) · billed(추가 청구 · 발주 단가) · credited(다음에 깎아 줌 · 발주 단가). returned 는 없다(거의 없다 · 생기면 그때).
  if p_resolution is null or p_resolution not in ('free', 'billed', 'credited') then
    raise exception 'Reason "%" is not one of free, billed, credited — nothing was saved', coalesce(p_resolution, '(empty)');
  end if;
  v_note := nullif(btrim(p_note), '');

  select * into v_d from public.po_receipt_diff where id = p_diff_id for update;                              -- 잠금 — 같은 차이를 두 사람이 동시에 닫지 않게(재고가 두 번 들어가면 안 된다)
  if not found then raise exception 'Difference % not found — nothing was saved', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  select pl.line_no into v_line_no from public.po_line pl where pl.id = v_d.po_line_id;

  -- ① over 만 — short 는 _resolve 가 닫는다 · off_po 는 형제 함수 po_receipt_diff_settle_off_po 가 정한다(⑤-6c1)
  if v_d.kind <> 'over' then
    raise exception 'Line % (%) on % is a "%" difference — only over differences are settled here. A short difference is settled with po_receipt_diff_resolve, an off-PO item with po_receipt_diff_settle_off_po — nothing was saved',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.kind;
  end if;
  -- ② 이미 닫힘 — 누가 무엇으로 언제 · ⚠️ over 는 reopen 이 없다(재고가 움직였다)
  if v_d.resolved_at is not null then
    raise exception 'Line % (%) on % was already settled as "%" by % on % and the extra is already in stock — it cannot be settled twice — nothing was saved',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.resolution,
      coalesce((select s.name from public.ims_staff s where s.id = v_d.resolved_by), '?'),
      to_char(v_d.resolved_at at time zone 'America/Toronto', 'YYYY-MM-DD');
  end if;
  if v_d.received_qty - v_d.expected_qty <= 0 then
    raise exception 'Line % (%) on % says over but received % is not above expected % — nothing was saved',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.received_qty, v_d.expected_qty;
  end if;

  update public.po_receipt_diff
     set resolution = p_resolution, resolution_note = v_note, resolved_by = v_staff, resolved_at = v_now
   where id = p_diff_id and resolved_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Line % on % was not saved — it may have been settled by someone else just now — nothing was saved', coalesce(v_line_no::text, '?'), v_r.receipt_number; end if;

  -- ⭐ 재고 — 창구가 원장(초과분만 · 빈 별)과 레이어(free 0 · 그 밖은 기준 레이어 값)를 넣는다. 원가 규칙은 창구 안에 산다 — 여기서는 부르기만.
  v_post := public.inv_post_receipt_over(p_diff_id);

  select count(*) into v_open from public.po_receipt_diff d where d.receipt_id = v_d.receipt_id and d.resolved_at is null;
  select jsonb_build_object('ordered_total', f.ordered_total, 'received_total', f.received_total, 'still_owed', f.still_owed, 'members', f.members)
    into v_fam
  from public.po_family_lines(v_d.po_id) f where f.product_id = v_d.product_id;

  return jsonb_build_object(
    'diff_id', v_d.id, 'receipt_id', v_d.receipt_id, 'receipt_number', v_r.receipt_number,
    'kind', v_d.kind, 'sku', v_sku, 'line_no', v_line_no, 'expected_qty', v_d.expected_qty, 'received_qty', v_d.received_qty,
    'resolution', p_resolution, 'resolution_note', v_note, 'resolved_by', v_staff, 'resolved_by_name', v_name, 'resolved_at', v_now,
    'qty_added', v_post->'qty_posted', 'unit_cost', v_post->'layer'->'unit_cost', 'cost_source', v_post->'layer'->>'cost_source', 'layer_id', v_post->'layer'->'layer_id',
    'ledger', v_post,
    'family', v_fam,
    'open_diffs_left', v_open);
end;
$$;

-- 5b) po_receipt_diff_resolve — 20260920171930:443 · 바뀐 것 1줄(거부 문장에 off_po 안내)
create or replace function public.po_receipt_diff_resolve(p_diff_id uuid, p_resolution text, p_note text default null) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_name    text;
  v_d       public.po_receipt_diff%rowtype;
  v_r       public.po_receipt%rowtype;
  v_note    text;
  v_n       int;
  v_open    int;
  v_now     timestamptz := now();
  v_sku     text;
  v_line_no int;
  v_fam     jsonb;
begin
  perform public.ims_require_write('receiving', 'saved');
  select s.id, s.name into v_staff, v_name from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  if p_resolution is null or p_resolution not in ('split_shipment', 'out_of_stock', 'lost_damaged', 'miscount', 'other') then
    raise exception 'Reason "%" is not one of split_shipment, out_of_stock, lost_damaged, miscount, other — nothing was saved', coalesce(p_resolution, '(empty)');
  end if;
  v_note := nullif(btrim(p_note), '');
  if p_resolution = 'other' and v_note is null then
    raise exception 'Reason "other" needs a note saying what actually happened — nothing was saved';
  end if;

  select * into v_d from public.po_receipt_diff where id = p_diff_id for update;                              -- 잠금 — 같은 차이를 두 사람이 동시에 닫지 않게
  if not found then raise exception 'Difference % not found — nothing was saved', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  select pl.line_no into v_line_no from public.po_line pl where pl.id = v_d.po_line_id;

  -- ① short 만 — over 는 재고를 움직이는 일이라 형제 함수 po_receipt_diff_settle_over 가 닫는다(2026-09-20 · 이유 free·billed·credited · 원장·레이어에 넣는다)
  if v_d.kind <> 'short' then
    raise exception 'Line % (%) on % is an "%" difference — only short differences are settled here. An over difference puts the extra into stock: settle it with po_receipt_diff_settle_over (reason free · billed · credited); an off-PO item is decided with po_receipt_diff_settle_off_po — nothing was saved',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.kind;
  end if;
  -- ② 이미 닫힘 — 누가 무엇으로 언제 · 빠져나갈 길(reopen)을 문장에
  if v_d.resolved_at is not null then
    raise exception 'Line % (%) on % was already settled as "%" by % on % — reopen it first if that was wrong — nothing was saved',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.resolution,
      coalesce((select s.name from public.ims_staff s where s.id = v_d.resolved_by), '?'),                    -- 별칭 s — ims_staff 자기 칸과 헷갈리지 않게
      to_char(v_d.resolved_at at time zone 'America/Toronto', 'YYYY-MM-DD');
  end if;

  update public.po_receipt_diff
     set resolution = p_resolution, resolution_note = v_note, resolved_by = v_staff, resolved_at = v_now
   where id = p_diff_id and resolved_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Line % on % was not saved — it may have been settled by someone else just now — nothing was saved', coalesce(v_line_no::text, '?'), v_r.receipt_number; end if;

  select count(*) into v_open from public.po_receipt_diff d where d.receipt_id = v_d.receipt_id and d.resolved_at is null;
  select jsonb_build_object('ordered_total', f.ordered_total, 'received_total', f.received_total, 'still_owed', f.still_owed, 'members', f.members)
    into v_fam
  from public.po_family_lines(v_d.po_id) f where f.product_id = v_d.product_id;

  return jsonb_build_object(
    'diff_id', v_d.id, 'receipt_id', v_d.receipt_id, 'receipt_number', v_r.receipt_number,
    'kind', v_d.kind, 'sku', v_sku, 'line_no', v_line_no, 'expected_qty', v_d.expected_qty, 'received_qty', v_d.received_qty,
    'resolution', p_resolution, 'resolution_note', v_note, 'resolved_by', v_staff, 'resolved_by_name', v_name, 'resolved_at', v_now,
    'family', v_fam,
    'open_diffs_left', v_open);
end;
$$;

-- 5c) po_receipt_diff_reopen — 20260920171930:518 · 더한 것 5줄(off_po accepted 거부 · rejected 는 그대로 허용)
create or replace function public.po_receipt_diff_reopen(p_diff_id uuid, p_note text default null) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_d     public.po_receipt_diff%rowtype;
  v_r     public.po_receipt%rowtype;
  v_n     int;
  v_open  int;
  v_note  text;
begin
  perform public.ims_require_write('receiving', 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_d from public.po_receipt_diff where id = p_diff_id for update;
  if not found then raise exception 'Difference % not found — nothing was saved', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  if v_d.resolved_at is null then
    raise exception 'This difference on % is not settled — there is nothing to reopen — nothing was saved', v_r.receipt_number;
  end if;
  -- ⭐ 2026-09-20 over 닫기 — over 는 닫히는 순간 초과분이 원장·레이어에 들어갔다(재고가 움직였다). 세 칸만 비우면 재고는 남고 기록만 사라진다.
  --   원장은 append-only 라 되돌리려면 반대 사건(상쇄)을 남기는 별도 길이 필요하다 — 아직 없다. 그래서 거부하고 무엇을 해야 하는지 말한다.
  if v_d.kind = 'over' then
    raise exception 'Line on % was settled as "%" and the extra % went into stock — it cannot be reopened, because the stock entry is already on the ledger (append-only). To undo it an offsetting stock entry is needed, which is not built yet — nothing was saved',
      v_r.receipt_number, v_d.resolution, v_d.received_qty - v_d.expected_qty;
  end if;
  -- ⑤-6c1 off-PO — accepted(free · billed)는 받는 순간 원장 · 레이어에 들어갔다(일곱 묶음 6 · 받은 뒤 되돌리기 없음) · rejected 는 장부에 아무것도 없어 되돌릴 수 있다
  if v_d.kind = 'off_po' and v_d.resolution like 'accepted%' then
    raise exception 'Off-PO item on % was accepted as "%" and % went into stock — it cannot be reopened, because the stock entry is already on the ledger (append-only). To undo it an offsetting stock entry is needed, which is not built yet — nothing was saved',
      v_r.receipt_number, v_d.resolution, v_d.received_qty;
  end if;

  v_note := nullif(btrim(p_note), '');
  update public.po_receipt_diff
     set resolution = null, resolved_by = null, resolved_at = null,
         resolution_note = case when v_note is null then resolution_note
                                else 'reopened: ' || v_note || coalesce(' | was: ' || resolution || coalesce(' — ' || resolution_note, ''), '') end
   where id = p_diff_id and resolved_at is not null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Difference on % was not saved — it may have been reopened by someone else just now — nothing was saved', v_r.receipt_number; end if;

  select count(*) into v_open from public.po_receipt_diff d where d.receipt_id = v_d.receipt_id and d.resolved_at is null;
  return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_d.receipt_id, 'receipt_number', v_r.receipt_number, 'kind', v_d.kind,
                            'was_resolution', v_d.resolution, 'was_resolved_by', v_d.resolved_by, 'was_resolved_at', v_d.resolved_at,
                            'reopened_by', v_staff, 'open_diffs_left', v_open);
end;
$$;

-- 5d) inv_layer_apply — 20260925012354:461 · 더한 것: 선언 3줄 · 루프 안 ims_offpo 가지 15줄 · 반환 3줄 · ⭐ revoke(판정 31)
create or replace function inv_layer_apply(p_until date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_t0          timestamptz := clock_timestamp();
  v_baseline    int;
  r             record;
  v_c int; v_u int; v_rows int; v_short int; v_proc int; v_rev int; v_layers int; v_orphan int; v_nz int; v_unk int; v_unkq numeric;
  v_partial int; v_traced int; v_avg int;
  v_po          int := 0;
  v_sale        int := 0;
  v_sale_keys   int := 0;
  v_sale_rev    int := 0;
  v_tr          int := 0;
  v_tr_layers   int := 0;
  v_tr_orphan   int := 0;
  v_tr_nz       int := 0;
  v_tr_unk      int := 0;
  v_tr_unkq     numeric := 0;
  v_tr_unpaired int := 0;
  v_adj         int := 0;
  v_adj_layers  int := 0;
  v_adj_rows    int := 0;
  v_adj_unk     int := 0;
  v_adj_new_nz  int := 0;
  v_asm         int := 0;
  v_asm_layers  int := 0;
  v_asm_rows    int := 0;
  v_asm_partial int := 0;
  v_asm_nz      int := 0;
  v_asm_unpaired int := 0;
  v_cr          int := 0;
  v_cr_layers   int := 0;
  v_cr_traced   int := 0;
  v_cr_avg      int := 0;
  v_cr_unk      int := 0;
  v_cr_nz       int := 0;
  v_layers_po   int := 0;
  v_consume     int := 0;
  v_unknown     int := 0;
  v_shorts      int := 0;
  v_skipped     jsonb;
  -- landed (2026-09-10)
  v_landed_rows int := 0;
  v_landed_amt  numeric := 0;
  v_landed_orph int := 0;
  v_neg         record;
  -- transfer_freight (2026-09-10)
  v_doc         record;
  v_grp         record;
  v_fr_n        int;
  v_fr_basis    numeric;
  v_fr_rows     int := 0;
  v_fr_amt      numeric := 0;
  v_fr_docs     int := 0;
  v_fr_nobasis  int := 0;
  v_fr_nobasis_amt numeric := 0;
  v_fr_orphan   int := 0;
  v_fr_multi    int := 0;
  -- IMS (2026-09-20) — 창구 둘(inv_layer_post_receipt · inv_layer_post_charge)의 반환을 합친다. ⚠️ 원문 변수와 겹치지 않는 v_ims_ 접두어
  v_ims_src     text;
  v_ims_task    text;
  v_ims_docno   text;
  v_ims_j       jsonb;
  v_ims_chg     record;
  v_ims_rcv         int := 0;   v_ims_rcv_layers int := 0;   v_ims_rcv_exist int := 0;   v_ims_rcv_cost numeric := 0;   v_ims_rcv_skipped int := 0;
  v_ims_chg_n       int := 0;   v_ims_chg_rows   int := 0;   v_ims_chg_amt   numeric := 0;
  v_ims_chg_nobasis_amt  numeric := 0;   v_ims_chg_nolayers_amt numeric := 0;   v_ims_chg_already int := 0;   v_ims_chg_skipped int := 0;
  v_ims_chg_unvisited int := 0;   v_ims_chg_unvisited_amt numeric := 0;
  v_ims_skip    jsonb := '[]'::jsonb;
  -- IMS 초과분 (2026-09-20 · over 닫기) — 형제 창구 inv_layer_post_receipt_over 의 반환을 합친다
  v_ims_over    text;
  v_ims_over_n  int := 0;   v_ims_over_layers int := 0;   v_ims_over_skipped int := 0;
  -- IMS off-PO (⑤-6c1 · 2026-09-27) — 형제 창구 inv_layer_post_receipt_off_po 의 반환을 합친다
  v_ims_offpo   text;
  v_ims_offpo_n int := 0;   v_ims_offpo_layers int := 0;   v_ims_offpo_skipped int := 0;
  v_ims_lref    text;                                                                     -- ⑤-6c1 — off-PO 행(<diff>:offpo)은 입고 단위 창구(ims_rcv)의 근거가 아니다(초안 입고에도 서는 행)
  -- IMS 문 · 보조 넷 (2026-09-20) — 창구가 아직 없는 IMS 사건을 사건 종류별로 센다(0 이 아니면 그 창구를 만들 때다). sale_out 은 없다(문 불필요).
  v_ims_gate    jsonb := '{"transfer_in": 0, "transfer_out": 0, "manual_reversal": 0, "adjust_existing": 0, "adjust_new": 0, "assemble_in": 0, "assemble_out": 0, "credit_in": 0}'::jsonb;
begin
  select count(*) into v_baseline from inv_layer where origin_type = 'baseline';
  if v_baseline = 0 then
    raise exception 'inv_layer has no baseline layers — run inv_layer_seed_baseline first';
  end if;

  -- ⭐ IMS 권한 문 (2026-09-20) — 창구 둘은 ims_require_write(receiving · purchasing) 로 auth.uid() 의 권한을 본다.
  --   권한이 없으면 창구가 전부 예외를 던지고 아래 IMS 블록이 그것을 「건너뛰었다」로 세어 버린다 — 재생성이 조용히 반쪽(IMS 만 빠진 레이어 표)이 된다.
  --   그래서 지우기 전에 먼저 막는다. psql 에서는 request.jwt.claims 에 admin 의 sub 를 심고 돌린다(20260918133858 검증 주석 선례).
  if not (ims_can_write('receiving') and ims_can_write('purchasing')) then
    raise exception 'inv_layer_apply: the IMS cost windows (inv_layer_post_receipt · inv_layer_post_charge) need write permission on receiving and purchasing for this login (auth.uid() = %) — from psql, set request.jwt.claims to an admin''s sub first — nothing was rebuilt',
      coalesce(auth.uid()::text, '(null)');
  end if;
  delete from inv_layer_consume;
  delete from inv_layer_cost_add;
  delete from inv_layer where origin_type <> 'baseline';
  perform inv_layer_apply_reset_done();

  -- 날짜순 루프 — ⭐ 사건 9종 전부 (order by occurred_on, seq_hint, po_in 먼저, id · source 필터 없음 · ⭐ 2026-09-21: 같은 날 유입끼리는 po_in 을 맨 앞에 — seq_hint 는 유입·유출만 가른다. 근거는 이 파일 머리 주석)
  for r in
    select id, event_type
      from inv_ledger
      where event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                           'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
        and (p_until is null or occurred_on <= p_until)
      order by occurred_on, seq_hint, case event_type when 'po_in' then 0 else 1 end, id
  loop
    -- ⭐⭐ IMS 문 · 보조 넷 (2026-09-20 · po_in 문의 형제 · Caleb 「문만 낸다 — 창구는 만들지 않는다」) — 창구가 아직 없는 IMS 사건은 보조 함수에 보내지 않고 사건 종류별로 센다.
    -- 왜 안 보내나: 보조 넷(transfer_in · adjust · assemble · credit)은 원가를 inv_cost / 레이어 평균에서 찾는다. IMS 사건은 거기 없어 unit_cost 0 · 'unknown' 레이어가 선다 — po_in 에서 실측된 사고(rcv_unknown 0→2)와 같다.
    -- 왜 창구를 지금 안 만드나: 트랜스퍼 모듈도 IMS 재고조정도 아직 없다 — 쓰지 않을 창구는 맞는지 검증할 표본이 없다. 그 사건을 내는 날 창구를 만들고 여기서 부른다(po_in 이 inv_layer_post_receipt 를 부르는 모양).
    -- 왜 세나: 조용히 지나가면 「IMS 트랜스퍼가 재고에 안 잡힌다」를 아무도 모른다. ims.skipped_by_event 가 0 이 아니면 창구를 만들 때가 됐다는 신호다.
    -- ⚠️ sale_out 은 세지도 막지도 않는다 — 소진은 출처를 안 보는 한 원장 FIFO 가 맞다(inv_layer_fifo_take). po_in 은 아래 분기가 창구로 처리한다.
    -- ⭐ 두 leg 다 막는다(⬜4) — transfer_out · manual_reversal · assemble_out 도 IMS 면 여기서 센다. out 은 대응 in 이 처리하므로 in 만 막아도 레이어는 안 서지만, 아래 *_unpaired 신호가 IMS 것으로 오염된다(그 집계에서도 ims 를 뺀다).
    -- 원문 루프 select(id, event_type)는 바꾸지 않는다 — po_in·sale_out 이 아닌 행만 PK 조회 한 번(po_in 은 아래 분기가 이미 조회한다).
    if r.event_type not in ('po_in', 'sale_out', 'credit_in') then   -- ⓒ1 2026-09-25: credit_in 은 아래 갈래가 source 로 가른다(IMS → 창구 inv_layer_apply_credit_ims · 문에서 세지 않는다 · skipped_by_event.credit_in 은 늘 0)
      select source into v_ims_src from inv_ledger where id = r.id;
      if v_ims_src = 'ims' then
        v_ims_gate := jsonb_set(v_ims_gate, array[r.event_type], to_jsonb(coalesce((v_ims_gate ->> r.event_type)::int, 0) + 1));
        continue;
      end if;
    end if;
    if r.event_type = 'po_in' then
      select * into v_c, v_u from inv_layer_apply_po_in(r.id, p_until);
      v_po := v_po + 1; v_layers_po := v_layers_po + v_c; v_unknown := v_unknown + v_u;
      -- ⭐⭐ IMS 입고 (2026-09-20) — 보조 inv_layer_apply_po_in 은 source='ims' 면 문에서 돌아섰다(0·0). 이 줄의 레이어는 창구 inv_layer_post_receipt 가 만든다.
      -- 왜 여기(루프 안 · 날짜순)이고 끝이 아닌가: 입고 레이어는 **수량** 레이어다 — 뒤에 오는 sale_out·transfer_out 이 FIFO 로 이것을 소진한다.
      --   끝에서 만들면 루프 안의 소진이 이 레이어를 못 보고 short 로 떨어지거나 다른 레이어를 먹어, 실시간 기표(확정 때 창구가 만든 상태)와 재생성 결과가 갈라진다.
      --   비용(cost_add)은 수량이 아니라 금액만 얹으므로 끝(landed·운송비와 같은 층)에 둔다 — 아래 「IMS 비용」 블록.
      -- 왜 창구에 넘기나: 원가 규칙(환율 곱하기 · 기준까지만 · bin 접기)이 창구 안에 있다. 여기 다시 적으면 같은 규칙이 두 곳에 살고 한쪽만 고치면 조용히 갈라진다.
      -- 왜 원장에서 훑나: 이 함수의 일은 「원장에서 레이어를 다시 만드는 것」이다 — 원장에 없으면 레이어도 없다. p_until 도 그대로 걸린다(as-of).
      -- 왜 입고 단위(doc_task_id = po_receipt.id)로 한 번인가: 입고 하나가 원장에 bin 별 여러 줄을 남긴다. 창구는 입고 단위로 일하고 4키 멱등이라 두 번 불러도 안전하지만,
      --   세는 값이 겹치지 않게 done 표(kind 'ims_rcv')로 한 번만 부른다. 같은 입고의 원장 줄은 occurred_on 이 같아(received_on) p_until 경계에 걸쳐 갈라지지 않는다.
      -- 왜 건너뛰고 세나(멈추지 않나 · Caleb 판정 2026-09-20): 이 함수는 검산 도구다. 입고 한 건의 빈칸(환율)으로 검산 자체가 안 되면 도구가 못 쓰게 된다.
      --   건너뛰어도 틀린 값이 들어가지 않는다 — 0 원가 레이어를 만드는 것과 전혀 다르다. 환율을 채우고 다시 돌리면 그 자리에 제대로 선다. 선례: freight_no_basis(기준 0 이면 버리고 금액을 센다).
      --   ⚠️ 몇 건을 왜 건너뛰었는지 반환(ims.receipts_skipped · ims.skip_reasons)에 반드시 남긴다 — 조용히 지나가면 같은 사고의 재판이다.
      select source, doc_task_id, doc_number, line_ref into v_ims_src, v_ims_task, v_ims_docno, v_ims_lref from inv_ledger where id = r.id;   -- 루프 select 는 바꾸지 않는다(원문 무변) — PK 조회 한 번 · ⑤-6c1 line_ref 도
      if v_ims_src = 'ims' and v_ims_task is not null and v_ims_lref not like '%:offpo'                                  -- ⑤-6c1 off-PO 행으로는 inv_layer_post_receipt 를 부르지 않는다(초안 입고라 거부돼 헛 skip 이 남는다)
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_rcv' and d.doc_number = v_ims_task and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_rcv', v_ims_task, '', '');   -- 입고 단위 키 — sku·warehouse 는 not null 이라 빈 문자열
        begin
          v_ims_j := inv_layer_post_receipt(v_ims_task::uuid);
          v_ims_rcv        := v_ims_rcv + 1;
          v_ims_rcv_layers := v_ims_rcv_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
          v_ims_rcv_exist  := v_ims_rcv_exist  + coalesce((v_ims_j->>'layers_existing')::int, 0);   -- 지운 뒤라 0 이어야 한다(생기면 신호 — 다른 축이 같은 4키를 먼저 만들었다)
          v_ims_rcv_cost   := v_ims_rcv_cost   + coalesce((v_ims_j->>'cost_total_cad')::numeric, 0);
        exception when others then
          -- ⚠️ 서브트랜잭션 — 창구가 던진 것(환율 없음 · 확정 아님 · po_line 없음 · base_currency 없음)만 여기로 온다. 그 호출이 넣은 레이어는 서브트랜잭션이 되돌린다 — 이 입고의 레이어는 하나도 서지 않는다.
          v_ims_rcv_skipped := v_ims_rcv_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'receipt', 'number', v_ims_docno, 'id', v_ims_task, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
      -- ⭐ IMS 초과분 (2026-09-20 · over 닫기) — line_ref 가 ':over' 인 po_in 행은 형제 창구 inv_layer_post_receipt_over(diff_id) 가 만든다(free → 0 · billed/credited → 기준 레이어의 unit_cost).
      --   왜 여기(루프 안): 수량 레이어라 뒤의 FIFO 소진이 봐야 한다(위 입고와 같은 이유). 기준 레이어가 먼저 서야 하는데, 초과분 행은 같은 날(received_on)·더 큰 id 라 (occurred_on, seq_hint, id) 순서에서 항상 뒤다.
      --   왜 diff 단위 한 번: 한 차이가 빈 별 여러 행을 남긴다 — done 표 kind 'ims_over'. 거부(기준 레이어 없음 등)는 건너뛰고 ims.over_skipped · skip_reasons 에 센다.
      select raw->>'diff_id' into v_ims_over from inv_ledger where id = r.id and source = 'ims' and line_ref like '%:over';
      if v_ims_over is not null
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_over' and d.doc_number = v_ims_over and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_over', v_ims_over, '', '');
        begin
          v_ims_j := inv_layer_post_receipt_over(v_ims_over::uuid);
          v_ims_over_n      := v_ims_over_n + 1;
          v_ims_over_layers := v_ims_over_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
        exception when others then
          v_ims_over_skipped := v_ims_over_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'over', 'number', v_ims_docno, 'id', v_ims_over, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
      -- ⭐ IMS off-PO (⑤-6c1 · 2026-09-27) — line_ref 가 ':offpo' 인 po_in 행은 형제 창구 inv_layer_post_receipt_off_po(diff_id) 가 만든다(accepted_free → 0 · accepted_billed → diff.unit_price × 환율 · manual).
      --   왜 diff 단위 한 번: 한 차이 = 한 행 · 한 칸이지만 over 와 같은 모양으로 done 표 kind 'ims_offpo' · 거부는 건너뛰고 ims.offpo_skipped · skip_reasons 에 센다.
      select raw->>'diff_id' into v_ims_offpo from inv_ledger where id = r.id and source = 'ims' and line_ref like '%:offpo';
      if v_ims_offpo is not null
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_offpo' and d.doc_number = v_ims_offpo and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_offpo', v_ims_offpo, '', '');
        begin
          v_ims_j := inv_layer_post_receipt_off_po(v_ims_offpo::uuid);
          v_ims_offpo_n      := v_ims_offpo_n + 1;
          v_ims_offpo_layers := v_ims_offpo_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
        exception when others then
          v_ims_offpo_skipped := v_ims_offpo_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'off_po', 'number', v_ims_docno, 'id', v_ims_offpo, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
    elsif r.event_type = 'sale_out' then
      select * into v_rows, v_short, v_proc, v_rev from inv_layer_apply_sale_out(r.id, p_until);
      v_sale := v_sale + 1; v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_sale_keys := v_sale_keys + v_proc; v_sale_rev := v_sale_rev + v_rev;
    elsif r.event_type = 'transfer_in' then
      select * into v_layers, v_rows, v_short, v_orphan, v_nz, v_unk, v_unkq, v_proc from inv_layer_apply_transfer_in(r.id, p_until);
      v_tr := v_tr + 1; v_tr_layers := v_tr_layers + v_layers; v_consume := v_consume + v_rows;
      v_shorts := v_shorts + v_short; v_tr_orphan := v_tr_orphan + v_orphan; v_tr_nz := v_tr_nz + v_nz;
      v_tr_unk := v_tr_unk + v_unk; v_tr_unkq := v_tr_unkq + v_unkq;
    elsif r.event_type in ('adjust_existing', 'adjust_new') then
      select * into v_layers, v_rows, v_short, v_unk, v_nz, v_proc from inv_layer_apply_adjust(r.id, p_until);
      v_adj := v_adj + 1; v_adj_layers := v_adj_layers + v_layers; v_adj_rows := v_adj_rows + v_rows;
      v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_adj_unk := v_adj_unk + v_unk; v_adj_new_nz := v_adj_new_nz + v_nz;
    elsif r.event_type = 'assemble_in' then
      select * into v_layers, v_rows, v_short, v_partial, v_nz, v_proc from inv_layer_apply_assemble(r.id, p_until);
      v_asm := v_asm + 1; v_asm_layers := v_asm_layers + v_layers; v_asm_rows := v_asm_rows + v_rows;
      v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_asm_partial := v_asm_partial + v_partial; v_asm_nz := v_asm_nz + v_nz;
    elsif r.event_type = 'assemble_out' then
      v_asm := v_asm + 1;   -- 부품 out 은 대응 in 이 처리한다(A-2 ④) — 여기서는 세기만
    elsif r.event_type = 'credit_in' then
      -- ⓒ1 2026-09-25: IMS 축(source ims)은 창구(inv_layer_post_credit)로 · Cin7 축은 종전 inv_layer_apply_credit — 두 축이 같은 반환 모양(17-f · 실시간과 재생성이 같은 함수)
      select source into v_ims_src from inv_ledger where id = r.id;
      if v_ims_src = 'ims' then
        select * into v_layers, v_traced, v_avg, v_unk, v_nz, v_proc from inv_layer_apply_credit_ims(r.id, p_until);
      else
        select * into v_layers, v_traced, v_avg, v_unk, v_nz, v_proc from inv_layer_apply_credit(r.id, p_until);
      end if;
      v_cr := v_cr + 1; v_cr_layers := v_cr_layers + v_layers; v_cr_traced := v_cr_traced + v_traced;
      v_cr_avg := v_cr_avg + v_avg; v_cr_unk := v_cr_unk + v_unk; v_cr_nz := v_cr_nz + v_nz;
    else
      v_tr := v_tr + 1;   -- transfer_out · manual_reversal: out leg 는 대응 in 이 처리한다
    end if;
  end loop;

  -- ⭐ 순액 > 0 인데 같은 날짜의 대응 in 이 처리하지 않은 out 키 — (doc, sku, wh, day) · 0 이어야 한다(생기면 신호)
  select count(*) into v_tr_unpaired
    from (select doc_number, sku, warehouse, occurred_on
            from inv_ledger
            where event_type in ('transfer_out', 'manual_reversal')
              and source <> 'ims'                                                       -- ⭐ 2026-09-20 IMS out leg 는 위 문이 세었다(ims.skipped_by_event) — 여기 섞이면 「생기면 신호」가 IMS 것으로 오염된다
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse, occurred_on
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'tr_out' and d.doc_number = o.doc_number and d.sku = o.sku
                          and d.warehouse = o.warehouse and d.day = o.occurred_on);

  -- 순액 > 0 인데 대응 in 이 처리하지 않은 부품 out 키 — 0 이어야 한다(생기면 신호). 순액 ≤ 0(상쇄 소멸) 키는 제외.
  select count(*) into v_asm_unpaired
    from (select doc_number, sku, warehouse
            from inv_ledger
            where event_type = 'assemble_out'
              and source <> 'ims'                                                       -- ⭐ 2026-09-20 같은 이유
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'asm_out' and d.doc_number = o.doc_number and d.sku = o.sku and d.warehouse = o.warehouse);

  -- ═══ PO landed → inv_layer_cost_add (2026-09-10 · 헤더) — 레이어가 전부 만들어진 뒤 집합 연산 한 번 ═══
  -- 가드: 키(4키 + occurred_on) 합이 음수면 예외 — inv_layer_cost_add 에는 amount CHECK 가 없어 이것이 유일한 방어다
  select c.doc_number, c.line_ref, c.sku, c.warehouse, c.occurred_on, sum(c.amount) as amt into v_neg
    from inv_cost c
    where c.cost_kind = 'landed' and (p_until is null or c.occurred_on <= p_until)
    group by c.doc_number, c.line_ref, c.sku, c.warehouse, c.occurred_on
    having sum(c.amount) < 0
    order by 1, 2, 5 limit 1;
  if found then
    raise exception 'inv_cost landed sum(amount) is negative for % / % / % / % @ %: % — refusing to add cost (revaluation offset? inspect inv_cost)',
      v_neg.doc_number, v_neg.line_ref, v_neg.sku, v_neg.warehouse, v_neg.occurred_on, v_neg.amt;
  end if;

  insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
  select x.id, 'landed',
         sum(c.amount),          -- ⭐ bin 이 여럿이면 합산 (실측 0건 · 방어)
         c.occurred_on,          -- ⚠️ 날짜별로 별개 행 (통관·freight·관세)
         c.doc_number, c.line_ref,
         null                    -- PO landed 는 인보이스 번호가 오지 않는다 (헤더)
    from inv_cost c
    join inv_layer x
      on  x.origin_type = 'purchase'
      and x.doc_number  = c.doc_number
      and x.line_ref    = c.line_ref
      and x.sku         = c.sku
      and x.warehouse   = c.warehouse
    where c.cost_kind = 'landed'
      and (p_until is null or c.occurred_on <= p_until)
    group by x.id, c.occurred_on, c.doc_number, c.line_ref;
  get diagnostics v_landed_rows = row_count;
  select coalesce(sum(amount), 0) into v_landed_amt from inv_layer_cost_add where kind = 'landed';

  -- orphan — 대응 purchase 레이어가 없는 landed 키 (조인에서 조용히 빠지므로 따로 센다)
  select count(*) into v_landed_orph
    from (select distinct c.doc_number, c.line_ref, c.sku, c.warehouse
            from inv_cost c
            where c.cost_kind = 'landed' and (p_until is null or c.occurred_on <= p_until)) k
    where not exists (select 1 from inv_layer x
                        where x.origin_type = 'purchase' and x.doc_number = k.doc_number and x.line_ref = k.line_ref
                          and x.sku = k.sku and x.warehouse = k.warehouse);

  -- ═══ 트랜스퍼 운송비 → inv_layer_cost_add (kind='transfer_freight' · 2026-09-10 · 헤더 B) — landed 와 같은 자리 ═══
  -- B-4 가드: 저널 행 금액이 음수면 예외 — inv_doc_cost 에도 inv_layer_cost_add 에도 amount CHECK 가 없어 이것이 유일한 방어다
  select d.doc_number, d.ref_number, d.occurred_on, d.amount into v_neg
    from inv_doc_cost d
    where d.doc_type = 'transfer' and d.kind = 'transfer_freight'
      and (p_until is null or d.occurred_on <= p_until)
      and d.amount < 0
    order by d.doc_number, d.occurred_on, d.ref_number limit 1;
  if found then
    raise exception 'inv_doc_cost transfer_freight amount is negative for % / invoice % @ %: % — refusing to distribute (correction? inspect inv_doc_cost)',
      v_neg.doc_number, coalesce(v_neg.ref_number, '(null)'), v_neg.occurred_on, v_neg.amount;
  end if;

  -- 문서 단위 루프 — 배분 기준(도착 레이어 원가 합)은 문서에 딸린 레이어로 정해지므로 문서마다 한 번 계산한다
  for v_doc in
    select doc_number, sum(amount) as amount     -- amount: no_basis 로 떨어질 때 합산할 문서 금액 (p_until 범위)
      from inv_doc_cost
      where doc_type = 'transfer' and kind = 'transfer_freight'
        and (p_until is null or occurred_on <= p_until)
      group by doc_number
      order by doc_number
  loop
    -- B-1 대상 = 도착 창고 레이어만 (IN_TRANSIT 제외) · B-2 기준 = unit_cost × qty (remaining 아님)
    select count(*), coalesce(sum(x.unit_cost * x.qty), 0) into v_fr_n, v_fr_basis
      from inv_layer x
      where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT';
    if v_fr_n = 0 then
      v_fr_orphan := v_fr_orphan + 1;          -- 대응 레이어 없음 (0 이 아니면 신호)
      continue;
    end if;
    if v_fr_basis <= 0 then
      v_fr_nobasis := v_fr_nobasis + 1;        -- 원가 미상(unknown · unit_cost 0) 레이어만 있는 문서 — 0 으로 나누지 않는다
      v_fr_nobasis_amt := v_fr_nobasis_amt + v_doc.amount;   -- ⚠️ 버린 운송비 금액 — Cin7 대조에서 설명된 차이의 크기 (헤더)
      continue;
    end if;

    -- 날짜별 한 묶음 — cost_add 유니크 키에 ref_number 가 없으므로 같은 날 인보이스가 둘이면 합산 1행 (헤더 B-3)
    for v_grp in
      select occurred_on, sum(amount) as amount, count(*) as n,
             string_agg(distinct ref_number, ',' order by ref_number) as ref_number
        from inv_doc_cost
        where doc_type = 'transfer' and kind = 'transfer_freight' and doc_number = v_doc.doc_number
          and (p_until is null or occurred_on <= p_until)
        group by occurred_on
        order by occurred_on
    loop
      if v_grp.n > 1 then v_fr_multi := v_fr_multi + 1; end if;
      -- B-2 배분: share = round(문서금액 × 레이어원가 / 합, 6) · 마지막 레이어(id 순) = 문서금액 − 앞선 share 합 (remainder on last)
      insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
      select t.id, 'transfer_freight',
             case when t.rn = t.cnt
                  then v_grp.amount - coalesce(sum(t.share) over (order by t.rn rows between unbounded preceding and 1 preceding), 0)
                  else t.share end,
             v_grp.occurred_on, v_doc.doc_number, t.line_ref, v_grp.ref_number
        from (select x.id, x.line_ref,
                     round(v_grp.amount * (x.unit_cost * x.qty) / v_fr_basis, 6) as share,
                     row_number() over (order by x.id) as rn,
                     count(*) over () as cnt
                from inv_layer x
                where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT') t;
      get diagnostics v_rows = row_count;
      v_fr_rows := v_fr_rows + v_rows;
    end loop;
    v_fr_docs := v_fr_docs + 1;
  end loop;
  select coalesce(sum(amount), 0) into v_fr_amt from inv_layer_cost_add where kind = 'transfer_freight';


  -- ═══ IMS 비용 → inv_layer_cost_add (kind='landed' · 2026-09-20) — landed·운송비와 같은 층 · 창구 inv_layer_post_charge 에 넘긴다 ═══
  -- 왜 여기(끝)인가: 비용은 수량이 아니라 금액만 얹는다 — FIFO 소진에 영향이 없어 Cin7 landed·운송비와 같은 자리다(입고 레이어는 루프 안 — 위).
  -- 왜 레이어에서 훑나(Caleb 판정 2026-09-20): 비용은 원장에 사건을 남기지 않아(금액만 얹는다) 원장으로 훑을 수 없다. 레이어가 없으면 얹을 곳도 없으니 부를 이유가 없다.
  --   길: inv_layer(cost_source='po_line').line_ref = po_line.id::text → po_line.po_id = po_charge_alloc.po_id → po_charge_alloc.po_charge_id = po_charge.id (confirmed).
  --   비용 문서 단위로 한 번(한 비용이 여러 발주에 배분된다 — exists 로 접는다) · 순서 고정.
  -- 왜 창구에 넘기나: 배분 규칙(환율 · unit_cost×qty 비례 · 6자리 · 끝수는 마지막 · 기준 0 버림 · 배분 줄 단위 멱등)이 창구 안에 있다 — 두 곳에 살게 하지 않는다.
  -- p_until: 창구는 occurred_on = po_charge.charge_date 로 얹는다 — 그래서 charge_date <= p_until 로 고른다(as-of 재생성).
  -- 방문하지 않은 확정 비용(배분된 발주 어디에도 IMS 레이어가 없는 것 — 예: 환율이 없어 입고를 건너뛴 발주)은 따로 센다(charges_unvisited · 금액 CAD)
  --   — 「버린 금액」의 그림이 빠지지 않게. Cin7 대조에서 이 금액만큼은 설명된 차이다(정본 D 의 freight_no_basis_amount 와 같은 구실).
  for v_ims_chg in
    select c.id, c.charge_number, c.charge_date
      from po_charge c
      where c.status = 'confirmed' and c.confirmed_at is not null
        and (p_until is null or c.charge_date <= p_until)
        and exists (select 1
                      from po_charge_alloc a
                      join po_line  pl on pl.po_id = a.po_id
                      join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'
                      where a.po_charge_id = c.id)
      order by c.charge_date, c.charge_number, c.id       -- ⚠️ 순서 고정 · charge_number 는 (supplier_id, charge_number) 유니크라 id 까지 건다
  loop
    begin
      v_ims_j := inv_layer_post_charge(v_ims_chg.id);
      v_ims_chg_n            := v_ims_chg_n + 1;
      v_ims_chg_rows         := v_ims_chg_rows         + coalesce((v_ims_j->>'layers_touched')::int, 0);
      v_ims_chg_amt          := v_ims_chg_amt          + coalesce((v_ims_j->>'amount_posted_cad')::numeric, 0);
      v_ims_chg_nobasis_amt  := v_ims_chg_nobasis_amt  + coalesce((v_ims_j->>'no_basis_amount_cad')::numeric, 0);    -- 기준 0 이라 버린 금액(정본 D)
      v_ims_chg_nolayers_amt := v_ims_chg_nolayers_amt + coalesce((v_ims_j->>'no_layers_amount_cad')::numeric, 0);   -- 배분 줄 중 레이어 없는 발주로 간 금액
      v_ims_chg_already      := v_ims_chg_already      + coalesce((v_ims_j->>'already_posted_allocs')::int, 0);      -- cost_add 를 지운 뒤라 0 이어야 한다(생기면 신호)
    exception when others then
      v_ims_chg_skipped := v_ims_chg_skipped + 1;
      v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'charge', 'number', v_ims_chg.charge_number, 'id', v_ims_chg.id, 'sqlstate', sqlstate, 'error', sqlerrm);
    end;
  end loop;
  -- 방문하지 않은 확정 비용 — 위 exists 가 거른 것. 금액은 창구와 같은 규칙으로 CAD(기준통화면 ×1 · 아니면 × exchange_rate). ⚠️ 환율 null 인 외화 비용은 합에서 빠진다(확정 게이트 ⑥ 뒤엔 없다 · 건수에는 든다).
  select count(*), coalesce(sum(c.total_amount * case when cu.code is not distinct from k.value then 1 else c.exchange_rate end), 0)
    into v_ims_chg_unvisited, v_ims_chg_unvisited_amt
    from po_charge c
    join ref_currency cu on cu.id = c.currency_id
    left join inv_config k on k.key = 'base_currency'
    where c.status = 'confirmed' and c.confirmed_at is not null
      and (p_until is null or c.charge_date <= p_until)
      and not exists (select 1
                        from po_charge_alloc a
                        join po_line  pl on pl.po_id = a.po_id
                        join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'
                        where a.po_charge_id = c.id);

  select coalesce(jsonb_object_agg(event_type, n), '{}'::jsonb) into v_skipped
    from (select event_type, count(*) as n
            from inv_ledger
            where event_type not in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                                     'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
              and (p_until is null or occurred_on <= p_until)
            group by event_type) s;

  return jsonb_build_object(
    'until',                     p_until,
    'processed_po_in',           v_po,
    'processed_sale_out',        v_sale,
    'sale_keys_processed',       v_sale_keys,
    'sale_keys_fully_reversed',  v_sale_rev,
    'processed_transfer',        v_tr,
    'transfer_layers_created',   v_tr_layers,
    'transfer_orphan_in',        v_tr_orphan,
    'transfer_keys_net_zero',    v_tr_nz,
    'transfer_unknown_layers',   v_tr_unk,
    'transfer_unknown_qty',      v_tr_unkq,
    'transfer_out_unpaired',     v_tr_unpaired,
    'processed_adjust',          v_adj,
    'adjust_layers_created',     v_adj_layers,
    'adjust_consume_rows',       v_adj_rows,
    'adjust_unknown_layers',     v_adj_unk,
    'adjust_new_net_zero',       v_adj_new_nz,
    'processed_assembly',        v_asm,
    'assembly_layers_created',   v_asm_layers,
    'assembly_consume_rows',     v_asm_rows,
    'assembly_partial_cost',     v_asm_partial,
    'assembly_net_zero',         v_asm_nz,
    'assembly_out_unpaired',     v_asm_unpaired,
    'processed_credit',          v_cr,
    'credit_layers_created',     v_cr_layers,
    'credit_traced',             v_cr_traced,
    'credit_avg',                v_cr_avg,
    'credit_unknown_layers',     v_cr_unk,
    'credit_net_zero',           v_cr_nz,
    'landed_rows',               v_landed_rows,
    'landed_amount',             v_landed_amt,
    'landed_orphan',             v_landed_orph,
    'freight_rows',              v_fr_rows,
    'freight_amount',            v_fr_amt,
    'freight_docs',              v_fr_docs,
    'freight_no_basis',          v_fr_nobasis,
    'freight_no_basis_amount',   v_fr_nobasis_amt,
    'freight_orphan',            v_fr_orphan,
    'freight_multi_ref',         v_fr_multi,
    -- ⭐ IMS (2026-09-20) — 한 칸에 중첩한다. ⚠️ jsonb_build_object 는 인자 100개 한도(키 50) — 기존 45키에 평면으로 더하면 넘는다. 기존 45칸은 이름·뜻 무변.
    'ims', jsonb_build_object(
      'receipts_posted',           v_ims_rcv,               -- 창구가 레이어를 만든 입고 수
      'layers_created',            v_ims_rcv_layers,        -- 그 레이어 행 수(라인 단위 · bin 접힘)
      'layers_existing',           v_ims_rcv_exist,         -- 0 이어야 한다
      'layers_cost_cad',           v_ims_rcv_cost,          -- Σ qty × unit_cost(CAD)
      'receipts_skipped',          v_ims_rcv_skipped,       -- ⚠️ 창구가 거부해 건너뛴 입고 수 — skip_reasons 에 문장
      'charges_posted',            v_ims_chg_n,
      'charge_rows',               v_ims_chg_rows,          -- cost_add 행 수
      'charge_amount_cad',         v_ims_chg_amt,
      'charge_no_basis_amount_cad',  v_ims_chg_nobasis_amt,   -- 버린 금액(정본 D)
      'charge_no_layers_amount_cad', v_ims_chg_nolayers_amt,  -- 버린 금액(레이어 없는 발주)
      'charge_already_posted',     v_ims_chg_already,       -- 0 이어야 한다
      'charges_skipped',           v_ims_chg_skipped,       -- ⚠️ 창구가 거부해 건너뛴 비용 수
      'charges_unvisited',         v_ims_chg_unvisited,     -- 배분된 발주 어디에도 IMS 레이어가 없어 부르지 않은 확정 비용 수
      'charges_unvisited_amount_cad', v_ims_chg_unvisited_amt,  -- 그 금액 — 설명된 차이
      'over_posted',               v_ims_over_n,            -- ⭐ 2026-09-20 초과분(over 닫기) — 창구가 레이어를 만든 차이 수
      'over_layers',               v_ims_over_layers,
      'over_skipped',              v_ims_over_skipped,      -- ⚠️ 창구가 거부해 건너뛴 차이 수 — skip_reasons kind 'over'
      'offpo_posted',              v_ims_offpo_n,           -- ⭐ ⑤-6c1 off-PO — 창구가 레이어를 만든 차이 수
      'offpo_layers',              v_ims_offpo_layers,
      'offpo_skipped',             v_ims_offpo_skipped,     -- ⚠️ 창구가 거부해 건너뛴 차이 수 — skip_reasons kind 'off_po'
      'skipped_by_event',          v_ims_gate,              -- ⭐ 2026-09-20 창구가 아직 없어 보조 함수에 보내지 않은 IMS 사건 수(종류별 · 여덟 키 항상) — 0 이 아니면 그 사건의 창구를 만들 때다
      'skip_reasons',              v_ims_skip),             -- [{kind receipt|charge · number · id · sqlstate · error}] — 이유 문장 그대로
    'skipped_by_type',           v_skipped,
    'layers_created',            v_layers_po,
    'consume_rows',              v_consume,
    'cost_unknown_layers',       v_unknown,
    'short_events',              v_shorts,
    'elapsed_ms',                round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$$;
revoke all on function public.inv_layer_apply(date) from public, anon, authenticated;   -- ⭐ 판정 31 — 재생성 계열은 사람이 psql(소유자)로만 · 재발행마다 같은 파일에 다시 적는다

-- 5e) po_receipt_detail — 20260919175712:271 · diffs[] 에 키 아홉(product_id · bin_id · bin · placed_by/_name/_at · unit_price · removed_by/_name/_at) · left join 셋 · 기존 키 무변
create or replace function public.po_receipt_detail(p_receipt_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with r as (
  select * from public.po_receipt where id = p_receipt_id
),
w as (
  select k.*, b.name as bin, b.zone,
         (select s.name from public.ims_staff s where s.id = k.counted_by) as counted_by_name,     -- ⚠️ 별칭 — ims_staff 자기 칸과 헷갈리지 않게
         (select s.name from public.ims_staff s where s.id = k.putaway_by) as putaway_by_name,
         (select s.name from public.ims_staff s where s.id = k.updated_by) as updated_by_name
  from public.po_receipt_work k
  left join public.ref_bin b on b.id = k.bin_id
  where k.receipt_id = p_receipt_id
),
rl as (
  select l.*, b.name as bin, b.zone, pl.line_no,
         (select s.name from public.ims_staff s where s.id = l.received_by) as received_by_name
  from public.po_receipt_line l
  join public.po_line pl on pl.id = l.po_line_id
  left join public.ref_bin b on b.id = l.bin_id
  where l.receipt_id = p_receipt_id
),
lines as (
  select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pr.name as product_name, pl.supplier_sku, pl.qty_ea as ordered,
         pl.entered_unit_product_id, pl.entered_qty, pl.entered_pack_factor,
         coalesce((select sum(il.qty_ea) from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                    where il.po_line_id = pl.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'), 0) as invoiced,
         coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as received_before,
         coalesce((select sum(y.qty_ea) from rl y where y.po_line_id = pl.id), 0) as received_here,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id), 0) as counted,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id and x.bin_id is not null), 0) as allocated,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id and x.putaway_done), 0) as placed
  from r
  join public.po_line pl on pl.po_id = r.po_id
  join public.product pr on pr.id = pl.product_id
),
fm as (                                                     -- 형제 문서 — 뿌리에서 내려온 전부 · 자기 자신 포함 · 분할이 없었으면 하나(차이 닫기 차수 2026-09-19)
  select * from public.po_family_members((select po_id from r))
),
fam as (                                                    -- 형제 합계 · 제품 단위 — ⭐ 계산은 DB 가 한다(화면이 형제를 찾아 더하지 않는다)
  select * from public.po_family_lines((select po_id from r))
)
select case when not exists (select 1 from r) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', r.id, 'receipt_number', r.receipt_number, 'status', r.status, 'received_on', r.received_on,
      'po_id', r.po_id, 'po_number', p.po_number, 'po_status', p.status, 'po_closed_at', p.closed_at,
      'po_split_from_number', sf.po_number,
      'po_split_to', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'po_number', c.po_number, 'status', c.status) order by c.po_number) from public.po c where c.split_from_id = p.id), '[]'::jsonb),
      'po_family', jsonb_build_object(                                                                      -- ⭐ 형제 문서 합계(문서 단위 · 2026-09-19) — 「12 중 12 · 다 받음」의 근거
        'root_number', (select m.po_number from fm m order by m.depth, m.po_number limit 1),
        'members', coalesce((select jsonb_agg(jsonb_build_object('id', m.po_id, 'po_number', m.po_number, 'status', m.status, 'closed_at', m.closed_at, 'is_this', m.is_self) order by m.po_number) from fm m), '[]'::jsonb),
        'ordered_total',  (select coalesce(sum(f.ordered_total), 0)  from fam f),
        'received_total', (select coalesce(sum(f.received_total), 0) from fam f),
        'still_owed',     (select coalesce(sum(f.still_owed), 0)     from fam f)),
      'supplier_id', p.supplier_id, 'supplier_name', s.name,
      'warehouse_id', r.warehouse_id, 'warehouse_name', wh.name,
      'created_by', r.created_by, 'created_by_name', cb.name,
      'confirmed_at', r.confirmed_at, 'confirmed_by_name', fb.name,
      'cancelled_at', r.cancelled_at, 'cancelled_by_name', xb.name,
      'note', r.note, 'created_at', r.created_at, 'updated_at', r.updated_at, 'updated_by_name', ub.name)
    from r
    join public.po p on p.id = r.po_id
    join public.supplier s on s.id = p.supplier_id
    join public.ref_warehouse wh on wh.id = r.warehouse_id
    left join public.po sf on sf.id = p.split_from_id
    left join public.ims_staff cb on cb.id = r.created_by
    left join public.ims_staff fb on fb.id = r.confirmed_by
    left join public.ims_staff xb on xb.id = r.cancelled_by
    left join public.ims_staff ub on ub.id = r.updated_by
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'po_line_id', l.po_line_id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', l.product_name, 'supplier_sku', l.supplier_sku,
      'entered_unit_product_id', l.entered_unit_product_id, 'entered_qty', l.entered_qty, 'entered_pack_factor', l.entered_pack_factor,
      'ordered', l.ordered, 'invoiced', l.invoiced, 'received_before', l.received_before, 'received_here', l.received_here,
      'remaining', l.ordered - l.received_before,
      'counted', l.counted, 'allocated', l.allocated, 'unallocated', l.counted - l.allocated, 'placed', l.placed,
      'over', (l.counted > l.ordered - l.received_before),
      'family', (select jsonb_build_object('ordered_total', f.ordered_total, 'received_total', f.received_total, 'still_owed', f.still_owed, 'members', f.members, 'fragments', f.fragments)
                 from fam f where f.product_id = l.product_id),                                              -- 형제 합계(제품 단위 · 2026-09-19) — 조각은 fragments[]
      'work', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', x.id, 'qty_ea', x.qty_ea, 'bin_id', x.bin_id, 'bin', x.bin, 'zone', x.zone, 'putaway_done', x.putaway_done,
          'count_method', x.count_method, 'counted_by', x.counted_by, 'counted_by_name', x.counted_by_name, 'counted_at', x.counted_at,
          'putaway_by', x.putaway_by, 'putaway_by_name', x.putaway_by_name, 'putaway_at', x.putaway_at,
          'note', x.note, 'updated_at', x.updated_at, 'updated_by_name', x.updated_by_name)
          order by x.bin_id nulls first, x.created_at)
        from w x where x.po_line_id = l.po_line_id), '[]'::jsonb))
      order by l.line_no)
    from lines l), '[]'::jsonb),
  'receipt_lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', y.id, 'po_line_id', y.po_line_id, 'line_no', y.line_no, 'qty_ea', y.qty_ea, 'bin_id', y.bin_id, 'bin', y.bin, 'zone', y.zone,
      'received_on', y.received_on, 'received_by', y.received_by, 'received_by_name', y.received_by_name, 'note', y.note, 'created_at', y.created_at)
      order by y.line_no, y.bin)
    from rl y), '[]'::jsonb),
  'diffs', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', d.id, 'kind', d.kind, 'po_line_id', d.po_line_id, 'line_no', pl.line_no, 'sku', pr.sku,
      'expected_qty', d.expected_qty, 'received_qty', d.received_qty, 'diff_qty', d.received_qty - d.expected_qty,
      'note', d.note, 'resolved_at', d.resolved_at, 'resolved_by', d.resolved_by, 'resolved_by_name', rb.name,      -- rb = 별칭 서브쿼리(ims_staff 자기 칸과 헷갈리지 않게)
      'resolution', d.resolution, 'resolution_note', d.resolution_note,                                              -- 닫은 이유(차이 닫기 차수 2026-09-19)
      'product_id', d.product_id, 'bin_id', d.bin_id, 'bin', db.name, 'placed_by', d.placed_by, 'placed_by_name', pb.name, 'placed_at', d.placed_at,   -- ⑤-6c1 off-PO 칸(off_po 아니면 null)
      'unit_price', d.unit_price, 'removed_by', d.removed_by, 'removed_by_name', rmb.name, 'removed_at', d.removed_at,
      'family', (select jsonb_build_object('ordered_total', f.ordered_total, 'received_total', f.received_total, 'still_owed', f.still_owed, 'members', f.members, 'fragments', f.fragments)
                 from fam f where f.product_id = d.product_id))                                              -- ⭐ 닫을 때 「결국 다 받았나」가 여기 있다
      order by pl.line_no)
    from public.po_receipt_diff d
    left join public.po_line pl on pl.id = d.po_line_id
    join public.product pr on pr.id = d.product_id
    left join public.ims_staff rb on rb.id = d.resolved_by
    left join public.ref_bin db on db.id = d.bin_id                                                          -- ⑤-6c1
    left join public.ims_staff pb on pb.id = d.placed_by
    left join public.ims_staff rmb on rmb.id = d.removed_by
    where d.receipt_id = p_receipt_id), '[]'::jsonb),
  'totals', (
    select jsonb_build_object(
      'lines', count(*), 'counted_lines', count(*) filter (where l.counted > 0),
      'ordered', coalesce(sum(l.ordered), 0), 'remaining', coalesce(sum(l.ordered - l.received_before), 0),
      'counted', coalesce(sum(l.counted), 0), 'allocated', coalesce(sum(l.allocated), 0), 'placed', coalesce(sum(l.placed), 0),
      'received_here', coalesce(sum(l.received_here), 0),
      'over_lines', count(*) filter (where l.counted > l.ordered - l.received_before),
      'short_lines', count(*) filter (where l.counted < l.ordered - l.received_before),
      'open_diffs', (select count(*) from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.resolved_at is null))
    from lines l
  ),
  'warnings', (
    select coalesce(jsonb_agg(v), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when (select p.status from r join public.po p on p.id = r.po_id) <> 'confirmed' and (select status from r) = 'draft' then 'po_not_confirmed' end,
        case when exists (select 1 from lines l where l.counted > l.ordered - l.received_before) then 'over_receipt' end,
        case when exists (select 1 from w x where x.bin_id is null) then 'unassigned_rows' end,
        case when not exists (select 1 from w) then 'nothing_counted' end,
        case when exists (select 1 from lines l where l.received_here <> l.counted) and (select status from r) = 'confirmed' then 'receipt_lines_differ_from_work' end,
        case when exists (select 1 from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.resolved_at is null) then 'open_diffs' end
      ], null)) as v) t
  )
) end;
$$;

-- 5f) wms_health_check — 20260928014844:88 · CTE 둘 · 행 둘(150 · 160) · 15 → 17 행
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
       and not exists (select 1 from public.wms_reports r                 -- ⑤-5c3: 「Not enough stock」 신고(판정 20 · 24-b 로 갈린 쪽)도 모자람을 설명한다 · resolved 무관
                        where r.order_id = s.id and r.sku = l.sku and r.kind = 'stock_short')
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
  select 200, 'last_release', 'info', 'Last release to WMS',
    'Newest Release to WMS from the office (Toronto time) - the signal that orders are still flowing into the warehouse. A long gap is normal when the office has nothing to release.',
    0::bigint, (select jsonb_build_object('last_at', last_at, 'last_at_toronto', last_at_toronto, 'minutes_ago', minutes_ago) from last_rel)
  order by 1;
end
$$;

-- 5g) inv_post_receipt — 20260926232330:47 · 더한 것 1줄(멱등 검사에서 <diff>:offpo 행 제외 — 훑기가 찾은 것: off-PO 를 확정 전에 받으면 확정의 원장 기표가 「이미 기표됨」으로 0행이 됐다)
create or replace function public.inv_post_receipt(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security invoker                                              -- 이견 3 — definer 가 필요한 표가 없다
set search_path = public, pg_temp
as $$
declare
  c_version   constant text := 'inv_post_receipt@2026-09-19.1';   -- raw.poster 에 박는다 — 배분 규칙이 바뀌면 올릴 것
  v_r         public.po_receipt%rowtype;
  v_po        public.po%rowtype;
  v_wh        text;
  v_existing  int;
  v_baseline  date;
  v_alloc     jsonb;
  v_lines     jsonb;
  v_rows      int := 0;
  v_counted   numeric := 0;
  v_posted    numeric := 0;
  v_excess    numeric := 0;
  v_warn      text[] := '{}';
  v_layers    jsonb;                                              -- 원가 레이어 결과(원가 이식 1차 · 2026-09-19)
  b           record;
begin

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was posted to the ledger', p_receipt_id; end if;
  if v_r.status <> 'confirmed' or v_r.confirmed_at is null then
    raise exception 'Receipt % is % — the ledger takes confirmed receipts only — nothing was posted to the ledger', v_r.receipt_number, v_r.status;
  end if;
  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  if v_wh is null then raise exception 'Warehouse of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;

  -- 2. 멱등 — 이미 기표된 입고는 다시 쓰지 않는다(터지지 않고 말한다 · ⬜5)
  select count(*) into v_existing
  from public.inv_ledger l
  where l.doc_type = 'purchase' and l.doc_number = v_r.receipt_number and l.source = 'ims'
    and l.line_ref not like '%:offpo';                                                          -- ⑤-6c1 off-PO 행(<diff>:offpo · 확정과 독립 · 확정 전에도 선다)은 「이미 기표됨」의 근거가 아니다
  if v_existing > 0 then
    -- ⭐ 원가 이식 1차(2026-09-19) — 원장은 이미 있어도 레이어는 없을 수 있다(이식 전에 확정된 RCV-00005·00006 · 백필 ⬜7).
    --   레이어 쪽도 같은 멱등 규칙(4키가 있으면 안 만든다)이라, 다시 부르면 빠진 레이어만 선다. 원장은 한 행도 다시 쓰지 않는다.
    v_layers := public.inv_layer_post_receipt(p_receipt_id);
    return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
                              'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0,
                              'qty_counted', null, 'qty_posted', null, 'qty_excess', null, 'lines', '[]'::jsonb,
                              'layers', v_layers, 'warnings', '["already_posted"]'::jsonb);
  end if;

  -- 6. 날짜 경고 — 기초선보다 이르면 · 미래면 (막지 않는다 · ⬜7)
  select (max(s.taken_at) at time zone 'America/Toronto')::date into v_baseline
  from public.inv_snapshot s
  where s.snapshot_key = (select c.value from public.inv_config c where c.key = 'baseline_snapshot_key');
  if v_baseline is not null and v_r.received_on < v_baseline then v_warn := array_append(v_warn, 'received_on_before_baseline'); end if;
  if v_r.received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  -- 3·4. 기준과 배분 — 한 번의 SQL 로 계산해 jsonb 배열에 담는다(그 뒤 루프는 넣고 더하기만 한다)
  with ln as (
    select l.po_line_id, sum(l.qty_ea) as counted, d.kind as diff_kind,
           case when d.kind is not null then d.expected_qty else sum(l.qty_ea) end as basis,     -- ⭐ 이견 1 — 기록용 기준: 차이 행(over·short)이 있으면 ⓑ 가 얼린 값 · 없으면 센 것
           case when d.kind = 'over'    then d.expected_qty else sum(l.qty_ea) end as cap        -- 깎기 상한: over 만 자른다 · posted 는 이것만 본다(검증 ⑤ 정정 — basis 와 갈랐다)
    from public.po_receipt_line l
    left join public.po_receipt_diff d on d.receipt_id = l.receipt_id and d.po_line_id = l.po_line_id
    where l.receipt_id = p_receipt_id
    group by l.po_line_id, d.kind, d.expected_qty
  ),
  alloc as (
    select l.id as receipt_line_id, l.po_line_id, l.bin_id, rb.name as bin, l.qty_ea, l.received_by, l.note,
           pl.line_no, pl.product_id, pl.unit_price, pr.sku,
           ln.counted, ln.basis, ln.cap, ln.diff_kind,
           least(l.qty_ea, greatest(ln.cap - coalesce(sum(l.qty_ea) over (partition by l.po_line_id order by l.qty_ea desc, rb.name, l.id
                                                                                  rows between unbounded preceding and 1 preceding), 0), 0)) as posted   -- ⭐ ⬜2 — 큰 빈부터 채우고 바닥나는 줄에서 자른다
    from public.po_receipt_line l
    join public.ref_bin  rb on rb.id = l.bin_id
    join public.po_line  pl on pl.id = l.po_line_id
    join public.product  pr on pr.id = pl.product_id
    join ln on ln.po_line_id = l.po_line_id
    where l.receipt_id = p_receipt_id
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no, a.qty_ea desc, a.bin, a.receipt_line_id), '[]'::jsonb) into v_alloc from alloc a;

  -- 5. 기표 — posted > 0 인 줄만 행이 된다
  for b in
    select * from jsonb_to_recordset(v_alloc) as t(
      receipt_line_id uuid, po_line_id uuid, bin_id uuid, bin text, qty_ea numeric, received_by uuid, note text,
      line_no int, product_id uuid, unit_price numeric, sku text, counted numeric, basis numeric, diff_kind text, posted numeric)
    order by line_no, qty_ea desc, bin
  loop
    if b.posted <= 0 then continue; end if;
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (
      v_r.received_on, 1, b.sku, v_wh, b.bin, b.posted, 'po_in', 'purchase', v_r.receipt_number, v_r.id::text, b.po_line_id::text, null, 'ims',          -- line_ref = po_line_id(라인 id · Caleb 실측 확정)
      jsonb_build_object(
        'kind', 'po_in', 'poster', c_version,
        'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'receipt_line_id', b.receipt_line_id,
        'po_id', v_po.id, 'po_number', v_po.po_number,                                   -- 갈라진 뒤의 번호(ⓓ 뒤에 불린다 · §11-j)
        'po_line_id', b.po_line_id, 'line_no', b.line_no, 'product_id', b.product_id, 'sku', b.sku,
        'warehouse_id', v_r.warehouse_id, 'warehouse', v_wh, 'bin_id', b.bin_id, 'bin', b.bin,
        'received_on', v_r.received_on, 'received_by', b.received_by, 'confirmed_by', v_r.confirmed_by, 'confirmed_at', v_r.confirmed_at,
        'line', jsonb_build_object('counted', b.counted, 'basis', b.basis, 'posted', least(b.counted, b.basis), 'excess', greatest(b.counted - b.basis, 0), 'diff_kind', b.diff_kind),
        'this_bin', jsonb_build_object('counted', b.qty_ea, 'posted', b.posted, 'trimmed', b.qty_ea - b.posted),
        'bins', (select jsonb_agg(jsonb_build_object('bin', t2.bin, 'counted', t2.qty_ea, 'posted', t2.posted, 'trimmed', t2.qty_ea - t2.posted) order by t2.qty_ea desc, t2.bin)
                 from jsonb_to_recordset(v_alloc) as t2(po_line_id uuid, bin text, qty_ea numeric, posted numeric) where t2.po_line_id = b.po_line_id),
        'trim_rule', 'fill bins by qty desc, then bin name; cut where the cap runs out; cap = po_receipt_diff.expected_qty when over, else counted (nothing to cut); basis (recorded) = expected_qty whenever a diff row exists, else counted',
        'unit_price', b.unit_price, 'currency_id', v_po.currency_id, 'exchange_rate', v_po.exchange_rate,
        'note', b.note));
    v_rows := v_rows + 1;
    v_posted := v_posted + b.posted;
  end loop;

  -- 라인 요약(0 으로 깎인 줄도 bins[] 에 남는다)
  select coalesce(jsonb_agg(jsonb_build_object(
           'po_line_id', t.po_line_id, 'line_no', t.line_no, 'sku', t.sku, 'counted', t.counted, 'basis', t.basis,
           'posted', t.posted, 'excess', greatest(t.counted - t.basis, 0), 'diff_kind', t.diff_kind, 'bins', t.bins) order by t.line_no), '[]'::jsonb),
         coalesce(sum(t.counted), 0), coalesce(sum(greatest(t.counted - t.basis, 0)), 0)
    into v_lines, v_counted, v_excess
  from (
    select a.po_line_id, min(a.line_no) as line_no, min(a.sku) as sku, min(a.counted) as counted, min(a.basis) as basis, min(a.diff_kind) as diff_kind,
           sum(a.posted) as posted,
           jsonb_agg(jsonb_build_object('bin', a.bin, 'counted', a.qty_ea, 'posted', a.posted, 'trimmed', a.qty_ea - a.posted) order by a.qty_ea desc, a.bin) as bins
    from jsonb_to_recordset(v_alloc) as a(po_line_id uuid, line_no int, sku text, bin text, qty_ea numeric, counted numeric, basis numeric, diff_kind text, posted numeric)
    group by a.po_line_id
  ) t;

  -- ⭐ 원가 레이어 — 원장 행을 만든 바로 그 수량으로(같은 트랜잭션 · 원장 사건과 함께 서거나 함께 죽는다 · 원가 이식 1차 2026-09-19).
  --   두 번 계산하지 않는다 — inv_layer_post_receipt 가 방금 넣은 inv_ledger 행(source='ims' · 이 RCV)을 읽어 라인 단위로 접는다.
  v_layers := public.inv_layer_post_receipt(p_receipt_id);

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
    'already_posted', false, 'existing_rows', 0,
    'rows_posted', v_rows, 'qty_counted', v_counted, 'qty_posted', v_posted, 'qty_excess', v_excess,
    'lines', v_lines, 'layers', v_layers, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Receipt % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_r.receipt_number, sqlerrm;
end;
$$;
revoke all on function public.inv_post_receipt(uuid) from public, anon, authenticated;   -- 5-3b 의 회수 그대로

-- 5h) inv_layer_post_receipt — 20260926232330:186 · 더한 것 1줄(루프에서 <diff>:offpo 행 제외 — :over 와 같은 이유 · 안 빼면 po_line 조회가 터져 확정 · 재생성이 죽는다)
create or replace function public.inv_layer_post_receipt(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_layer_post_receipt@2026-09-19.1';
  v_r        public.po_receipt%rowtype;
  v_po       public.po%rowtype;
  v_cur      text;
  v_base     text;
  v_factor   numeric;                 -- 통화 → CAD 계수. 기준통화면 1 · 아니면 po.exchange_rate(CAD per 통화)
  v_created  int := 0;
  v_existing int := 0;
  v_qty      numeric := 0;
  v_cost     numeric := 0;
  v_rows     int := 0;
  v_price    numeric;
  v_unit     numeric;
  v_layer_id bigint;
  v_lines    jsonb := '[]'::jsonb;
  v_warn     text[] := '{}';
  x          record;
begin

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — no cost layers were created', p_receipt_id; end if;
  if v_r.status <> 'confirmed' or v_r.confirmed_at is null then
    raise exception 'Receipt % is % — cost layers are built for confirmed receipts only — no cost layers were created', v_r.receipt_number, v_r.status;
  end if;
  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — no cost layers were created', v_r.receipt_number; end if;

  -- 통화 · 환율 (이견 4 — confirm 이 먼저 막지만 직접 호출·백필 경로도 여기서 막는다)
  select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
  select k.value into v_base from public.inv_config k where k.key = 'base_currency';
  if v_base is null then raise exception 'inv_config.base_currency is not set — cannot tell which orders need an exchange rate — no cost layers were created'; end if;
  if v_cur is distinct from v_base then
    if v_po.exchange_rate is null or v_po.exchange_rate <= 0 then
      raise exception 'PO % is in % but has no % per % exchange rate — stock cost cannot be worked out without it. Enter the rate in the order header ("Exchange rate" · it stays open after confirming) and run again — no cost layers were created',
        v_po.po_number, coalesce(v_cur, '?'), v_base, coalesce(v_cur, '?');
    end if;
    -- ⚠️⚠️⚠️ po.exchange_rate 는 CAD per USD 다 — unit_price(USD) × exchange_rate = CAD. 곱한다. 나누면 원가가 반으로 줄어드는데 에러가 안 난다.
    v_factor := v_po.exchange_rate;
  else
    v_factor := 1;                                                                                          -- 기준통화(CAD) — 환율을 곱하지 않는다(정본 1239행 「이미 CAD」)
    if v_po.exchange_rate is not null and v_po.exchange_rate <> 1 then v_warn := array_append(v_warn, 'exchange_rate_ignored_base_currency'); end if;
  end if;

  -- 원장 행을 라인 단위로 접는다(bin 을 버린다 · 이견 2 · 3) — 이 RCV 의 ims po_in 행만
  for x in
    select l.line_ref, l.sku, l.warehouse, sum(l.qty_delta) as qty, min(l.occurred_on) as received_on, count(*)::int as ledger_rows
    from public.inv_ledger l
    where l.doc_type = 'purchase' and l.source = 'ims' and l.event_type = 'po_in'
      and l.doc_number = v_r.receipt_number and l.qty_delta > 0
      and l.line_ref not like '%:over' and l.line_ref not like '%:offpo'                                -- ⑤-6c1 off-PO 행은 형제 창구 inv_layer_post_receipt_off_po 가 만든다(라인이 없어 po_line 조회가 안 된다)                                                              -- ⭐ 2026-09-20 초과분 행(over 닫기 · line_ref = po_line_id||':over')은 형제 창구 inv_layer_post_receipt_over 가 만든다 — 여기서 접으면 po_line 을 못 찾아 터지거나(접미어) free 를 발주 단가로 매긴다
    group by l.line_ref, l.sku, l.warehouse
    order by l.line_ref
  loop
    v_rows := v_rows + x.ledger_rows;
    -- 멱등 — 같은 4키의 레이어가 있으면 건너뛴다(inv_layer_apply_po_in 과 같은 규칙)
    if exists (select 1 from public.inv_layer y
                where y.origin_type = 'purchase' and y.doc_number = v_r.receipt_number and y.line_ref = x.line_ref
                  and y.sku = x.sku and y.warehouse = x.warehouse) then
      v_existing := v_existing + 1;
      continue;
    end if;
    -- 단가 — line_ref 가 po_line_id 다(원장 이식 2차 · Caleb 실측 확정)
    select pl.unit_price into v_price from public.po_line pl where pl.id::text = x.line_ref;
    if v_price is null then
      raise exception 'Ledger row % / % on % points at a PO line (%) that does not exist — the ledger is wrong, not this function — no cost layers were created', x.sku, x.warehouse, v_r.receipt_number, x.line_ref;
    end if;
    -- ⚠️⚠️⚠️ CAD per USD × USD 단가 = CAD 단가. 곱한다. (기준통화면 v_factor = 1)
    v_unit := v_price * v_factor;

    insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
    values (x.sku, x.warehouse, 'purchase', v_r.receipt_number, x.line_ref, null, x.received_on, true, x.qty, v_unit, 'po_line')
    returning id into v_layer_id;
    v_created := v_created + 1;
    v_qty  := v_qty  + x.qty;
    v_cost := v_cost + x.qty * v_unit;
    v_lines := v_lines || jsonb_build_object('layer_id', v_layer_id, 'po_line_id', x.line_ref, 'sku', x.sku, 'warehouse', x.warehouse,
                                             'qty', x.qty, 'ledger_rows', x.ledger_rows, 'unit_price', v_price, 'unit_cost_cad', v_unit, 'received_on', x.received_on);
  end loop;
  if v_rows = 0 then v_warn := array_append(v_warn, 'no_ledger_rows_for_receipt'); end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
    'currency', v_cur, 'base_currency', v_base, 'fx_rate', case when v_cur is distinct from v_base then v_po.exchange_rate else null end,
    'fx_direction', case when v_cur is distinct from v_base then v_base || ' per ' || coalesce(v_cur, '?') || ' — unit_price × rate'
                        else v_base || ' — base currency, no conversion (× 1)' end,          -- ⚠️ 나중에 방향을 의심할 때 보는 문장 — 거짓이면 안 된다(검증 ⑤ 정정)
    'ledger_rows', v_rows, 'layers_created', v_created, 'layers_existing', v_existing,
    'qty', v_qty, 'cost_total_cad', v_cost, 'cost_source', 'po_line', 'builder', c_version,
    'lines', v_lines, 'warnings', to_jsonb(v_warn));
end;
$$;
revoke all on function public.inv_layer_post_receipt(uuid) from public, anon, authenticated;   -- 5-3b 의 회수 그대로
