-- pur-1b-verify.sql — pur_sales_daily 「공급처 비우면 전부」(판정 604 · 616 · pur-1b):
--   null 공급처 → A · B 공급처 판매 + 기본 공급처 없는 낱개(PUR1-N)가 함께 · A 를 주면 \i 앞과 같은 결과(동일성) · 없는 공급처 거부 · 문(purchasing 없음) · 무접촉(G0 · Z1) · 서명 · ACL 무변
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261022144212_pur_1b_sales_all_suppliers.sql -f supabase/tests/pur-1b-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · I0/T13 셋은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 OK 수 − 2 · MISMATCH 0
--   가짜 재료 = pur-1 검증과 같다(PUR1 …) + 낱개 PUR1-N(공급처 줄 없음 · X 오더에서 3 개 판매) · 백오더 · 설정 재료는 없다 · 번호는 창구가 당긴다(so · so_invoice · so_credit 머리 → rollback 뒤 greatest)
--   ⚠️ 경계 날짜는 시험 안에서만 오늘 − 5 로 옮긴다(postgres · 되감긴다)

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261022144212' \gset
select :n_applied as schema_migrations_rows_for_20261022144212;
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
  select 'body=' || coalesce((select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_sales_daily'), '-')
      || ' acl=' || coalesce((select p.proacl::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_sales_daily'), '-') $$;
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
insert into public.product (sku, name, source, is_active, sellable) values ('PUR1-N', 'PUR1 No supplier', 'manual', true, true) returning id::text as pid_n \gset
insert into public.product (sku, name, source, is_active, sellable, parent_product_id, pack_factor, uom_name) values ('PUR1-B-6', 'PUR1 Base ×6', 'manual', true, true, :'pid_b'::uuid, 6, '6') returning id::text as pid_s \gset
insert into public.product (sku, name, source, is_active, sellable) values ('PUR1-C', 'PUR1 Combo', 'manual', true, true) returning id::text as pid_c \gset
insert into public.product_bom (parent_product_id, component_product_id, quantity, is_active, source) values (:'pid_c'::uuid, :'pid_b'::uuid, 2, true, 'manual'), (:'pid_c'::uuid, :'pid_d'::uuid, 1, true, 'manual');
insert into public.product_supplier (product_id, supplier_id, is_active, is_default, source) values (:'pid_b'::uuid, :'sup_a'::uuid, true, true, 'manual'), (:'pid_d'::uuid, :'sup_a'::uuid, true, true, 'manual'), (:'pid_x'::uuid, :'sup_b'::uuid, true, true, 'manual'), (:'pid_b'::uuid, :'sup_b'::uuid, true, false, 'manual');
insert into public.product_price (product_id, tier_id, price, source) values (:'pid_b'::uuid, :'tier_id'::uuid, 9.99, 'manual'), (:'pid_d'::uuid, :'tier_id'::uuid, 4.99, 'manual'), (:'pid_x'::uuid, :'tier_id'::uuid, 7.99, 'manual'), (:'pid_s'::uuid, :'tier_id'::uuid, 55, 'manual'), (:'pid_c'::uuid, :'tier_id'::uuid, 30, 'manual'), (:'pid_n'::uuid, :'tier_id'::uuid, 1.99, 'manual');
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values
  (public.ims_today() - 30, 1, 'PUR1-B', :'whname', :'bina', 20, 'po_in', 'purchase', 'PO-PUR1', 'pur1-b', 'manual'), (public.ims_today() - 30, 1, 'PUR1-X', :'whname', :'bina', 10, 'po_in', 'purchase', 'PO-PUR1', 'pur1-x', 'manual'), (public.ims_today() - 30, 1, 'PUR1-N', :'whname', :'bina', 10, 'po_in', 'purchase', 'PO-PUR1', 'pur1-n', 'manual');
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values
  ('PUR1-B', :'whname', 'purchase', 'PO-PUR1', 'pur1-b', public.ims_today() - 30, true, 20, 2.5, 'po_line'), ('PUR1-X', :'whname', 'purchase', 'PO-PUR1', 'pur1-x', public.ims_today() - 30, true, 10, 3, 'po_line'), ('PUR1-N', :'whname', 'purchase', 'PO-PUR1', 'pur1-n', public.ims_today() - 30, true, 10, 1, 'po_line');
insert into public.ref_service (name, unit_price, is_active) values ('PUR1 Prep service', 25, true) returning id::text as svc \gset
set local session_replication_role = origin;
select pg_temp.chk(format('M0 staff ×3 · suppliers A B · customers ×5 · products B D X N(no supplier) · set B-6 (×6) · combo C (B×2 + D×1) · stock B 20 · X 10 in %s · tier %s · tax %s · snapshots taken', :'bina', :'tier_name', :'r13_name'),
  :'w_uid' <> '' and :'sup_a' <> '' and :'c5' <> '' and :'pid_s' <> '' and :'pid_n' <> '' and :'svc' <> '' and :'real_before' <> '', 'see M0');

\echo '── T0) 시험용 경계 = 오늘 − 5 (postgres · 되감긴다) · 판매 재료 — 인보이스 A(C1 · 오늘 · B 2 + 세트 1 + 콤보 1 직접) · P(C1 · 오늘 − 20 · B 3 · 경계 전) · X(C2 · 오늘 · X 4 + N 3 · N 은 공급처 줄 없음) · 반품 1 · 서비스 인보이스'
update public.inv_config set value = (public.ims_today() - 5)::text where key = 'pur_ims_sales_from';
select pg_temp.mk_order(:'w', :'c1'::uuid, jsonb_build_array(jsonb_build_object('pid', :'pid_b', 'qty', 2), jsonb_build_object('pid', :'pid_s', 'qty', 1)), :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', true, 'pur-1 A')::text as mka \gset
select pg_temp.mk_order(:'w', :'c1'::uuid, jsonb_build_array(jsonb_build_object('pid', :'pid_b', 'qty', 3)), :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', true, 'pur-1 P')::text as mkp \gset
select pg_temp.mk_order(:'w', :'c2'::uuid, jsonb_build_array(jsonb_build_object('pid', :'pid_x', 'qty', 4), jsonb_build_object('pid', :'pid_n', 'qty', 3)), :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name', true, 'pur-1b X+N')::text as mkx \gset
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

\echo '── I0) \i 앞 — A 결과 담기 · null 은 거부'
select pg_temp.as_user(:'r', format('select public.pur_sales_daily(%L::uuid, public.ims_today() - 30, null)::text', :'sup_a')) as a_before \gset
select pg_temp.as_user(:'r', 'select public.pur_sales_daily(null, public.ims_today() - 30, null)::text') as null_before \gset

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) — pur-1 몸 · null 거부'
select pg_temp.chk('S0 before the trial: pur_sales_daily body = pur-1 (ba77908a…) · null supplier refused "Supplier not found" · not in schema_migrations',
  :'gate_before' like 'body=ba77908a49cf561a2d2d100340db81c3 acl=%' and :'null_before' like 'ERR P0001: Supplier not found%' and :n_applied = 0, format('%s | %s', :'gate_before', left(:'null_before', 120)));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: real so · invoices · credits · ledger · other config · pur_* unchanged', pg_temp.real_rows(:'t0'::timestamptz) = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows(:'t0'::timestamptz)));
\echo '── T13) 동일성 — A 를 주면 \i 앞과 같다'
select pg_temp.as_user(:'r', format('select public.pur_sales_daily(%L::uuid, public.ims_today() - 30, null)::text', :'sup_a')) as a_after \gset
select pg_temp.chk(format('T13 pur_sales_daily(A) identical before and after (%s)', pg_temp.sales_trace(pg_temp.j(:'a_after'))), :'a_before' = :'a_after' and :'a_before' not like 'ERR%', format('before %s | after %s', left(:'a_before', 400), left(:'a_after', 400)));
\else
select pg_temp.chk('P0c confirm run: migration 20261022144212 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() like 'body=c295855d253d95549dfcbd515a9ac831 acl=%') as landed \gset
\if :landed
\echo '── G1) 실물 — 몸 · 서명 하나 · ACL 무변'
select pg_temp.chk('G1 pur_sales_daily body = pur-1b (c295855d…) · one overload · definer · authenticated · service_role execute · anon none',
  pg_temp.gate_state() = 'body=c295855d253d95549dfcbd515a9ac831 acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_sales_daily') = 1
  and (select p.prosecdef from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'pur_sales_daily')
  and not has_function_privilege('anon', 'public.pur_sales_daily(uuid, date, date)', 'execute'), pg_temp.gate_state());

\echo '── T1) null 공급처 → A · B 의 판매 + 공급처 없는 PUR1-N 이 함께 · 경계 · 창 · 서비스 · 반품 규칙은 그대로'
select pg_temp.as_user(:'r', 'select public.pur_sales_daily(null, public.ims_today() - 30, null)::text') as t1 \gset
select pg_temp.chk(format('T1 pur_sales_daily(null, today−30, null) as R → PUR1 rows PUR1-B|today|10 · PUR1-D|today|1 · PUR1-N|today|3 (no supplier row) · PUR1-X|today|4 (supplier B) · supplier_id null · from = boundary · P (today−20) out · row_count ≥ 4 (real sales in the window may add rows: %s) → %s', pg_temp.j(:'t1')->>'row_count', pg_temp.sales_trace(pg_temp.j(:'t1'))),
  (select string_agg((r->>'sku') || '|' || (r->>'sale_date') || '|' || trim_scale((r->>'qty')::numeric), ',' order by r->>'sku') from jsonb_array_elements(pg_temp.j(:'t1')->'rows') r where r->>'sku' like 'PUR1-%')
    = format('PUR1-B|%s|10,PUR1-D|%s|1,PUR1-N|%s|3,PUR1-X|%s|4', public.ims_today(), public.ims_today(), public.ims_today(), public.ims_today())
  and jsonb_typeof(pg_temp.j(:'t1')->'supplier_id') = 'null' and (pg_temp.j(:'t1')->>'from')::date = public.ims_today() - 5 and (pg_temp.j(:'t1')->>'to')::date = public.ims_today() + 1 and (pg_temp.j(:'t1')->>'row_count')::int >= 4
  and (pg_temp.j(:'t1')->>'row_count')::int = jsonb_array_length(pg_temp.j(:'t1')->'rows'),
  left(:'t1', 900));

\echo '── T2) A 는 A 것만(null 결과의 부분집합) · B 는 X 만(N 은 공급처가 없어 B 에도 안 나옴) · 없는 공급처 거부 · 문'
select pg_temp.as_user(:'r', format('select public.pur_sales_daily(%L::uuid, public.ims_today() - 30, null)::text', :'sup_a')) as t2a \gset
select pg_temp.as_user(:'r', format('select public.pur_sales_daily(%L::uuid, public.ims_today() - 30, null)::text', :'sup_b')) as t2b \gset
select pg_temp.as_user(:'r', format('select public.pur_sales_daily(%L::uuid)::text', gen_random_uuid())) as t2c \gset
select pg_temp.as_user(:'n', 'select public.pur_sales_daily(null)::text') as t2d \gset
select pg_temp.chk(format('T2 A → PUR1-B|10 · PUR1-D|1 only · B → PUR1-X|4 only · unknown supplier → "Supplier not found" · N (no purchasing) → "cannot view purchasing data" → %s / %s', pg_temp.sales_trace(pg_temp.j(:'t2a')), pg_temp.sales_trace(pg_temp.j(:'t2b'))),
  pg_temp.sales_trace(pg_temp.j(:'t2a')) = format('PUR1-B|%s|10,PUR1-D|%s|1', public.ims_today(), public.ims_today()) and pg_temp.sales_trace(pg_temp.j(:'t2b')) = format('PUR1-X|%s|4', public.ims_today())
  and pg_temp.j(:'t2a')->>'supplier_id' = :'sup_a'
  and :'t2c' like 'ERR P0001: Supplier not found%' and :'t2d' like 'ERR P0001: You cannot view purchasing data%',
  format('%s | %s | %s | %s', left(:'t2a', 300), left(:'t2b', 300), left(:'t2c', 120), left(:'t2d', 120)));
\else
select pg_temp.chk('G1 ~ T2 skipped: pur-1b not landed', false, pg_temp.gate_state());
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real so · invoices · credits · ledger · other config · pur_* rows that existed at the snapshot untouched', pg_temp.real_rows(:'t0'::timestamptz) = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows(:'t0'::timestamptz)));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 시퀀스 셋 되돌리기'
select (select count(*) from public.customer where name like 'PUR1 %') + (select count(*) from public.product where sku like 'PUR1-%') + (select count(*) from public.ims_staff where email like 'pur1-%') + (select count(*) from public.supplier where name like 'PUR1 %') + (select count(*) from public.inv_ledger where sku like 'PUR1-%') + (select count(*) from public.ref_service where name like 'PUR1 %') as leftovers;
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$'), 0), :inv_seq_last), :'inv_seq_called'::boolean) as so_invoice_number_seq_reset_to;
select setval('public.so_credit_number_seq', greatest(coalesce((select max(substring(credit_number from '[0-9]+')::bigint) from public.so_credit), 0), :cr_seq_last), :'cr_seq_called'::boolean) as so_credit_number_seq_reset_to;
select (select last_value || '|' || is_called from public.so_number_seq) as so_seq_after, (select last_value || '|' || is_called from public.so_invoice_number_seq) as inv_seq_after, (select last_value || '|' || is_called from public.so_credit_number_seq) as cr_seq_after;
