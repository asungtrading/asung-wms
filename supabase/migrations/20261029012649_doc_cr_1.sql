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

-- ═══ doc-cr-1 — 인보이스 문서에 「어느 크레딧이 얼마」 목록과 늘 찍는 Balance due (2026-10-28 · 판정 864 · Caleb 「A로 하자」) ═══
--   동료 요청(인보이스 60073 캡처 · PDF 20261028_Payment_Line_Error.pdf): 「크레딧이 얼마 적용되었고 어느 크레딧 노트에서 왔는지 알면 좋겠다 · 토탈 29.06 인데 결제는 28.26 밖에 안 한 것 같아 보인다」
--   실물(테스트 DB 2026-10-28): 60073 = Total 29.06 · 현금 28.26 · CR-01010(60070 에 낸 가격 조정 크레딧 0.80 · 손으로 붙임 · source manual) · 남은 돈 0.00
--     v7 종이는 Payments 28.26 만 보이고 크레딧 줄(credit_applied 는 발행 때 몫이라 "") · Due 줄(528 「0 이면 줄 없음」)이 없다 → 손님은 0.80 이 빈다
--   판정 864: 문서 맨 아래 **Balance due 를 늘 찍는다 — 0 이면 "0.00"**(528 의 「Due 0 이면 줄 없음」 을 이 줄만 바꾼다 · 옛 열쇠 due_amount 는 그대로 "")
--             그 위에 Total · Payments · **Credits**(목록 — 어느 크레딧 노트 · 날짜 · 금액) 를 차례로 — 손님이 위에서 아래로 셈해 맞춘다(29.06 − 28.26 − 0.80 = 0.00) · 기각 B 「Paid in full」 글(숫자 확인을 손님 머리에 맡긴다)
--   새 열쇠(final_invoice · internal_receipt): credits[] = no · number(CR-…) · date(doc_fmt_date · 크레딧 발행일) · reference(원 인보이스 번호 — IMS invoice_number → Cin7 ref_invoice_number · 이 인보이스 자신이면 "") · amount(doc_fmt_money · 붙인 금액)
--                                            totals.credits(목록 합 · doc_fmt_money_nz · 0 이면 "" → 판의 줄이 사라진다)
--   새 열쇠(세 kind): totals.balance_due(doc_fmt_money · 찍는 순간 so_invoice_remaining · ship_ready 는 미리 보기의 남을 몫 · 0 이면 "0.00")
--   목록 조건 = so_invoice_list 의 cred · so_invoice_remaining 과 같다(invoice_id 붙임 · voided_at null · c.status issued) ⇒ 화면 Credited = 문서 Credits · 불변식 total − Σpayments − Σcredits = balance_due(payments 에 선결제 · 받아 둔 돈 몫이 이미 있다 — so_payment_alloc_add 는 kind payment 만)
--   옛 열쇠 무접촉(due_amount · due_label · credit_applied · deposit_applied · balance_forward · paid …) — 쓰는 판 v7 은 바뀌지 않는다 · v8(대화 Claude)이 새 열쇠를 쓰고 발행 때 셋(deposit_applied · credit_applied · balance_forward) 줄을 뺀다(이견 5 · 60019 는 v7 로 Credit applied 4.37 + Previous balance -4.37 이 둘 다 찍힌다)
--   required 무접촉(이견 9) · 음수 balance_due 는 닿을 수 없다(붙임 한도 = so_invoice_remaining · 이견 6) · credit_note · sales_order · ship_ready 의 credits 없음(이견 4)
--   ① doc_data_invoice 재발행 — 원본 DB 바이트(md5 d47d2a5ad8c28449676451176b76b9e8 · ar-2 판) + credits 열쇠 한 덩이(payments 뒤) · 서명 · 권한(postgres · service_role) · comment 없음 그대로
--   ② doc_data_invoice_fmt 재발행 — 원본 DB 바이트(md5 1ee6ba91dd1d4428f6659ff215fab183 · srs-1 판) + 선언 한 줄 · 크레딧 그리기 한 덩이 · return → v_out · 새 열쇠 둘을 얹는 줄 · comment 끝에 doc-cr-1 토막
--   ③ doc_field_catalog 재발행 — 원본 DB 바이트(md5 126e20963f966471979f31282f8691a6 · srs-1 판) + v_credit 선언 · 인보이스 갈래에 allowed · sections 더하는 줄 · comment 끝에 doc-cr-1 토막
--   새 표 · 칸 · 시퀀스 · 창구 0 → 컷오버 날 지우는 순서(cutover-delete) 변화 없음 · volatility(STABLE · STABLE · IMMUTABLE) · 권한 그대로(create or replace) · 검증 supabase/tests/doc_cr_1.sql
--   적용(Caleb · 테스트 Asung-IMS): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261029012649_doc_cr_1.sql && supabase migration repair --status applied 20261029012649 --db-url "$(cat ~/.asung-testdb-url)"

-- ═══ 원본 확인 — 셋 다 있고 md5 가 이 파일이 재발행하는 몸이어야 한다(다르면 멈춘다 · 이미 적용됐으면 멈춘다) ═══
do $$
declare v_ld text; v_fmt text; v_cat text;
begin
  select md5(prosrc) into v_ld  from pg_proc where proname = 'doc_data_invoice'     and pronamespace = 'public'::regnamespace;
  select md5(prosrc) into v_fmt from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace;
  select md5(prosrc) into v_cat from pg_proc where proname = 'doc_field_catalog'    and pronamespace = 'public'::regnamespace;
  if v_ld is null or v_fmt is null or v_cat is null then raise exception using errcode = 'IM511', message = 'STOP - doc_data_invoice, doc_data_invoice_fmt or doc_field_catalog is missing - nothing was changed'; end if;
  if (select prosrc from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace) ~ 'balance_due' then
    raise exception using errcode = 'IM511', message = 'STOP - doc-cr-1 is already applied (doc_data_invoice_fmt already makes totals.balance_due) - nothing was changed';
  end if;
  if v_ld <> 'd47d2a5ad8c28449676451176b76b9e8' or v_fmt <> '1ee6ba91dd1d4428f6659ff215fab183' or v_cat <> '126e20963f966471979f31282f8691a6' then
    raise exception using errcode = 'IM511', message = format('STOP - doc_data_invoice md5 %s / doc_data_invoice_fmt md5 %s / doc_field_catalog md5 %s are not the ar-2 / srs-1 bodies (d47d2a5a / 1ee6ba91 / 126e2096) this file re-issues - nothing was changed', left(v_ld, 8), left(v_fmt, 8), left(v_cat, 8));
  end if;
end $$;

-- ═══ ① doc_data_invoice 재발행 — 원본 DB 바이트(md5 d47d2a5ad8c28449676451176b76b9e8) + credits 한 덩이 · 서명 · 권한 그대로(create or replace) ═══
CREATE OR REPLACE FUNCTION public.doc_data_invoice(p_kind text, p_invoice_id uuid, p_cfg jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_inv public.so_invoice%rowtype;
  v_n   jsonb;
begin
  select * into v_inv from public.so_invoice i where i.id = p_invoice_id;
  if v_inv.id is null then raise exception 'Invoice not found'; end if;
  if v_inv.kind = 'opening' then raise exception 'Invoice % was carried forward from the previous system — the original is in QuickBooks. It cannot be printed or mailed from IMS', v_inv.invoice_number; end if;   -- ar-2 판정 785: doc_data 한 곳(화면 인쇄 · 미리 보기 · 서버 PDF · 메일 자리표 전부)
  v_n := jsonb_build_object(
    'header', jsonb_build_object('number', v_inv.invoice_number, 'issued_on', v_inv.issued_on, 'due_on', v_inv.due_on, 'payment_term_name', v_inv.payment_term_name, 'currency_code', v_inv.currency_code, 'memo', v_inv.note,
                                 'bill_to_customer_id', v_inv.bill_to_customer_id,
                                 'bill_to', jsonb_build_object('name', v_inv.bill_to_name, 'line1', v_inv.bill_to_line1, 'line2', v_inv.bill_to_line2, 'city', v_inv.bill_to_city, 'state_province', v_inv.bill_to_state_province, 'postal_code', v_inv.bill_to_postal_code, 'country', v_inv.bill_to_country)),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object(
                 'so_number', o.so_number, 'reference', s.ref, 'carrier', s.carrier, 'tracking', s.tracking_number, 'tax_rule', o.tax_rule, 'order_discount_pct', o.order_discount_pct,
                 'ship_to', jsonb_build_object('company', o.ship_to_company, 'contact', o.ship_to_contact, 'phone', o.ship_to_phone, 'line1', o.ship_to_line1, 'line2', o.ship_to_line2, 'city', o.ship_to_city, 'state_province', o.ship_to_state_province, 'postal_code', o.ship_to_postal_code, 'country', o.ship_to_country),
                 'lines', (select coalesce(jsonb_agg(jsonb_build_object('product_id', sl.product_id, 'sku', l.sku, 'description', l.description, 'comment', sl.comments, 'unit', l.unit, 'qty', l.qty, 'list_price', l.list_price, 'discount_pct', l.discount_pct,
                                                                        'unit_price', l.unit_price, 'amount', l.amount, 'tax_amount', l.tax_amount, 'is_free', sl.free_reason is not null, 'no_price', l.unit_price is null, 'manual', coalesce(public.so_line_manual(sl), false), 'final_sale', coalesce(sl.bgrade_bin_id is not null, false)) order by l.line_no), '[]'::jsonb)
                           from public.so_invoice_line l left join public.so_line sl on sl.id = l.so_line_id where l.invoice_order_id = o.id and l.kind = 'product')) order by o.so_number), '[]'::jsonb)
               from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id),
    'charges', (select coalesce(jsonb_agg(jsonb_build_object('so_number', o.so_number, 'kind', l.kind, 'account_code', l.account_code, 'description', l.description, 'comment', case when l.kind = 'charge' then c.description end,
                                                             'qty', l.qty, 'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'amount', l.amount, 'tax_amount', l.tax_amount) order by o.so_number, l.line_no), '[]'::jsonb)
                from public.so_invoice_line l join public.so_invoice_order o on o.id = l.invoice_order_id left join public.so_charge c on c.id = l.so_charge_id
                where l.invoice_id = v_inv.id and l.kind <> 'product'),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('reference', p.reference, 'paid_on', p.paid_on, 'method', p.method, 'amount', a.amount) order by p.paid_on, p.created_at, a.created_at), '[]'::jsonb)
                 from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
                 where a.invoice_id = v_inv.id and a.voided_at is null and p.status = 'active' and p.kind = 'payment'),
    'credits', (select coalesce(jsonb_agg(jsonb_build_object('credit_number', c.credit_number, 'issued_on', c.issued_on, 'amount', a.amount,
                                                             'reference', case when c.invoice_id = v_inv.id then null else coalesce((select oi.invoice_number from public.so_invoice oi where oi.id = c.invoice_id), c.ref_invoice_number) end)
                                          order by c.issued_on, c.credit_number, a.created_at), '[]'::jsonb)
                from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id
                where a.invoice_id = v_inv.id and a.voided_at is null and c.status = 'issued'),                                                                           -- doc-cr-1 판정 864: 이 인보이스에 걸린 살아 있는 크레딧(so_invoice_list cred · so_invoice_remaining 과 같은 조건) · reference = 원 인보이스 번호(IMS invoice_number → Cin7 ref_invoice_number) · 자기 자신이면 null
    'totals', jsonb_build_object('order_discount', v_inv.order_discount_amount, 'surcharge', v_inv.surcharge_amount, 'taxable', v_inv.taxable_amount, 'tax', v_inv.tax_amount, 'total', v_inv.total,
                                 'deposit_applied', v_inv.deposit_applied, 'credit_applied', v_inv.credit_applied, 'balance_forward', v_inv.balance_forward,
                                 'paid', (select coalesce(sum(a.amount), 0) from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id where a.invoice_id = v_inv.id and a.voided_at is null and p.status = 'active' and p.kind = 'payment'),
                                 'amount_due', v_inv.amount_due,
                                 'remaining', public.so_invoice_remaining(v_inv.id)));                                                                                     -- doc-1c 판정 528 ①: 찍는 순간 지금 남은 금액(발행 때 종이 값 amount_due 는 doc-2 의 남긴 PDF 가 지킨다)
  return public.doc_data_invoice_fmt(p_kind, p_cfg, v_n);
end;
$function$;

-- ═══ ② doc_data_invoice_fmt 재발행 — 원본 DB 바이트(md5 1ee6ba91dd1d4428f6659ff215fab183) + 더한 줄(줄 끝 「doc-cr-1」) · 서명 · 권한 · comment 그대로 + 토막 ═══
CREATE OR REPLACE FUNCTION public.doc_data_invoice_fmt(p_kind text, p_cfg jsonb, p_n jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_fmt  text := p_cfg->>'date_format';
  v_disp text := coalesce(p_cfg->>'unit_display', 'both');
  v_h    jsonb := p_n->'header';  v_t jsonb := p_n->'totals';
  v_orders jsonb;  v_charges jsonb;  v_payments jsonb;  v_inv jsonb;
  v_credits jsonb := '[]'::jsonb;  v_cr_amt numeric := 0;  v_out jsonb;                                                                                                   -- doc-cr-1 판정 864
  v_lines_amt numeric;  v_lines_tax numeric;  v_qty numeric;  v_chg_amt numeric;  v_chg_tax numeric;  v_chd numeric;
  v_due  numeric := coalesce((v_t->>'remaining')::numeric, (v_t->>'amount_due')::numeric);                                      -- doc-1c 판정 528 ①: 표에서 온 문서는 지금 남은 금액 · ship_ready(미리 보기)는 셈한 남을 몫
begin
  -- 제품 줄 — 오더 순(orders 배열 순 = so_number 순) · 줄 번호는 문서 안에서 1, 2, 3 … 이어서
  with ln as (
    select o.ord as o_ord, l.ord as l_ord, o.o->>'order_discount_pct' as od_pct, l.l, row_number() over (order by o.ord, l.ord) as no
    from jsonb_array_elements(p_n->'orders') with ordinality o(o, ord) cross join lateral jsonb_array_elements(o.o->'lines') with ordinality l(l, ord))
  select coalesce(jsonb_agg(jsonb_build_object(
           'so_number', coalesce(o.o->>'so_number', ''), 'reference', coalesce(o.o->>'reference', ''), 'carrier', coalesce(o.o->>'carrier', ''), 'tracking', coalesce(o.o->>'tracking', ''), 'tax_rule', coalesce(o.o->>'tax_rule', ''),
           'ship_to_repeat', exists (select 1 from jsonb_array_elements(p_n->'orders') with ordinality q(q, qord) where q.qord < o.ord and (select string_agg(lower(btrim(coalesce(q.q->'ship_to'->>k, ''))), '|' order by k) from unnest(array['company', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country']) k) = (select string_agg(lower(btrim(coalesce(o.o->'ship_to'->>k, ''))), '|' order by k) from unnest(array['company', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country']) k)),   -- srs-1 판정 788: 앞 오더에 같은 배송지(이름 · 주소 줄 · 도시 · 주 · 우편번호 · 나라 · lower(btrim))가 있으면 true — 판이 {{^ship_to_repeat}} 로 한 번만 그린다 · 첫 오더는 false
           'ship_to', (select jsonb_object_agg(k, coalesce(o.o->'ship_to'->>k, '')) from unnest(array['company', 'contact', 'phone', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country']) k),
           'lines', (select coalesce(jsonb_agg((jsonb_build_object('no', ln.no::text, 'upc', public.doc_upc(nullif(ln.l->>'product_id', '')::uuid), 'sku', coalesce(ln.l->>'sku', ''), 'description', coalesce(ln.l->>'description', ''), 'comment', coalesce(ln.l->>'comment', ''),
                                                                    'unit', coalesce(ln.l->>'unit', ''), 'qty', public.doc_fmt_qty((ln.l->>'qty')::numeric), 'list_price', public.doc_fmt_money((ln.l->>'list_price')::numeric), 'discount_pct', public.doc_fmt_pct((ln.l->>'discount_pct')::numeric),
                                                                    'amount', public.doc_fmt_money((ln.l->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((ln.l->>'tax_amount')::numeric), 'is_free', coalesce((ln.l->>'is_free')::boolean, false), 'no_price', coalesce((ln.l->>'no_price')::boolean, false), 'final_sale', coalesce((ln.l->>'final_sale')::boolean, false))
                                                || public.doc_unit_prices((ln.l->>'unit_price')::numeric, case when coalesce((ln.l->>'manual')::boolean, false) then null else (ln.od_pct)::numeric end, v_disp)) order by ln.no), '[]'::jsonb)
                     from ln where ln.o_ord = o.ord)) order by o.ord), '[]'::jsonb),
         coalesce((select sum((ln.l->>'amount')::numeric) from ln), 0), coalesce((select sum((ln.l->>'tax_amount')::numeric) from ln), 0), coalesce((select sum((ln.l->>'qty')::numeric) from ln), 0)
    into v_orders, v_lines_amt, v_lines_tax, v_qty
  from jsonb_array_elements(p_n->'orders') with ordinality o(o, ord);
  select coalesce(jsonb_agg(jsonb_build_object('no', c.ord::text, 'so_number', coalesce(c.c->>'so_number', ''), 'code', coalesce(c.c->>'account_code', ''), 'description', coalesce(c.c->>'description', ''), 'comment', coalesce(c.c->>'comment', ''),
                                               'qty', public.doc_fmt_qty((c.c->>'qty')::numeric), 'unit_price', public.doc_fmt_money((c.c->>'unit_price')::numeric), 'discount_pct', public.doc_fmt_pct((c.c->>'discount_pct')::numeric),
                                               'amount', public.doc_fmt_money((c.c->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((c.c->>'tax_amount')::numeric)) order by c.ord), '[]'::jsonb),
         coalesce(sum((c.c->>'amount')::numeric), 0), coalesce(sum((c.c->>'tax_amount')::numeric), 0), coalesce(sum((c.c->>'amount')::numeric) filter (where c.c->>'kind' = 'charge_discount'), 0)
    into v_charges, v_chg_amt, v_chg_tax, v_chd
  from jsonb_array_elements(p_n->'charges') with ordinality c(c, ord);
  select coalesce(jsonb_agg(jsonb_build_object('no', p.ord::text, 'reference', coalesce(p.p->>'reference', ''), 'date', public.doc_fmt_date((p.p->>'paid_on')::date, v_fmt), 'method', public.doc_method_label(p.p->>'method'), 'amount', public.doc_fmt_money((p.p->>'amount')::numeric)) order by p.ord), '[]'::jsonb)
    into v_payments from jsonb_array_elements(p_n->'payments') with ordinality p(p, ord);
  if p_kind <> 'ship_ready' then   -- doc-cr-1 판정 864: 크레딧 목록(번호 · 발행일 · 원 인보이스 번호 · 붙인 금액) + 합 — final_invoice · internal_receipt 만(ship_ready 는 발행 전 · 붙임 없음) · 순서는 적재(issued_on → credit_number)
    select coalesce(jsonb_agg(jsonb_build_object('no', c.ord::text, 'number', coalesce(c.c->>'credit_number', ''), 'date', public.doc_fmt_date((c.c->>'issued_on')::date, v_fmt), 'reference', coalesce(c.c->>'reference', ''), 'amount', public.doc_fmt_money((c.c->>'amount')::numeric)) order by c.ord), '[]'::jsonb),
           coalesce(sum((c.c->>'amount')::numeric), 0)
      into v_credits, v_cr_amt from jsonb_array_elements(coalesce(p_n->'credits', '[]'::jsonb)) with ordinality c(c, ord);
  end if;
  v_inv := jsonb_build_object('number', coalesce(v_h->>'number', ''), 'date', public.doc_fmt_date((v_h->>'issued_on')::date, v_fmt), 'due_date', public.doc_fmt_date((v_h->>'due_on')::date, v_fmt), 'terms', coalesce(v_h->>'payment_term_name', ''),
                              'currency', coalesce(v_h->>'currency_code', ''), 'memo', coalesce(v_h->>'memo', ''), 'total_qty', public.doc_fmt_qty(v_qty));
  v_inv := v_inv || jsonb_build_object('so_numbers', coalesce((select string_agg(o.o->>'so_number', ', ' order by o.ord) from jsonb_array_elements(p_n->'orders') with ordinality o(o, ord) where nullif(btrim(o.o->>'so_number'), '') is not null), ''));   -- srs-1 판정 787: 문서의 오더 SO 번호를 orders 순서대로 「, 」 로 이은 글(빈 번호 건너뜀) — 메일 제목 {{invoice.so_numbers}} 재료 · 세 kind 공통
  if p_kind = 'ship_ready' then
    v_inv := (v_inv - 'number') || jsonb_build_object('calc_at', public.doc_fmt_date(public.ims_today(), v_fmt) || ' ' || to_char(coalesce((p_n->>'calc_at')::timestamptz, now()) at time zone 'America/Toronto', 'HH24:MI'));
  end if;
  v_out := jsonb_build_object(   -- doc-cr-1: return → v_out(아래에서 새 열쇠를 얹는다) · 옛 열쇠 전부 무접촉
    'invoice', v_inv, 'orders', v_orders, 'charges', v_charges, 'payments', v_payments,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money(v_lines_amt), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money(v_lines_amt + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'order_discount', public.doc_fmt_money((v_t->>'order_discount')::numeric), 'surcharge', public.doc_fmt_money((v_t->>'surcharge')::numeric), 'charges_discount', public.doc_fmt_money(v_chd),
                                 'before_tax', public.doc_fmt_money((v_t->>'taxable')::numeric), 'tax', public.doc_fmt_money((v_t->>'tax')::numeric), 'total', public.doc_fmt_money((v_t->>'total')::numeric),
                                 'deposit_applied', public.doc_fmt_money_nz((v_t->>'deposit_applied')::numeric), 'credit_applied', public.doc_fmt_money_nz((v_t->>'credit_applied')::numeric), 'balance_forward', public.doc_fmt_money_nz((v_t->>'balance_forward')::numeric),   -- doc-1c 판정 528 ③: 0 이면 빈칸
                                 'paid', public.doc_fmt_money_nz((v_t->>'paid')::numeric), 'due_label', case when v_due > 0 then 'Due' when v_due < 0 then 'Credit' else '' end, 'due_amount', public.doc_fmt_money_nz(v_due)))   -- doc-1c 판정 528 ②: 남은 돈 0 이면 둘 다 빈칸(판이 {{#totals.due_amount}} 로 숨긴다)
    || public.doc_data_common(p_kind, p_cfg, (v_h->'bill_to') || public.doc_contact(nullif(v_h->>'bill_to_customer_id', '')::uuid));
  v_out := jsonb_set(v_out, '{totals,balance_due}', to_jsonb(public.doc_fmt_money(v_due)));                                                                                -- doc-cr-1 판정 864: 늘 찍는 남은 금액 — 0 이면 "0.00"(528 의 「0 이면 줄 없음」 을 이 열쇠만 바꾼다 · due_amount 는 그대로) · 세 kind
  if p_kind <> 'ship_ready' then v_out := jsonb_set(v_out, '{totals,credits}', to_jsonb(public.doc_fmt_money_nz(v_cr_amt))) || jsonb_build_object('credits', v_credits); end if;   -- doc-cr-1: Credits 합(0 이면 빈칸 → 판의 줄이 사라진다) · 목록
  return v_out;
end;
$function$;

-- ═══ ③ doc_field_catalog 재발행 — 원본 DB 바이트(md5 126e20963f966471979f31282f8691a6) + 더한 줄(줄 끝 「doc-cr-1」) · 서명 · 권한 · comment 그대로 + 토막 ═══
CREATE OR REPLACE FUNCTION public.doc_field_catalog(p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_common   text[] := array['company.name', 'company.hst', 'company.website', 'company.logo_url', 'company.terms',
                             'branches.code', 'branches.label', 'branches.line1', 'branches.line2', 'branches.phone', 'branches.email',
                             'doc.kind', 'doc.title', 'doc.printed_at', 'show.upc', 'show.comment', 'show.charge_code',
                             'bill_to.name', 'bill_to.line1', 'bill_to.line2', 'bill_to.city', 'bill_to.state_province', 'bill_to.postal_code', 'bill_to.country', 'bill_to.email', 'bill_to.phone'];
  v_ship     text[] := array['company', 'contact', 'phone', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country'];
  v_line     text[] := array['no', 'upc', 'sku', 'description', 'comment', 'unit', 'qty', 'list_price', 'discount_pct', 'unit_price', 'net_unit_price', 'amount', 'tax_amount', 'is_free', 'no_price'];
  v_charge   text[] := array['no', 'so_number', 'code', 'description', 'comment', 'qty', 'unit_price', 'discount_pct', 'amount', 'tax_amount'];
  v_money    text[] := array['no', 'reference', 'date', 'method', 'amount'];
  v_credit   text[] := array['no', 'number', 'date', 'reference', 'amount'];   -- doc-cr-1 판정 864: 크레딧 목록 한 줄(번호 · 발행일 · 원 인보이스 번호 · 붙인 금액)
  v_tot_inv  text[] := array['lines_before_tax', 'lines_tax', 'lines_total', 'charges_before_tax', 'charges_tax', 'charges_total', 'order_discount', 'surcharge', 'charges_discount',
                             'before_tax', 'tax', 'total', 'deposit_applied', 'credit_applied', 'balance_forward', 'paid', 'due_label', 'due_amount'];
  v_tot_cr   text[] := array['lines_before_tax', 'lines_tax', 'lines_total', 'charges_before_tax', 'charges_tax', 'charges_total', 'restocking_fee', 'before_tax', 'tax', 'total', 'applied', 'remaining'];
  v_tot_so   text[] := array['lines_before_tax', 'lines_tax', 'lines_total', 'charges_before_tax', 'charges_tax', 'charges_total', 'order_discount', 'surcharge', 'charges_discount',
                             'before_tax', 'tax', 'total', 'prepaid', 'due_amount'];
  v_allowed  text[];
  v_sections text[] := array['branches'];
  v_required text[];
  v_x text;
begin
  if p_kind not in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready', 'internal_receipt') then
    raise exception 'Unknown document kind % — final_invoice, credit_note, sales_order, ship_ready or internal_receipt', coalesce(p_kind, '(null)');
  end if;
  v_allowed := v_common;
  if p_kind in ('final_invoice', 'ship_ready', 'internal_receipt') then
    v_allowed := v_allowed || array['invoice.date', 'invoice.due_date', 'invoice.terms', 'invoice.currency', 'invoice.memo', 'invoice.total_qty'];
    v_allowed := v_allowed || case when p_kind = 'ship_ready' then array['invoice.calc_at'] else array['invoice.number'] end;
    v_allowed := v_allowed || array['invoice.so_numbers', 'orders.ship_to_repeat'];   -- srs-1 판정 787: 오더 SO 번호를 「, 」 로 이은 글(메일 제목 자리표) · 판정 788: 앞 오더와 같은 배송지면 true(불리언 · {{^ship_to_repeat}}) — final_invoice · ship_ready · internal_receipt
    v_allowed := v_allowed || array['orders.so_number', 'orders.reference', 'orders.carrier', 'orders.tracking', 'orders.tax_rule'];
    foreach v_x in array v_ship   loop v_allowed := v_allowed || ('orders.ship_to.' || v_x); end loop;
    foreach v_x in array v_line   loop v_allowed := v_allowed || ('orders.lines.' || v_x); end loop;
    foreach v_x in array v_charge loop v_allowed := v_allowed || ('charges.' || v_x); end loop;
    foreach v_x in array v_money  loop v_allowed := v_allowed || ('payments.' || v_x); end loop;
    foreach v_x in array v_tot_inv loop v_allowed := v_allowed || ('totals.' || v_x); end loop;
    v_sections := v_sections || array['orders', 'orders.lines', 'charges', 'payments'];
    v_allowed := v_allowed || 'totals.balance_due'::text;   -- doc-cr-1 판정 864: 늘 찍는 남은 금액(0 이면 "0.00") — 세 kind · required 는 무접촉(옛 판이 다시 Check 돼도 통과)
    if p_kind <> 'ship_ready' then   -- doc-cr-1 판정 864: 크레딧 목록 + 합 — final_invoice · internal_receipt(ship_ready 는 발행 전이라 붙임이 없다)
      foreach v_x in array v_credit loop v_allowed := v_allowed || ('credits.' || v_x); end loop;
      v_allowed := v_allowed || 'totals.credits'::text;
      v_sections := v_sections || 'credits'::text;
    end if;
    if p_kind = 'final_invoice' then v_allowed := v_allowed || 'orders.lines.final_sale'::text; end if;   -- bgr-1d 판정 640: B급으로 판 줄에 「Final sale」(손님 인보이스 · POS 영수증만 · 불리언)
    v_required := case p_kind when 'final_invoice'    then array['invoice.number', 'orders.lines', 'totals.tax', 'totals.total', 'totals.due_amount']
                              when 'ship_ready'       then array['invoice.calc_at', 'orders.lines', 'totals.tax', 'totals.total', 'totals.due_amount']
                              else                         array['invoice.number', 'invoice.total_qty', 'totals.total', 'totals.due_amount'] end;
  elsif p_kind = 'credit_note' then
    v_allowed := v_allowed || array['credit.number', 'credit.date', 'credit.invoice_number', 'credit.reference', 'credit.reason', 'credit.currency', 'credit.memo'];
    foreach v_x in array v_ship   loop v_allowed := v_allowed || ('ship_to.' || v_x); end loop;
    foreach v_x in array v_line   loop v_allowed := v_allowed || ('lines.' || v_x); end loop;
    foreach v_x in array v_charge loop v_allowed := v_allowed || ('charges.' || v_x); end loop;
    foreach v_x in array v_money  loop v_allowed := v_allowed || ('refunds.' || v_x); end loop;
    foreach v_x in array v_tot_cr loop v_allowed := v_allowed || ('totals.' || v_x); end loop;
    v_sections := v_sections || array['lines', 'charges', 'refunds'];
    v_required := array['credit.number', 'lines', 'totals.tax', 'totals.total'];
  else
    v_allowed := v_allowed || array['so.number', 'so.date', 'so.status', 'so.required_by', 'so.terms', 'so.reference', 'so.currency', 'so.memo'];
    foreach v_x in array v_ship   loop v_allowed := v_allowed || ('ship_to.' || v_x); end loop;
    foreach v_x in array v_line   loop v_allowed := v_allowed || ('lines.' || v_x); end loop;
    foreach v_x in array v_charge loop v_allowed := v_allowed || ('charges.' || v_x); end loop;
    foreach v_x in array v_money  loop v_allowed := v_allowed || ('prepayments.' || v_x); end loop;
    foreach v_x in array v_tot_so loop v_allowed := v_allowed || ('totals.' || v_x); end loop;
    v_sections := v_sections || array['lines', 'charges', 'prepayments'];
    v_required := array['so.number', 'lines', 'totals.tax', 'totals.total'];
  end if;
  return jsonb_build_object('kind', p_kind, 'allowed', to_jsonb(v_allowed), 'sections', to_jsonb(v_sections), 'required', to_jsonb(v_required));
end;
$function$;

comment on function public.doc_data_invoice_fmt(text, jsonb, jsonb) is 'doc-1b2 — 인보이스 꼴 문서(final_invoice · internal_receipt · ship_ready)의 그리기 한 곳: 중립 jsonb(표에서 온 것 · 또는 so_invoice_preview 의 미리 보기) → doc_field_catalog 의 열쇠 · 꼴 · 줄 번호 · 판정 314 단가 칸 · ship_ready 는 invoice.number 대신 invoice.calc_at · [srs-1 판정 787] invoice.so_numbers = 오더 SO 번호를 orders 순서대로 「, 」 로 이은 글(빈 번호 건너뜀 · 메일 제목 자리표) · [판정 788] orders.ship_to_repeat = 앞 오더와 같은 배송지(company · 주소 줄 · city · state_province · postal_code · country · lower(btrim))면 true — 묶음 인보이스가 같은 Ship To 를 한 번만 · [doc-cr-1 판정 864] totals.balance_due = 늘 찍는 남은 금액(0 이면 "0.00" · 세 kind) · final_invoice · internal_receipt 에 credits[](no · number · date · reference · amount) · totals.credits(합 · 0 이면 "") — 옛 열쇠 무접촉';
comment on function public.doc_field_catalog(text) is 'doc-1a ⑥ — 문서 kind 마다 판이 쓸 수 있는 자리표(allowed · 경로 꼴 orders.lines.sku = {{#orders}}{{#lines}}{{sku}}) · 목록 섹션(sections · 스코프를 미는 것 — 그 밖의 자리표도 {{#x}}…{{/x}} 조건으로 쓸 수 있으나 스코프를 밀지 않는다) · 필수(required · 섹션 이름은 섹션으로 써야 한다) · ⭐ doc-1b 데이터 창구는 이 목록과 똑같은 열쇠를 내야 한다(doc-1b 검증이 대조) · doc-0 Q2 와 다른 곳: bill_to · ship_to 에 city · state_province · postal_code · country(IMS 칸이 따로다) · charges.so_number · *.method · 크레딧 · SO 의 totals 는 제 것(deposit · balance_forward 없음) · [srs-1 판정 787 · 788] 인보이스 꼴 세 kind 에 invoice.so_numbers · orders.ship_to_repeat(불리언 · {{^ship_to_repeat}} 조건) · [doc-cr-1 판정 864] 인보이스 꼴 세 kind 에 totals.balance_due · final_invoice · internal_receipt 에 credits 섹션(no · number · date · reference · amount) · totals.credits · required 무접촉';

-- ═══ ④ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_k text; v_n jsonb;
begin
  if (select count(*) from pg_proc where proname = 'doc_data_invoice' and pronamespace = 'public'::regnamespace) <> 1 or (select count(*) from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace) <> 1
     or (select count(*) from pg_proc where proname = 'doc_field_catalog' and pronamespace = 'public'::regnamespace) <> 1 then v_bad := v_bad || ' dup-names'; end if;
  if (select provolatile from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) <> 's' or (select provolatile from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) <> 's'
     or (select provolatile from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) <> 'i' then v_bad := v_bad || ' volatility'; end if;
  if (select prosrc from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) !~ '''credits''' then v_bad := v_bad || ' loader-body'; end if;
  if (select prosrc from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) !~ 'balance_due' or (select prosrc from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) !~ 'so_numbers' then v_bad := v_bad || ' fmt-body'; end if;
  foreach v_k in array array['final_invoice', 'internal_receipt'] loop
    if not ((public.doc_field_catalog(v_k)->'allowed') ?& array['credits.no', 'credits.number', 'credits.date', 'credits.reference', 'credits.amount', 'totals.credits', 'totals.balance_due', 'invoice.so_numbers'])
       or not ((public.doc_field_catalog(v_k)->'sections') ? 'credits') or (public.doc_field_catalog(v_k)->'required') ? 'totals.balance_due' then v_bad := v_bad || ' catalog-' || v_k; end if;
  end loop;
  if not ((public.doc_field_catalog('ship_ready')->'allowed') ? 'totals.balance_due') or (public.doc_field_catalog('ship_ready')->'allowed') ? 'totals.credits' or (public.doc_field_catalog('ship_ready')->'sections') ? 'credits' then v_bad := v_bad || ' catalog-ship_ready'; end if;
  if (public.doc_field_catalog('ship_ready')->'sections') <> '["branches", "orders", "orders.lines", "charges", "payments"]'::jsonb then v_bad := v_bad || ' sections-ship_ready'; end if;
  if (public.doc_field_catalog('final_invoice')->'sections') <> '["branches", "orders", "orders.lines", "charges", "payments", "credits"]'::jsonb then v_bad := v_bad || ' sections-final_invoice'; end if;
  foreach v_k in array array['credit_note', 'sales_order'] loop
    if (public.doc_field_catalog(v_k)->'allowed') ? 'totals.balance_due' or (public.doc_field_catalog(v_k)->'allowed') ? 'totals.credits' or (public.doc_field_catalog(v_k)->'sections') ? 'credits' then v_bad := v_bad || ' catalog-leak-' || v_k; end if;
  end loop;
  -- 그리기 직접(중립 jsonb): 크레딧 둘 → 목록 둘 · 합 · balance_due "0.00" · ship_ready 는 credits 없음 · balance_due 있음
  v_n := public.doc_data_invoice_fmt('final_invoice', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb,
           '{"header":{"number":"1"},"orders":[],"charges":[],"payments":[],"credits":[{"credit_number":"CR-00001","issued_on":"2026-10-28","reference":"60070","amount":0.8},{"credit_number":"CR-00002","issued_on":"2026-10-27","reference":null,"amount":1.2}],"totals":{"total":2,"remaining":0}}'::jsonb);
  if jsonb_array_length(v_n->'credits') <> 2 or (v_n->'credits'->0) <> '{"no":"1","date":"28OCT2026","amount":"0.80","number":"CR-00001","reference":"60070"}'::jsonb or (v_n->'credits'->1->>'reference') <> ''
     or (v_n->'totals'->>'credits') <> '2.00' or (v_n->'totals'->>'balance_due') <> '0.00' or (v_n->'totals'->>'due_amount') <> '' then v_bad := v_bad || ' fmt-credits(' || (v_n->'credits')::text || ' ' || (v_n->'totals'->>'credits') || ' ' || (v_n->'totals'->>'balance_due') || ')'; end if;
  v_n := public.doc_data_invoice_fmt('ship_ready', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{},"orders":[],"charges":[],"payments":[],"totals":{"total":10,"amount_due":4.5}}'::jsonb);
  if v_n ? 'credits' or (v_n->'totals') ? 'credits' or (v_n->'totals'->>'balance_due') <> '4.50' or (v_n->'totals'->>'due_amount') <> '4.50' then v_bad := v_bad || ' fmt-ship_ready'; end if;
  v_n := public.doc_data_invoice_fmt('internal_receipt', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{"number":"1"},"orders":[],"charges":[],"payments":[],"totals":{"total":1,"remaining":1}}'::jsonb);
  if (v_n->'credits') <> '[]'::jsonb or (v_n->'totals'->>'credits') <> '' or (v_n->'totals'->>'balance_due') <> '1.00' then v_bad := v_bad || ' fmt-no-credits'; end if;
  if has_function_privilege('authenticated', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') or has_function_privilege('authenticated', 'public.doc_data_invoice(text, uuid, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.doc_field_catalog(text)', 'execute') or not has_function_privilege('authenticated', 'public.doc_field_catalog(text)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if (public.doc_template_check('final_invoice', '<div>{{#orders}}{{#lines}}{{sku}}{{/lines}}{{/orders}}{{invoice.number}} {{totals.tax}} {{totals.total}} {{totals.due_amount}} {{#credits}}{{no}} {{number}} {{date}} {{#reference}}(Invoice {{reference}}){{/reference}} {{amount}}{{/credits}}{{#totals.credits}}{{totals.credits}}{{/totals.credits}}{{totals.balance_due}}</div>', 'template')->>'ok')::boolean is distinct from true then v_bad := v_bad || ' template-check'; end if;
  if not exists (select 1 from jsonb_array_elements(public.doc_template_check('ship_ready', '<div>{{#credits}}{{number}}{{/credits}}</div>', 'template')->'problems') p where p->>'code' = 'unknown_field') then v_bad := v_bad || ' ship_ready-credits-not-rejected'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM511', message = format('STOP - doc-cr-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
