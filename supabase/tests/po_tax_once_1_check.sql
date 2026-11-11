-- supabase/tests/po_tax_once_1_check.sql — po-tax-once-1 검증 (2026-11-11 · 판정 1193 · §0 이견 1 ~ 7 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] 기준(begin 앞 · 잠금 없음) → begin → (-v mig 면 \i) → 가짜 재료(DO 하나) → R 실물 · F 가짜 · G 구조(DO 하나) → 실물 비교 표 → rollback
--   Claude Code(시험 · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -X -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111222857_po_tax_once_1_group_tax_once.sql -f supabase/tests/po_tax_once_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(갈래마다 · 시험 갈래에만 도는 검사 = R4 「바뀐 문서는 정확히 셋」)
--   ⚠️ 가짜 재료만(공급처 ZZ-TO1 · PO-79451 · PO-79452 · 문서 ZZTO1-*) — 실제 공급처 · 인보이스 · PO 는 읽기만 · 일감 claim · 송신 창구는 부르지 않는다(qbo_bill_body 는 읽기 — stable · 쓰기 0) · 공개 레포 — 상호를 찍지 않는다
--   ⚠️ create or replace view(po_tax_group ACCESS EXCLUSIVE) — 토론토 17:00 뒤 · begin ~ rollback 10 초 안
--   ⚠️ R1 · R2 는 2026-11-11 의 실물(인보이스 둘)을 본다 — 그 문서가 뒤에 고쳐지면 그날의 기록으로 둔다
\set ON_ERROR_STOP on
\pset pager off
\if :{?mig}
\set EXPECT_OK 23
\else
\set EXPECT_OK 22
\endif
select (select value from public.inv_config where key = 'db_role') as db_role;

create temp table t_res (n serial, label text, got text, want text, ok boolean);
create temp table t_ids (k text primary key, v text);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns text language plpgsql as $$
begin
  insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want);
  return case when p_got is not distinct from p_want then 'OK   ' else 'FAIL ' end || p_label || case when p_got is not distinct from p_want then '' else format(' — got %s · want %s', coalesce(p_got, '(null)'), coalesce(p_want, '(null)')) end;
end $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  execute p_sql into v_out;
  return coalesce(v_out, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p_txt text) returns jsonb language sql as $$ select case when left(p_txt, 1) in ('{', '[') then p_txt::jsonb end $$;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select v::uuid from t_ids where k = p_k $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$ insert into t_ids values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;

-- ── 기준(begin 앞 · 잠금 없음) — 실물 문서 전부의 돈 · 묶음 · PO 세금 · 무변 정의 md5 ──
create temp table t_pre as
select (select coalesce(jsonb_object_agg(m.id::text, to_jsonb(m)), '{}'::jsonb) from public.po_invoice_money m) as inv,
       (select coalesce(jsonb_object_agg(l.id::text, jsonb_build_object('po_number', l.po_number, 'status', l.status, 'net_total', l.net_total, 'tax_amount', l.tax_amount, 'total_with_tax', l.total_with_tax)), '{}'::jsonb) from public.po_list l) as po,
       (select string_agg(c.relname || ':' || md5(pg_get_viewdef(c.oid, true)), ' ' order by c.relname) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('po_invoice_money', 'po_list', 'po_invoice_list')) as md5_views,
       (select string_agg(p.proname || ':' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('so_tax_amount', 'so_tax_preview', 'po_detail', 'po_invoice_detail', 'po_invoice_confirm', 'po_doc_cancel', 'po_invoice_discount_parts', 'po_invoice_early_discount', 'po_early_discount_calc', 'po_pay_candidates',
                            'po_payment_detail', 'po_payment_target_check', 'qbo_bill_body', 'qbo_bill_payment_body', 'qbo_discount_credit_body', 'qbo_job_doc')) as md5_funcs;
select (select count(*) from jsonb_object_keys(inv)) as n_inv, (select count(*) from jsonb_object_keys(po)) as n_po, clock_timestamp() as t_begin from t_pre \gset
\echo '── 기준: supplier documents' :n_inv '· POs' :n_po

begin;
set local statement_timeout = '60s';
set local lock_timeout = '3s';
\if :{?mig}
\echo '── 시험 적용:' :mig
\i :mig
\endif

-- ── 가짜 재료(DO 하나) — 공급처 · PO 둘 · 문서 여섯(전부 draft · 일감 없음) ──
do $$
declare
  v_cad uuid := (select id from public.ref_currency where code = 'CAD'); v_term uuid := (select id from public.ref_payment_term where name = 'Due on receipt');
  v_hst uuid := (select id from public.ref_tax_rule where name = 'HST ON (Purchase)' and rate_pct = 13); v_gst uuid := (select id from public.ref_tax_rule where name = 'GST (Purchase)' and rate_pct = 5);
  v_prod uuid := (select id from public.product where sku = 'AAL10850'); v_ap public.ref_account%rowtype;
  v_s uuid := gen_random_uuid(); v_po uuid := gen_random_uuid(); v_po2 uuid := gen_random_uuid(); v_l1 uuid := gen_random_uuid();
  v_a uuid := gen_random_uuid(); v_b uuid := gen_random_uuid(); v_c uuid := gen_random_uuid(); v_d uuid := gen_random_uuid(); v_e uuid := gen_random_uuid(); v_f uuid := gen_random_uuid();
begin
  select * into v_ap from public.ref_account where code = '_62_';
  if v_cad is null or v_term is null or v_hst is null or v_gst is null or v_prod is null or v_ap.id is null then raise exception 'fixture: a reference row is missing (currency · term · HST ON 13 · GST 5 · product AAL10850 · _62_)'; end if;
  insert into public.supplier (id, name, source, is_active, payment_term_id, payment_term_name, account_payable_id, account_payable_code, currency_id) values (v_s, 'ZZ-TO1 Supplier', 'manual', true, v_term, 'Due on receipt', v_ap.id, v_ap.code, v_cad);
  insert into public.po (id, po_number, status, supplier_id, currency_id, tax_rule_id) values (v_po, 'PO-79451', 'confirmed', v_s, v_cad, v_hst), (v_po2, 'PO-79452', 'confirmed', v_s, v_cad, v_hst);
  insert into public.po_line (id, po_id, line_no, product_id, qty_ea, unit_price) values (v_l1, v_po, 1, v_prod, 1000, 2.5);
  insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (v_po2, 1, v_prod, 1, 0.33), (v_po2, 2, v_prod, 1, 0.33), (v_po2, 3, v_prod, 1, 0.33);
  insert into public.po_invoice (id, supplier_id, invoice_number, invoice_date, due_date, payment_term_id, payment_term_name, currency_id, total_amount, status, doc_kind, tax_rule_id, early_discount_pct, early_discount_basis) values
    (v_a, v_s, 'ZZTO1-ROUND',  public.ims_today() - 2, public.ims_today() + 28, v_term, 'Due on receipt', v_cad, 0, 'draft', 'invoice', v_hst, null, null),
    (v_b, v_s, 'ZZTO1-DISC',   public.ims_today() - 2, public.ims_today() + 28, v_term, 'Due on receipt', v_cad, 0, 'draft', 'invoice', v_hst, 2, 'with_tax'),
    (v_c, v_s, 'ZZTO1-NP',     public.ims_today() - 2, public.ims_today() + 28, v_term, 'Due on receipt', v_cad, 0, 'draft', 'invoice', v_hst, null, null),
    (v_d, v_s, 'ZZTO1-TWO',    public.ims_today() - 2, public.ims_today() + 28, v_term, 'Due on receipt', v_cad, 0, 'draft', 'invoice', v_hst, null, null),
    (v_e, v_s, 'ZZTO1-CR',     public.ims_today() - 2, null, null, null, v_cad, 0, 'draft', 'credit', v_hst, null, null),
    (v_f, v_s, 'ZZTO1-NORULE', public.ims_today() - 2, public.ims_today() + 28, v_term, 'Due on receipt', v_cad, 0, 'draft', 'invoice', null, null, null);
  -- A = 0.33 세 줄(줄마다 0.04 × 3 = 0.12 · 한 번 0.99 × 13 % = 0.13) · B = 10.33 세 줄 + charge 5.00 + 체인 10 % + with_tax 조기 할인 2 % · C = 안 내는 줄 섞임 · D = 세금 묶음 둘(HST 머리 · GST 줄) · E = 크레딧 · F = 규칙 없음
  insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, description, qty_ea, unit_price, is_payable, credit_reason, tax_rule_id) values
    (v_a, 1, 'goods', v_l1, null, 1, 0.33, true, null, null), (v_a, 2, 'goods', v_l1, null, 1, 0.33, true, null, null), (v_a, 3, 'goods', v_l1, null, 1, 0.33, true, null, null),
    (v_b, 1, 'goods', v_l1, null, 1, 10.33, true, null, null), (v_b, 2, 'goods', v_l1, null, 1, 10.33, true, null, null), (v_b, 3, 'goods', v_l1, null, 1, 10.33, true, null, null), (v_b, 4, 'charge', null, 'ZZ freight', 1, 5, true, null, null),
    (v_c, 1, 'goods', v_l1, null, 1, 0.33, true, null, null), (v_c, 2, 'goods', v_l1, null, 1, 0.33, true, null, null), (v_c, 3, 'goods', v_l1, null, 1, 0.33, false, null, null), (v_c, 4, 'charge', null, 'ZZ freight not paid', 1, 0.5, false, null, null),
    (v_d, 1, 'goods', v_l1, null, 1, 0.33, true, null, null), (v_d, 2, 'goods', v_l1, null, 1, 0.33, true, null, null), (v_d, 3, 'goods', v_l1, null, 1, 0.33, true, null, null),
    (v_d, 4, 'goods', v_l1, null, 1, 0.10, true, null, v_gst), (v_d, 5, 'goods', v_l1, null, 1, 0.10, true, null, v_gst), (v_d, 6, 'goods', v_l1, null, 1, 0.10, true, null, v_gst),
    (v_e, 1, 'goods', v_l1, null, 1, 0.33, true, 'price_difference', null), (v_e, 2, 'goods', v_l1, null, 1, 0.33, true, 'price_difference', null), (v_e, 3, 'goods', v_l1, null, 1, 0.33, true, 'price_difference', null),
    (v_f, 1, 'goods', v_l1, null, 1, 0.33, true, null, null);
  insert into public.po_invoice_discount (po_invoice_id, seq, name, percent) values (v_b, 1, 'ZZ trade', 10);
  perform pg_temp.put('a', v_a::text); perform pg_temp.put('b', v_b::text); perform pg_temp.put('c', v_c::text); perform pg_temp.put('d', v_d::text); perform pg_temp.put('e', v_e::text); perform pg_temp.put('f', v_f::text);
  perform pg_temp.put('po2', v_po2::text); perform pg_temp.put('hst', v_hst::text); perform pg_temp.put('gst', v_gst::text);
end $$;

-- ── R 실물 · F 가짜 · G 구조(DO 하나 · 서버 안) — 기대값은 손셈(주석에 식) ──
do $$
declare
  v_t text; v_b jsonb; v_m record; v_g record; v_pre t_pre%rowtype;
  c_real constant uuid := '697fb03d-909c-4807-b786-f6236b99c7ce';
  v_same uuid := (select i.id from public.po_invoice i where i.invoice_number = 'Order #8884650' and i.status = 'confirmed' order by i.created_at limit 1);
begin
  select * into v_pre from t_pre;
  -- R1 실물(11-11 의 15335): 과세 1,654.20 × 13 % = 215.046 → 215.05(줄마다 합 215.04) · 1,654.20 + 215.05 = 1,869.25 = 찍힌 합계
  select * into v_m from public.po_invoice_money where id = c_real;
  select * into v_g from public.po_tax_group where doc_kind = 'invoice' and doc_id = c_real;
  perform pg_temp.chk('R1a 실물 인보이스(15335): 묶음 과세 1654.20 · 참고 lines_tax 215.04 · discount_tax 0.00 · tax 215.05 · payable_tax 215.05',
    concat_ws(' ', v_g.taxable_amount, v_g.lines_tax, v_g.discount_tax, v_g.tax_amount, v_g.payable_tax), '1654.20 215.04 0.00 215.05 215.05');
  perform pg_temp.chk('R1b 실물 인보이스(15335): 돈 — tax 215.05 · computed_total 1869.25 · diff 0.00 · payable_net 1869.25 · 묶음 1',
    concat_ws(' ', v_m.tax_amount, v_m.computed_total, v_m.diff, v_m.payable_net, v_m.tax_rule_groups), '215.05 1869.25 0.00 1869.25 1');
  v_t := pg_temp.try(format('select public.qbo_bill_body(%L::uuid, %L)::text', c_real, 'bill')); v_b := pg_temp.j(v_t);
  perform pg_temp.chk('R1c 실물 인보이스(15335): qbo_bill_body 가 거부 없이 선다 — 8 줄 · TotalTax 215.05 · TaxLine 하나(215.05 · 과세 1654.20 · 13 %) · 지문 186925|CAD',
    case when v_b is null then left(v_t, 160) else concat_ws(' ', v_b->>'line_count', v_b->'body'->'TxnTaxDetail'->>'TotalTax', jsonb_array_length(v_b->'body'->'TxnTaxDetail'->'TaxLine'), v_b->'body'->'TxnTaxDetail'->'TaxLine'->0->>'Amount',
      v_b->'body'->'TxnTaxDetail'->'TaxLine'->0->'TaxLineDetail'->>'NetAmountTaxable', v_b->'body'->'TxnTaxDetail'->'TaxLine'->0->'TaxLineDetail'->>'TaxPercent', v_b->'lookup'->>'total_cents', v_b->>'fingerprint') end,
    '8 215.05 1 215.05 1654.20 13 186925 186925|CAD');
  -- R2 실물(세금 있는 다른 확정 인보이스): 줄마다 = 한 번 = 123.50 · 돈 줄 전체가 기준과 같다
  select * into v_m from public.po_invoice_money where id = v_same;
  perform pg_temp.chk('R2 실물 인보이스(세금 123.50): tax 123.50 · 돈 줄(jsonb) = 기준', concat_ws(' ', v_m.tax_amount, (to_jsonb(v_m) = v_pre.inv->(v_same::text))::text), '123.50 true');
  -- R3 기준 때 세금 0 이던 확정 인보이스 · 크레딧 전부: 돈 줄(jsonb)이 기준과 같다 · 한 장 이상
  perform pg_temp.chk('R3 세금 0 인 확정 문서: 기준과 다른 돈 줄 0 · 그런 문서가 한 장 이상',
    (select concat_ws(' ', count(*) filter (where to_jsonb(m) is distinct from e.value), (count(*) >= 1)::text)
       from jsonb_each(v_pre.inv) e join public.po_invoice_money m on m.id = e.key::uuid where e.value->>'status' = 'confirmed' and coalesce((e.value->>'tax_amount')::numeric, 0) = 0), '0 true');
  -- R5 기준 때 있던 문서 가운데 세금 말고 다른 칸이 바뀐 것 0(인보이스: tax · payable_tax · computed_total · diff · payable_net · unpaid · remaining 을 뺀 jsonb / PO: net_total)
  perform pg_temp.chk('R5 세금에서 나오지 않는 칸은 기준과 같다(인보이스 돈 줄에서 세금 계열 일곱 칸을 뺀 jsonb · PO net_total) — 다른 문서 0 0',
    (select count(*) from jsonb_each(v_pre.inv) e join public.po_invoice_money m on m.id = e.key::uuid
       where (to_jsonb(m) - array['tax_amount', 'payable_tax', 'computed_total', 'diff', 'payable_net', 'unpaid', 'remaining', 'credit_total']) is distinct from (e.value - array['tax_amount', 'payable_tax', 'computed_total', 'diff', 'payable_net', 'unpaid', 'remaining', 'credit_total']))::text
    || ' ' || (select count(*) from jsonb_each(v_pre.po) e join public.po_list l on l.id = e.key::uuid where l.net_total is distinct from (e.value->>'net_total')::numeric)::text, '0 0');

  -- F1 0.33 세 줄 @ 13 %: 줄마다 round(0.0429) = 0.04 × 3 = 0.12 · 한 번 round(0.99 × 0.13 = 0.1287) = 0.13
  select * into v_g from public.po_tax_group where doc_id = pg_temp.id('a');
  select * into v_m from public.po_invoice_money where id = pg_temp.id('a');
  perform pg_temp.chk('F1 0.33 × 3 @ 13 %: 과세 0.99 · 참고 lines_tax 0.12 · tax 0.13 · payable_tax 0.13 · 돈 tax 0.13 · computed 1.12 · payable_net 1.12',
    concat_ws(' ', v_g.taxable_amount, v_g.lines_tax, v_g.tax_amount, v_g.payable_tax, v_m.tax_amount, v_m.computed_total, v_m.payable_net), '0.99 0.12 0.13 0.13 0.13 1.12 1.12');
  -- F2 goods 30.99 · 체인 10 % → round(27.891) = 27.89 · 할인 3.10 · charge 5.00 · 과세 32.89 · 한 번 round(4.2757) = 4.28 · 옛 식 (1.34 × 3 + 0.65) − round(0.403) = 4.27 · 할인을 빼먹으면 round(35.99 × 0.13) = 4.68
  select * into v_g from public.po_tax_group where doc_id = pg_temp.id('b');
  select * into v_m from public.po_invoice_money where id = pg_temp.id('b');
  perform pg_temp.chk('F2 체인 할인 10 %: goods 30.99 · other 5.00 · 할인 3.10 · 과세 32.89 · 참고 lines_tax 4.67 · discount_tax 0.40 · tax 4.28 · payable_tax 4.28 · computed 37.17 · payable_net 37.17',
    concat_ws(' ', v_g.goods_amount, v_g.other_amount, v_g.discount_amount, v_g.taxable_amount, v_g.lines_tax, v_g.discount_tax, v_g.tax_amount, v_g.payable_tax, v_m.computed_total, v_m.payable_net), '30.99 5.00 3.10 32.89 4.67 0.40 4.28 4.28 37.17 37.17');
  -- F3 with_tax 조기 할인 2 %(판정 395): 기준 = 낼 돈 37.17 · 할인 round(0.7434) = 0.74 · 세금 몫 round(0.74 × 4.28 / 37.17 = 0.0852) = 0.09 · 그 밖의 몫 round(0.74 × 5 / 37.17 = 0.0995) = 0.10 · 원가 몫 0.55
  perform pg_temp.chk('F3 with_tax 조기 할인: 기준 37.17 · 할인 0.74 · 세 몫 = 원가 0.55 · 세금 0.09 · 그 밖 0.10(합 0.74) · 몫의 세금 = 묶음 세금 4.28',
    (select concat_ws(' ', d.base_amount, d.discount) from public.po_invoice_early_discount(pg_temp.id('b'), null) d) || ' ' ||
    (select concat_ws(' ', p.basis, p.base_amount, p.cost_part, p.tax_part, p.other_part, p.tax_amount) from public.po_invoice_discount_parts(pg_temp.id('b'), 0.74, null) p), '37.17 0.74 with_tax 37.17 0.55 0.09 0.10 4.28');
  -- F4 안 내는 줄: 전체 과세 0.99 + 0.50 = 1.49 → round(0.1937) = 0.19 · 낼 과세 0.66 → round(0.0858) = 0.09(옛 식 0.04 × 2 = 0.08)
  select * into v_g from public.po_tax_group where doc_id = pg_temp.id('c');
  select * into v_m from public.po_invoice_money where id = pg_temp.id('c');
  perform pg_temp.chk('F4 안 내는 줄 섞임: 과세 1.49 · tax 0.19 · 낼 과세 0.66 · payable_tax 0.09 · computed 1.68 · payable_net 0.75',
    concat_ws(' ', v_g.taxable_amount, v_g.tax_amount, v_g.payable_taxable, v_g.payable_tax, v_m.computed_total, v_m.payable_net), '1.49 0.19 0.66 0.09 1.68 0.75');
  -- F5 묶음 둘: HST 0.99 → 0.13(줄마다 0.12) · GST 0.10 × 3 = 0.30 → round(0.015) = 0.02(줄마다 round(0.005) = 0.01 × 3 = 0.03) · 돈 tax 0.15 · computed 0.99 + 0.30 + 0.15 = 1.44
  select * into v_m from public.po_invoice_money where id = pg_temp.id('d');
  perform pg_temp.chk('F5 세금 묶음 둘: GST 5 % 과세 0.30 참고 0.03 tax 0.02 | HST 13 % 과세 0.99 참고 0.12 tax 0.13 · 돈 tax 0.15 · computed 1.44 · 묶음 2',
    (select string_agg(concat_ws(' ', trim_scale(g.rate_pct), g.taxable_amount, g.lines_tax, g.tax_amount), ' | ' order by g.rate_pct) from public.po_tax_group g where g.doc_id = pg_temp.id('d'))
      || ' · ' || concat_ws(' ', v_m.tax_amount, v_m.computed_total, v_m.tax_rule_groups), '5 0.30 0.03 0.02 | 13 0.99 0.12 0.13 · 0.15 1.44 2');
  -- F6 크레딧(이견 1 — 같은 뷰 · 같은 식): 0.33 × 3 → 0.13 · 뺄 돈 1.12 · 안 붙은 크레딧 remaining 1.12
  select * into v_g from public.po_tax_group where doc_id = pg_temp.id('e');
  select * into v_m from public.po_invoice_money where id = pg_temp.id('e');
  perform pg_temp.chk('F6 크레딧도 같은 식: doc_kind(뷰) invoice · tax 0.13 · payable_tax 0.13 · 돈 doc_kind credit · payable_net 1.12 · remaining 1.12',
    concat_ws(' ', v_g.doc_kind, v_g.tax_amount, v_g.payable_tax, v_m.doc_kind, v_m.payable_net, v_m.remaining), 'invoice 0.13 0.13 credit 1.12 1.12');
  -- F7 규칙 없음: 세금 null · tax_rule_missing · computed = 세금 전 0.33
  select * into v_g from public.po_tax_group where doc_id = pg_temp.id('f');
  select * into v_m from public.po_invoice_money where id = pg_temp.id('f');
  perform pg_temp.chk('F7 규칙 없는 줄: 묶음 tax · payable_tax · lines_tax null · 돈 tax null · tax_rule_missing true · computed 0.33',
    concat_ws(' ', coalesce(v_g.tax_amount::text, 'null'), coalesce(v_g.payable_tax::text, 'null'), coalesce(v_g.lines_tax::text, 'null'), coalesce(v_m.tax_amount::text, 'null'), v_m.tax_rule_missing::text, v_m.computed_total), 'null null null null true 0.33');
  -- F8 PO(doc_kind po): 0.33 × 3 @ 13 % → 0.13 · 목록 예상 세금 0.13 · 세금 포함 1.12
  perform pg_temp.chk('F8 PO 도 같은 식: 묶음 tax 0.13 · payable_tax 0.13 · po_list tax_amount 0.13 · total_with_tax 1.12',
    (select concat_ws(' ', g.tax_amount, g.payable_tax) from public.po_tax_group g where g.doc_kind = 'po' and g.doc_id = pg_temp.id('po2'))
      || ' ' || (select concat_ws(' ', l.tax_amount, l.total_with_tax) from public.po_list l where l.id = pg_temp.id('po2')), '0.13 0.13 0.13 1.12');
  -- F9 모든 묶음(실물 + 가짜): tax_amount = round(taxable × rate / 100, 2) · payable_tax = round(payable_taxable × rate / 100, 2) — 어긋난 묶음 0 · 세율 아는 묶음 한 개 이상
  perform pg_temp.chk('F9 모든 묶음에서 tax = round(과세 × 세율, 2) · payable_tax = round(낼 과세 × 세율, 2) — 어긋난 묶음 0',
    (select concat_ws(' ', count(*) filter (where g.tax_amount is distinct from round(g.taxable_amount * g.rate_pct / 100, 2) or g.payable_tax is distinct from round(g.payable_taxable * g.rate_pct / 100, 2)), (count(*) >= 1)::text)
       from public.po_tax_group g where g.rate_pct is not null), '0 true');

  -- G 구조
  perform pg_temp.chk('G1 뷰 po_tax_group: 칸 18 개 이름 · 형 그대로 · security_invoker · 권한 그대로 · anon 권한 없음',
    md5((select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attnum) from pg_attribute a where a.attrelid = 'public.po_tax_group'::regclass and a.attnum > 0 and not a.attisdropped))
      || ' ' || (select count(*) from pg_attribute a where a.attrelid = 'public.po_tax_group'::regclass and a.attnum > 0 and not a.attisdropped)::text
      || ' ' || (select c.reloptions::text || ' ' || c.relacl::text from pg_class c where c.oid = 'public.po_tax_group'::regclass) || ' ' || has_table_privilege('anon', 'public.po_tax_group', 'select')::text,
    md5('doc_kind:text,doc_id:uuid,tax_rule_id:uuid,tax_rule:text,rate_pct:numeric(7,4),line_count:integer,goods_amount:numeric,other_amount:numeric,discount_amount:numeric,taxable_amount:numeric,lines_tax:numeric,discount_tax:numeric,tax_amount:numeric,goods_payable:numeric,other_payable:numeric,payable_discount:numeric,payable_taxable:numeric,payable_tax:numeric')
      || ' 18 {security_invoker=true} {postgres=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres} false');
  perform pg_temp.chk('G2 새 정의: md5 3f979ecb… · payable_lines_tax 없음 · 묶음 소계에 so_tax_amount 한 번씩(둘)',
    md5(pg_get_viewdef('public.po_tax_group'::regclass, true)) || ' ' || (pg_get_viewdef('public.po_tax_group'::regclass, true) like '%payable_lines_tax%')::text,
    '3f979ecbe76829db115d28c1398341ed false');
  perform pg_temp.chk('G3 의존 뷰 셋(po_invoice_money · po_list · po_invoice_list)의 정의 = 기준 · 옵션 security_invoker 셋',
    ((select string_agg(c.relname || ':' || md5(pg_get_viewdef(c.oid, true)), ' ' order by c.relname) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('po_invoice_money', 'po_list', 'po_invoice_list')) = v_pre.md5_views)::text
      || ' ' || (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('po_invoice_money', 'po_list', 'po_invoice_list') and c.reloptions::text = '{security_invoker=true}')::text, 'true 3');
  perform pg_temp.chk('G4 함수 무변 열여섯(so_tax_amount · so_tax_preview · 읽는 함수 열셋 · po_early_discount_calc) — md5 = 기준 · so_tax_amount md5 3408f7cd…',
    ((select string_agg(p.proname || ':' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('so_tax_amount', 'so_tax_preview', 'po_detail', 'po_invoice_detail', 'po_invoice_confirm', 'po_doc_cancel', 'po_invoice_discount_parts', 'po_invoice_early_discount', 'po_early_discount_calc', 'po_pay_candidates',
                          'po_payment_detail', 'po_payment_target_check', 'qbo_bill_body', 'qbo_bill_payment_body', 'qbo_discount_credit_body', 'qbo_job_doc')) = v_pre.md5_funcs)::text
      || ' ' || (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_tax_amount'), 'true 3408f7cd2707de5e89528ac40d0d0810');
  perform pg_temp.chk('G5 주석 셋(po_tax_group · po_invoice_money · po_list): po-tax-once-1 글이 있고 옛 「줄마다 반올림 · 할인 줄 한 번」 글이 없다',
    (select count(*) from pg_class c where c.oid in ('public.po_tax_group'::regclass, 'public.po_invoice_money'::regclass, 'public.po_list'::regclass) and obj_description(c.oid) like '%po-tax-once-1%' and obj_description(c.oid) not like '%줄마다 반올림 · 할인 줄 한 번%')::text, '3');
  perform pg_temp.chk('G6 손님 쪽 무접촉: so_ · pos_ · shop_ · doc_ 함수 가운데 po_tax_group · po_invoice_money 를 읽는 것 0',
    (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(so_|pos_|shop_|doc_)' and p.prosrc ~* 'po_tax_group|po_invoice_money')::text, '0');
  perform pg_temp.chk('G7 가짜 문서는 draft · 일감 0(트리거가 송신 일감을 세우지 않았다)',
    (select count(*) from public.qbo_job j where j.ims_id in (select v from t_ids))::text || ' ' || (select count(*) from public.po_invoice i where i.invoice_number like 'ZZTO1-%' and i.status = 'draft')::text, '0 6');
end $$;

\if :{?mig}
-- R4(시험 갈래만 — 확인 갈래에서는 기준이 이미 새 식이다) 기준과 세금이 달라진 실물 문서 = 정확히 셋: 인보이스 15335(215.04 → 215.05) · PO-02050(211.79 → 211.80) · PO-02051(4414.41 → 4414.29)
select pg_temp.chk('R4(시험 갈래) 세금이 달라진 실물 문서는 정확히 셋 — 인보이스 15335 +0.01 · PO-02050 +0.01 · PO-02051 −0.12',
  (select string_agg(x.txt, ' | ' order by x.txt) from (
     select 'invoice ' || i.invoice_number || ' ' || (e.value->>'tax_amount') || ' → ' || m.tax_amount as txt
       from t_pre p, jsonb_each(p.inv) e join public.po_invoice_money m on m.id = e.key::uuid join public.po_invoice i on i.id = m.id where m.tax_amount is distinct from (e.value->>'tax_amount')::numeric
     union all
     select 'po ' || l.po_number || ' ' || (e.value->>'tax_amount') || ' → ' || l.tax_amount
       from t_pre p, jsonb_each(p.po) e join public.po_list l on l.id = e.key::uuid where l.tax_amount is distinct from (e.value->>'tax_amount')::numeric) x),
  'invoice 15335 215.04 → 215.05 | po PO-02050 211.79 → 211.80 | po PO-02051 4414.41 → 4414.29');
\endif

-- ── 실물 비교 표(rollback 앞) — 기준(이 실행의 begin 앞) → 지금 · 세금이 달라진 문서 + 이름으로 고른 셋(확인 갈래에서는 앞 = 뒤) ──
\echo '── 실물 비교(앞 = 이 실행의 기준 · 뒤 = 트랜잭션 안) ──'
select 'invoice' as doc, i.invoice_number as number, i.status, (e.value->>'tax_amount') as tax_before, m.tax_amount as tax_after, (e.value->>'computed_total') as computed_before, m.computed_total as computed_after,
       (e.value->>'diff') as diff_before, m.diff as diff_after, (e.value->>'payable_net') as net_before, m.payable_net as net_after, (e.value->>'unpaid') as unpaid_before, m.unpaid as unpaid_after, m.alloc_total
  from t_pre p, jsonb_each(p.inv) e join public.po_invoice_money m on m.id = e.key::uuid join public.po_invoice i on i.id = m.id
 where m.tax_amount is distinct from (e.value->>'tax_amount')::numeric or i.id = '697fb03d-909c-4807-b786-f6236b99c7ce'
union all
select 'po', l.po_number, l.status, (e.value->>'tax_amount'), l.tax_amount, (e.value->>'total_with_tax'), l.total_with_tax, null, null, null, null, null, null, null
  from t_pre p, jsonb_each(p.po) e join public.po_list l on l.id = e.key::uuid
 where l.tax_amount is distinct from (e.value->>'tax_amount')::numeric or l.po_number in ('PO-02050', 'PO-02051')
order by 1, 2;

-- ── 결과(rollback 앞 — t_res 줄은 트랜잭션 안에서 들어갔다) ──
\echo '── 결과(상호 없음 · 가짜 행은 rollback) ──'
select case when ok then 'OK   ' else 'FAIL ' end || label || case when ok then '' else format(' — got %s · want %s', coalesce(got, '(null)'), coalesce(want, '(null)')) end as line from t_res order by n;
select format('OK %s · FAIL %s · EXPECT %s', count(*) filter (where ok), count(*) filter (where not ok), :EXPECT_OK) as summary from t_res \gset
\echo :summary
select round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s;
rollback;
select (select count(*) from public.po_invoice where invoice_number like 'ZZTO1-%') + (select count(*) from public.po where po_number in ('PO-79451', 'PO-79452')) + (select count(*) from public.supplier where name = 'ZZ-TO1 Supplier') as fake_rows_left;
