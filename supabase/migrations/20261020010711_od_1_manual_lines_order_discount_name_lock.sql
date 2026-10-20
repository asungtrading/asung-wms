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

-- ═══ od-1 — 손으로 정한 줄은 오더 할인을 안 받는다 · 마스터 이름 잠금 (2026-10-19 밤 · 판정 532 · 538 · 542 · 543 · 544 · fb-0 3번 (다)) ═══
--   M 줄 = 손으로 정한 줄 = so_line.price_override OR discount_source in ('manual', 'shopify') — 표식은 새 칸 없이 지금 칸(판정 542) · shopify 는 이견 1(손님이 본 가격 = 최종 · so_reprice 와 같은 기준)
--   문턱 바탕(so_order_discount · so_coupon_pct 의 so_lines_total)은 모든 줄 그대로(판정 543) · 할인 금액 바탕 = M 줄을 뺀 나머지(판정 542 · 544) · 금액 = −round(바탕 × pct / 100, 2)
--   식 한 곳 = so_tax_preview(totals.discount_basis_amount · manual_lines_amount · order_discount.basis · 줄마다 manual) — so_detail · so_totals_many 는 그 값을 읽는다 · so_invoice_issue · so_invoice_preview · so_proforma · doc_data_ship_ready 는 원래 v_prev 를 쓴다(무접촉)
--   so_credit_issue 는 인보이스 거울로 다시 셈한다(판정 325) → 같은 규칙(M 줄의 환불에는 오더 할인 몫 없음) · 이미 발행된 인보이스 · 크레딧은 바꾸지 않는다
--   문서의 줄별 net unit(doc_unit_prices · 판정 528 ④)도 M 줄은 오더 % 를 안 받는다 — doc_data_invoice(neutral 'manual') · doc_data_invoice_fmt · doc_data_so · so_invoice_preview(ship_ready 의 neutral)
--   재발행 여덟 = 마지막 정의 바이트 그대로 + 바뀐 줄만(원본: so_tax_preview · so_invoice_preview 20261019155731 · so_detail · so_totals_many 20261007171939 · so_credit_issue 20261007181109 · doc_data_invoice · doc_data_invoice_fmt · doc_data_so 20261019172034)
--   이름 잠금(판정 538) = ims_ref_name_lock() before update 행 트리거 다섯(ref_brand · ref_category · ref_unit · ref_payment_term · ref_bin) · ref_bin 은 warehouse_id 도 · errcode IM538 · 화면 글 「Names cannot be changed — switch this one off and add a new one.」
--   화면 계산 둘(so.html Net unit 2282 ~ 2283 · 2419 · pos.html 500)은 대화 Claude 가 so_detail lines[].manual 로 고친다(이 파일 밖)
do $$
declare v_bad text := '';
begin
  if to_regprocedure('public.so_tax_preview(uuid, date, uuid, text, jsonb)') is null then v_bad := v_bad || ' so_tax_preview(5)'; end if;
  if to_regprocedure('public.so_invoice_preview(jsonb, date)') is null then v_bad := v_bad || ' so_invoice_preview'; end if;
  if to_regprocedure('public.doc_data_invoice_fmt(text, jsonb, jsonb)') is null or to_regprocedure('public.doc_data_invoice(text, uuid, jsonb)') is null or to_regprocedure('public.doc_data_so(uuid, jsonb)') is null then v_bad := v_bad || ' doc_data'; end if;
  if to_regprocedure('public.so_credit_issue(jsonb, boolean)') is null or to_regprocedure('public.so_totals_many(uuid[])') is null or to_regprocedure('public.so_detail(uuid)') is null then v_bad := v_bad || ' so_fns'; end if;
  if to_regprocedure('public.so_line_manual(public.so_line)') is not null or exists (select 1 from pg_trigger where tgname = 'ref_brand_name_lock') then v_bad := v_bad || ' od-1-already-applied'; end if;
  if (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname in ('ref_brand', 'ref_category', 'ref_unit', 'ref_payment_term', 'ref_bin')) <> 5 then v_bad := v_bad || ' ref_tables'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM511', message = format('STOP - od-1 preconditions:%s - nothing was changed', v_bad); end if;
end $$;

-- ═══ ① so_line_manual — 「손으로 정한 줄」 판정 한 곳(판정 542 · 544 · 이견 1 shopify) · 순수 식이라 authenticated 에 열어 둔다(invoker 창구 so_detail · so_tax_preview 가 부른다 · 판정 31 예외 규칙 「불변식으로 안전한 함수」) ═══
create function public.so_line_manual(l public.so_line) returns boolean
  language sql immutable parallel safe
  set search_path = public, pg_temp
as $$
  select coalesce(l.price_override, false) or coalesce(l.discount_source, '') in ('manual', 'shopify');
$$;
revoke all on function public.so_line_manual(public.so_line) from public, anon;
grant execute on function public.so_line_manual(public.so_line) to authenticated, service_role;
comment on function public.so_line_manual(public.so_line) is 'od-1 판정 542 · 544 — 손으로 정한 줄(M 줄) = price_override 또는 discount_source manual · shopify(손님이 본 가격 그대로) · 오더 전체 할인(상시 · 금액 단계 · 쿠폰 · manual)을 받지 않는다 · 문턱(so_lines_total)에는 들어간다(판정 543) · 무상 줄(0 원 · override)도 M — 금액 0 이라 결과 같다';

-- ═══ ② so_tax_preview 재발행 — 원본 20261019155731_doc_1b2_ship_ready.sql:150 바이트 + 바뀐 줄(선언 1 · 줄 manual · M 합 · 할인 식 · order_discount.basis · totals 둘) ═══
create or replace function public.so_tax_preview(p_so_id uuid, p_on date default null, p_rule_id uuid default null, p_basis text default 'ordered', p_over jsonb default null) returns jsonb
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
  v_chd    jsonb;  v_chd_tax numeric := 0;  v_chd_amt numeric := 0;                   -- fr-1 판정 352 · 354: 운임 할인 줄(따로) · 할인 세금(줄마다 반올림) · 할인 합
  v_od_amt numeric := 0;  v_od_tax numeric := 0;
  v_m_amt  numeric := 0;                                                                  -- od-1 판정 542 · 544: 손으로 정한 줄(so_line_manual — price_override · manual · shopify 할인)의 금액 합 — 오더 할인 바탕에서 뺀다
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
                                              'discount_pct', l.discount_pct, 'discount_source', l.discount_source, 'price_override', l.price_override, 'manual', public.so_line_manual(l),   -- od-1
                                              'surcharge_label', l.surcharge_label, 'surcharge_unit', a.sc_unit, 'surcharge_total', s.sc_amt, 'surcharge_tax', public.so_tax_amount(s.sc_amt, v_sc_rate),   -- surcharge-2a(묶음 4): 줄마다 따로 반올림
                                              'combo', exists (select 1 from public.so_line cp where cp.combo_line_id = l.id), 'combo_line_id', l.combo_line_id, 'combo_sku', (select cp.sku from public.so_line cp where cp.id = l.combo_line_id),   -- asm-2b2(묶음 5): 줄 목록은 그대로(구성품 줄은 0 원 · 합계 불변) · 문서 창구(so_invoice_issue · so_proforma)가 이 표시로 구성품 줄을 뺀다
                                              'combo_components', (select jsonb_agg(jsonb_build_object('so_line_id', cp.id, 'product_id', cp.product_id, 'sku', cp.sku, 'description', cp.product_name, 'unit', cp.unit, 'qty_per_combo', cp.combo_qty, 'qty', a.qty * cp.combo_qty) order by cp.line_no) from public.so_line cp where cp.combo_line_id = l.id)) order by l.line_no), '[]'::jsonb),   -- 「includes …」 — 이 기준(basis)의 콤보 수 × 구성품 수
         coalesce(sum(public.so_tax_amount(a.amt, v_rate)), 0), coalesce(sum(a.amt), 0),
         coalesce(sum(s.sc_amt), 0), coalesce(sum(public.so_tax_amount(s.sc_amt, v_sc_rate)), 0), coalesce(sum(a.amt) filter (where public.so_line_manual(l)), 0)   -- od-1: 손으로 정한 줄의 금액 합(같은 수량 · 같은 식)
    into v_lines, v_lines_tax, v_lines_amt, v_sc_amt, v_sc_tax, v_m_amt
  from public.so_line l0
  cross join lateral (select (case when p_over->'lines' ? l0.id::text then jsonb_populate_record(l0, (p_over->'lines'->(l0.id::text)) - 'qty') else l0 end).*) l   -- doc-1b2: 줄 덮어쓰기(unit_price · discount_pct · discount_source · surcharge_*) — 마무리가 쓰기 전의 값으로 셈한다 · p_over 없으면 l0 그대로
  cross join lateral (select case when p_over->'lines'->(l0.id::text) ? 'qty' then (p_over->'lines'->(l0.id::text)->>'qty')::numeric when p_basis = 'shipped' then l.qty_shipped else l.qty_ordered end as qty,   -- doc-1b2: 수량 덮어쓰기(보낼 수량)
                             case when p_over->'lines'->(l0.id::text) ? 'qty' then round((p_over->'lines'->(l0.id::text)->>'qty')::numeric * l.unit_price, 2) when p_basis = 'shipped' then round(l.qty_shipped * l.unit_price, 2) else public.so_line_total(l) end as amt,   -- ⓐ1: 보낸 수량 기준은 round(qty_shipped × unit_price, 2)(so_line_total 과 같은 식 · 수량만 다르다) · doc-1b2: 덮어쓴 수량도 같은 식
                             public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount) as sc_unit) a                      -- surcharge-2a(묶음 1 · 2): 개당(센트) · 수량은 물건값(amt)과 같은 것
  cross join lateral (select public.so_line_surcharge_total(a.sc_unit, a.qty) as sc_amt) s
  where l0.so_id = p_so_id;

  if coalesce(v_so.order_discount_pct, 0) > 0 then                                  -- 오더 전체 할인은 제품 줄 합계에 한 번(D6 · 운임 제외) · 세금은 그 줄에 따로(판정 3 · SO-10842 −23.12)
    v_od_amt := -round((v_lines_amt - v_m_amt) * v_so.order_discount_pct / 100, 2);   -- od-1 판정 542 · 543 · 544: 할인 바탕 = 손으로 정한 줄을 뺀 나머지(문턱은 so_order_discount 의 so_lines_total 그대로)
    v_od_tax := public.so_tax_amount(v_od_amt, v_rate);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('line_no', c.line_no, 'name', c.name, 'amount', c.amount, 'tax', public.so_tax_amount(c.amount, v_rate),
                                              'charge_id', c.id, 'description', c.description, 'account_id', c.account_id, 'account_code', c.account_code,
                                              'discount_pct', c.discount_pct, 'discount_amount', c.discount_amount, 'discount', dc.disc, 'discount_tax', public.so_tax_amount(dc.disc, v_rate), 'net', c.amount - dc.disc) order by c.line_no), '[]'::jsonb),   -- fr-1: 운임 줄은 정가 그대로(amount · tax) + 할인 칸
         coalesce(sum(public.so_tax_amount(c.amount, v_rate)), 0), coalesce(sum(c.amount), 0),
         coalesce(sum(dc.disc), 0), coalesce(sum(public.so_tax_amount(dc.disc, v_rate)), 0),                                                                      -- fr-1 판정 354: 할인 세금은 할인 줄마다 따로 반올림(174.26 · 13% · 50% → 22.65 − 11.33 = 11.32)
         coalesce(jsonb_agg(jsonb_build_object('kind', 'charge_discount', 'charge_id', c.id, 'line_no', c.line_no, 'name', c.name || ' discount', 'discount_pct', c.discount_pct, 'discount_amount', c.discount_amount,
                                               'amount', -dc.disc, 'tax', -public.so_tax_amount(dc.disc, v_rate)) order by c.line_no) filter (where dc.disc > 0), '[]'::jsonb)                        -- fr-1 판정 352: 할인 줄(인보이스가 두 줄로 펼칠 재료 · fr-2 · 계정은 inv_config so_freight_discount_account_code)
    into v_chg, v_chg_tax, v_chg_amt, v_chd_amt, v_chd_tax, v_chd
  from (select c0.id, c0.line_no, c0.name, c0.description, c0.amount, c0.account_id, c0.account_code, c0.discount_pct, c0.discount_amount                                   -- doc-1b2: 운임 덮어쓰기(p_over->'charges' — 마무리 화면이 고친 · 더한 운임을 쓰기 전의 값으로) · 없으면 so_charge 그대로
          from public.so_charge c0 where c0.so_id = p_so_id and not exists (select 1 from jsonb_array_elements(coalesce(p_over->'charges', '[]'::jsonb)) x where nullif(x->>'charge_id', '') = c0.id::text)
        union all
        select nullif(x->>'charge_id', '')::uuid, coalesce(c1.line_no, (select coalesce(max(c2.line_no), 0) from public.so_charge c2 where c2.so_id = p_so_id) + x.ord::int),
               coalesce(x->>'name', c1.name), case when x ? 'description' then nullif(x->>'description', '') else c1.description end, coalesce((x->>'amount')::numeric, c1.amount),
               coalesce(nullif(x->>'account_id', '')::uuid, (select a.id from public.ref_account a where a.code = x->>'account_code'), c1.account_id), coalesce(x->>'account_code', c1.account_code),
               case when x ? 'discount_pct' then nullif(x->>'discount_pct', '')::numeric else c1.discount_pct end, case when x ? 'discount_amount' then nullif(x->>'discount_amount', '')::numeric else c1.discount_amount end
          from jsonb_array_elements(coalesce(p_over->'charges', '[]'::jsonb)) with ordinality x(x, ord) left join public.so_charge c1 on c1.id = nullif(x->>'charge_id', '')::uuid and c1.so_id = p_so_id) c
  cross join lateral (select public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount) as disc) dc;                                                    -- fr-1: 할인액 식 한 곳 · 운임도 배송지 주의 규칙 · 줄마다(판정 6)

  return jsonb_build_object(
    'so_number', v_so.so_number, 'on', v_on, 'basis', p_basis, 'source', v_source, 'rule', v_pick,
    'lines', v_lines, 'order_discount', jsonb_build_object('pct', v_so.order_discount_pct, 'amount', v_od_amt, 'tax', v_od_tax, 'basis', v_lines_amt - v_m_amt), 'charges', v_chg, 'charge_discounts', v_chd,   -- fr-1
    'totals', jsonb_build_object('lines_amount', v_lines_amt, 'lines_tax', v_lines_tax, 'order_discount_amount', v_od_amt, 'order_discount_tax', v_od_tax, 'discount_basis_amount', v_lines_amt - v_m_amt, 'manual_lines_amount', v_m_amt,   -- od-1
                                 'charges_amount', v_chg_amt, 'charges_tax', v_chg_tax,
                                 'charges_discount_amount', v_chd_amt, 'charges_discount_tax', v_chd_tax, 'charges_net_amount', v_chg_amt - v_chd_amt,   -- fr-1 판정 352 · 354: 새 열쇠(charges_amount 는 정가 합 그대로)
                                 'surcharge_amount', v_sc_amt, 'surcharge_tax', v_sc_tax,                                                     -- surcharge-2a(묶음 3): 물건값(lines_amount)과 따로 · 오더 할인 기준 밖
                                 'taxable_amount', v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt,                                                                          -- fr-1: 운임 할인을 뺀다
                                 'tax', case when v_rate is null then null else v_lines_tax + v_od_tax + v_chg_tax - v_chd_tax + v_sc_tax end,                                         -- fr-1 판정 354
                                 'total', case when v_rate is null then null else v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt + v_lines_tax + v_od_tax + v_chg_tax - v_chd_tax + v_sc_tax end),   -- fr-1
    'warnings', v_warn);
end;
$$;

-- ═══ ③ so_detail 재발행 — 원본 20261007171939_fr_1_freight_discount.sql:577 바이트 + 바뀐 줄(줄 manual · 할인 금액을 so_tax_preview 에서 · totals.discount_basis_amount) ═══
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
  v_chd    numeric := 0;                                                     -- fr-1 판정 352: 운임 할인 합 — so_tax_preview totals 에서(식 한 곳)
  v_warn     text[];
  v_tax      jsonb;  v_tw text[];                              -- 세금 ② — so_tax_preview
  v_basis    text;  v_inv jsonb;  v_inv_hist jsonb;  v_removed int;  v_qty_removed numeric;   -- ⓐ2 — 보낸 수량 기준 · 인보이스 · 뺀 몫
  v_bal      jsonb;                                            -- ⓑ2 — 청구처 손님 잔액(그 통화 행)
  v_rule     record;  v_rule_j jsonb;                          -- dsc-3a 판정 311 — manual 인데 규칙 쪽이 더 크면 경고
  v_cp       jsonb;                                            -- dsc-3b 판정 329 — 붙은 쿠폰
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found';
  end if;
  select c.name into v_cust from public.customer c where c.id = v_so.customer_id;

  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('manual', public.so_line_manual(l), 'total', public.so_line_total(l), 'no_price', l.unit_price is null, 'free', l.free_reason is not null, 'shipped_total', round(l.qty_shipped * l.unit_price, 2), 'removed', l.qty_removed > 0,
                                                              'surcharge_unit', public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), 'surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_ordered), 'shipped_surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_shipped),   -- surcharge-2a(묶음 1 · 2 · total · shipped_total 과 같은 수량)
                                                              'qty_credited', (select coalesce(sum(cl.qty_returned), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_line_id = l.id and c.status = 'issued'),   -- ⓒ2
                                                              'deal_ended', l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date),
                                                              'is_combo', exists (select 1 from public.so_line c where c.combo_line_id = l.id),                                                           -- asm-2a(묶음 2 · 5): 콤보 줄 · 구성품 줄(combo_line_id · combo_qty 는 to_jsonb(l) 에 있다)
                                                              'combo_sku', (select c.sku from public.so_line c where c.id = l.combo_line_id)) order by l.line_no), '[]'::jsonb),
         count(*) filter (where l.combo_line_id is null), count(*) filter (where l.unit_price is null), count(*) filter (where l.free_reason is not null), public.so_lines_total(p_so_id),   -- dsc-3a 판정 310: 기준 금액 식 한 곳
         count(*) filter (where l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)),
         count(*) filter (where l.qty_removed > 0), coalesce(sum(l.qty_removed), 0)
    into v_lines, v_lines_n, v_no_price, v_free, v_lines_total, v_deal_ended, v_removed, v_qty_removed
  from public.so_line l where l.so_id = p_so_id;

  select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object('discount', public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount), 'net', c.amount - public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount)) order by c.line_no), '[]'::jsonb), count(*), coalesce(sum(c.amount), 0)   -- fr-1: 할인액 · 순 운임(식 한 곳)
    into v_charges, v_charges_n, v_charges_total
  from public.so_charge c where c.so_id = p_so_id;

  -- 오더 전체 할인(D6) — 제품 줄 합계에 한 번 · round 2(SO-10842 실물) · 운임은 기준에 없다
  -- od-1 판정 542 ~ 544: 오더 할인 금액은 so_tax_preview 가 센 값(손으로 정한 줄을 뺀 바탕 · 식 한 곳) — 아래 v_tax 뒤에서 읽는다(ordered · shipped 둘 다)

  -- 세금(세금 ② · 판정 8) — 오더에 고른 규칙(manual|ship_to)으로 줄마다 · 규칙 없으면 tax null + 경고 tax_rule_missing
  v_basis := case when v_so.status in ('shipped', 'fulfilled') then 'shipped' else 'ordered' end;   -- ⓐ2: 나간 뒤에는 보낸 수량이 금액(뺀 몫·pick_short 제외 · 인보이스가 정본 8-c) · ⓑ2: invoiced 값 없음(판정 1)
  v_tax := public.so_tax_preview(p_so_id, null, null, v_basis);
  v_od_amt := -coalesce((v_tax->'totals'->>'order_discount_amount')::numeric, 0);                                                                       -- od-1: 양수(so_detail 의 모양) · 식은 so_tax_preview 한 곳
  v_sc_amt := coalesce((v_tax->'totals'->>'surcharge_amount')::numeric, 0);  v_sc_tax := coalesce((v_tax->'totals'->>'surcharge_tax')::numeric, 0);   -- surcharge-2a(묶음 3 · 4)
  v_chd := coalesce((v_tax->'totals'->>'charges_discount_amount')::numeric, 0);                                                                          -- fr-1 판정 352(세금은 v_tax 의 tax 가 이미 뺐다 · 354)
  if v_basis = 'shipped' then
    v_lines_total := (v_tax->'totals'->>'lines_amount')::numeric;
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
  if v_so.status = 'draft' and v_so.order_discount_source = 'manual' then                                          -- dsc-3a 판정 282 · 311: manual(0 포함)은 그대로 + 규칙 쪽이 더 크면 경고
    select * into v_rule from public.so_order_discount(p_so_id);
    if coalesce(v_rule.pct, 0) > coalesce(v_so.order_discount_pct, 0) then
      v_warn := array_append(v_warn, 'order_discount_rule_now_better');
      v_rule_j := jsonb_build_object('rule_pct', v_rule.pct, 'rule_deal_id', v_rule.deal_id, 'manual_pct', v_so.order_discount_pct);
    end if;
  end if;

  v_cp := public.so_coupon_info(v_so);
  if v_cp is not null and v_cp->>'status' <> 'won' then v_warn := array_append(v_warn, 'coupon_not_used'); end if;   -- dsc-3b 판정 329

  return jsonb_build_object(
    'so', to_jsonb(v_so),
    'customer_name', v_cust,
    'lines', v_lines,
    'charges', v_charges,
    'totals', jsonb_build_object('basis', v_basis, 'lines', v_lines_n, 'combo_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and exists (select 1 from public.so_line c where c.combo_line_id = x.id)),
                                 'component_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and x.combo_line_id is not null), 'lines_removed', v_removed, 'qty_removed', v_qty_removed, 'lines_total', v_lines_total, 'lines_without_price', v_no_price, 'free_lines', v_free,
                                 'order_discount_pct', v_so.order_discount_pct, 'order_discount_source', v_so.order_discount_source, 'order_discount_deal_id', v_so.order_discount_deal_id,
                                 'order_discount_amount', v_od_amt, 'lines_after_discount', v_lines_total - v_od_amt, 'discount_basis_amount', coalesce((v_tax->'totals'->>'discount_basis_amount')::numeric, 0),   -- od-1
                                 'charges', v_charges_n, 'charges_total', v_charges_total,
                                 'charges_discount_amount', v_chd, 'charges_net_total', v_charges_total - v_chd,                            -- fr-1 판정 352: charges_total 은 정가 합 그대로 · 새 열쇠
                                 'surcharge_amount', v_sc_amt, 'surcharge_tax', v_sc_tax,                                        -- surcharge-2a — 물건값 · 오더 할인 기준 밖(묶음 3)
                                 'order_total', v_lines_total - v_od_amt + v_charges_total - v_chd + v_sc_amt,                                    -- fr-1: 운임 할인을 뺀다
                                 'tax_rule', v_so.tax_rule, 'tax_rule_source', v_tax->>'source', 'tax', v_tax->'totals'->'tax',
                                 'order_total_with_tax', case when v_tax->'totals'->>'tax' is null then null else v_lines_total - v_od_amt + v_charges_total - v_chd + v_sc_amt + (v_tax->'totals'->>'tax')::numeric end),   -- fr-1
    'tax', v_tax,
    'invoice', v_inv,
    'invoice_history', v_inv_hist,
    'customer_balance', v_bal,
    'order_discount_rule', v_rule_j,
    'coupon', v_cp,
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ④ so_totals_many 재발행 — 원본 20261007171939_fr_1_freight_discount.sql:688 바이트 + 바뀐 줄 하나(할인 금액을 so_tax_preview 에서 · 반환 모양 무변 · 권한 · comment 그대로) ═══
create or replace function public.so_totals_many(p_so_ids uuid[])
  returns table (so_id uuid, basis text, lines_total numeric, order_discount_amount numeric, charges_total numeric, charges_discount_amount numeric, surcharge_amount numeric, tax numeric, order_total numeric, order_total_with_tax numeric)   -- fr-1: charges_discount_amount 열 하나(charges_total 뒤)
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_ids uuid[];
  v_r   record;
  v_tax jsonb;
  v_lt  numeric;  v_od numeric;  v_chg numeric;  v_sc numeric;  v_t numeric;  v_b text;
  v_chd numeric;                                                                                                     -- fr-1 판정 352: 운임 할인 합(so_tax_preview totals · so_detail 과 같은 자리)
begin
  if p_so_ids is null then return; end if;
  select array_agg(distinct x) into v_ids from unnest(p_so_ids) x where x is not null;                            -- 중복 · null 은 센다 · 한 오더는 한 행
  if v_ids is null then return; end if;
  if cardinality(v_ids) > 200 then
    raise exception 'so_totals_many takes at most 200 order ids at a time (got %) — nothing was read', cardinality(v_ids);
  end if;
  for v_r in select s.id, s.status, s.order_discount_pct from public.so s where s.id = any (v_ids) order by s.id loop   -- RLS 가 숨긴 오더 · 없는 id 는 여기서 빠진다(행 없음)
    v_b   := case when v_r.status in ('shipped', 'fulfilled') then 'shipped' else 'ordered' end;                    -- so_detail: 나간 뒤에는 보낸 수량이 금액(ⓐ2)
    v_tax := public.so_tax_preview(v_r.id, null, null, v_b);                                                        -- so_detail 과 같은 호출(오늘 · 오더에 고른 규칙 · basis)
    v_lt  := case when v_b = 'shipped' then (v_tax->'totals'->>'lines_amount')::numeric else public.so_lines_total(v_r.id) end;   -- so_detail: ordered 는 so_lines_total(판정 310) · shipped 는 tax 의 lines_amount
    v_od  := -coalesce((v_tax->'totals'->>'order_discount_amount')::numeric, 0);                                      -- od-1 판정 542 ~ 544: so_detail 과 같이 so_tax_preview 가 센 값(손으로 정한 줄을 뺀 바탕 · 식 한 곳)
    select coalesce(sum(c.amount), 0) into v_chg from public.so_charge c where c.so_id = v_r.id;                     -- so_detail: charges_total
    v_sc  := coalesce((v_tax->'totals'->>'surcharge_amount')::numeric, 0);                                          -- so_detail: surcharge-2a — tax totals 에서
    v_chd := coalesce((v_tax->'totals'->>'charges_discount_amount')::numeric, 0);                                   -- fr-1: so_detail 과 같은 식
    v_t   := (v_tax->'totals'->>'tax')::numeric;                                                                    -- 세금 규칙 없으면 null
    so_id := v_r.id;  basis := v_b;  lines_total := v_lt;  order_discount_amount := v_od;  charges_total := v_chg;  charges_discount_amount := v_chd;  surcharge_amount := v_sc;  tax := v_t;   -- fr-1
    order_total := v_lt - v_od + v_chg - v_chd + v_sc;                                                                                      -- fr-1: 운임 할인을 뺀다
    order_total_with_tax := case when v_t is null then null else v_lt - v_od + v_chg - v_chd + v_sc + v_t end;                              -- fr-1
    return next;
  end loop;
end;
$$;

-- ═══ ⑤ so_credit_issue 재발행 — 원본 20261007181109_fr_3_freight_discount_credit.sql:56 바이트 + 바뀐 줄 둘(오더 할인 거울 — M 줄의 환불액은 바탕에서 뺀다) ═══
create or replace function public.so_credit_issue(p jsonb, p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_reasons   constant text[] := array['customer_return','damaged','billing_error','other'];
  c_nr        constant text[] := array['damaged','b_grade','not_returned','other'];
  v_staff     uuid;
  v_on        date;
  v_reason    text;
  v_inv       public.so_invoice%rowtype;
  v_c         public.customer%rowtype;
  v_cur       public.ref_currency%rowtype;
  v_w         public.ref_warehouse%rowtype;
  v_rule      public.ref_tax_rule%rowtype;
  v_cr        public.so_credit%rowtype;
  v_il        public.so_invoice_line%rowtype;
  v_io        public.so_invoice_order%rowtype;
  v_pr        public.product%rowtype;
  v_bin       public.ref_bin%rowtype;
  v_acct      public.ref_account%rowtype;
  v_cin7      boolean := false;
  v_cin7_inv  text;  v_cin7_ord text;  v_cin7_date date;
  v_cust      uuid;
  v_origin_on date;
  v_wh        uuid;
  v_first_io  public.so_invoice_order%rowtype;
  v_fee_days  int;  v_fee_pct numeric;  v_fee_acct_code text;
  v_lines     jsonb := '[]'::jsonb;
  v_ln        int := 0;
  v_kind      text;
  v_qty       numeric;  v_already numeric;  v_unit numeric;  v_amount numeric;  v_rate numeric;  v_tax numeric;
  v_bin_name  text;  v_bin_id uuid;  v_nr text;  v_nr_note text;  v_desc text;  v_acct_id uuid;  v_acct_code text;
  v_product_id uuid;  v_so_line_id uuid;  v_sku text;  v_il_id uuid;
  v_lines_amt numeric := 0;  v_fee_amt numeric := 0;  v_tax_amt numeric := 0;  v_product_amt numeric := 0;
  v_od_amt    numeric := 0;  v_od record;  v_od_il public.so_invoice_line%rowtype;                                      -- dsc-3b 판정 325 — 오더 할인 몫(인보이스-오더마다 음수 줄 하나)
  v_sc        public.so_invoice_line%rowtype;  v_sc_amt numeric := 0;  v_sc_line numeric;  v_sc_tax numeric;  v_sc_already numeric;   -- surcharge-2b(묶음 7)
  v_fd        public.so_invoice_line%rowtype;  v_fd_amt numeric := 0;  v_fd_line numeric := 0;  v_fd_tax numeric;  v_fd_already numeric;  v_fd_inv numeric;   -- fr-3 판정 355: 운임 할인 되돌림(인보이스 charge_discount 줄 · 같은 비율 · 끝수는 마지막에)
  v_rates     numeric[] := '{}';  v_first_rate numeric;
  v_fee_lines int := 0;  v_restock_n int := 0;
  v_fee_sugg  jsonb;
  v_warn      text[] := '{}';
  v_ledger    jsonb;
  v_est       numeric;  v_est_qty numeric;
  v_ask       numeric;
  x           jsonb;
  e           jsonb;
  -- asm-2b2(묶음 7 · 판정 245): 콤보 인보이스 줄의 반품 — 콤보 크레딧 줄(금액 · qty = 콤보 수 · 칸 · 사유 없음 · combo_components) + 구성품 크레딧 줄(금액 0 · qty = n × combo_qty · 제 칸 또는 사유 · combo_credit_line_id) · 구성품 하나만의 상품 줄은 거부
  v_combo     jsonb;  cj jsonb;  v_cov jsonb;  v_def_bin text;  v_def_nr text;  v_def_note text;  v_cpr public.product%rowtype;  v_cq numeric;  v_idmap jsonb := '{}'::jsonb;  v_parent_ln int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — 발행은 manager 이상(판정 3)
  v_staff := public.so_current_staff();
  v_on := coalesce(nullif(p->>'issued_on', '')::date, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Credit date % is in the future — nothing was saved', v_on; end if;
  v_reason := nullif(trim(p->>'reason'), '');
  if v_reason is null or v_reason <> all (c_reasons) then raise exception 'reason must be one of customer_return, damaged, billing_error, other — nothing was saved'; end if;
  if v_reason = 'other' and nullif(trim(p->>'note'), '') is null then raise exception 'reason other needs a note — nothing was saved'; end if;
  if p->'lines' is null or jsonb_typeof(p->'lines') <> 'array' or jsonb_array_length(p->'lines') = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  -- 설정(판정 5·7)
  select nullif(k.value, '')::int into v_fee_days from public.inv_config k where k.key = 'so_credit_restock_fee_days';
  select nullif(k.value, '')::numeric into v_fee_pct from public.inv_config k where k.key = 'so_credit_restock_fee_pct';
  select nullif(k.value, '') into v_fee_acct_code from public.inv_config k where k.key = 'so_credit_restock_fee_account_code';

  -- 원본 — IMS 인보이스 또는 Cin7 번호 원문(판정 6 · 0-4)
  if nullif(p->>'invoice_id', '') is not null then
    select * into v_inv from public.so_invoice i where i.id = (p->>'invoice_id')::uuid for update;
    if not found then raise exception 'Invoice not found — nothing was saved'; end if;
    if v_inv.status <> 'issued' then raise exception 'Invoice % is % — credit the live invoice, not a cancelled one — nothing was saved', v_inv.invoice_number, v_inv.status; end if;
    v_cust := v_inv.bill_to_customer_id;  v_origin_on := v_inv.issued_on;
    select * into v_cur from public.ref_currency c where c.id = v_inv.currency_id;
    select o.* into v_first_io from public.so_invoice_order o where o.invoice_id = v_inv.id order by o.so_number limit 1;
    select s.location_id into v_wh from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id order by o.so_number limit 1;
  elsif p->'cin7' is not null and jsonb_typeof(p->'cin7') = 'object' then
    v_cin7 := true;
    v_cin7_inv := nullif(trim(p->'cin7'->>'invoice_number'), '');  v_cin7_ord := nullif(trim(p->'cin7'->>'order_number'), '');  v_cin7_date := nullif(p->'cin7'->>'invoice_date', '')::date;
    if v_cin7_inv is null then raise exception 'A Cin7 credit needs cin7.invoice_number (the paper number) — nothing was saved'; end if;
    if nullif(p->>'customer_id', '') is null then raise exception 'A Cin7 credit needs customer_id — nothing was saved'; end if;
    v_cust := (p->>'customer_id')::uuid;  v_origin_on := v_cin7_date;
    if v_cin7_ord is null then v_warn := array_append(v_warn, 'origin_sale_unknown'); end if;
    select * into v_cur from public.ref_currency c
     where c.id = coalesce(nullif(p->>'currency_id', '')::uuid, (select c2.id from public.ref_currency c2 where c2.code = upper(nullif(trim(p->>'currency_code'), ''))), (select c3.currency_id from public.customer c3 where c3.id = v_cust));
    if v_cur.id is null then raise exception 'Currency is required — the customer has no default currency — nothing was saved'; end if;
    if nullif(trim(p->>'tax_rule'), '') is null then raise exception 'A Cin7 credit needs tax_rule (an active sale tax rule name) — nothing was saved'; end if;
    select * into v_rule from public.ref_tax_rule r where r.name = trim(p->>'tax_rule') and r.direction = 'sale' and r.is_active;
    if v_rule.id is null then raise exception 'Tax rule % is not an active sale rule — nothing was saved', trim(p->>'tax_rule'); end if;
    select c.default_location_id into v_wh from public.customer c where c.id = v_cust;
  else
    raise exception 'Give invoice_id (an IMS invoice) or cin7 {invoice_number, order_number, invoice_date} — nothing was saved';
  end if;
  select * into v_c from public.customer c where c.id = v_cust for update;         -- 청구처 손님 행 잠금(잔액 직렬화 · ⓑ 와 같은 자물쇠)
  if not found then raise exception 'Customer not found — nothing was saved'; end if;

  -- 창고(반품을 받은 창고 · ⬜4) — 지정 → 원 판매 창고 → 손님 기본 창고 → 거부
  v_wh := coalesce(nullif(p->>'warehouse_id', '')::uuid, v_wh);
  if v_wh is null then raise exception 'warehouse_id is required — where were the goods returned to? — nothing was saved'; end if;
  select * into v_w from public.ref_warehouse w where w.id = v_wh;
  if not found then raise exception 'Warehouse not found — nothing was saved'; end if;
  if not v_w.is_active then raise exception 'Warehouse % is inactive — nothing was saved', v_w.name; end if;

  -- 줄 — 첫 바퀴: product · freight · tax · other(수수료는 둘째 바퀴 · 제품 합이 먼저 필요하다)
  for x in select t from jsonb_array_elements(p->'lines') t loop
    v_kind := nullif(trim(x->>'kind'), '');
    if v_kind = 'surcharge' then raise exception 'Surcharge lines are added automatically from the returned product lines — do not send them — nothing was saved'; end if;   -- surcharge-2b(D-3 · 자동만)
    if v_kind = 'freight_discount' then raise exception 'Freight discount lines are added automatically from the returned freight line — do not send them — nothing was saved'; end if;   -- fr-3 판정 355(자동만)
    if v_kind is null or v_kind not in ('product','freight','tax','other','restocking_fee') then raise exception 'Line kind must be one of product, freight, tax, other, restocking_fee — nothing was saved'; end if;
    if v_kind = 'restocking_fee' then v_fee_lines := v_fee_lines + 1; continue; end if;
    v_il := null;  v_io := null;  v_pr := null;  v_bin := null;  v_acct := null;  v_fd := null;  v_fd_line := 0;                                                           -- fr-3
    v_qty := null;  v_unit := null;  v_rate := null;  v_bin_id := null;  v_bin_name := null;  v_nr := null;  v_nr_note := null;  v_product_id := null;  v_so_line_id := null;  v_sku := null;  v_il_id := null;  v_desc := null;  v_est := null;
    v_acct_id := nullif(x->>'account_id', '')::uuid;
    if v_acct_id is not null then
      select * into v_acct from public.ref_account a where a.id = v_acct_id;
      if v_acct.id is null then raise exception 'Account % not found — nothing was saved', v_acct_id; end if;
    end if;

    if v_kind = 'product' then
      v_qty := nullif(x->>'qty_returned', '')::numeric;
      if v_qty is null or v_qty <= 0 then raise exception 'A product line needs qty_returned > 0 — nothing was saved'; end if;
      if v_cin7 then
        v_sku := nullif(trim(x->>'sku'), '');
        if v_sku is null then raise exception 'A Cin7 product line needs sku — nothing was saved'; end if;
        select * into v_pr from public.product pr where pr.sku = v_sku;
        if v_pr.id is null then raise exception 'Product % not found — nothing was saved', v_sku; end if;
        v_unit := nullif(x->>'unit_price', '')::numeric;
        if v_unit is null or v_unit < 0 then raise exception 'A Cin7 product line needs unit_price (the price on that invoice) — nothing was saved'; end if;
        v_rate := v_rule.rate_pct;  v_product_id := v_pr.id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_pr.name);
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_98_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then
          if exists (select 1 from public.so_line cl2 join public.so_invoice_order io2 on io2.so_id = cl2.so_id                                  -- asm-2b2(판정 245): 구성품은 인보이스 줄이 없다 — 하나만 돌려받는 길은 「other」 금액 줄
                      where io2.invoice_id = v_inv.id and cl2.combo_line_id is not null and (cl2.id = nullif(x->>'so_line_id', '')::uuid or cl2.sku = nullif(trim(x->>'sku'), ''))) then
            raise exception 'Line % is a component of a combo on invoice % — a combo is credited whole (credit the combo line); for one component use an other line (amount only, no stock) — nothing was saved', coalesce(nullif(trim(x->>'sku'), ''), x->>'so_line_id'), v_inv.invoice_number;
          end if;
          raise exception 'An IMS product line needs so_invoice_line_id (the invoice line being returned) — nothing was saved';
        end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'product';
        if v_il.id is null then raise exception 'Invoice line % is not a product line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        select coalesce(sum(cl.qty_returned), 0) into v_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id
         where cl.so_invoice_line_id = v_il.id and c.status = 'issued';
        select coalesce(sum((t->>'qty_returned')::numeric), 0) into v_ask from jsonb_array_elements(p->'lines') t where t->>'kind' = 'product' and nullif(t->>'so_invoice_line_id', '')::uuid = v_il.id;
        if v_already + v_ask > v_il.qty then
          raise exception 'Invoice % line % (%): % of % already credited and % asked now — only % can still be returned — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, v_already, v_il.qty, v_ask, v_il.qty - v_already;
        end if;
        v_unit := v_il.unit_price;  v_rate := v_io.rate_pct;  v_sku := v_il.sku;  v_so_line_id := v_il.so_line_id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        select sl.product_id into v_product_id from public.so_line sl where sl.id = v_il.so_line_id;
        select * into v_pr from public.product pr where pr.id = v_product_id;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      v_amount := round(v_qty * coalesce(v_unit, 0), 2);  v_tax := public.so_tax_amount(v_amount, v_rate);
      v_product_amt := v_product_amt + v_amount;  v_rates := array_append(v_rates, v_rate);
      -- 돌아오나(판정 1) — not_restocked_reason 이 있으면 안 돌아옴 · 아니면 칸(지정 → ims_last_bin → 거부 · '' 불허 · ⬜4)
      v_combo := case when v_cin7 then null else nullif(v_il.combo_components, 'null'::jsonb) end;
      v_nr := nullif(trim(x->>'not_restocked_reason'), '');
      if v_combo is not null then                                                                                 -- asm-2b2: 콤보 줄 자체는 칸 · 사유가 없다 — 줄에 적은 칸 · 사유는 구성품 전부의 기본값(components[] 가 덮는다)
        v_def_nr := v_nr;  v_def_note := nullif(trim(x->>'not_restocked_note'), '');  v_def_bin := nullif(trim(x->>'restock_bin'), '');  v_nr := null;
        if v_def_nr is not null and v_def_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
        if v_def_nr = 'other' and v_def_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
        if exists (select 1 from jsonb_array_elements(coalesce(nullif(x->'components', 'null'::jsonb), '[]'::jsonb)) cx where not exists (select 1 from jsonb_array_elements(v_combo) cy where cy->>'sku' = nullif(trim(cx->>'sku'), ''))) then
          raise exception 'components[] of combo % names a sku that is not part of that combo on invoice % — nothing was saved', v_sku, v_inv.invoice_number;
        end if;
      elsif v_nr is not null then
        if v_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
        v_nr_note := nullif(trim(x->>'not_restocked_note'), '');
        if v_nr = 'other' and v_nr_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
      else
        v_bin_name := nullif(trim(x->>'restock_bin'), '');
        if v_bin_name is null then
          v_bin_name := public.ims_last_bin(array[coalesce(v_pr.parent_product_id, v_pr.id)], v_w.id) -> coalesce(v_pr.parent_product_id, v_pr.id)::text ->> 'bin';
          if v_bin_name is null then raise exception 'No bin known for % in % — pick a restock bin (or mark the line not restocked) — nothing was saved', v_sku, v_w.name; end if;
        end if;
        select * into v_bin from public.ref_bin rb where rb.warehouse_id = v_w.id and rb.name = v_bin_name;
        if v_bin.id is null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bin_name, v_w.name; end if;
        if not v_bin.is_active then v_warn := array_append(v_warn, 'inactive_bin:' || v_bin_name); end if;
        v_bin_id := v_bin.id;  v_restock_n := v_restock_n + 1;
        -- 원가 복원 예상(미리 보기 · 원 판매의 소비 기록 평균 × EA · 없으면 null)
        select sum(cs.qty * cs.unit_cost) / nullif(sum(cs.qty), 0), sum(cs.qty) into v_est, v_est_qty
          from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
         where cs.doc_type = 'sale' and cs.reason = 'sale' and l.sku = coalesce((select pp.sku from public.product pp where pp.id = v_pr.parent_product_id), v_pr.sku)
           and cs.doc_number = case when v_cin7 then v_cin7_ord else (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id)) end;
      end if;
    elsif v_kind = 'freight' then
      if v_cin7 then
        v_amount := nullif(x->>'amount', '')::numeric;  v_rate := v_rule.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Freight');
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_99_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then raise exception 'An IMS freight line needs so_invoice_line_id (the charge line) — nothing was saved'; end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'charge';
        if v_il.id is null then raise exception 'Invoice line % is not a charge line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        v_amount := coalesce(nullif(x->>'amount', '')::numeric, v_il.amount);  v_rate := v_io.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        select coalesce(sum(cl.amount), 0) into v_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_il.id and c.status = 'issued';
        if v_already + v_amount > v_il.amount then raise exception 'Invoice % charge % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_already, v_il.amount, v_il.amount - v_already; end if;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      if v_amount is null or v_amount < 0 then raise exception 'A freight line needs amount ≥ 0 — nothing was saved'; end if;
      v_tax := public.so_tax_amount(v_amount, v_rate);
      if not v_cin7 then                                                                                             -- fr-3 판정 355: 그 운임 줄에 할인 줄(charge_discount · 같은 so_charge_id)이 있으면 같은 비율로 되돌린다
        select * into v_fd from public.so_invoice_line d where d.invoice_id = v_inv.id and d.kind = 'charge_discount' and d.so_charge_id = v_il.so_charge_id;
        if v_fd.id is not null then
          v_fd_inv := -v_fd.amount;                                                                                    -- 인보이스 할인(양수)
          select coalesce(-sum(cl.amount), 0) into v_fd_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_fd.id and c.status = 'issued';   -- 이미 돌려준 할인(양수)
          v_fd_line := case when v_already + v_amount = v_il.amount then v_fd_inv - v_fd_already                             -- 끝수 규칙: 정가를 다 돌려주는 마지막 줄은 남은 할인 전부(합 = 인보이스 할인 · 정확히)
                            else least(round(v_amount * v_fd_inv / v_il.amount, 2), v_fd_inv - v_fd_already) end;                 -- 그 밖은 round(x × 비율, 2) · 남은 할인을 넘지 않는다
          if (v_already - v_fd_already) + (v_amount - v_fd_line) > v_il.amount - v_fd_inv or v_fd_line > v_amount then         -- 순액 한도: 돌려준 순액 합 ≤ 손님이 낸 순액 · 남은 할인이 이번 운임보다 크면(앞 크레딧이 할인 없이 정가를 가져간 옛 모양) 음수 순액이 되므로 거부(정가 한도 검사는 위에 그대로)
            raise exception 'Invoice % charge % : the customer paid % net (% less % discount) — % net already credited and % asked now — only % left — nothing was saved',
              v_inv.invoice_number, v_il.line_no, v_il.amount - v_fd_inv, v_il.amount, v_fd_inv, v_already - v_fd_already, v_amount - v_fd_line, (v_il.amount - v_fd_inv) - (v_already - v_fd_already);
          end if;
        end if;
      end if;
    elsif v_kind = 'tax' then
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null or v_amount < 0 then raise exception 'A tax line needs amount ≥ 0 (the tax being returned) — nothing was saved'; end if;
      v_rate := null;  v_tax := 0;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Tax');
      if v_acct.id is null then
        select * into v_acct from public.ref_account a where a.id = (case when v_cin7 then v_rule.account_id else (select r.account_id from public.ref_tax_rule r where r.id = v_first_io.tax_rule_id) end);
      end if;
    else   -- other
      v_amount := nullif(x->>'amount', '')::numeric;  v_desc := nullif(trim(x->>'description'), '');
      if v_amount is null or v_amount < 0 then raise exception 'An other line needs amount ≥ 0 — nothing was saved'; end if;
      if v_desc is null then raise exception 'An other line needs a description — nothing was saved'; end if;
      if v_acct.id is null then raise exception 'An other line needs account_id (no default) — nothing was saved'; end if;
      v_rate := case when v_cin7 then v_rule.rate_pct else v_first_io.rate_pct end;  v_tax := public.so_tax_amount(v_amount, v_rate);
    end if;
    v_ln := v_ln + 1;  v_lines_amt := v_lines_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);  v_parent_ln := v_ln;
    v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', v_kind, 'so_invoice_line_id', v_il_id, 'so_line_id', v_so_line_id, 'product_id', v_product_id, 'sku', v_sku, 'description', v_desc,
                                             'qty_returned', v_qty, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                             'unit_price', v_unit, 'amount', v_amount, 'rate_pct', v_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code,
                                             'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_qty * coalesce(v_pr.pack_factor, 1), 6) end,
                                             'combo_components', case when v_kind = 'product' then v_combo end);                                           -- asm-2b2: 콤보 크레딧 줄에 includes(인보이스 줄 사본)
    if v_kind = 'freight' and not v_cin7 and v_fd.id is not null and v_fd_line > 0 then                                   -- fr-3 판정 355 · 352 · 354 · 358: 운임 줄 바로 뒤 할인 되돌림 줄 · 음수 · 세금 따로(줄마다) · 계정 = 인보이스 할인 줄 것
      v_fd_tax := public.so_tax_amount(-v_fd_line, v_io.rate_pct);
      v_ln := v_ln + 1;  v_fd_amt := v_fd_amt - v_fd_line;  v_tax_amt := v_tax_amt + coalesce(v_fd_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'freight_discount', 'so_invoice_line_id', v_fd.id, 'description', v_fd.description,
                                               'amount', -v_fd_line, 'rate_pct', v_io.rate_pct, 'tax_amount', coalesce(v_fd_tax, 0), 'account_id', v_fd.account_id, 'account_code', v_fd.account_code);
    end if;
    if v_kind = 'product' and not v_cin7 then                                                                  -- surcharge-2b(묶음 7): 그 상품의 인보이스 surcharge 줄이 있으면 크레딧 surcharge 줄을 자동으로 · 개당은 인보이스 줄의 것(문서는 문서에서) · 세금은 그 줄 세율로 따로 · 계정 복사 · 물건값(v_lines_amt) · 리스탁킹 피 바탕(v_product_amt) 밖
      select * into v_sc from public.so_invoice_line il where il.invoice_id = v_inv.id and il.kind = 'surcharge' and il.so_line_id = v_il.so_line_id;
      if v_sc.id is not null then
        v_sc_line := public.so_line_surcharge_total(v_sc.unit_price, v_qty);
        select coalesce(sum(cl.amount), 0) into v_sc_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_sc.id and c.status = 'issued';
        if v_sc_already + v_sc_line > v_sc.amount then raise exception 'Invoice % surcharge of line % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_sc_already, v_sc.amount, v_sc.amount - v_sc_already; end if;
        v_sc_tax := public.so_tax_amount(v_sc_line, v_io.rate_pct);
        v_ln := v_ln + 1;  v_sc_amt := v_sc_amt + v_sc_line;  v_tax_amt := v_tax_amt + coalesce(v_sc_tax, 0);
        v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'surcharge', 'so_invoice_line_id', v_sc.id, 'so_line_id', v_sc.so_line_id, 'product_id', v_product_id, 'sku', v_sc.sku, 'description', v_sc.description,
                                                 'qty_returned', v_qty, 'unit_price', v_sc.unit_price, 'amount', v_sc_line, 'rate_pct', v_io.rate_pct, 'tax_amount', coalesce(v_sc_tax, 0), 'account_id', v_sc.account_id, 'account_code', v_sc.account_code);
      end if;
    end if;
    if v_kind = 'product' and v_combo is not null then                                                             -- asm-2b2(묶음 7 · 판정 245): 구성품 크레딧 줄 — 콤보 n 개 ⇒ 구성품마다 n × combo_qty 가 재고로(제 칸 · 또는 안 돌아온 사유) · 금액 0 · 원장(credit_in)은 이 줄들만 · 원가 갈래 ① 은 구성품 SKU 의 소비 기록으로
      for cj in select c2.v from jsonb_array_elements(v_combo) with ordinality c2(v, ord) order by c2.ord loop
        select * into v_cpr from public.product pr where pr.id = nullif(cj->>'product_id', '')::uuid;
        if v_cpr.id is null then select * into v_cpr from public.product pr where pr.sku = cj->>'sku'; end if;
        if v_cpr.id is null then raise exception 'Component % of combo % is not a product any more — nothing was saved', cj->>'sku', v_sku; end if;
        select cx into v_cov from jsonb_array_elements(coalesce(nullif(x->'components', 'null'::jsonb), '[]'::jsonb)) cx where nullif(trim(cx->>'sku'), '') = cj->>'sku' limit 1;
        v_cq := v_qty * (cj->>'qty_per_combo')::numeric;
        v_bin := null;  v_bin_id := null;  v_bin_name := null;  v_est := null;  v_nr_note := null;
        v_nr := coalesce(nullif(trim(v_cov->>'not_restocked_reason'), ''), v_def_nr);
        if v_nr is not null then
          if v_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
          v_nr_note := coalesce(nullif(trim(v_cov->>'not_restocked_note'), ''), v_def_note);
          if v_nr = 'other' and v_nr_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
        else
          v_bin_name := coalesce(nullif(trim(v_cov->>'restock_bin'), ''), v_def_bin);
          if v_bin_name is null then
            v_bin_name := public.ims_last_bin(array[coalesce(v_cpr.parent_product_id, v_cpr.id)], v_w.id) -> coalesce(v_cpr.parent_product_id, v_cpr.id)::text ->> 'bin';
            if v_bin_name is null then raise exception 'No bin known for % (component of combo %) in % — pick a restock bin for it in components[] (or mark it not restocked) — nothing was saved', v_cpr.sku, v_sku, v_w.name; end if;
          end if;
          select * into v_bin from public.ref_bin rb where rb.warehouse_id = v_w.id and rb.name = v_bin_name;
          if v_bin.id is null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bin_name, v_w.name; end if;
          if not v_bin.is_active then v_warn := array_append(v_warn, 'inactive_bin:' || v_bin_name); end if;
          v_bin_id := v_bin.id;  v_restock_n := v_restock_n + 1;
          select sum(cs.qty * cs.unit_cost) / nullif(sum(cs.qty), 0) into v_est
            from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
           where cs.doc_type = 'sale' and cs.reason = 'sale' and l.sku = coalesce((select pp.sku from public.product pp where pp.id = v_cpr.parent_product_id), v_cpr.sku)
             and cs.doc_number = (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id));
        end if;
        v_ln := v_ln + 1;
        v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'product', 'so_invoice_line_id', null, 'so_line_id', nullif(cj->>'so_line_id', '')::uuid, 'product_id', v_cpr.id, 'sku', v_cpr.sku, 'description', coalesce(cj->>'description', v_cpr.name),
                                                 'qty_returned', v_cq, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                                 'unit_price', 0, 'amount', 0, 'rate_pct', v_rate, 'tax_amount', 0, 'account_id', v_acct.id, 'account_code', v_acct.code,
                                                 'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_cq * coalesce(v_cpr.pack_factor, 1), 6) end,
                                                 'combo_parent_line_no', v_parent_ln, 'combo_qty', (cj->>'qty_per_combo')::numeric, 'combo_sku', v_sku);
      end loop;
    end if;
  end loop;

  -- dsc-3b 판정 325 · 316: 인보이스 거울 — 인보이스-오더마다 오더 할인 % 가 있으면 그 오더의 제품 환불액에 음수 줄 하나(세금 따로 · 계정 = 그 인보이스의 order_discount 줄) · surcharge 는 기준 밖(인보이스와 같다) · Cin7 크레딧은 해당 없음
  if not v_cin7 then
    for v_od in
      select io.id as io_id, io.so_number, io.order_discount_pct as pct, io.rate_pct, sum((le->>'amount')::numeric) as amt
      from jsonb_array_elements(v_lines) le join public.so_invoice_line il on il.id = nullif(le->>'so_invoice_line_id', '')::uuid join public.so_invoice_order io on io.id = il.invoice_order_id join public.so_line sl on sl.id = il.so_line_id   -- od-1
      where le->>'kind' = 'product' and coalesce(io.order_discount_pct, 0) > 0 and not public.so_line_manual(sl)   -- od-1 판정 542 · 544: 손으로 정한 줄은 오더 할인을 받지 않았으니 되돌릴 몫도 없다
      group by io.id, io.so_number, io.order_discount_pct, io.rate_pct order by io.so_number
    loop
      v_amount := -round(v_od.amt * v_od.pct / 100, 2);  v_tax := public.so_tax_amount(v_amount, v_od.rate_pct);
      select * into v_od_il from public.so_invoice_line il where il.invoice_order_id = v_od.io_id and il.kind = 'order_discount' limit 1;
      v_ln := v_ln + 1;  v_od_amt := v_od_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'order_discount', 'so_invoice_line_id', v_od_il.id, 'description', format('Order discount %s%% (%s)', v_od.pct, v_od.so_number),
                                               'amount', v_amount, 'rate_pct', v_od.rate_pct, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_od_il.account_id, 'account_code', v_od_il.account_code);
    end loop;
  end if;

  -- 둘째 바퀴 — Restocking fee(판정 4·5·7 · 0-8): 기본 −round(Σ제품 × pct/100, 2) · 계정 = 지정 → 설정 → 거부 · 세율 = 첫 제품 줄(섞이면 경고) · 세금도 음수 · dsc-3b 판정 325: 기준 = 제품 환불액 − 오더 할인 몫(손님이 실제 낸 값)
  v_first_rate := case when v_cin7 then v_rule.rate_pct else v_rates[1] end;
  if v_fee_lines > 0 then
    if v_fee_lines > 1 then raise exception 'Only one restocking_fee line per credit note — nothing was saved'; end if;
    if (select count(distinct r) from unnest(v_rates) r) > 1 then v_warn := array_append(v_warn, 'fee_rate_mixed'); end if;
    for x in select t from jsonb_array_elements(p->'lines') t where t->>'kind' = 'restocking_fee' loop
      v_acct := null;  v_acct_id := nullif(x->>'account_id', '')::uuid;
      if v_acct_id is not null then select * into v_acct from public.ref_account a where a.id = v_acct_id;
      elsif v_fee_acct_code is not null then select * into v_acct from public.ref_account a where a.code = v_fee_acct_code; end if;
      if v_acct.id is null then raise exception 'A restocking fee line needs account_id — no default account is set (inv_config so_credit_restock_fee_account_code) — nothing was saved'; end if;
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null then v_amount := -round((v_product_amt + v_od_amt) * coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct, 0) / 100, 2); end if;   -- dsc-3b 판정 325: v_od_amt 는 음수
      if v_amount > 0 then raise exception 'A restocking fee reduces the credit — amount must be ≤ 0 (got %) — nothing was saved', v_amount; end if;
      v_tax := public.so_tax_amount(v_amount, v_first_rate);
      v_ln := v_ln + 1;  v_fee_amt := v_fee_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'restocking_fee', 'description', coalesce(nullif(trim(x->>'description'), ''), format('Restocking fee %s%%', coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct))),
                                               'amount', v_amount, 'rate_pct', v_first_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code);
    end loop;
  end if;
  -- 알림(판정 5) — 원 인보이스 발행일 + N일이 지났고 수수료 줄이 없으면 「대상」만 알린다(자동으로 붙이지 않는다)
  if v_origin_on is null then v_warn := array_append(v_warn, 'fee_window_unknown');
  elsif v_fee_days is not null and v_on - v_origin_on > v_fee_days and v_fee_lines = 0 and v_product_amt > 0 then
    v_warn := array_append(v_warn, 'restock_fee_window:' || (v_on - v_origin_on)::text);
    v_fee_sugg := jsonb_build_object('days_since_invoice', v_on - v_origin_on, 'pct', v_fee_pct, 'amount', -round((v_product_amt + v_od_amt) * coalesce(v_fee_pct, 0) / 100, 2), 'account_code', v_fee_acct_code);   -- dsc-3b 판정 325
  end if;
  if v_ln = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  if not p_commit then
    return jsonb_build_object('committed', false, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code, 'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                              'origin', case when v_cin7 then jsonb_build_object('cin7_invoice_number', v_cin7_inv, 'cin7_order_number', v_cin7_ord, 'cin7_invoice_date', v_cin7_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct)
                                             else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                              'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_lines_amt, 'order_discount_amount', v_od_amt, 'freight_discount_amount', v_fd_amt, 'fee_amount', v_fee_amt, 'surcharge_amount', v_sc_amt, 'tax_amount', v_tax_amt, 'total', v_lines_amt + v_od_amt + v_fd_amt + v_fee_amt + v_sc_amt + v_tax_amt, 'restock_lines', v_restock_n),
                              'fee_suggested', v_fee_sugg, 'ledger', null, 'warnings', to_jsonb(v_warn));
  end if;

  insert into public.so_credit (customer_id, currency_id, currency_code, invoice_id, cin7_invoice_number, cin7_order_number, cin7_invoice_date, origin_invoice_on, reason, note,
                                warehouse_id, warehouse_name, tax_rule_id, tax_rule, rate_pct, issued_on, issued_by, lines_amount, order_discount_amount, freight_discount_amount, fee_amount, surcharge_amount, tax_amount, total, created_by, updated_by)   -- fr-3
  values (v_cust, v_cur.id, v_cur.code, v_inv.id, v_cin7_inv, v_cin7_ord, v_cin7_date, v_origin_on, v_reason, nullif(trim(p->>'note'), ''),
          v_w.id, v_w.name, v_rule.id, v_rule.name, v_rule.rate_pct, v_on, v_staff, v_lines_amt, v_od_amt, v_fd_amt, v_fee_amt, v_sc_amt, v_tax_amt, v_lines_amt + v_od_amt + v_fd_amt + v_fee_amt + v_sc_amt + v_tax_amt, v_staff, v_staff)   -- fr-3
  returning * into v_cr;
  for e in select t from jsonb_array_elements(v_lines) t loop
    insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, so_line_id, product_id, sku, description, qty_returned, restock_bin_id, restock_bin, not_restocked_reason, not_restocked_note,
                                       unit_price, amount, rate_pct, tax_amount, account_id, account_code, updated_by, combo_credit_line_id, combo_qty, combo_components)
    values (v_cr.id, (e->>'line_no')::int, e->>'kind', nullif(e->>'so_invoice_line_id', '')::uuid, nullif(e->>'so_line_id', '')::uuid, nullif(e->>'product_id', '')::uuid, e->>'sku', e->>'description',
            nullif(e->>'qty_returned', '')::numeric, nullif(e->>'restock_bin_id', '')::uuid, e->>'restock_bin', e->>'not_restocked_reason', e->>'not_restocked_note',
            nullif(e->>'unit_price', '')::numeric, (e->>'amount')::numeric, nullif(e->>'rate_pct', '')::numeric, (e->>'tax_amount')::numeric, nullif(e->>'account_id', '')::uuid, e->>'account_code', v_staff,
            (v_idmap->>(e->>'combo_parent_line_no'))::uuid, nullif(e->>'combo_qty', '')::numeric, nullif(e->'combo_components', 'null'::jsonb))                   -- asm-2b2: 구성품 줄은 앞서 넣은 콤보 줄(line_no → id)에 매단다 · 콤보 줄은 includes 를 든다
    returning id into v_il_id;
    v_idmap := v_idmap || jsonb_build_object((e->>'line_no'), v_il_id);
  end loop;
  if v_restock_n > 0 then
    v_ledger := public.inv_post_credit(v_cr.id, v_on);
    v_warn := v_warn || coalesce((select array_agg(t.w) from jsonb_array_elements_text(coalesce(v_ledger->'warnings', '[]'::jsonb)) as t(w)), '{}');
  end if;

  return jsonb_build_object('committed', true, 'credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', v_cr.status, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code,
                            'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                            'origin', case when v_cin7 then jsonb_build_object('cin7_invoice_number', v_cin7_inv, 'cin7_order_number', v_cin7_ord, 'cin7_invoice_date', v_cin7_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct)
                                           else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                            'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_cr.lines_amount, 'order_discount_amount', v_cr.order_discount_amount, 'freight_discount_amount', v_cr.freight_discount_amount, 'fee_amount', v_cr.fee_amount, 'surcharge_amount', v_cr.surcharge_amount, 'tax_amount', v_cr.tax_amount, 'total', v_cr.total, 'restock_lines', v_restock_n),
                            'fee_suggested', v_fee_sugg, 'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑥ doc_data_invoice 재발행 — 원본 20261019172034_doc_1c_zero_blank_due_now.sql:57 바이트 + 바뀐 줄 하나(neutral 줄에 manual) ═══
create or replace function public.doc_data_invoice(p_kind text, p_invoice_id uuid, p_cfg jsonb) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_inv public.so_invoice%rowtype;
  v_n   jsonb;
begin
  select * into v_inv from public.so_invoice i where i.id = p_invoice_id;
  if v_inv.id is null then raise exception 'Invoice not found'; end if;
  v_n := jsonb_build_object(
    'header', jsonb_build_object('number', v_inv.invoice_number, 'issued_on', v_inv.issued_on, 'due_on', v_inv.due_on, 'payment_term_name', v_inv.payment_term_name, 'currency_code', v_inv.currency_code, 'memo', v_inv.note,
                                 'bill_to_customer_id', v_inv.bill_to_customer_id,
                                 'bill_to', jsonb_build_object('name', v_inv.bill_to_name, 'line1', v_inv.bill_to_line1, 'line2', v_inv.bill_to_line2, 'city', v_inv.bill_to_city, 'state_province', v_inv.bill_to_state_province, 'postal_code', v_inv.bill_to_postal_code, 'country', v_inv.bill_to_country)),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object(
                 'so_number', o.so_number, 'reference', s.ref, 'carrier', s.carrier, 'tracking', s.tracking_number, 'tax_rule', o.tax_rule, 'order_discount_pct', o.order_discount_pct,
                 'ship_to', jsonb_build_object('company', o.ship_to_company, 'contact', o.ship_to_contact, 'phone', o.ship_to_phone, 'line1', o.ship_to_line1, 'line2', o.ship_to_line2, 'city', o.ship_to_city, 'state_province', o.ship_to_state_province, 'postal_code', o.ship_to_postal_code, 'country', o.ship_to_country),
                 'lines', (select coalesce(jsonb_agg(jsonb_build_object('product_id', sl.product_id, 'sku', l.sku, 'description', l.description, 'comment', sl.comments, 'unit', l.unit, 'qty', l.qty, 'list_price', l.list_price, 'discount_pct', l.discount_pct,
                                                                        'unit_price', l.unit_price, 'amount', l.amount, 'tax_amount', l.tax_amount, 'is_free', sl.free_reason is not null, 'no_price', l.unit_price is null, 'manual', coalesce(public.so_line_manual(sl), false)) order by l.line_no), '[]'::jsonb)
                           from public.so_invoice_line l left join public.so_line sl on sl.id = l.so_line_id where l.invoice_order_id = o.id and l.kind = 'product')) order by o.so_number), '[]'::jsonb)
               from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id),
    'charges', (select coalesce(jsonb_agg(jsonb_build_object('so_number', o.so_number, 'kind', l.kind, 'account_code', l.account_code, 'description', l.description, 'comment', case when l.kind = 'charge' then c.description end,
                                                             'qty', l.qty, 'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'amount', l.amount, 'tax_amount', l.tax_amount) order by o.so_number, l.line_no), '[]'::jsonb)
                from public.so_invoice_line l join public.so_invoice_order o on o.id = l.invoice_order_id left join public.so_charge c on c.id = l.so_charge_id
                where l.invoice_id = v_inv.id and l.kind <> 'product'),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('reference', p.reference, 'paid_on', p.paid_on, 'method', p.method, 'amount', a.amount) order by p.paid_on, p.created_at, a.created_at), '[]'::jsonb)
                 from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
                 where a.invoice_id = v_inv.id and a.voided_at is null and p.status = 'active' and p.kind = 'payment'),
    'totals', jsonb_build_object('order_discount', v_inv.order_discount_amount, 'surcharge', v_inv.surcharge_amount, 'taxable', v_inv.taxable_amount, 'tax', v_inv.tax_amount, 'total', v_inv.total,
                                 'deposit_applied', v_inv.deposit_applied, 'credit_applied', v_inv.credit_applied, 'balance_forward', v_inv.balance_forward,
                                 'paid', (select coalesce(sum(a.amount), 0) from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id where a.invoice_id = v_inv.id and a.voided_at is null and p.status = 'active' and p.kind = 'payment'),
                                 'amount_due', v_inv.amount_due,
                                 'remaining', public.so_invoice_remaining(v_inv.id)));                                                                                     -- doc-1c 판정 528 ①: 찍는 순간 지금 남은 금액(발행 때 종이 값 amount_due 는 doc-2 의 남긴 PDF 가 지킨다)
  return public.doc_data_invoice_fmt(p_kind, p_cfg, v_n);
end;
$$;

-- ═══ ⑦ doc_data_invoice_fmt 재발행 — 원본 20261019172034_doc_1c_zero_blank_due_now.sql:95 바이트 + 바뀐 줄 하나(manual 줄은 net unit 에 오더 % 를 안 받는다) ═══
create or replace function public.doc_data_invoice_fmt(p_kind text, p_cfg jsonb, p_n jsonb) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_fmt  text := p_cfg->>'date_format';
  v_disp text := coalesce(p_cfg->>'unit_display', 'both');
  v_h    jsonb := p_n->'header';  v_t jsonb := p_n->'totals';
  v_orders jsonb;  v_charges jsonb;  v_payments jsonb;  v_inv jsonb;
  v_lines_amt numeric;  v_lines_tax numeric;  v_qty numeric;  v_chg_amt numeric;  v_chg_tax numeric;  v_chd numeric;
  v_due  numeric := coalesce((v_t->>'remaining')::numeric, (v_t->>'amount_due')::numeric);                                      -- doc-1c 판정 528 ①: 표에서 온 문서는 지금 남은 금액 · ship_ready(미리 보기)는 셈한 남을 몫
begin
  -- 제품 줄 — 오더 순(orders 배열 순 = so_number 순) · 줄 번호는 문서 안에서 1, 2, 3 … 이어서
  with ln as (
    select o.ord as o_ord, l.ord as l_ord, o.o->>'order_discount_pct' as od_pct, l.l, row_number() over (order by o.ord, l.ord) as no
    from jsonb_array_elements(p_n->'orders') with ordinality o(o, ord) cross join lateral jsonb_array_elements(o.o->'lines') with ordinality l(l, ord))
  select coalesce(jsonb_agg(jsonb_build_object(
           'so_number', coalesce(o.o->>'so_number', ''), 'reference', coalesce(o.o->>'reference', ''), 'carrier', coalesce(o.o->>'carrier', ''), 'tracking', coalesce(o.o->>'tracking', ''), 'tax_rule', coalesce(o.o->>'tax_rule', ''),
           'ship_to', (select jsonb_object_agg(k, coalesce(o.o->'ship_to'->>k, '')) from unnest(array['company', 'contact', 'phone', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country']) k),
           'lines', (select coalesce(jsonb_agg((jsonb_build_object('no', ln.no::text, 'upc', public.doc_upc(nullif(ln.l->>'product_id', '')::uuid), 'sku', coalesce(ln.l->>'sku', ''), 'description', coalesce(ln.l->>'description', ''), 'comment', coalesce(ln.l->>'comment', ''),
                                                                    'unit', coalesce(ln.l->>'unit', ''), 'qty', public.doc_fmt_qty((ln.l->>'qty')::numeric), 'list_price', public.doc_fmt_money((ln.l->>'list_price')::numeric), 'discount_pct', public.doc_fmt_pct((ln.l->>'discount_pct')::numeric),
                                                                    'amount', public.doc_fmt_money((ln.l->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((ln.l->>'tax_amount')::numeric), 'is_free', coalesce((ln.l->>'is_free')::boolean, false), 'no_price', coalesce((ln.l->>'no_price')::boolean, false))
                                                || public.doc_unit_prices((ln.l->>'unit_price')::numeric, case when coalesce((ln.l->>'manual')::boolean, false) then null else (ln.od_pct)::numeric end, v_disp)) order by ln.no), '[]'::jsonb)
                     from ln where ln.o_ord = o.ord)) order by o.ord), '[]'::jsonb),
         coalesce((select sum((ln.l->>'amount')::numeric) from ln), 0), coalesce((select sum((ln.l->>'tax_amount')::numeric) from ln), 0), coalesce((select sum((ln.l->>'qty')::numeric) from ln), 0)
    into v_orders, v_lines_amt, v_lines_tax, v_qty
  from jsonb_array_elements(p_n->'orders') with ordinality o(o, ord);
  select coalesce(jsonb_agg(jsonb_build_object('no', c.ord::text, 'so_number', coalesce(c.c->>'so_number', ''), 'code', coalesce(c.c->>'account_code', ''), 'description', coalesce(c.c->>'description', ''), 'comment', coalesce(c.c->>'comment', ''),
                                               'qty', public.doc_fmt_qty((c.c->>'qty')::numeric), 'unit_price', public.doc_fmt_money((c.c->>'unit_price')::numeric), 'discount_pct', public.doc_fmt_pct((c.c->>'discount_pct')::numeric),
                                               'amount', public.doc_fmt_money((c.c->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((c.c->>'tax_amount')::numeric)) order by c.ord), '[]'::jsonb),
         coalesce(sum((c.c->>'amount')::numeric), 0), coalesce(sum((c.c->>'tax_amount')::numeric), 0), coalesce(sum((c.c->>'amount')::numeric) filter (where c.c->>'kind' = 'charge_discount'), 0)
    into v_charges, v_chg_amt, v_chg_tax, v_chd
  from jsonb_array_elements(p_n->'charges') with ordinality c(c, ord);
  select coalesce(jsonb_agg(jsonb_build_object('no', p.ord::text, 'reference', coalesce(p.p->>'reference', ''), 'date', public.doc_fmt_date((p.p->>'paid_on')::date, v_fmt), 'method', public.doc_method_label(p.p->>'method'), 'amount', public.doc_fmt_money((p.p->>'amount')::numeric)) order by p.ord), '[]'::jsonb)
    into v_payments from jsonb_array_elements(p_n->'payments') with ordinality p(p, ord);
  v_inv := jsonb_build_object('number', coalesce(v_h->>'number', ''), 'date', public.doc_fmt_date((v_h->>'issued_on')::date, v_fmt), 'due_date', public.doc_fmt_date((v_h->>'due_on')::date, v_fmt), 'terms', coalesce(v_h->>'payment_term_name', ''),
                              'currency', coalesce(v_h->>'currency_code', ''), 'memo', coalesce(v_h->>'memo', ''), 'total_qty', public.doc_fmt_qty(v_qty));
  if p_kind = 'ship_ready' then
    v_inv := (v_inv - 'number') || jsonb_build_object('calc_at', public.doc_fmt_date(public.ims_today(), v_fmt) || ' ' || to_char(coalesce((p_n->>'calc_at')::timestamptz, now()) at time zone 'America/Toronto', 'HH24:MI'));
  end if;
  return jsonb_build_object(
    'invoice', v_inv, 'orders', v_orders, 'charges', v_charges, 'payments', v_payments,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money(v_lines_amt), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money(v_lines_amt + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'order_discount', public.doc_fmt_money((v_t->>'order_discount')::numeric), 'surcharge', public.doc_fmt_money((v_t->>'surcharge')::numeric), 'charges_discount', public.doc_fmt_money(v_chd),
                                 'before_tax', public.doc_fmt_money((v_t->>'taxable')::numeric), 'tax', public.doc_fmt_money((v_t->>'tax')::numeric), 'total', public.doc_fmt_money((v_t->>'total')::numeric),
                                 'deposit_applied', public.doc_fmt_money_nz((v_t->>'deposit_applied')::numeric), 'credit_applied', public.doc_fmt_money_nz((v_t->>'credit_applied')::numeric), 'balance_forward', public.doc_fmt_money_nz((v_t->>'balance_forward')::numeric),   -- doc-1c 판정 528 ③: 0 이면 빈칸
                                 'paid', public.doc_fmt_money_nz((v_t->>'paid')::numeric), 'due_label', case when v_due > 0 then 'Due' when v_due < 0 then 'Credit' else '' end, 'due_amount', public.doc_fmt_money_nz(v_due)))   -- doc-1c 판정 528 ②: 남은 돈 0 이면 둘 다 빈칸(판이 {{#totals.due_amount}} 로 숨긴다)
    || public.doc_data_common(p_kind, p_cfg, (v_h->'bill_to') || public.doc_contact(nullif(v_h->>'bill_to_customer_id', '')::uuid));
end;
$$;

-- ═══ ⑧ doc_data_so 재발행 — 원본 20261019172034_doc_1c_zero_blank_due_now.sql:131 바이트 + 바뀐 줄 하나(같은 규칙) ═══
create or replace function public.doc_data_so(p_so_id uuid, p_cfg jsonb) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_so   public.so%rowtype;
  v_pf   jsonb;  v_o jsonb;  v_t jsonb;
  v_fmt  text := p_cfg->>'date_format';
  v_disp text := coalesce(p_cfg->>'unit_display', 'both');
  v_lines jsonb;  v_charges jsonb := '[]'::jsonb;  v_prepay jsonb;
  v_lines_tax numeric;  v_n int := 0;  v_x jsonb;  v_sc_code text := (select c.value from public.inv_config c where c.key = 'so_surcharge_account_code');
  v_chg_amt numeric;  v_chg_tax numeric;
begin
  select * into v_so from public.so s where s.id = p_so_id;
  if v_so.id is null then raise exception 'Order not found'; end if;
  v_pf := public.so_proforma(array[p_so_id]);
  v_o := v_pf->'orders'->0;  v_t := v_pf->'totals';
  select coalesce(jsonb_agg((jsonb_build_object('no', x.no::text, 'upc', public.doc_upc(sl.product_id), 'sku', coalesce(x.l->>'sku', ''), 'description', coalesce(x.l->>'product_name', ''), 'comment', coalesce(sl.comments, ''),
                                                'unit', coalesce(x.l->>'unit', ''), 'qty', public.doc_fmt_qty((x.l->>'qty')::numeric), 'list_price', public.doc_fmt_money((x.l->>'list_price')::numeric), 'discount_pct', public.doc_fmt_pct((x.l->>'discount_pct')::numeric),
                                                'amount', public.doc_fmt_money((x.l->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((x.l->>'tax')::numeric), 'is_free', sl.free_reason is not null, 'no_price', sl.unit_price is null)
                             || public.doc_unit_prices(sl.unit_price, case when coalesce(public.so_line_manual(sl), false) then null else v_so.order_discount_pct end, v_disp)) order by x.no), '[]'::jsonb),
         coalesce(sum((x.l->>'tax')::numeric), 0)
    into v_lines, v_lines_tax
  from (select l, row_number() over (order by (l->>'line_no')::int) as no from jsonb_array_elements(coalesce(v_o->'lines', '[]'::jsonb)) l) x
  left join public.so_line sl on sl.id = (x.l->>'line_id')::uuid;
  -- charges = 운임(정가) · 운임 할인(음수) · 오더 할인(음수) · 줄 부가 요금 — so_tax_preview 가 센 값 그대로 · 순서 운임 → 할인 → 오더 할인 → 부가 요금
  for v_x in select c from jsonb_array_elements(coalesce(v_o->'charges', '[]'::jsonb)) c loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_x->>'account_code', ''), 'description', coalesce(v_x->>'name', ''), 'comment', coalesce(v_x->>'description', ''),
                                                 'qty', '', 'unit_price', '', 'discount_pct', public.doc_fmt_pct((v_x->>'discount_pct')::numeric), 'amount', public.doc_fmt_money((v_x->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'tax')::numeric));
  end loop;
  for v_x in select c from jsonb_array_elements(coalesce(v_o->'charge_discounts', '[]'::jsonb)) c loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce((select c.value from public.inv_config c where c.key = 'so_freight_discount_account_code'), ''), 'description', coalesce(v_x->>'name', ''), 'comment', '',
                                                 'qty', '', 'unit_price', '', 'discount_pct', public.doc_fmt_pct((v_x->>'discount_pct')::numeric), 'amount', public.doc_fmt_money((v_x->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'tax')::numeric));
  end loop;
  if coalesce((v_o->'order_discount'->>'amount')::numeric, 0) <> 0 then
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_so.sale_account_code, ''), 'description', format('Order discount %s%%', public.doc_fmt_qty((v_o->'order_discount'->>'pct')::numeric)), 'comment', '',
                                                 'qty', '', 'unit_price', '', 'discount_pct', '', 'amount', public.doc_fmt_money((v_o->'order_discount'->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_o->'order_discount'->>'tax')::numeric));
  end if;
  for v_x in select l from jsonb_array_elements(coalesce(v_o->'lines', '[]'::jsonb)) l where coalesce((l->>'surcharge_total')::numeric, 0) > 0 order by (l->>'line_no')::int loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_sc_code, ''), 'description', coalesce(nullif(v_x->>'surcharge_label', ''), 'Surcharge') || ' (' || (v_x->>'sku') || ')', 'comment', '',
                                                 'qty', public.doc_fmt_qty((v_x->>'qty')::numeric), 'unit_price', public.doc_fmt_money((v_x->>'surcharge_unit')::numeric), 'discount_pct', '',
                                                 'amount', public.doc_fmt_money((v_x->>'surcharge_total')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'surcharge_tax')::numeric));
  end loop;
  v_chg_amt := coalesce((v_t->>'charges_amount')::numeric, 0) - coalesce((v_t->>'charges_discount_amount')::numeric, 0) + coalesce((v_t->>'order_discount_amount')::numeric, 0) + coalesce((v_t->>'surcharge_amount')::numeric, 0);
  v_chg_tax := case when v_t->>'tax' is null then null else (v_t->>'tax')::numeric - v_lines_tax end;
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'reference', coalesce(x.d->>'reference', ''), 'date', public.doc_fmt_date((x.d->>'paid_on')::date, v_fmt), 'method', public.doc_method_label(x.d->>'method'), 'amount', public.doc_fmt_money((x.d->>'remaining')::numeric)) order by x.no), '[]'::jsonb)
    into v_prepay
  from (select d, row_number() over () as no from jsonb_array_elements(coalesce(v_pf->'deposits', '[]'::jsonb)) d) x;
  return jsonb_build_object(
    'so', jsonb_build_object('number', v_so.so_number, 'date', public.doc_fmt_date(v_so.order_date, v_fmt), 'status', v_so.status, 'required_by', public.doc_fmt_date(v_so.required_by, v_fmt), 'terms', coalesce(v_so.payment_term_name, ''),
                             'reference', coalesce(v_so.ref, ''), 'currency', coalesce(v_so.currency_code, ''), 'memo', coalesce(v_so.comments, '')),
    'ship_to', jsonb_build_object('company', coalesce(v_so.ship_to_company, ''), 'contact', coalesce(v_so.ship_to_contact, ''), 'phone', coalesce(v_so.ship_to_phone, ''), 'line1', coalesce(v_so.ship_to_line1, ''), 'line2', coalesce(v_so.ship_to_line2, ''),
                                  'city', coalesce(v_so.ship_to_city, ''), 'state_province', coalesce(v_so.ship_to_state_province, ''), 'postal_code', coalesce(v_so.ship_to_postal_code, ''), 'country', coalesce(v_so.ship_to_country, '')),
    'lines', v_lines, 'charges', v_charges, 'prepayments', v_prepay,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money((v_t->>'lines_amount')::numeric), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money((v_t->>'lines_amount')::numeric + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'order_discount', public.doc_fmt_money((v_t->>'order_discount_amount')::numeric), 'surcharge', public.doc_fmt_money((v_t->>'surcharge_amount')::numeric), 'charges_discount', public.doc_fmt_money(-(v_t->>'charges_discount_amount')::numeric),
                                 'before_tax', public.doc_fmt_money((v_t->>'taxable_amount')::numeric), 'tax', public.doc_fmt_money((v_t->>'tax')::numeric), 'total', public.doc_fmt_money((v_t->>'total')::numeric),
                                 'prepaid', public.doc_fmt_money_nz((v_t->>'received')::numeric), 'due_amount', public.doc_fmt_money((v_t->>'balance_due')::numeric)))   -- doc-1c 판정 528 ③ 의 결: 선결제 없으면 빈칸 · due 는 늘(아직 안 낸 오더)
    || public.doc_data_common('sales_order', p_cfg, jsonb_build_object('name', v_so.bill_to_name, 'line1', v_so.bill_to_line1, 'line2', v_so.bill_to_line2, 'city', v_so.bill_to_city, 'state_province', v_so.bill_to_state_province,
                                                                        'postal_code', v_so.bill_to_postal_code, 'country', v_so.bill_to_country) || public.doc_contact(coalesce(v_so.bill_to_customer_id, v_so.customer_id)));
end;
$$;

-- ═══ ⑨ so_invoice_preview 재발행 — 원본 20261019155731_doc_1b2_ship_ready.sql:471 바이트 + 바뀐 줄 하나(ship_ready neutral 줄에 manual — so_tax_preview 줄 객체에서) ═══
create or replace function public.so_invoice_preview(p_orders jsonb, p_shipped_on date default null) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_pf      jsonb;
  v_on      date := public.ims_today();                                                  -- 발행일 = 마무리한 날(so_finalize → so_invoice_issue(…, null) · ⓐ1) · p_shipped_on 은 출고일일 뿐
  v_g       jsonb;  v_o jsonb;  e jsonb;  x jsonb;
  v_ids     uuid[];
  v_first   public.so%rowtype;  v_so public.so%rowtype;  v_pt public.ref_payment_term%rowtype;
  v_rule_id uuid;  v_prev jsonb;  v_over jsonb;
  v_sc_code text := (select nullif(k.value, '') from public.inv_config k where k.key = 'so_surcharge_account_code');
  v_fd_code text := (select nullif(k.value, '') from public.inv_config k where k.key = 'so_freight_discount_account_code');
  v_orders  jsonb;  v_lines jsonb;  v_charges jsonb;  v_pay jsonb;  v_plan jsonb;  v_docs jsonb := '[]'::jsonb;  v_warn text[];
  v_lines_amt numeric;  v_od_amt numeric;  v_chg_amt numeric;  v_chd_amt numeric;  v_sc_amt numeric;  v_tax numeric;  v_total numeric;
  v_o_od numeric;
begin
  v_pf := public.so_finalize(p_orders, false, p_shipped_on);                             -- 검사 · 묶음 · 수량 · 다시 매긴 단가 · 운임 · 부가 요금 — 쓰지 않는다(p_commit false) · 문은 so_finalize 의 것(sales)
  for v_g in select g from jsonb_array_elements(v_pf->'invoices') g loop
    select array_agg((o->>'so_id')::uuid) into v_ids from jsonb_array_elements(v_pf->'orders') o where o->>'invoice_group' = v_g->>'group';
    select * into v_first from public.so s where s.id = any(v_ids) order by s.so_number limit 1;
    v_pt := null;
    if v_first.payment_term_id is not null then select * into v_pt from public.ref_payment_term t where t.id = v_first.payment_term_id; end if;
    v_orders := '[]'::jsonb;  v_charges := '[]'::jsonb;  v_warn := '{}';
    v_lines_amt := 0;  v_od_amt := 0;  v_chg_amt := 0;  v_chd_amt := 0;  v_sc_amt := 0;  v_tax := 0;
    for v_so in select * from public.so s where s.id = any(v_ids) order by s.so_number loop
      select o into v_o from jsonb_array_elements(v_pf->'orders') o where (o->>'so_id')::uuid = v_so.id;
      -- p_over: 보낼 수량(ship.lines picked) · 다시 매긴 단가(repriced) · 부가 요금(surcharges new) · 운임(charges — 마무리 화면이 고친 · 더한 것)
      select coalesce(jsonb_object_agg(z.line_id, z.o), '{}'::jsonb) into v_over
      from (select l->>'line_id' as line_id,
                   jsonb_build_object('qty', (l->>'picked')::numeric)
                   || coalesce((select jsonb_build_object('unit_price', r->'new_unit_price', 'discount_pct', r->'new_discount_pct', 'discount_source', r->'new_discount_source')
                                from jsonb_array_elements(coalesce(v_o->'repriced', '[]'::jsonb)) r where r->>'line_id' = l->>'line_id'), '{}'::jsonb)
                   || coalesce((select s->'new' from jsonb_array_elements(coalesce(v_o->'surcharges', '[]'::jsonb)) s where s->>'line_id' = l->>'line_id'), '{}'::jsonb) as o
            from jsonb_array_elements(coalesce(v_o->'ship'->'lines', '[]'::jsonb)) l) z;
      select pe into x from jsonb_array_elements(p_orders) pe where pe->>'so_id' = v_so.id::text;                                                     -- 입력(마무리 화면이 보낸 그대로) — description 은 so_finalize 미리 보기 항목에 없어 입력에서 짝(같은 순서)으로 가져온다
      v_over := jsonb_build_object('lines', v_over,
                                   'charges', (select coalesce(jsonb_agg(jsonb_build_object('charge_id', cc.c->'charge_id', 'name', cc.c->>'name', 'description', nullif(trim(ii.i->>'description'), ''), 'amount', cc.c->'amount',
                                                                                             'discount_pct', cc.c->'discount_pct', 'discount_amount', cc.c->'discount_amount', 'account_code', cc.c->'account_code') order by cc.ord), '[]'::jsonb)
                                               from jsonb_array_elements(coalesce(v_o->'charges', '[]'::jsonb)) with ordinality cc(c, ord)
                                               left join jsonb_array_elements(coalesce(nullif(x->'charges', 'null'::jsonb), '[]'::jsonb)) with ordinality ii(i, ord) on ii.ord = cc.ord));
      v_rule_id := public.so_invoice_rule_pick(v_so, v_on);
      v_prev := public.so_tax_preview(v_so.id, v_on, v_rule_id, 'shipped', v_over);
      v_o_od := (v_prev->'totals'->>'order_discount_amount')::numeric;
      -- 제품 줄(보낸 수량 > 0 · 구성품 줄 제외) · 그 뒤 surcharge 줄 · 오더 할인 줄 · 운임 줄 + 할인 줄 — so_invoice_issue 148 ~ 180 과 같은 순서
      select coalesce(jsonb_agg(jsonb_build_object('product_id', l->'product_id', 'sku', l->>'sku', 'description', l->>'product_name', 'comment', sl.comments, 'unit', l->>'unit', 'qty', (l->>'qty')::numeric,
                                                   'list_price', (l->>'list_price')::numeric, 'discount_pct', (l->>'discount_pct')::numeric, 'unit_price', (l->>'unit_price')::numeric, 'amount', (l->>'amount')::numeric, 'tax_amount', (l->>'tax')::numeric,
                                                   'is_free', sl.free_reason is not null, 'no_price', (l->>'unit_price') is null, 'manual', coalesce((l->>'manual')::boolean, false)) order by (l->>'line_no')::int), '[]'::jsonb)
        into v_lines
      from jsonb_array_elements(v_prev->'lines') l left join public.so_line sl on sl.id = (l->>'line_id')::uuid
      where (l->>'qty')::numeric > 0 and nullif(l->>'combo_line_id', '') is null;
      v_charges := v_charges || coalesce((select jsonb_agg(jsonb_build_object('so_number', v_so.so_number, 'kind', 'surcharge', 'account_code', v_sc_code, 'description', l->>'surcharge_label', 'comment', '',
                                                                                'qty', (l->>'qty')::numeric, 'unit_price', (l->>'surcharge_unit')::numeric, 'discount_pct', null, 'amount', (l->>'surcharge_total')::numeric, 'tax_amount', (l->>'surcharge_tax')::numeric) order by (l->>'line_no')::int)
                                          from jsonb_array_elements(v_prev->'lines') l where (l->>'qty')::numeric > 0 and nullif(l->>'combo_line_id', '') is null and coalesce((l->>'surcharge_total')::numeric, 0) > 0), '[]'::jsonb);
      if v_o_od <> 0 then
        v_charges := v_charges || jsonb_build_object('so_number', v_so.so_number, 'kind', 'order_discount', 'account_code', v_so.sale_account_code, 'description', format('Order discount %s%%', v_so.order_discount_pct), 'comment', '',
                                                     'qty', null, 'unit_price', null, 'discount_pct', null, 'amount', v_o_od, 'tax_amount', (v_prev->'order_discount'->>'tax')::numeric);
      end if;
      for e in select c from jsonb_array_elements(v_prev->'charges') c loop
        v_charges := v_charges || jsonb_build_object('so_number', v_so.so_number, 'kind', 'charge', 'account_code', e->>'account_code', 'description', (e->>'name') || coalesce(' — ' || (e->>'description'), ''), 'comment', coalesce(e->>'description', ''),
                                                     'qty', null, 'unit_price', null, 'discount_pct', null, 'amount', (e->>'amount')::numeric, 'tax_amount', (e->>'tax')::numeric);
        if coalesce((e->>'discount')::numeric, 0) > 0 then
          v_charges := v_charges || jsonb_build_object('so_number', v_so.so_number, 'kind', 'charge_discount', 'account_code', v_fd_code, 'comment', '',
                                                       'description', (e->>'name') || ' discount' || case when nullif(e->>'discount_pct', '') is not null then format(' %s%%', trim_scale((e->>'discount_pct')::numeric)) else '' end,
                                                       'qty', null, 'unit_price', null, 'discount_pct', nullif(e->>'discount_pct', '')::numeric, 'amount', -(e->>'discount')::numeric, 'tax_amount', -coalesce((e->>'discount_tax')::numeric, 0));
        end if;
      end loop;
      v_orders := v_orders || jsonb_build_object('so_number', v_so.so_number, 'reference', v_so.ref, 'carrier', coalesce((select rc.name from public.ref_carrier rc where rc.id = nullif(v_o->>'_carrier_id', '')::uuid), case when (v_o->>'_carrier_touch')::boolean then null else v_so.carrier end),
                                                 'tracking', case when (v_o->>'_tracking_touch')::boolean then nullif(array_to_string(array(select jsonb_array_elements_text(v_o->'_tracking')), ', '), '') else v_so.tracking_number end,
                                                 'tax_rule', v_prev->'rule'->>'rule', 'order_discount_pct', v_so.order_discount_pct,
                                                 'ship_to', jsonb_build_object('company', v_so.ship_to_company, 'contact', v_so.ship_to_contact, 'phone', v_so.ship_to_phone, 'line1', v_so.ship_to_line1, 'line2', v_so.ship_to_line2,
                                                                               'city', v_so.ship_to_city, 'state_province', v_so.ship_to_state_province, 'postal_code', v_so.ship_to_postal_code, 'country', v_so.ship_to_country),
                                                 'lines', v_lines);
      v_lines_amt := v_lines_amt + (v_prev->'totals'->>'lines_amount')::numeric;  v_od_amt := v_od_amt + v_o_od;
      v_chg_amt := v_chg_amt + (v_prev->'totals'->>'charges_amount')::numeric;  v_chd_amt := v_chd_amt + coalesce((v_prev->'totals'->>'charges_discount_amount')::numeric, 0);
      v_sc_amt := v_sc_amt + coalesce((v_prev->'totals'->>'surcharge_amount')::numeric, 0);  v_tax := v_tax + (v_prev->'totals'->>'tax')::numeric;
      if v_rule_id is distinct from v_so.tax_rule_id then v_warn := array_append(v_warn, 'draft_rule_changed:' || v_so.so_number); end if;
    end loop;
    v_total := v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt + v_tax;
    v_plan := public.so_invoice_apply_plan(v_first.bill_to_customer_id, v_first.currency_id, v_ids, v_total);
    select coalesce(jsonb_agg(jsonb_build_object('reference', s->'reference', 'paid_on', s->'paid_on', 'method', s->>'method', 'amount', (s->>'amount')::numeric) order by (s->>'paid_on')::date, (s->>'created_at')::timestamptz, ord), '[]'::jsonb)
      into v_pay from jsonb_array_elements(v_plan->'steps') with ordinality t(s, ord) where s->>'step' in ('auto_deposit', 'auto_balance');
    v_docs := v_docs || jsonb_build_object(
      'group', v_g->>'group', 'so_ids', to_jsonb(v_ids),
      'header', jsonb_build_object('number', null, 'issued_on', v_on, 'due_on', case when v_pt.net_days is not null then v_on + v_pt.net_days end, 'payment_term_name', coalesce(v_pt.name, v_first.payment_term_name),
                                   'currency_code', v_first.currency_code, 'memo', '', 'bill_to_customer_id', v_first.bill_to_customer_id,
                                   'bill_to', jsonb_build_object('name', v_first.bill_to_name, 'line1', v_first.bill_to_line1, 'line2', v_first.bill_to_line2, 'city', v_first.bill_to_city, 'state_province', v_first.bill_to_state_province, 'postal_code', v_first.bill_to_postal_code, 'country', v_first.bill_to_country)),
      'orders', v_orders, 'charges', v_charges, 'payments', v_pay,
      'totals', jsonb_build_object('order_discount', v_od_amt, 'surcharge', v_sc_amt, 'taxable', v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt, 'tax', v_tax, 'total', v_total,
                                   'deposit_applied', (v_plan->>'deposit')::numeric, 'credit_applied', (v_plan->>'credit')::numeric, 'balance_forward', -((v_plan->>'credit')::numeric + (v_plan->>'balance')::numeric),
                                   'paid', (v_plan->>'deposit')::numeric + (v_plan->>'balance')::numeric, 'amount_due', v_total - (v_plan->>'deposit')::numeric - (v_plan->>'credit')::numeric - (v_plan->>'balance')::numeric),
      'plan', v_plan, 'warnings', to_jsonb(v_warn), 'calc_at', now());
  end loop;
  return jsonb_build_object('issued_on', v_on, 'shipped_on', v_pf->>'shipped_on', 'docs', v_docs, 'finalize_warnings', v_pf->'warnings', 'put_back', v_pf->'put_back');
end;
$$;

-- ═══ ⑩ 마스터 이름 잠금 — 판정 538 「이름 바꾸기는 막고, 만들기 · 끄기 · 켜기로」 · 이름은 product · supplier · customer · 원장(bin · warehouse 글자) 에 글자로 베껴져 있어 바꾸면 갈라진다(fb-0 1번) · ref_bin 은 창고 바꾸기도 · 트리거 이름이 *_touch 보다 앞이라 먼저 돈다 ═══
create function public.ims_ref_name_lock() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  if new.name is distinct from old.name
     or (tg_table_name = 'ref_bin' and (to_jsonb(new)->>'warehouse_id') is distinct from (to_jsonb(old)->>'warehouse_id')) then
    raise exception using errcode = 'IM538', message = 'Names cannot be changed — switch this one off and add a new one.';
  end if;
  return new;
end;
$$;
revoke all on function public.ims_ref_name_lock() from public, anon, authenticated;
comment on function public.ims_ref_name_lock() is 'od-1 판정 538 — 마스터 다섯(ref_brand · ref_category · ref_unit · ref_payment_term · ref_bin)의 이름 바꾸기 거부(ref_bin 은 warehouse_id 도) · errcode IM538 · 꼭 바꿔야 하면 psql 소유자가 alter table … disable trigger <표>_name_lock 뒤 고치고 enable(베낀 글자 — product.brand_name · payment_term_name · inv_ledger.bin 등 — 을 함께 고친다)';
create trigger ref_brand_name_lock        before update on public.ref_brand        for each row execute function public.ims_ref_name_lock();
create trigger ref_category_name_lock     before update on public.ref_category     for each row execute function public.ims_ref_name_lock();
create trigger ref_unit_name_lock         before update on public.ref_unit         for each row execute function public.ims_ref_name_lock();
create trigger ref_payment_term_name_lock before update on public.ref_payment_term for each row execute function public.ims_ref_name_lock();
create trigger ref_bin_name_lock          before update on public.ref_bin          for each row execute function public.ims_ref_name_lock();

-- ═══ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text;
begin
  if to_regprocedure('public.so_line_manual(public.so_line)') is null or not has_function_privilege('authenticated', 'public.so_line_manual(public.so_line)', 'execute') or has_function_privilege('anon', 'public.so_line_manual(public.so_line)', 'execute') then v_bad := v_bad || ' so_line_manual'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = 'public.so_tax_preview(uuid, date, uuid, text, jsonb)'::regprocedure;
  if v_src not like '%''discount_basis_amount'', v_lines_amt - v_m_amt%' or v_src not like '%(v_lines_amt - v_m_amt) * v_so.order_discount_pct%' then v_bad := v_bad || ' so_tax_preview'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = 'public.so_detail(uuid)'::regprocedure;
  if v_src like '%round(v_lines_total * v_so.order_discount_pct%' or v_src not like '%''order_discount_amount'')::numeric, 0);%' then v_bad := v_bad || ' so_detail'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = 'public.so_totals_many(uuid[])'::regprocedure;
  if v_src like '%round(v_lt * v_r.order_discount_pct%' or v_src not like '%''order_discount_amount'')::numeric, 0);%' then v_bad := v_bad || ' so_totals_many'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_totals_many') <> 1 then v_bad := v_bad || ' so_totals_many-defs'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = 'public.so_credit_issue(jsonb, boolean)'::regprocedure;
  if v_src not like '%and not public.so_line_manual(sl)%' then v_bad := v_bad || ' so_credit_issue'; end if;
  if (select p.prosrc from pg_proc p where p.oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) not like '%''manual'', coalesce(public.so_line_manual(sl), false)%' then v_bad := v_bad || ' doc_data_invoice'; end if;
  if (select p.prosrc from pg_proc p where p.oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) not like '%(ln.l->>''manual'')::boolean%' then v_bad := v_bad || ' doc_data_invoice_fmt'; end if;
  if (select p.prosrc from pg_proc p where p.oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure) not like '%coalesce(public.so_line_manual(sl), false) then null else v_so.order_discount_pct%' then v_bad := v_bad || ' doc_data_so'; end if;
  if (select p.prosrc from pg_proc p where p.oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure) not like '%''manual'', coalesce((l->>''manual'')::boolean, false)%' then v_bad := v_bad || ' so_invoice_preview'; end if;
  if (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where t.tgname in ('ref_brand_name_lock', 'ref_category_name_lock', 'ref_unit_name_lock', 'ref_payment_term_name_lock', 'ref_bin_name_lock') and c.relname = replace(t.tgname, '_name_lock', '') and t.tgenabled <> 'D') <> 5 then v_bad := v_bad || ' name_lock-triggers'; end if;
  if has_function_privilege('authenticated', 'public.ims_ref_name_lock()', 'execute') or has_function_privilege('anon', 'public.ims_ref_name_lock()', 'execute') then v_bad := v_bad || ' name_lock-acl'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM511', message = format('STOP - od-1 did not land as designed:%s - nothing was changed', v_bad); end if;
end $$;
