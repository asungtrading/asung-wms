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
-- fc-pickup-1 — Freightcom 예약 뒤 픽업 스케줄 다시 읽기 · 알리기 (2026-11-05 · 지시서 ~/asung/prompts/fc-pickup-1.md · 조사 fc-pickup-0 · Claude Code 이견 1 ~ 12 모두 승인)
--   왜: 토론토 상자 예약(UPS · Purolator · 비정기 픽업 · 날짜 · 시각 보냄)이 Freightcom 에서 `waiting-for-scheduling` 에 머물고 확인번호가 비는데 IMS 는 예약 순간 상태만 적었다(deferred 464 · so §100-c 7).
--       이 차수는 「다시 읽기 · 알리기」 만 — 원인(H1 ~ H3)을 IMS 에 적게 한다 · 고치기(POST schedule · location · validate)는 fc-pickup-2 · 이 차수의 Freightcom 호출은 GET 만
--   ① fc_booking 칸 넷(이견 1): schedule_status(원문 그대로 · lower · trim · 40 자 · CHECK 없음 — 실물 꼴을 아무도 못 봤다 · 문자열이 아니면 'unknown') · schedule_error · schedule_checked_at(마지막 「성공」 읽기 · clock_timestamp — 한 트랜잭션 안 두 번 읽기도 가른다) · schedule_response(원문 · 덮어쓰기)
--   ② fc_schedule_parse(p) — 한 파서(저장 창구 · 읽기 창구가 같이 쓴다): {schedule:{…}} · {pickup:{…}} 감쌈 · 맨몸 · status · 확인번호(pickup_confirmation_number | confirmation_number | pickup_confirmation) · 오류 글(message | error | reason | errors[0].message | errors[0] | error_message — 짐작 · 원문이 남는다) · 받은 최상위 열쇠 목록(첫 실호출 뒤 확인용)
--   ③ fc_book_schedule_save(p_booking_id, p_schedule, p_shipment default null) — EF service_role 만 · booked 만(pending · failed · cancelled 거부 · 이견 8) · 팔렛 · 정기도 허용(GET 만) ·
--      확인번호: 비었으면 채움(schedule 먼저 · 없으면 shipment 의 pickup_confirmation_number) · 이미 있으면 덮지 않음(같으면 그대로 · 다르면 warning · 이견 6) · p_shipment 가 오면 id 가 이 예약의 것이어야 하고 state 를 새로 적는다(이견 3)
--      GET 실패(404 · 5xx · 망)는 EF 가 이 창구를 부르지 않는다(DB 무변 · fc_call_log 만 · 이견 2)
--   ④ fc_pickup_check(b) — 「픽업이 안 잡혔다」 판정 + 영어 한 줄(이견 4 · 5): needed = booked ∧ request.pickup_details.pre_scheduled_pickup = false(팔렛 dispatch_details · 정기 true 는 false) ·
--      not_scheduled = needed ∧ 확인번호 null ∧ (status ∈ {error, timed-out} ∨ 네 값 밖 ∨ 읽은 적 없음 ∨ booked_at 이 15 분 전 ∨ done 인데 번호 없음) · pending = needed ∧ 확인번호 null ∧ status pending ∧ 15 분 안 · 글은 DB 한 곳(EF 응답 detail · 새로 고침이 같다)
--   ⑤ fc_booking_for_shipment 재발행(원본 20261028223000:428 · DB md5 8b084076afea15fbd36a071b969b336b) — current 에서 schedule_response 도 뺀다(request · response 처럼) · current.pickup_check 를 더한다 · 그 밖 바이트 그대로
--   새 FK 없음 · cron 없음 · fc_book_prepare · fc_book_save · fc_book_cancel_save 무접촉(① 7 의 취소 덮어쓰기는 따로) · 화면 무접촉 · 첫 문장 = guard-test-only.sql 바이트 복사
--   적용(Caleb · 17:00 뒤): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261105183506_fc_pickup_1_schedule_read.sql && supabase migration repair --status applied 20261105183506 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback · 레포 루트 · 17:00 뒤): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261105183506_fc_pickup_1_schedule_read.sql -f supabase/tests/fc_pickup_1_check.sql

-- ═══ 1) 칸 넷 ═══
alter table public.fc_booking
  add column schedule_status     text,
  add column schedule_error      text,
  add column schedule_checked_at timestamptz,
  add column schedule_response   jsonb;
comment on column public.fc_booking.schedule_status     is 'fc-pickup-1: GET /shipment/{id}/schedule 의 status 원문(lower · trim · 40 자 · 문서는 pending | timed-out | error | done · 문자열이 아니면 unknown · CHECK 없음 — 실물 꼴 미확인) · null = 읽은 적 없음';
comment on column public.fc_booking.schedule_error      is 'fc-pickup-1: 같은 응답의 오류 글(message | error | reason | errors[0] … 짐작 · 읽을 때마다 덮는다 · 없으면 null)';
comment on column public.fc_booking.schedule_checked_at is 'fc-pickup-1: 마지막으로 성공해 읽은 시각(GET 실패는 DB 무변 · fc_call_log 만)';
comment on column public.fc_booking.schedule_response   is 'fc-pickup-1: GET /shipment/{id}/schedule 원문(덮어쓰기) · fc_booking_for_shipment.current 에는 싣지 않는다(request · response 처럼) · 첫 실호출 뒤 jsonb_object_keys 로 꼴 확인';

-- ═══ 2) 파서 하나 ═══
create function public.fc_schedule_parse(p jsonb) returns jsonb
  language plpgsql immutable
  set search_path = public, pg_temp
as $$
declare
  v_s    jsonb;
  v_st   text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    return jsonb_build_object('status', 'unknown', 'confirmation', null, 'error', null, 'keys', '[]'::jsonb, 'wrapped', null);
  end if;
  v_s := coalesce(nullif(p->'schedule', 'null'::jsonb), nullif(p->'pickup', 'null'::jsonb), p);
  if jsonb_typeof(v_s) <> 'object' then v_s := p; end if;
  v_st := case when jsonb_typeof(v_s->'status') = 'string' then left(lower(btrim(v_s->>'status')), 40) end;
  return jsonb_build_object(
    'status',       coalesce(nullif(v_st, ''), 'unknown'),
    'confirmation', coalesce(nullif(btrim(v_s->>'pickup_confirmation_number'), ''), nullif(btrim(v_s->>'confirmation_number'), ''), nullif(btrim(v_s->>'pickup_confirmation'), '')),
    'error',        left(coalesce(nullif(btrim(v_s->>'message'), ''), nullif(btrim(v_s->>'error'), ''), nullif(btrim(v_s->>'reason'), ''), nullif(btrim(v_s#>>'{errors,0,message}'), ''), nullif(btrim(v_s#>>'{errors,0}'), ''), nullif(btrim(v_s->>'error_message'), '')), 1000),
    'keys',         (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from jsonb_object_keys(p) k),
    'wrapped',      case when v_s is distinct from p then (select k from jsonb_object_keys(p) k where k in ('schedule', 'pickup') limit 1) end);
end;
$$;
revoke all on function public.fc_schedule_parse(jsonb) from public, anon, authenticated, service_role;
comment on function public.fc_schedule_parse(jsonb) is 'fc-pickup-1 ②: GET /shipment/{id}/schedule 응답 한 파서(속 · 저장 · 읽기 창구가 같이 쓴다) — {status, confirmation, error, keys(받은 최상위 열쇠 · 첫 실호출 확인용), wrapped} · 열쇠 이름은 문서 스키마 + 짐작 · 원문은 fc_booking.schedule_response 에 남는다';

-- ═══ 3) 저장 창구 ═══
create function public.fc_book_schedule_save(p_booking_id uuid, p_schedule jsonb, p_shipment jsonb default null) returns jsonb
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
         pickup_confirmation = v_conf, state = v_state
   where id = v_b.id;
  select * into v_b from public.fc_booking b where b.id = v_b.id;
  return jsonb_build_object('booking_id', v_b.id, 'attempt', v_b.attempt, 'status', v_b.status, 'schedule_status', v_b.schedule_status, 'schedule_error', v_b.schedule_error, 'schedule_checked_at', v_b.schedule_checked_at,
                            'pickup_confirmation', v_b.pickup_confirmation, 'confirmation_source', v_src, 'confirmation_mismatch', v_mis, 'state', v_b.state, 'shipment_read', p_shipment is not null,
                            'received_keys', v_p->'keys', 'wrapped', v_p->'wrapped', 'warnings', to_jsonb(v_warn), 'pickup_check', public.fc_pickup_check(v_b));
end;
$$;
revoke all on function public.fc_book_schedule_save(uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.fc_book_schedule_save(uuid, jsonb, jsonb) to service_role;
comment on function public.fc_book_schedule_save(uuid, jsonb, jsonb) is 'fc-pickup-1 ③: GET /shipment/{id}/schedule 결과 저장(EF service_role 만 · booked 만) — schedule_status · error · checked_at · 원문 · 확인번호는 비었을 때만(schedule → shipment 순) · 있으면 덮지 않음(다르면 warnings) · p_shipment(GET /shipment/{id} 원문 · 선택)가 오면 id 일치 검사 뒤 state 를 새로 · 반환에 received_keys(첫 실호출 꼴 확인) · pickup_check';

-- ═══ 4) 판정 · 글 ═══
create function public.fc_pickup_check(b public.fc_booking) returns jsonb
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
begin
  v_pkg := case when b.request ? 'dispatch_details' then 'pallet' else 'package' end;
  v_needed := b.status = 'booked' and v_pkg = 'package' and (b.request#>>'{pickup_details,pre_scheduled_pickup}') = 'false';
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
end;
$$;
revoke all on function public.fc_pickup_check(public.fc_booking) from public, anon, authenticated, service_role;
comment on function public.fc_pickup_check(public.fc_booking) is 'fc-pickup-1 ④(속 · definer 창구에서만): 예약 한 행의 「픽업이 안 잡혔다」 판정 + 영어 한 줄 — needed(booked · 상자 · pre_scheduled_pickup false) · not_scheduled(빨강) · pending(15 분 안 · check again) · status · error · checked_at · confirmation · freightcom_confirmation · confirmation_mismatch · minutes_since_booked · message';

-- ═══ 5) fc_booking_for_shipment 재발행(원본 20261028223000:428 · current 에서 schedule_response 도 빼고 pickup_check 를 더한다 · 그 밖 바이트 그대로) ═══
create or replace function public.fc_booking_for_shipment(p_shipment_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare v_f public.fc_shipment%rowtype;
begin
  select * into v_f from public.fc_shipment f where f.id = p_shipment_id;
  if not found then raise exception 'Shipment % not found', p_shipment_id; end if;
  if not (public.ims_can_view('sales') or public.ims_can_view('fulfillment') or public.ims_can_write('freight_booking')) then raise exception 'You cannot see freight bookings — ask an admin for the ''sales'', ''fulfillment'' or ''freight_booking'' permission'; end if;
  return jsonb_build_object('shipment_id', v_f.id, 'status', v_f.status, 'booking_id', v_f.booking_id, 'can_book', public.ims_can_write('freight_booking') and public.ims_can_warehouse(v_f.origin_warehouse_id),
    'current', (select to_jsonb(b) - 'request' - 'response' - 'schedule_response' || jsonb_build_object('pickup_check', public.fc_pickup_check(b)) from public.fc_booking b where b.id = v_f.booking_id),
    'attempts', (select coalesce(jsonb_agg(jsonb_build_object('booking_id', b.id, 'attempt', b.attempt, 'unique_id', b.unique_id, 'status', b.status, 'service_id', b.service_id, 'tracking_number', b.tracking_number, 'error', b.error, 'requested_at', b.requested_at, 'booked_at', b.booked_at, 'cancelled_at', b.cancelled_at) order by b.attempt), '[]'::jsonb) from public.fc_booking b where b.shipment_id = v_f.id),
    'labels', (select coalesce(jsonb_agg(jsonb_build_object('label_id', l.id, 'booking_id', l.booking_id, 'size', l.size, 'format', l.format, 'padded', l.padded, 'path', l.path, 'bytes', l.bytes, 'pages', l.pages, 'fetched_at', l.fetched_at) order by l.size, l.padded), '[]'::jsonb) from public.fc_label l where l.booking_id = v_f.booking_id));
end;
$$;
comment on function public.fc_booking_for_shipment(uuid) is 'fc-2b: 한 발송의 예약 — 현재 시도(request · response · schedule_response 는 뺀다) · current.pickup_check(fc-pickup-1 · 「픽업이 안 잡혔다」 표지 · 영어 한 줄) · 시도 이력 · 현재 시도의 라벨 행 · can_book(853 + 창고) · 문 = sales · fulfillment(보기) 또는 freight_booking · 화면이 fc_shipment_for_so 옆에서 부른다(for_so 무접촉)';

-- ═══ 6) 착지 검사 ═══
do $$
declare v_n int; v_acl text; v_md5 text;
begin
  select count(*) into v_n from information_schema.columns where table_schema = 'public' and table_name = 'fc_booking' and column_name in ('schedule_status', 'schedule_error', 'schedule_checked_at', 'schedule_response');
  if v_n <> 4 then raise exception 'fc-pickup-1 landing check failed: fc_booking columns %', v_n; end if;
  select count(*) into v_n from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_schedule_parse', 'fc_book_schedule_save', 'fc_pickup_check');
  if v_n <> 3 then raise exception 'fc-pickup-1 landing check failed: functions %', v_n; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_booking_for_shipment') <> 1 then raise exception 'fc-pickup-1 landing check failed: fc_booking_for_shipment count'; end if;
  select coalesce(p.proacl::text, '(null)') into v_acl from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fc_book_schedule_save';
  if v_acl <> '{postgres=X/postgres,service_role=X/postgres}' then raise exception 'fc-pickup-1 landing check failed: fc_book_schedule_save acl %', v_acl; end if;
  select coalesce(p.proacl::text, '(null)') into v_acl from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fc_booking_for_shipment';
  if v_acl <> '{postgres=X/postgres,authenticated=X/postgres}' then raise exception 'fc-pickup-1 landing check failed: fc_booking_for_shipment acl %', v_acl; end if;
  foreach v_md5 in array array['fc_schedule_parse', 'fc_pickup_check'] loop
    select coalesce(p.proacl::text, '(null)') into v_acl from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = v_md5;
    if v_acl <> '{postgres=X/postgres}' then raise exception 'fc-pickup-1 landing check failed: % acl %', v_md5, v_acl; end if;
  end loop;
  select relacl::text into v_acl from pg_class where oid = 'public.fc_booking'::regclass;
  if v_acl <> '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres}' then raise exception 'fc-pickup-1 landing check failed: fc_booking acl %', v_acl; end if;
  select md5(p.prosrc) into v_md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fc_book_save';
  if v_md5 <> 'e6a0f6a0c836a5304ff2b8e5f5f1fc1c' then raise exception 'fc-pickup-1 landing check failed: fc_book_save touched %', v_md5; end if;
  select md5(p.prosrc) into v_md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fc_book_cancel_save';
  if v_md5 <> '938df0b73e64df3b09ab0d0b3dc1e62a' then raise exception 'fc-pickup-1 landing check failed: fc_book_cancel_save touched %', v_md5; end if;
  if (select (public.fc_schedule_parse('{"schedule": {"status": " Done ", "pickup_confirmation_number": " 123 "}}'::jsonb))->>'status') <> 'done' then raise exception 'fc-pickup-1 landing check failed: parser'; end if;
end $$;
