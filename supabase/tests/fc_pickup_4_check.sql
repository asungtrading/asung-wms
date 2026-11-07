-- supabase/tests/fc_pickup_4_check.sql — fc-pickup-4 「픽업이 안 잡힌 예약」 목록 검증 (2026-11-06) · ⭐ 사슬 없음 — 가짜 행 직접(fc_pickup_2_check 꼴 · 운영 메인 DB 라 begin ~ rollback 10 초 안 · DO 블록 둘)
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261107020808_fc_pickup_4_attention_list.sql -f supabase/tests/fc_pickup_4_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 OK 는 EXPECT_OK(두 갈래 같다) · Z1 둘 다 · Z2 시험 갈래만
--   재료(FCX · rollback · 창고 A · B · 상자 · 비정기 · 픽업 오늘 · 확인번호 없음 · 3 시간 전 예약이 기본 · 손님은 실물 첫 행(FK · 이름은 찍지 않는다) · SO 는 가짜 SO-799xx):
--     a  error(거절)                                    → 있음   |  b  done · 번호 없음                                → 있음
--     c  pending · 3 h · 40 분 전 읽음                  → 있음   |  d  읽은 적 없음 · 3 h                              → 있음
--     e  읽은 적 없음 · 5 분 전 예약(이견 3)            → 있음   |  f  pending · 5 분 전 예약 · 1 분 전 읽음            → 없음
--     g  done · 확인번호 있음                           → 없음   |  h  정기(pre_scheduled_pickup true)                 → 없음
--     i  팔렛(dispatch_details)                         → 없음   |  j  같은 발송 시도 둘 — j1 취소 · j2 거절(날짜 없음) → j2 만(null 날짜 → 맨 뒤)
--     k  failed 시도(발송 selected)                     → 없음   |  l  72 h 전 예약 · 픽업 4 일 전 · error             → 창 밖 · 없음
--     m  72 h 전 예약 · 픽업 내일 · error               → 창 안 · 있음(맨 뒤에서 둘째 · 픽업 날 오름)
--     n  창고 B · error · 1 시간 전                     → admin 있음 · booker(A 만) 없음 · p_warehouse_id B 면 n 만
--     o  SO 셋(s17 · s18 · s19 · 운임 SO 가운데 s18) · error · 4 시간 전 → 있음 · 맨 앞 · so_numbers = [s18, s17, s19]
--   정렬(admin · 창고 없음) = o a b c d n e m j2 (픽업 날 오름 · null 뒤 → booked_at)
\set ON_ERROR_STOP on
\set EXPECT_OK 13
\pset pager off
select (select count(*) from public.so) as y_so, (select count(*) from public.fc_shipment) as y_fc, (select count(*) from public.fc_booking) as y_bk, (select count(*) from public.fc_shipment_so) as y_fso, (select count(*) from public.ims_staff) as y_staff, (select count(*) from public.ref_warehouse) as y_wh, (select count(*) from public.customer) as y_cu \gset
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
-- 가짜 행만 · 반환 순서 그대로(letter 를 잇는다 · 실물 행은 뺀다)
create function pg_temp.lst(p_wh uuid default null) returns text language plpgsql as $$   -- plpgsql: 몸은 첫 호출 때 풀린다(시험 갈래에서는 만들 때 함수가 아직 없다)
declare v jsonb; v_s text;
begin
  v := public.fc_pickup_attention_list(p_wh);
  select coalesce(string_agg(i.k, ' ' order by r.ord), '(none)') into v_s
    from jsonb_array_elements(v->'rows') with ordinality r(x, ord) join t_ids i on i.v = r.x->>'booking_id';
  return v_s;
end $$;
create function pg_temp.row_of(p_k text) returns jsonb language plpgsql as $$
begin
  return (select r.x from jsonb_array_elements((public.fc_pickup_attention_list(null))->'rows') r(x) where r.x->>'booking_id' = pg_temp.id(p_k)::text);
end $$;

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
declare v_wa uuid; v_wb uuid; v_cust uuid; v_cur uuid; v_ups uuid; v_pur uuid; v_so uuid; v_sh uuid; v_id uuid; v_today date := public.ims_today(); i int; k text;
  v_u_admin uuid; v_u_book uuid; v_u_sales uuid; v_u_none uuid;
  v_req_today jsonb; v_req_tomorrow jsonb; v_req_old jsonb; v_req_nodate jsonb; v_req_regular jsonb; v_req_pallet jsonb; v_req jsonb;
  v_status text; v_sstatus text; v_serr text; v_chk timestamptz; v_booked timestamptz; v_conf text; v_wh uuid; v_pkg text; v_att int; v_cancel timestamptz; v_failed timestamptz; v_fstatus text; v_sos text[]; v_charge text;
begin
  select id into v_cust from public.customer order by created_at limit 1;                 -- 읽기만(FK · 이름은 안 찍는다)
  select id into v_cur  from public.ref_currency order by created_at limit 1;
  select id into v_ups  from public.ref_carrier where name = 'UPS';
  select id into v_pur  from public.ref_carrier where name = 'Purolator';
  insert into public.ref_warehouse (name, source, is_active, address_line1, city, state_province, postal_code, country, freightcom_account, timezone, closes_at, contact_name, phone)
    values ('FCX A', 'manual', true, '1 Fcx Road', 'Toronto', 'ON', 'M9N 2V8', 'Canada', 'FCX', 'America/Toronto', '17:00', 'FCX Contact', '(416) 555-0100') returning id into v_wa;
  insert into public.ref_warehouse (name, source, is_active, address_line1, city, state_province, postal_code, country, freightcom_account, timezone, closes_at, contact_name, phone)
    values ('FCX B', 'manual', true, '2 Fcx Road', 'Edmonton', 'AB', 'T5A 0A1', 'Canada', 'FCX', 'America/Regina', '16:00', 'FCX Contact', '(780) 555-0100') returning id into v_wb;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-admin4@test.invalid', 'FCX Admin', 'admin', '[]', '{}') returning auth_user_id into v_u_admin;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-booker4@test.invalid', 'FCX Booker', 'worker', '["wms","fulfillment","freight_booking"]', array[v_wa]) returning auth_user_id into v_u_book;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-sales4@test.invalid', 'FCX Sales', 'worker', '["sales"]', '{}') returning auth_user_id into v_u_sales;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'fcx-none4@test.invalid', 'FCX None', 'worker', '["wms","receiving"]', '{}') returning auth_user_id into v_u_none;
  insert into t_ids values ('wa', v_wa), ('wb', v_wb), ('u_admin', v_u_admin), ('u_book', v_u_book), ('u_sales', v_u_sales), ('u_none', v_u_none);
  for i in 1..20 loop
    insert into public.so (customer_id, channel, intake, currency_id, so_number, status, created_at, closed_at) values (v_cust, 'warehouse', 'manual', v_cur, 'SO-799' || lpad(i::text, 2, '0'), 'fulfilled', now() - interval '2 hours' + (i * interval '1 minute'), now() - interval '1 hour') returning id into v_id;
    insert into t_ids values ('s' || i, v_id);
  end loop;
  v_req_today    := jsonb_build_object('pickup_details', jsonb_build_object('pre_scheduled_pickup', false, 'date', jsonb_build_object('year', extract(year from v_today)::int, 'month', extract(month from v_today)::int, 'day', extract(day from v_today)::int), 'ready_at', '{"hour": 9, "minute": 30}'::jsonb));
  v_req_tomorrow := jsonb_build_object('pickup_details', jsonb_build_object('pre_scheduled_pickup', false, 'date', jsonb_build_object('year', extract(year from v_today + 1)::int, 'month', extract(month from v_today + 1)::int, 'day', extract(day from v_today + 1)::int)));
  v_req_old      := jsonb_build_object('pickup_details', jsonb_build_object('pre_scheduled_pickup', false, 'date', jsonb_build_object('year', extract(year from v_today - 4)::int, 'month', extract(month from v_today - 4)::int, 'day', extract(day from v_today - 4)::int)));
  v_req_nodate   := '{"pickup_details": {"pre_scheduled_pickup": false}}';
  v_req_regular  := '{"pickup_details": {"pre_scheduled_pickup": true}}';
  v_req_pallet   := jsonb_build_object('dispatch_details', jsonb_build_object('date', jsonb_build_object('year', extract(year from v_today)::int, 'month', extract(month from v_today)::int, 'day', extract(day from v_today)::int)));
  i := 0;
  foreach k in array array['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j1', 'j2', 'k', 'l', 'm', 'n', 'o'] loop
    -- 기본값
    v_status := 'booked'; v_sstatus := null; v_serr := null; v_chk := null; v_booked := now() - interval '3 hours'; v_conf := null; v_wh := v_wa; v_pkg := 'package'; v_att := 1; v_cancel := null; v_failed := null; v_fstatus := 'booked'; v_req := v_req_today;
    case k
      when 'a'  then v_sstatus := 'error';   v_serr := 'carrier:Missing or invalid ContactName'; v_chk := now() - interval '170 minutes';
      when 'b'  then v_sstatus := 'done';    v_chk := now() - interval '20 minutes'; v_booked := now() - interval '3 hours' + interval '1 minute';
      when 'c'  then v_sstatus := 'pending'; v_chk := now() - interval '40 minutes'; v_booked := now() - interval '3 hours' + interval '2 minutes';
      when 'd'  then v_booked := now() - interval '3 hours' + interval '3 minutes';
      when 'e'  then v_booked := now() - interval '5 minutes';
      when 'f'  then v_sstatus := 'pending'; v_chk := now() - interval '1 minute'; v_booked := now() - interval '5 minutes';
      when 'g'  then v_sstatus := 'done';    v_chk := now() - interval '20 minutes'; v_conf := '26368294';
      when 'h'  then v_req := v_req_regular;
      when 'i'  then v_req := v_req_pallet;  v_pkg := 'pallet';
      when 'j1' then v_status := 'cancelled'; v_cancel := now() - interval '2 hours' - interval '10 minutes';
      when 'j2' then v_sstatus := 'error';   v_serr := 'carrier:Sender Name is a mandatory field.'; v_chk := now() - interval '110 minutes'; v_booked := now() - interval '2 hours'; v_att := 2; v_req := v_req_nodate;
      when 'k'  then v_status := 'failed';   v_failed := now() - interval '1 hour'; v_booked := null; v_fstatus := 'selected';
      when 'l'  then v_sstatus := 'error';   v_serr := 'carrier:rejected'; v_chk := now() - interval '71 hours'; v_booked := now() - interval '72 hours'; v_req := v_req_old;
      when 'm'  then v_sstatus := 'error';   v_serr := 'carrier:rejected'; v_chk := now() - interval '71 hours'; v_booked := now() - interval '72 hours'; v_req := v_req_tomorrow;
      when 'n'  then v_sstatus := 'error';   v_serr := 'carrier:rejected'; v_chk := now() - interval '50 minutes'; v_booked := now() - interval '1 hour'; v_wh := v_wb;
      when 'o'  then v_sstatus := 'error';   v_serr := 'carrier:rejected'; v_chk := now() - interval '230 minutes'; v_booked := now() - interval '4 hours';
    end case;
    if k = 'j2' then v_sh := pg_temp.id('sh_j1');
    else
      i := i + 1;
      v_sos := case when k = 'o' then array['s17', 's18', 's19'] else array['s' || i] end;   -- o 만 셋(fc_shipment_so 는 live SO 하나에 발송 하나 · 다른 글자와 겹치지 않게 17 ~ 19)
      if k = 'o' then v_charge := 's18'; else v_charge := 's' || i; end if;
      insert into public.fc_shipment (status, origin_warehouse_id, packaging_type, charge_so_id, customer_id, origin, destination, options, units, request, payload_hash, created_in, freightcom_account)
        values (v_fstatus, v_wh, v_pkg, pg_temp.id(v_charge), v_cust, '{}', '{}', '{}', '[]', '{}', 'fcx-p4-' || k, 'wms', 'FCX') returning id into v_sh;
      insert into public.fc_shipment_so (shipment_id, so_id, live) select v_sh, pg_temp.id(x), true from unnest(v_sos) x;
      insert into t_ids values ('sh_' || k, v_sh);
    end if;
    insert into public.fc_booking (shipment_id, attempt, unique_id, status, account, carrier_id, service_id, tracking_number, pickup, request, response, freightcom_shipment_id, state, booked_at, cancelled_at, failed_at, pickup_confirmation, schedule_status, schedule_error, schedule_checked_at)
      values (v_sh, v_att, 'fcx-p4-' || k, v_status, 'FCX', case when k in ('b', 'j2') then v_pur else v_ups end, case when k in ('b', 'j2') then 'purolatorcourier.ground' else 'ups.standard' end, 'T-' || k,
              jsonb_build_object('regular_pickup', false, 'date', v_today, 'ready_at', '09:30', 'ready_until', '17:00'), v_req,
              '{"shipment": {"state": "waiting-for-transit", "pickup_confirmation_number": ""}}', case when k = 'k' then null else 'FCX-' || k end, 'waiting-for-transit',
              v_booked, v_cancel, v_failed, v_conf, v_sstatus, v_serr, v_chk) returning id into v_id;
    update public.fc_shipment set booking_id = v_id where id = v_sh;
    insert into t_ids values (k, v_id);
  end loop;
end $$;
set local session_replication_role = origin;

-- ── 갈래 P0 ~ P12 (한 왕복) ──
do $$
declare p jsonb; r jsonb; v_s1 text; v_s2 text; v_s3 text; v_admin text := pg_temp.id('u_admin')::text; v_book text := pg_temp.id('u_book')::text; v_sales text := pg_temp.id('u_sales')::text; v_none text := pg_temp.id('u_none')::text; v_wa uuid := pg_temp.id('wa'); v_wb uuid := pg_temp.id('wb');
begin
  -- P0 착지 · 정적
  perform pg_temp.chk('P0 function count 1 · acl authenticated only · nowhere = 0 · fc_pickup_check · fc_booking_for_shipment · fc_pickup_poll_due md5 untouched',
    (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_pickup_attention_list')::text || '/' ||
    (select coalesce(proacl::text, '(null)') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_pickup_attention_list') || '/' ||
    (select pg_temp.nowhere(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_pickup_attention_list')::text || '/' ||
    (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_pickup_check') || '/' ||
    (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_booking_for_shipment') || '/' ||
    (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_pickup_poll_due'),
    '1/{postgres=X/postgres,authenticated=X/postgres}/0/b3a17787b3585d37712930e9315bc300/7413429f0b0e31d04a6e926042d6e6cf/8d3038d6f72ae14cc255a7e3a6ab226f');
  -- P1 admin · 창고 없음 — 대상 · 정렬
  perform pg_temp.as_user(v_admin);
  perform pg_temp.chk('P1 admin · all warehouses = o a b c d n e m j2 (pickup date asc · null last → booked_at) — not f(pending 5 min) g(confirmed) h(regular) i(pallet) j1(cancelled) k(failed) l(window past)',
    pg_temp.lst(null), 'o a b c d n e m j2');
  -- P2 봉투
  p := public.fc_pickup_attention_list(null);
  perform pg_temp.chk('P2 envelope — warehouse_id null · warehouse null · as_of · count = rows length · count ≥ 9 (fixtures) · keys',
    (p->>'warehouse_id' is null)::text || '/' || (p->>'warehouse' is null)::text || '/' || (p->>'as_of' is not null)::text || '/' || ((p->>'count')::int = jsonb_array_length(p->'rows'))::text || '/' || ((p->>'count')::int >= 9)::text || '/' || (select string_agg(k, ',' order by k) from jsonb_object_keys(p) k),
    'true/true/true/true/true/as_of,count,rows,warehouse,warehouse_id');
  -- P3 행 내용(a · error)
  r := pg_temp.row_of('a');
  perform pg_temp.chk('P3 row a — booking_status booked · attempt 1 · schedule_status error · schedule_error · message "Freightcom says: …" · not_scheduled true · pending false · minutes ≥ 180 · carrier UPS · service · account FCX · warehouse FCX A · so_number SO-79901 · so_numbers [SO-79901] · so_id = s1 · customer_name present · Freightcom id · tracking · pickup_date today · ready 09:30 ~ 17:00 · checked_at · done_at null · confirmation_mismatch false · window_until · keys 30',
    (r->>'booking_status') || '/' || (r->>'attempt') || '/' || (r->>'schedule_status') || '/' || (r->>'schedule_error') || '/' || (r->>'message') || '/' || (r->>'not_scheduled') || '/' || (r->>'pending') || '/' || ((r->>'minutes_since_booked')::int >= 180)::text || '/' ||
    (r->>'carrier') || '/' || (r->>'service_id') || '/' || (r->>'account') || '/' || (r->>'warehouse') || '/' || (r->>'so_number') || '/' || (r->'so_numbers')::text || '/' || (r->>'so_id' = pg_temp.id('s1')::text)::text || '/' || (nullif(r->>'customer_name', '') is not null)::text || '/' ||
    (r->>'freightcom_shipment_id') || '/' || (r->>'tracking_number') || '/' || ((r->>'pickup_date')::date = public.ims_today())::text || '/' || (r->>'ready_at') || '~' || (r->>'ready_until') || '/' || (r->>'schedule_checked_at' is not null)::text || '/' || (r->>'schedule_done_at' is null)::text || '/' || (r->>'confirmation_mismatch') || '/' || (r->>'window_until' is not null)::text || '/' || (select count(*) from jsonb_object_keys(r))::text,
    'booked/1/error/carrier:Missing or invalid ContactName/Pickup NOT scheduled — Freightcom says: carrier:Missing or invalid ContactName/true/false/true/UPS/ups.standard/FCX/FCX A/SO-79901/["SO-79901"]/true/true/FCX-a/T-a/true/09:30~17:00/true/true/false/true/30');
  -- P4 글 — b(done 번호 없음) · c(pending 15 분 지남) · d(읽은 적 없음) · e(읽은 적 없음 · 5 분 — 이견 3) · j2(날짜 없음 → pickup_date null · 창 48 h)
  perform pg_temp.chk('P4 messages — b done-no-number · c pending N minutes · d · e not checked since booking (e only 5 min old — still listed) · j2 pickup_date null · window = booked + 48 h',
    (pg_temp.row_of('b')->>'message') || ' | ' || regexp_replace(pg_temp.row_of('c')->>'message', '\d+ minutes', 'N minutes') || ' | ' || (pg_temp.row_of('d')->>'message') || ' | ' || (pg_temp.row_of('e')->>'message') || ' | ' || ((pg_temp.row_of('e')->>'minutes_since_booked')::int < 15)::text || ' | ' ||
    (pg_temp.row_of('j2')->>'pickup_date' is null)::text || '/' || (select ((pg_temp.row_of('j2')->>'window_until')::timestamptz = b.booked_at + interval '48 hours')::text from public.fc_booking b where b.id = pg_temp.id('j2')),
    'Pickup NOT scheduled — Freightcom says done but gave no confirmation number | Pickup NOT scheduled — Freightcom has been ''pending'' for N minutes since booking · ask Freightcom for the pickup | Pickup not confirmed — not checked with Freightcom since booking · use Check pickup | Pickup not confirmed — not checked with Freightcom since booking · use Check pickup | true | true/true');
  -- P5 같은 발송 시도 둘 — j2 만 · attempt 2 · j1 없음(P1 에서도) · 운송사 Purolator
  r := pg_temp.row_of('j2');
  perform pg_temp.chk('P5 j: second attempt only — attempt 2 · carrier Purolator · shipment_id = sh_j1 · first attempt (cancelled) absent',
    (r->>'attempt') || '/' || (r->>'carrier') || '/' || (r->>'shipment_id' = pg_temp.id('sh_j1')::text)::text || '/' || (pg_temp.row_of('j1') is null)::text, '2/Purolator/true/true');
  -- P6 SO 셋 — 운임 SO 먼저 · 나머지 created_at 순 · so_number = 운임 SO
  r := pg_temp.row_of('o');
  perform pg_temp.chk('P6 o: so_numbers = [SO-79918 (charge), SO-79917, SO-79919] · so_number SO-79918 · so_id = s18', (r->'so_numbers')::text || '/' || (r->>'so_number') || '/' || (r->>'so_id' = pg_temp.id('s18')::text)::text, '["SO-79918", "SO-79917", "SO-79919"]/SO-79918/true');
  -- P7 창 — m(72 h · 픽업 내일) 창 끝 = 내일 + 2 일 00:00 Toronto · l(픽업 4 일 전) 없음 · poll_due 와 같은 식
  perform pg_temp.chk('P7 window — m window_until = tomorrow + 2 at 00:00 Toronto (> booked + 48 h) · l absent · m window equals fc_pickup_poll_due''s for the same row',
    (select ((pg_temp.row_of('m')->>'window_until')::timestamptz = ((public.ims_today() + 3)::timestamp at time zone 'America/Toronto'))::text || '/' || ((pg_temp.row_of('m')->>'window_until')::timestamptz > b.booked_at + interval '48 hours')::text from public.fc_booking b where b.id = pg_temp.id('m')) || '/' ||
    (pg_temp.row_of('l') is null)::text || '/' || (select ((pg_temp.row_of('m')->>'window_until')::timestamptz = d.window_until)::text from public.fc_pickup_poll_due(50) d where d.booking_id = pg_temp.id('m')),
    'true/true/true/true');
  -- P8 창고 ① p_warehouse_id — B 면 n 만 · 봉투 warehouse 이름 · A 면 n 빠짐 · 모르는 id 거부
  p := public.fc_pickup_attention_list(v_wb);
  v_s1 := pg_temp.try(format('select public.fc_pickup_attention_list(%L)::text', gen_random_uuid()));
  perform pg_temp.chk('P8 p_warehouse_id — B → n only · envelope warehouse FCX B · warehouse_id B · A → o a b c d e m j2 · unknown id → Warehouse not found',
    pg_temp.lst(v_wb) || ' | ' || (p->>'warehouse') || '/' || (p->>'warehouse_id' = v_wb::text)::text || ' | ' || pg_temp.lst(v_wa) || ' | ' || v_s1,
    'n | FCX B/true | o a b c d e m j2 | ERR P0001: Warehouse not found');
  -- P9 창고 ② ims_can_warehouse — booker(A 만) → n 없음 · B 를 골라도 0 · sales(빈 접근 = 전부) → admin 과 같다
  perform pg_temp.as_user(v_book);
  v_s1 := pg_temp.lst(null); v_s2 := pg_temp.lst(v_wb);
  perform pg_temp.as_user(v_sales);
  v_s3 := pg_temp.lst(null);
  perform pg_temp.chk('P9 booker (access A only) → o a b c d e m j2 · booker + warehouse B → (none) · sales worker (empty access = all) → same as admin', v_s1 || ' | ' || v_s2 || ' | ' || v_s3, 'o a b c d e m j2 | (none) | o a b c d n e m j2');
  -- P10 문 — 권한 없는 직원 거부 · anon 거부(역할) · 글은 fc_booking_for_shipment 과 같다
  perform pg_temp.as_user(v_none);
  v_s1 := pg_temp.try('select public.fc_pickup_attention_list(null)::text');
  v_s2 := pg_temp.try('set local role anon; select public.fc_pickup_attention_list(null)::text');
  reset role;
  perform pg_temp.chk('P10 staff without sales · fulfillment · freight_booking → refused (same words as fc_booking_for_shipment) · anon → permission denied', v_s1 || ' | ' || left(v_s2, 9),
    'ERR P0001: You cannot see freight bookings — ask an admin for the ''sales'', ''fulfillment'' or ''freight_booking'' permission | ERR 42501');
  -- P11 확인번호가 들어오면 빠진다(a · service 저장) · 취소하면 빠진다(o · replica 로 흉내)
  perform pg_temp.as_user(v_admin, 'service_role');
  p := public.fc_book_schedule_save(pg_temp.id('a'), '{"error": "", "pickup_confirmation_number": "29FBD3C23EA", "status": "done"}');
  set local session_replication_role = replica;
  update public.fc_booking set status = 'cancelled', cancelled_at = now() where id = pg_temp.id('o');
  update public.fc_shipment set status = 'selected' where id = pg_temp.id('sh_o');
  set local session_replication_role = origin;
  perform pg_temp.as_user(v_admin);
  perform pg_temp.chk('P11 a confirmed via schedule_save → leaves · o cancelled → leaves · list = b c d n e m j2', (p->>'pickup_confirmation') || ' | ' || pg_temp.lst(null), '29FBD3C23EA | b c d n e m j2');
  -- P12 실물 — 지금 메인 DB 의 실물 행(가짜 제외)은 전부 not_scheduled · booked · 현재 시도 · 창 안(값은 찍지 않는다 · 개수만 info 줄)
  perform pg_temp.chk('P12 real rows in the list (admin) — every row is booked · not_scheduled true · a current attempt · inside its window · has so_number',
    coalesce((select bool_and((x->>'booking_status') = 'booked' and (x->>'not_scheduled')::boolean and (x->>'window_until')::timestamptz > now() and nullif(x->>'so_number', '') is not null
                              and exists (select 1 from public.fc_shipment f where f.id = (x->>'shipment_id')::uuid and f.booking_id = (x->>'booking_id')::uuid))::text
                from jsonb_array_elements((public.fc_pickup_attention_list(null))->'rows') x where x->>'booking_id' not in (select v from t_ids)), 'true'), 'true');
end $$;

-- ── 결과 ──
select clock_timestamp() - :'t_begin0000'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select set_config('request.jwt.claims', json_build_object('sub', pg_temp.id('u_admin'), 'role', 'authenticated')::text, true) as as_admin \gset
select count(*) as info_real_rows_now, string_agg(distinct coalesce(x->>'schedule_status', 'never-read'), ',') as statuses from jsonb_array_elements((public.fc_pickup_attention_list(null))->'rows') x where x->>'booking_id' not in (select v from t_ids);
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.so) = :y_so and (select count(*) from public.fc_shipment) = :y_fc and (select count(*) from public.fc_booking) = :y_bk and (select count(*) from public.fc_shipment_so) = :y_fso and (select count(*) from public.ims_staff) = :y_staff and (select count(*) from public.ref_warehouse) = :y_wh and (select count(*) from public.customer) = :y_cu then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when to_regprocedure('public.fc_pickup_attention_list(uuid)') is null then 'Z2 OK rollback restored · no function' else 'Z2 MISMATCH' end as z2;
\endif
