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

-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- tr-4b — 창고 간 트랜스퍼 ⑤-2: 얹힌 원가(PO 운임 · 관세 · 트랜스퍼 운임)가 IMS 트랜스퍼를 따라간다(판정 79) · 도착 순간 운임 저절로(판정 78) · 2026-09-29
--   조사(§1 A · 보고 1): 소진 금액(inv_layer_consume.amount)은 어느 소진(판매 · 조정 · 트랜스퍼)이든 qty × 레이어 unit_cost 뿐 — 얹힌 금액(inv_layer_cost_add)은 매출원가에 안 들어간다 ·
--     inv_layer_open 의 남은 원가는 (unit_cost × qty + 얹힌 합) / qty × 남은 수량 — 두 셈은 다른 규칙이다(이 차수는 판매 소진 규칙 무변 · 얹힌 원가는 남은 원가 축으로 따라간다)
--   ① inv_layer_cost_add.kind 에 'carried'(따라온 얹힌 원가) — 자식 레이어에 부모의 얹힌 행을 한 병당 비율로 비춘 행 · doc_number · line_ref · occurred_on 은 원래 행 그대로 · ref_number = layer:<부모 id>:<원래 kind>
--   ② inv_layer_carry(레이어) — 그 레이어가 IMS 트랜스퍼의 자식(origin transfer · parent 있음 · 문서가 inv_transfer 에 있음)이면 부모의 얹힌 행(모든 kind)마다 round(금액 × 자식 qty ÷ 부모 처음 qty, 6) 을 아직 없는 것만 넣고(멱등) ·
--      그 레이어의 IMS 자식으로 내려간다(사슬: 출발 창고 → IN_TRANSIT → 도착 창고 · 되돌림 · 더 보낸 몫) · 불러온 데이터 축의 트랜스퍼(문서가 inv_transfer 에 없다)는 건드리지 않는다 · inv_layer_fifo_take 무접촉(판매 · 조정 · 불러온 축이 같은 손을 쓴다)
--      불변식: 자식의 carried = 부모 얹힌 행 × 자식 qty ÷ 부모 qty — 자식이 먼저 섰든(창구가 세울 때) 얹힌 행이 나중에 왔든(inv_layer_post_charge 가 얹은 뒤 내려보낸다) 같은 결과 · 재생성 마지막 바퀴도 같은 함수
--   ③ inv_layer_post_transfer_depart · _arrive · _settle 재발행 — fifo_take 뒤 새 자식마다 inv_layer_carry · 반환에 carried_rows · carried_amount 키(lost 는 자식이 없어 얹힌 몫도 소진과 함께 사라진다)
--   ④ inv_layer_post_charge 재발행 — 얹은 레이어마다 inv_layer_carry(이미 떠난 몫에도) · 문에 wms_receiving(도착 창구 · 발주 배분 없는 문서만 · 판정 78) · 반환에 carried_rows 키(따라간 행이 있을 때만 — 발주 반환 모양 무변)
--   ⑤ tf_arrive 재발행(판정 78) — 원장 · 레이어 뒤 그 트랜스퍼에 배분된 확정 · 미적용 운임을 inv_layer_post_charge 로 얹는다 · 창구가 거부해도 도착은 된다(판정 65 · freight.errors) · 반환에 freight 키
--      나눠 도착(두 번 Complete)은 지금 구조에 없다 — tf_arrive 는 in_transit · receiving 에서만 · received 뒤의 남은 운송 중 몫은 tf_settle(lost · return) 로만 · 그래서 두 번째 도착의 새 레이어 문제는 생기지 않는다
--   ⑥ inv_layer_apply 재발행 — 얹힌 행 블록들(불러온 landed · transfer_freight · IMS 비용) 뒤 마지막 바퀴: IMS 자식 레이어를 id 순으로 inv_layer_carry · ims 키 carried_rows · carried_amount_cad
--   ⑦ inv_transfer_detail — 줄마다 carried {in_transit · arrived · returned · total}(화면 ⑥ 재료 · 키 추가만)
--   ⭐ 약속: 발주 비용 · 발주 입고 · 판매 · 조정 · 칸 옮기기 · 불러온 데이터 축의 원가 무변(L8 · L10) · 판매 소진 규칙 무변(L3 는 그 사실을 보인다)
--   ⚠️ UTC 이름 · 가드 첫 문장 · begin/commit 없음 · 재발행 = 마지막 정의 바이트 그대로 + 바꾼 줄(원본: depart 20260929003624 · arrive · tf_arrive 20260929010938 · settle 20260929014246 · post_charge · apply · transfer_detail 20260929021949)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ── ① 어휘 ──
alter table public.inv_layer_cost_add drop constraint inv_layer_cost_add_kind_ck;
alter table public.inv_layer_cost_add add constraint inv_layer_cost_add_kind_ck check (kind in ('landed', 'transfer_freight', 'carried'));
comment on column public.inv_layer_cost_add.kind is 'landed(입고 원가에 얹은 비용 · 불러온 축과 IMS 비용) · transfer_freight(불러온 축 트랜스퍼 운송비) · carried(tr-4b 판정 79 — IMS 트랜스퍼 자식 레이어로 따라온 부모의 얹힌 원가 · 한 병당 비율 · ref_number = layer:<부모 id>:<원래 kind>)';

-- ── ② 따라가기 ──
create function public.inv_layer_carry(p_layer_id bigint) returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_y public.inv_layer%rowtype; v_p public.inv_layer%rowtype; v_n int := 0; v_k int := 0; v_c record;
begin
  select * into v_y from public.inv_layer y where y.id = p_layer_id;
  if not found then return 0; end if;
  -- ① 이 레이어가 IMS 트랜스퍼의 자식이면 부모의 얹힌 행을 비춘다 — 아직 없는 (doc_number · line_ref · occurred_on) 만(멱등) · 금액 = 원래 금액 × 자식 처음 qty ÷ 부모 처음 qty · 6자리
  if v_y.origin_type = 'transfer' and v_y.parent_layer_id is not null and exists (select 1 from public.inv_transfer t where t.transfer_number = v_y.doc_number) then
    select * into v_p from public.inv_layer p where p.id = v_y.parent_layer_id;
    if found and v_p.qty > 0 then
      insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
      select v_y.id, 'carried', round(a.amount * v_y.qty / v_p.qty, 6), a.occurred_on, a.doc_number, a.line_ref, 'layer:' || v_p.id::text || ':' || a.kind
        from public.inv_layer_cost_add a
       where a.layer_id = v_p.id
         and not exists (select 1 from public.inv_layer_cost_add m where m.layer_id = v_y.id and m.kind = 'carried' and m.doc_number = a.doc_number and m.line_ref = a.line_ref and m.occurred_on = a.occurred_on)
       order by a.id;
      get diagnostics v_k = row_count;
      v_n := v_n + v_k;
    end if;
  end if;
  -- ② 이 레이어의 IMS 자식으로 내려간다(사슬 · 얹힌 행이 나중에 온 경우 = 이미 떠난 몫)
  for v_c in select c.id from public.inv_layer c where c.parent_layer_id = p_layer_id and c.origin_type = 'transfer' and exists (select 1 from public.inv_transfer t where t.transfer_number = c.doc_number) order by c.id loop
    v_n := v_n + public.inv_layer_carry(v_c.id);
  end loop;
  return v_n;
end;
$$;
-- ⚠️ 회수하지 않는다(판정 31 의 예외 · 근거): 부르는 창구 inv_layer_post_charge 가 invoker 라(tr-4 · 발주 비용 무변) 회수된 속을 못 부른다. 이 함수는 입력이 레이어 id 하나이고
--    넣는 행이 불변식(자식 carried = 부모 얹힌 행 × 자식 qty ÷ 부모 qty)으로 정해지며 없는 것만 넣는다(멱등) — 누가 불러도 재생성이 넣을 행 외에는 생기지 않는다 · 임의 금액 · 임의 문서를 넣을 길이 없다.
revoke all on function public.inv_layer_carry(bigint) from public, anon;
grant execute on function public.inv_layer_carry(bigint) to authenticated;
comment on function public.inv_layer_carry(bigint) is 'tr-4b(판정 79) — IMS 트랜스퍼 자식 레이어에 부모의 얹힌 원가(landed · transfer_freight · carried)를 한 병당 비율로 비춘 carried 행을 넣고(멱등 · 없는 것만) 그 자식의 IMS 자식으로 내려간다 · 넣은 행 수를 돌려준다 · 창구(depart · arrive · settle · post_charge)와 재생성 마지막 바퀴가 같은 함수를 쓴다 · 불러온 축 트랜스퍼 무접촉 · authenticated 에 허용(불변식으로 정해진 행만 · 멱등 · invoker 창구가 부른다)';

-- ── ③ 트랜스퍼 원가 창구 셋 재발행(자식마다 inv_layer_carry) ──
create or replace function public.inv_layer_post_transfer_depart(p_doc_number text, p_line_ref text, p_sku text, p_from_warehouse text, p_qty numeric, p_occurred_on date, p_hint jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_layer_post_transfer_depart@2026-09-29.1';   -- tr-4b: 얹힌 원가 따라가기(판정 79)
        v_rows int; v_short int; v_layers int; v_taken numeric; v_amt numeric; v_child record; v_carried int := 0; v_carried_amt numeric := 0;
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
  -- tr-4b(판정 79): 새로 선 자식 레이어마다 부모에 얹힌 원가(landed · transfer_freight · carried)를 한 병당 비율로 따라가게 한다(inv_layer_carry · 멱등)
  for v_child in select y.id from public.inv_layer y where y.origin_type = 'transfer' and y.doc_number = p_doc_number and y.line_ref = p_line_ref and y.warehouse = 'IN_TRANSIT' and y.parent_layer_id is not null order by y.id loop
    v_carried := v_carried + public.inv_layer_carry(v_child.id);
  end loop;
  select coalesce(sum(ca.amount), 0) into v_carried_amt from public.inv_layer_cost_add ca join public.inv_layer y on y.id = ca.layer_id
   where ca.kind = 'carried' and y.origin_type = 'transfer' and y.doc_number = p_doc_number and y.line_ref = p_line_ref and y.warehouse = 'IN_TRANSIT';
  -- 부족(출발 창고 레이어 < 보낸 EA)은 short 로 남긴다 — 불러온 축의 창고 출발 규칙과 같다(원가 미상 레이어를 세우지 않는다 · 운송 중 수량은 원장이 말한다 · 도착 ④ 가 같은 부족을 다시 본다)
  return jsonb_build_object('sku', p_sku, 'from_warehouse', p_from_warehouse, 'qty', p_qty, 'line_ref', p_line_ref,
                            'taken', coalesce(v_taken, 0), 'consume_rows', coalesce(v_rows, 0), 'layers', coalesce(v_layers, 0), 'short', coalesce(v_short, 0), 'short_qty', p_qty - coalesce(v_taken, 0),
                            'amount', v_amt, 'carried_rows', v_carried, 'carried_amount', v_carried_amt, 'reproduced', p_hint is not null, 'builder', c_version);
end;
$$;

create or replace function public.inv_layer_post_transfer_arrive(p_doc_number text, p_line_ref text, p_sku text, p_to_warehouse text, p_qty numeric, p_occurred_on date, p_hint jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_layer_post_transfer_arrive@2026-09-29.1';   -- tr-4b: 얹힌 원가 따라가기(판정 79)
        v_rows int; v_short int; v_layers int; v_taken numeric; v_amt numeric; v_child record; v_carried int := 0; v_carried_amt numeric := 0;
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
  -- tr-4b(판정 79): 새로 선 자식 레이어마다 부모에 얹힌 원가(landed · transfer_freight · carried)를 한 병당 비율로 따라가게 한다(inv_layer_carry · 멱등)
  for v_child in select y.id from public.inv_layer y where y.origin_type = 'transfer' and y.doc_number = p_doc_number and y.line_ref = p_line_ref and y.warehouse = p_to_warehouse and y.parent_layer_id is not null order by y.id loop
    v_carried := v_carried + public.inv_layer_carry(v_child.id);
  end loop;
  select coalesce(sum(ca.amount), 0) into v_carried_amt from public.inv_layer_cost_add ca join public.inv_layer y on y.id = ca.layer_id
   where ca.kind = 'carried' and y.origin_type = 'transfer' and y.doc_number = p_doc_number and y.line_ref = p_line_ref and y.warehouse = p_to_warehouse;
  return jsonb_build_object('sku', p_sku, 'to_warehouse', p_to_warehouse, 'qty', p_qty, 'line_ref', p_line_ref,
                            'taken', coalesce(v_taken, 0), 'consume_rows', coalesce(v_rows, 0), 'layers', coalesce(v_layers, 0), 'short', coalesce(v_short, 0), 'short_qty', p_qty - coalesce(v_taken, 0),
                            'amount', v_amt, 'carried_rows', v_carried, 'carried_amount', v_carried_amt, 'reproduced', p_hint is not null, 'builder', c_version);
end;
$$;

create or replace function public.inv_layer_post_transfer_settle(p_doc_number text, p_line_ref text, p_sku text, p_qty numeric, p_action text, p_dest_warehouse text, p_occurred_on date, p_from_warehouse text default null, p_hint jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_layer_post_transfer_settle@2026-09-29.1';   -- tr-4b: 얹힌 원가 따라가기(판정 79 · return · sent_more)
        v_rows int; v_short int; v_layers int; v_taken numeric; v_amt numeric; v_src text; v_reason text; v_scope text; v_child record; v_carried int := 0; v_carried_amt numeric := 0;
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
  if p_action <> 'lost' then                                                                -- lost 는 자식이 없다 — 얹힌 몫도 소진과 함께 사라진다(판정 77 과 같은 결)
    -- tr-4b(판정 79): 새로 선 자식 레이어마다 부모에 얹힌 원가(landed · transfer_freight · carried)를 한 병당 비율로 따라가게 한다(inv_layer_carry · 멱등)
    for v_child in select y.id from public.inv_layer y where y.origin_type = 'transfer' and y.doc_number = p_doc_number and y.line_ref = p_line_ref and y.warehouse = p_dest_warehouse and y.parent_layer_id is not null order by y.id loop
      v_carried := v_carried + public.inv_layer_carry(v_child.id);
    end loop;
    select coalesce(sum(ca.amount), 0) into v_carried_amt from public.inv_layer_cost_add ca join public.inv_layer y on y.id = ca.layer_id
     where ca.kind = 'carried' and y.origin_type = 'transfer' and y.doc_number = p_doc_number and y.line_ref = p_line_ref and y.warehouse = p_dest_warehouse;
  end if;
  return jsonb_build_object('action', p_action, 'sku', p_sku, 'from', v_src, 'to', case when p_action = 'lost' then null else p_dest_warehouse end, 'qty', p_qty, 'line_ref', p_line_ref,
                            'taken', coalesce(v_taken, 0), 'consume_rows', coalesce(v_rows, 0), 'layers', coalesce(v_layers, 0), 'short', coalesce(v_short, 0), 'short_qty', p_qty - coalesce(v_taken, 0),
                            'amount', v_amt, 'carried_rows', v_carried, 'carried_amount', v_carried_amt, 'reproduced', p_hint is not null, 'builder', c_version);
end;
$$;

-- ── ④ 비용 창구 재발행(얹은 뒤 따라가기 · 도착 창구의 문) ──
create or replace function public.inv_layer_post_charge(p_charge_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_version    constant text := 'inv_layer_post_charge@2026-09-29.2';   -- tr-4: 트랜스퍼 배분 갈래(판정 67 · 77 · 묶음 일곱) · tr-4b: 얹은 뒤 자식 레이어로 따라가기(판정 79) · 도착 창구의 문(판정 78)
  v_chg        public.po_charge%rowtype;
  v_cur        text;
  v_base_cur   text;
  v_factor     numeric;                -- 청구 통화 → CAD 계수. 기준통화면 1 · 아니면 po_charge.exchange_rate(CAD per 통화)
  v_alloc      record;
  v_lay        record;
  v_basis      numeric;
  v_n_layers   int;
  v_amount_cad numeric;
  v_share      numeric;
  v_given      numeric;
  v_i          int;
  v_touched    int := 0;
  v_posted     numeric := 0;
  v_no_basis   int := 0;  v_no_basis_amt numeric := 0;
  v_no_layers  int := 0;  v_no_layers_amt numeric := 0;
  v_already    int := 0;  v_already_amt numeric := 0;
  v_allocs     jsonb := '[]'::jsonb;
  v_lines      jsonb;
  v_warn       text[] := '{}';
  v_po_number  text;                   -- 발주 번호 · 트랜스퍼 배분이면 트랜스퍼 번호(cost_add.ref_number)
  v_ref        jsonb;
  v_carried    int := 0;               -- tr-4b: 얹은 레이어의 IMS 자식(운송 중 · 도착 창고)으로 따라간 행 수(inv_layer_carry)                  -- tr-4: 배분 줄 반환에 더하는 키(트랜스퍼면 transfer_id · transfer_number · 발주면 빈 객체 — 발주 반환 모양 무변)
begin
  -- 문 — 구매 열쇠(발주 비용 · 지금까지와 같다) · tr-4: transfer 열쇠는 발주 배분이 하나도 없는 비용만(트랜스퍼 운임 · 묶음 일곱 3)
  if not public.ims_can_write('purchasing') then
    if not ((public.ims_can_write('transfer') or public.ims_can_write('wms_receiving')) and not exists (select 1 from public.po_charge_alloc a where a.po_charge_id = p_charge_id and a.po_id is not null)) then   -- tr-4b(판정 78): 도착 창구(wms_receiving)가 도착 순간 트랜스퍼 운임을 얹는다
      perform public.ims_require_write('purchasing', 'posted');
    end if;
  end if;

  select * into v_chg from public.po_charge where id = p_charge_id;
  if not found then raise exception 'Charge % not found — no cost was added', p_charge_id; end if;
  if v_chg.status <> 'confirmed' or v_chg.confirmed_at is null then
    raise exception 'Charge % is % — cost is added for confirmed charges only — no cost was added', v_chg.charge_number, v_chg.status;
  end if;

  -- 통화 · 환율 (confirm 이 먼저 막지만 직접 호출·백필 경로도 여기서 막는다)
  select c.code into v_cur from public.ref_currency c where c.id = v_chg.currency_id;
  select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
  if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which charges need an exchange rate — no cost was added'; end if;
  if v_cur is distinct from v_base_cur then
    if v_chg.exchange_rate is null or v_chg.exchange_rate <= 0 then
      raise exception 'Charge % is in % but has no % per % exchange rate — the cost cannot be put on stock without it. Enter the rate on the charge and confirm again — no cost was added',
        v_chg.charge_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
    end if;
    -- ⚠️⚠️⚠️ po_charge.exchange_rate 는 CAD per USD 다 — amount(USD) × exchange_rate = CAD. 곱한다. 나누면 반값인데 에러가 안 난다.
    v_factor := v_chg.exchange_rate;
  else
    v_factor := 1;                                                                                          -- 기준통화(CAD) — 곱하지 않는다
    if v_chg.exchange_rate is not null and v_chg.exchange_rate <> 1 then v_warn := array_append(v_warn, 'exchange_rate_ignored_base_currency'); end if;
  end if;
  if v_chg.total_amount < 0 then v_warn := array_append(v_warn, 'negative_amount'); end if;

  if not exists (select 1 from public.po_charge_alloc a where a.po_charge_id = p_charge_id) then
    raise exception 'Charge % has no allocation lines — nothing to put on cost — no cost was added', v_chg.charge_number;
  end if;

  -- 배분 줄마다(발주 또는 트랜스퍼 — 정확히 하나 · tr-4)
  for v_alloc in
    select a.id, a.po_id, a.amount, p.po_number, a.transfer_id, t.transfer_number
    from public.po_charge_alloc a left join public.po p on p.id = a.po_id left join public.inv_transfer t on t.id = a.transfer_id
    where a.po_charge_id = p_charge_id
    order by p.po_number, t.transfer_number
  loop
    v_po_number  := coalesce(v_alloc.po_number, v_alloc.transfer_number);
    if v_alloc.transfer_id is not null and v_alloc.transfer_number is null then                                    -- tr-4: 이 로그인이 못 보는 트랜스퍼(RLS) — 조용히 0 을 얹지 않는다 · transfer 열쇠(또는 그 창고 열쇠)로
      raise exception 'Charge % is allocated to a transfer this login cannot see — the transfer key (or a warehouse key for that transfer) is needed — no cost was added', v_chg.charge_number;
    end if;
    v_ref        := case when v_alloc.transfer_id is not null then jsonb_build_object('transfer_id', v_alloc.transfer_id, 'transfer_number', v_alloc.transfer_number) else '{}'::jsonb end;
    -- ⚠️⚠️⚠️ CAD per USD × 청구 통화 금액 = CAD. 곱한다.
    v_amount_cad := v_alloc.amount * v_factor;

    -- 멱등 — 이 비용·이 배분 줄로 이미 얹은 행이 있으면 건너뛴다(이견 4)
    if exists (select 1 from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = v_chg.charge_number and ca.line_ref = v_alloc.id::text) then
      v_already := v_already + 1; v_already_amt := v_already_amt + v_amount_cad;
      v_allocs := v_allocs || (jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_alloc.po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                                 'status', 'already_posted', 'layers', 0, 'posted_cad', 0) || v_ref);
      continue;
    end if;

    -- 그 발주의 IMS 입고 레이어 — po_line 을 거쳐(이견 1) · 불러온 레이어는 cost_source 로 갈린다(이견 2)
    -- tr-4 트랜스퍼: 그 문서의 도착 레이어(origin transfer · doc_number TRF-n · 도착 창고 — leg 4 · sent_more over_4) · return(:settle: · 출발 창고) 제외 · found 는 조정 문서 레이어라 안 걸린다 · lost 는 레이어가 없다(판정 77 — 도착한 물건이 전부 떠안는다)
    select count(*), coalesce(sum(x.unit_cost * x.qty), 0)
      into v_n_layers, v_basis
    from public.inv_layer x
    left join public.po_line pl on pl.id::text = x.line_ref
    where (x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_alloc.po_id)
       or (v_alloc.transfer_id is not null and x.origin_type = 'transfer' and x.doc_number = v_alloc.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%');

    if v_n_layers = 0 then
      v_no_layers := v_no_layers + 1; v_no_layers_amt := v_no_layers_amt + v_amount_cad;
      v_allocs := v_allocs || (jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_alloc.po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                                 'status', 'no_layers', 'layers', 0, 'posted_cad', 0) || v_ref);
      continue;
    end if;
    if v_basis = 0 then
      -- 정본 D — 기준이 0 이면 버린다 · 수량 비례로 대신하지 않는다(Cin7 CostDistributionType='Cost' 와 방식이 갈린다)
      v_no_basis := v_no_basis + 1; v_no_basis_amt := v_no_basis_amt + v_amount_cad;
      v_allocs := v_allocs || (jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_alloc.po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                                 'status', 'no_basis', 'layers', v_n_layers, 'posted_cad', 0) || v_ref);
      continue;
    end if;

    -- 금액 비율(unit_cost × qty · 정본 B) · 6자리 · 끝수는 마지막 레이어
    v_given := 0; v_i := 0; v_lines := '[]'::jsonb;
    for v_lay in
      select x.id, x.sku, x.warehouse, x.line_ref, x.qty, x.unit_cost, x.unit_cost * x.qty as basis
      from public.inv_layer x
      left join public.po_line pl on pl.id::text = x.line_ref
      where (x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_alloc.po_id)
         or (v_alloc.transfer_id is not null and x.origin_type = 'transfer' and x.doc_number = v_alloc.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%')
      order by x.sku, x.line_ref, x.id
    loop
      v_i := v_i + 1;
      if v_i = v_n_layers then
        v_share := v_amount_cad - v_given;                                                                -- 마지막 레이어에 잔액 — 합이 정확히 금액과 같다
      else
        v_share := round(v_amount_cad * v_lay.basis / v_basis, 6);
      end if;
      v_given := v_given + v_share;
      insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
      values (v_lay.id, 'landed', v_share, v_chg.charge_date, v_chg.charge_number, v_alloc.id::text, v_po_number);
      v_touched := v_touched + 1;
      v_carried := v_carried + public.inv_layer_carry(v_lay.id);                                            -- tr-4b: 이미 떠난 몫(IMS 자식)에도 한 병당 비율로(판정 79 · 재생성과 같은 규칙)
      v_lines := v_lines || jsonb_build_object('layer_id', v_lay.id, 'sku', v_lay.sku, 'warehouse', v_lay.warehouse, 'po_line_id', v_lay.line_ref,
                                               'qty', v_lay.qty, 'unit_cost', v_lay.unit_cost, 'basis', v_lay.basis, 'share_cad', v_share);
    end loop;
    v_posted := v_posted + v_given;
    v_allocs := v_allocs || (jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_alloc.po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                               'status', 'posted', 'layers', v_n_layers, 'basis', v_basis, 'posted_cad', v_given, 'lines', v_lines) || v_ref);
  end loop;

  return jsonb_build_object(
    'charge_id', v_chg.id, 'charge_number', v_chg.charge_number, 'charge_kind', v_chg.kind, 'cost_add_kind', 'landed', 'charge_date', v_chg.charge_date,
    'currency', v_cur, 'base_currency', v_base_cur,
    'fx_rate', case when v_cur is distinct from v_base_cur then v_chg.exchange_rate else null end,
    'fx_direction', case when v_cur is distinct from v_base_cur then v_base_cur || ' per ' || coalesce(v_cur, '?') || ' — amount × rate'
                         else v_base_cur || ' — base currency, no conversion (× 1)' end,
    'amount_total', v_chg.total_amount, 'amount_total_cad', v_chg.total_amount * v_factor,
    'layers_touched', v_touched, 'amount_posted_cad', v_posted,
    'no_basis_allocs', v_no_basis, 'no_basis_amount_cad', v_no_basis_amt,
    'no_layers_allocs', v_no_layers, 'no_layers_amount_cad', v_no_layers_amt,
    'already_posted_allocs', v_already, 'already_posted_amount_cad', v_already_amt,
    'allocs', v_allocs, 'builder', c_version, 'warnings', to_jsonb(v_warn))
    || case when v_carried > 0 then jsonb_build_object('carried_rows', v_carried) else '{}'::jsonb end;   -- tr-4b: 따라간 행이 있을 때만 키(발주 반환 모양 무변)
exception
  when unique_violation then
    raise exception 'Charge % — a landed cost row with the same key already exists (%) — no cost was added', v_chg.charge_number, sqlerrm;
end;
$$;
comment on function public.inv_layer_post_charge(uuid) is 'IMS 비용(po_charge) → inv_layer_cost_add(landed): 배분 줄마다 — 발주면 그 발주의 입고 레이어 · 트랜스퍼면 그 문서의 도착 레이어(origin transfer · TRF-n · 도착 창고 · :settle: 제외)에 unit_cost × qty 비례 · 6자리 · 끝수는 마지막 · 기준 0 버림 · 배분 줄 단위 멱등 · tr-4b: 얹은 레이어의 IMS 자식으로 carried 를 내려보낸다(판정 79) · 문: 구매 열쇠 · transfer 또는 wms_receiving 열쇠는 발주 배분 없는 비용만(판정 78 도착 창구 · 2026-09-29)';

-- ── ⑤ 도착 창구 재발행(판정 78) ──
create or replace function public.tf_arrive(p_receipt_id uuid, p_staff uuid) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_r public.po_receipt%rowtype; v_x public.inv_transfer%rowtype; v_lines jsonb := '[]'::jsonb; v_ledger jsonb; v_n int; v_open int; v_over int := 0; v_short int := 0; v_posted numeric := 0; v_counted numeric := 0;
        v_l record; v_w record; v_rem numeric; v_take numeric; v_c record; v_fj jsonb; v_freight jsonb := '[]'::jsonb; v_ferr jsonb := '[]'::jsonb;
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
  -- tr-4b(판정 78): 도착 전에 확정해 둔 트랜스퍼 운임은 도착 순간 저절로 원가에 얹는다 — 배분 줄이 아직 안 얹힌 확정 문서만(멱등 · 창구가 배분 줄 단위로 건너뛴다)
  --   ⚠️ 재고 움직임은 운임을 기다리지 않는다(판정 65) — 창구가 거부해도 도착은 된다 · 사유는 freight.errors 로
  for v_c in select distinct c.id, c.charge_number from public.po_charge c join public.po_charge_alloc a on a.po_charge_id = c.id
              where a.transfer_id = v_x.id and c.status = 'confirmed' and c.confirmed_at is not null
                and not exists (select 1 from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = c.charge_number and ca.line_ref = a.id::text)
              order by c.charge_number loop
    begin
      v_fj := public.inv_layer_post_charge(v_c.id);
      v_freight := v_freight || jsonb_build_object('charge_id', v_c.id, 'charge_number', v_c.charge_number, 'layers_touched', v_fj -> 'layers_touched', 'amount_posted_cad', v_fj -> 'amount_posted_cad', 'warnings', v_fj -> 'warnings');
    exception when others then
      v_ferr := v_ferr || jsonb_build_object('charge_id', v_c.id, 'charge_number', v_c.charge_number, 'sqlstate', sqlstate, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'status', 'received',
                            'received_on', v_r.received_on, 'received_by', p_staff, 'counted_ea', v_counted, 'posted_ea', v_posted, 'over_lines', v_over, 'short_lines', v_short, 'lines', v_lines, 'ledger', v_ledger,
                            'freight', jsonb_build_object('posted', v_freight, 'errors', v_ferr));
end;
$$;
comment on function public.tf_arrive(uuid, uuid) is 'tr-3a(판정 66 · 68 · 70) — 트랜스퍼 도착 Complete: 세어 둔 줄을 입고 줄로(보낸 수량까지 · over/short 차이 기록) · 상태 receiving → received · 원장 · 레이어(inv_post_transfer_arrive) · tr-4b(판정 78): 배분된 확정 · 미적용 트랜스퍼 운임을 그 자리에서 inv_layer_post_charge 로 얹는다(거부돼도 도착은 된다 · freight.errors)';

-- ── ⑥ 재생성 재발행(마지막 바퀴) ──
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
  v_ims_carry_rows int := 0;   v_ims_carry_amt numeric := 0;   v_ims_carry record;   -- tr-4b(판정 79): IMS 트랜스퍼 자식 레이어로 따라간 얹힌 원가(마지막 한 바퀴)
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
  -- tr-4(2026-09-29): 비용 문서의 배분 줄이 트랜스퍼를 가리키면 그 문서의 도착 레이어에 얹는다 — 같은 창구 · 같은 규칙(판정 67 · 77 · 묶음 일곱) · 아래 exists 둘에 트랜스퍼 갈래를 더했다.
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
        and (exists (select 1
                      from po_charge_alloc a
                      join po_line  pl on pl.po_id = a.po_id
                      join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'
                      where a.po_charge_id = c.id)
             or exists (select 1                                                         -- tr-4: 트랜스퍼 배분 — 도착 레이어(origin transfer · TRF-n · 도착 창고 · :settle: 제외)가 선 것
                          from po_charge_alloc a
                          join inv_transfer t on t.id = a.transfer_id
                          join inv_layer x on x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%'
                          where a.po_charge_id = c.id))
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
      and not (exists (select 1
                        from po_charge_alloc a
                        join po_line  pl on pl.po_id = a.po_id
                        join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'
                        where a.po_charge_id = c.id)
               or exists (select 1                                                       -- tr-4: 트랜스퍼 배분(위 루프와 같은 조건)
                            from po_charge_alloc a
                            join inv_transfer t on t.id = a.transfer_id
                            join inv_layer x on x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%'
                            where a.po_charge_id = c.id));

  -- ═══ tr-4b(판정 79) 얹힌 원가 따라가기 — 마지막 한 바퀴 ═══
  -- 왜 끝인가: 얹힌 행(불러온 landed · transfer_freight · IMS 비용)은 레이어를 다 세운 뒤 위 블록들이 넣는다 — 재생 중 창구가 부른 inv_layer_carry 는 부모에 아직 얹힌 것이 없어 0 이다.
  --   그래서 IMS 트랜스퍼의 자식 레이어(origin transfer · parent 있음 · 문서가 inv_transfer 에 있음)를 id 순(부모 먼저)으로 한 번 더 돈다 · 멱등(같은 행은 다시 넣지 않는다) — 실시간과 같은 결과.
  --   불러온 데이터 축의 트랜스퍼(문서가 inv_transfer 에 없다)는 건드리지 않는다.
  for v_ims_carry in
    select y.id from inv_layer y
     where y.origin_type = 'transfer' and y.parent_layer_id is not null and exists (select 1 from inv_transfer t where t.transfer_number = y.doc_number)
     order by y.id
  loop
    v_ims_carry_rows := v_ims_carry_rows + inv_layer_carry(v_ims_carry.id);
  end loop;
  select coalesce(sum(amount), 0) into v_ims_carry_amt from inv_layer_cost_add where kind = 'carried';

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
      'carried_rows',              v_ims_carry_rows,        -- ⭐ tr-4b(판정 79) 마지막 바퀴가 넣은 따라간 행 수(재생 중 창구가 넣은 것은 0 이라 = 전체)
      'carried_amount_cad',        v_ims_carry_amt,         -- kind carried 합
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

-- ── ⑦ 읽기 재발행 ──
create or replace function public.inv_transfer_detail(p_transfer_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not public.ims_can_view('transfer') then null::jsonb else (
    select jsonb_build_object(
      'header', to_jsonb(x) || jsonb_build_object('from_warehouse', fw.name, 'to_warehouse', tw.name, 'created_by_name', cb.name, 'confirmed_by_name', fb.name),
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', p.name, 'qty', l.qty, 'qty_sent', l.qty_sent, 'short_sent', case when l.qty_sent is not null and l.qty_sent < l.qty then l.qty - l.qty_sent end, 'qty_received', l.qty_received, 'qty_lost', l.qty_lost, 'qty_returned', l.qty_returned, 'qty_extra', l.qty_extra, 'pack_factor', l.pack_factor,
                                                              'qty_ea', l.qty * l.pack_factor, 'stock_product_id', coalesce(p.parent_product_id, p.id),
                                                              -- tr-4b(판정 79 · 화면 ⑥ 재료): 이 줄의 자식 레이어(line_ref = 줄 id 또는 줄 id:…)로 따라온 얹힌 원가(kind carried) — 운송 중 · 도착 창고 · 되돌린(출발 창고)
                                                              'carried', (select jsonb_build_object('in_transit', coalesce(sum(ca.amount) filter (where y.warehouse = 'IN_TRANSIT'), 0), 'arrived', coalesce(sum(ca.amount) filter (where y.warehouse = tw.name), 0),
                                                                                                    'returned', coalesce(sum(ca.amount) filter (where y.warehouse = fw.name), 0), 'total', coalesce(sum(ca.amount), 0))
                                                                            from public.inv_layer y join public.inv_layer_cost_add ca on ca.layer_id = y.id and ca.kind = 'carried'
                                                                           where y.origin_type = 'transfer' and y.doc_number = x.transfer_number and (y.line_ref = l.id::text or y.line_ref like l.id::text || ':%'))) order by l.line_no), '[]'::jsonb)
                  from public.inv_transfer_line l join public.product p on p.id = l.product_id where l.transfer_id = x.id),
      'shortage', case when x.status = 'draft' then public.inv_transfer_shortage(x.id) else '[]'::jsonb end,
      -- tr-4(판정 67 · 묶음 일곱 · 화면 ⑥ 재료): 이 트랜스퍼에 배분된 비용 문서 — 문서별 금액(자기 통화) · CAD(기준통화면 ×1 · 아니면 × exchange_rate · 취소 제외) · 레이어에 얹힌 금액(cost_add landed · 배분 줄 단위)
      'freight', (select jsonb_build_object(
                    'total_cad', coalesce(sum(case when c.status <> 'cancelled' then a.amount * case when cu.code is not distinct from k.value then 1 else coalesce(c.exchange_rate, 0) end end), 0),
                    'posted_cad', coalesce(sum(pc.posted), 0),
                    'charges', coalesce(jsonb_agg(jsonb_build_object('charge_id', c.id, 'charge_number', c.charge_number, 'supplier_id', c.supplier_id, 'supplier_name', s.name, 'kind', c.kind, 'status', c.status, 'charge_date', c.charge_date, 'due_date', c.due_date,
                                                                'currency_code', cu.code, 'exchange_rate', c.exchange_rate, 'total_amount', c.total_amount, 'alloc_id', a.id, 'amount', a.amount, 'posted_cad', coalesce(pc.posted, 0), 'layers', coalesce(pc.n, 0), 'description', c.description) order by c.charge_date, c.charge_number), '[]'::jsonb))
                  from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id join public.supplier s on s.id = c.supplier_id join public.ref_currency cu on cu.id = c.currency_id
                  left join public.inv_config k on k.key = 'base_currency'
                  left join lateral (select sum(ca.amount) as posted, count(*) as n from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = c.charge_number and ca.line_ref = a.id::text) pc on true
                  where a.transfer_id = x.id))
      from public.inv_transfer x
      join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = x.to_warehouse_id
      left join public.ims_staff cb on cb.id = x.created_by left join public.ims_staff fb on fb.id = x.confirmed_by
     where x.id = p_transfer_id) end;
$$;
comment on function public.inv_transfer_detail(uuid) is 'IMS 트랜스퍼 상세(header · lines · shortage) · tr-4: freight(total_cad · posted_cad · charges[]) · tr-4b: lines[].carried {in_transit · arrived · returned · total}(판정 79 · 화면 ⑥ 재료) · transfer 열쇠 없으면 null';
