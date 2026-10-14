-- frt-1a (2026-10-14 · 판정 473 · pay-3a 20261014183133 위에) — asung.ca 「Pay on Invoice」 오더의 Shopify 운임을 SO 견적 운임으로
--   판정 473 [Caleb · 2026-10-14 · 안 1 · 미룬 191 닫음]: asung.ca 「Pay on Invoice」(asung.ca 의 유일한 수동 결제 방식)로 내려온 오더의 Shopify 운임은 SO 운임 줄에 견적(estimate)으로 넣는다 — Ship & invoice 에서 실제 운임으로 고칠 수 있다
--     까닭: 주문 때 손님이 낼 운임이 아직 정확하지 않고 손님들이 대개 오더를 더 보태며 asung.ca 손님은 모두 Shopify 로 주문하고 발송 전에 운임을 포함해 확인하고 결제한다 · 기각 안 2(경고 freight_not_applied 만) · 안 3(Pay on Invoice 끄기)
--   갈래 기준(frt-1a 조사): 스토어 종류 · 결제 방식 이름에 기대지 않고 **운임 금액 > 0 이면** 넣는다 — NetTerm 앱 오더는 운임 0 으로 오니 저절로 빠진다(CSV 47 건) · 픽업 오더는 shipping line 0.0(실측 #1014) · 이름(CSV Payment Method custom · 짐작)이 바뀌어도 안 깨진다
--   ① 새 속 함수 shop_order_freight(so_id, store_kind, order_name, shipping line jsonb) → 경고 원소 배열 — 운임 > 0 이면 so_charge_set(이름 = Shopify 운임 제목 · 금액 = 원 운임 · 설명 Shopify #이름 · 세금은 오더 규칙 · 할인은 판정 369 모양: 100 % 또는 금액 — aone 과 같은 호출) · aone 은 [] (지금 그대로) · 그 밖은 정보 원소 freight_estimate_from_shopify(settled_at = now() · 열린 경고 수에서 빠진다 · 판정 467 모양)
--   ② shop_order_process 재발행(pay-3a 판 바이트 복사 위 · ⑤ 운임 열 줄 → 한 줄 호출) — 경고 freight_not_applied 는 더 붙지 않는다 · 이미 SO 가 있는 오더는 손대지 않는다(메우기 없음 · 받기 처리는 received 오더에만)
--   ⚠️ 「확정」 표지는 없다 — 코드에는 aone 운임을 고정하는 칸 · 조건이 없고(so_finalize 는 charge_id 로 어느 줄이든 고친다 · 화면 estimate 꼬리표는 채널 warehouse + 상태로만) asung 줄도 같은 모양 · 둘의 차이는 정보 원소뿐(이견으로 보고)
--   ⚠️ 무접촉: so_charge · so_charge_set · so_finalize · ingest · 화면(이름표 freight_estimate_from_shopify 는 대화 Claude) · EF(받기 질의는 shippingLines 를 이미 읽는다) · 실물 #1001 ~ #1015 · SO-25081 ~ 25094
--   검증: ~/asung/prompts/frt-1a-verify.sql(시험 적용 begin → rollback · 속 함수를 가짜 SO 위에서 직접 — shop_order_process 는 so_number_seq 를 당기므로 부르지 않는다 · 시퀀스 무접촉)
--   적용: psql "$(cat ~/.asung-testdb-url)" -1 -v ON_ERROR_STOP=1 -f supabase/migrations/20261014201428_frt_1a_asung_freight_estimate.sql && supabase migration repair --status applied 20261014201428 --db-url "$(cat ~/.asung-testdb-url)"

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

-- ═══ ① shop_order_freight — 받기 처리의 운임 한 곳(aone 과 asung 이 같은 창구 · 다른 것은 정보 원소뿐) ═══
create or replace function public.shop_order_freight(p_so_id uuid, p_store_kind text, p_order_name text, p_fl jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_orig  numeric;
  v_disc  numeric;
  v_title text;
  v_res   jsonb;
begin
  v_orig  := (p_fl->'originalPriceSet'->'shopMoney'->>'amount')::numeric;                                                              -- ord-1a2 ⑤ 와 같은 식(칸 없으면 null → 0)
  v_disc  := (p_fl->'discountedPriceSet'->'shopMoney'->>'amount')::numeric;
  if coalesce(v_orig, 0) <= 0 then return '[]'::jsonb; end if;                                                                           -- 운임 0 · 없음 · 픽업(shipping line 0.0) · NetTerm 앱(운임 0) → 줄 없음
  v_title := coalesce(nullif(trim(p_fl->>'title'), ''), 'Freight');
  v_res := public.so_charge_set(p_so_id, v_title, v_orig, null, 'Shopify ' || p_order_name, null, null,                                  -- 판정 369 모양 그대로(aone 과 같은 호출): 무료 배송 = 운임 + 할인 100 % · 일부 할인 = 금액
                                case when coalesce(v_disc, v_orig) = 0 then 100 end,
                                case when coalesce(v_disc, v_orig) > 0 and v_disc < v_orig then round(v_orig - v_disc, 2) end);
  if p_store_kind = 'aone' then return '[]'::jsonb; end if;                                                                               -- 판정 369: 손님이 낸 배송비 그대로 · 원소 없음(지금 길)
  return jsonb_build_array(jsonb_build_object('code', 'freight_estimate_from_shopify', 'at', now(), 'settled_at', now(), 'amount', v_orig, 'discounted', v_disc, 'title', v_title,   -- 판정 473: 견적 · 처리됨 모양(467 · 열린 경고 아님)
                                              'charge_id', v_res->'charge'->>'id',
                                              'message', format('Shopify charged freight %s (%s) — put on the IMS order as an estimate; fix it at Ship & invoice if the actual freight differs', v_orig, v_title)));
end;
$$;
comment on function public.shop_order_freight(uuid, text, text, jsonb) is 'frt-1a 판정 473 · 369: 받기 처리(shop_order_process ⑤)의 운임 한 곳 — Shopify shipping line(원 운임 · 할인 뒤 운임 · 제목)이 운임 > 0 이면 so_charge_set(이름 = 제목 · 설명 Shopify #이름 · 세금은 오더 규칙 · 할인 100 % 또는 금액 · 판정 369 모양) · aone 은 [] · 그 밖(asung · Pay on Invoice · 카드)은 정보 원소 freight_estimate_from_shopify(settled_at · 열린 경고 아님) 하나를 돌려준다 — Ship & invoice 가 실제 운임으로 고친다(판정 357-7 · 확정 표지 없음) · 운임 0 · 픽업 · NetTerm 앱은 줄 없음 · 속 함수(실행권 없음 · process 안에서만)';
revoke all on function public.shop_order_freight(uuid, text, text, jsonb) from public, anon, authenticated;

-- ═══ ② shop_order_process 재발행 — pay-3a 20261014183133:306 ~ 483 바이트 복사 · 끼운 곳 하나(⑤ 운임 열 줄 → 두 줄) ═══
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
    -- ⑤ 운임 — aone(판정 369: 손님이 낸 배송비 · 무료 배송 = 운임 + 100 %) · asung(판정 473 · frt-1a: Shopify 운임을 SO 운임 줄에 견적으로 · 정보 원소 freight_estimate_from_shopify · Ship & invoice 가 고친다) — 속 함수 shop_order_freight 한 곳(운임 0 · 픽업 · NetTerm 은 줄 없음)
    v_warn := v_warn || public.shop_order_freight(v_so_id, v_s.kind, v_o.name, v_o.raw->'shippingLines'->'nodes'->0);
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
      insert into public.shop_order_transaction (transaction_gid, shop_order_id, so_payment_id, kind, gateway, amount, currency_code, processed_at, source)             -- pay-3a 판정 470: ⑦ 이 적은 결제의 거래 표지 — 받기가 raw 의 SALE · CAPTURE 를 「새 거래」로 다시 적지 않게(raw 비교와 별개로 남긴다)
      select t->>'id', v_o.id, (v_res->>'payment_id')::uuid, upper(t->>'kind'), t->>'gateway', (t->'amountSet'->'shopMoney'->>'amount')::numeric, upper(t->'amountSet'->'shopMoney'->>'currencyCode'), nullif(t->>'processedAt', '')::timestamptz, 'process'
        from jsonb_array_elements(coalesce(case when jsonb_typeof(v_o.raw->'transactions') = 'array' then v_o.raw->'transactions' end, '[]'::jsonb)) t
       where upper(coalesce(t->>'kind', '')) in ('CAPTURE', 'SALE') and upper(coalesce(t->>'status', '')) = 'SUCCESS' and coalesce(t->>'id', '') ~ '^gid://shopify/OrderTransaction/[0-9]+$' and nullif(t->'amountSet'->'shopMoney'->>'amount', '') ~ '^[0-9]+(\.[0-9]+)?$'
      on conflict (transaction_gid) do nothing;
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

-- ═══ comment(덧붙임 — 앞 차수 글은 그대로) ═══
do $$
begin
  execute format('comment on function public.shop_order_process(uuid) is %L', coalesce(obj_description('public.shop_order_process(uuid)'::regprocedure, 'pg_proc'), '') || ' · ⭐ frt-1a 판정 473: ⑤ 운임은 속 함수 shop_order_freight 한 곳 — asung(운임 > 0)도 SO 운임 줄을 견적으로 만들고 정보 원소 freight_estimate_from_shopify(settled) · 경고 freight_not_applied 는 더 붙지 않는다 · aone 은 그대로 · 이미 SO 가 있는 오더는 손대지 않는다');
end $$;

-- ═══ 자기 검사 — 설계대로 들어앉았는지(아니면 멈춘다 · 트랜잭션 안이라 되돌아간다) ═══
do $$
declare v_bad text := ''; v_src text;
begin
  select p.prosrc into v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_order_process';
  if v_src not like '%frt-1a%' or v_src not like '%public.shop_order_freight(v_so_id, v_s.kind, v_o.name%' or v_src like '%freight_not_applied%' or v_src not like '%pay-3a 판정 470%' or v_src not like '%ful-1b 판정 454%' or v_src not like '%insert into public.shop_order_transaction%' then v_bad := v_bad || ' process(body)'; end if;
  select p.prosrc into v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_order_freight';
  if v_src is null or v_src not like '%''freight_estimate_from_shopify''%' or v_src not like '%''settled_at'', now()%' or v_src not like '%so_charge_set(p_so_id%' then v_bad := v_bad || ' freight(body)'; end if;
  if has_function_privilege('authenticated', 'public.shop_order_freight(uuid, text, text, jsonb)', 'execute') or has_function_privilege('anon', 'public.shop_order_freight(uuid, text, text, jsonb)', 'execute') or has_function_privilege('public', 'public.shop_order_freight(uuid, text, text, jsonb)', 'execute') then v_bad := v_bad || ' freight(acl)'; end if;
  if to_regprocedure('public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric)') is null or to_regclass('public.shop_order_transaction') is null then v_bad := v_bad || ' deps'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM473', message = format('STOP - frt-1a did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
