-- po-disc-2-verify.sql — 입고 기준 단가 = 확정 인보이스 실제 단가 · 핀 po_receipt_cost · 식 함수 둘 · po_price_history 재발행 · 입고된 인보이스 취소 막기 (Asung-IMS · 2026-10-08)
--   기대: 시험 갈래 OK 34 · 확인 갈래(G0 셋 없음) OK 31 · MISMATCH 0(시험 적용 4회차 통과 · 2026-10-08) · 실제 입고 레이어 20 md5 전후 같음 · 시퀀스 무변 · 재생성 전체 가치 차이 +2.73
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261008234826_po_disc_2.sql -f supabase/tests/po-disc-2-verify.sql 2>&1 | tee /tmp/po-disc-2.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료는 가짜만(PO-792xx · RCV-792xx · DISC2-* · 가짜 공급처 · 가짜 직원) · 실제 행은 읽기만 · 끝은 rollback
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as po_seq_last, is_called as po_seq_called from public.po_number_seq \gset
select last_value as rcv_seq_last, is_called as rcv_seq_called from public.po_receipt_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
\echo '== seq head po' :po_seq_last :po_seq_called 'rcv' :rcv_seq_last :rcv_seq_called 'so_inv' :inv_seq_last :inv_seq_called
select md5(string_agg(doc_number || '|' || line_ref || '|' || sku || '|' || warehouse || '|' || qty::text || '|' || unit_cost::text, ',' order by doc_number, line_ref, sku, warehouse)) as real_layers_head, count(*) as real_layers_n from public.inv_layer where origin_type = 'purchase' and doc_number like 'RCV-%' \gset
\echo '== real receipt layers head' :real_layers_n :real_layers_head

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

-- ═══ 재료(postgres · 가짜) — 직원 둘 · 공급처 · 제품 · 통화 · 창고 ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc2-recv@test.invalid',  'PODISC2 Receiving', 'manager', '["receiving"]'::jsonb) returning auth_user_id::text as r_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc2-regen@test.invalid', 'PODISC2 Regen',     'manager', '["receiving","purchasing"]'::jsonb) returning auth_user_id::text as g_uid \gset
\set r_claims '{"sub":"' :r_uid '","role":"authenticated"}'
\set g_claims '{"sub":"' :g_uid '","role":"authenticated"}'
select id::text as usd from public.ref_currency where code = 'USD' \gset
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select value as base from public.inv_config where key = 'base_currency' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.name as binname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
insert into public.supplier (name, payment_term_name, account_payable_code) values ('PODISC2 Supplier', 'Net 30', '2000') returning id::text as sup \gset
insert into public.product (sku, name, source) values ('DISC2-P1', 'PODISC2 P1', 'manual') returning id::text as p1 \gset
insert into public.product (sku, name, source) values ('DISC2-P2', 'PODISC2 P2', 'manual') returning id::text as p2 \gset
insert into public.product (sku, name, source) values ('DISC2-P3', 'PODISC2 P3', 'manual') returning id::text as p3 \gset
insert into public.product (sku, name, source) values ('DISC2-P4', 'PODISC2 P4', 'manual') returning id::text as p4 \gset
insert into public.product (sku, name, source) values ('DISC2-P5', 'PODISC2 P5', 'manual') returning id::text as p5 \gset
insert into public.product (sku, name, source) values ('DISC2-P6', 'PODISC2 P6', 'manual') returning id::text as p6 \gset
insert into public.product (sku, name, source) values ('DISC2-P7', 'PODISC2 P7', 'manual') returning id::text as p7 \gset
insert into public.product (sku, name, source) values ('DISC2-P8', 'PODISC2 P8', 'manual') returning id::text as p8 \gset
insert into public.product (sku, name, source) values ('DISC2-P9', 'PODISC2 P9', 'manual') returning id::text as p9 \gset
insert into public.product (sku, name, source) values ('DISC2-P0', 'PODISC2 P0', 'manual') returning id::text as p0 \gset
-- 가짜 PO 여섯(값은 psql 변수 — 기대값은 이 입력으로 계산한다) · 트리거를 피해 replica
\set fx_po1 1.35
\set fx_inv1 1.40
\set fx_po2 1.30
\set fx_po4 1.30
set local session_replication_role = replica;
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79200', 'confirmed', :'sup'::uuid, :'usd'::uuid, 1.25, '2031-01-10', :'wh'::uuid, now()) returning id::text as po0 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79201', 'confirmed', :'sup'::uuid, :'usd'::uuid, :fx_po1, '2031-01-10', :'wh'::uuid, now()) returning id::text as po1 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79202', 'confirmed', :'sup'::uuid, :'usd'::uuid, :fx_po2, '2031-01-10', :'wh'::uuid, now()) returning id::text as po2 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79203', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2031-01-10', :'wh'::uuid, now()) returning id::text as po3 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79204', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2031-01-10', :'wh'::uuid, now()) returning id::text as po4 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79205', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2031-01-10', :'wh'::uuid, now()) returning id::text as po5 \gset
insert into public.po_discount (po_id, seq, name, percent) values (:'po0'::uuid, 1, 'Trade', 10), (:'po1'::uuid, 1, 'Trade', 10);
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po0'::uuid, 1, :'p0'::uuid, 40, 2.00) returning id::text as l0 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po1'::uuid, 1, :'p1'::uuid, 100, 2.00) returning id::text as l1 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po1'::uuid, 2, :'p2'::uuid, 50, 4.00) returning id::text as l2 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po1'::uuid, 3, :'p3'::uuid, 110, 3.50) returning id::text as l3 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po1'::uuid, 4, :'p4'::uuid, 20, 1.00) returning id::text as l4 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po1'::uuid, 5, :'p5'::uuid, 20, 1.00) returning id::text as l5 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po1'::uuid, 6, :'p6'::uuid, 10, 5.00) returning id::text as l6 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po2'::uuid, 1, :'p7'::uuid, 30, 2.00) returning id::text as l7 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po3'::uuid, 1, :'p8'::uuid, 30, 7.00) returning id::text as l8 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po4'::uuid, 1, :'p9'::uuid, 30, 3.00) returning id::text as l9 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po5'::uuid, 1, :'p9'::uuid, 30, 3.00) returning id::text as l10 \gset
-- 확정 인보이스(replica · 확정 창구는 PO 를 가르므로 쓰지 않는다 — 이 시험은 원가 창구와 취소 창구만 본다)
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'PODISC2-I0', '2031-01-12', :'usd'::uuid, 1.20, 0, 'confirmed', 'invoice', now() - interval '3 hour') returning id::text as i0 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'PODISC2-I1', '2031-01-12', :'usd'::uuid, :fx_inv1, 0, 'confirmed', 'invoice', now() - interval '2 hour') returning id::text as i1 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'PODISC2-I2', '2031-01-13', :'usd'::uuid, null, 0, 'confirmed', 'invoice', now() - interval '1 hour') returning id::text as i2 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'PODISC2-I3', '2031-01-12', :'usd'::uuid, null, 0, 'confirmed', 'invoice', now() - interval '2 hour') returning id::text as i3 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'PODISC2-I4', '2031-01-12', :'cad'::uuid, null, 0, 'confirmed', 'invoice', now() - interval '2 hour') returning id::text as i4 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'PODISC2-I5', '2031-01-12', :'usd'::uuid, null, 0, 'confirmed', 'invoice', now() - interval '2 hour') returning id::text as i5 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'PODISC2-I6', '2031-01-12', :'cad'::uuid, null, 0, 'confirmed', 'invoice', now() - interval '2 hour') returning id::text as i6 \gset
insert into public.po_invoice_discount (po_invoice_id, seq, name, percent) values (:'i0'::uuid, 1, 'Trade', 5), (:'i1'::uuid, 1, 'Trade', 17), (:'i1'::uuid, 2, 'Damage', 1), (:'i4'::uuid, 1, 'Trade', 5);
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values
  (:'i0'::uuid, 1, 'goods', :'l0'::uuid, 40, 2.20, true),
  (:'i1'::uuid, 1, 'goods', :'l1'::uuid, 100, 2.10, true),
  (:'i1'::uuid, 2, 'goods', :'l3'::uuid, 100, 3.50, true),
  (:'i1'::uuid, 3, 'goods', :'l3'::uuid, 10, 3.50, false),
  (:'i1'::uuid, 4, 'goods', :'l4'::uuid, 20, 1.00, false),
  (:'i1'::uuid, 5, 'goods', :'l5'::uuid, 20, 0, true),
  (:'i1'::uuid, 6, 'goods', :'l6'::uuid, 10, 5.00, true),
  (:'i2'::uuid, 1, 'goods', :'l6'::uuid, 10, 6.00, true),
  (:'i3'::uuid, 1, 'goods', :'l7'::uuid, 30, 2.50, true),
  (:'i4'::uuid, 1, 'goods', :'l8'::uuid, 30, 7.00, true),
  (:'i5'::uuid, 1, 'goods', :'l9'::uuid, 30, 3.00, true),
  (:'i6'::uuid, 1, 'goods', :'l10'::uuid, 30, 3.00, true);
-- 확정 입고(replica) — RCV-79200 ~ 79204 · 원장 po_in 행(창구가 읽는 모양 · line_ref = po_line_id · doc_number = RCV · source ims)
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at) values ('RCV-79200', :'po0'::uuid, :'wh'::uuid, '2031-01-15', 'confirmed', now()) returning id::text as r0 \gset
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at) values ('RCV-79201', :'po1'::uuid, :'wh'::uuid, '2031-01-15', 'confirmed', now()) returning id::text as r1 \gset
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at) values ('RCV-79202', :'po2'::uuid, :'wh'::uuid, '2031-01-15', 'confirmed', now()) returning id::text as r2 \gset
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at) values ('RCV-79203', :'po3'::uuid, :'wh'::uuid, '2031-01-15', 'confirmed', now()) returning id::text as r3 \gset
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at) values ('RCV-79204', :'po4'::uuid, :'wh'::uuid, '2031-01-15', 'confirmed', now()) returning id::text as r4 \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, source, raw) values
  ('2031-01-15', 1, 'DISC2-P0', :'whname', :'binname', 40,  'po_in', 'purchase', 'RCV-79200', :'r0', :'l0', 'ims', '{"fake":"po-disc-2"}'),
  ('2031-01-15', 1, 'DISC2-P1', :'whname', :'binname', 60,  'po_in', 'purchase', 'RCV-79201', :'r1', :'l1', 'ims', '{"fake":"po-disc-2"}'),
  ('2031-01-15', 1, 'DISC2-P1', :'whname', 'X2',       40,  'po_in', 'purchase', 'RCV-79201', :'r1', :'l1', 'ims', '{"fake":"po-disc-2"}'),
  ('2031-01-15', 1, 'DISC2-P2', :'whname', :'binname', 50,  'po_in', 'purchase', 'RCV-79201', :'r1', :'l2', 'ims', '{"fake":"po-disc-2"}'),
  ('2031-01-15', 1, 'DISC2-P3', :'whname', :'binname', 110, 'po_in', 'purchase', 'RCV-79201', :'r1', :'l3', 'ims', '{"fake":"po-disc-2"}'),
  ('2031-01-15', 1, 'DISC2-P4', :'whname', :'binname', 20,  'po_in', 'purchase', 'RCV-79201', :'r1', :'l4', 'ims', '{"fake":"po-disc-2"}'),
  ('2031-01-15', 1, 'DISC2-P5', :'whname', :'binname', 20,  'po_in', 'purchase', 'RCV-79201', :'r1', :'l5', 'ims', '{"fake":"po-disc-2"}'),
  ('2031-01-15', 1, 'DISC2-P6', :'whname', :'binname', 10,  'po_in', 'purchase', 'RCV-79201', :'r1', :'l6', 'ims', '{"fake":"po-disc-2"}'),
  ('2031-01-15', 1, 'DISC2-P7', :'whname', :'binname', 30,  'po_in', 'purchase', 'RCV-79202', :'r2', :'l7', 'ims', '{"fake":"po-disc-2"}'),
  ('2031-01-15', 1, 'DISC2-P8', :'whname', :'binname', 30,  'po_in', 'purchase', 'RCV-79203', :'r3', :'l8', 'ims', '{"fake":"po-disc-2"}'),
  ('2031-01-15', 1, 'DISC2-P9', :'whname', :'binname', 30,  'po_in', 'purchase', 'RCV-79204', :'r4', :'l9', 'ims', '{"fake":"po-disc-2"}');
set local session_replication_role = origin;
select pg_temp.chk('M fake material: PO 6 · invoices 7 · receipts 5 · ledger rows 11', (select count(*) from public.po where po_number like 'PO-792%')::text || '/' || (select count(*) from public.po_invoice where invoice_number like 'PODISC2-%') || '/' || (select count(*) from public.po_receipt where receipt_number like 'RCV-792%') || '/' || (select count(*) from public.inv_ledger where doc_number like 'RCV-792%'), '6/7/5/11');

-- ═══ D0 · G0 — 적용 전(시험 갈래): 옛 창구는 PO 기준 · 재발행 원본 md5 ═══
\if :{?mig}
select pg_temp.chk('G0a inv_layer_post_receipt last def = 20261008193337 (po-disc-1)', (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'inv_layer_post_receipt'), '54d8ad6d42fa9c4bf490661065b324ef');
select pg_temp.chk('G0b po_doc_cancel last def = 20260918000000', (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'po_doc_cancel'), 'a49d6ec61e47f43deeee6cf39271990e');
select pg_temp.chk('G0c po_price_history viewdef md5 = 20260920163231', (select md5(pg_get_viewdef('public.po_price_history'::regclass))), '0421dad907e5764907851243562d6320');
create temp table t_ph_before as select * from public.po_price_history where invoice_number not like 'PODISC2-%';
select clock_timestamp() as tph0 \gset
select count(*) as ph_n_before, sum(length(net_unit::text)) as ph_len_before from public.po_price_history \gset
select clock_timestamp() as tph1 \gset
select public.inv_layer_post_receipt(:'r0'::uuid) as r \gset d0_
select pg_temp.chk('D0 old window on RCV-79200 = PO basis (2.00 × 0.9 × 1.25) · no pin table yet', (select trim_scale(unit_cost)::text from public.inv_layer where doc_number = 'RCV-79200' and line_ref = :'l0') || '/' || (to_regclass('public.po_receipt_cost') is null)::text, trim_scale((2.00 * 0.9 * 1.25)::numeric)::text || '/true');
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\else
select public.inv_layer_post_receipt(:'r0'::uuid) as r \gset d0_
select pg_temp.chk('D0 (confirm branch) new window on RCV-79200 = invoice basis (2.20 × 0.95 × 1.20) · pinned', (select trim_scale(unit_cost)::text from public.inv_layer where doc_number = 'RCV-79200' and line_ref = :'l0') || '/' || (select source from public.po_receipt_cost where receipt_id = :'r0'::uuid), trim_scale((2.20 * 0.95 * 1.20)::numeric)::text || '/invoice');
\endif

-- ═══ S1 ~ S6 · S8 — RCV-79201 한 번(줄 여섯) · 창구는 직접 실행권이 없다(실제 길 = po_receipt_confirm_by · inv_layer_apply 둘 다 definer) → postgres 로 부른다 ═══
select pg_temp.chk('G1 window privileges: authenticated has no direct execute on inv_layer_post_receipt / inv_post_receipt / inv_layer_apply (real paths: confirm definer · regen from psql with claims)', has_function_privilege('authenticated', 'public.inv_layer_post_receipt(uuid)', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.inv_post_receipt(uuid)', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.inv_layer_apply(date)', 'execute')::text, 'false/false/false');
select clock_timestamp() as tw0 \gset
select public.inv_layer_post_receipt(:'r1'::uuid) as r \gset s1_
select clock_timestamp() as tw1 \gset
select 'timing: inv_layer_post_receipt(RCV-79201 · 6 lines) ms=' || round(extract(epoch from (:'tw1'::timestamptz - :'tw0'::timestamptz)) * 1000);
select x as s1_l1 from jsonb_array_elements(:'s1_r'::jsonb->'lines') x where x->>'po_line_id' = :'l1' \gset
select x as s1_l2 from jsonb_array_elements(:'s1_r'::jsonb->'lines') x where x->>'po_line_id' = :'l2' \gset
select x as s1_l3 from jsonb_array_elements(:'s1_r'::jsonb->'lines') x where x->>'po_line_id' = :'l3' \gset
select x as s1_l4 from jsonb_array_elements(:'s1_r'::jsonb->'lines') x where x->>'po_line_id' = :'l4' \gset
select x as s1_l5 from jsonb_array_elements(:'s1_r'::jsonb->'lines') x where x->>'po_line_id' = :'l5' \gset
select x as s1_l6 from jsonb_array_elements(:'s1_r'::jsonb->'lines') x where x->>'po_line_id' = :'l6' \gset
select pg_temp.chk('S1 L1: unit = 2.10 × 0.8217 × 1.40 (no rounding) · basis invoice · fx source invoice · layer qty 100 (two bins folded)', trim_scale((:'s1_l1'::jsonb->>'unit_cost_cad')::numeric)::text || '/' || (:'s1_l1'::jsonb->>'cost_basis') || '/' || (:'s1_l1'::jsonb->>'exchange_rate_source') || '/' || (:'s1_l1'::jsonb->>'qty'), trim_scale((2.10 * 0.8217 * :fx_inv1)::numeric)::text || '/invoice/invoice/100');
select pg_temp.chk('S1b L1 pin row: source invoice · unit_price_net 2.10×0.8217 · unit_cost_cad = layer · invoice I1 · fx 1.40', (select k.source || '/' || trim_scale(k.unit_price_net)::text || '/' || (k.unit_cost_cad = (select unit_cost from public.inv_layer where doc_number = 'RCV-79201' and line_ref = :'l1'))::text || '/' || (k.invoice_id = :'i1'::uuid)::text || '/' || trim_scale(k.exchange_rate)::text from public.po_receipt_cost k where k.receipt_id = :'r1'::uuid and k.po_line_id = :'l1'::uuid), 'invoice/' || trim_scale((2.10 * 0.8217)::numeric)::text || '/true/true/' || trim_scale((:fx_inv1)::numeric)::text);
select pg_temp.chk('S5 L3: 100 @ 3.50 + 10 free → 350 ÷ 110 × 0.8217 × 1.40 · qty_basis 110 · amount_basis 350×0.8217', trim_scale((:'s1_l3'::jsonb->>'unit_cost_cad')::numeric)::text || '/' || trim_scale((:'s1_l3'::jsonb->>'qty_basis')::numeric)::text || '/' || trim_scale((:'s1_l3'::jsonb->>'amount_basis')::numeric)::text, trim_scale(((350 * 0.8217) / 110 * :fx_inv1)::numeric)::text || '/110/' || trim_scale((350 * 0.8217)::numeric)::text);
select pg_temp.chk('S4a L4 (is_payable false only) → unit 0 · basis invoice', trim_scale((:'s1_l4'::jsonb->>'unit_cost_cad')::numeric)::text || '/' || (:'s1_l4'::jsonb->>'cost_basis'), '0/invoice');
select pg_temp.chk('S4b L5 (unit_price 0 only) → unit 0', trim_scale((:'s1_l5'::jsonb->>'unit_cost_cad')::numeric)::text, '0');
select pg_temp.chk('S4c po_price_history: L4 · L5 lines absent · L3 free line absent · paid L3 line present at 3.50', (select count(*) from public.po_price_history h where h.invoice_line_id in (select id from public.po_invoice_line where po_line_id in (:'l4'::uuid, :'l5'::uuid))) || '/' || (select count(*) || ':' || string_agg(trim_scale(h.gross_unit)::text, ',') from public.po_price_history h where h.po_id = :'po1'::uuid and h.sku = 'DISC2-P3'), '0/1:3.5');
select pg_temp.chk('S6 L2 (no invoice line) → PO basis 4.00 × 0.9 × 1.35 · basis po · warning no_invoice_line', trim_scale((:'s1_l2'::jsonb->>'unit_cost_cad')::numeric)::text || '/' || (:'s1_l2'::jsonb->>'cost_basis') || '/' || (:'s1_r'::jsonb->'warnings' @> to_jsonb(array['no_invoice_line:' || :'l2']))::text, trim_scale((4.00 * 0.9 * :fx_po1)::numeric)::text || '/po/true');
select pg_temp.chk('S8 L6 two confirmed invoices → latest I2 (6.00 · fx null → PO fx 1.35 · source po) + warning multiple_confirmed_invoices', trim_scale((:'s1_l6'::jsonb->>'unit_cost_cad')::numeric)::text || '/' || (:'s1_l6'::jsonb->>'invoice_number') || '/' || (:'s1_l6'::jsonb->>'exchange_rate_source') || '/' || (:'s1_r'::jsonb->'warnings' @> to_jsonb(array['multiple_confirmed_invoices:' || :'l6']))::text, trim_scale((6.00 * 1 * :fx_po1)::numeric)::text || '/PODISC2-I2/po/true');
select pg_temp.chk('S1c header: layers_created 6 · pins 6 · fx_rates lists invoice 1.40 and po 1.35', (:'s1_r'::jsonb->>'layers_created') || '/' || (select count(*) from public.po_receipt_cost where receipt_id = :'r1'::uuid) || '/' || (:'s1_r'::jsonb->'fx_rates' @> '[{"source":"invoice","rate":1.40},{"source":"po","rate":1.35}]'::jsonb)::text, '6/6/true');
select pg_temp.chk('S1d receipt discount_factor pinned 0.9 (po-disc-1 kept) · cost_source po_line · builder @2026-10-08.3', (select trim_scale(discount_factor)::text from public.po_receipt where id = :'r1'::uuid) || '/' || (select string_agg(distinct cost_source, ',') from public.inv_layer where doc_number = 'RCV-79201') || '/' || (:'s1_r'::jsonb->>'builder'), '0.9/po_line/inv_layer_post_receipt@2026-10-08.3');

-- ═══ S2 · S3 · S13 — RCV-79202(인보이스 환율 없음 → PO 환율 · receiving 만 가진 직원이 창구를 부른다 → 핀 써짐) · RCV-79203(기준통화) ═══
select public.inv_layer_post_receipt(:'r2'::uuid) as r \gset s2_
select pg_temp.chk('S2 RCV-79202: invoice fx null · same currency → PO fx 1.30 · source po · unit 2.50 × 1.30', trim_scale((:'s2_r'::jsonb->'lines'->0->>'unit_cost_cad')::numeric)::text || '/' || (:'s2_r'::jsonb->'lines'->0->>'exchange_rate_source'), trim_scale((2.50 * :fx_po2)::numeric)::text || '/po');
select pg_temp.chk('S2b pin written for RCV-79202 (source invoice · fx source po)', (select count(*) || '/' || string_agg(source || ':' || exchange_rate_source, ',') from public.po_receipt_cost where receipt_id = :'r2'::uuid), '1/invoice:po');
select public.inv_layer_post_receipt(:'r3'::uuid) as r \gset s3_
select pg_temp.chk('S3 RCV-79203 base currency: unit = 7.00 × 0.95 · exchange_rate null · source null', trim_scale((:'s3_r'::jsonb->'lines'->0->>'unit_cost_cad')::numeric)::text || '/' || coalesce(:'s3_r'::jsonb->'lines'->0->>'exchange_rate', 'null') || '/' || coalesce(:'s3_r'::jsonb->'lines'->0->>'exchange_rate_source', 'null'), trim_scale((7.00 * 0.95)::numeric)::text || '/null/null');

-- ═══ S9 — 인보이스 통화(USD) ≠ PO 통화(CAD) · 인보이스 환율 없음 → 거부(남의 환율 안 씀) · 아무것도 안 생김 ═══
select pg_temp.err(format('select public.inv_layer_post_receipt(%L::uuid)', :'r4')) as s9_err \gset
select pg_temp.chk('S9 refused with a readable sentence · no layer · no pin', (:'s9_err' like 'P0001 Invoice PODISC2-I5 (PO PO-79204) is in USD but has no CAD per USD exchange rate%')::text || '/' || (select count(*) from public.inv_layer where doc_number = 'RCV-79204') || '/' || (select count(*) from public.po_receipt_cost where receipt_id = :'r4'::uuid), 'true/0/0');
select set_config('app.r4', :'r4', false), set_config('app.l9', :'l9', false);
set local role authenticated;
select set_config('request.jwt.claims', :'r_claims', true);
do $$ begin insert into public.po_receipt_cost (receipt_id, po_line_id, source, unit_price_net, discount_factor, unit_cost_cad, builder) values (current_setting('app.r4', true)::uuid, current_setting('app.l9', true)::uuid, 'po', 1, 1, 1, 'verify'); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as s13a \gset
reset role;
select pg_temp.chk('S13a pin insert policy: receiving-only staff may insert (policy receiving) · row present', :'s13a' || '/' || (select count(*) from public.po_receipt_cost where receipt_id = :'r4'::uuid), 'no-error/1');

-- ═══ S7 — 핀 뒤 재료를 바꾸고(PO 환율 · PO 할인 · 인보이스 단가 · replica) 레이어를 지운 뒤 같은 창구 재호출 = 재생성 모양 → 같은 unit · source pinned ═══
select unit_cost::text as s7_before from public.inv_layer where doc_number = 'RCV-79201' and line_ref = :'l1' \gset
set local session_replication_role = replica;
update public.po set exchange_rate = 9.99 where id = :'po1'::uuid;
update public.po_discount set percent = 50 where po_id = :'po1'::uuid;
update public.po_invoice_line set unit_price = 99 where po_invoice_id = :'i1'::uuid;
update public.po_invoice set exchange_rate = 7.77 where id = :'i1'::uuid;
delete from public.inv_layer where doc_number = 'RCV-79201';
set local session_replication_role = origin;
select public.inv_layer_post_receipt(:'r1'::uuid) as r \gset s7_
select x as s7_l1 from jsonb_array_elements(:'s7_r'::jsonb->'lines') x where x->>'po_line_id' = :'l1' \gset
select pg_temp.chk('S7 regen shape: same unit as before · basis pinned · 6 layers again · pins still 6 (not re-written)', (:'s7_l1'::jsonb->>'unit_cost_cad' = :'s7_before')::text || '/' || (:'s7_l1'::jsonb->>'cost_basis') || '/' || (:'s7_r'::jsonb->>'layers_created') || '/' || (select count(*) from public.po_receipt_cost where receipt_id = :'r1'::uuid), 'true/pinned/6/6');
select pg_temp.chk('S7b idempotent: calling again creates 0 · existing 6', (select (r->>'layers_created') || '/' || (r->>'layers_existing') from public.inv_layer_post_receipt(:'r1'::uuid) r), '0/6');
set local session_replication_role = replica;
update public.po set exchange_rate = :fx_po1 where id = :'po1'::uuid;
update public.po_discount set percent = 10 where po_id = :'po1'::uuid;
update public.po_invoice_line set unit_price = case po_line_id when :'l1'::uuid then 2.10 when :'l3'::uuid then 3.50 when :'l4'::uuid then 1.00 when :'l5'::uuid then 0 else 5.00 end where po_invoice_id = :'i1'::uuid;
update public.po_invoice set exchange_rate = :fx_inv1 where id = :'i1'::uuid;
set local session_replication_role = origin;

-- ═══ S10 — 입고 있는 인보이스 취소 거부 · 입고 없는 인보이스 취소 됨(purchasing 직원) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select pg_temp.err(format('select public.po_doc_cancel(''invoice'', %L::uuid, true)', :'i1')) as s10a \gset
select public.po_doc_cancel('invoice', :'i6'::uuid, true) as r \gset s10b_
reset role;
select pg_temp.chk('S10a invoice with receipts → refused (ruling 396 sentence) · still confirmed', (:'s10a' = 'P0001 The warehouse has received against PO PO-79201 — a received invoice cannot be cancelled; correct it with a credit note — nothing was saved')::text || '/' || (select status from public.po_invoice where id = :'i1'::uuid), 'true/confirmed');
select pg_temp.chk('S10b invoice without receipts → cancelled', (:'s10b_r'::jsonb->>'status'), 'cancelled');

-- ═══ S11 · S12 — po_price_history 전후 · 계수 함수 = po_invoice_money.factor ═══
\if :{?mig}
select pg_temp.chk('S11 po_price_history before/after: except both ways 0 · same row count', (select count(*) from (select * from t_ph_before except select * from public.po_price_history where invoice_number not like 'PODISC2-%') q) || '/' || (select count(*) from (select * from public.po_price_history where invoice_number not like 'PODISC2-%' except select * from t_ph_before) q) || '/' || ((select count(*) from t_ph_before) = (select count(*) from public.po_price_history where invoice_number not like 'PODISC2-%'))::text, '0/0/true');
\else
select pg_temp.chk('S11 (confirm branch) po_price_history reads · real rows have no null factor', (select count(*) filter (where factor is null) from public.po_price_history where invoice_number not like 'PODISC2-%')::text, '0');
\endif
select clock_timestamp() as tph2 \gset
select count(*) as ph_n_after, sum(length(net_unit::text)) as ph_len_after from public.po_price_history \gset
select clock_timestamp() as tph3 \gset
\if :{?mig}
select 'timing: po_price_history full read ms before=' || round(extract(epoch from (:'tph1'::timestamptz - :'tph0'::timestamptz)) * 1000) || ' after=' || round(extract(epoch from (:'tph3'::timestamptz - :'tph2'::timestamptz)) * 1000) || ' rows=' || :ph_n_after;
\else
select 'timing: po_price_history full read ms after=' || round(extract(epoch from (:'tph3'::timestamptz - :'tph2'::timestamptz)) * 1000) || ' rows=' || :ph_n_after;
\endif
select pg_temp.chk('S12 po_invoice_discount_factor = po_invoice_money.factor on every invoice (numeric) · fake I1 = 0.8217', (select count(*) from public.po_invoice_money m where public.po_invoice_discount_factor(m.id) <> m.factor)::text || '/' || trim_scale(public.po_invoice_discount_factor(:'i1'::uuid))::text, '0/' || trim_scale((0.83 * 0.99)::numeric)::text);
select pg_temp.chk('S12b po_invoice_line_cost on I1 line 1: factor · net · fx · cad', (select trim_scale(c.factor)::text || '/' || trim_scale(c.net_unit)::text || '/' || c.exchange_rate_source || '/' || trim_scale(c.net_unit_cad)::text from public.po_invoice_line il, lateral public.po_invoice_line_cost(il.id) c where il.po_invoice_id = :'i1'::uuid and il.line_no = 1), trim_scale((0.83 * 0.99)::numeric)::text || '/' || trim_scale((2.10 * 0.8217)::numeric)::text || '/invoice/' || trim_scale((2.10 * 0.8217 * :fx_inv1)::numeric)::text);

-- ═══ S13b · S14 — 재생성 로그인(receiving + purchasing) · inv_layer_apply 전체 · 실제 레이어 · 전체 가치 ═══
select round(sum(unit_cost * qty), 4) as val_before from public.inv_layer where doc_number not like 'RCV-792%' \gset
select md5(string_agg(doc_number || '|' || line_ref || '|' || sku || '|' || warehouse || '|' || qty::text || '|' || unit_cost::text, ',' order by doc_number, line_ref, sku, warehouse)) as real_layers_mid from public.inv_layer where origin_type = 'purchase' and doc_number like 'RCV-%' and doc_number not like 'RCV-792%' \gset
select pg_temp.chk('S14a real receipt layers untouched by the migration (md5 = head)', :'real_layers_mid', :'real_layers_head');
select set_config('request.jwt.claims', :'g_claims', true);
select clock_timestamp() as ta0 \gset
select public.inv_layer_apply() as r \gset apply_
select clock_timestamp() as ta1 \gset
select set_config('request.jwt.claims', '', true);
select 'timing: inv_layer_apply ms=' || round(extract(epoch from (:'ta1'::timestamptz - :'ta0'::timestamptz)) * 1000);
select round(sum(unit_cost * qty), 4) as val_after from public.inv_layer where doc_number not like 'RCV-792%' \gset
select 'S14 regen: total value before=' || :val_before || ' after=' || :val_after || ' diff=' || (:val_after - :val_before)::text || ' · apply keys: ' || left(:'apply_r', 400);
select pg_temp.chk('S14b regen total value diff (real layers · fakes excluded) = +2.73 CAD (⑭ · po-disc-1 D8b)', round(:val_after - :val_before, 2)::text, '2.73');
select pg_temp.chk('S14c after regen: fake receipts keep their pinned values (RCV-79201 L1 = pinned unit · pins 6 · no new pin)', (select (unit_cost::text = :'s7_before')::text from public.inv_layer where doc_number = 'RCV-79201' and line_ref = :'l1') || '/' || (select count(*) from public.po_receipt_cost where receipt_id = :'r1'::uuid), 'true/6');
select pg_temp.chk('S14d after regen: real receipts got pins (one per real receipt layer) · pins unit = layer unit', (select count(*) from public.po_receipt_cost k join public.po_receipt r on r.id = k.receipt_id where r.receipt_number not like 'RCV-792%')::text || '/' || (select count(*) from public.po_receipt_cost k join public.po_receipt r on r.id = k.receipt_id join public.inv_layer y on y.doc_number = r.receipt_number and y.line_ref = k.po_line_id::text where r.receipt_number not like 'RCV-792%' and y.unit_cost <> k.unit_cost_cad), (select count(*)::text from public.inv_layer where origin_type = 'purchase' and doc_number like 'RCV-%' and doc_number not like 'RCV-792%' and line_ref not like '%:over' and line_ref not like '%:offpo') || '/0');

-- ═══ S13b · S13c — receiving 없는 직원은 핀을 못 넣는다 · anon 없음 · 권한 모양 ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc2-none@test.invalid', 'PODISC2 None', 'manager', '["sales"]'::jsonb) returning auth_user_id::text as n_uid \gset
\set n_claims '{"sub":"' :n_uid '","role":"authenticated"}'
set local role authenticated;
select set_config('request.jwt.claims', :'n_claims', true);
do $$ begin insert into public.po_receipt_cost (receipt_id, po_line_id, source, unit_price_net, discount_factor, unit_cost_cad, builder) values (current_setting('app.r4', true)::uuid, current_setting('app.l9', true)::uuid, 'po', 1, 1, 1, 'verify'); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as s13b \gset
reset role;
select pg_temp.chk('S13b staff without receiving → 42501 on pin insert', :'s13b', '42501');
set local role anon;
do $$ begin perform count(*) from public.po_receipt_cost; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as an1 \gset
do $$ begin perform public.po_invoice_line_cost(gen_random_uuid()); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as an2 \gset
reset role;
set local role authenticated;
select set_config('request.jwt.claims', :'r_claims', true);
do $$ begin update public.po_receipt_cost set unit_cost_cad = 0 where false; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as au1 \gset
do $$ begin delete from public.po_receipt_cost where false; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as au2 \gset
reset role;
select pg_temp.chk('S13c anon select · anon function → 42501 · authenticated update · delete on the pin table → 42501 (append-only)', :'an1' || ',' || :'an2' || ',' || :'au1' || ',' || :'au2', '42501,42501,42501,42501');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select md5(string_agg(doc_number || '|' || line_ref || '|' || sku || '|' || warehouse || '|' || qty::text || '|' || unit_cost::text, ',' order by doc_number, line_ref, sku, warehouse)) as real_layers_tail, count(*) as real_layers_tail_n from public.inv_layer where origin_type = 'purchase' and doc_number like 'RCV-%' \gset
select 'REAL_LAYERS_SAME ' || (:'real_layers_head' = :'real_layers_tail')::text || ' (' || :real_layers_n || ' → ' || :real_layers_tail_n || ')';
select 'seq tail po ' || last_value || ' ' || is_called from public.po_number_seq;
select 'seq tail rcv ' || last_value || ' ' || is_called from public.po_receipt_number_seq;
select 'seq tail so_inv ' || last_value || ' ' || is_called from public.so_invoice_number_seq;
