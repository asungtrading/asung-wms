-- supabase/tests/fc_lock_1_check.sql — fc-lock-1 aone 운임 잠금을 갈린 형제 SO 까지 (2026-10-29 · 판정 882)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — 기준(begin 앞 · 잠금 없음: 실제 행 수 · 함수 md5) → begin → 옛 prosrc 담기 → (-v mig 면 \i) → 가짜 재료 FCL-(창고 · 직원 · 손님 · 주소 · 스토어 둘 · SO 열 · 유닛 · Shopify 짝)
--   → A(잠금) · B(packed 비용 문) · G(새 함수 · 순환 · 깊이) · C(재발행 diff · 시험 갈래만) · D(nowhere 정적) · E(속성 · md5 · 무접촉) → rollback → Z1 실제 행 무변 · Z2 md5 복귀(시험 갈래만)
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261029235500_fc_lock_1_aone_split.sql -f supabase/tests/fc_lock_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 27 · 확인(적용 뒤) 23 — C0 ~ C3(옛 = 새 대조)은 시험 갈래만 · Z1 · Z2 는 t_res 밖 한 줄씩
--   쓰기 0 — 가짜 재료는 rollback · 번호 시퀀스를 당기는 창구는 부르지 않는다(so_number 는 글자 그대로 SO-79910 ~ SO-79914…)
--   ⚠️ 잠금 규칙: begin ~ rollback 10 초 안(끝에 begin_to_rollback 을 찍는다)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 27
\else
\set EXPECT_OK 23
\endif
\pset pager off
select (select count(*) from public.so) as n_so0, (select count(*) from public.so_line) as n_line0, (select count(*) from public.so_charge) as n_ch0, (select count(*) from public.customer) as n_cust0,
       (select count(*) from public.customer_address) as n_addr0, (select count(*) from public.wms_pallets) as n_unit0, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.ref_warehouse) as n_wh0,
       (select count(*) from public.shop_store) as n_store0, (select count(*) from public.shop_order) as n_web0, (select count(*) from public.fc_shipment) as n_fc0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_prepare') as prep_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_charge_gate') as gate_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_charge_set') as set_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_charge_remove') as rem_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize') as fin_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_for_so') as forso_md5_0,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_chain_shop_orders') as n_chain0 \gset
\echo '── 기준: so' :n_so0 '· so_charge' :n_ch0 '· shop_order' :n_web0 '· fc_shipment' :n_fc0 '· prepare md5' :prep_md5_0 '· gate md5' :gate_md5_0 '· so_chain_shop_orders' :n_chain0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
create temp table t_pre as select proname, prosrc, md5(prosrc) as md5, array_length(string_to_array(prosrc, E'\n'), 1) as n_lines from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_shipment_prepare', 'so_charge_gate');
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 도우미 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql security definer as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.chkb(p_name text, p_ok boolean, p_note text) returns void language sql security definer as $$
  insert into t_res(name, ok, got, want) values (p_name, coalesce(p_ok, false), p_note, 'true');
$$;
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
-- 미리 보기(p_commit false)의 잠금 둘만 글자로
create function pg_temp.lock(p_ids uuid[]) returns text language plpgsql as $$
declare v jsonb;
begin
  v := public.fc_shipment_prepare(p_ids, '{}'::jsonb, false);
  return (v->>'freight_locked') || '/' || coalesce(v->>'freight_locked_reason', '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 새 함수의 출력을 글자로: 행 수/이름:종류,…
create function pg_temp.chain(p_so uuid) returns text language sql as $$
  select count(*)::text || '/' || coalesce(string_agg(c.order_name || ':' || c.store_kind, ',' order by c.order_name), '(none)') from public.so_chain_shop_orders(p_so) c;
$$;
-- ar_2b_check 꼴: 깊이 0 의 update · delete 에 WHERE 가 없는 수(주석 제거 · 괄호 속은 지움 · 글자 리터럴은 세지 않는다)
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

-- ── 재료(가짜 FCL- · replica · rollback) ──
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as tier from public.ref_price_tier where purpose = 'sale' and is_active order by code limit 1 \gset
set local session_replication_role = replica;
insert into public.ref_warehouse (name, source, is_active, address_line1, city, state_province, postal_code, country, phone, email, contact_name, freightcom_account)
  values ('FCL Warehouse', 'manual', true, '35 Suntract Road', 'North York', 'ON', 'M9N 2V8', 'Canada', '(416) 792-2298', 'fcl@test.invalid', 'FCL Contact', 'FCL') returning id::text as wh \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcl-office@test.invalid', 'FCL Office', 'manager', '["ims","sales","master"]', '{}') returning auth_user_id::text as u_off \gset
insert into public.customer (name, source, currency_id, price_tier) values ('FCL Alpha Corp', 'manual', :'cad'::uuid, 'Wholesale') returning id::text as c_a \gset
insert into public.customer_address (customer_id, source, type, is_default_for_type, line1, city, state_province, postal_code, country) values (:'c_a'::uuid, 'manual', 'Shipping', true, '100 Fcl Street', 'Toronto', 'ON', 'M5V 1A1', 'Canada') returning id::text as addr_a \gset
insert into public.customer_contact (customer_id, source, name, phone, email, is_default, is_active) values (:'c_a'::uuid, 'manual', 'Alpha Buyer', '416-555-0101', 'alpha@test.invalid', true, true);
insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, secret_prefix, is_active, live) values ('fclaone', 'fcl-aone-test.myshopify.com', 'FCL fake aone', 'aone', :'tier'::uuid, 'SHOPIFY_FCLA', false, false) returning id::text as st_aone \gset
insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, secret_prefix, is_active, live) values ('fclasung', 'fcl-asung-test.myshopify.com', 'FCL fake asung', 'asung', :'tier'::uuid, 'SHOPIFY_FCLS', false, false) returning id::text as st_asung \gset
select set_config('fcl.cad', :'cad', true), set_config('fcl.wh', :'wh', true), set_config('fcl.c_a', :'c_a', true) \gset
-- packed SO 하나(머리 전부 · 줄 하나) — 형제는 split_from_id + stock_short · intake 는 물려받은 값(실측: 형제도 shopify)
create function pg_temp.mk_so(p_number text, p_intake text, p_split_from uuid, p_days int) returns uuid language plpgsql as $$
declare v_so uuid;
begin
  insert into public.so (so_number, customer_id, channel, intake, status, currency_id, location_id, location_name, confirmed_at, created_at, split_from_id, split_reason,
                         ship_to_company, ship_to_contact, ship_to_phone, ship_to_line1, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country)
  values (p_number, current_setting('fcl.c_a')::uuid, 'warehouse', p_intake, 'packed', current_setting('fcl.cad')::uuid, current_setting('fcl.wh')::uuid, 'FCL Warehouse',
          now() - make_interval(days => p_days + 1), now() - make_interval(days => p_days), p_split_from, case when p_split_from is null then null else 'stock_short' end,
          'FCL Alpha Corp', 'Alpha Buyer', '4165550101', '100 Fcl Street', 'Toronto', 'ON', 'M5V 1A1', 'Canada')
  returning id into v_so;
  insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered) select v_so, 1, p.id, p.sku, 1, 2 from public.product p where p.is_active order by p.sku limit 1;
  return v_so;
end $$;
-- 상자 하나(치수 · 무게 전부) — 트리거(wms_pallet_dims)를 켜고 넣는다
create function pg_temp.mk_unit(p_so uuid, p_label text) returns bigint language plpgsql as $$
declare v_id bigint;
begin
  insert into public.wms_pallets (order_id, label, unit_type, status, dim_length, dim_width, dim_height, dim_unit, weight, weight_unit) values (p_so, p_label, 'box', 'completed', 12, 10, 8, 'in', 23, 'lb') returning id into v_id;
  insert into public.wms_pallet_items (pallet_id, order_id, qty_base) values (v_id, p_so, 2);
  return v_id;
end $$;
-- 가짜 Shopify 오더 짝(원래 SO 에만 · 형제에는 없다 — 실물과 같다)
create function pg_temp.mk_web(p_so uuid, p_store uuid, p_name text, p_num bigint) returns uuid language plpgsql as $$
declare v_o uuid;
begin
  insert into public.shop_order (store_id, shopify_order_gid, name, raw, status, customer_id, location_id, so_id, processed_at, is_test)
  values (p_store, 'gid://shopify/Order/' || p_num, p_name, jsonb_build_object('id', 'gid://shopify/Order/' || p_num, 'name', p_name), 'created', current_setting('fcl.c_a')::uuid, current_setting('fcl.wh')::uuid, p_so, now(), true)
  returning id into v_o;
  return v_o;
end $$;
select pg_temp.mk_so('SO-79910', 'shopify', null, 3)::text as a \gset
select pg_temp.mk_so('SO-79910b', 'shopify', :'a'::uuid, 2)::text as b \gset
select pg_temp.mk_so('SO-79910c', 'shopify', :'b'::uuid, 1)::text as c \gset
select pg_temp.mk_so('SO-79911', 'shopify', null, 3)::text as x \gset
select pg_temp.mk_so('SO-79911a', 'shopify', :'x'::uuid, 2)::text as y \gset
select pg_temp.mk_so('SO-79912', 'manual', null, 1)::text as z \gset
select pg_temp.mk_so('SO-79913', 'shopify', null, 2)::text as m \gset
select pg_temp.mk_so('SO-79913a', 'shopify', :'m'::uuid, 1)::text as m1 \gset
select pg_temp.mk_so('SO-79914', 'shopify', null, 3)::text as r \gset
select set_config('fcl.r', :'r', true) \gset
-- 깊이 사슬: r ← d1 ← d2 ← … ← d50 (dN 에서 r 까지 N + 1 노드)
create temp table t_chain (n int, id uuid);
do $$
declare v_prev uuid := current_setting('fcl.r')::uuid; v_id uuid; i int;
begin
  for i in 1..50 loop
    v_id := pg_temp.mk_so('SO-79914' || repeat('a', i), 'shopify', v_prev, 1);
    insert into t_chain values (i, v_id);
    v_prev := v_id;
  end loop;
end $$;
select pg_temp.mk_web(:'a'::uuid, :'st_aone'::uuid, '#FCL-A', 7999100001)::text as w_a \gset
select pg_temp.mk_web(:'x'::uuid, :'st_asung'::uuid, '#FCL-X', 7999100002)::text as w_x \gset
select pg_temp.mk_web(:'r'::uuid, :'st_aone'::uuid, '#FCL-R', 7999100003)::text as w_r \gset
set local session_replication_role = origin;
select pg_temp.mk_unit(:'a'::uuid, 'BA'), pg_temp.mk_unit(:'b'::uuid, 'BB'), pg_temp.mk_unit(:'c'::uuid, 'BC'), pg_temp.mk_unit(:'x'::uuid, 'BX'), pg_temp.mk_unit(:'y'::uuid, 'BY'), pg_temp.mk_unit(:'z'::uuid, 'BZ'), pg_temp.mk_unit(:'m'::uuid, 'BM'), pg_temp.mk_unit(:'m1'::uuid, 'BM1');
select pg_temp.chkb('F0 fake material: warehouse FCL · office staff (sales · master) · customer · address · stores aone + asung (inactive · not live) · SO a ← b ← c (aone web order on a only) · x ← y (asung on x only) · z manual · m ← m1 (shopify intake · no web order) · r ← d1 … d50 (aone on r) · boxes on 8',
  :'wh' <> '' and :'u_off' <> '' and :'st_aone' <> '' and :'st_asung' <> '' and (select count(*) from t_chain) = 50
  and (select count(*) from public.so where so_number like 'SO-7991%') = 59 and (select count(*) from public.shop_order where name like '#FCL-%') = 3
  and (select count(*) from public.wms_pallets where label like 'B%' and order_id in (select id from public.so where so_number like 'SO-7991%')) = 8, 'see F0');

-- ── A) freight_locked — aone 은 사슬 전체 · asung 은 473 그대로 ──
select pg_temp.as_user(:'u_off');
select pg_temp.chk('A1 aone root a alone → locked · reason customer paid freight in Shopify (#FCL-A) (as before)', pg_temp.lock(array[:'a'::uuid]), 'true/customer paid freight in Shopify (#FCL-A)');
select pg_temp.chk('A2 aone sibling b alone (split_from a) → locked · same reason (was false before fc-lock-1)', pg_temp.lock(array[:'b'::uuid]), 'true/customer paid freight in Shopify (#FCL-A)');
select pg_temp.chk('A3 aone grandchild c alone (c ← b ← a) → locked · same reason', pg_temp.lock(array[:'c'::uuid]), 'true/customer paid freight in Shopify (#FCL-A)');
select pg_temp.chk('A4 asung sibling y (x ← y · asung web order) → not locked (473 unchanged)', pg_temp.lock(array[:'y'::uuid]), 'false/(null)');
select pg_temp.chk('A5 manual order z (no web order) → not locked', pg_temp.lock(array[:'z'::uuid]), 'false/(null)');
select pg_temp.chk('A6 a + b in one shipment → locked · the order name once (distinct)', pg_temp.lock(array[:'a'::uuid, :'b'::uuid]), 'true/customer paid freight in Shopify (#FCL-A)');
select pg_temp.chk('A7 shopify-intake sibling m1 whose chain has no web order → not locked (unchanged · the lock never looked at intake)', pg_temp.lock(array[:'m1'::uuid]), 'false/(null)');
select pg_temp.chk('A8 asung root x alone → not locked (unchanged)', pg_temp.lock(array[:'x'::uuid]), 'false/(null)');

-- ── B) so_charge_gate via so_charge_set — packed · sales + master ──
select pg_temp.chk('B1 packed aone sibling b → refused: came from aonebeauty (error text unchanged)', pg_temp.try(format('select public.so_charge_set(%L::uuid, ''Packing'', 5)::text', :'b')),
  'ERR P0001: Order SO-79910b came from aonebeauty and was paid at checkout — charges cannot change after packing — nothing was saved');
select pg_temp.try(format('select public.so_charge_set(%L::uuid, ''Packing'', 5)::text', :'y')) as b2 \gset
select pg_temp.chkb('B2 packed asung sibling y → not refused (before fc-lock-1 the gate said "store is unknown" — the sibling has intake shopify but no shop_order row) · returns the order', :'b2' not like 'ERR %' and :'b2' like '%SO-79911a%', left(:'b2', 80));
select pg_temp.chk('B3 packed shopify-intake sibling m1 whose chain has no web order → refused: store is unknown (549 unchanged · now judged on the chain)', pg_temp.try(format('select public.so_charge_set(%L::uuid, ''Packing'', 5)::text', :'m1')),
  'ERR P0001: Order SO-79913a is a Shopify order but its store is unknown — nothing was saved');
select pg_temp.chk('B4 packed aone root a → refused as before', pg_temp.try(format('select public.so_charge_set(%L::uuid, ''Packing'', 5)::text', :'a')),
  'ERR P0001: Order SO-79910 came from aonebeauty and was paid at checkout — charges cannot change after packing — nothing was saved');
select pg_temp.try(format('select public.so_charge_set(%L::uuid, ''Packing'', 5)::text', :'x')) as b5 \gset
select pg_temp.chkb('B5 packed asung root x → not refused as before', :'b5' not like 'ERR %' and :'b5' like '%SO-79911%', left(:'b5', 80));
select pg_temp.chk('B6 packed aone grandchild c → refused: came from aonebeauty', pg_temp.try(format('select public.so_charge_set(%L::uuid, ''Packing'', 5)::text', :'c')),
  'ERR P0001: Order SO-79910c came from aonebeauty and was paid at checkout — charges cannot change after packing — nothing was saved');

-- ── G) so_chain_shop_orders — 직접 · 순환 · 깊이 ──
select pg_temp.chk('G1 chain(c) = 1 row #FCL-A:aone · chain(y) = 1 row #FCL-X:asung · chain(z) = 0 · chain(m1) = 0 · chain(a) = itself', pg_temp.chain(:'c'::uuid) || ' | ' || pg_temp.chain(:'y'::uuid) || ' | ' || pg_temp.chain(:'z'::uuid) || ' | ' || pg_temp.chain(:'m1'::uuid) || ' | ' || pg_temp.chain(:'a'::uuid),
  '1/#FCL-A:aone | 1/#FCL-X:asung | 0/(none) | 0/(none) | 1/#FCL-A:aone');
-- 순환: a.split_from_id = c 로 묶어(replica · 서브트랜잭션 안 · 되돌린다) c 에서 올라가면 c → b → a → (c 는 path 에 있다) 멈춘다 · a 의 오더 한 번
create function pg_temp.cycle_probe() returns text language plpgsql as $$
declare v text;
begin
  execute 'set local session_replication_role = replica';
  update public.so set split_from_id = current_setting('fcl.c')::uuid, split_reason = 'manual' where id = current_setting('fcl.a')::uuid;
  v := pg_temp.chain(current_setting('fcl.c')::uuid) || ' | ' || pg_temp.lock(array[current_setting('fcl.c')::uuid]);
  raise exception using errcode = 'P7777', message = v;
exception when sqlstate 'P7777' then return sqlerrm;
          when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
select set_config('fcl.a', :'a', true), set_config('fcl.c', :'c', true) \gset
select pg_temp.chk('G2 cycle a ← b ← c ← a (rolled back) → chain(c) still 1 row · lock(c) still true · no hang', pg_temp.cycle_probe(), '1/#FCL-A:aone | true/customer paid freight in Shopify (#FCL-A)');
select pg_temp.chk('G3 depth guard 50: from d48 (49 nodes to r) found · from d49 (50 nodes) found · from d50 (51 nodes) stops → 0', pg_temp.chain((select id from t_chain where n = 48)) || ' | ' || pg_temp.chain((select id from t_chain where n = 49)) || ' | ' || pg_temp.chain((select id from t_chain where n = 50)),
  '1/#FCL-R:aone | 1/#FCL-R:aone | 0/(none)');

-- ── C) 재발행 diff — 옛(begin 앞 prosrc) = 새 대조 · 시험 갈래만 ──
\if :{?mig}
create temp table t_diff as
  with o as (select t.proname, x.l, x.n from t_pre t, regexp_split_to_table(t.prosrc, E'\n') with ordinality as x(l, n)),
       w as (select p.proname, x.l, x.n from pg_proc p, regexp_split_to_table(p.prosrc, E'\n') with ordinality as x(l, n) where p.pronamespace = 'public'::regnamespace and p.proname in ('fc_shipment_prepare', 'so_charge_gate'))
  select 'removed' as side, o.proname, o.n, o.l from o where not exists (select 1 from w where w.proname = o.proname and w.n = o.n and w.l = o.l)
  union all
  select 'added', w.proname, w.n, w.l from w where not exists (select 1 from o where o.proname = w.proname and o.n = w.n and o.l = w.l);
select pg_temp.chk('C0 begin 앞 prosrc = 두 마지막 정의(md5 · fc_1b5:39 · svc_1b:644)', (select string_agg(proname || ' ' || md5, ' · ' order by proname) from t_pre), 'fc_shipment_prepare 2a2a0206f9f2b12320dd93f6467fa8fc · so_charge_gate 12904d7f89b5db700d71087ed81523f4');
select pg_temp.chk('C1 line counts unchanged · prepare removed/added 1/1 on the same line · gate removed/added 2/2 on the same lines',
  (select bool_and(t.n_lines = array_length(string_to_array(p.prosrc, E'\n'), 1)) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname)::text || '/' ||
  (select count(*) filter (where side = 'removed') || '/' || count(*) filter (where side = 'added') || '/' || (count(distinct n) = count(*) filter (where side = 'removed'))::text from t_diff where proname = 'fc_shipment_prepare') || '/' ||
  (select count(*) filter (where side = 'removed') || '/' || count(*) filter (where side = 'added') || '/' || (count(distinct n) = count(*) filter (where side = 'removed'))::text from t_diff where proname = 'so_charge_gate'), 'true/1/1/true/2/2/true');
select pg_temp.chk('C2 prepare: the removed line is the old lock select · the added line calls so_chain_shop_orders with distinct names',
  (select string_agg(side || '=' || btrim(l), ' || ' order by side desc) from t_diff where proname = 'fc_shipment_prepare'),
  'removed=select string_agg(o.name, '', '') into v_lock_reason from public.shop_order o join public.shop_store st on st.id = o.store_id where o.so_id = any (v_ids) and st.kind = ''aone'';' ||
  ' || added=select string_agg(distinct c.order_name, '', '' order by c.order_name) into v_lock_reason from unnest(v_ids) i cross join lateral public.so_chain_shop_orders(i) c where c.store_kind = ''aone'';   -- fc-lock-1 판정 882: 갈린 형제(split_from_id 사슬)도 원래 오더로');
select pg_temp.chk('C3 gate: the two removed lines are the store-unknown and aone checks · the two added lines call so_chain_shop_orders · error lines untouched',
  (select string_agg(side || '=' || regexp_replace(btrim(l), '\s+--.*$', ''), ' || ' order by side desc, n) from t_diff where proname = 'so_charge_gate'),
  'removed=if not exists (select 1 from public.shop_order o where o.so_id = v_so.id) then || removed=if exists (select 1 from public.shop_order o join public.shop_store st on st.id = o.store_id where o.so_id = v_so.id and st.kind = ''aone'') then' ||
  ' || added=if not exists (select 1 from public.so_chain_shop_orders(v_so.id)) then || added=if exists (select 1 from public.so_chain_shop_orders(v_so.id) c where c.store_kind = ''aone'') then');
\endif

-- ── D) REST 첫 겹 — 정적: 깊이 0 의 update · delete 에 WHERE ──
select pg_temp.chk('D0 scanner self-test: no-where update 1 · where 0 · subquery-where-only 1 · with-update no-where 1 · delete no-where 1 · then-update 1 · string update 0',
  pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
  || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text, '1011110');
select pg_temp.chk('D1 new last definitions: WHERE-less update · delete = 0 for fc_shipment_prepare · so_charge_gate · so_chain_shop_orders',
  (select string_agg(proname || ' ' || pg_temp.nowhere(prosrc)::text, ' · ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_shipment_prepare', 'so_charge_gate', 'so_chain_shop_orders')),
  'fc_shipment_prepare 0 · so_chain_shop_orders 0 · so_charge_gate 0');

-- ── E) 속성 · md5 · 무접촉 ──
select pg_temp.chk('E1 so_chain_shop_orders: invoker · stable · search_path · anon no · authenticated no · service_role yes (default acl · same as so_charge_gate) · comment 882 · exactly one',
  (select prosecdef::text || '/' || provolatile::text || '/' || array_to_string(proconfig, ';') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_chain_shop_orders') || '/' ||
  has_function_privilege('anon', 'public.so_chain_shop_orders(uuid)', 'execute')::text || '/' || has_function_privilege('authenticated', 'public.so_chain_shop_orders(uuid)', 'execute')::text || '/' || has_function_privilege('service_role', 'public.so_chain_shop_orders(uuid)', 'execute')::text || '/' ||
  (coalesce(obj_description('public.so_chain_shop_orders(uuid)'::regprocedure, 'pg_proc'), '') like 'fc-lock-1 판정 882%')::text || '/' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_chain_shop_orders'),
  'false/s/search_path=public, pg_temp/false/false/true/true/1');
select pg_temp.chk('E2 reissued: fc_shipment_prepare md5 · one · authenticated yes · anon no · comment kept (fc-1a …) | so_charge_gate md5 · one · definer · authenticated no · comment 882',
  (select md5(prosrc) || '/' || count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_prepare' group by prosrc) || '/' || has_function_privilege('authenticated', 'public.fc_shipment_prepare(uuid[], jsonb, boolean)', 'execute')::text || '/' || has_function_privilege('anon', 'public.fc_shipment_prepare(uuid[], jsonb, boolean)', 'execute')::text || '/' ||
  (coalesce(obj_description('public.fc_shipment_prepare(uuid[], jsonb, boolean)'::regprocedure, 'pg_proc'), '') like 'fc-1a 판정 835%')::text || ' | ' ||
  (select md5(prosrc) || '/' || count(*) || '/' || bool_and(prosecdef)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_charge_gate' group by prosrc) || '/' || has_function_privilege('authenticated', 'public.so_charge_gate(uuid, text)', 'execute')::text || '/' ||
  (coalesce(obj_description('public.so_charge_gate(uuid, text)'::regprocedure, 'pg_proc'), '') like '%fc-lock-1 판정 882%')::text,
  'fb4a8429c7d3d11932063e56cdd71cea/1/true/false/true | 96c4226ace180c6dfa3938649d7f755a/1/true/false/true');
select pg_temp.chk('E3 untouched (md5 begin 앞 = 지금): so_charge_set · so_charge_remove · so_finalize · fc_shipment_for_so',
  (select md5(prosrc) = :'set_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_charge_set')::text || '/' || (select md5(prosrc) = :'rem_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_charge_remove')::text || '/' ||
  (select md5(prosrc) = :'fin_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize')::text || '/' || (select md5(prosrc) = :'forso_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_for_so')::text, 'true/true/true/true');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
select case when (select count(*) from public.so) = :n_so0 and (select count(*) from public.so_line) = :n_line0 and (select count(*) from public.so_charge) = :n_ch0 and (select count(*) from public.customer) = :n_cust0
            and (select count(*) from public.customer_address) = :n_addr0 and (select count(*) from public.wms_pallets) = :n_unit0 and (select count(*) from public.ims_staff) = :n_staff0 and (select count(*) from public.ref_warehouse) = :n_wh0
            and (select count(*) from public.shop_store) = :n_store0 and (select count(*) from public.shop_order) = :n_web0 and (select count(*) from public.fc_shipment) = :n_fc0
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_prepare') = :'prep_md5_0'
             and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_charge_gate') = :'gate_md5_0'
             and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_chain_shop_orders') = :n_chain0
       then 'Z2 OK functions back to before (prepare · gate md5 · so_chain_shop_orders count)' else 'Z2 MISMATCH functions not restored' end as z2;
\endif
