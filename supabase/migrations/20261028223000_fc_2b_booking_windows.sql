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
-- fc-2b — Freightcom 예약 ② DB: 예약 이력 · 라벨 표 · 창구 다섯 (2026-10-28 · 판정 835 · 837 · 851 ~ 858 · 지시서 ~/asung/prompts/fc-2.md · Caleb 결정 854 ~ 859 · Claude Code 이견 4 · 5 · 6 · 9)
--   왜: 견적(fc-1) 다음 단계 — 고른 줄로 Freightcom 에 예약하고 추적번호 · 라벨을 IMS 에 남긴다 · 돈이 드는 쓰기라 DB 가 검사 · 기록을 맡고 EF(fc-2c)는 나른다
--   ① fc_booking(이견 4): 시도마다 한 행(attempt · unique_id = 발송 id · 2 차부터 <발송 id>-<attempt> · 실패 시도도 남는다) · status pending → booked | failed · booked → cancelled ·
--      보낸 몸(request · pickup) · 받은 원문(response · labels) · 추적(primary · 목록 · url · bol · 확인번호) · ⭐ so_written = SO 에 쓴 값과 그 전 값(855 취소 때 「아직 같을 때만」 되돌리는 열쇠)
--   ② fc_label(858): 받아 둔 라벨 PDF 한 장 = 한 행 · 버킷 documents · 접두 fc_label/ · a6 · letter PDF 만(zpl 저장 안 함 · 851) · 예약마다 size × padded 하나(다시 받으면 덮음) · 창구 fc_label_add(service_role) · fc_label_get(읽기 · EF 가 서명 URL)
--   ③ fc_shipment.booking_id = 현재(마지막) 시도 · status booked 는 fc-1a 자리 그대로
--   ④ 창구: fc_book_gate(853 · 854 freight_booking + 그 창고 · definer 속) ·
--      fc_book_prepare(사용자 · 검사: selected · 고른 줄 · valid_until · units_changed · SO 출고 전 · 계정 · 852 픽업 — 정기 픽업이면 pre_scheduled_pickup true · 아니면 날짜 · 준비 ~ 마감(closes_at) · 팔렛(LTL)은 dispatch_details · 창고 시간대 857 · 마감 지났으면 다음 날 + 알림 · p_commit = pending 행 · 10 분 넘은 pending 은 failed 로 비켜 둔다) ·
--      fc_book_save(service_role · 응답 원문 → booked · 855 발송에 든 SO 모두의 carrier_id · carrier · tracking_number(목록을 쉼표로) 직접 · 실패(400 booking carrier)도 failed 행으로 · 사실이 먼저 — 응답이 왔으면 발송이 그 사이 바뀌었어도 기록하고 알린다) ·
--      fc_book_cancel_prepare(사용자 · 853 · booked 만 · SO 가 shipped 면 거부 · 실패 시도는 지울 것 없음) · fc_book_cancel_save(service_role · 856 fc_booking cancelled · fc_shipment 'selected' 로 · 855 SO 칸은 예약 때 쓴 값과 아직 같을 때만 그 전 값으로) ·
--      fc_booking_for_shipment(읽기 · 현재 시도 · 이력 · 라벨 — 화면이 for_so 옆에서 부른다 · for_so 는 무접촉)
--   짐작(fc-2c 실호출이 확인): pickup_details 의 날짜 · 시각 꼴 {date:{year,month,day}, ready_at:{hour,minute}, ready_until:{hour,minute}}(B 는 pre_scheduled 꼴만 실측) · dispatch_details 도 같은 꼴(B 실측) · payment_method_id 는 EF 가 채운다(값을 박지 않는다)
--   무접촉: fc_shipment_prepare · fc_quote_save · fc_quote_select · fc_shipment_for_so · so_finalize · so_header_update · 화면 · 운영 DB · 첫 문장 = guard-test-only.sql 바이트 복사
--   컷오버 날 지우기(cutover-delete.sql ③ · 같은 커밋): D + 2(fc_booking fc_label · d11) → 182 표 = D 85 · K 77 · R 20 · fc_shipment.booking_id ↔ fc_booking.shipment_id 는 둘 다 D(truncate 묶음) · 버킷 documents 의 fc_label/ 객체는 이 스크립트가 안 지운다(메모)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261028223000_fc_2b_booking_windows.sql && supabase migration repair --status applied 20261028223000 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback · 레포 루트에서 — fixtures 를 \copy 로 읽는다): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028223000_fc_2b_booking_windows.sql -f supabase/tests/fc_2b_check.sql  (안에서 fc_2a 사본 164)

-- ═══ 1) 표 ═══
create table public.fc_booking (
  id                     uuid primary key default gen_random_uuid(),
  shipment_id            uuid not null references public.fc_shipment (id),
  attempt                int  not null,
  unique_id              text not null,
  status                 text not null default 'pending',
  rate_id                uuid references public.fc_quote_rate (id),
  carrier_id             uuid references public.ref_carrier (id),
  service_id             text,
  account                text,
  pickup                 jsonb,
  request                jsonb,
  response               jsonb,
  error                  text,
  cancel_error           text,
  freightcom_shipment_id text,
  state                  text,
  transaction_number     text,
  tracking_number        text,
  tracking_numbers       text[] not null default '{}',
  tracking_url           text,
  bol_number             text,
  pickup_confirmation    text,
  labels                 jsonb,
  so_written             jsonb,
  requested_at           timestamptz not null default now(),
  requested_by           uuid references public.ims_staff (id),
  booked_at              timestamptz,
  failed_at              timestamptz,
  cancelled_at           timestamptz,
  cancelled_by           uuid references public.ims_staff (id),
  constraint fc_booking_attempt_uq  unique (shipment_id, attempt),
  constraint fc_booking_unique_id_uq unique (unique_id),
  constraint fc_booking_status_ck   check (status in ('pending', 'booked', 'failed', 'cancelled')),
  constraint fc_booking_cancel_ck   check ((status = 'cancelled') = (cancelled_at is not null)),
  constraint fc_booking_booked_ck   check (status not in ('booked', 'cancelled') or (freightcom_shipment_id is not null and booked_at is not null)),
  constraint fc_booking_failed_ck   check ((status = 'failed') = (failed_at is not null))
);
create index fc_booking_shipment_idx on public.fc_booking (shipment_id, attempt desc);
comment on table public.fc_booking is 'fc-2b 이견 4: Freightcom 예약 시도 한 번 = 한 행 — attempt · unique_id(발송 id · 2 차부터 <발송 id>-<attempt> · 677 정정의 「발송 id 가 바탕」) · pending(prepare) → booked | failed(save) · booked → cancelled(cancel_save) · request = 보낸 몸(payment_method_id 는 EF 가 채운 뒤 그대로 들어온다) · response = GET /shipment/{id} 원문 · labels = 받은 목록 원문 · so_written = SO 에 쓴 값 + 그 전 값(855) · 400 booking carrier 같은 실패 시도도 남는다(Freightcom 쪽에는 서지 않는다 · DELETE 403) · 컷오버 D';
alter table public.fc_shipment add column booking_id uuid references public.fc_booking (id);
comment on column public.fc_shipment.booking_id is 'fc-2b: 현재(마지막) 예약 시도 — status booked 면 그 시도가 booked · 취소 뒤 selected 로 돌아가도 마지막 시도를 가리킨다(이력은 fc_booking)';

create table public.fc_label (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid not null references public.fc_booking (id),
  shipment_id uuid not null references public.fc_shipment (id),
  size        text not null,
  format      text not null default 'pdf',
  padded      boolean not null default false,
  path        text not null,
  bytes       int not null,
  sha256      text not null,
  pages       int,
  source_url  text,
  fetched_at  timestamptz not null default now(),
  fetched_by  uuid references public.ims_staff (id),
  constraint fc_label_size_ck   check (size in ('a6', 'letter')),
  constraint fc_label_format_ck check (format = 'pdf'),
  constraint fc_label_one_uq    unique (booking_id, size, padded),
  constraint fc_label_path_uq   unique (path),
  constraint fc_label_path_ck   check (path ~ '^fc_label/[A-Za-z0-9._-]+\.pdf$'),
  constraint fc_label_bytes_ck  check (bytes > 0 and bytes <= 10485760),
  constraint fc_label_sha_ck    check (sha256 ~ '^[0-9a-f]{64}$'),
  constraint fc_label_pages_ck  check (pages is null or pages > 0)
);
create index fc_label_shipment_idx on public.fc_label (shipment_id);
comment on table public.fc_label is 'fc-2b 판정 851 · 858: 받아 둔 라벨 PDF 한 장 = 한 행 — 비공개 버킷 documents 의 fc_label/<발송>-<시도>-<size>[-padded].pdf · a6(4×6 라벨 프린터) · letter(일반 프린터 · 팔렛은 BOL+라벨 한 장) · zpl 은 저장 안 함 · 예약마다 size × padded 하나(다시 받으면 덮는다 — Freightcom url 만료 대비) · 직원은 fc_label_get → EF 가 서명 URL · doc_file 과 따로(판 없음 · 이견 3) · 컷오버 D(버킷 객체는 따로)';

do $$ declare t text; begin
  foreach t in array array['fc_booking', 'fc_label'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_select', t);
    execute format('revoke all on public.%I from public, anon, authenticated, service_role', t);
    execute format('grant select on public.%I to authenticated, service_role', t);
  end loop;
end $$;

-- ═══ 2) 문 · 조각 ═══
-- 853 · 854: freight_booking(admin · supervisor 는 역할로) + 그 창고(ims_can_warehouse) · definer 속(실행권 없음) · 견적 · 고르기의 fc_gate 와 별개
create function public.fc_book_gate(p_wh uuid, p_verb text default 'saved') returns void
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
begin
  if not public.ims_can_write('freight_booking') then
    raise exception 'You cannot book or cancel freight — ask an admin to add the ''freight_booking'' permission — nothing was %', p_verb;
  end if;
  if not public.ims_can_warehouse(p_wh) then raise exception 'This shipment belongs to another warehouse — nothing was %', p_verb; end if;
end;
$$;
revoke all on function public.fc_book_gate(uuid, text) from public, anon, authenticated, service_role;

create function public.fc_hm(p time) returns jsonb language sql immutable as $$ select case when p is null then null else jsonb_build_object('hour', extract(hour from p)::int, 'minute', extract(minute from p)::int) end; $$;
create function public.fc_ymd(p date) returns jsonb language sql immutable as $$ select case when p is null then null else jsonb_build_object('year', extract(year from p)::int, 'month', extract(month from p)::int, 'day', extract(day from p)::int) end; $$;
revoke all on function public.fc_hm(time) from public, anon, authenticated, service_role;
revoke all on function public.fc_ymd(date) from public, anon, authenticated, service_role;

-- ═══ 3) fc_book_prepare — 검사 → 예약 몸 · pending 행 ═══
create function public.fc_book_prepare(p_shipment_id uuid, p_pickup jsonb default '{}'::jsonb, p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_f       public.fc_shipment%rowtype;
  v_r       public.fc_quote_rate%rowtype;
  v_wh      public.ref_warehouse%rowtype;
  v_pk      public.ref_carrier_pickup%rowtype;
  v_staff   uuid;
  v_units   jsonb;
  v_sos     uuid[];
  v_nums    text[];
  v_bad     text;
  v_tz      text;
  v_local   timestamp;
  v_today   date;
  v_ship    date;
  v_date    date;
  v_at      time;
  v_until   time;
  v_regular boolean;
  v_past    boolean;
  v_warn    text[] := '{}';
  v_ev      jsonb;                                                                      -- 852: 이 줄의 마감 — 예약 순간 다시 센다(Freightcom 진짜 값 → 지금의 ref_carrier_pickup)
  v_attempt int;
  v_uid     text;
  v_bid     uuid;
  v_pend    public.fc_booking%rowtype;
  v_details jsonb;
  v_pickup  jsonb;
  v_req     jsonb;
begin
  if p_pickup is null or jsonb_typeof(p_pickup) <> 'object' then raise exception 'p_pickup must be a JSON object — nothing was saved'; end if;
  select * into v_f from public.fc_shipment f where f.id = p_shipment_id for update;
  if not found then raise exception 'Shipment % not found — nothing was saved', p_shipment_id; end if;
  perform public.fc_book_gate(v_f.origin_warehouse_id, 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  -- ① 상태 · 고른 줄
  if v_f.status = 'booked' then raise exception 'This shipment is already booked — cancel the booking first — nothing was saved'; end if;
  if v_f.status = 'cancelled' then raise exception 'This shipment was replaced — quote the orders again — nothing was saved'; end if;
  if v_f.status <> 'selected' or v_f.selected_rate_id is null then raise exception 'Choose a rate first — nothing was saved'; end if;
  if nullif(btrim(v_f.freightcom_account), '') is null then raise exception 'This shipment has no Freightcom account (quote again after setting the warehouse account) — nothing was saved'; end if;
  select * into v_r from public.fc_quote_rate r where r.id = v_f.selected_rate_id;
  if v_r.carrier_id is null then raise exception 'Carrier "%" is not on the IMS carrier list — nothing was saved', v_r.carrier_name; end if;
  select * into v_wh from public.ref_warehouse w where w.id = v_f.origin_warehouse_id;
  v_tz    := coalesce(v_wh.timezone, 'America/Toronto');
  v_local := now() at time zone v_tz;
  v_today := v_local::date;
  if v_r.valid_until is not null and v_r.valid_until < v_today then raise exception 'The quote expired on % — quote again — nothing was saved', v_r.valid_until; end if;
  -- ② SO · 유닛
  select array_agg(l.so_id order by s.created_at, s.so_number), array_agg(s.so_number order by s.created_at, s.so_number) into v_sos, v_nums
    from public.fc_shipment_so l join public.so s on s.id = l.so_id where l.shipment_id = v_f.id and l.live;
  select string_agg(s.so_number || ' (' || s.status || ')', ', ') into v_bad from public.so s where s.id = any (v_sos) and s.status not in ('picking', 'packed');
  if v_bad is not null then raise exception 'Orders % are not waiting to ship — nothing was saved', v_bad; end if;
  v_units := public.fc_units_snapshot(v_sos);
  if v_units <> v_f.units then raise exception 'The boxes or pallets changed since this quote — quote again — nothing was saved'; end if;
  -- ③ 852 픽업 — 정기 픽업 · 마감 · 날짜 · 준비 ~ 마감(closes_at) · 창고 시간대
  select * into v_pk from public.ref_carrier_pickup k where k.carrier_id = v_r.carrier_id and k.warehouse_id = v_f.origin_warehouse_id;
  v_regular := coalesce(v_pk.regular_pickup, false);
  v_ev := public.fc_cutoff_eval(v_f.origin_warehouse_id, v_r.carrier_id, v_r.raw->>'carrier_cut_off_time', v_today, now());   -- 견적 때 저장한 cutoff 가 아니라 지금 값(Settings 를 고친 뒤 예약하면 그 값)
  v_ship := nullif(btrim(v_f.options->>'ship_date'), '')::date;
  if nullif(btrim(p_pickup->>'date'), '') is not null then
    v_date := (p_pickup->>'date')::date;
    if v_date < v_today then raise exception 'Pickup date % has passed (today at the warehouse is %) — nothing was saved', v_date, v_today; end if;
  else
    v_date := greatest(coalesce(v_ship, v_today), v_today);
    if v_date = v_today and (v_ev->>'past_cutoff')::boolean then
      v_date := v_today + 1;
      v_warn := array_append(v_warn, format('past_cutoff:%s — %s cutoff %s has passed · pickup moved to %s', v_ev->>'cutoff', v_r.carrier_name, v_ev->>'cutoff', v_date));
    end if;
    if v_date = v_today and v_wh.closes_at is not null and v_local::time >= v_wh.closes_at then
      v_date := v_today + 1;
      v_warn := array_append(v_warn, format('closed:%s — the warehouse closed at %s · pickup moved to %s', to_char(v_wh.closes_at, 'HH24:MI'), to_char(v_wh.closes_at, 'HH24:MI'), v_date));
    end if;
  end if;
  if nullif(btrim(p_pickup->>'ready_at'), '') is not null then
    if not btrim(p_pickup->>'ready_at') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'ready_at "%" must be a time like 10:30 — nothing was saved', p_pickup->>'ready_at'; end if;
    v_at := btrim(p_pickup->>'ready_at')::time;
  else
    v_at := case when v_date = v_today then date_trunc('minute', v_local)::time + interval '1 minute' else time '09:00' end;
  end if;
  if nullif(btrim(p_pickup->>'ready_until'), '') is not null then
    if not btrim(p_pickup->>'ready_until') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'ready_until "%" must be a time like 17:00 — nothing was saved', p_pickup->>'ready_until'; end if;
    v_until := btrim(p_pickup->>'ready_until')::time;
  else
    v_until := v_wh.closes_at;
  end if;
  if not (v_regular and v_f.packaging_type = 'package') then                                            -- 정기 픽업 상자만 시간이 필요 없다(pre_scheduled) · 팔렛은 늘 dispatch_details
    if v_until is null then raise exception 'Set the closing time of % (Settings → Warehouses) or give ready_until — nothing was saved', v_wh.name; end if;
    if v_at >= v_until then raise exception 'Pickup window % ~ % is empty — nothing was saved', to_char(v_at, 'HH24:MI'), to_char(v_until, 'HH24:MI'); end if;
  end if;
  v_pickup := jsonb_build_object('regular_pickup', v_regular, 'date', v_date, 'ready_at', to_char(v_at, 'HH24:MI'), 'ready_until', to_char(v_until, 'HH24:MI'),
                                 'cutoff', v_ev->>'cutoff', 'cutoff_source', v_ev->>'cutoff_source', 'timezone', v_tz, 'local_now', to_char(v_local, 'YYYY-MM-DD HH24:MI'), 'ship_date', v_ship);
  -- ④ 시도 번호 · unique_id · 걸린 pending(10 분 넘으면 failed 로 비켜 둔다 · 아니면 거부)
  select * into v_pend from public.fc_booking b where b.shipment_id = v_f.id and b.status = 'pending' order by b.attempt desc limit 1;
  if v_pend.id is not null then
    if v_pend.requested_at > now() - interval '10 minutes' then raise exception 'A booking attempt (#%) is still in progress — use Check again or wait a few minutes — nothing was saved', v_pend.attempt; end if;
    if p_commit then update public.fc_booking set status = 'failed', failed_at = now(), error = 'abandoned — no answer recorded within 10 minutes' where id = v_pend.id; end if;
    v_warn := array_append(v_warn, format('abandoned:%s — attempt #%s had no answer and was set aside', v_pend.attempt, v_pend.attempt));
  end if;
  select coalesce(max(b.attempt), 0) + 1 into v_attempt from public.fc_booking b where b.shipment_id = v_f.id;
  v_uid := case when v_attempt = 1 then v_f.id::text else v_f.id::text || '-' || v_attempt end;
  -- ⑤ 몸 — 견적 때 details(origin · destination 에 연락처가 이미 든다 · fc-1a) + 출고일 = 픽업일 · pickup_details | dispatch_details · payment_method_id 는 EF
  v_details := jsonb_set(v_f.request->'details', '{expected_ship_date}', public.fc_ymd(v_date));
  v_req := jsonb_build_object('unique_id', v_uid, 'service_id', v_r.service_id, 'details', v_details);
  if v_f.packaging_type = 'pallet' then
    v_req := v_req || jsonb_build_object('dispatch_details', jsonb_build_object('date', public.fc_ymd(v_date), 'ready_at', public.fc_hm(v_at), 'ready_until', public.fc_hm(v_until)));
  elsif v_regular then
    v_req := v_req || jsonb_build_object('pickup_details', jsonb_build_object('pre_scheduled_pickup', true));
  else
    v_req := v_req || jsonb_build_object('pickup_details', jsonb_build_object('pre_scheduled_pickup', false, 'date', public.fc_ymd(v_date), 'ready_at', public.fc_hm(v_at), 'ready_until', public.fc_hm(v_until)));
  end if;
  if p_commit then
    insert into public.fc_booking (shipment_id, attempt, unique_id, status, rate_id, carrier_id, service_id, account, pickup, request, requested_by)
    values (v_f.id, v_attempt, v_uid, 'pending', v_r.id, v_r.carrier_id, v_r.service_id, v_f.freightcom_account, v_pickup, v_req, v_staff) returning id into v_bid;
    update public.fc_shipment f set booking_id = v_bid, updated_by = v_staff where f.id = v_f.id;
  end if;
  return jsonb_build_object('shipment_id', v_f.id, 'booking_id', v_bid, 'attempt', v_attempt, 'unique_id', v_uid, 'account', v_f.freightcom_account, 'packaging_type', v_f.packaging_type,
                            'rate_id', v_r.id, 'carrier_id', v_r.carrier_id, 'carrier_name', v_r.carrier_name, 'service_id', v_r.service_id, 'service_name', v_r.service_name, 'customer_charge_cents', v_r.customer_charge_cents,
                            'charge_so_id', v_f.charge_so_id, 'so_ids', to_jsonb(v_sos), 'so_numbers', to_jsonb(v_nums), 'pickup', v_pickup, 'request', v_req, 'warnings', to_jsonb(v_warn), 'committed', p_commit);
end;
$$;
revoke all on function public.fc_book_prepare(uuid, jsonb, boolean) from public, anon, service_role;
grant execute on function public.fc_book_prepare(uuid, jsonb, boolean) to authenticated;
comment on function public.fc_book_prepare(uuid, jsonb, boolean) is 'fc-2b 판정 835 · 852 ~ 854: 예약 준비 — 문 freight_booking + 그 창고 · 검사(selected · 고른 줄 · 운송사 짝 · 계정 · valid_until · SO 출고 전 · 유닛 무변) · 852 픽업: 정기 픽업 상자 = pre_scheduled_pickup true · 아니면 날짜 · 준비 ~ closes_at · 팔렛 = dispatch_details · 창고 시간대(857) · 마감 지남 · 문 닫힘이면 다음 날 + warnings · p_pickup {date?, ready_at?, ready_until?} · p_commit = fc_booking pending + fc_shipment.booking_id(10 분 넘은 pending 은 failed 로) · unique_id = 발송 id · 2 차부터 -<attempt> · payment_method_id 는 EF 가 채운다';

-- ═══ 4) fc_book_save — 응답 원문 → booked | failed · 855 SO 칸 ═══
create function public.fc_book_save(p_booking_id uuid, p_response jsonb, p_error text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_b      public.fc_booking%rowtype;
  v_f      public.fc_shipment%rowtype;
  v_s      jsonb;
  v_trk    text[];
  v_car    public.ref_carrier%rowtype;
  v_so     public.so%rowtype;
  v_wr     jsonb := '[]'::jsonb;
  v_warn   text[] := '{}';
  v_l      record;
begin
  if not public.doc_is_service() then raise exception 'fc_book_save is for the freight service only — nothing was saved'; end if;
  select * into v_b from public.fc_booking b where b.id = p_booking_id for update;
  if not found then raise exception 'Booking % not found — nothing was saved', p_booking_id; end if;
  select * into v_f from public.fc_shipment f where f.id = v_b.shipment_id for update;
  if v_b.status <> 'pending' then raise exception 'Booking #% is already % — nothing was saved', v_b.attempt, v_b.status; end if;
  if p_error is not null then
    update public.fc_booking set status = 'failed', failed_at = now(), error = left(p_error, 1000), response = p_response where id = v_b.id;
    return jsonb_build_object('booking_id', v_b.id, 'attempt', v_b.attempt, 'status', 'failed', 'error', left(p_error, 1000), 'shipment_status', v_f.status);
  end if;
  v_s := coalesce(p_response->'shipment', p_response);                                                                        -- 프로브 원문은 {shipment:{…}} 로 감싸였다 · 맨몸도 받는다
  if v_s is null or jsonb_typeof(v_s) <> 'object' or nullif(btrim(v_s->>'id'), '') is null then raise exception 'The booking answer has no shipment id — nothing was saved'; end if;
  if coalesce(v_s->>'state', '') = 'cancelled' then raise exception 'The booking answer says the shipment is cancelled — nothing was saved'; end if;
  select coalesce(array_agg(btrim(x) order by o), '{}') into v_trk from jsonb_array_elements_text(coalesce(nullif(v_s->'tracking_numbers', 'null'::jsonb), '[]'::jsonb)) with ordinality t(x, o) where btrim(x) <> '';
  if cardinality(v_trk) = 0 and nullif(btrim(v_s->>'primary_tracking_number'), '') is not null then v_trk := array[btrim(v_s->>'primary_tracking_number')]; end if;
  select * into v_car from public.ref_carrier c where c.id = v_b.carrier_id;
  -- 855: 발송에 든 SO 모두에 운송사 · 추적번호(목록을 쉼표로) · 그 전 값을 함께 남긴다 · 그 사이 shipped 가 된 SO 는 두고 알린다
  for v_so in select s.* from public.fc_shipment_so l join public.so s on s.id = l.so_id where l.shipment_id = v_f.id and l.live order by s.created_at, s.so_number loop
    if v_so.status not in ('picking', 'packed') then
      v_warn := array_append(v_warn, format('so_not_written:%s — order is %s · carrier and tracking left as they are', v_so.so_number, v_so.status));
      continue;
    end if;
    v_wr := v_wr || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number,
                                       'before', jsonb_build_object('carrier_id', v_so.carrier_id, 'carrier', v_so.carrier, 'tracking_number', v_so.tracking_number),
                                       'written', jsonb_build_object('carrier_id', v_b.carrier_id, 'carrier', v_car.name, 'tracking_number', nullif(array_to_string(v_trk, ', '), '')));
    update public.so s set carrier_id = v_b.carrier_id, carrier = v_car.name, tracking_number = nullif(array_to_string(v_trk, ', '), '') where s.id = v_so.id;
  end loop;
  if v_f.selected_rate_id is distinct from v_b.rate_id then
    v_warn := array_append(v_warn, 'rate_changed — the chosen rate changed while booking · set back to the booked rate');
    update public.fc_shipment set selected_rate_id = v_b.rate_id where id = v_f.id;
  end if;
  update public.fc_booking set status = 'booked', booked_at = now(), response = p_response, error = null,
         freightcom_shipment_id = btrim(v_s->>'id'), state = nullif(btrim(v_s->>'state'), ''), transaction_number = nullif(btrim(v_s->>'transaction_number'), ''),
         tracking_number = coalesce(nullif(btrim(v_s->>'primary_tracking_number'), ''), v_trk[1]), tracking_numbers = v_trk, tracking_url = nullif(btrim(v_s->>'tracking_url'), ''),
         bol_number = coalesce(nullif(btrim(v_s->>'bolnumber'), ''), nullif(btrim(v_s->>'bol_number'), '')), pickup_confirmation = nullif(btrim(v_s->>'pickup_confirmation_number'), ''),
         labels = coalesce(nullif(v_s->'labels', 'null'::jsonb), '[]'::jsonb), so_written = v_wr
   where id = v_b.id;
  update public.fc_shipment set status = 'booked', booking_id = v_b.id where id = v_f.id;
  select * into v_b from public.fc_booking where id = v_b.id;
  return jsonb_build_object('booking_id', v_b.id, 'attempt', v_b.attempt, 'status', 'booked', 'freightcom_shipment_id', v_b.freightcom_shipment_id, 'state', v_b.state, 'transaction_number', v_b.transaction_number,
                            'tracking_number', v_b.tracking_number, 'tracking_numbers', to_jsonb(v_b.tracking_numbers), 'tracking_url', v_b.tracking_url, 'bol_number', v_b.bol_number, 'pickup_confirmation', v_b.pickup_confirmation,
                            'labels', (select coalesce(jsonb_agg(jsonb_build_object('size', l->>'size', 'format', l->>'format', 'padded', coalesce((l->>'padded')::boolean, false))), '[]'::jsonb) from jsonb_array_elements(v_b.labels) l),
                            'orders_written', (select coalesce(jsonb_agg(w->>'so_number'), '[]'::jsonb) from jsonb_array_elements(v_wr) w), 'warnings', to_jsonb(v_warn));
end;
$$;
revoke all on function public.fc_book_save(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.fc_book_save(uuid, jsonb, text) to service_role;
comment on function public.fc_book_save(uuid, jsonb, text) is 'fc-2b 판정 837 · 855: 예약 결과 저장(EF service_role 만) — p_error 면 failed 행(400 booking carrier 도 남는다 · 발송은 selected 그대로) · 아니면 GET /shipment 원문({shipment:{…}} 또는 맨몸)에서 id · state · transaction · 추적(primary · 목록 · url) · bolnumber · 확인번호 · labels → booked · ⭐ 발송에 든 SO 모두의 carrier_id · carrier · tracking_number(목록을 쉼표로)를 직접 쓰고 그 전 값을 so_written 에(취소 때 되돌리는 열쇠) · shipped 가 된 SO 는 두고 warnings · 발송 booked · booking_id';

-- ═══ 5) 취소 두 단계 ═══
create function public.fc_book_cancel_prepare(p_shipment_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_f   public.fc_shipment%rowtype;
  v_b   public.fc_booking%rowtype;
  v_bad text;
begin
  select * into v_f from public.fc_shipment f where f.id = p_shipment_id;
  if not found then raise exception 'Shipment % not found — nothing was changed', p_shipment_id; end if;
  perform public.fc_book_gate(v_f.origin_warehouse_id, 'changed');
  if v_f.booking_id is not null then select * into v_b from public.fc_booking b where b.id = v_f.booking_id; end if;
  if v_b.id is null then raise exception 'This shipment has no booking — nothing was changed'; end if;
  if v_b.status = 'failed' then raise exception 'The last attempt (#%) failed — there is nothing to cancel at Freightcom — nothing was changed', v_b.attempt; end if;
  if v_b.status = 'pending' then raise exception 'Attempt #% is still in progress — use Check again first — nothing was changed', v_b.attempt; end if;
  if v_b.status <> 'booked' or v_f.status <> 'booked' then raise exception 'This shipment is % (booking %) — nothing to cancel — nothing was changed', v_f.status, v_b.status; end if;
  select string_agg(s.so_number, ', ') into v_bad from public.fc_shipment_so l join public.so s on s.id = l.so_id where l.shipment_id = v_f.id and l.live and s.status not in ('picking', 'packed');
  if v_bad is not null then raise exception 'Orders % have already shipped — the booking cannot be cancelled from IMS — nothing was changed', v_bad; end if;
  return jsonb_build_object('shipment_id', v_f.id, 'booking_id', v_b.id, 'attempt', v_b.attempt, 'account', v_b.account, 'freightcom_shipment_id', v_b.freightcom_shipment_id, 'tracking_number', v_b.tracking_number, 'carrier_name', (select c.name from public.ref_carrier c where c.id = v_b.carrier_id));
end;
$$;
revoke all on function public.fc_book_cancel_prepare(uuid) from public, anon, service_role;
grant execute on function public.fc_book_cancel_prepare(uuid) to authenticated;
comment on function public.fc_book_cancel_prepare(uuid) is 'fc-2b 판정 853 · 856: 취소 전 검사(쓰기 0) — 문 freight_booking + 그 창고 · booked 만(실패 시도는 Freightcom 에 서지 않아 지울 것 없음 · pending 은 Check again) · SO 가 shipped 면 거부 · EF 가 이것을 지난 뒤 DELETE /shipment/{id} → fc_book_cancel_save';

create function public.fc_book_cancel_save(p_booking_id uuid, p_response jsonb default null, p_error text default null) returns jsonb
  language plpgsql volatile security definer
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
  update public.fc_booking set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff, cancel_error = null, response = coalesce(p_response - 'cancelled_by', response) where id = v_b.id;
  update public.fc_shipment set status = 'selected' where id = v_f.id;                                                          -- 856: 고른 줄 그대로 · 다시 예약은 book_prepare(valid_until · units_changed 가 다시 본다)
  return jsonb_build_object('booking_id', v_b.id, 'attempt', v_b.attempt, 'status', 'cancelled', 'shipment_status', 'selected', 'orders_restored', to_jsonb(v_rest), 'orders_kept', to_jsonb(v_kept));
end;
$$;
revoke all on function public.fc_book_cancel_save(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.fc_book_cancel_save(uuid, jsonb, text) to service_role;
comment on function public.fc_book_cancel_save(uuid, jsonb, text) is 'fc-2b 판정 855 · 856: 취소 결과(EF service_role 만) — p_error 면 예약 그대로 + cancel_error · 아니면 fc_booking cancelled · fc_shipment selected(고른 줄 그대로) · SO 칸은 so_written 의 written 과 아직 같을 때만 before 로(사람이 바꾼 칸은 둔다 → orders_kept) · p_response.cancelled_by = 직원 id(EF 가 끼움)';

-- ═══ 6) 라벨 창구 · 읽기 ═══
create function public.fc_label_add(p jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_b public.fc_booking%rowtype; v_r public.fc_label%rowtype;
begin
  if not public.doc_is_service() then raise exception 'fc_label_add is for the freight service only — nothing was saved'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'p must be a JSON object — nothing was saved'; end if;
  select * into v_b from public.fc_booking b where b.id = nullif(p->>'booking_id', '')::uuid;
  if not found then raise exception 'Booking % not found — nothing was saved', p->>'booking_id'; end if;
  if v_b.status not in ('booked', 'cancelled') then raise exception 'Booking #% is % — labels come with a booked shipment — nothing was saved', v_b.attempt, v_b.status; end if;
  insert into public.fc_label (booking_id, shipment_id, size, padded, path, bytes, sha256, pages, source_url, fetched_by)
  values (v_b.id, v_b.shipment_id, p->>'size', coalesce((p->>'padded')::boolean, false), p->>'path', (p->>'bytes')::int, lower(p->>'sha256'), nullif(p->>'pages', '')::int, nullif(p->>'source_url', ''), nullif(p->>'fetched_by', '')::uuid)
  on conflict (booking_id, size, padded) do update set path = excluded.path, bytes = excluded.bytes, sha256 = excluded.sha256, pages = excluded.pages, source_url = excluded.source_url, fetched_at = now(), fetched_by = excluded.fetched_by
  returning * into v_r;
  return to_jsonb(v_r);
end;
$$;
revoke all on function public.fc_label_add(jsonb) from public, anon, authenticated;
grant execute on function public.fc_label_add(jsonb) to service_role;
comment on function public.fc_label_add(jsonb) is 'fc-2b 판정 858: 받아 둔 라벨 PDF 한 줄(EF service_role 만) — p {booking_id, size a6|letter, padded?, path fc_label/…pdf, bytes, sha256, pages?, source_url?, fetched_by?} · 예약마다 size × padded 하나(다시 받으면 덮는다) · 버킷 올리기는 EF';

create function public.fc_booking_for_shipment(p_shipment_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare v_f public.fc_shipment%rowtype;
begin
  select * into v_f from public.fc_shipment f where f.id = p_shipment_id;
  if not found then raise exception 'Shipment % not found', p_shipment_id; end if;
  if not (public.ims_can_view('sales') or public.ims_can_view('fulfillment') or public.ims_can_write('freight_booking')) then raise exception 'You cannot see freight bookings — ask an admin for the ''sales'', ''fulfillment'' or ''freight_booking'' permission'; end if;
  return jsonb_build_object('shipment_id', v_f.id, 'status', v_f.status, 'booking_id', v_f.booking_id, 'can_book', public.ims_can_write('freight_booking') and public.ims_can_warehouse(v_f.origin_warehouse_id),
    'current', (select to_jsonb(b) - 'request' - 'response' from public.fc_booking b where b.id = v_f.booking_id),
    'attempts', (select coalesce(jsonb_agg(jsonb_build_object('booking_id', b.id, 'attempt', b.attempt, 'unique_id', b.unique_id, 'status', b.status, 'service_id', b.service_id, 'tracking_number', b.tracking_number, 'error', b.error, 'requested_at', b.requested_at, 'booked_at', b.booked_at, 'cancelled_at', b.cancelled_at) order by b.attempt), '[]'::jsonb) from public.fc_booking b where b.shipment_id = v_f.id),
    'labels', (select coalesce(jsonb_agg(jsonb_build_object('label_id', l.id, 'booking_id', l.booking_id, 'size', l.size, 'format', l.format, 'padded', l.padded, 'path', l.path, 'bytes', l.bytes, 'pages', l.pages, 'fetched_at', l.fetched_at) order by l.size, l.padded), '[]'::jsonb) from public.fc_label l where l.booking_id = v_f.booking_id));
end;
$$;
revoke all on function public.fc_booking_for_shipment(uuid) from public, anon, service_role;
grant execute on function public.fc_booking_for_shipment(uuid) to authenticated;
comment on function public.fc_booking_for_shipment(uuid) is 'fc-2b: 한 발송의 예약 — 현재 시도(request · response 는 뺀다) · 시도 이력 · 현재 시도의 라벨 행 · can_book(853 + 창고) · 문 = sales · fulfillment(보기) 또는 freight_booking · 화면이 fc_shipment_for_so 옆에서 부른다(for_so 무접촉)';

create function public.fc_label_get(p_label_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare v_l public.fc_label%rowtype;
begin
  if not (public.doc_is_service() or public.ims_can_view('sales') or public.ims_can_view('fulfillment') or public.ims_can_write('freight_booking')) then raise exception 'You cannot open freight labels — ask an admin for the ''sales'', ''fulfillment'' or ''freight_booking'' permission'; end if;
  select * into v_l from public.fc_label l where l.id = p_label_id;
  if not found then raise exception 'Label % not found', p_label_id; end if;
  return to_jsonb(v_l);
end;
$$;
revoke all on function public.fc_label_get(uuid) from public, anon;
grant execute on function public.fc_label_get(uuid) to authenticated, service_role;
comment on function public.fc_label_get(uuid) is 'fc-2b 판정 858: 라벨 행 하나(path · bytes · sha256) — 문 = 서비스 또는 sales · fulfillment · freight_booking · EF label 이 이것으로 문을 확인한 뒤 documents 버킷 서명 URL 을 낸다(doc_file_get 선례)';

-- ═══ 7) 착지 검사 ═══
do $$
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'fc_shipment' and column_name = 'booking_id') <> 1 then raise exception 'fc-2b landing check failed: fc_shipment.booking_id'; end if;
  if (select string_agg(relacl::text, '|' order by relname) from pg_class where relname in ('fc_booking', 'fc_label') and relnamespace = 'public'::regnamespace) <> '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres}|{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres}' then raise exception 'fc-2b landing check failed: table acl'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_book_gate', 'fc_hm', 'fc_ymd', 'fc_book_prepare', 'fc_book_save', 'fc_book_cancel_prepare', 'fc_book_cancel_save', 'fc_label_add', 'fc_label_get', 'fc_booking_for_shipment')) <> 10 then raise exception 'fc-2b landing check failed: function count'; end if;
  if has_function_privilege('authenticated', 'public.fc_book_save(uuid, jsonb, text)', 'execute') or has_function_privilege('authenticated', 'public.fc_book_cancel_save(uuid, jsonb, text)', 'execute') or has_function_privilege('authenticated', 'public.fc_label_add(jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.fc_book_save(uuid, jsonb, text)', 'execute') or has_function_privilege('service_role', 'public.fc_book_prepare(uuid, jsonb, boolean)', 'execute') or not has_function_privilege('authenticated', 'public.fc_book_prepare(uuid, jsonb, boolean)', 'execute')
     or has_function_privilege('anon', 'public.fc_label_get(uuid)', 'execute') or has_function_privilege('authenticated', 'public.fc_book_gate(uuid, text)', 'execute') then
    raise exception 'fc-2b landing check failed: function acl';
  end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_for_so') <> '83b5e899f8fd8ebcbe5d654a20b20c4a' then raise exception 'fc-2b landing check failed: fc_shipment_for_so touched'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_quote_save') <> '750a0fbacaa37d2215112a9b8308d0ce' then raise exception 'fc-2b landing check failed: fc_quote_save touched'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_prepare') <> '2a2a0206f9f2b12320dd93f6467fa8fc' then raise exception 'fc-2b landing check failed: fc_shipment_prepare touched'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize') <> '70d4711f91b1ff0b3bb7067864383124' then raise exception 'fc-2b landing check failed: so_finalize touched'; end if;
  raise notice 'fc-2b landing OK — fc_booking · fc_label · fc_shipment.booking_id · windows 7 (prepare · save · cancel_prepare · cancel_save · label_add · label_get · for_shipment) · reissued 0';
end $$;
