-- 원가 레이어 — PO landed 코스트를 inv_layer_cost_add 에 얹는다 (2026-09-10)
--
-- 20260909235347 의 inv_layer_apply(main) 를 create or replace 로 덮어쓴다 — 루프 뒤에 landed 삽입 블록 하나를 더한 것 외에 본문 무변.
-- 기존 마이그레이션은 전부 테스트 DB 에 적용돼 손대지 않는다. 보조 함수는 바꾸지 않는다.
--
-- ═══ 배경 — inv_layer_cost_add 는 아직 행 0건이다 ═══
--  표는 20260908195949 에서 만들었지만 채우는 코드가 없어 한 번도 안 돌았다. ⭐ PO landed 는 이미 inv_cost 에 있으므로 만들면 바로 검증된다.
--  [실측 2026-09-10 테스트 DB · 재복사 후]
--    inv_cost  goods 730행 · 21 PO · $476,203.27 · 08-21~09-09 / landed 434행 · 11 PO · 405 SKU · $2,215.65 · 08-22~08-31
--    landed 키 (doc_number, line_ref, sku, warehouse) 408개 — has_layer 408(전부 purchase 레이어와 조인) · no_layer 0 · multi_bin 0 ·
--    ⚠️ multi_date 26(같은 라인에 landed 가 여러 날짜) · amt_neg 0.
--  ⭐ 434행 − 408키 = 26 = multi_date ⇒ 26키가 각각 2행. 통관·freight·관세가 **각각 다른 인보이스 날짜**로 오는 것이고
--  inv_layer_cost_add 유니크 키에 occurred_on 이 있으므로 **별개 행으로 공존**해야 한다 ⇒ cost_add 에는 **434행**이 들어가야 한다.
--
-- ═══ 왜 apply 안에서 하나 ═══
--  ⚠️ inv_layer_apply 가 매번 inv_layer_cost_add 를 전량 delete 한다 — 밖에서(별도 RPC) 채우면 다음 apply 에 사라진다.
--  ⇒ ⭐ apply 의 날짜순 루프가 끝난 뒤(레이어가 전부 만들어진 뒤 · layer_id 를 찾아야 하므로) **집합 연산 한 번**으로 삽입한다.
--
-- ═══ 삽입 규칙 ═══
--  · inv_cost.cost_kind='landed' 를 origin_type='purchase' 레이어와 4키(doc_number, line_ref, sku, warehouse)로 조인.
--  · (layer_id, occurred_on, doc_number, line_ref) 로 group by · sum(amount) — ⭐ bin 이 여럿이면 합산(실측 0건 · 방어) ·
--    ⚠️ 날짜별로 별개 행(통관·freight·관세 · 실측 26키가 2행) — 유니크 키에 occurred_on 이 있는 것이 그 때문이다.
--  · kind='landed' · p_until 반영(as-of 조회가 깨지지 않게).
--  · ref_number = **null**. ⚠️ **PO landed 는 ref_number 를 얻을 수 없다** — Cin7 이 InventoryMovements 로 주므로 인보이스 번호가 오지 않는다.
--    [확인] inv-cost 가 남기는 raw 는 {axis, im, alloc, invoice} 이고 landed 행은 invoice=null · alloc.mj_user_lines 는 12문서 전부 빈 배열.
--    📌 트랜스퍼 운송비는 ManualJournals.Reference 로 온다(별건 · 아래).
--
-- ═══ 가드 ═══
--  · 키(4키 + occurred_on) 합 sum(amount) < 0 이면 예외(키와 금액을 메시지에). [실측] amt_neg 0 이지만 po_in·adjust_new 와 같은 취지 —
--    제약 위반 메시지만으로는 어느 문서인지 알 수 없다.
--  · ⚠️ inv_layer_cost_add 에는 amount >= 0 CHECK 가 **없다**(확인 · 20260908195949: kind CHECK 와 5키 유니크만) ⇒ 이 가드가 유일한 방어다.
--
-- ═══ 반환에 추가 ═══
--  landed_rows(삽입한 cost_add 행 수 · ⭐ 434 가 나와야 한다) · landed_amount(합계 · ⭐ $2,215.65) ·
--  landed_orphan(대응 purchase 레이어를 못 찾은 landed 키 수 · 실측 0 · 0 이 아니면 신호).
--  ⚠️ orphan 은 따로 센다 — 조인이 안 되면 insert…select 에서 조용히 빠진다.
--
-- ═══ 레이어 원가에 미치는 영향 ═══
--  inv_layer_open.total_cost · remaining_cost 가 cost_add 합을 포함한다(뷰가 이미 그렇다 · 20260908195949) ⇒ ⭐ 재고 평가액이 landed 만큼 오른다.
--  ⚠️ unit_cost 는 안 바뀐다 — inv_layer.unit_cost 는 goods 만이고 landed 는 cost_add 로 별도다. ⭐ 그것이 설계다(어느 조각이 언제 붙었는지 남긴다).
--  ⚠️ 소비 기록의 unit_cost 도 안 바뀐다 — 「소비 시점 값을 굳힌다」. 📌 그래서 「뒤늦게 붙은 원가 차액」이 계산 가능해진다 —
--  이미 팔린 몫에 cost_add 가 붙으면 그 차액이 나온다(§13 미결).
--  ⚠️ 아직 안 되는 것: **트랜스퍼 운송비**(kind='transfer_freight')는 inv-cost 가 수집하지 않아 대상이 0건이다(별건 · §13).

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
begin
  select count(*) into v_baseline from inv_layer where origin_type = 'baseline';
  if v_baseline = 0 then
    raise exception 'inv_layer has no baseline layers — run inv_layer_seed_baseline first';
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
