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

-- ═══ srs-1 — 프로포마(Ship Ready) 메일 제목에 SO 번호 — 자리표 invoice.so_numbers (2026-10-26 밤 · 판정 787) · 묶음 인보이스의 같은 배송지는 한 번만 — orders.ship_to_repeat (판정 788) ═══
--   Caleb 「프로포마 이메일 화면에 이메일 제목에 세일즈 오더 번호가 자동으로 붙게 해줄 수 있지?」 → 「바로 쓰자」
--   사실: 메일 제목 = doc_setting(kind, mail_subject) 를 doc_mail_fill(text, doc) 이 채운다(값 하나짜리 {{a.b}} 만) · ship_ready 의 SO 번호는 orders.so_number — 목록 안에만 있어 제목에 넣을 자리표가 없었다
--   ① doc_data_invoice_fmt 재발행 — 원본 DB 바이트(md5 a0c3f58dbd760a01615ee7996556e7fb · bgr-1d 판) + 더한 줄 하나(줄 끝 「srs-1」): invoice.so_numbers = 문서의 오더 SO 번호를 orders 순서대로 「, 」 로 이은 글(빈 번호 건너뜀)
--      세 kind 공통(final_invoice · internal_receipt · ship_ready — 그리기 한 곳 · 인보이스 메일 제목에도 바로 쓸 수 있다) · credit_note · sales_order 는 무접촉
--   ①-b [판정 788 · Caleb 「merged 인보이스인데, 주소가 두번 나와」 · 실물 60073 · SO-25201 · SO-25202] 같은 함수에 더한 줄 하나 더: 오더마다 boolean ship_to_repeat — 이 문서의 앞 오더 중 배송지가 같은 것이 있으면 true(첫 오더는 false)
--      같음 = company · line1 · line2 · city · state_province · postal_code · country 의 lower(btrim) 전부 같음(contact · phone 은 안 본다 — 「이름 · 주소 줄 · 도시 · 주 · 우편번호 · 나라」) · 판은 {{^ship_to_repeat}}…{{/ship_to_repeat}} 로 숨긴다(판은 대화 Claude 가 통째로)
--   ② doc_field_catalog 재발행 — 원본 DB 바이트(md5 7a9edf38a1903ddc3398a9df700882e8 · bgr-1d 판) + 더한 줄 하나: 인보이스 꼴 세 kind 의 allowed 에 invoice.so_numbers · orders.ship_to_repeat
--   ③ ship_ready 기본 메일 제목 — 지금 값이 시드 원문 'PROFORMA INVOICE - Asung Trading Inc.' 과 정확히 같을 때만 'PROFORMA INVOICE {{invoice.so_numbers}} - Asung Trading Inc.' 로(직원이 고쳤으면 그대로)
--      doc_setting_set 창구는 ims_require_write(master) · auth.uid() 가 필요해 마이그레이션에서 못 부른다 → 같은 조건의 직접 update + 실물 확인이 doc_template_check(kind, value, 'text') 통과를 본다 · updated_by 는 시드처럼 null
--   미리 보기(Email the ship ready) 의 제목은 화면이 고치지 않아도 같은 값 — ims-doc.js:186 doc_mail_send(p_commit false · p_subject 없음) → DB 가 doc_setting 글을 doc_mail_fill 로 채워 돌려준다 · 보내기는 칸의 글(이미 채워짐)을 p_subject 로
--   ⚠️ ship_ready 메일은 docs[0] 만 본다(doc_mail_send) — 인보이스가 갈려 문서가 여럿이면 제목엔 첫 묶음의 SO 번호(화면은 PDF 가 둘 이상이면 보내기를 막는다 · ims-doc.js 「email each order on its own」)
--   새 표 · 칸 · 시퀀스 · 창구 0 · 서명 · volatility(STABLE · IMMUTABLE) · 권한 그대로(create or replace) · comment 끝에 srs-1 한 토막 · 검증 supabase/tests/srs_1_check.sql
do $$
declare v_fmt text; v_cat text;
begin
  select md5(prosrc) into v_fmt from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace;
  select md5(prosrc) into v_cat from pg_proc where proname = 'doc_field_catalog' and pronamespace = 'public'::regnamespace;
  if v_fmt is null or v_cat is null then raise exception using errcode = 'IM511', message = 'STOP - doc_data_invoice_fmt or doc_field_catalog (doc-1b2 · bgr-1d) is missing - nothing was changed'; end if;
  if (select prosrc from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace) ~ 'so_numbers' then
    raise exception using errcode = 'IM511', message = 'STOP - srs-1 is already applied (doc_data_invoice_fmt already makes invoice.so_numbers) - nothing was changed';
  end if;
  if v_fmt <> 'a0c3f58dbd760a01615ee7996556e7fb' or v_cat <> '7a9edf38a1903ddc3398a9df700882e8' then
    raise exception using errcode = 'IM511', message = format('STOP - doc_data_invoice_fmt md5 %s / doc_field_catalog md5 %s are not the bgr-1d bodies (a0c3f58d / 7a9edf38) this file re-issues - nothing was changed', left(v_fmt, 8), left(v_cat, 8));
  end if;
end $$;

-- ═══ ① doc_data_invoice_fmt 재발행 — 원본 DB 바이트(md5 a0c3f58dbd760a01615ee7996556e7fb) + 더한 줄 둘(줄 끝 「srs-1」 · 787 so_numbers · 788 ship_to_repeat) · 서명 · 권한 · comment 그대로(create or replace) ═══
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
  v_inv := jsonb_build_object('number', coalesce(v_h->>'number', ''), 'date', public.doc_fmt_date((v_h->>'issued_on')::date, v_fmt), 'due_date', public.doc_fmt_date((v_h->>'due_on')::date, v_fmt), 'terms', coalesce(v_h->>'payment_term_name', ''),
                              'currency', coalesce(v_h->>'currency_code', ''), 'memo', coalesce(v_h->>'memo', ''), 'total_qty', public.doc_fmt_qty(v_qty));
  v_inv := v_inv || jsonb_build_object('so_numbers', coalesce((select string_agg(o.o->>'so_number', ', ' order by o.ord) from jsonb_array_elements(p_n->'orders') with ordinality o(o, ord) where nullif(btrim(o.o->>'so_number'), '') is not null), ''));   -- srs-1 판정 787: 문서의 오더 SO 번호를 orders 순서대로 「, 」 로 이은 글(빈 번호 건너뜀) — 메일 제목 {{invoice.so_numbers}} 재료 · 세 kind 공통
  if p_kind = 'ship_ready' then
    v_inv := (v_inv - 'number') || jsonb_build_object('calc_at', public.doc_fmt_date(public.ims_today(), v_fmt) || ' ' || to_char(coalesce((p_n->>'calc_at')::timestamptz, now()) at time zone 'America/Toronto', 'HH24:MI'));
  end if;
  return jsonb_build_object(
    'invoice', v_inv, 'orders', v_orders, 'charges', v_charges, 'payments', v_payments,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money(v_lines_amt), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money(v_lines_amt + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'order_discount', public.doc_fmt_money((v_t->>'order_discount')::numeric), 'surcharge', public.doc_fmt_money((v_t->>'surcharge')::numeric), 'charges_discount', public.doc_fmt_money(v_chd),
                                 'before_tax', public.doc_fmt_money((v_t->>'taxable')::numeric), 'tax', public.doc_fmt_money((v_t->>'tax')::numeric), 'total', public.doc_fmt_money((v_t->>'total')::numeric),
                                 'deposit_applied', public.doc_fmt_money_nz((v_t->>'deposit_applied')::numeric), 'credit_applied', public.doc_fmt_money_nz((v_t->>'credit_applied')::numeric), 'balance_forward', public.doc_fmt_money_nz((v_t->>'balance_forward')::numeric),   -- doc-1c 판정 528 ③: 0 이면 빈칸
                                 'paid', public.doc_fmt_money_nz((v_t->>'paid')::numeric), 'due_label', case when v_due > 0 then 'Due' when v_due < 0 then 'Credit' else '' end, 'due_amount', public.doc_fmt_money_nz(v_due)))   -- doc-1c 판정 528 ②: 남은 돈 0 이면 둘 다 빈칸(판이 {{#totals.due_amount}} 로 숨긴다)
    || public.doc_data_common(p_kind, p_cfg, (v_h->'bill_to') || public.doc_contact(nullif(v_h->>'bill_to_customer_id', '')::uuid));
end;
$function$;

-- ═══ ② doc_field_catalog 재발행 — 원본 DB 바이트(md5 7a9edf38a1903ddc3398a9df700882e8) + 더한 줄 하나(줄 끝 「srs-1」 · 열쇠 둘) · 서명 · 권한 · comment 그대로(create or replace) ═══
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

comment on function public.doc_data_invoice_fmt(text, jsonb, jsonb) is 'doc-1b2 — 인보이스 꼴 문서(final_invoice · internal_receipt · ship_ready)의 그리기 한 곳: 중립 jsonb(표에서 온 것 · 또는 so_invoice_preview 의 미리 보기) → doc_field_catalog 의 열쇠 · 꼴 · 줄 번호 · 판정 314 단가 칸 · ship_ready 는 invoice.number 대신 invoice.calc_at · [srs-1 판정 787] invoice.so_numbers = 오더 SO 번호를 orders 순서대로 「, 」 로 이은 글(빈 번호 건너뜀 · 메일 제목 자리표) · [판정 788] orders.ship_to_repeat = 앞 오더와 같은 배송지(company · 주소 줄 · city · state_province · postal_code · country · lower(btrim))면 true — 묶음 인보이스가 같은 Ship To 를 한 번만';
comment on function public.doc_field_catalog(text) is 'doc-1a ⑥ — 문서 kind 마다 판이 쓸 수 있는 자리표(allowed · 경로 꼴 orders.lines.sku = {{#orders}}{{#lines}}{{sku}}) · 목록 섹션(sections · 스코프를 미는 것 — 그 밖의 자리표도 {{#x}}…{{/x}} 조건으로 쓸 수 있으나 스코프를 밀지 않는다) · 필수(required · 섹션 이름은 섹션으로 써야 한다) · ⭐ doc-1b 데이터 창구는 이 목록과 똑같은 열쇠를 내야 한다(doc-1b 검증이 대조) · doc-0 Q2 와 다른 곳: bill_to · ship_to 에 city · state_province · postal_code · country(IMS 칸이 따로다) · charges.so_number · *.method · 크레딧 · SO 의 totals 는 제 것(deposit · balance_forward 없음) · [srs-1 판정 787 · 788] 인보이스 꼴 세 kind 에 invoice.so_numbers · orders.ship_to_repeat(불리언 · {{^ship_to_repeat}} 조건)';

-- ═══ ③ ship_ready 기본 메일 제목 — 시드 원문일 때만 바꾼다(직원이 고친 값은 그대로) · updated_by 는 시드처럼 null ═══
update public.doc_setting set value = 'PROFORMA INVOICE {{invoice.so_numbers}} - Asung Trading Inc.'
 where kind = 'ship_ready' and key = 'mail_subject' and value = 'PROFORMA INVOICE - Asung Trading Inc.';

-- ═══ ④ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_k text; v_subj text; v_chk jsonb;
begin
  if (select count(*) from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace) <> 1 or (select count(*) from pg_proc where proname = 'doc_field_catalog' and pronamespace = 'public'::regnamespace) <> 1 then v_bad := v_bad || ' dup-names'; end if;
  if (select provolatile from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) <> 's' or (select provolatile from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) <> 'i' then v_bad := v_bad || ' volatility'; end if;
  if (select prosrc from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) !~ 'so_numbers' or (select prosrc from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) !~ 'ship_to_repeat' then v_bad := v_bad || ' fmt-body'; end if;
  foreach v_k in array array['final_invoice', 'ship_ready', 'internal_receipt'] loop
    if not ((public.doc_field_catalog(v_k)->'allowed') ? 'invoice.so_numbers') or not ((public.doc_field_catalog(v_k)->'allowed') ? 'orders.ship_to_repeat') then v_bad := v_bad || ' catalog-' || v_k; end if;
  end loop;
  foreach v_k in array array['credit_note', 'sales_order'] loop
    if (public.doc_field_catalog(v_k)->'allowed') ? 'invoice.so_numbers' or (public.doc_field_catalog(v_k)->'allowed') ? 'orders.ship_to_repeat' then v_bad := v_bad || ' catalog-leak-' || v_k; end if;
  end loop;
  if (public.doc_field_catalog('ship_ready')->'sections') <> '["branches", "orders", "orders.lines", "charges", "payments"]'::jsonb then v_bad := v_bad || ' sections'; end if;
  if has_function_privilege('authenticated', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') or has_function_privilege('anon', 'public.doc_field_catalog(text)', 'execute')
     or not has_function_privilege('authenticated', 'public.doc_field_catalog(text)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if (public.doc_template_check('ship_ready', 'PROFORMA INVOICE {{invoice.so_numbers}} - Asung Trading Inc.', 'text')->>'ok')::boolean is distinct from true then v_bad := v_bad || ' subject-check'; end if;
  if (public.doc_template_check('final_invoice', '<div>{{#orders}}{{^ship_to_repeat}}<p>{{ship_to.company}} {{ship_to.line1}}</p>{{/ship_to_repeat}}{{#lines}}{{sku}}{{/lines}}{{/orders}}{{invoice.number}} {{invoice.so_numbers}} {{totals.tax}} {{totals.total}} {{totals.due_amount}}</div>', 'template')->>'ok')::boolean is distinct from true then v_bad := v_bad || ' template-check'; end if;
  select d.value into v_subj from public.doc_setting d where d.kind = 'ship_ready' and d.key = 'mail_subject';
  if v_subj is null then v_bad := v_bad || ' subject-row';
  elsif v_subj <> '' then
    v_chk := public.doc_template_check('ship_ready', v_subj, 'text');
    if not (v_chk->>'ok')::boolean and (v_chk->'problems'->0->>'code') <> 'no_placeholders' then v_bad := v_bad || ' subject-value(' || (v_chk->'problems'->0->>'code') || ')'; end if;
  end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM511', message = format('STOP - srs-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
