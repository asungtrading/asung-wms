-- ═══ SO 크레딧 ⓒ2 — 잔액에 진 빚 · 발행 때 크레딧부터 · 취소 때 auto 크레딧 풀기 · 환불 한도(받아 둔 돈 + 진 빚 · 크레딧부터) · 크레딧 붙이기·떼기 창구 · so_detail (2026-09-25 · 지시서 ~/asung/prompts/so-credit-1.md · 판정 회신 · ⓒ1 20260925012354 위에) ═══
-- 판정: 8-e 「크레딧부터」 · 판정 5(발행 때 잔액 자동 · 순서 선결제 → 크레딧 → 받아 둔 돈) · 판정 6(붙이기 sales · 떼기 manager) · 판정 7(취소 때 auto 는 풀고 manual 이면 거부 — 크레딧도 같은 규칙) · 이견 0-9(크레딧 환불은 so_credit_alloc.refund_payment_id · received 무접촉 · 한도 received + owed_credit · 크레딧부터) · ⬜7(so_invoice.credit_applied 칸 · 종이엔 「이전 잔액」 한 줄)
-- 훑기(마지막 정의 · grep owed_credit·received·available·so_credit_alloc): 재발행 일곱 — so_customer_balance(진 빚 항 · 환불의 크레딧 몫) · so_invoice_remaining(크레딧 붙임 차감) · so_invoice_issue(② 크레딧 · ③ 받아 둔 돈만) · so_invoice_cancel(크레딧 가드·풀기) · so_payment_refund(한도·크레딧부터) · so_payment_void(환불 취소 → 크레딧 몫 풀기) · so_detail
--   무접촉 — so_payment_propose(결제 → 인보이스 제안 · 크레딧과 무관 · 남은 금액은 so_invoice_remaining 이 이미 크레딧을 뺀다) · so_proforma(customer_balance 를 함수로 받아 owed_credit 이 저절로 실린다) · so_payment_alloc_add(바닥은 received — 크레딧과 별개) · so_credit_cancel(활성 alloc 가드가 인보이스·환불 둘 다 본다 · ⓒ1)
-- 새 것: so_invoice.credit_applied + CHECK 둘 · so_credit_alloc_add(속) · so_credit_attach(sales) · so_credit_detach(manager)
-- 검증 ~/asung/prompts/so-credit-1b-verify.sql(새 틀 · -v mig=이 파일) · 시퀀스 셋 머리에서 읽고 끝에서 되돌림

-- ═══ ① so_invoice.credit_applied — 발행 순간 크레딧에서 자동으로 붙인 몫(② · 회계 근거 · ⬜7) · balance_forward ≤ −credit_applied ═══
alter table public.so_invoice add column if not exists credit_applied numeric not null default 0;
alter table public.so_invoice add constraint so_invoice_credit_ck    check (credit_applied >= 0);
alter table public.so_invoice add constraint so_invoice_bf_credit_ck check (balance_forward is null or balance_forward <= -credit_applied);
comment on column public.so_invoice.credit_applied is '발행 순간 손님의 진 빚(issued 크레딧)에서 자동으로 붙인 금액(so_credit_alloc source auto · 판정 5 「크레딧부터」 · ⓒ2) · balance_forward = −(credit_applied + 받아 둔 돈 붙임) 이라 종이엔 「이전 잔액」 한 줄(8-c) · 이 칸은 회계가 계정을 가를 근거(8-e ⚠️ 받아 둔 돈과 진 빚은 계정이 갈릴 수 있다) · CHECK credit_applied ≥ 0 · balance_forward ≤ −credit_applied';

-- ═══ ② so_credit_alloc_add — 크레딧 붙이기 한 줄(속 함수 · 인보이스 또는 환불 결제 · 한도 둘 = 크레딧 남은 몫 · 인보이스 남은 금액) ═══
create function public.so_credit_alloc_add(p_credit_id uuid, p_invoice_id uuid, p_amount numeric, p_source text, p_staff uuid, p_refund_payment_id uuid default null) returns public.so_credit_alloc
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_c   public.so_credit%rowtype;
  v_i   public.so_invoice%rowtype;
  v_p   public.so_payment%rowtype;
  v_rem numeric;
  v_row public.so_credit_alloc%rowtype;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Credit allocation amount must be positive — nothing was saved'; end if;
  if p_amount <> round(p_amount, 2) then raise exception 'Amounts have at most two decimals (got %) — nothing was saved', p_amount; end if;
  if p_source not in ('manual', 'auto') then raise exception 'Unknown credit allocation source % — nothing was saved', p_source; end if;
  if (p_invoice_id is null) = (p_refund_payment_id is null) then raise exception 'A credit allocation targets exactly one of an invoice or a refund — nothing was saved'; end if;
  select * into v_c from public.so_credit c where c.id = p_credit_id for update;
  if not found then raise exception 'Credit note not found — nothing was saved'; end if;
  if v_c.status <> 'issued' then raise exception 'Credit note % is % — nothing was saved', v_c.credit_number, v_c.status; end if;
  v_rem := v_c.total - coalesce((select sum(a.amount) from public.so_credit_alloc a where a.credit_id = v_c.id and a.voided_at is null), 0);
  if p_amount > v_rem then raise exception 'Credit note % has only % left (asked %) — nothing was saved', v_c.credit_number, v_rem, p_amount; end if;
  if p_invoice_id is not null then
    select * into v_i from public.so_invoice i where i.id = p_invoice_id for update;
    if not found then raise exception 'Invoice not found — nothing was saved'; end if;
    if v_i.status <> 'issued' then raise exception 'Invoice % is % — nothing was saved', v_i.invoice_number, v_i.status; end if;
    if v_i.bill_to_customer_id <> v_c.customer_id then raise exception 'Invoice % bills a different customer than credit note % — nothing was saved', v_i.invoice_number, v_c.credit_number; end if;
    if v_i.currency_id <> v_c.currency_id then raise exception 'Invoice % is in % but credit note % is in % — same currency only — nothing was saved', v_i.invoice_number, v_i.currency_code, v_c.credit_number, v_c.currency_code; end if;
    if exists (select 1 from public.so_credit_alloc a where a.credit_id = v_c.id and a.active_target = v_i.id) then
      raise exception 'Credit note % is already applied to invoice % — detach that first — nothing was saved', v_c.credit_number, v_i.invoice_number;
    end if;
    if p_amount > public.so_invoice_remaining(v_i.id) then raise exception 'Invoice % has only % left to pay (asked %) — nothing was saved', v_i.invoice_number, public.so_invoice_remaining(v_i.id), p_amount; end if;
  else
    select * into v_p from public.so_payment p where p.id = p_refund_payment_id;
    if not found or v_p.kind <> 'refund' or v_p.status <> 'active' then raise exception 'Refund payment not found or not an active refund — nothing was saved'; end if;
    if v_p.customer_id <> v_c.customer_id or v_p.currency_id <> v_c.currency_id then raise exception 'Refund and credit note % differ in customer or currency — nothing was saved', v_c.credit_number; end if;
  end if;
  insert into public.so_credit_alloc (credit_id, invoice_id, refund_payment_id, amount, source, created_by, updated_by)
  values (v_c.id, p_invoice_id, p_refund_payment_id, p_amount, p_source, p_staff, p_staff) returning * into v_row;
  return v_row;
end;
$$;
comment on function public.so_credit_alloc_add(uuid, uuid, numeric, text, uuid, uuid) is '⭐ 크레딧 붙이기 한 줄(속 함수 · ⓒ2 · 8-e credit_applied) — 크레딧 issued · 대상 = 인보이스(issued · 같은 청구처·통화 · 활성 짝 없음 · 한도 so_invoice_remaining) 또는 환불 결제(kind refund · 활성 · 같은 손님·통화) · 한도 = 크레딧 남은 몫 · source manual(창구 so_credit_attach · 환불) | auto(발행 ②) · 권한은 부르는 창구가 봤다';
revoke all on function public.so_credit_alloc_add(uuid, uuid, numeric, text, uuid, uuid) from public, anon, authenticated;

-- ═══ ③ 창구 둘 — so_credit_attach(sales) · so_credit_detach(manager) · ⓑ 의 so_payment_attach/detach 와 같은 모양 ═══
create function public.so_credit_attach(p_credit_id uuid, p_allocs jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_c public.so_credit%rowtype;  v_a public.so_credit_alloc%rowtype;  v_allocs jsonb := '[]'::jsonb;  v_sum numeric := 0;  x jsonb;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  select * into v_c from public.so_credit c where c.id = p_credit_id;
  if not found then raise exception 'Credit note not found — nothing was saved'; end if;
  perform 1 from public.customer c where c.id = v_c.customer_id for update;
  if jsonb_typeof(p_allocs) is distinct from 'array' or jsonb_array_length(p_allocs) = 0 then raise exception 'Nothing to apply — pass [{invoice_id, amount}] — nothing was saved'; end if;
  for x in select t from jsonb_array_elements(p_allocs) t loop
    v_a := public.so_credit_alloc_add(v_c.id, nullif(x->>'invoice_id', '')::uuid, (x->>'amount')::numeric, 'manual', v_staff, null);
    v_sum := v_sum + v_a.amount;
    v_allocs := v_allocs || jsonb_build_object('alloc_id', v_a.id, 'invoice_id', v_a.invoice_id, 'invoice_number', (select i.invoice_number from public.so_invoice i where i.id = v_a.invoice_id), 'amount', v_a.amount, 'invoice_remaining', public.so_invoice_remaining(v_a.invoice_id));
  end loop;
  return jsonb_build_object('credit_id', v_c.id, 'credit_number', v_c.credit_number, 'applied', v_sum, 'allocations', v_allocs,
                            'credit_remaining', v_c.total - coalesce((select sum(a.amount) from public.so_credit_alloc a where a.credit_id = v_c.id and a.voided_at is null), 0),
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_c.customer_id) b where b.currency_id = v_c.currency_id));
end;
$$;
comment on function public.so_credit_attach(uuid, jsonb) is '⭐ 크레딧을 인보이스에 붙이기(8-g 소진 · 판정 6 sales · ⓒ2) — definer · 첫 줄 ims_require_write(sales) · [{invoice_id, amount}] 를 so_credit_alloc_add(manual · 한도 둘)로 · 하나라도 막히면 전체 거부 · 반환 applied · allocations · credit_remaining · balance';
revoke all on function public.so_credit_attach(uuid, jsonb) from public, anon;
grant execute on function public.so_credit_attach(uuid, jsonb) to authenticated;

create function public.so_credit_detach(p_alloc_id uuid, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_a public.so_credit_alloc%rowtype;  v_c public.so_credit%rowtype;  v_note text;  v_n int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄(판정 6)
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  if v_note is null then raise exception 'Detaching needs a reason (p_note) — nothing was saved'; end if;
  select * into v_a from public.so_credit_alloc a where a.id = p_alloc_id for update;
  if not found then raise exception 'Credit allocation not found — nothing was saved'; end if;
  if v_a.voided_at is not null then raise exception 'This credit allocation was already detached — nothing was saved'; end if;
  if v_a.refund_payment_id is not null then raise exception 'This credit was paid out by a refund — void the refund instead (so_payment_void) — nothing was saved'; end if;
  select * into v_c from public.so_credit c where c.id = v_a.credit_id;
  perform 1 from public.customer c where c.id = v_c.customer_id for update;
  update public.so_credit_alloc set voided_at = now(), voided_by = v_staff, void_note = v_note, updated_by = v_staff where id = v_a.id and voided_at is null;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Credit allocation was not detached — it may have been changed by someone else just now — nothing was saved'; end if;
  return jsonb_build_object('alloc_id', v_a.id, 'credit_id', v_a.credit_id, 'credit_number', v_c.credit_number, 'invoice_id', v_a.invoice_id, 'amount', v_a.amount, 'source', v_a.source, 'note', v_note,
                            'invoice_remaining', public.so_invoice_remaining(v_a.invoice_id),
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_c.customer_id) b where b.currency_id = v_c.currency_id));
end;
$$;
comment on function public.so_credit_detach(uuid, text) is '⭐ 크레딧 떼기(판정 6 manager · ⓒ2) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · 사유 필수 · 인보이스에 붙인 것만(환불에 쓰인 몫은 환불을 취소해야 풀린다 · so_payment_void) · void(행 유지 · 흔적) · 진 빚으로 돌아간다';
revoke all on function public.so_credit_detach(uuid, text) from public, anon;
grant execute on function public.so_credit_detach(uuid, text) to authenticated;

-- ═══ ④ 재발행 일곱(옛 정의 바이트 그대로 · 바뀐 줄만) — so_invoice_remaining(ⓑ1) · so_customer_balance(ⓑ2) · so_invoice_issue(ⓑ2) · so_invoice_cancel(ⓑ2) · so_payment_refund(ⓑ1) · so_payment_void(ⓑ1) · so_detail(ⓑ2) ═══
-- 4-a so_invoice_remaining — 마지막 정의 20260924234250 · 크레딧 붙임도 뺀다
create or replace function public.so_invoice_remaining(p_invoice_id uuid) returns numeric
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when i.status = 'cancelled' then 0
              else i.total - coalesce((select sum(a.amount) from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
                                        where a.invoice_id = i.id and a.voided_at is null and p.status = 'active'), 0)
                           - coalesce((select sum(ca.amount) from public.so_credit_alloc ca join public.so_credit c on c.id = ca.credit_id
                                        where ca.invoice_id = i.id and ca.voided_at is null and c.status = 'issued'), 0) end   -- ⓒ2: 크레딧 붙임도 뺀다
  from public.so_invoice i where i.id = p_invoice_id;
$$;
comment on function public.so_invoice_remaining(uuid) is '⭐ 인보이스 남은 금액 — total − Σ활성 결제 붙임(활성 결제만) − Σ활성 크레딧 붙임(issued 크레딧만 · ⓒ2) · 0-5 「식은 한 곳」 · 취소된 인보이스는 0';

-- 4-b so_customer_balance — 마지막 정의 20260925001733 · 진 빚 항 · 환불의 크레딧 몫
create or replace function public.so_customer_balance(p_customer_id uuid)
  returns table (currency_id uuid, currency_code text, received numeric, reserved_deposit numeric, owed_credit numeric, available numeric, open_invoices int, open_invoices_due numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with cur as (
    select p.currency_id from public.so_payment p where p.customer_id = p_customer_id
    union
    select i.currency_id from public.so_invoice i where i.bill_to_customer_id = p_customer_id
    union
    select c.currency_id from public.so_credit c where c.customer_id = p_customer_id
  ),
  pay as (
    select p.id, p.currency_id, p.kind, p.amount,
           p.amount - coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null), 0) as remaining,
           p.amount - coalesce((select sum(ca.amount) from public.so_credit_alloc ca where ca.refund_payment_id = p.id and ca.voided_at is null), 0) as refund_from_received,   -- ⓒ2: 환불 중 크레딧이 갚은 몫은 received 에서 빼지 않는다(0-9)
           public.so_payment_is_reserved(p.id) as reserved
      from public.so_payment p
     where p.customer_id = p_customer_id and p.status = 'active'
  ),
  cred as (   -- ⓒ2 진 빚(8-e) = Σissued 크레딧 total − Σ활성 크레딧 붙임(인보이스 · 환불)
    select c.currency_id, sum(c.total) - coalesce(sum((select coalesce(sum(ca.amount), 0) from public.so_credit_alloc ca where ca.credit_id = c.id and ca.voided_at is null)), 0) as owed
      from public.so_credit c where c.customer_id = p_customer_id and c.status = 'issued'
     group by c.currency_id
  ),
  inv as (
    select i.currency_id, count(*) as n, sum(public.so_invoice_remaining(i.id)) as due
      from public.so_invoice i
     where i.bill_to_customer_id = p_customer_id and i.status = 'issued' and public.so_invoice_remaining(i.id) > 0
     group by i.currency_id
  ),
  agg as (
    select c.currency_id,
           coalesce(sum(case when y.kind = 'payment' then y.remaining end), 0) - coalesce(sum(case when y.kind = 'refund' then y.refund_from_received end), 0) as received,
           coalesce(sum(case when y.kind = 'payment' and y.reserved then y.remaining end), 0) as reserved_deposit
      from cur c left join pay y on y.currency_id = c.currency_id
     group by c.currency_id
  )
  select a.currency_id, rc.code, a.received, a.reserved_deposit, coalesce(cr.owed, 0) as owed_credit,
         greatest(a.received + coalesce(cr.owed, 0) - a.reserved_deposit, 0) as available,
         coalesce(v.n, 0)::int as open_invoices, coalesce(v.due, 0) as open_invoices_due
    from agg a
    join public.ref_currency rc on rc.id = a.currency_id
    left join inv v on v.currency_id = a.currency_id
    left join cred cr on cr.currency_id = a.currency_id
   order by rc.code;
$$;

comment on function public.so_customer_balance(uuid) is '⭐⭐ 손님 잔액 식의 정본(8-e · ⓑ1 · ⓑ2 · ⓒ2) — 통화별 한 행 · received = Σ활성 payment 남은 금액 − Σ활성 refund(⚠️ 환불 중 크레딧이 갚은 몫(so_credit_alloc.refund_payment_id)은 뺀다 · 0-9) · reserved_deposit = 예약된 선결제(so_payment_is_reserved) · ⭐ owed_credit = Σissued so_credit.total − Σ활성 so_credit_alloc(인보이스·환불) · available = greatest(received + owed_credit − reserved_deposit, 0) · open_invoices/_due = 미수 인보이스(so_invoice_remaining > 0) · ⚠️ 화면·다른 함수가 이 식을 다시 짜지 않는다 · 별도 잔액 표 없음';

-- 4-c so_invoice_issue — 마지막 정의 20260925001733 · ② 크레딧 · ③ 받아 둔 돈만 · credit_applied · balance_forward = −(② + ③)
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
comment on function public.so_invoice_issue(uuid[], uuid, date) is
  '⭐⭐ 인보이스 발행(§8 8-c · §17 ⓐ1 · ⓑ2 · ⓒ2 2026-09-25) — 속 함수(invoker · authenticated 없음 · so_finalize · so_invoice_reissue 가 부른다). 전부 shipped · 살아 있는 인보이스에 안 담김 · 같은 청구처 · 같은 통화 아니면 전체 거부 · 오더마다 규칙(manual 이면 오더 규칙 · 아니면 발행일로 배송지) · 금액은 so_tax_preview(shipped) · 줄 사본 · 기한. 합계를 굳힌 뒤 자동 셋: ① 담긴 오더 대상 선결제(auto_deposit · 판정 4) ② ⭐ 크레딧(진 빚 · issued 크레딧 발행일 순 · so_credit_alloc source auto · 8-e 「크레딧부터」) ③ 받아 둔 돈(auto_balance · received − reserved_deposit · 예약분 제외) — 인보이스만큼만 · deposit_applied · credit_applied · balance_forward = −(② + ③)(0 이하 · 봤는데 없으면 0 · 종이엔 「이전 잔액」 한 줄) · amount_due = total − ① − ② − ③ · 담긴 오더 shipped→fulfilled(closed_at) · 반환 totals · applied(auto_deposit · auto_credit · auto_balance) · customer_balance';

-- 4-d so_invoice_cancel — 마지막 정의 20260925001733 · 크레딧 가드·풀기(판정 7 과 같은 규칙)
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
  v_cr_manual int;  v_cr_auto int;  v_cr_amt numeric;   -- ⓒ2 크레딧 붙임
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
  -- ⓒ2 8-h 「크레딧이 붙기 전에만」 — 판정 7 과 같은 규칙: 사람이 붙인 크레딧(manual)이 있으면 거부 · 발행 때 자동으로 붙은 크레딧(auto)은 취소와 함께 void(진 빚으로 돌아간다)
  select count(*) into v_cr_manual from public.so_credit_alloc ca where ca.invoice_id = p_invoice_id and ca.voided_at is null and ca.source = 'manual';
  if v_cr_manual > 0 then
    raise exception 'Invoice % has % credit note allocation(s) applied by hand — detach them first (so_credit_detach) — nothing was saved', v_inv.invoice_number, v_cr_manual;
  end if;
  select count(*), coalesce(sum(ca.amount), 0) into v_cr_auto, v_cr_amt from public.so_credit_alloc ca where ca.invoice_id = p_invoice_id and ca.voided_at is null and ca.source = 'auto';
  update public.so_credit_alloc set voided_at = now(), voided_by = v_staff, void_note = 'Invoice ' || v_inv.invoice_number || ' cancelled: ' || v_note, updated_by = v_staff
  where invoice_id = p_invoice_id and voided_at is null and source = 'auto';
  get diagnostics v_n = row_count;
  if v_n <> v_cr_auto then raise exception 'Invoice % — % of % automatic credit allocations could not be released — nothing was saved', v_inv.invoice_number, v_n, v_cr_auto; end if;
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
                            'auto_credit_allocations_released', v_cr_auto, 'released_credit_amount', v_cr_amt,
                            'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id));
end;
$$;
comment on function public.so_invoice_cancel(uuid, text) is
  '⭐ 인보이스 취소(6-g · 8-h · ⓐ1 · ⓑ2 판정 7 · ⓒ2) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · issued 만 · 사유 필수 · 결제·크레딧 모두 같은 규칙: source manual 이 하나라도 있으면 「먼저 떼라」 거부 · 발행 때 자동으로 붙은 것(auto_deposit · auto_balance · 크레딧 auto)은 취소와 함께 void(흔적 · 돈은 받아 둔 돈·진 빚으로) · 담긴 오더 fulfilled→shipped(invoiced_at · closed_at null) · so_invoice_order.cancelled_at · 번호는 남는다 · 반환에 released 넷';

-- 4-e so_payment_refund — 마지막 정의 20260924234250 · 한도 received + owed_credit · 크레딧부터
create or replace function public.so_payment_refund(p jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_c      public.customer%rowtype;
  v_cur    public.ref_currency%rowtype;
  v_w      public.ref_warehouse%rowtype;
  v_acct   public.ref_account%rowtype;
  v_p      public.so_payment%rowtype;
  v_amount numeric;
  v_on     date;
  v_method text;
  v_wh     uuid;
  v_recv   numeric;
  v_owed   numeric;
  v_left   numeric;
  v_take   numeric;
  v_credit_used numeric := 0;
  v_ca     public.so_credit_alloc%rowtype;
  v_used   jsonb := '[]'::jsonb;
  cr       record;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄(판정 6)
  v_staff := public.so_current_staff();

  if nullif(p->>'customer_id', '') is null then raise exception 'customer_id is required — nothing was saved'; end if;
  select * into v_c from public.customer c where c.id = (p->>'customer_id')::uuid for update;   -- 손님 행 잠금
  if not found then raise exception 'Customer not found — nothing was saved'; end if;
  v_amount := (p->>'amount')::numeric;
  if v_amount is null or v_amount <= 0 then raise exception 'Amount must be positive — nothing was saved'; end if;
  if v_amount <> round(v_amount, 2) then raise exception 'Amounts have at most two decimals (got %) — nothing was saved', v_amount; end if;
  v_on := coalesce((p->>'paid_on')::date, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Refund date % is in the future — nothing was saved', v_on; end if;
  v_method := nullif(trim(p->>'method'), '');
  if v_method is null or v_method not in ('cheque','credit_card','debit_card','e_transfer','wire','cash','direct_deposit','shopify') then
    raise exception 'Unknown payment method % — use one of cheque, credit_card, debit_card, e_transfer, wire, cash, direct_deposit, shopify — nothing was saved', coalesce(v_method, '(none)');
  end if;
  select * into v_cur from public.ref_currency c
   where c.id = coalesce(nullif(p->>'currency_id', '')::uuid, (select c2.id from public.ref_currency c2 where c2.code = upper(nullif(trim(p->>'currency_code'), ''))), v_c.currency_id);
  if v_cur.id is null then raise exception 'Currency is required — the customer has no default currency — nothing was saved'; end if;
  v_wh := coalesce(nullif(p->>'warehouse_id', '')::uuid, v_c.default_location_id);
  if v_wh is null then raise exception 'Branch (warehouse_id) is required — the customer has no default warehouse — nothing was saved'; end if;
  select * into v_w from public.ref_warehouse w where w.id = v_wh;
  if not found then raise exception 'Warehouse not found — nothing was saved'; end if;
  if not v_w.is_active then raise exception 'Warehouse % is inactive — nothing was saved', v_w.name; end if;
  if nullif(p->>'account_id', '') is null then raise exception 'A refund needs an account (account_id) — there is no default for money going out — nothing was saved'; end if;
  v_acct := public.so_payment_resolve_account(v_method, v_w.id, v_cur.id, (p->>'account_id')::uuid);

  select b.received, b.owed_credit into v_recv, v_owed from public.so_customer_balance(v_c.id) b where b.currency_id = v_cur.id;
  v_recv := coalesce(v_recv, 0);  v_owed := coalesce(v_owed, 0);
  if v_amount > v_recv + v_owed then
    raise exception 'Customer has only % % on account (% received + % credit) — a refund cannot exceed it (asked %) — nothing was saved', v_recv + v_owed, v_cur.code, v_recv, v_owed, v_amount;
  end if;

  insert into public.so_payment (kind, amount, paid_on, method, reference, customer_id, currency_id, currency_code, account_id, account_code, warehouse_id, warehouse_name, note, created_by, updated_by)
  values ('refund', v_amount, v_on, v_method, nullif(trim(p->>'reference'), ''), v_c.id, v_cur.id, v_cur.code, v_acct.id, v_acct.code, v_w.id, v_w.name, nullif(trim(p->>'note'), ''), v_staff, v_staff)
  returning * into v_p;

  -- ⓒ2 크레딧부터(8-e · 8-g 「요청 시 현금 환불」) — issued 크레딧을 발행일 순으로 이 환불에 붙인다(so_credit_alloc.refund_payment_id · source manual — 매니저의 결정) · 나머지는 받아 둔 돈
  v_left := v_amount;
  for cr in
    select c.id, c.credit_number, c.total - coalesce((select sum(ca.amount) from public.so_credit_alloc ca where ca.credit_id = c.id and ca.voided_at is null), 0) as remaining
      from public.so_credit c where c.customer_id = v_c.id and c.currency_id = v_cur.id and c.status = 'issued'
     order by c.issued_on, c.created_at, c.id
  loop
    exit when v_left <= 0;
    if cr.remaining <= 0 then continue; end if;
    v_take := least(cr.remaining, v_left);
    v_ca := public.so_credit_alloc_add(cr.id, null, v_take, 'manual', v_staff, v_p.id);
    v_credit_used := v_credit_used + v_ca.amount;  v_left := v_left - v_ca.amount;
    v_used := v_used || jsonb_build_object('alloc_id', v_ca.id, 'credit_id', cr.id, 'credit_number', cr.credit_number, 'amount', v_ca.amount);
  end loop;
  if v_left > v_recv then
    raise exception 'Refund % exceeds credit (%) plus money on account (%) — nothing was saved', v_amount, v_credit_used, v_recv;
  end if;

  return jsonb_build_object('payment_id', v_p.id, 'kind', v_p.kind, 'credit_used', v_credit_used, 'received_used', v_left, 'credits', v_used, 'amount', v_p.amount, 'paid_on', v_p.paid_on, 'method', v_p.method, 'reference', v_p.reference,
                            'customer_id', v_p.customer_id, 'currency_code', v_p.currency_code, 'account_id', v_p.account_id, 'account_code', v_p.account_code, 'account_name', v_acct.name,
                            'warehouse_id', v_p.warehouse_id, 'warehouse_name', v_p.warehouse_name, 'status', v_p.status,
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_c.id) b where b.currency_id = v_cur.id));
end;
$$;
comment on function public.so_payment_refund(jsonb) is '⭐ 환불(8-e·8-g · 판정 6 manager · ⓑ1 · ⓒ2) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · p {customer_id, amount, paid_on?, method, reference?, currency_id?|currency_code?, account_id(⚠️ 필수), warehouse_id?, note?} · 한도 = 받아 둔 돈 + 진 빚(received + owed_credit) · ⭐ 크레딧부터(issued 크레딧 발행일 순 · so_credit_alloc.refund_payment_id · source manual) · 나머지는 받아 둔 돈(received 를 넘으면 거부) · kind refund 한 줄 · 반환 credit_used · received_used · credits · balance';

-- 4-f so_payment_void — 마지막 정의 20260924234250 · 환불 취소 → 그 환불이 갚은 크레딧 몫 풀기
create or replace function public.so_payment_void(p_payment_id uuid, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_p     public.so_payment%rowtype;
  v_note  text;
  v_n     int;
  v_rem   numeric;
  v_recv  numeric;
  v_cr    int := 0;   -- ⓒ2 환불에 붙은 크레딧
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄(판정 6)
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  if v_note is null then raise exception 'Voiding needs a reason (p_note) — nothing was saved'; end if;
  select * into v_p from public.so_payment p where p.id = p_payment_id;
  if not found then raise exception 'Payment not found — nothing was saved'; end if;
  perform 1 from public.customer c where c.id = v_p.customer_id for update;   -- 손님 행 잠금
  select * into v_p from public.so_payment p where p.id = p_payment_id for update;
  if v_p.status <> 'active' then raise exception 'Payment is already voided — nothing was saved'; end if;
  select count(*) into v_n from public.so_payment_alloc a where a.payment_id = v_p.id and a.voided_at is null;
  if v_n > 0 then raise exception 'Payment has % allocation(s) applied to invoices — detach them first — nothing was saved', v_n; end if;
  if v_p.kind = 'payment' then
    v_rem := v_p.amount;   -- 활성 alloc 0 이므로 남은 금액 = amount
    select b.received into v_recv from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id;
    if coalesce(v_recv, 0) - v_rem < 0 then
      raise exception 'Voiding this payment would put the customer''s % balance below zero (% on account, refunds already paid out) — nothing was saved', v_p.currency_code, coalesce(v_recv, 0);
    end if;
  end if;
  if v_p.kind = 'refund' then   -- ⓒ2: 이 환불이 갚은 크레딧 몫은 함께 풀린다(void · 진 빚으로 돌아간다)
    update public.so_credit_alloc set voided_at = now(), voided_by = v_staff, void_note = 'Refund voided: ' || v_note, updated_by = v_staff where refund_payment_id = v_p.id and voided_at is null;
    get diagnostics v_cr = row_count;
  end if;
  update public.so_payment set status = 'voided', voided_at = now(), voided_by = v_staff, void_note = v_note, updated_by = v_staff where id = v_p.id and status = 'active';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Payment was not voided — it may have been changed by someone else just now — nothing was saved'; end if;
  return jsonb_build_object('payment_id', v_p.id, 'kind', v_p.kind, 'amount', v_p.amount, 'status', 'voided', 'note', v_note, 'credit_allocations_released', v_cr,
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id));
end;
$$;
comment on function public.so_payment_void(uuid, text) is '⭐ 결제·환불 취소(판정 6 manager · ⓑ1 · 0-6 · ⓒ2) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · 사유 필수 · 활성 결제 붙임이 있으면 「먼저 떼라」 거부 · payment 는 취소 뒤 받아 둔 돈이 음수면 거부 · ⭐ refund 취소는 그 환불이 갚은 크레딧 몫(so_credit_alloc.refund_payment_id)을 함께 void(진 빚으로 돌아간다) · 대상 오더 표시는 그대로 · 삭제 없음';

-- 4-g so_detail — 마지막 정의 20260925001733 · invoice.credit_applied · credits · credited_total · 줄 qty_credited
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
  '⭐ SO 오더 읽기 한 창구(①b · ②-0b · 세금 ② · ⓐ2 · ⓑ2 · ⓒ2 재발행) — invoker · stable(RLS select · 로그인만). so · customer_name · lines(+ total · shipped_total · removed · no_price · free · deal_ended · ⓒ2 qty_credited(issued 크레딧의 반품 수량)) · charges · totals(basis ordered|shipped …) · tax · invoice(번호·상태·기한·total · deposit_applied · ⓒ2 credit_applied · balance_forward · amount_due · remaining · paid · ⓒ2 credits[] · credited_total) · invoice_history · customer_balance(그 통화 행 · owed_credit 포함) · warnings. 화면 셋이 다시 짜지 않는다';

-- ═══ 검증(~/asung/prompts/so-credit-1b-verify.sql · 새 틀 · -v mig=이 파일 · 전부 rollback · 시퀀스 셋) — 요지는 지시서 회신 ═══
