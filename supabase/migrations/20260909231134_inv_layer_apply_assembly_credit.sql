-- 원가 레이어 사건 적재 — assemble(조립) + credit_in(반품) · 마지막 두 사건 (2026-09-09 밤)
--
-- 20260909201223 의 inv_layer_apply(main) 를 create or replace 로 덮어쓴다(루프에 분기 추가). 보조 inv_layer_apply_assemble ·
-- inv_layer_apply_credit 은 신규. 기존 마이그레이션은 전부 테스트 DB 에 적용돼 손대지 않는다.
-- CHECK 확인(20260908195949 · 20260909155320 을 읽어 확인): origin_type 에 'assembly'·'creditnote' 있음 · cost_source 에
-- 'assembly_sum'·'layer_avg'·'unknown' 있음 · consume reason 에 'assembly_in' 있음 ⇒ 그대로 쓴다.
-- ⚠️ cost_source 'return_restore' 는 **없다** ⇒ 아래 alter 로 추가한다(사유는 B-①).
--
-- ⭐⭐ 이 둘이 붙으면 **사건 9종이 전부 처리된다**(po_in · sale_out · transfer_in/out · manual_reversal · adjust_existing ·
--  adjust_new · assemble_in/out · credit_in). ⇒ **잔량 대조가 처음으로 의미를 갖는다** — 20260909155320 헤더의 정정
--  (「부분 처리 상태에서는 잔량 대조가 성립하지 않는다」 · ledger-design §9)의 전제가 풀린다. skipped_by_type 은 {} 여야 한다.
--
-- ═══ A. assemble — 부품 소진 → 완제품 생성 ═══
--  A-1 구조 [실측 2026-09-09 재복사 후]
--     doc_number | occurred_on | seq | event_type   | source | rows | skus | qty
--    ------------+-------------+-----+--------------+--------+------+------+-----
--     FG-00130   | 2026-08-24  |  1  | assemble_in  | cin7   |    1 |    1 |   1
--     FG-00130   | 2026-08-24  |  2  | assemble_out | cin7   |    4 |    4 | -24
--     FG-00131   | 2026-08-28  |  1  | assemble_in  | cin7   |    1 |    1 |   1
--     FG-00131   | 2026-08-28  |  1  | assemble_in  | manual |    1 |    1 |  -1   ← 상쇄
--     FG-00131   | 2026-08-28  |  2  | assemble_out | cin7   |    4 |    4 | -24
--     FG-00131   | 2026-08-28  |  2  | assemble_out | manual |    4 |    4 |  24   ← 상쇄
--     FG-00132   | 2026-08-28  |  1  | assemble_in  | cin7   |    1 |    1 |   1
--     FG-00132   | 2026-08-28  |  2  | assemble_out | cin7   |    4 |    4 | -24
--     FG-00133   | 2026-09-01  |  (in +1 / manual −1 · out −2 / manual +2)        ← 전량 상쇄
--     FG-00134   | 2026-09-01  |  (같음)                                          ← 전량 상쇄
--    ⭐ 확정된 사실: 같은 문서·같은 날에 in·out 이 다 있다 ⇒ doc_number 로 짝을 찾는다 · 완제품 1 SKU : 부품 N SKU(실측 N=4 또는 2) ·
--    ⚠️ seq_hint 1=in · 2=out ⇒ 날짜순 루프에서 **in 이 먼저 온다** · ⭐ 5문서 중 3개가 완전 상쇄(FG-00131·00133·00134) ⇒ 키 순액이면
--    자동으로 걸러진다 — **처리할 것은 FG-00130·FG-00132 둘뿐** · ⚠️ 수량비가 문서마다 다르다(1:24 · 1:2) — 원가는 부품 레이어 합 ÷
--    완제품 수량이므로 비율은 상관없다.
--  A-2 ⚠️ 순서 처방 — **트랜스퍼와 같은 구조다**(20260909174046 C-2). in 이 먼저 오는데 완제품 원가를 알려면 부품을 먼저 소진해야
--    한다. ⇒ ⭐ **assemble_in 을 만났을 때 그 자리에서 같은 doc_number 의 assemble_out 을 먼저 처리한다.**
--      ① 같은 doc_number 의 assemble_out 을 (sku, warehouse) 키로 전부 찾는다 (p_until 안)
--         📌 실측은 전부 같은 날이지만 짝 찾기에 occurred_on 을 넣지 않는다 — 날짜가 갈린 문서가 나와도 짝이 맞고, 못 찾은 out 키는
--         루프 뒤 assembly_out_unpaired 가 센다(트랜스퍼의 transfer_out_unpaired 와 같은 안전망 · 0 이 아니면 신호).
--      ② 각 부품 키의 순액(= −sum(qty_delta))만큼 그 창고 레이어를 FIFO 소진 · reason='assembly_in' · 소진 금액을 전부 합산(v_parts_cost)
--         — 합산은 이 문서의 inv_layer_consume(reason='assembly_in') sum(amount) 로 읽는다(전량 재생성이라 낡은 행이 없다).
--      ③ 완제품 레이어: qty = assemble_in 키 순액 · unit_cost = v_parts_cost / qty · cost_source 'assembly_sum' · origin_type 'assembly' ·
--         received_on = 그 행의 occurred_on · age_known true · parent_layer_id null(부품이 여럿이라 하나를 가리킬 수 없다) ·
--         doc_number = FG 번호 · line_ref = 그 행의 line_ref.
--      ④ 처리 기록(inv_layer_apply_done kind 'asm_in' / 'asm_out') — 뒤에 그 out 행을 만나면 건너뛴다.
--    ⚠️ 한 문서에 완제품 키(순액 > 0)가 둘 이상이면 예외를 던진다 — 부품 원가를 어느 완제품에 얼마씩 배분할지 근거가 없고, 조용히
--    합치면 원가가 이중 계상된다. [실측] 5문서 전부 완제품 1 SKU. 나오면 사람이 본다(po_in 원가 가드와 같은 취지).
--  A-3 ⚠️ 부품 레이어가 부족할 때 — 있는 만큼만 소진하고 **그 금액으로만** 완제품 원가를 계산한다 ⇒ 완제품 qty 는 원장대로 만들되
--    unit_cost 가 낮아진다. ⚠️ **원가 미상 레이어를 만들지 않는다 — 트랜스퍼(20260909190145)와 판단이 다른 이유**: 트랜스퍼는
--    부족분만큼 **도착 재고 자체가 레이어에 없어지는** 문제라 수량을 맞추기 위해 원가 미상 레이어가 필요했다. 조립은 완제품이
--    **어차피 새 레이어**이고 수량이 원장과 맞는다 — 부족한 것은 「원가의 일부」이지 「재고」가 아니다. 원가 미상 레이어를 따로
--    만들면 없는 재고를 만드는 셈이다. ⇒ short_events +1(부품 키마다) · 새 카운터 **assembly_partial_cost**(원가가 과소평가된
--    완제품 레이어 수 · 0 이 아니면 신호). 📌 부품 out 키가 하나도 없는 문서(방어 경로 · 실측 0건)도 완제품 레이어를 만들고
--    (unit_cost 0 · assembly_sum) partial 로 센다 — 잔량 안전망은 유지되고 카운터가 알린다.
--  A-4 ⚠️ 완제품 키 순액이 0 이하면 — 전량 상쇄된 문서(FG-00131·00133·00134). **아무것도 하지 않는다.** ⭐ assembly_net_zero 로 센다
--    (정보 카운터 · 평상시 값이 있어도 무해 · sale_keys_fully_reversed 와 같은 성격). ⚠️ 부품도 소진하지 않는다 — 상쇄됐으므로
--    부품 순액도 0 이다([실측] 세 문서 모두 out 도 짝으로 상쇄). 부품 순액이 0 이 아닌데 완제품이 0 인 이상 상태는
--    assembly_out_unpaired 가 잡는다.
--
-- ═══ B. credit_in — 반품 ═══
--  B-1 ⭐ 두 갈래 [실측 2026-09-09 재복사 후]
--      20키 · 167개 · ⭐ 되짚기 가능 9 · 불가 11 · ⭐ SO 번호 없는 것 0
--    ⭐ **모든 반품이 원 판매를 가리킨다** — raw.header.order_number. ⚠️ 다만 11건은 그 판매가 8/20 기초 이전이라 원장에 없다.
--  갈래 ① 원 판매가 원장에 있다 (9키) — raw->'header'->>'order_number' 를 sale_out 의 doc_number 로 조인. ⭐ 그 판매가 소진한 레이어를
--    inv_layer_consume(doc_type 'sale' · reason 'sale')에서 찾아 **같은 단가로 되돌린다.**
--    · 구현 = (a) 원 소비 기록의 unit_cost 로 **새 레이어**를 만든다 · cost_source **'return_restore'**(⚠️ CHECK 에 없어 이 파일이 추가) ·
--      parent_layer_id = 원 레이어(되짚은 근거 · 트랜스퍼의 parent 와 같은 용법). 소진한 레이어가 여럿이면 레이어마다 하나(단가가 다르다).
--    · (b) inv_layer_consume 에 음수 행을 넣어 원 레이어를 되살리는 안은 **inv_layer_consume_qty_ck(qty > 0) 에 걸린다**(20260908195949
--      에서 확인) ⇒ (a) 로 간다. 📌 (a) 가 맞기도 하다 — 반품은 「소비 취소」가 아니라 물건이 돌아온 **새 사건**이고 날짜도 다르다.
--    · 되돌리는 순서 = 소비된 순서(원 레이어 received_on · id 순). 어느 개체가 돌아왔는지는 알 수 없으므로 관례로 정한다.
--    · ⚠️ 같은 판매에 크레딧노트가 둘 이상이면 앞선 반품이 이미 되돌린 몫을 뺀다(레이어별 소비량 − 그 SO 를 가리키는 creditnote
--      레이어 중 parent 가 같은 것의 합). 없으면 반품 합이 원 판매를 넘어도 전부 되짚어 버린다.
--    · 매칭 키는 **sku** 다(창고 아님) — 반품 창고가 판매 창고와 달라도 물건은 그 판매의 것이다. 레이어는 반품 행의 warehouse 에 만든다.
--      [실측] 창고가 갈린 반품이 있는지는 미확인(표본 20키 · ⬜). 갈려도 결과는 「단가는 원 판매 · 자리는 반품 창고」로 맞다.
--    · ⚠️ 반품 수량이 원 판매보다 많으면 **있는 만큼만** 되짚고 나머지는 갈래 ②로.
--  갈래 ② 원 판매가 원장에 없다 (11키) — 그 SKU×창고의 **남은 레이어 가중평균**(adjust_existing A-1 과 같은 규칙 · 20260909201223) ·
--    cost_source 'layer_avg'. ⚠️ 남은 레이어가 0 이면 'unknown' · unit_cost 0 · 카운터 credit_unknown_layers.
--    📌 순서는 ① 뒤 ② 다 — 반품 > 원 판매인 키에서 ② 의 평균은 **① 이 방금 만든 되짚기 레이어를 포함**한다(그 시점에 실재하는
--    재고이므로 「남은 레이어 전부」 규칙 그대로 · [로컬 검증] 28@5 + 10@8 + 되짚기 2@5 → 5.75).
--  B-2 공통 — origin_type 'creditnote' · received_on = 그 행의 occurred_on · age_known true. ⚠️ **원 판매 시점이 아니다** — 물건이 돌아온
--    날이 맞다(FIFO 순서상 「다시 들어온 재고」 · ⬜ 이견이 있으면 보고). 키 순액(doc_number, sku, warehouse)이 0 이하면 아무것도 하지
--    않는다(credit_net_zero). 📌 restock 라인만 원장에 온다 — 파손·미수령 크레딧노트는 재고를 안 움직이므로 다룰 것이 없다
--    ([실측] rule='restock line' · RestockDate 존재).
--
-- ═══ C. 공통 — 키 순액 ═══
--  소진량·생성량은 (doc_number, sku, warehouse) 순액 · source 무관 · p_until 안. ⚠️ line_ref 를 키에 넣지 않는다 · 접미어를 파싱하지
--  않는다. 루프가 같은 키를 여러 번 만나므로 처리한 키는 건너뛴다(inv_layer_apply_done · kind 'asm_in' / 'asm_out' / 'credit').
--  ⚠️ 조립은 키를 event_type 으로 가른다(asm_in 은 assemble_in 만 · asm_out 은 assemble_out 만) — 완제품 SKU 와 부품 SKU 가 같을 리는
--  없지만 안전하게(adjust 에서 event_type 별 키를 둔 것과 같은 이유).
--
-- 반환 jsonb 추가: processed_assembly(assemble_in+out 행 수) · assembly_layers_created · assembly_consume_rows · assembly_partial_cost ·
--  assembly_net_zero · assembly_out_unpaired(📌 지시 밖 추가 — 순액 > 0 인데 대응 in 이 처리하지 않은 out 키 · 0 이어야 한다) ·
--  processed_credit · credit_layers_created · credit_traced(갈래 ① 을 탄 키) · credit_avg(갈래 ② 를 탄 키 · ⚠️ 반품 > 원 판매인 키는
--  둘 다에 든다) · credit_unknown_layers · credit_net_zero. ⭐ skipped_by_type 은 {} 여야 한다.
--
-- 조회 예시:
--   select inv_layer_apply();
--   select origin_type, cost_source, count(*), sum(qty) from inv_layer where origin_type in ('assembly','creditnote') group by 1,2;
--   select c.doc_number, l.sku, c.qty, c.unit_cost, c.amount from inv_layer_consume c join inv_layer l on l.id=c.layer_id
--   where c.reason='assembly_in' order by c.doc_number, l.sku;

-- ── CHECK 확장 — cost_source 'return_restore' 추가 (이유는 B-①) ──
alter table inv_layer drop constraint inv_layer_source_ck;
alter table inv_layer add constraint inv_layer_source_ck check (cost_source in (
  'inv_cost','snapshot_value','cin7_unitcost',
  'layer_avg','assembly_sum','parent_layer','unknown','return_restore'));

-- ── 보조 5: assemble_in 한 행 → 같은 문서의 부품(assemble_out)을 먼저 소진하고 완제품 레이어 생성 (A) ──
--   o_layers = 완제품 레이어 수 · o_rows = 부품 consume 행 수 · o_short = 부품 부족 키 수 · o_partial = 원가 과소평가 완제품 레이어 수 ·
--   o_net_zero = 완제품 키 순액 ≤ 0 (상쇄 소멸) · o_processed = 이 호출이 in 키를 처리했으면 1
create or replace function inv_layer_apply_assemble(p_ledger_id bigint, p_until date,
                                                    out o_layers int, out o_rows int, out o_short int,
                                                    out o_partial int, out o_net_zero int, out o_processed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r            inv_ledger%rowtype;
  v_in_net     numeric;
  v_fg_keys    int;
  v_part_keys  int := 0;
  v_partial    boolean := false;
  v_cost       numeric;
  p            record;
  v_rows int; v_short int; v_layers int; v_taken numeric;
begin
  o_layers := 0; o_rows := 0; o_short := 0; o_partial := 0; o_net_zero := 0; o_processed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found or r.event_type <> 'assemble_in' then return; end if;

  -- 처리한 in 키는 건너뛴다 (doc, sku, wh · assemble_in 만)
  if exists (select 1 from inv_layer_apply_done d
              where d.kind = 'asm_in' and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = r.warehouse) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('asm_in', r.doc_number, r.sku, r.warehouse);
  o_processed := 1;

  -- 완제품 키 순액 (source 무관 · line_ref 키 제외 · p_until 안)
  select sum(qty_delta) into v_in_net
    from inv_ledger
    where event_type = 'assemble_in' and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until);
  if v_in_net is null or v_in_net <= 0 then
    o_net_zero := 1;            -- A-4 전량 상쇄 · 부품도 건드리지 않는다
    return;
  end if;

  -- A-2 가드 — 한 문서에 완제품 키가 둘 이상이면 배분 근거가 없다
  select count(*) into v_fg_keys
    from (select sku, warehouse from inv_ledger
            where event_type = 'assemble_in' and doc_number = r.doc_number
              and (p_until is null or occurred_on <= p_until)
            group by sku, warehouse having sum(qty_delta) > 0) k;
  if v_fg_keys > 1 then
    raise exception 'assembly % has % finished-goods keys with positive net (expected 1) — cannot allocate parts cost, refusing to build layer',
      r.doc_number, v_fg_keys;
  end if;

  -- ①② 같은 문서의 부품 키 — 순액만큼 FIFO 소진 · reason 'assembly_in' · out 키 기록(뒤에 만나면 건너뛴다)
  for p in
    select sku, warehouse, -sum(qty_delta) as need, min(occurred_on) as occurred_on,
           (array_agg(line_ref order by (source = 'cin7') desc, id))[1] as line_ref
      from inv_ledger
      where event_type = 'assemble_out' and doc_number = r.doc_number
        and (p_until is null or occurred_on <= p_until)
      group by sku, warehouse
  loop
    insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('asm_out', r.doc_number, p.sku, p.warehouse)
      on conflict do nothing;
    if p.need <= 0 then continue; end if;      -- 상쇄로 소멸한 부품 키
    v_part_keys := v_part_keys + 1;
    select * into v_rows, v_short, v_layers, v_taken
      from inv_layer_fifo_take(p.sku, p.warehouse, p.need,
                               r.doc_type, r.doc_number, p.line_ref, 'assemble_out', p.occurred_on, 'assembly_in', null);
    o_rows := o_rows + v_rows; o_short := o_short + v_short;
    if v_short > 0 then v_partial := true; end if;   -- A-3 있는 만큼만 · 원가 미상 레이어 없음
  end loop;
  if v_part_keys = 0 then v_partial := true; end if;  -- 부품이 하나도 없다 (방어 · 실측 0건)

  -- ③ 소진 금액 합 → 완제품 레이어 (소진 기록에서 읽는다 · 전량 재생성이라 낡은 행이 없다)
  select coalesce(sum(amount), 0) into v_cost
    from inv_layer_consume
    where doc_type = r.doc_type and doc_number = r.doc_number and reason = 'assembly_in';
  insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                         received_on, age_known, qty, unit_cost, cost_source)
  values (r.sku, r.warehouse, 'assembly', r.doc_number, r.line_ref, null,
          r.occurred_on, true, v_in_net, round(v_cost / v_in_net, 6), 'assembly_sum');
  o_layers := 1;
  if v_partial then o_partial := 1; end if;
end;
$$;

-- ── 보조 6: credit_in 한 행 → 원 판매 되짚기(①) · 남은 레이어 가중평균(②) ──
--   o_layers = 만든 레이어 수 · o_traced = ① 을 탄 키(0/1) · o_avg = ② 를 탄 키(0/1) · o_unknown = unknown 레이어 수 ·
--   o_net_zero = 키 순액 ≤ 0 · o_processed = 이 호출이 키를 처리했으면 1
create or replace function inv_layer_apply_credit(p_ledger_id bigint, p_until date,
                                                  out o_layers int, out o_traced int, out o_avg int,
                                                  out o_unknown int, out o_net_zero int, out o_processed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r         inv_ledger%rowtype;
  v_net     numeric;
  v_need    numeric;
  v_so      text;
  v_take    numeric;
  v_rem     numeric;
  v_remval  numeric;
  c         record;
begin
  o_layers := 0; o_traced := 0; o_avg := 0; o_unknown := 0; o_net_zero := 0; o_processed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found or r.event_type <> 'credit_in' then return; end if;

  if exists (select 1 from inv_layer_apply_done d
              where d.kind = 'credit' and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = r.warehouse) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('credit', r.doc_number, r.sku, r.warehouse);
  o_processed := 1;

  -- 키 순액 (source 무관 · line_ref 키 제외 · p_until 안)
  select sum(qty_delta) into v_net
    from inv_ledger
    where event_type = 'credit_in' and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until);
  if v_net is null or v_net <= 0 then
    o_net_zero := 1;
    return;
  end if;
  v_need := v_net;

  -- 갈래 ① — 원 판매(raw.header.order_number)가 소진한 레이어를 같은 단가로 되돌린다 (소비된 순서 · sku 로 매칭)
  v_so := r.raw -> 'header' ->> 'order_number';
  if v_so is not null then
    for c in
      select s.layer_id, s.unit_cost,
             s.qty - coalesce((select sum(x.qty) from inv_layer x
                                 where x.origin_type = 'creditnote' and x.cost_source = 'return_restore'
                                   and x.parent_layer_id = s.layer_id
                                   and x.doc_number in (select distinct e.doc_number from inv_ledger e
                                                          where e.event_type = 'credit_in'
                                                            and e.raw -> 'header' ->> 'order_number' = v_so)), 0) as avail
        from (select cs.layer_id, cs.unit_cost, sum(cs.qty) as qty, min(l.received_on) as received_on
                from inv_layer_consume cs join inv_layer l on l.id = cs.layer_id
                where cs.doc_type = 'sale' and cs.doc_number = v_so and cs.reason = 'sale' and l.sku = r.sku
                group by cs.layer_id, cs.unit_cost) s
        order by s.received_on, s.layer_id
    loop
      exit when v_need <= 0;
      if c.avail <= 0 then continue; end if;     -- 앞선 크레딧노트가 이미 되돌린 몫
      v_take := least(c.avail, v_need);
      insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                             received_on, age_known, qty, unit_cost, cost_source)
      values (r.sku, r.warehouse, 'creditnote', r.doc_number, r.line_ref, c.layer_id,
              r.occurred_on, true, v_take, c.unit_cost, 'return_restore');
      o_layers := o_layers + 1;
      o_traced := 1;
      v_need := v_need - v_take;
    end loop;
  end if;
  if v_need <= 0 then return; end if;

  -- 갈래 ② — 남은 레이어 가중평균 (adjust_existing A-1 과 같은 규칙 · 그 시점까지의 레이어만)
  select coalesce(sum(rem), 0), coalesce(sum(rem * unit_cost), 0) into v_rem, v_remval
    from (select x.unit_cost,
                 x.qty - coalesce((select sum(k.qty) from inv_layer_consume k where k.layer_id = x.id), 0) as rem
            from inv_layer x where x.sku = r.sku and x.warehouse = r.warehouse) t
    where rem > 0;
  if v_rem > 0 then
    insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                           received_on, age_known, qty, unit_cost, cost_source)
    values (r.sku, r.warehouse, 'creditnote', r.doc_number, r.line_ref, null,
            r.occurred_on, true, v_need, round(v_remval / v_rem, 6), 'layer_avg');
    o_avg := 1;
  else
    insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                           received_on, age_known, qty, unit_cost, cost_source)
    values (r.sku, r.warehouse, 'creditnote', r.doc_number, r.line_ref, null,
            r.occurred_on, true, v_need, 0, 'unknown');
    o_avg := 1; o_unknown := 1;       -- ② 를 탔으나 근거가 없었다
  end if;
  o_layers := o_layers + 1;
end;
$$;

-- ── main: assemble · credit 분기 추가 · 카운터 추가 (그 외는 20260909201223 그대로) ──
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

  select count(*) into v_tr_unpaired
    from (select doc_number, sku, warehouse
            from inv_ledger
            where event_type in ('transfer_out', 'manual_reversal')
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'tr_out' and d.doc_number = o.doc_number and d.sku = o.sku and d.warehouse = o.warehouse);

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

revoke all on function inv_layer_apply_assemble(bigint, date) from public, anon, authenticated;
revoke all on function inv_layer_apply_credit(bigint, date) from public, anon, authenticated;
revoke all on function inv_layer_apply(date) from public, anon;
grant execute on function inv_layer_apply(date) to authenticated;
