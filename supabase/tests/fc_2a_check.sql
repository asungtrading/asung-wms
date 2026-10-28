-- supabase/tests/fc_2a_check.sql — fc-2a 권한 853 · 854 · 859(freight_booking · rooms 둘) · 852 픽업 설정 · 마감 · 857 창고 시간대(Edmonton = America/Regina) 검증 (2026-10-28)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — begin → (-v mig 면 \i) → ⭐ fc_1b5_check 사본(137 = 1a 76 + 1b 23 + 1b2 7 + 1b3 13 + 1b4 8 + 1b5 10 · F10 의 for_so md5 는 2a 재발행 값으로 고쳤다) → G 갈래 → rollback → 실제 행 무변 · md5 복귀
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028201500_fc_2a_booking_perm_pickup_cutoff.sql -f supabase/tests/fc_2a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험 · 확인 둘 다 **EXPECT_OK** = 137 + G · Z1(실제 행 무변) 둘 다 · Z2(rollback 뒤 md5 복귀) 시험 갈래만 — 둘은 t_res 밖 한 줄씩
--   잠금 규칙: 기준값은 begin 앞 · lock_timeout 3s · begin ~ rollback 시간을 찍는다(10 초 안)
--   재료: 사본이 만든 가짜(FCX) — wh(토론토 꼴) · wh2(Edmonton 꼴 → G 에서 timezone America/Regina · closes_at 17:00) · car_a · car_b · car_g(c_a 가 피함) · c_a(기본 운송사 car_b) · S1 상자 · u_off(sales · master) · u_wms(fulfillment · wh) · u_none(picking)
--       + G 가 더하는 가짜 직원 셋: u_adm(admin) · u_sup(supervisor) · u_book(worker · fulfillment + freight_booking · wh)
\set ON_ERROR_STOP on
\set EXPECT_OK 164
\pset pager off
\! awk 'BEGIN{skip=0;done=0} /^\\if :\{\?mig\}/{skip=1;next} /^\\endif/{if(skip){skip=0;next}} /^-- ── 결과 ──/{done=1} done{next} skip{next} /^begin;$/{next} /^set local lock_timeout/{next} /^\\set EXPECT_OK/{next} {print}' supabase/tests/fc_1b5_check.sql > /tmp/fc_1b5-inner.sql
select (select count(*) from public.so) as x_so, (select count(*) from public.customer_address) as x_addr, (select count(*) from public.fc_shipment) as x_fc, (select count(*) from public.fc_quote) as x_q, (select count(*) from public.fc_quote_rate) as x_qr,
       (select count(*) from public.ims_staff) as x_staff, (select count(*) from public.ref_carrier) as x_car, (select count(*) from public.ref_warehouse) as x_wh,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_for_so') as forso_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_perm_catalog') as cat_md5_0,
       (select count(*) from public.ref_warehouse where name ilike '%edmonton%') as x_edm \gset
\echo '── 기준: so' :x_so '· fc_shipment' :x_fc '· fc_quote' :x_q '· staff' :x_staff '· warehouses' :x_wh '(Edmonton rows' :x_edm ') · for_so md5' :forso_md5_0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin0 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
\echo '── fc_1b5_check 속(사본 · 137)'
\i /tmp/fc_1b5-inner.sql
select count(*) as n_1b5 from t_res \gset
\echo '── fc-1b5 inner done: rows' :n_1b5

-- ── G 재료: 직원 셋 · wh2 를 Edmonton 꼴로(857) · 두 창고 closes_at 17:00 ──
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-admin@test.invalid', 'FCX Admin', 'admin', '["ims"]', '{}') returning auth_user_id::text as u_adm \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-super@test.invalid', 'FCX Super', 'supervisor', '["ims"]', '{}') returning auth_user_id::text as u_sup \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-booker@test.invalid', 'FCX Booker', 'worker', '["wms","fulfillment","freight_booking"]', array[:'wh'::uuid]) returning auth_user_id::text as u_book, id::text as st_book \gset
update public.ref_warehouse set timezone = 'America/Regina', closes_at = '17:00' where id = :'wh2'::uuid;
update public.ref_warehouse set closes_at = '17:00' where id = :'wh'::uuid;
set local session_replication_role = origin;
select id::text as st_wms from public.ims_staff where auth_user_id = :'u_wms'::uuid \gset

-- ── G1 · G2 853 · 854 · 859 권한 ──
select pg_temp.chk('G1 catalog: freight_booking room ims · rooms ["wms","ims"] · 18 screens · label names booking',
  (public.ims_perm_catalog()->'screens'->'freight_booking'->>'room') || '/' || (public.ims_perm_catalog()->'screens'->'freight_booking'->'rooms')::text || '/' || (select count(*) from jsonb_object_keys(public.ims_perm_catalog()->'screens')) || '/' || ((public.ims_perm_catalog()->'screens'->'freight_booking'->>'label') like 'Freight booking%')::text,
  'ims/["wms", "ims"]/18/true');
select pg_temp.as_user(:'u_none'); select public.ims_can_write('freight_booking')::text as p1 \gset
select pg_temp.as_user(:'u_off');  select public.ims_can_write('freight_booking')::text as p2 \gset
select pg_temp.as_user(:'u_wms');  select public.ims_can_write('freight_booking')::text as p3 \gset
select pg_temp.as_user(:'u_book'); select public.ims_can_write('freight_booking')::text || '/' || public.ims_can_view('freight_booking')::text as p4 \gset
select pg_temp.as_user(:'u_adm');  select public.ims_can_write('freight_booking')::text as p5 \gset
select pg_temp.as_user(:'u_sup');  select public.ims_can_write('freight_booking')::text as p6 \gset
select pg_temp.chk('G2 853 · 854: picking worker · office (sales · master) · warehouse (fulfillment) = false · worker with the key = true (view too) · admin · supervisor = true by role',
  :'p1' || '/' || :'p2' || '/' || :'p3' || '/' || :'p4' || '/' || :'p5' || '/' || :'p6', 'false/false/false/true/true/true/true');
select pg_temp.chk('G2b sales · fulfillment unchanged for the booker (no sales · fulfillment yes) · u_off still sales',
  (select public.ims_can_write('sales')::text || '/' || public.ims_can_write('fulfillment')::text from (select pg_temp.as_user(:'u_book')) x) || '/' || (select public.ims_can_write('sales')::text from (select pg_temp.as_user(:'u_off')) y), 'false/true/true');

-- ── G3 857 창고 시간대 ──
select pg_temp.chk('G3 857: default timezone America/Toronto (wh) · Edmonton row (if any) = America/Regina · wh2 set to Regina · closes_at 17:00',
  (select w.timezone from public.ref_warehouse w where w.id = :'wh'::uuid) || '/' || coalesce((select w.timezone from public.ref_warehouse w where w.name ilike '%edmonton%' limit 1), 'America/Regina') || '/' || (select w.timezone || '/' || to_char(w.closes_at, 'HH24:MI') from public.ref_warehouse w where w.id = :'wh2'::uuid),
  'America/Toronto/America/Regina/America/Regina/17:00');
select pg_temp.chk('G3b unknown IANA name refused by trigger (person words) · America/Edmonton accepted',
  (pg_temp.try(format('update public.ref_warehouse set timezone = ''Mars/Olympus'' where id = %L returning timezone', :'wh2')) like 'ERR P0001: Time zone "Mars/Olympus" is not recognized — use an IANA name such as America/Toronto or America/Regina — nothing was saved')::text || '/' || pg_temp.try(format('update public.ref_warehouse set timezone = ''America/Edmonton'' where id = %L returning timezone', :'wh2')),
  'true/America/Edmonton');

-- ── G4 · G5 마감 셈 ──
select pg_temp.chk('G4 fc_cutoff_parse: fake 31-12-0000 → null · 04:30PM → 16:30 · 12:05AM → 00:05 · 12:05PM → 12:05 · lower-case pm · garbage → null · null → null',
  (public.fc_cutoff_parse('31-12-0000 06:42PM') is null)::text || '/' || public.fc_cutoff_parse('28-10-2026 04:30PM')::text || '/' || public.fc_cutoff_parse('28-10-2026 12:05AM')::text || '/' || public.fc_cutoff_parse('28-10-2026 12:05PM')::text || '/' || public.fc_cutoff_parse('28-10-2026 4:05 pm')::text || '/' || (public.fc_cutoff_parse('garbage') is null)::text || '/' || (public.fc_cutoff_parse(null) is null)::text,
  'true/16:30:00/00:05:00/12:05:00/16:05:00/true/true');
-- 857 핵심: 12 월 · Edmonton 창고 16:00 마감 — 토론토 17:00 = Regina 16:00 → 아직 안 지남 · 17:01 → 지남 · (America/Edmonton 이었다면 15:01 → 안 지남으로 잘못 본다)
select pg_temp.chk('G5 Dec · Edmonton(Regina) cutoff 16:00 · ship 2026-12-15: Toronto 17:00 → not past · 17:01 → past · July 17:00 Toronto (Regina 15:00) → not past',
  public.fc_past_cutoff(:'wh2'::uuid, '16:00', '2026-12-15', timestamptz '2026-12-15 17:00 America/Toronto')::text || '/' || public.fc_past_cutoff(:'wh2'::uuid, '16:00', '2026-12-15', timestamptz '2026-12-15 17:01 America/Toronto')::text || '/' ||
  public.fc_past_cutoff(:'wh2'::uuid, '16:00', '2026-07-15', timestamptz '2026-07-15 17:00 America/Toronto')::text, 'false/true/false');
set local session_replication_role = replica;
update public.ref_warehouse set timezone = 'America/Edmonton' where id = :'wh2'::uuid;
set local session_replication_role = origin;
select pg_temp.chk('G5b the same moment with the old-data America/Edmonton would read 15:01 → not past (why 857 says Regina)', public.fc_past_cutoff(:'wh2'::uuid, '16:00', '2026-12-15', timestamptz '2026-12-15 17:01 America/Toronto')::text, 'false');
set local session_replication_role = replica;
update public.ref_warehouse set timezone = 'America/Regina' where id = :'wh2'::uuid;
set local session_replication_role = origin;
select pg_temp.chk('G5c Toronto wh cutoff 16:00: 17:00 → past · 16:00 sharp → not past · ship tomorrow → not past · ship yesterday → past · cutoff null → false · ship_date null = that day',
  public.fc_past_cutoff(:'wh'::uuid, '16:00', '2026-12-15', timestamptz '2026-12-15 17:00 America/Toronto')::text || '/' || public.fc_past_cutoff(:'wh'::uuid, '16:00', '2026-12-15', timestamptz '2026-12-15 16:00 America/Toronto')::text || '/' ||
  public.fc_past_cutoff(:'wh'::uuid, '16:00', '2026-12-16', timestamptz '2026-12-15 17:00 America/Toronto')::text || '/' || public.fc_past_cutoff(:'wh'::uuid, '16:00', '2026-12-14', timestamptz '2026-12-15 09:00 America/Toronto')::text || '/' ||
  public.fc_past_cutoff(:'wh'::uuid, null, '2026-12-14', timestamptz '2026-12-15 09:00 America/Toronto')::text || '/' || public.fc_past_cutoff(:'wh'::uuid, '16:00', null, timestamptz '2026-12-15 17:00 America/Toronto')::text, 'true/false/false/true/false/true');
select pg_temp.chk('G5d midnight edge: Toronto 2026-12-15 23:30 = Regina 22:30 (same day) → ship 12-15 cutoff 23:00 past · Toronto 00:30 12-16 = Regina 23:30 12-15 → ship 12-15 not past (day not over in Regina)',
  public.fc_past_cutoff(:'wh2'::uuid, '23:00', '2026-12-15', timestamptz '2026-12-15 23:30 America/Toronto')::text || '/' || public.fc_past_cutoff(:'wh2'::uuid, '23:45', '2026-12-15', timestamptz '2026-12-16 00:30 America/Toronto')::text, 'false/false');

-- ── G6 852 ref_carrier_pickup_set ──
select pg_temp.as_user(:'u_none');
select pg_temp.chk('G6a picking worker refused', (pg_temp.try(format('select public.ref_carrier_pickup_set(%L, %L, ''{"regular_pickup": true}'')::text', :'car_a', :'wh')) like 'ERR P0001: You cannot change carrier pickup settings — ask an admin to add the ''master'' or ''fulfillment'' permission — nothing was saved')::text, 'true');
select pg_temp.as_user(:'u_wms');
select pg_temp.chk('G6b fulfillment on another warehouse refused', pg_temp.try(format('select public.ref_carrier_pickup_set(%L, %L, ''{"regular_pickup": true}'')::text', :'car_a', :'wh2')), 'ERR P0001: This warehouse is not yours — nothing was saved');
select public.ref_carrier_pickup_set(:'car_a'::uuid, :'wh'::uuid, '{"regular_pickup": true, "cutoff": "16:00", "note": "  daily UPS pickup  "}'::jsonb) as g6c \gset
select pg_temp.chk('G6c fulfillment on own warehouse: row made · regular true · cutoff 16:00 · note trimmed · names · timezone · updated_by = staff',
  (:'g6c'::jsonb->>'regular_pickup') || '/' || (:'g6c'::jsonb->>'cutoff') || '/' || (:'g6c'::jsonb->>'note') || '/' || (:'g6c'::jsonb->>'carrier') || '/' || (:'g6c'::jsonb->>'warehouse') || '/' || (:'g6c'::jsonb->>'timezone') || '/' ||
  (select (k.updated_by::text = :'st_wms')::text from public.ref_carrier_pickup k where k.carrier_id = :'car_a'::uuid and k.warehouse_id = :'wh'::uuid), 'true/16:00/daily UPS pickup/FCX Alpha Carrier/FCX Warehouse/America/Toronto/true');
select pg_temp.as_user(:'u_off');
select pg_temp.chk('G6d master on wh2: cutoff 18:00 after closes 17:00 → refused · bad text → refused · Pickup kind carrier → refused · unknown warehouse → refused',
  pg_temp.try(format('select public.ref_carrier_pickup_set(%L, %L, ''{"cutoff": "18:00"}'')::text', :'car_b', :'wh2')) || ' | ' || pg_temp.try(format('select public.ref_carrier_pickup_set(%L, %L, ''{"cutoff": "4pm"}'')::text', :'car_b', :'wh2')) || ' | ' ||
  (pg_temp.try(format('select public.ref_carrier_pickup_set((select id from public.ref_carrier where kind = ''pickup'' limit 1), %L, ''{}'')::text', :'wh2')) like 'ERR P0001: Carrier % is not on the carrier list (Pickup · Delivery have no pickup settings) — nothing was saved')::text || ' | ' ||
  (pg_temp.try(format('select public.ref_carrier_pickup_set(%L, %L, ''{}'')::text', :'car_b', gen_random_uuid())) like 'ERR P0001: Warehouse % not found — nothing was saved')::text,
  'ERR P0001: Cutoff 18:00 is after FCX Warehouse 2 closes (17:00) — nothing was saved | ERR P0001: Cutoff "4pm" must be a time like 16:30 (24-hour) — nothing was saved | true | true');
select public.ref_carrier_pickup_set(:'car_b'::uuid, :'wh2'::uuid, '{"cutoff": "17:00"}'::jsonb) as g6e \gset
select pg_temp.chk('G6e cutoff = closes_at allowed · regular defaults false · note null', (:'g6e'::jsonb->>'cutoff') || '/' || (:'g6e'::jsonb->>'regular_pickup') || '/' || coalesce(:'g6e'::jsonb->>'note', '(null)'), '17:00/false/(null)');
select public.ref_carrier_pickup_set(:'car_a'::uuid, :'wh'::uuid, '{"cutoff": ""}'::jsonb) as g6f \gset
select pg_temp.chk('G6f patch: empty cutoff clears it · regular_pickup · note untouched (keys absent)', coalesce(:'g6f'::jsonb->>'cutoff', '(null)') || '/' || (:'g6f'::jsonb->>'regular_pickup') || '/' || (:'g6f'::jsonb->>'note'), '(null)/true/daily UPS pickup');
select public.ref_carrier_pickup_set(:'car_b'::uuid, :'wh2'::uuid, '{"delete": true}'::jsonb) as g6g \gset
select pg_temp.chk('G6g delete → deleted true · row gone · delete again → deleted false', (:'g6g'::jsonb->>'deleted') || '/' || (select count(*) from public.ref_carrier_pickup k where k.carrier_id = :'car_b'::uuid and k.warehouse_id = :'wh2'::uuid) || '/' || ((public.ref_carrier_pickup_set(:'car_b'::uuid, :'wh2'::uuid, '{"delete": true}'::jsonb))->>'deleted'), 'true/0/false');
select pg_temp.chk('G6h table acl: authenticated · service_role select only · anon nothing · RLS on · direct insert by authenticated → 42501',
  (select relacl::text from pg_class where oid = 'public.ref_carrier_pickup'::regclass) || '/' || (select relrowsecurity::text from pg_class where oid = 'public.ref_carrier_pickup'::regclass) || '/' ||
  pg_temp.try2('set local role authenticated', format('insert into public.ref_carrier_pickup (carrier_id, warehouse_id) values (%L, %L) returning carrier_id::text', :'car_g', :'wh')),
  '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres}/true/ERR 42501: permission denied for table ref_carrier_pickup');

-- ── G7 fc_cutoff_eval ──
select public.ref_carrier_pickup_set(:'car_a'::uuid, :'wh'::uuid, '{"cutoff": "16:00"}'::jsonb) as g7 \gset
select pg_temp.chk('G7 eval: fake Freightcom time → IMS 16:00 (ims · regular true) · real Freightcom 15:00 beats IMS (freightcom) · no row (Gamma) → null · regular false · timezone · past at injected now',
  (select (e->>'cutoff') || '/' || (e->>'cutoff_source') || '/' || (e->>'regular_pickup') || '/' || (e->>'past_cutoff') from public.fc_cutoff_eval(:'wh'::uuid, :'car_a'::uuid, '31-12-0000 06:42PM', '2026-12-15', timestamptz '2026-12-15 16:30 America/Toronto') e) || ' | ' ||
  (select (e->>'cutoff') || '/' || (e->>'cutoff_source') || '/' || (e->>'past_cutoff') from public.fc_cutoff_eval(:'wh'::uuid, :'car_a'::uuid, '15-12-2026 03:00PM', '2026-12-15', timestamptz '2026-12-15 15:30 America/Toronto') e) || ' | ' ||
  (select coalesce(e->>'cutoff', '(null)') || '/' || coalesce(e->>'cutoff_source', '(null)') || '/' || (e->>'regular_pickup') || '/' || (e->>'past_cutoff') || '/' || (e->>'timezone') || '/' || (e->>'local_now') from public.fc_cutoff_eval(:'wh'::uuid, :'car_g'::uuid, '31-12-0000 06:42PM', '2026-12-15', timestamptz '2026-12-15 15:30 America/Toronto') e),
  '16:00/ims/true/true | 15:00/freightcom/true | (null)/(null)/false/false/America/Toronto/2026-12-15 15:30');

-- ── G8 quote_save: cutoff columns · 미리 고르기에서 마감 지난 줄 제외(843 다음) · for_so 표시 · 고를 수는 있다 ──
select public.ref_carrier_pickup_set(:'car_b'::uuid, :'wh'::uuid, '{"cutoff": "09:00"}'::jsonb) as g8p \gset
select (public.ims_today() + 1)::text as tomorrow, (public.ims_today() - 1)::text as yesterday \gset
select public.fc_shipment_prepare(array[:'s1'::uuid], jsonb_build_object('ship_date', :'tomorrow'), true) as r8 \gset
\set rates8 '{"rates": [ {"service_id": "fcxalpha.std", "carrier_name": "Fcx Alpha", "service_name": "Standard", "base": {"currency": "CAD", "value": "2500"}, "surcharges": [], "taxes": [], "total": {"currency": "CAD", "value": "2500"}, "transit_time_days": 3, "carrier_cut_off_time": "15-12-2026 03:00PM"}, {"service_id": "fcxalpha.exp", "carrier_name": "Fcx Alpha", "service_name": "Express", "base": {"currency": "CAD", "value": "4000"}, "surcharges": [], "taxes": [], "total": {"currency": "CAD", "value": "4000"}, "carrier_cut_off_time": "31-12-0000 06:42PM"}, {"service_id": "fcxbeta.std", "carrier_name": "Fcx Beta", "service_name": "Standard", "base": {"currency": "CAD", "value": "3000"}, "surcharges": [], "taxes": [], "total": {"currency": "CAD", "value": "3000"}, "carrier_cut_off_time": "31-12-0000 06:42PM"}, {"service_id": "fcxgamma.exp", "carrier_name": "Fcx Gamma", "service_name": "Express", "base": {"currency": "CAD", "value": "1000"}, "surcharges": [], "taxes": [], "total": {"currency": "CAD", "value": "1000"}}, {"service_id": "unk.x", "carrier_name": "Unknown Carrier", "service_name": "X", "base": {"currency": "CAD", "value": "900"}, "surcharges": [], "taxes": [], "total": {"currency": "CAD", "value": "900"}} ]}'
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_quote_save((:'r8'::jsonb->>'shipment_id')::uuid, 'req-2a-1', :'rates8'::jsonb) as q8a \gset
select pg_temp.chk('G8a ship tomorrow: 5 rates · past_cutoff_rates 0 · ship_date returned · preselected = default carrier Beta (843 unchanged) · columns: Alpha std 15:00 freightcom · Alpha exp 16:00 ims · Beta 09:00 ims · Gamma null · Unknown null',
  (:'q8a'::jsonb->>'rates') || '/' || (:'q8a'::jsonb->>'past_cutoff_rates') || '/' || (:'q8a'::jsonb->>'ship_date') || '/' || (select r.service_id from public.fc_quote_rate r where r.quote_id = (:'q8a'::jsonb->>'quote_id')::uuid and r.preselected) || '/' ||
  (select string_agg(r.service_id || '=' || coalesce(to_char(r.cutoff, 'HH24:MI'), '-') || ':' || coalesce(r.cutoff_source, '-'), ' ' order by r.service_id) from public.fc_quote_rate r where r.quote_id = (:'q8a'::jsonb->>'quote_id')::uuid),
  '5/0/' || :'tomorrow' || '/fcxbeta.std/fcxalpha.exp=16:00:ims fcxalpha.std=15:00:freightcom fcxbeta.std=09:00:ims fcxgamma.exp=-:- unk.x=-:-');
set local session_replication_role = replica;
update public.fc_shipment set options = jsonb_set(options, '{ship_date}', to_jsonb(:'yesterday'::text)) where id = (:'r8'::jsonb->>'shipment_id')::uuid;
set local session_replication_role = origin;
select public.fc_quote_save((:'r8'::jsonb->>'shipment_id')::uuid, 'req-2a-2', :'rates8'::jsonb) as q8b \gset
select pg_temp.chk('G8b ship yesterday: 3 rates past (both Alpha · Beta) · default carrier Beta past → not used · Gamma avoided · Unknown unpaired → preselected none',
  (:'q8b'::jsonb->>'past_cutoff_rates') || '/' || coalesce(:'q8b'::jsonb->>'preselected_rate_id', '(null)') || '/' || (select count(*) from public.fc_quote_rate r where r.quote_id = (:'q8b'::jsonb->>'quote_id')::uuid and r.preselected), '3/(null)/0');
select pg_temp.as_user(:'u_off');
select public.fc_shipment_for_so(:'s1'::uuid) as f8 \gset
select pg_temp.chk('G8c for_so: rates carry cutoff · cutoff_source · past_cutoff (now · Toronto) · regular_pickup (Alpha true · Beta false) · shipment ship_date · warehouse_timezone · closes_at · local_now present · selected null',
  (select string_agg((r->>'service_id') || '=' || coalesce(r->>'cutoff', '-') || ':' || coalesce(r->>'cutoff_source', '-') || ':' || (r->>'past_cutoff') || ':' || (r->>'regular_pickup'), ' ' order by r->>'service_id') from jsonb_array_elements(:'f8'::jsonb#>'{quote,rates}') r) || ' | ' ||
  (:'f8'::jsonb#>>'{shipment,ship_date}') || '/' || (:'f8'::jsonb#>>'{shipment,warehouse_timezone}') || '/' || (:'f8'::jsonb#>>'{shipment,warehouse_closes_at}') || '/' || ((:'f8'::jsonb#>>'{shipment,local_now}') ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')::text || '/' || (:'f8'::jsonb->'selected')::text,
  'fcxalpha.exp=16:00:ims:true:true fcxalpha.std=15:00:freightcom:true:true fcxbeta.std=09:00:ims:true:false fcxgamma.exp=-:-:false:false unk.x=-:-:false:false | ' || :'yesterday' || '/America/Toronto/17:00/true/null');
select public.fc_quote_select((:'r8'::jsonb->>'shipment_id')::uuid, (select r.id from public.fc_quote_rate r where r.quote_id = (:'q8b'::jsonb->>'quote_id')::uuid and r.service_id = 'fcxalpha.std')) as s8 \gset
select public.fc_shipment_for_so(:'s1'::uuid) as f8b \gset
select pg_temp.chk('G8d a past-cutoff rate can still be chosen (852 「고를 수는 있음」) → selected · selected.cutoff 15:00 freightcom · past true · regular true',
  (:'f8b'::jsonb#>>'{shipment,status}') || '/' || (:'f8b'::jsonb#>>'{selected,cutoff}') || '/' || (:'f8b'::jsonb#>>'{selected,cutoff_source}') || '/' || (:'f8b'::jsonb#>>'{selected,past_cutoff}') || '/' || (:'f8b'::jsonb#>>'{selected,regular_pickup}'), 'selected/15:00/freightcom/true/true');
select pg_temp.chk('G8e rate ordering unchanged (avoided last · unpaired before avoided · cheapest first) · pair CHECK: cutoff without source refused',
  (select string_agg(r->>'service_id', ',') from jsonb_array_elements(:'f8b'::jsonb#>'{quote,rates}') r) || ' | ' || (pg_temp.try(format('update public.fc_quote_rate set cutoff_source = null where quote_id = %L and service_id = ''fcxbeta.std'' returning service_id', :'q8b'::jsonb->>'quote_id')) like 'ERR 23514: %fc_quote_rate_cutoff_pair_ck%')::text,
  'fcxalpha.std,fcxbeta.std,fcxalpha.exp,unk.x,fcxgamma.exp | true');
-- 옛 발송(options 에 ship_date 없음)도 저장된다 — ship_date null · past 는 「그날 = 오늘」 로 센다(값은 시각에 따라 달라 묻지 않는다)
set local session_replication_role = replica;
update public.fc_shipment set options = options - 'ship_date' where id = (:'r8'::jsonb->>'shipment_id')::uuid;
set local session_replication_role = origin;
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_quote_save((:'r8'::jsonb->>'shipment_id')::uuid, 'req-2a-3', :'rates8'::jsonb) as q8c \gset
select pg_temp.chk('G9 options without ship_date: saved · 5 rates · ship_date null · for_so shipment.ship_date null', (:'q8c'::jsonb->>'rates') || '/' || (:'q8c'::jsonb->'ship_date')::text || '/' || ((public.fc_shipment_for_so(:'s1'::uuid))#>'{shipment,ship_date}')::text, '5/null/null');
select pg_temp.as_user(:'u_off');

-- ── G10 재발행 · 무접촉 · 함수 권한 ──
select pg_temp.chk('G10 reissued 3 (md5 · one each): fc_quote_save · fc_shipment_for_so · ims_perm_catalog · untouched: ims_can_write · fc_shipment_prepare · fc_quote_select · so_finalize',
  (select md5(prosrc) || '/' || count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_quote_save' group by prosrc) || '/' ||
  (select md5(prosrc) || '/' || count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_for_so' group by prosrc) || '/' ||
  (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_perm_catalog') || '/' ||
  (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_can_write') || '/' || (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_prepare') || '/' ||
  (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_quote_select') || '/' || (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize'),
  '750a0fbacaa37d2215112a9b8308d0ce/1/83b5e899f8fd8ebcbe5d654a20b20c4a/1/e70510a8c5c161e64f1024bb856c31bf/82556f945f6acdecfc64043cba2a4ddc/2a2a0206f9f2b12320dd93f6467fa8fc/ca317868f2ecb6d2647439e9e370469e/' || :'fin_md5_0');
select pg_temp.chk('G10b function acl: ref_carrier_pickup_set authenticated only · fc_cutoff_eval authenticated (not anon · not service_role) · fc_cutoff_parse · fc_past_cutoff nobody but owner · fc_quote_save service_role kept · ref_warehouse_tz_check trigger present',
  has_function_privilege('authenticated', 'public.ref_carrier_pickup_set(uuid, uuid, jsonb)', 'execute')::text || has_function_privilege('anon', 'public.ref_carrier_pickup_set(uuid, uuid, jsonb)', 'execute')::text || has_function_privilege('service_role', 'public.ref_carrier_pickup_set(uuid, uuid, jsonb)', 'execute')::text || '/' ||
  has_function_privilege('authenticated', 'public.fc_cutoff_eval(uuid, uuid, text, date, timestamptz)', 'execute')::text || has_function_privilege('anon', 'public.fc_cutoff_eval(uuid, uuid, text, date, timestamptz)', 'execute')::text || has_function_privilege('service_role', 'public.fc_cutoff_eval(uuid, uuid, text, date, timestamptz)', 'execute')::text || '/' ||
  has_function_privilege('authenticated', 'public.fc_cutoff_parse(text)', 'execute')::text || has_function_privilege('authenticated', 'public.fc_past_cutoff(uuid, time, date, timestamptz)', 'execute')::text || '/' ||
  has_function_privilege('service_role', 'public.fc_quote_save(uuid, text, jsonb, text, jsonb)', 'execute')::text || '/' || (select count(*) from pg_trigger where tgrelid = 'public.ref_warehouse'::regclass and tgname = 'ref_warehouse_tz_check'),
  'truefalsefalse/truefalsefalse/falsefalse/true/1');

-- ── 결과 ──
select clock_timestamp() - :'t_begin0'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res where n > :n_1b5 or not ok order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok, :n_1b5 as from_fc_1b5 from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :x_so and (select count(*) from public.customer_address) = :x_addr and (select count(*) from public.fc_shipment) = :x_fc and (select count(*) from public.fc_quote) = :x_q and (select count(*) from public.fc_quote_rate) = :x_qr
             and (select count(*) from public.ims_staff) = :x_staff and (select count(*) from public.ref_carrier) = :x_car and (select count(*) from public.ref_warehouse) = :x_wh
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_for_so') = :'forso_md5_0' and (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_perm_catalog') = :'cat_md5_0'
             and to_regclass('public.ref_carrier_pickup') is null
       then 'Z2 OK rollback restored md5 · no table' else 'Z2 MISMATCH rollback did not restore' end as z2;
\endif
