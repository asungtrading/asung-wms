-- surcharge-2a — SO 관세 부가 요금(surcharge): 계산 한 곳 · 합계 · 세금 · 견적서 · 줄 고치기 · Finalize (2026-10-02 UTC · 판정 227 ~ 230 · surcharge 묶음 1 ~ 8 · surcharge-2 묶음 1 ~ 9 · so-module §36 · 조사 surcharge-1)
--   판정 228  무상 줄(free_reason · 단가 0)에는 surcharge 를 막는다(% · 금액 모두 · 창구 거부 · 영어 문장) · 조용히 0 으로 계산하지 않는다
--   판정 229  같은 SKU 를 더하면 있는 줄에 합치고 더한 수량은 그 줄의 surcharge 를 물려받는다 — so_line_add 는 지금 동작 그대로(고치지 않는다 · 검증 A 가 증명)
--   판정 230  surcharge 는 초안 + Finalize(packed · so_finalize · 운임과 같은 자리)에서 고친다 · shipped 뒤는 열지 않는다(인보이스 취소 → 재발행)
--   묶음 1    % 의 바탕은 so_line.unit_price(할인 뒤 · 덮어쓴 값이면 그 값) / 묶음 2 반올림은 개당 먼저 — 개당 = round(금액 또는 단가 × %, 2) · 줄 = 개당 × 수량 · 금액 입력은 센트 두 자리까지(넘으면 거부 · 자르지 않음)
--             대가: %형이면 줄 전체로 한 번에 계산할 때보다 최대 「수량 × 0.5센트」 적게 나올 수 있다 · 대신 백오더로 나뉘어도 두 쪽 합이 늘 원래와 같다
--   묶음 3    surcharge 는 물건값(amount · lines_amount)에 섞지 않고 따로 센다 — 오더 할인 기준 · 리스탁킹 피 기준 밖(9/21 근거 · 정부에 내는 돈)
--   묶음 4    세금은 줄마다 so_tax_amount(surcharge 줄 합, 오더 세율) 따로 반올림 · 세율은 오더 것 하나(판정 8 · manual 포함) · 회계사가 안 붙는다 하면 so_tax_preview 의 v_sc_rate 한 줄을 0 으로(36-e 76)
--   Caleb 확인  % 위 한계 CHECK 없음(2025 관세 100% 초과 실물) · 100 초과는 알리기 surcharge_pct_over_100(화면이 확인을 묻는다)
--   무접촉    인보이스 · 크레딧 · 머리 칸 · 계정 설정(2b) · 화면(surcharge-3) · so_line_total · so_tax_amount · so_order_discount · so_split · so_line_add · so_lines_paste
--   ⚠️ 2a 와 2b 사이: so_invoice_issue 는 so_tax_preview 의 totals.tax(이제 surcharge 세금 포함)를 읽고 lines·charges 만 줄로 담는다 — 그 사이 surcharge 오더를 발행하면 세금만 들어가고 금액은 빠진다(테스트 DB 뿐 · 2b 가 닫는다)
--
-- ① 계산 한 곳 — so_line_surcharge_unit(단가, %, 금액) · so_line_surcharge_total(개당, 수량) immutable · so_surcharge_check(%, 금액, 이름, 무상 사유) — 짝 · 범위 · 무상 금지 문장 한 곳(so_line_update · so_finalize 가 부른다)
-- ② so_line CHECK 셋 — surcharge_pct > 0 · surcharge_amount > 0 이고 센트 두 자리 · 무상 ↔ surcharge 금지(free_reason ⇔ unit_price = 0 은 so_line_free_pair_ck 가 이미 묶는다) · 기존 so_line_surcharge_ck · so_line_surcharge_label_ck 그대로 · S1 실측 21 줄 surcharge 0 이라 바로 건다
-- ③ so_tax_preview 재발행(마지막 정의 20260924200029:471 바이트 그대로 + surcharge 자리) — 줄 객체 넷(surcharge_label · surcharge_unit · surcharge_total · surcharge_tax) · totals 둘(surcharge_amount · surcharge_tax) · taxable_amount · tax · total 에 포함 · lines_amount · order_discount 무변
-- ④ so_detail 재발행(20260925014413:627) — 줄 셋(surcharge_unit · surcharge_total · shipped_surcharge_total) · totals 둘 · order_total · order_total_with_tax 에 포함 · 오더 할인 기준(lines_total) 무변
-- ⑤ so_proforma 재발행(20260925201614:259) — totals.surcharge_amount · taxable_amount · total · balance_due 에 포함(세금은 so_tax_preview tax 가 이미 들고 온다)
-- ⑥ so_line_update 재발행(20260924175014:609) — 짝 검사 아홉 줄 → so_surcharge_check 한 줄 · 알리기 surcharge_pct_over_100 · 반환에 surcharge_unit · surcharge_total
-- ⑦ so_finalize 재발행(20260926204246:259) — 오더 객체에 surcharges [{line_id, surcharge_pct?, surcharge_amount?, surcharge_label?}](so_line_update 와 같은 패치 모양) · ① 검사(줄 · 짝·범위·무상 · 중복) · ②′ 실행이면 쓰고 미리 보기면 old → new · 반환 orders[].surcharges
--   검증: ~/asung/prompts/surcharge-2a-verify.sql (시험 적용 장치 · 테스트 DB · rollback · 시퀀스 setval) · ⚠️ 운영 무접촉(컷오버 전 운영 적용 금지 · ims-principles)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 의 바이트 복사 — 운영에서는 멈춘다
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

-- ═══ ① 계산 한 곳 — 개당 · 줄 합 · 막기 문장 ═══════════════════════════════════════════════════════════════════════════════
create function public.so_line_surcharge_unit(p_unit_price numeric, p_pct numeric, p_amount numeric) returns numeric
  language sql immutable
  set search_path = public, pg_temp
as $$
  select coalesce(round(coalesce(p_amount, p_unit_price * p_pct / 100), 2), 0);
$$;
revoke all on function public.so_line_surcharge_unit(numeric, numeric, numeric) from public, anon;
grant execute on function public.so_line_surcharge_unit(numeric, numeric, numeric) to authenticated;
comment on function public.so_line_surcharge_unit(numeric, numeric, numeric) is
  '⭐ surcharge 개당(surcharge-2a · 묶음 1 · 2) — round(coalesce(금액, 단가 × %/100), 2) · 금액형은 개당 입력 그대로(센트) · %형은 할인 뒤 단가(so_line.unit_price · 덮어쓴 값이면 그 값)에서 센트로 한 번 · 둘 다 null 또는 단가 null(가격 없음)이면 0 · 저장 없음 — so_tax_preview · so_detail · so_line_update · so_finalize 가 전부 이것을 부른다';

create function public.so_line_surcharge_total(p_unit numeric, p_qty numeric) returns numeric
  language sql immutable
  set search_path = public, pg_temp
as $$
  select round(coalesce(p_unit, 0) * coalesce(p_qty, 0), 2);
$$;
revoke all on function public.so_line_surcharge_total(numeric, numeric) from public, anon;
grant execute on function public.so_line_surcharge_total(numeric, numeric) to authenticated;
comment on function public.so_line_surcharge_total(numeric, numeric) is
  '⭐ surcharge 줄 합(surcharge-2a · 묶음 2) — 개당(so_line_surcharge_unit) × 수량 · 수량은 물건값과 같은 것(초안 · 확정 qty_ordered · 보낸 뒤 qty_shipped · so_tax_preview 의 basis) · 개당이 센트라 백오더로 나뉘어도 두 쪽 합 = 원래(2.49 · 5% · 2 → 0.12 × 2 = 0.24 = 0.12 + 0.12 · 줄 전체 식이면 0.25 ≠ 0.24)';

create function public.so_surcharge_check(p_pct numeric, p_amount numeric, p_label text, p_free_reason text) returns void
  language plpgsql immutable
  set search_path = public, pg_temp
as $$
begin
  if p_pct is not null and p_amount is not null then
    raise exception 'Use either a surcharge percent or an amount, not both — nothing was saved';
  end if;
  if p_label is not null and p_pct is null and p_amount is null then
    raise exception 'A surcharge needs a percent or an amount — nothing was saved';
  end if;
  if p_label is null and (p_pct is not null or p_amount is not null) then
    raise exception 'A surcharge needs a label — nothing was saved';
  end if;
  if p_pct is not null and p_pct <= 0 then
    raise exception 'Surcharge percent must be greater than 0 — nothing was saved';
  end if;
  if p_amount is not null and p_amount <= 0 then
    raise exception 'Surcharge amount must be greater than 0 — nothing was saved';
  end if;
  if p_amount is not null and p_amount <> round(p_amount, 2) then
    raise exception 'Surcharge amount is per unit, in cents (2 decimals) — nothing was saved';
  end if;
  if p_free_reason is not null and p_label is not null then
    raise exception 'A free line cannot carry a surcharge — nothing was saved';
  end if;
end;
$$;
revoke all on function public.so_surcharge_check(numeric, numeric, text, text) from public, anon;
grant execute on function public.so_surcharge_check(numeric, numeric, text, text) to authenticated;
comment on function public.so_surcharge_check(numeric, numeric, text, text) is
  '⭐ surcharge 막기 문장 한 곳(surcharge-2a · 판정 7 · 228) — 짝(% 와 금액 둘 중 하나 · 이름 ↔ 값) · 범위(% > 0 · 위 한계 없음 — Caleb 확인 · 100 초과는 창구가 알리기 surcharge_pct_over_100 / 금액 > 0 · 센트 두 자리 — 넘으면 자르지 않고 거부) · 무상 줄(free_reason) 금지(판정 228 · 양방향) · so_line_update(초안) · so_finalize(packed · 판정 230) 가 부른다 · CHECK 셋이 마지막 문';

-- ═══ ② so_line CHECK 셋 — 창구 밖(직접 쓰기)도 막는다 · S1 실측 21 줄 surcharge 0 ═══════════════════════════════════════════
alter table public.so_line
  add constraint so_line_surcharge_pct_ck    check (surcharge_pct is null or surcharge_pct > 0),
  add constraint so_line_surcharge_amount_ck check (surcharge_amount is null or (surcharge_amount > 0 and surcharge_amount = round(surcharge_amount, 2))),
  add constraint so_line_surcharge_free_ck   check (free_reason is null or surcharge_label is null);
comment on constraint so_line_surcharge_pct_ck    on public.so_line is 'surcharge-2a — % 는 0 보다 크다 · 위 한계 없음(Caleb 확인 · 2025 관세 100% 초과 실물 · 100 초과는 창구 알리기 surcharge_pct_over_100)';
comment on constraint so_line_surcharge_amount_ck on public.so_line is 'surcharge-2a(묶음 2) — 금액은 개당 · 0 보다 크다 · 센트 두 자리(round(amount, 2) 와 같다 — 창구는 넘으면 자르지 않고 거부)';
comment on constraint so_line_surcharge_free_ck   on public.so_line is 'surcharge-2a(판정 228) — 무상 줄(free_reason · so_line_free_pair_ck 로 unit_price = 0 과 묶여 있다)에는 surcharge 가 없다 · 양방향(무상에 surcharge · surcharge 줄을 무상으로) · 창구 문장 「A free line cannot carry a surcharge」';
comment on column public.so_line.surcharge_pct    is '⭐ 부가(보복 관세 등 · Caleb 2026-09-21 · 5-e) — 한시적이라 가격을 올리지 않는다 · surcharge_amount 와 둘 중 하나만(CHECK so_line_surcharge_ck) · 둘 다 비면 없는 것 · ⚠️ so_charge 와 다른 자리 — 특정 제품에 붙는다(운임은 오더에 한 번) · [surcharge-2a] 바탕은 unit_price(할인 뒤) · 개당 = round(unit_price × %/100, 2)(so_line_surcharge_unit) · > 0 · 위 한계 없음';
comment on column public.so_line.surcharge_amount is '부가 금액 · surcharge_pct 와 둘 중 하나만(CHECK) · 우리 마진이 아니라 정부에 내는 돈 — 매출 분석에서 가른다(5-e) · [surcharge-2a · 묶음 1 · 2] ⭐ 개당 · 센트 두 자리 · > 0(CHECK so_line_surcharge_amount_ck) · 줄 합 = 개당 × 수량(so_line_surcharge_total)';
comment on column public.so_line.surcharge_label  is '부가 이름(예 US Tariff) — 몇 년 뒤 「이게 무엇이었나」를 알 수 있어야 한다(5-e) · [surcharge-2a] 무상 줄에는 없다(CHECK so_line_surcharge_free_ck · 판정 228)';

-- ═══ ③ so_tax_preview 재발행 — 마지막 정의 20260924200029_so_invoice_a1.sql:471~541 바이트 그대로 + surcharge 자리(선언 1 · v_sc_rate 1 · 줄 select 7 · totals 4 · create or replace) ═══
create or replace function public.so_tax_preview(p_so_id uuid, p_on date default null, p_rule_id uuid default null, p_basis text default 'ordered') returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so     public.so%rowtype;
  v_on     date := coalesce(p_on, public.ims_today());
  v_pick   jsonb;
  v_rate   numeric;
  v_rule   text;
  v_source text;
  v_active boolean;                                           -- 세금 ② — 오더에 굳은 규칙이 비활성이 됐나
  v_lines  jsonb;  v_lines_tax numeric;  v_lines_amt numeric;
  v_chg    jsonb;  v_chg_tax numeric;    v_chg_amt numeric;
  v_od_amt numeric := 0;  v_od_tax numeric := 0;
  v_sc_amt numeric := 0;  v_sc_tax numeric := 0;  v_sc_rate numeric;                      -- surcharge-2a(묶음 3 · 4): 줄마다 surcharge 합 · 그 세금 · surcharge 에 매길 세율
  v_warn   jsonb := '[]'::jsonb;
begin
  if p_basis not in ('ordered', 'shipped') then raise exception 'p_basis must be ordered or shipped'; end if;   -- ⓐ1 이견 4 — 인보이스는 보낸 수량(qty_shipped) 기준 · 초안·확정은 주문 수량
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found'; end if;

  if p_rule_id is not null then
    select r.name, r.rate_pct into v_rule, v_rate from public.ref_tax_rule r where r.id = p_rule_id and r.is_active and r.direction = 'sale';
    if v_rule is null then raise exception 'Tax rule % is not an active selling rule', p_rule_id; end if;
    v_source := 'explicit';
    v_pick := jsonb_build_object('rule_id', p_rule_id, 'rule', v_rule, 'rate_pct', v_rate, 'on', v_on);
  elsif v_so.tax_rule_id is not null then                                              -- 세금 ② — 오더에 고른 규칙을 먼저(배송지에서 고른 것 ship_to · 사람이 정한 것 manual · 판정 8)
    select r.name, r.rate_pct, r.is_active into v_rule, v_rate, v_active from public.ref_tax_rule r where r.id = v_so.tax_rule_id;
    v_source := case when v_so.tax_rule_manual then 'manual' else 'ship_to' end;
    v_pick := jsonb_build_object('rule_id', v_so.tax_rule_id, 'rule', v_rule, 'rate_pct', v_rate, 'on', v_on, 'manual', v_so.tax_rule_manual);
    if not v_active then v_warn := '["tax_rule_inactive"]'::jsonb; end if;
  else                                                                                 -- 규칙이 없는 초안(배송지 모름) — 지금 배송지로 다시 골라 보고 경고를 그대로 낸다
    v_pick := public.so_tax_rule_for(v_so.ship_to_country, v_so.ship_to_state_province, v_on, 'sale');
    v_rate := (v_pick->>'rate_pct')::numeric;  v_rule := v_pick->>'rule';
    v_source := 'ship_to';
    v_warn := coalesce(v_pick->'warnings', '[]'::jsonb);
  end if;

  v_sc_rate := v_rate;                                                                 -- ⭐ 36-e 76 — 회계사가 「surcharge 에 세금이 안 붙는다」 하면 이 줄 하나를 0 으로(surcharge 세금의 유일한 자리 · 묶음 4)
  select coalesce(jsonb_agg(jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'amount', a.amt, 'tax', public.so_tax_amount(a.amt, v_rate), 'free', l.free_reason is not null,
                                              'line_id', l.id, 'product_id', l.product_id, 'product_name', l.product_name, 'unit', l.unit, 'pack_factor', l.pack_factor,
                                              'qty', a.qty, 'qty_ordered', l.qty_ordered, 'qty_shipped', l.qty_shipped, 'unit_price', l.unit_price, 'list_price', l.list_price,
                                              'discount_pct', l.discount_pct, 'discount_source', l.discount_source, 'price_override', l.price_override,
                                              'surcharge_label', l.surcharge_label, 'surcharge_unit', a.sc_unit, 'surcharge_total', s.sc_amt, 'surcharge_tax', public.so_tax_amount(s.sc_amt, v_sc_rate)) order by l.line_no), '[]'::jsonb),   -- surcharge-2a(묶음 4): 줄마다 따로 반올림
         coalesce(sum(public.so_tax_amount(a.amt, v_rate)), 0), coalesce(sum(a.amt), 0),
         coalesce(sum(s.sc_amt), 0), coalesce(sum(public.so_tax_amount(s.sc_amt, v_sc_rate)), 0)
    into v_lines, v_lines_tax, v_lines_amt, v_sc_amt, v_sc_tax
  from public.so_line l
  cross join lateral (select case when p_basis = 'shipped' then l.qty_shipped else l.qty_ordered end as qty,
                             case when p_basis = 'shipped' then round(l.qty_shipped * l.unit_price, 2) else public.so_line_total(l) end as amt,   -- ⓐ1: 보낸 수량 기준은 round(qty_shipped × unit_price, 2)(so_line_total 과 같은 식 · 수량만 다르다)
                             public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount) as sc_unit) a                      -- surcharge-2a(묶음 1 · 2): 개당(센트) · 수량은 물건값(amt)과 같은 것
  cross join lateral (select public.so_line_surcharge_total(a.sc_unit, a.qty) as sc_amt) s
  where l.so_id = p_so_id;

  if coalesce(v_so.order_discount_pct, 0) > 0 then                                  -- 오더 전체 할인은 제품 줄 합계에 한 번(D6 · 운임 제외) · 세금은 그 줄에 따로(판정 3 · SO-10842 −23.12)
    v_od_amt := -round(v_lines_amt * v_so.order_discount_pct / 100, 2);
    v_od_tax := public.so_tax_amount(v_od_amt, v_rate);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('line_no', c.line_no, 'name', c.name, 'amount', c.amount, 'tax', public.so_tax_amount(c.amount, v_rate),
                                              'charge_id', c.id, 'description', c.description, 'account_id', c.account_id, 'account_code', c.account_code) order by c.line_no), '[]'::jsonb),
         coalesce(sum(public.so_tax_amount(c.amount, v_rate)), 0), coalesce(sum(c.amount), 0)
    into v_chg, v_chg_tax, v_chg_amt
  from public.so_charge c where c.so_id = p_so_id;                                  -- 운임도 배송지 주의 규칙 · 줄마다(판정 6)

  return jsonb_build_object(
    'so_number', v_so.so_number, 'on', v_on, 'basis', p_basis, 'source', v_source, 'rule', v_pick,
    'lines', v_lines, 'order_discount', jsonb_build_object('pct', v_so.order_discount_pct, 'amount', v_od_amt, 'tax', v_od_tax), 'charges', v_chg,
    'totals', jsonb_build_object('lines_amount', v_lines_amt, 'lines_tax', v_lines_tax, 'order_discount_amount', v_od_amt, 'order_discount_tax', v_od_tax,
                                 'charges_amount', v_chg_amt, 'charges_tax', v_chg_tax,
                                 'surcharge_amount', v_sc_amt, 'surcharge_tax', v_sc_tax,                                                     -- surcharge-2a(묶음 3): 물건값(lines_amount)과 따로 · 오더 할인 기준 밖
                                 'taxable_amount', v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt,
                                 'tax', case when v_rate is null then null else v_lines_tax + v_od_tax + v_chg_tax + v_sc_tax end,
                                 'total', case when v_rate is null then null else v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt + v_lines_tax + v_od_tax + v_chg_tax + v_sc_tax end),
    'warnings', v_warn);
end;
$$;

-- ═══ ④ so_detail 재발행 — 마지막 정의 20260925014413_so_credit_c2.sql:627~710 바이트 그대로 + surcharge 자리(선언 1 · 줄 1 · totals 읽기 1 · 반환 3) ═══
create or replace function public.so_detail(p_so_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so       public.so%rowtype;
  v_cust     text;
  v_lines    jsonb;
  v_charges  jsonb;
  v_lines_n  int;  v_no_price int;  v_free int;  v_charges_n int;  v_deal_ended int;
  v_lines_total numeric;  v_charges_total numeric;  v_od_amt numeric;
  v_sc_amt numeric := 0;  v_sc_tax numeric := 0;                            -- surcharge-2a — so_tax_preview totals 에서 읽는다(식 한 곳 · basis 를 따라간다)
  v_warn     text[];
  v_tax      jsonb;  v_tw text[];                              -- 세금 ② — so_tax_preview
  v_basis    text;  v_inv jsonb;  v_inv_hist jsonb;  v_removed int;  v_qty_removed numeric;   -- ⓐ2 — 보낸 수량 기준 · 인보이스 · 뺀 몫
  v_bal      jsonb;                                            -- ⓑ2 — 청구처 손님 잔액(그 통화 행)
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found';
  end if;
  select c.name into v_cust from public.customer c where c.id = v_so.customer_id;

  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('total', public.so_line_total(l), 'no_price', l.unit_price is null, 'free', l.free_reason is not null, 'shipped_total', round(l.qty_shipped * l.unit_price, 2), 'removed', l.qty_removed > 0,
                                                              'surcharge_unit', public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), 'surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_ordered), 'shipped_surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_shipped),   -- surcharge-2a(묶음 1 · 2 · total · shipped_total 과 같은 수량)
                                                              'qty_credited', (select coalesce(sum(cl.qty_returned), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_line_id = l.id and c.status = 'issued'),   -- ⓒ2
                                                              'deal_ended', l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)) order by l.line_no), '[]'::jsonb),
         count(*), count(*) filter (where l.unit_price is null), count(*) filter (where l.free_reason is not null), coalesce(sum(public.so_line_total(l)), 0),
         count(*) filter (where l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)),
         count(*) filter (where l.qty_removed > 0), coalesce(sum(l.qty_removed), 0)
    into v_lines, v_lines_n, v_no_price, v_free, v_lines_total, v_deal_ended, v_removed, v_qty_removed
  from public.so_line l where l.so_id = p_so_id;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.line_no), '[]'::jsonb), count(*), coalesce(sum(c.amount), 0)
    into v_charges, v_charges_n, v_charges_total
  from public.so_charge c where c.so_id = p_so_id;

  -- 오더 전체 할인(D6) — 제품 줄 합계에 한 번 · round 2(SO-10842 실물) · 운임은 기준에 없다
  v_od_amt := case when v_so.order_discount_pct is null then 0 else round(v_lines_total * v_so.order_discount_pct / 100, 2) end;

  -- 세금(세금 ② · 판정 8) — 오더에 고른 규칙(manual|ship_to)으로 줄마다 · 규칙 없으면 tax null + 경고 tax_rule_missing
  v_basis := case when v_so.status in ('shipped', 'fulfilled') then 'shipped' else 'ordered' end;   -- ⓐ2: 나간 뒤에는 보낸 수량이 금액(뺀 몫·pick_short 제외 · 인보이스가 정본 8-c) · ⓑ2: invoiced 값 없음(판정 1)
  v_tax := public.so_tax_preview(p_so_id, null, null, v_basis);
  v_sc_amt := coalesce((v_tax->'totals'->>'surcharge_amount')::numeric, 0);  v_sc_tax := coalesce((v_tax->'totals'->>'surcharge_tax')::numeric, 0);   -- surcharge-2a(묶음 3 · 4)
  if v_basis = 'shipped' then
    v_lines_total := (v_tax->'totals'->>'lines_amount')::numeric;
    v_od_amt := case when v_so.order_discount_pct is null then 0 else round(v_lines_total * v_so.order_discount_pct / 100, 2) end;
  end if;
  select jsonb_build_object('invoice_id', i.id, 'invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'due_on', i.due_on, 'total', i.total,
                            'deposit_applied', i.deposit_applied, 'credit_applied', i.credit_applied, 'balance_forward', i.balance_forward, 'amount_due', i.amount_due,
                            'remaining', public.so_invoice_remaining(i.id), 'paid', i.total - public.so_invoice_remaining(i.id),
                            'credits', (select coalesce(jsonb_agg(jsonb_build_object('credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'total', c.total) order by c.credit_number), '[]'::jsonb) from public.so_credit c where c.invoice_id = i.id),
                            'credited_total', (select coalesce(sum(c.total), 0) from public.so_credit c where c.invoice_id = i.id and c.status = 'issued')) into v_inv
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id and o.cancelled_at is null;
  select coalesce(jsonb_agg(jsonb_build_object('invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'cancelled_at', i.cancelled_at) order by i.invoice_number), '[]'::jsonb) into v_inv_hist
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id;
  select to_jsonb(b) into v_bal from public.so_customer_balance(coalesce(v_so.bill_to_customer_id, v_so.customer_id)) b where b.currency_id = v_so.currency_id;   -- ⓑ2: 청구처의 그 통화 잔액(받아 둔 돈 · 예약 · available · 미수)

  v_warn := public.so_tier_warnings(v_so);
  if v_so.tax_rule_id is null then v_warn := array_append(v_warn, 'tax_rule_missing'); end if;
  if v_removed > 0 then v_warn := array_append(v_warn, 'lines_removed'); end if;
  select array_agg(t.v) into v_tw from jsonb_array_elements_text(coalesce(v_tax->'warnings', '[]'::jsonb)) as t(v);
  v_warn := v_warn || coalesce(v_tw, '{}');
  if v_lines_n = 0    then v_warn := array_append(v_warn, 'no_lines'); end if;
  if v_no_price > 0   then v_warn := array_append(v_warn, 'lines_without_price'); end if;
  if v_deal_ended > 0 then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;

  return jsonb_build_object(
    'so', to_jsonb(v_so),
    'customer_name', v_cust,
    'lines', v_lines,
    'charges', v_charges,
    'totals', jsonb_build_object('basis', v_basis, 'lines', v_lines_n, 'lines_removed', v_removed, 'qty_removed', v_qty_removed, 'lines_total', v_lines_total, 'lines_without_price', v_no_price, 'free_lines', v_free,
                                 'order_discount_pct', v_so.order_discount_pct, 'order_discount_source', v_so.order_discount_source, 'order_discount_deal_id', v_so.order_discount_deal_id,
                                 'order_discount_amount', v_od_amt, 'lines_after_discount', v_lines_total - v_od_amt,
                                 'charges', v_charges_n, 'charges_total', v_charges_total,
                                 'surcharge_amount', v_sc_amt, 'surcharge_tax', v_sc_tax,                                        -- surcharge-2a — 물건값 · 오더 할인 기준 밖(묶음 3)
                                 'order_total', v_lines_total - v_od_amt + v_charges_total + v_sc_amt,
                                 'tax_rule', v_so.tax_rule, 'tax_rule_source', v_tax->>'source', 'tax', v_tax->'totals'->'tax',
                                 'order_total_with_tax', case when v_tax->'totals'->>'tax' is null then null else v_lines_total - v_od_amt + v_charges_total + v_sc_amt + (v_tax->'totals'->>'tax')::numeric end),
    'tax', v_tax,
    'invoice', v_inv,
    'invoice_history', v_inv_hist,
    'customer_balance', v_bal,
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑤ so_proforma 재발행 — 마지막 정의 20260925201614_so_payment_remaining_all.sql:259~341 바이트 그대로 + surcharge 자리(선언 1 · 합 1 · totals 4) ═══
create or replace function public.so_proforma(p_so_ids uuid[]) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_on       date := public.ims_today();
  v_n        int;
  v_cnt      int;
  v_bad      text;
  v_first    public.so%rowtype;
  v_so       public.so%rowtype;
  v_cust     uuid;
  v_prev     jsonb;
  v_orders   jsonb := '[]'::jsonb;
  v_deposits jsonb := '[]'::jsonb;
  v_lines_amt numeric := 0;  v_od_amt numeric := 0;  v_chg_amt numeric := 0;  v_tax numeric := 0;  v_tax_missing boolean := false;
  v_sc_amt numeric := 0;                                                                   -- surcharge-2a
  v_received numeric := 0;
  v_warn     text[] := '{}';
  v_tw       text[];
  v_bal      jsonb;
begin
  v_cnt := coalesce(array_length(p_so_ids, 1), 0);
  if v_cnt = 0 then raise exception 'A pro forma needs at least one order'; end if;
  select count(distinct x) into v_n from unnest(p_so_ids) x;
  if v_n <> v_cnt then raise exception 'The same order is listed twice'; end if;
  select count(*) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n <> v_cnt then raise exception 'Order not found'; end if;
  select string_agg(s.so_number || ' (' || s.status || ')', ', ' order by s.so_number) into v_bad from public.so s where s.id = any(p_so_ids) and s.status in ('fulfilled', 'cancelled');
  if v_bad is not null then raise exception 'A pro forma is for open orders only — % — a finished order has its invoice', v_bad; end if;
  select string_agg(s.so_number || ' is on invoice ' || i.invoice_number, ', ' order by s.so_number) into v_bad
  from public.so_invoice_order o join public.so s on s.id = o.so_id join public.so_invoice i on i.id = o.invoice_id where o.so_id = any(p_so_ids) and o.cancelled_at is null;
  if v_bad is not null then raise exception 'Order already invoiced — % — print the invoice instead', v_bad; end if;
  select count(distinct coalesce(s.bill_to_customer_id, s.customer_id)) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One pro forma bills one customer — these orders have different bill-to customers'; end if;
  select count(distinct s.currency_id) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One pro forma has one currency — these orders have different currencies'; end if;
  select * into v_first from public.so s where s.id = any(p_so_ids) order by s.so_number limit 1;
  v_cust := coalesce(v_first.bill_to_customer_id, v_first.customer_id);

  -- 오더마다 — 오늘 기준 예상 세금(so_tax_preview · 오더 규칙 · basis ordered: 발행 전 오더의 qty_removed 는 늘 0 · 0-11) · 규칙 없으면 세금 없이 경고
  for v_so in select * from public.so s where s.id = any(p_so_ids) order by s.so_number loop
    v_prev := public.so_tax_preview(v_so.id, v_on, null, 'ordered');
    v_lines_amt := v_lines_amt + (v_prev->'totals'->>'lines_amount')::numeric;
    v_od_amt    := v_od_amt + (v_prev->'totals'->>'order_discount_amount')::numeric;
    v_chg_amt   := v_chg_amt + (v_prev->'totals'->>'charges_amount')::numeric;
    v_sc_amt    := v_sc_amt + coalesce((v_prev->'totals'->>'surcharge_amount')::numeric, 0);   -- surcharge-2a(세금은 v_prev 의 tax 에 이미 들어 있다 · 묶음 4)
    if v_prev->'totals'->>'tax' is null then v_tax_missing := true; v_warn := array_append(v_warn, 'tax_rule_missing:' || v_so.so_number);
    else v_tax := v_tax + (v_prev->'totals'->>'tax')::numeric; end if;
    select array_agg(v_so.so_number || ':' || t.w) into v_tw from jsonb_array_elements_text(coalesce(v_prev->'warnings', '[]'::jsonb)) as t(w);
    v_warn := v_warn || coalesce(v_tw, '{}');
    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'status', v_so.status, 'order_date', v_so.order_date, 'ref', v_so.ref,
                                               'ship_to', jsonb_build_object('company', v_so.ship_to_company, 'contact', v_so.ship_to_contact, 'line1', v_so.ship_to_line1, 'line2', v_so.ship_to_line2,
                                                                             'city', v_so.ship_to_city, 'state_province', v_so.ship_to_state_province, 'postal_code', v_so.ship_to_postal_code, 'country', v_so.ship_to_country),
                                               'tax_rule', v_prev->'rule'->>'rule', 'rate_pct', v_prev->'rule'->'rate_pct', 'tax_source', v_prev->>'source',
                                               'lines', v_prev->'lines', 'order_discount', v_prev->'order_discount', 'charges', v_prev->'charges', 'totals', v_prev->'totals');
  end loop;

  -- 받은 금액 = 이 오더들을 대상으로 한 활성 선결제의 남은 금액(⬜9 · 대상이 다른 오더에도 걸린 결제는 남은 금액 전부를 보인다 — 짐작 그대로 · 정본에 적는다)
  select coalesce(jsonb_agg(jsonb_build_object('payment_id', z.id, 'paid_on', z.paid_on, 'method', z.method, 'reference', z.reference, 'amount', z.amount, 'remaining', z.remaining,
                                               'targets', (select jsonb_agg(s2.so_number order by s2.so_number) from public.so_payment_order o2 join public.so s2 on s2.id = o2.so_id where o2.payment_id = z.id)) order by z.paid_on, z.created_at), '[]'::jsonb),
         coalesce(sum(z.remaining), 0)
    into v_deposits, v_received
  from (select p.id, p.paid_on, p.method, p.reference, p.amount, p.created_at,
               public.so_payment_remaining(p.id) as remaining
          from public.so_payment p
         where p.customer_id = v_cust and p.currency_id = v_first.currency_id and p.status = 'active' and p.kind = 'payment'
           and exists (select 1 from public.so_payment_order o where o.payment_id = p.id and o.so_id = any(p_so_ids))) z
  where z.remaining > 0;
  select to_jsonb(b) into v_bal from public.so_customer_balance(v_cust) b where b.currency_id = v_first.currency_id;

  return jsonb_build_object(
    'document', 'PRO FORMA', 'note', 'This is not an invoice', 'invoice_number', null, 'as_of', v_on,
    'customer_id', v_cust, 'bill_to_name', v_first.bill_to_name, 'currency_code', v_first.currency_code,
    'orders', v_orders,
    'totals', jsonb_build_object('lines_amount', v_lines_amt, 'order_discount_amount', v_od_amt, 'charges_amount', v_chg_amt, 'surcharge_amount', v_sc_amt,   -- surcharge-2a(묶음 3)
                                 'taxable_amount', v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt,
                                 'tax', case when v_tax_missing then null else v_tax end,
                                 'total', case when v_tax_missing then null else v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt + v_tax end,
                                 'received', v_received,
                                 'balance_due', case when v_tax_missing then null else v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt + v_tax - v_received end),
    'deposits', v_deposits,
    'customer_balance', v_bal,
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑥ so_line_update 재발행 — 마지막 정의 20260924175014_so_tax_order_rule.sql:609~746 바이트 그대로 + surcharge 자리(짝 검사 9 줄 → so_surcharge_check 1 · 알리기 1 · 반환 2) ═══
create or replace function public.so_line_update(p_line_id uuid, p_patch jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_keys   constant text[] := array['qty_ordered', 'unit_price', 'discount_pct', 'free_reason', 'surcharge_pct', 'surcharge_amount', 'surcharge_label', 'comments'];   -- 세금 ②: tax_rule 은 오더 것(판정 8)
  v_staff  uuid;
  v_line   public.so_line%rowtype;
  v_so     public.so%rowtype;
  v_bad    text;
  q        record;
  v_qty    numeric;  v_unit numeric;  v_disc numeric;  v_override boolean;  v_dsrc text;  v_deal uuid;
  v_reason text;  v_comments text;
  v_spct   numeric;  v_samt numeric;  v_slbl text;
  v_line_no int;
  v_n      int;
  v_warn   text[] := '{}';
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();

  select * into v_line from public.so_line where id = p_line_id;
  if not found then
    raise exception 'Order line not found — nothing was saved';
  end if;
  v_line_no := v_line.line_no;
  v_so := public.so_require_draft(v_line.so_id, 'saved');

  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'p_patch must be a JSON object — nothing was saved';
  end if;
  if p_patch ? 'tax_rule' then                                  -- 세금 ② · 판정 8 — 줄마다 바꾸는 길은 없다(모르는 열쇠보다 먼저 · 사람이 읽는 말)
    raise exception 'The tax rule belongs to the order, not to a line — change it on the order (so_header_update tax_rule) — nothing was saved';
  end if;
  select k into v_bad from jsonb_object_keys(p_patch) k where k <> all (c_keys) limit 1;
  if v_bad is not null then
    raise exception 'Unknown field % — nothing was saved', v_bad;
  end if;
  if p_patch = '{}'::jsonb then
    raise exception 'Nothing to change — nothing was saved';
  end if;

  -- 수량
  v_qty := case when p_patch ? 'qty_ordered' then nullif(p_patch->>'qty_ordered', '')::numeric else v_line.qty_ordered end;
  if v_qty is null or v_qty <= 0 then
    raise exception 'Quantity must be a positive number — nothing was saved';
  end if;

  -- 가격 — 덮어쓰기 · 수동 할인 · 시스템으로 되돌리기 · 수량만 바뀐 시스템 줄은 다시 견적(판정 3) · 둘 다는 못 준다
  if p_patch ? 'unit_price' and p_patch ? 'discount_pct' then
    raise exception 'Give either a unit price or a discount, not both — nothing was saved';
  end if;
  if p_patch ? 'unit_price' then
    v_unit := nullif(p_patch->>'unit_price', '')::numeric;
    if v_unit is null then
      raise exception 'unit_price cannot be blank — remove the line or give a price — nothing was saved';
    end if;
    if v_unit < 0 then
      raise exception 'Unit price cannot be negative — nothing was saved';
    end if;
    v_override := true;  v_disc := null;  v_dsrc := null;  v_deal := null;
  elsif p_patch ? 'discount_pct' then
    v_disc := nullif(p_patch->>'discount_pct', '')::numeric;
    if v_disc is not null then                                   -- 수동 할인
      if v_disc < 0 or v_disc > 100 then
        raise exception 'discount_pct must be between 0 and 100 — nothing was saved';
      end if;
      v_dsrc := 'manual';  v_deal := null;
    else                                                         -- 비우면 시스템으로(할인 식 한 곳 · 딜 포함 · 이견 3)
      select * into q from public.so_line_quote(v_so, v_line.product_id, v_qty);
      v_disc := q.discount_pct;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;
    end if;
    v_unit := case when v_line.list_price is null then null else v_line.list_price * (1 - v_disc / 100) end;
    v_override := false;
  elsif v_qty is distinct from v_line.qty_ordered and not v_line.price_override and v_line.discount_source is distinct from 'manual' then
    select * into q from public.so_line_quote(v_so, v_line.product_id, v_qty);      -- 시스템 줄 · 수량이 바뀌었다 → 할인 다시(list 는 그대로)
    v_disc := q.discount_pct;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;
    v_unit := case when v_line.list_price is null then null else v_line.list_price * (1 - v_disc / 100) end;
    v_override := false;
  else
    v_unit := v_line.unit_price;  v_disc := v_line.discount_pct;  v_override := v_line.price_override;  v_dsrc := v_line.discount_source;  v_deal := v_line.deal_line_id;
  end if;

  -- 무상(판정 2 · ⬜7)
  v_reason   := case when p_patch ? 'free_reason' then nullif(trim(p_patch->>'free_reason'), '') else v_line.free_reason end;
  v_comments := case when p_patch ? 'comments'    then nullif(trim(p_patch->>'comments'), '')    else v_line.comments end;
  if v_unit is not distinct from 0 and v_reason is null then
    raise exception 'A free line (price 0) needs a reason — sample, promotion, replacement or other — nothing was saved';
  end if;
  if v_reason is not null and v_unit is distinct from 0 then
    raise exception 'Line % has a free-goods reason but a non-zero price — clear the reason or set the price to 0 — nothing was saved', v_line_no;
  end if;
  if v_reason is not null and v_reason not in ('sample', 'promotion', 'replacement', 'other') then
    raise exception 'Free reason % is not one of sample, promotion, replacement, other — nothing was saved', v_reason;
  end if;
  if v_reason = 'other' and v_comments is null then
    raise exception 'Reason other needs a comment — nothing was saved';
  end if;

  -- 부가 요금(판정 7 · 228 · surcharge-2a) — 짝 · 범위 · 무상 금지는 so_surcharge_check 한 곳(so_finalize 와 같은 문장)
  v_spct := case when p_patch ? 'surcharge_pct'    then nullif(p_patch->>'surcharge_pct', '')::numeric    else v_line.surcharge_pct end;
  v_samt := case when p_patch ? 'surcharge_amount' then nullif(p_patch->>'surcharge_amount', '')::numeric else v_line.surcharge_amount end;
  v_slbl := case when p_patch ? 'surcharge_label'  then nullif(trim(p_patch->>'surcharge_label'), '')     else v_line.surcharge_label end;
  perform public.so_surcharge_check(v_spct, v_samt, v_slbl, v_reason);

  update public.so_line set
    qty_ordered      = v_qty,
    unit_price       = v_unit,
    discount_pct     = v_disc,
    price_override   = v_override,
    discount_source  = v_dsrc,
    deal_line_id     = v_deal,
    free_reason      = v_reason,
    comments         = v_comments,
    surcharge_pct    = v_spct,
    surcharge_amount = v_samt,
    surcharge_label  = v_slbl,
    updated_by       = v_staff
  where id = p_line_id
  returning * into v_line;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Line % of % was not saved — it may have been removed by someone else just now — nothing was saved', v_line_no, v_so.so_number;
  end if;
  if v_line.unit_price is null then v_warn := array_append(v_warn, 'no_price'); end if;
  if v_line.deal_line_id is not null and public.so_deal_line_ended(v_line.deal_line_id, public.ims_today()) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if v_spct is not null and v_spct > 100 then v_warn := array_append(v_warn, 'surcharge_pct_over_100'); end if;   -- surcharge-2a(Caleb 확인 · 위 한계 CHECK 없음 · 화면이 확인을 묻는다)

  return jsonb_build_object('so_number', v_so.so_number, 'line', to_jsonb(v_line), 'total', public.so_line_total(v_line),
                            'surcharge_unit', public.so_line_surcharge_unit(v_line.unit_price, v_line.surcharge_pct, v_line.surcharge_amount), 'surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(v_line.unit_price, v_line.surcharge_pct, v_line.surcharge_amount), v_line.qty_ordered),   -- surcharge-2a
                            'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑦ so_finalize 재발행 — 마지막 정의 20260926204246_wms_5_2b_finalize_handoff_rollback.sql:259~471 바이트 그대로 + surcharge 자리(선언 1 · ① 검사 15 · 초기화 1 · ②′ 17 · 반환 1) ═══
create or replace function public.so_finalize(p_orders jsonb, p_commit boolean default true, p_shipped_on date default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_reasons  constant text[] := array['customer_removed', 'not_wanted', 'other'];
  v_staff    uuid;
  v_on       date;
  v_n        int;  v_cnt int;
  v_bad      text;
  e          jsonb;  x jsonb;
  v_so       public.so%rowtype;
  v_l        public.so_line%rowtype;
  v_c        public.customer%rowtype;
  v_acct     public.ref_account%rowtype;
  v_ch       public.so_charge%rowtype;
  q          record;
  v_qty      numeric;  v_remaining numeric;  v_new_unit numeric;
  v_reason   text;  v_key text;  k text;
  v_next     int;
  v_removed  jsonb;  v_repriced jsonb;  v_charges jsonb;  v_ship jsonb;  v_iss jsonb;
  v_surcharges jsonb;  v_spct numeric;  v_samt numeric;  v_slbl text;                 -- surcharge-2a(판정 230)
  v_orders   jsonb := '[]'::jsonb;
  v_groups   jsonb := '{}'::jsonb;
  v_invoices jsonb := '[]'::jsonb;
  v_ids      uuid[];
  v_warn     text[] := '{}';
  v_tw       text[];
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — 판정 8: 마무리는 오더 담당(sales)부터 · 역할 문 없음(R5 의 예외)
  v_staff := public.so_current_staff();
  v_on := coalesce(p_shipped_on, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Ship date % is in the future — nothing was saved', v_on; end if;
  if p_orders is null or jsonb_typeof(p_orders) <> 'array' or jsonb_array_length(p_orders) = 0 then
    raise exception 'p_orders must be a JSON array of orders — nothing was saved';
  end if;
  if exists (select 1 from jsonb_array_elements(p_orders) t where jsonb_typeof(t) <> 'object' or nullif(t->>'so_id', '') is null) then
    raise exception 'Every order needs a so_id — nothing was saved';
  end if;
  select count(*), count(distinct t->>'so_id') into v_cnt, v_n from jsonb_array_elements(p_orders) t;
  if v_n <> v_cnt then raise exception 'The same order is listed twice — nothing was saved'; end if;
  -- ⑤-2b(판정 16 · ⬜7): picks 가 없으면 WMS 인계(wms_so_handoff)의 picks 를 쓴다(있으면 그대로 — 오피스가 고칠 길)
  select jsonb_agg(case when t.e ? 'picks' then t.e else t.e || jsonb_build_object('picks', (public.wms_so_handoff((t.e->>'so_id')::uuid))->'picks') end order by t.ord) into p_orders from jsonb_array_elements(p_orders) with ordinality t(e, ord);

  -- ① 검사 — 오더마다(잠금) · 하나라도 막히면 전체 거부 · 오더 번호로 말한다
  for e in select t from jsonb_array_elements(p_orders) t loop
    select * into v_so from public.so s where s.id = (e->>'so_id')::uuid for update;
    if not found then raise exception 'Order % not found — nothing was saved', e->>'so_id'; end if;
    if v_so.status <> 'packed' then
      raise exception 'Order % is % — only a packed order (warehouse work finished) can be finalized here — nothing was saved', v_so.so_number, v_so.status;
    end if;
    if v_so.bill_to_customer_id is null then raise exception 'Order % has no bill-to customer — nothing was saved', v_so.so_number; end if;
    -- 뺀 몫(판정 5) — 모양 · 줄 · 수량 · 사유 · 중복
    if e ? 'removed' and jsonb_typeof(e->'removed') not in ('array', 'null') then
      raise exception 'Order %: removed must be an array of {line_id, qty, reason, note} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = nullif(x->>'line_id', '')::uuid and l.so_id = v_so.id;
      if not found then raise exception 'Order %: removed line % is not on this order — nothing was saved', v_so.so_number, coalesce(x->>'line_id', '?'); end if;
      if v_l.qty_removed > 0 then raise exception 'Order % line % already has a removed quantity — nothing was saved', v_so.so_number, v_l.line_no; end if;
      v_qty := case when (x->>'qty') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (x->>'qty')::numeric else null end;
      if v_qty is null or v_qty <= 0 then raise exception 'Order % line %: removed qty must be a positive number — nothing was saved', v_so.so_number, v_l.line_no; end if;
      if v_qty > v_l.qty_ordered then raise exception 'Order % line %: cannot remove % — only % ordered — nothing was saved', v_so.so_number, v_l.line_no, v_qty, v_l.qty_ordered; end if;
      v_reason := nullif(trim(x->>'reason'), '');
      if v_reason is null or v_reason <> all (c_reasons) then
        raise exception 'Order % line %: removed reason must be one of customer_removed, not_wanted, other — nothing was saved', v_so.so_number, v_l.line_no;
      end if;
      if v_reason = 'other' and nullif(trim(x->>'note'), '') is null then
        raise exception 'Order % line %: reason other needs a note — nothing was saved', v_so.so_number, v_l.line_no;
      end if;
    end loop;
    if (select count(*) - count(distinct t->>'line_id') from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t) > 0 then
      raise exception 'Order %: the same line is removed twice — nothing was saved', v_so.so_number;
    end if;
    -- 판정 9 — 모든 줄을 다 뺐다 → 거부 + 길
    if not exists (select 1 from public.so_line l
                   left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t where (t->>'line_id')::uuid = l.id) rm on true
                   where l.so_id = v_so.id and l.qty_ordered - coalesce(rm.q, 0) > 0) then
      raise exception 'Order % — every line was removed, there is nothing to ship: roll the order back in WMS, then cancel it (so_unconfirm / so_cancel) — nothing was saved', v_so.so_number;
    end if;
    -- 픽 — 모양 · 줄 · 수량 · 목표 초과(칸은 실행 때 so_ship 이 본다)
    if e->'picks' is null or jsonb_typeof(e->'picks') <> 'array' or jsonb_array_length(e->'picks') = 0 then
      raise exception 'Order %: picks must be a JSON array of {line_id, bin, qty} — nothing was saved', v_so.so_number;
    end if;
    if exists (select 1 from jsonb_array_elements(e->'picks') t where nullif(t->>'line_id', '') is null or (t->>'qty') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' or (t->>'qty')::numeric <= 0) then
      raise exception 'Order %: every pick needs a line_id and a positive qty — nothing was saved', v_so.so_number;
    end if;
    select string_agg(distinct t->>'line_id', ', ') into v_bad from jsonb_array_elements(e->'picks') t
    where not exists (select 1 from public.so_line l where l.id = (t->>'line_id')::uuid and l.so_id = v_so.id);
    if v_bad is not null then raise exception 'Order %: pick line % is not on this order — nothing was saved', v_so.so_number, v_bad; end if;
    select string_agg(format('line %s picked %s but %s to ship', l.line_no, pk.q, l.qty_ordered - coalesce(rm.q, 0)), '; ' order by l.line_no) into v_bad
    from public.so_line l
    join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(e->'picks') t where (t->>'line_id')::uuid = l.id) pk on true
    left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t where (t->>'line_id')::uuid = l.id) rm on true
    where l.so_id = v_so.id and pk.q > l.qty_ordered - coalesce(rm.q, 0);
    if v_bad is not null then raise exception 'Order %: over-pick — % — over-pick goes back to its bin — nothing was saved', v_so.so_number, v_bad; end if;
    -- 운임(판정 4 · so_charge_set 의 규칙)
    if e ? 'charges' and jsonb_typeof(e->'charges') not in ('array', 'null') then
      raise exception 'Order %: charges must be an array of {charge_id, name, amount, description, account_id} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'charges', 'null'::jsonb), '[]'::jsonb)) t loop
      if nullif(trim(x->>'name'), '') is null then raise exception 'Order %: a charge needs a name — nothing was saved', v_so.so_number; end if;
      if (x->>'amount') !~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then raise exception 'Order %: charge % needs an amount — nothing was saved', v_so.so_number, trim(x->>'name'); end if;
      if (x->>'amount')::numeric < 0 then raise exception 'Order %: a charge cannot be negative — use a credit note — nothing was saved', v_so.so_number; end if;
      if nullif(x->>'charge_id', '') is not null and not exists (select 1 from public.so_charge c where c.id = (x->>'charge_id')::uuid and c.so_id = v_so.id) then
        raise exception 'Order %: charge % is not on this order — nothing was saved', v_so.so_number, x->>'charge_id';
      end if;
      if nullif(x->>'account_id', '') is not null and not exists (select 1 from public.ref_account a where a.id = (x->>'account_id')::uuid) then
        raise exception 'Order %: account % not found — nothing was saved', v_so.so_number, x->>'account_id';
      end if;
    end loop;
    -- 부가 요금(판정 230 · surcharge-2a) — 운임과 같은 자리 · 모양 · 줄 · 짝·범위·무상(so_surcharge_check · so_line_update 와 한 곳) · 중복
    if e ? 'surcharges' and jsonb_typeof(e->'surcharges') not in ('array', 'null') then
      raise exception 'Order %: surcharges must be an array of {line_id, surcharge_pct, surcharge_amount, surcharge_label} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'surcharges', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = nullif(x->>'line_id', '')::uuid and l.so_id = v_so.id;
      if not found then raise exception 'Order %: surcharge line % is not on this order — nothing was saved', v_so.so_number, coalesce(x->>'line_id', '?'); end if;
      v_spct := case when x ? 'surcharge_pct'    then nullif(x->>'surcharge_pct', '')::numeric    else v_l.surcharge_pct end;
      v_samt := case when x ? 'surcharge_amount' then nullif(x->>'surcharge_amount', '')::numeric else v_l.surcharge_amount end;
      v_slbl := case when x ? 'surcharge_label'  then nullif(trim(x->>'surcharge_label'), '')     else v_l.surcharge_label end;
      perform public.so_surcharge_check(v_spct, v_samt, v_slbl, v_l.free_reason);
    end loop;
    if (select count(*) - count(distinct t->>'line_id') from jsonb_array_elements(coalesce(nullif(e->'surcharges', 'null'::jsonb), '[]'::jsonb)) t) > 0 then
      raise exception 'Order %: the same line has two surcharge changes — nothing was saved', v_so.so_number;
    end if;
  end loop;

  -- ②~⑤ 오더마다(주어진 순서) — 실행이면 쓰고 미리 보기면 계산만
  for e in select t from jsonb_array_elements(p_orders) t loop
    select * into v_so from public.so s where s.id = (e->>'so_id')::uuid;
    v_removed := '[]'::jsonb;  v_repriced := '[]'::jsonb;  v_charges := '[]'::jsonb;
    v_surcharges := '[]'::jsonb;                                                       -- surcharge-2a

    -- ② 택배사 · 추적번호 · 배송 메모(열쇠가 온 것만) · 운임 줄(새로 · 또는 charge_id 로 고침 · 세금은 오더 규칙 · 기본 계정 _99_)
    if p_commit and (e ? 'carrier' or e ? 'tracking_number' or e ? 'shipping_notes') then
      update public.so s set
        carrier         = case when e ? 'carrier'         then nullif(trim(e->>'carrier'), '')         else s.carrier end,
        tracking_number = case when e ? 'tracking_number' then nullif(trim(e->>'tracking_number'), '') else s.tracking_number end,
        shipping_notes  = case when e ? 'shipping_notes'  then nullif(trim(e->>'shipping_notes'), '')  else s.shipping_notes end,
        updated_by      = v_staff
      where s.id = v_so.id;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'charges', 'null'::jsonb), '[]'::jsonb)) t loop
      v_acct := null;
      if nullif(x->>'account_id', '') is not null then
        select * into v_acct from public.ref_account a where a.id = (x->>'account_id')::uuid;
      elsif nullif(x->>'charge_id', '') is null then
        select * into v_acct from public.ref_account a where a.code = '_99_';                      -- 기본 Freight Sales · 없으면 비우고 알린다(so_charge_set 과 같다)
        if not found then v_warn := array_append(v_warn, 'charge_account_unset:' || v_so.so_number); end if;
      end if;
      if p_commit then
        if nullif(x->>'charge_id', '') is null then
          select coalesce(max(c.line_no), 0) + 1 into v_next from public.so_charge c where c.so_id = v_so.id;
          insert into public.so_charge (so_id, line_no, name, description, amount, tax_rule, account_id, account_code, updated_by)
          values (v_so.id, v_next, trim(x->>'name'), nullif(trim(x->>'description'), ''), (x->>'amount')::numeric, v_so.tax_rule, v_acct.id, v_acct.code, v_staff)
          returning * into v_ch;
        else
          update public.so_charge c set
            name = trim(x->>'name'), description = nullif(trim(x->>'description'), ''), amount = (x->>'amount')::numeric, tax_rule = v_so.tax_rule,
            account_id = case when v_acct.id is not null then v_acct.id else c.account_id end, account_code = case when v_acct.id is not null then v_acct.code else c.account_code end, updated_by = v_staff
          where c.id = (x->>'charge_id')::uuid returning * into v_ch;
        end if;
        v_charges := v_charges || jsonb_build_object('charge_id', v_ch.id, 'line_no', v_ch.line_no, 'name', v_ch.name, 'amount', v_ch.amount, 'tax_rule', v_ch.tax_rule, 'account_code', v_ch.account_code);
      else
        v_charges := v_charges || jsonb_build_object('charge_id', nullif(x->>'charge_id', ''), 'name', trim(x->>'name'), 'amount', (x->>'amount')::numeric, 'tax_rule', v_so.tax_rule, 'account_code', v_acct.code, 'preview', true);
      end if;
    end loop;

    -- ②′ 부가 요금(판정 230 · surcharge-2a) — so_line_update 와 같은 패치 모양(열쇠가 온 칸만 · '' 은 비움) · 실행이면 쓰고 미리 보기면 old → new 만 · ③ 다시 견적 앞(%형은 저장값이 아니라 계산 때 단가를 읽는다)
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'surcharges', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = (x->>'line_id')::uuid;
      v_spct := case when x ? 'surcharge_pct'    then nullif(x->>'surcharge_pct', '')::numeric    else v_l.surcharge_pct end;
      v_samt := case when x ? 'surcharge_amount' then nullif(x->>'surcharge_amount', '')::numeric else v_l.surcharge_amount end;
      v_slbl := case when x ? 'surcharge_label'  then nullif(trim(x->>'surcharge_label'), '')     else v_l.surcharge_label end;
      if p_commit then
        update public.so_line set surcharge_pct = v_spct, surcharge_amount = v_samt, surcharge_label = v_slbl, updated_by = v_staff where id = v_l.id;
      end if;
      v_surcharges := v_surcharges || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku,
                                                         'old', jsonb_build_object('surcharge_pct', v_l.surcharge_pct, 'surcharge_amount', v_l.surcharge_amount, 'surcharge_label', v_l.surcharge_label),
                                                         'new', jsonb_build_object('surcharge_pct', v_spct, 'surcharge_amount', v_samt, 'surcharge_label', v_slbl),
                                                         'surcharge_unit', public.so_line_surcharge_unit(v_l.unit_price, v_spct, v_samt));
      if v_spct is not null and v_spct > 100 then v_warn := array_append(v_warn, 'surcharge_pct_over_100:' || v_so.so_number || ':' || v_l.line_no); end if;
    end loop;

    -- ③ 뺀 몫(판정 5) + 시스템 줄 다시 견적(판정 6 · 할인만 · 남은 수량 > 0 · 사람이 정한 줄은 그대로)
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = (x->>'line_id')::uuid;
      v_qty := (x->>'qty')::numeric;  v_remaining := v_l.qty_ordered - v_qty;
      if p_commit then
        update public.so_line set qty_removed = v_qty, removed_reason = nullif(trim(x->>'reason'), ''), removed_note = nullif(trim(x->>'note'), ''), removed_at = now(), removed_by = v_staff, updated_by = v_staff
        where id = v_l.id;
      end if;
      v_removed := v_removed || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'qty_ordered', v_l.qty_ordered, 'qty_removed', v_qty, 'remaining', v_remaining,
                                                   'reason', nullif(trim(x->>'reason'), ''), 'free', v_l.free_reason is not null);
      if v_remaining > 0 and not v_l.price_override and v_l.discount_source is distinct from 'manual' then
        select * into q from public.so_line_quote(v_so, v_l.product_id, v_remaining);
        v_new_unit := case when v_l.list_price is null then null else v_l.list_price * (1 - q.discount_pct / 100) end;
        if p_commit then perform public.so_line_requote(v_l.id, v_remaining, false); end if;
        v_repriced := v_repriced || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'qty', v_remaining,
                                                       'old_unit_price', v_l.unit_price, 'new_unit_price', v_new_unit, 'old_discount_pct', v_l.discount_pct, 'new_discount_pct', q.discount_pct,
                                                       'old_discount_source', v_l.discount_source, 'new_discount_source', q.discount_source, 'changed', v_new_unit is distinct from v_l.unit_price);
      end if;
    end loop;

    -- ④ 출고(so_ship · 목표 = 주문 − 뺀 것 · 그 아래 차이만 pick_short 판정 7) — 미리 보기는 줄별 계산만(칸 검사·원장은 실행 때)
    if p_commit then
      v_ship := public.so_ship(v_so.id, e->'picks', v_staff, v_on);
      select array_agg(v_so.so_number || ':' || t.w) into v_tw from jsonb_array_elements_text(coalesce(v_ship->'warnings', '[]'::jsonb)) as t(w);
      v_warn := v_warn || coalesce(v_tw, '{}');
    else
      select jsonb_build_object('preview', true,
               'lines', coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'ordered', l.qty_ordered, 'removed', coalesce(rm.q, 0), 'to_ship', l.qty_ordered - coalesce(rm.q, 0),
                                                              'picked', coalesce(pk.q, 0), 'short', l.qty_ordered - coalesce(rm.q, 0) - coalesce(pk.q, 0)) order by l.line_no), '[]'::jsonb),
               'backorder_lines', count(*) filter (where l.qty_ordered - coalesce(rm.q, 0) - coalesce(pk.q, 0) > 0))
        into v_ship
      from public.so_line l
      left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(e->'picks') t where (t->>'line_id')::uuid = l.id) pk on true
      left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t where (t->>'line_id')::uuid = l.id) rm on true
      where l.so_id = v_so.id;
    end if;

    -- ⑤ 묶음 열쇠(판정 2) — 청구처 · 청구처 설정이 켜졌으면 오더의 손님(매장) · invoice_group 이 오면 그것(청구처 안에서 · 직원이 바꾼 묶음)
    select * into v_c from public.customer c where c.id = v_so.bill_to_customer_id;
    v_key := v_so.bill_to_customer_id::text || '|' || coalesce(nullif(trim(e->>'invoice_group'), ''), case when coalesce(v_c.invoice_split_by_store, false) then 'store:' || v_so.customer_id::text else '' end);
    v_groups := jsonb_set(v_groups, array[v_key], coalesce(v_groups->v_key, '[]'::jsonb) || to_jsonb(v_so.id));
    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'invoice_group', v_key, 'removed', v_removed, 'repriced', v_repriced, 'charges', v_charges, 'surcharges', v_surcharges, 'ship', v_ship);
  end loop;

  -- ⑥ 발행 — 묶음마다 한 장(so_invoice_issue · 발행일 = 오늘 ims_today · §16 판정 5) · 미리 보기는 몇 장 · 어느 오더
  for k in select t.key_txt from jsonb_object_keys(v_groups) as t(key_txt) order by t.key_txt loop   -- 별칭은 변수 이름(x · e · k)과 다르게
    select array_agg(t.v::uuid) into v_ids from jsonb_array_elements_text(v_groups->k) as t(v);
    if p_commit then
      v_iss := public.so_invoice_issue(v_ids, v_staff, null);
      select array_agg((v_iss->>'invoice_number') || ':' || t.w) into v_tw from jsonb_array_elements_text(coalesce(v_iss->'warnings', '[]'::jsonb)) as t(w);
      v_warn := v_warn || coalesce(v_tw, '{}');
      v_invoices := v_invoices || jsonb_build_object('group', k, 'invoice_id', v_iss->'invoice_id', 'invoice_number', v_iss->'invoice_number', 'issued_on', v_iss->'issued_on', 'due_on', v_iss->'due_on',
                                                     'orders', (select jsonb_agg(o->>'so_number') from jsonb_array_elements(v_iss->'orders') o), 'totals', v_iss->'totals', 'warnings', v_iss->'warnings');
    else
      v_invoices := v_invoices || jsonb_build_object('group', k, 'preview', true, 'orders', (select jsonb_agg(s.so_number order by s.so_number) from public.so s where s.id = any(v_ids)), 'order_count', array_length(v_ids, 1));
    end if;
  end loop;

  return jsonb_build_object('committed', p_commit, 'shipped_on', v_on, 'orders', v_orders, 'invoices', v_invoices, 'invoice_count', jsonb_array_length(v_invoices), 'warnings', to_jsonb(v_warn));
end;
$$;

comment on function public.so_tax_preview(uuid, date, uuid, text) is
  '⭐ 세금 미리 보기 — 식 한 곳(§16 판정 3 · 8 · ⓐ1 basis · surcharge-2a) — 오더 규칙(manual | ship_to · 없으면 배송지로 다시) · 줄 · 오더 전체 할인 · 운임 · ⭐ surcharge 를 각자 so_tax_amount 로 줄마다 반올림해 더한다 · 줄 객체: amount · tax + surcharge_label · surcharge_unit(개당 · 센트) · surcharge_total(개당 × basis 수량) · surcharge_tax · totals: lines_amount · order_discount_amount · charges_amount · surcharge_amount(물건값과 따로 · 묶음 3) · taxable_amount(넷의 합) · tax(넷의 세금 합) · total · ⭐ 36-e 76: surcharge 세율은 v_sc_rate 한 줄(지금 = 오더 세율 · 회계사가 안 붙는다 하면 0) · so_detail · so_proforma · so_invoice_issue · so_pos_complete 가 이것을 쓴다';
comment on function public.so_detail(uuid) is
  '⭐ SO 상세 읽기(so · 손님 이름 · 줄 · 운임 · 합계 · 세금 · 인보이스 · 잔액 · 경고 · ⓐ2 basis · ⓑ2 · ⓒ2 · surcharge-2a) — 줄마다 total · shipped_total 과 나란히 surcharge_unit · surcharge_total(qty_ordered) · shipped_surcharge_total(qty_shipped) · totals 에 surcharge_amount · surcharge_tax(so_tax_preview totals 에서 · basis 따라감) · order_total · order_total_with_tax 에 포함 · ⚠️ lines_total · order_discount_amount 는 물건값만(묶음 3 — surcharge 는 오더 할인 기준 밖)';
comment on function public.so_proforma(uuid[]) is
  '⭐ 견적서(§18 · ⬜9 · surcharge-2a) — 열린 오더 묶음 · basis ordered · 오늘 세율 · 오더마다 so_tax_preview(줄 객체에 surcharge 넷이 실린다) · totals: lines_amount · order_discount_amount · charges_amount · surcharge_amount(물건값과 따로) · taxable_amount · tax(surcharge 세금 포함) · total · received(대상 선결제 남은 금액) · balance_due · 저장 없음 · 번호 없음';
comment on function public.so_line_update(uuid, jsonb) is
  '⭐ SO 초안 줄 고치기(①b · 할인 규칙 ②-0b · 세금 ② · surcharge-2a) — definer · 첫 줄 ims_require_write(sales) · 초안만(packed 은 so_finalize · 판정 230) · 열쇠 여덟(qty_ordered · unit_price · discount_pct · free_reason · surcharge_pct · surcharge_amount · surcharge_label · comments) · tax_rule 열쇠는 거부(판정 8) · ⭐ surcharge 는 so_surcharge_check 한 곳(짝 · % > 0 · 금액 > 0 센트 두 자리 · 무상 줄 금지 — 판정 228 · 양방향) · 알리기 surcharge_pct_over_100 · 반환 total(물건값) · surcharge_unit · surcharge_total';
comment on function public.so_finalize(jsonb, boolean, date) is
  '⭐⭐ 오피스 마무리(so-module §17 판정 1 · ⓐ2 · ⑤-2b 재발행 · surcharge-2a 판정 230) — definer · 첫 줄 ims_require_write(sales) · 역할 문 없음(판정 8 · R5 예외) · packed 오더 묶음을 한 트랜잭션에 출고 + 발행. p_orders [{so_id, picks?, removed?, charges?, surcharges?, carrier?, tracking_number?, shipping_notes?, invoice_group?}] · ⭐ surcharges [{line_id, surcharge_pct?, surcharge_amount?, surcharge_label?}] — so_line_update 와 같은 패치 모양(열쇠가 온 칸만 · 빈 글자는 비움) · 검사는 so_surcharge_check 한 곳(짝 · 범위 · 무상 금지) · 운임과 같은 자리(② 뒤 · ③ 다시 견적 앞) · 미리 보기는 old → new 만 · 반환 orders[].surcharges · 알리기 surcharge_pct_over_100:<오더>:<줄> · shipped 뒤는 이 함수가 packed 만 받으므로 닫혀 있다(인보이스 취소 → 재발행 길) · picks 가 없으면 WMS 인계(wms_so_handoff)';
