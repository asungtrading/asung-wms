-- supabase/tests/exp_1_check.sql — exp-1 내보내기 창구 검증 (2026-10-26 · 판정 699 · 700 · 759 ~ 764)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — begin → (-v mig 면 \i) → 가짜 직원 여섯(트랜잭션 안 · rollback) → 칸 목록 · 거부 · 행 수 · 꼴 · 크기 → rollback
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/<exp_1 파일>.sql -f supabase/tests/exp_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 새 함수만 세우는 차수라 적용 전 마른 실행은 첫 호출에서 「function does not exist」 로 선다(정상)
--   기대 OK: 시험 = 확인 = 아래 EXPECT_OK
--   쓰기 0 — 창구는 stable(착지가 본다) · 가짜 직원 행은 rollback · 실제 행 수 전후 대조
\set ON_ERROR_STOP on
\set EXPECT_OK 36
\pset pager off
select count(*) as n_prod, (select count(*) from public.customer) as n_cust, (select count(*) from public.supplier) as n_sup,
       (select count(*) from public.product_supplier) as n_ps, (select count(*) from public.customer_address) as n_ca, (select count(*) from public.ims_staff) as n_staff
from public.product \gset
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
-- 가짜 직원 여섯(트랜잭션 안 · auth_user_id 새 uuid · 실제 직원 무접촉)
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values
  (gen_random_uuid(), 'exp1-admin@test.invalid',  'exp1 admin',            'admin',   '[]', true),
  (gen_random_uuid(), 'exp1-mgr@test.invalid',    'exp1 manager no cost',  'manager', '["master", "purchasing:read", "sales:read"]', true),
  (gen_random_uuid(), 'exp1-sales@test.invalid',  'exp1 sales read',       'worker',  '["sales:read"]', true),
  (gen_random_uuid(), 'exp1-master@test.invalid', 'exp1 master read',      'worker',  '["master:read"]', true),
  (gen_random_uuid(), 'exp1-purch@test.invalid',  'exp1 purchasing read',  'worker',  '["purchasing:read"]', true),
  (gen_random_uuid(), 'exp1-none@test.invalid',   'exp1 no keys',          'worker',  '[]', true);
select max(auth_user_id::text) filter (where email = 'exp1-admin@test.invalid') as u_a, max(auth_user_id::text) filter (where email = 'exp1-mgr@test.invalid') as u_m,
       max(auth_user_id::text) filter (where email = 'exp1-sales@test.invalid') as u_s, max(auth_user_id::text) filter (where email = 'exp1-master@test.invalid') as u_w,
       max(auth_user_id::text) filter (where email = 'exp1-purch@test.invalid') as u_p, max(auth_user_id::text) filter (where email = 'exp1-none@test.invalid') as u_n
from public.ims_staff where email like 'exp1-%@test.invalid' \gset
-- 꼴 시험 재료(postgres 로 고른다 · 실제 행을 읽기만)
select p.sku as sku_bc2, (select b.barcode from public.product_barcode b where b.product_id = p.id and b.is_active order by b.is_primary desc, b.barcode limit 1) as bc_first
from public.product p where (select count(*) from public.product_barcode b where b.product_id = p.id and b.is_active) = 2 order by p.sku limit 1 \gset
select p.sku as sku_sup2, (select s.name from public.product_supplier ps join public.supplier s on s.id = ps.supplier_id where ps.product_id = p.id and ps.is_active and ps.is_default) as sup_default
from public.product p where (select count(*) from public.product_supplier ps where ps.product_id = p.id and ps.is_active) >= 2
  and exists (select 1 from public.product_supplier ps where ps.product_id = p.id and ps.is_active and ps.is_default) order by p.sku limit 1 \gset
select p.sku as sku_nodef from public.product p where p.is_active and p.parent_product_id is null
  and not exists (select 1 from public.product_supplier ps where ps.product_id = p.id and ps.is_active and ps.is_default) order by p.sku limit 1 \gset
select c.name as cust_multi, (select a.line1 from public.customer_address a where a.customer_id = c.id and a.is_active and a.type = 'Billing' and a.is_default_for_type) as cust_bill1
from public.customer c where (select count(*) from public.customer_address a where a.customer_id = c.id and a.is_active) >= 3
  and (select count(*) from public.customer c2 where c2.name = c.name) = 1 order by c.name limit 1 \gset
select (select count(*) from public.product p where p.is_active and p.parent_product_id is null) as want_prod_default,
       (select count(*) from public.customer where is_active) as want_cust_active,
       (select count(*) from public.supplier where is_active and is_purchasable is true and is_discontinued is false) as want_sup_reader,
       (select count(*) from public.supplier where is_active and is_purchasable is null) as want_sup_unset,
       (select count(*) from public.ref_price_tier where is_active and purpose in ('sale', 'compare')) as want_tiers \gset

-- ── C1 칸 목록: 원가 칸 · 연락처 칸 · reference 등급(759 · 760 · 761) ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_a', 'role', 'authenticated')::text, true);
set local role authenticated;
select (select count(*) from jsonb_array_elements(public.export_columns('product')->'columns') c where c->>'key' in ('default_fixed_cost', 'default_latest_cost')) as a_cost,
       (select count(*) from jsonb_array_elements(public.export_columns('product')->'columns') c where c->>'key' like 'price\_%') as a_tiers,
       (select count(*) from jsonb_array_elements(public.export_columns('product')->'columns') c where c->>'label' ilike '%REFERENCE%') as a_ref,
       (select count(*) from jsonb_array_elements(public.export_columns('customer')->'columns') c where c->>'group' in ('Billing address', 'Shipping address', 'Contact')) as a_contact,
       (select string_agg(c->>'key', ',' order by c->>'key') from jsonb_array_elements(public.export_columns('product')->'columns') c where (c->>'default')::boolean) as a_defaults \gset
reset role;
select pg_temp.chk('C1a admin: cost columns listed', :'a_cost', '2');
select pg_temp.chk('C1b admin: price tiers = sale + compare (no reference)', :'a_tiers', :'want_tiers');
select pg_temp.chk('C1c nobody sees REFERENCECOST (admin)', :'a_ref', '0');
select pg_temp.chk('C1d admin: contact/address columns listed', :'a_contact', '17');
select pg_temp.chk('C1e default product columns', :'a_defaults', 'barcodes,brand,category,default_supplier,is_active,name,price_1,sku');
select set_config('request.jwt.claims', json_build_object('sub', :'u_m', 'role', 'authenticated')::text, true);
set local role authenticated;
select (select count(*) from jsonb_array_elements(public.export_columns('product')->'columns') c where c->>'key' in ('default_fixed_cost', 'default_latest_cost')) as m_cost,
       (select count(*) from jsonb_array_elements(public.export_columns('customer')->'columns') c where c->>'group' in ('Billing address', 'Shipping address', 'Contact')) as m_contact \gset
do $$ begin perform public.product_export(p_columns => array['sku', 'default_latest_cost']); perform set_config('app.err', 'NO ERROR', true);
  exception when others then perform set_config('app.err', sqlerrm, true); end $$;
select current_setting('app.err') as m_force_cost \gset
do $$ begin perform public.product_export(p_columns => array['sku', 'price_8']); perform set_config('app.err', 'NO ERROR', true);
  exception when others then perform set_config('app.err', sqlerrm, true); end $$;
select current_setting('app.err') as m_force_ref \gset
reset role;
select pg_temp.chk('C1f manager without cost key: no cost columns (759 · 764)', :'m_cost', '0');
select pg_temp.chk('C1g manager with master write: contact columns listed (761)', :'m_contact', '17');
select pg_temp.chk('C1h forcing a cost column is refused', :'m_force_cost', 'You cannot export these columns: default_latest_cost — nothing was exported');
select pg_temp.chk('C1i forcing the reference tier is refused (760)', :'m_force_ref', 'Unknown columns: price_8 — nothing was exported');
select set_config('request.jwt.claims', json_build_object('sub', :'u_s', 'role', 'authenticated')::text, true);
set local role authenticated;
select (select count(*) from jsonb_array_elements(public.export_columns('customer')->'columns') c where c->>'group' in ('Billing address', 'Shipping address', 'Contact')) as s_contact,
       (select count(*) from jsonb_array_elements(public.export_columns('customer')->'columns')) as s_all \gset
do $$ begin perform public.customer_export(p_columns => array['name', 'contact_email']); perform set_config('app.err', 'NO ERROR', true);
  exception when others then perform set_config('app.err', sqlerrm, true); end $$;
select current_setting('app.err') as s_force_contact \gset
do $$ begin perform public.product_export(p_columns => array['sku']); perform set_config('app.err', 'NO ERROR', true);
  exception when others then perform set_config('app.err', sqlerrm, true); end $$;
select current_setting('app.err') as s_prod_door \gset
reset role;
select pg_temp.chk('C1j sales read only: no contact/address columns (761)', :'s_contact', '0');
select pg_temp.chk('C1k sales read only: customer basic columns = 20', :'s_all', '20');
select pg_temp.chk('C1l sales read only: forcing contact_email is refused', :'s_force_contact', 'You cannot export these columns: contact_email — nothing was exported');
select pg_temp.chk('C1m sales read only: product door refused', :'s_prod_door', 'You cannot export products — ask an admin for the Products (master) screen key — nothing was exported');

-- ── C2 문 · 칸 검사 ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_n', 'role', 'authenticated')::text, true);
set local role authenticated;
do $$ begin perform public.customer_export(p_columns => array['name']); perform set_config('app.err', 'NO ERROR', true);
  exception when others then perform set_config('app.err', sqlerrm, true); end $$;
select current_setting('app.err') as n_cust_door \gset
do $$ begin perform public.export_columns('supplier'); perform set_config('app.err', 'NO ERROR', true);
  exception when others then perform set_config('app.err', sqlerrm, true); end $$;
select current_setting('app.err') as n_sup_cols \gset
reset role;
select pg_temp.chk('C2a no keys: customer door refused', :'n_cust_door', 'You cannot export customers — ask an admin for the Customers (sales) screen key — nothing was exported');
select pg_temp.chk('C2b no keys: supplier column list refused', :'n_sup_cols', 'You cannot export suppliers — nothing was read');
select set_config('request.jwt.claims', json_build_object('sub', :'u_w', 'role', 'authenticated')::text, true);
set local role authenticated;
do $$ begin perform public.product_export(p_columns => array['sku', 'nope']); perform set_config('app.err', 'NO ERROR', true);
  exception when others then perform set_config('app.err', sqlerrm, true); end $$;
select current_setting('app.err') as w_unknown \gset
do $$ begin perform public.product_export(p_columns => array['sku', 'sku']); perform set_config('app.err', 'NO ERROR', true);
  exception when others then perform set_config('app.err', sqlerrm, true); end $$;
select current_setting('app.err') as w_twice \gset
do $$ begin perform public.product_export(p_columns => array[]::text[]); perform set_config('app.err', 'NO ERROR', true);
  exception when others then perform set_config('app.err', sqlerrm, true); end $$;
select current_setting('app.err') as w_empty \gset
do $$ begin perform public.export_catalog('product'); perform set_config('app.err', 'NO ERROR', true);
  exception when others then perform set_config('app.err', sqlerrm, true); end $$;
select current_setting('app.err') as w_inner \gset
select (public.supplier_export(p_columns => array['name'])->>'forced_filter') as w_sup_forced \gset
reset role;
select pg_temp.chk('C2c unknown column refused', :'w_unknown', 'Unknown columns: nope — nothing was exported');
select pg_temp.chk('C2d same column twice refused', :'w_twice', 'These columns are picked twice: sku — nothing was exported');
select pg_temp.chk('C2e empty pick refused', :'w_empty', 'Pick at least one column — nothing was exported');
select pg_temp.chk('C2f inner function not callable', :'w_inner', 'permission denied for function export_catalog');
select pg_temp.chk('C2g master read: supplier door open (master view) and filter forced', :'w_sup_forced', 'true');

-- ── C3 행 = 지금 목록의 거르기 그대로(700) ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_m', 'role', 'authenticated')::text, true);
set local role authenticated;
select (public.product_export(null, null, null, null, 'single', true, false, array['sku'])->>'total') as m_prod_total,
       (select total from public.product_list(null, null, null, null, 'single', true, false, 1, 0) limit 1) as m_list_total,
       (public.product_export(p_columns => array['sku'])->>'row_count') as m_prod_all,
       (public.customer_export(p_columns => array['name'])->>'total') as m_cust_total,
       (public.supplier_export(p_purchasable => 'unset', p_columns => array['name'])->>'total') as m_sup_unset,
       (public.supplier_export(p_purchasable => 'unset', p_columns => array['name'])->>'forced_filter') as m_sup_forced \gset
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'u_p', 'role', 'authenticated')::text, true);
set local role authenticated;
select (public.supplier_export(p_only_active => false, p_purchasable => 'no', p_columns => array['name'])->>'total') as p_sup_total \gset
reset role;
select pg_temp.chk('C3a products default filter = product_list total', :'m_prod_total', :'m_list_total');
select pg_temp.chk('C3b products default filter = active singles', :'m_prod_total', :'want_prod_default');
select pg_temp.chk('C3c products no filter = every product', :'m_prod_all', :'n_prod');
select pg_temp.chk('C3d customers default (active only)', :'m_cust_total', :'want_cust_active');
select pg_temp.chk('C3e supplier writer: purchasable not set, active', :'m_sup_unset', :'want_sup_unset');
select pg_temp.chk('C3f supplier writer: filter not forced', :'m_sup_forced', 'false');
select pg_temp.chk('C3g supplier purchasing reader: asked for no/all, got the forced list', :'p_sup_total', :'want_sup_reader');

-- ── C4 한 줄 꼴(762) ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_a', 'role', 'authenticated')::text, true);
set local role authenticated;
select (select r->>1 from jsonb_array_elements(public.product_export(p_q => :'sku_bc2', p_columns => array['sku', 'barcodes'])->'rows') r where r->>0 = :'sku_bc2') as f_bc,
       (select r->>1 from jsonb_array_elements(public.product_export(p_q => :'sku_sup2', p_columns => array['sku', 'default_supplier', 'all_suppliers'])->'rows') r where r->>0 = :'sku_sup2') as f_def,
       (select r->>2 from jsonb_array_elements(public.product_export(p_q => :'sku_sup2', p_columns => array['sku', 'default_supplier', 'all_suppliers'])->'rows') r where r->>0 = :'sku_sup2') as f_all,
       (select (r->1)::text from jsonb_array_elements(public.product_export(p_q => :'sku_nodef', p_columns => array['sku', 'default_supplier'])->'rows') r where r->>0 = :'sku_nodef') as f_nodef,
       (select r->>1 from jsonb_array_elements(public.customer_export(p_q => :'cust_multi', p_only_active => false, p_columns => array['name', 'billing_line1'])->'rows') r where r->>0 = :'cust_multi') as f_bill,
       (select jsonb_array_length(public.product_export(p_q => :'sku_bc2', p_columns => array['barcodes', 'sku', 'price_1'])->'columns')) as f_ncol,
       (select public.product_export(p_q => :'sku_bc2', p_columns => array['barcodes', 'sku'])->'columns'->0->>'key') as f_first \gset
reset role;
select pg_temp.chk('C4a barcodes joined with ; primary first', (:'f_bc' like (:'bc_first' || '; %'))::text, 'true');
select pg_temp.chk('C4b default supplier = the default line', :'f_def', :'sup_default');
select pg_temp.chk('C4c all suppliers joined with ;', (:'f_all' like '%; %')::text, 'true');
select pg_temp.chk('C4d no default supplier = null', :'f_nodef', 'null');
select pg_temp.chk('C4e customer billing = default billing line', :'f_bill', :'cust_bill1');
select pg_temp.chk('C4f columns = picked count', :'f_ncol', '3');
select pg_temp.chk('C4g columns keep the picked order', :'f_first', 'barcodes');

-- ── C5 최악 크기(REST 조건 · 8 초) — admin · 제품 전부 · 고를 수 있는 칸 전부 ──
select set_config('request.jwt.claims', json_build_object('sub', :'u_a', 'role', 'authenticated')::text, true);
set local role authenticated;
set local statement_timeout = '8s';
select array_agg(c->>'key' order by ord) as all_keys_txt from jsonb_array_elements(public.export_columns('product')->'columns') with ordinality x(c, ord) \gset
select clock_timestamp() as t5a \gset
select (x->>'row_count') as w_rows, length(x::text) as w_bytes from (select public.product_export(p_columns => :'all_keys_txt'::text[]) x) s \gset
select clock_timestamp() as t5b \gset
select (x->>'row_count') as wc_rows, length(x::text) as wc_bytes from (select public.customer_export(p_only_active => false, p_columns => (select array_agg(c->>'key') from jsonb_array_elements(public.export_columns('customer')->'columns') c)) x) s \gset
select clock_timestamp() as t5c \gset
reset role;
select pg_temp.chk('C5a worst product export: every row', :'w_rows', :'n_prod');
select pg_temp.chk('C5b worst customer export: every row', :'wc_rows', :'n_cust');
\echo '── 크기 · 시간(8 초 안이어야 · 문장이 섰다면 위에서 멈췄다)'
select :'w_rows' as product_rows, :'w_bytes' as product_bytes, (:'t5b'::timestamptz - :'t5a'::timestamptz) as product_time,
       :'wc_rows' as customer_rows, :'wc_bytes' as customer_bytes, (:'t5c'::timestamptz - :'t5b'::timestamptz) as customer_time;

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤)'
select (select count(*) from public.product) = :n_prod as prod_same, (select count(*) from public.customer) = :n_cust as cust_same,
       (select count(*) from public.supplier) = :n_sup as sup_same, (select count(*) from public.product_supplier) = :n_ps as ps_same,
       (select count(*) from public.customer_address) = :n_ca as ca_same, (select count(*) from public.ims_staff) = :n_staff as staff_same;
