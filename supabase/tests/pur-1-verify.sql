-- pur-1-verify.sql — 발주앱 이식 · DB(판정 604 ~ 606 · 608 · 615):
--   읽기 창구 넷(판매 일별 · 백오더 · 공급처 목록 · 세트 지도) · 경계 날짜 · 설정 표 넷 + 창구 · 옮겨 담기 · 문(purchasing 없음 · 읽기 · 쓰기) · 원가 608 · 재고 ⑥ 이름 짝 · 무접촉(G0 · Z1)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261022133010_pur_1_purchasing_db.sql -f supabase/tests/pur-1-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 둘은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 OK 수 − 1 · MISMATCH 0
--   가짜 재료는 전부 PUR1(공급처 A · B · 손님 C1 ~ C5 · 낱개 PUR1-B(재고 20) · PUR1-D · PUR1-X(공급처 B) · 세트 PUR1-B-6(계수 6) · 콤보 PUR1-C(B × 2 + D × 1) · 직원 N(purchasing 없음) · R(purchasing:read) · W(purchasing + sales + cost)) · 번호는 창구가 당긴다(so · so_invoice · so_credit 머리 → rollback 뒤 greatest)
--   ⚠️ 경계 날짜는 시험 안에서만 오늘 − 5 로 옮긴다(postgres · 되감긴다) — 재료 날짜가 과거여야 해서(§67-d 7) · 운영 값 2026-11-01 은 그대로

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261022133010' \gset
select :n_applied as schema_migrations_rows_for_20261022133010;
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
select :so_seq_last as so_seq_head, :inv_seq_last as inv_seq_head, :cr_seq_last as cr_seq_head;

begin;
set local statement_timeout = '600s';
select now() as t0 \gset

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
-- 실제 행(스냅샷 때 있던 것만 · Shopify cron 이 넣는 새 행은 안 센다) — so · 인보이스 · 크레딧 · 원장 · 설정 표 넷
create function pg_temp.real_rows(p_t0 timestamptz) returns text language plpgsql security definer as $$
begin
  return 'so=' || (select count(*) || '/' || md5(coalesce(string_agg(s.id::text || s.status || coalesce(s.updated_at::text, ''), ',' order by s.id), '')) from public.so s where s.created_at < p_t0)
      || ' inv=' || (select count(*) || '/' || md5(coalesce(string_agg(i.id::text || i.status || i.total, ',' order by i.id), '')) from public.so_invoice i where i.created_at < p_t0)
      || ' cr=' || (select count(*) || '/' || md5(coalesce(string_agg(c.id::text || c.status, ',' order by c.id), '')) from public.so_credit c where c.created_at < p_t0)
      || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where created_at < p_t0)
      || ' cfg=' || (select count(*) || '/' || md5(string_agg(c.key || '=' || c.value, ',' order by c.key)) from public.inv_config c where c.key <> 'pur_ims_sales_from')
      -- pur_* 는 스냅샷 때 있던 실제 행만(이 시험의 가짜 공급처 PUR1 · 이 트랜잭션이 넣은 연결 · wma 키는 뺀다) — 표가 없으면(시험 갈래 \i 앞) 빈 표와 같은 값
      || ' pur=' || (select count(*) || '/' || md5(coalesce(string_agg(x.supplier_id::text || x.lead_time || x.target || x.cycle || x.lt_sigma, ',' order by x.supplier_id), '')) from public.pur_supplier_setting x join public.supplier sp on sp.id = x.supplier_id where sp.name not like 'PUR1 %')
      || '/' || (select count(*) || '/' || md5(coalesce(string_agg(k.old_sku || '>' || k.new_sku, ',' order by k.old_sku, k.new_sku), '')) from public.pur_sku_link k where k.created_at < p_t0)
      || '/' || (select count(*) || '/' || md5(coalesce(string_agg(h.id::text, ',' order by h.id), '')) from public.pur_override_history h join public.supplier sp on sp.id = h.supplier_id where sp.name not like 'PUR1 %')
      || '/' || (select count(*) || '/' || md5(coalesce(string_agg(c.key || '=' || c.value::text, ',' order by c.key), '')) from public.pur_setting c where c.key <> 'wma');
exception when undefined_table then
  return 'so=' || (select count(*) || '/' || md5(coalesce(string_agg(s.id::text || s.status || coalesce(s.updated_at::text, ''), ',' order by s.id), '')) from public.so s where s.created_at < p_t0)
      || ' inv=' || (select count(*) || '/' || md5(coalesce(string_agg(i.id::text || i.status || i.total, ',' order by i.id), '')) from public.so_invoice i where i.created_at < p_t0)
      || ' cr=' || (select count(*) || '/' || md5(coalesce(string_agg(c.id::text || c.status, ',' order by c.id), '')) from public.so_credit c where c.created_at < p_t0)
      || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where created_at < p_t0)
      || ' cfg=' || (select count(*) || '/' || md5(string_agg(c.key || '=' || c.value, ',' order by c.key)) from public.inv_config c where c.key <> 'pur_ims_sales_from')
      || ' pur=0/' || md5('') || '/0/' || md5('') || '/0/' || md5('') || '/0/' || md5('');
end $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'tables=' || (select count(*) from pg_tables where schemaname = 'public' and tablename in ('pur_supplier_setting', 'pur_setting', 'pur_sku_link', 'pur_override_history'))::text
      || ' fns=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'pur\_%')::text
      || ' key=' || coalesce((select c.value from public.inv_config c where c.key = 'pur_ims_sales_from'), '-') $$;
-- 창고 오더 → 줄들 → 확정(재고 모자라면 백오더) → (p_finalize) 포장 · 출하 · 인보이스 · {so_id, line_ids[], invoice_id, bo}
create function pg_temp.mk_order(p_claims text, p_cust uuid, p_lines jsonb, p_wh uuid, p_bin text, p_rule uuid, p_rule_name text, p_finalize boolean, p_note text) returns jsonb language plpgsql as $$
declare v_so uuid; v_x jsonb; v_inv uuid; v_ids uuid[] := '{}'; v_picks jsonb := '[]'; e jsonb; v_l uuid; v_bo numeric;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  v_x := public.so_create(p_cust, 'warehouse', 'manual', p_wh, p_note);  v_so := (v_x->>'id')::uuid;
  for e in select * from jsonb_array_elements(p_lines) loop
    v_x := public.so_line_add(v_so, (e->>'pid')::uuid, (e->>'qty')::numeric, null, null, null, null, true);  v_l := (v_x->'line'->>'id')::uuid;
    v_ids := v_ids || v_l;  v_picks := v_picks || jsonb_build_object('line_id', v_l, 'bin', p_bin, 'qty', (e->>'qty')::numeric);
  end loop;
  execute 'set local session_replication_role = replica';
  update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v_so;
  execute 'set local session_replication_role = origin';
  v_x := public.so_confirm(v_so, null, false, true);
  select coalesce(sum(r.qty_allocated), 0) into v_bo from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = v_so and r.kind = 'backorder' and r.released_at is null;
  if p_finalize then
    execute 'set local session_replication_role = replica';
    update public.so set status = 'packed' where id = v_so and status = 'confirmed';
    execute 'set local session_replication_role = origin';
    v_x := public.so_finalize(jsonb_build_array(jsonb_build_object('so_id', v_so, 'picks', v_picks)), true, null);
    select i.id into v_inv from public.so_invoice i join public.so_invoice_order o on o.invoice_id = i.id where o.so_id = v_so and o.cancelled_at is null;
  end if;
  return jsonb_build_object('so_id', v_so, 'line_ids', to_jsonb(v_ids), 'invoice_id', v_inv, 'bo', v_bo, 'status', (select s.status from public.so s where s.id = v_so));
exception when others then
  return jsonb_build_object('err', sqlstate || ': ' || sqlerrm);
end $$;
-- 판매 자취 — {sku|date|qty,…} · 백오더 자취 — {sku|0-30|30-60|60-90|qty,…}
create function pg_temp.sales_trace(p jsonb) returns text language sql as $$
  select coalesce((select string_agg((r->>'sku') || '|' || (r->>'sale_date') || '|' || trim_scale((r->>'qty')::numeric), ',' order by r->>'sku', r->>'sale_date') from jsonb_array_elements(p->'rows') r), '-') $$;
create function pg_temp.bo_trace(p jsonb) returns text language sql as $$
  select coalesce((select string_agg((r->>'sku') || '|' || trim_scale((r->>'bo_0_30')::numeric) || '|' || trim_scale((r->>'bo_30_60')::numeric) || '|' || trim_scale((r->>'bo_60_90')::numeric) || '|' || trim_scale((r->>'bo_qty')::numeric), ',' order by r->>'sku') from jsonb_array_elements(p->'rows') r), '-') $$;

\echo '── M0) 가짜 직원 셋 · 공급처 둘 · 손님 다섯 · 제품 다섯(낱개 · 세트 · 콤보) · 재고 · 세율 · 서비스 · 스냅샷'
select pg_temp.real_rows(:'t0'::timestamptz) as real_before, pg_temp.gate_state() as gate_before \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pur1-n@test.invalid', 'PUR1 N', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as n_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pur1-r@test.invalid', 'PUR1 R', 'manager', '["ims","purchasing:read"]', '{}') returning auth_user_id::text as r_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pur1-w@test.invalid', 'PUR1 W', 'manager', '["ims","sales","purchasing","cost"]', '{}') returning auth_user_id::text as w_uid, id::text as w_id \gset
\set n '{"sub":"' :n_uid '","role":"authenticated"}'
\set r '{"sub":"' :r_uid '","role":"authenticated"}'
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.name as bina from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select rt.id::text as tier_id, rt.name as tier_name from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as r13, name as r13_name from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
set local session_replication_role = replica;
insert into public.supplier (name, source, is_active, payment_term_name, account_payable_code, currency_id) values ('PUR1 Supplier A', 'manual', true, 'Due on receipt', '_62_', :'cad'::uuid) returning id::text as sup_a \gset
insert into public.supplier (name, source, is_active, payment_term_name, account_payable_code, currency_id) values ('PUR1 Supplier B', 'manual', true, 'Due on receipt', '_62_', :'cad'::uuid) returning id::text as sup_b \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name)
  select 'PUR1 C' || g, 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name' from generate_series(1, 5) g;
select (select id::text from public.customer where name = 'PUR1 C1') as c1, (select id::text from public.customer where name = 'PUR1 C2') as c2, (select id::text from public.customer where name = 'PUR1 C3') as c3,
       (select id::text from public.customer where name = 'PUR1 C4') as c4, (select id::text from public.customer where name = 'PUR1 C5') as c5 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('PUR1-B', 'PUR1 Base', 'manual', true, true) returning id::text as pid_b \gset
insert into public.product (sku, name, source, is_active, sellable) values ('PUR1-D', 'PUR1 Base D', 'manual', true, true) returning id::text as pid_d \gset
insert into public.product (sku, name, source, is_active, sellable) values ('PUR1-X', 'PUR1 Other supplier', 'manual', true, true) returning id::text as pid_x \gset
insert into public.product (sku, name, source, is_active, sellable, parent_product_id, pack_factor, uom_name) values ('PUR1-B-6', 'PUR1 Base ×6', 'manual', true, true, :'pid_b'::uuid, 6, '6') returning id::text as pid_s \gset
insert into public.product (sku, name, source, is_active, sellable) values ('PUR1-C', 'PUR1 Combo', 'manual', true, true) returning id::text as pid_c \gset
insert into public.product_bom (parent_product_id, component_product_id, quantity, is_active, source) values (:'pid_c'::uuid, :'pid_b'::uuid, 2, true, 'manual'), (:'pid_c'::uuid, :'pid_d'::uuid, 1, true, 'manual');
insert into public.product_supplier (product_id, supplier_id, is_active, is_default, source) values (:'pid_b'::uuid, :'sup_a'::uuid, true, true, 'manual'), (:'pid_d'::uuid, :'sup_a'::uuid, true, true, 'manual'), (:'pid_x'::uuid, :'sup_b'::uuid, true, true, 'manual'), (:'pid_b'::uuid, :'sup_b'::uuid, true, false, 'manual');
insert into public.product_price (product_id, tier_id, price, source) values (:'pid_b'::uuid, :'tier_id'::uuid, 9.99, 'manual'), (:'pid_d'::uuid, :'tier_id'::uuid, 4.99, 'manual'), (:'pid_x'::uuid, :'tier_id'::uuid, 7.99, 'manual'), (:'pid_s'::uuid, :'tier_id'::uuid, 55, 'manual'), (:'pid_c'::uuid, :'tier_id'::uuid, 30, 'manual');
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values
  (public.ims_today() - 30, 1, 'PUR1-B', :'whname', :'bina', 20, 'po_in', 'purchase', 'PO-PUR1', 'pur1-b', 'manual'), (public.ims_today() - 30, 1, 'PUR1-X', :'whname', :'bina', 10, 'po_in', 'purchase', 'PO-PUR1', 'pur1-x', 'manual');
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values
  ('PUR1-B', :'whname', 'purchase', 'PO-PUR1', 'pur1-b', public.ims_today() - 30, true, 20, 2.5, 'po_line'), ('PUR1-X', :'whname', 'purchase', 'PO-PUR1', 'pur1-x', public.ims_today() - 30, true, 10, 3, 'po_line');
insert into public.ref_service (name, unit_price, is_active) values ('PUR1 Prep service', 25, true) returning id::text as svc \gset
set local session_replication_role = origin;
select pg_temp.chk(format('M0 staff ×3 · suppliers A B · customers ×5 · products B D X · set B-6 (×6) · combo C (B×2 + D×1) · stock B 20 · X 10 in %s · tier %s · tax %s · snapshots taken', :'bina', :'tier_name', :'r13_name'),
  :'w_uid' <> '' and :'sup_a' <> '' and :'c5' <> '' and :'pid_s' <> '' and :'svc' <> '' and :'real_before' <> '', 'see M0');

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) — 표 · 창구 · 설정 키 없음'
select pg_temp.chk('S0 before the trial: no pur_* tables · no pur_* functions · no pur_ims_sales_from · not in schema_migrations', :'gate_before' = 'tables=0 fns=0 key=-' and :n_applied = 0, :'gate_before');
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: real so · invoices · credits · ledger · other config · pur_* unchanged', pg_temp.real_rows(:'t0'::timestamptz) = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows(:'t0'::timestamptz)));
\else
select pg_temp.chk('P0c confirm run: migration 20261022133010 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() ~ '^tables=4 fns=14 key=[0-9]{4}-[0-9]{2}-[0-9]{2}$') as landed \gset
\if :landed
\echo '── G1) 실물 — 표 넷 ACL · RLS · 창구 ACL · 키'
select pg_temp.chk('G1 tables ×4 (anon · authenticated nothing · service_role all · RLS on) · functions ×14 (authenticated 12 · inner 2 none · anon none) · pur_ims_sales_from is a date',
  pg_temp.gate_state() ~ '^tables=4 fns=14 key=[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  and (select count(*) from pg_class c where c.relname in ('pur_supplier_setting', 'pur_setting', 'pur_sku_link', 'pur_override_history') and c.relrowsecurity and c.relacl::text !~ 'anon=' and c.relacl::text !~ 'authenticated=' and c.relacl::text ~ 'service_role=arwdDxtm') = 4
  and not has_table_privilege('authenticated', 'public.pur_supplier_setting', 'select') and not has_table_privilege('anon', 'public.pur_sku_link', 'select')
  and has_function_privilege('authenticated', 'public.pur_sales_daily(uuid, date, date)', 'execute') and not has_function_privilege('anon', 'public.pur_sales_daily(uuid, date, date)', 'execute')
  and not has_function_privilege('authenticated', 'public.pur_base(uuid)', 'execute') and not has_function_privilege('authenticated', 'public.pur_staff(boolean)', 'execute')
  and has_function_privilege('authenticated', 'public.pur_settings_import(jsonb, boolean)', 'execute'),
  pg_temp.gate_state() || ' ' || (select string_agg(c.relname || ':' || coalesce(c.relacl::text, '-') || ':' || c.relrowsecurity, ' ') from pg_class c where c.relname like 'pur\_%' and c.relkind = 'r'));

\echo '── T0) 시험용 경계 = 오늘 − 5 (postgres · 되감긴다) · 판매 재료 — 인보이스 A(C1 · 오늘 · B 2 + 세트 1 + 콤보 1 직접) · P(C1 · 오늘 − 20 · B 3 · 경계 전) · X(C2 · 오늘 · X 4) · 반품 1 · 서비스 인보이스'
update public.inv_config set value = (public.ims_today() - 5)::text where key = 'pur_ims_sales_from';
select pg_temp.mk_order(:'w', :'c1'::uuid, jsonb_build_array(jsonb_build_object('pid', :'pid_b', 'qty', 2), jsonb_build_object('pid', :'pid_s', 'qty', 1)), :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', true, 'pur-1 A')::text as mka \gset
select pg_temp.mk_order(:'w', :'c1'::uuid, jsonb_build_array(jsonb_build_object('pid', :'pid_b', 'qty', 3)), :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', true, 'pur-1 P')::text as mkp \gset
select pg_temp.mk_order(:'w', :'c2'::uuid, jsonb_build_array(jsonb_build_object('pid', :'pid_x', 'qty', 4)), :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', true, 'pur-1 X')::text as mkx \gset
select pg_temp.j(:'mka')->>'invoice_id' as inva, pg_temp.j(:'mka')->>'so_id' as soa, pg_temp.j(:'mkp')->>'invoice_id' as invp, pg_temp.j(:'mkx')->>'invoice_id' as invx \gset
set local session_replication_role = replica;
update public.so_invoice set issued_on = public.ims_today() - 20 where id = :'invp'::uuid;
insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, qty_shipped, unit_price) values (:'soa'::uuid, 9, :'pid_c'::uuid, 'PUR1-C', 'PUR1 Combo', 'EA', 1, 1, 1, 30) returning id::text as combo_line \gset
insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, unit, pack_factor, qty, unit_price, amount, tax_amount, combo_components)
  select :'inva'::uuid, o.id, 9, 'product', :'combo_line'::uuid, 'PUR1-C', 'PUR1 Combo', 'EA', 1, 1, 30, 30, 0,
         jsonb_build_array(jsonb_build_object('product_id', :'pid_b', 'sku', 'PUR1-B', 'qty', 2, 'qty_per_combo', 2), jsonb_build_object('product_id', :'pid_d', 'sku', 'PUR1-D', 'qty', 1, 'qty_per_combo', 1))
  from public.so_invoice_order o where o.invoice_id = :'inva'::uuid;
set local session_replication_role = origin;
select l.id::text as il_b from public.so_invoice_line l where l.invoice_id = :'inva'::uuid and l.sku = 'PUR1-B' \gset
select pg_temp.as_user(:'w', format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('invoice_id', :'inva', 'reason', 'customer_return', 'warehouse_id', :'wh', 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', :'il_b', 'qty_returned', 1, 'restock_bin', :'bina'))))) as cr \gset
select pg_temp.as_user(:'w', format('select public.so_create(%L::uuid, ''service'', ''manual'', %L::uuid, ''pur-1 service'')->>''id''', :'c2', :'wh')) as so_svc \gset
set local session_replication_role = replica;
update public.so set tax_rule_id = :'r13'::uuid, tax_rule = :'r13_name', tax_rule_manual = true where id = :'so_svc'::uuid;
set local session_replication_role = origin;
select pg_temp.as_user(:'w', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''PUR1 prep'', p_amount => 50, p_qty => 2, p_unit_price => 25)::text', :'so_svc')) as svc_chg \gset
select pg_temp.as_user(:'w', format('select public.so_service_confirm(%L::uuid)::text', :'so_svc')) as svc_conf \gset
select pg_temp.as_user(:'w', format('select public.so_service_invoice(%L::uuid, null, true)::text', :'so_svc')) as svc_inv \gset
select pg_temp.chk(format('M1 invoices A (so %s) · P (issued %s) · X · credit %s · service invoice %s · boundary %s',
    left(:'soa', 8), (select issued_on from public.so_invoice where id = :'invp'::uuid), left(:'cr', 60), left(:'svc_inv', 60), (select value from public.inv_config where key = 'pur_ims_sales_from')),
  :'inva' <> '' and :'invp' <> '' and :'invx' <> '' and pg_temp.j(:'cr') ? 'credit_id' and pg_temp.j(:'svc_inv') ? 'invoice_id' and (pg_temp.j(:'mka')->>'bo')::numeric = 0 and (pg_temp.j(:'mkp')->>'bo')::numeric = 0
  and (select count(*) from public.so_invoice_line l where l.invoice_id = (pg_temp.j(:'svc_inv')->>'invoice_id')::uuid and l.kind = 'charge') = 1,
  format('A %s | P %s | X %s | cr %s | svc %s %s %s %s', left(:'mka', 200), left(:'mkp', 120), left(:'mkx', 120), left(:'cr', 200), left(:'so_svc', 60), left(:'svc_chg', 120), left(:'svc_conf', 120), left(:'svc_inv', 200)));

\echo '── T1) 판매 일별 — 공급처 A · 낱개 · 세트 × 6 · 콤보 구성품 · 경계 전 제외 · 반품 안 뺌 · 서비스 안 섞임'
select pg_temp.as_user(:'r', format('select public.pur_sales_daily(%L::uuid, public.ims_today() - 30, null)::text', :'sup_a')) as t1 \gset
select pg_temp.chk(format('T1 pur_sales_daily(A, today−30, null) as R → from = boundary (today−5) · to = today+1 · rows PUR1-B|today|10 (2 + 6 + 2) · PUR1-D|today|1 · P (today−20) out · X out · credit not subtracted · service out → %s', pg_temp.sales_trace(pg_temp.j(:'t1'))),
  pg_temp.sales_trace(pg_temp.j(:'t1')) = format('PUR1-B|%s|10,PUR1-D|%s|1', public.ims_today(), public.ims_today())
  and (pg_temp.j(:'t1')->>'from')::date = public.ims_today() - 5 and (pg_temp.j(:'t1')->>'to')::date = public.ims_today() + 1 and (pg_temp.j(:'t1')->>'boundary')::date = public.ims_today() - 5 and (pg_temp.j(:'t1')->>'row_count')::int = 2,
  left(:'t1', 600));
select pg_temp.as_user(:'r', format('select public.pur_sales_daily(%L::uuid, null, null)::text', :'sup_b')) as t2a \gset
select pg_temp.as_user(:'r', format('select public.pur_sales_daily(%L::uuid, null, public.ims_today())::text', :'sup_b')) as t2b \gset
select pg_temp.as_user(:'r', format('select public.pur_sales_daily(%L::uuid, null, null)::text', gen_random_uuid())) as t2c \gset
select pg_temp.chk(format('T2 pur_sales_daily(B) → PUR1-X|today|4 only (PUR1-B is not B''s default) · to = today → window [from, today) empty · unknown supplier refused → %s / %s / %s', pg_temp.sales_trace(pg_temp.j(:'t2a')), pg_temp.sales_trace(pg_temp.j(:'t2b')), left(:'t2c', 60)),
  pg_temp.sales_trace(pg_temp.j(:'t2a')) = format('PUR1-X|%s|4', public.ims_today()) and (pg_temp.j(:'t2b')->>'row_count')::int = 0 and :'t2c' like 'ERR P0001: Supplier not found%',
  format('%s | %s | %s', left(:'t2a', 300), left(:'t2b', 300), left(:'t2c', 200)));

\echo '── T3) 백오더 재료 — 남은 B 재고 10(9 + 반품 1) · BO1 C1 16 (10 할당 · 6 은 stock_short 분할 형제 오더에 백오더) · BO2 C2 세트 2 (bo 2 = 낱개 12) · BO3 C3 3 · BO4 C3 4 (최신) · BO5 C1 5 (최신 · 뒤에 취소) · BO6 C4 2 (오더 날 −45) · BO7 C5 7 (−100 · 밖)'
select pg_temp.mk_order(:'w', :'c1'::uuid, jsonb_build_array(jsonb_build_object('pid', :'pid_b', 'qty', 16)), :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', false, 'pur-1 BO1')::text as bo1 \gset
select pg_temp.mk_order(:'w', :'c2'::uuid, jsonb_build_array(jsonb_build_object('pid', :'pid_s', 'qty', 2)), :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', false, 'pur-1 BO2')::text as bo2 \gset
select pg_temp.mk_order(:'w', :'c3'::uuid, jsonb_build_array(jsonb_build_object('pid', :'pid_b', 'qty', 3)), :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', false, 'pur-1 BO3')::text as bo3 \gset
select pg_temp.mk_order(:'w', :'c3'::uuid, jsonb_build_array(jsonb_build_object('pid', :'pid_b', 'qty', 4)), :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', false, 'pur-1 BO4')::text as bo4 \gset
select pg_temp.mk_order(:'w', :'c1'::uuid, jsonb_build_array(jsonb_build_object('pid', :'pid_b', 'qty', 5)), :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', false, 'pur-1 BO5')::text as bo5 \gset
select pg_temp.mk_order(:'w', :'c4'::uuid, jsonb_build_array(jsonb_build_object('pid', :'pid_b', 'qty', 2)), :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', false, 'pur-1 BO6')::text as bo6 \gset
select pg_temp.mk_order(:'w', :'c5'::uuid, jsonb_build_array(jsonb_build_object('pid', :'pid_b', 'qty', 7)), :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', false, 'pur-1 BO7')::text as bo7 \gset
set local session_replication_role = replica;
update public.so set order_date = public.ims_today() - 45 where id = (pg_temp.j(:'bo6')->>'so_id')::uuid;
update public.so set order_date = public.ims_today() - 100 where id = (pg_temp.j(:'bo7')->>'so_id')::uuid;
set local session_replication_role = origin;
select (select string_agg(trim_scale(l.qty_ordered) || '/' || coalesce((select string_agg(c.end_kind, '+') from public.so_backorder_close c where c.so_line_id = l.id and c.reopened_at is null), 'open'), ',') from public.so_line l join public.so s on s.id = l.so_id where s.customer_id = :'c1'::uuid and s.split_from_id = (pg_temp.j(:'bo1')->>'so_id')::uuid) as bo1_sib \gset
select pg_temp.chk(format('M2 backorders bo1 %s on the order itself · its stock_short sibling line %s (6 backordered · then superseded by BO5 = IMS keeps one open backorder per customer × SKU · 판정 464) · bo2 %s (sets) · bo3 %s · bo4 %s · bo5 %s · bo6 %s · bo7 %s', pg_temp.j(:'bo1')->>'bo', :'bo1_sib', pg_temp.j(:'bo2')->>'bo', pg_temp.j(:'bo3')->>'bo', pg_temp.j(:'bo4')->>'bo', pg_temp.j(:'bo5')->>'bo', pg_temp.j(:'bo6')->>'bo', pg_temp.j(:'bo7')->>'bo'),
  (pg_temp.j(:'bo1')->>'bo')::numeric = 0 and :'bo1_sib' = '6/superseded' and (pg_temp.j(:'bo2')->>'bo')::numeric = 2 and (pg_temp.j(:'bo3')->>'bo')::numeric = 3 and (pg_temp.j(:'bo4')->>'bo')::numeric = 4 and (pg_temp.j(:'bo5')->>'bo')::numeric = 5 and (pg_temp.j(:'bo6')->>'bo')::numeric = 2 and (pg_temp.j(:'bo7')->>'bo')::numeric = 7,
  format('%s | %s | %s | %s | %s | %s | %s', left(:'bo1', 150), left(:'bo2', 150), left(:'bo3', 100), left(:'bo4', 100), left(:'bo5', 100), left(:'bo6', 100), left(:'bo7', 100)));
select pg_temp.as_user(:'r', format('select public.pur_backorders(%L::uuid)::text', :'sup_a')) as t3a \gset
select pg_temp.as_user(:'w', format('select public.so_demand_flag_set(array[%L::uuid], ''duplicate'', ''pur-1 T3'')::text', pg_temp.j(:'bo5')->'line_ids'->>0)) as t3f \gset
select pg_temp.as_user(:'w', format('select public.so_cancel(%L::uuid, ''pur-1 T3 cancel'', ''{}'', true, true)::text', pg_temp.j(:'bo5')->>'so_id')) as t3x \gset
select pg_temp.as_user(:'r', format('select public.pur_backorders(%L::uuid)::text', :'sup_a')) as t3b \gset
select pg_temp.as_user(:'r', 'select public.pur_backorders(null)::text') as t3c \gset
select pg_temp.chk(format('T3 pur_backorders(A): PUR1-B|21|2|0|23 (C1 latest = BO5 5 · C2 set 2×6 = 12 · C3 latest 4 · C4 2 in 30-60 · C5 out) · demand flag on an OPEN backorder is refused by so_demand_flag_set (flags are for lost sales only) · cancel BO5 reopening what it superseded → PUR1-B|22|2|0|24 (C1 = the sibling 6 again) · null supplier has the same PUR1-B row → %s → %s', pg_temp.bo_trace(pg_temp.j(:'t3a')), pg_temp.bo_trace(pg_temp.j(:'t3b'))),
  pg_temp.bo_trace(pg_temp.j(:'t3a')) = 'PUR1-B|21|2|0|23' and pg_temp.bo_trace(pg_temp.j(:'t3b')) = 'PUR1-B|22|2|0|24' and :'t3f' like 'ERR P0001:%no lost sale to exclude%' and left(:'t3x', 3) <> 'ERR'
  and exists (select 1 from jsonb_array_elements(pg_temp.j(:'t3c')->'rows') r where r->>'sku' = 'PUR1-B' and (r->>'bo_qty')::numeric = 24),
  format('%s | flag %s | cancel %s | %s | null %s', left(:'t3a', 300), left(:'t3f', 160), left(:'t3x', 120), left(:'t3b', 300), left(:'t3c', 200)));

\echo '── T4) 문 — purchasing 없음 거부 · 읽기 OK · 읽기는 쓰기 거부'
select pg_temp.as_user(:'n', format('select public.pur_sales_daily(%L::uuid)::text', :'sup_a')) as t4a \gset
select pg_temp.as_user(:'n', 'select public.pur_settings()::text') as t4b \gset
select pg_temp.as_user(:'r', format('select public.pur_supplier_setting_set(%L::uuid, ''{"leadtime": 45}'')::text', :'sup_a')) as t4c \gset
select pg_temp.as_user(:'r', 'select public.pur_settings()::text') as t4d \gset
select pg_temp.chk('T4 gates: N (no purchasing) → sales · settings refused "cannot view purchasing data" · R (purchasing:read) → write refused "cannot change purchasing settings" · read OK with defaults (is_default true · weights 3 2 1 · boundary)',
  :'t4a' like 'ERR P0001: You cannot view purchasing data%' and :'t4b' like 'ERR P0001: You cannot view purchasing data%' and :'t4c' like 'ERR P0001: You cannot change purchasing settings%'
  and (pg_temp.j(:'t4d')->'weights'->>'is_default')::boolean and (pg_temp.j(:'t4d')->'weights'->>'w1')::int = 3 and (pg_temp.j(:'t4d')->>'boundary_date')::date = public.ims_today() - 5 and jsonb_typeof(pg_temp.j(:'t4d')->'supplier') = 'null',
  format('%s | %s | %s | %s', left(:'t4a', 120), left(:'t4b', 120), left(:'t4c', 120), left(:'t4d', 400)));

\echo '── T5) 공급처 목록 · 세트 지도'
select pg_temp.as_user(:'r', format('select public.pur_supplier_skus(%L::uuid)::text', :'sup_a')) as t5a \gset
select pg_temp.as_user(:'r', 'select public.pur_supplier_skus(null)::text') as t5b \gset
select pg_temp.as_user(:'r', 'select public.pur_set_map()::text') as t5c \gset
select pg_temp.chk(format('T5 pur_supplier_skus(A) → PUR1-B · PUR1-D (supplier_id A · brand —) · no set · no combo · no X · (null) ∋ PUR1-X with supplier B · pur_set_map ∋ PUR1-B-6→PUR1-B ×6 set · PUR1-C→PUR1-B ×2 · PUR1-C→PUR1-D ×1 combo (sets %s · combos %s)', pg_temp.j(:'t5c')->>'sets', pg_temp.j(:'t5c')->>'combos'),
  (select string_agg((r->>'sku') || '|' || (r->>'supplier_name') || '|' || (r->>'brand'), ',' order by r->>'sku') from jsonb_array_elements(pg_temp.j(:'t5a')->'rows') r where r->>'sku' like 'PUR1-%') = 'PUR1-B|PUR1 Supplier A|—,PUR1-D|PUR1 Supplier A|—'
  and (pg_temp.j(:'t5a')->>'row_count')::int = 2
  and exists (select 1 from jsonb_array_elements(pg_temp.j(:'t5b')->'rows') r where r->>'sku' = 'PUR1-X' and r->>'supplier_id' = :'sup_b')
  and (select string_agg((r->>'set_sku') || '>' || (r->>'base_sku') || 'x' || trim_scale((r->>'factor')::numeric) || (r->>'kind'), ',' order by r->>'set_sku', r->>'base_sku') from jsonb_array_elements(pg_temp.j(:'t5c')->'rows') r where r->>'set_sku' like 'PUR1-%') = 'PUR1-B-6>PUR1-Bx6set,PUR1-C>PUR1-Bx2combo,PUR1-C>PUR1-Dx1combo'
  and (pg_temp.j(:'t5c')->>'sets')::int >= 1 and (pg_temp.j(:'t5c')->>'combos')::int >= 1,
  format('%s | null rows %s | map %s', left(:'t5a', 400), pg_temp.j(:'t5b')->>'row_count', left(:'t5c', 200)));

\echo '── T6) 설정 쓰기 — 공급처 설정 일부 → 나머지 기본 · 다시 일부 → 앞 값 유지 · 거부 · 가중치 · 연결 · 오버라이드 이력'
select pg_temp.as_user(:'w', format('select public.pur_supplier_setting_set(%L::uuid, ''{"leadtime": 45, "target": 90}'')::text', :'sup_a')) as t6a \gset
select pg_temp.as_user(:'w', format('select public.pur_supplier_setting_set(%L::uuid, ''{"cycle": 14}'')::text', :'sup_a')) as t6b \gset
select pg_temp.as_user(:'w', format('select public.pur_supplier_setting_set(%L::uuid, ''{"cycle": "x"}'')::text', :'sup_a')) as t6c \gset
select pg_temp.as_user(:'w', format('select public.pur_supplier_setting_set(%L::uuid, ''{"foo": 1}'')::text', :'sup_a')) as t6d \gset
select pg_temp.chk(format('T6a supplier setting A: {leadtime 45, target 90} → 45 90 30 0 · then {cycle 14} → 45 90 14 0 · "x" refused · unknown key refused → %s', left(:'t6b', 120)),
  (pg_temp.j(:'t6a')->>'leadtime')::int = 45 and (pg_temp.j(:'t6a')->>'target')::int = 90 and (pg_temp.j(:'t6a')->>'cycle')::int = 30 and (pg_temp.j(:'t6a')->>'lt_sigma')::int = 0
  and (pg_temp.j(:'t6b')->>'leadtime')::int = 45 and (pg_temp.j(:'t6b')->>'cycle')::int = 14 and :'t6c' like 'ERR P0001: cycle must be a whole number%' and :'t6d' like 'ERR P0001: Unknown setting foo%',
  format('%s | %s | %s | %s', left(:'t6a', 200), left(:'t6b', 200), left(:'t6c', 120), left(:'t6d', 120)));
select pg_temp.as_user(:'w', 'select public.pur_weights_set(''{"w1": 4, "w2": 2, "w3": 1}'')::text') as t6e \gset
select pg_temp.as_user(:'w', 'select public.pur_weights_set(''{"w1": 11, "w2": 2, "w3": 1}'')::text') as t6f \gset
select pg_temp.as_user(:'w', 'select public.pur_sku_link_add('' old1 '', ''new1'')::text') as t6g \gset
select pg_temp.as_user(:'w', 'select public.pur_sku_link_add(''OLD1'', ''NEW1'')::text') as t6h \gset
select pg_temp.as_user(:'w', 'select public.pur_sku_link_add(''SAME'', ''same'')::text') as t6i \gset
select pg_temp.as_user(:'w', 'select public.pur_sku_link_add(''OLD2'', ''NEW1'')::text') as t6j \gset
select pg_temp.as_user(:'w', 'select public.pur_sku_link_remove(''old2'', ''NEW1'')::text') as t6k \gset
select pg_temp.chk('T6b weights {4,2,1} saved · 11 refused · link " old1 "→new1 stored as OLD1→NEW1 · duplicate refused · self refused · second link added then removed (removed 1)',
  (pg_temp.j(:'t6e')->>'w1')::int = 4 and not (pg_temp.j(:'t6e')->>'is_default')::boolean and :'t6f' like 'ERR P0001: w1 must be a whole number from 1 to 10%'
  and pg_temp.j(:'t6g')->>'oldSku' = 'OLD1' and pg_temp.j(:'t6g')->>'newSku' = 'NEW1' and :'t6h' like 'ERR P0001: SKU link OLD1 → NEW1 already exists%' and :'t6i' like 'ERR P0001: A SKU cannot be linked to itself%'
  and pg_temp.j(:'t6j') ? 'id' and (pg_temp.j(:'t6k')->>'removed')::int = 1 and (select count(*) from public.pur_sku_link) = 1,
  format('%s | %s | %s | %s | %s | %s | %s', left(:'t6e', 100), left(:'t6f', 100), left(:'t6g', 150), left(:'t6h', 100), left(:'t6i', 100), left(:'t6j', 100), left(:'t6k', 100)));
select pg_temp.as_user(:'w', format('select public.pur_override_record(%L::uuid, ''sea'', 1.2)::text', :'sup_a')) as t6l \gset
select pg_temp.as_user(:'w', format('select public.pur_override_record(%L::uuid, ''sea'', 1.2)::text', :'sup_a')) as t6m \gset
select pg_temp.as_user(:'w', format('select public.pur_override_record(%L::uuid, ''sea'', null)::text', :'sup_a')) as t6n \gset
select pg_temp.as_user(:'w', format('select public.pur_override_record(%L::uuid, ''xyz'', 1)::text', :'sup_a')) as t6o \gset
select pg_temp.chk(format('T6c override sea 1.2 → changed · same again → not changed · null (auto) → changed · history newest first [auto, 1.2] · key xyz refused → %s', (select string_agg(h->>'v', ',') from jsonb_array_elements(pg_temp.j(:'t6n')->'history') h)),
  (pg_temp.j(:'t6l')->>'changed')::boolean and not (pg_temp.j(:'t6m')->>'changed')::boolean and (pg_temp.j(:'t6n')->>'changed')::boolean
  and (select string_agg(h->>'v', ',') from jsonb_array_elements(pg_temp.j(:'t6n')->'history') h) = 'auto,1.2' and :'t6o' like 'ERR P0001: Override key must be sea or trd%',
  format('%s | %s | %s | %s', left(:'t6l', 200), left(:'t6m', 200), left(:'t6n', 200), left(:'t6o', 100)));

\echo '── T7) 옮겨 담기 — 미리 보기(쓰기 0) → 실행 → 다시 실행(같음) · 못 찾은 이름 목록 · 대소문자 · 공백 무시 짝'
\set imp '{"asung_po_v5": {"PUR1 Supplier A": {"leadtime": 21, "target": 70, "cycle": 28, "lt_sigma": 3}, " pur1 supplier b ": {"leadtime": 60, "target": 120, "cycle": 30}, "No Such Supplier": {"leadtime": 1, "target": 2, "cycle": 3}, "PUR1 Supplier B": {"leadtime": "abc"}}, "asung_ov_history": {"PUR1 Supplier A": {"sea": [{"v": 1.1, "d": "2026-09-01"}, {"v": "auto", "d": "2026-09-02"}], "trd": [{"v": 0.9, "d": "2026-09-03"}]}, "Nope Inc": {"sea": [{"v": 1, "d": "2026-09-01"}], "trd": []}}, "asung_sku_links": [{"oldSku": "a1", "newSku": "A2"}, {"oldSku": "X", "newSku": "x"}, {"oldSku": "OLD1", "newSku": "NEW1"}], "asung_wma": {"w1": 5, "w2": 3, "w3": 1}}'
select pg_temp.real_rows(:'t0'::timestamptz) as rows_before_import \gset
select pg_temp.as_user(:'w', format('select public.pur_settings_import(%L::jsonb, false)::text', :'imp')) as t7a \gset
select pg_temp.real_rows(:'t0'::timestamptz) as rows_after_preview \gset
select pg_temp.as_user(:'w', format('select public.pur_settings_import(%L::jsonb, true)::text', :'imp')) as t7b \gset
select pg_temp.as_user(:'w', format('select public.pur_settings_import(%L::jsonb, true)::text', :'imp')) as t7c \gset
select pg_temp.as_user(:'r', format('select public.pur_settings_import(%L::jsonb, false)::text', :'imp')) as t7d \gset
select pg_temp.chk(format('T7 import preview: settings 2 written (A · " pur1 supplier b " matched) · unknown [No Such Supplier] · invalid [PUR1 Supplier B (abc)] · history new 3 · unknown [Nope Inc] · links given 3 · new 1 · already 1 · invalid 1 · weights 5 3 1 · preview wrote nothing · commit same counts · re-commit new 0 · R refused → %s', left(:'t7c', 330)),
  (pg_temp.j(:'t7a')->'supplier_settings'->>'written')::int = 2 and pg_temp.j(:'t7a')->'supplier_settings'->'unknown_suppliers' = '["No Such Supplier"]'::jsonb and pg_temp.j(:'t7a')->'supplier_settings'->'invalid' = '["PUR1 Supplier B"]'::jsonb
  and (pg_temp.j(:'t7a')->'override_history'->>'new')::int = 3 and pg_temp.j(:'t7a')->'override_history'->'unknown_suppliers' = '["Nope Inc"]'::jsonb
  and (pg_temp.j(:'t7a')->'sku_links'->>'given')::int = 3 and (pg_temp.j(:'t7a')->'sku_links'->>'new')::int = 1 and (pg_temp.j(:'t7a')->'sku_links'->>'already_there')::int = 1 and (pg_temp.j(:'t7a')->'sku_links'->>'invalid')::int = 1
  and (pg_temp.j(:'t7a')->'weights'->>'w1')::int = 5 and not (pg_temp.j(:'t7a')->>'committed')::boolean
  and :'rows_before_import' = :'rows_after_preview'
  and (pg_temp.j(:'t7b')->'supplier_settings'->>'written')::int = 2 and (pg_temp.j(:'t7b')->'override_history'->>'new')::int = 3 and (pg_temp.j(:'t7b')->'sku_links'->>'new')::int = 1 and (pg_temp.j(:'t7b')->>'committed')::boolean
  and (pg_temp.j(:'t7c')->'override_history'->>'new')::int = 0 and (pg_temp.j(:'t7c')->'override_history'->>'already_there')::int = 3 and (pg_temp.j(:'t7c')->'sku_links'->>'new')::int = 0 and (pg_temp.j(:'t7c')->'sku_links'->>'already_there')::int = 2
  and :'t7d' like 'ERR P0001: You cannot change purchasing settings%'
  and (select count(*) from public.pur_supplier_setting) = 2 and (select count(*) from public.pur_override_history) = 5 and (select count(*) from public.pur_sku_link) = 2,
  format('preview %s | commit %s | again %s | R %s | rows %s / %s', left(:'t7a', 500), left(:'t7b', 300), left(:'t7c', 300), left(:'t7d', 100), :'rows_before_import', :'rows_after_preview'));

\echo '── T8) 설정 읽기 — 고른 공급처 A 의 실효값 · 전부 · 연결 · 이력'
select pg_temp.as_user(:'r', format('select public.pur_settings(%L::uuid)::text', :'sup_a')) as t8 \gset
select pg_temp.chk(format('T8 pur_settings(A) → supplier 21 70 28 3 (is_default false · updated_by_name PUR1 W) · supplier_settings 2 (A · B 60 120 30 0) · weights 5 3 1 · sku_links [A1→A2, OLD1→NEW1] · history sea [auto(today), 1.2(today), auto(09-02), 1.1(09-01)] · trd [0.9] → %s', left(:'t8', 200)),
  (pg_temp.j(:'t8')->'supplier'->>'leadtime')::int = 21 and (pg_temp.j(:'t8')->'supplier'->>'target')::int = 70 and (pg_temp.j(:'t8')->'supplier'->>'cycle')::int = 28 and (pg_temp.j(:'t8')->'supplier'->>'lt_sigma')::int = 3
  and not (pg_temp.j(:'t8')->'supplier'->>'is_default')::boolean and pg_temp.j(:'t8')->'supplier'->>'updated_by_name' = 'PUR1 W'
  and (select string_agg((x->>'name') || ':' || (x->>'leadtime') || '/' || (x->>'target') || '/' || (x->>'cycle') || '/' || (x->>'lt_sigma'), ',' order by x->>'name') from jsonb_array_elements(pg_temp.j(:'t8')->'supplier_settings') x) = 'PUR1 Supplier A:21/70/28/3,PUR1 Supplier B:60/120/30/0'
  and (pg_temp.j(:'t8')->'weights'->>'w1')::int = 5 and (pg_temp.j(:'t8')->'weights'->>'w2')::int = 3 and not (pg_temp.j(:'t8')->'weights'->>'is_default')::boolean
  and (select string_agg((x->>'oldSku') || '>' || (x->>'newSku'), ',' order by x->>'newSku') from jsonb_array_elements(pg_temp.j(:'t8')->'sku_links') x) = 'A1>A2,OLD1>NEW1'
  and (select string_agg((h->>'v') || '@' || (h->>'d'), ',') from jsonb_array_elements(pg_temp.j(:'t8')->'override_history'->'sea') h) = format('auto@%s,1.2@%s,auto@2026-09-02,1.1@2026-09-01', public.ims_today(), public.ims_today())
  and (select string_agg(h->>'v', ',') from jsonb_array_elements(pg_temp.j(:'t8')->'override_history'->'trd') h) = '0.9',
  left(:'t8', 1200));

\echo '── T9) 원가 608 — 열쇠 없는 R 은 stk_value_many 거부 · 열쇠 있는 W 는 받는다 · ⑥ 창고 이름 짝(Edmonton 포함 ↔ 그 외) · stk_availability by_warehouse 에 이름'
select pg_temp.as_user(:'r', format('select (select count(*) from public.stk_value_many(array[%L::uuid]))::text', :'pid_b')) as t9a \gset
select pg_temp.as_user(:'w', format('select (select string_agg(warehouse || ''='' || trim_scale(remaining_value), '','') from public.stk_value_many(array[%L::uuid]))', :'pid_b')) as t9b \gset
select pg_temp.as_user(:'w', format('select (select by_warehouse::text from public.stk_availability(null, ''PUR1-B'') where sku = ''PUR1-B'')')) as t9c \gset
select (select string_agg(name, ' / ' order by name) from public.ref_warehouse where is_active) as wh_names, (select count(*) from public.ref_warehouse where is_active) as wh_n, (select count(*) from public.ref_warehouse where is_active and name ilike '%edmonton%') as wh_edm \gset
select pg_temp.chk(format('T9 R without cost key → "Inventory cost permission" refused · W with key → %s · active warehouses %s (Edmonton-named %s of %s → screen rule includes(''edmonton'') else toronto) · by_warehouse carries warehouse names', left(:'t9b', 80), :'wh_names', :'wh_edm', :'wh_n'),
  :'t9a' like 'ERR P0001: You do not have the Inventory cost permission%' and :'t9b' like '%=%' and :'t9b' not like 'ERR%'
  and :wh_edm = 1 and :wh_n = 2
  and exists (select 1 from jsonb_array_elements(pg_temp.j(:'t9c')) b where b ? 'warehouse' and b ? 'on_hand'),
  format('%s | %s | %s', left(:'t9a', 150), left(:'t9b', 150), left(:'t9c', 400)));
\else
select pg_temp.chk('G1 ~ T9 skipped: pur-1 not landed', false, pg_temp.gate_state());
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real so · invoices · credits · ledger · other config · pur_* rows that existed at the snapshot untouched (this test''s PUR1 rows excluded)', pg_temp.real_rows(:'t0'::timestamptz) = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows(:'t0'::timestamptz)));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 시퀀스 셋 되돌리기'
select (select count(*) from public.customer where name like 'PUR1 %') + (select count(*) from public.product where sku like 'PUR1-%') + (select count(*) from public.ims_staff where email like 'pur1-%') + (select count(*) from public.supplier where name like 'PUR1 %') + (select count(*) from public.inv_ledger where sku like 'PUR1-%') + (select count(*) from public.ref_service where name like 'PUR1 %') as leftovers;
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$'), 0), :inv_seq_last), :'inv_seq_called'::boolean) as so_invoice_number_seq_reset_to;
select setval('public.so_credit_number_seq', greatest(coalesce((select max(substring(credit_number from '[0-9]+')::bigint) from public.so_credit), 0), :cr_seq_last), :'cr_seq_called'::boolean) as so_credit_number_seq_reset_to;
select (select last_value || '|' || is_called from public.so_number_seq) as so_seq_after, (select last_value || '|' || is_called from public.so_invoice_number_seq) as inv_seq_after, (select last_value || '|' || is_called from public.so_credit_number_seq) as cr_seq_after;
