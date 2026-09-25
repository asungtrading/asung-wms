-- SO 인보이스 읽기 창구 셋 — 뷰 so_invoice_list · so_invoice_detail(p_invoice_id) · so_invoice_ar_summary(p_customer_id) (2026-09-25 UTC · 토론토 2026-09-25 오후)
-- 지시서 ~/asung/prompts/so-inv-read-1.md · 판정 회신 Caleb 2026-09-25(이견 0-1~0-8 · ⬜1~⬜6 전부) · 정본 §17(인보이스) · §18(결제) · §19(크레딧) · 화면 so-invoices.html 은 그리기만(대화 Claude)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 시험 적용 + 검증 ~/asung/prompts/so-inv-read-1-verify.sql(-v mig)
-- ⭐ 식은 다시 짜지 않는다 — 남은 금액 = so_invoice_remaining(id) · 손님 잔액 = so_customer_balance(id) (§1 · 20260925014413:118 · :132) · 뷰·RPC 는 그 둘을 부른다 · 쓰기 문 없음(ims_require_write 안 부른다)
-- ⭐ 선례 = 발주 읽기(20260916163806 머리 주석 · po_invoice_list 20260916210000:378 · po_detail 20260916190000:369): 목록 = 뷰(PostgREST 로 표처럼 · range · 검색 칸) · 상세 = RPC jsonb 하나 · 없는 id → SQL null
-- ⚠️ 권한(⬜4 · 0-6): 뷰 with (security_invoker = true) → 바탕 표 RLS(전부 select using true) 그대로 · ⚠️ Supabase 기본 권한이 뷰에 ALL 을 붙인다(po_invoice_list 실측 — authenticated 가 INSERT·UPDATE·DELETE·TRUNCATE 까지) ⇒ revoke all from anon, authenticated 뒤 grant select 만
--    RPC 둘 = language sql stable security invoker · revoke public, anon · grant execute authenticated
-- ⚠️ 붙임 합의 조건은 so_invoice_remaining 과 같아야 한다(§3 ③): 결제 붙임 = alloc.voided_at is null ∧ payment.status = 'active' · 크레딧 붙임 = alloc.voided_at is null ∧ credit.status = 'issued' — 어긋나면 paid + credited ≠ total − remaining
-- ⚠️ 기한 없는 인보이스(due_on null · 결제조건 없음 · due_date_unknown)는 days_overdue 0 + due_unknown true 로 가른다(0-3) · R3 는 no_due_* 로 따로 센다(버킷 current 에 넣지 않는다)
-- ⚠️ 재발행 사슬 칸은 없다(reissued_from 류 grep 0 · 0-1) — R2 history = 이 인보이스의 오더가 걸렸던 다른 인보이스 전부(so_invoice_order.so_id 로 유도)
-- ⚠️ 크레딧 둘(0-2): credits_applied = 이 인보이스에 「붙은」 so_credit_alloc(남은 금액을 줄인다) · credits_against = 이 인보이스를 원판매로 「되짚은」 so_credit(invoice_id · 남은 금액과 무관) — 한 크레딧이 둘 다일 수 있다
-- ⚠️ 성능(0-4 실측 · 101행 시험 · 2026-09-25): 뷰 전체 8.1ms · remaining > 0 거르기 14.0ms · search_text ilike 9.0ms — 행마다 so_invoice_remaining 을 부른다(전 행 계산) · 1만 장이면 1~2초 짐작(정본 ⬜) · pg_trgm 은 깔려 있지 않다(인덱스는 뒤에)
-- ⚠️ 시험 자료는 직접 insert(0-5 · 번호 79001~ · 실물 없는 손님 · 시퀀스 무접촉) — 이 방식이 읽기 창구 검증의 규칙이 될 수 있다(말만)

-- ═══ R1 so_invoice_list — 인보이스 한 장 = 한 행 ═══
create view public.so_invoice_list
  with (security_invoker = true) as
with ord as (
  select o.invoice_id,
         string_agg(o.so_number, ', ' order by o.so_number) filter (where o.cancelled_at is null)  as so_numbers,
         array_agg(o.so_id order by o.so_number)             filter (where o.cancelled_at is null)  as so_ids,
         count(*)                                             filter (where o.cancelled_at is null)  as order_count,
         case when count(distinct s.channel) filter (where o.cancelled_at is null) > 1 then 'mixed'
              else min(s.channel) filter (where o.cancelled_at is null) end                          as channel,
         string_agg(o.so_number || coalesce(' ' || s.ref, ''), ' ' order by o.so_number) filter (where o.cancelled_at is null) as order_text
  from public.so_invoice_order o
  join public.so s on s.id = o.so_id
  group by o.invoice_id
),
pay as (   -- 살아 있는 결제 붙임(so_invoice_remaining 과 같은 조건)
  select a.invoice_id, sum(a.amount) as paid
  from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
  where a.voided_at is null and p.status = 'active'
  group by a.invoice_id
),
cred as (  -- 살아 있는 크레딧 붙임(issued 크레딧만)
  select a.invoice_id, sum(a.amount) as credited
  from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id
  where a.invoice_id is not null and a.voided_at is null and c.status = 'issued'
  group by a.invoice_id
)
select i.id, i.invoice_number, i.status, i.issued_on, i.due_on, i.payment_term_name, i.currency_id, i.currency_code,
       i.bill_to_customer_id, i.bill_to_name, cu.name as customer_name,
       o.so_numbers, o.so_ids, coalesce(o.order_count, 0)::int as order_count, o.channel,
       i.lines_amount, i.order_discount_amount, i.charges_amount, i.tax_amount, i.total,
       i.deposit_applied, i.credit_applied, i.balance_forward, i.amount_due,
       coalesce(pay.paid, 0)       as paid,
       coalesce(cred.credited, 0)  as credited,
       r.remaining,
       (i.due_on is null)          as due_unknown,
       case when i.status = 'issued' and r.remaining > 0 and i.due_on is not null and i.due_on < public.ims_today()
            then (public.ims_today() - i.due_on) else 0 end::int as days_overdue,
       (i.status = 'issued' and r.remaining > 0) as is_open,
       i.cancelled_at, i.cancel_note, i.note, i.created_at,
       (i.invoice_number || ' ' || coalesce(i.bill_to_name, '') || ' ' || coalesce(cu.name, '') || ' ' || coalesce(o.order_text, '')) as search_text
from public.so_invoice i
left join public.customer cu on cu.id = i.bill_to_customer_id
left join ord o on o.invoice_id   = i.id
left join pay  on pay.invoice_id  = i.id
left join cred on cred.invoice_id = i.id
cross join lateral (select public.so_invoice_remaining(i.id) as remaining) r;   -- 읽기 함수(stable)를 lateral 에서 한 번만 — 쓰기 창구가 아니다
comment on view public.so_invoice_list is
  '⭐ 판매 인보이스 목록(so-inv-read-1 R1 · 2026-09-25) — 한 장 한 행 · PostgREST 로 표처럼(range · order · ilike) · security_invoker. 돈: paid = 살아 있는 결제 붙임 · credited = 살아 있는 크레딧 붙임(issued) · remaining = so_invoice_remaining(id)(식의 정본 · 취소는 0) · paid + credited = total − remaining(issued). days_overdue = remaining > 0 ∧ due_on < ims_today() 일 때 일수(0-3: due_on 없음은 0 + due_unknown) · is_open = issued ∧ remaining > 0 · so_numbers·so_ids·order_count·channel(섞이면 mixed)은 살아 있는 so_invoice_order 만 · search_text = 번호 · 청구처 · 손님 · 오더 번호 · 오더 ref(화면이 or() 에 조인 칸을 못 넣어 한 칸 · ⬜1 · pg_trgm 없음 · 1만 장 1~2초 짐작)';
revoke all on public.so_invoice_list from anon, authenticated, public;
grant select on public.so_invoice_list to authenticated;

-- ═══ R2 so_invoice_detail — 한 장을 jsonb 하나로(po_detail 선례 · 없는 id → null) ═══
create function public.so_invoice_detail(p_invoice_id uuid) returns jsonb
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
                   -- 결제의 남은 금액(0-8) — 식은 so_customer_balance 의 pay CTE 그대로 옮겼다(20260925014413_so_credit_c2.sql:146) · ⬜ 결제 화면 차례에 함수(so_payment_remaining)로 떼고 여기와 그 함수가 같은 것을 부른다
                   'payment_remaining', p.amount - coalesce((select sum(x.amount) from public.so_payment_alloc x where x.payment_id = p.id and x.voided_at is null), 0),
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

-- ═══ R3 so_invoice_ar_summary — 화면 머리의 미수 요약(통화별 · 버킷은 기한일 기준 · ⬜3) ═══
create function public.so_invoice_ar_summary(p_customer_id uuid default null) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with x as (
    select v.currency_id, v.currency_code, v.remaining, v.days_overdue, v.due_unknown
    from public.so_invoice_list v
    where v.is_open and (p_customer_id is null or v.bill_to_customer_id = p_customer_id)
  ),
  g as (
    select x.currency_id, x.currency_code,
           count(*)::int                                                   as open_count,
           coalesce(sum(x.remaining), 0)                                   as remaining_total,
           count(*) filter (where x.days_overdue > 0)                      as overdue_count,
           coalesce(sum(x.remaining) filter (where x.days_overdue > 0), 0) as overdue_total,
           count(*) filter (where x.due_unknown)                           as no_due_count,
           coalesce(sum(x.remaining) filter (where x.due_unknown), 0)      as no_due_total,
           jsonb_build_object(
             'current', jsonb_build_object('count', count(*) filter (where not x.due_unknown and x.days_overdue = 0),  'total', coalesce(sum(x.remaining) filter (where not x.due_unknown and x.days_overdue = 0), 0)),
             'd1_30',   jsonb_build_object('count', count(*) filter (where x.days_overdue between 1 and 30),          'total', coalesce(sum(x.remaining) filter (where x.days_overdue between 1 and 30), 0)),
             'd31_60',  jsonb_build_object('count', count(*) filter (where x.days_overdue between 31 and 60),         'total', coalesce(sum(x.remaining) filter (where x.days_overdue between 31 and 60), 0)),
             'd61_90',  jsonb_build_object('count', count(*) filter (where x.days_overdue between 61 and 90),         'total', coalesce(sum(x.remaining) filter (where x.days_overdue between 61 and 90), 0)),
             'd90_plus',jsonb_build_object('count', count(*) filter (where x.days_overdue > 90),                      'total', coalesce(sum(x.remaining) filter (where x.days_overdue > 90), 0))
           ) as buckets
    from x
    group by x.currency_id, x.currency_code
  )
  select jsonb_build_object('customer_id', p_customer_id, 'as_of', public.ims_today(),
                            'currencies', coalesce((select jsonb_agg(to_jsonb(g) order by g.currency_code) from g), '[]'::jsonb));
$$;
comment on function public.so_invoice_ar_summary(uuid) is
  '⭐ 미수 요약(so-inv-read-1 R3 · 2026-09-25) — 읽기(stable · invoker) · p_customer_id null 이면 전부 · 뷰 so_invoice_list 의 is_open(issued ∧ remaining > 0) 행만 · 통화별 한 행: open_count · remaining_total · overdue_count/total(days_overdue > 0) · no_due_count/total(기한 없음 · 0-3 · 버킷 밖) · buckets current(기한 전 · 기한 있음) · d1_30 · d31_60 · d61_90 · d90_plus(기한일 기준 · ⬜3) — current + 버킷 넷 + no_due = remaining_total';
revoke all on function public.so_invoice_ar_summary(uuid) from public, anon;
grant execute on function public.so_invoice_ar_summary(uuid) to authenticated;
