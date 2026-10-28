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
-- fc-1b — Freightcom 견적: 판정 845 「주소 기억 필요 — 오피스 확인」 · 견적 pending 줄 · EF 가 보낸 몸 보존 (2026-10-28 · 판정 844 · 845 · 지시서 ~/asung/prompts/fc-1b.md · EF supabase/functions/freightcom)
--   845: 주소에 조건(주거지 · 테일게이트 · 인사이드)을 굳히는 것은 customer_update 라 sales(오피스)만 — 창고(WMS)의 remember 는 쓰지 않고 발송에 address_review(무엇을 · 왜 · 누가 · 언제)만 남긴다 ·
--        오피스가 주소를 못 찾거나(address_not_found) 둘 이상이면(address_ambiguous) 같은 표시 · 오피스가 Ship & invoice 에서 ① 주소 추가(customer_update address_add + 조건) ② 기본 배송 주소 바꾸기(address_set + 조건) ③ 이번만 → fc_address_review_close(p_shipment_id, p_action added | default_changed | once · sales) 로 닫는다(①② 는 주소를 다시 맞춰 address_id 를 채운다)
--   fc-1a 의 prepare 는 창고 remember 도 주소에 썼다(fc_gate 가 definer 라 닿았다) — 이 차수가 office 만으로 좁힌다 · 경고 열쇠는 그대로(address_not_found · address_ambiguous) · 새 열쇠 없음(fc_1a_check 4e 무변) · 반환에 address_review
--   견적 둘: fc_quote_pending(service_role · EF 가 POST /rate 뒤 202 request_id 를 받자마자 pending 줄 + 실제 보낸 몸) · fc_quote_save 에 p_request(EF 가 보낸 몸 · freight_class · services 포함) — 같은 request_id 의 pending 줄이 있으면 그 줄을 done · error 로(새 줄 아님) · 시그니처가 바뀌어 drop + create(4 인자 호출은 기본값으로 그대로)
--   fc_shipment_for_so 에 address_review 셋 · 거래 표 so 를 가리키는 새 FK 없음 · 새 표 없음(cutover-delete 무변) · so_finalize 무접촉
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261028170402_fc_1b_address_review_quote_pending.sql && supabase migration repair --status applied 20261028170402 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028170402_fc_1b_address_review_quote_pending.sql -f supabase/tests/fc_1b_check.sql  (안에서 fc_1a_check 의 76 을 함께 돌린다)

-- ═══ 1) 칸 — fc_shipment 주소 기억 표시 ═══
alter table public.fc_shipment
  add column address_review           jsonb,
  add column address_review_closed_at timestamptz,
  add column address_review_closed_by uuid references public.ims_staff (id),
  add column address_review_action    text,
  add constraint fc_shipment_review_action_ck check (address_review_action is null or address_review_action in ('added', 'default_changed', 'once')),
  add constraint fc_shipment_review_closed_ck check ((address_review_closed_at is null) = (address_review_action is null));
comment on column public.fc_shipment.address_review is 'fc-1b 판정 845: 「주소 기억 필요 — 오피스 확인」 — {residential, tailgate_required, threshold_delivery, reason wms | address_not_found | address_ambiguous, address_id, requested_by, requested_at} · 창고 remember 또는 오피스가 주소를 못 찾았을 때 · 닫기는 fc_address_review_close(closed_at · by · action) · 새 remember 요청은 표시를 다시 연다';

-- ═══ 2) 재발행 셋 — fc_shipment_prepare(845) · fc_quote_save(p_request · pending) · fc_shipment_for_so(address_review) — 20261028162209 바이트 복사 + 자리 몇 ═══
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

drop function public.fc_quote_save(uuid, text, jsonb, text);                                                                               -- fc-1b: 시그니처가 바뀐다(p_request) — drop 뒤 create · 부르는 곳 = EF(새 꼴) · fc_1a_check(4 인자 그대로 · 기본값)
create function public.fc_quote_save(p_shipment_id uuid, p_request_id text, p_response jsonb, p_error text default null, p_request jsonb default null) returns jsonb
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
  if p_request_id is not null then select q.id into v_pend from public.fc_quote q where q.shipment_id = p_shipment_id and q.request_id = p_request_id and q.status = 'pending' order by q.requested_at desc limit 1; end if;
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
                                   'address_review', v_f.address_review, 'address_review_closed_at', v_f.address_review_closed_at, 'address_review_action', v_f.address_review_action,   -- fc-1b 845
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
revoke all on function public.fc_quote_save(uuid, text, jsonb, text, jsonb) from public, anon;
grant execute on function public.fc_quote_save(uuid, text, jsonb, text, jsonb) to authenticated, service_role;
comment on function public.fc_quote_save(uuid, text, jsonb, text, jsonb) is 'fc-1a · fc-1b: 견적 결과 저장 — EF(service_role · 문 없음) 또는 직원(fc_gate) · 같은 request_id 의 pending 줄(fc_quote_pending)이 있으면 그 줄을 done · error 로 · p_request = EF 가 실제 보낸 몸(없으면 pending 줄의 것 → 발송 payload) · rates[] → fc_quote_rate(센트 · pretax · customer_charge 836 · carrier 짝 · avoided 843 · totals_mismatch) · preselected · 발송 quoted · 고른 줄 풀림';

-- ═══ 3) 새 창구 둘 — fc_quote_pending(EF) · fc_address_review_close(오피스) ═══
create function public.fc_quote_pending(p_shipment_id uuid, p_request_id text, p_request jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_f public.fc_shipment%rowtype;  v_staff uuid;  v_qid uuid;
        v_role text := coalesce(current_setting('request.jwt.claims', true)::jsonb->>'role', '');
begin
  select * into v_f from public.fc_shipment f where f.id = p_shipment_id for update;
  if not found then raise exception 'Shipment % not found — nothing was saved', p_shipment_id; end if;
  if v_role <> 'service_role' then perform public.fc_gate(v_f.origin_warehouse_id, 'saved'); end if;
  if v_f.status in ('booked', 'cancelled') then raise exception 'Shipment is % — no new quotes — nothing was saved', v_f.status; end if;
  if nullif(btrim(p_request_id), '') is null then raise exception 'request_id is required — nothing was saved'; end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  insert into public.fc_quote (shipment_id, request_id, status, request, by_staff) values (p_shipment_id, btrim(p_request_id), 'pending', p_request, v_staff) returning id into v_qid;
  return jsonb_build_object('quote_id', v_qid, 'status', 'pending', 'request_id', btrim(p_request_id));
end;
$$;
revoke all on function public.fc_quote_pending(uuid, text, jsonb) from public, anon;
grant execute on function public.fc_quote_pending(uuid, text, jsonb) to authenticated, service_role;
comment on function public.fc_quote_pending(uuid, text, jsonb) is 'fc-1b: EF 가 POST /rate 의 202 request_id 를 받자마자 pending 줄(실제 보낸 몸 포함) — 다 안 끝나 화면이 Check again 으로 이어 물을 때 fc_quote_save 가 이 줄을 done · error 로 바꾼다';

create function public.fc_address_review_close(p_shipment_id uuid, p_action text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_f public.fc_shipment%rowtype;  v_staff uuid;  v_cust public.customer%rowtype;  v_ship_cid uuid;  v_n int := 0;  v_aid uuid;
begin
  perform public.ims_require_write('sales');
  if p_action is null or p_action not in ('added', 'default_changed', 'once') then raise exception 'action must be one of added · default_changed · once — nothing was saved'; end if;
  select * into v_f from public.fc_shipment f where f.id = p_shipment_id for update;
  if not found then raise exception 'Shipment % not found — nothing was saved', p_shipment_id; end if;
  if v_f.status = 'cancelled' then raise exception 'Shipment is cancelled — nothing was saved'; end if;
  if v_f.address_review is null then raise exception 'This shipment has no address to confirm — nothing was saved'; end if;
  if v_f.address_review_closed_at is not null then raise exception 'Already confirmed (%) — nothing was saved', v_f.address_review_action; end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if p_action <> 'once' then                                                       -- ①② 뒤에는 주소가 있어야 한다 — prepare 와 같은 (line1, postal) 맞추기로 다시 찾는다
    select * into v_cust from public.customer c where c.id = v_f.customer_id;
    v_ship_cid := coalesce(v_cust.default_ship_to_customer_id, v_cust.id);
    select count(*), min(a.id::text)::uuid into v_n, v_aid from public.customer_address a
     where a.customer_id = v_ship_cid and a.is_active and a.type in ('Shipping', 'Business')
       and public.fc_norm(a.line1) = public.fc_norm(v_f.destination->'address'->>'address_line_1')
       and regexp_replace(public.fc_norm(a.postal_code), '\s', '', 'g') = regexp_replace(public.fc_norm(v_f.destination->'address'->>'postal_code'), '\s', '', 'g');
    if v_n <> 1 then raise exception 'The ship-to address (% · %) is still not exactly one of the customer''s addresses (found %) — add or fix it first, or choose "this time only" — nothing was saved',
                       v_f.destination->'address'->>'address_line_1', v_f.destination->'address'->>'postal_code', v_n; end if;
  end if;
  update public.fc_shipment f set address_review_closed_at = now(), address_review_closed_by = v_staff, address_review_action = p_action,
                                  address_id = coalesce(v_aid, f.address_id), updated_by = v_staff
   where f.id = p_shipment_id;
  return jsonb_build_object('shipment_id', p_shipment_id, 'action', p_action, 'address_id', coalesce(v_aid, v_f.address_id), 'closed_by', v_staff);
end;
$$;
revoke all on function public.fc_address_review_close(uuid, text) from public, anon, service_role;
grant execute on function public.fc_address_review_close(uuid, text) to authenticated;
comment on function public.fc_address_review_close(uuid, text) is 'fc-1b 판정 845: 오피스(sales)가 「주소 기억 필요」 표시를 닫는다 — added(주소를 추가했다) · default_changed(기본 배송 주소를 바꿨다) · once(이번만) · ①② 는 화면이 customer_update 로 주소 · 조건을 먼저 쓴 뒤 부른다 — 창구가 (line1, postal) 로 다시 맞춰 정확히 하나여야 하며 address_id 를 채운다';

-- ═══ 4) 착지 검사 ═══
do $$
declare v_n int;
begin
  select count(*) into v_n from information_schema.columns where table_schema = 'public' and table_name = 'fc_shipment' and column_name in ('address_review', 'address_review_closed_at', 'address_review_closed_by', 'address_review_action');
  if v_n <> 4 then raise exception 'fc-1b landing check failed: columns % of 4', v_n; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_quote_save') <> 1 then raise exception 'fc-1b landing check failed: fc_quote_save must be exactly one (drop + create)'; end if;
  if (select pg_get_function_identity_arguments(oid) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_quote_save') <> 'p_shipment_id uuid, p_request_id text, p_response jsonb, p_error text, p_request jsonb' then raise exception 'fc-1b landing check failed: fc_quote_save signature'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_prepare') <> 'ff55098078911f12f7f358c539755769' then raise exception 'fc-1b landing check failed: fc_shipment_prepare md5'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_quote_save') <> 'f7f0901e9c52b336f7455ca8e45ae98c' then raise exception 'fc-1b landing check failed: fc_quote_save md5'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_for_so') <> 'b332ab3406dfe6b7da494416bbebd70b' then raise exception 'fc-1b landing check failed: fc_shipment_for_so md5'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_quote_pending', 'fc_address_review_close')) <> 2 then raise exception 'fc-1b landing check failed: new functions'; end if;
  if not has_function_privilege('service_role', 'public.fc_quote_save(uuid, text, jsonb, text, jsonb)', 'execute') or not has_function_privilege('service_role', 'public.fc_quote_pending(uuid, text, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.fc_quote_pending(uuid, text, jsonb)', 'execute') or has_function_privilege('service_role', 'public.fc_address_review_close(uuid, text)', 'execute')
     or not has_function_privilege('authenticated', 'public.fc_shipment_prepare(uuid[], jsonb, boolean)', 'execute') then
    raise exception 'fc-1b landing check failed: function acl';
  end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_finalize') <> '70d4711f91b1ff0b3bb7067864383124' then raise exception 'fc-1b landing check failed: so_finalize touched'; end if;
  raise notice 'fc-1b landing OK — columns 4 · reissued 3 · new 2 · fc_quote_save (…, p_request)';
end $$;
