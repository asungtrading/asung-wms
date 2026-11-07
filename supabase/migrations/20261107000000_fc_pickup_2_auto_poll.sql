do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;
-- fc-pickup-2 — 확인번호 없는 Freightcom 예약을 5 분마다 자동으로 다시 읽기 (2026-11-05 · 지시서 ~/asung/prompts/fc-pickup-2.md · 판정 1041(짐작) · Claude Code 이견 1 ~ 14 모두 승인)
--   왜: 첫 실물 10 건(11-05 23:08 UTC) 전부 GET /shipment/{id}/schedule → done · 확인번호 있음 — Freightcom 은 예약 뒤 픽업을 따로 · 늦게 잡는다(H1) · IMS 가 다시 안 읽었을 뿐 · 몸 고치기는 필요 없다.
--       이 차수 = IMS 가 스스로 다시 읽는다(cron ims-fc-pickup-poll */5 → EF freightcom pickup_sweep · GET 만 · 청구 없음) · 「Check pickup」 단추(pickup_poll)는 그대로
--   ① inv_config 스위치 fc_pickup_poll_enabled(기본 off · 켜는 것은 Caleb) · fc_pickup_poll_batch(회차 최대 건수 · 기본 10 · 이견 1 · 5) — qbo_send_payments_enabled · qbo_send_batch 꼴
--   ② fc_booking.schedule_done_at — 「status done 을 처음 본 시각」(번호 유무 무관 · 한 번만 · 덮지 않음 · 기존 10 건 백필 없음 = null 은 모름 · 이견 8) · 걸린 시간 = schedule_done_at - booked_at
--   ③ fc_call_log.detail jsonb — 회차 요약 한 줄(action pickup_sweep · shipment_id null · by_staff null · 이견 6) · 다른 줄은 null
--   ④ fc_pickup_poll_due(p_limit) — 「대상」 정의 한 곳(cron where 와 EF 가 같이 쓴다 · service_role 만 · 읽기 · 이견 2):
--      needed = booked ∧ 상자(dispatch_details 없음) ∧ request.pickup_details.pre_scheduled_pickup = 'false' ∧ 확인번호 null ∧ Freightcom id 있음
--      창(이견 3) = now() < greatest(booked_at + 48 h, 픽업 날(request.pickup_details.date · 토론토) + 2 일 00:00 토론토) — 날짜가 없거나 깨졌으면 48 h 만
--      2 단(이견 4) = 예약 뒤 2 시간 안은 회차마다(fast) · 그 뒤는 마지막 성공 읽기(schedule_checked_at)에서 30 분 지났을 때만(slow · 읽은 적 없으면 바로)
--      순서 booked_at 오름 · p_limit(1 ~ 50 · 밖이면 10)
--   ⑤ fc_book_schedule_save 재발행(원본 20261105183506 · DB md5 78db2844cc49efa6b6b94f33f41d27f0) — update 에 schedule_done_at = done 이면 coalesce(기존, clock_timestamp()) 한 줄 · 반환에 schedule_done_at · 그 밖 바이트 그대로 · 시그니처 같음(grant · comment 유지)
--   새 FK 없음 · 화면 무접촉 · fc_pickup_check · fc_booking_for_shipment 무접촉(to_jsonb(b) 라 current 에 schedule_done_at 이 저절로 실린다) · cron 등록은 supabase/ops/cron.sql(Caleb) · 첫 문장 = guard-test-only.sql 바이트 복사
--   적용(Caleb · 17:00 뒤): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261107000000_fc_pickup_2_auto_poll.sql && supabase migration repair --status applied 20261107000000 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback · 레포 루트 · 17:00 뒤): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261107000000_fc_pickup_2_auto_poll.sql -f supabase/tests/fc_pickup_2_check.sql

-- ═══ 1) 스위치 · 회차 크기 ═══
insert into public.inv_config (key, value, note) values
  ('fc_pickup_poll_enabled', 'off', 'fc-pickup-2: 확인번호 없는 Freightcom 예약을 5 분마다 자동으로 다시 읽는 cron ims-fc-pickup-poll(EF freightcom pickup_sweep · GET 만 · 청구 없음)의 스위치 on | off — 켜는 것은 Caleb · off 면 cron SQL 의 where 가 호출 0 · EF 도 다시 본다'),
  ('fc_pickup_poll_batch', '10', 'fc-pickup-2: 자동 다시 읽기 한 회차 최대 건수(1 ~ 50 · 한 건 GET 3 ~ 7 s · cron timeout 120 s 안) — cron 몸이 읽어 EF 에 limit 으로 넘긴다')
on conflict (key) do nothing;

-- ═══ 2) 칸 둘 ═══
alter table public.fc_booking add column schedule_done_at timestamptz;
comment on column public.fc_booking.schedule_done_at is 'fc-pickup-2: GET /shipment/{id}/schedule 의 status done 을 처음 본 시각(번호 유무 무관 · 한 번만 · 덮지 않음 · clock_timestamp) · 걸린 시간 = schedule_done_at - booked_at · null = 아직 done 을 못 봤거나(2026-11-05 전 10 건) 모름 — 백필 없음';
alter table public.fc_call_log add column detail jsonb;
comment on column public.fc_call_log.detail is 'fc-pickup-2: 회차 요약(action pickup_sweep · shipment_id null · by_staff null) — {enabled, limit, candidates, read, done, pending, failed, other, skipped, ms} · Freightcom 호출 한 줄에는 null';

-- ═══ 3) 대상 — 한 곳 ═══
create function public.fc_pickup_poll_due(p_limit int default 10)
  returns table (booking_id uuid, shipment_id uuid, attempt int, account text, freightcom_shipment_id text, booked_at timestamptz, minutes_since_booked int, tier text, pickup_date date, window_until timestamptz, schedule_status text, schedule_checked_at timestamptz)
  language sql stable security definer
  set search_path = public, pg_temp
as $$
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
  select w.id, w.shipment_id, w.attempt, w.account, w.freightcom_shipment_id, w.booked_at, floor(extract(epoch from (now() - w.booked_at)) / 60)::int, w.tier, w.pickup_date, w.window_until, w.schedule_status, w.schedule_checked_at
    from w
   where now() < w.window_until
     and (w.tier = 'fast' or w.schedule_checked_at is null or w.schedule_checked_at < now() - interval '30 minutes')
   order by w.booked_at, w.attempt
   limit (case when p_limit between 1 and 50 then p_limit else 10 end);
$$;
revoke all on function public.fc_pickup_poll_due(int) from public, anon, authenticated;
grant execute on function public.fc_pickup_poll_due(int) to service_role;
comment on function public.fc_pickup_poll_due(int) is 'fc-pickup-2 ④: 자동 다시 읽기 대상(한 곳 · cron ims-fc-pickup-poll 의 where 와 EF freightcom pickup_sweep 가 같이 쓴다 · service_role 만 · 읽기) — booked · 상자 · 비정기(pre_scheduled_pickup false) · 확인번호 null · Freightcom id 있음 · 창 = greatest(booked_at + 48 h, 픽업 날 + 2 일 00:00 토론토) · 2 단(예약 2 시간 안 fast = 회차마다 · 그 뒤 slow = 마지막 성공 읽기에서 30 분) · booked_at 오름 · limit 1 ~ 50(밖이면 10)';

-- ═══ 4) fc_book_schedule_save 재발행(원본 20261105183506 · update 한 줄 + 반환 한 열쇠 · 그 밖 바이트 그대로) ═══
create or replace function public.fc_book_schedule_save(p_booking_id uuid, p_schedule jsonb, p_shipment jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_b     public.fc_booking%rowtype;
  v_p     jsonb;
  v_sh    jsonb;
  v_conf  text;
  v_src   text;
  v_state text;
  v_warn  text[] := '{}';
  v_mis   boolean := false;
begin
  if not public.doc_is_service() then raise exception 'fc_book_schedule_save is for the freight service only — nothing was saved'; end if;
  if p_schedule is null or jsonb_typeof(p_schedule) <> 'object' then raise exception 'p_schedule must be a JSON object — nothing was saved'; end if;
  select * into v_b from public.fc_booking b where b.id = p_booking_id for update;
  if not found then raise exception 'Booking % not found — nothing was saved', p_booking_id; end if;
  if v_b.status <> 'booked' then raise exception 'Booking #% is % — the pickup schedule is read for booked shipments only — nothing was saved', v_b.attempt, v_b.status; end if;
  v_p := public.fc_schedule_parse(p_schedule);
  v_conf := v_p->>'confirmation'; v_src := case when v_conf is not null then 'schedule' end;
  v_state := v_b.state;
  if p_shipment is not null then
    if jsonb_typeof(p_shipment) <> 'object' then raise exception 'p_shipment must be a JSON object — nothing was saved'; end if;
    v_sh := coalesce(nullif(p_shipment->'shipment', 'null'::jsonb), p_shipment);
    if nullif(btrim(v_sh->>'id'), '') is distinct from v_b.freightcom_shipment_id then raise exception 'The shipment answer is for % — this booking is % — nothing was saved', coalesce(nullif(btrim(v_sh->>'id'), ''), '(no id)'), v_b.freightcom_shipment_id; end if;
    v_state := coalesce(nullif(btrim(v_sh->>'state'), ''), v_b.state);
    if v_conf is null and nullif(btrim(v_sh->>'pickup_confirmation_number'), '') is not null then v_conf := btrim(v_sh->>'pickup_confirmation_number'); v_src := 'shipment'; end if;
  end if;
  if v_b.pickup_confirmation is not null then
    if v_conf is not null and v_conf <> v_b.pickup_confirmation then
      v_mis := true;
      v_warn := array_append(v_warn, format('confirmation_mismatch — IMS has %s · Freightcom now says %s (%s) · kept the IMS value', v_b.pickup_confirmation, v_conf, v_src));
    end if;
    v_conf := v_b.pickup_confirmation; v_src := 'kept';
  end if;
  update public.fc_booking
     set schedule_status = v_p->>'status', schedule_error = v_p->>'error', schedule_checked_at = clock_timestamp(), schedule_response = p_schedule,
         schedule_done_at = case when (v_p->>'status') = 'done' then coalesce(schedule_done_at, clock_timestamp()) else schedule_done_at end,
         pickup_confirmation = v_conf, state = v_state
   where id = v_b.id;
  select * into v_b from public.fc_booking b where b.id = v_b.id;
  return jsonb_build_object('booking_id', v_b.id, 'attempt', v_b.attempt, 'status', v_b.status, 'schedule_status', v_b.schedule_status, 'schedule_error', v_b.schedule_error, 'schedule_checked_at', v_b.schedule_checked_at, 'schedule_done_at', v_b.schedule_done_at,
                            'pickup_confirmation', v_b.pickup_confirmation, 'confirmation_source', v_src, 'confirmation_mismatch', v_mis, 'state', v_b.state, 'shipment_read', p_shipment is not null,
                            'received_keys', v_p->'keys', 'wrapped', v_p->'wrapped', 'warnings', to_jsonb(v_warn), 'pickup_check', public.fc_pickup_check(v_b));
end;
$$;
comment on function public.fc_book_schedule_save(uuid, jsonb, jsonb) is 'fc-pickup-1 ③ · fc-pickup-2 ⑤: GET /shipment/{id}/schedule 결과 저장(EF service_role 만 · booked 만) — schedule_status · error · checked_at · 원문 · schedule_done_at(done 을 처음 본 시각 · 한 번만) · 확인번호는 비었을 때만(schedule → shipment 순) · 있으면 덮지 않음(다르면 warnings) · p_shipment(GET /shipment/{id} 원문 · 선택)가 오면 id 일치 검사 뒤 state 를 새로 · 반환에 received_keys(첫 실호출 꼴 확인) · pickup_check';

-- ═══ 5) 착지 검사 ═══
do $$
declare v_n int; v_acl text; v_md5 text;
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'fc_booking' and column_name = 'schedule_done_at') <> 1 then raise exception 'fc-pickup-2 landing check failed: fc_booking.schedule_done_at'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'fc_call_log' and column_name = 'detail' and data_type = 'jsonb') <> 1 then raise exception 'fc-pickup-2 landing check failed: fc_call_log.detail'; end if;
  select count(*) into v_n from public.inv_config where key in ('fc_pickup_poll_enabled', 'fc_pickup_poll_batch');
  if v_n <> 2 then raise exception 'fc-pickup-2 landing check failed: inv_config rows %', v_n; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_book_schedule_save') <> 1 then raise exception 'fc-pickup-2 landing check failed: fc_book_schedule_save count'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_pickup_poll_due') <> 1 then raise exception 'fc-pickup-2 landing check failed: fc_pickup_poll_due count'; end if;
  foreach v_md5 in array array['fc_book_schedule_save', 'fc_pickup_poll_due'] loop
    select coalesce(p.proacl::text, '(null)') into v_acl from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = v_md5;
    if v_acl <> '{postgres=X/postgres,service_role=X/postgres}' then raise exception 'fc-pickup-2 landing check failed: % acl %', v_md5, v_acl; end if;
  end loop;
  select md5(p.prosrc) into v_md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fc_pickup_check';
  if v_md5 <> 'b3a17787b3585d37712930e9315bc300' then raise exception 'fc-pickup-2 landing check failed: fc_pickup_check touched %', v_md5; end if;
  select md5(p.prosrc) into v_md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fc_booking_for_shipment';
  if v_md5 <> '7413429f0b0e31d04a6e926042d6e6cf' then raise exception 'fc-pickup-2 landing check failed: fc_booking_for_shipment touched %', v_md5; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fc_book_schedule_save' and p.prosrc like '%schedule_done_at = case when%') <> 1 then raise exception 'fc-pickup-2 landing check failed: schedule_save body'; end if;
end $$;
