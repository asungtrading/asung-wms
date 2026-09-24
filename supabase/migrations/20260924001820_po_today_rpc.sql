-- PO 「오늘」 ② — 서버 함수 일곱 재발행 · current_date → public.ims_today() 만 (2026-09-24 UTC · 파일 시각 UTC · 토론토 2026-09-23 저녁)
-- 지시서 ~/asung/prompts/po-today-1.md · 판정 Caleb 2026-09-23 「(가) 화면 다섯 + 서버 함수 일곱을 함께 고친다」 · 화면 다섯은 대화 Claude(asung-ims torontoToday() · 빌드 2026-09-23)
-- 근거: so-module §13-h(회사의 「오늘」은 토론토 · ims_today() 20260923232500 ⓪) · 20260924000337_po_today_defaults.sql(기본값 넷 · 20:09 EDT 실측 current_date 09-24 · ims_today 09-23)
-- 대상: [테스트 · Asung-IMS] 먼저 — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음)
--
-- ⭐ 규칙 — 조사 표(po-today-1 회신)의 「마지막 정의 · 닿는다」 자리만 · current_date → public.ims_today() 만 바꾼다 · 그 밖은 한 글자도 바꾸지 않는다(바이트 대조 · ②-0b 비분리 공백 사고 선례)
--    시그니처 그대로 ⇒ create or replace(po_receipt_create 만 원본이 create function 이라 or replace 를 더했다 — 바뀐 줄 하나 더) · grant · comment 는 create or replace 가 유지한다(검증에서 확인)
-- ⭐ 일곱(원본 마지막 정의 · 바뀐 줄)
--    po_create             20260918000000_ims_rpc_honest_refusal_po.sql:57              폴백 coalesce(p_order_date, …) 1줄 — 화면이 p_order_date 를 안 보낸다 · 가장 큰 자리
--    po_receipt_create     20260918163552_po_receipt_rpc.sql:75                          인자 기본값 · 비교 received_on_in_future · 폴백 3줄 (+ create or replace)
--    po_receipt_confirm    20260919192236_cost_graft_1.sql:296                           비교 received_on_in_future 1줄
--    po_invoice_create     20260918003000_ims_rpc_honest_refusal_invoice.sql:27          크레딧 번호 연도 · 폴백 2줄
--    po_charge_create      20260918013000_ims_rpc_honest_refusal_charge_payment.sql:25   폴백 · 반환 echo 2줄
--    po_payment_create     20260918013000_ims_rpc_honest_refusal_charge_payment.sql:331  폴백 · 반환 echo 2줄
--    inv_post_receipt      20260919192236_cost_graft_1.sql:154                           비교 received_on_in_future 1줄
-- ⚠️ 고치지 않는 것 — 원장 inv_compare_run 3곳(cron 36 5 UTC = 토론토 01:36 · 그 시각 UTC 날짜 = 토론토 날짜 · 안 닿는다 · 정본 ⬜) · so_deal_best 폴백 둘(닿지 않음 · ⬜) · 덮인 옛 정의 11곳(죽은 코드)
-- ⚠️ 비교 세 곳(received_on_in_future)은 화면이 UTC 날짜를 보내던 동안엔 저녁 입고를 「미래」로 경고했을 것 — 화면 다섯이 torontoToday() 로 함께 바뀌어 짝이 맞는다
-- 검증: ~/asung/prompts/po-today-2-verify.sql — 일곱의 pg_get_functiondef 에 current_date 0 · ims_today 수 12 · 함수 수 그대로(오버로드 0) · grant·comment 유지 · 시간 시험 불가(식을 읽는다)

-- ═══ po_create — 원본 20260918000000_ims_rpc_honest_refusal_po.sql:57 · current_date 1곳 ═══
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
  values ('draft', p_supplier_id, v_cur, v_sup.payment_term_id, v_sup.payment_term_name, v_wh, coalesce(p_order_date, public.ims_today()), v_staff, p_note,
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

-- ═══ po_receipt_create — 원본 20260918163552_po_receipt_rpc.sql:75 · current_date 3곳 + create or replace ═══
create or replace function public.po_receipt_create(
  p_po_id        uuid,
  p_received_on  date default public.ims_today(),
  p_warehouse_id uuid default null                  -- po.ship_to_warehouse_id 가 null 일 때만 쓴다
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_po     public.po%rowtype;
  v_open   text;
  v_wh     uuid;
  v_whn    text;
  v_r      public.po_receipt%rowtype;
  v_warn   text[] := '{}';
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ②

  -- 만든 사람 — 서버 유도(po_create 선례 · 화면이 주지 않는다)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_po from public.po where id = p_po_id;
  if not found then raise exception 'PO % not found — nothing was saved', p_po_id; end if;
  -- ⬜3 confirmed 만 — draft(공급처에 안 갔다) · closed(입고 종료 · 남은 수량은 갈라진 문서로) · cancelled(안 온다)
  if v_po.status <> 'confirmed' then
    raise exception 'PO % is % — receiving can start only on a confirmed order% — nothing was saved',
      v_po.po_number, v_po.status,
      case v_po.status when 'closed' then ' (receiving is finished on this document; the remainder, if any, moved to the split document)'
                       when 'draft'  then ' (confirm it first)'
                       else '' end;
  end if;
  -- ⭐⭐ PO 당 draft 하나 — 부분 유니크 대신 여기서(규칙 29) · 기존 번호를 문장에
  perform pg_advisory_xact_lock(hashtext('po_receipt:' || p_po_id::text));           -- 이견 12 — 둘이 동시에 열면 뒤 것이 앞 것을 본다(권한 불필요 · 트랜잭션 끝에 풀림)
  select r.receipt_number into v_open from public.po_receipt r where r.po_id = p_po_id and r.status = 'draft' order by r.created_at limit 1;
  if v_open is not null then
    raise exception 'PO % already has an open receipt (%) — continue that one or delete it first — nothing was saved', v_po.po_number, v_open;
  end if;
  -- 창고 — PO 의 배송지 · 없으면 인자 · 그것도 없으면 거부(빈은 창고의 것 · ims_last_bin 의 축)
  v_wh := coalesce(v_po.ship_to_warehouse_id, p_warehouse_id);
  if v_wh is null then
    raise exception 'PO % has no ship-to warehouse — pass p_warehouse_id — nothing was saved', v_po.po_number;
  end if;
  if v_po.ship_to_warehouse_id is null then v_warn := array_append(v_warn, 'warehouse_from_parameter'); end if;
  select w.name into v_whn from public.ref_warehouse w where w.id = v_wh and w.is_active;
  if v_whn is null then raise exception 'Warehouse % not found or inactive — nothing was saved', v_wh; end if;
  if p_received_on is not null and p_received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  insert into public.po_receipt (po_id, warehouse_id, received_on, status, created_by)
  values (p_po_id, v_wh, coalesce(p_received_on, public.ims_today()), 'draft', v_staff)
  returning * into v_r;

  return jsonb_build_object(
    'id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status,
    'po_id', v_po.id, 'po_number', v_po.po_number,
    'warehouse_id', v_wh, 'warehouse_name', v_whn, 'received_on', v_r.received_on,
    'created_by', v_staff, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ po_receipt_confirm — 원본 20260919192236_cost_graft_1.sql:296 · current_date 1곳 ═══
create or replace function public.po_receipt_confirm(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security definer                                              -- ⭐ 이견 1 — po·po_line·po_discount(purchasing RLS)에 쓴다. 권한은 첫머리 ims_require_write('receiving') 가 묻는다
set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_r         public.po_receipt%rowtype;
  v_po        public.po%rowtype;
  v_pl        public.po_line%rowtype;
  v_base      text;
  v_max       text;
  v_a_num     text;
  v_b_num     text;
  v_b_id      uuid;
  v_n         int;
  v_free_txt  text;
  v_free_n    int;
  v_work_n    int;
  v_lines_n   int := 0;
  v_over      int := 0;
  v_short     int := 0;
  v_rem_total numeric := 0;
  v_reduced   int := 0;
  v_moved     int := 0;
  v_cleared   text[] := '{}';
  v_warn      text[] := '{}';
  v_rows      jsonb := '[]'::jsonb;
  v_now       timestamptz := now();
  v_ledger    jsonb;                                           -- ⓔ 원장 창구의 반환(원장 이식 2차 · 2026-09-19)
  v_cur       text;                                            -- ⑥ 환율 게이트(원가 이식 1차 · 2026-09-19) — 발주 통화 코드
  v_base_cur  text;                                            -- ⑥ 기준통화 코드 · ⚠️ v_base(접미사를 뗀 PO 번호 · 잠금·채번)와 다른 것 — 이름을 같이 쓰면 채번이 CADa 가 된다(2026-09-19 실사고)
  x           record;
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ② · definer 안에서도 auth.uid() 는 JWT 의 것
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  -- ① 이미 확정·취소
  if v_r.confirmed_at is not null or v_r.status = 'confirmed' then
    raise exception 'Receipt % was already confirmed on % — nothing was saved', v_r.receipt_number, to_char(v_r.confirmed_at, 'YYYY-MM-DD');
  end if;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — only a draft receipt can be confirmed — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was saved', v_r.receipt_number; end if;
  -- ⭐ 잠금 — PO 단위(형제 채번·분할·닫기 · 키는 접미사를 뗀 base) + 라인 단위(작업 줄 RPC 들과 같은 키 · 세는 중인 손을 줄 세운다)
  v_base := regexp_replace(v_po.po_number, '[a-z]+$', '');
  perform pg_advisory_xact_lock(hashtext('po:' || v_base));
  for x in select pl.id from public.po_line pl where pl.po_id = v_po.id loop
    perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || x.id::text));
  end loop;
  -- ④ 잠금 뒤 다시 본다 — 그 사이 닫혔거나 취소됐을 수 있다
  select * into v_po from public.po where id = v_r.po_id;
  if v_po.status <> 'confirmed' then
    raise exception 'PO % is % — a receipt can be confirmed only on a confirmed order — nothing was saved', v_po.po_number, v_po.status;
  end if;
  select * into v_r from public.po_receipt where id = p_receipt_id;                     -- 잠금 뒤 다시(남이 사이에 확정했을 수 있다)
  if v_r.status <> 'draft' or v_r.confirmed_at is not null then
    raise exception 'Receipt % was changed by someone else just now (% ) — reload and try again — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  -- ③ 작업 줄이 없다
  select count(*) into v_work_n from public.po_receipt_work w where w.receipt_id = p_receipt_id;
  if v_work_n = 0 then
    raise exception 'Receipt % has nothing counted — count at least one line before confirming, or delete the receipt — nothing was saved', v_r.receipt_number;
  end if;
  -- ②⭐⭐ 빈 없는 줄 — 라인·수량을 문장에 · 빠져나갈 길을 함께
  select count(*), string_agg(format('line %s (%s) %s EA', t.line_no, t.sku, t.qty_ea), ', ' order by t.line_no)
    into v_free_n, v_free_txt
  from (select pl.line_no, pr.sku, w.qty_ea
          from public.po_receipt_work w join public.po_line pl on pl.id = w.po_line_id join public.product pr on pr.id = pl.product_id
         where w.receipt_id = p_receipt_id and w.bin_id is null) t;
  if v_free_n > 0 then
    raise exception 'Receipt % cannot be confirmed — % row(s) still have no bin: %. Put them away first, or lower the count to what you actually placed — the rest stays on the order — nothing was saved',
      v_r.receipt_number, v_free_n, v_free_txt;
  end if;
  -- ⑤ 더 막는 것 — 빈이 그 사이 다른 창고 것·비활성으로 바뀌었나(배정 때 봤지만 확정은 장부에 닿는다 · 한 번 더)
  select count(*) into v_n
  from public.po_receipt_work w join public.ref_bin b on b.id = w.bin_id
  where w.receipt_id = p_receipt_id and (b.warehouse_id <> v_r.warehouse_id or not b.is_active);
  if v_n > 0 then
    raise exception 'Receipt % has % row(s) in a bin that is inactive or not in this receipt''s warehouse — move them to another bin first — nothing was saved', v_r.receipt_number, v_n;
  end if;
  if v_r.received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  -- ⑥ ⭐⭐ 환율 — 기준통화가 아닌 발주인데 환율이 없거나 0 이면 **확정 자체를 거부**한다(Caleb 2026-09-19 · 원가가 조용히 틀리는 것보다 낫다 · 정본 「0 금지」).
  --   기준통화는 inv_config.base_currency(박지 않는다) · 발주 통화는 po.currency_id → ref_currency.code.
  --   ⚠️ po.exchange_rate 는 **CAD per USD** 다(Cin7 「CAD units per USD」 · 화면 칸 「CAD per USD」) — unit_price × exchange_rate = CAD. 곱한다 · 나누지 않는다.
  --   문장이 어디서 고치는지 말한다 — 발주 머리의 「Exchange rate (CAD per USD)」 칸 · 확정 뒤에도 열려 있다(po.html HEAD_ALWAYS).
  select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
  select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
  if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which orders need an exchange rate — nothing was saved'; end if;
  if v_cur is distinct from v_base_cur and (v_po.exchange_rate is null or v_po.exchange_rate <= 0) then
    raise exception 'PO % is in % but has no % per % exchange rate — stock cost cannot be worked out without it. Enter the rate in the order header ("Exchange rate" · it stays open after confirming) and confirm again — nothing was saved',
      v_po.po_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
  end if;

  -- ═══ ⓐ 작업 줄 → 입고 줄 (1:1 · received_on 은 묶음의 것 · received_by 는 놓은 사람 → 센 사람 → 확정한 사람 · 초과분도 그대로) ═══
  insert into public.po_receipt_line (po_line_id, received_on, received_by, bin_id, qty_ea, note, receipt_id)
  select w.po_line_id, v_r.received_on, coalesce(w.putaway_by, w.counted_by, v_staff), w.bin_id, w.qty_ea, w.note, v_r.id
  from public.po_receipt_work w
  where w.receipt_id = p_receipt_id
  order by w.po_line_id, w.created_at;
  get diagnostics v_lines_n = row_count;
  if v_lines_n <> v_work_n then
    raise exception 'Receipt %: % work row(s) but % receipt line(s) were written — nothing was saved', v_r.receipt_number, v_work_n, v_lines_n;
  end if;

  -- ═══ ⓑ 차이 (분할 전 수량이 기준) — over · short · 안 센 라인은 short(received 0) ═══
  for x in
    select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pl.qty_ea as ordered,
           pl.qty_ea - coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as expected,
           coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id), 0) as counted
    from public.po_line pl join public.product pr on pr.id = pl.product_id
    where pl.po_id = v_po.id
    order by pl.line_no
  loop
    if x.counted <> x.expected then
      insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty)
      values (v_r.id, v_po.id, x.po_line_id, x.product_id, case when x.counted > x.expected then 'over' else 'short' end, greatest(x.expected, 0), x.counted);
      if x.counted > x.expected then v_over := v_over + 1; else v_short := v_short + 1; end if;
      v_rows := v_rows || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', case when x.counted > x.expected then 'over' else 'short' end,
                                             'expected_qty', greatest(x.expected, 0), 'received_qty', x.counted);
    end if;
    if x.expected - x.counted > 0 then v_rem_total := v_rem_total + (x.expected - x.counted); end if;
  end loop;

  -- ═══ ⓒ 분할 또는 닫기 ═══
  if v_rem_total > 0 then
    -- ⬜4 번호 — 같은 base 의 접미사 최댓값 다음 두 글자(없으면 a·b)
    select max(substring(p.po_number from length(v_base) + 1)) into v_max
    from public.po p where p.po_number ~ ('^' || v_base || '[a-z]+$');
    if v_max is null then
      v_a_num := v_base || 'a'; v_b_num := v_base || 'b';
    else
      if length(v_max) <> 1 or v_max >= 'y' then
        raise exception 'PO % has been split too many times (last suffix %) — split it by hand — nothing was saved', v_po.po_number, v_max;
      end if;
      v_a_num := v_base || chr(ascii(v_max) + 1); v_b_num := v_base || chr(ascii(v_max) + 2);
    end if;

    -- b 문서 — 머리를 통째로 복사(칸이 늘어도 따라온다) · 번호 b · split_from_id = a · 상태 confirmed(같은 확정의 나머지 · confirmed_at/by 도 물려받는다) · 닫힘·취소 흔적 없음
    v_b_id := gen_random_uuid();
    insert into public.po
    select * from jsonb_populate_record(null::public.po,
      to_jsonb(v_po) || jsonb_build_object('id', v_b_id, 'po_number', v_b_num, 'status', 'confirmed', 'split_from_id', v_po.id,
                                           'closed_at', null, 'cancelled_at', null, 'cancelled_by', null,
                                           'created_at', v_now, 'updated_at', v_now, 'updated_by', v_staff));
    -- 할인 줄 복사(PO-02001b 선례 · Caleb 손 작업과 같다)
    insert into public.po_discount (po_id, seq, name, percent, supplier_discount_id, note)
    select v_b_id, d.seq, d.name, d.percent, d.supplier_discount_id, d.note from public.po_discount d where d.po_id = v_po.id;

    -- 라인 — 일부 받은 라인은 a 줄이고 b 신설 · 하나도 안 온 라인은 행을 b 로 옮긴다(인보이스 줄이 가리켜도 FK 가 따라간다)
    for x in
      select pl.*, 
             pl.qty_ea - coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0)
               - coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id), 0) as remaining
      from public.po_line pl where pl.po_id = v_po.id order by pl.line_no
    loop
      if x.remaining <= 0 then continue; end if;                                     -- 다 받았거나 초과 — a 에 그대로
      if x.qty_ea - x.remaining > 0 then
        -- 일부 받았다 — a 는 받은 만큼으로(입력 단위 셋은 비운다 · 이견 5)
        update public.po_line set qty_ea = x.qty_ea - x.remaining, entered_unit_product_id = null, entered_qty = null, entered_pack_factor = null
         where id = x.id and qty_ea = x.qty_ea;
        get diagnostics v_n = row_count;
        if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
        insert into public.po_line
        select * from jsonb_populate_record(null::public.po_line,
          to_jsonb(x) - 'remaining' || jsonb_build_object('id', gen_random_uuid(), 'po_id', v_b_id, 'qty_ea', x.remaining,
                                                          'entered_unit_product_id', null, 'entered_qty', null, 'entered_pack_factor', null,
                                                          'created_at', v_now, 'updated_at', v_now, 'updated_by', v_staff));
        v_reduced := v_reduced + 1;
        if x.entered_unit_product_id is not null then v_cleared := array_append(v_cleared, x.line_no::text); end if;
      else
        -- 하나도 안 왔다 — 행을 통째로 b 로
        update public.po_line set po_id = v_b_id where id = x.id and po_id = v_po.id;
        get diagnostics v_n = row_count;
        if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
        v_moved := v_moved + 1;
      end if;
    end loop;

    -- a — 번호에 접미사 · 닫힘(입고 종료 · §11-b)
    update public.po set po_number = v_a_num, status = 'closed', closed_at = v_now where id = v_po.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
    if cardinality(v_cleared) > 0 then v_warn := array_append(v_warn, 'entered_units_cleared'); end if;
    v_warn := array_append(v_warn, 'po_split');
  else
    -- 다 받았다(또는 초과만) — 갈라지지 않고 닫힌다
    v_a_num := v_po.po_number;
    update public.po set status = 'closed', closed_at = v_now where id = v_po.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
    v_warn := array_append(v_warn, 'po_closed');
  end if;
  if v_over > 0 then v_warn := array_append(v_warn, 'over_receipt'); end if;
  if v_short > 0 then v_warn := array_append(v_warn, 'short_receipt'); end if;

  -- ═══ ⓓ 묶음 confirmed (맨 뒤 — 어디서 터져도 아무것도 안 남는다) ═══
  update public.po_receipt set status = 'confirmed', confirmed_at = v_now, confirmed_by = v_staff
   where id = p_receipt_id and status = 'draft' and confirmed_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Receipt % was not saved — it may have been changed by someone else just now — nothing was saved', v_r.receipt_number; end if;

  -- ═══ ⓔ 원장 — 창구를 부른다 (원장 이식 2차 · 2026-09-19 · ⬜1) ═══
  -- ⭐ 같은 트랜잭션 — 원장이 실패하면 확정도 실패한다(재고에 안 잡힐 거면 확정도 하면 안 된다). inv_ledger 에 직접 쓰지 않는다(원칙 2 · §11-j).
  -- ⭐ 자리가 ⓓ 뒤인 이유 셋: ① 창구는 「확정된 입고」만 받는다(status=confirmed 를 스스로 확인 — 직접 호출로 초안이 장부에 닿는 길을 막는다)
  --   ② raw 의 po_number 는 갈라진 뒤의 번호여야 한다(§11-j) — ⓒ 가 끝나야 안다 ③ 기준은 po_line.qty_ea 가 아니라 ⓑ 가 얼려 둔 po_receipt_diff.expected_qty 에서
  --   읽으므로(§2 의 함정 — ⓒ 가 qty_ea 를 줄인다) ⓒ 뒤라도 어긋나지 않는다. 기준을 「미리 잡아 두는」 그릇이 그 표다.
  v_ledger := public.inv_post_receipt(p_receipt_id);
  if coalesce((v_ledger->>'qty_excess')::numeric, 0) > 0 then v_warn := array_append(v_warn, 'ledger_trimmed_to_basis'); end if;
  if (v_ledger->'warnings') ? 'received_on_before_baseline' then v_warn := array_append(v_warn, 'received_on_before_baseline'); end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', 'confirmed', 'confirmed_at', v_now, 'confirmed_by', v_staff,
    'receipt_lines_created', v_lines_n,
    'po', jsonb_build_object('id', v_po.id, 'number_before', v_po.po_number, 'number_after', v_a_num, 'status', 'closed', 'closed_at', v_now),
    'split', case when v_rem_total > 0 then jsonb_build_object('remainder_po_id', v_b_id, 'remainder_number', v_b_num, 'lines_reduced', v_reduced, 'lines_moved', v_moved, 'remainder_qty', v_rem_total) else null end,
    'diffs', jsonb_build_object('over', v_over, 'short', v_short, 'rows', v_rows),
    'entered_units_cleared_lines', to_jsonb(v_cleared),
    'ledger', v_ledger,                                          -- ⭐ 원장 결과(rows_posted · qty_posted · qty_excess · lines[]) — 화면이 「재고에 들어갔다」를 말할 수 있게
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ po_invoice_create — 원본 20260918003000_ims_rpc_honest_refusal_invoice.sql:27 · current_date 2곳 ═══
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
      v_num := public.po_credit_next_number(v_credit_po_id, extract(year from coalesce(p_invoice_date, public.ims_today()))::int);
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
    values (v_supplier_id, p_doc_kind, v_num, coalesce(p_invoice_date, public.ims_today()), p_due_date, v_pt_id, v_pt_name,
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

-- ═══ po_charge_create — 원본 20260918013000_ims_rpc_honest_refusal_charge_payment.sql:25 · current_date 2곳 ═══
create or replace function public.po_charge_create(
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
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

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
    values (p_supplier_id, v_num, coalesce(p_charge_date, public.ims_today()), p_due_date, p_kind, p_description, v_cur, p_total_amount, 'draft', v_staff, p_note)
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
    'committed', p_commit, 'charge_id', v_chg_id, 'charge_number', v_num, 'charge_date', coalesce(p_charge_date, public.ims_today()), 'kind', p_kind,
    'supplier_id', p_supplier_id, 'supplier_name', v_sup.name, 'currency_id', v_cur, 'currency_code', v_cur_code,
    'total_amount', p_total_amount, 'alloc_sum', v_sum, 'unallocated', p_total_amount - v_sum,
    'allocs', v_allocs, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Charge % already exists for % — nothing was saved', v_num, coalesce(v_sup.name, 'this supplier');
end;
$$;

-- ═══ po_payment_create — 원본 20260918013000_ims_rpc_honest_refusal_charge_payment.sql:331 · current_date 2곳 ═══
create or replace function public.po_payment_create(
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
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

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
    values (coalesce(p_paid_on, public.ims_today()), p_amount, p_currency_id, p_account_id, p_reference, v_disc, v_staff, p_note)
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
    'committed', p_commit, 'payment_id', v_pay_id, 'paid_on', coalesce(p_paid_on, public.ims_today()),
    'amount', p_amount, 'discount_taken', v_disc, 'currency_id', p_currency_id, 'currency_code', v_cur_code,
    'supplier_id', v_sup_id, 'supplier_name', v_sup_name,
    'account_code', v_acc_code, 'account_name', v_acc_name,
    'alloc_sum', v_sum, 'gap', v_gap, 'allocs', v_allocs, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ inv_post_receipt — 원본 20260919192236_cost_graft_1.sql:154 · current_date 1곳 ═══
create or replace function public.inv_post_receipt(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security invoker                                              -- 이견 3 — definer 가 필요한 표가 없다
set search_path = public, pg_temp
as $$
declare
  c_version   constant text := 'inv_post_receipt@2026-09-19.1';   -- raw.poster 에 박는다 — 배분 규칙이 바뀌면 올릴 것
  v_r         public.po_receipt%rowtype;
  v_po        public.po%rowtype;
  v_wh        text;
  v_existing  int;
  v_baseline  date;
  v_alloc     jsonb;
  v_lines     jsonb;
  v_rows      int := 0;
  v_counted   numeric := 0;
  v_posted    numeric := 0;
  v_excess    numeric := 0;
  v_warn      text[] := '{}';
  v_layers    jsonb;                                              -- 원가 레이어 결과(원가 이식 1차 · 2026-09-19)
  b           record;
begin
  perform public.ims_require_write('receiving', 'posted');

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was posted to the ledger', p_receipt_id; end if;
  if v_r.status <> 'confirmed' or v_r.confirmed_at is null then
    raise exception 'Receipt % is % — the ledger takes confirmed receipts only — nothing was posted to the ledger', v_r.receipt_number, v_r.status;
  end if;
  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  if v_wh is null then raise exception 'Warehouse of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;

  -- 2. 멱등 — 이미 기표된 입고는 다시 쓰지 않는다(터지지 않고 말한다 · ⬜5)
  select count(*) into v_existing
  from public.inv_ledger l
  where l.doc_type = 'purchase' and l.doc_number = v_r.receipt_number and l.source = 'ims';
  if v_existing > 0 then
    -- ⭐ 원가 이식 1차(2026-09-19) — 원장은 이미 있어도 레이어는 없을 수 있다(이식 전에 확정된 RCV-00005·00006 · 백필 ⬜7).
    --   레이어 쪽도 같은 멱등 규칙(4키가 있으면 안 만든다)이라, 다시 부르면 빠진 레이어만 선다. 원장은 한 행도 다시 쓰지 않는다.
    v_layers := public.inv_layer_post_receipt(p_receipt_id);
    return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
                              'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0,
                              'qty_counted', null, 'qty_posted', null, 'qty_excess', null, 'lines', '[]'::jsonb,
                              'layers', v_layers, 'warnings', '["already_posted"]'::jsonb);
  end if;

  -- 6. 날짜 경고 — 기초선보다 이르면 · 미래면 (막지 않는다 · ⬜7)
  select (max(s.taken_at) at time zone 'America/Toronto')::date into v_baseline
  from public.inv_snapshot s
  where s.snapshot_key = (select c.value from public.inv_config c where c.key = 'baseline_snapshot_key');
  if v_baseline is not null and v_r.received_on < v_baseline then v_warn := array_append(v_warn, 'received_on_before_baseline'); end if;
  if v_r.received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  -- 3·4. 기준과 배분 — 한 번의 SQL 로 계산해 jsonb 배열에 담는다(그 뒤 루프는 넣고 더하기만 한다)
  with ln as (
    select l.po_line_id, sum(l.qty_ea) as counted, d.kind as diff_kind,
           case when d.kind is not null then d.expected_qty else sum(l.qty_ea) end as basis,     -- ⭐ 이견 1 — 기록용 기준: 차이 행(over·short)이 있으면 ⓑ 가 얼린 값 · 없으면 센 것
           case when d.kind = 'over'    then d.expected_qty else sum(l.qty_ea) end as cap        -- 깎기 상한: over 만 자른다 · posted 는 이것만 본다(검증 ⑤ 정정 — basis 와 갈랐다)
    from public.po_receipt_line l
    left join public.po_receipt_diff d on d.receipt_id = l.receipt_id and d.po_line_id = l.po_line_id
    where l.receipt_id = p_receipt_id
    group by l.po_line_id, d.kind, d.expected_qty
  ),
  alloc as (
    select l.id as receipt_line_id, l.po_line_id, l.bin_id, rb.name as bin, l.qty_ea, l.received_by, l.note,
           pl.line_no, pl.product_id, pl.unit_price, pr.sku,
           ln.counted, ln.basis, ln.cap, ln.diff_kind,
           least(l.qty_ea, greatest(ln.cap - coalesce(sum(l.qty_ea) over (partition by l.po_line_id order by l.qty_ea desc, rb.name, l.id
                                                                                  rows between unbounded preceding and 1 preceding), 0), 0)) as posted   -- ⭐ ⬜2 — 큰 빈부터 채우고 바닥나는 줄에서 자른다
    from public.po_receipt_line l
    join public.ref_bin  rb on rb.id = l.bin_id
    join public.po_line  pl on pl.id = l.po_line_id
    join public.product  pr on pr.id = pl.product_id
    join ln on ln.po_line_id = l.po_line_id
    where l.receipt_id = p_receipt_id
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no, a.qty_ea desc, a.bin, a.receipt_line_id), '[]'::jsonb) into v_alloc from alloc a;

  -- 5. 기표 — posted > 0 인 줄만 행이 된다
  for b in
    select * from jsonb_to_recordset(v_alloc) as t(
      receipt_line_id uuid, po_line_id uuid, bin_id uuid, bin text, qty_ea numeric, received_by uuid, note text,
      line_no int, product_id uuid, unit_price numeric, sku text, counted numeric, basis numeric, diff_kind text, posted numeric)
    order by line_no, qty_ea desc, bin
  loop
    if b.posted <= 0 then continue; end if;
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (
      v_r.received_on, 1, b.sku, v_wh, b.bin, b.posted, 'po_in', 'purchase', v_r.receipt_number, v_r.id::text, b.po_line_id::text, null, 'ims',          -- line_ref = po_line_id(라인 id · Caleb 실측 확정)
      jsonb_build_object(
        'kind', 'po_in', 'poster', c_version,
        'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'receipt_line_id', b.receipt_line_id,
        'po_id', v_po.id, 'po_number', v_po.po_number,                                   -- 갈라진 뒤의 번호(ⓓ 뒤에 불린다 · §11-j)
        'po_line_id', b.po_line_id, 'line_no', b.line_no, 'product_id', b.product_id, 'sku', b.sku,
        'warehouse_id', v_r.warehouse_id, 'warehouse', v_wh, 'bin_id', b.bin_id, 'bin', b.bin,
        'received_on', v_r.received_on, 'received_by', b.received_by, 'confirmed_by', v_r.confirmed_by, 'confirmed_at', v_r.confirmed_at,
        'line', jsonb_build_object('counted', b.counted, 'basis', b.basis, 'posted', least(b.counted, b.basis), 'excess', greatest(b.counted - b.basis, 0), 'diff_kind', b.diff_kind),
        'this_bin', jsonb_build_object('counted', b.qty_ea, 'posted', b.posted, 'trimmed', b.qty_ea - b.posted),
        'bins', (select jsonb_agg(jsonb_build_object('bin', t2.bin, 'counted', t2.qty_ea, 'posted', t2.posted, 'trimmed', t2.qty_ea - t2.posted) order by t2.qty_ea desc, t2.bin)
                 from jsonb_to_recordset(v_alloc) as t2(po_line_id uuid, bin text, qty_ea numeric, posted numeric) where t2.po_line_id = b.po_line_id),
        'trim_rule', 'fill bins by qty desc, then bin name; cut where the cap runs out; cap = po_receipt_diff.expected_qty when over, else counted (nothing to cut); basis (recorded) = expected_qty whenever a diff row exists, else counted',
        'unit_price', b.unit_price, 'currency_id', v_po.currency_id, 'exchange_rate', v_po.exchange_rate,
        'note', b.note));
    v_rows := v_rows + 1;
    v_posted := v_posted + b.posted;
  end loop;

  -- 라인 요약(0 으로 깎인 줄도 bins[] 에 남는다)
  select coalesce(jsonb_agg(jsonb_build_object(
           'po_line_id', t.po_line_id, 'line_no', t.line_no, 'sku', t.sku, 'counted', t.counted, 'basis', t.basis,
           'posted', t.posted, 'excess', greatest(t.counted - t.basis, 0), 'diff_kind', t.diff_kind, 'bins', t.bins) order by t.line_no), '[]'::jsonb),
         coalesce(sum(t.counted), 0), coalesce(sum(greatest(t.counted - t.basis, 0)), 0)
    into v_lines, v_counted, v_excess
  from (
    select a.po_line_id, min(a.line_no) as line_no, min(a.sku) as sku, min(a.counted) as counted, min(a.basis) as basis, min(a.diff_kind) as diff_kind,
           sum(a.posted) as posted,
           jsonb_agg(jsonb_build_object('bin', a.bin, 'counted', a.qty_ea, 'posted', a.posted, 'trimmed', a.qty_ea - a.posted) order by a.qty_ea desc, a.bin) as bins
    from jsonb_to_recordset(v_alloc) as a(po_line_id uuid, line_no int, sku text, bin text, qty_ea numeric, counted numeric, basis numeric, diff_kind text, posted numeric)
    group by a.po_line_id
  ) t;

  -- ⭐ 원가 레이어 — 원장 행을 만든 바로 그 수량으로(같은 트랜잭션 · 원장 사건과 함께 서거나 함께 죽는다 · 원가 이식 1차 2026-09-19).
  --   두 번 계산하지 않는다 — inv_layer_post_receipt 가 방금 넣은 inv_ledger 행(source='ims' · 이 RCV)을 읽어 라인 단위로 접는다.
  v_layers := public.inv_layer_post_receipt(p_receipt_id);

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
    'already_posted', false, 'existing_rows', 0,
    'rows_posted', v_rows, 'qty_counted', v_counted, 'qty_posted', v_posted, 'qty_excess', v_excess,
    'lines', v_lines, 'layers', v_layers, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Receipt % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_r.receipt_number, sqlerrm;
end;
$$;
