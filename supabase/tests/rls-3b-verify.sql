-- rls-3b-verify.sql — 원가 읽기 가리기(판정 576 · 580 · 582): 결함 재현(S0 · S0c 576 중간 상태 · 시험 전용) · 다섯 표 + product_supplier 가림(S1) · inv_layer_value · inv_layer_open 회수(S1) · 576 되돌리기 거부(S2) ·
--   열쇠와 무관하게 같은 것(S3 ~ S7 · S 대 SC · AR 대 ARC · P) · 새 문(S3 ~ S6 W 거부) · 살아야 하는 길(S8 Ship & invoice · S9 크레딧 · S5b 조정 — 원가 열쇠 없는 직원) · 무접촉(G0 · G1 · Z1)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261021131845_rls_3b_cost_read_gate.sql -f supabase/tests/rls-3b-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · S0c · G0 셋은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 19 − 3 + 1 = **17** · MISMATCH 0
--   가짜 재료는 전부 RLS3B-/7971x · 가짜 직원 여섯 · 번호 시퀀스 넷(so_number_seq S8 · so_invoice_number_seq S8 · so_credit_number_seq S9 · inv_adjust_number_seq S5)은 머리에서 읽고 rollback 뒤 greatest(실제 최대, 머리)로 되돌린다

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261021131845' \gset
select :n_applied as schema_migrations_rows_for_20261021131845;
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
select last_value as adj_seq_last, is_called as adj_seq_called from public.inv_adjust_number_seq \gset
select :inv_seq_last as so_invoice_number_seq_head, :'inv_seq_called' as inv_called, :so_seq_last as so_number_seq_head, :'so_seq_called' as so_called, :cr_seq_last as so_credit_number_seq_head, :'cr_seq_called' as cr_called, :adj_seq_last as inv_adjust_number_seq_head, :'adj_seq_called' as adj_called;

begin;
set local statement_timeout = '600s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 다섯 표 + product_supplier 의 정책 · 함수 여섯의 definer · inv_layer_open · inv_layer_value 의 ACL 을 한 글로
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'cost_pol=' || (select count(*) from pg_policies where schemaname = 'public' and tablename in ('inv_layer', 'inv_layer_cost_add', 'inv_layer_consume', 'inv_cost', 'inv_doc_cost') and cmd = 'SELECT' and qual ~ 'ims_can_view_cost')
      || ' true_pol=' || (select count(*) from pg_policies where schemaname = 'public' and tablename in ('inv_layer', 'inv_layer_cost_add', 'inv_layer_consume', 'inv_cost', 'inv_doc_cost', 'product_supplier') and qual = 'true')
      || ' write_pol=' || (select count(*) from pg_policies where schemaname = 'public' and tablename in ('inv_layer', 'inv_layer_cost_add', 'inv_layer_consume', 'inv_cost', 'inv_doc_cost', 'product_supplier') and cmd <> 'SELECT')
      || ' ps_pol=' || (select count(*) from pg_policies where schemaname = 'public' and tablename = 'product_supplier' and qual ~ 'ims_can_view\(''purchasing''' and qual ~ 'ims_can_view\(''master''' and qual ~ 'ims_can_view_cost')
      || ' definer=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.proname in ('so_stock_short_list', 'so_credit_detail', 'po_fx_cost_lines', 'inv_adjust_eval', 'po_charge_confirm', 'inv_transfer_detail'))
      || ' open_auth=' || has_table_privilege('authenticated', 'public.inv_layer_open', 'select')::text
      || ' value_auth=' || has_function_privilege('authenticated', 'public.inv_layer_value(bigint)', 'execute')::text
      || ' value_svc=' || has_function_privilege('service_role', 'public.inv_layer_value(bigint)', 'execute')::text
      || ' helper=' || (to_regprocedure('public.ims_require_ok(boolean, text)') is not null)::text $$;
-- 무접촉 집합(마이그레이션과 같은 식 — 뷰 inv_layer_open 의 grant 는 뺀다)
create function pg_temp.untouched_md5() returns text language sql security definer as $$
  select md5(string_agg(k, ',' order by k)) from (
    select 'pol:' || tablename || ':' || policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-') as k
      from pg_policies where schemaname = 'public' and (tablename like 'wms\_%' or tablename in ('inv_ledger', 'inv_config', 'inv_snapshot', 'inv_sync_state', 'inv_sku_types', 'inv_doc_state', 'inv_voided_docs', 'inv_missing_docs', 'inv_missing_lines', 'inv_conflicts', 'inv_collect_runs', 'inv_snapshot_runs', 'inv_compare', 'inv_compare_runs', 'inv_balance_diffs', 'inv_bin_notes'))
    union all
    select 'grant:' || table_name || ':' || grantee || ':' || privilege_type
      from information_schema.role_table_grants where table_schema = 'public' and (table_name like 'wms\_%' or table_name like 'inv\_%' or table_name = 'product_supplier') and table_name <> 'inv_layer_open'
    union all
    select 'fn:' || p.proname || ':' || coalesce(p.proacl::text, '-')
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_carry', 'inv_layer_cost_add_settle', 'inv_snap_balance_diffs', 'inv_compare_run', 'inv_ack_diff', 'tf_charge_confirm', 'tf_charge_update', 'tf_charge_delete', 'tf_charge_alloc_add', 'tf_charge_alloc_update', 'tf_charge_alloc_delete')
  ) s $$;
-- 여섯 함수의 ACL(이 차수는 ACL 을 안 바꾼다) + inv_layer_value 몸 md5
create function pg_temp.fn_acls() returns text language sql as $$
  select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) || ' value_md5=' || (select md5(x.prosrc) from pg_proc x where x.pronamespace = 'public'::regnamespace and x.proname = 'inv_layer_value')
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_stock_short_list', 'so_credit_detail', 'po_fx_cost_lines', 'inv_adjust_eval', 'po_charge_confirm', 'inv_transfer_detail') $$;
-- 실제 행(가짜 RLS3B- 제외)
create function pg_temp.real_rows() returns text language sql security definer as $$
  select 'layer=' || (select count(*) || '/' || coalesce(sum(id), 0) || '/' || coalesce(sum(qty * unit_cost), 0) from public.inv_layer where sku not like 'RLS3B-%')
      || ' adds=' || (select count(*) || '/' || coalesce(sum(a.amount), 0) from public.inv_layer_cost_add a join public.inv_layer x on x.id = a.layer_id where x.sku not like 'RLS3B-%')
      || ' cons=' || (select count(*) || '/' || coalesce(sum(c.amount), 0) from public.inv_layer_consume c join public.inv_layer x on x.id = c.layer_id where x.sku not like 'RLS3B-%')
      || ' cost=' || (select count(*) || '/' || coalesce(sum(amount), 0) from public.inv_cost)
      || ' doc_cost=' || (select count(*) || '/' || coalesce(sum(amount), 0) from public.inv_doc_cost)
      || ' ps=' || (select count(*) || '/' || coalesce(sum(cost), 0) from public.product_supplier ps join public.product p on p.id = ps.product_id where p.sku not like 'RLS3B-%')
      || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where sku not like 'RLS3B-%')
      || ' so=' || (select count(*) from public.so where customer_id not in (select id from public.customer where name = 'RLS3B Customer')) || ' inv=' || (select count(*) from public.so_invoice i where not exists (select 1 from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = i.id and s.customer_id in (select c.id from public.customer c where c.name = 'RLS3B Customer'))) $$;
create function pg_temp.layers_of(p_doc text) returns text language sql security definer as $$
  select coalesce(string_agg(regexp_replace(x.line_ref, '^[0-9a-f-]{36}', '#') || ':' || x.sku || ':' || trim_scale(x.qty) || '@' || trim_scale(x.unit_cost) || ':' || x.cost_source, ' | ' order by x.id), '(none)') from public.inv_layer x where x.doc_number = p_doc $$;
create function pg_temp.adds_of(p_doc text) returns text language sql security definer as $$
  select coalesce(string_agg(x.doc_number || '/' || regexp_replace(x.line_ref, '^[0-9a-f-]{36}', '#') || '=' || trim_scale(a.amount) || ':' || a.kind, ' | ' order by x.doc_number, x.line_ref), '(none)') from public.inv_layer_cost_add a join public.inv_layer x on x.id = a.layer_id where a.doc_number = p_doc $$;
create function pg_temp.consumes_of(p_doc text) returns text language sql security definer as $$
  select coalesce(string_agg(c.reason || ':' || trim_scale(c.qty) || '@' || trim_scale(c.amount), ' | ' order by c.id), '(none)') from public.inv_layer_consume c join public.inv_layer x on x.id = c.layer_id where x.doc_number = p_doc $$;
-- 역할을 바꿔 한 문장을 돌린다(결과 글) — set local role 은 호출자 문맥에서 하므로 여기서는 claims 만
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;

\echo '── M0) 가짜 직원 여섯 — W worker 열쇠 없음 · S sales · SC sales + cost + transfer · P purchasing + receiving + transfer(cost 없음) · AR stock_adjust · ARC stock_adjust + cost · 참조 · 실물 샘플 · 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls3b-w@test.invalid', 'RLS3B W', 'worker', '[]', '{}') returning auth_user_id::text as w_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls3b-s@test.invalid', 'RLS3B S', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as s_uid, id::text as s_id \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls3b-sc@test.invalid', 'RLS3B SC', 'manager', '["ims","sales","cost","transfer"]', '{}') returning auth_user_id::text as sc_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls3b-p@test.invalid', 'RLS3B P', 'manager', '["ims","purchasing","receiving","transfer"]', '{}') returning auth_user_id::text as p_uid, id::text as p_id \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls3b-ar@test.invalid', 'RLS3B AR', 'manager', '["ims","stock_adjust"]', '{}') returning auth_user_id::text as ar_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls3b-arc@test.invalid', 'RLS3B ARC', 'manager', '["ims","stock_adjust","cost"]', '{}') returning auth_user_id::text as arc_uid \gset
\set w  '{"sub":"' :w_uid  '","role":"authenticated"}'
\set s  '{"sub":"' :s_uid  '","role":"authenticated"}'
\set sc '{"sub":"' :sc_uid '","role":"authenticated"}'
\set p  '{"sub":"' :p_uid  '","role":"authenticated"}'
\set ar '{"sub":"' :ar_uid '","role":"authenticated"}'
\set arc '{"sub":"' :arc_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select (public.ims_today() - 2)::text as d0, (public.ims_today() - 1)::text as d1 \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.id::text as bina, b.name as binaname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select id as real_layer from public.inv_layer where qty > 0 order by id limit 1 \gset
select c.id::text as real_credit from public.so_credit c order by (select count(*) from public.inv_layer y where y.origin_type = 'creditnote' and y.doc_number = c.credit_number) desc, c.credit_number limit 1 \gset
select t.id::text as real_trf from public.inv_transfer t order by t.transfer_number limit 1 \gset
select rt.name as tier_name, rt.id::text as tier from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as tax_rule, name as tax_rule_name from public.ref_tax_rule where name = 'Exempt (Sale)' and is_active \gset
select count(*)::text as n_layer_pg from public.inv_layer \gset
select count(*)::text as n_ps_pg from public.product_supplier \gset
select pg_temp.real_rows() as real_before, pg_temp.untouched_md5() as untouched_before, pg_temp.fn_acls() as acls_before \gset
select pg_temp.chk(format('M0 staff ×6 · warehouse %s · bin %s · real layer %s · credit %s · transfer %s · tier %s · tax %s · layers %s · product_supplier %s', :'whname', :'binaname', :real_layer, left(:'real_credit', 8), left(:'real_trf', 8), :'tier_name', :'tax_rule_name', :n_layer_pg, :n_ps_pg),
  :'w_uid' <> '' and :'sc_uid' <> '' and :'arc_uid' <> '' and :'wh' <> '' and :'bina' <> '' and :real_layer > 0 and :'real_credit' <> '' and :'real_trf' <> '' and :'tier' <> '' and :'tax_rule' <> '' and :n_layer_pg > 0 and :'real_before' <> '', 'see M0');

\echo '── M1) 가짜 재료 — 공급처(RLS3B-P1 단가 2.00 CAD) · 제품 · PO-79710(600 @2.00 · 인보이스 600 @2.50) · 입고 draft · CHG-79710 60 CAD draft · 손님 · sale_shortfall 가짜 레이어(unit_cost 1.23 · 판매 RLS3B-SO1)'
set local session_replication_role = replica;
insert into public.supplier (name, payment_term_name, account_payable_code) values ('RLS3B Supplier', 'Net 30', '2000') returning id::text as sup \gset
insert into public.product (sku, name, source) values ('RLS3B-P1', 'RLS3B P1', 'manual') returning id::text as p1 \gset
insert into public.product_supplier (product_id, supplier_id, supplier_sku, cost, currency_id, is_default, is_active, source) values (:'p1'::uuid, :'sup'::uuid, 'RLS3B-SUP-1', 2.00, :'cad'::uuid, true, true, 'manual') returning id::text as ps1 \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79710', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, :'d0', :'wh'::uuid, now()) returning id::text as po1 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po1'::uuid, 1, :'p1'::uuid, 600, 2.00) returning id::text as l1 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'RLS3B-I1', :'d0', :'cad'::uuid, null, 1500, 'confirmed', 'invoice', now()) returning id::text as i1 \gset
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (:'i1'::uuid, 1, 'goods', :'l1'::uuid, 600, 2.50, true);
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by) values ('RCV-79710', :'po1'::uuid, :'wh'::uuid, :'d0'::date, 'draft', :'p_id'::uuid) returning id::text as r1 \gset
insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, status) values (:'sup'::uuid, 'CHG-79710', :'d1'::date, 'freight', :'cad'::uuid, 60, 'draft') returning id::text as c1 \gset
insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (:'c1'::uuid, :'po1'::uuid, 60) returning id::text as al1 \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id) values ('RLS3B Customer', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid) returning id::text as cust \gset
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values ('RLS3B-P1', :'whname', 'sale_shortfall', 'RLS3B-SO1', 'x', :'d1'::date, false, 3, 1.23, 'unknown') returning id as short_layer \gset
set local session_replication_role = origin;
select pg_temp.chk('M1 fixtures: supplier link 2.00 · PO-79710 confirmed · invoice confirmed · draft receipt · CHG-79710 draft allocated 60 · customer · sale_shortfall layer',
  :'ps1' <> '' and (select status from public.po where id = :'po1'::uuid) = 'confirmed' and (select status from public.po_receipt where id = :'r1'::uuid) = 'draft' and :'al1' <> '' and :'cust' <> '' and :short_layer > 0, 'see M1');

\echo '── M2) P(purchasing + receiving · cost 없음): 입고 확정 → 레이어 600 @2.5 · 비용 확정 → landed 60 얹힘(어느 갈래든 — 적용 전엔 invoker 뿌리 · 적용 뒤엔 definer)'
set local role authenticated;
select set_config('request.jwt.claims', :'p', true) as claims;
select pg_temp.run(format('select public.po_receipt_work_save(%L::uuid, %L::uuid, 600, ''manual'')::text', :'r1', :'l1')) as sv1 \gset
select coalesce(pg_temp.j(:'sv1')->>'work_id', '00000000-0000-0000-0000-000000000000') as w1 \gset
select pg_temp.run(format('select public.po_receipt_work_putaway(%L::uuid, %L::uuid, true)::text', :'w1', :'bina')) as pa1 \gset
select pg_temp.run(format('select public.po_receipt_confirm(%L::uuid)::text', :'r1')) as cf1 \gset
select pg_temp.run(format('select public.po_charge_confirm(%L::uuid, true)::text', :'c1')) as ch1 \gset
reset role;
select pg_temp.chk('M2 receipt + charge confirmed by P: layer 600 @2.5 · landed add 60 · charge confirmed',
  :'cf1' not like 'ERR%' and :'ch1' not like 'ERR%' and pg_temp.layers_of('RCV-79710') = '#:RLS3B-P1:600@2.5:po_line' and pg_temp.adds_of('CHG-79710') = 'RCV-79710/#=60:landed'
  and (select status from public.po_charge where id = :'c1'::uuid) = 'confirmed',
  format('sv1 %s | pa1 %s | cf1 %s | ch1 %s | lay %s | adds %s', left(:'sv1', 80), left(:'pa1', 80), left(:'cf1', 120), left(:'ch1', 200), pg_temp.layers_of('RCV-79710'), pg_temp.adds_of('CHG-79710')));

\if :{?mig}
\echo '── S0) 결함 재현(시험 전용) — W(열쇠 없음)가 inv_layer · inv_cost · product_supplier 를 읽는다 · inv_layer_value 가 금액을 낸다 · inv_layer_open 이 읽힌다 · S(sales 만)가 so_stock_short_list 로 unit_cost 를 본다'
select pg_temp.gate_state() as gate_before \gset
select count(*)::text as n_layer_now from public.inv_layer \gset
select count(*)::text as n_ps_now from public.product_supplier \gset
set local role authenticated;
select set_config('request.jwt.claims', :'w', true) as claims;
select pg_temp.run('select count(*)::text from public.inv_layer') as s0_layer \gset
select pg_temp.run('select count(*)::text from public.inv_cost') as s0_cost \gset
select pg_temp.run('select count(*)::text from public.product_supplier') as s0_ps \gset
select pg_temp.run(format('select remaining_value::text from public.inv_layer_value(%s)', :real_layer)) as s0_value \gset
select pg_temp.run('select count(*)::text from public.inv_layer_open') as s0_open \gset
select set_config('request.jwt.claims', :'s', true) as claims;
select pg_temp.run('select (public.so_stock_short_list(''{}''::jsonb)->''unchecked''->0->>''unit_cost'')') as s0_short \gset
reset role;
select pg_temp.chk('S0 before the trial: W reads inv_layer · inv_cost · product_supplier (same counts as postgres) · inv_layer_value returns a value · inv_layer_open readable · S sees unit_cost in so_stock_short_list (the defect) · not in schema_migrations',
  :'s0_layer' = :'n_layer_now' and :'s0_cost' ~ '^[1-9]' and :'s0_ps' = :'n_ps_now' and :'s0_value' ~ '^[0-9.]+$' and :'s0_open' ~ '^[1-9]' and :'s0_short' ~ '^[0-9.]+$'
  and :'gate_before' like 'cost_pol=0 true_pol=6 %' and :n_applied = 0,
  format('layer %s | cost %s | ps %s | value %s | open %s | short %s | gate %s | n_applied %s', :'s0_layer', :'s0_cost', :'s0_ps', :'s0_value', :'s0_open', :'s0_short', :'gate_before', :n_applied));
\echo '── S0c) 576 중간 상태 재현(시험 전용 · savepoint): 정책만 원가 열쇠로 바꾸고 po_charge_confirm 이 invoker 인 채 — P(cost 없음)가 CHG-79710 을 되돌리면 「이미 얹힘」 검사가 0 행이라 통과한다(장부 결함) → 되돌림'
savepoint s0c;
drop policy inv_layer_cost_add_select on public.inv_layer_cost_add;
create policy inv_layer_cost_add_select on public.inv_layer_cost_add for select to authenticated using ((select public.ims_can_view_cost()));
set local role authenticated;
select set_config('request.jwt.claims', :'p', true) as claims;
select pg_temp.run(format('select public.po_charge_confirm(%L::uuid, false)::text', :'c1')) as s0c_rev \gset
reset role;
select (select status from public.po_charge where id = :'c1'::uuid) as s0c_status, pg_temp.adds_of('CHG-79710') as s0c_adds \gset
rollback to savepoint s0c;
select pg_temp.chk('S0c the 576 defect reproduced in the half-way state (policy keyed · function still invoker): P reopened CHG-79710 although its landed add is on the layer · status went back to draft · landed add still there → rolled back',
  :'s0c_rev' not like 'ERR%' and :'s0c_status' = 'draft' and :'s0c_adds' = 'RCV-79710/#=60:landed' and (select status from public.po_charge where id = :'c1'::uuid) = 'confirmed',
  format('rev %s | status %s | adds %s | after rollback %s', left(:'s0c_rev', 160), :'s0c_status', :'s0c_adds', (select status from public.po_charge where id = :'c1'::uuid)));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: six function ACLs unchanged · inv_layer_value body md5 unchanged · untouched set (WMS 18 · inv_ledger · inv_config · rls-3a 16 · grants · rls-3a fn ACLs) same',
  pg_temp.fn_acls() = :'acls_before' and pg_temp.untouched_md5() = :'untouched_before',
  format('acls eq %s | untouched eq %s | acls %s', pg_temp.fn_acls() = :'acls_before', pg_temp.untouched_md5() = :'untouched_before', pg_temp.fn_acls()));
\else
select pg_temp.chk('P0c confirm run: migration 20261021131845 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() like 'cost_pol=5 true_pol=0 %') as landed \gset
\if :landed
\echo '── G1) 실물 — 원가 정책 5 · true 정책 0 · 쓰기 정책 0 · product_supplier 정책 1(세 열쇠) · definer 6 · inv_layer_open authenticated 없음 · inv_layer_value authenticated 없음 · service_role 있음 · 도우미 있음'
select pg_temp.gate_state() as gate \gset
select pg_temp.chk('G1 gate state exact', :'gate' = 'cost_pol=5 true_pol=0 write_pol=0 ps_pol=1 definer=6 open_auth=false value_auth=false value_svc=true helper=true', :'gate');

\echo '── S1) 가림 — W · S · P 의 다섯 표 select → 0 행(정책 · 예외 아님) · SC 는 postgres 와 같은 수 · product_supplier: W · S 0 행 · P · SC 같은 수 · inv_layer_value · inv_layer_open → 42501'
set local role authenticated;
select pg_temp.as_user(:'w',  'select (select count(*) from public.inv_layer) || ''/'' || (select count(*) from public.inv_layer_cost_add) || ''/'' || (select count(*) from public.inv_layer_consume) || ''/'' || (select count(*) from public.inv_cost) || ''/'' || (select count(*) from public.inv_doc_cost) || ''/'' || (select count(*) from public.product_supplier)') as s1_w \gset
select pg_temp.as_user(:'s',  'select (select count(*) from public.inv_layer) || ''/'' || (select count(*) from public.inv_layer_cost_add) || ''/'' || (select count(*) from public.inv_layer_consume) || ''/'' || (select count(*) from public.inv_cost) || ''/'' || (select count(*) from public.inv_doc_cost) || ''/'' || (select count(*) from public.product_supplier)') as s1_s \gset
select pg_temp.as_user(:'p',  'select (select count(*) from public.inv_layer) || ''/'' || (select count(*) from public.inv_cost) || ''/'' || (select count(*) from public.product_supplier)') as s1_p \gset
select pg_temp.as_user(:'sc', 'select (select count(*) from public.inv_layer) || ''/'' || (select count(*) from public.inv_layer_cost_add) || ''/'' || (select count(*) from public.inv_layer_consume) || ''/'' || (select count(*) from public.inv_cost) || ''/'' || (select count(*) from public.inv_doc_cost) || ''/'' || (select count(*) from public.product_supplier)') as s1_sc \gset
select pg_temp.as_user(:'sc', format('select remaining_value::text from public.inv_layer_value(%s)', :real_layer)) as s1_value \gset
select pg_temp.as_user(:'sc', 'select count(*)::text from public.inv_layer_open') as s1_open \gset
reset role;
select (select count(*) from public.inv_layer) || '/' || (select count(*) from public.inv_layer_cost_add) || '/' || (select count(*) from public.inv_layer_consume) || '/' || (select count(*) from public.inv_cost) || '/' || (select count(*) from public.inv_doc_cost) || '/' || (select count(*) from public.product_supplier) as s1_pg \gset
select (select count(*) from public.inv_layer) || '/' || (select count(*) from public.inv_cost) || '/' || (select count(*) from public.product_supplier) as s1_pg3 \gset
select pg_temp.chk('S1 hidden: W and S see 0/0/0/0/0/0 · P sees 0 layers · 0 inv_cost · all product_supplier · SC sees the same six counts as postgres · inv_layer_value and inv_layer_open → 42501 even for SC',
  :'s1_w' = '0/0/0/0/0/0' and :'s1_s' = '0/0/0/0/0/0' and :'s1_p' = '0/0/' || split_part(:'s1_pg3', '/', 3) and :'s1_sc' = :'s1_pg'
  and :'s1_value' like 'ERR 42501%' and :'s1_value' like '%function inv_layer_value%' and :'s1_open' like 'ERR 42501%' and :'s1_open' like '%inv_layer_open%',
  format('w %s | s %s | p %s | sc %s | pg %s | value %s | open %s', :'s1_w', :'s1_s', :'s1_p', :'s1_sc', :'s1_pg', left(:'s1_value', 80), left(:'s1_open', 80)));

\echo '── S2) 576 — P(cost 없음)가 CHG-79710 을 되돌리면 지금처럼 거부(landed 가 이미 얹혔다 · 판정은 postgres 로 센다) · 확정 그대로 · 얹힘 그대로'
set local role authenticated;
select pg_temp.as_user(:'p', format('select public.po_charge_confirm(%L::uuid, false)::text', :'c1')) as s2_rev \gset
reset role;
select pg_temp.chk('S2 576 closed: P reopening CHG-79710 is refused "already been added to stock cost (1 layer row(s))" · status still confirmed · landed add still 60',
  :'s2_rev' like 'ERR%' and :'s2_rev' like '%already been added to stock cost (1 layer row(s))%' and (select status from public.po_charge where id = :'c1'::uuid) = 'confirmed' and pg_temp.adds_of('CHG-79710') = 'RCV-79710/#=60:landed',
  format('rev %s | status %s | adds %s', left(:'s2_rev', 200), (select status from public.po_charge where id = :'c1'::uuid), pg_temp.adds_of('CHG-79710')));

\echo '── S2b) po_charge_confirm 반환 — P(cost 없음)가 새 비용 CHG-79711(40 CAD · PO-79710)을 확정하면 cost 에 금액 칸(amount_posted_cad · allocs …)이 없고 layers_touched · status · warnings 는 있다 · 얹힘은 그대로 40'
set local session_replication_role = replica;
insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, status) values (:'sup'::uuid, 'CHG-79711', :'d1'::date, 'duty', :'cad'::uuid, 40, 'draft') returning id::text as c2 \gset
insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (:'c2'::uuid, :'po1'::uuid, 40);
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'p', format('select public.po_charge_confirm(%L::uuid, true)::text', :'c2')) as ch2 \gset
reset role;
select pg_temp.chk('S2b po_charge_confirm as P after landing: CHG-79711 confirmed · landed 40 on the layer · returned cost has layers_touched 1 · no amount_posted_cad · no allocs · no late_*_cad',
  :'ch2' not like 'ERR%' and pg_temp.adds_of('CHG-79711') = 'RCV-79710/#=40:landed' and (pg_temp.j(:'ch2')->'cost'->>'layers_touched')::int = 1
  and not (pg_temp.j(:'ch2')->'cost' ? 'amount_posted_cad') and not (pg_temp.j(:'ch2')->'cost' ? 'allocs') and not (pg_temp.j(:'ch2')->'cost' ? 'late_sold_cad') and not (pg_temp.j(:'ch2')->'cost' ? 'deferred_amount_cad'),
  format('ch2 %s | adds %s', left(:'ch2', 300), pg_temp.adds_of('CHG-79711')));

\echo '── S3) so_stock_short_list — S 와 SC: unchecked 수 · 줄 수 · cost_source · unknown 같음 · unit_cost 는 S 에게 null · SC 에게 값 · W → sales 문 거부'
set local role authenticated;
select pg_temp.as_user(:'s',  'select public.so_stock_short_list(''{}''::jsonb)::text') as s3_s \gset
select pg_temp.as_user(:'sc', 'select public.so_stock_short_list(''{}''::jsonb)::text') as s3_sc \gset
select pg_temp.as_user(:'w',  'select public.so_stock_short_list(''{}''::jsonb)::text') as s3_w \gset
reset role;
select (select string_agg(coalesce(e->>'doc_number', '') || ':' || coalesce(e->>'sku', '') || ':' || coalesce(e->>'cost_source', '') || ':' || coalesce(e->>'unknown', ''), ',' order by e->>'doc_number', e->>'sku') from jsonb_array_elements(pg_temp.j(:'s3_s')->'unchecked') e) as s3_s_rows,
       (select string_agg(coalesce(e->>'doc_number', '') || ':' || coalesce(e->>'sku', '') || ':' || coalesce(e->>'cost_source', '') || ':' || coalesce(e->>'unknown', ''), ',' order by e->>'doc_number', e->>'sku') from jsonb_array_elements(pg_temp.j(:'s3_sc')->'unchecked') e) as s3_sc_rows,
       (select count(*) from jsonb_array_elements(pg_temp.j(:'s3_s')->'unchecked') e where e->>'unit_cost' is not null) as s3_s_costs,
       (select count(*) from jsonb_array_elements(pg_temp.j(:'s3_sc')->'unchecked') e where e->>'unit_cost' is not null) as s3_sc_costs,
       coalesce((select e->>'unit_cost' from jsonb_array_elements(pg_temp.j(:'s3_sc')->'unchecked') e where e->>'doc_number' = 'RLS3B-SO1'), 'null') as s3_sc_fake \gset
select pg_temp.chk('S3 so_stock_short_list: S and SC get the same unchecked_count · same rows (doc · sku · cost_source · unknown) · S has 0 unit_cost values · SC has them all (fake RLS3B-SO1 = 1.23) · W refused by the sales gate',
  pg_temp.j(:'s3_s')->>'unchecked_count' = pg_temp.j(:'s3_sc')->>'unchecked_count' and (pg_temp.j(:'s3_s')->>'unchecked_count')::int >= 1
  and :'s3_s_rows' = :'s3_sc_rows' and :s3_s_costs = 0 and :s3_sc_costs = (pg_temp.j(:'s3_sc')->>'unchecked_count')::int and :'s3_sc_fake' = '1.23'
  and :'s3_w' like 'ERR%' and :'s3_w' like '%cannot view sales data%',
  format('S count %s | SC count %s | S costs %s | SC costs %s | fake %s | rows eq %s | W %s', pg_temp.j(:'s3_s')->>'unchecked_count', pg_temp.j(:'s3_sc')->>'unchecked_count', :s3_s_costs, :s3_sc_costs, :'s3_sc_fake', :'s3_s_rows' = :'s3_sc_rows', left(:'s3_w', 120)));

\echo '── S4) so_credit_detail(실제 크레딧 하나) — S 와 SC: 줄 · 원장 · layers 의 수량 같음 · layers[].unit_cost 는 S 에게 null · W → sales 문 거부'
set local role authenticated;
select pg_temp.as_user(:'s',  format('select public.so_credit_detail(%L::uuid)::text', :'real_credit')) as s4_s \gset
select pg_temp.as_user(:'sc', format('select public.so_credit_detail(%L::uuid)::text', :'real_credit')) as s4_sc \gset
select pg_temp.as_user(:'w',  format('select public.so_credit_detail(%L::uuid)::text', :'real_credit')) as s4_w \gset
reset role;
select (pg_temp.j(:'s4_s') - 'layers')::text = (pg_temp.j(:'s4_sc') - 'layers')::text as s4_same_rest,
       (select string_agg((e - 'unit_cost')::text, ',' order by e->>'id') from jsonb_array_elements(pg_temp.j(:'s4_s')->'layers') e) = (select string_agg((e - 'unit_cost')::text, ',' order by e->>'id') from jsonb_array_elements(pg_temp.j(:'s4_sc')->'layers') e) as s4_same_layers,
       (select count(*) from jsonb_array_elements(pg_temp.j(:'s4_s')->'layers') e where e->>'unit_cost' is not null) as s4_s_costs,
       (select count(*) from jsonb_array_elements(pg_temp.j(:'s4_sc')->'layers') e where e->>'unit_cost' is not null) as s4_sc_costs,
       jsonb_array_length(pg_temp.j(:'s4_sc')->'layers') as s4_n_layers \gset
select pg_temp.chk(format('S4 so_credit_detail: everything but layers identical for S and SC · layers identical except unit_cost · S 0 unit_cost of %s · SC all · W refused by the sales gate', :s4_n_layers),
  :'s4_same_rest' = 't' and :'s4_same_layers' = 't' and :s4_s_costs = 0 and :s4_sc_costs = :s4_n_layers and :s4_n_layers >= 1 and :'s4_w' like 'ERR%' and :'s4_w' like '%cannot view sales data%',
  format('rest eq %s | layers eq %s | S costs %s | SC costs %s | n %s | W %s', :'s4_same_rest', :'s4_same_layers', :s4_s_costs, :s4_sc_costs, :s4_n_layers, left(:'s4_w', 120)));

\echo '── S5) inv_adjust_eval — AR(cost 없음)이 조정 초안 + 줄(+10 found · 단가 없음) → preview: cost_branch layer_avg 는 AR · ARC 같고 avg_unit_cost 는 AR 에게 null · ARC 에게 2.5 · W 는 inv_adjust_eval 직접 호출 거부 · S5b AR 확정 → 레이어 10 @2.5 layer_avg(확정은 열쇠와 무관)'
set local role authenticated;
select pg_temp.as_user(:'ar', format('select public.inv_adjust_create(%L::uuid, ''rls-3b test'', null)::text', :'wh')) as ad0 \gset
reset role;
select round(sum(v.remaining_value) / sum(v.remaining_qty), 6)::text as exp_avg from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = 'RLS3B-P1' and y.warehouse = :'whname' and v.remaining_qty > 0 \gset
set local role authenticated;
select coalesce(pg_temp.j(:'ad0')->>'id', '00000000-0000-0000-0000-000000000000') as adj, coalesce(pg_temp.j(:'ad0')->>'adjust_number', '?') as adjno \gset
select pg_temp.as_user(:'ar', format('select public.inv_adjust_line_set(%L::uuid, %L::jsonb)::text', :'adj', json_build_object('sku', 'RLS3B-P1', 'bin', :'binaname', 'mode', 'delta', 'qty', 10, 'reason', 'found')::text)) as ad1 \gset
select pg_temp.as_user(:'ar',  format('select public.inv_adjust_preview(%L::uuid)::text', :'adj')) as s5_ar \gset
select pg_temp.as_user(:'arc', format('select public.inv_adjust_preview(%L::uuid)::text', :'adj')) as s5_arc \gset
select pg_temp.as_user(:'w',   format('select count(*)::text from public.inv_adjust_eval(%L::uuid)', :'adj')) as s5_w \gset
select pg_temp.as_user(:'ar',  format('select public.inv_adjust_confirm(%L::uuid)::text', :'adj')) as s5_cf \gset
reset role;
select coalesce(pg_temp.j(:'s5_ar')->'lines'->0->>'cost_branch', 'null') as s5_ar_branch, coalesce(pg_temp.j(:'s5_ar')->'lines'->0->>'avg_unit_cost', 'null') as s5_ar_avg,
       coalesce(pg_temp.j(:'s5_arc')->'lines'->0->>'cost_branch', 'null') as s5_arc_branch, coalesce(pg_temp.j(:'s5_arc')->'lines'->0->>'avg_unit_cost', 'null') as s5_arc_avg,
       ((pg_temp.j(:'s5_ar')->'lines'->0) - 'avg_unit_cost')::text = ((pg_temp.j(:'s5_arc')->'lines'->0) - 'avg_unit_cost')::text as s5_same \gset
select pg_temp.chk('S5 inv_adjust_eval via preview: AR and ARC lines identical except avg_unit_cost · cost_branch layer_avg for both · AR avg null · ARC avg = Σ remaining value ÷ Σ remaining qty of the SKU''s layers here (postgres) · W refused (stock_adjust gate) · S5b AR confirmed: layer 10 @ that average layer_avg on the adjustment (posting unaffected by the mask)',
  :'ad0' not like 'ERR%' and :'ad1' not like 'ERR%' and :'s5_same' = 't' and :'s5_ar_branch' = 'layer_avg' and :'s5_arc_branch' = 'layer_avg' and :'s5_ar_avg' = 'null' and :'s5_arc_avg' = :'exp_avg'
  and :'s5_w' like 'ERR%' and :'s5_w' like '%cannot view stock adjustments%' and :'s5_cf' not like 'ERR%'
  and pg_temp.layers_of(:'adjno') = '#:RLS3B-P1:10@' || trim_scale(:'exp_avg'::numeric) || ':layer_avg',
  format('ad0 %s | ad1 %s | same %s | AR %s/%s | ARC %s/%s | exp %s | W %s | cf %s | layers %s', left(:'ad0', 80), left(:'ad1', 100), :'s5_same', :'s5_ar_branch', :'s5_ar_avg', :'s5_arc_branch', :'s5_arc_avg', :'exp_avg', left(:'s5_w', 100), left(:'s5_cf', 160), pg_temp.layers_of(:'adjno')));

\echo '── S6) po_fx_cost_lines — W 거부(purchasing 문) · P 는 줄이 나온다(PO-79710 · CAD 라 target 0) · po_fx_cost_status(사슬 · P) affected false'
set local role authenticated;
select pg_temp.as_user(:'w', format('select count(*)::text from public.po_fx_cost_lines(%L::uuid)', :'po1')) as s6_w \gset
select pg_temp.as_user(:'p', format('select string_agg(line_no || '':'' || sku || '':'' || layers || '':'' || trim_scale(layer_qty) || '':'' || trim_scale(remaining_cad), '','') from public.po_fx_cost_lines(%L::uuid)', :'po1')) as s6_p \gset
select pg_temp.as_user(:'p', format('select public.po_fx_cost_status(%L::uuid)::text', :'po1')) as s6_st \gset
reset role;
select case when exists (select 1 from public.po_receipt_cost k where k.receipt_id = :'r1'::uuid and k.exchange_rate_source = 'po') then '600' else '0' end as exp_pin_qty \gset
select pg_temp.chk('S6 po_fx_cost_lines: W refused by the purchasing gate · P gets the line (1 layer · pinned qty = 600 if the receipt cost was pinned to the PO else 0 · remaining 0 — CAD order) · po_fx_cost_status for P: affected false · is_base true',
  :'s6_w' like 'ERR%' and :'s6_w' like '%cannot view purchasing data%' and :'s6_p' = '1:RLS3B-P1:1:' || :'exp_pin_qty' || ':0'
  and :'s6_st' not like 'ERR%' and pg_temp.j(:'s6_st')->>'affected' = 'false' and pg_temp.j(:'s6_st')->>'is_base' = 'true',
  format('W %s | P %s | exp pin %s | status %s', left(:'s6_w', 100), :'s6_p', :'exp_pin_qty', left(:'s6_st', 200)));

\echo '── S7) inv_transfer_detail(실제 트랜스퍼 하나) — P(transfer · cost 없음)와 SC(transfer + cost): carried · posted_cad 만 다르고(P null) 나머지 같음 · W → null(ims_can_view transfer 그대로)'
set local role authenticated;
select pg_temp.as_user(:'p',  format('select public.inv_transfer_detail(%L::uuid)::text', :'real_trf')) as s7_p \gset
select pg_temp.as_user(:'sc', format('select public.inv_transfer_detail(%L::uuid)::text', :'real_trf')) as s7_sc \gset
select pg_temp.as_user(:'w',  format('select coalesce(public.inv_transfer_detail(%L::uuid)::text, ''(null)'')', :'real_trf')) as s7_w \gset
reset role;
create function pg_temp.strip_cost(p jsonb) returns jsonb language sql as $$
  select jsonb_set(jsonb_set(p, '{freight,posted_cad}', 'null'::jsonb), '{freight,charges}', coalesce((select jsonb_agg(c - 'posted_cad') from jsonb_array_elements(p->'freight'->'charges') c), '[]'::jsonb))
         || jsonb_build_object('lines', (select coalesce(jsonb_agg(l - 'carried' order by (l->>'line_no')::int), '[]'::jsonb) from jsonb_array_elements(p->'lines') l)) $$;
select (select count(*) from jsonb_array_elements(pg_temp.j(:'s7_p')->'lines') l where l->'carried'->>'total' is not null) as s7_p_carried,
       (select count(*) from jsonb_array_elements(pg_temp.j(:'s7_sc')->'lines') l where l->'carried'->>'total' is not null) as s7_sc_carried,
       jsonb_array_length(pg_temp.j(:'s7_sc')->'lines') as s7_n_lines,
       (pg_temp.j(:'s7_p')->'freight'->>'posted_cad' is null) as s7_p_posted_null, (pg_temp.j(:'s7_sc')->'freight'->>'posted_cad' is not null) as s7_sc_posted_num,
       pg_temp.strip_cost(pg_temp.j(:'s7_p'))::text = pg_temp.strip_cost(pg_temp.j(:'s7_sc'))::text as s7_same \gset
select pg_temp.chk(format('S7 inv_transfer_detail: P and SC identical after removing carried · posted_cad · P carried.total null on all %s lines · SC numeric on all · P freight.posted_cad null · SC numeric · W gets null (transfer gate as before)', :s7_n_lines),
  :'s7_same' = 't' and :s7_n_lines >= 1 and :s7_p_carried = 0 and :s7_sc_carried = :s7_n_lines and :'s7_p_posted_null' = 't' and :'s7_sc_posted_num' = 't' and :'s7_w' = '(null)',
  format('same %s | n %s | P carried %s | SC carried %s | P posted null %s | SC posted num %s | W %s', :'s7_same', :s7_n_lines, :s7_p_carried, :s7_sc_carried, :'s7_p_posted_null', :'s7_sc_posted_num', left(:'s7_w', 60)));

\echo '── S8) 살아야 하는 길 — S(sales · cost 없음): so_create → so_line_add(RLS3B-P1 5 EA @9) → so_confirm(allocated) → packed(replica · WMS 건너뜀) → Ship & invoice(so_finalize · 칸 A) → 원장 −5 · 레이어 소진 fifo 5 @2.5(inv_post_sale → fifo_take → inv_layer_value 가 definer 사슬 안에서 돈다)'
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''rls-3b test'')::text', :'cust', :'wh')) as so0 \gset
select coalesce(pg_temp.j(:'so0')->>'id', '00000000-0000-0000-0000-000000000000') as so1, coalesce(pg_temp.j(:'so0')->>'so_number', '?') as sono \gset
select pg_temp.as_user(:'s', format('select public.so_line_add(%L::uuid, %L::uuid, 5, 9.00, null, null, null, false)::text', :'so1', :'p1')) as so_l \gset
select coalesce(pg_temp.j(:'so_l')->'line'->>'id', '00000000-0000-0000-0000-000000000000') as sl1 \gset
reset role;
set local session_replication_role = replica;
update public.so set tax_rule_id = :'tax_rule'::uuid, tax_rule = :'tax_rule_name', tax_rule_manual = true where id = :'so1'::uuid;
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_confirm(%L::uuid, null, false, true)::text', :'so1')) as so_c \gset
reset role;
set local session_replication_role = replica;
update public.so set status = 'packed' where id = :'so1'::uuid and status = 'confirmed';
set local session_replication_role = origin;
select (select count(*) from public.inv_layer_consume c join public.inv_layer x on x.id = c.layer_id where x.doc_number = 'RCV-79710') as n_con0 \gset
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_finalize(%L::jsonb, true, null)::text', json_build_array(json_build_object('so_id', :'so1', 'picks', json_build_array(json_build_object('line_id', :'sl1', 'bin', :'binaname', 'qty', 5))))::text)) as s8_fin \gset
reset role;
select pg_temp.chk('S8 Ship & invoice as S (no cost key): order created · line · confirmed (allocated) · shipped · invoice issued · ledger −5 · RCV-79710 layer consumed sale 5 × (unit cost + landed share) · inv_layer_consume +1',
  :'so0' not like 'ERR%' and :'so_l' not like 'ERR%' and :'so_c' not like 'ERR%' and :'s8_fin' not like 'ERR%' and (pg_temp.j(:'s8_fin')->>'invoice_count')::int = 1 and (select status from public.so where id = :'so1'::uuid) in ('shipped', 'fulfilled')
  and (select coalesce(sum(l.qty_delta), 0) from public.inv_ledger l where l.doc_number = :'sono' and l.sku = 'RLS3B-P1') = -5
  and pg_temp.consumes_of('RCV-79710') ~ '^sale:5@[0-9.]+$' and (select count(*) from public.inv_layer_consume c join public.inv_layer x on x.id = c.layer_id where x.doc_number = 'RCV-79710') = :n_con0 + 1,
  format('so0 %s | line %s | confirm %s | fin %s | so %s | ledger %s | consumes %s', left(:'so0', 80), left(:'so_l', 80), left(:'so_c', 120), left(:'s8_fin', 200), (select status from public.so where id = :'so1'::uuid), (select coalesce(sum(l.qty_delta), 0) from public.inv_ledger l where l.doc_number = :'sono'), pg_temp.consumes_of('RCV-79710')));

\echo '── S9) 살아야 하는 길 — S(cost 없음): 크레딧(2 EA 되돌아옴 · 칸 A 재입고) so_credit_issue → 크레딧 레이어 2(inv_post_credit → inv_layer_post_credit → inv_layer_value)'
select coalesce(pg_temp.j(:'s8_fin')->'invoices'->0->>'invoice_id', '00000000-0000-0000-0000-000000000000') as inv1 \gset
select coalesce((select l.id::text from public.so_invoice_line l where l.invoice_id = :'inv1'::uuid and l.kind = 'product' order by l.line_no limit 1), '00000000-0000-0000-0000-000000000000') as il1 \gset
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_credit_issue(%L::jsonb, true)::text', json_build_object('invoice_id', :'inv1', 'reason', 'customer_return', 'warehouse_id', :'wh', 'lines', json_build_array(json_build_object('kind', 'product', 'so_invoice_line_id', :'il1', 'qty_returned', 2, 'restock_bin', :'binaname')))::text)) as s9_cr \gset
reset role;
select coalesce(pg_temp.j(:'s9_cr')->>'credit_number', '?') as crno \gset
select pg_temp.chk('S9 credit as S (no cost key): credit issued · creditnote layer 2 EA for RLS3B-P1 · ledger +2',
  :'s9_cr' not like 'ERR%' and :'crno' <> '?' and (select count(*) from public.inv_layer y where y.origin_type = 'creditnote' and y.doc_number = :'crno' and y.sku = 'RLS3B-P1' and y.qty = 2) = 1
  and (select coalesce(sum(l.qty_delta), 0) from public.inv_ledger l where l.doc_number = :'crno' and l.sku = 'RLS3B-P1') = 2,
  format('cr %s | layers %s', left(:'s9_cr', 240), pg_temp.layers_of(:'crno')));

\echo '── S10) 부르는 쪽 전수(pg_proc): authenticated 가 부를 수 있는 invoker 중 다섯 표 · inv_layer_open · inv_layer_value 를 읽는 것 0 · product_supplier 를 읽는 invoker 는 여섯(의도 · 이견 0)'
select pg_temp.chk('S10 no authenticated-callable invoker reads the five ledger-cost tables · inv_layer_open · inv_layer_value · product_supplier invoker readers = po_lines_paste price_formula_preview product_list so_backorder_arrivals so_backorder_demand so_backorder_overview',
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and not p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute')
     and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ '\m(inv_layer_open|inv_layer_value|inv_layer_cost_add|inv_layer_consume|inv_layer|inv_cost|inv_doc_cost)\M') = 0
  and (select string_agg(p.proname, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and not p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute')
     and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ '\mproduct_supplier\M') = 'po_lines_paste price_formula_preview product_list so_backorder_arrivals so_backorder_demand so_backorder_overview',
  format('cost readers %s | ps readers %s',
    (select string_agg(p.proname, ' ') from pg_proc p where p.pronamespace = 'public'::regnamespace and not p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute') and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ '\m(inv_layer_open|inv_layer_value|inv_layer_cost_add|inv_layer_consume|inv_layer|inv_cost|inv_doc_cost)\M'),
    (select string_agg(p.proname, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and not p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute') and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ '\mproduct_supplier\M')));

\echo '── S11) 화면이 받는 모양 — S 판과 SC 판의 null 칸(대화 Claude 가 화면을 고칠 재료 · 판정 아님)'
select 'so_stock_short_list unchecked[0] S:  ' || coalesce((pg_temp.j(:'s3_s')->'unchecked'->0)::text, '-') as shape union all
select 'so_stock_short_list unchecked[0] SC: ' || coalesce((pg_temp.j(:'s3_sc')->'unchecked'->0)::text, '-') union all
select 'so_credit_detail layers[0] S:  ' || coalesce((pg_temp.j(:'s4_s')->'layers'->0)::text, '-') union all
select 'so_credit_detail layers[0] SC: ' || coalesce((pg_temp.j(:'s4_sc')->'layers'->0)::text, '-') union all
select 'inv_adjust_preview lines[0] AR:  ' || coalesce((pg_temp.j(:'s5_ar')->'lines'->0)::text, '-') union all
select 'inv_adjust_preview lines[0] ARC: ' || coalesce((pg_temp.j(:'s5_arc')->'lines'->0)::text, '-') union all
select 'inv_transfer_detail lines[0].carried P:  ' || coalesce((pg_temp.j(:'s7_p')->'lines'->0->'carried')::text, '-') || ' · freight.posted_cad ' || coalesce(pg_temp.j(:'s7_p')->'freight'->>'posted_cad', 'null') union all
select 'inv_transfer_detail lines[0].carried SC: ' || coalesce((pg_temp.j(:'s7_sc')->'lines'->0->'carried')::text, '-') || ' · freight.posted_cad ' || coalesce(pg_temp.j(:'s7_sc')->'freight'->>'posted_cad', 'null') union all
select 'po_charge_confirm(confirm) cost P (after landing · CHG-79711): ' || coalesce((pg_temp.j(:'ch2')->'cost')::text, '-');
\else
select pg_temp.chk('G1 ~ S11 skipped: rls-3b not landed (select policies still true)', false, 'not landed — nothing to exercise');
\endif

\echo '── Z1) 실제 행 무접촉(가짜 RLS3B- 제외)'
select pg_temp.chk('Z1 real rows untouched (layers · adds · consumes · inv_cost · inv_doc_cost · product_supplier · ledger · so · invoices)', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 시퀀스 되돌리기(죽은 회차가 당겼으면 greatest(실제 최대, 머리))'
select (select count(*) from public.po where po_number = 'PO-79710') + (select count(*) from public.so where customer_id in (select id from public.customer where name = 'RLS3B Customer')) + (select count(*) from public.inv_layer where sku like 'RLS3B-%' or doc_number = 'RLS3B-SO1')
     + (select count(*) from public.ims_staff where email like 'rls3b-%') + (select count(*) from public.product where sku like 'RLS3B-%') + (select count(*) from public.customer where name = 'RLS3B Customer') as fake_traces_left;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(invoice_number)::bigint from public.so_invoice), 0), :inv_seq_last), :'inv_seq_called'::boolean) as so_invoice_number_seq_reset_to;
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select setval('public.so_credit_number_seq', greatest(coalesce((select max(substring(credit_number from '[0-9]+')::bigint) from public.so_credit), 0), :cr_seq_last), :'cr_seq_called'::boolean) as so_credit_number_seq_reset_to;
select setval('public.inv_adjust_number_seq', greatest(coalesce((select max(substring(adjust_number from '[0-9]+')::bigint) from public.inv_adjust), 0), :adj_seq_last), :'adj_seq_called'::boolean) as inv_adjust_number_seq_reset_to;
select (select last_value || '/' || is_called from public.so_invoice_number_seq) as inv_seq_after, (select last_value || '/' || is_called from public.so_number_seq) as so_seq_after, (select last_value || '/' || is_called from public.so_credit_number_seq) as cr_seq_after, (select last_value || '/' || is_called from public.inv_adjust_number_seq) as adj_seq_after;
