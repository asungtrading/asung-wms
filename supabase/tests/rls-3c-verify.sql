-- rls-3c-verify.sql — Backorders 함수 셋 invoker → definer + sales 보기 문(판정 583): 결함 재현(S0 · 시험 전용) · S 의 반환 = SP 의 반환(S2 — 공급처 말고 새로 보이는 것 없음) ·
--   S 적용 전 / 뒤 공급처 칸만 다름(S3) · 공급처 거르기(S4) · W 거부(S5) · 단가 칸 없음(S6) · 호출 가능한 invoker product_supplier 읽기 셋만(S7) · 무접촉(G0 · G1 · Z1)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261021135919_rls_3c_backorder_definer.sql -f supabase/tests/rls-3c-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · S3 셋은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 12 − 3 + 1 = **10** · MISMATCH 0
--   가짜 재료는 전부 RLS3C-/7972x · 가짜 직원 넷(W · S · SP · O) · 번호 시퀀스 so_number_seq(S 의 so_create · 백오더 분할)는 머리에서 읽고 rollback 뒤 greatest(실제 최대, 머리)
--   ⚠️ 창고 접근(ims_can_warehouse)은 셋이 안 쓴다(§1 실측) — S1(창고 하나) 꼴은 없다

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261021135919' \gset
select :n_applied as schema_migrations_rows_for_20261021135919;
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select :so_seq_last as so_number_seq_head, :'so_seq_called' as so_called_head, (select max(substring(so_number from '[0-9]+')::bigint) from public.so) as so_max_head;

begin;
set local statement_timeout = '600s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- jsonb 에서 키들을 재귀로 뺀다(공급처 칸 · elapsed_ms)
-- 셋을 역할(claims)로 부른다
create function pg_temp.call(p_claims text, p_fn text, p_filters jsonb) returns text language plpgsql as $$
begin
  return pg_temp.as_user(p_claims, format('select public.%I(%L::jsonb)::text', p_fn, p_filters));
end $$;
create function pg_temp.strip(p jsonb, p_keys text[]) returns jsonb language plpgsql immutable as $$
declare r jsonb; k text; v jsonb;
begin
  if p is null then return null; end if;
  if jsonb_typeof(p) = 'object' then
    r := '{}'::jsonb;
    for k, v in select * from jsonb_each(p) loop
      if not (k = any(p_keys)) then r := r || jsonb_build_object(k, pg_temp.strip(v, p_keys)); end if;
    end loop;
    return r;
  elsif jsonb_typeof(p) = 'array' then
    return coalesce((select jsonb_agg(pg_temp.strip(e, p_keys)) from jsonb_array_elements(p) e), '[]'::jsonb);
  else
    return p;
  end if;
end $$;
-- jsonb 의 모든 키(재귀)
create function pg_temp.keys(p jsonb) returns setof text language sql immutable as $$
  select k from jsonb_each(case when jsonb_typeof(p) = 'object' then p else '{}'::jsonb end) e(k, v)
  union
  select pg_temp.keys(v) from jsonb_each(case when jsonb_typeof(p) = 'object' then p else '{}'::jsonb end) e(k, v) where jsonb_typeof(v) in ('object', 'array')
  union
  select pg_temp.keys(e) from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) e where jsonb_typeof(e) in ('object', 'array') $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'definer=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.proname in ('so_backorder_arrivals', 'so_backorder_demand', 'so_backorder_overview'))
      || ' gated=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_backorder_arrivals', 'so_backorder_demand', 'so_backorder_overview') and p.prosrc ~ E'\nbegin\n  if not public\\.ims_can_view\\(''sales''\\)')
      || ' ps_invoker_readers=' || (select string_agg(p.proname, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and not p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute') and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ '\mproduct_supplier\M') $$;
-- 무접촉 집합(마이그레이션 ⓪ 과 같은 식 · 몸은 문 줄을 뺀 md5)
create function pg_temp.untouched_md5() returns text language sql security definer as $$
  select md5(string_agg(k, ',' order by k)) from (
    select 'pol:' || tablename || ':' || policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual, '-') || ':' || coalesce(with_check, '-') as k
      from pg_policies where schemaname = 'public' and (tablename like 'wms\_%' or tablename like 'inv\_%' or tablename = 'product_supplier')
    union all
    select 'grant:' || table_name || ':' || grantee || ':' || privilege_type
      from information_schema.role_table_grants where table_schema = 'public' and (table_name like 'wms\_%' or table_name like 'inv\_%' or table_name = 'product_supplier')
    union all
    select 'fn:' || p.proname || ':' || coalesce(p.proacl::text, '-')
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_carry', 'inv_layer_cost_add_settle', 'inv_snap_balance_diffs', 'inv_compare_run', 'inv_ack_diff', 'tf_charge_confirm', 'tf_charge_update', 'tf_charge_delete', 'tf_charge_alloc_add', 'tf_charge_alloc_update', 'tf_charge_alloc_delete',
                                                                             'so_stock_short_list', 'so_credit_detail', 'po_fx_cost_lines', 'inv_adjust_eval', 'po_charge_confirm', 'inv_transfer_detail', 'inv_layer_value', 'ims_require_ok',
                                                                             'so_backorder_arrivals', 'so_backorder_demand', 'so_backorder_overview')
    union all
    select 'body:' || p.proname || ':' || md5(regexp_replace(p.prosrc, E'\n  if not public\\.ims_can_view\\(''sales''\\)[^\n]*', '', '')) || ':' || coalesce(obj_description(p.oid, 'pg_proc'), '-')
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_backorder_arrivals', 'so_backorder_demand', 'so_backorder_overview')
  ) s $$;
create function pg_temp.real_rows() returns text language sql security definer as $$
  select 'ps=' || (select count(*) || '/' || coalesce(sum(cost), 0) from public.product_supplier ps join public.product p on p.id = ps.product_id where p.sku not like 'RLS3C-%')
      || ' so=' || (select count(*) || '/' || coalesce(sum(substring(so_number from '[0-9]+')::bigint), 0) from public.so where customer_id not in (select c.id from public.customer c where c.name = 'RLS3C Customer'))
      || ' reserve=' || (select count(*) from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.sku not like 'RLS3C-%')
      || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where sku not like 'RLS3C-%')
      || ' po=' || (select count(*) from public.po where po_number not like 'PO-7972%') $$;
\set STRIP '''{supplier_id,supplier_name,supplier_basis,supplier_ids,elapsed_ms}''::text[]'

\echo '── M0) 가짜 직원 넷 — W 열쇠 없음 · S sales · SP sales + purchasing · O receiving + purchasing(입고 재료) · 참조 · 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls3c-w@test.invalid', 'RLS3C W', 'worker', '[]', '{}') returning auth_user_id::text as w_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls3c-s@test.invalid', 'RLS3C S', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as s_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls3c-sp@test.invalid', 'RLS3C SP', 'manager', '["ims","sales","purchasing"]', '{}') returning auth_user_id::text as sp_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls3c-o@test.invalid', 'RLS3C O', 'manager', '["ims","receiving","purchasing"]', '{}') returning auth_user_id::text as o_uid, id::text as o_id \gset
\set w  '{"sub":"' :w_uid  '","role":"authenticated"}'
\set s  '{"sub":"' :s_uid  '","role":"authenticated"}'
\set sp '{"sub":"' :sp_uid '","role":"authenticated"}'
\set o  '{"sub":"' :o_uid  '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select (public.ims_today() - 2)::text as d0 \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.id::text as bina, b.name as binaname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select rt.name as tier_name from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as tax_rule, name as tax_rule_name from public.ref_tax_rule where name = 'Exempt (Sale)' and is_active \gset
select pg_temp.real_rows() as real_before, pg_temp.untouched_md5() as untouched_before \gset
select pg_temp.chk(format('M0 staff ×4 · warehouse %s · bin %s · tier %s · tax %s · snapshots taken', :'whname', :'binaname', :'tier_name', :'tax_rule_name'),
  :'w_uid' <> '' and :'s_uid' <> '' and :'sp_uid' <> '' and :'o_uid' <> '' and :'wh' <> '' and :'bina' <> '' and :'tax_rule' <> '' and :'real_before' <> '' and :'untouched_before' <> '', 'see M0');

\echo '── M1) 가짜 재료 — 공급처 · 제품 RLS3C-P1(재고 0) · 기본 공급처 줄(단가 2.00 — 반환에 나오면 안 된다) · 손님 · S 가 오더 4 EA → 확정 → 전량 백오더 · O 가 PO-79720 100 EA(인보이스 확정 · Invoice First) 입고 확정(arrivals 줄 · 공급처 = PO 의 것)'
set local session_replication_role = replica;
insert into public.supplier (name, payment_term_name, account_payable_code) values ('RLS3C Supplier', 'Net 30', '2000') returning id::text as sup \gset
insert into public.product (sku, name, source) values ('RLS3C-P1', 'RLS3C P1', 'manual') returning id::text as p1 \gset
insert into public.product_supplier (product_id, supplier_id, supplier_sku, cost, fixed_cost, currency_id, is_default, is_active, source) values (:'p1'::uuid, :'sup'::uuid, 'RLS3C-SUP-1', 2.00, 1.50, :'cad'::uuid, true, true, 'manual') returning id::text as ps1 \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id) values ('RLS3C Customer', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid) returning id::text as cust \gset
insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values ('PO-79720', 'confirmed', :'sup'::uuid, :'cad'::uuid, null, :'d0', :'wh'::uuid, now()) returning id::text as po1 \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po1'::uuid, 1, :'p1'::uuid, 100, 2.00) returning id::text as l1 \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at) values (:'sup'::uuid, 'RLS3C-I1', :'d0', :'cad'::uuid, null, 200, 'confirmed', 'invoice', now()) returning id::text as i1 \gset
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (:'i1'::uuid, 1, 'goods', :'l1'::uuid, 100, 2.00, true);
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by) values ('RCV-79720', :'po1'::uuid, :'wh'::uuid, :'d0'::date, 'draft', :'o_id'::uuid) returning id::text as r1 \gset
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''rls-3c test'')::text', :'cust', :'wh')) as so0 \gset
select coalesce(pg_temp.j(:'so0')->>'id', '00000000-0000-0000-0000-000000000000') as so1, coalesce(pg_temp.j(:'so0')->>'so_number', '?') as sono \gset
select pg_temp.as_user(:'s', format('select public.so_line_add(%L::uuid, %L::uuid, 4, 9.00, null, null, null, false)::text', :'so1', :'p1')) as so_l \gset
reset role;
set local session_replication_role = replica;
update public.so set tax_rule_id = :'tax_rule'::uuid, tax_rule = :'tax_rule_name', tax_rule_manual = true where id = :'so1'::uuid;
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_confirm(%L::uuid, null, false, true)::text', :'so1')) as so_c \gset
select pg_temp.as_user(:'o', format('select public.po_receipt_work_save(%L::uuid, %L::uuid, 100, ''manual'')::text', :'r1', :'l1')) as sv1 \gset
select coalesce(pg_temp.j(:'sv1')->>'work_id', '00000000-0000-0000-0000-000000000000') as w1 \gset
select pg_temp.as_user(:'o', format('select public.po_receipt_work_putaway(%L::uuid, %L::uuid, true)::text', :'w1', :'bina')) as pa1 \gset
select pg_temp.as_user(:'o', format('select public.po_receipt_confirm(%L::uuid)::text', :'r1')) as cf1 \gset
reset role;
select pg_temp.chk(format('M1 fixtures: %s confirmed with a backorder reserve of 4 for RLS3C-P1 · default supplier link (cost 2.00 · fixed 1.50) · RCV-79720 confirmed → ledger +100', :'sono'),
  :'so0' not like 'ERR%' and :'so_l' not like 'ERR%' and :'so_c' not like 'ERR%' and :'cf1' not like 'ERR%' and :'ps1' <> ''
  and (select coalesce(sum(r.qty_allocated), 0) from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.sku = 'RLS3C-P1' and r.kind = 'backorder' and r.released_at is null) = 4
  and (select coalesce(sum(l.qty_delta), 0) from public.inv_ledger l where l.doc_number = 'RCV-79720') = 100,
  format('so0 %s | line %s | confirm %s | sv1 %s | pa1 %s | cf1 %s | reserve %s', left(:'so0', 80), left(:'so_l', 80), left(:'so_c', 200), left(:'sv1', 60), left(:'pa1', 60), left(:'cf1', 120),
    (select coalesce(sum(r.qty_allocated), 0) from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.sku = 'RLS3C-P1' and r.kind = 'backorder' and r.released_at is null)));

\echo '── B0) 적용 전 S 의 반환 셋(어느 갈래든 받아 둔다 — 시험 갈래 S3 가 비교한다)'
set local role authenticated;
select pg_temp.call(:'s', 'so_backorder_demand', '{}'::jsonb) as b_dem \gset
select pg_temp.call(:'s', 'so_backorder_overview', '{}'::jsonb) as b_ov \gset
select pg_temp.call(:'s', 'so_backorder_arrivals', '{}'::jsonb) as b_arr \gset
select pg_temp.call(:'s', 'so_backorder_demand', jsonb_build_object('supplier_id', :'sup')) as b_dem_sup \gset
select pg_temp.call(:'s', 'so_backorder_overview', jsonb_build_object('supplier_id', :'sup')) as b_ov_sup \gset
select pg_temp.call(:'s', 'so_backorder_demand', '{"supplier_id":"none"}'::jsonb) as b_dem_none \gset
select pg_temp.call(:'sp', 'so_backorder_demand', '{}'::jsonb) as b_dem_sp \gset
reset role;

\if :{?mig}
\echo '── S0) 결함 재현(시험 전용) — S(sales 만): demand · overview · arrivals 의 RLS3C-P1 줄에 supplier_name 이 없다 · 공급처 거르기 0 줄 · 「none」 거르기에는 나온다 · SP 는 이름이 나온다'
select pg_temp.gate_state() as gate_before \gset
select (select r->>'supplier_name' from jsonb_array_elements(pg_temp.j(:'b_dem')->'rows') r where r->>'sku' = 'RLS3C-P1' limit 1) is null as s0_dem_null,
       (select r->>'supplier_name' from jsonb_array_elements(pg_temp.j(:'b_ov')->'rows') r where r->>'sku' = 'RLS3C-P1' limit 1) is null as s0_ov_null,
       (select count(*) from jsonb_array_elements(pg_temp.j(:'b_arr')->'rows') r where r->>'sku' = 'RLS3C-P1') as s0_arr_rows,
       (select coalesce(r->>'supplier_basis', 'null') from jsonb_array_elements(pg_temp.j(:'b_arr')->'rows') r where r->>'sku' = 'RLS3C-P1' limit 1) as s0_arr_basis,
       (select count(*) from jsonb_array_elements(pg_temp.j(:'b_dem_sup')->'rows') r where r->>'sku' = 'RLS3C-P1') as s0_dem_sup_n,
       (select count(*) from jsonb_array_elements(pg_temp.j(:'b_ov_sup')->'rows') r where r->>'sku' = 'RLS3C-P1') as s0_ov_sup_n,
       (select count(*) from jsonb_array_elements(pg_temp.j(:'b_dem_none')->'rows') r where r->>'sku' = 'RLS3C-P1') as s0_dem_none_n,
       (select coalesce(r->>'supplier_name', 'null') from jsonb_array_elements(pg_temp.j(:'b_dem_sp')->'rows') r where r->>'sku' = 'RLS3C-P1' limit 1) as s0_dem_sp \gset
select pg_temp.chk('S0 before the trial: S gets no supplier_name on the RLS3C-P1 row (demand · overview) · supplier filter → 0 rows (demand · overview) · "none" filter shows it · SP sees "RLS3C Supplier" · arrivals row present with basis po (PO-based — not affected) · invoker ×3 · not in schema_migrations',
  :'s0_dem_null' = 't' and :'s0_ov_null' = 't' and :s0_dem_sup_n = 0 and :s0_ov_sup_n = 0 and :s0_dem_none_n = 1 and :'s0_dem_sp' = 'RLS3C Supplier' and :s0_arr_rows = 1 and :'s0_arr_basis' = 'po'
  and :'gate_before' like 'definer=0 gated=0 %' and :n_applied = 0,
  format('dem null %s | ov null %s | sup n %s/%s | none n %s | sp %s | arr rows %s basis %s | gate %s | n_applied %s', :'s0_dem_null', :'s0_ov_null', :s0_dem_sup_n, :s0_ov_sup_n, :s0_dem_none_n, :'s0_dem_sp', :s0_arr_rows, :'s0_arr_basis', :'gate_before', :n_applied));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: untouched set (policies · grants · 23 fn ACLs · 3 comments · bodies minus the gate line) same', pg_temp.untouched_md5() = :'untouched_before', format('before %s | after %s', :'untouched_before', pg_temp.untouched_md5()));
\else
select pg_temp.chk('P0c confirm run: migration 20261021135919 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() like 'definer=3 gated=3 %') as landed \gset
\if :landed
\echo '── G1) 실물 — definer 3 · 첫 줄 문 3 · authenticated 가 부를 수 있는 invoker 중 product_supplier 를 읽는 것 = po_lines_paste · price_formula_preview · product_list'
select pg_temp.chk('G1 gate state exact', pg_temp.gate_state() = 'definer=3 gated=3 ps_invoker_readers=po_lines_paste,price_formula_preview,product_list', pg_temp.gate_state());

\echo '── S2) 적용 뒤 — S 의 반환 = SP 의 반환(셋 · elapsed_ms 만 빼고 전체 글 같음) · RLS3C-P1 줄에 supplier_name "RLS3C Supplier"(demand · overview)'
set local role authenticated;
select pg_temp.call(:'s', 'so_backorder_demand', '{}'::jsonb) as a_dem \gset
select pg_temp.call(:'s', 'so_backorder_overview', '{}'::jsonb) as a_ov \gset
select pg_temp.call(:'s', 'so_backorder_arrivals', '{}'::jsonb) as a_arr \gset
select pg_temp.call(:'sp', 'so_backorder_demand', '{}'::jsonb) as a_dem_sp \gset
select pg_temp.call(:'sp', 'so_backorder_overview', '{}'::jsonb) as a_ov_sp \gset
select pg_temp.call(:'sp', 'so_backorder_arrivals', '{}'::jsonb) as a_arr_sp \gset
reset role;
select (pg_temp.strip(pg_temp.j(:'a_dem'), '{elapsed_ms}')::text = pg_temp.strip(pg_temp.j(:'a_dem_sp'), '{elapsed_ms}')::text) as s2_dem_eq,
       (pg_temp.strip(pg_temp.j(:'a_ov'),  '{elapsed_ms}')::text = pg_temp.strip(pg_temp.j(:'a_ov_sp'),  '{elapsed_ms}')::text) as s2_ov_eq,
       (pg_temp.strip(pg_temp.j(:'a_arr'), '{elapsed_ms}')::text = pg_temp.strip(pg_temp.j(:'a_arr_sp'), '{elapsed_ms}')::text) as s2_arr_eq,
       jsonb_array_length(pg_temp.j(:'a_dem')->'rows') as s2_dem_n, jsonb_array_length(pg_temp.j(:'a_ov')->'rows') as s2_ov_n, jsonb_array_length(pg_temp.j(:'a_arr')->'rows') as s2_arr_n,
       (select coalesce(r->>'supplier_name', 'null') from jsonb_array_elements(pg_temp.j(:'a_dem')->'rows') r where r->>'sku' = 'RLS3C-P1' limit 1) as s2_dem_name,
       (select coalesce(r->>'supplier_name', 'null') from jsonb_array_elements(pg_temp.j(:'a_ov')->'rows') r where r->>'sku' = 'RLS3C-P1' limit 1) as s2_ov_name \gset
select pg_temp.chk(format('S2 after: S = SP for demand (%s rows) · overview (%s rows) · arrivals (%s rows) — whole jsonb minus elapsed_ms · RLS3C-P1 supplier_name "RLS3C Supplier" in demand and overview', :s2_dem_n, :s2_ov_n, :s2_arr_n),
  :'a_dem' not like 'ERR%' and :'a_ov' not like 'ERR%' and :'a_arr' not like 'ERR%' and :'s2_dem_eq' = 't' and :'s2_ov_eq' = 't' and :'s2_arr_eq' = 't'
  and :'s2_dem_name' = 'RLS3C Supplier' and :'s2_ov_name' = 'RLS3C Supplier' and :s2_dem_n >= 1 and :s2_ov_n >= 1 and :s2_arr_n >= 1,
  format('eq %s/%s/%s | names %s/%s | a_dem %s', :'s2_dem_eq', :'s2_ov_eq', :'s2_arr_eq', :'s2_dem_name', :'s2_ov_name', left(:'a_dem', 160)));

\if :{?mig}
\echo '── S3) 시험 전용 — S 의 적용 뒤 반환에서 공급처 칸(supplier_id · supplier_name · supplier_basis · supplier_ids) · elapsed_ms 를 빼면 적용 전과 같다(숫자 · 줄 · 손님 무변 · 셋)'
select (pg_temp.strip(pg_temp.j(:'a_dem'), :STRIP)::text = pg_temp.strip(pg_temp.j(:'b_dem'), :STRIP)::text) as s3_dem,
       (pg_temp.strip(pg_temp.j(:'a_ov'),  :STRIP)::text = pg_temp.strip(pg_temp.j(:'b_ov'),  :STRIP)::text) as s3_ov,
       (pg_temp.strip(pg_temp.j(:'a_arr'), :STRIP)::text = pg_temp.strip(pg_temp.j(:'b_arr'), :STRIP)::text) as s3_arr \gset
select pg_temp.chk('S3 S before = S after once supplier columns and elapsed_ms are removed (demand · overview · arrivals) — nothing but the supplier became visible',
  :'s3_dem' = 't' and :'s3_ov' = 't' and :'s3_arr' = 't', format('dem %s | ov %s | arr %s', :'s3_dem', :'s3_ov', :'s3_arr'));
\endif

\echo '── S4) 공급처 거르기 — S 가 RLS3C Supplier 로 거르면 demand · overview · arrivals 에 RLS3C-P1 줄이 나온다 · 「none」 거르기에는 안 나온다'
set local role authenticated;
select pg_temp.call(:'s', 'so_backorder_demand', jsonb_build_object('supplier_id', :'sup')) as a_dem_sup \gset
select pg_temp.call(:'s', 'so_backorder_overview', jsonb_build_object('supplier_id', :'sup')) as a_ov_sup \gset
select pg_temp.call(:'s', 'so_backorder_arrivals', jsonb_build_object('supplier_id', :'sup')) as a_arr_sup \gset
select pg_temp.call(:'s', 'so_backorder_demand', '{"supplier_id":"none"}'::jsonb) as a_dem_none \gset
reset role;
select (select count(*) from jsonb_array_elements(pg_temp.j(:'a_dem_sup')->'rows') r where r->>'sku' = 'RLS3C-P1') as s4_dem,
       (select count(*) from jsonb_array_elements(pg_temp.j(:'a_ov_sup')->'rows') r where r->>'sku' = 'RLS3C-P1') as s4_ov,
       (select count(*) from jsonb_array_elements(pg_temp.j(:'a_arr_sup')->'rows') r where r->>'sku' = 'RLS3C-P1') as s4_arr,
       (select count(*) from jsonb_array_elements(pg_temp.j(:'a_dem_none')->'rows') r where r->>'sku' = 'RLS3C-P1') as s4_none \gset
select pg_temp.chk('S4 supplier filter as S: RLS3C-P1 row present in demand · overview · arrivals when filtering by RLS3C Supplier · absent under "none"',
  :s4_dem = 1 and :s4_ov = 1 and :s4_arr = 1 and :s4_none = 0, format('dem %s | ov %s | arr %s | none %s', :s4_dem, :s4_ov, :s4_arr, :s4_none));

\echo '── S5) W(열쇠 없음) — 셋 모두 거부(P0001 · 영문 문장)'
set local role authenticated;
select pg_temp.call(:'w', 'so_backorder_demand', '{}'::jsonb) as w_dem \gset
select pg_temp.call(:'w', 'so_backorder_overview', '{}'::jsonb) as w_ov \gset
select pg_temp.call(:'w', 'so_backorder_arrivals', '{}'::jsonb) as w_arr \gset
reset role;
select pg_temp.chk('S5 W refused by the sales gate on all three (P0001 "You cannot view sales data")',
  :'w_dem' like 'ERR P0001%' and :'w_dem' like '%cannot view sales data%' and :'w_ov' like 'ERR P0001%' and :'w_ov' like '%cannot view sales data%' and :'w_arr' like 'ERR P0001%' and :'w_arr' like '%cannot view sales data%',
  format('dem %s | ov %s | arr %s', left(:'w_dem', 100), left(:'w_ov', 100), left(:'w_arr', 100)));

\echo '── S6) 반환에 단가 · 원가 칸 0 — 세 반환의 모든 키(재귀)에 cost · fixed_cost · unit_cost · price_formula_id 없음(unit_price 는 so_line 의 판매가)'
select coalesce((select string_agg(distinct k, ',') from (select pg_temp.keys(pg_temp.j(:'a_dem')) k union select pg_temp.keys(pg_temp.j(:'a_ov')) union select pg_temp.keys(pg_temp.j(:'a_arr'))) x where k ~ '^(cost|fixed_cost|unit_cost|price_formula_id|supplier_sku)$'), '') as s6_bad \gset
select pg_temp.chk('S6 no product_supplier price columns in the three returns (keys cost · fixed_cost · unit_cost · price_formula_id · supplier_sku absent)', :'s6_bad' = '', format('bad keys: %s', :'s6_bad'));

\echo '── S7) 부르는 쪽 전수 — authenticated 가 부를 수 있는 invoker 중 product_supplier 를 읽는 것 셋만 · 셋의 ACL · comment 그대로'
select pg_temp.chk('S7 invoker product_supplier readers = po_lines_paste price_formula_preview product_list · three functions keep ACL (postgres · authenticated · service_role) and comments',
  (select string_agg(p.proname, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and not p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute') and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ '\mproduct_supplier\M') = 'po_lines_paste price_formula_preview product_list'
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_backorder_arrivals', 'so_backorder_demand', 'so_backorder_overview') and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' and obj_description(p.oid, 'pg_proc') is not null) = 3,
  (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-'), ' ') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_backorder_arrivals', 'so_backorder_demand', 'so_backorder_overview')));
\else
select pg_temp.chk('G1 ~ S7 skipped: rls-3c not landed (three still invoker)', false, 'not landed — nothing to exercise');
\endif

\echo '── Z1) 실제 행 무접촉(가짜 RLS3C- 제외)'
select pg_temp.chk('Z1 real rows untouched (product_supplier · so · so_reserve · ledger · po)', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · so_number_seq 되돌리기(greatest(실제 최대, 머리))'
select (select count(*) from public.po where po_number = 'PO-79720') + (select count(*) from public.so where customer_id in (select id from public.customer where name = 'RLS3C Customer'))
     + (select count(*) from public.ims_staff where email like 'rls3c-%') + (select count(*) from public.product where sku like 'RLS3C-%') + (select count(*) from public.supplier where name = 'RLS3C Supplier') as fake_traces_left;
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select last_value as so_seq_last_after, is_called as so_seq_called_after from public.so_number_seq;
