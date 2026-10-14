-- ful-4b4 (2026-10-13 · 판정 463 · ful-4a 20261014000000 위에) — 오더 고치기 메아리를 환불 경고에서 거른다
--   실물(2026-10-13 · 테스트 DB · #1011): 23:37:25 order_drain 이 ANN01015 2 → 1(restock true) → last_push_at 23:37:25 · 큐 5 done ok · removed_qty 1 · 그런데 23:38:00 웹훅 받기가 refunded_in_shopify 를 붙였다
--     {"code":"refunded_in_shopify","amount":0.0,"refund_gid":"gid://shopify/Refund/938562158775"} — Shopify 는 restock 한 줄 지우기를 금액 0 의 Refund 로 남긴다 · 메아리 ⓑ(판정 447)는 updated_after_so 에만 걸리고 환불 고리에는 안 걸렸다
--   판정 463 [Caleb · 2026-10-13]: 새 환불이 ① 금액 0 그리고 ② createdAt 이 v_push(= greatest(shop_fulfillment.last_push_at, shop_order.last_push_at)) − 5 초 ~ + 2 분 안이면 refunded_in_shopify 를 붙이지 않는다 ·
--     금액이 0 이 아니면 창 안이어도 경고(돈이 움직인 환불은 삼키지 않는다) · 금액 null · 숫자 아님 · createdAt 없음은 거르지 않는다(is not true) · 기각: 0 원이면 늘 거름(넓다) · 환불 줄 × removed_qty 대조(받기 함수가 장부를 읽어 커진다)
--   ⚠️ 기존 고리 본문의 (…amount)::numeric 캐스팅은 숫자 아닌 금액에 지금도 예외(받기 전체 실패) — 이 차수 무접촉 · 새 조건은 정규식으로 지켜 더 나빠지지 않게
--   EF 무접촉(_shared/shopify-order.ts 41 행 refunds 질의에 createdAt 이 이미 온다) · 화면 · cron · #1011 의 거짓 경고 한 줄(시험 기록) 무접촉
--   검증: ~/asung/prompts/ful-4b4-verify.sql(시험 적용 begin → rollback · 기대 OK 9)

-- ═══ shop_order_ingest 재발행 — ful-4a 20261014000000:270 ~ 388 바이트 복사 · 바꾼 줄 1(환불 고리 for … loop 을 갈라 조건을 끼움) · 더한 줄 4(조건 2 · loop 1 · 주석 1) ═══
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
      -- ful-4b4 판정 463: 새 환불이 0 원이고 createdAt 이 v_push 창 안이면 우리 오더 고치기(order_drain · restock)의 메아리 — refunded_in_shopify 를 붙이지 않는다(raw 에는 남아 다음부터 옛것) · 일반 경고(updated_after_so)는 그대로 updatedAt 창(v_echo)을 본다
      select coalesce(array_agg(f->>'id'), '{}') into v_oldf from jsonb_array_elements(coalesce(v_o.raw->'fulfillments', '[]'::jsonb)) f;
      select coalesce(array_agg(f->>'id'), '{}') into v_newf from jsonb_array_elements(coalesce(p_order->'fulfillments', '[]'::jsonb)) f where not (f->>'id' = any(v_oldf));
      select coalesce(array_agg(g), '{}') into v_unk from unnest(v_newf) g where not exists (select 1 from public.shop_fulfillment sf where sf.shop_order_id = v_o.id and sf.shopify_fulfillment_gid = g);
      select coalesce(array_agg(f->>'id'), '{}') into v_oldr from jsonb_array_elements(coalesce(v_o.raw->'refunds', '[]'::jsonb)) f;
      select greatest(max(sf.last_push_at), v_o.last_push_at) into v_push from public.shop_fulfillment sf where sf.shop_order_id = v_o.id;   -- ful-4a: 오더 고치기(shop_order.last_push_at)도 메아리 ⓑ
      v_echo := (coalesce(array_length(v_newf, 1), 0) > 0 and coalesce(array_length(v_unk, 1), 0) = 0)
             or (v_push is not null and nullif(p_order->>'updatedAt', '')::timestamptz between v_push - interval '5 seconds' and v_push + interval '2 minutes');
      if coalesce(array_length(v_unk, 1), 0) > 0 then
        v_spec := v_spec || jsonb_build_object('code', 'fulfilled_in_shopify', 'at', now(), 'gids', to_jsonb(v_unk),
                                               'message', format('Shopify order %s was fulfilled in Shopify, not by IMS (%s fulfillment(s): %s) — the IMS order was not touched; check it by hand', p_order->>'name', array_length(v_unk, 1), array_to_string(v_unk, ', ')));
      end if;
      for r in select f from jsonb_array_elements(coalesce(p_order->'refunds', '[]'::jsonb)) f where not (f->>'id' = any(v_oldr))
                   and (nullif(f->'totalRefundedSet'->'shopMoney'->>'amount', '') ~ '^-?[0-9]+(\.[0-9]+)?$' and (f->'totalRefundedSet'->'shopMoney'->>'amount')::numeric = 0   -- ful-4b4 판정 463: 0 원 환불이(restock 한 줄 지우기를 Shopify 가 금액 0 의 Refund 로 남긴다 · 실물 #1011 Refund/938562158775)
                        and v_push is not null and nullif(f->>'createdAt', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' and nullif(f->>'createdAt', '')::timestamptz between v_push - interval '5 seconds' and v_push + interval '2 minutes') is not true   -- 우리 마지막 쓰기 뒤 2 분 안(앞 5 초 · 판정 447 ⓑ 와 같은 창)이면 메아리 → 건너뜀 · 금액 null · 숫자 아님 · createdAt 없음 · 돈이 움직인 환불은 창 안이어도 지금처럼 경고 · is not true: null 이면 거르지 않는다
      loop
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
do $$ begin
  execute format('comment on function public.shop_order_ingest(uuid, jsonb) is %L', coalesce(obj_description('public.shop_order_ingest(uuid, jsonb)'::regprocedure, 'pg_proc'), '') || ' · ⭐ ful-4b4 판정 463: 0 원 환불이 v_push − 5 초 ~ + 2 분 안이면(오더 고치기 restock 메아리) refunded_in_shopify 를 붙이지 않는다 · 돈이 움직인 환불은 창 안이어도 경고');
end $$;
