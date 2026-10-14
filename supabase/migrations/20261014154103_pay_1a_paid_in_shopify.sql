-- pay-1a (2026-10-14 · 판정 468 ② · ful-4b5 20261014133038 · ful-5a 20261014141305 위에) — Shopify 에서만 결제 표시된 웹 오더를 받기가 알아본다
--   판정 468 [Caleb · 2026-10-14 · 안 3 + 안 1 · 판정 449 의 반대 방향]: 결제는 IMS 에서만 기록한다 — ① 직원은 Shopify 에서 Mark as paid 를 하지 않는다(운영 · 코드 없음) ② 안전망: SO 가 만들어진 뒤(status created) Shopify 결제 상태가
--     PAID · PARTIALLY_PAID 로 바뀌었는데 IMS 가 시킨 것이 아니면 받기가 경고 paid_in_shopify 를 붙인다 · IMS 장부(결제 · 인보이스)는 건드리지 않는다
--     기각: 안 2(Shopify 표시를 근거로 IMS 결제 자동 기록 — Net 오더의 Mark as paid 는 돈의 증거가 아니고 계좌 · 방법을 모르며 진짜 수표를 적으면 두 번)
--   판정 449(정본 §61 · 아직 안 지음): Net 오더가 IMS 에서 다 결제되면 IMS 가 Shopify 를 Paid 로 바꾼다 — 그때의 바뀜은 IMS 가 시킨 것 · 표지 = 새 칸 shop_order.paid_push_at(449 차수의 EF 가 적는다 · 지금은 늘 null) · last_push_at(오더 고치기 메아리)과 다른 칸(같이 쓰면 오더 고치기 직후 2 분 안의 직원 Mark as paid 가 삼켜진다)
--   판정 370(SO 를 만들 때 PAID 면 결제를 적는다)은 그대로 — 이 차수는 SO 가 생긴 뒤의 바뀜만 본다
--   ⭐ 구현: ① 새 칸 paid_push_at ② shop_order_ingest 재발행(4b5 판 바이트 복사 위에 더하기) — else 갈래 · 받기 전 status created · 받기 전 financial_status 가 PAID 가 아니고 이번이 PAID 또는 PARTIALLY_PAID 이며 같지 않으면(PENDING → PAID · PENDING → PARTIALLY_PAID · PARTIALLY_PAID → PAID) 「결제 표시가 생겼다」
--     · paid_push_at 뒤 −5 초 ~ +2 분 창(판정 447 ⓑ 와 같은 창)의 updatedAt 이면 IMS 가 시킨 것 — 경고 없음 · 일반 경고(updated_after_so)도 없음(메아리) · IMS 쪽 남은 돈 = shop_so_family(so_id) 의 SO 가 든 살아 있는 인보이스(so_invoice_list · so_ids 겹침 · status ≠ cancelled)의 remaining 합 · 인보이스가 없으면 null(「not invoiced yet」)
--     · 남은 돈이 0 이하면(IMS 에서 다 받았고 Shopify 도 Paid — 어긋남 없음) 경고 없음 · 경고 원소 {code paid_in_shopify, at, from, to, ims_remaining, message} 는 v_spec 에 들어가 일반 경고를 막는다(4b4 규칙) · 반환 끝에 paid_in_shopify true|false
--   ⚠️ 무접촉: EF · 화면(이름표 지도 WARN_LBL · WEB_WARN 은 대화 Claude) · cron · 뷰 shop_order_list(칸 목록이 명시라 새 칸이 안 들어간다 — 449 차수가 필요하면 더한다) · IMS 결제 · 인보이스 · 실물 #1001 ~ #1012 · 환불 고리(REFUNDED 로 가는 것은 refunded_in_shopify 가 본다)
--   검증: ~/asung/prompts/pay-1a-verify.sql(시험 적용 begin → rollback · 가짜 스토어 · 가짜 so 다섯 · 가짜 인보이스 셋(번호를 직접 줌 · 시퀀스 무접촉) · 가짜 직원 · 시퀀스 무접촉)
--   적용: psql "$(cat ~/.asung-testdb-url)" -1 -v ON_ERROR_STOP=1 -f supabase/migrations/20261014154103_pay_1a_paid_in_shopify.sql && supabase migration repair --status applied 20261014154103 --db-url "$(cat ~/.asung-testdb-url)"

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

-- ═══ ① 새 칸 — IMS 가 Shopify 에 결제 표시를 보낸 시각(판정 449 차수의 EF 가 적는다 · 지금은 늘 null) ═══
alter table public.shop_order add column paid_push_at timestamptz;
comment on column public.shop_order.paid_push_at is 'pay-1a 판정 468: IMS 가 Shopify 에 결제 표시(orderMarkAsPaid)를 보낸 시각 · 판정 449 차수의 EF 가 적는다(지금은 늘 null) · 받기의 paid_in_shopify 거르기 표지 — 이 시각 −5 초 ~ +2 분 안의 Shopify 결제 상태 바뀜은 IMS 가 시킨 것(last_push_at 은 오더 고치기 메아리용 · 다른 칸)';

-- ═══ ② shop_order_ingest 재발행 — ful-4b5 20261014133038:40 ~ 206 바이트 복사 · 바꾼 줄 3(일반 경고 조건 · 반환 끝 쉼표 · comment 토막) · 더한 줄: declare 1 · 판정 블록(아래 「pay-1a 판정 468」) · 반환 1 ═══
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
  v_fin_old text;  v_fin_new text;  v_paidchg boolean := false;  v_pecho boolean := false;  v_fam uuid[];  v_rem numeric;  v_paidw boolean := false;   -- pay-1a 판정 468: 받기 전 · 이번 결제 상태 · 결제 표시가 생겼나 · IMS 가 시킨 것(paid_push_at 창) · 가족 SO · IMS 남은 돈 · 경고를 붙였나
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
      -- pay-1a 판정 468 ②: SO 가 생긴 뒤(받기 전 status created) Shopify 결제 상태가 PAID · PARTIALLY_PAID 로 바뀌었는데 IMS 가 시킨 것이 아니면 paid_in_shopify — 받기 전 값(v_o.financial_status)이 PAID 가 아니고 이번 값과 다르며 이번 값이 PAID 또는 PARTIALLY_PAID(PENDING → PAID · PENDING → PARTIALLY_PAID · PARTIALLY_PAID → PAID · 같은 받기에서 하나)
      --   IMS 가 시킨 것 = updatedAt 이 paid_push_at(판정 449 차수의 EF 가 적는다 · 지금은 늘 null) 뒤 −5 초 ~ +2 분 창 안(판정 447 ⓑ 와 같은 창 · last_push_at 과 다른 칸 — 오더 고치기 직후의 직원 Mark as paid 를 삼키지 않게) → 경고 없음 · 일반 경고도 없음(v_pecho · 메아리)
      --   IMS 쪽 남은 돈 = 가족 SO(shop_so_family · 자기 · split 자손 · 합쳐 들어간 오더)가 든 살아 있는 인보이스(so_invoice_list · so_ids 겹침 · status ≠ cancelled)의 remaining 합 · 0 이하면(IMS 에서 다 받았고 Shopify 도 Paid) 어긋남이 없어 경고 없음 · 인보이스가 없으면 null(「not invoiced yet」) · IMS 장부는 건드리지 않는다
      v_fin_old := upper(coalesce(v_o.financial_status, ''));  v_fin_new := upper(coalesce(p_order->>'displayFinancialStatus', ''));
      v_paidchg := v_o.status = 'created' and v_fin_new in ('PAID', 'PARTIALLY_PAID') and v_fin_old <> 'PAID' and v_fin_old <> v_fin_new;
      if v_paidchg then
        v_pecho := coalesce(v_o.paid_push_at is not null and nullif(p_order->>'updatedAt', '')::timestamptz between v_o.paid_push_at - interval '5 seconds' and v_o.paid_push_at + interval '2 minutes', false);
        if not v_pecho then
          select coalesce(array_agg(f.id), '{}') into v_fam from public.shop_so_family(v_o.so_id) as f(id);
          select sum(l.remaining) into v_rem from public.so_invoice_list l where l.so_ids && v_fam and l.status <> 'cancelled';
          if v_rem is null or v_rem > 0 then
            v_paidw := true;
            v_spec := v_spec || jsonb_build_object('code', 'paid_in_shopify', 'at', now(), 'from', v_o.financial_status, 'to', p_order->>'displayFinancialStatus', 'ims_remaining', v_rem,
                                                   'message', format('Shopify order %s was marked %s in Shopify, but payments are recorded in IMS only — record the real payment in IMS (Take a payment) or undo the mark in Shopify (IMS: %s)', p_order->>'name', p_order->>'displayFinancialStatus',
                                                                     case when v_rem is null then 'not invoiced yet' else format('%s still owed on the IMS invoice(s)', v_rem) end));
          end if;
        end if;
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
             warnings = warnings || (case when v_moved and not v_auto and not v_echo and not v_pecho and jsonb_array_length(v_spec) = 0 and coalesce(array_length(v_absorbed, 1), 0) = 0 then jsonb_build_array(v_warn) else '[]'::jsonb end)   -- ord-1b2: 자동 취소로 끝난 받기는 「손으로 확인」 경고(updated_after_so · cancelled_in_shopify)를 남기지 않는다 · ful-1b: 메아리 · 구체 경고가 있으면 안 붙인다   -- ful-4b5: 흡수된 환불이 있으면(메아리처럼) 일반 경고도 안 붙인다
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
                            'refunds_absorbed', to_jsonb(v_absorbed),                                                                                                            -- ful-4b5
                            'paid_in_shopify', v_paidw);                                                                                                                         -- pay-1a 판정 468
end;
$$;
revoke all on function public.shop_order_ingest(uuid, jsonb) from public, anon, authenticated;
do $$ begin
  execute format('comment on function public.shop_order_ingest(uuid, jsonb) is %L', coalesce(obj_description('public.shop_order_ingest(uuid, jsonb)'::regprocedure, 'pg_proc'), '') || ' · ⭐ pay-1a 판정 468: created 오더의 받기가 Shopify 결제 상태 바뀜(받기 전 PAID 아님 → PAID 또는 PARTIALLY_PAID · 같지 않을 때)을 보고 IMS 가 시킨 것(paid_push_at −5 초 ~ +2 분 창)이 아니고 IMS 인보이스 남은 돈이 0 이하가 아니면 paid_in_shopify {from, to, ims_remaining}(v_spec — 일반 경고 없음) · IMS 장부 무접촉 · 반환 paid_in_shopify');
end $$;

-- ═══ 자기 검사 — 설계대로 들어앉았는지(아니면 멈춘다 · 트랜잭션 안이라 되돌아간다) ═══
do $$
declare v_bad text := ''; v_src text;
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'shop_order' and column_name = 'paid_push_at' and data_type = 'timestamp with time zone') <> 1 then v_bad := v_bad || ' column'; end if;
  select p.prosrc into v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_order_ingest';
  if v_src not like '%pay-1a 판정 468%' or v_src not like '%''paid_in_shopify''%' or v_src not like '%shop_so_family%' or v_src not like '%paid_push_at%' or v_src not like '%not v_pecho%' then v_bad := v_bad || ' ingest(body)'; end if;
  if has_function_privilege('authenticated', 'public.shop_order_ingest(uuid, jsonb)', 'execute') or has_function_privilege('anon', 'public.shop_order_ingest(uuid, jsonb)', 'execute') or has_function_privilege('public', 'public.shop_order_ingest(uuid, jsonb)', 'execute') then v_bad := v_bad || ' ingest(acl)'; end if;
  if to_regprocedure('public.shop_so_family(uuid)') is null then v_bad := v_bad || ' shop_so_family'; end if;
  if (select count(*) from pg_attribute where attrelid = 'public.so_invoice_list'::regclass and attname in ('so_ids', 'remaining', 'status') and not attisdropped) <> 3 then v_bad := v_bad || ' so_invoice_list'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM468', message = format('STOP - pay-1a did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
