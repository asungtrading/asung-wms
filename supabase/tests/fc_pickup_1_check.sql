-- supabase/tests/fc_pickup_1_check.sql — fc-pickup-1 픽업 스케줄 다시 읽기 검증 (2026-11-05) · ⭐ 사슬 없음 — 가짜 행 직접(이견 11)
--   왜 사슬이 아닌가: 운영 메인 DB 라 문장마다 왕복 ≈ 0.2 초 · fc_2b2 사본 사슬(2b2 → 2b → 2a → 1b5 … → 1a)은 begin 뒤 110 초(1 회차 실측) → 「begin ~ rollback 10 초 안」 을 못 지킨다 ·
--       그래서 재료(직원 · 창고 · 발송 둘 · 시도 넷)를 replica 로 직접 넣고 · 갈래는 DO 블록 둘(왕복 둘)로 · 임시 함수 · t_res · fixture 는 begin 앞(잠금 없음)에서 만든다
--   Claude Code(시험 · 레포 루트 · ⚠️ 토론토 17:00 뒤): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261105183506_fc_pickup_1_schedule_read.sql -f supabase/tests/fc_pickup_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK 는 EXPECT_OK(두 갈래 같다) · Z1 둘 다 · Z2 시험 갈래만
--   재료(FCX · rollback): wh(가짜 창고) · u_book(freight_booking · 창고 wh) · u_none(wms · picking) · st_book ·
--     sh1 상자 · 시도 #1 cancelled · #2 failed · #3 booked(fx id CbeeOP… · request.pickup_details.pre_scheduled_pickup false — fc_book_prepare 255 행 꼴) · P14 에서 #3 취소(fc_book_cancel_save) 뒤 #4 booked(pre_scheduled_pickup true — 253 행 꼴 · fc_book_prepare 는 견적 · SO 사슬이 필요해 직접 넣는다)
--     sh4 팔렛 · 시도 #2 booked(fx id uv2bN… · request.dispatch_details — 251 행 꼴) · fx2 = fixtures/book-ltl-maritime.json(GET /shipment 실물 꼴 · P13 p_shipment)
--   가짜 schedule 응답은 전부 문서 스키마 짐작(실물 꼴은 첫 실호출 뒤 received_keys 로 확인) — fixtures 폴더에는 넣지 않는다(그 폴더는 프로브 원문)
\set ON_ERROR_STOP on
\set EXPECT_OK 21
\pset pager off
select (select count(*) from public.so) as y_so, (select count(*) from public.fc_shipment) as y_fc, (select count(*) from public.fc_booking) as y_bk, (select count(*) from public.ims_staff) as y_staff, (select count(*) from public.ref_warehouse) as y_wh, (select count(*) from public.so where tracking_number is not null) as y_trk \gset
-- ── begin 앞(잠금 없음): fixture · 임시 표 · 임시 함수 ──
create temp table fx_ltl (seq serial, line text);
\copy fx_ltl (line) from 'supabase/functions/freightcom/fixtures/book-ltl-maritime.json' with (format csv, quote e'\x01', delimiter e'\x02')
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
-- 화면이 읽는 길 그대로(fc_booking_for_shipment → current.pickup_check) · 부른 사람의 문은 request.jwt.claims(as_user)
create function pg_temp.pc(p_sh uuid) returns jsonb language sql security definer as $$ select (public.fc_booking_for_shipment(p_sh))#>'{current,pickup_check}' $$;
create temp table t_ids (k text primary key, v text);
create function pg_temp.id(p_k text) returns uuid language sql as $$ select v::uuid from t_ids where k = p_k $$;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin0000 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 재료(replica · 가짜 FCX · 한 왕복 — set local 은 최상위에서만 허용된다 · DO 안 set_config 는 permission denied) ──
set local session_replication_role = replica;
do $$
declare v_wh uuid; v_book uuid; v_st uuid; v_none uuid; v_sh1 uuid; v_sh4 uuid; v_b1 uuid; v_b2 uuid; v_b3 uuid; v_i1 uuid; v_so uuid;
begin
  -- charge_so_id 는 실제 so 한 줄을 가리킨다(읽기만 · replica 로 넣은 행도 같은 트랜잭션의 update(cancel_save 가 fc_shipment status 를 바꾼다)에서 FK 를 다시 검사한다)
  select id into v_so from public.so order by created_at limit 1;
  insert into public.ref_warehouse (name, source, is_active, address_line1, city, state_province, postal_code, country, freightcom_account) values ('FCX Warehouse', 'manual', true, '1 Fcx Road', 'Toronto', 'ON', 'M9N 2V8', 'Canada', 'FCX') returning id into v_wh;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-booker@test.invalid', 'FCX Booker', 'worker', '["wms","fulfillment","freight_booking"]', array[v_wh]) returning auth_user_id, id into v_book, v_st;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-none@test.invalid', 'FCX Nobody', 'worker', '["wms","picking"]', '{}') returning auth_user_id into v_none;
  insert into public.fc_shipment (status, origin_warehouse_id, packaging_type, charge_so_id, origin, destination, options, units, request, payload_hash, created_in, freightcom_account)
    values ('booked', v_wh, 'package', v_so, '{}', '{}', '{}', '[]', '{}', 'fcx-sh1', 'wms', 'FCX') returning id into v_sh1;
  insert into public.fc_shipment (status, origin_warehouse_id, packaging_type, charge_so_id, origin, destination, options, units, request, payload_hash, created_in, freightcom_account)
    values ('booked', v_wh, 'pallet', v_so, '{}', '{}', '{}', '[]', '{}', 'fcx-sh4', 'wms', 'FCX') returning id into v_sh4;
  -- 상자 · 비정기 request 꼴 = fc_book_prepare 255 행 · 팔렛 = 251 행(dispatch_details) · 정기 = 253 행
  insert into public.fc_booking (shipment_id, attempt, unique_id, status, account, request, freightcom_shipment_id, state, booked_at, cancelled_at, requested_by) values
    (v_sh1, 1, 'fcx-sh1-1', 'cancelled', 'FCX', '{"unique_id": "fcx-sh1-1", "pickup_details": {"pre_scheduled_pickup": false, "date": {"year": 2026, "month": 11, "day": 5}, "ready_at": {"hour": 14, "minute": 0}, "ready_until": {"hour": 17, "minute": 0}}}', 'FCX-C1', 'cancelled', now() - interval '2 hours', now() - interval '1 hour', v_st) returning id into v_b1;
  insert into public.fc_booking (shipment_id, attempt, unique_id, status, account, request, error, failed_at, requested_by) values
    (v_sh1, 2, 'fcx-sh1-2', 'failed', 'FCX', '{"unique_id": "fcx-sh1-2", "pickup_details": {"pre_scheduled_pickup": false, "date": {"year": 2026, "month": 11, "day": 5}, "ready_at": {"hour": 14, "minute": 0}, "ready_until": {"hour": 17, "minute": 0}}}', 'Freightcom book 422: fake', now() - interval '50 minutes', v_st) returning id into v_b2;
  insert into public.fc_booking (shipment_id, attempt, unique_id, status, account, request, response, freightcom_shipment_id, state, tracking_number, booked_at, requested_by) values
    (v_sh1, 3, 'fcx-sh1-3', 'booked', 'FCX', '{"unique_id": "fcx-sh1-3", "pickup_details": {"pre_scheduled_pickup": false, "date": {"year": 2026, "month": 11, "day": 5}, "ready_at": {"hour": 14, "minute": 0}, "ready_until": {"hour": 17, "minute": 0}}}', '{"shipment": {"id": "CbeeOPfzfSDUI1ajuQCx8NwjElun7pm4", "state": "waiting-for-transit", "pickup_confirmation_number": ""}}', 'CbeeOPfzfSDUI1ajuQCx8NwjElun7pm4', 'waiting-for-transit', '1ZFCX', now(), v_st) returning id into v_b3;
  insert into public.fc_booking (shipment_id, attempt, unique_id, status, account, request, response, freightcom_shipment_id, state, booked_at, requested_by) values
    (v_sh4, 2, 'fcx-sh4-2', 'booked', 'FCX', '{"unique_id": "fcx-sh4-2", "dispatch_details": {"date": {"year": 2026, "month": 11, "day": 6}, "ready_at": {"hour": 9, "minute": 0}, "ready_until": {"hour": 16, "minute": 0}}}', '{"shipment": {"id": "uv2bNzor8tvsd2fDt77sTW3VMV9J6H1u", "state": "waiting-for-transit"}}', 'uv2bNzor8tvsd2fDt77sTW3VMV9J6H1u', 'waiting-for-transit', now(), v_st) returning id into v_i1;
  update public.fc_shipment set booking_id = v_b3 where id = v_sh1;
  update public.fc_shipment set booking_id = v_i1 where id = v_sh4;
  insert into t_ids values ('wh', v_wh), ('u_book', v_book), ('st_book', v_st), ('u_none', v_none), ('sh1', v_sh1), ('sh4', v_sh4), ('b1', v_b1), ('b2', v_b2), ('b3', v_b3), ('i1', v_i1);
end $$;
set local session_replication_role = origin;

-- ── 갈래 P0 ~ P15 (한 왕복) ──
do $$
declare
  v_b3 uuid := pg_temp.id('b3'); v_i1 uuid := pg_temp.id('i1'); v_sh1 uuid := pg_temp.id('sh1'); v_sh4 uuid := pg_temp.id('sh4');
  v_book text := pg_temp.id('u_book')::text; v_none text := pg_temp.id('u_none')::text; v_st uuid := pg_temp.id('st_book');
  v_fx2 jsonb; p jsonb; p2 jsonb; v_before text; v_t1 timestamptz; v_b4 uuid;
begin
  select string_agg(line, E'\n' order by seq)::jsonb into v_fx2 from fx_ltl;
  -- P0 착지 · 정적
  perform pg_temp.chk('P0 columns 4 · functions 3 · nowhere(prosrc) = 0 for schedule_save · for_shipment · pickup_check · parse · fc_book_save md5 untouched',
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'fc_booking' and column_name like 'schedule\_%')::text || '/' ||
    (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_schedule_parse', 'fc_book_schedule_save', 'fc_pickup_check'))::text || '/' ||
    (select sum(pg_temp.nowhere(prosrc)) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_book_schedule_save', 'fc_booking_for_shipment', 'fc_pickup_check', 'fc_schedule_parse'))::text || '/' ||
    (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_book_save'),
    '4/3/0/e6a0f6a0c836a5304ff2b8e5f5f1fc1c');
  perform pg_temp.chk('P0b nowhere self-test (update without where 1 · with where 0 · delete 0-where 1)',
    pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text, '101');
  perform pg_temp.chk('P0c parser — wrapped {schedule} · status lower/trim · confirmation trim · keys · error from message | errors[0].message · non-string status → unknown · non-object → unknown',
    (public.fc_schedule_parse('{"schedule": {"status": " Done ", "pickup_confirmation_number": " 123 "}}'::jsonb))::text || ' | ' ||
    ((public.fc_schedule_parse('{"status": "error", "errors": [{"message": "no window"}]}'::jsonb))->>'error') || ' | ' ||
    ((public.fc_schedule_parse('{"status": {"done": true}}'::jsonb))->>'status') || ' | ' || ((public.fc_schedule_parse('[]'::jsonb))->>'status') || ' | ' || ((public.fc_schedule_parse(null))->>'status'),
    '{"keys": ["schedule"], "error": null, "status": "done", "wrapped": "schedule", "confirmation": "123"} | no window | unknown | unknown | unknown');
  -- P1 읽기 전 판정(화면 길)
  perform pg_temp.as_user(v_book);
  p := public.fc_booking_for_shipment(v_sh1);
  perform pg_temp.chk('P1 box · non-regular · booked · never read → needed true · not_scheduled true · pending false · status null · message "not checked" · current carries schedule_status but not schedule_response · attempts 3',
    (p#>>'{current,pickup_check,needed}') || '/' || (p#>>'{current,pickup_check,packaging}') || '/' || (p#>>'{current,pickup_check,not_scheduled}') || '/' || (p#>>'{current,pickup_check,pending}') || '/' ||
    coalesce(p#>>'{current,pickup_check,status}', '(null)') || '/' || (p#>>'{current,pickup_check,message}') || '/' || ((p->'current') ? 'schedule_status')::text || '/' || ((p->'current') ? 'schedule_response')::text || '/' || jsonb_array_length(p->'attempts'),
    'true/package/true/false/(null)/Pickup not confirmed — not checked with Freightcom since booking · use Check pickup/true/false/3');
  p := pg_temp.pc(v_sh4);
  perform pg_temp.chk('P1b pallet (sh4 · dispatch_details) → needed false · not_scheduled false · message "Pallet dispatch"',
    (p->>'needed') || '/' || (p->>'packaging') || '/' || (p->>'not_scheduled') || '/' || (p->>'message'), 'false/pallet/false/Pallet dispatch — no parcel pickup to check');
  -- P2 거부
  perform pg_temp.chk('P2 schedule_save by a person → refused',
    pg_temp.try(format('select public.fc_book_schedule_save(%L, ''{"status": "pending"}'')::text', v_b3)), 'ERR P0001: fc_book_schedule_save is for the freight service only — nothing was saved');
  perform pg_temp.as_user(v_none, 'service_role');
  perform pg_temp.chk('P2b failed attempt (#2) · cancelled attempt (#1) · non-object body · shipment answer for another id → refused · nothing saved (checked_at still null)',
    pg_temp.try(format('select public.fc_book_schedule_save(%L, ''{"status": "pending"}'')::text', pg_temp.id('b2'))) || ' | ' ||
    pg_temp.try(format('select public.fc_book_schedule_save(%L, ''{"status": "pending"}'')::text', pg_temp.id('b1'))) || ' | ' ||
    pg_temp.try(format('select public.fc_book_schedule_save(%L, ''[1]'')::text', v_b3)) || ' | ' ||
    pg_temp.try(format('select public.fc_book_schedule_save(%L, ''{"status": "pending"}'', ''{"shipment": {"id": "zzz", "state": "in-transit"}}'')::text', v_b3)) || ' | ' ||
    (select coalesce(b.schedule_checked_at::text, '(null)') || '/' || coalesce(b.state, '(null)') from public.fc_booking b where b.id = v_b3),
    'ERR P0001: Booking #2 is failed — the pickup schedule is read for booked shipments only — nothing was saved | ERR P0001: Booking #1 is cancelled — the pickup schedule is read for booked shipments only — nothing was saved | ERR P0001: p_schedule must be a JSON object — nothing was saved | ERR P0001: The shipment answer is for zzz — this booking is CbeeOPfzfSDUI1ajuQCx8NwjElun7pm4 — nothing was saved | (null)/waiting-for-transit');
  -- P3 · P4 pending 두 번
  p := public.fc_book_schedule_save(v_b3, '{"status": "pending"}'::jsonb);
  perform pg_temp.chk('P3 pending → schedule_status pending · confirmation null · checked_at set · received_keys [status] · pickup_check pending true · not_scheduled false · message "still scheduling"',
    (p->>'schedule_status') || '/' || coalesce(p->>'pickup_confirmation', '(null)') || '/' || (p->>'confirmation_source' is null)::text || '/' || ((p->>'schedule_checked_at') is not null)::text || '/' || (p->'received_keys')::text || '/' ||
    (p#>>'{pickup_check,pending}') || '/' || (p#>>'{pickup_check,not_scheduled}') || '/' || (p#>>'{pickup_check,message}') || '/' || (p->>'shipment_read'),
    'pending/(null)/true/true/["status"]/true/false/Freightcom is still scheduling the pickup — check again in a few minutes/false');
  select (to_jsonb(b) - 'schedule_checked_at')::text, b.schedule_checked_at into v_before, v_t1 from public.fc_booking b where b.id = v_b3;
  p := public.fc_book_schedule_save(v_b3, '{"status": "pending"}'::jsonb);
  perform pg_temp.chk('P4 same answer again → only schedule_checked_at moves (row minus checked_at identical · checked_at later)',
    (select ((to_jsonb(b) - 'schedule_checked_at')::text = v_before)::text || '/' || (b.schedule_checked_at > v_t1)::text from public.fc_booking b where b.id = v_b3), 'true/true');
  -- P5 15 분(fc_booking 에는 트리거가 없다 — 바로 update)
  update public.fc_booking set booked_at = now() - interval '20 minutes' where id = v_b3;
  perform pg_temp.as_user(v_book);
  p := pg_temp.pc(v_sh1);
  perform pg_temp.chk('P5 pending but booked 20 minutes ago → not_scheduled true · pending false · minutes 20 · message names the minutes',
    (p->>'not_scheduled') || '/' || (p->>'pending') || '/' || (p->>'minutes_since_booked') || '/' || (p->>'message'),
    'true/false/20/Pickup NOT scheduled — Freightcom has been ''pending'' for 20 minutes since booking · ask Freightcom for the pickup');
  update public.fc_booking set booked_at = now() where id = v_b3;
  perform pg_temp.as_user(v_none, 'service_role');
  -- P6 ~ P9 error · timed-out · unknown · done without number
  p := public.fc_book_schedule_save(v_b3, '{"schedule": {"status": "error", "message": "Carrier rejected the pickup window"}}'::jsonb);
  perform pg_temp.chk('P6 wrapped {schedule} error + message → status error · schedule_error · wrapped schedule · not_scheduled true · pending false · message carries the Freightcom text',
    (p->>'schedule_status') || '/' || (p->>'schedule_error') || '/' || (p->>'wrapped') || '/' || (p#>>'{pickup_check,not_scheduled}') || '/' || (p#>>'{pickup_check,pending}') || '/' || (p#>>'{pickup_check,message}'),
    'error/Carrier rejected the pickup window/schedule/true/false/Pickup NOT scheduled — Freightcom says: Carrier rejected the pickup window');
  p := public.fc_book_schedule_save(v_b3, '{"status": "timed-out"}'::jsonb);
  perform pg_temp.chk('P7 timed-out → status timed-out · error cleared (overwrite) · not_scheduled true · message quotes the status',
    (p->>'schedule_status') || '/' || coalesce(p->>'schedule_error', '(null)') || '/' || (p#>>'{pickup_check,not_scheduled}') || '/' || (p#>>'{pickup_check,message}'),
    'timed-out/(null)/true/Pickup NOT scheduled — Freightcom says: schedule status ''timed-out''');
  p := public.fc_book_schedule_save(v_b3, '{"status": " Scheduled-Maybe "}'::jsonb);
  p2 := public.fc_book_schedule_save(v_b3, '{"status": {"done": false}, "pickup_confirmation_number": ""}'::jsonb);
  perform pg_temp.chk('P8 value outside the four → stored as given (lower · trim) · not_scheduled true · non-string status → unknown · empty confirmation = none',
    (p->>'schedule_status') || '/' || (p#>>'{pickup_check,not_scheduled}') || '/' || (p#>>'{pickup_check,message}') || ' | ' || (p2->>'schedule_status') || '/' || coalesce(p2->>'pickup_confirmation', '(null)') || '/' || (p2->'received_keys')::text,
    'scheduled-maybe/true/Pickup NOT scheduled — Freightcom says: schedule status ''scheduled-maybe'' | unknown/(null)/["pickup_confirmation_number", "status"]');
  p := public.fc_book_schedule_save(v_b3, '{"status": "done"}'::jsonb);
  perform pg_temp.chk('P9 done without a number → not_scheduled true · message "done but gave no confirmation number"',
    (p->>'schedule_status') || '/' || (p#>>'{pickup_check,not_scheduled}') || '/' || (p#>>'{pickup_check,message}'), 'done/true/Pickup NOT scheduled — Freightcom says done but gave no confirmation number');
  -- P10 ~ P12 done + 확인번호 · 다름 · 같음
  p := public.fc_book_schedule_save(v_b3, '{"status": "done", "pickup_confirmation_number": " 12345 "}'::jsonb);
  perform pg_temp.as_user(v_book);
  p2 := pg_temp.pc(v_sh1);
  perform pg_temp.chk('P10 done + number → pickup_confirmation 12345 (trimmed · source schedule) · not_scheduled false · pending false · message "Pickup scheduled — confirmation 12345" · for_shipment agrees',
    (p->>'pickup_confirmation') || '/' || (p->>'confirmation_source') || '/' || (p->>'confirmation_mismatch') || '/' || (p#>>'{pickup_check,not_scheduled}') || '/' || (p#>>'{pickup_check,pending}') || '/' || (p#>>'{pickup_check,message}') || '/' ||
    (p2->>'confirmation') || '/' || (p2->>'not_scheduled'),
    '12345/schedule/false/false/false/Pickup scheduled — confirmation 12345/12345/false');
  perform pg_temp.as_user(v_none, 'service_role');
  p := public.fc_book_schedule_save(v_b3, '{"status": "done", "pickup_confirmation_number": "99999"}'::jsonb);
  perform pg_temp.chk('P11 done + a different number → IMS value kept · mismatch true · warning · pickup_check shows both · message says Freightcom now reports 99999',
    (p->>'pickup_confirmation') || '/' || (p->>'confirmation_source') || '/' || (p->>'confirmation_mismatch') || '/' || jsonb_array_length(p->'warnings') || '/' || (p#>>'{warnings,0}') || '/' ||
    (p#>>'{pickup_check,freightcom_confirmation}') || '/' || (p#>>'{pickup_check,confirmation_mismatch}') || '/' || (p#>>'{pickup_check,not_scheduled}') || '/' || (p#>>'{pickup_check,message}'),
    '12345/kept/true/1/confirmation_mismatch — IMS has 12345 · Freightcom now says 99999 (schedule) · kept the IMS value/99999/true/false/Pickup scheduled — confirmation 12345 · Freightcom now reports 99999 — check which one the driver has');
  p := public.fc_book_schedule_save(v_b3, '{"status": "done", "pickup_confirmation_number": "12345"}'::jsonb);
  perform pg_temp.chk('P12 same number again → no warning · mismatch false · message plain',
    (p->>'pickup_confirmation') || '/' || (p->>'confirmation_mismatch') || '/' || jsonb_array_length(p->'warnings') || '/' || (p#>>'{pickup_check,message}'), '12345/false/0/Pickup scheduled — confirmation 12345');
  -- P13 p_shipment(팔렛 i1 · fx2 maritime 실물 꼴 · id uv2bN…) — state 새로 · 확인번호는 shipment 에서
  p := public.fc_book_schedule_save(v_i1, '{"status": "pending"}'::jsonb, v_fx2 || jsonb_build_object('shipment', (v_fx2->'shipment') || '{"state": "in-transit", "pickup_confirmation_number": "PK-1"}'::jsonb));
  perform pg_temp.as_user(v_book);
  p2 := public.fc_booking_for_shipment(v_sh4);
  perform pg_temp.chk('P13 pallet + shipment answer → state in-transit · confirmation PK-1 (source shipment) · shipment_read true · pickup_check needed false · message "Pallet dispatch … · confirmation PK-1" · for_shipment state agrees',
    (p->>'state') || '/' || (p->>'pickup_confirmation') || '/' || (p->>'confirmation_source') || '/' || (p->>'shipment_read') || '/' || (p#>>'{pickup_check,needed}') || '/' || (p#>>'{pickup_check,message}') || '/' || (p2#>>'{current,state}'),
    'in-transit/PK-1/shipment/true/false/Pallet dispatch — no parcel pickup to check · confirmation PK-1/in-transit');
  perform pg_temp.as_user(v_none, 'service_role');
  p := public.fc_book_schedule_save(v_i1, '{"status": "done", "pickup_confirmation_number": "PK-2"}'::jsonb, v_fx2 || jsonb_build_object('shipment', (v_fx2->'shipment') || '{"pickup_confirmation_number": "PK-3"}'::jsonb));
  perform pg_temp.chk('P13b schedule answer wins over shipment answer for the number · an already-held number is not overwritten by the shipment answer',
    (p->>'pickup_confirmation') || '/' || (select b.pickup_confirmation || '/' || b.schedule_status from public.fc_booking b where b.id = v_i1), 'PK-1/PK-1/done');
  -- P14 정기 픽업 상자 — #3 취소(fc_book_cancel_save 실물 창구) → #4 booked(pre_scheduled_pickup true · 직접) → needed false
  p := public.fc_book_cancel_save(v_b3, jsonb_build_object('cancelled_by', v_st));
  insert into public.fc_booking (shipment_id, attempt, unique_id, status, account, request, response, freightcom_shipment_id, state, booked_at, requested_by) values
    (v_sh1, 4, 'fcx-sh1-4', 'booked', 'FCX', '{"unique_id": "fcx-sh1-4", "pickup_details": {"pre_scheduled_pickup": true}}', '{"shipment": {"id": "FCX-B4", "state": "waiting-for-transit", "pickup_confirmation_number": ""}}', 'FCX-B4', 'waiting-for-transit', now(), v_st) returning id into v_b4;
  update public.fc_shipment set booking_id = v_b4, status = 'booked' where id = v_sh1;
  perform pg_temp.as_user(v_book);
  p2 := public.fc_booking_for_shipment(v_sh1);
  perform pg_temp.as_user(v_none, 'service_role');
  perform pg_temp.chk('P14 regular-pickup box (#4 · pre_scheduled_pickup true) → cancel_save #3 ok · needed false · not_scheduled false · message "Regular pickup" · schedule_save still allowed (GET only) · attempts 4 · cancelled #3 keeps its schedule columns',
    (p->>'status') || '/' || (p->>'shipment_status') || '/' || (p2#>>'{current,pickup_check,needed}') || '/' || (p2#>>'{current,pickup_check,not_scheduled}') || '/' || (p2#>>'{current,pickup_check,message}') || '/' || jsonb_array_length(p2->'attempts') || '/' ||
    ((public.fc_book_schedule_save(v_b4, '{"status": "pending"}'::jsonb))#>>'{pickup_check,needed}') || '/' ||
    (select b.status || ':' || b.schedule_status || ':' || b.pickup_confirmation from public.fc_booking b where b.id = v_b3),
    'cancelled/selected/false/false/Regular pickup — no pickup request was sent/4/false/cancelled:done:12345');
  perform pg_temp.chk('P15 fc_book_cancel_save untouched (md5) · no booking row carries a schedule key inside response (raw stays apart)',
    (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_book_cancel_save') || '/' || (select count(*) from public.fc_booking b where b.response ? 'schedule_status')::text, '938df0b73e64df3b09ab0d0b3dc1e62a/0');
end $$;

-- ── 결과 ──
select clock_timestamp() - :'t_begin0000'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :y_so and (select count(*) from public.fc_shipment) = :y_fc and (select count(*) from public.fc_booking) = :y_bk and (select count(*) from public.ims_staff) = :y_staff and (select count(*) from public.ref_warehouse) = :y_wh and (select count(*) from public.so where tracking_number is not null) = :y_trk then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when to_regprocedure('public.fc_book_schedule_save(uuid, jsonb, jsonb)') is null and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'fc_booking' and column_name like 'schedule\_%') = 0 then 'Z2 OK rollback restored · no function · no columns' else 'Z2 MISMATCH' end as z2;
\endif
