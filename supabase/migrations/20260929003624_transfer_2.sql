-- ─────────────────────────────────────────────────────────────
-- 재고 사건 ② 트랜스퍼 · 둘째 몫 「창고 간」 ③ 출발 — 창고 마무리 순간 출발 창고에서 빠지고 운송 중으로 · 원가 따라가기 · 모자람은 뽑은 만큼 (Asung-IMS · tr-2 · 2026-09-28)
--   정본(뒤에 적는다): so-module §27(판정 65 · 67 · 73 · 74 · 묶음 4 · 5 · 8) · tr-1a · tr-1b1 · tr-1b2 위에 선다
--   든 것: ① inv_transfer_line.qty_sent(보낸 수량 · 판매 단위 · 출발 때 채운다 · 「덜 보냄」= qty_sent < qty · 판정 74) · inv_transfer_detail 줄에 qty_sent · short_sent(키 추가 · 모양 그대로)
--         ② tf_wms_status 에 picking → in_transit 짝 + departed_at/by · tf_depart(문서 id · 사람) — 창고 마무리 안에서만 부른다: wms_so_handoff 의 picks(Σ실제 칸 · 팩 회복 포함)로 줄마다 보낸 수량 → in_transit → 원장 창구
--         ③ inv_post_transfer_depart(원장 창구 · 멱등 · inv_post_sale · inv_post_move 모양): 낱개 SKU 키마다 레이어 창구 먼저 → 출발 창고 실제 칸마다 transfer_out −EA seq 2(leg 1) + 줄마다 IN_TRANSIT '' transfer_in +EA seq 1(leg 2) · raw.kind transfer · raw.cost
--            inv_layer_post_transfer_depart(레이어 창구 · definer): 출발 창고 FIFO 소진 → IN_TRANSIT 레이어(parent · 같은 unit_cost · received_on · age) · 부족은 short 로 남긴다(불러온 축 inv_layer_apply_transfer_in 의 창고 출발 규칙과 같다 · 레이어 없음)
--            inv_layer_apply_transfer_depart_ims(재생성 갈래 · (doc, sku) 한 번 · 실시간과 같은 창구) · inv_layer_apply 재발행: raw.kind transfer → 출발 out 은 세고 지나감 · IN_TRANSIT in 은 창구 · 도착 in(④)은 종전 문이 센다 · 반환 ims 에 여섯 키
--         ④ wms_finalize: 트랜스퍼 거부 줄을 갈래로 — 검사(팩 완료 · 팔렛 대조)는 판매와 같게 · wms_order_finalize(transfer_id) · 판매는 packed(무변) · 트랜스퍼는 tf_depart(반환에 departed 만 더한다)
--         ⑤ wms_rollback: 떠난 트랜스퍼(finalize 단계 · in_transit)는 거부(묶음 5 · 「운송 중 정리의 return 으로」) · 판매 갈래 무변 · wms_health_check: transfer_departed_no_ledger(178 · critical · 출발 짝 둘)
--   ⭐ 약속: 판매 동작 무변(tr-1b1 대조 12 · wms-round 11 을 이 파일로 다시) · 트랜스퍼는 출발까지 — 도착 · 운송 중 정리 · 운임은 ④ · ⑤
--   예약 · 가용 · P(D): so_available_many 의 트랜스퍼 예약은 status confirmed · at_wms · picking 만이라 in_transit 이 되는 순간 빠지고 같은 트랜잭션의 원장 −EA 가 대신한다(두 번 줄지 않는다) · inv_adjust_picked 는 status picking · packed 만이라 in_transit 에서 빠진다 — 둘 다 무접촉(검증 D5 가 본다)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 판매 표 · 행 무접촉 · 판매 창구(so_finalize · so_ship · inv_post_sale · so_allocate_run · so_confirm · so_wms_status 본문) 무접촉 · IMS 안에서만 선다(판정 51 · 60)
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

-- ═══ 1) 줄 칸 — 보낸 수량(판매 단위 · 출발 때 채운다 · 판정 74) ═══
alter table public.inv_transfer_line add column qty_sent numeric;
alter table public.inv_transfer_line add constraint inv_transfer_line_sent_ck check (qty_sent is null or (qty_sent >= 0 and qty_sent <= qty));
comment on column public.inv_transfer_line.qty_sent is 'tr-2(판정 74) — 출발 때 실제로 보낸 수량(판매 단위 · Σ실제 칸 ÷ pack_factor · wms_so_handoff 의 picks) · null = 아직 안 떠남 · qty_sent < qty = 덜 보냄(모자란 몫은 이 문서에서 닫힌다 · 더 보낼 것은 오피스가 새 트랜스퍼)';

-- ═══ 2) 레이어 창구 — 출발: 출발 창고 FIFO → IN_TRANSIT 레이어(parent · 같은 원가 · 같은 나이) · 낱개 SKU 키마다 한 번 · 멱등(같은 키가 이미 서 있으면 거부) ═══
create function public.inv_layer_post_transfer_depart(p_doc_number text, p_line_ref text, p_sku text, p_from_warehouse text, p_qty numeric, p_occurred_on date, p_hint jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_layer_post_transfer_depart@2026-09-28.1';
        v_rows int; v_short int; v_layers int; v_taken numeric; v_amt numeric;
begin
  if p_qty is null or p_qty <= 0 then return jsonb_build_object('qty', p_qty, 'branch', 'none', 'builder', c_version); end if;
  if exists (select 1 from public.inv_layer y where y.origin_type = 'transfer' and y.doc_number = p_doc_number and y.warehouse = 'IN_TRANSIT' and y.sku = p_sku)
     or exists (select 1 from public.inv_layer_consume c join public.inv_layer y on y.id = c.layer_id
                 where c.doc_type = 'transfer' and c.doc_number = p_doc_number and c.event_type = 'transfer_out' and y.sku = p_sku and y.warehouse = p_from_warehouse) then
    raise exception 'Transfer % / % departure was already costed — nothing was saved', p_doc_number, p_sku;
  end if;
  -- 출발 창고 FIFO 소진 → 소진한 레이어마다 IN_TRANSIT 레이어(parent_layer · unit_cost · received_on · age_known 그대로) — 불러온 축(inv_layer_apply_transfer_in · 창고 출발)과 같은 손(inv_layer_fifo_take) · 문서 범위 없음(실제 창고 출발)
  select * into v_rows, v_short, v_layers, v_taken
    from public.inv_layer_fifo_take(p_sku, p_from_warehouse, p_qty, 'transfer', p_doc_number, p_line_ref, 'transfer_out', p_occurred_on, 'transfer', 'IN_TRANSIT', null);
  select coalesce(sum(c.amount), 0) into v_amt from public.inv_layer_consume c join public.inv_layer y on y.id = c.layer_id
   where c.doc_type = 'transfer' and c.doc_number = p_doc_number and c.line_ref = p_line_ref and c.event_type = 'transfer_out' and y.sku = p_sku and y.warehouse = p_from_warehouse;
  -- 부족(출발 창고 레이어 < 보낸 EA)은 short 로 남긴다 — 불러온 축의 창고 출발 규칙과 같다(원가 미상 레이어를 세우지 않는다 · 운송 중 수량은 원장이 말한다 · 도착 ④ 가 같은 부족을 다시 본다)
  return jsonb_build_object('sku', p_sku, 'from_warehouse', p_from_warehouse, 'qty', p_qty, 'line_ref', p_line_ref,
                            'taken', coalesce(v_taken, 0), 'consume_rows', coalesce(v_rows, 0), 'layers', coalesce(v_layers, 0), 'short', coalesce(v_short, 0), 'short_qty', p_qty - coalesce(v_taken, 0),
                            'amount', v_amt, 'reproduced', p_hint is not null, 'builder', c_version);
end;
$$;
comment on function public.inv_layer_post_transfer_depart(text, text, text, text, numeric, date, jsonb) is 'tr-2(판정 65 · 67 앞) — 창고 간 트랜스퍼 출발의 원가: 출발 창고 레이어 FIFO 소진(reason transfer · event transfer_out) → IN_TRANSIT 레이어(origin transfer · parent_layer · 같은 unit_cost · received_on) · 낱개 SKU 키마다 한 번(줄 여럿은 접는다 · line_ref 첫 줄) · 부족은 short(레이어 없음) · 실시간(inv_post_transfer_depart)과 재생성(inv_layer_apply_transfer_depart_ims)이 같은 함수';
revoke all on function public.inv_layer_post_transfer_depart(text, text, text, text, numeric, date, jsonb) from public, anon, authenticated;

-- ═══ 3) 원장 창구 — 출발(멱등 · inv_post_sale · inv_post_move 모양 · 창고 마무리 트랜잭션 안에서 tf_depart 가 부른다) ═══
create function public.inv_post_transfer_depart(p_transfer_id uuid, p_picks jsonb, p_occurred_on date) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_post_transfer_depart@2026-09-28.1';
        v_x public.inv_transfer%rowtype; v_fw text; v_tw text; v_existing int; v_alloc jsonb; v_bad text; v_costs jsonb := '{}'::jsonb; v_rows int := 0; v_qty numeric := 0; v_hdr jsonb;
        v_k record; v_b record; v_g record;                                                     -- ⚠️ CTE 별칭(p · g · a)과 겹치지 않게 v_ 접두
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id;
  if not found then raise exception 'Transfer not found — nothing was posted to the ledger'; end if;
  if v_x.status <> 'in_transit' or v_x.departed_at is null then
    raise exception 'Transfer % is % — the ledger takes departed transfers only — nothing was posted to the ledger', v_x.transfer_number, v_x.status;
  end if;
  select w.name into v_fw from public.ref_warehouse w where w.id = v_x.from_warehouse_id;
  select w.name into v_tw from public.ref_warehouse w where w.id = v_x.to_warehouse_id;
  if v_fw is null or v_tw is null then raise exception 'Transfer % has no warehouse pair — nothing was posted to the ledger', v_x.transfer_number; end if;
  -- 멱등 — 이미 기표된 출발은 다시 쓰지 않는다(말하는 0)
  select count(*) into v_existing from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = v_x.transfer_number and e.source = 'ims';
  if v_existing > 0 then
    return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'already_posted', true, 'existing_rows', v_existing,
                              'rows_posted', 0, 'qty_ea_posted', 0, 'keys', '{}'::jsonb, 'warnings', '["already_posted"]'::jsonb);
  end if;
  -- 줄×칸 모으기 — picks {line_id, bin, qty}(판매 단위 · wms_so_handoff) → EA(pack_factor) · 낱개 SKU(세트 줄은 parent) · 이 문서의 줄만
  select string_agg(distinct p.line_id::text, ', ') into v_bad
    from (select (e->>'line_id')::uuid as line_id from jsonb_array_elements(coalesce(p_picks, '[]'::jsonb)) e) p
   where not exists (select 1 from public.inv_transfer_line l where l.id = p.line_id and l.transfer_id = p_transfer_id);
  if v_bad is not null then raise exception 'Pick line % is not on transfer % — nothing was posted to the ledger', v_bad, v_x.transfer_number; end if;
  with p as (
    select (e->>'line_id')::uuid as line_id, coalesce(nullif(trim(e->>'bin'), ''), '') as bin, (e->>'qty')::numeric as qty
      from jsonb_array_elements(coalesce(p_picks, '[]'::jsonb)) e
  ), g as (select line_id, bin, sum(qty) as qty from p group by 1, 2),
  a as (
    select l.id as line_id, l.line_no, l.product_id, l.sku, l.pack_factor, l.qty as qty_requested, l.qty_sent,
           coalesce(pp.sku, pr.sku) as base_sku, g.bin, g.qty, g.qty * l.pack_factor as qty_ea
      from g join public.inv_transfer_line l on l.id = g.line_id and l.transfer_id = p_transfer_id
      join public.product pr on pr.id = l.product_id left join public.product pp on pp.id = pr.parent_product_id
     where g.qty > 0
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no, a.bin), '[]'::jsonb) into v_alloc from a;
  if jsonb_array_length(v_alloc) = 0 then raise exception 'Transfer % has no picked quantity — nothing was posted to the ledger', v_x.transfer_number; end if;
  v_hdr := jsonb_build_object('transfer_number', v_x.transfer_number, 'from_warehouse_id', v_x.from_warehouse_id, 'from_warehouse', v_fw, 'to_warehouse_id', v_x.to_warehouse_id, 'to_warehouse', v_tw,
                              'departed_on', p_occurred_on, 'departed_at', v_x.departed_at, 'departed_by', v_x.departed_by, 'note', v_x.note);
  -- ⭐ 레이어 먼저 — 낱개 SKU 키마다 한 번(출발 창고 하나 · 줄 여럿은 접는다 · consume.line_ref = 첫 줄 · 재생성 키와 같다 · inv_post_sale 과 같은 결)
  for v_k in
    select t.base_sku, sum(t.qty_ea) as qty_ea, (array_agg(t.line_id::text order by t.line_no, t.bin))[1] as line_ref
      from jsonb_to_recordset(v_alloc) as t(base_sku text, qty_ea numeric, line_id uuid, line_no int, bin text)
     group by t.base_sku order by t.base_sku
  loop
    v_costs := v_costs || jsonb_build_object(v_k.base_sku, public.inv_layer_post_transfer_depart(v_x.transfer_number, v_k.line_ref, v_k.base_sku, v_fw, v_k.qty_ea, p_occurred_on, null));
  end loop;
  -- leg 1 — 줄×칸 · 출발 창고 실제 칸에서 −EA(seq 2 · 팩 회복 칸 포함 = 픽커가 뽑은 것과 같은 기록)
  for v_b in
    select * from jsonb_to_recordset(v_alloc) as t(line_id uuid, line_no int, product_id uuid, sku text, pack_factor numeric, qty_requested numeric, qty_sent numeric, base_sku text, bin text, qty numeric, qty_ea numeric)
     order by line_no, bin
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (p_occurred_on, 2, v_b.base_sku, v_fw, v_b.bin, -v_b.qty_ea, 'transfer_out', 'transfer', v_x.transfer_number, v_x.id::text, v_b.line_id::text, null, 'ims',
            jsonb_build_object('kind', 'transfer', 'leg', 1, 'poster', c_version, 'header', v_hdr,
              'line', jsonb_build_object('line_id', v_b.line_id, 'line_no', v_b.line_no, 'product_id', v_b.product_id, 'sku', v_b.sku, 'base_sku', v_b.base_sku, 'pack_factor', v_b.pack_factor,
                                         'qty_requested', v_b.qty_requested, 'qty_sent', v_b.qty_sent, 'bin', v_b.bin, 'qty', v_b.qty, 'qty_ea', v_b.qty_ea),
              'rule', format('transfer %s → %s leg 1: −%s EA at %s / %s (picked bins · pack recovery included · departure = warehouse finalize)', v_fw, v_tw, v_b.qty_ea, v_fw, v_b.bin),
              'cost', v_costs -> v_b.base_sku));
    v_rows := v_rows + 1; v_qty := v_qty + v_b.qty_ea;
  end loop;
  -- leg 2 — 줄마다 IN_TRANSIT(칸 '') +EA(seq 1 · 같은 날 유입 먼저 · 재생성은 이 행에서 출발 창구를 부른다)
  for v_g in
    select t.line_id, t.line_no, t.product_id, t.sku, t.base_sku, t.pack_factor, t.qty_requested, t.qty_sent, sum(t.qty) as qty, sum(t.qty_ea) as qty_ea
      from jsonb_to_recordset(v_alloc) as t(line_id uuid, line_no int, product_id uuid, sku text, pack_factor numeric, qty_requested numeric, qty_sent numeric, base_sku text, bin text, qty numeric, qty_ea numeric)
     group by t.line_id, t.line_no, t.product_id, t.sku, t.base_sku, t.pack_factor, t.qty_requested, t.qty_sent order by t.line_no
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (p_occurred_on, 1, v_g.base_sku, 'IN_TRANSIT', '', v_g.qty_ea, 'transfer_in', 'transfer', v_x.transfer_number, v_x.id::text, v_g.line_id::text, null, 'ims',
            jsonb_build_object('kind', 'transfer', 'leg', 2, 'poster', c_version, 'header', v_hdr,
              'line', jsonb_build_object('line_id', v_g.line_id, 'line_no', v_g.line_no, 'product_id', v_g.product_id, 'sku', v_g.sku, 'base_sku', v_g.base_sku, 'pack_factor', v_g.pack_factor,
                                         'qty_requested', v_g.qty_requested, 'qty_sent', v_g.qty_sent, 'qty', v_g.qty, 'qty_ea', v_g.qty_ea),
              'rule', format('transfer %s → %s leg 2: +%s EA into IN_TRANSIT (arrival at %s is the next step)', v_fw, v_tw, v_g.qty_ea, v_tw),
              'cost', v_costs -> v_g.base_sku));
    v_rows := v_rows + 1;
  end loop;
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'already_posted', false, 'existing_rows', 0,
                            'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'keys', v_costs, 'poster', c_version);
exception when unique_violation then
  raise exception 'Transfer % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_x.transfer_number, sqlerrm;
end;
$$;
comment on function public.inv_post_transfer_depart(uuid, jsonb, date) is 'tr-2(판정 65) — 창고 간 트랜스퍼 출발의 원장: 낱개 SKU 키마다 레이어 창구 먼저 → 출발 창고 실제 칸마다 transfer_out −EA(seq 2 · leg 1) + 줄마다 IN_TRANSIT '''' transfer_in +EA(seq 1 · leg 2) · raw.kind transfer · raw.cost · doc TRF-n · doc_task_id 문서 id · line_ref 줄 id · 멱등(같은 문서 ims 행이 있으면 말하는 0) · 창고 마무리 트랜잭션 안에서 tf_depart 가 부른다';
revoke all on function public.inv_post_transfer_depart(uuid, jsonb, date) from public, anon, authenticated;

-- ═══ 4) 재생성 갈래 — IN_TRANSIT in(leg 2 · raw.kind transfer) 에서 (doc, sku) 한 번 · 실시간과 같은 창구 ═══
create function public.inv_layer_apply_transfer_depart_ims(p_ledger_id bigint) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare r public.inv_ledger%rowtype; v_qty numeric; v_from text; v_lref text; v_res jsonb;
begin
  select * into r from public.inv_ledger where id = p_ledger_id;
  if not found or r.source <> 'ims' or (r.raw ->> 'kind') is distinct from 'transfer' or r.event_type <> 'transfer_in' or r.warehouse <> 'IN_TRANSIT' then
    return jsonb_build_object('processed', false, 'reason', 'not a departure transit row');
  end if;
  if exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_trd' and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = '') then
    return jsonb_build_object('processed', false, 'reason', 'done');
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_trd', r.doc_number, r.sku, '');   -- 키 = (문서, 낱개 SKU) · 실시간 창구가 키마다 한 번 부른 것과 같은 단위
  select sum(e.qty_delta) into v_qty from public.inv_ledger e
   where e.doc_type = 'transfer' and e.doc_number = r.doc_number and e.source = 'ims' and (e.raw ->> 'kind') = 'transfer'
     and e.event_type = 'transfer_in' and e.warehouse = 'IN_TRANSIT' and e.sku = r.sku;                               -- 같은 문서 · 같은 낱개 SKU 의 leg 2 전부(줄 여럿은 접는다)
  v_from := r.raw -> 'header' ->> 'from_warehouse';
  v_lref := coalesce(r.raw -> 'cost' ->> 'line_ref', r.line_ref);
  v_res := public.inv_layer_post_transfer_depart(r.doc_number, v_lref, r.sku, v_from, v_qty, r.occurred_on, r.raw -> 'cost');
  return v_res || jsonb_build_object('processed', true);
end;
$$;
comment on function public.inv_layer_apply_transfer_depart_ims(bigint) is 'tr-2 — inv_layer_apply 의 IMS 트랜스퍼 출발 갈래(raw.kind transfer · IN_TRANSIT transfer_in 행에서) · done 키 ims_trd(문서, 낱개 SKU) · 창구 inv_layer_post_transfer_depart 를 실시간과 같은 합으로 부른다 · 출발 out 행은 본체가 세고 지나간다 · 도착 in 은 ④';
revoke all on function public.inv_layer_apply_transfer_depart_ims(bigint) from public, anon, authenticated;

-- ═══ 5) tf_depart — 창고 마무리 안에서만 부르는 출발 손(판정 65 · 74 · 묶음 5) ═══
create function public.tf_depart(p_transfer_id uuid, p_staff uuid) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_x public.inv_transfer%rowtype; v_h jsonb; v_on date; v_ledger jsonb; v_lines jsonb;
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  if v_x.status <> 'picking' then raise exception 'Transfer % is % — only a transfer in warehouse work (picking) can depart — nothing was saved', v_x.transfer_number, v_x.status; end if;
  v_on := public.ims_today();
  v_h := public.wms_so_handoff(p_transfer_id);                                             -- picks = Σ실제 칸(팩 회복 포함 · 팩 verified · 요청 상한) · shorts = 덜 뽑은 줄 — 판매 인계와 같은 셈
  if coalesce(jsonb_array_length(v_h -> 'picks'), 0) = 0 then raise exception 'Transfer % has no picked quantity — nothing departs — nothing was saved', v_x.transfer_number; end if;
  -- 판정 74 — 줄마다 보낸 수량 = 뽑은 만큼(판매 단위) · 모자란 몫은 이 문서에서 닫힌다(백오더 · 새 문서 없음 · 더 보낼 것은 오피스가 새 트랜스퍼)
  update public.inv_transfer_line l set qty_sent = coalesce(s.q, 0), updated_by = p_staff
    from (select l2.id, (select sum((e ->> 'qty')::numeric) from jsonb_array_elements(v_h -> 'picks') e where (e ->> 'line_id')::uuid = l2.id) as q
            from public.inv_transfer_line l2 where l2.transfer_id = p_transfer_id) s
   where s.id = l.id;
  select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'requested', l.qty, 'sent', l.qty_sent, 'short', l.qty - l.qty_sent) order by l.line_no), '[]'::jsonb)
    into v_lines from public.inv_transfer_line l where l.transfer_id = p_transfer_id;
  perform public.tf_wms_status(p_transfer_id, 'in_transit', p_staff);                     -- 출발 = 상태 손 하나(departed_at/by 도 거기서) · 예약(so_available_many 의 talloc)은 이 순간 빠진다
  v_ledger := public.inv_post_transfer_depart(p_transfer_id, v_h -> 'picks', v_on);         -- 원장 · 레이어 · 같은 트랜잭션(실패하면 마무리도 안 된다)
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'status', 'in_transit', 'departed_on', v_on, 'departed_by', p_staff,
                            'lines', v_lines, 'shorts', v_h -> 'shorts', 'ledger', v_ledger);
end;
$$;
comment on function public.tf_depart(uuid, uuid) is 'tr-2(판정 65 · 74 · 묶음 5) — 창고 마무리(wms_finalize)가 트랜스퍼에 부르는 출발 손: 보낸 수량(줄 · 판매 단위) → in_transit(departed_at/by) → 원장 · 레이어 · 되돌리기 없음 · 직원에게는 회수(판정 31)';
revoke all on function public.tf_depart(uuid, uuid) from public, anon, authenticated;

-- ═══ 6) 재발행 6 — 마지막 정의 바이트 그대로 + 바꾼 줄(diff 원문은 보고) · create or replace 라 grant · comment · security 가 남는다 ═══

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
       or (p_to = 'in_transit' and v_from = 'picking')) then                            -- tr-2 판정 65: 출발 = 창고 마무리(picking → in_transit · tf_depart 만 부른다) · packed 는 트랜스퍼에 없다 · 도착(receiving · received)은 ④
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
         updated_by = p_staff
   where x.id = p_transfer_id and x.status = v_from;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Transfer % changed under you (expected %) — nothing was saved', v_x.transfer_number, v_from;
  end if;
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'from', v_from, 'to', p_to);
end;
$$;

-- ── wms_finalize ──
create or replace function public.wms_finalize(p_so_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_id uuid;  v_doc public.wms_order_doc%rowtype;  v_all boolean;  v_bad text;
  v_placed boolean;  v_units int;  v_nodim int;  v_type text;
  v_out jsonb := '[]'::jsonb;  v_warn text[] := '{}';  v_dep jsonb;
begin
  perform public.ims_require_write('fulfillment', 'saved');            -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  if p_so_ids is null or cardinality(p_so_ids) = 0 then raise exception 'No orders given — nothing was saved'; end if;
  -- ① 검사 전부(잠금 · 하나라도 막히면 전체 거부)
  foreach v_id in array p_so_ids loop
    perform 1 from public.so s where s.id = v_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
    perform 1 from public.inv_transfer x where x.id = v_id for update;             -- tr-1b2: 트랜스퍼 행 잠금(판정 72-3 의 짝 · 문서 id 는 둘 중 하나에만 맞는다)
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
    from (select coalesce(order_line_id, transfer_line_id) as order_line_id, sum(qty_base) as q from public.wms_pallet_items where coalesce(order_id, transfer_id) = v_id group by 1) pi
    join public.wms_order_doc_line sl on sl.line_id = pi.order_line_id
    left join (select coalesce(kl.order_line_id, kl.transfer_line_id) as order_line_id, sum(kl.verified_base) as q from public.wms_pack_task_lines kl join public.wms_pack_tasks k on k.id = kl.pack_task_id where coalesce(k.order_id, k.transfer_id) = v_id and k.status = 'completed' group by 1) pk on pk.order_line_id = pi.order_line_id
    where pi.q > coalesce(pk.q, 0);
    if v_bad is not null then raise exception 'Order % — more on pallets than was packed (%) — nothing was saved', v_doc.doc_number, v_bad; end if;
  end loop;
  -- ② 기록 + 전이
  foreach v_id in array p_so_ids loop
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    v_placed := exists (select 1 from public.wms_pallet_items pi where coalesce(pi.order_id, pi.transfer_id) = v_id);
    select count(*), count(*) filter (where u.length_in is null or u.width_in is null or u.height_in is null or u.weight_lb is null) into v_units, v_nodim
    from public.wms_pallets u where coalesce(u.order_id, u.transfer_id) = v_id or u.parent_id in (select p2.id from public.wms_pallets p2 where coalesce(p2.order_id, p2.transfer_id) = v_id);
    v_type := case when v_placed then 'packing_list' else 'direct' end;
    if v_nodim > 0 then v_warn := array_append(v_warn, format('units_without_dims:%s:%s', v_doc.doc_number, v_nodim)); end if;
    insert into public.wms_order_finalize (order_id, transfer_id, fulfillment_type, finalized_by, finalized_at, units, units_without_dims)
    values (case when v_doc.doc_kind = 'so' then v_id end, case when v_doc.doc_kind = 'transfer' then v_id end, v_type, v_staff, now(), v_units, v_nodim);
    if v_doc.doc_kind = 'so' then
      perform public.wms_doc_status(v_doc.doc_kind, v_id, 'packed', v_staff);       -- 판매: packed(출고 · 원장은 오피스 so_finalize → so_ship)
      v_dep := null;
    else
      v_dep := public.tf_depart(v_id, v_staff);                                     -- tr-2 판정 65: 트랜스퍼는 창고 마무리 순간 출발 — 같은 트랜잭션에 보낸 수량 · 원장 · 레이어 · in_transit
    end if;
    v_out := v_out || (jsonb_build_object('so_id', v_id, 'so_number', v_doc.doc_number, 'fulfillment_type', v_type, 'units', v_units, 'units_without_dims', v_nodim,
                                          'shorts', (public.wms_so_handoff(v_id))->'shorts')
                       || case when v_dep is null then '{}'::jsonb else jsonb_build_object('departed', v_dep) end);   -- 판매 반환 모양 무변 · 트랜스퍼만 departed 를 더한다(괄호 = 객체를 먼저 합친 뒤 배열에 한 원소로)
  end loop;
  return jsonb_build_object('finalized', v_out, 'count', jsonb_array_length(v_out), 'warnings', to_jsonb(v_warn));
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
  perform 1 from public.inv_transfer x where x.id = p_so_id for update;             -- tr-1b2: 트랜스퍼 행 잠금(판정 72-3 의 짝 · 문서 id 는 둘 중 하나에만 맞는다)
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_doc.warehouse_id) then              -- ⭐ 둘째
    raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_doc.doc_number;
  end if;
  select * into v_fin from public.wms_order_finalize f where coalesce(f.order_id, f.transfer_id) = p_so_id;
  if v_doc.doc_kind = 'transfer' and v_doc.status in ('in_transit', 'receiving', 'received') then   -- tr-2 묶음 5: 떠난 뒤 되돌리기 없음(출발 = 원장 · 레이어 · 예약 해제) · 떠나기 전(at_wms · picking)은 판매와 같은 검사로 간다
    raise exception 'Transfer % has left the warehouse (%) — there is no undo after departure; use the in-transit settlement return instead — nothing was saved', v_doc.doc_number, v_doc.status;
  end if;
  if p_action = 'finalize' then
    if v_doc.status <> 'packed' or coalesce(v_fin.order_id, v_fin.transfer_id) is null then raise exception 'Order % is not finalized (%) — nothing was saved', v_doc.doc_number, v_doc.status; end if;
  else
    if v_doc.status = 'packed' or coalesce(v_fin.order_id, v_fin.transfer_id) is not null then   -- SO-13893 벨트: Finalize 뒤에는 팩 · 픽 · 배치를 되돌리지 않는다
      raise exception 'Order % is finalized — use Undo Finalize first — nothing was saved', v_doc.doc_number;
    end if;
    if v_doc.status <> 'picking' then raise exception 'Order % is % — nothing to roll back here — nothing was saved', v_doc.doc_number, v_doc.status; end if;
  end if;
  v_status := v_doc.status;
  if p_action in ('finalize', 'fulfillment') then
    -- 팔렛 · 박스 · 담긴 것(운영 deleteFulfillmentRows) — 담긴 것 삭제 → 빈 유닛(담긴 것 0 · 자식 0) 삭제 · finalize 기록 삭제 · SO packed → picking
    v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_doc.doc_number, null, 'wms_pallet_items', format('coalesce(order_id, transfer_id) = %L', p_so_id));
    delete from public.wms_pallet_items where coalesce(order_id, transfer_id) = p_so_id;
    for i in 1 .. 2 loop                                               -- 두 단계: 빈 박스(자식) → 빈 팔렛(부모) · 담긴 것이 남은 유닛은 둔다(운영 deleteFulfillmentRows)
      v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_doc.doc_number, null, 'wms_pallets',
                  format('(coalesce(order_id, transfer_id) = %L or parent_id in (select id from public.wms_pallets where coalesce(order_id, transfer_id) = %L)) and not exists (select 1 from public.wms_pallet_items i where i.pallet_id = t.id) and not exists (select 1 from public.wms_pallets c where c.parent_id = t.id)', p_so_id, p_so_id));
      delete from public.wms_pallets u where (coalesce(u.order_id, u.transfer_id) = p_so_id or u.parent_id in (select id from public.wms_pallets where coalesce(order_id, transfer_id) = p_so_id))
        and not exists (select 1 from public.wms_pallet_items i where i.pallet_id = u.id) and not exists (select 1 from public.wms_pallets c where c.parent_id = u.id);
    end loop;
    if p_action = 'finalize' then
      v_arch := v_arch + public.wms_rb_archive(v_staff, p_action, p_so_id, v_doc.doc_number, null, 'wms_order_finalize', format('coalesce(order_id, transfer_id) = %L', p_so_id));
      delete from public.wms_order_finalize where coalesce(order_id, transfer_id) = p_so_id;
      perform public.wms_doc_status(v_doc.doc_kind, p_so_id, 'picking', v_staff);   -- tr-1b2
      v_status := 'picking';  v_orig := v_fin.finalized_by;
    end if;
    v_from := case p_action when 'finalize' then 'finalized' else 'fulfilled' end;  v_to := 'pack_complete';
  elsif p_action = 'pack' then
    if exists (select 1 from public.wms_pallet_items i where coalesce(i.order_id, i.transfer_id) = p_so_id) then raise exception 'Order % has items on pallets — Undo Fulfillment first — nothing was saved', v_doc.doc_number; end if;
    select coalesce(array_agg(id), '{}') into v_ids from public.wms_pack_tasks where coalesce(order_id, transfer_id) = p_so_id;
    select assigned_to into v_orig from public.wms_pack_tasks where coalesce(order_id, transfer_id) = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_doc.doc_number, null, 'wms_pack_tasks', format('coalesce(order_id, transfer_id) = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_doc.doc_number, null, 'wms_pack_task_lines', format('pack_task_id = any(%L::bigint[])', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pack_task_id', v_ids, c_pack, 'pack rollback (order ' || v_doc.doc_number || ')');
    update public.wms_worker_mistakes set reason = 'short_pick', resolved_by = null, resolved_at = null   -- 팩 회복을 다시 연다(오더 단위 · 규칙 14 양방향)
     where coalesce(order_id, transfer_id) = p_so_id and reason = 'resolved_pack_recovery' and voided_at is null and not manager_resolved;
    get diagnostics v_reopen = row_count;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pack', p_so_id, v_doc.doc_number, null, 'wms_pick_line_bins', format('pack_task_id = any(%L::bigint[])', v_ids));   -- 판정 57: 팩 회복 칸 행도 팩과 함께 간다(archive → 삭제 · FK cascade 는 안전망)
    delete from public.wms_pick_line_bins where pack_task_id = any(v_ids);
    delete from public.wms_pack_tasks where coalesce(order_id, transfer_id) = p_so_id;   -- 줄은 cascade
    v_from := 'pack_complete';  v_to := 'pick_complete';
  elsif p_action = 'pick' then
    if exists (select 1 from public.wms_pack_tasks k where coalesce(k.order_id, k.transfer_id) = p_so_id) then raise exception 'Order % has packing — Undo Pack first — nothing was saved', v_doc.doc_number; end if;
    select coalesce(array_agg(id), '{}') into v_ids from public.wms_pick_tasks where coalesce(order_id, transfer_id) = p_so_id;
    select assigned_to into v_orig from public.wms_pick_tasks where coalesce(order_id, transfer_id) = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_doc.doc_number, null, 'wms_pick_tasks', format('coalesce(order_id, transfer_id) = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_doc.doc_number, null, 'wms_pick_task_lines', format('pick_task_id = any(%L::bigint[])', v_ids));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'pick_reset', p_so_id, v_doc.doc_number, null, 'wms_pick_line_bins', format('not planned and pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(%L::bigint[]))', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', v_ids, array['short_pick'], 'pick reset (order ' || v_doc.doc_number || ')');
    delete from public.wms_pick_line_bins b where not b.planned and b.pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(v_ids));
    update public.wms_pick_task_lines set picked_base = 0, status = 'pending', verification_method = null, picked_at = null, picked_by = null where pick_task_id = any(v_ids);
    update public.wms_pick_tasks set status = 'pending', assigned_to = null, started_at = null, completed_at = null, completed_by = null, heartbeat_at = null, work_started = false, held_by = null, session_id = null where coalesce(order_id, transfer_id) = p_so_id;
    v_from := 'pick_complete';  v_to := 'pick_reset';
  else   -- split
    if exists (select 1 from public.wms_pack_tasks k where coalesce(k.order_id, k.transfer_id) = p_so_id) then raise exception 'Order % has packing — Undo Pack first — nothing was saved', v_doc.doc_number; end if;
    select coalesce(array_agg(id), '{}'), coalesce(array_agg(distinct wave_id) filter (where wave_id is not null), '{}') into v_ids, v_wids from public.wms_pick_tasks where coalesce(order_id, transfer_id) = p_so_id;
    select assigned_to into v_orig from public.wms_pick_tasks where coalesce(order_id, transfer_id) = p_so_id and assigned_to is not null limit 1;
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_doc.doc_number, null, 'wms_pick_tasks', format('coalesce(order_id, transfer_id) = %L', p_so_id));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_doc.doc_number, null, 'wms_pick_task_lines', format('pick_task_id = any(%L::bigint[])', v_ids));
    v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_doc.doc_number, null, 'wms_pick_line_bins', format('pick_task_line_id in (select id from public.wms_pick_task_lines where pick_task_id = any(%L::bigint[]))', v_ids));
    v_void := public.wms_rb_void(v_staff, 'pick_task_id', v_ids, array['short_pick'], 'split undo (order ' || v_doc.doc_number || ')');
    delete from public.wms_pick_tasks where coalesce(order_id, transfer_id) = p_so_id;   -- 줄 · 칸 행은 cascade
    foreach v_wid in array v_wids loop                                 -- 이 되돌리기로 빈 웨이브는 지운다(운영 doVoid 와 같다)
      if not exists (select 1 from public.wms_pick_tasks t where t.wave_id = v_wid) then
        v_arch := v_arch + public.wms_rb_archive(v_staff, 'split', p_so_id, v_doc.doc_number, null, 'wms_waves', format('id = %L', v_wid));
        delete from public.wms_waves where id = v_wid;
      end if;
    end loop;
    perform public.wms_doc_status(v_doc.doc_kind, p_so_id, 'at_wms', v_staff);   -- 과제 0 → 판정 18 · tr-1b2
    v_status := 'at_wms';  v_from := 'split';  v_to := 'unsplit';
  end if;
  insert into public.wms_rollback_log (order_id, transfer_id, order_number, action, from_stage, to_stage, performed_by, original_worker)
  values (case when v_doc.doc_kind = 'so' then p_so_id end, case when v_doc.doc_kind = 'transfer' then p_so_id end, v_doc.doc_number, p_action, v_from, v_to, v_staff, v_orig);
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_doc.doc_number, 'action', p_action, 'status', v_status, 'archived', v_arch, 'voided', v_void, 'reopened', v_reopen);
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
  trf_nl as (                                                            -- tr-2 2026-09-28 떠난 트랜스퍼(in_transit 부터)인데 출발 원장 짝(출발 창고 transfer_out · IN_TRANSIT transfer_in)이 없다 — 창고 마무리 트랜잭션이 끊겼다
    select x.transfer_number, x.status, x.departed_at, fw.name as from_warehouse,
           (select count(*) from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_out' and e.warehouse = fw.name) as out_rows,
           (select count(*) from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_in' and e.warehouse = 'IN_TRANSIT') as transit_rows
      from public.inv_transfer x join public.ref_warehouse fw on fw.id = x.from_warehouse_id
     where x.status in ('in_transit', 'receiving', 'received') and x.departed_at is not null
       and (not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_out' and e.warehouse = fw.name)
            or not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_in' and e.warehouse = 'IN_TRANSIT'))
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
      'transfer_out_passed',       v_ims_trd_out,           -- 출발 out 행 수(IN_TRANSIT in 이 처리) — skipped_by_event.transfer_out 에 안 잡힌다
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

-- ── inv_transfer_detail ──
create or replace function public.inv_transfer_detail(p_transfer_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not public.ims_can_view('transfer') then null::jsonb else (
    select jsonb_build_object(
      'header', to_jsonb(x) || jsonb_build_object('from_warehouse', fw.name, 'to_warehouse', tw.name, 'created_by_name', cb.name, 'confirmed_by_name', fb.name),
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', p.name, 'qty', l.qty, 'qty_sent', l.qty_sent, 'short_sent', case when l.qty_sent is not null and l.qty_sent < l.qty then l.qty - l.qty_sent end, 'pack_factor', l.pack_factor,
                                                              'qty_ea', l.qty * l.pack_factor, 'stock_product_id', coalesce(p.parent_product_id, p.id)) order by l.line_no), '[]'::jsonb)
                  from public.inv_transfer_line l join public.product p on p.id = l.product_id where l.transfer_id = x.id),
      'shortage', case when x.status = 'draft' then public.inv_transfer_shortage(x.id) else '[]'::jsonb end)
      from public.inv_transfer x
      join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = x.to_warehouse_id
      left join public.ims_staff cb on cb.id = x.created_by left join public.ims_staff fb on fb.id = x.confirmed_by
     where x.id = p_transfer_id) end;
$$;
