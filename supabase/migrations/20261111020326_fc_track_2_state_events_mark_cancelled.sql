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
-- fc-track-2 — Freightcom 쉽먼트 상태 자동 읽기 · 추적 이벤트 · 「Freightcom 에서 취소됨」 인정 (2026-11-10 밤 토론토 · 지시서 ~/asung/prompts/fc-track-2.md · 판정 1158 · 1159 · 1160 · Claude Code 이견 1 ~ 9 · ⬜1 ~ ⬜6 모두 Caleb 승인 11-10)
--   왜: fc_booking.state 는 예약 순간 값 그대로다(booked 53 중 40 · cron 64 는 schedule 만 읽는다) ⇒ 픽업됐는지 · 가는 중인지 · 배송됐는지 · Freightcom 에서 취소됐는지 IMS 가 모른다
--   ① 칸(fc_booking · 여섯): state_checked_at(마지막 성공 읽기) · delivered_at · track_last(마지막 이벤트 한 줄) · track_done_at(끝 상태 + 이벤트를 함께 저장한 시각 · 이견 2) · cancel_source(ims | freightcom · 이견 1) · cancel_note(500 자)
--   ② 표 fc_track_event(상태 · 이벤트뿐 — 주소 · 돈 없음) · at not null · 유니크(booking_id, at, type, md5(message)) · message = btrim 값 · 원문은 raw(이견 3) · ⬜4: 처음부터 닫음(RLS 켬 · 정책 0 · authenticated 권한 0)
--      ⚠️ 지시서의 칸 이름 where 는 SQL 예약어라 place 로 적는다({city, region, country} · 셋 다 비면 null)
--   ③ 속 함수 fc_state_kind(state) → cancelled | delivered | open(이견 8 · 한 곳) — 실물로 본 값은 cancelled · delivered 뿐 · canceled · cancel% 를 취소로 받는 것은 **짐작** · 모르는 값은 open(계속 읽는다)
--      속 함수 fc_ts(text) → timestamptz(나노초 9 자리 → 마이크로초로 자름 · 못 읽으면 null · 파서는 DB 한 곳 — fc_schedule_parse 선례)
--   ④ fc_track_due(p_limit) — service_role · 대상 한 곳(cron ims-fc-track-poll 의 where + EF track_sweep): booked ∧ Freightcom id ∧ track_done_at null ∧ 예약 뒤 30 일 안 ∧ (읽은 적 없음 ∨ 마지막 성공 읽기에서 3 시간 · track_last.message 가 out for delivery 로 시작하면 1 시간) · 정렬 state_checked_at nulls first → booked_at(⬜2)
--   ⑤ fc_track_save(p_booking_id, p_shipment, p_events) — service_role · booked 만 · 응답 id ≠ 예약의 Freightcom id 면 거부 · state(lower 원문 · CHECK 없음) · state_checked_at · 이벤트 넣기(중복 무시 · when 못 읽으면 skipped) · track_last · delivered_at(이벤트를 읽은 회차에만 — delivered 이벤트의 when · 없으면 그때 시각) ·
--      track_done_at(끝 상태 ∧ 이벤트 읽음) · pickup_confirmation · bol_number 는 비었을 때만(1041) · 추적번호 · SO 칸 무변(다르면 경고만 · 이견 9) · p_events null = 이벤트를 못 읽은 회차(state 만 저장 · 끝 표지 없음 → 다음 회차가 다시)
--   ⑥ fc_track_gate(p_booking_id) — 사람 길 track_poll 의 문(이견 4 · 사용자 JWT): sales ∨ fulfillment ∨ freight_booking(쓰기 — EF gate 의 label 묶음과 같다) + ims_can_warehouse · booked 만 · {account, freightcom_shipment_id …}
--   ⑦ 1158: fc_pickup_check(needed 에 「Freightcom 취소 아님」 · 글 Cancelled on Freightcom · 새 열쇠 freightcom_cancelled) · fc_pickup_poll_due(where 한 줄) 재발행 — fc_pickup_attention_list 는 판정을 fc_pickup_check.not_scheduled 로만 하므로 **바이트 그대로**(시험 P1 이 증명 · 착지 md5)
--   ⑧ 1159: fc_book_mark_cancelled(p_booking_id, p_note) — 문 fc_book_gate(freight_booking + 그 창고) · booked ∧ fc_state_kind = cancelled · Freightcom 호출 없음 · SO 칸 856 되돌림(예약 때 쓴 값과 아직 같을 때만) · 발송 booked → selected · cancel_source freightcom · response 는 덮지 않는다(475 를 되풀이하지 않는다)
--      fc_book_cancel_save 재발행 — 바뀐 것은 update 한 줄의 「cancel_source = 'ims'」 뿐(이견 1 의 ims 값을 쓰는 곳 · response 덮기(475)는 그대로 · 옛 2 건은 null)
--   ⑨ 스위치 inv_config fc_track_poll_enabled(off · Caleb 이 켠다) · fc_track_poll_batch(10)
--   무접촉(착지 md5): fc_book_schedule_save · fc_pickup_attention_list · fc_booking_for_shipment(current = to_jsonb(b) 라 새 칸이 그대로 실린다) · fc_book_cancel_prepare · fc_book_gate · fc_book_save · 첫 문장 = guard-test-only.sql 바이트 복사
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261111020326_fc_track_2_state_events_mark_cancelled.sql && supabase migration repair --status applied 20261111020326 --db-url "$(cat ~/.asung-testdb-url)" --yes
--   시험(Claude Code · rollback · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111020326_fc_track_2_state_events_mark_cancelled.sql -f supabase/tests/fc_track_2_check.sql

-- ═══ 1) 스위치 · 회차 크기 ═══
insert into public.inv_config (key, value, note) values
  ('fc_track_poll_enabled', 'off', 'fc-track-2: 살아 있는 Freightcom 예약의 상태 · 추적 이벤트를 자동으로 다시 읽는 cron ims-fc-track-poll(EF freightcom track_sweep · GET 만 · 청구 없음)의 스위치 on | off — 켜는 것은 Caleb · off 면 cron SQL 의 where 가 호출 0 · EF 도 다시 본다'),
  ('fc_track_poll_batch', '10', 'fc-track-2: 상태 다시 읽기 한 회차 최대 건수(1 ~ 50 · 한 건 GET 둘 · 회차 90 s 상한 · cron timeout 120 s) — cron 몸이 읽어 EF 에 limit 으로 넘긴다')
on conflict (key) do nothing;

-- ═══ 2) 칸 여섯 ═══
alter table public.fc_booking
  add column state_checked_at timestamptz,
  add column delivered_at     timestamptz,
  add column track_last       jsonb,
  add column track_done_at    timestamptz,
  add column cancel_source    text,
  add column cancel_note      text,
  add constraint fc_booking_cancel_source_ck check (cancel_source is null or cancel_source in ('ims', 'freightcom')),
  add constraint fc_booking_cancel_note_ck   check (cancel_note is null or char_length(cancel_note) <= 500);
comment on column public.fc_booking.state_checked_at is 'fc-track-2: GET /shipment/{id} 를 마지막으로 성공해 읽은 시각(fc_track_save 만 쓴다 · GET 실패는 DB 무변 · fc_book_schedule_save 의 state 쓰기는 이 칸을 건드리지 않는다)';
comment on column public.fc_booking.delivered_at     is 'fc-track-2: 배송 완료 시각 — delivered 이벤트의 when(가장 이른 것) · 이벤트가 없으면 state 가 delivered 인 것을 이벤트와 함께 처음 저장한 시각 · 이벤트를 못 읽은 회차에는 쓰지 않는다';
comment on column public.fc_booking.track_last       is 'fc-track-2: 마지막 추적 이벤트 한 줄 {type, at, city, region, message} — 목록이 한 줄로 읽게(fc_track_event 의 at 가장 늦은 행) · 이벤트를 읽은 회차에만 고친다';
comment on column public.fc_booking.track_done_at    is 'fc-track-2 이견 2: 끝 상태(fc_state_kind delivered | cancelled)와 이벤트를 함께 저장한 시각(처음 한 번) — 자동 다시 읽기(fc_track_due)는 이 칸이 null 인 예약만 읽는다 · state 만으로 멈추지 않는다(사람의 Check pickup 이 state 를 먼저 쓸 수 있다)';
comment on column public.fc_booking.cancel_source    is 'fc-track-2 이견 1: 누가 취소했나 — ims(IMS 가 DELETE /shipment 로 · fc_book_cancel_save) | freightcom(Freightcom 에서 이미 취소된 것을 IMS 가 인정 · fc_book_mark_cancelled · 1159) · 2026-11-10 이전 취소 2 건은 null';
comment on column public.fc_booking.cancel_note      is 'fc-track-2 이견 1: 인정할 때 직원이 적은 글(500 자 · 한 줄 · fc_book_mark_cancelled 만 쓴다)';

-- ═══ 3) 이벤트 표 — 상태 · 이벤트뿐(주소 · 돈 없음) · 처음부터 닫음(⬜4 · 화면은 창구로만 — fc-track-4) ═══
create table public.fc_track_event (
  id         bigint generated always as identity primary key,
  booking_id uuid        not null references public.fc_booking (id),
  type       text        not null,
  at         timestamptz not null,
  place      jsonb,
  message    text,
  raw        jsonb       not null,
  seen_at    timestamptz not null default now()
);
create unique index fc_track_event_uq on public.fc_track_event (booking_id, at, type, md5(coalesce(message, '')));
alter table public.fc_track_event enable row level security;
revoke all on table public.fc_track_event from public, anon, authenticated, service_role;
grant select on table public.fc_track_event to service_role;
comment on table public.fc_track_event is 'fc-track-2: Freightcom GET /shipment/{id}/tracking-events 의 이벤트 한 줄(더하기만 · fc_track_save 만 쓴다) — type 원문 lower(CHECK 없음 · 모르는 값 받음) · at = when(나노초 → 마이크로초) · place {city, region, country}(셋 다 비면 null) · message = btrim 값 · raw = 받은 원소 그대로 · RLS 켬 · 정책 없음(로그인한 사람도 표를 직접 못 읽는다 · 읽기 창구는 fc-track-4)';

-- ═══ 4) 속 함수 둘 ═══
create function public.fc_state_kind(p_state text) returns text
  language sql immutable
  set search_path = public, pg_temp
as $$
  select case
    when s is null or s = '' then 'open'
    when s = 'delivered' then 'delivered'
    when s in ('cancelled', 'canceled') or s like 'cancel%' then 'cancelled'      -- 실물은 cancelled 뿐 · 나머지는 짐작
    else 'open'
  end
  from (select lower(btrim(p_state)) as s) x;
$$;
revoke all on function public.fc_state_kind(text) from public, anon, authenticated, service_role;
comment on function public.fc_state_kind(text) is 'fc-track-2 이견 8(속 · 한 곳): Freightcom 쉽먼트 state 원문 → cancelled | delivered | open — 픽업 판정(fc_pickup_check · fc_pickup_poll_due) · 자동 다시 읽기의 끝(fc_track_save) · 인정 창구(fc_book_mark_cancelled)가 같이 쓴다 · 실물로 본 값은 cancelled · delivered · canceled · cancel% 는 짐작 · 모르는 값은 open';

create function public.fc_ts(p text) returns timestamptz
  language plpgsql immutable
  set search_path = public, pg_temp
as $$
declare v text := btrim(coalesce(p, ''));
begin
  if v !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}' then return null; end if;
  v := regexp_replace(v, '(\.\d{6})\d+', '\1');                                   -- 나노초 9 자리 → 마이크로초로 자름(반올림 아님)
  begin
    return v::timestamptz;
  exception when others then
    return null;
  end;
end;
$$;
revoke all on function public.fc_ts(text) from public, anon, authenticated, service_role;
comment on function public.fc_ts(text) is 'fc-track-2(속): Freightcom 의 when 글자(2026-11-05T22:45:20.465569955Z · 나노초 9 자리) → timestamptz(마이크로초로 자름) · ISO 꼴이 아니거나 못 읽으면 null(그 이벤트는 넣지 않고 skipped 로 센다)';

-- ═══ 5) 자동 다시 읽기 대상 — 한 곳 ═══
create function public.fc_track_due(p_limit int default 10)
  returns table (booking_id uuid, shipment_id uuid, attempt int, account text, freightcom_shipment_id text, booked_at timestamptz, state text, state_checked_at timestamptz, tier text)
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  with c as (
    select b.id, b.shipment_id, b.attempt, b.account, b.freightcom_shipment_id, b.booked_at, b.state, b.state_checked_at,
           case when b.state_checked_at is null then 'first'
                when lower(coalesce(b.track_last->>'message', '')) like 'out for delivery%' then 'out_for_delivery'
                else 'regular' end as tier
      from public.fc_booking b
     where b.status = 'booked'
       and nullif(btrim(b.freightcom_shipment_id), '') is not null
       and b.track_done_at is null
       and b.booked_at > now() - interval '30 days'
  )
  select c.id, c.shipment_id, c.attempt, c.account, c.freightcom_shipment_id, c.booked_at, c.state, c.state_checked_at, c.tier
    from c
   where c.tier = 'first'
      or c.state_checked_at < now() - (case when c.tier = 'out_for_delivery' then interval '1 hour' else interval '3 hours' end)
   order by c.state_checked_at nulls first, c.booked_at, c.attempt
   limit (case when p_limit between 1 and 50 then p_limit else 10 end);
$$;
revoke all on function public.fc_track_due(int) from public, anon, authenticated;
grant execute on function public.fc_track_due(int) to service_role;
comment on function public.fc_track_due(int) is 'fc-track-2 ④ · 판정 1160: 상태 자동 다시 읽기 대상(한 곳 · cron ims-fc-track-poll 의 where 와 EF freightcom track_sweep 가 같이 쓴다 · service_role 만 · 읽기) — booked · Freightcom id 있음 · track_done_at null(끝 상태 + 이벤트를 아직 함께 못 읽음) · 예약 뒤 30 일 안 · 읽은 적 없음(first) ∨ 마지막 성공 읽기에서 3 시간(regular) · track_last.message 가 out for delivery 로 시작하면 1 시간 · 정렬 state_checked_at nulls first → booked_at · p_limit 1 ~ 50(밖이면 10)';

-- ═══ 6) 저장 ═══
create function public.fc_track_save(p_booking_id uuid, p_shipment jsonb, p_events jsonb default null) returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare
  v_b      public.fc_booking%rowtype;
  v_sh     jsonb;
  v_arr    jsonb;
  v_e      jsonb;
  v_w      jsonb;
  v_at     timestamptz;
  v_place  jsonb;
  v_state  text;
  v_before text;
  v_kind   text;
  v_conf   text;
  v_bol    text;
  v_trk    text;
  v_n      int;
  v_recv   int := 0;
  v_add    int := 0;
  v_skip   int := 0;
  v_read   boolean := p_events is not null and jsonb_typeof(p_events) <> 'null';
  v_last   jsonb;
  v_deliv  timestamptz;
  v_done   timestamptz;
  v_mis    boolean := false;
  v_warn   text[] := '{}';
begin
  if not public.doc_is_service() then raise exception 'fc_track_save is for the freight service only — nothing was saved'; end if;
  if p_shipment is null or jsonb_typeof(p_shipment) <> 'object' then raise exception 'p_shipment must be a JSON object — nothing was saved'; end if;
  select * into v_b from public.fc_booking b where b.id = p_booking_id for update;
  if not found then raise exception 'Booking % not found — nothing was saved', p_booking_id; end if;
  if v_b.status <> 'booked' then raise exception 'Booking #% is % — tracking is read for booked shipments only — nothing was saved', v_b.attempt, v_b.status; end if;
  v_sh := case when jsonb_typeof(p_shipment->'shipment') = 'object' then p_shipment->'shipment' else p_shipment end;
  if nullif(btrim(v_sh->>'id'), '') is distinct from v_b.freightcom_shipment_id then raise exception 'The shipment answer is for % — this booking is % — nothing was saved', coalesce(nullif(btrim(v_sh->>'id'), ''), '(no id)'), v_b.freightcom_shipment_id; end if;
  v_before := v_b.state;
  v_state := left(nullif(lower(btrim(v_sh->>'state')), ''), 60);
  if v_state is null then v_state := v_b.state; v_warn := array_append(v_warn, 'no_state — the Freightcom answer has no state · kept ' || coalesce(v_b.state, '(none)')); end if;
  v_kind := public.fc_state_kind(v_state);
  -- 이벤트 — {events:[…]} 또는 배열 맨몸 · 더하기만 · when 을 못 읽으면 넣지 않고 센다
  if v_read then
    v_arr := case when jsonb_typeof(p_events) = 'array' then p_events when jsonb_typeof(p_events) = 'object' and jsonb_typeof(p_events->'events') = 'array' then p_events->'events' end;
    if v_arr is null then raise exception 'p_events must be a JSON list or {events:[…]} — nothing was saved'; end if;
    for v_e in select e from jsonb_array_elements(v_arr) e loop
      v_recv := v_recv + 1;
      v_at := case when jsonb_typeof(v_e) = 'object' then public.fc_ts(v_e->>'when') end;
      if v_at is null then v_skip := v_skip + 1; continue; end if;
      v_w := case when jsonb_typeof(v_e->'where') = 'object' then v_e->'where' end;
      v_place := jsonb_strip_nulls(jsonb_build_object('city', nullif(btrim(v_w->>'city'), ''), 'region', nullif(btrim(v_w->>'region'), ''), 'country', nullif(btrim(v_w->>'country'), '')));
      insert into public.fc_track_event (booking_id, type, at, place, message, raw)
      values (v_b.id, coalesce(left(nullif(lower(btrim(v_e->>'type')), ''), 60), 'unknown'), v_at, nullif(v_place, '{}'::jsonb), nullif(btrim(v_e->>'message'), ''), v_e)
      on conflict (booking_id, at, type, md5(coalesce(message, ''))) do nothing;
      get diagnostics v_n = row_count;
      v_add := v_add + v_n;
    end loop;
    if v_skip > 0 then v_warn := array_append(v_warn, format('events_skipped — %s of %s tracking events had no readable time and were not saved', v_skip, v_recv)); end if;
    select jsonb_build_object('type', t.type, 'at', t.at, 'city', t.place->>'city', 'region', t.place->>'region', 'message', t.message) into v_last
      from public.fc_track_event t where t.booking_id = v_b.id order by t.at desc, t.id desc limit 1;
  end if;
  v_deliv := v_b.delivered_at;
  v_done := v_b.track_done_at;
  if v_read and v_kind = 'delivered' then
    v_deliv := coalesce((select min(t.at) from public.fc_track_event t where t.booking_id = v_b.id and t.type = 'delivered'), v_b.delivered_at, clock_timestamp());
  end if;
  if v_read and v_kind in ('delivered', 'cancelled') then v_done := coalesce(v_b.track_done_at, clock_timestamp()); end if;
  -- 확인번호 · BOL 은 비었을 때만(1041) · 추적번호 · SO 칸은 건드리지 않는다(이견 9)
  v_conf := nullif(btrim(v_sh->>'pickup_confirmation_number'), '');
  if v_b.pickup_confirmation is not null then
    if v_conf is not null and v_conf <> v_b.pickup_confirmation then
      v_mis := true;
      v_warn := array_append(v_warn, format('confirmation_mismatch — IMS has %s · Freightcom now says %s · kept the IMS value', v_b.pickup_confirmation, v_conf));
    end if;
    v_conf := v_b.pickup_confirmation;
  end if;
  v_bol := coalesce(nullif(btrim(v_b.bol_number), ''), nullif(btrim(v_sh->>'bolnumber'), ''), nullif(btrim(v_sh->>'bol_number'), ''));
  v_trk := nullif(btrim(v_sh->>'primary_tracking_number'), '');
  if v_trk is not null and v_trk is distinct from v_b.tracking_number then
    v_warn := array_append(v_warn, format('tracking_differs — IMS has %s · Freightcom now says %s · the booking and the orders were left as they are', coalesce(v_b.tracking_number, '(none)'), v_trk));
  end if;
  update public.fc_booking
     set state = v_state, state_checked_at = clock_timestamp(), delivered_at = v_deliv, track_done_at = v_done,
         track_last = case when v_read then v_last else track_last end,
         pickup_confirmation = v_conf, bol_number = v_bol
   where id = v_b.id;
  select * into v_b from public.fc_booking b where b.id = v_b.id;
  return jsonb_build_object('booking_id', v_b.id, 'attempt', v_b.attempt, 'status', v_b.status,
                            'state', v_b.state, 'state_before', v_before, 'state_changed', v_b.state is distinct from v_before, 'state_kind', v_kind,
                            'state_checked_at', v_b.state_checked_at, 'delivered_at', v_b.delivered_at, 'track_done_at', v_b.track_done_at, 'track_last', v_b.track_last,
                            'events_read', v_read, 'events_received', v_recv, 'events_added', v_add, 'events_skipped', v_skip,
                            'events_total', (select count(*) from public.fc_track_event t where t.booking_id = v_b.id),
                            'pickup_confirmation', v_b.pickup_confirmation, 'confirmation_mismatch', v_mis, 'bol_number', v_b.bol_number,
                            'warnings', to_jsonb(v_warn), 'pickup_check', public.fc_pickup_check(v_b));
end;
$$;
revoke all on function public.fc_track_save(uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.fc_track_save(uuid, jsonb, jsonb) to service_role;
comment on function public.fc_track_save(uuid, jsonb, jsonb) is 'fc-track-2 ⑤ · 판정 1160: GET /shipment/{id} + GET /shipment/{id}/tracking-events 결과 저장(EF service_role 만 · booked 만 · 응답 id 가 예약과 다르면 거부) — state(lower 원문) · state_checked_at · 이벤트 더하기(중복 무시 · when 못 읽으면 skipped) · track_last · delivered_at · track_done_at(끝 상태 ∧ 이벤트 읽음 · 처음 한 번) · 확인번호 · BOL 은 비었을 때만 · 추적번호 · SO 칸 무변(다르면 warnings) · p_events null = 이벤트 못 읽은 회차 · 반환에 주소 없음';

-- ═══ 7) 사람 길의 문 ═══
create function public.fc_track_gate(p_booking_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_b public.fc_booking%rowtype;
  v_f public.fc_shipment%rowtype;
begin
  if not (public.ims_can_write('sales') or public.ims_can_write('fulfillment') or public.ims_can_write('freight_booking')) then
    raise exception 'You cannot refresh freight tracking — ask an admin for the ''sales'', ''fulfillment'' or ''freight_booking'' permission — nothing was read';
  end if;
  select * into v_b from public.fc_booking b where b.id = p_booking_id;
  if not found then raise exception 'Booking % not found — nothing was read', p_booking_id; end if;
  select * into v_f from public.fc_shipment f where f.id = v_b.shipment_id;
  if not public.ims_can_warehouse(v_f.origin_warehouse_id) then raise exception 'This shipment belongs to another warehouse — nothing was read'; end if;
  if v_b.status <> 'booked' or nullif(btrim(v_b.freightcom_shipment_id), '') is null then
    raise exception 'Booking #% is % — tracking is read for booked shipments only — nothing was read', v_b.attempt, v_b.status;
  end if;
  return jsonb_build_object('booking_id', v_b.id, 'shipment_id', v_b.shipment_id, 'attempt', v_b.attempt, 'status', v_b.status, 'account', v_b.account, 'freightcom_shipment_id', v_b.freightcom_shipment_id);
end;
$$;
revoke all on function public.fc_track_gate(uuid) from public, anon;
grant execute on function public.fc_track_gate(uuid) to authenticated;
comment on function public.fc_track_gate(uuid) is 'fc-track-2 ⑥ 이견 4: 사람 길 track_poll 의 문(사용자 JWT · 읽기) — sales ∨ fulfillment ∨ freight_booking 쓰기 + 그 창고(ims_can_warehouse) · booked ∧ Freightcom id · EF 가 GET 앞에 부르고 계정 · Freightcom id 를 받는다';

-- ═══ 8) 1158 — Freightcom 에서 취소된 예약은 「픽업 필요 없음」(재발행 둘 · fc_pickup_attention_list 는 이 판정을 그대로 읽는다) ═══
create or replace function public.fc_pickup_check(b public.fc_booking) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
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
  v_cx      boolean;
begin
  v_pkg := case when b.request ? 'dispatch_details' then 'pallet' else 'package' end;
  v_cx := b.status = 'booked' and public.fc_state_kind(b.state) = 'cancelled';                          -- fc-track-2 판정 1158: Freightcom 에서 취소됨 = 픽업 필요 없음
  v_needed := b.status = 'booked' and not v_cx and v_pkg = 'package' and (b.request#>>'{pickup_details,pre_scheduled_pickup}') = 'false';
  v_p := case when b.schedule_response is not null then public.fc_schedule_parse(b.schedule_response) end;
  v_fc_conf := v_p->>'confirmation';
  v_mis := b.pickup_confirmation is not null and v_fc_conf is not null and v_fc_conf <> b.pickup_confirmation;
  v_read := b.schedule_checked_at is not null;
  v_age := case when b.booked_at is not null then floor(extract(epoch from (now() - b.booked_at)) / 60)::int end;
  v_bad := b.schedule_status is not null and b.schedule_status not in ('pending', 'done');            -- error · timed-out · 네 값 밖(unknown · 원문)
  v_pend := v_needed and b.pickup_confirmation is null and coalesce(b.schedule_status = 'pending', false) and coalesce(v_age, 0) < 15;      -- 읽은 적 없음(status null)은 false · null 이 아니다(시험 4 회차 P1 에서 잡힘)
  v_not := v_needed and b.pickup_confirmation is null and (v_bad or not v_read or coalesce(v_age, 0) >= 15 or coalesce(b.schedule_status = 'done', false));
  v_msg := case
    when b.status <> 'booked' then null
    when v_cx then 'Cancelled on Freightcom — no pickup to check'
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
                            'confirmation', b.pickup_confirmation, 'freightcom_confirmation', v_fc_conf, 'confirmation_mismatch', v_mis, 'minutes_since_booked', v_age, 'message', v_msg, 'freightcom_cancelled', v_cx);
end;
$$;

create or replace function public.fc_pickup_poll_due(p_limit int default 10)
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
       and public.fc_state_kind(b.state) <> 'cancelled'
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

-- ═══ 9) 1159 — 「Freightcom 에서 취소됨」 인정(Freightcom 호출 없음 · 사람이 누른다) ═══
create function public.fc_book_mark_cancelled(p_booking_id uuid, p_note text default null) returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare
  v_b     public.fc_booking%rowtype;
  v_f     public.fc_shipment%rowtype;
  v_w     jsonb;
  v_so    public.so%rowtype;
  v_rest  text[] := '{}';
  v_kept  text[] := '{}';
  v_staff uuid;
  v_note  text := nullif(btrim(regexp_replace(coalesce(p_note, ''), '\s+', ' ', 'g')), '');
begin
  select * into v_b from public.fc_booking b where b.id = p_booking_id for update;
  if not found then raise exception 'Booking % not found — nothing was changed', p_booking_id; end if;
  select * into v_f from public.fc_shipment f where f.id = v_b.shipment_id for update;
  perform public.fc_book_gate(v_f.origin_warehouse_id, 'changed');
  if v_b.status <> 'booked' then raise exception 'Booking #% is % — there is nothing to mark as cancelled — nothing was changed', v_b.attempt, v_b.status; end if;
  if public.fc_state_kind(v_b.state) <> 'cancelled' then
    raise exception 'Freightcom does not show this shipment as cancelled (it says %) — refresh the tracking first · to cancel it at Freightcom use Cancel booking — nothing was changed', coalesce(v_b.state, 'nothing yet');
  end if;
  if char_length(coalesce(v_note, '')) > 500 then raise exception 'The note is % characters — the limit is 500 — nothing was changed', char_length(v_note); end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  -- 856: 예약 때 쓴 값과 아직 같을 때만 그 전 값으로 · 사람이 바꾼 칸은 둔다(fc_book_cancel_save 와 같은 판정)
  for v_w in select w from jsonb_array_elements(coalesce(v_b.so_written, '[]'::jsonb)) w loop
    select * into v_so from public.so s where s.id = (v_w->>'so_id')::uuid for update;
    if not found then continue; end if;
    if v_so.carrier_id::text is not distinct from nullif(v_w#>>'{written,carrier_id}', '') and v_so.carrier is not distinct from nullif(v_w#>>'{written,carrier}', '') and v_so.tracking_number is not distinct from nullif(v_w#>>'{written,tracking_number}', '') then
      update public.so s set carrier_id = nullif(v_w#>>'{before,carrier_id}', '')::uuid, carrier = nullif(v_w#>>'{before,carrier}', ''), tracking_number = nullif(v_w#>>'{before,tracking_number}', '') where s.id = v_so.id;
      v_rest := array_append(v_rest, v_so.so_number);
    else
      v_kept := array_append(v_kept, v_so.so_number);
    end if;
  end loop;
  update public.fc_booking set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff, cancel_error = null, cancel_source = 'freightcom', cancel_note = v_note where id = v_b.id;   -- response 는 덮지 않는다(475)
  if v_f.booking_id = v_b.id and v_f.status = 'booked' then
    update public.fc_shipment set status = 'selected', updated_by = v_staff where id = v_f.id;                               -- 856 과 같다 — 출고 전이면 바로 다시 예약 · 출고된 SO 는 fc_book_prepare 가 거부한다
  end if;
  return jsonb_build_object('booking_id', v_b.id, 'attempt', v_b.attempt, 'status', 'cancelled', 'cancel_source', 'freightcom', 'cancel_note', v_note, 'state', v_b.state,
                            'shipment_id', v_f.id, 'shipment_status', (select f.status from public.fc_shipment f where f.id = v_f.id), 'orders_restored', to_jsonb(v_rest), 'orders_kept', to_jsonb(v_kept));
end;
$$;
revoke all on function public.fc_book_mark_cancelled(uuid, text) from public, anon;
grant execute on function public.fc_book_mark_cancelled(uuid, text) to authenticated;
comment on function public.fc_book_mark_cancelled(uuid, text) is 'fc-track-2 ⑧ · 판정 1159: Freightcom 에서 이미 취소된 예약을 IMS 가 인정(사람이 누른다 · Freightcom 호출 없음) — 문 fc_book_gate(freight_booking + 그 창고) · booked ∧ fc_state_kind(state) = cancelled · 출고된 SO 도 받는다 · SO 칸은 예약 때 쓴 값과 아직 같을 때만 그 전 값으로(orders_restored / orders_kept) · 발송 booked → selected · cancel_source freightcom · cancel_note(500 자 · 한 줄) · response 무변';

create or replace function public.fc_book_cancel_save(p_booking_id uuid, p_response jsonb default null, p_error text default null) returns jsonb
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare
  v_b    public.fc_booking%rowtype;
  v_f    public.fc_shipment%rowtype;
  v_w    jsonb;
  v_so   public.so%rowtype;
  v_rest text[] := '{}';
  v_kept text[] := '{}';
  v_staff uuid;
begin
  if not public.doc_is_service() then raise exception 'fc_book_cancel_save is for the freight service only — nothing was saved'; end if;
  select * into v_b from public.fc_booking b where b.id = p_booking_id for update;
  if not found then raise exception 'Booking % not found — nothing was saved', p_booking_id; end if;
  select * into v_f from public.fc_shipment f where f.id = v_b.shipment_id for update;
  if v_b.status <> 'booked' then raise exception 'Booking #% is % — nothing to cancel — nothing was saved', v_b.attempt, v_b.status; end if;
  if p_error is not null then
    update public.fc_booking set cancel_error = left(p_error, 1000) where id = v_b.id;                                       -- Freightcom 이 거절 — 예약은 그대로 · 문장만 남긴다
    return jsonb_build_object('booking_id', v_b.id, 'attempt', v_b.attempt, 'status', 'booked', 'cancel_error', left(p_error, 1000));
  end if;
  v_staff := nullif(p_response->>'cancelled_by', '')::uuid;                                                                     -- EF 가 직원 id 를 끼워 보낸다(service_role 이라 auth.uid() 가 없다)
  -- 855: 예약 때 쓴 값과 아직 같을 때만 그 전 값으로 · 사람이 바꾼 칸은 둔다
  for v_w in select w from jsonb_array_elements(coalesce(v_b.so_written, '[]'::jsonb)) w loop
    select * into v_so from public.so s where s.id = (v_w->>'so_id')::uuid for update;
    if not found then continue; end if;
    if v_so.carrier_id::text is not distinct from nullif(v_w#>>'{written,carrier_id}', '') and v_so.carrier is not distinct from nullif(v_w#>>'{written,carrier}', '') and v_so.tracking_number is not distinct from nullif(v_w#>>'{written,tracking_number}', '') then
      update public.so s set carrier_id = nullif(v_w#>>'{before,carrier_id}', '')::uuid, carrier = nullif(v_w#>>'{before,carrier}', ''), tracking_number = nullif(v_w#>>'{before,tracking_number}', '') where s.id = v_so.id;
      v_rest := array_append(v_rest, v_so.so_number);
    else
      v_kept := array_append(v_kept, v_so.so_number);
    end if;
  end loop;
  update public.fc_booking set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff, cancel_error = null, cancel_source = 'ims', response = coalesce(p_response - 'cancelled_by', response) where id = v_b.id;
  update public.fc_shipment set status = 'selected' where id = v_f.id;                                                          -- 856: 고른 줄 그대로 · 다시 예약은 book_prepare(valid_until · units_changed 가 다시 본다)
  return jsonb_build_object('booking_id', v_b.id, 'attempt', v_b.attempt, 'status', 'cancelled', 'shipment_status', 'selected', 'orders_restored', to_jsonb(v_rest), 'orders_kept', to_jsonb(v_kept));
end;
$$;

-- ═══ 10) 착지 확인 — 무접촉 함수의 md5 · 새 것의 꼴 ═══
do $$
declare v_md5 text; v_r record;
begin
  for v_r in select * from (values ('fc_book_schedule_save', 'd26d7d7cd17bd681c3d5dca7bf9220e4'), ('fc_pickup_attention_list', 'b9177f02f0ae15e4d783e5208919f333'), ('fc_booking_for_shipment', '7413429f0b0e31d04a6e926042d6e6cf'),
                                    ('fc_book_cancel_prepare', 'd48d715d29d3157add217e39c8d7d02d'), ('fc_book_gate', '99c10bd35d0ba0b087b28425b514efd2'), ('fc_book_save', 'e6a0f6a0c836a5304ff2b8e5f5f1fc1c')) t(fn, want) loop
    select md5(p.prosrc) into v_md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = v_r.fn;
    if v_md5 is distinct from v_r.want then raise exception 'fc-track-2 landing check failed: % touched or missing (%)', v_r.fn, coalesce(v_md5, 'null'); end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fc_state_kind', 'fc_ts', 'fc_track_due', 'fc_track_save', 'fc_track_gate', 'fc_book_mark_cancelled', 'fc_pickup_check', 'fc_pickup_poll_due', 'fc_book_cancel_save')) <> 9 then
    raise exception 'fc-track-2 landing check failed: expected 9 functions (one definition each)';
  end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.fc_track_event'::regclass) or exists (select 1 from pg_policy p where p.polrelid = 'public.fc_track_event'::regclass)
     or has_table_privilege('authenticated', 'public.fc_track_event', 'select') or has_table_privilege('anon', 'public.fc_track_event', 'select') then
    raise exception 'fc-track-2 landing check failed: fc_track_event must be closed (RLS on · no policy · no authenticated / anon select)';
  end if;
  if (select count(*) from public.inv_config c where c.key in ('fc_track_poll_enabled', 'fc_track_poll_batch')) <> 2 then raise exception 'fc-track-2 landing check failed: inv_config keys missing'; end if;
  if exists (select 1 from public.fc_booking b where b.cancel_source is not null or b.track_done_at is not null or b.state_checked_at is not null) then raise exception 'fc-track-2 landing check failed: new columns must start empty'; end if;
end $$;
