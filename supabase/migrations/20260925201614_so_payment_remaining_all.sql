-- SO 결제 남은 금액 — 인라인 복사 식 일곱 자리를 so_payment_remaining 한 곳으로 (so-pay-remaining-2 · 2026-09-25 UTC · 토론토 2026-09-25 밤)
-- 지시서 ~/asung/prompts/so-pay-remaining-2.md · 판정 Caleb 2026-09-25(0-1 앞 차수 5507e0c 커밋 뒤 · 0-2 셋 더해 일곱 · 0-3 붙임 합·개수는 대상 아님 · ⬜1 근거 표 · ⬜2 검증 A(번호 소모 0) · ⬜3 한 차수)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 시험 적용 + 검증 ~/asung/prompts/so-pay-remaining-2-verify.sql(-v mig)
-- 바탕: so_payment_remaining(20260925195701 P0 · 취소 0 · 환불 null · 그 밖 amount − Σ활성 so_payment_alloc) · so_customer_balance · so_invoice_detail 은 그 파일이 이미 바꿨다
-- ⭐ 재발행 일곱 — 마지막 정의 → 바이트 그대로 → 바뀐 줄은 인라인 식 → public.so_payment_remaining(p.id | v_p.id) 뿐 · 시그니처·반환·grant 무변(create or replace)
--    so_invoice_issue(2줄 · ①·③ 커서) · so_proforma(1) · so_pos_complete(2) · so_pos_open_list(1) · so_payment_alloc_add(1 · 한도 검사) · so_payment_attach(1 · 반환) · so_payment_detach(1 · 반환)
-- ⭐ ⬜1 새 함수(취소 0 · 환불 null)가 값을 바꾸지 않는 근거 — 일곱 자리 전부 그 식이 도는 행은 status active ∧ kind payment 다:
--    so_invoice_issue :350(①) · :389(③)   커서 WHERE p.status = 'active' and p.kind = 'payment'
--    so_proforma :541                        서브쿼리 WHERE active ∧ payment
--    so_pos_complete :749 · :767             커서·합계 WHERE active ∧ payment
--    so_pos_open_list :165                   합계 WHERE active ∧ payment
--    so_payment_alloc_add :370               그 앞 :356~357 에서 status <> 'active' · kind <> 'payment' 면 이미 raise
--    so_payment_attach :520                  반환 직전 — alloc_add 가 한 번이라도 돌았으니 active·payment(안 돌면 :506 이 raise)
--    so_payment_detach :555                  v_p 는 활성 붙임의 결제 — void 는 활성 붙임이 있으면 거부(:605)라 voided 일 수 없고 환불은 so_payment_alloc 이 없다
-- ⚠️ 대상이 아닌 것(0-3): so_invoice_remaining(인보이스 쪽) · 뷰 so_invoice_list·so_payment_list 의 attached(붙임 합) · so_payment_detail 의 attached_from_this_payment · so_payment_void :604 · so_invoice_cancel :466(개수·합) — 「결제 남은 금액」이 아니다
-- ⚠️ 검증(⬜2 A): 발행 ①·③ 커서 SELECT 를 떼어 옛 식 vs 새 함수 행 집합 대조 · so_pos_complete(p_commit false) · so_proforma · so_pos_open_list jsonb 전후 대조 · alloc_add/attach/detach 는 savepoint 안 전후 대조 · 인보이스 번호 소모 0

-- ═══ so_invoice_issue 재발행 — 마지막 정의 20260925014413_so_credit_c2.sql:183~420 · 바이트 그대로 · 바뀐 줄 2(인라인 식 → so_payment_remaining) · create or replace 그대로 ═══
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
  v_pick     jsonb;
  v_prev     jsonb;
  v_rule_id  uuid;
  v_changed  boolean;
  v_rule     text;
  v_rate     numeric;
  v_ln       int := 0;
  v_lines_amt numeric := 0;  v_od_amt numeric := 0;  v_chg_amt numeric := 0;  v_tax numeric := 0;
  v_o_lines  numeric;  v_o_od numeric;  v_o_chg numeric;  v_o_tax numeric;
  v_orders   jsonb := '[]'::jsonb;
  v_warn     text[] := '{}';
  e          jsonb;
  -- ⓑ2 자동 붙이기
  v_total    numeric;
  v_deposit  numeric := 0;
  v_balance  numeric := 0;
  v_avail    numeric;
  v_recv     numeric;
  v_left     numeric;
  v_take     numeric;
  v_applied  jsonb := '[]'::jsonb;
  v_a        public.so_payment_alloc%rowtype;
  pay        record;
  -- ⓒ2 크레딧부터(8-e · 판정 5)
  v_credit   numeric := 0;
  v_ca       public.so_credit_alloc%rowtype;
  cr         record;
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

  -- 머리(합계는 0 으로 넣고 오더를 돌며 채운다 · CHECK 셋은 0 에서도 맞다)
  insert into public.so_invoice (bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_line2, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country,
                                 issued_on, issued_by, payment_term_id, payment_term_name, due_on, currency_id, currency_code, updated_by)
  values (v_first.bill_to_customer_id, v_first.bill_to_name, v_first.bill_to_line1, v_first.bill_to_line2, v_first.bill_to_city, v_first.bill_to_state_province, v_first.bill_to_postal_code, v_first.bill_to_country,
          v_on, p_staff, v_pt.id, coalesce(v_pt.name, v_first.payment_term_name), case when v_pt.net_days is not null then v_on + v_pt.net_days end, v_first.currency_id, v_first.currency_code, p_staff)
  returning * into v_inv;

  -- 오더마다 — 규칙 · 금액(식 한 곳 · 보낸 수량) · 담긴 오더 줄 · 줄 사본 · 상태 전이
  for v_so in select * from public.so s where s.id = any(p_so_ids) order by s.so_number loop
    if v_so.tax_rule_manual then
      v_rule_id := v_so.tax_rule_id;
    else
      v_pick := public.so_tax_rule_for(v_so.ship_to_country, v_so.ship_to_state_province, v_on, 'sale');
      v_rule_id := (v_pick->>'rule_id')::uuid;
    end if;
    if v_rule_id is null then
      raise exception 'Order % has no tax rule for its ship-to address on % — pick a tax rule on the order — nothing was saved', v_so.so_number, v_on;
    end if;
    v_changed := v_rule_id is distinct from v_so.tax_rule_id;
    v_prev := public.so_tax_preview(v_so.id, v_on, v_rule_id, 'shipped');          -- explicit 규칙 · 활성 sale 아니면 이 함수가 거부한다
    v_rule := v_prev->'rule'->>'rule';  v_rate := (v_prev->'rule'->>'rate_pct')::numeric;
    v_o_lines := (v_prev->'totals'->>'lines_amount')::numeric;  v_o_od := (v_prev->'totals'->>'order_discount_amount')::numeric;
    v_o_chg   := (v_prev->'totals'->>'charges_amount')::numeric;  v_o_tax := (v_prev->'totals'->>'tax')::numeric;
    if v_o_lines + v_o_od + v_o_chg = 0 and not exists (select 1 from public.so_line l where l.so_id = v_so.id and l.qty_shipped > 0) then
      raise exception 'Order % shipped nothing — there is nothing to invoice — nothing was saved', v_so.so_number;
    end if;

    insert into public.so_invoice_order (invoice_id, so_id, so_number, customer_id,
                                         ship_to_company, ship_to_contact, ship_to_phone, ship_to_line1, ship_to_line2, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country,
                                         tax_rule_id, tax_rule, rate_pct, tax_source, draft_rule_changed,
                                         lines_amount, order_discount_pct, order_discount_amount, charges_amount, taxable_amount, tax_amount, total, updated_by)
    values (v_inv.id, v_so.id, v_so.so_number, v_so.customer_id,
            v_so.ship_to_company, v_so.ship_to_contact, v_so.ship_to_phone, v_so.ship_to_line1, v_so.ship_to_line2, v_so.ship_to_city, v_so.ship_to_state_province, v_so.ship_to_postal_code, v_so.ship_to_country,
            v_rule_id, v_rule, v_rate, case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, v_changed,
            v_o_lines, v_so.order_discount_pct, v_o_od, v_o_chg, v_o_lines + v_o_od + v_o_chg, v_o_tax, v_o_lines + v_o_od + v_o_chg + v_o_tax, p_staff)
    returning * into v_io;

    for e in select x from jsonb_array_elements(v_prev->'lines') x loop                     -- 제품 줄(보낸 수량 > 0 만 · 안 나간 줄은 종이에 없다)
      if (e->>'qty')::numeric > 0 then
        v_ln := v_ln + 1;
        insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, unit, pack_factor, qty, list_price, discount_pct, discount_source, unit_price, amount, tax_amount, account_id, account_code, updated_by)
        values (v_inv.id, v_io.id, v_ln, 'product', (e->>'line_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
                (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, e->>'discount_source', (e->>'unit_price')::numeric, (e->>'amount')::numeric, (e->>'tax')::numeric,
                v_so.sale_account_id, v_so.sale_account_code, p_staff);
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
    end loop;

    v_lines_amt := v_lines_amt + v_o_lines;  v_od_amt := v_od_amt + v_o_od;  v_chg_amt := v_chg_amt + v_o_chg;  v_tax := v_tax + v_o_tax;
    if v_changed then v_warn := array_append(v_warn, 'draft_rule_changed:' || v_so.so_number); end if;
    if coalesce(v_prev->'warnings', '[]'::jsonb) ? 'tax_rule_inactive' then v_warn := array_append(v_warn, 'tax_rule_inactive:' || v_so.so_number); end if;

    update public.so set status = 'fulfilled', invoiced_at = now(), closed_at = now(), updated_by = p_staff where id = v_so.id and status = 'shipped';   -- ⓑ2 판정 1: 문지기 짝 shipped→fulfilled · 끝 상태 closed_at 짝(so_closed_at_ck)
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Order % was not invoiced — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'tax_rule', v_rule, 'rate_pct', v_rate,
                                               'tax_source', case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, 'draft_rule_changed', v_changed, 'totals', v_prev->'totals');
  end loop;

  -- 합계를 먼저 굳힌다(so_invoice_remaining 이 total 을 본다) · 잔액 항은 아직 0
  v_total := v_lines_amt + v_od_amt + v_chg_amt + v_tax;
  update public.so_invoice set lines_amount = v_lines_amt, order_discount_amount = v_od_amt, charges_amount = v_chg_amt,
                               taxable_amount = v_lines_amt + v_od_amt + v_chg_amt, tax_amount = v_tax, total = v_total, amount_due = v_total, updated_by = p_staff
  where id = v_inv.id returning * into v_inv;

  -- ⓑ2 ① 담긴 오더를 대상으로 한 선결제(판정 4 · auto_deposit) — 받은 날 순 · 한도는 so_payment_alloc_add(인보이스 남은 금액 · 결제 남은 금액 · 받아 둔 돈)
  v_left := public.so_invoice_remaining(v_inv.id);
  for pay in
    select p.id, p.paid_on, p.method, p.reference,
           public.so_payment_remaining(p.id) as remaining
      from public.so_payment p
     where p.customer_id = v_inv.bill_to_customer_id and p.currency_id = v_inv.currency_id and p.status = 'active' and p.kind = 'payment'
       and exists (select 1 from public.so_payment_order o where o.payment_id = p.id and o.so_id = any(p_so_ids))
     order by p.paid_on, p.created_at, p.id
  loop
    exit when v_left <= 0;
    if pay.remaining <= 0 then continue; end if;
    select b.received into v_recv from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id;
    v_take := least(pay.remaining, v_left, coalesce(v_recv, 0));
    if v_take <= 0 then continue; end if;
    v_a := public.so_payment_alloc_add(pay.id, v_inv.id, v_take, 'auto_deposit', p_staff);
    v_deposit := v_deposit + v_a.amount;  v_left := v_left - v_a.amount;
    v_applied := v_applied || jsonb_build_object('alloc_id', v_a.id, 'payment_id', pay.id, 'source', 'auto_deposit', 'amount', v_a.amount, 'paid_on', pay.paid_on, 'method', pay.method, 'reference', pay.reference);
  end loop;

  -- ⓒ2 ② 크레딧(진 빚 · 8-e 「크레딧부터」 · 판정 5) — issued 크레딧을 발행일 순으로 인보이스만큼만(auto) · so_credit_alloc_add
  if v_left > 0 then
    for cr in
      select c.id, c.credit_number, c.issued_on, c.total - coalesce((select sum(ca.amount) from public.so_credit_alloc ca where ca.credit_id = c.id and ca.voided_at is null), 0) as remaining
        from public.so_credit c
       where c.customer_id = v_inv.bill_to_customer_id and c.currency_id = v_inv.currency_id and c.status = 'issued'
       order by c.issued_on, c.created_at, c.id
    loop
      exit when v_left <= 0;
      if cr.remaining <= 0 then continue; end if;
      v_take := least(cr.remaining, v_left);
      v_ca := public.so_credit_alloc_add(cr.id, v_inv.id, v_take, 'auto', p_staff);
      v_credit := v_credit + v_ca.amount;  v_left := v_left - v_ca.amount;
      v_applied := v_applied || jsonb_build_object('alloc_id', v_ca.id, 'credit_id', cr.id, 'credit_number', cr.credit_number, 'source', 'auto_credit', 'amount', v_ca.amount, 'issued_on', cr.issued_on);
    end loop;
  end if;

  -- ⓑ2 ③ 손님의 받아 둔 돈(판정 5 · auto_balance) — 다른 오더 예약분 제외(received − reserved_deposit · so_payment_is_reserved) · 인보이스만큼만 · 받은 날 순 · ⓒ2: 크레딧은 위 ② 에서 썼으니 여기는 받아 둔 돈만(available 이 아니라 received − reserved)
  if v_left > 0 then
    select greatest(b.received - b.reserved_deposit, 0) into v_avail from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id;
    v_avail := coalesce(v_avail, 0);
    for pay in
      select p.id, p.paid_on, p.method, p.reference,
             public.so_payment_remaining(p.id) as remaining
        from public.so_payment p
       where p.customer_id = v_inv.bill_to_customer_id and p.currency_id = v_inv.currency_id and p.status = 'active' and p.kind = 'payment'
         and not public.so_payment_is_reserved(p.id)
       order by p.paid_on, p.created_at, p.id
    loop
      exit when v_left <= 0 or v_avail <= 0;
      if pay.remaining <= 0 then continue; end if;
      v_take := least(pay.remaining, v_left, v_avail);
      if v_take <= 0 then continue; end if;
      v_a := public.so_payment_alloc_add(pay.id, v_inv.id, v_take, 'auto_balance', p_staff);
      v_balance := v_balance + v_a.amount;  v_left := v_left - v_a.amount;  v_avail := v_avail - v_a.amount;
      v_applied := v_applied || jsonb_build_object('alloc_id', v_a.id, 'payment_id', pay.id, 'source', 'auto_balance', 'amount', v_a.amount, 'paid_on', pay.paid_on, 'method', pay.method, 'reference', pay.reference);
    end loop;
  end if;

  -- 종이에 찍히는 값을 굳힌다 — 받은 금액(deposit_applied) · 이전 잔액(balance_forward = −(크레딧 ② + 받아 둔 돈 ③) · 0 이하 · 봤는데 없으면 0 · 한 줄 8-c) · credit_applied(② 몫 · 회계 근거 · ⬜7) · 보내실 금액(amount_due · CHECK so_invoice_due_ck)
  update public.so_invoice set deposit_applied = v_deposit, credit_applied = v_credit, balance_forward = -(v_credit + v_balance), amount_due = v_total - v_deposit - v_credit - v_balance, updated_by = p_staff
  where id = v_inv.id returning * into v_inv;

  return jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status, 'issued_on', v_on, 'due_on', v_inv.due_on,
                            'bill_to_customer_id', v_inv.bill_to_customer_id, 'bill_to_name', v_inv.bill_to_name, 'payment_term_name', v_inv.payment_term_name, 'currency_code', v_inv.currency_code,
                            'orders', v_orders, 'lines', v_ln,
                            'totals', jsonb_build_object('lines_amount', v_inv.lines_amount, 'order_discount_amount', v_inv.order_discount_amount, 'charges_amount', v_inv.charges_amount,
                                                         'taxable_amount', v_inv.taxable_amount, 'tax_amount', v_inv.tax_amount, 'total', v_inv.total,
                                                         'deposit_applied', v_inv.deposit_applied, 'credit_applied', v_inv.credit_applied, 'balance_forward', v_inv.balance_forward, 'amount_due', v_inv.amount_due,
                                                         'remaining', public.so_invoice_remaining(v_inv.id)),
                            'applied', v_applied,
                            'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id),
                            'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ so_proforma 재발행 — 마지막 정의 20260925001733_so_payment_b2.sql:479~565 · 바이트 그대로 · 바뀐 줄 1(인라인 식 → so_payment_remaining) · create → create or replace ═══
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
    'totals', jsonb_build_object('lines_amount', v_lines_amt, 'order_discount_amount', v_od_amt, 'charges_amount', v_chg_amt, 'taxable_amount', v_lines_amt + v_od_amt + v_chg_amt,
                                 'tax', case when v_tax_missing then null else v_tax end,
                                 'total', case when v_tax_missing then null else v_lines_amt + v_od_amt + v_chg_amt + v_tax end,
                                 'received', v_received,
                                 'balance_due', case when v_tax_missing then null else v_lines_amt + v_od_amt + v_chg_amt + v_tax - v_received end),
    'deposits', v_deposits,
    'customer_balance', v_bal,
    'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_proforma(uuid[]) is
  '⭐ 견적서(pro forma · 판정 3 · ⓑ2) — 읽기만(stable · 아무것도 쓰지 않는다 · 저장하는 문서가 아니다 · 인보이스 번호 없음) · 열린 오더 묶음(끝 상태 아님 · 살아 있는 인보이스 없음 · 같은 청구처 · 같은 통화) → 오더마다 so_tax_preview(오늘 · 오더 규칙 · basis ordered — 발행 전 오더의 qty_removed 는 늘 0 · 0-11) · totals(줄 · 할인 · 운임 · 예상 세금(그날 기준) · 합계 · received = 이 오더들을 대상으로 한 활성 선결제의 남은 금액 Σ · balance_due = total − received(음수면 남는 돈이 잔액이 된다)) · deposits 목록 · customer_balance · 규칙 없는 오더는 세금 null + 경고 · 화면은 「PRO FORMA — 인보이스가 아닙니다」 를 찍는다 · 권한 로그인(so_detail 과 같은 급)';
revoke all on function public.so_proforma(uuid[]) from public, anon;
grant execute on function public.so_proforma(uuid[]) to authenticated;

-- ═══ so_pos_complete 재발행 — 마지막 정의 20260925142307_so_pos_a2_flow.sql:702~800 · 바이트 그대로 · 바뀐 줄 2(인라인 식 → so_payment_remaining) · create → create or replace ═══
create or replace function public.so_pos_complete(p_so_id uuid, p_picks jsonb, p_staff uuid, p_commit boolean) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so       public.so%rowtype;
  v_plan     jsonb;
  v_picks    jsonb;
  v_prev     jsonb;
  v_total    numeric;
  v_left     numeric;
  v_dep      numeric := 0;  v_cred numeric := 0;  v_bal numeric := 0;
  v_recv     numeric;  v_owed numeric;  v_res_other numeric;  v_avail numeric;
  v_cust     uuid;
  v_take     numeric;
  v_dep_map  jsonb := '{}'::jsonb;                              -- payment_id → ① 에서 쓴 금액(③ 의 예약 몫 계산)
  pay        record;
  v_est      jsonb;
  v_ship     jsonb;  v_iss jsonb;
  v_inv_id   uuid;
  v_warn     text[] := '{}';
  v_tw       text[];
begin
  if p_staff is null then raise exception 'so_pos_complete needs the acting staff id — nothing was saved'; end if;
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.channel not in ('pos', 'counter') then raise exception 'Order % is a % order — finish it with so_finalize — nothing was saved', v_so.so_number, v_so.channel; end if;
  if v_so.status <> 'confirmed' then raise exception 'Order % is % — only a confirmed % order can be finished — nothing was saved', v_so.so_number, v_so.status, v_so.channel; end if;

  -- 칸 계획(판정 1·2·4) — 준 픽이 없으면 계획 그대로 · counter 가 준 픽은 so_ship 이 검사한다(줄·칸·수량)
  v_plan := public.so_pick_plan(p_so_id);
  v_picks := coalesce(nullif(p_picks, 'null'::jsonb), v_plan->'picks');
  if v_picks is null or jsonb_typeof(v_picks) <> 'array' or jsonb_array_length(v_picks) = 0 then
    raise exception 'Order % has nothing to ship — nothing was saved', v_so.so_number;
  end if;
  select array_agg(t.w) into v_tw from jsonb_array_elements_text(coalesce(v_plan->'warnings', '[]'::jsonb)) as t(w);
  v_warn := v_warn || coalesce(v_tw, '{}');

  -- 미리 보기 금액(판정 5 · 누르기 전에 받은 금액·미수) — 발행 ①②③ 과 같은 순서를 읽기로
  v_prev := public.so_tax_preview(p_so_id, public.ims_today(), null, 'ordered');
  if v_prev->'totals'->>'tax' is null then raise exception 'Order % has no tax rule for its ship-to address — pick a tax rule on the order — nothing was saved', v_so.so_number; end if;
  v_total := (v_prev->'totals'->>'total')::numeric;
  v_cust := coalesce(v_so.bill_to_customer_id, v_so.customer_id);
  select b.received, b.owed_credit into v_recv, v_owed from public.so_customer_balance(v_cust) b where b.currency_id = v_so.currency_id;
  v_recv := coalesce(v_recv, 0);  v_owed := coalesce(v_owed, 0);
  v_left := v_total;
  for pay in
    select p.id, public.so_payment_remaining(p.id) as remaining
      from public.so_payment p
     where p.customer_id = v_cust and p.currency_id = v_so.currency_id and p.status = 'active' and p.kind = 'payment'
       and exists (select 1 from public.so_payment_order o where o.payment_id = p.id and o.so_id = p_so_id)
     order by p.paid_on, p.created_at, p.id
  loop
    exit when v_left <= 0;
    if pay.remaining <= 0 then continue; end if;
    v_take := least(pay.remaining, v_left, v_recv);
    if v_take <= 0 then continue; end if;
    v_dep := v_dep + v_take;  v_left := v_left - v_take;  v_recv := v_recv - v_take;
    v_dep_map := jsonb_set(v_dep_map, array[pay.id::text], to_jsonb(v_take));
  end loop;
  if v_left > 0 then
    v_cred := least(v_left, greatest(v_owed, 0));  v_left := v_left - v_cred;
  end if;
  if v_left > 0 then
    -- 발행 뒤 이 오더는 fulfilled 라 이 오더만 대상인 선결제의 예약은 풀린다 — 다른 열린 오더(살아 있는 인보이스 없음)를 대상으로 한 선결제의 남은 몫만 예약으로 남는다
    select coalesce(sum(public.so_payment_remaining(p.id) - coalesce((v_dep_map->>(p.id::text))::numeric, 0)), 0)
      into v_res_other
      from public.so_payment p
     where p.customer_id = v_cust and p.currency_id = v_so.currency_id and p.status = 'active' and p.kind = 'payment'
       and exists (select 1 from public.so_payment_order o join public.so s on s.id = o.so_id
                    where o.payment_id = p.id and s.id <> p_so_id and s.status not in ('fulfilled', 'cancelled')
                      and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id));
    v_avail := greatest(v_recv - v_res_other, 0);
    v_bal := least(v_left, v_avail);  v_left := v_left - v_bal;
  end if;
  v_est := jsonb_build_object('total', v_total, 'deposit', v_dep, 'credit', v_cred, 'balance', v_bal, 'amount_due', v_total - v_dep - v_cred - v_bal, 'remaining', v_left,
                              'received_before', (select b.received from public.so_customer_balance(v_cust) b where b.currency_id = v_so.currency_id));

  if not p_commit then
    return jsonb_build_object('committed', false, 'so_id', v_so.id, 'so_number', v_so.so_number, 'channel', v_so.channel, 'picks', v_picks, 'plan', v_plan->'lines',
                              'short_ea_total', v_plan->'short_ea_total', 'estimate', v_est, 'tax', v_prev->'totals', 'warnings', to_jsonb(v_warn));
  end if;

  -- 실행 — 출고(pos·counter 는 confirmed→shipped · 목표 아래 픽은 so_ship 이 거부) → 발행 한 장(발행일 오늘 · 발행 순간 fulfilled · 자동 붙이기 ①②③)
  v_ship := public.so_ship(p_so_id, v_picks, p_staff, null);
  select array_agg(t.w) into v_tw from jsonb_array_elements_text(coalesce(v_ship->'warnings', '[]'::jsonb)) as t(w);
  v_warn := v_warn || coalesce(v_tw, '{}');
  v_iss := public.so_invoice_issue(array[p_so_id], p_staff, null);
  v_inv_id := (v_iss->>'invoice_id')::uuid;
  select array_agg(t.w) into v_tw from jsonb_array_elements_text(coalesce(v_iss->'warnings', '[]'::jsonb)) as t(w);
  v_warn := v_warn || coalesce(v_tw, '{}');

  return jsonb_build_object('committed', true, 'so_id', v_so.id, 'so_number', v_so.so_number, 'channel', v_so.channel, 'status', 'fulfilled',
                            'invoice_id', v_inv_id, 'invoice_number', v_iss->>'invoice_number', 'issued_on', v_iss->'issued_on', 'due_on', v_iss->'due_on',
                            'totals', v_iss->'totals', 'received', jsonb_build_object('deposit_applied', v_iss->'totals'->'deposit_applied', 'credit_applied', v_iss->'totals'->'credit_applied', 'balance_forward', v_iss->'totals'->'balance_forward'),
                            'amount_due', v_iss->'totals'->'amount_due', 'remaining', public.so_invoice_remaining(v_inv_id),
                            'estimate', v_est, 'ship', v_ship, 'short_ea_total', v_plan->'short_ea_total', 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ so_pos_open_list 재발행 — 마지막 정의 20260925144959_so_pos_a3_lists.sql:144~181 · 바이트 그대로 · 바뀐 줄 1(인라인 식 → so_payment_remaining) · create → create or replace ═══
create or replace function public.so_pos_open_list(p_location_id uuid default null) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_orders jsonb;
  v_n      int;
  v_stale  int;
  v_wh     text;
begin
  if p_location_id is not null then
    select w.name into v_wh from public.ref_warehouse w where w.id = p_location_id;
    if v_wh is null then raise exception 'Warehouse not found'; end if;
  end if;
  with o as (
    select s.id, s.so_number, s.customer_id, c.name as customer_name, s.location_id, s.location_name, s.confirmed_at, s.confirmed_by, cb.name as confirmed_by_name,
           (s.confirmed_at at time zone 'America/Toronto')::date as confirmed_on,
           ((s.confirmed_at at time zone 'America/Toronto')::date < public.ims_today()) as stale,
           (select count(*) from public.so_line l where l.so_id = s.id) as lines,
           (select coalesce(sum(l.qty_ordered - l.qty_removed), 0) from public.so_line l where l.so_id = s.id) as qty,
           (public.so_tax_preview(s.id, null, null, 'ordered')->'totals'->>'total')::numeric as amount,
           (select coalesce(sum(public.so_payment_remaining(p.id)), 0)
              from public.so_payment p
             where p.status = 'active' and p.kind = 'payment' and exists (select 1 from public.so_payment_order po where po.payment_id = p.id and po.so_id = s.id)) as received
    from public.so s
    join public.customer c on c.id = s.customer_id
    left join public.ims_staff cb on cb.id = s.confirmed_by
    where s.channel = 'pos' and s.status = 'confirmed' and (p_location_id is null or s.location_id = p_location_id)
  )
  select coalesce(jsonb_agg(to_jsonb(o) order by o.confirmed_at, o.so_number), '[]'::jsonb), count(*), count(*) filter (where o.stale)
    into v_orders, v_n, v_stale
  from o;
  return jsonb_build_object('warehouse_id', p_location_id, 'warehouse', v_wh, 'count', v_n, 'stale_count', v_stale, 'orders', v_orders);
end;
$$;
comment on function public.so_pos_open_list(uuid) is '⭐ 끝나지 않은 POS 오더(§20 판정 15·16 · 잠시 두기 · 매니저 목록) — 읽기(stable · invoker) · 그 창고(null 이면 전부)의 channel pos · status confirmed · 줄 수 · 수량(뺀 몫 제외) · 금액(so_tax_preview ordered) · received(이 오더를 대상으로 한 활성 선결제의 남은 금액) · stale = 확정일(토론토) < ims_today()(그날 안에 Finish 되지 않았다 · 자동으로 풀지 않는다) · 모든 계산대에서 같은 목록(이어받기) · Finish·취소·다시 열기 뒤 빠진다 · jsonb 하나';
revoke all on function public.so_pos_open_list(uuid) from public, anon;
grant execute on function public.so_pos_open_list(uuid) to authenticated;

-- ═══ so_payment_alloc_add 재발행 — 마지막 정의 20260924234250_so_payment_b1.sql:339~383 · 바이트 그대로 · 바뀐 줄 1(인라인 식 → so_payment_remaining) · create → create or replace ═══
create or replace function public.so_payment_alloc_add(p_payment_id uuid, p_invoice_id uuid, p_amount numeric, p_source text, p_staff uuid) returns public.so_payment_alloc
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_p       public.so_payment%rowtype;
  v_i       public.so_invoice%rowtype;
  v_inv_rem numeric;
  v_pay_rem numeric;
  v_recv    numeric;
  v_row     public.so_payment_alloc%rowtype;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Allocation amount must be positive — nothing was saved'; end if;
  if p_amount <> round(p_amount, 2) then raise exception 'Amounts have at most two decimals (got %) — nothing was saved', p_amount; end if;
  if p_source not in ('manual', 'auto_deposit', 'auto_balance') then raise exception 'Unknown allocation source % — nothing was saved', p_source; end if;
  select * into v_p from public.so_payment p where p.id = p_payment_id for update;
  if not found then raise exception 'Payment not found — nothing was saved'; end if;
  if v_p.status <> 'active' then raise exception 'Payment is voided — nothing was saved'; end if;
  if v_p.kind <> 'payment' then raise exception 'A refund cannot be applied to an invoice — nothing was saved'; end if;
  select * into v_i from public.so_invoice i where i.id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found — nothing was saved'; end if;
  if v_i.status <> 'issued' then raise exception 'Invoice % is % — nothing was saved', v_i.invoice_number, v_i.status; end if;
  if v_i.bill_to_customer_id <> v_p.customer_id then raise exception 'Invoice % bills a different customer than this payment — nothing was saved', v_i.invoice_number; end if;
  if v_i.currency_id <> v_p.currency_id then
    raise exception 'Invoice % is in % but the payment is in % — same currency only (no exchange) — nothing was saved', v_i.invoice_number, v_i.currency_code, v_p.currency_code;
  end if;
  if exists (select 1 from public.so_payment_alloc a where a.payment_id = v_p.id and a.active_invoice_id = v_i.id) then
    raise exception 'This payment is already applied to invoice % — detach that first — nothing was saved', v_i.invoice_number;
  end if;
  v_inv_rem := public.so_invoice_remaining(v_i.id);
  if p_amount > v_inv_rem then raise exception 'Invoice % has only % left to pay (asked %) — nothing was saved', v_i.invoice_number, v_inv_rem, p_amount; end if;
  v_pay_rem := public.so_payment_remaining(v_p.id);
  if p_amount > v_pay_rem then raise exception 'Payment has only % left to apply (asked %) — nothing was saved', v_pay_rem, p_amount; end if;
  select b.received into v_recv from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id;
  if p_amount > coalesce(v_recv, 0) then
    raise exception 'Customer has only % % on account after refunds (asked %) — nothing was saved', coalesce(v_recv, 0), v_p.currency_code, p_amount;
  end if;
  insert into public.so_payment_alloc (payment_id, invoice_id, amount, source, created_by, updated_by)
  values (v_p.id, v_i.id, p_amount, p_source, p_staff, p_staff)
  returning * into v_row;
  return v_row;
end;
$$;
comment on function public.so_payment_alloc_add(uuid, uuid, numeric, text, uuid) is '⭐ SO 붙이기 한 줄(속 함수 · ⓑ1 · 0-6) — 결제 활성·kind payment · 인보이스 issued · 같은 청구처 · 같은 통화 · 활성 짝 없음 · 한도 셋 = 인보이스 남은 금액 · 결제 남은 금액 · 그 통화의 받아 둔 돈(received · 환불이 집계라 이것이 바닥) 아니면 거부 · source manual(창구) | auto_deposit | auto_balance(ⓑ2 발행 · auto_balance 는 부르는 쪽이 available 이하로 정한다) · 권한은 부르는 창구가 봤다';
revoke all on function public.so_payment_alloc_add(uuid, uuid, numeric, text, uuid) from public, anon, authenticated;

-- ═══ so_payment_attach 재발행 — 마지막 정의 20260924234250_so_payment_b1.sql:494~526 · 바이트 그대로 · 바뀐 줄 1(인라인 식 → so_payment_remaining) · create → create or replace ═══
create or replace function public.so_payment_attach(p_payment_id uuid, p_allocs jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_p      public.so_payment%rowtype;
  v_a      public.so_payment_alloc%rowtype;
  v_allocs jsonb := '[]'::jsonb;
  v_sum    numeric := 0;
  x        jsonb;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  select * into v_p from public.so_payment p where p.id = p_payment_id;
  if not found then raise exception 'Payment not found — nothing was saved'; end if;
  perform 1 from public.customer c where c.id = v_p.customer_id for update;   -- 손님 행 잠금
  if jsonb_typeof(p_allocs) is distinct from 'array' or jsonb_array_length(p_allocs) = 0 then raise exception 'Nothing to apply — pass [{invoice_id, amount}] — nothing was saved'; end if;
  for x in select t from jsonb_array_elements(p_allocs) t loop
    v_a := public.so_payment_alloc_add(v_p.id, nullif(x->>'invoice_id', '')::uuid, (x->>'amount')::numeric, 'manual', v_staff);
    v_sum := v_sum + v_a.amount;
    v_allocs := v_allocs || jsonb_build_object('alloc_id', v_a.id, 'invoice_id', v_a.invoice_id,
                                               'invoice_number', (select i.invoice_number from public.so_invoice i where i.id = v_a.invoice_id),
                                               'amount', v_a.amount, 'invoice_remaining', public.so_invoice_remaining(v_a.invoice_id));
  end loop;
  return jsonb_build_object('payment_id', v_p.id, 'applied', v_sum, 'allocations', v_allocs,
                            'payment_remaining', public.so_payment_remaining(v_p.id),
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id));
end;
$$;
comment on function public.so_payment_attach(uuid, jsonb) is '⭐ 붙이기(8-d · 판정 6 · ⓑ1) — definer · 첫 줄 ims_require_write(sales) · [{invoice_id, amount}] 를 so_payment_alloc_add(manual · 한도 셋) 로 · 하나라도 막히면 전체 거부 · 반환 applied · allocations · payment_remaining · balance';
revoke all on function public.so_payment_attach(uuid, jsonb) from public, anon;
grant execute on function public.so_payment_attach(uuid, jsonb) to authenticated;

-- ═══ so_payment_detach 재발행 — 마지막 정의 20260924234250_so_payment_b1.sql:529~561 · 바이트 그대로 · 바뀐 줄 1(인라인 식 → so_payment_remaining) · create → create or replace ═══
create or replace function public.so_payment_detach(p_alloc_id uuid, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_a     public.so_payment_alloc%rowtype;
  v_p     public.so_payment%rowtype;
  v_note  text;
  v_n     int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄(판정 6)
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  if v_note is null then raise exception 'Detaching needs a reason (p_note) — nothing was saved'; end if;
  select * into v_a from public.so_payment_alloc a where a.id = p_alloc_id for update;
  if not found then raise exception 'Allocation not found — nothing was saved'; end if;
  if v_a.voided_at is not null then raise exception 'This allocation was already detached — nothing was saved'; end if;
  select * into v_p from public.so_payment p where p.id = v_a.payment_id;
  perform 1 from public.customer c where c.id = v_p.customer_id for update;   -- 손님 행 잠금
  update public.so_payment_alloc set voided_at = now(), voided_by = v_staff, void_note = v_note, updated_by = v_staff where id = v_a.id and voided_at is null;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Allocation was not detached — it may have been changed by someone else just now — nothing was saved'; end if;
  return jsonb_build_object('alloc_id', v_a.id, 'payment_id', v_a.payment_id, 'invoice_id', v_a.invoice_id, 'amount', v_a.amount, 'source', v_a.source, 'note', v_note,
                            'invoice_remaining', public.so_invoice_remaining(v_a.invoice_id),
                            'payment_remaining', public.so_payment_remaining(v_p.id),
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id));
end;
$$;
comment on function public.so_payment_detach(uuid, text) is '⭐ 떼기(판정 6 manager · ⓑ1) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · 사유 필수 · 행은 지우지 않고 void(voided_at/by/note · active_invoice_id 가 비어 다시 붙일 수 있다) · 돈은 결제의 남은 금액 → 받아 둔 돈으로 돌아간다(반환 balance 로 보인다)';
revoke all on function public.so_payment_detach(uuid, text) from public, anon;
grant execute on function public.so_payment_detach(uuid, text) to authenticated;
