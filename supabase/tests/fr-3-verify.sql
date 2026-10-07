-- fr-3-verify.sql — 운임 할인 크레딧(판정 355 · 352 · 354 · 358) · 무변 · 전부 · 나눠 · 끝수 · 금액형 · 100% · 한도 둘 · 오더 할인 · 리스탁킹 피 무관 · prepare 열쇠 · CHECK (Asung-IMS · 2026-10-07)
--   기대: 시험 갈래 OK 25 · 확인 갈래(G0 셋 없음) OK 22 · MISMATCH 0(시험 적용 2회차 통과 · 2026-10-07) · 재료는 가짜만(SO-7997x · FR3-* · 가짜 손님 · 직원 · 가짜 크레딧 CR-79997 은 번호 직접) · 실제 인보이스 · 크레딧 무접촉
--   ⚠️ 인보이스 발행(so_invoice_issue)과 크레딧 발행(so_credit_issue)이 시퀀스 둘을 당긴다 — 머리에서 읽고 rollback 뒤 greatest(실제 최대, 머리)로 되돌린다(asung-workflow §4 · §49-d 3)
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261007181109_fr_3_freight_discount_credit.sql -f supabase/tests/fr-3-verify.sql 2>&1 | tee /tmp/fr-3.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다(D-pre 는 확인 갈래에서 새 함수)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
select max(invoice_number)::bigint as inv_max_head from public.so_invoice \gset
select max(substr(credit_number, 4))::bigint as cr_max_head from public.so_credit \gset
\echo '== seq head so' :so_seq_last :so_seq_called 'inv' :inv_seq_last :inv_seq_called '(max' :inv_max_head ') cr' :cr_seq_last :cr_seq_called '(max' :cr_max_head ')'
select count(*) as n_inv from public.so_invoice \gset
select count(*) as n_cr from public.so_credit \gset
\echo '== invoices' :n_inv '· credits' :n_cr

begin;
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create temp table t_pre as
  select p.proname as n, p.prosrc as src from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public'
   and p.proname in ('so_credit_issue', 'so_credit_prepare', 'so_credit_cancel', 'so_credit_detail', 'so_credit_remaining', 'so_invoice_issue', 'so_tax_preview');
do $$
declare v_src text;
begin
  select src into v_src from t_pre where n = 'so_credit_issue';
  execute format('create function public.fr3_pre_credit(p jsonb, p_commit boolean default true) returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as %L', v_src);
end $$;
grant execute on function public.fr3_pre_credit(jsonb, boolean) to authenticated;
\if :{?mig}
select pg_temp.chk('G0a so_credit_issue last def = 20261006204146:1075~1421', (select md5(src) from t_pre where n = 'so_credit_issue'), '953552f1d73ef2d5c57bc3e04c3eb01a');
select pg_temp.chk('G0b so_credit_prepare last def = 20261006000805:1313~1368', (select md5(src) from t_pre where n = 'so_credit_prepare'), '6d82480a483e80b174ba4f5fe42885d6');
select pg_temp.chk('G0c fr-2 credit guard present before trial', (to_regprocedure('public.so_credit_line_freight_discount_guard()') is not null)::text, 'true');
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create function pg_temp.clines(p_cr uuid) returns text language sql as $$
  select string_agg(l.line_no || ':' || l.kind || '|' || coalesce(l.description, '') || '|' || trim_scale(l.amount) || '|' || trim_scale(l.tax_amount) || '|' || coalesce(l.account_code, '-'), ' ‖ ' order by l.line_no) from public.so_credit_line l where l.credit_id = p_cr
$$;
create function pg_temp.chead(p_cr uuid) returns text language sql as $$
  select trim_scale(c.lines_amount) || '/' || trim_scale(c.order_discount_amount) || '/' || trim_scale(c.freight_discount_amount) || '/' || trim_scale(c.fee_amount) || '/' || trim_scale(c.surcharge_amount) || '/' || trim_scale(c.tax_amount) || '/' || trim_scale(c.total) from public.so_credit c where c.id = p_cr
$$;
create function pg_temp.canon_cr(p_cr uuid) returns text language sql as $$
  select coalesce((select string_agg(l.kind || '|' || coalesce(l.description, '') || '|' || trim_scale(l.amount) || '|' || trim_scale(l.tax_amount) || '|' || coalesce(l.account_code, '-') || '|' || coalesce(l.so_invoice_line_id::text, '-'), E'\n' order by l.line_no) from public.so_credit_line l where l.credit_id = p_cr), '')
         || E'\nH|' || (select trim_scale(c.lines_amount) || '|' || trim_scale(c.order_discount_amount) || '|' || trim_scale(c.fee_amount) || '|' || trim_scale(c.surcharge_amount) || '|' || trim_scale(c.tax_amount) || '|' || trim_scale(c.total) from public.so_credit c where c.id = p_cr)
$$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'no-error'; exception when others then return sqlerrm; end $$;
create function pg_temp.fd_sum(p_inv uuid) returns text language sql as $$
  select trim_scale(coalesce(-sum(cl.amount), 0)) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id join public.so_invoice_line il on il.id = cl.so_invoice_line_id where il.invoice_id = p_inv and cl.kind = 'freight_discount' and c.status = 'issued'
$$;

-- ═══ 재료 — 직원(manager · sales) · 손님 · 제품 · HST ON 13% · shipped 가짜 오더 → 인보이스: A(제품 100 + 운임 50 · 할인 없음) · B(174.26 · 50%) · C(100 · 50%) · D(100 · 금액 30) · E(제품 100 + 오더 할인 10% + 운임 100 · 50%) · F(100 · 100%) · G(1.00 · 금액 0.49 · 순액 한도 시험) ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'fr3-manager@test.invalid', 'FR3 Manager', 'manager', '["sales"]'::jsonb) returning id::text as m_id, auth_user_id::text as m_uid \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
select id::text as tier, name as tier_name from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
select id::text as cad from public.ref_currency where code = 'CAD' limit 1 \gset
select id::text as whx, name as whx_name from public.ref_warehouse where name = 'Asung Trading Inc.' \gset
select id::text as r13, name as r13_name from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
select id::text as acc99 from public.ref_account where code = '_99_' \gset
select id::text as acc6 from public.ref_account where code = '_6_' \gset
insert into public.ref_brand (name) values ('FR3 Brand') returning id::text as br \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct) values ('FR3 Customer', 'manual', :'tier_name', :'whx'::uuid, 0) returning id::text as cust \gset
insert into public.product (sku, name, source, brand_id) values ('FR3-P', 'FR3 Product P', 'manual', :'br'::uuid) returning id::text as pp \gset
set local session_replication_role = replica;
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79971', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR3 Customer', now(), now(), null, null) returning id::text as o_a \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79972', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR3 Customer', now(), now(), null, null) returning id::text as o_b \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79973', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR3 Customer', now(), now(), null, null) returning id::text as o_c \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79974', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR3 Customer', now(), now(), null, null) returning id::text as o_d \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79975', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR3 Customer', now(), now(), 10, 'manual') returning id::text as o_e \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79976', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR3 Customer', now(), now(), null, null) returning id::text as o_f \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id, status, order_date, price_tier_id, discount_pct, tax_rule_id, tax_rule, tax_rule_manual, location_id, location_name, bill_to_customer_id, bill_to_name, confirmed_at, shipped_at, order_discount_pct, order_discount_source) values ('SO-79977', :'cust'::uuid, 'warehouse', 'manual', :'cad'::uuid, 'shipped', public.ims_today(), :'tier'::uuid, 0, :'r13'::uuid, :'r13_name', true, :'whx'::uuid, :'whx_name', :'cust'::uuid, 'FR3 Customer', now(), now(), null, null) returning id::text as o_g \gset
insert into public.so_line (so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, list_price, unit_price) values (:'o_a'::uuid, 1, :'pp'::uuid, 'FR3-P', 'FR3 Product P', 1, 2, 2, 100, 100);
insert into public.so_line (so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, list_price, unit_price) values (:'o_e'::uuid, 1, :'pp'::uuid, 'FR3-P', 'FR3 Product P', 1, 1, 1, 100, 100);
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code) values (:'o_a'::uuid, 1, 'Freight', 50, :'r13_name', :'acc99'::uuid, '_99_');
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code, discount_pct) values (:'o_b'::uuid, 1, 'Freight', 174.26, :'r13_name', :'acc99'::uuid, '_99_', 50);
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code, discount_pct) values (:'o_c'::uuid, 1, 'Freight', 100, :'r13_name', :'acc99'::uuid, '_99_', 50);
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code, discount_amount) values (:'o_d'::uuid, 1, 'Freight', 100, :'r13_name', :'acc99'::uuid, '_99_', 30);
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code, discount_pct) values (:'o_e'::uuid, 1, 'Freight', 100, :'r13_name', :'acc99'::uuid, '_99_', 50);
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code, discount_pct) values (:'o_f'::uuid, 1, 'Freight', 100, :'r13_name', :'acc99'::uuid, '_99_', 100);
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_id, account_code, discount_amount) values (:'o_g'::uuid, 1, 'Freight', 1.00, :'r13_name', :'acc99'::uuid, '_99_', 0.49);
set local session_replication_role = origin;
select (public.so_invoice_issue(array[:'o_a'::uuid], :'m_id'::uuid)->>'invoice_id') as inv_a \gset
select (public.so_invoice_issue(array[:'o_b'::uuid], :'m_id'::uuid)->>'invoice_id') as inv_b \gset
select (public.so_invoice_issue(array[:'o_c'::uuid], :'m_id'::uuid)->>'invoice_id') as inv_c \gset
select (public.so_invoice_issue(array[:'o_d'::uuid], :'m_id'::uuid)->>'invoice_id') as inv_d \gset
select (public.so_invoice_issue(array[:'o_e'::uuid], :'m_id'::uuid)->>'invoice_id') as inv_e \gset
select (public.so_invoice_issue(array[:'o_f'::uuid], :'m_id'::uuid)->>'invoice_id') as inv_f \gset
select (public.so_invoice_issue(array[:'o_g'::uuid], :'m_id'::uuid)->>'invoice_id') as inv_g \gset
select l.id::text as il_a_p from public.so_invoice_line l where l.invoice_id = :'inv_a'::uuid and l.kind = 'product' \gset
select l.id::text as il_a_c from public.so_invoice_line l where l.invoice_id = :'inv_a'::uuid and l.kind = 'charge' \gset
select l.id::text as il_b from public.so_invoice_line l where l.invoice_id = :'inv_b'::uuid and l.kind = 'charge' \gset
select l.id::text as il_b_d from public.so_invoice_line l where l.invoice_id = :'inv_b'::uuid and l.kind = 'charge_discount' \gset
select l.id::text as il_c from public.so_invoice_line l where l.invoice_id = :'inv_c'::uuid and l.kind = 'charge' \gset
select l.id::text as il_d from public.so_invoice_line l where l.invoice_id = :'inv_d'::uuid and l.kind = 'charge' \gset
select l.id::text as il_e_p from public.so_invoice_line l where l.invoice_id = :'inv_e'::uuid and l.kind = 'product' \gset
select l.id::text as il_e_c from public.so_invoice_line l where l.invoice_id = :'inv_e'::uuid and l.kind = 'charge' \gset
select l.id::text as il_f from public.so_invoice_line l where l.invoice_id = :'inv_f'::uuid and l.kind = 'charge' \gset
select l.id::text as il_g from public.so_invoice_line l where l.invoice_id = :'inv_g'::uuid and l.kind = 'charge' \gset
select pg_temp.chk('M0 seven invoices issued · B has charge + charge_discount (fr-2) · C/D/E/F/G discounted', (select count(*) from public.so_invoice where id in (:'inv_a'::uuid, :'inv_b'::uuid, :'inv_c'::uuid, :'inv_d'::uuid, :'inv_e'::uuid, :'inv_f'::uuid, :'inv_g'::uuid))::text || '/' || (select count(*) from public.so_invoice_line where invoice_id = :'inv_b'::uuid) || '/' || (select count(*) from public.so_invoice_line where kind = 'charge_discount' and invoice_id in (:'inv_c'::uuid, :'inv_d'::uuid, :'inv_e'::uuid, :'inv_f'::uuid, :'inv_g'::uuid)), '7/2/5');

-- ═══ U 무변 — 할인 없는 A: 제품 1(안 돌아옴) + 운임 50 전부 — 옛 함수(savepoint) 와 새 함수의 줄 · 머리 같다 ═══
\set p_a '{"invoice_id":"' :inv_a '","reason":"customer_return","warehouse_id":"' :whx '","lines":[{"kind":"product","so_invoice_line_id":"' :il_a_p '","qty_returned":1,"not_restocked_reason":"not_returned"},{"kind":"freight","so_invoice_line_id":"' :il_a_c '","amount":50}]}'
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
savepoint sp;
select (public.fr3_pre_credit(:'p_a'::jsonb, true)->>'credit_id') as cr_pre \gset
select pg_temp.canon_cr(:'cr_pre'::uuid) as c_pre \gset
rollback to savepoint sp;
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_credit_issue(:'p_a'::jsonb, true) as r \gset ua_
reset role;
select (:'ua_r'::jsonb->>'credit_id') as cr_a \gset
select pg_temp.chk('U1 A (no discount): new credit = old credit (lines · header · ids excluded) · freight_discount_amount 0', (pg_temp.canon_cr(:'cr_a'::uuid) = :'c_pre')::text || '/' || (select trim_scale(freight_discount_amount) from public.so_credit where id = :'cr_a'::uuid), 'true/0');
select pg_temp.chk('U1b A lines: product 100/13 · freight 50/6.50 · header 150/0/0/0/0/19.50/169.50', pg_temp.clines(:'cr_a'::uuid) || ' » ' || pg_temp.chead(:'cr_a'::uuid), '1:product|FR3 Product P|100|13|- ‖ 2:freight|Freight|50|6.5|_99_ » 150/0/0/0/0/19.5/169.5');

-- ═══ N 전부 돌려줌 — C: 운임 100 · 50% → Freight 100/13 · Freight discount 50% −50/−6.50 · 손님에게 56.50 · 계정 _6_ · 할인 줄은 인보이스 charge_discount 줄을 가리킨다 ═══
\set p_c '{"invoice_id":"' :inv_c '","reason":"other","note":"fr-3 verify","warehouse_id":"' :whx '","lines":[{"kind":"freight","so_invoice_line_id":"' :il_c '","amount":100}]}'
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_credit_issue(:'p_c'::jsonb, false) as r \gset nc_pre_
select public.so_credit_issue(:'p_c'::jsonb, true) as r \gset nc_
reset role;
select (:'nc_r'::jsonb->>'credit_id') as cr_c \gset
select pg_temp.chk('N1 C full: lines freight 100/13 _99_ ‖ freight_discount "Freight discount 50%" −50/−6.50 _6_ · header lines 100 · fd −50 · tax 6.50 · total 56.50 · preview = commit totals', pg_temp.clines(:'cr_c'::uuid) || ' » ' || pg_temp.chead(:'cr_c'::uuid) || ' » ' || (select bool_and((:'nc_pre_r'::jsonb->'totals'->>k) = (:'nc_r'::jsonb->'totals'->>k)) from unnest(array['lines_amount', 'freight_discount_amount', 'fee_amount', 'tax_amount', 'total']) k)::text || '/' || (:'nc_pre_r'::jsonb->'totals'->>'freight_discount_amount'), '1:freight|Freight|100|13|_99_ ‖ 2:freight_discount|Freight discount 50%|-50|-6.5|_6_ » 100/0/-50/0/0/6.5/56.5 » true/-50.00');
select pg_temp.chk('N1b discount credit line points at the invoice charge_discount line · account copied from it', (select (l.so_invoice_line_id = il.id and l.account_id = il.account_id)::text from public.so_credit_line l join public.so_invoice_line il on il.invoice_id = :'inv_c'::uuid and il.kind = 'charge_discount' where l.credit_id = :'cr_c'::uuid and l.kind = 'freight_discount'), 'true');

-- ═══ P 나눠 돌려줌 + 끝수 — B 174.26 · 50%(할인 87.13): 100 → −50.00 · 74.26(마지막) → −37.13 · 합 정확히 87.13 · prepare 열쇠 ═══
select pg_temp.chk('P0 prepare B before any credit: charge line discount_amount 87.13 · net_amount 87.13 · discount_credited 0 · net_credited 0 · net_remaining 87.13 · discount_line_id = the charge_discount line', (select (l->>'discount_amount') || '/' || (l->>'net_amount') || '/' || (l->>'discount_credited') || '/' || (l->>'net_credited') || '/' || (l->>'net_remaining') || '/' || (l->>'discount_line_id' = :'il_b_d')::text from jsonb_array_elements(public.so_credit_prepare(:'inv_b'::uuid)->'lines') l where l->>'kind' = 'charge'), '87.13/87.13/0/0/87.13/true');
\set p_b1 '{"invoice_id":"' :inv_b '","reason":"other","note":"fr-3 part 1","warehouse_id":"' :whx '","lines":[{"kind":"freight","so_invoice_line_id":"' :il_b '","amount":100}]}'
\set p_b2 '{"invoice_id":"' :inv_b '","reason":"other","note":"fr-3 part 2","warehouse_id":"' :whx '","lines":[{"kind":"freight","so_invoice_line_id":"' :il_b '","amount":74.26}]}'
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_credit_issue(:'p_b1'::jsonb, true) as r \gset nb1_
reset role;
select (:'nb1_r'::jsonb->>'credit_id') as cr_b1 \gset
select pg_temp.chk('P1 B part 1 (100 of 174.26): discount −50.00 (round(100 × 87.13/174.26, 2)) · tax 13.00 − 6.50 · total 56.50', pg_temp.clines(:'cr_b1'::uuid) || ' » ' || pg_temp.chead(:'cr_b1'::uuid), '1:freight|Freight|100|13|_99_ ‖ 2:freight_discount|Freight discount 50%|-50|-6.5|_6_ » 100/0/-50/0/0/6.5/56.5');
select pg_temp.chk('P1b prepare B after part 1: amount_credited 100 · discount_credited 50 · net_credited 50 · net_remaining 37.13', (select trim_scale((l->>'amount_credited')::numeric) || '/' || trim_scale((l->>'discount_credited')::numeric) || '/' || trim_scale((l->>'net_credited')::numeric) || '/' || trim_scale((l->>'net_remaining')::numeric) from jsonb_array_elements(public.so_credit_prepare(:'inv_b'::uuid)->'lines') l where l->>'kind' = 'charge'), '100/50/50/37.13');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_credit_issue(:'p_b2'::jsonb, true) as r \gset nb2_
reset role;
select (:'nb2_r'::jsonb->>'credit_id') as cr_b2 \gset
select pg_temp.chk('P2 B part 2 (74.26 · last): discount = remaining 37.13 (not round(37.13) by chance — exact remainder) · tax 9.65 − 4.83 · total 41.95 · discount sum over both = 87.13 exactly', pg_temp.clines(:'cr_b2'::uuid) || ' » ' || pg_temp.chead(:'cr_b2'::uuid) || ' » ' || pg_temp.fd_sum(:'inv_b'::uuid), '1:freight|Freight|74.26|9.65|_99_ ‖ 2:freight_discount|Freight discount 50%|-37.13|-4.83|_6_ » 74.26/0/-37.13/0/0/4.82/41.95 » 87.13');
select pg_temp.chk('P2b prepare B after both: net_remaining 0 · net_credited 87.13', (select (l->>'net_remaining') || '/' || (l->>'net_credited') from jsonb_array_elements(public.so_credit_prepare(:'inv_b'::uuid)->'lines') l where l->>'kind' = 'charge'), '0.00/87.13');
-- 끝수 둘째 예: D 100 · 금액 30 → 40 먼저(−12.00) · 60 마지막(−18.00 = 남은 할인) · 합 30
\set p_d1 '{"invoice_id":"' :inv_d '","reason":"other","note":"fr-3 d1","warehouse_id":"' :whx '","lines":[{"kind":"freight","so_invoice_line_id":"' :il_d '","amount":40}]}'
\set p_d2 '{"invoice_id":"' :inv_d '","reason":"other","note":"fr-3 d2","warehouse_id":"' :whx '","lines":[{"kind":"freight","so_invoice_line_id":"' :il_d '","amount":60}]}'
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_credit_issue(:'p_d1'::jsonb, true) as r \gset nd1_
select public.so_credit_issue(:'p_d2'::jsonb, true) as r \gset nd2_
reset role;
select pg_temp.chk('P3 D amount-type 30: 40 → −12.00/−1.56 (description "Freight discount") · 60 (last) → −18.00/−2.34 · sum 30', pg_temp.clines((:'nd1_r'::jsonb->>'credit_id')::uuid) || ' » ' || pg_temp.clines((:'nd2_r'::jsonb->>'credit_id')::uuid) || ' » ' || pg_temp.fd_sum(:'inv_d'::uuid), '1:freight|Freight|40|5.2|_99_ ‖ 2:freight_discount|Freight discount|-12|-1.56|_6_ » 1:freight|Freight|60|7.8|_99_ ‖ 2:freight_discount|Freight discount|-18|-2.34|_6_ » 30');

-- ═══ F 100% 무료 배송 — 운임 100 · 할인 100 → 크레딧 100 / −100 · 순액 0 · 세금 0 · total 0(허용 · 막지 않는다) ═══
\set p_f '{"invoice_id":"' :inv_f '","reason":"other","note":"fr-3 free","warehouse_id":"' :whx '","lines":[{"kind":"freight","so_invoice_line_id":"' :il_f '","amount":100}]}'
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_credit_issue(:'p_f'::jsonb, true) as r \gset nf_
reset role;
select pg_temp.chk('F1 100% free shipping: freight 100/13 ‖ discount −100/−13 · total 0 · allowed', pg_temp.clines((:'nf_r'::jsonb->>'credit_id')::uuid) || ' » ' || pg_temp.chead((:'nf_r'::jsonb->>'credit_id')::uuid), '1:freight|Freight|100|13|_99_ ‖ 2:freight_discount|Freight discount 100%|-100|-13|_6_ » 100/0/-100/0/0/0/0');

-- ═══ K 한도 — 정가 넘게(기존 문장) · 순액 넘게(새 문장 · G: 1.00 · 할인 0.49 · 옛 모양의 크레딧이 정가 0.60 을 할인 없이 가져갔다고 치고 0.40 더 → 거부) ═══
\set p_b3 '{"invoice_id":"' :inv_b '","reason":"other","note":"fr-3 over","warehouse_id":"' :whx '","lines":[{"kind":"freight","so_invoice_line_id":"' :il_b '","amount":0.01}]}'
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select pg_temp.try(format('select public.so_credit_issue(%L::jsonb, true)', :'p_b3')) as k1 \gset
reset role;
select pg_temp.chk('K1 B gross exhausted → existing gross-limit message', :'k1', (select format('Invoice %s charge %s : %s of %s already credited — only %s left — nothing was saved', i.invoice_number, il.line_no, trim_scale(il.amount), trim_scale(il.amount), il.amount - il.amount) from public.so_invoice i join public.so_invoice_line il on il.invoice_id = i.id and il.kind = 'charge' where i.id = :'inv_b'::uuid));
set local session_replication_role = replica;
insert into public.so_credit (credit_number, customer_id, currency_id, reason, warehouse_id, issued_on, invoice_id, lines_amount, tax_amount, total) values ('CR-79997', :'cust'::uuid, :'cad'::uuid, 'other', :'whx'::uuid, public.ims_today(), :'inv_g'::uuid, 0.60, 0.08, 0.68) returning id::text as cr_g_old \gset
insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, description, amount, tax_amount) values (:'cr_g_old'::uuid, 1, 'freight', :'il_g'::uuid, 'Freight (legacy · no discount line)', 0.60, 0.08);
set local session_replication_role = origin;
\set p_g '{"invoice_id":"' :inv_g '","reason":"other","note":"fr-3 net","warehouse_id":"' :whx '","lines":[{"kind":"freight","so_invoice_line_id":"' :il_g '","amount":0.40}]}'
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select pg_temp.try(format('select public.so_credit_issue(%L::jsonb, true)', :'p_g')) as k2 \gset
reset role;
select pg_temp.chk('K2 G net limit: paid 0.51 net (1.00 less 0.49) · 0.60 net already credited by a legacy credit · 0.40 asked (discount 0.49 remaining → net −0.09) → refused by the net check', :'k2', (select format('Invoice %s charge 1 : the customer paid 0.51 net (1.00 less 0.49 discount) — 0.60 net already credited and -0.09 asked now — only -0.09 left — nothing was saved', i.invoice_number) from public.so_invoice i where i.id = :'inv_g'::uuid));
select pg_temp.chk('K3 sending a freight_discount line by hand → refused', (select pg_temp.try(format('select public.so_credit_issue(%L::jsonb, false)', replace(:'p_c', '"kind":"freight"', '"kind":"freight_discount"')))), 'Freight discount lines are added automatically from the returned freight line — do not send them — nothing was saved');

-- ═══ O 오더 할인 · 리스탁킹 피 — E: 제품 1(not_returned) + 운임 100 전부 + 수수료 20% → order_discount −10/−1.30 · fee −18 (base 100 − 10 · 운임 밖) · freight_discount −50/−6.50 ═══
\set p_e '{"invoice_id":"' :inv_e '","reason":"customer_return","warehouse_id":"' :whx '","lines":[{"kind":"product","so_invoice_line_id":"' :il_e_p '","qty_returned":1,"not_restocked_reason":"not_returned"},{"kind":"freight","so_invoice_line_id":"' :il_e_c '","amount":100},{"kind":"restocking_fee","pct":20,"account_id":"' :acc6 '"}]}'
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_credit_issue(:'p_e'::jsonb, true) as r \gset ne_
reset role;
select pg_temp.chk('O1 E: product 100/13 ‖ freight 100/13 ‖ freight_discount −50/−6.50 ‖ order_discount −10/−1.30 ‖ restocking fee −18/−2.34 (base 90 · freight and its discount outside) · header 200/−10/−50/−18/0/15.86/137.86', pg_temp.clines((:'ne_r'::jsonb->>'credit_id')::uuid) || ' » ' || pg_temp.chead((:'ne_r'::jsonb->>'credit_id')::uuid), '1:product|FR3 Product P|100|13|- ‖ 2:freight|Freight|100|13|_99_ ‖ 3:freight_discount|Freight discount 50%|-50|-6.5|_6_ ‖ 4:order_discount|Order discount 10% (SO-79975)|-10|-1.3|- ‖ 5:restocking_fee|Restocking fee 20%|-18|-2.34|_6_ » 200/-10/-50/-18/0/15.86/137.86');

-- ═══ R so_credit_detail · CHECK · 가드 · 무접촉 · 권한 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.so_credit_detail(:'cr_c'::uuid) as d \gset rd_
reset role;
select pg_temp.chk('R1 so_credit_detail (staff): credit.freight_discount_amount −50 · line kinds freight,freight_discount', (:'rd_d'::jsonb->'credit'->>'freight_discount_amount') || '/' || (select string_agg(l->>'kind', ',' order by (l->>'line_no')::int) from jsonb_array_elements(:'rd_d'::jsonb->'lines') l), '-50.00/freight,freight_discount');
savepoint sp;
select pg_temp.try(format('insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, amount, tax_amount) values (%L::uuid, 99, ''freight_discount'', %L::uuid, 5, 0)', :'cr_c', :'il_b_d')) as c1 \gset
rollback to savepoint sp;
savepoint sp;
select pg_temp.try(format('insert into public.so_credit_line (credit_id, line_no, kind, amount, tax_amount) values (%L::uuid, 99, ''freight_discount'', -5, 0)', :'cr_c')) as c2 \gset
rollback to savepoint sp;
savepoint sp;
select pg_temp.try(format('insert into public.so_credit_line (credit_id, line_no, kind, amount, tax_amount) values (%L::uuid, 99, ''bogus'', 5, 0)', :'cr_c')) as c3 \gset
rollback to savepoint sp;
savepoint sp;
select pg_temp.try(format('update public.so_credit set freight_discount_amount = 1 where id = %L::uuid', :'cr_c')) as c4 \gset
rollback to savepoint sp;
savepoint sp;
select pg_temp.try(format('update public.so_credit set freight_discount_amount = freight_discount_amount - 1 where id = %L::uuid', :'cr_c')) as c5 \gset
rollback to savepoint sp;
select pg_temp.chk('C1 positive freight_discount → amount_ck · C2 no so_invoice_line_id → freight_discount_ck · C3 unknown kind → kind_ck · C4 header > 0 → freight_discount_ck · C5 header shifted → total_ck', (:'c1' like '%so_credit_line_amount_ck%')::text || '/' || (:'c2' like '%so_credit_line_freight_discount_ck%')::text || '/' || (:'c3' like '%so_credit_line_kind_ck%')::text || '/' || (:'c4' like '%so_credit_freight_discount_ck%')::text || '/' || (:'c5' like '%so_credit_total_ck%')::text, 'true/true/true/true/true');
select pg_temp.chk('V1 fr-2 credit guard gone (function · trigger)', (to_regprocedure('public.so_credit_line_freight_discount_guard()') is null)::text || '/' || (select count(*) from pg_trigger where tgname = 'so_credit_line_freight_discount_guard'), 'true/0');
select pg_temp.chk('G1 untouched md5 (so_credit_cancel · so_credit_detail · so_credit_remaining · so_invoice_issue · so_tax_preview = 5) · reissued two carry fr-3', (select count(*)::text from t_pre t join pg_proc p on p.proname = t.n join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public' where t.n not in ('so_credit_issue', 'so_credit_prepare') and md5(p.prosrc) = md5(t.src)) || '/' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_credit_issue', 'so_credit_prepare') and p.prosrc like '%fr-3%'), '5/2');
select pg_temp.chk('G2 acl: so_credit_issue · so_credit_prepare authenticated yes · anon no · one def each', has_function_privilege('authenticated', 'public.so_credit_issue(jsonb, boolean)', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_credit_issue(jsonb, boolean)', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.so_credit_prepare(uuid)', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_credit_prepare(uuid)', 'execute')::text || '/' || (select count(*) from pg_proc where proname in ('so_credit_issue', 'so_credit_prepare')), 'true/false/true/false/2');
select pg_temp.chk('G3 prepare vocab line_kinds unchanged (freight_discount is automatic) · undiscounted charge line (A) has null discount keys (vocab compared as jsonb)', ((public.so_credit_prepare(:'inv_a'::uuid)->'vocab'->'line_kinds') = '["product","freight","tax","other","restocking_fee"]'::jsonb)::text || '/' || (select coalesce(l->>'discount_amount', 'null') || '/' || (l->>'net_amount') from jsonb_array_elements(public.so_credit_prepare(:'inv_a'::uuid)->'lines') l where l->>'kind' = 'charge'), 'true/null/50');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
select 'inv seq inside ' || last_value || ' ' || is_called from public.so_invoice_number_seq;
select 'cr seq inside ' || last_value || ' ' || is_called from public.so_credit_number_seq;
rollback;
select setval('public.so_invoice_number_seq', greatest((select max(invoice_number)::bigint from public.so_invoice), :inv_seq_last), true);
select setval('public.so_credit_number_seq', greatest((select max(substr(credit_number, 4))::bigint from public.so_credit), :cr_seq_last), true);
select 'seq tail so ' || last_value || ' ' || is_called from public.so_number_seq;
select 'seq tail inv ' || last_value || ' ' || is_called || ' (max invoice ' || (select max(invoice_number) from public.so_invoice) || ' · head ' || :inv_seq_last || ')' from public.so_invoice_number_seq;
select 'seq tail cr ' || last_value || ' ' || is_called || ' (max credit ' || (select max(credit_number) from public.so_credit) || ' · head ' || :cr_seq_last || ')' from public.so_credit_number_seq;
select 'invoices tail ' || (select count(*) from public.so_invoice) || ' · credits tail ' || (select count(*) from public.so_credit);
