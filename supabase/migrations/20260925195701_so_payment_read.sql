-- SO 결제 읽기 창구 — so_payment_remaining(식의 한 곳) · so_customer_balance 재발행 · so_invoice_detail 재발행 · 뷰 so_payment_list · so_payment_detail (2026-09-25 UTC · 토론토 2026-09-25 오후)
-- 지시서 ~/asung/prompts/so-pay-read-1.md · 판정 회신 Caleb 2026-09-25(이견 0-1~0-8 · ⬜1~⬜5 전부) · 정본 §18(결제 ⓑ) · §19(0-9) · 화면 so-payments.html 은 그리기만(대화 Claude)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 시험 적용 + 검증 ~/asung/prompts/so-pay-read-1-verify.sql(-v mig)
-- P0 so_payment_remaining(p_payment_id) — 취소(voided) 0 · 환불(refund) null(붙일 돈이 아니다 · 0-1·⬜1) · 그 밖 amount − Σ활성 so_payment_alloc(voided_at is null) — so_customer_balance pay CTE :146 의 식과 active·payment 행에서 같은 값
-- P1 so_customer_balance 재발행(마지막 정의 20260925014413:132~180 · 바이트 그대로 · 바뀐 줄 하나 = :146 remaining 식 → so_payment_remaining(p.id)) — ⚠️ 손님 잔액의 한 곳(부르는 곳 25 · 반환 표 무변) · 검증 P1 이 「모든 손님 × 통화 여덟 칸 재발행 전후 동일」을 증명
-- P2 so_invoice_detail 재발행(마지막 정의 20260925191843:68~118 · create → create or replace · 바뀐 줄 둘 = :84 주석 ⬜ → ✅ · :85 복사 식 → so_payment_remaining(p.id))
-- R1 뷰 so_payment_list — 결제 한 건 한 행 · security_invoker · attached(Σ활성 붙임) · remaining(P0) · held_for_orders(so_payment_is_reserved · payment 만 · 환불·취소 null · 0-5) · 환불 줄 두 칸 refund_credit_covered · refund_from_account(pay CTE :147 과 같은 뜻 · 0-2)
--    invoice_numbers(활성 붙임의 인보이스) · target_so_numbers(so_payment_order · 살아 있는 걸림) · created_by_name(ims_staff · 별칭 한정 · ⬜4) · search_text(참조 · 손님 · 인보이스 · 오더 · 방법 · 계좌 코드 · 메모 · 0-7)
-- R2 so_payment_detail(p_payment_id) — payment(뷰 행) · allocations(취소된 것도 · voided_at) · targets(오더 · 상태 · 발행됐나) · refund_credits(환불을 갚은 크레딧 붙임) · open_invoices(같은 손님 · 같은 통화 · is_open · 오래된 순 · attached_from_this_payment · 0-6) · customer_balance · 없는 id → null
-- 권한: 뷰 revoke all from anon, authenticated, public → grant select · RPC stable invoker · revoke public, anon → grant execute authenticated(20260925191843 선례) · 쓰기 문 없음
-- ⚠️ 붙임 합 조건은 so_invoice_remaining · so_customer_balance 와 같다(voided_at is null · 결제는 status active 를 뷰 행이 스스로 안다) — 어긋나면 attached + remaining ≠ amount
-- ⚠️ 시험 자료는 직접 insert(so-inv-read-1 0-5 방식 · 79001~ · Xeonium · 시퀀스 무접촉) · 화면 시험 실물(Clore · 결제 둘 · 60000)은 무변을 chk

-- ═══ P0 so_payment_remaining ═══
create function public.so_payment_remaining(p_payment_id uuid) returns numeric
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when p.status = 'voided' then 0
              when p.kind = 'refund' then null
              else p.amount - coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null), 0) end
  from public.so_payment p where p.id = p_payment_id;
$$;
comment on function public.so_payment_remaining(uuid) is '⭐ 결제 남은 금액의 정본(so-pay-read-1 P0 · 2026-09-25) — amount − Σ활성 so_payment_alloc(voided_at is null) · 취소된 결제 0 · 환불(kind refund)은 null(붙일 돈이 아니다 · 환불이 갚은 몫은 so_credit_alloc.refund_payment_id 쪽 · 뷰의 refund_credit_covered/refund_from_account) · so_customer_balance · so_invoice_detail · so_payment_list 가 이 함수를 부른다(식을 다시 짜지 마라)';
revoke all on function public.so_payment_remaining(uuid) from public, anon;
grant execute on function public.so_payment_remaining(uuid) to authenticated;

-- ═══ P1 so_customer_balance 재발행 — 마지막 정의 20260925014413:132~180 · 바이트 그대로 · 바뀐 줄 하나(:146) ═══
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
           public.so_payment_remaining(p.id) as remaining,                                                                                  -- so-pay-read-1 P1(2026-09-25): 식의 한 곳 — 옛 인라인 식(20260925014413:146)과 active·payment 행에서 값이 같다(검증 P1)
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

-- ═══ P2 so_invoice_detail 재발행 — 마지막 정의 20260925191843:68~118 · create → create or replace · 바뀐 줄 둘(:84 주석 · :85 식) ═══
create or replace function public.so_invoice_detail(p_invoice_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'invoice', to_jsonb(v),
    'orders', (select coalesce(jsonb_agg(to_jsonb(o) || jsonb_build_object('so_status', s.status, 'ref', s.ref, 'channel', s.channel, 'intake', s.intake, 'store_name', c2.name)
                                          order by o.so_number), '[]'::jsonb)
               from public.so_invoice_order o
               join public.so s on s.id = o.so_id
               left join public.customer c2 on c2.id = o.customer_id
               where o.invoice_id = v.id),
    'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.line_no), '[]'::jsonb) from public.so_invoice_line l where l.invoice_id = v.id),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object(
                   'alloc_id', a.id, 'payment_id', p.id, 'paid_on', p.paid_on, 'method', p.method, 'reference', p.reference, 'account_code', p.account_code, 'warehouse_name', p.warehouse_name,
                   'amount', a.amount, 'payment_amount', p.amount,
                   -- 결제의 남은 금액(0-8) — ✅ so-pay-read-1(2026-09-25) 이 so_payment_remaining 으로 뗐다(식의 한 곳 · 옛 복사 식은 20260925014413_so_credit_c2.sql:146 에서 왔었다)
                   'payment_remaining', public.so_payment_remaining(p.id),
                   'source', a.source, 'voided_at', a.voided_at, 'void_note', a.void_note, 'payment_status', p.status, 'created_at', a.created_at)
                   order by p.paid_on, p.created_at, a.created_at), '[]'::jsonb)
                 from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
                 where a.invoice_id = v.id),
    'credits_applied', (select coalesce(jsonb_agg(jsonb_build_object(
                          'alloc_id', a.id, 'credit_id', c.id, 'credit_number', c.credit_number, 'credit_status', c.status, 'issued_on', c.issued_on, 'credit_total', c.total,
                          'amount', a.amount, 'source', a.source, 'voided_at', a.voided_at, 'void_note', a.void_note, 'created_at', a.created_at)
                          order by c.issued_on, c.credit_number, a.created_at), '[]'::jsonb)
                        from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id
                        where a.invoice_id = v.id),
    'credits_against', (select coalesce(jsonb_agg(jsonb_build_object(
                          'credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'reason', c.reason,
                          'lines_amount', c.lines_amount, 'fee_amount', c.fee_amount, 'tax_amount', c.tax_amount, 'total', c.total, 'cancelled_at', c.cancelled_at,
                          'applied_here', coalesce((select sum(a.amount) from public.so_credit_alloc a where a.credit_id = c.id and a.invoice_id = v.id and a.voided_at is null), 0))
                          order by c.issued_on, c.credit_number), '[]'::jsonb)
                        from public.so_credit c where c.invoice_id = v.id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', h.id, 'invoice_number', h.invoice_number, 'status', h.status, 'issued_on', h.issued_on, 'total', h.total, 'cancelled_at', h.cancelled_at, 'cancel_note', h.cancel_note,
                  'so_numbers', (select string_agg(ho.so_number, ', ' order by ho.so_number) from public.so_invoice_order ho where ho.invoice_id = h.id))
                  order by h.invoice_number), '[]'::jsonb)
                from public.so_invoice h
                where h.id <> v.id
                  and exists (select 1 from public.so_invoice_order a1 join public.so_invoice_order a2 on a2.so_id = a1.so_id
                              where a1.invoice_id = v.id and a2.invoice_id = h.id)),
    'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v.bill_to_customer_id) b where b.currency_id = v.currency_id)
  )
  from public.so_invoice_list v
  where v.id = p_invoice_id;
$$;
comment on function public.so_invoice_detail(uuid) is
  '⭐ 판매 인보이스 한 장(so-inv-read-1 R2 · 2026-09-25) — jsonb 하나 · 읽기(stable · invoker) · 없는 id → null(po_detail 선례). invoice(뷰 행 전부 · remaining·paid·credited·days_overdue·is_open·due_unknown) · orders(오더별 배송지·세금 굳힘 + 오더 상태·ref·길·매장 이름) · lines(line_no 순) · payments(붙임 행마다 · 붙인 몫·결제 금액·payment_remaining(0-8 · 식은 so_customer_balance :146 그대로 · ⬜ 함수로 뗀다) · voided 도 실린다 — 화면이 가른다) · credits_applied(이 장에 붙은 크레딧 붙임) · credits_against(이 장을 원판매로 되짚은 크레딧 · applied_here) · history(같은 오더가 걸렸던 다른 인보이스 — 재발행 사슬 · 칸 없이 유도 · 0-1) · customer_balance(청구처의 그 통화 행)';
revoke all on function public.so_invoice_detail(uuid) from public, anon;
grant execute on function public.so_invoice_detail(uuid) to authenticated;

-- ═══ R1 so_payment_list — 결제 한 건 = 한 행 ═══
create view public.so_payment_list
  with (security_invoker = true) as
with al as (   -- 살아 있는 결제 붙임(voided_at is null · 결제 자체의 상태는 행이 안다)
  select a.payment_id, sum(a.amount) as attached,
         string_agg(i.invoice_number, ', ' order by i.invoice_number) as invoice_numbers
  from public.so_payment_alloc a join public.so_invoice i on i.id = a.invoice_id
  where a.voided_at is null
  group by a.payment_id
),
tg as (        -- 대상 오더(so_payment_order · 금액 없음 · 발행 순간 자동 붙음)
  select o.payment_id, string_agg(s.so_number, ', ' order by s.so_number) as target_so_numbers
  from public.so_payment_order o join public.so s on s.id = o.so_id
  group by o.payment_id
),
rc as (        -- 환불을 갚은 크레딧 몫(so_credit_alloc.refund_payment_id · 활성만 · pay CTE :147 refund_from_received 와 같은 뜻)
  select ca.refund_payment_id as payment_id, sum(ca.amount) as covered
  from public.so_credit_alloc ca
  where ca.refund_payment_id is not null and ca.voided_at is null
  group by ca.refund_payment_id
)
select p.id, p.kind, p.status, p.paid_on, p.method, p.reference, p.amount, p.currency_id, p.currency_code,
       p.customer_id, cu.name as customer_name,
       p.account_id, p.account_code, ac.name as account_name, p.warehouse_id, p.warehouse_name,
       case when p.kind = 'payment' and p.status = 'active' then coalesce(al.attached, 0) else 0 end as attached,
       r.remaining,
       case when p.kind = 'payment' and p.status = 'active' then public.so_payment_is_reserved(p.id) else null end as held_for_orders,
       case when p.kind = 'refund' then coalesce(rc.covered, 0) else null end                as refund_credit_covered,
       case when p.kind = 'refund' then p.amount - coalesce(rc.covered, 0) else null end     as refund_from_account,
       al.invoice_numbers, tg.target_so_numbers,
       p.voided_at, p.void_note, p.note, p.created_at,
       (select s.name from public.ims_staff s where s.id = p.created_by) as created_by_name,
       (coalesce(p.reference, '') || ' ' || coalesce(cu.name, '') || ' ' || coalesce(al.invoice_numbers, '') || ' ' || coalesce(tg.target_so_numbers, '') || ' ' || p.method || ' ' || coalesce(p.account_code, '') || ' ' || coalesce(p.note, '')) as search_text
from public.so_payment p
left join public.customer cu on cu.id = p.customer_id
left join public.ref_account ac on ac.id = p.account_id
left join al on al.payment_id = p.id
left join tg on tg.payment_id = p.id
left join rc on rc.payment_id = p.id
cross join lateral (select public.so_payment_remaining(p.id) as remaining) r;   -- 읽기 함수(stable)를 lateral 에서 한 번 — 쓰기 창구가 아니다
comment on view public.so_payment_list is
  '⭐ 결제 목록(so-pay-read-1 R1 · 2026-09-25) — 한 건 한 행 · PostgREST 로 표처럼 · security_invoker. attached = Σ활성 붙임(active payment 만 · 취소·환불 0) · remaining = so_payment_remaining(id)(취소 0 · 환불 null) · attached + remaining = amount(active payment) · held_for_orders = so_payment_is_reserved(payment 만 · 대상 오더에 걸려 발행을 기다리는 돈 · 손님 잔액 available 에서 빠진다 · 환불·취소 null) · 환불 줄은 refund_credit_covered(크레딧이 갚은 몫) · refund_from_account(받아 둔 돈에서 나간 몫) · invoice_numbers(활성 붙임) · target_so_numbers(so_payment_order) · search_text = 참조 · 손님 · 인보이스 · 오더 · 방법 · 계좌 코드 · 메모';
revoke all on public.so_payment_list from anon, authenticated, public;
grant select on public.so_payment_list to authenticated;

-- ═══ R2 so_payment_detail — 한 건을 jsonb 하나로(없는 id → null) ═══
create function public.so_payment_detail(p_payment_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'payment', to_jsonb(v),
    'allocations', (select coalesce(jsonb_agg(jsonb_build_object(
                      'alloc_id', a.id, 'invoice_id', i.id, 'invoice_number', i.invoice_number, 'invoice_status', i.status, 'invoice_total', i.total,
                      'amount', a.amount, 'source', a.source, 'voided_at', a.voided_at, 'void_note', a.void_note, 'created_at', a.created_at)
                      order by a.created_at, i.invoice_number), '[]'::jsonb)
                    from public.so_payment_alloc a join public.so_invoice i on i.id = a.invoice_id
                    where a.payment_id = v.id),
    'targets', (select coalesce(jsonb_agg(jsonb_build_object(
                  'so_id', s.id, 'so_number', s.so_number, 'so_status', s.status, 'channel', s.channel,
                  'invoiced', exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id))
                  order by s.so_number), '[]'::jsonb)
                from public.so_payment_order o join public.so s on s.id = o.so_id
                where o.payment_id = v.id),
    'refund_credits', (select coalesce(jsonb_agg(jsonb_build_object(
                         'alloc_id', ca.id, 'credit_id', c.id, 'credit_number', c.credit_number, 'credit_status', c.status, 'credit_total', c.total,
                         'amount', ca.amount, 'source', ca.source, 'voided_at', ca.voided_at, 'void_note', ca.void_note, 'created_at', ca.created_at)
                         order by ca.created_at, c.credit_number), '[]'::jsonb)
                       from public.so_credit_alloc ca join public.so_credit c on c.id = ca.credit_id
                       where ca.refund_payment_id = v.id),
    'open_invoices', (select coalesce(jsonb_agg(jsonb_build_object(
                        'invoice_id', l.id, 'invoice_number', l.invoice_number, 'issued_on', l.issued_on, 'due_on', l.due_on, 'due_unknown', l.due_unknown,
                        'total', l.total, 'remaining', l.remaining, 'days_overdue', l.days_overdue, 'so_numbers', l.so_numbers,
                        'attached_from_this_payment', coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = v.id and a.invoice_id = l.id and a.voided_at is null), 0))
                        order by l.issued_on, l.invoice_number), '[]'::jsonb)
                      from public.so_invoice_list l
                      where l.is_open and l.bill_to_customer_id = v.customer_id and l.currency_id = v.currency_id),
    'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v.customer_id) b where b.currency_id = v.currency_id)
  )
  from public.so_payment_list v
  where v.id = p_payment_id;
$$;
comment on function public.so_payment_detail(uuid) is
  '⭐ 결제 한 건(so-pay-read-1 R2 · 2026-09-25) — jsonb 하나 · 읽기(stable · invoker) · 없는 id → null. payment(뷰 행) · allocations(붙임 전부 — 취소된 것은 voided_at · 화면이 가른다) · targets(대상 오더 · 상태 · invoiced = 살아 있는 인보이스가 있나) · refund_credits(환불을 갚은 크레딧 붙임 · void 포함) · open_invoices(같은 손님 · 같은 통화 · is_open · issued_on → 번호 순 · attached_from_this_payment — 손으로 붙이기 고르기용 · 0-6) · customer_balance(그 통화 행)';
revoke all on function public.so_payment_detail(uuid) from public, anon;
grant execute on function public.so_payment_detail(uuid) to authenticated;
