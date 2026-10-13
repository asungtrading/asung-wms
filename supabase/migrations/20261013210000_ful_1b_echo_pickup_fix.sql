-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- ful-1b — Shopify ⑤ 오더 상태 · 메아리 거르기 · 픽업 오더 받기 · Picked up · 송장 고치기 (2026-10-13 · 판정 438 · 440 · 443 · 447 · 454 · ful-2a 20261013193000 위에)
--   ① 칸: shop_order.delivery_method(SHIPPING · PICK_UP · MIXED) · pickup_location_gid(ingest 가 raw 의 fulfillmentOrders 로) · shop_fulfillment.last_push_at(우리 마지막 Shopify 쓰기 — 메아리 ⓑ) · picked_up_by
--   ② shop_order_delivery(raw) — 배송 방식 가르기(판정 444 · 454 · 문서 「deliveryMethod 로만 가른다」)
--   ③ shop_order_ingest 재발행(마지막 정의 ord-1b2 20261011020000:41 바이트 복사 + 메아리 · 구체 경고 · delivery 칸 — 판정 447 · 440 · 이견 1)
--      메아리 = ⓐ 새로 보인 fulfillment GID 가 모두 shop_fulfillment 에 있다 · ⓑ updatedAt 이 last_push_at 뒤 2 분 안 → updated_after_so 없음 · 모르는 GID = fulfilled_in_shopify · 새 환불 = refunded_in_shopify(원문은 raw) · 구체 경고가 일반 경고를 대신
--   ④ shop_order_prepare 재발행(마지막 정의 ord-1a1 20261010233000:303 바이트 복사 + 픽업 브랜치 — 판정 454 · 이견 2 · 확인 필요 셋 pickup_locations_differ · pickup_location_unpaired · delivery_mixed)
--   ⑤ shop_order_process 재발행(마지막 정의 ord-1a2 20261011003000:405 바이트 복사 + 픽업 머리 — 배송지 비움(contact · phone) · 세금 주 차례 → tax_rule(manual) · 운송사 Pickup · 경고 pickup_tax_unknown · pickup_tax_from_location · pickup_carrier_missing)
--   ⑥ shop_order_warn 재발행(ful-2a) — 코드 둘 더함 pickup_failed · tracking_fix_failed
--   ⑦ shop_fulfill_requeue(so, kind) — 큐 행을 넣거나 다시 연다(unique(so_id, kind) · attempts 0) · 창구 둘이 쓴다
--   ⑧ 창구 shop_fulfill_picked_up(so) — 판정 443: 픽업 결과 행(ready_at 있고 picked_up_at 없음)에 picked_up_at · picked_up_by 를 바로 적고(찾아감은 직원이 본 사실) 큐 picked_up → EF 가 픽업 FO 에 fulfillmentCreate(notify false · 짐작 — Shopify 「Picked up」 전용 mutation 은 문서에 없다) → GID
--   ⑨ 창구 so_tracking_fix(so, carrier_id, tracking, commit) — 판정 438: 출고된 SO 의 운송사 · 송장만 · 종류가 바뀌는 고침 거절 · pickup · delivery 는 고칠 송장이 없다 · carrier 면 송장 필수 · so + 결과 표 머리마다 갱신 · GID 있는 머리가 있으면 큐 tracking_fix → EF fulfillmentTrackingInfoUpdate(notify false)
--   ⚠️ 무접촉: so_finalize · so_ship · so_header_update · cron(ims-fulfill-drain 49 가 kind 를 안 가린다) · 화면 · 439 · 441 · 449
--   적용: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f <이 파일> && supabase migration repair --status applied <버전> --db-url "$(cat ~/.asung-testdb-url)"  — ⚠️ EF shopify 배포보다 먼저
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


-- ═══ 1) 칸 ═══
alter table public.shop_order add column delivery_method text;
alter table public.shop_order add column pickup_location_gid text;
alter table public.shop_order add constraint shop_order_delivery_method_ck check (delivery_method is null or delivery_method in ('SHIPPING', 'PICK_UP', 'MIXED'));
comment on column public.shop_order.delivery_method is 'ful-1b 판정 444 · 454: raw 의 fulfillmentOrders.deliveryMethod 로 가른 것 — PICK_UP(전부 픽업) · MIXED(배송 + 픽업 · 확인 필요) · SHIPPING(그 밖 전부) · null(FO 를 못 봤다) · ingest 가 적는다(shop_order_delivery)';
comment on column public.shop_order.pickup_location_gid is 'ful-1b 판정 454: 픽업 FO 의 Shopify 위치 GID(픽업이 아니면 null) — 브랜치 = shop_location 짝 창고';
alter table public.shop_fulfillment add column last_push_at timestamptz;
alter table public.shop_fulfillment add column picked_up_by uuid references public.ims_staff (id) on delete no action;
create index shop_fulfillment_picked_up_by_idx on public.shop_fulfillment (picked_up_by);
comment on column public.shop_fulfillment.last_push_at is 'ful-1b 판정 447 ⓑ: EF 가 이 머리로 Shopify 에 마지막으로 쓴 시각(ship · Ready for pickup · Picked up · 송장 고침) — ingest 가 updatedAt 이 이 뒤 2 분 안이면 메아리로 본다';
comment on column public.shop_fulfillment.picked_up_by is 'ful-1b 판정 443: Picked up 을 누른 직원(picked_up_at 과 함께 창구 shop_fulfill_picked_up 이 적는다)';

-- ═══ 2) shop_order_delivery — 배송 방식 가르기(raw 의 fulfillmentOrders.nodes · 문서: deliveryMethod 로만 · shippingLines · 주소 유무로 짐작하지 않는다) ═══
--   method: FO 가 없으면 null · 전부 PICK_UP → PICK_UP · 섞이면 MIXED · 그 밖(SHIPPING · LOCAL · RETAIL · NONE …) → SHIPPING(= 픽업이 아니다) · 픽업 위치는 PICK_UP FO 의 것(여럿이면 locations > 1 · 첫 것만 돌려준다)
create function public.shop_order_delivery(p_raw jsonb) returns table (method text, location_gid text, location_name text, locations int)
  language sql immutable
  set search_path = public, pg_temp
as $$
  with fo as (select coalesce(n->'deliveryMethod'->>'methodType', '') as m, n->'assignedLocation'->'location'->>'id' as loc, n->'assignedLocation'->'location'->>'name' as loc_name
                from jsonb_array_elements(coalesce(p_raw->'fulfillmentOrders'->'nodes', '[]'::jsonb)) n)
  select case when count(*) = 0 then null when bool_and(m = 'PICK_UP') then 'PICK_UP' when bool_or(m = 'PICK_UP') then 'MIXED' else 'SHIPPING' end,
         (select loc from fo where m = 'PICK_UP' order by loc limit 1),
         (select loc_name from fo where m = 'PICK_UP' order by loc limit 1),
         (select count(distinct loc)::int from fo where m = 'PICK_UP')
    from fo;
$$;
revoke all on function public.shop_order_delivery(jsonb) from public, anon;
grant execute on function public.shop_order_delivery(jsonb) to authenticated;
comment on function public.shop_order_delivery(jsonb) is 'ful-1b 판정 444 · 454: 받은 오더 원문의 fulfillmentOrders 로 배송 방식을 가른다 — PICK_UP · MIXED · SHIPPING · null(FO 없음) + 픽업 위치 GID · 이름 · 서로 다른 픽업 위치 수 · 순수(immutable) · 화면도 부를 수 있다';

-- ═══ 3) shop_order_ingest 재발행 — ord-1b2 20261011020000:41 ~ 135 바이트 복사 · 더한 줄: 선언 2 · delivery 3 · 메아리 블록 · 경고 합치기 2 · 반환 1 ═══
create or replace function public.shop_order_ingest(p_store_id uuid, p_order jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_s       public.shop_store%rowtype;
  v_gid     text;
  v_o       public.shop_order%rowtype;
  v_action  text;
  v_ship    jsonb := p_order->'shippingAddress';
  v_fl      jsonb;
  v_li      jsonb;
  v_i       int := 0;
  v_n       int := 0;
  v_warn    jsonb;
  v_prep    jsonb := null;
  v_cancel  timestamptz := nullif(p_order->>'cancelledAt', '')::timestamptz;
  v_cres    jsonb := null;                                                                                                                   -- ord-1b2: 이번 받기의 shop_order_cancelled 결과
  v_auto    boolean := false;                                                                                                                -- ord-1b2: 자동 취소(auto_cancelled · closed_before_so)로 끝났나
  v_newcan  boolean := false;                                                                                                                -- ord-1b2: 이번 받기에서 처음 본 취소인가
  v_moved   boolean := false;                                                                                                                -- ord-1b2: Shopify updatedAt 이 바뀌었나
  v_dlv     record;                                                                                                                          -- ful-1b 판정 454: 배송 방식(shop_order_delivery)
  v_oldf    text[];  v_newf text[];  v_unk text[];  v_oldr text[];  v_push timestamptz;  v_echo boolean := false;  v_spec jsonb := '[]'::jsonb;  r jsonb;   -- ful-1b 판정 447: 메아리 · 구체 경고
begin
  select * into v_s from public.shop_store s where s.id = p_store_id;
  if v_s.id is null then raise exception 'shop_order_ingest: store % not found — nothing was saved', p_store_id; end if;
  if not v_s.is_active then raise exception 'shop_order_ingest: store % is off — nothing was saved', v_s.code; end if;
  if p_order is null or jsonb_typeof(p_order) <> 'object' then raise exception 'shop_order_ingest: p_order must be the GraphQL order object — nothing was saved'; end if;
  v_gid := p_order->>'id';
  if v_gid !~ '^gid://shopify/Order/[0-9]+$' then raise exception 'shop_order_ingest: order id % is not a Shopify Order GID — nothing was saved', coalesce(v_gid, '(none)'); end if;
  if nullif(p_order->>'name', '') is null then raise exception 'shop_order_ingest: order % has no name — nothing was saved', v_gid; end if;
  if coalesce(jsonb_typeof(p_order->'lineItems'->'nodes'), '') <> 'array' then raise exception 'shop_order_ingest: order % has no lineItems.nodes — nothing was saved', v_gid; end if;   -- coalesce: 칸이 없으면 jsonb_typeof 가 null 이라 if 가 조용히 지나간다(1회차 T8)
  v_fl := p_order->'shippingLines'->'nodes'->0;
  select * into v_dlv from public.shop_order_delivery(p_order);                                                                              -- ful-1b: SHIPPING · PICK_UP · MIXED · 픽업 위치

  select * into v_o from public.shop_order o where o.shopify_order_gid = v_gid for update;
  if v_o.id is null then
    insert into public.shop_order (store_id, shopify_order_gid, name, shopify_created_at, shopify_updated_at, shopify_cancelled_at, is_test, financial_status, source_name, email, shopify_customer_gid,
                                   ship_province_code, ship_country_code, currency_code, subtotal, total_discounts, total_shipping, total_tax, total, freight_amount, freight_title, raw, status, delivery_method, pickup_location_gid)
    values (v_s.id, v_gid, p_order->>'name', nullif(p_order->>'createdAt', '')::timestamptz, nullif(p_order->>'updatedAt', '')::timestamptz, v_cancel, coalesce((p_order->>'test')::boolean, false),
            p_order->>'displayFinancialStatus', p_order->>'sourceName', nullif(lower(trim(coalesce(p_order->>'email', p_order->'customer'->'defaultEmailAddress'->>'emailAddress'))), ''), nullif(p_order->'customer'->>'id', ''),
            nullif(upper(trim(v_ship->>'provinceCode')), ''), nullif(upper(trim(v_ship->>'countryCodeV2')), ''), p_order->>'currencyCode',
            (p_order->'subtotalPriceSet'->'shopMoney'->>'amount')::numeric, (p_order->'totalDiscountsSet'->'shopMoney'->>'amount')::numeric, (p_order->'totalShippingPriceSet'->'shopMoney'->>'amount')::numeric,
            (p_order->'totalTaxSet'->'shopMoney'->>'amount')::numeric, (p_order->'totalPriceSet'->'shopMoney'->>'amount')::numeric,
            (v_fl->'discountedPriceSet'->'shopMoney'->>'amount')::numeric, v_fl->>'title', p_order, 'received', v_dlv.method, v_dlv.location_gid)
    returning * into v_o;
    v_action := 'inserted';
  else
    if v_o.status in ('received', 'needs_review') then
      update public.shop_order set name = p_order->>'name', shopify_created_at = nullif(p_order->>'createdAt', '')::timestamptz, shopify_updated_at = nullif(p_order->>'updatedAt', '')::timestamptz, shopify_cancelled_at = v_cancel,
             is_test = coalesce((p_order->>'test')::boolean, false), financial_status = p_order->>'displayFinancialStatus', source_name = p_order->>'sourceName',
             email = nullif(lower(trim(coalesce(p_order->>'email', p_order->'customer'->'defaultEmailAddress'->>'emailAddress'))), ''), shopify_customer_gid = nullif(p_order->'customer'->>'id', ''),
             ship_province_code = nullif(upper(trim(v_ship->>'provinceCode')), ''), ship_country_code = nullif(upper(trim(v_ship->>'countryCodeV2')), ''), currency_code = p_order->>'currencyCode',
             subtotal = (p_order->'subtotalPriceSet'->'shopMoney'->>'amount')::numeric, total_discounts = (p_order->'totalDiscountsSet'->'shopMoney'->>'amount')::numeric, total_shipping = (p_order->'totalShippingPriceSet'->'shopMoney'->>'amount')::numeric,
             total_tax = (p_order->'totalTaxSet'->'shopMoney'->>'amount')::numeric, total = (p_order->'totalPriceSet'->'shopMoney'->>'amount')::numeric,
             freight_amount = (v_fl->'discountedPriceSet'->'shopMoney'->>'amount')::numeric, freight_title = v_fl->>'title', raw = p_order, status = 'received', reasons = '[]'::jsonb, error = null,
             delivery_method = v_dlv.method, pickup_location_gid = v_dlv.location_gid
       where id = v_o.id returning * into v_o;
      delete from public.shop_order_line where shop_order_id = v_o.id;                                                                          -- 줄은 다시 푼다(SO 가 없으니 자유)
      v_action := 'updated';
    else                                                                                                                                       -- created · cancelled · error: 원문만 갱신 · SO · 줄 무접촉(판정 372)
      v_warn := jsonb_build_object('code', case when v_o.status = 'created' then 'updated_after_so' else 'updated_after_' || v_o.status end, 'at', now(),
                                   'message', format('Shopify order %s changed after IMS %s it (Shopify updatedAt %s) — check the Shopify order and the IMS order by hand', p_order->>'name', v_o.status, p_order->>'updatedAt'));
      v_action := 'updated_after_' || v_o.status;                                                                                            -- ord-1b2: 받기 전 상태로(취소가 상태를 바꿔도 action 은 그대로)
      v_newcan := v_cancel is not null and v_o.shopify_cancelled_at is null;
      v_moved  := nullif(p_order->>'updatedAt', '')::timestamptz is distinct from v_o.shopify_updated_at;
      -- ful-1b 판정 447: 메아리 — ⓐ 새로 보인 fulfillment GID(이전 raw 에 없던 것)가 모두 우리 결과 표(shop_fulfillment)에 있다 · ⓑ updatedAt 이 우리 마지막 Shopify 쓰기(last_push_at) 뒤 2 분 안(앞 5 초 여유) → updated_after_so 를 안 붙인다
      --   모르는 GID → fulfilled_in_shopify · 새 환불 GID → refunded_in_shopify(원문은 raw 가 그대로 담는다 · 판정 440) · 구체 경고가 있으면 일반 경고(updated_after_so)는 안 붙인다 · 배포 뒤 첫 재읽기는 이전 raw 에 목록이 없어 전부 「새것」(우리 것은 걸러지고 모르는 것은 한 번만)
      select coalesce(array_agg(f->>'id'), '{}') into v_oldf from jsonb_array_elements(coalesce(v_o.raw->'fulfillments', '[]'::jsonb)) f;
      select coalesce(array_agg(f->>'id'), '{}') into v_newf from jsonb_array_elements(coalesce(p_order->'fulfillments', '[]'::jsonb)) f where not (f->>'id' = any(v_oldf));
      select coalesce(array_agg(g), '{}') into v_unk from unnest(v_newf) g where not exists (select 1 from public.shop_fulfillment sf where sf.shop_order_id = v_o.id and sf.shopify_fulfillment_gid = g);
      select coalesce(array_agg(f->>'id'), '{}') into v_oldr from jsonb_array_elements(coalesce(v_o.raw->'refunds', '[]'::jsonb)) f;
      select max(sf.last_push_at) into v_push from public.shop_fulfillment sf where sf.shop_order_id = v_o.id;
      v_echo := (coalesce(array_length(v_newf, 1), 0) > 0 and coalesce(array_length(v_unk, 1), 0) = 0)
             or (v_push is not null and nullif(p_order->>'updatedAt', '')::timestamptz between v_push - interval '5 seconds' and v_push + interval '2 minutes');
      if coalesce(array_length(v_unk, 1), 0) > 0 then
        v_spec := v_spec || jsonb_build_object('code', 'fulfilled_in_shopify', 'at', now(), 'gids', to_jsonb(v_unk),
                                               'message', format('Shopify order %s was fulfilled in Shopify, not by IMS (%s fulfillment(s): %s) — the IMS order was not touched; check it by hand', p_order->>'name', array_length(v_unk, 1), array_to_string(v_unk, ', ')));
      end if;
      for r in select f from jsonb_array_elements(coalesce(p_order->'refunds', '[]'::jsonb)) f where not (f->>'id' = any(v_oldr)) loop
        v_spec := v_spec || jsonb_build_object('code', 'refunded_in_shopify', 'at', now(), 'refund_gid', r->>'id', 'amount', (r->'totalRefundedSet'->'shopMoney'->>'amount')::numeric, 'note', nullif(trim(coalesce(r->>'note', '')), ''),
                                               'message', format('Shopify order %s was refunded in Shopify (%s %s · %s) — make the credit note in IMS by hand if stock came back (judge restocking there)', p_order->>'name', r->'totalRefundedSet'->'shopMoney'->>'amount', coalesce(r->'totalRefundedSet'->'shopMoney'->>'currencyCode', ''), coalesce(nullif(trim(coalesce(r->>'note', '')), ''), 'no note')));
      end loop;
      update public.shop_order set shopify_updated_at = nullif(p_order->>'updatedAt', '')::timestamptz, shopify_cancelled_at = v_cancel, financial_status = p_order->>'displayFinancialStatus', raw = p_order,
             delivery_method = v_dlv.method, pickup_location_gid = v_dlv.location_gid
       where id = v_o.id;                                                                                                                    -- ord-1b2: 원문 · 취소 시각 먼저(shop_order_cancelled 가 읽는다) · 경고는 취소 판정 뒤에
      if v_newcan and v_o.status in ('created', 'error') and not exists (select 1 from jsonb_array_elements(v_o.warnings) w where w->>'code' in ('auto_cancelled', 'cancel_needs_review', 'cancel_failed')) then
        v_cres := public.shop_order_cancelled(v_o.id);                                                                                       -- ord-1a2 판정 434: SO 가 있는 오더의 취소 — 한 번만 · ord-1b2: error(SO 없음)도 닫는다(closed_before_so)
      end if;
      v_auto := coalesce(v_cres->>'action', '') in ('auto_cancelled', 'closed_before_so');
      update public.shop_order set
             warnings = warnings || (case when v_moved and not v_auto and not v_echo and jsonb_array_length(v_spec) = 0 then jsonb_build_array(v_warn) else '[]'::jsonb end)   -- ord-1b2: 자동 취소로 끝난 받기는 「손으로 확인」 경고(updated_after_so · cancelled_in_shopify)를 남기지 않는다 · ful-1b: 메아리 · 구체 경고가 있으면 안 붙인다
                                 || (case when not v_auto then v_spec else '[]'::jsonb end)                                                 -- ful-1b 판정 447 · 440: fulfilled_in_shopify · refunded_in_shopify
                                 || (case when v_newcan and not v_auto
                                          then jsonb_build_array(jsonb_build_object('code', 'cancelled_in_shopify', 'at', now(), 'message', format('Shopify order %s was cancelled in Shopify (%s) but the IMS order was not cancelled automatically — check it by hand (see cancel_needs_review / cancel_failed)', p_order->>'name', v_cancel)))
                                          else '[]'::jsonb end)
       where id = v_o.id returning * into v_o;
    end if;
  end if;

  if v_action in ('inserted', 'updated') then
    for v_li in select x from jsonb_array_elements(p_order->'lineItems'->'nodes') as x loop
      v_i := v_i + 1;
      if coalesce((v_li->>'quantity')::numeric, 0) <= 0 then continue; end if;
      insert into public.shop_order_line (shop_order_id, line_gid, line_no, sku, name, quantity, list_price, discount_amount, unit_price)
      values (v_o.id, coalesce(nullif(v_li->>'id', ''), 'line-' || v_i), v_i, nullif(trim(coalesce(v_li->>'sku', v_li->'variant'->>'sku')), ''), v_li->>'name', (v_li->>'quantity')::numeric,
              (v_li->'originalUnitPriceSet'->'shopMoney'->>'amount')::numeric, (v_li->'totalDiscountSet'->'shopMoney'->>'amount')::numeric, (v_li->'discountedUnitPriceAfterAllDiscountsSet'->'shopMoney'->>'amount')::numeric);
      v_n := v_n + 1;
    end loop;
    v_prep := public.shop_order_prepare(v_o.id);
    if v_cancel is not null then perform public.shop_order_cancelled(v_o.id); end if;                                   -- ord-1a2 판정 434: SO 가 생기기 전에 취소됐으면 그냥 cancelled
    select * into v_o from public.shop_order o where o.id = v_o.id;
  end if;

  return jsonb_build_object('shop_order_id', v_o.id, 'action', v_action, 'status', v_o.status, 'name', v_o.name, 'lines', v_n,
                            'customer_id', v_o.customer_id, 'location_id', v_o.location_id, 'reasons', v_o.reasons, 'warnings', v_o.warnings, 'prepare', v_prep, 'cancel', v_cres,   -- ord-1b2: cancel = 이번 받기의 shop_order_cancelled 결과(없으면 null)
                            'echo', v_echo, 'new_fulfillments', to_jsonb(v_newf), 'unknown_fulfillments', to_jsonb(v_unk), 'delivery_method', v_dlv.method);                    -- ful-1b
end;
$$;
revoke all on function public.shop_order_ingest(uuid, jsonb) from public, anon, authenticated;
comment on function public.shop_order_ingest(uuid, jsonb) is 'ord-1a1 판정 363 · 372 · 431 ① · ord-1a2 434 · ord-1b2 · ful-1b 447 · 440 · 454: 받은 오더 넣기 한 곳(EF service_role · 웹훅 · 주기 확인) — GID 로 upsert · received | needs_review 면 원문 · 줄을 다시 풀고 prepare · created | cancelled | error 면 원문만 갱신하고 SO · 줄 무접촉 · 처음 본 취소면 shop_order_cancelled · ⭐ ful-1b 메아리: 새로 보인 fulfillment GID 가 모두 shop_fulfillment 에 있거나 updatedAt 이 last_push_at 뒤 2 분 안이면 updated_after_so 를 안 붙인다 · 모르는 GID = fulfilled_in_shopify · 새 환불 = refunded_in_shopify(원문은 raw) · delivery_method · pickup_location_gid 를 적는다 · 돌려주는 값에 echo · new_fulfillments · unknown_fulfillments · delivery_method';

-- ═══ 4) shop_order_prepare 재발행 — ord-1a1 20261010233000:303 ~ 429 바이트 복사 · 더한 줄: 선언 1 · 픽업 창고 4 · 새 손님 기본 창고 1 · ③ 브랜치 갈래 · 반환 1 ═══
create or replace function public.shop_order_prepare(p_shop_order_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_o        public.shop_order%rowtype;
  v_s        public.shop_store%rowtype;
  v_reasons  jsonb := '[]'::jsonb;
  v_cust     uuid;
  v_how      text;
  v_link     public.shop_customer%rowtype;
  v_n        int;
  v_cands    jsonb;
  v_name     text;
  v_ship     jsonb;
  v_bill     jsonb;
  v_tier     text;
  v_loc      uuid;
  v_payload  jsonb;
  v_res      jsonb;
  v_keys     text[];
  v_prev     jsonb;
  v_sys      uuid;
  l          record;
  v_bad      int := 0;
  v_dlv      record;  v_pick uuid;                                                                                                     -- ful-1b 판정 454: 배송 방식 · 픽업 위치의 짝 창고
begin
  select * into v_o from public.shop_order o where o.id = p_shop_order_id for update;
  if v_o.id is null then raise exception 'shop_order_prepare: shop order % not found — nothing was saved', p_shop_order_id; end if;
  if v_o.status not in ('received', 'needs_review') then
    return jsonb_build_object('shop_order_id', v_o.id, 'status', v_o.status, 'skipped', true, 'message', 'already ' || v_o.status);
  end if;
  select * into v_s from public.shop_store s where s.id = v_o.store_id;
  select s.id into v_sys from public.ims_staff s where s.is_system and s.is_active order by s.created_at limit 1;
  v_ship := v_o.raw->'shippingAddress';
  v_bill := v_o.raw->'billingAddress';
  select * into v_dlv from public.shop_order_delivery(v_o.raw);                                                                           -- ful-1b 판정 454: 픽업 오더면 브랜치 = 픽업 위치와 짝인 IMS 창고(배송지 주 430 대신)
  if v_dlv.method = 'PICK_UP' and v_dlv.locations = 1 then
    select sl.warehouse_id into v_pick from public.shop_location sl where sl.store_id = v_o.store_id and sl.is_active and sl.shopify_location_gid = v_dlv.location_gid;   -- 별칭 sl(변수 l 과 겹치지 않게)
  end if;
  v_cust := v_o.customer_id;                                                                                                             -- 직원이 골랐거나(resolve) 앞 prepare 가 정한 손님은 그대로

  -- ① 손님(판정 364) — 계정 잇기 → 이메일 하나 → 여럿(확인 필요) → 없음(새 손님)
  if v_cust is null and v_o.shopify_customer_gid is not null then
    select * into v_link from public.shop_customer x where x.store_id = v_o.store_id and x.shopify_customer_gid = v_o.shopify_customer_gid;
    if v_link.id is not null then v_cust := v_link.customer_id; v_how := 'account'; end if;
  end if;
  if v_cust is null and v_o.email is not null then
    select count(distinct cc.customer_id),
           coalesce(jsonb_agg(distinct jsonb_build_object('customer_id', c.id, 'name', c.name, 'city', (select a.city from public.customer_address a where a.customer_id = c.id and a.is_active order by (a.type = 'Shipping') desc, a.is_default_for_type desc, a.created_at limit 1))), '[]'::jsonb)
      into v_n, v_cands
      from public.customer_contact cc join public.customer c on c.id = cc.customer_id
     where cc.is_active and c.is_active and lower(trim(cc.email)) = v_o.email;
    if v_n = 1 then
      v_cust := (v_cands->0->>'customer_id')::uuid; v_how := 'email';
    elsif v_n > 1 then
      v_reasons := v_reasons || jsonb_build_object('code', 'email_multiple', 'email', v_o.email, 'count', v_n, 'candidates', v_cands,
                                                   'message', format('%s customers share the email %s — pick the customer (shop_order_resolve_customer)', v_n, v_o.email));
    end if;
  end if;
  if v_cust is null and jsonb_array_length(v_reasons) = 0 then                                                                           -- 없음 → 새 손님(판정 364 ④ · 스토어 티어 · customer_create 그대로 · 시스템 직원이 만든다)
    v_name := coalesce(nullif(trim(v_ship->>'company'), ''), nullif(trim(v_ship->>'name'), ''), nullif(trim(v_o.raw->'customer'->>'displayName'), ''),
                       nullif(trim(coalesce(v_o.raw->'customer'->>'firstName', '') || ' ' || coalesce(v_o.raw->'customer'->>'lastName', '')), ''), nullif(trim(v_bill->>'name'), ''), v_o.email);
    if v_name is null then
      v_reasons := v_reasons || jsonb_build_object('code', 'customer_unknown', 'message', 'The order has no customer account, no email and no name — pick or create the customer by hand');
    else
      select t.name into v_tier from public.ref_price_tier t where t.id = v_s.sale_tier_id;
      v_loc := coalesce(v_pick, public.shop_order_pick_location(v_o.store_id, v_o.ship_province_code, null));                                -- ful-1b: 새 손님의 기본 창고도 픽업 창고
      v_payload := jsonb_build_object('name', v_name, 'price_tier', v_tier, 'default_location_id', v_loc,
                                      'note', format('Created from Shopify order %s (store %s) by the Shopify system user', v_o.name, v_s.code),
                                      'addresses', (select coalesce(jsonb_agg(a), '[]'::jsonb) from (
                                         select jsonb_build_object('type', 'Shipping', 'is_default_for_type', true, 'label', nullif(trim(v_ship->>'name'), ''), 'line1', v_ship->>'address1', 'line2', v_ship->>'address2', 'city', v_ship->>'city',
                                                                   'state_province', coalesce(v_ship->>'provinceCode', v_ship->>'province'), 'postal_code', v_ship->>'zip', 'country', coalesce(v_ship->>'countryCodeV2', v_ship->>'country')) as a
                                          where nullif(trim(coalesce(v_ship->>'address1', '') || coalesce(v_ship->>'city', '') || coalesce(v_ship->>'zip', '')), '') is not null
                                         union all
                                         select jsonb_build_object('type', 'Billing', 'is_default_for_type', true, 'label', nullif(trim(v_bill->>'name'), ''), 'line1', v_bill->>'address1', 'line2', v_bill->>'address2', 'city', v_bill->>'city',
                                                                   'state_province', coalesce(v_bill->>'provinceCode', v_bill->>'province'), 'postal_code', v_bill->>'zip', 'country', coalesce(v_bill->>'countryCodeV2', v_bill->>'country'))
                                          where nullif(trim(coalesce(v_bill->>'address1', '') || coalesce(v_bill->>'city', '') || coalesce(v_bill->>'zip', '')), '') is not null) z),
                                      'contacts', (select coalesce(jsonb_agg(c), '[]'::jsonb) from (
                                         select jsonb_build_object('name', coalesce(nullif(trim(coalesce(v_o.raw->'customer'->>'firstName', '') || ' ' || coalesce(v_o.raw->'customer'->>'lastName', '')), ''), nullif(trim(v_ship->>'name'), '')),
                                                                   'email', v_o.email, 'phone', coalesce(nullif(trim(v_o.raw->>'phone'), ''), nullif(trim(v_ship->>'phone'), '')), 'is_default', true, 'include_in_email', true) as c
                                          where v_o.email is not null or nullif(trim(coalesce(v_o.raw->'customer'->>'firstName', '') || coalesce(v_o.raw->'customer'->>'lastName', '') || coalesce(v_o.raw->>'phone', '')), '') is not null) z));
      v_prev := public.shop_system_enter();
      v_res := public.customer_create(v_payload, false, '{}');                                                                       -- 검사만 → 경고 열쇠를 모아 → 저장(두 번 부르기 그대로)
      if jsonb_array_length(v_res->'blocks') = 0 then
        select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_res->'warnings') as w;
        v_res := public.customer_create(v_payload, true, v_keys);
      end if;
      perform public.shop_system_leave(v_prev);
      if (v_res->>'committed')::boolean then
        v_cust := (v_res->>'customer_id')::uuid; v_how := 'created';
      else
        v_reasons := v_reasons || jsonb_build_object('code', 'customer_create_blocked', 'blocks', v_res->'blocks', 'message', 'IMS could not create the customer — ' || coalesce((v_res->'blocks'->0->>'message'), 'see blocks'));
      end if;
    end if;
  end if;
  if v_cust is not null then
    if not exists (select 1 from public.customer c where c.id = v_cust and c.is_active) then
      v_reasons := v_reasons || jsonb_build_object('code', 'customer_inactive', 'customer_id', v_cust, 'message', 'The linked IMS customer is inactive — reactivate it or pick another customer');
    elsif v_how is not null and v_o.shopify_customer_gid is not null and v_how <> 'account' then                                          -- 잇기(스토어 × GID) — 계정이 있을 때만
      insert into public.shop_customer (store_id, shopify_customer_gid, customer_id, linked_how, linked_by, updated_by)
      values (v_o.store_id, v_o.shopify_customer_gid, v_cust, v_how, v_sys, v_sys)
      on conflict (store_id, shopify_customer_gid) do nothing;
    end if;
  end if;

  -- ② 줄 대조(판정 366) — SKU 글자 그대로 · 못 찾음 · 꺼짐 · 판매 안 함 → 확인 필요
  for l in select x.id, x.sku, x.line_no, p.id as pid, p.is_active, p.sellable from public.shop_order_line x left join public.product p on p.sku = x.sku where x.shop_order_id = v_o.id order by x.line_no loop
    update public.shop_order_line set product_id = l.pid,
           match = case when l.pid is null then 'not_found' when not l.is_active then 'inactive' when not l.sellable then 'not_sellable' else 'ok' end
     where id = l.id;
    if l.pid is null then v_bad := v_bad + 1; v_reasons := v_reasons || jsonb_build_object('code', 'sku_not_found', 'line_no', l.line_no, 'sku', l.sku, 'message', format('Line %s: SKU %s is not in IMS', l.line_no, coalesce(l.sku, '(none)')));
    elsif not l.is_active then v_bad := v_bad + 1; v_reasons := v_reasons || jsonb_build_object('code', 'product_inactive', 'line_no', l.line_no, 'sku', l.sku, 'message', format('Line %s: product %s is inactive in IMS', l.line_no, l.sku));
    elsif not l.sellable then v_bad := v_bad + 1; v_reasons := v_reasons || jsonb_build_object('code', 'product_not_sellable', 'line_no', l.line_no, 'sku', l.sku, 'message', format('Line %s: product %s is not for sale in IMS', l.line_no, l.sku));
    end if;
  end loop;
  if not exists (select 1 from public.shop_order_line x where x.shop_order_id = v_o.id) then
    v_reasons := v_reasons || jsonb_build_object('code', 'no_lines', 'message', 'The order has no lines with a positive quantity');
  end if;

  -- ③ 브랜치(판정 430 · 427 · ful-1b 454: 픽업 오더는 픽업 위치의 짝 창고 · 위치 둘 · 짝 없음 · 섞임(SHIPPING + PICK_UP)은 확인 필요)
  if v_dlv.method = 'PICK_UP' then
    v_loc := v_pick;
    if v_dlv.locations > 1 then
      v_reasons := v_reasons || jsonb_build_object('code', 'pickup_locations_differ', 'count', v_dlv.locations, 'message', format('Pickup order with %s pickup locations — IMS takes one warehouse per order; split or fix the order in Shopify', v_dlv.locations));
    elsif v_loc is null then
      v_reasons := v_reasons || jsonb_build_object('code', 'pickup_location_unpaired', 'location_gid', v_dlv.location_gid, 'message', format('Pickup location %s is not paired with an IMS warehouse — pair it in Settings → Shopify Stores', coalesce(v_dlv.location_name, v_dlv.location_gid, '(none)')));
    end if;
  else
    v_loc := public.shop_order_pick_location(v_o.store_id, v_o.ship_province_code, v_cust);
    if v_loc is null then
      v_reasons := v_reasons || jsonb_build_object('code', 'warehouse_unknown', 'message', format('Store %s has no active location pair — pair a warehouse in Settings → Shopify Stores', v_s.code));
    end if;
    if v_dlv.method = 'MIXED' then
      v_reasons := v_reasons || jsonb_build_object('code', 'delivery_mixed', 'message', 'The order has both shipping and pickup fulfillment orders — IMS takes one delivery method per order; split it in Shopify');
    end if;
  end if;

  update public.shop_order set customer_id = v_cust, location_id = v_loc, reasons = v_reasons,
         status = case when jsonb_array_length(v_reasons) = 0 then 'received' else 'needs_review' end
   where id = v_o.id returning * into v_o;
  return jsonb_build_object('shop_order_id', v_o.id, 'status', v_o.status, 'customer_id', v_cust, 'linked_how', v_how, 'location_id', v_loc, 'bad_lines', v_bad, 'reasons', v_reasons, 'delivery_method', v_dlv.method);   -- ful-1b
end;
$$;
revoke all on function public.shop_order_prepare(uuid) from public, anon, authenticated;
comment on function public.shop_order_prepare(uuid) is 'ord-1a1 판정 364 · 366 · 430 · 431 · ful-1b 454: 받은 오더를 SO 로 만들 수 있게 준비 — 손님(계정 잇기 → 이메일 하나 → 여럿 needs_review → 없음 새 손님) · 줄 SKU 대조 · 창고(픽업 오더 = 픽업 위치의 짝 창고 · 그 밖 shop_order_pick_location) → received | needs_review(reasons + ful-1b pickup_locations_differ · pickup_location_unpaired · delivery_mixed) · 몇 번 불러도 같은 결과 · created 뒤에는 건너뜀';

-- ═══ 5) shop_order_process 재발행 — ord-1a2 20261011003000:405 ~ 539 바이트 복사 · 더한 줄: 선언 1 · 픽업 판정 2 · ③ 머리 갈래(픽업 = 세금 주 차례 · 배송지 비움 · tax_rule manual · 운송사 Pickup · 경고 셋) · 반환 1 ═══
create or replace function public.shop_order_process(p_shop_order_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_o       public.shop_order%rowtype;
  v_s       public.shop_store%rowtype;
  c         public.customer%rowtype;
  v_prev    jsonb;
  v_so      jsonb;
  v_so_id   uuid;
  v_so_row  public.so%rowtype;
  v_ship    jsonb;
  v_warn    jsonb := '[]'::jsonb;
  v_res     jsonb;
  l         record;
  q         record;
  v_line    public.so_line%rowtype;
  v_pct     numeric;
  v_ims_pct numeric;
  v_fl      jsonb;
  v_orig    numeric;
  v_disc    numeric;
  v_ims_tax numeric;
  v_paid    numeric;
  v_conf    jsonb := null;
  v_blocked text := null;
  v_po      text;
  v_note    text;
  v_n_lines int := 0;
  v_pickup  boolean := false;  v_dlv record;  v_car public.ref_carrier%rowtype;  v_rule text;  v_src text;  v_tax jsonb;  v_a record;   -- ful-1b 판정 454: 픽업 오더(v_a — 원문 select 의 별칭 a 를 가리지 않게)
begin
  select * into v_o from public.shop_order o where o.id = p_shop_order_id for update;
  if v_o.id is null then raise exception 'shop_order_process: shop order % not found — nothing was saved', p_shop_order_id; end if;
  if v_o.status <> 'received' then
    return jsonb_build_object('shop_order_id', v_o.id, 'status', v_o.status, 'skipped', true, 'message', 'not received (' || v_o.status || ')');
  end if;
  if v_o.shopify_cancelled_at is not null then                                                                               -- 판정 434: SO 가 생기기 전에 취소됐다
    return public.shop_order_cancelled(v_o.id);
  end if;
  if v_o.customer_id is null or v_o.location_id is null or jsonb_array_length(v_o.reasons) > 0 then
    update public.shop_order set status = 'needs_review' where id = v_o.id;
    return jsonb_build_object('shop_order_id', v_o.id, 'status', 'needs_review', 'skipped', true, 'message', 'prepare left reasons or no customer / warehouse');
  end if;
  select * into v_s from public.shop_store s where s.id = v_o.store_id;
  select * into c from public.customer x where x.id = v_o.customer_id;
  v_ship := v_o.raw->'shippingAddress';
  v_po   := coalesce(nullif(trim(v_o.raw->>'poNumber'), ''), (select nullif(trim(a->>'value'), '') from jsonb_array_elements(coalesce(v_o.raw->'customAttributes', '[]'::jsonb)) a where lower(a->>'key') in ('purchase_order(po)', 'purchase_order', 'po') limit 1));
  v_note := coalesce(nullif(trim(v_o.raw->>'note'), ''), (select nullif(trim(a->>'value'), '') from jsonb_array_elements(coalesce(v_o.raw->'customAttributes', '[]'::jsonb)) a where lower(a->>'key') in ('order note', 'order_note', 'note') limit 1));
  select * into v_dlv from public.shop_order_delivery(v_o.raw);
  v_pickup := coalesce(v_o.delivery_method, v_dlv.method) = 'PICK_UP';                                                                   -- ful-1b 판정 454(칸은 ingest 가 · 없으면 raw 로)

  begin                                                                                                                      -- 실패하면 여기까지 되감긴다(SO 없음 · claims 도 되감김) → status error
    v_prev := public.shop_system_enter();
    -- ① 머리(so_create 그대로 · intake shopify · 손님 값 복사 · 오더 할인은 손님 딜로 찾힌다 → 아래서 0 으로)
    v_so := public.so_create(c.id, 'warehouse', 'shopify', v_o.location_id, null);
    v_so_id := (v_so->>'id')::uuid;
    -- ② 줄 — 단가 = Shopify 할인 뒤(판정 367 · 431 ③) · 같은 SKU 가 둘이어도 새 줄(p_force_new) · 0 원 줄은 promotion
    for l in select x.* from public.shop_order_line x where x.shop_order_id = v_o.id and x.match = 'ok' order by x.line_no loop
      v_res := public.so_line_add(v_so_id, l.product_id, l.quantity, coalesce(l.unit_price, 0), null, case when coalesce(l.unit_price, 0) = 0 then 'promotion' end, null, true);
      if v_res->>'action' <> 'added' then raise exception 'shop_order_process: line % (%) was not added (%) — nothing was saved', l.line_no, l.sku, v_res->>'action'; end if;
      v_pct := case when coalesce(l.list_price, 0) > 0 then round((l.list_price - coalesce(l.unit_price, 0)) / l.list_price * 100, 2) else 0 end;
      v_line := public.so_line_set_shopify((v_res->'line'->>'id')::uuid, l.list_price, greatest(0, least(100, v_pct)));
      update public.shop_order_line set so_line_id = v_line.id where id = l.id;
      v_n_lines := v_n_lines + 1;
      -- 할인 어긋남(판정 431 ③) — IMS 규칙(so_line_quote: 손님 기본 · 딜 · 세트)으로 셈한 % 와 대조 · 0.1 % 안은 같은 것(돈 반올림) · IMS 값으로 바꾸지 않는다
      select * into v_so_row from public.so where id = v_so_id;
      select * into q from public.so_line_quote(v_so_row, l.product_id, l.quantity);
      v_ims_pct := coalesce(q.discount_pct, 0);
      if abs(v_pct - v_ims_pct) > 0.1 then
        v_warn := v_warn || jsonb_build_object('code', 'discount_mismatch', 'line_no', l.line_no, 'sku', l.sku, 'shopify_pct', v_pct, 'ims_pct', v_ims_pct, 'ims_source', q.discount_source,
                                               'message', format('Line %s %s: Shopify discount %s%% but IMS rules give %s%% (%s) — the Shopify price was kept', l.line_no, l.sku, v_pct, v_ims_pct, coalesce(q.discount_source, 'none')));
      end if;
      if q.list_price is not null and l.list_price is not null and abs(q.list_price - l.list_price) > 0.005 then
        v_warn := v_warn || jsonb_build_object('code', 'list_price_mismatch', 'line_no', l.line_no, 'sku', l.sku, 'shopify_list', l.list_price, 'ims_list', q.list_price,
                                               'message', format('Line %s %s: Shopify list price %s but IMS tier price %s — the Shopify price was kept', l.line_no, l.sku, l.list_price, q.list_price));
      end if;
    end loop;
    if v_n_lines = 0 then raise exception 'shop_order_process: no matched lines — nothing was saved'; end if;
    -- ③ 머리 — ref · 메모(PO · Order Note) · 배송지 = Shopify 배송지(so_header_update 가 세금 규칙을 배송지로 다시 고른다 · 368) · ful-1b: 픽업 오더는 따로(454)
    if v_pickup then
      -- ful-1b 판정 454: 픽업 오더 — 배송지 주소는 비운다(contact · phone 만 · 누가 찾아가는지) · 세금 주 = 손님 주소 차례(오더 배송지 → 청구지 → Shopify 손님 기본 주소 → IMS 손님 주소(Billing 먼저) → 픽업 창고의 주) 중 규칙이 있는 첫 것
      --   → so_header_update 의 tax_rule 열쇠(so_tax_set_manual · manual = true — Caleb 이 SO-25086 에서 손으로 한 모양) · 운송사 = 표의 Pickup 미리 채움(판정 379 · 452 의 PICK_UP 검사를 지난다) · 깨끗하면 ⑧ 이 자동 확정
      for v_a in
        select 1 as ord, 'order shipping address' as src, v_ship->>'countryCodeV2' as country, v_ship->>'provinceCode' as state
        union all select 2, 'order billing address', v_o.raw->'billingAddress'->>'countryCodeV2', v_o.raw->'billingAddress'->>'provinceCode'
        union all select 3, 'Shopify customer default address', v_o.raw->'customer'->'defaultAddress'->>'countryCodeV2', v_o.raw->'customer'->'defaultAddress'->>'provinceCode'
        union all select 10 + (row_number() over (order by (ca.type = 'Billing') desc, ca.is_default_for_type desc, ca.created_at))::int, 'IMS customer ' || coalesce(ca.type, '') || ' address', ca.country, ca.state_province
                    from public.customer_address ca where ca.customer_id = c.id and ca.is_active
        union all select 99, 'pickup warehouse ' || w.name, w.country, w.state_province from public.ref_warehouse w where w.id = v_o.location_id
        order by 1
      loop
        if nullif(trim(coalesce(v_a.state, '')), '') is null then continue; end if;
        v_tax := public.so_tax_rule_for(v_a.country, v_a.state, null, 'sale');
        if v_tax->>'rule' is not null then v_rule := v_tax->>'rule'; v_src := v_a.src; exit; end if;
      end loop;
      perform public.so_header_update(v_so_id, jsonb_build_object(
        'ref', v_o.name,
        'comments', nullif(concat_ws(' · ', 'PICKUP' || coalesce(' ' || v_dlv.location_name, ''), case when v_po is not null then 'PO ' || v_po end, v_note, 'Shopify ' || v_s.code || ' ' || v_o.name), ''),
        'ship_to_company', null::text, 'ship_to_contact', coalesce(nullif(trim(v_ship->>'name'), ''), nullif(trim(v_o.raw->'customer'->>'displayName'), '')), 'ship_to_phone', coalesce(nullif(trim(v_o.raw->>'phone'), ''), nullif(trim(v_ship->>'phone'), '')),
        'ship_to_line1', null::text, 'ship_to_line2', null::text, 'ship_to_city', null::text, 'ship_to_state_province', null::text, 'ship_to_postal_code', null::text, 'ship_to_country', null::text)
        || case when v_rule is not null then jsonb_build_object('tax_rule', v_rule) else '{}'::jsonb end);
      if v_rule is null then
        v_warn := v_warn || jsonb_build_object('code', 'pickup_tax_unknown', 'message', 'Pickup order: no tax rule found from the customer address or the pickup warehouse — pick a tax rule on the order');
      elsif v_src like 'pickup warehouse%' then
        v_warn := v_warn || jsonb_build_object('code', 'pickup_tax_from_location', 'rule', v_rule, 'source', v_src, 'message', format('Pickup order: no customer address with a tax rule — tax rule %s taken from the %s', v_rule, v_src));
      end if;
      select * into v_car from public.ref_carrier rc where rc.kind = 'pickup' and rc.is_active order by rc.name limit 1;
      if v_car.id is null then
        v_warn := v_warn || jsonb_build_object('code', 'pickup_carrier_missing', 'message', 'Pickup order: no active Pickup carrier on the carrier list — pick the carrier before Ship & invoice');
      else
        update public.so set carrier_id = v_car.id, carrier = v_car.name where id = v_so_id;                                           -- so_header_update 엔 carrier_id 열쇠가 없다(ful-1a 는 so_finalize 만 고쳤다) · definer 안 · draft · 같은 칸을 쓰는 창구는 so_copy_customer(손님 기본) · so_finalize(①에서 푼 값)
      end if;
    else
      perform public.so_header_update(v_so_id, jsonb_build_object(                                                                -- null 도 보낸다 — SO 배송지 = Shopify 배송지 그대로(손님 기본 주소가 남지 않게)
        'ref', v_o.name,
        'comments', nullif(concat_ws(' · ', case when v_po is not null then 'PO ' || v_po end, v_note, 'Shopify ' || v_s.code || ' ' || v_o.name), ''),
        'ship_to_company', nullif(trim(v_ship->>'company'), ''), 'ship_to_contact', nullif(trim(v_ship->>'name'), ''), 'ship_to_phone', coalesce(nullif(trim(v_ship->>'phone'), ''), nullif(trim(v_o.raw->>'phone'), '')),
        'ship_to_line1', nullif(trim(v_ship->>'address1'), ''), 'ship_to_line2', nullif(trim(v_ship->>'address2'), ''), 'ship_to_city', nullif(trim(v_ship->>'city'), ''),
        'ship_to_state_province', coalesce(nullif(trim(v_ship->>'provinceCode'), ''), nullif(trim(v_ship->>'province'), '')), 'ship_to_postal_code', nullif(trim(v_ship->>'zip'), ''),
        'ship_to_country', coalesce(nullif(trim(v_ship->>'countryCodeV2'), ''), nullif(trim(v_ship->>'country'), ''))));
    end if;
    -- ④ 오더 전체 할인 — 손님이 본 금액 그대로(431 ③): 손님 딜로 찾힌 오더 할인은 0(manual) 으로 · 경고
    select * into v_so_row from public.so where id = v_so_id;
    if coalesce(v_so_row.order_discount_pct, 0) > 0 then
      v_warn := v_warn || jsonb_build_object('code', 'order_discount_dropped', 'ims_pct', v_so_row.order_discount_pct, 'source', v_so_row.order_discount_source,
                                             'message', format('IMS would give an order discount of %s%% (%s) — not applied, the Shopify amounts were kept', v_so_row.order_discount_pct, v_so_row.order_discount_source));
      perform public.so_header_update(v_so_id, '{"order_discount_pct": 0}'::jsonb);
    end if;
    -- ⑤ 운임 — aone 만(판정 369: 손님이 낸 배송비 = 확정 운임 · 무료 배송 = 운임 + 100 %) · asung 은 담기만(열어 둠)
    v_fl := v_o.raw->'shippingLines'->'nodes'->0;
    v_orig := (v_fl->'originalPriceSet'->'shopMoney'->>'amount')::numeric;
    v_disc := (v_fl->'discountedPriceSet'->'shopMoney'->>'amount')::numeric;
    if v_s.kind = 'aone' and coalesce(v_orig, 0) > 0 then
      perform public.so_charge_set(v_so_id, coalesce(nullif(trim(v_fl->>'title'), ''), 'Freight'), v_orig, null, 'Shopify ' || v_o.name, null, null,
                                   case when coalesce(v_disc, v_orig) = 0 then 100 end,
                                   case when coalesce(v_disc, v_orig) > 0 and v_disc < v_orig then round(v_orig - v_disc, 2) end);
    elsif v_s.kind <> 'aone' and coalesce(v_orig, 0) > 0 then
      v_warn := v_warn || jsonb_build_object('code', 'freight_not_applied', 'amount', v_orig, 'title', v_fl->>'title', 'message', format('Shopify charged freight %s (%s) — not put on the IMS order (asung.ca web freight is still an open question)', v_orig, v_fl->>'title'));
    end if;
    -- ⑥ 세금(판정 368) — IMS 가 셈한 세금 ↔ Shopify totalTax
    select t.tax into v_ims_tax from public.so_totals_many(array[v_so_id]) t;
    if v_o.total_tax is not null and abs(coalesce(v_ims_tax, 0) - v_o.total_tax) > 0.005 then
      v_warn := v_warn || jsonb_build_object('code', 'tax_mismatch', 'ims', round(coalesce(v_ims_tax, 0), 2), 'shopify', v_o.total_tax,
                                             'message', format('IMS tax %s but Shopify charged %s — check the tax rule and the ship-to province', round(coalesce(v_ims_tax, 0), 2), v_o.total_tax));
    end if;
    -- ⑦ 결제(판정 370) — aone 카드 · Shopify 가 받음 → 오더에 묶인 선결제 · asung NetTerm(pending) 은 없음
    if v_s.kind = 'aone' and upper(coalesce(v_o.financial_status, '')) = 'PAID' and coalesce(v_o.total, 0) > 0 then
      v_paid := round(v_o.total, 2);
      v_res := public.so_payment_add(jsonb_build_object('customer_id', c.id, 'amount', v_paid, 'method', 'shopify', 'reference', v_o.name, 'warehouse_id', v_o.location_id,
                                                        'note', 'Shopify ' || v_s.code || ' ' || v_o.name || ' (paid online)', 'target_so_ids', jsonb_build_array(v_so_id)));
    end if;
    -- ⑧ 확정(판정 371) — 막히면 draft 로 두고 까닭을 경고에
    begin
      v_conf := public.so_confirm(v_so_id);
    exception when others then
      v_blocked := sqlerrm;
    end;
    if v_blocked is not null then
      v_warn := v_warn || jsonb_build_object('code', 'confirm_blocked', 'message', v_blocked);
    end if;
    perform public.shop_system_leave(v_prev);
  exception when others then
    update public.shop_order set status = 'error', error = left(sqlerrm, 1000), processed_at = now() where id = v_o.id;
    return jsonb_build_object('shop_order_id', v_o.id, 'status', 'error', 'error', left(sqlerrm, 1000));
  end;

  update public.shop_order set status = 'created', so_id = v_so_id, processed_at = now(), so_baseline_at = now(), error = null, warnings = warnings || v_warn where id = v_o.id;
  select * into v_so_row from public.so where id = v_so_id;
  return jsonb_build_object('shop_order_id', v_o.id, 'status', 'created', 'so_id', v_so_id, 'so_number', v_so_row.so_number, 'so_status', v_so_row.status, 'lines', v_n_lines,
                            'confirmed', v_blocked is null, 'confirm', v_conf, 'payment', v_paid, 'warnings', v_warn, 'pickup', v_pickup, 'tax_rule', v_rule, 'tax_source', v_src);   -- ful-1b
end;
$$;
revoke all on function public.shop_order_process(uuid) from public, anon, authenticated;
comment on function public.shop_order_process(uuid) is 'ord-1a2 판정 367 ~ 371 · 431 ③ · 432 · ful-1b 454: 받은 오더(received)를 IMS 오더로 — 시스템 직원이 되어 so_create(intake shopify) → 줄 → so_header_update(ref · 메모 · 배송지 → 세금 규칙) → 할인 0 → aone 운임 · 결제 → so_confirm(막히면 draft + confirm_blocked) → created · ⭐ ful-1b 픽업 오더(delivery_method PICK_UP): 배송지 주소는 비우고 contact · phone 만 · 세금 주 = 오더 배송지 → 청구지 → Shopify 손님 기본 주소 → IMS 손님 주소 → 픽업 창고의 주(규칙이 있는 첫 것) → tax_rule(manual) · 운송사 Pickup 미리 채움 · 경고 pickup_tax_unknown · pickup_tax_from_location · pickup_carrier_missing · 돌려주는 값에 pickup · tax_rule · tax_source';

-- ═══ 6) shop_order_warn 재발행(ful-2a) — 코드 둘 더함 ═══
create or replace function public.shop_order_warn(p_shop_order_id uuid, p_code text, p_message text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_w jsonb;
begin
  if p_code not in ('fulfill_failed', 'fulfill_cut', 'fulfill_location_mismatch', 'fulfill_nothing_left', 'pickup_failed', 'tracking_fix_failed') then
    raise exception 'shop_order_warn: code % is not one of fulfill_failed, fulfill_cut, fulfill_location_mismatch, fulfill_nothing_left, pickup_failed, tracking_fix_failed — nothing was saved', p_code;
  end if;
  update public.shop_order set warnings = warnings || jsonb_build_array(jsonb_build_object('code', p_code, 'message', nullif(btrim(coalesce(p_message, '')), ''), 'at', now()))
   where id = p_shop_order_id
  returning warnings into v_w;
  if not found then raise exception 'shop_order_warn: shop_order % not found — nothing was saved', p_shop_order_id; end if;
  return jsonb_build_object('shop_order_id', p_shop_order_id, 'code', p_code, 'warnings', jsonb_array_length(v_w));
end;
$$;
comment on function public.shop_order_warn(uuid, text, text) is 'ful-2a · ful-1b: EF fulfill_drain 이 shop_order.warnings 에 경고 한 줄 {code, message, at} 을 더한다 — 한 문장(warnings || …)이라 ingest 의 경고와 겹쳐도 안 지워진다 · 코드 여섯(fulfill_failed · fulfill_cut · fulfill_location_mismatch · fulfill_nothing_left · pickup_failed · tracking_fix_failed) · service_role 만';

-- ═══ 7) shop_fulfill_requeue — 큐 행을 넣거나 다시 연다(unique(so_id, kind) · ful-1a 이견 7 「반복되는 일은 같은 행을 다시 연다」) ═══
--   ⚠️ 돌고 있는 행(started_at 있고 done_at 없음 · drain 한 회차 ≤ 40 s)을 다시 열면 그 회차의 끝 PATCH 가 done 으로 덮을 수 있다 — 드물고(1 분 창) 다시 고치면 된다
create function public.shop_fulfill_requeue(p_so_id uuid, p_kind text) returns bigint
  language sql volatile security invoker
  set search_path = public, pg_temp
as $$
  insert into public.shop_fulfill_queue (so_id, kind) values (p_so_id, p_kind)
  on conflict (so_id, kind) do update set queued_at = now(), started_at = null, done_at = null, result = null, error = null, attempts = 0
  returning id;
$$;
revoke all on function public.shop_fulfill_requeue(uuid, text) from public, anon, authenticated;
comment on function public.shop_fulfill_requeue(uuid, text) is 'ful-1b: 발송 큐에 (so, kind) 행을 넣거나 있으면 다시 연다(attempts 0 · 결과 지움) — 창구 shop_fulfill_picked_up · so_tracking_fix 가 definer 안에서 부른다 · 직접 호출 불가';

-- ═══ 8) 창구 shop_fulfill_picked_up — 판정 443 · 379 「Picked up」(메일 없음) ═══
create function public.shop_fulfill_picked_up(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_so    public.so%rowtype;
  v_n     int;
  v_q     bigint;
  v_now   timestamptz := now();
begin
  perform public.ims_require_write('sales', 'saved');
  v_staff := public.so_current_staff();
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order % not found — nothing was saved', p_so_id; end if;
  if v_so.shipped_at is null then raise exception 'Order % has not been shipped (Ship & invoice first) — nothing was saved', v_so.so_number; end if;
  update public.shop_fulfillment f set picked_up_at = v_now, picked_up_by = v_staff, updated_by = v_staff
   where f.so_id = p_so_id and f.carrier_kind = 'pickup' and f.ready_at is not null and f.picked_up_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'Order %: nothing is waiting for pickup (Ready for pickup was not sent to Shopify yet, or it was already picked up) — nothing was saved', v_so.so_number;
  end if;
  v_q := public.shop_fulfill_requeue(p_so_id, 'picked_up');
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'fulfillments', v_n, 'picked_up_at', v_now, 'queue_id', v_q);
end;
$$;
revoke all on function public.shop_fulfill_picked_up(uuid) from public, anon;
grant execute on function public.shop_fulfill_picked_up(uuid) to authenticated;
comment on function public.shop_fulfill_picked_up(uuid) is 'ful-1b 판정 443: 손님이 찾아갔다 — 이 SO 의 픽업 결과 표 머리(ready_at 있고 picked_up_at 없음)에 picked_up_at · picked_up_by 를 바로 적고(직원이 본 사실 · SO 상태 무접촉) 큐 picked_up 을 넣는다 → EF fulfill_drain 이 픽업 FO 에 fulfillmentCreate(notifyCustomer false · 짐작 — 전용 mutation 없음) 로 Shopify 를 Fulfilled 로 · GID 를 받아 적는다 · sales 쓰기 · definer · 기다리는 것이 없으면 거부';

-- ═══ 9) 창구 so_tracking_fix — 판정 438 · 436 · 437 · 452 ═══
create function public.so_tracking_fix(p_so_id uuid, p_carrier_id uuid, p_tracking text, p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_so    public.so%rowtype;
  v_old   public.ref_carrier%rowtype;
  v_new   public.ref_carrier%rowtype;
  v_kind  text;
  v_trk   text[];
  v_n     int := 0;  v_gid int := 0;
  v_q     bigint;
begin
  perform public.ims_require_write('sales', 'saved');
  v_staff := public.so_current_staff();
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order % not found — nothing was saved', p_so_id; end if;
  if v_so.shipped_at is null or v_so.status not in ('shipped', 'fulfilled') then
    raise exception 'Order % is % — only a shipped order (Ship & invoice done) can have its carrier / tracking fixed here — nothing was saved', v_so.so_number, v_so.status;
  end if;
  if v_so.carrier_id is not null then select * into v_old from public.ref_carrier rc where rc.id = v_so.carrier_id; end if;
  v_kind := coalesce(v_old.kind, (select f.carrier_kind from public.shop_fulfillment f where f.so_id = p_so_id and f.carrier_kind is not null order by f.created_at limit 1));   -- 옛 오더(carrier_id 없음)는 결과 표의 종류 · 그것도 없으면 자유
  if p_carrier_id is null then raise exception 'Order %: pick a carrier from the list — nothing was saved', v_so.so_number; end if;
  select * into v_new from public.ref_carrier rc where rc.id = p_carrier_id;
  if not found then raise exception 'Order %: carrier % is not on the carrier list — nothing was saved', v_so.so_number, p_carrier_id; end if;
  if not v_new.is_active then raise exception 'Order %: carrier % is switched off — pick an active carrier — nothing was saved', v_so.so_number, v_new.name; end if;
  if v_kind is not null and v_new.kind <> v_kind then
    raise exception 'Order %: changing % (%) to % (%) changes how the order was delivered — only the carrier name and tracking numbers can be fixed after shipping — nothing was saved', v_so.so_number, coalesce(v_old.name, v_so.carrier, v_kind), v_kind, v_new.name, v_new.kind;
  end if;
  if v_new.kind <> 'carrier' then
    raise exception 'Order %: % has no tracking to fix (Pickup / Delivery orders carry no tracking number) — nothing was saved', v_so.so_number, v_new.name;
  end if;
  v_trk := public.shop_tracking_split(p_tracking);
  if coalesce(array_length(v_trk, 1), 0) = 0 then
    raise exception 'Order %: % needs a tracking number (several: separate with commas or new lines) — nothing was saved', v_so.so_number, v_new.name;
  end if;
  select count(*), count(f.shopify_fulfillment_gid) into v_n, v_gid from public.shop_fulfillment f where f.so_id = p_so_id;
  if not p_commit then
    return jsonb_build_object('committed', false, 'so_id', p_so_id, 'so_number', v_so.so_number, 'carrier', v_new.name, 'carrier_id', v_new.id, 'tracking', to_jsonb(v_trk),
                              'was', jsonb_build_object('carrier', v_so.carrier, 'tracking', v_so.tracking_number), 'shopify_fulfillments', v_n, 'shopify_update', v_gid > 0);
  end if;
  update public.so s set carrier_id = v_new.id, carrier = v_new.name, tracking_number = array_to_string(v_trk, ', '), updated_by = v_staff where s.id = p_so_id;
  update public.shop_fulfillment f set carrier_id = v_new.id, carrier_name = v_new.name, carrier_kind = v_new.kind, shopify_company = v_new.shopify_company, tracking_numbers = v_trk, notify_customer = true, updated_by = v_staff
   where f.so_id = p_so_id;                                                                                                                -- 머리마다(합친 SO 는 오더마다 · 판정 442) · GID 없는 머리(error · skipped)도 값만 — 다시 보낼 때 새 값으로
  if v_gid > 0 then v_q := public.shop_fulfill_requeue(p_so_id, 'tracking_fix'); end if;
  return jsonb_build_object('committed', true, 'so_id', p_so_id, 'so_number', v_so.so_number, 'carrier', v_new.name, 'carrier_id', v_new.id, 'tracking', to_jsonb(v_trk),
                            'was', jsonb_build_object('carrier', v_so.carrier, 'tracking', v_so.tracking_number), 'shopify_fulfillments', v_n, 'queue_id', v_q);
end;
$$;
revoke all on function public.so_tracking_fix(uuid, uuid, text, boolean) from public, anon;
grant execute on function public.so_tracking_fix(uuid, uuid, text, boolean) to authenticated;
comment on function public.so_tracking_fix(uuid, uuid, text, boolean) is 'ful-1b 판정 438: Ship & invoice 뒤 운송사 · 송장만 고치는 창구 — shipped · fulfilled 오더 · 운송사는 켜진 표 행 · 종류(carrier ↔ pickup · delivery)가 바뀌는 고침 거절 · pickup · delivery 는 고칠 송장이 없다 · carrier 면 송장 필수(쉼표 · 줄바꿈) · so.carrier_id · carrier · tracking_number + 결과 표 머리마다 갱신 · GID 있는 머리가 있으면 큐 tracking_fix(있으면 다시 연다) → EF fulfillmentTrackingInfoUpdate(손님 메일 없음) · p_commit false = 미리 보기 · sales 쓰기 · definer · Shopify 계보 없는 SO 도 so 칸은 고쳐진다';
