-- po-disc-4b-verify.sql — To pay 창구 · 비용 청구서 할인 → landed(배분 비율 · landed 미얹힘 보류 · with_tax · 399) · 할인 고치기 창구 · 옛 모양 비용 할인 · CBSA 사건 · 권한 · 실물 무변 (Asung-IMS · 2026-10-09)
--   기대: 시험 갈래(-v mig) OK 17 · 확인 갈래 OK 15(= 17 − 시험 전용 2: G0 · D0a) · MISMATCH 0 · 증감 기대는 두 갈래(\if :{?mig})
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/<ts>_po_disc_4b.sql -f supabase/tests/po-disc-4b-verify.sql > /tmp/po-disc-4b.out 2>&1; echo "rc=$?"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료는 가짜만(PO-796xx · PODISC4B-* · CHG-796xx · RCV-796xx · 가짜 공급처 · 결제조건 · 직원) · CBSA 검사만 실제 행을 읽는다 · 끝은 rollback · identity 시퀀스는 greatest(실제 최대, 머리)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as po_seq_last, is_called as po_seq_called from public.po_number_seq \gset
select last_value as rcv_seq_last, is_called as rcv_seq_called from public.po_receipt_number_seq \gset
select last_value as add_seq_last, is_called as add_seq_called from public.inv_layer_cost_add_id_seq \gset
select last_value as con_seq_last, is_called as con_seq_called from public.inv_layer_consume_id_seq \gset
\echo '== seq head po' :po_seq_last :po_seq_called 'rcv' :rcv_seq_last :rcv_seq_called 'cost_add' :add_seq_last :add_seq_called 'consume' :con_seq_last :con_seq_called
select md5(string_agg(p.id::text || '|' || p.paid_on::text || '|' || p.amount::text || '|' || p.discount_taken::text || '|' || coalesce(p.reference, ''), ',' order by p.id)) as real_pay_head, count(*) as real_pay_n from public.po_payment p where coalesce(p.reference, '') not like 'PODISC4B-%' \gset
select md5(string_agg(a.id::text || '|' || coalesce(a.po_invoice_id::text, '') || '|' || coalesce(a.po_charge_id::text, '') || '|' || a.amount::text || '|' || a.discount_amount::text || '|' || a.discount_tax_part::text, ',' order by a.id)) as real_alloc_head, count(*) as real_alloc_n from public.po_payment_alloc a join public.po_payment p on p.id = a.po_payment_id where coalesce(p.reference, '') not like 'PODISC4B-%' \gset
select md5(string_agg(c.id::text || '|' || c.charge_number || '|' || c.status || '|' || c.total_amount::text || '|' || c.tax_amount::text, ',' order by c.id)) as real_chg_head, count(*) as real_chg_n from public.po_charge c where c.charge_number not like 'CHG-796%' \gset
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_head, count(*) as real_layers_n from public.inv_layer l where l.sku not like 'DISC4B-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by a.id)) as real_adds_head, count(*) as real_adds_n from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC4B-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text, ',' order by k.id)) as real_consume_head, count(*) as real_consume_n from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC4B-%' \gset
select count(*) as real_events_head from public.inv_cost_adjust \gset
\echo '== real head payments' :real_pay_n :real_pay_head 'allocs' :real_alloc_n 'charges' :real_chg_n 'layers' :real_layers_n :real_layers_head 'adds' :real_adds_n 'consume' :real_consume_n 'events' :real_events_head

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

-- ═══ 재료(postgres · 가짜) — 직원 둘 · 공급처 · 결제조건 · 제품 6 · PO 6(E3 PO-79600 2줄 · E2 PO-79601 · 79602 · E4/E6 PO-79603 · E5 PO-79604 · 인보이스용 PO-79605) · 인보이스 셋 + 비용 넷 ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc4b-g@test.invalid', 'PODISC4B Purchasing+Receiving', 'manager', '["purchasing","receiving"]'::jsonb) returning auth_user_id::text as g_uid, id::text as g_sid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc4b-n@test.invalid', 'PODISC4B NoKeys', 'manager', '[]'::jsonb) returning auth_user_id::text as n_uid \gset
\set g_claims '{"sub":"' :g_uid '","role":"authenticated"}'
\set n_claims '{"sub":"' :n_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.id::text as bin, b.name as binname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select id::text as hst, name as hstname from public.ref_tax_rule where direction = 'purchase' and is_active and name = 'HST ON (Purchase)' limit 1 \gset
insert into public.ref_payment_term (name, source, net_days, discount_days, discount_percent) values ('PODISC4B 2.1%13 Net30', 'manual', 30, 13, 2.1) returning id::text as t1 \gset
insert into public.supplier (name, payment_term_name, account_payable_code, currency_id) values ('PODISC4B Supplier', 'Net 30', '2000', :'cad'::uuid) returning id::text as sup \gset
insert into public.product (sku, name, source) select 'DISC4B-P' || i, 'PODISC4B P' || i, 'manual' from generate_series(1, 6) i;
set local session_replication_role = replica;
insert into public.po (po_number, status, supplier_id, currency_id, order_date, ship_to_warehouse_id, confirmed_at, payment_term_id, payment_term_name, tax_rule_id, tax_rule) values
  ('PO-79600', 'confirmed', :'sup'::uuid, :'cad'::uuid, '2026-10-01', :'wh'::uuid, now(), null, null, :'hst'::uuid, :'hstname'),
  ('PO-79601', 'confirmed', :'sup'::uuid, :'cad'::uuid, '2026-10-01', :'wh'::uuid, now(), null, null, :'hst'::uuid, :'hstname'),
  ('PO-79602', 'confirmed', :'sup'::uuid, :'cad'::uuid, '2026-10-01', :'wh'::uuid, now(), null, null, :'hst'::uuid, :'hstname'),
  ('PO-79603', 'confirmed', :'sup'::uuid, :'cad'::uuid, '2026-10-01', :'wh'::uuid, now(), null, null, :'hst'::uuid, :'hstname'),
  ('PO-79604', 'confirmed', :'sup'::uuid, :'cad'::uuid, '2026-10-01', :'wh'::uuid, now(), null, null, :'hst'::uuid, :'hstname'),
  ('PO-79605', 'confirmed', :'sup'::uuid, :'cad'::uuid, '2026-10-01', :'wh'::uuid, now(), :'t1'::uuid, 'PODISC4B 2.1%13 Net30', :'hst'::uuid, :'hstname');
select string_agg(id::text, ' ' order by po_number) as pos from public.po where po_number like 'PO-796%' \gset
select split_part(:'pos', ' ', 1) as po0, split_part(:'pos', ' ', 2) as po1, split_part(:'pos', ' ', 3) as po2, split_part(:'pos', ' ', 4) as po3, split_part(:'pos', ' ', 5) as po4, split_part(:'pos', ' ', 6) as po5 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po0'::uuid, 1, id, 100, 10.00 from public.product where sku = 'DISC4B-P1';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po0'::uuid, 2, id, 50, 4.00 from public.product where sku = 'DISC4B-P2';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po1'::uuid, 1, id, 100, 6.00 from public.product where sku = 'DISC4B-P3';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po2'::uuid, 1, id, 100, 2.00 from public.product where sku = 'DISC4B-P4';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po3'::uuid, 1, id, 100, 5.00 from public.product where sku = 'DISC4B-P5';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po4'::uuid, 1, id, 10, 1.00 from public.product where sku = 'DISC4B-P6';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po5'::uuid, 1, id, 100, 10.00 from public.product where sku = 'DISC4B-P1';
select pl.id::text as l1 from public.po_line pl where pl.po_id = :'po0'::uuid and pl.line_no = 1 \gset
select pl.id::text as l2 from public.po_line pl where pl.po_id = :'po0'::uuid and pl.line_no = 2 \gset
select pl.id::text as l3 from public.po_line pl where pl.po_id = :'po1'::uuid \gset
select pl.id::text as l4 from public.po_line pl where pl.po_id = :'po2'::uuid \gset
select pl.id::text as l5 from public.po_line pl where pl.po_id = :'po3'::uuid \gset
select pl.id::text as l6 from public.po_line pl where pl.po_id = :'po4'::uuid \gset
select pl.id::text as l7 from public.po_line pl where pl.po_id = :'po5'::uuid \gset
-- 비용 넷(확정 · CAD) — CHG-79600 → PO-79600 100(E3 · landed 미얹힘) · CHG-79601 → PO-79601 60 + PO-79602 40(E2 · landed 얹힘) · CHG-79602 → PO-79603 100 + tax 13(E4 with_tax) · CHG-79603 → PO-79604 5(E5 399)
insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, tax_amount, status, confirmed_at) values
  (:'sup'::uuid, 'CHG-79600', '2026-10-05', 'freight', :'cad'::uuid, 100, 0, 'confirmed', now()),
  (:'sup'::uuid, 'CHG-79601', '2026-10-05', 'freight', :'cad'::uuid, 100, 0, 'confirmed', now()),
  (:'sup'::uuid, 'CHG-79602', '2026-10-05', 'duty',    :'cad'::uuid, 100, 13, 'confirmed', now()),
  (:'sup'::uuid, 'CHG-79603', '2026-10-05', 'freight', :'cad'::uuid, 5, 0, 'confirmed', now());
select id::text as c0 from public.po_charge where charge_number = 'CHG-79600' \gset
select id::text as c1 from public.po_charge where charge_number = 'CHG-79601' \gset
select id::text as c2 from public.po_charge where charge_number = 'CHG-79602' \gset
select id::text as c3 from public.po_charge where charge_number = 'CHG-79603' \gset
insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (:'c0'::uuid, :'po0'::uuid, 100), (:'c1'::uuid, :'po1'::uuid, 60), (:'c1'::uuid, :'po2'::uuid, 40), (:'c2'::uuid, :'po3'::uuid, 100), (:'c3'::uuid, :'po4'::uuid, 5);
-- 인보이스 — I1(PO-79600 · 두 줄 · E3 확정 길의 요건) · I2(PO-79605 · 조건 2.1%/13 · E1 · E6 잠금) — 창구로(purchasing) · 확정은 replica
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select (public.po_invoice_create('invoice', 'PODISC4B-I1', :'po0'::uuid, null, null, '2026-10-02', null, 1356.00, true, true, null))->>'id' as i1 \gset
select (public.po_invoice_create('invoice', 'PODISC4B-I2', :'po5'::uuid, null, null, '2026-10-08', null, 1130.00, true, true, null))->>'id' as i2 \gset
select (public.po_invoice_create('invoice', 'PODISC4B-I3', :'po5'::uuid, null, null, '2026-09-01', null, 0, true, false, null))->>'committed' as i3_preview \gset
reset role;
set local session_replication_role = replica;
update public.po_invoice set status = 'confirmed', confirmed_at = now() where invoice_number in ('PODISC4B-I1', 'PODISC4B-I2');
-- 레이어 — E3: RCV-79600(PO-79600 L1 100 · 옛 규칙 입고 = landed 안 얹힘) · E2: RCV-79601(PO-79601 100) · RCV-79602(PO-79602 100) · E4: RCV-79603(PO-79603 100) · E5: RCV-79604(PO-79604 10) — 확정 입고 + 원장 + 창구
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at) values
  ('RCV-79600', :'po0'::uuid, :'wh'::uuid, '2026-10-02', 'confirmed', now()), ('RCV-79601', :'po1'::uuid, :'wh'::uuid, '2026-10-02', 'confirmed', now()), ('RCV-79602', :'po2'::uuid, :'wh'::uuid, '2026-10-02', 'confirmed', now()),
  ('RCV-79603', :'po3'::uuid, :'wh'::uuid, '2026-10-02', 'confirmed', now()), ('RCV-79604', :'po4'::uuid, :'wh'::uuid, '2026-10-02', 'confirmed', now());
select id::text as r0 from public.po_receipt where receipt_number = 'RCV-79600' \gset
select id::text as r1 from public.po_receipt where receipt_number = 'RCV-79601' \gset
select id::text as r2 from public.po_receipt where receipt_number = 'RCV-79602' \gset
select id::text as r3 from public.po_receipt where receipt_number = 'RCV-79603' \gset
select id::text as r4 from public.po_receipt where receipt_number = 'RCV-79604' \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, source, raw) values
  ('2026-10-02', 1, 'DISC4B-P1', :'whname', :'binname', 100, 'po_in', 'purchase', 'RCV-79600', :'r0', :'l1', 'ims', '{"fake":"po-disc-4b"}'),
  ('2026-10-02', 1, 'DISC4B-P3', :'whname', :'binname', 100, 'po_in', 'purchase', 'RCV-79601', :'r1', :'l3', 'ims', '{"fake":"po-disc-4b"}'),
  ('2026-10-02', 1, 'DISC4B-P4', :'whname', :'binname', 100, 'po_in', 'purchase', 'RCV-79602', :'r2', :'l4', 'ims', '{"fake":"po-disc-4b"}'),
  ('2026-10-02', 1, 'DISC4B-P5', :'whname', :'binname', 100, 'po_in', 'purchase', 'RCV-79603', :'r3', :'l5', 'ims', '{"fake":"po-disc-4b"}'),
  ('2026-10-02', 1, 'DISC4B-P6', :'whname', :'binname', 10,  'po_in', 'purchase', 'RCV-79604', :'r4', :'l6', 'ims', '{"fake":"po-disc-4b"}');
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status) values ('RCV-79605', :'po0'::uuid, :'wh'::uuid, '2026-10-06', 'draft') returning id::text as r5 \gset
insert into public.po_receipt_work (receipt_id, po_line_id, qty_ea, bin_id, putaway_done, count_method, counted_by, counted_at) values (:'r5'::uuid, :'l2'::uuid, 50, :'bin'::uuid, true, 'manual', :'g_sid'::uuid, now());
set local session_replication_role = origin;
select set_config('request.jwt.claims', :'g_claims', true);
select public.inv_layer_post_receipt(:'r0'::uuid) as r \gset f0_
select public.inv_layer_post_receipt(:'r1'::uuid) as r \gset f1_
select public.inv_layer_post_receipt(:'r2'::uuid) as r \gset f2_
select public.inv_layer_post_receipt(:'r3'::uuid) as r \gset f3_
select public.inv_layer_post_receipt(:'r4'::uuid) as r \gset f4_
select y.id::text as y1 from public.inv_layer y where y.doc_number = 'RCV-79600' and y.line_ref = :'l1' \gset
select y.id::text as y3 from public.inv_layer y where y.doc_number = 'RCV-79601' \gset
select y.id::text as y4 from public.inv_layer y where y.doc_number = 'RCV-79602' \gset
select y.id::text as y5 from public.inv_layer y where y.doc_number = 'RCV-79603' \gset
select y.id::text as y6 from public.inv_layer y where y.doc_number = 'RCV-79604' \gset
-- landed 얹기(E2 · E4 · E5) — post_charge(invoker · purchasing claims · postgres) · CHG-79600 은 일부러 안 얹는다(E3)
select public.inv_layer_post_charge(:'c1'::uuid) as r \gset pc1_
select public.inv_layer_post_charge(:'c2'::uuid) as r \gset pc2_
select public.inv_layer_post_charge(:'c3'::uuid) as r \gset pc3_
insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) values (:'y3'::bigint, 'sale', 'SO-79600', 'DISC4B-P3:1', 'sale_out', '2026-10-06', 25, 6.60, 165, 'sale');
select pg_temp.chk('M fake material: charges 4 · allocs 5 · layers 5 (P1 100@10 · P3 100@6 · P4 100@2 · P5 100@5 · P6 10@1) · landed posted CHG-79601 (60 → y3 · 40 → y4) · CHG-79602 100 → y5 · CHG-79603 5 → y6 · CHG-79600 none (posted_on null) · I1 1356 · I2 1130 (2.1% until 10-21)', (select count(*) from public.po_charge where charge_number like 'CHG-796%')::text || '/' || (select count(*) from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id where c.charge_number like 'CHG-796%') || '/' || (select count(*) from public.inv_layer where sku like 'DISC4B-%') || '/' || (select string_agg(trim_scale(y.unit_cost)::text, ',' order by y.sku) from public.inv_layer y where y.sku like 'DISC4B-%') || '/' || (select string_agg(x.doc_number || ':' || trim_scale(x.amount)::text, ',' order by x.doc_number, x.amount) from public.inv_layer_cost_add x join public.inv_layer y on y.id = x.layer_id where y.sku like 'DISC4B-%' and x.kind = 'landed') || '/' || (select count(*) from public.po_charge_alloc a where a.po_charge_id = :'c0'::uuid and a.posted_on is not null) || '/' || (select trim_scale(payable_net)::text from public.po_invoice_money where id = :'i1'::uuid) || '/' || (select trim_scale(m.payable_net)::text || '/' || i.early_discount_until::text from public.po_invoice_money m join public.po_invoice i on i.id = m.id where i.id = :'i2'::uuid), '4/5/5/10,6,2,5,1/CHG-79601:40,CHG-79601:60,CHG-79602:100,CHG-79603:5/0/1356/1130/2026-10-21');

-- ═══ D0 · G0 — 적용 전(시험 갈래): 비용 청구서 원소 discount 거부(④-a2) · 옛 모양 경고 있음 · 재발행 원본 md5 · To pay 없음 ═══
\if :{?mig}
select pg_temp.chk('G0 last defs: po_payment_create 0e991ab1 · po_payment_alloc_cost_events 76c991df (uuid, boolean) · no po_pay_candidates · no discount_set', (select string_agg(left(md5(p.prosrc), 8), ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('po_payment_create', 'po_payment_alloc_cost_events')) || '/' || (to_regprocedure('public.po_payment_alloc_cost_events(uuid, boolean)') is not null)::text || '/' || (to_regprocedure('public.po_pay_candidates(uuid, uuid, date)') is null)::text || '/' || (to_regprocedure('public.po_payment_alloc_discount_set(uuid, numeric, boolean, text)') is null)::text, '76c991df,0e991ab1/true/true/true');
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select pg_temp.chk('D0a before: charge element discount refused (④-a2) · legacy charge discount warns charge_discount_not_costed_yet and makes no events · CBSA events 0', (pg_temp.err(format('select public.po_payment_create(%L::uuid, ''2026-10-10'', 95, %L::uuid, 0, null, ''PODISC4B-D0'', null, jsonb_build_array(jsonb_build_object(''kind'', ''charge'', ''id'', %L, ''amount'', 100, ''discount'', 5)), false)', :'sup', :'cad', :'c1')) like 'P0001 Charge CHG-79601: a discount on a charge bill is not put on stock cost yet%')::text || '/' || ((public.po_payment_create(:'sup'::uuid, '2026-10-10', 95, :'cad'::uuid, 5, null, 'PODISC4B-D0', null, jsonb_build_array(jsonb_build_object('kind', 'charge', 'id', :'c1', 'amount', 100)), false))->'warnings' ? 'charge_discount_not_costed_yet:CHG-79601')::text || '/' || (select count(*) from public.inv_cost_adjust j join public.po_payment_alloc a on a.id = j.source_id join public.po_charge c on c.id = a.po_charge_id where c.charge_number = '10039192310530'), 'true/true/0');
reset role;
\i :mig
\endif
select pg_temp.chk('G1 untouched: cost_reverse 33062d78 · alloc_delete d2bbb0be · po_doc_delete 0eb94ef2 · alloc_set 64c2c53a · guards 70a0d11d · f43a18bc · post_cost_adjust 1f95d60c · post_charge bf36eb2c · confirm_by 857021b6 · invoice_parts 77b97c1b · views charge_money d6c4df08 · charge_list f539b0c0 · invoice_list ded8f573', (select string_agg(left(md5(p.prosrc), 8), ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('po_payment_alloc_cost_reverse', 'po_payment_alloc_delete', 'po_doc_delete', 'po_payment_alloc_set', 'po_payment_guard', 'po_payment_alloc_guard', 'inv_layer_post_cost_adjust', 'inv_layer_post_charge', 'po_receipt_confirm_by', 'po_invoice_discount_parts')) || '/' || left(md5(pg_get_viewdef('public.po_charge_money'::regclass)), 8) || ',' || left(md5(pg_get_viewdef('public.po_charge_list'::regclass)), 8) || ',' || left(md5(pg_get_viewdef('public.po_invoice_list'::regclass)), 8), 'bf36eb2c,1f95d60c,0eb94ef2,77b97c1b,33062d78,d2bbb0be,f43a18bc,64c2c53a,70a0d11d,857021b6/d6c4df08,f539b0c0,ded8f573');

-- ═══ E9 — CBSA(⬜2 · 양 갈래): 사건 둘 pending · −39.00(PO-02002a) · −11.95(PO-02001a) · landed 0 · 결제 · 충당 무변 ═══
select pg_temp.chk('E9 CBSA: events 2 · pending · charge_alloc · −39,−11.95 (sum −50.95 = amount_doc · fx null) · held note · landed rows 0 · payment 2496.42/50.95 · alloc 2547.37/50.95/0', (select count(*)::text || '/' || string_agg(distinct j.status || ':' || j.target_type, ',') || '/' || string_agg(trim_scale(j.amount_cad)::text || ':' || coalesce(p.po_number, '?'), ',' order by p.po_number) || '/' || trim_scale(sum(j.amount_doc))::text || '/' || bool_and(j.exchange_rate is null and j.note like '%held: landed not on cost yet%')::text from public.inv_cost_adjust j join public.po_payment_alloc a on a.id = j.source_id join public.po_charge c on c.id = a.po_charge_id join public.po_charge_alloc ca on ca.id = j.po_charge_alloc_id left join public.po p on p.id = ca.po_id where c.charge_number = '10039192310530') || '/' || (select count(*) from public.inv_layer_cost_add x where x.doc_number = '10039192310530') || '/' || (select trim_scale(p.amount)::text || '/' || trim_scale(p.discount_taken)::text || '/' || trim_scale(a.amount)::text || '/' || trim_scale(a.discount_amount)::text || '/' || trim_scale(a.discount_tax_part)::text from public.po_payment p join public.po_payment_alloc a on a.po_payment_id = p.id where p.reference = 'EFT-20260916-02'), '2/pending:charge_alloc/-11.95:PO-02001a,-39:PO-02002a/-50.95/true/0/2496.42/50.95/2547.37/50.95/0');

-- ═══ E1 — To pay(purchasing 직원): 인보이스 I2(기한 안) · I1(조건 없음) + 비용 넷 · 결제일 바꿔 부르기 · 정렬 · 비용 discount null · 실물 포함 전체 시간 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select clock_timestamp() as tc0 \gset
select count(*) as cand_n, coalesce(sum(unpaid), 0) as cand_unpaid from public.po_pay_candidates(null, null, null) \gset
select clock_timestamp() as tc1 \gset
select jsonb_agg(jsonb_build_object('kind', c.kind, 'number', c.number, 'unpaid', c.unpaid, 'disc', c.discount_available, 'valid', c.discount_valid, 'expired', c.discount_expired, 'src', c.terms_source, 'until', c.early_discount_until) order by c.number) as e1 from public.po_pay_candidates(:'sup'::uuid, :'cad'::uuid, '2026-10-21') c \gset
select jsonb_agg(c.number order by c.number) as e1b from public.po_pay_candidates(:'sup'::uuid, :'cad'::uuid, '2026-10-22') c where c.discount_expired \gset
select string_agg(c.number, ',') as e1c from public.po_pay_candidates(:'sup'::uuid, :'cad'::uuid, null) c \gset
reset role;
select 'timing: po_pay_candidates (all suppliers · real + fake) ms=' || round(extract(epoch from (:'tc1'::timestamptz - :'tc0'::timestamptz)) * 1000) || ' rows=' || :cand_n;
select pg_temp.chk('E1 To pay (supplier · CAD · 2026-10-21): rows 6 · I2 disc 21 (pre_tax 1000 × 2.1%) valid · I1 no terms (null) · charges discount null · unpaid incl. tax (CHG-79602 113) · on 10-22 I2 expired · sort: valid-discount invoice first, then by due/number', jsonb_array_length(:'e1'::jsonb) || '/' || (select trim_scale((x->>'disc')::numeric)::text || '/' || (x->>'valid') || '/' || (x->>'src') from jsonb_array_elements(:'e1'::jsonb) x where x->>'number' = 'PODISC4B-I2') || '/' || (select coalesce(x->>'disc', 'null') || '/' || coalesce(x->>'src', 'null') from jsonb_array_elements(:'e1'::jsonb) x where x->>'number' = 'PODISC4B-I1') || '/' || (select coalesce(x->>'disc', 'null') || '/' || trim_scale((x->>'unpaid')::numeric)::text from jsonb_array_elements(:'e1'::jsonb) x where x->>'number' = 'CHG-79602') || '/' || (:'e1b'::jsonb)::text || '/' || split_part(:'e1c', ',', 1), '6/21/true/invoice/null/null/null/113/["PODISC4B-I2"]/PODISC4B-I2');

-- ═══ E2 — 비용 청구서 할인 · 배분 둘 · landed 이미 얹힘 · 일부 판매: 배분 비율 60:40 · 사건 둘 posted · landed 낮춤 · cost_late 음수 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 92, :'cad'::uuid, 0, null, 'PODISC4B-P1', null, jsonb_build_array(jsonb_build_object('kind', 'charge', 'id', :'c1', 'amount', 97, 'discount', 5)), false) as r \gset pv1_
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 92, :'cad'::uuid, 0, null, 'PODISC4B-P1', null, jsonb_build_array(jsonb_build_object('kind', 'charge', 'id', :'c1', 'amount', 97, 'discount', 5)), true) as r \gset p1_
reset role;
select (:'p1_r'::jsonb->>'payment_id') as p1 \gset
select a.id::text as al1 from public.po_payment_alloc a where a.po_payment_id = :'p1'::uuid \gset
select pg_temp.chk('E2 charge discount 5 on a partial payment 92 + 5 = 97 of 100 (pre_tax · tax 0): preview parts cost 5 / tax 0 · events 2 posted (PO-79601 −3 · PO-79602 −2) · landed_posted true · y3 adds 60 − 3 = 57 · cost_late −0.75 (25 of 100 sold) · y4 adds 40 − 2 = 38 · discount_taken 5 · held 0', trim_scale((:'pv1_r'::jsonb->'allocs'->0->>'cost_part')::numeric)::text || '/' || trim_scale((:'pv1_r'::jsonb->'allocs'->0->>'tax_part')::numeric)::text || '/' || (:'pv1_r'::jsonb->'allocs'->0->>'discount_basis') || '/' || (:'p1_r'::jsonb->'cost_events'->0->>'event_count') || '/' || (select string_agg(trim_scale(j.amount_doc)::text || ':' || j.status || ':' || p.po_number, ',' order by p.po_number) from public.inv_cost_adjust j join public.po_charge_alloc ca on ca.id = j.po_charge_alloc_id join public.po p on p.id = ca.po_id where j.source_id = :'al1'::uuid) || '/' || (:'p1_r'::jsonb->'cost_events'->0->'events'->0->>'landed_posted') || '/' || (select trim_scale(sum(x.amount))::text from public.inv_layer_cost_add x where x.layer_id = :'y3'::bigint) || '/' || (select trim_scale(k.amount)::text from public.inv_layer_consume k where k.layer_id = :'y3'::bigint and k.reason = 'cost_late') || '/' || (select trim_scale(sum(x.amount))::text from public.inv_layer_cost_add x where x.layer_id = :'y4'::bigint) || '/' || (select trim_scale(discount_taken)::text from public.po_payment where id = :'p1'::uuid) || '/' || (:'p1_r'::jsonb->'cost_events'->0->>'held_landed_not_posted'), '5/0/pre_tax/2/-3:posted:PO-79601,-2:posted:PO-79602/true/57/-0.75/38/5/0');

-- ═══ E3 — landed 아직 안 얹힘(레이어 있음): 사건 pending(held) · 그 뒤 입고 확정(RCV-79605) → ⓕ landed → ⓖ 할인 함께 posted ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 90, :'cad'::uuid, 0, null, 'PODISC4B-P2', null, jsonb_build_array(jsonb_build_object('kind', 'charge', 'id', :'c0', 'amount', 100, 'discount', 10)), true) as r \gset p2_
reset role;
select (:'p2_r'::jsonb->>'payment_id') as p2 \gset
select a.id::text as al2 from public.po_payment_alloc a where a.po_payment_id = :'p2'::uuid \gset
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_receipt_confirm_by(:'g_sid'::uuid, :'r5'::uuid) as r \gset cf_
select y.id::text as y2 from public.inv_layer y where y.doc_number = 'RCV-79605' \gset
select pg_temp.chk('E3 held: event pending (landed_posted false · held 1 · layers exist) · add rows after the confirm 2 (y1 · y2) · receipt confirm: charges posted CHG-79600 (+100 across y1 1000 · y2 200 → 83.33/16.67) · adjustments posted 1 (−10) · event posted · y1 adds 83.33 − 8.33 = 75 · y2 adds 16.67 − 1.67 = 15', (:'p2_r'::jsonb->'cost_events'->0->'events'->0->>'status') || '/' || (:'p2_r'::jsonb->'cost_events'->0->'events'->0->>'landed_posted') || '/' || (:'p2_r'::jsonb->'cost_events'->0->>'held_landed_not_posted') || '/' || (select count(*) from public.inv_layer_cost_add x where x.line_ref = 'adj:' || (select j.id::text from public.inv_cost_adjust j where j.source_id = :'al2'::uuid)) || '/' || (:'cf_r'::jsonb->'charges'->'posted'->0->>'charge_number') || '/' || jsonb_array_length(:'cf_r'::jsonb->'adjustments'->'posted') || '/' || trim_scale((:'cf_r'::jsonb->'adjustments'->'posted'->0->>'posted_cad')::numeric)::text || '/' || (select j.status from public.inv_cost_adjust j where j.source_id = :'al2'::uuid) || '/' || (select trim_scale(sum(x.amount))::text from public.inv_layer_cost_add x where x.layer_id = :'y1'::bigint) || '/' || (select trim_scale(sum(x.amount))::text from public.inv_layer_cost_add x where x.layer_id = :'y2'::bigint), 'pending/false/1/2/CHG-79600/1/-10/posted/75/15');

-- ═══ E4 — with_tax 기준(tax 13 > 0): 세금 몫 기록 · tax 0 이면 기준 무관(식 함수 직접) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 101.70, :'cad'::uuid, 0, null, 'PODISC4B-P3', null, jsonb_build_array(jsonb_build_object('kind', 'charge', 'id', :'c2', 'amount', 113, 'discount', 11.30, 'discount_basis', 'with_tax')), true) as r \gset p3_
select pg_temp.err(format('select public.po_payment_create(%L::uuid, ''2026-10-10'', 1, %L::uuid, 0, null, ''PODISC4B-P3x'', null, jsonb_build_array(jsonb_build_object(''kind'', ''charge'', ''id'', %L, ''amount'', 2, ''discount'', 1, ''discount_basis'', ''net'')), false)', :'sup', :'cad', :'c3')) as bad_basis \gset
reset role;
select (:'p3_r'::jsonb->>'payment_id') as p3 \gset
select a.id::text as al3 from public.po_payment_alloc a where a.po_payment_id = :'p3'::uuid \gset
select pg_temp.chk('E4 with_tax 11.30 on 100 + 13: tax_part 1.30 · cost 10 · alloc tax_part 1.30 · event −10 posted · y5 adds 100 − 10 = 90 · tax 0 charge: parts(pre_tax) = parts(with_tax) · bad basis refused', trim_scale((:'p3_r'::jsonb->'allocs'->0->>'tax_part')::numeric)::text || '/' || trim_scale((:'p3_r'::jsonb->'allocs'->0->>'cost_part')::numeric)::text || '/' || (select trim_scale(discount_tax_part)::text from public.po_payment_alloc where id = :'al3'::uuid) || '/' || (select trim_scale(j.amount_doc)::text || ':' || j.status from public.inv_cost_adjust j where j.source_id = :'al3'::uuid) || '/' || (select trim_scale(sum(x.amount))::text from public.inv_layer_cost_add x where x.layer_id = :'y5'::bigint) || '/' || (select (a.cost_part = b.cost_part and a.tax_part = 0 and b.tax_part = 0)::text from public.po_charge_discount_parts(:'c1'::uuid, 5, 'pre_tax') a, public.po_charge_discount_parts(:'c1'::uuid, 5, 'with_tax') b) || '/' || (:'bad_basis' like 'P0001 p_targets[] discount_basis must be pre_tax or with_tax (got net for CHG-79603)%')::text, trim_scale(round(11.30 * 13 / 113.0, 2))::text || '/' || trim_scale(11.30 - round(11.30 * 13 / 113.0, 2))::text || '/' || trim_scale(round(11.30 * 13 / 113.0, 2))::text || '/-10:posted/90/true/true');

-- ═══ E5 — 판정 399: 비용 할인 20 > 레이어 원가(10 + landed 5) → 결제 전체 저장 안 됨 ═══
insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref) values (:'y6'::bigint, 'settlement_discount', -12, '2026-10-08', 'DISC4B-PRE', 'pre');   -- 앞선 조정으로 y6 원가를 10 + 5 − 12 = 3 으로(할인 ≤ 배분 ≤ landed 라 그냥은 399 에 못 닿는다 — 이견)
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select pg_temp.err(format('select public.po_payment_create(%L::uuid, ''2026-10-10'', 0.50, %L::uuid, 0, null, ''PODISC4B-P4'', null, jsonb_build_array(jsonb_build_object(''kind'', ''charge'', ''id'', %L, ''amount'', 5, ''discount'', 4.50)), true)', :'sup', :'cad', :'c3')) as e5 \gset
reset role;
select pg_temp.chk('E5 ruling 399 on a charge discount: y6 cost 10 + landed 5 − earlier adjust 12 = 3 < share 4.50 → refused with the layer sentence · payment P4 not saved · no allocation · no event on CHG-79603 allocations', (:'e5' like 'P0001 Cost adjustment % is a credit larger than the cost of the goods on layer %')::text || '/' || (select count(*) from public.po_payment where reference = 'PODISC4B-P4') || '/' || (select count(*) from public.inv_cost_adjust j where j.po_charge_alloc_id in (select id from public.po_charge_alloc where po_charge_id = :'c3'::uuid)), 'true/0/0');

-- ═══ E6 · E7 — 할인 고치기(E2 의 충당 al1 · posted 사건 둘): 미리 보기(쓰기 0) · 올림 5 → 8 · 내림 → 2 · 0(되돌림만 · 인보이스 잠금 풀림) · 미지급 초과 거부 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_alloc_discount_set(:'al1'::uuid, 8, false) as r \gset ds0_
select (select count(*) from public.inv_cost_adjust j where j.source_id = :'al1'::uuid) as ev_after_preview \gset
select trim_scale(amount)::text || '/' || trim_scale(discount_amount)::text as al_after_preview from public.po_payment_alloc where id = :'al1'::uuid \gset
select public.po_payment_alloc_discount_set(:'al1'::uuid, 8, true) as r \gset ds1_
select public.po_payment_alloc_discount_set(:'al1'::uuid, 2, true) as r \gset ds2_
select pg_temp.err(format('select public.po_payment_alloc_discount_set(%L::uuid, 9, true)', :'al1')) as ds_over \gset
reset role;
select pg_temp.chk('E7 preview: committed false · before amount 97 / discount 5 / events 2 · after amount 100 / discount 8 · cost 8 · no writes (events still 2 · alloc 100/5)', (:'ds0_r'::jsonb->>'committed') || '/' || trim_scale((:'ds0_r'::jsonb->'before'->>'amount')::numeric)::text || '/' || trim_scale((:'ds0_r'::jsonb->'before'->>'discount')::numeric)::text || '/' || (:'ds0_r'::jsonb->'before'->>'event_count') || '/' || trim_scale((:'ds0_r'::jsonb->'after'->>'amount')::numeric)::text || '/' || trim_scale((:'ds0_r'::jsonb->'after'->>'discount')::numeric)::text || '/' || trim_scale((:'ds0_r'::jsonb->'after'->>'cost_part')::numeric)::text || '/' || :ev_after_preview || '/' || :'al_after_preview', 'false/97/5/2/100/8/8/2/97/5');
select pg_temp.chk('E6 raise 5 → 8: alloc 100/8 · payment amount 92 fixed · discount_taken 8 · reversed 2 · new events 2 (−4.8 · −3.2) · y3 adds 60 − 3 + 3 − 4.8 = 55.2 · lower 8 → 2: alloc 94/2 · y3 adds 60 − 4.8 + 4.8 − 1.2 = 58.8 · over unpaid (9 → alloc 101 > 100) refused', (select trim_scale(amount)::text || '/' || trim_scale(discount_amount)::text from public.po_payment_alloc where id = :'al1'::uuid) || '/' || (select trim_scale(p.amount)::text || '/' || trim_scale(p.discount_taken)::text from public.po_payment p where p.id = :'p1'::uuid) || '/' || (:'ds1_r'::jsonb->'reversed'->>'reversed') || '/' || (:'ds1_r'::jsonb->'cost_events'->>'event_count') || '/' || (select string_agg(trim_scale((x->>'amount_doc')::numeric)::text, ',' order by x->>'target') from jsonb_array_elements(:'ds1_r'::jsonb->'cost_events'->'events') x) || '/' || (:'ds2_r'::jsonb->'reversed'->>'reversed') || '/' || (select trim_scale(sum(x.amount))::text from public.inv_layer_cost_add x where x.layer_id = :'y3'::bigint) || '/' || (:'ds_over' like 'P0001 Charge CHG-79601: allocating 101 but only 100 is unpaid — nothing was saved')::text, '94/2/92/2/2/2/-4.8,-3.2/2/58.8/true');
-- 잠금(⬜4): 인보이스 I2 에 할인 결제 → 조건 수정 거부 → 할인 0 으로 고치면 풀린다 · 되돌림만(사건 2 → 되돌림 2 · 새 사건 0)
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_create(:'sup'::uuid, '2026-10-10', 1109, :'cad'::uuid, 0, null, 'PODISC4B-P5', null, jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', :'i2', 'amount', 1130, 'discount', null)), true) as r \gset p5_
select pg_temp.err(format('update public.po_invoice set early_discount_pct = 3 where id = %L', :'i2')) as lock1 \gset
select a.id::text as al5 from public.po_payment_alloc a where a.po_payment_id = (:'p5_r'::jsonb->>'payment_id')::uuid \gset
select public.po_payment_alloc_discount_set(:'al5'::uuid, 0, true) as r \gset ds5_
select pg_temp.err(format('update public.po_invoice set early_discount_pct = 3 where id = %L', :'i2')) as lock2 \gset
reset role;
select pg_temp.chk('⬜4 lock: discount 21 taken → terms edit refused · discount_set 0 → reversal only (reversed 1 · new events none · alloc 1109/0 · discount_taken 0) → terms edit allowed · events for the alloc: 1 original + 1 reversal', (:'lock1' like 'P0001 Invoice PODISC4B-I2 — a payment already took its early-payment discount%')::text || '/' || (:'ds5_r'::jsonb->'reversed'->>'reversed') || '/' || (:'ds5_r'::jsonb->'cost_events')::text || '/' || (select trim_scale(amount)::text || '/' || trim_scale(discount_amount)::text from public.po_payment_alloc where id = :'al5'::uuid) || '/' || (select trim_scale(discount_taken)::text from public.po_payment where id = (:'p5_r'::jsonb->>'payment_id')::uuid) || '/' || :'lock2' || '/' || (select count(*) from public.inv_cost_adjust j where j.source_id = :'al5'::uuid or j.reverses_id in (select id from public.inv_cost_adjust where source_id = :'al5'::uuid)), 'true/1/{}/1109/0/0/no-error/2');

-- ═══ E8 — 옛 모양 비용 청구서 할인(p_discount_taken · 대상 하나): 이제 사건 생김 · 경고 없음 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_payment_create(:'sup'::uuid, '2026-10-11', 2.50, :'cad'::uuid, 0.50, null, 'PODISC4B-P6', null, jsonb_build_array(jsonb_build_object('kind', 'charge', 'id', :'c1', 'amount', 3)), true) as r \gset p6_
reset role;
select pg_temp.chk('E8 legacy charge discount 0.50 on CHG-79601 (unpaid 6 after E6): no charge_discount_not_costed_yet warning · legacy_shape · events 2 (−0.30 · −0.20) posted · alloc discount 0.50', (:'p6_r'::jsonb->'warnings' ? 'charge_discount_not_costed_yet:CHG-79601')::text || '/' || (:'p6_r'::jsonb->>'legacy_shape') || '/' || (:'p6_r'::jsonb->'cost_events'->0->>'event_count') || '/' || (select string_agg(trim_scale((x->>'amount_doc')::numeric)::text || ':' || (x->>'status'), ',' order by x->>'target') from jsonb_array_elements(:'p6_r'::jsonb->'cost_events'->0->'events') x) || '/' || (select trim_scale(a.discount_amount)::text from public.po_payment_alloc a where a.po_payment_id = (:'p6_r'::jsonb->>'payment_id')::uuid), 'false/true/2/-0.3:posted,-0.2:posted/0.5');

-- ═══ E10 — 권한: anon 없음 · 열쇠 없는 직원 거부(To pay · 고치기) · 속 함수 authenticated 없음 ═══
set local role anon;
do $$ begin perform count(*) from public.po_pay_candidates(null, null, null); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as an1 \gset
do $$ begin perform public.po_charge_discount_parts(gen_random_uuid(), 1, null); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as an2 \gset
reset role;
set local role authenticated;
select set_config('request.jwt.claims', :'n_claims', true);
do $$ begin perform count(*) from public.po_pay_candidates(null, null, null); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
select current_setting('app.out', true) as nk1 \gset
do $$ begin perform public.po_payment_alloc_discount_set(gen_random_uuid(), 1, false); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
select current_setting('app.out', true) as nk2 \gset
do $$ begin perform public.po_payment_alloc_cost_events(gen_random_uuid(), false, null); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as nk3 \gset
reset role;
select pg_temp.chk('E10 anon candidates · parts → 42501 · no-key staff candidates · discount_set → purchasing sentence · inner cost_events → 42501', :'an1' || ',' || :'an2' || ',' || (:'nk1' = 'P0001 You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was read')::text || ',' || (:'nk2' = 'P0001 You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was saved')::text || ',' || :'nk3', '42501,42501,true,true,42501');

-- ═══ E11 — 실물 무변(CBSA 밖) · 사건 수 = 머리 + 이번 차수(시험 2 · 확인 0) · 재생성 +2.73 · deferred 0 ═══
\if :{?mig}
\set ev_new 2
\else
\set ev_new 0
\endif
select md5(string_agg(p.id::text || '|' || p.paid_on::text || '|' || p.amount::text || '|' || p.discount_taken::text || '|' || coalesce(p.reference, ''), ',' order by p.id)) as real_pay_mid from public.po_payment p where coalesce(p.reference, '') not like 'PODISC4B-%' \gset
select md5(string_agg(a.id::text || '|' || coalesce(a.po_invoice_id::text, '') || '|' || coalesce(a.po_charge_id::text, '') || '|' || a.amount::text || '|' || a.discount_amount::text || '|' || a.discount_tax_part::text, ',' order by a.id)) as real_alloc_mid from public.po_payment_alloc a join public.po_payment p on p.id = a.po_payment_id where coalesce(p.reference, '') not like 'PODISC4B-%' \gset
select md5(string_agg(c.id::text || '|' || c.charge_number || '|' || c.status || '|' || c.total_amount::text || '|' || c.tax_amount::text, ',' order by c.id)) as real_chg_mid from public.po_charge c where c.charge_number not like 'CHG-796%' \gset
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_mid from public.inv_layer l where l.sku not like 'DISC4B-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by a.id)) as real_adds_mid from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC4B-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text, ',' order by k.id)) as real_consume_mid from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC4B-%' \gset
select pg_temp.chk('E11a real rows unchanged inside the test (payments · allocs incl. CBSA · charges · layers · adds · consume) · real events = head + this round', (:'real_pay_mid' = :'real_pay_head')::text || '/' || (:'real_alloc_mid' = :'real_alloc_head')::text || '/' || (:'real_chg_mid' = :'real_chg_head')::text || '/' || (:'real_layers_mid' = :'real_layers_head')::text || '/' || (:'real_adds_mid' = :'real_adds_head')::text || '/' || (:'real_consume_mid' = :'real_consume_head')::text || '/' || (select count(*) from public.inv_cost_adjust j where coalesce(j.po_line_id, j.po_charge_alloc_id) not in (select pl.id from public.po_line pl join public.po x on x.id = pl.po_id where x.po_number like 'PO-796%' union all select a.id from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id where c.charge_number like 'CHG-796%')), 'true/true/true/true/true/true/' || (:real_events_head + :ev_new)::text);
select round(sum(unit_cost * qty), 4) as val_before from public.inv_layer where sku not like 'DISC4B-%' \gset
select set_config('request.jwt.claims', :'g_claims', true);
select clock_timestamp() as ta0 \gset
select public.inv_layer_apply() as r \gset apply_
select clock_timestamp() as ta1 \gset
select 'timing: inv_layer_apply ms=' || round(extract(epoch from (:'ta1'::timestamptz - :'ta0'::timestamptz)) * 1000);
select round(sum(unit_cost * qty), 4) as val_after from public.inv_layer where sku not like 'DISC4B-%' \gset
select 'E11 regen: value before=' || :val_before || ' after=' || :val_after || ' diff=' || (:val_after - :val_before)::text || ' · adjusts: ' || (:'apply_r'::jsonb->'ims'->'adjusts')::text;
select pg_temp.chk('E11b regen total value diff (real · fakes excluded) = +2.73 · adjusts deferred 0 · skipped 0 · pending (CBSA 2 · P&G 13) not replayed · fake posted events replayed (posted = posted count)', round(:val_after - :val_before, 2)::text || '/' || (:'apply_r'::jsonb->'ims'->'adjusts'->>'deferred') || '/' || (:'apply_r'::jsonb->'ims'->'adjusts'->>'skipped') || '/' || ((:'apply_r'::jsonb->'ims'->'adjusts'->>'posted')::int = (select count(*) from public.inv_cost_adjust where status = 'posted'))::text, '2.73/0/0/true');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select md5(string_agg(p.id::text || '|' || p.paid_on::text || '|' || p.amount::text || '|' || p.discount_taken::text || '|' || coalesce(p.reference, ''), ',' order by p.id)) as real_pay_tail, count(*) as real_pay_tail_n from public.po_payment p where coalesce(p.reference, '') not like 'PODISC4B-%' \gset
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_tail, count(*) as real_layers_tail_n from public.inv_layer l where l.sku not like 'DISC4B-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by a.id)) as real_adds_tail, count(*) as real_adds_tail_n from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC4B-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text, ',' order by k.id)) as real_consume_tail, count(*) as real_consume_tail_n from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC4B-%' \gset
select 'REAL_SAME payments ' || (:'real_pay_head' = :'real_pay_tail')::text || ' (' || :real_pay_n || ' → ' || :real_pay_tail_n || ') layers ' || (:'real_layers_head' = :'real_layers_tail')::text || ' (' || :real_layers_n || ' → ' || :real_layers_tail_n || ') adds ' || (:'real_adds_head' = :'real_adds_tail')::text || ' (' || :real_adds_n || ' → ' || :real_adds_tail_n || ') consume ' || (:'real_consume_head' = :'real_consume_tail')::text || ' (' || :real_consume_n || ' → ' || :real_consume_tail_n || ')';
select setval('public.inv_layer_cost_add_id_seq', greatest((select max(id) from public.inv_layer_cost_add), :add_seq_last), true);
select setval('public.inv_layer_consume_id_seq', greatest((select max(id) from public.inv_layer_consume), :con_seq_last), true);
select 'seq tail po ' || last_value || ' ' || is_called from public.po_number_seq;
select 'seq tail rcv ' || last_value || ' ' || is_called from public.po_receipt_number_seq;
select 'seq tail cost_add ' || last_value || ' ' || is_called || ' (head ' || :add_seq_last || ' · reset to greatest(max, head))' from public.inv_layer_cost_add_id_seq;
select 'seq tail consume ' || last_value || ' ' || is_called || ' (head ' || :con_seq_last || ' · reset to greatest(max, head))' from public.inv_layer_consume_id_seq;
