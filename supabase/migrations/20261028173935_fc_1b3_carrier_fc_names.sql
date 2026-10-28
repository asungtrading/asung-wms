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
-- fc-1b3 — 운송사 한 줄에 Freightcom 이름 여럿(판정 847) + LTL 운송사 넣기(판정 846) (2026-10-28 · 지시서 ~/asung/prompts/fc-1b3.md)
--   왜: /services 실물은 한 운송사가 이름 여럿로 온다(Kindersley · Kindersley Transport / Maritime · Maritime-Ontario / 「Purolator Freight 」 끝 공백 · 응답은 「fastfrate」 소문자) — 칸 하나(fc-1a freightcom_carrier)로는 못 받는다
--   이름 자리 = 관계 표 ref_carrier_fc_name(carrier_id, name, name_norm = lower(btrim(name)) 생성 칸 · unique(name_norm) = 한 이름은 한 운송사에만) · 쓰기는 창구 ref_carrier_fc_names_set(p_carrier_id, p_names text[] · master · 통째 바꿈 · 표 직접 쓰기 닫힘)
--   옛 칸 ref_carrier.freightcom_carrier 는 값을 옮긴 뒤 지운다(같은 사실 두 군데 금지) · 부분 유니크 색인도 함께 · settings.html 은 이 칸을 안 썼다(name · kind · shopify_company · tracking_url_template · is_active 만 — 확인)
--   재발행 둘(바이트 복사 + 한 줄): fc_shipment_prepare(carriers = 켜진 운송사의 이름 전부 · 20261028170402) · fc_quote_save(짝 = 이름 표 name_norm · 20261028171641) — 그 밖에 이 칸을 읽는 함수 없음(DB prosrc grep: 둘뿐)
--   넣기(판정 846 · Caleb 표 · 확실한 것만): 새 운송사 7(Purolator Freight · Vitran · Apex · Kindersley · WCE · Fastfrate · Maritime · kind carrier · shopify_company 비움) + 이름 14(기존 UPS · Purolator · Canada Post · FedEx(FedEx Courier · 짐작) · Canpar(Canpar · 짐작) 포함) · 이미 있으면 건너뜀 · 이름이 다른 운송사에 이미 붙어 있으면 건너뜀(유니크 · 보고에)
--   846 「처음 보는 운송사」 표식 = fc_quote_rate.carrier_id null(그대로 · fc_quote_select 가 거부한다) · 넘기기 표시는 fc-1c 화면 차수에서
--   컷오버: ref_carrier_fc_name 은 K(남김 · cutover-delete k10 에 더함 · 같은 커밋) · 거래 표 FK 없음 · so_finalize 무접촉
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261028173935_fc_1b3_carrier_fc_names.sql && supabase migration repair --status applied 20261028173935 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028173935_fc_1b3_carrier_fc_names.sql -f supabase/tests/fc_1b3_check.sql  (안에서 fc_1b2 사본 106 — fc_1b 99 · fc_1a 76 포함 — 를 함께)

-- ═══ 1) 이름 표 ═══
create table public.ref_carrier_fc_name (
  carrier_id uuid not null references public.ref_carrier (id),
  name       text not null,
  name_norm  text generated always as (lower(btrim(name))) stored,
  created_at timestamptz not null default now(),
  created_by uuid references public.ims_staff (id),
  primary key (carrier_id, name_norm),
  constraint ref_carrier_fc_name_uk      unique (name_norm),
  constraint ref_carrier_fc_name_name_ck check (btrim(name) <> '')
);
comment on table public.ref_carrier_fc_name is 'fc-1b3 판정 847: 운송사 한 줄의 Freightcom 이름들(/services · 견적 응답의 carrier_name) · name 은 글자 그대로 · name_norm = lower(btrim) 이 열쇠(한 이름은 한 운송사에만 · 대소문자 · 앞뒤 공백 무시) · 쓰기는 ref_carrier_fc_names_set(master) · fc_shipment_prepare.carriers(상자 견적 services 고르기) · fc_quote_save(응답 → carrier_id) 가 읽는다 · 컷오버 K';
alter table public.ref_carrier_fc_name enable row level security;
create policy ref_carrier_fc_name_select on public.ref_carrier_fc_name for select to authenticated using (true);
revoke all on public.ref_carrier_fc_name from public, anon, authenticated, service_role;
grant select on public.ref_carrier_fc_name to authenticated, service_role;

-- 옮기기 — 옛 칸의 값을 이름 표로(테스트 DB 실물 셋: UPS · Purolator · Canada Post) · 그 뒤 옛 칸 · 색인 삭제
insert into public.ref_carrier_fc_name (carrier_id, name) select c.id, btrim(c.freightcom_carrier) from public.ref_carrier c where nullif(btrim(c.freightcom_carrier), '') is not null on conflict (name_norm) do nothing;
drop index public.ref_carrier_freightcom_uq;
alter table public.ref_carrier drop column freightcom_carrier;

-- ═══ 2) 쓰기 창구 — 통째 바꾸기(master) ═══
create function public.ref_carrier_fc_names_set(p_carrier_id uuid, p_names text[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_c public.ref_carrier%rowtype;  v_staff uuid;  v_names text[];  v_bad text;
begin
  perform public.ims_require_write('master');
  select * into v_c from public.ref_carrier c where c.id = p_carrier_id for update;
  if not found then raise exception 'Carrier % not found — nothing was saved', p_carrier_id; end if;
  if v_c.kind <> 'carrier' then raise exception 'Only a carrier (not Pickup · Delivery) can have Freightcom names — nothing was saved'; end if;
  select array_agg(distinct btrim(n)) into v_names from unnest(coalesce(p_names, '{}'::text[])) n where nullif(btrim(n), '') is not null;
  v_names := coalesce(v_names, '{}'::text[]);
  if (select count(*) - count(distinct lower(n)) from unnest(v_names) n) > 0 then raise exception 'The same name is given twice (case differs) — nothing was saved'; end if;
  select string_agg(n.name || ' → ' || c.name, ', ') into v_bad from public.ref_carrier_fc_name n join public.ref_carrier c on c.id = n.carrier_id
   where n.carrier_id <> p_carrier_id and n.name_norm in (select lower(x) from unnest(v_names) x);
  if v_bad is not null then raise exception 'Name(s) already belong to another carrier: % — a Freightcom name maps to one carrier — nothing was saved', v_bad; end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  delete from public.ref_carrier_fc_name n where n.carrier_id = p_carrier_id and not (n.name_norm in (select lower(x) from unnest(v_names) x));
  insert into public.ref_carrier_fc_name (carrier_id, name, created_by) select p_carrier_id, x, v_staff from unnest(v_names) x on conflict (carrier_id, name_norm) do nothing;
  return jsonb_build_object('carrier_id', p_carrier_id, 'carrier', v_c.name, 'names', (select coalesce(jsonb_agg(n.name order by n.name), '[]'::jsonb) from public.ref_carrier_fc_name n where n.carrier_id = p_carrier_id));
end;
$$;
revoke all on function public.ref_carrier_fc_names_set(uuid, text[]) from public, anon, service_role;
grant execute on function public.ref_carrier_fc_names_set(uuid, text[]) to authenticated;
comment on function public.ref_carrier_fc_names_set(uuid, text[]) is 'fc-1b3 판정 847: 운송사의 Freightcom 이름 목록을 통째로(master · kind carrier 만 · 빈 글자 버림 · 같은 이름 두 번 거부 · 다른 운송사에 붙은 이름 거부 — 사람 말로) · Settings → Carriers(fc-1c)가 부른다';

-- ═══ 3) 재발행 둘 ═══
create or replace function public.fc_shipment_prepare(p_so_ids uuid[], p_options jsonb default '{}'::jsonb, p_commit boolean default true) returns jsonb
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
  v_review   jsonb := null;                                                        -- fc-1b 판정 845: 「주소 기억 필요 — 오피스 확인」
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
  -- 판정 845: 창고(WMS)는 주소를 못 쓴다(③ 이번만) · 오피스라도 주소를 못 찾거나 둘 이상이면 못 쓴다 → 발송에 「주소 기억 필요」 표시만 남기고 오피스가 Ship & invoice 에서 ①②③ 으로 닫는다(fc_address_review_close)
  if v_remember and (v_mode = 'wms' or v_addr.id is null) then
    v_review := jsonb_build_object('residential', v_res, 'tailgate_required', v_tail, 'threshold_delivery', v_thr,
                                   'reason', case when v_mode = 'wms' then 'wms' when v_addr_n = 0 then 'address_not_found' else 'address_ambiguous' end,
                                   'address_id', v_addr.id, 'requested_by', v_staff, 'requested_at', now());
  end if;
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
  select coalesce(jsonb_agg(n.name order by n.name), '[]'::jsonb) into v_carriers from public.ref_carrier_fc_name n join public.ref_carrier c on c.id = n.carrier_id where c.is_active;   -- fc-1b3 판정 847: 켜진 운송사의 Freightcom 이름 전부(한 운송사에 여럿)
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
        units = v_units, request = v_req, payload_hash = v_hash, updated_by = v_staff,
        address_review = coalesce(v_review, case when f.address_review_closed_at is null then f.address_review end),                                   -- fc-1b 845: 새 요청이 없으면 안 닫힌 표시는 지킨다
        address_review_closed_at = case when v_review is not null then null else f.address_review_closed_at end,
        address_review_closed_by = case when v_review is not null then null else f.address_review_closed_by end,
        address_review_action    = case when v_review is not null then null else f.address_review_action end
      where f.id = v_sid;
    else
      insert into public.fc_shipment (origin_warehouse_id, packaging_type, charge_so_id, customer_id, address_id, freight_locked, freight_locked_reason, origin, destination, options, units, request, payload_hash, created_in, created_by, updated_by, address_review)
      values (v_first.location_id, v_ptype, v_first.id, v_first.customer_id, v_addr.id, v_locked, v_lock_reason, v_orig, v_dest,
              jsonb_build_object('residential', v_res, 'tailgate_required', v_tail, 'threshold_delivery', v_thr, 'ship_date', v_date), v_units, v_req, v_hash, v_mode, v_staff, v_staff, v_review)
      returning id into v_sid;
      insert into public.fc_shipment_so (shipment_id, so_id) select v_sid, i from unnest(v_ids) i;
      if v_action = 'supersede' then update public.fc_shipment f set superseded_by = v_sid where f.id = any (v_olds); end if;
    end if;
    if v_remember and v_addr.id is not null and v_mode = 'office' then                                                                                -- fc-1b 845: 주소에 굳히는 것은 오피스(sales)만
      update public.customer_address a set residential = v_res, tailgate_required = v_tail, threshold_delivery = v_thr, updated_by = v_staff where a.id = v_addr.id;
    end if;
  end if;
  return jsonb_build_object('committed', p_commit, 'action', v_action, 'shipment_id', v_sid, 'mode', v_mode, 'packaging_type', v_ptype,
                            'charge_so_id', (select f.charge_so_id from public.fc_shipment f where f.id = v_sid), 'charge_so_number', (select s.so_number from public.fc_shipment f join public.so s on s.id = f.charge_so_id where f.id = v_sid), 'first_so_number', v_first.so_number, 'so_ids', to_jsonb(v_ids), 'so_numbers', to_jsonb(v_nums),
                            'options', jsonb_build_object('residential', v_res, 'tailgate_required', v_tail, 'threshold_delivery', v_thr, 'ship_date', v_date, 'remember', v_remember),
                            'address_id', v_addr.id, 'address_review', v_review, 'freight_locked', v_locked, 'freight_locked_reason', v_lock_reason,
                            'units', v_units, 'request', v_req, 'payload_hash', v_hash, 'carriers', v_carriers, 'warnings', to_jsonb(v_warn));
end;
$$;

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
begin
  select * into v_f from public.fc_shipment f where f.id = p_shipment_id for update;
  if not found then raise exception 'Shipment % not found — nothing was saved', p_shipment_id; end if;
  if v_role <> 'service_role' then perform public.fc_gate(v_f.origin_warehouse_id, 'saved'); end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_f.status in ('booked', 'cancelled') then raise exception 'Shipment is % — no new quotes — nothing was saved', v_f.status; end if;
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

-- ═══ 4) 넣기 — 판정 846 운송사 7 + 이름(Caleb 표 그대로 · 이미 있으면 건너뜀) ═══
insert into public.ref_carrier (name, kind, is_active)
select x.name, 'carrier', true from (values ('Purolator Freight'), ('Vitran'), ('Apex'), ('Kindersley'), ('WCE'), ('Fastfrate'), ('Maritime')) as x(name)
where not exists (select 1 from public.ref_carrier c where c.name = x.name);
insert into public.ref_carrier_fc_name (carrier_id, name)
select c.id, x.fc from (values
  ('UPS', 'UPS'), ('Purolator', 'Purolator'), ('Canada Post', 'Canada Post'),
  ('FedEx', 'FedEx Courier'),                                                    -- 짐작(대화 Claude) — Caleb 이 Settings 에서 고칠 수 있다
  ('Canpar', 'Canpar'),                                                          -- 짐작(대화 Claude)
  ('Purolator Freight', 'Purolator Freight'), ('Vitran', 'Vitran'), ('Apex', 'Apex Motor Express'),
  ('Kindersley', 'Kindersley'), ('Kindersley', 'Kindersley Transport'), ('WCE', 'WCE'), ('Fastfrate', 'Fastfrate'),
  ('Maritime', 'Maritime'), ('Maritime', 'Maritime-Ontario')) as x(carrier, fc)
join public.ref_carrier c on c.name = x.carrier
on conflict (name_norm) do nothing;                                              -- 이미 다른 운송사에 붙은 이름은 건너뛴다(유니크 · 착지 검사가 수를 센다)

-- ═══ 5) 착지 검사 ═══
do $$
declare v_n int; v_missing text;
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'ref_carrier' and column_name = 'freightcom_carrier') <> 0 then raise exception 'fc-1b3 landing check failed: old column still there'; end if;
  if to_regclass('public.ref_carrier_freightcom_uq') is not null then raise exception 'fc-1b3 landing check failed: old index still there'; end if;
  if (select relacl::text from pg_class where oid = 'public.ref_carrier_fc_name'::regclass) <> '{postgres=arwdDxtm/postgres,authenticated=r/postgres,service_role=r/postgres}' then raise exception 'fc-1b3 landing check failed: acl'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_prepare') <> '04ef6b62015202b9483046920c552c6c' then raise exception 'fc-1b3 landing check failed: fc_shipment_prepare md5'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_quote_save') <> 'fd33e8353dcde217f098c3c0dfd4ff46' then raise exception 'fc-1b3 landing check failed: fc_quote_save md5'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prosrc like '%freightcom_carrier%') <> 0 then raise exception 'fc-1b3 landing check failed: a function still reads freightcom_carrier'; end if;
  select string_agg(x.name, ', ') into v_missing from (values ('UPS'), ('Purolator'), ('Canada Post'), ('FedEx'), ('Canpar'), ('Purolator Freight'), ('Vitran'), ('Apex'), ('Kindersley'), ('WCE'), ('Fastfrate'), ('Maritime')) as x(name)
   where not exists (select 1 from public.ref_carrier c where c.name = x.name and c.kind = 'carrier');
  if v_missing is not null then raise exception 'fc-1b3 landing check failed: carriers missing: %', v_missing; end if;
  select count(*) into v_n from public.ref_carrier_fc_name;
  if v_n < 14 then raise exception 'fc-1b3 landing check failed: names % < 14', v_n; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize') <> '70d4711f91b1ff0b3bb7067864383124' then raise exception 'fc-1b3 landing check failed: so_finalize touched'; end if;
  raise notice 'fc-1b3 landing OK — ref_carrier_fc_name % names · 12 carriers · old column gone · reissued 2', v_n;
end $$;
