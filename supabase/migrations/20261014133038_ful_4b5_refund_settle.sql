-- ful-4b5 (2026-10-14 · 판정 466 · ful-4b4 20261014010000 위에) — IMS 가 시킨 환불을 받기가 알아본다
--   실물(2026-10-14 · 테스트 DB · 시험 스토어 #1012 · ANN01002 × 2 · 1 발송 · 1 pick_short): 직원이 Shopify 에서 Unfulfilled 1 개 $1.49 Restock 환불 → 받기가 refunded_in_shopify 를 붙였다(「make the credit note in IMS by hand」 — 거짓 · 그 1 개는 IMS 에서 나간 적이 없다 · 따르면 크레딧 두 번)
--     그리고 장부 removed_qty 0 · gap 1 · warned_qty 1 그대로라 refund_due 가 영원히 열려 있다 · 금액 대조는 안 된다(IMS still owed 1.68 = 1.49 + 세금 vs Shopify 환불 1.49)
--   판정 466 [Caleb · 2026-10-14 · 안 1]: 받기가 ① refunded_in_shopify 를 붙이지 않고 ② 그 줄의 gap 을 닫고 ③ refund_due 는 지우지 않고 「처리됨」으로 — 짝은 금액이 아니라 Shopify 줄 GID · 수량 · 흡수되지 않는 환불(나간 물건 반품 · refund_due 없는 환불 · 줄 없는 금액만 환불)은 지금처럼 refunded_in_shopify
--     기각: 안 2(문구만 — 직원 판단에 기대고 refund_due 가 영원히 열림) · 안 3(금액 대조 — 세금으로 틀리고 같은 금액의 다른 줄 환불을 잘못 거른다)
--   ⭐ 구현 모양: 새 칸 없음 — 장부 removed_qty 의 뜻이 이미 「Shopify 가 더는 안 싣는 수량 = quantity − currentQuantity」(_shared/shopify-edit.ts:100)이고 Shopify 는 미발송 환불을 currentQuantity 에 반영한다(실측 I: quantity 2 · currentQuantity 1) → 받기가 같은 식으로 removed_qty 를 적으면 refund_due 는 저절로 닫힌다
--     (새 칸 refunded_qty 를 두면 같은 사실이 두 칸에 들어가 EF 가 removed_qty 를 다시 적는 순간 두 번 빠진다 — gap −1 → 거짓 shopify_qty_removed) · removed_qty 를 쓰는 곳은 EF writeRemoved(돈 안 받은 오더 · 큐) 와 받기(이 차수) 둘
--   ⚠️ 무접촉: EF · 화면 · cron · shop_unshipped_scan(upsert 가 removed_qty 를 덮지 않는 것을 검증 S9 가 확인) · 실물 #1012(적용 뒤 Caleb 이 Shopify 에서 건드려 시험 — 다음 받기에서 ① 이 removed_qty 1 → gap 0 → ④ 로 닫힌다)
--   검증: ~/asung/prompts/ful-4b5-verify.sql(시험 적용 begin → rollback · 가짜 스토어 · 가짜 so · 시퀀스 무접촉)
--   적용: psql "$(cat ~/.asung-testdb-url)" -1 -v ON_ERROR_STOP=1 -f supabase/migrations/20261014133038_ful_4b5_refund_settle.sql && supabase migration repair --status applied 20261014133038 --db-url "$(cat ~/.asung-testdb-url)"

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

-- ═══ shop_order_ingest 재발행 — ful-4b4 20261014010000:11 ~ 137 바이트 복사 · 바꾼 줄 3(일반 경고 조건 · 반환 끝 쉼표 · comment 토막) · 더한 줄: declare 1 · ①② 19 · ③ 14 · ④ 5 · 반환 1 ═══
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
  v_ln jsonb;  v_cq numeric;  v_wb numeric := 0;  v_wa numeric := 0;  v_abs jsonb := '{}'::jsonb;  v_ok boolean;  v_rl jsonb;  v_absorbed text[] := '{}';  v_settled jsonb := '[]'::jsonb;   -- ful-4b5 판정 466: 받기가 적는 removed_qty · 흡수 몫(line_gid → 남은 수량) · 흡수된 환불
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
      -- ful-4b5 판정 466: IMS 가 refund_due 로 시킨 환불을 직원이 Shopify 에서 하면 받기가 알아본다 — 장부는 created 오더에만(스캔이 그렇게 고른다) · ① removed_qty 를 받기가 적는다(EF removedQty 와 같은 식 quantity − currentQuantity · 상한 quantity − sent: Shopify 는 나간 몫을 「지울」 수 없다 — 나간 물건 반품이 currentQuantity 를 줄여도 gap 이 음수가 되지 않게)
      --   ② 흡수 몫 = warned_qty 가 줄어든 만큼(받기 안에서 gap 이 줄어드는 길은 removed_qty 뿐 — can_ship 은 안 건드린다) · warned_qty 를 새 gap 으로 내려 나중에 같은 줄의 새 gap 을 스캔이 다시 알리게(판정 461 「커질 때만」) · ③ 새 환불의 줄이 모두 이 오더의 line_gid 이고 수량이 남은 흡수 몫 안이면 refunded_in_shopify 를 붙이지 않는다(짝은 금액이 아니라 줄 GID · 수량 — 세금 때문에 금액은 어긋난다)
      --   ④ sum(warned_qty) 가 > 0 에서 0 이 되면 refund_due 원소에 settled_at · settled_refunds 를 덧붙인다(지우지 않는다 · 순서 그대로) · 새 환불 없이 닫히는 길(옛 환불이 raw 에 이미 있음)도 같다(settled_refunds 빈 배열) · 장부 줄이 없으면(스캔 전) 만든다 — 스캔의 upsert 는 removed_qty 를 덮지 않는다
      if v_o.status = 'created' then
        for v_ln in select x from jsonb_array_elements(p_order->'lineItems'->'nodes') as x loop
          if (nullif(v_ln->>'currentQuantity', '') ~ '^[0-9]+(\.[0-9]+)?$') is not true then continue; end if;                                   -- currentQuantity 가 없거나 숫자가 아니면 그 줄은 지금 값 그대로
          v_cq := (v_ln->>'currentQuantity')::numeric;
          insert into public.shop_order_line_unshipped as u (shop_order_line_id, shop_order_id, quantity, sent, can_ship, gap, removed_qty, computed_at)
          select sol.id, v_o.id, sol.quantity, 0, 0, 0, greatest(sol.quantity - v_cq, 0), now()
            from public.shop_order_line sol where sol.shop_order_id = v_o.id and sol.line_gid = v_ln->>'id'
          on conflict (shop_order_line_id) do update set removed_qty = least(greatest(excluded.quantity - v_cq, 0), greatest(excluded.quantity - u.sent, 0)), computed_at = now();
        end loop;
        update public.shop_order_line_unshipped u set gap = u.quantity - u.sent - u.removed_qty - u.can_ship where u.shop_order_id = v_o.id;           -- can_ship · sent 는 장부 값 그대로(받기는 can_ship 을 다시 세지 않는다)
        select coalesce(sum(u.warned_qty), 0), coalesce(jsonb_object_agg(sol.line_gid, u.warned_qty - least(u.warned_qty, greatest(u.gap, 0))) filter (where u.warned_qty > least(u.warned_qty, greatest(u.gap, 0))), '{}'::jsonb)
          into v_wb, v_abs
          from public.shop_order_line_unshipped u join public.shop_order_line sol on sol.id = u.shop_order_line_id where u.shop_order_id = v_o.id;
        update public.shop_order_line_unshipped u set warned_qty = least(u.warned_qty, greatest(u.gap, 0)) where u.shop_order_id = v_o.id and u.warned_qty > least(u.warned_qty, greatest(u.gap, 0));
        select coalesce(sum(u.warned_qty), 0) into v_wa from public.shop_order_line_unshipped u where u.shop_order_id = v_o.id;
      end if;
      for r in select f from jsonb_array_elements(coalesce(p_order->'refunds', '[]'::jsonb)) f where not (f->>'id' = any(v_oldr))
                   and (nullif(f->'totalRefundedSet'->'shopMoney'->>'amount', '') ~ '^-?[0-9]+(\.[0-9]+)?$' and (f->'totalRefundedSet'->'shopMoney'->>'amount')::numeric = 0   -- ful-4b4 판정 463: 0 원 환불이(restock 한 줄 지우기를 Shopify 가 금액 0 의 Refund 로 남긴다 · 실물 #1011 Refund/938562158775)
                        and v_push is not null and nullif(f->>'createdAt', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T' and nullif(f->>'createdAt', '')::timestamptz between v_push - interval '5 seconds' and v_push + interval '2 minutes') is not true   -- 우리 마지막 쓰기 뒤 2 분 안(앞 5 초 · 판정 447 ⓑ 와 같은 창)이면 메아리 → 건너뜀 · 금액 null · 숫자 아님 · createdAt 없음 · 돈이 움직인 환불은 창 안이어도 지금처럼 경고 · is not true: null 이면 거르지 않는다
      loop
        -- ful-4b5 판정 466 ③: 줄마다 모아(같은 lineItem 이 두 줄이면 합) 전부 이 오더의 줄이고 수량 > 0 이고 남은 흡수 몫 안이면 흡수 — refunded_in_shopify 없이 깎아 쓴다 · restockType 은 판정에 안 쓰고 기록만(Restock 을 끄면 NO_RESTOCK 으로 올 수 있다) · 수량이 숫자 아님 · 줄 없음 · 빈 목록은 흡수 아님
        select coalesce(bool_and(t.ok and (v_abs ? t.gid) and t.q > 0 and t.q <= (v_abs->>t.gid)::numeric), false),
               coalesce(jsonb_agg(jsonb_build_object('line_gid', t.gid, 'quantity', t.q, 'restock_type', t.rt)), '[]'::jsonb)
          into v_ok, v_rl
          from (select x->'lineItem'->>'id' as gid, bool_and(coalesce(x->>'quantity', '') ~ '^[0-9]+(\.[0-9]+)?$') as ok,
                       sum(case when coalesce(x->>'quantity', '') ~ '^[0-9]+(\.[0-9]+)?$' then (x->>'quantity')::numeric end) as q, string_agg(distinct x->>'restockType', ',') as rt
                  from jsonb_array_elements(coalesce(case when jsonb_typeof(r->'refundLineItems'->'nodes') = 'array' then r->'refundLineItems'->'nodes' end, '[]'::jsonb)) x
                 group by 1) t;
        if v_ok then
          select coalesce(jsonb_object_agg(a.key, a.value::numeric - coalesce((select sum((l->>'quantity')::numeric) from jsonb_array_elements(v_rl) l where l->>'line_gid' = a.key), 0)), '{}'::jsonb) into v_abs from jsonb_each_text(v_abs) a;
          v_absorbed := v_absorbed || (r->>'id');
          v_settled  := v_settled || jsonb_build_object('refund_gid', r->>'id', 'lines', v_rl);
          continue;
        end if;
        v_spec := v_spec || jsonb_build_object('code', 'refunded_in_shopify', 'at', now(), 'refund_gid', r->>'id', 'amount', (r->'totalRefundedSet'->'shopMoney'->>'amount')::numeric, 'note', nullif(trim(coalesce(r->>'note', '')), ''),
                                               'message', format('Shopify order %s was refunded in Shopify (%s %s · %s) — make the credit note in IMS by hand if stock came back (judge restocking there)', p_order->>'name', r->'totalRefundedSet'->'shopMoney'->>'amount', coalesce(r->'totalRefundedSet'->'shopMoney'->>'currencyCode', ''), coalesce(nullif(trim(coalesce(r->>'note', '')), ''), 'no note')));
      end loop;
      if v_o.status = 'created' and v_wb > 0 and v_wa = 0 then                                                                                 -- ful-4b5 판정 466 ④: 알린 몫이 다 지워졌다 — refund_due 를 「처리됨」으로(원소 무접촉 · 순서 그대로 · 다른 코드 무접촉)
        update public.shop_order o set warnings = coalesce((select jsonb_agg(case when w->>'code' = 'refund_due' and w->'settled_at' is null then w || jsonb_build_object('settled_at', now(), 'settled_refunds', v_settled) else w end order by ord)
                                                               from jsonb_array_elements(o.warnings) with ordinality as t(w, ord)), '[]'::jsonb)
         where o.id = v_o.id;
      end if;
      update public.shop_order set shopify_updated_at = nullif(p_order->>'updatedAt', '')::timestamptz, shopify_cancelled_at = v_cancel, financial_status = p_order->>'displayFinancialStatus', raw = p_order,
             delivery_method = v_dlv.method, pickup_location_gid = v_dlv.location_gid
       where id = v_o.id;                                                                                                                    -- ord-1b2: 원문 · 취소 시각 먼저(shop_order_cancelled 가 읽는다) · 경고는 취소 판정 뒤에
      if v_newcan and v_o.status in ('created', 'error') and not exists (select 1 from jsonb_array_elements(v_o.warnings) w where w->>'code' in ('auto_cancelled', 'cancel_needs_review', 'cancel_failed')) then
        v_cres := public.shop_order_cancelled(v_o.id);                                                                                       -- ord-1a2 판정 434: SO 가 있는 오더의 취소 — 한 번만 · ord-1b2: error(SO 없음)도 닫는다(closed_before_so)
      end if;
      v_auto := coalesce(v_cres->>'action', '') in ('auto_cancelled', 'closed_before_so');
      update public.shop_order set
             warnings = warnings || (case when v_moved and not v_auto and not v_echo and jsonb_array_length(v_spec) = 0 and coalesce(array_length(v_absorbed, 1), 0) = 0 then jsonb_build_array(v_warn) else '[]'::jsonb end)   -- ord-1b2: 자동 취소로 끝난 받기는 「손으로 확인」 경고(updated_after_so · cancelled_in_shopify)를 남기지 않는다 · ful-1b: 메아리 · 구체 경고가 있으면 안 붙인다   -- ful-4b5: 흡수된 환불이 있으면(메아리처럼) 일반 경고도 안 붙인다
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
                            'echo', v_echo, 'new_fulfillments', to_jsonb(v_newf), 'unknown_fulfillments', to_jsonb(v_unk), 'delivery_method', v_dlv.method,                    -- ful-1b
                            'refunds_absorbed', to_jsonb(v_absorbed));                                                                                                           -- ful-4b5
end;
$$;
revoke all on function public.shop_order_ingest(uuid, jsonb) from public, anon, authenticated;
do $$ begin
  execute format('comment on function public.shop_order_ingest(uuid, jsonb) is %L', coalesce(obj_description('public.shop_order_ingest(uuid, jsonb)'::regprocedure, 'pg_proc'), '') || ' · ⭐ ful-4b5 판정 466: created 오더의 받기가 removed_qty 를 적고(quantity − currentQuantity · 상한 quantity − sent) gap 을 다시 세며 warned_qty 가 줄어든 만큼이 흡수 몫 — 새 환불의 줄이 모두 이 오더의 line_gid 이고 수량이 흡수 몫 안이면 refunded_in_shopify 를 붙이지 않는다(짝은 줄 GID · 수량 · 금액 아님) · sum(warned_qty) 가 0 이 되면 refund_due 원소에 settled_at · settled_refunds · 반환 refunds_absorbed');
end $$;
