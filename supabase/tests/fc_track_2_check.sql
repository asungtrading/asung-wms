-- supabase/tests/fc_track_2_check.sql — fc-track-2 검증 (2026-11-10 밤 토론토 · 판정 1158 · 1159 · 1160 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] 기준(begin 앞) → begin(lock_timeout 3s) → 가짜 재료(DO 하나 — 직원 넷 · 발송 넷 · 예약 스물하나 · 실제 예약 하나를 복제해 표에 직접) → (-v mig 면 \i) → 새 칸 재료 → 시나리오 → 구조 · 정적 검사 → 집계 → rollback
--   Claude Code(시험 · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111020326_fc_track_2_state_events_mark_cancelled.sql -f supabase/tests/fc_track_2_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(갈래마다 같다)
--   마른 실행(적용 전 · -v mig 없이): 새 창구 · 칸이 없어 대부분 FAIL 로 잡히고 exit 3(죽지 않는다 — 새 것을 부르는 곳은 모두 try 안)
--   ⚠️ 레포 루트에서 돌린다 — fixture 둘(supabase/functions/freightcom/fixtures/track-*.json)을 psql 이 읽는다(deno 시험과 같은 파일)
--   ⚠️ 실물을 건드리는 곳은 셋 · 모두 rollback 안: C1(실제 예약 1474f64f 를 인정 — 아직 booked 일 때만 통과한다 · Caleb 이 화면에서 실제로 인정한 뒤에는 C1 이 FAIL 이 맞다) · C2(SO-21094 의 칸을 가짜 예약이 되돌림 — 출고된 SO 의 칸을 고칠 수 있는가) ·
--      T6(실제 booked 예약의 track_done_at 을 채워 목록에서 뺀다 — fc_track_due 의 limit 상한 50 이 실제 53 건보다 작다) · T6 은 잠금 구간을 줄이려고 파일 끝
\set ON_ERROR_STOP on
\pset pager off
\if :{?mig}
\set EXPECT_OK 40
\else
\set EXPECT_OK 40
\endif
\set fx_ship `cat supabase/functions/freightcom/fixtures/track-shipment.json`
\set fx_events `cat supabase/functions/freightcom/fixtures/track-events.json`
\set REAL_B 1474f64f-bb59-453f-bd79-3f64fcb2662d
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'fc\_%';
create temp table t_ids (k text primary key, v text);
create temp table t_res (n serial, label text, got text, want text, ok boolean);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns void language sql as $$ insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want); $$;
create function pg_temp.id(p_k text) returns text language sql as $$ select v from t_ids where k = p_k $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$ insert into t_ids values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.keyof(p_v text) returns text language sql as $$ select coalesce((select k from t_ids where v = p_v and k !~ '^(src|pre)_' limit 1), '?' || left(p_v, 8)) $$;
create function pg_temp.as_conn(p_role text, p_claims jsonb, p_sql text) returns text language plpgsql as $$
declare v text; v_old text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', coalesce(p_claims::text, ''), true);
  execute format('set local role %I', p_role);
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  execute 'reset role';
  perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
  return coalesce(v, '(null)');
end $$;
-- svc = EF 의 service_role 길 · usr(k) = 가짜 직원 k 의 세션(W freight_booking + TOR · S sales · 창고 전부 · N 권한 없음 · E freight_booking + EDM 만) · try = postgres 로(읽기 · 재료)
create function pg_temp.svc(p_sql text) returns text language sql as $$ select pg_temp.as_conn('service_role', '{"role":"service_role"}'::jsonb, p_sql) $$;
create function pg_temp.usr(p_k text, p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', jsonb_build_object('role', 'authenticated', 'sub', pg_temp.id('auth_' || p_k)), p_sql) $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  return coalesce(v, '(null)');
end $$;
create function pg_temp.j(p_v text, p_key text default null) returns text language sql as $$ select case when p_v like 'ERR %' or p_v = '(null)' then p_v when p_key is null then (p_v::jsonb)::text else coalesce(p_v::jsonb->>p_key, '(null)') end $$;
create function pg_temp.err(p_v text, p_like text) returns text language sql as $$ select case when p_v like 'ERR %' and p_v like p_like then 'refused' else left(p_v, 200) end $$;
-- 예약 한 행에서 식 하나(새 칸을 읽어도 마른 실행이 죽지 않게 try)
create function pg_temp.bk(p_k text, p_expr text) returns text language sql as $$ select pg_temp.try(format('select (%s)::text from public.fc_booking b where b.id = %L', p_expr, pg_temp.id(p_k))) $$;
create function pg_temp.save(p_k text, p_ship jsonb, p_events jsonb) returns text language sql as $$ select pg_temp.svc(format('select public.fc_track_save(%L, %L::jsonb, %L::jsonb)::text', pg_temp.id(p_k), p_ship, p_events)) $$;
create function pg_temp.mark(p_as text, p_k text, p_note text) returns text language sql as $$ select pg_temp.usr(p_as, format('select public.fc_book_mark_cancelled(%L, %L)::text', pg_temp.id(p_k), p_note)) $$;
create function pg_temp.so_cols(p_so text) returns text language sql as $$ select coalesce(s.carrier, '-') || '|' || coalesce(s.carrier_id::text, '-') || '|' || coalesce(s.tracking_number, '-') || '|' || s.status from public.so s where s.so_number = p_so $$;
-- 가짜 예약 하나 — 실제 예약(src_b)을 복제하고 칸을 덮는다(새 칸 여섯은 null 로 · 적용 전에는 모르는 열쇠라 무시된다)
create function pg_temp.mkb(p_k text, p_f text, p_attempt int, p_over jsonb default '{}'::jsonb) returns void language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into public.fc_booking
  select (jsonb_populate_record(null::public.fc_booking, to_jsonb(b) || jsonb_build_object(
            'id', v_id, 'shipment_id', pg_temp.id(p_f), 'attempt', p_attempt, 'unique_id', 'zzfct-' || p_k, 'freightcom_shipment_id', 'zzfct-ship-' || p_k, 'status', 'booked', 'state', 'in-transit',
            'pickup_confirmation', null, 'bol_number', null, 'so_written', '[]'::jsonb, 'labels', null, 'response', '{"zz":"orig"}'::jsonb, 'error', null, 'cancel_error', null, 'cancelled_at', null, 'cancelled_by', null, 'failed_at', null,
            'schedule_status', null, 'schedule_error', null, 'schedule_checked_at', null, 'schedule_response', null, 'schedule_done_at', null, 'booked_at', now() - interval '1 hour',
            'state_checked_at', null, 'delivered_at', null, 'track_last', null, 'track_done_at', null, 'cancel_source', null, 'cancel_note', null) || p_over)).*
    from public.fc_booking b where b.id = pg_temp.id('src_b')::uuid;
  perform pg_temp.put(p_k, v_id::text);
end $$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g'); exit when v_chunk = v_prev; end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
-- 옛 판(적용 전 본문 그대로 · prosrc md5 b3a17787… · 8d3038d6…) — P2 가 새 판과 견준다(확인 갈래에서도 옛 판이 있어야 하므로 여기에 뜬다)
create function pg_temp.pc_old(b public.fc_booking) returns jsonb language plpgsql stable as $$
declare
  v_needed  boolean;
  v_pkg     text;
  v_p       jsonb;
  v_fc_conf text;
  v_mis     boolean;
  v_read    boolean;
  v_age     int;
  v_bad     boolean;
  v_pend    boolean;
  v_not     boolean;
  v_msg     text;
begin
  v_pkg := case when b.request ? 'dispatch_details' then 'pallet' else 'package' end;
  v_needed := b.status = 'booked' and v_pkg = 'package' and (b.request#>>'{pickup_details,pre_scheduled_pickup}') = 'false';
  v_p := case when b.schedule_response is not null then public.fc_schedule_parse(b.schedule_response) end;
  v_fc_conf := v_p->>'confirmation';
  v_mis := b.pickup_confirmation is not null and v_fc_conf is not null and v_fc_conf <> b.pickup_confirmation;
  v_read := b.schedule_checked_at is not null;
  v_age := case when b.booked_at is not null then floor(extract(epoch from (now() - b.booked_at)) / 60)::int end;
  v_bad := b.schedule_status is not null and b.schedule_status not in ('pending', 'done');
  v_pend := v_needed and b.pickup_confirmation is null and coalesce(b.schedule_status = 'pending', false) and coalesce(v_age, 0) < 15;
  v_not := v_needed and b.pickup_confirmation is null and (v_bad or not v_read or coalesce(v_age, 0) >= 15 or coalesce(b.schedule_status = 'done', false));
  v_msg := case
    when b.status <> 'booked' then null
    when v_pkg = 'pallet' then 'Pallet dispatch — no parcel pickup to check' || case when b.pickup_confirmation is not null then ' · confirmation ' || b.pickup_confirmation else '' end
    when not v_needed then 'Regular pickup — no pickup request was sent' || case when b.pickup_confirmation is not null then ' · confirmation ' || b.pickup_confirmation else '' end
    when b.pickup_confirmation is not null then 'Pickup scheduled — confirmation ' || b.pickup_confirmation || case when v_mis then ' · Freightcom now reports ' || v_fc_conf || ' — check which one the driver has' else '' end
    when v_bad then 'Pickup NOT scheduled — Freightcom says: ' || coalesce(b.schedule_error, 'schedule status ''' || b.schedule_status || '''')
    when b.schedule_status = 'done' then 'Pickup NOT scheduled — Freightcom says done but gave no confirmation number'
    when not v_read then 'Pickup not confirmed — not checked with Freightcom since booking · use Check pickup'
    when v_age >= 15 then format('Pickup NOT scheduled — Freightcom has been ''pending'' for %s minutes since booking · ask Freightcom for the pickup', v_age)
    else 'Freightcom is still scheduling the pickup — check again in a few minutes'
  end;
  return jsonb_build_object('needed', v_needed, 'packaging', v_pkg, 'not_scheduled', v_not, 'pending', v_pend, 'status', b.schedule_status, 'error', b.schedule_error, 'checked_at', b.schedule_checked_at,
                            'confirmation', b.pickup_confirmation, 'freightcom_confirmation', v_fc_conf, 'confirmation_mismatch', v_mis, 'minutes_since_booked', v_age, 'message', v_msg);
end $$;
create function pg_temp.due_old(p_limit int) returns table (booking_id uuid) language sql stable as $$
  with c as (
    select b.id, b.shipment_id, b.attempt, b.account, b.freightcom_shipment_id, b.booked_at, b.schedule_status, b.schedule_checked_at,
           (select make_date((b.request#>>'{pickup_details,date,year}')::int, (b.request#>>'{pickup_details,date,month}')::int, (b.request#>>'{pickup_details,date,day}')::int)
              where (b.request#>>'{pickup_details,date,year}') ~ '^\d{4}$' and (b.request#>>'{pickup_details,date,month}') ~ '^\d{1,2}$' and (b.request#>>'{pickup_details,date,day}') ~ '^\d{1,2}$'
                and (b.request#>>'{pickup_details,date,month}')::int between 1 and 12 and (b.request#>>'{pickup_details,date,day}')::int between 1 and 31) as pickup_date
      from public.fc_booking b
     where b.status = 'booked'
       and not (b.request ? 'dispatch_details')
       and (b.request#>>'{pickup_details,pre_scheduled_pickup}') = 'false'
       and b.pickup_confirmation is null
       and nullif(btrim(b.freightcom_shipment_id), '') is not null
       and b.booked_at is not null
  ), w as (
    select c.*, greatest(c.booked_at + interval '48 hours', ((c.pickup_date + 2)::timestamp at time zone 'America/Toronto')) as window_until,
           case when now() - c.booked_at < interval '2 hours' then 'fast' else 'slow' end as tier
      from c
  )
  select w.id
    from w
   where now() < w.window_until
     and (w.tier = 'fast' or w.schedule_checked_at is null or w.schedule_checked_at < now() - interval '30 minutes')
   order by w.booked_at, w.attempt
   limit (case when p_limit between 1 and 50 then p_limit else 10 end);
$$;
-- 기준(begin 앞 · 실물 읽기)
select (select count(*) from public.fc_booking) as n_bk0, (select count(*) from public.fc_shipment) as n_f0, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from t_pre) as n_fn0,
       (select max(version) from supabase_migrations.schema_migrations) as ver0, pg_temp.so_cols('SO-21022') as so22_0, pg_temp.so_cols('SO-21094') as so94_0,
       (select b.status || '|' || coalesce(b.state, '-') || '|' || md5(coalesce(b.response::text, '')) from public.fc_booking b where b.id = :'REAL_B') as real_b0 \gset
select pg_temp.put('pre_so22', :'so22_0'), pg_temp.put('pre_so94', :'so94_0'), pg_temp.put('pre_real_b', :'real_b0'), pg_temp.put('real', :'REAL_B');
\echo '── 기준: 예약' :n_bk0 '· 발송' :n_f0 '· fc_ 함수' :n_fn0 '· 마지막 마이그레이션' :ver0 '· 실제 1474f64f' :real_b0

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
-- ── 가짜 재료(마이그레이션 앞 — 새 칸을 쓰지 않는다) ──
do $$
declare
  v_tor uuid := '045e4ca6-b7a9-446e-9e6a-a5a0db56d456'; v_edm uuid := '95caece3-cf3e-4832-a583-e233254feadc';
  v_src_b uuid; v_src_f uuid; v_k text; v_id uuid; v_so public.so%rowtype;
begin
  select b.id, b.shipment_id into v_src_b, v_src_f from public.fc_booking b join public.fc_shipment f on f.id = b.shipment_id
   where b.status = 'booked' and not (b.request ? 'dispatch_details') and (b.request#>>'{pickup_details,pre_scheduled_pickup}') = 'false' and f.origin_warehouse_id = v_tor order by b.booked_at, b.id limit 1;
  if v_src_b is null then raise exception 'fc_track_2_check: no booked Toronto package booking with a pickup request to clone'; end if;
  perform pg_temp.put('src_b', v_src_b::text), pg_temp.put('src_trk', (select b.tracking_number from public.fc_booking b where b.id = v_src_b));
  insert into public.ims_staff (id, auth_user_id, email, name, role, perms, warehouse_access) values
    ('f1c70000-0000-4000-8000-0000000000a1', 'f1c70000-0000-4000-8000-000000000001', 'fc-track-2-w@asung.invalid', 'ZZFCT Booker', 'manager', '["freight_booking"]', array[v_tor]),
    ('f1c70000-0000-4000-8000-0000000000a2', 'f1c70000-0000-4000-8000-000000000002', 'fc-track-2-s@asung.invalid', 'ZZFCT Sales', 'manager', '["sales"]', '{}'),
    ('f1c70000-0000-4000-8000-0000000000a3', 'f1c70000-0000-4000-8000-000000000003', 'fc-track-2-n@asung.invalid', 'ZZFCT Nobody', 'manager', '[]', '{}'),
    ('f1c70000-0000-4000-8000-0000000000a4', 'f1c70000-0000-4000-8000-000000000004', 'fc-track-2-e@asung.invalid', 'ZZFCT Edmonton', 'manager', '["freight_booking"]', array[v_edm]);
  perform pg_temp.put('auth_W', 'f1c70000-0000-4000-8000-000000000001'), pg_temp.put('auth_S', 'f1c70000-0000-4000-8000-000000000002'), pg_temp.put('auth_N', 'f1c70000-0000-4000-8000-000000000003'), pg_temp.put('auth_E', 'f1c70000-0000-4000-8000-000000000004'),
          pg_temp.put('W', 'f1c70000-0000-4000-8000-0000000000a1');
  foreach v_k in array array['f1', 'fp1', 'fp2', 'fc2'] loop
    v_id := gen_random_uuid();
    insert into public.fc_shipment select (jsonb_populate_record(null::public.fc_shipment, to_jsonb(f) || jsonb_build_object('id', v_id, 'booking_id', null, 'status', 'booked'))).* from public.fc_shipment f where f.id = v_src_f;
    perform pg_temp.put(v_k, v_id::text);
  end loop;
  -- 저장 시험
  perform pg_temp.mkb('k1', 'f1', 1, '{"freightcom_shipment_id":"fcShipTrack1"}');
  perform pg_temp.mkb('k2', 'f1', 2, '{"state":"waiting-for-transit"}');
  perform pg_temp.mkb('k3', 'f1', 3, '{"pickup_confirmation":"IMSCONF1"}');
  perform pg_temp.mkb('k4', 'f1', 4, jsonb_build_object('status', 'cancelled', 'cancelled_at', now()));
  perform pg_temp.mkb('k5', 'f1', 5, jsonb_build_object('status', 'failed', 'failed_at', now()));
  perform pg_temp.mkb('k7', 'f1', 6);
  perform pg_temp.mkb('c4', 'f1', 8);
  -- 대상(T6)
  perform pg_temp.mkb('d1', 'f1', 11, jsonb_build_object('booked_at', now() - interval '2 hours'));
  perform pg_temp.mkb('d2', 'f1', 12), pg_temp.mkb('d3', 'f1', 13), pg_temp.mkb('d4', 'f1', 14), pg_temp.mkb('d5', 'f1', 15, '{"state":"delivered"}');
  perform pg_temp.mkb('d6', 'f1', 16, '{"freightcom_shipment_id":"  "}');
  perform pg_temp.mkb('d7', 'f1', 17, jsonb_build_object('booked_at', now() - interval '40 days'));
  perform pg_temp.mkb('d8', 'f1', 18, jsonb_build_object('status', 'cancelled', 'cancelled_at', now()));
  -- 픽업(1158): 둘 다 상자 · 비정기 · 번호 없음 · schedule error — 옛 판이면 둘 다 not_scheduled
  perform pg_temp.mkb('p1', 'fp1', 1, jsonb_build_object('state', 'cancelled', 'schedule_status', 'error', 'schedule_error', 'zz no driver', 'schedule_checked_at', now() - interval '30 minutes', 'booked_at', now() - interval '90 minutes'));
  perform pg_temp.mkb('p2', 'fp2', 1, jsonb_build_object('state', 'in-transit', 'schedule_status', 'error', 'schedule_error', 'zz no driver', 'schedule_checked_at', now() - interval '30 minutes', 'booked_at', now() - interval '80 minutes'));
  -- 인정(1159) C2: 실제 출고된 SO-21094 의 칸이 「예약 때 쓴 값 그대로」 인 가짜 예약 — 그 전 값은 추적번호 ZZ-BEFORE
  select * into v_so from public.so s where s.so_number = 'SO-21094';
  perform pg_temp.mkb('c2', 'fc2', 1, jsonb_build_object('state', 'cancelled', 'so_written', jsonb_build_array(jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number,
            'before', jsonb_build_object('carrier', null, 'carrier_id', null, 'tracking_number', 'ZZ-BEFORE'),
            'written', jsonb_build_object('carrier', v_so.carrier, 'carrier_id', v_so.carrier_id, 'tracking_number', v_so.tracking_number)))));
  update public.fc_shipment f set booking_id = pg_temp.id(x.b)::uuid from (values ('f1', 'k1'), ('fp1', 'p1'), ('fp2', 'p2'), ('fc2', 'c2')) x(f, b) where f.id = pg_temp.id(x.f)::uuid;
end $$;
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select clock_timestamp() as t_after_mig \gset
-- ── 새 칸 재료(T6 · try 안 — 마른 실행에서는 ERR 로 남는다) ──
select pg_temp.put('post', pg_temp.try(format($q$ with u as (update public.fc_booking b set
      state_checked_at = case x.k when 'd2' then now() - interval '4 hours' when 'd3' then now() - interval '1 hour' when 'd4' then now() - interval '90 minutes' when 'd5' then now() - interval '5 hours' end,
      track_last = case x.k when 'd4' then '{"type":"in-transit","message":"Out For Delivery Today"}'::jsonb end,
      track_done_at = case x.k when 'd5' then now() end
    from (values ('d2', %L::uuid), ('d3', %L), ('d4', %L), ('d5', %L)) x(k, id) where b.id = x.id returning 1) select count(*)::text from u $q$, pg_temp.id('d2'), pg_temp.id('d3'), pg_temp.id('d4'), pg_temp.id('d5'))));

-- ── T1 · T2: 실물 꼴 저장 · 다시 저장 ──
select pg_temp.put('r1', pg_temp.save('k1', :'fx_ship'::jsonb, :'fx_events'::jsonb));
select pg_temp.put('sca1', pg_temp.bk('k1', 'b.state_checked_at')), pg_temp.put('done1', pg_temp.bk('k1', 'b.track_done_at'));
select pg_temp.chk('T1a 저장 반환 — state delivered · kind · 이벤트 받은 8 · 더한 8 · 건너뜀 0 · 읽음', pg_temp.j(pg_temp.id('r1'), 'state') || ' ' || pg_temp.j(pg_temp.id('r1'), 'state_kind') || ' ' || pg_temp.j(pg_temp.id('r1'), 'state_before') || ' recv=' || pg_temp.j(pg_temp.id('r1'), 'events_received') || ' add=' || pg_temp.j(pg_temp.id('r1'), 'events_added') || ' skip=' || pg_temp.j(pg_temp.id('r1'), 'events_skipped') || ' read=' || pg_temp.j(pg_temp.id('r1'), 'events_read'), 'delivered delivered in-transit recv=8 add=8 skip=0 read=true'),
       pg_temp.chk('T1b 예약 칸 — delivered_at = delivered 이벤트의 when(나노초 → 마이크로초 자름) · 끝 표지 · 읽은 시각 · 확인번호는 비어 있어 채움', pg_temp.bk('k1', $e$ b.state || ' ' || to_char(b.delivered_at at time zone 'utc', 'YYYY-MM-DD HH24:MI:SS.US') || ' done=' || (b.track_done_at is not null) || ' checked=' || (b.state_checked_at is not null) || ' conf=' || b.pickup_confirmation $e$), 'delivered 2026-11-10 21:06:12.123456 done=true checked=true conf=29FBD3C23EA'),
       pg_temp.chk('T1c track_last = 마지막 이벤트(type · city · region · message 는 btrim · at = delivered_at)', pg_temp.bk('k1', $e$ (b.track_last->>'type') || '|' || (b.track_last->>'city') || '|' || (b.track_last->>'region') || '|' || (b.track_last->>'message') || '|' || ((b.track_last->>'at')::timestamptz = b.delivered_at) || '|' || (select count(*) from jsonb_object_keys(b.track_last)) $e$), 'delivered|SAULT STE MARIE|ON|DELIVERED|true|5'),
       pg_temp.chk('T1d 이벤트 8 행 — 빈 where 2 건은 place null · message btrim · raw 는 끝 공백 그대로 · label-created 의 at 은 .465569(자름)', pg_temp.try(format($q$ select count(*) || ' null_place=' || count(*) filter (where t.place is null) || ' types=' || count(distinct t.type) || ' ' || max(t.message) filter (where t.type = 'delivered') || '/' || length(max(t.raw->>'message') filter (where t.type = 'delivered')) || ' ' || to_char(min(t.at) at time zone 'utc', 'HH24:MI:SS.US') || ' pickup=' || max(t.message) filter (where t.type = 'picked-up') || ' country=' || max(t.place->>'country') from public.fc_track_event t where t.booking_id = %L $q$, pg_temp.id('k1'))), '8 null_place=2 types=4 DELIVERED/10 22:45:20.465569 pickup=Pickup Scan country=CA'),
       pg_temp.chk('T1e 추적번호가 달라도 예약 칸 무변 · 경고 tracking_differs(이견 9) · response 무변', pg_temp.bk('k1', $e$ (b.tracking_number = pg_temp.id('src_trk')) || ' ' || (b.response = '{"zz":"orig"}'::jsonb) $e$) || ' ' || (pg_temp.j(pg_temp.id('r1'), 'warnings') like '%tracking_differs%')::text, 'true true true');
select pg_temp.put('r2', pg_temp.save('k1', :'fx_ship'::jsonb, :'fx_events'::jsonb));
select pg_temp.chk('T2 같은 것을 다시 저장 — 이벤트 더한 0 · 합 8 · state_checked_at 만 앞으로 · 끝 표지 · delivered_at 그대로', 'add=' || pg_temp.j(pg_temp.id('r2'), 'events_added') || ' total=' || pg_temp.j(pg_temp.id('r2'), 'events_total') || ' ' || pg_temp.bk('k1', format($e$ (b.state_checked_at > %L::timestamptz) || ' ' || (b.track_done_at = %L::timestamptz) || ' ' || to_char(b.delivered_at at time zone 'utc', 'HH24:MI:SS.US') $e$, pg_temp.id('sca1'), pg_temp.id('done1'))), 'add=0 total=8 true true 21:06:12.123456');

-- ── T3 · T4 · T5 · T7: 모르는 값 · 확인번호 · 거부 · 이벤트를 못 읽은 회차 ──
select pg_temp.put('r3', pg_temp.save('k2', format('{"id":"zzfct-ship-k2","state":" Waiting-For-Scheduling ","bolnumber":"BOLX","primary_tracking_number":%s}', to_jsonb(pg_temp.id('src_trk')))::jsonb,
                                      '[{"type":"Customs-Hold","when":"2026-11-09T10:00:00Z","where":"","message":"  "},{"type":"x","when":"garbage"},{"type":"y"},"just text"]'::jsonb)),
       pg_temp.put('r4', pg_temp.save('k3', '{"shipment":{"id":"zzfct-ship-k3","state":"in-transit","pickup_confirmation_number":"OTHER9","bol_number":"BOL77"}}'::jsonb, '{"events":[]}'::jsonb)),
       pg_temp.put('r7', pg_temp.save('k7', '{"shipment":{"id":"zzfct-ship-k7","state":"delivered"}}'::jsonb, null));
select pg_temp.chk('T3a 모르는 state · type 그대로 저장(lower · trim) · 거부 없음 · kind open · 끝 표지 없음 · 배열 맨몸 받음 · when 못 읽는 셋은 skipped', pg_temp.j(pg_temp.id('r3'), 'state') || ' ' || pg_temp.j(pg_temp.id('r3'), 'state_kind') || ' add=' || pg_temp.j(pg_temp.id('r3'), 'events_added') || ' skip=' || pg_temp.j(pg_temp.id('r3'), 'events_skipped') || ' done=' || pg_temp.bk('k2', 'b.track_done_at is not null') || ' warn=' || (pg_temp.j(pg_temp.id('r3'), 'warnings') like '%events_skipped%')::text, 'waiting-for-scheduling open add=1 skip=3 done=false warn=true'),
       pg_temp.chk('T3b 그 이벤트 — type customs-hold · where 가 글자면 place null · 빈 message 는 null · bolnumber(실물 열쇠)로 BOL 채움 · 추적번호 같으면 경고 없음', pg_temp.try(format($q$ select t.type || ' ' || (t.place is null) || ' ' || (t.message is null) from public.fc_track_event t where t.booking_id = %L $q$, pg_temp.id('k2'))) || ' ' || pg_temp.bk('k2', 'b.bol_number') || ' ' || (pg_temp.j(pg_temp.id('r3'), 'warnings') like '%tracking_differs%')::text, 'customs-hold true true BOLX false'),
       pg_temp.chk('T4 확인번호가 이미 있으면 IMS 값 유지(1041) · mismatch 알림 · bol_number(스펙 열쇠)로도 채움 · 이벤트 0 이면 track_last null', pg_temp.bk('k3', $e$ b.pickup_confirmation || ' ' || b.bol_number || ' ' || (b.track_last is null) || ' ' || b.state $e$) || ' ' || pg_temp.j(pg_temp.id('r4'), 'confirmation_mismatch') || ' ' || pg_temp.j(pg_temp.id('r4'), 'events_read'), 'IMSCONF1 BOL77 true in-transit true true'),
       pg_temp.chk('T5a status cancelled 예약에 저장 → 거부', pg_temp.err(pg_temp.save('k4', '{"id":"zzfct-ship-k4","state":"delivered"}'::jsonb, null), '%is cancelled — tracking is read for booked shipments only%'), 'refused'),
       pg_temp.chk('T5b status failed 예약에 저장 → 거부', pg_temp.err(pg_temp.save('k5', '{"id":"zzfct-ship-k5","state":"delivered"}'::jsonb, null), '%is failed — tracking is read for booked shipments only%'), 'refused'),
       pg_temp.chk('T5c 응답의 id 가 예약과 다르면 거부(이견 9) · 예약 무변', pg_temp.err(pg_temp.save('k3', '{"id":"someone-else","state":"cancelled"}'::jsonb, null), '%The shipment answer is for someone-else%') || ' ' || pg_temp.bk('k3', 'b.state'), 'refused in-transit'),
       pg_temp.chk('T5d p_events 가 목록이 아니면 거부 · 직원(authenticated)은 fc_track_save 를 못 부른다(42501)', pg_temp.err(pg_temp.save('k3', '{"id":"zzfct-ship-k3","state":"in-transit"}'::jsonb, '{"nope":1}'::jsonb), '%p_events must be a JSON list%') || ' ' || pg_temp.err(pg_temp.usr('W', format('select public.fc_track_save(%L, %L::jsonb, null)::text', pg_temp.id('k3'), '{"id":"zzfct-ship-k3"}')), 'ERR 42501%'), 'refused refused'),
       pg_temp.chk('T7 이벤트를 못 읽은 회차(p_events null) — state 는 delivered 로 저장되지만 끝 표지 · delivered_at 은 비운 채(이견 2 — 다음 회차가 다시 읽는다)', pg_temp.bk('k7', $e$ b.state || ' done=' || (b.track_done_at is not null) || ' delivered_at=' || (b.delivered_at is not null) || ' checked=' || (b.state_checked_at is not null) $e$) || ' read=' || pg_temp.j(pg_temp.id('r7'), 'events_read'), 'delivered done=false delivered_at=false checked=true read=false');

-- ── G: 사람 길의 문(이견 4) · 이벤트 표는 닫혀 있다(⬜4) ──
select pg_temp.put('g1', pg_temp.usr('S', format('select public.fc_track_gate(%L)::text', pg_temp.id('k1'))));
select pg_temp.chk('G-a fc_track_gate — sales 직원(창고 전부) 통과 · 계정 · Freightcom id 반환', pg_temp.j(pg_temp.id('g1'), 'freightcom_shipment_id') || ' ' || (pg_temp.j(pg_temp.id('g1'), 'account') = pg_temp.bk('k1', 'b.account'))::text || ' ' || pg_temp.j(pg_temp.id('g1'), 'status'), 'fcShipTrack1 true booked'),
       pg_temp.chk('G-b 권한 없는 직원 거부 · 다른 창고(EDM 만) 거부 · freight_booking + 그 창고 통과', pg_temp.err(pg_temp.usr('N', format('select public.fc_track_gate(%L)::text', pg_temp.id('k1'))), '%You cannot refresh freight tracking%') || ' ' || pg_temp.err(pg_temp.usr('E', format('select public.fc_track_gate(%L)::text', pg_temp.id('k1'))), '%belongs to another warehouse%') || ' ' || pg_temp.j(pg_temp.usr('W', format('select public.fc_track_gate(%L)::text', pg_temp.id('k1'))), 'attempt'), 'refused refused 1'),
       pg_temp.chk('G-c booked 가 아닌 예약 · Freightcom id 가 빈 예약 · 없는 예약은 거부', pg_temp.err(pg_temp.usr('S', format('select public.fc_track_gate(%L)::text', pg_temp.id('k4'))), '%tracking is read for booked shipments only%') || ' ' || pg_temp.err(pg_temp.usr('S', format('select public.fc_track_gate(%L)::text', pg_temp.id('d6'))), '%tracking is read for booked shipments only%') || ' ' || pg_temp.err(pg_temp.usr('S', format('select public.fc_track_gate(%L)::text', gen_random_uuid())), '%not found%'), 'refused refused refused'),
       pg_temp.chk('G-d fc_track_event 는 직원이 표로 못 읽는다(42501) · service_role 은 읽기만', pg_temp.err(pg_temp.usr('S', 'select count(*)::text from public.fc_track_event'), 'ERR 42501%') || ' ' || pg_temp.svc('select (count(*) >= 9)::text from public.fc_track_event') || ' ' || pg_temp.err(pg_temp.svc('delete from public.fc_track_event where booking_id is null'), 'ERR 42501%'), 'refused true refused');

-- ── P: 1158 — Freightcom 에서 취소된 예약은 픽업 필요 없음(판정 · cron 64 대상 · Action Centre 셋을 같이) ──
select pg_temp.put('pc1', pg_temp.try(format('select public.fc_pickup_check(b)::text from public.fc_booking b where b.id = %L', pg_temp.id('p1')))),
       pg_temp.put('al', pg_temp.usr('S', 'select public.fc_pickup_attention_list(null)::text')),
       pg_temp.put('pd', pg_temp.try('select coalesce(string_agg(d.booking_id::text, '',''), '''') from public.fc_pickup_poll_due(50) d'));
select pg_temp.chk('P1a state cancelled 인 booked 예약 — fc_pickup_check needed false · not_scheduled false · pending false · 글', pg_temp.j(pg_temp.id('pc1'), 'needed') || ' ' || pg_temp.j(pg_temp.id('pc1'), 'not_scheduled') || ' ' || pg_temp.j(pg_temp.id('pc1'), 'pending') || ' ' || pg_temp.j(pg_temp.id('pc1'), 'freightcom_cancelled') || ' ' || pg_temp.j(pg_temp.id('pc1'), 'message'), 'false false false true Cancelled on Freightcom — no pickup to check'),
       pg_temp.chk('P1b 그 예약은 fc_pickup_poll_due 에 없다 · 같은 꼴인데 취소가 아닌 p2 는 있다', (position(pg_temp.id('p1') in pg_temp.id('pd')) > 0)::text || ' ' || (position(pg_temp.id('p2') in pg_temp.id('pd')) > 0)::text, 'false true'),
       pg_temp.chk('P1c 그 예약은 fc_pickup_attention_list 에 없다 · p2 는 있다(목록 함수는 바이트 그대로 — 판정을 fc_pickup_check 로만 한다)', case when pg_temp.id('al') like 'ERR %' then pg_temp.id('al') else (position(pg_temp.id('p1') in pg_temp.id('al')) > 0)::text || ' ' || (position(pg_temp.id('p2') in pg_temp.id('al')) > 0)::text end, 'false true'),
       pg_temp.chk('P2a 취소가 아닌 모든 예약(실물 + 가짜) — 새 fc_pickup_check 에서 새 열쇠를 빼면 옛 판과 같다(다른 행 0 · 견준 행 50 넘음)', pg_temp.try($q$ select count(*) filter (where (public.fc_pickup_check(b) - 'freightcom_cancelled') is distinct from pg_temp.pc_old(b)) || ' ' || (count(*) > 50) || ' ' || bool_and((public.fc_pickup_check(b)->>'freightcom_cancelled') = 'false') from public.fc_booking b where not (b.status = 'booked' and lower(btrim(coalesce(b.state, ''))) like 'cancel%') $q$), '0 true true'),
       pg_temp.chk('P2b fc_pickup_poll_due — 옛 판의 대상에서 취소된 예약(가짜 p1 · c2 둘)만 빠진다(순서까지 같다)', pg_temp.try($q$ select (coalesce((select string_agg(o.booking_id::text, ',') from pg_temp.due_old(50) o join public.fc_booking b on b.id = o.booking_id where lower(btrim(coalesce(b.state, ''))) not like 'cancel%'), '') = coalesce((select string_agg(d.booking_id::text, ',') from public.fc_pickup_poll_due(50) d), ''))::text || ' ' || (select count(*) from pg_temp.due_old(50) o join public.fc_booking b on b.id = o.booking_id where lower(btrim(coalesce(b.state, ''))) like 'cancel%') $q$), 'true 2'),
       pg_temp.chk('P2c 속 함수 fc_state_kind — cancelled · canceled · cancel%(짐작) = cancelled · delivered · 그 밖 · null · 빈 글 = open', pg_temp.try($q$ select string_agg(public.fc_state_kind(x), ',' order by n) from (values (1, 'cancelled'), (2, ' Canceled '), (3, 'cancellation-requested'), (4, 'DELIVERED'), (5, 'in-transit'), (6, 'waiting-for-scheduling'), (7, null), (8, ''), (9, 'exception')) v(n, x) $q$), 'cancelled,cancelled,cancelled,delivered,open,open,open,open,open'),
       pg_temp.chk('P2d 속 함수 fc_ts — 나노초 자름 · 마이크로초 · 초 · 못 읽는 글 · null', pg_temp.try($q$ select string_agg(coalesce(to_char(public.fc_ts(x) at time zone 'utc', 'YYYY-MM-DD HH24:MI:SS.US'), 'null'), ',' order by n) from (values (1, '2026-11-05T22:45:20.465569955Z'), (2, '2026-11-05T22:45:20.999999999Z'), (3, '2026-11-05T17:45:20-05:00'), (4, 'garbage'), (5, null), (6, '2026-13-45T99:00:00Z')) v(n, x) $q$), '2026-11-05 22:45:20.465569,2026-11-05 22:45:20.999999,2026-11-05 22:45:20.000000,null,null,null');

-- ── C: 1159 — 「Freightcom 에서 취소됨」 인정 ──
select pg_temp.put('c3a', pg_temp.mark('W', 'k2', 'x')), pg_temp.put('c3b', pg_temp.mark('W', 'k4', 'x')), pg_temp.put('c3c', pg_temp.mark('S', 'p1', 'x')), pg_temp.put('c3d', pg_temp.mark('E', 'p1', 'x')), pg_temp.put('c3e', pg_temp.mark('W', 'p1', repeat('n', 501)));
select pg_temp.chk('C3 거부 넷 + 글 길이 — state 가 취소 아님 · status booked 아님 · 권한 없음(sales 만) · 다른 창고 · 글 501 자 · 그 뒤 p1 은 그대로 booked', pg_temp.err(pg_temp.id('c3a'), '%Freightcom does not show this shipment as cancelled (it says waiting-for-scheduling)%') || ' ' || pg_temp.err(pg_temp.id('c3b'), '%is cancelled — there is nothing to mark as cancelled%') || ' ' || pg_temp.err(pg_temp.id('c3c'), '%You cannot book or cancel freight%') || ' ' || pg_temp.err(pg_temp.id('c3d'), '%belongs to another warehouse%') || ' ' || pg_temp.err(pg_temp.id('c3e'), '%the limit is 500%') || ' ' || pg_temp.bk('p1', $e$ b.status || ' ' || coalesce(b.cancel_source, '-') $e$), 'refused refused refused refused refused booked -');
select pg_temp.put('c1', pg_temp.mark('W', 'real', E'  gone at Freightcom \n rebooked   by hand '));
select pg_temp.chk('C1a 실물 1474f64f(rollback 안) — status cancelled · 출고된 SO 둘 다 orders_kept · 되돌린 것 0 · 글은 한 줄로 · 발송 selected', pg_temp.j(pg_temp.id('c1'), 'status') || ' kept=' || pg_temp.j(pg_temp.id('c1'), 'orders_kept') || ' restored=' || pg_temp.j(pg_temp.id('c1'), 'orders_restored') || ' note=' || pg_temp.j(pg_temp.id('c1'), 'cancel_note') || ' f=' || pg_temp.j(pg_temp.id('c1'), 'shipment_status'), 'cancelled kept=["SO-21022", "SO-21094"] restored=[] note=gone at Freightcom rebooked by hand f=selected'),
       pg_temp.chk('C1b SO-21022 · SO-21094 의 칸 무변(이미 다른 추적번호)', (pg_temp.so_cols('SO-21022') = pg_temp.id('pre_so22'))::text || ' ' || (pg_temp.so_cols('SO-21094') = pg_temp.id('pre_so94'))::text || ' ' || split_part(pg_temp.id('pre_so94'), '|', 4), 'true true fulfilled'),
       pg_temp.chk('C1c 예약 행 — cancel_source freightcom · cancelled_by = 누른 직원 · cancelled_at · state 원문 그대로 · response 는 덮지 않음(475)', pg_temp.bk('real', $e$ b.status || ' ' || b.cancel_source || ' ' || (b.cancelled_by::text = pg_temp.id('W')) || ' ' || (b.cancelled_at is not null) || ' ' || (b.status || '|' || b.state || '|' || md5(coalesce(b.response::text, '')) = replace(pg_temp.id('pre_real_b'), 'booked|', 'cancelled|')) $e$), 'cancelled freightcom true true true');
select pg_temp.put('c2r', pg_temp.mark('W', 'c2', null));
select pg_temp.chk('C2 가짜 예약(SO 칸이 예약 때 값 그대로) — 출고된 SO-21094 의 칸을 그 전 값으로 되돌림(856) · 발송 selected · 글 없음 = null', 'restored=' || pg_temp.j(pg_temp.id('c2r'), 'orders_restored') || ' kept=' || pg_temp.j(pg_temp.id('c2r'), 'orders_kept') || ' so=' || pg_temp.so_cols('SO-21094') || ' f=' || pg_temp.try(format('select f.status from public.fc_shipment f where f.id = %L', pg_temp.id('fc2'))) || ' note=' || pg_temp.bk('c2', $e$ coalesce(b.cancel_note, 'null') || ' ' || b.cancel_source $e$), 'restored=["SO-21094"] kept=[] so=-|-|ZZ-BEFORE|fulfilled f=selected note=null freightcom'),
       pg_temp.chk('C2b 이미 인정한 예약을 다시 누르면 거부 · 인정 뒤에는 저장(fc_track_save)도 거부', pg_temp.err(pg_temp.mark('W', 'c2', null), '%is cancelled — there is nothing to mark as cancelled%') || ' ' || pg_temp.err(pg_temp.save('c2', '{"id":"zzfct-ship-c2","state":"cancelled"}'::jsonb, null), '%tracking is read for booked shipments only%'), 'refused refused'),
       pg_temp.chk('C4 IMS 취소(fc_book_cancel_save · service_role) — cancel_source ims · 나머지는 종전(status cancelled · 발송 selected)', pg_temp.j(pg_temp.svc(format('select public.fc_book_cancel_save(%L, %L::jsonb, null)::text', pg_temp.id('c4'), '{"cancelled_by":null,"http_status":200,"body":null}')), 'shipment_status') || ' ' || pg_temp.bk('c4', $e$ b.status || ' ' || b.cancel_source || ' ' || (b.cancel_note is null) $e$), 'selected cancelled ims true');

-- ── S · R · G: 구조 · 정적 검사 · md5 ──
select pg_temp.chk('S1 칸 여섯 · CHECK 둘 · 이벤트 표 유니크 · RLS 켬 · 정책 0', pg_temp.try($q$ select (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'fc_booking' and c.column_name in ('state_checked_at', 'delivered_at', 'track_last', 'track_done_at', 'cancel_source', 'cancel_note')) || ' ' || (select count(*) from pg_constraint c where c.conrelid = 'public.fc_booking'::regclass and c.conname in ('fc_booking_cancel_source_ck', 'fc_booking_cancel_note_ck')) || ' ' || (select count(*) from pg_indexes i where i.schemaname = 'public' and i.indexname = 'fc_track_event_uq' and i.indexdef like '%UNIQUE%md5%') || ' ' || (select c.relrowsecurity from pg_class c where c.oid = 'public.fc_track_event'::regclass) || ' ' || (select count(*) from pg_policy p where p.polrelid = 'public.fc_track_event'::regclass) $q$), '6 2 1 true 0'),
       pg_temp.chk('S2 권한 — 저장 · 대상은 service_role 만 · 문 · 인정은 authenticated(anon 아님) · 속 함수 둘은 아무에게도 · 표는 authenticated 0', pg_temp.try($q$ select concat_ws(' ', has_function_privilege('service_role', 'public.fc_track_save(uuid,jsonb,jsonb)', 'execute'), has_function_privilege('authenticated', 'public.fc_track_save(uuid,jsonb,jsonb)', 'execute'), has_function_privilege('service_role', 'public.fc_track_due(int)', 'execute'), has_function_privilege('authenticated', 'public.fc_track_due(int)', 'execute'),
              has_function_privilege('authenticated', 'public.fc_track_gate(uuid)', 'execute'), has_function_privilege('anon', 'public.fc_track_gate(uuid)', 'execute'), has_function_privilege('authenticated', 'public.fc_book_mark_cancelled(uuid,text)', 'execute'), has_function_privilege('anon', 'public.fc_book_mark_cancelled(uuid,text)', 'execute'),
              has_function_privilege('authenticated', 'public.fc_state_kind(text)', 'execute'), has_function_privilege('service_role', 'public.fc_ts(text)', 'execute'), has_table_privilege('authenticated', 'public.fc_track_event', 'select'), has_table_privilege('service_role', 'public.fc_track_event', 'insert')) $q$), 't f t f t f t f f f f f'),
       pg_temp.chk('S3 스위치 — fc_track_poll_enabled 는 off 로 시작하거나 Caleb 이 켠 on · batch 는 1 ~ 50 의 수', pg_temp.try($q$ select ((select c.value from public.inv_config c where c.key = 'fc_track_poll_enabled') in ('off', 'on'))::text || ' ' || ((select c.value from public.inv_config c where c.key = 'fc_track_poll_batch') ~ '^[0-9]{1,2}$')::text $q$), 'true true'),
       pg_temp.chk('R1 REST 겹 ① — 새 · 재발행 함수 여섯의 깊이 0 WHERE 없는 update · delete = 0', pg_temp.try($q$ select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc)::text, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fc_track_save', 'fc_track_due', 'fc_track_gate', 'fc_book_mark_cancelled', 'fc_book_cancel_save', 'fc_pickup_check', 'fc_pickup_poll_due') $q$), 'fc_book_cancel_save=0,fc_book_mark_cancelled=0,fc_pickup_check=0,fc_pickup_poll_due=0,fc_track_due=0,fc_track_gate=0,fc_track_save=0'),
       pg_temp.chk('G1 재발행 셋의 새 md5 · 그 밖 fc_ 함수는 begin 앞(또는 알려진 옛 값)과 같다 · 새 함수는 여섯뿐', pg_temp.try($q$ select (select string_agg(p.proname || ' ' || md5(p.prosrc), ' · ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fc_book_cancel_save', 'fc_pickup_check', 'fc_pickup_poll_due')) || ' | ' ||
              (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5 where t.proname not in ('fc_book_cancel_save', 'fc_pickup_check', 'fc_pickup_poll_due')) || ' | ' ||
              (select string_agg(p.proname || ' ' || md5(p.prosrc), ' · ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fc_book_schedule_save', 'fc_pickup_attention_list', 'fc_booking_for_shipment')) || ' | ' ||
              (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fc_state_kind', 'fc_ts', 'fc_track_due', 'fc_track_save', 'fc_track_gate', 'fc_book_mark_cancelled')) $q$),
         'fc_book_cancel_save 018c0ee62e0db52a50e237b1035ca40e · fc_pickup_check 82af22fb3857b7aec01e47a589d06ea3 · fc_pickup_poll_due 88b9b6821730fba5d6a9756858434448 | (none) | fc_book_schedule_save d26d7d7cd17bd681c3d5dca7bf9220e4 · fc_booking_for_shipment 7413429f0b0e31d04a6e926042d6e6cf · fc_pickup_attention_list b9177f02f0ae15e4d783e5208919f333 | 6'),
       pg_temp.chk('S4 fc_booking_for_shipment.current 에 새 칸이 그대로 실린다(재발행 없이 · 화면의 「배송 상태 한 줄」) · pickup_check 에 freightcom_cancelled', pg_temp.usr('S', format($q$ select (x->'current' ? 'track_last') || ' ' || (x->'current' ? 'state_checked_at') || ' ' || (x->'current' ? 'delivered_at') || ' ' || (x->'current' ? 'cancel_source') || ' ' || (x->'current'->'track_last'->>'message') || ' ' || (x->'current'->'pickup_check' ? 'freightcom_cancelled') from (select public.fc_booking_for_shipment(%L) as x) q $q$, pg_temp.id('f1'))), 'true true true true DELIVERED true');

-- ── T6: fc_track_due(파일 끝 — 실제 booked 예약의 track_done_at 을 채워 목록에서 뺀다 · 잠금 구간을 짧게) ──
select pg_temp.put('t6u', pg_temp.try($q$ with u as (update public.fc_booking b set track_done_at = now() where b.status = 'booked' and b.unique_id not like 'zzfct-%' returning 1) select (count(*) > 40)::text from u $q$));
select pg_temp.chk('T6a 대상 · 순서 · 단 — 읽은 적 없음 먼저(booked_at 순 · Freightcom 취소도 한 번은 읽는다) → 4 시간 전 → out for delivery 90 분 전 · 빠짐: 끝 표지 · 1 시간 전 · 방금 읽음 · IMS 취소 · failed · Freightcom id 빈 것 · 40 일 전', pg_temp.id('t6u') || ' ' || pg_temp.try($q$ select string_agg(pg_temp.keyof(d.booking_id::text) || ':' || d.tier, ',') from public.fc_track_due(50) d $q$), 'true d1:first,p1:first,p2:first,d2:regular,d4:out_for_delivery'),
       pg_temp.chk('T6b batch 지킴 — limit 2 는 앞의 둘 · 0 · 51 은 기본 10(여기서는 다섯 전부) · 직원은 못 부른다', pg_temp.try($q$ select (select string_agg(pg_temp.keyof(d.booking_id::text), ',') from public.fc_track_due(2) d) || ' ' || (select count(*) from public.fc_track_due(0)) || ' ' || (select count(*) from public.fc_track_due(51)) $q$) || ' ' || pg_temp.err(pg_temp.usr('W', 'select count(*)::text from public.fc_track_due(5)'), 'ERR 42501%'), 'd1,p1 5 5 refused');

-- ── Z(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(가짜 행 · 실물에 한 것 모두 rollback) ──'
select n, case when ok then 'OK  ' else 'FAIL' end as r, label, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' · want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, (count(*) filter (where not ok) > 0 or count(*) filter (where ok) <> :EXPECT_OK) as bad from t_res \gset
\echo 'OK' :ok '· FAIL' :fail '· total' :total '· expect_ok' :EXPECT_OK
select pg_temp.id('post') as new_column_fixture_rows, round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — t 여야 한다'
select (select count(*) from public.fc_booking) = :n_bk0 and (select count(*) from public.fc_shipment) = :n_f0 and (select count(*) from public.ims_staff) = :n_staff0
   and (select max(version) from supabase_migrations.schema_migrations) = :'ver0' and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'fc\_%') = :n_fn0
   and pg_temp.so_cols('SO-21022') = :'so22_0' and pg_temp.so_cols('SO-21094') = :'so94_0'
   and (select b.status || '|' || coalesce(b.state, '-') || '|' || md5(coalesce(b.response::text, '')) from public.fc_booking b where b.id = :'REAL_B') = :'real_b0' as rolled_back_clean;
\if :bad
do $$ begin raise exception 'fc_track_2_check: FAIL or OK count differs from EXPECT_OK — see the result table above'; end $$;
\endif
