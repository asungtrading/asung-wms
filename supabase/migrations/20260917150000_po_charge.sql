-- ─────────────────────────────────────────────────────────────
-- ⑤ 비용 문서(po_charge) 뒷단 — 목록 뷰 · 상세 · 만들기 · 배분 편집 셋 · 다시 비례 · 확정 · 취소/삭제 확장 (테스트 DB Asung-IMS · 2026-09-17)
--   표 둘(po_charge · po_charge_alloc)과 돈 뷰 po_charge_money 는 이미 서 있다(153313 · 190000) — 이 파일은 표를 만들지 않는다(칸 하나 cancelled_by 만 더한다)
--
-- 정본: docs/design/po-module.md §11-f(별도 문서 · 배분 두 단계 · 잔돈은 가장 큰 발주 · 동점은 발주번호 순) · §11-e(금액 비례의 원형) · §11-h(결제가 비용 문서도 가리킨다) · §13-h(미리 보기 p_commit · 확정의 뜻)
-- 선례: 20260916200000 po_invoice_create(미리 보기 두 단계 · 머리 원천 · 번호 중복) · po_invoice_confirm(확정 검사 · Reopen 은 결제 있으면 거부) · po_invoice_list · po_invoice_detail ·
--       20260917100000 po_doc_cancel · po_doc_delete(⚠️ 적용된 마이그레이션 · 여기서 create or replace 로 다시 내며 p_target 에 'charge' 를 더한다 — 그 파일 12행이 적어 둔 자리)
-- 지시서: ~/asung/prompts/po-charge.md · 검토 이견 1~16(2026-09-17 · 이 파일은 권고안 그대로 — 뒤집히면 해당 절만 고친다)
-- ❌ 범위 밖 — 결제 만들기(다음 차수 · 한 결제는 한 통화) · 원가 배분(발주 → 라인 · 원장 차수 §11-j) · 화면(대화 Claude)
--
-- ═══════════════════════════════════════════════════════════════
-- ⭐⭐ 화면(asung-ims · 대화 Claude)이 부르는 모양 — 여기 한 곳만 보고 쓴다 · supabase-js v2 · 예외는 error.message(HTTP 400) · 화면은 그 문장을 그대로 띄운다
-- ═══════════════════════════════════════════════════════════════
--   목록   sb.from("po_charge_list").select("*", { count:"exact" }).order("charge_date", { ascending:false }).range(a, b)
--          .ilike 검색 칸: charge_number · po_numbers(발주 번호로 찾기) · supplier_name · description   ·   필터 칸: status · kind · supplier_id
--          칸: id · charge_number · charge_date · due_date · kind · description · status · supplier_id · supplier_name · currency_id · currency_code · exchange_rate · total_amount ·
--              paid · unpaid · alloc_sum · unallocated(po_charge_money 그대로) · po_count · po_numbers · confirmed_at · cancelled_at · note · created_at · updated_at
--   상세   sb.rpc("po_charge_detail", { p_charge_id })                      → 없는 id 는 null
--          { header{ id, charge_number, charge_date, due_date, kind, description, status, supplier_id, supplier_name, currency_id, currency_code, exchange_rate, total_amount,
--                    created_by_name, confirmed_by_name, cancelled_by_name, confirmed_at, cancelled_at, note, created_at, updated_at },
--            money{ total_amount, paid, unpaid, alloc_sum, unallocated },
--            allocs[]{ alloc_id, po_id, po_number, po_status, amount, note, base_amount(그 발주의 라인 금액 합 · 비례의 기준), other_charges(그 발주에 붙은 다른 비용 배분 합 · 취소 제외) },
--            payments[]{ alloc_id, payment_id, paid_on, reference, alloc_amount, payment_amount, discount_taken, currency_code, account_code, account_name, paid_by_name },
--            warnings[] : unallocated · no_allocs · total_amount_zero · alloc_on_cancelled_po }
--   만들기 미리 보기  sb.rpc("po_charge_create", { p_supplier_id, p_charge_number, p_charge_date, p_kind, p_total_amount, p_currency_id, p_due_date, p_description, p_note, p_po_ids:[…], p_commit:false })
--          만들기        같은 인자 · p_commit:true
--          → { committed, charge_id(commit 때만 · 미리 보기는 null), charge_number, charge_date, kind, supplier_id, supplier_name, currency_id, currency_code, total_amount,
--              alloc_sum, unallocated, allocs[]{ po_id, po_number, po_status, base_amount, amount, inserted }, warnings[] }
--          warnings: charge_number_exists(미리 보기만 · commit 은 거부) · no_base_amount(발주 라인 금액이 전부 0 → 균등) · alloc_on_cancelled_po · total_amount_zero
--          ⚠️ p_kind 는 'freight' | 'duty' | 'brokerage' | 'other'(CHECK) · p_charge_date 를 안 주면 오늘 · p_total_amount 는 필수(우리가 넣는 숫자 · 계산값이 없다) · ⭐ p_currency_id 는 필수(없으면 거부 · 폴백 없음 — 화면이 필수 입력으로 막는다)
--   배분   sb.rpc("po_charge_alloc_add",    { p_charge_id, p_po_id, p_amount })   → { alloc_id, charge_id, charge_number, po_id, po_number, po_status, amount, alloc_sum, unallocated, warnings[] }
--          sb.rpc("po_charge_alloc_update", { p_alloc_id, p_amount })             → { alloc_id, charge_id, charge_number, po_number, amount_before, amount, alloc_sum, unallocated }   ⭐ 다른 줄은 안 움직인다
--          sb.rpc("po_charge_alloc_delete", { p_alloc_id })                        → { deleted:true, alloc_id, charge_id, charge_number, po_number, amount_removed, alloc_sum, unallocated }
--          sb.rpc("po_charge_alloc_spread", { p_charge_id })                       → { charge_id, charge_number, total_amount, alloc_sum, unallocated(0 이어야), allocs[]{ alloc_id, po_id, po_number, base_amount, amount_before, amount }, warnings[] }
--          ⚠️ 넷 다 draft 만 — 그 밖은 「… allocations can be edited only while draft — nothing was saved」 · spread 는 **사람이 누를 때만** 부른다(어떤 저장도 자동으로 부르지 않는다)
--   확정   sb.rpc("po_charge_confirm", { p_charge_id })                 → { id, charge_number, status:'confirmed', confirmed_at, money{…}, warnings[] }   ⚠️ unallocated ≠ 0 이면 거부(경고 아님)
--   되돌리기 sb.rpc("po_charge_confirm", { p_charge_id, p_confirm:false }) → status 'draft' · ⚠️ 결제가 붙어 있으면 거부(「… has payments applied (EFT-20260916-02 2547.37) — cannot reopen …」)
--   취소   sb.rpc("po_doc_cancel", { p_target:"charge", p_id })                → { target:'charge', id, charge_number, status, cancelled_at, confirmed_at, restored, attached{ pos }, warnings[] }   warnings: has_allocs · cancelled_from_draft
--   되돌리기 sb.rpc("po_doc_cancel", { p_target:"charge", p_id, p_cancel:false })
--   삭제   sb.rpc("po_doc_delete", { p_target:"charge", p_id })                → { deleted:true, target:'charge', id, charge_number, status_before, allocs_deleted }   ⚠️ confirmed_at 이 있으면 거부(같은 문장 모양)
--   머리 칸(due_date · description · note · 총액 · 날짜) 은 화면이 PostgREST 로 쓴다(인보이스 saveHead 선례) — ⚠️ draft 에서만 입력칸을 연다(이견 10 · 뒷단 잠금은 다음 차수)
--   버튼 노출: Delete = confirmed_at null · Cancel = cancelled 아닌 것 · Restore = cancelled 만 · Confirm = draft 이고 unallocated = 0 · Reopen = confirmed 이고 paid = 0 · 배분 편집·Spread = draft 만
-- ═══════════════════════════════════════════════════════════════
--
-- ⭐ 확정된 설계(Caleb 2026-09-17 · 지시서 §1) 와 이 파일의 대응
--   ① 만드는 자리   비용 화면에서 새로(청구서가 먼저 손에 있다) · PO 상세 진입점은 p_po_ids 에 그 발주 하나를 담아 부르는 것 — 뒷단은 같다
--   ② 확정          인보이스와 같게 잠근다(배분 편집 넷이 draft 만 받는다) · Reopen 은 결제 있으면 거부. ⚠️ 비용은 서는 순간 미지급이다(po_charge_money.unpaid 는 status 를 안 본다) — 확정은 「돈이 생긴다」가 아니라 「이 배분으로 원가에 얹겠다」는 선언
--   ③ 취소·삭제     po_doc_cancel / po_doc_delete 에 'charge' · 판정 축 그대로(삭제는 confirmed_at null 만 · 취소는 결제 있으면 거부) · 배분 줄은 CASCADE · allocs_deleted 반환
--   ④ 배분 편집     ⭐⭐ 고친 줄만 바뀐다 — update 문이 그 한 행만 건드린다. 합이 총액과 안 맞는 중간 상태가 정상(unallocated 가 그 값) · 다시 비례는 po_charge_alloc_spread 를 사람이 누를 때만
--   ⑤ 확정 전 검사  unallocated ≠ 0 ⇒ **거부** — 인보이스 diff 는 경고였다(공급처 총액이 정본 · 우리 계산은 대조값). 비용 배분은 양쪽 다 우리가 넣는 숫자라 안 맞으면 덜 입력한 것 · 배분 0줄 ⇒ 거부 · total 0 ⇒ 경고 · 취소된 발주에 배분 ⇒ 경고
--   ⑥ 비례 규칙     한 곳(po_charge_alloc_propose) — 기준은 발주의 라인 금액 합 = sum(round(qty_ea × unit_price, 2)) (po_list.subtotal 과 같은 식 · 할인 전) · 줄마다 round(총액 × 기준/합, 2) · 잔돈(총액 − 줄 합)은 기준이 가장 큰 발주 · 동점은 발주번호 순 · 기준이 전부 0 이면 균등 + no_base_amount
--
-- ⭐ 관례(181719 · 200000 · 100000 그대로) — plpgsql · volatile(쓰기) / sql stable(읽기) · security invoker · set search_path = public, pg_temp · 예외는 「… — nothing was saved」 · array_append(⚠️ text[] || 리터럴 금지 · 13-e ①) ·
--   만든 사람·확정한 사람·취소한 사람은 auth.uid() → ims_staff.id 서버 유도 · 돈의 식은 po_charge_money 만(여기서 다시 안 쓴다) · 반올림 2자리 · revoke public/anon + grant authenticated · 트리거 없음 · advisory lock 없음(채번이 없다 · 이견 13)
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS · --db-url 이 보이면 테스트)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① po_charge.cancelled_by — po · po_invoice 와 같은 결(100000 이 둘에만 더했다 · 이견 12) ═══
alter table public.po_charge
  add column if not exists cancelled_by uuid references public.ims_staff (id) on delete no action;
comment on column public.po_charge.cancelled_by is '취소한 사람 → ims_staff(id) · po_doc_cancel(p_target charge) 이 auth.uid() 로 유도해 넣는다 · 되돌리면 cancelled_at 과 함께 비운다. 2026-09-17';

-- ═══ ② po_charge_alloc_propose(p_total, p_po_ids) — ⑥ 비례 규칙 한 곳 (만들기 · 다시 비례가 같이 쓴다) ═══
-- 기준 = 발주의 라인 금액 합(할인 전 · po_list.subtotal 과 같은 식) · 줄마다 round(총액 × 기준/합, 2) · 잔돈은 기준이 가장 큰 발주(동점 발주번호 순) · 기준 합이 0 이면 균등(잔돈은 발주번호 첫째)
-- ⚠️ 없는 po id 는 조용히 빠진다 — 부르는 쪽이 먼저 존재를 검사한다(po_charge_create 가 한다)
create function public.po_charge_alloc_propose(p_total numeric, p_po_ids uuid[])
returns table (po_id uuid, po_number text, po_status text, base_amount numeric, amount numeric)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with ids as (
    select distinct u as po_id from unnest(coalesce(p_po_ids, '{}'::uuid[])) u
  ),
  b as (
    select i.po_id, x.po_number, x.status,
           coalesce((select sum(round(l.qty_ea * l.unit_price, 2)) from public.po_line l where l.po_id = i.po_id), 0) as base
    from ids i join public.po x on x.id = i.po_id
  ),
  s as (
    select coalesce(sum(base), 0) as sum_base, count(*) as n from b
  ),
  a as (
    select b.po_id, b.po_number, b.status, b.base,
           case when s.sum_base <> 0 then round(p_total * b.base / s.sum_base, 2)
                else round(p_total / s.n, 2) end as amt
    from b cross join s
  ),
  t as (
    select coalesce(sum(amt), 0) as sum_amt from a
  ),
  w as (
    select a.po_id from a order by a.base desc, a.po_number asc limit 1          -- 잔돈 받는 발주 · 결정론적
  )
  select a.po_id, a.po_number, a.status, a.base,
         a.amt + case when a.po_id = w.po_id then p_total - t.sum_amt else 0 end
  from a cross join t cross join w
  order by a.po_number;
$$;
comment on function public.po_charge_alloc_propose(numeric, uuid[]) is '⑤ 비용 배분 제안 — §11-f ① 규칙 한 곳. 기준 = 발주 라인 금액 합 sum(round(qty_ea×unit_price,2))(할인 전 · po_list.subtotal 과 같은 식) · 줄 = round(총액×기준/합, 2) · 잔돈 = 기준이 가장 큰 발주(동점은 발주번호 순) · 기준 합 0 이면 균등(부르는 쪽이 no_base_amount 경고). 없는 id 는 빠진다(부르는 쪽이 검사). po_charge_create · po_charge_alloc_spread 가 쓴다. 2026-09-17';
revoke all on function public.po_charge_alloc_propose(numeric, uuid[]) from public, anon;
grant execute on function public.po_charge_alloc_propose(numeric, uuid[]) to authenticated;

-- ═══ ③ 뷰 po_charge_list — po_invoice_list 와 같은 모양 · 배분 없는 청구서도 보인다(left join) ═══
create view public.po_charge_list
  with (security_invoker = true) as
with pos as (
  select a.po_charge_id,
         count(*)::int                                                  as po_count,
         string_agg(x.po_number, ' ' order by x.po_number)              as po_numbers
  from public.po_charge_alloc a
  join public.po x on x.id = a.po_id
  group by a.po_charge_id
)
select
  c.id, c.charge_number, c.charge_date, c.due_date, c.kind, c.description, c.status,
  c.supplier_id, s.name as supplier_name,
  c.currency_id, cur.code as currency_code, c.exchange_rate,
  c.total_amount,
  m.paid, m.unpaid, m.alloc_sum, m.unallocated,                          -- po_charge_money 그대로(식 없음)
  coalesce(pos.po_count, 0) as po_count,
  pos.po_numbers,                                                        -- 발주 번호로 청구서를 찾는다(.ilike)
  c.confirmed_at, c.cancelled_at, c.note, c.created_at, c.updated_at
from public.po_charge c
join public.po_charge_money m on m.id = c.id
join public.supplier s on s.id = c.supplier_id
join public.ref_currency cur on cur.id = c.currency_id
left join pos on pos.po_charge_id = c.id;

comment on view public.po_charge_list is '⑤ 비용 청구서 목록 — PostgREST 로 표처럼(§10-j 3-a · po_invoice_list 와 같은 모양). 돈은 po_charge_money(paid · unpaid · alloc_sum · unallocated · 식 없음) · po_count · po_numbers = 배분이 걸린 발주 번호 모음(검색 .ilike). 배분 없는 청구서도 보인다(left join · unallocated = 총액). security_invoker. 정본 po-module §11-f · 2026-09-17';
revoke all on public.po_charge_list from anon;
grant select on public.po_charge_list to authenticated;

-- ═══ ④ po_charge_detail(p_charge_id) — 한 장을 깊게 (po_invoice_detail 선례) ═══
create function public.po_charge_detail(p_charge_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with c as (
  select * from public.po_charge where id = p_charge_id
),
m as (
  select * from public.po_charge_money where id = p_charge_id
),
al as (
  select a.id as alloc_id, a.po_id, x.po_number, x.status as po_status, a.amount, a.note,
         coalesce((select sum(round(l.qty_ea * l.unit_price, 2)) from public.po_line l where l.po_id = a.po_id), 0) as base_amount,       -- 비례의 기준(할인 전)
         coalesce((select sum(a2.amount) from public.po_charge_alloc a2 join public.po_charge c2 on c2.id = a2.po_charge_id
                    where a2.po_id = a.po_id and a2.po_charge_id <> p_charge_id and c2.status <> 'cancelled'), 0) as other_charges       -- 그 발주에 이미 붙은 다른 비용
  from public.po_charge_alloc a
  join public.po x on x.id = a.po_id
  where a.po_charge_id = p_charge_id
),
pay as (
  select pa.id as alloc_id, pa.amount as alloc_amount, pm.id as payment_id, pm.paid_on, pm.reference, pm.amount as payment_amount, pm.discount_taken,
         cur.code as currency_code, acc.code as account_code, acc.name as account_name, st.name as paid_by_name
  from public.po_payment_alloc pa
  join public.po_payment pm on pm.id = pa.po_payment_id
  join public.ref_currency cur on cur.id = pm.currency_id
  left join public.ref_account acc on acc.id = pm.account_id
  left join public.ims_staff st on st.id = pm.paid_by
  where pa.po_charge_id = p_charge_id
)
select case when not exists (select 1 from c) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', c.id, 'charge_number', c.charge_number, 'charge_date', c.charge_date, 'due_date', c.due_date, 'kind', c.kind, 'description', c.description, 'status', c.status,
      'supplier_id', c.supplier_id, 'supplier_name', s.name,
      'currency_id', c.currency_id, 'currency_code', cur.code, 'exchange_rate', c.exchange_rate,
      'total_amount', c.total_amount,
      'created_by_name', cb.name, 'confirmed_by_name', fb.name, 'cancelled_by_name', xb.name,
      'confirmed_at', c.confirmed_at, 'cancelled_at', c.cancelled_at, 'note', c.note, 'created_at', c.created_at, 'updated_at', c.updated_at)
    from c
    join public.supplier s on s.id = c.supplier_id
    join public.ref_currency cur on cur.id = c.currency_id
    left join public.ims_staff cb on cb.id = c.created_by
    left join public.ims_staff fb on fb.id = c.confirmed_by
    left join public.ims_staff xb on xb.id = c.cancelled_by
  ),
  'money', (
    select jsonb_build_object('total_amount', m.total_amount, 'paid', m.paid, 'unpaid', m.unpaid, 'alloc_sum', m.alloc_sum, 'unallocated', m.unallocated) from m
  ),
  'allocs', coalesce((
    select jsonb_agg(jsonb_build_object('alloc_id', alloc_id, 'po_id', po_id, 'po_number', po_number, 'po_status', po_status, 'amount', amount, 'note', note,
                                        'base_amount', base_amount, 'other_charges', other_charges) order by po_number)
    from al), '[]'::jsonb),
  'payments', coalesce((
    select jsonb_agg(jsonb_build_object('alloc_id', alloc_id, 'payment_id', payment_id, 'paid_on', paid_on, 'reference', reference, 'alloc_amount', alloc_amount,
                                        'payment_amount', payment_amount, 'discount_taken', discount_taken, 'currency_code', currency_code,
                                        'account_code', account_code, 'account_name', account_name, 'paid_by_name', paid_by_name)
      order by paid_on, reference)
    from pay), '[]'::jsonb),
  'warnings', (
    select coalesce(jsonb_agg(w), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when m.unallocated <> 0 then 'unallocated' end,
        case when not exists (select 1 from al) then 'no_allocs' end,
        case when c.total_amount = 0 then 'total_amount_zero' end,
        case when exists (select 1 from al where al.po_status = 'cancelled') then 'alloc_on_cancelled_po' end
      ], null)) as w
      from c cross join m) t
  )
) end;
$$;
comment on function public.po_charge_detail(uuid) is '⑤ 비용 청구서 상세 — 한 장을 깊게(charges.html). header · money(po_charge_money 그대로) · allocs[](줄마다 base_amount = 발주 라인 금액 합 · other_charges = 그 발주에 붙은 다른 비용 합(취소 제외) — 사람이 배분을 고치는 판단의 재료) · payments[] · warnings[](unallocated · no_allocs · total_amount_zero · alloc_on_cancelled_po). 없는 id → null. 2026-09-17';
revoke all on function public.po_charge_detail(uuid) from public, anon;
grant execute on function public.po_charge_detail(uuid) to authenticated;

-- ═══ ⑤ po_charge_create — 미리 보기(p_commit=false) · 만들기 (po_invoice_create 선례) ═══
create function public.po_charge_create(
  p_supplier_id   uuid,                        -- 경비처(CBSA · BBE · Showtime …) — 발주처가 아니다
  p_charge_number text,                        -- 청구서 번호 · unique (supplier_id, charge_number)
  p_charge_date   date,                        -- 안 주면 오늘
  p_kind          text,                        -- freight | duty | brokerage | other
  p_total_amount  numeric,                     -- ⭐ 필수 · 우리가 넣는 숫자(계산값이 없다) · 정정은 음수 가능
  p_currency_id   uuid    default null,        -- ⭐ 필수(null 이면 거부 · 폴백 없음 · 이견 5 뒤집음) — 청구서는 자기 통화로 오고 비용처는 건마다 통화가 다를 수 있어 마스터 값이 그 청구서의 통화라는 보장이 없다 · 틀려도 결제 단계까지 조용히 간다. default null 은 인자 순서(뒤에 default 가 있다) 때문이지 선택이라는 뜻이 아니다
  p_due_date      date    default null,
  p_description   text    default null,
  p_note          text    default null,
  p_po_ids        uuid[]  default '{}',        -- 처음 담을 발주(빈 배열 허용) · ⑥ 규칙으로 배분 제안
  p_commit        boolean default false        -- false = 미리 보기(넣지 않는다)
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_sup       public.supplier%rowtype;
  v_num       text;
  v_cur       uuid;
  v_cur_code  text;
  v_exists    int;
  v_missing   int;
  v_chg_id    uuid;
  v_allocs    jsonb := '[]'::jsonb;
  v_sum       numeric := 0;
  v_base_sum  numeric := 0;
  v_n         int := 0;
  v_warn      text[] := '{}';
  r           record;
begin
  select * into v_sup from public.supplier where id = p_supplier_id;
  if not found then raise exception 'Supplier % not found — nothing was saved', p_supplier_id; end if;

  v_num := nullif(regexp_replace(coalesce(p_charge_number, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
  if v_num is null then raise exception 'Charge number is required — it is the supplier''s document number — nothing was saved'; end if;
  if p_kind is null or p_kind not in ('freight', 'duty', 'brokerage', 'other') then
    raise exception 'p_kind must be freight, duty, brokerage or other — nothing was saved';
  end if;
  if p_total_amount is null then raise exception 'Total amount is required — nothing was saved'; end if;

  -- 통화 — 사람이 고른다 · 폴백 없음(Caleb 2026-09-17 · 이견 5 뒤집음): 비용처는 건마다 통화가 다를 수 있어 공급처 마스터 값이 이 청구서의 통화라는 보장이 없고, 틀리면 결제 단계까지 조용히 간다
  if p_currency_id is null then raise exception 'Currency is required — nothing was saved'; end if;
  v_cur := p_currency_id;
  select c.code into v_cur_code from public.ref_currency c where c.id = v_cur;
  if v_cur_code is null then raise exception 'Currency % not found — nothing was saved', v_cur; end if;

  -- 번호 중복 — 미리 보기는 경고 · commit 은 읽을 문장으로 거부
  select count(*) into v_exists from public.po_charge where supplier_id = p_supplier_id and charge_number = v_num;
  if v_exists > 0 then
    if p_commit then raise exception 'Charge % already exists for % — nothing was saved', v_num, v_sup.name; end if;
    v_warn := array_append(v_warn, 'charge_number_exists');
  end if;
  if p_total_amount = 0 then v_warn := array_append(v_warn, 'total_amount_zero'); end if;

  -- 발주 존재 검사 — 제안 함수는 없는 id 를 조용히 빠뜨리므로 여기서 먼저
  select count(*) into v_missing from unnest(coalesce(p_po_ids, '{}'::uuid[])) u where not exists (select 1 from public.po x where x.id = u);
  if v_missing > 0 then raise exception '% of the given PO id(s) do not exist — nothing was saved', v_missing; end if;

  -- commit: 머리 한 행(만든 사람 서버 유도)
  if p_commit then
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
    insert into public.po_charge (supplier_id, charge_number, charge_date, due_date, kind, description, currency_id, total_amount, status, created_by, note)
    values (p_supplier_id, v_num, coalesce(p_charge_date, current_date), p_due_date, p_kind, p_description, v_cur, p_total_amount, 'draft', v_staff, p_note)
    returning id into v_chg_id;
  end if;

  -- 배분 제안(⑥ 규칙 한 곳) — 미리 보기는 계산만 · commit 은 박는다
  for r in select * from public.po_charge_alloc_propose(p_total_amount, p_po_ids) loop
    v_n := v_n + 1; v_sum := v_sum + r.amount; v_base_sum := v_base_sum + r.base_amount;
    if r.po_status = 'cancelled' and not ('alloc_on_cancelled_po' = any(v_warn)) then v_warn := array_append(v_warn, 'alloc_on_cancelled_po'); end if;
    if p_commit then
      insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (v_chg_id, r.po_id, r.amount);
    end if;
    v_allocs := v_allocs || jsonb_build_object('po_id', r.po_id, 'po_number', r.po_number, 'po_status', r.po_status, 'base_amount', r.base_amount, 'amount', r.amount, 'inserted', p_commit);
  end loop;
  if v_n > 0 and v_base_sum = 0 then v_warn := array_append(v_warn, 'no_base_amount'); end if;   -- 라인 금액이 전부 0 → 균등으로 나눴다

  return jsonb_build_object(
    'committed', p_commit, 'charge_id', v_chg_id, 'charge_number', v_num, 'charge_date', coalesce(p_charge_date, current_date), 'kind', p_kind,
    'supplier_id', p_supplier_id, 'supplier_name', v_sup.name, 'currency_id', v_cur, 'currency_code', v_cur_code,
    'total_amount', p_total_amount, 'alloc_sum', v_sum, 'unallocated', p_total_amount - v_sum,
    'allocs', v_allocs, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Charge % already exists for % — nothing was saved', v_num, coalesce(v_sup.name, 'this supplier');
end;
$$;
comment on function public.po_charge_create(uuid, text, date, text, numeric, uuid, date, text, text, uuid[], boolean) is '⑤ 비용 청구서 초안 만들기(미리 보기 = 같은 모양 · p_commit). 공급처는 경비처 · 번호 필수(unique (supplier, number) · 미리 보기 경고 · commit 거부) · kind CHECK 넷 · 총액 필수(우리 숫자) · 통화 필수(폴백 없음 — 비용처는 건마다 통화가 다를 수 있다) · p_po_ids 로 배분 제안(po_charge_alloc_propose · 금액 비례 · 잔돈 가장 큰 발주 · 동점 발주번호 · 기준 0 이면 균등 + no_base_amount) · created_by 서버 유도. 정본 po-module §11-f · 2026-09-17';
revoke all on function public.po_charge_create(uuid, text, date, text, numeric, uuid, date, text, text, uuid[], boolean) from public, anon;
grant execute on function public.po_charge_create(uuid, text, date, text, numeric, uuid, date, text, text, uuid[], boolean) to authenticated;

-- ═══ ⑥ 배분 편집 셋 — draft 만 · ⭐ 고친 줄만 바뀐다 (RPC 인 이유: 저장 전에 부모 문서의 status 를 봐야 한다) ═══
create function public.po_charge_alloc_add(p_charge_id uuid, p_po_id uuid, p_amount numeric default 0) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_chg  public.po_charge%rowtype;
  v_po   public.po%rowtype;
  v_id   uuid;
  v_m    record;
  v_warn text[] := '{}';
begin
  select * into v_chg from public.po_charge where id = p_charge_id;
  if not found then raise exception 'Charge % not found — nothing was saved', p_charge_id; end if;
  if v_chg.status <> 'draft' then
    raise exception 'Charge % is % — allocations can be edited only while draft — nothing was saved', v_chg.charge_number, v_chg.status;
  end if;
  select * into v_po from public.po where id = p_po_id;
  if not found then raise exception 'PO % not found — nothing was saved', p_po_id; end if;
  if exists (select 1 from public.po_charge_alloc where po_charge_id = p_charge_id and po_id = p_po_id) then
    raise exception 'PO % is already on charge % — edit that line instead — nothing was saved', v_po.po_number, v_chg.charge_number;
  end if;
  if v_po.status = 'cancelled' then v_warn := array_append(v_warn, 'alloc_on_cancelled_po'); end if;

  insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (p_charge_id, p_po_id, coalesce(p_amount, 0)) returning id into v_id;
  select * into v_m from public.po_charge_money where id = p_charge_id;
  return jsonb_build_object('alloc_id', v_id, 'charge_id', v_chg.id, 'charge_number', v_chg.charge_number, 'po_id', v_po.id, 'po_number', v_po.po_number, 'po_status', v_po.status,
                            'amount', coalesce(p_amount, 0), 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_charge_alloc_add(uuid, uuid, numeric) is '⑤ 비용 배분 줄 더하기 — draft 만 · 같은 발주 중복 거부(unique) · 취소된 발주는 경고 alloc_on_cancelled_po · 다른 줄은 안 건드린다 · 갱신 뒤 alloc_sum·unallocated 를 함께 준다. 2026-09-17';

create function public.po_charge_alloc_update(p_alloc_id uuid, p_amount numeric) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_al   public.po_charge_alloc%rowtype;
  v_chg  public.po_charge%rowtype;
  v_pon  text;
  v_m    record;
begin
  if p_amount is null then raise exception 'p_amount is required — nothing was saved'; end if;
  select * into v_al from public.po_charge_alloc where id = p_alloc_id;
  if not found then raise exception 'Allocation line % not found — nothing was saved', p_alloc_id; end if;
  select * into v_chg from public.po_charge where id = v_al.po_charge_id;
  if v_chg.status <> 'draft' then
    raise exception 'Charge % is % — allocations can be edited only while draft — nothing was saved', v_chg.charge_number, v_chg.status;
  end if;
  select po_number into v_pon from public.po where id = v_al.po_id;

  update public.po_charge_alloc set amount = p_amount where id = p_alloc_id;     -- ⭐ 이 한 줄만 — 나머지는 저절로 움직이지 않는다(④)
  select * into v_m from public.po_charge_money where id = v_chg.id;
  return jsonb_build_object('alloc_id', v_al.id, 'charge_id', v_chg.id, 'charge_number', v_chg.charge_number, 'po_number', v_pon,
                            'amount_before', v_al.amount, 'amount', p_amount, 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated);
end;
$$;
comment on function public.po_charge_alloc_update(uuid, numeric) is '⑤ 비용 배분 줄 금액 고치기 — draft 만 · ⭐⭐ 이 줄만 바뀐다(나머지를 다시 비례로 나누지 않는다 — 사람이 확인한 칸이 저절로 바뀌면 「박아 둔다」와 반대) · 합이 총액과 안 맞는 중간 상태가 정상(unallocated) · 다시 비례는 po_charge_alloc_spread. 2026-09-17';

create function public.po_charge_alloc_delete(p_alloc_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_al   public.po_charge_alloc%rowtype;
  v_chg  public.po_charge%rowtype;
  v_pon  text;
  v_m    record;
begin
  select * into v_al from public.po_charge_alloc where id = p_alloc_id;
  if not found then raise exception 'Allocation line % not found — nothing was deleted', p_alloc_id; end if;
  select * into v_chg from public.po_charge where id = v_al.po_charge_id;
  if v_chg.status <> 'draft' then
    raise exception 'Charge % is % — allocations can be edited only while draft — nothing was deleted', v_chg.charge_number, v_chg.status;
  end if;
  select po_number into v_pon from public.po where id = v_al.po_id;
  delete from public.po_charge_alloc where id = p_alloc_id;
  select * into v_m from public.po_charge_money where id = v_chg.id;
  return jsonb_build_object('deleted', true, 'alloc_id', v_al.id, 'charge_id', v_chg.id, 'charge_number', v_chg.charge_number, 'po_number', v_pon,
                            'amount_removed', v_al.amount, 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated);
end;
$$;
comment on function public.po_charge_alloc_delete(uuid) is '⑤ 비용 배분 줄 지우기 — draft 만 · 다른 줄은 안 건드린다 · 갱신 뒤 alloc_sum·unallocated. 2026-09-17';

revoke all on function public.po_charge_alloc_add(uuid, uuid, numeric) from public, anon;
revoke all on function public.po_charge_alloc_update(uuid, numeric)    from public, anon;
revoke all on function public.po_charge_alloc_delete(uuid)             from public, anon;
grant execute on function public.po_charge_alloc_add(uuid, uuid, numeric) to authenticated;
grant execute on function public.po_charge_alloc_update(uuid, numeric)    to authenticated;
grant execute on function public.po_charge_alloc_delete(uuid)             to authenticated;

-- ═══ ⑦ po_charge_alloc_spread(p_charge_id) — 다시 비례로 채우기 · ⭐ 사람이 누를 때만 ═══
create function public.po_charge_alloc_spread(p_charge_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_chg    public.po_charge%rowtype;
  v_ids    uuid[];
  v_m      record;
  v_out    jsonb := '[]'::jsonb;
  v_base   numeric := 0;
  v_warn   text[] := '{}';
  v_before numeric;
  v_alid   uuid;
  r        record;
begin
  select * into v_chg from public.po_charge where id = p_charge_id;
  if not found then raise exception 'Charge % not found — nothing was saved', p_charge_id; end if;
  if v_chg.status <> 'draft' then
    raise exception 'Charge % is % — allocations can be edited only while draft — nothing was saved', v_chg.charge_number, v_chg.status;
  end if;
  select array_agg(po_id) into v_ids from public.po_charge_alloc where po_charge_id = p_charge_id;
  if v_ids is null then
    raise exception 'Charge % has no allocation lines — add purchase orders first — nothing was saved', v_chg.charge_number;
  end if;

  for r in select * from public.po_charge_alloc_propose(v_chg.total_amount, v_ids) loop
    select id, amount into v_alid, v_before from public.po_charge_alloc where po_charge_id = p_charge_id and po_id = r.po_id;
    update public.po_charge_alloc set amount = r.amount where id = v_alid;
    v_base := v_base + r.base_amount;
    v_out := v_out || jsonb_build_object('alloc_id', v_alid, 'po_id', r.po_id, 'po_number', r.po_number, 'base_amount', r.base_amount, 'amount_before', v_before, 'amount', r.amount);
  end loop;
  if v_base = 0 then v_warn := array_append(v_warn, 'no_base_amount'); end if;

  select * into v_m from public.po_charge_money where id = p_charge_id;
  return jsonb_build_object('charge_id', v_chg.id, 'charge_number', v_chg.charge_number, 'total_amount', v_chg.total_amount,
                            'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated, 'allocs', v_out, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_charge_alloc_spread(uuid) is '⑤ 지금 담긴 발주 전부의 배분을 ⑥ 규칙(po_charge_alloc_propose)으로 다시 계산해 덮어쓴다 — ⭐ 사람이 누를 때만 · 어떤 저장도 자동으로 부르지 않는다 · draft 만 · 줄 없으면 거부 · 결과 unallocated 는 0 이어야 한다(잔돈 규칙). 2026-09-17';
revoke all on function public.po_charge_alloc_spread(uuid) from public, anon;
grant execute on function public.po_charge_alloc_spread(uuid) to authenticated;

-- ═══ ⑧ po_charge_confirm(p_charge_id, p_confirm) — 확정 = 「이 배분으로 원가에 얹겠다」 · 되돌리기는 결제 없을 때만 (po_invoice_confirm 선례) ═══
create function public.po_charge_confirm(p_charge_id uuid, p_confirm boolean default true) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_chg   public.po_charge%rowtype;
  v_m     record;
  v_n     int;
  v_txt   text;
  v_warn  text[] := '{}';
begin
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_chg from public.po_charge where id = p_charge_id;
  if not found then raise exception 'Charge % not found — nothing was saved', p_charge_id; end if;
  select * into v_m from public.po_charge_money where id = p_charge_id;

  if p_confirm then
    if v_chg.status = 'confirmed' then raise exception 'Charge % is already confirmed — nothing was saved', v_chg.charge_number; end if;
    if v_chg.status = 'cancelled' then raise exception 'Charge % is cancelled — a cancelled document cannot be confirmed — nothing was saved', v_chg.charge_number; end if;
    select count(*) into v_n from public.po_charge_alloc where po_charge_id = p_charge_id;
    if v_n = 0 then raise exception 'Charge % has no allocation lines — nothing to put on cost — nothing was saved', v_chg.charge_number; end if;
    -- ⭐⭐ 거부(경고 아님) — 양쪽 다 우리가 넣는 숫자라 안 맞으면 덜 입력한 것(⑤)
    if v_m.unallocated <> 0 then
      raise exception 'Charge % is not fully allocated — total % · allocated % · unallocated % — fix the allocations (or press Spread) first — nothing was saved',
        v_chg.charge_number, v_m.total_amount, v_m.alloc_sum, v_m.unallocated;
    end if;
    if v_chg.total_amount = 0 then v_warn := array_append(v_warn, 'total_amount_zero'); end if;
    if exists (select 1 from public.po_charge_alloc a join public.po x on x.id = a.po_id where a.po_charge_id = p_charge_id and x.status = 'cancelled') then
      v_warn := array_append(v_warn, 'alloc_on_cancelled_po');
    end if;
    update public.po_charge set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now() where id = p_charge_id returning * into v_chg;
  else
    if v_chg.status <> 'confirmed' then raise exception 'Charge % is % — only a confirmed document can be reopened — nothing was saved', v_chg.charge_number, v_chg.status; end if;
    -- ⭐ po_invoice_confirm Reopen · po_doc_cancel 과 같은 선 — 결제 참조번호·금액을 이름으로
    if v_m.paid > 0 then
      select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
      from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
      where pa.po_charge_id = p_charge_id;
      raise exception 'Charge % has payments applied (%) — cannot reopen while paid; remove the payment allocation first — nothing was saved', v_chg.charge_number, v_txt;
    end if;
    update public.po_charge set status = 'draft', confirmed_by = null, confirmed_at = null where id = p_charge_id returning * into v_chg;
  end if;

  return jsonb_build_object(
    'id', v_chg.id, 'charge_number', v_chg.charge_number, 'status', v_chg.status, 'confirmed_at', v_chg.confirmed_at,
    'money', jsonb_build_object('total_amount', v_m.total_amount, 'paid', v_m.paid, 'unpaid', v_m.unpaid, 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated),
    'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_charge_confirm(uuid, boolean) is '⑤ 비용 확정(p_confirm=true) = 「이 배분으로 원가에 얹겠다」는 선언(미지급은 문서가 선 순간부터다 · po_charge_money.unpaid 는 status 를 안 본다). 검사: 배분 0줄 ⇒ 거부 · ⭐ unallocated ≠ 0 ⇒ 거부(인보이스 diff 와 다르다 — 양쪽 다 우리 숫자) · total 0 ⇒ 경고 · 취소된 발주에 배분 ⇒ 경고. 되돌리기(false)는 결제 충당이 있으면 거부(참조번호·금액을 이름으로 · po_invoice_confirm Reopen 과 같은 선). confirmed_by 서버 유도. 확정 뒤 배분 잠금은 편집 RPC 넷이 draft 만 받는 것으로. 정본 po-module §11-f · 2026-09-17';
revoke all on function public.po_charge_confirm(uuid, boolean) from public, anon;
grant execute on function public.po_charge_confirm(uuid, boolean) to authenticated;

-- ═══ ⑨ po_doc_cancel · po_doc_delete — p_target 에 'charge' (100000 정의 그대로 + charge 가지 · create or replace) ═══
-- 바뀐 곳: p_target 검사 셋 · charge 가지 신설(취소: 결제 있으면 거부 · 배분은 경고 has_allocs / 삭제: confirmed_at 있으면 거부 · 결제 있으면 거부 · allocs_deleted) · po 가지·invoice 가지는 무변
create or replace function public.po_doc_cancel(
  p_target text,                          -- 'po' | 'invoice'(인보이스·크레딧 한 표 · doc_kind 는 행에서) | 'charge'
  p_id     uuid,
  p_cancel boolean default true           -- false = 되돌리기(cancelled → 취소 직전 상태)
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff        uuid;
  v_po           public.po%rowtype;
  v_inv          public.po_invoice%rowtype;
  v_for          public.po_invoice%rowtype;
  v_chg          public.po_charge%rowtype;
  v_label        text;
  v_m            record;
  v_m2           record;
  v_recv_n       int;
  v_recv_qty     numeric;
  v_n            int;
  v_txt          text;
  v_inv_txt      text;
  v_chg_txt      text;
  v_cred_txt     text;
  v_split_txt    text;
  v_new_status   text;
  v_unpaid_before numeric;
  v_unpaid_after  numeric;
  v_warn         text[] := '{}';
begin
  if p_target not in ('po', 'invoice', 'charge') then
    raise exception 'p_target must be po, invoice or charge — nothing was saved';
  end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then
    raise exception 'No active staff record for this login — nothing was saved';
  end if;

  -- ══════════ 발주 (100000 그대로) ══════════
  if p_target = 'po' then
    select * into v_po from public.po where id = p_id;
    if not found then raise exception 'PO % not found — nothing was saved', p_id; end if;

    if p_cancel then
      if v_po.status = 'cancelled' then
        raise exception 'PO % is already cancelled — nothing was saved', v_po.po_number;
      end if;
      if v_po.status = 'closed' then
        raise exception 'PO % is closed (receiving finished) — a closed order cannot be cancelled — nothing was saved', v_po.po_number;
      end if;
      select count(*), coalesce(sum(rl.qty_ea), 0) into v_recv_n, v_recv_qty
      from public.po_receipt_line rl join public.po_line pl on pl.id = rl.po_line_id
      where pl.po_id = p_id;
      if v_recv_n > 0 then
        raise exception 'PO % has % receipt line(s) (% EA received) — a received order cannot be cancelled; receipts are events — nothing was saved',
          v_po.po_number, v_recv_n, v_recv_qty;
      end if;

      select string_agg(distinct i.invoice_number, ', ' order by i.invoice_number) into v_inv_txt
      from public.po_invoice_line il
      join public.po_line pl on pl.id = il.po_line_id
      join public.po_invoice i on i.id = il.po_invoice_id
      where pl.po_id = p_id and i.status <> 'cancelled';
      if v_inv_txt is not null then v_warn := array_append(v_warn, 'has_invoices'); end if;

      select string_agg(distinct c.charge_number, ', ' order by c.charge_number) into v_chg_txt
      from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id
      where a.po_id = p_id and c.status <> 'cancelled';
      if v_chg_txt is not null then v_warn := array_append(v_warn, 'has_charges'); end if;

      select string_agg(k.invoice_number, ', ' order by k.invoice_number) into v_cred_txt
      from public.po_invoice k where k.credit_po_id = p_id and k.status <> 'cancelled';
      if v_cred_txt is not null then v_warn := array_append(v_warn, 'has_numbered_credits'); end if;

      select string_agg(c.po_number, ', ' order by c.po_number) into v_split_txt
      from public.po c where c.split_from_id = p_id;
      if v_split_txt is not null then v_warn := array_append(v_warn, 'has_split_children'); end if;

      update public.po set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff
      where id = p_id returning * into v_po;
    else
      if v_po.status <> 'cancelled' then
        raise exception 'PO % is % — only a cancelled order can be restored — nothing was saved', v_po.po_number, v_po.status;
      end if;
      v_new_status := case when v_po.confirmed_at is not null then 'confirmed' else 'draft' end;
      update public.po set status = v_new_status, cancelled_at = null, cancelled_by = null
      where id = p_id returning * into v_po;
    end if;

    return jsonb_build_object(
      'target', 'po', 'id', v_po.id, 'po_number', v_po.po_number, 'status', v_po.status,
      'cancelled_at', v_po.cancelled_at, 'confirmed_at', v_po.confirmed_at, 'restored', not p_cancel,
      'attached', jsonb_build_object('invoices', v_inv_txt, 'charges', v_chg_txt, 'numbered_credits', v_cred_txt, 'split_children', v_split_txt),
      'warnings', to_jsonb(v_warn));
  end if;

  -- ══════════ 비용 문서 (새 가지) ══════════
  if p_target = 'charge' then
    select * into v_chg from public.po_charge where id = p_id;
    if not found then raise exception 'Charge % not found — nothing was saved', p_id; end if;
    select * into v_m from public.po_charge_money where id = p_id;

    if p_cancel then
      if v_chg.status = 'cancelled' then
        raise exception 'Charge % is already cancelled — nothing was saved', v_chg.charge_number;
      end if;
      -- ⭐ 결제 충당 ⇒ 거부 — 인보이스 취소 · po_charge_confirm Reopen 과 같은 선 · 참조번호와 금액을 이름으로
      if v_m.paid > 0 then
        select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
        from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
        where pa.po_charge_id = p_id;
        raise exception 'Charge % has payments applied (%) — cannot cancel while paid; remove the payment allocation first — nothing was saved', v_chg.charge_number, v_txt;
      end if;
      -- 배분은 경고만(발주 취소가 인보이스를 경고만 하는 것과 같은 선) — 취소되면 po_list.charge_count · charge_total 에서 빠진다(190000 이 status 를 본다)
      select count(*), string_agg(x.po_number, ', ' order by x.po_number) into v_n, v_chg_txt
      from public.po_charge_alloc a join public.po x on x.id = a.po_id where a.po_charge_id = p_id;
      if v_n > 0 then v_warn := array_append(v_warn, 'has_allocs'); end if;
      if v_chg.status = 'draft' then v_warn := array_append(v_warn, 'cancelled_from_draft'); end if;

      update public.po_charge set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff
      where id = p_id returning * into v_chg;
    else
      if v_chg.status <> 'cancelled' then
        raise exception 'Charge % is % — only a cancelled document can be restored — nothing was saved', v_chg.charge_number, v_chg.status;
      end if;
      v_new_status := case when v_chg.confirmed_at is not null then 'confirmed' else 'draft' end;
      update public.po_charge set status = v_new_status, cancelled_at = null, cancelled_by = null
      where id = p_id returning * into v_chg;
    end if;

    return jsonb_build_object(
      'target', 'charge', 'id', v_chg.id, 'charge_number', v_chg.charge_number, 'status', v_chg.status,
      'cancelled_at', v_chg.cancelled_at, 'confirmed_at', v_chg.confirmed_at, 'restored', not p_cancel,
      'attached', jsonb_build_object('pos', v_chg_txt),
      'warnings', to_jsonb(v_warn));
  end if;

  -- ══════════ 인보이스 · 크레딧 (100000 그대로) ══════════
  select * into v_inv from public.po_invoice where id = p_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_id; end if;
  v_label := case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;
  select * into v_m from public.po_invoice_money where id = p_id;

  if p_cancel then
    if v_inv.status = 'cancelled' then
      raise exception '% % is already cancelled — nothing was saved', v_label, v_inv.invoice_number;
    end if;
    if v_m.alloc_total > 0 then
      select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
      from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
      where pa.po_invoice_id = p_id;
      raise exception '% % has payments applied (%) — cannot cancel while paid/used; remove the payment allocation first — nothing was saved',
        v_label, v_inv.invoice_number, v_txt;
    end if;
    select count(*), string_agg(c.invoice_number, ', ' order by c.invoice_number) into v_n, v_txt
    from public.po_invoice c where c.credit_for_invoice_id = p_id and c.status <> 'cancelled';
    if v_n > 0 then
      raise exception 'Invoice % has % credit note(s) attached (%) — cancel or detach those first — nothing was saved',
        v_inv.invoice_number, v_n, v_txt;
    end if;
    if v_inv.doc_kind = 'credit' and v_inv.credit_for_invoice_id is not null then
      select * into v_m2 from public.po_invoice_money where id = v_inv.credit_for_invoice_id;
      v_unpaid_before := v_m2.unpaid;
      if v_m2.alloc_total > 0 then v_warn := array_append(v_warn, 'credit_for_invoice_has_payments'); end if;
    end if;
    if v_inv.status = 'draft' then v_warn := array_append(v_warn, 'cancelled_from_draft'); end if;

    update public.po_invoice set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff
    where id = p_id returning * into v_inv;

    if v_inv.doc_kind = 'credit' and v_inv.credit_for_invoice_id is not null then
      select unpaid into v_unpaid_after from public.po_invoice_money where id = v_inv.credit_for_invoice_id;
    end if;
  else
    if v_inv.status <> 'cancelled' then
      raise exception '% % is % — only a cancelled document can be restored — nothing was saved', v_label, v_inv.invoice_number, v_inv.status;
    end if;
    v_new_status := case when v_inv.confirmed_at is not null then 'confirmed' else 'draft' end;
    if v_inv.credit_for_invoice_id is not null then
      select * into v_for from public.po_invoice where id = v_inv.credit_for_invoice_id;
      if v_for.status = 'cancelled' then v_warn := array_append(v_warn, 'credit_for_cancelled'); end if;
    end if;
    update public.po_invoice set status = v_new_status, cancelled_at = null, cancelled_by = null
    where id = p_id returning * into v_inv;
  end if;

  return jsonb_build_object(
    'target', 'invoice', 'id', v_inv.id, 'doc_kind', v_inv.doc_kind, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status,
    'cancelled_at', v_inv.cancelled_at, 'confirmed_at', v_inv.confirmed_at, 'restored', not p_cancel,
    'credit_for', case when v_inv.credit_for_invoice_id is not null then
        jsonb_build_object('invoice_id', v_inv.credit_for_invoice_id,
                           'invoice_number', (select f.invoice_number from public.po_invoice f where f.id = v_inv.credit_for_invoice_id),
                           'unpaid_before', v_unpaid_before, 'unpaid_after', v_unpaid_after) end,
    'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_doc_cancel(text, uuid, boolean) is '⑤ 취소 · 되돌리기(p_cancel=false) — 발주(p_target po) · 인보이스·크레딧(invoice) · ⭐ [2026-09-17 비용] 비용 문서(charge). 발주: closed · 입고 줄 있음 ⇒ 거부 · 인보이스/비용/번호 낸 크레딧/자식은 경고 + attached{}. 인보이스·크레딧: 결제 충당 ⇒ 거부(Reopen 과 같은 선 · 참조번호를 이름으로) · 취소 안 된 크레딧이 붙은 인보이스 ⇒ 거부 · 크레딧이 붙은 인보이스에 결제가 있으면 경고 + unpaid 전후. 비용: 결제 충당 ⇒ 거부(같은 선) · 배분은 경고 has_allocs + attached.pos. 되돌리기는 취소 직전 상태로(confirmed_at 있으면 confirmed) — 취소는 confirmed_at 을 안 건드린다. cancelled_by 는 auth.uid() 유도. 크레딧은 지울 수 없으므로 무효로 만드는 길은 이것 하나다. 정본 po-module §5 · §11-c · §11-f · §11-g · §13-f · 2026-09-17';

revoke all on function public.po_doc_cancel(text, uuid, boolean) from public, anon;
grant execute on function public.po_doc_cancel(text, uuid, boolean) to authenticated;

create or replace function public.po_doc_delete(
  p_target text,                          -- 'po' | 'invoice' | 'charge'
  p_id     uuid
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_po        public.po%rowtype;
  v_inv       public.po_invoice%rowtype;
  v_chg       public.po_charge%rowtype;
  v_label     text;
  v_n         int;
  v_txt       text;
  v_lines     int;
  v_discs     int;
begin
  if p_target not in ('po', 'invoice', 'charge') then
    raise exception 'p_target must be po, invoice or charge — nothing was deleted';
  end if;

  -- ══════════ 발주 (100000 그대로) ══════════
  if p_target = 'po' then
    select * into v_po from public.po where id = p_id;
    if not found then raise exception 'PO % not found — nothing was deleted', p_id; end if;

    if v_po.confirmed_at is not null then
      raise exception 'PO % was confirmed on % — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted',
        v_po.po_number, to_char(v_po.confirmed_at, 'YYYY-MM-DD');
    end if;

    select count(*) into v_n
    from public.po_receipt_line rl join public.po_line pl on pl.id = rl.po_line_id where pl.po_id = p_id;
    if v_n > 0 then
      raise exception 'PO % has % receipt line(s) — a received order cannot be deleted; receipts are events — nothing was deleted', v_po.po_number, v_n;
    end if;

    select count(distinct i.id), string_agg(distinct i.invoice_number, ', ' order by i.invoice_number) into v_n, v_txt
    from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id join public.po_invoice i on i.id = il.po_invoice_id
    where pl.po_id = p_id;
    if v_n > 0 then
      raise exception 'PO % is referenced by % invoice/credit document(s) (%) — remove those lines or delete those documents first — nothing was deleted', v_po.po_number, v_n, v_txt;
    end if;

    select count(*), string_agg(c.charge_number, ', ' order by c.charge_number) into v_n, v_txt
    from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id where a.po_id = p_id;
    if v_n > 0 then
      raise exception 'PO % has % charge allocation(s) (%) — remove the allocation first — nothing was deleted', v_po.po_number, v_n, v_txt;
    end if;

    select count(*), string_agg(c.po_number, ', ' order by c.po_number) into v_n, v_txt
    from public.po c where c.split_from_id = p_id;
    if v_n > 0 then
      raise exception 'PO % has % split document(s) (%) pointing at it — the chain would break — nothing was deleted', v_po.po_number, v_n, v_txt;
    end if;

    select count(*), string_agg(k.invoice_number, ', ' order by k.invoice_number) into v_n, v_txt
    from public.po_invoice k where k.credit_po_id = p_id;
    if v_n > 0 then
      raise exception 'PO % numbered % credit note(s) (%) — their number rests on this PO — nothing was deleted', v_po.po_number, v_n, v_txt;
    end if;

    select count(*) into v_lines from public.po_line     where po_id = p_id;
    select count(*) into v_discs from public.po_discount where po_id = p_id;
    delete from public.po where id = p_id;

    return jsonb_build_object(
      'deleted', true, 'target', 'po', 'id', v_po.id, 'po_number', v_po.po_number, 'status_before', v_po.status,
      'lines_deleted', v_lines, 'discounts_deleted', v_discs);
  end if;

  -- ══════════ 비용 문서 (새 가지) ══════════
  if p_target = 'charge' then
    select * into v_chg from public.po_charge where id = p_id;
    if not found then raise exception 'Charge % not found — nothing was deleted', p_id; end if;

    -- ⭐ 경계 — 세 문서 같은 문장 모양 · 판정 축은 confirmed_at
    if v_chg.confirmed_at is not null then
      raise exception 'Charge % was confirmed on % — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted',
        v_chg.charge_number, to_char(v_chg.confirmed_at, 'YYYY-MM-DD');
    end if;

    -- 밖에서 가리키는 하나 — 결제 충당(po_payment_alloc.po_charge_id · FK no action) · 이름으로
    select count(*), string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_n, v_txt
    from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id where pa.po_charge_id = p_id;
    if v_n > 0 then
      raise exception 'Charge % has payments applied (%) — remove the payment allocation first — nothing was deleted', v_chg.charge_number, v_txt;
    end if;

    -- 딸려 가는 하나(CASCADE) — 배분 줄 · 확정 전이라 원가에 내려간 적이 없다
    select count(*) into v_lines from public.po_charge_alloc where po_charge_id = p_id;
    delete from public.po_charge where id = p_id;

    return jsonb_build_object(
      'deleted', true, 'target', 'charge', 'id', v_chg.id, 'charge_number', v_chg.charge_number, 'status_before', v_chg.status,
      'allocs_deleted', v_lines);
  end if;

  -- ══════════ 인보이스 · 크레딧 (100000 그대로) ══════════
  select * into v_inv from public.po_invoice where id = p_id;
  if not found then raise exception 'Invoice % not found — nothing was deleted', p_id; end if;
  v_label := case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;

  if v_inv.doc_kind = 'credit' then
    raise exception 'Credit note % cannot be deleted — cancel it instead; its number must never be reused by another credit note — nothing was deleted', v_inv.invoice_number;
  end if;

  if v_inv.confirmed_at is not null then
    raise exception '% % was confirmed on % — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted',
      v_label, v_inv.invoice_number, to_char(v_inv.confirmed_at, 'YYYY-MM-DD');
  end if;

  select count(*), string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_n, v_txt
  from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id where pa.po_invoice_id = p_id;
  if v_n > 0 then
    raise exception '% % has payments applied (%) — remove the payment allocation first — nothing was deleted', v_label, v_inv.invoice_number, v_txt;
  end if;

  select count(*), string_agg(c.invoice_number, ', ' order by c.invoice_number) into v_n, v_txt
  from public.po_invoice c where c.credit_for_invoice_id = p_id;
  if v_n > 0 then
    raise exception 'Invoice % has % credit note(s) pointing at it (%) — cancel and detach those first — nothing was deleted', v_inv.invoice_number, v_n, v_txt;
  end if;

  select count(*) into v_lines from public.po_invoice_line     where po_invoice_id = p_id;
  select count(*) into v_discs from public.po_invoice_discount where po_invoice_id = p_id;
  delete from public.po_invoice where id = p_id;

  return jsonb_build_object(
    'deleted', true, 'target', 'invoice', 'id', v_inv.id, 'doc_kind', v_inv.doc_kind, 'invoice_number', v_inv.invoice_number, 'status_before', v_inv.status,
    'lines_deleted', v_lines, 'discounts_deleted', v_discs);
end;
$$;
comment on function public.po_doc_delete(text, uuid) is '⑤ 삭제 — 한 번도 확정되지 않은 것만(판정 축은 confirmed_at). 발주(po): confirmed_at 있으면 거부 · 밖에서 가리키는 다섯이 있으면 이름으로 거부 · 라인·할인 CASCADE. 인보이스(invoice): 크레딧은 무조건 거부(취소만) · confirmed_at 있으면 거부 · 결제/가리키는 크레딧 있으면 거부 · 줄·할인 CASCADE. ⭐ [2026-09-17 비용] 비용(charge): confirmed_at 있으면 거부(같은 문장 모양) · 결제 충당(po_payment_alloc.po_charge_id) 있으면 이름으로 거부 · 배분 줄 CASCADE · allocs_deleted 반환. 정본 po-module §5 · §11-f · §11-g · §13-f · §13-h · 2026-09-17';

revoke all on function public.po_doc_delete(text, uuid) from public, anon;
grant execute on function public.po_doc_delete(text, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 검증 (Caleb · 테스트 DB · 지시서 §5 · ⚠️ 실물 숫자는 4-b SQL 결과를 받은 뒤 채운다 — 아래는 지시서 1-⓪(2026-09-17) · 4-b 실측(Caleb 2026-09-17 SQL · po_list.subtotal PO-02001a 2446.80 · PO-02002 **8010.40**) · CBSA 10039192310530 = 597.49 + 1,949.88 · confirmed · EFT-20260916-02 2,547.37 에서)
--   📌 정본 §13-b 2868행의 「PO-02002 소계 7,985.00」은 2026-09-16 정오 실물이다(그때 discount_factor 1.000000 이라 소계 = net_total 7,985.00 · 164539 291행 · 163806 347행) · 그 뒤 PO-02002 라인이 +25.40 되어 지금 8,010.40 — 오기가 아니라 데이터가 움직였다
--   ⭐ 바로 이 자리가 「박아 둔 배분은 발주 금액이 바뀌어도 안 따라온다」(§11-f · po_charge_alloc 표 주석)의 실물 사례다 — 라인이 +25.40 움직였는데 배분 597.49 · 1,949.88 은 그대로고, 비례값(596.04 · 1,951.33)과 1.45 어긋난 채 남는 것이 설계다
--   ⚠️ po_charge_create(commit) · po_charge_confirm · po_doc_cancel 은 auth.uid() 를 본다 — psql 에서는 request.jwt.claims 를 심는다(§10-h). 미리 보기 · detail · alloc 셋 · spread · 뷰 · po_doc_delete 는 그냥 된다
--   ⚠️⚠️ CBSA 는 이미 **confirmed** 다(1-⓪) ⇒ 지시서 §5 ③~⑥ 의 「배분을 고친다 → 확정 거부 → spread → 확정」은 CBSA 로는 안 된다(편집 RPC 가 draft 만 받고 · Reopen 은 결제가 막는다 · ⑦) — 새 draft 청구서 T 로 돈다(이견 14)
-- ─────────────────────────────────────────────────────────────
-- ⓪ 적용 뒤
--   \d po_charge   → cancelled_by uuid(FK ims_staff)
--   \dv po_charge_list  ·  \df po_charge_*  → po_charge_alloc_propose · po_charge_detail · po_charge_create · po_charge_alloc_add/update/delete · po_charge_alloc_spread · po_charge_confirm
--   select pg_get_functiondef('public.po_doc_delete'::regproc) like '%charge%';   → true
-- ① 목록   select charge_number, status, total_amount, paid, unpaid, alloc_sum, unallocated, po_count, po_numbers from po_charge_list order by charge_date;
--   예상  1행 · 10039192310530 · confirmed · 2547.37 · paid 2547.37 · unpaid 0.00 · alloc_sum 2547.37 · unallocated 0.00 · po_count 2 · po_numbers 'PO-02001a PO-02002'
-- ② 상세   select jsonb_pretty(po_charge_detail((select id from po_charge where charge_number='10039192310530')));
--   예상  allocs 2줄 — PO-02001a { amount 597.49, base_amount 2446.80, other_charges 0, po_status closed } · PO-02002 { amount 1949.88, base_amount 8010.40, other_charges 0, po_status confirmed }
--         payments 1줄 — EFT-20260916-02 · alloc_amount 2547.37 · payment_amount 2496.42 · discount_taken 50.95 · CAD · money.unallocated 0.00 · warnings []
-- ②-b 비례 규칙 검산(함수만)   select * from po_charge_alloc_propose(2547.37, array[(select id from po where po_number='PO-02001a'), (select id from po where po_number='PO-02002')]);
--   예상  PO-02001a base 2446.80 amount 596.04 · PO-02002 base 8010.40 amount 1951.33 (합 2547.37 · 잔돈 0.00)
--         손계산(합 10457.20): 2547.37 × 2446.80 / 10457.20 = 596.0396… → 596.04 · 2547.37 × 8010.40 / 10457.20 = 1951.3304… → 1951.33 · 596.04 + 1951.33 = 2547.37 ⇒ 잔돈 0.00. 잔돈이 생겼다면 기준이 큰 PO-02002 가 받는다
--   ⭐ 지금 박힌 597.49 · 1949.88 은 이 비례값과 **1.45 어긋난다**(597.49 − 596.04 = +1.45 · 1949.88 − 1951.33 = −1.45) — 결함이 아니라 설계다: 사람이 넣은(고친) 배분은 다시 계산하지 않는다(po_charge_alloc 표 주석 · §11-f 「박아 두고 다시 계산하지 않는다」). spread 를 사람이 누를 때만 596.04 · 1951.33 이 된다
--   잔돈 실물   select * from po_charge_alloc_propose(100, array[<PO-02001a>, <PO-02002>, <PO-02007>]);   → 셋의 round 합이 100 과 어긋나면 기준이 가장 큰 발주(PO-02002 8010.40 · PO-02007 소계가 이보다 크면 그쪽 — 4-b 세 번째 SQL 의 subtotal 로 판정)가 잔돈을 받아 합 100.00
--   기준 0      select * from po_charge_alloc_propose(100, array[<PO-02009 처럼 라인 0 인 발주 둘>]);   → 50.00 · 50.00 · (부르는 쪽 경고 no_base_amount)
-- ③ CBSA 배분 고치기 시도   select po_charge_alloc_update((select id from po_charge_alloc a join po x on x.id=a.po_id join po_charge c on c.id=a.po_charge_id where c.charge_number='10039192310530' and x.po_number='PO-02001a'), 600);
--   예상  예외 「Charge 10039192310530 is confirmed — allocations can be edited only while draft — nothing was saved」 · 행 무변
-- ④ CBSA 되돌리기 시도(jwt)  select po_charge_confirm((select id from po_charge where charge_number='10039192310530'), false);
--   예상  예외 「Charge 10039192310530 has payments applied (EFT-20260916-02 2547.37) — cannot reopen while paid; remove the payment allocation first — nothing was saved」
-- ⑤ CBSA 삭제 시도   select po_doc_delete('charge', (select id from po_charge where charge_number='10039192310530'));
--   예상  예외 「Charge 10039192310530 was confirmed on 2026-09-16 — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted」(confirmed_at 날짜는 실물 · 2026-09-16 짐작)
--   취소 시도   select po_doc_cancel('charge', <같은 id>);   → 「Charge 10039192310530 has payments applied (EFT-20260916-02 2547.37) — cannot cancel while paid; …」
-- ⑥ 새 draft 청구서 T 로 편집 흐름(jwt · 공급처는 CBSA 의 supplier_id · 번호 'TEST-CHG-1' · duty · 300.00 · CAD · 발주 PO-02001a · PO-02002)
--   미리 보기  select jsonb_pretty(po_charge_create(<cbsa sid>, 'TEST-CHG-1', null, 'duty', 300.00, <CAD id>, null, null, null, array[<02001a>, <02002>], false));
--     예상  committed false · charge_id null · allocs [PO-02001a base 2446.80 amount 70.19, PO-02002 base 8010.40 amount 229.81] · alloc_sum 300.00 · unallocated 0.00 · warnings []
--           (300 × 2446.80/10457.20 = 70.1947… → 70.19 · 300 × 8010.40/10457.20 = 229.8053… → 229.81 · 합 300.00 · 잔돈 0)
--   만들기    같은 인자 · true → charge_id 있음 · allocs[].inserted true   ·  select unallocated from po_charge_money where id=<T>;  → 0.00
--   중복      같은 번호로 다시 미리 보기 → warnings ['charge_number_exists'] · commit → 「Charge TEST-CHG-1 already exists for <CBSA 공급처명> — nothing was saved」
--   한 줄 고치기  select po_charge_alloc_update(<T 의 PO-02001a alloc_id>, 100);   → amount_before 70.19 · amount 100 · alloc_sum 329.81 · unallocated -29.81   ⭐ PO-02002 줄은 229.81 그대로(③ 「다른 줄이 안 바뀐다」)
--   확정 시도  select po_charge_confirm(<T>);   → 「Charge TEST-CHG-1 is not fully allocated — total 300.00 · allocated 329.81 · unallocated -29.81 — fix the allocations (or press Spread) first — nothing was saved」
--   spread    select jsonb_pretty(po_charge_alloc_spread(<T>));   → allocs [PO-02001a amount_before 100 amount 70.19, PO-02002 229.81 → 229.81] · unallocated 0.00 · warnings []
--   더하기    select po_charge_alloc_add(<T>, <PO-02007 id>);   → amount 0 · alloc_sum 300.00 · unallocated 0.00 (0 으로 들어간다 · 사람이 고치거나 spread) · 같은 발주 다시 → 「PO PO-02007 is already on charge TEST-CHG-1 — edit that line instead — nothing was saved」
--   지우기    select po_charge_alloc_delete(<그 alloc_id>);   → deleted true · amount_removed 0 · unallocated 0.00
--   확정      select po_charge_confirm(<T>);   → status confirmed · money.unallocated 0.00 · warnings []
--   확정 뒤 편집 시도 → 「Charge TEST-CHG-1 is confirmed — allocations can be edited only while draft — nothing was saved」 (add · update · delete · spread 넷 다)
--   되돌리기  select po_charge_confirm(<T>, false);   → status draft (결제 없음)
--   삭제      select po_doc_delete('charge', <T>);   → deleted true · status_before 'draft' · allocs_deleted 2
--   목록      select count(*) from po_charge_list;   → 1 (T 가 없다)
-- ⑦ 취소·되돌리기(jwt) — T 를 다시 만들어 확정한 뒤   po_doc_cancel('charge', <T>) → status cancelled · attached.pos 'PO-02001a, PO-02002' · warnings ['has_allocs'] ·
--   select charge_count, charge_total from po_list where po_number='PO-02002';   → 1 · 1949.88 (취소된 T 는 빠진다)  ·  po_doc_cancel('charge', <T>, false) → status confirmed (confirmed_at 이 있었다)
