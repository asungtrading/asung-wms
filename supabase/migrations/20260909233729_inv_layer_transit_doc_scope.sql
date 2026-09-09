-- 원가 레이어 사건 적재 — IN_TRANSIT 소진은 같은 문서의 레이어에서만 (2026-09-09 밤)
--
-- 20260909174046 의 inv_layer_fifo_take(10인자)를 **drop 하고 11인자로 다시 만든다**(선택적 p_doc_scope) ·
-- 20260909190145 의 inv_layer_apply_transfer_in 을 create or replace 로 덮어쓴다(시그니처 동일 · 호출부 한 줄 변경).
-- main(inv_layer_apply · 20260909231134) 은 건드리지 않는다 — transfer_in 의 시그니처가 같아 그대로 부른다.
-- 기존 마이그레이션은 전부 테스트 DB 에 적용돼 손대지 않는다.
--
-- ═══ ⚠️⚠️ 결함 — IN_TRANSIT 에서 FIFO 가 남의 문서 레이어를 먹는다 ═══
--  [실측 2026-09-09 테스트 DB]
--    IN_TRANSIT consume 행 1,164
--      같은 문서   1,076
--      ⚠️ 다른 문서   88 · 1,345개   ← 결함
--  실물 — VNA57973
--    08-21  TR-04174  토론토 기초에서 −24  → IN_TRANSIT 레이어 46646 생성 (TR-04174)
--    08-26  TR-03975  ⚠️ 레이어 46646 을 소진  ← 자기 IN_TRANSIT 레이어가 없어서
--    09-01  TR-04174  IN_TRANSIT 에서 빼려는데 ⚠️ 이미 없다 → short
--  ⚠️ TR-03975 는 **기초 이전 출발**(8/14 출발 · leg 1·2 가 since 로 원장에 없음)이라 IN_TRANSIT 레이어가 없다. 그런데 FIFO 가
--  「그 SKU×IN_TRANSIT 의 오래된 레이어부터」 가져가므로 **TR-04174 것을 대신 먹었다.**
--
--  ⭐ **왜 창고와 IN_TRANSIT 을 다르게 다루나** — FIFO 자체는 정상 동작이다. **창고에서는 물건이 섞이는 것이 맞다** — 같은 자리에
--  있는 물건은 어느 문서로 들어왔든 한 뭉치다. ⚠️ **운송 중 재고는 문서별로 묶여 있다 — 다른 트럭에 실려 있다.** TR-03975 로 실려 간
--  물건과 TR-04174 로 실려 간 물건은 만날 수 없다. ⇒ **FIFO 의 전제(같은 자리 = 같은 뭉치)가 IN_TRANSIT 에는 성립하지 않는다.**
--  IN_TRANSIT 은 우리가 합성한 창고(원장 4행 구조)이고, 그 안의 「자리」는 창고가 아니라 **문서**다.
--
--  ⚠️ [사고 2026-09-09] 이 결함이 사건 9종을 다 붙인 뒤 남은 어긋남의 뿌리였다 — 잔량 대조(inv_layer 잔량 vs inv_balance):
--    ⭐ TOR gap **0** · 어긋난 칸 **0** (7,620칸 전부 일치)
--    ⚠️ EDM gap **−165** · 어긋난 칸 14
--    IN_TRANSIT gap +2,451 (⚠️ 이 중 일부는 구조적 — 원장 음수 215칸 · ledger-design §11)
--  EDM 14칸이 전부 이 연쇄다 — 남의 레이어를 먹혀서 정작 주인 문서가 도착할 때 빈손이 되고, 그 SKU 의 이후 사건까지 부족으로
--  번진다. 📌 short_events 14 와 어긋난 칸 14 가 같은 수다. ⭐ **TOR 은 이미 gap 0 이었다** — 창고 축은 정상이고 IN_TRANSIT 만
--  틀렸다는 것이 진단의 근거였다(창고 FIFO 를 건드릴 이유가 없다).
--
-- ═══ 고친 것 ═══
--  inv_layer_apply_transfer_in 의 **출발 레이어 소진 범위**:
--    출발 창고가 IN_TRANSIT 이면 → **같은 doc_number 의 IN_TRANSIT 레이어만** 소진 대상 · 그 안에서는 종전대로 received_on, id 순 FIFO ·
--      부족하면 종전 경로 그대로(쌍1 transfer_in@IN_TRANSIT 이 원장에 없으면 unknown 도착 레이어 · 있으면 short_events — 20260909190145).
--    출발 창고가 실제 창고(토론토·에드먼튼)면 → ⭐ **종전대로 FIFO 전체. 바꾸지 않는다.**
--
--  ⚠️ 구현 위치 — inv_layer_fifo_take 는 판매(sale_out)·조정(adjust_out)·조립(assembly_in)·트랜스퍼가 **함께 쓰는 공통 함수**다.
--  ⭐ 거기에 doc_number 조건을 무조건 넣으면 판매가 「그 판매 문서의 레이어」만 찾게 되어 **전부 부족으로 떨어진다**(판매는 레이어를
--  만들지 않는다). ⇒ 선택지 (a) **선택적 파라미터 p_doc_scope text default null** — null 이면 종전과 완전히 같고(다른 호출부는 인자를
--  안 넘기므로 자동으로 null), transfer_in 이 IN_TRANSIT 출발일 때만 doc_number 를 넘긴다.
--  (b) 트랜스퍼 전용 소진 경로를 따로 두는 안을 버린 이유: FIFO 루프·consume 삽입·도착 레이어 복사가 한 벌 더 생겨 **두 벌이 갈라진다**
--  (한쪽만 고치는 사고의 자리). 범위 조건은 where 절 한 줄이고 그것을 분기하는 것이 옳다.
--  ⚠️ Postgres 는 인자 수가 다른 함수를 **오버로드로 공존**시킨다 — 옛 10인자를 drop 하지 않으면 10인자 호출이 「10인자」와 「11인자+기본값」
--  사이에서 function is not unique 로 죽는다. 그래서 drop 먼저. plpgsql 호출부(sale_out·adjust·assemble)는 실행 시 해석되므로 다시
--  만들 필요가 없다.
--
--  📌 origin_type 은 범위에 넣지 않는다 — 판단 근거: IN_TRANSIT 레이어는 **전부 origin_type='transfer'** 다. 기초는 OnHand 만 읽어
--  IN_TRANSIT 이 없고(20260908202555), 발주·조정·조립·반품의 warehouse 는 Cin7 Location 에서 오므로 우리 합성값 IN_TRANSIT 이 될 수
--  없다. IN_TRANSIT 에 unknown 으로 만들어진 레이어(orphan 경로)도 origin_type='transfer' · doc_number = 그 TR 이고, **그 문서의 leg 3 이
--  그것을 소진하는 것이 맞다**(자기 문서 것). ⇒ doc_number 만으로 충분하고, origin_type 을 더하면 걸러지는 것이 없다. 조건을 늘려
--  「왜 이 레이어가 안 잡히나」의 자리를 하나 더 만들 이유가 없다.
--
--  ⚠️ 조립·판매·조정은 이 범위 제한을 받지 않는다 — 호출부가 p_doc_scope 를 넘기지 않는다(아래 [로컬 검증] 판매·조립이 문서 경계
--  없이 오래된 것부터 소진하는지 확인). IN_TRANSIT 재고를 판매하거나 조립에 쓰는 일은 없어야 하지만, 있다면 그것은 별개 문제이고
--  이 수정이 그 경로를 막지 않는다(그 호출은 doc_scope null → IN_TRANSIT 전체 FIFO).
--
-- 반환 jsonb: 변경 없음. 기대 효과 [테스트 DB 예측]: IN_TRANSIT consume 「다른 문서」 88행 → 0 · EDM gap −165 → 0 · short_events 14 → 0
--  (⚠️ 예측이다 — 테스트 DB 에 적용해 실측할 것 · transfer_unknown_layers/_qty 는 늘어난다(TR-03975 계열이 이제 정직하게 unknown 으로 간다)).
--
-- 조회 예시 — 결함 재발 감지(0 이어야 한다):
--   select count(*) filter (where c.doc_number <> l.doc_number) as other_doc, count(*) as total
--   from inv_layer_consume c join inv_layer l on l.id = c.layer_id where l.warehouse = 'IN_TRANSIT' and c.reason = 'transfer';

-- ── 공통: FIFO 소진 — p_doc_scope 추가 (옛 10인자 drop · 헤더 「구현 위치」) ──
--   p_doc_scope null = 그 SKU×창고 전체(종전과 동일 · 판매·조정·조립·창고 출발 트랜스퍼) ·
--   not null = 그 doc_number 로 만들어진 레이어만(IN_TRANSIT 출발 트랜스퍼)
drop function if exists inv_layer_fifo_take(text, text, numeric, text, text, text, text, date, text, text);

create or replace function inv_layer_fifo_take(p_sku text, p_wh text, p_need numeric,
                                               p_doc_type text, p_doc_number text, p_line_ref text,
                                               p_event_type text, p_occurred_on date, p_reason text,
                                               p_dest_wh text, p_doc_scope text default null,
                                               out o_rows int, out o_short int, out o_layers int, out o_taken numeric)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_need numeric := p_need;
  v_take numeric;
  l      record;
begin
  o_rows := 0; o_short := 0; o_layers := 0; o_taken := 0;
  if v_need is null or v_need <= 0 then return; end if;
  for l in
    select x.id, x.unit_cost, x.received_on, x.age_known,
           x.qty - coalesce((select sum(c.qty) from inv_layer_consume c where c.layer_id = x.id), 0) as remaining
      from inv_layer x
      where x.sku = p_sku and x.warehouse = p_wh
        and (p_doc_scope is null or x.doc_number = p_doc_scope)     -- ⭐ IN_TRANSIT 출발만 문서 범위 (헤더)
      order by x.received_on, x.id          -- inv_layer_fifo_idx
  loop
    exit when v_need <= 0;
    if l.remaining <= 0 then continue; end if;
    v_take := least(l.remaining, v_need);
    insert into inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on,
                                   qty, unit_cost, amount, reason)
    values (l.id, p_doc_type, p_doc_number, p_line_ref, p_event_type, p_occurred_on,
            v_take, l.unit_cost, round(v_take * l.unit_cost, 6), p_reason);
    o_rows := o_rows + 1;
    if p_dest_wh is not null then
      insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                             received_on, age_known, qty, unit_cost, cost_source)
      values (p_sku, p_dest_wh, 'transfer', p_doc_number, p_line_ref, l.id,
              l.received_on, l.age_known, v_take, l.unit_cost, 'parent_layer');
      o_layers := o_layers + 1;
    end if;
    o_taken := o_taken + v_take;
    v_need := v_need - v_take;
  end loop;
  if v_need > 0 then o_short := 1; end if;
end;
$$;

-- ── 보조 3: transfer_in — 출발이 IN_TRANSIT 이면 같은 문서 레이어만 소진 (그 외 20260909190145 그대로) ──
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
  --    ⭐ 출발이 IN_TRANSIT 이면 같은 문서의 레이어만 (p_doc_scope = r.doc_number) · 실제 창고 출발은 종전대로 전체 FIFO (null)
  select * into v_rows, v_short, v_layers, v_taken
    from inv_layer_fifo_take(r.sku, v_out_wh, v_out_net,
                             v_out.doc_type, r.doc_number, v_out.line_ref, v_out.event_type, v_out.occurred_on,
                             'transfer', r.warehouse,
                             case when v_out_wh = 'IN_TRANSIT' then r.doc_number else null end);
  o_rows := o_rows + v_rows; o_layers := o_layers + v_layers;

  -- ⭐ 부족분 — 기초 이전 출발(IN_TRANSIT 출발 · 쌍1 이 원장에 없음)만 도착 창고에 원가 미상 레이어 (20260909190145 「적용 범위」).
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

revoke all on function inv_layer_fifo_take(text, text, numeric, text, text, text, text, date, text, text, text) from public, anon, authenticated;
revoke all on function inv_layer_apply_transfer_in(bigint, date) from public, anon, authenticated;
