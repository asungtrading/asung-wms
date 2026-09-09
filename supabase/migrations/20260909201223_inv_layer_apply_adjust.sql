-- 원가 레이어 사건 적재 — adjust_existing + adjust_new (2026-09-09 저녁)
--
-- 20260909190145 의 inv_layer_apply(main) 를 create or replace 로 덮어쓴다(루프 분기 추가). 보조 inv_layer_apply_adjust 는 신규.
-- 기존 마이그레이션은 전부 테스트 DB 에 적용돼 손대지 않는다. CHECK 확인: origin_type 에 'adjust_existing'·'adjust_new' ·
-- cost_source 에 'layer_avg'·'cin7_unitcost'·'unknown' · consume reason 에 'adjust_out' 이 이미 있다(20260908195949 · 20260909155320) — alter 없음.
--
-- ═══ 왜 이 둘을 같이 붙이나 ═══
--  같은 doc_type='adjustment' 축이고 규칙이 확정돼 있다. ⭐ short_events 81 의 대부분이 adjust_existing 미처리 때문이다 —
--  소분 제품군(AS91...)의 재고가 조정 증가로만 생긴다. ⇒ 붙이면 81 이 크게 줄어야 하고 그것이 이번 검증 지표다.
--
-- ═══ A. adjust_existing (157키) ═══
--  ⚠️⚠️ **event_type 으로 분기하지 않는다 — 키 순액의 부호로 가른다.** adjust_existing 은 seq_hint 1(41행 양수)·2(116행 음수) 양쪽에 있다.
--  [실측 2026-09-09] (doc_number, sku, warehouse) 키 순액: net_pos 41 · net_neg 116 · ⭐ net_zero 0 ⇒ 한 키에 증가·감소가 섞이지 않는다.
--  A-1 순액 양수 = 증가 (41키 · +1,290) — 도착이 아니라 **그 자리에서 재고가 생긴 것** ⇒ 새 레이어.
--      origin_type 'adjust_existing' · cost_source 'layer_avg' · ⭐ unit_cost = 그 SKU×창고 **남은 레이어 가중평균**
--      (sum(remaining × unit_cost) / sum(remaining) · inv_layer_open 뷰 대신 직접 계산 · 날짜순 루프 안이라 그 시점까지의 레이어만) ·
--      received_on = 그 행의 occurred_on · age_known true · doc_number = ST- 번호 · line_ref = 그 행의 line_ref.
--      ⚠️ 왜 가중평균인가 — Cin7 이 UnitCost 를 주지 않는다([실측] ExistingStockLines 157행 전부 raw.line.UnitCost 없음 · adjust_new
--      28행은 전부 있다). ⭐ 실무 근거: 증가의 실체는 소분 제품군이고 벌크가 **non-inventory 로 입고**되므로(Caleb 확인 2026-09-09)
--      원장·원가 어디에도 그 원가가 없다 ⇒ 조립처럼 「부품에서 가져오는」 경로가 성립하지 않는다. **같은 자리에 있던 물건의 평균이
--      유일한 근거이고 그것이 맞다.** 📌 [실측 AS91463] 기초 26 + ST-01240 +188 + ST-01298 +15 + ST-01305 +15.
--  A-2 ⬜ 남은 레이어가 0 일 때 — 표본 0건 · 방어만. [실측] 157건 전부 조정 직전 재고가 양수(prior_zero_or_neg 0). 남은 레이어 합이
--      0 이하면 cost_source 'unknown' · unit_cost 0 으로 만들고 ⭐ adjust_unknown_layers 로 센다 — 0 이 아니게 되는 것 자체가 신호다.
--      ⚠️ 규칙을 지금 정하지 않는다 — 후보는 「그 SKU 의 마지막 소비 단가」와 unknown 이고, 표본이 나오면 그때(⏸ 표본 대기).
--  A-3 순액 음수 = 감소 (116키 · −2,076) — FIFO 소진 · inv_layer_consume reason='adjust_out'. 부족하면 있는 만큼만 · short_events +1 ·
--      예외 없음 (⚠️ 트랜스퍼처럼 원가 미상 레이어를 만들지 않는다 — 재고가 나가는 사건이다).
--      ⚠️⚠️ **사유를 판단하지 않는다.** [실측] raw.line.Comments 가 116행 전부 빈 문자열 · raw.header 에 사유 필드 없음(doc_number ·
--      effective_date · header_location_id · status · task_id). Caleb 확인: 조정 사유는 정말 다양하다 — WMS 실사만이 아니다.
--      ⇒ ⭐ 레이어는 「조정으로 빠졌다」까지만 기록한다. 파손·실사 차이·재분류는 회계 판단이고 reason='adjust_out' 이 판매('sale')와
--      구분되므로 나중에 갈라 쓸 수 있다. 되짚을 근거는 doc_number(ST- 번호). ⚠️ 사유를 추측해 계정을 배정하면 고칠 수 없다(원가는 소급 불가).
--  📌 키 순액이 정확히 0 인 adjust_existing 키는 [실측] 0건이다 — 나오면 아무것도 하지 않는다(카운터는 표본이 생기면 붙인다).
--
-- ═══ B. adjust_new (28키) ═══
--  [실측 2026-09-09] net_pos 25 · net_zero 3 · ⭐ net_neg 0 ⇒ 생성만으로 된다.
--  · 순액 양수일 때만 레이어. 0 이하면 아무것도 하지 않는다(manual 3행이 3키를 완전 상쇄 · adjust_new_net_zero 로 센다).
--  · origin_type 'adjust_new' · cost_source 'cin7_unitcost' · ⭐ unit_cost = Cin7 이 준 값 raw.line.UnitCost
--    ([실측] 28행 전부 존재 · $0.24~$15.67 · 0원 없음). ⚠️ adjust_existing 에는 이 필드가 없다 — NewStockLines 와 ExistingStockLines 를
--    Cin7 이 다르게 준다(스킬 「NewStockLines 는 규칙이 다르다」의 실체).
--  · 키에 여러 원장 행(bin 갈림)이면 **수량 가중평균**(sum(qty × UnitCost) / sum(qty) · 양수 행 · UnitCost 있는 행만).
--  · UnitCost 가 없거나 읽을 수 없으면 cost_source 'unknown' · unit_cost 0 · adjust_unknown_layers +1 (A-2 와 같은 카운터).
--  · received_on = occurred_on · age_known true.
--  📌 **원가 0 은 그대로 0 으로 쌓는다** — 서플라이어 프로모션 무상 재고가 실재한다(Caleb 확인 · 기초 스냅샷 51칸). 예외 처리하지 않는다.
--    지금 adjust_new 에는 0원이 없지만 나오면 정상이다.
--  ⚠️ **UnitCost 가드 — 음수는 거부한다.** (읽었는데 음수인 경우만 — 「읽을 수 없다」는 위 unknown 경로 · 0 은 정상)
--    inv_layer_cost_ck(unit_cost >= 0) 에 걸려 어차피 실패하는데, 그때는 제약 위반 메시지만 나오고 **22,000 사건 중 어느 문서 때문인지
--    알 수 없다.** [실측 2026-09-09] adjust_new 28행 중 음수 0건 · 0원 0건 · $0.24~$15.67 ⇒ 지금은 안전하다. ⚠️ 그러나 사람이 Cin7 화면에서
--    입력하는 값이라 오타가 들어올 수 있다. ⚠️ 0 으로 깎지 않는다 — 음수 단가는 우리가 판단할 수 없는 값이고 사람이 원인을 보게 해야
--    한다(「모르면 비워둔다」). 📌 po_in 의 같은 가드(20260909155320 · 원가 가드)와 같은 취지다.
--
-- ═══ C. 공통 — 키 순액 ═══
--  소진량·생성량 = (doc_number, sku, warehouse, event_type) 순액 · source 무관 · p_until 안. ⚠️ line_ref 를 키에 넣지 않는다 · 접미어를
--  파싱하지 않는다. 📌 [실측] adjust_new 의 manual 3행은 :reversal 접미어가 없다(suffix_rows 0) — 키 순액이면 접미어 유무와 무관하다.
--  루프가 같은 키를 여러 번 만나므로 처리한 키는 건너뛴다(inv_layer_apply_done · kind 'adj_ex' / 'adj_new').
--  📌 event_type 을 키에 넣는 이유: 같은 ST 문서가 ExistingStockLines 와 NewStockLines 를 함께 가질 수 있어 (doc, sku, wh) 만으로는
--  두 규칙이 한 순액에 섞인다. 분기는 event_type 으로 하지 않지만 **키는 event_type 별**이다.
--
-- 반환 jsonb 추가: processed_adjust(원장 행 수) · adjust_layers_created · adjust_consume_rows · adjust_unknown_layers · adjust_new_net_zero.
--  skipped_by_type 에서 adjust_existing·adjust_new 가 빠진다. short_events 에는 A-3 부족이 더해진다.

-- ── 보조 4: adjust 한 행 → 키 순액 부호로 생성/소진 ──
--   o_layers = 만든 레이어 수 · o_rows = consume 행 수 · o_short = 감소 부족 · o_unknown = 원가 근거 없어 unknown 으로 만든 수 ·
--   o_new_net_zero = 순액 ≤ 0 인 adjust_new 키 수 · o_processed = 이 호출이 키를 처리했으면 1
create or replace function inv_layer_apply_adjust(p_ledger_id bigint, p_until date,
                                                  out o_layers int, out o_rows int, out o_short int,
                                                  out o_unknown int, out o_new_net_zero int, out o_processed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r        inv_ledger%rowtype;
  v_kind   text;
  v_net    numeric;
  v_unit   numeric;
  v_src    text;
  v_rem    numeric;      -- 남은 레이어 합
  v_remval numeric;      -- 남은 레이어 × 단가 합
  v_wq     numeric;      -- adjust_new: UnitCost 있는 양수 행의 qty 합
  v_wv     numeric;      -- adjust_new: qty × UnitCost 합
  v_rows int; v_short int; v_layers int; v_taken numeric;
begin
  o_layers := 0; o_rows := 0; o_short := 0; o_unknown := 0; o_new_net_zero := 0; o_processed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found then return; end if;
  v_kind := case r.event_type when 'adjust_existing' then 'adj_ex' when 'adjust_new' then 'adj_new' end;
  if v_kind is null then return; end if;

  -- 처리한 키는 건너뛴다 (doc, sku, wh · event_type 별)
  if exists (select 1 from inv_layer_apply_done d
              where d.kind = v_kind and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = r.warehouse) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values (v_kind, r.doc_number, r.sku, r.warehouse);
  o_processed := 1;

  -- 키 순액 (source 무관 · line_ref 키 제외 · p_until 안)
  select sum(qty_delta) into v_net
    from inv_ledger
    where event_type = r.event_type and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until);

  if r.event_type = 'adjust_existing' then
    if v_net > 0 then
      -- A-1 증가 — 남은 레이어 가중평균 (직접 계산)
      select coalesce(sum(rem), 0), coalesce(sum(rem * unit_cost), 0) into v_rem, v_remval
        from (select x.unit_cost,
                     x.qty - coalesce((select sum(c.qty) from inv_layer_consume c where c.layer_id = x.id), 0) as rem
                from inv_layer x where x.sku = r.sku and x.warehouse = r.warehouse) t
        where rem > 0;
      if v_rem > 0 then
        v_unit := round(v_remval / v_rem, 6); v_src := 'layer_avg';
      else
        v_unit := 0; v_src := 'unknown'; o_unknown := o_unknown + 1;   -- A-2 방어 · 표본 대기
      end if;
      insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                             received_on, age_known, qty, unit_cost, cost_source)
      values (r.sku, r.warehouse, 'adjust_existing', r.doc_number, r.line_ref, null,
              r.occurred_on, true, v_net, v_unit, v_src);
      o_layers := o_layers + 1;
    elsif v_net < 0 then
      -- A-3 감소 — FIFO 소진 · reason 'adjust_out' · 부족은 short (원가 미상 레이어 없음)
      select * into v_rows, v_short, v_layers, v_taken
        from inv_layer_fifo_take(r.sku, r.warehouse, -v_net,
                                 r.doc_type, r.doc_number, r.line_ref, r.event_type, r.occurred_on, 'adjust_out', null);
      o_rows := o_rows + v_rows; o_short := o_short + v_short;
    end if;
    -- v_net = 0: 아무것도 하지 않는다 (실측 0건 — 헤더)
    return;
  end if;

  -- B. adjust_new
  if v_net is null or v_net <= 0 then
    o_new_net_zero := o_new_net_zero + 1;   -- 상쇄로 소멸
    return;
  end if;
  select coalesce(sum(qty_delta), 0),
         coalesce(sum(qty_delta * (raw -> 'line' ->> 'UnitCost')::numeric), 0)
    into v_wq, v_wv
    from inv_ledger
    where event_type = 'adjust_new' and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until)
      and qty_delta > 0
      and (raw -> 'line' ->> 'UnitCost') ~ '^-?[0-9]+(\.[0-9]+)?$';   -- 읽을 수 있는 값만
  if v_wq > 0 then
    v_unit := round(v_wv / v_wq, 6); v_src := 'cin7_unitcost';       -- 0 이면 0 으로 쌓는다 (프로모션 무상 재고 · 정상)
    -- UnitCost 가드 (헤더) — 읽었는데 음수면 거부. 0 은 통과 · 읽을 수 없으면 아래 unknown 경로.
    if v_unit < 0 then
      raise exception 'adjust_new UnitCost (qty-weighted) is negative for % / % / %: % — refusing to build layer (typo in Cin7? inspect raw.line.UnitCost)',
        r.doc_number, r.sku, r.warehouse, v_unit;
    end if;
  else
    v_unit := 0; v_src := 'unknown'; o_unknown := o_unknown + 1;
  end if;
  insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                         received_on, age_known, qty, unit_cost, cost_source)
  values (r.sku, r.warehouse, 'adjust_new', r.doc_number, r.line_ref, null,
          r.occurred_on, true, v_net, v_unit, v_src);
  o_layers := o_layers + 1;
end;
$$;

-- ── main: adjust 분기 추가 · 카운터 다섯 추가 (그 외는 20260909190145 그대로) ──
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
  v_adj         int := 0;
  v_adj_layers  int := 0;
  v_adj_rows    int := 0;
  v_adj_unk     int := 0;
  v_adj_new_nz  int := 0;
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
      where event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal', 'adjust_existing', 'adjust_new')
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
    elsif r.event_type in ('adjust_existing', 'adjust_new') then
      select * into v_layers, v_rows, v_short, v_unk, v_nz, v_proc from inv_layer_apply_adjust(r.id, p_until);
      v_adj := v_adj + 1; v_adj_layers := v_adj_layers + v_layers; v_adj_rows := v_adj_rows + v_rows;
      v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_adj_unk := v_adj_unk + v_unk; v_adj_new_nz := v_adj_new_nz + v_nz;
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
            where event_type not in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal', 'adjust_existing', 'adjust_new')
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
    'skipped_by_type',           v_skipped,
    'layers_created',            v_layers_po,
    'consume_rows',              v_consume,
    'cost_unknown_layers',       v_unknown,
    'short_events',              v_shorts,
    'elapsed_ms',                round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$$;

revoke all on function inv_layer_apply_adjust(bigint, date) from public, anon, authenticated;
revoke all on function inv_layer_apply(date) from public, anon;
grant execute on function inv_layer_apply(date) to authenticated;
