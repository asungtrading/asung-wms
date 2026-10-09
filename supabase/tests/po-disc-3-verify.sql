-- po-disc-3-verify.sql — 공통 원가 조정 장치: inv_cost_adjust · inv_layer_post_cost_adjust · 어휘 둘 · 입고 확정 ⓖ · 재생성 cogs_adj 갈래 · 되돌림 창구 (Asung-IMS · 2026-10-09)
--   기대: 시험 갈래(-v mig) OK 30 · 확인 갈래 OK 26(= 30 − 시험 전용 4: G0a · G0b · G0c · D0a) · MISMATCH 0 · 실제 레이어 · 얹기 · 소비 md5 전후 같음 · 재생성 전체 가치 차이 +2.73 그대로
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/<ts>_po_disc_3.sql -f supabase/tests/po-disc-3-verify.sql 2>&1 | tee /tmp/po-disc-3.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료는 가짜만(PO-793xx · RCV-793xx · CHG-793xx · DISC3-* · 가짜 공급처 · 가짜 직원) · 실제 행은 읽기만 · 끝은 rollback · 시퀀스는 끝에 greatest(실제 최대, 머리)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as po_seq_last, is_called as po_seq_called from public.po_number_seq \gset
select last_value as rcv_seq_last, is_called as rcv_seq_called from public.po_receipt_number_seq \gset
select last_value as add_seq_last, is_called as add_seq_called from public.inv_layer_cost_add_id_seq \gset
select last_value as con_seq_last, is_called as con_seq_called from public.inv_layer_consume_id_seq \gset
\echo '== seq head po' :po_seq_last :po_seq_called 'rcv' :rcv_seq_last :rcv_seq_called 'cost_add' :add_seq_last :add_seq_called 'consume' :con_seq_last :con_seq_called
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.origin_type || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_head, count(*) as real_layers_n from public.inv_layer l where l.sku not like 'DISC3-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref || '|' || coalesce(a.ref_number, ''), ',' order by a.id)) as real_adds_head, count(*) as real_adds_n from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC3-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text || '|' || k.doc_number || '|' || k.line_ref, ',' order by k.id)) as real_consume_head, count(*) as real_consume_n from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC3-%' \gset
\echo '== real head layers' :real_layers_n :real_layers_head 'adds' :real_adds_n :real_adds_head 'consume' :real_consume_n :real_consume_head

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

-- ═══ 재료(postgres · 가짜) — 직원 셋 · 공급처 · 제품 · 통화 · 창고 · PO 둘 · 입고 둘(확정 · 원장) · 인보이스 · 비용 둘 ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc3-recv@test.invalid',  'PODISC3 Receiving', 'manager', '["receiving"]'::jsonb) returning auth_user_id::text as r_uid, id::text as r_sid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc3-regen@test.invalid', 'PODISC3 Regen',     'manager', '["receiving","purchasing"]'::jsonb) returning auth_user_id::text as g_uid, id::text as g_sid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc3-none@test.invalid',  'PODISC3 NoKeys',    'manager', '[]'::jsonb) returning auth_user_id::text as n_uid \gset
\set r_claims '{"sub":"' :r_uid '","role":"authenticated"}'
\set g_claims '{"sub":"' :g_uid '","role":"authenticated"}'
\set n_claims '{"sub":"' :n_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.id::text as bin, b.name as binname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
insert into public.supplier (name, payment_term_name, account_payable_code) values ('PODISC3 Supplier', 'Net 30', '2000') returning id::text as sup \gset
insert into public.product (sku, name, source) select 'DISC3-P' || i, 'PODISC3 P' || i, 'manual' from generate_series(1, 9) i;
set local session_replication_role = replica;
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79300', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2026-09-20', :'wh'::uuid, now()) returning id::text as po0 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79301', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2026-09-20', :'wh'::uuid, now()) returning id::text as po1 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po0'::uuid, i, p.id, case when i = 7 then 50 else 100 end, 2.00 from generate_series(1, 7) i join public.product p on p.sku = 'DISC3-P' || i;
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po1'::uuid, 1, p.id, 10, 2.00 from public.product p where p.sku = 'DISC3-P9';
select string_agg(pl.id::text, ' ' order by pl.line_no) as lids from public.po_line pl where pl.po_id = :'po0'::uuid \gset
select split_part(:'lids', ' ', 1) as l1, split_part(:'lids', ' ', 2) as l2, split_part(:'lids', ' ', 3) as l3, split_part(:'lids', ' ', 4) as l4, split_part(:'lids', ' ', 5) as l5, split_part(:'lids', ' ', 6) as l6, split_part(:'lids', ' ', 7) as l7 \gset
select pl.id::text as l9 from public.po_line pl where pl.po_id = :'po1'::uuid \gset
-- 입고 둘(확정 · replica) — RCV-79300: L1..L7(L5 는 60) · PO 기준 2.00 · RCV-79301: L5 40 — 확정 인보이스 3.50(판정 392 · 두 입고 다른 단가 = A5)
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at) values ('RCV-79300', :'po0'::uuid, :'wh'::uuid, '2026-10-01', 'confirmed', now()) returning id::text as r0 \gset
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at) values ('RCV-79301', :'po0'::uuid, :'wh'::uuid, '2026-10-01', 'confirmed', now()) returning id::text as r1 \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, source, raw)
select '2026-10-01', 1, 'DISC3-P' || pl.line_no, :'whname', :'binname', case pl.line_no when 5 then 60 when 7 then 50 else 100 end, 'po_in', 'purchase', 'RCV-79300', :'r0', pl.id::text, 'ims', '{"fake":"po-disc-3"}' from public.po_line pl where pl.po_id = :'po0'::uuid;
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, source, raw) values ('2026-10-01', 1, 'DISC3-P5', :'whname', :'binname', 40, 'po_in', 'purchase', 'RCV-79301', :'r1', :'l5', 'ims', '{"fake":"po-disc-3"}');
-- 비용 둘(확정 · CAD) — CHG-79300 26 → PO-79300(A7 · 레이어 있음 · 아래서 얹는다) · CHG-79301 5 → PO-79301(A6 · 레이어 없음 · 입고 확정이 얹는다)
insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, status, confirmed_at) values (:'sup'::uuid, 'CHG-79300', '2026-10-05', 'freight', :'cad'::uuid, 26, 'confirmed', now()) returning id::text as c0 \gset
insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, status, confirmed_at) values (:'sup'::uuid, 'CHG-79301', '2026-10-05', 'freight', :'cad'::uuid, 5, 'confirmed', now()) returning id::text as c1 \gset
insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (:'c0'::uuid, :'po0'::uuid, 26) returning id::text as al0 \gset
insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (:'c1'::uuid, :'po1'::uuid, 5) returning id::text as al1 \gset
-- A6 재료 — PO-79301 의 확정 인보이스(확정 문이 요구한다) · 초안 입고 RCV-79302 + 작업 줄(빈 있음)
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'PODISC3-I1', '2026-09-25', :'cad'::uuid, null, 20, 'confirmed', 'invoice', now() - interval '1 hour') returning id::text as i1 \gset
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (:'i1'::uuid, 1, 'goods', :'l9'::uuid, 10, 2.00, true);
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status) values ('RCV-79302', :'po1'::uuid, :'wh'::uuid, '2026-10-03', 'draft') returning id::text as r2 \gset
insert into public.po_receipt_work (receipt_id, po_line_id, qty_ea, bin_id, putaway_done, count_method, counted_by, counted_at) values (:'r2'::uuid, :'l9'::uuid, 10, :'bin'::uuid, true, 'manual', :'r_sid'::uuid, now());
set local session_replication_role = origin;
-- 레이어 — 창구(po-disc-2 판)로 세운다 · RCV-79300 은 인보이스 없음 → PO 기준 2.00 · 그 뒤 L5 인보이스 3.50 → RCV-79301 은 인보이스 기준
select set_config('request.jwt.claims', :'g_claims', true);
select public.inv_layer_post_receipt(:'r0'::uuid) as r \gset f0_
set local session_replication_role = replica;
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'PODISC3-I0', '2026-09-25', :'cad'::uuid, null, 140, 'confirmed', 'invoice', now() - interval '2 hour') returning id::text as i0 \gset
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (:'i0'::uuid, 1, 'goods', :'l5'::uuid, 40, 3.50, true);
set local session_replication_role = origin;
select public.inv_layer_post_receipt(:'r1'::uuid) as r \gset f1_
select y.id::text as y1 from public.inv_layer y where y.doc_number = 'RCV-79300' and y.line_ref = :'l1' \gset
select y.id::text as y2 from public.inv_layer y where y.doc_number = 'RCV-79300' and y.line_ref = :'l2' \gset
select y.id::text as y3 from public.inv_layer y where y.doc_number = 'RCV-79300' and y.line_ref = :'l3' \gset
select y.id::text as y4 from public.inv_layer y where y.doc_number = 'RCV-79300' and y.line_ref = :'l4' \gset
select y.id::text as y5a from public.inv_layer y where y.doc_number = 'RCV-79300' and y.line_ref = :'l5' \gset
select y.id::text as y5b from public.inv_layer y where y.doc_number = 'RCV-79301' and y.line_ref = :'l5' \gset
select y.id::text as y6 from public.inv_layer y where y.doc_number = 'RCV-79300' and y.line_ref = :'l6' \gset
select y.id::text as y7 from public.inv_layer y where y.doc_number = 'RCV-79300' and y.line_ref = :'l7' \gset
-- 소비 · 자식 — A2 L2 30 판매 · A4 L4 100 판매(다 팔림) · A3 L3 40 트랜스퍼 + 자식 레이어(다른 창고)
insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) values
  (:'y2'::bigint, 'sale', 'SO-79300', 'DISC3-P2:1', 'sale_out', '2026-10-02', 30, 2.00, 60, 'sale'),
  (:'y4'::bigint, 'sale', 'SO-79300', 'DISC3-P4:1', 'sale_out', '2026-10-02', 100, 2.00, 200, 'sale'),
  (:'y3'::bigint, 'transfer', 'TRF-79300', 'DISC3-P3:1', 'transfer_out', '2026-10-02', 40, 2.00, 80, 'transfer');
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source) values ('DISC3-P3', 'DISC3-WH2', 'transfer', 'TRF-79300', 'DISC3-P3:1', :'y3'::bigint, '2026-10-02', true, 40, 2.00, 'parent_layer') returning id::text as y3c \gset
select pg_temp.chk('M fake material: PO 2 · lines 8 · receipts 3 · ledger 8 · layers 9 (8 purchase + 1 child) · charges 2 · L5 units 2.00 / 3.50', (select count(*) from public.po where po_number like 'PO-793%')::text || '/' || (select count(*) from public.po_line where po_id in (:'po0'::uuid, :'po1'::uuid)) || '/' || (select count(*) from public.po_receipt where receipt_number like 'RCV-793%') || '/' || (select count(*) from public.inv_ledger where doc_number like 'RCV-793%') || '/' || (select count(*) from public.inv_layer where sku like 'DISC3-%') || '/' || (select count(*) from public.po_charge where charge_number like 'CHG-793%') || '/' || (select trim_scale(unit_cost)::text from public.inv_layer where id = :'y5a'::bigint) || '/' || (select trim_scale(unit_cost)::text from public.inv_layer where id = :'y5b'::bigint), '2/8/3/8/9/2/2/3.5');

-- ═══ D0 · G0 — 적용 전(시험 갈래): 어휘 없음 재현 · 재발행 원본 md5 · 표 없음 ═══
\if :{?mig}
select pg_temp.chk('G0a inv_layer_apply_flush_adds last def = 20260930161946 (cogs-3)', (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'inv_layer_apply_flush_adds'), '4099ee2400ce3a0beb5f6d1f5d77314c');
select pg_temp.chk('G0b inv_layer_apply last def = 20260930161946 (cogs-3)', (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'inv_layer_apply'), 'd9007dbebb98978d98f570127ef1edd2');
select pg_temp.chk('G0c po_receipt_confirm_by last def = 20260929195458 (inv-basis-2)', (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'po_receipt_confirm_by'), '1f0e0017a038c0351d4a3143dca3f980');
select pg_temp.chk('D0a before: kind settlement_discount refused by CHECK (23514) · no inv_cost_adjust table · no window', left(pg_temp.err(format('insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref) values (%s, ''settlement_discount'', 0, ''2026-10-08'', ''DISC3-D0'', ''d0'')', :'y7')), 5) || '/' || (to_regclass('public.inv_cost_adjust') is null)::text || '/' || (to_regprocedure('public.inv_layer_post_cost_adjust(uuid, date)') is null)::text, '23514/true/true');
\i :mig
\endif
select pg_temp.chk('D0b after: kind settlement_discount accepted (amount 0 row on L7) · table · window · reverse door exist', pg_temp.err(format('insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref) values (%s, ''settlement_discount'', 0, ''2026-10-08'', ''DISC3-D0'', ''d0'')', :'y7')) || '/' || (to_regclass('public.inv_cost_adjust') is not null)::text || '/' || (to_regprocedure('public.inv_layer_post_cost_adjust(uuid, date)') is not null)::text || '/' || (to_regprocedure('public.inv_cost_adjust_reverse(uuid, text)') is not null)::text, 'no-error/true/true/true');
select pg_temp.chk('G1 untouched: settle · post_charge · post_receipt · inv_layer_value · inv_layer_carry · inv_layer_post_adjust(stock) md5 as before', (select string_agg(left(md5(p.prosrc), 8), ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('inv_layer_cost_add_settle', 'inv_layer_post_charge', 'inv_layer_post_receipt', 'inv_layer_value', 'inv_layer_carry', 'inv_layer_post_adjust')), '1ddd5e1e,e8f4217d,51a05522,bf36eb2c,989cf1f9,2d4a569c');
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.origin_type || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_mid from public.inv_layer l where l.sku not like 'DISC3-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref || '|' || coalesce(a.ref_number, ''), ',' order by a.id)) as real_adds_mid from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC3-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text || '|' || k.doc_number || '|' || k.line_ref, ',' order by k.id)) as real_consume_mid from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC3-%' \gset
select pg_temp.chk('A14a real layers · adds · consume untouched by the migration (md5 = head)', (:'real_layers_mid' = :'real_layers_head')::text || '/' || (:'real_adds_mid' = :'real_adds_head')::text || '/' || (:'real_consume_mid' = :'real_consume_head')::text, 'true/true/true');

-- ═══ 사건(postgres · source_type test) — E1..E7 PO-79300 줄 · E9 · E11 PO-79301 줄(pending) · E10 CHG-79301 배분(pending) · E12 CHG-79300 배분(A7 · 뒤에) ═══
insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, source_type, source_number, created_by) values ('settlement_discount', 'po_line', :'l1'::uuid, -20, 'test', 'DISC3-E1', :'g_sid'::uuid) returning id::text as e1 \gset
insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, source_type, source_number, created_by) values ('settlement_discount', 'po_line', :'l2'::uuid, -20, 'test', 'DISC3-E2', :'g_sid'::uuid) returning id::text as e2 \gset
insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, source_type, source_number, created_by) values ('settlement_discount', 'po_line', :'l3'::uuid, -20, 'test', 'DISC3-E3', :'g_sid'::uuid) returning id::text as e3 \gset
insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, source_type, source_number, created_by) values ('settlement_discount', 'po_line', :'l4'::uuid, -20, 'test', 'DISC3-E4', :'g_sid'::uuid) returning id::text as e4 \gset
insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, amount_doc, currency_id, source_type, source_number, created_by) values ('price_adjust', 'po_line', :'l5'::uuid, -20, -20, :'cad'::uuid, 'test', 'DISC3-E5', :'g_sid'::uuid) returning id::text as e5 \gset
insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, source_type, source_number, created_by) values ('settlement_discount', 'po_line', :'l6'::uuid, -20, 'test', 'DISC3-E6', :'g_sid'::uuid) returning id::text as e6 \gset
insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, source_type, source_number, created_by) values ('settlement_discount', 'po_line', :'l7'::uuid, -250, 'test', 'DISC3-E7', :'g_sid'::uuid) returning id::text as e7 \gset
insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, source_type, source_number, created_by) values ('settlement_discount', 'po_line', :'l9'::uuid, -3, 'test', 'DISC3-E9', :'g_sid'::uuid) returning id::text as e9 \gset
insert into public.inv_cost_adjust (kind, target_type, po_charge_alloc_id, amount_cad, source_type, source_number, created_by) values ('settlement_discount', 'charge_alloc', :'al1'::uuid, -1, 'test', 'DISC3-E10', :'g_sid'::uuid) returning id::text as e10 \gset
insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, source_type, source_number, created_by) values ('price_adjust', 'po_line', :'l9'::uuid, -5, 'test', 'DISC3-E11', :'g_sid'::uuid) returning id::text as e11 \gset
select pg_temp.chk('T table shape: pair CHECK (po_line without id) · amount 0 · both targets · bad kind all refused (23514)', left(pg_temp.err(format('insert into public.inv_cost_adjust (kind, target_type, amount_cad, source_type, source_number) values (''price_adjust'', ''po_line'', -1, ''test'', ''x'')')), 5) || '/' || left(pg_temp.err(format('insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, source_type, source_number) values (''price_adjust'', ''po_line'', %L, 0, ''test'', ''x'')', :'l1')), 5) || '/' || left(pg_temp.err(format('insert into public.inv_cost_adjust (kind, target_type, po_line_id, po_charge_alloc_id, amount_cad, source_type, source_number) values (''price_adjust'', ''po_line'', %L, %L, -1, ''test'', ''x'')', :'l1', :'al0')), 5) || '/' || left(pg_temp.err(format('insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, source_type, source_number) values (''rebate'', ''po_line'', %L, -1, ''test'', ''x'')', :'l1')), 5), '23514/23514/23514/23514');

-- ═══ A1 — 레이어 하나 · 안 팔림 · −20 (postgres + 재생성 로그인 claims · 창구 한 번 시간) ═══
select set_config('request.jwt.claims', :'g_claims', true);
select clock_timestamp() as t0 \gset
select public.inv_layer_post_cost_adjust(:'e1'::uuid) as r \gset a1_
select clock_timestamp() as t1 \gset
select 'timing: inv_layer_post_cost_adjust (A1) ms=' || round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000);
select pg_temp.chk('A1 return: posted · layers 1 · posted_cad −20 · posted_on today · builder', (:'a1_r'::jsonb->>'status') || '/' || (:'a1_r'::jsonb->>'layers') || '/' || trim_scale((:'a1_r'::jsonb->>'posted_cad')::numeric)::text || '/' || ((:'a1_r'::jsonb->>'posted_on')::date = public.ims_today())::text || '/' || (:'a1_r'::jsonb->>'builder'), 'posted/1/-20/true/inv_layer_post_cost_adjust@2026-10-09.1');
select pg_temp.chk('A1b cost_add row: kind settlement_discount · −20 · doc DISC3-E1 · line_ref adj:<id> · ref PO-79300 · cost_late 0 · value 180 · full_unit 1.8', (select a.kind || '/' || trim_scale(a.amount)::text || '/' || a.doc_number || '/' || (a.line_ref = 'adj:' || :'e1')::text || '/' || a.ref_number from public.inv_layer_cost_add a where a.layer_id = :'y1'::bigint) || '/' || (select count(*) from public.inv_layer_consume k where k.layer_id = :'y1'::bigint) || '/' || (select trim_scale(v.remaining_value)::text || '/' || trim_scale(v.full_unit)::text from public.inv_layer_value(:'y1'::bigint) v), 'settlement_discount/-20/DISC3-E1/true/PO-79300/0/180/1.8');
select pg_temp.chk('A1c event row: status posted · posted_on today · posted_ledger_id = ledger max id', (select j.status || '/' || (j.posted_on = public.ims_today())::text || '/' || (j.posted_ledger_id = (select max(id) from public.inv_ledger))::text from public.inv_cost_adjust j where j.id = :'e1'::uuid), 'posted/true/true');

-- ═══ A2 — 30 판매 뒤 −20: 남은 몫 −14 · cost_late −6 ═══
select public.inv_layer_post_cost_adjust(:'e2'::uuid) as r \gset a2_
select pg_temp.chk('A2 cost_late −6 (split_basis kind settlement_discount · items SO-79300) · late_sold −6 · remaining value 126 = 70 × 1.8', (select trim_scale(k.amount)::text || '/' || (k.split_basis->>'kind') || '/' || (k.split_basis->'items'->0->>'doc_number') from public.inv_layer_consume k where k.layer_id = :'y2'::bigint and k.reason = 'cost_late') || '/' || trim_scale((:'a2_r'::jsonb->>'late_sold_cad')::numeric)::text || '/' || (select trim_scale(v.remaining_value)::text || '/' || trim_scale(v.unit_cost)::text from public.inv_layer_value(:'y2'::bigint) v), '-6/settlement_discount/SO-79300/-6/126/1.8');

-- ═══ A3 — 40 트랜스퍼(자식) 뒤 −20: 자식 carried −8 · 부모 cost_moved −8 ═══
select public.inv_layer_post_cost_adjust(:'e3'::uuid) as r \gset a3_
select pg_temp.chk('A3 child carried −8 (ref layer:<parent>:settlement_discount · same doc/line_ref) · parent cost_moved −8 · carried_rows 1 · parent remaining 108 · child remaining 72', (select trim_scale(a.amount)::text || '/' || a.kind || '/' || (a.ref_number = 'layer:' || :'y3' || ':settlement_discount')::text || '/' || (a.line_ref = 'adj:' || :'e3')::text from public.inv_layer_cost_add a where a.layer_id = :'y3c'::bigint) || '/' || (select trim_scale(k.amount)::text || '/' || (k.split_basis->>'kind') from public.inv_layer_consume k where k.layer_id = :'y3'::bigint and k.reason = 'cost_moved') || '/' || (:'a3_r'::jsonb->>'carried_rows') || '/' || (select trim_scale(v.remaining_value)::text from public.inv_layer_value(:'y3'::bigint) v) || '/' || (select trim_scale(v.remaining_value)::text from public.inv_layer_value(:'y3c'::bigint) v), '-8/carried/true/true/-8/settlement_discount/1/108/72');

-- ═══ A4 — 다 팔린 레이어 −20: 전부 cost_late(판정 107) · 남은 가치 0 ═══
select public.inv_layer_post_cost_adjust(:'e4'::uuid) as r \gset a4_
select pg_temp.chk('A4 fully sold: cost_late −20 · remaining qty 0 · remaining value 0 · add row still −20 on the layer', (select trim_scale(k.amount)::text from public.inv_layer_consume k where k.layer_id = :'y4'::bigint and k.reason = 'cost_late') || '/' || (select trim_scale(v.remaining_qty)::text || '/' || trim_scale(v.remaining_value)::text || '/' || trim_scale(v.add_amount)::text from public.inv_layer_value(:'y4'::bigint) v), '-20/0/0/-20');

-- ═══ A5 — 같은 PO 줄 · 입고 둘(60 @ 2.00 · 40 @ 3.50): 비율 120:140 · 끝수 마지막 · 합 −20 · kind price_adjust ═══
select public.inv_layer_post_cost_adjust(:'e5'::uuid) as r \gset a5_
select pg_temp.chk('A5 shares: RCV-79300 −9.230769 · RCV-79301 −10.769231 (remainder) · sum −20 · layers 2 · basis 260 · kind price_adjust', (select string_agg(trim_scale(a.amount)::text, ',' order by a.layer_id) || '/' || trim_scale(sum(a.amount))::text || '/' || count(*)::text || '/' || string_agg(distinct a.kind, ',') from public.inv_layer_cost_add a where a.line_ref = 'adj:' || :'e5') || '/' || trim_scale((:'a5_r'::jsonb->>'basis')::numeric)::text, trim_scale(round(-20 * 120 / 260.0, 6))::text || ',' || trim_scale(-20 - round(-20 * 120 / 260.0, 6))::text || '/-20/2/price_adjust/260');

-- ═══ A8 — 멱등: 얹기 → 판매 → 같은 사건 재호출(실시간 · 재생성 모양 둘 다) = 0 줄 ═══
select public.inv_layer_post_cost_adjust(:'e6'::uuid) as r \gset a8_
insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) values (:'y6'::bigint, 'sale', 'SO-79301', 'DISC3-P6:1', 'sale_out', '2026-10-08', 10, 1.80, 18, 'sale');
select public.inv_layer_post_cost_adjust(:'e6'::uuid) as r \gset a8b_
select public.inv_layer_post_cost_adjust(:'e6'::uuid, public.ims_today()) as r \gset a8c_
select pg_temp.chk('A8 first posted · second already_posted 0 layers · regen-shape call already_posted · one add row', (:'a8_r'::jsonb->>'status') || '/' || (:'a8b_r'::jsonb->>'status') || '/' || (:'a8b_r'::jsonb->>'layers') || '/' || (:'a8c_r'::jsonb->>'status') || '/' || (select count(*) from public.inv_layer_cost_add a where a.line_ref = 'adj:' || :'e6'), 'posted/already_posted/0/already_posted/1');

-- ═══ A9 — 되돌림(purchasing 직원 · 창구): posted 사건 → 반대 부호 곧바로 · 두 번째 거부 · 되돌림의 되돌림 거부 · pending 사건 → 둘 다 pending ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.inv_cost_adjust_reverse(:'e6'::uuid, 'test reversal') as r \gset rv_
select pg_temp.err(format('select public.inv_cost_adjust_reverse(%L::uuid, null)', :'e6')) as rv2 \gset
select pg_temp.err(format('select public.inv_cost_adjust_reverse(%L::uuid, null)', :'rv_r'::jsonb->>'reversal_id')) as rv3 \gset
select public.inv_cost_adjust_reverse(:'e11'::uuid, 'reverse while pending') as r \gset rvp_
reset role;
select pg_temp.chk('A9 reversal row: +20 · source reversal · reverses E6 · posted · add +20 with its own line_ref · settle not skipped (cost_late +2 for the 10 sold) · L6 adds sum 0 · remaining 180 (90 × 2.00 — the 10 sold at 1.80 plus +2 late)', (select trim_scale(j.amount_cad)::text || '/' || j.source_type || '/' || (j.reverses_id = :'e6'::uuid)::text || '/' || j.status || '/' || (j.created_by = :'g_sid'::uuid)::text from public.inv_cost_adjust j where j.id = (:'rv_r'::jsonb->>'reversal_id')::uuid) || '/' || (select trim_scale(a.amount)::text || '/' || (a.line_ref = 'adj:' || (:'rv_r'::jsonb->>'reversal_id'))::text from public.inv_layer_cost_add a where a.line_ref = 'adj:' || (:'rv_r'::jsonb->>'reversal_id')) || '/' || (:'rv_r'::jsonb->'posting'->'lines'->0->>'settle_rows') || '/' || (select trim_scale(k.amount)::text from public.inv_layer_consume k where k.layer_id = :'y6'::bigint and k.reason = 'cost_late') || '/' || (select trim_scale(sum(a.amount))::text from public.inv_layer_cost_add a where a.layer_id = :'y6'::bigint) || '/' || (select trim_scale(v.remaining_value)::text from public.inv_layer_value(:'y6'::bigint) v), '20/reversal/true/posted/true/20/true/1/2/0/180');
select pg_temp.chk('A9b second reversal refused · reversing a reversal refused · pending E11 reversed → both pending · no add rows', (:'rv2' like 'P0001 Cost adjustment DISC3-E6 (%) was already reversed — nothing was saved')::text || '/' || (:'rv3' like 'P0001 Cost adjustment DISC3-E6 (%) is itself a reversal%')::text || '/' || (:'rvp_r'::jsonb->>'status') || '/' || (select string_agg(j.status, ',') from public.inv_cost_adjust j where j.id in (:'e11'::uuid, (:'rvp_r'::jsonb->>'reversal_id')::uuid)) || '/' || (select count(*) from public.inv_layer_cost_add a where a.line_ref in ('adj:' || :'e11', 'adj:' || (:'rvp_r'::jsonb->>'reversal_id'))), 'true/true/pending/pending,pending/0');

-- ═══ A10 — 음수 단가가 될 조정(⬜1): L7 50 @ 2.00 = 100 · −250 → 사건 전체 거부 · 아무것도 안 얹힘 · pending 그대로 ═══
select pg_temp.err(format('select public.inv_layer_post_cost_adjust(%L::uuid)', :'e7')) as a10 \gset
select pg_temp.chk('A10 refused with a readable sentence · no add rows · event still pending', (:'a10' like 'P0001 Cost adjustment DISC3-E7 (-250 CAD) is a credit larger than the cost of the goods on layer %')::text || '/' || (select count(*) from public.inv_layer_cost_add a where a.line_ref = 'adj:' || :'e7') || '/' || (select j.status from public.inv_cost_adjust j where j.id = :'e7'::uuid), 'true/0/pending');

-- ═══ A6 — 레이어 없음 → pending(no_layers) → 입고 확정(po_receipt_confirm_by · receiving 직원)이 저절로 얹는다(ⓕ 비용 뒤 ⓖ) · pending 되돌림 짝도 함께 ═══
select public.inv_layer_post_cost_adjust(:'e9'::uuid) as r \gset a6_
select pg_temp.chk('A6a no layers yet: no_layers · still pending · nothing added', (:'a6_r'::jsonb->>'status') || '/' || (select j.status from public.inv_cost_adjust j where j.id = :'e9'::uuid) || '/' || (select count(*) from public.inv_layer_cost_add a where a.line_ref = 'adj:' || :'e9'), 'no_layers/pending/0');
select set_config('request.jwt.claims', :'r_claims', true);
select public.po_receipt_confirm_by(:'r_sid'::uuid, :'r2'::uuid) as r \gset cf_
select set_config('request.jwt.claims', :'g_claims', true);
select y.id::text as y9 from public.inv_layer y where y.doc_number = 'RCV-79302' and y.line_ref = :'l9' \gset
select pg_temp.chk('A6b confirm: receipt confirmed · charge CHG-79301 posted (+5) · adjustments posted 4 (E9 −3 · E10 −1 · E11 −5 · E11 reversal +5 · sorted for the check) · errors 0 · no adjust_errors warning', (:'cf_r'::jsonb->>'status') || '/' || (:'cf_r'::jsonb->'charges'->'posted'->0->>'charge_number') || '/' || jsonb_array_length(:'cf_r'::jsonb->'adjustments'->'posted') || '/' || (select string_agg((x->>'source_number') || ':' || trim_scale((x->>'posted_cad')::numeric)::text, ',' order by x->>'source_number', (x->>'posted_cad')::numeric) from jsonb_array_elements(:'cf_r'::jsonb->'adjustments'->'posted') x) || '/' || jsonb_array_length(:'cf_r'::jsonb->'adjustments'->'errors') || '/' || (:'cf_r'::jsonb->'warnings' ? 'adjust_errors')::text, 'confirmed/CHG-79301/4/DISC3-E10:-1,DISC3-E11:-5,DISC3-E11:5,DISC3-E9:-3/0/false');
select pg_temp.chk('A6c L9 layer 10 @ 2.00 (invoice basis) · adds landed 5 · adjust kinds −4 (−3 −1 −5 +5) · total cost 21 · events posted · posted_on today · charge alloc posted_on today', (select trim_scale(y.qty)::text || '/' || trim_scale(y.unit_cost)::text from public.inv_layer y where y.id = :'y9'::bigint) || '/' || (select trim_scale(sum(a.amount) filter (where a.kind = 'landed'))::text || '/' || trim_scale(sum(a.amount) filter (where a.kind <> 'landed'))::text from public.inv_layer_cost_add a where a.layer_id = :'y9'::bigint) || '/' || (select trim_scale(v.remaining_value)::text from public.inv_layer_value(:'y9'::bigint) v) || '/' || (select string_agg(j.status, ',') || '/' || bool_and(j.posted_on = public.ims_today())::text from public.inv_cost_adjust j where j.id in (:'e9'::uuid, :'e10'::uuid, :'e11'::uuid)) || '/' || (select (a.posted_on = public.ims_today())::text from public.po_charge_alloc a where a.id = :'al1'::uuid), '10/2/5/-4/21/posted,posted,posted/true/true');

-- ═══ A7 — charge_alloc 대상: post_charge 가 CHG-79300 배분에 얹는 레이어 집합 = 조정이 얹는 집합(8 · 자식 트랜스퍼 레이어 제외) ═══
select public.inv_layer_post_charge(:'c0'::uuid) as r \gset a7_
insert into public.inv_cost_adjust (kind, target_type, po_charge_alloc_id, amount_cad, source_type, source_number, created_by) values ('settlement_discount', 'charge_alloc', :'al0'::uuid, -13, 'test', 'DISC3-E12', :'g_sid'::uuid) returning id::text as e12 \gset
select public.inv_layer_post_cost_adjust(:'e12'::uuid) as r \gset a7b_
select pg_temp.chk('A7 layer sets equal (post_charge lines vs adjust add rows · carried excluded) · 8 layers · sum −13 · landed sum on PO-79300 layers 26', ((select string_agg(x->>'layer_id', ',' order by (x->>'layer_id')::bigint) from jsonb_array_elements(:'a7_r'::jsonb->'allocs'->0->'lines') x) = (select string_agg(a.layer_id::text, ',' order by a.layer_id) from public.inv_layer_cost_add a where a.line_ref = 'adj:' || :'e12' and a.kind <> 'carried'))::text || '/' || (select count(*)::text || '/' || trim_scale(sum(a.amount))::text from public.inv_layer_cost_add a where a.line_ref = 'adj:' || :'e12' and a.kind <> 'carried') || '/' || (select trim_scale(sum(a.amount))::text from public.inv_layer_cost_add a join public.inv_layer y on y.id = a.layer_id where a.kind = 'landed' and y.doc_number in ('RCV-79300', 'RCV-79301')), 'true/8/-13/26');
select pg_temp.chk('A7b the transfer child layer holds only carried rows (settle followed A3 · the charge · E12 — original kinds in ref_number) · child share of E12 = −13×200/1360×40/100', (select string_agg(a.kind || ':' || split_part(a.ref_number, ':', 3), ',' order by a.id) || '/' || trim_scale(sum(a.amount) filter (where a.line_ref = 'adj:' || :'e12'))::text from public.inv_layer_cost_add a where a.layer_id = :'y3c'::bigint), 'carried:settlement_discount,carried:landed,carried:settlement_discount/' || trim_scale(round(round(-13 * 200 / 1360.0, 6) * 40 / 100, 6))::text);

-- ═══ A12 — 가치 보고 · 아침 점검 모양: landed 합은 비용만(31) · 새 어휘 합 · carried 는 ref_number 의 원래 kind · inv_layer_open total_cost 에 새 어휘 포함 ═══
select pg_temp.chk('A12 fake layers: landed 31 · settlement_discount −?/price_adjust −20 split · carried 3 (ref kinds) · inv_layer_open L1 total_cost 180 + landed − E12 share', (select trim_scale(sum(a.amount) filter (where a.kind = 'landed'))::text || '/' || trim_scale(sum(a.amount) filter (where a.kind = 'price_adjust'))::text || '/' || trim_scale(sum(a.amount) filter (where a.kind = 'settlement_discount'))::text || '/' || count(*) filter (where a.kind = 'carried')::text || '/' || string_agg(split_part(a.ref_number, ':', 3), ',' order by a.id) filter (where a.kind = 'carried') from public.inv_layer_cost_add a join public.inv_layer y on y.id = a.layer_id where y.sku like 'DISC3-%') || '/' || (select trim_scale(o.total_cost)::text from public.inv_layer_open o where o.id = :'y1'::bigint), '31/-20/-97/3/settlement_discount,landed,settlement_discount/' || trim_scale(180 + round(26 * 200 / 1360.0, 6) + round(-13 * 200 / 1360.0, 6))::text);

-- ═══ A11 · A14 — 재생성(receiving + purchasing claims · postgres) · 같은 자리 · 같은 금액 · deferred 0 · 실제 가치 차이 +2.73 ═══
select md5(string_agg(y.doc_number || '|' || y.line_ref || '|' || y.sku || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by y.doc_number, y.line_ref, a.kind, a.line_ref)) as fake_adds_before, count(*) as fake_adds_before_n from public.inv_layer_cost_add a join public.inv_layer y on y.id = a.layer_id where y.sku like 'DISC3-%' and y.origin_type = 'purchase' and a.line_ref <> 'd0' \gset
select round(sum(unit_cost * qty), 4) as val_before from public.inv_layer where sku not like 'DISC3-%' \gset
select set_config('request.jwt.claims', :'g_claims', true);                                   -- postgres + 재생성 로그인 claims(inv_layer_apply 는 authenticated 실행권 없음 · po-disc-2 S14 와 같다)
select clock_timestamp() as ta0 \gset
select public.inv_layer_apply() as r \gset apply_
select clock_timestamp() as ta1 \gset
select 'timing: inv_layer_apply ms=' || round(extract(epoch from (:'ta1'::timestamptz - :'ta0'::timestamptz)) * 1000);
select round(sum(unit_cost * qty), 4) as val_after from public.inv_layer where sku not like 'DISC3-%' \gset
select md5(string_agg(y.doc_number || '|' || y.line_ref || '|' || y.sku || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by y.doc_number, y.line_ref, a.kind, a.line_ref)) as fake_adds_after, count(*) as fake_adds_after_n from public.inv_layer_cost_add a join public.inv_layer y on y.id = a.layer_id where y.sku like 'DISC3-%' and y.origin_type = 'purchase' and a.line_ref <> 'd0' \gset
select 'A11 regen: value before=' || :val_before || ' after=' || :val_after || ' diff=' || (:val_after - :val_before)::text || ' · adjusts: ' || (:'apply_r'::jsonb->'ims'->'adjusts')::text || ' · charge_allocs_deferred ' || (:'apply_r'::jsonb->'ims'->>'charge_allocs_deferred');
select pg_temp.chk('A11 regen: fake add rows identical (same layer · kind · amount · occurred_on = posted_on · doc · line_ref) · 29 rows · adjusts posted 12 · amount −117 · deferred 0 · skipped 0 · no_layers 0 · charge allocs deferred 0', (:'fake_adds_after' = :'fake_adds_before')::text || '/' || :fake_adds_after_n || '/' || (:'apply_r'::jsonb->'ims'->'adjusts'->>'posted') || '/' || trim_scale((:'apply_r'::jsonb->'ims'->'adjusts'->>'amount_cad')::numeric)::text || '/' || (:'apply_r'::jsonb->'ims'->'adjusts'->>'deferred') || '/' || (:'apply_r'::jsonb->'ims'->'adjusts'->>'skipped') || '/' || (:'apply_r'::jsonb->'ims'->'adjusts'->>'no_layers') || '/' || (:'apply_r'::jsonb->'ims'->>'charge_allocs_deferred'), 'true/29/12/-117/0/0/0/0');
select pg_temp.chk('A11b after regen: events untouched (posted_on · posted_ledger_id same) · E7 still pending · L1 value 180 + 26×200/1360 landed − 13×200/1360 E12 share', (select count(*) from public.inv_cost_adjust j where j.status = 'posted' and j.posted_on = public.ims_today() and j.posted_ledger_id is not null)::text || '/' || (select j.status from public.inv_cost_adjust j where j.id = :'e7'::uuid) || '/' || (select trim_scale(o.total_cost)::text from public.inv_layer_open o where o.doc_number = 'RCV-79300' and o.line_ref = :'l1'), '12/pending/' || trim_scale(180 + round(26 * 200 / 1360.0, 6) + round(-13 * 200 / 1360.0, 6))::text);
select pg_temp.chk('A14b regen total value diff (real layers · fakes excluded) = +2.73 CAD (⑭ · po-disc-2 S14b)', round(:val_after - :val_before, 2)::text, '2.73');

-- ═══ A13 — 권한: anon 없음 · 열쇠 없는 직원 거부 · authenticated 는 표 직접 쓰기 · 속 창구 실행 막힘 ═══
set local role anon;
do $$ begin perform count(*) from public.inv_cost_adjust; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as an1 \gset
do $$ begin perform public.inv_cost_adjust_reverse(gen_random_uuid(), null); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as an2 \gset
reset role;
set local role authenticated;
select set_config('request.jwt.claims', :'n_claims', true);
do $$ begin perform public.inv_cost_adjust_reverse((select id from public.inv_cost_adjust where source_number = 'DISC3-E1'), null); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
select current_setting('app.out', true) as au1 \gset
do $$ begin insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, source_type, source_number) select 'price_adjust', 'po_line', po_line_id, -1, 'test', 'x' from public.inv_cost_adjust where source_number = 'DISC3-E1'; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as au2 \gset
do $$ begin update public.inv_cost_adjust set note = 'x' where false; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as au3 \gset
do $$ begin delete from public.inv_cost_adjust where false; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as au4 \gset
do $$ begin perform public.inv_layer_post_cost_adjust(gen_random_uuid()); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as au5 \gset
select count(*)::text as au6 from public.inv_cost_adjust where source_number like 'DISC3-%' \gset
reset role;
select pg_temp.chk('A13 anon select · anon door → 42501 · no-key staff door → readable refusal · authenticated insert · update · delete → 42501 · inner window → 42501 · authenticated reads events (13)', :'an1' || ',' || :'an2' || ',' || (:'au1' = 'P0001 You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was saved')::text || ',' || :'au2' || ',' || :'au3' || ',' || :'au4' || ',' || :'au5' || ',' || :'au6', '42501,42501,true,42501,42501,42501,42501,13');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.origin_type || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_tail, count(*) as real_layers_tail_n from public.inv_layer l where l.sku not like 'DISC3-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref || '|' || coalesce(a.ref_number, ''), ',' order by a.id)) as real_adds_tail, count(*) as real_adds_tail_n from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC3-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text || '|' || k.doc_number || '|' || k.line_ref, ',' order by k.id)) as real_consume_tail, count(*) as real_consume_tail_n from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC3-%' \gset
select 'REAL_SAME layers ' || (:'real_layers_head' = :'real_layers_tail')::text || ' (' || :real_layers_n || ' → ' || :real_layers_tail_n || ') adds ' || (:'real_adds_head' = :'real_adds_tail')::text || ' (' || :real_adds_n || ' → ' || :real_adds_tail_n || ') consume ' || (:'real_consume_head' = :'real_consume_tail')::text || ' (' || :real_consume_n || ' → ' || :real_consume_tail_n || ')';
select setval('public.inv_layer_cost_add_id_seq', greatest((select max(id) from public.inv_layer_cost_add), :add_seq_last), true);
select setval('public.inv_layer_consume_id_seq', greatest((select max(id) from public.inv_layer_consume), :con_seq_last), true);
select 'seq tail po ' || last_value || ' ' || is_called from public.po_number_seq;
select 'seq tail rcv ' || last_value || ' ' || is_called from public.po_receipt_number_seq;
select 'seq tail cost_add ' || last_value || ' ' || is_called || ' (head ' || :add_seq_last || ' · reset to greatest(max, head))' from public.inv_layer_cost_add_id_seq;
select 'seq tail consume ' || last_value || ' ' || is_called || ' (head ' || :con_seq_last || ' · reset to greatest(max, head))' from public.inv_layer_consume_id_seq;
