-- ─────────────────────────────────────────────────────────────
-- 원가 이식 1차 — 입고가 레이어를 만든다 (Asung-IMS · 2026-09-19)
--   ① inv_layer.cost_source + 'po_line'      IMS 발주 단가에서 왔다(Cin7 이 준 값 cin7_unitcost 와 섞지 않는다) · 기존 여덟 그대로
--   ② inv_layer_post_receipt(receipt_id)   ⭐⭐ 원가의 창구 — 확정된 입고의 원장 행(source='ims' · RCV)을 읽어 라인 단위 레이어를 만든다(멱등 · 환율 · CAD)
--   ③ inv_post_receipt(receipt_id)         다시 냄(시그니처 무변 · create or replace) — 원장을 넣은 뒤 ②를 부른다 · already_posted 분기에서도 부른다(백필 ⬜7) · 반환 + layers
--   ④ po_receipt_confirm(receipt_id)       다시 냄(시그니처 무변) — 게이트 ⑥ 환율: 기준통화 아닌 발주에 환율이 없거나 0 이면 확정 거부(저장 전 · 문장이 어디서 고치는지 말한다)
--
-- ⚠️⚠️ 전부 create or replace · alter … drop/add constraint(다시 밀어도 된다 · §13-f 교훈).
-- 앞 차수: 20260919155005(원장 이식 2차 · inv_post_receipt · confirm ⓔ) · 20260919175712(차이 닫기 · detail — 무접촉). 원가 표 다섯(20260908195949~)은 이미 IMS 에 있다 — 끊긴 자리만 잇는다.
-- 정본: ledger-design §4단계 원가(레이어 = inv_ledger + inv_cost 로 재생성 · 「원장 행 하나 = 레이어 하나가 아니다 — bin 을 버리고 창고 단위로 접는다」 · 1236~1240 환율 「0 금지」·「COGS 에 환율을 곱하지 않는다 — 이미 CAD」)
--       · po-module §11-j(사건) · §11-i(초과는 기준까지만) · 지시서 ~/asung/prompts/ims-cost-graft-1.md · ⬜1~9 는 회신에
--
-- ⭐⭐ Caleb 판정 (2026-09-19 · ⬜9): **재고 원가는 인식 시점 환율(= 발주 환율)로 세운다.**
--   실제 결제 환율과의 차액은 **재고가 아니라 환차손익**이다 — 레이어에 얹지 않는다.
--   ⚠️ 다만 최종 판단은 회계사와 확인한 뒤다 — inv_layer_cost_add 가 그 차액을 받을 수 있는 자리이므로 나중에 ③(레이어에 얹는 쪽)으로 바꿀 길은 열려 있다.
--
-- ⚠️⚠️⚠️ 환율 방향 — po.exchange_rate 는 **CAD per USD** 다(Cin7 화면 「CAD units per USD 1.39054」 · po.html 칸 「CAD per USD」).
--   unit_cost(CAD) = unit_price(공급처 통화) × exchange_rate. **곱한다 — 나누면 원가가 반으로 줄어드는데 에러가 안 난다.** USD 5.19 → CAD 7.22.
--   기준통화(CAD) 발주는 환율이 null 이어도 맞다 — 곱하지 않는다(환율이 적혀 있어도 무시하고 경고만).
--
-- ⭐⭐ 이견 1 — doc_number · line_ref 는 **원장 행과 같다**(RCV-… · po_line_id). 기존 803 레이어도 그 규칙이다 — inv_layer_apply_po_in(20260909155320)이 원장 행의
--   doc_number·line_ref 를 그대로 레이어에 옮기고 같은 4키(doc_number·line_ref·sku·warehouse)로 bin 을 접는다. Cin7 행은 PO 번호·CardID, IMS 행은 RCV·po_line_id 가
--   원장에 있으니 레이어도 그렇게 된다. 「레이어 키 = 원장 키」 하나의 규칙이고, PO 번호는 원장 raw.po_number 에 있다.
-- ⭐⭐ 이견 2 — 한 라인이 두 빈이면 레이어는 **한 행**이다(기존 규칙 그대로 · 「원장은 bin 단위 · 레이어는 창고 단위」). 원장 행 수 ≠ 레이어 행 수는 설계다 — 반환 ledger_rows·layers 가 둘을 따로 낸다.
-- ⭐ 이견 3 — 레이어는 **방금 넣은 inv_ledger 행을 읽어** 만든다. 두 번 계산하지 않는다 — 원장의 posted(기준까지만 · 배분)가 유일한 수량이고 레이어는 그 합이다.
--   그래서 백필도 같은 길이다: 원장이 이미 있는 입고(RCV-00005·00006)에 창구를 다시 부르면 already_posted 분기가 레이어만 세운다(⬜7).
-- ⭐ 이견 4 — 환율 게이트는 **둘 다**에 있다. confirm(사람이 누르는 자리 · 저장 전 · 문장이 닿는다)이 먼저 막고, inv_layer_post_receipt 도 막는다(직접 호출·백필 경로 · 게이트를 우회해 0 원가 레이어가 서지 않게).
-- ⚠️⚠️ 이견 5 — **전량 재생성 inv_layer_apply(20260909231134:288)는 이 레이어를 지우고 다시 만들지 않는다.** delete from inv_layer where origin_type <> 'baseline' 뒤 source='cin7' 만 돈다.
--   테스트 DB 에서 inv_layer_apply() 를 돌리면 오늘 만든 레이어가 사라진다. 이 차수는 그 함수를 건드리지 않는다(170행 · 별건) — 회신 ⬜9 · §13-f 에 적는다. 재생성은 inv_layer_post_receipt 를 RCV 마다 불러 되살린다.
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① inv_layer.cost_source — + 'po_line' ═══
-- 제약 이름 실물 inv_layer_source_ck(20260908195949 → 20260909155320 'unknown' → 20260909231134 'return_restore'). 기존 여덟 그대로 + 'po_line'.
alter table public.inv_layer drop constraint inv_layer_source_ck;
alter table public.inv_layer add constraint inv_layer_source_ck check (cost_source in (
  'inv_cost','snapshot_value','cin7_unitcost',
  'layer_avg','assembly_sum','parent_layer','unknown','return_restore',
  'po_line'));                                                                                             -- IMS 발주 단가 × 발주 환율(CAD) · 2026-09-19
comment on column public.inv_layer.cost_source is 'unit_cost 를 어디서 가져왔나 — inv_cost(Cin7 COGS) · snapshot_value · cin7_unitcost · layer_avg · assembly_sum · parent_layer · unknown(모르면 비운다 · 0) · return_restore · ⭐ po_line(2026-09-19 · IMS 발주 po_line.unit_price × po.exchange_rate(CAD per 통화) — 인식 시점 환율 · 결제 환율 차액은 환차손익이라 레이어에 안 얹는다 · Caleb 판정 · 회계사 확인 대기)';

-- ═══ ② inv_layer_post_receipt(p_receipt_id) — ⭐⭐ 원가의 창구 ═══
-- 읽는 것: 확정된 입고 → 그 RCV 의 inv_ledger 행(source='ims' · event_type po_in · qty_delta>0)을 (line_ref, sku, warehouse) 로 접는다 = 라인 단위(bin 을 버린다 · 이견 2).
--   단가 = po_line.unit_price(line_ref 가 po_line_id 다) · 환율 = po.exchange_rate · 통화 = po.currency_id → ref_currency.code · 기준통화 = inv_config.base_currency.
-- 만드는 것: inv_layer 한 행/라인 — origin_type 'purchase' · doc_number RCV · line_ref po_line_id · received_on 원장 occurred_on(=묶음 received_on) · age_known true · qty = 원장 합 · unit_cost CAD · cost_source 'po_line' · parent null.
-- 멱등: 같은 4키(purchase · doc_number · line_ref · sku · warehouse)의 레이어가 있으면 그 라인은 건너뛴다(inv_layer_apply_po_in 과 같은 규칙) — 두 번 불러도 한 벌.
-- 막는 것(읽을 수 있는 문장): 확정 아님 · 기준통화 설정 없음 · 기준통화 아닌데 환율 null·0 · 원장 행의 po_line 이 없음(있을 수 없다 — 있으면 원장이 틀린 것).
-- 경고만: 기준통화 발주에 환율이 적혀 있다(무시했다) · 레이어를 만들 원장 행이 없다(원장부터 없다).
-- ⚠️ append-only — insert 만. 잘못 만든 레이어는 상쇄(음수 레이어는 CHECK qty>0 이 막는다 ⇒ 소진 행이나 cost_add 로 · 정본 §4단계)로 고친다.
-- security invoker — inv_layer 는 authenticated 에 insert 가 열려 있다(auth_all · delete/truncate 만 회수). confirm(definer) 안에서 불리면 그 문맥으로 돈다.
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
  perform public.ims_require_write('receiving', 'posted');

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
comment on function public.inv_layer_post_receipt(uuid) is '⭐⭐ 원가의 창구(원가 이식 1차 · 2026-09-19) — 확정된 입고의 원장 행(source ims · po_in · 이 RCV)을 (line_ref, sku, warehouse) 로 접어 inv_layer 한 행/라인을 만든다(bin 은 버린다 · 원장 행 수 ≠ 레이어 행 수는 설계). 수량 = 원장 합(기준까지만 — 두 번 계산하지 않는다) · unit_cost = po_line.unit_price × po.exchange_rate(⚠️ CAD per USD · 곱한다 · 기준통화면 ×1) · cost_source po_line · origin purchase · doc_number RCV · line_ref po_line_id(레이어 키 = 원장 키). 멱등: 같은 4키 레이어가 있으면 건너뛴다 — 백필은 다시 부르기만. 거부(문장): 확정 아님 · base_currency 없음 · 기준통화 아닌데 환율 null·0(어디서 고치는지 말한다) · 원장이 가리키는 po_line 없음. 경고: 기준통화에 환율 적힘(무시) · 원장 행 없음. ⭐ 재고 원가는 인식 시점(발주) 환율 — 결제 환율 차액은 환차손익(Caleb · 회계사 확인 대기 · cost_add 로 바꿀 길은 열림). ⚠️ inv_layer_apply() 전량 재생성은 이 레이어를 지우고 되살리지 않는다(§13-f). security invoker · append-only';
revoke all on function public.inv_layer_post_receipt(uuid) from public, anon;
grant execute on function public.inv_layer_post_receipt(uuid) to authenticated;

-- ═══ ③ inv_post_receipt — 다시 냄 (155005 43~171행 복사 · create or replace · 바뀐 곳 넷: declare v_layers · already_posted 분기에서 ② 호출 · 기표 뒤 ② 호출 · 반환 layers) ═══
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
  perform public.ims_require_write('receiving', 'posted');

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
  where l.doc_type = 'purchase' and l.doc_number = v_r.receipt_number and l.source = 'ims';
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
  if v_r.received_on > current_date then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

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
comment on function public.inv_post_receipt(uuid) is '⭐⭐ 원장의 창구 — 확정된 입고(po_receipt · confirmed)를 읽어 inv_ledger 에 po_in 사건을 기표한다(원장 이식 2차 · 2026-09-19 · §11-j). 한 입고 줄 = 한 행(bin 별) · doc_type purchase · doc_number = RCV-(PO 번호가 아니다) · doc_task_id = po_receipt.id · line_ref = po_line_id · occurred_on = 묶음의 received_on · seq_hint 1 · source ims · amount null(단가·통화·환율은 raw). ⭐ 초과는 기준까지만(기준 = po_receipt_diff.expected_qty · over·short 둘 다 · 깎는 상한은 over 만 · 큰 빈부터 채우고 바닥나는 줄에서 자른다 · raw 에 전부). 멱등: 이미 기표된 입고는 already_posted=true · 0행. ⭐ [원가 이식 1차 2026-09-19] 기표 뒤 inv_layer_post_receipt 를 같은 트랜잭션으로 부른다(원장 사건과 레이어가 함께 서거나 함께 죽는다) · already_posted 분기에서도 부른다(원장은 있는데 레이어가 없는 입고의 백필 — RCV-00005·00006) · 반환 + layers{layers_created, layers_existing, qty, cost_total_cad, fx_rate, lines[]}. 거부: 권한 · 확정 아님 · (레이어 쪽) 환율 없음. security invoker · append-only';
-- grant·revoke 는 155005 의 것이 유지된다(create or replace).

-- ═══ ④ po_receipt_confirm — 다시 냄 (155005 178~394행 복사 · 시그니처 무변 · 바뀐 곳 둘: declare v_cur·v_base · 게이트 ⑥ 환율(⑤ 뒤 · ⓐ 앞 · 저장 전)) ═══
create or replace function public.po_receipt_confirm(p_receipt_id uuid) returns jsonb
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
  perform public.ims_require_write('receiving', 'saved');      -- §5 ② · definer 안에서도 auth.uid() 는 JWT 의 것
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
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
  if v_r.received_on > current_date then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

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
comment on function public.po_receipt_confirm(uuid) is '⑤⭐⭐ 입고 확정(리시빙 2-b 2026-09-18 → 원장 이식 2차 → 원가 이식 1차 2026-09-19 다시 냄) — 「이 배로 온 것이 정해졌다」. 막는 것: 권한(receiving) · 이미 확정/취소 · PO 가 confirmed 아님(잠금 뒤 다시 본다) · 작업 줄 없음 · ⭐ 빈 없는 줄(라인·수량 + 빠져나갈 길) · 빈이 다른 창고·비활성 · ⭐ ⑥ 기준통화(inv_config.base_currency) 아닌 발주에 환율(po.exchange_rate · CAD per USD)이 없거나 0(어디서 고치는지 문장에 · 확정 뒤에도 열린 칸). 하는 일 ⓐ 작업 줄 → po_receipt_line ⓑ 차이 큐 ⓒ 분할/닫기 ⓓ 묶음 confirmed ⓔ 원장 창구 inv_post_receipt(같은 트랜잭션 · 원장 사건 + ⭐ 원가 레이어 inv_layer_post_receipt · 하나가 실패하면 확정도 실패). 반환에 ledger{… layers{…}} · warnings. ⭐ security definer(2-b 이견 1) · 잠금 po:<base> + 라인 키. 정본 §11-i·c·j';
-- grant·revoke 는 20260918203805 의 것이 유지된다(create or replace).

-- ─────────────────────────────────────────────────────────────
-- 화면(receiving.html · po.html · 대화 Claude)이 보는 모양
--   확정 거부  「PO … is in USD but has no CAD per USD exchange rate — … Enter the rate in the order header …」 → po.html 발주 머리 「Exchange rate (CAD per USD)」(HEAD_ALWAYS · 확정 뒤에도 열림)
--   확정 뒤    data.ledger.layers.layers_created · cost_total_cad — 「재고 원가 n 개 · $x CAD 로 잡혔다」
--   백필       select inv_post_receipt('<RCV id>') — 원장은 그대로(already_posted) · 빠진 레이어만 선다(환율을 먼저 넣어야 한다)
-- 검증(회신 §5 · psql heredoc · Caleb 이 실행 · 쓰는 것은 rollback) 요지 — ⓪ 기존 803 레이어의 doc_number·line_ref 실물 ① 환율 없이 확정 → 거부 문장 ② 1.39 넣고 확정 → unit_cost = unit_price × 1.39
--   ③ 수량 = 원장(초과도 기준까지만) ④ 두 빈 → 레이어 한 행 · 합 ⑤ CAD 발주는 환율 없이 · unit_cost 그대로 ⑥ 두 번 불러도 한 벌 ⑦ 권한 없음 거부 ⑧ 롤백 뒤 po_line 레이어 0행
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────
