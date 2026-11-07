-- fc-pickup-3 (2026-11-06 · 판정 1040 ~ 1042 · fc-ref-1 합침) — fc_book_prepare 재발행 하나(표 · 칸 · FK 무변 · EF 무접촉 · 몸은 그대로 지나간다)
--   실물: 11-06 토론토 비정기 상자 예약 9 건 전부 예약 직후 schedule error — UPS 「Missing or invalid ContactName」 7 · Purolator 「Sender Name is a mandatory field.」 2 ⇒ 픽업 몸에 연락처 칸이 빠졌다(H2 확정 · 직원이 사이트에서 손 요청)
--   문서(Customer API 2.11.0 PickupDetails): pre_scheduled_pickup(true 면 다른 칸 무시) · date · ready_at · ready_until · pickup_location(string · 설명 없음) · contact_name(string) · contact_phone_number($ref PhoneNumber {number, extension?} · "without any special characters")
--     details.reference_codes = array of string "Reference codes for the shipment." · 개수 · 길이 한도 없음
--   ① 1042 비정기 상자(pre_scheduled_pickup false)만: contact_name = ref_warehouse.contact_name(btrim) · contact_phone_number = {number: fc_phone(phone)} — origin 과 같은 출처(fc-1a) · 비거나 10 자리가 아니면 예약 거부(Settings → Warehouses → Edit 의 Contact · Phone)
--      정기 픽업({pre_scheduled_pickup:true}) · 팔렛(dispatch_details) 은 바이트 그대로 · pickup_location 은 보내지 않는다(이견 4 · 출처 칸 없음 · 문서 설명 없음)
--   ② 1040 details.reference_codes = [운임 SO(charge_so_id · fc_charge_so_set 으로 옮긴 것 포함), 같은 발송의 나머지 SO(created_at · so_number 순)] · 원소당 SO 번호 하나 · 견적 details 에 있던 값은 덮는다 · 운임 SO 가 발송의 live SO 에 없으면 created_at 순 + warnings charge_so_missing
--   ③ 1041 픽업 날 주말(토론토 · 에드먼턴 모두 토 · 일 출고 없음 · Caleb 11-06): 자동 갈래(ship_date · 오늘 · 마감 지남/문 닫힘의 +1)가 토 · 일이면 다음 월요일 + warnings weekend:<날> · 직원이 적은 p_pickup.date 가 주말이면 거부 · 공휴일은 이 차수 밖
--   원본 20261028223000_fc_2b_booking_windows.sql:144(DB prosrc md5 de3009d8 = 파일) 를 바이트 복사 + 더한 줄만(diff 는 커밋 메시지 · 검사 supabase/tests/fc_pickup_3_check.sql) · grant · revoke 는 replace 라 그대로 남는다
--   fc-pickup-2(20261105232000 · 번호는 Caleb 이 뒤로 바꾼다)와 무접촉 — 그 파일에 fc_book_prepare 0
create or replace function public.fc_book_prepare(p_shipment_id uuid, p_pickup jsonb default '{}'::jsonb, p_commit boolean default true) returns jsonb
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
  v_wk      date;                                                                       -- 1041: 자동 갈래가 고른 날이 토 · 일이면 다음 월요일로(창고는 주말 출고 없음 · Caleb 11-06)
  v_charge  text;                                                                       -- 1040: 운임 SO 번호 → details.reference_codes 맨 앞
  v_refs    text[];
  v_cname   text;                                                                       -- 1042: 비정기 상자 픽업의 연락처(origin 과 같은 출처 · ref_warehouse.contact_name · phone)
  v_cphone  text;
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
    if extract(isodow from v_date) in (6, 7) then raise exception 'Pickup date % is a % — the warehouse does not ship on weekends · pick a weekday or leave the date empty — nothing was saved', v_date, trim(to_char(v_date, 'Day')); end if;
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
    if extract(isodow from v_date) in (6, 7) then                                                        -- 1041: 금요일 마감 · 문 닫힘 뒤의 +1 · 주말 ship_date · 주말의 오늘 → 다음 월요일
      v_wk   := v_date;
      v_date := v_date + (8 - extract(isodow from v_date)::int);
      v_warn := array_append(v_warn, format('weekend:%s — %s is a %s · pickup moved to %s', v_wk, v_wk, trim(to_char(v_wk, 'Day')), v_date));
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
  if v_f.packaging_type = 'package' and not v_regular then                                              -- 1042: 비정기 상자만 — 픽업 몸에 contact_name · contact_phone_number(운송사가 요구 · 11-06 UPS ContactName · Purolator Sender Name) · 비면 거부
    v_cname  := nullif(btrim(v_wh.contact_name), '');
    v_cphone := public.fc_phone(v_wh.phone);
    if v_cname is null or v_cphone is null then
      raise exception 'Warehouse % has no pickup contact (%) — set Contact and Phone in Settings → Warehouses → Edit — nothing was saved', v_wh.name,
        concat_ws(' · ', case when v_cname is null then 'Contact is empty' end, case when v_cphone is null then 'Phone must be a 10-digit number' end);
    end if;
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
  select s.so_number into v_charge from public.so s where s.id = v_f.charge_so_id and s.id = any (v_sos);          -- 1040: reference_codes = [운임 SO, 나머지 created_at 순] · 운임 SO 가 발송에 없으면 created_at 순 + warning
  if v_charge is null then
    v_refs := v_nums;
    v_warn := array_append(v_warn, 'charge_so_missing — the freight-charge order is not on this shipment · reference codes in order-created order');
  else
    v_refs := array[v_charge] || array(select t.n from unnest(v_nums) with ordinality t(n, o) where t.n <> v_charge order by t.o);
  end if;
  v_details := jsonb_set(v_details, '{reference_codes}', to_jsonb(v_refs));
  v_req := jsonb_build_object('unique_id', v_uid, 'service_id', v_r.service_id, 'details', v_details);
  if v_f.packaging_type = 'pallet' then
    v_req := v_req || jsonb_build_object('dispatch_details', jsonb_build_object('date', public.fc_ymd(v_date), 'ready_at', public.fc_hm(v_at), 'ready_until', public.fc_hm(v_until)));
  elsif v_regular then
    v_req := v_req || jsonb_build_object('pickup_details', jsonb_build_object('pre_scheduled_pickup', true));
  else
    v_req := v_req || jsonb_build_object('pickup_details', jsonb_build_object('pre_scheduled_pickup', false, 'date', public.fc_ymd(v_date), 'ready_at', public.fc_hm(v_at), 'ready_until', public.fc_hm(v_until),
                                                                              'contact_name', v_cname, 'contact_phone_number', jsonb_build_object('number', v_cphone)));
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
comment on function public.fc_book_prepare(uuid, jsonb, boolean) is 'fc-2b 판정 835 · 852 ~ 854 · fc-pickup-3 판정 1040 ~ 1042(비정기 상자 pickup_details 에 contact_name · contact_phone_number{number} = ref_warehouse Contact · Phone · 비면 거부 · pickup_location 안 보냄 · details.reference_codes = [운임 SO, 나머지 created_at 순] · 운임 SO 없으면 created_at 순 + charge_so_missing · 자동 고른 픽업 날이 토 · 일이면 다음 월요일 + weekend warning · 직원이 적은 주말 날짜는 거부): 예약 준비 — 문 freight_booking + 그 창고 · 검사(selected · 고른 줄 · 운송사 짝 · 계정 · valid_until · SO 출고 전 · 유닛 무변) · 852 픽업: 정기 픽업 상자 = pre_scheduled_pickup true · 아니면 날짜 · 준비 ~ closes_at · 팔렛 = dispatch_details · 창고 시간대(857) · 마감 지남 · 문 닫힘이면 다음 날 + warnings · p_pickup {date?, ready_at?, ready_until?} · p_commit = fc_booking pending + fc_shipment.booking_id(10 분 넘은 pending 은 failed 로) · unique_id = 발송 id · 2 차부터 -<attempt> · payment_method_id 는 EF 가 채운다';
