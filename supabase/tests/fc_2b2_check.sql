-- supabase/tests/fc_2b2_check.sql — fc-2b2 fc_book_pending_set 검증 (2026-10-28) · fc_2b 사본(193) 위에 I 갈래 셋
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028233000_fc_2b2_book_pending_set.sql -f supabase/tests/fc_2b2_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK 196 · Z1 둘 다 · Z2 시험 갈래만
\set ON_ERROR_STOP on
\set EXPECT_OK 196
\pset pager off
\! awk 'BEGIN{skip=0;done=0} /^\\if :\{\?mig\}/{skip=1;next} /^\\endif/{if(skip){skip=0;next}} /^-- ── 결과 ──/{done=1} done{next} skip{next} /^begin;$/{next} /^set local lock_timeout/{next} /^\\set EXPECT_OK/{next} {print}' supabase/tests/fc_2b_check.sql > /tmp/fc_2b-inner.sql
select (select count(*) from public.so) as v_so, (select count(*) from public.fc_shipment) as v_fc, (select count(*) from public.ims_staff) as v_staff, (select count(*) from public.so where tracking_number is not null) as v_trk \gset
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin000 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
\echo '── fc_2b_check 속(사본 · 193)'
\i /tmp/fc_2b-inner.sql
select count(*) as n_2b from t_res \gset
\echo '── fc-2b inner done: rows' :n_2b
-- I: S4 는 H13c 뒤 selected → 새 pending 시도 → id 적기
select pg_temp.as_user(:'u_book');
select public.fc_book_prepare(:'sh4'::uuid, '{}'::jsonb, true) as i1 \gset
select pg_temp.chk('I1 pending_set by a person → refused · on a booked attempt (S1 #3) → refused · empty id → refused',
  pg_temp.try(format('select public.fc_book_pending_set(%L, ''abc'')::text', :'i1'::jsonb->>'booking_id')) || ' | ' ||
  (select pg_temp.try(format('select public.fc_book_pending_set(%L, ''abc'')::text', :'h12'::jsonb->>'booking_id')) || ' | ' || pg_temp.try(format('select public.fc_book_pending_set(%L, ''  '')::text', :'i1'::jsonb->>'booking_id')) from (select pg_temp.as_user(:'u_none', 'service_role')) a),
  'ERR P0001: fc_book_pending_set is for the freight service only — nothing was saved | ERR P0001: Booking #3 is already booked — nothing was saved | ERR P0001: Freightcom shipment id is empty — nothing was saved');
select pg_temp.as_user(:'u_none', 'service_role');
select public.fc_book_pending_set((:'i1'::jsonb->>'booking_id')::uuid, ' uv2bNzor8tvsd2fDt77sTW3VMV9J6H1u ', (:'i1'::jsonb->'request') || '{"payment_method_id": "pm-test"}'::jsonb) as i2 \gset
select pg_temp.chk('I2 pending_set: id trimmed · status pending · request now carries payment_method_id · account returned',
  (:'i2'::jsonb->>'freightcom_shipment_id') || '/' || (:'i2'::jsonb->>'status') || '/' || (select (b.request->>'payment_method_id') || '/' || (b.request->>'unique_id' = b.unique_id)::text from public.fc_booking b where b.id = (:'i1'::jsonb->>'booking_id')::uuid) || '/' || ((:'i2'::jsonb->>'account') = (select f.freightcom_account from public.fc_shipment f where f.id = :'sh4'::uuid))::text,
  'uv2bNzor8tvsd2fDt77sTW3VMV9J6H1u/pending/pm-test/true/true');
select public.fc_book_save((:'i1'::jsonb->>'booking_id')::uuid, :'fx2'::jsonb) as i3 \gset
select pg_temp.chk('I3 save after pending_set → booked · same id · for_shipment current shows it · pending_set now refused · 2b windows md5 untouched (count 7)',
  (:'i3'::jsonb->>'status') || '/' || (:'i3'::jsonb->>'freightcom_shipment_id') || '/' || (select ((public.fc_booking_for_shipment(:'sh4'::uuid))#>>'{current,freightcom_shipment_id}') from (select pg_temp.as_user(:'u_book')) a) || ' | ' ||
  (select pg_temp.try(format('select public.fc_book_pending_set(%L, ''x'')::text', :'i1'::jsonb->>'booking_id')) from (select pg_temp.as_user(:'u_none', 'service_role')) b) || ' | ' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_book_prepare', 'fc_book_save', 'fc_book_cancel_prepare', 'fc_book_cancel_save', 'fc_label_add', 'fc_label_get', 'fc_booking_for_shipment')),
  'booked/uv2bNzor8tvsd2fDt77sTW3VMV9J6H1u/uv2bNzor8tvsd2fDt77sTW3VMV9J6H1u | ERR P0001: Booking #2 is already booked — nothing was saved | 7');
-- ── 결과 ──
select clock_timestamp() - :'t_begin000'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res where n > :n_2b or not ok order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok, :n_2b as from_fc_2b from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :v_so and (select count(*) from public.fc_shipment) = :v_fc and (select count(*) from public.ims_staff) = :v_staff and (select count(*) from public.so where tracking_number is not null) = :v_trk then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when to_regprocedure('public.fc_book_pending_set(uuid, text, jsonb)') is null then 'Z2 OK rollback restored · no function' else 'Z2 MISMATCH' end as z2;
\endif
