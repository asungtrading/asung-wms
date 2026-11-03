-- 20261103070000_so_inv_branch_1.sql — so-inv-branch-1: 인보이스 목록 뷰 so_invoice_list 에 브랜치(창고) 칸 셋을 끝에 더한다 (2026-11-03 · 판정 994)
-- [운영 · Asung-IMS] 적용은 Caleb · psql -1 -f + supabase migration repair --status applied 20261103070000 · db push 금지 · 토론토 07:00 전
--
-- 왜: Action Centre(manager-list.html) 「Unpaid at hand-over」 탭이 브랜치(All branches · Toronto · Edmonton)를 못 따른다 — 뷰에 창고 칸이 없어서(deferred 337 ① · so-module 3895 ⬜ · 3961 ⬜).
-- 판정 994(Caleb): 「돈 안 받고 넘긴 인보이스」 의 브랜치 = 물건을 내준 브랜치(그 인보이스의 오더 SO 의 창고) · 오더가 없는 인보이스(이월 · kind opening)는 손님의 기본 브랜치 · All branches 는 전부.
-- 이견 답(2026-11-03 · so-inv-branch-1 §0):
--   1 ㉠ 살아 있는 오더가 여럿이고 창고가 다르면 첫 SO(so_number 순)의 창고(실물 0 장 · so_invoice_issue 에 창고 가드 없음)
--   2 오더가 없으면 매장(store_customer_id)의 기본 브랜치 먼저 · 비면 청구처(bill_to_customer_id)의 — so_opening_load 의 받아 둔 돈 브랜치 규칙과 같다
--   3 둘 다 비면 null(All branches 에서만 보인다 · 열린 이월 307 장 중 비는 장 0)
--   4 끝에 더한다(create or replace view · 앞에 끼우면 안 된다) · security_invoker · 권한(authenticated SELECT 만) · comment 는 새 칸 글을 보태 다시
--   5 칸 꼴 warehouse_id uuid(= ref_warehouse.id · manager-list 의 whId · so.location_id · customer.default_location_id 와 같은 값) · warehouse_name text(= ref_warehouse.name) · warehouse_source text(so | store | bill_to | null — warehouse_id 가 null 이면 null)
--   6 화면(manager-list unpaidQuery 의 .eq("warehouse_id", whId) 한 줄 · 목록 · 배지 둘 다)은 대화 Claude 몫
-- 무엇: ① 뷰 재발행 — ar-2(20261027014202) 본문 그대로 + ord CTE 에 집계 둘(wh_id · wh_n) + lateral wh + ref_warehouse 조인 1 + 끝에 칸 셋 ② comment ③ 자기 검사
-- 무접촉: 옛 43 칸의 값 · 순서(검사 so_inv_branch_1_check.sql 이 옛 본문과 양방향 except 0) · 권한 · 의존 함수 8(so_invoice_detail 의 to_jsonb(v) 는 invoice 에 키 셋이 더해진다 — 더하기만) · 화면 · EF · qbo_* · so_invoice 표
-- 검증: supabase/tests/so_inv_branch_1_check.sql (begin → \i → 검증 → rollback)

-- ═══ 1) 뷰 so_invoice_list 재발행 — 20261027014202(ar-2) 본문 그대로 + 창고 칸 셋 끝에 ═══
create or replace view public.so_invoice_list
  with (security_invoker = true) as
with ord as (
  select o.invoice_id,
         string_agg(o.so_number, ', ' order by o.so_number) filter (where o.cancelled_at is null)  as so_numbers,
         array_agg(o.so_id order by o.so_number)             filter (where o.cancelled_at is null)  as so_ids,
         count(*)                                             filter (where o.cancelled_at is null)  as order_count,
         case when count(distinct s.channel) filter (where o.cancelled_at is null) > 1 then 'mixed'
              else min(s.channel) filter (where o.cancelled_at is null) end                          as channel,
         string_agg(o.so_number || coalesce(' ' || s.ref, ''), ' ' order by o.so_number) filter (where o.cancelled_at is null) as order_text,
         (array_agg(s.location_id order by o.so_number) filter (where o.cancelled_at is null))[1]   as wh_id,   -- so-inv-branch-1 판정 994 · 이견 1 ㉠: 첫 SO(so_number 순)의 창고
         count(distinct s.location_id) filter (where o.cancelled_at is null)                         as wh_n     -- so-inv-branch-1: 창고 가짓수(검사 · 나중 화면용 · 뷰 칸은 아님)
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
       (i.invoice_number || ' ' || coalesce(i.bill_to_name, '') || ' ' || coalesce(cu.name, '') || ' ' || coalesce(o.order_text, '')) as search_text,
       i.surcharge_amount,                                                                                                     -- surcharge-2b(끝에 — create or replace view 는 열을 끝에만 더할 수 있다)
       i.charges_discount_amount,                                                                                              -- fr-2 판정 352(끝에 — 같은 이유)
       i.kind, i.prior_settled, i.store_customer_id, st.name as store_name, i.legacy_sale_id, i.legacy_invoice_id,                    -- ar-2 판정 783(끝에 — 같은 이유 · so_invoice_detail 의 invoice 행이 이 뷰)
       wh.warehouse_id,                                                                                                        -- so-inv-branch-1 판정 994(끝에 — 같은 이유): 오더 있으면 첫 SO 의 창고 · 없으면 매장 → 청구처 기본 브랜치 · 둘 다 없으면 null
       w.name as warehouse_name,                                                                                               -- so-inv-branch-1: ref_warehouse.name(customer_review_list.default_location_name 과 같은 글자)
       case when wh.warehouse_id is null then null
            when coalesce(o.order_count, 0) > 0 then 'so'
            when st.default_location_id is not null then 'store'
            else 'bill_to' end as warehouse_source                                                                             -- so-inv-branch-1: 어디서 왔나 — so | store | bill_to | null(warehouse_id 가 null 이면 null)
from public.so_invoice i
left join public.customer cu on cu.id = i.bill_to_customer_id
left join public.customer st on st.id = i.store_customer_id                                                                       -- ar-2: 이월 인보이스의 매장(sale 은 null)
left join ord o on o.invoice_id   = i.id
left join pay  on pay.invoice_id  = i.id
left join cred on cred.invoice_id = i.id
cross join lateral (select public.so_invoice_remaining(i.id) as remaining) r    -- 읽기 함수(stable)를 lateral 에서 한 번만 — 쓰기 창구가 아니다
cross join lateral (select case when coalesce(o.order_count, 0) > 0 then o.wh_id
                                else coalesce(st.default_location_id, cu.default_location_id) end as warehouse_id) wh            -- so-inv-branch-1: 브랜치 식 한 곳(이름 · 출처가 같은 값을 본다)
left join public.ref_warehouse w on w.id = wh.warehouse_id;                                                                      -- so-inv-branch-1: 4 행 표 · 이름만

-- ═══ 2) comment — 옛 글 그대로 + 창고 칸 셋 ═══
comment on view public.so_invoice_list is
  '⭐ 판매 인보이스 목록(so-inv-read-1 R1 · 2026-09-25 · surcharge-2b 열 하나 끝에 · so-inv-branch-1 창고 칸 셋 끝에) — 한 장 한 행 · PostgREST 로 표처럼(range · order · ilike) · security_invoker. 돈: paid = 살아 있는 결제 붙임 · credited = 살아 있는 크레딧 붙임(issued) · remaining = so_invoice_remaining(id)(식의 정본 · 취소는 0) · paid + credited = total − remaining(issued) · ⭐ surcharge_amount(묶음 3 · 물건값과 따로 · total 에는 들어 있다) · days_overdue = remaining > 0 ∧ due_on < ims_today() 일 때 일수 · is_open = issued ∧ remaining > 0 · so_numbers·so_ids·order_count·channel 은 살아 있는 so_invoice_order 만 · search_text = 번호 · 청구처 · 손님 · 오더 번호 · 오더 ref · ⭐ warehouse_id · warehouse_name · warehouse_source(판정 994 · 2026-11-03): 오더 있으면 첫 SO(so_number 순)의 창고(so) · 없으면 매장 store_customer_id 의 기본 브랜치(store) · 비면 청구처의(bill_to) · 둘 다 없으면 null(All branches 에서만) — Action Centre Unpaid at hand-over 의 브랜치 거르기';

-- ═══ 3) 자기 검사 — 설계대로 안 섰으면 전체 되돌림 ═══
do $$
declare
  v_bad  text := '';
  v_cols text;
begin
  select string_agg(column_name || ':' || data_type, ',' order by ordinal_position) into v_cols
    from information_schema.columns where table_schema = 'public' and table_name = 'so_invoice_list' and ordinal_position > 43;
  if v_cols is distinct from 'warehouse_id:uuid,warehouse_name:text,warehouse_source:text' then v_bad := v_bad || format(' columns(got %s)', coalesce(v_cols, '(none)')); end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_invoice_list') <> 46 then v_bad := v_bad || ' column_count'; end if;
  if (select reloptions::text from pg_class where relname = 'so_invoice_list' and relnamespace = 'public'::regnamespace) not like '%security_invoker=true%' then v_bad := v_bad || ' invoker'; end if;
  if not has_table_privilege('authenticated', 'public.so_invoice_list', 'select') or has_table_privilege('authenticated', 'public.so_invoice_list', 'insert') or has_table_privilege('anon', 'public.so_invoice_list', 'select') then v_bad := v_bad || ' grants'; end if;
  if exists (select 1 from public.so_invoice_list where (warehouse_id is null) <> (warehouse_source is null) or (warehouse_id is null) <> (warehouse_name is null)) then v_bad := v_bad || ' null_pairing'; end if;
  if exists (select 1 from public.so_invoice_list where warehouse_source not in ('so', 'store', 'bill_to')) then v_bad := v_bad || ' source_values'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM994', message = format('STOP - so-inv-branch-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
