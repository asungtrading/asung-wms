-- supabase/tests/wun_1_check.sql — wun-1 오피스 발송 유닛 더하기 · 빼기 창구(wms_unit_add · wms_unit_remove) 검증 (2026-10-29 · 판정 881)
-- [테스트 · Asung-IMS] 시험 적용 장치 — db_role = test 가드 → 기준(begin 앞: 함수 md5 · 표 수 · identity 시퀀스) → begin → (-v mig 면 \i) → 가짜(직원 셋 · 손님 · SO 아홉 · 유닛 · 발송 · 예약 — 전부 rollback) → T1~T9 → rollback → Z
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261029235000_wun_1_office_units.sql -f supabase/tests/wun_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) EXPECT_OK 는 파일 끝 합계 표의 expect_ok · M1(begin 앞에 새 함수가 없었다)은 시험 갈래만 · Z1 은 t_res 밖 한 줄
--   ⚠️ 번호 시퀀스(so · 인보이스)는 안 당긴다 — SO 번호는 직접(SO-79971 ~ 79979) · wms_pallets · wms_pallet_items 의 identity 시퀀스는 insert 시험으로 올라간다(번호 시퀀스가 아니다 · fc 시험도 같다) — 전후 값을 끝에 찍는다
--   잠금 규칙: 기준값은 begin 앞 · lock_timeout 3s · begin ~ rollback 시간을 끝에 찍는다 · 안의 쓰기는 가짜 행뿐
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
  select p.proname, md5(p.prosrc) as md5, p.proacl::text as acl, p.prosecdef, coalesce(obj_description(p.oid, 'pg_proc'), '') as cmt
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('wms_unit_dims_set', 'wms_so_handoff', 'fc_units_snapshot', 'fc_shipment_for_so', 'wms_finalize', 'fc_shipment_prepare', 'fc_book_prepare', 'wms_rollback',
                     'wms_unit_add', 'wms_unit_remove', 'wms_unit_booking_gate', 'wms_unit_counts_refresh');
select (select count(*) from t_pre where proname in ('wms_unit_add', 'wms_unit_remove', 'wms_unit_booking_gate', 'wms_unit_counts_refresh')) as fn_n0 \gset
select (select count(*) from public.wms_pallets) as w_pal, (select count(*) from public.wms_pallet_items) as w_item, (select count(*) from public.so) as w_so, (select count(*) from public.ims_staff) as w_staff,
       (select count(*) from public.customer) as w_cust, (select count(*) from public.fc_shipment) as w_ship, (select count(*) from public.fc_booking) as w_book, (select count(*) from public.wms_order_finalize) as w_fin,
       (select count(*) from public.so_line) as w_line \gset
select last_value as pal_seq0, is_called as pal_seq0_called from public.wms_pallets_id_seq \gset
select last_value as item_seq0, is_called as item_seq0_called from public.wms_pallet_items_id_seq \gset
\echo '── 기준: wms_pallets' :w_pal '· items' :w_item '· so' :w_so '· staff' :w_staff '· customer' :w_cust '· fc_shipment' :w_ship '· fc_booking' :w_book '· finalize' :w_fin '· so_line' :w_line '· new fns present' :fn_n0 '· wms_pallets_id_seq' :pal_seq0 :pal_seq0_called '· items_id_seq' :item_seq0 :item_seq0_called
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
-- safeupdate 의 규칙을 정적으로 센다(cdc_1_check.sql · qbo_1c_check.sql · ar_2b_check.sql 의 것 그대로)
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
-- 창구를 화면처럼 부른다(authenticated 역할 · 가짜 직원 uid) · 결과는 jsonb 글자 · 예외는 'ERR <sqlstate>: <문장>'
create function pg_temp.ua(p_uid text, p_so text, p_type text, p_l numeric, p_w numeric, p_h numeric, p_wt numeric, p_n int, p_du text default 'in', p_wu text default 'lb') returns text language plpgsql as $$
declare v text;
begin
  perform pg_temp.as_user(p_uid);
  execute 'set local role authenticated';
  execute format('select public.wms_unit_add(%L, %L, %L, %L, %L, %L, %L, %L, %L)::text', p_so::uuid, p_type, p_l, p_w, p_h, p_wt, p_n, p_du, p_wu) into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then reset role; return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.ur(p_uid text, p_so text, p_unit bigint) returns text language plpgsql as $$
declare v text;
begin
  perform pg_temp.as_user(p_uid);
  execute 'set local role authenticated';
  execute format('select public.wms_unit_remove(%L, %L)::text', p_so::uuid, p_unit) into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then reset role; return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 그 오더의 유닛을 한 줄로(id 순): label:LxWxH/wt/dim_unit/weight_unit/status/parent/created_by = 가짜 sales 직원
create function pg_temp.units(p_so text, p_staff text) returns text language sql as $$
  select coalesce(string_agg(u.label || ':' || coalesce(u.length_in::text, '-') || 'x' || coalesce(u.width_in::text, '-') || 'x' || coalesce(u.height_in::text, '-') || '/' || coalesce(u.weight_lb::text, '-')
                             || '/' || coalesce(u.dim_unit, '-') || '/' || coalesce(u.weight_unit, '-') || '/' || u.status || '/' || coalesce(u.parent_id::text, '-') || '/' || (u.created_by::text = p_staff)::text, ' · ' order by u.id), '(none)')
  from public.wms_pallets u where u.order_id = p_so::uuid;
$$;
create function pg_temp.fin(p_so text) returns text language sql as $$
  select coalesce((select f.fulfillment_type || '/' || f.units || '/' || f.units_without_dims || '/' || (f.finalized_at < now())::text from public.wms_order_finalize f where f.order_id = p_so::uuid), '(no row)');
$$;

-- ── 가짜(replica · WUN1-): 직원 셋 · 손님 · SO 아홉(번호 직접) · Finalize 기록 둘 ──
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh from public.ref_warehouse where is_active order by (name like 'Asung Trading%') desc, name limit 1 \gset
select id::text as prod, sku as prod_sku from public.product where is_active order by sku limit 1 \gset
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'wun1-sales@test.invalid', 'WUN1 Sales', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as u_sales, id::text as st_sales \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'wun1-picker@test.invalid', 'WUN1 Picker', 'worker', '["wms","picking"]', '{}') returning auth_user_id::text as u_pick \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'wun1-wms@test.invalid', 'WUN1 Warehouse', 'worker', '["wms","fulfillment"]', array[:'wh'::uuid]) returning auth_user_id::text as u_wms, id::text as st_wms \gset
insert into public.customer (name, source, currency_id, price_tier) values ('WUN1 Co', 'manual', :'cad'::uuid, 'Wholesale') returning id::text as cust \gset
create function pg_temp.mk_so(p_n int, p_status text) returns uuid language plpgsql as $$
declare v_so uuid;
begin
  insert into public.so (so_number, customer_id, channel, intake, status, currency_id, location_id, location_name, confirmed_at, created_at, closed_at, closed_reason)
  values ('SO-7997' || p_n::text, current_setting('wun1.cust')::uuid, 'warehouse', 'manual', p_status, current_setting('wun1.cad')::uuid, current_setting('wun1.wh')::uuid, 'WUN1 Warehouse',
          case when p_status = 'draft' then null else now() - interval '2 day' end, now() - interval '3 day',
          case when p_status in ('fulfilled', 'cancelled') then now() - interval '1 day' end, case when p_status = 'cancelled' then 'voided' end)
  returning id into v_so;
  insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered) values (v_so, 1, current_setting('wun1.prod')::uuid, current_setting('wun1.sku'), 1, 2);
  return v_so;
end $$;
select set_config('wun1.cad', :'cad', true), set_config('wun1.wh', :'wh', true), set_config('wun1.cust', :'cust', true), set_config('wun1.prod', :'prod', true), set_config('wun1.sku', :'prod_sku', true) \gset
select pg_temp.mk_so(1, 'packed')::text as s1, pg_temp.mk_so(2, 'packed')::text as s2, pg_temp.mk_so(3, 'picking')::text as s3, pg_temp.mk_so(4, 'draft')::text as s4, pg_temp.mk_so(5, 'confirmed')::text as s5,
       pg_temp.mk_so(6, 'at_wms')::text as s6, pg_temp.mk_so(7, 'fulfilled')::text as s7, pg_temp.mk_so(8, 'shipped')::text as s8, pg_temp.mk_so(9, 'cancelled')::text as s9 \gset
select l.id::text as s2_line from public.so_line l where l.so_id = :'s2'::uuid \gset
insert into public.wms_order_finalize (order_id, fulfillment_type, finalized_by, finalized_at, units, units_without_dims) values (:'s1'::uuid, 'direct', :'st_wms'::uuid, now() - interval '1 hour', 0, 0);
insert into public.wms_order_finalize (order_id, fulfillment_type, finalized_by, finalized_at, units, units_without_dims) values (:'s2'::uuid, 'packing_list', :'st_wms'::uuid, now() - interval '1 hour', 2, 1);
set local session_replication_role = origin;
-- 창고 화면이 만든 모양의 유닛(wms-fulfillment.html addUnit:1440 과 같은 칸 · 트리거 켠 채): s2 = B1(담김 · 치수) + B5(빈 · 치수 없음 · 번호 틈) · s3 = P1 + 그 위 B1(빈)
insert into public.wms_pallets (order_id, unit_type, label, parent_id, status, created_by, dim_length, dim_width, dim_height, dim_unit, weight, weight_unit) values (:'s2'::uuid, 'box', 'B1', null, 'building', :'st_wms'::uuid, 12, 10, 8, 'in', 23, 'lb') returning id::text as s2_b1 \gset
insert into public.wms_pallet_items (pallet_id, order_id, order_line_id, qty_base) values (:'s2_b1'::bigint, :'s2'::uuid, :'s2_line'::uuid, 2);
insert into public.wms_pallets (order_id, unit_type, label, parent_id, status, created_by) values (:'s2'::uuid, 'box', 'B5', null, 'building', :'st_wms'::uuid) returning id::text as s2_b5 \gset
insert into public.wms_pallets (order_id, unit_type, label, parent_id, status, created_by) values (:'s3'::uuid, 'pallet', 'P1', null, 'building', :'st_wms'::uuid) returning id::text as s3_p1 \gset
insert into public.wms_pallets (order_id, unit_type, label, parent_id, status, created_by) values (:'s3'::uuid, 'box', 'B1', :'s3_p1'::bigint, 'building', :'st_wms'::uuid) returning id::text as s3_b1 \gset
-- T8 재료: 원장 · 예약 · 인보이스 · so_line 의 지문(시험 전)
select (select count(*) from public.inv_ledger) as led0, (select count(*) from public.so_reserve) as res0, (select count(*) from public.so_invoice) as inv0,
       (select md5(string_agg(l::text, '|' order by l.id)) from public.so_line l where l.so_id in (:'s1'::uuid, :'s2'::uuid, :'s3'::uuid)) as line0 \gset

-- ── S0 스캐너 자기 시험 ──
select pg_temp.chk('S0 scanner self-test: no-where update 1 · where 0 · subquery-where-only 1 · with-update no-where 1 · delete no-where 1 · then-update 1 · string update 0 · where singleton 0',
  pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
  || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text
  || pg_temp.nowhere('update t set a = 1 where singleton returning * into v;')::text, '10111100');

-- ── T1 유닛 0 인 packed 오더(s1)에 박스 3 개 ──
select pg_temp.ua(:'u_sales', :'s1', 'box', 17, 12, 13, 22, 3) as r1 \gset
select pg_temp.chk('T1a add 3 boxes to a finalized order with no units → added 3 · labels B1 B2 B3 · unit_type box · no shipment → shipment_status null · units_changed false · units[0] in/lb as given',
  concat_ws('/', coalesce((pg_temp.j(:'r1')->>'added'), :'r1'), (pg_temp.j(:'r1')->'labels')::text, pg_temp.j(:'r1')->>'unit_type', coalesce(pg_temp.j(:'r1')->>'shipment_status', '(null)'), pg_temp.j(:'r1')->>'units_changed',
            (pg_temp.j(:'r1')->'units'->0->>'length_in') || 'x' || (pg_temp.j(:'r1')->'units'->0->>'width_in') || 'x' || (pg_temp.j(:'r1')->'units'->0->>'height_in') || '/' || (pg_temp.j(:'r1')->'units'->0->>'weight_lb'), jsonb_array_length(pg_temp.j(:'r1')->'unit_ids')::text),
  '3/["B1", "B2", "B3"]/box/(null)/false/17.00x12.00x13.00/22.00/3');
select pg_temp.chk('T1b rows: three boxes · in · lb stored by the trigger · dim_unit in · weight_unit lb · status building · parent null · created_by = the sales staff',
  pg_temp.units(:'s1', :'st_sales'),
  'B1:17.00x12.00x13.00/22.00/in/lb/building/-/true · B2:17.00x12.00x13.00/22.00/in/lb/building/-/true · B3:17.00x12.00x13.00/22.00/in/lb/building/-/true');
select pg_temp.chk('T1c column shape = a warehouse-made unit (same keys · same non-dimension values: status · notes · completed_at · parent · transfer_id)',
  (select ((to_jsonb(o) - 'id' - 'created_at' - 'label' - 'order_id' - 'created_by' - 'dim_length' - 'dim_width' - 'dim_height' - 'dim_unit' - 'weight' - 'weight_unit' - 'length_in' - 'width_in' - 'height_in' - 'weight_lb')
             = (to_jsonb(w) - 'id' - 'created_at' - 'label' - 'order_id' - 'created_by' - 'dim_length' - 'dim_width' - 'dim_height' - 'dim_unit' - 'weight' - 'weight_unit' - 'length_in' - 'width_in' - 'height_in' - 'weight_lb'))::text
          || '/' || ((select array_agg(k order by k) from jsonb_object_keys(to_jsonb(o)) k)::text = (select array_agg(k order by k) from jsonb_object_keys(to_jsonb(w)) k)::text)::text
     from public.wms_pallets o, public.wms_pallets w where o.order_id = :'s1'::uuid and o.label = 'B1' and w.id = :'s2_b5'::bigint), 'true/true');
select public.wms_so_handoff(:'s1'::uuid) as h1 \gset
select pg_temp.chk('T1d wms_so_handoff(s1) reads the three (labels · unit_type · dims · items []) · units_without_dims 0',
  (select string_agg((e->>'label') || ':' || (e->>'unit_type') || ':' || (e->>'length_in') || '/' || (e->>'weight_lb') || ':' || (e->'items')::text, ' · ' order by (e->>'unit_id')::bigint) from jsonb_array_elements(pg_temp.j(:'h1')->'units') e)
  || ' | ' || (pg_temp.j(:'h1')->>'units_without_dims'), 'B1:box:17.00/22.00:[] · B2:box:17.00/22.00:[] · B3:box:17.00/22.00:[] | 0');
select pg_temp.chk('T1e fc_units_snapshot([s1]) = the three top-level units · pieces 0',
  (select string_agg((e->>'label') || ':' || (e->>'unit_type') || ':' || (e->>'pieces'), ' · ' order by (e->>'unit_id')::bigint) from jsonb_array_elements(public.fc_units_snapshot(array[:'s1'::uuid])) e), 'B1:box:0 · B2:box:0 · B3:box:0');
select pg_temp.chk('T1f wms_order_finalize(s1) recounted: units 3 · without_dims 0 · fulfillment_type · finalized_at untouched', pg_temp.fin(:'s1'), 'direct/3/0/true');

-- ── T2 창고 유닛이 있는 오더(s2: B1 담김 · B5 빈) → B6 부터(최대 + 1 · 틈을 다시 쓰지 않는다) · cm · kg 변환 · 팔렛은 섞임 거부 ──
select pg_temp.ua(:'u_sales', :'s2', 'box', 30, 25, 20, 10, 1, 'cm', 'kg') as r2 \gset
select pg_temp.chk('T2a add 1 box (cm · kg) next to warehouse B1 · B5 → label B6 (max + 1, like nextUnitLabel) · 30 cm = 11.81 in · 10 kg = 22.05 lb',
  (pg_temp.j(:'r2')->'labels')::text || '/' || (pg_temp.j(:'r2')->'units'->0->>'length_in') || '/' || (pg_temp.j(:'r2')->'units'->0->>'weight_lb') || ' | ' || pg_temp.units(:'s2', :'st_sales'),
  '["B6"]/11.81/22.05 | B1:12.00x10.00x8.00/23.00/in/lb/building/-/false · B5:-x-x-/-/-/-/building/-/false · B6:11.81x9.84x7.87/22.05/cm/kg/building/-/true');
select pg_temp.chk('T2b pallet onto a box order → refused (same meaning as fc_shipment_prepare mixes boxes and pallets) · rows untouched',
  pg_temp.ua(:'u_sales', :'s2', 'pallet', 48, 40, 50, 300, 1) || ' | ' || (select count(*)::text from public.wms_pallets u where u.order_id = :'s2'::uuid),
  'ERR P0001: Order SO-79972 already has boxes — one order is all boxes or all pallets (this shipment would mix boxes and pallets) — nothing was saved | 3');
select pg_temp.chk('T2c box onto a pallet order (s3: P1 with child box B1) → refused — top-level units decide, the child box does not make it a box order',
  pg_temp.ua(:'u_sales', :'s3', 'box', 17, 12, 13, 22, 1), 'ERR P0001: Order SO-79973 already has pallets — one order is all boxes or all pallets (this shipment would mix boxes and pallets) — nothing was saved');
select pg_temp.chk('T2d wms_order_finalize(s2) recounted after the add: units 3 (B1 · B5 · B6) · without_dims 1 (B5) · packing_list kept', pg_temp.fin(:'s2'), 'packing_list/3/1/true');

-- ── T3 picking OK · draft · confirmed · at_wms · fulfilled · shipped · cancelled 거부 ──
select pg_temp.ua(:'u_sales', :'s3', 'pallet', 48, 40, 50, 300, 2) as r3 \gset
select pg_temp.chk('T3a picking order (s3 · has P1) → 2 pallets P2 P3 · no finalize row → fin (no row)', (pg_temp.j(:'r3')->'labels')::text || ' | ' || pg_temp.fin(:'s3'), '["P2", "P3"] | (no row)');
select pg_temp.chk('T3b draft · confirmed · at_wms · fulfilled · shipped · cancelled → refused with the status in the sentence (add)',
  pg_temp.ua(:'u_sales', :'s4', 'box', 1, 1, 1, 1, 1) || ' | ' || pg_temp.ua(:'u_sales', :'s5', 'box', 1, 1, 1, 1, 1) || ' | ' || pg_temp.ua(:'u_sales', :'s6', 'box', 1, 1, 1, 1, 1) || ' | ' || pg_temp.ua(:'u_sales', :'s7', 'box', 1, 1, 1, 1, 1)
  || ' | ' || pg_temp.ua(:'u_sales', :'s8', 'box', 1, 1, 1, 1, 1) || ' | ' || pg_temp.ua(:'u_sales', :'s9', 'box', 1, 1, 1, 1, 1),
  'ERR P0001: Order SO-79974 is draft — boxes and pallets can be added only while it is Working or Finalized — nothing was saved | ERR P0001: Order SO-79975 is confirmed — boxes and pallets can be added only while it is Working or Finalized — nothing was saved | ERR P0001: Order SO-79976 is at_wms — boxes and pallets can be added only while it is Working or Finalized — nothing was saved | ERR P0001: Order SO-79977 is fulfilled — boxes and pallets can be added only while it is Working or Finalized — nothing was saved | ERR P0001: Order SO-79978 is shipped — boxes and pallets can be added only while it is Working or Finalized — nothing was saved | ERR P0001: Order SO-79979 is cancelled — boxes and pallets can be added only while it is Working or Finalized — nothing was saved');
select pg_temp.chk('T3c remove on a shipped order → refused by status before anything else · unknown order → not found',
  pg_temp.ur(:'u_sales', :'s8', :'s2_b5'::bigint) || ' | ' || pg_temp.ur(:'u_sales', '00000000-0000-4000-8000-00000000c0de', :'s2_b5'::bigint),
  'ERR P0001: Order SO-79978 is shipped — boxes and pallets can be removed only while it is Working or Finalized — nothing was saved | ERR P0001: Order 00000000-0000-4000-8000-00000000c0de not found — nothing was saved');

-- ── T4 빼기 ──
select u.id::text as s1_b1, (select id from public.wms_pallets where order_id = :'s1'::uuid and label = 'B2')::text as s1_b2 from public.wms_pallets u where u.order_id = :'s1'::uuid and u.label = 'B1' \gset
select pg_temp.ur(:'u_sales', :'s1', :'s1_b2'::bigint) as r4a \gset
select pg_temp.chk('T4a remove empty B2 of s1 → removed true · label B2 · remaining B1 · B3 keep their names · finalize recounted 2',
  concat_ws('/', coalesce(pg_temp.j(:'r4a')->>'removed', :'r4a'), pg_temp.j(:'r4a')->>'label', pg_temp.j(:'r4a')->>'unit_type', coalesce(pg_temp.j(:'r4a')->>'shipment_status', '(null)'), pg_temp.j(:'r4a')->>'units_changed')
  || ' | ' || (select string_agg(u.label, ',' order by u.id) from public.wms_pallets u where u.order_id = :'s1'::uuid) || ' | ' || pg_temp.fin(:'s1'), 'true/B2/box/(null)/false | B1,B3 | direct/2/0/true');
select pg_temp.chk('T4b warehouse B1 of s2 (1 item line packed) → refused · row and item stay',
  pg_temp.ur(:'u_sales', :'s2', :'s2_b1'::bigint) || ' | ' || (select count(*)::text from public.wms_pallet_items i where i.pallet_id = :'s2_b1'::bigint) || '/' || (select count(*)::text from public.wms_pallets u where u.id = :'s2_b1'::bigint),
  'ERR P0001: Unit B1 has 1 item line(s) packed in it — only empty units can be removed (the warehouse unpacks it) — nothing was saved | 1/1');
select pg_temp.chk('T4c a unit of another order (s1 B1 through s2) → refused · unknown unit id → not found',
  pg_temp.ur(:'u_sales', :'s2', :'s1_b1'::bigint) || ' | ' || pg_temp.ur(:'u_sales', :'s2', 999999999),
  'ERR P0001: Unit ' || :'s1_b1' || ' (B1) belongs to another order — nothing was saved | ERR P0001: Unit 999999999 not found — nothing was saved');
select pg_temp.ur(:'u_sales', :'s3', :'s3_p1'::bigint) as r4d1 \gset
select pg_temp.ur(:'u_sales', :'s3', :'s3_b1'::bigint) as r4d2 \gset
select pg_temp.ur(:'u_sales', :'s3', :'s3_p1'::bigint) as r4d3 \gset
select pg_temp.chk('T4d pallet with a child box → refused · the empty child box can be removed · then the pallet · P2 · P3 keep their names',
  :'r4d1' || ' | ' || coalesce(pg_temp.j(:'r4d2')->>'label', :'r4d2') || '/' || coalesce(pg_temp.j(:'r4d3')->>'label', :'r4d3') || ' | ' || (select string_agg(u.label, ',' order by u.id) from public.wms_pallets u where u.order_id = :'s3'::uuid),
  'ERR P0001: Unit P1 has 1 box(es) on it — remove or move them first — nothing was saved | B1/P1 | P2,P3');
select pg_temp.ua(:'u_sales', :'s1', 'box', 17, 12, 13, 22, 1) as r4e \gset
select pg_temp.chk('T4e add again after removing B2 → B4 (max + 1 · B2 is not reused · same as the warehouse rule)', (pg_temp.j(:'r4e')->'labels')::text || ' | ' || (select string_agg(u.label, ',' order by u.id) from public.wms_pallets u where u.order_id = :'s1'::uuid), '["B4"] | B1,B3,B4');

-- ── T5 견적을 고른 뒤(살아 있는 발송 selected) 더하기 → units_changed · 예약 booked → 거부 · pending 10 분 안 → 거부 · 10 분 넘은 pending → 통과 ──
set local session_replication_role = replica;
insert into public.fc_shipment (status, origin_warehouse_id, packaging_type, charge_so_id, customer_id, origin, destination, options, units, request, payload_hash, created_in, created_by)
  values ('selected', :'wh'::uuid, 'package', :'s1'::uuid, :'cust'::uuid, '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, public.fc_units_snapshot(array[:'s1'::uuid]), '{}'::jsonb, 'wun1', 'office', :'st_sales'::uuid) returning id::text as sh \gset
insert into public.fc_shipment_so (shipment_id, so_id, live) values (:'sh'::uuid, :'s1'::uuid, true);
set local session_replication_role = origin;
select pg_temp.as_user(:'u_sales');
select (public.fc_shipment_for_so(:'s1'::uuid)->>'units_changed') as uc0 \gset
select pg_temp.ua(:'u_sales', :'s1', 'box', 17, 12, 13, 22, 1) as r5a \gset
select pg_temp.as_user(:'u_sales');
select (public.fc_shipment_for_so(:'s1'::uuid)->>'units_changed') as uc1 \gset
select pg_temp.chk('T5a live shipment selected (quote chosen): units_changed false before · add B5 → ok · shipment_status selected · units_changed true in the result and in fc_shipment_for_so (the existing quote-again path)',
  :'uc0' || ' | ' || (pg_temp.j(:'r5a')->'labels')::text || '/' || (pg_temp.j(:'r5a')->>'shipment_status') || '/' || (pg_temp.j(:'r5a')->>'units_changed') || ' | ' || :'uc1', 'false | ["B5"]/selected/true | true');
select u.id::text as s1_b5 from public.wms_pallets u where u.order_id = :'s1'::uuid and u.label = 'B5' \gset
set local session_replication_role = replica;
update public.fc_shipment set status = 'booked' where id = :'sh'::uuid;
insert into public.fc_booking (shipment_id, attempt, unique_id, status, freightcom_shipment_id, booked_at, requested_by) values (:'sh'::uuid, 1, :'sh', 'booked', 'WUN1-FC-1', now(), :'st_sales'::uuid);
set local session_replication_role = origin;
select pg_temp.chk('T5b shipment booked → add refused · remove refused (cancel the booking first) · rows untouched',
  pg_temp.ua(:'u_sales', :'s1', 'box', 17, 12, 13, 22, 1) || ' | ' || pg_temp.ur(:'u_sales', :'s1', :'s1_b5'::bigint) || ' | ' || (select string_agg(u.label, ',' order by u.id) from public.wms_pallets u where u.order_id = :'s1'::uuid),
  'ERR P0001: Shipment for SO-79971 is booked — cancel the booking first, then change the boxes or pallets — nothing was saved | ERR P0001: Shipment for SO-79971 is booked — cancel the booking first, then change the boxes or pallets — nothing was saved | B1,B3,B4,B5');
set local session_replication_role = replica;
update public.fc_booking set status = 'cancelled', cancelled_at = now() where shipment_id = :'sh'::uuid and attempt = 1;
update public.fc_shipment set status = 'selected' where id = :'sh'::uuid;
insert into public.fc_booking (shipment_id, attempt, unique_id, status, requested_at, requested_by) values (:'sh'::uuid, 2, :'sh' || '-2', 'pending', now(), :'st_sales'::uuid);
set local session_replication_role = origin;
select pg_temp.ua(:'u_sales', :'s1', 'box', 17, 12, 13, 22, 1) as r5c1 \gset
select pg_temp.ur(:'u_sales', :'s1', :'s1_b5'::bigint) as r5c2 \gset
set local session_replication_role = replica;
update public.fc_booking set requested_at = now() - interval '11 minutes' where shipment_id = :'sh'::uuid and attempt = 2;
set local session_replication_role = origin;
select pg_temp.ur(:'u_sales', :'s1', :'s1_b5'::bigint) as r5c3 \gset
select pg_temp.chk('T5c booking attempt pending (fresh) → add · remove refused (in progress) · pending older than 10 min (abandoned · fc_book_prepare line) → remove B5 ok · units_changed true',
  :'r5c1' || ' | ' || :'r5c2' || ' | ' || coalesce(pg_temp.j(:'r5c3')->>'label', :'r5c3') || '/' || (pg_temp.j(:'r5c3')->>'units_changed'),
  'ERR P0001: A booking attempt (#2) for SO-79971 is still in progress — use Check again or wait a few minutes — nothing was saved | ERR P0001: A booking attempt (#2) for SO-79971 is still in progress — use Check again or wait a few minutes — nothing was saved | B5/true');

-- ── T6 입력 거부 · 권한 ──
select pg_temp.chk('T6a count 0 · 21 · null-ish → refused · length 0 · weight negative → refused · type crate · size unit ft · weight unit g → refused',
  pg_temp.ua(:'u_sales', :'s1', 'box', 1, 1, 1, 1, 0) || ' | ' || pg_temp.ua(:'u_sales', :'s1', 'box', 1, 1, 1, 1, 21) || ' | ' || pg_temp.ua(:'u_sales', :'s1', 'box', 0, 1, 1, 1, 1) || ' | ' || pg_temp.ua(:'u_sales', :'s1', 'box', 1, 1, 1, -1, 1)
  || ' | ' || pg_temp.ua(:'u_sales', :'s1', 'crate', 1, 1, 1, 1, 1) || ' | ' || pg_temp.ua(:'u_sales', :'s1', 'box', 1, 1, 1, 1, 1, 'ft', 'lb') || ' | ' || pg_temp.ua(:'u_sales', :'s1', 'box', 1, 1, 1, 1, 1, 'in', 'g'),
  'ERR P0001: Count 0 is out of range — add 1 to 20 units at a time — nothing was saved | ERR P0001: Count 21 is out of range — add 1 to 20 units at a time — nothing was saved | ERR P0001: Length, width, height and weight must all be greater than 0 — nothing was saved | ERR P0001: Length, width, height and weight must all be greater than 0 — nothing was saved | ERR P0001: Unit type "crate" is not box or pallet — nothing was saved | ERR P0001: Size unit "ft" is not in or cm — nothing was saved | ERR P0001: Weight unit "g" is not lb or kg — nothing was saved');
select pg_temp.chk('T6b picking-only staff → refused by ims_require_write(sales) (add · remove) · fulfillment staff of that warehouse → refused too (881 ⑤ sales only)',
  pg_temp.ua(:'u_pick', :'s1', 'box', 1, 1, 1, 1, 1) || ' | ' || pg_temp.ur(:'u_pick', :'s1', :'s1_b1'::bigint) || ' | ' || pg_temp.ua(:'u_wms', :'s1', 'box', 1, 1, 1, 1, 1),
  'ERR P0001: You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved | ERR P0001: You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved | ERR P0001: You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved');
select pg_temp.chk('T6c acl: add · remove = authenticated yes · anon no · service_role no · no public grant · definer · search_path pinned; gate · refresh = authenticated no',
  (select string_agg(p.proname || ':' || has_function_privilege('authenticated', p.oid, 'execute')::text || has_function_privilege('anon', p.oid, 'execute')::text || has_function_privilege('service_role', p.oid, 'execute')::text
                     || (p.proacl::text !~ '^\{=')::text || p.prosecdef::text || (array_to_string(p.proconfig, ',') ~ 'search_path=public, pg_temp')::text, ' · ' order by p.proname)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_unit_add', 'wms_unit_remove', 'wms_unit_booking_gate', 'wms_unit_counts_refresh')),
  'wms_unit_add:truefalsefalsetruetruetrue · wms_unit_booking_gate:falsefalsefalsetruetruetrue · wms_unit_counts_refresh:falsefalsefalsetruetruetrue · wms_unit_remove:truefalsefalsetruetruetrue');
select pg_temp.chk('T6d signatures as the screen will call them',
  (select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ' · ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_unit_add', 'wms_unit_remove')),
  'wms_unit_add(p_so_id uuid, p_type text, p_length numeric, p_width numeric, p_height numeric, p_weight numeric, p_count integer, p_dim_unit text, p_weight_unit text) · wms_unit_remove(p_so_id uuid, p_unit_id bigint)');

-- ── T7 같은 트랜잭션 안 두 번 연달아 더하기(s3: P2 · P3 있음) → 이름이 겹치지 않는다 · so 행 잠금 줄 ──
select pg_temp.ua(:'u_sales', :'s3', 'pallet', 48, 40, 50, 300, 2) as r7a \gset
select pg_temp.ua(:'u_sales', :'s3', 'pallet', 48, 40, 50, 300, 1) as r7b \gset
select pg_temp.chk('T7 two consecutive adds (2 then 1) → P4 P5 then P6 · all labels of the order distinct · wms_unit_add locks the so row (for update) before numbering',
  (pg_temp.j(:'r7a')->'labels')::text || '/' || (pg_temp.j(:'r7b')->'labels')::text || ' | ' || (select (count(*) = count(distinct u.label))::text || '/' || count(*)::text from public.wms_pallets u where u.order_id = :'s3'::uuid)
  || ' | ' || (select (p.prosrc ~ 'from public\.so s where s\.id = p_so_id for update')::text from pg_proc p where p.oid = 'public.wms_unit_add(uuid, text, numeric, numeric, numeric, numeric, int, text, text)'::regprocedure),
  '["P4", "P5"]/["P6"] | true/5 | true');

-- ── T8 원장 · 예약 · 인보이스 · so_line 무변 ──
select pg_temp.chk('T8 inv_ledger · so_reserve · so_invoice counts and the fake orders'' so_line fingerprint = before the tests',
  (select count(*) from public.inv_ledger)::text || '/' || (select count(*) from public.so_reserve)::text || '/' || (select count(*) from public.so_invoice)::text || '/'
  || (select md5(string_agg(l::text, '|' order by l.id)) from public.so_line l where l.so_id in (:'s1'::uuid, :'s2'::uuid, :'s3'::uuid)),
  :'led0' || '/' || :'res0' || '/' || :'inv0' || '/' || :'line0');

-- ── T9 REST 첫 겹(정적): 새 함수의 update · delete 에 깊이 0 WHERE ──
select pg_temp.chk('T9 nowhere(prosrc) = 0 for wms_unit_add · wms_unit_remove · wms_unit_counts_refresh · wms_unit_booking_gate',
  (select string_agg(proname || ' ' || pg_temp.nowhere(prosrc)::text, ' · ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('wms_unit_add', 'wms_unit_remove', 'wms_unit_counts_refresh', 'wms_unit_booking_gate')),
  'wms_unit_add 0 · wms_unit_booking_gate 0 · wms_unit_counts_refresh 0 · wms_unit_remove 0');

-- ── M 무접촉 · comment ──
\if :{?mig}
select pg_temp.chk('M1 (시험 갈래) the four new functions were absent at begin 앞', :'fn_n0', '0');
\endif
select pg_temp.chk('M2 wms_unit_dims_set · wms_so_handoff · fc_units_snapshot · fc_shipment_for_so · wms_finalize · fc_shipment_prepare · fc_book_prepare · wms_rollback untouched (prosrc md5 · acl = begin 앞)',
  (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5 and p.proacl::text is not distinct from t.acl
    where t.proname in ('wms_unit_dims_set', 'wms_so_handoff', 'fc_units_snapshot', 'fc_shipment_for_so', 'wms_finalize', 'fc_shipment_prepare', 'fc_book_prepare', 'wms_rollback')), '8');
select pg_temp.chk('M3 comments carry 판정 881 on the four functions',
  (select count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_unit_add', 'wms_unit_remove', 'wms_unit_booking_gate', 'wms_unit_counts_refresh') and obj_description(p.oid, 'pg_proc') ~ '881'), '4');
select pg_temp.chk('M4 wms_pallets · wms_pallet_items policies untouched (auth_all · using true · with check true · 판정 569)',
  (select string_agg(tablename || ':' || policyname || ':' || qual || ':' || with_check, ' · ' order by tablename) from pg_policies where schemaname = 'public' and tablename in ('wms_pallets', 'wms_pallet_items')),
  'wms_pallet_items:auth_all:true:true · wms_pallets:auth_all:true:true');

-- ── 결과 ──
select clock_timestamp() - :'t_begin0'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, count(*) as expect_ok from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select last_value as pal_seq1, is_called as pal_seq1_called from public.wms_pallets_id_seq \gset
select last_value as item_seq1, is_called as item_seq1_called from public.wms_pallet_items_id_seq \gset
\echo '── identity seq after (advanced by rolled-back inserts · not a document number): wms_pallets_id_seq' :pal_seq0 '→' :pal_seq1 '· items_id_seq' :item_seq0 '→' :item_seq1
select case when (select count(*) from public.wms_pallets) = :w_pal and (select count(*) from public.wms_pallet_items) = :w_item and (select count(*) from public.so) = :w_so and (select count(*) from public.ims_staff) = :w_staff
            and (select count(*) from public.customer) = :w_cust and (select count(*) from public.fc_shipment) = :w_ship and (select count(*) from public.fc_booking) = :w_book and (select count(*) from public.wms_order_finalize) = :w_fin
            and (select count(*) from public.so_line) = :w_line
            and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('wms_unit_add', 'wms_unit_remove', 'wms_unit_booking_gate', 'wms_unit_counts_refresh')) = :fn_n0
            and (select count(*) from public.so where so_number like 'SO-7997%') = 0 and (select count(*) from public.ims_staff where email like 'wun1-%') = 0 and (select count(*) from public.customer where name = 'WUN1 Co') = 0
       then 'Z1 OK real rows unchanged (wms_pallets · items · so · so_line · staff · customer · fc_shipment · fc_booking · finalize · no WUN1 leftovers) · new fn presence = begin 앞' else 'Z1 MISMATCH real rows or functions changed' end as z1;
