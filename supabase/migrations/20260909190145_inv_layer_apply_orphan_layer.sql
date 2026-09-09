-- 원가 레이어 사건 적재 — 기초 이전 출발 트랜스퍼: 부족분만큼 원가 미상 도착 레이어를 만든다 (2026-09-09 저녁)
--
-- 20260909183253 의 inv_layer_apply_transfer_in · inv_layer_apply 를 덮어쓴다(그 파일과 174046 은 테스트 DB 에 적용돼 손대지 않는다).
--
-- ═══ ⚠️⚠️ 판정을 두 번 뒤집었다 — 경위 ═══
--  1차 (설계 09-08 · ledger-design §원가 레이어 6번): 「IN_TRANSIT 에 소진할 레이어가 없으면 **도착 레이어를 원가 미상으로 만든다**」
--  2차 (09-09 오후 · 174046 C-4 · ⚠️ 오판): 「**만들지 않는다.** 만들면 없는 재고를 만드는 셈이다」 — 근거로 든 것: 스킬의
--      「상쇄하면 없던 사건을 만드는 셈이다」(2026-08-28 IN_TRANSIT 기초 경계 결정) · 「원장이 IN_TRANSIT 잔고를 영구히 음수로
--      남겨두고 채우지 않는다」. ⚠️⚠️ **틀렸다 — 두 축을 섞었다.** 「없는 재고」는 IN_TRANSIT 축의 음수 얘기고, **에드먼튼(real 축)
--      에는 재고가 실재한다** — 원장이 인정하고 Cin7 도 인정한다.
--  3차 (09-09 저녁 · 실측으로 확정 · 이 파일): 「**부족한 만큼 도착 창고에 원가 미상 레이어를 만든다.**」 — 1차가 맞았다.
--
--  ⭐ 결정적 실측 — RIN01018 (에드먼튼)
--    inv_balance: baseline 0 · delta +34 · qty 34   ← 원장은 34개를 인정한다
--    inv_layer:   에드먼튼 레이어 0개                 ⚠️ 레이어에는 없다
--    원장 사건: TR-03975 transfer_in EDM +48 (도착만) · TR-03975 transfer_out IN_TRANSIT −48 (IN_TRANSIT in 이 없다 — 8/14 출발 ·
--              since 로 제외) · TR-04183 (bin 이동 4행 완비) · SO-15477 sale_out −12 · SO-15579 −2
--  ⚠️ Cin7 에는 출발이 있다 — [실측 Movements 화면 2026-09-09] 08/14 Transfer out TR-03975 Asung Trading Inc.: D100401 −48 →
--     08/26 Transfer in TR-03975 Asung - Edmonton +48. ⇒ ⭐ 그래도 원가는 알 수 없다 — 그 48개의 원가는 「8/14 시점 토론토
--     D100401 의 원가」인데 우리 레이어의 시작점은 8/20 기초다. 그리고 8/20 기초에도 그 48개는 없다(이미 출발 · 도착 전 · IN_TRANSIT ·
--     inv-snapshot 은 OnHand 만 읽는다). ⇒ 원장이 제외한 것은 정확하고, 그 재고의 원가 근거는 어디에도 없다.
--  ⚠️⚠️ 레이어를 만들지 않으면 연쇄가 난다: TR-03975 IN_TRANSIT 부족 → 에드먼튼 레이어 0 (뿌리) → TR-04183 에드먼튼에서 뺄 것이
--     없다 → short (파생) → 판매 14개 short (파생). ⭐ 하나의 뿌리가 여러 부족을 만든다. [실측] same_day 부족 207건 · 1,639개가 전부
--     이 연쇄이고, 에드먼튼 레이어가 원장보다 **−2,449** 모자란다(IN_TRANSIT 은 정확히 짝인 **+2,450** 초과).
--  ⇒ ⭐ **판정 기준: 「원장(real 축)이 그 재고를 인정하는가」.** 인정하면 레이어를 만든다 — 원가를 모르는 것과 재고가 없는 것은
--     다르다. 「모르면 비워둔다」는 **원가를 비우는 것**이지 **재고를 없애는 것**이 아니다.
--
-- ═══ 고친 것 (inv_layer_apply_transfer_in · 출발 레이어가 부족할 때) ═══
--  · 종전(C-4): 있는 만큼만 소진 · 부족분은 도착 레이어를 만들지 않는다 · short_events +1
--  · ⭐ 지금: 있는 만큼은 정상 이동(parent_layer 복사) · **부족분만큼 도착 창고에 원가 미상 레이어 하나**
--      origin_type 'transfer' · cost_source 'unknown' · unit_cost 0 · parent_layer_id null · age_known false ·
--      received_on = 그 원장 행의 occurred_on · doc_number = TR 번호 · line_ref = 그 원장 행의 line_ref
--  · ⚠️ unknown 레이어를 만든 경우 short_events 는 올리지 않는다 — 부족이 아니다. 새 카운터 **transfer_unknown_layers**(레이어 수) ·
--    **transfer_unknown_qty**(수량 — 「얼마나」)로 센다. 범위 밖 부족은 종전대로 short_events 다(아래 적용 범위).
--  · ⚠️ transfer_orphan_in 과 구분한다 — 둘 다 unknown 레이어를 만들지만 원인이 다르다:
--      transfer_orphan_in     = out leg 행이 **아예 없다** ([실측] 0건 · 방어 경로)
--      transfer_unknown_layers = out leg 는 있는데 **소진할 레이어가 없다** ([실측] 이것이 2,449개의 정체)
--  · ⭐ **적용 범위 — 기초 이전 출발(IN_TRANSIT 출발 부족 · 쌍1 이 원장에 없음)만이다** (Caleb 판정 2026-09-09 저녁).
--    판정 기준(「원장이 real 축 재고를 인정하는가」)은 출발 창고와 무관하다. **그러나 「나중에 해소되는가」가 갈린다:**
--      IN_TRANSIT 출발 부족 (leg 1·2 기초 이전) | 인정 | ⚠️ **영구** — 재기준선까지 남는다
--      창고 출발 부족                            | 인정 | ⭐ **해소** — 미처리 adjust_existing(157행)·assemble·credit_in 을 붙이면 저절로 사라진다
--    ⚠️⚠️ 창고 출발 부족에 unknown 레이어를 만들면 **미처리 사건이 만든 부족을 원가 미상으로 덮는다** — 그 축을 붙일 때 「원가 미상이 왜
--    이렇게 많나」를 다시 파야 하고, ⭐ short_events 가 「아직 안 붙인 것」을 알려주는 신호를 잃는다.
--    ⇒ **「영구히 원가를 모르는 것」과 「아직 안 붙인 것」을 섞지 않는다.**
--    📌 [실측] 창고 출발 부족의 실체는 소분 제품군(AS91...)이고 벌크가 non-inventory 로 입고돼 adjust_existing 증가로만 재고가 생긴다
--    ⇒ 그 축을 붙이면 해소되는 것이 확인돼 있다. 📌 ⬜ 미처리 사건 넷을 다 붙인 뒤 창고 출발 부족이 남으면 그때 다시 판단한다
--    (그때는 「영구」로 확정되므로 범위를 넓히는 것이 맞을 수 있다).
--    ⚠️ **조건은 두 개다** — v_out_wh = 'IN_TRANSIT' 만으로는 부족하다: 창고 출발 부족은 쌍1 에서 short 로 남지만 그 때문에 IN_TRANSIT
--    레이어가 모자라 **쌍2 가 「IN_TRANSIT 출발 부족」으로 보여** 에드먼튼에 unknown 을 만들게 된다(한 단계 건너 덮인다). 「영구」의
--    실체는 **그 문서의 IN_TRANSIT in leg(쌍1)가 원장에 없다**는 것이므로 그것을 함께 본다:
--      unknown 레이어 = IN_TRANSIT 출발 부족 **AND** 같은 (doc, sku) 의 transfer_in@IN_TRANSIT 행이 원장에 없음
--      그 외 부족(창고 출발 · 쌍1 이 있는 IN_TRANSIT 부족 = 전파된 것) = 종전대로 short_events +1 · 도착 레이어 없음
--  · ⚠️ **sale_out 은 바꾸지 않는다** — 판매는 부족하면 그대로 short 다(재고가 나가는 사건 · 원가 미상 레이어를 만들 이유가 없다).
--    inv_layer_fifo_take · inv_layer_apply_sale_out · inv_layer_apply_po_in 은 183253/174046 그대로다.
--
-- 반환 jsonb 추가: transfer_unknown_layers · transfer_unknown_qty. 나머지 키는 20260909183253 과 같다.

drop function if exists inv_layer_apply_transfer_in(bigint, date);

-- ── 보조 3: transfer_in 한 행 → 대응 out 을 먼저 소진하고 도착 레이어 생성 · 부족분은 원가 미상 도착 레이어 ──
--   o_layers = 도착 레이어 수(unknown 포함) · o_rows = consume 행 수 · o_short = 범위 밖 부족(창고 출발 · 전파된 IN_TRANSIT 부족) ·
--   o_orphan = out 행 자체가 없어 만든 unknown 레이어 수 · o_net_zero = in 순액 ≤ 0 키 수 ·
--   o_unknown = 출발 부족으로 만든 unknown 레이어 수 · o_unknown_qty = 그 수량 · o_processed = 이 호출이 in 키를 처리했으면 1
create or replace function inv_layer_apply_transfer_in(p_ledger_id bigint, p_until date,
                                                       out o_layers int, out o_rows int, out o_short int,
                                                       out o_orphan int, out o_net_zero int,
                                                       out o_unknown int, out o_unknown_qty numeric, out o_processed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r         inv_ledger%rowtype;
  v_out_wh  text;
  v_out     record;
  v_out_net numeric;
  v_in_net  numeric;
  v_it      record;
  v_rows int; v_short int; v_layers int; v_taken numeric; v_orphan int; v_nz int; v_unk int; v_unkq numeric; v_proc int;
  v_missing numeric;
begin
  o_layers := 0; o_rows := 0; o_short := 0; o_orphan := 0; o_net_zero := 0; o_unknown := 0; o_unknown_qty := 0; o_processed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found then return; end if;

  if exists (select 1 from inv_layer_apply_done d
              where d.kind = 'tr_in' and d.doc_number = r.doc_number and d.sku = r.sku
                and d.warehouse = r.warehouse and d.day = r.occurred_on) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse, day) values ('tr_in', r.doc_number, r.sku, r.warehouse, r.occurred_on);
  o_processed := 1;

  -- ⓪ 창고 in 인데 같은 (doc, sku) 의 IN_TRANSIT in 이 아직 안 처리됐으면 그것부터 (같은 날 id 순서 무관)
  if r.warehouse <> 'IN_TRANSIT' then
    for v_it in
      select id from inv_ledger i
        where i.doc_number = r.doc_number and i.sku = r.sku and i.warehouse = 'IN_TRANSIT' and i.event_type = 'transfer_in'
          and i.occurred_on <= r.occurred_on and (p_until is null or i.occurred_on <= p_until)
          and not exists (select 1 from inv_layer_apply_done d
                            where d.kind = 'tr_in' and d.doc_number = i.doc_number and d.sku = i.sku
                              and d.warehouse = 'IN_TRANSIT' and d.day = i.occurred_on)
        order by i.occurred_on, i.id
    loop
      select * into v_layers, v_rows, v_short, v_orphan, v_nz, v_unk, v_unkq, v_proc from inv_layer_apply_transfer_in(v_it.id, p_until);
      o_layers := o_layers + v_layers; o_rows := o_rows + v_rows; o_short := o_short + v_short;
      o_orphan := o_orphan + v_orphan; o_net_zero := o_net_zero + v_nz;
      o_unknown := o_unknown + v_unk; o_unknown_qty := o_unknown_qty + v_unkq;
    end loop;
  end if;

  -- ⓪′ in leg 순액 — 0 이하면 상쇄로 소멸한 키: 처리할 것이 없다
  select sum(qty_delta) into v_in_net
    from inv_ledger
    where doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse and event_type = 'transfer_in'
      and (p_until is null or occurred_on <= p_until);
  if v_in_net is null or v_in_net <= 0 then
    o_net_zero := o_net_zero + 1;
    return;
  end if;

  -- ① 대응 out leg 의 창고
  if r.warehouse = 'IN_TRANSIT' then
    select warehouse into v_out_wh
      from inv_ledger
      where doc_number = r.doc_number and sku = r.sku and warehouse <> 'IN_TRANSIT'
        and event_type in ('transfer_out', 'manual_reversal')
        and (p_until is null or occurred_on <= p_until)
      order by (occurred_on = r.occurred_on) desc, occurred_on, id
      limit 1;
  else
    v_out_wh := 'IN_TRANSIT';
  end if;

  -- ② out leg 의 키 순액 × −1
  if v_out_wh is not null then
    select -sum(qty_delta) into v_out_net
      from inv_ledger
      where doc_number = r.doc_number and sku = r.sku and warehouse = v_out_wh
        and event_type in ('transfer_out', 'manual_reversal')
        and (p_until is null or occurred_on <= p_until);
    select doc_type, line_ref, event_type, occurred_on into v_out
      from inv_ledger
      where doc_number = r.doc_number and sku = r.sku and warehouse = v_out_wh and event_type = 'transfer_out'
        and (p_until is null or occurred_on <= p_until)
      order by (occurred_on = r.occurred_on) desc, id
      limit 1;
  end if;

  if v_out_wh is null or v_out_net is null or v_out_net <= 0 or v_out is null then
    -- C-3 대응 out **행 자체** 없음(방어 경로) — unknown 도착 레이어 · transfer_orphan_in
    insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                           received_on, age_known, qty, unit_cost, cost_source)
    values (r.sku, r.warehouse, 'transfer', r.doc_number, r.line_ref, null,
            r.occurred_on, false, v_in_net, 0, 'unknown');
    o_layers := o_layers + 1;
    o_orphan := o_orphan + 1;
    return;
  end if;

  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('tr_out', r.doc_number, r.sku, v_out_wh)
    on conflict do nothing;

  -- ②③ 출발 FIFO 소진 + 소진한 레이어마다 도착 레이어 (parent_layer 복사)
  select * into v_rows, v_short, v_layers, v_taken
    from inv_layer_fifo_take(r.sku, v_out_wh, v_out_net,
                             v_out.doc_type, r.doc_number, v_out.line_ref, v_out.event_type, v_out.occurred_on,
                             'transfer', r.warehouse);
  o_rows := o_rows + v_rows; o_layers := o_layers + v_layers;

  -- ⭐ 부족분 — 기초 이전 출발(IN_TRANSIT 출발 · 쌍1 이 원장에 없음)만 도착 창고에 원가 미상 레이어 (헤더 「적용 범위」).
  --    그 외 부족(창고 출발 · 쌍1 이 있는 IN_TRANSIT 부족 = 전파된 것)은 종전대로 short — 「아직 안 붙인 것」의 신호로 남긴다.
  v_missing := v_out_net - coalesce(v_taken, 0);
  if v_missing > 0 then
    if v_out_wh = 'IN_TRANSIT'
       and not exists (select 1 from inv_ledger i
                         where i.doc_number = r.doc_number and i.sku = r.sku and i.warehouse = 'IN_TRANSIT'
                           and i.event_type = 'transfer_in'
                           and (p_until is null or i.occurred_on <= p_until)) then
      insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                             received_on, age_known, qty, unit_cost, cost_source)
      values (r.sku, r.warehouse, 'transfer', r.doc_number, r.line_ref, null,
              r.occurred_on, false, v_missing, 0, 'unknown');
      o_layers := o_layers + 1;
      o_unknown := o_unknown + 1;
      o_unknown_qty := o_unknown_qty + v_missing;
    else
      o_short := o_short + 1;
    end if;
  end if;
end;
$$;

-- ── main: 카운터 둘 추가 (transfer_unknown_layers · transfer_unknown_qty) ──
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
  v_layers_po   int := 0;
  v_consume     int := 0;
  v_unknown     int := 0;
  v_shorts      int := 0;
  v_skipped     jsonb;
begin
  select count(*) into v_baseline from inv_layer where origin_type = 'baseline';
  if v_baseline = 0 then
    raise exception 'inv_layer has no baseline layers — run inv_layer_seed_baseline first';
  end if;

  delete from inv_layer_consume;
  delete from inv_layer_cost_add;
  delete from inv_layer where origin_type <> 'baseline';
  perform inv_layer_apply_reset_done();

  for r in
    select id, event_type
      from inv_ledger
      where event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal')
        and (p_until is null or occurred_on <= p_until)
      order by occurred_on, seq_hint, id
  loop
    if r.event_type = 'po_in' then
      select * into v_c, v_u from inv_layer_apply_po_in(r.id, p_until);
      v_po := v_po + 1; v_layers_po := v_layers_po + v_c; v_unknown := v_unknown + v_u;
    elsif r.event_type = 'sale_out' then
      select * into v_rows, v_short, v_proc, v_rev from inv_layer_apply_sale_out(r.id, p_until);
      v_sale := v_sale + 1; v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_sale_keys := v_sale_keys + v_proc; v_sale_rev := v_sale_rev + v_rev;
    elsif r.event_type = 'transfer_in' then
      select * into v_layers, v_rows, v_short, v_orphan, v_nz, v_unk, v_unkq, v_proc from inv_layer_apply_transfer_in(r.id, p_until);
      v_tr := v_tr + 1; v_tr_layers := v_tr_layers + v_layers; v_consume := v_consume + v_rows;
      v_shorts := v_shorts + v_short; v_tr_orphan := v_tr_orphan + v_orphan; v_tr_nz := v_tr_nz + v_nz;
      v_tr_unk := v_tr_unk + v_unk; v_tr_unkq := v_tr_unkq + v_unkq;
    else
      v_tr := v_tr + 1;
    end if;
  end loop;

  select count(*) into v_tr_unpaired
    from (select doc_number, sku, warehouse
            from inv_ledger
            where event_type in ('transfer_out', 'manual_reversal')
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'tr_out' and d.doc_number = o.doc_number and d.sku = o.sku and d.warehouse = o.warehouse);

  select coalesce(jsonb_object_agg(event_type, n), '{}'::jsonb) into v_skipped
    from (select event_type, count(*) as n
            from inv_ledger
            where event_type not in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal')
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
    'skipped_by_type',           v_skipped,
    'layers_created',            v_layers_po,
    'consume_rows',              v_consume,
    'cost_unknown_layers',       v_unknown,
    'short_events',              v_shorts,
    'elapsed_ms',                round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$$;

revoke all on function inv_layer_apply_transfer_in(bigint, date) from public, anon, authenticated;
revoke all on function inv_layer_apply(date) from public, anon;
grant execute on function inv_layer_apply(date) to authenticated;
