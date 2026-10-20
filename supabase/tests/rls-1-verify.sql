-- rls-1-verify.sql — 원장 · 원가 표 넷 쓰기 닫기(판정 565): 결함 재현(S0) · 직접 쓰기 거부(S1) · 창구 길마다 원장/레이어 행 증가(S2 ~ S7 · 직원 신원 authenticated) · 재생성(S8) · 13 definer · ACL 그대로(S9) · 실제 행 무변(Z1 · Z2)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261020201002_rls_1_ledger_layer_write_gate.sql -f supabase/tests/rls-1-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 는 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더
--   재생성 inv_layer_apply 는 전량 · 약 36 초 — 두 번(앞 · 끝) · 신원 = receiving + purchasing(claims · postgres) · 가짜 재료는 전부 RLS1-/796xx · 끝은 rollback

\echo '── db_role · schema_migrations'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261020201002' \gset
select :n_applied as schema_migrations_rows_for_20261020201002;

begin;
set local statement_timeout = '900s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');   -- 0 행 returning 은 null — \gset 이 변수를 비워 다음 식이 깨진다(결함 판 mutA 에서 실측)
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.ledger_of(p_doc text) returns text language sql security definer as $$
  select coalesce(string_agg(regexp_replace(l.line_ref, '^[0-9a-f-]{36}', '#') || ':' || l.bin || ':' || trim_scale(l.qty_delta), ' | ' order by l.id), '(none)') from public.inv_ledger l where l.doc_number = p_doc $$;
create function pg_temp.layers_of(p_doc text) returns text language sql security definer as $$
  select coalesce(string_agg(regexp_replace(x.line_ref, '^[0-9a-f-]{36}', '#') || ':' || x.sku || ':' || trim_scale(x.qty) || '@' || trim_scale(x.unit_cost) || ':' || x.cost_source, ' | ' order by x.id), '(none)') from public.inv_layer x where x.doc_number = p_doc $$;
create function pg_temp.adds_of(p_doc text) returns text language sql security definer as $$
  select coalesce(string_agg(x.doc_number || '/' || regexp_replace(x.line_ref, '^[0-9a-f-]{36}', '#') || '=' || trim_scale(a.amount) || ':' || a.kind, ' | ' order by x.doc_number, x.line_ref), '(none)') from public.inv_layer_cost_add a join public.inv_layer x on x.id = a.layer_id where a.doc_number = p_doc $$;
-- 실제 레이어 · 얹기 · 소진의 내용 md5(가짜 SKU RLS1- 제외 · id 뺀 글) — 재생성이 id 를 바꾸므로 id 집합이 아니라 내용으로 비교
create function pg_temp.md5_layers() returns text language sql as $$
  select md5(coalesce(string_agg(k, ',' order by k), '')) from (
    select x.doc_number || '|' || x.line_ref || '|' || x.sku || '|' || x.warehouse || '|' || x.origin_type || '|' || x.received_on || '|' || trim_scale(x.qty) || '|' || trim_scale(x.unit_cost) || '|' || x.cost_source as k
    from public.inv_layer x where x.sku not like 'RLS1-%') s $$;
create function pg_temp.md5_adds() returns text language sql as $$
  select md5(coalesce(string_agg(k, ',' order by k), '')) from (
    select a.kind || '|' || trim_scale(a.amount) || '|' || a.occurred_on || '|' || a.doc_number || '|' || regexp_replace(a.line_ref, 'layer:[0-9]+:', 'layer:#:') || '|' || x.doc_number || '|' || x.line_ref || '|' || x.sku as k
    from public.inv_layer_cost_add a join public.inv_layer x on x.id = a.layer_id where x.sku not like 'RLS1-%') s $$;
create function pg_temp.md5_consume() returns text language sql as $$
  select md5(coalesce(string_agg(k, ',' order by k), '')) from (
    select c.doc_type || '|' || c.doc_number || '|' || c.line_ref || '|' || c.event_type || '|' || c.occurred_on || '|' || trim_scale(c.qty) || '|' || trim_scale(c.unit_cost) || '|' || trim_scale(c.amount) || '|' || c.reason || '|' || x.doc_number || '|' || x.line_ref || '|' || x.sku as k
    from public.inv_layer_consume c join public.inv_layer x on x.id = c.layer_id where x.sku not like 'RLS1-%') s $$;
-- 네 표의 정책 · grant · 13 함수의 definer 를 한 글로
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'auth_all=' || (select count(*) from pg_policies where schemaname = 'public' and tablename in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume') and policyname = 'auth_all')
      || ' select_pol=' || (select count(*) from pg_policies where schemaname = 'public' and tablename in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume') and cmd = 'SELECT' and roles::text ~ 'authenticated')
      || ' other_pol=' || (select count(*) from pg_policies where schemaname = 'public' and tablename in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume') and cmd <> 'SELECT')
      || ' auth_write_grants=' || (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume') and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'))
      || ' auth_select=' || (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume') and grantee = 'authenticated' and privilege_type = 'SELECT')
      || ' service_role_write=' || (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume') and grantee = 'service_role' and privilege_type in ('INSERT', 'UPDATE', 'DELETE'))
      || ' definer=' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prosecdef and proname in ('inv_layer_post_charge', 'inv_layer_post_receipt', 'inv_layer_post_receipt_off_po', 'inv_layer_post_receipt_over', 'inv_post_adjust', 'inv_post_credit', 'inv_post_move', 'inv_post_receipt', 'inv_post_receipt_off_po', 'inv_post_receipt_over', 'inv_post_sale', 'inv_post_transfer_arrive', 'inv_post_transfer_depart'))
      || ' invoker_writers=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and not p.prosecdef and p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?inv_(ledger|layer|layer_cost_add|layer_consume)\M') $$;
-- 13 함수의 몸(prosrc) md5 + ACL 글 — 머리 줄 하나만 바뀌었음을 증명(몸 바이트 · ACL 무변)
create function pg_temp.fn_bodies() returns text language sql as $$
  select md5(string_agg(p.proname || '=' || md5(p.prosrc) || '/' || coalesce(p.proacl::text, '-'), ',' order by p.proname)) from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_post_charge', 'inv_layer_post_receipt', 'inv_layer_post_receipt_off_po', 'inv_layer_post_receipt_over', 'inv_post_adjust', 'inv_post_credit', 'inv_post_move', 'inv_post_receipt', 'inv_post_receipt_off_po', 'inv_post_receipt_over', 'inv_post_sale', 'inv_post_transfer_arrive', 'inv_post_transfer_depart') $$;
create function pg_temp.fn_acls() returns text language sql as $$
  select string_agg(p.proname || ':' || case when coalesce(p.proacl::text, '') ~ 'authenticated' then 'auth' else 'noauth' end, ' ' order by p.proname) from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_post_charge', 'inv_layer_post_receipt', 'inv_layer_post_receipt_off_po', 'inv_layer_post_receipt_over', 'inv_post_adjust', 'inv_post_credit', 'inv_post_move', 'inv_post_receipt', 'inv_post_receipt_off_po', 'inv_post_receipt_over', 'inv_post_sale', 'inv_post_transfer_arrive', 'inv_post_transfer_depart') $$;

\echo '── M0) 직원 하나(office: manager · receiving + purchasing + stock_adjust + stock_move · 창고 전부) · 참조 · 빈 둘 · 실제 원장 스냅샷(id 집합) · 13 함수 몸 md5 · ACL'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls1-office@test.invalid', 'RLS1 office', 'manager', '["ims","receiving","purchasing","stock_adjust","stock_move"]', '{}') returning auth_user_id::text as g_uid, id::text as st \gset
\set g_claims '{"sub":"' :g_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select (public.ims_today() - 2)::text as d0, (public.ims_today() - 1)::text as d1 \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.id::text as bina, b.name as binaname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select b.id::text as binb, b.name as binbname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 offset 1 \gset
create temp table t_real_ledger as select l.id from public.inv_ledger l;
select count(*) as n_real_ledger, md5(coalesce(string_agg(l.id::text || ':' || l.qty_delta || ':' || l.line_ref || ':' || l.doc_number, '|' order by l.id), '')) as md5_real_ledger from public.inv_ledger l join t_real_ledger t on t.id = l.id \gset
select pg_temp.fn_bodies() as fn_bodies_before, pg_temp.fn_acls() as fn_acls_before \gset
select pg_temp.chk(format('M0 staff · warehouse %s · bins %s %s · %s real ledger rows snapshotted · 13 function bodies + ACL hashed', :'whname', :'binaname', :'binbname', :n_real_ledger),
  :'g_uid' <> '' and :'wh' <> '' and :'bina' <> '' and :'binb' <> '' and :'bina' <> :'binb' and :n_real_ledger > 0 and :'fn_bodies_before' <> '', 'see M0');

\echo '── M1) 가짜 재료 — 공급처 · 제품 둘 · PO-79600(P1 600 @2.00 · 인보이스 600 @2.50) · PO-79601(P2 50 @4.00 · 인보이스 50 @4.00) · 입고 둘 draft(오늘−2) · CHG-79600 65 CAD draft(PO-79600)'
set local session_replication_role = replica;
insert into public.supplier (name, payment_term_name, account_payable_code) values ('RLS1 Supplier', 'Net 30', '2000') returning id::text as sup \gset
insert into public.product (sku, name, source) values ('RLS1-P1', 'RLS1 P1', 'manual') returning id::text as p1 \gset
insert into public.product (sku, name, source) values ('RLS1-P2', 'RLS1 P2', 'manual') returning id::text as p2 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79600', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, :'d0', :'wh'::uuid, now()) returning id::text as po1 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79601', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, :'d0', :'wh'::uuid, now()) returning id::text as po2 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po1'::uuid, 1, :'p1'::uuid, 600, 2.00) returning id::text as l1 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po2'::uuid, 1, :'p2'::uuid, 50, 4.00) returning id::text as l2 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'RLS1-I1', :'d0', :'cad'::uuid, null, 1500, 'confirmed', 'invoice', now()) returning id::text as i1 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'RLS1-I2', :'d0', :'cad'::uuid, null, 200, 'confirmed', 'invoice', now()) returning id::text as i2 \gset
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (:'i1'::uuid, 1, 'goods', :'l1'::uuid, 600, 2.50, true), (:'i2'::uuid, 1, 'goods', :'l2'::uuid, 50, 4.00, true);
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by) values ('RCV-79600', :'po1'::uuid, :'wh'::uuid, :'d0'::date, 'draft', :'st'::uuid) returning id::text as r1 \gset
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by) values ('RCV-79601', :'po2'::uuid, :'wh'::uuid, :'d0'::date, 'draft', :'st'::uuid) returning id::text as r2 \gset
insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, status) values (:'sup'::uuid, 'CHG-79600', :'d1'::date, 'freight', :'cad'::uuid, 65, 'draft') returning id::text as c1 \gset
insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (:'c1'::uuid, :'po1'::uuid, 65) returning id::text as al1 \gset
set local session_replication_role = origin;
select pg_temp.chk('M1 fixtures: 2 POs confirmed · 2 confirmed invoices · 2 draft receipts · CHG-79600 draft allocated 65',
  (select count(*) from public.po where po_number like 'PO-796%' and status = 'confirmed') = 2 and (select count(*) from public.po_receipt where receipt_number like 'RCV-796%' and status = 'draft') = 2
  and (select count(*) from public.po_invoice where invoice_number like 'RLS1-I%' and status = 'confirmed') = 2 and :'al1' <> '', 'see M1');

select set_config('request.jwt.claims', :'g_claims', true) as claims;
\if :{?mig}
\echo '── S0) 결함 재현(시험 전용) — 로그인 직원(authenticated)이 네 표에 직접 insert 하면 들어간다 · auth_all 넷 · 쓰기 grant 있음'
select pg_temp.gate_state() as gate_before \gset
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.run(format('insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values (%L::date, 1, ''RLS1-P1'', %L, %L, 1, ''adjust_new'', ''adjustment'', ''RLS1-S0'', ''x'', ''manual'') returning id::text', :'d0', :'whname', :'binaname')) as s0_led \gset
select pg_temp.run(format('insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values (''RLS1-P1'', %L, ''adjust_new'', ''RLS1-S0'', ''x'', %L::date, true, 1, 0, ''manual'') returning id::text', :'whname', :'d0')) as s0_lay \gset
select pg_temp.run(format('insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref) values (%s, ''landed'', 1, %L::date, ''RLS1-S0'', ''x'') returning id::text', case when :'s0_lay' like 'ERR%' then '0' else :'s0_lay' end, :'d0')) as s0_add \gset
select pg_temp.run(format('insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) values (%s, ''adjustment'', ''RLS1-S0'', ''x'', ''adjust_existing'', %L::date, 1, 0, 0, ''lost'') returning id::text', case when :'s0_lay' like 'ERR%' then '0' else :'s0_lay' end, :'d0')) as s0_con \gset
reset role;
delete from public.inv_layer_consume where doc_number = 'RLS1-S0';
delete from public.inv_layer_cost_add where doc_number = 'RLS1-S0';
delete from public.inv_layer where doc_number = 'RLS1-S0';
delete from public.inv_ledger where doc_number = 'RLS1-S0';
select pg_temp.chk('S0 before the trial: authenticated staff inserted directly into inv_ledger · inv_layer · inv_layer_cost_add · inv_layer_consume (the defect) · auth_all ×4 · write grants present · 13 writers not all definer · not in schema_migrations',
  :'s0_led' not like 'ERR%' and :'s0_lay' not like 'ERR%' and :'s0_add' not like 'ERR%' and :'s0_con' not like 'ERR%'
  and :'gate_before' like 'auth_all=4 %' and :'gate_before' !~ 'auth_write_grants=0 ' and :'gate_before' !~ 'definer=13 ' and :n_applied = 0,
  format('led %s | lay %s | add %s | con %s | gate %s | n_applied %s', left(:'s0_led', 60), left(:'s0_lay', 60), left(:'s0_add', 60), left(:'s0_con', 60), :'gate_before', :n_applied));
select public.inv_layer_apply()::text as apply_old \gset
select pg_temp.md5_layers() as m_layers_old, pg_temp.md5_adds() as m_adds_old, pg_temp.md5_consume() as m_cons_old \gset
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: the 13 function bodies (prosrc) and ACLs are byte-identical — only the security header changed',
  pg_temp.fn_bodies() = :'fn_bodies_before' and pg_temp.fn_acls() = :'fn_acls_before', format('acls before %s | after %s', :'fn_acls_before', pg_temp.fn_acls()));
\else
select pg_temp.chk('P0c confirm run: migration 20261020201002 applied', :n_applied = 1, format('%s rows', :n_applied));
select public.inv_layer_apply()::text as apply_old \gset
select pg_temp.md5_layers() as m_layers_old, pg_temp.md5_adds() as m_adds_old, pg_temp.md5_consume() as m_cons_old \gset
\endif

select (pg_temp.gate_state() like 'auth_all=0 select_pol=4 %') as landed \gset
\if :landed
\echo '── G1) 실물 — 정책 select 넷 · 쓰기 정책 0 · authenticated 쓰기 grant 0 · select grant 4 · service_role 쓰기 12 · definer 13 · invoker 쓰기 함수 0 · ACL 다섯 auth / 여덟 noauth 그대로'
select pg_temp.gate_state() as gate \gset
select pg_temp.chk('G1 gate: auth_all 0 · select policies 4 · other policies 0 · authenticated write grants 0 · select 4 · service_role insert/update/delete 12 · definer 13 · invoker writers 0 · ACLs unchanged (5 auth · 8 noauth)',
  :'gate' = 'auth_all=0 select_pol=4 other_pol=0 auth_write_grants=0 auth_select=4 service_role_write=12 definer=13 invoker_writers=0'
  and pg_temp.fn_acls() = 'inv_layer_post_charge:auth inv_layer_post_receipt:noauth inv_layer_post_receipt_off_po:auth inv_layer_post_receipt_over:auth inv_post_adjust:noauth inv_post_credit:noauth inv_post_move:noauth inv_post_receipt:noauth inv_post_receipt_off_po:auth inv_post_receipt_over:auth inv_post_sale:noauth inv_post_transfer_arrive:noauth inv_post_transfer_depart:noauth',
  format('gate %s | acls %s', :'gate', pg_temp.fn_acls()));

\echo '── S1) 직접 쓰기 거부 — authenticated 직원: 네 표 insert · 원장 update · delete → 42501 permission denied for table(grant 벽이 먼저) · select 는 된다'
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.run(format('insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values (%L::date, 1, ''RLS1-P1'', %L, %L, 1, ''adjust_new'', ''adjustment'', ''RLS1-S1'', ''x'', ''manual'') returning id::text', :'d0', :'whname', :'binaname')) as s1_led \gset
select pg_temp.run(format('insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values (''RLS1-P1'', %L, ''adjust_new'', ''RLS1-S1'', ''x'', %L::date, true, 1, 0, ''manual'') returning id::text', :'whname', :'d0')) as s1_lay \gset
select pg_temp.run(format('insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref) values (0, ''landed'', 1, %L::date, ''RLS1-S1'', ''x'') returning id::text', :'d0')) as s1_add \gset
select pg_temp.run(format('insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) values (0, ''adjustment'', ''RLS1-S1'', ''x'', ''adjust_existing'', %L::date, 1, 0, 0, ''lost'') returning id::text', :'d0')) as s1_con \gset
select pg_temp.run('update public.inv_ledger set amount = amount where doc_number = ''RLS1-S1'' returning id::text') as s1_upd \gset
select pg_temp.run('delete from public.inv_ledger where doc_number = ''RLS1-S1'' returning id::text') as s1_del \gset
select pg_temp.run('update public.inv_layer set qty = qty where doc_number = ''RLS1-S1'' returning id::text') as s1_upd2 \gset
select pg_temp.run('select (select count(*) from public.inv_ledger)::text || ''/'' || (select count(*) from public.inv_layer)::text || ''/'' || (select count(*) from public.inv_layer_cost_add)::text || ''/'' || (select count(*) from public.inv_layer_consume)::text') as s1_sel \gset
reset role;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.chk('S1 direct writes refused for authenticated: insert ×4 · update ×2 · delete ×1 → 42501 "permission denied for table" · select on all four still works · nothing written',
  :'s1_led' like 'ERR 42501%' and :'s1_led' like '%permission denied for table inv_ledger%' and :'s1_lay' like 'ERR 42501%' and :'s1_lay' like '%permission denied for table inv_layer%'
  and :'s1_add' like 'ERR 42501%' and :'s1_add' like '%permission denied for table inv_layer_cost_add%' and :'s1_con' like 'ERR 42501%' and :'s1_con' like '%permission denied for table inv_layer_consume%'
  and :'s1_upd' like 'ERR 42501%' and :'s1_upd' like '%permission denied for table inv_ledger%' and :'s1_del' like 'ERR 42501%' and :'s1_upd2' like 'ERR 42501%'
  and :'s1_sel' ~ '^[0-9]+/[0-9]+/[0-9]+/[0-9]+$' and (select count(*) from public.inv_ledger where doc_number = 'RLS1-S1') + (select count(*) from public.inv_layer where doc_number = 'RLS1-S1') = 0,
  format('led %s | lay %s | add %s | con %s | upd %s | del %s | upd2 %s | sel %s', left(:'s1_led', 90), left(:'s1_lay', 90), left(:'s1_add', 90), left(:'s1_con', 90), left(:'s1_upd', 90), left(:'s1_del', 90), left(:'s1_upd2', 90), :'s1_sel'));

\echo '── S2) 입고 확정 길(authenticated 직원 · 셸 → _by definer → inv_post_receipt · inv_layer_post_receipt): RCV-79600 650 셈 → 칸 A → 확정 → 원장 600(:p 없음) · off_invoice 50 차이(칸 A) · 레이어 600 @2.5 · RCV-79601 50 셈 → 칸 B → 확정 → 원장 50 · 레이어 50 @4'
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.run(format('select public.po_receipt_work_save(%L::uuid, %L::uuid, 650, ''manual'')::text', :'r1', :'l1')) as sv1 \gset
select coalesce(pg_temp.j(:'sv1')->>'work_id', '00000000-0000-0000-0000-000000000000') as w1 \gset
select pg_temp.run(format('select public.po_receipt_work_putaway(%L::uuid, %L::uuid, true)::text', :'w1', :'bina')) as pa1 \gset
select pg_temp.run(format('select public.po_receipt_confirm(%L::uuid)::text', :'r1')) as cf1 \gset
select pg_temp.run(format('select public.po_receipt_work_save(%L::uuid, %L::uuid, 50, ''manual'')::text', :'r2', :'l2')) as sv2 \gset
select coalesce(pg_temp.j(:'sv2')->>'work_id', '00000000-0000-0000-0000-000000000000') as w2 \gset
select pg_temp.run(format('select public.po_receipt_work_putaway(%L::uuid, %L::uuid, true)::text', :'w2', :'binb')) as pa2 \gset
select pg_temp.run(format('select public.po_receipt_confirm(%L::uuid)::text', :'r2')) as cf2 \gset
reset role;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select coalesce((select d.id::text from public.po_receipt_diff d where d.receipt_id = :'r1'::uuid and d.kind = 'off_invoice'), '') as diff_oi \gset
select pg_temp.chk('S2 receipt confirm path as authenticated: RCV-79600 ledger 600 in bin A (no :p tail) · one off_invoice diff 50 placed in bin A · layer 600 @2.5 · RCV-79601 ledger 50 in bin B · layer 50 @4 · both receipts confirmed',
  :'cf1' not like 'ERR%' and :'cf2' not like 'ERR%' and :'sv1' not like 'ERR%' and :'pa1' not like 'ERR%'
  and pg_temp.ledger_of('RCV-79600') = '#:' || :'binaname' || ':600' and pg_temp.layers_of('RCV-79600') = '#:RLS1-P1:600@2.5:po_line'
  and pg_temp.ledger_of('RCV-79601') = '#:' || :'binbname' || ':50' and pg_temp.layers_of('RCV-79601') = '#:RLS1-P2:50@4:po_line'
  and :'diff_oi' <> '' and (select d.received_qty - d.expected_qty from public.po_receipt_diff d where d.id = nullif(:'diff_oi', '')::uuid) = 50 and (select d.bin_id::text from public.po_receipt_diff d where d.id = nullif(:'diff_oi', '')::uuid) = :'bina'
  and (select count(*) from public.po_receipt where receipt_number like 'RCV-796%' and status = 'confirmed') = 2,
  format('sv1 %s | pa1 %s | cf1 %s | cf2 %s | led1 %s | lay1 %s | led2 %s | lay2 %s | diff %s', left(:'sv1', 80), left(:'pa1', 80), left(:'cf1', 160), left(:'cf2', 160), pg_temp.ledger_of('RCV-79600'), pg_temp.layers_of('RCV-79600'), pg_temp.ledger_of('RCV-79601'), pg_temp.layers_of('RCV-79601'), :'diff_oi'));

\echo '── S3) 비용 확정 길(⚠️ 끊기던 뿌리 — po_charge_confirm invoker → inv_layer_post_charge): authenticated 직원 → CHG-79600 landed 65 가 RCV-79600 레이어에 얹힌다'
select (select count(*) from public.inv_layer_cost_add) as n_add0 \gset
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.run(format('select public.po_charge_confirm(%L::uuid, true)::text', :'c1')) as ch1 \gset
reset role;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.chk('S3 charge confirm path as authenticated (invoker root → definer layer writer): CHG-79600 confirmed · 1 landed add 65 on RCV-79600 layer · inv_layer_cost_add +1',
  :'ch1' not like 'ERR%' and pg_temp.adds_of('CHG-79600') = 'RCV-79600/#=65:landed' and (select count(*) from public.inv_layer_cost_add) = :n_add0 + 1
  and (select status from public.po_charge where id = :'c1'::uuid) = 'confirmed',
  format('ch1 %s | adds %s | n_add %s → %s', left(:'ch1', 200), pg_temp.adds_of('CHG-79600'), :n_add0, (select count(*) from public.inv_layer_cost_add)));

\echo '── S4) off-invoice 결정 길(⚠️ 끊기던 뿌리 — settle_off_invoice invoker → inv_post_receipt_off_po → inv_layer_post_receipt_off_po): accepted_free → 원장 :offpo 50 칸 A · 레이어 50 @0 free'
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.run(format('select public.po_receipt_diff_settle_off_invoice(%L::uuid, ''accepted_free'', null, ''rls-1 test'')::text', :'diff_oi')) as oi1 \gset
reset role;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.chk('S4 off-invoice accept path as authenticated: ledger RCV-79600 gains :offpo 50 in bin A · layer 50 @0 free · diff resolved accepted_free',
  :'oi1' not like 'ERR%' and pg_temp.ledger_of('RCV-79600') = '#:' || :'binaname' || ':600 | #:offpo:' || :'binaname' || ':50'
  and pg_temp.layers_of('RCV-79600') = '#:RLS1-P1:600@2.5:po_line | #:offpo:RLS1-P1:50@0:free'
  and (select d.resolution from public.po_receipt_diff d where d.id = nullif(:'diff_oi', '')::uuid) = 'accepted_free',
  format('oi1 %s | led %s | lay %s', left(:'oi1', 200), pg_temp.ledger_of('RCV-79600'), pg_temp.layers_of('RCV-79600')));

\echo '── S5) 옛 over 결정 길(⚠️ 끊기던 뿌리 — settle_over invoker → inv_post_receipt_over → inv_layer_post_receipt_over): RCV-79601 에 입고 줄 +5(칸 B) · over 차이(50 → 55) 를 심고 free 로 → 원장 :over 5 · 레이어 5'
set local session_replication_role = replica;
insert into public.po_receipt_line (po_line_id, received_on, received_by, bin_id, qty_ea, receipt_id) values (:'l2'::uuid, :'d0'::date, :'st'::uuid, :'binb'::uuid, 5, :'r2'::uuid);
insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty, note) values (:'r2'::uuid, :'po2'::uuid, :'l2'::uuid, :'p2'::uuid, 'over', 50, 55, 'rls-1 old over fixture (kind over keeps bin · placed · unit_price null — po_receipt_diff_off_po_cols_ck)') returning id::text as diff_ov \gset
set local session_replication_role = origin;
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.run(format('select public.po_receipt_diff_settle_over(%L::uuid, ''free'', ''rls-1 test'')::text', :'diff_ov')) as ov1 \gset
reset role;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.chk('S5 old over settle path as authenticated: ledger RCV-79601 gains :over 5 in bin B · a second layer of 5 · diff resolved free',
  :'ov1' not like 'ERR%' and pg_temp.ledger_of('RCV-79601') = '#:' || :'binbname' || ':50 | #:over:' || :'binbname' || ':5'
  and (select count(*) from public.inv_layer x where x.doc_number = 'RCV-79601') = 2 and (select trim_scale(x.qty)::text from public.inv_layer x where x.doc_number = 'RCV-79601' and x.line_ref like '%:over') = '5'
  and (select d.resolution from public.po_receipt_diff d where d.id = :'diff_ov'::uuid) = 'free',
  format('ov1 %s | led %s | lay %s', left(:'ov1', 200), pg_temp.ledger_of('RCV-79601'), pg_temp.layers_of('RCV-79601')));

\echo '── S6) 조정 길(inv_adjust_confirm definer → inv_post_adjust): RLS1-P1 칸 A +5 found → 원장 adjustment 행 1'
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.run(format('select public.inv_adjust_create(%L::uuid, ''rls-1 test'', null)::text', :'wh')) as ad0 \gset
select coalesce(pg_temp.j(:'ad0')->>'id', '00000000-0000-0000-0000-000000000000') as adj, coalesce(pg_temp.j(:'ad0')->>'adjust_number', '?') as adjno \gset
select pg_temp.run(format('select public.inv_adjust_line_set(%L::uuid, %L::jsonb)::text', :'adj', json_build_object('sku', 'RLS1-P1', 'bin', :'binaname', 'mode', 'delta', 'qty', 5, 'reason', 'found')::text)) as ad1 \gset
select pg_temp.run(format('select public.inv_adjust_confirm(%L::uuid)::text', :'adj')) as ad2 \gset
reset role;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.chk('S6 adjustment path as authenticated: create · line (+5 found in bin A) · confirm → 1 ledger adjustment row +5 for RLS1-P1',
  :'ad0' not like 'ERR%' and :'ad1' not like 'ERR%' and :'ad2' not like 'ERR%'
  and (select count(*) from public.inv_ledger l where l.doc_type = 'adjustment' and l.doc_number = :'adjno' and l.sku = 'RLS1-P1' and l.qty_delta = 5 and l.bin = :'binaname') = 1,
  format('ad0 %s | ad1 %s | ad2 %s', left(:'ad0', 120), left(:'ad1', 160), left(:'ad2', 200)));

\echo '── S7) 칸 옮김 길(inv_move_confirm definer → inv_post_move): RLS1-P1 칸 A → 칸 B 10 → 원장 transfer 행 2(−10 · +10)'
set local role authenticated;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.run(format('select public.inv_move_create(%L::uuid, ''rls-1 test'')::text', :'wh')) as mv0 \gset
select coalesce(pg_temp.j(:'mv0')->>'id', '00000000-0000-0000-0000-000000000000') as mv, coalesce(pg_temp.j(:'mv0')->>'move_number', '?') as mvno \gset
select pg_temp.run(format('select public.inv_move_line_set(%L::uuid, %L::jsonb)::text', :'mv', json_build_object('sku', 'RLS1-P1', 'from_bin', :'binaname', 'to_bin', :'binbname', 'qty', 10)::text)) as mv1 \gset
select pg_temp.run(format('select public.inv_move_confirm(%L::uuid)::text', :'mv')) as mv2 \gset
reset role;
select set_config('request.jwt.claims', :'g_claims', true) as claims;
select pg_temp.chk('S7 bin move path as authenticated: create · line (A → B 10) · confirm → 2 ledger transfer rows (−10 A · +10 B) for RLS1-P1',
  :'mv0' not like 'ERR%' and :'mv1' not like 'ERR%' and :'mv2' not like 'ERR%'
  and (select count(*) from public.inv_ledger l where l.doc_type = 'transfer' and l.doc_number = :'mvno' and l.sku = 'RLS1-P1') = 2
  and (select sum(l.qty_delta) from public.inv_ledger l where l.doc_type = 'transfer' and l.doc_number = :'mvno') = 0
  and (select l.qty_delta from public.inv_ledger l where l.doc_type = 'transfer' and l.doc_number = :'mvno' and l.bin = :'binbname') = 10,
  format('mv0 %s | mv1 %s | mv2 %s', left(:'mv0', 120), left(:'mv1', 160), left(:'mv2', 200)));

\echo '── S8) 재생성(postgres + claims · definer 창구로 다시 짓는다): 가짜 레이어 넷(600 · offpo 50 · 50 · over 5) 그대로 · 얹기 65 그대로 · 실제 레이어 · 얹기 · 소진 md5 앞과 같다 · 건너뛴 입고 0'
select pg_temp.layers_of('RCV-79600') || ' ## ' || pg_temp.layers_of('RCV-79601') as lay_rt, pg_temp.adds_of('CHG-79600') as adds_rt \gset
select clock_timestamp()::text as tc0 \gset
select public.inv_layer_apply()::text as apply_end \gset
select clock_timestamp()::text as tc1 \gset
select pg_temp.layers_of('RCV-79600') || ' ## ' || pg_temp.layers_of('RCV-79601') as lay_rg, pg_temp.adds_of('CHG-79600') as adds_rg \gset
select pg_temp.md5_layers() as m_layers_new, pg_temp.md5_adds() as m_adds_new, pg_temp.md5_consume() as m_cons_new \gset
select pg_temp.chk('S8 regeneration after the gate: fake layers (600 @2.5 · offpo 50 free · 50 @4 · over 5) and the landed add 65 reproduced · real layers · adds · consumes md5 unchanged · receipts_skipped 0',
  :'apply_end' not like 'ERR%' and :'lay_rg' = :'lay_rt' and :'adds_rg' = :'adds_rt' and (pg_temp.j(:'apply_end')->'ims'->>'receipts_skipped')::int = 0
  and :'m_layers_new' = :'m_layers_old' and :'m_adds_new' = :'m_adds_old' and :'m_cons_new' = :'m_cons_old',
  format('apply %s ms | lay eq %s | adds eq %s | skipped %s | md5 layers %s adds %s cons %s | rt %s | rg %s', round(extract(epoch from (:'tc1'::timestamptz - :'tc0'::timestamptz)) * 1000), :'lay_rg' = :'lay_rt', :'adds_rg' = :'adds_rt', pg_temp.j(:'apply_end')->'ims'->>'receipts_skipped', :'m_layers_new' = :'m_layers_old', :'m_adds_new' = :'m_adds_old', :'m_cons_new' = :'m_cons_old', :'lay_rt', :'lay_rg'));

\echo '── S9) 판매 · 크레딧 · 트랜스퍼 길(여기서 돌리지 않는 셋)은 pg_proc 로 — inv_post_sale · inv_post_credit · inv_post_transfer_depart · _arrive 가 definer · search_path 고정 · 부르는 definer 창구(so_ship · so_credit_issue · wms_finalize · wms_recv_complete)가 있다'
select pg_temp.chk('S9 sale · credit · transfer writers are definer with search_path pinned · their definer callers exist',
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.proconfig::text ~ 'search_path=public, pg_temp' and p.proname in ('inv_post_sale', 'inv_post_credit', 'inv_post_transfer_depart', 'inv_post_transfer_arrive')) = 4
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.proname in ('so_ship', 'so_credit_issue', 'wms_finalize', 'wms_recv_complete')) >= 3,
  format('definer+search_path %s of 4 | callers %s', (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.proconfig::text ~ 'search_path=public, pg_temp' and p.proname in ('inv_post_sale', 'inv_post_credit', 'inv_post_transfer_depart', 'inv_post_transfer_arrive')), (select string_agg(p.proname || ':' || p.prosecdef, ' ') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_ship', 'so_credit_issue', 'wms_finalize', 'wms_recv_complete'))));

\else
select pg_temp.chk('G1 ~ S9 skipped: rls-1 not landed (auth_all still on the four tables)', false, 'not landed — nothing to exercise');   -- 미적용 DB 의 마른 실행이 ERROR 가 아니라 MISMATCH 로 끝나게
\endif

\echo '── Z1) 실제 원장 무접촉(스냅샷 id 집합)'
select pg_temp.chk(format('Z1 %s real ledger rows untouched (qty · line_ref · doc)', :n_real_ledger),
  (select md5(coalesce(string_agg(l.id::text || ':' || l.qty_delta || ':' || l.line_ref || ':' || l.doc_number, '|' order by l.id), '')) from public.inv_ledger l join t_real_ledger t on t.id = l.id) = :'md5_real_ledger', 'see Z1');

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0'
select (select count(*) from public.po where po_number like 'PO-796%') + (select count(*) from public.inv_ledger where doc_number like 'RCV-796%' or doc_number like 'RLS1-%') + (select count(*) from public.inv_layer where sku like 'RLS1-%')
     + (select count(*) from public.ims_staff where email like 'rls1-%') + (select count(*) from public.product where sku like 'RLS1-%') as fake_traces_left;
