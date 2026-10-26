-- ovd-1 (2026-10-26 · 판정 768 ~ 771 · frt-1a 20261014201428 위에) — 연체 인보이스 알림: 읽기 창구 + 웹 오더 경고(DB 몫 · 화면 pos.html · so.html 은 대화 Claude)
--   판정 768 [Caleb 「B」]: 기한이 지난(연체) 인보이스가 있을 때만 알린다 — 기한 전 미수(Net 30 등) · 기한 없는 인보이스(due_on null · due_unknown)는 알리지 않는다(정본 「기한 없음은 연체에 섞지 않는다」)
--   판정 769 [Caleb 「맞아」]: POS · Sales Orders 새 오더는 손님을 고르는 순간 창(연체 N 장 · 합계 통화별 · 가장 오래된 N 일 · OK 로 닫힘 · 막지 않음) · Shopify 웹 오더는 사람이 없으니 SO 에 경고 꼬리표(판정 467 꼴 · Mark checked)
--   판정 770 [Caleb 「A」]: 여유 0 일 — 뷰 so_invoice_list 의 days_overdue > 0 정의 그대로(C.B.S 는 due_on = issued_on 이라 다음 날부터 연체) · 설정 칸(inv_config)은 만들지 않는다
--   판정 771 [Caleb 「A」]: 창구가 「쓸 수 있는 돈」(so_customer_balance.available · 통화별 · > 0 만)을 함께 돌려준다 — 화면이 작게 보인다(미배분 결제가 있는 손님을 괜히 독촉하지 않게)
--   누구의 연체: 청구처(bill-to) 기준 — 창구 안에서 coalesce(customer.default_bill_to_customer_id, customer.id)(so_copy_customer 와 같은 줄) · 청구처가 다르면 bill_to_differs true + bill_to_name
--   ① 새 읽기 창구 so_customer_overdue(p_customer_id) → jsonb {customer_id, bill_to_customer_id, bill_to_name, bill_to_differs, as_of, count, oldest_days, by_currency[{currency_code, count, amount, oldest_days}], invoices[상위 10 · 일수 내림 · {invoice_id, invoice_number, issued_on, due_on, days_overdue, remaining, currency_code}], available[{currency_code, available}]}
--      · stable · security invoker · authenticated 실행(so_invoice_ar_summary 와 같은 꼴 — 뷰 so_invoice_list 도 invoker · so_invoice select 정책 authenticated 전부 · 원가 값 없음) · 손님이 없으면 null · 셈은 뷰 한 곳(식을 다시 짜지 않는다) · count 0 이면 화면은 창을 띄우지 않는다
--   ② 새 속 함수 shop_order_overdue_warning(p_customer_id) → jsonb 배열(경고 원소 하나 customer_overdue 또는 빈 배열) — 글 「N overdue invoice(s) at the time the order came in — CAD 1,234.56 · USD 10.00 — oldest N day(s)[ — billed to 청구처]」 · 그때 값(count · oldest_days · by_currency · bill_to_* · as_of · at) · 직접 호출 불가(revoke · shop_order_process 안에서만 · frt-1a shop_order_freight 꼴)
--   ③ shop_order_process 재발행(frt-1a 판 바이트 복사 위 · 더한 줄 1 = ① so_create 바로 뒤 한 문장) — v_warn 에 원소를 더하고 뒤의 「created · warnings || v_warn」 이 그대로 싣는다 · 오더당 한 번(received → created)이라 중복 없음 · 막지 않는다(so_confirm 은 그대로) · 경고는 지우지 않는다(판정 467 · Mark checked) · 연체가 나중에 풀려도 그대로(글이 「at the time」)
--   ⚠️ 무접촉: 뷰 so_invoice_list · so_invoice_ar_summary · so_customer_balance · shop_order_warn(허용 목록 — process 가 만드는 원소는 그 목록을 거치지 않는다) · ingest · prepare · resolve_customer · 화면(이름표 customer_overdue 는 so.html · shopify-orders.html · 창은 pos.html · so.html — 대화 Claude) · inv_config · 실물 인보이스 · 손님
--   검증: ~/asung/prompts/ovd-1-verify.sql(시험 적용 begin → rollback · 가짜 손님 넷(부모 = 청구처 · 자식 · 홀로 · 빈) · 가짜 인보이스 8 장 · 결제 2 · 번호 시퀀스 무접촉 — shop_order_process 는 so_number_seq 를 당기므로 부르지 않고 속 함수 ② 를 직접)
--   적용: psql "$(cat ~/.asung-testdb-url)" -1 -v ON_ERROR_STOP=1 -f supabase/migrations/20261026192704_ovd_1_customer_overdue.sql && supabase migration repair --status applied 20261026192704 --db-url "$(cat ~/.asung-testdb-url)"

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

-- ═══ ① so_customer_overdue — 읽기 창구(손님 → 청구처 → 연체 인보이스 · 통화별 · 가장 오래된 일수 · 상위 10 장 · 쓸 수 있는 돈) ═══
create function public.so_customer_overdue(p_customer_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with c as (
    select c.id as customer_id, coalesce(c.default_bill_to_customer_id, c.id) as bill_to_customer_id                        -- so_copy_customer 와 같은 줄(청구처 규칙은 default_bill_to_customer_id 한 칸 · null = 자기)
      from public.customer c where c.id = p_customer_id
  ),
  x as (                                                                                                                 -- 연체 = 뷰 정의 그대로(issued ∧ remaining > 0 ∧ due_on < ims_today) · 기한 없음은 days_overdue 0 이라 빠진다 · 여유 0 일(판정 770)
    select l.id, l.invoice_number, l.issued_on, l.due_on, l.days_overdue, l.remaining, l.currency_code
      from c join public.so_invoice_list l on l.bill_to_customer_id = c.bill_to_customer_id
     where l.is_open and l.days_overdue > 0
  ),
  g as (
    select x.currency_code, count(*)::int as n, sum(x.remaining) as amount, max(x.days_overdue)::int as oldest_days
      from x group by x.currency_code
  )
  select jsonb_build_object(
           'customer_id',         c.customer_id,
           'bill_to_customer_id', c.bill_to_customer_id,
           'bill_to_name',        (select b.name from public.customer b where b.id = c.bill_to_customer_id),
           'bill_to_differs',     (c.bill_to_customer_id <> c.customer_id),
           'as_of',               public.ims_today(),
           'count',               (select count(*)::int from x),
           'oldest_days',         (select coalesce(max(x.days_overdue), 0)::int from x),
           'by_currency',         coalesce((select jsonb_agg(jsonb_build_object('currency_code', g.currency_code, 'count', g.n, 'amount', g.amount, 'oldest_days', g.oldest_days) order by g.currency_code) from g), '[]'::jsonb),
           'invoices',            coalesce((select jsonb_agg(jsonb_build_object('invoice_id', t.id, 'invoice_number', t.invoice_number, 'issued_on', t.issued_on, 'due_on', t.due_on, 'days_overdue', t.days_overdue, 'remaining', t.remaining, 'currency_code', t.currency_code) order by t.days_overdue desc, t.invoice_number)
                                            from (select x.* from x order by x.days_overdue desc, x.invoice_number limit 10) t), '[]'::jsonb),
           'available',           coalesce((select jsonb_agg(jsonb_build_object('currency_code', b.currency_code, 'available', b.available) order by b.currency_code)
                                            from public.so_customer_balance(c.bill_to_customer_id) b where b.available > 0), '[]'::jsonb))   -- 판정 771: 받아 둔 돈 + 크레딧 − 예약(so_customer_balance 한 곳의 값) · > 0 만
    from c;
$$;
revoke all on function public.so_customer_overdue(uuid) from public, anon;
grant execute on function public.so_customer_overdue(uuid) to authenticated;
comment on function public.so_customer_overdue(uuid) is
  '⭐ ovd-1 판정 768 ~ 771: 손님의 청구처 연체 — 읽기(stable · invoker · authenticated) · 청구처 = coalesce(default_bill_to_customer_id, id) · 연체 = 뷰 so_invoice_list 의 is_open ∧ days_overdue > 0(여유 0 일 · 기한 없음 제외 · 취소 제외 · remaining 은 so_invoice_remaining) · {customer_id, bill_to_customer_id, bill_to_name, bill_to_differs, as_of, count, oldest_days, by_currency[{currency_code, count, amount, oldest_days}], invoices[상위 10 · 일수 내림], available[{currency_code, available} · so_customer_balance · > 0 만]} · 손님이 없으면 null · POS · Sales Orders 가 손님을 고르는 순간 한 번 부른다(count 0 = 창 없음 · 막지 않음) · 웹 오더 경고(shop_order_overdue_warning)도 이 값으로 — 셈을 다시 짜지 않는다';

-- ═══ ② shop_order_overdue_warning — 경고 원소 배열(하나 또는 빈 배열) · shop_order_process 안에서만 ═══
create function public.shop_order_overdue_warning(p_customer_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with o as (select public.so_customer_overdue(p_customer_id) as v)
  select case when coalesce((o.v->>'count')::int, 0) = 0 then '[]'::jsonb
              else jsonb_build_array(jsonb_build_object(
                     'code', 'customer_overdue', 'at', now(),
                     'count', o.v->'count', 'oldest_days', o.v->'oldest_days', 'by_currency', o.v->'by_currency',
                     'bill_to_customer_id', o.v->'bill_to_customer_id', 'bill_to_name', o.v->'bill_to_name', 'bill_to_differs', o.v->'bill_to_differs', 'as_of', o.v->'as_of',
                     'message', format('%s overdue invoice%s at the time the order came in — %s — oldest %s day%s%s',
                                       o.v->>'count', case when (o.v->>'count')::int = 1 then '' else 's' end,
                                       (select string_agg(e->>'currency_code' || ' ' || to_char((e->>'amount')::numeric, 'FM999,999,990.00'), ' · ' order by e->>'currency_code') from jsonb_array_elements(o.v->'by_currency') e),
                                       o.v->>'oldest_days', case when (o.v->>'oldest_days')::int = 1 then '' else 's' end,
                                       case when (o.v->>'bill_to_differs')::boolean then ' — billed to ' || (o.v->>'bill_to_name') else '' end)))
         end
    from o;
$$;
revoke all on function public.shop_order_overdue_warning(uuid) from public, anon, authenticated;
comment on function public.shop_order_overdue_warning(uuid) is
  'ovd-1 판정 769: 웹 오더의 손님(→ 청구처)에 연체 인보이스가 있으면 경고 원소 하나 [{code customer_overdue, at, count, oldest_days, by_currency, bill_to_customer_id, bill_to_name, bill_to_differs, as_of, message}] · 없으면 [] — so_customer_overdue 의 그때 값 · 글 「N overdue invoice(s) at the time the order came in — CAD 1,234.56 · USD 10.00 — oldest N day(s)[ — billed to 청구처]」 · shop_order_process ① so_create 바로 뒤에서만(직접 호출 불가 · revoke) · 막지 않는다 · 지우지 않는다(판정 467 · Mark checked) · 연체가 나중에 풀려도 그대로';

-- ═══ ③ shop_order_process 재발행 — frt-1a 20261014201428:67 ~ 235 바이트 복사 · 더한 줄 1(① so_create 바로 뒤 한 문장) ═══
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
    v_warn := v_warn || public.shop_order_overdue_warning(c.id);                                                                          -- ovd-1 판정 769 · 770 · 771: 청구처에 연체 인보이스가 있으면 경고 원소 customer_overdue(그때 값 · 금액 · 「at the time the order came in」 · 없으면 빈 배열) — 막지 않는다 · 뒤의 created 갱신이 warnings || v_warn 으로 싣는다
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
  execute format('comment on function public.shop_order_process(uuid) is %L', coalesce(obj_description('public.shop_order_process(uuid)'::regprocedure, 'pg_proc'), '') || ' · ⭐ ovd-1 판정 769: ① so_create 바로 뒤 v_warn := v_warn || shop_order_overdue_warning(c.id) — 청구처에 연체 인보이스가 있으면 경고 원소 customer_overdue(그때 값 · 금액 · 「at the time the order came in」) · 막지 않는다 · 지우지 않는다(판정 467 · Mark checked) · 오더당 한 번이라 중복 없음');
end $$;

-- ═══ 자기 검사 — 설계대로 들어앉았는지(아니면 멈춘다 · 트랜잭션 안이라 되돌아간다) ═══
do $$
declare v_bad text := ''; v_src text; v_p pg_proc%rowtype;
begin
  select p.* into v_p from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_customer_overdue';
  if v_p.oid is null then v_bad := v_bad || ' overdue(missing)';
  else
    if v_p.prosecdef or v_p.provolatile <> 's' then v_bad := v_bad || ' overdue(invoker/stable)'; end if;
    if v_p.prosrc not like '%coalesce(c.default_bill_to_customer_id, c.id)%' or v_p.prosrc not like '%l.is_open and l.days_overdue > 0%' or v_p.prosrc not like '%public.so_customer_balance(c.bill_to_customer_id)%' or v_p.prosrc not like '%limit 10%' then v_bad := v_bad || ' overdue(body)'; end if;
    if not has_function_privilege('authenticated', 'public.so_customer_overdue(uuid)', 'execute') or has_function_privilege('anon', 'public.so_customer_overdue(uuid)', 'execute') then v_bad := v_bad || ' overdue(acl)'; end if;
  end if;
  select p.* into v_p from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_order_overdue_warning';
  if v_p.oid is null then v_bad := v_bad || ' warning(missing)';
  else
    if v_p.prosrc not like '%''customer_overdue''%' or v_p.prosrc not like '%at the time the order came in%' or v_p.prosrc not like '%billed to%' then v_bad := v_bad || ' warning(body)'; end if;
    if has_function_privilege('authenticated', 'public.shop_order_overdue_warning(uuid)', 'execute') or has_function_privilege('anon', 'public.shop_order_overdue_warning(uuid)', 'execute') or has_function_privilege('public', 'public.shop_order_overdue_warning(uuid)', 'execute') then v_bad := v_bad || ' warning(acl)'; end if;
  end if;
  select p.prosrc into v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_order_process';
  if v_src not like '%v_warn := v_warn || public.shop_order_overdue_warning(c.id);%' or v_src not like '%ovd-1 판정 769%'
     or v_src not like '%frt-1a%' or v_src not like '%public.shop_order_freight(v_so_id, v_s.kind, v_o.name%' or v_src not like '%pay-3a 판정 470%' or v_src not like '%ful-1b 판정 454%' or v_src not like '%insert into public.shop_order_transaction%' then v_bad := v_bad || ' process(body)'; end if;
  if (select count(*) from regexp_matches(v_src, 'shop_order_overdue_warning', 'g')) <> 1 then v_bad := v_bad || ' process(once)'; end if;
  if exists (select 1 from public.inv_config where key like '%overdue%') then v_bad := v_bad || ' inv_config(판정 770 — 설정 칸 없음)'; end if;
  if to_regprocedure('public.so_invoice_ar_summary(uuid)') is null or to_regprocedure('public.so_customer_balance(uuid)') is null or to_regclass('public.so_invoice_list') is null then v_bad := v_bad || ' deps'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM769', message = format('STOP - ovd-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
