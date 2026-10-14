-- pay-3a (2026-10-14 · 판정 470 · pay-1a 20261014154103 · pay-2b 20261014164407 위에) — Shopify 카드 캡처를 IMS 결제로 자동 기록
--   판정 470 [Caleb · 2026-10-14 · 판정 370 을 넓힘]: SO 가 생긴 뒤(shop_order.status created) Shopify 결제 상태가 바뀌었을 때 거래(transaction)의 gateway 로 가른다 — 카드 거래(gateway 가 손 표시가 아닌 kind CAPTURE · SALE · status SUCCESS)는 IMS 가 결제를 자동으로 적는다(370 과 같은 모양 · 거래 GID 로 두 번 적지 않는다)
--     · 경고 대신 「처리됨」 정보 원소 card_payment_recorded(settled_at 바로 · 판정 467 모양 · open_warning_count 에서 빠진다) · manual 게이트웨이(Mark as paid · 실물 #1005 · #1007 · #1010 gateway 'manual')는 지금처럼 paid_in_shopify(판정 468)
--   ① 새 표 shop_order_transaction — 거래 GID 표지(transaction_gid pk · shop_order_id · so_payment_id · kind · gateway · amount · currency_code · processed_at · source ingest|process) · 읽기만(authenticated select) · 쓰기는 ingest · process 안에서만
--   ② shop_order_ingest 재발행(pay-1a 판 바이트 복사 위 · 끼운 줄만) — else 갈래(created)에서 이전 raw 에 없던 거래 GID 이고 표지에도 없는 CAPTURE · SALE · SUCCESS 를 가른다: 손 표시(manual · gift_card · store_credit · 빈 값) · test 어긋남 → 지금처럼 paid_in_shopify 길 · 금액 · 통화 어긋남 → card_payment_failed · 나머지 = 카드 →
--      370 ⑦ 과 같은 창구 so_payment_add(method shopify · reference 오더 이름 · warehouse 오더 위치 · note 「card captured in Shopify」 + GID 끝 8 자 · 시스템 직원) · 손님 = SO 청구처 · 붙이기 = 창구 규칙 그대로(살아 있는 인보이스 남은 돈 → 인보이스 없는 열린 가족 SO 보증금 → 받아 둔 돈) · 창구 거부는 그 거래만 card_payment_failed(subtransaction · 받기는 끝까지)
--      · 결제 상태 바뀜(v_paidchg)이 적은 카드 거래로 다 설명되면(손 표시 없음 · 적은 결제 ≥ 1) paid_in_shopify 없음 · 일부만(카드 + manual)이면 카드 몫은 적고 paid_in_shopify 는 붙인 뒤의 남은 돈으로 · 일반 경고 updated_after_so 는 카드 원소가 있으면 안 붙는다 · 반환 끝에 card_payments
--   ③ shop_order_process 재발행(ful-1b 판 바이트 복사 위 · ⑦ 뒤 한 문장) — ⑦ 이 적은 결제의 거래(raw 의 CAPTURE · SALE · SUCCESS)를 같은 표지로 남긴다(raw 비교와 별개 · 배포 뒤 첫 재읽기 · raw 가 비었던 옛 오더 대비)
--   ⚠️ 무접촉: so_payment 표 · 창구 · shop_order_warn(card_payment_failed 는 ingest 가 직접 덧붙인다 — EF 는 안 쓴다) · 큐 · 스캔 · paid_state · 화면(이름표 card_payment_recorded · card_payment_failed 는 대화 Claude) · 실물 #1001 ~ #1014 · SO-25093
--   ⚠️ 판정 370 ⑦ 의 범위(aone 스토어만 · 받는 순간 PAID · v_o.total)는 그대로 — asung 스토어가 받는 순간 PAID(카드 SALE)인 오더는 이 차수도 적지 않는다(SO 가 생긴 뒤의 새 거래만 · 이견으로 보고)
--   검증: ~/asung/prompts/pay-3a-verify.sql(시험 적용 begin → rollback · 가짜 스토어 · 손님 · so · 인보이스 · 원문 · 시퀀스 무접촉 — so_payment 는 번호가 없다 · so_number · so_invoice_number 는 직접 준다)
--   적용: psql "$(cat ~/.asung-testdb-url)" -1 -v ON_ERROR_STOP=1 -f supabase/migrations/20261014183133_pay_3a_card_capture.sql && supabase migration repair --status applied 20261014183133 --db-url "$(cat ~/.asung-testdb-url)"

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

-- ═══ ① shop_order_transaction — 거래 GID 표지(두 번 적지 않기) ═══
create table if not exists public.shop_order_transaction (
  transaction_gid text primary key check (transaction_gid ~ '^gid://shopify/OrderTransaction/[0-9]+$'),
  shop_order_id   uuid not null references public.shop_order(id),
  so_payment_id   uuid references public.so_payment(id),
  kind            text not null check (kind in ('CAPTURE', 'SALE')),
  gateway         text,
  amount          numeric not null check (amount > 0),
  currency_code   text,
  processed_at    timestamptz,
  source          text not null check (source in ('ingest', 'process')),
  recorded_at     timestamptz not null default now()
);
create index if not exists shop_order_transaction_order_idx   on public.shop_order_transaction (shop_order_id);
create index if not exists shop_order_transaction_payment_idx on public.shop_order_transaction (so_payment_id);
comment on table public.shop_order_transaction is 'pay-3a 판정 470: IMS 가 결제로 적은 Shopify 거래(OrderTransaction GID) 표지 — 받기(shop_order_ingest)가 카드 캡처를 so_payment 로 적을 때(source ingest) · 370 ⑦(shop_order_process · aone 받는 순간 PAID)이 적을 때(source process) 남긴다 · 받기는 이전 raw 에 없던 GID 라도 여기 있으면 다시 적지 않는다 · 읽기만(authenticated select) · 쓰기는 두 창구 안에서만 · 지우지 않는다(so_payment 취소는 so_payment_void — 표지는 남는다)';
comment on column public.shop_order_transaction.so_payment_id is '이 거래로 만든 IMS 결제(so_payment.id) · 370 ⑦ 은 거래 여럿이 한 결제(v_o.total)를 가리킬 수 있다';
alter table public.shop_order_transaction enable row level security;
drop policy if exists shop_order_transaction_select on public.shop_order_transaction;
create policy shop_order_transaction_select on public.shop_order_transaction for select to authenticated using (true);
revoke all on public.shop_order_transaction from public, anon, authenticated;
grant select on public.shop_order_transaction to authenticated;

-- ═══ ② shop_order_ingest 재발행 — pay-1a 20261014154103:46 ~ 228 바이트 복사 · 끼운 곳 넷(declare 한 줄 · 카드 거래 블록 + paid_in_shopify 조건 · 경고 덧붙임 두 줄 · 반환 한 줄) ═══
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
  v_tx jsonb;  v_oldt text[];  v_gw text;  v_amt numeric;  v_so_cur text;  v_bill uuid;  v_inv record;  v_allocs jsonb;  v_left numeric;  v_tgt uuid[];  v_prev jsonb;  v_pay jsonb;  v_hand boolean := false;  v_cfail boolean := false;  v_ncard int := 0;  v_cardsum numeric := 0;  v_cgids text[] := '{}';  v_cpids uuid[] := '{}';  v_cards jsonb := '[]'::jsonb;  v_cspec jsonb := '[]'::jsonb;   -- pay-3a 판정 470: 거래 원소 · 이전 raw 의 거래 GID · 게이트웨이 · 금액 · SO 통화 · 청구처 · 인보이스 커서 · 붙이기 · 남은 몫 · 보증금 대상 · 시스템 직원 전 claims · 창구 반환 · 손 표시가 있었나 · 창구 거부가 있었나 · 적은 결제 수 · 합 · GID · 결제 id · 반환 목록 · 결제 원소(정보 · 실패)
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
      -- pay-3a 판정 470: SO 가 생긴 뒤(status created) 새로 보인 카드 거래는 IMS 결제로 적는다 — 새것 = 이전 raw 의 transactions 에 없던 GID(447 · 440 과 같은 모양) 이고 표지 shop_order_transaction 에도 없음 · kind CAPTURE · SALE · status SUCCESS
      --   손 표시(gateway manual(Mark as paid · 실물 #1005) · gift_card · store_credit · 빈 값)와 test 어긋남(거래 test ≠ 오더 test)은 적지 않고 지금처럼 paid_in_shopify 길(v_hand) · 금액 · 통화가 SO 와 어긋나면 card_payment_failed · 창구(so_payment_add)가 거부하면 그 거래만 card_payment_failed(받기는 끝까지 · 되감긴 것은 그 결제뿐)
      --   370 ⑦ 과 같은 창구 · 같은 열쇠(method shopify · reference 오더 이름 · warehouse 오더 위치 · 시스템 직원 shop_system_enter) · 손님은 SO 의 청구처(coalesce(bill_to, customer) — 창구가 그 손님의 인보이스에만 붙이고 그 손님의 오더만 대상으로 받는다) · 금액 = 거래 금액(shopMoney)
      --   붙이기는 창구의 규칙 그대로: 가족의 살아 있는 인보이스(issued · 남은 돈 > 0) 에 번호 순으로 남은 돈까지(allocations) → 남으면 인보이스 없는 열린 가족 SO 의 보증금(target_so_ids) → 그것도 없으면 받아 둔 돈 · 적은 거래는 shop_order_transaction 에 GID 로 남겨 두 번 적지 않는다(⑦ 도 같은 표지를 남긴다) · 적었으면 정보 원소 card_payment_recorded(settled_at 바로 · 열린 경고 아님)
      if v_o.status = 'created' then
        select coalesce(array_agg(t->>'id'), '{}') into v_oldt from jsonb_array_elements(coalesce(case when jsonb_typeof(v_o.raw->'transactions') = 'array' then v_o.raw->'transactions' end, '[]'::jsonb)) t;
        select rc.code, coalesce(s.bill_to_customer_id, s.customer_id) into v_so_cur, v_bill from public.so s left join public.ref_currency rc on rc.id = s.currency_id where s.id = v_o.so_id;
        select coalesce(array_agg(f.id), '{}') into v_fam from public.shop_so_family(v_o.so_id) as f(id);
        for v_tx in select t from jsonb_array_elements(coalesce(case when jsonb_typeof(p_order->'transactions') = 'array' then p_order->'transactions' end, '[]'::jsonb)) t
                     where upper(coalesce(t->>'kind', '')) in ('CAPTURE', 'SALE') and upper(coalesce(t->>'status', '')) = 'SUCCESS' and coalesce(t->>'id', '') ~ '^gid://shopify/OrderTransaction/[0-9]+$'
                       and not (t->>'id' = any(v_oldt)) and not exists (select 1 from public.shop_order_transaction x where x.transaction_gid = t->>'id')
        loop
          v_gw  := lower(trim(coalesce(v_tx->>'gateway', '')));
          v_amt := case when nullif(v_tx->'amountSet'->'shopMoney'->>'amount', '') ~ '^[0-9]+(\.[0-9]+)?$' then (v_tx->'amountSet'->'shopMoney'->>'amount')::numeric end;
          if v_gw in ('', 'manual', 'gift_card', 'store_credit') or coalesce((v_tx->>'test')::boolean, false) is distinct from coalesce((p_order->>'test')::boolean, v_o.is_test) then
            v_hand := true;  continue;                                                                                                     -- 손 표시 · test 어긋남: 돈의 증거가 아니다 → 지금처럼 paid_in_shopify 길
          end if;
          if v_amt is null or v_amt <= 0 or v_amt <> round(v_amt, 2) or upper(coalesce(v_tx->'amountSet'->'shopMoney'->>'currencyCode', '')) <> upper(coalesce(v_so_cur, '')) then
            v_cfail := true;
            v_cspec := v_cspec || jsonb_build_object('code', 'card_payment_failed', 'at', now(), 'transaction_gid', v_tx->>'id', 'amount', v_amt, 'currency', v_tx->'amountSet'->'shopMoney'->>'currencyCode', 'reason', case when v_amt is null or v_amt <= 0 or v_amt <> round(v_amt, 2) then 'amount' else 'currency' end,
                                                     'message', format('Shopify order %s took a card payment of %s %s but the IMS order is in %s — record the payment in IMS by hand (Take a payment)', p_order->>'name', coalesce(v_tx->'amountSet'->'shopMoney'->>'amount', '?'), coalesce(v_tx->'amountSet'->'shopMoney'->>'currencyCode', '?'), coalesce(v_so_cur, '?')));
            continue;
          end if;
          v_left := v_amt;  v_allocs := '[]'::jsonb;  v_tgt := null;  v_prev := null;
          for v_inv in select l.id, l.invoice_number, l.remaining from public.so_invoice_list l where l.so_ids && v_fam and l.status = 'issued' and l.remaining > 0 order by l.invoice_number loop
            exit when v_left <= 0;
            v_allocs := v_allocs || jsonb_build_object('invoice_id', v_inv.id, 'amount', least(v_left, v_inv.remaining));
            v_left := v_left - least(v_left, v_inv.remaining);
          end loop;
          if v_left > 0 then
            select array_agg(s.id order by s.so_number) into v_tgt from public.so s where s.id = any(v_fam) and s.status not in ('fulfilled', 'cancelled') and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id);
          end if;
          begin
            v_prev := public.shop_system_enter();
            v_pay := public.so_payment_add(jsonb_build_object('customer_id', v_bill, 'amount', v_amt, 'method', 'shopify', 'reference', p_order->>'name', 'warehouse_id', v_o.location_id, 'currency_code', v_so_cur,
                                                              'note', 'Shopify ' || v_s.code || ' ' || (p_order->>'name') || ' (card captured in Shopify · ' || v_gw || ' · …' || right(v_tx->>'id', 8) || ')',
                                                              'allocations', v_allocs, 'target_so_ids', coalesce(to_jsonb(v_tgt), '[]'::jsonb)));
            insert into public.shop_order_transaction (transaction_gid, shop_order_id, so_payment_id, kind, gateway, amount, currency_code, processed_at, source)
            values (v_tx->>'id', v_o.id, (v_pay->>'payment_id')::uuid, upper(v_tx->>'kind'), v_tx->>'gateway', v_amt, upper(v_tx->'amountSet'->'shopMoney'->>'currencyCode'), nullif(v_tx->>'processedAt', '')::timestamptz, 'ingest');
            perform public.shop_system_leave(v_prev);
            v_ncard := v_ncard + 1;  v_cardsum := v_cardsum + v_amt;  v_cgids := v_cgids || (v_tx->>'id');  v_cpids := v_cpids || (v_pay->>'payment_id')::uuid;
            v_cards := v_cards || jsonb_build_object('transaction_gid', v_tx->>'id', 'amount', v_amt, 'so_payment_id', v_pay->>'payment_id', 'allocations', v_pay->'allocations', 'targets', v_pay->'targets', 'remaining', v_pay->'remaining');
          exception when others then                                                                                                      -- 창구 거부 · 표지 중복: 이 거래의 결제 · 표지 · claims 만 되감긴다(subtransaction) · 받기는 계속
            v_cfail := true;
            v_cspec := v_cspec || jsonb_build_object('code', 'card_payment_failed', 'at', now(), 'transaction_gid', v_tx->>'id', 'amount', v_amt, 'currency', v_so_cur, 'reason', 'rejected', 'error', left(sqlerrm, 500),
                                                     'message', format('Shopify order %s took a card payment of %s %s but IMS could not record it (%s) — record the payment in IMS by hand (Take a payment)', p_order->>'name', v_amt, v_so_cur, left(sqlerrm, 200)));
          end;
        end loop;
        if v_ncard > 0 then
          v_cspec := v_cspec || jsonb_build_object('code', 'card_payment_recorded', 'at', now(), 'settled_at', now(), 'transaction_gids', to_jsonb(v_cgids), 'amount', v_cardsum, 'so_payment_ids', to_jsonb(v_cpids),
                                                   'message', format('Card payment of %s %s captured in Shopify was recorded in IMS automatically (%s payment(s))', v_cardsum, v_so_cur, v_ncard));
        end if;
      end if;
      if v_paidchg then
        v_pecho := coalesce(v_o.paid_push_at is not null and nullif(p_order->>'updatedAt', '')::timestamptz between v_o.paid_push_at - interval '5 seconds' and v_o.paid_push_at + interval '2 minutes', false);
        if not v_pecho and (v_hand or (v_ncard = 0 and not v_cfail)) then                                                                   -- pay-3a 판정 470: 이번 바뀜이 적은 카드 거래로 다 설명되면(손 표시 없음 · 적은 결제 ≥ 1) 경고 없음 · 창구 거부만 있으면 card_payment_failed 가 대신한다 · 남은 돈은 카드 결제를 붙인 뒤의 값
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
             warnings = warnings || (case when v_moved and not v_auto and not v_echo and not v_pecho and jsonb_array_length(v_spec) = 0 and jsonb_array_length(v_cspec) = 0 and coalesce(array_length(v_absorbed, 1), 0) = 0 then jsonb_build_array(v_warn) else '[]'::jsonb end)   -- ord-1b2: 자동 취소로 끝난 받기는 「손으로 확인」 경고(updated_after_so · cancelled_in_shopify)를 남기지 않는다 · ful-1b: 메아리 · 구체 경고가 있으면 안 붙인다   -- ful-4b5: 흡수된 환불이 있으면(메아리처럼) 일반 경고도 안 붙인다   -- pay-3a: 카드 결제 원소(정보 · 실패)가 있어도 안 붙인다
                                 || (case when not v_auto then v_spec else '[]'::jsonb end)                                                 -- ful-1b 판정 447 · 440: fulfilled_in_shopify · refunded_in_shopify
                                 || v_cspec                                                                                                 -- pay-3a 판정 470: card_payment_recorded(settled) · card_payment_failed — 자동 취소로 끝나도 남긴다(돈은 이미 적혔다)
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
                            'paid_in_shopify', v_paidw,                                                                                                                          -- pay-1a 판정 468
                            'card_payments', v_cards);                                                                                                                           -- pay-3a 판정 470: [{transaction_gid, amount, so_payment_id, allocations, targets, remaining}]
end;
$$;

-- ═══ ③ shop_order_process 재발행 — ful-1b 20261013210000:347 ~ 519 바이트 복사 · 끼운 곳 하나(⑦ 뒤 표지 insert) ═══
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
  execute format('comment on function public.shop_order_ingest(uuid, jsonb) is %L', coalesce(obj_description('public.shop_order_ingest(uuid, jsonb)'::regprocedure, 'pg_proc'), '') || ' · ⭐ pay-3a 판정 470: created 오더의 받기가 이전 raw 와 표지(shop_order_transaction)에 없던 CAPTURE · SALE · SUCCESS 거래를 가른다 — 손 표시(manual · gift_card · store_credit · 빈 값) · test 어긋남은 지금처럼 paid_in_shopify 길 · 금액 · 통화 어긋남 · 창구 거부는 card_payment_failed(그 거래만 · 받기는 끝까지) · 카드는 so_payment_add(method shopify · 시스템 직원 · 손님 = SO 청구처 · 살아 있는 인보이스 남은 돈 → 열린 가족 SO 보증금 → 받아 둔 돈) + 표지 + 정보 원소 card_payment_recorded(settled_at) · 다 설명되면 paid_in_shopify 없음 · 일반 경고 없음 · 반환 card_payments');
  execute format('comment on function public.shop_order_process(uuid) is %L', coalesce(obj_description('public.shop_order_process(uuid)'::regprocedure, 'pg_proc'), '') || ' · ⭐ pay-3a 판정 470: ⑦ 이 적은 결제의 거래(raw 의 CAPTURE · SALE · SUCCESS)를 shop_order_transaction 에 표지로 남긴다(받기가 다시 적지 않게)');
end $$;

-- ═══ 자기 검사 — 설계대로 들어앉았는지(아니면 멈춘다 · 트랜잭션 안이라 되돌아간다) ═══
do $$
declare v_bad text := ''; v_src text;
begin
  if to_regclass('public.shop_order_transaction') is null then v_bad := v_bad || ' table'; end if;
  if (select count(*) from pg_constraint where conrelid = 'public.shop_order_transaction'::regclass and contype = 'c') <> 4 then v_bad := v_bad || ' table(check 4)'; end if;
  if not (select relrowsecurity from pg_class where oid = 'public.shop_order_transaction'::regclass) then v_bad := v_bad || ' table(rls)'; end if;
  if has_table_privilege('authenticated', 'public.shop_order_transaction', 'insert') or has_table_privilege('anon', 'public.shop_order_transaction', 'select') or not has_table_privilege('authenticated', 'public.shop_order_transaction', 'select') then v_bad := v_bad || ' table(acl)'; end if;
  select p.prosrc into v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_order_ingest';
  if v_src not like '%pay-3a 판정 470%' or v_src not like '%''card_payment_recorded''%' or v_src not like '%''card_payment_failed''%' or v_src not like '%shop_order_transaction%' or v_src not like '%''card_payments''%'
     or v_src not like '%pay-1a 판정 468%' or v_src not like '%ful-4b5 판정 466%' or v_src not like '%not v_pecho and (v_hand or (v_ncard = 0 and not v_cfail))%' or v_src not like '%|| v_cspec%' then v_bad := v_bad || ' ingest(body)'; end if;
  select p.prosrc into v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_order_process';
  if v_src not like '%pay-3a 판정 470%' or v_src not like '%shop_order_transaction%' or v_src not like '%ful-1b 판정 454%' then v_bad := v_bad || ' process(body)'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'shop_order' and column_name = 'paid_push_at') <> 1 then v_bad := v_bad || ' paid_push_at(pay-1a)'; end if;
  if to_regprocedure('public.shop_so_family(uuid)') is null or to_regprocedure('public.shop_system_enter()') is null or to_regprocedure('public.shop_system_leave(jsonb)') is null or to_regprocedure('public.so_payment_add(jsonb)') is null then v_bad := v_bad || ' deps'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM471', message = format('STOP - pay-3a did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
