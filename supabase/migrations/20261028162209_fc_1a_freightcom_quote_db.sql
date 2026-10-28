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
-- fc-1a — Freightcom 견적: DB 바탕 (표 · 칸 · 창구) (2026-10-28 · 판정 835 ~ 843 · 조사 fc-0 · 지시서 ~/asung/prompts/fc-1a.md)
--   왜: 운임 견적 · 운송사 · 추적번호가 Freightcom 웹과 IMS 사이를 두 번 손으로 옮겨 다닌다(so-module §1-p · 판정 677) — 1 단계 = 견적(이 차수 DB · fc-1b EF · fc-1c 화면) · 2 단계 = 예약(fc-2)
--   엔진 하나 · 입구 둘(835): 창고 Finalize(fulfillment 열쇠 + 그 창고) · 오피스 Ship & invoice(sales 열쇠) — 같은 창구를 두 문 중 하나로 지난다(fc_gate) · 창고 직원에게 sales 는 주지 않는다(판정 7)
--   칸: ref_warehouse + phone · email · contact_name(출발지 연락처 · Settings 마스터 편집기가 RLS master 로 직접 쓴다 — 창구 0) ·
--       customer_address + residential(null = 기본 규칙 839) · tailgate_required · threshold_delivery(840 · customer_update address_add · address_set 열쇠 셋 — 주소 창구는 이 하나) ·
--       ref_carrier + freightcom_carrier(Freightcom carrier_name 그대로 · 대소문자 무시 유니크 · settings.html 이 직접 쓴다 — 창구 0) · customer_carrier_avoid(843 피할 운송사 · 창구 customer_carrier_avoid_set) ·
--       inv_config fc_markup_pct = 5(836 · ims_config_set master)
--   표: fc_shipment(한 발송 = SO 하나 이상 · 스냅샷 · payload · charge_so_id 837 · freight_locked 836) · fc_shipment_so(live · 한 SO 는 살아 있는 발송 하나 — 부분 유니크 · 트리거가 status 와 맞춘다) ·
--       fc_quote(요청 · 응답 원문) · fc_quote_rate(줄마다 센트 · 836 셈 · 843 avoided · preselected) · fc_call_log(EF · 90 일 · shop_call_log 꼴)
--   창구: fc_shipment_prepare(검사 → payload · DB 가 만든다 · EF 는 나른다) · fc_quote_save(EF service_role 또는 직원) · fc_quote_select · fc_charge_so_set(sales) · fc_shipment_for_so(읽기 · 화면 둘이 같은 모양) · wms_unit_dims_set(841 오피스 치수) · customer_carrier_avoid_set
--   짐작(fc-1b 가 확인): /rate 요청 몸 = {details:{origin, destination, expected_ship_date, packaging_type, packaging_properties}} · services[] 는 EF 가 ref_carrier.freightcom_carrier 로 고른다(payload 밖 carriers[]) · 금액은 센트 정수 글자(value) · surcharges[].amount · taxes[].amount 는 {currency,value} 또는 숫자 — 둘 다 읽는다 · freight_class 는 EF 가 /freight-class/calculate 로
--   so_finalize 무접촉(이 차수) · so_copy_customer 무접촉 · so_customer_is_company 무접촉(839 의 「회사」 = SO 스냅샷 ship_to_company 가 찼는가 — 794 가 복사 때 정한 값 · 직원이 초안에서 고친 값까지 그대로)
--   컷오버 날 지우기(cutover-delete.sql ③ 분류 · 같은 커밋에서 고침): D(거래) = fc_quote_rate fc_quote fc_shipment_so fc_shipment · K(남김) = fc_call_log customer_carrier_avoid · 거래 표 so 를 가리키는 FK = fc_shipment.charge_so_id · fc_shipment_so.so_id(둘 다 D 안)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261028162209_fc_1a_freightcom_quote_db.sql && supabase migration repair --status applied 20261028162209 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028162209_fc_1a_freightcom_quote_db.sql -f supabase/tests/fc_1a_check.sql

-- ═══ 1) 칸 ═══
alter table public.ref_warehouse
  add column phone        text,
  add column email        text,
  add column contact_name text;
comment on column public.ref_warehouse.phone        is 'fc-1a: 출발지 전화(Freightcom origin.phone_number · 숫자만 남겨 보낸다) · Settings 에서';
comment on column public.ref_warehouse.email        is 'fc-1a: 출발지 이메일(origin.email_addresses) · Settings 에서';
comment on column public.ref_warehouse.contact_name is 'fc-1a: 출발지 담당자(origin.contact_name) · Settings 에서';

alter table public.customer_address
  add column residential        boolean,
  add column tailgate_required  boolean not null default false,
  add column threshold_delivery boolean not null default false;
comment on column public.customer_address.residential        is 'fc-1a 판정 839: 주거지인가 — null = 기본 규칙(오더 배송지가 회사면 상업지 · 아니면 주거지) · 견적 때 바꾸고 「기억」 하면 여기 굳는다(기억한 값이 기본보다 앞)';
comment on column public.customer_address.tailgate_required  is 'fc-1a 판정 840: 테일게이트 — 견적 때 자동으로 destination.tailgate_required 로';
comment on column public.customer_address.threshold_delivery is 'fc-1a 판정 840: 인사이드 딜리버리 — 팔렛 견적의 pallet_service_details.threshold_delivery 로(상자 견적에는 없다)';

alter table public.ref_carrier add column freightcom_carrier text;
create unique index ref_carrier_freightcom_uq on public.ref_carrier (lower(btrim(freightcom_carrier))) where freightcom_carrier is not null;
comment on column public.ref_carrier.freightcom_carrier is 'fc-1a(fc-0 ④ 안 A): Freightcom /services 의 carrier_name 그대로(예 UPS · Purolator Freight · Maritime) · 대소문자 · 앞뒤 공백 무시 유니크 · 짝 없는 운송사의 견적은 고를 수 없다(Settings 에서 운송사를 더한다 · 판정 450)';

create table public.customer_carrier_avoid (
  customer_id uuid not null references public.customer (id),
  carrier_id  uuid not null references public.ref_carrier (id),
  created_at  timestamptz not null default now(),
  created_by  uuid references public.ims_staff (id),
  primary key (customer_id, carrier_id)
);
comment on table public.customer_carrier_avoid is 'fc-1a 판정 843: 손님마다 피할 운송사 — 그 운송사의 견적은 avoided(흐림 · 고를 수 없음 · 미리 고르기에서도 뺀다) · 쓰기는 customer_carrier_avoid_set(sales) · 컷오버 K';
alter table public.customer_carrier_avoid enable row level security;
create policy customer_carrier_avoid_select on public.customer_carrier_avoid for select to authenticated using (true);
revoke all on public.customer_carrier_avoid from public, anon, authenticated, service_role;
grant select on public.customer_carrier_avoid to authenticated, service_role;

insert into public.inv_config (key, value, note) values ('fc_markup_pct', '5', 'fc-1a 판정 836: 손님 운임 = Freightcom 세전(base + 할증) × (1 + 이 %) · 센트 반올림 · Settings(master · ims_config_set)')
on conflict (key) do nothing;

-- ═══ 2) 표 — 발송 · 견적 · 줄 · 호출 기록 ═══
create table public.fc_shipment (
  id                    uuid primary key default gen_random_uuid(),
  status                text not null default 'draft',
  origin_warehouse_id   uuid not null references public.ref_warehouse (id),
  packaging_type        text not null,
  charge_so_id          uuid not null references public.so (id),
  customer_id           uuid references public.customer (id),
  address_id            uuid references public.customer_address (id),
  freight_locked        boolean not null default false,
  freight_locked_reason text,
  origin                jsonb not null,
  destination           jsonb not null,
  options               jsonb not null,
  units                 jsonb not null,
  request               jsonb not null,
  payload_hash          text not null,
  selected_rate_id      uuid,
  created_in            text not null,
  created_by            uuid references public.ims_staff (id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  updated_by            uuid references public.ims_staff (id),
  superseded_by         uuid references public.fc_shipment (id),
  cancelled_at          timestamptz,
  cancel_reason         text,
  constraint fc_shipment_status_ck     check (status in ('draft', 'quoted', 'selected', 'booked', 'cancelled')),
  constraint fc_shipment_packaging_ck  check (packaging_type in ('package', 'pallet')),
  constraint fc_shipment_created_in_ck check (created_in in ('wms', 'office')),
  constraint fc_shipment_cancel_ck     check ((status = 'cancelled') = (cancelled_at is not null))
);
create index fc_shipment_charge_so_idx on public.fc_shipment (charge_so_id);
comment on table public.fc_shipment is 'fc-1a 판정 835 ~ 838: 한 발송 = SO 하나 이상(같은 배송지 · 같은 창고 · 상자만 또는 팔렛만) · 견적 때 보낸 그대로의 스냅샷(origin · destination · options · units · request · payload_hash) · charge_so_id = 운임 줄을 받을 SO(837 · 가장 먼저 만든 SO · fc_charge_so_set 으로 옮긴다) · freight_locked = 손님이 Shopify 에서 운임을 결제한 웹 오더(836 · aone 스토어) — 견적 · 기록만, 운임 줄은 덮지 않는다 · status draft → quoted → selected → booked(fc-2) · cancelled(다시 prepare 가 다른 SO 묶음으로 갈아 끼울 때 superseded_by) · id 가 예약 unique_id 의 바탕(677 정정)';
create trigger fc_shipment_touch before update on public.fc_shipment for each row execute function public.ims_touch();

create table public.fc_shipment_so (
  shipment_id uuid not null references public.fc_shipment (id),
  so_id       uuid not null references public.so (id),
  live        boolean not null default true,
  primary key (shipment_id, so_id)
);
create unique index fc_shipment_so_live_uq on public.fc_shipment_so (so_id) where live;
comment on table public.fc_shipment_so is 'fc-1a: 발송에 든 SO · live = 발송이 cancelled 가 아님(트리거 fc_shipment_live_sync 가 status 와 맞춘다) · 부분 유니크(so_id) where live = 한 SO 는 살아 있는 발송 하나에만';

create table public.fc_quote (
  id           uuid primary key default gen_random_uuid(),
  shipment_id  uuid not null references public.fc_shipment (id),
  request_id   text,
  status       text not null default 'pending',
  request      jsonb,
  response     jsonb,
  error        text,
  requested_at timestamptz not null default now(),
  done_at      timestamptz,
  by_staff     uuid references public.ims_staff (id),
  constraint fc_quote_status_ck check (status in ('pending', 'done', 'error'))
);
create index fc_quote_shipment_idx on public.fc_quote (shipment_id, requested_at desc);
comment on table public.fc_quote is 'fc-1a: 견적 한 번(POST /rate → request_id → GET /rate/{id} 끝) · request = 보낸 payload · response = 응답 원문(센트 짐작 확인용) · 옛 견적은 발송을 갈아 끼워도 남는다';

create table public.fc_quote_rate (
  id                   uuid primary key default gen_random_uuid(),
  quote_id             uuid not null references public.fc_quote (id),
  service_id           text not null,
  carrier_name         text,
  service_name         text,
  carrier_id           uuid references public.ref_carrier (id),
  base_cents           bigint,
  surcharge_cents      bigint not null default 0,
  tax_cents            bigint not null default 0,
  total_cents          bigint,
  pretax_cents         bigint not null,
  markup_pct           numeric not null,
  customer_charge_cents bigint not null,
  transit_days         int,
  valid_until          date,
  avoided              boolean not null default false,
  preselected          boolean not null default false,
  totals_mismatch      boolean not null default false,
  raw                  jsonb not null,
  created_at           timestamptz not null default now()
);
create index fc_quote_rate_quote_idx on public.fc_quote_rate (quote_id);
alter table public.fc_shipment add constraint fc_shipment_selected_rate_fk foreign key (selected_rate_id) references public.fc_quote_rate (id);
comment on table public.fc_quote_rate is 'fc-1a: 견적 줄 하나 = rates[] 원소 · 센트 정수 · pretax = base + 할증 합 · customer_charge = round(pretax × (1 + 마크업 %))(836) · carrier_id = ref_carrier.freightcom_carrier 짝(없으면 고를 수 없음) · avoided = customer_carrier_avoid(843) · preselected = 손님 기본 운송사 중 최저 · 없으면 전체 최저(피할 것 · 짝 없는 것 제외) · totals_mismatch = total ≠ pretax + 세금 합(센트 짐작 확인용)';

create table public.fc_call_log (
  id                 bigint generated always as identity primary key,
  called_at          timestamptz not null default now(),
  shipment_id        uuid,                                                           -- FK 없음: 기록은 발송보다 오래 남는다(컷오버 K · cutover-delete ③-c 「D 밖 → D FK 0」)
  action             text not null,
  ok                 boolean not null,
  http_status        int,
  error              text,
  by_staff           uuid references public.ims_staff (id),
  ms                 int
);
create index fc_call_log_called_idx on public.fc_call_log (called_at);
comment on table public.fc_call_log is 'fc-1a: EF freightcom 의 호출 기록(shop_call_log 꼴 · 90 일 · EF 가 service_role 로 쓰고 지운다) · 컷오버 K';

do $$ declare t text; begin
  foreach t in array array['fc_shipment', 'fc_shipment_so', 'fc_quote', 'fc_quote_rate', 'fc_call_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_select', t);
    execute format('revoke all on public.%I from public, anon, authenticated, service_role', t);
    execute format('grant select on public.%I to authenticated, service_role', t);
  end loop;
end $$;
grant insert, delete on public.fc_call_log to service_role;                        -- EF 가 REST 로 기록 · 90 일 지우기(shop_call_log 와 같다)
revoke all on sequence public.fc_call_log_id_seq from public, anon, authenticated, service_role;
grant usage on sequence public.fc_call_log_id_seq to service_role;

-- live 맞추기 — 발송이 cancelled 가 되면 그 SO 줄의 live 를 끈다(되살리기 없음 · 새 발송은 새 행)
create function public.fc_shipment_live_sync() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  if new.status is distinct from old.status then
    update public.fc_shipment_so set live = (new.status <> 'cancelled') where shipment_id = new.id;
  end if;
  return new;
end;
$$;
revoke all on function public.fc_shipment_live_sync() from public, anon, authenticated, service_role;
create trigger fc_shipment_live_sync after update of status on public.fc_shipment for each row execute function public.fc_shipment_live_sync();

-- ═══ 3) 도우미 — 문 · 글자 꼴 · 센트 · 유닛 스냅샷 ═══
-- 문(판정 835 · 7): sales 가 있으면 office · 없고 fulfillment 가 있으면 wms(그 창고여야) · 둘 다 없으면 거부 — 창구 첫 줄에서 부른다 · definer 속(authenticated 실행권 없음)
create function public.fc_gate(p_wh uuid, p_verb text default 'saved') returns text
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
begin
  if public.ims_can_write('sales') then return 'office'; end if;
  if public.ims_can_write('fulfillment') then
    if not public.ims_can_warehouse(p_wh) then
      raise exception 'This order belongs to another warehouse — nothing was %', p_verb;
    end if;
    return 'wms';
  end if;
  raise exception 'You cannot work with freight quotes — ask an admin to add the ''sales'' or ''fulfillment'' permission — nothing was %', p_verb;
end;
$$;
revoke all on function public.fc_gate(uuid, text) from public, anon, authenticated, service_role;

create function public.fc_norm(p text) returns text
  language sql immutable
as $$ select lower(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g')); $$;
revoke all on function public.fc_norm(text) from public, anon, authenticated, service_role;

-- 나라 두 글자 — SO 스냅샷에 Canada · CA · CANADA 가 섞여 있다(fc-0 ②)
create function public.fc_country(p text) returns text
  language plpgsql immutable
as $$
declare v text := upper(btrim(coalesce(p, '')));
begin
  if v in ('', 'CA', 'CAN', 'CANADA') then return 'CA'; end if;
  if v in ('US', 'USA', 'UNITED STATES', 'UNITED STATES OF AMERICA') then return 'US'; end if;
  if v ~ '^[A-Z]{2}$' then return v; end if;
  raise exception 'Country "%" is not a two-letter country code — fix the address — nothing was saved', p;
end;
$$;
revoke all on function public.fc_country(text) from public, anon, authenticated, service_role;

-- 전화 — 숫자만 · 북미 11 자리(1 로 시작)는 앞 1 을 뗀다 · 10 자리가 아니면 null(부르는 쪽이 거부한다)
create function public.fc_phone(p text) returns text
  language sql immutable
as $$
  select case when d ~ '^1[0-9]{10}$' then substr(d, 2) when d ~ '^[0-9]{10}$' then d else null end
  from (select regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') as d) t;
$$;
revoke all on function public.fc_phone(text) from public, anon, authenticated, service_role;

-- 돈 → 센트 정수(짐작: value 는 센트 정수 글자) · {currency, value} 또는 글자 · 숫자 둘 다 · 없으면 null
create function public.fc_money_cents(p jsonb) returns bigint
  language sql immutable
as $$
  select case
           when p is null or jsonb_typeof(p) = 'null' then null
           when jsonb_typeof(p) = 'object' then round(nullif(btrim(p->>'value'), '')::numeric)::bigint
           when jsonb_typeof(p) in ('string', 'number') then round(nullif(btrim(p #>> '{}'), '')::numeric)::bigint
         end;
$$;
revoke all on function public.fc_money_cents(jsonb) from public, anon, authenticated, service_role;

-- 유닛 스냅샷 — 이 SO 들이 가진 맨 위 유닛(parent 없음) · in · lb(wms_pallet_dims 가 채운 칸) · 팔렛 안 상자 수
create function public.fc_units_snapshot(p_so_ids uuid[]) returns jsonb
  language sql stable
  set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object('unit_id', u.id, 'label', u.label, 'unit_type', u.unit_type, 'so_id', u.order_id,
                                               'length_in', u.length_in, 'width_in', u.width_in, 'height_in', u.height_in, 'weight_lb', u.weight_lb,
                                               'pieces', (select count(*) from public.wms_pallets b where b.parent_id = u.id)) order by u.id), '[]'::jsonb)
  from public.wms_pallets u
  where u.order_id = any (p_so_ids) and u.parent_id is null;
$$;
revoke all on function public.fc_units_snapshot(uuid[]) from public, anon, authenticated, service_role;

-- ═══ 4) 창구 — prepare · quote_save · select · charge_so_set · for_so · 치수 · 피할 운송사 ═══
-- 4-a prepare: 검사 전부 → 발송 행(스냅샷 · payload) · p_commit false 면 쓰기 0(payload 만) · 살아 있는 발송이 같은 SO 묶음이면 갈아 끼움(옛 견적은 남는다) · 다른 묶음이면 옛 발송 cancelled(superseded_by) · booked 면 거부(취소는 fc-2)
--   p_options: residential · tailgate_required · threshold_delivery(견적 때 바꾼 값 · 없으면 주소 기억 값 → 기본 규칙) · remember(true 면 주소에 굳힘 · 판정 840 「영구」) · ship_date(기본 ims_today)
create function public.fc_shipment_prepare(p_so_ids uuid[], p_options jsonb default '{}'::jsonb, p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_ids      uuid[];
  v_so       public.so%rowtype;
  v_first    public.so%rowtype;
  v_wh       public.ref_warehouse%rowtype;
  v_cust     public.customer%rowtype;
  v_ship_cid uuid;
  v_addr     public.customer_address%rowtype;
  v_addr_n   int := 0;
  v_mode     text;
  v_staff    uuid;
  v_nums     text[] := '{}';
  v_bad      text;
  v_ptype    text;
  v_units    jsonb;
  v_opts     jsonb := coalesce(p_options, '{}'::jsonb);
  v_res      boolean;  v_tail boolean;  v_thr boolean;  v_date date;  v_remember boolean;
  v_phone    text;  v_email text;
  v_orig     jsonb;  v_dest jsonb;  v_req jsonb;  v_hash text;  v_pack jsonb;
  v_locked   boolean := false;  v_lock_reason text;
  v_old      public.fc_shipment%rowtype;
  v_olds     uuid[];
  v_action   text := 'new';
  v_sid      uuid;
  v_warn     text[] := '{}';
  v_carriers jsonb;
  v_id       uuid;
begin
  -- ① 입력 · 잠금(id 순)
  select array_agg(distinct i order by i) into v_ids from unnest(p_so_ids) i where i is not null;
  if coalesce(cardinality(v_ids), 0) = 0 then raise exception 'Choose at least one order — nothing was saved'; end if;
  perform 1 from public.so s where s.id = any (v_ids) order by s.id for update;
  foreach v_id in array v_ids loop
    select * into v_so from public.so s where s.id = v_id;
    if not found then raise exception 'Order % not found — nothing was saved', v_id; end if;
    if v_so.status not in ('picking', 'packed') then
      raise exception 'Order % is % — freight quotes are for orders being finalized or finalized (working · packed) — nothing was saved', v_so.so_number, v_so.status;
    end if;
    if v_so.location_id is null then raise exception 'Order % has no warehouse — nothing was saved', v_so.so_number; end if;
    if v_first.id is null or (v_so.created_at, v_so.so_number) < (v_first.created_at, v_first.so_number) then v_first := v_so; end if;   -- 837: 가장 먼저 만든 SO
    v_nums := array_append(v_nums, v_so.so_number);
  end loop;
  -- ② 문(835 · 7) — 창고는 첫 SO 의 창고 · 다른 창고 SO 가 섞이면 거부
  v_mode := public.fc_gate(v_first.location_id, 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  select string_agg(s.so_number, ', ' order by s.so_number) into v_bad from public.so s where s.id = any (v_ids) and s.location_id is distinct from v_first.location_id;
  if v_bad is not null then raise exception 'Orders % ship from a different warehouse than % — one shipment leaves one warehouse — nothing was saved', v_bad, v_first.so_number; end if;
  -- ③ 같은 배송지(주소 칸 여섯 · 공백 · 대소문자 무시)
  select string_agg(s.so_number, ', ' order by s.so_number) into v_bad from public.so s where s.id = any (v_ids)
   and (public.fc_norm(s.ship_to_line1), public.fc_norm(s.ship_to_line2), public.fc_norm(s.ship_to_city), public.fc_norm(s.ship_to_state_province), public.fc_norm(s.ship_to_postal_code), public.fc_country(s.ship_to_country))
       is distinct from
       (public.fc_norm(v_first.ship_to_line1), public.fc_norm(v_first.ship_to_line2), public.fc_norm(v_first.ship_to_city), public.fc_norm(v_first.ship_to_state_province), public.fc_norm(v_first.ship_to_postal_code), public.fc_country(v_first.ship_to_country));
  if v_bad is not null then raise exception 'Orders % have a different ship-to address than % — one shipment goes to one address — nothing was saved', v_bad, v_first.so_number; end if;
  -- ④ 유닛(838 · 841): 맨 위 유닛 · 상자만 또는 팔렛만 · 치수 · 무게 전부 · 남의 SO 물건이 든 유닛은 그 SO 도 함께
  v_units := public.fc_units_snapshot(v_ids);
  if jsonb_array_length(v_units) = 0 then raise exception 'No pallets or boxes yet for % — pack the order into units first — nothing was saved', array_to_string(v_nums, ', '); end if;
  select string_agg(s.so_number, ', ' order by s.so_number) into v_bad from public.so s where s.id = any (v_ids)
   and not exists (select 1 from public.wms_pallets u where u.order_id = s.id)
   and not exists (select 1 from public.wms_pallet_items i where i.order_id = s.id);
  if v_bad is not null then raise exception 'Orders % have no pallet or box — nothing was saved', v_bad; end if;
  select string_agg(distinct e->>'unit_type', ' + ') into v_bad from jsonb_array_elements(v_units) e;
  if v_bad like '%+%' then raise exception 'This shipment mixes boxes and pallets (%) — one shipment is all boxes or all pallets — nothing was saved', v_bad; end if;
  v_ptype := case when v_bad = 'pallet' then 'pallet' else 'package' end;
  select string_agg(coalesce(e->>'label', '#' || (e->>'unit_id')), ', ' order by (e->>'unit_id')::bigint) into v_bad from jsonb_array_elements(v_units) e
   where e->>'length_in' is null or e->>'width_in' is null or e->>'height_in' is null or e->>'weight_lb' is null;
  if v_bad is not null then raise exception 'Units % need length, width, height and weight before a quote — nothing was saved', v_bad; end if;
  select string_agg(distinct s.so_number, ', ') into v_bad
    from public.wms_pallet_items i join public.so s on s.id = i.order_id
   where i.order_id is not null and not (i.order_id = any (v_ids))
     and i.pallet_id in (select u.id from public.wms_pallets u where (u.order_id = any (v_ids) and u.parent_id is null)
                           or u.parent_id in (select u2.id from public.wms_pallets u2 where u2.order_id = any (v_ids) and u2.parent_id is null));
  if v_bad is not null then raise exception 'These units also hold goods of % — include those orders in the shipment — nothing was saved', v_bad; end if;
  -- ⑤ 출발지 — SO 창고
  select * into v_wh from public.ref_warehouse w where w.id = v_first.location_id;
  if nullif(btrim(v_wh.address_line1), '') is null or nullif(btrim(v_wh.city), '') is null or nullif(btrim(v_wh.state_province), '') is null or nullif(btrim(v_wh.postal_code), '') is null then
    raise exception 'Warehouse % has no full address (street · city · province · postal code) — set it in Settings — nothing was saved', v_wh.name;
  end if;
  if public.fc_phone(v_wh.phone) is null then raise exception 'Warehouse % needs a 10-digit phone number for the carrier — set it in Settings — nothing was saved', v_wh.name; end if;
  v_orig := jsonb_strip_nulls(jsonb_build_object(
    'name', v_wh.name,
    'address', jsonb_build_object('address_line_1', btrim(v_wh.address_line1), 'address_line_2', nullif(btrim(v_wh.address_line2), ''), 'city', btrim(v_wh.city),
                                  'region', upper(btrim(v_wh.state_province)), 'country', public.fc_country(v_wh.country), 'postal_code', upper(regexp_replace(v_wh.postal_code, '\s+', '', 'g'))),
    'residential', false, 'tailgate_required', false,
    'contact_name', nullif(btrim(v_wh.contact_name), ''),
    'phone_number', jsonb_build_object('number', public.fc_phone(v_wh.phone)),
    'email_addresses', case when nullif(btrim(v_wh.email), '') is null then null else jsonb_build_array(btrim(v_wh.email)) end));
  -- ⑥ 도착지 — SO 스냅샷 · 전화는 SO → 손님 기본 연락처 · 이메일은 기본 연락처 · 주소 기억 값은 배송 손님의 활성 주소 가운데 (line1, postal) 로 하나만 맞을 때
  select * into v_cust from public.customer c where c.id = v_first.customer_id;
  v_ship_cid := coalesce(v_cust.default_ship_to_customer_id, v_cust.id);
  if nullif(btrim(v_first.ship_to_line1), '') is null or nullif(btrim(v_first.ship_to_city), '') is null or nullif(btrim(v_first.ship_to_state_province), '') is null or nullif(btrim(v_first.ship_to_postal_code), '') is null then
    raise exception 'Order % has no full ship-to address (street · city · province · postal code) — nothing was saved', v_first.so_number;
  end if;
  v_phone := public.fc_phone(v_first.ship_to_phone);
  if v_phone is null then
    select public.fc_phone(coalesce(k.phone, k.mobile_phone)) into v_phone from public.customer_contact k
     where k.customer_id = v_ship_cid and k.is_active and public.fc_phone(coalesce(k.phone, k.mobile_phone)) is not null order by k.is_default desc, k.created_at limit 1;
  end if;
  if v_phone is null then raise exception 'Order % has no 10-digit phone for the carrier — add one to the ship-to or the customer contact — nothing was saved', v_first.so_number; end if;
  select nullif(btrim(k.email), '') into v_email from public.customer_contact k where k.customer_id = v_ship_cid and k.is_active and nullif(btrim(k.email), '') is not null order by k.is_default desc, k.created_at limit 1;
  select count(*), min(a.id::text)::uuid into v_addr_n, v_id from public.customer_address a
   where a.customer_id = v_ship_cid and a.is_active and a.type in ('Shipping', 'Business')
     and public.fc_norm(a.line1) = public.fc_norm(v_first.ship_to_line1) and public.fc_norm(a.postal_code) = public.fc_norm(v_first.ship_to_postal_code);
  if v_addr_n = 1 then select * into v_addr from public.customer_address a where a.id = v_id; else v_addr := null; end if;
  -- 조건(839 · 840): 견적 때 준 값 → 주소 기억 값 → 기본(회사 = ship_to_company 가 찼다 → 상업지)
  v_res  := coalesce(nullif(btrim(v_opts->>'residential'), '')::boolean,        v_addr.residential,        v_first.ship_to_company is null);
  v_tail := coalesce(nullif(btrim(v_opts->>'tailgate_required'), '')::boolean,  v_addr.tailgate_required,  false);
  v_thr  := coalesce(nullif(btrim(v_opts->>'threshold_delivery'), '')::boolean, v_addr.threshold_delivery, false);
  v_date := coalesce(nullif(btrim(v_opts->>'ship_date'), '')::date, public.ims_today());
  v_remember := coalesce(nullif(btrim(v_opts->>'remember'), '')::boolean, false);
  if v_remember and v_addr.id is null then v_warn := array_append(v_warn, case when v_addr_n = 0 then 'address_not_found' else 'address_ambiguous' end); end if;
  v_dest := jsonb_strip_nulls(jsonb_build_object(
    'name', coalesce(nullif(btrim(v_first.ship_to_company), ''), nullif(btrim(v_first.ship_to_contact), ''), v_cust.name),
    'address', jsonb_build_object('address_line_1', btrim(v_first.ship_to_line1), 'address_line_2', nullif(btrim(v_first.ship_to_line2), ''), 'city', btrim(v_first.ship_to_city),
                                  'region', upper(btrim(v_first.ship_to_state_province)), 'country', public.fc_country(v_first.ship_to_country), 'postal_code', upper(regexp_replace(v_first.ship_to_postal_code, '\s+', '', 'g'))),
    'residential', v_res, 'tailgate_required', v_tail,
    'contact_name', nullif(btrim(v_first.ship_to_contact), ''),
    'phone_number', jsonb_build_object('number', v_phone),
    'email_addresses', case when v_email is null then null else jsonb_build_array(v_email) end));
  -- ⑦ 포장(838) — in · lb 그대로 · 팔렛은 ltl · 안 쌓음 · num_pieces = 안의 상자 수(없으면 1) · freight_class 는 EF 가 · 인사이드는 팔렛에만(840)
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'measurements', jsonb_build_object('weight', jsonb_build_object('unit', 'lb', 'value', trim_scale((e->>'weight_lb')::numeric)),
                                              'cuboid', jsonb_build_object('unit', 'in', 'l', trim_scale((e->>'length_in')::numeric), 'w', trim_scale((e->>'width_in')::numeric), 'h', trim_scale((e->>'height_in')::numeric))),
           'description', coalesce(e->>'label', e->>'unit_type'),
           'num_pieces', case when v_ptype = 'pallet' then greatest((e->>'pieces')::int, 1) end)) order by (e->>'unit_id')::bigint)
    into v_pack from jsonb_array_elements(v_units) e;
  v_req := jsonb_build_object('details', jsonb_build_object(
    'origin', v_orig, 'destination', v_dest,
    'expected_ship_date', jsonb_build_object('year', extract(year from v_date)::int, 'month', extract(month from v_date)::int, 'day', extract(day from v_date)::int),
    'packaging_type', v_ptype,
    'packaging_properties', case when v_ptype = 'pallet'
      then jsonb_build_object('pallet_type', 'ltl', 'has_stackable_pallets', false, 'pallets', v_pack, 'pallet_service_details', jsonb_build_object('threshold_delivery', v_thr))
      else jsonb_build_object('packages', v_pack) end));
  v_hash := md5(v_req::text);
  -- ⑧ 836: 손님이 Shopify 에서 운임을 결제한 웹 오더(aone 스토어)가 하나라도 들면 운임 줄을 덮지 않는다
  select string_agg(o.name, ', ') into v_lock_reason from public.shop_order o join public.shop_store st on st.id = o.store_id where o.so_id = any (v_ids) and st.kind = 'aone';
  v_locked := v_lock_reason is not null;
  if v_locked then v_lock_reason := 'customer paid freight in Shopify (' || v_lock_reason || ')'; end if;
  select coalesce(jsonb_agg(c.freightcom_carrier order by c.freightcom_carrier), '[]'::jsonb) into v_carriers from public.ref_carrier c where c.is_active and c.freightcom_carrier is not null;
  -- ⑨ 살아 있는 발송 — booked 거부 · 같은 묶음 하나면 갈아 끼움 · 그 밖은 superseded
  select array_agg(distinct l.shipment_id) into v_olds from public.fc_shipment_so l where l.so_id = any (v_ids) and l.live;
  if v_olds is not null then
    select string_agg(s.so_number, ', ') into v_bad from public.fc_shipment_so l join public.so s on s.id = l.so_id join public.fc_shipment f on f.id = l.shipment_id where l.shipment_id = any (v_olds) and f.status = 'booked';
    if v_bad is not null then raise exception 'Orders % are on a booked shipment — cancel the booking first — nothing was saved', v_bad; end if;
    if cardinality(v_olds) = 1 and (select array_agg(l.so_id order by l.so_id) from public.fc_shipment_so l where l.shipment_id = v_olds[1] and l.live) = v_ids then
      v_action := 'replace';  v_sid := v_olds[1];
    else
      v_action := 'supersede';
    end if;
  end if;
  -- ⑩ 쓰기(p_commit)
  if p_commit then
    if v_action = 'supersede' then
      update public.fc_shipment f set status = 'cancelled', cancelled_at = now(), cancel_reason = 'superseded', updated_by = v_staff where f.id = any (v_olds);
    end if;
    if v_action = 'replace' then
      update public.fc_shipment f set status = 'draft', selected_rate_id = null, origin_warehouse_id = v_first.location_id, packaging_type = v_ptype,
        charge_so_id = case when f.charge_so_id = any (v_ids) then f.charge_so_id else v_first.id end, customer_id = v_first.customer_id,                 -- 갈아 끼울 때 오피스가 옮긴 charge SO 는 지킨다(837)
        address_id = v_addr.id, freight_locked = v_locked, freight_locked_reason = v_lock_reason, origin = v_orig, destination = v_dest,
        options = jsonb_build_object('residential', v_res, 'tailgate_required', v_tail, 'threshold_delivery', v_thr, 'ship_date', v_date),
        units = v_units, request = v_req, payload_hash = v_hash, updated_by = v_staff
      where f.id = v_sid;
    else
      insert into public.fc_shipment (origin_warehouse_id, packaging_type, charge_so_id, customer_id, address_id, freight_locked, freight_locked_reason, origin, destination, options, units, request, payload_hash, created_in, created_by, updated_by)
      values (v_first.location_id, v_ptype, v_first.id, v_first.customer_id, v_addr.id, v_locked, v_lock_reason, v_orig, v_dest,
              jsonb_build_object('residential', v_res, 'tailgate_required', v_tail, 'threshold_delivery', v_thr, 'ship_date', v_date), v_units, v_req, v_hash, v_mode, v_staff, v_staff)
      returning id into v_sid;
      insert into public.fc_shipment_so (shipment_id, so_id) select v_sid, i from unnest(v_ids) i;
      if v_action = 'supersede' then update public.fc_shipment f set superseded_by = v_sid where f.id = any (v_olds); end if;
    end if;
    if v_remember and v_addr.id is not null then
      update public.customer_address a set residential = v_res, tailgate_required = v_tail, threshold_delivery = v_thr, updated_by = v_staff where a.id = v_addr.id;
    end if;
  end if;
  return jsonb_build_object('committed', p_commit, 'action', v_action, 'shipment_id', v_sid, 'mode', v_mode, 'packaging_type', v_ptype,
                            'charge_so_id', (select f.charge_so_id from public.fc_shipment f where f.id = v_sid), 'charge_so_number', (select s.so_number from public.fc_shipment f join public.so s on s.id = f.charge_so_id where f.id = v_sid), 'first_so_number', v_first.so_number, 'so_ids', to_jsonb(v_ids), 'so_numbers', to_jsonb(v_nums),
                            'options', jsonb_build_object('residential', v_res, 'tailgate_required', v_tail, 'threshold_delivery', v_thr, 'ship_date', v_date, 'remember', v_remember),
                            'address_id', v_addr.id, 'freight_locked', v_locked, 'freight_locked_reason', v_lock_reason,
                            'units', v_units, 'request', v_req, 'payload_hash', v_hash, 'carriers', v_carriers, 'warnings', to_jsonb(v_warn));
end;
$$;
revoke all on function public.fc_shipment_prepare(uuid[], jsonb, boolean) from public, anon, service_role;
grant execute on function public.fc_shipment_prepare(uuid[], jsonb, boolean) to authenticated;
comment on function public.fc_shipment_prepare(uuid[], jsonb, boolean) is 'fc-1a 판정 835 ~ 841: 견적 준비 — 검사(같은 창고 · 같은 배송지 · 상자만/팔렛만 · 치수 · 무게 전부 · 남의 SO 물건 든 유닛 · 전화 10 자리 · 주소 전부) → 발송 행 + Freightcom /rate payload(DB 가 만든다 · EF 는 나른다 · services 는 EF 가 carriers[] 로) · 문 = sales 또는 fulfillment + 그 창고 · 조건 = p_options → 주소 기억 값 → 기본(회사면 상업지) · remember 면 주소에 굳힘 · 살아 있는 발송: booked 거부 · 같은 묶음이면 갈아 끼움(옛 견적 남음) · 다른 묶음이면 superseded · p_commit false = 쓰기 0';

-- 4-b quote_save: EF(service_role) 또는 직원 — 응답 원문을 남기고 rates 를 줄로 · 836 셈 · 843 avoided · preselected · 발송 draft → quoted(새 견적은 고른 줄을 푼다)
create function public.fc_quote_save(p_shipment_id uuid, p_request_id text, p_response jsonb, p_error text default null) returns jsonb
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
begin
  select * into v_f from public.fc_shipment f where f.id = p_shipment_id for update;
  if not found then raise exception 'Shipment % not found — nothing was saved', p_shipment_id; end if;
  if v_role <> 'service_role' then perform public.fc_gate(v_f.origin_warehouse_id, 'saved'); end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_f.status in ('booked', 'cancelled') then raise exception 'Shipment is % — no new quotes — nothing was saved', v_f.status; end if;
  if p_error is not null then
    insert into public.fc_quote (shipment_id, request_id, status, request, error, done_at, by_staff) values (p_shipment_id, p_request_id, 'error', v_f.request, left(p_error, 1000), now(), v_staff) returning id into v_qid;
    return jsonb_build_object('quote_id', v_qid, 'status', 'error', 'rates', 0);
  end if;
  if p_response is null or jsonb_typeof(coalesce(p_response->'rates', 'null'::jsonb)) <> 'array' then raise exception 'The quote response has no rates[] — nothing was saved'; end if;
  v_pct := coalesce((select c.value::numeric from public.inv_config c where c.key = 'fc_markup_pct'), 0);
  select c.default_carrier_id into v_defc from public.customer c where c.id = v_f.customer_id;
  insert into public.fc_quote (shipment_id, request_id, status, request, response, done_at, by_staff) values (p_shipment_id, p_request_id, 'done', v_f.request, p_response, now(), v_staff) returning id into v_qid;
  for v_r in select t.rate, t.ord from jsonb_array_elements(p_response->'rates') with ordinality as t(rate, ord) loop
    if nullif(btrim(v_r.rate->>'service_id'), '') is null then continue; end if;
    v_base  := public.fc_money_cents(v_r.rate->'base');
    v_sur   := coalesce((select sum(public.fc_money_cents(s->'amount')) from jsonb_array_elements(coalesce(nullif(v_r.rate->'surcharges', 'null'::jsonb), '[]'::jsonb)) s), 0);
    v_tax   := coalesce((select sum(public.fc_money_cents(s->'amount')) from jsonb_array_elements(coalesce(nullif(v_r.rate->'taxes', 'null'::jsonb), '[]'::jsonb)) s), 0);
    v_total := public.fc_money_cents(v_r.rate->'total');
    v_pre   := coalesce(v_base, 0) + v_sur;
    select c.id into v_cid from public.ref_carrier c where c.freightcom_carrier is not null and lower(btrim(c.freightcom_carrier)) = lower(btrim(coalesce(v_r.rate->>'carrier_name', ''))) limit 1;
    v_vu := case when jsonb_typeof(v_r.rate->'valid_until') = 'object' and (v_r.rate->'valid_until'->>'year') ~ '^[0-9]+$'
                 then make_date((v_r.rate->'valid_until'->>'year')::int, (v_r.rate->'valid_until'->>'month')::int, (v_r.rate->'valid_until'->>'day')::int) end;
    insert into public.fc_quote_rate (quote_id, service_id, carrier_name, service_name, carrier_id, base_cents, surcharge_cents, tax_cents, total_cents, pretax_cents, markup_pct, customer_charge_cents, transit_days, valid_until, avoided, totals_mismatch, raw)
    values (v_qid, btrim(v_r.rate->>'service_id'), nullif(btrim(v_r.rate->>'carrier_name'), ''), nullif(btrim(v_r.rate->>'service_name'), ''), v_cid, v_base, v_sur, v_tax, v_total, v_pre, v_pct,
            round(v_pre * (1 + v_pct / 100))::bigint,                                                                     -- 836: 세전 × (1 + 마크업) · 센트 반올림
            case when (v_r.rate->>'transit_time_days') ~ '^[0-9]+$' then (v_r.rate->>'transit_time_days')::int end, v_vu,
            v_cid is not null and exists (select 1 from public.customer_carrier_avoid a where a.customer_id = v_f.customer_id and a.carrier_id = v_cid),   -- 843
            v_total is not null and v_total <> v_pre + v_tax, v_r.rate);
    v_n := v_n + 1;
  end loop;
  -- 843 미리 고르기 — 피할 것 · 짝 없는 것 제외 · 손님 기본 운송사에 줄이 있으면 그 가운데 최저 · 없으면 전체 최저
  v_use_def := v_defc is not null and exists (select 1 from public.fc_quote_rate q where q.quote_id = v_qid and not q.avoided and q.carrier_id = v_defc);
  select q.id into v_pre_id from public.fc_quote_rate q where q.quote_id = v_qid and not q.avoided and q.carrier_id is not null and (not v_use_def or q.carrier_id = v_defc)
   order by q.pretax_cents, q.service_id limit 1;
  if v_pre_id is not null then update public.fc_quote_rate set preselected = true where id = v_pre_id; end if;
  update public.fc_shipment f set status = 'quoted', selected_rate_id = null, updated_by = coalesce(v_staff, f.updated_by) where f.id = p_shipment_id;
  return jsonb_build_object('quote_id', v_qid, 'status', 'done', 'rates', v_n, 'preselected_rate_id', v_pre_id, 'freight_locked', v_f.freight_locked, 'markup_pct', v_pct);
end;
$$;
revoke all on function public.fc_quote_save(uuid, text, jsonb, text) from public, anon;
grant execute on function public.fc_quote_save(uuid, text, jsonb, text) to authenticated, service_role;
comment on function public.fc_quote_save(uuid, text, jsonb, text) is 'fc-1a: 견적 결과 저장 — EF(service_role · 문 없음) 또는 직원(fc_gate) · 응답 원문 fc_quote.response · rates[] → fc_quote_rate(센트 · pretax = base + 할증 · customer_charge = round(pretax × (1 + fc_markup_pct %)) 836 · carrier_id 짝 · avoided 843 · totals_mismatch) · preselected(기본 운송사 중 최저 → 전체 최저) · 발송 quoted · 고른 줄 풀림 · p_error 면 error 견적만';

-- 4-c select: 사람이 고른다 — 마지막 done 견적의 줄 · 피할 운송사 · 짝 없는 운송사 거부
create function public.fc_quote_select(p_shipment_id uuid, p_rate_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_f   public.fc_shipment%rowtype;
  v_r   public.fc_quote_rate%rowtype;
  v_qid uuid;
  v_staff uuid;
begin
  select * into v_f from public.fc_shipment f where f.id = p_shipment_id for update;
  if not found then raise exception 'Shipment % not found — nothing was saved', p_shipment_id; end if;
  perform public.fc_gate(v_f.origin_warehouse_id, 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_f.status not in ('quoted', 'selected') then raise exception 'Shipment is % — get a quote first — nothing was saved', v_f.status; end if;
  select q.id into v_qid from public.fc_quote q where q.shipment_id = p_shipment_id and q.status = 'done' order by q.requested_at desc, q.id desc limit 1;
  select * into v_r from public.fc_quote_rate r where r.id = p_rate_id and r.quote_id = v_qid;
  if not found then raise exception 'That rate is not on the latest quote of this shipment — quote again — nothing was saved'; end if;
  if v_r.avoided then raise exception 'This customer avoids % — pick another rate — nothing was saved', v_r.carrier_name; end if;
  if v_r.carrier_id is null then raise exception 'Carrier "%" is not on the IMS carrier list — add it in Settings (Freightcom name) before choosing it — nothing was saved', v_r.carrier_name; end if;
  update public.fc_shipment f set status = 'selected', selected_rate_id = v_r.id, updated_by = v_staff where f.id = p_shipment_id;
  return jsonb_build_object('shipment_id', p_shipment_id, 'selected_rate_id', v_r.id, 'carrier_id', v_r.carrier_id, 'service_id', v_r.service_id,
                            'customer_charge_cents', v_r.customer_charge_cents, 'charge_amount', case when v_f.freight_locked then null else round(v_r.customer_charge_cents / 100.0, 2) end,
                            'freight_locked', v_f.freight_locked, 'charge_so_id', v_f.charge_so_id);
end;
$$;
revoke all on function public.fc_quote_select(uuid, uuid) from public, anon, service_role;
grant execute on function public.fc_quote_select(uuid, uuid) to authenticated;
comment on function public.fc_quote_select(uuid, uuid) is 'fc-1a 판정 843: 견적 줄 고르기 — 마지막 done 견적의 줄만 · avoided · 짝 없는 운송사 거부 · 발송 selected · charge_amount = 운임 줄에 넣을 달러(freight_locked 면 null · 836)';

-- 4-d charge_so_set: 837 — 운임 줄을 받을 SO 옮기기(sales 만 · 창고 문 없음)
create function public.fc_charge_so_set(p_shipment_id uuid, p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_f public.fc_shipment%rowtype;  v_staff uuid;  v_num text;
begin
  perform public.ims_require_write('sales');
  select * into v_f from public.fc_shipment f where f.id = p_shipment_id for update;
  if not found then raise exception 'Shipment % not found — nothing was saved', p_shipment_id; end if;
  if v_f.status = 'cancelled' then raise exception 'Shipment is cancelled — nothing was saved'; end if;
  select s.so_number into v_num from public.fc_shipment_so l join public.so s on s.id = l.so_id where l.shipment_id = p_shipment_id and l.so_id = p_so_id and l.live;
  if v_num is null then raise exception 'That order is not on this shipment — nothing was saved'; end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  update public.fc_shipment f set charge_so_id = p_so_id, updated_by = v_staff where f.id = p_shipment_id and f.charge_so_id is distinct from p_so_id;
  return jsonb_build_object('shipment_id', p_shipment_id, 'charge_so_id', p_so_id, 'charge_so_number', v_num);
end;
$$;
revoke all on function public.fc_charge_so_set(uuid, uuid) from public, anon, service_role;
grant execute on function public.fc_charge_so_set(uuid, uuid) to authenticated;
comment on function public.fc_charge_so_set(uuid, uuid) is 'fc-1a 판정 837: 발송의 운임 줄을 받을 SO 를 옮긴다(sales · 발송에 든 살아 있는 SO 만)';

-- 4-e for_so: 읽기 — 화면 둘(Finalize · Ship & invoice)이 쓰는 한 모양 · 발송 없음 = null + 지금 유닛 상태
create function public.fc_shipment_for_so(p_so_id uuid) returns jsonb
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
  select coalesce(jsonb_agg(jsonb_build_object('so_id', s.id, 'so_number', s.so_number, 'status', s.status, 'is_charge_so', s.id = v_f.charge_so_id) order by s.created_at, s.so_number), '[]'::jsonb)
    into v_sos from public.fc_shipment_so l join public.so s on s.id = l.so_id where l.shipment_id = v_f.id and l.live;
  select * into v_q from public.fc_quote q where q.shipment_id = v_f.id order by q.requested_at desc, q.id desc limit 1;
  if v_q.id is not null and v_q.status = 'done' then
    select coalesce(jsonb_agg(jsonb_build_object('rate_id', r.id, 'service_id', r.service_id, 'carrier_name', r.carrier_name, 'service_name', r.service_name, 'carrier_id', r.carrier_id,
                                                 'base_cents', r.base_cents, 'surcharge_cents', r.surcharge_cents, 'tax_cents', r.tax_cents, 'total_cents', r.total_cents, 'pretax_cents', r.pretax_cents,
                                                 'customer_charge_cents', r.customer_charge_cents, 'transit_days', r.transit_days, 'valid_until', r.valid_until,
                                                 'avoided', r.avoided, 'preselected', r.preselected, 'selectable', (not r.avoided and r.carrier_id is not null), 'totals_mismatch', r.totals_mismatch,
                                                 'selected', r.id = v_f.selected_rate_id)
                              order by r.avoided, (r.carrier_id is null), r.pretax_cents, r.service_id), '[]'::jsonb)
      into v_rates from public.fc_quote_rate r where r.quote_id = v_q.id;
  end if;
  if v_f.selected_rate_id is not null then select * into v_sel from public.fc_quote_rate r where r.id = v_f.selected_rate_id; end if;
  select public.fc_units_snapshot(array(select l.so_id from public.fc_shipment_so l where l.shipment_id = v_f.id and l.live)) into v_units;
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number,
    'shipment', jsonb_build_object('id', v_f.id, 'status', v_f.status, 'packaging_type', v_f.packaging_type, 'origin_warehouse_id', v_f.origin_warehouse_id,
                                   'charge_so_id', v_f.charge_so_id, 'customer_id', v_f.customer_id, 'address_id', v_f.address_id,
                                   'freight_locked', v_f.freight_locked, 'freight_locked_reason', v_f.freight_locked_reason,
                                   'origin', v_f.origin, 'destination', v_f.destination, 'options', v_f.options, 'units', v_f.units, 'request', v_f.request, 'payload_hash', v_f.payload_hash,
                                   'created_in', v_f.created_in, 'created_by', v_f.created_by, 'created_at', v_f.created_at, 'updated_at', v_f.updated_at),
    'orders', v_sos,
    'quote', case when v_q.id is null then null else jsonb_build_object('id', v_q.id, 'status', v_q.status, 'request_id', v_q.request_id, 'error', v_q.error, 'requested_at', v_q.requested_at, 'done_at', v_q.done_at, 'rates', coalesce(v_rates, '[]'::jsonb)) end,
    'selected', case when v_sel.id is null then null else jsonb_build_object('rate_id', v_sel.id, 'carrier_id', v_sel.carrier_id, 'carrier_name', v_sel.carrier_name, 'service_id', v_sel.service_id, 'service_name', v_sel.service_name,
                                                                        'customer_charge_cents', v_sel.customer_charge_cents, 'pretax_cents', v_sel.pretax_cents) end,
    'charge_amount', case when v_sel.id is null or v_f.freight_locked then null else round(v_sel.customer_charge_cents / 100.0, 2) end,
    'units_now', v_units, 'units_changed', (v_units <> v_f.units),
    'units_without_dims', (select count(*) from jsonb_array_elements(v_units) e where e->>'length_in' is null or e->>'width_in' is null or e->>'height_in' is null or e->>'weight_lb' is null),
    'markup_pct', (select c.value::numeric from public.inv_config c where c.key = 'fc_markup_pct'));
end;
$$;
revoke all on function public.fc_shipment_for_so(uuid) from public, anon, service_role;
grant execute on function public.fc_shipment_for_so(uuid) to authenticated;
comment on function public.fc_shipment_for_so(uuid) is 'fc-1a: 한 SO 의 살아 있는 발송 · SO 목록(charge SO 표시) · 조건 · 보낸 유닛 · 마지막 견적의 줄(avoided · preselected · selectable · selected) · 고른 줄 · charge_amount(운임 줄 달러 · freight_locked 면 null) · units_now · units_changed(견적 뒤 유닛이 바뀌었나) · 발송 없으면 shipment null + 지금 유닛';

-- 4-f 치수(841 오피스): 창고 화면과 같은 칸 · 같은 CHECK · 같은 트리거(wms_pallet_dims) — 문은 fulfillment(그 창고) 또는 sales
create function public.wms_unit_dims_set(p_unit_id bigint, p jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_u public.wms_pallets%rowtype;  v_wh uuid;
begin
  select * into v_u from public.wms_pallets u where u.id = p_unit_id for update;
  if not found then raise exception 'Unit % not found — nothing was saved', p_unit_id; end if;
  select coalesce((select s.location_id from public.so s where s.id = v_u.order_id), (select t.from_warehouse_id from public.inv_transfer t where t.id = v_u.transfer_id)) into v_wh;
  perform public.fc_gate(v_wh, 'saved');
  update public.wms_pallets u set
    dim_length  = case when p ? 'dim_length'  then nullif(btrim(p->>'dim_length'), '')::numeric  else u.dim_length  end,
    dim_width   = case when p ? 'dim_width'   then nullif(btrim(p->>'dim_width'), '')::numeric   else u.dim_width   end,
    dim_height  = case when p ? 'dim_height'  then nullif(btrim(p->>'dim_height'), '')::numeric  else u.dim_height  end,
    dim_unit    = case when p ? 'dim_unit'    then nullif(btrim(p->>'dim_unit'), '')             else u.dim_unit    end,
    weight      = case when p ? 'weight'      then nullif(btrim(p->>'weight'), '')::numeric      else u.weight      end,
    weight_unit = case when p ? 'weight_unit' then nullif(btrim(p->>'weight_unit'), '')          else u.weight_unit end
  where u.id = p_unit_id
  returning * into v_u;
  return jsonb_build_object('unit_id', v_u.id, 'label', v_u.label, 'unit_type', v_u.unit_type, 'dim_length', v_u.dim_length, 'dim_width', v_u.dim_width, 'dim_height', v_u.dim_height, 'dim_unit', v_u.dim_unit,
                            'weight', v_u.weight, 'weight_unit', v_u.weight_unit, 'length_in', v_u.length_in, 'width_in', v_u.width_in, 'height_in', v_u.height_in, 'weight_lb', v_u.weight_lb);
end;
$$;
revoke all on function public.wms_unit_dims_set(bigint, jsonb) from public, anon, service_role;
grant execute on function public.wms_unit_dims_set(bigint, jsonb) to authenticated;
comment on function public.wms_unit_dims_set(bigint, jsonb) is 'fc-1a 판정 841: 유닛 치수 · 무게 넣기 — 열쇠가 온 칸만(dim_length · dim_width · dim_height · dim_unit in|cm · weight · weight_unit lb|kg · '''' 은 비움) · 같은 CHECK · 트리거가 in · lb 를 채운다 · 문 = sales 또는 fulfillment + 그 창고(창고 화면의 직접 쓰기는 그대로 · 판정 6)';

-- 4-g 피할 운송사(843): 손님의 목록을 통째로 바꾼다(sales)
create function public.customer_carrier_avoid_set(p_customer_id uuid, p_carrier_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid;  v_ids uuid[];  v_bad text;
begin
  perform public.ims_require_write('sales');
  if not exists (select 1 from public.customer c where c.id = p_customer_id) then raise exception 'Customer % not found — nothing was saved', p_customer_id; end if;
  select array_agg(distinct i) into v_ids from unnest(coalesce(p_carrier_ids, '{}'::uuid[])) i where i is not null;
  select string_agg(i::text, ', ') into v_bad from unnest(coalesce(v_ids, '{}'::uuid[])) i where not exists (select 1 from public.ref_carrier c where c.id = i and c.kind = 'carrier');
  if v_bad is not null then raise exception 'Carrier(s) % are not on the carrier list (Pickup · Delivery cannot be avoided) — nothing was saved', v_bad; end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  delete from public.customer_carrier_avoid a where a.customer_id = p_customer_id and not (a.carrier_id = any (coalesce(v_ids, '{}'::uuid[])));
  insert into public.customer_carrier_avoid (customer_id, carrier_id, created_by) select p_customer_id, i, v_staff from unnest(coalesce(v_ids, '{}'::uuid[])) i on conflict do nothing;
  return jsonb_build_object('customer_id', p_customer_id, 'carrier_ids', (select coalesce(jsonb_agg(a.carrier_id order by a.carrier_id), '[]'::jsonb) from public.customer_carrier_avoid a where a.customer_id = p_customer_id));
end;
$$;
revoke all on function public.customer_carrier_avoid_set(uuid, uuid[]) from public, anon, service_role;
grant execute on function public.customer_carrier_avoid_set(uuid, uuid[]) to authenticated;
comment on function public.customer_carrier_avoid_set(uuid, uuid[]) is 'fc-1a 판정 843: 손님이 피할 운송사 목록을 통째로(sales · kind carrier 만) · 견적 줄의 avoided 가 이 표를 본다';

-- ═══ 5) 재발행 둘 — customer_update(주소 조건 열쇠 셋 · 20261024174246:73 바이트 복사 + 네 자리) · ims_config_set(fc_markup_pct master · 20261024233000:117 바이트 복사 + 두 자리) ═══
create or replace function public.customer_update(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_master   boolean;
  v_mgr_ok   boolean;                                                              -- mail-4a 판정 517: manager 이상인가
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_reviewed uuid[] := '{}';
  v_money    text[] := array['price_tier', 'discount_pct', 'payment_term_id', 'currency_id', 'ar_account_id', 'sale_account_id', 'default_bill_to_customer_id', 'invoice_split_by_store', 'is_active'];   -- 판정 241(cs-3): 켜기 · 끄기도 master 만 · 판정 254(cs-par-1): is_bill_parent 는 뺐다(받은 값을 비춰 둘 뿐 · 적재가 매번 덮는다)
  v_general  text[] := array['name', 'display_name', 'note', 'tax_rule', 'default_location_id', 'default_carrier', 'tax_number', 'tags', 'is_legal_entity', 'default_ship_to_customer_id'];   -- 판정 252(cs-par-1): parent_id 는 v_struct 로
  v_struct   text[] := array['parent_id'];   -- cs-par-1 판정 252(이견 5) — 문은 master(돈 칸과 같은 문) · 저장은 reviewed · open_so_keep_old 경고 없이(오더에 복사되는 조건이 아니다)
  v_mgr      text[] := array['backorder_mail', 'final_invoice_mail'];   -- mail-4a 판정 507 · 517: 백오더 알림 받기 — 값이 바뀔 때만 manager 이상(sales 는 보기만 · 판정 237 의 일반 칸 = sales 의 예외) · doc-3a 판정 529: 최종 인보이스 자동 메일도 같은 결
  v_afields  text[] := array['type', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country', 'label', 'residential', 'tailgate_required', 'threshold_delivery'];   -- fc-1a 판정 839 · 840: 배송 조건 셋
  v_cfields  text[] := array['name', 'phone', 'mobile_phone', 'fax', 'email', 'website', 'job_title', 'include_in_email', 'marketing_consent'];
  v_n        int;
  v_i        int := 0;
  v_c        jsonb;
  v_op       text;
  v_field    text;
  v_cid      uuid;
  v_key      text;
  v_cust     public.customer%rowtype;
  v_cur      text;
  v_new      text;
  v_num      numeric;
  v_seen     text[] := '{}';
  v_touched  uuid[] := '{}';
  v_money_ok uuid[] := '{}';
  v_addr_ch  uuid[] := '{}';
  v_tier     public.ref_price_tier%rowtype;
  v_term     public.ref_payment_term%rowtype;
  v_curr     public.ref_currency%rowtype;
  v_acct     public.ref_account%rowtype;
  v_wh       public.ref_warehouse%rowtype;
  v_other    public.customer%rowtype;
  v_a        public.customer_address%rowtype;
  v_ct       public.customer_contact%rowtype;
  v_vals     jsonb;
  v_olds     jsonb;
  v_f        text;
  v_folded   text;
  v_n_act    int;
  v_n_off    int;
  v_matches  jsonb;
  v_open_so  int;
  v_open_inv int;
  v_inv_due  numeric;
  v_bal      numeric;
  v_kids     int;
  v_consent  text;
  v_keys     text[];
  v_unacked  text[];
  v_rid      uuid;
  v_newdef   text[] := '{}';   -- 이 호출이 새 기본을 세우는 자리 — <customer_id>:<type>(주소) · <customer_id>(연락처) — 그 자리의 옛 기본을 끄는 op 는 알리지 않는다
begin
  -- ⭐ 문(판정 237) — sales 또는 master 쓰기 · 문장은 ims_require_write 모양(2a 와 같다)
  if not (public.ims_can_write('sales') or public.ims_can_write('master')) then
    raise exception 'You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved';
  end if;
  v_master := public.ims_can_write('master');
  v_mgr_ok := coalesce(public.ims_role_rank((select s.role from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active)), 0) >= public.ims_role_rank('manager');   -- mail-4a 판정 517
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  -- ① 모양
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then raise exception 'p_changes must be a JSON array of changes — nothing was saved'; end if;
  v_n := jsonb_array_length(p_changes);
  if v_n = 0 then raise exception 'No changes given — nothing was saved'; end if;
  if v_n > 1000 then raise exception 'Too many changes in one call (% — the limit is 1,000) — nothing was saved', v_n; end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_op := v_c->>'op';
    if v_op is null or v_op not in ('set', 'address_add', 'address_set', 'address_off', 'address_default', 'contact_add', 'contact_set', 'contact_off', 'contact_default') then
      raise exception 'Unknown op % — one of set · address_add · address_set · address_off · address_default · contact_add · contact_set · contact_off · contact_default — nothing was saved', coalesce(v_op, '(blank)');
    end if;
    if v_op = 'address_add' and coalesce((v_c->'values'->>'is_default_for_type')::boolean, false) then v_newdef := array_append(v_newdef, coalesce(v_c->>'customer_id', '') || ':' || btrim(coalesce(v_c->'values'->>'type', ''))); end if;
    if v_op = 'address_default' then v_newdef := array_append(v_newdef, coalesce(v_c->>'customer_id', '') || ':' || coalesce((select a.type from public.customer_address a where a.id = nullif(v_c->>'address_id', '')::uuid), '')); end if;
    if v_op = 'contact_add' and coalesce((v_c->'values'->>'is_default')::boolean, false) then v_newdef := array_append(v_newdef, coalesce(v_c->>'customer_id', '')); end if;
    if v_op = 'contact_default' then v_newdef := array_append(v_newdef, coalesce(v_c->>'customer_id', '')); end if;
  end loop;

  -- ② 검사 — 줄마다(현재 값은 지금 읽는다 · 저장은 ③에서 같은 순서로)
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_field := nullif(btrim(v_c->>'field'), '');
    v_cid := nullif(v_c->>'customer_id', '')::uuid;
    v_key := coalesce(v_cid::text, '(blank)');
    v_changes := v_changes || jsonb_build_object('i', v_i, 'customer_id', v_cid, 'op', v_op, 'field', v_field, 'applied', false);
    select * into v_cust from public.customer c where c.id = v_cid;
    if v_cid is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':customer_unknown', 'customer_id', v_cid, 'code', 'customer_unknown', 'message', format('Change %s: the customer does not exist — nothing was saved', v_i));
      continue;
    end if;
    v_touched := array_append(v_touched, v_cid);

    -- ── set ──
    if v_op = 'set' then
      if v_field is null or not (v_field = any(v_general) or v_field = any(v_money) or v_field = any(v_struct) or v_field = any(v_mgr)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:' || coalesce(v_field, '(blank)'), 'customer_id', v_cid, 'code', 'field_unknown', 'message', format('%s: field %s cannot be changed here — nothing was saved', v_cust.name, coalesce(v_field, '(blank)')));
        continue;
      end if;
      if (v_key || ':' || v_field) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_field, 'customer_id', v_cid, 'code', 'field_duplicate_in_call', 'message', format('%s %s is changed twice in this call — keep one — nothing was saved', v_cust.name, v_field));
        continue;
      end if;
      v_seen := array_append(v_seen, v_key || ':' || v_field);
      if (v_field = any(v_money) or v_field = any(v_struct)) and not v_master then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':money_field_not_allowed:' || v_field, 'customer_id', v_cid, 'code', 'money_field_not_allowed', 'message', format('Only a master user can change %s of %s — nothing was saved', v_field, v_cust.name));
        continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:' || v_field, 'customer_id', v_cid, 'code', 'old_missing', 'message', format('%s %s: the old value the screen saw is missing — nothing was saved', v_cust.name, v_field));
        continue;
      end if;
      v_cur := case v_field
        when 'name' then v_cust.name when 'display_name' then v_cust.display_name when 'note' then v_cust.note when 'tax_rule' then v_cust.tax_rule
        when 'default_location_id' then v_cust.default_location_id::text when 'default_carrier' then v_cust.default_carrier when 'tax_number' then v_cust.tax_number when 'tags' then v_cust.tags
        when 'is_legal_entity' then v_cust.is_legal_entity::text when 'parent_id' then v_cust.parent_id::text when 'default_ship_to_customer_id' then v_cust.default_ship_to_customer_id::text when 'is_active' then v_cust.is_active::text
        when 'price_tier' then v_cust.price_tier when 'discount_pct' then v_cust.discount_pct::text when 'payment_term_id' then v_cust.payment_term_id::text when 'currency_id' then v_cust.currency_id::text
        when 'ar_account_id' then v_cust.ar_account_id::text when 'sale_account_id' then v_cust.sale_account_id::text when 'default_bill_to_customer_id' then v_cust.default_bill_to_customer_id::text
        when 'invoice_split_by_store' then v_cust.invoice_split_by_store::text when 'backorder_mail' then v_cust.backorder_mail::text when 'final_invoice_mail' then v_cust.final_invoice_mail::text end;   -- doc-3a
      if (case when v_field = 'discount_pct' then (v_cur::numeric is distinct from nullif(v_c->>'old', '')::numeric)
               when v_field in ('is_legal_entity', 'is_active', 'invoice_split_by_store', 'backorder_mail', 'final_invoice_mail') then (v_cur::boolean is distinct from nullif(v_c->>'old', '')::boolean)   -- doc-3a
               else (v_cur is distinct from nullif(v_c->>'old', '')) end) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:' || v_field, 'customer_id', v_cid, 'code', 'changed_elsewhere', 'message', format('Someone just changed %s of %s (now "%s") — check again — nothing was saved', v_field, v_cust.name, coalesce(v_cur, '')));
        continue;
      end if;
      v_new := nullif(btrim(v_c->>'value'), '');
      -- 값 검사(바꾸는 칸만 · 옛 값은 보지 않는다)
      if v_field = 'name' then
        if v_new is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'customer_id', v_cid, 'code', 'name_missing', 'message', format('%s cannot have an empty name — nothing was saved', v_cust.name));
        else
          v_folded := lower(regexp_replace(v_new, '\s+', ' ', 'g'));
          select count(*) filter (where c.is_active), count(*) filter (where not c.is_active),
                 coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'is_active', c.is_active) order by c.is_active desc, c.created_at) filter (where c.rn <= 5), '[]'::jsonb)
            into v_n_act, v_n_off, v_matches
            from (select c0.*, row_number() over (order by c0.is_active desc, c0.created_at) as rn from public.customer c0 where c0.id <> v_cid and lower(regexp_replace(btrim(c0.name), '\s+', ' ', 'g')) = v_folded) c;
          if v_n_act > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':name_exists', 'customer_id', v_cid, 'code', 'name_exists', 'matches', v_matches, 'message', format('%s active customer(s) already have the name "%s" — is this really the same name? Confirm to rename anyway', v_n_act, v_new));
          elsif v_n_off > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':name_matches_inactive', 'customer_id', v_cid, 'code', 'name_matches_inactive', 'matches', v_matches, 'message', format('%s inactive customer(s) have the name "%s" — confirm to rename anyway', v_n_off, v_new));
          end if;
        end if;
      elsif v_field in ('is_legal_entity', 'is_active', 'invoice_split_by_store', 'backorder_mail', 'final_invoice_mail') then   -- doc-3a
        if v_new is null or v_new not in ('true', 'false') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:' || v_field, 'customer_id', v_cid, 'code', 'value_invalid', 'message', format('%s %s must be true or false — nothing was saved', v_cust.name, v_field));
        elsif v_field = 'is_active' and v_new = 'false' then
          -- 끄기 — 알리기 넷(판정 B-4) · so_create 가 새 오더를 막는 것은 기존 동작
          select count(*) into v_open_so from public.so s where s.customer_id = v_cid and s.status in ('draft', 'confirmed', 'at_wms', 'picking', 'packed');
          select count(*), coalesce(sum(public.so_invoice_remaining(i.id)), 0) into v_open_inv, v_inv_due from public.so_invoice i where i.bill_to_customer_id = v_cid and i.status = 'issued' and public.so_invoice_remaining(i.id) > 0;
          select coalesce(sum(b.available), 0) + coalesce(sum(b.owed_credit), 0) into v_bal from public.so_customer_balance(v_cid) b;
          select count(*) into v_kids from public.customer k where k.is_active and k.id <> v_cid and (k.parent_id = v_cid or k.default_ship_to_customer_id = v_cid or k.default_bill_to_customer_id = v_cid);
          if v_open_so > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_so', 'customer_id', v_cid, 'code', 'inactive_open_so', 'count', v_open_so, 'message', format('%s has %s open order(s) — they keep running; new orders will be refused once the customer is inactive. Confirm to deactivate', v_cust.name, v_open_so)); end if;
          if v_open_inv > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_invoice', 'customer_id', v_cid, 'code', 'inactive_open_invoice', 'count', v_open_inv, 'amount', v_inv_due, 'message', format('%s has %s unpaid invoice(s) (%s due) — confirm to deactivate', v_cust.name, v_open_inv, v_inv_due)); end if;
          if v_bal <> 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_balance', 'customer_id', v_cid, 'code', 'inactive_balance', 'amount', v_bal, 'message', format('%s has a balance (available + credit = %s) — confirm to deactivate', v_cust.name, v_bal)); end if;
          if v_kids > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_children', 'customer_id', v_cid, 'code', 'inactive_children', 'count', v_kids, 'message', format('%s active customer(s) point at %s as parent, ship-to or bill-to — confirm to deactivate', v_kids, v_cust.name)); end if;
        elsif v_field = 'is_active' and v_new = 'true' then
          v_folded := lower(regexp_replace(btrim(v_cust.name), '\s+', ' ', 'g'));
          select count(*), coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.created_at), '[]'::jsonb) into v_n_act, v_matches
            from public.customer c where c.id <> v_cid and c.is_active and lower(regexp_replace(btrim(c.name), '\s+', ' ', 'g')) = v_folded;
          if v_n_act > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':name_exists', 'customer_id', v_cid, 'code', 'name_exists', 'matches', v_matches, 'message', format('%s active customer(s) already have the name "%s" — confirm to reactivate anyway', v_n_act, v_cust.name)); end if;
        end if;
      elsif v_field = 'discount_pct' then
        if v_new is null or v_new !~ '^[0-9]+(\.[0-9]+)?$' or v_new::numeric > 100 then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_invalid', 'customer_id', v_cid, 'code', 'discount_invalid', 'message', format('%s: discount_pct must be a number from 0 to 100 (got %s) — nothing was saved', v_cust.name, coalesce(v_new, '(blank)')));
        end if;
      elsif v_field = 'price_tier' then
        select * into v_tier from public.ref_price_tier t where t.name = v_new and t.is_active and t.purpose = 'sale';
        if v_new is null or not found then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_invalid', 'customer_id', v_cid, 'code', 'tier_invalid', 'message', format('%s: price tier %s does not exist, is inactive or is not a sale tier — nothing was saved', v_cust.name, coalesce(v_new, '(blank)')));
        elsif v_cust.currency_id is not null and v_tier.currency_id <> v_cust.currency_id then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':tier_currency_mismatch', 'customer_id', v_cid, 'code', 'tier_currency_mismatch', 'message', format('Price tier %s is not in the currency of %s (%s) — order prices will not match', v_tier.name, v_cust.name, v_cust.currency_code));
        end if;
      elsif v_field = 'payment_term_id' then
        select * into v_term from public.ref_payment_term t where t.id = v_new::uuid and t.is_active;
        if v_new is null or not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':payment_term_invalid', 'customer_id', v_cid, 'code', 'payment_term_invalid', 'message', format('%s: the payment term does not exist or is inactive — nothing was saved', v_cust.name)); end if;
      elsif v_field = 'currency_id' then
        select * into v_curr from public.ref_currency r where r.id = v_new::uuid and r.is_active;
        if v_new is null or not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':currency_invalid', 'customer_id', v_cid, 'code', 'currency_invalid', 'message', format('%s: the currency does not exist or is inactive — nothing was saved', v_cust.name)); end if;
      elsif v_field in ('ar_account_id', 'sale_account_id') then
        select * into v_acct from public.ref_account a where a.id = v_new::uuid and a.is_active;
        if v_new is null or not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || replace(v_field, '_id', '_invalid'), 'customer_id', v_cid, 'code', replace(v_field, '_id', '_invalid'), 'message', format('%s: the account does not exist or is inactive — nothing was saved', v_cust.name)); end if;
      elsif v_field = 'default_location_id' then
        if v_new is not null and not exists (select 1 from public.ref_warehouse w where w.id = v_new::uuid and w.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':warehouse_unknown', 'customer_id', v_cid, 'code', 'warehouse_unknown', 'message', format('%s: the default warehouse does not exist or is inactive — nothing was saved', v_cust.name));
        end if;
      elsif v_field = 'parent_id' then
        if v_new is not null then
          select * into v_other from public.customer c where c.id = v_new::uuid and c.is_active;
          if v_new::uuid = v_cid then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_self', 'customer_id', v_cid, 'code', 'parent_self', 'message', format('%s cannot be its own parent — nothing was saved', v_cust.name));
          elsif not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_unknown', 'customer_id', v_cid, 'code', 'parent_unknown', 'message', format('%s: the parent customer does not exist or is inactive — nothing was saved', v_cust.name));
          elsif v_other.parent_id is not null then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_has_parent', 'customer_id', v_cid, 'code', 'parent_has_parent', 'message', format('%s already has a parent — a customer tree is one level deep — nothing was saved', v_other.name));
          elsif exists (select 1 from public.customer k where k.parent_id = v_cid) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_has_parent', 'customer_id', v_cid, 'code', 'parent_has_parent', 'message', format('%s has children of its own — a customer tree is one level deep — nothing was saved', v_cust.name)); end if;
        end if;
        -- cs-par-1 규칙 4(이견 3 · 7) — 부모를 비우거나 바꿀 때: 같은 호출이 그 옛 부모를 청구처로 다시 보내면 막는다 · 청구처가 옛 부모인데 이 호출이 청구처를 안 바꾸면 트리거(customer_parent_guard)가 null 로 돌린다고 알린다(ack)
        if v_cust.parent_id is not null and v_new is distinct from v_cust.parent_id::text then
          if exists (select 1 from jsonb_array_elements(p_changes) z where z->>'op' = 'set' and nullif(btrim(z->>'field'), '') = 'default_bill_to_customer_id' and nullif(z->>'customer_id', '')::uuid = v_cid and nullif(btrim(z->>'value'), '') = v_cust.parent_id::text) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':bill_to_is_old_parent', 'customer_id', v_cid, 'code', 'bill_to_is_old_parent', 'message', format('%s: the bill-to customer in this call is the parent being removed — pick another bill-to or leave it blank — nothing was saved', v_cust.name));
          elsif v_cust.default_bill_to_customer_id = v_cust.parent_id and not exists (select 1 from jsonb_array_elements(p_changes) z where z->>'op' = 'set' and nullif(btrim(z->>'field'), '') = 'default_bill_to_customer_id' and nullif(z->>'customer_id', '')::uuid = v_cid) then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':bill_to_reset_with_parent', 'customer_id', v_cid, 'code', 'bill_to_reset_with_parent', 'message', format('%s is billed to its parent — removing or changing the parent resets the bill-to to the customer itself. Confirm', v_cust.name));
          end if;
        end if;
      elsif v_field in ('default_ship_to_customer_id', 'default_bill_to_customer_id') then
        -- cs-par-1 규칙 2(이견 6 · 판정 255) — 자기 자신은 null 하나로 표기한다 · 보내면 막는다(CHECK customer_bill_to_not_self_ck · customer_ship_to_not_self_ck 가 모든 길에서 같은 것을 막는다)
        if v_new is not null and v_new::uuid = v_cid then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || case when v_field = 'default_ship_to_customer_id' then 'ship_to_self' else 'bill_to_self' end, 'customer_id', v_cid, 'code', case when v_field = 'default_ship_to_customer_id' then 'ship_to_self' else 'bill_to_self' end, 'message', format('%s cannot be its own %s customer — leave it blank (blank means the customer itself) — nothing was saved', v_cust.name, case when v_field = 'default_ship_to_customer_id' then 'ship-to' else 'bill-to' end));
        end if;
        if v_new is not null and not exists (select 1 from public.customer c where c.id = v_new::uuid and c.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || case when v_field = 'default_ship_to_customer_id' then 'ship_to_unknown' else 'bill_to_unknown' end, 'customer_id', v_cid, 'code', case when v_field = 'default_ship_to_customer_id' then 'ship_to_unknown' else 'bill_to_unknown' end, 'message', format('%s: that customer does not exist or is inactive — nothing was saved', v_cust.name));
        end if;
      end if;
      if v_field in ('backorder_mail', 'final_invoice_mail') and not v_mgr_ok and v_new is distinct from v_cur then   -- doc-3a 판정 529: 같은 결   -- mail-4a 판정 517: 값이 바뀔 때만(같은 값이 실려 와도 막지 않는다)
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':manager_needed:' || v_field, 'customer_id', v_cid, 'code', 'manager_needed', 'message', format('Only a manager or above can turn backorder alerts %s for %s — nothing was saved', case when v_new = 'true' then 'on' else 'off' end, v_cust.name));
      end if;
      if v_field = any(v_money) then v_money_ok := array_append(v_money_ok, v_cid); end if;

    -- ── 주소 op ──
    elsif v_op like 'address_%' then
      v_vals := coalesce(v_c->'values', '{}'::jsonb);
      v_olds := coalesce(v_c->'olds', '{}'::jsonb);
      if v_op = 'address_add' then
        v_f := nullif(btrim(v_vals->>'type'), '');
        if v_f is null or v_f not in ('Billing', 'Business', 'Shipping') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_type_invalid:' || v_i, 'customer_id', v_cid, 'code', 'address_type_invalid', 'message', format('%s: address type must be Billing, Business or Shipping (got %s) — nothing was saved', v_cust.name, coalesce(v_f, '(blank)')));
        end if;
        if nullif(btrim(coalesce(v_vals->>'line1', '') || coalesce(v_vals->>'city', '') || coalesce(v_vals->>'postal_code', '')), '') is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_empty:' || v_i, 'customer_id', v_cid, 'code', 'address_empty', 'message', format('%s: the new address has no street, city or postal code — nothing was saved', v_cust.name));
        end if;
      else
        select * into v_a from public.customer_address a where a.id = nullif(v_c->>'address_id', '')::uuid and a.customer_id = v_cid;
        if not found then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_unknown:' || v_i, 'customer_id', v_cid, 'code', 'address_unknown', 'message', format('%s: that address is not on this customer — nothing was saved', v_cust.name));
          continue;
        end if;
        if (v_key || ':address:' || v_a.id::text) = any(v_seen) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:address:' || v_a.id::text, 'customer_id', v_cid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same address is changed twice in this call — nothing was saved', v_cust.name));
          continue;
        end if;
        v_seen := array_append(v_seen, v_key || ':address:' || v_a.id::text);
        if v_op = 'address_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if not (v_f = any(v_afields)) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:address.' || v_f, 'customer_id', v_cid, 'code', 'field_unknown', 'message', format('%s: address field %s cannot be changed here — nothing was saved', v_cust.name, v_f)); continue;
            end if;
            if not (v_olds ? v_f) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:address.' || v_f, 'customer_id', v_cid, 'code', 'old_missing', 'message', format('%s: address %s — the old value the screen saw is missing — nothing was saved', v_cust.name, v_f)); continue;
            end if;
            v_cur := case v_f when 'type' then v_a.type when 'line1' then v_a.line1 when 'line2' then v_a.line2 when 'city' then v_a.city when 'state_province' then v_a.state_province when 'postal_code' then v_a.postal_code when 'country' then v_a.country when 'residential' then v_a.residential::text when 'tailgate_required' then v_a.tailgate_required::text when 'threshold_delivery' then v_a.threshold_delivery::text else v_a.label end;   -- fc-1a: boolean 은 true/false 글자
            if v_cur is distinct from nullif(v_olds->>v_f, '') then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:address.' || v_f, 'customer_id', v_cid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the address %s of %s (now "%s") — check again — nothing was saved', v_f, v_cust.name, coalesce(v_cur, '')));
            end if;
            if v_f = 'type' and nullif(btrim(v_vals->>'type'), '') not in ('Billing', 'Business', 'Shipping') then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_type_invalid:' || v_i, 'customer_id', v_cid, 'code', 'address_type_invalid', 'message', format('%s: address type must be Billing, Business or Shipping — nothing was saved', v_cust.name));
            end if;
          end loop;
        elsif v_op = 'address_off' then
          if not v_a.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_inactive:' || v_i, 'customer_id', v_cid, 'code', 'address_inactive', 'message', format('%s: that address is already off — nothing was saved', v_cust.name));
          elsif v_a.is_default_for_type and not ((v_key || ':' || v_a.type) = any(v_newdef)) then v_warns := v_warns || jsonb_build_object('key', v_key || ':address_default_off:' || v_a.type, 'customer_id', v_cid, 'code', 'address_default_off', 'message', format('%s: this is the default %s address — switching it off leaves no default %s address (orders will warn). Confirm', v_cust.name, v_a.type, v_a.type)); end if;
        elsif v_op = 'address_default' then
          if not v_a.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_inactive:' || v_i, 'customer_id', v_cid, 'code', 'address_inactive', 'message', format('%s: an inactive address cannot be the default — switch it on first — nothing was saved', v_cust.name)); end if;
        end if;
      end if;
      v_addr_ch := array_append(v_addr_ch, v_cid);

    -- ── 연락처 op ──
    else
      v_vals := coalesce(v_c->'values', '{}'::jsonb);
      v_olds := coalesce(v_c->'olds', '{}'::jsonb);
      if v_op = 'contact_add' then
        if nullif(btrim(coalesce(v_vals->>'name', '') || coalesce(v_vals->>'phone', '') || coalesce(v_vals->>'mobile_phone', '') || coalesce(v_vals->>'email', '')), '') is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_empty:' || v_i, 'customer_id', v_cid, 'code', 'contact_empty', 'message', format('%s: the new contact has no name, phone or email — nothing was saved', v_cust.name));
        end if;
        v_consent := nullif(btrim(v_vals->>'marketing_consent'), '');
        if v_consent is not null and v_consent not in ('0', '1', '2', '3') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':consent_invalid:' || v_i, 'customer_id', v_cid, 'code', 'consent_invalid', 'message', format('%s: marketing_consent must be 0 or 1 (unknown), 2 (opt in) or 3 (opt out) — got %s — nothing was saved', v_cust.name, v_consent));
        end if;
      else
        select * into v_ct from public.customer_contact k where k.id = nullif(v_c->>'contact_id', '')::uuid and k.customer_id = v_cid;
        if not found then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_unknown:' || v_i, 'customer_id', v_cid, 'code', 'contact_unknown', 'message', format('%s: that contact is not on this customer — nothing was saved', v_cust.name));
          continue;
        end if;
        if (v_key || ':contact:' || v_ct.id::text) = any(v_seen) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:contact:' || v_ct.id::text, 'customer_id', v_cid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same contact is changed twice in this call — nothing was saved', v_cust.name));
          continue;
        end if;
        v_seen := array_append(v_seen, v_key || ':contact:' || v_ct.id::text);
        if v_op = 'contact_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if not (v_f = any(v_cfields)) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:contact.' || v_f, 'customer_id', v_cid, 'code', 'field_unknown', 'message', format('%s: contact field %s cannot be changed here — nothing was saved', v_cust.name, v_f)); continue;
            end if;
            if not (v_olds ? v_f) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:contact.' || v_f, 'customer_id', v_cid, 'code', 'old_missing', 'message', format('%s: contact %s — the old value the screen saw is missing — nothing was saved', v_cust.name, v_f)); continue;
            end if;
            v_cur := case v_f when 'name' then v_ct.name when 'phone' then v_ct.phone when 'mobile_phone' then v_ct.mobile_phone when 'fax' then v_ct.fax when 'email' then v_ct.email when 'website' then v_ct.website when 'job_title' then v_ct.job_title
                              when 'include_in_email' then v_ct.include_in_email::text else case v_ct.marketing_consent when true then '2' when false then '3' else null end end;
            if (case when v_f = 'include_in_email' then (v_cur::boolean is distinct from nullif(v_olds->>v_f, '')::boolean)
                     when v_f = 'marketing_consent' then (v_cur is distinct from (case nullif(v_olds->>v_f, '') when '2' then '2' when '3' then '3' else null end))
                     else (v_cur is distinct from nullif(v_olds->>v_f, '')) end) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:contact.' || v_f, 'customer_id', v_cid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the contact %s of %s (now "%s") — check again — nothing was saved', v_f, v_cust.name, coalesce(v_cur, '')));
            end if;
            if v_f = 'marketing_consent' and nullif(btrim(v_vals->>v_f), '') is not null and nullif(btrim(v_vals->>v_f), '') not in ('0', '1', '2', '3') then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':consent_invalid:' || v_i, 'customer_id', v_cid, 'code', 'consent_invalid', 'message', format('%s: marketing_consent must be 0 or 1 (unknown), 2 (opt in) or 3 (opt out) — nothing was saved', v_cust.name));
            end if;
          end loop;
        elsif v_op = 'contact_off' then
          if not v_ct.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_inactive:' || v_i, 'customer_id', v_cid, 'code', 'contact_inactive', 'message', format('%s: that contact is already off — nothing was saved', v_cust.name));
          elsif v_ct.is_default and not (v_key = any(v_newdef)) then v_warns := v_warns || jsonb_build_object('key', v_key || ':contact_default_off', 'customer_id', v_cid, 'code', 'contact_default_off', 'message', format('%s: this is the default contact — switching it off leaves no default contact. Confirm', v_cust.name)); end if;
        elsif v_op = 'contact_default' then
          if not v_ct.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_inactive:' || v_i, 'customer_id', v_cid, 'code', 'contact_inactive', 'message', format('%s: an inactive contact cannot be the default — switch it on first — nothing was saved', v_cust.name)); end if;
        end if;
      end if;
    end if;
  end loop;

  -- 열린 오더 알리기 — 돈 칸 · 주소를 바꾸는 손님마다(열린 SO 는 복사해 굳힌 값 그대로 · master-cs-0 §C)
  for v_cid in select distinct u from unnest(v_money_ok || v_addr_ch) as u loop
    select count(*), max(c.name) into v_open_so, v_cur from public.so s join public.customer c on c.id = s.customer_id where s.customer_id = v_cid and s.status in ('draft', 'confirmed', 'at_wms', 'picking', 'packed');
    if v_open_so > 0 then
      v_warns := v_warns || jsonb_build_object('key', v_cid::text || ':open_so_keep_old', 'customer_id', v_cid, 'code', 'open_so_keep_old', 'count', v_open_so, 'message', format('%s has %s open order(s) — they keep the old terms and addresses; only new orders get the change. Confirm', v_cur, v_open_so));
    end if;
  end loop;

  -- ③ 판정
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns, 'reviewed_now', '[]'::jsonb,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ④ 저장 — 줄 순서대로 · 손님 행 잠금 · 한 트랜잭션 · 23505 는 문장으로
  begin
    perform 1 from public.customer c where c.id = any(v_touched) for update;
    v_i := 0;
    for v_c in select x from jsonb_array_elements(p_changes) as x loop
      v_i := v_i + 1;
      v_op := v_c->>'op'; v_field := nullif(btrim(v_c->>'field'), ''); v_cid := (v_c->>'customer_id')::uuid;
      v_new := nullif(btrim(v_c->>'value'), '');
      v_vals := coalesce(v_c->'values', '{}'::jsonb);
      if v_op = 'set' then
        case v_field
          when 'name' then update public.customer set name = v_new, updated_by = v_staff where id = v_cid;
          when 'display_name' then update public.customer set display_name = v_new, updated_by = v_staff where id = v_cid;
          when 'note' then update public.customer set note = v_new, updated_by = v_staff where id = v_cid;
          when 'tax_rule' then update public.customer set tax_rule = v_new, updated_by = v_staff where id = v_cid;
          when 'default_location_id' then update public.customer set default_location_id = v_new::uuid, default_location_name = (select w.name from public.ref_warehouse w where w.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'default_carrier' then update public.customer set default_carrier = v_new, updated_by = v_staff where id = v_cid;
          when 'tax_number' then update public.customer set tax_number = v_new, updated_by = v_staff where id = v_cid;
          when 'tags' then update public.customer set tags = v_new, updated_by = v_staff where id = v_cid;
          when 'is_legal_entity' then update public.customer set is_legal_entity = v_new::boolean, updated_by = v_staff where id = v_cid;
          when 'parent_id' then update public.customer set parent_id = v_new::uuid, parent_source = 'ims', updated_by = v_staff where id = v_cid;   -- 판정 253 · 678(ldfix-1a2 · 2026-10-24): 창구가 세우거나 바꾸거나 떼면 모두 ims — 뗀 것도 「IMS 가 부모 없음으로 정했다」 는 표식(적재 2단계가 건너뛴다) · 옛 줄은 비울 때 null(256 옛 뜻)
          when 'default_ship_to_customer_id' then update public.customer set default_ship_to_customer_id = v_new::uuid, updated_by = v_staff where id = v_cid;
          when 'is_active' then update public.customer set is_active = v_new::boolean, updated_by = v_staff where id = v_cid;
          when 'price_tier' then update public.customer set price_tier = v_new, updated_by = v_staff where id = v_cid;
          when 'discount_pct' then update public.customer set discount_pct = v_new::numeric, updated_by = v_staff where id = v_cid;
          when 'payment_term_id' then update public.customer set payment_term_id = v_new::uuid, payment_term_name = (select t.name from public.ref_payment_term t where t.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'currency_id' then update public.customer set currency_id = v_new::uuid, currency_code = (select r.code from public.ref_currency r where r.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'ar_account_id' then update public.customer set ar_account_id = v_new::uuid, ar_account_code = (select a.code from public.ref_account a where a.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'sale_account_id' then update public.customer set sale_account_id = v_new::uuid, sale_account_code = (select a.code from public.ref_account a where a.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'default_bill_to_customer_id' then update public.customer set default_bill_to_customer_id = v_new::uuid, updated_by = v_staff where id = v_cid;
          when 'invoice_split_by_store' then update public.customer set invoice_split_by_store = v_new::boolean, updated_by = v_staff where id = v_cid;
          when 'backorder_mail' then update public.customer set backorder_mail = v_new::boolean, updated_by = v_staff where id = v_cid;   -- mail-4a 판정 507 · 517(누가 · 언제 = updated_by · updated_at — 다른 칸과 같다)
          when 'final_invoice_mail' then update public.customer set final_invoice_mail = v_new::boolean, updated_by = v_staff where id = v_cid;   -- doc-3a 판정 529(같은 결)
        end case;
        -- 판정 240 — 돈 칸을 master 가 바꾸면 확인 · 처음 확인만 남긴다
        if v_field = any(v_money) then
          update public.customer set reviewed_by = v_staff, reviewed_at = now() where id = v_cid and reviewed_at is null returning id into v_rid;
          if v_rid is not null then v_reviewed := array_append(v_reviewed, v_rid); v_rid := null; end if;
        end if;
      elsif v_op = 'address_add' then
        v_f := btrim(v_vals->>'type');
        if coalesce((v_vals->>'is_default_for_type')::boolean, false) then
          update public.customer_address set is_default_for_type = false, updated_by = v_staff where customer_id = v_cid and type = v_f and is_default_for_type;
        end if;
        insert into public.customer_address (customer_id, source, updated_by, type, is_default_for_type, label, line1, line2, city, state_province, postal_code, country, residential, tailgate_required, threshold_delivery)
        values (v_cid, 'manual', v_staff, v_f, coalesce((v_vals->>'is_default_for_type')::boolean, false), nullif(btrim(v_vals->>'label'), ''), nullif(btrim(v_vals->>'line1'), ''), nullif(btrim(v_vals->>'line2'), ''),
                nullif(btrim(v_vals->>'city'), ''), nullif(btrim(v_vals->>'state_province'), ''), nullif(btrim(v_vals->>'postal_code'), ''), nullif(btrim(v_vals->>'country'), ''),
                nullif(btrim(v_vals->>'residential'), '')::boolean, coalesce(nullif(btrim(v_vals->>'tailgate_required'), '')::boolean, false), coalesce(nullif(btrim(v_vals->>'threshold_delivery'), '')::boolean, false))   -- fc-1a 판정 839 · 840
        returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'address_set' then
        update public.customer_address a set
          type = case when v_vals ? 'type' then btrim(v_vals->>'type') else a.type end,
          line1 = case when v_vals ? 'line1' then nullif(btrim(v_vals->>'line1'), '') else a.line1 end,
          line2 = case when v_vals ? 'line2' then nullif(btrim(v_vals->>'line2'), '') else a.line2 end,
          city = case when v_vals ? 'city' then nullif(btrim(v_vals->>'city'), '') else a.city end,
          state_province = case when v_vals ? 'state_province' then nullif(btrim(v_vals->>'state_province'), '') else a.state_province end,
          postal_code = case when v_vals ? 'postal_code' then nullif(btrim(v_vals->>'postal_code'), '') else a.postal_code end,
          country = case when v_vals ? 'country' then nullif(btrim(v_vals->>'country'), '') else a.country end,
          label = case when v_vals ? 'label' then nullif(btrim(v_vals->>'label'), '') else a.label end,
          residential = case when v_vals ? 'residential' then nullif(btrim(v_vals->>'residential'), '')::boolean else a.residential end,                                   -- fc-1a 판정 839: null = 기본 규칙(회사 → 상업지 · 사람 → 주거지)
          tailgate_required = case when v_vals ? 'tailgate_required' then coalesce(nullif(btrim(v_vals->>'tailgate_required'), '')::boolean, false) else a.tailgate_required end,   -- fc-1a 판정 840
          threshold_delivery = case when v_vals ? 'threshold_delivery' then coalesce(nullif(btrim(v_vals->>'threshold_delivery'), '')::boolean, false) else a.threshold_delivery end,   -- fc-1a 판정 840
          updated_by = v_staff
        where a.id = (v_c->>'address_id')::uuid;
      elsif v_op = 'address_off' then
        update public.customer_address set is_active = false, is_default_for_type = false, updated_by = v_staff where id = (v_c->>'address_id')::uuid;
      elsif v_op = 'address_default' then
        select * into v_a from public.customer_address a where a.id = (v_c->>'address_id')::uuid;
        update public.customer_address a set is_default_for_type = (a.id = v_a.id), updated_by = v_staff where a.customer_id = v_cid and a.type = v_a.type and a.is_active and (a.is_default_for_type or a.id = v_a.id);
      elsif v_op = 'contact_add' then
        v_consent := nullif(btrim(v_vals->>'marketing_consent'), '');
        if coalesce((v_vals->>'is_default')::boolean, false) then
          update public.customer_contact set is_default = false, updated_by = v_staff where customer_id = v_cid and is_default;
        end if;
        insert into public.customer_contact (customer_id, source, updated_by, name, phone, mobile_phone, fax, email, website, job_title, include_in_email, marketing_consent, is_default)
        values (v_cid, 'manual', v_staff, nullif(btrim(v_vals->>'name'), ''), nullif(btrim(v_vals->>'phone'), ''), nullif(btrim(v_vals->>'mobile_phone'), ''), nullif(btrim(v_vals->>'fax'), ''), nullif(btrim(v_vals->>'email'), ''),
                nullif(btrim(v_vals->>'website'), ''), nullif(btrim(v_vals->>'job_title'), ''), coalesce((v_vals->>'include_in_email')::boolean, false),
                case v_consent when '2' then true when '3' then false else null end, coalesce((v_vals->>'is_default')::boolean, false))
        returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'contact_set' then
        update public.customer_contact k set
          name = case when v_vals ? 'name' then nullif(btrim(v_vals->>'name'), '') else k.name end,
          phone = case when v_vals ? 'phone' then nullif(btrim(v_vals->>'phone'), '') else k.phone end,
          mobile_phone = case when v_vals ? 'mobile_phone' then nullif(btrim(v_vals->>'mobile_phone'), '') else k.mobile_phone end,
          fax = case when v_vals ? 'fax' then nullif(btrim(v_vals->>'fax'), '') else k.fax end,
          email = case when v_vals ? 'email' then nullif(btrim(v_vals->>'email'), '') else k.email end,
          website = case when v_vals ? 'website' then nullif(btrim(v_vals->>'website'), '') else k.website end,
          job_title = case when v_vals ? 'job_title' then nullif(btrim(v_vals->>'job_title'), '') else k.job_title end,
          include_in_email = case when v_vals ? 'include_in_email' then coalesce((v_vals->>'include_in_email')::boolean, false) else k.include_in_email end,
          marketing_consent = case when v_vals ? 'marketing_consent' then (case nullif(btrim(v_vals->>'marketing_consent'), '') when '2' then true when '3' then false else null end) else k.marketing_consent end,
          updated_by = v_staff
        where k.id = (v_c->>'contact_id')::uuid;
      elsif v_op = 'contact_off' then
        update public.customer_contact set is_active = false, is_default = false, updated_by = v_staff where id = (v_c->>'contact_id')::uuid;
      elsif v_op = 'contact_default' then
        update public.customer_contact k set is_default = (k.id = (v_c->>'contact_id')::uuid), updated_by = v_staff where k.customer_id = v_cid and k.is_active and (k.is_default or k.id = (v_c->>'contact_id')::uuid);
      end if;
      v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
    end loop;
  exception when unique_violation then
    raise exception 'Two defaults would remain for one customer (%) — set one default per address type and one default contact — nothing was saved', coalesce(sqlerrm, '');
  end;

  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb, 'reviewed_now', to_jsonb(v_reviewed));
end;
$$;
create or replace function public.ims_config_set(p_key text, p_value text, p_old text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
-- rls-2 · 판정 572 ~ 574 — 화면(settings.html)이 설정 한 키를 저장하는 유일한 길.
--   열쇠 식 한 곳: mail_enabled · mail_redirect_to = admin · 잠긴 3(ims_config_locked_keys) = supervisor 이상 · 나머지 메일 8 · 문서 7 · so_invoice_unit_display = master(mail_settings().edit_level · doc_config().can_edit_text 와 같은 식).
--   drive-1 판정 707: 드라이브 키 셋(ims_drive_config_keys · drive_enabled · drive_since · drive_root_id) = admin.
--   거부 20(판정 572): db_role · doc_public_base_url · base_currency · baseline_snapshot_key · customer_default_* 7 · supplier_default_* 4 · po_inventory_account_code · 계정 코드 4 · so_direct_order_tier_code — 「a migration or psql changes this」. 없는 키는 「is not a setting」.
--   값 검사는 여기 없다 — update 가 guard(inv_config_guard)를 깨우고 guard 가 누가 쓰든 값을 본다(이견 2). guard 의 사람 문은 창구 뒤의 마지막 벽(판정 573 · definer 라 닿지 않는다 · 그래서 db_role 은 여기서 먼저 거부).
--   p_old(판정 574): 화면이 본 값 · 다르면 changed_elsewhere 예외 · null 이면 검사 안 함 · 같은 값은 쓰지 않고 changed false.
declare
  v_staff   public.ims_staff%rowtype;
  v_level   text;
  v_cur     public.inv_config%rowtype;
  v_old     text;
  v_by_name text;
  v_changed boolean := false;
begin
  if p_key is null or btrim(p_key) = '' then raise exception 'p_key is required — nothing was saved'; end if;
  -- 허용 21 · 열쇠 등급(판정 572)
  if p_key in ('mail_enabled', 'mail_redirect_to') or p_key = any (public.ims_drive_config_keys()) then v_level := 'admin';
  elsif p_key = any (public.ims_config_locked_keys()) then v_level := 'supervisor';
  elsif p_key = any (public.ims_mail_config_keys()) or (p_key = any (public.ims_doc_config_keys()) and p_key <> 'doc_public_base_url') or p_key in ('so_invoice_unit_display', 'fc_markup_pct') then v_level := 'master';   -- fc-1a 판정 836: 운임 마크업 % 는 master
  elsif exists (select 1 from public.inv_config c where c.key = p_key) then
    raise exception 'Setting % is not changed from the app — a migration or psql changes this — nothing was saved', p_key;
  else
    raise exception 'Setting % is not a setting — nothing was saved', p_key;
  end if;
  -- 누가(열쇠 식 한 곳 · guard · mail_settings 와 같은 말)
  select * into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff.id is null then raise exception 'You are not registered as active staff — nothing was saved'; end if;
  if v_level = 'admin' and not public.ims_is_admin() then
    raise exception 'Changing % needs an admin — it decides whether and where customer mail goes — nothing was saved', p_key;
  elsif v_level = 'supervisor' and coalesce(public.ims_role_rank(v_staff.role), 0) < public.ims_role_rank('supervisor') then
    raise exception 'Changing % needs a supervisor or above (you are %) — this value closes backorder orders for good — nothing was saved', p_key, v_staff.role;
  elsif v_level = 'master' and not public.ims_can_write('master') then
    raise exception 'Changing % needs the master permission — nothing was saved', p_key;
  end if;
  if p_value is null then raise exception 'The value cannot be empty (null) — nothing was saved'; end if;
  if p_key = 'fc_markup_pct' and (p_value !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' or p_value::numeric > 100) then                                                   -- fc-1a: 0 ~ 100 · 소수 둘째 자리까지(guard 는 이 키를 모른다 — 창구가 유일한 앱 길)
    raise exception 'fc_markup_pct must be a percent from 0 to 100 (up to two decimals · got %) — nothing was saved', p_value;
  end if;
  select * into v_cur from public.inv_config c where c.key = p_key for update;
  if not found then raise exception 'Setting % has no row yet — a migration seeds it first — nothing was saved', p_key; end if;
  v_old := v_cur.value;
  -- 판정 574 — 화면이 본 값과 다르면 거부
  if p_old is not null and p_old is distinct from v_cur.value then
    select s.name into v_by_name from public.ims_staff s where s.id = v_cur.updated_by;
    raise exception 'changed_elsewhere: % was changed by % at % to "%" since this page loaded — reload and try again — nothing was saved',
      p_key, coalesce(v_by_name, '(unknown)'), coalesce(to_char(v_cur.updated_at, 'YYYY-MM-DD HH24:MI'), '?'), left(v_cur.value, 80);
  end if;
  if v_cur.value is distinct from p_value then
    update public.inv_config set value = p_value, updated_at = now(), updated_by = v_staff.id where key = p_key;   -- guard 가 값을 본다(값 틀리면 여기서 guard 의 문장으로 선다)
    v_changed := true;
    select * into v_cur from public.inv_config c where c.key = p_key;
  end if;
  select s.name into v_by_name from public.ims_staff s where s.id = v_cur.updated_by;
  return jsonb_build_object('key', p_key, 'value', v_cur.value, 'old_value', v_old, 'changed', v_changed,
                            'updated_at', v_cur.updated_at, 'updated_by_name', v_by_name, 'edit_level', v_level);
end;
$$;

-- ═══ 6) 착지 검사 — 표 · 칸 · 색인 · 함수 · 권한 · 설정 · 재발행 md5 · 무접촉 ═══
do $$
declare v_n int; v_t text; v_acl text;
begin
  select count(*) into v_n from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r' and relname in ('fc_shipment', 'fc_shipment_so', 'fc_quote', 'fc_quote_rate', 'fc_call_log', 'customer_carrier_avoid');
  if v_n <> 6 then raise exception 'fc-1a landing check failed: tables % of 6', v_n; end if;
  select count(*) into v_n from information_schema.columns where table_schema = 'public' and (
       (table_name = 'ref_warehouse' and column_name in ('phone', 'email', 'contact_name'))
    or (table_name = 'customer_address' and column_name in ('residential', 'tailgate_required', 'threshold_delivery'))
    or (table_name = 'ref_carrier' and column_name = 'freightcom_carrier'));
  if v_n <> 7 then raise exception 'fc-1a landing check failed: new columns % of 7', v_n; end if;
  if to_regclass('public.ref_carrier_freightcom_uq') is null or to_regclass('public.fc_shipment_so_live_uq') is null then raise exception 'fc-1a landing check failed: unique index missing'; end if;
  select count(*) into v_n from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_gate', 'fc_norm', 'fc_country', 'fc_phone', 'fc_money_cents', 'fc_units_snapshot', 'fc_shipment_live_sync',
    'fc_shipment_prepare', 'fc_quote_save', 'fc_quote_select', 'fc_charge_so_set', 'fc_shipment_for_so', 'wms_unit_dims_set', 'customer_carrier_avoid_set');
  if v_n <> 14 then raise exception 'fc-1a landing check failed: functions % of 14', v_n; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('customer_update', 'ims_config_set')) <> 2 then raise exception 'fc-1a landing check failed: reissued functions doubled'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'customer_update') <> '609b22f22fd09864acd2d0268fdfe4d7' then raise exception 'fc-1a landing check failed: customer_update md5'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_config_set') <> '1ae6db956ec8962064bb4fece08a552f' then raise exception 'fc-1a landing check failed: ims_config_set md5'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize') <> '70d4711f91b1ff0b3bb7067864383124' then raise exception 'fc-1a landing check failed: so_finalize touched'; end if;
  if (select value from public.inv_config where key = 'fc_markup_pct') <> '5' then raise exception 'fc-1a landing check failed: fc_markup_pct'; end if;
  foreach v_t in array array['fc_shipment', 'fc_shipment_so', 'fc_quote', 'fc_quote_rate', 'customer_carrier_avoid'] loop
    select relacl::text into v_acl from pg_class where oid = ('public.' || v_t)::regclass;
    if v_acl <> '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres}' then raise exception 'fc-1a landing check failed: % acl %', v_t, v_acl; end if;
  end loop;
  select relacl::text into v_acl from pg_class where oid = 'public.fc_call_log'::regclass;
  if v_acl <> '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=ard/postgres}' then raise exception 'fc-1a landing check failed: fc_call_log acl %', v_acl; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('fc_shipment', 'fc_shipment_so', 'fc_quote', 'fc_quote_rate', 'fc_call_log', 'customer_carrier_avoid')) <> 6 then raise exception 'fc-1a landing check failed: policies'; end if;
  if has_function_privilege('anon', 'public.fc_shipment_prepare(uuid[], jsonb, boolean)', 'execute') or has_function_privilege('service_role', 'public.fc_shipment_prepare(uuid[], jsonb, boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.fc_gate(uuid, text)', 'execute') or not has_function_privilege('service_role', 'public.fc_quote_save(uuid, text, jsonb, text)', 'execute') then
    raise exception 'fc-1a landing check failed: function acl';
  end if;
  raise notice 'fc-1a landing OK — tables 6 · columns 7 · functions 14 · reissued 2 · fc_markup_pct 5';
end $$;
