-- supabase/tests/fc_1a_check.sql — fc-1a Freightcom 견적 DB 바탕 검증 (2026-10-28 · 판정 835 ~ 843)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4 · 잠금 규칙 ①~⑥) — 기준(begin 앞 · 잠금 없음: 실제 행 수 · 함수 md5)
--   → begin → 가짜 재료 FCX-(직원 셋 · 창고 · 손님 둘 · 주소 · 연락처 · 운송사 셋) → (-v mig 면 옛 customer_update 호출 담기 → \i) → 재료 둘째(새 칸 · SO 열 · 유닛 · 웹 스토어) → 갈래 1 ~ 12 → rollback → 실제 행 무변 · md5 복귀
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028162209_fc_1a_freightcom_quote_db.sql -f supabase/tests/fc_1a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 77 · 확인(적용 뒤 · -v mig 없음) 76 — M1(옛 = 새 customer_update 모양)은 시험 갈래만 · Z1(실제 행 무변)은 둘 다 · Z2(rollback 복귀)는 시험 갈래만 · 둘은 t_res 밖 한 줄씩
--   쓰기 0 — 가짜 재료는 rollback · 번호 시퀀스를 당기는 창구는 부르지 않는다(so_number 는 글자 그대로 SO-79900a ~ k)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 77
\else
\set EXPECT_OK 76
\endif
\pset pager off
select (select count(*) from public.so) as n_so0, (select count(*) from public.customer) as n_cust0, (select count(*) from public.customer_address) as n_addr0,
       (select count(*) from public.wms_pallets) as n_unit0, (select count(*) from public.ref_carrier) as n_car0, (select count(*) from public.ref_warehouse) as n_wh0,
       (select count(*) from public.inv_config) as n_cfg0, (select count(*) from public.ims_staff) as n_staff0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'customer_update') as cu_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_config_set') as cfg_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize') as fin_md5_0 \gset
\echo '── 기준: so' :n_so0 '· customer' :n_cust0 '· address' :n_addr0 '· units' :n_unit0 '· carriers' :n_car0 '· warehouses' :n_wh0 '· config' :n_cfg0 '· customer_update md5' :cu_md5_0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset

-- ── 재료 ① (옛 칸만 · replica · 가짜 FCX-) ──
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as tier from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
set local session_replication_role = replica;
insert into public.ref_warehouse (name, source, is_active, address_line1, city, state_province, postal_code, country, freightcom_account) values ('FCX Warehouse', 'manual', true, '35 Suntract Road', 'North York', 'ON', 'M9N 2V8', 'Canada', 'FCX') returning id::text as wh \gset
insert into public.ref_warehouse (name, source, is_active, address_line1, city, state_province, postal_code, country, freightcom_account) values ('FCX Warehouse 2', 'manual', true, '18418 105 Ave NW', 'Edmonton', 'AB', 'T5S 0N7', 'Canada', 'FCX2') returning id::text as wh2 \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-wms@test.invalid', 'FCX Worker', 'worker', '["wms","fulfillment"]', array[:'wh'::uuid]) returning auth_user_id::text as u_wms \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-office@test.invalid', 'FCX Office', 'manager', '["ims","sales","master"]', '{}') returning auth_user_id::text as u_off \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-none@test.invalid', 'FCX Nobody', 'worker', '["wms","picking"]', '{}') returning auth_user_id::text as u_none \gset
insert into public.ref_carrier (name, kind, is_active) values ('FCX Alpha Carrier', 'carrier', true) returning id::text as car_a \gset
insert into public.ref_carrier (name, kind, is_active) values ('FCX Beta Carrier', 'carrier', true) returning id::text as car_b \gset
insert into public.ref_carrier (name, kind, is_active) values ('FCX Gamma Carrier', 'carrier', true) returning id::text as car_g \gset
insert into public.customer (name, source, currency_id, price_tier, default_carrier_id) values ('FCX Alpha Corp', 'manual', :'cad'::uuid, 'Wholesale', :'car_b'::uuid) returning id::text as c_a \gset
insert into public.customer (name, source, currency_id, price_tier) values ('FCX Person', 'manual', :'cad'::uuid, 'AONE') returning id::text as c_p \gset
insert into public.customer_address (customer_id, source, type, is_default_for_type, line1, city, state_province, postal_code, country) values (:'c_a'::uuid, 'manual', 'Shipping', true, '100 Fcx Street', 'Toronto', 'ON', 'M5V 1A1', 'Canada') returning id::text as addr_a \gset
insert into public.customer_address (customer_id, source, type, is_default_for_type, line1, city, state_province, postal_code, country) values (:'c_p'::uuid, 'manual', 'Shipping', true, '200 Fcx Lane', 'Toronto', 'ON', 'M4B 2C2', 'CA') returning id::text as addr_p \gset
insert into public.customer_contact (customer_id, source, name, phone, email, is_default, is_active) values (:'c_a'::uuid, 'manual', 'Alpha Buyer', '416-555-0101', 'alpha@test.invalid', true, true);
insert into public.customer_contact (customer_id, source, name, mobile_phone, email, is_default, is_active) values (:'c_p'::uuid, 'manual', 'FCX Person', '(647) 555-0202', 'person@test.invalid', true, true);
set local session_replication_role = origin;

\if :{?mig}
-- 옛 customer_update(address_set · 옛 열쇠만)의 모양을 담는다 — 적용 뒤 같은 호출과 견준다(M1)
select set_config('request.jwt.claims', json_build_object('sub', :'u_off', 'role', 'authenticated')::text, true) \gset
select (public.customer_update(jsonb_build_array(jsonb_build_object('op', 'address_set', 'customer_id', :'c_a', 'address_id', :'addr_a', 'values', jsonb_build_object('line2', 'Unit 9'), 'olds', jsonb_build_object('line2', null))), true, array[:'c_a' || ':open_so_keep_old']) - 'reviewed_now' - 'warnings')::text as cu_old_shape \gset
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql security definer as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 되돌리는 호출: 서브트랜잭션에서 돌리고 결과만 글자로(쓰기 0)
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  raise exception using errcode = 'P7777', message = coalesce(v, '(null)');
exception when sqlstate 'P7777' then return sqlerrm;
          when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
$$;
create function pg_temp.errhead(p text) returns text language sql as $$ select case when p like 'ERR %' then left(p, 56) else p end; $$;
-- 앞 문장(쓰기)을 돌린 뒤 본 문장 — 둘 다 서브트랜잭션에서 되돌린다
create function pg_temp.try2(p_pre text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_pre;
  execute p_sql into v;
  raise exception using errcode = 'P7777', message = coalesce(v, '(null)');
exception when sqlstate 'P7777' then return sqlerrm;
          when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;

-- ── 재료 ② (새 칸 · SO 열 · 유닛 · 웹 스토어 · replica) ──
set local session_replication_role = replica;
update public.ref_warehouse set phone = '(416) 792-2298', email = 'fcx@test.invalid', contact_name = 'FCX Contact' where id = :'wh'::uuid;
update public.ref_warehouse set phone = '7807527678' where id = :'wh2'::uuid;
insert into public.ref_carrier_fc_name (carrier_id, name) values (:'car_a'::uuid, 'Fcx Alpha'), (:'car_b'::uuid, 'Fcx Beta'), (:'car_g'::uuid, 'Fcx Gamma');   -- fc-1b3: 이름 표(옛 칸 freightcom_carrier 는 없어졌다)
create function pg_temp.mk_so(p_tag text, p_status text, p_cust uuid, p_company text, p_contact text, p_phone text, p_line1 text, p_postal text, p_country text, p_days int, p_wh uuid default null) returns uuid language plpgsql as $$
declare v_so uuid;
begin
  insert into public.so (so_number, customer_id, channel, intake, status, currency_id, location_id, location_name, confirmed_at, created_at,
                         ship_to_company, ship_to_contact, ship_to_phone, ship_to_line1, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country)
  values ('SO-79900' || chr(96 + p_tag::int), p_cust, 'warehouse', 'manual', p_status, current_setting('fcx.cad')::uuid, coalesce(p_wh, current_setting('fcx.wh')::uuid), 'FCX Warehouse', now() - make_interval(days => p_days + 1), now() - make_interval(days => p_days),
          p_company, p_contact, p_phone, p_line1, 'Toronto', 'ON', p_postal, p_country)
  returning id into v_so;
  insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered) select v_so, 1, p.id, p.sku, 1, 2 from public.product p where p.is_active order by p.sku limit 1;
  return v_so;
end $$;
create function pg_temp.mk_unit(p_so uuid, p_label text, p_type text, p_l numeric, p_w numeric, p_h numeric, p_unit text, p_wt numeric, p_wunit text, p_parent bigint default null) returns bigint language plpgsql as $$
declare v_id bigint;
begin
  insert into public.wms_pallets (order_id, label, unit_type, status, parent_id, dim_length, dim_width, dim_height, dim_unit, weight, weight_unit)
  values (p_so, p_label, p_type, 'completed', p_parent, p_l, p_w, p_h, p_unit, p_wt, p_wunit) returning id into v_id;
  insert into public.wms_pallet_items (pallet_id, order_id, qty_base) values (v_id, p_so, 2);
  return v_id;
end $$;
select set_config('fcx.cad', :'cad', true), set_config('fcx.wh', :'wh', true) \gset
select pg_temp.mk_so('1', 'packed', :'c_a'::uuid, 'FCX Alpha Corp', 'Alpha Buyer', '4165550101 x', '100 Fcx Street', 'M5V 1A1', 'Canada', 3)::text as s1,
       pg_temp.mk_so('2', 'packed', :'c_a'::uuid, 'FCX Alpha Corp', 'Alpha Buyer', '4165550101', '100 Fcx Street', 'M5V 1A1', 'CANADA', 2)::text as s2,
       pg_temp.mk_so('3', 'packed', :'c_a'::uuid, 'FCX Alpha Corp', 'Alpha Buyer', '4165550101', '999 Other Rd', 'M9W 9Z9', 'CA', 2)::text as s3,
       pg_temp.mk_so('4', 'packed', :'c_a'::uuid, 'FCX Alpha Corp', 'Alpha Buyer', '4165550101', '100 Fcx Street', 'M5V 1A1', 'Canada', 1)::text as s4,
       pg_temp.mk_so('5', 'packed', :'c_a'::uuid, 'FCX Alpha Corp', 'Alpha Buyer', '4165550101', '100 Fcx Street', 'M5V 1A1', 'Canada', 1)::text as s5,
       pg_temp.mk_so('6', 'packed', :'c_p'::uuid, null, 'FCX Person', null, '200 Fcx Lane', 'M4B 2C2', 'CA', 1)::text as s6,
       pg_temp.mk_so('7', 'packed', :'c_a'::uuid, 'FCX Alpha Corp', 'Alpha Buyer', '4165550101', '100 Fcx Street', 'M5V 1A1', 'Canada', 1)::text as s7,
       pg_temp.mk_so('8', 'picking', :'c_a'::uuid, 'FCX Alpha Corp', 'Alpha Buyer', '4165550101', '100 Fcx Street', 'M5V 1A1', 'Canada', 1)::text as s8,
       pg_temp.mk_so('9', 'confirmed', :'c_a'::uuid, 'FCX Alpha Corp', 'Alpha Buyer', '4165550101', '100 Fcx Street', 'M5V 1A1', 'Canada', 1)::text as s9,
       pg_temp.mk_so('10', 'packed', :'c_a'::uuid, 'FCX Alpha Corp', 'Alpha Buyer', '4165550101', '100 Fcx Street', 'M5V 1A1', 'Canada', 0)::text as s10,
       pg_temp.mk_so('11', 'packed', :'c_a'::uuid, 'FCX Alpha Corp', 'Alpha Buyer', '4165550101', '100 Fcx Street', 'M5V 1A1', 'Canada', 0, :'wh2'::uuid)::text as s11 \gset
insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, secret_prefix, is_active, live) values ('fcx', 'fcx-test.myshopify.com', 'FCX Store', 'aone', :'tier'::uuid, 'SHOPIFY_FCX', false, false) returning id::text as store \gset
insert into public.shop_order (store_id, shopify_order_gid, name, raw, status, so_id) values (:'store'::uuid, 'gid://shopify/Order/799999001', '#FCX1', '{}'::jsonb, 'created', :'s7'::uuid);
set local session_replication_role = origin;   -- 유닛은 트리거(wms_pallet_dims)를 켜고 넣는다
select pg_temp.mk_unit(:'s1'::uuid, 'B1', 'box', 12, 10, 8, 'in', 23, 'lb')::text as b1,
       pg_temp.mk_unit(:'s2'::uuid, 'B2', 'box', 30, 25, 20, 'cm', 10, 'kg')::text as b2,
       pg_temp.mk_unit(:'s3'::uuid, 'B3', 'box', 12, 10, 8, 'in', 23, 'lb')::text as b3,
       pg_temp.mk_unit(:'s4'::uuid, 'P1', 'pallet', 48, 40, 48, 'in', 800, 'lb')::text as p1,
       pg_temp.mk_unit(:'s5'::uuid, 'B5', 'box', null, null, null, null, null, null)::text as b5,
       pg_temp.mk_unit(:'s6'::uuid, 'B6', 'box', 12, 10, 8, 'in', 23, 'lb')::text as b6,
       pg_temp.mk_unit(:'s7'::uuid, 'B7', 'box', 12, 10, 8, 'in', 23, 'lb')::text as b7,
       pg_temp.mk_unit(:'s8'::uuid, 'B8', 'box', 12, 10, 8, 'in', 23, 'lb')::text as b8,
       pg_temp.mk_unit(:'s11'::uuid, 'B11', 'box', 12, 10, 8, 'in', 23, 'lb')::text as b11 \gset
select pg_temp.mk_unit(:'s4'::uuid, 'B4a', 'box', null, null, null, null, null, null, :'p1'::bigint)::text as b4a, pg_temp.mk_unit(:'s4'::uuid, 'B4b', 'box', null, null, null, null, null, null, :'p1'::bigint)::text as b4b \gset
insert into public.wms_pallet_items (pallet_id, order_id, qty_base) values (:'b8'::bigint, :'s10'::uuid, 1);   -- 공유 유닛: B8(S8) 에 S10 물건
select pg_temp.chk('M0 fake material: 11 SO · 11 units · 3 carriers · 2 customers · 3 staff',
  ((select count(*) from public.so where so_number like 'SO-79900%') || '/' || (select count(*) from public.wms_pallets where order_id in (select id from public.so where so_number like 'SO-79900%'))
   || '/' || (select count(*) from public.ref_carrier where name like 'FCX %') || '/' || (select count(*) from public.customer where name like 'FCX %') || '/' || (select count(*) from public.ims_staff where email like 'fcx-%'))::text, '11/11/3/2/3');

-- ── F 꼴 · 권한 ──
select pg_temp.chk('F1 new tables 6 · functions 14', (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r' and relname in ('fc_shipment', 'fc_shipment_so', 'fc_quote', 'fc_quote_rate', 'fc_call_log', 'customer_carrier_avoid'))::text || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_gate', 'fc_norm', 'fc_country', 'fc_phone', 'fc_money_cents', 'fc_units_snapshot', 'fc_shipment_live_sync', 'fc_shipment_prepare', 'fc_quote_save', 'fc_quote_select', 'fc_charge_so_set', 'fc_shipment_for_so', 'wms_unit_dims_set', 'customer_carrier_avoid_set'))::text, '6/14');
select pg_temp.chk('F2 fc_shipment_so_live_uq = unique (so_id) where live', (select pg_get_indexdef(i.indexrelid) from pg_index i where i.indexrelid = to_regclass('public.fc_shipment_so_live_uq')), 'CREATE UNIQUE INDEX fc_shipment_so_live_uq ON public.fc_shipment_so USING btree (so_id) WHERE live');
select pg_temp.chk('F3 anon · service_role cannot run fc_shipment_prepare · authenticated can', (has_function_privilege('anon', 'public.fc_shipment_prepare(uuid[], jsonb, boolean)', 'execute') || '/' || has_function_privilege('service_role', 'public.fc_shipment_prepare(uuid[], jsonb, boolean)', 'execute') || '/' || has_function_privilege('authenticated', 'public.fc_shipment_prepare(uuid[], jsonb, boolean)', 'execute'))::text, 'false/false/true');
select pg_temp.chk('F4 fc_gate · fc_units_snapshot are inner (no authenticated execute)', (has_function_privilege('authenticated', 'public.fc_gate(uuid, text)', 'execute') || '/' || has_function_privilege('authenticated', 'public.fc_units_snapshot(uuid[])', 'execute'))::text, 'false/false');
select pg_temp.chk('F5 fc_markup_pct seeded 5', (select value from public.inv_config where key = 'fc_markup_pct'), '5');
select pg_temp.chk('F6 Freightcom name unique across carriers (case · space) — fc-1b3 name table', pg_temp.errhead(pg_temp.try(format('insert into public.ref_carrier_fc_name (carrier_id, name) values (%L, '' FCX ALPHA '') returning name', :'car_g'))), 'ERR 23505: duplicate key value violates unique constrain');
select pg_temp.chk('F7 so_finalize untouched', (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize'), :'fin_md5_0');

-- ── 1 상자 한 개 · 미리 보기 → 실행 ──
select pg_temp.as_user(:'u_off');
select public.fc_shipment_prepare(array[:'s1'::uuid], '{}'::jsonb, false) as pv \gset
select pg_temp.chk('1a preview: not committed · action new · package · mode office', (:'pv'::jsonb->>'committed') || '/' || (:'pv'::jsonb->>'action') || '/' || (:'pv'::jsonb->>'packaging_type') || '/' || (:'pv'::jsonb->>'mode') || '/' || ((:'pv'::jsonb->>'shipment_id') is null)::text, 'false/new/package/office/true');
select pg_temp.chk('1b preview writes nothing (shipments of the FCX orders only — real rows exist since the live test · bo-2b 이견 8)', (select count(*) from public.fc_shipment f where f.charge_so_id in (select id from public.so where so_number like 'SO-79900%'))::text, '0');
select pg_temp.chk('1c payload: packaging_type package · one package · in · lb · 12×10×8 · 23', (:'pv'::jsonb#>>'{request,details,packaging_type}') || '/' || jsonb_array_length(:'pv'::jsonb#>'{request,details,packaging_properties,packages}') || '/' ||
  (:'pv'::jsonb#>>'{request,details,packaging_properties,packages,0,measurements,cuboid,unit}') || '/' || (:'pv'::jsonb#>>'{request,details,packaging_properties,packages,0,measurements,weight,unit}') || '/' ||
  (:'pv'::jsonb#>>'{request,details,packaging_properties,packages,0,measurements,cuboid,l}') || '/' || (:'pv'::jsonb#>>'{request,details,packaging_properties,packages,0,measurements,weight,value}') || '/' || (:'pv'::jsonb#>>'{request,details,packaging_properties,packages,0,description}'), 'package/1/in/lb/12/23/B1');
select pg_temp.chk('1d payload: destination CA · postal no space · phone digits only · region ON · name = company · email from contact', (:'pv'::jsonb#>>'{request,details,destination,address,country}') || '/' || (:'pv'::jsonb#>>'{request,details,destination,address,postal_code}') || '/' || (:'pv'::jsonb#>>'{request,details,destination,phone_number,number}') || '/' ||
  (:'pv'::jsonb#>>'{request,details,destination,address,region}') || '/' || (:'pv'::jsonb#>>'{request,details,destination,name}') || '/' || (:'pv'::jsonb#>>'{request,details,destination,email_addresses,0}'), 'CA/M5V1A1/4165550101/ON/FCX Alpha Corp/alpha@test.invalid');
select pg_temp.chk('1e payload: origin from warehouse · phone digits · contact · email · ship date today', (:'pv'::jsonb#>>'{request,details,origin,name}') || '/' || (:'pv'::jsonb#>>'{request,details,origin,phone_number,number}') || '/' || (:'pv'::jsonb#>>'{request,details,origin,contact_name}') || '/' || (:'pv'::jsonb#>>'{request,details,origin,address,country}') || '/' ||
  ((:'pv'::jsonb#>>'{request,details,expected_ship_date,year}')::int = extract(year from public.ims_today())::int and (:'pv'::jsonb#>>'{request,details,expected_ship_date,day}')::int = extract(day from public.ims_today())::int)::text, 'FCX Warehouse/4167922298/FCX Contact/CA/true');
select pg_temp.chk('1f package payload has no pallet_service_details · no num_pieces', ((:'pv'::jsonb#>'{request,details,packaging_properties}') ? 'pallet_service_details' or (:'pv'::jsonb#>'{request,details,packaging_properties,packages,0}') ? 'num_pieces')::text, 'false');
select pg_temp.chk('1g charge_so = S1 · carriers list has the 3 fcx names · payload_hash = md5(request)', (:'pv'::jsonb->>'first_so_number') || '/' || (select string_agg(x, ',' order by x) from jsonb_array_elements_text(:'pv'::jsonb->'carriers') x where x like 'Fcx %') || '/' || ((:'pv'::jsonb->>'payload_hash') = md5((:'pv'::jsonb->'request')::text))::text, 'SO-79900a/Fcx Alpha,Fcx Beta,Fcx Gamma/true');
select public.fc_shipment_prepare(array[:'s1'::uuid], '{}'::jsonb, true) as r1 \gset
select pg_temp.chk('1h commit: shipment row draft · one live so row · created_in office · hash same as preview', (select f.status || '/' || f.created_in || '/' || (f.payload_hash = (:'pv'::jsonb->>'payload_hash'))::text || '/' || (select count(*) from public.fc_shipment_so l where l.shipment_id = f.id and l.live) from public.fc_shipment f where f.id = (:'r1'::jsonb->>'shipment_id')::uuid), 'draft/office/true/1');

-- ── 2 같은 배송지 둘 → 발송 하나 · charge_so = 먼저 만든 것 · 옮기기 ──
select public.fc_shipment_prepare(array[:'s2'::uuid, :'s1'::uuid], '{}'::jsonb, true) as r2 \gset
select pg_temp.chk('2a two orders · action supersede (S1 had its own shipment) · charge_so = S1 (created first) · 2 so', (:'r2'::jsonb->>'action') || '/' || (:'r2'::jsonb->>'charge_so_number') || '/' || jsonb_array_length(:'r2'::jsonb->'so_numbers'), 'supersede/SO-79900a/2');
select pg_temp.chk('2b old shipment cancelled · superseded_by new · its so rows live=false · S1 live rows = 1', (select f.status || '/' || (f.superseded_by = (:'r2'::jsonb->>'shipment_id')::uuid)::text || '/' || (select count(*) from public.fc_shipment_so l where l.shipment_id = f.id and l.live) from public.fc_shipment f where f.id = (:'r1'::jsonb->>'shipment_id')::uuid)
  || '/' || (select count(*) from public.fc_shipment_so l where l.so_id = :'s1'::uuid and l.live), 'cancelled/true/0/1');
select pg_temp.chk('2c cm/kg box in payload as in/lb (30×25×20 cm · 10 kg → 11.81×9.84×7.87 · 22.05)', (select (p->'measurements'->'cuboid'->>'l') || '/' || (p->'measurements'->'cuboid'->>'w') || '/' || (p->'measurements'->'cuboid'->>'h') || '/' || (p->'measurements'->'weight'->>'value')
  from jsonb_array_elements(:'r2'::jsonb#>'{request,details,packaging_properties,packages}') p where p->>'description' = 'B2'), '11.81/9.84/7.87/22.05');
select pg_temp.chk('2d fc_charge_so_set → S2 (office)', (public.fc_charge_so_set((:'r2'::jsonb->>'shipment_id')::uuid, :'s2'::uuid))->>'charge_so_number', 'SO-79900b');
select pg_temp.chk('2e fc_charge_so_set with an order not on the shipment → refused', pg_temp.errhead(pg_temp.try(format('select public.fc_charge_so_set(%L, %L)::text', :'r2'::jsonb->>'shipment_id', :'s3'))), 'ERR P0001: That order is not on this shipment — nothing ');

-- ── 3 거부 넷: 다른 배송지 · 섞임 · 치수 없음 · 상태 · 공유 유닛 ──
select pg_temp.chk('3a different ship-to → refused', pg_temp.errhead(pg_temp.try(format('select public.fc_shipment_prepare(array[%L,%L]::uuid[], ''{}'', false)::text', :'s1', :'s3'))), 'ERR P0001: Orders SO-79900c have a different ship-to add');
select pg_temp.chk('3b box + pallet → refused', pg_temp.errhead(pg_temp.try(format('select public.fc_shipment_prepare(array[%L,%L]::uuid[], ''{}'', false)::text', :'s1', :'s4'))), 'ERR P0001: This shipment mixes boxes and pallets (box + ');
select pg_temp.chk('3c unit without dims → refused with the unit name', pg_temp.errhead(pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', false)::text', :'s5'))), 'ERR P0001: Units B5 need length, width, height and weigh');
select pg_temp.chk('3d confirmed order → refused · picking (working) allowed', pg_temp.errhead(pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', false)::text', :'s9'))) || ' | ' || (pg_temp.try(format('select public.fc_shipment_prepare(array[%L,%L]::uuid[], ''{}'', false)::text', :'s8', :'s10'))::jsonb->>'action'), 'ERR P0001: Order SO-79900i is confirmed — freight quotes | new');
select pg_temp.chk('3e shared unit (B8 holds S10 goods) → refused naming S10 · with S10 included → ok', pg_temp.errhead(pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', false)::text', :'s8'))), 'ERR P0001: These units also hold goods of SO-79900j — in');
select pg_temp.chk('3f other warehouse mixed → refused', pg_temp.errhead(pg_temp.try(format('select public.fc_shipment_prepare(array[%L,%L]::uuid[], ''{}'', false)::text', :'s1', :'s11'))), 'ERR P0001: Orders SO-79900k ship from a different wareho');

-- ── 4 839 주거지 기본 · 주소 기억 ──
select pg_temp.chk('4a company (ship_to_company set) → residential false', (pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', false)::text', :'s1'))::jsonb#>>'{options,residential}'), 'false');
select public.fc_shipment_prepare(array[:'s6'::uuid], '{}'::jsonb, false) as pv6 \gset
select pg_temp.chk('4b person (AONE · no company) → residential true · phone from contact mobile · address matched', (:'pv6'::jsonb#>>'{options,residential}') || '/' || (:'pv6'::jsonb#>>'{request,details,destination,phone_number,number}') || '/' || ((:'pv6'::jsonb->>'address_id') = :'addr_p')::text || '/' || (:'pv6'::jsonb#>>'{request,details,destination,name}'), 'true/6475550202/true/FCX Person');
select public.fc_shipment_prepare(array[:'s6'::uuid], '{"residential": false, "tailgate_required": true, "remember": true}'::jsonb, true) as r6 \gset
select pg_temp.chk('4c remember → address row updated (residential false · tailgate true · threshold false)', (select a.residential::text || '/' || a.tailgate_required::text || '/' || a.threshold_delivery::text from public.customer_address a where a.id = :'addr_p'::uuid), 'false/true/false');
select pg_temp.chk('4d next prepare without options → remembered values win over default', (select (o#>>'{options,residential}') || '/' || (o#>>'{options,tailgate_required}') || '/' || (o#>>'{request,details,destination,tailgate_required}') from (select pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', false)::text', :'s6'))::jsonb as o) t), 'false/true/true');
select pg_temp.chk('4e remember with no matching address → warning address_not_found · no write', (select (o->'warnings')::text || '/' || ((o->>'address_id') is null)::text from (select pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{"remember": true}'', false)::text', :'s3'))::jsonb as o) t), '["address_not_found"]/true');

-- ── 5 840 팔렛 payload: 테일게이트 · 인사이드 · num_pieces · ltl ──
select pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{"tailgate_required": true, "threshold_delivery": true}'', false)::text', :'s4'))::jsonb as pv4 \gset
select pg_temp.chk('5a pallet: packaging_type pallet · ltl · not stackable · tailgate on destination · threshold in pallet_service_details', (:'pv4'::jsonb#>>'{request,details,packaging_type}') || '/' || (:'pv4'::jsonb#>>'{request,details,packaging_properties,pallet_type}') || '/' || (:'pv4'::jsonb#>>'{request,details,packaging_properties,has_stackable_pallets}') || '/' ||
  (:'pv4'::jsonb#>>'{request,details,destination,tailgate_required}') || '/' || (:'pv4'::jsonb#>>'{request,details,packaging_properties,pallet_service_details,threshold_delivery}'), 'pallet/ltl/false/true/true');
select pg_temp.chk('5b pallet: one pallet · num_pieces 2 (two boxes inside) · 48×40×48 · 800 · no freight_class (EF fills)', jsonb_array_length(:'pv4'::jsonb#>'{request,details,packaging_properties,pallets}') || '/' || (:'pv4'::jsonb#>>'{request,details,packaging_properties,pallets,0,num_pieces}') || '/' || (:'pv4'::jsonb#>>'{request,details,packaging_properties,pallets,0,measurements,cuboid,l}') || '/' ||
  (:'pv4'::jsonb#>>'{request,details,packaging_properties,pallets,0,measurements,weight,value}') || '/' || ((:'pv4'::jsonb#>'{request,details,packaging_properties,pallets,0}') ? 'freight_class')::text, '1/2/48/800/false');
select pg_temp.chk('5c origin never tailgate/residential', (:'pv4'::jsonb#>>'{request,details,origin,tailgate_required}') || '/' || (:'pv4'::jsonb#>>'{request,details,origin,residential}'), 'false/false');

-- ── 6 · 7 견적 저장(service_role) · 836 셈 · 843 avoided · preselected · 고르기 ──
select public.customer_carrier_avoid_set(:'c_a'::uuid, array[:'car_g'::uuid]) as av \gset
select pg_temp.chk('6a avoid list set for Alpha Corp = Gamma', (:'av'::jsonb->'carrier_ids')::text, jsonb_build_array(:'car_g'::uuid)::text);
select pg_temp.chk('6b avoid list refuses Pickup kind', (pg_temp.try(format('select public.customer_carrier_avoid_set(%L, array[(select id from public.ref_carrier where kind = ''pickup'' limit 1)])::text', :'c_a')) like 'ERR P0001: Carrier(s) % are not on the carrier list (Pickup · Delivery cannot be avoided)%')::text, 'true');
\set rates '{"rates": [ {"service_id": "fcxalpha.std", "carrier_name": "Fcx Alpha", "service_name": "Standard", "base": {"currency": "CAD", "value": "2500"}, "surcharges": [{"type": "fuel", "amount": {"currency": "CAD", "value": "497"}}], "taxes": [{"type": "HST", "amount": {"currency": "CAD", "value": "390"}}], "total": {"currency": "CAD", "value": "3387"}, "transit_time_days": 3, "valid_until": {"year": 2026, "month": 11, "day": 4}}, {"service_id": "fcxbeta.std", "carrier_name": "Fcx Beta", "service_name": "Ground", "base": {"currency": "CAD", "value": "3000"}, "surcharges": [], "taxes": [{"type": "HST", "amount": "390"}], "total": "3390"}, {"service_id": "fcxgamma.exp", "carrier_name": "Fcx Gamma", "service_name": "Express", "base": {"currency": "CAD", "value": "1000"}, "total": {"currency": "CAD", "value": "1130"}, "taxes": [{"type": "HST", "amount": {"currency": "CAD", "value": "130"}}]}, {"service_id": "unk.x", "carrier_name": "Unknown Carrier", "service_name": "X", "base": {"currency": "CAD", "value": "900"}, "total": {"currency": "CAD", "value": "900"}}, {"service_id": "fcxbeta.exp", "carrier_name": "fcx beta", "service_name": "Express", "base": {"currency": "CAD", "value": "3500"}, "total": {"currency": "CAD", "value": "9999"}} ]}'
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_quote_save((:'r2'::jsonb->>'shipment_id')::uuid, 'req-1', :'rates'::jsonb) as q1 \gset
select pg_temp.chk('6c quote_save (service_role · no staff gate): 5 rates · status done · markup 5', (:'q1'::jsonb->>'rates') || '/' || (:'q1'::jsonb->>'status') || '/' || (:'q1'::jsonb->>'markup_pct'), '5/done/5');
select pg_temp.chk('6d 836: pretax 2997 → 3147 · 3000 → 3150 · tax from object and from string · totals_mismatch flag on the wrong total', (select string_agg(r.service_id || '=' || r.pretax_cents || '>' || r.customer_charge_cents || ':' || r.tax_cents || ':' || r.totals_mismatch::text, ' ' order by r.service_id) from public.fc_quote_rate r where r.quote_id = (:'q1'::jsonb->>'quote_id')::uuid) collate "C",
  'fcxalpha.std=2997>3147:390:false fcxbeta.exp=3500>3675:0:true fcxbeta.std=3000>3150:390:false fcxgamma.exp=1000>1050:130:false unk.x=900>945:0:false');
select pg_temp.chk('6e carrier pairing case-insensitive (fcx beta → Beta) · Unknown → null · valid_until · transit', (select (r.carrier_id = :'car_b'::uuid)::text from public.fc_quote_rate r where r.quote_id = (:'q1'::jsonb->>'quote_id')::uuid and r.service_id = 'fcxbeta.exp') || '/' ||
  (select (r.carrier_id is null)::text from public.fc_quote_rate r where r.quote_id = (:'q1'::jsonb->>'quote_id')::uuid and r.service_id = 'unk.x') || '/' ||
  (select r.valid_until::text || '/' || r.transit_days from public.fc_quote_rate r where r.quote_id = (:'q1'::jsonb->>'quote_id')::uuid and r.service_id = 'fcxalpha.std'), 'true/true/2026-11-04/3');
select pg_temp.chk('7a 843: Gamma avoided · default carrier Beta → preselected = cheapest Beta (fcxbeta.std) not cheaper Alpha', (select string_agg(r.service_id, ',' order by r.service_id) from public.fc_quote_rate r where r.quote_id = (:'q1'::jsonb->>'quote_id')::uuid and r.avoided) || '/' ||
  (select r.service_id from public.fc_quote_rate r where r.quote_id = (:'q1'::jsonb->>'quote_id')::uuid and r.preselected) || '/' || (:'q1'::jsonb->>'preselected_rate_id' = (select r.id::text from public.fc_quote_rate r where r.quote_id = (:'q1'::jsonb->>'quote_id')::uuid and r.preselected))::text, 'fcxgamma.exp/fcxbeta.std/true');
select pg_temp.chk('7b shipment quoted · selected null', (select f.status || '/' || (f.selected_rate_id is null)::text from public.fc_shipment f where f.id = (:'r2'::jsonb->>'shipment_id')::uuid), 'quoted/true');
select pg_temp.as_user(:'u_off');
select pg_temp.chk('7c select avoided → refused · unknown carrier → refused', pg_temp.errhead(pg_temp.try(format('select public.fc_quote_select(%L, (select id from public.fc_quote_rate where quote_id = %L and service_id = ''fcxgamma.exp''))::text', :'r2'::jsonb->>'shipment_id', :'q1'::jsonb->>'quote_id'))) || ' | ' ||
  pg_temp.errhead(pg_temp.try(format('select public.fc_quote_select(%L, (select id from public.fc_quote_rate where quote_id = %L and service_id = ''unk.x''))::text', :'r2'::jsonb->>'shipment_id', :'q1'::jsonb->>'quote_id'))),
  'ERR P0001: This customer avoids Fcx Gamma — pick another | ERR P0001: Carrier "Unknown Carrier" is not on the IMS c');
select public.fc_quote_select((:'r2'::jsonb->>'shipment_id')::uuid, (select id from public.fc_quote_rate where quote_id = (:'q1'::jsonb->>'quote_id')::uuid and service_id = 'fcxalpha.std')) as sel \gset
select pg_temp.chk('7d select Alpha std → selected · charge_amount 31.47 · carrier Alpha', (:'sel'::jsonb->>'charge_amount') || '/' || ((:'sel'::jsonb->>'carrier_id') = :'car_a')::text || '/' || (select f.status from public.fc_shipment f where f.id = (:'r2'::jsonb->>'shipment_id')::uuid), '31.47/true/selected');
select public.fc_shipment_for_so(:'s2'::uuid) as fs \gset
select pg_temp.chk('7e for_so(S2): shipment selected · 2 orders · charge so = S2 · 5 rates · avoided last · selected flagged · charge_amount 31.47 · units unchanged', (:'fs'::jsonb#>>'{shipment,status}') || '/' || jsonb_array_length(:'fs'::jsonb->'orders') || '/' || (select o->>'so_number' from jsonb_array_elements(:'fs'::jsonb->'orders') o where (o->>'is_charge_so')::boolean) || '/' ||
  jsonb_array_length(:'fs'::jsonb#>'{quote,rates}') || '/' || (:'fs'::jsonb#>>'{quote,rates,4,service_id}') || '/' || (select r->>'service_id' from jsonb_array_elements(:'fs'::jsonb#>'{quote,rates}') r where (r->>'selected')::boolean) || '/' || (:'fs'::jsonb->>'charge_amount') || '/' || (:'fs'::jsonb->>'units_changed'),
  'selected/2/SO-79900b/5/fcxgamma.exp/fcxalpha.std/31.47/false');
select public.fc_shipment_for_so(:'s3'::uuid) as fs3 \gset
select pg_temp.chk('7f for_so(S3 · no shipment): shipment null · units_now 1 · units_without_dims 0', (jsonb_typeof(:'fs3'::jsonb->'shipment') = 'null')::text || '/' || jsonb_array_length(:'fs3'::jsonb->'units_now') || '/' || (:'fs3'::jsonb->>'units_without_dims'), 'true/1/0');
select public.wms_unit_dims_set(:'b1'::bigint, '{"dim_length": "13"}'::jsonb) as d0 \gset
select pg_temp.chk('7g units_changed true after a unit dims change (S1 box resized)', (public.fc_shipment_for_so(:'s1'::uuid))->>'units_changed', 'true');
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_quote_save((:'r6'::jsonb->>'shipment_id')::uuid, 'req-2', :'rates'::jsonb) as q6 \gset
select pg_temp.chk('7h no default carrier · nothing avoided → preselected = cheapest paired (Gamma 1000 · not Unknown 900)', (select r.service_id from public.fc_quote_rate r where r.quote_id = (:'q6'::jsonb->>'quote_id')::uuid and r.preselected), 'fcxgamma.exp');
select pg_temp.as_user(:'u_off');

-- ── 8 웹 오더(aone · 손님이 운임 결제) → 운임 줄 덮지 않음 표식 ──
select public.fc_shipment_prepare(array[:'s7'::uuid], '{}'::jsonb, true) as r7 \gset
select pg_temp.chk('8a aone web order → freight_locked true · reason names #FCX1', (:'r7'::jsonb->>'freight_locked') || '/' || (:'r7'::jsonb->>'freight_locked_reason'), 'true/customer paid freight in Shopify (#FCX1)');
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_quote_save((:'r7'::jsonb->>'shipment_id')::uuid, 'req-3', :'rates'::jsonb) as q7 \gset
select pg_temp.as_user(:'u_off');
select pg_temp.chk('8b quote still computes customer_charge · select returns charge_amount null · for_so charge_amount null', (select r.customer_charge_cents::text from public.fc_quote_rate r where r.quote_id = (:'q7'::jsonb->>'quote_id')::uuid and r.service_id = 'fcxalpha.std') || '/' ||
  (((public.fc_quote_select((:'r7'::jsonb->>'shipment_id')::uuid, (select id from public.fc_quote_rate where quote_id = (:'q7'::jsonb->>'quote_id')::uuid and service_id = 'fcxalpha.std')))->>'charge_amount') is null)::text, '3147/true');
select pg_temp.chk('8b2 for_so charge_amount null when locked', (((public.fc_shipment_for_so(:'s7'::uuid))->>'charge_amount') is null)::text, 'true');
select pg_temp.chk('8c asung-kind web order is not locked (S1 has no shop_order) — already shown by 1h', (select f.freight_locked::text from public.fc_shipment f where f.id = (:'r2'::jsonb->>'shipment_id')::uuid), 'false');

-- ── 9 한 SO 한 발송 · 같은 묶음 갈아 끼움 · 옛 견적 남음 ──
select public.fc_shipment_prepare(array[:'s1'::uuid, :'s2'::uuid], '{}'::jsonb, true) as r9 \gset
select pg_temp.chk('9a same set again → action replace · same shipment id · back to draft · selection cleared · old quote kept (1)', (:'r9'::jsonb->>'action') || '/' || ((:'r9'::jsonb->>'shipment_id') = (:'r2'::jsonb->>'shipment_id'))::text || '/' || (select f.status || '/' || (f.selected_rate_id is null)::text || '/' || (select count(*) from public.fc_quote q where q.shipment_id = f.id) from public.fc_shipment f where f.id = (:'r2'::jsonb->>'shipment_id')::uuid), 'replace/true/draft/true/1');
select pg_temp.chk('9b replace keeps the charge SO the office moved to (S2) · returned charge_so_number too', (select s.so_number from public.fc_shipment f join public.so s on s.id = f.charge_so_id where f.id = (:'r2'::jsonb->>'shipment_id')::uuid) || '/' || (:'r9'::jsonb->>'charge_so_number') || '/' || (:'r9'::jsonb->>'first_so_number'), 'SO-79900b/SO-79900b/SO-79900a');
select public.fc_shipment_prepare(array[:'s1'::uuid], '{}'::jsonb, true) as r9b \gset
select pg_temp.chk('9c S1 alone → supersede · S1 and S2 each have exactly one live row (S2 none now) · superseded shipment keeps its quote', (:'r9b'::jsonb->>'action') || '/' || (select count(*) from public.fc_shipment_so l where l.so_id = :'s1'::uuid and l.live) || '/' || (select count(*) from public.fc_shipment_so l where l.so_id = :'s2'::uuid and l.live) || '/' ||
  (select count(*) from public.fc_quote q where q.shipment_id = (:'r2'::jsonb->>'shipment_id')::uuid), 'supersede/1/0/1');
select pg_temp.chk('9d second live row for one SO is impossible (partial unique)', pg_temp.errhead(pg_temp.try(format('insert into public.fc_shipment_so (shipment_id, so_id) values (%L, %L) returning so_id::text', :'r6'::jsonb->>'shipment_id', :'s1'))), 'ERR 23505: duplicate key value violates unique constrain');
select pg_temp.chk('9e booked shipment → prepare refused', pg_temp.errhead(pg_temp.try2(format('update public.fc_shipment set status = ''booked'' where id = %L', :'r9b'::jsonb->>'shipment_id'), format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', false)::text', :'s1'))), 'ERR P0001: Orders SO-79900a are on a booked shipment — c');

-- ── 10 권한: 창고 문 · sales 문 · 둘 다 없음 · 창고 밖 · charge_so_set 은 sales 만 ──
select pg_temp.as_user(:'u_wms');
select pg_temp.chk('10a warehouse worker (fulfillment · own warehouse) → mode wms', (pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', false)::text', :'s2'))::jsonb->>'mode'), 'wms');
select pg_temp.chk('10b warehouse worker · other warehouse → refused', pg_temp.errhead(pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', false)::text', :'s11'))), 'ERR P0001: This order belongs to another warehouse — not');
select pg_temp.chk('10c fc_charge_so_set needs sales (worker refused) · customer_carrier_avoid_set too', pg_temp.errhead(pg_temp.try(format('select public.fc_charge_so_set(%L, %L)::text', :'r9b'::jsonb->>'shipment_id', :'s1'))) || ' | ' || pg_temp.errhead(pg_temp.try(format('select public.customer_carrier_avoid_set(%L, ''{}'')::text', :'c_a'))),
  'ERR P0001: You cannot change sales data — ask an admin t | ERR P0001: You cannot change sales data — ask an admin t');
select pg_temp.chk('10d quote_save as a staff user goes through the gate (worker ok on own warehouse)', (pg_temp.try(format('select public.fc_quote_save(%L, ''req-w'', %L::jsonb)::text', :'r9b'::jsonb->>'shipment_id', :'rates'))::jsonb->>'status'), 'done');
select pg_temp.as_user(:'u_none');
select pg_temp.chk('10e neither permission → refused (prepare · select · for_so still readable)', pg_temp.errhead(pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', false)::text', :'s2'))) || ' | ' || ((public.fc_shipment_for_so(:'s1'::uuid))->>'so_number'), 'ERR P0001: You cannot work with freight quotes — ask an  | SO-79900a');
select pg_temp.chk('10f quote_save by a staff user without the gate → refused', pg_temp.errhead(pg_temp.try(format('select public.fc_quote_save(%L, ''req-x'', %L::jsonb)::text', :'r9b'::jsonb->>'shipment_id', :'rates'))), 'ERR P0001: You cannot work with freight quotes — ask an ');

-- ── 11 오피스 치수 창구 ──
select pg_temp.as_user(:'u_off');
select public.wms_unit_dims_set(:'b5'::bigint, '{"dim_length": "10", "dim_width": "10", "dim_height": "10", "dim_unit": "in", "weight": "5", "weight_unit": "lb"}'::jsonb) as d1 \gset
select pg_temp.chk('11a office sets in/lb → trigger fills *_in · weight_lb', (:'d1'::jsonb->>'length_in') || '/' || (:'d1'::jsonb->>'weight_lb') || '/' || (:'d1'::jsonb->>'dim_unit'), '10.00/5.00/in');
select public.wms_unit_dims_set(:'b5'::bigint, '{"dim_length": "100", "dim_width": "50", "dim_height": "25", "dim_unit": "cm", "weight": "10", "weight_unit": "kg"}'::jsonb) as d2 \gset
select pg_temp.chk('11b cm/kg → 39.37 × 19.69 × 9.84 · 22.05 lb', (:'d2'::jsonb->>'length_in') || '/' || (:'d2'::jsonb->>'width_in') || '/' || (:'d2'::jsonb->>'height_in') || '/' || (:'d2'::jsonb->>'weight_lb'), '39.37/19.69/9.84/22.05');
select pg_temp.chk('11c bad unit mm → CHECK refuses · zero weight → CHECK refuses', pg_temp.errhead(pg_temp.try(format('select public.wms_unit_dims_set(%s, ''{"dim_unit": "mm"}'')::text', :'b5'))) || ' | ' || pg_temp.errhead(pg_temp.try(format('select public.wms_unit_dims_set(%s, ''{"weight": "0"}'')::text', :'b5'))),
  'ERR 23514: new row for relation "wms_pallets" violates c | ERR 23514: new row for relation "wms_pallets" violates c');
select pg_temp.chk('11d S5 now quotable (dims present)', (pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', false)::text', :'s5'))::jsonb->>'action'), 'new');
select pg_temp.as_user(:'u_none');
select pg_temp.chk('11e dims without permission → refused', pg_temp.errhead(pg_temp.try(format('select public.wms_unit_dims_set(%s, ''{"weight": "6"}'')::text', :'b5'))), 'ERR P0001: You cannot work with freight quotes — ask an ');
select pg_temp.as_user(:'u_off');

-- ── 12 기존 창구에 더한 열쇠 · 옛 호출 그대로 · 설정 ──
select (public.customer_update(jsonb_build_array(jsonb_build_object('op', 'address_set', 'customer_id', :'c_a', 'address_id', :'addr_a', 'values', jsonb_build_object('line2', 'Unit 10'), 'olds', jsonb_build_object('line2', (select a.line2 from public.customer_address a where a.id = :'addr_a'::uuid)))), true, array[:'c_a' || ':open_so_keep_old']) - 'reviewed_now' - 'warnings')::text as cu_new \gset
\if :{?mig}
select pg_temp.chk('M1 old-key customer_update call: same shape before and after (committed · changes · applied)', (:'cu_old_shape'::jsonb - 'changes')::text || '/' || (:'cu_old_shape'::jsonb#>>'{changes,0,applied}'), (:'cu_new'::jsonb - 'changes')::text || '/' || (:'cu_new'::jsonb#>>'{changes,0,applied}'));
\endif
select pg_temp.chk('12a old-key address_set still writes (line2 = Unit 10)', (select a.line2 from public.customer_address a where a.id = :'addr_a'::uuid), 'Unit 10');
select public.customer_update(jsonb_build_array(jsonb_build_object('op', 'address_set', 'customer_id', :'c_a', 'address_id', :'addr_a', 'values', jsonb_build_object('residential', 'true', 'threshold_delivery', 'true'), 'olds', jsonb_build_object('residential', null, 'threshold_delivery', 'false'))), true, array[:'c_a' || ':open_so_keep_old']) as cu12b \gset
select pg_temp.chk('12b new keys via customer_update address_set (residential true · threshold true) · old must be sent', (:'cu12b'::jsonb->>'committed')
  || '/' || (select a.residential::text || '/' || a.threshold_delivery::text || '/' || a.tailgate_required::text from public.customer_address a where a.id = :'addr_a'::uuid), 'true/true/true/false');
select pg_temp.chk('12c changed_elsewhere on a new key (old residential false ≠ now true) → block', (select (public.customer_update(jsonb_build_array(jsonb_build_object('op', 'address_set', 'customer_id', :'c_a', 'address_id', :'addr_a', 'values', jsonb_build_object('residential', 'false'), 'olds', jsonb_build_object('residential', 'false'))), true, array[:'c_a' || ':open_so_keep_old']))#>>'{blocks,0,code}'), 'changed_elsewhere');
select (public.customer_update(jsonb_build_array(jsonb_build_object('op', 'address_add', 'customer_id', :'c_a', 'values', jsonb_build_object('type', 'Shipping', 'line1', '300 Fcx Way', 'city', 'Toronto', 'postal_code', 'M1M 1M1', 'residential', 'false', 'tailgate_required', 'true'))), true, array[:'c_a' || ':open_so_keep_old']))->>'committed' as add_ok \gset
select pg_temp.chk('12d address_add with the new keys', :'add_ok' || '/' || (select a.residential::text || '/' || a.tailgate_required::text from public.customer_address a where a.customer_id = :'c_a'::uuid and a.line1 = '300 Fcx Way'), 'true/false/true');
select pg_temp.chk('12e ims_config_set fc_markup_pct 7 (master) · 150 refused · abc refused', ((public.ims_config_set('fc_markup_pct', '7'))->>'value') || ' | ' || pg_temp.errhead(pg_temp.try('select public.ims_config_set(''fc_markup_pct'', ''150'')::text')) || ' | ' || pg_temp.errhead(pg_temp.try('select public.ims_config_set(''fc_markup_pct'', ''abc'')::text')),
  '7 | ERR P0001: fc_markup_pct must be a percent from 0 to 100 | ERR P0001: fc_markup_pct must be a percent from 0 to 100');
select pg_temp.as_user(:'u_none', 'service_role');
select (public.fc_quote_save((:'r9b'::jsonb->>'shipment_id')::uuid, 'req-4', :'rates'::jsonb))->>'quote_id' as q4 \gset
select pg_temp.chk('12f markup 7 → 2997 × 1.07 = 3206.79 → 3207 on the next quote', (select r.customer_charge_cents::text || '/' || r.markup_pct from public.fc_quote_rate r where r.quote_id = :'q4'::uuid and r.service_id = 'fcxalpha.std'), '3207/7');
select pg_temp.as_user(:'u_off');
set local role authenticated;
select pg_temp.chk('12g settings direct write (RLS master · authenticated): warehouse phone · carrier Freightcom names via the window (fc-1b3)', pg_temp.run(format('update public.ref_warehouse set phone = ''416-000-0000'' where id = %L returning phone', :'wh')) || '/' || pg_temp.run(format('select (public.ref_carrier_fc_names_set(%L, array[''Fcx Gamma'', ''Fcx Gamma LTL'']))->>''names''', :'car_g')), '416-000-0000/["Fcx Gamma", "Fcx Gamma LTL"]');
reset role;
select pg_temp.chk('12h ims_config_set other keys unchanged path: unknown key still "is not a setting"', pg_temp.errhead(pg_temp.try('select public.ims_config_set(''fc_nonsense'', ''1'')::text')), 'ERR P0001: Setting fc_nonsense is not a setting — nothin');

-- ── 결과 ──
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
-- ── Z 실제 행 무변 · md5 복귀(begin 밖) ──
select case when (select count(*) from public.so) = :n_so0 and (select count(*) from public.customer) = :n_cust0 and (select count(*) from public.customer_address) = :n_addr0 and (select count(*) from public.wms_pallets) = :n_unit0
            and (select count(*) from public.ref_carrier) = :n_car0 and (select count(*) from public.ref_warehouse) = :n_wh0 and (select count(*) from public.inv_config) = :n_cfg0 and (select count(*) from public.ims_staff) = :n_staff0
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'customer_update') = :'cu_md5_0'
             and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_config_set') = :'cfg_md5_0'
             and to_regclass('public.fc_shipment') is null then 'Z2 OK functions · tables rolled back' else 'Z2 MISMATCH rollback left something' end as z2;
\endif
