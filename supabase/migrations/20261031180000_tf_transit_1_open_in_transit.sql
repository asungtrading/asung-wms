-- tf-transit-1 (2026-10-31 · 판정 896) — 이미 떠난 Cin7 트랜스퍼를 IMS 트랜스퍼 「가는 중」 으로 열어 에드먼턴이 IMS 받기 화면으로 받는다
--   사실(Caleb · Cin7 화면): 10-26(월) 토론토 → 에드먼턴 트랜스퍼 4 장 = 한 트럭의 팔렛 넷(TR-06396 P1 · 06397 P2 · 06398 P3 · 06399 P4) · 컷오버 때문에 Cin7 에서 모두 VOIDED ·
--     물건은 실제로 떠났고 아직 도착 전(11-02 또는 11-03 짐작). 참조 SO-18288 · 18290 · 18291 은 손님 오더가 아니다(옛 WMS 픽용 · VOID) — IMS 에 다시 만들지 않는다.
--   원장(이 DB · 쓰기 0 · 2026-10-31 실측): 네 장 모두 source cin7 · occurred_on 10-26 · 출발 창고 transfer_out(−) + IN_TRANSIT transfer_in(+) 뿐 · 도착 다리 없음 ·
--     IN_TRANSIT 들어감 = 186 줄 1,512 · 293 줄 1,821 · 32 줄 349 · 88 줄 1,343(TR-06397 출고 −1,839 ≠ 들어감 +1,821 — bin 변경 이중 기입 6 SKU × 3 = 18 은 893 조정 몫 · 이 차수는 들어감 수량 기준).
--     IN_TRANSIT 레이어(parent_layer)도 같은 번호로 서 있다(1,512 · 1,803 · 349 · 1,343 — TR-06397 의 6 SKU 는 레이어 0 · 도착 때 short 18 이 기준값).
--   판정 896(Caleb 2026-10-31): 길 (다) — 원장의 cin7 출발은 그대로 두고 IMS 문서를 「가는 중」 으로 열어 에드먼턴이 기존 받기 화면(wms-receiver.html → wms_recv_start → … → wms_recv_complete → tf_arrive → inv_post_transfer_arrive)으로 받는다.
--   결정(Caleb 2026-10-31 · 이견 넷):
--     ① 번호 ⓒ — IMS transfer_number = Cin7 번호 그대로(TR-0639x). 도착 원가는 inv_layer_post_transfer_arrive → inv_layer_fifo_take(p_doc_scope = 문서 번호)가 **문서 번호 범위**의 IN_TRANSIT 레이어를 집으므로
--        번호가 같으면 함수 수정 0 으로 cin7 레이어가 이어지고, 문서별 IN_TRANSIT 원장도 같은 번호 안에서 0 이 된다. 재생성(inv_layer_apply)도 안전 — 불러온 축 inv_layer_apply_transfer_in 은 source ims 면 return ·
--        순액은 같은 날짜만(10-26) · ims leg 3/4 는 도착일이라 섞이지 않는다 · v_tr_unpaired 는 source <> 'ims'. TRF- 꼴을 파싱하는 코드 없음(grep: 마이그레이션 주석뿐 · asung-ims 0).
--     ② source = 'ims' 로 IN_TRANSIT 를 읽는 독자 둘을 이 차수에서 넓힌다(바이트 복사 + 조건 한 줄 · 마지막 정의 md5 대조):
--        tf_settle(v_rem · 부분 받기 뒤 lost · return 이 「nothing in transit」 로 거부되던 것) · wms_health_check(trf_nl — 네 장이 영구히 「출발 원장 짝 없음」 으로 뜨던 것 · trf_old 같은 까닭).
--     ③ Shopify 큐 — 줄을 넣으면 inv_transfer_line 트리거가 큐에 넣는다(끄지 않는다). in_transit 문서는 가용(inv_available_base · 트랜스퍼 예약은 confirmed · at_wms · picking 만)에 무접촉 → drain 은 skipped_same · Shopify 호출 0. 기준 = 보낼 값(shop_stock_payload) 전후 동일.
--     ④ inv_voided_docs 3772(TR-06397 · VOIDED · resolved null)는 ops 스크립트가 직접 resolved_at · resolution_note 로 닫는다 · 나머지 셋은 행을 만들지 않는다(수집기의 감지 기록이라 사람이 짓지 않는다 · 출처는 inv_transfer.note).
--   만드는 것: 1) inv_transfer_open_in_transit(p_doc_number, p_note) · 2) tf_settle 갈래 · 3) wms_health_check 갈래. ops: supabase/ops/tf-transit-1.sql(네 장 한 트랜잭션) · supabase/ops/tf-transit-arrive-manual.sql(대비책 (가) · 트럭이 먼저 오면 도착 줄을 SQL 로).
--   컷오버 지우는 순서: 새 표 없음 → 해당 없음(inv_transfer · inv_transfer_line 은 기존 표).
--   [운영 · Asung-IMS fazgmyvzzhqybtvtktyg] 적용: psql -1 -f + supabase migration repair --status applied 20261031180000 (db push 금지).

-- ═══ 1) inv_transfer_open_in_transit — 원장에 cin7 출발만 있는 트랜스퍼를 IMS 문서 「가는 중」 으로 연다(판정 896) ═══
create or replace function public.inv_transfer_open_in_transit(p_doc_number text, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_transfer_open_in_transit@2026-10-31.1';
        v_staff uuid; v_doc text; v_from_cin7 uuid; v_to_cin7 uuid; v_pairs int; v_f public.ref_warehouse%rowtype; v_t public.ref_warehouse%rowtype;
        v_in_rows int; v_other_src int; v_arrival int; v_days int; v_on date; v_at timestamptz; v_out_wh text; v_bad text;
        v_x public.inv_transfer%rowtype; v_n int; v_ea numeric;
begin
  perform public.ims_require_admin('a transfer opened from the stock book');                                   -- ⭐ 첫 줄 문 — admin 만(사람이 줄을 붙이지 않는 한 번짜리 창구)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  v_doc := upper(trim(coalesce(p_doc_number, '')));
  if v_doc !~ '^TR-[0-9]{5}$' then raise exception 'p_doc_number must be a Cin7 transfer number like TR-06398 (got %) — nothing was saved', coalesce(p_doc_number, '<null>'); end if;
  perform pg_advisory_xact_lock(hashtext('inv_transfer_open_in_transit:' || v_doc));                          -- 같은 번호 두 번 열기는 줄을 선다(유니크 제약이 두 번째를 막는다)
  if exists (select 1 from public.inv_transfer x where x.transfer_number = v_doc) then
    raise exception 'Transfer % already exists in IMS — nothing was saved', v_doc;
  end if;
  -- 원장 — 그 문서의 IN_TRANSIT 들어감 줄(leg 2 · source cin7)만이 줄의 원천이다(수량은 원장 그대로 · 사람이 줄을 붙이지 않는다)
  select count(*) into v_in_rows from public.inv_ledger e
   where e.doc_type = 'transfer' and e.doc_number = v_doc and e.warehouse = 'IN_TRANSIT' and e.event_type = 'transfer_in' and e.source = 'cin7';
  if v_in_rows = 0 then raise exception 'Transfer % has no in-transit arrival rows (IN_TRANSIT transfer_in · source cin7) in the stock book — nothing was saved', v_doc; end if;
  select count(*) into v_other_src from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = v_doc and e.source <> 'cin7';
  if v_other_src > 0 then raise exception 'Transfer % already has % non-cin7 ledger row(s) (ims or manual) — it is not a plain Cin7 departure — nothing was saved', v_doc, v_other_src; end if;
  select count(*) into v_arrival from public.inv_ledger e
   where e.doc_type = 'transfer' and e.doc_number = v_doc
     and ((e.warehouse = 'IN_TRANSIT' and e.event_type = 'transfer_out') or (e.warehouse <> 'IN_TRANSIT' and e.event_type = 'transfer_in'));
  if v_arrival > 0 then raise exception 'Transfer % already has an arrival leg in the stock book (% row(s)) — it cannot be opened as in transit — nothing was saved', v_doc, v_arrival; end if;
  -- 창고 — 원장 raw.header 의 Cin7 위치 id(from · to) → ref_warehouse.cin7_id · 짝은 하나여야 한다
  select count(*) into v_pairs from (select distinct e.raw -> 'header' ->> 'from', e.raw -> 'header' ->> 'to' from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = v_doc) d;
  if v_pairs <> 1 then raise exception 'Transfer % has % warehouse pairs in raw.header — expected exactly one — nothing was saved', v_doc, v_pairs; end if;
  select (e.raw -> 'header' ->> 'from')::uuid, (e.raw -> 'header' ->> 'to')::uuid into v_from_cin7, v_to_cin7
    from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = v_doc limit 1;
  select * into v_f from public.ref_warehouse w where w.cin7_id = v_from_cin7 and w.is_active;
  if not found then raise exception 'Transfer % — from warehouse (Cin7 %) is not an active IMS warehouse — nothing was saved', v_doc, v_from_cin7; end if;
  select * into v_t from public.ref_warehouse w where w.cin7_id = v_to_cin7 and w.is_active;
  if not found then raise exception 'Transfer % — to warehouse (Cin7 %) is not an active IMS warehouse — nothing was saved', v_doc, v_to_cin7; end if;
  if v_f.id = v_t.id then raise exception 'Transfer % — from and to are the same warehouse — nothing was saved', v_doc; end if;
  select min(e.warehouse) into v_out_wh from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = v_doc and e.event_type = 'transfer_out' and e.warehouse <> 'IN_TRANSIT';
  if v_out_wh is distinct from v_f.name then raise exception 'Transfer % — departure rows leave % but raw.header says % — nothing was saved', v_doc, coalesce(v_out_wh, '<none>'), v_f.name; end if;
  -- 날짜 — ims_today() 가 아니라 원장의 occurred_on(출발일 · 하루여야 한다) · departed_at 은 그날 토론토 정오(화면은 토론토 날짜로 그린다)
  select count(distinct e.occurred_on), min(e.occurred_on) into v_days, v_on from public.inv_ledger e
   where e.doc_type = 'transfer' and e.doc_number = v_doc and e.warehouse = 'IN_TRANSIT' and e.event_type = 'transfer_in' and e.source = 'cin7';
  if v_days <> 1 then raise exception 'Transfer % — in-transit rows span % departure dates — expected one — nothing was saved', v_doc, v_days; end if;
  v_at := (v_on + time '12:00') at time zone 'America/Toronto';
  -- 제품 — 원장 sku(낱개) 는 product 표의 활성 낱개여야 하고, 수량은 계수로 나누어떨어져야 한다
  create temp table if not exists t_tf_open (sku text primary key, qty_ea numeric not null, product_id uuid, pack_factor numeric) on commit drop;
  truncate t_tf_open;
  insert into t_tf_open (sku, qty_ea, product_id, pack_factor)
  select q.sku, q.qty_ea, p.id, coalesce(nullif(p.pack_factor, 0), 1)
    from (select e.sku, sum(e.qty_delta) as qty_ea from public.inv_ledger e
           where e.doc_type = 'transfer' and e.doc_number = v_doc and e.warehouse = 'IN_TRANSIT' and e.event_type = 'transfer_in' and e.source = 'cin7'
           group by e.sku) q
    left join public.product p on p.sku = q.sku and p.is_active and p.parent_product_id is null;
  select string_agg(sku, ', ' order by sku) into v_bad from t_tf_open where qty_ea <= 0;
  if v_bad is not null then raise exception 'Transfer % — in-transit quantity is not positive for %: % — nothing was saved', v_doc, v_bad, '(net of the ledger rows)'; end if;
  select string_agg(sku, ', ' order by sku) into v_bad from t_tf_open where product_id is null;
  if v_bad is not null then raise exception 'Transfer % — no active base product for sku(s) % — nothing was saved', v_doc, v_bad; end if;
  select string_agg(sku, ', ' order by sku) into v_bad from t_tf_open where qty_ea <> trunc(qty_ea / pack_factor) * pack_factor;
  if v_bad is not null then raise exception 'Transfer % — quantity is not a whole number of units for sku(s) % — nothing was saved', v_doc, v_bad; end if;
  -- 문서 — 상태 「가는 중」 · 확정 · WMS · 픽 · 출발 시각은 전부 출발일(원장 쓰기 0 · 출발은 이미 cin7 줄로 있다)
  insert into public.inv_transfer (transfer_number, status, from_warehouse_id, to_warehouse_id, note, created_by, confirmed_by, confirmed_at, at_wms_at, picking_at, departed_at, departed_by, updated_by)
  values (v_doc, 'in_transit', v_f.id, v_t.id, nullif(trim(coalesce(p_note, '')), ''), v_staff, v_staff, v_at, v_at, v_at, v_at, v_staff, v_staff)
  returning * into v_x;
  -- 줄 — SKU 순 · qty = 보낸 수량 = 원장 EA ÷ 계수(판정 74 · 받기는 qty_sent × pack_factor 를 기대로 읽는다)
  insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor, qty_sent, updated_by)
  select v_x.id, row_number() over (order by t.sku), t.product_id, t.sku, t.qty_ea / t.pack_factor, t.pack_factor, t.qty_ea / t.pack_factor, v_staff
    from t_tf_open t;
  get diagnostics v_n = row_count;
  select coalesce(sum(l.qty_sent * l.pack_factor), 0) into v_ea from public.inv_transfer_line l where l.transfer_id = v_x.id;
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'status', v_x.status,
                            'from_warehouse_id', v_f.id, 'from_warehouse', v_f.name, 'to_warehouse_id', v_t.id, 'to_warehouse', v_t.name,
                            'departed_on', v_on, 'departed_at', v_x.departed_at, 'line_count', v_n, 'qty_ea', v_ea, 'ledger_in_rows', v_in_rows, 'note', v_x.note, 'opened_by', v_staff, 'poster', c_version);
end;
$$;
revoke all on function public.inv_transfer_open_in_transit(text, text) from public, anon;
grant execute on function public.inv_transfer_open_in_transit(text, text) to authenticated;
comment on function public.inv_transfer_open_in_transit(text, text) is
  'tf-transit-1(판정 896 · 2026-10-31) — 원장에 cin7 출발(출발 창고 transfer_out · IN_TRANSIT transfer_in)만 있는 Cin7 트랜스퍼를 IMS 문서 「가는 중」(in_transit) 으로 연다 · 번호 = Cin7 번호 그대로(원가 · 운송 중 잔고 · 정리가 같은 문서 번호에서 이어진다) · 줄 = 원장 IN_TRANSIT 들어감 줄(SKU × 수량) · 원장 쓰기 0 · admin 만 · 거부: 이미 있음 · 들어감 줄 0 · cin7 아닌 줄 있음 · 도착 다리 있음 · 창고 짝 둘 · 출발일 둘 · 제품 없음/비활성 · 계수 안 맞음. 컷오버 날 떠나 있던 TR-06396 ~ 06399(2026-10-26 · 한 트럭 팔렛 넷)를 위해 — supabase/ops/tf-transit-1.sql';


-- ═══ 2) tf_settle — 마지막 정의(20260929014246_transfer_3b · DB prosrc md5 a100eb24c61c69f63af69905f543b6d8) 바이트 복사 + 갈래(v_rem · 42 ~ 44 행) ═══
CREATE OR REPLACE FUNCTION public.tf_settle(p_transfer_id uuid, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare c_version constant text := 'tf_settle@2026-10-31.1';   -- tf-transit-1(판정 896): 잔고 셈에 ims 아닌 줄을 더했다(아래 v_rem)
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
     where e.doc_type = 'transfer' and e.doc_number = v_x.transfer_number and e.warehouse = 'IN_TRANSIT' and e.sku = v_base
       and ((e.source = 'ims' and (e.line_ref = v_l.id::text or e.line_ref like v_l.id::text || ':%'))
            or e.source <> 'ims');   -- tf-transit-1(판정 896 · 2026-10-31): 원장에서 연 문서(inv_transfer_open_in_transit)는 들어감 줄이 cin7(line_ref = ProductID)이라 같은 문서 · SKU 의 ims 아닌 줄도 잔고에 센다 · TRF- 문서에는 ims 아닌 줄이 없어 결과 같다
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
$function$

;

-- ═══ 3) wms_health_check — 마지막 정의(20260929195458_inv_basis_2 · DB prosrc md5 930f5c813797d4b91fe8f0e1969aa84e) 바이트 복사 + 갈래(trf_nl 4 곳 · trf_old 1 곳) ═══
CREATE OR REPLACE FUNCTION public.wms_health_check()
 RETURNS TABLE(sort integer, check_key text, category text, title text, hint text, fail_count bigint, sample jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  offinv_und as (                                                        -- inv-basis-3 off-invoice(판정 88 ⑧)가 정해지지 않은 채 24h — 선반에는 있고 장부에는 없다
    select r.receipt_number, pr.sku, d.received_qty - d.expected_qty as extra_qty, (d.po_line_id is not null) as on_po_line, (d.placed_at is not null) as on_shelf, b.name as bin, d.created_at
      from public.po_receipt_diff d
      join public.po_receipt r on r.id = d.receipt_id
      join public.product pr on pr.id = d.product_id
      left join public.ref_bin b on b.id = d.bin_id
     where d.kind = 'off_invoice' and d.resolved_at is null and d.created_at < now() - c_stale
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
  trf_nl as (                                                            -- tr-2 2026-09-28 떠난 트랜스퍼(in_transit 부터)인데 출발 원장 짝(출발 창고 transfer_out · IN_TRANSIT transfer_in)이 없다 — 창고 마무리 트랜잭션이 끊겼다   -- tf-transit-1(판정 896 · 2026-10-31): 원장에서 연 문서(inv_transfer_open_in_transit · 출발 줄이 cin7)도 짝으로 센다 — source in ('ims','cin7') · TRF- 문서에는 cin7 줄이 없어 결과 같다
    select x.transfer_number, x.status, x.departed_at, fw.name as from_warehouse,
           (select count(*) from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source in ('ims', 'cin7') and e.event_type = 'transfer_out' and e.warehouse = fw.name) as out_rows,
           (select count(*) from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source in ('ims', 'cin7') and e.event_type = 'transfer_in' and e.warehouse = 'IN_TRANSIT') as transit_rows
      from public.inv_transfer x join public.ref_warehouse fw on fw.id = x.from_warehouse_id
     where x.status in ('in_transit', 'receiving', 'received') and x.departed_at is not null
       and (not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source in ('ims', 'cin7') and e.event_type = 'transfer_out' and e.warehouse = fw.name)
            or not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source in ('ims', 'cin7') and e.event_type = 'transfer_in' and e.warehouse = 'IN_TRANSIT'))
  ),
  trf_rnl as (                                                           -- tr-3a 받은 트랜스퍼(received)인데 도착 원장(도착 창고 transfer_in · 그 입고)이 없다 — Complete 트랜잭션이 끊겼다
    select x.transfer_number, r.receipt_number, x.received_at, tw.name as to_warehouse
      from public.inv_transfer x join public.ref_warehouse tw on tw.id = x.to_warehouse_id
      join public.po_receipt r on r.transfer_id = x.id and r.status = 'confirmed'
     where x.status = 'received'
       and not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_in'
                         and e.warehouse = tw.name and e.raw -> 'header' ->> 'receipt_number' = r.receipt_number)
  ),
  trf_old as (                                                           -- tr-3a 묶음 10 의 8: 떠난 지 30일이 넘었는데 운송 중에 남은 몫(IN_TRANSIT 잔고 > 0 · 다 못 받았거나 아직 안 받았다) — 매니저 정리(분실 / 되돌리기)   -- tf-transit-1(판정 896): 같은 까닭으로 IN_TRANSIT 잔고를 ims + cin7 로 센다
    select x.transfer_number, x.status, x.departed_at, s.remaining_ea
      from public.inv_transfer x
      join (select e.doc_number, sum(e.qty_delta) as remaining_ea from public.inv_ledger e where e.doc_type = 'transfer' and e.source in ('ims', 'cin7') and e.warehouse = 'IN_TRANSIT' group by e.doc_number) s on s.doc_number = x.transfer_number
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
  select 151, 'off_invoice_undecided', 'warn', 'Off-invoice item waiting for a decision for 24h',
    'Goods received beyond the confirmed invoice (more than invoiced, an item the invoice does not have, or an item not on the PO) have been waiting more than 24 hours for the office to accept them (free or billed). Until then they sit on the shelf but not in the books - decide them in Purchase Receipts.',
    (select count(*) from offinv_und), (select jsonb_agg(t) from (select * from offinv_und limit 8) t)
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
$function$

;
