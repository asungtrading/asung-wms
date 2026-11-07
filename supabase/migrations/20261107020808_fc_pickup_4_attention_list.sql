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
-- fc-pickup-4 — Action Centre 용 「픽업이 안 잡힌 예약」 목록 읽기 창구 (2026-11-06 · 지시서 ~/asung/prompts/fc-pickup-4.md · 판정 「A」 11-06 · Claude Code 이견 1 ~ 12 모두 승인)
--   왜: 예약됨 칸(상태 줄 · Check pickup)은 Ship & invoice · WMS Finalize 단계에만 그려져 출고(Shipped · Fulfilled) 뒤에는 운송사가 픽업을 거절해도 볼 화면이 없다 ⇒ Action Centre 에 목록(화면은 대화 Claude · 이 차수 밖)
--   ① fc_pickup_attention_list(p_warehouse_id default null) returns jsonb — definer · 첫 줄 문 = fc_booking_for_shipment 과 같다(sales 보기 ∨ fulfillment 보기 ∨ freight_booking 쓰기) · authenticated 만
--      대상 = booked ∧ 발송의 현재 시도(f.booking_id = b.id · booked 는 늘 현재 시도지만 뜻을 적는다 · 이견 4) ∧ fc_pickup_check(b).not_scheduled(판정은 그 함수 하나 · 화면 · 여기서 다시 짜지 않는다 — needed(상자 · 비정기)가 그 안에 있다 · 「읽은 적 없음」 은 15 분과 무관하게 든다 · 이견 3)
--      창(이견 1) = fc_pickup_poll_due ④ 와 같은 식 — now() < greatest(booked_at + 48 h, 픽업 날(request.pickup_details.date · 깨졌으면 null) + 2 일 00:00 America/Toronto) · ⚠️ 둘을 같이 고친다 · 「목록에 있다 = cron 이 아직 읽는다」
--      창고 두 겹(이견 5) = p_warehouse_id(Branch 고르기 · 모르는 id 는 거부) ∧ 행마다 ims_can_warehouse(origin) · 「확인함」 표시 칸 없음(이견 2 · 월요일 실사용 뒤)
--      행 = booking_id · shipment_id · attempt · booking_status · so_id · so_number(운임 SO · so.html?so=) · so_numbers(운임 SO 먼저 · 나머지 created_at · so_number) · customer_name · warehouse_id · warehouse · account · carrier_id · carrier · service_id ·
--          freightcom_shipment_id · tracking_number · pickup_date · ready_at · ready_until(fc_booking.pickup · 창고 시각) · booked_at · minutes_since_booked · schedule_status · schedule_error · schedule_checked_at · schedule_done_at · confirmation_mismatch · pending · not_scheduled · message(fc_pickup_check 그대로 · 평평하게) · window_until
--      정렬 = 픽업 날 오름(null 뒤) → booked_at → attempt · 봉투 {warehouse_id, warehouse, as_of, count, rows}(so_stock_short_list 꼴 · 하루 몇 건 · 1,000 행 캡 무관)
--   새 표 · 칸 · FK · cron 없음 · fc_pickup_check · fc_booking_for_shipment · fc_pickup_poll_due 무접촉(착지 md5) · 화면 · EF 무접촉 · 첫 문장 = guard-test-only.sql 바이트 복사
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261107020808_fc_pickup_4_attention_list.sql && supabase migration repair --status applied 20261107020808 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261107020808_fc_pickup_4_attention_list.sql -f supabase/tests/fc_pickup_4_check.sql

-- ═══ 1) 목록 창구 ═══
create function public.fc_pickup_attention_list(p_warehouse_id uuid default null) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_wh   text;
  v_rows jsonb;
  v_n    int;
begin
  if not (public.ims_can_view('sales') or public.ims_can_view('fulfillment') or public.ims_can_write('freight_booking')) then raise exception 'You cannot see freight bookings — ask an admin for the ''sales'', ''fulfillment'' or ''freight_booking'' permission'; end if;
  if p_warehouse_id is not null then
    select w.name into v_wh from public.ref_warehouse w where w.id = p_warehouse_id;
    if v_wh is null then raise exception 'Warehouse not found'; end if;
  end if;
  with c as (
    select b.id as booking_id, b.shipment_id, b.attempt, b.status as booking_status, b.account, b.carrier_id, b.service_id, b.freightcom_shipment_id, b.tracking_number,
           b.booked_at, b.schedule_done_at, b.pickup->>'ready_at' as ready_at, b.pickup->>'ready_until' as ready_until,
           f.charge_so_id as so_id, f.origin_warehouse_id as warehouse_id, f.customer_id,
           w.name as warehouse, cr.name as carrier,
           public.fc_pickup_check(b) as pc,
           (select make_date((b.request#>>'{pickup_details,date,year}')::int, (b.request#>>'{pickup_details,date,month}')::int, (b.request#>>'{pickup_details,date,day}')::int)   -- fc_pickup_poll_due ④ 와 같은 식(창 · 둘을 같이 고친다)
              where (b.request#>>'{pickup_details,date,year}') ~ '^\d{4}$' and (b.request#>>'{pickup_details,date,month}') ~ '^\d{1,2}$' and (b.request#>>'{pickup_details,date,day}') ~ '^\d{1,2}$'
                and (b.request#>>'{pickup_details,date,month}')::int between 1 and 12 and (b.request#>>'{pickup_details,date,day}')::int between 1 and 31) as pickup_date
      from public.fc_booking b
      join public.fc_shipment f on f.id = b.shipment_id
      join public.ref_warehouse w on w.id = f.origin_warehouse_id
      left join public.ref_carrier cr on cr.id = b.carrier_id
     where b.status = 'booked'
       and f.booking_id = b.id
       and (p_warehouse_id is null or f.origin_warehouse_id = p_warehouse_id)
       and public.ims_can_warehouse(f.origin_warehouse_id)
  ), w as (
    select c.*, greatest(c.booked_at + interval '48 hours', ((c.pickup_date + 2)::timestamp at time zone 'America/Toronto')) as window_until
      from c
     where coalesce((c.pc->>'not_scheduled')::boolean, false)
  ), r as (
    select w.*,
           (select s.so_number from public.so s where s.id = w.so_id) as so_number,
           (select coalesce(jsonb_agg(s.so_number order by (s.id <> w.so_id), s.created_at, s.so_number), '[]'::jsonb) from public.fc_shipment_so l join public.so s on s.id = l.so_id where l.shipment_id = w.shipment_id and l.live) as so_numbers,
           (select cu.name from public.customer cu where cu.id = w.customer_id) as customer_name
      from w
     where now() < w.window_until
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'booking_id', r.booking_id, 'shipment_id', r.shipment_id, 'attempt', r.attempt, 'booking_status', r.booking_status,
           'so_id', r.so_id, 'so_number', r.so_number, 'so_numbers', r.so_numbers, 'customer_name', r.customer_name,
           'warehouse_id', r.warehouse_id, 'warehouse', r.warehouse, 'account', r.account, 'carrier_id', r.carrier_id, 'carrier', r.carrier, 'service_id', r.service_id,
           'freightcom_shipment_id', r.freightcom_shipment_id, 'tracking_number', r.tracking_number,
           'pickup_date', r.pickup_date, 'ready_at', r.ready_at, 'ready_until', r.ready_until, 'booked_at', r.booked_at, 'minutes_since_booked', r.pc->'minutes_since_booked',
           'schedule_status', r.pc->'status', 'schedule_error', r.pc->'error', 'schedule_checked_at', r.pc->'checked_at', 'schedule_done_at', r.schedule_done_at,
           'confirmation_mismatch', r.pc->'confirmation_mismatch', 'pending', r.pc->'pending', 'not_scheduled', r.pc->'not_scheduled', 'message', r.pc->'message',
           'window_until', r.window_until) order by r.pickup_date nulls last, r.booked_at, r.attempt), '[]'::jsonb), count(*)
    into v_rows, v_n
    from r;
  return jsonb_build_object('warehouse_id', p_warehouse_id, 'warehouse', v_wh, 'as_of', now(), 'count', v_n, 'rows', v_rows);
end;
$$;
revoke all on function public.fc_pickup_attention_list(uuid) from public, anon, service_role;
grant execute on function public.fc_pickup_attention_list(uuid) to authenticated;
comment on function public.fc_pickup_attention_list(uuid) is 'fc-pickup-4 ①: Action Centre 「Pickups not scheduled」 목록 — booked · 발송의 현재 시도 · fc_pickup_check(b).not_scheduled(판정은 그 함수 하나) · 창 = fc_pickup_poll_due 와 같은 식(greatest(booked_at + 48 h, 픽업 날 + 2 일 00:00 Toronto) · 둘을 같이 고친다) · 문 = fc_booking_for_shipment 과 같다(sales · fulfillment 보기 ∨ freight_booking 쓰기) · 창고 두 겹(p_warehouse_id ∧ ims_can_warehouse) · 정렬 픽업 날(null 뒤) → booked_at → attempt · 봉투 {warehouse_id, warehouse, as_of, count, rows} · 행에 so_number(so.html?so=) · so_numbers(운임 SO 먼저) · customer_name · 운송사 · 서비스 · Freightcom id · 추적 · 픽업 날 · ready_at · ready_until · fc_pickup_check 의 글 · window_until';

-- ═══ 2) 착지 검사 ═══
do $$
declare v_n int; v_acl text; v_md5 text;
begin
  select count(*) into v_n from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_pickup_attention_list';
  if v_n <> 1 then raise exception 'fc-pickup-4 landing check failed: fc_pickup_attention_list count %', v_n; end if;
  select coalesce(p.proacl::text, '(null)') into v_acl from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fc_pickup_attention_list';
  if v_acl <> '{postgres=X/postgres,authenticated=X/postgres}' then raise exception 'fc-pickup-4 landing check failed: fc_pickup_attention_list acl %', v_acl; end if;
  select md5(p.prosrc) into v_md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fc_pickup_check';
  if v_md5 <> 'b3a17787b3585d37712930e9315bc300' then raise exception 'fc-pickup-4 landing check failed: fc_pickup_check touched %', v_md5; end if;
  select md5(p.prosrc) into v_md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fc_booking_for_shipment';
  if v_md5 <> '7413429f0b0e31d04a6e926042d6e6cf' then raise exception 'fc-pickup-4 landing check failed: fc_booking_for_shipment touched %', v_md5; end if;
  select md5(p.prosrc) into v_md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fc_pickup_poll_due';
  if v_md5 <> '8d3038d6f72ae14cc255a7e3a6ab226f' then raise exception 'fc-pickup-4 landing check failed: fc_pickup_poll_due touched %', v_md5; end if;
end $$;
