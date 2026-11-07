-- supabase/tests/fc_pickup_3_check.sql — fc-pickup-3 픽업 연락처 · reference_codes · 주말 검증 (2026-11-06 · 판정 1040 ~ 1042) · ⭐ 사슬 없음 — 가짜 행 직접(fc_pickup_1 선례)
--   fc_book_prepare 를 실제로 부른다(p_commit false · 쓰기 0 · 잠금은 가짜 발송 행뿐) — 발송 selected + fc_quote · fc_quote_rate(실제 ref_carrier id 는 읽기만) + live SO(packed · 유닛 없음 ⇒ 스냅샷 []) 를 replica 로 직접 넣는다
--   Claude Code(시험 · 레포 루트 · ⚠️ 토론토 17:00 뒤): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261107012000_fc_pickup_3_pickup_contact_refs.sql -f supabase/tests/fc_pickup_3_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK 는 EXPECT_OK(두 갈래 같다 · P3 · P4 「전후 같음」 은 확인 실행에서는 둘 다 새 몸이라 자명) · Z1 둘 다 · Z2 시험 갈래만
--   재료(FCX · rollback): whA(Contact · Phone 있음 · closes 17:00) · whB(Contact 있음 · Phone 5 자리) · whC(둘 다 빈칸) · u_book(freight_booking · 창고 셋) · u_sales(sales · fc_charge_so_set 용) ·
--     SO-79901 ~ 79912(packed · 유닛 없음 · created_at 1 분씩) · 운송사 UPS(비정기) · Purolator(whA · whC 정기) · Fastfrate(팔렛) · 발송마다 quote 1 + rate 1
--   값(연락처 이름 · 전화)은 출력하지 않는다 — 길이 · 꼴로만 단언
\set ON_ERROR_STOP on
\set EXPECT_OK 16
\pset pager off
select (select count(*) from public.so) as y_so, (select count(*) from public.fc_shipment) as y_fc, (select count(*) from public.fc_booking) as y_bk, (select count(*) from public.ims_staff) as y_staff, (select count(*) from public.ref_warehouse) as y_wh, (select count(*) from public.ref_carrier_pickup) as y_pk, (select count(*) from public.fc_quote) as y_q, (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_book_prepare') as y_md5 \gset
-- ── begin 앞(잠금 없음): 임시 표 · 임시 함수 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql security definer as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
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
create temp table t_ids (k text primary key, v text);
create function pg_temp.id(p_k text) returns uuid language sql as $$ select v::uuid from t_ids where k = p_k $$;
create function pg_temp.num(p_k text) returns text language sql as $$ select s.so_number from public.so s where s.id = pg_temp.id(p_k) $$;
create temp table t_before (k text primary key, req jsonb);
-- 몸 비교용: 이번에 더해진 details.reference_codes 만 뺀 몸
create function pg_temp.strip(p jsonb) returns jsonb language sql immutable as $$ select p #- '{details,reference_codes}' $$;
-- 발송 하나 = selected 발송 + quote 1 + rate 1(carrier_id 실제 행 · raw {} ⇒ 마감은 IMS 값) + live SO 줄 · 견적 details 에 옛 reference_codes 를 심어 둔다(덮이는지)
create function pg_temp.mk(p_k text, p_wh text, p_ptype text, p_carrier text, p_sos text[], p_charge text, p_ship date) returns void language plpgsql as $$
declare v_sh uuid; v_q uuid; v_r uuid; v_c public.ref_carrier%rowtype; k text;
begin
  select * into v_c from public.ref_carrier c where c.name = p_carrier;
  insert into public.fc_shipment (status, origin_warehouse_id, packaging_type, charge_so_id, origin, destination, options, units, request, payload_hash, created_in, freightcom_account)
    values ('selected', pg_temp.id(p_wh), p_ptype, pg_temp.id(p_charge), '{}', '{}', jsonb_build_object('ship_date', p_ship), '[]',
            jsonb_build_object('details', jsonb_build_object('origin', '{}'::jsonb, 'destination', '{}'::jsonb, 'packaging_type', p_ptype, 'expected_ship_date', '{}'::jsonb, 'reference_codes', jsonb_build_array('OLD-REF'))),
            'fcx3-' || p_k, 'wms', 'FCX') returning id into v_sh;
  insert into public.fc_quote (shipment_id, status, request) values (v_sh, 'done', '{}') returning id into v_q;
  insert into public.fc_quote_rate (quote_id, service_id, carrier_name, service_name, carrier_id, pretax_cents, markup_pct, customer_charge_cents, raw)
    values (v_q, 'fcx3-svc-' || p_k, v_c.name, 'FCX service', v_c.id, 1000, 0, 1000, '{}') returning id into v_r;
  update public.fc_shipment set selected_rate_id = v_r where id = v_sh;
  foreach k in array p_sos loop insert into public.fc_shipment_so (shipment_id, so_id, live) values (v_sh, pg_temp.id(k), true); end loop;
  insert into t_ids values (p_k, v_sh);
end $$;
-- 화면 길 그대로(fc_book_prepare · p_commit false · 부른 사람의 문은 request.jwt.claims)
create function pg_temp.prep(p_k text, p_pickup jsonb default '{}') returns jsonb language sql as $$ select public.fc_book_prepare(pg_temp.id(p_k), p_pickup, false) $$;
create function pg_temp.keys(p jsonb) returns text language sql immutable as $$ select coalesce((select string_agg(k, ',' order by k) from jsonb_object_keys(p) k), '(none)') $$;
-- 날짜: 다음 주 평일 하나(wd) · 다음 토요일(sat) · 일요일(sun) · 그 다음 월요일(mon)
select d as wd from (select public.ims_today() + 7 + case extract(isodow from public.ims_today() + 7) when 6 then 2 when 7 then 1 else 0 end as d) t \gset
select d as sat, d + 1 as sun, d + 2 as mon from (select public.ims_today() + ((6 - extract(isodow from public.ims_today())::int + 7) % 7) + case when extract(isodow from public.ims_today()) = 6 then 7 else 0 end as d) t \gset
\echo '── wd' :wd '· sat' :sat '· sun' :sun '· mon' :mon
-- psql 변수는 DO $$ 안에 안 들어간다 → 임시 표로 넘긴다
create temp table t_d (k text primary key, d date);
insert into t_d values ('wd', :'wd'), ('sat', :'sat'), ('sun', :'sun'), ('mon', :'mon');
create function pg_temp.d(p_k text) returns date language sql as $$ select d from t_d where k = p_k $$;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin0000 \gset
-- ── 재료(replica · 가짜 FCX · 한 왕복) ──
set local session_replication_role = replica;
do $$
declare v_a uuid; v_b uuid; v_c uuid; v_book uuid; v_sales uuid; v_cust uuid; v_cur uuid; v_id uuid; i int;
begin
  select id into v_cust from public.customer order by created_at limit 1;                 -- 읽기만(FK)
  select id into v_cur  from public.ref_currency order by created_at limit 1;
  insert into public.ref_warehouse (name, source, is_active, address_line1, city, state_province, postal_code, country, freightcom_account, timezone, closes_at, contact_name, phone)
    values ('FCX A', 'manual', true, '1 Fcx Road', 'Toronto', 'ON', 'M9N 2V8', 'Canada', 'FCX', 'America/Toronto', '17:00', 'FCX Contact', '(416) 555-0100') returning id into v_a;
  insert into public.ref_warehouse (name, source, is_active, address_line1, city, state_province, postal_code, country, freightcom_account, timezone, closes_at, contact_name, phone)
    values ('FCX B', 'manual', true, '2 Fcx Road', 'Toronto', 'ON', 'M9N 2V8', 'Canada', 'FCX', 'America/Toronto', '17:00', 'FCX Contact', '12345') returning id into v_b;
  insert into public.ref_warehouse (name, source, is_active, address_line1, city, state_province, postal_code, country, freightcom_account, timezone, closes_at, contact_name, phone)
    values ('FCX C', 'manual', true, '3 Fcx Road', 'Toronto', 'ON', 'M9N 2V8', 'Canada', 'FCX', 'America/Toronto', '17:00', '  ', null) returning id into v_c;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-booker3@test.invalid', 'FCX Booker', 'worker', '["wms","fulfillment","freight_booking"]', array[v_a, v_b, v_c]) returning auth_user_id into v_book;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-sales3@test.invalid', 'FCX Sales', 'worker', '["sales"]', '{}') returning auth_user_id into v_sales;
  insert into t_ids values ('a', v_a), ('b', v_b), ('c', v_c), ('u_book', v_book), ('u_sales', v_sales);
  insert into public.ref_carrier_pickup (carrier_id, warehouse_id, regular_pickup)
    select c.id, w.wh, w.reg from public.ref_carrier c join (values ('UPS', v_a, false), ('Purolator', v_a, true), ('UPS', v_b, false), ('UPS', v_c, false), ('Purolator', v_c, true)) w(cn, wh, reg) on w.cn = c.name;
  for i in 1..12 loop
    insert into public.so (customer_id, channel, intake, currency_id, so_number, status, created_at) values (v_cust, 'warehouse', 'manual', v_cur, 'SO-799' || lpad(i::text, 2, '0'), 'packed', now() - interval '1 hour' + (i * interval '1 minute')) returning id into v_id;
    insert into t_ids values ('s' || i, v_id);
  end loop;
  perform pg_temp.mk('a1', 'a', 'package', 'UPS',       array['s1'],             's1', pg_temp.d('wd'));         -- 비정기 상자 · SO 하나 · 평일 ship_date
  perform pg_temp.mk('a2', 'a', 'package', 'UPS',       array['s2', 's3', 's4'], 's3', pg_temp.d('wd'));         -- 셋 · 운임 SO 가운데
  perform pg_temp.mk('a3', 'a', 'package', 'Purolator', array['s5'],             's5', pg_temp.d('wd'));         -- 정기 픽업 상자
  perform pg_temp.mk('a4', 'a', 'pallet',  'Fastfrate', array['s6'],             's6', pg_temp.d('wd'));         -- 팔렛
  perform pg_temp.mk('a5', 'a', 'package', 'UPS',       array['s7'],             's7', pg_temp.d('sat'));        -- ship_date 토요일 → 자동 갈래 주말
  perform pg_temp.mk('a6', 'a', 'package', 'UPS',       array['s8'],             's1', pg_temp.d('wd'));         -- 운임 SO 가 발송에 없음
  perform pg_temp.mk('b1', 'b', 'package', 'UPS',       array['s9'],             's9', pg_temp.d('wd'));         -- Phone 5 자리
  perform pg_temp.mk('c1', 'c', 'package', 'UPS',       array['s10'],            's10', pg_temp.d('wd'));        -- Contact · Phone 빈칸
  perform pg_temp.mk('c2', 'c', 'package', 'Purolator', array['s11'],            's11', pg_temp.d('wd'));        -- 빈칸 창고 · 정기 → 검사 안 함
  perform pg_temp.mk('c3', 'c', 'pallet',  'Fastfrate', array['s12'],            's12', pg_temp.d('wd'));        -- 빈칸 창고 · 팔렛 → 검사 안 함
end $$;
set local session_replication_role = origin;
-- ── 재발행 앞의 몸(정기 · 팔렛 · 전후 비교용) ──
do $$
begin
  perform pg_temp.as_user(pg_temp.id('u_book')::text);
  insert into t_before values ('a3', pg_temp.prep('a3')->'request'), ('a4', pg_temp.prep('a4')->'request'), ('c2', pg_temp.prep('c2')->'request'), ('c3', pg_temp.prep('c3')->'request');
end $$;
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 갈래 P0 ~ P13 (한 왕복) ──
do $$
declare p jsonb; q jsonb; v_wd date := pg_temp.d('wd'); v_sat date := pg_temp.d('sat'); v_sun date := pg_temp.d('sun'); v_mon date := pg_temp.d('mon');
        v_wd2 date := pg_temp.d('wd') + case extract(isodow from pg_temp.d('wd')) when 5 then 3 when 6 then 2 else 1 end;   -- wd 다음 평일
begin
  perform pg_temp.chk('P0 fc_book_prepare 1 · md5 = file body (857e3baf) · nowhere(prosrc) 0 · fc_book_save · fc_charge_so_set md5 untouched',
    (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_book_prepare')::text || '/' ||
    (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_book_prepare') || '/' ||
    (select pg_temp.nowhere(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_book_prepare')::text || '/' ||
    (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_book_save') || '/' ||
    (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_charge_so_set'),
    '1/857e3baf1d4e174314040c1d2b610320/0/e6a0f6a0c836a5304ff2b8e5f5f1fc1c/1940fae6deab473f8338612f3b3ffc1b');
  perform pg_temp.as_user(pg_temp.id('u_book')::text);
  -- P1 비정기 상자 · SO 하나
  p := pg_temp.prep('a1');
  perform pg_temp.chk('P1 UPS box · non-regular → pickup_details keys 6 · contact_name present(len>0) · contact_phone_number {number} 10 digits · pre_scheduled false · date = ship_date · warnings 0 · committed false',
    pg_temp.keys(p#>'{request,pickup_details}') || '/' || (length(p#>>'{request,pickup_details,contact_name}') > 0)::text || '/' || pg_temp.keys(p#>'{request,pickup_details,contact_phone_number}') || '/' ||
    ((p#>>'{request,pickup_details,contact_phone_number,number}') ~ '^[0-9]{10}$')::text || '/' || (p#>>'{request,pickup_details,pre_scheduled_pickup}') || '/' || (p#>>'{request,pickup_details,date,day}') || '/' ||
    jsonb_array_length(p->'warnings')::text || '/' || (p->>'committed'),
    'contact_name,contact_phone_number,date,pre_scheduled_pickup,ready_at,ready_until/true/number/true/false/' || extract(day from v_wd)::text || '/0/false');
  perform pg_temp.chk('P1b same contact as origin would carry (ref_warehouse Contact · fc_phone(Phone)) · no pickup_location · OLD-REF overwritten → ["SO-79901"] · expected_ship_date = ship_date',
    ((p#>>'{request,pickup_details,contact_name}') = (select btrim(w.contact_name) from public.ref_warehouse w where w.id = pg_temp.id('a')))::text || '/' ||
    ((p#>>'{request,pickup_details,contact_phone_number,number}') = (select public.fc_phone(w.phone) from public.ref_warehouse w where w.id = pg_temp.id('a')))::text || '/' ||
    ((p#>'{request,pickup_details}') ? 'pickup_location')::text || '/' || (p#>>'{request,details,reference_codes}') || '/' || (p#>>'{request,details,expected_ship_date,day}'),
    'true/true/false/["SO-79901"]/' || extract(day from v_wd)::text);
  -- P2 셋 · 운임 SO 가운데(s3) → [s3, s2, s4]
  p := pg_temp.prep('a2');
  perform pg_temp.chk('P2 three orders · charge SO in the middle → reference_codes [charge, rest by created_at] · so_numbers stays created_at order',
    (p#>>'{request,details,reference_codes}') || '/' || (p->>'so_numbers'), '["SO-79903", "SO-79902", "SO-79904"]/["SO-79902", "SO-79903", "SO-79904"]');
  -- P2b 운임 SO 를 fc_charge_so_set(실물 창구 · sales)으로 s4 로 옮김 → [s4, s2, s3]
  perform pg_temp.as_user(pg_temp.id('u_sales')::text);
  q := public.fc_charge_so_set(pg_temp.id('a2'), pg_temp.id('s4'));
  perform pg_temp.as_user(pg_temp.id('u_book')::text);
  p := pg_temp.prep('a2');
  perform pg_temp.chk('P2b charge SO moved with fc_charge_so_set → [new charge, rest by created_at]', (q->>'charge_so_number') || '/' || (p#>>'{request,details,reference_codes}'), 'SO-79904/["SO-79904", "SO-79902", "SO-79903"]');
  -- P3 정기 픽업 상자 — 전후 같음(reference_codes 빼고) · pickup_details 그대로 · 연락처 칸 없음
  p := pg_temp.prep('a3');
  perform pg_temp.chk('P3 regular-pickup box → request unchanged except details.reference_codes · pickup_details exactly {pre_scheduled_pickup:true} · reference_codes ["SO-79905"]',
    (pg_temp.strip(p->'request') = (select pg_temp.strip(req) from t_before where k = 'a3'))::text || '/' || (p#>>'{request,pickup_details}') || '/' || (p#>>'{request,details,reference_codes}'),
    'true/{"pre_scheduled_pickup": true}/["SO-79905"]');
  -- P4 팔렛 — 전후 같음 · dispatch_details 그대로 · pickup_details 없음
  p := pg_temp.prep('a4');
  perform pg_temp.chk('P4 pallet → request unchanged except details.reference_codes · dispatch_details keys date,ready_at,ready_until · no pickup_details · reference_codes ["SO-79906"]',
    (pg_temp.strip(p->'request') = (select pg_temp.strip(req) from t_before where k = 'a4'))::text || '/' || pg_temp.keys(p#>'{request,dispatch_details}') || '/' || ((p->'request') ? 'pickup_details')::text || '/' || (p#>>'{request,details,reference_codes}'),
    'true/date,ready_at,ready_until/false/["SO-79906"]');
  -- P5 운임 SO 가 발송에 없음 → created_at 순 + charge_so_missing
  p := pg_temp.prep('a6');
  perform pg_temp.chk('P5 charge SO not on the shipment → reference_codes in created_at order · warnings[0] charge_so_missing · still prepares',
    (p#>>'{request,details,reference_codes}') || '/' || (p->'warnings'->>0), '["SO-79908"]/charge_so_missing — the freight-charge order is not on this shipment · reference codes in order-created order');
  -- P6 ship_date 토요일(자동 갈래) → 다음 월요일 · weekend warning · ready_at 09:00 · 몸의 날짜도 월요일
  p := pg_temp.prep('a5');
  perform pg_temp.chk('P6 auto path lands on Saturday (ship_date) → moved to Monday · warnings weekend:<sat> · ready_at 09:00 · pickup_details.date = Monday · expected_ship_date = Monday',
    (p#>>'{pickup,date}') || '/' || (p->'warnings'->>0) || '/' || (p#>>'{pickup,ready_at}') || '/' || (p#>>'{request,pickup_details,date,day}') || '/' || (p#>>'{request,details,expected_ship_date,day}'),
    v_mon::text || '/weekend:' || v_sat::text || ' — ' || v_sat::text || ' is a Saturday · pickup moved to ' || v_mon::text || '/09:00/' || extract(day from v_mon)::text || '/' || extract(day from v_mon)::text);
  -- P7 직원이 적은 주말 날짜 → 거부(토 · 일)
  perform pg_temp.chk('P7 explicit Saturday · Sunday date → rejected · sentence',
    pg_temp.try(format('select pg_temp.prep(''a1'', %L)::text', jsonb_build_object('date', v_sat))) || ' | ' || pg_temp.try(format('select pg_temp.prep(''a1'', %L)::text', jsonb_build_object('date', v_sun))),
    'ERR P0001: Pickup date ' || v_sat::text || ' is a Saturday — the warehouse does not ship on weekends · pick a weekday or leave the date empty — nothing was saved | ERR P0001: Pickup date ' || v_sun::text || ' is a Sunday — the warehouse does not ship on weekends · pick a weekday or leave the date empty — nothing was saved');
  -- P8 직원이 적은 평일 날짜 → 그대로 · 연락처 칸 있음 · 지난 날짜 → 옛 거부 그대로
  p := pg_temp.prep('a1', jsonb_build_object('date', v_wd2, 'ready_at', '10:30'));
  perform pg_temp.chk('P8 explicit weekday date + ready_at → accepted as given · contact keys present · past date still rejected (old rule)',
    (p#>>'{pickup,date}') || '/' || (p#>>'{pickup,ready_at}') || '/' || ((p#>'{request,pickup_details}') ? 'contact_name')::text || '/' ||
    left(pg_temp.try(format('select pg_temp.prep(''a1'', %L)::text', jsonb_build_object('date', public.ims_today() - 1))), 30),
    v_wd2::text || '/10:30/true/ERR P0001: Pickup date ' || left((public.ims_today() - 1)::text, 7));
  -- P9 Phone 5 자리(whB) → 거부 · P10 Contact · Phone 빈칸(whC) → 거부(둘 다 적는다)
  perform pg_temp.chk('P9 warehouse Phone not 10 digits → rejected · names the Phone only',
    pg_temp.try('select pg_temp.prep(''b1'')::text'), 'ERR P0001: Warehouse FCX B has no pickup contact (Phone must be a 10-digit number) — set Contact and Phone in Settings → Warehouses → Edit — nothing was saved');
  perform pg_temp.chk('P10 warehouse Contact blank · Phone empty → rejected · names both',
    pg_temp.try('select pg_temp.prep(''c1'')::text'), 'ERR P0001: Warehouse FCX C has no pickup contact (Contact is empty · Phone must be a 10-digit number) — set Contact and Phone in Settings → Warehouses → Edit — nothing was saved');
  -- P11 빈칸 창고라도 정기 픽업 · 팔렛은 검사 안 함 · 전후 같음
  p := pg_temp.prep('c2'); q := pg_temp.prep('c3');
  perform pg_temp.chk('P11 blank-contact warehouse · regular box and pallet → not rejected · bodies unchanged except reference_codes',
    (p#>>'{request,pickup_details}') || '/' || (pg_temp.strip(p->'request') = (select pg_temp.strip(req) from t_before where k = 'c2'))::text || '/' ||
    ((q->'request') ? 'dispatch_details')::text || '/' || (pg_temp.strip(q->'request') = (select pg_temp.strip(req) from t_before where k = 'c3'))::text,
    '{"pre_scheduled_pickup": true}/true/true/true');
  -- P12 p_commit false → 쓰기 0 · 발송 selected 그대로 · 문 없는 직원은 거부(옛 규칙)
  perform pg_temp.as_user(pg_temp.id('u_sales')::text);
  perform pg_temp.chk('P12 no fc_booking rows written · shipments still selected · staff without freight_booking rejected (old gate)',
    (select count(*) from public.fc_booking b where b.shipment_id in (select v::uuid from t_ids where k ~ '^[abc][0-9]$'))::text || '/' ||
    (select string_agg(distinct f.status, ',') from public.fc_shipment f where f.id in (select v::uuid from t_ids where k ~ '^[abc][0-9]$')) || '/' ||
    rtrim(left(pg_temp.try('select pg_temp.prep(''a1'')::text'), 45)),
    '0/selected/ERR P0001: You cannot book or cancel freight');
  -- P13 몸 전체 꼴(비정기 상자) — 최상위 열쇠 넷 · details 열쇠(reference_codes 포함) · 값은 없음
  perform pg_temp.as_user(pg_temp.id('u_book')::text);
  p := pg_temp.prep('a1');
  perform pg_temp.chk('P13 body keys — top details,pickup_details,service_id,unique_id (payment_method_id is the EF) · details keys incl. reference_codes',
    pg_temp.keys(p->'request') || '/' || pg_temp.keys(p#>'{request,details}'), 'details,pickup_details,service_id,unique_id/destination,expected_ship_date,origin,packaging_type,reference_codes');
end $$;

-- ── 결과 ──
select clock_timestamp() - :'t_begin0000'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :y_so and (select count(*) from public.fc_shipment) = :y_fc and (select count(*) from public.fc_booking) = :y_bk and (select count(*) from public.ims_staff) = :y_staff
             and (select count(*) from public.ref_warehouse) = :y_wh and (select count(*) from public.ref_carrier_pickup) = :y_pk and (select count(*) from public.fc_quote) = :y_q
             and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_book_prepare') = :'y_md5'
        then 'Z1 OK — rows and fc_book_prepare md5 back to before' else 'Z1 MISMATCH — something stayed' end as z1;
\if :{?mig}
select case when :'y_md5' = 'de3009d800f8dd9ab1a93b5d93b4621b' then 'Z2 OK — trial ran against the original fc_book_prepare (de3009d8)' else 'Z2 MISMATCH — DB fc_book_prepare was not the fc-2b original before the trial: ' || :'y_md5' end as z2;
\endif
