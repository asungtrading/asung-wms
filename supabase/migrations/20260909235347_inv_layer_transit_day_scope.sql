-- 원가 레이어 사건 적재 — 트랜스퍼 순액 계산 범위를 중복 방지 키(날짜)와 맞춘다 (2026-09-09 밤)
--
-- 20260909233729 의 inv_layer_apply_transfer_in 을 create or replace 로 덮어쓴다(시그니처 동일 · 순액·대응 out 탐색에 날짜 조건).
-- 20260909231134 의 inv_layer_apply(main) 을 create or replace 로 덮어쓴다 — transfer_out_unpaired 집계 한 곳만 날짜 단위로(그 외 동일).
-- inv_layer_fifo_take(p_doc_scope) 는 그대로다. 기존 마이그레이션은 전부 테스트 DB 에 적용돼 손대지 않는다.
--
-- ═══ ⚠️⚠️ 결함 — 순액은 문서 전체로 계산하는데 중복 방지는 날짜별이다 ═══
--  inv_layer_apply_transfer_in 은 tr_in 중복 방지 키에 day 를 넣어 **날짜별**로 처리하면서(20260909174046 C-2 「같은 날 두 bin 으로
--  도착해도 한 번」), v_in_net · v_out_net 순액은 **문서 전체**(doc, sku, wh)로 계산했다. ⇒ 같은 문서의 두 날짜가 **각각** 「문서 전체
--  순액」을 소진한다. 재고가 충분하면 **이중 소진**, 부족하면 **거짓 short** 다.
--
--  실증 [로컬 진단 픽스처 2026-09-09 · 20260909233729 검증 중 발견]
--    TOR 기초 40 · TR-M 이 08-21 −10 · 08-23 −10 (쌍1 이 이틀로 갈림)
--                      원장   레이어
--     TOR 에서 소진      20     40 (consume 2행 · 각 20)
--     IN_TRANSIT 잔량    20     40
--     short_events        —      0   ⚠️ 조용히 틀린다
--
--  ⚠️⚠️ **이 결함은 어느 카운터에도 안 잡힌다** — short_events 0 인 채로 조용히 틀린다. transfer_orphan_in · transfer_out_unpaired ·
--  transfer_keys_net_zero 어디에도 나타나지 않는다(각 날짜가 「정상 처리」로 보인다). ⭐ 그래서 문서에 적어두는 것으로 넘기지 않고
--  고쳤다 — 발견 자체가 안 되는 결함은 기록으로 해결되지 않는다.
--
--  📌 [실측 2026-09-09 테스트 DB] 실데이터에는 지금 **0건**이다:
--    transfer_in @ IN_TRANSIT 이 여러 날에 걸친 (doc, sku)   0
--    transfer_out/manual_reversal 이 여러 날에 걸친 키        0
--  ⇒ ⭐ **이 수정으로 테스트 DB 의 숫자가 하나도 바뀌지 않아야 한다 — 그것이 검증이다.** 바뀌면 이 헤더의 전제가 틀린 것이다.
--
-- ═══ 고친 것 — (a) 순액을 날짜까지 좁힌다 ═══
--  · ⓪′ v_in_net  : (doc, sku, wh) → (doc, sku, wh, **occurred_on = r.occurred_on**)
--  · ①  대응 out 창고 탐색 : 같은 날짜의 out leg 만 (종전엔 「같은 날짜 우선」 정렬이었다 — 이제 조건)
--  · ②  v_out_net · 대표 out 행 : 같은 날짜만
--  · ④  tr_out 처리 기록에 day 를 넣는다 · main 의 transfer_out_unpaired 집계도 (doc, sku, wh, **day**) 로 — 첫날 짝이 처리되면
--       둘째 날의 짝 없는 out 이 감지망에서 빠지는 구멍을 막는다(그 키가 이미 마크돼 있어 안 세어졌다).
--  · 부족분 판정의 「쌍1 이 원장에 없음」(20260909190145) 은 **문서 단위 그대로** — 묻는 것은 「출발이 기초 이전인가」이고 날짜와 무관하다.
--  · ⚠️ p_doc_scope(20260909233729)와 충돌하지 않는다 — 문서 범위 제한은 그대로 두고 날짜 조건만 더했다. IN_TRANSIT 출발 leg 3 은
--    「그 문서의 IN_TRANSIT 레이어(날짜 무관 · FIFO)」에서 「그 날짜의 out 순액」만큼 뺀다 — 둘은 다른 축이다(레이어 범위 vs 소진량).
--
--  ⭐ 왜 (a) 인가 — [실측 2026-09-09] **leg 쌍은 항상 같은 날 안에서 완결된다**(문서×날짜 346개 중 pair1_broken 0 · pair2_broken 0 ·
--  orphan 0). 날짜로 좁혀도 짝이 깨지지 않고, 여러 날에 걸친 문서가 나타나면 **각 날짜가 독립적으로 정확히 처리된다** — 그것이 실제
--  사건의 모양이다(둘째 날 출발분은 둘째 날에 떠났다).
--  ❌ (b) 중복 방지 키에서 날짜를 빼는 안 — 먼저 온 날짜만 처리하고 나중 것을 건너뛴다. 순액이 문서 전체라 수량은 맞지만 나중 날짜의
--  사건이 먼저 날짜로 뭉개져 **나이(received_on)가 틀어진다.** 에드먼튼은 트랜스퍼가 유일한 유입 경로라 나이가 곧 aging 이다.
--  ⚠️ (a) 의 대가: 짝이 날짜를 넘어 갈리는 문서(out 은 D일 · in 은 D+1일)가 나오면 in 은 orphan 경로(unknown 레이어 · transfer_orphan_in),
--  out 은 transfer_out_unpaired 로 **둘 다 신호가 뜬다.** 조용히 틀리지 않는다 — 그것이 지금 결함과의 차이다.
--
-- 반환 jsonb: 변경 없음. 조회 예시(테스트 DB 적용 후 · 숫자가 20260909233729 적용 직후와 같아야 한다):
--   select inv_layer_apply();

-- ── 보조 3: transfer_in — 순액·대응 out 을 그 행의 날짜로 좁힌다 (그 외 20260909233729 그대로) ──
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

  -- ⓪′ in leg 순액 — ⭐ 그 날짜만 (중복 방지 키와 같은 범위) · 0 이하면 상쇄로 소멸한 키
  select sum(qty_delta) into v_in_net
    from inv_ledger
    where doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse and event_type = 'transfer_in'
      and occurred_on = r.occurred_on
      and (p_until is null or occurred_on <= p_until);
  if v_in_net is null or v_in_net <= 0 then
    o_net_zero := o_net_zero + 1;
    return;
  end if;

  -- ① 대응 out leg 의 창고 — ⭐ 같은 날짜의 out 만 (leg 쌍은 같은 날 안에서 완결 · 헤더)
  if r.warehouse = 'IN_TRANSIT' then
    select warehouse into v_out_wh
      from inv_ledger
      where doc_number = r.doc_number and sku = r.sku and warehouse <> 'IN_TRANSIT'
        and event_type in ('transfer_out', 'manual_reversal')
        and occurred_on = r.occurred_on
        and (p_until is null or occurred_on <= p_until)
      order by id
      limit 1;
  else
    v_out_wh := 'IN_TRANSIT';
  end if;

  -- ② out leg 의 키 순액 × −1 — ⭐ 같은 날짜만
  if v_out_wh is not null then
    select -sum(qty_delta) into v_out_net
      from inv_ledger
      where doc_number = r.doc_number and sku = r.sku and warehouse = v_out_wh
        and event_type in ('transfer_out', 'manual_reversal')
        and occurred_on = r.occurred_on
        and (p_until is null or occurred_on <= p_until);
    select doc_type, line_ref, event_type, occurred_on into v_out
      from inv_ledger
      where doc_number = r.doc_number and sku = r.sku and warehouse = v_out_wh and event_type = 'transfer_out'
        and occurred_on = r.occurred_on
        and (p_until is null or occurred_on <= p_until)
      order by id
      limit 1;
  end if;

  if v_out_wh is null or v_out_net is null or v_out_net <= 0 or v_out is null then
    -- C-3 그 날짜에 대응 out **행 자체** 없음(방어 경로) — unknown 도착 레이어 · transfer_orphan_in
    insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                           received_on, age_known, qty, unit_cost, cost_source)
    values (r.sku, r.warehouse, 'transfer', r.doc_number, r.line_ref, null,
            r.occurred_on, false, v_in_net, 0, 'unknown');
    o_layers := o_layers + 1;
    o_orphan := o_orphan + 1;
    return;
  end if;

  -- ④ out 키 기록 — ⭐ 날짜 포함 (main 의 unpaired 집계와 같은 키)
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse, day) values ('tr_out', r.doc_number, r.sku, v_out_wh, r.occurred_on)
    on conflict do nothing;

  -- ②③ 출발 FIFO 소진 + 소진한 레이어마다 도착 레이어 (parent_layer 복사)
  --    출발이 IN_TRANSIT 이면 같은 문서의 레이어만 (p_doc_scope = r.doc_number · 20260909233729) · 실제 창고 출발은 전체 FIFO (null)
  select * into v_rows, v_short, v_layers, v_taken
    from inv_layer_fifo_take(r.sku, v_out_wh, v_out_net,
                             v_out.doc_type, r.doc_number, v_out.line_ref, v_out.event_type, v_out.occurred_on,
                             'transfer', r.warehouse,
                             case when v_out_wh = 'IN_TRANSIT' then r.doc_number else null end);
  o_rows := o_rows + v_rows; o_layers := o_layers + v_layers;

  -- 부족분 — 기초 이전 출발(IN_TRANSIT 출발 · 쌍1 이 원장에 없음 · ⚠️ 문서 단위 판정)만 도착 창고에 원가 미상 레이어 (20260909190145).
  --    그 외 부족(창고 출발 · 쌍1 이 있는 IN_TRANSIT 부족 = 전파된 것)은 종전대로 short.
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

-- ── main: transfer_out_unpaired 를 (doc, sku, wh, day) 로 — 그 외 20260909231134 그대로 ──
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
