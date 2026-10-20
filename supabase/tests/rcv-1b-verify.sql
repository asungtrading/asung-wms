-- rcv-1b-verify.sql — 입고 「먼저 반영」: 묶음 표 · 창구 po_receipt_post_now(미리 보기 · 반영) · 원장 :pN · 레이어 · 핀 재사용 · 비용 미루기(판정 553) · 마지막 확정(남은 몫 · short 한 번 · 미룬 비용 · cost_late) · 가드 ⑤ · 거부 넷 · 권한 · 재생성 같음 · 옛 흐름 무변
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261020153535_rcv_1b_post_now.sql -f supabase/tests/rcv-1b-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0(옛 재생성 md5 · 옛 모양) · G0 는 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더
--   재료는 가짜만(직원 둘 · 공급처 · 제품 RCV1B-P1 · P2 · PO-79500/79501/79502 · 인보이스 RCV1B-I1 ~ I4 · RCV-79500/79501/79502 draft · CHG-79500 draft) · 실제 행 무변 = 스냅샷 때 있던 id 집합 · rollback
--   재생성 inv_layer_apply 는 전량 · 약 36 초 — 세 번(옛 · 판매 뒤 · 끝) · 신원 = receiving + purchasing(claims · postgres)
--   ⚠️ rcv-1a 함정: 확인 갈래가 옛 md5 를 찍으려 재생성을 먼저 돌리면 가짜 핀이 남는다 — 두 갈래 공통 치우기(여기서는 가짜 입고에 원장이 아직 없어 0 행)

\echo '── 시퀀스 · db_role · schema_migrations'
select last_value as po_seq_last, is_called as po_seq_called from public.po_number_seq \gset
select last_value as rcv_seq_last, is_called as rcv_seq_called from public.po_receipt_number_seq \gset
select :po_seq_last as po_seq, :'po_seq_called' as po_seq_called, :rcv_seq_last as rcv_seq, (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261020153535' \gset
select :n_applied as schema_migrations_rows_for_20261020153535;

begin;
set local statement_timeout = '900s';

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
create function pg_temp.lay_key(p_id bigint) returns text language sql as $$
  select x.doc_number || '|' || x.line_ref || '|' || x.sku || '|' || x.warehouse || '|' || x.origin_type || '|' || x.received_on || '|' || trim_scale(x.qty) || '|' || trim_scale(x.unit_cost) || '|' || x.cost_source from public.inv_layer x where x.id = p_id $$;
create function pg_temp.snap_layers(p_tag text) returns void language plpgsql as $$
begin
  execute format('create temp table t_lay_%s as select pg_temp.lay_key(x.id) as k, coalesce(pg_temp.lay_key(x.parent_layer_id), '''') as parent from public.inv_layer x where x.doc_number not like ''RCV-795%%'' and x.doc_number not like ''SO-795%%''', p_tag);
  execute format('create temp table t_add_%s as select a.kind || ''|'' || trim_scale(a.amount) || ''|'' || a.occurred_on || ''|'' || a.doc_number || ''|'' || regexp_replace(a.line_ref, ''layer:[0-9]+:'', ''layer:#:'') || ''|'' || regexp_replace(coalesce(a.ref_number, ''''), ''layer:[0-9]+:'', ''layer:#:'') as k, pg_temp.lay_key(a.layer_id) as lay from public.inv_layer_cost_add a join public.inv_layer x on x.id = a.layer_id where a.doc_number not like ''CHG-795%%'' and x.doc_number not like ''RCV-795%%''', p_tag);
end $$;
create function pg_temp.md5_layers() returns text language sql as $$
  select md5(coalesce(string_agg(k, ',' order by k), '')) from (
    select x.doc_number || '|' || x.line_ref || '|' || x.sku || '|' || x.warehouse || '|' || x.origin_type || '|' || x.received_on || '|' || trim_scale(x.qty) || '|' || trim_scale(x.unit_cost) || '|' || x.cost_source || '|' || coalesce(pg_temp.lay_key(x.parent_layer_id), '') as k
    from public.inv_layer x where x.doc_number not like 'RCV-795%' and x.doc_number not like 'SO-795%') s $$;
create function pg_temp.md5_adds() returns text language sql as $$
  select md5(coalesce(string_agg(k, ',' order by k), '')) from (
    select a.kind || '|' || trim_scale(a.amount) || '|' || a.occurred_on || '|' || a.doc_number || '|' || regexp_replace(a.line_ref, 'layer:[0-9]+:', 'layer:#:') || '|' || regexp_replace(coalesce(a.ref_number, ''), 'layer:[0-9]+:', 'layer:#:') || '|' || x.doc_number || '|' || x.line_ref || '|' || x.sku || '|' || x.warehouse as k
    from public.inv_layer_cost_add a join public.inv_layer x on x.id = a.layer_id where a.doc_number not like 'CHG-795%' and x.doc_number not like 'RCV-795%') s $$;
create function pg_temp.md5_consume() returns text language sql as $$
  select md5(coalesce(string_agg(k, ',' order by k), '')) from (
    select c.doc_type || '|' || c.doc_number || '|' || c.line_ref || '|' || c.event_type || '|' || c.occurred_on || '|' || trim_scale(c.qty) || '|' || trim_scale(c.unit_cost) || '|' || trim_scale(c.amount) || '|' || c.reason || '|' || x.doc_number || '|' || x.line_ref || '|' || x.sku as k
    from public.inv_layer_consume c join public.inv_layer x on x.id = c.layer_id where c.doc_number not like 'SO-795%' and x.doc_number not like 'RCV-795%') s $$;
create function pg_temp.layers_of(p_doc text) returns text language sql as $$
  select coalesce(string_agg(x.line_ref || ':' || x.sku || ':' || trim_scale(x.qty) || '@' || trim_scale(x.unit_cost) || ':' || x.cost_source, ' | ' order by x.id), '(none)') from public.inv_layer x where x.doc_number = p_doc $$;
create function pg_temp.ledger_of(p_doc text) returns text language sql as $$
  select coalesce(string_agg(l.line_ref || ':' || l.bin || ':' || trim_scale(l.qty_delta) || '@' || l.occurred_on, ' | ' order by l.id), '(none)') from public.inv_ledger l where l.doc_number = p_doc $$;
create function pg_temp.adds_of(p_doc text) returns text language sql as $$
  select coalesce(string_agg(x.doc_number || '/' || x.line_ref || '=' || trim_scale(a.amount) || '@' || a.occurred_on, ' | ' order by x.doc_number, x.line_ref), '(none)') from public.inv_layer_cost_add a join public.inv_layer x on x.id = a.layer_id where a.doc_number = p_doc $$;
create function pg_temp.cons_of(p_doc text) returns text language sql as $$
  select coalesce(string_agg(x.doc_number || '/' || x.line_ref || ':' || c.reason || ':' || trim_scale(c.qty) || '=' || trim_scale(c.amount), ' | ' order by x.doc_number, x.line_ref, c.reason), '(none)') from public.inv_layer_consume c join public.inv_layer x on x.id = c.layer_id where c.doc_number = p_doc or (c.reason = 'cost_late' and x.doc_number like 'RCV-795%') $$;

\echo '── M0) 직원 둘(office: receiving + purchasing · noperm: ims 만) · 참조 · 빈 셋 · 실제 행 스냅샷(id 집합)'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rcv1b-office@test.invalid', 'RCV1B office', 'manager', '["ims","receiving","purchasing"]', '{}') returning auth_user_id::text as g_uid, id::text as st \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rcv1b-noperm@test.invalid', 'RCV1B noperm', 'worker', '["ims"]', '{}') returning auth_user_id::text as g_uid2 \gset
\set g_claims '{"sub":"' :g_uid '","role":"authenticated"}'
\set g_claims2 '{"sub":"' :g_uid2 '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
-- 입고일(오늘−2) · 판매일(오늘−1 · 그 사이) · 바꾼 날짜(오늘+4) — 실시간 순서(입고 → 판매 → 마지막 확정 · 비용 오늘)를 재생성이 같은 순서로 밟게 과거 날짜(미래 날짜면 posted_on 이 원장보다 앞서 순서가 뒤집힌다 · r1) · ⚠️ \gset 줄 끝에 주석을 두면 인자로 읽힌다
select (public.ims_today() - 2)::text as d0, (public.ims_today() - 1)::text as d1, (public.ims_today() + 4)::text as d4 \gset
select value as base from public.inv_config where key = 'base_currency' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.id::text as bina, b.name as binaname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select b.id::text as binb, b.name as binbname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 offset 1 \gset
select b.id::text as binc, b.name as bincname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 offset 2 \gset
create temp table t_real_ledger as select l.id from public.inv_ledger l;
select count(*) as n_real_ledger, md5(coalesce(string_agg(l.id::text || ':' || l.qty_delta || ':' || l.line_ref || ':' || l.doc_number, '|' order by l.id), '')) as md5_real_ledger from public.inv_ledger l join t_real_ledger t on t.id = l.id \gset
select pg_temp.chk(format('M0 staff ×2 · base %s · warehouse %s · bins %s %s %s · %s real ledger rows snapshotted', :'base', :'whname', :'binaname', :'binbname', :'bincname', :n_real_ledger),
  :'g_uid' <> '' and :'g_uid2' <> '' and :'base' = 'CAD' and :'wh' <> '' and :'bina' <> '' and :'binb' <> '' and :'binc' <> '' and :'bina' <> :'binb' and :n_real_ledger > 0, 'see M0');

\echo '── M1) 가짜 재료 — 공급처 · 제품 둘 · PO-79500/79501(P1 600 @2.00 · 인보이스 600 @2.50) · PO-79502(P2 50 @4.00) · 입고 셋 draft(오늘−2) · CHG-79500 65 CAD draft · 초안 인보이스 I4(PO-79500)'
set local session_replication_role = replica;
insert into public.supplier (name, payment_term_name, account_payable_code) values ('RCV1B Supplier', 'Net 30', '2000') returning id::text as sup \gset
insert into public.product (sku, name, source) values ('RCV1B-P1', 'RCV1B P1', 'manual') returning id::text as p1 \gset
insert into public.product (sku, name, source) values ('RCV1B-P2', 'RCV1B P2', 'manual') returning id::text as p2 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79500', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, :'d0', :'wh'::uuid, now()) returning id::text as po1 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79501', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, :'d0', :'wh'::uuid, now()) returning id::text as po2 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79502', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, :'d0', :'wh'::uuid, now()) returning id::text as po3 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po1'::uuid, 1, :'p1'::uuid, 600, 2.00) returning id::text as l1 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po2'::uuid, 1, :'p1'::uuid, 600, 2.00) returning id::text as l2 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po3'::uuid, 1, :'p2'::uuid, 50, 4.00) returning id::text as l3 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'RCV1B-I1', :'d0', :'cad'::uuid, null, 1500, 'confirmed', 'invoice', now()) returning id::text as i1 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'RCV1B-I2', :'d0', :'cad'::uuid, null, 1500, 'confirmed', 'invoice', now()) returning id::text as i2 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'RCV1B-I3', :'d0', :'cad'::uuid, null, 200, 'confirmed', 'invoice', now()) returning id::text as i3 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind) values (:'sup'::uuid, 'RCV1B-I4', :'d1', :'cad'::uuid, null, 25, 'draft', 'invoice') returning id::text as i4 \gset
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values
  (:'i1'::uuid, 1, 'goods', :'l1'::uuid, 600, 2.50, true), (:'i2'::uuid, 1, 'goods', :'l2'::uuid, 600, 2.50, true), (:'i3'::uuid, 1, 'goods', :'l3'::uuid, 50, 4.00, true), (:'i4'::uuid, 1, 'goods', :'l1'::uuid, 10, 2.50, true);
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by) values ('RCV-79500', :'po1'::uuid, :'wh'::uuid, :'d0'::date, 'draft', :'st'::uuid) returning id::text as r1 \gset
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by) values ('RCV-79501', :'po2'::uuid, :'wh'::uuid, :'d0'::date, 'draft', :'st'::uuid) returning id::text as r2 \gset
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by) values ('RCV-79502', :'po3'::uuid, :'wh'::uuid, :'d0'::date, 'draft', :'st'::uuid) returning id::text as r3 \gset
insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, status) values (:'sup'::uuid, 'CHG-79500', :'d1'::date, 'freight', :'cad'::uuid, 65, 'draft') returning id::text as c1 \gset
insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (:'c1'::uuid, :'po1'::uuid, 65) returning id::text as al1 \gset
set local session_replication_role = origin;
select pg_temp.chk('M1 fixtures: 3 POs confirmed · 3 confirmed invoices + 1 draft (I4 on PO-79500) · 3 draft receipts · CHG-79500 draft allocated 65',
  (select count(*) from public.po where po_number like 'PO-795%' and status = 'confirmed') = 3 and (select count(*) from public.po_receipt where receipt_number like 'RCV-795%' and status = 'draft') = 3
  and (select count(*) from public.po_invoice where invoice_number like 'RCV1B-I%' and status = 'confirmed') = 3 and :'al1' <> '' and :'i4' <> '', 'see M1');

select set_config('request.jwt.claims', :'g_claims', true) as claims;
\if :{?mig}
\echo '── S0) 옛 모양 · 옛 재생성 — 실제 행 레이어 · 얹기 · 소진 md5 를 옛 함수로 찍어 둔다'
select clock_timestamp()::text as ta0 \gset
select public.inv_layer_apply()::text as apply_old \gset
select clock_timestamp()::text as ta1 \gset
select pg_temp.md5_layers() as m_layers_old, pg_temp.md5_adds() as m_adds_old, pg_temp.md5_consume() as m_cons_old \gset
select pg_temp.snap_layers('old');
select pg_temp.chk('S0 (old · trial only) old regeneration ran · real-row md5 captured',
  pg_temp.j(:'apply_old') is not null and :'m_layers_old' <> '', format('apply %s ms', round(extract(epoch from (:'ta1'::timestamptz - :'ta0'::timestamptz)) * 1000)));
select pg_temp.chk('G0 before the trial: no po_receipt_post · inv_post_receipt(uuid) one-arg · no post_now · work rows have no post_id · not in schema_migrations',
  to_regclass('public.po_receipt_post') is null and to_regprocedure('public.inv_post_receipt(uuid)') is not null and to_regprocedure('public.po_receipt_post_now(uuid, jsonb, boolean)') is null
  and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'po_receipt_work' and column_name = 'post_id') and :n_applied = 0, format('n_applied %s', :n_applied));
\echo '── \i 시험 적용'
\i :mig
\else
select pg_temp.chk('P0c confirm run: migration 20261020153535 applied', :n_applied = 1, format('%s rows', :n_applied));
select clock_timestamp()::text as ta0 \gset
select public.inv_layer_apply()::text as apply_old \gset
select clock_timestamp()::text as ta1 \gset
select pg_temp.md5_layers() as m_layers_old, pg_temp.md5_adds() as m_adds_old, pg_temp.md5_consume() as m_cons_old \gset
select pg_temp.snap_layers('old');
\endif
delete from public.po_receipt_cost where receipt_id in (:'r1'::uuid, :'r2'::uuid, :'r3'::uuid);   -- 두 갈래 공통(rcv-1a 함정 · 여기서는 0 행 — 가짜 입고에 아직 원장이 없다)

\echo '── G1) 실물 — 표 · 칸 · 유니크 · 함수 · 재발행 13 · 가드 6 · ACL'
select pg_temp.chk('G1 po_receipt_post · work.post_id/post_key · line.post_id · unique (receipt, line, bin, post_key) · inv_post_receipt(uuid, uuid) only · post_now + _by · 13 bodies carry rcv-1b · 6 guards · _by and inv_post_receipt revoked from authenticated',
  to_regclass('public.po_receipt_post') is not null
  and (select count(*) from information_schema.columns where table_schema = 'public' and ((table_name = 'po_receipt_work' and column_name in ('post_id', 'post_key')) or (table_name = 'po_receipt_line' and column_name = 'post_id'))) = 3
  and exists (select 1 from pg_constraint where conname = 'po_receipt_work_receipt_line_bin_post_key') and not exists (select 1 from pg_constraint where conname = 'po_receipt_work_receipt_line_bin_key')
  and to_regprocedure('public.inv_post_receipt(uuid)') is null and to_regprocedure('public.inv_post_receipt(uuid, uuid)') is not null
  and to_regprocedure('public.po_receipt_post_now(uuid, jsonb, boolean)') is not null and to_regprocedure('public.po_receipt_post_now_by(uuid, uuid, jsonb, boolean)') is not null
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc ~ 'rcv-1b' and p.proname in ('inv_layer_post_receipt', 'inv_post_receipt', 'po_receipt_confirm_by', 'inv_layer_post_charge', 'po_charge_confirm', 'po_receipt_over_bins', 'po_receipt_detail', 'po_receipt_work_save_by', 'po_receipt_work_putaway_by', 'po_receipt_work_putaway_all_by', 'po_receipt_work_split', 'po_receipt_work_unassign', 'po_receipt_work_delete')) = 13
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc ~ 'already in stock from post-now' and p.proname in ('po_receipt_work_save_by', 'po_receipt_work_putaway_by', 'po_receipt_work_split', 'po_receipt_work_unassign', 'po_receipt_work_delete', 'po_receipt_confirm_by')) = 6
  and coalesce((select proacl::text from pg_proc where proname = 'po_receipt_post_now_by' and pronamespace = 'public'::regnamespace), '') !~ 'authenticated'
  and coalesce((select proacl::text from pg_proc where proname = 'inv_post_receipt' and pronamespace = 'public'::regnamespace), '') !~ 'authenticated'
  and coalesce((select proacl::text from pg_proc where proname = 'po_receipt_post_now' and pronamespace = 'public'::regnamespace), '') ~ 'authenticated', 'see G1');

select (to_regclass('public.po_receipt_post') is not null and to_regprocedure('public.po_receipt_post_now(uuid, jsonb, boolean)') is not null) as landed \gset
\if :landed
\echo '── S1) RCV-79500: 600 셈 → 100 을 칸 A 로 쪼갬 → 미리 보기(쓰기 0 · 단가 근거 invoice · 가용 +100) → 반영 → 원장 :p1 100 · 레이어 · 핀 · 가용 +100 · PO confirmed · 입고 draft · 차이 0'
select pg_temp.run(format('select public.po_receipt_work_save_by(%L::uuid, %L::uuid, %L::uuid, 600, ''manual'')::text', :'st', :'r1', :'l1')) as sv1 \gset
select coalesce(pg_temp.j(:'sv1')->>'work_id', '00000000-0000-0000-0000-000000000000') as w0 \gset
select pg_temp.run(format('select public.po_receipt_work_split(%L::uuid, 100, %L::uuid)::text', :'w0', :'bina')) as sp1 \gset
select coalesce(pg_temp.j(:'sp1')->'to'->>'work_id', '00000000-0000-0000-0000-000000000000') as wa \gset
select coalesce((select (b.qty_ea - b.sales_alloc_ea - b.transfer_alloc_ea)::text from public.inv_available_base(:'wh'::uuid, array[:'p1'::uuid]) b), '0') as av0 \gset
select pg_temp.run(format('select public.po_receipt_post_now(%L::uuid, %L::jsonb, false)::text', :'r1', '["' || :'wa' || '"]')) as pv1 \gset
select (select count(*) from public.po_receipt_post) as n_post0, (select count(*) from public.inv_ledger where doc_number = 'RCV-79500') as n_led0, (select count(*) from public.po_receipt_line where receipt_id = :'r1'::uuid) as n_rl0 \gset
select pg_temp.run(format('select public.po_receipt_post_now(%L::uuid, %L::jsonb, true)::text', :'r1', '["' || :'wa' || '"]')) as ps1 \gset
select coalesce((select (b.qty_ea - b.sales_alloc_ea - b.transfer_alloc_ea)::text from public.inv_available_base(:'wh'::uuid, array[:'p1'::uuid]) b), '0') as av1 \gset
select pg_temp.ledger_of('RCV-79500') as led1 \gset
select pg_temp.layers_of('RCV-79500') as lay1 \gset
select pg_temp.chk('S1 preview: committed false · batch 1 · 1 row · 100 EA · basis invoice RCV1B-I1 · available_after = now + 100 · zero writes | post: committed true · batch 1 · ledger :p1 100 @A on d0 · layer 100 @2.5 · pin 1 (invoice) · available +100 · PO confirmed · receipt draft · diffs 0 · receipt line with post_id · work row frozen',
  :'sv1' not like 'ERR%' and :'sp1' not like 'ERR%' and :'pv1' not like 'ERR%' and :'ps1' not like 'ERR%'
  and (pg_temp.j(:'pv1')->>'committed') = 'false' and (pg_temp.j(:'pv1')->>'batch_no')::int = 1 and (pg_temp.j(:'pv1')->>'rows')::int = 1 and (pg_temp.j(:'pv1')->>'qty_ea')::numeric = 100
  and (pg_temp.j(:'pv1')->'lines'->0->>'cost_basis') = 'invoice' and (pg_temp.j(:'pv1')->'lines'->0->>'invoice_number') = 'RCV1B-I1'
  and (pg_temp.j(:'pv1')->'availability'->0->>'available_after')::numeric = (pg_temp.j(:'pv1')->'availability'->0->>'available_now')::numeric + 100
  and (pg_temp.j(:'pv1')->'availability'->0->>'available_now')::numeric = :'av0'::numeric
  and :n_post0 = 0 and :n_led0 = 0 and :n_rl0 = 0
  and (pg_temp.j(:'ps1')->>'committed') = 'true' and (pg_temp.j(:'ps1')->>'batch_no')::int = 1 and (pg_temp.j(:'ps1')->'ledger'->>'rows_posted')::int = 1 and (pg_temp.j(:'ps1')->'ledger'->>'qty_posted')::numeric = 100
  and :'led1' = :'l1' || ':p1:' || :'binaname' || ':100@' || :'d0'
  and :'lay1' = :'l1' || ':p1:RCV1B-P1:100@2.5:po_line'
  and (select count(*) from public.po_receipt_cost k where k.receipt_id = :'r1'::uuid and k.source = 'invoice') = 1
  and :'av1'::numeric = :'av0'::numeric + 100
  and (select status from public.po where id = :'po1'::uuid) = 'confirmed' and (select status from public.po_receipt where id = :'r1'::uuid) = 'draft'
  and (select count(*) from public.po_receipt_diff where receipt_id = :'r1'::uuid) = 0
  and (select count(*) from public.po_receipt_line where receipt_id = :'r1'::uuid and post_id is not null and qty_ea = 100) = 1
  and (select post_id is not null from public.po_receipt_work where id = :'wa'::uuid),
  format('sv1 %s | sp1 %s | pv1 %s | ps1 %s | led %s | lay %s | av %s → %s', left(:'sv1', 120), left(:'sp1', 120), left(:'pv1', 500), left(:'ps1', 400), :'led1', :'lay1', :'av0', :'av1'));

\echo '── S2) 같은 입고 두 번째 반영 — 50 을 칸 B 로 쪼갬 → :p2 · 핀 재사용(핀 1 · 레이어 기준 pinned · 같은 단가 2.5)'
select pg_temp.run(format('select public.po_receipt_work_split(%L::uuid, 50, %L::uuid)::text', :'w0', :'binb')) as sp2 \gset
select coalesce(pg_temp.j(:'sp2')->'to'->>'work_id', '00000000-0000-0000-0000-000000000000') as wb \gset
select pg_temp.run(format('select public.po_receipt_post_now(%L::uuid, %L::jsonb, true)::text', :'r1', '["' || :'wb' || '"]')) as ps2 \gset
select pg_temp.ledger_of('RCV-79500') as led2 \gset
select pg_temp.layers_of('RCV-79500') as lay2 \gset
select pg_temp.chk('S2 second batch: batch 2 · ledger :p2 50 @B · layers :p1 100 + :p2 50 both @2.5 · pin still 1 · layer basis pinned · posted_before batches 1 qty 100',
  :'sp2' not like 'ERR%' and :'ps2' not like 'ERR%' and (pg_temp.j(:'ps2')->>'batch_no')::int = 2
  and :'led2' = :'l1' || ':p1:' || :'binaname' || ':100@' || :'d0' || ' | ' || :'l1' || ':p2:' || :'binbname' || ':50@' || :'d0'
  and :'lay2' = :'l1' || ':p1:RCV1B-P1:100@2.5:po_line | ' || :'l1' || ':p2:RCV1B-P1:50@2.5:po_line'
  and (select count(*) from public.po_receipt_cost k where k.receipt_id = :'r1'::uuid) = 1
  and (pg_temp.j(:'ps2')->'layers'->'lines'->0->>'cost_basis') = 'pinned' and (pg_temp.j(:'ps2')->'layers'->>'layers_existing')::int = 1 and (pg_temp.j(:'ps2')->'layers'->>'layers_created')::int = 1
  and (pg_temp.j(:'ps2')->'posted_before'->>'batches')::int = 1 and (pg_temp.j(:'ps2')->'posted_before'->>'qty')::numeric = 100,
  format('sp2 %s | ps2 %s | led %s | lay %s', left(:'sp2', 120), left(:'ps2', 500), :'led2', :'lay2'));

\echo '── D1) po_receipt_detail 열쇠 — lines[].posted 150 · postable_rows 0 · work[].post_id/batch_no · header.posts 2 · post_now_ok false(칸 있는 미반영 줄 없음) · totals.posted · posted_batches · warnings posted_before'
select public.po_receipt_detail(:'r1'::uuid)::text as det1 \gset
select pg_temp.chk('D1 detail keys: lines[0].posted 150 · postable_rows 0 · work rows carry post_id + batch_no (1 · 2) · header.posts [1: 100 EA · 2: 50 EA] with posted_by_name · post_now_ok false · totals.posted 150 · posted_batches 2 · warnings ∋ posted_before · old keys intact (counted 600 · expected 600)',
  (pg_temp.j(:'det1')->'lines'->0->>'posted')::numeric = 150 and (pg_temp.j(:'det1')->'lines'->0->>'postable_rows')::int = 0
  and (select count(*) from jsonb_array_elements(pg_temp.j(:'det1')->'lines'->0->'work') w where (w->>'post_id') is not null) = 2
  and (select string_agg(w->>'batch_no', ',' order by (w->>'batch_no')::int) from jsonb_array_elements(pg_temp.j(:'det1')->'lines'->0->'work') w where (w->>'post_id') is not null) = '1,2'
  and jsonb_array_length(pg_temp.j(:'det1')->'header'->'posts') = 2 and (pg_temp.j(:'det1')->'header'->'posts'->0->>'qty_ea')::numeric = 100 and (pg_temp.j(:'det1')->'header'->'posts'->1->>'qty_ea')::numeric = 50
  and (pg_temp.j(:'det1')->'header'->'posts'->0->>'posted_by_name') = 'RCV1B office' and (pg_temp.j(:'det1')->'header'->'posts'->1->>'rows')::int = 1
  and (pg_temp.j(:'det1')->'header'->>'post_now_ok') = 'false'
  and (pg_temp.j(:'det1')->'totals'->>'posted')::numeric = 150 and (pg_temp.j(:'det1')->'totals'->>'posted_batches')::int = 2
  and (pg_temp.j(:'det1')->'warnings') ? 'posted_before'
  and (pg_temp.j(:'det1')->'lines'->0->>'counted')::numeric = 600 and (pg_temp.j(:'det1')->'lines'->0->>'expected')::numeric = 600,
  left(:'det1', 900));

\echo '── S3) 반영 뒤 비용 확정 → 얹지 않음(deferred · 경고 cost_deferred_post_now · 얹기 줄 0 · posted_on 비움) · 레이어 가치 그대로'
select pg_temp.run(format('select public.po_charge_confirm(%L::uuid, true)::text', :'c1')) as ch1 \gset
select pg_temp.chk('S3 charge confirm: status confirmed · cost.deferred_allocs 1 · allocs[0].status deferred · warnings ∋ cost_deferred_post_now · 0 landed rows · alloc posted_on null · layers still 2.5',
  :'ch1' not like 'ERR%' and (pg_temp.j(:'ch1')->>'status') = 'confirmed' and (pg_temp.j(:'ch1')->'cost'->>'deferred_allocs')::int = 1 and (pg_temp.j(:'ch1')->'cost'->>'layers_touched')::int = 0
  and (pg_temp.j(:'ch1')->'cost'->'allocs'->0->>'status') = 'deferred' and (pg_temp.j(:'ch1')->'warnings') ? 'cost_deferred_post_now'
  and (select count(*) from public.inv_layer_cost_add where doc_number = 'CHG-79500') = 0 and (select posted_on is null from public.po_charge_alloc where id = :'al1'::uuid)
  and pg_temp.layers_of('RCV-79500') = :'lay2', left(:'ch1', 600));

\echo '── S3b) 그 사이 판매 120(오늘−1) → 재생성(입고 draft · 묶음 둘): 건너뛴 입고 0 · 레이어 둘 그대로 · 소진 :p1 100 + :p2 20 · 비용은 여전히 미룸(0 행)'
set local session_replication_role = replica;
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, source, raw) values
  (:'d1'::date, 2, 'RCV1B-P1', :'whname', :'binaname', -120, 'sale_out', 'sale', 'SO-79500', null, 'rcv1b-sale:1', 'ims', '{"fake":"rcv-1b"}');
set local session_replication_role = origin;
select clock_timestamp()::text as tb0 \gset
select public.inv_layer_apply()::text as apply_mid \gset
select clock_timestamp()::text as tb1 \gset
select pg_temp.cons_of('SO-79500') as cons_mid \gset
select pg_temp.chk('S3b regeneration while draft: receipts_skipped 0 · layers :p1 100 + :p2 50 @2.5 · sale consumed 100 from :p1 then 20 from :p2 · CHG-79500 still 0 rows (deferred in regeneration too)',
  (pg_temp.j(:'apply_mid')->'ims'->>'receipts_skipped')::int = 0 and pg_temp.layers_of('RCV-79500') = :'lay2'
  and :'cons_mid' = 'RCV-79500/' || :'l1' || ':p1:sale:100=250 | RCV-79500/' || :'l1' || ':p2:sale:20=50'
  and (select count(*) from public.inv_layer_cost_add where doc_number = 'CHG-79500') = 0,
  format('skipped %s · apply %s ms | lay %s | cons %s | chg rows %s', pg_temp.j(:'apply_mid')->'ims'->>'receipts_skipped', round(extract(epoch from (:'tb1'::timestamptz - :'tb0'::timestamptz)) * 1000), pg_temp.layers_of('RCV-79500'), :'cons_mid', (select count(*) from public.inv_layer_cost_add where doc_number = 'CHG-79500')));

\echo '── S6) 가드 ⑤ — 반영 아래로 세기(90 · 140) · 반영 줄 putaway · split · unassign · delete 거부 · putaway_all 은 반영 줄 제외 · 나머지 450 을 같은 칸 A 에(따로 선다 · 병합 없음)'
select pg_temp.run(format('select public.po_receipt_work_save_by(%L::uuid, %L::uuid, %L::uuid, 90, ''manual'')::text', :'st', :'r1', :'l1')) as g1 \gset
select pg_temp.run(format('select public.po_receipt_work_save_by(%L::uuid, %L::uuid, %L::uuid, 140, ''manual'')::text', :'st', :'r1', :'l1')) as g2 \gset
select pg_temp.run(format('select public.po_receipt_work_putaway_by(%L::uuid, %L::uuid, %L::uuid, true)::text', :'st', :'wa', :'binc')) as g3 \gset
select pg_temp.run(format('select public.po_receipt_work_split(%L::uuid, 30, %L::uuid)::text', :'wa', :'binc')) as g4 \gset
select pg_temp.run(format('select public.po_receipt_work_unassign(%L::uuid)::text', :'wa')) as g5 \gset
select pg_temp.run(format('select public.po_receipt_work_delete(%L::uuid)::text', :'wa')) as g6 \gset
select pg_temp.run(format('select public.po_receipt_work_putaway_all_by(%L::uuid, %L::uuid, %L::uuid, false)::text', :'st', :'r1', :'bina')) as g7 \gset
select pg_temp.run(format('select public.po_receipt_work_putaway_by(%L::uuid, %L::uuid, %L::uuid, true)::text', :'st', :'w0', :'bina')) as g8 \gset
select pg_temp.chk('S6 guards: count 90 → refused (post-now) · count 140 → refused · putaway/split/unassign/delete of a posted row → refused (post-now wording) · putaway_all rows_changed 0 (posted row untouched · still done) · rest 450 into bin A → own row (not merged · 2 rows on line+bin A) · line total 600',
  :'g1' like 'ERR %already in stock from post-now%' and :'g2' like 'ERR %already in stock from post-now%'
  and :'g3' like 'ERR %already in stock from post-now%' and :'g4' like 'ERR %already in stock from post-now%' and :'g5' like 'ERR %already in stock from post-now%' and :'g6' like 'ERR %already in stock from post-now%'
  and :'g7' not like 'ERR%' and (pg_temp.j(:'g7')->>'rows_changed')::int = 0 and (select putaway_done from public.po_receipt_work where id = :'wa'::uuid)
  and :'g8' not like 'ERR%' and (pg_temp.j(:'g8')->>'merged_into') is null
  and (select count(*) from public.po_receipt_work w where w.receipt_id = :'r1'::uuid and w.po_line_id = :'l1'::uuid and w.bin_id = :'bina'::uuid) = 2
  and (select sum(qty_ea) from public.po_receipt_work w where w.receipt_id = :'r1'::uuid) = 600
  and (select qty_ea from public.po_receipt_work where id = :'wa'::uuid) = 100,
  format('g1 %s | g2 %s | g3 %s | g4 %s | g5 %s | g6 %s | g7 %s | g8 %s', left(:'g1', 140), left(:'g2', 100), left(:'g3', 100), left(:'g4', 100), left(:'g5', 100), left(:'g6', 100), left(:'g7', 160), left(:'g8', 200)));

\echo '── S7) 반영 뒤 거부 넷(지금 검사로) — PO 취소 · 입고 삭제 · 새 인보이스 확정 · 확정 인보이스 Reopen · + 날짜 바꾼 뒤 post_now · 확정 거부(이견 9) → 되돌림'
select pg_temp.run(format('select public.po_doc_cancel(''po'', %L::uuid, true)::text', :'po1')) as x1 \gset
select pg_temp.run(format('select public.po_receipt_delete(%L::uuid)::text', :'r1')) as x2 \gset
select pg_temp.run(format('select public.po_invoice_confirm(%L::uuid, true)::text', :'i4')) as x3 \gset
select pg_temp.run(format('select public.po_invoice_confirm(%L::uuid, false)::text', :'i1')) as x4 \gset
update public.po_receipt set received_on = :'d4'::date where id = :'r1'::uuid;
select pg_temp.run(format('select public.po_receipt_post_now(%L::uuid, %L::jsonb, false)::text', :'r1', '["' || :'w0' || '"]')) as x5 \gset
select pg_temp.run(format('select public.po_receipt_confirm_by(%L::uuid, %L::uuid)::text', :'st', :'r1')) as x6 \gset
update public.po_receipt set received_on = :'d0'::date where id = :'r1'::uuid;
select pg_temp.chk('S7 refusals: PO cancel (receipt lines) · receipt delete (receipt lines) · confirming another invoice on the PO (already has a receipt) · Reopen of the confirmed invoice (warehouse started) · date changed after a batch → post_now preview and final confirm both refused · receipt still draft · date set back',
  :'x1' like 'ERR %receipt line(s)%' and :'x2' like 'ERR %receipt line(s)%' and :'x3' like 'ERR %already has a receipt%' and :'x4' like 'ERR %Reopen is not possible%'
  and :'x5' like 'ERR %date was changed%' and :'x6' like 'ERR %date was changed%'
  and (select status from public.po_receipt where id = :'r1'::uuid) = 'draft' and (select received_on from public.po_receipt where id = :'r1'::uuid) = :'d0'::date,
  format('x1 %s | x2 %s | x3 %s | x4 %s | x5 %s | x6 %s', left(:'x1', 120), left(:'x2', 120), left(:'x3', 120), left(:'x4', 120), left(:'x5', 160), left(:'x6', 160)));

\echo '── S8) 권한 — receiving 없는 직원(authenticated) → 거부 · 창고 셸에는 창구 없음'
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims2', true) as claims2;
select pg_temp.run(format('select public.po_receipt_post_now(%L::uuid, %L::jsonb, true)::text', :'r1', '["' || :'w0' || '"]')) as pm1 \gset
reset role;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.chk('S8 permission: staff without receiving → "cannot change receiving data" · no wms_recv_post_now · no batch 3 written',
  :'pm1' like 'ERR %cannot change receiving data%' and to_regprocedure('public.wms_recv_post_now(uuid, jsonb, boolean)') is null
  and (select count(*) from public.po_receipt_post where receipt_id = :'r1'::uuid) = 2, left(:'pm1', 200));

\echo '── S4) 마지막 확정(남은 450 · 칸 A) → 꼬리 없는 450 · short 0 · PO closed · 미룬 비용 65 가 세 레이어(100 · 50 · 450 @2.5 → 250 · 125 · 1125 / 1500)에 비례 · 팔린 몫 cost_late(:p1 전량 · :p2 20/50) · posted_before 2 · 150'
select pg_temp.run(format('select public.po_receipt_confirm_by(%L::uuid, %L::uuid)::text', :'st', :'r1')) as cf1 \gset
select pg_temp.ledger_of('RCV-79500') as led4 \gset
select pg_temp.layers_of('RCV-79500') as lay4 \gset
select pg_temp.adds_of('CHG-79500') as adds4 \gset
select pg_temp.cons_of('SO-79500') as cons4 \gset
select pg_temp.chk('S4 final confirm: receipt_lines_created 1 · posted_before {2 · 150 · 2} · diffs 0/0 · PO closed · ledger + 450 no tail @A · layers :p1 100 · :p2 50 · final 450 all @2.5 · charge posted on 3 layers 10.833333 · 5.416667 · 48.75 (= 65) · alloc posted_on = today · cost_late :p1 10.833333 (all sold) · :p2 2.166667 (20/50)',
  :'cf1' not like 'ERR%' and (pg_temp.j(:'cf1')->>'receipt_lines_created')::int = 1
  and (pg_temp.j(:'cf1')->'posted_before'->>'batches')::int = 2 and (pg_temp.j(:'cf1')->'posted_before'->>'qty')::numeric = 150 and (pg_temp.j(:'cf1')->'posted_before'->>'rows')::int = 2
  and (pg_temp.j(:'cf1')->'diffs'->>'short')::int = 0 and (pg_temp.j(:'cf1')->'diffs'->>'over')::int = 0 and (pg_temp.j(:'cf1')->'po'->>'status') = 'closed'
  and (pg_temp.j(:'cf1')->'ledger'->>'rows_posted')::int = 1 and (pg_temp.j(:'cf1')->'ledger'->>'qty_posted')::numeric = 450
  and :'led4' = :'l1' || ':p1:' || :'binaname' || ':100@' || :'d0' || ' | ' || :'l1' || ':p2:' || :'binbname' || ':50@' || :'d0' || ' | ' || :'l1' || ':' || :'binaname' || ':450@' || :'d0'
  and :'lay4' = :'l1' || ':p1:RCV1B-P1:100@2.5:po_line | ' || :'l1' || ':p2:RCV1B-P1:50@2.5:po_line | ' || :'l1' || ':RCV1B-P1:450@2.5:po_line'
  and (pg_temp.j(:'cf1')->'charges'->'posted'->0->>'layers_touched')::int = 3 and (pg_temp.j(:'cf1')->'charges'->'posted'->0->>'amount_posted_cad')::numeric = 65 and jsonb_array_length(pg_temp.j(:'cf1')->'charges'->'errors') = 0
  and :'adds4' = 'RCV-79500/' || :'l1' || '=48.75@' || public.ims_today() || ' | RCV-79500/' || :'l1' || ':p1=10.833333@' || public.ims_today() || ' | RCV-79500/' || :'l1' || ':p2=5.416667@' || public.ims_today()
  and (select posted_on from public.po_charge_alloc where id = :'al1'::uuid) = public.ims_today()
  and :'cons4' = 'RCV-79500/' || :'l1' || ':p1:cost_late:0=10.833333 | RCV-79500/' || :'l1' || ':p1:sale:100=250 | RCV-79500/' || :'l1' || ':p2:cost_late:0=2.166667 | RCV-79500/' || :'l1' || ':p2:sale:20=50',
  format('cf1 %s | led %s | lay %s | adds %s | cons %s', left(:'cf1', 700), :'led4', :'lay4', :'adds4', :'cons4'));

\echo '── S5) RCV-79501: 400 셈 → 100 칸 A 반영(차이 0) → 나머지 300 칸 B → 마지막 확정 → short 50 은 마지막에만 한 번(expected 600 · received 400) · 꼬리 없는 300'
select pg_temp.run(format('select public.po_receipt_work_save_by(%L::uuid, %L::uuid, %L::uuid, 400, ''manual'')::text', :'st', :'r2', :'l2')) as sv5 \gset
select coalesce(pg_temp.j(:'sv5')->>'work_id', '00000000-0000-0000-0000-000000000000') as w5 \gset
select pg_temp.run(format('select public.po_receipt_work_split(%L::uuid, 100, %L::uuid)::text', :'w5', :'bina')) as sp5 \gset
select coalesce(pg_temp.j(:'sp5')->'to'->>'work_id', '00000000-0000-0000-0000-000000000000') as wa5 \gset
select pg_temp.run(format('select public.po_receipt_post_now(%L::uuid, %L::jsonb, true)::text', :'r2', '["' || :'wa5' || '"]')) as ps5 \gset
select (select count(*) from public.po_receipt_diff where receipt_id = :'r2'::uuid) as n_diff5 \gset
select pg_temp.run(format('select public.po_receipt_work_putaway_by(%L::uuid, %L::uuid, %L::uuid, true)::text', :'st', :'w5', :'binb')) as pa5 \gset
select pg_temp.run(format('select public.po_receipt_confirm_by(%L::uuid, %L::uuid)::text', :'st', :'r2')) as cf5 \gset
select pg_temp.ledger_of('RCV-79501') as led5 \gset
select pg_temp.chk('S5 short only at the end: post 100 (:p1 · diffs 0) → final 300 → short 1 (expected 600 · received 400) · ledger :p1 100 + 300 no tail · PO closed · posted_before 1 · 100',
  :'sv5' not like 'ERR%' and :'sp5' not like 'ERR%' and :'ps5' not like 'ERR%' and :'pa5' not like 'ERR%' and :'cf5' not like 'ERR%'
  and :n_diff5 = 0 and (pg_temp.j(:'ps5')->>'batch_no')::int = 1
  and (pg_temp.j(:'cf5')->'diffs'->>'short')::int = 1 and (pg_temp.j(:'cf5')->'diffs'->'rows'->0->>'expected_qty')::numeric = 600 and (pg_temp.j(:'cf5')->'diffs'->'rows'->0->>'received_qty')::numeric = 400
  and (select count(*) from public.po_receipt_diff where receipt_id = :'r2'::uuid and kind = 'short' and expected_qty = 600 and received_qty = 400) = 1
  and :'led5' = :'l2' || ':p1:' || :'binaname' || ':100@' || :'d0' || ' | ' || :'l2' || ':' || :'binbname' || ':300@' || :'d0'
  and (pg_temp.j(:'cf5')->'po'->>'status') = 'closed' and (pg_temp.j(:'cf5')->'posted_before'->>'batches')::int = 1 and (pg_temp.j(:'cf5')->'posted_before'->>'qty')::numeric = 100
  and pg_temp.layers_of('RCV-79501') = :'l2' || ':p1:RCV1B-P1:100@2.5:po_line | ' || :'l2' || ':RCV1B-P1:300@2.5:po_line',
  format('ps5 %s | cf5 %s | led %s', left(:'ps5', 200), left(:'cf5', 500), :'led5'));

\echo '── S10) RCV-79502(반영 없음 · 옛 흐름) — 50 셈 · 칸 C · 확정 → 꼬리 없는 행 하나 · 레이어 @4 · posted_before 0 · detail posts [] · 반환 모양 그대로'
select pg_temp.run(format('select public.po_receipt_work_save_by(%L::uuid, %L::uuid, %L::uuid, 50, ''manual'')::text', :'st', :'r3', :'l3')) as sv10 \gset
select coalesce(pg_temp.j(:'sv10')->>'work_id', '00000000-0000-0000-0000-000000000000') as w10 \gset
select pg_temp.run(format('select public.po_receipt_work_putaway_by(%L::uuid, %L::uuid, %L::uuid, true)::text', :'st', :'w10', :'binc')) as pa10 \gset
select pg_temp.run(format('select public.po_receipt_confirm_by(%L::uuid, %L::uuid)::text', :'st', :'r3')) as cf10 \gset
select public.po_receipt_detail(:'r3'::uuid)::text as det10 \gset
select pg_temp.chk('S10 old flow unchanged: ledger 1 row no tail 50 @C · layer 50 @4 · pin invoice · posted_before {0 · 0 · 0} · receipt_lines_created 1 · diffs 0 · detail posts [] · posted 0 · post_now_ok false · no posted_before warning',
  :'sv10' not like 'ERR%' and :'pa10' not like 'ERR%' and :'cf10' not like 'ERR%'
  and pg_temp.ledger_of('RCV-79502') = :'l3' || ':' || :'bincname' || ':50@' || :'d0' and pg_temp.layers_of('RCV-79502') = :'l3' || ':RCV1B-P2:50@4:po_line'
  and (select count(*) from public.po_receipt_cost k where k.receipt_id = :'r3'::uuid and k.source = 'invoice') = 1
  and (pg_temp.j(:'cf10')->'posted_before'->>'batches')::int = 0 and (pg_temp.j(:'cf10')->'posted_before'->>'qty')::numeric = 0 and (pg_temp.j(:'cf10')->>'receipt_lines_created')::int = 1
  and (pg_temp.j(:'cf10')->'diffs'->>'short')::int = 0 and (pg_temp.j(:'cf10')->'diffs'->>'over')::int = 0
  and jsonb_array_length(pg_temp.j(:'det10')->'header'->'posts') = 0 and (pg_temp.j(:'det10')->'totals'->>'posted')::numeric = 0 and (pg_temp.j(:'det10')->'header'->>'post_now_ok') = 'false'
  and not ((pg_temp.j(:'det10')->'warnings') ? 'posted_before'),
  format('cf10 %s | led %s | lay %s', left(:'cf10', 400), pg_temp.ledger_of('RCV-79502'), pg_temp.layers_of('RCV-79502')));

\echo '── S9) 끝 재생성 — 세 입고의 레이어 · 얹기 · 소진이 실시간과 같다(id 뺀 글) · 건너뛴 입고 0 · 실제 행 md5 전후 같음'
select pg_temp.layers_of('RCV-79500') || ' ## ' || pg_temp.layers_of('RCV-79501') || ' ## ' || pg_temp.layers_of('RCV-79502') as lay_rt \gset
select pg_temp.adds_of('CHG-79500') as adds_rt \gset
select pg_temp.cons_of('SO-79500') as cons_rt \gset
select clock_timestamp()::text as tc0 \gset
select public.inv_layer_apply()::text as apply_end \gset
select clock_timestamp()::text as tc1 \gset
select pg_temp.layers_of('RCV-79500') || ' ## ' || pg_temp.layers_of('RCV-79501') || ' ## ' || pg_temp.layers_of('RCV-79502') as lay_rg \gset
select pg_temp.adds_of('CHG-79500') as adds_rg \gset
select pg_temp.cons_of('SO-79500') as cons_rg \gset
select pg_temp.md5_layers() as m_layers_new, pg_temp.md5_adds() as m_adds_new, pg_temp.md5_consume() as m_cons_new \gset
select pg_temp.snap_layers('new');
select coalesce((select string_agg(d, ' ;; ') from (select 'old-only ' || k || ' ^' || parent as d from (select k, parent from t_lay_old except select k, parent from t_lay_new) a union all select 'new-only ' || k || ' ^' || parent from (select k, parent from t_lay_new except select k, parent from t_lay_old) b limit 4) z), '(none)') as lay_diff \gset
select coalesce((select string_agg(d, ' ;; ') from (select 'old-only ' || k || ' @' || lay as d from (select k, lay from t_add_old except select k, lay from t_add_new) a union all select 'new-only ' || k || ' @' || lay from (select k, lay from t_add_new except select k, lay from t_add_old) b limit 4) z), '(none)') as add_diff \gset
select pg_temp.chk('S9 regeneration = realtime: layers (3 receipts) · landed shares · cost_late · sale consumes identical · receipts_skipped 0 · real layers · adds · consumes md5 unchanged vs the old regeneration',
  :'lay_rg' = :'lay_rt' and :'adds_rg' = :'adds_rt' and :'cons_rg' = :'cons_rt' and (pg_temp.j(:'apply_end')->'ims'->>'receipts_skipped')::int = 0
  and :'m_layers_new' = :'m_layers_old' and :'m_adds_new' = :'m_adds_old' and :'m_cons_new' = :'m_cons_old',
  format('lay eq %s | adds eq %s | cons eq %s | skipped %s · apply %s ms | md5 layers %s adds %s cons %s | lay_diff %s | add_diff %s | rg lay %s | rg adds %s | rg cons %s', :'lay_rg' = :'lay_rt', :'adds_rg' = :'adds_rt', :'cons_rg' = :'cons_rt', pg_temp.j(:'apply_end')->'ims'->>'receipts_skipped', round(extract(epoch from (:'tc1'::timestamptz - :'tc0'::timestamptz)) * 1000), :'m_layers_new' = :'m_layers_old', :'m_adds_new' = :'m_adds_old', :'m_cons_new' = :'m_cons_old', left(:'lay_diff', 400), left(:'add_diff', 400), :'lay_rg', :'adds_rg', :'cons_rg'));

\else
select pg_temp.chk('S1 ~ S9 skipped: rcv-1b not landed (po_receipt_post · po_receipt_post_now missing)', false, 'not landed — nothing to exercise');   -- 미적용 DB 의 마른 실행이 ERROR 가 아니라 MISMATCH 로 끝나게
\endif

\echo '── Z1) 실제 원장 무접촉(스냅샷 id 집합)'
select pg_temp.chk(format('Z1 %s real ledger rows untouched (qty · line_ref · doc)', :n_real_ledger),
  (select md5(coalesce(string_agg(l.id::text || ':' || l.qty_delta || ':' || l.line_ref || ':' || l.doc_number, '|' order by l.id), '')) from public.inv_ledger l join t_real_ledger t on t.id = l.id) = :'md5_real_ledger', 'see Z1');

rollback;
\echo '── rollback 뒤 — 시퀀스 무접촉(직접 insert · 가짜 번호) · 가짜 흔적 0'
select (select last_value from public.po_number_seq) as po_seq_now, :po_seq_last as po_seq_head, (select last_value from public.po_receipt_number_seq) as rcv_seq_now, :rcv_seq_last as rcv_seq_head,
       (select count(*) from public.po where po_number like 'PO-795%') + (select count(*) from public.inv_ledger where doc_number like 'RCV-795%' or doc_number like 'SO-795%') + (select count(*) from public.ims_staff where email like 'rcv1b-%') + (select count(*) from public.product where sku like 'RCV1B-%') as fake_traces_left;
