-- supabase/tests/cdc_1_check.sql — cdc-1 손님 기본 운송사 창구 customer_default_carrier_set + customer_export 재발행 검증 (2026-10-29 · 판정 876)
-- [테스트 · Asung-IMS] 시험 적용 장치 — db_role = test 가드 → 기준(begin 앞: 함수 md5 · acl · 전 손님 내보내기 md5) → begin → (-v mig 면 \i) → 가짜(직원 둘 · 운송사 넷 · 손님 여섯 · SO 넷 — 전부 rollback) → T1~T8 → rollback → Z
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261029230000_cdc_1_default_carrier.sql -f supabase/tests/cdc_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) EXPECT_OK 23 · 확인(적용 뒤) 22 — M1(customer_export md5 가 begin 앞과 다르다)은 시험 갈래만 · Z1 은 t_res 밖 한 줄
--   ⚠️ 시퀀스는 롤백되지 않는다(so_next_number comment) ⇒ SO 는 번호를 직접 넣는다(SO-79981~4) · so_create 대신 그 안의 so_copy_customer 를 바로 부른다(ord_1a2:132 · 창구가 손님 값을 싣는 유일한 곳)
--   ⚠️ begin 앞의 전 손님 내보내기(2.6 초)는 실제 admin 직원의 uid 를 세션 변수로 빌려 읽기만 한다(export_door 가 sales 열쇠를 본다 · customer_export 는 stable · 쓰기 없음) — 가짜 직원은 트랜잭션 안에서만
--   잠금 규칙: 무거운 기준값은 begin 앞 · lock_timeout 3s · begin ~ rollback 시간을 끝에 찍는다(안의 전 손님 내보내기 한 번 ≈ 3 초)
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
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('customer_export', 'so_copy_customer', 'customer_update', 'customer_carrier_avoid_set', 'customer_default_carrier_set');
select (select count(*) from t_pre where proname = 'customer_default_carrier_set') = 0 as fn_absent \gset
select (select count(*) from public.customer) as w_cust, (select count(*) from public.so) as w_so, (select count(*) from public.ims_staff) as w_staff, (select count(*) from public.ref_carrier) as w_car,
       (select md5 from t_pre where proname = 'customer_export') as exp_md5_0, (select acl from t_pre where proname = 'customer_export') as exp_acl_0 \gset
select auth_user_id::text as u_real from public.ims_staff where role = 'admin' and is_active order by created_at limit 1 \gset
select set_config('request.jwt.claims', json_build_object('sub', :'u_real', 'role', 'authenticated')::text, false) as borrowed_identity_for_read_only_baseline;
select array_agg(c.key order by c.ord)::text as cols from public.export_catalog('customer') c where public.export_gate_ok(c.gate) \gset
select md5((e->'rows')::text) as md5_rows0, md5((e->'columns')::text) as md5_cols0, e->>'row_count' as rc0 from (select public.customer_export(null, false, false, :'cols'::text[]) e) x \gset
select set_config('request.jwt.claims', '', false) as identity_off;
\echo '── 기준: customer' :w_cust '· so' :w_so '· staff' :w_staff '· ref_carrier' :w_car '· customer_export md5' :exp_md5_0 '· new fn absent' :fn_absent '· export rows' :rc0 '· cols' :cols
\if :{?mig}
\set EXPECT_OK 23
\else
\set EXPECT_OK 22
\endif
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
-- safeupdate 의 규칙을 정적으로 센다(qbo_1c_check.sql · ar_2b_check.sql 의 것 그대로): 문장마다 머리 동사가 update · delete(then · else · loop · begin 뒤 포함) 또는 with 뒤 최상위 update · delete 이고 깊이 0 에 where 가 없으면 하나
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
create function pg_temp.cdc(p_uid text, p_cust text, p_car text, p_old text) returns text language plpgsql as $$
declare v text;
begin
  perform pg_temp.as_user(p_uid);
  execute 'set local role authenticated';
  execute format('select public.customer_default_carrier_set(%L, %L, %L)::text', p_cust::uuid, p_car::uuid, p_old::uuid) into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then reset role; return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.crow(p_cust text) returns text language sql as $$
  select coalesce(c.default_carrier_id::text, '(null)') || '|' || coalesce(c.default_carrier, '(null)') || '|' || coalesce(c.updated_by::text, '(null)') || '|' || (c.updated_at > now() - interval '1 hour')::text
  from public.customer c where c.id = p_cust::uuid;
$$;

-- ── 가짜: 직원 둘 · 운송사 넷 · 손님 여섯 — 손님의 updated_at 은 하루 전(touch 가 돌면 now()) ──
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'cdc1-sales@test.invalid', 'CDC1 Sales', 'worker', '["sales"]', '{}') returning auth_user_id::text as u_sales, id::text as st_sales \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'cdc1-picker@test.invalid', 'CDC1 Picker', 'worker', '["picking"]', '{}') returning auth_user_id::text as u_pick \gset
set local session_replication_role = origin;
insert into public.ref_carrier (name, kind) values ('CDC1 Carrier', 'carrier') returning id::text as car_a \gset
insert into public.ref_carrier (name, kind) values ('CDC1 Pickup', 'pickup') returning id::text as car_p \gset
insert into public.ref_carrier (name, kind) values ('CDC1 Delivery', 'delivery') returning id::text as car_d \gset
insert into public.ref_carrier (name, kind, is_active) values ('CDC1 Off', 'carrier', false) returning id::text as car_off \gset
select id::text as cad from public.ref_currency where code = 'CAD' \gset

-- ── T7a · T7b 전 손님 내보내기(가짜 손님을 넣기 전 · 가짜 sales 직원으로 · 같은 칸 목록) — 다른 칸 전후 같음 · 운송사 칸은 id 가 있으면 표 이름(실물에선 글자 = 표 이름이라 같다) ──
select pg_temp.as_user(:'u_sales');
select md5((e->'rows')::text) as md5_rows1, md5((e->'columns')::text) as md5_cols1, e->>'row_count' as rc1 from (select public.customer_export(null, false, false, :'cols'::text[]) e) x \gset
select pg_temp.chk('T7a customer_export(all gated columns · all customers) rows md5 · row_count = begin 앞(옛 판)과 같다', :'md5_rows1' || '/' || :'rc1', :'md5_rows0' || '/' || :'rc0');
select pg_temp.chk('T7b columns[] (이름 · 순서 · label · text) = begin 앞과 같다', :'md5_cols1', :'md5_cols0');

insert into public.customer (name, source, currency_id, price_tier, created_at, updated_at) values ('CDC1 None Co', 'manual', :'cad'::uuid, 'Wholesale', now() - interval '2 day', now() - interval '1 day') returning id::text as c1 \gset
insert into public.customer (name, source, currency_id, price_tier, default_carrier, created_at, updated_at) values ('CDC1 Typed Co', 'cin7', :'cad'::uuid, 'Wholesale', 'Old Freight Co', now() - interval '2 day', now() - interval '1 day') returning id::text as c2 \gset
insert into public.customer (name, source, currency_id, price_tier, default_carrier_id, default_carrier, created_at, updated_at) values ('CDC1 Listed Co', 'cin7', :'cad'::uuid, 'Wholesale', :'car_a'::uuid, 'CDC1 Carrier', now() - interval '2 day', now() - interval '1 day') returning id::text as c3 \gset
insert into public.customer (name, source, currency_id, price_tier, default_carrier_id, default_carrier, created_at, updated_at) values ('CDC1 Stale Co', 'cin7', :'cad'::uuid, 'Wholesale', :'car_a'::uuid, 'Stale Name', now() - interval '2 day', now() - interval '1 day') returning id::text as c4 \gset
insert into public.customer (name, source, currency_id, price_tier, default_carrier, created_at, updated_at) values ('CDC1 Typed Keep Co', 'cin7', :'cad'::uuid, 'Wholesale', 'Typed Keep', now() - interval '2 day', now() - interval '1 day') returning id::text as c5 \gset
insert into public.customer (name, source, currency_id, price_tier, default_carrier_id, default_carrier, created_at, updated_at) values ('CDC1 Stale Keep Co', 'cin7', :'cad'::uuid, 'Wholesale', :'car_a'::uuid, 'Stale Keep', now() - interval '2 day', now() - interval '1 day') returning id::text as c6 \gset

-- ── S0 스캐너 자기 시험 ──
select pg_temp.chk('S0 scanner self-test: no-where update 1 · where 0 · subquery-where-only 1 · with-update no-where 1 · delete no-where 1 · then-update 1 · string update 0 · where singleton 0',
  pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
  || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text
  || pg_temp.nowhere('update t set a = 1 where singleton returning * into v;')::text, '10111100');

-- ── T1 sales 직원: carrier 고름 ──
select pg_temp.cdc(:'u_sales', :'c1', :'car_a', null) as r1 \gset
select pg_temp.chk('T1 sales picks a carrier (kind carrier · p_old null) → changed true · id · text = list name · row: id · text · updated_by = staff · updated_at moved (touch ran)',
  concat_ws('/', coalesce(pg_temp.j(:'r1')->>'changed', :'r1'), (pg_temp.j(:'r1')->>'default_carrier_id' = :'car_a')::text, pg_temp.j(:'r1')->>'default_carrier', pg_temp.crow(:'c1')),
  'true/true/CDC1 Carrier/' || :'car_a' || '|CDC1 Carrier|' || :'st_sales' || '|true');

-- ── T2 pickup · delivery 종류도 받는다 ──
select pg_temp.cdc(:'u_sales', :'c1', :'car_p', :'car_a') as r2a \gset
select pg_temp.cdc(:'u_sales', :'c1', :'car_d', :'car_p') as r2b \gset
select pg_temp.chk('T2 pickup kind (p_old = carrier) then delivery kind (p_old = pickup) → both changed true · text follows · row ends on Delivery',
  concat_ws('/', coalesce(pg_temp.j(:'r2a')->>'changed', :'r2a'), pg_temp.j(:'r2a')->>'default_carrier', coalesce(pg_temp.j(:'r2b')->>'changed', :'r2b'), pg_temp.j(:'r2b')->>'default_carrier', pg_temp.crow(:'c1')),
  'true/CDC1 Pickup/true/CDC1 Delivery/' || :'car_d' || '|CDC1 Delivery|' || :'st_sales' || '|true');

-- ── T6a · T6b 새 SO 가 so_copy_customer 로 손님 기본을 싣는다(번호 직접 · 시퀀스 안 당김) ──
insert into public.so (so_number, customer_id, channel, intake, currency_id) values ('SO-79981', :'c1'::uuid, 'warehouse', 'manual', :'cad'::uuid) returning id::text as so1 \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id) values ('SO-79982', :'c2'::uuid, 'warehouse', 'manual', :'cad'::uuid) returning id::text as so2 \gset
select public.so_copy_customer(:'so1'::uuid, :'c1'::uuid) as x1 \gset
select public.so_copy_customer(:'so2'::uuid, :'c2'::uuid) as x2 \gset
select pg_temp.chk('T6a new SO for the customer after picking (Delivery) → so.carrier_id = that id · so.carrier = list name',
  (select coalesce(s.carrier_id::text, '(null)') || '|' || coalesce(s.carrier, '(null)') from public.so s where s.id = :'so1'::uuid), :'car_d' || '|CDC1 Delivery');
select pg_temp.chk('T6b new SO for a typed-only customer (id null · text Old Freight Co) before clearing → carrier_id null · carrier = the old text (why 876 ④ clears the text)',
  (select coalesce(s.carrier_id::text, '(null)') || '|' || coalesce(s.carrier, '(null)') from public.so s where s.id = :'so2'::uuid), '(null)|Old Freight Co');

-- ── T3 null → 둘 다 null · 옛 글자만 있던 손님에 p_old null + null → 글자 비워짐 ──
select pg_temp.cdc(:'u_sales', :'c1', null, :'car_d') as r3a \gset
select pg_temp.cdc(:'u_sales', :'c2', null, null) as r3b \gset
select pg_temp.chk('T3a none (p_carrier_id null · p_old = current id) → changed true · id · text both null in the result and on the row',
  concat_ws('/', coalesce(pg_temp.j(:'r3a')->>'changed', :'r3a'), (pg_temp.j(:'r3a') ? 'default_carrier_id')::text, coalesce(pg_temp.j(:'r3a')->>'default_carrier_id', '(null)'), coalesce(pg_temp.j(:'r3a')->>'default_carrier', '(null)'), pg_temp.crow(:'c1')),
  'true/true/(null)/(null)/(null)|(null)|' || :'st_sales' || '|true');
select pg_temp.chk('T3b typed-only customer (id null · text Old Freight Co) · none with p_old null → changed true · text cleared · id null · touched',
  concat_ws('/', coalesce(pg_temp.j(:'r3b')->>'changed', :'r3b'), pg_temp.crow(:'c2')), 'true/(null)|(null)|' || :'st_sales' || '|true');

-- ── T6c 비운 뒤의 새 SO → 둘 다 비어 있음 ──
insert into public.so (so_number, customer_id, channel, intake, currency_id) values ('SO-79983', :'c1'::uuid, 'warehouse', 'manual', :'cad'::uuid) returning id::text as so3 \gset
insert into public.so (so_number, customer_id, channel, intake, currency_id) values ('SO-79984', :'c2'::uuid, 'warehouse', 'manual', :'cad'::uuid) returning id::text as so4 \gset
select public.so_copy_customer(:'so3'::uuid, :'c1'::uuid) as x3 \gset
select public.so_copy_customer(:'so4'::uuid, :'c2'::uuid) as x4 \gset
select pg_temp.chk('T6c new SOs after clearing (both customers) → carrier_id null · carrier null',
  (select string_agg(coalesce(s.carrier_id::text, '(null)') || '|' || coalesce(s.carrier, '(null)'), ' · ' order by s.so_number) from public.so s where s.id in (:'so3'::uuid, :'so4'::uuid)), '(null)|(null) · (null)|(null)');

-- ── T4 거부 여섯 ──
select pg_temp.chk('T4a p_old differs from the row (row = Carrier · screen saw none) → refused · one sentence with the current name · row untouched',
  pg_temp.cdc(:'u_sales', :'c3', :'car_p', null) || ' / ' || pg_temp.crow(:'c3'),
  'ERR P0001: Someone changed this customer''s default carrier just now (it is now CDC1 Carrier) — reload the customer and try again — nothing was saved / ' || :'car_a' || '|CDC1 Carrier|(null)|false');
select pg_temp.chk('T4b switched-off carrier → refused (so_header_update wording) · row untouched',
  pg_temp.cdc(:'u_sales', :'c3', :'car_off', :'car_a') || ' / ' || pg_temp.crow(:'c3'),
  'ERR P0001: Carrier CDC1 Off is switched off — pick an active carrier — nothing was saved / ' || :'car_a' || '|CDC1 Carrier|(null)|false');
select pg_temp.cdc(:'u_sales', :'c3', '00000000-0000-4000-8000-00000000c0de', :'car_a') as r4c \gset
select pg_temp.chk('T4c unknown carrier id → refused · row untouched',
  :'r4c' || ' / ' || pg_temp.crow(:'c3'),
  'ERR P0001: Carrier 00000000-0000-4000-8000-00000000c0de is not on the carrier list — pick one from the list — nothing was saved / ' || :'car_a' || '|CDC1 Carrier|(null)|false');
select pg_temp.chk('T4d unknown customer → refused',
  pg_temp.cdc(:'u_sales', '00000000-0000-4000-8000-00000000c0de', :'car_a', null), 'ERR P0001: Customer 00000000-0000-4000-8000-00000000c0de not found — nothing was saved');
select pg_temp.chk('T4e staff without sales write (picking only) → refused by ims_require_write(sales) · row untouched',
  pg_temp.cdc(:'u_pick', :'c3', :'car_p', :'car_a') || ' / ' || pg_temp.crow(:'c3'),
  'ERR P0001: You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved / ' || :'car_a' || '|CDC1 Carrier|(null)|false');
select pg_temp.chk('T4f function acl: authenticated execute · anon no · service_role no · public no · security definer · search_path pinned',
  has_function_privilege('authenticated', 'public.customer_default_carrier_set(uuid, uuid, uuid)', 'execute')::text || has_function_privilege('anon', 'public.customer_default_carrier_set(uuid, uuid, uuid)', 'execute')::text
  || has_function_privilege('service_role', 'public.customer_default_carrier_set(uuid, uuid, uuid)', 'execute')::text || (select (p.proacl::text ~ '=X/' and p.proacl::text !~ '^\{=')::text || '/' || p.prosecdef::text || '/' || (array_to_string(p.proconfig, ',') ~ 'search_path=public, pg_temp')::text from pg_proc p where p.oid = 'public.customer_default_carrier_set(uuid, uuid, uuid)'::regprocedure),
  'truefalsefalsetrue/true/true');

-- ── T5 같은 값 다시 → changed false · 행 무변 · 같은 id 지만 글자가 옛것이면 글자만 고친다 ──
select pg_temp.cdc(:'u_sales', :'c3', :'car_a', :'car_a') as r5a \gset
select pg_temp.chk('T5a same id · text already the list name → changed false · result echoes id · name · row untouched (updated_by null · updated_at a day old)',
  concat_ws('/', coalesce(pg_temp.j(:'r5a')->>'changed', :'r5a'), (pg_temp.j(:'r5a')->>'default_carrier_id' = :'car_a')::text, pg_temp.j(:'r5a')->>'default_carrier', pg_temp.crow(:'c3')),
  'false/true/CDC1 Carrier/' || :'car_a' || '|CDC1 Carrier|(null)|false');
select pg_temp.cdc(:'u_sales', :'c4', :'car_a', :'car_a') as r5b \gset
select pg_temp.chk('T5b same id but stale text (Stale Name) → changed true · text becomes the list name · touched',
  concat_ws('/', coalesce(pg_temp.j(:'r5b')->>'changed', :'r5b'), pg_temp.crow(:'c4')), 'true/' || :'car_a' || '|CDC1 Carrier|' || :'st_sales' || '|true');

-- ── T7c 내보내기 운송사 칸: id 의 표 이름 · id 없는 손님은 옛 글자 · 비운 손님은 빈칸 ──
select (array_position(:'cols'::text[], 'name') - 1)::text as i_name, (array_position(:'cols'::text[], 'carrier') - 1)::text as i_car \gset
select pg_temp.as_user(:'u_sales');
select pg_temp.chk('T7c export carrier column: Listed = list name · Stale Keep (id + stale text) = list name (id wins) · Typed Keep (text only) = the text · None · Typed (cleared) = null · Stale (fixed in T5b) = list name',
  (select jsonb_object_agg(r->>(:i_name), coalesce(r->>(:i_car), '(null)'))::text from jsonb_array_elements(public.customer_export('CDC1 ', false, false, :'cols'::text[])->'rows') r),
  jsonb_build_object('CDC1 None Co', '(null)', 'CDC1 Typed Co', '(null)', 'CDC1 Listed Co', 'CDC1 Carrier', 'CDC1 Stale Co', 'CDC1 Carrier', 'CDC1 Typed Keep Co', 'Typed Keep', 'CDC1 Stale Keep Co', 'CDC1 Carrier')::text);

-- ── T8 REST 첫 겹(정적): 새 함수 · 재발행 함수의 update · delete 에 깊이 0 WHERE ──
select pg_temp.chk('T8 nowhere(prosrc) = 0 for customer_default_carrier_set and customer_export',
  (select string_agg(proname || ' ' || pg_temp.nowhere(prosrc)::text, ' · ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('customer_default_carrier_set', 'customer_export')),
  'customer_default_carrier_set 0 · customer_export 0');

-- ── M 재발행 · 무접촉 · comment ──
\if :{?mig}
select pg_temp.chk('M1 (시험 갈래) customer_export prosrc md5 differs from begin 앞 · acl same · comment carries 876 · only the carrier line and the join changed (coalesce(rc.name, c.default_carrier) · left join ref_carrier rc)',
  (select (md5(p.prosrc) <> :'exp_md5_0')::text || '/' || (p.proacl::text = :'exp_acl_0')::text || '/' || (obj_description(p.oid, 'pg_proc') ~ '876')::text || '/' || (p.prosrc ~ '''carrier'', coalesce\(rc\.name, c\.default_carrier\)')::text || '/' || (p.prosrc ~ 'left join public\.ref_carrier rc on rc\.id = c\.default_carrier_id')::text || '/' || p.prosecdef::text || '/' || p.provolatile::text
   from pg_proc p where p.oid = 'public.customer_export(text, boolean, boolean, text[])'::regprocedure), 'true/true/true/true/true/true/s');
\endif
select pg_temp.chk('M2 so_copy_customer · customer_update · customer_carrier_avoid_set untouched (prosrc md5 = begin 앞)',
  (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5 where t.proname in ('so_copy_customer', 'customer_update', 'customer_carrier_avoid_set')), '3');
select pg_temp.chk('M3 comments carry 판정 876: function · customer.default_carrier_id · customer.default_carrier (old text kept in front)',
  (obj_description('public.customer_default_carrier_set(uuid, uuid, uuid)'::regprocedure, 'pg_proc') ~ '876')::text || '/'
  || (select (col_description('public.customer'::regclass, a.attnum) ~ '^ful-1a 판정 436 · 451: 손님 기본 운송사.*cdc-1 판정 876')::text from pg_attribute a where a.attrelid = 'public.customer'::regclass and a.attname = 'default_carrier_id') || '/'
  || (select (col_description('public.customer'::regclass, a.attnum) ~ '^Cin7 Carrier 원문.*cdc-1 판정 876')::text from pg_attribute a where a.attrelid = 'public.customer'::regclass and a.attname = 'default_carrier'), 'true/true/true');

-- ── 결과 ──
select clock_timestamp() - :'t_begin0'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.customer) = :w_cust and (select count(*) from public.so) = :w_so and (select count(*) from public.ims_staff) = :w_staff and (select count(*) from public.ref_carrier) = :w_car
            and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'customer_export') = :'exp_md5_0'
            and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'customer_default_carrier_set') = (case when :'fn_absent' = 't' then 0 else 1 end)
            and (select count(*) from public.customer where name like 'CDC1 %') = 0 and (select count(*) from public.so where so_number like 'SO-7998%') = 0
       then 'Z1 OK real rows unchanged (customer · so · staff · ref_carrier · no CDC1 leftovers) · customer_export md5 = begin 앞 · new fn presence = begin 앞' else 'Z1 MISMATCH real rows or functions changed' end as z1;
