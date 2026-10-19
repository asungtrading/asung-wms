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
-- 20261019155731_doc_1b2_ship_ready.sql — doc-1b2 (2026-10-19 · 회사 PC · Fable · 문서 템플릿 ③ Ship Ready(PROFORMA) — 마무리 미리 보기에 돈을 얹는다)
--   판정 521 ~ 525 · doc-0 Q2 ①~⑦ · doc-1b2 §0 이견(회신)
--   길: so_finalize 무접촉(반환 그대로 · ③ 안) · 발행과 미리 보기가 같은 식을 쓰도록 so_invoice_issue 에서 둘만 뗀다 — 세율 고르기(so_invoice_rule_pick) · 자동 붙이기 계획(so_invoice_apply_plan · 쓰지 않는다)
--      줄 · 운임 · 세금 · 합계의 식은 이미 so_tax_preview 하나 — 거기에 「쓰기 전의 값」 덮어쓰기 인자 p_over(lines{qty · unit_price · discount_* · surcharge_*} · charges[])를 더한다(drop + create · 부르는 자리 일곱은 네 인자 그대로)
--   ① so_invoice_rule_pick(so, on) — 발행 · 미리 보기가 같은 세율을 고른다(수동 규칙 그대로 · 아니면 발행일 · 배송지로 다시 · 없으면 거부)
--   ② so_invoice_apply_plan(customer, currency, so_ids, total) — ⓑ2 ① 선수금 → ⓒ2 ② 크레딧 → ⓑ2 ③ 받아 둔 돈 순서 · 금액 · 한도(남은 돈 · 결제 남은 금액 · 받아 둔 돈 · 다른 오더 예약분)를 옛 so_invoice_issue 의 세 고리와 같은 식으로 셈만 한다 · 미리 보기에서는 담긴 오더가 아직 packed 라 「다른 오더 예약분」 에서 담긴 오더를 뺀다(발행 때는 fulfilled 라 저절로 빠지던 것)
--   ③ so_tax_preview 재발행(원본 20261007171939:1 바이트 + p_over · drop + create · grant · comment 다시)
--   ④ so_invoice_issue 재발행(원본 20261007173939:63 바이트 + ①② 호출로 바꾼 자리만 · 반환 모양 그대로 · 부르는 자리 셋 so_finalize · so_invoice_reissue · so_pos_complete 무접촉)
--   ⑤ so_invoice_preview(p_orders, p_shipped_on) — so_finalize(p_commit false) 가 돌려준 수량 · 다시 매긴 단가 · 운임 · 부가 요금 · 묶음을 그대로 p_over 로 옮겨 so_tax_preview(shipped) → 발행과 같은 순서로 줄을 세우고 ② 로 붙일 몫을 셈한다 · 아무것도 쓰지 않는다(잠금은 so_finalize 의 것 · 트랜잭션 끝에 풀린다)
--   ⑥ doc_data_invoice 를 「표 → 중립 jsonb」(loader) + 「중립 jsonb → 문서」(doc_data_invoice_fmt)로 가른다 · ship_ready = ⑤ 의 중립 jsonb → 같은 fmt · doc_data 재발행(ship_ready 갈래 · volatile — so_finalize 미리 보기가 for update 를 잡으므로 읽기 전용 트랜잭션에서는 돌 수 없다)
--   검증 ~/asung/prompts/doc-1b2-verify.sql — R(옛 발행 = 새 발행 · 여덟 시나리오) · P(미리 보기 = 실제 발행 · 칸마다)
--   무접촉: so_finalize · so_ship · so_proforma · 화면 · git · 운영 DB · 첫 문장 = guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록

-- ═══ ① 세율 고르기 한 곳 — 옛 so_invoice_issue 118 ~ 126 행 그대로(발행일 · 배송지) ═══
create function public.so_invoice_rule_pick(p_so public.so, p_on date) returns uuid
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_pick    jsonb;
  v_rule_id uuid;
begin
  if p_so.tax_rule_manual then
    v_rule_id := p_so.tax_rule_id;
  else
    v_pick := public.so_tax_rule_for(p_so.ship_to_country, p_so.ship_to_state_province, p_on, 'sale');
    v_rule_id := (v_pick->>'rule_id')::uuid;
  end if;
  if v_rule_id is null then
    raise exception 'Order % has no tax rule for its ship-to address on % — pick a tax rule on the order — nothing was saved', p_so.so_number, p_on;
  end if;
  return v_rule_id;
end;
$$;
comment on function public.so_invoice_rule_pick(public.so, date) is 'doc-1b2 — 인보이스의 세율 고르기 한 곳(옛 so_invoice_issue 안의 아홉 줄): 사람이 정한 규칙(tax_rule_manual)이면 그대로 · 아니면 발행일 · 배송지로 다시(so_tax_rule_for) · 없으면 거부 — so_invoice_issue(발행) · so_invoice_preview(Ship Ready)가 같은 함수를 부른다';
revoke all on function public.so_invoice_rule_pick(public.so, date) from public, anon;
grant execute on function public.so_invoice_rule_pick(public.so, date) to authenticated, service_role;

-- ═══ ② 자동 붙이기 계획 — 옛 so_invoice_issue 201 ~ 258 행의 세 고리를 쓰지 않고 셈만 ═══
create function public.so_invoice_apply_plan(p_customer_id uuid, p_currency_id uuid, p_so_ids uuid[], p_total numeric) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_left    numeric := p_total;
  v_recv    numeric;
  v_avail   numeric;
  v_take    numeric;
  v_deposit numeric := 0;  v_credit numeric := 0;  v_balance numeric := 0;
  v_steps   jsonb := '[]'::jsonb;
  v_used    jsonb := '{}'::jsonb;                                                       -- 결제마다 이 계획이 이미 쓴 몫(① 뒤 ③ 의 남은 금액 = 남은 금액 − 쓴 몫)
  pay       record;
  cr        record;
begin
  -- ⓑ2 ① 담긴 오더를 대상으로 한 선결제(판정 4 · auto_deposit) — 받은 날 순 · 한도 = 결제 남은 금액 · 인보이스 남은 돈 · 받아 둔 돈(received — 붙일 때마다 그만큼 준다)
  select b.received into v_recv from public.so_customer_balance(p_customer_id) b where b.currency_id = p_currency_id;
  v_recv := coalesce(v_recv, 0);
  for pay in
    select p.id, p.paid_on, p.method, p.reference, p.created_at, public.so_payment_remaining(p.id) as remaining
      from public.so_payment p
     where p.customer_id = p_customer_id and p.currency_id = p_currency_id and p.status = 'active' and p.kind = 'payment'
       and exists (select 1 from public.so_payment_order o where o.payment_id = p.id and o.so_id = any(p_so_ids))
     order by p.paid_on, p.created_at, p.id
  loop
    exit when v_left <= 0;
    if pay.remaining <= 0 then continue; end if;
    v_take := least(pay.remaining, v_left, v_recv);
    if v_take <= 0 then continue; end if;
    v_deposit := v_deposit + v_take;  v_left := v_left - v_take;  v_recv := v_recv - v_take;
    v_used := v_used || jsonb_build_object(pay.id::text, v_take);
    v_steps := v_steps || jsonb_build_object('step', 'auto_deposit', 'payment_id', pay.id, 'amount', v_take, 'paid_on', pay.paid_on, 'method', pay.method, 'reference', pay.reference, 'created_at', pay.created_at);
  end loop;
  -- ⓒ2 ② 크레딧(진 빚 · 8-e 「크레딧부터」 · 판정 5) — issued 크레딧을 발행일 순으로 인보이스만큼만
  if v_left > 0 then
    for cr in
      select c.id, c.credit_number, c.issued_on, public.so_credit_remaining(c.id) as remaining
        from public.so_credit c
       where c.customer_id = p_customer_id and c.currency_id = p_currency_id and c.status = 'issued'
       order by c.issued_on, c.created_at, c.id
    loop
      exit when v_left <= 0;
      if cr.remaining <= 0 then continue; end if;
      v_take := least(cr.remaining, v_left);
      v_credit := v_credit + v_take;  v_left := v_left - v_take;
      v_steps := v_steps || jsonb_build_object('step', 'auto_credit', 'credit_id', cr.id, 'credit_number', cr.credit_number, 'amount', v_take, 'issued_on', cr.issued_on);
    end loop;
  end if;
  -- ⓑ2 ③ 손님의 받아 둔 돈(판정 5 · auto_balance) — 다른 오더 예약분 제외 · 인보이스만큼만 · 받은 날 순
  --   예약분 = 아직 열린(fulfilled · cancelled 아님 · 살아 있는 인보이스 없음) 다른 오더를 대상으로 한 결제의 남은 금액 — 담긴 오더(p_so_ids)는 뺀다(발행 때는 이미 fulfilled 라 so_payment_is_reserved 가 저절로 뺐다 · 미리 보기는 아직 packed)
  if v_left > 0 then
    select greatest(v_recv - coalesce(sum(public.so_payment_remaining(p.id) - coalesce((v_used->>(p.id::text))::numeric, 0)), 0), 0) into v_avail
      from public.so_payment p
     where p.customer_id = p_customer_id and p.currency_id = p_currency_id and p.status = 'active' and p.kind = 'payment'
       and exists (select 1 from public.so_payment_order o join public.so s on s.id = o.so_id
                    where o.payment_id = p.id and s.status not in ('fulfilled', 'cancelled') and not (s.id = any(p_so_ids))
                      and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id));
    v_avail := coalesce(v_avail, 0);
    for pay in
      select p.id, p.paid_on, p.method, p.reference, p.created_at, public.so_payment_remaining(p.id) - coalesce((v_used->>(p.id::text))::numeric, 0) as remaining
        from public.so_payment p
       where p.customer_id = p_customer_id and p.currency_id = p_currency_id and p.status = 'active' and p.kind = 'payment'
         and not exists (select 1 from public.so_payment_order o join public.so s on s.id = o.so_id
                          where o.payment_id = p.id and s.status not in ('fulfilled', 'cancelled') and not (s.id = any(p_so_ids))
                            and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id))
       order by p.paid_on, p.created_at, p.id
    loop
      exit when v_left <= 0 or v_avail <= 0;
      if pay.remaining <= 0 then continue; end if;
      v_take := least(pay.remaining, v_left, v_avail);
      if v_take <= 0 then continue; end if;
      v_balance := v_balance + v_take;  v_left := v_left - v_take;  v_avail := v_avail - v_take;
      v_steps := v_steps || jsonb_build_object('step', 'auto_balance', 'payment_id', pay.id, 'amount', v_take, 'paid_on', pay.paid_on, 'method', pay.method, 'reference', pay.reference, 'created_at', pay.created_at);
    end loop;
  end if;
  return jsonb_build_object('deposit', v_deposit, 'credit', v_credit, 'balance', v_balance, 'left', v_left, 'steps', v_steps);
end;
$$;
comment on function public.so_invoice_apply_plan(uuid, uuid, uuid[], numeric) is 'doc-1b2 — 발행 순간 자동으로 붙는 돈의 계획(쓰지 않는다): ⓑ2 ① 담긴 오더 대상 선수금(받은 날 순 · 한도 결제 남은 금액 · 남은 돈 · 받아 둔 돈) → ⓒ2 ② issued 크레딧(발행일 순) → ⓑ2 ③ 받아 둔 돈(다른 열린 오더 예약분 제외 · 담긴 오더는 뺀다) — 옛 so_invoice_issue 세 고리(20261007173939:201 ~ 258)와 같은 식 · so_invoice_issue 는 이 계획대로 alloc_add 를 부르고(한도 검사 그대로) · so_invoice_preview(Ship Ready)는 셈만 보인다 · 반환 {deposit, credit, balance, left, steps[{step auto_deposit | auto_credit | auto_balance, payment_id | credit_id, amount, paid_on · method · reference · created_at | credit_number · issued_on}]}';
revoke all on function public.so_invoice_apply_plan(uuid, uuid, uuid[], numeric) from public, anon;
grant execute on function public.so_invoice_apply_plan(uuid, uuid, uuid[], numeric) to authenticated, service_role;

-- ═══ ③ so_tax_preview 재발행 — 원본 20261007171939_fr_1_freight_discount.sql:1 바이트 + p_over(drop + create · 시그니처가 바뀐다 · 부르는 일곱 자리는 네 인자 그대로) ═══
drop function public.so_tax_preview(uuid, date, uuid, text);
create function public.so_tax_preview(p_so_id uuid, p_on date default null, p_rule_id uuid default null, p_basis text default 'ordered', p_over jsonb default null) returns jsonb
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
                                              'surcharge_label', l.surcharge_label, 'surcharge_unit', a.sc_unit, 'surcharge_total', s.sc_amt, 'surcharge_tax', public.so_tax_amount(s.sc_amt, v_sc_rate),   -- surcharge-2a(묶음 4): 줄마다 따로 반올림
                                              'combo', exists (select 1 from public.so_line cp where cp.combo_line_id = l.id), 'combo_line_id', l.combo_line_id, 'combo_sku', (select cp.sku from public.so_line cp where cp.id = l.combo_line_id),   -- asm-2b2(묶음 5): 줄 목록은 그대로(구성품 줄은 0 원 · 합계 불변) · 문서 창구(so_invoice_issue · so_proforma)가 이 표시로 구성품 줄을 뺀다
                                              'combo_components', (select jsonb_agg(jsonb_build_object('so_line_id', cp.id, 'product_id', cp.product_id, 'sku', cp.sku, 'description', cp.product_name, 'unit', cp.unit, 'qty_per_combo', cp.combo_qty, 'qty', a.qty * cp.combo_qty) order by cp.line_no) from public.so_line cp where cp.combo_line_id = l.id)) order by l.line_no), '[]'::jsonb),   -- 「includes …」 — 이 기준(basis)의 콤보 수 × 구성품 수
         coalesce(sum(public.so_tax_amount(a.amt, v_rate)), 0), coalesce(sum(a.amt), 0),
         coalesce(sum(s.sc_amt), 0), coalesce(sum(public.so_tax_amount(s.sc_amt, v_sc_rate)), 0)
    into v_lines, v_lines_tax, v_lines_amt, v_sc_amt, v_sc_tax
  from public.so_line l0
  cross join lateral (select (case when p_over->'lines' ? l0.id::text then jsonb_populate_record(l0, (p_over->'lines'->(l0.id::text)) - 'qty') else l0 end).*) l   -- doc-1b2: 줄 덮어쓰기(unit_price · discount_pct · discount_source · surcharge_*) — 마무리가 쓰기 전의 값으로 셈한다 · p_over 없으면 l0 그대로
  cross join lateral (select case when p_over->'lines'->(l0.id::text) ? 'qty' then (p_over->'lines'->(l0.id::text)->>'qty')::numeric when p_basis = 'shipped' then l.qty_shipped else l.qty_ordered end as qty,   -- doc-1b2: 수량 덮어쓰기(보낼 수량)
                             case when p_over->'lines'->(l0.id::text) ? 'qty' then round((p_over->'lines'->(l0.id::text)->>'qty')::numeric * l.unit_price, 2) when p_basis = 'shipped' then round(l.qty_shipped * l.unit_price, 2) else public.so_line_total(l) end as amt,   -- ⓐ1: 보낸 수량 기준은 round(qty_shipped × unit_price, 2)(so_line_total 과 같은 식 · 수량만 다르다) · doc-1b2: 덮어쓴 수량도 같은 식
                             public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount) as sc_unit) a                      -- surcharge-2a(묶음 1 · 2): 개당(센트) · 수량은 물건값(amt)과 같은 것
  cross join lateral (select public.so_line_surcharge_total(a.sc_unit, a.qty) as sc_amt) s
  where l0.so_id = p_so_id;

  if coalesce(v_so.order_discount_pct, 0) > 0 then                                  -- 오더 전체 할인은 제품 줄 합계에 한 번(D6 · 운임 제외) · 세금은 그 줄에 따로(판정 3 · SO-10842 −23.12)
    v_od_amt := -round(v_lines_amt * v_so.order_discount_pct / 100, 2);
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
    'lines', v_lines, 'order_discount', jsonb_build_object('pct', v_so.order_discount_pct, 'amount', v_od_amt, 'tax', v_od_tax), 'charges', v_chg, 'charge_discounts', v_chd,   -- fr-1
    'totals', jsonb_build_object('lines_amount', v_lines_amt, 'lines_tax', v_lines_tax, 'order_discount_amount', v_od_amt, 'order_discount_tax', v_od_tax,
                                 'charges_amount', v_chg_amt, 'charges_tax', v_chg_tax,
                                 'charges_discount_amount', v_chd_amt, 'charges_discount_tax', v_chd_tax, 'charges_net_amount', v_chg_amt - v_chd_amt,   -- fr-1 판정 352 · 354: 새 열쇠(charges_amount 는 정가 합 그대로)
                                 'surcharge_amount', v_sc_amt, 'surcharge_tax', v_sc_tax,                                                     -- surcharge-2a(묶음 3): 물건값(lines_amount)과 따로 · 오더 할인 기준 밖
                                 'taxable_amount', v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt,                                                                          -- fr-1: 운임 할인을 뺀다
                                 'tax', case when v_rate is null then null else v_lines_tax + v_od_tax + v_chg_tax - v_chd_tax + v_sc_tax end,                                         -- fr-1 판정 354
                                 'total', case when v_rate is null then null else v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt + v_lines_tax + v_od_tax + v_chg_tax - v_chd_tax + v_sc_tax end),   -- fr-1
    'warnings', v_warn);
end;
$$;

comment on function public.so_tax_preview(uuid, date, uuid, text, jsonb) is '⭐ 세금 미리 보기 — 식 한 곳(§16 판정 3 · 8 · ⓐ1 basis · surcharge-2a) — 오더 규칙(manual | ship_to · 없으면 배송지로 다시) · 줄 · 오더 전체 할인 · 운임 · ⭐ surcharge 를 각자 so_tax_amount 로 줄마다 반올림해 더한다 · 줄 객체: amount · tax + surcharge_label · surcharge_unit(개당 · 센트) · surcharge_total(개당 × basis 수량) · surcharge_tax · totals: lines_amount · order_discount_amount · charges_amount · surcharge_amount(물건값과 따로 · 묶음 3) · taxable_amount(넷의 합) · tax(넷의 세금 합) · total · ⭐ 36-e 76: surcharge 세율은 v_sc_rate 한 줄(지금 = 오더 세율 · 회계사가 안 붙는다 하면 0) · so_detail · so_proforma · so_invoice_issue · so_pos_complete 가 이것을 쓴다 · [doc-1b2] p_over = 쓰기 전의 값 덮어쓰기 — lines{<line_id>: {qty · unit_price · discount_pct · discount_source · surcharge_pct · surcharge_amount · surcharge_label}}(jsonb_populate_record · qty 는 basis 수량을 대신한다) · charges[{charge_id 있으면 그 줄 고침 · 없으면 새 줄 · name · description · amount · discount_pct · discount_amount · account_code}] · null 이면 종전 그대로(so_invoice_preview 가 so_finalize 미리 보기의 값을 옮겨 쓴다)';
revoke all on function public.so_tax_preview(uuid, date, uuid, text, jsonb) from public, anon;
grant execute on function public.so_tax_preview(uuid, date, uuid, text, jsonb) to authenticated, service_role;

-- ═══ ④ so_invoice_issue 재발행 — 원본 20261007173939_fr_2_freight_discount_invoice.sql:63 바이트 + 바뀐 자리 셋(declare · 세율 고르기 → ① · 자동 붙이기 세 고리 → ② 계획대로) · 반환 그대로 ═══
create or replace function public.so_invoice_issue(p_so_ids uuid[], p_staff uuid, p_issued_on date default null) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_on       date := coalesce(p_issued_on, public.ims_today());
  v_n        int;
  v_cnt      int;
  v_bad      text;
  v_first    public.so%rowtype;
  v_so       public.so%rowtype;
  v_pt       public.ref_payment_term%rowtype;
  v_inv      public.so_invoice%rowtype;
  v_io       public.so_invoice_order%rowtype;
  v_prev     jsonb;
  v_rule_id  uuid;
  v_changed  boolean;
  v_rule     text;
  v_rate     numeric;
  v_ln       int := 0;
  v_lines_amt numeric := 0;  v_od_amt numeric := 0;  v_chg_amt numeric := 0;  v_tax numeric := 0;
  v_o_lines  numeric;  v_o_od numeric;  v_o_chg numeric;  v_o_tax numeric;
  v_sc_amt   numeric := 0;  v_o_sc numeric;  v_has_sc boolean;  v_sc_code text;  v_sc_acct public.ref_account%rowtype;   -- surcharge-2b(묶음 5 · 6)
  v_chd_amt  numeric := 0;  v_o_chd numeric;  v_has_fd boolean;  v_fd_code text;  v_fd_acct public.ref_account%rowtype;   -- fr-2 판정 352 · 358: 운임 할인 합 · 할인 줄 계정(inv_config so_freight_discount_account_code · 기본 _6_)
  v_orders   jsonb := '[]'::jsonb;
  v_warn     text[] := '{}';
  e          jsonb;
  -- ⓑ2 자동 붙이기
  v_total    numeric;
  v_deposit  numeric := 0;
  v_balance  numeric := 0;
  v_applied  jsonb := '[]'::jsonb;
  v_a        public.so_payment_alloc%rowtype;
  v_plan     jsonb;                                                                     -- doc-1b2: 자동 붙이기 계획(so_invoice_apply_plan · 미리 보기와 같은 식)
  -- ⓒ2 크레딧부터(8-e · 판정 5)
  v_credit   numeric := 0;
  v_ca       public.so_credit_alloc%rowtype;
begin
  if p_staff is null then raise exception 'so_invoice_issue needs the acting staff id — nothing was saved'; end if;
  if v_on > public.ims_today() then raise exception 'Invoice date % is in the future — nothing was saved', v_on; end if;
  v_cnt := coalesce(array_length(p_so_ids, 1), 0);
  if v_cnt = 0 then raise exception 'An invoice needs at least one order — nothing was saved'; end if;
  select count(distinct x) into v_n from unnest(p_so_ids) x;
  if v_n <> v_cnt then raise exception 'The same order is listed twice — nothing was saved'; end if;

  -- 잠금(번호 순) · 존재 · 상태 · 이미 담김 · 청구처 · 통화
  perform s.id from public.so s where s.id = any(p_so_ids) order by s.so_number for update;
  select count(*) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n <> v_cnt then raise exception 'Order not found — nothing was saved'; end if;
  select string_agg(s.so_number || ' (' || s.status || ')', ', ' order by s.so_number) into v_bad
  from public.so s where s.id = any(p_so_ids) and (s.status <> 'shipped' or s.shipped_at is null);
  if v_bad is not null then raise exception 'Only shipped orders can be invoiced — % — nothing was saved', v_bad; end if;
  select string_agg(s.so_number || ' is on invoice ' || i.invoice_number, ', ' order by s.so_number) into v_bad
  from public.so_invoice_order o join public.so s on s.id = o.so_id join public.so_invoice i on i.id = o.invoice_id
  where o.so_id = any(p_so_ids) and o.cancelled_at is null;
  if v_bad is not null then raise exception 'Order already invoiced — % — cancel that invoice first — nothing was saved', v_bad; end if;
  select string_agg(s.so_number, ', ' order by s.so_number) into v_bad from public.so s where s.id = any(p_so_ids) and s.bill_to_customer_id is null;
  if v_bad is not null then raise exception 'Order % has no bill-to customer — nothing was saved', v_bad; end if;
  select count(distinct s.bill_to_customer_id) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One invoice bills one customer — these orders have different bill-to customers, split them — nothing was saved'; end if;
  select count(distinct s.currency_id) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One invoice has one currency — these orders have different currencies, split them — nothing was saved'; end if;

  select * into v_first from public.so s where s.id = any(p_so_ids) order by s.so_number limit 1;
  perform 1 from public.customer c where c.id = v_first.bill_to_customer_id for update;   -- ⓑ2: 청구처 손님 행 잠금(잔액 검사 직렬화 · so_payment_* 창구와 같은 자물쇠)

  -- 결제조건 · 기한(판정 10)
  if v_first.payment_term_id is not null then
    select * into v_pt from public.ref_payment_term t where t.id = v_first.payment_term_id;
  end if;
  if v_pt.id is null then
    v_warn := v_warn || array['payment_term_missing', 'due_date_unknown'];
  elsif v_pt.net_days is null then
    v_warn := array_append(v_warn, 'due_date_unknown');
  end if;
  if coalesce(v_pt.is_split, false) then v_warn := array_append(v_warn, 'split_terms'); end if;
  if (select count(distinct coalesce(s.payment_term_id::text, '')) from public.so s where s.id = any(p_so_ids)) > 1 then v_warn := array_append(v_warn, 'payment_term_differs'); end if;
  if exists (select 1 from public.so s where s.id = any(p_so_ids)
              and (s.bill_to_name, s.bill_to_line1, s.bill_to_line2, s.bill_to_city, s.bill_to_state_province, s.bill_to_postal_code, s.bill_to_country)
                  is distinct from (v_first.bill_to_name, v_first.bill_to_line1, v_first.bill_to_line2, v_first.bill_to_city, v_first.bill_to_state_province, v_first.bill_to_postal_code, v_first.bill_to_country)) then
    v_warn := array_append(v_warn, 'bill_to_differs');
  end if;

  -- surcharge 계정(surcharge-2b · 묶음 6) — 담긴 오더에 보낸 surcharge 줄이 있으면 ⭐ 머리 insert(번호를 당긴다) 앞에서 계정을 잡는다 · 비었거나 · 없거나 · 꺼졌으면 surcharge 있는 발행만 막는다 · 없는 발행은 지금처럼
  select exists (select 1 from public.so_line l where l.so_id = any(p_so_ids) and l.surcharge_label is not null and l.qty_shipped > 0) into v_has_sc;
  if v_has_sc then
    select nullif(k.value, '') into v_sc_code from public.inv_config k where k.key = 'so_surcharge_account_code';
    if v_sc_code is null then raise exception 'Surcharge account is not set — set inv_config so_surcharge_account_code (e.g. _94_) before invoicing an order with a surcharge — nothing was saved'; end if;
    select * into v_sc_acct from public.ref_account a where a.code = v_sc_code;
    if v_sc_acct.id is null then raise exception 'Surcharge account % (inv_config so_surcharge_account_code) is not in the chart of accounts — nothing was saved', v_sc_code; end if;
    if not v_sc_acct.is_active then raise exception 'Surcharge account % (%) is inactive — pick an active account in inv_config so_surcharge_account_code — nothing was saved', v_sc_acct.code, v_sc_acct.name; end if;
  end if;
  -- 운임 할인 계정(fr-2 판정 358 · surcharge 와 같은 모양) — 담긴 오더에 할인이 걸린 운임 줄이 있으면 머리 insert 앞에서 계정을 잡는다 · 비었거나 · 없거나 · 꺼졌으면 할인 운임이 있는 발행만 막는다
  select exists (select 1 from public.so_charge c where c.so_id = any(p_so_ids) and (c.discount_pct is not null or c.discount_amount is not null)) into v_has_fd;
  if v_has_fd then
    select nullif(k.value, '') into v_fd_code from public.inv_config k where k.key = 'so_freight_discount_account_code';
    if v_fd_code is null then raise exception 'Freight discount account is not set — set inv_config so_freight_discount_account_code (e.g. _6_ Sales Discounts) before invoicing an order with a freight discount — nothing was saved'; end if;
    select * into v_fd_acct from public.ref_account a where a.code = v_fd_code;
    if v_fd_acct.id is null then raise exception 'Freight discount account % (inv_config so_freight_discount_account_code) is not in the chart of accounts — nothing was saved', v_fd_code; end if;
    if not v_fd_acct.is_active then raise exception 'Freight discount account % (%) is inactive — pick an active account in inv_config so_freight_discount_account_code — nothing was saved', v_fd_acct.code, v_fd_acct.name; end if;
  end if;

  -- 머리(합계는 0 으로 넣고 오더를 돌며 채운다 · CHECK 셋은 0 에서도 맞다)
  insert into public.so_invoice (bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_line2, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country,
                                 issued_on, issued_by, payment_term_id, payment_term_name, due_on, currency_id, currency_code, updated_by)
  values (v_first.bill_to_customer_id, v_first.bill_to_name, v_first.bill_to_line1, v_first.bill_to_line2, v_first.bill_to_city, v_first.bill_to_state_province, v_first.bill_to_postal_code, v_first.bill_to_country,
          v_on, p_staff, v_pt.id, coalesce(v_pt.name, v_first.payment_term_name), case when v_pt.net_days is not null then v_on + v_pt.net_days end, v_first.currency_id, v_first.currency_code, p_staff)
  returning * into v_inv;

  -- 오더마다 — 규칙 · 금액(식 한 곳 · 보낸 수량) · 담긴 오더 줄 · 줄 사본 · 상태 전이
  for v_so in select * from public.so s where s.id = any(p_so_ids) order by s.so_number loop
    v_rule_id := public.so_invoice_rule_pick(v_so, v_on);                             -- doc-1b2: 세율 고르기 한 곳(미리 보기 so_invoice_preview 와 같은 함수)
    v_changed := v_rule_id is distinct from v_so.tax_rule_id;
    v_prev := public.so_tax_preview(v_so.id, v_on, v_rule_id, 'shipped');          -- explicit 규칙 · 활성 sale 아니면 이 함수가 거부한다
    v_rule := v_prev->'rule'->>'rule';  v_rate := (v_prev->'rule'->>'rate_pct')::numeric;
    v_o_lines := (v_prev->'totals'->>'lines_amount')::numeric;  v_o_od := (v_prev->'totals'->>'order_discount_amount')::numeric;
    v_o_chg   := (v_prev->'totals'->>'charges_amount')::numeric;  v_o_tax := (v_prev->'totals'->>'tax')::numeric;
    v_o_sc    := coalesce((v_prev->'totals'->>'surcharge_amount')::numeric, 0);                                             -- surcharge-2b: 이 오더 몫 · tax 는 2a 부터 surcharge 세금을 이미 품는다
    v_o_chd   := coalesce((v_prev->'totals'->>'charges_discount_amount')::numeric, 0);                                      -- fr-2 판정 352: 이 오더의 운임 할인 합(fr-1 so_tax_preview · tax 는 할인 세금을 이미 뺐다 · 354)
    if v_o_lines + v_o_od + v_o_chg = 0 and not exists (select 1 from public.so_line l where l.so_id = v_so.id and l.qty_shipped > 0) then
      raise exception 'Order % shipped nothing — there is nothing to invoice — nothing was saved', v_so.so_number;
    end if;

    insert into public.so_invoice_order (invoice_id, so_id, so_number, customer_id,
                                         ship_to_company, ship_to_contact, ship_to_phone, ship_to_line1, ship_to_line2, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country,
                                         tax_rule_id, tax_rule, rate_pct, tax_source, draft_rule_changed,
                                         lines_amount, order_discount_pct, order_discount_amount, charges_amount, charges_discount_amount, surcharge_amount, taxable_amount, tax_amount, total, updated_by)   -- fr-2
    values (v_inv.id, v_so.id, v_so.so_number, v_so.customer_id,
            v_so.ship_to_company, v_so.ship_to_contact, v_so.ship_to_phone, v_so.ship_to_line1, v_so.ship_to_line2, v_so.ship_to_city, v_so.ship_to_state_province, v_so.ship_to_postal_code, v_so.ship_to_country,
            v_rule_id, v_rule, v_rate, case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, v_changed,
            v_o_lines, v_so.order_discount_pct, v_o_od, v_o_chg, v_o_chd, v_o_sc, v_o_lines + v_o_od + v_o_chg - v_o_chd + v_o_sc, v_o_tax, v_o_lines + v_o_od + v_o_chg - v_o_chd + v_o_sc + v_o_tax, p_staff)   -- fr-2: 운임 할인을 뺀다
    returning * into v_io;

    for e in select x from jsonb_array_elements(v_prev->'lines') x loop                     -- 제품 줄(보낸 수량 > 0 만 · 안 나간 줄은 종이에 없다)
      if (e->>'qty')::numeric > 0 and nullif(e->>'combo_line_id', '') is null then                  -- asm-2b2(묶음 5): 구성품 줄은 종이에 없다 · 콤보 줄은 product 줄(qty = 나간 콤보 수) + 「includes …」 를 combo_components 에 굳힌다(so_line 이 뒤에 바뀌어도 그대로)
        v_ln := v_ln + 1;
        insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, unit, pack_factor, qty, list_price, discount_pct, discount_source, unit_price, amount, tax_amount, account_id, account_code, updated_by, combo_components)
        values (v_inv.id, v_io.id, v_ln, 'product', (e->>'line_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
                (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, e->>'discount_source', (e->>'unit_price')::numeric, (e->>'amount')::numeric, (e->>'tax')::numeric,
                v_so.sale_account_id, v_so.sale_account_code, p_staff, nullif(e->'combo_components', 'null'::jsonb));
        if coalesce((e->>'surcharge_total')::numeric, 0) > 0 then                        -- surcharge-2b(묶음 5): 그 상품 줄 바로 뒤 · 값은 so_tax_preview 줄 객체에서(2a 계산 한 곳 · 다시 세지 않는다) · 계정 = inv_config so_surcharge_account_code
          v_ln := v_ln + 1;
          insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, qty, unit_price, amount, tax_amount, account_id, account_code, updated_by)
          values (v_inv.id, v_io.id, v_ln, 'surcharge', (e->>'line_id')::uuid, e->>'sku', e->>'surcharge_label', (e->>'qty')::numeric, (e->>'surcharge_unit')::numeric, (e->>'surcharge_total')::numeric, (e->>'surcharge_tax')::numeric,
                  v_sc_acct.id, v_sc_acct.code, p_staff);
        end if;
      end if;
    end loop;
    if v_o_od <> 0 then                                                                    -- 오더 전체 할인 줄 하나(D6 · 음수 · 세금 따로 · §16 판정 3)
      v_ln := v_ln + 1;
      insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, description, amount, tax_amount, account_id, account_code, updated_by)
      values (v_inv.id, v_io.id, v_ln, 'order_discount', format('Order discount %s%%', v_so.order_discount_pct), v_o_od, (v_prev->'order_discount'->>'tax')::numeric, v_so.sale_account_id, v_so.sale_account_code, p_staff);
    end if;
    for e in select x from jsonb_array_elements(v_prev->'charges') x loop                   -- 운임·서비스 줄 전부(0 도 · 무료 배송 흔적 · 1-p)
      v_ln := v_ln + 1;
      insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_charge_id, description, amount, tax_amount, account_id, account_code, updated_by)
      values (v_inv.id, v_io.id, v_ln, 'charge', (e->>'charge_id')::uuid, e->>'name' || coalesce(' — ' || (e->>'description'), ''), (e->>'amount')::numeric, (e->>'tax')::numeric,
              (e->>'account_id')::uuid, e->>'account_code', p_staff);
      if coalesce((e->>'discount')::numeric, 0) > 0 then                                   -- fr-2 판정 352 · 354: 할인 줄은 그 운임 줄 바로 뒤 · 음수 · 세금은 할인 줄 몫(so_tax_preview 가 따로 반올림) · 계정 = inv_config so_freight_discount_account_code
        v_ln := v_ln + 1;
        insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_charge_id, description, discount_pct, amount, tax_amount, account_id, account_code, updated_by)
        values (v_inv.id, v_io.id, v_ln, 'charge_discount', (e->>'charge_id')::uuid,
                (e->>'name') || ' discount' || case when nullif(e->>'discount_pct', '') is not null then format(' %s%%', trim_scale((e->>'discount_pct')::numeric)) else '' end,
                nullif(e->>'discount_pct', '')::numeric, -(e->>'discount')::numeric, -coalesce((e->>'discount_tax')::numeric, 0), v_fd_acct.id, v_fd_acct.code, p_staff);
      end if;
    end loop;

    v_lines_amt := v_lines_amt + v_o_lines;  v_od_amt := v_od_amt + v_o_od;  v_chg_amt := v_chg_amt + v_o_chg;  v_tax := v_tax + v_o_tax;  v_sc_amt := v_sc_amt + v_o_sc;   -- surcharge-2b
    v_chd_amt := v_chd_amt + v_o_chd;                                                                                                                              -- fr-2
    if v_changed then v_warn := array_append(v_warn, 'draft_rule_changed:' || v_so.so_number); end if;
    if coalesce(v_prev->'warnings', '[]'::jsonb) ? 'tax_rule_inactive' then v_warn := array_append(v_warn, 'tax_rule_inactive:' || v_so.so_number); end if;

    update public.so set status = 'fulfilled', invoiced_at = now(), closed_at = now(), updated_by = p_staff where id = v_so.id and status = 'shipped';   -- ⓑ2 판정 1: 문지기 짝 shipped→fulfilled · 끝 상태 closed_at 짝(so_closed_at_ck)
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Order % was not invoiced — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'tax_rule', v_rule, 'rate_pct', v_rate,
                                               'tax_source', case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, 'draft_rule_changed', v_changed, 'totals', v_prev->'totals');
  end loop;

  -- 합계를 먼저 굳힌다(so_invoice_remaining 이 total 을 본다) · 잔액 항은 아직 0
  v_total := v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt + v_tax;                                                               -- surcharge-2b · fr-2 운임 할인을 뺀다
  update public.so_invoice set lines_amount = v_lines_amt, order_discount_amount = v_od_amt, charges_amount = v_chg_amt, charges_discount_amount = v_chd_amt, surcharge_amount = v_sc_amt,   -- fr-2
                               taxable_amount = v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt, tax_amount = v_tax, total = v_total, amount_due = v_total, updated_by = p_staff
  where id = v_inv.id returning * into v_inv;

  -- doc-1b2: ⓑ2 ① 선수금 · ⓒ2 ② 크레딧 · ⓑ2 ③ 받아 둔 돈 — 셈은 so_invoice_apply_plan 하나(미리 보기 so_invoice_preview 와 같은 식 · 쓰지 않는다) · 여기서는 그 계획대로 붙인다(한도 검사는 alloc_add 가 그대로)
  v_plan := public.so_invoice_apply_plan(v_inv.bill_to_customer_id, v_inv.currency_id, p_so_ids, v_total);
  for e in select x from jsonb_array_elements(v_plan->'steps') x loop
    if e->>'step' = 'auto_credit' then
      v_ca := public.so_credit_alloc_add((e->>'credit_id')::uuid, v_inv.id, (e->>'amount')::numeric, 'auto', p_staff);
      v_credit := v_credit + v_ca.amount;
      v_applied := v_applied || jsonb_build_object('alloc_id', v_ca.id, 'credit_id', e->'credit_id', 'credit_number', e->>'credit_number', 'source', 'auto_credit', 'amount', v_ca.amount, 'issued_on', e->'issued_on');
    else
      v_a := public.so_payment_alloc_add((e->>'payment_id')::uuid, v_inv.id, (e->>'amount')::numeric, e->>'step', p_staff);
      if e->>'step' = 'auto_deposit' then v_deposit := v_deposit + v_a.amount; else v_balance := v_balance + v_a.amount; end if;
      v_applied := v_applied || jsonb_build_object('alloc_id', v_a.id, 'payment_id', e->'payment_id', 'source', e->>'step', 'amount', v_a.amount, 'paid_on', e->'paid_on', 'method', e->>'method', 'reference', e->'reference');
    end if;
  end loop;

  -- 종이에 찍히는 값을 굳힌다 — 받은 금액(deposit_applied) · 이전 잔액(balance_forward = −(크레딧 ② + 받아 둔 돈 ③) · 0 이하 · 봤는데 없으면 0 · 한 줄 8-c) · credit_applied(② 몫 · 회계 근거 · ⬜7) · 보내실 금액(amount_due · CHECK so_invoice_due_ck)
  update public.so_invoice set deposit_applied = v_deposit, credit_applied = v_credit, balance_forward = -(v_credit + v_balance), amount_due = v_total - v_deposit - v_credit - v_balance, updated_by = p_staff
  where id = v_inv.id returning * into v_inv;

  return jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status, 'issued_on', v_on, 'due_on', v_inv.due_on,
                            'bill_to_customer_id', v_inv.bill_to_customer_id, 'bill_to_name', v_inv.bill_to_name, 'payment_term_name', v_inv.payment_term_name, 'currency_code', v_inv.currency_code,
                            'orders', v_orders, 'lines', v_ln,
                            'totals', jsonb_build_object('lines_amount', v_inv.lines_amount, 'order_discount_amount', v_inv.order_discount_amount, 'charges_amount', v_inv.charges_amount, 'charges_discount_amount', v_inv.charges_discount_amount, 'surcharge_amount', v_inv.surcharge_amount,   -- fr-2
                                                         'taxable_amount', v_inv.taxable_amount, 'tax_amount', v_inv.tax_amount, 'total', v_inv.total,
                                                         'deposit_applied', v_inv.deposit_applied, 'credit_applied', v_inv.credit_applied, 'balance_forward', v_inv.balance_forward, 'amount_due', v_inv.amount_due,
                                                         'remaining', public.so_invoice_remaining(v_inv.id)),
                            'applied', v_applied,
                            'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id),
                            'warnings', to_jsonb(v_warn));
end;
$$;

comment on function public.so_invoice_issue(uuid[], uuid, date) is '⭐⭐ 인보이스 발행 — 식 한 곳(§17 · ⓐ2 · ⓑ2 · ⓒ2 · surcharge-2b) · invoker · p_staff 필수 · shipped 오더 묶음(같은 청구처 · 같은 통화) · 오더마다 so_tax_preview(…, ''shipped'')의 totals 로 so_invoice_order(lines · od · charges · ⭐ surcharge_amount · taxable · tax · total) · 줄 사본 product(qty > 0) → ⭐ surcharge(그 상품 줄 바로 뒤 · so_tax_preview 줄 객체의 surcharge_label · surcharge_unit · surcharge_total · surcharge_tax · so_line_id 같음 · 계정 inv_config so_surcharge_account_code — 보낸 surcharge 줄이 있는데 키가 비었거나 계정이 없거나 꺼졌으면 머리 insert 앞에서 거부) → order_discount → charge · 머리 합계(surcharge_amount 포함 · CHECK 셋) · 선결제 · 크레딧 · 받아 둔 돈 자동 붙이기 · amount_due · so_finalize · so_pos_complete · so_invoice_reissue 가 부른다 · [doc-1b2] 세율 고르기는 so_invoice_rule_pick · 자동 붙이기(선수금 · 크레딧 · 받아 둔 돈)는 so_invoice_apply_plan 의 계획대로 alloc_add — Ship Ready 미리 보기(so_invoice_preview)와 같은 식';

-- ═══ ⑤ so_invoice_preview — Ship Ready: so_finalize 미리 보기(수량 · 다시 매긴 단가 · 운임 · 부가 요금 · 묶음) → p_over → so_tax_preview(shipped) → 발행과 같은 순서의 줄 · 합계 · ② 계획 · 중립 jsonb(doc_data_invoice_fmt 가 먹는 것) ═══
create function public.so_invoice_preview(p_orders jsonb, p_shipped_on date default null) returns jsonb
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
                                                   'is_free', sl.free_reason is not null, 'no_price', (l->>'unit_price') is null) order by (l->>'line_no')::int), '[]'::jsonb)
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
comment on function public.so_invoice_preview(jsonb, date) is 'doc-1b2 — Ship Ready(PROFORMA)의 숫자: so_finalize(p_orders, false) 가 돌려준 묶음 · 보낼 수량(picked) · 다시 매긴 단가 · 부가 요금 · 운임 고침을 p_over 로 so_tax_preview(shipped) 에 넘겨 발행(so_invoice_issue)과 같은 식 · 같은 순서(제품 → surcharge → 오더 할인 → 운임 → 운임 할인)로 줄을 세우고 so_invoice_apply_plan 으로 붙을 돈을 셈한다 · 발행일 = 오늘(ims_today — so_finalize 가 so_invoice_issue 에 null 을 넘긴다) · 아무것도 쓰지 않는다 · 묶음마다 중립 jsonb 하나(docs) — doc_data_invoice_fmt 가 문서로 그린다 · ⚠️ 미리 보기와 실제 발행 사이에 바뀔 수 있는 것(doc-0 Q2 ⑥): 세율(날짜) · 결제 · 크레딧 · WMS 픽 · 묶음 — calc_at 을 종이에 찍는다';
revoke all on function public.so_invoice_preview(jsonb, date) from public, anon;
grant execute on function public.so_invoice_preview(jsonb, date) to authenticated, service_role;

-- ═══ ⑥ doc_data_invoice 를 둘로 — loader(표 → 중립) + fmt(중립 → 문서) · ship_ready · doc_data 재발행 ═══
-- 중립 jsonb: header{number · issued_on · due_on · payment_term_name · currency_code · memo · bill_to_customer_id · bill_to{7}} · orders[{so_number · reference · carrier · tracking · tax_rule · order_discount_pct · ship_to{9} · lines[{product_id · sku · description · comment · unit · qty · list_price · discount_pct · unit_price · amount · tax_amount · is_free · no_price}]}]
--            · charges[{so_number · kind · account_code · description · comment · qty · unit_price · discount_pct · amount · tax_amount}] · payments[{reference · paid_on · method · amount}] · totals{order_discount · surcharge · taxable · tax · total · deposit_applied · credit_applied · balance_forward · paid · amount_due} · calc_at
create function public.doc_data_invoice_fmt(p_kind text, p_cfg jsonb, p_n jsonb) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_fmt  text := p_cfg->>'date_format';
  v_disp text := coalesce(p_cfg->>'unit_display', 'both');
  v_h    jsonb := p_n->'header';  v_t jsonb := p_n->'totals';
  v_orders jsonb;  v_charges jsonb;  v_payments jsonb;  v_inv jsonb;
  v_lines_amt numeric;  v_lines_tax numeric;  v_qty numeric;  v_chg_amt numeric;  v_chg_tax numeric;  v_chd numeric;
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
                                                || public.doc_unit_prices((ln.l->>'unit_price')::numeric, (ln.od_pct)::numeric, v_disp)) order by ln.no), '[]'::jsonb)
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
                                 'deposit_applied', public.doc_fmt_money((v_t->>'deposit_applied')::numeric), 'credit_applied', public.doc_fmt_money((v_t->>'credit_applied')::numeric), 'balance_forward', public.doc_fmt_money((v_t->>'balance_forward')::numeric),
                                 'paid', public.doc_fmt_money((v_t->>'paid')::numeric), 'due_label', case when (v_t->>'amount_due')::numeric > 0 then 'Due' when (v_t->>'amount_due')::numeric < 0 then 'Credit' else 'Paid' end, 'due_amount', public.doc_fmt_money((v_t->>'amount_due')::numeric)))
    || public.doc_data_common(p_kind, p_cfg, (v_h->'bill_to') || public.doc_contact(nullif(v_h->>'bill_to_customer_id', '')::uuid));
end;
$$;
comment on function public.doc_data_invoice_fmt(text, jsonb, jsonb) is 'doc-1b2 — 인보이스 꼴 문서(final_invoice · internal_receipt · ship_ready)의 그리기 한 곳: 중립 jsonb(표에서 온 것 · 또는 so_invoice_preview 의 미리 보기) → doc_field_catalog 의 열쇠 · 꼴 · 줄 번호 · 판정 314 단가 칸 · ship_ready 는 invoice.number 대신 invoice.calc_at';
revoke all on function public.doc_data_invoice_fmt(text, jsonb, jsonb) from public, anon, authenticated;

-- doc_data_invoice 재발행 — 원본 20261019152102:215 의 「읽기」 만 남기고 「그리기」 는 위 fmt 로(같은 시그니처 · 값 같음 — 검증 P · doc-1b1 F1 ~ F4 다시)
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
                                                                        'unit_price', l.unit_price, 'amount', l.amount, 'tax_amount', l.tax_amount, 'is_free', sl.free_reason is not null, 'no_price', l.unit_price is null) order by l.line_no), '[]'::jsonb)
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
                                 'amount_due', v_inv.amount_due));
  return public.doc_data_invoice_fmt(p_kind, p_cfg, v_n);
end;
$$;

create function public.doc_data_ship_ready(p_ref jsonb, p_cfg jsonb) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare
  v_pv jsonb;
begin
  if p_ref->'orders' is null or jsonb_typeof(p_ref->'orders') <> 'array' then raise exception 'p_ref needs orders — the same array Ship & invoice sends (plus an optional shipped_on)'; end if;
  v_pv := public.so_invoice_preview(p_ref->'orders', nullif(p_ref->>'shipped_on', '')::date);
  return (select coalesce(jsonb_agg(public.doc_data_invoice_fmt('ship_ready', p_cfg, d) || jsonb_build_object('_group', d->>'group', '_so_ids', d->'so_ids', '_warnings', d->'warnings') order by ord), '[]'::jsonb)
          from jsonb_array_elements(v_pv->'docs') with ordinality t(d, ord));
end;
$$;
comment on function public.doc_data_ship_ready(jsonb, jsonb) is 'doc-1b2 — ship_ready 문서들(묶음마다 하나): so_invoice_preview → doc_data_invoice_fmt · _group · _so_ids · _warnings 는 화면용 꼬리(자리표 목록 밖 — 판이 쓰지 않는다 · doc_data 가 뗀다)';
revoke all on function public.doc_data_ship_ready(jsonb, jsonb) from public, anon, authenticated;

-- doc_data 재발행 — 원본 20261019152102:413 + ship_ready 갈래 · ⚠️ stable → volatile(so_finalize 미리 보기가 for update 를 잡는다 — PostgREST 는 stable 창구를 읽기 전용 트랜잭션에서 돌린다) · 쓰는 것은 없다
create or replace function public.doc_data(p_kind text, p_ref jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_cfg jsonb;
  v_doc jsonb;
begin
  perform public.doc_staff_or_service();                                                           -- ⭐ 문 — 첫 줄(활성 직원 · service_role)
  if p_kind not in ('final_invoice', 'internal_receipt', 'credit_note', 'sales_order', 'ship_ready') then raise exception 'Unknown document kind % — final_invoice, internal_receipt, credit_note, sales_order or ship_ready', coalesce(p_kind, '(null)'); end if;
  if p_ref is null or jsonb_typeof(p_ref) <> 'object' then raise exception 'p_ref must be a JSON object like {"invoice_id": "…"}'; end if;
  v_cfg := public.doc_config();
  if p_kind = 'ship_ready' then
    return jsonb_build_object('kind', p_kind, 'docs', (select coalesce(jsonb_agg(d - '_group' - '_so_ids' - '_warnings' order by ord), '[]'::jsonb) from jsonb_array_elements(public.doc_data_ship_ready(p_ref, v_cfg)) with ordinality t(d, ord)),
                              'groups', (select coalesce(jsonb_agg(jsonb_build_object('group', d->>'_group', 'so_ids', d->'_so_ids', 'warnings', d->'_warnings') order by ord), '[]'::jsonb) from jsonb_array_elements(public.doc_data_ship_ready(p_ref, v_cfg)) with ordinality t(d, ord)));
  end if;
  if p_kind in ('final_invoice', 'internal_receipt') then
    if nullif(p_ref->>'invoice_id', '') is null then raise exception 'p_ref needs invoice_id'; end if;
    v_doc := public.doc_data_invoice(p_kind, (p_ref->>'invoice_id')::uuid, v_cfg);
  elsif p_kind = 'credit_note' then
    if nullif(p_ref->>'credit_id', '') is null then raise exception 'p_ref needs credit_id'; end if;
    v_doc := public.doc_data_credit((p_ref->>'credit_id')::uuid, v_cfg);
  else
    if nullif(p_ref->>'so_id', '') is null then raise exception 'p_ref needs so_id'; end if;
    v_doc := public.doc_data_so((p_ref->>'so_id')::uuid, v_cfg);
  end if;
  return jsonb_build_object('kind', p_kind, 'docs', jsonb_build_array(v_doc));
end;
$$;
comment on function public.doc_data(text, jsonb) is 'doc-1b1 — 문서 데이터 창구: 판(Mustache)이 먹을 값을 doc_field_catalog(kind) 와 똑같은 열쇠로 · {kind, docs: [문서]} · p_ref = {invoice_id} | {credit_id} | {so_id} | [doc-1b2] ship_ready {orders: Ship & invoice 가 보내는 p_orders 그대로, shipped_on?} → docs 는 묶음마다 하나 + groups[{group, so_ids, warnings}] · 값은 전부 글자 꼴과 JSON 불리언 · 빈 값 "" · 문 = doc_staff_or_service(ship_ready 는 그 안의 so_finalize 가 sales 쓰기를 또 묻는다) · 없는 id 거부 · ⚠️ volatile(ship_ready 의 so_finalize 미리 보기가 for update 를 잡는다) — 쓰는 것은 없다 · 원천: final_invoice · internal_receipt = so_invoice 표 셋 · credit_note = so_credit 표 둘 · sales_order = so_proforma · ship_ready = so_invoice_preview(발행과 같은 식)';
revoke all on function public.doc_data(text, jsonb) from public, anon;
grant execute on function public.doc_data(text, jsonb) to authenticated, service_role;

-- ═══ ⑦ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if to_regprocedure('public.so_tax_preview(uuid, date, uuid, text)') is not null then v_bad := v_bad || ' old-tax-preview-still-there'; end if;
  if to_regprocedure('public.so_tax_preview(uuid, date, uuid, text, jsonb)') is null then v_bad := v_bad || ' tax-preview'; end if;
  if (select count(*) from pg_proc where proname = 'so_tax_preview') <> 1 or (select count(*) from pg_proc where proname = 'so_invoice_issue') <> 1 or (select count(*) from pg_proc where proname = 'doc_data') <> 1 then v_bad := v_bad || ' dup-names'; end if;
  if (select prosrc from pg_proc where oid = 'public.so_invoice_issue(uuid[], uuid, date)'::regprocedure) !~ 'so_invoice_apply_plan' or (select prosrc from pg_proc where oid = 'public.so_invoice_issue(uuid[], uuid, date)'::regprocedure) !~ 'so_invoice_rule_pick' then v_bad := v_bad || ' issue-body'; end if;
  if (select provolatile from pg_proc where oid = 'public.doc_data(text, jsonb)'::regprocedure) <> 'v' then v_bad := v_bad || ' doc_data-volatile'; end if;
  if (select prosrc from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) !~ 'doc_data_invoice_fmt' then v_bad := v_bad || ' invoice-loader'; end if;
  if not has_function_privilege('authenticated', 'public.so_tax_preview(uuid, date, uuid, text, jsonb)', 'execute') or has_function_privilege('anon', 'public.so_tax_preview(uuid, date, uuid, text, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.so_invoice_preview(jsonb, date)', 'execute') or has_function_privilege('authenticated', 'public.doc_data_ship_ready(jsonb, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if (select count(*) from pg_proc p where p.prosrc like '%so_tax_preview(%' and p.proname <> 'so_tax_preview' and p.pronamespace = 'public'::regnamespace) < 6 then v_bad := v_bad || ' callers'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM511', message = format('STOP - doc-1b2 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
