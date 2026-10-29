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

-- ═══ doc-sr-1 — PROFORMA(ship_ready)에 크레딧 목록 · INVOICE 와 같은 꼴 (2026-10-29 · 판정 874 · Caleb 「1번부터 하자」 · deferred 380 닫음) ═══
--   동료 요청: 「프로포마에서 크레딧이 적용됐는데, 적용된 크레딧 노트가 안 보여. … 프로포마는 적용이 안됐나?」
--   실물(테스트 DB 2026-10-29 · SO-25251 · Ship & invoice → Ship Ready · 운임 30.14): Total 158.50 · Deposit applied 115.72 · Credit applied 13.56 · Previous balance −13.56 · Payments 115.72(표 한 줄 115.72) · Balance due 29.22
--     → 같은 돈이 두 번(Payments 표 = Deposit applied) · 크레딧도 두 번(Credit applied = Previous balance · so_invoice_preview 가 balance_forward = −(credit + balance) 로 싣는다 · 20261020010711:927) · 크레딧 노트 번호는 없다
--   판정 874: ship_ready 를 final_invoice v9 와 같은 꼴로 — Total → Payments → Credits(목록 · 번호 · 날짜 · 원 인보이스 · 금액) → Balance due · 옛 세 줄(Deposit applied · Credit applied · Previous balance)은 판에서 뺀다
--   ⇒ 이 파일은 열쇠만 더한다(옛 열쇠 전부 그대로 — 쓰는 판 ship_ready v5 는 바뀌지 않는다 · 이중 표시는 새 판이 옛 세 줄을 빼는 것으로 끝난다 — 출력 값의 셈은 맞다: 158.50 − 115.72 − 13.56 = 29.22)
--   새 열쇠(ship_ready): credits[] = no · number(CR-…) · date(doc_fmt_date · 크레딧 발행일) · reference(원 인보이스 번호 — IMS invoice_number → Cin7 ref_invoice_number · 없으면 "") · amount(doc_fmt_money · 계획한 금액)
--                      totals.credits(목록 합 · doc_fmt_money_nz · 0 이면 "") — final_invoice · internal_receipt 와 같은 이름 · 같은 뜻 · 같은 꼴
--   원천: ship_ready 는 발행 전이라 붙임(so_credit_alloc)이 없다 — so_invoice_preview 가 doc 에 싣는 plan(so_invoice_apply_plan · steps 의 auto_credit 걸음 · credit_id · credit_number · issued_on · amount)에서 만든다 · reference 는 계획에 없어 fmt 가 so_credit → so_invoice 로 읽는다
--   불변식(장마다): total − Σpayments[] − Σcredits[] = balance_due — payments[] = auto_deposit + auto_balance 걸음(= totals.paid) · Σcredits = plan.credit · balance_due = amount_due = total − deposit − credit − balance(so_invoice_preview)
--   ⚠️ 묶음이 둘 이상(groups[])이면 장마다 apply_plan 이 따로 돌아 같은 크레딧이 두 장에 다 계획된다(미리 보기 ≠ 발행 — 발행은 장마다 붙여 가며 남은 돈이 준다) — 이 파일은 손대지 않는다(이견 · 미룬 항목 후보)
--   ① doc_data_invoice_fmt 재발행 — 원본 DB 바이트(md5 8bfd2523b9484ed1815d965040e6b3ec · doc-cr-1 판) + 선언 한 줄 · 크레딧 원천 갈래(ship_ready = plan · 그 밖 = credits[]) · 얹는 줄의 ship_ready 조건 뺌 · comment 끝에 doc-sr-1 토막
--   ② doc_field_catalog 재발행 — 원본 DB 바이트(md5 f8f5ab5b78fb4d441e81a42a6f837bf7 · doc-cr-1 판) − ship_ready 가드(credits.* · totals.credits · sections credits 가 세 kind) · required 무접촉 · comment 끝에 doc-sr-1 토막
--   final_invoice · internal_receipt · credit_note · sales_order 의 목록 · 출력은 한 글자도 바뀌지 않는다(검증 T4 · T5) · 새 표 · 칸 · 시퀀스 · 창구 · grant 0 · volatility(STABLE · IMMUTABLE) · 권한 그대로(create or replace) · 검증 supabase/tests/doc_sr_1_check.sql
--   적용(Caleb · 테스트 Asung-IMS): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/migrations/20261029220000_doc_sr_1_proforma_credits.sql && supabase migration repair --status applied 20261029220000 --db-url "$(cat ~/.asung-testdb-url)"

-- ═══ 원본 확인 — 둘 다 있고 md5 가 이 파일이 재발행하는 몸이어야 한다(다르면 멈춘다 · 이미 적용됐으면 멈춘다) ═══
do $$
declare v_fmt text; v_cat text;
begin
  select md5(prosrc) into v_fmt from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace;
  select md5(prosrc) into v_cat from pg_proc where proname = 'doc_field_catalog'    and pronamespace = 'public'::regnamespace;
  if v_fmt is null or v_cat is null then raise exception using errcode = 'IM511', message = 'STOP - doc_data_invoice_fmt or doc_field_catalog is missing - nothing was changed'; end if;
  if (select prosrc from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace) ~ 'auto_credit' then
    raise exception using errcode = 'IM511', message = 'STOP - doc-sr-1 is already applied (doc_data_invoice_fmt already reads the credit plan) - nothing was changed';
  end if;
  if v_fmt <> '8bfd2523b9484ed1815d965040e6b3ec' or v_cat <> 'f8f5ab5b78fb4d441e81a42a6f837bf7' then
    raise exception using errcode = 'IM511', message = format('STOP - doc_data_invoice_fmt md5 %s / doc_field_catalog md5 %s are not the doc-cr-1 bodies (8bfd2523 / f8f5ab5b) this file re-issues - nothing was changed', left(v_fmt, 8), left(v_cat, 8));
  end if;
end $$;

-- ═══ ① doc_data_invoice_fmt 재발행 — 원본 DB 바이트(md5 8bfd2523b9484ed1815d965040e6b3ec) + 더한 줄(줄 끝 「doc-sr-1」) · 서명 · 권한 · comment 그대로 + 토막 ═══
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
  v_cr_src  jsonb;                                                                                                                                                      -- doc-sr-1 판정 874: 크레딧 목록의 중립 원천(final_invoice · internal_receipt = 적재의 credits[] · ship_ready = apply_plan 의 auto_credit 걸음)
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
  if p_kind = 'ship_ready' then   -- doc-sr-1 판정 874: ship_ready 는 발행 전이라 붙임(so_credit_alloc)이 없다 — so_invoice_preview 가 실은 apply_plan 의 크레딧 계획(auto_credit 걸음 · credit_id · credit_number · issued_on · amount)을 같은 중립 꼴로 · reference(원 인보이스 번호)는 계획에 없어 so_credit → so_invoice.invoice_number(IMS) → ref_invoice_number(Cin7) 로 읽는다 · 순서는 계획 순(issued_on → created_at)
    select coalesce(jsonb_agg(jsonb_build_object('credit_number', s.s->>'credit_number', 'issued_on', s.s->'issued_on', 'amount', (s.s->>'amount')::numeric,
                                                 'reference', (select coalesce((select oi.invoice_number from public.so_invoice oi where oi.id = c.invoice_id), c.ref_invoice_number) from public.so_credit c where c.id = nullif(s.s->>'credit_id', '')::uuid)) order by s.ord), '[]'::jsonb)
      into v_cr_src from jsonb_array_elements(coalesce(p_n->'plan'->'steps', '[]'::jsonb)) with ordinality s(s, ord) where s.s->>'step' = 'auto_credit';
  else
    v_cr_src := coalesce(p_n->'credits', '[]'::jsonb);   -- doc-cr-1 판정 864: 적재(doc_data_invoice)가 실은 살아 있는 붙임 목록
  end if;
  -- doc-cr-1 판정 864 · doc-sr-1 판정 874: 크레딧 목록(번호 · 발행일 · 원 인보이스 번호 · 금액) + 합 — 세 kind 같은 꼴 · 순서는 원천 순
    select coalesce(jsonb_agg(jsonb_build_object('no', c.ord::text, 'number', coalesce(c.c->>'credit_number', ''), 'date', public.doc_fmt_date((c.c->>'issued_on')::date, v_fmt), 'reference', coalesce(c.c->>'reference', ''), 'amount', public.doc_fmt_money((c.c->>'amount')::numeric)) order by c.ord), '[]'::jsonb),
           coalesce(sum((c.c->>'amount')::numeric), 0)
      into v_credits, v_cr_amt from jsonb_array_elements(v_cr_src) with ordinality c(c, ord);
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
  v_out := jsonb_set(v_out, '{totals,credits}', to_jsonb(public.doc_fmt_money_nz(v_cr_amt))) || jsonb_build_object('credits', v_credits);   -- doc-cr-1: Credits 합(0 이면 빈칸 → 판의 줄이 사라진다) · 목록 · [doc-sr-1 판정 874] 세 kind(ship_ready 도)
  return v_out;
end;
$function$;

-- ═══ ② doc_field_catalog 재발행 — 원본 DB 바이트(md5 f8f5ab5b78fb4d441e81a42a6f837bf7) − ship_ready 가드 · 서명 · 권한 · comment 그대로 + 토막 ═══
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
    foreach v_x in array v_credit loop v_allowed := v_allowed || ('credits.' || v_x); end loop;   -- doc-cr-1 판정 864 · [doc-sr-1 판정 874] 크레딧 목록 + 합 — 세 kind(ship_ready 는 apply_plan 의 크레딧 계획 · final_invoice · internal_receipt 는 붙임)
    v_allowed := v_allowed || 'totals.credits'::text;
    v_sections := v_sections || 'credits'::text;
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

comment on function public.doc_data_invoice_fmt(text, jsonb, jsonb) is 'doc-1b2 — 인보이스 꼴 문서(final_invoice · internal_receipt · ship_ready)의 그리기 한 곳: 중립 jsonb(표에서 온 것 · 또는 so_invoice_preview 의 미리 보기) → doc_field_catalog 의 열쇠 · 꼴 · 줄 번호 · 판정 314 단가 칸 · ship_ready 는 invoice.number 대신 invoice.calc_at · [srs-1 판정 787] invoice.so_numbers = 오더 SO 번호를 orders 순서대로 「, 」 로 이은 글(빈 번호 건너뜀 · 메일 제목 자리표) · [판정 788] orders.ship_to_repeat = 앞 오더와 같은 배송지(company · 주소 줄 · city · state_province · postal_code · country · lower(btrim))면 true — 묶음 인보이스가 같은 Ship To 를 한 번만 · [doc-cr-1 판정 864] totals.balance_due = 늘 찍는 남은 금액(0 이면 "0.00" · 세 kind) · final_invoice · internal_receipt 에 credits[](no · number · date · reference · amount) · totals.credits(합 · 0 이면 "") — 옛 열쇠 무접촉 · [doc-sr-1 판정 874] ship_ready 에도 credits[] · totals.credits(같은 이름 · 뜻 · 꼴) — 원천은 so_invoice_preview 가 실은 plan(so_invoice_apply_plan)의 auto_credit 걸음 · reference 는 so_credit → so_invoice 로 읽음 · 불변식 total − Σpayments − Σcredits = balance_due(장마다)';
comment on function public.doc_field_catalog(text) is 'doc-1a ⑥ — 문서 kind 마다 판이 쓸 수 있는 자리표(allowed · 경로 꼴 orders.lines.sku = {{#orders}}{{#lines}}{{sku}}) · 목록 섹션(sections · 스코프를 미는 것 — 그 밖의 자리표도 {{#x}}…{{/x}} 조건으로 쓸 수 있으나 스코프를 밀지 않는다) · 필수(required · 섹션 이름은 섹션으로 써야 한다) · ⭐ doc-1b 데이터 창구는 이 목록과 똑같은 열쇠를 내야 한다(doc-1b 검증이 대조) · doc-0 Q2 와 다른 곳: bill_to · ship_to 에 city · state_province · postal_code · country(IMS 칸이 따로다) · charges.so_number · *.method · 크레딧 · SO 의 totals 는 제 것(deposit · balance_forward 없음) · [srs-1 판정 787 · 788] 인보이스 꼴 세 kind 에 invoice.so_numbers · orders.ship_to_repeat(불리언 · {{^ship_to_repeat}} 조건) · [doc-cr-1 판정 864] 인보이스 꼴 세 kind 에 totals.balance_due · final_invoice · internal_receipt 에 credits 섹션(no · number · date · reference · amount) · totals.credits · required 무접촉 · [doc-sr-1 판정 874] credits 섹션 · totals.credits 가 ship_ready 에도(세 kind 같은 목록) · required 무접촉';

-- ═══ ③ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_k text; v_n jsonb; v_body text;
begin
  if (select count(*) from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace) <> 1 or (select count(*) from pg_proc where proname = 'doc_field_catalog' and pronamespace = 'public'::regnamespace) <> 1 then v_bad := v_bad || ' dup-names'; end if;
  if (select provolatile from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) <> 's' or (select provolatile from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) <> 'i' then v_bad := v_bad || ' volatility'; end if;
  if (select prosrc from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) !~ 'auto_credit' or (select prosrc from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) ~ 'if p_kind <> ''ship_ready'' then' then v_bad := v_bad || ' fmt-body'; end if;
  if (select prosrc from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) ~ 'if p_kind <> ''ship_ready'' then' then v_bad := v_bad || ' cat-body'; end if;
  foreach v_k in array array['final_invoice', 'internal_receipt', 'ship_ready'] loop
    if not ((public.doc_field_catalog(v_k)->'allowed') ?& array['credits.no', 'credits.number', 'credits.date', 'credits.reference', 'credits.amount', 'totals.credits', 'totals.balance_due', 'invoice.so_numbers'])
       or not ((public.doc_field_catalog(v_k)->'sections') ? 'credits') or (public.doc_field_catalog(v_k)->'required') ? 'totals.credits' or (public.doc_field_catalog(v_k)->'required') ? 'totals.balance_due' then v_bad := v_bad || ' catalog-' || v_k; end if;
  end loop;
  if (public.doc_field_catalog('ship_ready')->'sections') <> '["branches", "orders", "orders.lines", "charges", "payments", "credits"]'::jsonb then v_bad := v_bad || ' sections-ship_ready'; end if;
  if (public.doc_field_catalog('ship_ready')->'required') <> '["invoice.calc_at", "orders.lines", "totals.tax", "totals.total", "totals.due_amount"]'::jsonb then v_bad := v_bad || ' required-ship_ready'; end if;
  if (public.doc_field_catalog('final_invoice')->'sections') <> '["branches", "orders", "orders.lines", "charges", "payments", "credits"]'::jsonb then v_bad := v_bad || ' sections-final_invoice'; end if;
  foreach v_k in array array['credit_note', 'sales_order'] loop
    if (public.doc_field_catalog(v_k)->'allowed') ? 'totals.balance_due' or (public.doc_field_catalog(v_k)->'allowed') ? 'totals.credits' or (public.doc_field_catalog(v_k)->'sections') ? 'credits' then v_bad := v_bad || ' catalog-leak-' || v_k; end if;
  end loop;
  -- 그리기 직접(중립 jsonb · ship_ready = plan): auto_credit 둘 → 목록 둘(계획 순 · reference 는 credit_id 가 가짜라 "") · 합 · balance_due = amount_due · 옛 열쇠 그대로
  v_n := public.doc_data_invoice_fmt('ship_ready', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb,
           '{"header":{},"orders":[],"charges":[],"payments":[{"reference":"x","paid_on":"2026-10-29","method":"cash","amount":1}],"totals":{"total":10,"amount_due":4.5,"deposit_applied":1,"credit_applied":4.5,"balance_forward":-4.5,"paid":1},"plan":{"deposit":1,"credit":4.5,"balance":0,"left":4.5,"steps":[{"step":"auto_deposit","payment_id":"00000000-0000-4000-8000-000000000001","amount":1,"paid_on":"2026-10-29"},{"step":"auto_credit","credit_id":"00000000-0000-4000-8000-000000000002","credit_number":"CR-00001","amount":3,"issued_on":"2026-10-28"},{"step":"auto_credit","credit_id":"00000000-0000-4000-8000-000000000003","credit_number":"CR-00002","amount":1.5,"issued_on":"2026-10-29"}]}}'::jsonb);
  if jsonb_array_length(v_n->'credits') <> 2 or (v_n->'credits'->0) <> '{"no":"1","date":"28OCT2026","amount":"3.00","number":"CR-00001","reference":""}'::jsonb or (v_n->'credits'->1) <> '{"no":"2","date":"29OCT2026","amount":"1.50","number":"CR-00002","reference":""}'::jsonb
     or (v_n->'totals'->>'credits') <> '4.50' or (v_n->'totals'->>'balance_due') <> '4.50' or (v_n->'totals'->>'due_amount') <> '4.50' or (v_n->'totals'->>'credit_applied') <> '4.50' or (v_n->'totals'->>'balance_forward') <> '-4.50' or (v_n->'totals'->>'deposit_applied') <> '1.00' or (v_n->'totals'->>'paid') <> '1.00'
     or jsonb_array_length(v_n->'payments') <> 1 then v_bad := v_bad || ' fmt-ship_ready(' || (v_n->'credits')::text || ' ' || (v_n->'totals')::text || ')'; end if;
  v_n := public.doc_data_invoice_fmt('ship_ready', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{},"orders":[],"charges":[],"payments":[],"totals":{"total":10,"amount_due":10},"plan":{"deposit":0,"credit":0,"balance":0,"left":10,"steps":[]}}'::jsonb);
  if (v_n->'credits') <> '[]'::jsonb or (v_n->'totals'->>'credits') <> '' or (v_n->'totals'->>'balance_due') <> '10.00' then v_bad := v_bad || ' fmt-ship_ready-none'; end if;
  v_n := public.doc_data_invoice_fmt('ship_ready', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{},"orders":[],"charges":[],"payments":[],"totals":{"total":10,"amount_due":10}}'::jsonb);
  if (v_n->'credits') <> '[]'::jsonb or (v_n->'totals'->>'credits') <> '' then v_bad := v_bad || ' fmt-ship_ready-noplan'; end if;
  -- final_invoice · internal_receipt 는 doc-cr-1 그대로(적재의 credits[] · plan 은 안 본다)
  v_n := public.doc_data_invoice_fmt('final_invoice', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb,
           '{"header":{"number":"1"},"orders":[],"charges":[],"payments":[],"credits":[{"credit_number":"CR-00001","issued_on":"2026-10-28","reference":"60070","amount":0.8},{"credit_number":"CR-00002","issued_on":"2026-10-27","reference":null,"amount":1.2}],"totals":{"total":2,"remaining":0},"plan":{"steps":[{"step":"auto_credit","credit_id":"00000000-0000-4000-8000-000000000002","credit_number":"CR-77777","amount":3,"issued_on":"2026-10-28"}]}}'::jsonb);
  if jsonb_array_length(v_n->'credits') <> 2 or (v_n->'credits'->0) <> '{"no":"1","date":"28OCT2026","amount":"0.80","number":"CR-00001","reference":"60070"}'::jsonb or (v_n->'credits'->1->>'reference') <> ''
     or (v_n->'totals'->>'credits') <> '2.00' or (v_n->'totals'->>'balance_due') <> '0.00' or (v_n->'totals'->>'due_amount') <> '' or v_n::text ~ 'CR-77777' then v_bad := v_bad || ' fmt-final_invoice(' || (v_n->'credits')::text || ')'; end if;
  v_n := public.doc_data_invoice_fmt('internal_receipt', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{"number":"1"},"orders":[],"charges":[],"payments":[],"totals":{"total":1,"remaining":1}}'::jsonb);
  if (v_n->'credits') <> '[]'::jsonb or (v_n->'totals'->>'credits') <> '' or (v_n->'totals'->>'balance_due') <> '1.00' then v_bad := v_bad || ' fmt-internal_receipt'; end if;
  if has_function_privilege('authenticated', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') or has_function_privilege('anon', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.doc_field_catalog(text)', 'execute') or not has_function_privilege('authenticated', 'public.doc_field_catalog(text)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  -- 판 검사: v9 꼴 Credits 표가 ship_ready 에서 통과 · 쓰는 ship_ready 판(옛 열쇠만)도 여전히 통과(required 무접촉) · {{#credits}} 가 더는 unknown_field 가 아니다
  if (public.doc_template_check('ship_ready', '<div>{{#orders}}{{#lines}}{{sku}}{{/lines}}{{/orders}}{{invoice.calc_at}} {{totals.tax}} {{totals.total}} {{totals.due_amount}} {{#credits}}{{no}} {{number}} {{date}} {{#reference}}(Invoice {{reference}}){{/reference}} {{amount}}{{/credits}}{{#totals.credits}}{{totals.credits}}{{/totals.credits}}{{totals.balance_due}}</div>', 'template')->>'ok')::boolean is distinct from true then v_bad := v_bad || ' template-check'; end if;
  if exists (select 1 from jsonb_array_elements(public.doc_template_check('ship_ready', '<div>{{#credits}}{{number}}{{/credits}}</div>', 'template')->'problems') p where p->>'code' = 'unknown_field') then v_bad := v_bad || ' ship_ready-credits-still-rejected'; end if;
  select t.body into v_body from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'ship_ready');
  if v_body is not null and (public.doc_template_check('ship_ready', v_body, 'template')->>'ok')::boolean is distinct from true then v_bad := v_bad || ' active-ship_ready-template'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM511', message = format('STOP - doc-sr-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
