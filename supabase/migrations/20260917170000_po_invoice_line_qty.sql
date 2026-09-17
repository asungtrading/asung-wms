-- ─────────────────────────────────────────────────────────────
-- ⑤ 인보이스 만들 때 줄마다 수량을 정한다 — po_invoice_create 에 p_line_qty (테스트 DB Asung-IMS · 2026-09-17)
--
-- ⭐ 왜(Caleb 실무 2026-09-17) — 물건은 한 번에 오는데 공급처가 인보이스만 여러 장으로 나눠 보낸다(부분 입고가 아니다 · PO 는 안 갈라진다 · 한 PO 에 여러 장 · §11-g 실물 PO-01010).
--   지금은 미청구 수량이 전 라인 채워져 나와 안 실린 품목을 만든 뒤 하나씩 지운다(열 중 셋만 청구됐으면 일곱 번). ⇒ 만들기 전에 수량을 정한다 · 0 인 줄은 만들지 않는다.
--   실무가 「공급처 인보이스를 보며 숫자를 옮기는 일」이라 안 적힌 품목은 자연히 비고, 부분 청구된 품목은 어차피 수량을 고쳐야 한다 — 두 일이 한 자리에서 끝난다.
--   ⚠️ 다음 장은 저절로 맞는다 — po_uninvoiced_lines(주문 − 취소 안 된 인보이스 goods 합)가 그대로다. 첫 장에 400 만 넣으면 둘째 장은 200 · 안 넣은 품목은 주문 수량 그대로. **그 함수는 건드리지 않는다.**
--
-- 정본: docs/design/po-module.md §11-g 「인보이스·크레딧을 만드는 법」(줄 = 미청구 수량 · 미리 보기) · §11-b(넘긴 수량은 초과 입고와 같은 모양이라 사후 구별이 안 된다 — 저장 전에 막는다) · §13-h RPC 열
-- 앞 정의: ⚠️ **20260916210000**(크레딧 자동 채번 판 — 200000 이 아니다 · 이견 1). 그 정의를 그대로 가져와 「── 줄 ── 인보이스」 블록과 반환 조립만 바꿨다. 크레딧 가지 · 채번 · 머리 원천 · 할인 복사 · 총액 · 번호 중복은 무변
-- ⚠️⚠️ 시그니처가 바뀐다(인자 하나 추가) — create or replace 는 **덧씌우지 못하고 오버로드를 만든다**(Postgres 는 함수를 이름+인자 타입으로 구별한다). 둘이 남으면 PostgREST 의 이름 인자 호출이 두 후보를 다 맞춰 실패한다(짐작 · Postgres 쪽 「둘이 남는다」는 확정).
--   ⇒ 옛 시그니처를 **drop 하고 새로 만든다**(이견 2 · 레포 첫 사례 — 210000 은 타입이 같아 replace 가 됐다). 같은 트랜잭션 안이라 사이가 없다.
-- 지시서: ~/asung/prompts/po-invoice-line-qty.md · 검토 이견 1~12(2026-09-17)
-- ❌ 범위 밖 — po_invoice_add_po_lines(다른 PO 줄 더하기)의 같은 성가심(이견 11 · 말만) · 화면(대화 Claude)
--
-- ═══════════════════════════════════════════════════════════════
-- ⭐⭐ 화면(asung-ims · 대화 Claude)이 부르는 모양 — 여기 한 곳만 보고 고친다 · supabase-js v2 · 예외는 error.message(HTTP 400)
-- ═══════════════════════════════════════════════════════════════
--   지금 호출(po.html runCreateInvoice · 이름 인자)은 **그대로 돈다** — p_line_qty 를 안 주면 미청구 수량 전부(변경 없음)
--     sb.rpc("po_invoice_create", { p_doc_kind:"invoice", p_invoice_number:num, p_po_id:h.id, p_invoice_date:d, p_total_amount:t, p_commit:false })
--   ⭐ 수량을 정해 부를 때 — 새 인자 하나
--     p_line_qty: { "<po_line_id>": <qty_ea>, … }     ← 키 = po_line.id(uuid 문자열) · 값 = 낱개(EA) 수량 · JSON number(문자열 숫자도 받는다)
--       예  { "3f2a…-…": 400, "9c1d…-…": 120, "77be…-…": 0 }
--       키에 있는 라인만 그 수량으로 줄을 만든다 · 키에 없는 라인 = 이번 인보이스에 안 실린 것(줄 없음 · lines[] 에는 verdict 'skipped' 로 담긴다) · 값 0 또는 null = 같다(「지운다」의 뜻)
--       ⚠️ 인보이스만 — 크레딧(p_doc_kind:'credit')에 주면 거부 「p_line_qty is for invoices only …」
--     거부(저장 전 · 미리 보기에서도 같은 판정):
--       미청구 수량을 넘김   「Line 3 (HBE00245) of PO-02007: requested 600 EA but only 500 EA remain uninvoiced — nothing was saved」
--       음수·숫자 아님       「Line 3 (HBE00245) of PO-02007: requested quantity -5 is negative — nothing was saved」 · 「… quantity "abc" is not a number — nothing was saved」
--       그 PO 의 라인 아님   「p_line_qty has 2 key(s) that are not lines of PO PO-02007 (<uuid>, <uuid>) — nothing was saved」
--       남길 줄 없음(전부 0) 「p_line_qty leaves no line to invoice on PO PO-02007 — give at least one quantity above 0 — nothing was saved」
--   반환(기존 키 그대로 + 셋)
--     line_count(만들/만든 줄 수 · 기존) · ⭐ skipped_count(이번에 뺀 라인 수 · p_line_qty 없으면 0) · ⭐ requested_total(준 수량의 합 · p_line_qty 없으면 null)
--     lines[] 인보이스: { n, verdict('ok' | 'fully_invoiced' | ⭐'skipped'), po_line_id, po_number, po_line_no, sku, qty_ordered, invoiced_qty, remaining_qty, ⭐ requested_qty(준 값 · 안 줬으면 null), qty_ea, unit_price, line_no, inserted, message }
--     ⚠️ 'skipped' 줄도 lines[] 에 담긴다 — 화면이 「이번에 뺀 품목」을 보여 준다 · remaining ≤ 0 인 라인은 키에 없어도 'fully_invoiced'(사실이 더 세다 · 이견 4)
--   화면 안(제안 · 이견 12): Check 결과의 lines[] 를 표로 그리고 remaining_qty 를 기본값으로 둔 수량 입력칸을 줄마다 둔다 → 사람이 0 으로 지우거나 줄이면 그 표에서 p_line_qty 를 모아 Create 를 부른다. 두 단계(Check → Create)는 그대로
-- ═══════════════════════════════════════════════════════════════
--
-- ⭐ 관례(200000 · 210000 그대로) — plpgsql · volatile · security invoker · set search_path · 「… — nothing was saved」 · array_append(text[] || 리터럴 금지) · 검사는 **저장 전에**(머리 insert 앞에서 p_line_qty 를 한 번 훑는다) · revoke public/anon + grant authenticated
-- jsonb 키를 uuid 로 읽는 관례 — 값은 (p->>'k')::uuid 선례가 있고(200000 437행 등) **키를 도는 선례는 없다**(2026-09-17 grep · 4-a ④) ⇒ jsonb_each_text(p_line_qty) 의 key::uuid · 첫 사용
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS · --db-url 이 보이면 테스트)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① 옛 시그니처를 내린다 — replace 로는 덧씌워지지 않는다(인자 타입이 달라졌다) ═══
drop function if exists public.po_invoice_create(text, text, uuid, uuid, uuid, date, date, numeric, boolean, boolean);

-- ═══ ② po_invoice_create — 210000 정의 + p_line_qty (맨 뒤 · 기본 null · 이견 3) ═══
create function public.po_invoice_create(
  p_doc_kind              text,                       -- 'invoice' | 'credit'
  p_invoice_number        text    default null,       -- 인보이스: 필수(공급처 번호) · 크레딧: 안 주면 자동(우리 번호) · 주면 그대로
  p_po_id                 uuid    default null,       -- 인보이스: 필수 · 크레딧: 머리 원천 둘째 · 크레딧 번호의 축(credit_po_id)
  p_credit_for_invoice_id uuid    default null,       -- 크레딧만 · 있으면 줄 자동 채우기(차이) · 그 인보이스의 발주가 하나면 그것이 번호의 축
  p_supplier_id           uuid    default null,       -- 크레딧 머리 원천 셋째(조정 크레딧 · CN-<연도>-<n>)
  p_invoice_date          date    default null,       -- 안 주면 오늘 · 조정 번호의 연도
  p_due_date              date    default null,
  p_total_amount          numeric default null,       -- 찍힌 총액 · 안 주면 0 + 경고
  p_copy_discounts        boolean default true,       -- 인보이스만
  p_commit                boolean default false,      -- false = 미리 보기
  p_line_qty              jsonb   default null        -- ⭐ 새 · 인보이스만 · { "<po_line_id>": <qty_ea> } · null 이면 미청구 수량 전부(지금 그대로) · 키에 없는 라인·0 은 줄 없음('skipped')
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
  v_skip         int := 0;
  v_disc_n       int := 0;
  r              record;
  v_verdict      text;
  v_qty          numeric;
  v_req          numeric;
  v_full         boolean;
  v_msgs         text[];
  -- ⭐ p_line_qty
  v_use_qty      boolean := false;
  v_req_total    numeric;
  v_bad_n        int;
  v_bad_txt      text;
  v_keep_n       int;
begin
  if p_doc_kind not in ('invoice', 'credit') then
    raise exception 'p_doc_kind must be ''invoice'' or ''credit'' — nothing was saved';
  end if;
  v_kind_label := case p_doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;
  v_num := nullif(regexp_replace(coalesce(p_invoice_number, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
  if p_doc_kind = 'invoice' and v_num is null then
    raise exception 'Invoice number is required — it is the supplier''s number — nothing was saved';
  end if;

  -- ⭐ p_line_qty 는 인보이스만 — 크레딧에 주면 거부(조용히 무시하면 화면 실수를 덮는다)
  if p_line_qty is not null then
    if p_doc_kind <> 'invoice' then
      raise exception 'p_line_qty is for invoices only — a credit note is filled from invoice minus received — nothing was saved';
    end if;
    if jsonb_typeof(p_line_qty) <> 'object' then
      raise exception 'p_line_qty must be a JSON object { "<po_line_id>": qty } — nothing was saved';
    end if;
    v_use_qty := true;
  end if;

  -- ── 머리의 원천 (210000 그대로) ──
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

  -- ── ⭐ p_line_qty 검사 넷 — 저장 전에 · 미리 보기에서도 같은 판정 ──
  if v_use_qty then
    -- ③ 그 PO 의 라인이 아닌 키(uuid 가 아닌 키도 여기서 걸린다 — ::uuid 가 invalid_text_representation 을 낸다 · 아래 exception 절이 읽을 문장으로)
    select count(*), string_agg(k.key, ', ' order by k.key) into v_bad_n, v_bad_txt
    from jsonb_each_text(p_line_qty) k
    where not exists (select 1 from public.po_line l where l.id = k.key::uuid and l.po_id = p_po_id);
    if v_bad_n > 0 then
      raise exception 'p_line_qty has % key(s) that are not lines of PO % (%) — nothing was saved', v_bad_n, v_po.po_number, v_bad_txt;
    end if;
    -- ② 숫자 아님 · 음수  ① 미청구 초과  — 라인 번호·SKU·수량을 문장에
    for r in
      select u.line_no, u.sku, u.remaining_qty, k.value as raw
      from jsonb_each_text(p_line_qty) k
      join public.po_uninvoiced_lines(p_po_id) u on u.po_line_id = k.key::uuid
      order by u.line_no
    loop
      if r.raw is null then continue; end if;                                   -- null 값 = 0 과 같다(줄 없음)
      if r.raw !~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then
        raise exception 'Line % (%) of PO %: requested quantity "%" is not a number — nothing was saved', r.line_no, r.sku, v_po.po_number, r.raw;
      end if;
      v_req := r.raw::numeric;
      if v_req < 0 then
        raise exception 'Line % (%) of PO %: requested quantity % is negative — nothing was saved', r.line_no, r.sku, v_po.po_number, v_req;
      end if;
      if v_req > r.remaining_qty then
        -- ⚠️ 넘겨 받으면 다음 장의 remaining 이 음수가 되고 초과 입고의 음수와 같은 모양이라 사후 구별이 안 된다(§11-b · po_line_update 와 같은 이유)
        raise exception 'Line % (%) of PO %: requested % EA but only % EA remain uninvoiced — nothing was saved', r.line_no, r.sku, v_po.po_number, v_req, r.remaining_qty;
      end if;
    end loop;
    -- ④ 남길 줄이 하나도 없다(전부 0·null) — 줄 0개 인보이스는 확정이 어차피 막는다 · 만들기에서 막아 못 쓰는 문서를 안 남긴다
    select count(*) into v_keep_n
    from jsonb_each_text(p_line_qty) k
    where k.value is not null and k.value ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' and k.value::numeric > 0;
    if v_keep_n = 0 then
      raise exception 'p_line_qty leaves no line to invoice on PO % — give at least one quantity above 0 — nothing was saved', v_po.po_number;
    end if;
    select coalesce(sum(k.value::numeric), 0) into v_req_total
    from jsonb_each_text(p_line_qty) k
    where k.value is not null and k.value ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$';
  end if;

  -- ── ⭐ 크레딧 — 번호의 축(credit_po_id)과 번호 (210000 그대로) ──
  if p_doc_kind = 'credit' then
    if p_po_id is not null then
      v_credit_po_id := v_po.id;
    elsif p_credit_for_invoice_id is not null then
      select count(distinct pl.po_id), (array_agg(distinct pl.po_id))[1] into v_po_n, v_credit_po_id
      from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id
      where il.po_invoice_id = p_credit_for_invoice_id;
      if coalesce(v_po_n, 0) > 1 then
        v_credit_po_id := null;
        v_warn := array_append(v_warn, 'credit_po_ambiguous');
      end if;
    end if;
    if v_credit_po_id is not null then
      select po_number into v_credit_po_number from public.po where id = v_credit_po_id;
    end if;

    if v_num is null then
      v_num := public.po_credit_next_number(v_credit_po_id, extract(year from coalesce(p_invoice_date, current_date))::int);
      v_num_src := case when v_credit_po_id is not null then 'auto_po' else 'auto_year' end;
      if not p_commit then v_warn := array_append(v_warn, 'number_is_provisional'); end if;
    else
      v_num_src := 'given';
      v_warn := array_append(v_warn, 'credit_number_manual');
    end if;
  else
    v_num_src := 'given';
  end if;

  -- ── 번호 중복 — 미리 보기는 경고 · commit 은 읽을 문장으로 거부 (그대로) ──
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

  -- ── commit: 머리 한 행 (그대로) ──
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

  -- ── 줄 ──
  if p_doc_kind = 'invoice' then
    -- ⭐ 바뀐 블록 — p_line_qty 가 있으면 키에 있는 라인만 그 수량으로 · 없으면 미청구 수량 전부(그대로)
    for r in
      select u.*,
             case when v_use_qty then (select nullif(regexp_replace(k.value, '\s', '', 'g'), '')::numeric
                                         from jsonb_each_text(p_line_qty) k where k.key::uuid = u.po_line_id) end as requested_qty,
             case when v_use_qty then (p_line_qty ? u.po_line_id::text) end as in_keys
      from public.po_uninvoiced_lines(p_po_id) u
    loop
      v_n := v_n + 1; v_msgs := '{}'; v_qty := null; v_full := false;
      v_req := case when v_use_qty and coalesce(r.in_keys, false) then coalesce(r.requested_qty, 0) end;   -- 준 값(null 값은 0)
      if r.remaining_qty <= 0 then
        -- 청구할 것이 없다 — 사실이 더 세다(키에 있고 0 이든 없든 · 0 초과는 위 ① 이 이미 막았다)
        v_verdict := 'fully_invoiced';
        v_msgs := array_append(v_msgs, case when r.remaining_qty < 0 then 'over-invoiced — check earlier invoices' else 'nothing left to invoice' end);
      elsif v_use_qty and coalesce(v_req, 0) = 0 then
        -- ⭐ 이번 인보이스에 안 실렸다(키에 없음 · 0 · null) — 줄 없음 · lines[] 에는 담는다
        v_verdict := 'skipped'; v_skip := v_skip + 1;
        v_msgs := array_append(v_msgs, case when coalesce(r.in_keys, false) then 'requested 0 — not on this invoice' else 'not in p_line_qty — not on this invoice' end);
      else
        v_verdict := 'ok'; v_ok := v_ok + 1;
        v_qty := case when v_use_qty then v_req else r.remaining_qty end;
        v_full := (v_qty = r.qty_ea);                                          -- 단위 칸 넷은 주문 수량과 같을 때만(그대로)
        if r.invoiced_qty > 0 then v_msgs := array_append(v_msgs, format('%s already invoiced on other invoice(s) — remaining %s', r.invoiced_qty, r.remaining_qty)); end if;
        if v_use_qty and v_qty < r.remaining_qty then v_msgs := array_append(v_msgs, format('requested %s of %s remaining', v_qty, r.remaining_qty)); end if;
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
      end if;
      v_lines := v_lines || jsonb_build_object(
        'n', v_n, 'verdict', v_verdict, 'po_line_id', r.po_line_id, 'po_number', v_po.po_number, 'po_line_no', r.line_no, 'sku', r.sku,
        'qty_ordered', r.qty_ea, 'invoiced_qty', r.invoiced_qty, 'remaining_qty', r.remaining_qty,
        'requested_qty', v_req,                                                                   -- ⭐ 새 · 준 값(안 줬으면 null)
        'qty_ea', v_qty, 'unit_price', case when v_verdict = 'ok' then r.unit_price end,
        'line_no', case when v_verdict = 'ok' then (case when p_commit then v_ins else v_ok end) end,
        'inserted', (p_commit and v_verdict = 'ok'), 'message', array_to_string(v_msgs, ' · '));
    end loop;
    if v_ok = 0 then v_warn := array_append(v_warn, 'no_uninvoiced_lines'); end if;       -- p_line_qty 가 있으면 ④ 가 먼저 막아 여기 안 온다

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
    -- 크레딧 (210000 그대로)
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
    'invoice_number', v_num, 'number_source', v_num_src,
    'credit_po_id', v_credit_po_id, 'credit_po_number', v_credit_po_number,
    'header_source', v_source,
    'supplier_id', v_supplier_id, 'supplier_name', v_sup_name, 'currency_id', v_currency_id, 'currency_code', v_cur_code,
    'payment_term_name', v_pt_name, 'total_amount', coalesce(p_total_amount, 0),
    'line_count', case when p_commit then v_ins else v_ok end,
    'skipped_count', v_skip,                                                      -- ⭐ 새 · 이번에 뺀 라인 수(p_line_qty 없으면 0)
    'requested_total', v_req_total,                                               -- ⭐ 새 · 준 수량의 합(p_line_qty 없으면 null)
    'lines', v_lines,
    'discounts', v_discs, 'discounts_copied', v_disc_n,
    'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception '% % already exists for % — nothing was saved', v_kind_label, v_num, coalesce(v_sup_name, 'this supplier');
  when invalid_text_representation then
    -- p_line_qty 의 키가 uuid 모양이 아니다(k.key::uuid) — 읽을 문장으로
    raise exception 'p_line_qty keys must be po_line_id uuids — one of them is not (%) — nothing was saved', sqlerrm;
end;
$$;
comment on function public.po_invoice_create(text, text, uuid, uuid, uuid, date, date, numeric, boolean, boolean, jsonb) is '⑤ 인보이스·크레딧 초안 만들기(미리 보기 = 같은 모양 · p_commit). 210000 정의 + ⭐ [2026-09-17] p_line_qty jsonb { "<po_line_id>": qty_ea } — 인보이스만 · 키에 있는 라인만 그 수량으로 · 키에 없음/0/null 은 줄 없음(verdict skipped · lines[] 에는 담는다 · skipped_count) · 저장 전 거부 넷(그 PO 의 라인 아님 · 숫자 아님/음수 · 미청구 초과 — 초과 입고의 음수와 같은 모양이라 사후 구별 불가 §11-b · 남길 줄 없음) · 미리 보기도 같은 판정 · 크레딧에 주면 거부 · requested_qty · requested_total. 없으면 미청구 수량 전부(그대로 · 다음 장은 po_uninvoiced_lines 가 맞춘다). 크레딧 번호 자동(po_credit_next_number) · credit_po_id · 머리 원천 · 할인 복사 · 총액 0+경고 · 번호 중복은 210000 그대로. 정본 po-module §11-g · §11-b · 2026-09-17';

revoke all on function public.po_invoice_create(text, text, uuid, uuid, uuid, date, date, numeric, boolean, boolean, jsonb) from public, anon;
grant execute on function public.po_invoice_create(text, text, uuid, uuid, uuid, date, date, numeric, boolean, boolean, jsonb) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 검증 (Caleb · 테스트 DB · 지시서 §5 · 실물은 4-b(Caleb 2026-09-17 SQL): PO-02007 confirmed · 13라인 · 소계 586.92 · 전 라인 qty_ea 12 · 인보이스 없음 · 검토 Claude 는 SQL 을 돌리지 않았다)
--   라인 1  APR10048  84a563b5-0999-42a0-8739-454df60100c8  @3.43
--   라인 2  APR11829  dd55d88b-6877-4d9c-bf37-a67a8a43cde7  @3.50
--   라인 3  APR15412  19800c98-70c7-44f0-b3e5-01906cc2e08a  @3.50
--   라인 13 APR40008  2ed406e0-6198-4117-89d4-2dfeea962de5  @8.34
--   다른 PO 의 라인(⑤): PO-02001a 라인 1 · AMP00405 · 75849eed-e433-4313-b9d2-d9ec505123b6
--   ⚠️ commit 은 auth.uid() 를 보므로 psql 에서는 request.jwt.claims 를 심는다 — 미리 보기는 그냥 된다
--   ⚠️ 시그니처가 바뀌었으니 먼저: select count(*) from pg_proc where proname='po_invoice_create';   → 1 (둘이면 drop 이 안 된 것 · 오버로드)
--   자리 호출로 부를 때 p_line_qty 는 열한째 — 앞 열 개는 210000 검증 절과 같다
-- ─────────────────────────────────────────────────────────────
-- ⓪ 적용 뒤
--   select pg_get_function_arguments('public.po_invoice_create'::regproc);   → … p_commit boolean DEFAULT false, p_line_qty jsonb DEFAULT NULL
-- ① p_line_qty 없이 미리 보기 — 지금과 같다
--   select jsonb_pretty(po_invoice_create('invoice', 'LQ-TEST-1', (select id from po where po_number='PO-02007'), null, null, current_date, null, null, true, false));
--   예상  lines 13줄 전부 verdict ok · qty_ea 12 · remaining_qty 12 · invoiced_qty 0 · requested_qty 전부 null · line_count 13 · skipped_count 0 · requested_total null ·
--         warnings ['total_amount_missing'] (+ discounts_copied_from_po 는 po_discount 행이 있을 때만 · Strength of Nature 는 0행 짐작)
-- ② 라인 1·2 는 전량 12 · ⭐ 라인 3 만 6(절반) — ⑦ 에서 남은 6 이 돌아오는지가 이 차수의 핵심
--   select jsonb_pretty(po_invoice_create('invoice', 'LQ-TEST-1', (select id from po where po_number='PO-02007'), null, null, current_date, null, null, true, false,
--          '{"84a563b5-0999-42a0-8739-454df60100c8": 12, "dd55d88b-6877-4d9c-bf37-a67a8a43cde7": 12, "19800c98-70c7-44f0-b3e5-01906cc2e08a": 6}'::jsonb));
--   예상  라인 1 APR10048  ok · requested_qty 12 · qty_ea 12 · unit_price 3.43 · line_no 1 · message ''
--         라인 2 APR11829  ok · requested_qty 12 · qty_ea 12 · unit_price 3.50 · line_no 2 · message ''
--         라인 3 APR15412  ok · requested_qty 6  · qty_ea 6  · unit_price 3.50 · line_no 3 · message 'requested 6 of 12 remaining · partial — entered unit reset to EA'
--         라인 4~13(APR40008 포함)  verdict 'skipped' · requested_qty null · qty_ea null · unit_price null · line_no null · message 'not in p_line_qty — not on this invoice'
--         line_count 3 · skipped_count 10 · requested_total 30 · lines[] 13줄(skipped 포함) · warnings ['total_amount_missing']
--   ②-b 0 을 섞어서   '{"84a563b5-…0100c8": 12, "dd55d88b-…43cde7": 0}' → 라인 1 ok · 라인 2 skipped(requested_qty 0 · message 'requested 0 — not on this invoice') · 라인 3~13 skipped · line_count 1 · skipped_count 12 · requested_total 12
-- ③ 미청구 수량을 넘겨 준다 — 라인 1 에 13(remaining 12)
--   … , '{"84a563b5-0999-42a0-8739-454df60100c8": 13}'::jsonb)
--   예상  예외 「Line 1 (APR10048) of PO PO-02007: requested 13 EA but only 12 EA remain uninvoiced — nothing was saved」 (미리 보기 · commit 둘 다 같은 문장)
--   음수   '{"84a563b5-…0100c8": -5}' → 「Line 1 (APR10048) of PO PO-02007: requested quantity -5 is negative — nothing was saved」
--   문자열 '{"84a563b5-…0100c8": "abc"}' → 「Line 1 (APR10048) of PO PO-02007: requested quantity "abc" is not a number — nothing was saved」 · '{"…0100c8": "12"}' 는 숫자로 받아 ok
-- ④ 전부 0 으로 준다   '{"84a563b5-…0100c8": 0, "dd55d88b-…43cde7": 0}'
--   예상  예외 「p_line_qty leaves no line to invoice on PO PO-02007 — give at least one quantity above 0 — nothing was saved」
-- ⑤ 다른 PO 의 po_line_id 를 섞는다 — PO-02001a 라인 1(AMP00405)
--   … , '{"84a563b5-0999-42a0-8739-454df60100c8": 12, "75849eed-e433-4313-b9d2-d9ec505123b6": 10}'::jsonb)
--   예상  예외 「p_line_qty has 1 key(s) that are not lines of PO PO-02007 (75849eed-e433-4313-b9d2-d9ec505123b6) — nothing was saved」
--   uuid 아닌 키  '{"abc": 1}' → 「p_line_qty keys must be po_line_id uuids — one of them is not (invalid input syntax for type uuid: "abc") — nothing was saved」 (괄호 안은 Postgres 원문 · 짐작)
-- ⑥ 크레딧에 p_line_qty 를 준다
--   select po_invoice_create('credit', null, null, (select id from po_invoice where invoice_number='AMP-778812' and doc_kind='invoice'), null, null, null, null, true, false, '{}'::jsonb);
--   예상  예외 「p_line_qty is for invoices only — a credit note is filled from invoice minus received — nothing was saved」 (빈 객체 {} 도 「줬다」로 본다 — 조용히 무시하지 않는다)
-- ⑦ ⭐ 핵심 — ② 를 commit(jwt · 열째 인자 true) → po_invoice_confirm(<새 id>) → 같은 PO 로 둘째 인보이스 미리 보기(p_line_qty 없이 · 번호 'LQ-TEST-2')
--   select jsonb_pretty(po_invoice_create('invoice', 'LQ-TEST-2', (select id from po where po_number='PO-02007'), null, null, current_date, null, null, true, false));
--   예상  라인 1 APR10048  fully_invoiced · invoiced_qty 12 · remaining_qty 0 · message 'nothing left to invoice'
--         라인 2 APR11829  fully_invoiced · invoiced_qty 12 · remaining_qty 0
--         ⭐ 라인 3 APR15412  ok · invoiced_qty 6 · remaining_qty 6 · qty_ea 6 · message '6 already invoiced on other invoice(s) — remaining 6 · partial — entered unit reset to EA'
--         라인 4~13  ok · invoiced_qty 0 · remaining_qty 12 · qty_ea 12 (주문 수량 그대로 · message '')
--         line_count 11 · skipped_count 0 · requested_total null  ⇒ 「다음 장은 저절로 맞는다」 — po_uninvoiced_lines 무변으로 얻는다
--   select po_number, invoiced_qty, ordered_qty, invoice_phase from po_list where po_number='PO-02007';   → invoiced_qty 30 · ordered_qty 156 · invoice_phase 'partial'
--   확인 뒤 po_doc_cancel('invoice', <첫 장 id>) 로 취소하거나 Reopen(po_invoice_confirm(…, false)) 뒤 po_doc_delete 로 지운다(검증 데이터를 남기려면 두어도 된다 — 다음 미리 보기의 remaining 이 그만큼 줄어 있다)
