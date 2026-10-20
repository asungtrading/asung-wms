-- rcv-1a-verify.sql — 입고 line_ref 꼬리 :pN 을 읽는 쪽(inv_po_line_of · 재발행 9 · 식 인덱스) · 바이트 무변(재생성 전후 실제 행 md5) · 접미어 시나리오(레이어 둘 · 핀 하나 · landed 비례 · FIFO · 재생성 같음)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261020143921_rcv_1a_receipt_line_ref_suffix.sql -f supabase/tests/rcv-1a-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0(옛 창구가 :p1 행에서 선다 · 옛 재생성 md5) · G0 는 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더
--   재료는 가짜만(직원 RCV1A · 공급처 · 제품 RCV1A-P1 · P2 · PO-79400 · 인보이스 RCV1A-I1 · RCV-79400 · 비용 CHG-79400 · 원장 행은 직접 — 실제 창구는 rcv-1b) · 실제 행 무변 = 스냅샷 때 있던 id 집합 · rollback
--   재생성 inv_layer_apply 는 전량(표를 비우고 다시) · 9 ~ 10 초 — 세 번 돈다(옛 · 새 · 판매 뒤) · 신원 = receiving + purchasing 둘 다(claims · postgres)

\echo '── 시퀀스 · db_role · schema_migrations'
select last_value as po_seq_last, is_called as po_seq_called from public.po_number_seq \gset
select last_value as rcv_seq_last, is_called as rcv_seq_called from public.po_receipt_number_seq \gset
select :po_seq_last as po_seq, :'po_seq_called' as po_seq_called, :rcv_seq_last as rcv_seq, (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261020143921' \gset
select :n_applied as schema_migrations_rows_for_20261020143921;

begin;
set local statement_timeout = '600s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return v;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 레이어 내용 지문(id 뺌 · 재생성은 id 를 바꾼다 · carried 얹기 줄의 line_ref · ref_number 안 layer:<id> 도 지운다 — 가짜 입고 3 레이어가 id 를 민다) — 가짜 문서 밖
create function pg_temp.lay_key(p_id bigint) returns text language sql as $$
  select x.doc_number || '|' || x.line_ref || '|' || x.sku || '|' || x.warehouse || '|' || x.origin_type || '|' || x.received_on || '|' || trim_scale(x.qty) || '|' || trim_scale(x.unit_cost) || '|' || x.cost_source from public.inv_layer x where x.id = p_id $$;
create function pg_temp.snap_layers(p_tag text) returns void language plpgsql as $$
begin
  execute format('create temp table t_lay_%s as select pg_temp.lay_key(x.id) as k, coalesce(pg_temp.lay_key(x.parent_layer_id), '''') as parent from public.inv_layer x where x.doc_number not in (''RCV-79400'') and x.doc_number not like ''SO-794%%''', p_tag);
  execute format('create temp table t_add_%s as select a.kind || ''|'' || trim_scale(a.amount) || ''|'' || a.occurred_on || ''|'' || a.doc_number || ''|'' || regexp_replace(a.line_ref, ''layer:[0-9]+:'', ''layer:#:'') || ''|'' || regexp_replace(coalesce(a.ref_number, ''''), ''layer:[0-9]+:'', ''layer:#:'') as k, pg_temp.lay_key(a.layer_id) as lay from public.inv_layer_cost_add a join public.inv_layer x on x.id = a.layer_id where a.doc_number not in (''CHG-79400'') and x.doc_number not in (''RCV-79400'')', p_tag);
end $$;
create function pg_temp.md5_layers() returns text language sql as $$
  select md5(coalesce(string_agg(x.doc_number || '|' || x.line_ref || '|' || x.sku || '|' || x.warehouse || '|' || x.origin_type || '|' || x.received_on || '|' || trim_scale(x.qty) || '|' || trim_scale(x.unit_cost) || '|' || x.cost_source || '|' || coalesce(pg_temp.lay_key(x.parent_layer_id), ''),
                                 ',' order by x.doc_number, x.line_ref, x.sku, x.warehouse, x.origin_type, x.received_on, x.qty, x.unit_cost, x.cost_source, coalesce(pg_temp.lay_key(x.parent_layer_id), '')), ''))
  from public.inv_layer x where x.doc_number not in ('RCV-79400') and x.doc_number not like 'SO-794%' $$;
create function pg_temp.md5_adds() returns text language sql as $$
  select md5(coalesce(string_agg(k, ',' order by k), '')) from (
    select a.kind || '|' || trim_scale(a.amount) || '|' || a.occurred_on || '|' || a.doc_number || '|' || regexp_replace(a.line_ref, 'layer:[0-9]+:', 'layer:#:') || '|' || regexp_replace(coalesce(a.ref_number, ''), 'layer:[0-9]+:', 'layer:#:') || '|' || x.doc_number || '|' || x.line_ref || '|' || x.sku || '|' || x.warehouse as k
    from public.inv_layer_cost_add a join public.inv_layer x on x.id = a.layer_id where a.doc_number not in ('CHG-79400') and x.doc_number not in ('RCV-79400')) s $$;
create function pg_temp.md5_consume() returns text language sql as $$
  select md5(coalesce(string_agg(c.doc_type || '|' || c.doc_number || '|' || c.line_ref || '|' || c.event_type || '|' || c.occurred_on || '|' || trim_scale(c.qty) || '|' || trim_scale(c.unit_cost) || '|' || trim_scale(c.amount) || '|' || c.reason || '|' || x.doc_number || '|' || x.line_ref || '|' || x.sku,
                                 ',' order by c.doc_number, c.line_ref, c.occurred_on, x.doc_number, x.line_ref, x.sku, c.qty, c.amount, c.reason), ''))
  from public.inv_layer_consume c join public.inv_layer x on x.id = c.layer_id where c.doc_number not like 'SO-794%' and x.doc_number not in ('RCV-79400') $$;
create function pg_temp.layers_of(p_doc text) returns text language sql as $$
  select coalesce(string_agg(x.line_ref || ':' || x.sku || ':' || trim_scale(x.qty) || '@' || trim_scale(x.unit_cost) || ':' || x.cost_source, ' | ' order by x.id), '(none)') from public.inv_layer x where x.doc_number = p_doc $$;

\echo '── M0) 직원(receiving + purchasing) · 참조 · 실제 행 스냅샷(id 집합)'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rcv1a-regen@test.invalid', 'RCV1A regen', 'manager', '["ims","receiving","purchasing"]', '{}') returning auth_user_id::text as g_uid \gset
\set g_claims '{"sub":"' :g_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select value as base from public.inv_config where key = 'base_currency' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.name as binname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
create temp table t_real_ledger as select l.id from public.inv_ledger l;
select count(*) as n_real_ledger, md5(coalesce(string_agg(l.id::text || ':' || l.qty_delta || ':' || l.line_ref || ':' || l.doc_number, '|' order by l.id), '')) as md5_real_ledger from public.inv_ledger l join t_real_ledger t on t.id = l.id \gset
select pg_temp.chk(format('M0 regen staff · base %s · warehouse %s · bin %s · %s real ledger rows snapshotted', :'base', :'whname', :'binname', :n_real_ledger),
  :'g_uid' <> '' and :'base' = 'CAD' and :'wh' <> '' and :'binname' <> '' and :n_real_ledger > 0, 'see M0');

\echo '── M1) 가짜 재료 — 공급처 · 제품 둘 · PO-79400(CAD · 줄 둘) · 확정 인보이스 · RCV-79400 confirmed · 원장 행 셋(l1:p1 100 · l1 500 · l2 50 · 같은 날 · 같은 빈) · 비용 65 CAD 배분'
set local session_replication_role = replica;
insert into public.supplier (name, payment_term_name, account_payable_code) values ('RCV1A Supplier', 'Net 30', '2000') returning id::text as sup \gset
insert into public.product (sku, name, source) values ('RCV1A-P1', 'RCV1A P1', 'manual') returning id::text as p1 \gset
insert into public.product (sku, name, source) values ('RCV1A-P2', 'RCV1A P2', 'manual') returning id::text as p2 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79400', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, '2031-02-01', :'wh'::uuid, now()) returning id::text as po \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po'::uuid, 1, :'p1'::uuid, 600, 2.00) returning id::text as l1 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po'::uuid, 2, :'p2'::uuid, 50, 4.00) returning id::text as l2 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'RCV1A-I1', '2031-02-01', :'cad'::uuid, null, 0, 'confirmed', 'invoice', now()) returning id::text as i1 \gset
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (:'i1'::uuid, 1, 'goods', :'l1'::uuid, 600, 2.50, true), (:'i1'::uuid, 2, 'goods', :'l2'::uuid, 50, 4.00, true);
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, confirmed_at) values ('RCV-79400', :'po'::uuid, :'wh'::uuid, '2031-02-01', 'confirmed', now()) returning id::text as r1 \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, source, raw) values
  ('2031-02-01', 1, 'RCV1A-P1', :'whname', :'binname', 100, 'po_in', 'purchase', 'RCV-79400', :'r1', :'l1' || ':p1', 'ims', '{"fake":"rcv-1a","batch":1}'),
  ('2031-02-01', 1, 'RCV1A-P1', :'whname', :'binname', 500, 'po_in', 'purchase', 'RCV-79400', :'r1', :'l1',          'ims', '{"fake":"rcv-1a","final":true}'),
  ('2031-02-01', 1, 'RCV1A-P2', :'whname', :'binname', 50,  'po_in', 'purchase', 'RCV-79400', :'r1', :'l2',          'ims', '{"fake":"rcv-1a","final":true}');
insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, status, confirmed_at) values (:'sup'::uuid, 'CHG-79400', '2031-02-03', 'freight', :'cad'::uuid, 65, 'confirmed', now()) returning id::text as c1 \gset
insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (:'c1'::uuid, :'po'::uuid, 65) returning id::text as al1 \gset
set local session_replication_role = origin;
select pg_temp.chk('M1 fixtures: PO-79400 (2 lines) · invoice RCV1A-I1 confirmed (2.50 · 4.00) · RCV-79400 confirmed · 3 ledger rows (l1:p1 100 · l1 500 · l2 50) · charge 65 allocated',
  (select count(*) from public.inv_ledger where doc_number = 'RCV-79400') = 3 and (select count(*) from public.inv_ledger where doc_number = 'RCV-79400' and line_ref = :'l1' || ':p1') = 1
  and (select count(*) from public.po_invoice_line il where il.po_invoice_id = :'i1'::uuid) = 2 and :'al1' <> '', 'see M1');

select set_config('request.jwt.claims', :'g_claims', true) as claims;
\if :{?mig}
\echo '── S0) 옛 창구 · 옛 재생성 — :p1 행에서 선다(결함 재현) · 실제 행 레이어 · 얹기 · 소진 md5 를 옛 함수로 찍어 둔다'
select pg_temp.run(format('select public.inv_layer_post_receipt(%L::uuid)::text', :'r1')) as s0 \gset
select clock_timestamp()::text as ta0 \gset
select public.inv_layer_apply()::text as apply_old \gset
select clock_timestamp()::text as ta1 \gset
select pg_temp.md5_layers() as m_layers_old, pg_temp.md5_adds() as m_adds_old, pg_temp.md5_consume() as m_cons_old \gset
select pg_temp.snap_layers('old');
select (select count(*) from public.inv_layer where doc_number = 'RCV-79400') as n_fake_old \gset
select pg_temp.chk('S0 (old · trial only) inv_layer_post_receipt on the :p1 row → "points at a PO line … that does not exist" · old regeneration skips RCV-79400 (ims.receipts_skipped ≥ 1 · 0 fake layers) · real-row md5 captured',
  :'s0' like 'ERR %points at a PO line%that does not exist%' and (pg_temp.j(:'apply_old')->'ims'->>'receipts_skipped')::int >= 1 and :n_fake_old = 0 and :'m_layers_old' <> '',
  format('%s | skipped %s · fake layers %s · apply %s ms', left(:'s0', 160), pg_temp.j(:'apply_old')->'ims'->>'receipts_skipped', :n_fake_old, round(extract(epoch from (:'ta1'::timestamptz - :'ta0'::timestamptz)) * 1000)));
select pg_temp.chk('G0 before the trial: no inv_po_line_of · no inv_layer_po_line_idx · inv_layer_post_charge still joins pl.id::text = x.line_ref · not in schema_migrations',
  to_regprocedure('public.inv_po_line_of(text)') is null and not exists (select 1 from pg_indexes where indexname = 'inv_layer_po_line_idx')
  and (select prosrc from pg_proc where oid = 'public.inv_layer_post_charge(uuid, date, uuid)'::regprocedure) ~ 'pl\.id::text = x\.line_ref' and :n_applied = 0, format('n_applied %s', :n_applied));
\echo '── \i 시험 적용'
\i :mig
\else
select pg_temp.chk('P0c confirm run: migration 20261020143921 applied', :n_applied = 1, format('%s rows', :n_applied));
select clock_timestamp()::text as ta0 \gset
select public.inv_layer_apply()::text as apply_old \gset
select clock_timestamp()::text as ta1 \gset
delete from public.inv_layer_cost_add a using public.inv_layer x where x.id = a.layer_id and x.doc_number = 'RCV-79400';   -- 확인 갈래: 새 함수가 이미 만든 가짜 레이어는 S1 이 다시 만들게 치운다(실제 행은 그대로 · rollback)
delete from public.inv_layer where doc_number = 'RCV-79400';
select pg_temp.md5_layers() as m_layers_old, pg_temp.md5_adds() as m_adds_old, pg_temp.md5_consume() as m_cons_old \gset
select pg_temp.snap_layers('old');
\endif
delete from public.po_receipt_cost where receipt_id = :'r1'::uuid;   -- 두 갈래 공통: 확인 갈래의 옛 md5 재생성이 만든 가짜 핀을 치운다(S1 이 다시 만든다 · 시험 갈래는 0 행 · 재생성은 핀을 안 지운다)

\echo '── G1) 실물'
select pg_temp.chk('G1 inv_po_line_of (immutable · abc:p1 → abc · abc → abc · abc:p2:offpo → abc) · inv_layer_po_line_idx (partial purchase) · 9 bodies call it · no old compare left · ims_rcv key still per receipt',
  (select p.provolatile = 'i' from pg_proc p where p.oid = to_regprocedure('public.inv_po_line_of(text)'))
  and pg_temp.run('select public.inv_po_line_of(''abc:p1'')') = 'abc' and pg_temp.run('select public.inv_po_line_of(''abc'')') = 'abc' and pg_temp.run('select public.inv_po_line_of(''abc:p2:offpo'')') = 'abc'
  and (select indexdef from pg_indexes where indexname = 'inv_layer_po_line_idx') like '%WHERE (origin_type = ''purchase''%'
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_post_receipt', 'inv_layer_post_charge', 'inv_layer_post_cost_adjust', 'inv_layer_apply', 'inv_layer_apply_flush_adds', 'po_fx_cost_lines', 'po_credit_cost_events', 'inv_layer_post_receipt_over', 'inv_post_receipt_over') and p.prosrc ~ 'inv_po_line_of\(') = 9
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_post_receipt', 'inv_layer_post_charge', 'inv_layer_post_cost_adjust', 'inv_layer_apply', 'inv_layer_apply_flush_adds', 'po_fx_cost_lines', 'po_credit_cost_events', 'inv_layer_post_receipt_over', 'inv_post_receipt_over')
          and (p.prosrc ~ 'pl\.id::text = x\.line_ref' or p.prosrc ~ 'x\.line_ref = pl\.id::text' or p.prosrc ~ 'y\.line_ref = pl\.id::text' or p.prosrc ~ 'x\.line_ref::uuid' or p.prosrc ~ 'y\.line_ref = k\.po_line_id::text' or p.prosrc ~ 'y\.line_ref = v_d\.po_line_id::text' or p.prosrc ~ 'x\.line_ref = v_d\.po_line_id::text')) = 0
  and (select prosrc from pg_proc where oid = 'public.inv_layer_apply(date)'::regprocedure) ~ 'kind = ''ims_rcv''', 'see G1');

\echo '── S1) 새 창구: 레이어 셋(l1:p1 100 · l1 500 · l2 50) · 핀 둘(l1 · l2) · 단가 = 인보이스(2.50 · 4.00) · :p1 이 먼저(원장 순서) · 둘째 묶음은 핀을 읽는다'
select pg_temp.run(format('select public.inv_layer_post_receipt(%L::uuid)::text', :'r1')) as s1 \gset
select pg_temp.layers_of('RCV-79400') as lay1 \gset
select pg_temp.chk('S1 layers_created 3 · existing 0 · l1:p1 100 @2.5 first · l1 500 @2.5 · l2 50 @4 · pins 2 (l1 invoice · l2 invoice) · lines[0] basis invoice · lines[1] basis pinned · cost_total 1700',
  :'s1' not like 'ERR%' and (pg_temp.j(:'s1')->>'layers_created')::int = 3 and (pg_temp.j(:'s1')->>'layers_existing')::int = 0
  and :'lay1' = :'l1' || ':p1:RCV1A-P1:100@2.5:po_line | ' || :'l1' || ':RCV1A-P1:500@2.5:po_line | ' || :'l2' || ':RCV1A-P2:50@4:po_line'
  and (select count(*) from public.po_receipt_cost k where k.receipt_id = :'r1'::uuid) = 2 and (select bool_and(k.source = 'invoice') from public.po_receipt_cost k where k.receipt_id = :'r1'::uuid)
  and (pg_temp.j(:'s1')->'lines'->0->>'cost_basis') = 'invoice' and (pg_temp.j(:'s1')->'lines'->1->>'cost_basis') = 'pinned' and (pg_temp.j(:'s1')->'lines'->0->>'po_line_id') = :'l1' || ':p1'
  and (pg_temp.j(:'s1')->>'cost_total_cad')::numeric = 1700,
  format('%s | %s', :'lay1', left(:'s1', 400)));

\echo '── S2) landed 65 → 세 레이어에 금액 비례(250 · 1250 · 200 / 1700) · 끝수는 마지막 레이어 · 합 65'
select pg_temp.run(format('select public.inv_layer_post_charge(%L::uuid)::text', :'c1')) as s2 \gset
select coalesce(string_agg(x.line_ref || '=' || trim_scale(a.amount), ' | ' order by x.id), '(none)') as adds2, coalesce(sum(a.amount), 0)::text as sum2 from public.inv_layer_cost_add a join public.inv_layer x on x.id = a.layer_id where a.doc_number = 'CHG-79400' \gset
select pg_temp.chk('S2 landed: layers_touched 3 · posted 65 · :p1 share 9.558824 · final 47.794118 · l2 7.647058 (remainder) · sum 65 · no_layers 0',
  :'s2' not like 'ERR%' and (pg_temp.j(:'s2')->>'layers_touched')::int = 3 and (pg_temp.j(:'s2')->>'amount_posted_cad')::numeric = 65 and (pg_temp.j(:'s2')->>'no_layers_allocs')::int = 0
  and :'adds2' = :'l1' || ':p1=9.558824 | ' || :'l1' || '=47.794118 | ' || :'l2' || '=7.647058' and :'sum2'::numeric = 65,
  format('%s | %s', :'adds2', left(:'s2', 300)));

\echo '── S3) 판매 150 (다음 날) → 재생성: 레이어 셋 같음 · 소진 = :p1 100 먼저 + 마지막 50 · landed 같음 · 실제 행 md5 전후 같음(바이트 무변) · 건너뛴 입고 0'
set local session_replication_role = replica;
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, source, raw) values
  ('2031-02-02', 2, 'RCV1A-P1', :'whname', :'binname', -150, 'sale_out', 'sale', 'SO-79400', null, 'rcv1a-sale:1', 'ims', '{"fake":"rcv-1a"}');
set local session_replication_role = origin;
select clock_timestamp()::text as tb0 \gset
select public.inv_layer_apply()::text as apply_new \gset
select clock_timestamp()::text as tb1 \gset
select pg_temp.layers_of('RCV-79400') as lay3 \gset
select coalesce(string_agg(x.line_ref || '=' || trim_scale(a.amount), ' | ' order by x.id), '(none)') as adds3 from public.inv_layer_cost_add a join public.inv_layer x on x.id = a.layer_id where a.doc_number = 'CHG-79400' \gset
select coalesce(string_agg(x.line_ref || ':' || trim_scale(c.qty) || '@' || trim_scale(c.unit_cost), ' | ' order by x.id), '(none)') as cons3 from public.inv_layer_consume c join public.inv_layer x on x.id = c.layer_id where c.doc_number = 'SO-79400' \gset
select pg_temp.md5_layers() as m_layers_new, pg_temp.md5_adds() as m_adds_new, pg_temp.md5_consume() as m_cons_new \gset
select pg_temp.snap_layers('new');
select coalesce((select string_agg(d, ' ;; ') from (select 'old-only ' || k || ' ^' || parent as d from (select k, parent from t_lay_old except select k, parent from t_lay_new) a union all select 'new-only ' || k || ' ^' || parent from (select k, parent from t_lay_new except select k, parent from t_lay_old) b limit 4) z), '(none)') as lay_diff \gset
select coalesce((select string_agg(d, ' ;; ') from (select 'old-only ' || k || ' @' || lay as d from (select k, lay from t_add_old except select k, lay from t_add_new) a union all select 'new-only ' || k || ' @' || lay from (select k, lay from t_add_new except select k, lay from t_add_old) b limit 4) z), '(none)') as add_diff \gset
select pg_temp.chk('S3 regeneration: same 3 layers (same order · :p1 first) · landed shares identical · sale 150 consumed 100 from :p1 then 50 from the final layer @2.595588 (2.5 + landed per unit · equal on both) · RCV-79400 not skipped · real layers · adds · consumes md5 unchanged vs the old regeneration (byte-for-byte on real rows)',
  :'lay3' = :'lay1' and :'adds3' = :'adds2'
  and :'cons3' = :'l1' || ':p1:100@2.595588 | ' || :'l1' || ':50@2.595588'
  and (pg_temp.j(:'apply_new')->'ims'->>'receipts_skipped')::int = 0
  and :'m_layers_new' = :'m_layers_old' and :'m_adds_new' = :'m_adds_old' and :'m_cons_new' = :'m_cons_old',
  format('layers %s | adds %s | cons %s | skipped %s · apply %s ms | md5 layers %s adds %s cons %s | lay_diff %s | add_diff %s', :'lay3', :'adds3', :'cons3', pg_temp.j(:'apply_new')->'ims'->>'receipts_skipped', round(extract(epoch from (:'tb1'::timestamptz - :'tb0'::timestamptz)) * 1000), :'m_layers_new' = :'m_layers_old', :'m_adds_new' = :'m_adds_old', :'m_cons_new' = :'m_cons_old', left(:'lay_diff', 600), left(:'add_diff', 600)));

\echo '── S4) 식 인덱스가 쓰인다(explain) · 꼬리 조건은 그대로(:offpo 행은 입고 창구가 안 읽는다)'
create function pg_temp.plan(p_sql text) returns text language plpgsql as $$
declare r record; v text := '';
begin
  for r in execute 'explain (costs off) ' || p_sql loop v := v || r."QUERY PLAN" || ' '; end loop;
  return v;
end $$;
select pg_temp.run(format('select pg_temp.plan(%L)', format('select count(*) from public.inv_layer x join public.po_line pl on pl.id::text = public.inv_po_line_of(x.line_ref) where x.origin_type = ''purchase'' and x.cost_source = ''po_line'' and pl.po_id = %L::uuid', :'po'))) as plan4 \gset
select pg_temp.chk('S4 explain uses inv_layer_po_line_idx · inv_layer_post_receipt still skips :offpo / :over rows (regex intact)',
  :'plan4' like '%inv_layer_po_line_idx%' and (select prosrc from pg_proc where oid = 'public.inv_layer_post_receipt(uuid)'::regprocedure) ~ 'line_ref not like ''%:over'' and l\.line_ref not like ''%:offpo''', left(:'plan4', 300));

\echo '── Z1) 실제 원장 무접촉(스냅샷 id 집합)'
select pg_temp.chk(format('Z1 %s real ledger rows untouched (qty · line_ref · doc)', :n_real_ledger),
  (select md5(coalesce(string_agg(l.id::text || ':' || l.qty_delta || ':' || l.line_ref || ':' || l.doc_number, '|' order by l.id), '')) from public.inv_ledger l join t_real_ledger t on t.id = l.id) = :'md5_real_ledger', 'see Z1');

rollback;
\echo '── rollback 뒤 — 시퀀스 무접촉(직접 insert · 가짜 번호) · 가짜 흔적 0'
select (select last_value from public.po_number_seq) as po_seq_now, :po_seq_last as po_seq_head, (select last_value from public.po_receipt_number_seq) as rcv_seq_now, :rcv_seq_last as rcv_seq_head,
       (select count(*) from public.po where po_number = 'PO-79400') + (select count(*) from public.inv_ledger where doc_number in ('RCV-79400', 'SO-79400')) + (select count(*) from public.ims_staff where email like 'rcv1a-%') + (select count(*) from public.product where sku like 'RCV1A-%') as fake_traces_left;
