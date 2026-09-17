-- ─────────────────────────────────────────────────────────────
-- ⑤ 크레딧 노트 자동 번호 + 공급처 참조 번호 (테스트 DB Asung-IMS · 2026-09-16 저녁)
--   po_invoice 에 칸 둘        supplier_ref_number(공급처가 보내온 크레딧 노트 번호 · 참조) · credit_po_id(⭐ 번호를 낸 발주 · 채번의 축)
--   po_credit_next_number()    채번 — CN-<PO번호>(둘째부터 -2 · -3 …) · 발주가 없으면 CN-<연도>-<네자리>
--   po_invoice_create          크레딧이고 번호를 안 주면 자동으로 붙인다 · 인보이스는 그대로 번호 필수
--   po_invoice_list · po_invoice_detail · po_list   새 칸 노출 · 검색(doc_numbers)에 공급처 참조 번호
--
-- 정본: docs/design/po-module.md §11-c(번호 · 「PO-12345 는 우리 번호일 뿐」) · §11-g(인보이스·크레딧) · §13
-- 앞 정의: 20260916200000(po_invoice_create · po_invoice_list · po_invoice_detail) · 20260916190000(po_list) — create or replace 로 이어짓는다
-- 선례: 20260916144201 po_next_number()(시퀀스 + 함수 · authenticated USAGE) — ⚠️ 이번 채번은 시퀀스가 아니다(아래)
-- 지시서: ~/asung/prompts/po-credit-number.md · 검토 이견 1~14(2026-09-16 저녁 · 전부 받음 · ⓒ 실측으로 예상값 성립)
-- ⚠️ 파일명 — 앞 파일이 200000 이라 그 뒤에 서도록 210000.
--
-- ⭐⭐ 왜 — 인보이스 번호는 공급처의 것이고, 크레딧 번호는 우리 것이다 (Caleb 실측 2026-09-16)
--   인보이스는 공급처가 번호를 붙여 보내오고 그 번호로 문의해 온다 ⇒ 사람이 넣는다 · 없으면 거부(그대로).
--   크레딧은 순서가 반대다 — 「리시빙을 하면서 못 받은 것을 supplier credit 으로 돌린다. 그 내역을 알려 주면 공급처가 진짜 크레딧 노트를 보내 주거나 그냥 금액을 까 준다」
--   ⇒ 만들 때 번호가 없다 · 우리가 먼저 붙인다 · 끝까지 공급처 번호가 안 오는 경우도 있다(금액만 까 주는 경우).
--   ⇒ 공급처가 진짜 크레딧 노트를 보내오면 그 번호는 **참조**(supplier_ref_number)로 남긴다. 우리 번호를 갈아치우지 않는다 — 그동안 주고받은 기록이 안 맞게 된다(§11-c 와 같은 판단).
--
-- ⭐ 번호 규칙 (Caleb 2026-09-16)
--   발주에 붙는 크레딧   CN-<po_number>          첫째는 꼬리 없음 · 둘째부터 CN-<po_number>-2 · -3 …
--                        📌 발주 분할(첫째에도 a)과 반대다 — 발주는 갈라진 사실이 신호라 꼬리가 표시가 되지만, 크레딧은 대개 하나뿐이라 늘 -1 이 붙으면 아무것도 말하지 않는다
--   발주가 없는 조정 크레딧  CN-<연도>-<네자리>   연도는 문서 날짜(invoice_date · 안 주면 오늘)의 연도 · 해가 바뀌면 0001 부터 · ⭐ 전 공급처 통합(검토 이견 7 — 공급처별이면 CN-2026-0001 이 여러 곳에 생겨 대화에서 헷갈린다)
--   사람이 번호를 주면 그대로 쓴다(검토 이견 8) — 공급처가 먼저 보내온 크레딧 노트를 사후 입력하는 실물이 있다(Cin7 23537005816) · warnings credit_number_manual
--
-- ⭐⭐ 「그 발주의 몇 번째인가」를 어떻게 세나 (검토 이견 4·5·6·7)
--   축     credit_po_id — 만들 때의 발주를 문서에 박는다. 줄로 유추(credit_for → 줄 → 발주)하면 ① 줄이 빈 조정 크레딧에서 안 되고 ② 인보이스가 발주 둘에 걸치면 정해지지 않고 ③ 줄을 고치면 이미 붙은 번호의 근거가 사라진다.
--          ⚠️ §11-g 「머리에 PO 칸을 두지 않는다」와 긴장이 있다 — 이 칸은 「걸린 발주」가 아니라 **채번의 축**이다. 관계는 여전히 줄(po_invoice_line.po_line_id)이 말한다. po_detail credits[] · po_list credit_count 는 줄로 센다(무변).
--          채우는 규칙: p_po_id 가 있으면 그것 · 없고 credit_for 가 있으면 그 인보이스의 줄이 가리키는 발주가 **정확히 하나**일 때 그것 · 둘 이상이면 null + warnings credit_po_ambiguous(→ 조정 번호) · 줄이 없으면 null(→ 조정 번호).
--   셈     「최대 꼬리 + 1」 — 건수를 세지 않고 번호를 읽는다. CN-<po> 가 없으면 그것 · 있으면 CN-<po>-<n> 의 n 최댓값 + 1(없으면 2). 조정 번호도 같다(CN-<연도>-% 의 최댓값 + 1).
--          ⭐ 취소된 크레딧도 셈에 든다 — 빼면 같은 번호가 다시 나서 ① 유니크(supplier, doc_kind, number)에 걸리고 ② 공급처에 이미 알려 준 번호가 다른 문서를 가리킨다. 번호가 건너뛰는 것은 PO 시퀀스의 빈 번호와 같은 판단으로 허용.
--          ⚠️ 초안을 지우면 그 번호가 다시 날 수 있다 — 지운 초안은 공급처에 안 갔다고 본다(짐작).
--   동시성  ⭐ 트랜잭션 advisory lock(pg_advisory_xact_lock · 채번 직전 · 트랜잭션 끝에 저절로 풀린다) — 두 사람이 동시에 만들어도 차례로 센다. 재시도 루프보다 짧고, 조정 번호는 유니크가 공급처별이라 재시도로는 전역 중복을 못 잡는다.
--          ⚠️ 이 레포의 첫 advisory lock 이다(2026-09-16 grep 선례 없음). 시퀀스로 못 내는 이유 — 발주마다 다시 세고 해마다 0001 로 돌아간다.
--   ⚠️ 접두어 CN- 로만 센다 — 시험 데이터의 인보이스 번호가 'PO-02002'(발주 번호를 그대로 넣은 것 · Caleb)여도 셈에 안 든다. 다만 공급처가 우연히 그런 번호를 쓰면 인보이스 PO-02002 와 크레딧 CN-PO-02002 가 나란히 서서 헷갈릴 수 있다.
--      막을 방법은 없다(공급처 번호는 우리가 못 정한다) — 화면이 Kind 칩으로 가른다.
--
-- ⭐ 미리 보기(p_commit=false)에도 번호를 보여 준다(검토 이견 9) — 「이 번호로 만들어진다(예정)」 · number_source(given · auto_po · auto_year) · warnings number_is_provisional(미리 보기만 · commit 때 다시 센다)
-- ⭐ 참조 번호는 PostgREST 한 칸으로 · confirmed 에서도 넣는다(검토 이견 11) — 장부(줄·할인·총액)를 안 건드리고, 참조를 나중에 받는 것이 정상 흐름이다. 뒷단이 머리를 막지 않으므로 그대로 된다.
-- ❌ 유니크 없음(검토 이견 2) — 공급처 크레딧 노트 한 장이 우리 크레딧 여럿을 덮을 수 있다(짐작 · 「금액을 까 준다」와 같은 결). ❌ po_detail(190000) credits[] 는 이번에 무변(검토 이견 12 — 크레딧을 깊게 보는 화면은 invoices.html).
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS · --db-url 이 보이면 테스트)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① po_invoice — 칸 둘 + CHECK + 인덱스 + 주석 ═══
alter table public.po_invoice
  add column if not exists supplier_ref_number text,                                                        -- 공급처가 보내온 크레딧 노트 번호(참조 · 나중에 · 없을 수 있다)
  add column if not exists credit_po_id        uuid references public.po (id) on delete no action;          -- ⭐ 번호를 낸 발주(채번의 축) · 관계가 아니다

alter table public.po_invoice
  add constraint po_invoice_credit_only_ck check (doc_kind = 'credit' or (supplier_ref_number is null and credit_po_id is null));   -- 인보이스는 둘 다 못 쓴다(같은 행 안 · CHECK 가능)

create index if not exists po_invoice_credit_po_id_idx on public.po_invoice (credit_po_id);   -- FK 인덱스(§5) · 채번이 「이 발주의 크레딧 번호들」을 읽는 축

comment on column public.po_invoice.supplier_ref_number is '⭐ 공급처가 보내온 크레딧 노트 번호 — **참조**다(2026-09-16 저녁). 크레딧은 우리가 먼저 만들고 번호를 붙이므로(리시빙에서 못 받은 것을 돌린다 · Caleb) 공급처 번호는 나중에 오거나 안 온다(금액만 까 주는 경우). 우리 번호(invoice_number)를 갈아치우지 않는다 — 주고받은 기록이 안 맞게 된다(§11-c 와 같은 판단). 크레딧 전용(CHECK po_invoice_credit_only_ck) · 인보이스는 invoice_number 가 이미 공급처 번호다. 유니크 없음 — 한 장이 우리 크레딧 여럿을 덮을 수 있다(짐작). PostgREST 한 칸으로 · confirmed 뒤에도 넣는다(장부를 안 건드린다). 검색: po_invoice_list · po_list.doc_numbers';
comment on column public.po_invoice.credit_po_id        is '⭐ 이 크레딧의 **번호를 낸 발주** → po(id) · 크레딧 전용(CHECK) · nullable. ⚠️ 「걸린 발주」가 아니라 채번의 축이다 — 관계는 여전히 줄(po_invoice_line.po_line_id)이 말한다(§11-g 머리에 PO 칸 없음은 그대로). 채우는 규칙(po_invoice_create): p_po_id → 없으면 credit_for 인보이스의 줄이 가리키는 발주가 정확히 하나일 때 그것 → 아니면 null(조정 번호 CN-<연도>-<n> · 둘 이상이면 warnings credit_po_ambiguous). 사람이 번호를 준 크레딧(CN-AMP-778812-1)은 null 로 남는다(backfill 없음)';
comment on column public.po_invoice.invoice_number      is '⭐ 인보이스: 공급처가 준 번호(INV 2142773 · 0094204-IN) — 공급처의 것 · 사람이 넣는다 · 없으면 거부. ⭐ 크레딧: **우리 번호**(2026-09-16 저녁 · Caleb) — 크레딧은 우리가 먼저 만든다. 안 주면 po_invoice_create 가 자동으로 붙인다: 발주에 붙으면 CN-<po_number>(둘째부터 -2 · -3 · 첫째는 꼬리 없음 — 대개 하나뿐이라) · 발주가 없으면 CN-<연도>-<네자리>(해마다 0001 · 전 공급처 통합). 사람이 주면 그대로(사후 입력 실물 · credit_number_manual). 공급처가 보내온 진짜 크레딧 노트 번호는 supplier_ref_number 에. unique (supplier_id, doc_kind, invoice_number) — [③차] 종류를 넣은 이유는 20260916175003. ⚠️ 공급처가 우연히 PO-02002 같은 번호를 쓰면 크레딧 CN-PO-02002 와 나란히 서서 헷갈릴 수 있다 — 막을 방법이 없다(공급처 번호는 우리가 못 정한다) · 화면이 종류 칩으로 가른다';

-- ═══ ② po_credit_next_number(p_po_id, p_year) — 크레딧 채번 (⚠️ 시퀀스 아님 · 최대 꼬리 + 1 · advisory lock) ═══
-- 부르는 쪽(po_invoice_create)이 같은 트랜잭션에서 insert 까지 한다 — lock 은 트랜잭션 끝에 풀리므로 채번과 insert 사이에 다른 사람이 못 끼어든다.
create function public.po_credit_next_number(p_po_id uuid, p_year integer)
returns text
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_base text;
  v_next int;
  v_po_number text;
begin
  perform pg_advisory_xact_lock(hashtext('po_credit_number'));                  -- ⭐ 채번 직렬화 · 트랜잭션 끝까지

  if p_po_id is not null then
    select po_number into v_po_number from public.po where id = p_po_id;
    if v_po_number is null then
      raise exception 'PO % not found — cannot number the credit note', p_po_id;
    end if;
    v_base := 'CN-' || v_po_number;
    if not exists (select 1 from public.po_invoice where doc_kind = 'credit' and invoice_number = v_base) then
      return v_base;                                                             -- 첫째 · 꼬리 없음(Caleb)
    end if;
    -- 둘째부터 — CN-<po>-<n> 의 n 최댓값 + 1(없으면 2) · 취소된 것도 든다 · 공급처 무관(발주는 한 공급처)
    select coalesce(max(substring(invoice_number from length(v_base) + 2)::int), 1) + 1 into v_next
    from public.po_invoice
    where doc_kind = 'credit' and invoice_number ~ ('^' || v_base || '-[0-9]+$');
    return v_base || '-' || v_next;
  end if;

  -- 조정 크레딧 · CN-<연도>-<네자리> · 전 공급처 통합 · 해마다 0001
  v_base := 'CN-' || p_year || '-';
  select coalesce(max(substring(invoice_number from length(v_base) + 1)::int), 0) + 1 into v_next
  from public.po_invoice
  where doc_kind = 'credit' and invoice_number ~ ('^' || v_base || '[0-9]+$');
  return v_base || lpad(v_next::text, 4, '0');
end;
$$;
comment on function public.po_credit_next_number(uuid, integer) is '⑤ 크레딧 노트 채번(2026-09-16 저녁 · Caleb 규칙). 발주가 있으면 CN-<po_number>(첫째 꼬리 없음 · 둘째부터 -2 · -3 … = 그 모양 번호의 최댓값 + 1 · 취소된 것도 든다) · 없으면 CN-<연도>-<네자리>(전 공급처 통합 · 최댓값 + 1 · 해마다 0001). ⚠️ 시퀀스가 아니다 — 발주마다 다시 세고 해마다 돌아간다. ⭐ pg_advisory_xact_lock 으로 채번을 직렬화한다(레포 첫 사용 · 트랜잭션 끝에 풀림) — 부르는 쪽이 같은 트랜잭션에서 insert 까지 해야 뜻이 있다. 접두어 CN- 로만 센다(인보이스 번호 PO-02002 는 안 든다)';

revoke all on function public.po_credit_next_number(uuid, integer) from public, anon;
grant execute on function public.po_credit_next_number(uuid, integer) to authenticated;

-- ═══ ③ po_invoice_create — 크레딧이고 번호를 안 주면 자동 (200000 정의를 그대로 가져와 바뀐 곳만) ═══
-- 바뀐 곳: p_invoice_number default null · 크레딧 번호 자동(po_credit_next_number) · credit_po_id 결정 · insert 에 credit_po_id · 반환에 number_source · credit_po_id · credit_po_number ·
--          warnings 새 값 credit_number_manual · number_is_provisional(미리 보기만) · credit_po_ambiguous
-- POST /rest/v1/rpc/po_invoice_create
--   크레딧(번호 자동)  {"p_doc_kind":"credit","p_credit_for_invoice_id":"<uuid>","p_commit":false}   → invoice_number 'CN-PO-02001a' · number_source 'auto_po' · warnings ['number_is_provisional', …]
--   조정 크레딧        {"p_doc_kind":"credit","p_supplier_id":"<uuid>","p_commit":true}               → 'CN-2026-0001' · 'auto_year'
--   인보이스           번호 필수 — 그대로
create or replace function public.po_invoice_create(
  p_doc_kind              text,                       -- 'invoice' | 'credit'
  p_invoice_number        text    default null,       -- ⭐ 인보이스: 필수(공급처 번호) · 크레딧: 안 주면 자동(우리 번호) · 주면 그대로
  p_po_id                 uuid    default null,       -- 인보이스: 필수 · 크레딧: 머리 원천 둘째 · ⭐ 크레딧 번호의 축(credit_po_id)
  p_credit_for_invoice_id uuid    default null,       -- 크레딧만 · 있으면 줄 자동 채우기(차이) · 그 인보이스의 발주가 하나면 그것이 번호의 축
  p_supplier_id           uuid    default null,       -- 크레딧 머리 원천 셋째(조정 크레딧 · CN-<연도>-<n>)
  p_invoice_date          date    default null,       -- 안 주면 오늘 · 조정 번호의 연도
  p_due_date              date    default null,
  p_total_amount          numeric default null,       -- ⭐ 찍힌 총액 · 안 주면 0 + 경고
  p_copy_discounts        boolean default true,       -- 인보이스만
  p_commit                boolean default false       -- false = 미리 보기
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff        uuid;
  v_num          text;
  v_num_src      text;
  v_kind_label   text;
  v_po           public.po%rowtype;
  v_for          public.po_invoice%rowtype;
  v_sup          public.supplier%rowtype;
  v_source       text;
  v_supplier_id  uuid;  v_currency_id uuid;  v_rate numeric;  v_pt_id uuid;  v_pt_name text;
  v_sup_name     text;  v_cur_code text;
  v_credit_po_id uuid;  v_credit_po_number text;  v_po_n int;
  v_exists       int;
  v_inv_id       uuid;
  v_warn         text[] := '{}';
  v_lines        jsonb  := '[]'::jsonb;
  v_discs        jsonb  := '[]'::jsonb;
  v_n            int := 0;
  v_ins          int := 0;
  v_ok           int := 0;
  v_disc_n       int := 0;
  r              record;
  v_verdict      text;
  v_qty          numeric;
  v_full         boolean;
  v_msgs         text[];
begin
  if p_doc_kind not in ('invoice', 'credit') then
    raise exception 'p_doc_kind must be ''invoice'' or ''credit'' — nothing was saved';
  end if;
  v_kind_label := case p_doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;
  v_num := nullif(regexp_replace(coalesce(p_invoice_number, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
  if p_doc_kind = 'invoice' and v_num is null then
    raise exception 'Invoice number is required — it is the supplier''s number — nothing was saved';   -- ⭐ 인보이스 번호는 공급처의 것
  end if;

  -- ── 머리의 원천 (200000 그대로) ──
  if p_doc_kind = 'invoice' then
    if p_po_id is null then
      raise exception 'An invoice starts from a PO — p_po_id is required — nothing was saved';
    end if;
    if p_credit_for_invoice_id is not null then
      raise exception 'p_credit_for_invoice_id is for credit notes only — nothing was saved';
    end if;
  end if;

  if p_credit_for_invoice_id is not null then
    select * into v_for from public.po_invoice where id = p_credit_for_invoice_id;
    if not found then
      raise exception 'Invoice % not found (credit_for) — nothing was saved', p_credit_for_invoice_id;
    end if;
    if v_for.doc_kind <> 'invoice' then
      raise exception 'Credit note cannot be for another credit note (%) — nothing was saved', v_for.invoice_number;
    end if;
    v_supplier_id := v_for.supplier_id; v_currency_id := v_for.currency_id; v_rate := v_for.exchange_rate;
    v_pt_id := v_for.payment_term_id;   v_pt_name := v_for.payment_term_name;   v_source := 'invoice';
  end if;

  if p_po_id is not null then
    select * into v_po from public.po where id = p_po_id;
    if not found then
      raise exception 'PO % not found — nothing was saved', p_po_id;
    end if;
    if v_source is null then
      v_supplier_id := v_po.supplier_id; v_currency_id := v_po.currency_id; v_rate := v_po.exchange_rate;
      v_pt_id := v_po.payment_term_id;   v_pt_name := v_po.payment_term_name;   v_source := 'po';
    elsif v_po.supplier_id <> v_supplier_id then
      raise exception 'PO % belongs to a different supplier than invoice % — nothing was saved', v_po.po_number, v_for.invoice_number;
    end if;
  end if;

  if v_source is null then
    if p_supplier_id is null then
      raise exception 'A credit note needs one of: p_credit_for_invoice_id, p_po_id or p_supplier_id — nothing was saved';
    end if;
    select * into v_sup from public.supplier where id = p_supplier_id;
    if not found then
      raise exception 'Supplier % not found — nothing was saved', p_supplier_id;
    end if;
    v_supplier_id := v_sup.id; v_pt_id := v_sup.payment_term_id; v_pt_name := v_sup.payment_term_name; v_source := 'supplier';
    v_currency_id := v_sup.currency_id;
    if v_currency_id is null then
      select c.id into v_currency_id from public.ref_currency c join public.inv_config k on k.key = 'base_currency' and k.value = c.code;
      if v_currency_id is null then
        raise exception 'Supplier has no currency and inv_config.base_currency does not point at a ref_currency row — nothing was saved';
      end if;
      v_warn := array_append(v_warn, 'currency_defaulted');
    end if;
  end if;

  select s.name into v_sup_name from public.supplier s where s.id = v_supplier_id;
  select c.code into v_cur_code from public.ref_currency c where c.id = v_currency_id;

  -- ── ⭐ 크레딧 — 번호의 축(credit_po_id)과 번호 ──
  if p_doc_kind = 'credit' then
    if p_po_id is not null then
      v_credit_po_id := v_po.id;
    elsif p_credit_for_invoice_id is not null then
      -- 그 인보이스의 줄이 가리키는 발주 — 정확히 하나면 그것 · 둘 이상이면 정하지 않는다(조정 번호 + 경고) · 줄이 없으면 null
      select count(distinct pl.po_id), (array_agg(distinct pl.po_id))[1] into v_po_n, v_credit_po_id
      from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id
      where il.po_invoice_id = p_credit_for_invoice_id;
      if coalesce(v_po_n, 0) > 1 then
        v_credit_po_id := null;
        v_warn := array_append(v_warn, 'credit_po_ambiguous');                  -- 화면이 p_po_id 를 골라 주면 그 발주 번호로 간다
      end if;
    end if;
    if v_credit_po_id is not null then
      select po_number into v_credit_po_number from public.po where id = v_credit_po_id;
    end if;

    if v_num is null then
      -- ⭐ 우리 번호 — advisory lock 안에서 센다(트랜잭션 끝까지 유지 → 아래 insert 까지 직렬)
      v_num := public.po_credit_next_number(v_credit_po_id, extract(year from coalesce(p_invoice_date, current_date))::int);
      v_num_src := case when v_credit_po_id is not null then 'auto_po' else 'auto_year' end;
      if not p_commit then v_warn := array_append(v_warn, 'number_is_provisional'); end if;   -- commit 때 다시 센다 — 사이에 끼면 달라진다
    else
      v_num_src := 'given';
      v_warn := array_append(v_warn, 'credit_number_manual');                   -- 사후 입력(공급처가 먼저 보낸 크레딧 노트) — 그대로 쓴다 · 덮지 않는다
    end if;
  else
    v_num_src := 'given';
  end if;

  -- ── 번호 중복 — 미리 보기는 경고 · commit 은 읽을 문장으로 거부 ──
  select count(*) into v_exists from public.po_invoice
   where supplier_id = v_supplier_id and doc_kind = p_doc_kind and invoice_number = v_num;
  if v_exists > 0 then
    if p_commit then
      raise exception '% % already exists for % — nothing was saved', v_kind_label, v_num, v_sup_name;
    end if;
    v_warn := array_append(v_warn, 'invoice_number_exists');
  end if;
  if p_total_amount is null then v_warn := array_append(v_warn, 'total_amount_missing'); end if;
  if p_doc_kind = 'credit' and p_due_date is not null then v_warn := array_append(v_warn, 'due_date_on_credit'); end if;

  -- ── commit: 머리 한 행 ──
  if p_commit then
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff is null then
      raise exception 'No active staff record for this login — nothing was saved';
    end if;
    insert into public.po_invoice (supplier_id, doc_kind, invoice_number, invoice_date, due_date, payment_term_id, payment_term_name,
                                   currency_id, exchange_rate, total_amount, status, created_by, credit_for_invoice_id, credit_po_id)
    values (v_supplier_id, p_doc_kind, v_num, coalesce(p_invoice_date, current_date), p_due_date, v_pt_id, v_pt_name,
            v_currency_id, v_rate, coalesce(p_total_amount, 0), 'draft', v_staff, p_credit_for_invoice_id, v_credit_po_id)
    returning id into v_inv_id;
  end if;

  -- ── 줄 (200000 그대로) ──
  if p_doc_kind = 'invoice' then
    for r in select * from public.po_uninvoiced_lines(p_po_id) loop
      v_n := v_n + 1; v_msgs := '{}'; v_qty := null; v_full := false;
      if r.remaining_qty > 0 then
        v_verdict := 'ok'; v_qty := r.remaining_qty; v_full := (r.remaining_qty = r.qty_ea); v_ok := v_ok + 1;
        if r.invoiced_qty > 0 then v_msgs := array_append(v_msgs, format('%s already invoiced on other invoice(s) — remaining %s', r.invoiced_qty, r.remaining_qty)); end if;
        if not v_full then v_msgs := array_append(v_msgs, 'partial — entered unit reset to EA'); end if;
        if p_commit then
          v_ins := v_ins + 1;
          insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable,
                                              entered_unit_product_id, entered_qty, entered_pack_factor)
          values (v_inv_id, v_ins, 'goods', r.po_line_id, v_qty, r.unit_price, true,
                  case when v_full then r.entered_unit_product_id end,
                  case when v_full then r.entered_qty end,
                  case when v_full then r.entered_pack_factor end);
        end if;
      else
        v_verdict := 'fully_invoiced';
        v_msgs := array_append(v_msgs, case when r.remaining_qty < 0 then 'over-invoiced — check earlier invoices' else 'nothing left to invoice' end);
      end if;
      v_lines := v_lines || jsonb_build_object(
        'n', v_n, 'verdict', v_verdict, 'po_line_id', r.po_line_id, 'po_number', v_po.po_number, 'po_line_no', r.line_no, 'sku', r.sku,
        'qty_ordered', r.qty_ea, 'invoiced_qty', r.invoiced_qty, 'remaining_qty', r.remaining_qty,
        'qty_ea', v_qty, 'unit_price', case when v_verdict = 'ok' then r.unit_price end,
        'line_no', case when v_verdict = 'ok' then (case when p_commit then v_ins else v_ok end) end,
        'inserted', (p_commit and v_verdict = 'ok'), 'message', array_to_string(v_msgs, ' · '));
    end loop;
    if v_ok = 0 then v_warn := array_append(v_warn, 'no_uninvoiced_lines'); end if;

    if p_copy_discounts then
      for r in select d.seq, d.name, d.percent, d.supplier_discount_id from public.po_discount d where d.po_id = p_po_id order by d.seq loop
        v_disc_n := v_disc_n + 1;
        if p_commit then
          insert into public.po_invoice_discount (po_invoice_id, seq, name, percent, supplier_discount_id)
          values (v_inv_id, r.seq, r.name, r.percent, r.supplier_discount_id);
        end if;
        v_discs := v_discs || jsonb_build_object('seq', r.seq, 'name', r.name, 'percent', r.percent, 'supplier_discount_id', r.supplier_discount_id, 'inserted', p_commit);
      end loop;
      if v_disc_n > 0 then v_warn := array_append(v_warn, 'discounts_copied_from_po'); end if;
    end if;

  elsif p_credit_for_invoice_id is not null then
    for r in
      select il.po_line_id, il.qty_ea as invoice_qty, il.unit_price, pl.line_no as po_line_no, x.po_number, pr.sku,
             coalesce((select sum(rl.qty_ea) from public.po_receipt_line rl where rl.po_line_id = il.po_line_id), 0) as received_qty,
             (select count(distinct x2.po_invoice_id) from public.po_invoice_line x2 join public.po_invoice i2 on i2.id = x2.po_invoice_id
               where x2.po_line_id = il.po_line_id and x2.line_kind = 'goods' and i2.doc_kind = 'invoice' and i2.status <> 'cancelled'
                 and i2.id <> p_credit_for_invoice_id)::int as other_invoices
      from public.po_invoice_line il
      join public.po_line pl on pl.id = il.po_line_id
      join public.po x on x.id = pl.po_id
      join public.product pr on pr.id = pl.product_id
      where il.po_invoice_id = p_credit_for_invoice_id and il.line_kind = 'goods'
      order by il.line_no
    loop
      v_n := v_n + 1; v_msgs := '{}'; v_qty := r.invoice_qty - r.received_qty;
      if r.other_invoices > 0 then v_msgs := array_append(v_msgs, format('line_has_other_invoices (%s) — difference may belong to another invoice', r.other_invoices)); end if;
      if v_qty > 0 then
        v_verdict := 'ok'; v_ok := v_ok + 1;
        if p_commit then
          v_ins := v_ins + 1;
          insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable)
          values (v_inv_id, v_ins, 'goods', r.po_line_id, v_qty, r.unit_price, true);
        end if;
      elsif v_qty = 0 then
        v_verdict := 'no_difference'; v_msgs := array_append(v_msgs, 'invoiced = received');
      else
        v_verdict := 'over_received'; v_msgs := array_append(v_msgs, 'received more than invoiced — not a credit (§11-i difference)');
      end if;
      v_lines := v_lines || jsonb_build_object(
        'n', v_n, 'verdict', v_verdict, 'po_line_id', r.po_line_id, 'po_number', r.po_number, 'po_line_no', r.po_line_no, 'sku', r.sku,
        'invoice_qty', r.invoice_qty, 'received_qty', r.received_qty, 'diff_qty', v_qty,
        'qty_ea', case when v_verdict = 'ok' then v_qty end, 'unit_price', case when v_verdict = 'ok' then r.unit_price end,
        'line_no', case when v_verdict = 'ok' then (case when p_commit then v_ins else v_ok end) end,
        'inserted', (p_commit and v_verdict = 'ok'), 'message', array_to_string(v_msgs, ' · '));
    end loop;
    if v_ok = 0 then v_warn := array_append(v_warn, 'no_qty_difference'); end if;
  end if;

  return jsonb_build_object(
    'committed', p_commit, 'id', v_inv_id, 'doc_kind', p_doc_kind,
    'invoice_number', v_num, 'number_source', v_num_src,                              -- ⭐ 미리 보기에도 번호(예정) · given | auto_po | auto_year
    'credit_po_id', v_credit_po_id, 'credit_po_number', v_credit_po_number,           -- ⭐ 번호의 축(크레딧만 · 인보이스는 null)
    'header_source', v_source,
    'supplier_id', v_supplier_id, 'supplier_name', v_sup_name, 'currency_id', v_currency_id, 'currency_code', v_cur_code,
    'payment_term_name', v_pt_name, 'total_amount', coalesce(p_total_amount, 0),
    'line_count', case when p_commit then v_ins else v_ok end, 'lines', v_lines,
    'discounts', v_discs, 'discounts_copied', v_disc_n,
    'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception '% % already exists for % — nothing was saved', v_kind_label, v_num, coalesce(v_sup_name, 'this supplier');
end;
$$;
comment on function public.po_invoice_create(text, text, uuid, uuid, uuid, date, date, numeric, boolean, boolean) is '⑤ 인보이스·크레딧 초안 만들기(미리 보기 = 같은 모양 · p_commit). ⭐ [2026-09-16 저녁] 인보이스 번호는 공급처의 것(필수 · 사람이) · 크레딧 번호는 우리 것 — 안 주면 자동(po_credit_next_number · CN-<po> / CN-<연도>-<n> · advisory lock) · 주면 그대로(credit_number_manual). credit_po_id = p_po_id → credit_for 인보이스의 발주가 하나면 그것 → 아니면 null(credit_po_ambiguous). 머리는 credit_for → PO → 공급처 순. 인보이스 줄 = 미청구 수량 · po_discount 복사 제안. 크레딧(credit_for) 줄 = 인보이스 수량 − 입고 합 > 0 · 없으면 빈 초안 + no_qty_difference. total 안 주면 0 + 경고. 미리 보기에 번호(예정 · number_is_provisional). 정본 po-module §11-c·e·g · 2026-09-16';

revoke all on function public.po_invoice_create(text, text, uuid, uuid, uuid, date, date, numeric, boolean, boolean) from public, anon;
grant execute on function public.po_invoice_create(text, text, uuid, uuid, uuid, date, date, numeric, boolean, boolean) to authenticated;

-- ═══ ④ po_invoice_list — 기존 31칸 그대로 + 뒤에 3칸 (create or replace 규칙 · 순서·타입 무변) ═══
create or replace view public.po_invoice_list
  with (security_invoker = true) as
with pos as (
  select il.po_invoice_id,
         count(distinct pl.po_id)::int                                   as po_count,
         string_agg(distinct x.po_number, ' ' order by x.po_number)      as po_numbers
  from public.po_invoice_line il
  join public.po_line pl on pl.id = il.po_line_id
  join public.po x on x.id = pl.po_id
  group by il.po_invoice_id
)
select
  i.id, i.doc_kind, i.invoice_number, i.invoice_date, i.due_date, i.status,
  i.supplier_id, s.name as supplier_name,
  i.currency_id, cur.code as currency_code, i.exchange_rate,
  i.payment_term_name,
  i.total_amount,
  round(m.factor, 6)      as discount_factor,
  m.computed_total, m.diff, m.payable_net,
  m.alloc_total,
  m.credit_total, m.unpaid, m.remaining,
  m.line_count,
  coalesce(pos.po_count, 0) as po_count,
  pos.po_numbers,
  i.credit_for_invoice_id, f.invoice_number as credit_for_number,
  i.confirmed_at, i.cancelled_at, i.note, i.created_at, i.updated_at,
  -- ── 새 3칸 (2026-09-16 저녁) ──
  i.supplier_ref_number,                              -- 공급처가 보내온 크레딧 노트 번호(참조) · 검색 .or 에 한 항 더
  i.credit_po_id,                                     -- 번호를 낸 발주(채번의 축)
  cp.po_number as credit_po_number
from public.po_invoice i
join public.po_invoice_money m on m.id = i.id
join public.supplier s on s.id = i.supplier_id
join public.ref_currency cur on cur.id = i.currency_id
left join public.po_invoice f on f.id = i.credit_for_invoice_id
left join public.po cp on cp.id = i.credit_po_id
left join pos on pos.po_invoice_id = i.id;

comment on view public.po_invoice_list is '⑤ 인보이스·크레딧 목록 — PostgREST 로 표처럼(§10-j 3-a). 돈은 po_invoice_money(식 없음) · po_numbers = 줄이 가리키는 발주 번호 모음(검색) · credit_for_number. ⭐ [2026-09-16 저녁] + supplier_ref_number(공급처 참조 번호 · 검색 .or 에 더한다 — 공급처가 그들 번호로 물어온다) · credit_po_id · credit_po_number(번호를 낸 발주). security_invoker. 정본 po-module §11-c·g · 2026-09-16';

revoke all on public.po_invoice_list from anon;
grant select on public.po_invoice_list to authenticated;

-- ═══ ⑤ po_invoice_detail — header 에 셋 (200000 정의 그대로 · header 만 바뀜) ═══
create or replace function public.po_invoice_detail(p_invoice_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with i as (
  select * from public.po_invoice where id = p_invoice_id
),
m as (
  select * from public.po_invoice_money where id = p_invoice_id
),
lines as (
  select il.*,
         pl.po_id, x.po_number, pl.line_no as po_line_no, pl.qty_ea as po_qty_ea, pl.unit_price as po_unit_price,
         pr.sku, pr.name as product_name, up.sku as entered_unit_sku,
         round(il.qty_ea * il.unit_price, 2) as amount,
         case when il.po_line_id is not null
              then coalesce((select sum(rl.qty_ea) from public.po_receipt_line rl where rl.po_line_id = il.po_line_id), 0) end as received_qty,
         case when il.po_line_id is not null
              then coalesce((select sum(x2.qty_ea) from public.po_invoice_line x2 join public.po_invoice i2 on i2.id = x2.po_invoice_id
                              where x2.po_line_id = il.po_line_id and x2.line_kind = 'goods' and i2.doc_kind = 'invoice' and i2.status <> 'cancelled'
                                and i2.id <> p_invoice_id), 0) end as other_invoiced_qty
  from public.po_invoice_line il
  left join public.po_line pl on pl.id = il.po_line_id
  left join public.po x on x.id = pl.po_id
  left join public.product pr on pr.id = pl.product_id
  left join public.product up on up.id = il.entered_unit_product_id
  where il.po_invoice_id = p_invoice_id
),
shares as (
  select l.po_id, l.po_number, x.status as po_status, count(*)::int as line_count,
         coalesce(sum(l.qty_ea) filter (where l.line_kind = 'goods'), 0) as qty_ea,
         coalesce(sum(l.amount), 0) as amount
  from lines l join public.po x on x.id = l.po_id
  where l.po_id is not null
  group by l.po_id, l.po_number, x.status
),
cred as (
  select c.id, c.invoice_number, c.invoice_date, c.status, c.total_amount, c.supplier_ref_number, cm.payable_net as credit_net, cm.alloc_total as used
  from public.po_invoice c join public.po_invoice_money cm on cm.id = c.id
  where c.credit_for_invoice_id = p_invoice_id
),
pay as (
  select pa.id as alloc_id, pa.amount as alloc_amount, pm.id as payment_id, pm.paid_on, pm.reference, pm.amount as payment_amount, pm.discount_taken,
         cur.code as currency_code, acc.code as account_code, acc.name as account_name, st.name as paid_by_name
  from public.po_payment_alloc pa
  join public.po_payment pm on pm.id = pa.po_payment_id
  join public.ref_currency cur on cur.id = pm.currency_id
  left join public.ref_account acc on acc.id = pm.account_id
  left join public.ims_staff st on st.id = pm.paid_by
  where pa.po_invoice_id = p_invoice_id
)
select case when not exists (select 1 from i) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', i.id, 'doc_kind', i.doc_kind, 'invoice_number', i.invoice_number, 'invoice_date', i.invoice_date, 'due_date', i.due_date, 'status', i.status,
      'supplier_ref_number', i.supplier_ref_number,                                          -- ⭐ 새 · 공급처가 보내온 크레딧 노트 번호(참조) · PostgREST 로 고친다
      'credit_po_id', i.credit_po_id, 'credit_po_number', cp.po_number,                     -- ⭐ 새 · 번호를 낸 발주
      'supplier_id', i.supplier_id, 'supplier_name', s.name,
      'currency_id', i.currency_id, 'currency_code', cur.code, 'exchange_rate', i.exchange_rate,
      'payment_term_id', i.payment_term_id, 'payment_term_name', coalesce(i.payment_term_name, pt.name),
      'total_amount', i.total_amount,
      'credit_for_invoice_id', i.credit_for_invoice_id, 'credit_for_number', f.invoice_number, 'credit_for_status', f.status,
      'created_by_name', cb.name, 'confirmed_by_name', fb.name,
      'confirmed_at', i.confirmed_at, 'cancelled_at', i.cancelled_at, 'note', i.note, 'created_at', i.created_at, 'updated_at', i.updated_at)
    from i
    join public.supplier s on s.id = i.supplier_id
    join public.ref_currency cur on cur.id = i.currency_id
    left join public.ref_payment_term pt on pt.id = i.payment_term_id
    left join public.po_invoice f on f.id = i.credit_for_invoice_id
    left join public.po cp on cp.id = i.credit_po_id
    left join public.ims_staff cb on cb.id = i.created_by
    left join public.ims_staff fb on fb.id = i.confirmed_by
  ),
  'money', (
    select jsonb_build_object(
      'line_count', m.line_count, 'goods_sum', m.goods_sum, 'other_sum', m.other_sum, 'goods_payable', m.goods_payable, 'other_payable', m.other_payable,
      'discount_factor', round(m.factor, 6),
      'computed_total', m.computed_total, 'diff', m.diff,
      'payable_net', m.payable_net,
      'alloc_total', m.alloc_total,
      'credit_total', m.credit_total, 'unpaid', m.unpaid, 'remaining', m.remaining)
    from m
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'line_no', line_no, 'line_kind', line_kind, 'po_line_id', po_line_id, 'po_id', po_id, 'po_number', po_number, 'po_line_no', po_line_no,
      'sku', sku, 'product_name', product_name, 'description', description,
      'qty_ea', qty_ea, 'entered_unit_sku', entered_unit_sku, 'entered_unit_product_id', entered_unit_product_id, 'entered_qty', entered_qty, 'entered_pack_factor', entered_pack_factor,
      'unit_price', unit_price, 'amount', amount, 'is_payable', is_payable, 'note', note,
      'po_qty_ea', po_qty_ea, 'po_unit_price', po_unit_price,
      'received_qty', received_qty, 'other_invoiced_qty', other_invoiced_qty,
      'qty_diff', case when line_kind = 'goods' then qty_ea - received_qty end)
      order by line_no)
    from lines), '[]'::jsonb),
  'discounts', coalesce((
    select jsonb_agg(jsonb_build_object('id', d.id, 'seq', d.seq, 'name', d.name, 'percent', d.percent, 'supplier_discount_id', d.supplier_discount_id, 'note', d.note) order by d.seq)
    from public.po_invoice_discount d where d.po_invoice_id = p_invoice_id), '[]'::jsonb),
  'po_shares', coalesce((
    select jsonb_agg(jsonb_build_object('po_id', po_id, 'po_number', po_number, 'po_status', po_status, 'line_count', line_count, 'qty_ea', qty_ea, 'amount', amount) order by po_number)
    from shares), '[]'::jsonb),
  'credits', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'credit_number', invoice_number, 'credit_date', invoice_date, 'status', status, 'total_amount', total_amount,
                                        'supplier_ref_number', supplier_ref_number,                                   -- ⭐ 새
                                        'credit_net', credit_net, 'used', used)
      order by invoice_date, invoice_number)
    from cred), '[]'::jsonb),
  'payments', coalesce((
    select jsonb_agg(jsonb_build_object('alloc_id', alloc_id, 'payment_id', payment_id, 'paid_on', paid_on, 'reference', reference, 'alloc_amount', alloc_amount,
                                        'payment_amount', payment_amount, 'discount_taken', discount_taken, 'currency_code', currency_code,
                                        'account_code', account_code, 'account_name', account_name, 'paid_by_name', paid_by_name)
      order by paid_on, reference)
    from pay), '[]'::jsonb),
  'warnings', (
    select coalesce(jsonb_agg(w), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when i.doc_kind = 'credit' and i.credit_for_invoice_id is not null and m.alloc_total > 0 then 'attached_and_used' end,
        case when f.doc_kind = 'credit' then 'credit_for_is_credit' end,
        case when f.supplier_id is not null and f.supplier_id <> i.supplier_id then 'credit_for_other_supplier' end,
        case when i.total_amount = 0 then 'total_amount_zero' end,
        case when m.diff <> 0 then 'total_differs_from_lines' end,
        case when m.line_count = 0 then 'no_lines' end
      ], null)) as w
      from i cross join m left join public.po_invoice f on f.id = i.credit_for_invoice_id) t
  )
) end;
$$;
comment on function public.po_invoice_detail(uuid) is '⑤ 인보이스·크레딧 상세 — 한 장을 깊게(invoices.html). header · money(po_invoice_money 그대로) · lines[](발주 대조 · qty_diff) · discounts[] · po_shares[] · credits[] · payments[] · warnings[]. ⭐ [2026-09-16 저녁] header 에 supplier_ref_number · credit_po_id · credit_po_number · credits[] 에 supplier_ref_number. 없는 id → null. 2026-09-16';

revoke all on function public.po_invoice_detail(uuid) from public, anon;
grant execute on function public.po_invoice_detail(uuid) to authenticated;

-- ═══ ⑥ po_list — doc_numbers 에 공급처 참조 번호와 「번호를 낸 발주」 경로를 더한다 (190000 정의 그대로 · nums CTE 두 갈래만 · 칸 집합 무변) ═══
create or replace view public.po_list
  with (security_invoker = true) as
with l as (
  select po_id,
         count(*)::int                                      as line_count,
         coalesce(sum(qty_ea), 0)                           as ordered_qty,
         coalesce(sum(round(qty_ea * unit_price, 2)), 0)    as subtotal
  from public.po_line
  group by po_id
),
r as (
  select pl.po_id, coalesce(sum(rl.qty_ea), 0) as received_qty
  from public.po_receipt_line rl
  join public.po_line pl on pl.id = rl.po_line_id
  group by pl.po_id
),
d as (
  select po_id, public.po_mul(1 - percent / 100) as factor
  from public.po_discount
  group by po_id
),
c as (
  select po_id, coalesce(sum(amount), 0) as charge_total
  from public.po_charge_alloc
  group by po_id
),
sp as (
  select split_from_id as po_id, count(*)::int as split_to_count
  from public.po
  where split_from_id is not null
  group by split_from_id
),
il as (
  select x.po_invoice_id, pl.po_id,
         coalesce(sum(x.qty_ea)                          filter (where x.line_kind = 'goods'), 0) as goods_qty,
         coalesce(sum(round(x.qty_ea * x.unit_price, 2)) filter (where x.line_kind = 'goods'), 0) as goods_amount
  from public.po_invoice_line x
  join public.po_line pl on pl.id = x.po_line_id
  group by x.po_invoice_id, pl.po_id
),
inv as (
  select x.po_id,
         count(*)::int                        as invoice_count,
         coalesce(sum(x.goods_qty), 0)        as invoiced_qty,
         coalesce(sum(x.goods_amount), 0)     as invoiced_total,
         coalesce(sum(m.alloc_total), 0)      as paid,
         coalesce(sum(m.unpaid), 0)           as unpaid
  from il x
  join public.po_invoice i on i.id = x.po_invoice_id
  join public.po_invoice_money m on m.id = i.id
  where i.doc_kind = 'invoice' and i.status <> 'cancelled'
  group by x.po_id
),
cred as (                                     -- 걸린 크레딧(줄 · credit_for) — ⚠️ credit_po_id 는 채번의 축이라 여기 안 센다(po_detail credits[] 와 같은 집합)
  select po_id, count(*)::int as credit_count
  from (
    select x.po_id, x.po_invoice_id as credit_id
    from il x join public.po_invoice k on k.id = x.po_invoice_id
    where k.doc_kind = 'credit' and k.status <> 'cancelled'
    union
    select x.po_id, k.id
    from public.po_invoice k
    join il x on x.po_invoice_id = k.credit_for_invoice_id
    where k.doc_kind = 'credit' and k.status <> 'cancelled'
  ) u
  group by po_id
),
chg as (
  select a.po_id,
         count(*)::int                 as charge_count,
         coalesce(sum(m.paid), 0)      as paid,
         coalesce(sum(m.unpaid), 0)    as unpaid
  from public.po_charge_alloc a
  join public.po_charge c on c.id = a.po_charge_id
  join public.po_charge_money m on m.id = c.id
  where c.status <> 'cancelled'
  group by a.po_id
),
nums as (                                     -- 검색용 문서 번호 모음(취소 포함) · ⭐ [2026-09-16 저녁] + 공급처 참조 번호 · 번호를 낸 발주 경로(줄 없는 크레딧도 그 발주에서 찾힌다)
  select po_id, string_agg(distinct num, ' ' order by num) as doc_numbers
  from (
    select x.po_id, k.invoice_number as num
    from il x join public.po_invoice k on k.id = x.po_invoice_id
    union
    select x.po_id, k.invoice_number
    from public.po_invoice k join il x on x.po_invoice_id = k.credit_for_invoice_id
    where k.doc_kind = 'credit'
    union
    select x.po_id, k.supplier_ref_number
    from il x join public.po_invoice k on k.id = x.po_invoice_id
    where k.supplier_ref_number is not null
    union
    select x.po_id, k.supplier_ref_number
    from public.po_invoice k join il x on x.po_invoice_id = k.credit_for_invoice_id
    where k.supplier_ref_number is not null
    union
    select k.credit_po_id, k.invoice_number
    from public.po_invoice k where k.credit_po_id is not null
    union
    select k.credit_po_id, k.supplier_ref_number
    from public.po_invoice k where k.credit_po_id is not null and k.supplier_ref_number is not null
    union
    select a.po_id, c.charge_number
    from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id
  ) u
  group by po_id
)
select
  p.id,
  p.po_number,
  p.status,
  p.order_date,
  p.supplier_id,
  s.name                                                       as supplier_name,
  cur.code                                                     as currency_code,
  coalesce(l.line_count, 0)                                    as line_count,
  coalesce(l.ordered_qty, 0)                                   as ordered_qty,
  coalesce(r.received_qty, 0)                                  as received_qty,
  coalesce(l.subtotal, 0)                                      as subtotal,
  round(coalesce(d.factor, 1), 6)                              as discount_factor,
  round(coalesce(l.subtotal, 0) * coalesce(d.factor, 1), 2)    as net_total,
  coalesce(c.charge_total, 0)                                  as charge_total,
  sf.po_number                                                 as split_from_number,
  coalesce(sp.split_to_count, 0)                               as split_to_count,
  p.confirmed_at,
  p.closed_at,
  p.cancelled_at,
  p.note,
  p.created_at,
  p.updated_at,
  p.required_by,
  coalesce(inv.invoice_count, 0)                               as invoice_count,
  coalesce(inv.invoiced_qty, 0)                                as invoiced_qty,
  coalesce(inv.invoiced_total, 0)                              as invoiced_total,
  coalesce(cred.credit_count, 0)                               as credit_count,
  coalesce(chg.charge_count, 0)                                as charge_count,
  coalesce(inv.paid, 0) + coalesce(chg.paid, 0)                as paid_total,
  coalesce(inv.unpaid, 0) + coalesce(chg.unpaid, 0)            as unpaid_total,
  nums.doc_numbers,
  case when coalesce(l.line_count, 0) = 0                                                   then 'none'
       when p.status = 'draft' or (p.status = 'cancelled' and p.confirmed_at is null)       then 'partial'
       else 'done' end                                         as order_phase,
  case when coalesce(inv.invoiced_qty, 0) = 0                                               then 'none'
       when inv.invoiced_qty < coalesce(l.ordered_qty, 0)                                   then 'partial'
       else 'done' end                                         as invoice_phase,
  case when coalesce(r.received_qty, 0) = 0                                                 then 'none'
       when r.received_qty < coalesce(l.ordered_qty, 0)                                     then 'partial'
       else 'done' end                                         as receipt_phase,
  case when coalesce(chg.charge_count, 0) = 0                                               then 'none'
       else 'done' end                                         as charge_phase,
  case when coalesce(inv.invoice_count, 0) + coalesce(chg.charge_count, 0) = 0              then 'none'
       when coalesce(inv.unpaid, 0) + coalesce(chg.unpaid, 0) > 0
            then case when coalesce(inv.paid, 0) + coalesce(chg.paid, 0) > 0 then 'partial' else 'none' end
       else 'done' end                                         as payment_phase
from public.po p
join public.supplier     s   on s.id   = p.supplier_id
join public.ref_currency cur on cur.id = p.currency_id
left join l    on l.po_id    = p.id
left join r    on r.po_id    = p.id
left join d    on d.po_id    = p.id
left join c    on c.po_id    = p.id
left join public.po sf on sf.id = p.split_from_id
left join sp   on sp.po_id   = p.id
left join inv  on inv.po_id  = p.id
left join cred on cred.po_id = p.id
left join chg  on chg.po_id  = p.id
left join nums on nums.po_id = p.id;

comment on view public.po_list is '⑤ 발주 목록 — PostgREST 로 표처럼 읽는다(§10-j 3-a). security_invoker. 기존 22칸(164539) + 넓은 목록 14칸(190000 · 국면 다섯 · doc_numbers · unpaid_total …) 그대로. ⭐ [2026-09-16 저녁] doc_numbers 에 크레딧의 공급처 참조 번호(supplier_ref_number)와 「번호를 낸 발주」(credit_po_id) 경로를 더했다 — 공급처가 그들 번호로 물어오면 발주도 찾힌다 · 줄 없는 크레딧(CN-PO-02002 조정)도 그 발주에서 찾힌다. credit_count 는 그대로 줄·credit_for 로 센다(채번 축은 관계가 아니다). ⚠️⚠️ paid_total·unpaid_total 은 문서 기준 — 세로로 더하면 두 번 센다. 정본 po-module §13 · §13-f · 2026-09-16';

revoke all on public.po_list from anon;
grant select on public.po_list to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 화면(asung-ims · 대화 Claude)에서 바뀌는 것
-- ─────────────────────────────────────────────────────────────
--   po_invoice_create   크레딧은 p_invoice_number 를 **안 준다**(자동) — 주면 그대로 + warnings credit_number_manual
--                       반환 + number_source('given' | 'auto_po' | 'auto_year') · credit_po_id · credit_po_number
--                       미리 보기(p_commit:false)의 invoice_number 는 예정 번호 · warnings 에 number_is_provisional — 「CN-PO-02002 (provisional)」로 그린다 · commit 결과의 번호가 정본
--                       warnings 새 값 credit_po_ambiguous — 다중 발주 인보이스에서 축을 못 정했다 → 화면이 p_po_id 를 골라 다시 부르거나 조정 번호로 둔다
--                       인보이스는 무변(번호 필수 · 없으면 「Invoice number is required — it is the supplier's number …」)
--   po_invoice_list     + supplier_ref_number · credit_po_id · credit_po_number
--                       검색 .or 에 supplier_ref_number.ilike 한 항 더 — 공급처가 그들 번호로 물어온다
--                       크레딧 행: 번호 아래 「ref <supplier_ref_number>」 · 「for <credit_for_number>」 나란히
--   po_invoice_detail   header + supplier_ref_number · credit_po_id · credit_po_number · credits[] + supplier_ref_number
--                       ⭐ Supplier ref 입력칸 — **confirmed 에서도** 보인다(장부를 안 건드린다 · 참조를 나중에 받는 것이 정상 흐름)
--                       저장: sb.from("po_invoice").update({ supplier_ref_number: v }).eq("id", id).select("id")  (PostgREST 한 칸 · imsSaved)
--   po_list.doc_numbers 공급처 참조 번호로도 발주가 찾힌다 — 화면 변경 없음(이미 doc_numbers.ilike 를 쓴다)
--   po.html Create 모달  Kind 가 Invoice 하나로 줄었으니(이견 2) 이 파일과 무관 · 크레딧 만들기 버튼(invoices.html · 이견 1)은 번호 칸을 두지 않는다(자동)

-- ─────────────────────────────────────────────────────────────
-- 검증 (Caleb · 테스트 DB · 예상값은 ⓒ 실측(2026-09-16 저녁)에서 — po_invoice 3행: AMP-778812 invoice · CN-AMP-778812-1 credit · PO-02002 invoice(draft · HoC · 인보이스 번호가 발주 번호와 같은 시험 데이터))
--   ⚠️ commit 은 auth.uid() 를 보므로 psql 에서는 request.jwt.claims 를 심는다 — 미리 보기·채번 함수·뷰·detail 은 그냥 된다
-- ─────────────────────────────────────────────────────────────
-- ⓪ 적용 뒤
--   \d po_invoice   → supplier_ref_number text · credit_po_id uuid · CHECK po_invoice_credit_only_ck · 인덱스 po_invoice_credit_po_id_idx
--   select invoice_number, doc_kind, supplier_ref_number, credit_po_id from po_invoice order by 1;   → 3행 전부 null · null (backfill 없음)
--   select pg_get_functiondef('public.po_invoice_create'::regproc) like '%p_invoice_number text DEFAULT NULL%';   → true
-- ① 채번 함수만 (lock 은 문장 끝에 풀린다)
--   select po_credit_next_number((select id from po where po_number='PO-02002'), 2026);    → CN-PO-02002
--   select po_credit_next_number((select id from po where po_number='PO-02001a'), 2026);   → CN-PO-02001a   (CN-AMP-778812-1 은 접두어가 달라 셈에 안 든다)
--   select po_credit_next_number(null, 2026);                                              → CN-2026-0001
-- ② 미리 보기 — PO-02002 의 인보이스에서 크레딧 (ⓓ)
--   select jsonb_pretty(po_invoice_create('credit', null, null, (select id from po_invoice where invoice_number='PO-02002' and doc_kind='invoice'), null, null, null, null, true, false));
--   예상  invoice_number 'CN-PO-02002' · number_source 'auto_po' · credit_po_number 'PO-02002' · header_source 'invoice' · House of Cheatham
--         lines[] = 그 인보이스 goods 줄 수만큼 · 입고 0 이면 전부 verdict ok · diff_qty = 인보이스 수량 · warnings ['number_is_provisional','total_amount_missing']
--   AMP-778812 에서: invoice_number 'CN-PO-02001a' · lines 3 전부 no_difference · warnings ['number_is_provisional','total_amount_missing','no_qty_difference']
--   공급처만: select … ('credit', null, null, null, (select supplier_id from po where po_number='PO-02002'), …, false) → 'CN-2026-0001' · 'auto_year' · credit_po_id null · lines []
--   번호를 주면: ('credit', 'CN-X', null, <AMP-778812 id>, …) → 'CN-X' · 'given' · warnings 에 credit_number_manual
--   인보이스 번호 없이: ('invoice', null, (select id from po where po_number='PO-02007'), …) → 예외 「Invoice number is required — it is the supplier's number …」
-- ③ commit (jwt 심고) — PO-02002 의 인보이스에서 두 번
--   첫째 → invoice_number 'CN-PO-02002' · credit_po_id = PO-02002 · warnings 에 number_is_provisional 없음
--   둘째 → 'CN-PO-02002-2'  ·  셋째 → 'CN-PO-02002-3'
--   둘째를 cancelled 로 바꾸고 넷째 → 'CN-PO-02002-4' (취소된 것도 셈에 든다)  ·  셋째를 delete 하고 다섯째 → 'CN-PO-02002-4' 가 다시 난다(지운 초안은 번호를 돌려준다 · 설계대로)
--   select po_number, credit_count, doc_numbers from po_list where po_number='PO-02002';   → credit_count = 취소 안 된 크레딧 수(줄 기준) · doc_numbers 에 'CN-PO-02002 CN-PO-02002-2 … PO-02002 10039192310530'
--   update po_invoice set supplier_ref_number='23537005816' where invoice_number='CN-PO-02002';   → 성공(draft 든 confirmed 든)
--   select doc_numbers from po_list where po_number='PO-02002';   → '23537005816' 이 들어 있다
--   select invoice_number, supplier_ref_number, credit_po_number from po_invoice_list where doc_kind='credit' order by 1;   → CN-PO-02002 · 23537005816 · PO-02002
--   select po_invoice_detail((select id from po_invoice where invoice_number='CN-PO-02002')) -> 'header' ->> 'supplier_ref_number';   → 23537005816
--   update po_invoice set supplier_ref_number='x' where invoice_number='AMP-778812';   → CHECK 위반(인보이스는 못 쓴다)
--   확인 뒤 지운다(검증 데이터를 남기려면 두어도 된다 — 다음 채번은 이어 붙는다)
-- ④ 조정 번호 — 공급처만으로 commit 두 번 → CN-2026-0001 · CN-2026-0002 (다른 공급처로 만들어도 이어진다 · 전 공급처 통합)
--   select po_invoice_create('credit', null, null, null, <sid>, '2027-01-05', null, null, true, false) ->> 'invoice_number';   → CN-2027-0001 (문서 날짜의 연도)
-- ⑤ 동시성(선택) — psql 두 세션에서 begin; select po_credit_next_number(<PO-02002 id>, 2026); 를 동시에 → 둘째 세션이 첫째의 commit/rollback 까지 기다린다(advisory lock)
