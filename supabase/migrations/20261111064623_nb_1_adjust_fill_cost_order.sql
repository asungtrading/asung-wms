do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;

-- ═══ nb-1 — + 조정의 원가 메우기 규칙 · 단가를 비운 + 조정의 원가 순서 (2026-11-11 · 판정 1169 · 1170 · 1171 · 정본 so-module §112-g 3 · 지시서 ~/asung/prompts/nb-1.md) ═══
--   결함(§112-g 3 · 유령 원가): 재고 없이 팔면 inv_layer_post_sale 이 sale_shortfall 레이어를 세우고 그 자리에서 소진한다(장부 −1 · 레이어 남은 0) · 그 뒤 + 조정은 inv_layer_post_adjust 가
--     줄마다 새 레이어를 무조건 세워 장부 0 · 레이어 남은 1(가치 있음)이 된다 — 실물 EZB70340 · ORS21020 EDM(합 $10.82 · 고치는 것은 nb-5).
--   R1 메우기(판정 1170 · 모든 + 조정): f = 그 SKU × 창고의 「레이어 남은 수량 − 장부 수량」(0 아래는 0) · min(q, f) 만큼은 레이어를 세우지 않는다 · 남는 몫만 종전대로.
--     f 를 두 장부의 차로 세는 까닭(지시서 ⬜1 (나)): 지점 창고 15,404 키가 전부 레이어 = 장부이고 어긋난 것은 유령 둘뿐(11-11 01:40 토론토 읽기) — 차이가 곧 「메워지지 않은 부족분」이다 ·
--     메움을 따로 적는 표가 필요 없고 · 재고 없이 판 뒤 입고가 먼저 와도(장부 9 · 레이어 10) 같은 식이 맞고 · 다른 칸의 − 조정이 short 로 끝난 뒤의 + 조정도 유령을 만들지 않는다.
--     메움 몫은 레이어 · 소진 행을 만들지 않는다 ⇒ 하루 원가 장(qbo_cost_expected 는 레이어 · 소진 · 얹힌 몫만 읽는다)에 아무것도 안 쓰인다 — 판정 1094 가 판매 때 이미 적었다(두 번 안 쓴다 · 새 origin · cost_source · reason 값 없음).
--   R2 원가 순서(판정 1171 · 메우고 남는 몫 · 단가 비움): ② 이 창고 남은 레이어 가중평균(그대로) → ③ 최근 원가(inv_layer_recent_cost — inv_layer_post_sale 의 ② 블록과 같은 세 단계 · sale_shortfall 원천 제외) → ④ unknown 0 · 단가를 넣으면 manual(그대로).
--   R3 재생성 hint: raw.cost(= 이 창구의 반환)에 fill_qty · layer_qty · step · source 가 실린다 · hint 가 있으면 fill_qty 를 다시 세지 않는다(옛 행에는 열쇠가 없다 = 0 — 옛 결과를 그대로 재현한다) ·
--     cost_source 받는 목록에 layer_recent · layer_recent_other_wh · price_history 추가 · inv_post_adjust · inv_layer_apply_adjust_ims 는 반환 · raw.cost 를 통째로 주고받아 무접촉.
--   R4 읽기 창구: inv_adjust_eval 에 칸 넷(fill_qty · layer_qty · layer_unit_cost · cost_from) · cost_branch 에 filled · layer_recent · layer_recent_other_wh · price_history · 돈 칸(layer_unit_cost · cost_from)은 avg_unit_cost 와 같은 문(ims_can_view_cost).
--     반환 칸이 늘어 create or replace 가 안 된다 ⇒ drop → create(부르는 쪽 inv_adjust_confirm · inv_adjust_preview · inv_adjust_detail 은 plpgsql 이라 이름으로 다시 묶인다) · ACL 은 종전과 같게 다시.
--   무접촉: inv_layer_post_sale · inv_layer_post_credit(최근 원가 식이 아직 안에 따로 있다 — 셋을 하나로 모으는 것은 다음 차수 · 이 차수는 시험이 「도우미 = 판매 함수의 결과」를 본다) · inv_post_adjust · inv_adjust_confirm ·
--     inv_layer_apply · inv_layer_apply_adjust_ims · qbo_cost_* · so_stock_short_list · 표 · 제약 · 정책 · 실물 행(쌓인 두 건은 nb-5).

-- ═══ 1) inv_layer_recent_cost — 최근 원가 세 단계 + unknown(새 함수 · inv_layer_post_sale@2026-09-30.2 의 「② 부족분」 else 블록과 같은 식 · 같은 순서 · 같은 source 모양) ═══
create function public.inv_layer_recent_cost(p_sku text, p_warehouse text)
  returns table(unit_cost numeric, cost_source text, step int, source jsonb)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare x record;
begin
  -- ① 같은 SKU×창고 · 마지막으로 세워진 레이어(소진 무관 · received_on desc, id desc) · sale_shortfall 제외(추정의 추정 금지) · 처음 한 병(얹힌 몫 포함 · inv_layer_value.full_unit)
  select y.id, y.doc_number, y.line_ref, y.received_on, y.warehouse, (select v.full_unit from public.inv_layer_value(y.id) v) as unit into x
    from public.inv_layer y where y.sku = p_sku and y.warehouse = p_warehouse and y.origin_type <> 'sale_shortfall'
   order by y.received_on desc, y.id desc limit 1;
  if found then
    return query select x.unit, 'layer_recent'::text, 1, jsonb_build_object('layer_id', x.id, 'doc_number', x.doc_number, 'line_ref', x.line_ref, 'received_on', x.received_on, 'warehouse', x.warehouse);
    return;
  end if;
  -- ② 다른 창고의 마지막 레이어
  select y.id, y.doc_number, y.line_ref, y.received_on, y.warehouse, (select v.full_unit from public.inv_layer_value(y.id) v) as unit into x
    from public.inv_layer y where y.sku = p_sku and y.warehouse <> p_warehouse and y.origin_type <> 'sale_shortfall'
   order by y.received_on desc, y.id desc limit 1;
  if found then
    return query select x.unit, 'layer_recent_other_wh'::text, 2, jsonb_build_object('layer_id', x.id, 'doc_number', x.doc_number, 'line_ref', x.line_ref, 'received_on', x.received_on, 'warehouse', x.warehouse);
    return;
  end if;
  -- ③ 확정 인보이스 가격(po_price_history · CAD · 환율 없으면 null 이라 건너뛴다)
  select h.net_unit_cad, h.invoice_number, h.invoice_date, h.supplier_name into x
    from public.po_price_history h where h.sku = p_sku and h.net_unit_cad is not null
   order by h.invoice_date desc, h.invoice_number desc limit 1;
  if found then
    return query select x.net_unit_cad, 'price_history'::text, 3, jsonb_build_object('invoice_number', x.invoice_number, 'invoice_date', x.invoice_date, 'supplier_name', x.supplier_name);
    return;
  end if;
  -- ④ 모른다 — 0 · 표시가 남는다
  return query select 0::numeric, 'unknown'::text, 4, null::jsonb;
end;
$$;
revoke all on function public.inv_layer_recent_cost(text, text) from public, anon, authenticated;
comment on function public.inv_layer_recent_cost(text, text) is 'nb-1(2026-11-11 · 판정 1171) 최근 원가 — ① 이 창고 마지막 레이어 → ② 다른 창고 마지막 레이어 → ③ 확정 인보이스 가격(po_price_history · CAD) → ④ unknown 0 · sale_shortfall 레이어는 원천에서 뺀다 · 한 줄(unit_cost · cost_source · step 1 ~ 4 · source) · inv_layer_post_sale 의 부족분 블록과 같은 식(그 함수 · inv_layer_post_credit 은 아직 안에 따로 갖고 있다) · 부르는 곳 inv_layer_post_adjust · inv_adjust_eval(둘 다 definer) · authenticated 없음';

-- ═══ 2) inv_layer_post_adjust — 원본 20260930144905_cogs_2_cost_split.sql:1425 ~ 1458 바이트 그대로 + 메우기(R1) · 최근 원가(R2) · hint(R3) ═══
create or replace function public.inv_layer_post_adjust(p_doc_number text, p_line_ref text, p_sku text, p_warehouse text, p_qty numeric, p_occurred_on date, p_unit_cost numeric, p_hint jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_layer_post_adjust@2026-11-11.1';   -- nb-1(판정 1170 · 1171): 메우기 · 최근 원가 · hint 넓힘
        v_hint jsonb := case when p_hint is not null and jsonb_typeof(p_hint) = 'object' then p_hint else null end;
        v_unit numeric; v_src text; v_origin text; v_id bigint; v_rem numeric; v_remval numeric; v_rows int; v_short int; v_layers int; v_taken numeric; v_amt numeric;
        v_fill numeric := 0; v_lay numeric; v_led numeric; v_qty numeric; v_step int; v_source jsonb;   -- nb-1
begin
  if p_qty is null or p_qty = 0 then return jsonb_build_object('qty', p_qty, 'branch', 'none', 'builder', c_version); end if;
  if exists (select 1 from public.inv_layer y where y.origin_type in ('adjust_existing', 'adjust_new') and y.doc_number = p_doc_number and y.line_ref = p_line_ref)
     or exists (select 1 from public.inv_layer_consume c where c.doc_type = 'adjustment' and c.doc_number = p_doc_number and c.line_ref = p_line_ref) then
    raise exception 'Adjustment % line % was already costed — nothing was saved', p_doc_number, p_line_ref;
  end if;
  if p_qty < 0 then                                                                         -- − = FIFO 소진(Cin7 축 A-3 과 같은 reason adjust_out)
    select * into v_rows, v_short, v_layers, v_taken
      from public.inv_layer_fifo_take(p_sku, p_warehouse, -p_qty, 'adjustment', p_doc_number, p_line_ref, 'adjust_existing', p_occurred_on, 'adjust_out', null);
    select coalesce(sum(c.amount), 0) into v_amt from public.inv_layer_consume c where c.doc_type = 'adjustment' and c.doc_number = p_doc_number and c.line_ref = p_line_ref;
    return jsonb_build_object('qty', p_qty, 'branch', 'fifo', 'consume_rows', v_rows, 'layers', v_layers, 'taken', v_taken, 'short', v_short, 'amount', v_amt, 'builder', c_version);
  end if;
  -- nb-1 R1 메우기(판정 1170): 이 SKU × 창고의 레이어 남은 수량이 장부 수량보다 많은 만큼(= 재고 없이 팔려 판매 때 이미 원가를 잡은 몫)은 새 레이어를 세우지 않는다 · 창고 단위(레이어가 창고 단위다 · 칸 · 칸 없음은 합친다)
  if v_hint is not null then                                                                -- 재생성 = 실시간이 적어 둔 수량 그대로(다시 세지 않는다 · 옛 행은 열쇠가 없다 = 0)
    v_fill := coalesce(nullif(v_hint->>'fill_qty', '')::numeric, 0);
    if v_fill < 0 or v_fill > p_qty then
      raise exception 'Fill hint (%) does not fit the adjustment quantity (%) for % / % on % — the ledger raw is wrong, not this function — nothing was saved', v_fill, p_qty, p_sku, p_warehouse, p_doc_number;
    end if;
  else
    perform pg_advisory_xact_lock(hashtextextended('inv_layer_fill:' || p_sku || '|' || p_warehouse, 0));   -- 같은 SKU × 창고의 + 조정 둘이 같은 부족분을 함께 메우지 않게(트랜잭션 끝까지)
    select coalesce(sum(v.remaining_qty), 0) into v_lay
      from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = p_sku and y.warehouse = p_warehouse;
    select coalesce(sum(b.qty), 0) into v_led from public.inv_balance b where b.sku = p_sku and b.warehouse = p_warehouse;   -- 이 줄의 원장 행은 아직 없다(inv_post_adjust 는 레이어 먼저) · 같은 문서의 앞 줄은 들어 있다
    v_fill := least(p_qty, greatest(v_lay - v_led, 0));
  end if;
  v_qty := p_qty - v_fill;
  if v_qty = 0 then                                                                         -- 전부 메움 = 레이어 · 소진 행 없음(하루 원가 장에 쓸 것이 없다 · 판정 1094 가 판매 때 적었다)
    return jsonb_build_object('qty', p_qty, 'branch', 'filled', 'fill_qty', v_fill, 'layer_qty', 0, 'amount', 0,
                              'fill', case when v_hint is null then jsonb_build_object('layer_remaining', v_lay, 'ledger', v_led) end, 'reproduced', v_hint is not null, 'builder', c_version);
  end if;
  if p_unit_cost is not null then                                                           -- + 단가 있음 = 새 재고(manual)
    v_unit := p_unit_cost; v_src := 'manual'; v_origin := 'adjust_new';
  elsif v_hint is not null and nullif(v_hint->>'unit_cost', '') is not null and (v_hint->>'cost_source') in ('layer_avg', 'unknown', 'layer_recent', 'layer_recent_other_wh', 'price_history') then
    v_unit := (v_hint->>'unit_cost')::numeric; v_src := v_hint->>'cost_source'; v_origin := 'adjust_existing';   -- 재생성 hint = 실시간과 같은 값
    v_step := nullif(v_hint->>'step', '')::int; v_source := v_hint->'source';
  else                                                                                      -- + 단가 없음 = 남은 레이어 가중평균(없으면 최근 원가 → unknown 0 · nb-1 판정 1171)
    select coalesce(sum(v.remaining_qty), 0), coalesce(sum(v.remaining_value), 0) into v_rem, v_remval     -- cogs-2(판정 111): 남은 가치 ÷ 남은 수량(얹힌 몫 포함) · 식은 inv_layer_value 하나
      from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = p_sku and y.warehouse = p_warehouse and v.remaining_qty > 0;
    if v_rem > 0 then v_unit := round(v_remval / v_rem, 6); v_src := 'layer_avg'; v_step := 2; v_source := jsonb_build_object('remaining_qty', v_rem, 'remaining_value', v_remval);
    else select rc.unit_cost, rc.cost_source, rc.step + 2, rc.source into v_unit, v_src, v_step, v_source from public.inv_layer_recent_cost(p_sku, p_warehouse) rc;   -- nb-1(판정 1171): ③ 최근 원가(판매 부족분과 같은 순서 · step 3 ~ 5) → ④ unknown 0(step 6) — step 번호는 inv_layer_post_credit 과 같다
    end if;
    v_origin := 'adjust_existing';
  end if;
  insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
  values (p_sku, p_warehouse, v_origin, p_doc_number, p_line_ref, null, p_occurred_on, true, v_qty, v_unit, v_src) returning id into v_id;
  return jsonb_build_object('qty', p_qty, 'branch', v_src, 'origin_type', v_origin, 'layer_id', v_id, 'unit_cost', v_unit, 'cost_source', v_src, 'amount', round(v_qty * v_unit, 6), 'reproduced', v_hint is not null, 'builder', c_version)
         || jsonb_build_object('fill_qty', v_fill, 'layer_qty', v_qty, 'step', v_step, 'source', v_source, 'fill', case when v_hint is null then jsonb_build_object('layer_remaining', v_lay, 'ledger', v_led) end);   -- nb-1: 재생성 hint(R3)
end;
$$;
revoke all on function public.inv_layer_post_adjust(text, text, text, text, numeric, date, numeric, jsonb) from public, anon, authenticated;
comment on function public.inv_layer_post_adjust(text, text, text, text, numeric, date, numeric, jsonb) is '재고 조정 한 줄의 원가 레이어 창구(묶음 11 · IMS 축) — − = FIFO 소진(adjust_out) · + = ⭐ nb-1(판정 1170): 레이어 남은 수량이 장부 수량보다 많은 만큼은 메움(레이어를 세우지 않는다 · 재고 없이 판 몫은 판매 때 원가를 잡았다) · 남는 몫만 레이어 — 단가 있으면 manual(adjust_new) · 없으면 남은 레이어 가중평균 → 최근 원가(inv_layer_recent_cost · 판정 1171) → unknown 0(adjust_existing) · 반환 = raw.cost = 재생성 hint(fill_qty · layer_qty · unit_cost · cost_source · step · source) · hint 가 있으면 다시 세지 않는다 · inv_post_adjust · inv_layer_apply_adjust_ims 만 부른다';

-- ═══ 3) inv_adjust_eval — 원본 20261021131845_rls_3b_cost_read_gate.sql:167 ~ 195 바이트 그대로 + 칸 넷 · 메움 · 최근 원가(R4) · 반환 칸이 늘어 drop → create ═══
drop function public.inv_adjust_eval(uuid);
CREATE FUNCTION public.inv_adjust_eval(p_adjust_id uuid)
 RETURNS TABLE(line_id uuid, line_no integer, product_id uuid, sku text, bin_id uuid, bin text, mode text, qty_input numeric, reason text, reason_note text, unit_cost numeric, seen_ledger numeric, seen_picked numeric, ledger numeric, picked numeric, basis numeric, delta numeric, result numeric, cost_branch text, avg_unit_cost numeric, rejects text[], fill_qty numeric, layer_qty numeric, layer_unit_cost numeric, cost_from jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER   -- rls-3b
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.ims_require_ok(public.ims_can_adjust_read(), 'You cannot view stock adjustments — this needs the stock_adjust key — nothing was read');   -- rls-3b(판정 582): 첫 줄 문 = inv_adjust 의 select 정책과 같은 열쇠 · definer 라 표 정책을 지나므로 여기서 거른다(sql 함수 — 도우미가 raise)
  with h as (select a.warehouse, a.warehouse_id from public.inv_adjust a where a.id = p_adjust_id),
  x as materialized (                                                                     -- adj-a2(판정 54 B): 줄마다 장부 · P · avg · 칸을 한 번만 — 인라인된 식이 참조 자리마다 다시 돌던 것(≈13회/줄)을 막는다
    select l.*, public.inv_adjust_ledger(h.warehouse, l.bin, l.sku) as ledger, public.inv_adjust_picked(h.warehouse_id, l.bin_id, l.product_id) as picked,
           (select coalesce(sum(v.remaining_value) / nullif(sum(v.remaining_qty), 0), null)                   -- cogs-2(판정 111): 남은 가치 ÷ 남은 수량 · 식은 inv_layer_value 하나
              from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = l.sku and y.warehouse = h.warehouse and v.remaining_qty > 0) as avg_cost,
           (select b.is_active and b.warehouse_id = h.warehouse_id from public.ref_bin b where b.id = l.bin_id) as bin_ok,
           h.warehouse as wh_name,                                                                             -- nb-1
           (select coalesce(sum(v.remaining_qty), 0) from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = l.sku and y.warehouse = h.warehouse)
             - (select coalesce(sum(b.qty), 0) from public.inv_balance b where b.sku = l.sku and b.warehouse = h.warehouse) as gap   -- nb-1(판정 1170): 레이어 남은 수량 − 장부 수량(창고 단위) = 메울 수 있는 몫
      from public.inv_adjust_line l, h where l.adjust_id = p_adjust_id
  ),
  y as (select x.*, x.ledger - x.picked as basis, case when x.mode = 'set' then x.qty_input - (x.ledger - x.picked) else x.qty_input end as d from x),
  z as (select y.*, case when y.d > 0 then greatest(least(y.d, greatest(y.gap, 0)                              -- nb-1: 같은 문서 · 같은 SKU 의 앞 + 줄이 먼저 메운다(줄 번호 순 · 확정이 도는 순서) — 미리 보기 · 확정(inv_layer_post_adjust)이 다시 센다
                        - coalesce(sum(case when y.d > 0 then y.d else 0 end) over (partition by y.sku order by y.line_no rows between unbounded preceding and 1 preceding), 0)), 0) else 0 end as fill from y),
  w as (select z.*, rc.unit_cost as rc_unit, rc.cost_source as rc_src, rc.source as rc_source                  -- nb-1(판정 1171): 단가 비움 · 남은 레이어 없음 · 레이어로 설 몫이 있을 때만 최근 원가
          from z left join lateral public.inv_layer_recent_cost(z.sku, z.wh_name) rc on z.d > z.fill and z.unit_cost is null and z.avg_cost is null)
  select y.id, y.line_no, y.product_id, y.sku, y.bin_id, y.bin, y.mode, y.qty_input, y.reason, y.reason_note, y.unit_cost,
         y.seen_ledger, y.seen_picked, y.ledger, y.picked, y.basis, y.d, y.ledger + y.d,
         case when y.d > 0 and y.fill >= y.d then 'filled' when y.d > 0 and y.unit_cost is not null then 'manual' when y.d > 0 and y.avg_cost is not null then 'layer_avg'
              when y.d > 0 then coalesce(y.rc_src, 'unknown') when y.d < 0 then 'fifo' else 'none' end,
         case when (select public.ims_can_view_cost()) then round(y.avg_cost, 6) end,   -- rls-3b(판정 580): avg_unit_cost 값만 열쇠로 · 방법 칸(layer_avg · unknown)은 위에서 실제 avg 로 정한다 · 확정(inv_layer_post_adjust)은 레이어에서 다시 센다
         array_remove(array[
           case when y.ledger + y.d < 0 then format('line %s %s %s: result would be %s (below zero)', y.line_no, y.sku, y.bin, y.ledger + y.d) end,
           case when y.ledger <> y.seen_ledger then format('line %s %s %s: ledger changed (you saw %s, it is now %s)', y.line_no, y.sku, y.bin, y.seen_ledger, y.ledger) end,
           case when y.picked <> y.seen_picked then format('line %s %s %s: picked-not-shipped changed (you saw %s, it is now %s)', y.line_no, y.sku, y.bin, y.seen_picked, y.picked) end,
           case when not coalesce(y.bin_ok, false) then format('line %s: bin %s is inactive or not in this warehouse', y.line_no, y.bin) end
         ], null),
         y.fill, case when y.d > 0 then y.d - y.fill else 0 end,                                               -- nb-1: 메움 수량 · 새 레이어 수량(수량은 열쇠와 무관)
         case when (select public.ims_can_view_cost()) and y.d > y.fill then                                   -- nb-1(판정 580 과 같은 문): 새 레이어의 단가 — 원가 열쇠가 없으면 null(갈래 이름만)
                case when y.unit_cost is not null then y.unit_cost when y.avg_cost is not null then round(y.avg_cost, 6) else coalesce(y.rc_unit, 0) end end,
         case when (select public.ims_can_view_cost()) and y.d > y.fill and y.unit_cost is null and y.avg_cost is null then y.rc_source end   -- nb-1: 최근 원가의 출처(다른 창고 이름 · 인보이스 번호 · 날짜) — 같은 문
    from w y order by y.line_no;

$function$;
revoke all on function public.inv_adjust_eval(uuid) from public, anon;   grant execute on function public.inv_adjust_eval(uuid) to authenticated;
comment on function public.inv_adjust_eval(uuid) is '재고 조정 줄마다 지금 값으로 다시 읽기(미리 보기 · 확정 판정 · 화면 stock-adjustments) — 장부 · 픽만 한 수량 · delta · 결과 · 거부 사유 · cost_branch(filled · manual · layer_avg · layer_recent · layer_recent_other_wh · price_history · unknown · fifo · none) · ⭐ nb-1(판정 1170 · 1171): fill_qty(메움 — 레이어를 세우지 않는 몫) · layer_qty(새 레이어 수량) · layer_unit_cost · cost_from(돈 칸 — avg_unit_cost 와 같은 문 ims_can_view_cost · 없으면 null) · 첫 줄 문 ims_can_adjust_read · definer(rls-3b)';

-- ═══ 착지 — 새 함수 · 재발행 둘이 선 모양 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_layer_recent_cost' and p.prosecdef) <> 1 then v_bad := v_bad || ' · inv_layer_recent_cost missing'; end if;
  if has_function_privilege('authenticated', 'public.inv_layer_recent_cost(text, text)', 'execute') or has_function_privilege('anon', 'public.inv_layer_recent_cost(text, text)', 'execute') then v_bad := v_bad || ' · inv_layer_recent_cost is callable by staff'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_layer_post_adjust' and p.prosrc ~ 'inv_layer_post_adjust@2026-11-11\.1' and p.prosrc ~ 'inv_layer_recent_cost' and p.prosecdef) <> 1 then v_bad := v_bad || ' · inv_layer_post_adjust not republished'; end if;
  if has_function_privilege('authenticated', 'public.inv_layer_post_adjust(text, text, text, text, numeric, date, numeric, jsonb)', 'execute') then v_bad := v_bad || ' · inv_layer_post_adjust is callable by staff'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_adjust_eval' and p.prosecdef
        and p.prosrc ~ 'ims_require_ok\(public\.ims_can_adjust_read\(\)' and p.prosrc ~ 'ims_can_view_cost\(\)\) then round\(y\.avg_cost, 6\)'       -- rls-3b 의 착지 둘 그대로
        and pg_get_function_result(p.oid) ~ 'fill_qty numeric, layer_qty numeric, layer_unit_cost numeric, cost_from jsonb\)$') <> 1 then v_bad := v_bad || ' · inv_adjust_eval not republished'; end if;
  if not has_function_privilege('authenticated', 'public.inv_adjust_eval(uuid)', 'execute') or has_function_privilege('anon', 'public.inv_adjust_eval(uuid)', 'execute') then v_bad := v_bad || ' · inv_adjust_eval grants are wrong'; end if;
  if v_bad <> '' then raise exception 'nb-1 landing check failed:% — nothing was changed', v_bad; end if;
end $$;
