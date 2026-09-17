-- ─────────────────────────────────────────────────────────────
-- ⑤ 결제(po_payment) 뒷단 — 목록 뷰 · 상세 · 만들기(미리 보기) · 충당 편집 둘 · 삭제 확장 (테스트 DB Asung-IMS · 2026-09-17)
--   표 둘(po_payment · po_payment_alloc)은 이미 서 있다(153313) — 이 파일은 표를 만들지도 고치지도 않는다
--
-- 정본: docs/design/po-module.md §11-h(IMS 는 사실만 · 분개는 QBO · discount_taken 은 사람이 선언 · for_payments 를 필터로 쓰지 마라 · 결제는 인보이스 또는 비용 문서) · §11-g(확정 = 장부에 받아들였다 · 그때 미지급이 생긴다) · §11-f(비용 문서도 돈을 낸다)
-- 선례: 20260917150000 po_charge_create(미리 보기 두 단계) · po_charge_detail · po_charge_list · po_doc_cancel/po_doc_delete(charge 가지 — 그대로 따른다) · 20260917170000(시그니처가 바뀌면 drop+create — 이번엔 인자 무변이라 replace)
-- 지시서: ~/asung/prompts/po-payment.md · 검토 이견 1~14(2026-09-17 · 권고안 그대로 — 뒤집히면 해당 절만)
-- ❌ 범위 밖 — 크레딧을 결제에 쓰는 것(§11-h 「안 붙은 크레딧만 이 길」 · 이견 4 · 다음 차수 · 지금은 **거부**한다) · 환차손익(exchange_rate 칸은 두되 안 쓴다 · ①) · 화면(대화 Claude)
--
-- ═══════════════════════════════════════════════════════════════
-- ⭐⭐ 화면(asung-ims · 대화 Claude)이 부르는 모양 — 여기 한 곳만 보고 쓴다 · supabase-js v2 · 예외는 error.message(HTTP 400) · 화면은 그 문장을 그대로 띄운다
-- ═══════════════════════════════════════════════════════════════
--   목록   sb.from("po_payment_list").select("*", { count:"exact" }).order("paid_on", { ascending:false }).range(a, b)
--          .ilike 검색 칸: reference · doc_numbers(청구서 번호로 결제를 찾는다) · supplier_names · account_code · account_name   ·   필터 칸: currency_id · account_id · balanced
--          칸: id · paid_on · amount · discount_taken · currency_id · currency_code · exchange_rate · account_id · account_code · account_name · reference · paid_by · paid_by_name · note · created_at · updated_at ·
--              alloc_sum · alloc_count · balanced(alloc_sum = amount + discount_taken) · doc_numbers(공백 구분 · 인보이스·비용 함께) · supplier_names(공백 구분 · 여럿이면 여럿)
--   상세   sb.rpc("po_payment_detail", { p_payment_id })                     → 없는 id 는 null
--          { header{ id, paid_on, amount, discount_taken, currency_id, currency_code, exchange_rate, account_id, account_code, account_name, reference, paid_by, paid_by_name, note, created_at, updated_at },
--            money{ amount, discount_taken, alloc_sum, gap(= amount + discount_taken − alloc_sum · 0 이어야) },
--            allocs[]{ alloc_id, target_kind('invoice'|'charge'), target_id, target_number, target_status, supplier_id, supplier_name, currency_code, amount, note,
--                      doc_total(인보이스 payable_net · 비용 total_amount), doc_paid_total(그 문서에 붙은 모든 결제의 충당 합), doc_unpaid(그 문서의 지금 미지급) },
--            warnings[] : gap_not_zero · no_allocs · mixed_currency · alloc_on_unconfirmed_doc · mixed_supplier }
--   만들기 미리 보기  sb.rpc("po_payment_create", { p_supplier_id, p_paid_on, p_amount, p_currency_id, p_discount_taken, p_account_id, p_reference, p_note, p_targets:[…], p_commit:false })
--          만들기        같은 인자 · p_commit:true
--          ⭐ p_targets = [ { "kind":"invoice", "id":"<po_invoice.id>", "amount":123.45, "note":null }, { "kind":"charge", "id":"<po_charge.id>", "amount":50, "note":null } ]
--             배열이다(문서마다 금액이 따로) · kind 는 'invoice' | 'charge' 만(크레딧은 거부 · 다음 차수) · amount 를 안 주거나 null 이면 **그 문서의 미지급 전액**을 제안해 채워 돌려준다 · note 는 선택
--          → { committed, payment_id(commit 때만 · 미리 보기는 null), paid_on, amount, discount_taken, currency_id, currency_code, supplier_id, supplier_name(대상 문서들의 공급처가 하나면 그것 · 아니면 null), account_code, account_name,
--              alloc_sum, gap, allocs[]{ kind, id, number, supplier_name, currency_code, doc_total, doc_paid_before, doc_unpaid_before, amount, inserted }, warnings[] }
--          warnings: mixed_supplier(이견 1 — 대상 문서의 공급처가 둘 이상이거나 p_supplier_id 와 다르다) · discount_taken_zero_with_gap 없음(gap ≠ 0 은 **거부**다) · account_missing(계좌를 안 골랐다 · 막지 않는다)
--          거부(저장 전 · 미리 보기에서도 같은 판정): 통화 다름 「… 5566 is USD but the payment is CAD — one payment, one currency …」 · 미확정 「Invoice 5566 is draft — only a confirmed document can be paid …」 ·
--                초과 「Invoice 5566: allocating 700.00 but only 586.92 is unpaid …」 · 검산 「Allocations 300.00 do not match amount 586.92 + discount 0.00 = 586.92 (gap 286.92) …」 · 크레딧 「CN-… is a credit note — …」 · 같은 문서 둘 「… appears twice in p_targets …」
--   충당 편집  sb.rpc("po_payment_alloc_set",    { p_payment_id, p_kind, p_target_id, p_amount, p_note })   → { alloc_id, payment_id, kind, target_id, target_number, amount_before(없었으면 null), amount, alloc_sum, gap, warnings[] }   ⭐ 있으면 고치고 없으면 더한다
--             sb.rpc("po_payment_alloc_delete", { p_alloc_id })                                           → { deleted:true, alloc_id, payment_id, kind, target_number, amount_removed, alloc_sum, gap }
--             ⚠️ 둘 다 만들기와 **같은 검사**(po_payment_target_check)를 쓴다 · gap 은 여기서 막지 않는다(편집 중간 상태) — 목록 balanced · 상세 gap 이 보여 준다
--   머리 칸(paid_on · amount · discount_taken · account_id · reference · note)  화면이 PostgREST 로 쓴다 — 결제는 상태가 없어 잠금 지점이 없다(이견 3 · ⚠️ currency_id 는 충당이 있으면 화면이 잠근다)
--   삭제   sb.rpc("po_doc_delete", { p_target:"payment", p_id })    → { deleted:true, target:'payment', id, reference, paid_on, amount, allocs_deleted, docs('AMP-778812, 10039192310530' · 미지급이 되살아난 문서) }   언제든(상태 없음)
--   취소   sb.rpc("po_doc_cancel", { p_target:"payment", p_id })    → 예외 「A payment has no cancelled state — delete it instead — nothing was saved」 (화면에 Cancel 버튼을 두지 않는다)
--   버튼 노출: Delete = 항상 · Cancel/Restore 없음 · 충당 편집 = 항상(잠금 없음) · Create 는 미리 보기 gap = 0 일 때만 활성
-- ═══════════════════════════════════════════════════════════════
--
-- ⭐ 확정된 설계(Caleb 2026-09-17 · 지시서 §1)와 대응
--   ① 통화는 공급처가 정한다 — 만들기는 p_supplier_id 를 받아 화면이 후보 문서·통화를 거기서 따라오게 한다 · KRW 송금은 인보이스를 CAD 로 만들어 푼다 · exchange_rate 는 안 쓴다(insert 안 함 · null)
--   ② ⭐⭐ 한 결제 = 한 통화 — 대상 문서 전부의 currency_id = p_currency_id 를 **뒷단이** 검사한다(화면이 공급처로 좁혀도 · anon key 공개) · 거부 문장에 문서 번호와 통화 코드를 이름으로
--   ③ 계좌 — ref_account 무변 · account_id nullable · 통화 검사 없음 · for_payments 안 쓴다 · 코드 하드코딩 없음 · 안 고르면 경고 account_missing 만
--   ④ 확정된 문서에만 — 인보이스·비용 status='confirmed' 만(po_invoice_money.unpaid 는 status 를 안 봐 초안에도 미지급이 계산된다 — 그래서 여기서 막는다) · cancelled 도 거부
--   ⑤ 부분 결제는 정상 — 막는 것은 둘: 문서 미지급 초과 · Σ충당 ≠ amount + discount_taken(만들기에서 거부 · 편집 RPC 는 gap 을 보여 주기만)
--   ⑥ discount_taken 은 사람이 준다(default 0 · 계산 유도 없음 · ≥ 0 은 CHECK)
--   ⑦ 상태 없음 — po_doc_delete 'payment'(언제든 · 충당 CASCADE · allocs_deleted) · po_doc_cancel 'payment' 는 거부
--
-- ⭐ 검사 한 곳(이견 2) — po_payment_target_check(kind, target_id, amount, currency_id, exclude_alloc_id): 존재 · 종류(크레딧 거부) · confirmed · 통화 · 초과. 만들기와 alloc_set 이 같은 함수를 쓴다 — 규칙이 두 곳이면 갈린다
--   초과의 기준 = 그 문서의 지금 미지급(po_invoice_money.unpaid · po_charge_money.unpaid) + (고치는 중이면 그 줄의 지금 금액) — 돈의 식은 뷰 그대로 · 여기서 다시 쓰지 않는다
--
-- ⭐ 관례(150000 그대로) — plpgsql · volatile(쓰기) / sql stable(읽기) · security invoker · set search_path · 「… — nothing was saved」 · array_append · paid_by 는 auth.uid() → ims_staff.id 서버 유도 · 반올림 2자리 · revoke public/anon + grant authenticated · 트리거 없음
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS · --db-url 이 보이면 테스트)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① po_payment_target_check — 대상 문서 검사 한 곳 (만들기 · 충당 편집이 같이 쓴다) ═══
-- 돌려주는 것: 문서의 사실(번호 · 상태 · 공급처 · 통화 · doc_total · doc_paid · doc_unpaid) · 통과 못 하면 예외
create function public.po_payment_target_check(
  p_kind            text,                  -- 'invoice' | 'charge'
  p_target_id       uuid,
  p_amount          numeric,               -- null 이면 초과 검사를 건너뛴다(미지급 전액 제안용)
  p_currency_id     uuid,                  -- 결제 통화 · 대상 문서와 같아야 한다
  p_exclude_alloc_id uuid default null     -- 고치는 중인 줄 — 그 금액은 미지급에 되돌려 놓고 본다
) returns table (
  target_number text, target_status text, supplier_id uuid, supplier_name text,
  currency_id uuid, currency_code text, doc_total numeric, doc_paid numeric, doc_unpaid numeric
)
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_label   text;
  v_kind    text;
  v_excl    numeric := 0;
  v_pay_cur text;
begin
  if p_kind not in ('invoice', 'charge') then
    raise exception 'p_targets[].kind must be invoice or charge — nothing was saved';
  end if;
  if p_exclude_alloc_id is not null then
    select coalesce(a.amount, 0) into v_excl from public.po_payment_alloc a where a.id = p_exclude_alloc_id;
    v_excl := coalesce(v_excl, 0);
  end if;
  select c.code into v_pay_cur from public.ref_currency c where c.id = p_currency_id;

  if p_kind = 'invoice' then
    select i.invoice_number, i.status, i.supplier_id, s.name, i.currency_id, cur.code, m.payable_net, m.alloc_total, m.unpaid, i.doc_kind
      into target_number, target_status, supplier_id, supplier_name, currency_id, currency_code, doc_total, doc_paid, doc_unpaid, v_kind
    from public.po_invoice i
    join public.po_invoice_money m on m.id = i.id
    join public.supplier s on s.id = i.supplier_id
    join public.ref_currency cur on cur.id = i.currency_id
    where i.id = p_target_id;
    if not found then raise exception 'Invoice % not found — nothing was saved', p_target_id; end if;
    if v_kind = 'credit' then
      -- §11-h 「안 붙은 크레딧만 이 길 · 붙은 크레딧은 두 번 깎인다」 — 부호가 반대라 이 검산에 못 섞는다 · 다음 차수(이견 4)
      raise exception '% is a credit note — using a credit note in a payment is a later step; only invoices and charges can be paid here — nothing was saved', target_number;
    end if;
    v_label := 'Invoice';
  else
    select c.charge_number, c.status, c.supplier_id, s.name, c.currency_id, cur.code, c.total_amount, m.paid, m.unpaid
      into target_number, target_status, supplier_id, supplier_name, currency_id, currency_code, doc_total, doc_paid, doc_unpaid
    from public.po_charge c
    join public.po_charge_money m on m.id = c.id
    join public.supplier s on s.id = c.supplier_id
    join public.ref_currency cur on cur.id = c.currency_id
    where c.id = p_target_id;
    if not found then raise exception 'Charge % not found — nothing was saved', p_target_id; end if;
    v_label := 'Charge';
  end if;

  -- ④ 확정된 문서에만 — 초안에도 미지급이 계산되므로 여기서 막는다
  if target_status <> 'confirmed' then
    raise exception '% % is % — only a confirmed document can be paid (confirm it first) — nothing was saved', v_label, target_number, target_status;
  end if;
  -- ② 한 결제 = 한 통화 — 문서 번호와 통화를 이름으로
  if currency_id <> p_currency_id then
    raise exception '% % is % but the payment is % — one payment, one currency; pay it with a separate % payment — nothing was saved',
      v_label, target_number, currency_code, coalesce(v_pay_cur, p_currency_id::text), currency_code;
  end if;
  -- ⑤ 미지급 초과 — 고치는 중인 줄의 금액은 되돌려 놓고 본다
  if p_amount is not null and p_amount > doc_unpaid + v_excl then
    raise exception '% %: allocating % but only % is unpaid — nothing was saved', v_label, target_number, p_amount, doc_unpaid + v_excl;
  end if;
  return next;
end;
$$;
comment on function public.po_payment_target_check(text, uuid, numeric, uuid, uuid) is '⑤ 결제 대상 문서 검사 한 곳 — po_payment_create · po_payment_alloc_set 이 같이 쓴다. 존재 · 종류(크레딧은 거부 · 다음 차수) · confirmed 만(④ · 초안에도 미지급이 계산되므로 여기서 막는다) · 통화 = 결제 통화(② 한 결제 한 통화 · 이름으로) · 미지급 초과(⑤ · 고치는 줄의 금액은 되돌려 놓고). 통과하면 문서의 사실 한 행(번호 · 상태 · 공급처 · 통화 · doc_total(payable_net/total_amount) · doc_paid · doc_unpaid — 뷰 그대로). 2026-09-17';
revoke all on function public.po_payment_target_check(text, uuid, numeric, uuid, uuid) from public, anon;
grant execute on function public.po_payment_target_check(text, uuid, numeric, uuid, uuid) to authenticated;

-- ═══ ② 뷰 po_payment_list — po_charge_list · po_invoice_list 와 같은 모양 · 충당 없는 결제도 보인다(left join) ═══
create view public.po_payment_list
  with (security_invoker = true) as
with al as (
  select pa.po_payment_id,
         count(*)::int                                                                 as alloc_count,
         coalesce(sum(pa.amount), 0)                                                    as alloc_sum,
         string_agg(coalesce(i.invoice_number, c.charge_number), ' ' order by coalesce(i.invoice_number, c.charge_number)) as doc_numbers,
         string_agg(distinct s.name, ' ' order by s.name)                               as supplier_names
  from public.po_payment_alloc pa
  left join public.po_invoice i on i.id = pa.po_invoice_id
  left join public.po_charge  c on c.id = pa.po_charge_id
  left join public.supplier   s on s.id = coalesce(i.supplier_id, c.supplier_id)
  group by pa.po_payment_id
)
select
  p.id, p.paid_on, p.amount, p.discount_taken,
  p.currency_id, cur.code as currency_code, p.exchange_rate,
  p.account_id, acc.code as account_code, acc.name as account_name,
  p.reference, p.paid_by, st.name as paid_by_name, p.note, p.created_at, p.updated_at,
  coalesce(al.alloc_sum, 0)                                                     as alloc_sum,
  coalesce(al.alloc_count, 0)                                                   as alloc_count,
  (coalesce(al.alloc_sum, 0) = p.amount + p.discount_taken)                     as balanced,      -- 검산 Σ충당 = amount + discount_taken
  al.doc_numbers,                                                               -- 청구서 번호로 결제를 찾는다(.ilike)
  al.supplier_names                                                             -- 한 결제 한 공급처가 원칙이나 표가 강제하지 않는다 — 여럿이면 여럿
from public.po_payment p
join public.ref_currency cur on cur.id = p.currency_id
left join public.ref_account acc on acc.id = p.account_id
left join public.ims_staff st on st.id = p.paid_by
left join al on al.po_payment_id = p.id;

comment on view public.po_payment_list is '⑤ 결제 목록 — PostgREST 로 표처럼(§10-j 3-a · po_charge_list 와 같은 모양). alloc_sum · alloc_count · balanced(Σ충당 = amount + discount_taken · 표 주석의 검산) · doc_numbers(갚은 문서 번호 모음 · 인보이스·비용 함께 · 검색) · supplier_names(여럿이면 여럿). 충당 없는 결제도 보인다(left join · balanced false). security_invoker. 정본 po-module §11-h · 2026-09-17';
revoke all on public.po_payment_list from anon;
grant select on public.po_payment_list to authenticated;

-- ═══ ③ po_payment_detail(p_payment_id) — 한 건을 깊게 (po_charge_detail 선례) ═══
create function public.po_payment_detail(p_payment_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with p as (
  select * from public.po_payment where id = p_payment_id
),
al as (
  select pa.id as alloc_id, pa.amount, pa.note,
         case when pa.po_charge_id is not null then 'charge' else 'invoice' end                  as target_kind,
         coalesce(pa.po_invoice_id, pa.po_charge_id)                                             as target_id,
         coalesce(i.invoice_number, c.charge_number)                                             as target_number,
         coalesce(i.status, c.status)                                                            as target_status,
         coalesce(i.supplier_id, c.supplier_id)                                                  as supplier_id,
         s.name                                                                                  as supplier_name,
         coalesce(i.currency_id, c.currency_id)                                                  as doc_currency_id,
         cur.code                                                                                as currency_code,
         case when pa.po_charge_id is not null then cm.total_amount else im.payable_net end      as doc_total,        -- 인보이스 payable_net · 비용 total_amount
         case when pa.po_charge_id is not null then cm.paid         else im.alloc_total end      as doc_paid_total,   -- 그 문서에 붙은 모든 결제의 충당 합
         case when pa.po_charge_id is not null then cm.unpaid       else im.unpaid end           as doc_unpaid
  from public.po_payment_alloc pa
  left join public.po_invoice i on i.id = pa.po_invoice_id
  left join public.po_invoice_money im on im.id = pa.po_invoice_id
  left join public.po_charge c on c.id = pa.po_charge_id
  left join public.po_charge_money cm on cm.id = pa.po_charge_id
  left join public.supplier s on s.id = coalesce(i.supplier_id, c.supplier_id)
  left join public.ref_currency cur on cur.id = coalesce(i.currency_id, c.currency_id)
  where pa.po_payment_id = p_payment_id
),
m as (
  select p.amount, p.discount_taken, coalesce((select sum(amount) from al), 0) as alloc_sum,
         p.amount + p.discount_taken - coalesce((select sum(amount) from al), 0) as gap
  from p
)
select case when not exists (select 1 from p) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', p.id, 'paid_on', p.paid_on, 'amount', p.amount, 'discount_taken', p.discount_taken,
      'currency_id', p.currency_id, 'currency_code', cur.code, 'exchange_rate', p.exchange_rate,
      'account_id', p.account_id, 'account_code', acc.code, 'account_name', acc.name,
      'reference', p.reference, 'paid_by', p.paid_by, 'paid_by_name', st.name, 'note', p.note, 'created_at', p.created_at, 'updated_at', p.updated_at)
    from p
    join public.ref_currency cur on cur.id = p.currency_id
    left join public.ref_account acc on acc.id = p.account_id
    left join public.ims_staff st on st.id = p.paid_by
  ),
  'money', (select jsonb_build_object('amount', m.amount, 'discount_taken', m.discount_taken, 'alloc_sum', m.alloc_sum, 'gap', m.gap) from m),
  'allocs', coalesce((
    select jsonb_agg(jsonb_build_object('alloc_id', alloc_id, 'target_kind', target_kind, 'target_id', target_id, 'target_number', target_number, 'target_status', target_status,
                                        'supplier_id', supplier_id, 'supplier_name', supplier_name, 'currency_code', currency_code, 'amount', amount, 'note', note,
                                        'doc_total', doc_total, 'doc_paid_total', doc_paid_total, 'doc_unpaid', doc_unpaid)
                     order by target_kind, target_number)
    from al), '[]'::jsonb),
  'warnings', (
    select coalesce(jsonb_agg(w), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when m.gap <> 0 then 'gap_not_zero' end,
        case when not exists (select 1 from al) then 'no_allocs' end,
        case when exists (select 1 from al where al.doc_currency_id <> p.currency_id) then 'mixed_currency' end,
        case when exists (select 1 from al where al.target_status <> 'confirmed') then 'alloc_on_unconfirmed_doc' end,
        case when (select count(distinct supplier_id) from al) > 1 then 'mixed_supplier' end
      ], null)) as w
      from p cross join m) t
  )
) end;
$$;
comment on function public.po_payment_detail(uuid) is '⑤ 결제 상세 — 한 건을 깊게(payments.html). header · money(amount · discount_taken · alloc_sum · gap = amount + discount_taken − alloc_sum · 0 이어야) · allocs[](줄마다 문서의 대조값 doc_total/doc_paid_total/doc_unpaid — 부분 결제가 정상이라 「지금 얼마 남았나」를 보고 금액을 정한다 · 돈은 po_invoice_money·po_charge_money 그대로) · warnings[](gap_not_zero · no_allocs · mixed_currency · alloc_on_unconfirmed_doc · mixed_supplier). 없는 id → null. 2026-09-17';
revoke all on function public.po_payment_detail(uuid) from public, anon;
grant execute on function public.po_payment_detail(uuid) to authenticated;

-- ═══ ④ po_payment_create — 미리 보기(p_commit=false) · 만들기 (po_charge_create 선례) ═══
create function public.po_payment_create(
  p_supplier_id    uuid,                        -- 화면의 축(후보 문서·통화가 여기서 따라온다) · ⭐ 선택(이견 1·ⓑ) — 대상 문서의 공급처와 다르면 경고 mixed_supplier · 표에 칸이 없다(결제는 공급처를 안 담는다)
  p_paid_on        date,                        -- 안 주면 오늘
  p_amount         numeric,                     -- 실제로 낸 돈(결제 통화) · > 0(CHECK)
  p_currency_id    uuid,                        -- ⭐ 필수 · 결제 통화 = 대상 문서 전부의 통화(②)
  p_discount_taken numeric default 0,           -- ⑥ 사람이 선언 · ≥ 0(CHECK)
  p_account_id     uuid    default null,        -- 지정만(③) · 통화 검사 없음 · 안 고르면 경고
  p_reference      text    default null,
  p_note           text    default null,
  p_targets        jsonb   default null,        -- [ {kind, id, amount, note}, … ] · amount 없으면 미지급 전액 제안
  p_commit         boolean default false
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff      uuid;
  v_sup_id     uuid;
  v_sup_name   text;
  v_cur_code   text;
  v_acc_code   text;  v_acc_name text;
  v_pay_id     uuid;
  v_allocs     jsonb := '[]'::jsonb;
  v_sum        numeric := 0;
  v_gap        numeric;
  v_disc       numeric;
  v_warn       text[] := '{}';
  v_sups       uuid[] := '{}';
  v_seen       text[] := '{}';
  v_key        text;
  v_kind       text;  v_tid uuid;  v_amt numeric;  v_note text;
  t            record;
  r            jsonb;
begin
  if p_amount is null then raise exception 'Amount is required — nothing was saved'; end if;
  if p_amount <= 0 then raise exception 'Amount must be above 0 (got %) — nothing was saved', p_amount; end if;
  if p_currency_id is null then raise exception 'Currency is required — nothing was saved'; end if;
  select c.code into v_cur_code from public.ref_currency c where c.id = p_currency_id;
  if v_cur_code is null then raise exception 'Currency % not found — nothing was saved', p_currency_id; end if;
  v_disc := coalesce(p_discount_taken, 0);
  if v_disc < 0 then raise exception 'Discount taken cannot be negative (got %) — nothing was saved', v_disc; end if;
  v_sup_id := p_supplier_id;
  if v_sup_id is not null then
    select s.name into v_sup_name from public.supplier s where s.id = v_sup_id;
    if v_sup_name is null then raise exception 'Supplier % not found — nothing was saved', v_sup_id; end if;
  end if;
  if p_account_id is not null then
    select a.code, a.name into v_acc_code, v_acc_name from public.ref_account a where a.id = p_account_id;
    if v_acc_code is null then raise exception 'Account % not found — nothing was saved', p_account_id; end if;
  else
    v_warn := array_append(v_warn, 'account_missing');
  end if;
  if p_targets is not null and jsonb_typeof(p_targets) <> 'array' then
    raise exception 'p_targets must be a JSON array [{kind, id, amount, note}] — nothing was saved';
  end if;

  -- ── 대상 문서 검사(한 곳 · po_payment_target_check) — 미리 보기도 같은 판정 ──
  for r in select * from jsonb_array_elements(coalesce(p_targets, '[]'::jsonb)) loop
    v_kind := r->>'kind';
    v_tid  := nullif(r->>'id', '')::uuid;
    v_amt  := nullif(r->>'amount', '')::numeric;
    v_note := r->>'note';
    if v_tid is null then raise exception 'p_targets[] needs an id on every element — nothing was saved'; end if;
    v_key := coalesce(v_kind, '?') || ':' || v_tid::text;
    if v_key = any(v_seen) then raise exception 'Document % appears twice in p_targets — nothing was saved', v_tid; end if;
    v_seen := array_append(v_seen, v_key);
    if v_amt is not null and v_amt <= 0 then
      raise exception 'p_targets[] amount must be above 0 or omitted (got % for %) — nothing was saved', v_amt, v_tid;
    end if;
    select * into t from public.po_payment_target_check(v_kind, v_tid, v_amt, p_currency_id, null);
    if v_amt is null then v_amt := t.doc_unpaid; end if;                          -- 미지급 전액 제안
    if v_amt <= 0 then
      raise exception '% % has nothing unpaid (%) — nothing to allocate — nothing was saved', case v_kind when 'invoice' then 'Invoice' else 'Charge' end, t.target_number, t.doc_unpaid;
    end if;
    v_sum := v_sum + v_amt;
    if not (t.supplier_id = any(v_sups)) then v_sups := array_append(v_sups, t.supplier_id); end if;
    v_allocs := v_allocs || jsonb_build_object('kind', v_kind, 'id', v_tid, 'number', t.target_number, 'supplier_name', t.supplier_name, 'currency_code', t.currency_code,
                                               'doc_total', t.doc_total, 'doc_paid_before', t.doc_paid, 'doc_unpaid_before', t.doc_unpaid, 'amount', v_amt, 'note', v_note, 'inserted', p_commit);
  end loop;

  -- 공급처 — 강제하지 않는다(이견 1 · ⓑ) · 둘 이상이거나 p_supplier_id 와 다르면 경고
  if cardinality(v_sups) > 1 or (v_sup_id is not null and cardinality(v_sups) = 1 and v_sups[1] <> v_sup_id) then
    v_warn := array_append(v_warn, 'mixed_supplier');
  end if;
  if v_sup_id is null and cardinality(v_sups) = 1 then
    v_sup_id := v_sups[1];
    select s.name into v_sup_name from public.supplier s where s.id = v_sup_id;
  end if;

  -- ⑤ 검산 — Σ충당 = amount + discount_taken · 거부(양쪽 다 우리가 넣는 숫자)
  v_gap := round(p_amount + v_disc - v_sum, 2);
  if v_gap <> 0 then
    raise exception 'Allocations % do not match amount % + discount % = % (gap %) — fix the amounts or the discount first — nothing was saved',
      v_sum, p_amount, v_disc, p_amount + v_disc, v_gap;
  end if;

  -- ── commit: 머리 한 행 + 충당 줄 ──
  if p_commit then
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
    insert into public.po_payment (paid_on, amount, currency_id, account_id, reference, discount_taken, paid_by, note)
    values (coalesce(p_paid_on, current_date), p_amount, p_currency_id, p_account_id, p_reference, v_disc, v_staff, p_note)
    returning id into v_pay_id;
    for r in select * from jsonb_array_elements(v_allocs) loop
      insert into public.po_payment_alloc (po_payment_id, po_invoice_id, po_charge_id, amount, note)
      values (v_pay_id,
              case when r->>'kind' = 'invoice' then (r->>'id')::uuid end,
              case when r->>'kind' = 'charge'  then (r->>'id')::uuid end,
              (r->>'amount')::numeric, r->>'note');
    end loop;
  end if;

  return jsonb_build_object(
    'committed', p_commit, 'payment_id', v_pay_id, 'paid_on', coalesce(p_paid_on, current_date),
    'amount', p_amount, 'discount_taken', v_disc, 'currency_id', p_currency_id, 'currency_code', v_cur_code,
    'supplier_id', v_sup_id, 'supplier_name', v_sup_name,
    'account_code', v_acc_code, 'account_name', v_acc_name,
    'alloc_sum', v_sum, 'gap', v_gap, 'allocs', v_allocs, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_payment_create(uuid, date, numeric, uuid, numeric, uuid, text, text, jsonb, boolean) is '⑤ 결제 만들기(미리 보기 = 같은 모양 · p_commit). p_targets [{kind invoice|charge, id, amount, note}] — amount 없으면 미지급 전액 제안. 검사(po_payment_target_check · 미리 보기도 같은 판정): confirmed 만(④) · 한 결제 한 통화(② · 이름으로) · 미지급 초과(⑤) · 크레딧 거부(다음 차수) · 같은 문서 둘 거부 · ⭐ Σ충당 = amount + discount_taken 아니면 거부(⑤ · gap 을 문장에). 공급처는 강제 안 함(mixed_supplier 경고 · 비용처는 경비처라 발주처와 다르다). discount_taken 은 사람이(⑥). 계좌는 지정만 · 안 고르면 account_missing. paid_by 서버 유도. exchange_rate 는 안 쓴다(①). 정본 po-module §11-h · 2026-09-17';
revoke all on function public.po_payment_create(uuid, date, numeric, uuid, numeric, uuid, text, text, jsonb, boolean) from public, anon;
grant execute on function public.po_payment_create(uuid, date, numeric, uuid, numeric, uuid, text, text, jsonb, boolean) to authenticated;

-- ═══ ⑤ 충당 편집 둘 — 있으면 고치고 없으면 더한다 · 만들기와 같은 검사 · gap 은 보여 주기만 ═══
create function public.po_payment_alloc_set(p_payment_id uuid, p_kind text, p_target_id uuid, p_amount numeric, p_note text default null) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_pay    public.po_payment%rowtype;
  v_al     public.po_payment_alloc%rowtype;
  t        record;
  v_id     uuid;
  v_before numeric;
  v_sum    numeric;
  v_warn   text[] := '{}';
begin
  select * into v_pay from public.po_payment where id = p_payment_id;
  if not found then raise exception 'Payment % not found — nothing was saved', p_payment_id; end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'p_amount must be above 0 (got %) — to remove the line use po_payment_alloc_delete — nothing was saved', p_amount;
  end if;
  if p_kind not in ('invoice', 'charge') then raise exception 'p_kind must be invoice or charge — nothing was saved'; end if;

  -- 이미 있는 줄인가 — unique (po_payment_id, po_invoice_id) · (po_payment_id, po_charge_id) 가 축(null 은 서로 다르게 취급되어 종류가 다르면 안 겹친다)
  select * into v_al from public.po_payment_alloc a
  where a.po_payment_id = p_payment_id
    and ((p_kind = 'invoice' and a.po_invoice_id = p_target_id) or (p_kind = 'charge' and a.po_charge_id = p_target_id));
  if found then v_id := v_al.id; v_before := v_al.amount; end if;

  -- 만들기와 같은 검사 — 고치는 줄의 지금 금액은 미지급에 되돌려 놓고 본다
  select * into t from public.po_payment_target_check(p_kind, p_target_id, p_amount, v_pay.currency_id, v_id);

  if v_id is not null then
    update public.po_payment_alloc set amount = p_amount, note = coalesce(p_note, note) where id = v_id;
  else
    insert into public.po_payment_alloc (po_payment_id, po_invoice_id, po_charge_id, amount, note)
    values (p_payment_id, case when p_kind = 'invoice' then p_target_id end, case when p_kind = 'charge' then p_target_id end, p_amount, p_note)
    returning id into v_id;
  end if;

  select coalesce(sum(amount), 0) into v_sum from public.po_payment_alloc where po_payment_id = p_payment_id;
  if exists (select 1 from public.po_payment_alloc a
             left join public.po_invoice i on i.id = a.po_invoice_id left join public.po_charge c on c.id = a.po_charge_id
             where a.po_payment_id = p_payment_id and coalesce(i.supplier_id, c.supplier_id) <> t.supplier_id) then
    v_warn := array_append(v_warn, 'mixed_supplier');
  end if;
  return jsonb_build_object('alloc_id', v_id, 'payment_id', p_payment_id, 'kind', p_kind, 'target_id', p_target_id, 'target_number', t.target_number,
                            'amount_before', v_before, 'amount', p_amount,
                            'alloc_sum', v_sum, 'gap', round(v_pay.amount + v_pay.discount_taken - v_sum, 2), 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_payment_alloc_set(uuid, text, uuid, numeric, text) is '⑤ 결제 충당 줄 — 있으면 고치고 없으면 더한다(unique (payment, invoice) · (payment, charge) 가 축). 만들기와 같은 검사(po_payment_target_check · confirmed · 통화 · 초과 — 고치는 줄의 금액은 되돌려 놓고). gap 은 막지 않는다(편집 중간 상태 · 목록 balanced · 상세 gap 이 보여 준다). 갱신 뒤 alloc_sum · gap. 2026-09-17';

create function public.po_payment_alloc_delete(p_alloc_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_al   public.po_payment_alloc%rowtype;
  v_pay  public.po_payment%rowtype;
  v_num  text;
  v_sum  numeric;
begin
  select * into v_al from public.po_payment_alloc where id = p_alloc_id;
  if not found then raise exception 'Allocation line % not found — nothing was deleted', p_alloc_id; end if;
  select * into v_pay from public.po_payment where id = v_al.po_payment_id;
  select coalesce(i.invoice_number, c.charge_number) into v_num
  from public.po_payment_alloc a left join public.po_invoice i on i.id = a.po_invoice_id left join public.po_charge c on c.id = a.po_charge_id
  where a.id = p_alloc_id;
  delete from public.po_payment_alloc where id = p_alloc_id;
  select coalesce(sum(amount), 0) into v_sum from public.po_payment_alloc where po_payment_id = v_pay.id;
  return jsonb_build_object('deleted', true, 'alloc_id', v_al.id, 'payment_id', v_pay.id,
                            'kind', case when v_al.po_charge_id is not null then 'charge' else 'invoice' end, 'target_number', v_num,
                            'amount_removed', v_al.amount, 'alloc_sum', v_sum, 'gap', round(v_pay.amount + v_pay.discount_taken - v_sum, 2));
end;
$$;
comment on function public.po_payment_alloc_delete(uuid) is '⑤ 결제 충당 줄 지우기 — 그 문서의 미지급이 그만큼 되살아난다 · 갱신 뒤 alloc_sum · gap. 2026-09-17';

revoke all on function public.po_payment_alloc_set(uuid, text, uuid, numeric, text) from public, anon;
revoke all on function public.po_payment_alloc_delete(uuid)                     from public, anon;
grant execute on function public.po_payment_alloc_set(uuid, text, uuid, numeric, text) to authenticated;
grant execute on function public.po_payment_alloc_delete(uuid)                     to authenticated;

-- ═══ ⑥ po_doc_cancel · po_doc_delete — 'payment' (150000 정의 그대로 + payment 가지 · 인자 무변이라 create or replace) ═══
-- 바뀐 곳: p_target 검사 넷 · cancel 은 'payment' 를 **거부**(상태가 없다 · 조용히 통과시키지 않는다) · delete 는 payment 가지 신설(언제든 · 충당 CASCADE · allocs_deleted · docs) · po·invoice·charge 가지는 무변
create or replace function public.po_doc_cancel(
  p_target text,                          -- 'po' | 'invoice' | 'charge' | 'payment'(거부)
  p_id     uuid,
  p_cancel boolean default true
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
  if p_target not in ('po', 'invoice', 'charge', 'payment') then
    raise exception 'p_target must be po, invoice, charge or payment — nothing was saved';
  end if;
  -- ⭐ 결제는 상태가 없다(⑦) — 취소가 아니라 삭제
  if p_target = 'payment' then
    raise exception 'A payment has no cancelled state — delete it instead (po_doc_delete with p_target payment) — nothing was saved';
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

  -- ══════════ 비용 문서 (150000 그대로) ══════════
  if p_target = 'charge' then
    select * into v_chg from public.po_charge where id = p_id;
    if not found then raise exception 'Charge % not found — nothing was saved', p_id; end if;
    select * into v_m from public.po_charge_money where id = p_id;

    if p_cancel then
      if v_chg.status = 'cancelled' then
        raise exception 'Charge % is already cancelled — nothing was saved', v_chg.charge_number;
      end if;
      if v_m.paid > 0 then
        select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
        from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
        where pa.po_charge_id = p_id;
        raise exception 'Charge % has payments applied (%) — cannot cancel while paid; remove the payment allocation first — nothing was saved', v_chg.charge_number, v_txt;
      end if;
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
comment on function public.po_doc_cancel(text, uuid, boolean) is '⑤ 취소 · 되돌리기(p_cancel=false) — 발주(po) · 인보이스·크레딧(invoice) · 비용(charge). ⭐ [2026-09-17 결제] payment 는 **거부** — 결제는 상태가 없다(사실 · §11-h) · 지운다. 발주: closed · 입고 줄 ⇒ 거부 · 인보이스/비용/번호 낸 크레딧/자식은 경고. 인보이스·크레딧: 결제 충당 ⇒ 거부 · 붙은 크레딧 ⇒ 거부 · credit_for 결제 있으면 경고. 비용: 결제 충당 ⇒ 거부 · 배분은 경고. 되돌리기는 취소 직전 상태로. cancelled_by 서버 유도. 정본 po-module §5 · §11-c · §11-f · §11-g · §11-h · §13-f · 2026-09-17';

revoke all on function public.po_doc_cancel(text, uuid, boolean) from public, anon;
grant execute on function public.po_doc_cancel(text, uuid, boolean) to authenticated;

create or replace function public.po_doc_delete(
  p_target text,                          -- 'po' | 'invoice' | 'charge' | 'payment'
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
  v_pay       public.po_payment%rowtype;
  v_label     text;
  v_n         int;
  v_txt       text;
  v_lines     int;
  v_discs     int;
begin
  if p_target not in ('po', 'invoice', 'charge', 'payment') then
    raise exception 'p_target must be po, invoice, charge or payment — nothing was deleted';
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

  -- ══════════ 비용 문서 (150000 그대로) ══════════
  if p_target = 'charge' then
    select * into v_chg from public.po_charge where id = p_id;
    if not found then raise exception 'Charge % not found — nothing was deleted', p_id; end if;

    if v_chg.confirmed_at is not null then
      raise exception 'Charge % was confirmed on % — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted',
        v_chg.charge_number, to_char(v_chg.confirmed_at, 'YYYY-MM-DD');
    end if;

    select count(*), string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_n, v_txt
    from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id where pa.po_charge_id = p_id;
    if v_n > 0 then
      raise exception 'Charge % has payments applied (%) — remove the payment allocation first — nothing was deleted', v_chg.charge_number, v_txt;
    end if;

    select count(*) into v_lines from public.po_charge_alloc where po_charge_id = p_id;
    delete from public.po_charge where id = p_id;

    return jsonb_build_object(
      'deleted', true, 'target', 'charge', 'id', v_chg.id, 'charge_number', v_chg.charge_number, 'status_before', v_chg.status,
      'allocs_deleted', v_lines);
  end if;

  -- ══════════ 결제 (새 가지) — 상태가 없다 · 언제든 지운다(⑦ · 표 주석 「잘못 넣었으면 지운다」) · 충당 줄은 CASCADE · 그 문서들의 미지급이 되살아난다 ══════════
  if p_target = 'payment' then
    select * into v_pay from public.po_payment where id = p_id;
    if not found then raise exception 'Payment % not found — nothing was deleted', p_id; end if;

    select count(*), string_agg(coalesce(i.invoice_number, c.charge_number), ', ' order by coalesce(i.invoice_number, c.charge_number)) into v_lines, v_txt
    from public.po_payment_alloc a
    left join public.po_invoice i on i.id = a.po_invoice_id
    left join public.po_charge  c on c.id = a.po_charge_id
    where a.po_payment_id = p_id;
    delete from public.po_payment where id = p_id;

    return jsonb_build_object(
      'deleted', true, 'target', 'payment', 'id', v_pay.id, 'reference', v_pay.reference, 'paid_on', v_pay.paid_on, 'amount', v_pay.amount,
      'allocs_deleted', v_lines, 'docs', v_txt);                                  -- docs = 미지급이 되살아난 문서 번호(없으면 null)
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
comment on function public.po_doc_delete(text, uuid) is '⑤ 삭제 — 한 번도 확정되지 않은 것만(판정 축 confirmed_at) · 발주(po) · 인보이스(invoice · 크레딧은 무조건 거부) · 비용(charge). ⭐ [2026-09-17 결제] payment: 상태가 없어 confirmed_at 검사 없음 · 언제든 지운다(§11-h 「잘못 넣었으면 지운다」) · 충당 줄 CASCADE · allocs_deleted · docs(미지급이 되살아난 문서 번호). 정본 po-module §5 · §11-f · §11-g · §11-h · §13-f · §13-h · 2026-09-17';

revoke all on function public.po_doc_delete(text, uuid) from public, anon;
grant execute on function public.po_doc_delete(text, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 검증 (Caleb · 테스트 DB · 지시서 §6 · 실물은 5-b(Caleb 2026-09-17 SQL) — 검토 Claude 는 SQL 을 돌리지 않았다 · 검토 이견 1~14 전부 받음)
--   5566          invoice · draft · Strength of Nature, LLC · USD · payable_net 586.92 · unpaid 586.92   ← 미지급이 남은 유일한 문서(⚠️ draft — ① 이 그 거부를 본다)
--   AMP-778812    invoice · confirmed · Ampro · USD · unpaid 0.00
--   CN-AMP-778812-1  credit · cancelled(앞 차수 검증에서 취소)
--   계좌  _104_ TD CAD CHEQUING  a2c23414-143b-4ba9-9097-338268dacf97 · _105_ BMO CAD CHEQUING 6c27d47e-10b2-4dd4-907d-d24dc290bee3 · ⭐ _106_ BMO USD CHEQUING bada315d-60db-4ee1-9b58-d81ba9aeedf8(USD 결제는 이것)
--   ⚠️ 통화 id 는 code 로 찾는다 — <USD> = (select id from ref_currency where code='USD') · <CAD> = (select id from ref_currency where code='CAD') (⬜ CAD id 실물은 Caleb 에게 요청 — 화면이 쓸 값)
--   <5566> = (select id from po_invoice where invoice_number='5566' and doc_kind='invoice') · <SoN> = (select supplier_id from po_invoice where invoice_number='5566' and doc_kind='invoice') · <CBSA> = (select supplier_id from po_charge where charge_number='10039192310530')
--   ⚠️ po_payment_create(commit) · po_invoice_confirm · po_charge_create(commit) · po_charge_confirm 은 auth.uid() 를 본다 — psql 에서는 request.jwt.claims 를 심는다 · 미리 보기 · detail · alloc 둘 · 뷰 · po_doc_delete 는 그냥 된다
-- ─────────────────────────────────────────────────────────────
-- ⓪ 적용 뒤
--   \dv po_payment_list · \df po_payment_*  → po_payment_target_check · po_payment_detail · po_payment_create · po_payment_alloc_set · po_payment_alloc_delete
--   select pg_get_functiondef('public.po_doc_delete'::regproc) like '%payment%';   → true
--   select reference, amount, discount_taken, alloc_sum, alloc_count, balanced, doc_numbers, supplier_names from po_payment_list order by paid_on, reference;
--   예상  2행 — EFT-20260916-02 · 2496.42 · 50.95 · 2547.37 · 1 · true · '10039192310530' · <CBSA 공급처명>  /  WIRE-20260916-01 · 2010.54 · 0 · 2010.54 · 1 · true · 'AMP-778812' · 'Ampro'(실물명 짐작)
--   select jsonb_pretty(po_payment_detail((select id from po_payment where reference='EFT-20260916-02')));
--   예상  money { amount 2496.42, discount_taken 50.95, alloc_sum 2547.37, gap 0.00 } · allocs 1줄 { target_kind 'charge', target_number '10039192310530', target_status 'confirmed', currency_code 'CAD', amount 2547.37, doc_total 2547.37, doc_paid_total 2547.37, doc_unpaid 0.00 } · warnings []
-- ① 5566(draft)에 결제 미리 보기 — ④ 확정 문서만
--   select po_payment_create(<SoN>, current_date, 586.92, <USD>, 0, 'bada315d-60db-4ee1-9b58-d81ba9aeedf8', 'TEST-PAY-1', null,
--          jsonb_build_array(jsonb_build_object('kind','invoice','id',<5566>)), false);
--   예상  예외 「Invoice 5566 is draft — only a confirmed document can be paid (confirm it first) — nothing was saved」
-- ② 5566 확정(jwt · select po_invoice_confirm(<5566>);) 뒤 같은 미리 보기 — amount 를 안 줌(전액 제안)
--   예상  committed false · payment_id null · amount 586.92 · currency_code 'USD' · supplier_name 'Strength of Nature, LLC' · account_code '_106_' · account_name 'BMO USD CHEQUING' ·
--         alloc_sum 586.92 · gap 0.00 · allocs [{ kind 'invoice', number '5566', supplier_name 'Strength of Nature, LLC', currency_code 'USD', doc_total 586.92, doc_paid_before 0, doc_unpaid_before 586.92, amount 586.92, inserted false }] · warnings []
--         p_supplier_id 를 null 로 주면 supplier_id/supplier_name 이 SoN 으로 채워진다(이견 2) · <CBSA> 로 주면 warnings ['mixed_supplier'](이견 1 · 막지 않는다) · 계좌를 null 로 주면 warnings ['account_missing']
-- ③ 부분 결제 300 commit(jwt) — amount 300 · discount 0 · 충당 300
--   select jsonb_pretty(po_payment_create(<SoN>, current_date, 300, <USD>, 0, 'bada315d-60db-4ee1-9b58-d81ba9aeedf8', 'TEST-PAY-1', null,
--          jsonb_build_array(jsonb_build_object('kind','invoice','id',<5566>,'amount',300)), true));
--   예상  committed true · payment_id <P1> · gap 0.00 · allocs[0].inserted true
--         select unpaid, alloc_total from po_invoice_money where id=<5566>;   → 286.92 · 300.00
--         select payment_phase, paid_total, unpaid_total from po_list where po_number='PO-02007';   → 'partial' · 300.00 · 286.92
--         select reference, balanced, doc_numbers from po_payment_list where reference='TEST-PAY-1';   → true · '5566'
-- ④ 같은 문서에 둘째 결제 — amount 286.92 · 충당은 안 줌(전액 제안 = 남은 286.92)
--   select jsonb_pretty(po_payment_create(<SoN>, current_date, 286.92, <USD>, 0, 'bada315d-60db-4ee1-9b58-d81ba9aeedf8', 'TEST-PAY-2', null,
--          jsonb_build_array(jsonb_build_object('kind','invoice','id',<5566>)), true));
--   예상  allocs[0] { doc_paid_before 300.00, doc_unpaid_before 286.92, amount 286.92 } · gap 0.00 · payment_id <P2>  ·  unpaid 0.00 · alloc_total 586.92 · payment_phase 'done' (부분 결제가 두 번 나뉜다)
-- ⑤ 미지급보다 많이 — ③ 뒤(unpaid 286.92) · ④ 전에 시험한다
--   select po_payment_create(<SoN>, current_date, 700, <USD>, 0, 'bada315d-…', 'X', null, jsonb_build_array(jsonb_build_object('kind','invoice','id',<5566>,'amount',700)), false);
--   예상  예외 「Invoice 5566: allocating 700 but only 286.92 is unpaid — nothing was saved」
-- ⑥ 검산 어긋남 — ③ 뒤 · amount 286.92 인데 충당 100
--   select po_payment_create(<SoN>, current_date, 286.92, <USD>, 0, 'bada315d-…', 'X', null, jsonb_build_array(jsonb_build_object('kind','invoice','id',<5566>,'amount',100)), false);
--   예상  예외 「Allocations 100 do not match amount 286.92 + discount 0 = 286.92 (gap 186.92) — fix the amounts or the discount first — nothing was saved」
--   할인으로 맞추면 통과(⑥ 사람이 선언): amount 250 · discount 36.92 · 충당 286.92 → gap 0.00 · warnings []
-- ⑦ 통화가 다른 문서를 섞는다 — 실물이 없다(미지급은 5566 USD 뿐) ⇒ CAD 비용 T 를 만든다(jwt · ⚠️ po_charge_create 는 p_currency_id 필수)
--   select po_charge_create(<CBSA>, 'FX-TEST-1', current_date, 'freight', 100.00, <CAD>, null, 'currency-mix test', null,
--          array[(select id from po where po_number='PO-02007')], true) ->> 'charge_id';   → <T>   (배분 PO-02007 100.00 · unallocated 0.00)
--   select po_charge_confirm(<T>) ->> 'status';   → 'confirmed'
--   select po_payment_create(null, current_date, 386.92, <USD>, 0, 'bada315d-…', 'TEST-PAY-FX', null,
--          jsonb_build_array(jsonb_build_object('kind','invoice','id',<5566>), jsonb_build_object('kind','charge','id',<T>)), false);
--   예상  예외 「Charge FX-TEST-1 is CAD but the payment is USD — one payment, one currency; pay it with a separate CAD payment — nothing was saved」 (배열 순서대로 — 5566 이 먼저 통과하고 FX-TEST-1 에서 막힌다)
--   반대로 <CAD> 결제에 5566 을 넣으면 → 「Invoice 5566 is USD but the payment is CAD — …」
--   확인 뒤 po_doc_cancel('charge', <T>) 또는 po_charge_confirm(<T>, false) 뒤 po_doc_delete('charge', <T>)
-- ⑦-b ⭐ 크레딧 거부(이견 4) — CN-AMP-778812-1 로 시험한다. cancelled 여도 된다: po_payment_target_check 는 **종류 검사를 상태 검사보다 먼저** 하므로(문서 조회 직후 doc_kind 를 본다) 상태와 무관하게 크레딧 문장이 나온다
--   select po_payment_create(null, current_date, 30.90, <USD>, 0, null, 'X', null,
--          jsonb_build_array(jsonb_build_object('kind','invoice','id',(select id from po_invoice where invoice_number='CN-AMP-778812-1'))), false);
--   예상  예외 「CN-AMP-778812-1 is a credit note — using a credit note in a payment is a later step; only invoices and charges can be paid here — nothing was saved」
--   (확정된 크레딧으로 다시 보고 싶으면 po_doc_cancel('invoice', <CN id>, false) 로 되살린 뒤 같은 호출 — 같은 문장)
-- ⑧ po_doc_cancel('payment', <P1>)   → 예외 「A payment has no cancelled state — delete it instead (po_doc_delete with p_target payment) — nothing was saved」 (jwt 없이도 이 문장 — staff 검사보다 앞)
-- ⑨ po_doc_delete('payment', <P1>)   → deleted true · target 'payment' · reference 'TEST-PAY-1' · amount 300 · allocs_deleted 1 · docs '5566'
--   select unpaid from po_invoice_money where id=<5566>;   → ④ 를 했으면 300.00(586.92 − 286.92) · 안 했으면 586.92 — P1 의 300 이 되살아난다
--   충당 편집(P2 로): select po_payment_alloc_set(<P2>, 'invoice', <5566>, 200);   → amount_before 286.92 · amount 200 · alloc_sum 200 · gap 86.92 · warnings [] (막지 않는다 · 목록 balanced false)
--                    select po_payment_alloc_set(<P2>, 'invoice', <5566>, 286.92);  → gap 0.00  ·  select po_payment_alloc_delete(<그 alloc_id>);  → amount_removed 286.92 · alloc_sum 0 · gap 286.92
--                    다른 결제 P1 이 이미 지워졌으니 5566 미지급은 586.92 → 초과 시험: po_payment_alloc_set(<P2>, 'invoice', <5566>, 600) → 「Invoice 5566: allocating 600 but only 586.92 is unpaid …」
--   끝나면 po_doc_delete('payment', <P2>) · 5566 은 Reopen 하지 않고 두어도 된다(검증 데이터 · confirmed · unpaid 586.92)
