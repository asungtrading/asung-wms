-- supabase/tests/fc_pickup_2_check.sql — fc-pickup-2 자동 다시 읽기 검증 (2026-11-05) · ⭐ 사슬 없음 — 가짜 행 직접(fc_pickup_1_check 꼴 · 운영 메인 DB 라 begin ~ rollback 10 초 안 · DO 블록 둘)
--   Claude Code(시험 · 레포 루트 · ⚠️ 토론토 17:00 뒤): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261107000000_fc_pickup_2_auto_poll.sql -f supabase/tests/fc_pickup_2_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK 는 EXPECT_OK(두 갈래 같다) · Z1 둘 다 · Z2 시험 갈래만
--   재료(FCX · rollback · 전부 상자 · 비정기 · 확인번호 없음이 기본 · request.pickup_details 는 fc_book_prepare 255 행 꼴):
--     a  booked 10 분 전 · 픽업 오늘                → fast · 대상          |  b  booked 3 시간 전 · 마지막 읽기 40 분 전 · 픽업 오늘 → slow · 대상
--     c  booked 3 시간 전 · 마지막 읽기 5 분 전    → slow · 대상 아님     |  d  booked 72 시간 전 · 픽업 4 일 전              → 창 지남 · 대상 아님
--     e  booked 72 시간 전 · 픽업 내일(금 → 월 꼴) → 창 안 · slow · 대상 |  f  확인번호 있음 → 아님 · g  정기(true) → 아님 · h  팔렛 → 아님 · i  cancelled → 아님
--     j  booked 3 시간 전 · 날짜 없음 · 읽은 적 없음 → 48 h 창 · 대상     |  k  Freightcom id 빈칸('   ' · null 은 CHECK fc_booking_booked_ck 가 막는다) → 아님
--   가짜 schedule 응답 = 11-05 실물 꼴 {error, pickup_confirmation_number, status} 맨몸
\set ON_ERROR_STOP on
\set EXPECT_OK 16
\pset pager off
select (select count(*) from public.so) as y_so, (select count(*) from public.fc_shipment) as y_fc, (select count(*) from public.fc_booking) as y_bk, (select count(*) from public.ims_staff) as y_staff, (select count(*) from public.ref_warehouse) as y_wh, (select count(*) from public.fc_call_log) as y_log, (select count(*) from public.inv_config) as y_cfg \gset
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
-- 대상 목록을 글 하나로(letter 순서 그대로 · tier 붙여서)
create temp table t_ids (k text primary key, v text);
create function pg_temp.id(p_k text) returns uuid language sql as $$ select v::uuid from t_ids where k = p_k $$;
create function pg_temp.due_list() returns text language plpgsql security definer as $$   -- plpgsql: 몸은 첫 호출 때 풀린다(sql 이면 만들 때 fc_pickup_poll_due 가 아직 없어 멈춘다 · 1 회차)
begin                                                                                      -- ⚠️ 가짜 행만 · 한도 50 — 메인 DB 에는 실물 대상(오늘 예약 · 번호 없음)이 섞여 limit 10 이 가짜 a 를 잘랐다(5 회차 · 11-06 실물 9 건)
  return (select coalesce(string_agg(i.k || ':' || d.tier, ' ' order by d.booked_at, d.attempt), '(none)')
            from public.fc_pickup_poll_due(50) d join t_ids i on i.v = d.booking_id::text);
end $$;
create function pg_temp.due_n(p_limit int) returns text language plpgsql security definer as $$   -- limit 검사용: 행 수 / booked_at 오름인가(실물 포함)
declare v_n int; v_ord boolean;
begin
  select count(*), coalesce(bool_and(d.booked_at >= d.prev), true) into v_n, v_ord
    from (select booked_at, lag(booked_at) over (order by booked_at, attempt) as prev from public.fc_pickup_poll_due(p_limit)) d;
  return v_n::text || (case when v_ord then '' else '!order' end);
end $$;
create function pg_temp.pc(p_sh uuid) returns jsonb language sql security definer as $$ select (public.fc_booking_for_shipment(p_sh))#>'{current}' $$;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin0000 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 재료(replica · 가짜 FCX · 한 왕복) ──
set local session_replication_role = replica;
do $$
declare v_wh uuid; v_book uuid; v_st uuid; v_so uuid; v_sh uuid; v_id uuid; v_today date := public.ims_today();
  v_req_today jsonb; v_req_tomorrow jsonb; v_req_old jsonb; v_req_nodate jsonb; v_req_regular jsonb; v_req_pallet jsonb; k text;
begin
  select id into v_so from public.so order by created_at limit 1;
  insert into public.ref_warehouse (name, source, is_active, address_line1, city, state_province, postal_code, country, freightcom_account) values ('FCX Warehouse', 'manual', true, '1 Fcx Road', 'Toronto', 'ON', 'M9N 2V8', 'Canada', 'FCX') returning id into v_wh;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-booker@test.invalid', 'FCX Booker', 'worker', '["wms","fulfillment","freight_booking"]', array[v_wh]) returning auth_user_id, id into v_book, v_st;
  v_req_today    := jsonb_build_object('pickup_details', jsonb_build_object('pre_scheduled_pickup', false, 'date', jsonb_build_object('year', extract(year from v_today)::int, 'month', extract(month from v_today)::int, 'day', extract(day from v_today)::int), 'ready_at', '{"hour": 9, "minute": 30}'::jsonb));
  v_req_tomorrow := jsonb_build_object('pickup_details', jsonb_build_object('pre_scheduled_pickup', false, 'date', jsonb_build_object('year', extract(year from v_today + 1)::int, 'month', extract(month from v_today + 1)::int, 'day', extract(day from v_today + 1)::int)));
  v_req_old      := jsonb_build_object('pickup_details', jsonb_build_object('pre_scheduled_pickup', false, 'date', jsonb_build_object('year', extract(year from v_today - 4)::int, 'month', extract(month from v_today - 4)::int, 'day', extract(day from v_today - 4)::int)));
  v_req_nodate   := '{"pickup_details": {"pre_scheduled_pickup": false}}';
  v_req_regular  := '{"pickup_details": {"pre_scheduled_pickup": true}}';
  v_req_pallet   := jsonb_build_object('dispatch_details', jsonb_build_object('date', jsonb_build_object('year', extract(year from v_today)::int, 'month', extract(month from v_today)::int, 'day', extract(day from v_today)::int)));
  foreach k in array array['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k'] loop
    insert into public.fc_shipment (status, origin_warehouse_id, packaging_type, charge_so_id, origin, destination, options, units, request, payload_hash, created_in, freightcom_account)
      values ('booked', v_wh, case when k = 'h' then 'pallet' else 'package' end, v_so, '{}', '{}', '{}', '[]', '{}', 'fcx-p2-' || k, 'wms', 'FCX') returning id into v_sh;
    insert into public.fc_booking (shipment_id, attempt, unique_id, status, account, request, response, freightcom_shipment_id, state, booked_at, cancelled_at, pickup_confirmation, schedule_status, schedule_checked_at, requested_by)
      values (v_sh, 1, 'fcx-p2-' || k || '-1', case when k = 'i' then 'cancelled' else 'booked' end, 'FCX',
              case k when 'd' then v_req_old when 'e' then v_req_tomorrow when 'g' then v_req_regular when 'h' then v_req_pallet when 'j' then v_req_nodate else v_req_today end,
              '{"shipment": {"state": "waiting-for-transit", "pickup_confirmation_number": ""}}', case when k = 'k' then '   ' else 'FCX-' || k end, 'waiting-for-transit',
              case k when 'a' then now() - interval '10 minutes' when 'd' then now() - interval '72 hours' when 'e' then now() - interval '72 hours' else now() - interval '3 hours' end,
              case when k = 'i' then now() - interval '1 hour' end, case when k = 'f' then '26368294' end,
              case when k in ('b', 'c') then 'pending' end, case k when 'b' then now() - interval '40 minutes' when 'c' then now() - interval '5 minutes' end, v_st) returning id into v_id;
    update public.fc_shipment set booking_id = v_id where id = v_sh;
    insert into t_ids values (k, v_id), ('sh_' || k, v_sh);
  end loop;
  insert into t_ids values ('u_book', v_book), ('st_book', v_st);
end $$;
set local session_replication_role = origin;

-- ── 갈래 P0 ~ P12 (한 왕복 · 순서가 있는 것은 문장을 나눠 변수에 받는다 · from (update …) 는 안 된다 — CTE 만) ──
do $$
declare p jsonb; p2 jsonb; v_t1 timestamptz; v_t2 timestamptz; v_s1 text; v_s2 text; v_s3 text; v_a uuid := pg_temp.id('a'); v_b uuid := pg_temp.id('b'); v_e uuid := pg_temp.id('e'); v_j uuid := pg_temp.id('j'); v_book text := pg_temp.id('u_book')::text;
  v_real jsonb := '{"error": "", "pickup_confirmation_number": "29FBD3C23EA", "status": "done"}';
  v_pend jsonb := '{"error": "", "pickup_confirmation_number": "", "status": "pending"}';
begin
  -- P0 착지 · 정적
  perform pg_temp.chk('P0 columns (fc_booking.schedule_done_at · fc_call_log.detail jsonb) · inv_config switch off · batch 10 · due acl service_role only · schedule_save acl · nowhere = 0 · fc_pickup_check · fc_booking_for_shipment md5 untouched',
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'fc_booking' and column_name = 'schedule_done_at' and data_type = 'timestamp with time zone')::text || '/' ||
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'fc_call_log' and column_name = 'detail' and data_type = 'jsonb')::text || '/' ||
    (select string_agg(key || '=' || value, ',' order by key) from public.inv_config where key like 'fc_pickup_poll%') || '/' ||
    (select coalesce(proacl::text, '(null)') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_pickup_poll_due') || '/' ||
    (select coalesce(proacl::text, '(null)') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_book_schedule_save') || '/' ||
    (select sum(pg_temp.nowhere(prosrc)) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_book_schedule_save', 'fc_pickup_poll_due'))::text || '/' ||
    (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_pickup_check') || '/' ||
    (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_booking_for_shipment'),
    '1/1/fc_pickup_poll_batch=10,fc_pickup_poll_enabled=off/{postgres=X/postgres,service_role=X/postgres}/{postgres=X/postgres,service_role=X/postgres}/0/b3a17787b3585d37712930e9315bc300/7413429f0b0e31d04a6e926042d6e6cf');
  -- P1 대상 — 11 건 중 넷(e · b · j · a 순 = booked_at 오름) · tier
  perform pg_temp.as_user(v_book, 'service_role');
  perform pg_temp.chk('P1 due(10) = e(72 h · pickup tomorrow · slow) b(3 h · read 40 min ago · slow) j(3 h · no date · never read · slow) a(10 min · fast) — not c(read 5 min ago) d(window past) f(confirmed) g(regular) h(pallet) i(cancelled) k(blank Freightcom id)',
    pg_temp.due_list(), 'e:slow b:slow j:slow a:fast');
  v_s1 := pg_temp.due_n(50);   -- 전체(가짜 4 + 실물 n) · 실물 수는 결과 표 뒤 info 줄에
  perform pg_temp.chk('P1b limit — 1 → 1 row · 2 → 2 · 0 → default 10 → least(10, total) · 99 → default 10 → least(10, total) · 50 → total ≥ 4 · all ordered by booked_at asc',
    pg_temp.due_n(1) || '/' || pg_temp.due_n(2) || '/' || pg_temp.due_n(0) || '/' || pg_temp.due_n(99) || '/' || (v_s1::int >= 4)::text,
    '1/2/' || least(10, v_s1::int)::text || '/' || least(10, v_s1::int)::text || '/true');
  perform pg_temp.chk('P1c window_until — a = greatest(booked + 48 h, today + 2 at 00:00 Toronto) · e = tomorrow + 2 at 00:00 Toronto (> booked + 48 h) · j (no date) = booked + 48 h · pickup_date a = today · j null · minutes_since_booked a = 10',
    (select (d.window_until = greatest(b.booked_at + interval '48 hours', ((public.ims_today() + 2)::timestamp at time zone 'America/Toronto')))::text || '/' || (d.pickup_date = public.ims_today())::text || '/' || d.minutes_since_booked from public.fc_pickup_poll_due(50) d join public.fc_booking b on b.id = d.booking_id where d.booking_id = v_a) || ' | ' ||
    (select (d.window_until = ((public.ims_today() + 3)::timestamp at time zone 'America/Toronto'))::text || '/' || (d.window_until > b.booked_at + interval '48 hours')::text || '/' || (d.pickup_date = public.ims_today() + 1)::text from public.fc_pickup_poll_due(50) d join public.fc_booking b on b.id = d.booking_id where d.booking_id = v_e) || ' | ' ||
    (select (d.window_until = b.booked_at + interval '48 hours')::text || '/' || coalesce(d.pickup_date::text, 'null') from public.fc_pickup_poll_due(50) d join public.fc_booking b on b.id = d.booking_id where d.booking_id = v_j),
    'true/true/10 | true/true/true | true/null');
  -- P2 문 — 사람(authenticated) · anon 은 거부(역할로 · 창구는 definer 라 역할이 문이다)
  v_s1 := pg_temp.try('set local role authenticated; select count(*)::text from public.fc_pickup_poll_due(10)');
  reset role;
  v_s2 := pg_temp.try('set local role anon; select count(*)::text from public.fc_pickup_poll_due(10)');
  reset role;
  perform pg_temp.chk('P2 due as authenticated → permission denied · as anon → permission denied', left(v_s1, 9) || ' | ' || left(v_s2, 9), 'ERR 42501 | ERR 42501');
  -- P3 저장 — 실물 꼴 done → done_at 채움 · 확인번호 · 반환 열쇠 · 대상에서 빠짐
  perform pg_temp.as_user(v_book, 'service_role');
  p := public.fc_book_schedule_save(v_a, v_real);
  select schedule_done_at into v_t1 from public.fc_booking where id = v_a;
  v_s1 := pg_temp.due_list();
  perform pg_temp.chk('P3 a: real-shape done → schedule_done_at set (= returned) · confirmation 29FBD3C23EA (schedule) · received_keys [error, pickup_confirmation_number, status] · pickup_check not_scheduled false · a leaves the due list',
    (v_t1 is not null)::text || '/' || ((p->>'schedule_done_at')::timestamptz = v_t1)::text || '/' || (p->>'pickup_confirmation') || '/' || (p->>'confirmation_source') || '/' || (p->'received_keys')::text || '/' || (p#>>'{pickup_check,not_scheduled}') || '/' || v_s1,
    'true/true/29FBD3C23EA/schedule/["error", "pickup_confirmation_number", "status"]/false/e:slow b:slow j:slow');
  -- P4 done 을 또 봐도 done_at 그대로(덮지 않음) · checked_at 은 새로
  p2 := public.fc_book_schedule_save(v_a, v_real);
  perform pg_temp.chk('P4 a: done again → schedule_done_at unchanged · schedule_checked_at moved forward',
    (select (b.schedule_done_at = v_t1)::text || '/' || (b.schedule_checked_at > b.schedule_done_at)::text from public.fc_booking b where b.id = v_a), 'true/true');
  -- P5 pending 저장은 done_at 을 안 채운다 · slow 는 읽은 직후 대상에서 빠진다(30 분) · fast 는 읽은 직후에도 대상
  p := public.fc_book_schedule_save(v_b, v_pend);
  v_s1 := pg_temp.due_list();
  perform pg_temp.chk('P5 b (slow): pending saved → schedule_done_at null · status pending · leaves the due list for 30 min (checked just now) · pickup_check pending false (3 h ≥ 15 min → not_scheduled true)',
    coalesce((select schedule_done_at::text from public.fc_booking where id = v_b), 'null') || '/' || (p->>'schedule_status') || '/' || v_s1 || '/' || (p#>>'{pickup_check,pending}') || '/' || (p#>>'{pickup_check,not_scheduled}'), 'null/pending/e:slow j:slow/false/true');
  update public.fc_booking set pickup_confirmation = null, schedule_done_at = null, schedule_status = 'pending' where id = v_a;   -- a 를 다시 빈칸으로(fast 갈래 확인용 · checked_at 은 방금)
  v_s1 := pg_temp.due_list();
  p := public.fc_book_schedule_save(v_a, v_pend);
  select schedule_done_at into v_t1 from public.fc_booking where id = v_a;
  p := public.fc_book_schedule_save(v_a, v_real);
  perform pg_temp.chk('P5b a (fast · 10 min · checked just now) is still due every run · pending does not fill done_at · then done fills it once',
    v_s1 || ' | ' || coalesce(v_t1::text, 'null') || ' | ' || (p->>'schedule_done_at' is not null)::text, 'e:slow j:slow a:fast | null | true');
  -- P6 done 인데 번호 없음 → done_at 은 채워진다(이견 8) · 판정은 빨강 그대로 · slow + 방금 읽음 → 대상 아님
  p := public.fc_book_schedule_save(v_j, '{"error": "", "pickup_confirmation_number": "", "status": "done"}');
  v_s1 := pg_temp.due_list();
  perform pg_temp.chk('P6 j: done without a number → schedule_done_at set · confirmation null · pickup_check not_scheduled true · message "done but gave no confirmation number" · j (slow · checked just now) not due',
    (p->>'schedule_done_at' is not null)::text || '/' || coalesce(p->>'pickup_confirmation', 'null') || '/' || (p#>>'{pickup_check,not_scheduled}') || '/' || (p#>>'{pickup_check,message}') || '/' || v_s1,
    'true/null/true/Pickup NOT scheduled — Freightcom says done but gave no confirmation number/e:slow');
  -- P7 화면 길 — current 에 schedule_done_at 이 실린다(재발행 없이) · schedule_response 는 여전히 뺀다
  perform pg_temp.as_user(v_book, 'authenticated');
  p := pg_temp.pc(pg_temp.id('sh_a'));
  perform pg_temp.chk('P7 fc_booking_for_shipment.current carries schedule_done_at (not null for a) · still no schedule_response · pickup_check.confirmation 29FBD3C23EA',
    (p ? 'schedule_done_at')::text || '/' || (p->>'schedule_done_at' is not null)::text || '/' || (p ? 'schedule_response')::text || '/' || (p#>>'{pickup_check,confirmation}'), 'true/true/false/29FBD3C23EA');
  -- P8 회차 요약 줄 — service_role insert(EF recordCall 꼴) · detail jsonb · by_staff null · shipment_id null · detail 없는 줄도 그대로
  v_t1 := null; p2 := to_jsonb(pg_temp.id('sh_a'));   -- service_role 은 t_ids(임시 표)를 못 읽는다(3 회차) — 역할 바꾸기 전에 꺼낸다
  set local role service_role;
  insert into public.fc_call_log (shipment_id, account, action, ok, http_status, error, by_staff, ms, detail) values (null, null, 'pickup_sweep', true, null, null, null, 1234, '{"enabled": true, "limit": 10, "candidates": 2, "read": 2, "done": 1, "pending": 1, "other": 0, "failed": 0, "ms": 1234}');
  insert into public.fc_call_log (shipment_id, account, action, ok, http_status, error, by_staff, ms) values ((p2#>>'{}')::uuid, 'FCX', 'schedule_poll', true, 200, null, null, 4000);
  reset role;
  perform pg_temp.chk('P8 summary row as service_role → stored · detail->>done = 1 · by_staff null · shipment_id null · a plain schedule_poll row without detail → detail null',
    (select (detail->>'done') || '/' || (by_staff is null)::text || '/' || (shipment_id is null)::text from public.fc_call_log where action = 'pickup_sweep' order by id desc limit 1) || '/' ||
    (select (detail is null)::text from public.fc_call_log where action = 'schedule_poll' and shipment_id = pg_temp.id('sh_a') order by id desc limit 1), '1/true/true/true');
  -- P9 거부 그대로(pickup-1) — 사람 저장 · cancelled 저장
  perform pg_temp.as_user(v_book, 'authenticated');
  v_s1 := pg_temp.try(format('select public.fc_book_schedule_save(%L, %L)::text', v_a, v_real));
  perform pg_temp.as_user(v_book, 'service_role');
  v_s2 := pg_temp.try(format('select public.fc_book_schedule_save(%L, %L)::text', pg_temp.id('i'), v_real));
  perform pg_temp.chk('P9 schedule_save by a person → refused · by service on a cancelled attempt (i) → refused', v_s1 || ' | ' || v_s2,
    'ERR P0001: fc_book_schedule_save is for the freight service only — nothing was saved | ERR P0001: Booking #1 is cancelled — the pickup schedule is read for booked shipments only — nothing was saved');
  -- P10 확인번호가 이미 있으면 덮지 않음 + done_at 은 채움(f)
  p := public.fc_book_schedule_save(pg_temp.id('f'), '{"error": "", "pickup_confirmation_number": "99999", "status": "done"}');
  perform pg_temp.chk('P10 f (already confirmed 26368294): done with another number → kept · mismatch warning · schedule_done_at set',
    (p->>'pickup_confirmation') || '/' || (p->>'confirmation_mismatch') || '/' || (p->>'schedule_done_at' is not null)::text, '26368294/true/true');
  -- P11 창 경계 — d 를 픽업 내일로 바꾸면 창이 열린다(72 h 지났어도) · e 를 5 일 전 예약 · 픽업 3 일 전으로 → 닫힘 · 깨진 날짜(월 13)는 48 h 창으로
  update public.fc_booking set request = jsonb_set(request, '{pickup_details,date}', jsonb_build_object('year', extract(year from public.ims_today() + 1)::int, 'month', extract(month from public.ims_today() + 1)::int, 'day', extract(day from public.ims_today() + 1)::int)) where id = pg_temp.id('d');
  update public.fc_booking set request = jsonb_set(request, '{pickup_details,date}', jsonb_build_object('year', extract(year from public.ims_today() - 3)::int, 'month', extract(month from public.ims_today() - 3)::int, 'day', extract(day from public.ims_today() - 3)::int)), booked_at = now() - interval '5 days' where id = v_e;
  v_s1 := pg_temp.due_list();
  update public.fc_booking set request = jsonb_set(request, '{pickup_details,date,month}', '13'), schedule_checked_at = null where id = v_j;
  v_s2 := pg_temp.due_list();
  perform pg_temp.chk('P11 window follows the pickup date: d (72 h old · pickup tomorrow) now due · e (5 days old · pickup 3 days ago) not due · a broken date (month 13) falls back to the 48 h window (3 h old j → due)',
    v_s1 || ' | ' || v_s2, 'd:slow | d:slow j:slow');
  -- P12 cron where 꼴 — exists(select 1 from fc_pickup_poll_due(1)) · 스위치 off 면 false
  v_s1 := (exists (select 1 from public.inv_config c where c.key = 'fc_pickup_poll_enabled' and c.value = 'on') and exists (select 1 from public.fc_pickup_poll_due(1)))::text;
  update public.inv_config set value = 'on' where key = 'fc_pickup_poll_enabled';
  v_s2 := (exists (select 1 from public.inv_config c where c.key = 'fc_pickup_poll_enabled' and c.value = 'on') and exists (select 1 from public.fc_pickup_poll_due(1)))::text;
  update public.fc_booking set pickup_confirmation = 'Z' where id in (pg_temp.id('d'), v_j);
  v_s3 := pg_temp.due_list();   -- 가짜 대상 0 · 실물 대상은 남을 수 있어 exists 는 그대로 true 일 수 있다(맞는 동작 · 5 회차)
  perform pg_temp.chk('P12 cron where: switch off → false · on → true (candidates exist) · fixture candidates all confirmed → none left among fixtures', v_s1 || '/' || v_s2 || '/' || v_s3, 'false/true/(none)');
end $$;

-- ── 결과 ──
select clock_timestamp() - :'t_begin0000'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select count(*) as info_real_due_rows_now, min(minutes_since_booked) as min_minutes, max(minutes_since_booked) as max_minutes, string_agg(distinct coalesce(schedule_status, 'never-read'), ',') as statuses from public.fc_pickup_poll_due(50) d where d.booking_id::text not in (select v from t_ids);
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :y_so and (select count(*) from public.fc_shipment) = :y_fc and (select count(*) from public.fc_booking) = :y_bk and (select count(*) from public.ims_staff) = :y_staff and (select count(*) from public.ref_warehouse) = :y_wh and (select count(*) from public.fc_call_log) = :y_log and (select count(*) from public.inv_config) = :y_cfg then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when to_regprocedure('public.fc_pickup_poll_due(int)') is null and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'fc_booking' and column_name = 'schedule_done_at') = 0 and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'fc_call_log' and column_name = 'detail') = 0 and (select count(*) from public.inv_config where key like 'fc_pickup_poll%') = 0 then 'Z2 OK rollback restored · no function · no columns · no switch' else 'Z2 MISMATCH' end as z2;
\endif
