-- SO 크레딧 읽기 창구 — so_credit_remaining(식의 한 곳) · 복사 식 여섯 교체 · 뷰 so_credit_list · so_credit_detail 키 넷 · so_credit_prepare (so-credit-read-1 · 2026-09-25 UTC · 토론토 2026-09-25 밤)
-- 지시서 ~/asung/prompts/so-credit-read-1.md · 판정 Caleb 2026-09-25(0-1~0-8 · ⬜1~⬜5 전부 · 한 차수) · 정본 §19 · §18 · 화면 so-credits.html(IMS 인보이스 반품만 · Cin7 반품은 전환 전 다음 판)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 시험 적용 + 검증 ~/asung/prompts/so-credit-read-1-verify.sql(-v mig)
-- C0 so_credit_remaining(p_credit_id) — so_credit_detail :1274 의 식 그대로: 취소 0 · 그 밖 total − Σ활성 so_credit_alloc(voided_at is null · 인보이스 붙임 + 환불 붙임)
-- C1 살아 있는 정의 여섯의 복사 식 → C0 호출(바뀐 줄은 식 한 줄씩 · 시그니처·반환·grant 무변 · create or replace)
-- ⭐ ⬜1 근거 표 — 새 함수(취소 0)가 값을 바꾸지 않는 이유(자리마다):
--    so_credit_detail    20260925012354:1274  식이 「cancelled → 0 · else total − Σ」 = C0 정의 그대로
--    so_credit_alloc_add 20260925014413:33    :32 에서 status <> 'issued' 면 이미 raise
--    so_credit_attach    20260925014413:78    반환 직전 — alloc_add 가 한 번이라도 돌았으니 issued(안 돌면 :72 가 raise)
--    so_payment_refund   20260925014413:557   커서 WHERE c.status = 'issued'
--    so_invoice_issue ②  20260925201614:205   커서 WHERE c.status = 'issued'   (⚠️ 오늘 세 번째 재발행 · 마지막 정의는 그 파일)
--    so_customer_balance 20260925195701:50    cred CTE WHERE status = 'issued' · Σtotal − Σ(Σalloc) = Σ(total − Σalloc)(합의 분배 · numeric 정확 · 행 없으면 둘 다 null → 바깥 coalesce 0) ⇒ sum(so_credit_remaining(c.id))(⬜2)
-- ⚠️ 대상 아닌 것(0-3): so_credit_cancel :1221(활성 붙임 개수) · so_credit_detail applied(붙임 합) · so_invoice_detail credits_against.applied_here(인보이스별 몫) · 뷰 둘의 credited·refund_credit_covered(붙임 합)
-- R1 뷰 so_credit_list — 한 장 한 행 · security_invoker · applied_to_invoices(Σ활성 인보이스 붙임) · refunded(Σ활성 환불 붙임) · remaining(C0) · applied + refunded + remaining = total(issued) · invoice_number(원판매) · search_text
-- R2 so_credit_detail — 옛 키 아홉 그대로(credit · customer_name · invoice_number · lines · allocations(활성만) · applied · remaining · ledger · layers) + 넷(credit_row · allocations_all(void 포함 · 환불 결제 정보) · open_invoices(같은 손님·통화 · is_open · 오래된 순 · attached_from_this_credit) · customer_balance)
-- R3 so_credit_prepare(p_invoice_id) — 인보이스에서 크레딧을 낼 때의 준비물(읽기) · invoice(며칠 지났나) · warehouse(원판매 첫 오더의 창고 — 발행 창구의 기본과 같은 줄 :996) · lines(product·charge · qty_sold · qty_credited · qty_returnable · amount_credited · restock_bin_default = ims_last_bin(낱개 제품 · 그 창고) — 발행 창구 :1077 과 같은 길)
--    restock_fee(days · pct · account_code · days_since_invoice · applies — 제안 금액 없음: so_credit_issue(p, false) 의 fee_suggested 가 답 · 0-7) · already_credited · 어휘 셋
--    ⚠️ qty_credited 는 so_credit_issue :1055~1056 의 식을 복사한 것(0-5) — ⬜ so_credit_line_returned(so_invoice_line_id) 류 함수로 떼고 발행 창구와 함께 부른다(다음 차수 · 정본 ⬜)
-- 권한: 뷰 revoke all from anon, authenticated, public → grant select · 새 RPC 둘 stable invoker · revoke public, anon → grant execute authenticated · 재발행 여섯의 grant 는 그대로(create or replace)
-- ⚠️ 순서: C0 → R1 뷰 → 재발행 여섯(detail 이 뷰를 읽는다) → R3 · 쓰기 문 없음 · lateral 은 읽기 함수만 · 시험 자료는 직접 insert(크레딧 시퀀스 무접촉)

-- ═══ C0 so_credit_remaining ═══
create function public.so_credit_remaining(p_credit_id uuid) returns numeric
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when c.status = 'cancelled' then 0
              else c.total - coalesce((select sum(a.amount) from public.so_credit_alloc a where a.credit_id = c.id and a.voided_at is null), 0) end
  from public.so_credit c where c.id = p_credit_id;
$$;
comment on function public.so_credit_remaining(uuid) is '⭐ 크레딧 남은 금액(진 빚 남은 몫)의 정본(so-credit-read-1 C0 · 2026-09-25) — total − Σ활성 so_credit_alloc(인보이스 붙임 + 환불 붙임 · voided_at is null) · 취소된 크레딧 0 · so_credit_detail · so_credit_alloc_add · so_credit_attach · so_payment_refund · so_invoice_issue ② · so_customer_balance(owed_credit = Σ) · so_credit_list 가 이 함수를 부른다(식을 다시 짜지 마라)';
revoke all on function public.so_credit_remaining(uuid) from public, anon;
grant execute on function public.so_credit_remaining(uuid) to authenticated;

-- ═══ R1 so_credit_list — 크레딧 한 장 = 한 행 ═══
create view public.so_credit_list
  with (security_invoker = true) as
with al as (   -- 살아 있는 붙임(voided_at is null) — 인보이스 쪽과 환불 쪽을 가른다
  select a.credit_id,
         sum(a.amount) filter (where a.invoice_id is not null)        as applied_to_invoices,
         sum(a.amount) filter (where a.refund_payment_id is not null) as refunded,
         string_agg(i.invoice_number, ', ' order by i.invoice_number) filter (where a.invoice_id is not null) as invoice_numbers_applied
  from public.so_credit_alloc a left join public.so_invoice i on i.id = a.invoice_id
  where a.voided_at is null
  group by a.credit_id
)
select c.id, c.credit_number, c.status, c.issued_on, c.customer_id, cu.name as customer_name, c.currency_id, c.currency_code,
       c.reason, c.note, c.warehouse_id, c.warehouse_name,
       c.invoice_id, i.invoice_number, c.cin7_invoice_number, c.cin7_order_number, c.origin_invoice_on,
       c.lines_amount, c.fee_amount, c.tax_amount, c.total,
       coalesce(al.applied_to_invoices, 0) as applied_to_invoices,
       coalesce(al.refunded, 0)            as refunded,
       r.remaining,
       al.invoice_numbers_applied,
       c.cancelled_at, c.cancel_note, c.created_at,
       (select s.name from public.ims_staff s where s.id = c.issued_by) as issued_by_name,
       (c.credit_number || ' ' || coalesce(cu.name, '') || ' ' || coalesce(i.invoice_number, '') || ' ' || coalesce(c.cin7_invoice_number, '') || ' ' || coalesce(al.invoice_numbers_applied, '') || ' ' || c.reason || ' ' || coalesce(c.note, '')) as search_text
from public.so_credit c
left join public.customer cu on cu.id = c.customer_id
left join public.so_invoice i on i.id = c.invoice_id
left join al on al.credit_id = c.id
cross join lateral (select public.so_credit_remaining(c.id) as remaining) r;   -- 읽기 함수(stable)를 lateral 에서 한 번 — 쓰기 창구가 아니다
comment on view public.so_credit_list is
  '⭐ 크레딧 노트 목록(so-credit-read-1 R1 · 2026-09-25) — 한 장 한 행 · PostgREST 로 표처럼 · security_invoker. applied_to_invoices = Σ활성 인보이스 붙임 · refunded = Σ활성 환불 붙임 · remaining = so_credit_remaining(id)(취소 0) · applied + refunded + remaining = total(issued) · invoice_number = 원판매(되짚은) 인보이스 · invoice_numbers_applied = 붙은 인보이스들 · search_text = 번호 · 손님 · 원판매 인보이스 · Cin7 번호 · 붙은 인보이스 · 사유 · 메모';
revoke all on public.so_credit_list from anon, authenticated, public;
grant select on public.so_credit_list to authenticated;

-- ═══ C1·R2 so_credit_detail 재발행 — 마지막 정의 20260925012354:1258~1284 · 바이트 그대로 · 바뀐 줄 1(remaining → C0) · 더한 줄(R2 키 넷) · create → create or replace ═══
create or replace function public.so_credit_detail(p_credit_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_cr public.so_credit%rowtype;
begin
  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  if not found then raise exception 'Credit note not found'; end if;
  return jsonb_build_object(
    'credit', to_jsonb(v_cr),
    'customer_name', (select c.name from public.customer c where c.id = v_cr.customer_id),
    'invoice_number', (select i.invoice_number from public.so_invoice i where i.id = v_cr.invoice_id),
    'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.line_no), '[]'::jsonb) from public.so_credit_line l where l.credit_id = v_cr.id),
    'allocations', (select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at), '[]'::jsonb) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null),
    'applied', (select coalesce(sum(a.amount), 0) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null),
    'remaining', public.so_credit_remaining(v_cr.id),                                                                                   -- so-credit-read-1 C1: 식의 한 곳(옛 식은 C0 정의 그대로였다)
    -- so-credit-read-1 R2(2026-09-25) — 더한 키 넷(옛 키 아홉은 그대로 · 부르는 곳 0 이지만 규칙대로 더하기만)
    'credit_row', (select to_jsonb(v) from public.so_credit_list v where v.id = v_cr.id),
    'allocations_all', (select coalesce(jsonb_agg(jsonb_build_object('alloc_id', a.id, 'invoice_id', a.invoice_id, 'invoice_number', i.invoice_number, 'invoice_status', i.status,
                                                                     'refund_payment_id', a.refund_payment_id, 'refund_paid_on', p.paid_on, 'refund_method', p.method, 'refund_reference', p.reference, 'refund_status', p.status,
                                                                     'amount', a.amount, 'source', a.source, 'voided_at', a.voided_at, 'void_note', a.void_note, 'created_at', a.created_at) order by a.created_at), '[]'::jsonb)
                        from public.so_credit_alloc a left join public.so_invoice i on i.id = a.invoice_id left join public.so_payment p on p.id = a.refund_payment_id
                        where a.credit_id = v_cr.id),
    'open_invoices', (select coalesce(jsonb_agg(jsonb_build_object('invoice_id', l.id, 'invoice_number', l.invoice_number, 'issued_on', l.issued_on, 'due_on', l.due_on, 'due_unknown', l.due_unknown,
                                                                   'total', l.total, 'remaining', l.remaining, 'days_overdue', l.days_overdue, 'so_numbers', l.so_numbers,
                                                                   'attached_from_this_credit', coalesce((select sum(a.amount) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.invoice_id = l.id and a.voided_at is null), 0)) order by l.issued_on, l.invoice_number), '[]'::jsonb)
                      from public.so_invoice_list l
                      where l.is_open and l.bill_to_customer_id = v_cr.customer_id and l.currency_id = v_cr.currency_id),
    'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_cr.customer_id) b where b.currency_id = v_cr.currency_id),
    'ledger', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'occurred_on', g.occurred_on, 'sku', g.sku, 'warehouse', g.warehouse, 'bin', g.bin, 'qty_delta', g.qty_delta, 'line_ref', g.line_ref, 'cost', g.raw -> 'cost') order by g.id), '[]'::jsonb)
                 from public.inv_ledger g where g.doc_type = 'creditnote' and g.doc_number = v_cr.credit_number and g.source = 'ims'),
    'layers', (select coalesce(jsonb_agg(jsonb_build_object('id', y.id, 'sku', y.sku, 'warehouse', y.warehouse, 'qty', y.qty, 'unit_cost', y.unit_cost, 'cost_source', y.cost_source, 'parent_layer_id', y.parent_layer_id,
                                                            'consumed', (select coalesce(sum(k.qty), 0) from public.inv_layer_consume k where k.layer_id = y.id)) order by y.id), '[]'::jsonb)
               from public.inv_layer y where y.origin_type = 'creditnote' and y.doc_number = v_cr.credit_number));
end;
$$;
comment on function public.so_credit_detail(uuid) is '크레딧 노트 읽기 한 창구(ⓒ1) — invoker · stable(RLS select · 로그인) · credit · lines · 활성 allocations · applied · remaining(진 빚 남은 몫) · ledger(credit_in 행 · raw.cost) · layers(원가 레이어 · 소진량)';
revoke all on function public.so_credit_detail(uuid) from public, anon;
grant execute on function public.so_credit_detail(uuid) to authenticated;

-- ═══ C1 so_credit_alloc_add 재발행 — 마지막 정의 20260925014413:15~56 · 바뀐 줄 1(:33) ═══
create or replace function public.so_credit_alloc_add(p_credit_id uuid, p_invoice_id uuid, p_amount numeric, p_source text, p_staff uuid, p_refund_payment_id uuid default null) returns public.so_credit_alloc
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
  v_rem := public.so_credit_remaining(v_c.id);                                                                                    -- so-credit-read-1 C1
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

-- ═══ C1 so_credit_attach 재발행 — 마지막 정의 20260925014413:59~84 · 바뀐 줄 1(:78) ═══
create or replace function public.so_credit_attach(p_credit_id uuid, p_allocs jsonb) returns jsonb
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
                            'credit_remaining', public.so_credit_remaining(v_c.id),                                                            -- so-credit-read-1 C1
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_c.customer_id) b where b.currency_id = v_c.currency_id));
end;
$$;
comment on function public.so_credit_attach(uuid, jsonb) is '⭐ 크레딧을 인보이스에 붙이기(8-g 소진 · 판정 6 sales · ⓒ2) — definer · 첫 줄 ims_require_write(sales) · [{invoice_id, amount}] 를 so_credit_alloc_add(manual · 한도 둘)로 · 하나라도 막히면 전체 거부 · 반환 applied · allocations · credit_remaining · balance';
revoke all on function public.so_credit_attach(uuid, jsonb) from public, anon;
grant execute on function public.so_credit_attach(uuid, jsonb) to authenticated;

-- ═══ C1 so_payment_refund 재발행 — 마지막 정의 20260925014413:493~578 · 바뀐 줄 1(:557) ═══
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
    select c.id, c.credit_number, public.so_credit_remaining(c.id) as remaining                                                          -- so-credit-read-1 C1
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

-- ═══ C1 so_invoice_issue 재발행 — 마지막 정의 20260925201614:19~256 · 바뀐 줄 1(:205 · ② 크레딧 커서) ═══
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
      select c.id, c.credit_number, c.issued_on, public.so_credit_remaining(c.id) as remaining                                            -- so-credit-read-1 C1
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

-- ═══ C1 so_customer_balance 재발행 — 마지막 정의 20260925195701:29~77 · 바뀐 줄 1(:50 · cred CTE → Σ C0) ═══
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
    select c.currency_id, sum(public.so_credit_remaining(c.id)) as owed                                                                     -- so-credit-read-1 C1(⬜2): Σtotal − Σ(Σalloc) = Σ(total − Σalloc) · issued 만 · 검증 「여덟 칸 전후 동일」
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

-- ═══ R3 so_credit_prepare — 인보이스에서 크레딧을 낼 때 화면이 한 번 읽는 준비물(읽기 · 쓰지 않는다) ═══
create function public.so_credit_prepare(p_invoice_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with inv as (
    select i.*, cu.name as customer_name, public.ims_today() as today,
           (select s.location_id from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = i.id order by o.so_number limit 1) as wh_id   -- 발행 창구 :996 과 같은 줄(원판매 첫 오더의 창고)
    from public.so_invoice i left join public.customer cu on cu.id = i.bill_to_customer_id
    where i.id = p_invoice_id
  ),
  cfg as (
    select (select nullif(k.value, '')::int     from public.inv_config k where k.key = 'so_credit_restock_fee_days')         as fee_days,
           (select nullif(k.value, '')::numeric from public.inv_config k where k.key = 'so_credit_restock_fee_pct')          as fee_pct,
           (select nullif(k.value, '')          from public.inv_config k where k.key = 'so_credit_restock_fee_account_code') as fee_account_code
  )
  select jsonb_build_object(
    'invoice', jsonb_build_object('id', inv.id, 'invoice_number', inv.invoice_number, 'status', inv.status, 'creditable', (inv.status = 'issued'), 'issued_on', inv.issued_on,
                                  'days_since_invoice', inv.today - inv.issued_on, 'customer_id', inv.bill_to_customer_id, 'customer_name', inv.customer_name, 'bill_to_name', inv.bill_to_name,
                                  'currency_id', inv.currency_id, 'currency_code', inv.currency_code, 'total', inv.total, 'remaining', public.so_invoice_remaining(inv.id)),
    'warehouse', (select jsonb_build_object('warehouse_id', w.id, 'warehouse_name', w.name, 'is_active', w.is_active) from public.ref_warehouse w where w.id = inv.wh_id),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                'so_invoice_line_id', l.id, 'line_no', l.line_no, 'kind', l.kind, 'sku', l.sku, 'description', l.description, 'unit', l.unit, 'pack_factor', l.pack_factor,
                'qty_sold', l.qty,
                -- ⚠️ 복사 식(0-5): so_credit_issue 20260925012354:1055~1056 의 「이미 반품」과 글자까지 같아야 창구가 거부하지 않는다 · ⬜ so_credit_line_returned(so_invoice_line_id) 류 함수로 떼고 발행 창구와 함께 부른다(다음 차수)
                'qty_credited', case when l.kind = 'product' then (select coalesce(sum(cl.qty_returned), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') end,
                'qty_returnable', case when l.kind = 'product' then l.qty - (select coalesce(sum(cl.qty_returned), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') end,
                'amount', l.amount,
                -- charge 줄의 「이미 반품」은 금액(발행 창구 :1099~1103 의 v_already 와 같은 뜻)
                'amount_credited', case when l.kind = 'charge' then (select coalesce(sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') end,
                'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'rate_pct', io.rate_pct, 'tax_rule', io.tax_rule, 'tax_amount', l.tax_amount, 'account_code', l.account_code,
                'product_id', sl.product_id, 'stock_product_id', coalesce(pr.parent_product_id, pr.id), 'stock_sku', coalesce(pp.sku, pr.sku),
                -- 되돌려 놓을 칸 기본값 — 발행 창구 :1077 과 같은 길(ims_last_bin(낱개 제품, 창고) · ④a1 뒤로 보관용 아님 먼저 · 없으면 null → 사람이 고르거나 안 돌아옴으로)
                'restock_bin_default', case when l.kind = 'product' and inv.wh_id is not null and pr.id is not null
                                            then public.ims_last_bin(array[coalesce(pr.parent_product_id, pr.id)], inv.wh_id) -> coalesce(pr.parent_product_id, pr.id)::text end)
              order by l.line_no), '[]'::jsonb)
              from public.so_invoice_line l
              join public.so_invoice_order io on io.id = l.invoice_order_id
              left join public.so_line sl on sl.id = l.so_line_id
              left join public.product pr on pr.id = sl.product_id
              left join public.product pp on pp.id = pr.parent_product_id
              where l.invoice_id = inv.id and l.kind in ('product', 'charge')),
    'restock_fee', jsonb_build_object('days', cfg.fee_days, 'pct', cfg.fee_pct, 'account_code', cfg.fee_account_code,
                                      'days_since_invoice', inv.today - inv.issued_on,
                                      'applies', (cfg.fee_days is not null and inv.today - inv.issued_on > cfg.fee_days),
                                      'note', 'notice only — the preview so_credit_issue(p, false) proposes the amount (fee_suggested); the account must be picked when account_code is null'),
    'already_credited', (select coalesce(jsonb_agg(jsonb_build_object('credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'reason', c.reason, 'total', c.total, 'remaining', public.so_credit_remaining(c.id)) order by c.credit_number), '[]'::jsonb)
                         from public.so_credit c where c.invoice_id = inv.id),
    'vocab', jsonb_build_object('reasons', '["customer_return","damaged","billing_error","other"]'::jsonb,
                                'not_restocked_reasons', '["damaged","b_grade","not_returned","other"]'::jsonb,
                                'line_kinds', '["product","freight","tax","other","restocking_fee"]'::jsonb)
  )
  from inv, cfg;
$$;
comment on function public.so_credit_prepare(uuid) is
  '⭐ 크레딧 발행 준비물(so-credit-read-1 R3 · 2026-09-25) — 읽기(stable · invoker) · 없는 id → null · invoice(며칠 지났나 · creditable) · warehouse(원판매 첫 오더의 창고 · 발행 창구 기본과 같다) · lines(product·charge · qty_sold · qty_credited(issued 크레딧 줄 합 · 발행 창구 :1055 와 같은 식 · ⬜ 함수로 뗀다) · qty_returnable · amount_credited(charge) · rate_pct · restock_bin_default(ims_last_bin · 낱개 · 그 창고)) · restock_fee(days · pct · account_code · days_since_invoice · applies — 제안 금액은 미리 보기 fee_suggested) · already_credited · vocab 셋';
revoke all on function public.so_credit_prepare(uuid) from public, anon;
grant execute on function public.so_credit_prepare(uuid) to authenticated;
