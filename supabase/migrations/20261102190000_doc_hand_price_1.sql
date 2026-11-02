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

-- ═══ doc-hand-price-1 — 손 가격 줄은 문서에 손 가격을 단가로 (2026-11-02 · 판정 976 · 977 · 이견 답 1 ㉡ · 2 · 3 ⓑ · Caleb) ═══
--   실측(테스트 DB = IMS · 2026-11-02): 판 다섯(final_invoice v9 · internal_receipt v5 · ship_ready v7 · sales_order v2 · credit_note v2) 전부 제품 줄 단가 칸이 {{list_price}} · 할인 칸 {{discount_pct}} — 제품 줄 unit_price · net_unit_price 는 판 어디에도 없다
--     손 가격 줄(so_line.price_override · 15 줄 · 전부 SO-20843 Draft)은 「21.59 · (빈칸) · 194.04」 로 나와 셈이 안 맞아 보인다(자료의 unit_price 16.17 은 판이 안 본다) · 손 가격 줄이 든 발행 인보이스 0 장
--     크레딧 노트: doc_data_credit 이 제품 줄 전부에 list_price '' 를 준다(crn-1 20261021194405:627 부터) ⇒ 발행된 크레딧 노트(CR-01008 · RON02584 2 × 2.99)의 제품 줄 Unit price · Disc 가 둘 다 빈칸
--   판정 976 (가): 손 가격 줄은 문서에 손 가격을 단가로 · 할인 빈칸 — 「16.17 · (빈칸) · 194.04」 · 딜 · 손님 · 손 할인 % · Shopify 줄은 지금처럼 「정가 · 할인 % · 금액」 · 기각 (나) 정가 + 실효 할인 %
--   판정 977: SO 화면의 「−25.1 % vs list」 는 화면만(so_detail 줄에 list_price · unit_price · price_override 가 이미 온다 · 서버 무접촉)
--   이견 답 1 ㉡: 판 · 카탈로그 무변 · doc_data 만 — 열쇠 이름 · 수 그대로(list_price 열쇠 = 판정 527 의 「문서 Unit price 칸」 · 시스템 줄 = 정가 · 손 줄 = 손 가격 · unit_price · net_unit_price 열쇠는 그대로 진짜 값)
--     손 줄 판별 한 곳 = doc_price_cells(list · discount_pct · unit · manual · is_free): manual ∧ discount_pct is null ∧ not is_free ∧ unit not null — fmt(final_invoice · internal_receipt · ship_ready) · doc_data_so · doc_data_credit 셋이 같은 함수를 부른다
--     ⇒ so_line 에서 이 식 = price_override(무상 제외): manual = price_override ∨ discount_source ∈ (manual, shopify)(so_line_manual) · CHECK so_line_discount_pair_ck(discount_pct ⇔ discount_source) · 덮어쓴 줄은 source · pct null(§15 ①b 5) ⇒ manual ∧ pct null ⇔ price_override · 아래 ⑤ 가 모든 so_line · so_invoice_line 으로 검산한다
--     Shopify(1,087 줄 · pct 전부 있음) · 손 할인 %(14) 줄은 manual 이지만 pct 가 있어 손 줄이 아니다 · so_invoice_preview(price_override 를 떨군다 · od_1 8 k)는 안 건드린다
--   이견 답 2: 무상 줄(unit 0 · free_reason · 창구가 price_override true)은 지금대로 「정가 · 빈칸 · 0.00 + FREE」 — 판정 2 「받았을 금액 = list_price 가 남는다」 ⇒ is_free 면 손 줄이 아니다
--   이견 답 3 ⓑ: 크레딧 노트 제품 줄 = 인보이스 줄(so_invoice_line)의 정가 · 할인 %(손 줄은 같은 식으로 손 가격 · 빈칸) · 가격 조정 줄은 개당 차액 · 빈칸(613 그대로) · 참조 크레딧(인보이스 줄 없음)은 넣은 단가 · 빈칸
--     · 층 단가가 인보이스 단가와 다른 반품 줄(crn-2 tiers · 설명에 「2 × 9.49 + 1 × 7.99」)은 크레딧 단가 · 빈칸(정가 × 할인 × 수량 ≠ 금액이 되지 않게) · is_free 는 so_line.free_reason 으로(지금은 늘 false · 무상 반품 줄에 FREE 표가 붙는다 · 금액 0)
--   ① 새 함수 doc_price_cells(immutable · service 만 · doc_unit_prices 와 같은 선) ② doc_data_invoice_fmt 재발행 — 원본 DB 바이트(md5 6a2fe901b2d006e1ea1d8314c7991f84 · doc-sr-1 판) + 줄 둘 ③ doc_data_so 재발행 — 원본(904414a209c081eb2900bfe5daa935c3 · od-1 판) + 줄 둘
--   ④ doc_data_credit 재발행 — 원본(017c7f9b5111995d418a6d5888d27bda · hcr-1 판) + so_invoice_line 조인 · 제품 줄 칸 ⑤ 실물 확인(판별식 = price_override 전수 · 그리기 직접 · 모양 · 권한)
--   출력 열쇠 이름 · 수는 다섯 kind 모두 그대로(카탈로그 ↔ 출력 대조 무변) · 새 표 · 칸 · 창구 · grant(authenticated) 0 · 판 · 카탈로그 · 화면 · so_invoice_preview · doc_data_invoice · doc_data · doc_template_check 무접촉 · 검증 supabase/tests/doc_hand_price_1_check.sql
--   적용(Caleb · 테스트 Asung-IMS = IMS 운영 · 판정 617): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/migrations/20261102190000_doc_hand_price_1.sql && supabase migration repair --status applied 20261102190000 --db-url "$(cat ~/.asung-testdb-url)"

-- ═══ 원본 확인 — 셋 다 있고 md5 가 이 파일이 재발행하는 몸이어야 한다(다르면 멈춘다 · 이미 적용됐으면 멈춘다) ═══
do $$
declare v_fmt text; v_so text; v_cr text;
begin
  select md5(prosrc) into v_fmt from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace;
  select md5(prosrc) into v_so  from pg_proc where proname = 'doc_data_so'          and pronamespace = 'public'::regnamespace;
  select md5(prosrc) into v_cr  from pg_proc where proname = 'doc_data_credit'      and pronamespace = 'public'::regnamespace;
  if v_fmt is null or v_so is null or v_cr is null then raise exception using errcode = 'IM511', message = 'STOP - doc_data_invoice_fmt, doc_data_so or doc_data_credit is missing - nothing was changed'; end if;
  if exists (select 1 from pg_proc where proname = 'doc_price_cells' and pronamespace = 'public'::regnamespace) or (select prosrc from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace) ~ 'doc_price_cells' then
    raise exception using errcode = 'IM511', message = 'STOP - doc-hand-price-1 is already applied (doc_price_cells exists) - nothing was changed';
  end if;
  if v_fmt <> '6a2fe901b2d006e1ea1d8314c7991f84' or v_so <> '904414a209c081eb2900bfe5daa935c3' or v_cr <> '017c7f9b5111995d418a6d5888d27bda' then
    raise exception using errcode = 'IM511', message = format('STOP - doc_data_invoice_fmt md5 %s / doc_data_so md5 %s / doc_data_credit md5 %s are not the bodies (6a2fe901 / 904414a2 / 017c7f9b) this file re-issues - nothing was changed', left(v_fmt, 8), left(v_so, 8), left(v_cr, 8));
  end if;
end $$;

-- ═══ ① doc_price_cells — 제품 줄의 「Unit price · Disc.」 두 칸 · 손 줄 판별과 꼴 한 곳 ═══
create or replace function public.doc_price_cells(p_list numeric, p_discount_pct numeric, p_unit numeric, p_manual boolean, p_is_free boolean) returns jsonb
  language sql immutable parallel safe set search_path = public, pg_temp as $$
  select case when coalesce(p_manual, false) and p_discount_pct is null and not coalesce(p_is_free, false) and p_unit is not null
              then jsonb_build_object('list_price', public.doc_fmt_money(p_unit), 'discount_pct', '')                                   -- 손 가격 줄(price_override): 손 가격 · 빈칸 — 판정 976 (가)
              else jsonb_build_object('list_price', public.doc_fmt_money(p_list), 'discount_pct', public.doc_fmt_pct(p_discount_pct)) end;   -- 그 밖(손님 · 딜 · 손 할인 % · Shopify · 무상 · 가격 없음): 정가 · 할인 % — 판정 527 그대로
$$;
revoke all on function public.doc_price_cells(numeric, numeric, numeric, boolean, boolean) from public, anon, authenticated;
comment on function public.doc_price_cells(numeric, numeric, numeric, boolean, boolean) is 'doc-hand-price-1 판정 976 — 문서 제품 줄의 Unit price · Disc. 두 칸(열쇠 list_price · discount_pct · 판 다섯이 단가 칸에 {{list_price}} 를 찍는다): 손 가격 줄 = manual(so_line_manual) ∧ discount_pct null ∧ 무상 아님 ∧ 단가 있음 ⇔ so_line.price_override(CHECK so_line_discount_pair_ck · 덮어쓴 줄은 source · pct null) → 손 가격 · 빈칸 · 그 밖은 정가 · 할인 %(판정 527) · 무상 줄은 정가 · 빈칸(판정 2 · 이견 답 2) · fmt(세 kind) · doc_data_so · doc_data_credit 이 같이 쓴다 — 다른 길로 판별하지 마라';

-- ═══ ② doc_data_invoice_fmt 재발행 — 원본 DB 바이트(md5 6a2fe901b2d006e1ea1d8314c7991f84) + 줄 둘(줄 끝 「doc-hand-price-1」) · 서명 · 권한 · comment 그대로 + 토막 ═══
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
                                                                    'unit', coalesce(ln.l->>'unit', ''), 'qty', public.doc_fmt_qty((ln.l->>'qty')::numeric),   -- doc-hand-price-1: list_price · discount_pct 는 아래 doc_price_cells 가 준다
                                                                    'amount', public.doc_fmt_money((ln.l->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((ln.l->>'tax_amount')::numeric), 'is_free', coalesce((ln.l->>'is_free')::boolean, false), 'no_price', coalesce((ln.l->>'no_price')::boolean, false), 'final_sale', coalesce((ln.l->>'final_sale')::boolean, false))
                                                || public.doc_unit_prices((ln.l->>'unit_price')::numeric, case when coalesce((ln.l->>'manual')::boolean, false) then null else (ln.od_pct)::numeric end, v_disp)
                                                || public.doc_price_cells((ln.l->>'list_price')::numeric, (ln.l->>'discount_pct')::numeric, (ln.l->>'unit_price')::numeric, coalesce((ln.l->>'manual')::boolean, false), coalesce((ln.l->>'is_free')::boolean, false))) order by ln.no), '[]'::jsonb)   -- doc-hand-price-1 판정 976: 손 가격 줄(manual ∧ discount_pct null ∧ 무상 아님)은 단가 칸에 손 가격 · 할인 빈칸 — 판별 · 꼴 한 곳 doc_price_cells
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
comment on function public.doc_data_invoice_fmt(text, jsonb, jsonb) is 'doc-1b2 — 인보이스 꼴 문서(final_invoice · internal_receipt · ship_ready)의 그리기 한 곳: 중립 jsonb(표에서 온 것 · 또는 so_invoice_preview 의 미리 보기) → doc_field_catalog 의 열쇠 · 꼴 · 줄 번호 · 판정 314 단가 칸 · ship_ready 는 invoice.number 대신 invoice.calc_at · [srs-1 판정 787] invoice.so_numbers = 오더 SO 번호를 orders 순서대로 「, 」 로 이은 글(빈 번호 건너뜀 · 메일 제목 자리표) · [판정 788] orders.ship_to_repeat = 앞 오더와 같은 배송지(company · 주소 줄 · city · state_province · postal_code · country · lower(btrim))면 true — 묶음 인보이스가 같은 Ship To 를 한 번만 · [doc-cr-1 판정 864] totals.balance_due = 늘 찍는 남은 금액(0 이면 "0.00" · 세 kind) · final_invoice · internal_receipt 에 credits[](no · number · date · reference · amount) · totals.credits(합 · 0 이면 "") — 옛 열쇠 무접촉 · [doc-sr-1 판정 874] ship_ready 에도 credits[] · totals.credits(같은 이름 · 뜻 · 꼴) — 원천은 so_invoice_preview 가 실은 plan(so_invoice_apply_plan)의 auto_credit 걸음 · reference 는 so_credit → so_invoice 로 읽음 · 불변식 total − Σpayments − Σcredits = balance_due(장마다) · [doc-hand-price-1 판정 976] orders.lines 의 list_price · discount_pct 는 doc_price_cells 가 — 손 가격 줄(manual ∧ discount_pct null ∧ 무상 아님)은 손 가격 · 빈칸 · 그 밖은 정가 · 할인 %(열쇠 이름 · 수 그대로 · 판 무변)';

-- ═══ ③ doc_data_so 재발행 — 원본 DB 바이트(md5 904414a209c081eb2900bfe5daa935c3) + 줄 둘 ═══
CREATE OR REPLACE FUNCTION public.doc_data_so(p_so_id uuid, p_cfg jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_so   public.so%rowtype;
  v_pf   jsonb;  v_o jsonb;  v_t jsonb;
  v_fmt  text := p_cfg->>'date_format';
  v_disp text := coalesce(p_cfg->>'unit_display', 'both');
  v_lines jsonb;  v_charges jsonb := '[]'::jsonb;  v_prepay jsonb;
  v_lines_tax numeric;  v_n int := 0;  v_x jsonb;  v_sc_code text := (select c.value from public.inv_config c where c.key = 'so_surcharge_account_code');
  v_chg_amt numeric;  v_chg_tax numeric;
begin
  select * into v_so from public.so s where s.id = p_so_id;
  if v_so.id is null then raise exception 'Order not found'; end if;
  v_pf := public.so_proforma(array[p_so_id]);
  v_o := v_pf->'orders'->0;  v_t := v_pf->'totals';
  select coalesce(jsonb_agg((jsonb_build_object('no', x.no::text, 'upc', public.doc_upc(sl.product_id), 'sku', coalesce(x.l->>'sku', ''), 'description', coalesce(x.l->>'product_name', ''), 'comment', coalesce(sl.comments, ''),
                                                'unit', coalesce(x.l->>'unit', ''), 'qty', public.doc_fmt_qty((x.l->>'qty')::numeric),   -- doc-hand-price-1: list_price · discount_pct 는 아래 doc_price_cells 가 준다
                                                'amount', public.doc_fmt_money((x.l->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((x.l->>'tax')::numeric), 'is_free', sl.free_reason is not null, 'no_price', sl.unit_price is null)
                             || public.doc_unit_prices(sl.unit_price, case when coalesce(public.so_line_manual(sl), false) then null else v_so.order_discount_pct end, v_disp)
                             || public.doc_price_cells((x.l->>'list_price')::numeric, (x.l->>'discount_pct')::numeric, sl.unit_price, coalesce(public.so_line_manual(sl), false), sl.free_reason is not null)) order by x.no), '[]'::jsonb),   -- doc-hand-price-1 판정 976: 손 가격 줄은 단가 칸에 손 가격 · 할인 빈칸(fmt 와 같은 식 · doc_price_cells)
         coalesce(sum((x.l->>'tax')::numeric), 0)
    into v_lines, v_lines_tax
  from (select l, row_number() over (order by (l->>'line_no')::int) as no from jsonb_array_elements(coalesce(v_o->'lines', '[]'::jsonb)) l) x
  left join public.so_line sl on sl.id = (x.l->>'line_id')::uuid;
  -- charges = 운임(정가) · 운임 할인(음수) · 오더 할인(음수) · 줄 부가 요금 — so_tax_preview 가 센 값 그대로 · 순서 운임 → 할인 → 오더 할인 → 부가 요금
  for v_x in select c from jsonb_array_elements(coalesce(v_o->'charges', '[]'::jsonb)) c loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_x->>'account_code', ''), 'description', coalesce(v_x->>'name', ''), 'comment', coalesce(v_x->>'description', ''),
                                                 'qty', '', 'unit_price', '', 'discount_pct', public.doc_fmt_pct((v_x->>'discount_pct')::numeric), 'amount', public.doc_fmt_money((v_x->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'tax')::numeric));
  end loop;
  for v_x in select c from jsonb_array_elements(coalesce(v_o->'charge_discounts', '[]'::jsonb)) c loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce((select c.value from public.inv_config c where c.key = 'so_freight_discount_account_code'), ''), 'description', coalesce(v_x->>'name', ''), 'comment', '',
                                                 'qty', '', 'unit_price', '', 'discount_pct', public.doc_fmt_pct((v_x->>'discount_pct')::numeric), 'amount', public.doc_fmt_money((v_x->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'tax')::numeric));
  end loop;
  if coalesce((v_o->'order_discount'->>'amount')::numeric, 0) <> 0 then
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_so.sale_account_code, ''), 'description', format('Order discount %s%%', public.doc_fmt_qty((v_o->'order_discount'->>'pct')::numeric)), 'comment', '',
                                                 'qty', '', 'unit_price', '', 'discount_pct', '', 'amount', public.doc_fmt_money((v_o->'order_discount'->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_o->'order_discount'->>'tax')::numeric));
  end if;
  for v_x in select l from jsonb_array_elements(coalesce(v_o->'lines', '[]'::jsonb)) l where coalesce((l->>'surcharge_total')::numeric, 0) > 0 order by (l->>'line_no')::int loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_sc_code, ''), 'description', coalesce(nullif(v_x->>'surcharge_label', ''), 'Surcharge') || ' (' || (v_x->>'sku') || ')', 'comment', '',
                                                 'qty', public.doc_fmt_qty((v_x->>'qty')::numeric), 'unit_price', public.doc_fmt_money((v_x->>'surcharge_unit')::numeric), 'discount_pct', '',
                                                 'amount', public.doc_fmt_money((v_x->>'surcharge_total')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'surcharge_tax')::numeric));
  end loop;
  v_chg_amt := coalesce((v_t->>'charges_amount')::numeric, 0) - coalesce((v_t->>'charges_discount_amount')::numeric, 0) + coalesce((v_t->>'order_discount_amount')::numeric, 0) + coalesce((v_t->>'surcharge_amount')::numeric, 0);
  v_chg_tax := case when v_t->>'tax' is null then null else (v_t->>'tax')::numeric - v_lines_tax end;
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'reference', coalesce(x.d->>'reference', ''), 'date', public.doc_fmt_date((x.d->>'paid_on')::date, v_fmt), 'method', public.doc_method_label(x.d->>'method'), 'amount', public.doc_fmt_money((x.d->>'remaining')::numeric)) order by x.no), '[]'::jsonb)
    into v_prepay
  from (select d, row_number() over () as no from jsonb_array_elements(coalesce(v_pf->'deposits', '[]'::jsonb)) d) x;
  return jsonb_build_object(
    'so', jsonb_build_object('number', v_so.so_number, 'date', public.doc_fmt_date(v_so.order_date, v_fmt), 'status', v_so.status, 'required_by', public.doc_fmt_date(v_so.required_by, v_fmt), 'terms', coalesce(v_so.payment_term_name, ''),
                             'reference', coalesce(v_so.ref, ''), 'currency', coalesce(v_so.currency_code, ''), 'memo', coalesce(v_so.comments, '')),
    'ship_to', jsonb_build_object('company', coalesce(v_so.ship_to_company, ''), 'contact', coalesce(v_so.ship_to_contact, ''), 'phone', coalesce(v_so.ship_to_phone, ''), 'line1', coalesce(v_so.ship_to_line1, ''), 'line2', coalesce(v_so.ship_to_line2, ''),
                                  'city', coalesce(v_so.ship_to_city, ''), 'state_province', coalesce(v_so.ship_to_state_province, ''), 'postal_code', coalesce(v_so.ship_to_postal_code, ''), 'country', coalesce(v_so.ship_to_country, '')),
    'lines', v_lines, 'charges', v_charges, 'prepayments', v_prepay,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money((v_t->>'lines_amount')::numeric), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money((v_t->>'lines_amount')::numeric + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'order_discount', public.doc_fmt_money((v_t->>'order_discount_amount')::numeric), 'surcharge', public.doc_fmt_money((v_t->>'surcharge_amount')::numeric), 'charges_discount', public.doc_fmt_money(-(v_t->>'charges_discount_amount')::numeric),
                                 'before_tax', public.doc_fmt_money((v_t->>'taxable_amount')::numeric), 'tax', public.doc_fmt_money((v_t->>'tax')::numeric), 'total', public.doc_fmt_money((v_t->>'total')::numeric),
                                 'prepaid', public.doc_fmt_money_nz((v_t->>'received')::numeric), 'due_amount', public.doc_fmt_money((v_t->>'balance_due')::numeric)))   -- doc-1c 판정 528 ③ 의 결: 선결제 없으면 빈칸 · due 는 늘(아직 안 낸 오더)
    || public.doc_data_common('sales_order', p_cfg, jsonb_build_object('name', v_so.bill_to_name, 'line1', v_so.bill_to_line1, 'line2', v_so.bill_to_line2, 'city', v_so.bill_to_city, 'state_province', v_so.bill_to_state_province,
                                                                        'postal_code', v_so.bill_to_postal_code, 'country', v_so.bill_to_country) || public.doc_contact(coalesce(v_so.bill_to_customer_id, v_so.customer_id)));
end;
$function$;
comment on function public.doc_data_so(uuid, jsonb) is 'doc-1b — sales_order 문서 자료(so_proforma 의 줄 · 운임 · 오더 할인 · 부가 요금 · 선결제 · doc_data_common) · [od-1 판정 544] 손 줄(so_line_manual)은 오더 할인 몫 0(doc_unit_prices od_pct null) · [doc-hand-price-1 판정 976] lines 의 list_price · discount_pct 는 doc_price_cells 가 — 손 가격 줄은 손 가격 · 빈칸 · 그 밖은 정가 · 할인 %(fmt · doc_data_credit 과 같은 식 · 판 sales_order v2 무변)';

-- ═══ ④ doc_data_credit 재발행 — 원본 DB 바이트(md5 017c7f9b5111995d418a6d5888d27bda) + so_invoice_line 조인 · 제품 줄 두 칸 · is_free ═══
CREATE OR REPLACE FUNCTION public.doc_data_credit(p_credit_id uuid, p_cfg jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cr   public.so_credit%rowtype;
  v_inv  public.so_invoice%rowtype;
  v_fmt  text := p_cfg->>'date_format';
  v_bill jsonb;  v_ship jsonb;  v_lines jsonb;  v_charges jsonb;  v_refunds jsonb;
  v_lines_amt numeric;  v_lines_tax numeric;  v_chg_amt numeric;  v_chg_tax numeric;  v_applied numeric;  v_ref text;
begin
  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  if v_cr.id is null then raise exception 'Credit note not found'; end if;
  if v_cr.invoice_id is not null then
    select * into v_inv from public.so_invoice i where i.id = v_cr.invoice_id;
    v_bill := jsonb_build_object('name', v_inv.bill_to_name, 'line1', v_inv.bill_to_line1, 'line2', v_inv.bill_to_line2, 'city', v_inv.bill_to_city, 'state_province', v_inv.bill_to_state_province, 'postal_code', v_inv.bill_to_postal_code, 'country', v_inv.bill_to_country);
    select jsonb_build_object('company', o.ship_to_company, 'contact', o.ship_to_contact, 'phone', o.ship_to_phone, 'line1', o.ship_to_line1, 'line2', o.ship_to_line2, 'city', o.ship_to_city, 'state_province', o.ship_to_state_province, 'postal_code', o.ship_to_postal_code, 'country', o.ship_to_country)
      into v_ship
    from public.so_invoice_order o where o.invoice_id = v_inv.id order by o.so_number limit 1;                                                   -- 여러 오더면 첫 오더(so_number 순)의 배송지
    select string_agg(s.ref, ', ' order by o.so_number) into v_ref from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id and s.ref is not null and s.ref <> '';
  else
    select jsonb_build_object('name', c.name, 'line1', a.line1, 'line2', a.line2, 'city', a.city, 'state_province', a.state_province, 'postal_code', a.postal_code, 'country', a.country) into v_bill
    from public.customer c left join public.customer_address a on a.customer_id = c.id and a.is_active and a.type = 'Billing' and a.is_default_for_type where c.id = v_cr.customer_id;
    select jsonb_build_object('company', c.name, 'contact', '', 'phone', '', 'line1', a.line1, 'line2', a.line2, 'city', a.city, 'state_province', a.state_province, 'postal_code', a.postal_code, 'country', a.country) into v_ship
    from public.customer c left join public.customer_address a on a.customer_id = c.id and a.is_active and a.type = 'Shipping' and a.is_default_for_type where c.id = coalesce(v_cr.store_customer_id, v_cr.customer_id);   -- hcr-1 판정 779: 참조 크레딧의 배송지 블록(종이의 매장) = 매장 칸 · 청구 블록은 청구처 그대로
  end if;
  -- 제품 줄(콤보 구성품 줄은 뺀다 — 손님 문서 · amount 0) · 그 밖(freight · tax · other · surcharge · order_discount · freight_discount)은 charges · restocking_fee 는 totals
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'upc', public.doc_upc(x.product_id), 'sku', coalesce(x.sku, ''), 'description', coalesce(x.description, ''), 'comment', '', 'unit', coalesce(x.unit, ''),
                                               'qty', public.doc_fmt_qty(coalesce(x.qty_returned, x.qty_adjusted)), 'unit_price', public.doc_fmt_money(x.unit_price), 'net_unit_price', '',   -- crn-2: 가격 조정 줄은 조정 수량 · 개당 차액 · doc-hand-price-1: list_price · discount_pct 는 아래가 준다(판 credit_note v2 는 단가 칸에 {{list_price}} 를 찍는다 — crn-1 부터 빈칸이던 것)
                                               'amount', public.doc_fmt_money(x.amount), 'tax_amount', public.doc_fmt_money(x.tax_amount), 'is_free', x.is_free, 'no_price', false)
                             || case when x.kind = 'product' and x.il_unit is not null and x.unit_price = x.il_unit then public.doc_price_cells(x.il_list, x.il_pct, x.unit_price, x.manual, x.is_free)   -- doc-hand-price-1 판정 976 ⓑ: 반품 줄 = 인보이스 줄의 정가 · 할인 %(손 가격 줄은 손 가격 · 빈칸 — fmt 와 같은 식)
                                     else jsonb_build_object('list_price', public.doc_fmt_money(x.unit_price), 'discount_pct', '') end order by x.no), '[]'::jsonb),                                  -- 가격 조정 줄(개당 차액) · 참조 크레딧(넣은 단가) · 층 단가가 인보이스 단가와 다른 반품 줄 = 크레딧 단가 · 빈칸(금액 = 수량 × 단가 가 맞게)
         coalesce(sum(x.amount), 0), coalesce(sum(x.tax_amount), 0)
    into v_lines, v_lines_amt, v_lines_tax
  from (select l.*, coalesce(sl.unit, p.uom_name) as unit, row_number() over (order by l.line_no) as no,
               il.list_price as il_list, il.discount_pct as il_pct, il.unit_price as il_unit, coalesce(public.so_line_manual(sl), false) as manual, sl.free_reason is not null as is_free   -- doc-hand-price-1
        from public.so_credit_line l left join public.so_line sl on sl.id = l.so_line_id left join public.product p on p.id = l.product_id left join public.so_invoice_line il on il.id = l.so_invoice_line_id
        where l.credit_id = v_cr.id and l.kind in ('product', 'price_adjustment') and l.combo_credit_line_id is null) x;                                          -- crn-2 판정 603: 가격 조정 줄은 제품 표에(설명 「Price adjustment 9.49 → 7.99 — …」)
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'so_number', '', 'code', coalesce(x.account_code, ''), 'description', coalesce(x.description, ''), 'comment', '', 'qty', public.doc_fmt_qty(x.qty_returned),
                                               'unit_price', public.doc_fmt_money(x.unit_price), 'discount_pct', '', 'amount', public.doc_fmt_money(x.amount), 'tax_amount', public.doc_fmt_money(x.tax_amount)) order by x.no), '[]'::jsonb),
         coalesce(sum(x.amount), 0), coalesce(sum(x.tax_amount), 0)
    into v_charges, v_chg_amt, v_chg_tax
  from (select l.*, row_number() over (order by l.line_no) as no from public.so_credit_line l where l.credit_id = v_cr.id and l.kind not in ('product', 'restocking_fee', 'price_adjustment')) x;   -- crn-2
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'reference', coalesce(x.reference, ''), 'date', public.doc_fmt_date(x.paid_on, v_fmt), 'method', public.doc_method_label(x.method), 'amount', public.doc_fmt_money(x.amount)) order by x.no), '[]'::jsonb)
    into v_refunds
  from (select a.amount, p.reference, p.paid_on, p.method, row_number() over (order by p.paid_on, p.created_at, a.created_at) as no
        from public.so_credit_alloc a join public.so_payment p on p.id = a.refund_payment_id
        where a.credit_id = v_cr.id and a.refund_payment_id is not null and a.voided_at is null and p.status = 'active') x;
  select coalesce(sum(a.amount), 0) into v_applied from public.so_credit_alloc a where a.credit_id = v_cr.id and a.invoice_id is not null and a.voided_at is null;
  return jsonb_build_object(
    'credit', jsonb_build_object('number', v_cr.credit_number, 'date', public.doc_fmt_date(v_cr.issued_on, v_fmt), 'invoice_number', coalesce(v_inv.invoice_number, v_cr.ref_invoice_number, ''),   -- crn-1 판정 609: 참조 번호(옛 이름은 판정 609 앞의 것)
                                 'reference', coalesce(v_ref, ''), 'reason', coalesce(v_cr.reason, ''), 'currency', coalesce(v_cr.currency_code, ''), 'memo', coalesce(v_cr.note, '')),
    'ship_to', jsonb_build_object('company', coalesce(v_ship->>'company', ''), 'contact', coalesce(v_ship->>'contact', ''), 'phone', coalesce(v_ship->>'phone', ''), 'line1', coalesce(v_ship->>'line1', ''), 'line2', coalesce(v_ship->>'line2', ''),
                                  'city', coalesce(v_ship->>'city', ''), 'state_province', coalesce(v_ship->>'state_province', ''), 'postal_code', coalesce(v_ship->>'postal_code', ''), 'country', coalesce(v_ship->>'country', '')),
    'lines', v_lines, 'charges', v_charges, 'refunds', v_refunds,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money(v_lines_amt), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money(v_lines_amt + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'restocking_fee', public.doc_fmt_money(v_cr.fee_amount), 'before_tax', public.doc_fmt_money(v_cr.total - v_cr.tax_amount), 'tax', public.doc_fmt_money(v_cr.tax_amount), 'total', public.doc_fmt_money(v_cr.total),
                                 'applied', public.doc_fmt_money(v_applied), 'remaining', public.doc_fmt_money(public.so_credit_remaining(v_cr.id))))
    || public.doc_data_common('credit_note', p_cfg, coalesce(v_bill, '{}'::jsonb) || public.doc_contact(v_cr.customer_id));
end;
$function$;
comment on function public.doc_data_credit(uuid, jsonb) is 'doc-1b — credit_note 문서 자료(so_credit · 제품 줄 · charges · 환불 · 붙인 돈 · doc_data_common) · [crn-1 판정 609] 참조 번호 · [crn-2 판정 603 · 613] 가격 조정 줄은 제품 표에(조정 수량 · 개당 차액) · [hcr-1 판정 779] 참조 크레딧의 배송지 = 매장 · [doc-hand-price-1 판정 976 ⓑ] 제품 줄의 list_price · discount_pct(판 credit_note v2 의 단가 · 할인 칸 — crn-1 부터 빈칸이던 것) = 인보이스 줄(so_invoice_line)의 정가 · 할인 % · 손 가격 줄은 손 가격 · 빈칸(doc_price_cells · fmt 와 같은 식) · 가격 조정 · 참조 크레딧 · 층 단가가 인보이스 단가와 다른 줄은 크레딧 단가 · 빈칸 · is_free = so_line.free_reason';

-- ═══ ⑤ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n jsonb; v_l jsonb; v_bad_so bigint; v_bad_il bigint; v_hand bigint;
begin
  if (select count(*) from pg_proc where proname in ('doc_price_cells', 'doc_data_invoice_fmt', 'doc_data_so', 'doc_data_credit') and pronamespace = 'public'::regnamespace) <> 4 then v_bad := v_bad || ' dup-or-missing'; end if;
  if (select provolatile from pg_proc where oid = 'public.doc_price_cells(numeric, numeric, numeric, boolean, boolean)'::regprocedure) <> 'i'
     or (select provolatile from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) <> 's'
     or (select provolatile from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure) <> 's'
     or (select provolatile from pg_proc where oid = 'public.doc_data_credit(uuid, jsonb)'::regprocedure) <> 's' then v_bad := v_bad || ' volatility'; end if;
  if has_function_privilege('authenticated', 'public.doc_price_cells(numeric, numeric, numeric, boolean, boolean)', 'execute') or has_function_privilege('anon', 'public.doc_price_cells(numeric, numeric, numeric, boolean, boolean)', 'execute')
     or not has_function_privilege('service_role', 'public.doc_price_cells(numeric, numeric, numeric, boolean, boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') or has_function_privilege('authenticated', 'public.doc_data_so(uuid, jsonb)', 'execute') or has_function_privilege('authenticated', 'public.doc_data_credit(uuid, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') or has_function_privilege('anon', 'public.doc_data_so(uuid, jsonb)', 'execute') or has_function_privilege('anon', 'public.doc_data_credit(uuid, jsonb)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if (select count(*) from pg_proc where proname in ('doc_data_invoice_fmt', 'doc_data_so', 'doc_data_credit') and pronamespace = 'public'::regnamespace and prosrc ~ 'doc_price_cells') <> 3 then v_bad := v_bad || ' bodies'; end if;
  -- 판별식 = price_override(무상 · 구성품 · 가격 없음 제외) — 모든 so_line · 모든 so_invoice_line 제품 줄(so_line 조인)
  select count(*) into v_bad_so from public.so_line l where l.combo_line_id is null and l.free_reason is null and l.unit_price is not null
                                                      and (coalesce(public.so_line_manual(l), false) and l.discount_pct is null) <> coalesce(l.price_override, false);
  select count(*) into v_bad_il from public.so_invoice_line il join public.so_line sl on sl.id = il.so_line_id where il.kind = 'product' and sl.free_reason is null and il.unit_price is not null
                                                      and (coalesce(public.so_line_manual(sl), false) and il.discount_pct is null) <> coalesce(sl.price_override, false);
  select count(*) into v_hand from public.so_line l where coalesce(l.price_override, false) and l.free_reason is null and l.combo_line_id is null;
  if v_bad_so <> 0 or v_bad_il <> 0 then v_bad := v_bad || format(' rule-vs-price_override(so_line %s · so_invoice_line %s)', v_bad_so, v_bad_il); end if;
  -- doc_price_cells 진리표: 손(16.17) · 손님 7 %(10.69 · 7%) · Shopify 0 %(manual · pct 0 → 정가 · 빈칸) · 손 할인 % 25(manual · pct 25 → 정가 · 25%) · 무상(manual · pct null · is_free → 정가 · 빈칸) · 가격 없음(unit null → 정가 · 빈칸) · 정가 없는 손 줄(list null → 손 가격)
  if public.doc_price_cells(21.59, null, 16.17, true, false) <> '{"list_price": "16.17", "discount_pct": ""}'::jsonb
     or public.doc_price_cells(10.69, 7, 9.9417, false, false) <> '{"list_price": "10.69", "discount_pct": "7%"}'::jsonb
     or public.doc_price_cells(2.99, 0, 2.99, true, false) <> '{"list_price": "2.99", "discount_pct": ""}'::jsonb
     or public.doc_price_cells(21.59, 25, 16.1925, true, false) <> '{"list_price": "21.59", "discount_pct": "25%"}'::jsonb
     or public.doc_price_cells(10, null, 0, true, true) <> '{"list_price": "10.00", "discount_pct": ""}'::jsonb
     or public.doc_price_cells(5, null, null, false, false) <> '{"list_price": "5.00", "discount_pct": ""}'::jsonb
     or public.doc_price_cells(null, null, 16.17, true, false) <> '{"list_price": "16.17", "discount_pct": ""}'::jsonb
     or public.doc_price_cells(21.59, null, 16.17, null, null) <> '{"list_price": "21.59", "discount_pct": ""}'::jsonb then v_bad := v_bad || ' cells-truth-table'; end if;
  -- 그리기 직접(중립 jsonb · ship_ready): 손 줄 · 손님 줄 · Shopify 줄 · 무상 줄 · 가격 없음 — 열쇠 이름 · 수 그대로(14) · 값
  v_n := public.doc_data_invoice_fmt('ship_ready', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb,
           '{"header":{},"charges":[],"payments":[],"totals":{"total":10,"amount_due":10},"orders":[{"so_number":"SO-1","order_discount_pct":10,"lines":[
              {"sku":"H","qty":12,"list_price":21.59,"discount_pct":null,"unit_price":16.17,"amount":194.04,"tax_amount":0,"is_free":false,"no_price":false,"manual":true},
              {"sku":"C","qty":3,"list_price":10.69,"discount_pct":7,"unit_price":9.9417,"amount":29.83,"tax_amount":0,"is_free":false,"no_price":false,"manual":false},
              {"sku":"S","qty":2,"list_price":2.99,"discount_pct":0,"unit_price":2.99,"amount":5.98,"tax_amount":0,"is_free":false,"no_price":false,"manual":true},
              {"sku":"F","qty":1,"list_price":10,"discount_pct":null,"unit_price":0,"amount":0,"tax_amount":0,"is_free":true,"no_price":false,"manual":true},
              {"sku":"N","qty":1,"list_price":5,"discount_pct":null,"unit_price":null,"amount":null,"tax_amount":0,"is_free":false,"no_price":true,"manual":false}]}]}'::jsonb);
  v_l := v_n->'orders'->0->'lines';
  if jsonb_array_length(v_l) <> 5
     or (v_l->0->>'list_price') <> '16.17' or (v_l->0->>'discount_pct') <> '' or (v_l->0->>'unit_price') <> '16.17' or (v_l->0->>'net_unit_price') <> '' or (v_l->0->>'amount') <> '194.04'
     or (v_l->1->>'list_price') <> '10.69' or (v_l->1->>'discount_pct') <> '7%' or (v_l->1->>'unit_price') <> '9.94' or (v_l->1->>'net_unit_price') <> '8.95'
     or (v_l->2->>'list_price') <> '2.99' or (v_l->2->>'discount_pct') <> '' or (v_l->2->>'unit_price') <> '2.99' or (v_l->2->>'net_unit_price') <> ''
     or (v_l->3->>'list_price') <> '10.00' or (v_l->3->>'discount_pct') <> '' or (v_l->3->>'unit_price') <> '0.00' or (v_l->3->>'is_free')::boolean is distinct from true
     or (v_l->4->>'list_price') <> '5.00' or (v_l->4->>'discount_pct') <> '' or (v_l->4->>'unit_price') <> '' or (v_l->4->>'no_price')::boolean is distinct from true
     or (select array_agg(k order by k) from jsonb_object_keys(v_l->0) k) <> array['amount', 'comment', 'description', 'discount_pct', 'final_sale', 'is_free', 'list_price', 'net_unit_price', 'no', 'no_price', 'qty', 'sku', 'tax_amount', 'unit', 'unit_price', 'upc']
     then v_bad := v_bad || ' fmt-lines(' || v_l::text || ')'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM511', message = format('STOP - doc-hand-price-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
  raise notice 'doc-hand-price-1: landed - hand-price rule = price_override on every so_line / so_invoice_line (mismatch 0 / 0) - hand-price lines now %', v_hand;
end $$;
