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

-- ════════════════════════════════════════════════════════════════════════════════════════════
-- ord-1a1 — Shopify ④ 오더 받기 · DB 첫 차수: 표 · 시스템 직원 · 받기 · 손님 잇기 · 브랜치 (2026-10-10 밤 · 판정 363 ~ 366 · 430 · 431 · 정본 shopify-integration.md §2 · 원문 so-module §60 예정)
--   ① ims_staff.is_system + 「Shopify」 시스템 직원 한 행(auth 사용자 없음 · 고정 uuid · role manager · perms sales + master · 화면 목록은 is_system 으로 숨긴다 — ord-1c)
--   ② shop_system_enter() · shop_system_leave(): 시스템 창구 안에서 request.jwt.claims 를 시스템 직원으로 바꿔 **기존 창구(customer_create · 뒤 차수의 so_create …)를 그대로 부른다** — 같은 계산이 두 곳에 생기지 않는다(asung-so 한 창구 원칙)
--   ③ 표 shop_customer(스토어 × Shopify 손님 GID → IMS 손님 · 판정 364 ① · 431 ④) · shop_order(받은 오더 원문 · GID 로 한 번만 · 판정 363 · 431 ①) · shop_order_line(줄)
--   ④ shop_order_ingest(store, order jsonb) — GID upsert · 줄 풀기 · 이미 SO 가 있으면 SO 무접촉 + 경고(판정 372 「웹 오더는 고치지 않는다」) · 끝에 prepare
--   ⑤ shop_order_prepare(shop_order) — 손님(364 네 단계 · 새 손님은 customer_create 그대로) · 줄 대조(366) · 브랜치(430: 배송지 주 AB · BC · SK → Edmonton · 없으면 손님 기본 · 짝이 하나뿐인 스토어(aone)는 그 하나) → received(깨끗) | needs_review(까닭 목록)
--   ⑥ shop_order_resolve_customer(shop_order, customer, commit) — 직원 창구(sales) · 고른 손님을 잇고(linked_how staff) 다시 prepare
--   ⑦ 뷰 shop_order_list(security_invoker · ord-1c)
--   다음 차수 ord-1a2: shop_order_process(SO 만들기 · 줄 할인 출처 shopify · 할인 어긋남 · 세금 · 운임 · 결제 · 자동 확정) · shop_order_cancelled(372) · 줄 고르기 resolve · discount_source CHECK 에 shopify
--   무접촉: so_* · customer_* 창구 전부(prosrc md5 전후 같음) · EF(ord-1b) · 화면(ord-1c)
-- ════════════════════════════════════════════════════════════════════════════════════════════

-- ═══ 1) 시스템 직원 — ims_staff.is_system · 「Shopify」 한 행 ═══
alter table public.ims_staff add column if not exists is_system boolean not null default false;
comment on column public.ims_staff.is_system is 'ord-1a1: 사람이 아닌 직원(Shopify 받기 등) — 로그인 없음(auth_user_id 는 고정 uuid · auth.users 에 없다) · 시스템 창구가 shop_system_enter() 로 이 직원이 되어 기존 창구를 부른다 · 화면 목록은 is_system 을 숨긴다(ord-1c) · 사람이 고치지 않는다';
insert into public.ims_staff (id, auth_user_id, email, name, role, perms, is_active, note, is_system)
values ('00000000-0000-4000-a000-000000000001', '00000000-0000-4000-a000-000000000002', 'shopify@system.asung-ims.invalid', 'Shopify', 'manager', '["sales", "master"]'::jsonb, true,
        'ord-1a1 시스템 직원 — Shopify 에서 받은 오더 · 손님을 만드는 주체 · 로그인 불가(auth 사용자 없음) · perms sales(오더) · master(스토어 티어로 손님 만들기 · customer_create 의 돈 칸)', true)
on conflict (id) do nothing;

-- ═══ 2) 시스템이 되기 · 돌아오기 — 같은 트랜잭션 안에서만(set_config local) ═══
create function public.shop_system_enter() returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_auth uuid;
  v_prev jsonb;
begin
  select s.auth_user_id into v_auth from public.ims_staff s where s.is_system and s.is_active order by s.created_at limit 1;
  if v_auth is null then raise exception 'No active system staff (ims_staff.is_system) — nothing was saved'; end if;
  v_prev := jsonb_build_object('claims', coalesce(current_setting('request.jwt.claims', true), ''), 'sub', coalesce(current_setting('request.jwt.claim.sub', true), ''));
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_auth, 'role', 'service_role', 'ims_system', true)::text, true);   -- auth.uid() 가 시스템 직원을 가리킨다 · 트랜잭션 끝까지(local)
  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  return v_prev;
end;
$$;
create function public.shop_system_leave(p_prev jsonb) returns void
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
begin
  perform set_config('request.jwt.claims', coalesce(p_prev->>'claims', ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(p_prev->>'sub', ''), true);
end;
$$;
revoke all on function public.shop_system_enter() from public, anon, authenticated;
revoke all on function public.shop_system_leave(jsonb) from public, anon, authenticated;
comment on function public.shop_system_enter() is 'ord-1a1 판정 431 ②: 시스템 창구 안에서만 — request.jwt.claims 를 시스템 직원(ims_staff.is_system)으로 바꿔 기존 창구(customer_create · so_create …)를 그대로 부른다 · 돌려주는 값은 shop_system_leave 에 넘길 이전 값 · service_role 만 실행(authenticated 42501)';
comment on function public.shop_system_leave(jsonb) is 'ord-1a1: shop_system_enter 가 돌려준 이전 claims 로 되돌린다(같은 트랜잭션 · 예외가 나면 트랜잭션이 끝나며 저절로 사라진다)';

-- ═══ 3) 표 셋 ═══
-- 3-a shop_customer — 스토어 × Shopify 손님 GID → IMS 손님(판정 364 ① · 431 ④) · 스토어마다 GID 가 다르다
create table public.shop_customer (
  id                    uuid primary key default gen_random_uuid(),
  store_id              uuid not null references public.shop_store (id) on delete no action,
  shopify_customer_gid  text not null,
  customer_id           uuid not null references public.customer (id) on delete no action,
  linked_how            text not null,                                                      -- account(이미 이어짐) · email(이메일 하나) · staff(직원이 고름) · created(새 손님)
  linked_by             uuid references public.ims_staff (id) on delete no action,
  linked_at             timestamptz not null default now(),
  note                  text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  updated_by            uuid references public.ims_staff (id) on delete no action,
  constraint shop_customer_store_gid_uk unique (store_id, shopify_customer_gid),
  constraint shop_customer_gid_ck       check (shopify_customer_gid ~ '^gid://shopify/Customer/[0-9]+$'),
  constraint shop_customer_how_ck       check (linked_how in ('account', 'email', 'staff', 'created'))
);
create index shop_customer_customer_id_idx on public.shop_customer (customer_id);
create index shop_customer_linked_by_idx   on public.shop_customer (linked_by);
create index shop_customer_updated_by_idx  on public.shop_customer (updated_by);
create trigger shop_customer_touch before update on public.shop_customer for each row execute function public.ims_touch();
comment on table public.shop_customer is 'ord-1a1 판정 364 · 431 ④: 스토어 × Shopify 손님 GID → IMS 손님 잇기 — linked_how account | email | staff | created · 한 IMS 손님이 두 스토어에 있을 수 있어 customer 칸이 아니라 표 · 쓰기는 시스템 창구(prepare) · 직원 창구(resolve_customer)';

-- 3-b shop_order — 받은 오더 원문(판정 363 · 431 ①) · Shopify 오더 GID 로 한 번만
create table public.shop_order (
  id                    uuid primary key default gen_random_uuid(),
  store_id              uuid not null references public.shop_store (id) on delete no action,
  shopify_order_gid     text not null,
  name                  text not null,                                                      -- Shopify 오더 이름(AS-6950 · #1001)
  shopify_created_at    timestamptz,
  shopify_updated_at    timestamptz,
  shopify_cancelled_at  timestamptz,
  is_test               boolean not null default false,
  financial_status      text,                                                               -- displayFinancialStatus(PENDING · PAID …)
  source_name           text,
  email                 text,
  shopify_customer_gid  text,
  ship_province_code    text,
  ship_country_code     text,
  currency_code         text,
  subtotal              numeric,
  total_discounts       numeric,
  total_shipping        numeric,
  total_tax             numeric,
  total                 numeric,
  freight_amount        numeric,                                                            -- 열어 둔 운임(asung.ca) — 담기만 · SO 운임 줄은 ord-1a2(aone 만 · 판정 369)
  freight_title         text,
  raw                   jsonb not null,                                                     -- GraphQL order 원문(ord-0-shopify.graphql ①)
  status                text not null default 'received',
  reasons               jsonb not null default '[]'::jsonb,                                 -- needs_review 까닭 [{code, message, …}]
  warnings              jsonb not null default '[]'::jsonb,                                 -- 경고 [{code, message, at}] — updated_after_so · cancelled_in_shopify · (1a2) discount_mismatch · tax_mismatch …
  customer_id           uuid references public.customer (id) on delete no action,
  location_id           uuid references public.ref_warehouse (id) on delete no action,
  so_id                 uuid references public.so (id) on delete no action,
  received_at           timestamptz not null default now(),
  processed_at          timestamptz,
  error                 text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  updated_by            uuid references public.ims_staff (id) on delete no action,
  constraint shop_order_gid_uk     unique (shopify_order_gid),
  constraint shop_order_gid_ck     check (shopify_order_gid ~ '^gid://shopify/Order/[0-9]+$'),
  constraint shop_order_status_ck  check (status in ('received', 'needs_review', 'created', 'cancelled', 'error')),
  constraint shop_order_so_ck      check ((status = 'created') = (so_id is not null))
);
create index shop_order_store_status_idx on public.shop_order (store_id, status, received_at);
create index shop_order_customer_id_idx  on public.shop_order (customer_id);
create index shop_order_location_id_idx  on public.shop_order (location_id);
create index shop_order_so_id_idx        on public.shop_order (so_id);
create index shop_order_updated_by_idx   on public.shop_order (updated_by);
create trigger shop_order_touch before update on public.shop_order for each row execute function public.ims_touch();
comment on table public.shop_order is 'ord-1a1 판정 363 · 431 ①: Shopify 에서 받은 오더 원문 — GID 로 한 번만(unique) · status received(받음 · 깨끗하면 1a2 가 SO 로) | needs_review(까닭 reasons) | created(so_id) | cancelled | error · 이미 created 면 받기는 raw 만 갱신하고 SO 무접촉 + warnings(판정 372) · 운임은 담기만(freight_*) · 쓰기는 시스템 창구(ingest · prepare) · 직원 창구(resolve_*)';

-- 3-c shop_order_line — 오더 줄(정가 · 줄 할인 · 할인 뒤 단가 · SKU 대조)
create table public.shop_order_line (
  id               uuid primary key default gen_random_uuid(),
  shop_order_id    uuid not null references public.shop_order (id) on delete cascade,      -- 문서 → 소유 줄(거래 표 규약)
  line_gid         text not null,
  line_no          int not null,
  sku              text,
  name             text,
  quantity         numeric not null,
  list_price       numeric,                                                                 -- originalUnitPriceSet(정가)
  discount_amount  numeric,                                                                 -- totalDiscountSet(그 줄의 할인 합)
  unit_price       numeric,                                                                 -- discountedUnitPriceAfterAllDiscountsSet(할인 뒤 단가)
  product_id       uuid references public.product (id) on delete no action,
  match            text,                                                                    -- ok · not_found · inactive · not_sellable · null(아직 대조 안 함)
  so_line_id       uuid references public.so_line (id) on delete no action,
  constraint shop_order_line_uk        unique (shop_order_id, line_gid),
  constraint shop_order_line_no_uk     unique (shop_order_id, line_no),
  constraint shop_order_line_qty_ck    check (quantity > 0),
  constraint shop_order_line_match_ck  check (match is null or match in ('ok', 'not_found', 'inactive', 'not_sellable'))
);
create index shop_order_line_product_id_idx on public.shop_order_line (product_id);
create index shop_order_line_so_line_id_idx on public.shop_order_line (so_line_id);
comment on table public.shop_order_line is 'ord-1a1 판정 366 · 431 ③: 받은 오더의 줄 — Shopify 정가(list_price) · 줄 할인(discount_amount) · 할인 뒤 단가(unit_price)를 그대로 · product_id · match 는 prepare 가 SKU 글자 그대로 대조(ok | not_found | inactive | not_sellable) · so_line_id 는 1a2';

do $$ declare t text; begin
  foreach t in array array['shop_customer', 'shop_order', 'shop_order_line'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_select', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- ═══ 4) 브랜치 한 곳 — 판정 430(배송지 주 먼저 · 없으면 손님 기본) · 427(짝이 하나뿐인 스토어 = 그 하나 · aone Toronto) ═══
create function public.shop_order_pick_location(p_store_id uuid, p_province_code text, p_customer_id uuid) returns uuid
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_edm uuid;
  v_tor uuid;
  v_n   int;
  v_cust uuid;
begin
  select count(*) into v_n from public.shop_location l where l.store_id = p_store_id and l.is_active;
  if v_n = 0 then return null; end if;
  select l.warehouse_id into v_edm from public.shop_location l join public.ref_warehouse w on w.id = l.warehouse_id
   where l.store_id = p_store_id and l.is_active and w.name ilike '%edmonton%' order by w.name limit 1;                                -- 이름으로 Edmonton 짝을 찾는다(ref_warehouse 에 지역 칸이 없다 · 이견)
  select l.warehouse_id into v_tor from public.shop_location l join public.ref_warehouse w on w.id = l.warehouse_id
   where l.store_id = p_store_id and l.is_active and l.warehouse_id is distinct from v_edm order by w.is_default desc, w.name limit 1;
  if v_edm is null then return v_tor; end if;                                                                                            -- 짝 하나(aone) → 늘 그 창고(판정 427)
  if v_tor is null then return v_edm; end if;
  if upper(trim(coalesce(p_province_code, ''))) in ('AB', 'BC', 'SK') then return v_edm; end if;                                          -- 판정 430
  if nullif(trim(p_province_code), '') is not null then return v_tor; end if;
  select c.default_location_id into v_cust from public.customer c where c.id = p_customer_id;                                            -- 주가 없을 때만 손님 기본 · 그 스토어의 짝이어야 한다
  if v_cust is not null and v_cust in (v_edm, v_tor) then return v_cust; end if;
  return v_tor;
end;
$$;
revoke all on function public.shop_order_pick_location(uuid, text, uuid) from public, anon, authenticated;
comment on function public.shop_order_pick_location(uuid, text, uuid) is 'ord-1a1 판정 430 · 427: 웹 오더의 창고 — 스토어의 활성 위치 짝이 하나면 그것(aone = Toronto) · 둘이면 배송지 provinceCode AB · BC · SK → Edmonton 짝 · 다른 주 → Toronto 짝 · 주가 없으면 손님 기본 창고(그 스토어의 짝일 때만) · 그래도 없으면 Toronto 짝 · 재고로 고르지 않는다(365)';

-- ═══ 5) 받기 — shop_order_ingest(store, order jsonb) · GID upsert · 줄 풀기 · 끝에 prepare ═══
create function public.shop_order_ingest(p_store_id uuid, p_order jsonb) returns jsonb
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

  select * into v_o from public.shop_order o where o.shopify_order_gid = v_gid for update;
  if v_o.id is null then
    insert into public.shop_order (store_id, shopify_order_gid, name, shopify_created_at, shopify_updated_at, shopify_cancelled_at, is_test, financial_status, source_name, email, shopify_customer_gid,
                                   ship_province_code, ship_country_code, currency_code, subtotal, total_discounts, total_shipping, total_tax, total, freight_amount, freight_title, raw, status)
    values (v_s.id, v_gid, p_order->>'name', nullif(p_order->>'createdAt', '')::timestamptz, nullif(p_order->>'updatedAt', '')::timestamptz, v_cancel, coalesce((p_order->>'test')::boolean, false),
            p_order->>'displayFinancialStatus', p_order->>'sourceName', nullif(lower(trim(coalesce(p_order->>'email', p_order->'customer'->'defaultEmailAddress'->>'emailAddress'))), ''), nullif(p_order->'customer'->>'id', ''),
            nullif(upper(trim(v_ship->>'provinceCode')), ''), nullif(upper(trim(v_ship->>'countryCodeV2')), ''), p_order->>'currencyCode',
            (p_order->'subtotalPriceSet'->'shopMoney'->>'amount')::numeric, (p_order->'totalDiscountsSet'->'shopMoney'->>'amount')::numeric, (p_order->'totalShippingPriceSet'->'shopMoney'->>'amount')::numeric,
            (p_order->'totalTaxSet'->'shopMoney'->>'amount')::numeric, (p_order->'totalPriceSet'->'shopMoney'->>'amount')::numeric,
            (v_fl->'discountedPriceSet'->'shopMoney'->>'amount')::numeric, v_fl->>'title', p_order, 'received')
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
             freight_amount = (v_fl->'discountedPriceSet'->'shopMoney'->>'amount')::numeric, freight_title = v_fl->>'title', raw = p_order, status = 'received', reasons = '[]'::jsonb, error = null
       where id = v_o.id returning * into v_o;
      delete from public.shop_order_line where shop_order_id = v_o.id;                                                                          -- 줄은 다시 푼다(SO 가 없으니 자유)
      v_action := 'updated';
    else                                                                                                                                       -- created · cancelled · error: 원문만 갱신 · SO · 줄 무접촉(판정 372)
      v_warn := jsonb_build_object('code', case when v_o.status = 'created' then 'updated_after_so' else 'updated_after_' || v_o.status end, 'at', now(),
                                   'message', format('Shopify order %s changed after IMS %s it (Shopify updatedAt %s) — check the Shopify order and the IMS order by hand', p_order->>'name', v_o.status, p_order->>'updatedAt'));
      update public.shop_order set shopify_updated_at = nullif(p_order->>'updatedAt', '')::timestamptz, shopify_cancelled_at = v_cancel, financial_status = p_order->>'displayFinancialStatus', raw = p_order,
             warnings = warnings || (case when nullif(p_order->>'updatedAt', '')::timestamptz is distinct from v_o.shopify_updated_at then jsonb_build_array(v_warn) else '[]'::jsonb end)
                                 || (case when v_cancel is not null and v_o.shopify_cancelled_at is null
                                          then jsonb_build_array(jsonb_build_object('code', 'cancelled_in_shopify', 'at', now(), 'message', format('Shopify order %s was cancelled in Shopify (%s) — the IMS order is untouched until shop_order_cancelled runs (ord-1a2)', p_order->>'name', v_cancel)))
                                          else '[]'::jsonb end)
       where id = v_o.id returning * into v_o;
      v_action := 'updated_after_' || v_o.status;
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
    select * into v_o from public.shop_order o where o.id = v_o.id;
  end if;

  return jsonb_build_object('shop_order_id', v_o.id, 'action', v_action, 'status', v_o.status, 'name', v_o.name, 'lines', v_n,
                            'customer_id', v_o.customer_id, 'location_id', v_o.location_id, 'reasons', v_o.reasons, 'warnings', v_o.warnings, 'prepare', v_prep);
end;
$$;
revoke all on function public.shop_order_ingest(uuid, jsonb) from public, anon, authenticated;
comment on function public.shop_order_ingest(uuid, jsonb) is 'ord-1a1 판정 363 · 372 · 431 ①: 받은 오더 넣기 한 곳(EF ord-1b 가 service_role 로 · 웹훅 · 주기 확인 둘 다) — p_order = GraphQL order 원문(ord-0-shopify.graphql ① · lineItems.nodes · shippingLines.nodes) · GID 로 upsert · received | needs_review 면 원문 · 줄을 다시 풀고 prepare · created | cancelled | error 면 원문만 갱신하고 SO · 줄 무접촉 + warnings(updated_after_so · cancelled_in_shopify) · 돌려주는 값 {shop_order_id, action inserted | updated | updated_after_<status>, status, lines, customer_id, location_id, reasons, warnings, prepare}';

-- ═══ 6) 준비 — 손님(364) · 줄 대조(366) · 브랜치(430) → received | needs_review ═══
create function public.shop_order_prepare(p_shop_order_id uuid) returns jsonb
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
      v_loc := public.shop_order_pick_location(v_o.store_id, v_o.ship_province_code, null);
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

  -- ③ 브랜치(판정 430 · 427)
  v_loc := public.shop_order_pick_location(v_o.store_id, v_o.ship_province_code, v_cust);
  if v_loc is null then
    v_reasons := v_reasons || jsonb_build_object('code', 'warehouse_unknown', 'message', format('Store %s has no active location pair — pair a warehouse in Settings → Shopify Stores', v_s.code));
  end if;

  update public.shop_order set customer_id = v_cust, location_id = v_loc, reasons = v_reasons,
         status = case when jsonb_array_length(v_reasons) = 0 then 'received' else 'needs_review' end
   where id = v_o.id returning * into v_o;
  return jsonb_build_object('shop_order_id', v_o.id, 'status', v_o.status, 'customer_id', v_cust, 'linked_how', v_how, 'location_id', v_loc, 'bad_lines', v_bad, 'reasons', v_reasons);
end;
$$;
revoke all on function public.shop_order_prepare(uuid) from public, anon, authenticated;
comment on function public.shop_order_prepare(uuid) is 'ord-1a1 판정 364 · 366 · 430 · 431: 받은 오더를 SO 로 만들 수 있게 준비 — 손님(계정 잇기 → 이메일 하나 → 여럿 needs_review email_multiple → 없음 새 손님 customer_create(시스템 직원 · 스토어 티어 · 주소 · 연락처) + shop_customer 잇기) · 줄 SKU 대조(product_id · match · 못 찾음 · 꺼짐 · 판매 안 함 → needs_review) · 창고(shop_order_pick_location) → status received(깨끗 · 1a2 process 가 SO 로) | needs_review(reasons) · 몇 번 불러도 같은 결과 · created 뒤에는 건너뜀';

-- ═══ 7) 직원 창구 — 확인 필요(손님 여럿) 풀기 ═══
create function public.shop_order_resolve_customer(p_shop_order_id uuid, p_customer_id uuid, p_commit boolean default false) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_o     public.shop_order%rowtype;
  c       public.customer%rowtype;
  v_res   jsonb;
begin
  perform public.ims_require_write('sales', 'saved');                                                                                   -- ⭐ 유일한 문 — 첫 줄
  v_staff := public.so_current_staff();
  select * into v_o from public.shop_order o where o.id = p_shop_order_id for update;
  if v_o.id is null then raise exception 'Shop order not found — nothing was saved'; end if;
  if v_o.status not in ('received', 'needs_review') then raise exception 'Shop order % is already % — nothing was saved', v_o.name, v_o.status; end if;
  select * into c from public.customer x where x.id = p_customer_id;
  if c.id is null then raise exception 'Customer not found — nothing was saved'; end if;
  if not c.is_active then raise exception 'Customer % is inactive — reactivate it first — nothing was saved', c.name; end if;
  if not p_commit then
    return jsonb_build_object('committed', false, 'shop_order_id', v_o.id, 'name', v_o.name, 'customer_id', c.id, 'customer_name', c.name,
                              'will_link', v_o.shopify_customer_gid is not null, 'shopify_customer_gid', v_o.shopify_customer_gid, 'current_reasons', v_o.reasons);
  end if;
  if v_o.shopify_customer_gid is not null then
    insert into public.shop_customer (store_id, shopify_customer_gid, customer_id, linked_how, linked_by, updated_by)
    values (v_o.store_id, v_o.shopify_customer_gid, c.id, 'staff', v_staff, v_staff)
    on conflict (store_id, shopify_customer_gid) do update set customer_id = excluded.customer_id, linked_how = 'staff', linked_by = excluded.linked_by, linked_at = now();
  end if;
  update public.shop_order set customer_id = c.id where id = v_o.id;
  v_res := public.shop_order_prepare(v_o.id);
  return jsonb_build_object('committed', true, 'shop_order_id', v_o.id, 'name', v_o.name, 'customer_id', c.id, 'customer_name', c.name, 'linked', v_o.shopify_customer_gid is not null, 'prepare', v_res);
end;
$$;
revoke all on function public.shop_order_resolve_customer(uuid, uuid, boolean) from public, anon;
grant execute on function public.shop_order_resolve_customer(uuid, uuid, boolean) to authenticated;
comment on function public.shop_order_resolve_customer(uuid, uuid, boolean) is 'ord-1a1 판정 364 ③: 직원이 받은 오더의 손님을 고른다(이메일 여럿 · 손님 모름) — definer · 첫 줄 ims_require_write(sales) · 두 번 부르기(p_commit false = 미리 보기) · 계정 GID 가 있으면 shop_customer 에 잇는다(linked_how staff · 있으면 바꾼다) → 다시 prepare → received | needs_review';

-- ═══ 8) 뷰 — 화면 ord-1c ═══
create view public.shop_order_list
  with (security_invoker = true) as
  select o.id, o.store_id, s.code as store_code, o.shopify_order_gid, o.name, o.status, o.shopify_created_at, o.shopify_updated_at, o.shopify_cancelled_at, o.is_test,
         o.financial_status, o.source_name, o.email, o.shopify_customer_gid, o.ship_province_code, o.ship_country_code, o.currency_code,
         o.subtotal, o.total_discounts, o.total_shipping, o.total_tax, o.total, o.freight_amount, o.freight_title,
         o.customer_id, c.name as customer_name, o.location_id, w.name as location_name, o.so_id, so.so_number, so.status as so_status,
         o.reasons, jsonb_array_length(o.reasons) as reason_count, o.warnings, jsonb_array_length(o.warnings) as warning_count,
         (select count(*) from public.shop_order_line l where l.shop_order_id = o.id) as line_count,
         (select count(*) from public.shop_order_line l where l.shop_order_id = o.id and l.match is distinct from 'ok') as unmatched_count,
         o.received_at, o.processed_at, o.error, o.updated_at
    from public.shop_order o
    join public.shop_store s on s.id = o.store_id
    left join public.customer c on c.id = o.customer_id
    left join public.ref_warehouse w on w.id = o.location_id
    left join public.so so on so.id = o.so_id;
revoke all on public.shop_order_list from anon, authenticated;
grant select on public.shop_order_list to authenticated;
comment on view public.shop_order_list is 'ord-1a1: 받은 오더 목록(화면 ord-1c) — 스토어 · 상태 · 손님 · 창고 · SO 번호 · 까닭(reasons · reason_count) · 경고(warnings · warning_count) · 줄 수 · 안 맞는 줄 수 · security_invoker · select 만';

-- ═══ 끝 — 자기 점검 ═══
do $$ begin
  if (select count(*) from public.ims_staff where is_system and is_active and role = 'manager' and perms ? 'sales' and perms ? 'master') <> 1 then raise exception 'ord-1a1: system staff row missing'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('shop_system_enter', 'shop_system_leave', 'shop_order_pick_location', 'shop_order_ingest', 'shop_order_prepare', 'shop_order_resolve_customer')) <> 6 then raise exception 'ord-1a1: functions missing'; end if;
  if (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relname in ('shop_customer', 'shop_order', 'shop_order_line') and c.relrowsecurity) <> 3 then raise exception 'ord-1a1: tables / rls missing'; end if;
  if has_function_privilege('authenticated', 'public.shop_order_ingest(uuid, jsonb)', 'execute') or has_function_privilege('authenticated', 'public.shop_system_enter()', 'execute') then raise exception 'ord-1a1: system functions must not be executable by authenticated'; end if;
  if to_regclass('public.shop_order_list') is null then raise exception 'ord-1a1: view missing'; end if;
end $$;
