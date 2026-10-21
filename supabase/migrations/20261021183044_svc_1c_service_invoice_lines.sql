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

-- ═══ svc-1c — 서비스 인보이스 줄에 수량 · 단가 (2026-10-21 · 판정 590 · 593 ~ 597 · svc-1a · svc-1b 위) ═══
--   계기: 서비스 오더(channel service · svc-1b)의 인보이스 줄이 금액만 들었다(svc-1b N1 「invl: charge|540|70.2」) — 종이에 1200 × 0.45 가 아니라 540 만 보인다.
--   ① CHECK — so_invoice_line_qty_ck 를 kind charge 에 qty 를 허락하는 꼴로 다시(product · surcharge 는 qty 필수 · charge 는 선택 · 그 밖은 금지 — 옛 행 무변: 지금 charge 줄 9 행은 qty · unit_price 모두 null)
--      짝 CHECK so_invoice_line_charge_qty_ck(so_charge 의 짝 CHECK 와 같은 꼴): charge 줄은 qty · unit_price 둘 다 null 이거나 둘 다 · 있으면 amount = round(qty × unit_price, 2)
--   ② so_invoice_issue 재발행 — 비용 줄을 넣을 때 so_charge 의 qty · unit_price 를 함께(금액이 qty × 단가와 같을 때만 · 마무리 화면이 금액을 고친 운임은 금액만) · 금액 · 세금 · 할인 셈 무변 · 물건 · counter · 묶음 · 재발행(so_invoice_reissue → 같은 함수) 무변
--   ③ 문서 데이터 무접촉 — doc_data_invoice 는 이미 인보이스 줄의 qty · unit_price 를 charges 에 낸다(:19 ~ 20) · doc_data_invoice_fmt 는 doc_fmt_qty · doc_fmt_money(null → '' · 「0 이면 빈칸」 그대로) · doc_data_credit 은 크레딧 줄의 qty_returned · unit_price(서비스 크레딧은 금액만 — 아래 ⑤)
--   ④ 판 무접촉 — final_invoice v5 · credit_note v2 의 「Freight & surcharges」 표가 이미 {{qty}} · {{unit_price}} 칸을 그린다(지금은 빈칸)
--   ⑤ 크레딧 무접촉 — 서비스 인보이스의 서비스 줄은 so_credit_issue 의 freight 갈래(kind charge · so_invoice_line_id · amount)로 일부 · 전부 돌려준다 · 창고 = 서비스 오더의 창고(594) · 재입고 0 · 원장 0 · 크레딧 줄은 금액만(so_credit_line_qty_ck 가 freight 에 qty 를 막는다 — 시험 ④ 로 증명)
--   ⚠️ 재발행 몸 = DB 원문(svc-1b 정의) 바이트 + 바꾼 줄만(착지 md5) · 운영에는 닿지 않는다(가드).

create temp table svc1c_before as
select (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.proname in ('so_invoice_reissue', 'so_invoice_cancel', 'so_invoice_preview', 'so_credit_issue', 'so_credit_prepare', 'doc_data', 'doc_data_invoice', 'doc_data_invoice_fmt', 'doc_data_credit', 'so_tax_preview', 'so_finalize', 'so_service_invoice', 'so_pos_complete', 'so_charge_set')) as others,
       (select coalesce(p.proacl::text, '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_invoice_issue') as issue_acl,
       (select string_agg(conname || ':' || pg_get_constraintdef(oid), ' ' order by conname) from pg_constraint where conrelid = 'public.so_invoice_line'::regclass and contype = 'c' and conname <> 'so_invoice_line_qty_ck') as other_checks,
       (select count(*) from public.so_invoice_line where kind = 'charge') as n_charge_lines,
       (select count(*) from public.so_invoice_line where kind = 'charge' and (qty is not null or unit_price is not null)) as n_charge_qty;

-- ═══ ① CHECK — charge 줄에도 qty · unit_price(짝 · 금액 식) ═══
alter table public.so_invoice_line drop constraint so_invoice_line_qty_ck;
alter table public.so_invoice_line add constraint so_invoice_line_qty_ck
  check (case when kind in ('product', 'surcharge') then qty is not null when kind = 'charge' then true else qty is null end);
alter table public.so_invoice_line add constraint so_invoice_line_charge_qty_ck
  check (kind <> 'charge' or ((qty is null) = (unit_price is null) and (qty is null or amount = round(qty * unit_price, 2))));
comment on constraint so_invoice_line_charge_qty_ck on public.so_invoice_line is 'svc-1c(판정 590 · 596): 비용 줄이 수량 × 단가 줄(서비스)이면 qty · unit_price 둘 다 · amount = round(qty × unit_price, 2) · 운임처럼 금액만이면 둘 다 null';

-- ═══ so_invoice_issue 재발행 — 원본 20261021180840_svc_1b_service_channel.sql:682 바이트 + 더한 · 바꾼 줄만 · svc-1c ═══
CREATE OR REPLACE FUNCTION public.so_invoice_issue(p_so_ids uuid[], p_staff uuid, p_issued_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_applied  jsonb := '[]'::jsonb;
  v_a        public.so_payment_alloc%rowtype;
  v_plan     jsonb;                                                                     -- doc-1b2: 자동 붙이기 계획(so_invoice_apply_plan · 미리 보기와 같은 식)
  -- ⓒ2 크레딧부터(8-e · 판정 5)
  v_credit   numeric := 0;
  v_ca       public.so_credit_alloc%rowtype;
  v_cq       numeric;  v_cup numeric;                                                   -- svc-1c: 비용 줄의 수량 · 단가(so_charge · 서비스 줄)
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
  if v_cnt > 1 and exists (select 1 from public.so s where s.id = any(p_so_ids) and s.channel = 'service') then                    -- svc-1b 판정 590(대화 Claude 결정 · 늘 따로): 서비스 오더 하나 = 인보이스 한 장 — 물건 오더와도 · 다른 서비스 오더와도 안 묶는다
    select string_agg(s.so_number, ', ' order by s.so_number) into v_bad from public.so s where s.id = any(p_so_ids) and s.channel = 'service';
    raise exception 'A service order is invoiced on its own (one service order, one invoice) — take % out of this batch — nothing was saved', v_bad;
  end if;

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
    v_rule_id := public.so_invoice_rule_pick(v_so, v_on);                             -- doc-1b2: 세율 고르기 한 곳(미리 보기 so_invoice_preview 와 같은 함수)
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
      select c.qty, c.unit_price into v_cq, v_cup from public.so_charge c where c.id = nullif(e->>'charge_id', '')::uuid;                           -- svc-1c 판정 590 · 596: 수량 × 단가 줄(서비스)이면 인보이스 줄에 수량 · 단가를 싣는다
      if v_cq is null or (e->>'amount')::numeric <> round(v_cq * v_cup, 2) then v_cq := null; v_cup := null; end if;                                  -- 금액이 수량 × 단가와 다르면(마무리 화면이 금액을 고친 운임) 금액만 — CHECK so_invoice_line_charge_qty_ck 와 같은 식
      insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_charge_id, description, qty, unit_price, amount, tax_amount, account_id, account_code, updated_by)
      values (v_inv.id, v_io.id, v_ln, 'charge', (e->>'charge_id')::uuid, e->>'name' || coalesce(' — ' || (e->>'description'), ''), v_cq, v_cup, (e->>'amount')::numeric, (e->>'tax')::numeric,   -- svc-1c: qty · unit_price
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

  -- doc-1b2: ⓑ2 ① 선수금 · ⓒ2 ② 크레딧 · ⓑ2 ③ 받아 둔 돈 — 셈은 so_invoice_apply_plan 하나(미리 보기 so_invoice_preview 와 같은 식 · 쓰지 않는다) · 여기서는 그 계획대로 붙인다(한도 검사는 alloc_add 가 그대로)
  v_plan := public.so_invoice_apply_plan(v_inv.bill_to_customer_id, v_inv.currency_id, p_so_ids, v_total);
  for e in select x from jsonb_array_elements(v_plan->'steps') x loop
    if e->>'step' = 'auto_credit' then
      v_ca := public.so_credit_alloc_add((e->>'credit_id')::uuid, v_inv.id, (e->>'amount')::numeric, 'auto', p_staff);
      v_credit := v_credit + v_ca.amount;
      v_applied := v_applied || jsonb_build_object('alloc_id', v_ca.id, 'credit_id', e->'credit_id', 'credit_number', e->>'credit_number', 'source', 'auto_credit', 'amount', v_ca.amount, 'issued_on', e->'issued_on');
    else
      v_a := public.so_payment_alloc_add((e->>'payment_id')::uuid, v_inv.id, (e->>'amount')::numeric, e->>'step', p_staff);
      if e->>'step' = 'auto_deposit' then v_deposit := v_deposit + v_a.amount; else v_balance := v_balance + v_a.amount; end if;
      v_applied := v_applied || jsonb_build_object('alloc_id', v_a.id, 'payment_id', e->'payment_id', 'source', e->>'step', 'amount', v_a.amount, 'paid_on', e->'paid_on', 'method', e->>'method', 'reference', e->'reference');
    end if;
  end loop;

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
$function$;

-- ═══ 착지 — CHECK 둘 · 재발행 md5 · 옛 행 무변 · 다른 인보이스 · 크레딧 · 문서 창구 무변 ═══
do $$
declare
  v_bad text := '';
  v_n   int;
  b     record;
  v_exp jsonb := '{"so_invoice_issue": "7a03148223048349d2b9d461969ca3f6"}'::jsonb;
  k     text;
begin
  select * into b from svc1c_before;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.so_invoice_line'::regclass and conname = 'so_invoice_line_qty_ck') !~ 'charge' then v_bad := v_bad || ' qty_ck'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.so_invoice_line'::regclass and conname = 'so_invoice_line_charge_qty_ck') !~ 'round' then v_bad := v_bad || ' charge_qty_ck'; end if;
  if (select string_agg(conname || ':' || pg_get_constraintdef(oid), ' ' order by conname) from pg_constraint where conrelid = 'public.so_invoice_line'::regclass and contype = 'c' and conname not in ('so_invoice_line_qty_ck', 'so_invoice_line_charge_qty_ck')) is distinct from b.other_checks then v_bad := v_bad || ' other_checks'; end if;
  if (select count(*) from public.so_invoice_line where kind = 'charge') <> b.n_charge_lines or (select count(*) from public.so_invoice_line where kind = 'charge' and (qty is not null or unit_price is not null)) <> b.n_charge_qty then v_bad := v_bad || ' old_rows'; end if;
  for k in select jsonb_object_keys(v_exp) loop
    select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = k;
    if v_n <> 1 then v_bad := v_bad || format(' %s_overloads_%s', k, v_n); end if;
    if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = k) is distinct from (v_exp->>k) then v_bad := v_bad || ' ' || k || '_body'; end if;
  end loop;
  if (select coalesce(p.proacl::text, '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_invoice_issue') is distinct from b.issue_acl then v_bad := v_bad || ' issue_acl'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname in ('so_invoice_reissue', 'so_invoice_cancel', 'so_invoice_preview', 'so_credit_issue', 'so_credit_prepare', 'doc_data', 'doc_data_invoice', 'doc_data_invoice_fmt', 'doc_data_credit', 'so_tax_preview', 'so_finalize', 'so_service_invoice', 'so_pos_complete', 'so_charge_set')) is distinct from b.others then v_bad := v_bad || ' others_changed'; end if;
  if v_bad <> '' then raise exception 'svc-1c landing check failed:%', v_bad; end if;
end $$;
drop table svc1c_before;
