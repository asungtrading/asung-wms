-- supabase/tests/so_shipto_1_check.sql — so-shipto-1 Finalized 오더 배송지 바꾸기 창구 so_ship_to_change 검증 (2026-11-12 · 판정 1200 ~ 1210)
-- [테스트 · Asung-IMS] 시험 적용 장치 — db_role = test 가드 → 기준(begin 앞) → begin → (-v mig 면 \i) → 가짜(직원 둘 · SO 스물셋 · 발송 · 예약 · 유닛 · 웹 오더 · 결제 — 전부 rollback) → S0 · T1 ~ T25 · M → rollback → Z
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261113001115_so_shipto_1_ship_to_change.sql -f supabase/tests/so_shipto_1_check.sql
--   기대 OK: 시험(-v mig) · 확인(적용 뒤) 둘 다 42 + Z1 + RESULT OK(exit 0) · MISMATCH 가 있으면 exit 3
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 마른 실행(적용 전 · -v mig 없음)은 MISMATCH 가 나야 한다(창구가 없다)
--   ⚠️ 발행 · 예약 · 견적 창구를 부르지 않는다(번호 시퀀스 · 실제 Freightcom) — 발송 · 예약은 가짜 행 · SO 는 번호 · id 를 직접 넣는다(SO-7995x ~ 7997x · id 끝자리 = 번호 → 잠금 · 「첫 오더」 순서가 정해진다)
--   ⚠️ 상태가 draft 가 아닌 가짜는 문지기를 replica 로 비껴 넣는다 · 손님 · 통화 · 제품 · 계정 · 창고 · 스토어는 실물 id 를 FK 로만 빌린다
\set ON_ERROR_STOP on
\pset pager off
select coalesce((select value from public.inv_config where key = 'db_role'), '(missing)') as db_role \gset
select (:'db_role' = 'test') as is_test \gset
\echo '── db_role' :db_role
\if :is_test
\else
\echo 'STOP — inv_config.db_role is not test — nothing was run'
\quit
\endif
-- ── 기준(begin 앞) ──
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('so_header_update', 'so_finalize', 'so_invoice_rule_pick', 'so_copy_customer', 'fc_shipment_prepare', 'fc_book_prepare', 'fc_book_cancel_save', 'customer_update', 'so_tax_refresh', 'so_ship_to_change');
select (select count(*) from t_pre where proname = 'so_ship_to_change') = 0 as fn_absent \gset
select (select count(*) from public.so) as w_so, (select count(*) from public.ims_staff) as w_staff, (select count(*) from public.fc_shipment) as w_ship, (select count(*) from public.fc_booking) as w_book,
       (select count(*) from public.customer_address) as w_addr, (select count(*) from public.shop_order) as w_shop, (select count(*) from public.so where so_number ~ '^SO-799[5-7][0-9]$') as w_fake,
       (select count(*)::text || '/' || coalesce(md5(string_agg(f.id::text || f.status, '|' order by f.id)), '') from public.fc_shipment f) as m_ship0 \gset
\echo '── 기준: so' :w_so '· staff' :w_staff '· fc_shipment' :w_ship '· fc_booking' :w_book '· customer_address' :w_addr '· fake SO-7995x~7x' :w_fake '· new fn absent' :fn_absent
\set EXPECT_OK 42
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin0 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
-- safeupdate 의 규칙을 정적으로 센다(cdc_1_check.sql · shn_1_check.sql 의 것 그대로)
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop
      v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g');
      exit when v_chunk = v_prev;
    end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
$$;
-- 값 하나 읽기(없는 표 · 함수여도 멈추지 않는다 — 마른 실행) · p_role 을 주면 그 역할로
create function pg_temp.q(p_sql text, p_role text default null) returns text language plpgsql as $$
declare v text;
begin
  if p_role is not null then execute format('set local role %I', p_role); end if;
  execute p_sql into v;
  if p_role is not null then reset role; end if;
  return coalesce(v, '(null)');
exception when others then reset role; return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 창구를 화면처럼 부른다(authenticated · 가짜 직원 uid) · 결과는 jsonb 글자 · 예외는 'ERR <sqlstate>: <문장>'
create function pg_temp.stc(p_uid text, p_orders jsonb, p_addr jsonb, p_save boolean default false, p_cond jsonb default null) returns text language plpgsql as $$
declare v text;
begin
  perform pg_temp.as_user(p_uid);
  execute 'set local role authenticated';
  execute format('select public.so_ship_to_change(%L::jsonb, %L::jsonb, %L::boolean, %L::jsonb)::text', p_orders, p_addr, p_save, p_cond) into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then reset role; return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.nine(p_so text) returns jsonb language sql as $$
  select jsonb_build_object('ship_to_company', s.ship_to_company, 'ship_to_contact', s.ship_to_contact, 'ship_to_phone', s.ship_to_phone, 'ship_to_line1', s.ship_to_line1, 'ship_to_line2', s.ship_to_line2,
                            'ship_to_city', s.ship_to_city, 'ship_to_state_province', s.ship_to_state_province, 'ship_to_postal_code', s.ship_to_postal_code, 'ship_to_country', s.ship_to_country)
  from public.so s where s.id = p_so::uuid;
$$;
-- p_orders: 오더마다 지금 값을 「화면이 본 옛 값」 으로
create function pg_temp.ord(variadic p_ids text[]) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('so_id', i, 'old', pg_temp.nine(i))) from unnest(p_ids) i;
$$;
create function pg_temp.addr(p_line1 text, p_city text, p_state text, p_postal text, p_country text default 'Canada') returns jsonb language sql as $$
  select jsonb_build_object('ship_to_company', 'New Co', 'ship_to_contact', 'New Contact', 'ship_to_phone', '613-555-0199', 'ship_to_line1', p_line1, 'ship_to_line2', '  ',
                            'ship_to_city', p_city, 'ship_to_state_province', p_state, 'ship_to_postal_code', p_postal, 'ship_to_country', p_country);
$$;
create function pg_temp.ship9(p_so text) returns text language sql as $$
  select concat_ws('|', coalesce(s.ship_to_company, '(null)'), coalesce(s.ship_to_contact, '(null)'), coalesce(s.ship_to_phone, '(null)'), coalesce(s.ship_to_line1, '(null)'), coalesce(s.ship_to_line2, '(null)'),
                   coalesce(s.ship_to_city, '(null)'), coalesce(s.ship_to_state_province, '(null)'), coalesce(s.ship_to_postal_code, '(null)'), coalesce(s.ship_to_country, '(null)'))
  from public.so s where s.id = p_so::uuid;
$$;
create function pg_temp.taxs(p_so text) returns text language sql as $$
  select concat_ws('|', coalesce(s.tax_rule_id::text, '(null)'), coalesce(s.tax_rule, '(null)'), s.tax_rule_manual::text) from public.so s where s.id = p_so::uuid;
$$;
-- 아홉 칸 · 세금 셋 · updated_* 를 뺀 나머지
create function pg_temp.rest(p_so text) returns text language sql as $$
  select md5((to_jsonb(s) - array['ship_to_company', 'ship_to_contact', 'ship_to_phone', 'ship_to_line1', 'ship_to_line2', 'ship_to_city', 'ship_to_state_province', 'ship_to_postal_code', 'ship_to_country',
                                  'tax_rule', 'tax_rule_id', 'tax_rule_manual', 'updated_at', 'updated_by'])::text) from public.so s where s.id = p_so::uuid;
$$;
create function pg_temp.fullrow(p_so text) returns text language sql as $$ select md5(to_jsonb(s)::text) from public.so s where s.id = p_so::uuid; $$;
create function pg_temp.codes(p text) returns text language sql as $$
  select coalesce((select string_agg(w->>'code', ',' order by w->>'code') from jsonb_array_elements(pg_temp.j(p)->'warnings') w), case when pg_temp.j(p) is null then p else '' end);
$$;
create function pg_temp.wmsg(p text, p_code text) returns text language sql as $$
  select coalesce((select w->>'message' from jsonb_array_elements(pg_temp.j(p)->'warnings') w where w->>'code' = p_code), '(none)');
$$;
create function pg_temp.shst(p_ship text) returns text language sql as $$
  select concat_ws('|', f.status, coalesce(f.cancel_reason, '(null)'), (f.cancelled_at is not null)::text, (select string_agg(l.live::text, ',' order by l.so_id) from public.fc_shipment_so l where l.shipment_id = f.id))
  from public.fc_shipment f where f.id = p_ship::uuid;
$$;
create function pg_temp.logs(p_so text, p_expr text) returns text language sql as $$
  select pg_temp.q(format('select string_agg((%s)::text, '';'' order by g.changed_at, g.id) from public.so_ship_to_log g where g.so_id = %L', p_expr, p_so));
$$;

-- ── 가짜 ──
select w.id::text as wh_tor from public.ref_warehouse w where w.name = 'Asung Trading Inc.' \gset
select w.id::text as wh_edm from public.ref_warehouse w where w.name = 'Asung - Edmonton' \gset
select c.id::text as cust, c.currency_id::text as cur from public.customer c where c.is_active and c.default_ship_to_customer_id is null order by c.created_at, c.id limit 1 \gset
select c.id::text as cust_b from public.customer c where c.is_active and c.default_ship_to_customer_id is null and c.id <> :'cust'::uuid
   and exists (select 1 from public.customer_address a where a.customer_id = c.id and a.is_active and a.type = 'Shipping') order by c.created_at, c.id limit 1 \gset
select a.id::text as addr_b from public.customer_address a where a.customer_id = :'cust_b'::uuid and a.is_active and a.type = 'Shipping' order by a.id limit 1 \gset
select p.id::text as prod from public.product p where p.is_active order by p.created_at, p.id limit 1 \gset
select a.id::text as acct from public.ref_account a order by a.code limit 1 \gset
select st.id::text as store_aone from public.shop_store st where st.kind = 'aone' order by st.code limit 1 \gset
-- 세금 규칙 — 기대는 so_tax_rule_for 반환 그대로
select r->>'rule_id' as on_id, r->>'rule' as on_name, trim_scale((r->>'rate_pct')::numeric)::text as on_rate from public.so_tax_rule_for('Canada', 'ON', public.ims_today(), 'sale') r \gset
select r->>'rule_id' as ab_id, r->>'rule' as ab_name, trim_scale((r->>'rate_pct')::numeric)::text as ab_rate from public.so_tax_rule_for('Canada', 'AB', public.ims_today(), 'sale') r \gset
select r->>'rule_id' as zr_id, r->>'rule' as zr_name, trim_scale((r->>'rate_pct')::numeric)::text as zr_rate from public.so_tax_rule_for('France', null, public.ims_today(), 'sale') r \gset
\echo '── 세금: ON' :on_name :on_rate '· AB' :ab_name :ab_rate '· 해외' :zr_name :zr_rate
select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) as m_addr_a0, count(*) as n_addr_a0 from public.customer_address a where a.customer_id = :'cust'::uuid \gset
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'shipto1-sales@test.invalid', 'SHIPTO1 Sales', 'worker', '["sales"]', '{}') returning auth_user_id::text as u_sales, id::text as st_sales \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'shipto1-picker@test.invalid', 'SHIPTO1 Picker', 'worker', '["picking", "fulfillment"]', '{}') returning auth_user_id::text as u_pick \gset
create temp table t_so (k text primary key, id text, so_number text);
insert into t_so (k, so_number) values ('a', 'SO-79951'), ('b', 'SO-79952'), ('m', 'SO-79953'), ('m2', 'SO-79954'), ('x', 'SO-79955'), ('d', 'SO-79956'), ('bk', 'SO-79957'), ('pn', 'SO-79958'), ('s1', 'SO-79959'),
  ('g1', 'SO-79960'), ('g2', 'SO-79961'), ('t1', 'SO-79962'), ('t2', 'SO-79963'), ('cf', 'SO-79964'), ('u1', 'SO-79965'), ('u2', 'SO-79966'), ('o', 'SO-79967'), ('w', 'SO-79968'), ('ad', 'SO-79969'),
  ('dr', 'SO-79970'), ('n', 'SO-79971'), ('ad2', 'SO-79972'), ('ad3', 'SO-79973');
update t_so set id = '00000000-0000-4000-8000-0000000' || right(so_number, 5) where true;
insert into public.so (id, so_number, customer_id, channel, intake, currency_id, status, location_id, ship_to_company, ship_to_contact, ship_to_phone, ship_to_line1, ship_to_line2, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country,
                       tax_rule_id, tax_rule, tax_rule_manual, created_at, updated_at)
select t.id::uuid, t.so_number, case when t.k = 'o' then :'cust_b' else :'cust' end::uuid, 'warehouse', case when t.k = 'x' then 'shopify' else 'manual' end, :'cur'::uuid,
       case t.k when 'cf' then 'confirmed' when 'dr' then 'draft' else 'packed' end, case when t.k = 'w' then :'wh_edm' else :'wh_tor' end::uuid,
       'Old Co', 'Old Contact', '416-555-0100', case when t.k = 'n' then '2 Other Street' else '1 Old Street' end, null, 'Toronto', 'ON', 'M1M 1M1', 'Canada',
       case when t.k in ('m', 'm2') then :'zr_id' when t.k = 'dr' then null else :'on_id' end::uuid, case when t.k in ('m', 'm2') then :'zr_name' when t.k = 'dr' then null else :'on_name' end, t.k in ('m', 'm2'),
       now() - interval '2 day', now() - interval '1 day'
from t_so t;
select max(id) filter (where k = 'a') as s_a, max(id) filter (where k = 'b') as s_b, max(id) filter (where k = 'm') as s_m, max(id) filter (where k = 'm2') as s_m2, max(id) filter (where k = 'x') as s_x,
       max(id) filter (where k = 'd') as s_d, max(id) filter (where k = 'bk') as s_bk, max(id) filter (where k = 'pn') as s_pn, max(id) filter (where k = 's1') as s_s1, max(id) filter (where k = 'g1') as s_g1,
       max(id) filter (where k = 'g2') as s_g2, max(id) filter (where k = 't1') as s_t1, max(id) filter (where k = 't2') as s_t2, max(id) filter (where k = 'cf') as s_cf, max(id) filter (where k = 'u1') as s_u1,
       max(id) filter (where k = 'u2') as s_u2, max(id) filter (where k = 'o') as s_o, max(id) filter (where k = 'w') as s_w, max(id) filter (where k = 'ad') as s_ad, max(id) filter (where k = 'dr') as s_dr,
       max(id) filter (where k = 'n') as s_n, max(id) filter (where k = 'ad2') as s_ad2, max(id) filter (where k = 'ad3') as s_ad3 from t_so \gset
-- 줄 · 운임(세금 기록이 따라오는지) — b 오더
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, unit_price, tax_rule) values (:'s_b'::uuid, 1, :'prod'::uuid, 'SHIPTO1-SKU', 1, 1, 1, :'on_name');
insert into public.so_charge (so_id, line_no, name, amount, tax_rule) values (:'s_b'::uuid, 1, 'Freight', 5, :'on_name');
-- 발송: bk(booked + 예약 booked) · pn(selected + 예약 pending) · s1(selected) · g(selected · g1 + g2 · 주소 기억 필요 열림) · t(quoted · t1 + t2)
create temp table t_ship (k text primary key, id text);
with ins as (
  insert into public.fc_shipment (status, origin_warehouse_id, packaging_type, charge_so_id, customer_id, origin, destination, options, units, request, payload_hash, created_in, address_review)
  select v.st, :'wh_tor'::uuid, 'package', v.so::uuid, :'cust'::uuid, '{}', '{"address": {"city": "Toronto"}}', '{}', '[]', '{"details": {"destination": {"address": {"city": "Toronto"}}}}', 'shipto1-' || v.k, 'office',
         case when v.k = 'g' then '{"reason": "wms"}'::jsonb end
  from (values ('bk', 'booked', :'s_bk'), ('pn', 'selected', :'s_pn'), ('s1', 'selected', :'s_s1'), ('g', 'selected', :'s_g1'), ('t', 'quoted', :'s_t1')) v(k, st, so)
  returning id, payload_hash)
insert into t_ship (k, id) select substr(i.payload_hash, 9), i.id::text from ins i;
select max(id) filter (where k = 'bk') as f_bk, max(id) filter (where k = 'pn') as f_pn, max(id) filter (where k = 's1') as f_s1, max(id) filter (where k = 'g') as f_g, max(id) filter (where k = 't') as f_t from t_ship \gset
insert into public.fc_shipment_so (shipment_id, so_id) values (:'f_bk'::uuid, :'s_bk'::uuid), (:'f_pn'::uuid, :'s_pn'::uuid), (:'f_s1'::uuid, :'s_s1'::uuid),
  (:'f_g'::uuid, :'s_g1'::uuid), (:'f_g'::uuid, :'s_g2'::uuid), (:'f_t'::uuid, :'s_t1'::uuid), (:'f_t'::uuid, :'s_t2'::uuid);
insert into public.fc_booking (shipment_id, attempt, unique_id, status, freightcom_shipment_id, booked_at) values (:'f_bk'::uuid, 1, 'shipto1-bk-1', 'booked', 'shipto1-fake', now());
insert into public.fc_booking (shipment_id, attempt, unique_id, status) values (:'f_pn'::uuid, 1, 'shipto1-pn-1', 'pending');
-- 유닛: u1 의 상자에 u2 물건이 함께 들었다
insert into public.wms_pallets (id, unit_type, order_id, label) overriding system value values (990000001, 'box', :'s_u1'::uuid, 'SHIPTO1-BOX');
insert into public.wms_pallet_items (id, pallet_id, order_id) overriding system value values (990000001, 990000001, :'s_u1'::uuid), (990000002, 990000001, :'s_u2'::uuid);
-- 웹 오더(aone · PAID) → x · 결제(디파짓) → d
insert into public.shop_order (store_id, shopify_order_gid, name, financial_status, raw, status, so_id) values (:'store_aone'::uuid, 'gid://shopify/Order/999999900001', '#SHIPTO1-1', 'PAID', '{}', 'created', :'s_x'::uuid) returning id::text as shop_x \gset
with p as (insert into public.so_payment (kind, amount, method, customer_id, currency_id, account_id, warehouse_id) values ('payment', 10, 'cash', :'cust'::uuid, :'cur'::uuid, :'acct'::uuid, :'wh_tor'::uuid) returning id)
insert into public.so_payment_order (payment_id, so_id) select p.id, :'s_d'::uuid from p;
set local session_replication_role = origin;
create temp table t_base as select t.k, t.id, pg_temp.rest(t.id) as rest0, pg_temp.fullrow(t.id) as full0 from t_so t;
select md5(to_jsonb(o)::text) as m_shop_x0 from public.shop_order o where o.id = :'shop_x'::uuid \gset

-- ── S0 스캐너 자기 시험 ──
select pg_temp.chk('S0 scanner self-test: no-where update 1 · where 0 · subquery-where-only 1 · with-update no-where 1 · delete no-where 1 · then-update 1 · string update 0 · where singleton 0',
  pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
  || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text
  || pg_temp.nowhere('update t set a = 1 where singleton returning * into v;')::text, '10111100');

-- ── T1 같은 주(ON → ON) ──
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_a'), pg_temp.addr('  99 New Road ', 'Ottawa', 'ON', 'K1A 0B1')) as r1 \gset
select pg_temp.chk('T1a same province: changed true · nine cells saved btrim · blank line2 → null · tax rule untouched · no warnings · other columns same',
  concat_ws(' / ', coalesce(pg_temp.j(:'r1')->>'changed', :'r1'), pg_temp.ship9(:'s_a'), pg_temp.taxs(:'s_a'), '[' || pg_temp.codes(:'r1') || ']', (pg_temp.rest(:'s_a') = (select rest0 from t_base where k = 'a'))::text),
  'true / New Co|New Contact|613-555-0199|99 New Road|(null)|Ottawa|ON|K1A 0B1|Canada / ' || :'on_id' || '|' || :'on_name' || '|false / [] / true');
select pg_temp.chk('T1b result: one order · tax_changed false · no shipment cut · updated_by = the staff · log row 1 (before line1 → after line1 · by staff)',
  concat_ws(' / ', jsonb_array_length(pg_temp.j(:'r1')->'orders')::text, pg_temp.j(:'r1')#>>'{orders,0,tax_changed}', pg_temp.j(:'r1')->>'shipments_cancelled',
            (select (s.updated_by::text = :'st_sales')::text from public.so s where s.id = :'s_a'::uuid),
            pg_temp.logs(:'s_a', $$concat_ws('→', g.before->>'ship_to_line1', g.after->>'ship_to_line1', g.changed_by)$$)),
  '1 / false / [] / true / 1 Old Street→99 New Road→' || :'st_sales');

-- ── T2 다른 주(ON → AB) — 세금 ──
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_b'), pg_temp.addr('500 Centre St', 'Calgary', 'AB', 'T2P 1J9')) as r2 \gset
select pg_temp.chk('T2a other province: changed · so rule = so_tax_rule_for(AB) · manual false · so_line · so_charge tax_rule follow · warnings = tax_changed',
  concat_ws(' / ', coalesce(pg_temp.j(:'r2')->>'changed', :'r2'), pg_temp.taxs(:'s_b'), (select l.tax_rule from public.so_line l where l.so_id = :'s_b'::uuid), (select c.tax_rule from public.so_charge c where c.so_id = :'s_b'::uuid), '[' || pg_temp.codes(:'r2') || ']'),
  'true / ' || :'ab_id' || '|' || :'ab_name' || '|false / ' || :'ab_name' || ' / ' || :'ab_name' || ' / [tax_changed]');
select pg_temp.chk('T2b tax_changed message names old → new rule with rates and says to send the Ship Ready again (1210) · log tax_before → tax_after',
  pg_temp.wmsg(:'r2', 'tax_changed') || ' / ' || pg_temp.logs(:'s_b', $$concat_ws('→', g.tax_before->>'rule', g.tax_after->>'rule', g.tax_after->>'manual')$$),
  'The tax rule changed with the new ship-to (SO-79952: ' || :'on_name' || ' ' || :'on_rate' || '% → ' || :'ab_name' || ' ' || :'ab_rate' || '%) — the order totals follow the new rule. If a Ship Ready was already sent, send it again. / '
  || :'on_name' || '→' || :'ab_name' || '→false');

-- ── T3 · T4 사람이 정한 규칙(판정 7) ──
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_m'), pg_temp.addr('500 Centre St', 'Calgary', 'AB', 'T2P 1J9')) as r3 \gset
select pg_temp.chk('T3 manual rule + province change → manual released · ship-to rule (AB) · warnings tax_changed + tax_rule_reset_by_ship_to',
  concat_ws(' / ', coalesce(pg_temp.j(:'r3')->>'changed', :'r3'), pg_temp.taxs(:'s_m'), '[' || pg_temp.codes(:'r3') || ']'),
  'true / ' || :'ab_id' || '|' || :'ab_name' || '|false / [tax_changed,tax_rule_reset_by_ship_to]');
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_m2'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) as r4 \gset
select pg_temp.chk('T4 manual rule + same province → the manual rule stays · no warnings',
  concat_ws(' / ', coalesce(pg_temp.j(:'r4')->>'changed', :'r4'), pg_temp.ship9(:'s_m2'), pg_temp.taxs(:'s_m2'), '[' || pg_temp.codes(:'r4') || ']'),
  'true / New Co|New Contact|613-555-0199|99 New Road|(null)|Ottawa|ON|K1A 0B1|Canada / ' || :'zr_id' || '|' || :'zr_name' || '|true / []');

-- ── T5 · T6 aone(1205) ──
select pg_temp.chk('T5a aone order → another province refused · row untouched',
  pg_temp.stc(:'u_sales', pg_temp.ord(:'s_x'), pg_temp.addr('500 Centre St', 'Calgary', 'AB', 'T2P 1J9')) || ' / ' || (pg_temp.fullrow(:'s_x') = (select full0 from t_base where k = 'x'))::text,
  'ERR P0001: Order SO-79955 was paid in Shopify (#SHIPTO1-1) — its ship-to cannot move to another province or country — nothing was saved / true');
select pg_temp.chk('T5b aone order → province the tax table cannot read (ZZ) refused the same way · row untouched',
  pg_temp.stc(:'u_sales', pg_temp.ord(:'s_x'), pg_temp.addr('500 Centre St', 'Calgary', 'ZZ', 'T2P 1J9')) || ' / ' || (pg_temp.fullrow(:'s_x') = (select full0 from t_base where k = 'x'))::text,
  'ERR P0001: Order SO-79955 was paid in Shopify (#SHIPTO1-1) — its ship-to cannot move to another province or country — nothing was saved / true');
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_x'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) as r6 \gset
select pg_temp.chk('T6 aone order → same province allowed · Shopify order row untouched',
  concat_ws(' / ', coalesce(pg_temp.j(:'r6')->>'changed', :'r6'), pg_temp.ship9(:'s_x'), '[' || pg_temp.codes(:'r6') || ']', (select (md5(to_jsonb(o)::text) = :'m_shop_x0')::text from public.shop_order o where o.id = :'shop_x'::uuid)),
  'true / New Co|New Contact|613-555-0199|99 New Road|(null)|Ottawa|ON|K1A 0B1|Canada / [] / true');

-- ── T7 디파짓 붙은 오더 → 다른 주 허락 ──
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_d'), pg_temp.addr('500 Centre St', 'Calgary', 'AB', 'T2P 1J9')) as r7 \gset
select pg_temp.chk('T7 order with a deposit (so_payment_order) → another province allowed · tax follows · payment rows untouched',
  concat_ws(' / ', coalesce(pg_temp.j(:'r7')->>'changed', :'r7'), pg_temp.taxs(:'s_d'), '[' || pg_temp.codes(:'r7') || ']', (select count(*)::text from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active' where o.so_id = :'s_d'::uuid)),
  'true / ' || :'ab_id' || '|' || :'ab_name' || '|false / [tax_changed] / 1');

-- ── T8 · T9 살아 있는 예약(1201) ──
select pg_temp.chk('T8 booked shipment → refused · order row and shipment untouched',
  pg_temp.stc(:'u_sales', pg_temp.ord(:'s_bk'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) || ' / ' || (pg_temp.fullrow(:'s_bk') = (select full0 from t_base where k = 'bk'))::text || ' / ' || pg_temp.shst(:'f_bk'),
  'ERR P0001: Cancel the Freightcom booking first — SO-79957 (booked) — nothing was saved / true / booked|(null)|false|true');
select pg_temp.chk('T9 selected shipment with a pending booking → refused · order row and shipment untouched',
  pg_temp.stc(:'u_sales', pg_temp.ord(:'s_pn'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) || ' / ' || (pg_temp.fullrow(:'s_pn') = (select full0 from t_base where k = 'pn'))::text || ' / ' || pg_temp.shst(:'f_pn'),
  'ERR P0001: Cancel the Freightcom booking first — SO-79958 (booking in progress) — nothing was saved / true / selected|(null)|false|true');

-- ── T10 selected 발송 끊김 ──
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_s1'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) as r10 \gset
select pg_temp.chk('T10 selected shipment → cancelled · cancel_reason ship_to_changed · live false (trigger) · result and log carry the shipment id · no warnings',
  concat_ws(' / ', coalesce(pg_temp.j(:'r10')->>'changed', :'r10'), pg_temp.shst(:'f_s1'), pg_temp.j(:'r10')->>'shipments_cancelled', pg_temp.j(:'r10')#>>'{orders,0,shipments_cancelled}', pg_temp.logs(:'s_s1', 'g.shipments_cancelled'), '[' || pg_temp.codes(:'r10') || ']'),
  'true / cancelled|ship_to_changed|true|false / ["' || :'f_s1' || '"] / ["' || :'f_s1' || '"] / {' || :'f_s1' || '} / []');

-- ── T11 하나만 바꾸기 — 배열 밖 형제(1209) ──
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_g1'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) as r11 \gset
select pg_temp.chk('T11a one of two orders on a shared shipment → allowed · shipment cut for both · warnings shipment_siblings_cut + address_review_dropped · siblings_cut names the other order',
  concat_ws(' / ', coalesce(pg_temp.j(:'r11')->>'changed', :'r11'), pg_temp.shst(:'f_g'), '[' || pg_temp.codes(:'r11') || ']', pg_temp.j(:'r11')->>'siblings_cut', pg_temp.logs(:'s_g1', 'g.siblings_cut')),
  'true / cancelled|ship_to_changed|true|false,false / [address_review_dropped,shipment_siblings_cut] / ["SO-79961"] / {SO-79961}');
select pg_temp.chk('T11b the sibling order row is untouched (all columns) · it has no log row · the message names it',
  concat_ws(' / ', (pg_temp.fullrow(:'s_g2') = (select full0 from t_base where k = 'g2'))::text, pg_temp.logs(:'s_g2', 'g.id'), pg_temp.wmsg(:'r11', 'shipment_siblings_cut')),
  'true / (null) / The freight quote was shared with SO-79961 — it was dropped for them too. Quote them again from their own Ship & invoice window.');

-- ── T12 함께 바꾸기 — 둘 다 배열에 ──
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_t1', :'s_t2'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) as r12 \gset
select pg_temp.chk('T12 two orders with the same old ship-to together → both saved · quoted shipment cut · no sibling warning · one change_id on both log rows',
  concat_ws(' / ', coalesce(pg_temp.j(:'r12')->>'changed', :'r12'), jsonb_array_length(pg_temp.j(:'r12')->'orders')::text, (pg_temp.ship9(:'s_t1') = pg_temp.ship9(:'s_t2'))::text, pg_temp.ship9(:'s_t2'), pg_temp.shst(:'f_t'), '[' || pg_temp.codes(:'r12') || ']',
            pg_temp.q(format('select count(*)::text || ''/'' || count(distinct g.change_id)::text from public.so_ship_to_log g where g.so_id in (%L, %L) and g.change_id = %L', :'s_t1', :'s_t2', pg_temp.j(:'r12')->>'change_id'))),
  'true / 2 / true / New Co|New Contact|613-555-0199|99 New Road|(null)|Ottawa|ON|K1A 0B1|Canada / cancelled|ship_to_changed|true|false,false / [] / 2/1');

-- ── T13 옛 값 어긋남 · T14 같은 값 ──
select pg_temp.fullrow(:'s_a') as a_full1 \gset
select pg_temp.chk('T13 the screen saw another contact than the row has → refused · row untouched',
  pg_temp.stc(:'u_sales', jsonb_build_array(jsonb_build_object('so_id', :'s_a', 'old', pg_temp.nine(:'s_a') || '{"ship_to_contact": "Somebody Else"}')), pg_temp.addr('7 Third Ave', 'Ottawa', 'ON', 'K1A 0B1'))
  || ' / ' || (pg_temp.fullrow(:'s_a') = :'a_full1')::text,
  'ERR P0001: Someone changed the ship-to address on order SO-79951 just now — reload the order and try again — nothing was saved / true');
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_a'), pg_temp.addr(' 99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) as r14 \gset
select pg_temp.chk('T14 same value after btrim → changed false · row untouched (all columns) · still one log row',
  concat_ws(' / ', coalesce(pg_temp.j(:'r14')->>'changed', :'r14'), (pg_temp.fullrow(:'s_a') = :'a_full1')::text, pg_temp.q(format('select count(*) from public.so_ship_to_log g where g.so_id = %L', :'s_a'))),
  'false / true / 1');

-- ── T15 상태 · T16 문 ──
select pg_temp.chk('T15a confirmed order → refused · row untouched',
  pg_temp.stc(:'u_sales', pg_temp.ord(:'s_cf'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) || ' / ' || (pg_temp.fullrow(:'s_cf') = (select full0 from t_base where k = 'cf'))::text,
  'ERR P0001: Order SO-79964 is confirmed — the ship-to can be changed here only once the warehouse has finalized the order — nothing was saved / true');
select pg_temp.chk('T15b draft order → refused (the draft path stays so_header_update) · row untouched',
  pg_temp.stc(:'u_sales', pg_temp.ord(:'s_dr'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) || ' / ' || (pg_temp.fullrow(:'s_dr') = (select full0 from t_base where k = 'dr'))::text,
  'ERR P0001: Order SO-79970 is a draft — change the ship-to on the order itself — nothing was saved / true');
select pg_temp.chk('T16 staff without sales write (picking · fulfillment) → refused by ims_require_write(sales) · row untouched',
  pg_temp.stc(:'u_pick', pg_temp.ord(:'s_ad'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) || ' / ' || (pg_temp.fullrow(:'s_ad') = (select full0 from t_base where k = 'ad'))::text,
  'ERR P0001: You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved / true');

-- ── T17 유닛을 나눠 가진 오더(1209) ──
select pg_temp.chk('T17a u1 alone — its box also holds goods of u2 → refused · include those orders',
  pg_temp.stc(:'u_sales', pg_temp.ord(:'s_u1'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) || ' / ' || (pg_temp.fullrow(:'s_u1') = (select full0 from t_base where k = 'u1'))::text,
  'ERR P0001: The boxes or pallets of these orders also hold goods of SO-79966 — include those orders in the change — nothing was saved / true');
select pg_temp.chk('T17b u2 alone — its goods sit in the box of u1 → refused the same way',
  pg_temp.stc(:'u_sales', pg_temp.ord(:'s_u2'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) || ' / ' || (pg_temp.fullrow(:'s_u2') = (select full0 from t_base where k = 'u2'))::text,
  'ERR P0001: The boxes or pallets of these orders also hold goods of SO-79965 — include those orders in the change — nothing was saved / true');
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_u1', :'s_u2'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) as r17 \gset
select pg_temp.chk('T17c u1 + u2 together → allowed', concat_ws(' / ', coalesce(pg_temp.j(:'r17')->>'changed', :'r17'), (pg_temp.ship9(:'s_u1') = pg_temp.ship9(:'s_u2'))::text, pg_temp.ship9(:'s_u2')),
  'true / true / New Co|New Contact|613-555-0199|99 New Road|(null)|Ottawa|ON|K1A 0B1|Canada');

-- ── T18 함께 — 다른 배송 손님 · 다른 창고 · 다른 주소 ──
select pg_temp.chk('T18a two orders of different ship-to customers → refused',
  pg_temp.stc(:'u_sales', pg_temp.ord(:'s_ad', :'s_o'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')),
  'ERR P0001: Order SO-79969 ships to a different customer than SO-79967 — change them separately — nothing was saved');
select pg_temp.chk('T18b two orders from different warehouses → refused',
  pg_temp.stc(:'u_sales', pg_temp.ord(:'s_ad', :'s_w'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')),
  'ERR P0001: Order SO-79969 ships from a different warehouse than SO-79968 — change them separately — nothing was saved');
select pg_temp.chk('T18c two orders with different old ship-to addresses → refused · both rows untouched',
  pg_temp.stc(:'u_sales', pg_temp.ord(:'s_ad', :'s_n'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1')) || ' / ' || (pg_temp.fullrow(:'s_ad') = (select full0 from t_base where k = 'ad'))::text || (pg_temp.fullrow(:'s_n') = (select full0 from t_base where k = 'n'))::text,
  'ERR P0001: Order SO-79971 has a different ship-to address than SO-79969 — change them separately — nothing was saved / truetrue');

-- ── T19 새 주소 꼴 · 세금 규칙 없음 ──
select pg_temp.chk('T19a new address without a city → refused',
  pg_temp.stc(:'u_sales', pg_temp.ord(:'s_ad3'), pg_temp.addr('99 New Road', '  ', 'ON', 'K1A 0B1')),
  'ERR P0001: The new ship-to needs a street, city, province and postal code — nothing was saved');
select pg_temp.chk('T19b province the tax table cannot read (Canada · ZZ) on a non-web order → refused · row untouched',
  pg_temp.stc(:'u_sales', pg_temp.ord(:'s_ad3'), pg_temp.addr('99 New Road', 'Ottawa', 'ZZ', 'K1A 0B1')) || ' / ' || (pg_temp.fullrow(:'s_ad3') = (select full0 from t_base where k = 'ad3'))::text,
  'ERR P0001: No tax rule for the new ship-to (ZZ · Canada) — check the province and country — nothing was saved / true');
select pg_temp.chk('T19c p_address without ship_to_phone → refused · address_id together with address fields → refused · address of another customer → refused',
  concat_ws(' / ', pg_temp.stc(:'u_sales', pg_temp.ord(:'s_ad3'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1') - 'ship_to_phone'),
            pg_temp.stc(:'u_sales', pg_temp.ord(:'s_ad3'), pg_temp.addr('99 New Road', 'Ottawa', 'ON', 'K1A 0B1') || jsonb_build_object('address_id', :'addr_b')),
            pg_temp.stc(:'u_sales', pg_temp.ord(:'s_ad3'), jsonb_build_object('address_id', :'addr_b', 'ship_to_company', 'New Co', 'ship_to_contact', 'New Contact', 'ship_to_phone', '613-555-0199'))),
  'ERR P0001: p_address must carry ship_to_company, ship_to_contact and ship_to_phone (blank is allowed) — nothing was saved / ERR P0001: Send either address_id or the address fields, not both — nothing was saved / ERR P0001: That address is not an active shipping address of this customer — nothing was saved');

-- ── T20 ~ T22 주소록(1204 · 1207) ──
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_ad'), pg_temp.addr('77 Amazon Way', 'Ottawa', 'ON', 'K2K 2K2'), true, '{"residential": false, "tailgate_required": true}') as r20 \gset
select coalesce(pg_temp.j(:'r20')#>>'{address_saved,address_id}', '00000000-0000-0000-0000-000000000000') as addr_new \gset
select pg_temp.chk('T20a save to the address book: one new row · Shipping · manual · not default · conditions (residential false · tailgate true · threshold false) · by the staff · log carries its id',
  concat_ws(' / ', coalesce(pg_temp.j(:'r20')->>'changed', :'r20'), (pg_temp.j(:'r20')#>>'{address_saved,customer_id}' = :'cust')::text,
            (select concat_ws('|', a.type, a.source, a.is_default_for_type::text, a.is_active::text, a.line1, coalesce(a.line2, '(null)'), a.city, a.state_province, a.postal_code, a.country, a.residential::text, a.tailgate_required::text, a.threshold_delivery::text, (a.updated_by::text = :'st_sales')::text)
               from public.customer_address a where a.id = :'addr_new'::uuid),
            (pg_temp.logs(:'s_ad', 'g.address_saved_id') = :'addr_new')::text, '[' || pg_temp.codes(:'r20') || ']'),
  'true / true / Shipping|manual|false|true|77 Amazon Way|(null)|Ottawa|ON|K2K 2K2|Canada|false|true|false|true / true / []');
select pg_temp.chk('T20b the customer''s other addresses (and so the default ship-to) are untouched · count + 1',
  (select (md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) = :'m_addr_a0')::text || '/' || (count(*) = :n_addr_a0)::text from public.customer_address a where a.customer_id = :'cust'::uuid and a.id <> :'addr_new'::uuid)
  || '/' || (select (count(*) = :n_addr_a0 + 1)::text from public.customer_address a where a.customer_id = :'cust'::uuid), 'true/true/true');
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_ad2'), pg_temp.addr('77  AMAZON way', 'Ottawa', 'ON', 'k2k 2k2'), true) as r21 \gset
select pg_temp.chk('T21 same address again (spacing · case differ) with save → order saved · not added again · warning address_exists · address_saved null',
  concat_ws(' / ', coalesce(pg_temp.j(:'r21')->>'changed', :'r21'), '[' || pg_temp.codes(:'r21') || ']', coalesce(pg_temp.j(:'r21')->>'address_saved', '(null)'), (select (count(*) = :n_addr_a0 + 1)::text from public.customer_address a where a.customer_id = :'cust'::uuid)),
  'true / [address_exists] / (null) / true');
select pg_temp.stc(:'u_sales', pg_temp.ord(:'s_ad3'), jsonb_build_object('address_id', :'addr_new', 'ship_to_company', 'Book Co', 'ship_to_contact', '', 'ship_to_phone', '613-555-0111'), true) as r22 \gset
select pg_temp.chk('T22 pick from the address book (address_id): six address cells from the book · company · contact · phone from p_address (blank → null) · nothing added to the book',
  concat_ws(' / ', coalesce(pg_temp.j(:'r22')->>'changed', :'r22'), pg_temp.ship9(:'s_ad3'), '[' || pg_temp.codes(:'r22') || ']', coalesce(pg_temp.j(:'r22')->>'address_saved', '(null)'), (select (count(*) = :n_addr_a0 + 1)::text from public.customer_address a where a.customer_id = :'cust'::uuid)),
  'true / Book Co|(null)|613-555-0111|77 Amazon Way|(null)|Ottawa|ON|K2K 2K2|Canada / [] / (null) / true');

-- ── T23 기록 표는 닫혔다 · 권한 ──
select pg_temp.chk('T23a so_ship_to_log: RLS on · policies 0 · no table privilege for authenticated · anon · service_role · authenticated select refused',
  concat_ws(' / ', pg_temp.q($$select c.relrowsecurity::text || '/' || (select count(*) from pg_policy p where p.polrelid = c.oid)::text from pg_class c where c.oid = 'public.so_ship_to_log'::regclass$$),
            pg_temp.q($$select has_table_privilege('authenticated', 'public.so_ship_to_log', 'select,insert,update,delete')::text || has_table_privilege('anon', 'public.so_ship_to_log', 'select,insert,update,delete')::text || has_table_privilege('service_role', 'public.so_ship_to_log', 'select,insert,update,delete')::text$$),
            left(pg_temp.q('select count(*) from public.so_ship_to_log', 'authenticated'), 9)),
  'true/0 / falsefalsefalse / ERR 42501');
select pg_temp.chk('T23b so_ship_to_change: authenticated execute · anon · service_role no · definer · search_path pinned / so_tax_refresh_at: authenticated · anon no · service_role yes · not definer / so_tax_refresh acl as before (service_role only)',
  concat_ws(' / ',
    pg_temp.q($$select has_function_privilege('authenticated', p.oid, 'execute')::text || has_function_privilege('anon', p.oid, 'execute')::text || has_function_privilege('service_role', p.oid, 'execute')::text || '/' || p.prosecdef::text || '/' || (array_to_string(p.proconfig, ',') ~ 'search_path=public, pg_temp')::text from pg_proc p where p.oid = 'public.so_ship_to_change(jsonb, jsonb, boolean, jsonb)'::regprocedure$$),
    pg_temp.q($$select has_function_privilege('authenticated', p.oid, 'execute')::text || has_function_privilege('anon', p.oid, 'execute')::text || has_function_privilege('service_role', p.oid, 'execute')::text || '/' || p.prosecdef::text from pg_proc p where p.oid = 'public.so_tax_refresh_at(uuid, uuid, text, text, boolean, text)'::regprocedure$$),
    pg_temp.q($$select has_function_privilege('authenticated', p.oid, 'execute')::text || has_function_privilege('anon', p.oid, 'execute')::text || has_function_privilege('service_role', p.oid, 'execute')::text || '/' || p.prosecdef::text from pg_proc p where p.oid = 'public.so_tax_refresh(uuid, uuid, text, text, boolean)'::regprocedure$$)),
  'truefalsefalse/true/true / falsefalsetrue/false / falsefalsetrue/false');

-- ── T24 REST 첫 겹(정적) ──
select pg_temp.chk('T24 nowhere(prosrc) = 0 for so_ship_to_change · so_tax_refresh · so_tax_refresh_at',
  (select string_agg(proname || ' ' || pg_temp.nowhere(prosrc)::text, ' · ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_ship_to_change', 'so_tax_refresh', 'so_tax_refresh_at')),
  'so_ship_to_change 0 · so_tax_refresh 0 · so_tax_refresh_at 0');

-- ── T25 so_tax_refresh(draft 길) 회귀 ──
select pg_temp.chk('T25a so_tax_refresh on a draft still picks the ship-to rule (ON) and writes it',
  concat_ws(' / ', pg_temp.q(format($$select (r->>'rule') || '|' || (r->>'manual') || '|' || (r->>'changed') from public.so_tax_refresh(%L, null) r$$, :'s_dr')), pg_temp.taxs(:'s_dr')),
  :'on_name' || '|false|true / ' || :'on_id' || '|' || :'on_name' || '|false');
select pg_temp.chk('T25b so_tax_refresh on a packed order still refuses with the original sentence · so_tax_refresh_at refuses other statuses · the wrapper is the draft door of so_tax_refresh_at',
  concat_ws(' / ', pg_temp.q(format('select public.so_tax_refresh(%L, null)::text', :'s_ad')), pg_temp.q(format($$select public.so_tax_refresh_at(%L, null, null, null, false, 'confirmed')::text$$, :'s_cf')),
            (select (p.prosrc ~ 'so_tax_refresh_at\(p_so_id, p_staff, p_prev_country, p_prev_state, p_clear_manual, ''draft''\)')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_tax_refresh')),
  'ERR P0001: This order is not a draft (status packed) — its tax rule is fixed — nothing was saved / ERR P0001: so_tax_refresh_at: status confirmed is not draft or packed — nothing was saved / true');

-- ── M 무접촉 ──
select pg_temp.chk('M1 untouched functions (prosrc md5 = begin 앞): so_header_update · so_finalize · so_invoice_rule_pick · so_copy_customer · fc_shipment_prepare · fc_book_prepare · fc_book_cancel_save · customer_update',
  (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5 where t.proname not in ('so_tax_refresh', 'so_ship_to_change')), '8');
select pg_temp.chk('M2 real freight shipments untouched (count / md5 of id + status of the rows that existed 기준) · comments carry the judgement numbers',
  (select count(*)::text || '/' || coalesce(md5(string_agg(f.id::text || f.status, '|' order by f.id)), '') from public.fc_shipment f where f.payload_hash not like 'shipto1-%') || ' / '
  || pg_temp.q($$select (obj_description('public.so_ship_to_change(jsonb, jsonb, boolean, jsonb)'::regprocedure, 'pg_proc') ~ '^so-shipto-1 판정 1200 ~ 1210')::text || (obj_description('public.so_ship_to_log'::regclass, 'pg_class') ~ '컷오버 날 지우는 순서')::text$$),
  :'m_ship0' || ' / truetrue');

-- ── 결과 ──
select clock_timestamp() - :'t_begin0'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select (count(*) filter (where not ok) = 0 and count(*) = :EXPECT_OK) as all_ok from t_res \gset
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :w_so and (select count(*) from public.ims_staff) = :w_staff and (select count(*) from public.fc_shipment) = :w_ship and (select count(*) from public.fc_booking) = :w_book
            and (select count(*) from public.customer_address) = :w_addr and (select count(*) from public.shop_order) = :w_shop and (select count(*) from public.so where so_number ~ '^SO-799[5-7][0-9]$') = :w_fake
            and (select count(*)::text || '/' || coalesce(md5(string_agg(f.id::text || f.status, '|' order by f.id)), '') from public.fc_shipment f) = :'m_ship0'
            and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_ship_to_change') = (case when :'fn_absent' = 't' then 0 else 1 end)
            and (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = (select count(*) from t_pre)
       then 'Z1 OK real rows unchanged (so · staff · fc_shipment · fc_booking · customer_address · shop_order · no fake leftovers) · functions = begin 앞' else 'Z1 MISMATCH real rows or functions changed' end as z1;
\if :all_ok
\echo 'RESULT OK'
\else
\echo 'RESULT FAIL'
do $$ begin raise exception 'so_shipto_1_check: RESULT FAIL — see the MISMATCH rows above'; end $$;
\endif
