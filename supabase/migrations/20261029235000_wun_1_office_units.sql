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
-- wun-1 — 오피스에서 발송 유닛(박스 · 팔렛) 더하기 · 빼기 (2026-10-29 · 판정 881 · 동료 피드백 6 「IMS에서 쉽핑 어레인지를 할때, 박스나, 팔렛을 추가할 수가 없는 것 같아.」 · 조사 fb-1029-0)
--   무엇이 났나: so.html Ship & invoice 의 「What the warehouse packed」 표는 wms_so_handoff 를 읽어 그리고 「Edit sizes and weights」 는 wms_unit_dims_set(fc_1a:646) 으로 있는 줄의 치수만 고친다 —
--     줄을 더하거나 빼는 창구가 없다 · 창고 화면(wms-fulfillment.html addUnit:1440)은 wms_pallets 에 직접 insert · 오피스가 유닛 없는 Finalized 오더에서 유닛을 처음부터 만들어 견적 · 예약까지 하는 것이 평소 일(Caleb 2026-10-29)
--   판정 881(Caleb 「쓰자」 · 2026-10-29): ① 더하기 · 치수 고치기(기존 wms_unit_dims_set) · 빼기 ② 더하기 = 종류 · 크기 · 무게 · 개수 ③ 빼기 = 물건이 담기지 않은 유닛만 ④ 상태 picking · packed 만
--     ⑤ 문 = sales 쓰기 ⑥ 섞기 금지(그 오더의 맨 위 유닛과 종류가 다르면 거부 — fc_shipment_prepare 의 「mixes boxes and pallets」 와 같은 뜻) ⑦ 유닛이 바뀌면 지금처럼 다시 견적(units_changed) ·
--     예약(booked · 진행 중 pending)이 있으면 거부 「cancel the booking first」(예약된 발송의 유닛을 바꾸면 라벨 · BOL 과 어긋난다)
--   창구 둘: wms_unit_add(p_so_id, p_type, p_length, p_width, p_height, p_weight, p_count, p_dim_unit, p_weight_unit) · wms_unit_remove(p_so_id, p_unit_id bigint)
--     유닛 이름 = 창고 화면 wms-packing.js nextUnitLabel 과 같은 규칙(그 오더의 같은 종류 유닛 중 ^[PB]\d+$ 최대 번호 + 1 · 자식 박스도 센다 · 옛 꼴 라벨은 안 센다) · so 행 for update 로 동시 더하기를 줄 세운다
--     칸은 창고 화면 addUnit 과 같게(order_id · unit_type · label · parent_id null · status building · created_by = ims_staff.id) + 치수(wms_unit_dims_set 과 같은 칸 · 같은 CHECK · 트리거 wms_pallet_dims 가 in · lb 를 채운다)
--     「오피스가 만든 유닛」 표지 칸은 wms_pallets 에 없다 — 새 칸을 만들지 않는다(created_by 가 누가 만들었는지 말한다 · 이견 1)
--     wms_order_finalize.units · units_without_dims(Finalize 때 센 수 · so.html:3168 「N unit(s)」)는 더하기 · 빼기 뒤 다시 센다(fulfillment_type · finalized_by · finalized_at 은 그대로 · 이견 6)
--   새 표 없음 · 새 FK 없음 · 데이터 무접촉(새 함수 셋 · comment) · wms_pallets 행은 창구가 불릴 때만 바뀐다 · wms_pallets · wms_pallet_items 정책(auth_all · 판정 569)은 그대로
--   화면(asung-ims so.html · 대화 Claude): sb.rpc("wms_unit_add", { p_so_id, p_type: "box"|"pallet", p_length, p_width, p_height, p_weight, p_count, p_dim_unit: "in"|"cm", p_weight_unit: "lb"|"kg" }) ·
--     sb.rpc("wms_unit_remove", { p_so_id, p_unit_id }) · error.message 를 그대로 보인다 · 성공이면 wms_so_handoff · fc_shipment_for_so 를 다시 읽는다(units_changed 가 「다시 견적」 을 말한다)
--   ⚠️ 적용은 Caleb: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/migrations/20261029235000_wun_1_office_units.sql && supabase migration repair --status applied 20261029235000 --db-url "$(cat ~/.asung-testdb-url)" — db push 금지
--   시험: supabase/tests/wun_1_check.sql(-v mig · begin → rollback · T1~T9) · 둘째 겹 = 적용 뒤 so.html 새 판에서 Finalized 오더 하나에 박스 둘을 더하고 하나를 뺀 뒤 견적(REST)

-- ═══ 0) 마지막 정의 확인 — 새 창구 셋은 아직 없어야 · wms_unit_dims_set 은 fc-1a(20261028162209:646 · 유일한 정의)의 것 ═══
do $$
declare v_bad text := '';
begin
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname in ('wms_unit_add', 'wms_unit_remove', 'wms_unit_counts_refresh')) then v_bad := v_bad || ' wms_unit_add/remove/counts_refresh(already there)'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_unit_dims_set') is distinct from '11522dd8efe4bdc31673954cdbcd0626' then v_bad := v_bad || ' wms_unit_dims_set(md5)'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM881', message = format('STOP - not the expected state:%s - re-read before re-issuing - nothing was changed', v_bad); end if;
end $$;

-- ═══ 1) 속 함수 — 예약 문(booked · 진행 중 pending) · Finalize 기록의 유닛 수 다시 세기 ═══
-- 예약 검사: 이 SO 가 든 살아 있는 발송이 booked 면 거부 · 그 발송의 pending 시도가 10 분 안이면 거부(fc_book_prepare 와 같은 선 · 10 분 넘은 pending 은 fc_book_prepare 가 failed 로 비켜 둔다) · 반환 = 발송 상태(없으면 null)
create function public.wms_unit_booking_gate(p_so_id uuid, p_so_number text) returns text
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare v_f public.fc_shipment%rowtype;  v_pend public.fc_booking%rowtype;
begin
  select f.* into v_f from public.fc_shipment f join public.fc_shipment_so l on l.shipment_id = f.id where l.so_id = p_so_id and l.live;
  if not found then return null; end if;
  if v_f.status = 'booked' then
    raise exception 'Shipment for % is booked — cancel the booking first, then change the boxes or pallets — nothing was saved', p_so_number;
  end if;
  select b.* into v_pend from public.fc_booking b where b.shipment_id = v_f.id and b.status = 'pending' order by b.attempt desc limit 1;
  if found and v_pend.requested_at > now() - interval '10 minutes' then
    raise exception 'A booking attempt (#%) for % is still in progress — use Check again or wait a few minutes — nothing was saved', v_pend.attempt, p_so_number;
  end if;
  return v_f.status;
end;
$$;
revoke all on function public.wms_unit_booking_gate(uuid, text) from public, anon, authenticated, service_role;
comment on function public.wms_unit_booking_gate(uuid, text) is 'wun-1 판정 881 ⑦: 유닛을 더하거나 빼기 전 예약 문 — 살아 있는 발송이 booked 면 거부 · pending 시도가 10 분 안이면 거부(fc_book_prepare 의 선) · 반환 = 발송 상태(없으면 null) · 속 함수(직원 실행권 없음)';

-- Finalize 기록(wms_order_finalize.units · units_without_dims)을 wms_finalize(20260928234815:884) 와 같은 식으로 다시 센다 — packed 가 아니면 행이 없어 0 행(WHERE 있음)
create function public.wms_unit_counts_refresh(p_so_id uuid) returns void
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
begin
  update public.wms_order_finalize f
     set units = c.n, units_without_dims = c.nodim
    from (select count(*) as n, count(*) filter (where u.length_in is null or u.width_in is null or u.height_in is null or u.weight_lb is null) as nodim
            from public.wms_pallets u
           where u.order_id = p_so_id or u.parent_id in (select p2.id from public.wms_pallets p2 where p2.order_id = p_so_id)) c
   where f.order_id = p_so_id and (f.units is distinct from c.n or f.units_without_dims is distinct from c.nodim);
end;
$$;
revoke all on function public.wms_unit_counts_refresh(uuid) from public, anon, authenticated, service_role;
comment on function public.wms_unit_counts_refresh(uuid) is 'wun-1 판정 881: 오피스가 유닛을 더하거나 뺀 뒤 wms_order_finalize.units · units_without_dims 를 Finalize 와 같은 식으로 다시 센다(fulfillment_type · finalized_by · finalized_at 은 그대로) · 속 함수(직원 실행권 없음)';

-- ═══ 2) 창구 wms_unit_add — 같은 유닛 n 개를 한 번에 · 꼴 · 보안은 customer_default_carrier_set(cdc-1) 그대로 · 문 = sales 쓰기 ═══
create function public.wms_unit_add(p_so_id uuid, p_type text, p_length numeric, p_width numeric, p_height numeric, p_weight numeric, p_count int default 1, p_dim_unit text default 'in', p_weight_unit text default 'lb') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_so public.so%rowtype;  v_u public.wms_pallets%rowtype;  v_staff uuid;  v_other text;  v_max int;  v_pfx text;  v_ship text;  v_out jsonb := '[]'::jsonb;  i int;
begin
  perform public.ims_require_write('sales');                                                                                               -- ⭐ 첫 줄 · 881 ⑤
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if p_type is null or p_type not in ('box', 'pallet') then raise exception 'Unit type "%" is not box or pallet — nothing was saved', coalesce(p_type, ''); end if;
  if p_count is null or p_count < 1 or p_count > 20 then raise exception 'Count % is out of range — add 1 to 20 units at a time — nothing was saved', coalesce(p_count::text, 'null'); end if;
  if p_dim_unit is null or p_dim_unit not in ('in', 'cm') then raise exception 'Size unit "%" is not in or cm — nothing was saved', coalesce(p_dim_unit, ''); end if;
  if p_weight_unit is null or p_weight_unit not in ('lb', 'kg') then raise exception 'Weight unit "%" is not lb or kg — nothing was saved', coalesce(p_weight_unit, ''); end if;
  if coalesce(p_length, 0) <= 0 or coalesce(p_width, 0) <= 0 or coalesce(p_height, 0) <= 0 or coalesce(p_weight, 0) <= 0 then
    raise exception 'Length, width, height and weight must all be greater than 0 — nothing was saved';
  end if;
  select * into v_so from public.so s where s.id = p_so_id for update;                                                                      -- 잠금 — 동시 더하기의 번호가 겹치지 않게
  if not found then raise exception 'Order % not found — nothing was saved', p_so_id; end if;
  if v_so.status not in ('picking', 'packed') then                                                                                          -- 881 ④
    raise exception 'Order % is % — boxes and pallets can be added only while it is Working or Finalized — nothing was saved', v_so.so_number, v_so.status;
  end if;
  v_ship := public.wms_unit_booking_gate(p_so_id, v_so.so_number);                                                                          -- 881 ⑦
  select string_agg(distinct u.unit_type, ' + ') into v_other from public.wms_pallets u where u.order_id = p_so_id and u.parent_id is null and u.unit_type <> p_type;   -- 881 ⑥ · 맨 위 유닛(fc_units_snapshot 과 같은 범위)
  if v_other is not null then
    raise exception 'Order % already has % — one order is all boxes or all pallets (this shipment would mix boxes and pallets) — nothing was saved', v_so.so_number, case v_other when 'box' then 'boxes' else 'pallets' end;
  end if;
  select coalesce(max((regexp_match(u.label, '^[PB](\d+)$'))[1]::int), 0) into v_max                                                        -- 창고 화면 nextUnitLabel: 같은 종류 · ^[PB]\d+$ · 최대 + 1
    from public.wms_pallets u where u.order_id = p_so_id and u.unit_type = p_type and u.label ~ '^[PB]\d+$';
  v_pfx := case p_type when 'box' then 'B' else 'P' end;
  for i in 1 .. p_count loop
    insert into public.wms_pallets (order_id, unit_type, label, parent_id, status, created_by, dim_length, dim_width, dim_height, dim_unit, weight, weight_unit)
    values (p_so_id, p_type, v_pfx || (v_max + i)::text, null, 'building', v_staff, p_length, p_width, p_height, p_dim_unit, p_weight, p_weight_unit)
    returning * into v_u;
    v_out := v_out || jsonb_build_object('unit_id', v_u.id, 'label', v_u.label, 'unit_type', v_u.unit_type,
                                         'length_in', v_u.length_in, 'width_in', v_u.width_in, 'height_in', v_u.height_in, 'weight_lb', v_u.weight_lb);
  end loop;
  perform public.wms_unit_counts_refresh(p_so_id);
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'unit_type', p_type, 'added', p_count, 'units', v_out,
                            'unit_ids', (select jsonb_agg(e->'unit_id') from jsonb_array_elements(v_out) e), 'labels', (select jsonb_agg(e->'label') from jsonb_array_elements(v_out) e),
                            'shipment_status', v_ship, 'units_changed', v_ship is not null);
end;
$$;
revoke all on function public.wms_unit_add(uuid, text, numeric, numeric, numeric, numeric, int, text, text) from public, anon, service_role;
grant execute on function public.wms_unit_add(uuid, text, numeric, numeric, numeric, numeric, int, text, text) to authenticated;
comment on function public.wms_unit_add(uuid, text, numeric, numeric, numeric, numeric, int, text, text) is 'wun-1 판정 881: 오피스가 발송 유닛을 더한다(sales 쓰기 · picking · packed 만 · 종류 box|pallet · 크기 · 무게 > 0 · 개수 1 ~ 20 · 단위 in|cm · lb|kg) — 이름은 창고 화면과 같은 규칙(그 오더의 같은 종류 ^[PB]\d+$ 최대 + 1 · so 행 잠금) · 칸은 창고 addUnit 과 같게(parent null · building · created_by) + 치수(트리거가 in · lb) · 맨 위 유닛과 종류가 다르면 거부(⑥) · 발송이 booked 거나 pending 10 분 안이면 거부(⑦) · Finalize 기록의 유닛 수 다시 셈 · 반환 {so_id, so_number, unit_type, added, units[{unit_id, label, unit_type, length_in, width_in, height_in, weight_lb}], unit_ids[], labels[], shipment_status, units_changed}';

-- ═══ 3) 창구 wms_unit_remove — 빈 유닛만 · 다른 유닛 이름은 다시 매기지 않는다 ═══
create function public.wms_unit_remove(p_so_id uuid, p_unit_id bigint) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_so public.so%rowtype;  v_u public.wms_pallets%rowtype;  v_n int;  v_ship text;
begin
  perform public.ims_require_write('sales');                                                                                               -- ⭐ 첫 줄 · 881 ⑤
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order % not found — nothing was saved', p_so_id; end if;
  if v_so.status not in ('picking', 'packed') then                                                                                          -- 881 ④
    raise exception 'Order % is % — boxes and pallets can be removed only while it is Working or Finalized — nothing was saved', v_so.so_number, v_so.status;
  end if;
  select * into v_u from public.wms_pallets u where u.id = p_unit_id for update;
  if not found then raise exception 'Unit % not found — nothing was saved', p_unit_id; end if;
  if v_u.order_id is distinct from p_so_id then raise exception 'Unit % (%) belongs to another order — nothing was saved', p_unit_id, coalesce(v_u.label, ''); end if;
  v_ship := public.wms_unit_booking_gate(p_so_id, v_so.so_number);                                                                          -- 881 ⑦
  select count(*) into v_n from public.wms_pallet_items i where i.pallet_id = p_unit_id;                                                    -- 881 ③ · 다른 오더의 물건이 올라 있어도 막는다
  if v_n > 0 then raise exception 'Unit % has % item line(s) packed in it — only empty units can be removed (the warehouse unpacks it) — nothing was saved', coalesce(v_u.label, p_unit_id::text), v_n; end if;
  select count(*) into v_n from public.wms_pallets c where c.parent_id = p_unit_id;                                                         -- 자식 박스가 있는 팔렛 — FK parent_id 가 막기 전에 말로
  if v_n > 0 then raise exception 'Unit % has % box(es) on it — remove or move them first — nothing was saved', coalesce(v_u.label, p_unit_id::text), v_n; end if;
  delete from public.wms_pallets u where u.id = p_unit_id;
  perform public.wms_unit_counts_refresh(p_so_id);
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'unit_id', p_unit_id, 'label', v_u.label, 'unit_type', v_u.unit_type, 'removed', true,
                            'shipment_status', v_ship, 'units_changed', v_ship is not null);
end;
$$;
revoke all on function public.wms_unit_remove(uuid, bigint) from public, anon, service_role;
grant execute on function public.wms_unit_remove(uuid, bigint) to authenticated;
comment on function public.wms_unit_remove(uuid, bigint) is 'wun-1 판정 881: 오피스가 발송 유닛을 뺀다(sales 쓰기 · picking · packed 만 · 그 오더의 유닛만) — 담긴 물건(wms_pallet_items)이 있으면 거부(③ · 창고가 담은 기록이 고아가 된다) · 자식 박스가 있으면 거부 · 발송이 booked 거나 pending 10 분 안이면 거부(⑦) · 다른 유닛 이름은 다시 매기지 않는다 · Finalize 기록의 유닛 수 다시 셈 · 반환 {so_id, so_number, unit_id, label, unit_type, removed, shipment_status, units_changed}';

-- ═══ 4) 착지 — 셋이 섰고 · 권한 · definer · search_path ═══
do $$
declare v_n int;
begin
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('wms_unit_add', 'wms_unit_remove', 'wms_unit_booking_gate', 'wms_unit_counts_refresh')
     and p.prosecdef and array_to_string(p.proconfig, ',') ~ 'search_path=public, pg_temp';
  if v_n <> 4 then raise exception 'wun-1: expected 4 definer functions with search_path pinned, found %', v_n; end if;
  if not has_function_privilege('authenticated', 'public.wms_unit_add(uuid, text, numeric, numeric, numeric, numeric, int, text, text)', 'execute')
     or has_function_privilege('anon', 'public.wms_unit_add(uuid, text, numeric, numeric, numeric, numeric, int, text, text)', 'execute')
     or not has_function_privilege('authenticated', 'public.wms_unit_remove(uuid, bigint)', 'execute')
     or has_function_privilege('anon', 'public.wms_unit_remove(uuid, bigint)', 'execute')
     or has_function_privilege('authenticated', 'public.wms_unit_booking_gate(uuid, text)', 'execute')
     or has_function_privilege('authenticated', 'public.wms_unit_counts_refresh(uuid)', 'execute') then
    raise exception 'wun-1: function privileges are not as expected';
  end if;
end $$;
