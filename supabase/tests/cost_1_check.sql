-- supabase/tests/cost_1_check.sql — cost-1a · 1a2 · 1b 검증 (2026-10-26 · 판정 759 · 764 · 765 · deferred 339)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준값은 begin 앞 · begin → (-v mig · mig2 · mig3 면 \i) → 가짜 직원 여덟 · 가짜 재료(COST1 · PO-9990x · RCV-COST1x · 전부 되감긴다) → 검사 → rollback
--   갈래는 변수가 아니라 DB 상태로 가른다: 회수 여부 = has_column_privilege(authenticated · cost) → 1b 뒤 검사(C6 ⓐ) / 1b 전 검사(C6 ⓑ)
--   Claude Code(시험 ①  1a + 1a2):   psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261026173000_cost_1a_supplier_cost_window.sql -v mig2=supabase/migrations/20261026173100_cost_1a2_product_update_cost_words.sql -f supabase/tests/cost_1_check.sql
--   Claude Code(시험 ②  1a + 1a2 + 1b): 위 명령에 -v mig3=supabase/migrations/20261026173200_cost_1b_supplier_cost_grant.sql
--   Caleb(확인 ③ · 1a · 1a2 적용 뒤):  같은 명령에서 -v mig · mig2 · mig3 를 모두 뺀다 → 1b 전 갈래(C6 ⓑ)
--   Caleb(확인 ④ · 1b 적용 뒤):        같은 명령(변수 없음) → 1b 뒤 갈래(C6 ⓐ)
--   기대 OK: 시험 ① = EXPECT_TRIAL_A · 시험 ② = EXPECT_TRIAL_B · 확인 ③ = EXPECT_CHECK_A · 확인 ④ = EXPECT_CHECK_B(머리의 수는 통과한 실행에서 받아 적는다 · S0 셋은 시험 갈래에만 · 확인 = 시험 − 3 · 마른 실행(-v 없음 · 적용 전)은 G1a MISMATCH 뒤 C1 첫 호출(:171 창구 없음)에서 선다 = 정상 · 2026-10-26 실측 시험 ① 43/0 · ② 49/0)
--   쓰기 0(실제 행) — 가짜만 · product_supplier 지문(순서 무관 합) · 표 행 수 · 시퀀스 머리 전후 대조
\set ON_ERROR_STOP on
\set EXPECT_TRIAL_A 43
\set EXPECT_TRIAL_B 49
\set EXPECT_CHECK_A 40
\set EXPECT_CHECK_B 46
\pset pager off
\echo '── 기준값(begin 앞 · 잠금 없음)'
select count(*) as n_ps, sum(('x' || left(md5(ps::text), 15))::bit(60)::bigint) as fp_ps from public.product_supplier ps \gset
select (select count(*) from public.po) as n_po, (select count(*) from public.po_line) as n_pol, (select count(*) from public.product) as n_prod, (select count(*) from public.supplier) as n_sup,
       (select count(*) from public.ims_staff) as n_staff, (select count(*) from public.po_receipt) as n_rcv, (select count(*) from public.po_invoice) as n_inv, (select count(*) from public.inv_ledger) as n_led \gset
select last_value as po_seq_last, is_called as po_seq_called from public.po_number_seq \gset
select last_value as rcv_seq_last, is_called as rcv_seq_called from public.po_receipt_number_seq \gset
select ps.supplier_id::text as big_sup, count(*) as big_n from public.product_supplier ps group by ps.supplier_id order by count(*) desc, ps.supplier_id limit 1 \gset
select :n_ps as n_ps, :fp_ps as fp_ps, :big_n as biggest_supplier_lines;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql security definer as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- postgres 역할 + 가짜 직원 claims(auth.uid 가 그 직원) — definer 창구 · 셸 시험
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- authenticated 역할 + claims — 권한(grant · RLS) 시험(REST 조건 · statement_timeout 8 s)
create function pg_temp.as_role(p_role text, p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute format('set local role %I', p_role);
  perform set_config('request.jwt.claims', p_claims, true);
  perform set_config('statement_timeout', '8s', true);
  execute p_sql into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then
  reset role;
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.fns() returns text language sql security definer as $$
  select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('po_receipt_confirm_by', 'po_receipt_post_now_by', 'po_receipt_confirm', 'po_receipt_post_now', 'wms_recv_confirm', 'product_create_core', 'product_export', 'stk_value_total', 'product_list', 'ims_can_view_cost', 'ims_can_view', 'price_formula_calc', 'price_formula_save') $$;
create function pg_temp.state() returns text language sql security definer as $$
  select 'paste=' || coalesce((select left(md5(p.prosrc), 8) || ':' || p.prosecdef::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste'), '-')
      || ' preview=' || coalesce((select left(md5(p.prosrc), 8) || ':' || p.prosecdef::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'price_formula_preview'), '-')
      || ' latest=' || coalesce((select left(md5(p.prosrc), 8) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_receipt_latest_apply'), '-')
      || ' update=' || coalesce((select left(md5(p.prosrc), 8) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_update'), '-')
      || ' window=' || (to_regprocedure('public.product_supplier_costs(uuid[], uuid, boolean)') is not null)::text
      || ' relacl=' || (select relacl::text from pg_class where oid = 'public.product_supplier'::regclass) $$;
-- 공급처 연결 자취 — sku:cost/fixed/last_supplied/active
create function pg_temp.ps_trace(p_sup uuid) returns text language sql security definer as $$
  select string_agg(pr.sku || ':' || coalesce(trim_scale(ps.cost)::text, '-') || '/' || coalesce(trim_scale(ps.fixed_cost)::text, '-') || '/' || coalesce(ps.last_supplied::text, '-') || '/' || ps.is_active::text, ' ' order by pr.sku)
  from public.product_supplier ps join public.product pr on pr.id = ps.product_id where ps.supplier_id = p_sup $$;
select pg_temp.fns() as fns_before, pg_temp.state() as state_before \gset
select qual as pol_before from pg_policies where schemaname = 'public' and tablename = 'product_supplier' and policyname = 'product_supplier_select' \gset

\echo '── M0) 가짜 직원 여덟 · 가짜 재료(COST1)'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values
  (gen_random_uuid(), 'cost1-a@test.invalid', 'COST1 admin',                    'admin',      '[]', '{}'),
  (gen_random_uuid(), 'cost1-k@test.invalid', 'COST1 manager with cost key',    'manager',    '["ims","master","purchasing","receiving","cost:read"]', '{}'),
  (gen_random_uuid(), 'cost1-m@test.invalid', 'COST1 manager no cost (reads)',  'manager',    '["ims","master:read","purchasing:read"]', '{}'),
  (gen_random_uuid(), 'cost1-p@test.invalid', 'COST1 purchasing write no cost', 'worker',     '["ims","purchasing"]', '{}'),
  (gen_random_uuid(), 'cost1-w@test.invalid', 'COST1 master write no cost',     'manager',    '["ims","master"]', '{}'),
  (gen_random_uuid(), 'cost1-r@test.invalid', 'COST1 receiving no cost',        'manager',    '["ims","receiving","purchasing"]', '{}'),
  (gen_random_uuid(), 'cost1-z@test.invalid', 'COST1 worker no keys',           'worker',     '["wms"]', '{}'),
  (gen_random_uuid(), 'cost1-s@test.invalid', 'COST1 supervisor',               'supervisor', '[]', '{}');
select max(auth_user_id::text) filter (where email = 'cost1-a@test.invalid') as a_uid, max(auth_user_id::text) filter (where email = 'cost1-k@test.invalid') as k_uid,
       max(auth_user_id::text) filter (where email = 'cost1-m@test.invalid') as m_uid, max(auth_user_id::text) filter (where email = 'cost1-p@test.invalid') as p_uid,
       max(auth_user_id::text) filter (where email = 'cost1-w@test.invalid') as w_uid, max(auth_user_id::text) filter (where email = 'cost1-r@test.invalid') as r_uid,
       max(auth_user_id::text) filter (where email = 'cost1-z@test.invalid') as z_uid, max(auth_user_id::text) filter (where email = 'cost1-s@test.invalid') as s_uid,
       max(id::text) filter (where email = 'cost1-r@test.invalid') as r_id, max(id::text) filter (where email = 'cost1-k@test.invalid') as k_id
from public.ims_staff where email like 'cost1-%@test.invalid' \gset
\set a '{"sub":"' :a_uid '","role":"authenticated"}'
\set k '{"sub":"' :k_uid '","role":"authenticated"}'
\set m '{"sub":"' :m_uid '","role":"authenticated"}'
\set p '{"sub":"' :p_uid '","role":"authenticated"}'
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
\set r '{"sub":"' :r_uid '","role":"authenticated"}'
\set z '{"sub":"' :z_uid '","role":"authenticated"}'
\set s '{"sub":"' :s_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select w.id::text as wh from public.ref_warehouse w where w.is_active order by w.name limit 1 \gset
select b.id::text as bin from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select id::text as tier_ws from public.ref_price_tier where is_active and purpose = 'sale' and code = 1 \gset
select (public.ims_today() - 3)::text as rcv_on \gset
set local session_replication_role = replica;
insert into public.supplier (name, source, is_active, payment_term_name, account_payable_code, currency_id) values ('COST1 Supplier', 'manual', true, 'Due on receipt', '_62_', :'cad'::uuid) returning id::text as sup \gset
insert into public.product (sku, name, source, is_active, sellable) values ('COST1-P1', 'COST1 fixed 9 latest 2.5', 'manual', true, true) returning id::text as p1 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('COST1-P2', 'COST1 latest 3 only', 'manual', true, true) returning id::text as p2 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('COST1-P3', 'COST1 no price', 'manual', true, true) returning id::text as p3 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('COST1-P4', 'COST1 link inactive', 'manual', true, true) returning id::text as p4 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('COST1-P5', 'COST1 no link', 'manual', true, true) returning id::text as p5 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('COST1-P6', 'COST1 receipt by r', 'manual', true, true) returning id::text as p6 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('COST1-P7', 'COST1 receipt by k', 'manual', true, true) returning id::text as p7 \gset
insert into public.product_supplier (product_id, supplier_id, is_active, is_default, source, fixed_cost, cost, last_supplied, currency_id, supplier_sku) values
  (:'p1'::uuid, :'sup'::uuid, true,  true,  'manual', 9,    2.5,  public.ims_today() - 30, :'cad'::uuid, 'S-P1'),
  (:'p2'::uuid, :'sup'::uuid, true,  true,  'manual', null, 3,    public.ims_today() - 20, :'cad'::uuid, 'S-P2'),
  (:'p3'::uuid, :'sup'::uuid, true,  true,  'manual', null, null, null,                    :'cad'::uuid, 'S-P3'),
  (:'p4'::uuid, :'sup'::uuid, false, false, 'manual', null, 1,    public.ims_today() - 40, :'cad'::uuid, 'S-P4'),
  (:'p6'::uuid, :'sup'::uuid, true,  true,  'manual', null, 1.00, public.ims_today() - 30, :'cad'::uuid, 'S-P6'),
  (:'p7'::uuid, :'sup'::uuid, true,  true,  'manual', null, 1.00, public.ims_today() - 30, :'cad'::uuid, 'S-P7');
-- 초안 PO(붙여 넣기) · 확정 PO A(P6 · r 가 확정) · 확정 PO B(P7 · k 가 확정) — 확정 인보이스 2.50 · draft 입고 + 작업 줄
insert into public.po (po_number, supplier_id, currency_id, status, ship_to_warehouse_id, order_date) values ('PO-99903', :'sup'::uuid, :'cad'::uuid, 'draft', :'wh'::uuid, public.ims_today()) returning id::text as po_d \gset
insert into public.po (po_number, supplier_id, currency_id, status, ship_to_warehouse_id, order_date, confirmed_at, created_by) values ('PO-99904', :'sup'::uuid, :'cad'::uuid, 'confirmed', :'wh'::uuid, public.ims_today() - 10, now(), :'r_id'::uuid) returning id::text as po_a \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po_a'::uuid, 1, :'p6'::uuid, 10, 1.00) returning id::text as pl_a \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, total_amount, status, confirmed_at, confirmed_by, doc_kind, created_by) values (:'sup'::uuid, 'COST1-INV-A', public.ims_today() - 5, :'cad'::uuid, 0, 'confirmed', now(), :'r_id'::uuid, 'invoice', :'r_id'::uuid) returning id::text as inv_a \gset
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (:'inv_a'::uuid, 1, 'goods', :'pl_a'::uuid, 10, 2.50, true);
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by) values ('RCV-COST1A', :'po_a'::uuid, :'wh'::uuid, :'rcv_on'::date, 'draft', :'r_id'::uuid) returning id::text as rcv_a \gset
insert into public.po_receipt_work (receipt_id, po_line_id, qty_ea, bin_id, putaway_done, count_method, counted_by, counted_at, putaway_by, putaway_at) values (:'rcv_a'::uuid, :'pl_a'::uuid, 10, :'bin'::uuid, true, 'manual', :'r_id'::uuid, now(), :'r_id'::uuid, now());
insert into public.po (po_number, supplier_id, currency_id, status, ship_to_warehouse_id, order_date, confirmed_at, created_by) values ('PO-99905', :'sup'::uuid, :'cad'::uuid, 'confirmed', :'wh'::uuid, public.ims_today() - 10, now(), :'k_id'::uuid) returning id::text as po_b \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po_b'::uuid, 1, :'p7'::uuid, 5, 1.00) returning id::text as pl_b \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, total_amount, status, confirmed_at, confirmed_by, doc_kind, created_by) values (:'sup'::uuid, 'COST1-INV-B', public.ims_today() - 5, :'cad'::uuid, 0, 'confirmed', now(), :'k_id'::uuid, 'invoice', :'k_id'::uuid) returning id::text as inv_b \gset
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (:'inv_b'::uuid, 1, 'goods', :'pl_b'::uuid, 5, 2.50, true);
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by) values ('RCV-COST1B', :'po_b'::uuid, :'wh'::uuid, :'rcv_on'::date, 'draft', :'k_id'::uuid) returning id::text as rcv_b \gset
insert into public.po_receipt_work (receipt_id, po_line_id, qty_ea, bin_id, putaway_done, count_method, counted_by, counted_at, putaway_by, putaway_at) values (:'rcv_b'::uuid, :'pl_b'::uuid, 5, :'bin'::uuid, true, 'manual', :'k_id'::uuid, now(), :'k_id'::uuid, now());
set local session_replication_role = origin;
select pg_temp.ps_trace(:'sup'::uuid) as ps0 \gset
select pg_temp.chk('M0 fake staff · supplier · P1 ~ P7 · links · PO draft · PO A · B with confirmed invoices · draft receipts', :'ps0',
  format('COST1-P1:2.5/9/%s/true COST1-P2:3/-/%s/true COST1-P3:-/-/-/true COST1-P4:1/-/%s/false COST1-P6:1/-/%s/true COST1-P7:1/-/%s/true', public.ims_today() - 30, public.ims_today() - 20, public.ims_today() - 40, public.ims_today() - 30, public.ims_today() - 30));
\set lines_p1 '[{"sku":"COST1-P1","qty":"2"}]'
\set lines_3  '[{"sku":"COST1-P1","qty":"2"},{"sku":"COST1-P2","qty":"1"},{"sku":"COST1-P3","qty":"4"}]'
\set lines_pasted '[{"sku":"COST1-P2","qty":"1","price":"4.25"}]'
\set formula '{"supplier_id":"' :sup '","currency_id":"' :cad '","freight":"1.1","duty_pct":"0","margin":"0.65","endings":["99"]}'
\set chg_sup '[{"op":"supplier_set","sku":"COST1-P1","supplier_id":"' :sup '","cost":"5","old":{"cost":"1"}}]'
\set chg_fml '[{"op":"price_set","sku":"COST1-P1","tier_id":"' :tier_ws '","price":"1.00","formula":' :formula '}]'

\if :{?mig}
\echo '── S0) 옛 판 — 결함 재현(원가 열쇠 없는 m · w 에게 단가가 샌다 · 시험 갈래만)'
select pg_temp.as_user(:'p', format('select public.po_lines_paste(%L::uuid, %L::jsonb, false)::text', :'po_d', :'lines_p1')) as s0_paste \gset
select pg_temp.as_user(:'m', format('select public.price_formula_preview(%L::jsonb, array[''COST1-P1''])::text', :'formula')) as s0_prev \gset
select pg_temp.as_user(:'w', format('select public.product_update(%L::jsonb, false)::text', :'chg_sup')) as s0_upd \gset
select pg_temp.chk('S0a old paste: p (purchasing write · no cost key) is offered the fixed price (the leak)', pg_temp.j(:'s0_paste')->'lines'->0->>'price_source' || '/' || trim_scale((pg_temp.j(:'s0_paste')->'lines'->0->>'unit_price')::numeric), 'fixed/9');
select pg_temp.chk('S0b old preview: m gets the cost (the leak)', trim_scale((pg_temp.j(:'s0_prev')->'rows'->0->>'cost')::numeric)::text, '2.5');
select pg_temp.chk('S0c old product_update: w (no cost key) sees cost in changed_elsewhere (the leak)', (pg_temp.j(:'s0_upd')->'blocks'->0->>'message' ~ '\(now sku S-P1 · cost 2\.50* · fixed 9(\.0+)?\)')::text, 'true');
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
\if :{?mig2}
\echo '── 시험 적용(rollback 됨):' :mig2
\i :mig2
\endif
\if :{?mig3}
\echo '── 시험 적용(rollback 됨):' :mig3
\i :mig3
\endif
select (not has_column_privilege('authenticated', 'public.product_supplier', 'cost', 'SELECT'))::text as revoked \gset
\echo '── 회수 갈래(1b 뒤인가):' :revoked

\echo '── G1) 착지 — 창구 · 재발행 넷 md5 · definer · ACL'
select pg_temp.chk('G1a landed: paste · preview · latest · update bodies = cost-1a · 1a2 · window exists', regexp_replace(pg_temp.state(), ' relacl=.*$', ''),
  'paste=ce2b79de:true preview=f77403f8:true latest=f4b70da7 update=6d7ec9ff window=true');
select pg_temp.chk('G1b window ACL: authenticated only (no anon · service_role · public)',
  has_function_privilege('authenticated', 'public.product_supplier_costs(uuid[], uuid, boolean)', 'execute')::text || '/' || has_function_privilege('anon', 'public.product_supplier_costs(uuid[], uuid, boolean)', 'execute')::text || '/' || has_function_privilege('service_role', 'public.product_supplier_costs(uuid[], uuid, boolean)', 'execute')::text,
  'true/false/false');
select pg_temp.chk('G1c reissued ACL unchanged: paste · preview = authenticated + service_role · latest_apply = nobody',
  (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_lines_paste', 'price_formula_preview', 'po_receipt_latest_apply', 'product_update')),
  'po_lines_paste:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} po_receipt_latest_apply:{postgres=X/postgres} price_formula_preview:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} product_update:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}');

\echo '── C1) 원가 창구 product_supplier_costs — 있음 = 값 · 없음 = {has_key:false, rows:[]} · 갈래 셋 · 한도 · 시간'
select pg_temp.as_role('authenticated', :'a', format('select public.product_supplier_costs(array[%L, %L, %L, %L, %L]::uuid[])::text', :'p1', :'p2', :'p3', :'p4', :'p5')) as c1_ids \gset
select pg_temp.as_role('authenticated', :'k', format('select public.product_supplier_costs(null, %L::uuid)::text', :'sup')) as c1_sup \gset
select pg_temp.as_role('authenticated', :'m', format('select public.product_supplier_costs(array[%L]::uuid[])::text', :'p1')) as c1_m \gset
select pg_temp.as_role('authenticated', :'z', format('select public.product_supplier_costs(null, %L::uuid)::text', :'sup')) as c1_z \gset
select pg_temp.as_role('authenticated', :'w', format('select public.product_supplier_costs(null, null, true)::text')) as c1_w_stats \gset
select pg_temp.as_role('authenticated', :'s', format('select public.product_supplier_costs(null, %L::uuid, true)::text', :'sup')) as c1_stats \gset
select pg_temp.as_role('authenticated', :'k', 'select public.product_supplier_costs((select array_agg(gen_random_uuid()) from generate_series(1, 1001)))::text') as c1_cap \gset
select pg_temp.as_role('authenticated', :'k', 'select public.product_supplier_costs()::text') as c1_none \gset
select pg_temp.as_role('authenticated', :'k', format('select public.product_supplier_costs(array[%L, %L]::uuid[], %L::uuid)::text', :'p1', :'p2', :'sup')) as c1_both \gset
select pg_temp.chk('C1a admin · ids: four links (P4 inactive too · P5 none) with cost · fixed · is_active',
  (select string_agg((x->>'product_id' = :'p1')::text || ':' || coalesce(trim_scale((x->>'cost')::numeric)::text, '-') || '/' || coalesce(trim_scale((x->>'fixed_cost')::numeric)::text, '-') || '/' || (x->>'is_active'), ' ' order by x->>'product_id' = :'p1' desc, x->>'cost')
     from jsonb_array_elements(pg_temp.j(:'c1_ids')->'rows') x) || ' key=' || (pg_temp.j(:'c1_ids')->>'has_key'),
  'true:2.5/9/true false:1/-/false false:3/-/true false:-/-/true key=true');
select pg_temp.chk('C1b cost key · supplier mode: every line of the supplier (6 · inactive too) · values as the table',
  (select count(*) from jsonb_array_elements(pg_temp.j(:'c1_sup')->'rows'))::text || ' ' ||
  (select string_agg(pr.sku || ':' || coalesce(trim_scale((x->>'cost')::numeric)::text, '-'), ' ' order by pr.sku) from jsonb_array_elements(pg_temp.j(:'c1_sup')->'rows') x join public.product pr on pr.id = (x->>'product_id')::uuid),
  '6 COST1-P1:2.5 COST1-P2:3 COST1-P3:- COST1-P4:1 COST1-P6:1 COST1-P7:1');
select pg_temp.chk('C1c no cost key (manager master:read · purchasing:read): empty result, not an error', :'c1_m', '{"rows": [], "has_key": false}');
select pg_temp.chk('C1d no keys at all (worker): same empty result', :'c1_z', '{"rows": [], "has_key": false}');
select pg_temp.chk('C1e stats · supervisor (cost by role): n 5 · default 5 · no price 1 (P3) · last supplied = newest active line',
  (select (x->>'n') || '/' || (x->>'n_default') || '/' || (x->>'n_no_price') || '/' || (x->>'last_supplied') from jsonb_array_elements(pg_temp.j(:'c1_stats')->'stats') x where x->>'supplier_id' = :'sup') || ' n_sup=' || jsonb_array_length(pg_temp.j(:'c1_stats')->'stats'),
  format('5/5/1/%s n_sup=1', public.ims_today() - 20));
select pg_temp.chk('C1f stats without the key (master write only): has_key false · no stats', :'c1_w_stats', '{"rows": [], "has_key": false}');
select pg_temp.chk('C1g 1,001 ids refused', :'c1_cap', 'ERR P0001: Too many products in one call (1001 — the limit is 1000) — split the list');
select pg_temp.chk('C1h no ids and no supplier refused', :'c1_none', 'ERR P0001: Give product ids or a supplier — nothing was read');
select pg_temp.chk('C1i ids + supplier narrows to that supplier', (select count(*) from jsonb_array_elements(pg_temp.j(:'c1_both')->'rows'))::text, '2');
select clock_timestamp() as t1a \gset
select pg_temp.as_role('authenticated', :'a', format('select public.product_supplier_costs(null, %L::uuid)::text', :'big_sup')) as c1_big \gset
select clock_timestamp() as t1b \gset
select pg_temp.as_role('authenticated', :'a', 'select public.product_supplier_costs(null, null, true)::text') as c1_allstats \gset
select clock_timestamp() as t1c \gset
select pg_temp.chk('C1j biggest real supplier (read only): every line in one call', (select count(*) from jsonb_array_elements(pg_temp.j(:'c1_big')->'rows'))::text, :'big_n');
select pg_temp.chk('C1k stats for every supplier = suppliers with active lines', jsonb_array_length(pg_temp.j(:'c1_allstats')->'stats')::text, (select count(distinct supplier_id) from public.product_supplier where is_active)::text);
\echo '── 창구 시간(8 초 안이어야) — 공급처 한 곳 · 전체 통계'
select :big_n as biggest_supplier_lines, (:'t1b'::timestamptz - :'t1a'::timestamptz) as supplier_mode_time, (:'t1c'::timestamptz - :'t1b'::timestamptz) as all_stats_time;

\echo '── C2) po_lines_paste — 765: 열쇠 없음 = 0 · none · 문장 · 줄은 선다 · 열쇠 있음 = Fixed → Latest · pasted 는 열쇠와 무관 · 문은 purchasing 쓰기'
select pg_temp.as_user(:'p', format('select public.po_lines_paste(%L::uuid, %L::jsonb, false)::text', :'po_d', :'lines_3')) as c2_p_prev \gset
select pg_temp.as_user(:'k', format('select public.po_lines_paste(%L::uuid, %L::jsonb, false)::text', :'po_d', :'lines_3')) as c2_k_prev \gset
select pg_temp.as_user(:'p', format('select public.po_lines_paste(%L::uuid, %L::jsonb, false)::text', :'po_d', :'lines_pasted')) as c2_p_pasted \gset
select pg_temp.as_user(:'z', format('select public.po_lines_paste(%L::uuid, %L::jsonb, false)::text', :'po_d', :'lines_p1')) as c2_z \gset
select pg_temp.as_user(:'m', format('select public.po_lines_paste(%L::uuid, %L::jsonb, false)::text', :'po_d', :'lines_p1')) as c2_m \gset
select pg_temp.as_user(:'p', format('select public.po_lines_paste(%L::uuid, %L::jsonb, true)::text', :'po_d', :'lines_3')) as c2_p_commit \gset
select string_agg(pl.line_no || ':' || pr.sku || ':' || trim_scale(pl.unit_price) || ':' || coalesce(pl.supplier_sku, '-'), ' ' order by pl.line_no) as c2_lines from public.po_line pl join public.product pr on pr.id = pl.product_id where pl.po_id = :'po_d'::uuid \gset
select pg_temp.chk('C2a purchasing write · no cost key · preview: P1 0/none · P2 0/none · P3 0/none · verdict ok · message no_cost_permission · supplier_sku still given',
  (select string_agg((x->>'sku') || ':' || trim_scale((x->>'unit_price')::numeric) || '/' || (x->>'price_source') || '/' || (x->>'verdict') || '/' || (x->>'supplier_sku') || '/' || (x->>'message'), ' ' order by x->>'n') from jsonb_array_elements(pg_temp.j(:'c2_p_prev')->'lines') x),
  'COST1-P1:0/none/ok/S-P1/no_cost_permission — price 0, fill in by hand COST1-P2:0/none/ok/S-P2/no_cost_permission — price 0, fill in by hand COST1-P3:0/none/ok/S-P3/no_cost_permission — price 0, fill in by hand');
select pg_temp.chk('C2b cost key · preview: P1 9/fixed · P2 3/latest · P3 0/none no_price (as before)',
  (select string_agg((x->>'sku') || ':' || trim_scale((x->>'unit_price')::numeric) || '/' || (x->>'price_source') || '/' || (x->>'message'), ' ' order by x->>'n') from jsonb_array_elements(pg_temp.j(:'c2_k_prev')->'lines') x),
  'COST1-P1:9/fixed/ COST1-P2:3/latest/ COST1-P3:0/none/no_price — fixed and latest are both empty');
select pg_temp.chk('C2c no cost key · pasted price 4.25 is used (624 · key-free)',
  trim_scale((pg_temp.j(:'c2_p_pasted')->'lines'->0->>'unit_price')::numeric)::text || '/' || (pg_temp.j(:'c2_p_pasted')->'lines'->0->>'price_source') || '/' || (pg_temp.j(:'c2_p_pasted')->'lines'->0->>'message'), '4.25/pasted/');
select pg_temp.chk('C2d worker without purchasing refused by the gate (unchanged)', (:'c2_z' like 'ERR P0001:%purchasing%')::text, 'true');
select pg_temp.chk('C2e purchasing:read refused by the gate (unchanged)', (:'c2_m' like 'ERR P0001:%purchasing%')::text, 'true');
select pg_temp.chk('C2f no cost key · commit: three lines inserted at 0 (the line stands · fill in by hand)',
  (pg_temp.j(:'c2_p_commit')->'summary'->>'inserted') || ' | ' || :'c2_lines', '3 | 1:COST1-P1:0:S-P1 2:COST1-P2:0:S-P2 3:COST1-P3:0:S-P3');

\echo '── C3) price_formula_preview — 열쇠 없음 = 거부 문장(첫 줄) · 열쇠 있음 = cost 그대로'
select pg_temp.as_user(:'m', format('select public.price_formula_preview(%L::jsonb, array[''COST1-P1''])::text', :'formula')) as c3_m \gset
select pg_temp.as_user(:'z', format('select public.price_formula_preview(%L::jsonb, array[''COST1-P1''])::text', :'formula')) as c3_z \gset
select pg_temp.as_user(:'w', format('select public.price_formula_preview(%L::jsonb, array[''COST1-P1''])::text', :'formula')) as c3_w \gset
select pg_temp.as_user(:'k', format('select public.price_formula_preview(%L::jsonb, array[''COST1-P1'', ''COST1-P3''])::text', :'formula')) as c3_k \gset
select pg_temp.chk('C3a manager without cost key refused', :'c3_m', 'ERR P0001: Price formula preview needs the cost permission — ask an admin to switch it on in Staff — nothing was read');
select pg_temp.chk('C3b worker without keys refused (same first line)', :'c3_z', 'ERR P0001: Price formula preview needs the cost permission — ask an admin to switch it on in Staff — nothing was read');
select pg_temp.chk('C3c master write without cost key refused (the screen key alone is not enough)', :'c3_w', 'ERR P0001: Price formula preview needs the cost permission — ask an admin to switch it on in Staff — nothing was read');
select pg_temp.chk('C3d cost key: P1 cost 2.5 · P3 flagged no_cost · calc present',
  (select string_agg((x->>'sku') || ':' || coalesce(trim_scale((x->>'cost')::numeric)::text, '-') || ':' || (x->'flags')::text || ':' || (x->'calc' is not null)::text, ' ' order by x->>'sku') from jsonb_array_elements(pg_temp.j(:'c3_k')->'rows') x),
  'COST1-P1:2.5:[]:true COST1-P3:-:["no_cost"]:true');

\echo '── C4) product_update — changed_elsewhere(:713) · formula_mismatch(:656) 문장에 열쇠 없으면 hidden'
select pg_temp.as_user(:'w', format('select public.product_update(%L::jsonb, false)::text', :'chg_sup')) as c4_w \gset
select pg_temp.as_user(:'k', format('select public.product_update(%L::jsonb, false)::text', :'chg_sup')) as c4_k \gset
select pg_temp.as_user(:'w', format('select public.product_update(%L::jsonb, false)::text', :'chg_fml')) as c4_w_f \gset
select pg_temp.as_user(:'k', format('select public.product_update(%L::jsonb, false)::text', :'chg_fml')) as c4_k_f \gset
select pg_temp.chk('C4a master write · no cost key: changed_elsewhere without the numbers', pg_temp.j(:'c4_w')->'blocks'->0->>'code' || ' | ' || (pg_temp.j(:'c4_w')->'blocks'->0->>'message'),
  'changed_elsewhere | Someone just changed supplier COST1 Supplier of COST1-P1 (now sku S-P1 · cost hidden · fixed hidden) — check again — nothing was saved');
select pg_temp.chk('C4b cost key: changed_elsewhere with the numbers (as before · column scale 7)', (pg_temp.j(:'c4_k')->'blocks'->0->>'message' ~ '^Someone just changed supplier COST1 Supplier of COST1-P1 \(now sku S-P1 · cost 2\.50* · fixed 9(\.0+)?\) — check again — nothing was saved$')::text, 'true');
select pg_temp.chk('C4c master write · no cost key: formula_mismatch warning says "from cost hidden"',
  (select string_agg((x->>'code') || ':' || ((x->>'message') like '%from cost hidden) — it will be saved as a manual price')::text, ' ') from jsonb_array_elements(pg_temp.j(:'c4_w_f')->'warnings') x where x->>'code' = 'formula_mismatch') || ' blocks=' || jsonb_array_length(pg_temp.j(:'c4_w_f')->'blocks'),
  'formula_mismatch:true blocks=0');
select pg_temp.chk('C4d cost key: formula_mismatch warning says "from cost 2.5"',
  (select string_agg((x->>'code') || ':' || ((x->>'message') ~ 'from cost 2\.50*\) — it will be saved as a manual price$')::text, ' ') from jsonb_array_elements(pg_temp.j(:'c4_k_f')->'warnings') x where x->>'code' = 'formula_mismatch'),
  'formula_mismatch:true');
select pg_temp.chk('C4e no cost in any other block/warning text for w (whole return)', ((:'c4_w' || :'c4_w_f') ~ '2\.50*|cost 9|fixed 9')::text, 'false');

\echo '── C5) 입고 확정 → po_receipt_latest_apply 반환 — 열쇠 없는 r: old_cost · new_cost 없음(갱신은 됨) · 열쇠 있는 k: 1 → 2.5'
select pg_temp.as_user(:'r', format('select public.po_receipt_confirm(%L::uuid)::text', :'rcv_a')) as c5_r \gset
select pg_temp.as_user(:'k', format('select public.po_receipt_confirm(%L::uuid)::text', :'rcv_b')) as c5_k \gset
select pg_temp.ps_trace(:'sup'::uuid) as ps5 \gset
select pg_temp.chk('C5a receiving · no cost key: confirmed · latest_updated P6 keeps sku · supplier · new_last_supplied · drops old_cost · new_cost',
  (pg_temp.j(:'c5_r')->>'status') || ' | ' || (select string_agg((u->>'sku') || ':' || (u ? 'old_cost')::text || '/' || (u ? 'new_cost')::text || '/' || (u ? 'new_last_supplied')::text || '/' || (u ? 'supplier')::text || '/' || (u->>'link_active'), ' ') from jsonb_array_elements(pg_temp.j(:'c5_r')->'latest_updated') u),
  'confirmed | COST1-P6:false/false/true/true/true');
select pg_temp.chk('C5b cost key: confirmed · latest_updated P7 old_cost 1 → new_cost 2.5',
  (pg_temp.j(:'c5_k')->>'status') || ' | ' || (select string_agg((u->>'sku') || ':' || trim_scale((u->>'old_cost')::numeric) || '→' || trim_scale((u->>'new_cost')::numeric), ' ') from jsonb_array_elements(pg_temp.j(:'c5_k')->'latest_updated') u),
  'confirmed | COST1-P7:1→2.5');
select pg_temp.chk('C5c both links were updated regardless of the key (P6 · P7 → 2.5 · last_supplied = received_on)',
  :'ps5', format('COST1-P1:2.5/9/%s/true COST1-P2:3/-/%s/true COST1-P3:-/-/-/true COST1-P4:1/-/%s/false COST1-P6:2.5/-/%s/true COST1-P7:2.5/-/%s/true', public.ims_today() - 30, public.ims_today() - 20, public.ims_today() - 40, :'rcv_on', :'rcv_on'));

\if :revoked
\echo '── C6 ⓐ) 1b 뒤 — authenticated 는 cost · fixed_cost 를 못 읽고(42501) 원가 아닌 칸은 읽는다 · 창구 · 정의 창구(definer)는 열쇠로 값 · product_list 는 돈다'
select pg_temp.as_role('authenticated', :'m', format('select count(*)::text from public.product_supplier where supplier_id = %L::uuid and cost is not null', :'sup')) as c6_cost \gset
select pg_temp.as_role('authenticated', :'m', format('select coalesce(sum(fixed_cost), 0)::text from public.product_supplier where supplier_id = %L::uuid', :'sup')) as c6_fixed \gset
select pg_temp.as_role('authenticated', :'m', format('select count(*)::text from (select * from public.product_supplier where supplier_id = %L::uuid) x', :'sup')) as c6_star \gset
select pg_temp.as_role('authenticated', :'m', format('select count(*)::text from public.product_supplier where supplier_id = %L::uuid and cost is null', :'sup')) as c6_where \gset
select pg_temp.as_role('authenticated', :'m', format('select string_agg(supplier_sku || '':'' || is_default::text || '':'' || coalesce(last_supplied::text, ''-''), '' '' order by supplier_sku) from public.product_supplier where supplier_id = %L::uuid and is_active', :'sup')) as c6_ok \gset
select pg_temp.as_role('authenticated', :'m', format('select count(*)::text from public.product_supplier where supplier_id = %L::uuid', :'sup')) as c6_count \gset
select pg_temp.as_role('authenticated', :'k', format('select count(*)::text from public.product_supplier where supplier_id = %L::uuid and cost is not null', :'sup')) as c6_k_direct \gset
select pg_temp.as_role('authenticated', :'k', format('select (public.product_supplier_costs(array[%L]::uuid[])->''rows''->0->>''cost'')', :'p1')) as c6_k_win \gset
select pg_temp.as_role('authenticated', :'k', format('select (public.po_lines_paste(%L::uuid, %L::jsonb, false)->''lines''->0->>''price_source'')', :'po_d', '[{"sku":"COST1-P5","qty":"1"},{"sku":"COST1-P6","qty":"1"}]')) as c6_k_paste \gset
select pg_temp.as_role('authenticated', :'m', format('select count(*)::text from public.product_list(null, null, null, %L::uuid, ''single'', true, false, 50, 0)', :'sup')) as c6_list \gset
select pg_temp.as_role('authenticated', :'m', format('select count(*)::text from public.product p where exists (select 1 from public.product_supplier ps where ps.product_id = p.id and ps.supplier_id = %L::uuid and ps.is_active)', :'sup')) as c6_exists \gset
select pg_temp.chk('C6a1 after 1b · m: select cost = 42501', :'c6_cost', 'ERR 42501: permission denied for table product_supplier');
select pg_temp.chk('C6a2 after 1b · m: sum(fixed_cost) = 42501', :'c6_fixed', 'ERR 42501: permission denied for table product_supplier');
select pg_temp.chk('C6a3 after 1b · m: select * = 42501 (products.html:443 · supplier-products.html:205 shape)', :'c6_star', 'ERR 42501: permission denied for table product_supplier');
select pg_temp.chk('C6a4 after 1b · m: where cost is null = 42501 (supplier-products.html:210 or() shape)', :'c6_where', 'ERR 42501: permission denied for table product_supplier');
select pg_temp.chk('C6a5 after 1b · m: non-cost columns still readable (policy purchasing:read)', :'c6_ok', format('S-P1:true:%s S-P2:true:%s S-P3:true:- S-P6:true:%s S-P7:true:%s', public.ims_today() - 30, public.ims_today() - 20, :'rcv_on', :'rcv_on'));
select pg_temp.chk('C6a6 after 1b · k: direct select cost = 42501 even with the key (only the window gives it)', :'c6_k_direct', 'ERR 42501: permission denied for table product_supplier');
select pg_temp.chk('C6a7 after 1b · k: window still gives the value (definer)', trim_scale(:'c6_k_win'::numeric)::text, '2.5');
select pg_temp.chk('C6a8 after 1b · k: po_lines_paste as authenticated still suggests latest for P6 (definer · P5 no_link first)', :'c6_k_paste', 'none');
select pg_temp.chk('C6a9 after 1b · m: product_list filtered by supplier still runs (exists on non-cost columns)', (:'c6_list' !~ '^ERR' and :'c6_list' = :'c6_exists')::text || ' n=' || :'c6_list', 'true n=' || :'c6_exists');
select pg_temp.chk('C6a10 after 1b: relacl authenticated=xtm · 15 columns · cost · fixed_cost 0',
  (select relacl::text from pg_class where oid = 'public.product_supplier'::regclass) || ' | ' ||
  (select count(*) from information_schema.column_privileges where table_schema = 'public' and table_name = 'product_supplier' and grantee = 'authenticated' and privilege_type = 'SELECT') || '/' ||
  (select count(*) from information_schema.column_privileges where table_schema = 'public' and table_name = 'product_supplier' and grantee = 'authenticated' and privilege_type = 'SELECT' and column_name in ('cost', 'fixed_cost')),
  '{postgres=arwdDxtm/postgres,authenticated=xtm/postgres,service_role=arwdDxtm/postgres} | 15/0');
\echo '── (정보) 1b 뒤 count(*) 만 — system-check.html:123 head count `*` 의 PostgREST 꼴은 화면 시험에서 본다:' :c6_count
\else
\echo '── C6 ⓑ) 1b 전 — authenticated(purchasing:read)는 아직 cost 를 읽는다(옛 화면이 그대로 도는 까닭) · 창구 · 재발행은 이미 선다'
select pg_temp.as_role('authenticated', :'m', format('select count(*)::text from public.product_supplier where supplier_id = %L::uuid and cost is not null', :'sup')) as c6_cost \gset
select pg_temp.as_role('authenticated', :'k', format('select (public.product_supplier_costs(array[%L]::uuid[])->''rows''->0->>''cost'')', :'p1')) as c6_k_win \gset
select pg_temp.as_role('authenticated', :'m', format('select count(*)::text from (select * from public.product_supplier where supplier_id = %L::uuid) x', :'sup')) as c6_star \gset
select pg_temp.chk('C6b1 before 1b · m: cost still readable directly (old screens keep working until 1b)', :'c6_cost', '5');
select pg_temp.chk('C6b2 before 1b · m: select * still works', :'c6_star', '6');
select pg_temp.chk('C6b3 before 1b · k: window gives the value', trim_scale(:'c6_k_win'::numeric)::text, '2.5');
select pg_temp.chk('C6b4 before 1b: relacl authenticated=rxtm (1b not applied)', (select relacl::text from pg_class where oid = 'public.product_supplier'::regclass), '{postgres=arwdDxtm/postgres,authenticated=rxtm/postgres,service_role=arwdDxtm/postgres}');
\endif

\echo '── Z) 무접촉 — 다른 함수 md5 · 정책 · 가짜 밖 product_supplier 행'
select pg_temp.chk('Z1 other functions unchanged (confirm_by · post_now_by · shells · wms_recv_confirm · product_create_core · product_export · stk_value_total · product_list · ims_can_view(_cost) · price_formula_calc · _save)', pg_temp.fns(), :'fns_before');
select pg_temp.chk('Z2 product_supplier_select policy unchanged (purchasing ∨ master ∨ cost)', (select qual from pg_policies where schemaname = 'public' and tablename = 'product_supplier' and policyname = 'product_supplier_select'), :'pol_before');
select pg_temp.chk('Z3 real product_supplier rows untouched inside the transaction (fingerprint without COST1 rows)',
  (select sum(('x' || left(md5(ps::text), 15))::bit(60)::bigint)::text || '/' || count(*) from public.product_supplier ps where ps.supplier_id <> :'sup'::uuid), :'fp_ps' || '/' || :'n_ps');

\echo '── 결과'
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, left(got, 300) as got, left(want, 300) as want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch,
       case when :'revoked'::boolean then :EXPECT_TRIAL_B else :EXPECT_TRIAL_A end as expect_ok_trial, case when :'revoked'::boolean then :EXPECT_CHECK_B else :EXPECT_CHECK_A end as expect_ok_check from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── rollback 뒤 — 실제 행 무변 · 가짜 흔적 0 · 시퀀스 머리'
select (select count(*) from public.product_supplier) = :n_ps as ps_same, (select sum(('x' || left(md5(ps::text), 15))::bit(60)::bigint) from public.product_supplier ps) = :fp_ps as ps_fingerprint_same,
       (select count(*) from public.po) = :n_po as po_same, (select count(*) from public.po_line) = :n_pol as po_line_same, (select count(*) from public.product) = :n_prod as product_same,
       (select count(*) from public.supplier) = :n_sup as supplier_same, (select count(*) from public.ims_staff) = :n_staff as staff_same, (select count(*) from public.po_receipt) = :n_rcv as receipt_same,
       (select count(*) from public.po_invoice) = :n_inv as invoice_same, (select count(*) from public.inv_ledger) = :n_led as ledger_same,
       (select count(*) from public.supplier where name like 'COST1 %') + (select count(*) from public.product where sku like 'COST1-%') + (select count(*) from public.ims_staff where email like 'cost1-%') + (select count(*) from public.po where po_number in ('PO-99903', 'PO-99904', 'PO-99905')) as fake_left,
       (select relacl::text from pg_class where oid = 'public.product_supplier'::regclass) as relacl_now;
select :po_seq_last as po_seq_before, last_value as po_seq_after, :'po_seq_called' as called_before, is_called as called_after from public.po_number_seq;
select :rcv_seq_last as rcv_seq_before, last_value as rcv_seq_after, :'rcv_seq_called' as called_before, is_called as called_after from public.po_receipt_number_seq;
