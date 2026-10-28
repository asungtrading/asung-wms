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
-- fc-2a — Freightcom 예약 ① DB 바탕: 권한 853 · 픽업 설정 852 · 창고 시간대 857 · 마감 표시 (2026-10-28 · 판정 852 ~ 854 · 857 · 859 · 지시서 ~/asung/prompts/fc-2.md · Claude Code 이견 1 · 2 · 7 · 8 뒤 Caleb 결정)
--   왜: 예약(fc-2b) 창구가 「누가 예약하나」(853) 와 「언제 픽업하나」(852) 를 알아야 한다 — 둘은 예약 표 없이도 서고 견적 화면에 바로 보이므로 먼저 간다(나누는 안 2a → 2b → 2c → 2d)
--   ① 853 · 854 · 859 — ims_perm_catalog 재발행: screens.freight_booking(room ims · ⭐ rooms ["wms","ims"] — 창고 · 오피스 사람이 각자 켠다 · staff.html 의 방 거르기가 rooms 를 보는 한 줄은 fc-2d) ·
--      ims_can_write · ims_can_view 는 `catalog->'screens' ? p_screen` 만 보므로 무접촉 · admin · supervisor 는 role 로 늘 true(854 「지금 계약 그대로」) · 나머지는 사람마다
--   ② 857 — ref_warehouse.timezone(not null · 기본 America/Toronto · IANA 이름 검사 트리거) · closes_at(창고 문 닫는 시각 = 기본 픽업 창 끝 · fc-2b 가 dispatch ready_until 로) ·
--      ⚠️ Edmonton 창고 = 'America/Regina'(Alberta 는 2026-11-01 부터 시계를 안 돌린다 — 상시 UTC-6 · 테스트 DB 의 tz 자료는 모른다 — 실측 12-15 18:00Z → Edmonton 11:00 · Regina 12:00 · Toronto 13:00) · 이름으로 찾되 없으면 건너뜀
--   ③ 852 — ref_carrier_pickup(carrier_id · warehouse_id PK · regular_pickup · cutoff time · note) · 값은 창고 담당자가 채운다 → 창구 ref_carrier_pickup_set(master 또는 fulfillment + 그 창고 · 이견 8) · 컷오버 K
--   ④ 852 — fc_cutoff_parse(Freightcom carrier_cut_off_time 'DD-MM-YYYY hh:miAM' → time · 연도 0000 = 가짜 → null) · fc_past_cutoff(창고 시간대의 지금 vs 출고일 · 마감) · fc_cutoff_eval(Freightcom 값이 진짜면 그것 · 아니면 IMS 값 · regular_pickup 함께)
--   ⑤ fc_quote_rate + cutoff · cutoff_source → fc_quote_save 재발행(20261028173935:284 바이트 복사 + 줄 넷: 저장 때 마감 판정 · 미리 고르기에서 지난 줄 제외 — 843 다음 조건 · past_cutoff_rates 반환)
--   ⑥ fc_shipment_for_so 재발행(20261028180558:244 바이트 복사 + 열쇠: rates[].cutoff · cutoff_source · past_cutoff(읽는 순간 · 창고 시간대) · regular_pickup · shipment.ship_date · warehouse_timezone · warehouse_closes_at · local_now · selected.* 같은 넷)
--   무접촉: ims_can_write · ims_can_view · fc_shipment_prepare · fc_quote_select · fc_gate · so_finalize · 화면 · 운영 DB · 첫 문장 = guard-test-only.sql 바이트 복사
--   컷오버 날 지우기(cutover-delete.sql ③ 분류 · 같은 커밋): K + 1(ref_carrier_pickup · k10) → 180 표 = D 83 · K 77 · R 20 · 칸만(ref_warehouse K · fc_quote_rate D)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261028201500_fc_2a_booking_perm_pickup_cutoff.sql && supabase migration repair --status applied 20261028201500 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028201500_fc_2a_booking_perm_pickup_cutoff.sql -f supabase/tests/fc_2a_check.sql  (안에서 fc_1b5 사본 137)

-- ═══ 1) 853 · 854 · 859 — ims_perm_catalog 재발행(20261020232704:36 바이트 복사 + freight_booking 한 줄) ═══
create or replace function public.ims_perm_catalog() returns jsonb
  language sql immutable
  set search_path = public, pg_temp
as $$
  select '{
    "modes": ["wms", "ims"],
    "screens": {
      "shopify":    {"room": "ims", "min_role": "manager", "label": "Shopify stores, product push, stock sync (manager and above · shop-1a)"},
      "purchasing": {"room": "ims", "label": "Purchase orders, invoices, charges, payments"},
      "master":     {"room": "ims", "label": "Settings, suppliers, products, families, supplier products, prices, product tags, deals"},
      "receiving":  {"room": "ims", "label": "Receiving and putaway"},
      "staff":      {"room": "ims", "label": "Adding and editing people (below your own rank)"},
      "sales":      {"room": "ims", "label": "Sales orders, customer addresses and contacts"},
      "picking":     {"room": "wms", "label": "Picking — pick tasks, waves, holds"},
      "packing":     {"room": "wms", "label": "Packing — pack tasks, pallets, boxes"},
      "fulfillment": {"room": "wms", "label": "Fulfillment — finalize, shipping, manager review"},
      "wms_manage":  {"room": "wms", "min_role": "manager", "label": "Warehouse management — batches, waves, rollbacks (manager and above)"},
      "wms_receiving":         {"room": "wms", "label": "Warehouse receiving — count, put away, hold, off-PO"},
      "wms_receiving_confirm": {"room": "wms", "min_role": "manager", "label": "Warehouse receiving — confirm a receipt (manager and above · off until switched on)"},
      "stock_adjust":          {"room": "ims", "min_role": "manager", "label": "Stock adjustments — draft and confirm (manager and above · off until switched on)"},
      "stock_move":            {"room": "wms", "label": "Bin moves — move stock between bins in one warehouse (person by person · off until switched on)"},
      "transfer":              {"room": "ims", "label": "Transfers — warehouse to warehouse (person by person · off until switched on)"},
      "doc_template":          {"room": "ims", "min_role": "supervisor", "label": "Document templates — publish a layout version (admin always · supervisor only when switched on · off until switched on)"},
      "cost":                  {"room": "ims", "label": "Inventory cost — stock value, layer values, unit costs (admin and supervisor always · person by person · read and write both show it · off until switched on)"},
      "freight_booking":       {"room": "ims", "rooms": ["wms", "ims"], "label": "Freight booking — book, cancel and re-book Freightcom shipments (admin and supervisor always · person by person · warehouse and office each switched on · quotes stay with sales / fulfillment · off until switched on)"}
    }
  }'::jsonb;
$$;
do $$ begin
  execute format('comment on function public.ims_perm_catalog() is %L',
    obj_description(to_regprocedure('public.ims_perm_catalog()'), 'pg_proc')
    || ' · ⭐ [2026-10-28 fc-2a] screens.freight_booking(예약 · 취소 · 다시 예약 — 판정 853 · admin · supervisor 는 역할로(854) · 나머지는 Staff 에서 사람마다 · ⭐ rooms ["wms","ims"] 첫 사례(859): 한 열쇠를 창고 · 오피스 두 방이 쓴다 — room 은 옛 화면용 · staff.html 이 rooms 를 보는 한 줄은 fc-2d · 견적 · 고르기는 그대로 sales / fulfillment)');
end $$;

-- ═══ 2) 857 — ref_warehouse.timezone · closes_at · Edmonton = America/Regina ═══
alter table public.ref_warehouse
  add column timezone  text not null default 'America/Toronto',
  add column closes_at time;
comment on column public.ref_warehouse.timezone  is 'fc-2a 판정 857: 창고 시간대(IANA 이름 · 트리거가 검사) — 마감(852) · 픽업 창의 「지금」 은 이 시간대로 · ⚠️ Edmonton = America/Regina(Alberta 는 2026-11-01 부터 상시 UTC-6 · DB 의 tz 자료는 모른다 · Regina = Saskatchewan 늘 UTC-6 이 같다) · Settings → Warehouses';
comment on column public.ref_warehouse.closes_at is 'fc-2a 판정 852: 창고 문 닫는 시각 — 픽업 창의 기본 끝(fc-2b dispatch ready_until · pickup_details) · 운송사 마감(ref_carrier_pickup.cutoff)은 이보다 늦을 수 없다(ref_carrier_pickup_set 이 거부) · null = 아직 안 적음 · Settings → Warehouses';

create function public.ref_warehouse_tz_check() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  begin
    perform now() at time zone new.timezone;                                                    -- 모르는 이름이면 22023
  exception when invalid_parameter_value then
    raise exception 'Time zone "%" is not recognized — use an IANA name such as America/Toronto or America/Regina — nothing was saved', new.timezone;
  end;
  return new;
end;
$$;
revoke all on function public.ref_warehouse_tz_check() from public, anon;
create trigger ref_warehouse_tz_check before insert or update of timezone on public.ref_warehouse for each row execute function public.ref_warehouse_tz_check();
comment on function public.ref_warehouse_tz_check() is 'fc-2a 판정 857: ref_warehouse.timezone 이 Postgres 가 아는 IANA 이름인지(now() at time zone 으로) — 아니면 사람 말로 거부';

update public.ref_warehouse set timezone = 'America/Regina' where name ilike '%edmonton%';   -- 857: 이름으로 찾되 없으면 건너뜀(테스트 · 운영 둘 다 「Asung - Edmonton」)

-- ═══ 3) 852 — ref_carrier_pickup · 창구 ═══
create table public.ref_carrier_pickup (
  carrier_id     uuid not null references public.ref_carrier (id),
  warehouse_id   uuid not null references public.ref_warehouse (id),
  regular_pickup boolean not null default false,
  cutoff         time,
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.ims_staff (id),
  primary key (carrier_id, warehouse_id)
);
comment on table public.ref_carrier_pickup is 'fc-2a 판정 852: 운송사 × 창고 — 정기 픽업이 있나(regular_pickup → 예약 때 pre_scheduled_pickup true · 없으면 픽업 시간을 넣는다) · 마감 시각(cutoff · 창고 시간대 · Freightcom 이 진짜 마감을 주면 그것이 먼저) · 값은 창고 담당자가 채운다 → 창구 ref_carrier_pickup_set(master 또는 fulfillment + 그 창고) · 행 없음 = 모른다(정기 픽업 없음 · 마감 없음) · 컷오버 K';
create trigger ref_carrier_pickup_touch before update on public.ref_carrier_pickup for each row execute function public.ims_touch();
alter table public.ref_carrier_pickup enable row level security;
create policy ref_carrier_pickup_select on public.ref_carrier_pickup for select to authenticated using (true);
revoke all on public.ref_carrier_pickup from public, anon, authenticated, service_role;
grant select on public.ref_carrier_pickup to authenticated, service_role;

create function public.ref_carrier_pickup_set(p_carrier_id uuid, p_warehouse_id uuid, p jsonb default '{}'::jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_car    public.ref_carrier%rowtype;
  v_wh     public.ref_warehouse%rowtype;
  v_row    public.ref_carrier_pickup%rowtype;
  v_cut    time;
  v_reg    boolean;
  v_note   text;
begin
  -- 문(이견 8 · fc_gate 와 같은 두 문): master(Settings) 또는 fulfillment + 그 창고
  if not public.ims_can_write('master') then
    if public.ims_can_write('fulfillment') then
      if not public.ims_can_warehouse(p_warehouse_id) then raise exception 'This warehouse is not yours — nothing was saved'; end if;
    else
      raise exception 'You cannot change carrier pickup settings — ask an admin to add the ''master'' or ''fulfillment'' permission — nothing was saved';
    end if;
  end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'p must be a JSON object — nothing was saved'; end if;
  select * into v_car from public.ref_carrier c where c.id = p_carrier_id;
  if not found or v_car.kind <> 'carrier' then raise exception 'Carrier % is not on the carrier list (Pickup · Delivery have no pickup settings) — nothing was saved', p_carrier_id; end if;
  select * into v_wh from public.ref_warehouse w where w.id = p_warehouse_id;
  if not found then raise exception 'Warehouse % not found — nothing was saved', p_warehouse_id; end if;
  select * into v_row from public.ref_carrier_pickup k where k.carrier_id = p_carrier_id and k.warehouse_id = p_warehouse_id for update;
  if coalesce((p->>'delete')::boolean, false) then
    delete from public.ref_carrier_pickup k where k.carrier_id = p_carrier_id and k.warehouse_id = p_warehouse_id;
    return jsonb_build_object('carrier_id', p_carrier_id, 'warehouse_id', p_warehouse_id, 'deleted', found, 'carrier', v_car.name, 'warehouse', v_wh.name);
  end if;
  -- 열쇠가 온 칸만(패치) · 빈 글자 = 비움
  v_reg  := case when p ? 'regular_pickup' then coalesce((p->>'regular_pickup')::boolean, false) else coalesce(v_row.regular_pickup, false) end;
  v_note := case when p ? 'note' then nullif(btrim(p->>'note'), '') else v_row.note end;
  if p ? 'cutoff' then
    if nullif(btrim(p->>'cutoff'), '') is null then v_cut := null;
    elsif btrim(p->>'cutoff') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then v_cut := btrim(p->>'cutoff')::time;
    else raise exception 'Cutoff "%" must be a time like 16:30 (24-hour) — nothing was saved', p->>'cutoff';
    end if;
  else
    v_cut := v_row.cutoff;
  end if;
  if v_cut is not null and v_wh.closes_at is not null and v_cut > v_wh.closes_at then
    raise exception 'Cutoff % is after % closes (%) — nothing was saved', to_char(v_cut, 'HH24:MI'), v_wh.name, to_char(v_wh.closes_at, 'HH24:MI');
  end if;
  insert into public.ref_carrier_pickup (carrier_id, warehouse_id, regular_pickup, cutoff, note, updated_by)
  values (p_carrier_id, p_warehouse_id, v_reg, v_cut, v_note, v_staff)
  on conflict (carrier_id, warehouse_id) do update set regular_pickup = excluded.regular_pickup, cutoff = excluded.cutoff, note = excluded.note, updated_by = excluded.updated_by
  returning * into v_row;
  return jsonb_build_object('carrier_id', v_row.carrier_id, 'warehouse_id', v_row.warehouse_id, 'carrier', v_car.name, 'warehouse', v_wh.name, 'timezone', v_wh.timezone,
                            'regular_pickup', v_row.regular_pickup, 'cutoff', to_char(v_row.cutoff, 'HH24:MI'), 'note', v_row.note, 'updated_at', v_row.updated_at);
end;
$$;
revoke all on function public.ref_carrier_pickup_set(uuid, uuid, jsonb) from public, anon, service_role;
grant execute on function public.ref_carrier_pickup_set(uuid, uuid, jsonb) to authenticated;
comment on function public.ref_carrier_pickup_set(uuid, uuid, jsonb) is 'fc-2a 판정 852: 운송사 × 창고 픽업 설정 쓰기 — 문 = master 또는 fulfillment + 그 창고 · p {regular_pickup?, cutoff? "HH:MM" | "" , note?, delete?} 열쇠가 온 칸만 · cutoff 는 창고 closes_at 보다 늦을 수 없다 · Pickup · Delivery 종류 거부 · 반환 = 행 + 이름';

-- ═══ 4) 852 — 마감 셈: fc_cutoff_parse · fc_past_cutoff · fc_cutoff_eval ═══
-- Freightcom 견적 줄의 carrier_cut_off_time — 테스트에서 전부 '31-12-0000 06:42PM'(가짜 · 연도 0000) · 운영에서 진짜가 오는지 모른다(fc-2 B) → 꼴이 맞고 연도가 0000 이 아니면 그 시각만(날짜는 보지 않는다 · 마감은 날마다 같은 시각) · 그 밖은 null
create function public.fc_cutoff_parse(p text) returns time
  language plpgsql immutable
  set search_path = public, pg_temp
as $$
declare m text[];
begin
  m := regexp_match(btrim(coalesce(p, '')), '^(\d{2})-(\d{2})-(\d{4}) (\d{1,2}):(\d{2}) ?([AaPp][Mm])$');
  if m is null or m[3] = '0000' then return null; end if;
  return to_timestamp(m[4] || ':' || m[5] || ' ' || upper(m[6]), 'HH12:MI AM')::time;
exception when others then
  return null;
end;
$$;
revoke all on function public.fc_cutoff_parse(text) from public, anon, authenticated, service_role;
comment on function public.fc_cutoff_parse(text) is 'fc-2a 판정 852: Freightcom carrier_cut_off_time(''DD-MM-YYYY hh:miAM'') → 시각 · 연도 0000(테스트의 가짜) · 다른 꼴 · 못 읽는 값 = null(그러면 IMS 값으로)';

-- 마감이 지났나 — 창고 시간대의 「지금」(p_now · 시험은 주입) vs 출고일(ship_date · null = 그날) · 마감 시각. 마감을 모르면 false(모른다고 지났다 하지 않는다) · 출고일이 지났으면 true · 아직이면 false · 그날이면 시각 비교
create function public.fc_past_cutoff(p_warehouse_id uuid, p_cutoff time, p_ship_date date, p_now timestamptz default now()) returns boolean
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_tz    text;
  v_local timestamp;
  v_ship  date;
begin
  if p_cutoff is null then return false; end if;
  select w.timezone into v_tz from public.ref_warehouse w where w.id = p_warehouse_id;
  v_local := p_now at time zone coalesce(v_tz, 'America/Toronto');
  v_ship  := coalesce(p_ship_date, v_local::date);
  if v_ship < v_local::date then return true; end if;
  if v_ship > v_local::date then return false; end if;
  return v_local::time > p_cutoff;
end;
$$;
revoke all on function public.fc_past_cutoff(uuid, time, date, timestamptz) from public, anon, authenticated, service_role;
comment on function public.fc_past_cutoff(uuid, time, date, timestamptz) is 'fc-2a 판정 852: 마감이 지났나 — 창고 시간대(ref_warehouse.timezone · 857)의 p_now 를 출고일 · 마감 시각과 견준다 · 마감 null = false · 출고일 지남 = true · 출고일 뒤 = false · 그날 = 시각 > 마감 · fc_quote_save(미리 고르기) · fc_shipment_for_so(표시) 가 부른다';

-- 한 줄의 마감 — Freightcom 값이 진짜면 그것(cutoff_source freightcom) · 아니면 IMS 운송사 × 창고 값(ims) · 둘 다 없으면 null · regular_pickup 함께
create function public.fc_cutoff_eval(p_warehouse_id uuid, p_carrier_id uuid, p_fc_cutoff text, p_ship_date date, p_now timestamptz default now()) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_fc   time := public.fc_cutoff_parse(p_fc_cutoff);
  v_pk   public.ref_carrier_pickup%rowtype;
  v_cut  time;
  v_src  text;
  v_tz   text;
begin
  if p_carrier_id is not null then select * into v_pk from public.ref_carrier_pickup k where k.carrier_id = p_carrier_id and k.warehouse_id = p_warehouse_id; end if;
  v_cut := coalesce(v_fc, v_pk.cutoff);
  v_src := case when v_fc is not null then 'freightcom' when v_pk.cutoff is not null then 'ims' end;
  select w.timezone into v_tz from public.ref_warehouse w where w.id = p_warehouse_id;
  return jsonb_build_object('cutoff', to_char(v_cut, 'HH24:MI'), 'cutoff_source', v_src,
                            'past_cutoff', public.fc_past_cutoff(p_warehouse_id, v_cut, p_ship_date, p_now),
                            'regular_pickup', coalesce(v_pk.regular_pickup, false),
                            'timezone', v_tz, 'local_now', to_char(p_now at time zone coalesce(v_tz, 'America/Toronto'), 'YYYY-MM-DD HH24:MI'),
                            'ship_date', p_ship_date);
end;
$$;
revoke all on function public.fc_cutoff_eval(uuid, uuid, text, date, timestamptz) from public, anon, service_role;
grant execute on function public.fc_cutoff_eval(uuid, uuid, text, date, timestamptz) to authenticated;
comment on function public.fc_cutoff_eval(uuid, uuid, text, date, timestamptz) is 'fc-2a 판정 852: 견적 줄 하나의 마감 — Freightcom carrier_cut_off_time 이 진짜면 그것(freightcom) · 아니면 ref_carrier_pickup(ims) · 없으면 null · past_cutoff(창고 시간대 · p_now 주입 가능) · regular_pickup · 화면 · fc-2b 도 부른다';

-- ═══ 5) fc_quote_rate + cutoff · cutoff_source → fc_quote_save 재발행(20261028173935:284 바이트 복사 + 줄 넷) ═══
alter table public.fc_quote_rate
  add column cutoff        time,
  add column cutoff_source text,
  add constraint fc_quote_rate_cutoff_source_ck check (cutoff_source is null or cutoff_source in ('freightcom', 'ims')),
  add constraint fc_quote_rate_cutoff_pair_ck   check ((cutoff is null) = (cutoff_source is null));
comment on column public.fc_quote_rate.cutoff        is 'fc-2a 판정 852: 이 줄의 마감 시각(창고 시간대) — 저장 때 fc_cutoff_eval(Freightcom 진짜 값 → IMS 값) · 지났는지는 읽는 순간 fc_past_cutoff 가 센다(저장값 아님)';
comment on column public.fc_quote_rate.cutoff_source is 'fc-2a: freightcom(응답의 carrier_cut_off_time 이 진짜) · ims(ref_carrier_pickup) · null = 모른다';

create or replace function public.fc_quote_save(p_shipment_id uuid, p_request_id text, p_response jsonb, p_error text default null, p_request jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_f      public.fc_shipment%rowtype;
  v_staff  uuid;
  v_role   text := coalesce(current_setting('request.jwt.claims', true)::jsonb->>'role', '');
  v_qid    uuid;
  v_pct    numeric;
  v_defc   uuid;
  v_use_def boolean;
  v_n      int := 0;
  v_pre_id uuid;
  v_r      record;
  v_base   bigint;  v_sur bigint;  v_tax bigint;  v_total bigint;  v_pre bigint;
  v_cid    uuid;
  v_vu     date;
  v_pend   uuid;                                                                      -- fc-1b: 이 request_id 의 pending 줄(fc_quote_pending 이 넣음)
  v_ship   date;                                                                      -- fc-2a 852: 출고일(prepare 가 options.ship_date 에 굳힘)
  v_ev     jsonb;                                                                     -- fc-2a 852: 줄의 마감 판정
  v_past   int := 0;
begin
  select * into v_f from public.fc_shipment f where f.id = p_shipment_id for update;
  if not found then raise exception 'Shipment % not found — nothing was saved', p_shipment_id; end if;
  if v_role <> 'service_role' then perform public.fc_gate(v_f.origin_warehouse_id, 'saved'); end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_f.status in ('booked', 'cancelled') then raise exception 'Shipment is % — no new quotes — nothing was saved', v_f.status; end if;
  v_ship := nullif(btrim(v_f.options->>'ship_date'), '')::date;                                                                                   -- fc-2a
  if p_request_id is not null then select q.id into v_pend from public.fc_quote q where q.shipment_id = p_shipment_id and q.request_id = p_request_id and q.status = 'pending' order by q.seq desc limit 1; end if;   -- fc-1b2: seq
  if p_error is not null then
    if v_pend is not null then
      update public.fc_quote q set status = 'error', error = left(p_error, 1000), done_at = now(), request = coalesce(p_request, q.request), by_staff = coalesce(v_staff, q.by_staff) where q.id = v_pend returning q.id into v_qid;
    else
      insert into public.fc_quote (shipment_id, request_id, status, request, error, done_at, by_staff) values (p_shipment_id, p_request_id, 'error', coalesce(p_request, v_f.request), left(p_error, 1000), now(), v_staff) returning id into v_qid;
    end if;
    return jsonb_build_object('quote_id', v_qid, 'status', 'error', 'rates', 0);
  end if;
  if p_response is null or jsonb_typeof(coalesce(p_response->'rates', 'null'::jsonb)) <> 'array' then raise exception 'The quote response has no rates[] — nothing was saved'; end if;
  v_pct := coalesce((select c.value::numeric from public.inv_config c where c.key = 'fc_markup_pct'), 0);
  select c.default_carrier_id into v_defc from public.customer c where c.id = v_f.customer_id;
  if v_pend is not null then
    update public.fc_quote q set status = 'done', response = p_response, done_at = now(), request = coalesce(p_request, q.request), by_staff = coalesce(v_staff, q.by_staff) where q.id = v_pend returning q.id into v_qid;
  else
    insert into public.fc_quote (shipment_id, request_id, status, request, response, done_at, by_staff) values (p_shipment_id, p_request_id, 'done', coalesce(p_request, v_f.request), p_response, now(), v_staff) returning id into v_qid;   -- fc-1b: request = EF 가 실제 보낸 몸(freight_class · services 포함) · 없으면 발송의 payload
  end if;
  for v_r in select t.rate, t.ord from jsonb_array_elements(p_response->'rates') with ordinality as t(rate, ord) loop
    if nullif(btrim(v_r.rate->>'service_id'), '') is null then continue; end if;
    v_base  := public.fc_money_cents(v_r.rate->'base');
    v_sur   := coalesce((select sum(public.fc_money_cents(s->'amount')) from jsonb_array_elements(coalesce(nullif(v_r.rate->'surcharges', 'null'::jsonb), '[]'::jsonb)) s), 0);
    v_tax   := coalesce((select sum(public.fc_money_cents(s->'amount')) from jsonb_array_elements(coalesce(nullif(v_r.rate->'taxes', 'null'::jsonb), '[]'::jsonb)) s), 0);
    v_total := public.fc_money_cents(v_r.rate->'total');
    v_pre   := coalesce(v_base, 0) + v_sur;
    select n.carrier_id into v_cid from public.ref_carrier_fc_name n where n.name_norm = lower(btrim(coalesce(v_r.rate->>'carrier_name', ''))) limit 1;   -- fc-1b3 판정 847: 이름 표(한 이름은 한 운송사 · 대소문자 · 앞뒤 공백 무시 — 응답의 「fastfrate」 · 「Maritime 」 도 붙는다)
    v_vu := case when jsonb_typeof(v_r.rate->'valid_until') = 'object' and (v_r.rate->'valid_until'->>'year') ~ '^[0-9]+$'
                 then make_date((v_r.rate->'valid_until'->>'year')::int, (v_r.rate->'valid_until'->>'month')::int, (v_r.rate->'valid_until'->>'day')::int) end;
    v_ev := public.fc_cutoff_eval(v_f.origin_warehouse_id, v_cid, v_r.rate->>'carrier_cut_off_time', v_ship, now());                              -- fc-2a 852: Freightcom 진짜 값 → IMS 값
    if (v_ev->>'past_cutoff')::boolean then v_past := v_past + 1; end if;
    insert into public.fc_quote_rate (quote_id, service_id, carrier_name, service_name, carrier_id, base_cents, surcharge_cents, tax_cents, total_cents, pretax_cents, markup_pct, customer_charge_cents, transit_days, valid_until, avoided, totals_mismatch, raw, cutoff, cutoff_source)
    values (v_qid, btrim(v_r.rate->>'service_id'), nullif(btrim(v_r.rate->>'carrier_name'), ''), nullif(btrim(v_r.rate->>'service_name'), ''), v_cid, v_base, v_sur, v_tax, v_total, v_pre, v_pct,
            round(v_pre * (1 + v_pct / 100))::bigint,                                                                     -- 836: 세전 × (1 + 마크업) · 센트 반올림
            case when (v_r.rate->>'transit_time_days') ~ '^[0-9]+$' then (v_r.rate->>'transit_time_days')::int end, v_vu,
            v_cid is not null and exists (select 1 from public.customer_carrier_avoid a where a.customer_id = v_f.customer_id and a.carrier_id = v_cid),   -- 843
            v_total is not null and v_total <> v_pre + v_tax, v_r.rate,
            (v_ev->>'cutoff')::time, v_ev->>'cutoff_source');                                                                                           -- fc-2a 852
    v_n := v_n + 1;
  end loop;
  -- 843 미리 고르기 — 피할 것 · 짝 없는 것 제외 · ⭐ fc-2a 852: 마감 지난 줄 제외(843 다음 조건 · 고를 수는 있다) · 손님 기본 운송사에 줄이 있으면 그 가운데 최저 · 없으면 전체 최저
  v_use_def := v_defc is not null and exists (select 1 from public.fc_quote_rate q where q.quote_id = v_qid and not q.avoided and q.carrier_id = v_defc and not public.fc_past_cutoff(v_f.origin_warehouse_id, q.cutoff, v_ship, now()));
  select q.id into v_pre_id from public.fc_quote_rate q where q.quote_id = v_qid and not q.avoided and q.carrier_id is not null and (not v_use_def or q.carrier_id = v_defc)
     and not public.fc_past_cutoff(v_f.origin_warehouse_id, q.cutoff, v_ship, now())
   order by q.pretax_cents, q.service_id limit 1;
  if v_pre_id is not null then update public.fc_quote_rate set preselected = true where id = v_pre_id; end if;
  update public.fc_shipment f set status = 'quoted', selected_rate_id = null, updated_by = coalesce(v_staff, f.updated_by) where f.id = p_shipment_id;
  return jsonb_build_object('quote_id', v_qid, 'status', 'done', 'rates', v_n, 'preselected_rate_id', v_pre_id, 'freight_locked', v_f.freight_locked, 'markup_pct', v_pct, 'ship_date', v_ship, 'past_cutoff_rates', v_past);
end;
$$;
comment on function public.fc_quote_save(uuid, text, jsonb, text, jsonb) is 'fc-1a 견적 결과 저장(EF service_role 또는 직원 fc_gate · rates[] → fc_quote_rate 센트 · 836 마크업 · 847 이름 짝 · 843 avoided · preselected) · fc-1b p_request · fc-1b2 seq · ⭐ fc-2a 판정 852: 줄마다 cutoff · cutoff_source(Freightcom 진짜 값 → ref_carrier_pickup) · 미리 고르기는 마감 지난 줄을 뺀다(843 다음 · 고를 수는 있다) · 반환 ship_date · past_cutoff_rates';

-- ═══ 6) fc_shipment_for_so 재발행(20261028180558:244 바이트 복사 + 마감 · 창고 시간대 열쇠) ═══
create or replace function public.fc_shipment_for_so(p_so_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_f     public.fc_shipment%rowtype;
  v_q     public.fc_quote%rowtype;
  v_so    public.so%rowtype;
  v_units jsonb;
  v_rates jsonb;
  v_sel   public.fc_quote_rate%rowtype;
  v_sos   jsonb;
  v_now   jsonb;
  v_ship  date;                                                                       -- fc-2a 852
  v_wh    public.ref_warehouse%rowtype;                                               -- fc-2a 857
begin
  select * into v_so from public.so s where s.id = p_so_id;
  if not found then raise exception 'Order % not found', p_so_id; end if;
  select f.* into v_f from public.fc_shipment_so l join public.fc_shipment f on f.id = l.shipment_id where l.so_id = p_so_id and l.live;
  v_now := public.fc_units_snapshot(array[p_so_id]);
  if v_f.id is null then
    return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'shipment', null,
                              'units_now', v_now, 'units_without_dims', (select count(*) from jsonb_array_elements(v_now) e where e->>'length_in' is null or e->>'width_in' is null or e->>'height_in' is null or e->>'weight_lb' is null),
                              'markup_pct', (select c.value::numeric from public.inv_config c where c.key = 'fc_markup_pct'));
  end if;
  v_ship := nullif(btrim(v_f.options->>'ship_date'), '')::date;
  select * into v_wh from public.ref_warehouse w where w.id = v_f.origin_warehouse_id;
  select coalesce(jsonb_agg(jsonb_build_object('so_id', s.id, 'so_number', s.so_number, 'status', s.status, 'is_charge_so', s.id = v_f.charge_so_id) order by s.created_at, s.so_number), '[]'::jsonb)
    into v_sos from public.fc_shipment_so l join public.so s on s.id = l.so_id where l.shipment_id = v_f.id and l.live;
  select * into v_q from public.fc_quote q where q.shipment_id = v_f.id order by q.seq desc limit 1;                                 -- fc-1b2: 「최신」 = seq(한 트랜잭션 안 now() 동점 · id 난수 → 갈렸다)
  if v_q.id is not null and v_q.status = 'done' then
    select coalesce(jsonb_agg(jsonb_build_object('rate_id', r.id, 'service_id', r.service_id, 'carrier_name', r.carrier_name, 'service_name', r.service_name, 'carrier_id', r.carrier_id,
                                                 'base_cents', r.base_cents, 'surcharge_cents', r.surcharge_cents, 'tax_cents', r.tax_cents, 'total_cents', r.total_cents, 'pretax_cents', r.pretax_cents,
                                                 'customer_charge_cents', r.customer_charge_cents, 'transit_days', r.transit_days, 'valid_until', r.valid_until,
                                                 'avoided', r.avoided, 'preselected', r.preselected, 'selectable', (not r.avoided and r.carrier_id is not null), 'totals_mismatch', r.totals_mismatch,
                                                 'selected', r.id = v_f.selected_rate_id,
                                                 'cutoff', to_char(r.cutoff, 'HH24:MI'), 'cutoff_source', r.cutoff_source,                                                       -- fc-2a 852
                                                 'past_cutoff', public.fc_past_cutoff(v_f.origin_warehouse_id, r.cutoff, v_ship, now()),                                          -- 읽는 순간 · 창고 시간대 — 화면: 「마감 지남 — 내일 나감」
                                                 'regular_pickup', coalesce(pk.regular_pickup, false))
                              order by r.avoided, (r.carrier_id is null), r.pretax_cents, r.service_id), '[]'::jsonb)
      into v_rates from public.fc_quote_rate r left join public.ref_carrier_pickup pk on pk.carrier_id = r.carrier_id and pk.warehouse_id = v_f.origin_warehouse_id where r.quote_id = v_q.id;
  end if;
  if v_f.selected_rate_id is not null then select * into v_sel from public.fc_quote_rate r where r.id = v_f.selected_rate_id; end if;
  select public.fc_units_snapshot(array(select l.so_id from public.fc_shipment_so l where l.shipment_id = v_f.id and l.live)) into v_units;
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number,
    'shipment', jsonb_build_object('id', v_f.id, 'status', v_f.status, 'packaging_type', v_f.packaging_type, 'origin_warehouse_id', v_f.origin_warehouse_id,
                                   'charge_so_id', v_f.charge_so_id, 'customer_id', v_f.customer_id, 'address_id', v_f.address_id, 'freightcom_account', v_f.freightcom_account,   -- fc-1b4
                                   'freight_locked', v_f.freight_locked, 'freight_locked_reason', v_f.freight_locked_reason,
                                   'address_review', v_f.address_review, 'address_review_closed_at', v_f.address_review_closed_at, 'address_review_action', v_f.address_review_action,   -- fc-1b 845
                                   'origin', v_f.origin, 'destination', v_f.destination, 'options', v_f.options, 'units', v_f.units, 'request', v_f.request, 'payload_hash', v_f.payload_hash,
                                   'created_in', v_f.created_in, 'created_by', v_f.created_by, 'created_at', v_f.created_at, 'updated_at', v_f.updated_at,
                                   'ship_date', v_ship, 'warehouse_timezone', v_wh.timezone, 'warehouse_closes_at', to_char(v_wh.closes_at, 'HH24:MI'),                              -- fc-2a 852 · 857
                                   'local_now', to_char(now() at time zone coalesce(v_wh.timezone, 'America/Toronto'), 'YYYY-MM-DD HH24:MI')),
    'orders', v_sos,
    'quote', case when v_q.id is null then null else jsonb_build_object('id', v_q.id, 'status', v_q.status, 'request_id', v_q.request_id, 'error', v_q.error, 'requested_at', v_q.requested_at, 'done_at', v_q.done_at, 'rates', coalesce(v_rates, '[]'::jsonb)) end,
    'selected', case when v_sel.id is null then null else jsonb_build_object('rate_id', v_sel.id, 'carrier_id', v_sel.carrier_id, 'carrier_name', v_sel.carrier_name, 'service_id', v_sel.service_id, 'service_name', v_sel.service_name,
                                                                        'customer_charge_cents', v_sel.customer_charge_cents, 'pretax_cents', v_sel.pretax_cents,
                                                                        'cutoff', to_char(v_sel.cutoff, 'HH24:MI'), 'cutoff_source', v_sel.cutoff_source,                                        -- fc-2a 852
                                                                        'past_cutoff', public.fc_past_cutoff(v_f.origin_warehouse_id, v_sel.cutoff, v_ship, now()),
                                                                        'regular_pickup', coalesce((select pk.regular_pickup from public.ref_carrier_pickup pk where pk.carrier_id = v_sel.carrier_id and pk.warehouse_id = v_f.origin_warehouse_id), false)) end,
    'charge_amount', case when v_sel.id is null or v_f.freight_locked then null else round(v_sel.customer_charge_cents / 100.0, 2) end,
    'units_now', v_units, 'units_changed', (v_units <> v_f.units),
    'units_without_dims', (select count(*) from jsonb_array_elements(v_units) e where e->>'length_in' is null or e->>'width_in' is null or e->>'height_in' is null or e->>'weight_lb' is null),
    'markup_pct', (select c.value::numeric from public.inv_config c where c.key = 'fc_markup_pct'));
end;
$$;
comment on function public.fc_shipment_for_so(uuid) is 'fc-1a 한 SO 의 살아 있는 발송 · 최신 견적(seq) · 줄 · 고른 줄 · units_changed — 화면 둘(WMS Finalize · 오피스 Ship & invoice)이 같은 모양으로 읽는다 · fc-1b 845 · fc-1b4 계정 · ⭐ fc-2a 판정 852 · 857: rates[].cutoff · cutoff_source · past_cutoff(읽는 순간 · 창고 시간대) · regular_pickup · selected 같은 넷 · shipment.ship_date · warehouse_timezone · warehouse_closes_at · local_now';

-- ═══ 7) 착지 검사 ═══
do $$
declare v_cat jsonb := public.ims_perm_catalog();
begin
  if (v_cat->'screens'->'freight_booking'->'rooms')::text <> '["wms", "ims"]' then raise exception 'fc-2a landing check failed: freight_booking rooms'; end if;
  if (select count(*) from jsonb_object_keys(v_cat->'screens')) <> 18 then raise exception 'fc-2a landing check failed: screens count'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and ((table_name = 'ref_warehouse' and column_name in ('timezone', 'closes_at')) or (table_name = 'fc_quote_rate' and column_name in ('cutoff', 'cutoff_source')))) <> 4 then raise exception 'fc-2a landing check failed: columns'; end if;
  if (select count(*) from public.ref_warehouse where timezone not in ('America/Toronto', 'America/Regina')) <> 0 then raise exception 'fc-2a landing check failed: unexpected timezone'; end if;
  if exists (select 1 from public.ref_warehouse where name ilike '%edmonton%' and timezone <> 'America/Regina') then raise exception 'fc-2a landing check failed: Edmonton timezone'; end if;
  if (select relacl::text from pg_class where oid = 'public.ref_carrier_pickup'::regclass) <> '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres}' then raise exception 'fc-2a landing check failed: ref_carrier_pickup acl'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('ref_carrier_pickup_set', 'fc_cutoff_parse', 'fc_past_cutoff', 'fc_cutoff_eval', 'ref_warehouse_tz_check', 'fc_quote_save', 'fc_shipment_for_so', 'ims_perm_catalog')) <> 8 then raise exception 'fc-2a landing check failed: function count'; end if;
  if has_function_privilege('anon', 'public.ref_carrier_pickup_set(uuid, uuid, jsonb)', 'execute') or has_function_privilege('service_role', 'public.ref_carrier_pickup_set(uuid, uuid, jsonb)', 'execute') or not has_function_privilege('authenticated', 'public.ref_carrier_pickup_set(uuid, uuid, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.fc_past_cutoff(uuid, time, date, timestamptz)', 'execute') or has_function_privilege('anon', 'public.fc_cutoff_eval(uuid, uuid, text, date, timestamptz)', 'execute') or not has_function_privilege('authenticated', 'public.fc_cutoff_eval(uuid, uuid, text, date, timestamptz)', 'execute') then
    raise exception 'fc-2a landing check failed: function acl';
  end if;
  if public.fc_cutoff_parse('31-12-0000 06:42PM') is not null or public.fc_cutoff_parse('28-10-2026 04:30PM') <> time '16:30' then raise exception 'fc-2a landing check failed: fc_cutoff_parse'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_quote_save') <> '750a0fbacaa37d2215112a9b8308d0ce' then raise exception 'fc-2a landing check failed: fc_quote_save md5'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_for_so') <> '83b5e899f8fd8ebcbe5d654a20b20c4a' then raise exception 'fc-2a landing check failed: fc_shipment_for_so md5'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_perm_catalog') <> 'e70510a8c5c161e64f1024bb856c31bf' then raise exception 'fc-2a landing check failed: ims_perm_catalog md5'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_can_write') <> '82556f945f6acdecfc64043cba2a4ddc' then raise exception 'fc-2a landing check failed: ims_can_write touched'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_prepare') <> '2a2a0206f9f2b12320dd93f6467fa8fc' then raise exception 'fc-2a landing check failed: fc_shipment_prepare touched'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize') <> '70d4711f91b1ff0b3bb7067864383124' then raise exception 'fc-2a landing check failed: so_finalize touched'; end if;
  raise notice 'fc-2a landing OK — freight_booking(rooms 2) · ref_warehouse.timezone · closes_at · ref_carrier_pickup + set · cutoff parse/past/eval · fc_quote_rate.cutoff · reissued 3';
end $$;
