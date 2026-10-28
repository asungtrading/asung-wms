-- supabase/tests/fc_2b_check.sql — fc-2b 예약 이력(fc_booking) · 라벨(fc_label) · 창구 일곱 검증 (2026-10-28 · 판정 835 · 837 · 851 ~ 858)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — begin → (-v mig 면 \i) → ⭐ fc_2a_check 사본(164) → H 갈래 → rollback → 실제 행 무변 · 표 없음 복귀
--   Claude Code(시험 · ⚠️ 레포 루트에서 — fixtures 를 \copy 로 읽는다): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028223000_fc_2b_booking_windows.sql -f supabase/tests/fc_2b_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험 · 확인 둘 다 EXPECT_OK = 164 + H · Z1 둘 다 · Z2 시험 갈래만
--   재료: 2a 사본의 가짜(FCX) — S1 상자(G9 뒤 quoted · 마지막 견적 q8c) · S4 팔렛 · car_a(wh · regular true · cutoff 16:00) · car_b(c_a 기본 운송사) · u_book(worker · fulfillment + freight_booking · wh) · u_off(sales · master) · u_wms(fulfillment) · u_none
--       + 레포 fixtures 실물 응답: book-package.json(UPS Standard · 라벨 5) · book-ltl-maritime.json(maritime.dry · BOL · 라벨 1)
\set ON_ERROR_STOP on
\set EXPECT_OK 193
\pset pager off
\! awk 'BEGIN{skip=0;done=0} /^\\if :\{\?mig\}/{skip=1;next} /^\\endif/{if(skip){skip=0;next}} /^-- ── 결과 ──/{done=1} done{next} skip{next} /^begin;$/{next} /^set local lock_timeout/{next} /^\\set EXPECT_OK/{next} {print}' supabase/tests/fc_2a_check.sql > /tmp/fc_2a-inner.sql
select (select count(*) from public.so) as w_so, (select count(*) from public.fc_shipment) as w_fc, (select count(*) from public.fc_quote) as w_q, (select count(*) from public.ims_staff) as w_staff, (select count(*) from public.ref_warehouse) as w_wh,
       (select count(*) from public.so where tracking_number is not null) as w_trk, (select count(*) from public.so where carrier_id is not null) as w_car \gset
\echo '── 기준: so' :w_so '· fc_shipment' :w_fc '· fc_quote' :w_q '· staff' :w_staff '· so with tracking' :w_trk '· with carrier' :w_car
create temp table fx_pkg (seq serial, line text);
create temp table fx_ltl (seq serial, line text);
\copy fx_pkg (line) from 'supabase/functions/freightcom/fixtures/book-package.json' with (format csv, quote e'\x01', delimiter e'\x02')
\copy fx_ltl (line) from 'supabase/functions/freightcom/fixtures/book-ltl-maritime.json' with (format csv, quote e'\x01', delimiter e'\x02')
select string_agg(line, E'\n' order by seq)::jsonb::text as fx1 from fx_pkg \gset
select string_agg(line, E'\n' order by seq)::jsonb::text as fx2 from fx_ltl \gset
\echo '── fixtures read:' :'fx1'
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin00 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
\echo '── fc_2a_check 속(사본 · 164)'
\i /tmp/fc_2a-inner.sql
select count(*) as n_2a from t_res \gset
\echo '── fc-2a inner done: rows' :n_2a

-- ── H0 재료: S1 고르기(q8c 의 Alpha std) · 전 값 담기 ──
select pg_temp.as_user(:'u_off');
select (:'r8'::jsonb->>'shipment_id') as sh1 \gset
select public.fc_quote_select(:'sh1'::uuid, (select r.id from public.fc_quote_rate r where r.quote_id = (:'q8c'::jsonb->>'quote_id')::uuid and r.service_id = 'fcxalpha.exp')) as sel1 \gset
select coalesce(s.carrier_id::text, '(null)') || '/' || coalesce(s.carrier, '(null)') || '/' || coalesce(s.tracking_number, '(null)') as s1_before, s.so_number as s1_num from public.so s where s.id = :'s1'::uuid \gset
select pg_temp.chk('H0 S1 selected (Alpha exp · car_a · fake Freightcom cutoff → IMS value rules) · fixtures parsed (package labels 5 · ltl labels 1)', (select f.status from public.fc_shipment f where f.id = :'sh1'::uuid) || '/' || jsonb_array_length(:'fx1'::jsonb#>'{shipment,labels}') || '/' || jsonb_array_length(:'fx2'::jsonb#>'{shipment,labels}'), 'selected/5/1');

-- ── H1 853 문 ──
select pg_temp.as_user(:'u_wms');
select pg_temp.chk('H1 fulfillment without the key → refused · picking worker → refused', (pg_temp.try(format('select public.fc_book_prepare(%L, ''{}'', false)::text', :'sh1')) like 'ERR P0001: You cannot book or cancel freight — ask an admin to add the ''freight_booking'' permission — nothing was saved')::text || '/' ||
  (select (pg_temp.try(format('select public.fc_book_prepare(%L, ''{}'', false)::text', :'sh1')) like 'ERR P0001: You cannot book or cancel freight%')::text from (select pg_temp.as_user(:'u_none')) x), 'true/true');
set local session_replication_role = replica;
update public.ims_staff set warehouse_access = array[:'wh2'::uuid] where auth_user_id = :'u_book'::uuid;
set local session_replication_role = origin;
select pg_temp.as_user(:'u_book');
select pg_temp.chk('H1b key holder of another warehouse → refused', pg_temp.try(format('select public.fc_book_prepare(%L, ''{}'', false)::text', :'sh1')), 'ERR P0001: This shipment belongs to another warehouse — nothing was saved');
set local session_replication_role = replica;
update public.ims_staff set warehouse_access = array[:'wh'::uuid] where auth_user_id = :'u_book'::uuid;
set local session_replication_role = origin;

-- ── H2 · H3 852 픽업 몸 ──
select (public.ims_today() + 1)::text as tmr \gset
select public.fc_book_prepare(:'sh1'::uuid, jsonb_build_object('date', :'tmr'), false) as h2 \gset
select pg_temp.chk('H2 preview (regular pickup carrier · date given): attempt 1 · unique_id = shipment id · service_id · pickup_details = {pre_scheduled_pickup:true} only · expected_ship_date = pickup date · details keep origin contact · no row · committed false',
  (:'h2'::jsonb->>'attempt') || '/' || ((:'h2'::jsonb->>'unique_id') = :'sh1')::text || '/' || (:'h2'::jsonb#>>'{request,service_id}') || '/' || (:'h2'::jsonb#>'{request,pickup_details}')::text || '/' || ((:'h2'::jsonb#>'{request}') ? 'dispatch_details')::text || '/' ||
  (:'h2'::jsonb#>>'{request,details,expected_ship_date,day}') || '/' || ((:'h2'::jsonb#>'{request,details,origin}') ? 'contact_name')::text || '/' || (:'h2'::jsonb#>>'{pickup,regular_pickup}') || '/' || (select count(*) from public.fc_booking) || '/' || (:'h2'::jsonb->>'committed'),
  '1/true/fcxalpha.exp/{"pre_scheduled_pickup": true}/false/' || extract(day from :'tmr'::date) || '/true/true/0/false');
select pg_temp.as_user(:'u_off');
select public.ref_carrier_pickup_set(:'car_a'::uuid, :'wh'::uuid, '{"regular_pickup": false, "cutoff": "00:00"}'::jsonb) as h3p \gset
select pg_temp.as_user(:'u_book');
select public.fc_book_prepare(:'sh1'::uuid, '{}'::jsonb, false) as h3 \gset
select pg_temp.chk('H3 no regular pickup · cutoff 00:00 already passed · no date given → moved to tomorrow + warning · pickup_details with date · ready_at 09:00 · ready_until = closes_at 17:00 · pre_scheduled false',
  (:'h3'::jsonb#>>'{pickup,date}') || '/' || (:'h3'::jsonb#>>'{pickup,ready_at}') || '/' || (:'h3'::jsonb#>>'{pickup,ready_until}') || '/' || (:'h3'::jsonb#>>'{request,pickup_details,pre_scheduled_pickup}') || '/' || (:'h3'::jsonb#>>'{request,pickup_details,ready_until,hour}') || '/' || (:'h3'::jsonb#>>'{request,pickup_details,date,day}') || '/' || ((:'h3'::jsonb#>>'{warnings,0}') like 'past_cutoff:00:00 — Fcx Alpha cutoff 00:00 has passed · pickup moved to %')::text,
  :'tmr' || '/09:00/17:00/false/17/' || extract(day from :'tmr'::date) || '/true');
select pg_temp.chk('H3b empty window · bad ready_at · past date → refused',
  pg_temp.try(format('select public.fc_book_prepare(%L, ''{"ready_at": "18:00"}'', false)::text', :'sh1')) || ' | ' || pg_temp.try(format('select public.fc_book_prepare(%L, ''{"ready_at": "9am"}'', false)::text', :'sh1')) || ' | ' || (pg_temp.try(format('select public.fc_book_prepare(%L, ''{"date": "2026-01-01"}'', false)::text', :'sh1')) like 'ERR P0001: Pickup date 2026-01-01 has passed (today at the warehouse is %')::text,
  'ERR P0001: Pickup window 18:00 ~ 17:00 is empty — nothing was saved | ERR P0001: ready_at "9am" must be a time like 10:30 — nothing was saved | true');
set local session_replication_role = replica;
update public.ref_warehouse set closes_at = null where id = :'wh'::uuid;
set local session_replication_role = origin;
select pg_temp.chk('H3c warehouse without closes_at → refused unless ready_until given', pg_temp.try(format('select public.fc_book_prepare(%L, ''{}'', false)::text', :'sh1')) || ' | ' || (pg_temp.try(format('select public.fc_book_prepare(%L, ''{"ready_until": "16:00"}'', false)::text', :'sh1'))::jsonb#>>'{pickup,ready_until}'),
  'ERR P0001: Set the closing time of FCX Warehouse (Settings → Warehouses) or give ready_until — nothing was saved | 16:00');
set local session_replication_role = replica;
update public.ref_warehouse set closes_at = '17:00' where id = :'wh'::uuid;
set local session_replication_role = origin;

-- ── H4 · H5 유닛 바뀜 · 만료 ──
select pg_temp.as_user(:'u_off');
select public.wms_unit_dims_set(:'b1'::bigint, '{"dim_length": "14"}'::jsonb) as d1 \gset
select pg_temp.as_user(:'u_book');
select pg_temp.try(format('select public.fc_book_prepare(%L, ''{}'', false)::text', :'sh1')) as h4a \gset
select pg_temp.as_user(:'u_off');
select public.wms_unit_dims_set(:'b1'::bigint, '{"dim_length": "13"}'::jsonb) as d2 \gset
select pg_temp.as_user(:'u_book');
select pg_temp.chk('H4 units changed since the quote → refused · set back → ok', :'h4a' || ' | ' || (pg_temp.try(format('select public.fc_book_prepare(%L, ''{}'', false)::text', :'sh1')) like '{%')::text, 'ERR P0001: The boxes or pallets changed since this quote — quote again — nothing was saved | true');
set local session_replication_role = replica;
update public.fc_quote_rate set valid_until = public.ims_today() - 1 where id = (:'sel1'::jsonb->>'selected_rate_id')::uuid;
set local session_replication_role = origin;
select pg_temp.chk('H5 quote expired → refused', (pg_temp.try(format('select public.fc_book_prepare(%L, ''{}'', false)::text', :'sh1')) like 'ERR P0001: The quote expired on % — quote again — nothing was saved')::text, 'true');
set local session_replication_role = replica;
update public.fc_quote_rate set valid_until = null where id = (:'sel1'::jsonb->>'selected_rate_id')::uuid;
set local session_replication_role = origin;

-- ── H6 · H7 pending → booked(실물 응답 · 상자) · 855 ──
select public.fc_book_prepare(:'sh1'::uuid, '{}'::jsonb, true) as h6 \gset
select pg_temp.chk('H6 commit: pending row · attempt 1 · unique_id = id · fc_shipment.booking_id · status stays selected · request · pickup saved · requested_by = booker · second prepare → in progress',
  (select b.status || '/' || b.attempt || '/' || (b.unique_id = :'sh1')::text || '/' || (b.request->>'unique_id' = :'sh1')::text || '/' || (b.pickup->>'ready_until') || '/' || (b.requested_by::text = :'st_book')::text from public.fc_booking b where b.id = (:'h6'::jsonb->>'booking_id')::uuid) || '/' ||
  (select (f.booking_id::text = (:'h6'::jsonb->>'booking_id'))::text || '/' || f.status from public.fc_shipment f where f.id = :'sh1'::uuid) || ' | ' || pg_temp.try(format('select public.fc_book_prepare(%L, ''{}'', true)::text', :'sh1')),
  'pending/1/true/true/17:00/true/true/selected | ERR P0001: A booking attempt (#1) is still in progress — use Check again or wait a few minutes — nothing was saved');
set local session_replication_role = replica;
update public.fc_booking set requested_at = now() - interval '11 minutes' where id = (:'h6'::jsonb->>'booking_id')::uuid;
set local session_replication_role = origin;
select public.fc_book_prepare(:'sh1'::uuid, '{}'::jsonb, false) as h6b \gset
select pg_temp.chk('H6b pending older than 10 min: preview sets it aside (warning · attempt 2 · unique_id -2) · no write in preview', (:'h6b'::jsonb->>'attempt') || '/' || (:'h6b'::jsonb->>'unique_id') || '/' || (exists (select 1 from jsonb_array_elements_text(:'h6b'::jsonb->'warnings') w where w like 'abandoned:1 — %'))::text || '/' || (select b.status from public.fc_booking b where b.id = (:'h6'::jsonb->>'booking_id')::uuid), '2/' || :'sh1' || '-2/true/pending');
select pg_temp.chk('H7a save by a person (authenticated) → refused', pg_temp.try(format('select public.fc_book_save(%L, %L::jsonb)::text', :'h6'::jsonb->>'booking_id', :'fx1')), 'ERR P0001: fc_book_save is for the freight service only — nothing was saved');
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_book_save((:'h6'::jsonb->>'booking_id')::uuid, :'fx1'::jsonb) as h7 \gset
select pg_temp.chk('H7 save (package fixture): booked · Freightcom id · transaction · tracking primary + list 1 · url · bol null · pickup_confirmation null · labels 5 (letter pdf ×2 · a6 zpl · a6 pdf · a6 pdf padded) · orders_written = S1 · no warnings',
  (:'h7'::jsonb->>'status') || '/' || (:'h7'::jsonb->>'freightcom_shipment_id') || '/' || (:'h7'::jsonb->>'transaction_number') || '/' || (:'h7'::jsonb->>'tracking_number') || '/' || jsonb_array_length(:'h7'::jsonb->'tracking_numbers') || '/' || (:'h7'::jsonb->>'tracking_url') || '/' || coalesce(:'h7'::jsonb->>'bol_number', '(null)') || '/' || coalesce(:'h7'::jsonb->>'pickup_confirmation', '(null)') || '/' ||
  (select string_agg((l->>'size') || ':' || (l->>'format') || ':' || (l->>'padded'), ',') from jsonb_array_elements(:'h7'::jsonb->'labels') l) || '/' || (:'h7'::jsonb->'orders_written')::text || '/' || (:'h7'::jsonb->'warnings')::text,
  'booked/CbeeOPfzfSDUI1ajuQCx8NwjElun7pm4/20120444/1ZXXXXXXXXXXXXXXXX/1/https://www.ups.com/WebTracking?trackingNumber=1ZXXXXXXXXXXXXXXXX/(null)/(null)/letter:pdf:false,a6:zpl:false,letter:pdf:false,a6:pdf:false,a6:pdf:true/["' || :'s1_num' || '"]/[]');
select pg_temp.chk('H7b 855 SO S1: carrier_id = Alpha · carrier = name · tracking written · so_written keeps before + written · shipment booked · booking_id · response kept · state waiting-for-transit',
  (select (s.carrier_id::text = :'car_a')::text || '/' || s.carrier || '/' || s.tracking_number from public.so s where s.id = :'s1'::uuid) || '/' ||
  (select (b.so_written->0->>'so_number') || '/' || coalesce(b.so_written#>>'{0,before,carrier_id}', '(null)') || '/' || coalesce(b.so_written#>>'{0,before,carrier}', '(null)') || '/' || coalesce(b.so_written#>>'{0,before,tracking_number}', '(null)') || '/' || (b.so_written#>>'{0,written,tracking_number}') || '/' || b.state || '/' || (b.response#>>'{shipment,id}') from public.fc_booking b where b.id = (:'h6'::jsonb->>'booking_id')::uuid) || '/' ||
  (select f.status || '/' || (f.booking_id::text = (:'h6'::jsonb->>'booking_id'))::text from public.fc_shipment f where f.id = :'sh1'::uuid),
  'true/FCX Alpha Carrier/1ZXXXXXXXXXXXXXXXX/' || :'s1_num' || '/' || :'s1_before' || '/1ZXXXXXXXXXXXXXXXX/waiting-for-transit/CbeeOPfzfSDUI1ajuQCx8NwjElun7pm4/booked/true');
select pg_temp.chk('H8 while booked: book_prepare · fc_shipment_prepare (quote) · fc_quote_save · save again → all refused',
  (select pg_temp.try(format('select public.fc_book_prepare(%L, ''{}'', false)::text', :'sh1')) from (select pg_temp.as_user(:'u_book')) a) || ' | ' || (pg_temp.try(format('select public.fc_shipment_prepare(array[%L]::uuid[], ''{}'', false)::text', :'s1')) like 'ERR P0001: Orders % are on a booked shipment — cancel the booking first — nothing was saved')::text || ' | ' ||
  (select pg_temp.try(format('select public.fc_quote_save(%L, ''req-x'', %L::jsonb)::text', :'sh1', :'rates8')) from (select pg_temp.as_user(:'u_none', 'service_role')) b) || ' | ' || pg_temp.try(format('select public.fc_book_save(%L, %L::jsonb)::text', :'h6'::jsonb->>'booking_id', :'fx1')),
  'ERR P0001: This shipment is already booked — cancel the booking first — nothing was saved | true | ERR P0001: Shipment is booked — no new quotes — nothing was saved | ERR P0001: Booking #1 is already booked — nothing was saved');

-- ── H9 · H10 취소(사람이 바꾼 추적번호는 둔다 · 856 selected) ──
select pg_temp.as_user(:'u_wms');
select pg_temp.chk('H9 cancel_prepare without the key → refused', (pg_temp.try(format('select public.fc_book_cancel_prepare(%L)::text', :'sh1')) like 'ERR P0001: You cannot book or cancel freight%nothing was changed')::text, 'true');
select pg_temp.as_user(:'u_book');
select public.fc_book_cancel_prepare(:'sh1'::uuid) as h9 \gset
select pg_temp.chk('H9b cancel_prepare (booker): booking · Freightcom id · account · carrier · no write', ((:'h9'::jsonb->>'booking_id') = (:'h6'::jsonb->>'booking_id'))::text || '/' || (:'h9'::jsonb->>'freightcom_shipment_id') || '/' || ((:'h9'::jsonb->>'account') = (select f.freightcom_account from public.fc_shipment f where f.id = :'sh1'::uuid))::text || '/' || (:'h9'::jsonb->>'carrier_name') || '/' || (select f.status from public.fc_shipment f where f.id = :'sh1'::uuid), 'true/CbeeOPfzfSDUI1ajuQCx8NwjElun7pm4/true/FCX Alpha Carrier/booked');
set local session_replication_role = replica;
update public.so set tracking_number = '1ZMANUAL' where id = :'s1'::uuid;
set local session_replication_role = origin;
select pg_temp.chk('H10a cancel_save by a person → refused · Freightcom refusal (p_error) keeps the booking + cancel_error', pg_temp.try(format('select public.fc_book_cancel_save(%L)::text', :'h6'::jsonb->>'booking_id')) || ' | ' ||
  (select (pg_temp.try(format('select public.fc_book_cancel_save(%L, null, ''HTTP 403 permission denied'')::text', :'h6'::jsonb->>'booking_id'))::jsonb->>'status') from (select pg_temp.as_user(:'u_none', 'service_role')) a),
  'ERR P0001: fc_book_cancel_save is for the freight service only — nothing was saved | booked');
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_book_cancel_save((:'h6'::jsonb->>'booking_id')::uuid, jsonb_build_object('cancelled_by', :'st_book', 'state', 'cancelled')) as h10 \gset
select pg_temp.chk('H10 cancel_save: booking cancelled (by booker) · shipment selected · rate kept · 855 tracking changed by a person → orders_kept · SO tracking 1ZMANUAL · carrier untouched · cancel_error cleared',
  (:'h10'::jsonb->>'status') || '/' || (:'h10'::jsonb->>'shipment_status') || '/' || (:'h10'::jsonb->'orders_restored')::text || '/' || (:'h10'::jsonb->'orders_kept')::text || '/' ||
  (select b.status || '/' || (b.cancelled_by::text = :'st_book')::text || '/' || coalesce(b.cancel_error, '(null)') || '/' || (b.response->>'state') from public.fc_booking b where b.id = (:'h6'::jsonb->>'booking_id')::uuid) || '/' ||
  (select f.status || '/' || (f.selected_rate_id = (:'sel1'::jsonb->>'selected_rate_id')::uuid)::text from public.fc_shipment f where f.id = :'sh1'::uuid) || '/' || (select s.tracking_number || '/' || (s.carrier_id::text = :'car_a')::text from public.so s where s.id = :'s1'::uuid),
  'cancelled/selected/[]/["' || :'s1_num' || '"]/cancelled/true/(null)/cancelled/selected/true/1ZMANUAL/true');

-- ── H11 · H12 다시 예약: attempt 2 실패(400 booking carrier) → attempt 3 booked · shipped 뒤 취소 거부 · 이력 ──
select pg_temp.as_user(:'u_book');
select public.fc_book_prepare(:'sh1'::uuid, '{}'::jsonb, true) as h11 \gset
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_book_save((:'h11'::jsonb->>'booking_id')::uuid, '{"message": "bad or missing data", "data": {"booking": "carrier"}}'::jsonb, 'Freightcom book 400: bad or missing data (booking: carrier)') as h11s \gset
select pg_temp.chk('H11 attempt 2 (unique_id -2) fails with 400 booking carrier → failed row · error · body kept · shipment selected · booking_id = failed attempt · SO untouched · cancel_prepare → nothing to cancel',
  (:'h11'::jsonb->>'attempt') || '/' || (:'h11'::jsonb->>'unique_id') || '/' || (:'h11s'::jsonb->>'status') || '/' || (select b.status || '/' || (b.failed_at is not null)::text || '/' || (b.response#>>'{data,booking}') || '/' || left(b.error, 22) from public.fc_booking b where b.id = (:'h11'::jsonb->>'booking_id')::uuid) || '/' ||
  (select f.status || '/' || (f.booking_id::text = (:'h11'::jsonb->>'booking_id'))::text from public.fc_shipment f where f.id = :'sh1'::uuid) || '/' || (select s.tracking_number from public.so s where s.id = :'s1'::uuid) || ' | ' ||
  (select pg_temp.try(format('select public.fc_book_cancel_prepare(%L)::text', :'sh1')) from (select pg_temp.as_user(:'u_book')) a),
  '2/' || :'sh1' || '-2/failed/failed/true/carrier/Freightcom book 400: b/selected/true/1ZMANUAL | ERR P0001: The last attempt (#2) failed — there is nothing to cancel at Freightcom — nothing was changed');
select pg_temp.as_user(:'u_book');
select public.fc_book_prepare(:'sh1'::uuid, '{}'::jsonb, true) as h12 \gset
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_book_save((:'h12'::jsonb->>'booking_id')::uuid, :'fx1'::jsonb) as h12s \gset
select pg_temp.chk('H12 attempt 3 (unique_id -3) booked again · SO tracking overwritten (1ZMANUAL → booked value · before snapshot = 1ZMANUAL) · unique ids distinct',
  (:'h12'::jsonb->>'attempt') || '/' || (:'h12'::jsonb->>'unique_id') || '/' || (:'h12s'::jsonb->>'status') || '/' || (select s.tracking_number from public.so s where s.id = :'s1'::uuid) || '/' || (select b.so_written#>>'{0,before,tracking_number}' from public.fc_booking b where b.id = (:'h12'::jsonb->>'booking_id')::uuid) || '/' ||
  (select count(distinct unique_id) || '/' || count(*) from public.fc_booking b where b.shipment_id = :'sh1'::uuid), '3/' || :'sh1' || '-3/booked/1ZXXXXXXXXXXXXXXXX/1ZMANUAL/3/3');
set local session_replication_role = replica;
update public.so set status = 'shipped' where id = :'s1'::uuid;
set local session_replication_role = origin;
select pg_temp.as_user(:'u_book');
select pg_temp.chk('H12b order shipped → cancel_prepare refused · book_prepare on a shipped order refused too (shipment already booked wins)', pg_temp.try(format('select public.fc_book_cancel_prepare(%L)::text', :'sh1')) || ' | ' || pg_temp.try(format('select public.fc_book_prepare(%L, ''{}'', false)::text', :'sh1')),
  'ERR P0001: Orders ' || :'s1_num' || ' have already shipped — the booking cannot be cancelled from IMS — nothing was changed | ERR P0001: This shipment is already booked — cancel the booking first — nothing was saved');
set local session_replication_role = replica;
update public.so set status = 'packed' where id = :'s1'::uuid;
set local session_replication_role = origin;
select public.fc_booking_for_shipment(:'sh1'::uuid) as h12f \gset
select pg_temp.chk('H12c for_shipment (booker): status booked · 3 attempts cancelled/failed/booked · current = attempt 3 without request/response · can_book true · picking worker → refused',
  (:'h12f'::jsonb->>'status') || '/' || (select string_agg((a->>'attempt') || ':' || (a->>'status'), ',') from jsonb_array_elements(:'h12f'::jsonb->'attempts') a) || '/' || (:'h12f'::jsonb#>>'{current,attempt}') || '/' || ((:'h12f'::jsonb->'current') ? 'response')::text || '/' || (:'h12f'::jsonb->>'can_book') || ' | ' ||
  (select (pg_temp.try(format('select public.fc_booking_for_shipment(%L)::text', :'sh1')) like 'ERR P0001: You cannot see freight bookings%')::text from (select pg_temp.as_user(:'u_none')) a), 'booked/1:cancelled,2:failed,3:booked/3/false/true | true');

-- ── H13 팔렛(S4 · LTL 실물 응답) — dispatch_details · BOL · 취소가 전 값으로 되돌림 ──
select pg_temp.as_user(:'u_off');
select public.fc_shipment_prepare(array[:'s4'::uuid], jsonb_build_object('ship_date', :'tmr', 'residential', false), true) as p4 \gset
select (:'p4'::jsonb->>'shipment_id') as sh4 \gset
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_quote_save(:'sh4'::uuid, 'req-ltl', '{"rates": [{"service_id": "fcxbeta.ltl", "carrier_name": "Fcx Beta", "service_name": "Dry", "base": {"currency": "CAD", "value": "33844"}, "surcharges": [{"type": "fuel", "amount": {"currency": "CAD", "value": "12316"}}], "taxes": [{"type": "tax-gst-ab", "amount": {"currency": "CAD", "value": "2510"}}], "total": {"currency": "CAD", "value": "48670"}, "transit_time_days": 6, "carrier_cut_off_time": "31-12-0000 06:42PM", "valid_until": {"year": 2099, "month": 1, "day": 1}}]}'::jsonb) as q4 \gset
select pg_temp.as_user(:'u_off');
select public.fc_quote_select(:'sh4'::uuid, (select r.id from public.fc_quote_rate r where r.quote_id = (:'q4'::jsonb->>'quote_id')::uuid)) as sel4 \gset
select coalesce(s.carrier_id::text, '(null)') || '/' || coalesce(s.carrier, '(null)') || '/' || coalesce(s.tracking_number, '(null)') as s4_before from public.so s where s.id = :'s4'::uuid \gset
select pg_temp.as_user(:'u_book');
select public.fc_book_prepare(:'sh4'::uuid, '{}'::jsonb, true) as h13 \gset
select pg_temp.chk('H13 pallet prepare: dispatch_details {date tomorrow · ready_at 09:00 · ready_until 17:00} · no pickup_details · unique_id = S4 shipment id · attempt 1 · no cutoff (Beta has no row at wh2? — S4 ships from wh · Beta cutoff 09:00 set in 2a G8 → past? date tomorrow → no warning)',
  (:'h13'::jsonb#>>'{request,dispatch_details,date,day}') || '/' || (:'h13'::jsonb#>>'{request,dispatch_details,ready_at,hour}') || '/' || (:'h13'::jsonb#>>'{request,dispatch_details,ready_until,hour}') || '/' || ((:'h13'::jsonb->'request') ? 'pickup_details')::text || '/' || ((:'h13'::jsonb->>'unique_id') = :'sh4')::text || '/' || (:'h13'::jsonb->>'attempt') || '/' || (:'h13'::jsonb#>>'{pickup,date}') || '/' || (:'h13'::jsonb->'warnings')::text,
  extract(day from :'tmr'::date) || '/9/17/false/true/1/' || :'tmr' || '/[]');
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_book_save((:'h13'::jsonb->>'booking_id')::uuid, :'fx2'::jsonb) as h13s \gset
select pg_temp.chk('H13b save (maritime fixture): booked · tracking F8093865 · url m-o.com · bol MO393895 · labels 1 letter pdf · S4 carrier Beta · tracking F8093865',
  (:'h13s'::jsonb->>'status') || '/' || (:'h13s'::jsonb->>'tracking_number') || '/' || (:'h13s'::jsonb->>'tracking_url') || '/' || (:'h13s'::jsonb->>'bol_number') || '/' || (select string_agg((l->>'size') || ':' || (l->>'format'), ',') from jsonb_array_elements(:'h13s'::jsonb->'labels') l) || '/' ||
  (select (s.carrier_id::text = :'car_b')::text || '/' || s.carrier || '/' || s.tracking_number from public.so s where s.id = :'s4'::uuid),
  'booked/F8093865/https://www.m-o.com/quick-track-form/?t=F8093865/MO393895/letter:pdf/true/FCX Beta Carrier/F8093865');
select public.fc_book_cancel_save((:'h13'::jsonb->>'booking_id')::uuid, jsonb_build_object('cancelled_by', :'st_book')) as h13c \gset
select pg_temp.chk('H13c cancel with nothing changed by a person → orders_restored = S4 · SO carrier · tracking back to the values before booking · shipment selected',
  jsonb_array_length(:'h13c'::jsonb->'orders_restored') || '/' || (:'h13c'::jsonb->'orders_kept')::text || '/' || (select coalesce(s.carrier_id::text, '(null)') || '/' || coalesce(s.carrier, '(null)') || '/' || coalesce(s.tracking_number, '(null)') from public.so s where s.id = :'s4'::uuid) || '/' || (select f.status from public.fc_shipment f where f.id = :'sh4'::uuid),
  '1/[]/' || :'s4_before' || '/selected');

-- ── H14 라벨 ──
select public.fc_label_add(jsonb_build_object('booking_id', :'h12'::jsonb->>'booking_id', 'size', 'a6', 'padded', false, 'path', 'fc_label/' || :'sh1' || '-3-a6.pdf', 'bytes', 12345, 'sha256', repeat('ab', 32), 'pages', 1, 'source_url', 'https://s3.example/labels/x/MASKED/a6.pdf', 'fetched_by', :'st_book')) as l1 \gset
select public.fc_label_add(jsonb_build_object('booking_id', :'h12'::jsonb->>'booking_id', 'size', 'a6', 'padded', false, 'path', 'fc_label/' || :'sh1' || '-3-a6-v2.pdf', 'bytes', 22222, 'sha256', repeat('cd', 32), 'pages', 1)) as l2 \gset
select pg_temp.chk('H14 label_add: row · same size again → replaced (one row · new path · bytes) · a4 → refused · bad path → refused · failed attempt → refused · by a person → refused',
  (:'l1'::jsonb->>'size') || '/' || (:'l1'::jsonb->>'bytes') || '/' || ((:'l2'::jsonb->>'id') = (:'l1'::jsonb->>'id'))::text || '/' || (:'l2'::jsonb->>'bytes') || '/' || (select count(*) from public.fc_label l where l.booking_id = (:'h12'::jsonb->>'booking_id')::uuid) || ' | ' ||
  (pg_temp.try(format('select public.fc_label_add(%L::jsonb)::text', jsonb_build_object('booking_id', :'h12'::jsonb->>'booking_id', 'size', 'a4', 'path', 'fc_label/x.pdf', 'bytes', 1, 'sha256', repeat('ab', 32))::text)) like 'ERR 23514: %fc_label_size_ck%')::text || '/' ||
  (pg_temp.try(format('select public.fc_label_add(%L::jsonb)::text', jsonb_build_object('booking_id', :'h12'::jsonb->>'booking_id', 'size', 'letter', 'path', 'labels/x.pdf', 'bytes', 1, 'sha256', repeat('ab', 32))::text)) like 'ERR 23514: %fc_label_path_ck%')::text || '/' ||
  pg_temp.try(format('select public.fc_label_add(%L::jsonb)::text', jsonb_build_object('booking_id', :'h11'::jsonb->>'booking_id', 'size', 'letter', 'path', 'fc_label/y.pdf', 'bytes', 1, 'sha256', repeat('ab', 32))::text)) || ' | ' ||
  (select pg_temp.try(format('select public.fc_label_add(%L::jsonb)::text', jsonb_build_object('booking_id', :'h12'::jsonb->>'booking_id', 'size', 'letter', 'path', 'fc_label/z.pdf', 'bytes', 1, 'sha256', repeat('ab', 32))::text)) from (select pg_temp.as_user(:'u_book')) a),
  'a6/12345/true/22222/1 | true/true/ERR P0001: Booking #2 is failed — labels come with a booked shipment — nothing was saved | ERR P0001: fc_label_add is for the freight service only — nothing was saved');
select pg_temp.as_user(:'u_off');
select pg_temp.chk('H14b label_get: office (sales view) ok · booker ok · picking worker refused · for_shipment lists the label on the current booking',
  ((public.fc_label_get((:'l1'::jsonb->>'id')::uuid))->>'path') || '/' || (select ((public.fc_label_get((:'l1'::jsonb->>'id')::uuid))->>'bytes') from (select pg_temp.as_user(:'u_book')) a) || '/' || (select (pg_temp.try(format('select public.fc_label_get(%L)::text', :'l1'::jsonb->>'id')) like 'ERR P0001: You cannot open freight labels%')::text from (select pg_temp.as_user(:'u_none')) b) || '/' ||
  (select jsonb_array_length((public.fc_booking_for_shipment(:'sh1'::uuid))->'labels')::text || '/' || ((public.fc_booking_for_shipment(:'sh1'::uuid))#>>'{labels,0,size}') from (select pg_temp.as_user(:'u_book')) c),
  'fc_label/' || :'sh1' || '-3-a6-v2.pdf/22222/true/1/a6');

-- ── H15 권한 · 무접촉 ──
select pg_temp.chk('H15 table acl · RLS · direct insert by authenticated → 42501 · untouched md5 (for_so 2a · quote_save 2a · prepare · quote_select · so_finalize) · function count 10',
  (select string_agg(relacl::text || ':' || relrowsecurity::text, '|' order by relname) from pg_class where relname in ('fc_booking', 'fc_label') and relnamespace = 'public'::regnamespace) || ' | ' ||
  pg_temp.try2('set local role authenticated', format('insert into public.fc_booking (shipment_id, attempt, unique_id) values (%L, 9, ''x'') returning id::text', :'sh1')) || ' | ' ||
  (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_for_so') || '/' || (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_quote_save') || '/' || (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_prepare') || '/' || (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_quote_select') || '/' || (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize') || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_book_gate', 'fc_hm', 'fc_ymd', 'fc_book_prepare', 'fc_book_save', 'fc_book_cancel_prepare', 'fc_book_cancel_save', 'fc_label_add', 'fc_label_get', 'fc_booking_for_shipment')),
  '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres}:true|{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres}:true | ERR 42501: permission denied for table fc_booking | 83b5e899f8fd8ebcbe5d654a20b20c4a/750a0fbacaa37d2215112a9b8308d0ce/2a2a0206f9f2b12320dd93f6467fa8fc/ca317868f2ecb6d2647439e9e370469e/' || :'fin_md5_0' || '/10');

-- ── 결과 ──
select clock_timestamp() - :'t_begin00'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res where n > :n_2a or not ok order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok, :n_2a as from_fc_2a from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :w_so and (select count(*) from public.fc_shipment) = :w_fc and (select count(*) from public.fc_quote) = :w_q and (select count(*) from public.ims_staff) = :w_staff and (select count(*) from public.ref_warehouse) = :w_wh
             and (select count(*) from public.so where tracking_number is not null) = :w_trk and (select count(*) from public.so where carrier_id is not null) = :w_car
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when to_regclass('public.fc_booking') is null and to_regclass('public.fc_label') is null and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'fc_shipment' and column_name = 'booking_id') = 0
       then 'Z2 OK rollback restored · no tables · no column' else 'Z2 MISMATCH rollback did not restore' end as z2;
\endif
