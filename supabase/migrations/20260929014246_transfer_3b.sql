-- ─────────────────────────────────────────────────────────────
-- 재고 사건 ② 트랜스퍼 · 둘째 몫 「창고 간」 ④-2 운송 중 정리(분실 · 되돌리기) · 더 온 몫 결정 (Asung-IMS · tr-3b · 2026-09-28)
--   정본(뒤에 적는다): so-module §27(판정 68 · 75 · 76 · 묶음 아홉 2 · 열 5) · tr-1a ~ tr-3a 위에 선다
--   든 것: ① inv_transfer_settle(정리 기록 · 줄마다 lost/return · 칸 · 사람 · 시각 · 짝 차이 행) · inv_transfer_line.qty_lost · qty_returned · 차이 행 resolution 에 lost · returned · sent_more · found · inv_layer_consume reason 에 lost
--         ② tf_settle(문서 · 줄마다 {line_id, action lost|return, qty EA, bin_id|bin}) — 문 = ims_can_adjust(판정 75) + 창고(lost = 출발 또는 도착 · return = 출발) · 최대 = 그 줄의 IN_TRANSIT 잔고(원장) · lost = IN_TRANSIT transfer_out −EA(leg lost) + 문서 레이어 FIFO 소진(reason lost · 레이어 없음 = 가치 소멸)
--            return = IN_TRANSIT transfer_out −EA(leg return_out) + 출발 칸 transfer_in +EA(leg return_in) + 문서 레이어 FIFO → 출발 창고 레이어(parent · 같은 원가 · 나이) · 줄의 잔고가 0 이 되면 short 차이 행을 닫는다(lost | returned) · 문서 상태는 그대로(in_transit · receiving · received 어디서든 · 전량 정리 뒤에도 상태 무변 · Health 30일은 잔고 0 이라 사라진다)
--         ③ tf_over_decide(over 차이 행 · choice sent_more|found · from_bin · note) — 문 = ims_can_adjust(판정 76) + 창고(sent_more = 출발 · found = 도착) · 한 번만(resolved_at)
--            sent_more = 출발 칸 −N(leg over_1) · IN_TRANSIT +N(over_2) · IN_TRANSIT −N(over_3) · 도착 칸 +N(over_4 · 입고 때 놓은 칸 중 가장 많이 놓은 칸) · 원가 = 출발 창고 FIFO → 도착 창고 레이어(IN_TRANSIT 층은 같은 날 ±N 이라 건너뛴다) · 출발 칸 선반 기대량(장부 − P) 을 넘으면 거부 · 줄 qty_extra 에 +N(qty_sent · qty_received 는 요청 상한 CHECK 그대로)
--            found = 도착 창고 조정 문서(inv_adjust_create → line_set(delta +N · reason found · 놓은 칸 · 메모 TRF-n over) → confirm) — 조정 창구를 부르기만 · 원가는 조정 규칙(layer_avg · 없으면 unknown 0 · 반환 warnings) · 차이 행에 ADJ 번호
--         ④ inv_layer_post_transfer_settle(레이어 창구 · lost/return/sent_more 한 손) · inv_layer_apply_transfer_settle_ims(재생성 갈래 · 행마다 · done 키 = line_ref) · inv_layer_apply 재발행(lost · return_in · over_4 → 정리 창구 · over_2 는 세고 지나감 · 반환 ims 여섯 키) · depart/arrive 도우미는 leg 2 · 4 만 합친다(over 행이 섞이지 않게)
--         ⑤ Health transfer_over_undecided(177 · warn) · inv_transfer_detail 줄에 qty_lost · qty_returned
--   ⭐ 약속: PO 입고 · 판매 · 조정 동작 무변(조정 창구는 부르기만) · 가치를 바꾸는 창구 둘은 ims_can_adjust 로만 · 운임은 ⑤
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 판매 표 · 행 무접촉 · IMS 안에서만 선다(판정 51 · 60)
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

-- ═══ 1) 표 · 어휘 ═══
alter table public.inv_transfer_line add column qty_lost numeric not null default 0;
alter table public.inv_transfer_line add column qty_returned numeric not null default 0;
alter table public.inv_transfer_line add column qty_extra numeric not null default 0;
alter table public.inv_transfer_line add constraint inv_transfer_line_settle_ck check (qty_lost >= 0 and qty_returned >= 0 and qty_extra >= 0);
comment on column public.inv_transfer_line.qty_lost is 'tr-3b(판정 68 · 75) — 운송 중에서 분실로 정리한 수량(판매 단위 · 누적 · tf_settle lost)';
comment on column public.inv_transfer_line.qty_returned is 'tr-3b(판정 68 · 75) — 운송 중에서 출발 창고로 되돌린 수량(판매 단위 · 누적 · tf_settle return)';
comment on column public.inv_transfer_line.qty_extra is 'tr-3b(판정 76) — 더 온 몫을 「출발에서 더 보낸 것」으로 결정한 수량(판매 단위 · tf_over_decide sent_more) · qty_sent · qty_received 는 요청 상한(CHECK)이라 그대로 두고 여기 더한다 · found 는 조정 문서라 0';
create table public.inv_transfer_settle (
  id                uuid primary key default gen_random_uuid(),
  transfer_id       uuid not null references public.inv_transfer (id) on delete restrict,
  transfer_line_id  uuid not null references public.inv_transfer_line (id) on delete restrict,
  action            text not null check (action in ('lost', 'return')),
  qty_ea            numeric not null check (qty_ea > 0),
  bin_id            uuid references public.ref_bin (id) on delete restrict,                -- return: 출발 창고 칸
  bin               text,
  diff_id           uuid references public.po_receipt_diff (id) on delete set null,       -- 짝 = 모자람(short) 차이 행(있으면 · 도착 전 정리는 없다)
  note              text,
  settled_by        uuid not null references public.ims_staff (id) on delete restrict,
  settled_at        timestamptz not null default now(),
  constraint inv_transfer_settle_return_bin_ck check ((action = 'return') = (bin_id is not null))
);
create index inv_transfer_settle_transfer_idx on public.inv_transfer_settle (transfer_id);
create index inv_transfer_settle_line_idx on public.inv_transfer_settle (transfer_line_id);
alter table public.inv_transfer_settle enable row level security;
create policy inv_transfer_settle_select on public.inv_transfer_settle for select to authenticated
  using (public.ims_can_view('transfer') or public.ims_can_view('picking') or public.ims_can_view('packing') or public.ims_can_view('fulfillment') or public.ims_can_view('wms_manage') or public.ims_can_view('wms_receiving'));
revoke all on public.inv_transfer_settle from public, anon;
grant select on public.inv_transfer_settle to authenticated;                              -- 쓰기는 창구(definer)만
comment on table public.inv_transfer_settle is 'tr-3b(판정 68 · 75 · 묶음 아홉 2) — 운송 중 정리 기록: 줄마다 lost(운송 중에서 빼고 그 문서 원가 몫 소진) 또는 return(출발 창고 칸으로 · 원가 층 따라감) · EA · 칸 · 사람 · 시각 · 짝 차이 행 · 원장 line_ref = 줄:settle:이 id';
alter table public.po_receipt_diff drop constraint po_receipt_diff_resolution_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_resolution_ck check (resolution is null or resolution in ('split_shipment', 'out_of_stock', 'lost_damaged', 'miscount', 'other', 'free', 'billed', 'credited', 'accepted_free', 'accepted_billed', 'rejected', 'lost', 'returned', 'sent_more', 'found'));
alter table public.po_receipt_diff drop constraint po_receipt_diff_resolution_kind_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_resolution_kind_ck check (resolution is null
  or (kind = 'short' and resolution in ('split_shipment', 'out_of_stock', 'lost_damaged', 'miscount', 'other', 'lost', 'returned'))
  or (kind = 'over' and resolution in ('free', 'billed', 'credited', 'sent_more', 'found'))
  or (kind = 'off_po' and resolution in ('accepted_free', 'accepted_billed', 'rejected')));   -- tr-3b: 트랜스퍼 짝(short → lost · returned / over → sent_more · found) 만 더했다 · PO 어휘 그대로
alter table public.inv_layer_consume drop constraint inv_layer_consume_reason_ck;
alter table public.inv_layer_consume add constraint inv_layer_consume_reason_ck check (reason in ('sale', 'transfer', 'adjust_out', 'assembly_in', 'reversal', 'lost'));   -- tr-3b: lost = 운송 중 분실(가치 소멸이 그대로 읽힌다)

-- ═══ 2) 레이어 창구 — 정리 · 더 온 몫 한 손(멱등 = line_ref) ═══
create function public.inv_layer_post_transfer_settle(p_doc_number text, p_line_ref text, p_sku text, p_qty numeric, p_action text, p_dest_warehouse text, p_occurred_on date, p_from_warehouse text default null, p_hint jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_layer_post_transfer_settle@2026-09-28.1';
        v_rows int; v_short int; v_layers int; v_taken numeric; v_amt numeric; v_src text; v_reason text; v_scope text;
begin
  if p_qty is null or p_qty <= 0 then return jsonb_build_object('qty', p_qty, 'branch', 'none', 'builder', c_version); end if;
  if p_action not in ('lost', 'return', 'sent_more') then raise exception 'inv_layer_post_transfer_settle: unknown action %', p_action; end if;
  if exists (select 1 from public.inv_layer_consume c where c.doc_type = 'transfer' and c.doc_number = p_doc_number and c.line_ref = p_line_ref) then
    raise exception 'Transfer % settlement % was already costed — nothing was saved', p_doc_number, p_line_ref;
  end if;
  if p_action = 'sent_more' then
    if p_from_warehouse is null or p_dest_warehouse is null then raise exception 'sent_more needs the from and to warehouses'; end if;
    v_src := p_from_warehouse; v_reason := 'transfer'; v_scope := null;                     -- 출발 창고 FIFO → 도착 창고 레이어(IN_TRANSIT 층은 같은 날 ±N · 건너뛴다)
  else
    v_src := 'IN_TRANSIT'; v_reason := case when p_action = 'lost' then 'lost' else 'transfer' end; v_scope := p_doc_number;   -- 그 문서의 IN_TRANSIT 층만
  end if;
  select * into v_rows, v_short, v_layers, v_taken
    from public.inv_layer_fifo_take(p_sku, v_src, p_qty, 'transfer', p_doc_number, p_line_ref, 'transfer_out', p_occurred_on, v_reason, case when p_action = 'lost' then null else p_dest_warehouse end, v_scope);
  select coalesce(sum(c.amount), 0) into v_amt from public.inv_layer_consume c where c.doc_type = 'transfer' and c.doc_number = p_doc_number and c.line_ref = p_line_ref;
  return jsonb_build_object('action', p_action, 'sku', p_sku, 'from', v_src, 'to', case when p_action = 'lost' then null else p_dest_warehouse end, 'qty', p_qty, 'line_ref', p_line_ref,
                            'taken', coalesce(v_taken, 0), 'consume_rows', coalesce(v_rows, 0), 'layers', coalesce(v_layers, 0), 'short', coalesce(v_short, 0), 'short_qty', p_qty - coalesce(v_taken, 0),
                            'amount', v_amt, 'reproduced', p_hint is not null, 'builder', c_version);
end;
$$;
comment on function public.inv_layer_post_transfer_settle(text, text, text, numeric, text, text, date, text, jsonb) is 'tr-3b(판정 68 · 75 · 76) — 운송 중 정리 · 더 온 몫의 원가 한 손: lost = 그 문서의 IN_TRANSIT 층 FIFO 소진(reason lost · 레이어 없음) · return = 같은 소진 → 출발 창고 레이어(parent) · sent_more = 출발 창고 FIFO → 도착 창고 레이어 · 멱등 = line_ref · 실시간(tf_settle · tf_over_decide)과 재생성(inv_layer_apply_transfer_settle_ims)이 같은 함수';
revoke all on function public.inv_layer_post_transfer_settle(text, text, text, numeric, text, text, date, text, jsonb) from public, anon, authenticated;

-- ═══ 3) 재생성 갈래 — lost · return_in · over_4 행마다(line_ref 가 곧 키) ═══
create function public.inv_layer_apply_transfer_settle_ims(p_ledger_id bigint) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare r public.inv_ledger%rowtype; v_leg text; v_action text; v_from text; v_res jsonb;
begin
  select * into r from public.inv_ledger where id = p_ledger_id;
  if not found or r.source <> 'ims' or (r.raw ->> 'kind') is distinct from 'transfer' then return jsonb_build_object('processed', false, 'reason', 'not an ims transfer row'); end if;
  v_leg := r.raw ->> 'leg';
  if v_leg not in ('lost', 'return_in', 'over_4') then return jsonb_build_object('processed', false, 'reason', 'not a settlement row'); end if;
  if exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_trs' and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = r.line_ref) then
    return jsonb_build_object('processed', false, 'reason', 'done');
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_trs', r.doc_number, r.sku, r.line_ref);   -- 키 = (문서, SKU, line_ref) · warehouse 칸에 line_ref(not null 칸 재사용)
  v_action := case v_leg when 'lost' then 'lost' when 'return_in' then 'return' else 'sent_more' end;
  v_from := r.raw -> 'header' ->> 'from_warehouse';
  v_res := public.inv_layer_post_transfer_settle(r.doc_number, r.line_ref, r.sku, abs(r.qty_delta), v_action, case when v_leg = 'lost' then null else r.warehouse end, r.occurred_on, v_from, r.raw -> 'cost');
  return v_res || jsonb_build_object('processed', true);
end;
$$;
comment on function public.inv_layer_apply_transfer_settle_ims(bigint) is 'tr-3b — inv_layer_apply 의 정리 · 더 온 몫 갈래(raw.leg lost · return_in · over_4 행에서 · 행마다 한 번 · done 키 ims_trs(문서, SKU, line_ref)) · 창구 inv_layer_post_transfer_settle 를 실시간과 같은 값으로 부른다';
revoke all on function public.inv_layer_apply_transfer_settle_ims(bigint) from public, anon, authenticated;

-- ═══ 4) tf_settle — 운송 중 정리(판정 68 · 75 · 묶음 아홉 2) ═══
create function public.tf_settle(p_transfer_id uuid, p_lines jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'tf_settle@2026-09-28.1';
        v_staff uuid; v_x public.inv_transfer%rowtype; v_fw text; v_tw text; v_on date; v_e jsonb; v_l public.inv_transfer_line%rowtype; v_action text; v_qty numeric; v_bin public.ref_bin%rowtype;
        v_base text; v_rem numeric; v_sid uuid; v_lref text; v_cost jsonb; v_hdr jsonb; v_out jsonb := '[]'::jsonb; v_closed int := 0; v_d public.po_receipt_diff%rowtype; v_n int;
        v_lost_tot numeric := 0; v_ret_tot numeric := 0;
begin
  if not public.ims_can_adjust() then raise exception 'You cannot settle stock in transit — this needs the stock_adjust key (admin, or a supervisor or manager with the key switched on) — nothing was saved'; end if;   -- ⭐ 첫 줄 문(판정 75)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;                 -- 문서 잠금 — 같은 문서 두 정리는 줄을 선다(잔고는 잠근 뒤 읽는다)
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  if v_x.status not in ('in_transit', 'receiving', 'received') then raise exception 'Transfer % is % — only stock that has left the sending warehouse can be settled — nothing was saved', v_x.transfer_number, v_x.status; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'p_lines must be a JSON array of {line_id, action lost|return, qty, bin_id|bin (return)} — nothing was saved'; end if;
  select w.name into v_fw from public.ref_warehouse w where w.id = v_x.from_warehouse_id;
  select w.name into v_tw from public.ref_warehouse w where w.id = v_x.to_warehouse_id;
  v_on := public.ims_today();
  for v_e in select * from jsonb_array_elements(p_lines) loop
    v_action := lower(trim(v_e ->> 'action'));
    if v_action not in ('lost', 'return') then raise exception 'action must be lost or return — nothing was saved'; end if;
    if (v_e ->> 'qty') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' or (v_e ->> 'qty')::numeric <= 0 then raise exception 'qty must be a positive number of units (EA) — nothing was saved'; end if;
    v_qty := (v_e ->> 'qty')::numeric;
    select * into v_l from public.inv_transfer_line l where l.id = (v_e ->> 'line_id')::uuid and l.transfer_id = v_x.id;
    if not found then raise exception 'Line % is not on transfer % — nothing was saved', v_e ->> 'line_id', v_x.transfer_number; end if;
    -- 창고 권한 — lost 는 출발 또는 도착 어느 쪽 사람이든(분실은 양쪽이 안다) · return 은 출발 창고(물건이 그 칸으로 돌아온다)
    if v_action = 'return' then
      if not public.ims_can_warehouse(v_x.from_warehouse_id) then raise exception 'Transfer % returns to a warehouse you are not set up for — nothing was saved', v_x.transfer_number; end if;
      if nullif(v_e ->> 'bin_id', '') is not null then select * into v_bin from public.ref_bin b where b.id = (v_e ->> 'bin_id')::uuid;
      else select * into v_bin from public.ref_bin b where b.warehouse_id = v_x.from_warehouse_id and b.name = trim(v_e ->> 'bin'); end if;
      if not found or v_bin.warehouse_id <> v_x.from_warehouse_id or not v_bin.is_active or v_bin.name = '' then raise exception 'Bin % is not an active bin at % — nothing was saved', coalesce(v_e ->> 'bin', v_e ->> 'bin_id', '?'), v_fw; end if;
    else
      if not (public.ims_can_warehouse(v_x.from_warehouse_id) or public.ims_can_warehouse(v_x.to_warehouse_id)) then raise exception 'Transfer % is between warehouses you are not set up for — nothing was saved', v_x.transfer_number; end if;
      v_bin := null;
    end if;
    select coalesce(pp.sku, pr.sku) into v_base from public.product pr left join public.product pp on pp.id = pr.parent_product_id where pr.id = v_l.product_id;
    -- 최대 = 그 줄의 IN_TRANSIT 잔고(원장 · leg 2 + · leg 3 − · 앞선 정리 − · over_2/3 ±)
    select coalesce(sum(e.qty_delta), 0) into v_rem from public.inv_ledger e
     where e.doc_type = 'transfer' and e.doc_number = v_x.transfer_number and e.source = 'ims' and e.warehouse = 'IN_TRANSIT' and e.sku = v_base
       and (e.line_ref = v_l.id::text or e.line_ref like v_l.id::text || ':%');
    if v_rem <= 0 then raise exception 'Line % of transfer % has nothing in transit — nothing to settle — nothing was saved', v_l.line_no, v_x.transfer_number; end if;
    if v_qty > v_rem then raise exception 'Line % of transfer %: % in transit, cannot settle % — nothing was saved', v_l.line_no, v_x.transfer_number, v_rem, v_qty; end if;
    insert into public.inv_transfer_settle (transfer_id, transfer_line_id, action, qty_ea, bin_id, bin, note, settled_by)
    values (v_x.id, v_l.id, v_action, v_qty, v_bin.id, v_bin.name, nullif(trim(v_e ->> 'note'), ''), v_staff) returning id into v_sid;
    v_lref := v_l.id::text || ':settle:' || v_sid::text;
    v_cost := public.inv_layer_post_transfer_settle(v_x.transfer_number, v_lref, v_base, v_qty, v_action, v_fw, v_on, null, null);
    v_hdr := jsonb_build_object('transfer_number', v_x.transfer_number, 'from_warehouse_id', v_x.from_warehouse_id, 'from_warehouse', v_fw, 'to_warehouse_id', v_x.to_warehouse_id, 'to_warehouse', v_tw,
                                'settle_id', v_sid, 'action', v_action, 'settled_on', v_on, 'settled_by', v_staff, 'in_transit_before', v_rem, 'note', nullif(trim(v_e ->> 'note'), ''));
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_on, 2, v_base, 'IN_TRANSIT', '', -v_qty, 'transfer_out', 'transfer', v_x.transfer_number, v_x.id::text, v_lref, null, 'ims',
            jsonb_build_object('kind', 'transfer', 'leg', case when v_action = 'lost' then 'lost' else 'return_out' end, 'poster', c_version, 'header', v_hdr,
              'line', jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'product_id', v_l.product_id, 'sku', v_l.sku, 'base_sku', v_base, 'pack_factor', v_l.pack_factor, 'qty_ea', v_qty),
              'rule', case when v_action = 'lost' then format('transfer %s → %s lost in transit: −%s EA out of IN_TRANSIT · its cost share consumed (reason lost) · nothing arrives', v_fw, v_tw, v_qty)
                           else format('transfer %s → %s returned to sender: −%s EA out of IN_TRANSIT (goes back into %s / %s)', v_fw, v_tw, v_qty, v_fw, v_bin.name) end,
              'cost', v_cost));
    if v_action = 'return' then
      insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
      values (v_on, 1, v_base, v_fw, v_bin.name, v_qty, 'transfer_in', 'transfer', v_x.transfer_number, v_x.id::text, v_lref, null, 'ims',
              jsonb_build_object('kind', 'transfer', 'leg', 'return_in', 'poster', c_version, 'header', v_hdr,
                'line', jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'product_id', v_l.product_id, 'sku', v_l.sku, 'base_sku', v_base, 'pack_factor', v_l.pack_factor, 'bin_id', v_bin.id, 'bin', v_bin.name, 'qty_ea', v_qty),
                'rule', format('transfer %s → %s returned to sender: +%s EA into %s / %s (cost layers follow from the transit layers of this document)', v_fw, v_tw, v_qty, v_fw, v_bin.name),
                'cost', v_cost));
    end if;
    update public.inv_transfer_line set qty_lost = qty_lost + case when v_action = 'lost' then v_qty / v_l.pack_factor else 0 end, qty_returned = qty_returned + case when v_action = 'return' then v_qty / v_l.pack_factor else 0 end, updated_by = v_staff where id = v_l.id;
    if v_action = 'lost' then v_lost_tot := v_lost_tot + v_qty; else v_ret_tot := v_ret_tot + v_qty; end if;
    -- 짝: 모자람(short) 차이 행(있으면) — 줄의 잔고가 0 이 되면 닫는다(lost | returned · 둘 다면 lost · 메모에 둘 다)
    select * into v_d from public.po_receipt_diff d where d.transfer_line_id = v_l.id and d.kind = 'short' and d.resolved_at is null order by d.created_at limit 1;
    if found then
      update public.inv_transfer_settle set diff_id = v_d.id where id = v_sid;
      if v_rem - v_qty = 0 then
        update public.po_receipt_diff set resolution = case when (select coalesce(sum(s.qty_ea), 0) from public.inv_transfer_settle s where s.transfer_line_id = v_l.id and s.action = 'lost') > 0 then 'lost' else 'returned' end,
               resolved_by = v_staff, resolved_at = now(), updated_by = v_staff,
               resolution_note = format('settled in transit: lost %s EA · returned %s EA', (select coalesce(sum(s.qty_ea), 0) from public.inv_transfer_settle s where s.transfer_line_id = v_l.id and s.action = 'lost'), (select coalesce(sum(s.qty_ea), 0) from public.inv_transfer_settle s where s.transfer_line_id = v_l.id and s.action = 'return'))
         where id = v_d.id;
        v_closed := v_closed + 1;
      end if;
    end if;
    v_out := v_out || jsonb_build_object('settle_id', v_sid, 'line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'action', v_action, 'qty_ea', v_qty, 'bin', v_bin.name,
                                         'in_transit_before', v_rem, 'in_transit_after', v_rem - v_qty, 'diff_id', v_d.id, 'diff_closed', (v_d.id is not null and v_rem - v_qty = 0), 'cost', v_cost);
    v_d := null;
  end loop;
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'status', v_x.status, 'settled_on', v_on, 'settled_by', v_staff,
                            'lost_ea', v_lost_tot, 'returned_ea', v_ret_tot, 'diffs_closed', v_closed, 'lines', v_out, 'poster', c_version);
exception when unique_violation then
  raise exception 'Transfer % — a ledger row with the same key already exists (%) — nothing was saved', v_x.transfer_number, sqlerrm;
end;
$$;
comment on function public.tf_settle(uuid, jsonb) is 'tr-3b(판정 68 · 75 · 묶음 아홉 2 · 열 5) — 운송 중 정리: 줄마다 lost(IN_TRANSIT −EA · 문서 원가 몫 소진 · 가치 소멸) 또는 return(IN_TRANSIT −EA · 출발 칸 +EA · 원가 층 따라감) · 문 = ims_can_adjust + 창고(lost 양쪽 · return 출발) · 최대 = 그 줄의 IN_TRANSIT 잔고 · 문서 상태 무변 · 잔고 0 이면 short 차이 행을 닫는다 · 기록 inv_transfer_settle';
revoke all on function public.tf_settle(uuid, jsonb) from public, anon;
grant execute on function public.tf_settle(uuid, jsonb) to authenticated;

-- ═══ 5) tf_over_decide — 더 온 몫 결정(판정 76) ═══
create function public.tf_over_decide(p_diff_id uuid, p_choice text, p_from_bin uuid default null, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'tf_over_decide@2026-09-28.1';
        v_staff uuid; v_d public.po_receipt_diff%rowtype; v_x public.inv_transfer%rowtype; v_l public.inv_transfer_line%rowtype; v_r public.po_receipt%rowtype; v_fw text; v_tw text; v_on date; v_n numeric; v_base text; v_pid uuid;
        v_fbin public.ref_bin%rowtype; v_tbin public.ref_bin%rowtype; v_shelf numeric; v_lref text; v_cost jsonb; v_hdr jsonb; v_adj jsonb; v_adj_id uuid; v_line jsonb; v_conf jsonb; v_warn text[] := '{}'; v_cnt int;
begin
  if not public.ims_can_adjust() then raise exception 'You cannot decide an over-receipt — this needs the stock_adjust key (admin, or a supervisor or manager with the key switched on) — nothing was saved'; end if;   -- ⭐ 첫 줄 문(판정 76)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if p_choice not in ('sent_more', 'found') then raise exception 'p_choice must be sent_more (the sending warehouse sent more) or found (the receiving warehouse found them) — nothing was saved'; end if;
  select * into v_d from public.po_receipt_diff d where d.id = p_diff_id for update;
  if not found then raise exception 'Difference row not found — nothing was saved'; end if;
  if v_d.kind <> 'over' or v_d.transfer_id is null or v_d.transfer_line_id is null then raise exception 'Difference row % is not a transfer over-receipt — nothing was saved', p_diff_id; end if;
  if v_d.resolved_at is not null then raise exception 'This over-receipt was already decided (%) on % — nothing was saved', v_d.resolution, to_char(v_d.resolved_at, 'YYYY-MM-DD'); end if;
  select * into v_x from public.inv_transfer x where x.id = v_d.transfer_id for update;
  select * into v_l from public.inv_transfer_line l where l.id = v_d.transfer_line_id;
  select * into v_r from public.po_receipt r where r.id = v_d.receipt_id;
  select w.name into v_fw from public.ref_warehouse w where w.id = v_x.from_warehouse_id;
  select w.name into v_tw from public.ref_warehouse w where w.id = v_x.to_warehouse_id;
  v_n := v_d.received_qty - v_d.expected_qty;
  if v_n <= 0 then raise exception 'Difference row % has no extra units — nothing was saved', p_diff_id; end if;
  select coalesce(pp.id, pr.id), coalesce(pp.sku, pr.sku) into v_pid, v_base from public.product pr left join public.product pp on pp.id = pr.parent_product_id where pr.id = v_l.product_id;
  v_on := public.ims_today();
  -- 도착 칸 = 입고 때 놓은 칸 가운데 가장 많이 놓은 칸(입고 줄) · 없으면 작업 줄
  select b.* into v_tbin from public.po_receipt_line l join public.ref_bin b on b.id = l.bin_id where l.receipt_id = v_d.receipt_id and l.transfer_line_id = v_l.id order by l.qty_ea desc, b.name limit 1;
  if v_tbin.id is null then select b.* into v_tbin from public.po_receipt_work w join public.ref_bin b on b.id = w.bin_id where w.receipt_id = v_d.receipt_id and w.transfer_line_id = v_l.id order by w.qty_ea desc, b.name limit 1; end if;
  if v_tbin.id is null then raise exception 'Transfer % line %: no bin was recorded at arrival — nothing was saved', v_x.transfer_number, v_l.line_no; end if;
  if p_choice = 'sent_more' then
    if not public.ims_can_warehouse(v_x.from_warehouse_id) then raise exception 'Transfer % leaves from a warehouse you are not set up for — nothing was saved', v_x.transfer_number; end if;
    -- 출발 칸 = 고른 칸 · 기본 = 픽 계획 칸(그 줄의 첫 계획 칸)
    if p_from_bin is not null then select * into v_fbin from public.ref_bin b where b.id = p_from_bin;
    else select b.* into v_fbin from public.wms_pick_line_bins pb join public.wms_pick_task_lines pl on pl.id = pb.pick_task_line_id join public.ref_bin b on b.id = pb.bin_id
          where pl.transfer_line_id = v_l.id and pb.planned order by pb.id limit 1; end if;
    if v_fbin.id is null or v_fbin.warehouse_id <> v_x.from_warehouse_id or not v_fbin.is_active then raise exception 'Transfer %: pick a bin at % the extra units came from (no planned bin to default to, or the bin is not there) — nothing was saved', v_x.transfer_number, v_fw; end if;
    -- 출발 칸 선반 기대량(장부 − P)을 넘으면 거부(판정 76 · 실제로 거기 있었던 것만 보낼 수 있다)
    v_shelf := public.inv_adjust_ledger(v_fw, v_fbin.name, v_base) - public.inv_adjust_picked(v_x.from_warehouse_id, v_fbin.id, v_pid);
    if v_shelf < v_n then raise exception 'Transfer %: bin % at % is expected to hold only % EA (ledger minus picked) — it cannot have sent % more; pick another bin or decide found — nothing was saved', v_x.transfer_number, v_fbin.name, v_fw, v_shelf, v_n; end if;
    v_lref := v_l.id::text || ':over:' || v_d.id::text;
    v_cost := public.inv_layer_post_transfer_settle(v_x.transfer_number, v_lref, v_base, v_n, 'sent_more', v_tw, v_on, v_fw, null);
    v_hdr := jsonb_build_object('transfer_number', v_x.transfer_number, 'from_warehouse_id', v_x.from_warehouse_id, 'from_warehouse', v_fw, 'to_warehouse_id', v_x.to_warehouse_id, 'to_warehouse', v_tw,
                                'receipt_number', v_r.receipt_number, 'diff_id', v_d.id, 'decision', 'sent_more', 'decided_on', v_on, 'decided_by', v_staff, 'note', nullif(trim(p_note), ''));
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw) values
      (v_on, 2, v_base, v_fw, v_fbin.name, -v_n, 'transfer_out', 'transfer', v_x.transfer_number, v_x.id::text, v_lref, null, 'ims',
       jsonb_build_object('kind', 'transfer', 'leg', 'over_1', 'poster', c_version, 'header', v_hdr, 'line', jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'product_id', v_l.product_id, 'sku', v_l.sku, 'base_sku', v_base, 'pack_factor', v_l.pack_factor, 'bin', v_fbin.name, 'qty_ea', v_n),
         'rule', format('transfer %s → %s over-receipt decided sent_more: −%s EA at %s / %s (the extra was really sent · shelf expectation %s)', v_fw, v_tw, v_n, v_fw, v_fbin.name, v_shelf), 'cost', v_cost)),
      (v_on, 1, v_base, 'IN_TRANSIT', '', v_n, 'transfer_in', 'transfer', v_x.transfer_number, v_x.id::text, v_lref, null, 'ims',
       jsonb_build_object('kind', 'transfer', 'leg', 'over_2', 'poster', c_version, 'header', v_hdr, 'line', jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'base_sku', v_base, 'qty_ea', v_n),
         'rule', format('transfer %s → %s over-receipt: +%s EA through IN_TRANSIT (same day · net 0 · cost layers go straight to the receiving warehouse)', v_fw, v_tw, v_n), 'cost', v_cost)),
      (v_on, 2, v_base, 'IN_TRANSIT', '', -v_n, 'transfer_out', 'transfer', v_x.transfer_number, v_x.id::text, v_lref, null, 'ims',
       jsonb_build_object('kind', 'transfer', 'leg', 'over_3', 'poster', c_version, 'header', v_hdr, 'line', jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'base_sku', v_base, 'qty_ea', v_n),
         'rule', format('transfer %s → %s over-receipt: −%s EA out of IN_TRANSIT (same day · net 0)', v_fw, v_tw, v_n), 'cost', v_cost)),
      (v_on, 1, v_base, v_tw, v_tbin.name, v_n, 'transfer_in', 'transfer', v_x.transfer_number, v_x.id::text, v_lref, null, 'ims',
       jsonb_build_object('kind', 'transfer', 'leg', 'over_4', 'poster', c_version, 'header', v_hdr, 'line', jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'product_id', v_l.product_id, 'sku', v_l.sku, 'base_sku', v_base, 'pack_factor', v_l.pack_factor, 'bin_id', v_tbin.id, 'bin', v_tbin.name, 'qty_ea', v_n),
         'rule', format('transfer %s → %s over-receipt decided sent_more: +%s EA into %s / %s (the bin the arrival was put in)', v_fw, v_tw, v_n, v_tw, v_tbin.name), 'cost', v_cost));
    update public.inv_transfer_line set qty_extra = qty_extra + v_n / v_l.pack_factor, updated_by = v_staff where id = v_l.id;   -- 더 보낸 몫은 별 칸(qty_sent · qty_received 는 요청 상한 CHECK 그대로 · 원장 · 차이 행이 사실을 든다)
    update public.po_receipt_diff set resolution = 'sent_more', resolved_by = v_staff, resolved_at = now(), updated_by = v_staff,
           resolution_note = format('sent_more: %s EA from %s / %s into %s / %s%s', v_n, v_fw, v_fbin.name, v_tw, v_tbin.name, coalesce(' · ' || nullif(trim(p_note), ''), '')) where id = v_d.id;
    return jsonb_build_object('diff_id', v_d.id, 'transfer_number', v_x.transfer_number, 'decision', 'sent_more', 'qty_ea', v_n, 'from_bin', v_fbin.name, 'to_bin', v_tbin.name, 'shelf_expected_before', v_shelf,
                              'ledger_rows', 4, 'cost', v_cost, 'decided_by', v_staff, 'decided_on', v_on, 'warnings', to_jsonb(v_warn), 'poster', c_version);
  else
    if not public.ims_can_warehouse(v_x.to_warehouse_id) then raise exception 'Transfer % arrives at a warehouse you are not set up for — nothing was saved', v_x.transfer_number; end if;
    -- 도착 창고 조정 문서(조정 창구를 부르기만 · 원가 · 문 · 번호는 조정 규칙 그대로)
    v_adj := public.inv_adjust_create(v_x.to_warehouse_id, format('%s over-receipt · found at arrival (receipt %s)', v_x.transfer_number, v_r.receipt_number), null);
    v_adj_id := (v_adj ->> 'id')::uuid;
    v_line := public.inv_adjust_line_set(v_adj_id, jsonb_build_object('product_id', v_pid, 'bin_id', v_tbin.id, 'mode', 'delta', 'qty', v_n, 'reason', 'found', 'note', format('%s over · found at arrival%s', v_x.transfer_number, coalesce(' · ' || nullif(trim(p_note), ''), ''))));
    v_conf := public.inv_adjust_confirm(v_adj_id);
    if (v_conf -> 'ledger' -> 'keys' -> (v_line ->> 'line_id') ->> 'cost_source') = 'unknown' then v_warn := array_append(v_warn, 'unit_cost_unknown_zero'); end if;   -- 판정 56: 도착 창고에 이 SKU 레이어가 없으면 0 원가(화면이 말한다)
    update public.po_receipt_diff set resolution = 'found', resolved_by = v_staff, resolved_at = now(), updated_by = v_staff,
           resolution_note = format('found: %s EA at %s / %s · %s%s', v_n, v_tw, v_tbin.name, v_adj ->> 'adjust_number', coalesce(' · ' || nullif(trim(p_note), ''), '')) where id = v_d.id;
    return jsonb_build_object('diff_id', v_d.id, 'transfer_number', v_x.transfer_number, 'decision', 'found', 'qty_ea', v_n, 'to_bin', v_tbin.name, 'adjust_id', v_adj_id, 'adjust_number', v_adj ->> 'adjust_number',
                              'adjust', v_conf, 'decided_by', v_staff, 'decided_on', v_on, 'warnings', to_jsonb(v_warn), 'poster', c_version);
  end if;
exception when unique_violation then
  raise exception 'Transfer % — a ledger row with the same key already exists (%) — nothing was saved', v_x.transfer_number, sqlerrm;
end;
$$;
comment on function public.tf_over_decide(uuid, text, uuid, text) is 'tr-3b(판정 68 · 76) — 트랜스퍼 도착의 더 온 몫(over 차이 행) 결정 한 번: sent_more = 출발 칸 −N · IN_TRANSIT ±N · 도착 칸 +N(네 행 · 원가 출발 → 도착 · 선반 기대량 초과 거부 · 줄 qty_sent/received +N) / found = 도착 창고 조정 문서(found · 조정 창구를 부르기만) · 문 = ims_can_adjust + 창고(sent_more 출발 · found 도착) · 차이 행에 방법 · 사람 · 시각 · ADJ 번호';
revoke all on function public.tf_over_decide(uuid, text, uuid, text) from public, anon;
grant execute on function public.tf_over_decide(uuid, text, uuid, text) to authenticated;

-- ═══ 6) 재발행 5 — 마지막 정의 바이트 그대로 + 바꾼 줄(diff 원문은 보고) ═══

-- ── inv_layer_apply_transfer_depart_ims ──
create or replace function public.inv_layer_apply_transfer_depart_ims(p_ledger_id bigint) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare r public.inv_ledger%rowtype; v_qty numeric; v_from text; v_lref text; v_res jsonb;
begin
  select * into r from public.inv_ledger where id = p_ledger_id;
  if not found or r.source <> 'ims' or (r.raw ->> 'kind') is distinct from 'transfer' or r.event_type <> 'transfer_in' or r.warehouse <> 'IN_TRANSIT' or (r.raw ->> 'leg') is distinct from '2' then   -- tr-3b: leg 2 만(over_2 는 본체가 세고 지나간다)
    return jsonb_build_object('processed', false, 'reason', 'not a departure transit row');
  end if;
  if exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_trd' and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = '') then
    return jsonb_build_object('processed', false, 'reason', 'done');
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_trd', r.doc_number, r.sku, '');   -- 키 = (문서, 낱개 SKU) · 실시간 창구가 키마다 한 번 부른 것과 같은 단위
  select sum(e.qty_delta) into v_qty from public.inv_ledger e
   where e.doc_type = 'transfer' and e.doc_number = r.doc_number and e.source = 'ims' and (e.raw ->> 'kind') = 'transfer'
     and e.event_type = 'transfer_in' and e.warehouse = 'IN_TRANSIT' and e.sku = r.sku and (e.raw ->> 'leg') = '2';   -- 같은 문서 · 같은 낱개 SKU 의 leg 2 전부(줄 여럿은 접는다) · tr-3b: over_2(더 온 몫)는 빼고
  v_from := r.raw -> 'header' ->> 'from_warehouse';
  v_lref := coalesce(r.raw -> 'cost' ->> 'line_ref', r.line_ref);
  v_res := public.inv_layer_post_transfer_depart(r.doc_number, v_lref, r.sku, v_from, v_qty, r.occurred_on, r.raw -> 'cost');
  return v_res || jsonb_build_object('processed', true);
end;
$$;

-- ── inv_layer_apply_transfer_arrive_ims ──
create or replace function public.inv_layer_apply_transfer_arrive_ims(p_ledger_id bigint) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare r public.inv_ledger%rowtype; v_rcv text; v_qty numeric; v_lref text; v_res jsonb;
begin
  select * into r from public.inv_ledger where id = p_ledger_id;
  if not found or r.source <> 'ims' or (r.raw ->> 'kind') is distinct from 'transfer' or r.event_type <> 'transfer_in' or r.warehouse = 'IN_TRANSIT' or (r.raw ->> 'leg') is distinct from '4' then   -- tr-3b: leg 4 만(return_in · over_4 는 정리 갈래)
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
     and e.event_type = 'transfer_in' and e.warehouse = r.warehouse and e.sku = r.sku and e.raw -> 'header' ->> 'receipt_number' = v_rcv and (e.raw ->> 'leg') = '4';   -- 같은 문서 · 입고 · 낱개 SKU 의 leg 4 전부(칸 여럿은 접는다) · tr-3b: over_4 는 빼고
  v_lref := coalesce(r.raw -> 'cost' ->> 'line_ref', r.line_ref);
  v_res := public.inv_layer_post_transfer_arrive(r.doc_number, v_lref, r.sku, r.warehouse, v_qty, r.occurred_on, r.raw -> 'cost');
  return v_res || jsonb_build_object('processed', true);
end;
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
  v_ims_leg     text;                                                                     -- tr-3b raw.leg(lost · return_in · over_2 · over_4 갈래)
  v_ims_trs     int := 0;   v_ims_trs_layers int := 0;   v_ims_trs_rows int := 0;   v_ims_trs_short numeric := 0;   v_ims_trs_skipped int := 0;   v_ims_trs_pass int := 0;   -- tr-3b 정리 창구 inv_layer_apply_transfer_settle_ims 의 반환 합
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
      select source, raw ->> 'kind', warehouse, raw ->> 'leg' into v_ims_src, v_ims_kind, v_ims_wh, v_ims_leg from inv_ledger where id = r.id;   -- trf-a: kind 도 함께(조회 한 번 그대로) · tr-2: warehouse 도 · tr-3b: leg 도
      if v_ims_src = 'ims' and v_ims_kind = 'bin_move' and r.event_type in ('transfer_in', 'transfer_out') then   -- trf-a 2026-09-28 칸 옮기기(같은 창고 · inv_post_move) — 레이어는 (sku, warehouse) 단위라 할 일이 없다 · 세지 않고 지나간다(실시간 창구도 레이어를 부르지 않는다 = 같은 결과) · 창고 간 문서는 kind 가 다르다(뒤 차수의 갈래)
        v_bin_moves := v_bin_moves + 1;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and v_ims_leg in ('lost', 'return_in', 'over_4') then   -- tr-3b 운송 중 정리(lost · return) · 더 온 몫(sent_more) → 창구(inv_layer_post_transfer_settle · 실시간과 같은 함수) · 행마다(line_ref 가 곧 키)
        begin
          v_ims_j := inv_layer_apply_transfer_settle_ims(r.id);
          if (v_ims_j ->> 'processed')::boolean then
            v_ims_trs        := v_ims_trs + 1;
            v_ims_trs_layers := v_ims_trs_layers + coalesce((v_ims_j ->> 'layers')::int, 0);
            v_ims_trs_rows   := v_ims_trs_rows   + coalesce((v_ims_j ->> 'consume_rows')::int, 0);
            v_ims_trs_short  := v_ims_trs_short  + coalesce((v_ims_j ->> 'short_qty')::numeric, 0);
          end if;
        exception when others then
          v_ims_trs_skipped := v_ims_trs_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'transfer_settle', 'number', (select doc_number from inv_ledger where id = r.id), 'id', r.id, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and v_ims_leg = 'over_2' then                  -- tr-3b 더 온 몫의 IN_TRANSIT in(같은 날 ±N · 레이어는 over_4 가 출발 창고에서 곧장 도착 창고로) — 세고 지나간다
        v_ims_trs_pass := v_ims_trs_pass + 1;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and r.event_type = 'transfer_out' then     -- tr-2 2026-09-28 창고 간 트랜스퍼 출발 out(출발 창고) — IN_TRANSIT in 이 처리한다(불러온 축과 같은 결) · 세고 지나간다 · tr-3b: leg 3 · return_out · over_1 · over_3 도 여기
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
      'transfer_settles_posted',   v_ims_trs,               -- ⭐ tr-3b 정리 · 더 온 몫(lost · return_in · over_4 행마다) — 창구가 소진 · 레이어를 만든 수
      'transfer_settle_layers',    v_ims_trs_layers,        -- 되돌린 · 더 보낸 몫의 레이어 수(lost 는 0)
      'transfer_settle_consume_rows', v_ims_trs_rows,       -- 소진 행 수
      'transfer_settle_short_qty', v_ims_trs_short,         -- 문서 레이어가 모자란 EA
      'transfer_settles_skipped',  v_ims_trs_skipped,       -- ⚠️ 창구가 거부해 건너뛴 수 — skip_reasons kind 'transfer_settle'
      'transfer_over_in_passed',   v_ims_trs_pass,          -- over_2 행 수(세고 지나감)
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
  trf_over as (                                                          -- tr-3b 판정 76: 더 온 몫이 결정을 기다린다(over 차이 행 · 트랜스퍼 · 미결)
    select x.transfer_number, r.receipt_number, pr.sku, d.received_qty - d.expected_qty as over_ea, d.created_at
      from public.po_receipt_diff d join public.inv_transfer x on x.id = d.transfer_id join public.po_receipt r on r.id = d.receipt_id join public.product pr on pr.id = d.product_id
     where d.kind = 'over' and d.transfer_id is not null and d.resolved_at is null
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
  select 177, 'transfer_over_undecided', 'warn', 'Transfer arrived with more than was sent - decision pending',
    'A transfer arrival counted more units than were sent; only the sent units arrived. Someone with the stock-adjust key must decide whether the sending warehouse sent more (move them across) or the receiving warehouse found them (stock adjustment).',
    (select count(*) from trf_over), (select jsonb_agg(t) from (select * from trf_over limit 8) t)
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

-- ── inv_transfer_detail ──
create or replace function public.inv_transfer_detail(p_transfer_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not public.ims_can_view('transfer') then null::jsonb else (
    select jsonb_build_object(
      'header', to_jsonb(x) || jsonb_build_object('from_warehouse', fw.name, 'to_warehouse', tw.name, 'created_by_name', cb.name, 'confirmed_by_name', fb.name),
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', p.name, 'qty', l.qty, 'qty_sent', l.qty_sent, 'short_sent', case when l.qty_sent is not null and l.qty_sent < l.qty then l.qty - l.qty_sent end, 'qty_received', l.qty_received, 'qty_lost', l.qty_lost, 'qty_returned', l.qty_returned, 'qty_extra', l.qty_extra, 'pack_factor', l.pack_factor,
                                                              'qty_ea', l.qty * l.pack_factor, 'stock_product_id', coalesce(p.parent_product_id, p.id)) order by l.line_no), '[]'::jsonb)
                  from public.inv_transfer_line l join public.product p on p.id = l.product_id where l.transfer_id = x.id),
      'shortage', case when x.status = 'draft' then public.inv_transfer_shortage(x.id) else '[]'::jsonb end)
      from public.inv_transfer x
      join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = x.to_warehouse_id
      left join public.ims_staff cb on cb.id = x.created_by left join public.ims_staff fb on fb.id = x.confirmed_by
     where x.id = p_transfer_id) end;
$$;
