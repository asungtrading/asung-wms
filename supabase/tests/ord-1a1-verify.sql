-- ord-1a1-verify.sql — Shopify ④ 오더 받기 DB 첫 차수: 시스템 직원 · shop_customer · shop_order · shop_order_line · ingest · prepare · pick_location · resolve_customer · 뷰 (Asung-IMS · 테스트)
--   기대: 시험 갈래(-v mig) OK 18 · 확인 갈래 OK 16(= 18 − 시험 전용 2: G0a · T1c) · MISMATCH 0 · 확인 갈래 전용 줄(\else)은 없다
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261010233000_ord_1a1_shop_order.sql -f supabase/tests/ord-1a1-verify.sql > /tmp/ord-1a1.out 2>&1; echo exit=$?
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료: 오더 원문은 pg_temp.ord() 가 손으로 만든 jsonb(ord-0-shopify.graphql ① 모양) · 실제 손님(이메일 하나 72cf6eba Debi Blair · 이메일 겹침 accounting@herabeauty.ca 18 명)은 읽기만 · 새 손님 · 가짜 스토어(aone 꼴) · 가짜 직원 둘은 rollback
--   ⚠️ 실제 행을 바꾸는 갈래 없음(새 표 · 새 손님 · 가짜 행만 · 전부 rollback) · 시퀀스 없음(uuid 만)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
begin;
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
select string_agg(proname || ':' || md5(prosrc), ',' order by proname) as h0_untouched from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_create', 'so_line_add', 'so_charge_set', 'so_payment_add', 'so_confirm', 'so_cancel', 'customer_create', 'customer_update', 'so_copy_customer', 'so_tax_refresh', 'ims_can_write', 'ims_touch') \gset
select count(*)::text as staff_head from public.ims_staff \gset
\i :mig
\endif
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql security definer as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql security definer as $$
begin execute p_sql; return 'no-error'; exception when others then return sqlstate || ' ' || sqlerrm; end $$;
create function pg_temp.err_inv(p_sql text) returns text language plpgsql as $$                                                        -- invoker: 권한(42501) 시험은 definer 도우미로는 못 본다(1회차 T3b)
begin execute p_sql; return 'no-error'; exception when others then return sqlstate || ' ' || sqlerrm; end $$;
-- 오더 원문 만들기 — ① 모양 · p_lines = [{sku, qty, price, disc}] · p_extra 로 덮기
create function pg_temp.ord(p_gid text, p_name text, p_email text, p_cust_gid text, p_prov text, p_lines jsonb, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select (jsonb_build_object('id', p_gid, 'name', p_name, 'createdAt', '2026-10-10T20:00:00Z', 'updatedAt', '2026-10-10T20:00:00Z', 'cancelledAt', null, 'test', true,
            'displayFinancialStatus', 'PENDING', 'sourceName', '2627105', 'email', p_email, 'phone', null,
            'customer', case when p_cust_gid is null then null else jsonb_build_object('id', p_cust_gid, 'firstName', 'Test', 'lastName', 'Buyer', 'displayName', 'Test Buyer', 'defaultEmailAddress', jsonb_build_object('emailAddress', p_email)) end,
            'shippingAddress', case when p_prov is null then null else jsonb_build_object('name', 'Test Buyer', 'company', null, 'address1', '1 Test St', 'city', 'Somewhere', 'provinceCode', p_prov, 'zip', 'A1A 1A1', 'countryCodeV2', 'CA', 'phone', '555-0100') end,
            'billingAddress', jsonb_build_object('name', 'Test Buyer', 'address1', '1 Test St', 'city', 'Somewhere', 'provinceCode', coalesce(p_prov, 'ON'), 'zip', 'A1A 1A1', 'countryCodeV2', 'CA'),
            'currencyCode', 'CAD', 'subtotalPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', '30.00')), 'totalDiscountsSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', '2.00')),
            'totalShippingPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', '9.99')), 'totalTaxSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', '1.40')), 'totalPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', '39.39')),
            'shippingLines', jsonb_build_object('nodes', jsonb_build_array(jsonb_build_object('title', 'Standard', 'originalPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', '9.99')), 'discountedPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', '9.99'))))),
            'lineItems', jsonb_build_object('nodes', (select coalesce(jsonb_agg(jsonb_build_object('id', 'gid://shopify/LineItem/' || t.n, 'sku', l->>'sku', 'name', 'Item ' || (l->>'sku'), 'quantity', (l->>'qty')::numeric,
                              'originalUnitPriceSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', l->>'price')), 'discountedUnitPriceAfterAllDiscountsSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', ((l->>'price')::numeric - coalesce((l->>'disc')::numeric, 0))::text)),
                              'totalDiscountSet', jsonb_build_object('shopMoney', jsonb_build_object('amount', to_char(coalesce((l->>'disc')::numeric, 0) * (l->>'qty')::numeric, 'FM999999990.00'))))), '[]'::jsonb) from jsonb_array_elements(p_lines) with ordinality as t(l, n))))
         ) || p_extra;
$$;
create function pg_temp.reasons(p_id uuid) returns text language sql security definer as $$
  select coalesce(string_agg(r->>'code', ',' order by r->>'code'), '') from public.shop_order o, jsonb_array_elements(o.reasons) r where o.id = p_id;
$$;
create function pg_temp.warns(p_id uuid) returns text language sql security definer as $$
  select coalesce(string_agg(r->>'code', ',' order by r->>'code'), '') from public.shop_order o, jsonb_array_elements(o.warnings) r where o.id = p_id;
$$;
\if :{?mig}
select pg_temp.chk('G0a trial marker: shop_order exists only after the trial apply', (to_regclass('public.shop_order') is not null)::text, 'true');
\endif

-- ═══ 재료 ═══
select id::text as store from public.shop_store where code = 'test' \gset
select id::text as wh_to from public.ref_warehouse where name = 'Asung Trading Inc.' \gset
select id::text as wh_ed from public.ref_warehouse where name = 'Asung - Edmonton' \gset
select s.id::text as sys_id, s.auth_user_id::text as sys_auth from public.ims_staff s where s.is_system \gset
select c.customer_id::text as c_debi from public.customer_contact c where lower(trim(c.email)) = '03.novelty.plosive@icloud.com' and c.is_active limit 1 \gset
select c.id::text as c_edm from public.customer c where c.is_active and c.default_location_id = :'wh_ed'::uuid and exists (select 1 from public.customer_contact x where x.customer_id = c.id and x.is_active and nullif(trim(x.email), '') is not null) order by c.created_at limit 1 \gset
select count(distinct customer_id)::text as hera_n from public.customer_contact where is_active and lower(trim(email)) = 'accounting@herabeauty.ca' \gset
select id::text as any_so from public.so order by created_at limit 1 \gset
select count(*)::text as cust_head from public.customer \gset

-- ═══ T1 — 객체 · 권한 · 시스템 직원 ═══
select pg_temp.chk('T1a tables 3 (rls on · select policy) · functions 6 (definer: enter · leave · ingest · prepare · resolve) · pick_location invoker · view · ims_staff.is_system column',
  (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname in ('shop_customer', 'shop_order', 'shop_order_line') and c.relrowsecurity) || '/' ||
  (select count(*)::text from pg_policies where schemaname = 'public' and tablename in ('shop_customer', 'shop_order', 'shop_order_line') and cmd = 'SELECT') || '/' ||
  (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_system_enter', 'shop_system_leave', 'shop_order_pick_location', 'shop_order_ingest', 'shop_order_prepare', 'shop_order_resolve_customer')) || '/' ||
  (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_system_enter', 'shop_system_leave', 'shop_order_ingest', 'shop_order_prepare', 'shop_order_resolve_customer') and prosecdef) || '/' ||
  (select prosecdef::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_pick_location') || '/' ||
  (to_regclass('public.shop_order_list') is not null)::text || '/' || (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'ims_staff' and column_name = 'is_system'),
  '3/3/6/5/false/true/1');
select pg_temp.chk('T1b privileges: authenticated select on 3 tables + view · no insert · execute only on resolve_customer · nothing on ingest · prepare · enter · leave · pick_location · anon nothing',
  (has_table_privilege('authenticated', 'public.shop_customer', 'select') and has_table_privilege('authenticated', 'public.shop_order', 'select') and has_table_privilege('authenticated', 'public.shop_order_line', 'select') and has_table_privilege('authenticated', 'public.shop_order_list', 'select'))::text || '/' ||
  (has_table_privilege('authenticated', 'public.shop_order', 'insert') or has_table_privilege('authenticated', 'public.shop_customer', 'insert') or has_table_privilege('authenticated', 'public.shop_order_line', 'delete'))::text || '/' ||
  has_function_privilege('authenticated', 'public.shop_order_resolve_customer(uuid, uuid, boolean)', 'execute')::text || '/' ||
  (has_function_privilege('authenticated', 'public.shop_order_ingest(uuid, jsonb)', 'execute') or has_function_privilege('authenticated', 'public.shop_order_prepare(uuid)', 'execute') or has_function_privilege('authenticated', 'public.shop_system_enter()', 'execute') or has_function_privilege('authenticated', 'public.shop_system_leave(jsonb)', 'execute') or has_function_privilege('authenticated', 'public.shop_order_pick_location(uuid, text, uuid)', 'execute'))::text || '/' ||
  (has_table_privilege('anon', 'public.shop_order', 'select') or has_table_privilege('anon', 'public.shop_order_list', 'select'))::text,
  'true/false/true/false/false');
\if :{?mig}
select pg_temp.chk('T1c (trial) twelve existing functions byte-identical (so_* · customer_* · ims_can_write · ims_touch) · staff rows +1 (the system staff)',
  (:'h0_untouched' = (select string_agg(proname || ':' || md5(prosrc), ',' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_create', 'so_line_add', 'so_charge_set', 'so_payment_add', 'so_confirm', 'so_cancel', 'customer_create', 'customer_update', 'so_copy_customer', 'so_tax_refresh', 'ims_can_write', 'ims_touch')))::text || '/' ||
  ((select count(*) from public.ims_staff) - :staff_head::int)::text, 'true/1');
\endif
select pg_temp.chk('T1d system staff: one row · fixed ids · manager · perms sales + master · is_system · active · no auth.users row behind it',
  (select count(*)::text from public.ims_staff where is_system) || '/' || :'sys_id' || '/' || :'sys_auth' || '/' ||
  (select role || '/' || (perms ? 'sales')::text || (perms ? 'master')::text || '/' || is_active::text from public.ims_staff where is_system) || '/' ||
  (select count(*)::text from auth.users u where u.id = :'sys_auth'::uuid),
  '1/00000000-0000-4000-a000-000000000001/00000000-0000-4000-a000-000000000002/manager/truetrue/true/0');

-- ═══ T2 — 깨끗한 asung 오더(이메일 하나 · AB · 줄 둘) → received · Edmonton · 잇기 email · 두 번째(같은 GID) → updated · 한 줄 · 세 번째(같은 손님 GID · 새 오더) → account ═══
select coalesce(current_setting('request.jwt.claims', true), '') as claims0 \gset
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000001', 'AS-T0001', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10850","qty":2,"price":"10.00","disc":"1.00"},{"sku":"AAL10925","qty":1,"price":"10.00"}]'::jsonb)) as t2_a \gset
select (:'t2_a'::jsonb->>'shop_order_id')::uuid as o1 \gset
select pg_temp.chk('T2a clean order → inserted · received · customer = Debi (email) · Edmonton (AB · 430) · 2 lines · lines matched ok with list/discount/unit kept · freight 9.99 Standard stored only · claims restored after the system call',
  (:'t2_a'::jsonb->>'action') || '/' || (:'t2_a'::jsonb->>'status') || '/' || ((:'t2_a'::jsonb->>'customer_id') = :'c_debi')::text || '/' || ((:'t2_a'::jsonb->>'location_id') = :'wh_ed')::text || '/' || (:'t2_a'::jsonb->>'lines') || '/' ||
  (select string_agg(l.sku || ':' || l.match || ':' || l.quantity || ':' || l.list_price || ':' || l.discount_amount || ':' || l.unit_price, ',' order by l.line_no) from public.shop_order_line l where l.shop_order_id = :'o1'::uuid) || '/' ||
  (select freight_amount::text || ':' || freight_title from public.shop_order where id = :'o1'::uuid) || '/' || (coalesce(current_setting('request.jwt.claims', true), '') = :'claims0')::text,
  'inserted/received/true/true/2/AAL10850:ok:2:10.00:2.00:9.00,AAL10925:ok:1:10.00:0.00:10.00/9.99:Standard/true');
select pg_temp.chk('T2b shop_customer linked (store × customer GID → Debi · linked_how email · linked_by system) · view row: store test · customer name · location Edmonton · line_count 2 · unmatched 0',
  (select linked_how || '/' || (customer_id = :'c_debi'::uuid)::text || '/' || (linked_by = :'sys_id'::uuid)::text from public.shop_customer where store_id = :'store'::uuid and shopify_customer_gid = 'gid://shopify/Customer/700000000001') || '/' ||
  (select store_code || '/' || (customer_name is not null)::text || '/' || location_name || '/' || line_count || '/' || unmatched_count || '/' || reason_count from public.shop_order_list where id = :'o1'::uuid),
  'email/true/true/test/true/Asung - Edmonton/2/0/0');
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000001', 'AS-T0001', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10850","qty":3,"price":"10.00"}]'::jsonb, '{"updatedAt":"2026-10-10T20:05:00Z"}'::jsonb)) as t2_c \gset
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000002', 'AS-T0002', 'other@test.invalid', 'gid://shopify/Customer/700000000001', 'ON',
  '[{"sku":"AAL10850","qty":1,"price":"10.00"}]'::jsonb)) as t2_d \gset
select pg_temp.chk('T2c same GID again → updated · still one shop_order row · lines re-exploded (1 line · qty 3) · new order with the same customer GID but another email → linked by account (Debi) · Toronto (ON)',
  (:'t2_c'::jsonb->>'action') || '/' || (select count(*)::text from public.shop_order where shopify_order_gid = 'gid://shopify/Order/900000000001') || '/' ||
  (select count(*)::text || ':' || string_agg(quantity::text, ',') from public.shop_order_line where shop_order_id = :'o1'::uuid) || '/' ||
  (:'t2_d'::jsonb->'prepare'->>'linked_how') || '/' || ((:'t2_d'::jsonb->>'customer_id') = :'c_debi')::text || '/' || ((:'t2_d'::jsonb->>'location_id') = :'wh_to')::text,
  'updated/1/1:3/account/true/true');

-- ═══ T3 — 이메일 겹침 → needs_review(후보) → 직원 resolve → received · staff 잇기 ═══
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000003', 'AS-T0003', 'accounting@herabeauty.ca', 'gid://shopify/Customer/700000000003', 'QC',
  '[{"sku":"AAL10850","qty":1,"price":"10.00"}]'::jsonb)) as t3_a \gset
select (:'t3_a'::jsonb->>'shop_order_id')::uuid as o3 \gset
select (r->>'count') || '/' || jsonb_array_length(r->'candidates') as t3_cands from public.shop_order o, jsonb_array_elements(o.reasons) r where o.id = :'o3'::uuid and r->>'code' = 'email_multiple' \gset
select (r->'candidates'->0->>'customer_id')::uuid as c_pick from public.shop_order o, jsonb_array_elements(o.reasons) r where o.id = :'o3'::uuid and r->>'code' = 'email_multiple' \gset
select pg_temp.chk('T3a shared email (herabeauty · 18 customers) → needs_review · reason email_multiple with count = customers sharing it and candidates · no customer · no shop_customer row · location Toronto (QC)',
  (:'t3_a'::jsonb->>'status') || '/' || pg_temp.reasons(:'o3'::uuid) || '/' || :'t3_cands' || '/' || (:'t3_a'::jsonb->>'customer_id' is null)::text || '/' ||
  (select count(*)::text from public.shop_customer where shopify_customer_gid = 'gid://shopify/Customer/700000000003') || '/' || ((:'t3_a'::jsonb->>'location_id') = :'wh_to')::text,
  'needs_review/email_multiple/' || :'hera_n' || '/' || :'hera_n' || '/true/0/true');
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'ord1a1-sales@test.invalid', 'ORD1A1 Sales', 'manager', '["sales"]'::jsonb) returning auth_user_id::text as s_uid, id::text as s_sid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'ord1a1-none@test.invalid', 'ORD1A1 None', 'worker', '[]'::jsonb) returning auth_user_id::text as n_uid \gset
\set s_claims '{"sub":"' :s_uid '","role":"authenticated"}'
\set n_claims '{"sub":"' :n_uid '","role":"authenticated"}'
savepoint t3;
set local role authenticated;
select set_config('request.jwt.claims', :'n_claims', true);
select pg_temp.err(format('select public.shop_order_resolve_customer(%L, %L, true)', :'o3', :'c_pick')) as t3_none \gset
select pg_temp.err_inv(format('select public.shop_order_ingest(%L, %L::jsonb)', :'store', '{}')) as t3_ingest_auth \gset
select pg_temp.err_inv('select public.shop_system_enter()') as t3_enter_auth \gset
select set_config('request.jwt.claims', :'s_claims', true);
select public.shop_order_resolve_customer(:'o3'::uuid, :'c_pick'::uuid, false)::text as t3_pre \gset
select status as t3_pre_status from public.shop_order where id = :'o3'::uuid \gset
select public.shop_order_resolve_customer(:'o3'::uuid, :'c_pick'::uuid, true)::text as t3_go \gset
select count(*)::text as t3_rows_seen from public.shop_order_list where id = :'o3'::uuid \gset
reset role;
select pg_temp.chk('T3b gates: worker without sales → P0001 · authenticated cannot execute ingest (42501) nor shop_system_enter (42501) · preview (commit false) changes nothing · authenticated reads the view',
  left(:'t3_none', 5) || '/' || left(:'t3_ingest_auth', 5) || '/' || left(:'t3_enter_auth', 5) || '/' || (:'t3_pre'::jsonb->>'committed') || '/' || :'t3_pre_status' || '/' || :'t3_rows_seen',
  'P0001/42501/42501/false/needs_review/1');
select pg_temp.chk('T3c resolve by sales staff → committed · received · customer = picked · shop_customer linked_how staff · linked_by that staff · reasons empty',
  (:'t3_go'::jsonb->>'committed') || '/' || (select status || '/' || (customer_id = :'c_pick'::uuid)::text from public.shop_order where id = :'o3'::uuid) || '/' ||
  (select linked_how || '/' || (linked_by = :'s_sid'::uuid)::text from public.shop_customer where store_id = :'store'::uuid and shopify_customer_gid = 'gid://shopify/Customer/700000000003') || '/' || pg_temp.reasons(:'o3'::uuid),
  'true/received/true/staff/true/');
release savepoint t3;

-- ═══ T4 — 새 손님(이메일 없는 손님 · 계정 있음) → customer_create 그대로(시스템 직원 · 스토어 티어 Wholesale · 주소 둘 · 연락처) · 잇기 created ═══
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000004', 'AS-T0004', 'ord1a1-new@test.invalid', 'gid://shopify/Customer/700000000004', 'ON',
  '[{"sku":"AAL10850","qty":1,"price":"10.00"}]'::jsonb, '{"shippingAddress":{"name":"New Person","company":"ORD1A1 New Shop","address1":"9 New Rd","city":"Toronto","provinceCode":"ON","zip":"M1M 1M1","countryCodeV2":"CA","phone":"555-0199"}}'::jsonb)) as t4_a \gset
select (:'t4_a'::jsonb->>'customer_id')::uuid as c_new \gset
select pg_temp.chk('T4a unknown email → new customer created: received · linked_how created · name = ship company · tier Wholesale (store) · default warehouse Toronto · source manual · created_by + reviewed_by = system staff · currency CAD · 2 addresses (Shipping default · Billing default) · 1 contact with email · shop_customer created',
  (:'t4_a'::jsonb->>'status') || '/' || (:'t4_a'::jsonb->'prepare'->>'linked_how') || '/' ||
  (select c.name || '/' || c.price_tier || '/' || c.default_location_name || '/' || c.source || '/' || (c.created_by = :'sys_id'::uuid)::text || (c.reviewed_by = :'sys_id'::uuid)::text || '/' || c.currency_code from public.customer c where c.id = :'c_new'::uuid) || '/' ||
  (select string_agg(a.type || ':' || a.is_default_for_type::text || ':' || a.state_province, ',' order by a.type) from public.customer_address a where a.customer_id = :'c_new'::uuid) || '/' ||
  (select count(*)::text || ':' || max(email) || ':' || max(is_default::text) from public.customer_contact x where x.customer_id = :'c_new'::uuid) || '/' ||
  (select linked_how from public.shop_customer where shopify_customer_gid = 'gid://shopify/Customer/700000000004'),
  'received/created/ORD1A1 New Shop/Wholesale/Asung Trading Inc./manual/truetrue/CAD/Billing:true:ON,Shipping:true:ON/1:ord1a1-new@test.invalid:true/created');
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000005', 'AS-T0005', 'ord1a1-new@test.invalid', null, 'ON', '[{"sku":"AAL10850","qty":1,"price":"10.00"}]'::jsonb)) as t4_b \gset
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000006', 'AS-T0006', null, null, null, '[{"sku":"AAL10850","qty":1,"price":"10.00"}]'::jsonb, '{"shippingAddress":null,"billingAddress":null,"customer":null}'::jsonb)) as t4_c \gset
select pg_temp.chk('T4b guest order with that email → found by email (the customer just created) · no GID → no shop_customer row · no email · no name · no customer → needs_review customer_unknown · location falls back to Toronto · customers +1 only',
  (:'t4_b'::jsonb->'prepare'->>'linked_how') || '/' || ((:'t4_b'::jsonb->>'customer_id') = :'c_new'::text)::text || '/' || (select count(*)::text from public.shop_customer where customer_id = :'c_new'::uuid) || '/' ||
  (:'t4_c'::jsonb->>'status') || '/' || pg_temp.reasons((:'t4_c'::jsonb->>'shop_order_id')::uuid) || '/' || ((:'t4_c'::jsonb->>'location_id') = :'wh_to')::text || '/' || ((select count(*) from public.customer) - :cust_head::int)::text,
  'email/true/1/needs_review/customer_unknown/true/1');

-- ═══ T5 — 줄 대조(366): 모르는 SKU · 꺼진 상품 · 판매 안 함 · 수량 0 줄 ═══
select id::text as p_inactive_sku from (select sku as id from public.product where not is_active order by sku limit 1) z \gset
select id::text as p_unsell_sku from (select sku as id from public.product where is_active and not sellable and parent_product_id is null order by sku limit 1) z \gset
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000007', 'AS-T0007', '03.novelty.plosive@icloud.com', null, 'ON',
  ('[{"sku":"NOPE-0000","qty":1,"price":"1.00"},{"sku":"' || :'p_inactive_sku' || '","qty":1,"price":"1.00"},{"sku":"' || :'p_unsell_sku' || '","qty":1,"price":"1.00"},{"sku":"AAL10850","qty":0,"price":"1.00"},{"sku":"AAL10925","qty":2,"price":"1.00"}]')::jsonb)) as t5_a \gset
select (:'t5_a'::jsonb->>'shop_order_id')::uuid as o7 \gset
select pg_temp.chk('T5a unknown · inactive · not-sellable SKUs → needs_review with one reason each · qty 0 line dropped · good line ok · view unmatched_count 3 of 4',
  (:'t5_a'::jsonb->>'status') || '/' || pg_temp.reasons(:'o7'::uuid) || '/' || (select string_agg(coalesce(l.match, '-'), ',' order by l.line_no) from public.shop_order_line l where l.shop_order_id = :'o7'::uuid) || '/' ||
  (select line_count || '/' || unmatched_count from public.shop_order_list where id = :'o7'::uuid),
  'needs_review/product_inactive,product_not_sellable,sku_not_found/not_found,inactive,not_sellable,ok/4/3');

-- ═══ T6 — 브랜치 한 곳(430 · 427) ═══
insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, oos_policy) values ('ord1a1_aone', 'ord1a1-aone.myshopify.com', 'Fake aone', 'aone', (select id from public.ref_price_tier where name = 'AONE'), 'deny') returning id::text as aone \gset
insert into public.shop_location (store_id, shopify_location_gid, warehouse_id) values (:'aone'::uuid, 'gid://shopify/Location/990000000001', :'wh_to'::uuid);
select pg_temp.chk('T6a test store (two pairs): BC → Edmonton · SK → Edmonton · ON → Toronto · no province + customer default Edmonton → Edmonton · no province + Debi (Toronto) → Toronto · no province + no customer → Toronto',
  (public.shop_order_pick_location(:'store'::uuid, 'BC', null) = :'wh_ed'::uuid)::text || (public.shop_order_pick_location(:'store'::uuid, 'sk', null) = :'wh_ed'::uuid)::text || (public.shop_order_pick_location(:'store'::uuid, 'ON', null) = :'wh_to'::uuid)::text || '/' ||
  (public.shop_order_pick_location(:'store'::uuid, null, :'c_edm'::uuid) = :'wh_ed'::uuid)::text || (public.shop_order_pick_location(:'store'::uuid, null, :'c_debi'::uuid) = :'wh_to'::uuid)::text || (public.shop_order_pick_location(:'store'::uuid, null, null) = :'wh_to'::uuid)::text,
  'truetruetrue/truetruetrue');
select pg_temp.chk('T6b aone-shaped store (one pair · Toronto): AB → Toronto · null → Toronto (427) · store with no pair → null',
  (public.shop_order_pick_location(:'aone'::uuid, 'AB', null) = :'wh_to'::uuid)::text || (public.shop_order_pick_location(:'aone'::uuid, null, :'c_edm'::uuid) = :'wh_to'::uuid)::text || '/' ||
  (public.shop_order_pick_location(gen_random_uuid(), 'AB', null) is null)::text, 'truetrue/true');

-- ═══ T7 — 이미 created 인 오더가 Shopify 에서 바뀜 · 취소됨 → 원문만 · SO · 줄 무접촉 · 경고(판정 372) ═══
update public.shop_order set status = 'created', so_id = :'any_so'::uuid where id = :'o1'::uuid;                                            -- 1a2 의 process 를 흉내(실제 so 행 하나를 가리키기만 · 읽기)
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000001', 'AS-T0001', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10850","qty":9,"price":"10.00"}]'::jsonb, '{"updatedAt":"2026-10-10T21:00:00Z"}'::jsonb)) as t7_a \gset
select public.shop_order_ingest(:'store'::uuid, pg_temp.ord('gid://shopify/Order/900000000001', 'AS-T0001', '03.novelty.plosive@icloud.com', 'gid://shopify/Customer/700000000001', 'AB',
  '[{"sku":"AAL10850","qty":9,"price":"10.00"}]'::jsonb, '{"updatedAt":"2026-10-10T21:30:00Z","cancelledAt":"2026-10-10T21:30:00Z"}'::jsonb)) as t7_b \gset
select pg_temp.chk('T7a created order changed in Shopify → action updated_after_created · status still created · so_id kept · lines untouched (qty 3 not 9) · raw updated · warning updated_after_so · then cancelled → + cancelled_in_shopify · shopify_cancelled_at set · prepare skipped',
  (:'t7_a'::jsonb->>'action') || '/' || (select status || '/' || (so_id = :'any_so'::uuid)::text || '/' || (select string_agg(quantity::text, ',') from public.shop_order_line l where l.shop_order_id = o.id) || '/' || (o.raw->>'updatedAt') || '/' || (o.shopify_cancelled_at is not null)::text from public.shop_order o where o.id = :'o1'::uuid) || '/' ||
  pg_temp.warns(:'o1'::uuid) || '/' || (:'t7_b'::jsonb->'prepare' is null or :'t7_b'::jsonb->'prepare' = 'null'::jsonb)::text,
  'updated_after_created/created/true/3/2026-10-10T21:30:00Z/true/cancelled_in_shopify,updated_after_so,updated_after_so/true');

-- ═══ T8 — 모양 검사 · 한 번 더 prepare 해도 같음 ═══
select pg_temp.chk('T8a shape errors: not an Order GID → P0001 · no lineItems.nodes → P0001 · unknown store → P0001 · prepare again on a received order → same status · same reasons (idempotent)',
  left(pg_temp.err(format('select public.shop_order_ingest(%L, %L::jsonb)', :'store', '{"id":"gid://shopify/Product/1","name":"x","lineItems":{"nodes":[]}}')), 5) || '/' ||
  left(pg_temp.err(format('select public.shop_order_ingest(%L, %L::jsonb)', :'store', '{"id":"gid://shopify/Order/1","name":"x"}')), 5) || '/' ||
  left(pg_temp.err(format('select public.shop_order_ingest(%L, %L::jsonb)', gen_random_uuid()::text, '{"id":"gid://shopify/Order/1","name":"x","lineItems":{"nodes":[]}}')), 5) || '/' ||
  (public.shop_order_prepare((:'t2_d'::jsonb->>'shop_order_id')::uuid)->>'status') || '/' || (public.shop_order_prepare(:'o7'::uuid)->>'status') || '/' || pg_temp.reasons(:'o7'::uuid),
  'P0001/P0001/P0001/received/needs_review/product_inactive,product_not_sellable,sku_not_found');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select 'after rollback: shop_order table ' || (to_regclass('public.shop_order') is not null)::text || ' (trial run → false · applied DB → true) · fake staff ' || (select count(*) from public.ims_staff where email like 'ord1a1-%') || ' · fake store ' || (select count(*) from public.shop_store where code = 'ord1a1_aone') || ' · customers ' || (select count(*) from public.customer);
