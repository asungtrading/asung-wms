-- po-disc-5b-verify.sql — 환율 차액: po_fx_cost_status(핀 출처 po 만 · invoice 제외 · 기준통화 0) · po_fx_cost_apply(멱등 · 되돌림 부호 · 399 · 판매 · 트랜스퍼 뒤 settle · 미리 보기) · 권한 · 실물 무변 (Asung-IMS · 2026-10-09)
--   기대: 시험 갈래(-v mig) OK 13 · 확인 갈래 OK 12(= 13 − 시험 전용 1: D0a) · MISMATCH 0 · 증감 기대는 두 갈래(\if :{?mig})
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/<ts>_po_disc_5b.sql -f supabase/tests/po-disc-5b-verify.sql > /tmp/po-disc-5b.out 2>&1; echo "rc=$?"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료는 가짜만(PO-798xx · PODISC5B-* · RCV-798xx · 가짜 공급처 · 직원) · 실제 행 무변(실제 PO 는 상태 창구로 읽기만) · 끝은 rollback · identity 시퀀스는 greatest(실제 최대, 머리)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as po_seq_last, is_called as po_seq_called from public.po_number_seq \gset
select last_value as rcv_seq_last, is_called as rcv_seq_called from public.po_receipt_number_seq \gset
select last_value as add_seq_last, is_called as add_seq_called from public.inv_layer_cost_add_id_seq \gset
select last_value as con_seq_last, is_called as con_seq_called from public.inv_layer_consume_id_seq \gset
\echo '== seq head po' :po_seq_last :po_seq_called 'rcv' :rcv_seq_last :rcv_seq_called 'cost_add' :add_seq_last :add_seq_called 'consume' :con_seq_last :con_seq_called
select md5(string_agg(x.id::text || '|' || x.po_number || '|' || x.status || '|' || coalesce(x.exchange_rate::text, ''), ',' order by x.id)) as real_po_head, count(*) as real_po_n from public.po x where x.po_number not like 'PO-798%' \gset
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_head, count(*) as real_layers_n from public.inv_layer l where l.sku not like 'DISC5B-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by a.id)) as real_adds_head, count(*) as real_adds_n from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC5B-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text, ',' order by k.id)) as real_consume_head, count(*) as real_consume_n from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC5B-%' \gset
select count(*) as real_events_head from public.inv_cost_adjust \gset
select count(*) as real_pins_head from public.po_receipt_cost \gset
\echo '== real head pos' :real_po_n :real_po_head 'layers' :real_layers_n :real_layers_head 'adds' :real_adds_n 'consume' :real_consume_n 'events' :real_events_head 'pins' :real_pins_head

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

-- ═══ 재료(postgres · 가짜) — 직원 둘 · 공급처 · 제품 5 · PO 4(USD 1.35 셋 · CAD 하나) · 인보이스 1(L2 만 · 핀 출처 invoice) · 입고 4 · 레이어 5 + 자식 1 ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc5b-g@test.invalid', 'PODISC5B Purchasing+Receiving', 'manager', '["purchasing","receiving"]'::jsonb) returning auth_user_id::text as g_uid, id::text as g_sid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'podisc5b-n@test.invalid', 'PODISC5B NoKeys', 'manager', '[]'::jsonb) returning auth_user_id::text as n_uid \gset
\set g_claims '{"sub":"' :g_uid '","role":"authenticated"}'
\set n_claims '{"sub":"' :n_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as usd from public.ref_currency where code = 'USD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.id::text as bin, b.name as binname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select id::text as hst, name as hstname from public.ref_tax_rule where direction = 'purchase' and is_active and name = 'HST ON (Purchase)' limit 1 \gset
insert into public.supplier (name, payment_term_name, account_payable_code, currency_id) values ('PODISC5B Supplier', 'Net 30', '2000', :'usd'::uuid) returning id::text as sup \gset
insert into public.product (sku, name, source) select 'DISC5B-P' || i, 'PODISC5B P' || i, 'manual' from generate_series(1, 5) i;
set local session_replication_role = replica;
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at, tax_rule_id, tax_rule) values
  ('PO-79800', 'confirmed', :'sup'::uuid, :'usd'::uuid, 1.35, '2026-10-01', :'wh'::uuid, now(), :'hst'::uuid, :'hstname'),
  ('PO-79801', 'confirmed', :'sup'::uuid, :'usd'::uuid, 1.35, '2026-10-01', :'wh'::uuid, now(), :'hst'::uuid, :'hstname'),
  ('PO-79802', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2026-10-01', :'wh'::uuid, now(), :'hst'::uuid, :'hstname'),
  ('PO-79803', 'confirmed', :'sup'::uuid, :'usd'::uuid, 1.35, '2026-10-01', :'wh'::uuid, now(), :'hst'::uuid, :'hstname');
select string_agg(id::text, ' ' order by po_number) as pos from public.po where po_number like 'PO-798%' \gset
select split_part(:'pos', ' ', 1) as po0, split_part(:'pos', ' ', 2) as po1, split_part(:'pos', ' ', 3) as po2, split_part(:'pos', ' ', 4) as po3 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po0'::uuid, 1, id, 100, 5.00 from public.product where sku = 'DISC5B-P1';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po0'::uuid, 2, id, 50, 4.00 from public.product where sku = 'DISC5B-P2';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po1'::uuid, 1, id, 100, 2.00 from public.product where sku = 'DISC5B-P3';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po2'::uuid, 1, id, 100, 3.00 from public.product where sku = 'DISC5B-P4';
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) select :'po3'::uuid, 1, id, 10, 1.00 from public.product where sku = 'DISC5B-P5';
select pl.id::text as l1 from public.po_line pl where pl.po_id = :'po0'::uuid and pl.line_no = 1 \gset
select pl.id::text as l2 from public.po_line pl where pl.po_id = :'po0'::uuid and pl.line_no = 2 \gset
select pl.id::text as l3 from public.po_line pl where pl.po_id = :'po1'::uuid \gset
select pl.id::text as l4 from public.po_line pl where pl.po_id = :'po2'::uuid \gset
select pl.id::text as l5 from public.po_line pl where pl.po_id = :'po3'::uuid \gset
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select (public.po_invoice_create('invoice', 'PODISC5B-I1', :'po0'::uuid, null, null, '2026-10-02', null, 226.00, true, true, jsonb_build_object(:'l2', 50)))->>'id' as i1 \gset
reset role;
set local session_replication_role = replica;
update public.po_invoice set status = 'confirmed', confirmed_at = now() where id = :'i1'::uuid;
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at) values
  ('RCV-79800', :'po0'::uuid, :'wh'::uuid, '2026-10-03', 'confirmed', now()), ('RCV-79801', :'po1'::uuid, :'wh'::uuid, '2026-10-03', 'confirmed', now()),
  ('RCV-79802', :'po2'::uuid, :'wh'::uuid, '2026-10-03', 'confirmed', now()), ('RCV-79803', :'po3'::uuid, :'wh'::uuid, '2026-10-03', 'confirmed', now());
select id::text as r0 from public.po_receipt where receipt_number = 'RCV-79800' \gset
select id::text as r1 from public.po_receipt where receipt_number = 'RCV-79801' \gset
select id::text as r2 from public.po_receipt where receipt_number = 'RCV-79802' \gset
select id::text as r3 from public.po_receipt where receipt_number = 'RCV-79803' \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, source, raw) values
  ('2026-10-03', 1, 'DISC5B-P1', :'whname', :'binname', 100, 'po_in', 'purchase', 'RCV-79800', :'r0', :'l1', 'ims', '{"fake":"po-disc-5b"}'),
  ('2026-10-03', 1, 'DISC5B-P2', :'whname', :'binname', 50,  'po_in', 'purchase', 'RCV-79800', :'r0', :'l2', 'ims', '{"fake":"po-disc-5b"}'),
  ('2026-10-03', 1, 'DISC5B-P3', :'whname', :'binname', 100, 'po_in', 'purchase', 'RCV-79801', :'r1', :'l3', 'ims', '{"fake":"po-disc-5b"}'),
  ('2026-10-03', 1, 'DISC5B-P4', :'whname', :'binname', 100, 'po_in', 'purchase', 'RCV-79802', :'r2', :'l4', 'ims', '{"fake":"po-disc-5b"}'),
  ('2026-10-03', 1, 'DISC5B-P5', :'whname', :'binname', 10,  'po_in', 'purchase', 'RCV-79803', :'r3', :'l5', 'ims', '{"fake":"po-disc-5b"}');
set local session_replication_role = origin;
select set_config('request.jwt.claims', :'g_claims', true);
select public.inv_layer_post_receipt(:'r0'::uuid) as r \gset f0_
select public.inv_layer_post_receipt(:'r1'::uuid) as r \gset f1_
select public.inv_layer_post_receipt(:'r2'::uuid) as r \gset f2_
select public.inv_layer_post_receipt(:'r3'::uuid) as r \gset f3_
select y.id::text as y1 from public.inv_layer y where y.doc_number = 'RCV-79800' and y.line_ref = :'l1' \gset
select y.id::text as y2 from public.inv_layer y where y.doc_number = 'RCV-79800' and y.line_ref = :'l2' \gset
select y.id::text as y3 from public.inv_layer y where y.doc_number = 'RCV-79801' \gset
select y.id::text as y4 from public.inv_layer y where y.doc_number = 'RCV-79802' \gset
select y.id::text as y5 from public.inv_layer y where y.doc_number = 'RCV-79803' \gset
-- G4 재료: y3 에서 20 판매 · 30 트랜스퍼(자식 레이어 · 다른 창고)
insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) values
  (:'y3'::bigint, 'sale', 'SO-79800', 'DISC5B-P3:1', 'sale_out', '2026-10-04', 20, 2.70, 54, 'sale'),
  (:'y3'::bigint, 'transfer', 'TRF-79800', 'DISC5B-P3:1', 'transfer_out', '2026-10-04', 30, 2.70, 81, 'transfer');
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source) values ('DISC5B-P3', 'DISC5B-WH2', 'transfer', 'TRF-79800', 'DISC5B-P3:1', :'y3'::bigint, '2026-10-04', true, 30, 2.70, 'parent_layer') returning id::text as y3c \gset
select pg_temp.chk('M fake material: layers y1 100@6.75 (pin po 1.35) · y2 50@5.4 (pin invoice 1.35) · y3 100@2.7 (pin po) · y4 100@3 (CAD · pin fx null) · y5 10@1.35 (pin po) · child 30@2.7', (select trim_scale(y.qty)::text || '@' || trim_scale(y.unit_cost)::text || ':' || coalesce(k.exchange_rate_source, 'null') || ':' || coalesce(trim_scale(k.exchange_rate)::text, 'null') from public.inv_layer y join public.po_receipt r on r.receipt_number = y.doc_number join public.po_receipt_cost k on k.receipt_id = r.id and k.po_line_id::text = y.line_ref where y.id = :'y1'::bigint) || '/' || (select trim_scale(y.unit_cost)::text || ':' || k.exchange_rate_source from public.inv_layer y join public.po_receipt r on r.receipt_number = y.doc_number join public.po_receipt_cost k on k.receipt_id = r.id and k.po_line_id::text = y.line_ref where y.id = :'y2'::bigint) || '/' || (select trim_scale(y.unit_cost)::text || ':' || k.exchange_rate_source from public.inv_layer y join public.po_receipt r on r.receipt_number = y.doc_number join public.po_receipt_cost k on k.receipt_id = r.id and k.po_line_id::text = y.line_ref where y.id = :'y3'::bigint) || '/' || (select trim_scale(y.unit_cost)::text || ':' || coalesce(k.exchange_rate_source, 'null') from public.inv_layer y join public.po_receipt r on r.receipt_number = y.doc_number join public.po_receipt_cost k on k.receipt_id = r.id and k.po_line_id::text = y.line_ref where y.id = :'y4'::bigint) || '/' || (select trim_scale(y.unit_cost)::text from public.inv_layer y where y.id = :'y5'::bigint) || '/' || (select trim_scale(y.qty)::text || '@' || trim_scale(y.unit_cost)::text from public.inv_layer y where y.id = :'y3c'::bigint), '100@6.75:po:1.35/5.4:invoice/2.7:po/3:null/1.35/30@2.7');

-- ═══ D0 · G0 — 적용 전(시험 갈래): 창구 셋 없음 · fx_fix 사건 0 · 무접촉 md5 ═══
\if :{?mig}
select pg_temp.chk('D0a before: no po_fx_cost_lines / status / apply · fx_fix events 0', (to_regprocedure('public.po_fx_cost_lines(uuid)') is null and to_regprocedure('public.po_fx_cost_status(uuid)') is null and to_regprocedure('public.po_fx_cost_apply(uuid, boolean)') is null)::text || '/' || (select count(*) from public.inv_cost_adjust where source_type = 'fx_fix'), 'true/0');
\i :mig
\endif
select pg_temp.chk('D0b after: three functions · apply definer · status/lines invoker · fx_fix events 0 · untouched post_cost_adjust 1f95d60c · reverse 02d8d9b9 · post_receipt 989cf1f9 · po_detail a2c1c426', (to_regprocedure('public.po_fx_cost_lines(uuid)') is not null and to_regprocedure('public.po_fx_cost_status(uuid)') is not null and to_regprocedure('public.po_fx_cost_apply(uuid, boolean)') is not null)::text || '/' || (select string_agg(p.proname || ':' || p.prosecdef::text, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'po_fx_cost_%') || '/' || (select count(*) from public.inv_cost_adjust where source_type = 'fx_fix') || '/' || (select string_agg(left(md5(p.prosrc), 8), ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_post_cost_adjust', 'inv_cost_adjust_reverse', 'inv_layer_post_receipt', 'po_detail')), 'true/po_fx_cost_apply:true,po_fx_cost_lines:false,po_fx_cost_status:false/0/02d8d9b9,1f95d60c,989cf1f9,a2c1c426');

-- ═══ G1 — 환율 1.35 → 1.40(po.html 이 PostgREST 로 하듯 직접) · 상태: po 출처 줄만 차액 25 · invoice 출처 레이어 제외 1 · 전체 시간(실제 PO 포함) ═══
update public.po set exchange_rate = 1.40 where id = :'po0'::uuid;
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select clock_timestamp() as t0 \gset
select public.po_fx_cost_status(:'po0'::uuid) as r \gset s1_
select clock_timestamp() as t1 \gset
select public.po_fx_cost_status((select x.id from public.po x join public.ref_currency c on c.id = x.currency_id where c.code <> 'CAD' and x.po_number not like 'PO-798%' and exists (select 1 from public.po_line pl join public.inv_layer y on y.line_ref = pl.id::text where pl.po_id = x.id) order by x.po_number limit 1)) as r \gset sr_
select clock_timestamp() as t2 \gset
reset role;
select 'timing: po_fx_cost_status fake PO ms=' || round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000) || ' · real PO ' || (:'sr_r'::jsonb->>'po_number') || ' ms=' || round(extract(epoch from (:'t2'::timestamptz - :'t1'::timestamptz)) * 1000) || ' lines=' || jsonb_array_length(:'sr_r'::jsonb->'lines') || ' unpinned=' || (:'sr_r'::jsonb->>'unpinned_layers') || ' remaining=' || (:'sr_r'::jsonb->>'total_remaining_cad');
select pg_temp.chk('G1 status after 1.35 → 1.40: fx_now 1.4 · not base · L1 (pin po 1.35 · net 5 · qty 100) target 700 · already 675 · remaining 25 · L2 excluded (invoice) remaining 0 · excluded_invoice_layers 1 · affected_lines 1 · total 25 · affected true · no warnings', trim_scale((:'s1_r'::jsonb->>'fx_now')::numeric)::text || '/' || (:'s1_r'::jsonb->>'is_base') || '/' || (select (x->>'pin_source') || '/' || trim_scale((x->>'pin_fx')::numeric)::text || '/' || trim_scale((x->>'target_cad')::numeric)::text || '/' || trim_scale((x->>'already_cad')::numeric)::text || '/' || trim_scale((x->>'remaining_cad')::numeric)::text from jsonb_array_elements(:'s1_r'::jsonb->'lines') x where x->>'po_line_id' = :'l1') || '/' || (select coalesce(x->>'pin_source', 'null') || '/' || trim_scale((x->>'remaining_cad')::numeric)::text || '/' || (x->>'excluded_invoice_layers') from jsonb_array_elements(:'s1_r'::jsonb->'lines') x where x->>'po_line_id' = :'l2') || '/' || (:'s1_r'::jsonb->>'excluded_invoice_layers') || '/' || (:'s1_r'::jsonb->>'affected_lines') || '/' || trim_scale((:'s1_r'::jsonb->>'total_remaining_cad')::numeric)::text || '/' || (:'s1_r'::jsonb->>'affected') || '/' || jsonb_array_length(:'s1_r'::jsonb->'warnings'), '1.4/false/po/1.35/700/675/25/null/0/1/1/1/25/true/0');

-- ═══ G6 — 미리 보기: 사건 1 (25 · preview) · 저장 0 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_fx_cost_apply(:'po0'::uuid, false) as r \gset pv_
reset role;
select pg_temp.chk('G6 preview: committed false · event_count 1 · amount 25 · status preview · no id · DB fx_fix events 0', (:'pv_r'::jsonb->>'committed') || '/' || (:'pv_r'::jsonb->>'event_count') || '/' || trim_scale((:'pv_r'::jsonb->'events'->0->>'amount_cad')::numeric)::text || '/' || (:'pv_r'::jsonb->'events'->0->>'status') || '/' || coalesce(:'pv_r'::jsonb->'events'->0->>'id', 'null') || '/' || (select count(*) from public.inv_cost_adjust where source_type = 'fx_fix'), 'false/1/25/preview/null/0');

-- ═══ G2 — 반영 → 사건 +25 posted · y1 adds +25 · 상태 남은 0 · 같은 환율로 또 반영 → 사건 0 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_fx_cost_apply(:'po0'::uuid, true) as r \gset ap1_
select public.po_fx_cost_status(:'po0'::uuid) as r \gset s2_
select public.po_fx_cost_apply(:'po0'::uuid, true) as r \gset ap2_
reset role;
select pg_temp.chk('G2 apply: committed · event +25 posted (source fx_fix · source_id PO · number FX PO-79800 <today> 1.4 · amount_doc null) · y1 adds +25 · remaining value 700 · status remaining 0 · fx_fix_cad 25 · second apply: 0 events · applied 0', (:'ap1_r'::jsonb->>'committed') || '/' || (:'ap1_r'::jsonb->>'event_count') || '/' || (select trim_scale(j.amount_cad)::text || '/' || j.status || '/' || j.source_type || '/' || (j.source_id = :'po0'::uuid)::text || '/' || j.source_number || '/' || coalesce(j.amount_doc::text, 'null') from public.inv_cost_adjust j where j.source_type = 'fx_fix' and j.po_line_id = :'l1'::uuid) || '/' || (select trim_scale(sum(a.amount))::text from public.inv_layer_cost_add a where a.layer_id = :'y1'::bigint) || '/' || (select trim_scale(v.remaining_value)::text from public.inv_layer_value(:'y1'::bigint) v) || '/' || trim_scale((:'s2_r'::jsonb->>'total_remaining_cad')::numeric)::text || '/' || (select trim_scale((x->>'fx_fix_cad')::numeric)::text from jsonb_array_elements(:'s2_r'::jsonb->'lines') x where x->>'po_line_id' = :'l1') || '/' || (:'ap2_r'::jsonb->>'event_count') || '/' || trim_scale((:'ap2_r'::jsonb->>'applied_cad')::numeric)::text, 'true/1/25/posted/fx_fix/true/FX PO-79800 ' || public.ims_today()::text || ' 1.4/null/25/700/0/25/0/0');

-- ═══ G3 — 1.40 → 1.35 되돌리고 반영 → 반대 부호 −25 · fx_fix 합 0 · y1 adds 0 · 상태 0 ═══
update public.po set exchange_rate = 1.35 where id = :'po0'::uuid;
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_fx_cost_apply(:'po0'::uuid, true) as r \gset ap3_
select public.po_fx_cost_status(:'po0'::uuid) as r \gset s3_
reset role;
select pg_temp.chk('G3 rate back to 1.35 → apply: event −25 posted · fx_fix events on L1: 2 · sum 0 · y1 adds 0 · status remaining 0', (:'ap3_r'::jsonb->>'event_count') || '/' || trim_scale((:'ap3_r'::jsonb->'events'->0->>'amount_cad')::numeric)::text || '/' || (:'ap3_r'::jsonb->'events'->0->>'status') || '/' || (select count(*)::text || '/' || trim_scale(sum(j.amount_cad))::text from public.inv_cost_adjust j where j.source_type = 'fx_fix' and j.po_line_id = :'l1'::uuid) || '/' || (select trim_scale(sum(a.amount))::text from public.inv_layer_cost_add a where a.layer_id = :'y1'::bigint) || '/' || trim_scale((:'s3_r'::jsonb->>'total_remaining_cad')::numeric)::text, '1/-25/posted/2/0/0/0');

-- ═══ G3b — 판정 399: y5 10@1.35 = 13.5 에 앞선 조정 −13 → 원가 0.5 · 환율 1.35 → 1.00 → 차액 −3.5 → 전체 거부 · 사건 0 ═══
insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref) values (:'y5'::bigint, 'price_adjust', -13, '2026-10-08', 'DISC5B-PRE', 'pre');
update public.po set exchange_rate = 1.00 where id = :'po3'::uuid;
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_fx_cost_status(:'po3'::uuid) as r \gset s5_
select pg_temp.err(format('select public.po_fx_cost_apply(%L::uuid, true)', :'po3')) as ap5 \gset
reset role;
select pg_temp.chk('G3b ruling 399: status remaining −3.5 · apply refused with the layer sentence · fx_fix events for L5 0 · y5 adds still −13 only', trim_scale((:'s5_r'::jsonb->>'total_remaining_cad')::numeric)::text || '/' || (:'ap5' like 'P0001 Cost adjustment FX PO-79803 % is a credit larger than the cost of the goods on layer %')::text || '/' || (select count(*) from public.inv_cost_adjust where source_type = 'fx_fix' and po_line_id = :'l5'::uuid) || '/' || (select trim_scale(sum(a.amount))::text from public.inv_layer_cost_add a where a.layer_id = :'y5'::bigint), '-3.5/true/0/-13');

-- ═══ G4 — 일부 판매(20) · 트랜스퍼(30 · 자식) 뒤 반영(⬜5): 사건 +14 (100 × 2 × 0.05) · 부모 adds +14 · cost_late +2.8 · cost_moved +4.2 · 자식 carried +4.2 ═══
update public.po set exchange_rate = 1.40 where id = :'po1'::uuid;
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_fx_cost_apply(:'po1'::uuid, true) as r \gset ap4_
reset role;
select pg_temp.chk('G4 apply after sale 20 + transfer 30 of 100: event +10 posted (layer qty 100 · pin net 2 · 1.35 → 1.40 = 0.05) · parent adds +10 · cost_late +2 (20/100) · cost_moved +3 (30/100) · child carried +3 (ref layer:<parent>:price_adjust) · parent remaining 280 − (54 + 81 + 2 + 3) = 140 = 50 × 2.80', (:'ap4_r'::jsonb->>'event_count') || '/' || trim_scale((:'ap4_r'::jsonb->'events'->0->>'amount_cad')::numeric)::text || '/' || (:'ap4_r'::jsonb->'events'->0->>'status') || '/' || (select trim_scale(sum(a.amount))::text from public.inv_layer_cost_add a where a.layer_id = :'y3'::bigint) || '/' || (select trim_scale(k.amount)::text from public.inv_layer_consume k where k.layer_id = :'y3'::bigint and k.reason = 'cost_late') || '/' || (select trim_scale(k.amount)::text from public.inv_layer_consume k where k.layer_id = :'y3'::bigint and k.reason = 'cost_moved') || '/' || (select trim_scale(a.amount)::text || ':' || a.kind || ':' || (a.ref_number = 'layer:' || :'y3' || ':price_adjust')::text from public.inv_layer_cost_add a where a.layer_id = :'y3c'::bigint) || '/' || (select trim_scale(v.remaining_value)::text || '/' || trim_scale(v.unit_cost)::text from public.inv_layer_value(:'y3'::bigint) v), '1/10/posted/10/2/3/3:carried:true/140/2.8');

-- ═══ G5 — 기준통화 PO: 상태 is_base · 늘 0 · 반영 skipped base_currency · 사건 0 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_fx_cost_status(:'po2'::uuid) as r \gset s4_
select public.po_fx_cost_apply(:'po2'::uuid, true) as r \gset ap6_
reset role;
select pg_temp.chk('G5 CAD PO: is_base true · fx_now null · lines 1 · remaining 0 · affected false · apply skipped base_currency · events 0', (:'s4_r'::jsonb->>'is_base') || '/' || coalesce(:'s4_r'::jsonb->>'fx_now', 'null') || '/' || jsonb_array_length(:'s4_r'::jsonb->'lines') || '/' || trim_scale((:'s4_r'::jsonb->>'total_remaining_cad')::numeric)::text || '/' || (:'s4_r'::jsonb->>'affected') || '/' || (:'ap6_r'::jsonb->>'skipped') || '/' || (:'ap6_r'::jsonb->>'event_count') || '/' || (select count(*) from public.inv_cost_adjust where source_type = 'fx_fix' and po_line_id = :'l4'::uuid), 'true/null/1/0/false/base_currency/0/0');

-- ═══ H1 — 권한: anon 없음 · 열쇠 없는 직원 거부(읽기 · 반영) · 환율 없는 PO 반영 거부 ═══
set local role anon;
do $$ begin perform public.po_fx_cost_status(gen_random_uuid()); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as an1 \gset
do $$ begin perform public.po_fx_cost_apply(gen_random_uuid(), false); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as an2 \gset
reset role;
set local role authenticated;
select set_config('request.jwt.claims', :'n_claims', true);
do $$ begin perform public.po_fx_cost_status(gen_random_uuid()); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
select current_setting('app.out', true) as nk1 \gset
do $$ begin perform public.po_fx_cost_apply(gen_random_uuid(), true); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
select current_setting('app.out', true) as nk2 \gset
reset role;
update public.po set exchange_rate = null where id = :'po3'::uuid;
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true);
select public.po_fx_cost_status(:'po3'::uuid) as r \gset s6_
select pg_temp.err(format('select public.po_fx_cost_apply(%L::uuid, true)', :'po3')) as ap7 \gset
reset role;
select pg_temp.chk('H1 anon status · apply → 42501 · no-key staff → purchasing sentences (read · saved) · PO without rate: status warning po_exchange_rate_missing · remaining 0 · apply refused', :'an1' || ',' || :'an2' || ',' || (:'nk1' = 'P0001 You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was read')::text || ',' || (:'nk2' = 'P0001 You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was saved')::text || ',' || (:'s6_r'::jsonb->'warnings' ? 'po_exchange_rate_missing')::text || ',' || trim_scale((:'s6_r'::jsonb->>'total_remaining_cad')::numeric)::text || ',' || (:'ap7' like 'P0001 PO PO-79803 has no exchange rate — enter it in the order header first — nothing was saved')::text, '42501,42501,true,true,true,0,true');

-- ═══ H2 — 실물 무변 · 사건 수 = 머리 + 이번 차수(시험 0 · 확인 0 — 이 차수는 실제 사건을 만들지 않는다) · 재생성 +2.73 · deferred 0 ═══
\if :{?mig}
\set ev_new 0
\else
\set ev_new 0
\endif
select md5(string_agg(x.id::text || '|' || x.po_number || '|' || x.status || '|' || coalesce(x.exchange_rate::text, ''), ',' order by x.id)) as real_po_mid from public.po x where x.po_number not like 'PO-798%' \gset
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_mid from public.inv_layer l where l.sku not like 'DISC5B-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by a.id)) as real_adds_mid from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC5B-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text, ',' order by k.id)) as real_consume_mid from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC5B-%' \gset
select pg_temp.chk('H2a real rows unchanged inside the test (POs incl. exchange rates · layers · adds · consume) · real events = head + this round · real pins unchanged', (:'real_po_mid' = :'real_po_head')::text || '/' || (:'real_layers_mid' = :'real_layers_head')::text || '/' || (:'real_adds_mid' = :'real_adds_head')::text || '/' || (:'real_consume_mid' = :'real_consume_head')::text || '/' || (select count(*) from public.inv_cost_adjust j where j.po_line_id not in (select pl.id from public.po_line pl join public.po x on x.id = pl.po_id where x.po_number like 'PO-798%') or j.po_line_id is null) || '/' || (select count(*) from public.po_receipt_cost k join public.po_receipt r on r.id = k.receipt_id where r.receipt_number not like 'RCV-798%'), 'true/true/true/true/' || (:real_events_head + :ev_new)::text || '/' || :real_pins_head);
select round(sum(unit_cost * qty), 4) as val_before from public.inv_layer where sku not like 'DISC5B-%' \gset
select set_config('request.jwt.claims', :'g_claims', true);
select clock_timestamp() as ta0 \gset
select public.inv_layer_apply() as r \gset apply_
select clock_timestamp() as ta1 \gset
select 'timing: inv_layer_apply ms=' || round(extract(epoch from (:'ta1'::timestamptz - :'ta0'::timestamptz)) * 1000);
select round(sum(unit_cost * qty), 4) as val_after from public.inv_layer where sku not like 'DISC5B-%' \gset
select 'H2 regen: value before=' || :val_before || ' after=' || :val_after || ' diff=' || (:val_after - :val_before)::text || ' · adjusts: ' || (:'apply_r'::jsonb->'ims'->'adjusts')::text;
select pg_temp.chk('H2b regen total value diff (real · fakes excluded) = +2.73 · adjusts deferred 0 · skipped 0 · posted = posted count (fake fx_fix events replayed)', round(:val_after - :val_before, 2)::text || '/' || (:'apply_r'::jsonb->'ims'->'adjusts'->>'deferred') || '/' || (:'apply_r'::jsonb->'ims'->'adjusts'->>'skipped') || '/' || ((:'apply_r'::jsonb->'ims'->'adjusts'->>'posted')::int = (select count(*) from public.inv_cost_adjust where status = 'posted'))::text, '2.73/0/0/true');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select md5(string_agg(x.id::text || '|' || x.po_number || '|' || x.status || '|' || coalesce(x.exchange_rate::text, ''), ',' order by x.id)) as real_po_tail, count(*) as real_po_tail_n from public.po x where x.po_number not like 'PO-798%' \gset
select md5(string_agg(coalesce(l.doc_number, '') || '|' || coalesce(l.line_ref, '') || '|' || l.sku || '|' || l.warehouse || '|' || l.qty::text || '|' || l.unit_cost::text, ',' order by l.id)) as real_layers_tail, count(*) as real_layers_tail_n from public.inv_layer l where l.sku not like 'DISC5B-%' \gset
select md5(string_agg(a.layer_id::text || '|' || a.kind || '|' || a.amount::text || '|' || a.occurred_on::text || '|' || a.doc_number || '|' || a.line_ref, ',' order by a.id)) as real_adds_tail, count(*) as real_adds_tail_n from public.inv_layer_cost_add a join public.inv_layer l on l.id = a.layer_id where l.sku not like 'DISC5B-%' \gset
select md5(string_agg(k.layer_id::text || '|' || k.reason || '|' || k.qty::text || '|' || k.amount::text || '|' || k.occurred_on::text, ',' order by k.id)) as real_consume_tail, count(*) as real_consume_tail_n from public.inv_layer_consume k join public.inv_layer l on l.id = k.layer_id where l.sku not like 'DISC5B-%' \gset
select 'REAL_SAME pos ' || (:'real_po_head' = :'real_po_tail')::text || ' (' || :real_po_n || ' → ' || :real_po_tail_n || ') layers ' || (:'real_layers_head' = :'real_layers_tail')::text || ' (' || :real_layers_n || ' → ' || :real_layers_tail_n || ') adds ' || (:'real_adds_head' = :'real_adds_tail')::text || ' (' || :real_adds_n || ' → ' || :real_adds_tail_n || ') consume ' || (:'real_consume_head' = :'real_consume_tail')::text || ' (' || :real_consume_n || ' → ' || :real_consume_tail_n || ')';
select setval('public.inv_layer_cost_add_id_seq', greatest((select max(id) from public.inv_layer_cost_add), :add_seq_last), true);
select setval('public.inv_layer_consume_id_seq', greatest((select max(id) from public.inv_layer_consume), :con_seq_last), true);
select 'seq tail po ' || last_value || ' ' || is_called from public.po_number_seq;
select 'seq tail rcv ' || last_value || ' ' || is_called from public.po_receipt_number_seq;
select 'seq tail cost_add ' || last_value || ' ' || is_called || ' (head ' || :add_seq_last || ' · reset to greatest(max, head))' from public.inv_layer_cost_add_id_seq;
select 'seq tail consume ' || last_value || ' ' || is_called || ' (head ' || :con_seq_last || ' · reset to greatest(max, head))' from public.inv_layer_consume_id_seq;
