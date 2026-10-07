do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;
-- 20261007173939_fr_2_freight_discount_invoice.sql — fr-2 (2026-10-07 · 회사 PC)
--   판정 352 운임 줄과 할인 줄을 따로(인보이스 Freight 100.00 / Freight discount −50.00 · 회계상 운임 매출 · 운임 할인 따로) · 353 so_charge 할인 칸을 발행 때 두 줄로 펼친다 · 354 세금은 줄마다(fr-1 so_tax_preview 의 charges[].discount · discount_tax) · 358 할인 줄 계정 = inv_config so_freight_discount_account_code(기본 _6_ Sales Discounts · surcharge 키와 같은 모양 · 비었거나 · 없거나 · 꺼졌으면 할인 운임이 있는 발행만 막는다)
--   ⭐ 첫 일: fr-1(20261007171939)의 임시 가드 so_invoice_order_freight_discount_guard(트리거 + 함수)를 지운다 — 이제 발행이 할인 줄을 펼친다
--   표: so_invoice · so_invoice_order 에 charges_discount_amount(머리에서도 운임 매출과 할인이 따로 보인다 · charges_amount 는 정가 그대로) · taxable CHECK 둘 = lines + order_discount + charges − charges_discount + surcharge · so_invoice_line kind CHECK + charge_discount · 부호(≤ 0) · 짝(so_charge_id = 그 운임 줄)
--   재발행: so_invoice_issue(20261006000805:966~1223 바이트 복사 + 더한 줄 · 바꾼 줄 · 줄 끝 -- fr-2) · 뷰 so_invoice_list(20261002144956:665~712 + 열 하나 끝에) · so_invoice_reissue(issue 를 부를 뿐) · so_invoice_cancel(머리 · 오더 상태만 — 줄은 취소된 인보이스에 남는다) · so_invoice_detail(to_jsonb(l) · 뷰 행)은 본문 그대로 — 검증이 셋을 돌려 확인
--   크레딧 틈(fr-3 전까지): so_credit_line BEFORE INSERT 가드 — 할인 줄이 있는 운임 줄을 kind freight 로 돌려주면 거부(한도가 정가라 더 돌려줄 수 있다 · 판정 355 가 닫는다) · fr-3 가 지운다
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록이 실물을 세어 어긋나면 전부 되돌린다 · 검증 supabase/tests/fr-2-verify.sql

-- ═══ 1) fr-1 임시 가드 지우기 ═══
drop trigger if exists so_invoice_order_freight_discount_guard on public.so_invoice_order;
drop function if exists public.so_invoice_order_freight_discount_guard();

-- ═══ 2) 계정 키(판정 358) — surcharge 키와 같은 모양(잠금 밖 문자열 · inv_config_guard 는 지나간다 · 규칙 · 막기는 발행 창구가 든다) ═══
insert into public.inv_config (key, value, note) values
  ('so_freight_discount_account_code', '_6_', 'SO 인보이스 · 운임 할인 줄(kind charge_discount)의 계정 code(ref_account) · 발행 때 읽어 줄에 얼린다 · 비었거나 계정이 없거나 꺼졌으면 할인 운임이 있는 발행만 막는다(fr-2 판정 358 · 기본 _6_ Sales Discounts) · 잠금 밖(ims_config_locked_keys 아님) · surcharge 키 so_surcharge_account_code 와 같은 모양')
on conflict (key) do nothing;

-- ═══ 3) 표 — 머리 · 오더 칸 charges_discount_amount · taxable CHECK 둘 · 줄 CHECK 셋 ═══
alter table public.so_invoice       add column if not exists charges_discount_amount numeric not null default 0;
alter table public.so_invoice_order add column if not exists charges_discount_amount numeric not null default 0;
comment on column public.so_invoice.charges_discount_amount       is 'fr-2 판정 352 — 운임 할인 줄(kind charge_discount) 금액 합의 절댓값(≥ 0) · charges_amount(운임 정가 합)와 따로 · taxable_amount = lines + order_discount + charges − charges_discount + surcharge(so_invoice_taxable_ck)';
comment on column public.so_invoice_order.charges_discount_amount is 'fr-2 판정 352 — 이 오더 몫의 운임 할인 합(so_tax_preview totals.charges_discount_amount) · taxable = lines + order_discount + charges − charges_discount + surcharge(so_invoice_order_taxable_ck)';
alter table public.so_invoice       drop constraint so_invoice_taxable_ck;
alter table public.so_invoice       add constraint so_invoice_taxable_ck check (taxable_amount = lines_amount + order_discount_amount + charges_amount - charges_discount_amount + surcharge_amount);
alter table public.so_invoice_order drop constraint so_invoice_order_taxable_ck;
alter table public.so_invoice_order add constraint so_invoice_order_taxable_ck check (taxable_amount = lines_amount + order_discount_amount + charges_amount - charges_discount_amount + surcharge_amount);
alter table public.so_invoice_line  drop constraint so_invoice_line_kind_ck, drop constraint so_invoice_line_amount_ck, drop constraint so_invoice_line_charge_ck;
alter table public.so_invoice_line
  add constraint so_invoice_line_kind_ck   check (kind in ('product', 'charge', 'order_discount', 'surcharge', 'charge_discount')),
  add constraint so_invoice_line_amount_ck check (case when kind in ('order_discount', 'charge_discount') then amount <= 0 else amount >= 0 end),
  add constraint so_invoice_line_charge_ck check ((kind in ('charge', 'charge_discount')) = (so_charge_id is not null));
comment on constraint so_invoice_line_kind_ck   on public.so_invoice_line is 'product · charge · order_discount · surcharge(surcharge-2b) · charge_discount(fr-2 판정 352 · 그 운임 줄 바로 뒤 · so_charge_id = 그 운임 줄의 so_charge · description = <운임 이름> discount [N%] · amount ≤ 0 · tax_amount ≤ 0 · 계정 inv_config so_freight_discount_account_code)';
comment on constraint so_invoice_line_amount_ck on public.so_invoice_line is 'order_discount · charge_discount(fr-2)는 ≤ 0 · 나머지는 ≥ 0';
comment on constraint so_invoice_line_charge_ck on public.so_invoice_line is 'charge · charge_discount(fr-2)만 so_charge_id 를 가진다 — 할인 줄은 자기 운임 줄을 가리킨다';

-- ═══ 4) so_invoice_issue 재발행 — 마지막 정의 20261006000805:966~1223(DB md5 a898a99f · 검증 G0) · 할인 줄 펼치기 · 계정 키 · 머리 · 오더 합계 ═══
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
  v_sc_amt   numeric := 0;  v_o_sc numeric;  v_has_sc boolean;  v_sc_code text;  v_sc_acct public.ref_account%rowtype;   -- surcharge-2b(묶음 5 · 6)
  v_chd_amt  numeric := 0;  v_o_chd numeric;  v_has_fd boolean;  v_fd_code text;  v_fd_acct public.ref_account%rowtype;   -- fr-2 판정 352 · 358: 운임 할인 합 · 할인 줄 계정(inv_config so_freight_discount_account_code · 기본 _6_)
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

  -- surcharge 계정(surcharge-2b · 묶음 6) — 담긴 오더에 보낸 surcharge 줄이 있으면 ⭐ 머리 insert(번호를 당긴다) 앞에서 계정을 잡는다 · 비었거나 · 없거나 · 꺼졌으면 surcharge 있는 발행만 막는다 · 없는 발행은 지금처럼
  select exists (select 1 from public.so_line l where l.so_id = any(p_so_ids) and l.surcharge_label is not null and l.qty_shipped > 0) into v_has_sc;
  if v_has_sc then
    select nullif(k.value, '') into v_sc_code from public.inv_config k where k.key = 'so_surcharge_account_code';
    if v_sc_code is null then raise exception 'Surcharge account is not set — set inv_config so_surcharge_account_code (e.g. _94_) before invoicing an order with a surcharge — nothing was saved'; end if;
    select * into v_sc_acct from public.ref_account a where a.code = v_sc_code;
    if v_sc_acct.id is null then raise exception 'Surcharge account % (inv_config so_surcharge_account_code) is not in the chart of accounts — nothing was saved', v_sc_code; end if;
    if not v_sc_acct.is_active then raise exception 'Surcharge account % (%) is inactive — pick an active account in inv_config so_surcharge_account_code — nothing was saved', v_sc_acct.code, v_sc_acct.name; end if;
  end if;
  -- 운임 할인 계정(fr-2 판정 358 · surcharge 와 같은 모양) — 담긴 오더에 할인이 걸린 운임 줄이 있으면 머리 insert 앞에서 계정을 잡는다 · 비었거나 · 없거나 · 꺼졌으면 할인 운임이 있는 발행만 막는다
  select exists (select 1 from public.so_charge c where c.so_id = any(p_so_ids) and (c.discount_pct is not null or c.discount_amount is not null)) into v_has_fd;
  if v_has_fd then
    select nullif(k.value, '') into v_fd_code from public.inv_config k where k.key = 'so_freight_discount_account_code';
    if v_fd_code is null then raise exception 'Freight discount account is not set — set inv_config so_freight_discount_account_code (e.g. _6_ Sales Discounts) before invoicing an order with a freight discount — nothing was saved'; end if;
    select * into v_fd_acct from public.ref_account a where a.code = v_fd_code;
    if v_fd_acct.id is null then raise exception 'Freight discount account % (inv_config so_freight_discount_account_code) is not in the chart of accounts — nothing was saved', v_fd_code; end if;
    if not v_fd_acct.is_active then raise exception 'Freight discount account % (%) is inactive — pick an active account in inv_config so_freight_discount_account_code — nothing was saved', v_fd_acct.code, v_fd_acct.name; end if;
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
    v_o_sc    := coalesce((v_prev->'totals'->>'surcharge_amount')::numeric, 0);                                             -- surcharge-2b: 이 오더 몫 · tax 는 2a 부터 surcharge 세금을 이미 품는다
    v_o_chd   := coalesce((v_prev->'totals'->>'charges_discount_amount')::numeric, 0);                                      -- fr-2 판정 352: 이 오더의 운임 할인 합(fr-1 so_tax_preview · tax 는 할인 세금을 이미 뺐다 · 354)
    if v_o_lines + v_o_od + v_o_chg = 0 and not exists (select 1 from public.so_line l where l.so_id = v_so.id and l.qty_shipped > 0) then
      raise exception 'Order % shipped nothing — there is nothing to invoice — nothing was saved', v_so.so_number;
    end if;

    insert into public.so_invoice_order (invoice_id, so_id, so_number, customer_id,
                                         ship_to_company, ship_to_contact, ship_to_phone, ship_to_line1, ship_to_line2, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country,
                                         tax_rule_id, tax_rule, rate_pct, tax_source, draft_rule_changed,
                                         lines_amount, order_discount_pct, order_discount_amount, charges_amount, charges_discount_amount, surcharge_amount, taxable_amount, tax_amount, total, updated_by)   -- fr-2
    values (v_inv.id, v_so.id, v_so.so_number, v_so.customer_id,
            v_so.ship_to_company, v_so.ship_to_contact, v_so.ship_to_phone, v_so.ship_to_line1, v_so.ship_to_line2, v_so.ship_to_city, v_so.ship_to_state_province, v_so.ship_to_postal_code, v_so.ship_to_country,
            v_rule_id, v_rule, v_rate, case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, v_changed,
            v_o_lines, v_so.order_discount_pct, v_o_od, v_o_chg, v_o_chd, v_o_sc, v_o_lines + v_o_od + v_o_chg - v_o_chd + v_o_sc, v_o_tax, v_o_lines + v_o_od + v_o_chg - v_o_chd + v_o_sc + v_o_tax, p_staff)   -- fr-2: 운임 할인을 뺀다
    returning * into v_io;

    for e in select x from jsonb_array_elements(v_prev->'lines') x loop                     -- 제품 줄(보낸 수량 > 0 만 · 안 나간 줄은 종이에 없다)
      if (e->>'qty')::numeric > 0 and nullif(e->>'combo_line_id', '') is null then                  -- asm-2b2(묶음 5): 구성품 줄은 종이에 없다 · 콤보 줄은 product 줄(qty = 나간 콤보 수) + 「includes …」 를 combo_components 에 굳힌다(so_line 이 뒤에 바뀌어도 그대로)
        v_ln := v_ln + 1;
        insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, unit, pack_factor, qty, list_price, discount_pct, discount_source, unit_price, amount, tax_amount, account_id, account_code, updated_by, combo_components)
        values (v_inv.id, v_io.id, v_ln, 'product', (e->>'line_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
                (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, e->>'discount_source', (e->>'unit_price')::numeric, (e->>'amount')::numeric, (e->>'tax')::numeric,
                v_so.sale_account_id, v_so.sale_account_code, p_staff, nullif(e->'combo_components', 'null'::jsonb));
        if coalesce((e->>'surcharge_total')::numeric, 0) > 0 then                        -- surcharge-2b(묶음 5): 그 상품 줄 바로 뒤 · 값은 so_tax_preview 줄 객체에서(2a 계산 한 곳 · 다시 세지 않는다) · 계정 = inv_config so_surcharge_account_code
          v_ln := v_ln + 1;
          insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, qty, unit_price, amount, tax_amount, account_id, account_code, updated_by)
          values (v_inv.id, v_io.id, v_ln, 'surcharge', (e->>'line_id')::uuid, e->>'sku', e->>'surcharge_label', (e->>'qty')::numeric, (e->>'surcharge_unit')::numeric, (e->>'surcharge_total')::numeric, (e->>'surcharge_tax')::numeric,
                  v_sc_acct.id, v_sc_acct.code, p_staff);
        end if;
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
      if coalesce((e->>'discount')::numeric, 0) > 0 then                                   -- fr-2 판정 352 · 354: 할인 줄은 그 운임 줄 바로 뒤 · 음수 · 세금은 할인 줄 몫(so_tax_preview 가 따로 반올림) · 계정 = inv_config so_freight_discount_account_code
        v_ln := v_ln + 1;
        insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_charge_id, description, discount_pct, amount, tax_amount, account_id, account_code, updated_by)
        values (v_inv.id, v_io.id, v_ln, 'charge_discount', (e->>'charge_id')::uuid,
                (e->>'name') || ' discount' || case when nullif(e->>'discount_pct', '') is not null then format(' %s%%', trim_scale((e->>'discount_pct')::numeric)) else '' end,
                nullif(e->>'discount_pct', '')::numeric, -(e->>'discount')::numeric, -coalesce((e->>'discount_tax')::numeric, 0), v_fd_acct.id, v_fd_acct.code, p_staff);
      end if;
    end loop;

    v_lines_amt := v_lines_amt + v_o_lines;  v_od_amt := v_od_amt + v_o_od;  v_chg_amt := v_chg_amt + v_o_chg;  v_tax := v_tax + v_o_tax;  v_sc_amt := v_sc_amt + v_o_sc;   -- surcharge-2b
    v_chd_amt := v_chd_amt + v_o_chd;                                                                                                                              -- fr-2
    if v_changed then v_warn := array_append(v_warn, 'draft_rule_changed:' || v_so.so_number); end if;
    if coalesce(v_prev->'warnings', '[]'::jsonb) ? 'tax_rule_inactive' then v_warn := array_append(v_warn, 'tax_rule_inactive:' || v_so.so_number); end if;

    update public.so set status = 'fulfilled', invoiced_at = now(), closed_at = now(), updated_by = p_staff where id = v_so.id and status = 'shipped';   -- ⓑ2 판정 1: 문지기 짝 shipped→fulfilled · 끝 상태 closed_at 짝(so_closed_at_ck)
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Order % was not invoiced — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'tax_rule', v_rule, 'rate_pct', v_rate,
                                               'tax_source', case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, 'draft_rule_changed', v_changed, 'totals', v_prev->'totals');
  end loop;

  -- 합계를 먼저 굳힌다(so_invoice_remaining 이 total 을 본다) · 잔액 항은 아직 0
  v_total := v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt + v_tax;                                                               -- surcharge-2b · fr-2 운임 할인을 뺀다
  update public.so_invoice set lines_amount = v_lines_amt, order_discount_amount = v_od_amt, charges_amount = v_chg_amt, charges_discount_amount = v_chd_amt, surcharge_amount = v_sc_amt,   -- fr-2
                               taxable_amount = v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt, tax_amount = v_tax, total = v_total, amount_due = v_total, updated_by = p_staff
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
                            'totals', jsonb_build_object('lines_amount', v_inv.lines_amount, 'order_discount_amount', v_inv.order_discount_amount, 'charges_amount', v_inv.charges_amount, 'charges_discount_amount', v_inv.charges_discount_amount, 'surcharge_amount', v_inv.surcharge_amount,   -- fr-2
                                                         'taxable_amount', v_inv.taxable_amount, 'tax_amount', v_inv.tax_amount, 'total', v_inv.total,
                                                         'deposit_applied', v_inv.deposit_applied, 'credit_applied', v_inv.credit_applied, 'balance_forward', v_inv.balance_forward, 'amount_due', v_inv.amount_due,
                                                         'remaining', public.so_invoice_remaining(v_inv.id)),
                            'applied', v_applied,
                            'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id),
                            'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 5) 뷰 so_invoice_list 재발행 — 20261002144956:665~712 바이트 그대로 + charges_discount_amount 를 끝에(so_invoice_detail 의 invoice 행이 이 뷰 · 권한 유지) ═══
create or replace view public.so_invoice_list
  with (security_invoker = true) as
with ord as (
  select o.invoice_id,
         string_agg(o.so_number, ', ' order by o.so_number) filter (where o.cancelled_at is null)  as so_numbers,
         array_agg(o.so_id order by o.so_number)             filter (where o.cancelled_at is null)  as so_ids,
         count(*)                                             filter (where o.cancelled_at is null)  as order_count,
         case when count(distinct s.channel) filter (where o.cancelled_at is null) > 1 then 'mixed'
              else min(s.channel) filter (where o.cancelled_at is null) end                          as channel,
         string_agg(o.so_number || coalesce(' ' || s.ref, ''), ' ' order by o.so_number) filter (where o.cancelled_at is null) as order_text
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
       i.charges_discount_amount                                                                                               -- fr-2 판정 352(끝에 — 같은 이유)
from public.so_invoice i
left join public.customer cu on cu.id = i.bill_to_customer_id
left join ord o on o.invoice_id   = i.id
left join pay  on pay.invoice_id  = i.id
left join cred on cred.invoice_id = i.id
cross join lateral (select public.so_invoice_remaining(i.id) as remaining) r;   -- 읽기 함수(stable)를 lateral 에서 한 번만 — 쓰기 창구가 아니다


-- ═══ 6) 크레딧 틈 가드(fr-3 전까지) — so_credit_line BEFORE INSERT · 할인 줄이 있는 운임 줄을 freight 로 돌려주면 거부 · fr-3 가 트리거 · 함수를 지운다 ═══
create function public.so_credit_line_freight_discount_guard() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
begin
  if new.kind = 'freight' and new.so_invoice_line_id is not null
     and exists (select 1 from public.so_invoice_line il join public.so_invoice_line d on d.invoice_id = il.invoice_id and d.kind = 'charge_discount' and d.so_charge_id = il.so_charge_id where il.id = new.so_invoice_line_id) then
    raise exception 'Invoice line % is a freight line that carries a freight discount — crediting discounted freight arrives with fr-3 (the discount must come back in the same proportion) — nothing was saved', new.so_invoice_line_id;
  end if;
  return new;
end;
$$;
revoke all on function public.so_credit_line_freight_discount_guard() from public, anon, authenticated;
comment on function public.so_credit_line_freight_discount_guard() is 'fr-2 임시 가드(2026-10-07) — so_credit_line BEFORE INSERT · kind freight 줄이 가리키는 인보이스 운임 줄에 할인 줄(charge_discount · 같은 so_charge_id)이 있으면 거부(so_credit_issue 의 한도가 운임 정가라 손님이 낸 돈보다 더 돌려줄 수 있는 틈 · 판정 355) · ⚠️ fr-3(크레딧 할인 비례)가 트리거와 함께 지운다 · 할인 없는 운임의 크레딧은 지금처럼';
create trigger so_credit_line_freight_discount_guard before insert on public.so_credit_line for each row execute function public.so_credit_line_freight_discount_guard();

-- ═══ 7) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text;
begin
  if to_regprocedure('public.so_invoice_order_freight_discount_guard()') is not null or exists (select 1 from pg_trigger where tgname = 'so_invoice_order_freight_discount_guard') then v_bad := v_bad || ' fr1_guard_still_there'; end if;
  if (select value from public.inv_config where key = 'so_freight_discount_account_code') is distinct from '_6_' then v_bad := v_bad || ' inv_config'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name in ('so_invoice', 'so_invoice_order') and column_name = 'charges_discount_amount') <> 2 then v_bad := v_bad || ' columns'; end if;
  if (select count(*) from pg_constraint where conname in ('so_invoice_taxable_ck', 'so_invoice_order_taxable_ck') and pg_get_constraintdef(oid) like '%- charges_discount_amount%') <> 2 then v_bad := v_bad || ' taxable_ck'; end if;
  if (select count(*) from pg_constraint where conrelid = 'public.so_invoice_line'::regclass and conname in ('so_invoice_line_kind_ck', 'so_invoice_line_amount_ck', 'so_invoice_line_charge_ck') and pg_get_constraintdef(oid) like '%charge_discount%') <> 3 then v_bad := v_bad || ' line_ck'; end if;
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_invoice_issue';
  if v_src not like '%''charge_discount''%' or v_src not like '%so_freight_discount_account_code%' or v_src not like '%- v_o_chd%' then v_bad := v_bad || ' so_invoice_issue(body)'; end if;
  if has_function_privilege('authenticated', 'public.so_invoice_issue(uuid[], uuid, date)', 'execute') or has_function_privilege('anon', 'public.so_invoice_issue(uuid[], uuid, date)', 'execute') then v_bad := v_bad || ' so_invoice_issue(acl)'; end if;
  if (select count(*) from pg_attribute where attrelid = 'public.so_invoice_list'::regclass and attname = 'charges_discount_amount' and not attisdropped) <> 1 then v_bad := v_bad || ' view'; end if;
  if (select count(*) from pg_class where relname = 'so_invoice_list' and 'security_invoker=true' = any(reloptions)) <> 1 then v_bad := v_bad || ' view(invoker)'; end if;
  if to_regprocedure('public.so_credit_line_freight_discount_guard()') is null or (select count(*) from pg_trigger where tgrelid = 'public.so_credit_line'::regclass and tgname = 'so_credit_line_freight_discount_guard' and tgenabled <> 'D') <> 1 then v_bad := v_bad || ' credit_guard'; end if;
  if has_function_privilege('authenticated', 'public.so_credit_line_freight_discount_guard()', 'execute') or has_function_privilege('anon', 'public.so_credit_line_freight_discount_guard()', 'execute') or has_function_privilege('public', 'public.so_credit_line_freight_discount_guard()', 'execute') then v_bad := v_bad || ' credit_guard(acl)'; end if;
  -- so_tax_preview 는 fr-1 주석이 「fr-2」를 품어 단어 검사에서 뺀다(무변은 검증 G 의 md5 로) · asung-workflow §4 「끝 do 블록의 단어 검사는 내 주석도 센다」
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_invoice_reissue', 'so_invoice_cancel', 'so_invoice_detail', 'so_credit_issue', 'so_credit_prepare', 'inv_config_guard') and p.prosrc like '%fr-2%') <> 0 then v_bad := v_bad || ' untouched(touched)'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM358', message = format('STOP - fr-2 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
