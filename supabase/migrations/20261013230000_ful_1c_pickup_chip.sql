-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- ful-1c — 픽업 칩(모든 채널) DB · 화면(ful-3)이 보낼 운송사 id 받기 (2026-10-13 · 판정 436 · 443 · 452 · 455 · ful-0b ⬜4 · ful-1b 20261013210000 위에)
--   ① so.picked_up_at · picked_up_by — 찾아감은 SO 의 사실(판정 443 · 455 · SO 상태 무접촉) · 칩 = 채널 warehouse ∧ 운송사 종류 pickup ∧ shipped_at ∧ (picked_up_at 없음 → Waiting for pickup · 있음 → Picked up)
--      운송사 종류는 so 에 칸을 두지 않는다 — 목록이 carrier:carrier_id(kind,name) 로 끼워 읽고 「Waiting 만」 필터 때만 !inner(이견 1 · 동기화할 칸이 없다)
--   ② 창구 so_picked_up(p_so_id) — 옛 shop_fulfill_picked_up(ful-1b) 을 대신한다(지움 · 호출처 0 — EF 주석 두 줄만)
--      문 = 위 조건 넷 + 아직 안 찾아감 · Shopify 픽업 행: sent + ready_at → 결과 표 · 큐 picked_up(ful-1b 그대로) · pending → 거절(1 분 안에 풀린다 · 찾아간 뒤 Ready 메일이 가는 것을 막는다) · error · skipped → IMS 만 + 경고 pickup_not_sent
--   ③ shop_order_warn 재발행(ful-1b) — 코드 pickup_not_sent 더함
--   ④ 이관 — 결과 표에 이미 있는 찾아감(SO-25086)을 so 칸으로(touch 트리거를 잠시 끄고 · updated_by 를 안 덮는다)
--   ⑤ so_header_update 재발행(마지막 정의 dsc_3a 20261006201443:405 바이트 복사) — 열쇠 carrier_id · carrier 글자는 표 이름만(판정 436) · 초안만은 그대로
--   ⑥ so_merge 재발행(마지막 정의 dsc_3b 20261006204146:665 바이트 복사) — 새 머리의 carrier_id 도 null(carrier · tracking_number 와 같이)
--   ⚠️ 무접촉: so_finalize · so_ship · so_copy_customer · EF · 화면 · cron · 456(짓는 것 없음) · 찾아감 되돌리기(미룬 — manager SQL)
--   적용: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f <이 파일> && supabase migration repair --status applied <버전> --db-url "$(cat ~/.asung-testdb-url)"
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

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


-- ═══ 1) so 칸 ═══
alter table public.so add column picked_up_at timestamptz;
alter table public.so add column picked_up_by uuid references public.ims_staff (id) on delete no action;
alter table public.so add constraint so_picked_up_pair_ck check ((picked_up_at is null) = (picked_up_by is null));
alter table public.so add constraint so_picked_up_shipped_ck check (picked_up_at is null or shipped_at is not null);
create index so_picked_up_by_idx on public.so (picked_up_by);
comment on column public.so.picked_up_at is 'ful-1c 판정 443 · 455: 손님이 창고에 와서 찾아간 시각(창구 so_picked_up · 직원이 본 사실 · SO 상태 무접촉) — 칩: channel warehouse ∧ 운송사 종류 pickup(ref_carrier.kind) ∧ shipped_at ∧ 이 칸 없음 = Waiting for pickup · 있음 = Picked up';
comment on column public.so.picked_up_by is 'ful-1c: Picked up 을 누른 직원(picked_up_at 과 짝)';

-- ═══ 2) shop_order_warn 재발행(ful-1b 20261013210000 의 몸 + 코드 pickup_not_sent) ═══
create or replace function public.shop_order_warn(p_shop_order_id uuid, p_code text, p_message text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_w jsonb;
begin
  if p_code not in ('fulfill_failed', 'fulfill_cut', 'fulfill_location_mismatch', 'fulfill_nothing_left', 'pickup_failed', 'tracking_fix_failed', 'pickup_not_sent') then
    raise exception 'shop_order_warn: code % is not one of fulfill_failed, fulfill_cut, fulfill_location_mismatch, fulfill_nothing_left, pickup_failed, tracking_fix_failed, pickup_not_sent — nothing was saved', p_code;
  end if;
  update public.shop_order set warnings = warnings || jsonb_build_array(jsonb_build_object('code', p_code, 'message', nullif(btrim(coalesce(p_message, '')), ''), 'at', now()))
   where id = p_shop_order_id
  returning warnings into v_w;
  if not found then raise exception 'shop_order_warn: shop_order % not found — nothing was saved', p_shop_order_id; end if;
  return jsonb_build_object('shop_order_id', p_shop_order_id, 'code', p_code, 'warnings', jsonb_array_length(v_w));
end;
$$;
comment on function public.shop_order_warn(uuid, text, text) is 'ful-2a · ful-1b · ful-1c: shop_order.warnings 에 경고 한 줄 {code, message, at} 을 더한다 — 한 문장(warnings || …) · 코드 일곱(fulfill_failed · fulfill_cut · fulfill_location_mismatch · fulfill_nothing_left · pickup_failed · tracking_fix_failed · pickup_not_sent) · service_role 만(EF) · definer 창구 so_picked_up 안에서도';

-- ═══ 3) so_picked_up — Picked up 창구(판정 443 · 455) · 옛 shop_fulfill_picked_up 을 대신한다 ═══
drop function public.shop_fulfill_picked_up(uuid);
create function public.so_picked_up(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  v_car    public.ref_carrier%rowtype;
  v_now    timestamptz := now();
  v_ready  int := 0;
  v_q      bigint;
  v_warn   jsonb := '[]'::jsonb;
  r        record;
begin
  perform public.ims_require_write('sales', 'saved');
  v_staff := public.so_current_staff();
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order % not found — nothing was saved', p_so_id; end if;
  if v_so.channel <> 'warehouse' then
    raise exception 'Order % is a % order — it was handed over at the counter, there is no pickup to record — nothing was saved', v_so.so_number, v_so.channel;
  end if;
  if v_so.carrier_id is not null then select * into v_car from public.ref_carrier rc where rc.id = v_so.carrier_id; end if;
  if v_car.kind is distinct from 'pickup' then
    raise exception 'Order % is not a pickup order (carrier %) — nothing was saved', v_so.so_number, coalesce(v_car.name, v_so.carrier, 'none');
  end if;
  if v_so.shipped_at is null then
    raise exception 'Order % has not been shipped yet — Ship & invoice it first, then mark it picked up — nothing was saved', v_so.so_number;
  end if;
  if v_so.picked_up_at is not null then
    raise exception 'Order % was already picked up (%) — nothing was saved', v_so.so_number, to_char(v_so.picked_up_at at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI');
  end if;
  if exists (select 1 from public.shop_fulfillment f where f.so_id = p_so_id and f.carrier_kind = 'pickup' and f.status = 'pending') then
    raise exception 'Order %: Shopify is still being told the order is ready for pickup — try again in a minute — nothing was saved', v_so.so_number;
  end if;

  update public.so s set picked_up_at = v_now, picked_up_by = v_staff, updated_by = v_staff where s.id = p_so_id;
  -- Shopify 짝 — Ready 가 간 행(sent + ready_at)만 결과 표에 적고 큐 picked_up(ful-1b 그대로 · EF 가 픽업 FO 에 fulfillmentCreate notify false)
  update public.shop_fulfillment f set picked_up_at = v_now, picked_up_by = v_staff, updated_by = v_staff
   where f.so_id = p_so_id and f.carrier_kind = 'pickup' and f.status = 'sent' and f.ready_at is not null and f.picked_up_at is null and f.shopify_fulfillment_gid is null;
  get diagnostics v_ready = row_count;
  if v_ready > 0 then v_q := public.shop_fulfill_requeue(p_so_id, 'picked_up'); end if;
  -- Ready 가 Shopify 에 못 간 행(error · skipped) — IMS 에만 적고 Web Orders 경고(직원이 Shopify 에서 손으로 Mark as picked up)
  for r in select f.id, f.shop_order_id, f.status, o.name from public.shop_fulfillment f join public.shop_order o on o.id = f.shop_order_id
            where f.so_id = p_so_id and f.carrier_kind = 'pickup' and f.status in ('error', 'skipped') loop
    perform public.shop_order_warn(r.shop_order_id, 'pickup_not_sent',
      format('IMS order %s was picked up, but Shopify order %s never got "Ready for pickup" (%s) — mark it picked up in Shopify by hand', v_so.so_number, r.name, r.status));
    v_warn := v_warn || jsonb_build_object('code', 'pickup_not_sent', 'shopify_order', r.name, 'status', r.status);
  end loop;
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'picked_up_at', v_now, 'picked_up_by', v_staff,
                            'shopify', v_ready > 0, 'shopify_fulfillments', v_ready, 'queue_id', v_q, 'warnings', v_warn);
end;
$$;
revoke all on function public.so_picked_up(uuid) from public, anon;
grant execute on function public.so_picked_up(uuid) to authenticated;
comment on function public.so_picked_up(uuid) is 'ful-1c 판정 443 · 455: 손님이 찾아갔다 — 문 = 채널 warehouse(counter · pos 거절) · 운송사 종류 pickup · shipped_at 있음 · 아직 안 찾아감 · Shopify 픽업 행이 pending 이면 거절(1 분 안에 다시) → so.picked_up_at · picked_up_by(SO 상태 무접촉) · Shopify 픽업 행이 sent + ready_at 이면 결과 표에도 적고 큐 picked_up(EF → fulfillmentCreate notify false) · error · skipped 면 IMS 만 + shop_order 경고 pickup_not_sent · 반환 {so_id, so_number, picked_up_at, picked_up_by, shopify, shopify_fulfillments, queue_id, warnings} · sales 쓰기 · definer · 되돌리기 없음(미룬)';
comment on function public.shop_fulfill_requeue(uuid, text) is 'ful-1b · ful-1c: 발송 큐에 (so, kind) 행을 넣거나 있으면 다시 연다(attempts 0 · 결과 지움) — 창구 so_picked_up · so_tracking_fix 가 definer 안에서 부른다 · 직접 호출 불가';
comment on column public.shop_fulfillment.picked_up_by is 'ful-1b · ful-1c: Picked up 을 누른 직원(창구 so_picked_up 이 so.picked_up_by 와 함께 적는다 · Shopify 로 보낼 행만)';

-- ═══ 4) 이관 — 결과 표의 찾아감을 so 로(이미 출고된 Shopify 픽업 SO · touch 트리거를 잠시 끈다) ═══
alter table public.so disable trigger so_touch;
update public.so s set picked_up_at = x.at, picked_up_by = x.by
  from (select distinct on (f.so_id) f.so_id, f.picked_up_at as at, f.picked_up_by as by
          from public.shop_fulfillment f where f.carrier_kind = 'pickup' and f.picked_up_at is not null and f.picked_up_by is not null
         order by f.so_id, f.picked_up_at) x
 where s.id = x.so_id and s.picked_up_at is null and s.shipped_at is not null;
alter table public.so enable trigger so_touch;

-- ═══ 5) so_header_update 재발행 — dsc_3a 20261006201443:405 ~ 607 바이트 복사 · 더한 줄: 열쇠 1 · 선언 1 · 운송사 블록 · update 두 줄(carrier_id · carrier) ═══
create or replace function public.so_header_update(p_so_id uuid, p_patch jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_keys  constant text[] := array[
    'customer_id', 'location_id', 'payment_term_id', 'discount_pct', 'tax_rule', 'price_tier',
    'order_date', 'required_by', 'ref', 'comments', 'shipping_notes', 'carrier', 'carrier_id', 'tracking_number',   -- ful-1c: carrier_id
    'bill_to_name', 'bill_to_line1', 'bill_to_line2', 'bill_to_city', 'bill_to_state_province', 'bill_to_postal_code', 'bill_to_country',
    'ship_to_company', 'ship_to_contact', 'ship_to_phone', 'ship_to_line1', 'ship_to_line2', 'ship_to_city', 'ship_to_state_province', 'ship_to_postal_code', 'ship_to_country',
    'order_discount_pct'];
  v_staff uuid;
  v_so    public.so%rowtype;
  v_key   text;
  v_bad   text;
  v_n_lines int;  v_n_charges int;
  c       public.customer%rowtype;
  v_wh    public.ref_warehouse%rowtype;
  v_pt    public.ref_payment_term%rowtype;
  v_tier  public.ref_price_tier%rowtype;
  v_disc  numeric;
  v_od    numeric;
  od      record;
  v_reprice boolean := false;
  v_warn  text[] := '{}';
  v_n     int;
  v_prev_c text;  v_prev_s text;                              -- 세금 ② — 바뀌기 전 배송지 나라·주(판정 7)
  v_tax   jsonb;  v_tw text[];
  v_car   public.ref_carrier%rowtype;  v_car2 public.ref_carrier%rowtype;  v_car_touch boolean := false;   -- ful-1c 판정 436: 운송사(표)
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'p_patch must be a JSON object — nothing was saved';
  end if;
  select k into v_bad from jsonb_object_keys(p_patch) k where k <> all (c_keys) limit 1;
  if v_bad is not null then
    raise exception 'Unknown field % — nothing was saved', v_bad;
  end if;
  if p_patch = '{}'::jsonb then
    raise exception 'Nothing to change — nothing was saved';
  end if;

  select count(*) into v_n_lines   from public.so_line   where so_id = p_so_id;
  select count(*) into v_n_charges from public.so_charge where so_id = p_so_id;

  -- 손님 바꾸기(⬜6) — 줄·운임이 있으면 거부 · 비활성 거부(판정 A) · so_copy_customer 가 다시 굳힌다(창고는 이미 있으면 그대로)
  if p_patch ? 'customer_id' then
    if v_n_lines + v_n_charges > 0 then
      raise exception 'Remove all lines and charges before changing the customer — nothing was saved';
    end if;
    select * into c from public.customer where id = nullif(p_patch->>'customer_id', '')::uuid;
    if not found then
      raise exception 'Customer not found — nothing was saved';
    end if;
    if not c.is_active then
      raise exception 'Customer % is inactive — reactivate it first — nothing was saved', c.name;
    end if;
    perform public.so_copy_customer(p_so_id, c.id);
    select * into v_so from public.so where id = p_so_id;
  end if;

  -- 창고 — 준 값 검사(null 이면 비운다)
  if p_patch ? 'location_id' then
    if jsonb_typeof(p_patch->'location_id') = 'null' or p_patch->>'location_id' = '' then
      v_wh := null;
    else
      select * into v_wh from public.ref_warehouse where id = (p_patch->>'location_id')::uuid;
      if not found then
        raise exception 'Warehouse not found — nothing was saved';
      end if;
      if not v_wh.is_active then
        raise exception 'Warehouse % is inactive — nothing was saved', v_wh.name;
      end if;
    end if;
  end if;

  -- 결제조건 — FK + 원문 짝
  if p_patch ? 'payment_term_id' then
    if jsonb_typeof(p_patch->'payment_term_id') = 'null' or p_patch->>'payment_term_id' = '' then
      v_pt := null;
    else
      select * into v_pt from public.ref_payment_term where id = (p_patch->>'payment_term_id')::uuid;
      if not found then
        raise exception 'Payment term not found — nothing was saved';
      end if;
    end if;
  end if;

  -- 손님 기본 할인 — 0~100 · 이미 들어간 줄의 할인은 따라가지 않는다(넣는 순간 굳힌다 · ⬜5) · 줄이 있으면 reprice_suggested(판정 3)
  if p_patch ? 'discount_pct' then
    v_disc := nullif(p_patch->>'discount_pct', '')::numeric;
    if v_disc is not null and (v_disc < 0 or v_disc > 100) then
      raise exception 'discount_pct must be between 0 and 100 — nothing was saved';
    end if;
    if v_n_lines > 0 then v_warn := array_append(v_warn, 'lines_keep_prices'); v_reprice := true; end if;
  end if;

  -- 티어(판정 B ⑤) — 이름으로 받아 purpose sale · 활성만 · 원문 + FK 짝으로 · 들어간 줄의 가격은 그대로(④ 로 보인다) · 줄이 있으면 reprice_suggested
  if p_patch ? 'price_tier' then
    select * into v_tier from public.ref_price_tier where name = p_patch->>'price_tier';
    if not found then
      raise exception 'Price tier % not found — nothing was saved', p_patch->>'price_tier';
    end if;
    if v_tier.purpose <> 'sale' then
      raise exception 'Price tier % is not a selling tier (purpose %) — nothing was saved', v_tier.name, v_tier.purpose;
    end if;
    if not v_tier.is_active then
      raise exception 'Price tier % is inactive — nothing was saved', v_tier.name;
    end if;
    if v_n_lines > 0 then v_warn := array_append(v_warn, 'lines_keep_prices'); v_reprice := true; end if;
  end if;

  -- 오더 날짜 — 딜 기간의 기준(D7) · 줄이 있으면 reprice_suggested(줄은 그대로 · 판정 3)
  if p_patch ? 'order_date' and v_n_lines > 0 and nullif(p_patch->>'order_date', '')::date is distinct from v_so.order_date then
    v_reprice := true;
  end if;

  -- 오더 전체 할인 — 값이면 manual(0~100 · 0 = 사람이 껐다) · null 이면 다시 찾기(아래)
  if p_patch ? 'order_discount_pct' then
    v_od := nullif(p_patch->>'order_discount_pct', '')::numeric;
    if v_od is not null and (v_od < 0 or v_od > 100) then
      raise exception 'order_discount_pct must be between 0 and 100 — nothing was saved';
    end if;
  end if;

  -- ful-1c 판정 436 · 452: 운송사 — 열쇠 carrier_id(표 행 id) 또는 carrier(표 이름과 정확히 같은 글자 · 대소문자 · 앞뒤 공백 무시 · so_finalize 의 글자 길과 같다) · null · '' = 둘 다 비움
  --   켜진 행만 · 둘이 함께 오면 같은 행이어야 · 글자 칸은 늘 표 이름(옛 자유 글자를 새로 쓰지 않는다) · 손님 바꾸기(so_copy_customer)가 이미 채운 값은 열쇠가 없으면 그대로
  if p_patch ? 'carrier_id' or p_patch ? 'carrier' then
    v_car_touch := true;
    if p_patch ? 'carrier_id' and p_patch ? 'carrier'
       and (nullif(p_patch->>'carrier_id', '') is null) <> (nullif(trim(coalesce(p_patch->>'carrier', '')), '') is null) then
      raise exception 'carrier_id and carrier disagree (one is empty) — send one of them — nothing was saved';
    end if;
    if nullif(p_patch->>'carrier_id', '') is not null then
      select * into v_car from public.ref_carrier rc where rc.id = (p_patch->>'carrier_id')::uuid;
      if not found then raise exception 'Carrier % is not on the carrier list — nothing was saved', p_patch->>'carrier_id'; end if;
    end if;
    if nullif(trim(coalesce(p_patch->>'carrier', '')), '') is not null then
      select * into v_car2 from public.ref_carrier rc where lower(rc.name) = lower(trim(p_patch->>'carrier')) order by rc.is_active desc, rc.name limit 1;
      if not found then raise exception 'Carrier "%" is not on the carrier list — pick one from the list (Pickup and Delivery are on it too) — nothing was saved', trim(p_patch->>'carrier'); end if;
      if v_car.id is not null and v_car.id <> v_car2.id then
        raise exception 'carrier_id (%) and carrier "%" are different carriers — send one of them — nothing was saved', v_car.name, trim(p_patch->>'carrier');
      end if;
      v_car := v_car2;
    end if;
    if v_car.id is not null and not v_car.is_active then
      raise exception 'Carrier % is switched off — pick an active carrier — nothing was saved', v_car.name;
    end if;
  end if;

  v_prev_c := v_so.ship_to_country;  v_prev_s := v_so.ship_to_state_province;     -- 세금 ② — 손님을 바꿨으면 이미 새 손님의 배송지(so_copy_customer 가 그 안에서 골랐다)
  update public.so s set
    location_id        = case when p_patch ? 'location_id'     then v_wh.id   else s.location_id end,
    location_name      = case when p_patch ? 'location_id'     then v_wh.name else s.location_name end,
    payment_term_id    = case when p_patch ? 'payment_term_id' then v_pt.id   else s.payment_term_id end,
    payment_term_name  = case when p_patch ? 'payment_term_id' then v_pt.name else s.payment_term_name end,
    discount_pct       = case when p_patch ? 'discount_pct'    then v_disc    else s.discount_pct end,
    price_tier         = case when p_patch ? 'price_tier'      then v_tier.name else s.price_tier end,
    price_tier_id      = case when p_patch ? 'price_tier'      then v_tier.id   else s.price_tier_id end,
    order_date         = case when p_patch ? 'order_date'      then coalesce(nullif(p_patch->>'order_date', '')::date, s.order_date) else s.order_date end,
    required_by        = case when p_patch ? 'required_by'     then nullif(p_patch->>'required_by', '')::date else s.required_by end,
    ref                = case when p_patch ? 'ref'             then nullif(trim(p_patch->>'ref'), '') else s.ref end,
    comments           = case when p_patch ? 'comments'        then nullif(trim(p_patch->>'comments'), '') else s.comments end,
    shipping_notes     = case when p_patch ? 'shipping_notes'  then nullif(trim(p_patch->>'shipping_notes'), '') else s.shipping_notes end,
    carrier_id         = case when v_car_touch                 then v_car.id   else s.carrier_id end,          -- ful-1c: id 와 글자를 같이(글자 = 표 이름)
    carrier            = case when v_car_touch                 then v_car.name else s.carrier end,
    tracking_number    = case when p_patch ? 'tracking_number' then nullif(trim(p_patch->>'tracking_number'), '') else s.tracking_number end,
    bill_to_name           = case when p_patch ? 'bill_to_name'           then nullif(trim(p_patch->>'bill_to_name'), '')           else s.bill_to_name end,
    bill_to_line1          = case when p_patch ? 'bill_to_line1'          then nullif(trim(p_patch->>'bill_to_line1'), '')          else s.bill_to_line1 end,
    bill_to_line2          = case when p_patch ? 'bill_to_line2'          then nullif(trim(p_patch->>'bill_to_line2'), '')          else s.bill_to_line2 end,
    bill_to_city           = case when p_patch ? 'bill_to_city'           then nullif(trim(p_patch->>'bill_to_city'), '')           else s.bill_to_city end,
    bill_to_state_province = case when p_patch ? 'bill_to_state_province' then nullif(trim(p_patch->>'bill_to_state_province'), '') else s.bill_to_state_province end,
    bill_to_postal_code    = case when p_patch ? 'bill_to_postal_code'    then nullif(trim(p_patch->>'bill_to_postal_code'), '')    else s.bill_to_postal_code end,
    bill_to_country        = case when p_patch ? 'bill_to_country'        then nullif(trim(p_patch->>'bill_to_country'), '')        else s.bill_to_country end,
    ship_to_company        = case when p_patch ? 'ship_to_company'        then nullif(trim(p_patch->>'ship_to_company'), '')        else s.ship_to_company end,
    ship_to_contact        = case when p_patch ? 'ship_to_contact'        then nullif(trim(p_patch->>'ship_to_contact'), '')        else s.ship_to_contact end,
    ship_to_phone          = case when p_patch ? 'ship_to_phone'          then nullif(trim(p_patch->>'ship_to_phone'), '')          else s.ship_to_phone end,
    ship_to_line1          = case when p_patch ? 'ship_to_line1'          then nullif(trim(p_patch->>'ship_to_line1'), '')          else s.ship_to_line1 end,
    ship_to_line2          = case when p_patch ? 'ship_to_line2'          then nullif(trim(p_patch->>'ship_to_line2'), '')          else s.ship_to_line2 end,
    ship_to_city           = case when p_patch ? 'ship_to_city'           then nullif(trim(p_patch->>'ship_to_city'), '')           else s.ship_to_city end,
    ship_to_state_province = case when p_patch ? 'ship_to_state_province' then nullif(trim(p_patch->>'ship_to_state_province'), '') else s.ship_to_state_province end,
    ship_to_postal_code    = case when p_patch ? 'ship_to_postal_code'    then nullif(trim(p_patch->>'ship_to_postal_code'), '')    else s.ship_to_postal_code end,
    ship_to_country        = case when p_patch ? 'ship_to_country'        then nullif(trim(p_patch->>'ship_to_country'), '')        else s.ship_to_country end,
    reprice_suggested_at   = case when v_reprice then now() else s.reprice_suggested_at end,
    updated_by         = v_staff
  where s.id = p_so_id and s.status = 'draft'
  returning * into v_so;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order was not saved — it may have been changed by someone else just now — nothing was saved';
  end if;

  -- 오더 전체 할인(D6 · ⬜4) — 값을 받았으면 manual · null 을 받았거나(다시 찾기) 손님·오더 날짜가 바뀌었는데 source 가 manual 이 아니면 so_order_discount 로 다시
  if p_patch ? 'order_discount_pct' and v_od is not null then
    update public.so set order_discount_pct = v_od, order_discount_deal_id = null, order_discount_source = 'manual', updated_by = v_staff
    where id = p_so_id and status = 'draft' returning * into v_so;
  elsif p_patch ? 'order_discount_pct' then
    v_so := public.so_order_discount_apply(p_so_id, v_staff, true);         -- dsc-3a 판정 308 · 312: null = 다시 찾기 — 사람의 뜻이라 manual · 잠금을 넘는다(잠금 자체는 남는다)
  elsif p_patch ? 'customer_id' or p_patch ? 'order_date' then
    v_so := public.so_order_discount_apply(p_so_id, v_staff);               -- dsc-3a 판정 308: manual · 잠긴 오더는 helper 가 그대로 둔다
  end if;

  -- 세금 규칙(세금 ② · 판정 7·8·9) — 배송지의 나라·주 열쇠가 오면 다시 고른다(manual 이었으면 같은 나라·주는 그대로 · 다르면 되돌리고 경고 tax_rule_reset_by_ship_to) ·
  --   열쇠 tax_rule: 활성 sale 규칙 이름 → manual(so_tax_set_manual) · null → manual 을 풀고 배송지로(so_tax_refresh p_clear_manual) · 줄·운임의 tax_rule 은 두 속 함수가 함께 맞춘다
  if p_patch ? 'ship_to_country' or p_patch ? 'ship_to_state_province' then
    v_tax := public.so_tax_refresh(p_so_id, v_staff, v_prev_c, v_prev_s);
    select array_agg(t.v) into v_tw from jsonb_array_elements_text(v_tax->'warnings') as t(v);
    v_warn := v_warn || coalesce(v_tw, '{}');
  end if;
  if p_patch ? 'tax_rule' then
    if nullif(trim(p_patch->>'tax_rule'), '') is null then
      v_tax := public.so_tax_refresh(p_so_id, v_staff, null, null, true);
    else
      v_tax := public.so_tax_set_manual(p_so_id, v_staff, p_patch->>'tax_rule');
    end if;
    select array_agg(t.v) into v_tw from jsonb_array_elements_text(v_tax->'warnings') as t(v);
    v_warn := v_warn || coalesce(v_tw, '{}');
  end if;
  if v_tax is not null then
    select * into v_so from public.so where id = p_so_id;
  end if;

  if v_reprice then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  v_warn := v_warn || public.so_tier_warnings(v_so);
  return jsonb_build_object('so', to_jsonb(v_so), 'tax', v_tax, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 6) so_merge 재발행 — dsc_3b 20261006204146:665 ~ 953 바이트 복사 · 바꾼 줄 1(새 머리 carrier_id null) ═══
create or replace function public.so_merge(p_so_ids uuid[], p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_head_fields constant text[] := array['ship_to_company','ship_to_contact','ship_to_phone','ship_to_line1','ship_to_line2','ship_to_city','ship_to_state_province','ship_to_postal_code','ship_to_country',
                                         'bill_to_customer_id','bill_to_name','bill_to_line1','bill_to_line2','bill_to_city','bill_to_state_province','bill_to_postal_code','bill_to_country',
                                         'payment_term_id','payment_term_name','price_tier','price_tier_id','tax_rule','tax_rule_id','tax_rule_manual','discount_pct',
                                         'order_discount_pct','order_discount_source','order_discount_deal_id','required_by','ref','comments','intake',
                                         'carrier','tracking_number','shipping_notes','ar_account_code','sale_account_code'];
  v_staff   uuid;
  v_ids     uuid[];
  v_n       int;
  v_today   date := public.ims_today();
  v_old     public.so%rowtype;                       -- 가장 오래된 원본 = 머리(⬜2)
  v_head    public.so%rowtype;                       -- 미리 보기용 가상 머리(order_date = 오늘)
  v_new     public.so%rowtype;
  v_cust    public.customer%rowtype;
  v_numbers text;
  v_any_confirmed boolean;
  v_diffs   jsonb; v_plan jsonb; v_calc_in jsonb; v_hint jsonb; v_pay jsonb; v_sib jsonb; v_sup jsonb; v_charges jsonb;
  v_warn    text[] := '{}';
  v_note    text;
  v_id      uuid;
  v_line_id uuid;
  v_cnt     int;
  v_bo      int := 0; v_reopened int := 0; v_released int := 0; v_moved int := 0; v_lines_n int := 0;
  v_combos  jsonb := '[]'::jsonb;  v_comp_n int := 0;                 -- asm-2b2(묶음 2 · 3): 콤보 줄끼리 합친다(열쇠 + 구성품 모양) · 합친 콤보 줄 아래 구성품을 다시 매단다(합친 콤보 수 × combo_qty · 저장된 combo_qty 로 · 정의가 바뀐 콤보는 열쇠가 갈라 따로 둔다)
  r record;
  e jsonb;
  v_cps jsonb := '[]'::jsonb;  v_best_cp uuid;  v_best_pct numeric := -1;  v_cp_pct numeric;   -- dsc-3b 판정 324 — 원본 쿠폰 가운데 큰 쪽
  od record;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — sales 묶음
  v_staff := public.so_current_staff();

  -- ── 대상 검사 ──
  select array_agg(distinct x) into v_ids from unnest(p_so_ids) x where x is not null;
  if coalesce(array_length(p_so_ids, 1), 0) <> coalesce(array_length(v_ids, 1), 0) then raise exception 'The same order is listed twice — nothing was saved'; end if;
  if coalesce(array_length(v_ids, 1), 0) < 2 then raise exception 'A merge needs at least two orders — nothing was saved'; end if;
  perform 1 from public.so s where s.id = any(v_ids) order by s.id for update;
  get diagnostics v_n = row_count;
  if v_n <> array_length(v_ids, 1) then raise exception 'Order not found — nothing was saved'; end if;
  for r in select s.* from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number loop
    if r.status not in ('draft', 'confirmed') then
      raise exception 'Order % is % — only draft or confirmed orders still in IMS can be merged — nothing was saved', r.so_number,
        r.status || case when r.status = 'cancelled' and r.closed_reason = 'merged' then ' (already merged into ' || coalesce((select m.so_number from public.so m where m.id = r.merged_into_id), '?') || ')'
                         when r.status in ('at_wms', 'picking', 'packed') then ' (it is with the warehouse — merge is only possible before release)'
                         else '' end;
    end if;
    if r.channel <> 'warehouse' then raise exception 'Order % is a % order — only warehouse orders can be merged — nothing was saved', r.so_number, r.channel; end if;
  end loop;
  if (select count(distinct s.customer_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders belong to different customers — nothing was saved'; end if;
  if (select count(distinct coalesce(s.location_id::text, '(none)')) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are for different warehouses — change the warehouse first — nothing was saved'; end if;
  if (select count(distinct s.currency_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are in different currencies — nothing was saved'; end if;
  select c.* into v_cust from public.customer c where c.id = (select s.customer_id from public.so s where s.id = v_ids[1]);
  if not v_cust.is_active then raise exception 'Customer % is inactive — nothing was saved', v_cust.name; end if;
  v_any_confirmed := exists (select 1 from public.so s where s.id = any(v_ids) and s.status = 'confirmed');
  if v_any_confirmed then perform public.so_require_role('manager', 'saved'); end if;   -- 판정 5 · R5: 확정 오더의 재고를 푸는 순간 선을 넘는다

  select s.* into v_old from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number limit 1;
  select string_agg(s.so_number, ', ' order by s.order_date, s.so_number) into v_numbers from public.so s where s.id = any(v_ids);

  -- ── 머리 차이(판정 2·7 · 막지 않는다) ──
  select coalesce(jsonb_agg(jsonb_build_object('field', d.f, 'values', d.vals) order by d.f), '[]'::jsonb) into v_diffs
  from (select f, jsonb_agg(jsonb_build_object('so_number', s.so_number, 'value', to_jsonb(s)->f) order by s.order_date, s.so_number) as vals
        from public.so s cross join unnest(c_head_fields) f
        where s.id = any(v_ids)
        group by f having count(distinct coalesce(to_jsonb(s)->f, 'null'::jsonb)) > 1) d;

  -- ── 줄 계획(판정 4 · 고침 ①: 열쇠 = 제품 · 단가 · 정가 · 할인 % · 무상 사유 · override · 부가 셋 — tax_rule 은 열쇠 밖 · 전부 합친 오더 규칙) ──
  with src as (
    select l.*, s.so_number, dense_rank() over (order by s.order_date, s.so_number) as ord,
           exists (select 1 from public.so_reserve rs join public.so_line cp on cp.id = rs.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and rs.released_at is null and rs.kind = 'preorder')  as was_preorder,    -- asm-2b2: 콤보 줄의 예약은 구성품에
           exists (select 1 from public.so_reserve rs join public.so_line cp on cp.id = rs.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and rs.released_at is null and rs.kind = 'backorder') as was_backorder,
           (l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, v_today)) as deal_ended,
           (select string_agg(cp.sku || ':' || trim_scale(cp.combo_qty)::text, ',' order by cp.sku) from public.so_line cp where cp.combo_line_id = l.id) as combo_sig   -- asm-2b2: 콤보 줄의 구성품 모양(열쇠에 든다 · 보통 줄은 null)
    from public.so_line l join public.so s on s.id = l.so_id
    where s.id = any(v_ids) and l.combo_line_id is null                                                                                  -- asm-2b2: 구성품 줄은 계획에 들지 않는다(콤보 줄을 따라 다시 선다)
  ), grp as (
    select product_id, unit_price, list_price, discount_pct, free_reason, price_override, surcharge_pct, surcharge_amount, surcharge_label, combo_sig,
           min(ord * 100000 + line_no) as first_pos, sum(qty_ordered) as qty, count(*) as n, (array_agg(id order by ord, line_no))[1] as first_line_id,
           (array_agg(sku order by ord, line_no))[1] as sku, (array_agg(product_name order by ord, line_no))[1] as product_name,
           (array_agg(unit order by ord, line_no))[1] as unit, (array_agg(pack_factor order by ord, line_no))[1] as pack_factor,
           (array_agg(comments order by ord, line_no) filter (where comments is not null))[1] as comments,
           bool_or(was_preorder) as was_preorder, bool_or(was_backorder) as was_backorder, bool_or(deal_ended) as deal_ended,
           jsonb_agg(jsonb_build_object('so_number', so_number, 'line_no', line_no, 'line_id', id, 'qty', qty_ordered, 'discount_source', discount_source, 'deal_line_id', deal_line_id,
                                        'was_preorder', was_preorder, 'was_backorder', was_backorder) order by ord, line_no) as sources
    from src
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
  ), numbered as (
    select g.*, row_number() over (order by g.first_pos) as line_no,
           count(*) over (partition by g.product_id) as n_same_product,
           first_value(g.unit_price)     over (partition by g.product_id order by g.first_pos) as p_unit_price,
           first_value(g.list_price)     over (partition by g.product_id order by g.first_pos) as p_list_price,
           first_value(g.discount_pct)   over (partition by g.product_id order by g.first_pos) as p_discount_pct,
           first_value(g.free_reason)    over (partition by g.product_id order by g.first_pos) as p_free_reason,
           first_value(g.price_override) over (partition by g.product_id order by g.first_pos) as p_override,
           first_value(g.surcharge_label) over (partition by g.product_id order by g.first_pos) as p_surcharge_label,
           first_value(g.combo_sig)      over (partition by g.product_id order by g.first_pos) as p_combo_sig
    from grp g
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'line_no', x.line_no, 'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name, 'unit', x.unit, 'pack_factor', x.pack_factor,
           'qty', x.qty, 'list_price', x.list_price, 'discount_pct', x.discount_pct, 'unit_price', x.unit_price, 'price_override', x.price_override, 'free_reason', x.free_reason,
           'discount_source', case when x.price_override then null when x.discount_pct is not null then 'manual' else null end,
           'surcharge_pct', x.surcharge_pct, 'surcharge_amount', x.surcharge_amount, 'surcharge_label', x.surcharge_label, 'comments', x.comments,
           'source_lines', x.n, 'sources', x.sources, 'was_preorder', x.was_preorder, 'was_backorder', x.was_backorder, 'deal_ended', x.deal_ended,
           'is_combo', x.combo_sig is not null, 'combo_sig', x.combo_sig, 'first_line_id', x.first_line_id,                                              -- asm-2b2
           'kept_apart', (x.n_same_product > 1),
           'differs_in', case when x.n_same_product > 1 then
              (select coalesce(jsonb_agg(k), '[]'::jsonb) from unnest(array[
                 case when x.unit_price is distinct from x.p_unit_price then 'unit_price' end,
                 case when x.list_price is distinct from x.p_list_price then 'list_price' end,
                 case when x.discount_pct is distinct from x.p_discount_pct then 'discount_pct' end,
                 case when x.free_reason is distinct from x.p_free_reason then 'free_reason' end,
                 case when x.price_override is distinct from x.p_override then 'price_override' end,
                 case when x.surcharge_label is distinct from x.p_surcharge_label then 'surcharge' end,
                 case when x.combo_sig is distinct from x.p_combo_sig then 'combo_definition' end]) k where k is not null)
              else '[]'::jsonb end) order by x.line_no), '[]'::jsonb)
    into v_plan
  from numbered x;
  v_lines_n := coalesce(jsonb_array_length(v_plan), 0);

  -- ── 판정 4 보완 ①: 가상 머리(가장 오래된 원본 + 오늘) 로 다시 견적 ──
  v_head := v_old;
  v_head.order_date := v_today;
  select coalesce(jsonb_agg(jsonb_build_object('line_no', p->'line_no', 'product_id', p->'product_id', 'sku', p->'sku', 'qty', p->'qty', 'unit_price', p->'unit_price', 'discount_pct', p->'discount_pct',
                                               'discount_source', p->'discount_source', 'free_reason', p->'free_reason', 'price_override', p->'price_override')), '[]'::jsonb)
    into v_calc_in from jsonb_array_elements(v_plan) p;
  v_hint := public.so_merge_requote_calc(v_head, v_calc_in);

  -- ── 선결제 대상(옮긴다 · 조사 ③ unique (payment_id, so_id)) ──
  select coalesce(jsonb_agg(jsonb_build_object('payment_id', x.id, 'amount', x.amount, 'method', x.method, 'paid_on', x.paid_on, 'targets', x.targets) order by x.paid_on, x.id), '[]'::jsonb) into v_pay
  from (select p.id, p.amount, p.method, p.paid_on, jsonb_agg(s.so_number order by s.so_number) as targets
        from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active' join public.so s on s.id = o.so_id
        where o.so_id = any(v_ids) group by p.id, p.amount, p.method, p.paid_on) x;

  -- ── 판정 1 로 이어받기에서 빠질 형제(원본의 split 자손 중 열린 백오더가 있는 confirmed 오더) ──
  with recursive d as (
    select s.id, 0 as depth, array[s.id] as path from public.so s where s.id = any(v_ids)
    union all
    select c.id, d.depth + 1, d.path || c.id from d join public.so c on c.split_from_id = d.id where d.depth < 50 and not (c.id = any(d.path))
  )
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'status', s.status, 'split_reason', s.split_reason,
           'open_backorder_lines', (select count(*) from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null)) order by s.so_number), '[]'::jsonb)
    into v_sib
  from d join public.so s on s.id = d.id
  where d.depth > 0 and not (s.id = any(v_ids)) and s.status = 'confirmed'
    and exists (select 1 from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null);

  -- ── 원본이 확정 때 이어받은 남의 백오더 줄(⬜4 · 0-7: confirmed 이고 열린 예약이 없는 줄만 다시 연다 · 나머지는 닫힌 채 + 경고) ──
  select coalesce(jsonb_agg(jsonb_build_object('close_id', c.id, 'so_number', s.so_number, 'line_no', l.line_no, 'sku', l.sku, 'qty_open', c.qty_open, 'qty_taken', c.qty_taken, 'qty_unwanted', c.qty_unwanted,
           'taken_by', t.so_number, 'target_status', s.status,
           'reopenable', (s.status = 'confirmed' and not exists (select 1 from public.so_reserve rs where rs.so_line_id = l.id and rs.released_at is null))) order by s.so_number, l.line_no), '[]'::jsonb)
    into v_sup
  from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id join public.so s on s.id = l.so_id join public.so t on t.id = c.taken_by_so_id
  where c.taken_by_so_id = any(v_ids) and c.reopened_at is null and c.end_kind = 'superseded';

  -- ── 운임(판정 8: 옮기지 않는다 · 다시 계산한다) ──
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'line_no', c.line_no, 'name', c.name, 'amount', c.amount) order by s.so_number, c.line_no), '[]'::jsonb) into v_charges
  from public.so_charge c join public.so s on s.id = c.so_id where c.so_id = any(v_ids);

  -- ── 경고(막지 않는다) ──
  if jsonb_array_length(v_diffs) > 0 then v_warn := array_append(v_warn, 'head_differs'); end if;
  if jsonb_array_length(v_charges) > 0 then v_warn := array_append(v_warn, 'charges_not_merged'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'was_preorder')::boolean) then v_warn := array_append(v_warn, 'preorder_lines_need_reflag'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'deal_ended')::boolean) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if exists (select 1 from jsonb_array_elements(v_sup) x where not (x->>'reopenable')::boolean) then v_warn := array_append(v_warn, 'superseded_not_reopenable'); end if;
  if v_old.order_date <> v_today and v_lines_n > 0 then v_warn := array_append(v_warn, 'reprice_suggested'); end if;   -- §13 판정 3: 주문일이 바뀌면 줄은 그대로 + 표시 + 경고
  if jsonb_array_length(v_sib) > 0 then v_warn := array_append(v_warn, 'backorder_siblings_stay_open'); end if;      -- 판정 1 · 0-1 대가

  if not p_commit then
    return jsonb_build_object('committed', false, 'orders', to_jsonb(string_to_array(v_numbers, ', ')), 'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today,
                              'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'charges', v_charges,
                              'needs_manager', v_any_confirmed, 'warnings', to_jsonb(v_warn));
  end if;

  -- ── 실행 ① 새 오더(머리 통째 복사 · 위 주석의 칸 표) ──
  v_id := gen_random_uuid();
  v_note := 'Merged from ' || v_numbers;
  insert into public.so
  select * from jsonb_populate_record(null::public.so,
    to_jsonb(v_old) || jsonb_build_object(
      'id', v_id, 'so_number', public.so_next_number(), 'status', 'draft', 'order_date', v_today, 'ref', null,
      'comments', case when v_old.comments is null then v_note else v_old.comments || E'\n' || v_note end,
      'split_from_id', null, 'split_reason', null,
      'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
      'confirmed_at', null, 'confirmed_by', null, 'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null,
      'unconfirmed_at', null, 'unconfirmed_by', null, 'carrier', null, 'carrier_id', null, 'tracking_number', null,   -- ful-1c: carrier_id 도 비운다(합친 뒤 Ship & invoice 에서 고른다)
      'reprice_suggested_at', null, 'order_discount_locked_at', null,
      'created_at', now(), 'created_by', v_staff, 'updated_at', now(), 'updated_by', v_staff));
  select * into v_new from public.so where id = v_id;
  perform public.so_order_discount_apply(v_id, v_staff);                             -- 판정 7 · dsc-3a 판정 308 · 312: 새 머리는 잠기지 않는다 · manual 은 helper 가 그대로 · 줄이 들어오며 so_line 트리거가 금액 단계로 다시 고른다

  -- ── 실행 ② 줄(계획 그대로 · tax_rule = 합친 오더 규칙 · 짝 표) ──
  for e in select p from jsonb_array_elements(v_plan) p order by (p->>'line_no')::int loop
    insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                                list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, updated_by)
    values (v_id, (e->>'line_no')::int, (e->>'product_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
            (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, (e->>'unit_price')::numeric, (e->>'price_override')::boolean, e->>'discount_source', null, e->>'free_reason',
            (e->>'surcharge_pct')::numeric, (e->>'surcharge_amount')::numeric, e->>'surcharge_label', v_new.tax_rule, e->>'comments', v_staff)
    returning id into v_line_id;
    insert into public.so_line_merge_source (line_id, from_line_id, created_by)
    select v_line_id, (x->>'line_id')::uuid, v_staff from jsonb_array_elements(e->'sources') x;
    if (e->>'is_combo')::boolean then v_combos := v_combos || jsonb_build_object('line_id', v_line_id, 'first_line_id', e->'first_line_id', 'qty', e->'qty', 'sources', e->'sources'); end if;
  end loop;
  -- asm-2b2(묶음 2): 합친 콤보 줄마다 구성품을 다시 매단다 — 첫 원본 콤보 줄의 구성품(저장된 combo_qty · 정의를 다시 읽지 않는다) · 수량 = 합친 콤보 수 × combo_qty · 값 0 · 줄 번호는 끝에(so_line_add 와 같은 자리) · 짝 표에 원본 구성품 줄도
  for e in select p from jsonb_array_elements(v_combos) p loop
    insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, updated_by, combo_line_id, combo_qty)
    select v_id, (select coalesce(max(n.line_no), 0) from public.so_line n where n.so_id = v_id) + row_number() over (order by cp.line_no), cp.product_id, cp.sku, cp.product_name, cp.unit, cp.pack_factor, (e->>'qty')::numeric * cp.combo_qty,
           null, null, 0, false, null, null, null, null, null, null, v_new.tax_rule, null, v_staff, (e->>'line_id')::uuid, cp.combo_qty
    from public.so_line cp where cp.combo_line_id = (e->>'first_line_id')::uuid;
    get diagnostics v_cnt = row_count;  v_comp_n := v_comp_n + v_cnt;
    insert into public.so_line_merge_source (line_id, from_line_id, created_by)
    select n.id, sc.id, v_staff
    from public.so_line n join jsonb_array_elements(e->'sources') sx on true join public.so_line sc on sc.combo_line_id = (sx->>'line_id')::uuid and sc.product_id = n.product_id
    where n.so_id = v_id and n.combo_line_id = (e->>'line_id')::uuid;
  end loop;
  if v_old.order_date <> v_today and v_lines_n > 0 then
    update public.so set reprice_suggested_at = now(), updated_by = v_staff where id = v_id;
  end if;
  -- dsc-3b 판정 324: 원본들의 쿠폰 가운데 helper 로 골라 본 % 가 큰 쪽만 새 머리에(같으면 오래된 원본 것) · 나머지는 뗀 채 남는다(원본은 merged 라 가족 판정에 안 걸린다)
  for r in select s.coupon_id, s.so_number, s.created_at from public.so s where s.id = any(v_ids) and s.coupon_id is not null order by s.created_at, s.so_number loop
    update public.so set coupon_id = r.coupon_id where id = v_id;
    perform public.so_order_discount_apply(v_id, v_staff, true);
    select case when s.order_discount_source = 'coupon' then s.order_discount_pct else -1 end into v_cp_pct from public.so s where s.id = v_id;
    v_cps := v_cps || jsonb_build_object('so_number', r.so_number, 'code', (select c.code from public.so_coupon c where c.id = r.coupon_id),
                                         'pct', (select public.so_coupon_pct(c, s) from public.so_coupon c, public.so s where c.id = r.coupon_id and s.id = v_id), 'won_pct', nullif(v_cp_pct, -1));
    if v_cp_pct > v_best_pct then v_best_pct := v_cp_pct; v_best_cp := r.coupon_id; end if;
  end loop;
  if v_cps <> '[]'::jsonb then
    update public.so set coupon_id = case when v_best_pct > -1 then v_best_cp else null end where id = v_id;
    perform public.so_order_discount_apply(v_id, v_staff, true);
    select coalesce(jsonb_agg(c || jsonb_build_object('kept', (select s.coupon_id from public.so s where s.id = v_id) = (select x.id from public.so_coupon x where x.code = c->>'code'))), '[]'::jsonb) into v_cps from jsonb_array_elements(v_cps) c;
  end if;

  -- ── 실행 ③ 원본의 열린 백오더 줄 → 장부 merged + 예약 closed(0-4) · asm-2b2: 수요 줄 단위(콤보 줄은 구성품 예약을 콤보 수로 · 장부는 콤보 줄에 · 구성품 예약 함께 닫힘) ──
  for r in
    select x.id as so_line_id, q.qty_open, q.ids as reserve_ids
    from public.so_line x
    cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, array_agg(res.id) as ids
                        from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                        where (cp.id = x.id or cp.combo_line_id = x.id) and res.released_at is null and res.kind = 'backorder') q
    where x.so_id = any(v_ids) and x.combo_line_id is null and q.qty_open is not null
  loop
    perform public.so_backorder_record(r.so_line_id, 'merged', r.qty_open, 0, 0, null, null, v_staff, 'Merged into ' || v_new.so_number);
    update public.so_reserve set released_at = now(), released_by = v_staff, released_reason = 'closed', updated_by = v_staff where id = any(r.reserve_ids);
    v_bo := v_bo + 1;
  end loop;

  -- ── 실행 ④ 원본이 이어받은 남의 줄 다시 열기(⬜4 · confirmed 이고 열린 예약 없는 줄만 · so_backorder_reopen 과 같은 모양) ──
  for r in select (x->>'close_id')::uuid as close_id, (x->>'reopenable')::boolean as ok from jsonb_array_elements(v_sup) x loop
    if r.ok then
      update public.so_backorder_close set reopened_at = now(), reopened_by = v_staff, updated_by = v_staff where id = r.close_id and reopened_at is null;
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
      select c.so_line_id, c.qty_open, 'backorder', null from public.so_backorder_close c where c.id = r.close_id;
      v_reopened := v_reopened + 1;
    end if;
  end loop;

  -- ── 실행 ⑤ 원본의 남은 열린 예약(allocated · preorder · hold) 풀기 → released(트리거가 reason 을 넣는다 · ⬜5) ──
  update public.so_reserve res set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x where x.id = res.so_line_id and res.released_at is null and x.so_id = any(v_ids);
  get diagnostics v_released = row_count;

  -- ── 실행 ⑥ 원본 닫기(한 문장 · so_merge_reason_ck 양방향 · so_closed_at_ck) ──
  update public.so set status = 'cancelled', closed_reason = 'merged', merged_into_id = v_id, closed_at = now(), closed_note = 'Merged into ' || v_new.so_number, cancelled_by = v_staff, updated_by = v_staff
  where id = any(v_ids) and status in ('draft', 'confirmed');
  get diagnostics v_cnt = row_count;
  if v_cnt <> array_length(v_ids, 1) then
    raise exception 'Not every order could be merged — one may have been changed by someone else just now — nothing was saved';
  end if;

  -- ── 실행 ⑦ 선결제 대상 옮기기(원본 행은 기록으로 · 합친 오더 행 하나) ──
  insert into public.so_payment_order (payment_id, so_id, created_by)
  select distinct o.payment_id, v_id, v_staff
  from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active'
  where o.so_id = any(v_ids)
  on conflict on constraint so_payment_order_uq do nothing;
  get diagnostics v_moved = row_count;

  return jsonb_build_object('committed', true, 'so_id', v_id, 'so_number', v_new.so_number, 'status', 'draft', 'orders', to_jsonb(string_to_array(v_numbers, ', ')),
                            'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today, 'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint,
                            'payments_moved', v_moved, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'superseded_reopened', v_reopened,
                            'backorder_lines_recorded', v_bo, 'reserves_released', v_released, 'charges', v_charges, 'component_lines', v_comp_n, 'coupons', v_cps, 'warnings', to_jsonb(v_warn));   -- asm-2b2: 다시 매단 구성품 줄 수
end;
$$;

-- 설명은 덮지 않고 이어 붙인다(dsc-3a · dsc-3b 의 설명이 그대로 남게)
do $$ begin
  execute format('comment on function public.so_header_update(uuid, jsonb) is %L', coalesce(obj_description('public.so_header_update(uuid, jsonb)'::regprocedure, 'pg_proc'), '') || ' · ⭐ ful-1c 판정 436: 운송사 열쇠 carrier_id(표 행 id) 또는 carrier(표 이름과 정확히 같은 글자) · 켜진 행만 · null · 빈 글자 = 비움 · 둘이 함께 오면 같은 행이어야 · id 와 글자를 같이 쓴다(글자 = 표 이름)');
  execute format('comment on function public.so_merge(uuid[], boolean) is %L', coalesce(obj_description('public.so_merge(uuid[], boolean)'::regprocedure, 'pg_proc'), '') || ' · ⭐ ful-1c: 새 머리의 carrier_id 도 비운다(carrier · tracking_number 와 같이 — 합친 뒤 Ship & invoice 에서 고른다)');
end $$;
