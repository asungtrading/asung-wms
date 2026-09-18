-- ─────────────────────────────────────────────────────────────
-- 쓰기 RPC 가 막혔을 때 정직하게 답한다 — ②/③ 인보이스·할인 계열 (Asung-IMS) · 2026-09-17 밤
--
-- 앞 차수: 20260918000000_ims_rpc_honest_refusal_po.sql (①/③ · d6c3155 · 도우미 ims_require_write 는 거기서 만들었다 — 여기서는 부르기만).
-- 같은 처방: ① 첫머리 ims_require_write('<묶음>', 'saved'|'deleted') — RLS 에 닿기 전에 읽을 수 있는 말로 거부
--            ② delete 뒤 get diagnostics row_count · update … returning 뒤 if not found — 0행이면 「… was not saved|deleted — it may have been removed or changed by someone else just now — nothing was …」
-- 이 파일의 여덟: po_invoice_create · po_invoice_add_po_lines · po_invoice_line_add · po_invoice_line_update · po_invoice_line_delete · po_invoice_confirm · po_discount_save · po_discount_delete
--   본문은 원본 마이그레이션(20260917170000 · 20260916200000)에서 **바이트 그대로** 옮기고 아래 줄만 더했다(스크립트로 이어 붙임 · 회신에 diff 첨부).
--   여덟 정의 전부 머리를 `create` → `create or replace` 로 바꿨다(200000·170000 판은 replace 없이 만들어졌다) · 인자 무변 ⇒ 덧씌워진다 · grant·comment 유지.
--
-- ⚠️ 두 묶음 함수 둘 — po_discount_save · po_discount_delete: p_target='supplier' 갈래는 supplier_discount(master)를 쓴다.
--   ⇒ 권한 검사는 p_target 으로 가른다: case when p_target = 'supplier' then 'master' else 'purchasing' end.
--   p_target 검증(셋 중 하나) 바로 뒤 · 어떤 select 보다 앞. purchasing 만 가진 사람이 공급처 할인을 고치면 「You do not have master access …」.
--
-- 함수별로 더한 것
--   po_invoice_create         perform (insert 만 · 미리 보기 p_commit=false 도 막는다 — 앞 차수 이견 3 과 같은 이유)
--   po_invoice_add_po_lines   perform (insert 만 · p_commit=false 도 막는다)
--   po_invoice_line_add       perform (insert 만)
--   po_invoice_line_update    perform + update 0행 검사 (v_line_no 를 미리 든다 — returning 이 v_row 를 null 로 덮는다)
--   po_invoice_line_delete    perform('deleted') + delete row_count
--   po_invoice_confirm        perform + update 2곳 0행 검사 (v_num 을 미리 든다)
--   po_discount_save          perform(case) + update 3곳 0행 검사
--   po_discount_delete        perform(case, 'deleted') + delete 3곳 row_count
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) po_invoice_create — 첫머리 권한 (insert 만) ═══
create or replace function public.po_invoice_create(
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
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

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

-- ═══ 2) po_invoice_add_po_lines — 첫머리 권한 (insert 만) ═══
create or replace function public.po_invoice_add_po_lines(
  p_invoice_id uuid,
  p_po_id      uuid,
  p_commit     boolean default true
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_inv    public.po_invoice%rowtype;
  v_po     public.po%rowtype;
  v_next   int;
  v_n      int := 0;  v_ok int := 0;  v_ins int := 0;
  v_warn   text[] := '{}';
  v_lines  jsonb := '[]'::jsonb;
  v_msgs   text[];
  v_verdict text;  v_qty numeric;  v_full boolean;
  r        record;
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_inv from public.po_invoice where id = p_invoice_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_invoice_id; end if;
  if v_inv.doc_kind <> 'invoice' then
    raise exception 'Credit note % — PO lines are added to invoices only (add credit lines one by one) — nothing was saved', v_inv.invoice_number;
  end if;
  if v_inv.status <> 'draft' then
    raise exception 'Invoice % is % — lines can be changed only while draft (confirmed = accepted into the books) — nothing was saved', v_inv.invoice_number, v_inv.status;
  end if;
  select * into v_po from public.po where id = p_po_id;
  if not found then raise exception 'PO % not found — nothing was saved', p_po_id; end if;
  if v_po.supplier_id <> v_inv.supplier_id then
    raise exception 'PO % belongs to a different supplier than invoice % — nothing was saved', v_po.po_number, v_inv.invoice_number;
  end if;
  if v_po.currency_id <> v_inv.currency_id then v_warn := array_append(v_warn, 'currency_mismatch'); end if;

  select coalesce(max(line_no), 0) into v_next from public.po_invoice_line where po_invoice_id = p_invoice_id;

  for r in select * from public.po_uninvoiced_lines(p_po_id) loop
    v_n := v_n + 1; v_msgs := '{}'; v_qty := null; v_full := false;
    if r.remaining_qty > 0 then
      v_verdict := 'ok'; v_qty := r.remaining_qty; v_full := (r.remaining_qty = r.qty_ea); v_ok := v_ok + 1;
      if r.invoiced_qty > 0 then v_msgs := array_append(v_msgs, format('%s already invoiced — remaining %s', r.invoiced_qty, r.remaining_qty)); end if;
      if not v_full then v_msgs := array_append(v_msgs, 'partial — entered unit reset to EA'); end if;
      v_next := v_next + 1;
      if p_commit then
        v_ins := v_ins + 1;
        insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable,
                                            entered_unit_product_id, entered_qty, entered_pack_factor)
        values (p_invoice_id, v_next, 'goods', r.po_line_id, v_qty, r.unit_price, true,
                case when v_full then r.entered_unit_product_id end, case when v_full then r.entered_qty end, case when v_full then r.entered_pack_factor end);
      end if;
    else
      v_verdict := 'fully_invoiced';
      v_msgs := array_append(v_msgs, case when r.remaining_qty < 0 then 'over-invoiced — check earlier invoices' else 'nothing left to invoice' end);
    end if;
    v_lines := v_lines || jsonb_build_object(
      'n', v_n, 'verdict', v_verdict, 'po_line_id', r.po_line_id, 'po_number', v_po.po_number, 'po_line_no', r.line_no, 'sku', r.sku,
      'qty_ordered', r.qty_ea, 'invoiced_qty', r.invoiced_qty, 'remaining_qty', r.remaining_qty,
      'qty_ea', v_qty, 'unit_price', case when v_verdict = 'ok' then r.unit_price end,
      'line_no', case when v_verdict = 'ok' then v_next end,
      'inserted', (p_commit and v_verdict = 'ok'), 'message', array_to_string(v_msgs, ' · '));
  end loop;
  if v_ok = 0 then v_warn := array_append(v_warn, 'no_uninvoiced_lines'); end if;

  return jsonb_build_object('committed', p_commit, 'invoice_id', p_invoice_id, 'invoice_number', v_inv.invoice_number,
                            'po_id', p_po_id, 'po_number', v_po.po_number, 'lines', v_lines, 'inserted', v_ins, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 3) po_invoice_line_add — 첫머리 권한 (insert 만) ═══
create or replace function public.po_invoice_line_add(
  p_invoice_id uuid,
  p_line       jsonb
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_inv    public.po_invoice%rowtype;
  v_pl     public.po_line%rowtype;
  v_po     public.po%rowtype;
  v_kind   text;  v_pol uuid;  v_desc text;  v_qty numeric;  v_price numeric;  v_pay boolean;
  v_next   int;   v_cnt int;   v_dup int;
  v_row    public.po_invoice_line%rowtype;
  v_warn   text[] := '{}';
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_inv from public.po_invoice where id = p_invoice_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_invoice_id; end if;
  if v_inv.status <> 'draft' then
    raise exception '% % is % — lines can be changed only while draft — nothing was saved',
      case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end, v_inv.invoice_number, v_inv.status;
  end if;
  if p_line is null or jsonb_typeof(p_line) <> 'object' then raise exception 'p_line must be a JSON object — nothing was saved'; end if;

  v_kind  := coalesce(nullif(p_line->>'line_kind', ''), 'goods');
  v_pol   := nullif(p_line->>'po_line_id', '')::uuid;
  v_desc  := nullif(p_line->>'description', '');
  v_qty   := nullif(p_line->>'qty_ea', '')::numeric;
  v_price := coalesce(nullif(p_line->>'unit_price', '')::numeric, 0);
  v_pay   := coalesce(nullif(p_line->>'is_payable', '')::boolean, true);

  if v_kind not in ('goods', 'charge', 'other') then raise exception 'line_kind must be goods, charge or other — nothing was saved'; end if;
  if v_kind = 'goods' then
    if v_pol is null then raise exception 'A goods line must point at a PO line (po_line_id) — use line_kind charge/other with a description for anything else — nothing was saved'; end if;
    select * into v_pl from public.po_line where id = v_pol;
    if not found then raise exception 'PO line % not found — nothing was saved', v_pol; end if;
    select * into v_po from public.po where id = v_pl.po_id;
    if v_po.supplier_id <> v_inv.supplier_id then
      raise exception 'PO % belongs to a different supplier than % % — nothing was saved', v_po.po_number, lower(case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end), v_inv.invoice_number;
    end if;
    if v_po.currency_id <> v_inv.currency_id then v_warn := array_append(v_warn, 'currency_mismatch'); end if;
    if v_qty is null then raise exception 'qty_ea is required for a goods line — nothing was saved'; end if;
    select count(*) into v_dup from public.po_invoice_line where po_invoice_id = p_invoice_id and po_line_id = v_pol;
    if v_dup > 0 then v_warn := array_append(v_warn, 'line_already_on_invoice'); end if;      -- 막지 않는다(부분 선적이 한 장에 두 줄로 올 수 있다 · 짐작) · 알린다
  else
    if v_desc is null then raise exception 'A % line needs a description — nothing was saved', v_kind; end if;
    v_qty := coalesce(v_qty, 1);
  end if;

  select coalesce(max(line_no), 0) + 1 into v_next from public.po_invoice_line where po_invoice_id = p_invoice_id;

  insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, description, qty_ea, unit_price, is_payable,
                                      entered_unit_product_id, entered_qty, entered_pack_factor, note)
  values (p_invoice_id, v_next, v_kind, case when v_kind = 'goods' then v_pol end, v_desc, v_qty, v_price, v_pay,
          nullif(p_line->>'entered_unit_product_id', '')::uuid, nullif(p_line->>'entered_qty', '')::numeric,
          nullif(p_line->>'entered_pack_factor', '')::numeric, nullif(p_line->>'note', ''))
  returning * into v_row;
  -- CHECK(target · unit_price >= 0 · entered_unit_ck)는 표가 지킨다 — 어기면 표의 예외가 그대로 올라간다

  select count(*) into v_cnt from public.po_invoice_line where po_invoice_id = p_invoice_id;
  return jsonb_build_object('line', to_jsonb(v_row), 'line_count', v_cnt, 'invoice_number', v_inv.invoice_number, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 4) po_invoice_line_update — 첫머리 권한 + update 0행 검사 ═══
create or replace function public.po_invoice_line_update(
  p_line_id uuid,
  p_patch   jsonb
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_line_no int;                                                -- ②-b: 0행이면 v_row 가 null 로 덮이므로 번호를 미리 든다
  v_row   public.po_invoice_line%rowtype;
  v_inv   public.po_invoice%rowtype;
  v_pl    public.po_line%rowtype;
  v_po    public.po%rowtype;
  v_kind  text;  v_pol uuid;  v_desc text;  v_qty numeric;
  v_warn  text[] := '{}';
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_row from public.po_invoice_line where id = p_line_id;
  if not found then raise exception 'Invoice line % not found — nothing was saved', p_line_id; end if;
  v_line_no := v_row.line_no;
  select * into v_inv from public.po_invoice where id = v_row.po_invoice_id;
  if v_inv.status <> 'draft' then
    raise exception '% % is % — lines can be changed only while draft (confirmed = accepted into the books; reopen first) — nothing was saved',
      case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end, v_inv.invoice_number, v_inv.status;
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'p_patch must be a JSON object — nothing was saved'; end if;

  -- 새 값(patch 우선 · 없으면 기존) — CHECK 위반을 표의 예외 대신 읽을 문장으로 먼저 낸다
  v_kind := case when p_patch ? 'line_kind'   then coalesce(nullif(p_patch->>'line_kind', ''), 'goods') else v_row.line_kind end;
  v_pol  := case when p_patch ? 'po_line_id'  then nullif(p_patch->>'po_line_id', '')::uuid            else v_row.po_line_id end;
  v_desc := case when p_patch ? 'description' then nullif(p_patch->>'description', '')                 else v_row.description end;
  v_qty  := case when p_patch ? 'qty_ea'      then nullif(p_patch->>'qty_ea', '')::numeric             else v_row.qty_ea end;
  if v_kind not in ('goods', 'charge', 'other') then raise exception 'line_kind must be goods, charge or other — nothing was saved'; end if;
  if v_kind = 'goods' and v_pol is null then raise exception 'A goods line must point at a PO line (po_line_id) — nothing was saved'; end if;
  if v_kind <> 'goods' and v_desc is null then raise exception 'A % line needs a description — nothing was saved', v_kind; end if;
  if v_qty is null then raise exception 'qty_ea is required — nothing was saved'; end if;
  if v_kind = 'goods' and (p_patch ? 'po_line_id') and v_pol is distinct from v_row.po_line_id then
    select * into v_pl from public.po_line where id = v_pol;
    if not found then raise exception 'PO line % not found — nothing was saved', v_pol; end if;
    select * into v_po from public.po where id = v_pl.po_id;
    if v_po.supplier_id <> v_inv.supplier_id then
      raise exception 'PO % belongs to a different supplier than % — nothing was saved', v_po.po_number, v_inv.invoice_number;
    end if;
    if v_po.currency_id <> v_inv.currency_id then v_warn := array_append(v_warn, 'currency_mismatch'); end if;
  end if;

  update public.po_invoice_line set
    line_kind               = v_kind,
    po_line_id              = case when v_kind = 'goods' then v_pol else null end,                     -- goods 가 아니면 라인 참조를 비운다
    description             = v_desc,
    qty_ea                  = v_qty,
    unit_price              = case when p_patch ? 'unit_price'              then (p_patch->>'unit_price')::numeric                    else unit_price end,
    is_payable              = case when p_patch ? 'is_payable'              then coalesce((p_patch->>'is_payable')::boolean, true)     else is_payable end,
    entered_unit_product_id = case when p_patch ? 'entered_unit_product_id' then nullif(p_patch->>'entered_unit_product_id', '')::uuid  else entered_unit_product_id end,
    entered_qty             = case when p_patch ? 'entered_qty'             then nullif(p_patch->>'entered_qty', '')::numeric           else entered_qty end,
    entered_pack_factor     = case when p_patch ? 'entered_pack_factor'     then nullif(p_patch->>'entered_pack_factor', '')::numeric   else entered_pack_factor end,
    note                    = case when p_patch ? 'note'                    then nullif(p_patch->>'note', '')                           else note end
  where id = p_line_id
  returning * into v_row;
  if not found then                                             -- ②-b
    raise exception 'Line % of % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_line_no, v_inv.invoice_number;
  end if;

  return jsonb_build_object('line', to_jsonb(v_row), 'invoice_number', v_inv.invoice_number, 'status', v_inv.status, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 5) po_invoice_line_delete — 첫머리 권한 + delete 0행 검사 ═══
create or replace function public.po_invoice_line_delete(p_line_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_n   int;                                                    -- ②-b: row_count
  v_row public.po_invoice_line%rowtype;
  v_inv public.po_invoice%rowtype;
  v_cnt int;
begin
  perform public.ims_require_write('purchasing', 'deleted');     -- ②-b

  select * into v_row from public.po_invoice_line where id = p_line_id;
  if not found then raise exception 'Invoice line % not found — nothing was deleted', p_line_id; end if;
  select * into v_inv from public.po_invoice where id = v_row.po_invoice_id;
  if v_inv.status <> 'draft' then
    raise exception '% % is % — lines can be deleted only while draft — nothing was deleted',
      case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end, v_inv.invoice_number, v_inv.status;
  end if;
  delete from public.po_invoice_line where id = p_line_id;
  get diagnostics v_n = row_count;                              -- ②-b
  if v_n = 0 then
    raise exception 'Line % of % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', v_row.line_no, v_inv.invoice_number;
  end if;
  select count(*) into v_cnt from public.po_invoice_line where po_invoice_id = v_inv.id;
  return jsonb_build_object('deleted', true, 'invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'line_no', v_row.line_no, 'line_count', v_cnt);
end;
$$;

-- ═══ 6) po_invoice_confirm — 첫머리 권한 + update 2곳 0행 검사 ═══
create or replace function public.po_invoice_confirm(
  p_invoice_id uuid,
  p_confirm    boolean default true
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_num   text;                                                 -- ②-b: 0행 문장용 번호(returning 이 v_inv 를 null 로 덮는다)
  v_staff uuid;
  v_inv   public.po_invoice%rowtype;
  v_for   public.po_invoice%rowtype;
  v_m     record;
  v_cnt   int;
  v_cred  int;
  v_warn  text[] := '{}';
  v_label text;
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_inv from public.po_invoice where id = p_invoice_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_invoice_id; end if;
  v_label := case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;
  v_num := v_inv.invoice_number;
  select * into v_m from public.po_invoice_money where id = p_invoice_id;

  if p_confirm then
    if v_inv.status = 'confirmed' then raise exception '% % is already confirmed — nothing was saved', v_label, v_inv.invoice_number; end if;
    if v_inv.status = 'cancelled' then raise exception '% % is cancelled — a cancelled document cannot be confirmed — nothing was saved', v_label, v_inv.invoice_number; end if;
    select count(*) into v_cnt from public.po_invoice_line where po_invoice_id = p_invoice_id;
    if v_cnt = 0 then raise exception '% % has no lines — nothing to accept into the books — nothing was saved', v_label, v_inv.invoice_number; end if;
    if v_inv.credit_for_invoice_id is not null then                       -- 다른 행의 사실 — po_detail credits[].warnings 와 같은 셋을 여기서는 막는다
      select * into v_for from public.po_invoice where id = v_inv.credit_for_invoice_id;
      if v_for.doc_kind <> 'invoice' then raise exception 'Credit note % points at another credit note (%) — nothing was saved', v_inv.invoice_number, v_for.invoice_number; end if;
      if v_for.supplier_id <> v_inv.supplier_id then raise exception 'Credit note % points at an invoice of a different supplier (%) — nothing was saved', v_inv.invoice_number, v_for.invoice_number; end if;
    end if;
    if v_inv.total_amount = 0 then v_warn := array_append(v_warn, 'total_amount_zero'); end if;                 -- 샘플 인보이스 실물 · 막지 않는다
    if v_m.diff <> 0 then v_warn := array_append(v_warn, 'total_differs_from_lines'); end if;                   -- 반올림 · other 할인 미결 · 정본은 찍힌 값 · 막지 않는다
    update public.po_invoice set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now() where id = p_invoice_id returning * into v_inv;
    if not found then raise exception '% % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_label, v_num; end if;   -- ②-b
  else
    if v_inv.status <> 'confirmed' then raise exception '% % is % — only a confirmed document can be reopened — nothing was saved', v_label, v_inv.invoice_number, v_inv.status; end if;
    if v_m.alloc_total > 0 then
      raise exception '% % has payments applied (%) — cannot reopen while paid/used; remove the payment allocation first — nothing was saved', v_label, v_inv.invoice_number, v_m.alloc_total;
    end if;
    select count(*) into v_cred from public.po_invoice c where c.credit_for_invoice_id = p_invoice_id and c.status <> 'cancelled';
    if v_cred > 0 then v_warn := array_append(v_warn, 'has_attached_credits'); end if;
    update public.po_invoice set status = 'draft', confirmed_by = null, confirmed_at = null where id = p_invoice_id returning * into v_inv;
    if not found then raise exception '% % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_label, v_num; end if;   -- ②-b
  end if;

  return jsonb_build_object(
    'id', v_inv.id, 'doc_kind', v_inv.doc_kind, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status, 'confirmed_at', v_inv.confirmed_at,
    'money', jsonb_build_object('total_amount', v_m.total_amount, 'computed_total', v_m.computed_total, 'diff', v_m.diff, 'payable_net', v_m.payable_net,
                                'alloc_total', v_m.alloc_total, 'credit_total', v_m.credit_total, 'unpaid', v_m.unpaid, 'remaining', v_m.remaining),
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 7) po_discount_save — 두 묶음(supplier → master · 그 외 purchasing) + update 3곳 0행 검사 ═══
create or replace function public.po_discount_save(
  p_target    text,
  p_target_id uuid,
  p_patch     jsonb,
  p_id        uuid default null
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_po        public.po%rowtype;
  v_inv       public.po_invoice%rowtype;
  v_sup_id    uuid;                 -- 문서의 공급처(supplier_discount_id 검증용)
  v_name      text;  v_pct numeric;  v_seq int;  v_src uuid;  v_note text;  v_active boolean;
  v_created   boolean := (p_id is null);
  v_row       jsonb;
  v_owner     uuid;
begin
  if p_target not in ('supplier', 'po', 'invoice') then raise exception 'p_target must be supplier, po or invoice — nothing was saved'; end if;
  perform public.ims_require_write(case when p_target = 'supplier' then 'master' else 'purchasing' end, 'saved');   -- ②-b: 두 묶음 — 갈래로 가른다
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'p_patch must be a JSON object — nothing was saved'; end if;

  -- ── 대상 문서와 상태 (다른 행 · 저장 전에 본다) ──
  if p_target = 'supplier' then
    select id into v_sup_id from public.supplier where id = p_target_id;
    if v_sup_id is null then raise exception 'Supplier % not found — nothing was saved', p_target_id; end if;
  elsif p_target = 'po' then
    select * into v_po from public.po where id = p_target_id;
    if not found then raise exception 'PO % not found — nothing was saved', p_target_id; end if;
    if v_po.status in ('closed', 'cancelled') then
      raise exception 'PO % is % — discounts cannot be changed — nothing was saved', v_po.po_number, v_po.status;
    end if;
    v_sup_id := v_po.supplier_id;
  else
    select * into v_inv from public.po_invoice where id = p_target_id;
    if not found then raise exception 'Invoice % not found — nothing was saved', p_target_id; end if;
    if v_inv.status <> 'draft' then
      raise exception '% % is % — discounts can be changed only while draft (confirmed = accepted into the books; reopen first) — nothing was saved',
        case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end, v_inv.invoice_number, v_inv.status;
    end if;
    v_sup_id := v_inv.supplier_id;
  end if;

  -- ── 값 ──
  v_name   := nullif(p_patch->>'name', '');
  v_pct    := nullif(p_patch->>'percent', '')::numeric;
  v_seq    := nullif(p_patch->>'seq', '')::int;
  v_src    := nullif(p_patch->>'supplier_discount_id', '')::uuid;
  v_note   := nullif(p_patch->>'note', '');
  v_active := nullif(p_patch->>'is_active', '')::boolean;
  if v_pct is not null and (v_pct < 0 or v_pct > 100) then raise exception 'percent must be between 0 and 100 — nothing was saved'; end if;
  if v_seq is not null and v_seq < 1 then raise exception 'seq must be 1 or more — nothing was saved'; end if;
  if p_target <> 'supplier' and (p_patch ? 'supplier_discount_id') and v_src is not null then
    -- 제안의 원천은 같은 공급처의 줄이어야 한다(다른 공급처 줄을 가리키면 Source 열이 거짓말을 한다)
    if not exists (select 1 from public.supplier_discount d where d.id = v_src and d.supplier_id = v_sup_id) then
      raise exception 'supplier_discount % is not a discount line of this supplier — nothing was saved', v_src;
    end if;
  end if;

  if v_created then
    if v_name is null or v_pct is null then raise exception 'name and percent are required for a new discount line — nothing was saved'; end if;
  end if;

  -- ── 표마다 (정적 SQL 세 갈래 · seq 안 주면 max+1) ──
  if p_target = 'supplier' then
    if v_created then
      if v_seq is null then select coalesce(max(seq), 0) + 1 into v_seq from public.supplier_discount where supplier_id = p_target_id; end if;
      insert into public.supplier_discount (supplier_id, name, percent, seq, note, is_active, source)
      values (p_target_id, v_name, v_pct, v_seq, v_note, coalesce(v_active, true), 'manual')
      returning to_jsonb(supplier_discount.*) into v_row;
    else
      select supplier_id into v_owner from public.supplier_discount where id = p_id;
      if v_owner is null or v_owner <> p_target_id then raise exception 'Discount line % is not on this supplier — nothing was saved', p_id; end if;
      update public.supplier_discount set
        name      = coalesce(v_name, name),
        percent   = coalesce(v_pct, percent),
        seq       = coalesce(v_seq, seq),
        note      = case when p_patch ? 'note' then v_note else note end,
        is_active = coalesce(v_active, is_active)
      where id = p_id returning to_jsonb(supplier_discount.*) into v_row;
      if not found then raise exception 'Discount line % on this % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_id, p_target; end if;   -- ②-b
    end if;
  elsif p_target = 'po' then
    if v_created then
      if v_seq is null then select coalesce(max(seq), 0) + 1 into v_seq from public.po_discount where po_id = p_target_id; end if;
      insert into public.po_discount (po_id, seq, name, percent, supplier_discount_id, note)
      values (p_target_id, v_seq, v_name, v_pct, v_src, v_note)
      returning to_jsonb(po_discount.*) into v_row;
    else
      select po_id into v_owner from public.po_discount where id = p_id;
      if v_owner is null or v_owner <> p_target_id then raise exception 'Discount line % is not on this PO — nothing was saved', p_id; end if;
      update public.po_discount set
        name                 = coalesce(v_name, name),
        percent              = coalesce(v_pct, percent),
        seq                  = coalesce(v_seq, seq),
        supplier_discount_id = case when p_patch ? 'supplier_discount_id' then v_src else supplier_discount_id end,
        note                 = case when p_patch ? 'note' then v_note else note end
      where id = p_id returning to_jsonb(po_discount.*) into v_row;
      if not found then raise exception 'Discount line % on this % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_id, p_target; end if;   -- ②-b
    end if;
  else
    if v_created then
      if v_seq is null then select coalesce(max(seq), 0) + 1 into v_seq from public.po_invoice_discount where po_invoice_id = p_target_id; end if;
      insert into public.po_invoice_discount (po_invoice_id, seq, name, percent, supplier_discount_id, note)
      values (p_target_id, v_seq, v_name, v_pct, v_src, v_note)
      returning to_jsonb(po_invoice_discount.*) into v_row;
    else
      select po_invoice_id into v_owner from public.po_invoice_discount where id = p_id;
      if v_owner is null or v_owner <> p_target_id then raise exception 'Discount line % is not on this invoice — nothing was saved', p_id; end if;
      update public.po_invoice_discount set
        name                 = coalesce(v_name, name),
        percent              = coalesce(v_pct, percent),
        seq                  = coalesce(v_seq, seq),
        supplier_discount_id = case when p_patch ? 'supplier_discount_id' then v_src else supplier_discount_id end,
        note                 = case when p_patch ? 'note' then v_note else note end
      where id = p_id returning to_jsonb(po_invoice_discount.*) into v_row;
      if not found then raise exception 'Discount line % on this % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_id, p_target; end if;   -- ②-b
    end if;
  end if;

  return jsonb_build_object('target', p_target, 'target_id', p_target_id, 'row', v_row, 'created', v_created);
exception
  when unique_violation then
    raise exception 'seq % is already used on this % — pick a free number (gaps are fine; order is what matters) — nothing was saved', v_seq, p_target;
end;
$$;

-- ═══ 8) po_discount_delete — 두 묶음 + delete 3곳 0행 검사 ═══
create or replace function public.po_discount_delete(
  p_target text,
  p_id     uuid
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_n     int;                                                  -- ②-b: row_count
  v_po    public.po%rowtype;
  v_inv   public.po_invoice%rowtype;
  v_seq   int;  v_owner uuid;  v_refs int;
begin
  if p_target not in ('supplier', 'po', 'invoice') then raise exception 'p_target must be supplier, po or invoice — nothing was deleted'; end if;
  perform public.ims_require_write(case when p_target = 'supplier' then 'master' else 'purchasing' end, 'deleted');   -- ②-b: 두 묶음 — 갈래로 가른다

  if p_target = 'supplier' then
    select supplier_id, seq into v_owner, v_seq from public.supplier_discount where id = p_id;
    if v_owner is null then raise exception 'Supplier discount % not found — nothing was deleted', p_id; end if;
    select (select count(*) from public.po_discount where supplier_discount_id = p_id)
         + (select count(*) from public.po_invoice_discount where supplier_discount_id = p_id) into v_refs;
    if v_refs > 0 then
      -- FK(no action)가 어차피 막는다 — 마스터는 지우지 않고 내린다(§3-f 관례)
      raise exception 'Supplier discount is referenced by % document discount line(s) — deactivate it instead (is_active=false) — nothing was deleted', v_refs;
    end if;
    delete from public.supplier_discount where id = p_id;
    get diagnostics v_n = row_count; if v_n = 0 then raise exception 'Discount line % on this % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', p_id, p_target; end if;   -- ②-b
  elsif p_target = 'po' then
    select po_id, seq into v_owner, v_seq from public.po_discount where id = p_id;
    if v_owner is null then raise exception 'PO discount % not found — nothing was deleted', p_id; end if;
    select * into v_po from public.po where id = v_owner;
    if v_po.status in ('closed', 'cancelled') then raise exception 'PO % is % — discounts cannot be deleted — nothing was deleted', v_po.po_number, v_po.status; end if;
    delete from public.po_discount where id = p_id;
    get diagnostics v_n = row_count; if v_n = 0 then raise exception 'Discount line % on this % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', p_id, p_target; end if;   -- ②-b
  else
    select po_invoice_id, seq into v_owner, v_seq from public.po_invoice_discount where id = p_id;
    if v_owner is null then raise exception 'Invoice discount % not found — nothing was deleted', p_id; end if;
    select * into v_inv from public.po_invoice where id = v_owner;
    if v_inv.status <> 'draft' then
      raise exception '% % is % — discounts can be deleted only while draft — nothing was deleted',
        case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end, v_inv.invoice_number, v_inv.status;
    end if;
    delete from public.po_invoice_discount where id = p_id;
    get diagnostics v_n = row_count; if v_n = 0 then raise exception 'Discount line % on this % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', p_id, p_target; end if;   -- ②-b
  end if;

  return jsonb_build_object('deleted', true, 'target', p_target, 'id', p_id, 'seq', v_seq, 'target_id', v_owner);
end;
$$;

-- ═══ 검증 (Caleb · psql heredoc · 회신 §5) ═══
-- select proname, prosecdef from pg_proc where proname in ('po_invoice_create','po_invoice_add_po_lines','po_invoice_line_add','po_invoice_line_update','po_invoice_line_delete','po_invoice_confirm','po_discount_save','po_discount_delete') order by 1;
--   → 8행 · 전부 prosecdef=false · 각 이름 1개
-- select proname, count(*) from pg_proc where proname like 'po\_%' group by 1 having count(*) > 1;   → 0행
