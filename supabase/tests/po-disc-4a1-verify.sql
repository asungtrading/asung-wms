-- po-disc-4a1-verify.sql — 인보이스 조기 결제 할인 조건 · 충당 할인(정본) · discount_taken Σ 트리거 · 문지기(결제 머리 · 충당 직접 쓰기) · po_invoice_create 제안 · po_invoice_list 칸 · po_payment_detail 경고 (Asung-IMS · 2026-10-09)
--   기대: 시험 갈래(-v mig) OK 21 · 확인 갈래 OK 19(= 21 − 시험 전용 2: G0 · D0a) · MISMATCH 0 · 실제 결제 · 충당 · 인보이스 md5 전후 같음(백필 칸은 따로 센다)
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/<ts>_po_disc_4a1.sql -f supabase/tests/po-disc-4a1-verify.sql > /tmp/po-disc-4a1.out 2>&1; echo "rc=$?"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료는 가짜만(PO-794xx · PODISC4A1-* · 가짜 공급처 · 결제조건 · 직원) · 실제 행은 읽기만 · 끝은 rollback
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as po_seq_last, is_called as po_seq_called from public.po_number_seq \gset
select last_value as rcv_seq_last, is_called as rcv_seq_called from public.po_receipt_number_seq \gset
\echo '== seq head po' :po_seq_last :po_seq_called 'rcv' :rcv_seq_last :rcv_seq_called
select md5(string_agg(p.id::text || '|' || p.paid_on::text || '|' || p.amount::text || '|' || p.discount_taken::text || '|' || coalesce(p.reference, '') || '|' || p.currency_id::text || '|' || coalesce(p.account_id::text, ''), ',' order by p.id)) as real_pay_head, count(*) as real_pay_n from public.po_payment p where coalesce(p.reference, '') not like 'PODISC4A1-%' \gset
select md5(string_agg(a.id::text || '|' || a.po_payment_id::text || '|' || coalesce(a.po_invoice_id::text, '') || '|' || coalesce(a.po_charge_id::text, '') || '|' || a.amount::text, ',' order by a.id)) as real_alloc_head, count(*) as real_alloc_n from public.po_payment_alloc a join public.po_payment p on p.id = a.po_payment_id where coalesce(p.reference, '') not like 'PODISC4A1-%' \gset
select md5(string_agg(i.id::text || '|' || i.invoice_number || '|' || i.status || '|' || i.total_amount::text || '|' || coalesce(i.due_date::text, ''), ',' order by i.id)) as real_inv_head, count(*) as real_inv_n from public.po_invoice i where i.invoice_number not like 'PODISC4A1-%' \gset
\echo '== real head payments' :real_pay_n :real_pay_head 'allocs' :real_alloc_n :real_alloc_head 'invoices' :real_inv_n :real_inv_head

begin;
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql security definer as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql security definer as $$
begin
  execute p_sql; return 'no-error';
exception when others then return sqlstate || ' ' || sqlerrm;
end $$;

-- ═══ 재료(postgres · 가짜) — 직원 둘 · 공급처 · 결제조건 둘 · 제품 둘 · PO 셋(조건 2.1%/13 · 2%/일수 없음 · 조건 없음) ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc4a1-buy@test.invalid',  'PODISC4A1 Purchasing', 'manager', '["purchasing"]'::jsonb) returning auth_user_id::text as g_uid, id::text as g_sid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc4a1-none@test.invalid', 'PODISC4A1 NoKeys',     'manager', '[]'::jsonb) returning auth_user_id::text as n_uid \gset
\set g_claims '{"sub":"' :g_uid '","role":"authenticated"}'
\set n_claims '{"sub":"' :n_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh from public.ref_warehouse where is_active order by name limit 1 \gset
select id::text as hst, name as hstname from public.ref_tax_rule where direction = 'purchase' and is_active and name = 'HST ON (Purchase)' limit 1 \gset
insert into public.ref_payment_term (name, source, net_days, discount_days, discount_percent) values ('PODISC4A1 2.1%13 Net30', 'manual', 30, 13, 2.1) returning id::text as t1 \gset
insert into public.ref_payment_term (name, source, net_days, discount_days, discount_percent) values ('PODISC4A1 2% Net30 (no days)', 'manual', 30, null, 2) returning id::text as t2 \gset
insert into public.supplier (name, payment_term_name, account_payable_code, currency_id) values ('PODISC4A1 Supplier', 'Net 30', '2000', :'cad'::uuid) returning id::text as sup \gset
insert into public.product (sku, name, source) values ('DISC4A1-P1', 'PODISC4A1 P1', 'manual') returning id::text as p1 \gset
insert into public.product (sku, name, source) values ('DISC4A1-P2', 'PODISC4A1 P2', 'manual') returning id::text as p2 \gset
set local session_replication_role = replica;
insert into public.po (po_number, status, supplier_id, currency_id, order_date, ship_to_warehouse_id, confirmed_at, payment_term_id, payment_term_name, tax_rule_id, tax_rule) values ('PO-79400', 'confirmed', :'sup'::uuid, :'cad'::uuid, '2026-10-01', :'wh'::uuid, now(), :'t1'::uuid, 'PODISC4A1 2.1%13 Net30', :'hst'::uuid, :'hstname') returning id::text as po0 \gset
insert into public.po (po_number, status, supplier_id, currency_id, order_date, ship_to_warehouse_id, confirmed_at, payment_term_id, payment_term_name, tax_rule_id, tax_rule) values ('PO-79401', 'confirmed', :'sup'::uuid, :'cad'::uuid, '2026-10-01', :'wh'::uuid, now(), :'t2'::uuid, 'PODISC4A1 2% Net30 (no days)', :'hst'::uuid, :'hstname') returning id::text as po1 \gset
insert into public.po (po_number, status, supplier_id, currency_id, order_date, ship_to_warehouse_id, confirmed_at, payment_term_id, payment_term_name, tax_rule_id, tax_rule) values ('PO-79402', 'confirmed', :'sup'::uuid, :'cad'::uuid, '2026-10-01', :'wh'::uuid, now(), null, null, :'hst'::uuid, :'hstname') returning id::text as po2 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po0'::uuid, 1, :'p1'::uuid, 100, 10.00), (:'po0'::uuid, 2, :'p2'::uuid, 50, 4.00), (:'po1'::uuid, 1, :'p1'::uuid, 10, 10.00), (:'po2'::uuid, 1, :'p2'::uuid, 10, 4.00);
set local session_replication_role = origin;
select pg_temp.chk('M fake material: terms 2 · POs 3 · lines 4 · every real payment with a discount has one allocation (backfill precondition)', (select count(*) from public.ref_payment_term where name like 'PODISC4A1%')::text || '/' || (select count(*) from public.po where po_number like 'PO-794%') || '/' || (select count(*) from public.po_line pl join public.po x on x.id = pl.po_id where x.po_number like 'PO-794%') || '/' || (select count(*) from public.po_payment p where p.discount_taken > 0 and (select count(*) from public.po_payment_alloc a where a.po_payment_id = p.id) <> 1), '2/3/4/0');

-- ═══ D0 · G0 — 적용 전(시험 갈래): 칸 없음 · 재발행 원본 md5 · 목록 뷰 시간(적용 전) ═══
select clock_timestamp() as tl0 \gset
select count(*) as lv_n0, coalesce(sum(length(invoice_number)), 0) as lv_s0 from public.po_invoice_list \gset
select clock_timestamp() as tl1 \gset
select 'timing: po_invoice_list full scan (before) ms=' || round(extract(epoch from (:'tl1'::timestamptz - :'tl0'::timestamptz)) * 1000) || ' rows=' || :lv_n0;
\if :{?mig}
select pg_temp.chk('G0 last defs: po_invoice_create 74f6853c · po_payment_create 77dfdde7 · po_payment_alloc_set 94c873da · po_payment_detail 612d5faa · po_invoice_list viewdef 3401ace3', (select string_agg(left(md5(p.prosrc), 8), ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('po_invoice_create', 'po_payment_create', 'po_payment_alloc_set', 'po_payment_detail')) || '/' || left(md5(pg_get_viewdef('public.po_invoice_list'::regclass)), 8), '74f6853c,94c873da,77dfdde7,612d5faa/3401ace3');
select pg_temp.chk('D0a before: no early_discount columns · no alloc discount_amount · no guard triggers · direct update of discount_taken is possible (defect)', (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_invoice' and column_name like 'early\_discount\_%')::text || '/' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_payment_alloc' and column_name = 'discount_amount') || '/' || (select count(*) from pg_trigger where not tgisinternal and tgname in ('po_payment_guard', 'po_payment_alloc_guard', 'po_payment_alloc_discount_sync', 'po_invoice_early_lock')) || '/' || pg_temp.err('update public.po_payment set discount_taken = discount_taken where false'), '0/0/0/no-error');
\i :mig
\endif
select pg_temp.chk('D0b after: columns 4 + 1 · triggers 4 · functions 2 · po_invoice_list 44 columns', (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_invoice' and column_name like 'early\_discount\_%')::text || '/' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_payment_alloc' and column_name = 'discount_amount') || '/' || (select count(*) from pg_trigger where not tgisinternal and tgname in ('po_payment_guard', 'po_payment_alloc_guard', 'po_payment_alloc_discount_sync', 'po_invoice_early_lock')) || '/' || (to_regprocedure('public.po_early_discount_calc(numeric, numeric, text, date, numeric, numeric, date)') is not null and to_regprocedure('public.po_invoice_early_discount(uuid, date)') is not null)::text || '/' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_invoice_list'), '4/1/4/true/44');
select pg_temp.chk('G1 untouched: po_invoice_money 08f428cb · po_charge_money d6c4df08 · po_payment_alloc_delete f80a194d · po_doc_delete 8864a994 · po_payment_target_check c874cde8 · inv_layer_post_cost_adjust 1f95d60c', left(md5(pg_get_viewdef('public.po_invoice_money'::regclass)), 8) || '/' || left(md5(pg_get_viewdef('public.po_charge_money'::regclass)), 8) || '/' || (select string_agg(left(md5(p.prosrc), 8), ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('po_payment_alloc_delete', 'po_doc_delete', 'po_payment_target_check', 'inv_layer_post_cost_adjust')), '08f428cb/d6c4df08/1f95d60c,8864a994,f80a194d,c874cde8');
select pg_temp.chk('B14 backfill: real allocs with discount_amount > 0 = 2 (EFT-20260916-02 50.95 · P&G 952.08) · every payment discount_taken = Σ alloc discount', (select string_agg(coalesce(p.reference, 'ref:' || i.invoice_number) || ':' || trim_scale(a.discount_amount)::text, ',' order by p.paid_on) from public.po_payment_alloc a join public.po_payment p on p.id = a.po_payment_id left join public.po_invoice i on i.id = a.po_invoice_id where a.discount_amount > 0 and coalesce(p.reference, '') not like 'PODISC4A1-%') || '/' || (select count(*) from public.po_payment p left join (select po_payment_id, sum(discount_amount) s from public.po_payment_alloc group by 1) q on q.po_payment_id = p.id where p.discount_taken is distinct from coalesce(q.s, 0)), 'EFT-20260916-02:50.95,ref:1030266656:952.08/0');
select clock_timestamp() as tl2 \gset
select count(*) as lv_n1, coalesce(sum(length(invoice_number)), 0) as lv_s1, coalesce(sum(early_discount_value), 0) as lv_ed from public.po_invoice_list \gset
select clock_timestamp() as tl3 \gset
select 'timing: po_invoice_list full scan (after) ms=' || round(extract(epoch from (:'tl3'::timestamptz - :'tl2'::timestamptz)) * 1000) || ' rows=' || :lv_n1 || ' Σearly_discount_value=' || :lv_ed;
select pg_temp.chk('L0 po_invoice_list same rows after reissue · real invoices have no terms yet (Σ value 0)', (:lv_n1 = :lv_n0)::text || '/' || trim_scale(:lv_ed)::text, 'true/0');

-- ═══ B1 — po_invoice_create 제안(purchasing 직원) — 2.1%/13 → pct 2.1 · basis pre_tax · until +13 · 일수 없음 → until null + 경고 · 조건 없음 → null 셋 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_invoice_create('invoice', 'PODISC4A1-I1', :'po0'::uuid, null, null, '2026-10-08', null, 1356.00, true, true, null) as r \gset c1_
select public.po_invoice_create('invoice', 'PODISC4A1-I2', :'po1'::uuid, null, null, '2026-10-08', null, 113.00, true, true, null) as r \gset c2_
select public.po_invoice_create('invoice', 'PODISC4A1-I3', :'po2'::uuid, null, null, '2026-10-08', null, 45.20, true, true, null) as r \gset c3_
select public.po_invoice_create('invoice', 'PODISC4A1-I4', :'po0'::uuid, null, null, '2026-10-08', null, 0, true, false, null) as r \gset c4_
reset role;
select (:'c1_r'::jsonb->>'id') as i1 \gset
select (:'c2_r'::jsonb->>'id') as i2 \gset
select (:'c3_r'::jsonb->>'id') as i3 \gset
select pg_temp.chk('B1a I1 (2.1%/13): pct 2.1 · basis pre_tax · until 2026-10-21 · amount null · suggested {pct 2.1, until, term} · lines 2 · no no_deadline warning', (select trim_scale(i.early_discount_pct)::text || '/' || i.early_discount_basis || '/' || i.early_discount_until::text || '/' || coalesce(i.early_discount_amount::text, 'null') from public.po_invoice i where i.id = :'i1'::uuid) || '/' || trim_scale((:'c1_r'::jsonb->'early_discount_suggested'->>'pct')::numeric)::text || '/' || (:'c1_r'::jsonb->'early_discount_suggested'->>'until') || '/' || (:'c1_r'::jsonb->'early_discount_suggested'->>'term_name') || '/' || (:'c1_r'::jsonb->>'line_count') || '/' || (:'c1_r'::jsonb->'warnings' ? 'early_discount_no_deadline')::text, '2.1/pre_tax/2026-10-21/null/2.1/2026-10-21/PODISC4A1 2.1%13 Net30/2/false');
select pg_temp.chk('B1b I2 (2% · no days): pct 2 · until null · warning early_discount_no_deadline · I3 (no term): all null · suggested null · I4 preview (no commit) still suggests', (select trim_scale(i.early_discount_pct)::text || '/' || coalesce(i.early_discount_until::text, 'null') from public.po_invoice i where i.id = :'i2'::uuid) || '/' || (:'c2_r'::jsonb->'warnings' ? 'early_discount_no_deadline')::text || '/' || (select (i.early_discount_pct is null and i.early_discount_basis is null and i.early_discount_until is null)::text from public.po_invoice i where i.id = :'i3'::uuid) || '/' || (:'c3_r'::jsonb->'early_discount_suggested')::text || '/' || (:'c4_r'::jsonb->>'committed') || '/' || (:'c4_r'::jsonb->'early_discount_suggested'->>'pct'), '2/null/true/true/null/false/2.1');

-- ═══ T — 짝 CHECK 모양(⬜10) · 식 함수 값 · 사람이 고칠 수 있다(충당 없음) ═══
select pg_temp.chk('T CHECK: pct+amount both · basis without terms · until without terms · bad basis · pct 0 → 23514 ×5', (select string_agg(left(pg_temp.err(format(q, :'i3')), 5), ',') from unnest(array[
  'update public.po_invoice set early_discount_pct = 2, early_discount_amount = 5, early_discount_basis = ''pre_tax'' where id = %L',
  'update public.po_invoice set early_discount_basis = ''pre_tax'' where id = %L',
  'update public.po_invoice set early_discount_until = ''2026-12-01'' where id = %L',
  'update public.po_invoice set early_discount_pct = 2, early_discount_basis = ''net'' where id = %L',
  'update public.po_invoice set early_discount_pct = 0, early_discount_basis = ''pre_tax'' where id = %L']) q), '23514,23514,23514,23514,23514');
select pg_temp.chk('F1 I1 money: payable_taxable 1200 · tax 156 · payable_net 1356 · calc on 2026-10-21: discount 25.20 · valid · days_left 0 · on 10-22: invalid · days_left -1', (select trim_scale(m.payable_taxable)::text || '/' || trim_scale(m.payable_tax)::text || '/' || trim_scale(m.payable_net)::text from public.po_invoice_money m where m.id = :'i1'::uuid) || '/' || (select trim_scale(d.discount)::text || '/' || d.is_valid::text || '/' || d.days_left::text from public.po_invoice_early_discount(:'i1'::uuid, '2026-10-21') d) || '/' || (select d.is_valid::text || '/' || d.days_left::text from public.po_invoice_early_discount(:'i1'::uuid, '2026-10-22') d), '1200/156/1356/25.2/true/0/false/-1');
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
with u as (update public.po_invoice set early_discount_basis = 'with_tax' where id = :'i1'::uuid returning 1) select count(*) as e1 from u \gset
select trim_scale(d.discount)::text as f_wt from public.po_invoice_early_discount(:'i1'::uuid, null) d \gset
with u as (update public.po_invoice set early_discount_pct = null, early_discount_amount = 15, early_discount_basis = 'pre_tax' where id = :'i1'::uuid returning 1) select count(*) as e2 from u \gset
select trim_scale(d.discount)::text || '/' || d.has_terms::text as f_amt from public.po_invoice_early_discount(:'i1'::uuid, null) d \gset
with u as (update public.po_invoice set early_discount_pct = 2.1, early_discount_amount = null, early_discount_basis = 'pre_tax' where id = :'i1'::uuid returning 1) select count(*) as e3 from u \gset
select (d.has_terms::text || '/' || trim_scale(d.discount)::text || '/' || d.is_valid::text) as f_none from public.po_invoice_early_discount(:'i3'::uuid, null) d \gset
reset role;
select pg_temp.chk('F2 purchasing staff edits terms freely before any discount is taken: with_tax → 1356 × 2.1% = 28.48 · amount 15 → 15 · back to 2.1% pre_tax · I3 no terms → has_terms false · 0 · invalid', :e1 || '/' || :'f_wt' || '/' || :e2 || '/' || :'f_amt' || '/' || :e3 || '/' || :'f_none', '1/28.48/1/15/true/1/false/0/false');
select pg_temp.chk('L1 po_invoice_list I1: value 25.20 · valid today · I2 value 2.00 (2% of 100) valid (no deadline) · I3 value 0 · not valid', (select trim_scale(l.early_discount_value)::text || '/' || l.early_discount_valid_today::text from public.po_invoice_list l where l.id = :'i1'::uuid) || '/' || (select trim_scale(l.early_discount_value)::text || '/' || l.early_discount_valid_today::text from public.po_invoice_list l where l.id = :'i2'::uuid) || '/' || (select trim_scale(l.early_discount_value)::text || '/' || l.early_discount_valid_today::text from public.po_invoice_list l where l.id = :'i3'::uuid), '25.2/true/2/true/0/false');

-- ═══ B7 · B6 — 결제 창구(옛 모양): 대상 하나 + p_discount_taken → 그 충당에 · 둘 + 할인 → 거부 · 원소 discount 열쇠 → 거부 · Σ 트리거 ═══
set local session_replication_role = replica;
update public.po_invoice set status = 'confirmed', confirmed_at = now() where id in (:'i1'::uuid, :'i2'::uuid, :'i3'::uuid);
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 1330.80, :'cad'::uuid, 25.20, null, 'PODISC4A1-PAY1', null, jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', :'i1', 'amount', 1356)), true) as r \gset pay1_
select pg_temp.err(format('select public.po_payment_create(%L::uuid, ''2026-10-10'', 133.00, %L::uuid, 25.20, null, ''PODISC4A1-PAY2'', null, jsonb_build_array(jsonb_build_object(''kind'', ''invoice'', ''id'', %L, ''amount'', 113), jsonb_build_object(''kind'', ''invoice'', ''id'', %L, ''amount'', 45.20)), true)', :'sup', :'cad', :'i2', :'i3')) as b7_two \gset
select pg_temp.err(format('select public.po_payment_create(%L::uuid, ''2026-10-10'', 100, %L::uuid, 0, null, ''PODISC4A1-PAY3'', null, jsonb_build_array(jsonb_build_object(''kind'', ''invoice'', ''id'', %L, ''amount'', 113, ''discount'', 13)), false)', :'sup', :'cad', :'i2')) as b7_key \gset
reset role;
select (:'pay1_r'::jsonb->>'payment_id') as pay1 \gset
select pg_temp.chk('B7a one target + p_discount_taken 25.20: alloc discount_amount 25.20 · payment discount_taken 25.20 (Σ trigger) · return allocs[0].discount 25.2 · gap 0', (select trim_scale(a.discount_amount)::text from public.po_payment_alloc a where a.po_payment_id = :'pay1'::uuid) || '/' || (select trim_scale(p.discount_taken)::text from public.po_payment p where p.id = :'pay1'::uuid) || '/' || trim_scale((:'pay1_r'::jsonb->'allocs'->0->>'discount')::numeric)::text || '/' || trim_scale((:'pay1_r'::jsonb->>'gap')::numeric)::text, '25.2/25.2/25.2/0');
select pg_temp.chk('B7b two targets + discount → refused (say which document) · element discount key → refused (next step) · no PAY2/PAY3 rows', (:'b7_two' like 'P0001 Say which document the discount of 25.20 belongs to — a payment that settles 2 documents%')::text || '/' || (:'b7_key' like 'P0001 A discount per document (p_targets[].discount) arrives with the next payment-window update%')::text || '/' || (select count(*) from public.po_payment where reference in ('PODISC4A1-PAY2', 'PODISC4A1-PAY3')), 'true/true/0');
select pg_temp.chk('B10x lock: terms of I1 cannot change while PAY1 holds its discount (readable sentence) · note still editable · I2 (no discount taken) editable', (pg_temp.err(format('update public.po_invoice set early_discount_pct = 3 where id = %L', :'i1')) like 'P0001 Invoice PODISC4A1-I1 — a payment already took its early-payment discount (PODISC4A1-PAY1 (25.20)) — reverse that payment''s discount first%')::text || '/' || pg_temp.err(format('update public.po_invoice set note = ''x'' where id = %L', :'i1')) || '/' || pg_temp.err(format('update public.po_invoice set early_discount_until = ''2026-10-31'' where id = %L', :'i2')), 'true/no-error/no-error');
-- Σ 동기: alloc_set 으로 둘째 문서(I2 100 of 113) · 플래그 아래 직접 고치기(= ④-b 창구 모양) 25.20 → 30 · 창구로 떼기 → 0 · 결제 지우기(CASCADE · 오류 없음)
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_alloc_set(:'pay1'::uuid, 'invoice', :'i2'::uuid, 100, 'second doc') as r \gset as_
select trim_scale(p.discount_taken)::text as dt_25 from public.po_payment p where p.id = :'pay1'::uuid \gset
reset role;
select set_config('po.payment_door', '1', true);
update public.po_payment_alloc set discount_amount = 30 where po_payment_id = :'pay1'::uuid and po_invoice_id = :'i1'::uuid;
select set_config('po.payment_door', '', true);
select trim_scale(p.discount_taken)::text as dt_30 from public.po_payment p where p.id = :'pay1'::uuid \gset
select a.id::text as al1 from public.po_payment_alloc a where a.po_payment_id = :'pay1'::uuid and a.po_invoice_id = :'i1'::uuid \gset
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_alloc_delete(:'al1'::uuid) as r \gset ad_
select trim_scale(p.discount_taken)::text as dt_0 from public.po_payment p where p.id = :'pay1'::uuid \gset
select public.po_doc_delete('payment', :'pay1'::uuid) as r \gset dd_
reset role;
select pg_temp.chk('B6 Σ sync: alloc_set adds I2 (discount_taken stays 25.2 · alloc_sum 1456) · door-flag edit 25.2 → 30 → discount_taken 30 · alloc_delete(I1) → 0 · payment deleted (cascade · no error) · rows 0', trim_scale((:'as_r'::jsonb->>'alloc_sum')::numeric)::text || '/' || :'dt_25' || '/' || :'dt_30' || '/' || :'dt_0' || '/' || (:'dd_r'::jsonb->>'deleted') || '/' || (select count(*) from public.po_payment_alloc a where a.po_payment_id = :'pay1'::uuid), '1456/25.2/30/0/true/0');

-- ═══ B11 — 문지기(purchasing 직원 · PostgREST 모양): 머리 amount · discount_taken · 직접 insert 거부 · paid_on · reference 는 된다 · 충당 amount · discount_amount · 직접 insert 거부 · note 는 된다 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_create(:'sup'::uuid, '2026-10-25', 1330.80, :'cad'::uuid, 25.20, null, 'PODISC4A1-PAY4', null, jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', :'i1', 'amount', 1356)), true) as r \gset pay4_
select (:'pay4_r'::jsonb->>'payment_id') as pay4 \gset
select a.id::text as al4 from public.po_payment_alloc a where a.po_payment_id = :'pay4'::uuid \gset
select (pg_temp.err(format('update public.po_payment set amount = 1 where id = %L', :'pay4')) like 'P0001 Paid (1330.80 → 1) and Discount taken (25.20 → 25.20) on payment PODISC4A1-PAY4 are changed through the payment window%')::text as g1 \gset
select (pg_temp.err(format('update public.po_payment set discount_taken = 0 where id = %L', :'pay4')) like 'P0001 Paid (1330.80 → 1330.80) and Discount taken (25.20 → 0) on payment PODISC4A1-PAY4 are changed through the payment window%')::text as g2 \gset
select pg_temp.err(format('update public.po_payment set paid_on = ''2026-10-26'', reference = ''PODISC4A1-PAY4b'', note = ''n'' where id = %L', :'pay4')) as g3 \gset
select (pg_temp.err(format('insert into public.po_payment (paid_on, amount, currency_id) values (''2026-10-10'', 5, %L)', :'cad')) like 'P0001 A payment is created through the payment window (Pay · po_payment_create), not by inserting a row%')::text as g4 \gset
select (pg_temp.err(format('update public.po_payment_alloc set amount = 1 where id = %L', :'al4')) like 'P0001 The amount (1356 → 1) and discount (25.20 → 25.20) on this allocation line are changed through the payment window%')::text as g5 \gset
select (pg_temp.err(format('update public.po_payment_alloc set discount_amount = 0 where id = %L', :'al4')) like 'P0001 The amount (1356 → 1356) and discount (25.20 → 0) on this allocation line are changed through the payment window%')::text as g6 \gset
select pg_temp.err(format('update public.po_payment_alloc set note = ''why'' where id = %L', :'al4')) as g7 \gset
select (pg_temp.err(format('insert into public.po_payment_alloc (po_payment_id, po_invoice_id, amount) values (%L, %L, 1)', :'pay4', :'i3')) like 'P0001 A document is put on a payment through the payment window (Pay · Add a document), not by inserting a row%')::text as g8 \gset
select public.po_payment_detail(:'pay4'::uuid) as r \gset pd_
reset role;
select pg_temp.chk('B11 guard: amount · discount_taken · insert payment → P0001 sentence · paid_on/reference/note ok · alloc amount · discount_amount · insert alloc → P0001 · alloc note ok · values unchanged', :'g1' || '|' || :'g2' || '|' || :'g3' || '|' || :'g4' || '|' || :'g5' || '|' || :'g6' || '|' || :'g7' || '|' || :'g8' || '|' || (select trim_scale(p.amount)::text || '/' || trim_scale(p.discount_taken)::text || '/' || p.paid_on::text || '/' || p.reference from public.po_payment p where p.id = :'pay4'::uuid), 'true|true|no-error|true|true|true|no-error|true|1330.8/25.2/2026-10-26/PODISC4A1-PAY4b');
select pg_temp.chk('B11b po_payment_detail: allocs[0].discount_amount 25.2 · early_discount_until 2026-10-21 · money.discount_sum 25.2 · warning paid_on_after_discount_deadline (paid 10-25 > 10-21) · gap_not_zero absent', trim_scale((:'pd_r'::jsonb->'allocs'->0->>'discount_amount')::numeric)::text || '/' || (:'pd_r'::jsonb->'allocs'->0->>'early_discount_until') || '/' || trim_scale((:'pd_r'::jsonb->'money'->>'discount_sum')::numeric)::text || '/' || (:'pd_r'::jsonb->'warnings' ? 'paid_on_after_discount_deadline')::text || '/' || (:'pd_r'::jsonb->'warnings' ? 'gap_not_zero')::text, '25.2/2026-10-21/25.2/true/false');

-- ═══ B15 — 권한: anon 없음 · 열쇠 없는 직원 거부(창구 문장 · RLS 0 행) ═══
set local role anon;
do $$ begin perform public.po_invoice_early_discount(gen_random_uuid()); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as an1 \gset
do $$ begin perform public.po_early_discount_calc(1, null, 'pre_tax', null, 1, 1); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as an2 \gset
do $$ begin perform count(*) from public.po_invoice_list; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as an3 \gset
reset role;
set local role authenticated;
select set_config('request.jwt.claims', :'n_claims', true);
do $$ begin perform public.po_invoice_create('invoice', 'PODISC4A1-X', null, null, null, null, null, null, true, false, null); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
select current_setting('app.out', true) as nk1 \gset
with u as (update public.po_invoice set early_discount_until = '2026-11-01' where id = :'i2'::uuid returning 1) select count(*) as nk2 from u \gset
select count(*) as nk3 from public.po_invoice_early_discount(:'i1'::uuid, null) \gset
reset role;
select pg_temp.chk('B15 anon: function · calc · list → 42501 · no-key staff: po_invoice_create refused (purchasing sentence) · terms update 0 rows (RLS) · can read the discount function (1)', :'an1' || ',' || :'an2' || ',' || :'an3' || ',' || (:'nk1' = 'P0001 You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was saved')::text || ',' || :nk2 || ',' || :nk3, '42501,42501,42501,true,0,1');

-- ═══ B16 — 실물 무변(이 시험 안): 실제 결제 · 충당 · 인보이스 md5 = 머리 ═══
select md5(string_agg(p.id::text || '|' || p.paid_on::text || '|' || p.amount::text || '|' || p.discount_taken::text || '|' || coalesce(p.reference, '') || '|' || p.currency_id::text || '|' || coalesce(p.account_id::text, ''), ',' order by p.id)) as real_pay_mid from public.po_payment p where coalesce(p.reference, '') not like 'PODISC4A1-%' \gset
select md5(string_agg(a.id::text || '|' || a.po_payment_id::text || '|' || coalesce(a.po_invoice_id::text, '') || '|' || coalesce(a.po_charge_id::text, '') || '|' || a.amount::text, ',' order by a.id)) as real_alloc_mid from public.po_payment_alloc a join public.po_payment p on p.id = a.po_payment_id where coalesce(p.reference, '') not like 'PODISC4A1-%' \gset
select md5(string_agg(i.id::text || '|' || i.invoice_number || '|' || i.status || '|' || i.total_amount::text || '|' || coalesce(i.due_date::text, ''), ',' order by i.id)) as real_inv_mid from public.po_invoice i where i.invoice_number not like 'PODISC4A1-%' \gset
select pg_temp.chk('B16 real payments · allocs · invoices unchanged inside the test (md5 = head) · real invoices still have no early terms (not backfilled — suggestion is for new invoices)', (:'real_pay_mid' = :'real_pay_head')::text || '/' || (:'real_alloc_mid' = :'real_alloc_head')::text || '/' || (:'real_inv_mid' = :'real_inv_head')::text || '/' || (select count(*) from public.po_invoice i where i.invoice_number not like 'PODISC4A1-%' and i.early_discount_basis is not null), 'true/true/true/0');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select md5(string_agg(p.id::text || '|' || p.paid_on::text || '|' || p.amount::text || '|' || p.discount_taken::text || '|' || coalesce(p.reference, '') || '|' || p.currency_id::text || '|' || coalesce(p.account_id::text, ''), ',' order by p.id)) as real_pay_tail, count(*) as real_pay_tail_n from public.po_payment p where coalesce(p.reference, '') not like 'PODISC4A1-%' \gset
select md5(string_agg(a.id::text || '|' || a.po_payment_id::text || '|' || coalesce(a.po_invoice_id::text, '') || '|' || coalesce(a.po_charge_id::text, '') || '|' || a.amount::text, ',' order by a.id)) as real_alloc_tail, count(*) as real_alloc_tail_n from public.po_payment_alloc a join public.po_payment p on p.id = a.po_payment_id where coalesce(p.reference, '') not like 'PODISC4A1-%' \gset
select md5(string_agg(i.id::text || '|' || i.invoice_number || '|' || i.status || '|' || i.total_amount::text || '|' || coalesce(i.due_date::text, ''), ',' order by i.id)) as real_inv_tail, count(*) as real_inv_tail_n from public.po_invoice i where i.invoice_number not like 'PODISC4A1-%' \gset
select 'REAL_SAME payments ' || (:'real_pay_head' = :'real_pay_tail')::text || ' (' || :real_pay_n || ' → ' || :real_pay_tail_n || ') allocs ' || (:'real_alloc_head' = :'real_alloc_tail')::text || ' (' || :real_alloc_n || ' → ' || :real_alloc_tail_n || ') invoices ' || (:'real_inv_head' = :'real_inv_tail')::text || ' (' || :real_inv_n || ' → ' || :real_inv_tail_n || ')';
select 'seq tail po ' || last_value || ' ' || is_called from public.po_number_seq;
select 'seq tail rcv ' || last_value || ' ' || is_called from public.po_receipt_number_seq;
