-- 원가 레이어 사건 적재 — inv_layer_apply(p_until) + 보조 둘 (2026-09-09)
--
-- 배경: inv_layer(20260908195949) 는 그릇, inv_layer_seed_baseline(20260908202555) 은 기초만 깐다.
-- 여기서 처음으로 **원장 사건**을 레이어에 반영한다 — 입고(po_in)는 레이어를 만들고, 판매(sale_out)는 FIFO 로 소진한다.
--
-- 무엇을 하나 — ⚠️ 이번 단계는 po_in + sale_out **둘만**이다.
--  transfer / adjust_existing / adjust_new / assemble / credit_in 은 **미착수**이고 skipped_by_type 으로 센다(예외 아님).
--  ⚠️ 그러므로 이 단계에서 「레이어 잔량 = 원장 잔고」는 **맞지 않는다** —
--  ⭐ **차이가 정확히 미처리 사건의 합과 같은지**가 이번 단계의 검산이다(inv_layer_open 잔량 vs inv_balance).
--
-- ⚠️ 전량 재생성인 이유 — **커서를 두지 않는다.** 원가가 뒤늦게 붙고(landed · Simple 결손) 규칙도 바뀔 것이라
--  매번 다시 만드는 것이 불변 조건(레이어 = inv_ledger + inv_cost + inv_snapshot 으로 전량 재생성)과 같은 모양이다.
--  매 호출: ① inv_layer_consume 전량 delete → ② inv_layer_cost_add 전량 delete → ③ inv_layer 의 baseline 외 전량 delete.
--  ⚠️ FK 때문에 순서가 중요하다 — consume·cost_add 가 layer 를 참조하므로 먼저 지운다.
--  ⚠️ baseline 은 지우지 않는다 — inv_layer_seed_baseline 이 관할한다. baseline 이 0건이면 예외(기초 없이 소진하면
--  전부 부족으로 처리된다).
--  ⚠️ 속도는 재보고 판단한다 — inv_balance 가 3.9초를 겪고 구체화를 검토한 것과 같은 순서로.
--
-- ⭐ 정렬 근거 — order by occurred_on, seq_hint, id.
--  [실측 2026-09-09] seq_hint 1 = 유입(전량 양수) · 2 = 유출(전량 음수) · 예외 0건.
--  ⚠️ 「같은 날은 유입 먼저」를 **원장이 이미 보장한다** — 우리가 부호로 분기하지 않는다.
--  ⚠️ adjust_existing 은 seq_hint 1(41행 양수)과 2(116행 음수) 양쪽에 있다 — event_type 만으로 분기하면 틀린다.
--  다음 단계에서 주의(이번 단계는 그 타입을 건드리지 않는다).
--
-- po_in → 레이어 생성 (inv_layer_apply_po_in)
--  · ⚠️ 원장 행 하나 = 레이어 하나가 **아니다.** 원장은 bin 단위, 레이어는 창고 단위 ⇒ 같은 (doc_number, line_ref, sku,
--    warehouse) 의 원장 행들을 **합쳐** 레이어 하나로. 루프는 행마다 부르므로 **그 키로 이미 만들었으면 만들지 않는다.**
--  · 원가 = inv_cost 의 cost_kind='goods' · 같은 4키 · **sum(amount) / sum(qty)**(bin 이 여럿이라 반드시 합산).
--    ⚠️ amount 축을 쓴다 — amount_orig × fx_rate 로 재계산하지 않는다(할인이 빠진다).
--  · cost_source = 'inv_cost' / 행이 없으면 **'unknown' · unit_cost 0** · cost_unknown_layers +1
--    (Simple Purchase 결손 · 아직 수집 안 된 입고 둘 다 여기 온다).
--  · received_on = 원장 occurred_on(키 안 최솟값) · age_known = true · qty = 그 키의 qty_delta 합(양수만) ·
--    origin_type = 'purchase' · parent_layer_id = null.
--
-- sale_out → FIFO 소진 (inv_layer_apply_sale_out)
--  · 그 SKU×창고의 레이어를 order by received_on, id 로 열어 오래된 것부터 뺀다(inv_layer_fifo_idx).
--  · 남은 수량 = qty − 이미 쌓인 consume 합 — ⚠️ inv_layer_open 뷰를 쓰지 않고 직접 계산한다(루프 안 뷰 반복 조회는 느리다).
--  · inv_layer_consume 행: reason='sale' · unit_cost = **그 레이어의 unit_cost**(⭐ 소비 시점 값을 굳힌다) ·
--    amount = qty × unit_cost · event_type/doc_*/occurred_on 은 원장 행에서. 원장 qty_delta 는 음수 ⇒ abs().
--  · ⚠️ 레이어가 부족하면 있는 만큼만 소진하고 부족분은 consume 을 만들지 않는다 · short_events +1 · **예외 없음**
--    (IN_TRANSIT 음수 215칸이 구조적으로 존재한다 — 기초 경계 · 버그 아님 · ledger-design §원가 레이어 6번).
--
-- ⚠️ cost_source CHECK 에 'unknown' 을 추가한다(아래 alter). 이유: 원장에 입고가 있는데 inv_cost 가 없는 경우가
--  **영구적으로 존재한다**(Simple Purchase 결손 · 수집 지연). 레이어를 안 만들면 수량이 원장과 어긋나 대조 안전망이
--  깨지고, 0 으로 두면 프로모션 무상 재고와 구분이 안 된다 ⇒ **「모르면 비워둔다」를 cost_source 로 표시한다.**
--
-- ⚠️ **원가 가드 — 음수 금액·0 수량은 거부한다.** (inv_layer_apply_po_in · inv_cost 행이 **있을 때만** — 행 0건은 위 unknown 경로)
--  inv_layer_cost_ck(unit_cost >= 0) 에 걸려 어차피 실패하는데, 그때는 제약 위반 메시지만 나오고 **22,285 사건 중 어느 문서
--  때문인지 알 수 없다.** 그래서 insert 전에 4키와 금액을 담아 예외를 던진다.
--  [실측 2026-09-09 테스트 DB] goods 514키 중 amount < 0 **0건** · qty <= 0 **0건** · 최소 단가 $0.879792 ⇒ 지금은 안전하다.
--  ⚠️ 그러나 Cin7 은 재평가로 값을 바꾸고 같은 (ProductID, Date) 에 상쇄 행(+A/−A/+B)이 쌓일 수 있다 — 순액이 음수가 되는
--  조합이 언제든 나올 수 있다. ⚠️ 0 으로 깎지 않는다 — 음수 원가는 우리가 판단할 수 없는 값이고 사람이 원인을 보게
--  해야 한다(「모르면 비워둔다」).
--
-- 반환 jsonb: { until, processed_po_in, processed_sale_out, skipped_by_type, layers_created, consume_rows,
--               cost_unknown_layers, short_events, elapsed_ms }
--  processed_* 는 **원장 행 수**(레이어 수가 아니다 — 두 bin 행이 레이어 하나가 된다). skipped_by_type 은 처리하지
--  않은 event_type 별 행 수(집계 쿼리 한 번 · 루프에서 세지 않는다).
--
-- ⚠️ security definer — inv_layer 는 authenticated 의 delete 를 회수했다(inv_layer 헤더). 전량 재생성은 delete 가
--  필수라 소유자 권한으로 돈다(inv_layer_seed_baseline 과 같은 사유). 보조 둘은 main 이 부르는 용도라 authenticated 에
--  execute 를 주지 않는다(definer 인 main 은 소유자 권한이라 부를 수 있다).
--
-- 조회 예시:
--   select inv_layer_apply();                          -- 전량
--   select inv_layer_apply('2026-08-31');              -- 그날까지만(as-of)
--   select l.sku, l.warehouse, sum(o.remaining_qty), round(sum(o.remaining_cost),2)
--   from inv_layer_open o join inv_layer l on l.id = o.id group by 1,2 order by 1,2;
--   select cost_source, count(*), sum(qty) from inv_layer where origin_type='purchase' group by 1;

-- ── CHECK 확장 — 'unknown' 추가 (이유는 헤더) ──
alter table inv_layer drop constraint inv_layer_source_ck;
alter table inv_layer add constraint inv_layer_source_ck check (cost_source in (
  'inv_cost','snapshot_value','cin7_unitcost',
  'layer_avg','assembly_sum','parent_layer','unknown'));

-- ── 보조 1: po_in 한 행 → 그 행의 4키 레이어가 없으면 만든다 ──
--   o_created = 만든 레이어 수(0 또는 1) · o_unknown = 그 레이어가 원가 미상이면 1
create or replace function inv_layer_apply_po_in(p_ledger_id bigint, p_until date,
                                                 out o_created int, out o_unknown int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r             inv_ledger%rowtype;
  v_qty         numeric;
  v_received_on date;
  v_cost_amt    numeric;
  v_cost_qty    numeric;
  v_unit        numeric;
  v_source      text;
begin
  o_created := 0; o_unknown := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found then return; end if;

  -- 이미 그 키로 만들었으면 끝 (두 번째 bin 행 · 같은 CardID)
  if exists (select 1 from inv_layer l
              where l.origin_type = 'purchase' and l.doc_number = r.doc_number and l.line_ref = r.line_ref
                and l.sku = r.sku and l.warehouse = r.warehouse) then
    return;
  end if;

  -- 키의 원장 합 (양수만 · p_until 안) — bin 을 버리고 창고 단위로
  select sum(qty_delta), min(occurred_on) into v_qty, v_received_on
    from inv_ledger
    where source = 'cin7' and event_type = 'po_in' and qty_delta > 0
      and doc_number = r.doc_number and line_ref = r.line_ref and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until);
  if v_qty is null or v_qty <= 0 then return; end if;

  -- 원가: inv_cost goods · 4키 합산 · amount 축
  select sum(amount), sum(qty) into v_cost_amt, v_cost_qty
    from inv_cost
    where cost_kind = 'goods'
      and doc_number = r.doc_number and line_ref = r.line_ref and sku = r.sku and warehouse = r.warehouse;
  -- 원가 가드 (헤더) — 행이 있는데 값이 음수이거나 수량이 0 이하면 거부. 행 0건(v_cost_qty null)은 아래 unknown 경로.
  if v_cost_qty is not null then
    if v_cost_amt < 0 then
      raise exception 'inv_cost goods sum(amount) is negative for % / % / % / %: % — refusing to build layer (revaluation offset? inspect inv_cost)',
        r.doc_number, r.line_ref, r.sku, r.warehouse, v_cost_amt;
    end if;
    if v_cost_qty <= 0 then
      raise exception 'inv_cost goods sum(qty) is % (<= 0) for % / % / % / % — refusing to build layer (division by zero)',
        v_cost_qty, r.doc_number, r.line_ref, r.sku, r.warehouse;
    end if;
  end if;
  if v_cost_qty is not null then
    v_unit := round(v_cost_amt / v_cost_qty, 6);
    v_source := 'inv_cost';
  else
    v_unit := 0;
    v_source := 'unknown';
    o_unknown := 1;
  end if;

  insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                         received_on, age_known, qty, unit_cost, cost_source)
  values (r.sku, r.warehouse, 'purchase', r.doc_number, r.line_ref, null,
          v_received_on, true, v_qty, v_unit, v_source);
  o_created := 1;
end;
$$;

-- ── 보조 2: sale_out 한 행 → FIFO 소진 ──
--   o_rows = 만든 consume 행 수 · o_short = 레이어가 부족했으면 1
create or replace function inv_layer_apply_sale_out(p_ledger_id bigint,
                                                    out o_rows int, out o_short int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r         inv_ledger%rowtype;
  v_need    numeric;
  v_take    numeric;
  l         record;
begin
  o_rows := 0; o_short := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found then return; end if;
  v_need := abs(r.qty_delta);
  if v_need <= 0 then return; end if;

  -- 오래된 것부터 — inv_layer_fifo_idx (sku, warehouse, received_on, id)
  for l in
    select x.id, x.unit_cost,
           x.qty - coalesce((select sum(c.qty) from inv_layer_consume c where c.layer_id = x.id), 0) as remaining
      from inv_layer x
      where x.sku = r.sku and x.warehouse = r.warehouse
      order by x.received_on, x.id
  loop
    exit when v_need <= 0;
    if l.remaining <= 0 then continue; end if;
    v_take := least(l.remaining, v_need);
    insert into inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on,
                                   qty, unit_cost, amount, reason)
    values (l.id, r.doc_type, r.doc_number, r.line_ref, r.event_type, r.occurred_on,
            v_take, l.unit_cost, round(v_take * l.unit_cost, 6), 'sale');
    o_rows := o_rows + 1;
    v_need := v_need - v_take;
  end loop;

  if v_need > 0 then o_short := 1; end if;   -- 부족분은 consume 을 만들지 않는다 · 예외 없음
end;
$$;

-- ── main: 전량 재생성 · 날짜순 루프 ──
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
  v_c           int; v_u int; v_rows int; v_short int;
  v_po          int := 0;
  v_sale        int := 0;
  v_layers      int := 0;
  v_consume     int := 0;
  v_unknown     int := 0;
  v_shorts      int := 0;
  v_skipped     jsonb;
begin
  -- 가드: 기초 없이 소진하면 전부 부족으로 처리된다
  select count(*) into v_baseline from inv_layer where origin_type = 'baseline';
  if v_baseline = 0 then
    raise exception 'inv_layer has no baseline layers — run inv_layer_seed_baseline first';
  end if;

  -- 전량 재생성 — FK 순서: consume · cost_add 먼저, 그 다음 baseline 외 레이어
  delete from inv_layer_consume;
  delete from inv_layer_cost_add;
  delete from inv_layer where origin_type <> 'baseline';

  -- 날짜순 루프 — ⭐ order by occurred_on, seq_hint, id 가 「같은 날은 유입 먼저」를 보장한다
  for r in
    select id, event_type
      from inv_ledger
      where source = 'cin7'
        and event_type in ('po_in', 'sale_out')
        and (p_until is null or occurred_on <= p_until)
      order by occurred_on, seq_hint, id
  loop
    if r.event_type = 'po_in' then
      select * into v_c, v_u from inv_layer_apply_po_in(r.id, p_until);
      v_po := v_po + 1; v_layers := v_layers + v_c; v_unknown := v_unknown + v_u;
    else
      select * into v_rows, v_short from inv_layer_apply_sale_out(r.id);
      v_sale := v_sale + 1; v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
    end if;
  end loop;

  -- 미처리 사건 — 종류별 행 수 (루프 밖 집계 한 번)
  select coalesce(jsonb_object_agg(event_type, n), '{}'::jsonb) into v_skipped
    from (select event_type, count(*) as n
            from inv_ledger
            where source = 'cin7'
              and event_type not in ('po_in', 'sale_out')
              and (p_until is null or occurred_on <= p_until)
            group by event_type) s;

  return jsonb_build_object(
    'until',               p_until,
    'processed_po_in',     v_po,
    'processed_sale_out',  v_sale,
    'skipped_by_type',     v_skipped,
    'layers_created',      v_layers,
    'consume_rows',        v_consume,
    'cost_unknown_layers', v_unknown,
    'short_events',        v_shorts,
    'elapsed_ms',          round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$$;

revoke all on function inv_layer_apply_po_in(bigint, date) from public, anon, authenticated;
revoke all on function inv_layer_apply_sale_out(bigint) from public, anon, authenticated;
revoke all on function inv_layer_apply(date) from public, anon;
grant execute on function inv_layer_apply(date) to authenticated;
