-- supabase/migrations/20261107143714_so_detail_keys_1.sql — so-detail-keys-1: so_detail 줄 객체에서 주석에 먹힌 키 넷(no_price · free · shipped_total · removed) 되살리기 (2026-11-07 · 지시서 ~/asung/prompts/so-detail-keys-1.md)
-- 증상: SO-20918 등 Fulfilled 오더의 줄 TOTAL 「—」 · 줄 GP · 오더 GP 음수(so.html 은 l.shipped_total 을 읽는데 키가 없어 매출 0 으로 잡힘) · 위 합계 · 인보이스 · QuickBooks 는 맞다
-- 원인: 20261020123910_ln_1(:391 · 0c5886e) 부터 jsonb_build_object 안의 「-- ln-1 판정 546(…)」 주석이 같은 줄의 'no_price', … 'removed', … 를 줄 끝까지 먹었다 · 20261023141448_bgr_1c(:665) 가 그대로 이어받음
-- 몸 = DB prosrc 원본 바이트(md5 9f4e87f639bcef66b663a3cd78906247 · 10967 자 · 106 줄) · 바꾼 것 하나 = 24 행을 'no_price', 앞에서 두 줄로(주석은 'total', … 줄 끝에 남고 네 키는 새 줄 · 들여쓰기 62 = 25 행과 같음 · 주석 끝 공백 하나 지움 → +62 자)
-- 시그니처 · invoker · stable · search_path · comment · acl 그대로(create or replace · drop 없음) · 화면 무변 · 다른 함수 무변
-- ⚠️ jsonb_build_object 안에 「--」 줄 주석을 두지 마라 — 재발행 생성기가 줄을 합치면 뒤 키가 조용히 사라진다(docs-1107 이 정본 · 스킬로 옮긴다)
create or replace function public.so_detail(p_so_id uuid)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_so       public.so%rowtype;
  v_cust     text;
  v_lines    jsonb;
  v_charges  jsonb;
  v_lines_n  int;  v_no_price int;  v_free int;  v_charges_n int;  v_deal_ended int;
  v_lines_total numeric;  v_charges_total numeric;  v_od_amt numeric;
  v_sc_amt numeric := 0;  v_sc_tax numeric := 0;                            -- surcharge-2a — so_tax_preview totals 에서 읽는다(식 한 곳 · basis 를 따라간다)
  v_chd    numeric := 0;                                                     -- fr-1 판정 352: 운임 할인 합 — so_tax_preview totals 에서(식 한 곳)
  v_warn     text[];
  v_tax      jsonb;  v_tw text[];                              -- 세금 ② — so_tax_preview
  v_basis    text;  v_inv jsonb;  v_inv_hist jsonb;  v_removed int;  v_qty_removed numeric;   -- ⓐ2 — 보낸 수량 기준 · 인보이스 · 뺀 몫
  v_bal      jsonb;                                            -- ⓑ2 — 청구처 손님 잔액(그 통화 행)
  v_rule     record;  v_rule_j jsonb;                          -- dsc-3a 판정 311 — manual 인데 규칙 쪽이 더 크면 경고
  v_cp       jsonb;                                            -- dsc-3b 판정 329 — 붙은 쿠폰
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found';
  end if;
  select c.name into v_cust from public.customer c where c.id = v_so.customer_id;

  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('manual', public.so_line_manual(l), 'price_set_by_name', (select s.name from public.ims_staff s where s.id = l.price_set_by), 'total', public.so_line_total(l),   -- ln-1 판정 546(price_set_by · price_set_at 은 to_jsonb(l) 에)
                                                              'no_price', l.unit_price is null, 'free', l.free_reason is not null, 'shipped_total', round(l.qty_shipped * l.unit_price, 2), 'removed', l.qty_removed > 0,
                                                              'surcharge_unit', public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), 'surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_ordered), 'shipped_surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_shipped),   -- surcharge-2a(묶음 1 · 2 · total · shipped_total 과 같은 수량)
                                                              'qty_credited', (select coalesce(sum(cl.qty_returned), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_line_id = l.id and c.status = 'issued'),   -- ⓒ2
                                                              'deal_ended', l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date),
                                                              'is_combo', exists (select 1 from public.so_line c where c.combo_line_id = l.id),                                                           -- asm-2a(묶음 2 · 5): 콤보 줄 · 구성품 줄(combo_line_id · combo_qty 는 to_jsonb(l) 에 있다)
                                                              'bgrade_bin', (select rb.name from public.ref_bin rb where rb.id = l.bgrade_bin_id), 'is_bgrade_line', l.bgrade_bin_id is not null,   -- bgr-1c 판정 634 · 635: POS · so 화면의 B-grade 표시
                                                              'combo_sku', (select c.sku from public.so_line c where c.id = l.combo_line_id)) order by l.line_no), '[]'::jsonb),
         count(*) filter (where l.combo_line_id is null), count(*) filter (where l.unit_price is null), count(*) filter (where l.free_reason is not null), public.so_lines_total(p_so_id),   -- dsc-3a 판정 310: 기준 금액 식 한 곳
         count(*) filter (where l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)),
         count(*) filter (where l.qty_removed > 0), coalesce(sum(l.qty_removed), 0)
    into v_lines, v_lines_n, v_no_price, v_free, v_lines_total, v_deal_ended, v_removed, v_qty_removed
  from public.so_line l where l.so_id = p_so_id;

  select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object('discount', public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount), 'net', c.amount - public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount)) order by c.line_no), '[]'::jsonb), count(*), coalesce(sum(c.amount), 0)   -- fr-1: 할인액 · 순 운임(식 한 곳)
    into v_charges, v_charges_n, v_charges_total
  from public.so_charge c where c.so_id = p_so_id;

  -- 오더 전체 할인(D6) — 제품 줄 합계에 한 번 · round 2(SO-10842 실물) · 운임은 기준에 없다
  -- od-1 판정 542 ~ 544: 오더 할인 금액은 so_tax_preview 가 센 값(손으로 정한 줄을 뺀 바탕 · 식 한 곳) — 아래 v_tax 뒤에서 읽는다(ordered · shipped 둘 다)

  -- 세금(세금 ② · 판정 8) — 오더에 고른 규칙(manual|ship_to)으로 줄마다 · 규칙 없으면 tax null + 경고 tax_rule_missing
  v_basis := case when v_so.status in ('shipped', 'fulfilled') then 'shipped' else 'ordered' end;   -- ⓐ2: 나간 뒤에는 보낸 수량이 금액(뺀 몫·pick_short 제외 · 인보이스가 정본 8-c) · ⓑ2: invoiced 값 없음(판정 1)
  v_tax := public.so_tax_preview(p_so_id, null, null, v_basis);
  v_od_amt := -coalesce((v_tax->'totals'->>'order_discount_amount')::numeric, 0);                                                                       -- od-1: 양수(so_detail 의 모양) · 식은 so_tax_preview 한 곳
  v_sc_amt := coalesce((v_tax->'totals'->>'surcharge_amount')::numeric, 0);  v_sc_tax := coalesce((v_tax->'totals'->>'surcharge_tax')::numeric, 0);   -- surcharge-2a(묶음 3 · 4)
  v_chd := coalesce((v_tax->'totals'->>'charges_discount_amount')::numeric, 0);                                                                          -- fr-1 판정 352(세금은 v_tax 의 tax 가 이미 뺐다 · 354)
  if v_basis = 'shipped' then
    v_lines_total := (v_tax->'totals'->>'lines_amount')::numeric;
  end if;
  select jsonb_build_object('invoice_id', i.id, 'invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'due_on', i.due_on, 'total', i.total,
                            'deposit_applied', i.deposit_applied, 'credit_applied', i.credit_applied, 'balance_forward', i.balance_forward, 'amount_due', i.amount_due,
                            'remaining', public.so_invoice_remaining(i.id), 'paid', i.total - public.so_invoice_remaining(i.id),
                            'credits', (select coalesce(jsonb_agg(jsonb_build_object('credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'total', c.total) order by c.credit_number), '[]'::jsonb) from public.so_credit c where c.invoice_id = i.id),
                            'credited_total', (select coalesce(sum(c.total), 0) from public.so_credit c where c.invoice_id = i.id and c.status = 'issued')) into v_inv
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id and o.cancelled_at is null;
  select coalesce(jsonb_agg(jsonb_build_object('invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'cancelled_at', i.cancelled_at) order by i.invoice_number), '[]'::jsonb) into v_inv_hist
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id;
  select to_jsonb(b) into v_bal from public.so_customer_balance(coalesce(v_so.bill_to_customer_id, v_so.customer_id)) b where b.currency_id = v_so.currency_id;   -- ⓑ2: 청구처의 그 통화 잔액(받아 둔 돈 · 예약 · available · 미수)

  v_warn := public.so_tier_warnings(v_so);
  if v_so.tax_rule_id is null then v_warn := array_append(v_warn, 'tax_rule_missing'); end if;
  if v_removed > 0 then v_warn := array_append(v_warn, 'lines_removed'); end if;
  select array_agg(t.v) into v_tw from jsonb_array_elements_text(coalesce(v_tax->'warnings', '[]'::jsonb)) as t(v);
  v_warn := v_warn || coalesce(v_tw, '{}');
  if v_lines_n = 0    then v_warn := array_append(v_warn, 'no_lines'); end if;
  if v_no_price > 0   then v_warn := array_append(v_warn, 'lines_without_price'); end if;
  if v_deal_ended > 0 then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  if v_so.status = 'draft' and v_so.order_discount_source = 'manual' then                                          -- dsc-3a 판정 282 · 311: manual(0 포함)은 그대로 + 규칙 쪽이 더 크면 경고
    select * into v_rule from public.so_order_discount(p_so_id);
    if coalesce(v_rule.pct, 0) > coalesce(v_so.order_discount_pct, 0) then
      v_warn := array_append(v_warn, 'order_discount_rule_now_better');
      v_rule_j := jsonb_build_object('rule_pct', v_rule.pct, 'rule_deal_id', v_rule.deal_id, 'manual_pct', v_so.order_discount_pct);
    end if;
  end if;

  v_cp := public.so_coupon_info(v_so);
  if v_cp is not null and v_cp->>'status' <> 'won' then v_warn := array_append(v_warn, 'coupon_not_used'); end if;   -- dsc-3b 판정 329

  return jsonb_build_object(
    'so', to_jsonb(v_so),
    'customer_name', v_cust,
    'lines', v_lines,
    'charges', v_charges,
    'totals', jsonb_build_object('basis', v_basis, 'lines', v_lines_n, 'combo_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and exists (select 1 from public.so_line c where c.combo_line_id = x.id)),
                                 'component_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and x.combo_line_id is not null), 'lines_removed', v_removed, 'qty_removed', v_qty_removed, 'lines_total', v_lines_total, 'lines_without_price', v_no_price, 'free_lines', v_free,
                                 'order_discount_pct', v_so.order_discount_pct, 'order_discount_source', v_so.order_discount_source, 'order_discount_deal_id', v_so.order_discount_deal_id,
                                 'order_discount_amount', v_od_amt, 'lines_after_discount', v_lines_total - v_od_amt, 'discount_basis_amount', coalesce((v_tax->'totals'->>'discount_basis_amount')::numeric, 0),   -- od-1
                                 'charges', v_charges_n, 'charges_total', v_charges_total,
                                 'charges_discount_amount', v_chd, 'charges_net_total', v_charges_total - v_chd,                            -- fr-1 판정 352: charges_total 은 정가 합 그대로 · 새 열쇠
                                 'surcharge_amount', v_sc_amt, 'surcharge_tax', v_sc_tax,                                        -- surcharge-2a — 물건값 · 오더 할인 기준 밖(묶음 3)
                                 'order_total', v_lines_total - v_od_amt + v_charges_total - v_chd + v_sc_amt,                                    -- fr-1: 운임 할인을 뺀다
                                 'tax_rule', v_so.tax_rule, 'tax_rule_source', v_tax->>'source', 'tax', v_tax->'totals'->'tax',
                                 'order_total_with_tax', case when v_tax->'totals'->>'tax' is null then null else v_lines_total - v_od_amt + v_charges_total - v_chd + v_sc_amt + (v_tax->'totals'->>'tax')::numeric end),   -- fr-1
    'tax', v_tax,
    'invoice', v_inv,
    'invoice_history', v_inv_hist,
    'customer_balance', v_bal,
    'order_discount_rule', v_rule_j,
    'coupon', v_cp,
    'warnings', to_jsonb(v_warn));
end;
$function$;
-- ═══ 착지 ═══
do $$
declare v_bad text := ''; v_src text; v_n int;
begin
  select count(*) into v_n from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_detail';
  if v_n <> 1 then v_bad := v_bad || ' overloads=' || v_n; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_detail';
  if md5(v_src) <> 'e56a3ce9c77617e72aaccd428d2285f3' then v_bad := v_bad || ' md5=' || left(md5(v_src), 8); end if;
  if length(v_src) <> 11029 then v_bad := v_bad || ' len=' || length(v_src); end if;
  -- 네 키가 주석 줄이 아닌 줄에(「--」 뒤에 오는 'no_price' 등 없음 · 네 키 줄이 제 줄로 있음)
  if exists (select 1 from unnest(string_to_array(v_src, E'\n')) line where line ~ '--.*''(no_price|free|shipped_total|removed)'',') then v_bad := v_bad || ' keys_in_comment'; end if;
  if not exists (select 1 from unnest(string_to_array(v_src, E'\n')) line where line = repeat(' ', 62) || '''no_price'', l.unit_price is null, ''free'', l.free_reason is not null, ''shipped_total'', round(l.qty_shipped * l.unit_price, 2), ''removed'', l.qty_removed > 0,') then v_bad := v_bad || ' keys_line_missing'; end if;
  -- 머리 · 권한 · comment 그대로
  if (select pg_get_function_identity_arguments(oid) || '|' || prosecdef::text || '|' || provolatile::text || '|' || coalesce(proconfig::text, '-') || '|' || coalesce(proacl::text, '-') || '|' || md5(coalesce(obj_description(oid, 'pg_proc'), '')) || '|' || prorettype::regtype::text
        from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_detail')
     <> 'p_so_id uuid|false|s|{"search_path=public, pg_temp"}|{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}|47e068a1d6d690c8bd7347c01401992b|jsonb'
     then v_bad := v_bad || ' head_acl_comment'; end if;
  if v_bad <> '' then raise exception 'so-detail-keys-1 landing check failed:%', v_bad; end if;
end $$;
