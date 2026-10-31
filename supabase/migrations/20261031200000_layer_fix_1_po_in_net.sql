-- layer-fix-1 (2026-10-31 · deferred 403 · A 차수) — inv_layer_apply_po_in 이 manual 상쇄(:reversal · :reversal:fix · :reversal:fix:undo · :voided)를 못 읽던 결함.
--
-- 원본: 20260920142635:33~105 (마지막 판 · DB prosrc md5 ada141e8df74f575b5b8b021564672be · 2026-10-31 대조). 시그니처 무변 · create or replace.
-- 결함: 키에 line_ref 가 그대로 들어가 「…:reversal」 이 다른 키가 되고, 「qty_delta > 0」 이 음수를 걸렀다.
--       ⇒ PO-01361 Kim & C 5 칸(36,864 · AS91603 의 :reversal:fix +5,760 은 양수라 제 키로 unknown 레이어까지 섰다) ·
--         PO-01382 LAC79351~64 14 칸(+99 ×13 · +27) 이 「레이어 > 원장」 으로 남았다(reload §I ② 10-30 실측 · so §91-d).
-- 고침(셋 · 나머지 바이트는 원본 그대로):
--   ① v_base := split_part(line_ref, ':', 1) — 원행과 상쇄 · 정정 · 되돌림을 한 키로(Cin7 po_in line_ref 2,847 줄 전부 GUID · 콜론 0 · IMS 줄은 위 문에서 돌아선다)
--   ② 원장 합을 「양수만」 이 아니라 순액으로 · 순액 > 0 만 레이어 · received_on 은 양수 행의 min(occurred_on)
--   ③ 레이어 존재 확인 · inv_cost 조회 · 레이어 line_ref 를 전부 v_base 로 — flush_adds 의 landed 얹기(x.line_ref = c.line_ref)가 그대로 맞는다
-- 다른 축(sale_out · assemble · adjust · credit · transfer_in ← out leg)은 이미 (doc, sku, wh) 순액 · source 무관으로 읽는다(2026-10-31 조사) — 손대지 않는다.
-- 호출자: inv_layer_apply 하나(prosrc grep · 2026-10-31). 실시간 포스터는 이 함수를 부르지 않는다.

create or replace function inv_layer_apply_po_in(p_ledger_id bigint, p_until date,
                                                 out o_created int, out o_unknown int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r             inv_ledger%rowtype;
  v_base        text;      -- layer-fix-1: 접미어를 뗀 기준 line_ref (원행 GUID)
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
  -- ⭐⭐ IMS 문 (2026-09-20) — 이 줄은 우리 것이다. Cin7 방식으로 만들지 않는다.
  -- 왜: inv_cost 에는 IMS 입고가 없다(Cin7 을 거치지 않았다) ⇒ 아래 unknown 경로로 빠져
  --     unit_cost 0 · cost_source 'unknown' 레이어가 선다. 수량은 맞고 금액만 0 이라 조용하다.
  --     게다가 그 0 짜리가 4키 자리를 차지해 inv_layer_post_receipt 의 멱등이 「이미 있다」로 건너뛴다 ⇒ 창구를 다시 불러도 복구가 안 된다.
  -- 이 줄의 레이어는 본체 inv_layer_apply 가 같은 루프 자리에서 inv_layer_post_receipt(창구) 로 만든다 — 원가 규칙은 창구 한 곳에만 산다.
  if r.source = 'ims' then
    return;
  end if;

  -- layer-fix-1 (2026-10-31 · deferred 403): 상쇄 접미어(:reversal · :voided · :reversal:fix …)를 떼어 원행과 한 키로 본다.
  v_base := split_part(r.line_ref, ':', 1);

  if exists (select 1 from inv_layer l
              where l.origin_type = 'purchase' and l.doc_number = r.doc_number and l.line_ref = v_base
                and l.sku = r.sku and l.warehouse = r.warehouse) then
    return;
  end if;

  -- 키의 원장 순액 (상쇄 포함 · p_until 안 · ⚠️ source 무관) — bin 을 버리고 창고 단위로 · received_on 은 양수(입고) 행의 첫 날
  select sum(qty_delta), min(occurred_on) filter (where qty_delta > 0) into v_qty, v_received_on
    from inv_ledger
    where event_type = 'po_in'
      and doc_number = r.doc_number and split_part(line_ref, ':', 1) = v_base and sku = r.sku and warehouse = r.warehouse
      and source <> 'ims'   -- ⭐ 2026-09-20 · IMS 행은 위 문에서 돌아섰지만, 같은 4키에 두 축이 함께 잡히는 날 한 레이어로 합쳐지지 않게 여기서도 가른다. ⚠️ 'cin7' 만 고르지 않는다 — manual(상쇄) 행은 들어가야 한다
      and (p_until is null or occurred_on <= p_until);
  if v_qty is null or v_qty <= 0 then return; end if;   -- 전량 상쇄(순액 0 이하) — 레이어 없음

  select sum(amount), sum(qty) into v_cost_amt, v_cost_qty
    from inv_cost
    where cost_kind = 'goods'
      and doc_number = r.doc_number and line_ref = v_base and sku = r.sku and warehouse = r.warehouse;
  -- 원가 가드 (20260909155320 헤더) — 행이 있는데 음수·0 수량이면 거부. 행 0건은 unknown 경로.
  if v_cost_qty is not null then
    if v_cost_amt < 0 then
      raise exception 'inv_cost goods sum(amount) is negative for % / % / % / %: % — refusing to build layer (revaluation offset? inspect inv_cost)',
        r.doc_number, v_base, r.sku, r.warehouse, v_cost_amt;
    end if;
    if v_cost_qty <= 0 then
      raise exception 'inv_cost goods sum(qty) is % (<= 0) for % / % / % / % — refusing to build layer (division by zero)',
        v_cost_qty, r.doc_number, v_base, r.sku, r.warehouse;
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
  values (r.sku, r.warehouse, 'purchase', r.doc_number, v_base, null,
          v_received_on, true, v_qty, v_unit, v_source);
  o_created := 1;
end;
$$;
