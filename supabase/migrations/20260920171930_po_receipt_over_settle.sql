-- ─────────────────────────────────────────────────────────────
-- over 차이를 닫는다 — 초과 입고를 재고에 넣는다 (Asung-IMS · 2026-09-20)
--   ① po_receipt_diff CHECK          resolution 어휘 +3(free · billed · credited) · ⭐ kind 별 어휘 CHECK(short 는 다섯 · over 는 셋 — 같은 행 안)
--   ② inv_layer.cost_source           + 'free'(진짜 0 · 「원가를 모른다」 unknown 과 섞지 않는다)
--   ③ inv_layer_post_receipt          다시 냄(create or replace · 시그니처 무변 · 원본 20260919192236:52) — 더한 것 1줄: 초과분 행(line_ref ':over')은 접지 않는다
--   ④ inv_post_receipt_over(diff)     ⭐ 새 창구 — 초과분만 원장에(빈 별 · 센 것 − 이미 기표된 것) · 끝에 ⑤ 를 부른다 · 멱등
--   ⑤ inv_layer_post_receipt_over(diff) ⭐ 새 창구 — 초과분 레이어 하나: free → unit_cost 0 · cost_source free / billed·credited → **기준 레이어의 unit_cost 그대로**(환율 식을 다시 적지 않는다) · 멱등
--   ⑥ po_receipt_diff_settle_over(diff, reason, note)  ⭐ 사람이 누르는 자리 — _resolve 의 형제 · 잠금 · 어휘 · 닫기 → ④ 호출(같은 트랜잭션) · 반환 + ledger · family · open_diffs_left
--   ⑦ po_receipt_diff_resolve         다시 냄(시그니처 무변 · 원본 20260919175712:127) — 바뀐 것 2줄: over 거부 문장이 ⑥ 을 가리킨다(「별도 차수」가 아니다)
--   ⑧ po_receipt_diff_reopen          다시 냄(시그니처 무변 · 원본 20260919175712:202) — 더한 것: over 로 닫힌 것은 거부(재고가 움직였다 · 상쇄 길은 별도)
--   ⑨ inv_layer_apply                 다시 냄(시그니처 무변 · 원본 20260920142635:111) — 더한 것: 초과분 행을 만나면 ⑤ 를 diff 단위로 · 반환 ims.over_posted/over_layers/over_skipped
--   ⚠️ 빈은 건드리지 않는다 — 풋어웨이에서 15 를 다 놓았다. 장부(원장·레이어)만 올린다.
--
-- ⭐⭐ Caleb 판정 (2026-09-20)
--   실무 셋: 1 잘못 더 보냈고 공짜로 쓰라고 한다(⭐ 가장 많다) · 2 인보이스를 추가로 보낸다 · 3 다음 오더에서 깐다. 「돌려보내는 일은 거의 없어」 ⇒ returned 는 만들지 않는다(쓰지 않을 갈래도 유지해야 할 코드다 · 생기면 그때).
--   이유 셋 · 원가 둘: free → 0 / billed·credited → 그 발주의 단가. 셋으로 남기는 이유 — 칸 하나의 비용은 없고, 합치면 「그때 깎기로 했다」가 사라진다(이력 보존).
--   왜 그 발주 단가인가 — Cin7 은 재고조정으로 넣어 창고 평균원가가 붙는다(같은 배로 온 물건인데 값이 달라진다). IMS 는 어느 발주에서 왔는지 안다 ⇒ 같은 값. ⭐ 이것이 나아지는 부분이다.
--   왜 free 는 0 인가 — 공짜 3개에 11.606 을 매기면 자산 34.82 가 공중에서 생긴다(낸 돈이 없다). 0 이면 낸 돈 99.48 = 재고 자산. 팔릴 때 이익이 크게 잡히는데 그것이 사실이다.
--   ⚠️ 「총액을 15 로 나눈다」(6.632)는 기각 — 이미 선 12개의 단가가 흔들린다 · landed 가 얹혔거나 팔렸으면 되돌릴 수 없다 · 원가 append-only 와 부딪힌다.
--
-- ⭐ 원장 사건의 모양 (⬜2) — doc_type purchase · event_type po_in · doc_number = RCV(그대로) · doc_task_id = po_receipt.id · **line_ref = po_line_id||':over'** · occurred_on = received_on(물건이 그날 들어왔다) · seq_hint 1(유입) · source ims · bin 별.
--   왜 line_ref 접미어인가 — 유니크 7키(doc_type, doc_number, line_ref, event_type, warehouse, bin, sku)가 같은 빈의 기준 행(12)과 부딪힌다. 접미어는 ':reversal'(sale_out 상쇄 · 20260909174046) 선례.
--   덤으로 레이어 4키도 갈라진다(기준 레이어 po_line_id · 초과 레이어 po_line_id:over) — 두 창구의 멱등이 서로를 건너뛰게 하지 않는다. raw.kind 'po_over' · raw.diff_id 가 재생성의 열쇠다.
--   ⚠️ inv_layer_post_charge(pl.id::text = x.line_ref)는 초과 레이어에 landed 를 얹지 않는다 — free 는 맞고 billed 는 논의 여지(⬜ · 회신).
-- ⭐ 어느 빈으로 올리나 (⬜8) — po_receipt_line(확정된 사실 · 빈 별)에서 센 수량 − 그 빈의 기준 원장 행 qty_delta = 그 빈의 초과분. 여러 빈이면 여러 행. 합이 gap(received − expected)과 다르면 거부(입고 줄과 원장이 어긋난 것).
-- ⭐ 환율 (⬜4) — free 는 환율이 필요 없다(0). billed·credited 는 **기준 레이어에서 unit_cost 를 읽는다** — 환율 곱하기 식이 두 곳에 살지 않는다(inv_layer_apply 차수의 교훈). 기준 레이어가 없으면(환율 없이 확정된 옛 입고) 거부하며 어디서 고치는지 말한다.
-- ⭐ 재생성(⑨) — 「레이어 = 원장 + 원가로 전량 재생성」이 초과분에도 성립한다: 원장 행(raw.diff_id)에서 ⑤ 를 다시 부른다. 기준 레이어가 먼저 서는 순서는 (occurred_on, seq_hint, id) 가 보장한다(같은 날 · 더 큰 id).
--
-- 정본: po-module §11-i(초과는 기준까지만 · 사람이 보고 메운다) · §11-j · ledger-design 4부 「원가 이식 1차」(키 = 원장 키 · 환율 곱한다) · 지시서 ~/asung/prompts/ims-over-settle.md · ⬜1~8 은 회신에
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① po_receipt_diff — 이유 어휘 +3 · kind 별 어휘 ═══
alter table public.po_receipt_diff drop constraint if exists po_receipt_diff_resolution_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_resolution_ck
  check (resolution is null or resolution in ('split_shipment', 'out_of_stock', 'lost_damaged', 'miscount', 'other', 'free', 'billed', 'credited'));
alter table public.po_receipt_diff drop constraint if exists po_receipt_diff_resolution_kind_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_resolution_kind_ck
  check (resolution is null
         or (kind = 'short' and resolution in ('split_shipment', 'out_of_stock', 'lost_damaged', 'miscount', 'other'))
         or (kind = 'over'  and resolution in ('free', 'billed', 'credited')));                            -- ⭐ short 의 이유로 over 를 닫거나 그 반대를 DB 가 막는다(같은 행 안)
comment on column public.po_receipt_diff.resolution is '닫은 이유 — short: split_shipment | out_of_stock | lost_damaged | miscount | other(메모 필수) · ⭐ over(2026-09-20): free(공짜 · 원가 0) | billed(추가 청구 · 발주 단가) | credited(다음에 깎아 줌 · 발주 단가) — kind 별 어휘는 CHECK po_receipt_diff_resolution_kind_ck. null = 열림. returned 는 없다(거의 없다 · 생기면 그때)';

-- ═══ ② inv_layer.cost_source — + 'free' ═══
-- 기존 아홉 그대로(20260919192236) + free. ⚠️ unknown 을 쓰지 마라 — 「원가를 모른다」와 「진짜 0」이 섞인다(정본 ⬜ 「unknown 의 0 을 null 로」).
alter table public.inv_layer drop constraint inv_layer_source_ck;
alter table public.inv_layer add constraint inv_layer_source_ck check (cost_source in (
  'inv_cost','snapshot_value','cin7_unitcost',
  'layer_avg','assembly_sum','parent_layer','unknown','return_restore',
  'po_line',
  'free'));                                                                                                -- ⭐ 공짜로 받은 초과분 · 진짜 0 · 2026-09-20
comment on column public.inv_layer.cost_source is 'unit_cost 를 어디서 가져왔나 — inv_cost(Cin7 COGS) · snapshot_value · cin7_unitcost · layer_avg · assembly_sum · parent_layer · unknown(모르면 비운다 · 0) · return_restore · po_line(IMS 발주 po_line.unit_price × po.exchange_rate · 인식 시점 환율) · ⭐ free(2026-09-20 · 공짜로 받은 초과분 · 진짜 0 — 낸 돈이 없다 · unknown 과 섞지 않는다)';

-- ═══ ③ inv_layer_post_receipt — 다시 냄 (원본 20260919192236:52~148 · 더한 것 1줄) ═══
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
      and l.line_ref not like '%:over'                                                              -- ⭐ 2026-09-20 초과분 행(over 닫기 · line_ref = po_line_id||':over')은 형제 창구 inv_layer_post_receipt_over 가 만든다 — 여기서 접으면 po_line 을 못 찾아 터지거나(접미어) free 를 발주 단가로 매긴다
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

comment on function public.inv_layer_post_receipt(uuid) is '⭐⭐ 원가의 창구(원가 이식 1차 · 2026-09-19) — 확정된 입고의 원장 행(source ims · po_in · 이 RCV)을 (line_ref, sku, warehouse) 로 접어 inv_layer 한 행/라인을 만든다(bin 은 버린다 · 원장 행 수 ≠ 레이어 행 수는 설계). 수량 = 원장 합(기준까지만 — 두 번 계산하지 않는다) · unit_cost = po_line.unit_price × po.exchange_rate(⚠️ CAD per USD · 곱한다 · 기준통화면 ×1) · cost_source po_line · origin purchase · doc_number RCV · line_ref po_line_id(레이어 키 = 원장 키). 멱등: 같은 4키 레이어가 있으면 건너뛴다 — 백필은 다시 부르기만. 거부(문장): 확정 아님 · base_currency 없음 · 기준통화 아닌데 환율 null·0(어디서 고치는지 말한다) · 원장이 가리키는 po_line 없음. 경고: 기준통화에 환율 적힘(무시) · 원장 행 없음. ⭐ 재고 원가는 인식 시점(발주) 환율 — 결제 환율 차액은 환차손익(Caleb · 회계사 확인 대기 · cost_add 로 바꿀 길은 열림). ⭐ inv_layer_apply() 전량 재생성은 이 레이어를 지운 뒤 이 창구를 다시 불러 되살린다(20260920142635 · 환율 없으면 건너뛰고 ims.receipts_skipped 에 센다). ⭐ [2026-09-20 over 닫기] 초과분 행(line_ref po_line_id:over)은 접지 않는다 — 형제 창구 inv_layer_post_receipt_over 의 몫. security invoker · append-only';

-- ═══ ④ inv_post_receipt_over(p_diff_id) — ⭐ 초과분만 원장에 ═══
-- 읽는 것: over 로 닫힌 차이(resolution free·billed·credited) · 그 입고(confirmed) · 그 라인의 po_receipt_line(빈 별 센 수량) · 그 빈의 기준 원장 행(이미 기표된 것).
-- 넣는 것: 빈마다 (센 것 − 기표된 것) 이 양수면 po_in 행 하나 — line_ref po_line_id:over · 나머지는 기준 행과 같은 모양(RCV · 입고일 · ims). 합이 gap 과 다르면 거부(입고 줄과 원장이 어긋났다).
-- 멱등: 이미 :over 행이 있으면 already_posted · 레이어 창구만 다시 부른다(백필). security invoker — inv_ledger insert 는 authenticated 에 열려 있다(auth_all).
create or replace function public.inv_post_receipt_over(p_diff_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_post_receipt_over@2026-09-20.1';
  v_d        public.po_receipt_diff%rowtype;
  v_r        public.po_receipt%rowtype;
  v_po       public.po%rowtype;
  v_wh       text;
  v_sku      text;
  v_line_no  int;
  v_gap      numeric;
  v_ref      text;
  v_existing int;
  v_rows     int := 0;
  v_posted   numeric := 0;
  v_lines    jsonb := '[]'::jsonb;
  v_layer    jsonb;
  b          record;
begin
  perform public.ims_require_write('receiving', 'posted');

  select * into v_d from public.po_receipt_diff where id = p_diff_id;
  if not found then raise exception 'Difference % not found — nothing was posted to the ledger', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  if not found then raise exception 'Receipt of difference % not found — nothing was posted to the ledger', p_diff_id; end if;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  select pl.line_no into v_line_no from public.po_line pl where pl.id = v_d.po_line_id;
  if v_d.kind <> 'over' then
    raise exception 'Line % (%) on % is a "%" difference — only over differences put extra stock on the ledger — nothing was posted to the ledger',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.kind;
  end if;
  if v_d.resolved_at is null or v_d.resolution not in ('free', 'billed', 'credited') then
    raise exception 'Line % (%) on % is not settled as free, billed or credited — settle it first (po_receipt_diff_settle_over) — nothing was posted to the ledger',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  if v_r.status <> 'confirmed' or v_r.confirmed_at is null then
    raise exception 'Receipt % is % — the ledger takes confirmed receipts only — nothing was posted to the ledger', v_r.receipt_number, v_r.status;
  end if;
  select * into v_po from public.po where id = v_r.po_id;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  if v_wh is null then raise exception 'Warehouse of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;
  v_gap := v_d.received_qty - v_d.expected_qty;
  if v_gap <= 0 then
    raise exception 'Line % (%) on % says over but received % is not above expected % — nothing was posted to the ledger',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.received_qty, v_d.expected_qty;
  end if;
  v_ref := v_d.po_line_id::text || ':over';                                                            -- ⭐ 유니크 7키가 기준 행과 부딪히지 않게 · 레이어 4키도 갈린다 · ':reversal' 선례

  -- 멱등 — 이미 초과분 행이 있으면 다시 쓰지 않는다 · 레이어만 다시(백필)
  select count(*) into v_existing from public.inv_ledger l
   where l.doc_type = 'purchase' and l.source = 'ims' and l.event_type = 'po_in' and l.doc_number = v_r.receipt_number and l.line_ref = v_ref;
  if v_existing > 0 then
    v_layer := public.inv_layer_post_receipt_over(p_diff_id);
    return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number, 'sku', v_sku,
                              'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0, 'qty_posted', 0, 'gap', v_gap,
                              'lines', '[]'::jsonb, 'layer', v_layer, 'warnings', '["already_posted"]'::jsonb);
  end if;

  -- 빈마다: 센 것(po_receipt_line · 확정된 사실) − 그 빈에 이미 기표된 것(기준 행) = 그 빈의 초과분. 0 으로 깎인 빈은 기준 행이 없어 센 것 전부가 초과분이다.
  for b in
    select rb.name as bin, l.bin_id, sum(l.qty_ea) as counted,
           coalesce((select sum(x.qty_delta) from public.inv_ledger x
                      where x.doc_type = 'purchase' and x.source = 'ims' and x.event_type = 'po_in'
                        and x.doc_number = v_r.receipt_number and x.line_ref = v_d.po_line_id::text and x.bin = rb.name), 0) as posted_base
    from public.po_receipt_line l
    join public.ref_bin rb on rb.id = l.bin_id
    where l.receipt_id = v_r.id and l.po_line_id = v_d.po_line_id
    group by rb.name, l.bin_id
    order by rb.name
  loop
    if b.counted - b.posted_base <= 0 then continue; end if;
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (
      v_r.received_on, 1, v_sku, v_wh, b.bin, b.counted - b.posted_base, 'po_in', 'purchase', v_r.receipt_number, v_r.id::text, v_ref, null, 'ims',
      jsonb_build_object(
        'kind', 'po_over', 'poster', c_version,
        'diff_id', v_d.id, 'resolution', v_d.resolution, 'resolution_note', v_d.resolution_note, 'settled_by', v_d.resolved_by, 'settled_at', v_d.resolved_at,
        'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_id', v_po.id, 'po_number', v_po.po_number,
        'po_line_id', v_d.po_line_id, 'line_no', v_line_no, 'product_id', v_d.product_id, 'sku', v_sku,
        'warehouse_id', v_r.warehouse_id, 'warehouse', v_wh, 'bin_id', b.bin_id, 'bin', b.bin,
        'received_on', v_r.received_on, 'expected_qty', v_d.expected_qty, 'received_qty', v_d.received_qty, 'gap', v_gap,
        'this_bin', jsonb_build_object('counted', b.counted, 'posted_base', b.posted_base, 'over', b.counted - b.posted_base),
        'cost_rule', case v_d.resolution when 'free' then 'free — unit_cost 0 (nothing was paid)' else v_d.resolution || ' — unit_cost of the receipt''s own layer (same shipment, same price)' end));
    v_rows := v_rows + 1;
    v_posted := v_posted + (b.counted - b.posted_base);
    v_lines := v_lines || jsonb_build_object('bin', b.bin, 'counted', b.counted, 'posted_base', b.posted_base, 'over', b.counted - b.posted_base);
  end loop;
  if v_posted <> v_gap then
    raise exception 'Line % (%) on %: the bins add up to % extra but the difference says % — the receipt lines and the ledger disagree; nothing was posted to the ledger',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_posted, v_gap;
  end if;

  -- ⭐ 레이어 — 방금 넣은 초과분 행으로(같은 트랜잭션 · 함께 서거나 함께 죽는다)
  v_layer := public.inv_layer_post_receipt_over(p_diff_id);

  return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number, 'sku', v_sku,
                            'already_posted', false, 'existing_rows', 0, 'rows_posted', v_rows, 'qty_posted', v_posted, 'gap', v_gap,
                            'lines', v_lines, 'layer', v_layer, 'warnings', '[]'::jsonb);
exception
  when unique_violation then
    raise exception 'Difference % on % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', p_diff_id, coalesce(v_r.receipt_number, '?'), sqlerrm;
end;
$$;
comment on function public.inv_post_receipt_over(uuid) is '⭐ 원장의 창구 · 초과분(over 닫기 · 2026-09-20) — over 로 닫힌 차이(resolution free·billed·credited)의 초과분만 inv_ledger 에 po_in 으로 넣는다. 빈마다 po_receipt_line 의 센 수량 − 그 빈의 기준 행(po_line_id) 기표 수량 = 초과분(여러 빈이면 여러 행 · 합 ≠ gap 이면 거부). 모양은 기준 행과 같되 line_ref = po_line_id:over(유니크 7키·레이어 4키가 갈린다 · :reversal 선례) · raw.kind po_over · raw.diff_id(재생성의 열쇠). 끝에 inv_layer_post_receipt_over 를 같은 트랜잭션으로 부른다. 멱등: :over 행이 있으면 already_posted · 레이어만 다시. 거부(문장): 권한(receiving) · 없는 차이 · over 아님 · 안 닫힘/이유 밖 · 확정 아님 · gap ≤ 0 · 합 불일치. ⚠️ 빈은 건드리지 않는다(이미 다 놓았다). security invoker · append-only';
revoke all on function public.inv_post_receipt_over(uuid) from public, anon;
grant execute on function public.inv_post_receipt_over(uuid) to authenticated;

-- ═══ ⑤ inv_layer_post_receipt_over(p_diff_id) — ⭐ 초과분 레이어 하나 ═══
-- free → unit_cost 0 · cost_source free. billed·credited → 기준 레이어(같은 RCV · po_line_id · sku · warehouse)의 unit_cost 를 그대로(같은 배 · 같은 값 · 환율 식을 다시 적지 않는다) · cost_source po_line.
-- 기준 레이어가 없으면 거부하며 어디서 고치는지 말한다(환율 없이 확정된 옛 입고 — 환율을 넣고 inv_post_receipt 를 다시 부르면 기준 레이어가 선다).
-- 멱등: (purchase · RCV · po_line_id:over · sku · warehouse) 레이어가 있으면 건너뛴다. security invoker — inv_layer insert 는 authenticated 에 열려 있다.
create or replace function public.inv_layer_post_receipt_over(p_diff_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_layer_post_receipt_over@2026-09-20.1';
  v_d        public.po_receipt_diff%rowtype;
  v_r        public.po_receipt%rowtype;
  v_wh       text;
  v_sku      text;
  v_line_no  int;
  v_ref      text;
  v_qty      numeric;
  v_recv_on  date;
  v_rows     int;
  v_unit     numeric;
  v_src      text;
  v_layer_id bigint;
  v_base_id  bigint;
begin
  perform public.ims_require_write('receiving', 'posted');

  select * into v_d from public.po_receipt_diff where id = p_diff_id;
  if not found then raise exception 'Difference % not found — no cost layer was created', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  if not found then raise exception 'Receipt of difference % not found — no cost layer was created', p_diff_id; end if;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  select pl.line_no into v_line_no from public.po_line pl where pl.id = v_d.po_line_id;
  if v_d.kind <> 'over' or v_d.resolved_at is null or v_d.resolution not in ('free', 'billed', 'credited') then
    raise exception 'Line % (%) on % is not an over difference settled as free, billed or credited — no cost layer was created',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  v_ref := v_d.po_line_id::text || ':over';

  -- 초과분 원장 행을 접는다(한 라인 · 한 SKU · 한 창고 ⇒ 레이어 하나 · 빈은 버린다)
  select sum(l.qty_delta), min(l.occurred_on), count(*)::int into v_qty, v_recv_on, v_rows
  from public.inv_ledger l
  where l.doc_type = 'purchase' and l.source = 'ims' and l.event_type = 'po_in'
    and l.doc_number = v_r.receipt_number and l.line_ref = v_ref and l.sku = v_sku and l.warehouse = v_wh and l.qty_delta > 0;
  if coalesce(v_rows, 0) = 0 then
    return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'resolution', v_d.resolution,
                              'ledger_rows', 0, 'layers_created', 0, 'layers_existing', 0, 'qty', 0, 'builder', c_version, 'warnings', '["no_ledger_rows_for_over"]'::jsonb);
  end if;

  -- 멱등 — 같은 4키(purchase · RCV · po_line_id:over · sku · warehouse)의 레이어가 있으면 건너뛴다
  if exists (select 1 from public.inv_layer y
              where y.origin_type = 'purchase' and y.doc_number = v_r.receipt_number and y.line_ref = v_ref and y.sku = v_sku and y.warehouse = v_wh) then
    return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'resolution', v_d.resolution,
                              'ledger_rows', v_rows, 'layers_created', 0, 'layers_existing', 1, 'qty', v_qty, 'builder', c_version, 'warnings', '[]'::jsonb);
  end if;

  if v_d.resolution = 'free' then
    v_unit := 0; v_src := 'free';                                                                         -- ⭐ 낸 돈이 없다 — 자산이 공중에서 생기지 않게 · unknown 이 아니다(진짜 0)
  else
    -- ⭐ 같은 배 · 같은 값 — 기준 레이어의 unit_cost 그대로. 환율 곱하기 식은 inv_layer_post_receipt 한 곳에만 산다.
    select y.id, y.unit_cost into v_base_id, v_unit
    from public.inv_layer y
    where y.origin_type = 'purchase' and y.doc_number = v_r.receipt_number and y.line_ref = v_d.po_line_id::text and y.sku = v_sku and y.warehouse = v_wh
    order by y.id limit 1;
    if v_base_id is null then
      raise exception 'Line % (%) on % is settled as "%" but the receipt''s own cost layer is missing (was it confirmed without an exchange rate?) — enter the rate on the order header and run inv_post_receipt for % first, then run this again — no cost layer was created',
        coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.resolution, v_r.receipt_number;
    end if;
    v_src := 'po_line';
  end if;

  insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
  values (v_sku, v_wh, 'purchase', v_r.receipt_number, v_ref, null, v_recv_on, true, v_qty, v_unit, v_src)
  returning id into v_layer_id;

  return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'warehouse', v_wh, 'resolution', v_d.resolution,
                            'ledger_rows', v_rows, 'layers_created', 1, 'layers_existing', 0, 'layer_id', v_layer_id, 'base_layer_id', v_base_id,
                            'qty', v_qty, 'unit_cost', v_unit, 'cost_source', v_src, 'cost_total_cad', v_qty * v_unit, 'received_on', v_recv_on,
                            'builder', c_version, 'warnings', '[]'::jsonb);
end;
$$;
comment on function public.inv_layer_post_receipt_over(uuid) is '⭐ 원가의 창구 · 초과분(over 닫기 · 2026-09-20) — 초과분 원장 행(RCV · line_ref po_line_id:over · sku · warehouse)을 접어 inv_layer 한 행을 만든다. free → unit_cost 0 · cost_source free(진짜 0 · unknown 아님). billed·credited → 기준 레이어(같은 RCV · po_line_id)의 unit_cost 그대로 · cost_source po_line — 같은 배 같은 값 · 환율 식을 다시 적지 않는다. 기준 레이어가 없으면 거부하며 어디서 고치는지(환율 → inv_post_receipt) 말한다. 멱등: 4키 레이어가 있으면 건너뛴다 · 원장 행이 없으면 경고만. inv_layer_apply() 재생성이 raw.diff_id 로 이 창구를 다시 부른다. ⚠️ inv_layer_post_charge 는 이 레이어(line_ref 접미어)에 landed 를 얹지 않는다. security invoker · append-only';
revoke all on function public.inv_layer_post_receipt_over(uuid) from public, anon;
grant execute on function public.inv_layer_post_receipt_over(uuid) to authenticated;

-- ═══ ⑥ po_receipt_diff_settle_over(p_diff_id, p_resolution, p_note) — ⭐ over 를 닫는다 · _resolve 의 형제 ═══
-- short(_resolve)는 「왜 덜 왔나」를 적는 일이고 over 는 재고를 움직이는 일이다 — 거부 조건·반환이 달라 한 함수에 섞지 않는다.
-- 순서: 권한 · 어휘 · 잠금 · 검사 → 닫기(update) → 창구 ④(원장 + ⑤ 레이어) — 같은 트랜잭션. 창구가 거부하면 닫기도 함께 되돌아간다.
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

  -- ① over 만 — short 는 _resolve 가 닫는다 · off_po 는 어휘만(아직 날 수 없다)
  if v_d.kind <> 'over' then
    raise exception 'Line % (%) on % is a "%" difference — only over differences are settled here. A short difference is settled with po_receipt_diff_resolve — nothing was saved',
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
comment on function public.po_receipt_diff_settle_over(uuid, text, text) is '⑤⭐ over 차이 닫기(2026-09-20 · Caleb) — 초과 입고를 재고에 넣는다. 이유 셋: free(공짜 · 가장 흔하다 · 원가 0) · billed(추가 청구) · credited(다음에 깎아 줌) — 뒤 둘은 그 발주의 단가(= 기준 레이어 unit_cost · Cin7 의 평균원가와 갈린다 · 같은 배 같은 값). returned 는 없다. resolution·resolved_by(서버 유도)·resolved_at 을 채운 뒤 같은 트랜잭션으로 창구 inv_post_receipt_over(원장 · 빈 별 초과분) → inv_layer_post_receipt_over(레이어)를 부른다 — 창구가 거부하면 닫기도 되돌아간다. 막는 것(문장): 권한(receiving) · 어휘 밖 · 없는 차이 · over 아님(short 는 _resolve) · 이미 닫힘(두 번 넣지 않는다 · reopen 없음) · gap ≤ 0 · 남이 사이에 닫음 · 창구의 거부(기준 레이어 없음 등). 반환 qty_added · unit_cost · cost_source · layer_id · ledger{…} · family · open_diffs_left. ⚠️ 빈은 건드리지 않는다. security invoker · 잠금 for update. 정본 po-module §11-i';
revoke all on function public.po_receipt_diff_settle_over(uuid, text, text) from public, anon;
grant execute on function public.po_receipt_diff_settle_over(uuid, text, text) to authenticated;

-- ═══ ⑦ po_receipt_diff_resolve — 다시 냄 (원본 20260919175712:127~195 · 바뀐 것 2줄 · over 거부 문장) ═══
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
    raise exception 'Line % (%) on % is an "%" difference — only short differences are settled here. An over difference puts the extra into stock: settle it with po_receipt_diff_settle_over (reason free · billed · credited) — nothing was saved',
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

comment on function public.po_receipt_diff_resolve(uuid, text, text) is '⑤⭐ 차이 닫기(short 만 · 2026-09-19 · Caleb) — 이유 어휘 다섯(split_shipment · out_of_stock · lost_damaged · miscount · other[메모 필수])으로 닫고 resolution·resolved_by(서버 유도)·resolved_at 을 함께 채운다. 막는 것(읽을 수 있는 문장): 권한(receiving) · 어휘 밖 · other 인데 메모 없음 · 없는 차이 · ⭐ over 는 거부하며 형제 함수 po_receipt_diff_settle_over 를 가리킨다(2026-09-20 · 초과분을 재고에 넣는다) · 이미 닫힘(누가·무엇으로·언제 + reopen 안내) · 남이 사이에 닫음(row_count 0). 반환에 family(형제 합계 · 제품 단위)와 open_diffs_left. security invoker · 잠금 for update. 정본 po-module §11-i';
revoke all on function public.po_receipt_diff_resolve(uuid, text, text) from public, anon;
grant execute on function public.po_receipt_diff_resolve(uuid, text, text) to authenticated;

-- ═══ ⑧ po_receipt_diff_reopen — 다시 냄 (원본 20260919175712:202~241 · 더한 것: over 거부) ═══
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

comment on function public.po_receipt_diff_reopen(uuid, text) is '⑤ 차이 되돌리기(2026-09-19) — 닫힌 차이의 resolution·resolved_by·resolved_at 을 함께 비운다(CHECK 가 셋을 묶는다). resolution_note 는 지우지 않고 새 메모를 주면 「reopened: … | was: <이유>」로 덧붙인다(흔적). 막는 것: 권한 · 없는 차이 · 안 닫힌 것 · ⭐ over 로 닫힌 것(2026-09-20 · 초과분이 원장·레이어에 들어갔다 — append-only · 상쇄 길은 별도 차수) · 남이 사이에 되돌림. 반환에 was_* 와 open_diffs_left. security invoker. 정본 po-module §11-i';
revoke all on function public.po_receipt_diff_reopen(uuid, text) from public, anon;
grant execute on function public.po_receipt_diff_reopen(uuid, text) to authenticated;

-- ═══ ⑨ inv_layer_apply — 다시 냄 (원본 20260920142635:111~523 · 더한 것: 초과분 분기 · 반환 ims.over_*) ═══
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

  -- 날짜순 루프 — ⭐ 사건 9종 전부 (order by occurred_on, seq_hint, id · source 필터 없음)
  for r in
    select id, event_type
      from inv_ledger
      where event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                           'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
        and (p_until is null or occurred_on <= p_until)
      order by occurred_on, seq_hint, id
  loop
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
      select source, doc_task_id, doc_number into v_ims_src, v_ims_task, v_ims_docno from inv_ledger where id = r.id;   -- 루프 select 는 바꾸지 않는다(원문 무변) — PK 조회 한 번
      if v_ims_src = 'ims' and v_ims_task is not null
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
      select * into v_layers, v_traced, v_avg, v_unk, v_nz, v_proc from inv_layer_apply_credit(r.id, p_until);
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
      'skip_reasons',              v_ims_skip),             -- [{kind receipt|charge · number · id · sqlstate · error}] — 이유 문장 그대로
    'skipped_by_type',           v_skipped,
    'layers_created',            v_layers_po,
    'consume_rows',              v_consume,
    'cost_unknown_layers',       v_unknown,
    'short_events',              v_shorts,
    'elapsed_ms',                round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$$;

revoke all on function inv_layer_apply(date) from public, anon;
grant execute on function inv_layer_apply(date) to authenticated;
comment on function inv_layer_apply(date) is '⭐ 원가 레이어 전량 재생성(검산 도구 · 사람이 부를 때만 돈다 · cron 없음) — baseline 외 inv_layer · inv_layer_consume · inv_layer_cost_add 를 지우고 원장(inv_ledger · ⚠️ source 필터 없음 — cin7·manual·ims 전부)을 날짜순으로 다시 태운다. Cin7 줄은 inv_cost 로(보조 여섯), ⭐ IMS 줄(source ims · 2026-09-20)은 창구로 — 입고는 루프 안에서 inv_layer_post_receipt(입고 단위 · doc_task_id) · ⭐ 초과분(line_ref po_line_id:over · over 닫기 2026-09-20)은 루프 안에서 inv_layer_post_receipt_over(차이 단위 · raw.diff_id · 기준 레이어 뒤) · 비용은 끝에서 inv_layer_post_charge. 창구가 거부한 것은 멈추지 않고 건너뛰어 센다 — 반환 ims.receipts_skipped · over_skipped · charges_skipped · skip_reasons[]. 권한: 창구가 receiving·purchasing 쓰기 권한을 보므로 시작에서 막는다(psql 은 request.jwt.claims). 반환 45칸 무변 + ims{} 중첩. 원본 20260910141553 → 20260920142635 → 20260920171930';
