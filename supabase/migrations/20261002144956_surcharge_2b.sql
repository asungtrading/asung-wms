-- surcharge-2b — SO 관세 부가 요금(surcharge): 문서 — 인보이스 · 크레딧 줄(kind surcharge) · 머리 칸 surcharge_amount · 합계 CHECK · 계정 설정 (2026-10-02 UTC · 판정 227 ~ 230 · surcharge 묶음 1 ~ 8 · surcharge-2 묶음 3 ~ 9 · so-module §36 · 앞 차수 2a bd5c71b)
--   묶음 5    인보이스 · 크레딧에는 surcharge 를 별도 줄로 얼려 담는다 — kind surcharge · 그 상품 줄 바로 뒤 · 이름(surcharge_label) · 수량 · 개당 · 금액 · 세금 · 계정 · 머리 표에 surcharge_amount 칸 하나 + 합계 CHECK 셋을 다시 건다
--   묶음 6    계정은 inv_config so_surcharge_account_code = _94_(리스탁킹 피 계정 키와 같은 모양 · 잠금 밖 — inv_config_guard 는 잠긴 키를 양의 정수로만 받는다) · 발행 때 읽어 얼린다 · 비었거나 · 없거나 · 꺼졌으면 surcharge 있는 발행만 막는다(⭐ 머리 insert 가 번호를 당기기 전에) · 크레딧은 인보이스 줄 계정을 복사
--   묶음 7    크레딧은 surcharge 줄을 자동으로 — 돌려주는 수량 × 인보이스 surcharge 줄의 개당(문서는 문서에서 · so_line 이 아니다) · 세금은 그 줄 세율로 따로 반올림 · 리스탁킹 피 바탕(v_product_amt)과 물건값(lines_amount) 밖 · 손으로 보낸 kind surcharge 는 거부(D-3 · 자동 값과 어긋나는 줄을 안 만든다)
--   묶음 3    surcharge 는 물건값(lines_amount)과 따로 — so_invoice · so_invoice_order · so_credit 의 surcharge_amount 칸 · taxable_amount = lines + order_discount + charges + surcharge · so_credit.total = lines + fee + surcharge + tax
--   2a 중간 상태를 닫는다 — so_invoice_issue 가 so_tax_preview 의 totals.tax(2a 부터 surcharge 세금 포함)를 읽으면서 surcharge 금액 줄이 없던 것(2a 검증 F3′ 20.00 / 2.78 / 22.78) → 이제 20.00 + 1.40 + 2.78 = 24.18
--   무접촉    2a 의 함수 · 도우미 · so_invoice_detail · so_credit_detail(to_jsonb 라 새 칸 · 새 kind 가 저절로 실린다) · so_invoice_remaining · so_credit_remaining · so_customer_balance · so_invoice_ar_summary(total 만 읽는다) · so_invoice_cancel · so_invoice_reissue · so_pos_complete · so_counter_ship(전부 so_invoice_issue 를 거친다 — insert into public.so_invoice 는 그 함수 한 곳) · ims_config_locked_keys(계정 코드 키는 잠금 밖)
--
-- ① inv_config so_surcharge_account_code = _94_ seed(있으면 두기)
-- ② 표 — so_invoice · so_invoice_order · so_credit 에 surcharge_amount numeric not null default 0 · CHECK 다시 걸기(taxable 둘 · credit total) · so_credit_surcharge_ck(≥ 0) · so_invoice_line kind + so_line_ck · qty_ck 를 product|surcharge 로 · so_credit_line kind + qty_ck 를 product|surcharge 로 · 기존 행은 기본값 0 으로 그대로 맞는다(E 검증 · ALTER 가 검사한다)
-- ③ so_invoice_issue 재발행(마지막 정의 20260925205011:271 바이트 그대로 + surcharge 자리 — 선언 1 · 계정 10 · 오더 몫 1 · 오더 행 2 · 줄 7 · 합 1 · 머리 3 · 반환 1)
-- ④ so_credit_issue 재발행(20260925012354:928 · 선언 1 · 손으로 거부 1 · 자동 줄 15 · 미리 보기 1 · 머리 2 · 반환 1)
-- ⑤ so_credit_prepare 재발행(20260925205011:562 · surcharge 줄도 보인다 · amount_credited)
-- ⑥ 뷰 so_invoice_list(20260925191843:16) · so_credit_list(20260925205011:36) — create or replace · surcharge_amount 를 끝에(권한 유지)
--   검증: ~/asung/prompts/surcharge-2b-verify.sql (시험 적용 장치 · 테스트 DB · rollback · 시퀀스 셋 setval) · ⚠️ 운영 무접촉(컷오버 전 운영 적용 금지 · ims-principles)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 의 바이트 복사 — 운영에서는 멈춘다
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

-- ═══ ① 계정 설정 — 리스탁킹 피 계정 키와 같은 모양(잠금 밖) ═══════════════════════════════════════════════════════════════
insert into public.inv_config (key, value, note) values
  ('so_surcharge_account_code', '_94_', 'SO 인보이스 · surcharge 줄(kind surcharge)의 계정 code(ref_account) · 발행 때 읽어 줄에 얼린다 · 비었거나 계정이 없거나 꺼졌으면 surcharge 가 있는 발행만 막는다(surcharge-2 묶음 6 · so-module §37) · 잠금 밖(계정 코드 — inv_config_guard 는 잠긴 키를 양의 정수로만 받는다 · so_credit_restock_fee_account_code 와 같은 모양) · 회계사 확인 거리 36-e 76')
on conflict (key) do nothing;

-- ═══ ② 표 — 머리 칸 셋 · CHECK 다시 걸기 · 줄 종류 둘 ═══════════════════════════════════════════════════════════════════════
alter table public.so_invoice       add column if not exists surcharge_amount numeric not null default 0;
alter table public.so_invoice_order add column if not exists surcharge_amount numeric not null default 0;
alter table public.so_credit        add column if not exists surcharge_amount numeric not null default 0;
alter table public.so_invoice       drop constraint so_invoice_taxable_ck;
alter table public.so_invoice       add constraint so_invoice_taxable_ck check (taxable_amount = lines_amount + order_discount_amount + charges_amount + surcharge_amount);
alter table public.so_invoice_order drop constraint so_invoice_order_taxable_ck;
alter table public.so_invoice_order add constraint so_invoice_order_taxable_ck check (taxable_amount = lines_amount + order_discount_amount + charges_amount + surcharge_amount);
alter table public.so_credit        drop constraint so_credit_total_ck;
alter table public.so_credit        add constraint so_credit_total_ck check (total = lines_amount + fee_amount + surcharge_amount + tax_amount),
                                    add constraint so_credit_surcharge_ck check (surcharge_amount >= 0);
alter table public.so_invoice_line  drop constraint so_invoice_line_kind_ck, drop constraint so_invoice_line_so_line_ck, drop constraint so_invoice_line_qty_ck;
alter table public.so_invoice_line
  add constraint so_invoice_line_kind_ck    check (kind in ('product', 'charge', 'order_discount', 'surcharge')),
  add constraint so_invoice_line_so_line_ck check ((kind in ('product', 'surcharge')) = (so_line_id is not null)),
  add constraint so_invoice_line_qty_ck     check ((kind in ('product', 'surcharge')) = (qty is not null));
alter table public.so_credit_line   drop constraint so_credit_line_kind_ck, drop constraint so_credit_line_qty_ck;
alter table public.so_credit_line
  add constraint so_credit_line_kind_ck     check (kind in ('product', 'freight', 'tax', 'other', 'restocking_fee', 'surcharge')),
  add constraint so_credit_line_qty_ck      check ((kind in ('product', 'surcharge')) = (qty_returned is not null));
comment on column public.so_invoice.surcharge_amount       is 'surcharge-2b(묶음 3 · 5) — surcharge 줄(kind surcharge) 금액 합 · 물건값(lines_amount)과 따로 · taxable_amount = lines + order_discount + charges + surcharge(CHECK so_invoice_taxable_ck) · 세금은 tax_amount 에 함께(줄마다 따로 반올림한 값의 합)';
comment on column public.so_invoice_order.surcharge_amount is 'surcharge-2b — 이 오더 몫의 surcharge 합(so_tax_preview totals.surcharge_amount · basis shipped) · CHECK so_invoice_order_taxable_ck';
comment on column public.so_credit.surcharge_amount        is 'surcharge-2b(묶음 7) — 자동 surcharge 줄 합(≥ 0 · CHECK so_credit_surcharge_ck) · lines_amount(product · freight · tax · other) 밖 · total = lines + fee + surcharge + tax(CHECK so_credit_total_ck) · 리스탁킹 피 바탕이 아니다';
comment on constraint so_invoice_line_kind_ck on public.so_invoice_line is 'product · charge · order_discount · surcharge(surcharge-2b · 그 상품 줄 바로 뒤 · so_line_id = 그 상품 줄의 so_line · description = surcharge_label · qty = 보낸 수량 · unit_price = 개당 · amount = 개당 × 수량 · 계정 inv_config so_surcharge_account_code)';
comment on constraint so_credit_line_kind_ck  on public.so_credit_line  is 'product · freight · tax · other · restocking_fee · surcharge(surcharge-2b · 자동만 — 손으로 보내면 거부 · so_invoice_line_id = 인보이스 surcharge 줄 · qty_returned = 그 상품 줄과 같다 · unit_price = 인보이스 줄 개당)';

-- ═══ ③ so_invoice_issue 재발행 — 마지막 정의 20260925205011_so_credit_read.sql:271~508 바이트 그대로 + surcharge 자리 ═══
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
    if v_o_lines + v_o_od + v_o_chg = 0 and not exists (select 1 from public.so_line l where l.so_id = v_so.id and l.qty_shipped > 0) then
      raise exception 'Order % shipped nothing — there is nothing to invoice — nothing was saved', v_so.so_number;
    end if;

    insert into public.so_invoice_order (invoice_id, so_id, so_number, customer_id,
                                         ship_to_company, ship_to_contact, ship_to_phone, ship_to_line1, ship_to_line2, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country,
                                         tax_rule_id, tax_rule, rate_pct, tax_source, draft_rule_changed,
                                         lines_amount, order_discount_pct, order_discount_amount, charges_amount, surcharge_amount, taxable_amount, tax_amount, total, updated_by)
    values (v_inv.id, v_so.id, v_so.so_number, v_so.customer_id,
            v_so.ship_to_company, v_so.ship_to_contact, v_so.ship_to_phone, v_so.ship_to_line1, v_so.ship_to_line2, v_so.ship_to_city, v_so.ship_to_state_province, v_so.ship_to_postal_code, v_so.ship_to_country,
            v_rule_id, v_rule, v_rate, case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, v_changed,
            v_o_lines, v_so.order_discount_pct, v_o_od, v_o_chg, v_o_sc, v_o_lines + v_o_od + v_o_chg + v_o_sc, v_o_tax, v_o_lines + v_o_od + v_o_chg + v_o_sc + v_o_tax, p_staff)
    returning * into v_io;

    for e in select x from jsonb_array_elements(v_prev->'lines') x loop                     -- 제품 줄(보낸 수량 > 0 만 · 안 나간 줄은 종이에 없다)
      if (e->>'qty')::numeric > 0 then
        v_ln := v_ln + 1;
        insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, unit, pack_factor, qty, list_price, discount_pct, discount_source, unit_price, amount, tax_amount, account_id, account_code, updated_by)
        values (v_inv.id, v_io.id, v_ln, 'product', (e->>'line_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
                (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, e->>'discount_source', (e->>'unit_price')::numeric, (e->>'amount')::numeric, (e->>'tax')::numeric,
                v_so.sale_account_id, v_so.sale_account_code, p_staff);
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
    end loop;

    v_lines_amt := v_lines_amt + v_o_lines;  v_od_amt := v_od_amt + v_o_od;  v_chg_amt := v_chg_amt + v_o_chg;  v_tax := v_tax + v_o_tax;  v_sc_amt := v_sc_amt + v_o_sc;   -- surcharge-2b
    if v_changed then v_warn := array_append(v_warn, 'draft_rule_changed:' || v_so.so_number); end if;
    if coalesce(v_prev->'warnings', '[]'::jsonb) ? 'tax_rule_inactive' then v_warn := array_append(v_warn, 'tax_rule_inactive:' || v_so.so_number); end if;

    update public.so set status = 'fulfilled', invoiced_at = now(), closed_at = now(), updated_by = p_staff where id = v_so.id and status = 'shipped';   -- ⓑ2 판정 1: 문지기 짝 shipped→fulfilled · 끝 상태 closed_at 짝(so_closed_at_ck)
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Order % was not invoiced — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'tax_rule', v_rule, 'rate_pct', v_rate,
                                               'tax_source', case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, 'draft_rule_changed', v_changed, 'totals', v_prev->'totals');
  end loop;

  -- 합계를 먼저 굳힌다(so_invoice_remaining 이 total 을 본다) · 잔액 항은 아직 0
  v_total := v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt + v_tax;                                                                           -- surcharge-2b
  update public.so_invoice set lines_amount = v_lines_amt, order_discount_amount = v_od_amt, charges_amount = v_chg_amt, surcharge_amount = v_sc_amt,
                               taxable_amount = v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt, tax_amount = v_tax, total = v_total, amount_due = v_total, updated_by = p_staff
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
                            'totals', jsonb_build_object('lines_amount', v_inv.lines_amount, 'order_discount_amount', v_inv.order_discount_amount, 'charges_amount', v_inv.charges_amount, 'surcharge_amount', v_inv.surcharge_amount,
                                                         'taxable_amount', v_inv.taxable_amount, 'tax_amount', v_inv.tax_amount, 'total', v_inv.total,
                                                         'deposit_applied', v_inv.deposit_applied, 'credit_applied', v_inv.credit_applied, 'balance_forward', v_inv.balance_forward, 'amount_due', v_inv.amount_due,
                                                         'remaining', public.so_invoice_remaining(v_inv.id)),
                            'applied', v_applied,
                            'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id),
                            'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ④ so_credit_issue 재발행 — 마지막 정의 20260925012354_so_credit_c1.sql:928~1187 바이트 그대로 + surcharge 자리 ═══
create or replace function public.so_credit_issue(p jsonb, p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_reasons   constant text[] := array['customer_return','damaged','billing_error','other'];
  c_nr        constant text[] := array['damaged','b_grade','not_returned','other'];
  v_staff     uuid;
  v_on        date;
  v_reason    text;
  v_inv       public.so_invoice%rowtype;
  v_c         public.customer%rowtype;
  v_cur       public.ref_currency%rowtype;
  v_w         public.ref_warehouse%rowtype;
  v_rule      public.ref_tax_rule%rowtype;
  v_cr        public.so_credit%rowtype;
  v_il        public.so_invoice_line%rowtype;
  v_io        public.so_invoice_order%rowtype;
  v_pr        public.product%rowtype;
  v_bin       public.ref_bin%rowtype;
  v_acct      public.ref_account%rowtype;
  v_cin7      boolean := false;
  v_cin7_inv  text;  v_cin7_ord text;  v_cin7_date date;
  v_cust      uuid;
  v_origin_on date;
  v_wh        uuid;
  v_first_io  public.so_invoice_order%rowtype;
  v_fee_days  int;  v_fee_pct numeric;  v_fee_acct_code text;
  v_lines     jsonb := '[]'::jsonb;
  v_ln        int := 0;
  v_kind      text;
  v_qty       numeric;  v_already numeric;  v_unit numeric;  v_amount numeric;  v_rate numeric;  v_tax numeric;
  v_bin_name  text;  v_bin_id uuid;  v_nr text;  v_nr_note text;  v_desc text;  v_acct_id uuid;  v_acct_code text;
  v_product_id uuid;  v_so_line_id uuid;  v_sku text;  v_il_id uuid;
  v_lines_amt numeric := 0;  v_fee_amt numeric := 0;  v_tax_amt numeric := 0;  v_product_amt numeric := 0;
  v_sc        public.so_invoice_line%rowtype;  v_sc_amt numeric := 0;  v_sc_line numeric;  v_sc_tax numeric;  v_sc_already numeric;   -- surcharge-2b(묶음 7)
  v_rates     numeric[] := '{}';  v_first_rate numeric;
  v_fee_lines int := 0;  v_restock_n int := 0;
  v_fee_sugg  jsonb;
  v_warn      text[] := '{}';
  v_ledger    jsonb;
  v_est       numeric;  v_est_qty numeric;
  v_ask       numeric;
  x           jsonb;
  e           jsonb;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — 발행은 manager 이상(판정 3)
  v_staff := public.so_current_staff();
  v_on := coalesce(nullif(p->>'issued_on', '')::date, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Credit date % is in the future — nothing was saved', v_on; end if;
  v_reason := nullif(trim(p->>'reason'), '');
  if v_reason is null or v_reason <> all (c_reasons) then raise exception 'reason must be one of customer_return, damaged, billing_error, other — nothing was saved'; end if;
  if v_reason = 'other' and nullif(trim(p->>'note'), '') is null then raise exception 'reason other needs a note — nothing was saved'; end if;
  if p->'lines' is null or jsonb_typeof(p->'lines') <> 'array' or jsonb_array_length(p->'lines') = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  -- 설정(판정 5·7)
  select nullif(k.value, '')::int into v_fee_days from public.inv_config k where k.key = 'so_credit_restock_fee_days';
  select nullif(k.value, '')::numeric into v_fee_pct from public.inv_config k where k.key = 'so_credit_restock_fee_pct';
  select nullif(k.value, '') into v_fee_acct_code from public.inv_config k where k.key = 'so_credit_restock_fee_account_code';

  -- 원본 — IMS 인보이스 또는 Cin7 번호 원문(판정 6 · 0-4)
  if nullif(p->>'invoice_id', '') is not null then
    select * into v_inv from public.so_invoice i where i.id = (p->>'invoice_id')::uuid for update;
    if not found then raise exception 'Invoice not found — nothing was saved'; end if;
    if v_inv.status <> 'issued' then raise exception 'Invoice % is % — credit the live invoice, not a cancelled one — nothing was saved', v_inv.invoice_number, v_inv.status; end if;
    v_cust := v_inv.bill_to_customer_id;  v_origin_on := v_inv.issued_on;
    select * into v_cur from public.ref_currency c where c.id = v_inv.currency_id;
    select o.* into v_first_io from public.so_invoice_order o where o.invoice_id = v_inv.id order by o.so_number limit 1;
    select s.location_id into v_wh from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id order by o.so_number limit 1;
  elsif p->'cin7' is not null and jsonb_typeof(p->'cin7') = 'object' then
    v_cin7 := true;
    v_cin7_inv := nullif(trim(p->'cin7'->>'invoice_number'), '');  v_cin7_ord := nullif(trim(p->'cin7'->>'order_number'), '');  v_cin7_date := nullif(p->'cin7'->>'invoice_date', '')::date;
    if v_cin7_inv is null then raise exception 'A Cin7 credit needs cin7.invoice_number (the paper number) — nothing was saved'; end if;
    if nullif(p->>'customer_id', '') is null then raise exception 'A Cin7 credit needs customer_id — nothing was saved'; end if;
    v_cust := (p->>'customer_id')::uuid;  v_origin_on := v_cin7_date;
    if v_cin7_ord is null then v_warn := array_append(v_warn, 'origin_sale_unknown'); end if;
    select * into v_cur from public.ref_currency c
     where c.id = coalesce(nullif(p->>'currency_id', '')::uuid, (select c2.id from public.ref_currency c2 where c2.code = upper(nullif(trim(p->>'currency_code'), ''))), (select c3.currency_id from public.customer c3 where c3.id = v_cust));
    if v_cur.id is null then raise exception 'Currency is required — the customer has no default currency — nothing was saved'; end if;
    if nullif(trim(p->>'tax_rule'), '') is null then raise exception 'A Cin7 credit needs tax_rule (an active sale tax rule name) — nothing was saved'; end if;
    select * into v_rule from public.ref_tax_rule r where r.name = trim(p->>'tax_rule') and r.direction = 'sale' and r.is_active;
    if v_rule.id is null then raise exception 'Tax rule % is not an active sale rule — nothing was saved', trim(p->>'tax_rule'); end if;
    select c.default_location_id into v_wh from public.customer c where c.id = v_cust;
  else
    raise exception 'Give invoice_id (an IMS invoice) or cin7 {invoice_number, order_number, invoice_date} — nothing was saved';
  end if;
  select * into v_c from public.customer c where c.id = v_cust for update;         -- 청구처 손님 행 잠금(잔액 직렬화 · ⓑ 와 같은 자물쇠)
  if not found then raise exception 'Customer not found — nothing was saved'; end if;

  -- 창고(반품을 받은 창고 · ⬜4) — 지정 → 원 판매 창고 → 손님 기본 창고 → 거부
  v_wh := coalesce(nullif(p->>'warehouse_id', '')::uuid, v_wh);
  if v_wh is null then raise exception 'warehouse_id is required — where were the goods returned to? — nothing was saved'; end if;
  select * into v_w from public.ref_warehouse w where w.id = v_wh;
  if not found then raise exception 'Warehouse not found — nothing was saved'; end if;
  if not v_w.is_active then raise exception 'Warehouse % is inactive — nothing was saved', v_w.name; end if;

  -- 줄 — 첫 바퀴: product · freight · tax · other(수수료는 둘째 바퀴 · 제품 합이 먼저 필요하다)
  for x in select t from jsonb_array_elements(p->'lines') t loop
    v_kind := nullif(trim(x->>'kind'), '');
    if v_kind = 'surcharge' then raise exception 'Surcharge lines are added automatically from the returned product lines — do not send them — nothing was saved'; end if;   -- surcharge-2b(D-3 · 자동만)
    if v_kind is null or v_kind not in ('product','freight','tax','other','restocking_fee') then raise exception 'Line kind must be one of product, freight, tax, other, restocking_fee — nothing was saved'; end if;
    if v_kind = 'restocking_fee' then v_fee_lines := v_fee_lines + 1; continue; end if;
    v_il := null;  v_io := null;  v_pr := null;  v_bin := null;  v_acct := null;
    v_qty := null;  v_unit := null;  v_rate := null;  v_bin_id := null;  v_bin_name := null;  v_nr := null;  v_nr_note := null;  v_product_id := null;  v_so_line_id := null;  v_sku := null;  v_il_id := null;  v_desc := null;  v_est := null;
    v_acct_id := nullif(x->>'account_id', '')::uuid;
    if v_acct_id is not null then
      select * into v_acct from public.ref_account a where a.id = v_acct_id;
      if v_acct.id is null then raise exception 'Account % not found — nothing was saved', v_acct_id; end if;
    end if;

    if v_kind = 'product' then
      v_qty := nullif(x->>'qty_returned', '')::numeric;
      if v_qty is null or v_qty <= 0 then raise exception 'A product line needs qty_returned > 0 — nothing was saved'; end if;
      if v_cin7 then
        v_sku := nullif(trim(x->>'sku'), '');
        if v_sku is null then raise exception 'A Cin7 product line needs sku — nothing was saved'; end if;
        select * into v_pr from public.product pr where pr.sku = v_sku;
        if v_pr.id is null then raise exception 'Product % not found — nothing was saved', v_sku; end if;
        v_unit := nullif(x->>'unit_price', '')::numeric;
        if v_unit is null or v_unit < 0 then raise exception 'A Cin7 product line needs unit_price (the price on that invoice) — nothing was saved'; end if;
        v_rate := v_rule.rate_pct;  v_product_id := v_pr.id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_pr.name);
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_98_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then raise exception 'An IMS product line needs so_invoice_line_id (the invoice line being returned) — nothing was saved'; end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'product';
        if v_il.id is null then raise exception 'Invoice line % is not a product line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        select coalesce(sum(cl.qty_returned), 0) into v_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id
         where cl.so_invoice_line_id = v_il.id and c.status = 'issued';
        select coalesce(sum((t->>'qty_returned')::numeric), 0) into v_ask from jsonb_array_elements(p->'lines') t where t->>'kind' = 'product' and nullif(t->>'so_invoice_line_id', '')::uuid = v_il.id;
        if v_already + v_ask > v_il.qty then
          raise exception 'Invoice % line % (%): % of % already credited and % asked now — only % can still be returned — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, v_already, v_il.qty, v_ask, v_il.qty - v_already;
        end if;
        v_unit := v_il.unit_price;  v_rate := v_io.rate_pct;  v_sku := v_il.sku;  v_so_line_id := v_il.so_line_id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        select sl.product_id into v_product_id from public.so_line sl where sl.id = v_il.so_line_id;
        select * into v_pr from public.product pr where pr.id = v_product_id;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      v_amount := round(v_qty * coalesce(v_unit, 0), 2);  v_tax := public.so_tax_amount(v_amount, v_rate);
      v_product_amt := v_product_amt + v_amount;  v_rates := array_append(v_rates, v_rate);
      -- 돌아오나(판정 1) — not_restocked_reason 이 있으면 안 돌아옴 · 아니면 칸(지정 → ims_last_bin → 거부 · '' 불허 · ⬜4)
      v_nr := nullif(trim(x->>'not_restocked_reason'), '');
      if v_nr is not null then
        if v_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
        v_nr_note := nullif(trim(x->>'not_restocked_note'), '');
        if v_nr = 'other' and v_nr_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
      else
        v_bin_name := nullif(trim(x->>'restock_bin'), '');
        if v_bin_name is null then
          v_bin_name := public.ims_last_bin(array[coalesce(v_pr.parent_product_id, v_pr.id)], v_w.id) -> coalesce(v_pr.parent_product_id, v_pr.id)::text ->> 'bin';
          if v_bin_name is null then raise exception 'No bin known for % in % — pick a restock bin (or mark the line not restocked) — nothing was saved', v_sku, v_w.name; end if;
        end if;
        select * into v_bin from public.ref_bin rb where rb.warehouse_id = v_w.id and rb.name = v_bin_name;
        if v_bin.id is null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bin_name, v_w.name; end if;
        if not v_bin.is_active then v_warn := array_append(v_warn, 'inactive_bin:' || v_bin_name); end if;
        v_bin_id := v_bin.id;  v_restock_n := v_restock_n + 1;
        -- 원가 복원 예상(미리 보기 · 원 판매의 소비 기록 평균 × EA · 없으면 null)
        select sum(cs.qty * cs.unit_cost) / nullif(sum(cs.qty), 0), sum(cs.qty) into v_est, v_est_qty
          from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
         where cs.doc_type = 'sale' and cs.reason = 'sale' and l.sku = coalesce((select pp.sku from public.product pp where pp.id = v_pr.parent_product_id), v_pr.sku)
           and cs.doc_number = case when v_cin7 then v_cin7_ord else (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id)) end;
      end if;
    elsif v_kind = 'freight' then
      if v_cin7 then
        v_amount := nullif(x->>'amount', '')::numeric;  v_rate := v_rule.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Freight');
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_99_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then raise exception 'An IMS freight line needs so_invoice_line_id (the charge line) — nothing was saved'; end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'charge';
        if v_il.id is null then raise exception 'Invoice line % is not a charge line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        v_amount := coalesce(nullif(x->>'amount', '')::numeric, v_il.amount);  v_rate := v_io.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        select coalesce(sum(cl.amount), 0) into v_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_il.id and c.status = 'issued';
        if v_already + v_amount > v_il.amount then raise exception 'Invoice % charge % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_already, v_il.amount, v_il.amount - v_already; end if;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      if v_amount is null or v_amount < 0 then raise exception 'A freight line needs amount ≥ 0 — nothing was saved'; end if;
      v_tax := public.so_tax_amount(v_amount, v_rate);
    elsif v_kind = 'tax' then
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null or v_amount < 0 then raise exception 'A tax line needs amount ≥ 0 (the tax being returned) — nothing was saved'; end if;
      v_rate := null;  v_tax := 0;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Tax');
      if v_acct.id is null then
        select * into v_acct from public.ref_account a where a.id = (case when v_cin7 then v_rule.account_id else (select r.account_id from public.ref_tax_rule r where r.id = v_first_io.tax_rule_id) end);
      end if;
    else   -- other
      v_amount := nullif(x->>'amount', '')::numeric;  v_desc := nullif(trim(x->>'description'), '');
      if v_amount is null or v_amount < 0 then raise exception 'An other line needs amount ≥ 0 — nothing was saved'; end if;
      if v_desc is null then raise exception 'An other line needs a description — nothing was saved'; end if;
      if v_acct.id is null then raise exception 'An other line needs account_id (no default) — nothing was saved'; end if;
      v_rate := case when v_cin7 then v_rule.rate_pct else v_first_io.rate_pct end;  v_tax := public.so_tax_amount(v_amount, v_rate);
    end if;
    v_ln := v_ln + 1;  v_lines_amt := v_lines_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
    v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', v_kind, 'so_invoice_line_id', v_il_id, 'so_line_id', v_so_line_id, 'product_id', v_product_id, 'sku', v_sku, 'description', v_desc,
                                             'qty_returned', v_qty, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                             'unit_price', v_unit, 'amount', v_amount, 'rate_pct', v_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code,
                                             'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_qty * coalesce(v_pr.pack_factor, 1), 6) end);
    if v_kind = 'product' and not v_cin7 then                                                                  -- surcharge-2b(묶음 7): 그 상품의 인보이스 surcharge 줄이 있으면 크레딧 surcharge 줄을 자동으로 · 개당은 인보이스 줄의 것(문서는 문서에서) · 세금은 그 줄 세율로 따로 · 계정 복사 · 물건값(v_lines_amt) · 리스탁킹 피 바탕(v_product_amt) 밖
      select * into v_sc from public.so_invoice_line il where il.invoice_id = v_inv.id and il.kind = 'surcharge' and il.so_line_id = v_il.so_line_id;
      if v_sc.id is not null then
        v_sc_line := public.so_line_surcharge_total(v_sc.unit_price, v_qty);
        select coalesce(sum(cl.amount), 0) into v_sc_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_sc.id and c.status = 'issued';
        if v_sc_already + v_sc_line > v_sc.amount then raise exception 'Invoice % surcharge of line % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_sc_already, v_sc.amount, v_sc.amount - v_sc_already; end if;
        v_sc_tax := public.so_tax_amount(v_sc_line, v_io.rate_pct);
        v_ln := v_ln + 1;  v_sc_amt := v_sc_amt + v_sc_line;  v_tax_amt := v_tax_amt + coalesce(v_sc_tax, 0);
        v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'surcharge', 'so_invoice_line_id', v_sc.id, 'so_line_id', v_sc.so_line_id, 'product_id', v_product_id, 'sku', v_sc.sku, 'description', v_sc.description,
                                                 'qty_returned', v_qty, 'unit_price', v_sc.unit_price, 'amount', v_sc_line, 'rate_pct', v_io.rate_pct, 'tax_amount', coalesce(v_sc_tax, 0), 'account_id', v_sc.account_id, 'account_code', v_sc.account_code);
      end if;
    end if;
  end loop;

  -- 둘째 바퀴 — Restocking fee(판정 4·5·7 · 0-8): 기본 −round(Σ제품 × pct/100, 2) · 계정 = 지정 → 설정 → 거부 · 세율 = 첫 제품 줄(섞이면 경고) · 세금도 음수
  v_first_rate := case when v_cin7 then v_rule.rate_pct else v_rates[1] end;
  if v_fee_lines > 0 then
    if v_fee_lines > 1 then raise exception 'Only one restocking_fee line per credit note — nothing was saved'; end if;
    if (select count(distinct r) from unnest(v_rates) r) > 1 then v_warn := array_append(v_warn, 'fee_rate_mixed'); end if;
    for x in select t from jsonb_array_elements(p->'lines') t where t->>'kind' = 'restocking_fee' loop
      v_acct := null;  v_acct_id := nullif(x->>'account_id', '')::uuid;
      if v_acct_id is not null then select * into v_acct from public.ref_account a where a.id = v_acct_id;
      elsif v_fee_acct_code is not null then select * into v_acct from public.ref_account a where a.code = v_fee_acct_code; end if;
      if v_acct.id is null then raise exception 'A restocking fee line needs account_id — no default account is set (inv_config so_credit_restock_fee_account_code) — nothing was saved'; end if;
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null then v_amount := -round(v_product_amt * coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct, 0) / 100, 2); end if;
      if v_amount > 0 then raise exception 'A restocking fee reduces the credit — amount must be ≤ 0 (got %) — nothing was saved', v_amount; end if;
      v_tax := public.so_tax_amount(v_amount, v_first_rate);
      v_ln := v_ln + 1;  v_fee_amt := v_fee_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'restocking_fee', 'description', coalesce(nullif(trim(x->>'description'), ''), format('Restocking fee %s%%', coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct))),
                                               'amount', v_amount, 'rate_pct', v_first_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code);
    end loop;
  end if;
  -- 알림(판정 5) — 원 인보이스 발행일 + N일이 지났고 수수료 줄이 없으면 「대상」만 알린다(자동으로 붙이지 않는다)
  if v_origin_on is null then v_warn := array_append(v_warn, 'fee_window_unknown');
  elsif v_fee_days is not null and v_on - v_origin_on > v_fee_days and v_fee_lines = 0 and v_product_amt > 0 then
    v_warn := array_append(v_warn, 'restock_fee_window:' || (v_on - v_origin_on)::text);
    v_fee_sugg := jsonb_build_object('days_since_invoice', v_on - v_origin_on, 'pct', v_fee_pct, 'amount', -round(v_product_amt * coalesce(v_fee_pct, 0) / 100, 2), 'account_code', v_fee_acct_code);
  end if;
  if v_ln = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  if not p_commit then
    return jsonb_build_object('committed', false, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code, 'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                              'origin', case when v_cin7 then jsonb_build_object('cin7_invoice_number', v_cin7_inv, 'cin7_order_number', v_cin7_ord, 'cin7_invoice_date', v_cin7_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct)
                                             else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                              'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_lines_amt, 'fee_amount', v_fee_amt, 'surcharge_amount', v_sc_amt, 'tax_amount', v_tax_amt, 'total', v_lines_amt + v_fee_amt + v_sc_amt + v_tax_amt, 'restock_lines', v_restock_n),
                              'fee_suggested', v_fee_sugg, 'ledger', null, 'warnings', to_jsonb(v_warn));
  end if;

  insert into public.so_credit (customer_id, currency_id, currency_code, invoice_id, cin7_invoice_number, cin7_order_number, cin7_invoice_date, origin_invoice_on, reason, note,
                                warehouse_id, warehouse_name, tax_rule_id, tax_rule, rate_pct, issued_on, issued_by, lines_amount, fee_amount, surcharge_amount, tax_amount, total, created_by, updated_by)
  values (v_cust, v_cur.id, v_cur.code, v_inv.id, v_cin7_inv, v_cin7_ord, v_cin7_date, v_origin_on, v_reason, nullif(trim(p->>'note'), ''),
          v_w.id, v_w.name, v_rule.id, v_rule.name, v_rule.rate_pct, v_on, v_staff, v_lines_amt, v_fee_amt, v_sc_amt, v_tax_amt, v_lines_amt + v_fee_amt + v_sc_amt + v_tax_amt, v_staff, v_staff)
  returning * into v_cr;
  for e in select t from jsonb_array_elements(v_lines) t loop
    insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, so_line_id, product_id, sku, description, qty_returned, restock_bin_id, restock_bin, not_restocked_reason, not_restocked_note,
                                       unit_price, amount, rate_pct, tax_amount, account_id, account_code, updated_by)
    values (v_cr.id, (e->>'line_no')::int, e->>'kind', nullif(e->>'so_invoice_line_id', '')::uuid, nullif(e->>'so_line_id', '')::uuid, nullif(e->>'product_id', '')::uuid, e->>'sku', e->>'description',
            nullif(e->>'qty_returned', '')::numeric, nullif(e->>'restock_bin_id', '')::uuid, e->>'restock_bin', e->>'not_restocked_reason', e->>'not_restocked_note',
            nullif(e->>'unit_price', '')::numeric, (e->>'amount')::numeric, nullif(e->>'rate_pct', '')::numeric, (e->>'tax_amount')::numeric, nullif(e->>'account_id', '')::uuid, e->>'account_code', v_staff);
  end loop;
  if v_restock_n > 0 then
    v_ledger := public.inv_post_credit(v_cr.id, v_on);
    v_warn := v_warn || coalesce((select array_agg(t.w) from jsonb_array_elements_text(coalesce(v_ledger->'warnings', '[]'::jsonb)) as t(w)), '{}');
  end if;

  return jsonb_build_object('committed', true, 'credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', v_cr.status, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code,
                            'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                            'origin', case when v_cin7 then jsonb_build_object('cin7_invoice_number', v_cin7_inv, 'cin7_order_number', v_cin7_ord, 'cin7_invoice_date', v_cin7_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct)
                                           else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                            'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_cr.lines_amount, 'fee_amount', v_cr.fee_amount, 'surcharge_amount', v_cr.surcharge_amount, 'tax_amount', v_cr.tax_amount, 'total', v_cr.total, 'restock_lines', v_restock_n),
                            'fee_suggested', v_fee_sugg, 'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑤ so_credit_prepare 재발행 — 마지막 정의 20260925205011_so_credit_read.sql:562~614 바이트 그대로 + surcharge 자리(create or replace · lines 필터 · amount_credited) ═══
create or replace function public.so_credit_prepare(p_invoice_id uuid) returns jsonb
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
                'amount_credited', case when l.kind in ('charge', 'surcharge') then (select coalesce(sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') end,   -- surcharge-2b: surcharge 줄은 보이기만(자동 · 손으로 못 보낸다)
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
              where l.invoice_id = inv.id and l.kind in ('product', 'charge', 'surcharge')),
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

-- ═══ ⑥ 뷰 둘 재발행 — so_invoice_list 20260925191843_so_invoice_read.sql:16 · so_credit_list 20260925205011_so_credit_read.sql:36 · 바이트 그대로 + create or replace + surcharge_amount 를 끝에(권한 유지) ═══
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
       i.surcharge_amount                                                                                                      -- surcharge-2b(끝에 — create or replace view 는 열을 끝에만 더할 수 있다)
from public.so_invoice i
left join public.customer cu on cu.id = i.bill_to_customer_id
left join ord o on o.invoice_id   = i.id
left join pay  on pay.invoice_id  = i.id
left join cred on cred.invoice_id = i.id
cross join lateral (select public.so_invoice_remaining(i.id) as remaining) r;   -- 읽기 함수(stable)를 lateral 에서 한 번만 — 쓰기 창구가 아니다

create or replace view public.so_credit_list
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
       (c.credit_number || ' ' || coalesce(cu.name, '') || ' ' || coalesce(i.invoice_number, '') || ' ' || coalesce(c.cin7_invoice_number, '') || ' ' || coalesce(al.invoice_numbers_applied, '') || ' ' || c.reason || ' ' || coalesce(c.note, '')) as search_text,
       c.surcharge_amount                                                                                                      -- surcharge-2b(끝에)
from public.so_credit c
left join public.customer cu on cu.id = c.customer_id
left join public.so_invoice i on i.id = c.invoice_id
left join al on al.credit_id = c.id
cross join lateral (select public.so_credit_remaining(c.id) as remaining) r;   -- 읽기 함수(stable)를 lateral 에서 한 번 — 쓰기 창구가 아니다

comment on function public.so_invoice_issue(uuid[], uuid, date) is
  '⭐⭐ 인보이스 발행 — 식 한 곳(§17 · ⓐ2 · ⓑ2 · ⓒ2 · surcharge-2b) · invoker · p_staff 필수 · shipped 오더 묶음(같은 청구처 · 같은 통화) · 오더마다 so_tax_preview(…, ''shipped'')의 totals 로 so_invoice_order(lines · od · charges · ⭐ surcharge_amount · taxable · tax · total) · 줄 사본 product(qty > 0) → ⭐ surcharge(그 상품 줄 바로 뒤 · so_tax_preview 줄 객체의 surcharge_label · surcharge_unit · surcharge_total · surcharge_tax · so_line_id 같음 · 계정 inv_config so_surcharge_account_code — 보낸 surcharge 줄이 있는데 키가 비었거나 계정이 없거나 꺼졌으면 머리 insert 앞에서 거부) → order_discount → charge · 머리 합계(surcharge_amount 포함 · CHECK 셋) · 선결제 · 크레딧 · 받아 둔 돈 자동 붙이기 · amount_due · so_finalize · so_pos_complete · so_invoice_reissue 가 부른다';
comment on function public.so_credit_issue(jsonb, boolean) is
  '⭐⭐ 크레딧 노트 발행(§19 · ⓒ1 · surcharge-2b) — definer · manager · p = {invoice_id | cin7{…}, reason, note, warehouse_id, issued_on, lines[{kind product|freight|tax|other|restocking_fee …}]} · ⭐ IMS product 줄마다 그 상품의 인보이스 surcharge 줄이 있으면 kind surcharge 줄을 자동으로 바로 뒤에(qty_returned × 인보이스 개당 · so_line_surcharge_total · 세금 그 줄 세율 · 계정 복사 · Σ ≤ 인보이스 surcharge amount) · 손으로 보낸 kind surcharge 는 거부 · 머리 surcharge_amount(lines_amount · 리스탁킹 피 바탕 밖) · total = lines + fee + surcharge + tax · p_commit false 미리 보기 · restock_bin_id 있으면 inv_post_credit';
comment on function public.so_credit_prepare(uuid) is
  '크레딧 준비물(so-credit-read-1 R3 · surcharge-2b) — invoice · warehouse · lines(product · charge · ⭐ surcharge — 보이기만 · amount_credited · 손으로는 못 보낸다 · vocab.line_kinds 는 보낼 수 있는 다섯 그대로) · restock_fee · already_credited · vocab';
comment on view public.so_invoice_list is
  '⭐ 판매 인보이스 목록(so-inv-read-1 R1 · 2026-09-25 · surcharge-2b 열 하나 끝에) — 한 장 한 행 · PostgREST 로 표처럼(range · order · ilike) · security_invoker. 돈: paid = 살아 있는 결제 붙임 · credited = 살아 있는 크레딧 붙임(issued) · remaining = so_invoice_remaining(id)(식의 정본 · 취소는 0) · paid + credited = total − remaining(issued) · ⭐ surcharge_amount(묶음 3 · 물건값과 따로 · total 에는 들어 있다) · days_overdue = remaining > 0 ∧ due_on < ims_today() 일 때 일수 · is_open = issued ∧ remaining > 0 · so_numbers·so_ids·order_count·channel 은 살아 있는 so_invoice_order 만 · search_text = 번호 · 청구처 · 손님 · 오더 번호 · 오더 ref';
comment on view public.so_credit_list is
  '⭐ 크레딧 노트 목록(so-credit-read-1 R1 · surcharge-2b 열 하나 끝에) — 한 장 한 행 · security_invoker · applied_to_invoices · refunded · remaining = so_credit_remaining(id) · applied + refunded + remaining = total(issued) · ⭐ surcharge_amount(자동 surcharge 줄 합 · lines_amount 밖 · total 에는 들어 있다) · invoice_number(원판매) · search_text';
