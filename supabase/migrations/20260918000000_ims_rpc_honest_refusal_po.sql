-- ─────────────────────────────────────────────────────────────
-- 쓰기 RPC 가 막혔을 때 정직하게 답한다 — ①/③ 발주 계열 (Asung-IMS) · 2026-09-17 밤
--
-- 앞 차수: 20260917230000(판정 함수 여섯 · 5b4e4c7) · 20260917235000(표별 RLS · 352d024). 리시빙 여덟 차수의 ②-b — 앞 차수 이견 1 이 찾아낸 것.
-- 정본: docs/design/po-module.md §5 — ⚠️ 규약 한 줄이 새로 선다(회신 「정본 갱신」): 「쓰기 RPC 는 첫머리에서 쓰기 권한을 보고 · delete·update 뒤 row_count 를 본다」
--
-- ⭐⭐ 무엇이 문제였나 — RLS 는 쓰기를 거부하지 않는다. **안 보이게 한다.**
--   읽기 전용 사용자가 삭제 RPC 를 부르면 앞의 select 검사는 통과하고(읽기 열림) delete 는 0행이 되며, 함수에 row_count 검사가 없어
--   `deleted: true` 를 돌려줬다. 정책은 막았고 함수가 거짓말을 했다. insert 는 42501 로 죽는데 그 문장은 사람이 읽는 말이 아니다.
--
-- ⭐ 고치는 것 둘 [Caleb 2026-09-17 「전부 하자」]
--   ① 함수 첫머리에서 ims_can_write('<묶음>') — false 면 읽을 수 있는 문장으로 거부한다(RLS 에 닿기 전에). 42501 도 0행 거짓말도 사라진다.
--   ② delete·update 뒤 row_count 를 본다 — 0행이면 예외. ①이 있어도 필요하다: 권한이 있는데도 0행인 경우가 있다(그 사이 남이 지웠다·바꿨다).
--   거부 문장은 관례를 따른다 — 「… — nothing was saved」 / 삭제 「… — nothing was deleted」 · 무엇이 없어서 막혔는지 이름으로.
--
-- ═══ 조사 (2026091*.sql 전수 · 마지막 판 기준 · 개수는 세었다) ═══
--   쓰기 RPC 23 (읽기 8 제외: po_detail · po_invoice_detail · po_charge_detail · po_payment_detail · po_uninvoiced_lines · po_charge_alloc_propose · po_payment_target_check · po_credit_next_number)
--   delete·update 뒤 row_count 를 안 보는 것: delete 6 함수/10 문장 · update 9 함수/16 문장 (`returning * into` 는 있으나 not found 검사 없음 — 0행이면 변수만 null 이 되고 성공 응답)
--   두 묶음을 건드리는 함수 2: po_discount_save · po_discount_delete (p_target='supplier' → supplier_discount = master) — ②-b-2 에서 갈래 안에서 가른다. 그 외 전수 확인 — 없다.
--   전부 다시 내면 본문만 2,014행 ⇒ 한 차수 상한(900)의 두 배 ⇒ **셋으로 나눈다** (원본 마이그레이션의 계보를 따른다):
--     ②-b-1 (이 파일)  발주 계열 6 — po_create · po_lines_paste · po_line_update · po_line_delete · po_doc_cancel · po_doc_delete
--     ②-b-2             인보이스·할인 8 — po_invoice_create · po_invoice_add_po_lines · po_invoice_line_add/update/delete · po_invoice_confirm · po_discount_save · po_discount_delete (두 묶음 둘 포함)
--     ②-b-3             비용·결제 9 — po_charge_create · po_charge_alloc_add/update/delete/spread · po_charge_confirm · po_payment_create · po_payment_alloc_set/delete
--   시그니처: 여섯 전부 인자 무변 ⇒ create or replace 로 덧씌워진다(확인함 · 20260917170000 의 drop 사례는 인자가 늘어난 경우). 같은 OID 라 grant·comment 는 그대로 남는다(Postgres 규칙) — 다시 적지 않는다.
--   security invoker 그대로 ⇒ ims_can_write() 는 함수 안에서도 호출자(auth.uid())를 본다(definer 는 판정 함수 자신만).
--
-- ═══ 화면이 볼 것 — 거부 문장의 모양(기존 문장은 한 글자도 바꾸지 않았다 · docErr 가 그대로 띄운다) ═══
--   권한 없음(읽기만)   You can read purchasing but not change it — ask an admin to add the 'purchasing' permission — nothing was saved|deleted
--   권한 없음(전무)     You do not have purchasing access — ask an admin to add the 'purchasing' permission — nothing was saved|deleted
--   0행                 <문서> … was not saved|deleted — it may have been removed or changed by someone else just now — nothing was saved|deleted
--
-- ⭐ 도우미 ims_require_write(p_screen, p_verb) — 이견 1: 23 함수에 같은 두 문장을 복사하지 않기 위해 한 곳에 둔다(판정은 여전히 ims_can_write 하나).
--   raise 만 하는 함수 · security invoker · stable. 반대면 각 함수의 첫 줄을 if not ims_can_write(...) then raise ... 로 펴면 된다(기계적).
-- ─────────────────────────────────────────────────────────────

-- ═══ 0) 도우미 — 읽을 수 있는 거부 문장 한 곳 ═══
create or replace function public.ims_require_write(p_screen text, p_verb text default 'saved') returns void
  language plpgsql stable
  set search_path = public, pg_temp
as $$
begin
  if public.ims_can_write(p_screen) then
    return;
  end if;
  if public.ims_can_view(p_screen) then
    raise exception 'You can read % but not change it — ask an admin to add the ''%'' permission — nothing was %', p_screen, p_screen, p_verb;
  end if;
  raise exception 'You do not have % access — ask an admin to add the ''%'' permission — nothing was %', p_screen, p_screen, p_verb;
end;
$$;
comment on function public.ims_require_write(text, text) is
  '쓰기 RPC 첫머리 — ims_can_write(p_screen) 가 false 면 읽을 수 있는 문장으로 거부(RLS 에 닿기 전에). p_verb = saved | deleted (문장 끝 관례). 판정은 ims_can_write 하나 · 이 함수는 문장만 (2026-09-17 ②-b)';
revoke all on function public.ims_require_write(text, text) from public, anon;
grant execute on function public.ims_require_write(text, text) to authenticated;

-- ═══ 1) po_create — 첫머리 권한 (insert 만 · row_count 불필요) ═══
create or replace function public.po_create(
  p_supplier_id  uuid,
  p_warehouse_id uuid default null,
  p_order_date   date default null,
  p_note         text default null
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_sup       public.supplier%rowtype;
  v_cur       uuid;
  v_wh        uuid;
  v_wh_n      int;
  v_ct        public.supplier_contact%rowtype;   -- 그날의 연락처
  v_ct_n      int;
  v_ct_def_n  int;
  v_ad        public.supplier_address%rowtype;   -- 그날의 주소
  v_ad_n      int;
  v_ad_bil_n  int;
  v_acct_code text;
  v_acct_id   uuid;
  v_po_id     uuid;
  v_po_number text;
  v_disc      int := 0;
  v_warn      text[] := '{}';
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b: RLS 에 닿기 전에 읽을 수 있는 말로

  -- 만든 사람 — 서버 유도(§10-h 열쇠 auth_user_id) · 행이 없으면 아무것도 안 쓴다
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then
    raise exception 'No active staff record for this login — nothing was saved';
  end if;

  select * into v_sup from public.supplier where id = p_supplier_id;
  if not found then
    raise exception 'Supplier % not found — nothing was saved', p_supplier_id;
  end if;
  -- ⚠️ 비활성·미판정 공급처는 막지 않는다 — 판정은 화면의 정돈 규칙(§10-j 3-b) 한곳에. 여기서는 알리기만
  if not v_sup.is_active then v_warn := array_append(v_warn, 'supplier_inactive'); end if;
  if v_sup.is_purchasable is distinct from true then v_warn := array_append(v_warn, 'supplier_not_purchasable'); end if;

  -- 통화 — 공급처 기본통화 · 없으면 inv_config.base_currency · 그것도 없으면 예외(po.currency_id 는 not null)
  v_cur := v_sup.currency_id;
  if v_cur is null then
    select c.id into v_cur
    from public.ref_currency c
    join public.inv_config k on k.key = 'base_currency' and k.value = c.code;
    if v_cur is null then
      raise exception 'Supplier has no currency and inv_config.base_currency does not point at a ref_currency row — nothing was saved';
    end if;
    v_warn := array_append(v_warn, 'currency_defaulted');
  end if;

  -- 창고 — 준 것 · 아니면 기본 창고가 정확히 하나일 때만(짐작으로 고르지 않는다)
  v_wh := p_warehouse_id;
  if v_wh is null then
    select count(*), (array_agg(w.id))[1] into v_wh_n, v_wh
    from public.ref_warehouse w where w.is_default and w.is_active;
    if coalesce(v_wh_n, 0) <> 1 then
      v_wh := null;
      v_warn := array_append(v_warn, 'warehouse_unset');
    end if;
  end if;

  -- ⭐ 그날의 연락처 — 활성 중 is_default 가 정확히 하나면 그것 · 아니면 활성이 정확히 하나면 그것 · 그 외 null + 경고
  --    [실측 2026-09-16] 활성 226 중 기본 정확히 하나 159 · 기본 없이 하나 20 · 0건 44 ⇒ 179 곳을 덮는다
  select count(*), count(*) filter (where c.is_default) into v_ct_n, v_ct_def_n
  from public.supplier_contact c where c.supplier_id = p_supplier_id and c.is_active;
  if v_ct_def_n = 1 then
    select * into v_ct from public.supplier_contact c where c.supplier_id = p_supplier_id and c.is_active and c.is_default;
  elsif v_ct_n = 1 then
    select * into v_ct from public.supplier_contact c where c.supplier_id = p_supplier_id and c.is_active;
  elsif v_ct_n = 0 then
    v_warn := array_append(v_warn, 'contact_unset');
  else
    v_warn := array_append(v_warn, 'contact_ambiguous');
  end if;

  -- ⭐ 그날의 주소 — 활성 1건이면 그것 · 여럿이면 Billing 이 정확히 하나면 그것 · 그 외 null + 경고 (§3-b B 규칙 · DefaultForType 은 안 담았다)
  --    ⚠️ [실측] 활성 226 중 주소 0건 143 ⇒ address_unset 이 대다수에서 뜬다 — 화면이 오류처럼 그리면 안 된다(말만)
  select count(*), count(*) filter (where a.type = 'Billing') into v_ad_n, v_ad_bil_n
  from public.supplier_address a where a.supplier_id = p_supplier_id and a.is_active;
  if v_ad_n = 1 then
    select * into v_ad from public.supplier_address a where a.supplier_id = p_supplier_id and a.is_active;
  elsif v_ad_n > 1 and v_ad_bil_n = 1 then
    select * into v_ad from public.supplier_address a where a.supplier_id = p_supplier_id and a.is_active and a.type = 'Billing';
  elsif v_ad_n = 0 then
    v_warn := array_append(v_warn, 'address_unset');
  else
    v_warn := array_append(v_warn, 'address_ambiguous');
  end if;

  -- 세금규칙 — 공급처 원문 그대로(실측 226/226 채움 · 비어 있으면 알리기만)
  if v_sup.tax_rule is null then v_warn := array_append(v_warn, 'tax_rule_unset'); end if;

  -- ⭐ 재고 자산 계정 — inv_config po_inventory_account_code → ref_account.code (없으면 null + 경고 · 활성 여부는 안 본다 — 기본값이 비활성이면 그것이 보여야 한다)
  select k.value into v_acct_code from public.inv_config k where k.key = 'po_inventory_account_code';
  if v_acct_code is not null then
    select r.id into v_acct_id from public.ref_account r where r.code = v_acct_code;
  end if;
  if v_acct_id is null then
    v_acct_code := null;                                  -- 코드가 표에 없으면 원문도 박지 않는다(짐작 값을 남기지 않는다)
    v_warn := array_append(v_warn, 'inventory_account_unset');
  end if;

  -- ① po 한 행 — po_number 는 기본값 po_next_number() · 결제조건은 FK + 원문 · 연락처·주소는 원문만(그날 값)
  insert into public.po (status, supplier_id, currency_id, payment_term_id, payment_term_name, ship_to_warehouse_id, order_date, created_by, note,
                         tax_rule, inventory_account_id, inventory_account_code,
                         supplier_contact_name, supplier_contact_phone, supplier_contact_email,
                         supplier_address_line1, supplier_address_line2, supplier_city, supplier_state_province, supplier_postal_code, supplier_country)
  values ('draft', p_supplier_id, v_cur, v_sup.payment_term_id, v_sup.payment_term_name, v_wh, coalesce(p_order_date, current_date), v_staff, p_note,
          v_sup.tax_rule, v_acct_id, v_acct_code,
          v_ct.name, v_ct.phone, v_ct.email,
          v_ad.line1, v_ad.line2, v_ad.city, v_ad.state_province, v_ad.postal_code, v_ad.country)
  returning id, po_number into v_po_id, v_po_number;

  -- ② supplier_discount → po_discount 복사(예상 층 · §11-e · 활성만 · seq 그대로 · 원천 id 를 남긴다) — 지금 0행 · 채우면 듣는다
  insert into public.po_discount (po_id, seq, name, percent, supplier_discount_id)
  select v_po_id, d.seq, d.name, d.percent, d.id
  from public.supplier_discount d
  where d.supplier_id = p_supplier_id and d.is_active
  order by d.seq;
  get diagnostics v_disc = row_count;

  return jsonb_build_object(
    'id', v_po_id, 'po_number', v_po_number, 'status', 'draft',
    'currency_id', v_cur, 'ship_to_warehouse_id', v_wh, 'payment_term_name', v_sup.payment_term_name,
    'tax_rule', v_sup.tax_rule, 'inventory_account_code', v_acct_code,
    'supplier_contact_name', v_ct.name, 'supplier_contact_email', v_ct.email,
    'supplier_address_line1', v_ad.line1,
    'discounts_copied', v_disc,
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 2) po_lines_paste — 첫머리 권한 (insert 만) · ⚠️ 미리 보기(p_commit=false)도 막는다: 붙여넣기 판정은 쓰기 화면의 일이고, 두 갈래로 가르면 「왜 미리 보기는 되는데 저장이 안 되지」가 생긴다 ═══
create or replace function public.po_lines_paste(
  p_po_id  uuid,
  p_lines  jsonb,                          -- [{sku, qty}]
  p_commit boolean default false
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_limit      constant int := 500;
  v_po         public.po%rowtype;
  v_n          int;
  v_next       int;
  r            record;
  v_sku        text;
  v_qty        numeric;
  v_pid        uuid;  v_psku text;  v_pname text;  v_pactive boolean;
  v_fixed      numeric;  v_cost numeric;  v_ssku text;  v_lactive boolean;  v_link_found boolean;
  v_verdict    text;
  v_msgs       text[];
  v_price      numeric;
  v_src        text;
  v_line_no    int;
  v_inserted   boolean;
  v_exists_no  int;
  v_seen_ids   uuid[] := '{}';
  v_seen_n     int[]  := '{}';
  v_dup_of     int;
  v_rows       jsonb := '[]'::jsonb;
  n_ok int := 0; n_nolink int := 0; n_nf int := 0; n_dup int := 0; n_ex int := 0; n_bad int := 0; n_ins int := 0;
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_po from public.po where id = p_po_id;
  if not found then
    raise exception 'PO % not found — nothing was saved', p_po_id;
  end if;
  if v_po.status in ('closed', 'cancelled') then
    raise exception 'PO % is % — lines cannot be added (closed = receiving finished) — nothing was saved', v_po.po_number, v_po.status;
  end if;

  v_n := coalesce(jsonb_array_length(p_lines), 0);
  if v_n > c_limit then
    -- ⭐ 예외가 아니라 판정 — 미리 보기 단계에서 걸리고 넣지도 않는다(Caleb)
    return jsonb_build_object(
      'po_id', p_po_id, 'po_number', v_po.po_number, 'committed', false,
      'summary', jsonb_build_object('total', v_n, 'ok', 0, 'no_link', 0, 'not_found', 0, 'duplicate', 0, 'exists', 0, 'bad_qty', 0, 'inserted', 0,
                                    'too_many', true, 'limit', c_limit,
                                    'message', format('Too many lines (%s) — up to %s lines per paste. Nothing was saved.', v_n, c_limit)),
      'lines', '[]'::jsonb);
  end if;

  select coalesce(max(line_no), 0) into v_next from public.po_line where po_id = p_po_id;

  for r in
    select t.ord::int as n, t.e->>'sku' as sku_raw, t.e->>'qty' as qty_raw
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) with ordinality as t(e, ord)
    order by t.ord
  loop
    v_pid := null; v_psku := null; v_pname := null; v_pactive := null;
    v_fixed := null; v_cost := null; v_ssku := null; v_lactive := null; v_link_found := false;
    v_verdict := null; v_msgs := '{}'; v_price := null; v_src := null; v_line_no := null; v_inserted := false; v_dup_of := null; v_exists_no := null;

    -- SKU 다듬기 — 앞뒤 공백(비분리 공백 포함)만
    v_sku := nullif(regexp_replace(coalesce(r.sku_raw, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
    -- 수량 — 숫자만
    v_qty := case when r.qty_raw ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then r.qty_raw::numeric else null end;

    if v_sku is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'empty_sku');
    else
      select p.id, p.sku, p.name, p.is_active into v_pid, v_psku, v_pname, v_pactive
      from public.product p where p.sku = v_sku;                                  -- 유니크 인덱스
      if v_pid is null then
        select p.id, p.sku, p.name, p.is_active into v_pid, v_psku, v_pname, v_pactive
        from public.product p where upper(p.sku) = upper(v_sku) limit 1;         -- 폴백 · 인덱스 없음 · 못 찾은 줄에만
        if v_pid is not null then v_msgs := array_append(v_msgs, 'case_fixed'); end if;
      end if;
    end if;

    if v_verdict is null and v_pid is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'sku_not_in_product');
    end if;

    if v_verdict is null then
      if v_pactive is false then v_msgs := array_append(v_msgs, 'inactive_product'); end if;   -- 막지 않는다(제품은 감추지 않는다 · §10-j 3-b) · 알린다
      v_dup_of := (select v_seen_n[i] from generate_subscripts(v_seen_ids, 1) i where v_seen_ids[i] = v_pid limit 1);
      if v_dup_of is not null then
        v_verdict := 'duplicate';
        v_msgs := array_append(v_msgs, format('duplicate_of_paste_line_%s — fix the source and paste again', v_dup_of));
      else
        v_seen_ids := array_append(v_seen_ids, v_pid); v_seen_n := array_append(v_seen_n, r.n);
        select pl.line_no into v_exists_no from public.po_line pl where pl.po_id = p_po_id and pl.product_id = v_pid order by pl.line_no limit 1;
        if v_exists_no is not null then
          v_verdict := 'exists';
          v_msgs := array_append(v_msgs, format('already_on_line_%s — to change the quantity edit that line (po_line_update), not paste', v_exists_no));
        elsif v_qty is null or v_qty <= 0 then
          v_verdict := 'bad_qty'; v_msgs := array_append(v_msgs, 'qty_must_be_positive_number');
        else
          select ps.fixed_cost, ps.cost, ps.supplier_sku, ps.is_active, true
            into v_fixed, v_cost, v_ssku, v_lactive, v_link_found
          from public.product_supplier ps where ps.product_id = v_pid and ps.supplier_id = v_po.supplier_id;   -- (product_id, supplier_id) 유니크 인덱스
          if not coalesce(v_link_found, false) then
            v_verdict := 'no_link'; v_msgs := array_append(v_msgs, 'no_product_supplier_link_for_this_supplier — price 0, fill in by hand');
            v_price := 0; v_src := 'none'; v_ssku := null;
          elsif v_lactive is false then
            v_verdict := 'no_link'; v_msgs := array_append(v_msgs, 'link_inactive — price not suggested (§3-f), fill in by hand');
            v_price := 0; v_src := 'none';
          else
            v_verdict := 'ok';
            if coalesce(v_fixed, 0) > 0 then v_price := v_fixed; v_src := 'fixed';
            elsif coalesce(v_cost, 0) > 0 then v_price := v_cost; v_src := 'latest';
            else v_price := 0; v_src := 'none'; v_msgs := array_append(v_msgs, 'no_price — fixed and latest are both empty');
            end if;
          end if;
        end if;
      end if;
    end if;

    -- 넣을 수 있는 줄만 번호를 받는다
    if v_verdict in ('ok', 'no_link') then
      v_next := v_next + 1; v_line_no := v_next;
      if p_commit then
        insert into public.po_line (po_id, line_no, product_id, supplier_sku, qty_ea, unit_price)
        values (p_po_id, v_line_no, v_pid, v_ssku, v_qty, v_price);
        v_inserted := true; n_ins := n_ins + 1;
      end if;
    end if;

    case v_verdict
      when 'ok' then n_ok := n_ok + 1;
      when 'no_link' then n_nolink := n_nolink + 1;
      when 'not_found' then n_nf := n_nf + 1;
      when 'duplicate' then n_dup := n_dup + 1;
      when 'exists' then n_ex := n_ex + 1;
      when 'bad_qty' then n_bad := n_bad + 1;
      else null;
    end case;

    v_rows := v_rows || jsonb_build_object(
      'n', r.n, 'input_sku', r.sku_raw, 'input_qty', r.qty_raw,
      'verdict', v_verdict,
      'product_id', v_pid, 'sku', v_psku, 'product_name', v_pname, 'product_active', v_pactive,
      'unit_price', v_price, 'price_source', v_src, 'supplier_sku', v_ssku,
      'line_no', v_line_no, 'inserted', v_inserted,
      'message', array_to_string(v_msgs, ' · '));
  end loop;

  return jsonb_build_object(
    'po_id', p_po_id, 'po_number', v_po.po_number, 'committed', p_commit,
    'summary', jsonb_build_object('total', v_n, 'ok', n_ok, 'no_link', n_nolink, 'not_found', n_nf, 'duplicate', n_dup, 'exists', n_ex, 'bad_qty', n_bad,
                                  'inserted', n_ins, 'too_many', false, 'limit', c_limit, 'message', null),
    'lines', v_rows);
end;
$$;

-- ═══ 3) po_line_update — 첫머리 권한 + update 0행 검사 ═══
create or replace function public.po_line_update(
  p_line_id uuid,
  p_patch   jsonb
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_line   public.po_line%rowtype;
  v_po     public.po%rowtype;
  v_recv   numeric;
  v_qty    numeric;
  v_line_no int;                                                -- ②-b: 0행이면 v_line 이 null 로 덮이므로 번호를 미리 든다
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_line from public.po_line where id = p_line_id;
  if not found then
    raise exception 'PO line % not found — nothing was saved', p_line_id;
  end if;
  v_line_no := v_line.line_no;
  select * into v_po from public.po where id = v_line.po_id;
  if v_po.status in ('closed', 'cancelled') then
    raise exception 'PO % is % — lines cannot be changed (closed = receiving finished) — nothing was saved', v_po.po_number, v_po.status;
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'p_patch must be a JSON object — nothing was saved';
  end if;

  select coalesce(sum(qty_ea), 0) into v_recv from public.po_receipt_line where po_line_id = p_line_id;

  if p_patch ? 'qty_ea' then
    v_qty := (p_patch->>'qty_ea')::numeric;
    if v_qty is null or v_qty <= 0 then
      raise exception 'qty_ea must be a positive number — nothing was saved';
    end if;
    -- ⭐ 받은 것보다 적게 줄일 수 없다(§1 ①) — 100 시켜 90 온 것은 라인 수정이 아니라 입고 90 · 크레딧 10 이다
    if v_qty < v_recv then
      raise exception 'Line % of %: cannot set quantity to % — % already received. Quantity must be at least the received quantity. Nothing was saved',
        v_line.line_no, v_po.po_number, v_qty, v_recv;
    end if;
  end if;

  update public.po_line set
    qty_ea                  = case when p_patch ? 'qty_ea'                  then (p_patch->>'qty_ea')::numeric                 else qty_ea end,
    unit_price              = case when p_patch ? 'unit_price'              then (p_patch->>'unit_price')::numeric             else unit_price end,
    supplier_sku            = case when p_patch ? 'supplier_sku'            then nullif(p_patch->>'supplier_sku', '')          else supplier_sku end,
    tax_rule                = case when p_patch ? 'tax_rule'                then nullif(p_patch->>'tax_rule', '')              else tax_rule end,
    note                    = case when p_patch ? 'note'                    then nullif(p_patch->>'note', '')                  else note end,
    entered_unit_product_id = case when p_patch ? 'entered_unit_product_id' then nullif(p_patch->>'entered_unit_product_id', '')::uuid else entered_unit_product_id end,
    entered_qty             = case when p_patch ? 'entered_qty'             then nullif(p_patch->>'entered_qty', '')::numeric  else entered_qty end,
    entered_pack_factor     = case when p_patch ? 'entered_pack_factor'     then nullif(p_patch->>'entered_pack_factor', '')::numeric else entered_pack_factor end
  where id = p_line_id
  returning * into v_line;
  if not found then                                             -- ②-b: 권한은 있었는데 0행 — 그 사이 지워졌거나 정책이 감췼다
    raise exception 'Line % of % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_line_no, v_po.po_number;
  end if;
  -- CHECK(qty_ea > 0 · unit_price >= 0 · entered_unit_ck)는 표가 그대로 지킨다 — 어기면 표의 예외가 그대로 올라간다

  return jsonb_build_object('line', to_jsonb(v_line), 'received_qty', v_recv, 'po_number', v_po.po_number, 'status', v_po.status);
end;
$$;

-- ═══ 4) po_line_delete — 첫머리 권한 + delete 0행 검사 ═══
create or replace function public.po_line_delete(
  p_line_id uuid
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_line   public.po_line%rowtype;
  v_po     public.po%rowtype;
  v_recv   int;
  v_inv    int;
  v_n      int;                                                 -- ②-b: row_count
begin
  perform public.ims_require_write('purchasing', 'deleted');   -- ②-b

  select * into v_line from public.po_line where id = p_line_id;
  if not found then
    raise exception 'PO line % not found — nothing was deleted', p_line_id;
  end if;
  select * into v_po from public.po where id = v_line.po_id;
  if v_po.status in ('closed', 'cancelled') then
    raise exception 'PO % is % — lines cannot be deleted — nothing was deleted', v_po.po_number, v_po.status;
  end if;
  select count(*) into v_recv from public.po_receipt_line where po_line_id = p_line_id;
  if v_recv > 0 then
    raise exception 'Line % of % has % receipt line(s) — a received line cannot be deleted (reduce nothing; receipts are events) — nothing was deleted', v_line.line_no, v_po.po_number, v_recv;
  end if;
  select count(*) into v_inv from public.po_invoice_line where po_line_id = p_line_id;
  if v_inv > 0 then
    -- FK(no action)가 어차피 막지만 사람이 읽을 수 있는 말로 먼저 막는다
    raise exception 'Line % of % is referenced by % invoice/credit line(s) — remove those first — nothing was deleted', v_line.line_no, v_po.po_number, v_inv;
  end if;

  delete from public.po_line where id = p_line_id;
  get diagnostics v_n = row_count;                              -- ②-b
  if v_n = 0 then
    raise exception 'Line % of % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', v_line.line_no, v_po.po_number;
  end if;
  return jsonb_build_object('deleted', true, 'po_id', v_po.id, 'po_number', v_po.po_number, 'line_no', v_line.line_no);
end;
$$;

-- ═══ 5) po_doc_cancel — 첫머리 권한 + update 6곳 0행 검사 (p_target=payment 거부보다 권한이 먼저 — 권한 없는 사람에게는 무엇을 부르든 같은 대답) ═══
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
  v_doc          text;                                          -- ②-b: 0행 문장용 문서 이름(rowtype 이 null 로 덮이기 전에 든다)
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

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
    v_doc := 'PO ' || v_po.po_number;

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
      if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    else
      if v_po.status <> 'cancelled' then
        raise exception 'PO % is % — only a cancelled order can be restored — nothing was saved', v_po.po_number, v_po.status;
      end if;
      v_new_status := case when v_po.confirmed_at is not null then 'confirmed' else 'draft' end;
      update public.po set status = v_new_status, cancelled_at = null, cancelled_by = null
      where id = p_id returning * into v_po;
      if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
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
    v_doc := 'Charge ' || v_chg.charge_number;
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
      if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    else
      if v_chg.status <> 'cancelled' then
        raise exception 'Charge % is % — only a cancelled document can be restored — nothing was saved', v_chg.charge_number, v_chg.status;
      end if;
      v_new_status := case when v_chg.confirmed_at is not null then 'confirmed' else 'draft' end;
      update public.po_charge set status = v_new_status, cancelled_at = null, cancelled_by = null
      where id = p_id returning * into v_chg;
      if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
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
  v_doc := v_label || ' ' || v_inv.invoice_number;
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
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;     -- ②-b

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
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;     -- ②-b
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

-- ═══ 6) po_doc_delete — 첫머리 권한 + delete 4곳 0행 검사 ═══
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
  v_del       int;                                              -- ②-b: row_count
begin
  perform public.ims_require_write('purchasing', 'deleted');   -- ②-b

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
    get diagnostics v_del = row_count;                          -- ②-b
    if v_del = 0 then
      raise exception 'PO % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', v_po.po_number;
    end if;

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
    get diagnostics v_del = row_count;                          -- ②-b
    if v_del = 0 then
      raise exception 'Charge % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', v_chg.charge_number;
    end if;

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
    get diagnostics v_del = row_count;                          -- ②-b
    if v_del = 0 then
      raise exception 'Payment % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', coalesce(v_pay.reference, p_id::text);
    end if;

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
  get diagnostics v_del = row_count;                            -- ②-b
  if v_del = 0 then
    raise exception '% % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', v_label, v_inv.invoice_number;
  end if;

  return jsonb_build_object(
    'deleted', true, 'target', 'invoice', 'id', v_inv.id, 'doc_kind', v_inv.doc_kind, 'invoice_number', v_inv.invoice_number, 'status_before', v_inv.status,
    'lines_deleted', v_lines, 'discounts_deleted', v_discs);
end;
$$;

-- ═══ 검증 (Caleb · psql heredoc · 회신 §5) ═══
-- select proname, prosecdef from pg_proc where proname in ('ims_require_write','po_create','po_lines_paste','po_line_update','po_line_delete','po_doc_cancel','po_doc_delete') order by 1;
--   → 7행 · 전부 prosecdef=false(invoker) · 각 이름 1개(오버로드 없음)
-- select proname, count(*) from pg_proc where proname like 'po\_%' group by 1 having count(*) > 1;   → 0행
