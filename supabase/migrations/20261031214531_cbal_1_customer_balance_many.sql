-- 20261031214531_cbal_1_customer_balance_many.sql — cbal-1 · 판정 912(Caleb 「A로 가자」 · 2026-10-31 저녁)
-- 손님 잔액을 여러 명 한 번에 읽는 창구 so_customer_balance_many(p_customer_ids uuid[])
--   · 손님 목록(customers.html cs v8 →)이 Credit owed · Money on account 칸과 그 정렬에 쓴다 — 기각 B(쪽마다 손님 수만큼 so_customer_balance 를 부름)
--   · 값의 정본은 그대로 so_customer_balance(마지막 정의 20260925205011:511 ~ 557 · prosrc md5 801f4408… — 검증 M0) — 식을 복사하지 않고 **그 함수를 lateral 로 부른다**(한 푼도 다를 수 없다)
--   · 반환 = 단일 창구의 칸 + 맨 앞 customer_id · 손님 × 통화마다 한 행 · 단일이 0 행이면 0 행(없는 id · 거래 없는 손님) · 같은 id 두 번 = 한 번
--   · p_customer_ids null = 「잔액 칸 중 하나라도 0 이 아닌 손님 전부」 — 후보를 싸게 좁힌 뒤 lateral:
--       후보 = 활성 payment 의 customer_id ∪ issued credit 의 customer_id ∪ issued invoice 의 bill_to_customer_id
--       (received · reserved_deposit 은 활성 payment 없이는 0 · owed_credit 은 issued credit 없이는 0 · open_invoices · _due 는 issued invoice 없이는 0 · available 은 그 셋에서 나온다
--        ⇒ 후보 밖 손님은 모든 칸이 0 이거나 0 행 — 전 손님 lateral 과 집합이 같다 · 검증 N1 이 전 손님 단일 호출과 대조)
--   · 배열 상한 500(넘으면 거부 · 「nothing was read」) · 빈 배열 = 0 행(null 모드가 아니다)
--   · 보안 · 권한 = 단일 창구와 같은 문: stable · security invoker · search_path public, pg_temp · revoke public, anon · grant authenticated
--       (단일은 직원 · 열쇠 검사가 없다 — so_payment · so_invoice · so_credit 의 select 정책이 authenticated using (true) 라 로그인이면 읽힌다 · 여기도 같게 · 문을 세우려면 둘을 함께)
--   · 청구처: 단일 창구가 인보이스는 bill_to_customer_id · 결제 · 크레딧은 customer_id(돈을 낸 · 크레딧을 가진 손님) 축으로 센다 — 매장 → 본사 되돌림은 없다(화면의 「본사로 청구되는 매장은 잔액이 본사에」 는
--       발행 · 이월이 돈을 청구처에 기록하는 관례(ar-2 · so_invoice_issue)에 기댄다) · 여기도 같게 — 매장 id 를 주면 매장 자신의 행(대개 0 행)
--   · 쓰기 0 · 표 · 정책 무변 · 되돌리기 = drop function public.so_customer_balance_many(uuid[])

create function public.so_customer_balance_many(p_customer_ids uuid[])
  returns table (customer_id uuid, currency_id uuid, currency_code text, received numeric, reserved_deposit numeric, owed_credit numeric, available numeric, open_invoices int, open_invoices_due numeric)
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  if p_customer_ids is not null and coalesce(array_length(p_customer_ids, 1), 0) > 500 then
    raise exception 'Too many customers in one call (% — the limit is 500) — nothing was read', array_length(p_customer_ids, 1);
  end if;
  if p_customer_ids is null then
    return query
      with cand as (
        select p.customer_id as id from public.so_payment p where p.status = 'active' and p.customer_id is not null
        union
        select c.customer_id from public.so_credit c where c.status = 'issued' and c.customer_id is not null
        union
        select i.bill_to_customer_id from public.so_invoice i where i.status = 'issued' and i.bill_to_customer_id is not null
      )
      select k.id, b.currency_id, b.currency_code, b.received, b.reserved_deposit, b.owed_credit, b.available, b.open_invoices, b.open_invoices_due
        from cand k cross join lateral public.so_customer_balance(k.id) b
       where b.received <> 0 or b.reserved_deposit <> 0 or b.owed_credit <> 0 or b.open_invoices <> 0 or b.open_invoices_due <> 0
       order by k.id, b.currency_code;
  else
    return query
      select k.id, b.currency_id, b.currency_code, b.received, b.reserved_deposit, b.owed_credit, b.available, b.open_invoices, b.open_invoices_due
        from (select distinct x as id from unnest(p_customer_ids) x where x is not null) k
        cross join lateral public.so_customer_balance(k.id) b
       order by k.id, b.currency_code;
  end if;
end $$;

revoke all on function public.so_customer_balance_many(uuid[]) from public, anon;
grant execute on function public.so_customer_balance_many(uuid[]) to authenticated;

comment on function public.so_customer_balance_many(uuid[]) is
  '⭐ cbal-1 판정 912: 손님 잔액 여러 명 한 번에 — 손님 × 통화 한 행(customer_id + so_customer_balance 의 여덟 칸) · 값은 so_customer_balance 를 lateral 로 부른 것(식 복사 없음 · 한 푼도 다르지 않다) · null = 잔액 칸 중 하나라도 0 이 아닌 손님 전부(후보 = 활성 결제 ∪ issued 크레딧 ∪ issued 인보이스 청구처) · 빈 배열 = 0 행 · 같은 id 두 번 = 한 번 · 상한 500 · 문 = 단일 창구와 같다(stable · invoker · authenticated) · 청구처 되돌림 없음(단일과 같다)';
