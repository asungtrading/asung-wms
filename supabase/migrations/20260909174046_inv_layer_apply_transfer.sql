-- 원가 레이어 사건 적재 2차 — source 필터 제거 · sale 키 순액 · transfer 이동 (2026-09-09)
--
-- 20260909155320_inv_layer_apply.sql 의 함수 셋을 create or replace 로 덮어쓴다(그 파일은 테스트 DB 에 이미 적용돼 손대지 않는다).
-- 시그니처가 바뀐 보조 둘은 옛 것을 drop 한다(out 컬럼이 달라 replace 가 안 된다).
--
-- ═══ A. 결함 수정 — 원장을 읽을 때 `source` 를 필터하지 말 것 ═══
--  ⚠️⚠️ 원장 잔고의 정본은 inv_balance 뷰이고 **그 정의에 source 조건이 없다.** 상쇄는 source='manual' 로만 들어오므로
--  cin7 만 읽으면 **상쇄 전 세계**를 본다. [실측 2026-09-09 운영] source='manual' 전수:
--    manual_reversal/transfer 592행 net +7439 (5문서 · 접미어 0) · sale_out/sale 684행 +3733 (10문서 · 접미어 680) ·
--    transfer_in 138행 −1247 (접미어 138) · transfer_out 151행 +1345 (접미어 138) · assemble_out 8 · adjust_new 3 · assemble_in 3.
--  ⇒ 세 함수에서 source='cin7' 조건을 전부 뺐다(루프 · po_in 키 합 · transfer). manual po_in 은 0건이라 po_in 결과는 같다.
--  ⚠️ [사고 2026-09-09] 이 함정으로 트랜스퍼 5문서를 「이중 기표 · 순액 −7,537」로 오진했다. 실제로는 08-31~09-01 에 정상
--  상쇄돼 doc_net 0 이었다. ⭐ **「⑧·② 대조가 깨끗한데 내 계산이 안 맞으면 감지 창구를 의심하기 전에 ① 내 쿼리의 source
--  필터 ② line_ref 를 키에 넣었는지를 먼저 볼 것.」**
--
-- ═══ B. sale_out — 행 단위 → 키 순액 단위 ═══
--  ⭐ 소진량 = **(doc_number, sku, warehouse) 의 순액 × −1** (event_type='sale_out' · source 무관 · p_until 안).
--  순액 0 이상이면 소진하지 않는다(완전 상쇄된 판매). 루프가 같은 키를 여러 번 만나므로 **처리한 키는 건너뛴다.**
--  ⚠️⚠️ line_ref 를 키에 넣지 않는다 — 상쇄 행은 line_ref 에 ':reversal' 접미어가 붙어 원본과 다르다. line_ref 를 빼면
--  접미어 파싱 없이 자동 상쇄된다. ⚠️ replace(line_ref, ':reversal', '') 는 **금지**(문자열을 만지는 방식 · 규칙이 바뀌면
--  조용히 깨진다 — 「SKU 접미사 파싱 금지」와 같은 정신).
--  [실측 검증 · 같은 데이터를 세 키로 묶은 결과] (doc,line_ref,sku,wh) 13,865키 · 완전상쇄 0 · 순액양수 681 ⚠️ /
--  (+replace) 13,187 · 680 · 1 / ⭐ **(doc,sku,wh) 13,183 · 완전상쇄 681 · 부분 3 · 순액양수 0** — 세 번째만 정합.
--  📌 키 13,183 = cin7 sale_out 행 수와 일치. consume 행의 line_ref 에는 그 원장 행의 line_ref 를 그대로 넣는다(추적용).
--  ⭐ 상쇄 관례(원장 실측 2026-09-09): 타입을 **유지**하는 상쇄는 line_ref 에 ':reversal' 접미어(같은 doc_number 안이라
--  키를 갈라야 한다) · 타입을 **바꾸는** 상쇄(manual_reversal)는 접미어가 없다(타입으로 갈린다).
--  ⇒ ⭐ **키 순액 방식이면 어느 관례든 자동 흡수된다 — 함수가 관례를 알 필요가 없다.**
--
-- ═══ C. transfer — 소비가 아니라 이동 ═══
--  출발 레이어를 소진하고 도착 창고에 **원가·received_on·age_known 을 복사한 레이어**를 만든다(parent_layer_id = 출발 레이어).
--  나이가 따라가야 한다 — 에드먼튼은 PO 가 없어 트랜스퍼가 유일한 유입 경로다.
--  C-1 4행 구조: 쌍1 창고 out(−) → IN_TRANSIT in(+) · 쌍2 IN_TRANSIT out(−) → 창고 in(+). ⭐ leg 쌍은 항상 같은 날 안에서
--      완결된다 — [실측 2026-09-09] 문서×날짜 346개 중 pair1_broken 0 · pair2_broken 0 · orphan 0 ⇒ 날짜순 루프로 처리 가능.
--  C-2 ⚠️ seq_hint 1=유입 · 2=유출이라 같은 날이면 in 이 out 보다 **먼저** 온다 — 도착을 만들려는 시점에 출발이 아직 안 빠졌다.
--      ⭐ 처방: **transfer_in 을 만났을 때 그 자리에서 대응 out 을 먼저 처리한다.** ① 같은 (doc_number, occurred_on) 의 대응
--      out leg(in 이 IN_TRANSIT 이면 창고 · in 이 창고면 IN_TRANSIT) ② 그 out 의 (doc_number, sku, warehouse) 키 순액만큼
--      출발 레이어 FIFO 소진 ③ 소진한 레이어**마다** 도착 레이어 하나 ④ 처리 기록 — 뒤에 그 out 행을 만나면 건너뛴다.
--      📌 out 을 먼저 만나는 경우(대응 in 없음)는 이번 데이터에 0건 — 그 경로는 만들지 않고, 루프 뒤에 「기록 없는 out 키」를
--      transfer_out_unpaired 로 센다(생기면 신호).
--      ⚠️ 같은 날 쌍1·쌍2 가 함께 있으면 두 in 행이 모두 seq_hint 1 이라 **id 순서에 따라 쌍2(창고 in)가 쌍1(IN_TRANSIT in)보다
--      먼저 올 수 있다** — 그때 IN_TRANSIT 레이어가 아직 없어 부족으로 오처리된다. ⇒ 창고 in 을 처리할 때 같은 (doc, sku) 의
--      미처리 IN_TRANSIT in 이 있으면 **그것을 먼저 처리한다**(중첩 호출 · 카운터는 합산). 순서에 기대지 않는다.
--  C-3 ⚠️ 대응 out **행 자체**가 없는 경우 — 방어 경로.
--      같은 (doc_number, occurred_on) 에 in leg 는 있는데 out leg 행이 아예 없는 문서다.
--      ⇒ 도착 레이어를 만든다(수량이 원장과 맞아야 대조 안전망이 유지된다) · parent null · cost_source 'unknown' · unit_cost 0 ·
--      received_on = 그 행의 occurred_on · age_known false · 예외 없음 · transfer_orphan_in +1.
--      📌 [실측 2026-09-09] **이번 데이터에 0건**이다(문서×날짜 346개 중 pair1_broken 0 · pair2_broken 0 · orphan 0).
--      ⇒ ⭐ 실동작 미검증 방어 경로이고, transfer_orphan_in 이 0 이 아니게 되는 것 자체가 신호다.
--      ⚠️⚠️ **TR-03975 계열(8/20 이전 출발 · leg 1·2 가 since 필터로 원장에 없음)은 여기가 아니라 C-4 다.** leg 3(IN_TRANSIT out)이
--      실재하므로 대응 out 은 찾아지고, 다만 IN_TRANSIT 에 소진할 레이어가 없어 부족으로 떨어진다.
--      ⇒ ⭐ **도착 레이어를 만들지 않는 것이 옳다** — 만들면 없는 재고를 만드는 셈이고(스킬: 「상쇄하면 없던 사건을 만드는 셈이다」),
--      원장도 IN_TRANSIT 잔고를 영구히 음수로 남겨두고 채우지 않는다. 레이어가 채우면 두 축이 어긋나 대조가 깨진다.
--      ⚠️ 대가는 에드먼튼 재고가 그만큼 레이어에 없는 것이고 short_events 로 세진다 ⇒ 「모르면 비워둔다」. 재기준선이 지운다.
--      (Caleb 판정 2026-09-09)
--  C-4 ⚠️ 출발 레이어 부족 — sale_out 과 같다. 있는 만큼만 소진하고 **그만큼만** 도착 레이어를 만든다. 부족분은 소비 기록도
--      도착 레이어도 만들지 않는다. short_events +1 · 예외 없음.
--  C-5 레이어: origin_type 'transfer' · doc_number = TR 번호(⭐ 운송비를 inv_layer_cost_add 로 얹을 때의 연결점) · line_ref = 그
--      원장 행의 line_ref(추적용) · cost_source 'parent_layer' · received_on·age_known·unit_cost = **출발 레이어에서 복사**
--      (⚠️⚠️ 도착일이 아니라 원래 입고일 — 물건은 그대로고 자리만 옮겼다) · parent_layer_id = 출발 레이어 id.
--  C-6 소비 기록: inv_layer_consume reason='transfer' · unit_cost 는 그 레이어 값을 굳힌다. ⚠️ **COGS 가 아니다** — 트랜스퍼는
--      손익에 영향이 없다. reason 이 그 구분이다.
--  C-7 ⚠️ manual_reversal 592행 — 전부 doc_type='transfer' · seq_hint 1 · 전량 양수. **정상 사건으로 처리하지 않는다.**
--      [확정 · 원장 실측 2026-09-09] 이 592행은 08-31 「출발 bin 해결」 배포가 만든 옛 벌(창고 out · 빈 bin)을 상쇄한 것이다.
--      08-31 20:11:28.585~.988 — **0.4초 안에 5문서**에 써졌고 그 다섯이 TR-04173·04174·04175·04330·04331 이다.
--      ⇒ 상쇄 대상이 out leg 이므로 **out leg 의 키 순액에 더하는 것이 옳다**(양수라 out 을 줄인다). 타입 분기로 「유입」에 넣으면
--      부호가 반대라 결과가 뒤집힌다. 📌 관례가 아니라 **사건 하나**다 — 앞으로 같은 타입이 다른 성격으로 쓰이면 이 가정이 깨진다.
--  ⚠️ out leg / in leg 의 구분은 event_type 으로 한다: out leg = transfer_out + manual_reversal · in leg = transfer_in
--      (각각 ':reversal' 접미어 상쇄 행은 같은 타입이라 자동 포함). IN_TRANSIT 은 한 문서 안에 in·out 이 함께 있어 창고 키만으로는
--      순액이 0 이 되므로 이 구분이 필요하다.
--
-- ⚠️ 운송비는 이번 범위 밖 — stockTransfer.ManualJournals 에서 Debit='_59_' 만 · inv-cost 확장이 먼저 필요하다. 배분이
--  CostDistributionType='Cost'(원가 비례)라 **이 함수가 만든 레이어의 원가가 있어야 계산된다** ⇒ 순서가 고정이다.
-- ⬜ 미처리로 남는 것: adjust_existing(±157) · adjust_new(28) · assemble(21) · credit_in(18).
--  ⚠️ 잔량 대조는 그 넷까지 붙은 뒤에 의미를 갖는다(20260909155320 헤더의 정정 참조).
--
-- 반환 jsonb 추가: sale_keys_processed · sale_keys_fully_reversed · processed_transfer(transfer 계열 행 수) ·
--  transfer_layers_created · transfer_orphan_in · transfer_out_unpaired. skipped_by_type 에서 transfer 계열은 빠진다.
--
-- 조회 예시:
--   select inv_layer_apply();
--   select warehouse, origin_type, count(*), sum(qty) from inv_layer group by 1,2 order by 1,2;
--   select l.doc_number, l.warehouse, l.qty, l.received_on, l.age_known, p.warehouse as from_wh
--   from inv_layer l join inv_layer p on p.id = l.parent_layer_id where l.origin_type='transfer' limit 20;

drop function if exists inv_layer_apply_po_in(bigint, date);
drop function if exists inv_layer_apply_sale_out(bigint);

-- ── 처리 기록 (세션 임시 표 · main 이 만들고 비운다) ──
--   kind: 'sale' (doc,sku,wh) · 'tr_in' (doc,sku,wh,day) · 'tr_out' (doc,sku,wh)
create or replace function inv_layer_apply_reset_done()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if to_regclass('pg_temp.inv_layer_apply_done') is null then
    create temp table inv_layer_apply_done (
      kind text not null, doc_number text not null, sku text not null, warehouse text not null,
      day date not null default '0001-01-01',   -- 날짜가 키에 안 드는 kind(sale · tr_out)는 기본값 — PK 컬럼은 null 불가
      primary key (kind, doc_number, sku, warehouse, day)
    ) on commit drop;
  else
    truncate inv_layer_apply_done;
  end if;
end;
$$;

-- ── 공통: FIFO 소진 (+ 선택적으로 도착 창고에 복사 레이어) ──
--   p_dest_wh null = 소비만(sale) · not null = 소진한 레이어마다 도착 레이어 하나(transfer)
--   o_rows = consume 행 수 · o_short = 부족했으면 1 · o_layers = 만든 도착 레이어 수 · o_taken = 실제 소진 수량
create or replace function inv_layer_fifo_take(p_sku text, p_wh text, p_need numeric,
                                               p_doc_type text, p_doc_number text, p_line_ref text,
                                               p_event_type text, p_occurred_on date, p_reason text,
                                               p_dest_wh text,
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
      -- 이동: 원가·received_on·age_known 복사 · parent = 출발 레이어 (C-5)
      insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                             received_on, age_known, qty, unit_cost, cost_source)
      values (p_sku, p_dest_wh, 'transfer', p_doc_number, p_line_ref, l.id,
              l.received_on, l.age_known, v_take, l.unit_cost, 'parent_layer');
      o_layers := o_layers + 1;
    end if;
    o_taken := o_taken + v_take;
    v_need := v_need - v_take;
  end loop;
  if v_need > 0 then o_short := 1; end if;   -- 부족분은 소비도 도착도 만들지 않는다 · 예외 없음 (C-4)
end;
$$;

-- ── 보조 1: po_in 한 행 → 그 행의 4키 레이어가 없으면 만든다 (source 필터만 뺐다 · 나머지 20260909155320 그대로) ──
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

  if exists (select 1 from inv_layer l
              where l.origin_type = 'purchase' and l.doc_number = r.doc_number and l.line_ref = r.line_ref
                and l.sku = r.sku and l.warehouse = r.warehouse) then
    return;
  end if;

  -- 키의 원장 합 (양수만 · p_until 안 · ⚠️ source 무관) — bin 을 버리고 창고 단위로
  select sum(qty_delta), min(occurred_on) into v_qty, v_received_on
    from inv_ledger
    where event_type = 'po_in' and qty_delta > 0
      and doc_number = r.doc_number and line_ref = r.line_ref and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until);
  if v_qty is null or v_qty <= 0 then return; end if;

  select sum(amount), sum(qty) into v_cost_amt, v_cost_qty
    from inv_cost
    where cost_kind = 'goods'
      and doc_number = r.doc_number and line_ref = r.line_ref and sku = r.sku and warehouse = r.warehouse;
  -- 원가 가드 (20260909155320 헤더) — 행이 있는데 음수·0 수량이면 거부. 행 0건은 unknown 경로.
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

-- ── 보조 2: sale_out 한 행 → 키 (doc_number, sku, warehouse) 순액으로 한 번만 FIFO 소진 (B) ──
--   o_processed = 이 호출이 키를 처리했으면 1(중복 호출은 0) · o_reversed = 순액 ≤ 0 이라 소진 없이 닫혔으면 1
create or replace function inv_layer_apply_sale_out(p_ledger_id bigint, p_until date,
                                                    out o_rows int, out o_short int,
                                                    out o_processed int, out o_reversed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r       inv_ledger%rowtype;
  v_net   numeric;
  v_rows  int; v_short int; v_layers int; v_taken numeric;
begin
  o_rows := 0; o_short := 0; o_processed := 0; o_reversed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found then return; end if;

  -- 이미 처리한 키면 끝
  if exists (select 1 from inv_layer_apply_done d
              where d.kind = 'sale' and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = r.warehouse) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('sale', r.doc_number, r.sku, r.warehouse);
  o_processed := 1;

  -- 키 순액 × −1 — ⚠️ line_ref 는 키에 없다(접미어 상쇄 자동 흡수) · source 무관
  select -sum(qty_delta) into v_net
    from inv_ledger
    where event_type = 'sale_out'
      and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until);
  if v_net is null or v_net <= 0 then o_reversed := 1; return; end if;   -- 완전 상쇄된 판매

  select * into v_rows, v_short, v_layers, v_taken
    from inv_layer_fifo_take(r.sku, r.warehouse, v_net,
                             r.doc_type, r.doc_number, r.line_ref, r.event_type, r.occurred_on, 'sale', null);
  o_rows := v_rows; o_short := v_short;
end;
$$;

-- ── 보조 3: transfer_in 한 행 → 대응 out 을 먼저 소진하고 도착 레이어 생성 (C) ──
--   o_layers = 도착 레이어 수 · o_rows = consume 행 수 · o_short = 출발 부족 · o_orphan = 대응 out 없음(unknown 레이어) ·
--   o_processed = 이 호출이 in 키를 처리했으면 1
create or replace function inv_layer_apply_transfer_in(p_ledger_id bigint, p_until date,
                                                       out o_layers int, out o_rows int, out o_short int,
                                                       out o_orphan int, out o_processed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r         inv_ledger%rowtype;
  v_out_wh  text;
  v_out     record;          -- 대응 out 대표 행 (doc_type · line_ref · event_type · occurred_on)
  v_out_net numeric;
  v_in_net  numeric;
  v_it      record;          -- 먼저 처리할 IN_TRANSIT in 행 (⓪)
  v_rows int; v_short int; v_layers int; v_taken numeric; v_orphan int; v_proc int;
begin
  o_layers := 0; o_rows := 0; o_short := 0; o_orphan := 0; o_processed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found then return; end if;

  -- in 키 (doc, sku, 도착창고, 날짜) 중복 방지 — 같은 날 두 bin 으로 도착해도 한 번
  if exists (select 1 from inv_layer_apply_done d
              where d.kind = 'tr_in' and d.doc_number = r.doc_number and d.sku = r.sku
                and d.warehouse = r.warehouse and d.day = r.occurred_on) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse, day) values ('tr_in', r.doc_number, r.sku, r.warehouse, r.occurred_on);
  o_processed := 1;

  -- ⓪ 창고 in 인데 같은 (doc, sku) 의 IN_TRANSIT in 이 아직 안 처리됐으면 그것부터 (C-2 · 같은 날 id 순서 무관)
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
      select * into v_layers, v_rows, v_short, v_orphan, v_proc from inv_layer_apply_transfer_in(v_it.id, p_until);
      o_layers := o_layers + v_layers; o_rows := o_rows + v_rows; o_short := o_short + v_short; o_orphan := o_orphan + v_orphan;
    end loop;
  end if;

  -- ① 대응 out leg 의 창고 — in 이 IN_TRANSIT 이면 창고 · in 이 창고면 IN_TRANSIT (같은 문서·날짜 우선)
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

  -- ② out leg 의 키 순액 × −1 (event_type 으로 leg 를 가른다 · source 무관 · 접미어·manual_reversal 자동 흡수)
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
    -- C-3 대응 out 없음 — 기초 경계. in 키 순액만큼 unknown 도착 레이어 · 예외 없음
    select sum(qty_delta) into v_in_net
      from inv_ledger
      where doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse and event_type = 'transfer_in'
        and (p_until is null or occurred_on <= p_until);
    if v_in_net is not null and v_in_net > 0 then
      insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                             received_on, age_known, qty, unit_cost, cost_source)
      values (r.sku, r.warehouse, 'transfer', r.doc_number, r.line_ref, null,
              r.occurred_on, false, v_in_net, 0, 'unknown');
      o_layers := 1;
    end if;
    o_orphan := 1;
    return;
  end if;

  -- ④ out 키 기록 — 뒤에 그 out 행을 만나면 건너뛴다
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('tr_out', r.doc_number, r.sku, v_out_wh)
    on conflict do nothing;

  -- ②③ 출발 FIFO 소진 + 소진한 레이어마다 도착 레이어 (reason='transfer' · COGS 아님)
  select * into v_rows, v_short, v_layers, v_taken
    from inv_layer_fifo_take(r.sku, v_out_wh, v_out_net,
                             v_out.doc_type, r.doc_number, v_out.line_ref, v_out.event_type, v_out.occurred_on,
                             'transfer', r.warehouse);
  o_rows := o_rows + v_rows; o_short := o_short + v_short; o_layers := o_layers + v_layers;   -- ⓪ 중첩분에 더한다
end;
$$;

-- ── main: 전량 재생성 · 날짜순 루프 (A: source 필터 없음 · B · C 반영) ──
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
  v_c int; v_u int; v_rows int; v_short int; v_proc int; v_rev int; v_layers int; v_orphan int;
  v_po          int := 0;
  v_sale        int := 0;
  v_sale_keys   int := 0;
  v_sale_rev    int := 0;
  v_tr          int := 0;
  v_tr_layers   int := 0;
  v_tr_orphan   int := 0;
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

  -- 전량 재생성 — FK 순서: consume · cost_add 먼저, 그 다음 baseline 외 레이어
  delete from inv_layer_consume;
  delete from inv_layer_cost_add;
  delete from inv_layer where origin_type <> 'baseline';
  perform inv_layer_apply_reset_done();

  -- 날짜순 루프 — ⭐ order by occurred_on, seq_hint, id (같은 날은 유입 먼저) · ⚠️ source 필터 없음
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
      select * into v_layers, v_rows, v_short, v_orphan, v_proc from inv_layer_apply_transfer_in(r.id, p_until);
      v_tr := v_tr + 1; v_tr_layers := v_tr_layers + v_layers; v_consume := v_consume + v_rows;
      v_shorts := v_shorts + v_short; v_tr_orphan := v_tr_orphan + v_orphan;
    else
      -- transfer_out · manual_reversal: out leg 는 대응 in 이 처리한다(C-2 ④) — 여기서는 세기만
      v_tr := v_tr + 1;
    end if;
  end loop;

  -- C-2 📌 대응 in 없이 남은 out 키 — 이번 데이터엔 0건이어야 한다(생기면 신호)
  select count(*) into v_tr_unpaired
    from (select distinct doc_number, sku, warehouse
            from inv_ledger
            where event_type in ('transfer_out', 'manual_reversal')
              and (p_until is null or occurred_on <= p_until)) o
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
    'transfer_out_unpaired',     v_tr_unpaired,
    'skipped_by_type',           v_skipped,
    'layers_created',            v_layers_po,
    'consume_rows',              v_consume,
    'cost_unknown_layers',       v_unknown,
    'short_events',              v_shorts,
    'elapsed_ms',                round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$$;

revoke all on function inv_layer_apply_reset_done() from public, anon, authenticated;
revoke all on function inv_layer_fifo_take(text, text, numeric, text, text, text, text, date, text, text) from public, anon, authenticated;
revoke all on function inv_layer_apply_po_in(bigint, date) from public, anon, authenticated;
revoke all on function inv_layer_apply_sale_out(bigint, date) from public, anon, authenticated;
revoke all on function inv_layer_apply_transfer_in(bigint, date) from public, anon, authenticated;
revoke all on function inv_layer_apply(date) from public, anon;
grant execute on function inv_layer_apply(date) to authenticated;
