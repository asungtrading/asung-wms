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
-- fc-track-4 — Freightcom 쉽먼트 보드 창구 · 돈 보는 문 · 열려 있던 fc_ 표 일곱 닫기 (2026-11-10 밤 토론토 · 지시서 ~/asung/prompts/fc-track-4.md · 판정 1167 · 1168 + Caleb 답 11-10)
--   왜: Freightcom 으로 예약한 쉽먼트를 한눈에 보는 목록이 없다(Caleb 11-10) — 픽업 · 운송 중 · 배송 · 문제 · 추가 요금 · 계정 한도를 Integrations 의 Freightcom 화면 하나에서 본다 · 화면은 표를 직접 읽지 않고 이 창구만 부른다(1168)
--   ① 문(1167 + 이견 1 · 2):
--      상태 문 = ims_can_view('sales') ∨ ims_can_view('fulfillment') ∨ ims_can_write('freight_booking') (fc_booking_for_shipment 와 같다) ∨ 돈 문(⚠️ 이 차수에서 더한 것 — purchasing 쓰기만 있는 사람도 보드를 연다 · 실제 직원 중 해당자 0)
--      돈 문 = ims_can_write('freight_booking') ∨ ims_can_write('purchasing') (fc_finance_gate 와 같은 쓰기 기준 · purchasing:read 는 돈을 못 본다) — 아니면 money = null · accounts = [] · counts.extra · cancelled_billed = null
--      창고 경계 = ims_can_warehouse(origin_warehouse_id) — rows · counts · total 은 볼 수 있는 창고만 · detail 은 남의 창고면 거부 · accounts 는 그 계정을 쓰는 창고를 볼 수 있는 것만
--   ② fc_add_business_days(d, n)(속) — 주말을 건너뛴 n 영업일 뒤(공휴일은 세지 않는다 · **짐작** ⬜1)
--   ③ fc_board_row(b, charge, money)(속 · 한 곳) — 보드 한 줄: 예약 + 발송 + 손님 + SO + 상태 + 늦음 + 픽업 + 깃발 + 돈
--      moving = booked 이고 fc_state_kind = open · fc_cancelled = booked 인데 Freightcom state 가 cancelled(IMS 에서 인정 전) ·
--      exception = moving 인데 state 가 아는 글자(waiting-for-transit · in-transit · label-created · ready-for-shipping · picked-up · out-for-delivery)가 아님(**짐작** — 실물 0 건) ·
--      expected_by = 픽업 날(request 의 pickup_details.date · 팔렛은 dispatch_details.date · 없으면 예약일 토론토) + transit_time_days 영업일 · late = moving 이고 오늘(ims_today) > expected_by + 1 일(**짐작** ⬜1) ·
--      pickup.not_scheduled = moving 이고 fc_pickup_check.not_scheduled · flags = exception · late · fc_cancelled · pickup_not_scheduled (+ 돈 문만 extra · cancelled_billed) ·
--      money = {charge_state, booked_total, billed_total, extra_cents, currency, warnings} — ⚠️ 금액은 전부 센트 정수(fc_charge_check 그대로 · booked_total · billed_total 은 세금 포함 · extra_cents 는 세전 차이) ·
--      ⚠️ request · response · labels(Freightcom 라벨 원본 주소 · deferred 362) · schedule_response 는 싣지 않는다
--   ④ fc_board(from, to, warehouse_id, view, q, limit, offset) — 창(⬜4) = 예약일(토론토)이 from ~ to(기본 오늘 − 30 일 ~ 오늘) ∨ 배송이 안 끝난 것(moving · 날짜와 상관없이) · booked · cancelled 만(pending · failed 는 SO 화면의 attempts) ·
--      q = SO 번호 · 손님 이름 · 운송장 · 거래 번호(부분 · 대소문자 무시 · % _ 는 글자 그대로) · view = all | moving | problems | delivered | cancelled(cancelled = IMS 취소 ∨ fc_cancelled) ·
--      counts 는 창 + q 안에서(view 앞) · all = moving + delivered + cancelled · fc_charge_check 는 창 안 행에 · 돈 문 통과자에게만 · 한 번(offset 0 · ⬜2 — 실측 55 행 49 ms)
--   ⑤ fc_board_detail(booking_id) — {row(같은 꼴), events[{type, at, city, region, message}](fc_track_event · 최신 먼저), money(돈 문만): {charge(fc_charge_check 전체), documents[], lines[]}}
--   ⑥ 닫기(1168 + 이견 3) — fc_booking · fc_call_log · fc_label · fc_quote · fc_quote_rate · fc_shipment · fc_shipment_so: select 정책 drop + anon · authenticated 권한 0 · service_role 은 그대로(EF sbGet · fc_call_log 쓰기)
--      조사(11-10): 화면 · ims-*.js · ims-mcp · GAS 의 직접 읽기 0 · 뷰 0 · publication 0 · EF freightcom 의 직접 읽기는 service_role — deferred 564 · 362 닫힘
--   무접촉: 기존 fc_ 함수 49 개(착지 확인이 수를 본다) · EF · 화면 · cron · inv_config · 표의 칸
--   빠진 것(Caleb): 「다음 결제로 풀릴 금액」 은 넣지 않는다 — 모든 shipment-order-details 의 줄을 읽어야 한다(deferred 569) · IMS 밖 예약은 이번 밖(deferred 565)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261111042906_fc_track_4_board_money_gate_close_tables.sql && supabase migration repair --status applied 20261111042906 --db-url "$(cat ~/.asung-testdb-url)" --yes
--   시험(Claude Code · rollback · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111042906_fc_track_4_board_money_gate_close_tables.sql -f supabase/tests/fc_track_4_check.sql

-- ═══ 1) 속 함수 — 영업일 ═══
create function public.fc_add_business_days(p_d date, p_n int) returns date
  language sql immutable
  set search_path = public, pg_temp
as $$
  select case
    when p_d is null or p_n is null or p_n > 60 then null
    when p_n <= 0 then p_d
    else (select max(x.d) from (select p_d + i as d from generate_series(1, p_n * 2 + 7) i where extract(isodow from p_d + i) < 6 order by i limit p_n) x)
  end;
$$;
revoke all on function public.fc_add_business_days(date, int) from public, anon, authenticated, service_role;
comment on function public.fc_add_business_days(date, int) is 'fc-track-4 ②(속): 주말(토 · 일)을 건너뛴 n 영업일 뒤의 날 — n ≤ 0 이면 그날 · n > 60 이나 null 이면 null · 공휴일은 세지 않는다(**짐작** — Freightcom transit_time_days 가 영업일인지 확인된 적 없다)';

-- ═══ 2) 속 함수 — 보드 한 줄(한 곳) ═══
create function public.fc_board_row(b public.fc_booking, p_charge jsonb, p_money boolean) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_f       public.fc_shipment%rowtype;
  v_kind    text := public.fc_state_kind(b.state);
  v_st      text := nullif(lower(btrim(coalesce(b.state, ''))), '');
  v_pc      jsonb := public.fc_pickup_check(b);
  v_rate    jsonb := b.response#>'{shipment,rate}';
  v_pickup  date := coalesce(public.fc_doc_date(b.request#>'{pickup_details,date}'), public.fc_doc_date(b.request#>'{dispatch_details,date}'));
  v_days    int;
  v_carrier text;
  v_service text;
  v_moving  boolean;
  v_fcx     boolean;
  v_exp     date;
  v_exc     boolean;
  v_late    boolean;
  v_pns     boolean;
  v_money   boolean := coalesce(p_money, false) and p_charge is not null;
  v_sos     jsonb;
begin
  select * into v_f from public.fc_shipment f where f.id = b.shipment_id;
  v_days := case when (v_rate->>'transit_time_days') ~ '^\d{1,3}$' then (v_rate->>'transit_time_days')::int end;
  v_carrier := nullif(btrim(v_rate->>'carrier_name'), '');
  v_service := nullif(btrim(v_rate->>'service_name'), '');
  if (v_days is null or v_carrier is null or v_service is null) and b.rate_id is not null then          -- IMS 취소가 response 를 덮은 예약(deferred 475) — 고른 견적 줄에서
    select coalesce(v_days, q.transit_days::int), coalesce(v_carrier, q.carrier_name), coalesce(v_service, q.service_name) into v_days, v_carrier, v_service from public.fc_quote_rate q where q.id = b.rate_id;
  end if;
  if v_carrier is null and b.carrier_id is not null then select c.name into v_carrier from public.ref_carrier c where c.id = b.carrier_id; end if;
  v_service := coalesce(v_service, b.service_id);
  v_moving := b.status = 'booked' and v_kind = 'open';
  v_fcx := b.status = 'booked' and v_kind = 'cancelled';
  v_exp := public.fc_add_business_days(coalesce(v_pickup, (b.booked_at at time zone 'America/Toronto')::date), v_days);
  v_exc := v_moving and v_st is not null and v_st not in ('waiting-for-transit', 'in-transit', 'label-created', 'ready-for-shipping', 'picked-up', 'out-for-delivery');
  v_late := v_moving and v_exp is not null and public.ims_today() > v_exp + 1;
  v_pns := v_moving and coalesce((v_pc->>'not_scheduled')::boolean, false);
  select coalesce(jsonb_agg(s.so_number order by (s.id <> v_f.charge_so_id), s.created_at, s.so_number), '[]'::jsonb) into v_sos
    from public.fc_shipment_so l join public.so s on s.id = l.so_id
   where l.shipment_id = b.shipment_id and (l.live or not exists (select 1 from public.fc_shipment_so l2 where l2.shipment_id = b.shipment_id and l2.live));
  return jsonb_build_object(
           'booking_id', b.id, 'shipment_id', b.shipment_id, 'attempt', b.attempt, 'status', b.status, 'cancel_source', b.cancel_source, 'cancel_note', b.cancel_note, 'cancelled_at', b.cancelled_at,
           'account', b.account, 'transaction_number', nullif(btrim(b.transaction_number), ''),
           'warehouse_id', v_f.origin_warehouse_id, 'warehouse_name', (select w.name from public.ref_warehouse w where w.id = v_f.origin_warehouse_id),
           'booked_at', b.booked_at, 'pickup_date', v_pickup,
           'so_numbers', v_sos,
           'charge_so_id', v_f.charge_so_id, 'charge_so_number', (select s.so_number from public.so s where s.id = v_f.charge_so_id),
           'customer_id', v_f.customer_id, 'customer_name', (select cu.name from public.customer cu where cu.id = v_f.customer_id),
           'carrier_name', v_carrier, 'service_name', v_service,
           'tracking_number', b.tracking_number, 'tracking_numbers', to_jsonb(b.tracking_numbers), 'tracking_url', b.tracking_url,
           'state', b.state, 'state_kind', v_kind, 'state_checked_at', b.state_checked_at, 'delivered_at', b.delivered_at, 'track_last', b.track_last,
           'transit_days', v_days, 'expected_by', v_exp, 'late', v_late, 'moving', v_moving, 'exception', v_exc,
           'pickup', jsonb_build_object('needed', v_pc->'needed', 'not_scheduled', v_pns, 'confirmation', b.pickup_confirmation, 'message', v_pc->'message'),
           'fc_cancelled', v_fcx,
           'flags', to_jsonb(array_remove(array[
                      case when v_exc then 'exception' end, case when v_late then 'late' end, case when v_fcx then 'fc_cancelled' end, case when v_pns then 'pickup_not_scheduled' end,
                      case when v_money and p_charge->>'state' = 'extra' then 'extra' end, case when v_money and p_charge->>'state' = 'cancelled_billed' then 'cancelled_billed' end], null)),
           'money', case when v_money then
                      jsonb_build_object('charge_state', p_charge->'state', 'booked_total', p_charge->'booked_total', 'billed_total', p_charge->'billed_total', 'extra_cents', p_charge->'extra_cents',
                                         'currency', p_charge->'currency', 'warnings', coalesce(p_charge->'warnings', '[]'::jsonb)) end);
end;
$$;
revoke all on function public.fc_board_row(public.fc_booking, jsonb, boolean) from public, anon, authenticated, service_role;
comment on function public.fc_board_row(public.fc_booking, jsonb, boolean) is 'fc-track-4 ③(속 · 한 곳 · 아무도 직접 못 부른다): 보드 한 줄 — 예약 + 발송 + 손님 + SO 번호 + 상태(state_kind · moving · fc_cancelled · exception **짐작**) + 늦음(expected_by = 픽업 날 또는 예약일 + transit 영업일 · late = 오늘 > expected_by + 1 일 **짐작**) + 픽업(fc_pickup_check) + flags + money(p_money 이고 p_charge 가 있을 때만 · 센트 정수 · booked_total · billed_total 은 세금 포함 · extra_cents 는 세전 차이) · request · response · labels · schedule_response 는 싣지 않는다(deferred 362)';

-- ═══ 3) 보드(1167) ═══
create function public.fc_board(p_from date default null, p_to date default null, p_warehouse_id uuid default null, p_view text default 'all', p_q text default null, p_limit int default 50, p_offset int default 0)
  returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_money    boolean := public.ims_can_write('freight_booking') or public.ims_can_write('purchasing');
  v_view     text := lower(btrim(coalesce(p_view, 'all')));
  v_q        text := nullif(btrim(coalesce(p_q, '')), '');
  v_pat      text;
  v_to       date := coalesce(p_to, public.ims_today());
  v_from     date;
  v_limit    int := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset   int := greatest(coalesce(p_offset, 0), 0);
  v_wh       text;
  v_accounts jsonb := '[]'::jsonb;
  v_out      jsonb;
begin
  if not (public.ims_can_view('sales') or public.ims_can_view('fulfillment') or public.ims_can_write('freight_booking') or v_money) then
    raise exception 'You cannot see freight shipments — ask an admin for the ''sales'', ''fulfillment'' or ''freight_booking'' permission';
  end if;
  if v_view not in ('all', 'moving', 'problems', 'delivered', 'cancelled') then raise exception 'view must be one of all, moving, problems, delivered, cancelled'; end if;
  v_from := coalesce(p_from, v_to - 30);
  if v_from > v_to then raise exception 'from (%) must not be after to (%)', v_from, v_to; end if;
  if char_length(v_q) > 100 then raise exception 'Search text is too long (100 characters at most)'; end if;
  if p_warehouse_id is not null then
    select w.name into v_wh from public.ref_warehouse w where w.id = p_warehouse_id;
    if v_wh is null then raise exception 'Warehouse not found'; end if;
    if not public.ims_can_warehouse(p_warehouse_id) then raise exception 'You cannot see the freight shipments of % — it is outside your warehouse access', v_wh; end if;
  end if;
  if v_q is not null then v_pat := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%'; end if;
  if v_money then
    select coalesce(jsonb_agg(public.fc_finance_account_summary(a.acc) || jsonb_build_object('warehouses', a.whs) order by a.acc), '[]'::jsonb) into v_accounts
      from (select w.freightcom_account as acc, jsonb_agg(w.name order by w.name) as whs
              from public.ref_warehouse w
             where nullif(btrim(w.freightcom_account), '') is not null and public.ims_can_warehouse(w.id) and (p_warehouse_id is null or w.id = p_warehouse_id)
             group by w.freightcom_account) a;
  end if;
  with w0 as materialized (
    select b.id, b.booked_at, public.fc_board_row(b, case when v_money then public.fc_charge_check(b.id) end, v_money) as r
      from public.fc_booking b
      join public.fc_shipment f on f.id = b.shipment_id
     where b.status in ('booked', 'cancelled') and nullif(btrim(b.freightcom_shipment_id), '') is not null
       and (p_warehouse_id is null or f.origin_warehouse_id = p_warehouse_id)
       and public.ims_can_warehouse(f.origin_warehouse_id)
       and ((b.booked_at at time zone 'America/Toronto')::date between v_from and v_to or (b.status = 'booked' and public.fc_state_kind(b.state) = 'open'))
     offset 0
  ), w as materialized (
    select w0.* from w0
     where v_pat is null or w0.r->>'customer_name' ilike v_pat or w0.r->>'tracking_number' ilike v_pat or w0.r->>'transaction_number' ilike v_pat
        or exists (select 1 from jsonb_array_elements_text(w0.r->'so_numbers') e where e ilike v_pat)
        or exists (select 1 from jsonb_array_elements_text(w0.r->'tracking_numbers') e where e ilike v_pat)
  ), v as materialized (
    select w.* from w
     where case v_view
             when 'all' then true
             when 'moving' then (w.r->>'moving')::boolean
             when 'delivered' then w.r->>'status' = 'booked' and w.r->>'state_kind' = 'delivered'
             when 'cancelled' then w.r->>'status' = 'cancelled' or (w.r->>'fc_cancelled')::boolean
             else jsonb_array_length(w.r->'flags') > 0
           end
  )
  select jsonb_build_object(
           'as_of', now(), 'can_see_money', v_money, 'from', v_from, 'to', v_to, 'warehouse_id', p_warehouse_id, 'warehouse', v_wh, 'view', v_view, 'q', v_q, 'limit', v_limit, 'offset', v_offset,
           'accounts', v_accounts,
           'counts', (select jsonb_build_object(
                               'all', count(*),
                               'moving', count(*) filter (where (w.r->>'moving')::boolean),
                               'delivered', count(*) filter (where w.r->>'status' = 'booked' and w.r->>'state_kind' = 'delivered'),
                               'cancelled', count(*) filter (where w.r->>'status' = 'cancelled' or (w.r->>'fc_cancelled')::boolean),
                               'problems', count(*) filter (where jsonb_array_length(w.r->'flags') > 0),
                               'exception', count(*) filter (where w.r->'flags' ? 'exception'),
                               'late', count(*) filter (where w.r->'flags' ? 'late'),
                               'fc_cancelled', count(*) filter (where w.r->'flags' ? 'fc_cancelled'),
                               'pickup_not_scheduled', count(*) filter (where w.r->'flags' ? 'pickup_not_scheduled'),
                               'extra', case when v_money then count(*) filter (where w.r->'flags' ? 'extra') end,
                               'cancelled_billed', case when v_money then count(*) filter (where w.r->'flags' ? 'cancelled_billed') end)
                        from w),
           'total', (select count(*) from v),
           'rows', coalesce((select jsonb_agg(p.r order by p.booked_at desc, p.id) from (select v.* from v order by v.booked_at desc, v.id limit v_limit offset v_offset) p), '[]'::jsonb))
    into v_out;
  return v_out;
end;
$$;
revoke all on function public.fc_board(date, date, uuid, text, text, int, int) from public, anon;
grant execute on function public.fc_board(date, date, uuid, text, text, int, int) to authenticated;
comment on function public.fc_board(date, date, uuid, text, text, int, int) is 'fc-track-4 ④ · 판정 1167 · 1168: Freightcom 쉽먼트 보드(사용자 JWT · 읽기 · 화면은 이 창구만) — 상태 문 = sales 보기 ∨ fulfillment 보기 ∨ freight_booking 쓰기 ∨ 돈 문 · 돈 문 = freight_booking 쓰기 ∨ purchasing 쓰기(아니면 money null · accounts [] · counts.extra · cancelled_billed null) · 창고 경계 ims_can_warehouse · 창 = 예약일(토론토) from ~ to(기본 오늘 − 30 일 ~ 오늘) ∨ 배송 안 끝난 것 · booked · cancelled 만 · view all | moving | problems | delivered | cancelled · q = SO 번호 · 손님 · 운송장 · 거래 번호 · counts 는 창 + q 안(view 앞) · limit 1 ~ 200(기본 50) → {as_of, can_see_money, from, to, warehouse_id, warehouse, view, q, limit, offset, accounts[fc_finance_account_summary + warehouses], counts, total, rows[fc_board_row]} · 금액은 센트 정수';

-- ═══ 4) 보드 상세 ═══
create function public.fc_board_detail(p_booking_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_money  boolean := public.ims_can_write('freight_booking') or public.ims_can_write('purchasing');
  v_b      public.fc_booking%rowtype;
  v_wh     uuid;
  v_fc     text;
  v_tn     text;
  v_charge jsonb;
  v_m      jsonb;
begin
  if not (public.ims_can_view('sales') or public.ims_can_view('fulfillment') or public.ims_can_write('freight_booking') or v_money) then
    raise exception 'You cannot see freight shipments — ask an admin for the ''sales'', ''fulfillment'' or ''freight_booking'' permission';
  end if;
  select * into v_b from public.fc_booking b where b.id = p_booking_id;
  if not found then raise exception 'Booking % not found', p_booking_id; end if;
  select f.origin_warehouse_id into v_wh from public.fc_shipment f where f.id = v_b.shipment_id;
  if not public.ims_can_warehouse(v_wh) then raise exception 'This shipment belongs to another warehouse'; end if;
  v_fc := nullif(btrim(v_b.freightcom_shipment_id), '');
  v_tn := nullif(btrim(v_b.transaction_number), '');
  if v_money then
    v_charge := public.fc_charge_check(v_b.id);
    v_m := jsonb_build_object(
      'charge', v_charge,
      'documents', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'type', d.type, 'number', d.number, 'doc_date', d.doc_date, 'amount_cents', d.amount_cents, 'owing_cents', d.owing_cents) order by d.doc_date desc nulls last, d.id), '[]'::jsonb)
                      from public.fc_document d
                     where d.account = v_b.account
                       and ((d.type = 'shipment-order-details' and d.number = v_tn) or exists (select 1 from public.fc_document_line l where l.document_id = d.id and l.shipment_fc_id = v_fc))),
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('document_id', l.document_id, 'type', l.type, 'sub_type', l.sub_type, 'amount_cents', l.amount_cents, 'message', l.message) order by d.doc_date desc nulls last, l.document_id, l.type, l.sub_type nulls first, l.line_id), '[]'::jsonb)
                  from public.fc_document_line l join public.fc_document d on d.id = l.document_id
                 where d.account = v_b.account and l.shipment_fc_id = v_fc));
  end if;
  return jsonb_build_object(
    'booking_id', v_b.id, 'as_of', now(), 'can_see_money', v_money,
    'row', public.fc_board_row(v_b, v_charge, v_money),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('type', e.type, 'at', e.at, 'city', e.place->>'city', 'region', e.place->>'region', 'message', e.message) order by e.at desc, e.id desc), '[]'::jsonb)
                 from public.fc_track_event e where e.booking_id = v_b.id),
    'money', v_m);
end;
$$;
revoke all on function public.fc_board_detail(uuid) from public, anon;
grant execute on function public.fc_board_detail(uuid) to authenticated;
comment on function public.fc_board_detail(uuid) is 'fc-track-4 ⑤ · 판정 1167: 보드 상세(사용자 JWT · 읽기) — 문은 fc_board 와 같다 · 남의 창고면 거부 → {booking_id, as_of, can_see_money, row(fc_board_row), events[{type, at, city, region, message}](fc_track_event · 최신 먼저 · raw 는 싣지 않는다), money(돈 문만 · 아니면 null): {charge(fc_charge_check 전체), documents[{id, type, number, doc_date, amount_cents, owing_cents}], lines[{document_id, type, sub_type, amount_cents, message}]}} · 금액은 센트 정수';

-- ═══ 5) 닫기(1168) — 열려 있던 fc_ 표 일곱 ═══
drop policy fc_booking_select     on public.fc_booking;
drop policy fc_call_log_select    on public.fc_call_log;
drop policy fc_label_select       on public.fc_label;
drop policy fc_quote_select       on public.fc_quote;
drop policy fc_quote_rate_select  on public.fc_quote_rate;
drop policy fc_shipment_select    on public.fc_shipment;
drop policy fc_shipment_so_select on public.fc_shipment_so;
revoke all on table public.fc_booking, public.fc_call_log, public.fc_label, public.fc_quote, public.fc_quote_rate, public.fc_shipment, public.fc_shipment_so from public, anon, authenticated;

-- ═══ 6) 착지 확인 ═══
do $$
declare v_t text;
begin
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('fc_add_business_days', 'fc_board_row', 'fc_board', 'fc_board_detail')) <> 4 then
    raise exception 'fc-track-4 landing check failed: expected 4 new functions (one definition each)';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'fc\_%') <> 53 then raise exception 'fc-track-4 landing check failed: expected 53 fc_ functions (49 before + 4)'; end if;
  foreach v_t in array array['fc_booking', 'fc_call_log', 'fc_label', 'fc_quote', 'fc_quote_rate', 'fc_shipment', 'fc_shipment_so', 'fc_track_event', 'fc_document', 'fc_document_line', 'fc_balance'] loop
    if not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || v_t)::regclass) or exists (select 1 from pg_policy p where p.polrelid = ('public.' || v_t)::regclass)
       or has_table_privilege('authenticated', 'public.' || v_t, 'select') or has_table_privilege('anon', 'public.' || v_t, 'select') or not has_table_privilege('service_role', 'public.' || v_t, 'select') then
      raise exception 'fc-track-4 landing check failed: % must be closed (RLS on · no policy · no authenticated / anon select · service_role select kept)', v_t;
    end if;
  end loop;
  if not has_function_privilege('authenticated', 'public.fc_board(date, date, uuid, text, text, int, int)', 'execute') or not has_function_privilege('authenticated', 'public.fc_board_detail(uuid)', 'execute')
     or has_function_privilege('anon', 'public.fc_board(date, date, uuid, text, text, int, int)', 'execute') or has_function_privilege('authenticated', 'public.fc_board_row(public.fc_booking, jsonb, boolean)', 'execute') then
    raise exception 'fc-track-4 landing check failed: function privileges';
  end if;
end $$;
