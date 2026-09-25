-- ═══ SO 결제 ⓑ2 — 발행 연결(선결제·잔액 자동 붙이기 · deposit_applied · balance_forward) · 오더 끝 fulfilled · 취소 가드·풀기 · so_detail · 견적서 (2026-09-24 · 지시서 ~/asung/prompts/so-payment-1.md · 판정 회신 Caleb 2026-09-24 집 · ⓑ1 20260924234250 위에) ═══
-- 판정(Caleb 2026-09-24)
--   판정 1  오더의 끝 = 인보이스 + 출하 · 돈은 조건이 아니다 ⇒ 발행 순간 shipped → fulfilled 곧장(⬜7 안 C · closed_at 짝) · invoiced 값은 so_status_ck 에서 뺀다(쓰는 이 없음 · 시각 칸 invoiced_at 은 남는다)
--   판정 3  선결제 때 손님에게 주는 종이 = 견적서(pro forma) · 저장하지 않는다 · 읽기 함수 so_proforma(0-11: 발행 전 오더의 qty_removed 는 늘 0 이라 basis ordered 가 정확)
--   판정 4  결제에 적어 둔 대상 오더가 발행되면 그 인보이스에 자동으로 붙는다(auto_deposit) · 인보이스가 선결제보다 적으면 남는 돈은 잔액(대상이 전부 발행되면 저절로 풀린다 · 0-7)
--   판정 5  발행 때 손님 잔액을 자동으로 붙인다(auto_balance · 크레딧 → 받아 둔 돈 순서 · ⓒ 전이라 받아 둔 돈만 · 다른 오더 예약분 제외 = available) · 인보이스만큼만 · balance_forward 는 이제 0 이하(봤는데 없으면 0 · null 은 ⓑ 전 발행분)
--   판정 7  취소 때 alloc 에 source manual 이 하나라도 있으면 거부 · auto_deposit·auto_balance 는 취소와 함께 void(흔적 · void_note 에 인보이스 번호) · 오더 fulfilled → shipped(invoiced_at · closed_at null)
-- 이견 0-4  amount_due = total − deposit_applied + balance_forward(선결제 항이 없던 CHECK 교체) · 0-5 남은 금액은 so_invoice_remaining 하나 · 0-10 so_finalize 는 재발행 없음(issue 반환의 totals·warnings 를 그대로 싣는다 · applied 목록은 안 실린다 — 필요하면 한 줄 재발행 · Caleb 판정)
-- 훑기(마지막 정의 · 2026-09-24): 상태 값 'invoiced' 를 쓰는 코드 다섯 — so_status_ck(20260923133042:128) · so_status_guard(20260924200029:269) · so_invoice_issue(:684) · so_invoice_cancel(:739) · so_detail(20260924202425:463) — 전부 여기서 고친다 · 뭉치(so_family_*)·백오더·스윕·so_available 은 cancelled 분기뿐(무접촉) · 화면·js·gs 0
-- 재발행: so_status_guard · so_invoice_issue · so_invoice_cancel · so_detail · so_customer_balance(예약 판정을 so_payment_is_reserved 로 · 식은 그대로) · 새 함수 so_payment_is_reserved · so_proforma
-- 검증 ~/asung/prompts/so-payment-1b-verify.sql · 시퀀스 둘은 rollback 밖 setval

-- ═══ ① so_invoice — deposit_applied 칸 · CHECK 교체(0-4) · balance_forward 0 이하 ═══
alter table public.so_invoice add column if not exists deposit_applied numeric not null default 0;
alter table public.so_invoice drop constraint if exists so_invoice_due_ck;
alter table public.so_invoice add constraint so_invoice_due_ck      check (amount_due = total - deposit_applied + coalesce(balance_forward, 0));
alter table public.so_invoice add constraint so_invoice_deposit_ck  check (deposit_applied >= 0);
alter table public.so_invoice add constraint so_invoice_bf_ck       check (balance_forward is null or balance_forward <= 0);
comment on column public.so_invoice.deposit_applied is '발행 순간 이 인보이스의 오더를 대상으로 한 선결제(so_payment_order)에서 자동으로 붙인 금액(auto_deposit · 판정 4 · ⓑ2) · 종이의 「받은 금액」 · 0 = 대상 선결제가 없었다';
comment on column public.so_invoice.balance_forward is '발행 시점 이월 잔액(8-c 「그 종이에 찍혀 나간 값」) — ⓑ2 부터 = −(발행 순간 손님의 일반 잔액에서 자동으로 붙인 금액 · auto_balance · 판정 5) · 0 이하(CHECK so_invoice_bf_ck) · 0 = 봤는데 없었다 · null = ⓑ 전 발행분(모르면 비운다 · Caleb) · 종이의 「이전 잔액 −x」';
comment on column public.so_invoice.amount_due      is '보내실 금액 = total − deposit_applied + coalesce(balance_forward, 0) · CHECK so_invoice_due_ck(ⓑ2 교체 · 0-4) · 종이에 찍힌 값 · ⚠️ 남은 금액은 이것이 아니라 so_invoice_remaining(total − Σ활성 alloc · 0-5)';

-- ═══ ② so.status — invoiced 를 뺀다(⬜7 안 C · 판정 1) · 문지기 짝 shipped→fulfilled · fulfilled→shipped ═══
alter table public.so drop constraint if exists so_status_ck;
alter table public.so add constraint so_status_ck check (status in ('draft','confirmed','at_wms','picking','packed','shipped','fulfilled','cancelled'));
comment on column public.so.status is '⭐ CHECK so_status_ck 여덟 — draft · confirmed · at_wms · picking · packed · shipped · fulfilled · cancelled(6-a · ⓑ2 2026-09-24: invoiced 를 뺐다 — 판정 1 「오더의 끝 = 인보이스 + 출하」라 발행 순간 shipped → fulfilled 곧장 · 시각 칸 invoiced_at 은 남는다) · 기본 draft · 끝 상태는 fulfilled·cancelled 둘(closed 없음 · closed_at 짝) · at_wms 가 소유권의 선(6-e) · shipped 가 원장에서 빠지는 유일한 자리(6-d · 7-b) · 전이는 so_status_guard';

create or replace function public.so_status_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare
  v_ok boolean := false;
begin
  if tg_op = 'INSERT' then
    if new.status is distinct from 'draft' then
      raise exception 'A new order must start as draft (got %) — nothing was saved', new.status;
    end if;
    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;                                   -- status 그대로 — 머리 고치기 · 줄 수 반영 등은 지나간다
  end if;

  -- 허락 짝 목록 — ② 확정·할당(⬜3) 넷 + ③a 출고(2026-09-24 · ⬜5): packed→shipped(so_ship 의 CAS 플립 · warehouse 길)
  --   ⓑ2 2026-09-24: shipped→fulfilled(so_invoice_issue · 판정 1 발행이 곧 끝) · fulfilled→shipped(so_invoice_cancel · 8-h 하향) — ⓐ1 의 shipped→invoiced · invoiced→shipped 를 대신한다
  --   ④ POS·counter(confirmed→shipped) · ⑤ Release to WMS · WMS 사건(at_wms · picking · packed · 내려가는 짝 · 6-g′ ⬜) 이 여기에 더한다
  v_ok := (old.status, new.status) in (('draft','confirmed'), ('confirmed','draft'), ('confirmed','cancelled'), ('draft','cancelled'), ('packed','shipped'),
                                        ('shipped','fulfilled'), ('fulfilled','shipped'));

  if not v_ok then
    raise exception 'Order % cannot move from % to % this way — use the order actions — nothing was saved',
      old.so_number, old.status, new.status;
  end if;
  return new;
end;
$$;
comment on function public.so_status_guard() is
  '⭐ SO 상태 문지기(6-g′ · 12-b 판정 6 · ②a ⬜3 · ③a ⬜5 · ⓑ2) — insert 는 draft 만 · status 가 바뀌는 update 는 허락 짝에 없으면 거부(소유자·definer 창구도 지난다) · 같은 상태의 update 는 통과. 짝 일곱: draft→confirmed · confirmed→draft · confirmed→cancelled · draft→cancelled · packed→shipped(so_ship) · shipped→fulfilled(so_invoice_issue · 판정 1) · fulfilled→shipped(so_invoice_cancel · 8-h 하향). ④ POS·counter(confirmed→shipped) · ⑤ Release·WMS 사건이 여기에 더한다';

-- ═══ ③ so_payment_is_reserved — 예약된 선결제 판정 한 곳(0-7) · so_customer_balance 와 so_invoice_issue 가 같은 함수를 본다 ═══
create function public.so_payment_is_reserved(p_payment_id uuid) returns boolean
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select exists (select 1 from public.so_payment_order o join public.so s on s.id = o.so_id
                  where o.payment_id = p_payment_id and s.status not in ('fulfilled', 'cancelled')
                    and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id));
$$;
comment on function public.so_payment_is_reserved(uuid) is '예약된 선결제인가(0-7 · ⓑ2) — 대상 오더(so_payment_order) 중 「끝 상태 아님 ∧ 살아 있는 인보이스 없음」이 하나라도 있으면 true · 그 결제의 남은 금액은 일반 잔액(available)에서 빠지고 발행 때 auto_balance 로 쓰이지 않는다 · 대상이 전부 발행·취소되면 false(저절로 풀림) · so_customer_balance · so_invoice_issue 가 같은 함수를 본다';
revoke all on function public.so_payment_is_reserved(uuid) from public, anon;
grant execute on function public.so_payment_is_reserved(uuid) to authenticated;

-- ═══ ④ so_customer_balance 재발행 — 예약 판정을 so_payment_is_reserved 로(식은 그대로 · 마지막 정의 20260924234250) ═══
create or replace function public.so_customer_balance(p_customer_id uuid)
  returns table (currency_id uuid, currency_code text, received numeric, reserved_deposit numeric, owed_credit numeric, available numeric, open_invoices int, open_invoices_due numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with cur as (
    select p.currency_id from public.so_payment p where p.customer_id = p_customer_id
    union
    select i.currency_id from public.so_invoice i where i.bill_to_customer_id = p_customer_id
  ),
  pay as (
    select p.id, p.currency_id, p.kind, p.amount,
           p.amount - coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null), 0) as remaining,
           public.so_payment_is_reserved(p.id) as reserved
      from public.so_payment p
     where p.customer_id = p_customer_id and p.status = 'active'
  ),
  inv as (
    select i.currency_id, count(*) as n, sum(public.so_invoice_remaining(i.id)) as due
      from public.so_invoice i
     where i.bill_to_customer_id = p_customer_id and i.status = 'issued' and public.so_invoice_remaining(i.id) > 0
     group by i.currency_id
  ),
  agg as (
    select c.currency_id,
           coalesce(sum(case when y.kind = 'payment' then y.remaining end), 0) - coalesce(sum(case when y.kind = 'refund' then y.amount end), 0) as received,
           coalesce(sum(case when y.kind = 'payment' and y.reserved then y.remaining end), 0) as reserved_deposit
      from cur c left join pay y on y.currency_id = c.currency_id
     group by c.currency_id
  )
  select a.currency_id, rc.code, a.received, a.reserved_deposit, 0::numeric as owed_credit,
         greatest(a.received + 0 - a.reserved_deposit, 0) as available,
         coalesce(v.n, 0)::int as open_invoices, coalesce(v.due, 0) as open_invoices_due
    from agg a
    join public.ref_currency rc on rc.id = a.currency_id
    left join inv v on v.currency_id = a.currency_id
   order by rc.code;
$$;

-- ═══ ⑤ so_invoice_issue 재발행 — 마지막 정의 20260924200029:551~708 · 같은 시그니처(replace · revoke 그대로) · 바뀐 곳: 합계를 먼저 굳힘 → ① auto_deposit ② auto_balance → deposit_applied·balance_forward·amount_due → shipped→fulfilled(closed_at) · 반환 applied ═══
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
           p.amount - coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null), 0) as remaining
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

  -- ⓑ2 ② 손님의 일반 잔액(판정 5 · auto_balance) — 크레딧 → 받아 둔 돈(ⓒ 전이라 받아 둔 돈만) · 다른 오더 예약분 제외(available · so_payment_is_reserved) · 인보이스만큼만 · 받은 날 순
  if v_left > 0 then
    select b.available into v_avail from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id;
    v_avail := coalesce(v_avail, 0);
    for pay in
      select p.id, p.paid_on, p.method, p.reference,
             p.amount - coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null), 0) as remaining
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

  -- 종이에 찍히는 값을 굳힌다 — 받은 금액(deposit_applied) · 이전 잔액(balance_forward ≤ 0 · 봤는데 없으면 0) · 보내실 금액(amount_due · CHECK so_invoice_due_ck)
  update public.so_invoice set deposit_applied = v_deposit, balance_forward = -v_balance, amount_due = v_total - v_deposit - v_balance, updated_by = p_staff
  where id = v_inv.id returning * into v_inv;

  return jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status, 'issued_on', v_on, 'due_on', v_inv.due_on,
                            'bill_to_customer_id', v_inv.bill_to_customer_id, 'bill_to_name', v_inv.bill_to_name, 'payment_term_name', v_inv.payment_term_name, 'currency_code', v_inv.currency_code,
                            'orders', v_orders, 'lines', v_ln,
                            'totals', jsonb_build_object('lines_amount', v_inv.lines_amount, 'order_discount_amount', v_inv.order_discount_amount, 'charges_amount', v_inv.charges_amount,
                                                         'taxable_amount', v_inv.taxable_amount, 'tax_amount', v_inv.tax_amount, 'total', v_inv.total,
                                                         'deposit_applied', v_inv.deposit_applied, 'balance_forward', v_inv.balance_forward, 'amount_due', v_inv.amount_due,
                                                         'remaining', public.so_invoice_remaining(v_inv.id)),
                            'applied', v_applied,
                            'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id),
                            'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_invoice_issue(uuid[], uuid, date) is
  '⭐⭐ 인보이스 발행(§8 8-c · §17 ⓐ1 · ⓑ2 2026-09-24) — 속 함수(invoker · authenticated 없음 · so_finalize(ⓐ2) · so_invoice_reissue 가 부른다). 이미 갈린 오더 묶음 하나 → 한 장: 전부 shipped · 살아 있는 인보이스에 안 담김 · 같은 청구처 · 같은 통화 아니면 전체 거부. 오더마다 규칙 = manual 이면 오더 규칙 · 아니면 발행일로 배송지에서 다시(§16 판정 5·7) · 금액은 so_tax_preview(…, shipped) 식 한 곳 · 줄 사본 so_invoice_line · 기한 issued_on + net_days(판정 10). ⓑ2: 합계를 굳힌 뒤 ① 담긴 오더 대상 선결제를 auto_deposit 으로(판정 4 · 받은 날 순 · 남는 돈은 잔액) ② 손님 일반 잔액(available · 예약분 제외 · ⓒ 전이라 받아 둔 돈만)을 auto_balance 로 인보이스만큼만(판정 5) · deposit_applied · balance_forward = −② (0 이하 · 봤는데 없으면 0) · amount_due = total − ① + bf · 담긴 오더 shipped→fulfilled(closed_at · 판정 1) · 반환 totals(+remaining) · applied · customer_balance · 번호는 되돌리지 않는다';

-- ═══ ⑥ so_invoice_cancel 재발행 — 마지막 정의 20260924200029:710~749 · 판정 7 가드·풀기 · fulfilled→shipped(invoiced_at · closed_at null) ═══
create or replace function public.so_invoice_cancel(p_invoice_id uuid, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_inv   public.so_invoice%rowtype;
  v_note  text;
  v_n     int;
  v_orders int;
  v_manual int;
  v_auto   int;
  v_auto_amt numeric;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — 인보이스 취소는 manager 이상(6-g · 8-h · 판정 8)
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  if v_note is null then raise exception 'A cancel needs a reason (p_note) — nothing was saved'; end if;

  select * into v_inv from public.so_invoice i where i.id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found — nothing was saved'; end if;
  if v_inv.status <> 'issued' then raise exception 'Invoice % is already % — nothing was saved', v_inv.invoice_number, v_inv.status; end if;
  perform 1 from public.customer c where c.id = v_inv.bill_to_customer_id for update;   -- 청구처 손님 행 잠금

  -- ⓑ2 판정 7 — 사람이 붙인 결제(manual)가 있으면 거부 · 발행 때 자동으로 붙은 것(auto_deposit · auto_balance)은 취소와 함께 void(흔적)
  select count(*) into v_manual from public.so_payment_alloc a where a.invoice_id = p_invoice_id and a.voided_at is null and a.source = 'manual';
  if v_manual > 0 then
    raise exception 'Invoice % has % payment allocation(s) applied by hand — detach them first (or issue a credit note instead, 8-h) — nothing was saved', v_inv.invoice_number, v_manual;
  end if;
  -- ⬜ ⓒ 자리(8-h 「크레딧이 붙기 전에만」): so_credit_alloc 표가 서는 차수가 이 함수를 재발행해 「크레딧이 붙었으면 거부」를 여기에 더한다(없는 표를 참조하는 코드는 지금 쓰지 않는다)
  select count(*), coalesce(sum(a.amount), 0) into v_auto, v_auto_amt from public.so_payment_alloc a where a.invoice_id = p_invoice_id and a.voided_at is null and a.source in ('auto_deposit', 'auto_balance');
  update public.so_payment_alloc set voided_at = now(), voided_by = v_staff, void_note = 'Invoice ' || v_inv.invoice_number || ' cancelled: ' || v_note, updated_by = v_staff
  where invoice_id = p_invoice_id and voided_at is null and source in ('auto_deposit', 'auto_balance');
  get diagnostics v_n = row_count;
  if v_n <> v_auto then raise exception 'Invoice % — % of % automatic allocations could not be released — nothing was saved', v_inv.invoice_number, v_n, v_auto; end if;

  update public.so_invoice set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff, cancel_note = v_note, updated_by = v_staff
  where id = p_invoice_id and status = 'issued';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Invoice % was not cancelled — it may have been changed by someone else just now — nothing was saved', v_inv.invoice_number; end if;
  update public.so_invoice_order set cancelled_at = now(), updated_by = v_staff where invoice_id = p_invoice_id and cancelled_at is null;   -- active_so_id 가 풀린다 → 다시 발행 가능
  get diagnostics v_orders = row_count;
  update public.so s set status = 'shipped', invoiced_at = null, closed_at = null, updated_by = v_staff                                   -- 문지기 짝 fulfilled→shipped(8-h 하향 · closed_at 짝 비움)
  from public.so_invoice_order o where o.invoice_id = p_invoice_id and s.id = o.so_id and s.status = 'fulfilled';
  get diagnostics v_n = row_count;
  if v_n <> v_orders then raise exception 'Invoice % — % of % orders could not be set back to shipped — nothing was saved', v_inv.invoice_number, v_n, v_orders; end if;

  return jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'status', 'cancelled', 'orders_back_to_shipped', v_orders, 'cancelled_by', v_staff, 'note', v_note,
                            'auto_allocations_released', v_auto, 'released_amount', v_auto_amt,
                            'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id));
end;
$$;
comment on function public.so_invoice_cancel(uuid, text) is
  '⭐ 인보이스 취소(6-g · 8-h · §17 ⓐ1 · ⓑ2 판정 7) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · issued 만 · 사유 필수 · 문서 전체가 틀렸을 때만(부분 문제는 크레딧 8-h) · ⓑ2: alloc 에 source manual 이 하나라도 있으면 「먼저 떼라」 거부 · auto_deposit·auto_balance 는 취소와 함께 void(void_note 「Invoice N cancelled: 사유」 · 돈은 받아 둔 돈으로 · 선결제는 대상 표시가 남아 다시 발행하면 다시 붙는다) · 담긴 오더 전부 fulfilled→shipped(invoiced_at · closed_at null) · so_invoice_order.cancelled_at(active_so_id 풀림 → so_invoice_reissue 로 새 번호) · 번호는 남는다 · ⬜ 크레딧이 붙었으면 거부는 ⓒ 가 재발행해 더한다';

-- ═══ ⑦ so_detail 재발행 — 마지막 정의 20260924202425:426~504 · 바뀐 곳: basis 목록에서 invoiced 제거 · invoice 에 deposit_applied·balance_forward·remaining·paid · customer_balance ═══
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
  if v_basis = 'shipped' then
    v_lines_total := (v_tax->'totals'->>'lines_amount')::numeric;
    v_od_amt := case when v_so.order_discount_pct is null then 0 else round(v_lines_total * v_so.order_discount_pct / 100, 2) end;
  end if;
  select jsonb_build_object('invoice_id', i.id, 'invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'due_on', i.due_on, 'total', i.total,
                            'deposit_applied', i.deposit_applied, 'balance_forward', i.balance_forward, 'amount_due', i.amount_due,
                            'remaining', public.so_invoice_remaining(i.id), 'paid', i.total - public.so_invoice_remaining(i.id)) into v_inv
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
                                 'order_total', v_lines_total - v_od_amt + v_charges_total,
                                 'tax_rule', v_so.tax_rule, 'tax_rule_source', v_tax->>'source', 'tax', v_tax->'totals'->'tax',
                                 'order_total_with_tax', case when v_tax->'totals'->>'tax' is null then null else v_lines_total - v_od_amt + v_charges_total + (v_tax->'totals'->>'tax')::numeric end),
    'tax', v_tax,
    'invoice', v_inv,
    'invoice_history', v_inv_hist,
    'customer_balance', v_bal,
    'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_detail(uuid) is
  '⭐ SO 오더 읽기 한 창구(①b · 할인 규칙 ②-0b · 세금 ② · ⓐ2 · ⓑ2 재발행) — invoker · stable(RLS select 그대로 · 로그인만). so · customer_name · lines(+ total(주문 수량) · shipped_total(보낸 수량) · removed · no_price · free · deal_ended) · charges · totals(⭐ basis ordered|shipped — shipped·fulfilled 는 보낸 수량 기준(뺀 몫·pick_short 제외 · 인보이스가 정본 8-c) · lines_removed · qty_removed · lines_total · order_discount_amount · charges_total · order_total · tax_rule · tax_rule_source · tax · order_total_with_tax) · tax = so_tax_preview(basis) · ⭐ invoice(살아 있는 인보이스 번호·상태·기한·total · ⓑ2 deposit_applied · balance_forward · amount_due · remaining(so_invoice_remaining) · paid) · invoice_history(취소된 것 포함) · ⓑ2 customer_balance(청구처의 그 통화 행 · so_customer_balance) · warnings = so_tier_warnings + tax_rule_missing · lines_removed · tax 경고 + no_lines · lines_without_price · deal_ended_before_line_added · reprice_suggested. 화면 셋이 다시 짜지 않는다';

-- ═══ ⑧ so_proforma — 견적서(판정 3 · pro forma · 저장하지 않는다 · 읽기만) · invoker · stable · 로그인(so_detail 과 같은 급) ═══
create function public.so_proforma(p_so_ids uuid[]) returns jsonb
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
               p.amount - coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null), 0) as remaining
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

-- ═══ 검증(~/asung/prompts/so-payment-1b-verify.sql · psql -v ON_ERROR_STOP=1 -f · 전부 rollback · 시퀀스 둘은 rollback 밖 setval) ═══
--   구조(deposit_applied · CHECK 셋 · so_status_ck 여덟 · 문지기 짝 · so_proforma · so_payment_is_reserved) · 0.23 → 188.77 인보이스 → 보내실 금액 188.54(auto_balance 0.23 · bf −0.23) · 잔액 500 > 인보이스 188.77 → 인보이스만큼만(bf −188.77 · due 0) ·
--   다른 오더 대상 선결제(예약)는 발행 때 안 쓰임 · 선결제 대상 셋 → so_finalize(실제 픽·원장) → auto_deposit · 인보이스가 적으면 남는 돈 잔액(대상이 전부 발행돼 예약 풀림) · so_finalize 반환에 totals.deposit_applied 보임 ·
--   끝 fulfilled(closed_at) · 취소 → shipped(closed_at null) · auto 풀림(void_note 인보이스 번호 · 돈은 잔액으로) · manual 있으면 거부 → 떼고 취소 · 다시 발행 → 다시 붙음 · so_detail invoice.remaining·paid·customer_balance ·
--   견적서(받은 금액 · 남은 금액 · 예상 세금 · 아무것도 안 씀 · 끝난 오더 거부) · so_status_ck 가 invoiced 거부 · CHECK 셋 constraint_name · 흔적 0 · 25000 f · 60000 f
