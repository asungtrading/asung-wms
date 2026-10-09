-- po-disc-4a2-verify.sql — 결제 할인 → 원가 사건(po_payment_create 원소 discount · 제안 · 경고 셋 · 세 몫 · PO 줄마다 사건 · 399 거부) · 되돌림(충당 떼기 · 결제 지우기) · 문지기 문장 · P&G 백필 (Asung-IMS · 2026-10-09)
--   기대: 시험 갈래(-v mig) OK 20 · 확인 갈래 OK 18(= 20 − 시험 전용 2: G0 · D0a) · MISMATCH 0 · 실제 결제 · 충당 · 인보이스(P&G 밖) · 레이어 · 얹기 · 소비 md5 전후 같음 · 재생성 가치 차이 +2.73
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/<ts>_po_disc_4a2.sql -f supabase/tests/po-disc-4a2-verify.sql > /tmp/po-disc-4a2.out 2>&1; echo "rc=$?"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료는 가짜만(PO-795xx · PODISC4A2-* · RCV-795xx · CHG-79500 · 가짜 공급처 · 결제조건 · 직원) · 백필 검사만 실제 P&G 행을 읽는다 · 끝은 rollback · identity 시퀀스는 greatest(실제 최대, 머리)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as po_seq_last, is_called as po_seq_called from public.po_number_seq \gset
select last_value as rcv_seq_last, is_called as rcv_seq_called from public.po_receipt_number_seq \gset
select last_value as add_seq_last, is_called as add_seq_called from public.inv_layer_cost_add_id_seq \gset
select last_value as con_seq_last, is_called as con_seq_called from public.inv_layer_consume_id_seq \gset
\echo '== seq head po' :po_seq_last :po_seq_called 'rcv' :rcv_seq_last :rcv_seq_called 'cost_add' :add_seq_last :add_seq_called 'consume' :con_seq_last :con_seq_called
select md5(string_agg(p.id::text || '|' || p.paid_on::text || '|' || p.amount::text || '|' || p.discount_taken::text || '|' || coalesce(p.reference, '') || '|' || p.currency_id::text, ',' order by p.id)) as real_pay_head, count(*) as real_pay_n from public.po_payment p where coalesce(p.reference, '') not like 'PODISC4A2-%' \gset
select md5(string_agg(a.id::text || '|' || a.po_payment_id::text || '|' || coalesce(a.po_invoice_id::text, '') || '|' || coalesce(a.po_charge_id::text, '') || '|' || a.amount::text || '|' || a.discount_amount::text, ',' order by a.id)) as real_alloc_head, count(*) as real_alloc_n from public.po_payment_alloc a join public.po_payment p on p.id = a.po_payment_id where coalesce(p.reference, '') not like 'PODISC4A2-%' \gset
select md5(string_agg(i.id::text || '|' || i.invoice_number || '|' || i.status || '|' || i.total_amount::text || '|' || coalesce(i.due_date::text, '') || '|' || coalesce(i.early_discount_basis, ''), ',' order by i.id)) as real_inv_head, count(*) as real_inv_n from public.po_invoice i where i.invoice_number not like 'PODISC4A2-%' and i.invoice_number <> '1030266656' \gset
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_head, count(*) as real_layers_n from public.inv_layer l where l.sku not like 'DISC4A2-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by a.id)) as real_adds_head, count(*) as real_adds_n from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC4A2-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text, ',' order by k.id)) as real_consume_head, count(*) as real_consume_n from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC4A2-%' \gset
select count(*) as real_events_head from public.inv_cost_adjust \gset
\echo '== real head payments' :real_pay_n :real_pay_head 'allocs' :real_alloc_n :real_alloc_head 'invoices(not PG)' :real_inv_n :real_inv_head 'layers' :real_layers_n :real_layers_head 'adds' :real_adds_n 'consume' :real_consume_n 'events' :real_events_head

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

-- ═══ 재료(postgres · 가짜) — 직원 둘 · 공급처 · 결제조건 · 제품 8 · PO 6 · 비용 1 ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc4a2-g@test.invalid', 'PODISC4A2 Purchasing+Receiving', 'manager', '["purchasing","receiving"]'::jsonb) returning auth_user_id::text as g_uid, id::text as g_sid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc4a2-n@test.invalid', 'PODISC4A2 NoKeys', 'manager', '[]'::jsonb) returning auth_user_id::text as n_uid \gset
\set g_claims '{"sub":"' :g_uid '","role":"authenticated"}'
\set n_claims '{"sub":"' :n_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as usd from public.ref_currency where code = 'USD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.id::text as bin, b.name as binname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select id::text as hst, name as hstname from public.ref_tax_rule where direction = 'purchase' and is_active and name = 'HST ON (Purchase)' limit 1 \gset
insert into public.ref_payment_term (name, source, net_days, discount_days, discount_percent) values ('PODISC4A2 2.1%13 Net30', 'manual', 30, 13, 2.1) returning id::text as t1 \gset
insert into public.supplier (name, payment_term_name, account_payable_code, currency_id) values ('PODISC4A2 Supplier', 'Net 30', '2000', :'cad'::uuid) returning id::text as sup \gset
insert into public.product (sku, name, source) select 'DISC4A2-P' || i, 'PODISC4A2 P' || i, 'manual' from generate_series(1, 8) i;
set local session_replication_role = replica;
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at, payment_term_id, payment_term_name, tax_rule_id, tax_rule) values
  ('PO-79500', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2026-10-01', :'wh'::uuid, now(), :'t1'::uuid, 'PODISC4A2 2.1%13 Net30', :'hst'::uuid, :'hstname'),
  ('PO-79501', 'confirmed', :'sup'::uuid, :'usd'::uuid, 1.40, '2026-10-01', :'wh'::uuid, now(), null, null, :'hst'::uuid, :'hstname'),
  ('PO-79502', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2026-09-01', :'wh'::uuid, now(), :'t1'::uuid, 'PODISC4A2 2.1%13 Net30', :'hst'::uuid, :'hstname'),
  ('PO-79503', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2026-10-01', :'wh'::uuid, now(), null, null, :'hst'::uuid, :'hstname'),
  ('PO-79504', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2026-10-01', :'wh'::uuid, now(), null, null, :'hst'::uuid, :'hstname'),
  ('PO-79505', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2026-10-01', :'wh'::uuid, now(), null, null, :'hst'::uuid, :'hstname');
select string_agg(id::text, ' ' order by po_number) as pos from public.po where po_number like 'PO-795%' \gset
select split_part(:'pos', ' ', 1) as po0, split_part(:'pos', ' ', 2) as po1, split_part(:'pos', ' ', 3) as po2, split_part(:'pos', ' ', 4) as po3, split_part(:'pos', ' ', 5) as po4, split_part(:'pos', ' ', 6) as po5 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po0'::uuid, 1, id, 100, 10.00 from public.product where sku = 'DISC4A2-P1';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po0'::uuid, 2, id, 50, 4.00 from public.product where sku = 'DISC4A2-P2';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po1'::uuid, 1, id, 100, 5.00 from public.product where sku = 'DISC4A2-P3';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po2'::uuid, 1, id, 10, 10.00 from public.product where sku = 'DISC4A2-P4';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po3'::uuid, 1, id, 10, 4.00 from public.product where sku = 'DISC4A2-P5';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po4'::uuid, 1, id, 100, 2.00 from public.product where sku = 'DISC4A2-P6';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po4'::uuid, 2, id, 10, 3.00 from public.product where sku = 'DISC4A2-P7';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po5'::uuid, 1, id, 10, 1.00 from public.product where sku = 'DISC4A2-P8';
select pl.id::text as l1 from public.po_line pl where pl.po_id = :'po0'::uuid and pl.line_no = 1 \gset
select pl.id::text as l2 from public.po_line pl where pl.po_id = :'po0'::uuid and pl.line_no = 2 \gset
select pl.id::text as l3 from public.po_line pl where pl.po_id = :'po1'::uuid \gset
select pl.id::text as l4 from public.po_line pl where pl.po_id = :'po2'::uuid \gset
select pl.id::text as l5 from public.po_line pl where pl.po_id = :'po3'::uuid \gset
select pl.id::text as l6 from public.po_line pl where pl.po_id = :'po4'::uuid and pl.line_no = 1 \gset
select pl.id::text as l7 from public.po_line pl where pl.po_id = :'po4'::uuid and pl.line_no = 2 \gset
select pl.id::text as l8 from public.po_line pl where pl.po_id = :'po5'::uuid \gset
insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, status, confirmed_at) values (:'sup'::uuid, 'CHG-79500', '2026-10-05', 'freight', :'cad'::uuid, 20, 'confirmed', now()) returning id::text as c0 \gset
insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (:'c0'::uuid, :'po3'::uuid, 20);
set local session_replication_role = origin;
-- 인보이스 여섯(창구 · purchasing 직원) — I1 2.1%/13(10-08 → 10-21) · I2 USD(조건은 손으로 with_tax 2% · 10-31) · I3 기한 지남(09-01 → 09-14) · I4 조건 없음 · I5 무상 줄 · I6 399 용
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select (public.po_invoice_create('invoice', 'PODISC4A2-I1', :'po0'::uuid, null, null, '2026-10-08', null, 1356.00, true, true, null))->>'id' as i1 \gset
select (public.po_invoice_create('invoice', 'PODISC4A2-I2', :'po1'::uuid, null, null, '2026-10-08', null, 565.00, true, true, null))->>'id' as i2 \gset
select (public.po_invoice_create('invoice', 'PODISC4A2-I3', :'po2'::uuid, null, null, '2026-09-01', null, 113.00, true, true, null))->>'id' as i3 \gset
select (public.po_invoice_create('invoice', 'PODISC4A2-I4', :'po3'::uuid, null, null, '2026-10-08', null, 45.20, true, true, null))->>'id' as i4 \gset
select (public.po_invoice_create('invoice', 'PODISC4A2-I5', :'po4'::uuid, null, null, '2026-10-08', null, 226.00, true, true, null))->>'id' as i5 \gset
select (public.po_invoice_create('invoice', 'PODISC4A2-I6', :'po5'::uuid, null, null, '2026-10-08', null, 11.30, true, true, null))->>'id' as i6 \gset
update public.po_invoice set early_discount_pct = 2, early_discount_basis = 'with_tax', early_discount_until = '2026-10-31' where id = :'i2'::uuid;
reset role;
set local session_replication_role = replica;
update public.po_invoice set status = 'confirmed', confirmed_at = now() where invoice_number like 'PODISC4A2-I%';
update public.po_invoice_line set is_payable = false, unit_price = 0 where po_invoice_id = :'i5'::uuid and po_line_id = :'l7'::uuid;     -- 무상 줄(판정 398)
-- 레이어 — I2(USD 5.00 × 1.40 = 7.00) · I6(1.00) 는 확정 입고 + 원장 + 창구 · I1 은 초안 입고 + 작업 줄(C2 확정 길)
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at) values ('RCV-79501', :'po1'::uuid, :'wh'::uuid, '2026-10-02', 'confirmed', now()) returning id::text as r1 \gset
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at) values ('RCV-79505', :'po5'::uuid, :'wh'::uuid, '2026-10-02', 'confirmed', now()) returning id::text as r5 \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, source, raw) values
  ('2026-10-02', 1, 'DISC4A2-P3', :'whname', :'binname', 100, 'po_in', 'purchase', 'RCV-79501', :'r1', :'l3', 'ims', '{"fake":"po-disc-4a2"}'),
  ('2026-10-02', 1, 'DISC4A2-P8', :'whname', :'binname', 10,  'po_in', 'purchase', 'RCV-79505', :'r5', :'l8', 'ims', '{"fake":"po-disc-4a2"}');
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status) values ('RCV-79500', :'po0'::uuid, :'wh'::uuid, '2026-10-03', 'draft') returning id::text as r0 \gset
insert into public.po_receipt_work (receipt_id, po_line_id, qty_ea, bin_id, putaway_done, count_method, counted_by, counted_at) values (:'r0'::uuid, :'l1'::uuid, 100, :'bin'::uuid, true, 'manual', :'g_sid'::uuid, now()), (:'r0'::uuid, :'l2'::uuid, 50, :'bin'::uuid, true, 'manual', :'g_sid'::uuid, now());
set local session_replication_role = origin;
select set_config('request.jwt.claims', :'g_claims', true);
select public.inv_layer_post_receipt(:'r1'::uuid) as r \gset f1_
select public.inv_layer_post_receipt(:'r5'::uuid) as r \gset f5_
select y.id::text as y3 from public.inv_layer y where y.doc_number = 'RCV-79501' and y.line_ref = :'l3' \gset
select y.id::text as y8 from public.inv_layer y where y.doc_number = 'RCV-79505' and y.line_ref = :'l8' \gset
insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) values (:'y3'::bigint, 'sale', 'SO-79500', 'DISC4A2-P3:1', 'sale_out', '2026-10-05', 30, 7.00, 210, 'sale');
select pg_temp.chk('M fake material: invoices 6 confirmed · I1 1200/156/1356 · I2 500/65/565 (USD fx 1.40) · I5 payable 200 (free line) · layers y3 100 @ 7.00 · y8 10 @ 1 · I3 until 2026-09-14 · I2 with_tax 2% 10-31', (select count(*) from public.po_invoice where invoice_number like 'PODISC4A2-I%' and status = 'confirmed')::text || '/' || (select trim_scale(payable_taxable)::text || '/' || trim_scale(payable_tax)::text || '/' || trim_scale(payable_net)::text from public.po_invoice_money where id = :'i1'::uuid) || '/' || (select trim_scale(payable_taxable)::text || '/' || trim_scale(payable_tax)::text || '/' || trim_scale(payable_net)::text from public.po_invoice_money where id = :'i2'::uuid) || '/' || (select trim_scale(payable_taxable)::text from public.po_invoice_money where id = :'i5'::uuid) || '/' || (select trim_scale(qty)::text || '@' || trim_scale(unit_cost)::text from public.inv_layer where id = :'y3'::bigint) || '/' || (select trim_scale(qty)::text || '@' || trim_scale(unit_cost)::text from public.inv_layer where id = :'y8'::bigint) || '/' || (select early_discount_until::text from public.po_invoice where id = :'i3'::uuid) || '/' || (select early_discount_basis || trim_scale(early_discount_pct)::text from public.po_invoice where id = :'i2'::uuid), '6/1200/156/1356/500/65/565/200/100@7/10@1/2026-09-14/with_tax2');

-- ═══ D0 · G0 — 적용 전(시험 갈래): 원소 discount 열쇠 거부(④-a1) · 재발행 원본 md5 ═══
\if :{?mig}
select pg_temp.chk('G0 last defs: po_payment_create d54d37bc · po_payment_alloc_delete f80a194d · po_doc_delete 8864a994 · guards f2d2c929 · 449839d4', (select string_agg(left(md5(p.prosrc), 8), ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('po_payment_create', 'po_payment_alloc_delete', 'po_doc_delete', 'po_payment_guard', 'po_payment_alloc_guard')), '8864a994,f80a194d,449839d4,d54d37bc,f2d2c929');
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select pg_temp.chk('D0a before: element discount key refused (④-a1) · no parts function · P&G invoice has no terms · 0 events', (pg_temp.err(format('select public.po_payment_create(%L::uuid, ''2026-10-10'', 1330.80, %L::uuid, 0, null, ''PODISC4A2-D0'', null, jsonb_build_array(jsonb_build_object(''kind'', ''invoice'', ''id'', %L, ''amount'', 1356, ''discount'', null)), false)', :'sup', :'cad', :'i1')) like 'P0001 A discount per document (p_targets[].discount) arrives with the next payment-window update%')::text || '/' || (to_regprocedure('public.po_invoice_discount_parts(uuid, numeric, text)') is null)::text || '/' || (select (early_discount_basis is null)::text || '/' || due_date::text from public.po_invoice where invoice_number = '1030266656') || '/' || (select count(*) from public.inv_cost_adjust where source_type = 'po_payment_alloc'), 'true/true/true/2026-10-21/0');
reset role;
\i :mig
\endif
select pg_temp.chk('G1 untouched: alloc_set 64c2c53a · post_cost_adjust 1f95d60c · reverse 02d8d9b9 · confirm_by 857021b6 · early_discount 33efa87b · calc 95d72724 · line_cost 46533c68 · money view 08f428cb · definer three', (select string_agg(left(md5(p.prosrc), 8), ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('po_payment_alloc_set', 'inv_layer_post_cost_adjust', 'inv_cost_adjust_reverse', 'po_receipt_confirm_by', 'po_invoice_early_discount', 'po_early_discount_calc', 'po_invoice_line_cost')) || '/' || left(md5(pg_get_viewdef('public.po_invoice_money'::regclass)), 8) || '/' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_payment_create', 'po_payment_alloc_delete', 'po_doc_delete') and p.prosecdef), '02d8d9b9,1f95d60c,95d72724,33efa87b,46533c68,64c2c53a,857021b6/08f428cb/3');

-- ═══ C11 — P&G 백필(양 갈래: 시험은 방금 · 확인은 이미) ═══
select pg_temp.chk('C11 P&G 1030266656: terms 2.1 · pre_tax · 2026-10-21 · due 2026-11-07 · events 13 · Σ amount_cad −952.08 = Σ amount_doc · all pending · settlement_discount/po_line · payment 50278.68/952.08 · alloc 51230.76/952.08/0/0 · no layers on its PO lines', (select trim_scale(early_discount_pct)::text || '/' || early_discount_basis || '/' || early_discount_until::text || '/' || due_date::text from public.po_invoice where invoice_number = '1030266656') || '/' || (select count(*)::text || '/' || trim_scale(sum(j.amount_cad))::text || '/' || (sum(j.amount_cad) = sum(j.amount_doc))::text || '/' || string_agg(distinct j.status || ':' || j.kind || ':' || j.target_type, ',') || '/' || bool_and(j.exchange_rate is null and j.source_number = 'PAY 2026-10-08 1030266656')::text from public.inv_cost_adjust j join public.po_payment_alloc a on a.id = j.source_id join public.po_invoice i on i.id = a.po_invoice_id where j.source_type = 'po_payment_alloc' and i.invoice_number = '1030266656') || '/' || (select trim_scale(p.amount)::text || '/' || trim_scale(p.discount_taken)::text || '/' || trim_scale(a.amount)::text || '/' || trim_scale(a.discount_amount)::text || '/' || trim_scale(a.discount_tax_part)::text || '/' || trim_scale(a.discount_other_part)::text from public.po_payment p join public.po_payment_alloc a on a.po_payment_id = p.id join public.po_invoice i on i.id = a.po_invoice_id where i.invoice_number = '1030266656') || '/' || (select count(*) from public.inv_layer y join public.po_line pl on pl.id::text = y.line_ref join public.po_invoice_line il on il.po_line_id = pl.id join public.po_invoice i on i.id = il.po_invoice_id where i.invoice_number = '1030266656'), '2.1/pre_tax/2026-10-21/2026-11-07/13/-952.08/true/pending:settlement_discount:po_line/true/50278.68/952.08/51230.76/952.08/0/0/0');
select pg_temp.chk('C11b P&G events = formula (12 of 13 equal the rounded share · the last line carries the remainder) · line 6 (3600 EA) share −490.65', (select count(*) from (select il.po_line_id, round(952.08 * sum(il.qty_ea * il.unit_price) / (select sum(x.qty_ea * x.unit_price) from public.po_invoice_line x join public.po_invoice i2 on i2.id = x.po_invoice_id where i2.invoice_number = '1030266656'), 2) as exp from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id where i.invoice_number = '1030266656' group by il.po_line_id) w join public.inv_cost_adjust j on j.po_line_id = w.po_line_id and j.source_type = 'po_payment_alloc' where j.amount_doc = -w.exp)::text || '/' || (select trim_scale(j.amount_doc)::text from public.inv_cost_adjust j join public.po_line pl on pl.id = j.po_line_id join public.po x on x.id = pl.po_id where j.source_type = 'po_payment_alloc' and x.po_number = 'PO-02045' and pl.line_no = 6), '12/-490.65');

-- ═══ C1 — P&G 모양(CAD · 13% · pre_tax 2.1% · 기한 안 · 레이어 없음): 제안 25.20 · 사건 PO 줄마다 · Σ = −할인 · pending · 검산 · 미리 보기 = 저장 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 1330.80, :'cad'::uuid, 0, null, 'PODISC4A2-P1', null, jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', :'i1', 'amount', 1356, 'discount', null)), false) as r \gset pv1_
select clock_timestamp() as t0 \gset
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 1330.80, :'cad'::uuid, 0, null, 'PODISC4A2-P1', null, jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', :'i1', 'amount', 1356, 'discount', null)), true) as r \gset p1_
select clock_timestamp() as t1 \gset
reset role;
select 'timing: po_payment_create commit (C1 · 1 invoice · 2 events) ms=' || round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000);
select (:'p1_r'::jsonb->>'payment_id') as p1 \gset
select pg_temp.chk('C1 preview = save: discount 25.2 suggested · pre_tax · cost 25.2 / tax 0 / other 0 · warning discount_suggested · preview makes no events · save: discount_taken 25.2 · alloc 25.2 · events 2 (L1 −21 · L2 −4.2 · pending · CAD fx null) · Σ amount_cad = −25.2', trim_scale((:'pv1_r'::jsonb->'allocs'->0->>'discount')::numeric)::text || '/' || (:'pv1_r'::jsonb->'allocs'->0->>'discount_source') || '/' || (:'pv1_r'::jsonb->'allocs'->0->>'discount_basis') || '/' || trim_scale((:'pv1_r'::jsonb->'allocs'->0->>'cost_part')::numeric)::text || '/' || trim_scale((:'pv1_r'::jsonb->'allocs'->0->>'tax_part')::numeric)::text || '/' || (:'pv1_r'::jsonb->'warnings' ? 'discount_suggested:PODISC4A2-I1')::text || '/' || jsonb_array_length(:'pv1_r'::jsonb->'cost_events') || '/' || trim_scale((:'p1_r'::jsonb->>'discount_taken')::numeric)::text || '/' || (select trim_scale(discount_amount)::text from public.po_payment_alloc where po_payment_id = :'p1'::uuid) || '/' || (:'p1_r'::jsonb->'cost_events'->0->>'event_count') || '/' || (select string_agg(trim_scale(j.amount_doc)::text || ':' || j.status || ':' || coalesce(j.exchange_rate::text, 'null'), ',' order by pl.line_no) || '/' || trim_scale(sum(j.amount_cad))::text from public.inv_cost_adjust j join public.po_line pl on pl.id = j.po_line_id where j.source_id = (select id from public.po_payment_alloc where po_payment_id = :'p1'::uuid)), '25.2/suggested/pre_tax/25.2/0/true/0/25.2/25.2/2/-21:pending:null,-4.2:pending:null/-25.2');
select pg_temp.chk('C1b parts function directly: (I1, 25.20) → basis pre_tax · base 1200 · goods 1200 · tax 156 · cost 25.2 · tax_part 0 · other 0 · with_tax override → base 1356 · tax_part 2.9 · cost 22.3', (select basis || '/' || trim_scale(base_amount)::text || '/' || trim_scale(goods_net)::text || '/' || trim_scale(tax_amount)::text || '/' || trim_scale(cost_part)::text || '/' || trim_scale(tax_part)::text || '/' || trim_scale(other_part)::text from public.po_invoice_discount_parts(:'i1'::uuid, 25.20, null)) || '/' || (select trim_scale(base_amount)::text || '/' || trim_scale(tax_part)::text || '/' || trim_scale(cost_part)::text from public.po_invoice_discount_parts(:'i1'::uuid, 25.20, 'with_tax')), 'pre_tax/1200/1200/156/25.2/0/0/1356/' || trim_scale(round(25.20 * 156 / 1356.0, 2))::text || '/' || trim_scale(25.20 - round(25.20 * 156 / 1356.0, 2))::text);

-- ═══ C2 — C1 뒤 입고 확정(po_receipt_confirm_by · ⓖ): pending → posted · 레이어 가치 = 인보이스 원가 − 몫 ═══
select public.po_receipt_confirm_by(:'g_sid'::uuid, :'r0'::uuid) as r \gset cf_
select y.id::text as y1 from public.inv_layer y where y.doc_number = 'RCV-79500' and y.line_ref = :'l1' \gset
select y.id::text as y2 from public.inv_layer y where y.doc_number = 'RCV-79500' and y.line_ref = :'l2' \gset
select pg_temp.chk('C2 confirm posts the 2 pending events · posted_on today · L1 layer 100 @ 10 → remaining 979 · L2 50 @ 4 → 195.8 · adjust_errors absent', jsonb_array_length(:'cf_r'::jsonb->'adjustments'->'posted') || '/' || (select string_agg(j.status, ',') || '/' || bool_and(j.posted_on = public.ims_today())::text from public.inv_cost_adjust j where j.source_id = (select id from public.po_payment_alloc where po_payment_id = :'p1'::uuid)) || '/' || (select trim_scale(v.remaining_value)::text from public.inv_layer_value(:'y1'::bigint) v) || '/' || (select trim_scale(v.remaining_value)::text from public.inv_layer_value(:'y2'::bigint) v) || '/' || (:'cf_r'::jsonb->'warnings' ? 'adjust_errors')::text, '2/posted,posted/true/979/195.8/false');

-- ═══ C3 — USD · 환율 1.40 · with_tax 2% · 레이어 있음 · 30 판매: 원가 몫 = 세금 전 비율 · 세금 몫 기록 · amount_cad = 몫 × 1.40 · cost_late 음수 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 553.70, :'usd'::uuid, 0, null, 'PODISC4A2-P2', null, jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', :'i2', 'amount', 565, 'discount', null)), true) as r \gset p2_
reset role;
select (:'p2_r'::jsonb->>'payment_id') as p2 \gset
select a.id::text as al2 from public.po_payment_alloc a where a.po_payment_id = :'p2'::uuid \gset
select pg_temp.chk('C3 discount 11.30 (2% of 565 with_tax) · tax_part 1.30 · cost 10 · alloc tax_part 1.30 · event L3 amount_doc −10 · fx 1.40 · amount_cad −14 · posted · cost_late −4.2 (30 of 100 sold) · remaining 480.2 = 70 × 6.86', trim_scale((:'p2_r'::jsonb->'allocs'->0->>'discount')::numeric)::text || '/' || trim_scale((:'p2_r'::jsonb->'allocs'->0->>'tax_part')::numeric)::text || '/' || trim_scale((:'p2_r'::jsonb->'allocs'->0->>'cost_part')::numeric)::text || '/' || (select trim_scale(discount_tax_part)::text from public.po_payment_alloc where id = :'al2'::uuid) || '/' || (select trim_scale(j.amount_doc)::text || '/' || trim_scale(j.exchange_rate)::text || '/' || trim_scale(j.amount_cad)::text || '/' || j.status from public.inv_cost_adjust j where j.source_id = :'al2'::uuid) || '/' || (select trim_scale(k.amount)::text from public.inv_layer_consume k where k.layer_id = :'y3'::bigint and k.reason = 'cost_late') || '/' || (select trim_scale(v.remaining_value)::text || '/' || trim_scale(v.unit_cost)::text from public.inv_layer_value(:'y3'::bigint) v), '11.3/' || trim_scale(round(11.30 * 65 / 565.0, 2))::text || '/' || trim_scale(11.30 - round(11.30 * 65 / 565.0, 2))::text || '/' || trim_scale(round(11.30 * 65 / 565.0, 2))::text || '/-10/1.4/-14/posted/-4.2/480.2/6.86');

-- ═══ C4 · C5 — 기한 지남(제안 0 + discount_expired) · 사람이 넣음(discount_after_deadline) · 조건 없음(discount_without_terms) · 한 결제 · 인보이스 둘 · 할인 다름 · discount_taken = Σ ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 113, :'cad'::uuid, 0, null, 'PODISC4A2-P3x', null, jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', :'i3', 'amount', 113, 'discount', null)), false) as r \gset pv3_
select pg_temp.err(format('select public.po_payment_create(%L::uuid, ''2026-10-10'', 150.20, %L::uuid, 9, null, ''PODISC4A2-P3y'', null, jsonb_build_array(jsonb_build_object(''kind'', ''invoice'', ''id'', %L, ''amount'', 113, ''discount'', 5), jsonb_build_object(''kind'', ''invoice'', ''id'', %L, ''amount'', 45.20, ''discount'', 3)), false)', :'sup', :'cad', :'i3', :'i4')) as both \gset
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 150.20, :'cad'::uuid, 0, null, 'PODISC4A2-P3', null, jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', :'i3', 'amount', 113, 'discount', 5), jsonb_build_object('kind', 'invoice', 'id', :'i4', 'amount', 45.20, 'discount', 3)), true) as r \gset p3_
reset role;
select (:'p3_r'::jsonb->>'payment_id') as p3 \gset
select pg_temp.chk('C4 expired: suggested 0 + discount_expired:I3 · C5 given 5 (after deadline) + 3 (no terms · pre_tax) → warnings both · discount_taken 8 · allocs 5/3 · events L4 −5 · L5 −3 pending · both-ways different totals refused', trim_scale((:'pv3_r'::jsonb->'allocs'->0->>'discount')::numeric)::text || '/' || (:'pv3_r'::jsonb->'warnings' ? 'discount_expired:PODISC4A2-I3')::text || '/' || (:'p3_r'::jsonb->'warnings' ? 'discount_after_deadline:PODISC4A2-I3')::text || '/' || (:'p3_r'::jsonb->'warnings' ? 'discount_without_terms:PODISC4A2-I4')::text || '/' || (:'p3_r'::jsonb->'allocs'->1->>'discount_basis') || '/' || (select trim_scale(discount_taken)::text from public.po_payment where id = :'p3'::uuid) || '/' || (select string_agg(trim_scale(a.discount_amount)::text, ',' order by a.amount desc) from public.po_payment_alloc a where a.po_payment_id = :'p3'::uuid) || '/' || (select string_agg(trim_scale(j.amount_doc)::text || ':' || j.status, ',' order by j.amount_doc) from public.inv_cost_adjust j where j.source_id in (select id from public.po_payment_alloc where po_payment_id = :'p3'::uuid)) || '/' || (:'both' like 'P0001 Say the discount once — per document (p_targets[].discount, total 8) or as p_discount_taken (9)%')::text, '0/true/true/true/pre_tax/8/5,3/-5:pending,-3:pending/true');

-- ═══ C6 — 무상 줄 섞인 인보이스: 무상 줄의 PO 줄에는 사건 없음 · 합 맞음 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 216, :'cad'::uuid, 0, null, 'PODISC4A2-P4', null, jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', :'i5', 'amount', 226, 'discount', 10)), true) as r \gset p4_
reset role;
select (:'p4_r'::jsonb->>'payment_id') as p4 \gset
select a.id::text as al4 from public.po_payment_alloc a where a.po_payment_id = :'p4'::uuid \gset
select pg_temp.chk('C6 free line: events 1 (L6 −10) · none on L7 · free_lines 1 · cost_part 10', (:'p4_r'::jsonb->'cost_events'->0->>'event_count') || '/' || (select count(*) from public.inv_cost_adjust j where j.source_id = :'al4'::uuid and j.po_line_id = :'l7'::uuid) || '/' || (select trim_scale(j.amount_doc)::text from public.inv_cost_adjust j where j.source_id = :'al4'::uuid and j.po_line_id = :'l6'::uuid) || '/' || (:'p4_r'::jsonb->'cost_events'->0->>'free_lines') || '/' || trim_scale((:'p4_r'::jsonb->'cost_events'->0->>'cost_part')::numeric)::text, '1/0/-10/1/10');

-- ═══ C7 — 판정 399: 할인 11 > 레이어 원가 10 → 결제 전체 저장 안 됨 · 사건 0 · 충당 0 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select pg_temp.err(format('select public.po_payment_create(%L::uuid, ''2026-10-10'', 0.30, %L::uuid, 0, null, ''PODISC4A2-P5'', null, jsonb_build_array(jsonb_build_object(''kind'', ''invoice'', ''id'', %L, ''amount'', 11.30, ''discount'', 11)), true)', :'sup', :'cad', :'i6')) as c7 \gset
reset role;
select pg_temp.chk('C7 ruling 399: refused with the layer sentence · no payment · no allocation · no events for L8 · layer y8 untouched', (:'c7' like 'P0001 Cost adjustment % is a credit larger than the cost of the goods on layer %')::text || '/' || (select count(*) from public.po_payment where reference = 'PODISC4A2-P5') || '/' || (select count(*) from public.inv_cost_adjust where po_line_id = :'l8'::uuid) || '/' || (select count(*) from public.inv_layer_cost_add where layer_id = :'y8'::bigint), 'true/0/0/0');

-- ═══ C8 — 되돌림: 충당 떼기(posted · 그 사이 20 더 팔림 · ⬜3) · 결제 지우기(posted 둘 · pending 둘) · 합 0 · 돈 원래대로 · 사건은 남는다 ═══
insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) values (:'y3'::bigint, 'sale', 'SO-79501', 'DISC4A2-P3:2', 'sale_out', '2026-10-09', 20, 7.00, 140, 'sale');
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_alloc_delete(:'al2'::uuid) as r \gset ad_
select public.po_doc_delete('payment', :'p1'::uuid) as r \gset d1_
select public.po_doc_delete('payment', :'p3'::uuid) as r \gset d3_
reset role;
select pg_temp.chk('C8a alloc_delete(P2 · posted): reversed 1 · reversal posted +10 doc/+14 cad · y3 adds Σ 0 · cost_late rows −4.2 and +7 (reversal split at 50 sold · ⬜3) · P2 discount_taken 0 · gap = 553.70 (nothing allocated) · I2 unpaid 565 again', (:'ad_r'::jsonb->'cost_reversed'->>'reversed') || '/' || (select trim_scale(j.amount_doc)::text || '/' || trim_scale(j.amount_cad)::text || '/' || j.status from public.inv_cost_adjust j where j.reverses_id = (select id from public.inv_cost_adjust where source_id = :'al2'::uuid)) || '/' || (select trim_scale(sum(a.amount))::text from public.inv_layer_cost_add a where a.layer_id = :'y3'::bigint) || '/' || (select string_agg(trim_scale(k.amount)::text, ',' order by k.id) from public.inv_layer_consume k where k.layer_id = :'y3'::bigint and k.reason = 'cost_late') || '/' || (select trim_scale(discount_taken)::text from public.po_payment where id = :'p2'::uuid) || '/' || trim_scale((:'ad_r'::jsonb->>'gap')::numeric)::text || '/' || (select trim_scale(unpaid)::text from public.po_invoice_money where id = :'i2'::uuid), '1/10/14/posted/0/-4.2,7/0/553.7/565');
select pg_temp.chk('C8b po_doc_delete(P1 · posted 2): cost_reversed[0].reversed 2 · reversals posted · y1 · y2 adds Σ 0 · I1 unpaid 1356 · events kept (4 rows · source_id orphan · FK none) · P3 (pending 2): reversals pending · 4 rows all pending', (:'d1_r'::jsonb->'cost_reversed'->0->>'reversed') || '/' || (select string_agg(r.status, ',') from public.inv_cost_adjust r where r.reverses_id in (select j.id from public.inv_cost_adjust j where j.po_line_id in (:'l1'::uuid, :'l2'::uuid) and j.source_type = 'po_payment_alloc')) || '/' || (select trim_scale(coalesce(sum(a.amount), 0))::text from public.inv_layer_cost_add a where a.layer_id in (:'y1'::bigint, :'y2'::bigint)) || '/' || (select trim_scale(unpaid)::text from public.po_invoice_money where id = :'i1'::uuid) || '/' || (select count(*) from public.inv_cost_adjust j where j.po_line_id in (:'l1'::uuid, :'l2'::uuid)) || '/' || (select count(*) from public.po_payment where id in (:'p1'::uuid, :'p3'::uuid)) || '/' || (select count(*)::text || '/' || string_agg(distinct j.status, ',') from public.inv_cost_adjust j where j.po_line_id in (:'l4'::uuid, :'l5'::uuid)), '2/posted,posted/0/1356/4/0/4/pending');

-- ═══ C9 — 비용 청구서: 원소 discount → 거부 · 옛 모양(대상 하나 · p_discount_taken) → 충당에만 + 경고 · 사건 0 · 옛 모양 인보이스 → discount_available 경고만 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select pg_temp.err(format('select public.po_payment_create(%L::uuid, ''2026-10-10'', 18, %L::uuid, 0, null, ''PODISC4A2-P6x'', null, jsonb_build_array(jsonb_build_object(''kind'', ''charge'', ''id'', %L, ''amount'', 20, ''discount'', 2)), false)', :'sup', :'cad', :'c0')) as c9a \gset
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 18, :'cad'::uuid, 2, null, 'PODISC4A2-P6', null, jsonb_build_array(jsonb_build_object('kind', 'charge', 'id', :'c0', 'amount', 20)), true) as r \gset p6_
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 565, :'usd'::uuid, 0, null, 'PODISC4A2-P7', null, jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', :'i2', 'amount', 565)), false) as r \gset pv7_
reset role;
select pg_temp.chk('C9 charge element discount → refused (next step) · legacy charge: alloc discount 2 · warning charge_discount_not_costed_yet · events 0 · legacy invoice with valid terms: no suggestion filled · warning discount_available:I2:11.30 · legacy_shape true', (:'c9a' like 'P0001 Charge CHG-79500: a discount on a charge bill is not put on stock cost yet%')::text || '/' || (select trim_scale(a.discount_amount)::text from public.po_payment_alloc a where a.po_payment_id = (:'p6_r'::jsonb->>'payment_id')::uuid) || '/' || (:'p6_r'::jsonb->'warnings' ? 'charge_discount_not_costed_yet:CHG-79500')::text || '/' || jsonb_array_length(:'p6_r'::jsonb->'cost_events') || '/' || trim_scale((:'pv7_r'::jsonb->'allocs'->0->>'discount')::numeric)::text || '/' || (:'pv7_r'::jsonb->'warnings' ? 'discount_available:PODISC4A2-I2:11.30')::text || '/' || (:'pv7_r'::jsonb->>'legacy_shape'), 'true/2/true/0/0/true/true');

-- ═══ C10 — 문지기 문장: uuid 없음 · 결제일 · 금액 · 통화 · reference · 「delete this payment and enter it again」 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select pg_temp.err(format('update public.po_payment set amount = 1 where id = %L', :'p4')) as g1 \gset
select pg_temp.err(format('update public.po_payment_alloc set discount_amount = 0 where id = %L', :'al4')) as g2 \gset
reset role;
select pg_temp.chk('C10 guard sentences: payment → "on the payment of 216 CAD dated 2026-10-10 (PODISC4A2-P4) … delete this payment and enter it again" · no uuid · alloc → "On this payment column … delete this payment and enter it again"', (:'g1' like 'P0001 Paid (216 → 1) and Discount taken (10 → 10) on the payment of 216 CAD dated 2026-10-10 (PODISC4A2-P4) are not edited here — to correct them, delete this payment and enter it again — nothing was saved')::text || '/' || (:'g1' !~ '[0-9a-f]{8}-[0-9a-f]{4}-')::text || '/' || (:'g2' like 'P0001 The amount (226 → 226) and discount (10 → 0) on this line are not edited here — change the amount in the On this payment column; to change the discount, delete this payment and enter it again — nothing was saved')::text, 'true/true/true');

-- ═══ C12 — 권한: anon 없음 · 속 함수 둘 authenticated 없음 · 열쇠 없는 직원 거부 ═══
set local role anon;
do $$ begin perform public.po_invoice_discount_parts(gen_random_uuid(), 1, null); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as an1 \gset
reset role;
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
do $$ begin perform public.po_payment_alloc_cost_events(gen_random_uuid(), false); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as au1 \gset
do $$ begin perform public.po_payment_alloc_cost_reverse(gen_random_uuid(), null); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as au2 \gset
select set_config('request.jwt.claims', :'n_claims', true);
do $$ begin perform public.po_payment_create(null, null, 1, null, 0, null, null, null, null, false); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
select current_setting('app.out', true) as nk1 \gset
do $$ begin perform public.po_doc_delete('payment', gen_random_uuid()); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
select current_setting('app.out', true) as nk2 \gset
reset role;
select pg_temp.chk('C12 anon parts → 42501 · authenticated inner events · reverse → 42501 · no-key staff create · delete → purchasing sentences', :'an1' || ',' || :'au1' || ',' || :'au2' || ',' || (:'nk1' = 'P0001 You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was saved')::text || ',' || (:'nk2' = 'P0001 You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was deleted')::text, '42501,42501,42501,true,true');

-- ═══ C13 — 실물 무변 · 재생성(receiving + purchasing claims · postgres) 가치 차이 +2.73 · deferred 0 ═══
select md5(string_agg(p.id::text || '|' || p.paid_on::text || '|' || p.amount::text || '|' || p.discount_taken::text || '|' || coalesce(p.reference, '') || '|' || p.currency_id::text, ',' order by p.id)) as real_pay_mid from public.po_payment p where coalesce(p.reference, '') not like 'PODISC4A2-%' \gset
select md5(string_agg(a.id::text || '|' || a.po_payment_id::text || '|' || coalesce(a.po_invoice_id::text, '') || '|' || coalesce(a.po_charge_id::text, '') || '|' || a.amount::text || '|' || a.discount_amount::text, ',' order by a.id)) as real_alloc_mid from public.po_payment_alloc a join public.po_payment p on p.id = a.po_payment_id where coalesce(p.reference, '') not like 'PODISC4A2-%' \gset
select md5(string_agg(i.id::text || '|' || i.invoice_number || '|' || i.status || '|' || i.total_amount::text || '|' || coalesce(i.due_date::text, '') || '|' || coalesce(i.early_discount_basis, ''), ',' order by i.id)) as real_inv_mid from public.po_invoice i where i.invoice_number not like 'PODISC4A2-%' and i.invoice_number <> '1030266656' \gset
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_mid from public.inv_layer l where l.sku not like 'DISC4A2-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by a.id)) as real_adds_mid from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC4A2-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text, ',' order by k.id)) as real_consume_mid from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC4A2-%' \gset
\if :{?mig}
\set ev_new 13
\else
\set ev_new 0
\endif
select pg_temp.chk('C13a real rows unchanged inside the test (payments · allocs · invoices except P&G · layers · adds · consume md5 = head) · real events = head + this round (trial 13 · confirm 0: the backfill is already in the head)', (:'real_pay_mid' = :'real_pay_head')::text || '/' || (:'real_alloc_mid' = :'real_alloc_head')::text || '/' || (:'real_inv_mid' = :'real_inv_head')::text || '/' || (:'real_layers_mid' = :'real_layers_head')::text || '/' || (:'real_adds_mid' = :'real_adds_head')::text || '/' || (:'real_consume_mid' = :'real_consume_head')::text || '/' || (select count(*) from public.inv_cost_adjust j join public.po_line pl on pl.id = j.po_line_id join public.po x on x.id = pl.po_id where x.po_number not like 'PO-795%'), 'true/true/true/true/true/true/' || (:real_events_head + :ev_new)::text);
select round(sum(unit_cost * qty), 4) as val_before from public.inv_layer where sku not like 'DISC4A2-%' \gset
select set_config('request.jwt.claims', :'g_claims', true);
select clock_timestamp() as ta0 \gset
select public.inv_layer_apply() as r \gset apply_
select clock_timestamp() as ta1 \gset
select 'timing: inv_layer_apply ms=' || round(extract(epoch from (:'ta1'::timestamptz - :'ta0'::timestamptz)) * 1000);
select round(sum(unit_cost * qty), 4) as val_after from public.inv_layer where sku not like 'DISC4A2-%' \gset
select 'C13 regen: value before=' || :val_before || ' after=' || :val_after || ' diff=' || (:val_after - :val_before)::text || ' · adjusts: ' || (:'apply_r'::jsonb->'ims'->'adjusts')::text;
select pg_temp.chk('C13b regen total value diff (real · fakes excluded) = +2.73 · adjusts deferred 0 · skipped 0 · P&G 13 pending not replayed (posted count = fake posted events)', round(:val_after - :val_before, 2)::text || '/' || (:'apply_r'::jsonb->'ims'->'adjusts'->>'deferred') || '/' || (:'apply_r'::jsonb->'ims'->'adjusts'->>'skipped') || '/' || (:'apply_r'::jsonb->'ims'->'adjusts'->>'posted') || '/' || (select count(*) from public.inv_cost_adjust where status = 'posted'), '2.73/0/0/' || (select count(*) from public.inv_cost_adjust where status = 'posted')::text || '/' || (select count(*) from public.inv_cost_adjust where status = 'posted')::text);

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select md5(string_agg(p.id::text || '|' || p.paid_on::text || '|' || p.amount::text || '|' || p.discount_taken::text || '|' || coalesce(p.reference, '') || '|' || p.currency_id::text, ',' order by p.id)) as real_pay_tail, count(*) as real_pay_tail_n from public.po_payment p where coalesce(p.reference, '') not like 'PODISC4A2-%' \gset
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_tail, count(*) as real_layers_tail_n from public.inv_layer l where l.sku not like 'DISC4A2-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by a.id)) as real_adds_tail, count(*) as real_adds_tail_n from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC4A2-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text, ',' order by k.id)) as real_consume_tail, count(*) as real_consume_tail_n from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC4A2-%' \gset
select 'REAL_SAME payments ' || (:'real_pay_head' = :'real_pay_tail')::text || ' (' || :real_pay_n || ' → ' || :real_pay_tail_n || ') layers ' || (:'real_layers_head' = :'real_layers_tail')::text || ' (' || :real_layers_n || ' → ' || :real_layers_tail_n || ') adds ' || (:'real_adds_head' = :'real_adds_tail')::text || ' (' || :real_adds_n || ' → ' || :real_adds_tail_n || ') consume ' || (:'real_consume_head' = :'real_consume_tail')::text || ' (' || :real_consume_n || ' → ' || :real_consume_tail_n || ')';
select setval('public.inv_layer_cost_add_id_seq', greatest((select max(id) from public.inv_layer_cost_add), :add_seq_last), true);
select setval('public.inv_layer_consume_id_seq', greatest((select max(id) from public.inv_layer_consume), :con_seq_last), true);
select 'seq tail po ' || last_value || ' ' || is_called from public.po_number_seq;
select 'seq tail rcv ' || last_value || ' ' || is_called from public.po_receipt_number_seq;
select 'seq tail cost_add ' || last_value || ' ' || is_called || ' (head ' || :add_seq_last || ' · reset to greatest(max, head))' from public.inv_layer_cost_add_id_seq;
select 'seq tail consume ' || last_value || ' ' || is_called || ' (head ' || :con_seq_last || ' · reset to greatest(max, head))' from public.inv_layer_consume_id_seq;
