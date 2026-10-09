-- po-disc-5a-verify.sql — 크레딧 goods 줄 credit_reason(제안 · 고치기 · 확정 거부) · 가격 크레딧 → 원가 사건(핀 환율 · 399 · 입고 전 pending) · 다시 열기 · 취소 · 복구 되돌림 · 권한 · 실물 무변 (Asung-IMS · 2026-10-09)
--   기대: 시험 갈래(-v mig) OK 16 · 확인 갈래 OK 14(= 16 − 시험 전용 2: G0 · D0a) · MISMATCH 0 · 증감 기대는 두 갈래(\if :{?mig})
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/<ts>_po_disc_5a.sql -f supabase/tests/po-disc-5a-verify.sql > /tmp/po-disc-5a.out 2>&1; echo "rc=$?"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료는 가짜만(PO-797xx · PODISC5A-* · 크레딧은 자동 번호 CN-PO-797xx-n · RCV-797xx · 가짜 공급처 · 직원) · 실제 행 무변 · 끝은 rollback · identity 시퀀스는 greatest(실제 최대, 머리)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as po_seq_last, is_called as po_seq_called from public.po_number_seq \gset
select last_value as rcv_seq_last, is_called as rcv_seq_called from public.po_receipt_number_seq \gset
select last_value as add_seq_last, is_called as add_seq_called from public.inv_layer_cost_add_id_seq \gset
select last_value as con_seq_last, is_called as con_seq_called from public.inv_layer_consume_id_seq \gset
\echo '== seq head po' :po_seq_last :po_seq_called 'rcv' :rcv_seq_last :rcv_seq_called 'cost_add' :add_seq_last :add_seq_called 'consume' :con_seq_last :con_seq_called
select md5(string_agg(i.id::text || '|' || i.doc_kind || '|' || i.invoice_number || '|' || i.status || '|' || i.total_amount::text || '|' || coalesce(i.confirmed_at::text, ''), ',' order by i.id)) as real_inv_head, count(*) as real_inv_n from public.po_invoice i where i.invoice_number not like 'PODISC5A-%' and i.invoice_number not like 'CN-PO-797%' \gset
select md5(string_agg(il.id::text || '|' || il.line_kind || '|' || il.qty_ea::text || '|' || il.unit_price::text, ',' order by il.id)) as real_line_head, count(*) as real_line_n from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id where i.invoice_number not like 'PODISC5A-%' and i.invoice_number not like 'CN-PO-797%' \gset
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_head, count(*) as real_layers_n from public.inv_layer l where l.sku not like 'DISC5A-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by a.id)) as real_adds_head, count(*) as real_adds_n from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC5A-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text, ',' order by k.id)) as real_consume_head, count(*) as real_consume_n from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC5A-%' \gset
select count(*) as real_events_head from public.inv_cost_adjust \gset
\echo '== real head invoices' :real_inv_n :real_inv_head 'lines' :real_line_n 'layers' :real_layers_n :real_layers_head 'adds' :real_adds_n 'consume' :real_consume_n 'events' :real_events_head

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

-- ═══ 재료(postgres · 가짜) — 직원 둘 · 공급처 · 제품 6 · PO 5 · 인보이스 5(확정) · 입고 4(확정 · 원장 · 창구) · 초안 입고 1(F8) ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc5a-g@test.invalid', 'PODISC5A Purchasing+Receiving', 'manager', '["purchasing","receiving"]'::jsonb) returning auth_user_id::text as g_uid, id::text as g_sid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc5a-n@test.invalid', 'PODISC5A NoKeys', 'manager', '[]'::jsonb) returning auth_user_id::text as n_uid \gset
\set g_claims '{"sub":"' :g_uid '","role":"authenticated"}'
\set n_claims '{"sub":"' :n_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as usd from public.ref_currency where code = 'USD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.id::text as bin, b.name as binname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select id::text as hst, name as hstname from public.ref_tax_rule where direction = 'purchase' and is_active and name = 'HST ON (Purchase)' limit 1 \gset
insert into public.supplier (name, payment_term_name, account_payable_code, currency_id) values ('PODISC5A Supplier', 'Net 30', '2000', :'cad'::uuid) returning id::text as sup \gset
insert into public.product (sku, name, source) select 'DISC5A-P' || i, 'PODISC5A P' || i, 'manual' from generate_series(1, 6) i;
set local session_replication_role = replica;
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at, tax_rule_id, tax_rule) values
  ('PO-79700', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2026-10-01', :'wh'::uuid, now(), :'hst'::uuid, :'hstname'),
  ('PO-79701', 'confirmed', :'sup'::uuid, :'usd'::uuid, 1.35, '2026-10-01', :'wh'::uuid, now(), :'hst'::uuid, :'hstname'),
  ('PO-79702', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2026-10-01', :'wh'::uuid, now(), :'hst'::uuid, :'hstname'),
  ('PO-79703', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2026-10-01', :'wh'::uuid, now(), :'hst'::uuid, :'hstname'),
  ('PO-79704', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2026-10-01', :'wh'::uuid, now(), :'hst'::uuid, :'hstname');
select string_agg(id::text, ' ' order by po_number) as pos from public.po where po_number like 'PO-797%' \gset
select split_part(:'pos', ' ', 1) as po0, split_part(:'pos', ' ', 2) as po1, split_part(:'pos', ' ', 3) as po2, split_part(:'pos', ' ', 4) as po3, split_part(:'pos', ' ', 5) as po4 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po0'::uuid, 1, id, 100, 3.50 from public.product where sku = 'DISC5A-P1';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po0'::uuid, 2, id, 50, 2.00 from public.product where sku = 'DISC5A-P2';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po1'::uuid, 1, id, 100, 5.00 from public.product where sku = 'DISC5A-P3';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po2'::uuid, 1, id, 100, 4.00 from public.product where sku = 'DISC5A-P4';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po3'::uuid, 1, id, 10, 1.00 from public.product where sku = 'DISC5A-P5';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po4'::uuid, 1, id, 100, 3.50 from public.product where sku = 'DISC5A-P6';
select pl.id::text as l1 from public.po_line pl where pl.po_id = :'po0'::uuid and pl.line_no = 1 \gset
select pl.id::text as l2 from public.po_line pl where pl.po_id = :'po0'::uuid and pl.line_no = 2 \gset
select pl.id::text as l3 from public.po_line pl where pl.po_id = :'po1'::uuid \gset
select pl.id::text as l4 from public.po_line pl where pl.po_id = :'po2'::uuid \gset
select pl.id::text as l5 from public.po_line pl where pl.po_id = :'po3'::uuid \gset
select pl.id::text as l6 from public.po_line pl where pl.po_id = :'po4'::uuid \gset
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select (public.po_invoice_create('invoice', 'PODISC5A-I1', :'po0'::uuid, null, null, '2026-10-02', null, 508.50, true, true, null))->>'id' as i1 \gset
select (public.po_invoice_create('invoice', 'PODISC5A-I2', :'po1'::uuid, null, null, '2026-10-02', null, 565.00, true, true, null))->>'id' as i2 \gset
select (public.po_invoice_create('invoice', 'PODISC5A-I3', :'po2'::uuid, null, null, '2026-10-02', null, 452.00, true, true, null))->>'id' as i3 \gset
select (public.po_invoice_create('invoice', 'PODISC5A-I4', :'po3'::uuid, null, null, '2026-10-02', null, 11.30, true, true, null))->>'id' as i4 \gset
select (public.po_invoice_create('invoice', 'PODISC5A-I5', :'po4'::uuid, null, null, '2026-10-02', null, 395.50, true, true, null))->>'id' as i5 \gset
reset role;
set local session_replication_role = replica;
update public.po_invoice set status = 'confirmed', confirmed_at = now() where invoice_number like 'PODISC5A-I%';
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at) values
  ('RCV-79700', :'po0'::uuid, :'wh'::uuid, '2026-10-03', 'confirmed', now()), ('RCV-79701', :'po1'::uuid, :'wh'::uuid, '2026-10-03', 'confirmed', now()),
  ('RCV-79703', :'po3'::uuid, :'wh'::uuid, '2026-10-03', 'confirmed', now()), ('RCV-79704', :'po4'::uuid, :'wh'::uuid, '2026-10-03', 'confirmed', now());
select id::text as r0 from public.po_receipt where receipt_number = 'RCV-79700' \gset
select id::text as r1 from public.po_receipt where receipt_number = 'RCV-79701' \gset
select id::text as r3 from public.po_receipt where receipt_number = 'RCV-79703' \gset
select id::text as r4 from public.po_receipt where receipt_number = 'RCV-79704' \gset
insert into public.po_receipt_line (po_line_id, received_on, bin_id, qty_ea, receipt_id) values (:'l1'::uuid, '2026-10-03', :'bin'::uuid, 90, :'r0'::uuid), (:'l2'::uuid, '2026-10-03', :'bin'::uuid, 50, :'r0'::uuid), (:'l3'::uuid, '2026-10-03', :'bin'::uuid, 100, :'r1'::uuid), (:'l5'::uuid, '2026-10-03', :'bin'::uuid, 10, :'r3'::uuid), (:'l6'::uuid, '2026-10-03', :'bin'::uuid, 100, :'r4'::uuid);
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, source, raw) values
  ('2026-10-03', 1, 'DISC5A-P1', :'whname', :'binname', 90,  'po_in', 'purchase', 'RCV-79700', :'r0', :'l1', 'ims', '{"fake":"po-disc-5a"}'),
  ('2026-10-03', 1, 'DISC5A-P2', :'whname', :'binname', 50,  'po_in', 'purchase', 'RCV-79700', :'r0', :'l2', 'ims', '{"fake":"po-disc-5a"}'),
  ('2026-10-03', 1, 'DISC5A-P3', :'whname', :'binname', 100, 'po_in', 'purchase', 'RCV-79701', :'r1', :'l3', 'ims', '{"fake":"po-disc-5a"}'),
  ('2026-10-03', 1, 'DISC5A-P5', :'whname', :'binname', 10,  'po_in', 'purchase', 'RCV-79703', :'r3', :'l5', 'ims', '{"fake":"po-disc-5a"}'),
  ('2026-10-03', 1, 'DISC5A-P6', :'whname', :'binname', 100, 'po_in', 'purchase', 'RCV-79704', :'r4', :'l6', 'ims', '{"fake":"po-disc-5a"}');
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status) values ('RCV-79702', :'po2'::uuid, :'wh'::uuid, '2026-10-06', 'draft') returning id::text as r2 \gset
insert into public.po_receipt_work (receipt_id, po_line_id, qty_ea, bin_id, putaway_done, count_method, counted_by, counted_at) values (:'r2'::uuid, :'l4'::uuid, 100, :'bin'::uuid, true, 'manual', :'g_sid'::uuid, now());
set local session_replication_role = origin;
select set_config('request.jwt.claims', :'g_claims', true);
select public.inv_layer_post_receipt(:'r0'::uuid) as r \gset f0_
select public.inv_layer_post_receipt(:'r1'::uuid) as r \gset f1_
select public.inv_layer_post_receipt(:'r3'::uuid) as r \gset f3_
select public.inv_layer_post_receipt(:'r4'::uuid) as r \gset f4_
select y.id::text as y1 from public.inv_layer y where y.doc_number = 'RCV-79700' and y.line_ref = :'l1' \gset
select y.id::text as y2 from public.inv_layer y where y.doc_number = 'RCV-79700' and y.line_ref = :'l2' \gset
select y.id::text as y3 from public.inv_layer y where y.doc_number = 'RCV-79701' \gset
select y.id::text as y5 from public.inv_layer y where y.doc_number = 'RCV-79703' \gset
select y.id::text as y6 from public.inv_layer y where y.doc_number = 'RCV-79704' \gset
select pg_temp.chk('M fake material: invoices 5 confirmed · layers 5 (P1 90@3.5 · P2 50@2 · P3 100@6.75 · P5 10@1 · P6 100@3.5) · pins fx: P3 1.35 invoice · P1 null · receipt lines 5', (select count(*) from public.po_invoice where invoice_number like 'PODISC5A-I%' and status = 'confirmed')::text || '/' || (select string_agg(trim_scale(y.qty)::text || '@' || trim_scale(y.unit_cost)::text, ',' order by y.sku) from public.inv_layer y where y.sku like 'DISC5A-%') || '/' || (select trim_scale(k.exchange_rate)::text || ':' || k.exchange_rate_source from public.po_receipt_cost k where k.po_line_id = :'l3'::uuid) || '/' || (select coalesce(k.exchange_rate::text, 'null') from public.po_receipt_cost k where k.po_line_id = :'l1'::uuid) || '/' || (select count(*) from public.po_receipt_line rl join public.po_line pl on pl.id = rl.po_line_id join public.po x on x.id = pl.po_id where x.po_number like 'PO-797%'), '5/90@3.5,50@2,100@6.75,10@1,100@3.5/1.35:invoice/null/5');

-- ═══ D0 · G0 — 적용 전(시험 갈래): 칸 없음 · 재발행 원본 md5 ═══
\if :{?mig}
select pg_temp.chk('G0 last defs: po_invoice_create eced8864 · line_add 2b0eed6c · line_update 07409ac9 · detail 7d3e9d86 · confirm f69b1962 · cancel 118d64ac · invoker(confirm · cancel)', (select string_agg(left(md5(p.prosrc), 8) || ':' || p.prosecdef::text, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_invoice_create', 'po_invoice_line_add', 'po_invoice_line_update', 'po_invoice_detail', 'po_invoice_confirm', 'po_doc_cancel')), '118d64ac:false,f69b1962:false,eced8864:false,7d3e9d86:false,2b0eed6c:false,07409ac9:false');
select pg_temp.chk('D0a before: no credit_reason column · no suggest function · no po_credit events', (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_invoice_line' and column_name = 'credit_reason')::text || '/' || (to_regprocedure('public.po_credit_reason_suggest(uuid, uuid, numeric, uuid)') is null)::text || '/' || (select count(*) from public.inv_cost_adjust where source_type = 'po_credit'), '0/true/0');
\i :mig
\endif
select pg_temp.chk('D0b after: column · CHECK · guard trigger · suggest · helpers · confirm · cancel definer · real lines reason all null · po_credit events 0', (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_invoice_line' and column_name = 'credit_reason')::text || '/' || (select count(*) from pg_constraint where conname = 'po_invoice_line_credit_reason_ck') || '/' || (select count(*) from pg_trigger where not tgisinternal and tgname = 'po_invoice_line_credit_reason_guard') || '/' || (to_regprocedure('public.po_credit_reason_suggest(uuid, uuid, numeric, uuid)') is not null and to_regprocedure('public.po_credit_cost_events(uuid, boolean)') is not null and to_regprocedure('public.po_credit_cost_reverse(uuid, text)') is not null)::text || '/' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_invoice_confirm', 'po_doc_cancel') and p.prosecdef) || '/' || (select count(*) from public.po_invoice_line where credit_reason is not null) || '/' || (select count(*) from public.inv_cost_adjust where source_type = 'po_credit'), '1/1/1/true/2/0/0');
select pg_temp.chk('G1 untouched: line_delete ad303475 · add_po_lines · post_cost_adjust 1f95d60c · reverse 02d8d9b9 · post_receipt 989cf1f9 · confirm_by 857021b6 · line_cost 46533c68 · discount_factor 67f714a5 · money view 08f428cb', (select string_agg(left(md5(p.prosrc), 8), ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_invoice_line_delete', 'inv_layer_post_cost_adjust', 'inv_cost_adjust_reverse', 'inv_layer_post_receipt', 'po_receipt_confirm_by', 'po_invoice_line_cost', 'po_invoice_discount_factor')) || '/' || left(md5(pg_get_viewdef('public.po_invoice_money'::regclass)), 8), '02d8d9b9,1f95d60c,989cf1f9,67f714a5,46533c68,ad303475,857021b6/08f428cb');

-- ═══ F1 — 100 청구 · 90 입고 → 크레딧 자동 채움: 줄 not_received(제안 · 상세) · 확정 · 사건 0 · 레이어 무변 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_invoice_create('credit', null, null, :'i1'::uuid, null, '2026-10-05', null, 35.00, true, true, null) as r \gset c1_
select (:'c1_r'::jsonb->>'id') as c1 \gset
select public.po_invoice_detail(:'c1'::uuid) as r \gset d1_
select public.po_invoice_confirm(:'c1'::uuid, true) as r \gset cf1_
reset role;
select pg_temp.chk('F1 auto credit: lines[0] L1 ok diff 10 credit_reason not_received · L2 no_difference · DB reason not_received · detail suggested not_received · left 10 · spans false · no credit_reason_missing · confirm: event_count 0 · y1 adds 0 · 315 remaining', (select x->>'verdict' || '/' || (x->>'diff_qty') || '/' || (x->>'credit_reason') from jsonb_array_elements(:'c1_r'::jsonb->'lines') x where x->>'po_line_id' = :'l1') || '/' || (select x->>'verdict' from jsonb_array_elements(:'c1_r'::jsonb->'lines') x where x->>'po_line_id' = :'l2') || '/' || (select string_agg(credit_reason, ',') from public.po_invoice_line where po_invoice_id = :'c1'::uuid) || '/' || (:'d1_r'::jsonb->'lines'->0->>'credit_reason_suggested') || '/' || trim_scale((:'d1_r'::jsonb->'lines'->0->>'credit_not_received_left')::numeric)::text || '/' || (:'d1_r'::jsonb->'lines'->0->>'credit_spans_both') || '/' || (:'d1_r'::jsonb->'warnings' ? 'credit_reason_missing')::text || '/' || (:'cf1_r'::jsonb->'cost_events'->>'event_count') || '/' || (select count(*) from public.inv_layer_cost_add where layer_id = :'y1'::bigint) || '/' || (select trim_scale(v.remaining_value)::text from public.inv_layer_value(:'y1'::bigint) v), 'ok/10/not_received/no_difference/not_received/not_received/10/false/false/0/0/315');

-- ═══ F4 — 직원이 제안을 바꿈: 다시 열기(되돌림 0) → not_received → price_difference(경고 differs) → 확정 → 사건 −35(10 × 3.50) posted · y1 315 → 280 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_invoice_confirm(:'c1'::uuid, false) as r \gset ro1_
select cl.id::text as c1l1 from public.po_invoice_line cl where cl.po_invoice_id = :'c1'::uuid \gset
select public.po_invoice_line_update(:'c1l1'::uuid, '{"credit_reason":"price_difference"}'::jsonb) as r \gset lu1_
select public.po_invoice_confirm(:'c1'::uuid, true) as r \gset cf1b_
reset role;
select pg_temp.chk('F4 reopen: reversed 0 · update reason → warning credit_reason_differs_from_suggestion:not_received · confirm: 1 event −35 CAD (fx null · pinned source null) posted · y1 adds −35 · remaining 280 · source po_credit · source_id = line', (:'ro1_r'::jsonb->'cost_reversed'->>'reversed') || '/' || (:'lu1_r'::jsonb->'warnings' ? 'credit_reason_differs_from_suggestion:not_received')::text || '/' || (:'cf1b_r'::jsonb->'cost_events'->>'event_count') || '/' || (select trim_scale(j.amount_cad)::text || '/' || coalesce(j.exchange_rate::text, 'null') || '/' || j.status || '/' || j.source_type || '/' || (j.source_id = :'c1l1'::uuid)::text from public.inv_cost_adjust j where j.source_id = :'c1l1'::uuid) || '/' || (select trim_scale(sum(a.amount))::text from public.inv_layer_cost_add a where a.layer_id = :'y1'::bigint) || '/' || (select trim_scale(v.remaining_value)::text from public.inv_layer_value(:'y1'::bigint) v), '0/true/1/-35/null/posted/po_credit/true/-35/280');

-- ═══ F2 · F3 — 100 청구 · 100 입고 · 사람이 100 × 0.30 줄(제안 price_difference) · 30 판매 뒤 확정 → 사건 −30 · cost_late −9 · 레이어 몫 −21 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_invoice_create('credit', null, null, :'i5'::uuid, null, '2026-10-05', null, 30.00, true, true, null) as r \gset c2_
select (:'c2_r'::jsonb->>'id') as c2 \gset
select public.po_invoice_line_add(:'c2'::uuid, jsonb_build_object('po_line_id', :'l6', 'qty_ea', 100, 'unit_price', 0.30)) as r \gset la2_
reset role;
insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) values (:'y6'::bigint, 'sale', 'SO-79700', 'DISC5A-P6:1', 'sale_out', '2026-10-04', 30, 3.50, 105, 'sale');
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_invoice_confirm(:'c2'::uuid, true) as r \gset cf2_
reset role;
select (:'la2_r'::jsonb->'line'->>'id') as c2l1 \gset
select pg_temp.chk('F2/F3 credit from a fully received invoice: auto lines 0 (no_qty_difference) · added line suggested price_difference (left 0) · warning credit_reason_suggested · confirm: event −30 posted · cost_late −9 (30 of 100 sold) · y6 remaining 350 − 30 − (105 − 9) = 224 · unit 3.2', (:'c2_r'::jsonb->>'line_count') || '/' || (:'c2_r'::jsonb->'warnings' ? 'no_qty_difference')::text || '/' || (:'la2_r'::jsonb->>'credit_reason_suggested') || '/' || trim_scale((:'la2_r'::jsonb->>'credit_not_received_left')::numeric)::text || '/' || (:'la2_r'::jsonb->'warnings' ? 'credit_reason_suggested:price_difference')::text || '/' || (select trim_scale(j.amount_cad)::text || ':' || j.status from public.inv_cost_adjust j where j.source_id = :'c2l1'::uuid) || '/' || (select trim_scale(k.amount)::text from public.inv_layer_consume k where k.layer_id = :'y6'::bigint and k.reason = 'cost_late') || '/' || (select trim_scale(v.remaining_value)::text || '/' || trim_scale(v.unit_cost)::text from public.inv_layer_value(:'y6'::bigint) v), '0/true/price_difference/0/true/-30:posted/-9/224/3.2');

-- ═══ F6 — 취소(되돌림 · 합 0) → 복구(confirmed · 새 사건) → 다시 열기(되돌림) → 다시 확정(새 사건) · 줄의 사건 5(원래 3 · 되돌림 2) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_doc_cancel('invoice', :'c2'::uuid, true) as r \gset cn2_
select trim_scale(coalesce(sum(a.amount), 0))::text as y6_after_cancel from public.inv_layer_cost_add a where a.layer_id = :'y6'::bigint \gset
select string_agg(trim_scale(k.amount)::text, ',' order by k.id) as late_after_cancel from public.inv_layer_consume k where k.layer_id = :'y6'::bigint and k.reason = 'cost_late' \gset
select public.po_doc_cancel('invoice', :'c2'::uuid, false) as r \gset rs2_
select trim_scale(coalesce(sum(a.amount), 0))::text as y6_after_restore from public.inv_layer_cost_add a where a.layer_id = :'y6'::bigint \gset
select public.po_invoice_confirm(:'c2'::uuid, false) as r \gset ro2_
select trim_scale(coalesce(sum(a.amount), 0))::text as y6_after_reopen from public.inv_layer_cost_add a where a.layer_id = :'y6'::bigint \gset
select public.po_invoice_confirm(:'c2'::uuid, true) as r \gset cf2b_
reset role;
select pg_temp.chk('F6 cancel: reversed 1 · y6 adds 0 · cost_late rows −9,+9 · restore → confirmed · new event 1 · adds −30 · reopen: reversed 1 · adds 0 · re-confirm: new event · adds −30 · events for the line 5 (3 originals · 2 reversals) · current un-reversed 1', (:'cn2_r'::jsonb->'cost_reversed'->>'reversed') || '/' || :'y6_after_cancel' || '/' || :'late_after_cancel' || '/' || (:'rs2_r'::jsonb->>'status') || '/' || (:'rs2_r'::jsonb->'cost_events'->>'event_count') || '/' || :'y6_after_restore' || '/' || (:'ro2_r'::jsonb->'cost_reversed'->>'reversed') || '/' || :'y6_after_reopen' || '/' || (:'cf2b_r'::jsonb->'cost_events'->>'event_count') || '/' || (select trim_scale(coalesce(sum(a.amount), 0))::text from public.inv_layer_cost_add a where a.layer_id = :'y6'::bigint) || '/' || (select count(*) from public.inv_cost_adjust j where j.source_id = :'c2l1'::uuid or j.reverses_id in (select id from public.inv_cost_adjust where source_id = :'c2l1'::uuid)) || '/' || (select count(*) from public.inv_cost_adjust j where j.source_id = :'c2l1'::uuid and not exists (select 1 from public.inv_cost_adjust r where r.reverses_id = j.id)), '1/0/-9,9/confirmed/1/-30/1/0/1/-30/5/1');

-- ═══ F5 — 걸치는 줄(⬜1): L1 남은 안 온 수량 10 · 줄 15 → 제안 not_received + 경고 spans · 확정 거부(split the line) · price_difference 로 바꾸면 확정 · 사건 −52.50 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_invoice_create('credit', null, null, :'i1'::uuid, null, '2026-10-06', null, 52.50, true, true, null) as r \gset c3_
select (:'c3_r'::jsonb->>'id') as c3 \gset
select public.po_invoice_line_delete((select cl.id from public.po_invoice_line cl where cl.po_invoice_id = :'c3'::uuid limit 1)) as r \gset ld3_
select public.po_invoice_line_add(:'c3'::uuid, jsonb_build_object('po_line_id', :'l1', 'qty_ea', 15, 'unit_price', 3.50)) as r \gset la3_
select (:'la3_r'::jsonb->'line'->>'id') as c3l1 \gset
select public.po_invoice_detail(:'c3'::uuid) as r \gset d3_
select pg_temp.err(format('select public.po_invoice_confirm(%L::uuid, true)', :'c3')) as cf3_err \gset
select public.po_invoice_line_update(:'c3l1'::uuid, '{"credit_reason":"price_difference"}'::jsonb) as r \gset lu3_
select public.po_invoice_confirm(:'c3'::uuid, true) as r \gset cf3_
reset role;
select pg_temp.chk('F5 spanning line (left 10 · qty 15): suggested not_received · spans true · warning on add and in detail · confirm refused (split the line · 15 vs 10) · as price_difference: confirmed · event −52.5 posted · y1 remaining 227.5', (:'la3_r'::jsonb->>'credit_reason_suggested') || '/' || (:'la3_r'::jsonb->>'credit_spans_both') || '/' || (:'la3_r'::jsonb->'warnings' ? 'credit_line_spans_both')::text || '/' || (:'d3_r'::jsonb->'warnings' ? 'credit_line_spans_both')::text || '/' || (:'cf3_err' like 'P0001 Credit note %: line 1 (DISC5A-P1) marks 15 EA as Not received but only 10 EA are still unreceived on that PO line (billed 100 · received 90 · already credited 0) — split the line%')::text || '/' || (:'cf3_r'::jsonb->>'status') || '/' || (select trim_scale(j.amount_cad)::text || ':' || j.status from public.inv_cost_adjust j where j.source_id = :'c3l1'::uuid) || '/' || (select trim_scale(v.remaining_value)::text from public.inv_layer_value(:'y1'::bigint) v), 'not_received/true/true/true/true/confirmed/-52.5:posted/227.5');

-- ═══ F7 — 판정 399: 10 × 1.50 = 15 > 레이어 원가 10 → 확정 전체 저장 안 됨(status draft · 사건 0) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_invoice_create('credit', null, null, :'i4'::uuid, null, '2026-10-06', null, 15.00, true, true, null) as r \gset c5_
select (:'c5_r'::jsonb->>'id') as c5 \gset
select public.po_invoice_line_add(:'c5'::uuid, jsonb_build_object('po_line_id', :'l5', 'qty_ea', 10, 'unit_price', 1.50, 'credit_reason', 'price_difference')) as r \gset la5_
select pg_temp.err(format('select public.po_invoice_confirm(%L::uuid, true)', :'c5')) as cf5_err \gset
reset role;
select pg_temp.chk('F7 ruling 399: confirm refused with the layer sentence · credit still draft · events 0 · y5 adds 0', (:'cf5_err' like 'P0001 Cost adjustment % is a credit larger than the cost of the goods on layer %')::text || '/' || (select status from public.po_invoice where id = :'c5'::uuid) || '/' || (select count(*) from public.inv_cost_adjust j where j.source_id in (select id from public.po_invoice_line where po_invoice_id = :'c5'::uuid)) || '/' || (select count(*) from public.inv_layer_cost_add where layer_id = :'y5'::bigint), 'true/draft/0/0');

-- ═══ F8 — 입고 전 가격 크레딧: 제안 not_received(left 100) → 사람이 price_difference(경고 differs · above_received) · 확정 → pending · 입고 확정 ⓖ → posted · y4 400 → 350 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_invoice_create('credit', null, null, :'i3'::uuid, null, '2026-10-06', null, 50.00, true, true, null) as r \gset c6_
select (:'c6_r'::jsonb->>'id') as c6 \gset
select public.po_invoice_line_delete((select cl.id from public.po_invoice_line cl where cl.po_invoice_id = :'c6'::uuid limit 1)) as r \gset ld6_
select public.po_invoice_line_add(:'c6'::uuid, jsonb_build_object('po_line_id', :'l4', 'qty_ea', 100, 'unit_price', 0.50)) as r \gset la6_
select (:'la6_r'::jsonb->'line'->>'id') as c6l1 \gset
select public.po_invoice_line_update(:'c6l1'::uuid, '{"credit_reason":"price_difference"}'::jsonb) as r \gset lu6_
select public.po_invoice_confirm(:'c6'::uuid, true) as r \gset cf6_
reset role;
select j.status as c6_db_status from public.inv_cost_adjust j where j.source_id = :'c6l1'::uuid \gset
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_receipt_confirm_by(:'g_sid'::uuid, :'r2'::uuid) as r \gset rc6_
select y.id::text as y4 from public.inv_layer y where y.doc_number = 'RCV-79702' \gset
select pg_temp.chk('F8 before receipt: auto line 100 not_received removed · added line suggested not_received (left 100) · set price_difference (warning differs) · confirm: warning price_credit_qty_above_received:1 · no fx warning (CAD) · event no_layers (DB row pending) · then receipt confirm: adjustments posted 1 (−50) · y4 100@4 remaining 350', (:'c6_r'::jsonb->>'line_count') || '/' || (:'la6_r'::jsonb->>'credit_reason_suggested') || '/' || trim_scale((:'la6_r'::jsonb->>'credit_not_received_left')::numeric)::text || '/' || (:'lu6_r'::jsonb->'warnings' ? 'credit_reason_differs_from_suggestion:not_received')::text || '/' || (:'cf6_r'::jsonb->'warnings' ? 'price_credit_qty_above_received:1')::text || '/' || (:'cf6_r'::jsonb->'warnings' ? 'credit_fx_unpinned:1')::text || '/' || (:'cf6_r'::jsonb->'cost_events'->'events'->0->>'status') || ':' || :'c6_db_status' || '/' || jsonb_array_length(:'rc6_r'::jsonb->'adjustments'->'posted') || '/' || trim_scale((:'rc6_r'::jsonb->'adjustments'->'posted'->0->>'posted_cad')::numeric)::text || '/' || (select trim_scale(v.remaining_value)::text from public.inv_layer_value(:'y4'::bigint) v), '1/not_received/100/true/true/false/no_layers:pending/1/-50/350');

-- ═══ F9 — USD 핀 1.35 · 크레딧 환율 1.40(⬜2): 사건 amount_doc −50 · exchange_rate 1.35(pinned) · amount_cad −67.5 · y3 675 → 607.5 · 경고 없음 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_invoice_create('credit', null, null, :'i2'::uuid, null, '2026-10-06', null, 50.00, true, true, null) as r \gset c4_
select (:'c4_r'::jsonb->>'id') as c4 \gset
reset role;
set local session_replication_role = replica;
update public.po_invoice set exchange_rate = 1.40 where id = :'c4'::uuid;
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_invoice_line_add(:'c4'::uuid, jsonb_build_object('po_line_id', :'l3', 'qty_ea', 100, 'unit_price', 0.50, 'credit_reason', 'price_difference')) as r \gset la4_
select public.po_invoice_confirm(:'c4'::uuid, true) as r \gset cf4_
reset role;
select pg_temp.chk('F9 USD credit (credit fx 1.40 · pin 1.35): event amount_doc −50 · exchange_rate 1.35 · source pinned · amount_cad −67.5 · posted · y3 remaining 607.5 · no credit_fx warnings', (select trim_scale(j.amount_doc)::text || '/' || trim_scale(j.exchange_rate)::text || '/' || trim_scale(j.amount_cad)::text || '/' || j.status from public.inv_cost_adjust j where j.source_id = (:'la4_r'::jsonb->'line'->>'id')::uuid) || '/' || (:'cf4_r'::jsonb->'cost_events'->'events'->0->>'exchange_rate_source') || '/' || (select trim_scale(v.remaining_value)::text from public.inv_layer_value(:'y3'::bigint) v) || '/' || (select count(*) from jsonb_array_elements_text(:'cf4_r'::jsonb->'warnings') w where w like 'credit_fx_%'), '-50/1.35/-67.5/posted/pinned/607.5/0');

-- ═══ H1 — 권한: anon 없음 · 속 함수 둘 authenticated 없음 · 열쇠 없는 직원 거부 · 인보이스 줄에 credit_reason → 거부(창구 · 트리거) ═══
set local role anon;
do $$ begin perform public.po_credit_reason_suggest(gen_random_uuid(), gen_random_uuid(), 1, null); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as an1 \gset
reset role;
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
do $$ begin perform public.po_credit_cost_events(gen_random_uuid(), false); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as au1 \gset
do $$ begin perform public.po_credit_cost_reverse(gen_random_uuid(), null); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as au2 \gset
select (public.po_invoice_create('invoice', 'PODISC5A-I6', :'po0'::uuid, null, null, '2026-10-07', null, 0, true, true, null))->>'id' as i6 \gset
select pg_temp.err(format('select public.po_invoice_line_add(%L::uuid, jsonb_build_object(''po_line_id'', %L, ''qty_ea'', 1, ''unit_price'', 1, ''credit_reason'', ''not_received''))', :'i6', :'l1')) as au3 \gset
select pg_temp.err(format('select public.po_invoice_line_add(%L::uuid, jsonb_build_object(''po_line_id'', %L, ''qty_ea'', 1, ''unit_price'', 1, ''credit_reason'', ''maybe''))', :'c5', :'l5')) as au4 \gset
select set_config('request.jwt.claims', :'n_claims', true);
do $$ begin perform public.po_invoice_confirm(gen_random_uuid(), true); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
select current_setting('app.out', true) as nk1 \gset
do $$ begin perform public.po_doc_cancel('invoice', gen_random_uuid(), true); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
select current_setting('app.out', true) as nk2 \gset
reset role;
select pg_temp.err(format('update public.po_invoice_line set credit_reason = ''not_received'' where po_invoice_id = %L and line_no = 1', :'i1')) as tg1 \gset
select pg_temp.chk('H1 anon suggest → 42501 · inner events · reverse → 42501 (authenticated) · draft invoice line with a reason via the add door → refused · bad value → refused · no-key staff confirm · cancel → purchasing sentences · trigger refuses reason on an invoice line', :'an1' || ',' || :'au1' || ',' || :'au2' || ',' || (:'au3' like 'P0001 credit_reason belongs to goods lines of a credit note only%')::text || ',' || (:'au4' like 'P0001 credit_reason must be not_received or price_difference (got maybe)%')::text || ',' || (:'nk1' = 'P0001 You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was saved')::text || ',' || (:'nk2' = 'P0001 You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was saved')::text || ',' || (:'tg1' like 'P0001 credit_reason belongs to goods lines of a credit note only (line 1 is goods on an invoice document)%')::text, '42501,42501,42501,true,true,true,true,true');

-- ═══ H2 — 실물 무변 · 사건 수 = 머리 + 이번 차수(시험 0 · 확인 0 — 이 차수는 실제 사건을 만들지 않는다) · 재생성 +2.73 · deferred 0 ═══
\if :{?mig}
\set ev_new 0
\else
\set ev_new 0
\endif
select md5(string_agg(i.id::text || '|' || i.doc_kind || '|' || i.invoice_number || '|' || i.status || '|' || i.total_amount::text || '|' || coalesce(i.confirmed_at::text, ''), ',' order by i.id)) as real_inv_mid from public.po_invoice i where i.invoice_number not like 'PODISC5A-%' and i.invoice_number not like 'CN-PO-797%' \gset
select md5(string_agg(il.id::text || '|' || il.line_kind || '|' || il.qty_ea::text || '|' || il.unit_price::text, ',' order by il.id)) as real_line_mid from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id where i.invoice_number not like 'PODISC5A-%' and i.invoice_number not like 'CN-PO-797%' \gset
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_mid from public.inv_layer l where l.sku not like 'DISC5A-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by a.id)) as real_adds_mid from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC5A-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text, ',' order by k.id)) as real_consume_mid from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC5A-%' \gset
select pg_temp.chk('H2a real rows unchanged inside the test (invoices · lines incl. the real draft credit · layers · adds · consume) · real credit line reason still null · real events = head + this round', (:'real_inv_mid' = :'real_inv_head')::text || '/' || (:'real_line_mid' = :'real_line_head')::text || '/' || (:'real_layers_mid' = :'real_layers_head')::text || '/' || (:'real_adds_mid' = :'real_adds_head')::text || '/' || (:'real_consume_mid' = :'real_consume_head')::text || '/' || (select count(*) from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id where i.doc_kind = 'credit' and i.invoice_number not like 'CN-PO-797%' and il.credit_reason is not null) || '/' || (select count(*) from public.inv_cost_adjust j where j.po_line_id not in (select pl.id from public.po_line pl join public.po x on x.id = pl.po_id where x.po_number like 'PO-797%') or j.po_line_id is null), 'true/true/true/true/true/0/' || (:real_events_head + :ev_new)::text);
select round(sum(unit_cost * qty), 4) as val_before from public.inv_layer where sku not like 'DISC5A-%' \gset
select set_config('request.jwt.claims', :'g_claims', true);
select clock_timestamp() as ta0 \gset
select public.inv_layer_apply() as r \gset apply_
select clock_timestamp() as ta1 \gset
select 'timing: inv_layer_apply ms=' || round(extract(epoch from (:'ta1'::timestamptz - :'ta0'::timestamptz)) * 1000);
select round(sum(unit_cost * qty), 4) as val_after from public.inv_layer where sku not like 'DISC5A-%' \gset
select 'H2 regen: value before=' || :val_before || ' after=' || :val_after || ' diff=' || (:val_after - :val_before)::text || ' · adjusts: ' || (:'apply_r'::jsonb->'ims'->'adjusts')::text;
select pg_temp.chk('H2b regen total value diff (real · fakes excluded) = +2.73 · adjusts deferred 0 · skipped 0 · posted = posted count', round(:val_after - :val_before, 2)::text || '/' || (:'apply_r'::jsonb->'ims'->'adjusts'->>'deferred') || '/' || (:'apply_r'::jsonb->'ims'->'adjusts'->>'skipped') || '/' || ((:'apply_r'::jsonb->'ims'->'adjusts'->>'posted')::int = (select count(*) from public.inv_cost_adjust where status = 'posted'))::text, '2.73/0/0/true');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select md5(string_agg(i.id::text || '|' || i.doc_kind || '|' || i.invoice_number || '|' || i.status || '|' || i.total_amount::text || '|' || coalesce(i.confirmed_at::text, ''), ',' order by i.id)) as real_inv_tail, count(*) as real_inv_tail_n from public.po_invoice i where i.invoice_number not like 'PODISC5A-%' and i.invoice_number not like 'CN-PO-797%' \gset
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_tail, count(*) as real_layers_tail_n from public.inv_layer l where l.sku not like 'DISC5A-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by a.id)) as real_adds_tail, count(*) as real_adds_tail_n from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC5A-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text, ',' order by k.id)) as real_consume_tail, count(*) as real_consume_tail_n from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC5A-%' \gset
select 'REAL_SAME invoices ' || (:'real_inv_head' = :'real_inv_tail')::text || ' (' || :real_inv_n || ' → ' || :real_inv_tail_n || ') layers ' || (:'real_layers_head' = :'real_layers_tail')::text || ' (' || :real_layers_n || ' → ' || :real_layers_tail_n || ') adds ' || (:'real_adds_head' = :'real_adds_tail')::text || ' (' || :real_adds_n || ' → ' || :real_adds_tail_n || ') consume ' || (:'real_consume_head' = :'real_consume_tail')::text || ' (' || :real_consume_n || ' → ' || :real_consume_tail_n || ')';
select setval('public.inv_layer_cost_add_id_seq', greatest((select max(id) from public.inv_layer_cost_add), :add_seq_last), true);
select setval('public.inv_layer_consume_id_seq', greatest((select max(id) from public.inv_layer_consume), :con_seq_last), true);
select 'seq tail po ' || last_value || ' ' || is_called from public.po_number_seq;
select 'seq tail rcv ' || last_value || ' ' || is_called from public.po_receipt_number_seq;
select 'seq tail cost_add ' || last_value || ' ' || is_called || ' (head ' || :add_seq_last || ' · reset to greatest(max, head))' from public.inv_layer_cost_add_id_seq;
select 'seq tail consume ' || last_value || ' ' || is_called || ' (head ' || :con_seq_last || ' · reset to greatest(max, head))' from public.inv_layer_consume_id_seq;
