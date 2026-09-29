-- ─────────────────────────────────────────────────────────────
-- 재고 사건 ② 트랜스퍼 · 둘째 몫 「창고 간」 ④-1 도착 — 입고 창구가 트랜스퍼를 받고 · Complete 순간 도착 장부 · 원가 · received (Asung-IMS · tr-3a · 2026-09-28)
--   정본(뒤에 적는다): so-module §27(판정 66 · 68 · 70 · 73 · 74 · 묶음 아홉 7 · 열 4 · 8) · tr-1a · tr-1b1 · tr-1b2 · tr-2 위에 선다
--   든 것: ① 입고 표 넷 넓힘(trf-2 D 안 (가)) — po_receipt.transfer_id(po_id 와 정확히 하나) · po_receipt_line.transfer_line_id · po_receipt_work.transfer_line_id · po_receipt_diff.transfer_id/transfer_line_id(많아야 하나 · off_po 는 둘 다 없음) · 보통 유니크(규칙 29 · 부분 유니크 없음) · inv_transfer_line.qty_received
--         ② 입고 셸 넓힘 — wms_recv_start(문서 id · 트랜스퍼면 in_transit/receiving · 도착 창고 권한 · 초안 하나) · scan · count 의 첫 세기에 in_transit → receiving(tf_receiving_started) · 속 po_receipt_work_save_by 의 트랜스퍼 줄 갈래(기대 = qty_sent × pack_factor) · putaway_by · split · unassign · work_delete 의 줄 짝은 coalesce(PO 무변)
--         ③ Complete = 도착(판정 70) — wms_recv_complete 가 트랜스퍼면 같은 트랜잭션에 tf_arrive: 칸 없는 줄 거부 · 입고 줄(po_receipt_line · transfer_line_id) · 받은 > 보낸 은 보낸 수량까지만(넘는 몫은 po_receipt_diff over 기록만 · 결정은 tr-3b) · 받은 < 보낸 은 받은 만큼만(모자란 몫은 IN_TRANSIT 에 남는다 · short 기록 · 정리는 tr-3b · 판정 68) · qty_received · received · 입고 확정(오피스 확정 없음)
--            inv_post_transfer_arrive(원장 · 멱등): 낱개 SKU 키마다 레이어 창구 먼저 → IN_TRANSIT transfer_out −EA(seq 2 · leg 3 · 줄마다) + 도착 칸 transfer_in +EA(seq 1 · leg 4 · 칸마다) · line_ref = 줄 id ':' 입고 번호(묶음 아홉 7 · 나눠 받아도 유니크) · raw.kind transfer · raw.header.receipt_number
--            inv_layer_post_transfer_arrive(definer): IN_TRANSIT 레이어를 그 문서 범위로 FIFO(inv_layer_fifo_take p_doc_scope = TRF-n) → 도착 창고 레이어(parent · 같은 원가 · 나이) · 부족은 short(불러온 축과 같다)
--            inv_layer_apply 재발행: raw.kind transfer · 도착 창고 transfer_in → inv_layer_apply_transfer_arrive_ims(done 키 ims_tra(문서, 입고, SKU)) · leg 3 out 은 종전 out 갈래가 센다 · 반환 ims 에 다섯 키
--         ④ tf_wms_status 에 in_transit → receiving · receiving → received(receiving_at · received_at/by) · po_receipt_confirm_by · inv_post_receipt 는 트랜스퍼를 막는 한 줄만 · wms_recv_off_po 는 트랜스퍼 입고를 거부(초과 · 모르는 물건은 tr-3b)
--         ⑤ 읽기 정책 — inv_transfer · inv_transfer_line 의 창고 열쇠 정책에 wms_receiving 을 더한다(판정 73) · tf_receipt_detail(트랜스퍼 입고 상세 읽기 · ⑥ 화면용 · po_receipt_detail 은 PO 전용 그대로) · inv_transfer_detail 줄에 qty_received
--         ⑥ Health — transfer_received_no_ledger(179 · critical) · transfer_in_transit_30d(176 · warn · 묶음 10 의 8) · recv_stale 이 트랜스퍼 초안도 센다 · recv_nc 는 PO 만(트랜스퍼는 Complete = 확정)
--   ⭐ 약속: PO 입고 동작 무변(PO 로 부를 때 반환 · 전이 · 쓰는 행이 같다 — tr-3a-verify A10 옛/새 대조) · 판매 무변(wms-round · tr-1b1) · 트랜스퍼는 도착까지 — 운송 중 정리(lost · return) · 초과 결정 · 운임은 tr-3b · ⑤
--   되돌리기(G): 트랜스퍼 입고는 Complete 가 곧 확정이라 wms_recv_reopen 이 「already confirmed」로 거부한다(도착 원장 뒤 · 정리는 tr-3b) · PO 갈래 무변
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 판매 표 · 행 무접촉 · 판매 창구 · po_receipt_confirm(셸) · inv_post_receipt 본문(막는 한 줄 밖) 무접촉 · IMS 안에서만 선다(판정 51 · 60)
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

-- ═══ 1) 입고 표 넷 넓힘(trf-2 D 안 (가)) · 트랜스퍼 줄 칸 ═══
alter table public.inv_transfer_line add column qty_received numeric;
alter table public.inv_transfer_line add constraint inv_transfer_line_received_ck check (qty_received is null or (qty_received >= 0 and qty_received <= qty));
comment on column public.inv_transfer_line.qty_received is 'tr-3a(판정 68) — 도착 창고가 받아 칸에 넣은 수량(판매 단위 · 보낸 수량 상한 · Complete 때 채운다) · null = 아직 안 받음 · qty_received < qty_sent = 모자란 몫이 운송 중에 남아 있다(정리는 운송 중 정리)';
alter table public.po_receipt alter column po_id drop not null;
alter table public.po_receipt add column transfer_id uuid references public.inv_transfer (id) on delete restrict;
alter table public.po_receipt add constraint po_receipt_doc_ck check ((po_id is not null)::int + (transfer_id is not null)::int = 1);
create index po_receipt_transfer_id_idx on public.po_receipt (transfer_id);
comment on column public.po_receipt.transfer_id is 'tr-3a(판정 66) — 이 입고가 트랜스퍼 도착이면 그 문서(po_id 와 둘 중 정확히 하나) · 도착 창고 = warehouse_id · Complete 가 곧 확정(판정 70)';
alter table public.po_receipt_line alter column po_line_id drop not null;
alter table public.po_receipt_line add column transfer_line_id uuid references public.inv_transfer_line (id) on delete restrict;
alter table public.po_receipt_line add constraint po_receipt_line_doc_ck check ((po_line_id is not null)::int + (transfer_line_id is not null)::int = 1);
create index po_receipt_line_transfer_line_id_idx on public.po_receipt_line (transfer_line_id);
comment on column public.po_receipt_line.transfer_line_id is 'tr-3a — 트랜스퍼 줄(po_line_id 와 둘 중 정확히 하나) · 도착 사실 한 줄 = 칸 하나(Complete 가 쓴다)';
alter table public.po_receipt_work alter column po_line_id drop not null;
alter table public.po_receipt_work add column transfer_line_id uuid references public.inv_transfer_line (id) on delete restrict;
alter table public.po_receipt_work add constraint po_receipt_work_doc_ck check ((po_line_id is not null)::int + (transfer_line_id is not null)::int = 1);
alter table public.po_receipt_work add constraint po_receipt_work_receipt_tline_bin_key unique (receipt_id, transfer_line_id, bin_id);   -- 보통 유니크(규칙 29) · PO 줄은 po_line_id 짝이 지킨다
create index po_receipt_work_transfer_line_id_idx on public.po_receipt_work (transfer_line_id);
comment on column public.po_receipt_work.transfer_line_id is 'tr-3a — 트랜스퍼 줄(po_line_id 와 둘 중 정확히 하나) · 세기 · 놓기는 PO 와 같은 손(po_receipt_work_save_by · putaway_by)';
alter table public.po_receipt_diff alter column po_id drop not null;
alter table public.po_receipt_diff add column transfer_id uuid references public.inv_transfer (id) on delete restrict;
alter table public.po_receipt_diff add column transfer_line_id uuid references public.inv_transfer_line (id) on delete restrict;
alter table public.po_receipt_diff add constraint po_receipt_diff_doc_ck check ((po_id is not null)::int + (transfer_id is not null)::int = 1 and (po_line_id is not null)::int + (transfer_line_id is not null)::int <= 1);
alter table public.po_receipt_diff drop constraint po_receipt_diff_off_po_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_off_po_ck check ((kind = 'off_po') = (po_line_id is null and transfer_line_id is null));   -- 뜻 그대로(off-PO 만 줄이 없다) · 트랜스퍼 줄 차이(over · short)는 transfer_line_id 를 든다
alter table public.po_receipt_diff add constraint po_receipt_diff_receipt_tline_key unique (receipt_id, transfer_line_id);
create index po_receipt_diff_transfer_id_idx on public.po_receipt_diff (transfer_id);
comment on column public.po_receipt_diff.transfer_id is 'tr-3a(판정 68) — 트랜스퍼 도착의 차이(over = 보낸 것보다 더 왔다 · short = 덜 왔다 · 기록만 · 결정 · 정리는 운송 중 정리)';

-- ═══ 2) 읽기 정책 — 창고 일 열쇠에 wms_receiving 을 더한다(판정 73 · tr-1b2 정책 둘을 그 자리에서 고친다) ═══
alter policy inv_transfer_select_warehouse on public.inv_transfer
  using (public.ims_can_view('picking') or public.ims_can_view('packing') or public.ims_can_view('fulfillment') or public.ims_can_view('wms_manage') or public.ims_can_view('wms_receiving'));
alter policy inv_transfer_line_select_warehouse on public.inv_transfer_line
  using (public.ims_can_view('picking') or public.ims_can_view('packing') or public.ims_can_view('fulfillment') or public.ims_can_view('wms_manage') or public.ims_can_view('wms_receiving'));

-- ═══ 3) tf_receiving_started — 첫 세기에 in_transit → receiving(멱등 · 창고 창구만) ═══
create function public.tf_receiving_started(p_transfer_id uuid, p_staff uuid) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_st text;
begin
  select x.status into v_st from public.inv_transfer x where x.id = p_transfer_id for update;
  if v_st = 'in_transit' then return public.tf_wms_status(p_transfer_id, 'receiving', p_staff); end if;   -- 판정 66: 세기 시작 = receiving(저절로) · 이미 receiving 이면 그대로
  if v_st = 'receiving' then return jsonb_build_object('transfer_id', p_transfer_id, 'from', v_st, 'to', v_st); end if;
  raise exception 'Transfer is % — it cannot be counted in (only a transfer in transit or being received) — nothing was saved', coalesce(v_st, '<missing>');
end;
$$;
comment on function public.tf_receiving_started(uuid, uuid) is 'tr-3a(판정 66 · 묶음 열 4) — 도착 창고의 첫 세기(wms_recv_scan · count)가 부른다: in_transit → receiving 저절로 · 멱등 · 직원에게는 회수';
revoke all on function public.tf_receiving_started(uuid, uuid) from public, anon, authenticated;

-- ═══ 4) 레이어 창구 — 도착: IN_TRANSIT 레이어를 그 문서 범위로 FIFO → 도착 창고 레이어(parent · 같은 원가 · 나이) · 키 = (문서, 입고, 낱개 SKU) · 멱등 ═══
create function public.inv_layer_post_transfer_arrive(p_doc_number text, p_line_ref text, p_sku text, p_to_warehouse text, p_qty numeric, p_occurred_on date, p_hint jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_layer_post_transfer_arrive@2026-09-28.1';
        v_rows int; v_short int; v_layers int; v_taken numeric; v_amt numeric;
begin
  if p_qty is null or p_qty <= 0 then return jsonb_build_object('qty', p_qty, 'branch', 'none', 'builder', c_version); end if;
  if exists (select 1 from public.inv_layer y where y.origin_type = 'transfer' and y.doc_number = p_doc_number and y.warehouse = p_to_warehouse and y.sku = p_sku and y.line_ref = p_line_ref) then
    raise exception 'Transfer % / % arrival (%) was already costed — nothing was saved', p_doc_number, p_sku, p_line_ref;
  end if;
  -- IN_TRANSIT 소진은 그 문서의 레이어만(p_doc_scope = 문서 번호 · 불러온 축 inv_layer_apply_transfer_in 의 IN_TRANSIT 출발과 같은 손) → 도착 창고 레이어(parent = IN_TRANSIT 레이어 · unit_cost · received_on · age_known 그대로)
  select * into v_rows, v_short, v_layers, v_taken
    from public.inv_layer_fifo_take(p_sku, 'IN_TRANSIT', p_qty, 'transfer', p_doc_number, p_line_ref, 'transfer_out', p_occurred_on, 'transfer', p_to_warehouse, p_doc_number);
  select coalesce(sum(c.amount), 0) into v_amt from public.inv_layer_consume c join public.inv_layer y on y.id = c.layer_id
   where c.doc_type = 'transfer' and c.doc_number = p_doc_number and c.line_ref = p_line_ref and c.event_type = 'transfer_out' and y.sku = p_sku and y.warehouse = 'IN_TRANSIT';
  return jsonb_build_object('sku', p_sku, 'to_warehouse', p_to_warehouse, 'qty', p_qty, 'line_ref', p_line_ref,
                            'taken', coalesce(v_taken, 0), 'consume_rows', coalesce(v_rows, 0), 'layers', coalesce(v_layers, 0), 'short', coalesce(v_short, 0), 'short_qty', p_qty - coalesce(v_taken, 0),
                            'amount', v_amt, 'reproduced', p_hint is not null, 'builder', c_version);
end;
$$;
comment on function public.inv_layer_post_transfer_arrive(text, text, text, text, numeric, date, jsonb) is 'tr-3a(판정 66 · 67 앞) — 창고 간 트랜스퍼 도착의 원가: IN_TRANSIT 레이어를 그 문서 범위로 FIFO 소진(reason transfer) → 도착 창고 레이어(origin transfer · parent_layer · 같은 unit_cost · received_on · doc_number = TRF-n · line_ref = 줄:입고) · 부족은 short(레이어 없음) · 실시간(inv_post_transfer_arrive)과 재생성(inv_layer_apply_transfer_arrive_ims)이 같은 함수 · 운임(⑤)은 origin transfer · 도착 창고 레이어에 붙는다';
revoke all on function public.inv_layer_post_transfer_arrive(text, text, text, text, numeric, date, jsonb) from public, anon, authenticated;

-- ═══ 5) 원장 창구 — 도착(멱등 · 입고 단위 · inv_post_receipt 와 같은 결: 확정된 입고 줄에서 읽는다) ═══
create function public.inv_post_transfer_arrive(p_receipt_id uuid) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_post_transfer_arrive@2026-09-28.1';
        v_r public.po_receipt%rowtype; v_x public.inv_transfer%rowtype; v_fw text; v_tw text; v_existing int; v_alloc jsonb; v_costs jsonb := '{}'::jsonb; v_rows int := 0; v_qty numeric := 0; v_hdr jsonb;
        v_k record; v_b record; v_g record;                                                       -- ⚠️ CTE 별칭과 겹치지 않게 v_ 접두
begin
  select * into v_r from public.po_receipt r where r.id = p_receipt_id;
  if not found then raise exception 'Receipt not found — nothing was posted to the ledger'; end if;
  if v_r.transfer_id is null then raise exception 'Receipt % is a purchase receipt — its ledger is inv_post_receipt — nothing was posted to the ledger', v_r.receipt_number; end if;
  if v_r.status <> 'confirmed' or v_r.confirmed_at is null then raise exception 'Receipt % is % — the ledger takes completed (confirmed) arrivals only — nothing was posted to the ledger', v_r.receipt_number, v_r.status; end if;
  select * into v_x from public.inv_transfer x where x.id = v_r.transfer_id;
  select w.name into v_fw from public.ref_warehouse w where w.id = v_x.from_warehouse_id;
  select w.name into v_tw from public.ref_warehouse w where w.id = v_r.warehouse_id;
  if v_fw is null or v_tw is null then raise exception 'Transfer % has no warehouse pair — nothing was posted to the ledger', v_x.transfer_number; end if;
  -- 멱등 — 이 입고의 도착 행이 있으면 다시 쓰지 않는다(같은 문서의 다른 입고 · 출발 행은 근거가 아니다 · line_ref 접미어 = 입고 번호)
  select count(*) into v_existing from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = v_x.transfer_number and e.source = 'ims' and e.line_ref like '%:' || v_r.receipt_number;
  if v_existing > 0 then
    return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'already_posted', true, 'existing_rows', v_existing,
                              'rows_posted', 0, 'qty_ea_posted', 0, 'keys', '{}'::jsonb, 'warnings', '["already_posted"]'::jsonb);
  end if;
  -- 입고 줄(확정 사실 · 칸마다 · 보낸 수량까지 잘린 뒤의 EA)에서 줄×칸 모으기 · 낱개 SKU(세트 줄은 parent)
  with a as (
    select l.id as receipt_line_id, tl.id as line_id, tl.line_no, tl.product_id, tl.sku, tl.pack_factor, tl.qty as qty_requested, tl.qty_sent, tl.qty_received,
           coalesce(pp.sku, pr.sku) as base_sku, rb.name as bin, l.bin_id, l.qty_ea
      from public.po_receipt_line l
      join public.inv_transfer_line tl on tl.id = l.transfer_line_id
      join public.ref_bin rb on rb.id = l.bin_id
      join public.product pr on pr.id = tl.product_id left join public.product pp on pp.id = pr.parent_product_id
     where l.receipt_id = p_receipt_id and l.qty_ea > 0
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no, a.bin), '[]'::jsonb) into v_alloc from a;
  if jsonb_array_length(v_alloc) = 0 then raise exception 'Receipt % has no received quantity — nothing was posted to the ledger', v_r.receipt_number; end if;
  v_hdr := jsonb_build_object('transfer_number', v_x.transfer_number, 'from_warehouse_id', v_x.from_warehouse_id, 'from_warehouse', v_fw, 'to_warehouse_id', v_r.warehouse_id, 'to_warehouse', v_tw,
                              'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'received_on', v_r.received_on, 'received_at', v_x.received_at, 'received_by', v_x.received_by, 'confirmed_by', v_r.confirmed_by);
  -- ⭐ 레이어 먼저 — 낱개 SKU 키마다 한 번(IN_TRANSIT 문서 범위 → 도착 창고) · line_ref = 첫 줄 id ':' 입고 번호(묶음 아홉 7 · 재생성 키와 같다)
  for v_k in
    select t.base_sku, sum(t.qty_ea) as qty_ea, (array_agg(t.line_id::text order by t.line_no, t.bin))[1] || ':' || v_r.receipt_number as line_ref
      from jsonb_to_recordset(v_alloc) as t(base_sku text, qty_ea numeric, line_id uuid, line_no int, bin text)
     group by t.base_sku order by t.base_sku
  loop
    v_costs := v_costs || jsonb_build_object(v_k.base_sku, public.inv_layer_post_transfer_arrive(v_x.transfer_number, v_k.line_ref, v_k.base_sku, v_tw, v_k.qty_ea, v_r.received_on, null));
  end loop;
  -- leg 3 — 줄마다 IN_TRANSIT(칸 '') −EA(seq 2 · line_ref = 줄:입고)
  for v_g in
    select t.line_id, t.line_no, t.product_id, t.sku, t.base_sku, t.pack_factor, t.qty_requested, t.qty_sent, t.qty_received, sum(t.qty_ea) as qty_ea
      from jsonb_to_recordset(v_alloc) as t(line_id uuid, line_no int, product_id uuid, sku text, base_sku text, pack_factor numeric, qty_requested numeric, qty_sent numeric, qty_received numeric, bin text, qty_ea numeric)
     group by t.line_id, t.line_no, t.product_id, t.sku, t.base_sku, t.pack_factor, t.qty_requested, t.qty_sent, t.qty_received order by t.line_no
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_r.received_on, 2, v_g.base_sku, 'IN_TRANSIT', '', -v_g.qty_ea, 'transfer_out', 'transfer', v_x.transfer_number, v_x.id::text, v_g.line_id::text || ':' || v_r.receipt_number, null, 'ims',
            jsonb_build_object('kind', 'transfer', 'leg', 3, 'poster', c_version, 'header', v_hdr,
              'line', jsonb_build_object('line_id', v_g.line_id, 'line_no', v_g.line_no, 'product_id', v_g.product_id, 'sku', v_g.sku, 'base_sku', v_g.base_sku, 'pack_factor', v_g.pack_factor,
                                         'qty_requested', v_g.qty_requested, 'qty_sent', v_g.qty_sent, 'qty_received', v_g.qty_received, 'qty_ea', v_g.qty_ea),
              'rule', format('transfer %s → %s leg 3: −%s EA out of IN_TRANSIT at arrival (receipt %s · received units only · the rest stays in transit)', v_fw, v_tw, v_g.qty_ea, v_r.receipt_number),
              'cost', v_costs -> v_g.base_sku));
    v_rows := v_rows + 1;
  end loop;
  -- leg 4 — 줄×칸 · 도착 창고 칸에 +EA(seq 1)
  for v_b in
    select * from jsonb_to_recordset(v_alloc) as t(receipt_line_id uuid, line_id uuid, line_no int, product_id uuid, sku text, pack_factor numeric, qty_requested numeric, qty_sent numeric, qty_received numeric, base_sku text, bin text, bin_id uuid, qty_ea numeric)
     order by line_no, bin
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_r.received_on, 1, v_b.base_sku, v_tw, v_b.bin, v_b.qty_ea, 'transfer_in', 'transfer', v_x.transfer_number, v_x.id::text, v_b.line_id::text || ':' || v_r.receipt_number, null, 'ims',
            jsonb_build_object('kind', 'transfer', 'leg', 4, 'poster', c_version, 'header', v_hdr,
              'line', jsonb_build_object('line_id', v_b.line_id, 'line_no', v_b.line_no, 'product_id', v_b.product_id, 'sku', v_b.sku, 'base_sku', v_b.base_sku, 'pack_factor', v_b.pack_factor,
                                         'qty_requested', v_b.qty_requested, 'qty_sent', v_b.qty_sent, 'qty_received', v_b.qty_received, 'receipt_line_id', v_b.receipt_line_id, 'bin_id', v_b.bin_id, 'bin', v_b.bin, 'qty_ea', v_b.qty_ea),
              'rule', format('transfer %s → %s leg 4: +%s EA into %s / %s (receipt %s · arrival = warehouse Complete)', v_fw, v_tw, v_b.qty_ea, v_tw, v_b.bin, v_r.receipt_number),
              'cost', v_costs -> v_b.base_sku));
    v_rows := v_rows + 1; v_qty := v_qty + v_b.qty_ea;
  end loop;
  return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'already_posted', false, 'existing_rows', 0,
                            'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'keys', v_costs, 'poster', c_version);
exception when unique_violation then
  raise exception 'Transfer % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_x.transfer_number, sqlerrm;
end;
$$;
comment on function public.inv_post_transfer_arrive(uuid) is 'tr-3a(판정 66 · 68 · 70) — 트랜스퍼 도착의 원장(입고 단위): 확정된 입고 줄에서 낱개 SKU 키마다 레이어 창구 먼저 → IN_TRANSIT '''' transfer_out −EA(seq 2 · leg 3 · 줄마다) + 도착 칸 transfer_in +EA(seq 1 · leg 4 · 칸마다) · line_ref = 줄 id:입고 번호 · raw.kind transfer · raw.header.receipt_number · 멱등(그 입고의 행이 있으면 말하는 0) · Complete 트랜잭션 안에서 tf_arrive 가 부른다';
revoke all on function public.inv_post_transfer_arrive(uuid) from public, anon, authenticated;

-- ═══ 6) 재생성 갈래 — 도착 창고 in(leg 4 · raw.kind transfer)에서 (문서, 입고, SKU) 한 번 · 실시간과 같은 창구 ═══
create function public.inv_layer_apply_transfer_arrive_ims(p_ledger_id bigint) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare r public.inv_ledger%rowtype; v_rcv text; v_qty numeric; v_lref text; v_res jsonb;
begin
  select * into r from public.inv_ledger where id = p_ledger_id;
  if not found or r.source <> 'ims' or (r.raw ->> 'kind') is distinct from 'transfer' or r.event_type <> 'transfer_in' or r.warehouse = 'IN_TRANSIT' then
    return jsonb_build_object('processed', false, 'reason', 'not an arrival row');
  end if;
  v_rcv := r.raw -> 'header' ->> 'receipt_number';
  if v_rcv is null then return jsonb_build_object('processed', false, 'reason', 'no receipt number in raw.header'); end if;
  if exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_tra' and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = v_rcv) then
    return jsonb_build_object('processed', false, 'reason', 'done');
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_tra', r.doc_number, r.sku, v_rcv);   -- 키 = (문서, 낱개 SKU, 입고 번호) · warehouse 칸에 입고 번호(not null 칸 재사용 · 창고는 행이 안다)
  select sum(e.qty_delta) into v_qty from public.inv_ledger e
   where e.doc_type = 'transfer' and e.doc_number = r.doc_number and e.source = 'ims' and (e.raw ->> 'kind') = 'transfer'
     and e.event_type = 'transfer_in' and e.warehouse = r.warehouse and e.sku = r.sku and e.raw -> 'header' ->> 'receipt_number' = v_rcv;   -- 같은 문서 · 입고 · 낱개 SKU 의 leg 4 전부(칸 여럿은 접는다)
  v_lref := coalesce(r.raw -> 'cost' ->> 'line_ref', r.line_ref);
  v_res := public.inv_layer_post_transfer_arrive(r.doc_number, v_lref, r.sku, r.warehouse, v_qty, r.occurred_on, r.raw -> 'cost');
  return v_res || jsonb_build_object('processed', true);
end;
$$;
comment on function public.inv_layer_apply_transfer_arrive_ims(bigint) is 'tr-3a — inv_layer_apply 의 IMS 트랜스퍼 도착 갈래(raw.kind transfer · 도착 창고 transfer_in 행에서) · done 키 ims_tra(문서, 낱개 SKU, 입고 번호) · 창구 inv_layer_post_transfer_arrive 를 실시간과 같은 합으로 부른다(IN_TRANSIT 문서 범위) · leg 3 out 은 본체가 세고 지나간다';
revoke all on function public.inv_layer_apply_transfer_arrive_ims(bigint) from public, anon, authenticated;

-- ═══ 7) tf_arrive — 창고 Complete 안에서만 부르는 도착 손(판정 66 · 68 · 70 · 74) ═══
create function public.tf_arrive(p_receipt_id uuid, p_staff uuid) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_r public.po_receipt%rowtype; v_x public.inv_transfer%rowtype; v_lines jsonb := '[]'::jsonb; v_ledger jsonb; v_n int; v_open int; v_over int := 0; v_short int := 0; v_posted numeric := 0; v_counted numeric := 0;
        v_l record; v_w record; v_rem numeric; v_take numeric;
begin
  select * into v_r from public.po_receipt r where r.id = p_receipt_id for update;
  if not found then raise exception 'Receipt not found — nothing was saved'; end if;
  if v_r.transfer_id is null then raise exception 'Receipt % is a purchase receipt — nothing was saved', v_r.receipt_number; end if;
  if v_r.status <> 'draft' then raise exception 'Receipt % is already % — nothing was saved', v_r.receipt_number, v_r.status; end if;
  select * into v_x from public.inv_transfer x where x.id = v_r.transfer_id for update;
  if v_x.status not in ('in_transit', 'receiving') then raise exception 'Transfer % is % — only a transfer in transit can arrive — nothing was saved', v_x.transfer_number, v_x.status; end if;
  select count(*) into v_open from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.bin_id is null;
  if v_open > 0 then raise exception 'Receipt % — % counted row(s) still have no bin; put them away first — nothing was saved', v_r.receipt_number, v_open; end if;
  if not exists (select 1 from public.po_receipt_work w where w.receipt_id = p_receipt_id) then raise exception 'Receipt % has nothing counted — nothing was saved', v_r.receipt_number; end if;
  -- 줄마다: 기대 = 보낸 수량(qty_sent × pack_factor · 판정 74) · 받은 = Σ작업 줄 · 판정 68: 받은 > 보낸 → 보낸 수량까지만 도착(큰 칸부터 채우고 바닥나는 줄에서 자른다 · inv_post_receipt 와 같은 규칙) · 넘는 몫은 over 기록 · 받은 < 보낸 → 받은 만큼만 · 모자란 몫은 IN_TRANSIT 에 남고 short 기록
  for v_l in
    select tl.id, tl.line_no, tl.product_id, tl.sku, tl.pack_factor, tl.qty, coalesce(tl.qty_sent, 0) * tl.pack_factor as expected_ea, coalesce(sum(w.qty_ea), 0) as counted_ea
      from public.inv_transfer_line tl left join public.po_receipt_work w on w.receipt_id = p_receipt_id and w.transfer_line_id = tl.id
     where tl.transfer_id = v_x.id group by tl.id order by tl.line_no
  loop
    if v_l.counted_ea = 0 then
      if v_l.expected_ea > 0 then
        insert into public.po_receipt_diff (receipt_id, po_id, transfer_id, po_line_id, transfer_line_id, product_id, kind, expected_qty, received_qty, note, updated_by)
        values (p_receipt_id, null, v_x.id, null, v_l.id, v_l.product_id, 'short', v_l.expected_ea, 0, 'transfer arrival — nothing received for this line (the sent units stay in transit)', p_staff);
        v_short := v_short + 1;
      end if;
      update public.inv_transfer_line set qty_received = 0, updated_by = p_staff where id = v_l.id;
      v_lines := v_lines || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'expected_ea', v_l.expected_ea, 'counted_ea', 0, 'posted_ea', 0, 'over_ea', 0, 'short_ea', v_l.expected_ea);
      continue;
    end if;
    v_rem := least(v_l.counted_ea, v_l.expected_ea);
    for v_w in select w.id, w.bin_id, w.qty_ea, rb.name as bin from public.po_receipt_work w join public.ref_bin rb on rb.id = w.bin_id where w.receipt_id = p_receipt_id and w.transfer_line_id = v_l.id order by w.qty_ea desc, rb.name, w.id loop
      v_take := least(v_w.qty_ea, greatest(v_rem, 0));
      if v_take > 0 then
        insert into public.po_receipt_line (po_line_id, transfer_line_id, received_on, received_by, bin_id, qty_ea, receipt_id)
        values (null, v_l.id, v_r.received_on, p_staff, v_w.bin_id, v_take, p_receipt_id);
      end if;
      v_rem := v_rem - v_take;
    end loop;
    if v_l.counted_ea > v_l.expected_ea then
      insert into public.po_receipt_diff (receipt_id, po_id, transfer_id, po_line_id, transfer_line_id, product_id, kind, expected_qty, received_qty, note, updated_by)
      values (p_receipt_id, null, v_x.id, null, v_l.id, v_l.product_id, 'over', v_l.expected_ea, v_l.counted_ea, 'transfer arrival — more counted than was sent; only the sent units arrived, the extra is recorded for the in-transit settlement', p_staff);
      v_over := v_over + 1;
    elsif v_l.counted_ea < v_l.expected_ea then
      insert into public.po_receipt_diff (receipt_id, po_id, transfer_id, po_line_id, transfer_line_id, product_id, kind, expected_qty, received_qty, note, updated_by)
      values (p_receipt_id, null, v_x.id, null, v_l.id, v_l.product_id, 'short', v_l.expected_ea, v_l.counted_ea, 'transfer arrival — fewer counted than were sent; the missing units stay in transit (in-transit settlement)', p_staff);
      v_short := v_short + 1;
    end if;
    update public.inv_transfer_line set qty_received = least(v_l.counted_ea, v_l.expected_ea) / v_l.pack_factor, updated_by = p_staff where id = v_l.id;
    v_posted := v_posted + least(v_l.counted_ea, v_l.expected_ea); v_counted := v_counted + v_l.counted_ea;
    v_lines := v_lines || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'expected_ea', v_l.expected_ea, 'counted_ea', v_l.counted_ea, 'posted_ea', least(v_l.counted_ea, v_l.expected_ea),
                                             'over_ea', greatest(v_l.counted_ea - v_l.expected_ea, 0), 'short_ea', greatest(v_l.expected_ea - v_l.counted_ea, 0));
  end loop;
  select count(*) into v_n from public.po_receipt_line l where l.receipt_id = p_receipt_id;
  if v_n = 0 then raise exception 'Receipt % — nothing of what was sent was received — nothing was saved', v_r.receipt_number; end if;
  -- 상태 손 — receiving → received(received_at/by) · 입고 확정(판정 70 · 오피스 확정 없음)
  if v_x.status = 'in_transit' then perform public.tf_wms_status(v_x.id, 'receiving', p_staff); end if;
  perform public.tf_wms_status(v_x.id, 'received', p_staff);
  update public.po_receipt set status = 'confirmed', confirmed_by = p_staff, confirmed_at = now(), updated_by = p_staff where id = p_receipt_id and status = 'draft';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Receipt % changed under you — nothing was saved', v_r.receipt_number; end if;
  v_ledger := public.inv_post_transfer_arrive(p_receipt_id);                              -- 원장 · 레이어 · 같은 트랜잭션(실패하면 Complete 도 안 된다)
  return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'status', 'received',
                            'received_on', v_r.received_on, 'received_by', p_staff, 'counted_ea', v_counted, 'posted_ea', v_posted, 'over_lines', v_over, 'short_lines', v_short, 'lines', v_lines, 'ledger', v_ledger);
end;
$$;
comment on function public.tf_arrive(uuid, uuid) is 'tr-3a(판정 66 · 68 · 70 · 74) — 창고 Complete(wms_recv_complete)가 트랜스퍼 입고에 부르는 도착 손: 입고 줄(칸마다 · 보낸 수량까지) · over/short 기록 · qty_received · receiving → received · 입고 확정 · 원장 · 레이어 · 되돌리기 없음 · 직원에게는 회수(판정 31)';
revoke all on function public.tf_arrive(uuid, uuid) from public, anon, authenticated;

-- ═══ 8) tf_receipt_detail — 트랜스퍼 입고 상세 읽기(⑥ 화면용 · po_receipt_detail 은 PO 전용 그대로 · invoker · RLS 가 문) ═══
create function public.tf_receipt_detail(p_receipt_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not exists (select 1 from public.po_receipt r where r.id = p_receipt_id and r.transfer_id is not null) then null::jsonb else (
    select jsonb_build_object(
      'header', jsonb_build_object('id', r.id, 'receipt_number', r.receipt_number, 'status', r.status, 'received_on', r.received_on, 'transfer_id', x.id, 'transfer_number', x.transfer_number, 'transfer_status', x.status,
                                   'from_warehouse_id', x.from_warehouse_id, 'from_warehouse', fw.name, 'warehouse_id', r.warehouse_id, 'warehouse_name', tw.name, 'departed_at', x.departed_at, 'received_at', x.received_at,
                                   'confirmed_at', r.confirmed_at, 'created_at', r.created_at, 'note', r.note),
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('line_id', tl.id, 'line_no', tl.line_no, 'product_id', tl.product_id, 'sku', tl.sku, 'product_name', p.name, 'pack_factor', tl.pack_factor,
                         'qty', tl.qty, 'qty_sent', tl.qty_sent, 'qty_received', tl.qty_received, 'expected_ea', coalesce(tl.qty_sent, 0) * tl.pack_factor,
                         'counted', coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = r.id and w.transfer_line_id = tl.id), 0),
                         'allocated', coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = r.id and w.transfer_line_id = tl.id and w.bin_id is not null), 0),
                         'placed', coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = r.id and w.transfer_line_id = tl.id and w.putaway_done), 0),
                         'received_here', coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.receipt_id = r.id and l.transfer_line_id = tl.id), 0),
                         'work', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'qty_ea', w.qty_ea, 'bin_id', w.bin_id, 'bin', b.name, 'zone', b.zone, 'putaway_done', w.putaway_done, 'count_method', w.count_method,
                                                                               'counted_by', w.counted_by, 'counted_at', w.counted_at, 'putaway_by', w.putaway_by, 'putaway_at', w.putaway_at) order by w.bin_id nulls first, w.created_at)
                                            from public.po_receipt_work w left join public.ref_bin b on b.id = w.bin_id where w.receipt_id = r.id and w.transfer_line_id = tl.id), '[]'::jsonb))
                       order by tl.line_no), '[]'::jsonb)
                  from public.inv_transfer_line tl join public.product p on p.id = tl.product_id where tl.transfer_id = x.id),
      'diffs', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'transfer_line_id', d.transfer_line_id, 'sku', pr.sku, 'expected_qty', d.expected_qty, 'received_qty', d.received_qty, 'diff_qty', d.received_qty - d.expected_qty,
                                                              'note', d.note, 'resolved_at', d.resolved_at, 'resolution', d.resolution) order by d.created_at), '[]'::jsonb)
                  from public.po_receipt_diff d join public.product pr on pr.id = d.product_id where d.receipt_id = r.id),
      'wms', public.wms_recv_state(r.id))
      from public.po_receipt r join public.inv_transfer x on x.id = r.transfer_id
      join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = r.warehouse_id
     where r.id = p_receipt_id) end;
$$;
comment on function public.tf_receipt_detail(uuid) is 'tr-3a — 트랜스퍼 도착 입고의 상세 읽기(입고 화면 ⑥): 머리(입고 · 트랜스퍼 · 출발/도착 창고) · 줄(보낸 · 기대 EA · 센 · 놓은 · 받은 · 작업 줄) · 차이 · 창고 상태 · PO 입고는 po_receipt_detail 그대로';
revoke all on function public.tf_receipt_detail(uuid) from public, anon;
grant execute on function public.tf_receipt_detail(uuid) to authenticated;

-- ═══ 9) 재발행 16 — 마지막 정의 바이트 그대로 + 바꾼 줄(diff 원문은 보고) · create or replace 라 grant · comment · security 가 남는다 ═══

-- ── tf_wms_status ──
create or replace function public.tf_wms_status(p_transfer_id uuid, p_to text, p_staff uuid) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare
  v_x    public.inv_transfer%rowtype;
  v_from text;
  v_n    int;
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  v_from := v_x.status;
  if not ((p_to = 'at_wms'    and v_from in ('confirmed', 'picking'))
       or (p_to = 'confirmed' and v_from = 'at_wms')
       or (p_to = 'picking'   and v_from = 'at_wms')
       or (p_to = 'in_transit' and v_from = 'picking')                                  -- tr-2 판정 65: 출발 = 창고 마무리(picking → in_transit · tf_depart 만 부른다) · packed 는 트랜스퍼에 없다
       or (p_to = 'receiving'  and v_from = 'in_transit')                                -- tr-3a 판정 66: 도착 창고가 세기 시작하면 저절로(wms_recv_scan · count 의 첫 세기)
       or (p_to = 'received'   and v_from = 'receiving')) then                            -- tr-3a 판정 70: 도착 창고 Complete = 확정(tf_arrive 만 부른다) · 되돌리기 없음
    raise exception 'Transfer % is % — it cannot move to % from there — nothing was saved', v_x.transfer_number, v_from, p_to;
  end if;
  update public.inv_transfer x
     set status     = p_to,
         at_wms_at  = case when p_to = 'at_wms' and v_from = 'confirmed' then now()   when p_to = 'confirmed' then null else x.at_wms_at  end,
         at_wms_by  = case when p_to = 'at_wms' and v_from = 'confirmed' then p_staff when p_to = 'confirmed' then null else x.at_wms_by  end,
         picking_at = case when p_to = 'picking' and v_from = 'at_wms' then now()     when p_to = 'at_wms' and v_from = 'picking' then null else x.picking_at end,
         picking_by = case when p_to = 'picking' and v_from = 'at_wms' then p_staff   when p_to = 'at_wms' and v_from = 'picking' then null else x.picking_by end,
         departed_at = case when p_to = 'in_transit' then now()   else x.departed_at end,                                                          -- tr-2: 출발 시각 · 사람(되돌리기 없음 · 묶음 5)
         departed_by = case when p_to = 'in_transit' then p_staff else x.departed_by end,
         receiving_at = case when p_to = 'receiving' then now() else x.receiving_at end,                                                            -- tr-3a
         received_at = case when p_to = 'received' then now()   else x.received_at end,
         received_by = case when p_to = 'received' then p_staff else x.received_by end,
         updated_by = p_staff
   where x.id = p_transfer_id and x.status = v_from;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Transfer % changed under you (expected %) — nothing was saved', v_x.transfer_number, v_from;
  end if;
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'from', v_from, 'to', p_to);
end;
$$;

-- ── po_receipt_work_save_by ──
create or replace function public.po_receipt_work_save_by(
  p_staff        uuid,                              -- ⑤-3a 속: 부른 셸이 확인한 사람(판정 7) · 문은 셸에
  p_receipt_id   uuid,
  p_po_line_id   uuid,
  p_qty_ea       numeric,                           -- ⭐ 그 라인의 센 수량(총량 · 낱개) · 0 = 센 것 없음
  p_count_method text default null                  -- 'scanned' | 'manual' | null
) returns jsonb
language plpgsql
volatile
security definer                                   -- ⑤-3a: po_receipt* 의 RLS 가 receiving 을 요구한다 · 창고 사람은 셸의 문을 지나 여기로 · 표는 소유자로 쓴다
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_r      public.po_receipt%rowtype;
  v_pl     public.po_line%rowtype;
  v_tl     public.inv_transfer_line%rowtype;         -- tr-3a: 트랜스퍼 줄(receipt.transfer_id 가 있으면 p_po_line_id 는 트랜스퍼 줄 id)
  v_line_no int; v_expected numeric; v_is_tf boolean := false;
  v_sku    text;
  v_alloc  numeric;
  v_free   public.po_receipt_work%rowtype;    -- 빈 없는 줄(있으면)
  v_free_n int;
  v_rest   numeric;
  v_n      int;
  v_action text;
  v_id     uuid;
  v_now    timestamptz := now();
begin
  if p_staff is null then raise exception 'po_receipt_work_save_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

  if p_qty_ea is null or p_qty_ea < 0 then raise exception 'p_qty_ea must be 0 or more — nothing was saved'; end if;
  if p_count_method is not null and p_count_method not in ('scanned', 'manual') then
    raise exception 'p_count_method must be scanned, manual or null — nothing was saved';
  end if;
  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — counts can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  if v_r.transfer_id is not null then                                          -- tr-3a 판정 66 · 74: 트랜스퍼 입고 — 기대 = 보낸 수량(qty_sent × pack_factor · 낱개)
    v_is_tf := true;
    select * into v_tl from public.inv_transfer_line where id = p_po_line_id;
    if not found then raise exception 'Transfer line % not found — nothing was saved', p_po_line_id; end if;
    if v_tl.transfer_id <> v_r.transfer_id then
      raise exception 'Transfer line % does not belong to the transfer of receipt % — nothing was saved', p_po_line_id, v_r.receipt_number;
    end if;
    v_line_no := v_tl.line_no; v_expected := coalesce(v_tl.qty_sent, 0) * v_tl.pack_factor;
    select pr.sku into v_sku from public.product pr where pr.id = v_tl.product_id;
  else
  select * into v_pl from public.po_line where id = p_po_line_id;
  if not found then raise exception 'PO line % not found — nothing was saved', p_po_line_id; end if;
  if v_pl.po_id <> v_r.po_id then                                              -- 남의 PO 라인을 붙이지 못하게
    raise exception 'PO line % does not belong to the PO of receipt % — nothing was saved', p_po_line_id, v_r.receipt_number;
  end if;
  v_line_no := v_pl.line_no; v_expected := v_pl.qty_ea;
  select pr.sku into v_sku from public.product pr where pr.id = v_pl.product_id;
  end if;
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || p_po_line_id::text));   -- 이견 12 — 같은 라인의 동시 저장을 줄 세운다(빈 없는 줄 둘 방지)

  -- 배정 합(빈 붙은 줄들) · 빈 없는 줄
  select coalesce(sum(w.qty_ea), 0) into v_alloc from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id and w.bin_id is not null;
  select count(*) into v_free_n from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id and w.bin_id is null;
  if v_free_n > 1 then                                                          -- 불변식 ① 이 깨져 있다 — 자동으로 고치지 않고 알린다
    raise exception 'Line % of receipt % has % unassigned rows — this should not happen; fix the rows first — nothing was saved', v_line_no, v_r.receipt_number, v_free_n;
  end if;
  select * into v_free from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id and w.bin_id is null;

  -- ⬜2 나머지 = 센 수량 − 배정 합
  v_rest := p_qty_ea - v_alloc;
  if v_rest < 0 then
    raise exception 'Line % (%) of receipt %: counted % is less than the % already assigned to bins — reduce or remove the bin rows first — nothing was saved',
      v_line_no, v_sku, v_r.receipt_number, p_qty_ea, v_alloc;
  end if;

  if v_rest = 0 then
    if v_free.id is not null then
      delete from public.po_receipt_work where id = v_free.id;
      get diagnostics v_n = row_count;
      if v_n = 0 then raise exception 'Line % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_line_no, v_r.receipt_number; end if;
      v_action := 'deleted';
    else
      v_action := 'unchanged';                                                  -- 0 을 세었고 줄도 없다 — 쓸 것이 없다
    end if;
  elsif v_free.id is not null then
    update public.po_receipt_work
       set qty_ea = v_rest, count_method = coalesce(p_count_method, count_method), counted_by = v_staff, counted_at = v_now
     where id = v_free.id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Line % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_line_no, v_r.receipt_number; end if;
    v_id := v_free.id; v_action := 'updated';
  else
    insert into public.po_receipt_work (receipt_id, po_line_id, transfer_line_id, qty_ea, count_method, counted_by, counted_at)
    values (p_receipt_id, case when v_is_tf then null else p_po_line_id end, case when v_is_tf then p_po_line_id end, v_rest, p_count_method, v_staff, v_now)
    returning id into v_id;
    v_action := 'inserted';
  end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_line_id', p_po_line_id, 'line_no', v_line_no, 'sku', v_sku,
    'counted', p_qty_ea, 'allocated', v_alloc, 'unallocated', v_rest,
    'work_id', v_id, 'action', v_action, 'counted_by', v_staff, 'counted_at', v_now,
    'over_ordered', (p_qty_ea > v_expected));                                   -- 초과 신호(표시용 · 판정·큐는 2-b 확정 RPC · 트랜스퍼는 보낸 수량 기준)
end;
$$;

-- ── po_receipt_work_putaway_by ──
create or replace function public.po_receipt_work_putaway_by(
  p_staff        uuid,                              -- ⑤-3a 속: 부른 셸이 확인한 사람(판정 7) · 문은 셸에
  p_work_id uuid,
  p_bin_id  uuid,
  p_done    boolean default true
) returns jsonb
language plpgsql
volatile
security definer                                   -- ⑤-3a: po_receipt* 의 RLS 가 receiving 을 요구한다 · 창고 사람은 셸의 문을 지나 여기로 · 표는 소유자로 쓴다
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_w      public.po_receipt_work%rowtype;
  v_r      public.po_receipt%rowtype;
  v_b      public.ref_bin%rowtype;
  v_dup    public.po_receipt_work%rowtype;
  v_n      int;
  v_now    timestamptz := now();
  v_out_id uuid;
  v_merged uuid;
begin
  if p_staff is null then raise exception 'po_receipt_work_putaway_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

  select * into v_w from public.po_receipt_work where id = p_work_id;
  if not found then raise exception 'Work row % not found — nothing was saved', p_work_id; end if;
  select * into v_r from public.po_receipt where id = v_w.receipt_id;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — putaway can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  v_b := public.po_receipt_bin_check(v_w.receipt_id, p_bin_id);                -- 창고·활성
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || coalesce(v_w.po_line_id, v_w.transfer_line_id)::text));   -- 이견 12 — 같은 라인의 동시 저장을 줄 세운다(빈 없는 줄 둘 방지) · tr-3a 트랜스퍼 줄도 같은 열쇠

  -- 같은 라인에 그 빈 줄이 이미 있으면(다른 줄) — 합친다(유니크가 막는 자리를 병합으로 · 합 불변)
  select * into v_dup from public.po_receipt_work w
   where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id) and w.bin_id = p_bin_id and w.id <> p_work_id;
  if found then
    update public.po_receipt_work set qty_ea = qty_ea + v_w.qty_ea, putaway_done = coalesce(p_done, true), putaway_by = v_staff, putaway_at = v_now where id = v_dup.id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_dup.id, v_r.receipt_number; end if;
    delete from public.po_receipt_work where id = p_work_id and qty_ea = v_w.qty_ea;                  -- 읽은 수량 그대로일 때만 지운다
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;
    v_out_id := v_dup.id; v_merged := v_dup.id;
  else
    update public.po_receipt_work
       set bin_id = p_bin_id, putaway_done = coalesce(p_done, true), putaway_by = v_staff, putaway_at = v_now
     where id = p_work_id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;
    v_out_id := p_work_id;
  end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'work_id', v_out_id, 'po_line_id', coalesce(v_w.po_line_id, v_w.transfer_line_id),
    'bin_id', p_bin_id, 'bin', v_b.name, 'zone', v_b.zone, 'putaway_done', coalesce(p_done, true),
    'putaway_by', v_staff, 'putaway_at', v_now, 'merged_into', v_merged);
end;
$$;

-- ── po_receipt_work_split ──
create or replace function public.po_receipt_work_split(
  p_work_id uuid,
  p_qty_ea  numeric,                                -- 떼어 낼 수량(낱개) · 0 < p_qty_ea < 원래 수량
  p_bin_id  uuid                                    -- ⭐ 새 줄의 빈(필수 · 그 입고의 창고 · 활성)
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_w      public.po_receipt_work%rowtype;
  v_r      public.po_receipt%rowtype;
  v_b      public.ref_bin%rowtype;
  v_to     public.po_receipt_work%rowtype;
  v_to_id  uuid;
  v_to_before numeric := 0;
  v_merged boolean := false;
  v_n      int;
  v_total  numeric;
  v_now    timestamptz := now();
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ②
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_w from public.po_receipt_work where id = p_work_id;
  if not found then raise exception 'Work row % not found — nothing was saved', p_work_id; end if;
  select * into v_r from public.po_receipt where id = v_w.receipt_id;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — rows can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  if p_qty_ea is null or p_qty_ea <= 0 then raise exception 'p_qty_ea must be above 0 — nothing was saved'; end if;
  if p_qty_ea >= v_w.qty_ea then
    raise exception 'Cannot split % of % — the row would be left with nothing; use putaway to move the whole row — nothing was saved', p_qty_ea, v_w.qty_ea;
  end if;
  v_b := public.po_receipt_bin_check(v_w.receipt_id, p_bin_id);                -- 창고·활성(도우미 · 문장은 거기)
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || coalesce(v_w.po_line_id, v_w.transfer_line_id)::text));   -- 이견 12 — 같은 라인의 동시 저장을 줄 세운다(빈 없는 줄 둘 방지) · tr-3a
  if v_w.bin_id = p_bin_id then
    raise exception 'The row is already in bin % — pick a different bin to split into — nothing was saved', v_b.name;
  end if;

  -- 원래 줄에서 뺀다
  update public.po_receipt_work set qty_ea = qty_ea - p_qty_ea where id = p_work_id and qty_ea = v_w.qty_ea;   -- ⭐ 읽은 수량 그대로일 때만(남이 사이에 바꿨으면 0행)
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;

  -- 같은 라인·같은 빈 줄이 있으면 합친다(유니크가 막는 자리를 병합으로) · 없으면 새 줄
  select * into v_to from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id) and w.bin_id = p_bin_id;
  if found then
    v_to_id := v_to.id; v_to_before := v_to.qty_ea; v_merged := true;
    update public.po_receipt_work set qty_ea = qty_ea + p_qty_ea, putaway_done = true, putaway_by = v_staff, putaway_at = v_now where id = v_to.id;   -- ⬜1 합쳐진 줄도 놓인 것 · by/at 은 putaway 병합 가지와 같은 모양(덮는다)
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_to.id, v_r.receipt_number; end if;
  else
    insert into public.po_receipt_work (receipt_id, po_line_id, transfer_line_id, qty_ea, bin_id, putaway_done, count_method, counted_by, counted_at, putaway_by, putaway_at)
    values (v_w.receipt_id, v_w.po_line_id, v_w.transfer_line_id, p_qty_ea, p_bin_id, true, v_w.count_method, v_w.counted_by, v_w.counted_at, v_staff, v_now)    -- ⭐ 빈을 고르는 순간 놓인 것(true · Caleb 2026-09-18) · 수량 축은 원래 줄의 것을 물려받는다(센 사람은 안 바뀐다)
    returning id into v_to_id;
  end if;

  select coalesce(sum(w.qty_ea), 0) into v_total from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id);
  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_line_id', v_w.po_line_id,
    'from', jsonb_build_object('work_id', v_w.id, 'bin_id', v_w.bin_id, 'qty_before', v_w.qty_ea, 'qty_after', v_w.qty_ea - p_qty_ea),
    'to',   jsonb_build_object('work_id', v_to_id, 'bin_id', p_bin_id, 'bin', v_b.name, 'zone', v_b.zone, 'qty_before', v_to_before, 'qty_after', v_to_before + p_qty_ea, 'merged', v_merged),
    'line_total', v_total);                                                    -- ⭐ 쪼개기 전과 같아야 한다
end;
$$;

-- ── po_receipt_work_unassign ──
create or replace function public.po_receipt_work_unassign(p_work_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_w       public.po_receipt_work%rowtype;
  v_r       public.po_receipt%rowtype;
  v_b       public.ref_bin%rowtype;
  v_free    public.po_receipt_work%rowtype;    -- 그 라인의 빈 없는 줄(있으면)
  v_free_n  int;
  v_before  numeric;
  v_after   numeric;
  v_n       int;
  v_out_id  uuid;
  v_removed uuid;
  v_merged  uuid;
  v_qty     numeric;
  v_action  text;
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ②
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_w from public.po_receipt_work where id = p_work_id;
  if not found then raise exception 'Work row % not found — nothing was saved', p_work_id; end if;
  select * into v_r from public.po_receipt where id = v_w.receipt_id;
  if v_r.confirmed_at is not null or v_r.status <> 'draft' then                    -- 축은 confirmed_at · status 도 함께(cancelled 도 못 고친다) — work_delete 와 같은 검사
    raise exception 'Receipt % is % — rows can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || coalesce(v_w.po_line_id, v_w.transfer_line_id)::text));   -- 2-a 이견 12 와 같은 키 — 같은 라인의 동시 저장을 줄 세운다(빈 없는 줄 둘 방지) · tr-3a
  select coalesce(sum(w.qty_ea), 0) into v_before from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id);

  -- ⬜1 이미 빈이 없다 — 쓸 것이 없다(멱등)
  if v_w.bin_id is null then
    return jsonb_build_object(
      'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_line_id', v_w.po_line_id,
      'work_id', v_w.id, 'removed_work_id', null, 'merged_into', null,
      'qty_moved', 0, 'qty_after', v_w.qty_ea, 'bin_before', null, 'line_total', v_before, 'action', 'unchanged');
  end if;
  select * into v_b from public.ref_bin where id = v_w.bin_id;                     -- 반환용 이름(없어도 진행 — 되돌리는 데 빈 표는 필요 없다)

  -- 그 라인의 빈 없는 줄 — 둘 이상이면 불변식이 깨져 있다(work_save 와 같은 처방 · 자동으로 고치지 않는다)
  select count(*) into v_free_n from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id) and w.bin_id is null;
  if v_free_n > 1 then
    raise exception 'Line of receipt % has % unassigned rows — this should not happen; fix the rows first — nothing was saved', v_r.receipt_number, v_free_n;
  end if;
  select * into v_free from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id) and w.bin_id is null;

  if v_free.id is not null then
    -- ⭐ 병합 — 빈 없는 줄에 더하고 이 줄을 지운다(putaway 의 v_dup 가지와 같은 결 · 수량 축 counted_* 은 안 건드린다)
    update public.po_receipt_work set qty_ea = qty_ea + v_w.qty_ea where id = v_free.id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_free.id, v_r.receipt_number; end if;
    delete from public.po_receipt_work where id = p_work_id and qty_ea = v_w.qty_ea;                  -- 읽은 수량 그대로일 때만 지운다
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;
    v_out_id := v_free.id; v_removed := v_w.id; v_merged := v_free.id; v_qty := v_free.qty_ea + v_w.qty_ea; v_action := 'merged';
  else
    -- 빈 없는 줄이 없다 — 이 줄이 그 줄이 된다(빈·놓았나·넣은 사람 전부 되돌린다 · putaway_bin_ck 와 함께)
    update public.po_receipt_work
       set bin_id = null, putaway_done = false, putaway_by = null, putaway_at = null
     where id = p_work_id and bin_id = v_w.bin_id;                                                     -- 읽은 빈 그대로일 때만(남이 사이에 옮겼으면 0행)
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;
    v_out_id := v_w.id; v_removed := null; v_merged := null; v_qty := v_w.qty_ea; v_action := 'unassigned';
  end if;

  -- ⭐ 합 불변 — 함수가 보장한다(다르면 전부 되돌린다)
  select coalesce(sum(w.qty_ea), 0) into v_after from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id);
  if v_after <> v_before then
    raise exception 'Line total of receipt % changed from % to % while taking the row out of its bin — nothing was saved', v_r.receipt_number, v_before, v_after;
  end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_line_id', v_w.po_line_id,
    'work_id', v_out_id, 'removed_work_id', v_removed, 'merged_into', v_merged,
    'qty_moved', v_w.qty_ea, 'qty_after', v_qty,
    'bin_before', jsonb_build_object('bin_id', v_w.bin_id, 'bin', v_b.name, 'zone', v_b.zone),
    'line_total', v_after, 'action', v_action);
end;
$$;

-- ── po_receipt_work_delete ──
create or replace function public.po_receipt_work_delete(p_work_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_w  public.po_receipt_work%rowtype;
  v_r  public.po_receipt%rowtype;
  v_n  int;
  v_total numeric;
begin
  perform public.ims_require_write('receiving', 'deleted');    -- §5 ②
  select * into v_w from public.po_receipt_work where id = p_work_id;
  if not found then raise exception 'Work row % not found — nothing was deleted', p_work_id; end if;
  select * into v_r from public.po_receipt where id = v_w.receipt_id;
  if v_r.confirmed_at is not null or v_r.status <> 'draft' then                    -- 축은 confirmed_at(20260917100000) · status 도 함께(cancelled 도 못 고친다)
    raise exception 'Receipt % is % — rows can be deleted only while draft — nothing was deleted', v_r.receipt_number, v_r.status;
  end if;
  delete from public.po_receipt_work where id = p_work_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Work row % of receipt % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', p_work_id, v_r.receipt_number; end if;
  select coalesce(sum(w.qty_ea), 0) into v_total from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id);
  return jsonb_build_object('deleted', true, 'work_id', v_w.id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number,
                            'po_line_id', v_w.po_line_id, 'qty_removed', v_w.qty_ea, 'bin_id', v_w.bin_id, 'line_total', v_total);
end;
$$;

-- ── wms_recv_start ──
create or replace function public.wms_recv_start(p_po_id uuid) returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_po public.po%rowtype; v_r public.po_receipt%rowtype; v_out jsonb; v_x public.inv_transfer%rowtype; v_whn text;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_po from public.po p where p.id = p_po_id;
  if not found then
    -- tr-3a 판정 66: 문서 id 가 트랜스퍼면 도착 창고의 입고 초안(PO 갈래는 아래 그대로) · in_transit(첫 시작) 또는 receiving(초안이 이미 있다) · 도착 창고 권한
    select * into v_x from public.inv_transfer x where x.id = p_po_id;
    if not found then raise exception 'PO not found — nothing was saved'; end if;
    if not public.ims_can_warehouse(v_x.to_warehouse_id) then
      raise exception 'Transfer % arrives at another warehouse — you are not set up for it — nothing was saved', v_x.transfer_number;
    end if;
    if v_x.status not in ('in_transit', 'receiving') then
      raise exception 'Transfer % is % — receiving can start only once it has left the sending warehouse (in transit) — nothing was saved', v_x.transfer_number, v_x.status;
    end if;
    select * into v_r from public.po_receipt r where r.transfer_id = v_x.id and r.status = 'draft' order by r.created_at limit 1;
    if found then
      return jsonb_build_object('id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status, 'po_id', null, 'po_number', null, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number,
                                'warehouse_id', v_r.warehouse_id, 'received_on', v_r.received_on, 'existing', true,
                                'held', exists (select 1 from public.wms_task_holds h where h.receipt_id = v_r.id and h.resumed_at is null));
    end if;
    perform pg_advisory_xact_lock(hashtext('po_receipt:' || v_x.id::text));                          -- 문서당 초안 하나(규칙 29 · po_receipt_create_by 와 같은 손)
    if exists (select 1 from public.po_receipt r where r.transfer_id = v_x.id and r.status = 'draft') then
      raise exception 'Transfer % already has an open receipt — continue that one — nothing was saved', v_x.transfer_number;
    end if;
    select w.name into v_whn from public.ref_warehouse w where w.id = v_x.to_warehouse_id and w.is_active;
    if v_whn is null then raise exception 'Warehouse of transfer % not found or inactive — nothing was saved', v_x.transfer_number; end if;
    insert into public.po_receipt (po_id, transfer_id, warehouse_id, received_on, status, created_by)
    values (null, v_x.id, v_x.to_warehouse_id, public.ims_today(), 'draft', v_staff) returning * into v_r;
    return jsonb_build_object('id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status, 'po_id', null, 'po_number', null, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number,
                              'warehouse_id', v_r.warehouse_id, 'warehouse_name', v_whn, 'received_on', v_r.received_on, 'created_by', v_staff, 'warnings', '[]'::jsonb, 'existing', false, 'held', false);
  end if;
  if v_po.ship_to_warehouse_id is not null and not public.ims_can_warehouse(v_po.ship_to_warehouse_id) then
    raise exception 'PO % ships to another warehouse — you are not set up for it — nothing was saved', v_po.po_number;
  end if;
  select * into v_r from public.po_receipt r where r.po_id = p_po_id and r.status = 'draft' order by r.created_at limit 1;
  if found then
    return jsonb_build_object('id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status, 'po_id', v_po.id, 'po_number', v_po.po_number,
                              'warehouse_id', v_r.warehouse_id, 'received_on', v_r.received_on, 'existing', true,
                              'held', exists (select 1 from public.wms_task_holds h where h.receipt_id = v_r.id and h.resumed_at is null));
  end if;
  v_out := public.po_receipt_create_by(v_staff, p_po_id, public.ims_today(), null);
  return v_out || jsonb_build_object('existing', false, 'held', false);
end;
$$;

-- ── wms_recv_scan ──
create or replace function public.wms_recv_scan(p_receipt_id uuid, p_po_line_id uuid, p_delta_ea numeric, p_count_method text default 'scanned') returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_r public.po_receipt%rowtype; v_total numeric;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  v_r := public.wms_recv_gate(p_receipt_id);
  if p_delta_ea is null or p_delta_ea = 0 then raise exception 'Scan delta must not be 0 — nothing was saved'; end if;
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || p_po_line_id::text));   -- 속과 같은 열쇠(재진입) · 읽기와 쓰기를 한 손에
  select coalesce(sum(w.qty_ea), 0) into v_total from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id;
  if v_total + p_delta_ea < 0 then raise exception 'Line total would go below 0 (now % · delta %) — nothing was saved', v_total, p_delta_ea; end if;
  if v_r.transfer_id is not null then perform public.tf_receiving_started(v_r.transfer_id, v_staff); end if;   -- tr-3a 판정 66: 첫 세기에 in_transit → receiving 저절로
  return public.po_receipt_work_save_by(v_staff, p_receipt_id, p_po_line_id, v_total + p_delta_ea, p_count_method) || jsonb_build_object('delta', p_delta_ea, 'total_before', v_total);
end;
$$;

-- ── wms_recv_count ──
create or replace function public.wms_recv_count(p_receipt_id uuid, p_po_line_id uuid, p_total_ea numeric, p_seen_total numeric, p_count_method text default 'manual') returns jsonb
  language plpgsql volatile security definer      -- ⑤-3a 셸: 회수된 속(_by)을 부른다(a1 부터의 모양 · 문은 첫 줄)
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_r public.po_receipt%rowtype; v_total numeric;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  v_r := public.wms_recv_gate(p_receipt_id);
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || p_po_line_id::text));
  select coalesce(sum(w.qty_ea), 0) into v_total from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id;
  if p_seen_total is not null and v_total <> p_seen_total then
    raise exception 'Line total changed under you: you saw %, it is now % (someone else counted) — reload the line and try again — nothing was saved', p_seen_total, v_total;
  end if;
  if v_r.transfer_id is not null then perform public.tf_receiving_started(v_r.transfer_id, v_staff); end if;   -- tr-3a 판정 66: 첫 세기에 in_transit → receiving 저절로
  return public.po_receipt_work_save_by(v_staff, p_receipt_id, p_po_line_id, p_total_ea, p_count_method) || jsonb_build_object('total_before', v_total);
end;
$$;

-- ── wms_recv_complete ──
create or replace function public.wms_recv_complete(p_receipt_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_r public.po_receipt%rowtype; v_c public.wms_receipt_complete%rowtype; v_open int; v_arr jsonb;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_r from public.po_receipt r where r.id = p_receipt_id;
  if not found then raise exception 'Receipt not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_r.warehouse_id) then
    raise exception 'Receipt % is at another warehouse — you are not set up for it — nothing was saved', v_r.receipt_number;
  end if;
  if v_r.status <> 'draft' then raise exception 'Receipt % is already % — nothing to complete — nothing was saved', v_r.receipt_number, v_r.status; end if;
  if exists (select 1 from public.wms_receipt_complete c where c.receipt_id = p_receipt_id and c.completed) then
    raise exception 'Receipt % is already completed in the warehouse — nothing was saved', v_r.receipt_number;
  end if;
  if not exists (select 1 from public.po_receipt_work w where w.receipt_id = p_receipt_id) then
    raise exception 'Receipt % has nothing counted — count at least one line before completing — nothing was saved', v_r.receipt_number;
  end if;
  select count(*) into v_open from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.bin_id is null;
  if v_r.transfer_id is not null and v_open > 0 then                                      -- tr-3a 판정 66 · 70: 트랜스퍼는 Complete 가 곧 도착(칸에 들어온다) — 칸 없는 줄이 있으면 받지 않는다
    raise exception 'Receipt % — % counted row(s) still have no bin; put them away first (a transfer arrives into its bins at Complete) — nothing was saved', v_r.receipt_number, v_open;
  end if;
  update public.wms_task_holds set resumed_at = now(), resumed_by = v_staff where receipt_id = p_receipt_id and resumed_at is null;   -- 열린 보류가 있으면 Complete 가 닫는다(운영 finishReceipt 와 같다)
  insert into public.wms_receipt_complete as c (receipt_id, completed, completed_by, completed_at)
  values (p_receipt_id, true, v_staff, now())
  on conflict (receipt_id) do update set completed = true, completed_by = v_staff, completed_at = now()
  returning * into v_c;
  if v_r.transfer_id is not null then v_arr := public.tf_arrive(p_receipt_id, v_staff); end if;   -- tr-3a 판정 66 · 68 · 70: 같은 트랜잭션에 도착 — 입고 줄 · 차이 기록 · 원장 · 레이어 · received · 입고 확정(오피스 확정 없음)
  return jsonb_build_object('receipt_id', p_receipt_id, 'receipt_number', v_r.receipt_number, 'completed', true, 'completed_by', v_c.completed_by, 'completed_at', v_c.completed_at,
                            'lines_without_bin', v_open, 'warnings', case when v_open > 0 then jsonb_build_array('lines_without_bin') else '[]'::jsonb end)
         || case when v_arr is null then '{}'::jsonb else jsonb_build_object('arrived', v_arr) end;   -- PO 반환 모양 무변 · 트랜스퍼만 arrived 를 더한다
end;
$$;

-- ── wms_recv_off_po ──
create or replace function public.wms_recv_off_po(p_receipt_id uuid, p_product_id uuid, p_qty_ea numeric) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_r public.po_receipt%rowtype; v_p public.product%rowtype; v_d public.po_receipt_diff%rowtype; v_new boolean := false;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  v_r := public.wms_recv_gate(p_receipt_id);
  if v_r.status <> 'draft' then raise exception 'Receipt % is % — off-PO items can be added only while draft — nothing was saved', v_r.receipt_number, v_r.status; end if;
  if v_r.transfer_id is not null then raise exception 'Receipt % is a transfer arrival — items that were not sent are settled in the in-transit settlement (next step), not as off-PO — nothing was saved', v_r.receipt_number; end if;   -- tr-3a: 초과 · 모르는 물건은 tr-3b
  if p_qty_ea is null or p_qty_ea <= 0 then raise exception 'Off-PO quantity must be more than 0 — nothing was saved'; end if;
  select * into v_p from public.product p where p.id = p_product_id;
  if not found then raise exception 'Product not found — nothing was saved'; end if;
  if exists (select 1 from public.po_line l where l.po_id = v_r.po_id and l.product_id = p_product_id) then
    raise exception 'Product % is on this PO — count it on its line, not as off-PO — nothing was saved', v_p.sku;
  end if;
  select * into v_d from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.kind = 'off_po' and d.product_id = p_product_id and d.resolved_at is null;
  if found then
    update public.po_receipt_diff set received_qty = received_qty + p_qty_ea, updated_by = v_staff where id = v_d.id returning * into v_d;
  else
    insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty, note, updated_by)
    values (p_receipt_id, v_r.po_id, null, p_product_id, 'off_po', 0, p_qty_ea, 'off-PO (WMS receiving) — approval pending', v_staff) returning * into v_d;
    v_new := true;
  end if;
  return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_p.sku, 'product_id', p_product_id, 'kind', 'off_po', 'received_qty', v_d.received_qty, 'added', p_qty_ea, 'created', v_new, 'declared_by', v_staff);
end;
$$;

-- ── po_receipt_confirm_by ──
create or replace function public.po_receipt_confirm_by(p_staff uuid, p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security definer                                              -- ⭐ 이견 1 — po·po_line·po_discount(purchasing RLS)에 쓴다. 권한은 첫머리 ims_require_write('receiving') 가 묻는다
set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_r         public.po_receipt%rowtype;
  v_po        public.po%rowtype;
  v_pl        public.po_line%rowtype;
  v_base      text;
  v_max       text;
  v_a_num     text;
  v_b_num     text;
  v_b_id      uuid;
  v_n         int;
  v_free_txt  text;
  v_free_n    int;
  v_work_n    int;
  v_lines_n   int := 0;
  v_over      int := 0;
  v_short     int := 0;
  v_rem_total numeric := 0;
  v_reduced   int := 0;
  v_moved     int := 0;
  v_cleared   text[] := '{}';
  v_warn      text[] := '{}';
  v_rows      jsonb := '[]'::jsonb;
  v_now       timestamptz := now();
  v_ledger    jsonb;                                           -- ⓔ 원장 창구의 반환(원장 이식 2차 · 2026-09-19)
  v_cur       text;                                            -- ⑥ 환율 게이트(원가 이식 1차 · 2026-09-19) — 발주 통화 코드
  v_base_cur  text;                                            -- ⑥ 기준통화 코드 · ⚠️ v_base(접미사를 뗀 PO 번호 · 잠금·채번)와 다른 것 — 이름을 같이 쓰면 채번이 CADa 가 된다(2026-09-19 실사고)
  x           record;
begin
  if p_staff is null then raise exception 'po_receipt_confirm_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  if v_r.transfer_id is not null then raise exception 'Receipt % is a transfer arrival — it is confirmed by the warehouse Complete, not here — nothing was saved', v_r.receipt_number; end if;   -- tr-3a 판정 70(트랜스퍼를 막는 한 줄만)
  -- ① 이미 확정·취소
  if v_r.confirmed_at is not null or v_r.status = 'confirmed' then
    raise exception 'Receipt % was already confirmed on % — nothing was saved', v_r.receipt_number, to_char(v_r.confirmed_at, 'YYYY-MM-DD');
  end if;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — only a draft receipt can be confirmed — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was saved', v_r.receipt_number; end if;
  -- ⭐ 잠금 — PO 단위(형제 채번·분할·닫기 · 키는 접미사를 뗀 base) + 라인 단위(작업 줄 RPC 들과 같은 키 · 세는 중인 손을 줄 세운다)
  v_base := regexp_replace(v_po.po_number, '[a-z]+$', '');
  perform pg_advisory_xact_lock(hashtext('po:' || v_base));
  for x in select pl.id from public.po_line pl where pl.po_id = v_po.id loop
    perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || x.id::text));
  end loop;
  -- ④ 잠금 뒤 다시 본다 — 그 사이 닫혔거나 취소됐을 수 있다
  select * into v_po from public.po where id = v_r.po_id;
  if v_po.status <> 'confirmed' then
    raise exception 'PO % is % — a receipt can be confirmed only on a confirmed order — nothing was saved', v_po.po_number, v_po.status;
  end if;
  select * into v_r from public.po_receipt where id = p_receipt_id;                     -- 잠금 뒤 다시(남이 사이에 확정했을 수 있다)
  if v_r.status <> 'draft' or v_r.confirmed_at is not null then
    raise exception 'Receipt % was changed by someone else just now (% ) — reload and try again — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  -- ③ 작업 줄이 없다
  select count(*) into v_work_n from public.po_receipt_work w where w.receipt_id = p_receipt_id;
  if v_work_n = 0 then
    raise exception 'Receipt % has nothing counted — count at least one line before confirming, or delete the receipt — nothing was saved', v_r.receipt_number;
  end if;
  -- ②⭐⭐ 빈 없는 줄 — 라인·수량을 문장에 · 빠져나갈 길을 함께
  select count(*), string_agg(format('line %s (%s) %s EA', t.line_no, t.sku, t.qty_ea), ', ' order by t.line_no)
    into v_free_n, v_free_txt
  from (select pl.line_no, pr.sku, w.qty_ea
          from public.po_receipt_work w join public.po_line pl on pl.id = w.po_line_id join public.product pr on pr.id = pl.product_id
         where w.receipt_id = p_receipt_id and w.bin_id is null) t;
  if v_free_n > 0 then
    raise exception 'Receipt % cannot be confirmed — % row(s) still have no bin: %. Put them away first, or lower the count to what you actually placed — the rest stays on the order — nothing was saved',
      v_r.receipt_number, v_free_n, v_free_txt;
  end if;
  -- ⑤ 더 막는 것 — 빈이 그 사이 다른 창고 것·비활성으로 바뀌었나(배정 때 봤지만 확정은 장부에 닿는다 · 한 번 더)
  select count(*) into v_n
  from public.po_receipt_work w join public.ref_bin b on b.id = w.bin_id
  where w.receipt_id = p_receipt_id and (b.warehouse_id <> v_r.warehouse_id or not b.is_active);
  if v_n > 0 then
    raise exception 'Receipt % has % row(s) in a bin that is inactive or not in this receipt''s warehouse — move them to another bin first — nothing was saved', v_r.receipt_number, v_n;
  end if;
  if v_r.received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  -- ⑥ ⭐⭐ 환율 — 기준통화가 아닌 발주인데 환율이 없거나 0 이면 **확정 자체를 거부**한다(Caleb 2026-09-19 · 원가가 조용히 틀리는 것보다 낫다 · 정본 「0 금지」).
  --   기준통화는 inv_config.base_currency(박지 않는다) · 발주 통화는 po.currency_id → ref_currency.code.
  --   ⚠️ po.exchange_rate 는 **CAD per USD** 다(Cin7 「CAD units per USD」 · 화면 칸 「CAD per USD」) — unit_price × exchange_rate = CAD. 곱한다 · 나누지 않는다.
  --   문장이 어디서 고치는지 말한다 — 발주 머리의 「Exchange rate (CAD per USD)」 칸 · 확정 뒤에도 열려 있다(po.html HEAD_ALWAYS).
  select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
  select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
  if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which orders need an exchange rate — nothing was saved'; end if;
  if v_cur is distinct from v_base_cur and (v_po.exchange_rate is null or v_po.exchange_rate <= 0) then
    raise exception 'PO % is in % but has no % per % exchange rate — stock cost cannot be worked out without it. Enter the rate in the order header ("Exchange rate" · it stays open after confirming) and confirm again — nothing was saved',
      v_po.po_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
  end if;

  -- ═══ ⓐ 작업 줄 → 입고 줄 (1:1 · received_on 은 묶음의 것 · received_by 는 놓은 사람 → 센 사람 → 확정한 사람 · 초과분도 그대로) ═══
  insert into public.po_receipt_line (po_line_id, received_on, received_by, bin_id, qty_ea, note, receipt_id)
  select w.po_line_id, v_r.received_on, coalesce(w.putaway_by, w.counted_by, v_staff), w.bin_id, w.qty_ea, w.note, v_r.id
  from public.po_receipt_work w
  where w.receipt_id = p_receipt_id
  order by w.po_line_id, w.created_at;
  get diagnostics v_lines_n = row_count;
  if v_lines_n <> v_work_n then
    raise exception 'Receipt %: % work row(s) but % receipt line(s) were written — nothing was saved', v_r.receipt_number, v_work_n, v_lines_n;
  end if;

  -- ═══ ⓑ 차이 (분할 전 수량이 기준) — over · short · 안 센 라인은 short(received 0) ═══
  for x in
    select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pl.qty_ea as ordered,
           pl.qty_ea - coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as expected,
           coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id), 0) as counted
    from public.po_line pl join public.product pr on pr.id = pl.product_id
    where pl.po_id = v_po.id
    order by pl.line_no
  loop
    if x.counted <> x.expected then
      insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty)
      values (v_r.id, v_po.id, x.po_line_id, x.product_id, case when x.counted > x.expected then 'over' else 'short' end, greatest(x.expected, 0), x.counted);
      if x.counted > x.expected then v_over := v_over + 1; else v_short := v_short + 1; end if;
      v_rows := v_rows || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', case when x.counted > x.expected then 'over' else 'short' end,
                                             'expected_qty', greatest(x.expected, 0), 'received_qty', x.counted);
    end if;
    if x.expected - x.counted > 0 then v_rem_total := v_rem_total + (x.expected - x.counted); end if;
  end loop;

  -- ═══ ⓒ 분할 또는 닫기 ═══
  if v_rem_total > 0 then
    -- ⬜4 번호 — 같은 base 의 접미사 최댓값 다음 두 글자(없으면 a·b)
    select max(substring(p.po_number from length(v_base) + 1)) into v_max
    from public.po p where p.po_number ~ ('^' || v_base || '[a-z]+$');
    if v_max is null then
      v_a_num := v_base || 'a'; v_b_num := v_base || 'b';
    else
      if length(v_max) <> 1 or v_max >= 'y' then
        raise exception 'PO % has been split too many times (last suffix %) — split it by hand — nothing was saved', v_po.po_number, v_max;
      end if;
      v_a_num := v_base || chr(ascii(v_max) + 1); v_b_num := v_base || chr(ascii(v_max) + 2);
    end if;

    -- b 문서 — 머리를 통째로 복사(칸이 늘어도 따라온다) · 번호 b · split_from_id = a · 상태 confirmed(같은 확정의 나머지 · confirmed_at/by 도 물려받는다) · 닫힘·취소 흔적 없음
    v_b_id := gen_random_uuid();
    insert into public.po
    select * from jsonb_populate_record(null::public.po,
      to_jsonb(v_po) || jsonb_build_object('id', v_b_id, 'po_number', v_b_num, 'status', 'confirmed', 'split_from_id', v_po.id,
                                           'closed_at', null, 'cancelled_at', null, 'cancelled_by', null,
                                           'created_at', v_now, 'updated_at', v_now, 'updated_by', v_staff));
    -- 할인 줄 복사(PO-02001b 선례 · Caleb 손 작업과 같다)
    insert into public.po_discount (po_id, seq, name, percent, supplier_discount_id, note)
    select v_b_id, d.seq, d.name, d.percent, d.supplier_discount_id, d.note from public.po_discount d where d.po_id = v_po.id;

    -- 라인 — 일부 받은 라인은 a 줄이고 b 신설 · 하나도 안 온 라인은 행을 b 로 옮긴다(인보이스 줄이 가리켜도 FK 가 따라간다)
    for x in
      select pl.*, 
             pl.qty_ea - coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0)
               - coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id), 0) as remaining
      from public.po_line pl where pl.po_id = v_po.id order by pl.line_no
    loop
      if x.remaining <= 0 then continue; end if;                                     -- 다 받았거나 초과 — a 에 그대로
      if x.qty_ea - x.remaining > 0 then
        -- 일부 받았다 — a 는 받은 만큼으로(입력 단위 셋은 비운다 · 이견 5)
        update public.po_line set qty_ea = x.qty_ea - x.remaining, entered_unit_product_id = null, entered_qty = null, entered_pack_factor = null
         where id = x.id and qty_ea = x.qty_ea;
        get diagnostics v_n = row_count;
        if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
        insert into public.po_line
        select * from jsonb_populate_record(null::public.po_line,
          to_jsonb(x) - 'remaining' || jsonb_build_object('id', gen_random_uuid(), 'po_id', v_b_id, 'qty_ea', x.remaining,
                                                          'entered_unit_product_id', null, 'entered_qty', null, 'entered_pack_factor', null,
                                                          'created_at', v_now, 'updated_at', v_now, 'updated_by', v_staff));
        v_reduced := v_reduced + 1;
        if x.entered_unit_product_id is not null then v_cleared := array_append(v_cleared, x.line_no::text); end if;
      else
        -- 하나도 안 왔다 — 행을 통째로 b 로
        update public.po_line set po_id = v_b_id where id = x.id and po_id = v_po.id;
        get diagnostics v_n = row_count;
        if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
        v_moved := v_moved + 1;
      end if;
    end loop;

    -- a — 번호에 접미사 · 닫힘(입고 종료 · §11-b)
    update public.po set po_number = v_a_num, status = 'closed', closed_at = v_now where id = v_po.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
    if cardinality(v_cleared) > 0 then v_warn := array_append(v_warn, 'entered_units_cleared'); end if;
    v_warn := array_append(v_warn, 'po_split');
  else
    -- 다 받았다(또는 초과만) — 갈라지지 않고 닫힌다
    v_a_num := v_po.po_number;
    update public.po set status = 'closed', closed_at = v_now where id = v_po.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
    v_warn := array_append(v_warn, 'po_closed');
  end if;
  if v_over > 0 then v_warn := array_append(v_warn, 'over_receipt'); end if;
  if v_short > 0 then v_warn := array_append(v_warn, 'short_receipt'); end if;

  -- ═══ ⓓ 묶음 confirmed (맨 뒤 — 어디서 터져도 아무것도 안 남는다) ═══
  update public.po_receipt set status = 'confirmed', confirmed_at = v_now, confirmed_by = v_staff
   where id = p_receipt_id and status = 'draft' and confirmed_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Receipt % was not saved — it may have been changed by someone else just now — nothing was saved', v_r.receipt_number; end if;

  -- ═══ ⓔ 원장 — 창구를 부른다 (원장 이식 2차 · 2026-09-19 · ⬜1) ═══
  -- ⭐ 같은 트랜잭션 — 원장이 실패하면 확정도 실패한다(재고에 안 잡힐 거면 확정도 하면 안 된다). inv_ledger 에 직접 쓰지 않는다(원칙 2 · §11-j).
  -- ⭐ 자리가 ⓓ 뒤인 이유 셋: ① 창구는 「확정된 입고」만 받는다(status=confirmed 를 스스로 확인 — 직접 호출로 초안이 장부에 닿는 길을 막는다)
  --   ② raw 의 po_number 는 갈라진 뒤의 번호여야 한다(§11-j) — ⓒ 가 끝나야 안다 ③ 기준은 po_line.qty_ea 가 아니라 ⓑ 가 얼려 둔 po_receipt_diff.expected_qty 에서
  --   읽으므로(§2 의 함정 — ⓒ 가 qty_ea 를 줄인다) ⓒ 뒤라도 어긋나지 않는다. 기준을 「미리 잡아 두는」 그릇이 그 표다.
  v_ledger := public.inv_post_receipt(p_receipt_id);
  if coalesce((v_ledger->>'qty_excess')::numeric, 0) > 0 then v_warn := array_append(v_warn, 'ledger_trimmed_to_basis'); end if;
  if (v_ledger->'warnings') ? 'received_on_before_baseline' then v_warn := array_append(v_warn, 'received_on_before_baseline'); end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', 'confirmed', 'confirmed_at', v_now, 'confirmed_by', v_staff,
    'receipt_lines_created', v_lines_n,
    'po', jsonb_build_object('id', v_po.id, 'number_before', v_po.po_number, 'number_after', v_a_num, 'status', 'closed', 'closed_at', v_now),
    'split', case when v_rem_total > 0 then jsonb_build_object('remainder_po_id', v_b_id, 'remainder_number', v_b_num, 'lines_reduced', v_reduced, 'lines_moved', v_moved, 'remainder_qty', v_rem_total) else null end,
    'diffs', jsonb_build_object('over', v_over, 'short', v_short, 'rows', v_rows),
    'entered_units_cleared_lines', to_jsonb(v_cleared),
    'ledger', v_ledger,                                          -- ⭐ 원장 결과(rows_posted · qty_posted · qty_excess · lines[]) — 화면이 「재고에 들어갔다」를 말할 수 있게
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ── inv_post_receipt ──
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
  if v_r.transfer_id is not null then raise exception 'Receipt % is a transfer arrival — its ledger is inv_post_transfer_arrive — nothing was posted to the ledger', v_r.receipt_number; end if;   -- tr-3a(트랜스퍼를 막는 한 줄만)
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

-- ── inv_transfer_detail ──
create or replace function public.inv_transfer_detail(p_transfer_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not public.ims_can_view('transfer') then null::jsonb else (
    select jsonb_build_object(
      'header', to_jsonb(x) || jsonb_build_object('from_warehouse', fw.name, 'to_warehouse', tw.name, 'created_by_name', cb.name, 'confirmed_by_name', fb.name),
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', p.name, 'qty', l.qty, 'qty_sent', l.qty_sent, 'short_sent', case when l.qty_sent is not null and l.qty_sent < l.qty then l.qty - l.qty_sent end, 'qty_received', l.qty_received, 'pack_factor', l.pack_factor,
                                                              'qty_ea', l.qty * l.pack_factor, 'stock_product_id', coalesce(p.parent_product_id, p.id)) order by l.line_no), '[]'::jsonb)
                  from public.inv_transfer_line l join public.product p on p.id = l.product_id where l.transfer_id = x.id),
      'shortage', case when x.status = 'draft' then public.inv_transfer_shortage(x.id) else '[]'::jsonb end)
      from public.inv_transfer x
      join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = x.to_warehouse_id
      left join public.ims_staff cb on cb.id = x.created_by left join public.ims_staff fb on fb.id = x.confirmed_by
     where x.id = p_transfer_id) end;
$$;

-- ── inv_layer_apply ──
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
  v_ims_kind    text;                                                                     -- trf-a 2026-09-28 raw.kind — 'bin_move' = 같은 창고 칸 옮기기(레이어는 창고 단위라 할 일이 없다)
  v_bin_moves   int := 0;                                                                 -- trf-a 지나간 칸 옮기기 행 수(out · in 둘 다 센다 · 반환 ims.bin_moves_passed)
  v_ims_wh      text;                                                                     -- tr-2 2026-09-28 창고(IN_TRANSIT 갈래)
  v_ims_trd     int := 0;   v_ims_trd_layers int := 0;   v_ims_trd_rows int := 0;   v_ims_trd_short numeric := 0;   v_ims_trd_skipped int := 0;   v_ims_trd_out int := 0;   -- tr-2 출발 창구 inv_layer_apply_transfer_depart_ims 의 반환 합
  v_ims_tra     int := 0;   v_ims_tra_layers int := 0;   v_ims_tra_rows int := 0;   v_ims_tra_short numeric := 0;   v_ims_tra_skipped int := 0;                            -- tr-3a 도착 창구 inv_layer_apply_transfer_arrive_ims 의 반환 합
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
    if r.event_type not in ('po_in', 'sale_out', 'credit_in', 'adjust_existing', 'adjust_new') then   -- adj-a 2026-09-28: 조정 둘도 아래 갈래가 source 로 가른다(IMS → inv_layer_apply_adjust_ims) · ⓒ1 2026-09-25: credit_in 은 아래 갈래가 source 로 가른다(IMS → 창구 inv_layer_apply_credit_ims · 문에서 세지 않는다 · skipped_by_event.credit_in 은 늘 0)
      select source, raw ->> 'kind', warehouse into v_ims_src, v_ims_kind, v_ims_wh from inv_ledger where id = r.id;   -- trf-a: kind 도 함께(조회 한 번 그대로) · tr-2: warehouse 도
      if v_ims_src = 'ims' and v_ims_kind = 'bin_move' and r.event_type in ('transfer_in', 'transfer_out') then   -- trf-a 2026-09-28 칸 옮기기(같은 창고 · inv_post_move) — 레이어는 (sku, warehouse) 단위라 할 일이 없다 · 세지 않고 지나간다(실시간 창구도 레이어를 부르지 않는다 = 같은 결과) · 창고 간 문서는 kind 가 다르다(뒤 차수의 갈래)
        v_bin_moves := v_bin_moves + 1;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and r.event_type = 'transfer_out' then     -- tr-2 2026-09-28 창고 간 트랜스퍼 출발 out(출발 창고) — IN_TRANSIT in 이 처리한다(불러온 축과 같은 결) · 세고 지나간다
        v_ims_trd_out := v_ims_trd_out + 1;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and r.event_type = 'transfer_in' and v_ims_wh = 'IN_TRANSIT' then   -- tr-2 출발 IN_TRANSIT in → 창구(inv_layer_post_transfer_depart · 실시간과 같은 함수) · (doc, sku) 한 번 · 도착 창고 in 은 ④(지금은 문이 센다)
        begin
          v_ims_j := inv_layer_apply_transfer_depart_ims(r.id);
          if (v_ims_j ->> 'processed')::boolean then
            v_ims_trd        := v_ims_trd + 1;
            v_ims_trd_layers := v_ims_trd_layers + coalesce((v_ims_j ->> 'layers')::int, 0);
            v_ims_trd_rows   := v_ims_trd_rows   + coalesce((v_ims_j ->> 'consume_rows')::int, 0);
            v_ims_trd_short  := v_ims_trd_short  + coalesce((v_ims_j ->> 'short_qty')::numeric, 0);
          end if;
        exception when others then
          v_ims_trd_skipped := v_ims_trd_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'transfer_depart', 'number', (select doc_number from inv_ledger where id = r.id), 'id', r.id, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and r.event_type = 'transfer_in' and v_ims_wh <> 'IN_TRANSIT' then   -- tr-3a 도착 창고 in(leg 4) → 창구(inv_layer_post_transfer_arrive · IN_TRANSIT 문서 범위 FIFO · 실시간과 같은 함수) · (doc, receipt, sku) 한 번 · leg 3 out 은 위 out 갈래가 센다
        begin
          v_ims_j := inv_layer_apply_transfer_arrive_ims(r.id);
          if (v_ims_j ->> 'processed')::boolean then
            v_ims_tra        := v_ims_tra + 1;
            v_ims_tra_layers := v_ims_tra_layers + coalesce((v_ims_j ->> 'layers')::int, 0);
            v_ims_tra_rows   := v_ims_tra_rows   + coalesce((v_ims_j ->> 'consume_rows')::int, 0);
            v_ims_tra_short  := v_ims_tra_short  + coalesce((v_ims_j ->> 'short_qty')::numeric, 0);
          end if;
        exception when others then
          v_ims_tra_skipped := v_ims_tra_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'transfer_arrive', 'number', (select doc_number from inv_ledger where id = r.id), 'id', r.id, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
        continue;
      end if;
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
      -- adj-a 2026-09-28: IMS 축(source ims)은 창구(inv_layer_post_adjust)로 · Cin7 축은 종전 inv_layer_apply_adjust — 같은 반환 모양(credit_in 갈래와 같은 식)
      select source into v_ims_src from inv_ledger where id = r.id;
      if v_ims_src = 'ims' then
        select * into v_layers, v_rows, v_short, v_unk, v_nz, v_proc from inv_layer_apply_adjust_ims(r.id, p_until);
      else
        select * into v_layers, v_rows, v_short, v_unk, v_nz, v_proc from inv_layer_apply_adjust(r.id, p_until);
      end if;
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
      'bin_moves_passed',          v_bin_moves,             -- ⭐ trf-a 2026-09-28 raw.kind bin_move 인 칸 옮기기 행 수 — 창구가 있으니 skipped_by_event 의 transfer 두 키에 안 잡힌다(0 이 정상)
      'transfer_departs_posted',   v_ims_trd,               -- ⭐ tr-2 2026-09-28 raw.kind transfer 출발(doc × sku 키) — 창구가 레이어를 만든 수
      'transfer_depart_layers',    v_ims_trd_layers,        -- IN_TRANSIT 레이어 수
      'transfer_depart_consume_rows', v_ims_trd_rows,       -- 출발 창고 소진 행 수
      'transfer_depart_short_qty', v_ims_trd_short,         -- 출발 창고 레이어가 모자란 EA(불러온 축과 같이 short · 레이어 없음)
      'transfer_departs_skipped',  v_ims_trd_skipped,       -- ⚠️ 창구가 거부해 건너뛴 수 — skip_reasons kind 'transfer_depart'
      'transfer_out_passed',       v_ims_trd_out,           -- 출발 out 행 수(leg 1 · tr-3a 부터 도착 leg 3 IN_TRANSIT out 도 여기) — skipped_by_event.transfer_out 에 안 잡힌다
      'transfer_arrivals_posted',  v_ims_tra,               -- ⭐ tr-3a 도착(doc × receipt × sku 키) — 창구가 레이어를 만든 수
      'transfer_arrive_layers',    v_ims_tra_layers,        -- 도착 창고 레이어 수
      'transfer_arrive_consume_rows', v_ims_tra_rows,       -- IN_TRANSIT 소진 행 수(문서 범위)
      'transfer_arrive_short_qty', v_ims_tra_short,         -- IN_TRANSIT 문서 레이어가 모자란 EA(불러온 축과 같이 short)
      'transfer_arrivals_skipped', v_ims_tra_skipped,       -- ⚠️ 창구가 거부해 건너뛴 수 — skip_reasons kind 'transfer_arrive'
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
  recv_nc as (                                                           -- ⑤-6b 창고 Complete 뒤 24h 넘게 오피스 확정이 없다(여전히 draft) · tr-3a: 트랜스퍼 입고(po_id null)는 Complete = 확정이라 여기 안 든다(join po 가 거른다 · 판정 70)
    select r.receipt_number, p.po_number, c.completed_at, c.completed_by
      from public.wms_receipt_complete c
      join public.po_receipt r on r.id = c.receipt_id
      join public.po p on p.id = r.po_id
     where c.completed and r.status = 'draft' and c.completed_at < now() - c_stale
  ),
  recv_stale as (                                                        -- ⑤-6b 초안인데 작업 줄 0 · 만든 지 24h 넘음(열어 두고 아무것도 안 셈) · tr-3a: 트랜스퍼 입고도 든다(번호는 TRF)
    select r.receipt_number, coalesce(p.po_number, x.transfer_number) as po_number, r.created_at, r.created_by
      from public.po_receipt r
      left join public.po p on p.id = r.po_id
      left join public.inv_transfer x on x.id = r.transfer_id
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
  trf_nl as (                                                            -- tr-2 2026-09-28 떠난 트랜스퍼(in_transit 부터)인데 출발 원장 짝(출발 창고 transfer_out · IN_TRANSIT transfer_in)이 없다 — 창고 마무리 트랜잭션이 끊겼다
    select x.transfer_number, x.status, x.departed_at, fw.name as from_warehouse,
           (select count(*) from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_out' and e.warehouse = fw.name) as out_rows,
           (select count(*) from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_in' and e.warehouse = 'IN_TRANSIT') as transit_rows
      from public.inv_transfer x join public.ref_warehouse fw on fw.id = x.from_warehouse_id
     where x.status in ('in_transit', 'receiving', 'received') and x.departed_at is not null
       and (not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_out' and e.warehouse = fw.name)
            or not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_in' and e.warehouse = 'IN_TRANSIT'))
  ),
  trf_rnl as (                                                           -- tr-3a 받은 트랜스퍼(received)인데 도착 원장(도착 창고 transfer_in · 그 입고)이 없다 — Complete 트랜잭션이 끊겼다
    select x.transfer_number, r.receipt_number, x.received_at, tw.name as to_warehouse
      from public.inv_transfer x join public.ref_warehouse tw on tw.id = x.to_warehouse_id
      join public.po_receipt r on r.transfer_id = x.id and r.status = 'confirmed'
     where x.status = 'received'
       and not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_in'
                         and e.warehouse = tw.name and e.raw -> 'header' ->> 'receipt_number' = r.receipt_number)
  ),
  trf_old as (                                                           -- tr-3a 묶음 10 의 8: 떠난 지 30일이 넘었는데 운송 중에 남은 몫(IN_TRANSIT 잔고 > 0 · 다 못 받았거나 아직 안 받았다) — 매니저 정리(분실 / 되돌리기)
    select x.transfer_number, x.status, x.departed_at, s.remaining_ea
      from public.inv_transfer x
      join (select e.doc_number, sum(e.qty_delta) as remaining_ea from public.inv_ledger e where e.doc_type = 'transfer' and e.source = 'ims' and e.warehouse = 'IN_TRANSIT' group by e.doc_number) s on s.doc_number = x.transfer_number
     where x.departed_at < now() - interval '30 days' and s.remaining_ea > 0
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
  select 178, 'transfer_departed_no_ledger', 'critical', 'Departed transfer without departure ledger rows',
    'A transfer that has left the warehouse (in transit or later) has no departure pair in the ledger (transfer_out at the from warehouse plus transfer_in at IN_TRANSIT) - the finalize transaction was interrupted between the document and the ledger. Stock at the from warehouse and in transit is wrong until inv_post_transfer_depart is run by the DB owner.',
    (select count(*) from trf_nl), (select jsonb_agg(t) from (select * from trf_nl limit 8) t)
  union all
  select 179, 'transfer_received_no_ledger', 'critical', 'Received transfer without arrival ledger rows',
    'A transfer marked received has a confirmed arrival receipt but no arrival rows in the ledger (transfer_in at the receiving warehouse for that receipt) - the Complete transaction was interrupted between the receipt and the ledger. Stock at the receiving warehouse and in transit is wrong until inv_post_transfer_arrive is run by the DB owner.',
    (select count(*) from trf_rnl), (select jsonb_agg(t) from (select * from trf_rnl limit 8) t)
  union all
  select 176, 'transfer_in_transit_30d', 'warn', 'Transfer stock still in transit after 30 days',
    'A transfer left the sending warehouse more than 30 days ago and part of it is still in transit (not received, or received short). Settle it: mark the missing units lost or return them to the sending warehouse (in-transit settlement).',
    (select count(*) from trf_old), (select jsonb_agg(t) from (select * from trf_old limit 8) t)
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
